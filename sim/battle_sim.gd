extends RefCounted
## Deterministic per-soldier battle simulation (milestone 1: infantry melee
## and morale).
##
## Rules this file must keep (see CLAUDE.md and docs/DESIGN.md section 5):
## - Integers only. No float appears in state or logic, including setup.
## - Own seeded RNG (xorshift32, explicitly masked to 32 bits).
## - Fixed iteration order: soldiers and units are always visited by index;
##   no Dictionary ordering or object ids are relied on.
## - No per-soldier objects: soldiers are struct-of-arrays in packed arrays.
##
## Public API:
##   setup(scenario: Dictionary, seed: int)
##   queue_order(order: Dictionary)   # plain data, ints only, has "tick"
##   step()                           # advance one 10 Hz tick
##   state_hash() -> int              # 32-bit hash of the full sim state
##   read access to the packed arrays below (view must not write them).
##
## Coordinates: 1 m = 1024 units, x right, y down. Angles 0..1023, 0 = +x,
## increasing clockwise on screen (towards +y). See fixed_math.gd.

const FM := preload("res://sim/fixed_math.gd")
const UT := preload("res://sim/unit_types.gd")
const BattleAI := preload("res://sim/battle_ai.gd")

const TICKS_PER_SECOND := 10
const M := 1024  # sim units per metre

# Soldier states.
const S_FORMED := 0     # following its formation slot
const S_FIGHTING := 1   # has a melee target
const S_ROUTING := 2    # fleeing
const S_DEAD := 3
const S_DOWN := 4       # reserved: knocked down (cavalry, milestone 2)

# Unit states.
const U_READY := 0
const U_ROUTING := 1
const U_DESTROYED := 2

# Unit orders (current standing order of a unit).
const O_NONE := 0
const O_MOVE := 1
const O_ATTACK := 2

# Order types for queue_order().
const ORDER_MOVE := 1     # unit, x, y, facing, width, run
const ORDER_ATTACK := 2   # unit, target, run
const ORDER_HALT := 3     # unit
const ORDER_RUN := 4      # unit, run

# Formation geometry.
const FILE_SPACING := 1126  # 1.1 m between files
const RANK_SPACING := 1331  # 1.3 m between ranks
const MIN_FILES := 4
const REFORM_IN_PLACE_DIST := 12 * M  # shorter moves snap the anchor

# Combat geometry.
const CONTACT_MARGIN := 12 * M   # unit bboxes closer than this are "in contact"
const SEARCH_FRONT := 8 * M      # front rank looks this far for enemies
const SEARCH_REAR := 5 * M / 2   # other ranks only react to close enemies
const TARGET_KEEP_EXTRA := 2 * M
const SEPARATION := 717          # 0.7 m: friendly fighters push apart
const CATCH_UP_DIST := 3 * M     # soldiers further than this from slot run
const GRID_SHIFT := 12           # 4 m cells (4096 units)

# Melee.
const BASE_HIT := 35
const FLANK_BONUS := 15
const REAR_BONUS := 30
const FRONT_ARC := 170           # +-60 degrees
const REAR_ARC := 341            # beyond +-120 degrees is rear

# Morale (0..1000).
const MORALE_MAX := 1000
const MORALE_LOSS_PER_DEATH_TOTAL := 1200  # spread over the unit's start size
const MORALE_FLANK_HIT := 3                # per hit landing on the unit's flank
const MORALE_REAR_HIT := 5                 # per hit landing on the unit's rear
const MORALE_ROUTING_FRIEND := 15          # per routing friend nearby, per second
const MAX_ROUTING_FRIENDS := 2             # cap on friends counted
const ROUTING_FRIEND_RANGE := 40 * M
const MORALE_RECOVER := 2                  # per tick when not engaged
const ROUT_THRESHOLD := 100
const RALLY_THRESHOLD := 450
const RALLY_SAFE_RANGE := 50 * M
const MAX_ROUTS := 1                       # a unit rallies once; the next rout is final

# ---------------------------------------------------------------- state ---

var tick: int = 0
var seed_value: int = 0
var rng_state: int = 1
var field_w: int = 0
var field_h: int = 0
var ai_sides: PackedInt32Array = PackedInt32Array([0, 0])  # 1 = AI controls side
var winner: int = -1  # -1 undecided, else winning side

# Soldiers (struct of arrays).
var n: int = 0
var pos_x := PackedInt32Array()
var pos_y := PackedInt32Array()
var prev_x := PackedInt32Array()
var prev_y := PackedInt32Array()
var facing := PackedInt32Array()
var hp := PackedInt32Array()
var state := PackedInt32Array()
var cooldown := PackedInt32Array()
var unit_of := PackedInt32Array()
var slot_of := PackedInt32Array()
var target := PackedInt32Array()

# Units (struct of arrays).
var n_units: int = 0
var u_side := PackedInt32Array()
var u_type := PackedInt32Array()
var u_count0 := PackedInt32Array()
var u_alive := PackedInt32Array()
var u_state := PackedInt32Array()
var u_morale := PackedInt32Array()
var u_routs := PackedInt32Array()
var u_files := PackedInt32Array()
var u_ax := PackedInt32Array()      # formation anchor = front centre
var u_ay := PackedInt32Array()
var u_face := PackedInt32Array()
var u_order := PackedInt32Array()
var u_dx := PackedInt32Array()      # move destination (front centre)
var u_dy := PackedInt32Array()
var u_dface := PackedInt32Array()
var u_target := PackedInt32Array()
var u_run := PackedInt32Array()
var u_slot_base := PackedInt32Array()
var u_contact := PackedInt32Array()
var u_fighting := PackedInt32Array()  # soldiers fighting last tick
var u_settled := PackedInt32Array()   # every soldier at its slot and idle
var u_dirty := PackedInt32Array()     # slot offsets need recomputing
var u_cx := PackedInt32Array()        # centroid and bbox of living soldiers
var u_cy := PackedInt32Array()
var u_minx := PackedInt32Array()
var u_miny := PackedInt32Array()
var u_maxx := PackedInt32Array()
var u_maxy := PackedInt32Array()
var u_flee_x := PackedInt32Array()    # Q12 unit vector
var u_flee_y := PackedInt32Array()
var slot_soldier := PackedInt32Array()  # u_slot_base[u] + slot -> soldier
var off_x := PackedInt32Array()         # u_slot_base[u] + slot -> offset
var off_y := PackedInt32Array()

# Unit type stats copied out of UnitTypes for fast indexed access.
var t_attack := PackedInt32Array()
var t_defence := PackedInt32Array()
var t_armour := PackedInt32Array()
var t_shield := PackedInt32Array()
var t_damage := PackedInt32Array()
var t_reach := PackedInt32Array()
var t_mass := PackedInt32Array()
var t_walk := PackedInt32Array()
var t_run := PackedInt32Array()
var t_hp := PackedInt32Array()
var t_cooldown := PackedInt32Array()
var t_morale := PackedInt32Array()

# Spatial grid, one per side so target search only walks enemies.
var grid_w: int = 0
var grid_h: int = 0
var grid_head0 := PackedInt32Array()
var grid_head1 := PackedInt32Array()
var grid_next := PackedInt32Array()

# Orders waiting for their tick. Each is a Dictionary of ints.
var pending_orders: Array = []
var _order_seq: int = 0

# Diagnostics (not part of the hashed state).
var stat_attacks: int = 0
var stat_searches: int = 0
var stat_grid_soldiers: int = 0


# ---------------------------------------------------------------- setup ---

## scenario = {
##   "width_m": int, "height_m": int,
##   "ai_sides": [side, ...],
##   "units": [{"side", "type", "count", "x_m", "y_m", "facing", "files"}, ...]
## }  x_m/y_m is the front centre of the unit in metres.
func setup(scenario: Dictionary, p_seed: int) -> void:
	seed_value = p_seed
	rng_state = ((p_seed & 0x7FFFFFFF) * 48271 + 0x2545F491) & 0xFFFFFFFF
	if rng_state == 0:
		rng_state = 0x1234567
	tick = 0
	winner = -1
	pending_orders = []
	_order_seq = 0
	field_w = int(scenario["width_m"]) * M
	field_h = int(scenario["height_m"]) * M
	ai_sides = PackedInt32Array([0, 0])
	for s in scenario.get("ai_sides", []):
		ai_sides[int(s)] = 1

	_load_types()

	var units: Array = scenario["units"]
	n_units = units.size()
	var total := 0
	for ud in units:
		total += int(ud["count"])
	n = total

	for arr in _soldier_arrays():
		arr.resize(n)
	for arr in _unit_arrays():
		arr.resize(n_units)
		arr.fill(0)
	slot_soldier.resize(n)
	off_x.resize(n)
	off_y.resize(n)
	target.fill(-1)

	var base := 0
	for u in n_units:
		var ud: Dictionary = units[u]
		var ty := int(ud["type"])
		var cnt := int(ud["count"])
		u_side[u] = int(ud["side"])
		u_type[u] = ty
		u_count0[u] = cnt
		u_alive[u] = cnt
		u_state[u] = U_READY
		u_morale[u] = t_morale[ty]
		u_files[u] = clampi(int(ud.get("files", 20)), 1, cnt)
		u_ax[u] = int(ud["x_m"]) * M
		u_ay[u] = int(ud["y_m"]) * M
		u_face[u] = int(ud["facing"]) & FM.ANGLE_MASK
		u_dface[u] = u_face[u]
		u_target[u] = -1
		u_order[u] = O_NONE
		u_slot_base[u] = base
		u_dirty[u] = 1
		_compute_offsets(u)
		for s in cnt:
			var i := base + s
			unit_of[i] = u
			slot_of[i] = s
			slot_soldier[base + s] = i
			# Small deterministic jitter so ranks do not look ruled.
			pos_x[i] = u_ax[u] + off_x[base + s] + _rand() % 205 - 102
			pos_y[i] = u_ay[u] + off_y[base + s] + _rand() % 205 - 102
			facing[i] = u_face[u]
			hp[i] = t_hp[ty]
			state[i] = S_FORMED
			cooldown[i] = 1 + _rand() % t_cooldown[ty]
			target[i] = -1
		base += cnt

	prev_x = pos_x.duplicate()
	prev_y = pos_y.duplicate()
	grid_w = (field_w >> GRID_SHIFT) + 1
	grid_h = (field_h >> GRID_SHIFT) + 1
	grid_head0.resize(grid_w * grid_h)
	grid_head1.resize(grid_w * grid_h)
	grid_next.resize(n)
	_update_bounds()


func _soldier_arrays() -> Array:
	return [pos_x, pos_y, prev_x, prev_y, facing, hp, state, cooldown, unit_of,
		slot_of, target]


func _unit_arrays() -> Array:
	return [u_side, u_type, u_count0, u_alive, u_state, u_morale, u_routs,
		u_files, u_ax, u_ay, u_face, u_order, u_dx, u_dy, u_dface, u_target,
		u_run, u_slot_base, u_contact, u_fighting, u_settled, u_dirty, u_cx,
		u_cy, u_minx, u_miny, u_maxx, u_maxy, u_flee_x, u_flee_y]


func _load_types() -> void:
	var nt := UT.TYPES.size()
	var arrays := [t_attack, t_defence, t_armour, t_shield, t_damage, t_reach,
		t_mass, t_walk, t_run, t_hp, t_cooldown, t_morale]
	var keys := ["attack", "defence", "armour", "shield", "damage", "reach",
		"mass", "walk", "run", "hp", "cooldown", "morale"]
	for k in arrays.size():
		var arr: PackedInt32Array = arrays[k]
		arr.resize(nt)
		for t in nt:
			arr[t] = int(UT.TYPES[t][keys[k]])


# ------------------------------------------------------------------ rng ---

func _rand() -> int:
	var x := rng_state
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	rng_state = x
	return x


# --------------------------------------------------------------- orders ---

static func make_move_order(p_tick: int, unit: int, x: int, y: int, face: int,
		width: int, run: int) -> Dictionary:
	return {"tick": p_tick, "type": ORDER_MOVE, "unit": unit, "x": x, "y": y,
		"facing": face, "width": width, "run": run}


static func make_attack_order(p_tick: int, unit: int, target_unit: int, run: int) -> Dictionary:
	return {"tick": p_tick, "type": ORDER_ATTACK, "unit": unit,
		"target": target_unit, "run": run}


static func make_halt_order(p_tick: int, unit: int) -> Dictionary:
	return {"tick": p_tick, "type": ORDER_HALT, "unit": unit}


static func make_run_order(p_tick: int, unit: int, run: int) -> Dictionary:
	return {"tick": p_tick, "type": ORDER_RUN, "unit": unit, "run": run}


## Queue an order. Orders are applied at the start of order["tick"] (or the
## next step if that tick has passed). Within a tick they apply in order of
## (player, seq); "player" defaults to 0 and "seq" to a local counter. For
## lockstep both peers must supply the same player/seq values.
func queue_order(order: Dictionary) -> void:
	# Orders are plain data: force every value to int so a float that slipped
	# in from the view can never reach sim state.
	var o := {}
	for k in order:
		o[k] = int(order[k])
	if not o.has("player"):
		o["player"] = 0
	if not o.has("seq"):
		o["seq"] = _order_seq
		_order_seq += 1
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
		_apply_order(o)


func _apply_order(o: Dictionary) -> void:
	var u := int(o.get("unit", -1))
	if u < 0 or u >= n_units or u_state[u] != U_READY:
		return
	var typ := int(o["type"])
	if typ == ORDER_MOVE:
		var x := clampi(int(o["x"]), 0, field_w)
		var y := clampi(int(o["y"]), 0, field_h)
		var face := int(o["facing"]) & FM.ANGLE_MASK
		var files := width_to_files(int(o["width"]), u_alive[u])
		u_run[u] = 1 if int(o.get("run", 0)) != 0 else 0
		u_target[u] = -1
		var dx := x - u_ax[u]
		var dy := y - u_ay[u]
		if dx * dx + dy * dy <= REFORM_IN_PLACE_DIST * REFORM_IN_PLACE_DIST:
			u_ax[u] = x
			u_ay[u] = y
			u_face[u] = face
			u_order[u] = O_NONE
		else:
			u_order[u] = O_MOVE
			u_dx[u] = x
			u_dy[u] = y
		u_dface[u] = face
		if files != u_files[u]:
			u_files[u] = files
		u_dirty[u] = 1
		u_settled[u] = 0
	elif typ == ORDER_ATTACK:
		var t := int(o["target"])
		if t < 0 or t >= n_units or u_side[t] == u_side[u] or u_state[t] == U_DESTROYED:
			return
		u_order[u] = O_ATTACK
		u_target[u] = t
		u_run[u] = 1 if int(o.get("run", 0)) != 0 else 0
		u_settled[u] = 0
	elif typ == ORDER_HALT:
		u_order[u] = O_NONE
		u_target[u] = -1
		u_settled[u] = 0
	elif typ == ORDER_RUN:
		u_run[u] = 1 if int(o.get("run", 0)) != 0 else 0
		u_settled[u] = 0


# ------------------------------------------------------------ formation ---

## Number of files for a requested frontage (sim units).
static func width_to_files(width: int, alive: int) -> int:
	var f := (width + FILE_SPACING / 2) / FILE_SPACING
	return clampi(f, mini(MIN_FILES, maxi(alive, 1)), maxi(alive, 1))


## Offsets (interleaved x, y) of `count` slots relative to the front-centre
## anchor for a formation with `files` files facing `face`. Rows fill from
## the front; the last, partial rank is centred.
static func formation_offsets(count: int, files: int, face: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(count * 2)
	_fill_offsets(out, 0, count, files, face, true)
	return out


static func _fill_offsets(out: PackedInt32Array, base: int, count: int, files: int,
		face: int, interleaved: bool, out_y: PackedInt32Array = PackedInt32Array()) -> void:
	files = maxi(files, 1)
	var c := FM.cos_a(face)
	var s := FM.sin_a(face)
	var full_ranks := count / files
	var last := count - full_ranks * files
	for slot in count:
		var rank := slot / files
		var file := slot - rank * files
		var k := files
		if rank == full_ranks:
			k = last
		var lat := ((2 * file - (k - 1)) * FILE_SPACING) / 2
		var back := rank * RANK_SPACING
		# forward = (c, s), right = (-s, c); offset = lat * right - back * forward
		var ox := (-back * c - lat * s) >> FM.TRIG_SHIFT
		var oy := (-back * s + lat * c) >> FM.TRIG_SHIFT
		if interleaved:
			out[base + slot * 2] = ox
			out[base + slot * 2 + 1] = oy
		else:
			out[base + slot] = ox
			out_y[base + slot] = oy


func _compute_offsets(u: int) -> void:
	var alive := u_alive[u]
	if alive <= 0:
		return
	var files := mini(u_files[u], alive)
	_fill_offsets(off_x, u_slot_base[u], alive, files, u_face[u], false, off_y)
	u_dirty[u] = 0


## Depth (front to back) of a unit's formation in sim units.
func unit_depth(u: int) -> int:
	var files := maxi(mini(u_files[u], u_alive[u]), 1)
	var ranks := (u_alive[u] + files - 1) / files
	return maxi(ranks - 1, 0) * RANK_SPACING


# ----------------------------------------------------------------- step ---

func step() -> void:
	_apply_orders()
	BattleAI.think(self)
	_apply_orders()  # AI orders are queued for this tick
	prev_x = pos_x.duplicate()
	prev_y = pos_y.duplicate()
	_update_units()
	_update_contacts()
	_build_grid()
	_update_soldiers()
	_refresh_offsets()
	_update_morale()
	_check_winner()
	tick += 1


func _update_units() -> void:
	for u in n_units:
		if u_state[u] != U_READY:
			continue
		var ty := u_type[u]
		var speed := t_run[ty] if u_run[u] != 0 else t_walk[ty]
		var aspeed := (speed * 7) >> 3
		var order := u_order[u]
		if order == O_MOVE:
			var dx := u_dx[u] - u_ax[u]
			var dy := u_dy[u] - u_ay[u]
			var d := FM.isqrt(dx * dx + dy * dy)
			if d <= aspeed:
				u_ax[u] = u_dx[u]
				u_ay[u] = u_dy[u]
				u_order[u] = O_NONE
				if u_face[u] != u_dface[u]:
					u_face[u] = u_dface[u]
					u_dirty[u] = 1
			else:
				u_ax[u] += dx * aspeed / d
				u_ay[u] += dy * aspeed / d
				# March facing the direction of travel; turn to the final
				# facing for the last stretch.
				var want := FM.atan2_a(dy, dx) if d > REFORM_IN_PLACE_DIST else u_dface[u]
				if absi(FM.angle_diff(u_face[u], want)) > 3:
					u_face[u] = want
					u_dirty[u] = 1
		elif order == O_ATTACK:
			var t := u_target[u]
			if t < 0 or u_state[t] == U_DESTROYED:
				u_order[u] = O_NONE
				u_target[u] = -1
			elif u_fighting[u] == 0 or u_state[t] == U_ROUTING:
				var dx := u_cx[t] - u_ax[u]
				var dy := u_cy[t] - u_ay[u]
				var d := FM.isqrt(dx * dx + dy * dy)
				if d > 0:
					var hw := (u_maxx[t] - u_minx[t]) >> 1
					var hh := (u_maxy[t] - u_miny[t]) >> 1
					var ext := (absi(dx) * hw + absi(dy) * hh) / d
					var stop := ext + M
					if d > stop:
						var mv := mini(aspeed, d - stop)
						u_ax[u] += dx * mv / d
						u_ay[u] += dy * mv / d
					var want := FM.atan2_a(dy, dx)
					if absi(FM.angle_diff(u_face[u], want)) > 3:
						u_face[u] = want
						u_dirty[u] = 1
		u_ax[u] = clampi(u_ax[u], 0, field_w)
		u_ay[u] = clampi(u_ay[u], 0, field_h)
		if u_dirty[u] != 0:
			_compute_offsets(u)
			u_settled[u] = 0
		if order != O_NONE:
			u_settled[u] = 0


func _update_contacts() -> void:
	for u in n_units:
		u_contact[u] = 0
	for a in n_units:
		if u_state[a] == U_DESTROYED:
			continue
		var sa := u_side[a]
		var ax0 := u_minx[a] - CONTACT_MARGIN
		var ax1 := u_maxx[a] + CONTACT_MARGIN
		var ay0 := u_miny[a] - CONTACT_MARGIN
		var ay1 := u_maxy[a] + CONTACT_MARGIN
		for b in range(a + 1, n_units):
			if u_side[b] == sa or u_state[b] == U_DESTROYED:
				continue
			if u_maxx[b] < ax0 or u_minx[b] > ax1 or u_maxy[b] < ay0 or u_miny[b] > ay1:
				continue
			# Two routing units do not need the grid for each other.
			if u_state[a] == U_ROUTING and u_state[b] == U_ROUTING:
				continue
			u_contact[a] = 1
			u_contact[b] = 1
	for u in n_units:
		if u_contact[u] != 0:
			u_settled[u] = 0


func _build_grid() -> void:
	grid_head0.fill(-1)
	grid_head1.fill(-1)
	var gs := GRID_SHIFT
	var gw := grid_w
	var gmax := grid_w * grid_h - 1
	var cnt := 0
	for u in n_units:
		if u_contact[u] == 0:
			continue
		var head: PackedInt32Array = grid_head0 if u_side[u] == 0 else grid_head1
		var base := u_slot_base[u]
		for s in u_alive[u]:
			var i := slot_soldier[base + s]
			var c := clampi((pos_y[i] >> gs) * gw + (pos_x[i] >> gs), 0, gmax)
			grid_next[i] = head[c]
			head[c] = i
			cnt += 1
	stat_grid_soldiers = cnt


func _update_soldiers() -> void:
	# Hot loop. Iterates unit by unit, slot by slot (a fixed order), with all
	# per-unit values hoisted into typed locals. Settled units are skipped
	# outright; units not near an enemy take a tight slot-following path.
	var px := pos_x
	var py := pos_y
	var fc := facing
	var st := state
	var ss := slot_soldier
	var oxs := off_x
	var oys := off_y
	var fw := field_w
	var fh := field_h
	var shift := FM.TRIG_SHIFT
	for u in n_units:
		var alive := u_alive[u]
		if alive <= 0 or u_settled[u] != 0:
			continue
		var base := u_slot_base[u]
		var ty := u_type[u]
		var walk := t_walk[ty]
		var run := t_run[ty]
		var face := u_face[u]
		if u_state[u] == U_ROUTING:
			var rs := (run * 7) >> 3
			var flx := u_flee_x[u]
			var fly := u_flee_y[u]
			var rminx := fw
			var rmaxx := 0
			var rminy := fh
			var rmaxy := 0
			var rsx := 0
			var rsy := 0
			for s in alive:
				var i := ss[base + s]
				var jitter := ((i * 37) & 15) - 7  # per-soldier spread
				var fx := flx - fly * jitter / 24
				var fy := fly + flx * jitter / 24
				var x := clampi(px[i] + ((fx * rs) >> shift), 0, fw)
				var y := clampi(py[i] + ((fy * rs) >> shift), 0, fh)
				px[i] = x
				py[i] = y
				fc[i] = FM.atan2_a(fy, fx)
				rsx += x
				rsy += y
				rminx = mini(rminx, x)
				rmaxx = maxi(rmaxx, x)
				rminy = mini(rminy, y)
				rmaxy = maxi(rmaxy, y)
			_set_bounds(u, rsx / alive, rsy / alive, rminx, rminy, rmaxx, rmaxy)
			continue

		var ax := u_ax[u]
		var ay := u_ay[u]
		var spd_formed := run if u_run[u] != 0 else walk
		var moved := 0

		var minx := fw
		var maxx := 0
		var miny := fh
		var maxy := 0
		var sumx := 0
		var sumy := 0
		if u_contact[u] == 0:
			# Fast path: slot following only (no separation, no search).
			for s in alive:
				var k := base + s
				var i := ss[k]
				var x := px[i]
				var y := py[i]
				var dx := ax + oxs[k] - x
				var dy := ay + oys[k] - y
				fc[i] = face
				if dx == 0 and dy == 0:
					if st[i] != S_FORMED:
						st[i] = S_FORMED
					sumx += x
					sumy += y
					if x < minx: minx = x
					if x > maxx: maxx = x
					if y < miny: miny = y
					if y > maxy: maxy = y
					continue
				moved += 1
				st[i] = S_FORMED
				# Inline approx_len (alpha max plus beta min).
				var adx := dx if dx >= 0 else -dx
				var ady := dy if dy >= 0 else -dy
				var d: int
				if adx > ady:
					d = adx - (adx >> 5) + ((ady * 3) >> 3) + (ady >> 6)
				else:
					d = ady - (ady >> 5) + ((adx * 3) >> 3) + (adx >> 6)
				var spd := spd_formed if d <= CATCH_UP_DIST else run
				if d <= spd:
					x = clampi(x + dx, 0, fw)
					y = clampi(y + dy, 0, fh)
				else:
					x = clampi(x + dx * spd / d, 0, fw)
					y = clampi(y + dy * spd / d, 0, fh)
				px[i] = x
				py[i] = y
				sumx += x
				sumy += y
				if x < minx: minx = x
				if x > maxx: maxx = x
				if y < miny: miny = y
				if y > maxy: maxy = y
			_set_bounds(u, sumx / alive, sumy / alive, minx, miny, maxx, maxy)
			u_fighting[u] = 0
			if moved == 0 and u_order[u] == O_NONE and u_dirty[u] == 0:
				u_settled[u] = 1
			continue

		# Contact path: target search, melee, separation, slot following.
		var tg := target
		var cd := cooldown
		var gnext := grid_next
		var gs := GRID_SHIFT
		var gw := grid_w
		var gmax := grid_w * grid_h - 1
		var tk := tick
		var files := maxi(u_files[u], 1)
		var reach := t_reach[ty]
		var want := (reach * 3) >> 2
		var half_reach := reach >> 1
		var cool := t_cooldown[ty]
		var enemy_head: PackedInt32Array = grid_head1 if u_side[u] == 0 else grid_head0
		var own_head: PackedInt32Array = grid_head0 if u_side[u] == 0 else grid_head1
		var keep_front := (SEARCH_FRONT + TARGET_KEEP_EXTRA) * (SEARCH_FRONT + TARGET_KEEP_EXTRA)
		var keep_rear := (SEARCH_REAR + TARGET_KEEP_EXTRA) * (SEARCH_REAR + TARGET_KEEP_EXTRA)
		var fighting := 0
		var counted := 0
		# Slots can be reshuffled by deaths inside this loop (gap filling), so
		# walk a snapshot of the slot list.
		var order := ss.slice(base, base + alive)
		for s in alive:
			var i := order[s]
			if st[i] == S_DEAD:
				continue
			var x := px[i]
			var y := py[i]
			var nx := x
			var ny := y
			var front := slot_of[i] < files
			var t := tg[i]
			var lost := false
			if t >= 0:
				if st[t] == S_DEAD:
					t = -1
					lost = true
				else:
					var ddx := px[t] - x
					var ddy := py[t] - y
					if ddx * ddx + ddy * ddy > (keep_front if front else keep_rear):
						t = -1
						lost = true
			if t < 0:
				if lost or (tk + i) % (3 if front else 7) == 0:
					if front:
						t = _find_target(x, y, SEARCH_FRONT, 2, enemy_head)
					else:
						t = _find_target(x, y, SEARCH_REAR, 1, enemy_head)
			tg[i] = t

			if t >= 0:
				# Fighting: close to reach, face the target, swing on cooldown.
				fighting += 1
				st[i] = S_FIGHTING
				var dx := px[t] - x
				var dy := py[t] - y
				var d := FM.approx_len(dx, dy)
				if d > want:
					var step_len := mini(walk, d - want)
					nx = x + dx * step_len / d
					ny = y + dy * step_len / d
				elif d < half_reach and d > 0:
					var back := mini(walk >> 1, half_reach - d)
					nx = x - dx * back / d
					ny = y - dy * back / d
				fc[i] = FM.atan2_a(dy, dx)
				# Keep friendly fighters from stacking (every other tick).
				if ((tk + i) & 1) == 0:
					var c := clampi((ny >> gs) * gw + (nx >> gs), 0, gmax)
					var j := own_head[c]
					var checked := 0
					while j >= 0 and checked < 10:
						if j != i and st[j] != S_DEAD:
							var sx := nx - px[j]
							var sy := ny - py[j]
							if absi(sx) < SEPARATION and absi(sy) < SEPARATION:
								var sd := FM.approx_len(sx, sy)
								if sd < SEPARATION:
									if sd == 0:
										sx = (i & 1) * 2 - 1
										sy = 0
										sd = 1
									var push := (SEPARATION - sd) >> 1
									nx += sx * push / sd
									ny += sy * push / sd
						j = gnext[j]
						checked += 1
				var c2 := cd[i] - 1
				if c2 <= 0:
					if d <= reach:
						_melee(i, t)
						c2 = cool + _rand() % 4
					else:
						c2 = 1 + ((tk + i) & 3)
				cd[i] = c2
			else:
				# Slot following only.
				st[i] = S_FORMED
				var k := base + slot_of[i]
				var dx := ax + oxs[k] - x
				var dy := ay + oys[k] - y
				if dx != 0 or dy != 0:
					var d := FM.approx_len(dx, dy)
					var spd := spd_formed if d <= CATCH_UP_DIST else run
					if d <= spd:
						nx = x + dx
						ny = y + dy
					else:
						nx = x + dx * spd / d
						ny = y + dy * spd / d
				fc[i] = face
			nx = clampi(nx, 0, fw)
			ny = clampi(ny, 0, fh)
			px[i] = nx
			py[i] = ny
			counted += 1
			sumx += nx
			sumy += ny
			if nx < minx: minx = nx
			if nx > maxx: maxx = nx
			if ny < miny: miny = ny
			if ny > maxy: maxy = ny
		u_fighting[u] = fighting
		if counted > 0:
			_set_bounds(u, sumx / counted, sumy / counted, minx, miny, maxx, maxy)


## Nearest living enemy within radius r, scanning (2*cr+1)^2 cells.
func _find_target(x: int, y: int, r: int, cr: int, head: PackedInt32Array) -> int:
	stat_searches += 1
	var gs := GRID_SHIFT
	var cx := x >> gs
	var cy := y >> gs
	var best := -1
	var best_d := r * r + 1
	var px := pos_x
	var py := pos_y
	var st := state
	var nxt := grid_next
	var gw := grid_w
	for gy in range(maxi(cy - cr, 0), mini(cy + cr, grid_h - 1) + 1):
		var row := gy * gw
		for gx in range(maxi(cx - cr, 0), mini(cx + cr, gw - 1) + 1):
			var j := head[row + gx]
			while j >= 0:
				if st[j] != S_DEAD:
					var dx := px[j] - x
					var dy := py[j] - y
					var d2 := dx * dx + dy * dy
					# Tie-break on index so the result never depends on
					# list order.
					if d2 < best_d or (d2 == best_d and j < best):
						best_d = d2
						best = j
				j = nxt[j]
	return best


func _melee(a: int, d: int) -> void:
	stat_attacks += 1
	var ua := unit_of[a]
	var ud := unit_of[d]
	var ta := u_type[ua]
	var td := u_type[ud]
	var from_def := FM.atan2_a(pos_y[a] - pos_y[d], pos_x[a] - pos_x[d])
	var rel := absi(FM.angle_diff(facing[d], from_def))
	var frontal := rel <= FRONT_ARC
	var bonus := 0
	if state[d] == S_ROUTING:
		frontal = false
		bonus = REAR_BONUS
	elif rel > REAR_ARC:
		bonus = REAR_BONUS
	elif not frontal:
		bonus = FLANK_BONUS
	var chance := clampi(BASE_HIT + t_attack[ta] - t_defence[td] + bonus, 5, 95)
	if _rand() % 100 >= chance:
		return
	if frontal and _rand() % 100 < t_shield[td]:
		return
	var dmg := maxi(t_damage[ta] - t_armour[td], 4)
	dmg = dmg * (85 + _rand() % 31) / 100
	# Morale cares whether the *unit* is hit in the flank or rear (relative
	# to the unit's facing), not how an individual duellist is turned.
	if state[d] != S_ROUTING:
		var unit_rel := absi(FM.angle_diff(u_face[ud], from_def))
		if unit_rel > REAR_ARC:
			u_morale[ud] -= MORALE_REAR_HIT
		elif unit_rel > FRONT_ARC:
			u_morale[ud] -= MORALE_FLANK_HIT
	var h := hp[d] - dmg
	if h <= 0:
		_kill(d)
	else:
		hp[d] = h


func _kill(d: int) -> void:
	var u := unit_of[d]
	hp[d] = 0
	state[d] = S_DEAD
	target[d] = -1
	var alive := u_alive[u]
	var base := u_slot_base[u]
	var files := maxi(u_files[u], 1)
	# Fill the gap: the soldier behind steps forward, repeatedly, so the hole
	# ends at the back; then the last slot fills it to keep slots compact.
	var hole := slot_of[d]
	while hole + files < alive:
		var mover := slot_soldier[base + hole + files]
		slot_soldier[base + hole] = mover
		slot_of[mover] = hole
		hole += files
	var last := alive - 1
	if hole != last:
		var mover2 := slot_soldier[base + last]
		slot_soldier[base + hole] = mover2
		slot_of[mover2] = hole
	slot_soldier[base + last] = -1
	slot_of[d] = -1
	alive -= 1
	u_alive[u] = alive
	u_morale[u] -= MORALE_LOSS_PER_DEATH_TOTAL / maxi(u_count0[u], 1)
	u_dirty[u] = 1
	u_settled[u] = 0
	if alive <= 0:
		u_state[u] = U_DESTROYED
		u_order[u] = O_NONE


func _set_bounds(u: int, cx: int, cy: int, minx: int, miny: int, maxx: int, maxy: int) -> void:
	u_cx[u] = cx
	u_cy[u] = cy
	u_minx[u] = minx
	u_miny[u] = miny
	u_maxx[u] = maxx
	u_maxy[u] = maxy


## Recompute slot offsets of units whose formation changed this tick
## (deaths shrink the last rank).
func _refresh_offsets() -> void:
	for u in n_units:
		if u_dirty[u] != 0 and u_state[u] == U_READY and u_alive[u] > 0:
			_compute_offsets(u)


## Full recompute of centroids and bounding boxes (setup only; during play
## _update_soldiers maintains them as it moves soldiers).
func _update_bounds() -> void:
	for u in n_units:
		var alive := u_alive[u]
		if alive <= 0:
			continue
		if u_settled[u] != 0 and u_dirty[u] == 0:
			continue
		var base := u_slot_base[u]
		var i0 := slot_soldier[base]
		var minx := pos_x[i0]
		var maxx := minx
		var miny := pos_y[i0]
		var maxy := miny
		var sx := 0
		var sy := 0
		for s in alive:
			var i := slot_soldier[base + s]
			var x := pos_x[i]
			var y := pos_y[i]
			sx += x
			sy += y
			if x < minx:
				minx = x
			elif x > maxx:
				maxx = x
			if y < miny:
				miny = y
			elif y > maxy:
				maxy = y
		u_cx[u] = sx / alive
		u_cy[u] = sy / alive
		u_minx[u] = minx
		u_maxx[u] = maxx
		u_miny[u] = miny
		u_maxy[u] = maxy
		if u_dirty[u] != 0 and u_state[u] == U_READY:
			_compute_offsets(u)


func _update_morale() -> void:
	for u in n_units:
		var us := u_state[u]
		if us == U_DESTROYED:
			continue
		var ty := u_type[u]
		var m := u_morale[u]
		var periodic := (u + tick) % TICKS_PER_SECOND == 0
		if us == U_READY:
			if u_contact[u] == 0 and u_fighting[u] == 0:
				var base_m := t_morale[ty]
				var cap := base_m - (u_count0[u] - u_alive[u]) * base_m / (2 * u_count0[u])
				if m < cap:
					m = mini(m + MORALE_RECOVER, cap)
			if periodic:
				var routing_near := 0
				for o in n_units:
					if o != u and u_side[o] == u_side[u] and u_state[o] == U_ROUTING:
						var dx := u_cx[o] - u_cx[u]
						var dy := u_cy[o] - u_cy[u]
						if absi(dx) < ROUTING_FRIEND_RANGE and absi(dy) < ROUTING_FRIEND_RANGE:
							routing_near += 1
				m -= MORALE_ROUTING_FRIEND * mini(routing_near, MAX_ROUTING_FRIENDS)
			u_morale[u] = clampi(m, -MORALE_MAX, MORALE_MAX)
			if m < ROUT_THRESHOLD:
				_start_rout(u)
		else:  # routing
			if periodic:
				var e := _nearest_enemy_unit(u, true)
				var safe := true
				if e >= 0:
					var dx := u_cx[u] - u_cx[e]
					var dy := u_cy[u] - u_cy[e]
					var d := FM.isqrt(dx * dx + dy * dy)
					safe = d > RALLY_SAFE_RANGE
					if d > 0:
						u_flee_x[u] = dx * FM.TRIG_ONE / d
						u_flee_y[u] = dy * FM.TRIG_ONE / d
				if safe:
					m += 40
			u_morale[u] = clampi(m, -MORALE_MAX, MORALE_MAX)
			if m >= RALLY_THRESHOLD and u_routs[u] < MAX_ROUTS and u_alive[u] * 5 >= u_count0[u]:
				_rally(u)


func _nearest_enemy_unit(u: int, ready_only: bool) -> int:
	var best := -1
	var best_d := 0
	for o in n_units:
		if u_side[o] == u_side[u] or u_state[o] == U_DESTROYED:
			continue
		if ready_only and u_state[o] != U_READY:
			continue
		var dx := u_cx[o] - u_cx[u]
		var dy := u_cy[o] - u_cy[u]
		var d2 := dx * dx + dy * dy
		if best < 0 or d2 < best_d:
			best = o
			best_d = d2
	return best


func _start_rout(u: int) -> void:
	u_state[u] = U_ROUTING
	u_routs[u] += 1
	u_order[u] = O_NONE
	u_target[u] = -1
	u_settled[u] = 0
	u_morale[u] = 0
	# Flee away from the nearest enemy, default: straight back.
	var e := _nearest_enemy_unit(u, false)
	var fx := -FM.cos_a(u_face[u])
	var fy := -FM.sin_a(u_face[u])
	if e >= 0:
		var dx := u_cx[u] - u_cx[e]
		var dy := u_cy[u] - u_cy[e]
		var d := FM.isqrt(dx * dx + dy * dy)
		if d > 0:
			fx = dx * FM.TRIG_ONE / d
			fy = dy * FM.TRIG_ONE / d
	u_flee_x[u] = fx
	u_flee_y[u] = fy
	var base := u_slot_base[u]
	for s in u_alive[u]:
		var i := slot_soldier[base + s]
		state[i] = S_ROUTING
		target[i] = -1


func _rally(u: int) -> void:
	u_state[u] = U_READY
	u_morale[u] = RALLY_THRESHOLD
	var e := _nearest_enemy_unit(u, false)
	var face := u_face[u]
	if e >= 0:
		face = FM.atan2_a(u_cy[e] - u_cy[u], u_cx[e] - u_cx[u])
	u_face[u] = face
	u_ax[u] = u_cx[u]
	u_ay[u] = u_cy[u]
	u_order[u] = O_NONE
	u_run[u] = 0
	u_dirty[u] = 1
	u_settled[u] = 0
	_compute_offsets(u)
	var base := u_slot_base[u]
	for s in u_alive[u]:
		var i := slot_soldier[base + s]
		state[i] = S_FORMED
		target[i] = -1


func _check_winner() -> void:
	if winner >= 0:
		return
	var ready := [0, 0]
	for u in n_units:
		if u_state[u] == U_READY:
			ready[u_side[u]] += 1
	if ready[0] == 0 and ready[1] > 0:
		winner = 1
	elif ready[1] == 0 and ready[0] > 0:
		winner = 0
	elif ready[0] == 0 and ready[1] == 0:
		winner = 2  # mutual destruction / both routed


# ---------------------------------------------------------------- query ---

func alive_count(side: int = -1) -> int:
	var c := 0
	for u in n_units:
		if side < 0 or u_side[u] == side:
			c += u_alive[u]
	return c


func is_ai_side(side: int) -> bool:
	return ai_sides[side] != 0


## 32-bit hash of the full simulation state (MD5 of every state array).
func state_hash() -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	# Pending (future) orders are deliberately left out: in lockstep a peer
	# may already hold orders the other has not received yet.
	var header := PackedInt64Array([tick, rng_state, winner, n, n_units])
	ctx.update(header.to_byte_array())
	for arr in [pos_x, pos_y, facing, hp, state, cooldown, unit_of, slot_of, target]:
		ctx.update((arr as PackedInt32Array).to_byte_array())
	for arr in _unit_arrays():
		ctx.update((arr as PackedInt32Array).to_byte_array())
	ctx.update(slot_soldier.to_byte_array())
	ctx.update(off_x.to_byte_array())
	ctx.update(off_y.to_byte_array())
	var digest := ctx.finish()
	return digest.decode_u32(0)
