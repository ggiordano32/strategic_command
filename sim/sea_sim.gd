extends RefCounted
## Real-time sea battle (N3a; docs/DESIGN.md "Sea battles (as built, N3a)").
##
## A sibling of BattleSim, not a mode inside it: a sea battle has a handful
## of ships and no soldiers, so it shares none of BattleSim's per-man
## arrays, maps or engines; keeping it apart leaves every land battle (and
## Rome) byte-identical. It keeps the same discipline and the interface the
## lockstep layer needs (sim/lockstep.gd picks it for a scenario with
## "sea"): integer / fixed-point maths only (sim/fixed_math.gd: 1 m = 1024
## units, angles 0..1023 with 0 along +x and growing toward +y), the sim's
## own xorshift RNG, fixed iteration order (ship index), orders queued with
## (tick, player, seq), state_hash() over every state array, snapshot() /
## restore() of every script variable. A tick is 0.1 s (lockstep runs one
## per frame at 1x).
##
## Ships (index s, the scenario's "units" in order) are pieces with a
## position, a heading (x16 for smooth turns), a speed, a sail setting
## (stop / battle / full), hull, rigging and crew, troops aboard (they fight
## boardings), two broadsides (port 0, starboard 1) each loaded with a shot
## kind and reloading, a mode (hold course, sail to a point, engage a
## target, board a target, flee, hold a heading) and a state (u_state:
## fighting, struck, sunk, taken, fled).
##
## The wind blows from w_from (an angle) at w_str (0-100); it shifts a
## little every WIND_EVERY ticks (seeded, within WIND_SPAN of the start).
## Points of sail (_drive): no drive inside the no-go zone (the row's
## "irons", off the wind), then rising to the best on a broad reach;
## rowed ships ignore the wind. The navigator (_course) beats to windward
## in two tacks (laylines) and turns through the wind when the ship has
## the way for it ("tack" % of its top speed), else wears round; a ship
## caught in irons without way falls off. Land and shoals (a grid from
## "land": open sea, an island, a coast on the sides the campaign cell has
## land) stop ships; deep-draught ships run aground on shoals.
##
## Broadsides: each side fires all its working guns at once when loaded and
## a target lies in its arc (ARC) and in range of the loaded shot: round
## shot breaks the hull (and kills by splinters), chain the rigging (speed),
## grape the crew (short range). Each gun hits at a % by range, target
## size and the gun crew's quality; raking (from ahead or astern of the
## target) kills 1.5-2 x the men. Reload time grows when the crew is too
## thin to work the guns. Round shot can start a fire; a fire the crew does
## not put out can reach the magazine (the ship blows up and scorches her
## neighbours). Hull 0: she sinks.
##
## Boarding: a ship ordered to board sails alongside; close and at a low
## relative speed she grapples, both stop, and the crews (with the troops
## aboard, the boarders' row quality, the defenders' deck bonus) fight it
## out over a few seconds: the defenders are taken, or the boarders are
## thrown back (BOARD_MAX_TICKS at most). N3b hook: with the scenario's
## "deck" 1 the sim does not resolve a boarding; deck_request() lists the
## grappled pairs and their crews (the data for a deck melee in the
## soldier sim) and O_DECK applies its result.
##
## Morale: hits, losses and raking lower it, quiet time restores it; a ship
## strikes her colours at 0, or when her crew or hull is nearly gone with an
## enemy near. A struck ship stops and is out of the fight; it is taken by
## the winner when the battle is decided. The battle is decided when a side
## has no ship fighting (sunk, struck, taken or fled off the map edge), or
## at the time limit by the fighting power left (ties: side 1, the
## defender).
##
## Battle AI (sides with ai_sides 1; every ship thinks every 10 ticks,
## staggered): flee to the far edge when beaten, else pick the nearest
## weakest enemy; board (coming up under her stern) when its boarding
## strength, with friends already boarding her, is well above the
## target's; else engage: beat up to windward of it when far (the weather
## gauge), then keep the broadside on at the shot's range, presenting the
## loaded side, rake when the geometry offers it; grape close, chain to
## cripple (boarders), round otherwise; flee when beaten or hopelessly
## outgunned.

const FM := preload("res://sim/fixed_math.gd")
const ST := preload("res://sim/sea_types.gd")

const U := 1024                  # units per metre
const TIME_LIMIT := 9000         # ticks (15 minutes)
const END_TICKS := 60            # after the decision, then `ended`
const FIELD_W := 2400            # metres
const FIELD_H := 1600
const CELL_M := 20               # land grid cell

# Ship states (u_state; 0 is what the lockstep layer calls U_READY).
const S_SAIL := 0
const S_STRUCK := 1
const S_SUNK := 2
const S_TAKEN := 3
const S_FLED := 4
const STATE_NAMES := ["fighting", "struck", "sunk", "taken", "escaped"]

# Modes.
const M_FREE := 0
const M_GOTO := 1
const M_ENGAGE := 2
const M_BOARD := 3
const M_FLEE := 4
const M_HEAD := 5

# Orders (types inside the lockstep's sim-order range, avoiding its special
# 8 withdraw-all, 13 ready and 20 works; 7 is what withdraw-all queues).
const O_SAIL := 1       # unit, x, y (metres): sail there (the course is planned by the wind)
const O_TARGET := 2     # unit, target: engage that ship (broadside on, focus fire)
const O_HOLD := 3       # unit: drop the order, hold the course
const O_SAILS := 4      # unit, on: 0 stop (heave to), 1 battle sail, 2 full sail
const O_FIRE := 5       # unit, on: fire at will (1) or only at the ordered target (0)
const O_SHOT := 6       # unit, on: ST.SHOT_* loaded at the next reload
const O_FLEE := 7       # unit: run for the map edge away from the enemy
const O_BOARD := 9      # unit, target: lay her alongside and board
const O_HEAD := 10      # unit, facing (angle 0..1023): hold that heading
const O_DECK := 11      # unit (boarder), target, on (1 boarders won), a, b (crews left): N3b deck result
const O_LAST := 11

const ARC := 120                 # half-width of a broadside's arc (angle units, ~42 deg)
const SAIL_PCT := [0, 75, 100]
const BOARD_MAX_TICKS := 600
const DECK_BONUS_PCT := 125      # defenders on their own deck
const FIRE_PM := 5               # per mille per round-shot hit: a fire starts
const MAGAZINE_PM := 15          # per mille a second while burning: she blows up
const EXTINGUISH_PCT := 14       # % a second at full crew: the fire is out
const BLAST_M := 70
const WIND_EVERY := 300
const WIND_SPAN := 100           # angle units either side of the start wind (~35 deg)
const EDGE_M := 90               # ships keep this far from the edge unless fleeing
const RANGE_PREF := [165, 140, 70]   # metres: the range a ship engages at, by shot

# ---- lockstep interface (duck-typed like BattleSim) ----
var n_units := 0
var u_side := PackedInt32Array()
var u_state := PackedInt32Array()
var u_hand := PackedInt32Array()     # always -1 (no war dogs at sea)
var u_pack := PackedInt32Array()
var u_char := PackedInt32Array()
var ch_on := 0
var dep_on := 0
var dep_need := 0
var ai_sides := PackedInt32Array([0, 1])
var pending_orders: Array = []
var _order_seq := 0

# ---- hashed state ----
var tick := 0
var rng_state := 1
var winner := -1
var decided_tick := -1
var ended := 0
var time_limit := TIME_LIMIT
var field_w := FIELD_W
var field_h := FIELD_H
var seed_value := 1
var w_base := 0
var w_from := 0
var w_goal := 0
var w_str := 80
var deck_on := 0
var ter_hash := 0
var s_type := PackedInt32Array()
var s_x := PackedInt32Array()
var s_y := PackedInt32Array()
var s_h16 := PackedInt32Array()
var s_want := PackedInt32Array()
var s_tdir := PackedInt32Array()
var s_spd := PackedInt32Array()
var s_sail := PackedInt32Array()
var s_hull := PackedInt32Array()
var s_hull0 := PackedInt32Array()
var s_crew := PackedInt32Array()
var s_crew0 := PackedInt32Array()
var s_rig := PackedInt32Array()
var s_rig0 := PackedInt32Array()
var s_troops := PackedInt32Array()
var s_q := PackedInt32Array()
var s_bq := PackedInt32Array()
var s_mor := PackedInt32Array()
var s_mode := PackedInt32Array()
var s_tx := PackedInt32Array()
var s_ty := PackedInt32Array()
var s_tgt := PackedInt32Array()
var s_fire := PackedInt32Array()
var s_shot := PackedInt32Array()
var s_ld := PackedInt32Array()       # 2 per ship: the shot loaded (port, starboard)
var s_rl := PackedInt32Array()       # 2 per ship: reload work left (ticks x 1000)
var s_tack := PackedInt32Array()
var s_grap := PackedInt32Array()
var s_boarder := PackedInt32Array()
var s_bd_t := PackedInt32Array()
var s_bd_wait := PackedInt32Array()
var s_by := PackedInt32Array()
var s_burn := PackedInt32Array()
var s_ground := PackedInt32Array()
var s_hit_t := PackedInt32Array()
var s_end_t := PackedInt32Array()
var s_kills := PackedInt32Array()
var s_blown := PackedInt32Array()
var s_flee_x := PackedInt32Array()
var s_flee_y := PackedInt32Array()

# ---- rebuilt by setup() (not in snapshots) ----
var g_w := 0
var g_h := 0
var g := PackedByteArray()           # 0 sea, 1 shoal, 2 land

# ---- view events and statistics (snapshotted, not hashed) ----
const EV_CAP := 256
const EV_BROADSIDE := 0   # a: ship, b: side (0 port / 1 starboard), c: target, d: hits, e: shot
const EV_BLAST := 1       # a: ship
const EV_GRAPPLE := 2     # a: boarder, c: target
const EV_TAKEN := 3       # a: captor (-1 struck at the end), c: prize
const EV_STRIKE := 4      # a: ship
const EV_SINK := 5        # a: ship
const EV_REPELLED := 6    # a: boarder, c: target
const EV_FIRE := 7        # a: ship
const EV_GROUND := 8      # a: ship
const EV_FLED := 9        # a: ship
var ev_n := 0
var ev_t := PackedInt32Array()
var ev_k := PackedInt32Array()
var ev_a := PackedInt32Array()
var ev_b := PackedInt32Array()
var ev_c := PackedInt32Array()
var ev_d := PackedInt32Array()
var ev_e := PackedInt32Array()
var stats := {"broadsides": 0, "hits": 0, "rakes": 0, "boardings": 0, "captured": 0, "repelled": 0, "struck": 0,
	"sunk": 0, "fires": 0, "blown": 0, "tacks": 0, "wears": 0, "grounded": 0, "fled": 0, "chain": 0, "grape": 0}


# ------------------------------------------------------------------ setup ---

## Bearing in degrees (0 north, 90 east, clockwise) to a sim angle.
static func bearing_to_angle(deg: int) -> int:
	return (deg * FM.ANGLE_FULL / 360 - FM.ANGLE_QUARTER) & FM.ANGLE_MASK


## Sim angle to a bearing in degrees.
static func angle_to_bearing(a: int) -> int:
	return (((a + FM.ANGLE_QUARTER) & FM.ANGLE_MASK) * 360 / FM.ANGLE_FULL) % 360


## Scenario: {"sea": 1, "width_m", "height_m", "wind_deg" (bearing the wind
## blows from), "wind_str" 0-100, "ai_sides" [0|1, 0|1], "time_limit" (s),
## "deck" 0|1, "land": {"kind": 0 open / 1 island / 2 coast, "dirs" (coast:
## bit i for land toward angle i * 128, 0 east, 2 south, 4 west, 6 north),
## "mseed", optional island "ix", "iy", "ir" metres}, "layout": "ns" | "we" |
## "gauge0" | "gauge1" (where the fleets start when ships have no x / y),
## "units": [{"side", "t" (ship key), optional "x", "y" (m), "head"
## (bearing), "hull", "crew", "rig" (% of the row), "q" (gunnery %), "bq"
## (boarding %), "troops" (men), "mor"}]}.
func setup(scn: Dictionary, p_seed: int) -> void:
	seed_value = p_seed
	rng_state = (p_seed * 2654435761 + 12345) & 0x7FFFFFFF
	if rng_state == 0:
		rng_state = 1
	field_w = clampi(int(scn.get("width_m", FIELD_W)), 600, 6000)
	field_h = clampi(int(scn.get("height_m", FIELD_H)), 600, 6000)
	time_limit = int(scn.get("time_limit", TIME_LIMIT / 10)) * 10
	w_base = bearing_to_angle(int(scn.get("wind_deg", 90)))
	w_from = w_base
	w_goal = w_base
	w_str = clampi(int(scn.get("wind_str", 80)), 10, 100)
	deck_on = 1 if int(scn.get("deck", 0)) != 0 else 0
	var ai: Array = scn.get("ai_sides", [0, 1])
	ai_sides = PackedInt32Array([int(ai[0]), int(ai[1])])
	_make_land(scn.get("land", {}))
	var units: Array = scn.get("units", [])
	n_units = units.size()
	for nm in SHIP_ARRAYS:
		var arr := PackedInt32Array()
		arr.resize(n_units)
		arr.fill(0)
		set(nm, arr)
	s_ld.resize(n_units * 2)
	s_ld.fill(0)
	s_rl.resize(n_units * 2)
	s_rl.fill(0)
	u_hand.resize(n_units)
	u_hand.fill(-1)
	u_pack.resize(n_units)
	u_pack.fill(-1)
	u_char.resize(n_units)
	u_char.fill(0)
	for s in n_units:
		var d: Dictionary = units[s]
		var ty := maxi(ST.index_of(str(d.get("t", "frigate"))), 0)
		s_type[s] = ty
		u_side[s] = clampi(int(d.get("side", 0)), 0, 1)
		u_state[s] = S_SAIL
		s_hull0[s] = ST.stat(ty, "hull")
		s_hull[s] = maxi(s_hull0[s] * clampi(int(d.get("hull", 100)), 1, 100) / 100, 1)
		s_crew0[s] = ST.stat(ty, "crew")
		s_crew[s] = maxi(s_crew0[s] * clampi(int(d.get("crew", 100)), 1, 100) / 100, 1)
		s_rig0[s] = maxi(ST.stat(ty, "rig"), 1)
		s_rig[s] = s_rig0[s] * clampi(int(d.get("rig", 100)), 0, 100) / 100
		s_troops[s] = maxi(int(d.get("troops", 0)), 0)
		s_q[s] = clampi(int(d.get("q", 100)), 40, 160)
		s_bq[s] = clampi(int(d.get("bq", ST.stat(ty, "board"))), 40, 200)
		s_mor[s] = clampi(int(d.get("mor", 100)), 20, 150)
		s_sail[s] = 2
		s_fire[s] = 1
		s_tgt[s] = -1
		s_grap[s] = -1
		s_by[s] = -1
		s_end_t[s] = -1
		s_want[s] = -1
		s_hit_t[s] = -1000
		s_flee_x[s] = -1
		s_flee_y[s] = -1
		if d.has("x") and d.has("y"):
			s_x[s] = int(d["x"]) * U
			s_y[s] = int(d["y"]) * U
		else:
			s_x[s] = -1
		var hd := bearing_to_angle(int(d.get("head", 0)))
		s_h16[s] = hd * 16
		s_spd[s] = _vmax(s) * 55 / 100  # under way when it begins
	_layout(str(scn.get("layout", "ns")), units)
	for s in n_units:
		s_want[s] = s_h16[s] >> 4
	ev_t.resize(EV_CAP)
	ev_k.resize(EV_CAP)
	ev_a.resize(EV_CAP)
	ev_b.resize(EV_CAP)
	ev_c.resize(EV_CAP)
	ev_d.resize(EV_CAP)
	ev_e.resize(EV_CAP)


const SHIP_ARRAYS: Array[String] = ["u_side", "u_state", "s_type", "s_x", "s_y", "s_h16", "s_want", "s_tdir", "s_spd",
	"s_sail", "s_hull", "s_hull0", "s_crew", "s_crew0", "s_rig", "s_rig0", "s_troops", "s_q", "s_bq", "s_mor", "s_mode",
	"s_tx", "s_ty", "s_tgt", "s_fire", "s_shot", "s_tack", "s_grap", "s_boarder", "s_bd_t", "s_bd_wait", "s_by", "s_burn",
	"s_ground", "s_hit_t", "s_end_t", "s_kills", "s_blown", "s_flee_x", "s_flee_y"]


func is_tower(_u: int) -> bool:
	return false


## Ships without a position: each side in a line abreast at its end of the
## field (side 0 south / west / downwind, side 1 north / east / upwind for
## "gauge1"), facing the enemy or the nearest point of sail, clear of land.
func _layout(kind: String, units: Array) -> void:
	var cx := field_w * U / 2
	var cy := field_h * U / 2
	var ax := 0
	var ay := FM.TRIG_ONE  # side 0 is toward +y (south)
	var half := (field_h / 2 - 260) * U
	if kind == "we":
		ax = -FM.TRIG_ONE
		ay = 0
		half = (field_w / 2 - 300) * U
	elif kind == "gauge0" or kind == "gauge1":
		# Along the wind: side g at the upwind end.
		var up := w_from
		if kind == "gauge1":
			up = (w_from + FM.ANGLE_HALF) & FM.ANGLE_MASK
		ax = FM.cos_a(up)
		ay = FM.sin_a(up)
		half = mini(field_w, field_h) / 2 * U - 280 * U
	for side in 2:
		var list: Array[int] = []
		for s in n_units:
			if u_side[s] == side and s_x[s] < 0:
				list.append(s)
		var sgn := 1 if side == 0 else -1
		var bx := cx + sgn * ((ax * (half >> 6)) >> 6)
		var by := cy + sgn * ((ay * (half >> 6)) >> 6)
		# Across the axis: (-ay, ax).
		for i in list.size():
			var s := list[i]
			var off := (i * 2 - (list.size() - 1)) * 55 * U
			var px := bx + ((-ay * (off >> 6)) >> 6)
			var py := by + ((ax * (off >> 6)) >> 6)
			# Stagger: every other ship a little back.
			if i % 2 == 1:
				px += sgn * ((ax * (40 * U >> 6)) >> 6)
				py += sgn * ((ay * (40 * U >> 6)) >> 6)
			var p := _clear_spot(px, py)
			s_x[s] = p[0]
			s_y[s] = p[1]
			var face := FM.atan2_a(-sgn * ay, -sgn * ax)
			if (units[s] as Dictionary).has("head"):
				face = s_h16[s] >> 4
			s_h16[s] = _sailable(s, face) * 16


## The nearest clear water to (x, y) (spiralling toward the centre).
func _clear_spot(x: int, y: int) -> Array:
	var px := x
	var py := y
	var cx := field_w * U / 2
	var cy := field_h * U / 2
	for k in 40:
		if _clear_area(px, py, 50):
			return [px, py]
		px += (cx - px) / 12
		py += (cy - py) / 12
	return [px, py]


func _clear_area(x: int, y: int, r_m: int) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if _cell_at(x + dx * r_m * U, y + dy * r_m * U) != 0:
				return false
	return true


# ------------------------------------------------------------------- land ---

func _make_land(l: Dictionary) -> void:
	g_w = (field_w + CELL_M - 1) / CELL_M
	g_h = (field_h + CELL_M - 1) / CELL_M
	g = PackedByteArray()
	g.resize(g_w * g_h)
	g.fill(0)
	var kind := int(l.get("kind", 0))
	var ms := int(l.get("mseed", 1))
	var ph := PackedInt32Array()
	for k in 6:
		ms = (ms * 1103515245 + 12345) & 0x7FFFFFFF
		ph.append(ms % 1024)
	var cx := field_w / 2
	var cy := field_h / 2
	if kind == 2:
		var dirs := int(l.get("dirs", 0))
		for i in 8:
			if (dirs >> i) & 1 == 0:
				continue
			var a := i * 128
			var dx := FM.cos_a(a)
			var dy := FM.sin_a(a)
			# The edge in that direction (the corner for a diagonal), then the
			# coast that far in, ragged by the noise.
			var edge := (absi(dx) * cx + absi(dy) * cy) >> 12
			var depth := 300 if i % 2 == 0 else 380
			for gy in g_h:
				for gx in g_w:
					var mx := gx * CELL_M + CELL_M / 2
					var my := gy * CELL_M + CELL_M / 2
					var proj := ((mx - cx) * dx + (my - cy) * dy) >> 12
					var along := ((mx - cx) * -dy + (my - cy) * dx) >> 12
					var nz := (FM.sin_a(along * 3 + ph[0]) * 60 + FM.sin_a(along * 7 + ph[1]) * 28 +
						FM.sin_a(along * 17 + ph[2]) * 12) >> 12
					var lim := edge - depth + nz
					var c := gy * g_w + gx
					if proj > lim:
						g[c] = 2
					elif proj > lim - 55 and g[c] == 0:
						g[c] = 1
	if kind == 1 or l.has("ir"):
		var ix := int(l.get("ix", cx + (ph[3] - 512) * field_w / 4096))
		var iy := int(l.get("iy", cy + (ph[4] - 512) * field_h / 3000))
		var ir := int(l.get("ir", 90 + ph[5] % 100))
		for gy in g_h:
			for gx in g_w:
				var mx := gx * CELL_M + CELL_M / 2 - ix
				var my := gy * CELL_M + CELL_M / 2 - iy
				var d := FM.isqrt(mx * mx + my * my)
				var a := FM.atan2_a(my, mx)
				var nz := (FM.sin_a(a * 3 + ph[0]) * ir / 4 + FM.sin_a(a * 5 + ph[2]) * ir / 7) >> 12
				var c := gy * g_w + gx
				if d < ir + nz:
					g[c] = 2
				elif d < ir + nz + 45 and g[c] == 0:
					g[c] = 1
	var h := 5381
	for k in g.size():
		h = ((h * 33) ^ g[k]) & 0x7FFFFFFF
	ter_hash = h


func _cell_at(x: int, y: int) -> int:
	if x < 0 or y < 0:
		return 0
	var gx := x / (CELL_M * U)
	var gy := y / (CELL_M * U)
	if gx >= g_w or gy >= g_h:
		return 0
	return g[gy * g_w + gx]


## Land at (x, y) for ship s (a shoal stops deep-draught ships only).
func _blocked(s: int, x: int, y: int) -> bool:
	var v := _cell_at(x, y)
	return v == 2 or (v == 1 and ST.stat(s_type[s], "draft") != 0)


func land_at_m(x_m: int, y_m: int) -> int:
	return _cell_at(x_m * U, y_m * U)


# -------------------------------------------------------------------- rng ---

func _rand() -> int:
	var x := rng_state
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	rng_state = x
	return x


func _roll(n: int) -> int:
	if n <= 1:
		return 0
	return (_rand() & 0x7FFFFFFF) % n


# ----------------------------------------------------------------- orders ---

func queue_order(order: Dictionary) -> void:
	var o := {}
	for k in order:
		o[k] = int(order[k])
	if not o.has("player"):
		o["player"] = 0
	if not o.has("seq"):
		o["seq"] = _order_seq
		_order_seq += 1
	if not o.has("tick"):
		o["tick"] = tick
	pending_orders.append(o)


static func _order_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a["tick"]) != int(b["tick"]):
		return int(a["tick"]) < int(b["tick"])
	if int(a["player"]) != int(b["player"]):
		return int(a["player"]) < int(b["player"])
	return int(a["seq"]) < int(b["seq"])


func _apply_orders() -> void:
	if pending_orders.is_empty():
		return
	var due: Array = []
	var rest: Array = []
	for o in pending_orders:
		if int(o["tick"]) <= tick:
			due.append(o)
		else:
			rest.append(o)
	if due.is_empty():
		return
	pending_orders = rest
	due.sort_custom(_order_less)
	for o in due:
		_order(o)


func _order(o: Dictionary) -> void:
	var s := int(o.get("unit", -1))
	if s < 0 or s >= n_units:
		return
	var typ := int(o.get("type", 0))
	if typ == O_DECK:
		_deck_result(s, int(o.get("target", -1)), int(o.get("on", 0)), int(o.get("a", 0)), int(o.get("b", 0)))
		return
	if u_state[s] != S_SAIL:
		return
	match typ:
		O_SAIL:
			s_mode[s] = M_GOTO
			s_tx[s] = clampi(int(o.get("x", 0)), 0, field_w) * U
			s_ty[s] = clampi(int(o.get("y", 0)), 0, field_h) * U
			s_tack[s] = 0
			s_tdir[s] = 0
		O_TARGET:
			var t := int(o.get("target", -1))
			if t >= 0 and t < n_units and u_side[t] != u_side[s] and u_state[t] == S_SAIL:
				s_mode[s] = M_ENGAGE
				s_tgt[s] = t
				s_tack[s] = 0
				s_tdir[s] = 0
		O_HOLD:
			s_mode[s] = M_FREE
			s_tgt[s] = -1
			s_tdir[s] = 0
		O_SAILS:
			s_sail[s] = clampi(int(o.get("on", 2)), 0, 2)
		O_FIRE:
			s_fire[s] = 1 if int(o.get("on", 1)) != 0 else 0
		O_SHOT:
			s_shot[s] = clampi(int(o.get("on", 0)), 0, 2)
		O_FLEE:
			s_mode[s] = M_FLEE
			s_flee_x[s] = -1
			s_sail[s] = 2
			s_tdir[s] = 0
		O_BOARD:
			var t2 := int(o.get("target", -1))
			if t2 >= 0 and t2 < n_units and u_side[t2] != u_side[s] and (u_state[t2] == S_SAIL or u_state[t2] == S_STRUCK):
				s_mode[s] = M_BOARD
				s_tgt[s] = t2
				s_tack[s] = 0
				s_tdir[s] = 0
		O_HEAD:
			s_mode[s] = M_HEAD
			s_tx[s] = int(o.get("facing", 0)) & FM.ANGLE_MASK
			s_tdir[s] = 0


# ------------------------------------------------------------------- step ---

func step() -> void:
	_apply_orders()
	_wind()
	for s in n_units:
		if (tick + s) % 10 == 0 and ai_sides[u_side[s]] != 0 and u_state[s] == S_SAIL and decided_tick < 0:
			_think(s)
	for s in n_units:
		if (tick + s) % 5 == 0 or s_want[s] < 0:
			_steer(s)
	for s in n_units:
		_move(s)
	_contacts()
	if tick % 10 == 0:
		_boardings()
	_gunnery()
	if tick % 10 == 0:
		_fires()
		_morale()
	_decide()
	tick += 1


func _wind() -> void:
	if tick > 0 and tick % WIND_EVERY == 0:
		var d := _roll(61) - 30
		w_goal = (w_base + clampi(FM.angle_diff(w_base, w_goal) + d, -WIND_SPAN, WIND_SPAN)) & FM.ANGLE_MASK
	if tick % 4 == 0 and w_from != w_goal:
		w_from = (w_from + (1 if FM.angle_diff(w_from, w_goal) > 0 else -1)) & FM.ANGLE_MASK


func heading(s: int) -> int:
	return (s_h16[s] >> 4) & FM.ANGLE_MASK


func _vmax(s: int) -> int:
	return ST.stat(s_type[s], "vmax") * U / 100


func _irons(s: int) -> int:
	return ST.stat(s_type[s], "irons") * FM.ANGLE_FULL / 360


## Angle off the wind of heading h (0: head to wind, 512: dead downwind).
func off_wind(h: int) -> int:
	return absi(FM.angle_diff(h, w_from))


## Drive % on heading h for ship s (the points of sail).
func drive(s: int, h: int) -> int:
	if ST.stat(s_type[s], "oars") != 0:
		return 100
	var i := _irons(s)
	var off := off_wind(h)
	if off < i:
		return 0
	if off < i + 40:
		return 45 + (off - i) * 35 / 40
	if off < 256:
		return 80 + (off - i - 40) * 20 / maxi(256 - i - 40, 1)
	if off <= 400:
		return 100
	return 100 - (off - 400) * 18 / 112


## A heading near h that ship s can sail (out of the no-go zone).
func _sailable(s: int, h: int) -> int:
	if ST.stat(s_type[s], "oars") != 0:
		return h & FM.ANGLE_MASK
	var c := _irons(s) + 24
	var d := FM.angle_diff(w_from, h)
	if absi(d) >= c:
		return h & FM.ANGLE_MASK
	return (w_from + (c if d >= 0 else -c)) & FM.ANGLE_MASK


func target_speed(s: int) -> int:
	if u_state[s] != S_SAIL or s_grap[s] >= 0:
		return 0
	var ty := s_type[s]
	var v := _vmax(s) * drive(s, heading(s)) / 100 * int(SAIL_PCT[s_sail[s]]) / 100
	if ST.stat(ty, "oars") != 0:
		v = v * (300 + 700 * s_crew[s] / maxi(s_crew0[s], 1)) / 1000
	else:
		v = v * (250 + 750 * s_rig[s] / s_rig0[s]) / 1000
		v = v * mini(450 + w_str * 7, 1100) / 1000
	var hp := s_hull[s] * 100 / s_hull0[s]
	if hp < 50:
		v = v * (50 + hp) / 100
	return v


# ------------------------------------------------------------- navigation ---

## The heading ship s steers for a point: straight there when it can lie
## that course, else close-hauled on the current tack until the point
## bears on the other tack's layline (or land / the edge is ahead).
func _course(s: int, tx: int, ty: int) -> int:
	var b := FM.atan2_a(ty - s_y[s], tx - s_x[s])
	if ST.stat(s_type[s], "oars") != 0:
		s_tack[s] = 0
		return b
	var c := _irons(s) + 24
	var d := FM.angle_diff(w_from, b)
	if absi(d) >= c:
		s_tack[s] = 0
		return b
	if s_tack[s] == 0:
		var dh := FM.angle_diff(w_from, heading(s))
		s_tack[s] = 1 if dh >= 0 else -1
	var hd := (w_from + s_tack[s] * c) & FM.ANGLE_MASK
	if not _probe_clear(s, hd, 160, false):
		s_tack[s] = -s_tack[s]
		hd = (w_from + s_tack[s] * c) & FM.ANGLE_MASK
	return hd


## Clear water along heading h for `dist` metres (probes every 40 m) and
## inside the field (EDGE_M from the edges unless `edge_ok`).
func _probe_clear(s: int, h: int, dist: int, edge_ok: bool) -> bool:
	var cs := FM.cos_a(h)
	var sn := FM.sin_a(h)
	var m := 40
	while m <= dist:
		var x := s_x[s] + ((cs * m) >> 12) * U
		var y := s_y[s] + ((sn * m) >> 12) * U
		if _blocked(s, x, y):
			return false
		if not edge_ok and (x < EDGE_M * U or y < EDGE_M * U or x > (field_w - EDGE_M) * U or y > (field_h - EDGE_M) * U) \
				and _outward(s, h):
			return false
		m += 40
	return true


func _outward(s: int, h: int) -> bool:
	var cx := field_w * U / 2 - s_x[s]
	var cy := field_h * U / 2 - s_y[s]
	var to_c := FM.atan2_a(cy, cx)
	return absi(FM.angle_diff(h, to_c)) > 256


## Heading h, or the nearest one (in 20 degree steps either way) with clear
## water ahead that ship s can sail.
func _avoid(s: int, h: int, edge_ok: bool) -> int:
	var reach := 120 + ST.stat(s_type[s], "len") * 2
	if _probe_clear(s, h, reach, edge_ok):
		return h
	for k in range(1, 9):
		for sg: int in [1, -1]:
			var c := (h + sg * k * 57) & FM.ANGLE_MASK
			if drive(s, c) > 0 and _probe_clear(s, c, reach, edge_ok):
				return c
	return h


func _steer(s: int) -> void:
	if u_state[s] != S_SAIL:
		s_want[s] = heading(s)
		return
	if s_grap[s] >= 0:
		s_want[s] = heading(s)
		return
	var h := heading(s)
	var want := h
	var edge_ok := false
	match s_mode[s]:
		M_FREE:
			want = h
		M_HEAD:
			want = _sailable(s, s_tx[s])
		M_GOTO:
			var dx := s_tx[s] - s_x[s]
			var dy := s_ty[s] - s_y[s]
			if FM.approx_len(dx, dy) < 35 * U:
				s_mode[s] = M_FREE
			else:
				want = _course(s, s_tx[s], s_ty[s])
		M_ENGAGE:
			var t := s_tgt[s]
			if t < 0 or u_state[t] != S_SAIL:
				s_mode[s] = M_FREE
				s_tgt[s] = -1
			else:
				want = _engage_heading(s, t)
		M_BOARD:
			var t2 := s_tgt[s]
			if t2 < 0 or not (u_state[t2] == S_SAIL or u_state[t2] == S_STRUCK) or s_grap[t2] >= 0:
				s_mode[s] = M_FREE
				s_tgt[s] = -1
			else:
				want = _board_heading(s, t2)
		M_FLEE:
			edge_ok = true
			if s_flee_x[s] < 0 or tick % 50 == 0:
				_flee_goal(s)
			want = _course(s, s_flee_x[s], s_flee_y[s])
	want = _avoid(s, want, edge_ok)
	if absi(FM.angle_diff(want, s_want[s])) > 28:
		s_tdir[s] = 0
	s_want[s] = want


## Engage target t: close on it (beating up to windward of it when far),
## then keep a broadside on at the loaded shot's range, presenting the
## loaded side; open the range when too close.
func _engage_heading(s: int, t: int) -> int:
	var dx := s_x[t] - s_x[s]
	var dy := s_y[t] - s_y[s]
	var d := FM.approx_len(dx, dy) / U
	var bt := FM.atan2_a(dy, dx)
	var rng := ST.stat(s_type[s], "range")
	var want_r := mini(int(RANGE_PREF[s_ld[s * 2]]) if s_rl[s * 2] == 0 else int(RANGE_PREF[s_shot[s]]), rng * 8 / 10)
	if d > want_r + 220:
		var gx := s_x[t]
		var gy := s_y[t]
		if d > 600 and ST.stat(s_type[s], "oars") == 0:
			# The weather gauge: make for a point up to windward of it.
			gx += ((FM.cos_a(w_from) * 220) >> 12) * U
			gy += ((FM.sin_a(w_from) * 220) >> 12) * U
		return _course(s, gx, gy)
	var cands: Array[int] = []
	if d > want_r + 60:
		cands = [(bt + 160) & FM.ANGLE_MASK, (bt - 160) & FM.ANGLE_MASK]
	elif d >= want_r - 50:
		cands = [(bt + 256) & FM.ANGLE_MASK, (bt - 256) & FM.ANGLE_MASK]
	else:
		cands = [(bt + 340) & FM.ANGLE_MASK, (bt - 340) & FM.ANGLE_MASK]
	var h := heading(s)
	var best := h
	var bs := 1 << 30
	for i in 2:
		var c := _sailable(s, cands[i])
		# cands[0] (bt + x) puts the target to port, cands[1] to starboard.
		var score := absi(FM.angle_diff(h, c))
		if s_rl[s * 2 + i] > 0:
			score += 160
		if c != cands[i]:
			score += 60
		if score < bs:
			bs = score
			best = c
	return best


func _board_heading(s: int, t: int) -> int:
	var dx := s_x[t] - s_x[s]
	var dy := s_y[t] - s_y[s]
	var d := FM.approx_len(dx, dy) / U
	var th := heading(t)
	var lead := clampi(d * 10 / maxi(s_spd[s] * 10 / U, 2), 0, 60)  # ticks ahead
	var tx := s_x[t] + ((FM.cos_a(th) * s_spd[t]) >> 12) * lead / 4
	var ty := s_y[t] + ((FM.sin_a(th) * s_spd[t]) >> 12) * lead / 4
	if d > 90:
		# Come up under her stern, where her broadsides do not bear.
		var back := ST.stat(s_type[t], "len") / 2 + mini(d / 3, 70)
		var ax := tx - ((FM.cos_a(th) * back) >> 12) * U
		var ay := ty - ((FM.sin_a(th) * back) >> 12) * U
		s_sail[s] = 2
		return _course(s, ax, ay)
	# Close: come up alongside, matching her speed.
	var mine := s_spd[s]
	if mine > s_spd[t] + 200 and d < 45:
		s_sail[s] = 0
	elif mine > s_spd[t] + 120:
		s_sail[s] = 1
	else:
		s_sail[s] = 2
	if d > 30:
		return _sailable(s, FM.atan2_a(ty - s_y[s], tx - s_x[s]))
	return _sailable(s, th)


func _flee_goal(s: int) -> void:
	# The edge point (of the four nearest) farthest from the enemy.
	var cands := [[s_x[s], -60 * U], [s_x[s], (field_h + 60) * U], [-60 * U, s_y[s]], [(field_w + 60) * U, s_y[s]]]
	var best := 0
	var bv := -(1 << 60)
	for i in 4:
		var c: Array = cands[i]
		var dmin := 1 << 40
		for e in n_units:
			if u_side[e] != u_side[s] and u_state[e] == S_SAIL:
				dmin = mini(dmin, FM.approx_len(int(c[0]) - s_x[e], int(c[1]) - s_y[e]))
		var own := FM.approx_len(int(c[0]) - s_x[s], int(c[1]) - s_y[s])
		var v := dmin - own * 2
		var b := FM.atan2_a(int(c[1]) - s_y[s], int(c[0]) - s_x[s])
		v -= (100 - drive(s, b)) * 8 * U
		if v > bv:
			bv = v
			best = i
	s_flee_x[s] = int(cands[best][0])
	s_flee_y[s] = int(cands[best][1])


# --------------------------------------------------------------- movement ---

func _turn_rate16(s: int) -> int:
	var ty := s_type[s]
	var r := ST.stat(ty, "turn") * 16384 / 36000
	var half := maxi(_vmax(s) / 2, 1)
	var pct := 25 + 75 * mini(s_spd[s], half) / half
	if ST.stat(ty, "oars") != 0:
		pct = maxi(pct, 60)
	return maxi(r * pct / 100, 1)


func _move(s: int) -> void:
	var st := u_state[s]
	if st == S_SUNK or st == S_FLED:
		return
	var ty := s_type[s]
	if s_grap[s] >= 0:
		_hold_alongside(s)
		return
	# Turning.
	var h := heading(s)
	var want := s_want[s]
	var oars := ST.stat(ty, "oars") != 0
	var stalled := not oars and off_wind(h) < _irons(s) and s_spd[s] < _vmax(s) * 8 / 100
	if stalled and st == S_SAIL:
		# In irons without way: the wind pushes her bow off.
		var side := 1 if FM.angle_diff(w_from, h) >= 0 else -1
		s_h16[s] = (s_h16[s] + side * 9) & 16383
		s_tdir[s] = 0
	elif st == S_SAIL and want >= 0 and want != h:
		var diff := FM.angle_diff(h, want)
		if s_tdir[s] == 0:
			var dir := 1 if diff > 0 else -1
			if not oars and _crosses_wind(h, diff):
				if s_spd[s] < _vmax(s) * ST.stat(ty, "tack") / 100:
					dir = -dir  # wear round
					stats["wears"] = int(stats["wears"]) + 1
				else:
					stats["tacks"] = int(stats["tacks"]) + 1
			s_tdir[s] = dir
		var rate := _turn_rate16(s)
		var rem16 := 0
		if (diff > 0) == (s_tdir[s] > 0):
			rem16 = absi(diff) * 16
		else:
			rem16 = (FM.ANGLE_FULL - absi(diff)) * 16
		if rem16 <= rate:
			s_h16[s] = want * 16
			s_tdir[s] = 0
		else:
			s_h16[s] = (s_h16[s] + s_tdir[s] * rate) & 16383
	h = heading(s)
	# Speed.
	var tv := target_speed(s)
	var v := s_spd[s]
	if tv > v:
		v += maxi((tv - v) / 40, 1)
	elif tv < v:
		var k := 25
		if not oars and off_wind(h) < _irons(s):
			k = 12
		v -= maxi((v - tv) / k, 1)
	s_spd[s] = maxi(v, 0)
	# Way and leeway.
	var lee := 31 * w_str / 100
	if st != S_SAIL:
		lee = lee * 3 / 2
	var wt := (w_from + FM.ANGLE_HALF) & FM.ANGLE_MASK
	var nx := s_x[s] + ((FM.cos_a(h) * s_spd[s]) >> 12) + ((FM.cos_a(wt) * lee) >> 12)
	var ny := s_y[s] + ((FM.sin_a(h) * s_spd[s]) >> 12) + ((FM.sin_a(wt) * lee) >> 12)
	# The edge: a fleeing ship (or any not fighting) leaves the battle.
	var out := nx < 0 or ny < 0 or nx > field_w * U or ny > field_h * U
	if out:
		if st == S_SAIL and s_mode[s] == M_FLEE:
			u_state[s] = S_FLED
			s_end_t[s] = tick
			stats["fled"] = int(stats["fled"]) + 1
			_event(EV_FLED, s, 0, -1, 0, 0)
			return
		# Held at the edge: she slides along it (and the navigator turns her in).
		nx = clampi(nx, 0, field_w * U)
		ny = clampi(ny, 0, field_h * U)
		s_spd[s] = s_spd[s] * 15 / 16
	# Land: the bow and the hull's middle.
	var half := ST.stat(ty, "len") * U / 2
	var bx := nx + ((FM.cos_a(h) * (half >> 6)) >> 6)
	var by := ny + ((FM.sin_a(h) * (half >> 6)) >> 6)
	if _blocked(s, bx, by) or _blocked(s, nx, ny):
		if s_spd[s] > _vmax(s) / 5 and s_ground[s] <= tick:
			s_hull[s] = maxi(s_hull[s] - maxi(s_hull0[s] / 40, 1), 0)
			stats["grounded"] = int(stats["grounded"]) + 1
			_event(EV_GROUND, s, 0, -1, 0, 0)
			s_ground[s] = tick + 50
		s_spd[s] = 0
		if not _blocked(s, nx, ny) and _blocked(s, bx, by):
			# The bow is on the bank: she lies there (the steering turns her off).
			return
		# The middle too: back her off along her wake.
		var px := s_x[s] - ((FM.cos_a(h) * 2 * U) >> 12)
		var py := s_y[s] - ((FM.sin_a(h) * 2 * U) >> 12)
		if not _blocked(s, px, py):
			s_x[s] = px
			s_y[s] = py
		return
	s_x[s] = nx
	s_y[s] = ny


## True if turning from h by the signed diff (the short way) crosses the
## wind's eye.
func _crosses_wind(h: int, diff: int) -> bool:
	var a := FM.angle_diff(h, w_from)
	if diff > 0:
		return a > 0 and a < diff
	return a < 0 and a > diff


## A grappled pair: the defender drifts, the boarder lies alongside her.
func _hold_alongside(s: int) -> void:
	var o := s_grap[s]
	s_spd[s] = s_spd[s] * 7 / 8
	if s_boarder[s] == 0:
		var lee := 20 * w_str / 100
		var wt := (w_from + FM.ANGLE_HALF) & FM.ANGLE_MASK
		var nx := s_x[s] + ((FM.cos_a(wt) * lee) >> 12) + ((FM.cos_a(heading(s)) * s_spd[s]) >> 12)
		var ny := s_y[s] + ((FM.sin_a(wt) * lee) >> 12) + ((FM.sin_a(heading(s)) * s_spd[s]) >> 12)
		if not _blocked(s, nx, ny):
			s_x[s] = clampi(nx, 0, field_w * U)
			s_y[s] = clampi(ny, 0, field_h * U)
		return
	# The boarder: beside her, on the side it came from, heading with her.
	var oh := heading(o)
	var side := 1 if FM.angle_diff(oh, FM.atan2_a(s_y[s] - s_y[o], s_x[s] - s_x[o])) >= 0 else -1
	var gap := (ST.stat(s_type[s], "beam") + ST.stat(s_type[o], "beam")) / 2 + 2
	var pa := (oh + side * 256) & FM.ANGLE_MASK
	var gx := s_x[o] + ((FM.cos_a(pa) * gap) >> 12) * U
	var gy := s_y[o] + ((FM.sin_a(pa) * gap) >> 12) * U
	s_x[s] += (gx - s_x[s]) / 6
	s_y[s] += (gy - s_y[s]) / 6
	var dh := FM.angle_diff(heading(s), oh)
	s_h16[s] = (s_h16[s] + clampi(dh * 16, -40, 40)) & 16383


## Ships too close push apart; boarders grapple their target.
func _contacts() -> void:
	for a in n_units:
		if u_state[a] == S_SUNK or u_state[a] == S_FLED:
			continue
		for b in range(a + 1, n_units):
			if u_state[b] == S_SUNK or u_state[b] == S_FLED:
				continue
			if s_grap[a] == b:
				continue
			var dx := s_x[b] - s_x[a]
			var dy := s_y[b] - s_y[a]
			var lim := (ST.stat(s_type[a], "len") + ST.stat(s_type[b], "len")) * U * 30 / 100
			if absi(dx) > lim * 2 or absi(dy) > lim * 2:
				continue
			var d := FM.approx_len(dx, dy)
			if d < lim:
				var push := (lim - d) / 2 + 1
				var ang := FM.atan2_a(dy, dx) if d > 0 else (a * 97) & FM.ANGLE_MASK
				var px := (FM.cos_a(ang) * (push >> 4)) >> 8
				var py := (FM.sin_a(ang) * (push >> 4)) >> 8
				if not _blocked(a, s_x[a] - px, s_y[a] - py) and s_grap[a] < 0:
					s_x[a] -= px
					s_y[a] -= py
				if not _blocked(b, s_x[b] + px, s_y[b] + py) and s_grap[b] < 0:
					s_x[b] += px
					s_y[b] += py
				s_spd[a] = s_spd[a] * 9 / 10
				s_spd[b] = s_spd[b] * 9 / 10
	for s in n_units:
		if u_state[s] != S_SAIL or s_mode[s] != M_BOARD or s_grap[s] >= 0:
			continue
		var t := s_tgt[s]
		if t < 0 or s_grap[t] >= 0 or not (u_state[t] == S_SAIL or u_state[t] == S_STRUCK):
			continue
		var d2 := FM.approx_len(s_x[t] - s_x[s], s_y[t] - s_y[s])
		var reach := ((ST.stat(s_type[s], "len") + ST.stat(s_type[t], "len")) * 40 / 100 + 8) * U
		if d2 > reach:
			continue
		var vx := ((FM.cos_a(heading(s)) * s_spd[s]) >> 12) - ((FM.cos_a(heading(t)) * s_spd[t]) >> 12)
		var vy := ((FM.sin_a(heading(s)) * s_spd[s]) >> 12) - ((FM.sin_a(heading(t)) * s_spd[t]) >> 12)
		if FM.approx_len(vx, vy) > 360 and s_spd[t] > 150:
			continue
		_grapple(s, t)


func _grapple(s: int, t: int) -> void:
	s_grap[s] = t
	s_grap[t] = s
	s_boarder[s] = 1
	s_boarder[t] = 0
	s_bd_t[s] = tick
	s_mode[s] = M_FREE
	stats["boardings"] = int(stats["boardings"]) + 1
	_event(EV_GRAPPLE, s, 0, t, 0, 0)
	if u_state[t] == S_STRUCK:
		_capture(t, s)
		return
	if deck_on != 0:
		s_bd_wait[s] = 1


## Boarding fights (a second at a time): Lanchester-like losses by the
## boarders' strength (crew x quality + troops) against the defenders' (on
## their own deck, DECK_BONUS_PCT); the defenders are taken when they fall
## under 40 % of the boarders, the boarders thrown back under 50 % of the
## defenders or after BOARD_MAX_TICKS.
func _boardings() -> void:
	for s in n_units:
		if s_grap[s] < 0 or s_boarder[s] == 0 or s_bd_wait[s] != 0:
			continue
		var t := s_grap[s]
		var a := s_crew[s] * s_bq[s] / 100 + s_troops[s] * 12 / 10
		var d := (s_crew[t] * s_bq[t] / 100 + s_troops[t] * 12 / 10) * DECK_BONUS_PCT / 100
		var k := 5 + _roll(4)
		var la := maxi(d * k / 100, 1)
		var ld := maxi(a * k / 100, 1)
		_lose_men(s, la * 100 / maxi(s_bq[s], 1))
		_lose_men(t, ld * 100 / maxi(s_bq[t], 1))
		s_kills[s] += ld
		s_kills[t] += la
		var a2 := s_crew[s] * s_bq[s] / 100 + s_troops[s] * 12 / 10
		var d2 := (s_crew[t] * s_bq[t] / 100 + s_troops[t] * 12 / 10) * DECK_BONUS_PCT / 100
		if d2 * 100 < a2 * 40 or s_crew[t] <= 2:
			_capture(t, s)
		elif a2 * 100 < d2 * 50 or s_crew[s] <= 2 or tick - s_bd_t[s] >= BOARD_MAX_TICKS:
			_ungrapple(s)
			s_mor[s] -= 25
			s_mode[s] = M_FREE
			stats["repelled"] = int(stats["repelled"]) + 1
			_event(EV_REPELLED, s, 0, t, 0, 0)


## Men lost from ship s: troops and crew in proportion.
func _lose_men(s: int, n: int) -> void:
	var tot := s_crew[s] + s_troops[s]
	if tot <= 0 or n <= 0:
		return
	var tl := s_troops[s] * n / tot
	s_troops[s] = maxi(s_troops[s] - tl, 0)
	s_crew[s] = maxi(s_crew[s] - (n - tl), 0)


func _ungrapple(s: int) -> void:
	var t := s_grap[s]
	s_grap[s] = -1
	s_boarder[s] = 0
	s_bd_wait[s] = 0
	if t >= 0:
		s_grap[t] = -1
		s_boarder[t] = 0
		s_bd_wait[t] = 0


## Prize p is taken by ship c's side: a prize crew goes across.
func _capture(p: int, c: int) -> void:
	_ungrapple(c)
	u_state[p] = S_TAKEN
	s_by[p] = u_side[c]
	s_end_t[p] = tick
	s_sail[p] = 0
	s_burn[p] = 0
	var pc := clampi(s_crew[c] / 8, 1, 40)
	s_crew[c] = maxi(s_crew[c] - pc, 1)
	s_crew[p] = pc
	s_troops[p] = 0
	s_mode[c] = M_FREE
	s_tgt[c] = -1
	stats["captured"] = int(stats["captured"]) + 1
	_event(EV_TAKEN, c, 0, p, 0, 0)
	_shock(p, 10)


## N3b: the deck melee between boarder s and target t is decided.
func _deck_result(s: int, t: int, won: int, crew_a: int, crew_b: int) -> void:
	if t < 0 or t >= n_units or s_grap[s] != t or s_boarder[s] == 0:
		return
	s_crew[s] = clampi(crew_a, 0, s_crew[s])
	s_crew[t] = clampi(crew_b, 0, s_crew[t])
	s_bd_wait[s] = 0
	if won != 0:
		_capture(t, s)
	else:
		_ungrapple(s)
		s_mor[s] -= 25
		_event(EV_REPELLED, s, 0, t, 0, 0)


## N3b hook: the grappled pairs waiting for a deck melee (scenario "deck"):
## [{boarder, target, sides, crews, troops, quality}].
func deck_request() -> Array:
	var out: Array = []
	for s in n_units:
		if s_grap[s] >= 0 and s_boarder[s] != 0 and s_bd_wait[s] != 0:
			var t := s_grap[s]
			out.append({"boarder": s, "target": t, "sides": [u_side[s], u_side[t]], "crews": [s_crew[s], s_crew[t]],
				"troops": [s_troops[s], s_troops[t]], "quality": [s_bq[s], s_bq[t]],
				"ships": [str(ST.row(s_type[s])["key"]), str(ST.row(s_type[t])["key"])]})
	return out


# ---------------------------------------------------------------- gunnery ---

func shot_range(s: int, shot: int) -> int:
	var r := ST.stat(s_type[s], "range")
	if shot == ST.SHOT_CHAIN:
		return r * ST.CHAIN_RANGE_PCT / 100
	if shot == ST.SHOT_GRAPE:
		return r * ST.GRAPE_RANGE_PCT / 100
	return r


## Reload speed per mille (the gun crews: MEN_PER_GUN a gun on both sides).
func _crew_rate(s: int) -> int:
	var need := maxi(ST.stat(s_type[s], "guns") * ST.MEN_PER_GUN * 2, 1)
	return clampi(s_crew[s] * 1000 / need, 150, 1000)


func guns_working(s: int) -> int:
	var gn := ST.stat(s_type[s], "guns")
	return maxi(gn * (40 + 60 * s_hull[s] / s_hull0[s]) / 100, 1 if s_hull[s] > 0 else 0)


func _gunnery() -> void:
	for s in n_units:
		if u_state[s] != S_SAIL:
			continue
		var rate := _crew_rate(s)
		for k in 2:
			var i := s * 2 + k
			if s_rl[i] > 0:
				s_rl[i] = maxi(s_rl[i] - rate, 0)
				continue
			if s_grap[s] >= 0 or decided_tick >= 0:
				continue
			var t := _pick_target(s, k)
			if t >= 0:
				_broadside(s, k, t)


## The target for ship s's broadside k (0 port, 1 starboard): the ordered
## one when it bears, else (fire at will) the nearest enemy in the arc and
## in range of the loaded shot, not masked by a friend.
func _pick_target(s: int, k: int) -> int:
	var h := heading(s)
	var arc := (h - 256 if k == 0 else h + 256) & FM.ANGLE_MASK
	var rng := shot_range(s, s_ld[s * 2 + k]) * U
	var best := -1
	var bd := 1 << 40
	for t in n_units:
		if u_side[t] == u_side[s] or u_state[t] != S_SAIL:
			continue
		var dx := s_x[t] - s_x[s]
		var dy := s_y[t] - s_y[s]
		if absi(dx) > rng or absi(dy) > rng:
			continue
		var d := FM.approx_len(dx, dy)
		if d > rng:
			continue
		if absi(FM.angle_diff(arc, FM.atan2_a(dy, dx))) > ARC:
			continue
		if t != s_tgt[s] and s_fire[s] == 0:
			continue
		var score := d
		if t == s_tgt[s]:
			score -= 1 << 30
		if score < bd and not _masked(s, t, d):
			bd = score
			best = t
	return best


## A friendly ship lies in the line of fire from s to t (d: distance).
func _masked(s: int, t: int, d: int) -> bool:
	var bt := FM.atan2_a(s_y[t] - s_y[s], s_x[t] - s_x[s])
	for f in n_units:
		if f == s or u_side[f] != u_side[s] or u_state[f] == S_SUNK or u_state[f] == S_FLED:
			continue
		var dx := s_x[f] - s_x[s]
		var dy := s_y[f] - s_y[s]
		var df := FM.approx_len(dx, dy)
		if df >= d or df < 5 * U:
			continue
		var half := (ST.stat(s_type[f], "len") / 2 + 4) * U
		var ang := absi(FM.angle_diff(bt, FM.atan2_a(dy, dx)))
		# The friend's half-length subtends about half / df radians.
		if ang * df < half * 163:
			return true
	return false


func _broadside(s: int, k: int, t: int) -> void:
	var i := s * 2 + k
	var shot := s_ld[i]
	var ty := s_type[s]
	var tt := s_type[t]
	var d := FM.approx_len(s_x[t] - s_x[s], s_y[t] - s_y[s]) / U
	var rng := maxi(shot_range(s, shot), 1)
	var size := 50 + ST.stat(tt, "len") * 50 / 40
	var p := 88 * size / 100 * (100 - 70 * mini(d, rng) / rng) / 100 * s_q[s] / 100
	if shot == ST.SHOT_GRAPE:
		p = p * 120 / 100
	p = clampi(p, 3, 95)
	var guns := guns_working(s)
	var hits := 0
	for n in guns:
		if _roll(100) < p:
			hits += 1
	# Raking: from ahead of her bow or astern, down her length.
	var asp := absi(FM.angle_diff(heading(t), FM.atan2_a(s_y[s] - s_y[t], s_x[s] - s_x[t])))
	var rake := asp < 90 or asp > FM.ANGLE_HALF - 90
	var w := ST.stat(ty, "gun")
	var hull0 := s_hull[t]
	var men := 0
	match shot:
		ST.SHOT_ROUND:
			s_hull[t] -= hits * w
			men = hits * (w + 2) / 5
			for n in hits:
				if s_burn[t] == 0 and _roll(1000) < FIRE_PM:
					s_burn[t] = 1
					stats["fires"] = int(stats["fires"]) + 1
					_event(EV_FIRE, t, 0, s, 0, 0)
			s_rig[t] -= hits * w / 4
		ST.SHOT_CHAIN:
			s_rig[t] -= hits * w * 2
			s_hull[t] -= hits
			men = hits / 3
			stats["chain"] = int(stats["chain"]) + 1
		_:
			men = hits * (w / 4 + 1)
			s_rig[t] -= hits
			stats["grape"] = int(stats["grape"]) + 1
	if rake:
		# Down her length: round shot 2 x the slaughter, chain 1.5, grape 1.6.
		men = men * [20, 15, 16][shot] / 10
		stats["rakes"] = int(stats["rakes"]) + 1
	men += _roll(hits + 1) if hits > 0 else 0
	s_rig[t] = maxi(s_rig[t], 0)
	var before := s_crew[t] + s_troops[t]
	_lose_men(t, men)
	var lost := before - s_crew[t] - s_troops[t]
	s_kills[s] += lost
	s_hull[t] = maxi(s_hull[t], 0)
	# Morale: the share of hull and men lost, raking, a hit at all.
	if hits > 0:
		var dm := (hull0 - s_hull[t]) * 100 / s_hull0[t] / 2 + lost * 150 / maxi(s_crew0[t], 1) + (3 if rake else 0) + 1
		s_mor[t] -= dm
		s_hit_t[t] = tick
	if s_hull[t] == 0:
		_sink(t)
	s_rl[i] = ST.stat(ty, "reload") * 10 * 1000
	s_ld[i] = s_shot[s]
	stats["broadsides"] = int(stats["broadsides"]) + 1
	stats["hits"] = int(stats["hits"]) + hits
	_event(EV_BROADSIDE, s, k, t, hits, shot)


func _sink(s: int) -> void:
	if u_state[s] == S_SUNK:
		return
	if s_grap[s] >= 0:
		_ungrapple(s_grap[s] if s_boarder[s] == 0 else s)
	u_state[s] = S_SUNK
	s_end_t[s] = tick
	s_spd[s] = 0
	s_burn[s] = 0
	stats["sunk"] = int(stats["sunk"]) + 1
	_event(EV_SINK, s, 0, -1, 0, 0)
	_shock(s, 12)


## Friends of ship s within 500 m lose heart.
func _shock(s: int, n: int) -> void:
	for f in n_units:
		if f != s and u_side[f] == u_side[s] and u_state[f] == S_SAIL:
			if FM.approx_len(s_x[f] - s_x[s], s_y[f] - s_y[s]) < 500 * U:
				s_mor[f] -= n


# ------------------------------------------------------------ fire, morale ---

func _fires() -> void:
	for s in n_units:
		if s_burn[s] == 0:
			continue
		if u_state[s] == S_SUNK or u_state[s] == S_FLED:
			s_burn[s] = 0
			continue
		s_burn[s] += 10
		s_hull[s] = maxi(s_hull[s] - maxi(s_hull0[s] / 150, 1), 0)
		if s_hull[s] == 0:
			_sink(s)
			continue
		if _roll(1000) < MAGAZINE_PM + (MAGAZINE_PM if s_burn[s] > 300 else 0):
			_blast(s)
			continue
		var put_out := EXTINGUISH_PCT * s_crew[s] / maxi(s_crew0[s], 1)
		if u_state[s] == S_TAKEN:
			put_out = 30
		if _roll(100) < put_out:
			s_burn[s] = 0


## The magazine goes up: she is gone, her neighbours scorched (and fired).
func _blast(s: int) -> void:
	s_blown[s] = 1
	stats["blown"] = int(stats["blown"]) + 1
	_event(EV_BLAST, s, 0, -1, 0, 0)
	s_hull[s] = 0
	s_crew[s] = s_crew[s] / 10
	s_troops[s] = s_troops[s] / 10
	_sink(s)
	for f in n_units:
		if f == s or u_state[f] == S_SUNK or u_state[f] == S_FLED:
			continue
		var d := FM.approx_len(s_x[f] - s_x[s], s_y[f] - s_y[s]) / U
		if d >= BLAST_M:
			continue
		s_hull[f] = maxi(s_hull[f] - 140 * (BLAST_M - d) / BLAST_M, 0)
		_lose_men(f, s_crew[f] * (BLAST_M - d) / BLAST_M / 6)
		s_mor[f] -= 20
		if s_burn[f] == 0 and _roll(100) < 50:
			s_burn[f] = 1
			stats["fires"] = int(stats["fires"]) + 1
		if s_hull[f] == 0:
			_sink(f)


func _morale() -> void:
	if decided_tick >= 0:
		return
	for s in n_units:
		if u_state[s] != S_SAIL:
			continue
		if tick - s_hit_t[s] > 80 and s_mor[s] < 100:
			s_mor[s] += 1
		if s_grap[s] >= 0 and s_boarder[s] != 0:
			continue
		var crew_pct := s_crew[s] * 100 / maxi(s_crew0[s], 1)
		var hull_pct := s_hull[s] * 100 / s_hull0[s]
		var near := _enemy_within(s, 400)
		if s_mor[s] <= 0 or (near and (crew_pct < 18 or (hull_pct < 12 and s_rig[s] * 100 / s_rig0[s] < 25))):
			_strike(s)


func _enemy_within(s: int, m: int) -> bool:
	for e in n_units:
		if u_side[e] != u_side[s] and u_state[e] == S_SAIL:
			if FM.approx_len(s_x[e] - s_x[s], s_y[e] - s_y[s]) < m * U:
				return true
	return false


func _strike(s: int) -> void:
	if s_grap[s] >= 0:
		_ungrapple(s_grap[s] if s_boarder[s] == 0 else s)
	u_state[s] = S_STRUCK
	s_end_t[s] = tick
	s_sail[s] = 0
	s_mode[s] = M_FREE
	stats["struck"] = int(stats["struck"]) + 1
	_event(EV_STRIKE, s, 0, -1, 0, 0)
	_shock(s, 8)


# ----------------------------------------------------------------- decide ---

func fighting(side: int) -> int:
	var n := 0
	for s in n_units:
		if u_side[s] == side and u_state[s] == S_SAIL:
			n += 1
	return n


## Fighting power left on a side (hull x guns of its fighting ships, by
## their crews).
func power(side: int) -> int:
	var p := 0
	for s in n_units:
		if u_side[s] == side and u_state[s] == S_SAIL:
			p += (ST.stat(s_type[s], "guns") * 10 + s_hull[s] / 10) * (s_hull[s] * 100 / s_hull0[s] + s_crew[s] * 100 /
				maxi(s_crew0[s], 1)) / 200
	return p


func _decide() -> void:
	if decided_tick >= 0:
		if ended == 0 and tick >= decided_tick + END_TICKS:
			ended = 1
		return
	var f0 := fighting(0)
	var f1 := fighting(1)
	var w := -1
	if f0 == 0 or f1 == 0:
		w = 0 if f0 > 0 else 1
	elif tick >= time_limit:
		w = 0 if power(0) > power(1) else 1
	if w < 0:
		return
	winner = w
	decided_tick = tick
	for s in n_units:
		if u_state[s] == S_STRUCK and u_side[s] != w:
			u_state[s] = S_TAKEN
			s_by[s] = w
			_event(EV_TAKEN, -1, 0, s, 0, 0)
		elif u_state[s] == S_STRUCK:
			u_state[s] = S_SAIL  # her own side held the field: the colours go up again
			s_mode[s] = M_FREE
			s_mor[s] = maxi(s_mor[s], 40)
		if s_grap[s] >= 0 and s_boarder[s] != 0:
			_ungrapple(s)


# --------------------------------------------------------------------- AI ---

## The battle AI's decision for ship s (see the header).
func _think(s: int) -> void:
	if s_grap[s] >= 0:
		return
	var crew_pct := s_crew[s] * 100 / maxi(s_crew0[s], 1)
	var hull_pct := s_hull[s] * 100 / s_hull0[s]
	if s_mode[s] == M_FLEE:
		return
	var mine := power(u_side[s])
	var theirs := power(1 - u_side[s])
	var outgunned := theirs > mine * 3 and (hull_pct < 75 or crew_pct < 75)
	if ((hull_pct < 28 or crew_pct < 32 or s_mor[s] < 22) and theirs * 10 > mine * 12) or outgunned:
		s_mode[s] = M_FLEE
		s_flee_x[s] = -1
		s_sail[s] = 2
		return
	# Target: near and weak; keep the current one unless another is much better.
	var best := -1
	var bs := 1 << 40
	var cur_score := 1 << 40
	for t in n_units:
		if u_side[t] == u_side[s] or u_state[t] != S_SAIL:
			continue
		var d := FM.approx_len(s_x[t] - s_x[s], s_y[t] - s_y[s]) / U
		var sc := d + s_hull[t] * 300 / s_hull0[t]
		if t == s_tgt[s]:
			cur_score = sc
		if sc < bs:
			bs = sc
			best = t
	if best < 0:
		s_mode[s] = M_FREE
		return
	if s_tgt[s] >= 0 and cur_score < (1 << 40) and cur_score <= bs + 150:
		best = s_tgt[s]
	var t2 := best
	var dist := FM.approx_len(s_x[t2] - s_x[s], s_y[t2] - s_y[s]) / U
	# Board when much stronger in men (and close, or she is crippled).
	var my_b := s_crew[s] * s_bq[s] / 100 + s_troops[s] * 12 / 10
	var her_b := (s_crew[t2] * s_bq[t2] / 100 + s_troops[t2] * 12 / 10) * DECK_BONUS_PCT / 100
	# Friends already going for her board with us (a swarm of sloops).
	for f in n_units:
		if f != s and u_side[f] == u_side[s] and u_state[f] == S_SAIL and s_tgt[f] == t2 \
				and (s_mode[f] == M_BOARD or s_grap[f] == t2):
			my_b += s_crew[f] * s_bq[f] / 100 + s_troops[f] * 12 / 10
	var crippled := s_rig[t2] * 100 / s_rig0[t2] < 40 or s_spd[t2] < _vmax(t2) / 4
	var runs := s_mode[t2] == M_FLEE and s_spd[t2] * 10 >= s_spd[s] * 9
	if my_b * 100 > her_b * 160 and not runs and (dist < 260 or crippled or ST.stat(s_type[s], "oars") != 0):
		if s_mode[s] != M_BOARD or s_tgt[s] != t2:
			s_mode[s] = M_BOARD
			s_tgt[s] = t2
			s_tack[s] = 0
			s_tdir[s] = 0
		return
	if s_mode[s] != M_ENGAGE or s_tgt[s] != t2:
		s_mode[s] = M_ENGAGE
		s_tgt[s] = t2
		s_tack[s] = 0
		s_tdir[s] = 0
	s_fire[s] = 1
	s_sail[s] = 1 if dist < 320 else 2
	# Shot: grape close, chain to cripple a ship it means to board, else round.
	if dist < shot_range(s, ST.SHOT_GRAPE) * 9 / 10 and s_crew[t2] * 100 / maxi(s_crew0[t2], 1) > 35:
		s_shot[s] = ST.SHOT_GRAPE
	elif s_bq[s] >= 110 and s_rig[t2] * 100 / s_rig0[t2] > 50 and my_b * 100 > her_b * 90 \
			and dist < shot_range(s, ST.SHOT_CHAIN) * 105 / 100:
		s_shot[s] = ST.SHOT_CHAIN
	else:
		s_shot[s] = ST.SHOT_ROUND


# ----------------------------------------------------------------- events ---

func _event(k: int, a: int, b: int, c: int, d: int, e: int) -> void:
	var i := ev_n % EV_CAP
	ev_t[i] = tick
	ev_k[i] = k
	ev_a[i] = a
	ev_b[i] = b
	ev_c[i] = c
	ev_d[i] = d
	ev_e[i] = e
	ev_n += 1


# ----------------------------------------------------------------- result ---

func is_decided() -> bool:
	return decided_tick >= 0


func result() -> Dictionary:
	var units: Array = []
	var sides: Array = []
	for sd in 2:
		sides.append({"side": sd, "ships": 0, "fighting": 0, "sunk": 0, "taken": 0, "struck": 0, "fled": 0,
			"crew0": 0, "crew": 0, "kills": 0})
	for s in n_units:
		var r := {"unit": s, "side": u_side[s], "ship": str(ST.row(s_type[s])["key"]), "hull": s_hull[s],
			"hull0": s_hull0[s], "crew": s_crew[s], "crew0": s_crew0[s], "rig": s_rig[s], "rig0": s_rig0[s],
			"troops": s_troops[s], "state": u_state[s], "by": s_by[s], "kills": s_kills[s], "blown": s_blown[s]}
		units.append(r)
		var t: Dictionary = sides[u_side[s]]
		t["ships"] = int(t["ships"]) + 1
		t["crew0"] = int(t["crew0"]) + s_crew0[s]
		t["crew"] = int(t["crew"]) + s_crew[s]
		t["kills"] = int(t["kills"]) + s_kills[s]
		match u_state[s]:
			S_SAIL:
				t["fighting"] = int(t["fighting"]) + 1
			S_SUNK:
				t["sunk"] = int(t["sunk"]) + 1
			S_TAKEN:
				t["taken"] = int(t["taken"]) + 1
			S_STRUCK:
				t["struck"] = int(t["struck"]) + 1
			S_FLED:
				t["fled"] = int(t["fled"]) + 1
	return {"sea": 1, "winner": winner, "decided_tick": decided_tick, "ended": ended, "tick": tick, "units": units,
		"sides": sides}


# --------------------------------------------------------------- snapshot ---

const _SNAP_SKIP := {"g": true, "g_w": true, "g_h": true}
const _SNAP_MAGIC := 0x31414553  # "SEA1"


func snapshot() -> PackedByteArray:
	var d := {}
	for p in get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var nm: String = p["name"]
		if _SNAP_SKIP.has(nm):
			continue
		d[nm] = get(nm)
	var raw := var_to_bytes(d)
	var z := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var out := PackedByteArray()
	out.resize(8)
	out.encode_u32(0, _SNAP_MAGIC)
	out.encode_u32(4, raw.size())
	out.append_array(z)
	return out


func restore(blob: PackedByteArray) -> bool:
	if blob.size() < 8 or blob.decode_u32(0) != _SNAP_MAGIC:
		return false
	var raw_size := blob.decode_u32(4)
	if raw_size <= 0 or raw_size > 64 << 20:
		return false
	var raw := blob.slice(8).decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != raw_size:
		return false
	var v = bytes_to_var(raw)
	if not (v is Dictionary):
		return false
	var d: Dictionary = v
	for k in ["n_units", "ter_hash", "field_w", "field_h", "seed_value"]:
		if not d.has(k) or int(d[k]) != int(get(k)):
			return false
	var names := {}
	for p in get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			names[p["name"]] = true
	for k in d:
		if not names.has(k) or typeof(d[k]) != typeof(get(k)):
			return false
	for k in d:
		set(k, d[k])
	return true


## 32-bit hash of the whole sea battle state.
func state_hash() -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	var head := PackedInt64Array([tick, rng_state, winner, decided_tick, ended, n_units, w_base, w_from, w_goal,
		w_str, ter_hash, time_limit, field_w, field_h, deck_on])
	ctx.update(head.to_byte_array())
	for nm in SHIP_ARRAYS:
		ctx.update((get(nm) as PackedInt32Array).to_byte_array())
	ctx.update(s_ld.to_byte_array())
	ctx.update(s_rl.to_byte_array())
	ctx.update(ai_sides.to_byte_array())
	return ctx.finish().decode_u32(0)
