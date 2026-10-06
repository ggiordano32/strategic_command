extends RefCounted
## Battle AI on settlement maps (sim/mapgen.gd city maps). Like the field
## AI it only queues the orders a player can give, and its memory lives in
## hashed sim arrays (ai_phase / ai_t / ai_gate per side, u_ai / u_ai_t /
## u_ai_x / u_ai_y per unit).
##
## Attackers (each army once a second, units once a second staggered):
##   approach  the army forms up out of the wall archers' reach facing the
##             gate it goes for (ai_gate: the weakest and nearest, a gate
##             already open or broken first); batteries move to 165 m from
##             it and shoot it; archers stand 110 m out and shoot the men on
##             the walls; with no working battery (or after two minutes of
##             bombardment, or once the batteries are empty) the heaviest
##             foot units hack at the gate; everyone else waits.
##   assault   once a gate is open or broken (or the town has no walls),
##             the foot go in: each attacks a defender unit within 45 m
##             (at the plaza while it is still contested: the nearest
##             defender off the walls anywhere), otherwise makes for the plaza (an open town is entered by
##             its streets, the units shared out over them); archers follow
##             to the breach; cavalry stays outside, riding only at
##             defenders outside the walls, until the defenders break.
##   pursue    the defenders are broken: cavalry rides down the routers.
##   all out    with no foot left, cavalry and missile troops storm too;
##             four minutes into the assault every unit goes in; and
##             when fewer than 10 defenders have died (a gate's 100 hp
##             counting as one) in 2.5 minutes, every attacking unit storms (hunting the nearest
##             defender anywhere) if the attackers still have 1.2x the
##             defenders' strength off the walls, else they withdraw; all
##             out and still nothing for 5 more minutes: they withdraw
##             unless 1.5x stronger.
##   The army withdraws as in the field when the battle is clearly lost.
## Defenders (never withdraw):
##   wall      units on the walls stand and shoot (fire at will).
##   gate      the foot unit inside each gate holds it: it attacks attackers
##             that come within 25 m of the gate's inside, else returns.
##   reserve   the rest hold the plaza and the main street: they attack
##             attackers inside the settlement within 140 m of their post,
##             and go back to it when there are none.
##   gates     an open gate with attackers within 100 m is closed.
##   off wall  wall units whose gate is open or broken, with attackers in
##             the town within 40 m, come down by a stair and fall back to
##             the citadel (or the agora).
##   citadel   where there is one: when the town is lost (attackers within
##             30 m of the citadel's gate, or more attackers than defenders
##             inside the walls) every unit falls back into it (wall units
##             by the stairs) and its gate is shut once they are in (or
##             attackers are within 25 m of it); inside they attack
##             attackers that get in.
## Attackers with the outer gate down and a citadel shut against them: the
## heaviest foot hack at its gate (the batteries shoot it if they reach),
## the rest fight in the town and gather before it.

const FM := preload("res://sim/fixed_math.gd")
const UT := preload("res://sim/unit_types.gd")
const BattleAI := preload("res://sim/battle_ai.gd")
const MapGen := preload("res://sim/mapgen.gd")

const M := 1024
const THINK_PERIOD := 10

const U_READY := 0
const U_ROUTING := 1
const U_DESTROYED := 2
const O_NONE := 0
const O_MOVE := 1
const O_ATTACK := 2
const O_WITHDRAW := 3
const ORDER_ATTACK := 2
const ORDER_FIRE := 5
const ORDER_SKIRMISH := 6
const ORDER_WITHDRAW_ALL := 8
const ORDER_REFILL := 10
const ORDER_GATE := 11
const GATE_OPEN := 0
const GATE_CLOSED := 1
const GATE_BROKEN := 2

# Army phases (ai_phase) on settlement maps.
const SP_APPROACH := 10
const SP_ASSAULT := 11
const SP_PURSUE := 12
const SD_HOLD := 20
const P_WITHDRAW := 3

# Unit modes (u_ai; stat_ai counts them).
const A_WALLU := 20     # defender on a wall
const A_GATE := 21      # defender holding a gate (u_ai_y = gate)
const A_RESERVE := 22   # defender reserve (u_ai_x / u_ai_y = post)
const A_SART := 23      # attacking battery
const A_HACK := 24      # attacker hacking at a gate
const A_COVER := 25     # attacking archers covering the gate
const A_WAIT := 26      # attacking foot waiting for the breach
const A_STORM := 27     # attacking foot in the assault (u_ai_x: 0 to the street mouth, 1 to the plaza)
const A_CAVOUT := 28    # attacking cavalry kept outside
const A_CIT := 29       # defender holding the citadel (u_ai_x / u_ai_y = post)

const STAGE_OUT := 160 * M      # waiting line from the gate's face
const ART_OUT := 165 * M        # batteries' firing line
const COVER_OUT := 110 * M      # archers' line
const HACK_AFTER := 1200        # bombardment ticks before the foot hack anyway
const STORM_R := 45 * M         # assault: attack defenders this close
const BEATEN_PCT := 35         # attackers down to this % of their strength and weaker than the defenders: withdraw
const SPREAD := 25 * M          # ... each other unit of ours on a defender counts as this much further
const GATE_REACT := 25 * M      # gate guards attack attackers this close to the gate
const RESERVE_R := 140 * M      # reserves attack attackers inside this close to their post
const CLOSE_R := 100 * M        # close an open gate with attackers this close
const STALL_TICKS := 1500       # under STALL_PROG defenders killed / gate damage (100 hp each) for this long: a stall
const STALL_PROG := 10
const ASSAULT_ALL := 2400       # after this long in the assault every unit goes in
const OFFWALL_R := 40 * M       # wall units come down with attackers in the town this close
const CIT_LOST_R := 30 * M      # attackers this close to the citadel's gate: into the citadel
const CIT_SHUT_R := 25 * M      # ... and it is shut with attackers this close


static func think(sim) -> void:
	var tick: int = sim.tick
	if tick % THINK_PERIOD == 0:
		for side in 2:
			if sim.ai_sides[side] != 0:
				_army(sim, side)
	if sim.ai_sides[0] == 0 and sim.ai_sides[1] == 0:
		return
	var local := [0, 0]
	for u in sim.n_units:
		var side: int = sim.u_side[u]
		var k: int = local[side]
		local[side] = k + 1
		if sim.ai_sides[side] == 0 or sim.u_state[u] != U_READY:
			continue
		if (k + tick) % THINK_PERIOD != 0:
			continue
		if sim.ai_phase[side] == P_WITHDRAW or sim.u_order[u] == O_WITHDRAW:
			continue
		if side == sim.city_def:
			_defender(sim, u)
		else:
			_attacker(sim, u)


# ------------------------------------------------------------ army level ---

static func _army(sim, side: int) -> void:
	var phase: int = sim.ai_phase[side]
	if phase == P_WITHDRAW:
		return
	if side == sim.city_def:
		if phase != SD_HOLD:
			sim.ai_phase[side] = SD_HOLD
			sim.ai_t[side] = sim.tick
			for u in sim.n_units:
				if sim.u_side[u] == side and sim.u_state[u] == U_READY:
					_classify_defender(sim, u)
		_close_gates(sim, side)
		if sim.cit_r > 0:
			_citadel(sim, side)
		return
	# Attackers. Clearly lost: withdraw (as in the field).
	var own := BattleAI._strength(sim, side)
	var foe := BattleAI._strength(sim, 1 - side)
	if sim.tick > 600 and foe > 0 and (own * 100 < foe * 30 \
			or (own * 100 < BattleAI._start_strength(sim, side) * BEATEN_PCT and own < foe)):
		sim.queue_order({"tick": sim.tick, "type": ORDER_WITHDRAW_ALL, "side": side,
			"player": BattleAI.AI_PLAYER_BASE + side, "seq": 9000})
		sim.ai_phase[side] = P_WITHDRAW
		sim.ai_t[side] = sim.tick
		sim.stat_ai[8] += 1
		return
	if phase < SP_APPROACH:
		phase = SP_APPROACH
		sim.ai_t[side] = sim.tick
	# Stall watch: defenders killed and gate damage so far (the attack's
	# progress; its own losses are not).
	var prog := 0
	for u in sim.n_units:
		if sim.u_side[u] != side:
			prog += sim.u_killed[u]
	for g in sim.n_gates:
		prog += (sim.g_hp0[g] - sim.g_hp[g]) / 10000
	if prog >= sim.ai_prog[0] + STALL_PROG or (phase == SP_APPROACH and sim.tick - sim.ai_t[side] < 2 * HACK_AFTER):
		# (The first four minutes of the approach - the batteries setting up
		# and bombarding, then the foot hacking - never count as a stall.)
		sim.ai_prog[0] = maxi(prog, sim.ai_prog[0])
		sim.ai_prog[1] = sim.tick
	elif phase == SP_ASSAULT and sim.tick - sim.ai_t[side] > ASSAULT_ALL and sim.ai_prog[2] == 0:
		sim.ai_prog[2] = 1  # four minutes into the assault: everything goes in
	elif sim.tick - sim.ai_prog[1] > STALL_TICKS and (sim.ai_prog[2] == 0 \
			or sim.tick - sim.ai_prog[1] > 2 * STALL_TICKS):
		var foe_g := _ground_strength(sim, 1 - side)
		if sim.ai_prog[2] == 0 and own * 10 >= foe_g * 12:
			sim.ai_prog[2] = 1  # all out
			sim.ai_prog[1] = sim.tick
		elif sim.ai_prog[2] != 0 and own * 10 >= foe_g * 15:
			sim.ai_prog[1] = sim.tick  # all out and still clearly stronger: keep at it
		else:
			# Too weak, or all out and still nothing for 5 minutes: give up.
			sim.queue_order({"tick": sim.tick, "type": ORDER_WITHDRAW_ALL, "side": side,
				"player": BattleAI.AI_PLAYER_BASE + side, "seq": 9001})
			sim.ai_phase[side] = P_WITHDRAW
			sim.ai_t[side] = sim.tick
			sim.stat_ai[8] += 1
			return
	if not _defenders_standing(sim, side):
		if phase != SP_PURSUE:
			phase = SP_PURSUE
			sim.ai_t[side] = sim.tick
	elif phase == SP_APPROACH:
		var br := _breach(sim, side)
		if br != -1:
			phase = SP_ASSAULT
			sim.ai_t[side] = sim.tick
			sim.ai_gate[side] = br
		else:
			var g: int = sim.ai_gate[side]
			if g < 0 or sim.g_state[g] != GATE_CLOSED:
				sim.ai_gate[side] = _pick_gate(sim, side)
	sim.ai_phase[side] = phase


## Fighting strength of side's ready units off the walls.
static func _ground_strength(sim, side: int) -> int:
	var s := 0
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and sim.u_wall[u] == 0:
			s += sim.u_alive[u] * UT.stat(sim.u_type[u], "cost")
	return s


## The attackers have no ready foot left.
static func _no_foot(sim, side: int) -> bool:
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and \
				(sim.u_cls[u] == UT.CLS_INF or sim.u_cls[u] == UT.CLS_PIKE):
			return false
	return true


## Any ready defender unit off the walls (or the plaza not yet theirs).
static func _defenders_standing(sim, side: int) -> bool:
	for u in sim.n_units:
		if sim.u_side[u] != side and sim.u_state[u] == U_READY and sim.u_wall[u] == 0:
			return true
	return false


## A gate the assault can go through now: an open or broken one (nearest
## the army), -2 for a town without walls, -1 none.
static func _breach(sim, side: int) -> int:
	if sim.n_gates == 0:
		return -2
	var c := _army_centre(sim, side)
	var best := -1
	var best_d := 0
	for g in sim.n_gates:
		if sim.g_state[g] == GATE_CLOSED or sim.g_cit[g] != 0:
			continue
		var d := BattleAI._d(sim.g_ox[g] - c.x, sim.g_oy[g] - c.y)
		if best < 0 or d < best_d:
			best = g
			best_d = d
	return best


## Gate to break: the weakest and nearest (hit points count 4 m per 100 hp).
static func _pick_gate(sim, side: int) -> int:
	var c := _army_centre(sim, side)
	var best := -1
	var best_s := 0
	for g in sim.n_gates:
		if sim.g_state[g] != GATE_CLOSED or sim.g_cit[g] != 0:
			continue
		var s: int = BattleAI._d(sim.g_ox[g] - c.x, sim.g_oy[g] - c.y) / M + sim.g_hp[g] / 100 * 4 / 100
		if best < 0 or s < best_s:
			best = g
			best_s = s
	return best


static func _army_centre(sim, side: int) -> Vector2i:
	var sx := 0
	var sy := 0
	var n := 0
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY:
			sx += sim.u_cx[u] * sim.u_alive[u]
			sy += sim.u_cy[u] * sim.u_alive[u]
			n += sim.u_alive[u]
	if n == 0:
		return Vector2i(sim.field_w / 2, sim.field_h / 2)
	return Vector2i(sx / n, sy / n)


## Defenders shut an open gate when attackers come near (if nobody is in it).
static func _close_gates(sim, side: int) -> void:
	var any := -1
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY:
			any = u
			break
	if any < 0:
		return
	for g in sim.n_gates:
		if sim.g_state[g] != GATE_OPEN or sim.g_cit[g] != 0:
			continue
		for o in sim.n_units:
			if sim.u_side[o] == side or sim.u_state[o] != U_READY:
				continue
			if BattleAI._d(sim.u_cx[o] - sim.g_x[g], sim.u_cy[o] - sim.g_y[g]) < CLOSE_R:
				sim.queue_order({"tick": sim.tick, "type": ORDER_GATE, "unit": any, "gate": g, "on": 1,
					"player": BattleAI.AI_PLAYER_BASE + side, "seq": 8000 + g})
				break


# ------------------------------------------------------------- defenders ---

static func _classify_defender(sim, u: int) -> void:
	if sim.u_wall[u] > 0:
		BattleAI._set_mode(sim, u, A_WALLU)
		return
	for g in sim.n_gates:
		if sim.g_cit[g] == 0 and BattleAI._d(sim.u_ax[u] - sim.g_ix[g], sim.u_ay[u] - sim.g_iy[g]) < 20 * M:
			BattleAI._set_mode(sim, u, A_GATE)
			sim.u_ai_y[u] = g
			sim.u_ai_x[u] = 0
			return
	BattleAI._set_mode(sim, u, A_RESERVE)
	sim.u_ai_x[u] = sim.u_ax[u]
	sim.u_ai_y[u] = sim.u_ay[u]


static func _defender(sim, u: int) -> void:
	var mode: int = sim.u_ai[u]
	if mode == A_WALLU:
		if sim.u_wall[u] == 0:
			# Came down (or was ordered down): hold a post in the town.
			BattleAI._set_mode(sim, u, A_RESERVE)
			sim.u_ai_x[u] = sim.u_ax[u]
			sim.u_ai_y[u] = sim.u_ay[u]
			return
		if sim.u_fire[u] == 0 and sim.u_ammo[u] > 0:
			BattleAI._order(sim, u, {"type": ORDER_FIRE, "on": 1}, 21)
		_off_wall(sim, u)
		return
	if mode == A_CIT:
		_cit_guard(sim, u)
		return
	if mode == A_GATE:
		_gate_guard(sim, u)
		return
	if mode == A_RESERVE:
		_reserve(sim, u)
		return
	# Not yet classified (the army thinks first on the same tick).


## A wall unit whose gate is open or broken with attackers in the town
## near it comes down (by a stair) and falls back toward the citadel (if
## its gate is still open) or the agora.
static func _off_wall(sim, u: int) -> void:
	if sim.u_stair[u] != 0 or sim.u_order[u] == O_MOVE:
		return
	var sg: int = sim.u_wall[u] - 1
	var mx: int = (sim.ws_x0[sg] + sim.ws_x1[sg]) / 2
	var my: int = (sim.ws_y0[sg] + sim.ws_y1[sg]) / 2
	var g := -1
	var gd := 0
	for k in sim.n_gates:
		if sim.g_cit[k] != 0:
			continue
		var d := BattleAI._d(sim.g_x[k] - mx, sim.g_y[k] - my)
		if g < 0 or d < gd:
			g = k
			gd = d
	if g < 0 or sim.g_state[g] == GATE_CLOSED:
		return
	if _nearest_attacker(sim, u, sim.u_cx[u], sim.u_cy[u], OFFWALL_R, true) < 0:
		return
	var post := _fallback_post(sim, u)
	BattleAI._order(sim, u, {"type": 1, "x": post.x, "y": post.y, "facing": post.z,
		"width": BattleAI._width(sim, u), "run": 1}, 2)


## Where a defender falls back to: inside the citadel while its gate is not
## shut (spread round its middle), else the agora.
static func _fallback_post(sim, u: int) -> Vector3i:
	var k := 0
	for o in u:
		if sim.u_side[o] == sim.u_side[u]:
			k += 1
	if sim.cit_r > 0 and sim.g_state[sim.cit_gate] != GATE_CLOSED:
		var rr: int = maxi(sim.cit_r - sim.wall_t / 2 - 5 * M, 2 * M)
		var a := (k * 389) & 1023
		var r2 := rr * ((k * 7) % 10 + 2) / 12
		var x: int = sim.cit_x + FM.cos_a(a) * r2 / FM.TRIG_ONE
		var y: int = sim.cit_y + FM.sin_a(a) * r2 / FM.TRIG_ONE
		return Vector3i(x, y, FM.atan2_a(sim.g_y[sim.cit_gate] - y, sim.g_x[sim.cit_gate] - x))
	var ax: int = sim.agora[0] + ((k % 3) - 1) * sim.agora[2] / 2
	var ay: int = sim.agora[1] + ((k / 3) % 3 - 1) * sim.agora[2] / 2
	var face: int = FM.atan2_a(sim.g_y[0] - ay, sim.g_x[0] - ax) if sim.n_gates > 0 else 0
	return Vector3i(ax, ay, face)


## The citadel: when the town is lost (attackers near its gate, or more of
## them than defenders inside the walls) everyone falls back into it; its
## gate is shut once they are in or attackers come close.
static func _citadel(sim, side: int) -> void:
	var g: int = sim.cit_gate
	if sim.ai_cit[side] == 0:
		var lost := false
		var att := 0
		var dfn := 0
		for o in sim.n_units:
			if sim.u_state[o] != U_READY:
				continue
			if sim.u_side[o] == side:
				if sim.u_wall[o] == 0:
					dfn += sim.u_alive[o]
				continue
			if BattleAI._d(sim.u_cx[o] - sim.g_x[g], sim.u_cy[o] - sim.g_y[g]) < CIT_LOST_R:
				lost = true
			if (sim.veg_bits(sim.u_cx[o], sim.u_cy[o]) & MapGen.V_URBAN) != 0:
				att += sim.u_alive[o]
		if not lost and att <= dfn:
			return
		sim.ai_cit[side] = 1
		# As many as the citadel holds (about 2 m2 a man), the wall units
		# first, then missile troops, then the rest by index; the others
		# fight on in the town.
		var inner: int = maxi(sim.cit_r - sim.wall_t / 2 - M, 4 * M) / M
		var room := inner * inner * 3 / 2
		var width := maxi(inner * 2 * 70 / 100, 8) * M
		for pass_n in 3:
			for u in sim.n_units:
				if sim.u_side[u] != side or sim.u_state[u] != U_READY or sim.u_ai[u] == A_CIT:
					continue
				var mode: int = sim.u_ai[u]
				var cls: int = sim.u_cls[u]
				if pass_n == 0 and mode != A_WALLU:
					continue
				if pass_n == 1 and cls != UT.CLS_MISSILE:
					continue
				if cls == UT.CLS_CAV or cls == UT.CLS_ART or sim.u_alive[u] > room:
					continue
				room -= sim.u_alive[u]
				BattleAI._set_mode(sim, u, A_CIT)
				var post := _fallback_post(sim, u)
				sim.u_ai_x[u] = post.x
				sim.u_ai_y[u] = post.y
				BattleAI._order(sim, u, {"type": 1, "x": post.x, "y": post.y, "facing": post.z,
					"width": mini(BattleAI._width(sim, u), width), "run": 1}, 2)
		return
	if sim.g_state[g] != GATE_OPEN:
		return
	var shut := true
	var any := -1
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY:
			continue
		any = u
		if sim.u_ai[u] == A_CIT and BattleAI._d(sim.u_cx[u] - sim.cit_x, sim.u_cy[u] - sim.cit_y) > sim.cit_r:
			shut = false
	if any < 0:
		return
	if not shut:
		for o in sim.n_units:
			if sim.u_side[o] != side and sim.u_state[o] == U_READY \
					and BattleAI._d(sim.u_cx[o] - sim.g_x[g], sim.u_cy[o] - sim.g_y[g]) < CIT_SHUT_R:
				shut = true
				break
	if shut:
		sim.queue_order({"tick": sim.tick, "type": ORDER_GATE, "unit": any, "gate": g, "on": 1,
			"player": BattleAI.AI_PLAYER_BASE + side, "seq": 8000 + g})


## In the citadel: attack attackers that get in, else hold the post
## (missile troops shoot from it).
static func _cit_guard(sim, u: int) -> void:
	if sim.u_wall[u] > 0 or sim.u_stair[u] != 0:
		return
	if _engaged(sim, u):
		return
	var t := -1
	var best_d: int = sim.cit_r + 8 * M
	for o in sim.n_units:
		if sim.u_side[o] == sim.u_side[u] or sim.u_state[o] != U_READY:
			continue
		var d := BattleAI._d(sim.u_cx[o] - sim.cit_x, sim.u_cy[o] - sim.cit_y)
		if d < best_d:
			best_d = d
			t = o
	if t >= 0 and sim.u_cls[u] != UT.CLS_ART and not (sim.u_cls[u] == UT.CLS_MISSILE and sim.u_ammo[u] > 0):
		BattleAI._attack(sim, u, t, 0)
		return
	if sim.u_cls[u] == UT.CLS_MISSILE and sim.u_fire[u] == 0 and sim.u_ammo[u] > 0:
		BattleAI._order(sim, u, {"type": ORDER_FIRE, "on": 1}, 21)
	_go_home(sim, u, sim.u_ai_x[u], sim.u_ai_y[u], sim.u_dface[u], 6)


## Gate guard: fight attackers at (or through) the gate, else hold the post.
static func _gate_guard(sim, u: int) -> void:
	var g: int = sim.u_ai_y[u]
	var gx: int = sim.g_ix[g]
	var gy: int = sim.g_iy[g]
	if _engaged(sim, u):
		return
	var t := _nearest_attacker(sim, u, gx, gy, GATE_REACT, false)
	if t >= 0:
		BattleAI._attack(sim, u, t, 0)
		return
	if sim.g_state[g] == GATE_BROKEN:
		# The gate has fallen and nobody is at it: hold the street behind.
		var t2 := _nearest_attacker(sim, u, gx, gy, 60 * M, true)
		if t2 >= 0:
			BattleAI._attack(sim, u, t2, 0)
			return
	var dir: int = sim.g_dir[g]
	var hx: int = gx - FM.cos_a(dir) * 5 * M / FM.TRIG_ONE
	var hy: int = gy - FM.sin_a(dir) * 5 * M / FM.TRIG_ONE
	_go_home(sim, u, hx, hy, dir, 8)


## Reserve: attack attackers inside the settlement near the post, else hold.
static func _reserve(sim, u: int) -> void:
	if _engaged(sim, u):
		return
	var hx: int = sim.u_ai_x[u]
	var hy: int = sim.u_ai_y[u]
	var t := _nearest_attacker(sim, u, hx, hy, RESERVE_R, true)
	if t >= 0 and sim.u_cls[u] != UT.CLS_ART:
		if sim.u_cls[u] == UT.CLS_MISSILE and sim.u_ammo[u] > 0:
			return  # shoot from the post (fire at will)
		BattleAI._attack(sim, u, t, 1 if BattleAI._dist2(sim, u, t) < 30 * M * 30 * M else 0)
		return
	var face: int = FM.atan2_a(sim.g_y[0] - hy, sim.g_x[0] - hx) if sim.n_gates > 0 else sim.u_dface[u]
	_go_home(sim, u, hx, hy, face, 10)


## Unit u is fighting a ready enemy it was ordered at.
static func _engaged(sim, u: int) -> bool:
	if sim.u_order[u] != O_ATTACK or sim.u_fighting[u] == 0:
		return false
	var t: int = sim.u_target[u]
	return t >= 0 and sim.u_state[t] == U_READY


## Move back to (x, y) unless within `slack` metres of it already.
static func _go_home(sim, u: int, x: int, y: int, face: int, slack: int) -> void:
	if sim.u_order[u] == O_MOVE:
		if BattleAI._d(sim.u_dx[u] - x, sim.u_dy[u] - y) < 4 * M:
			return
	elif BattleAI._d(sim.u_ax[u] - x, sim.u_ay[u] - y) < slack * M:
		return
	BattleAI._move(sim, u, x, y, face, BattleAI._width(sim, u), 0, 2)


## As _go_home, at the run if `run`.
static func _go_run(sim, u: int, x: int, y: int, face: int, slack: int, run: int) -> void:
	if sim.u_order[u] == O_MOVE:
		if BattleAI._d(sim.u_dx[u] - x, sim.u_dy[u] - y) < 4 * M and sim.u_run[u] == run:
			return
	elif BattleAI._d(sim.u_ax[u] - x, sim.u_ay[u] - y) < slack * M:
		return
	BattleAI._order(sim, u, {"type": 1, "x": x, "y": y, "facing": face, "width": BattleAI._width(sim, u),
		"run": run}, 2)


## Nearest ready attacking unit (not routing) within r of (x, y); inside the
## settlement only if `inside`.
static func _nearest_attacker(sim, u: int, x: int, y: int, r: int, inside: bool) -> int:
	var best := -1
	var best_d := r
	for o in sim.n_units:
		if sim.u_side[o] == sim.u_side[u] or sim.u_state[o] != U_READY:
			continue
		var d := BattleAI._d(sim.u_cx[o] - x, sim.u_cy[o] - y)
		if d > best_d:
			continue
		if inside and (sim.veg_bits(sim.u_cx[o], sim.u_cy[o]) & MapGen.V_URBAN) == 0:
			continue
		best = o
		best_d = d
	return best


# ------------------------------------------------------------- attackers ---

static func _attacker(sim, u: int) -> void:
	var side: int = sim.u_side[u]
	var phase: int = sim.ai_phase[side]
	var cls: int = sim.u_cls[u]
	# Badly mauled: fall back once (as in the field).
	var mode: int = sim.u_ai[u]
	if mode != BattleAI.A_RETIRE and sim.u_alive[u] * 100 < sim.u_count0[u] * 30 and sim.u_morale[u] < 350:
		BattleAI._retire(sim, u)
		return
	if mode == BattleAI.A_RETIRE:
		if sim.tick - sim.u_ai_t[u] < BattleAI.RETIRE_TICKS or sim.u_order[u] != O_NONE:
			return
		BattleAI._set_mode(sim, u, A_WAIT)
	if cls == UT.CLS_ART:
		_att_art(sim, u, phase)
	elif cls == UT.CLS_CAV:
		_att_cav(sim, u, phase)
	elif cls == UT.CLS_MISSILE:
		_att_missile(sim, u, phase)
	else:
		_att_foot(sim, u, phase)


## A point `out` from gate g's face along its outward direction, `lat`
## to the side; clamped into the field.
static func _gate_point(sim, g: int, out: int, lat: int) -> Vector2i:
	var dir: int = sim.g_dir[g]
	var c := FM.cos_a(dir)
	var s := FM.sin_a(dir)
	var f: Vector2i = sim.gate_face(g)
	var x: int = f.x + (c * out - s * lat) / FM.TRIG_ONE
	var y: int = f.y + (s * out + c * lat) / FM.TRIG_ONE
	return Vector2i(clampi(x, 8 * M, sim.field_w - 8 * M), clampi(y, 8 * M, sim.field_h - 8 * M))


## Rank of unit u among its side's ready units of the same role (0, 1, ...)
## and how many there are: spreads them along a line.
static func _rank(sim, u: int, same: Callable) -> Vector2i:
	var k := 0
	var n := 0
	for o in sim.n_units:
		if sim.u_side[o] != sim.u_side[u] or sim.u_state[o] != U_READY or not same.call(o):
			continue
		if o < u:
			k += 1
		n += 1
	return Vector2i(k, n)


static func _spread(k: int, n: int, gap: int) -> int:
	return (k * 2 - (n - 1)) * gap / 2


static func _att_art(sim, u: int, phase: int) -> void:
	var side: int = sim.u_side[u]
	BattleAI._set_mode(sim, u, A_SART)
	var ty: int = sim.u_type[u]
	var full: int = sim.u_neng[u] * UT.stat(ty, "m_ammo")
	# Refilling or getting into / out of it: as in the field.
	if sim.u_refill[u] != 0:
		if BattleAI._art_threatened(sim, u) or sim.u_ammo[u] * 4 >= full * 3:
			BattleAI._order(sim, u, {"type": ORDER_REFILL, "on": 0}, 23)
		return
	if sim.u_rprog[u] > 0:
		return
	if sim.u_ammo[u] * 4 <= full and BattleAI._can_refill(sim, u) and not BattleAI._art_threatened(sim, u) \
			and sim.u_order[u] != O_MOVE:
		BattleAI._order(sim, u, {"type": ORDER_REFILL, "on": 1}, 23)
		return
	var g: int = sim.ai_gate[side]
	if phase == SP_APPROACH and g >= 0 and sim.g_state[g] == GATE_CLOSED and sim.u_ammo[u] > 0:
		var rk := _rank(sim, u, func(o): return sim.u_cls[o] == UT.CLS_ART)
		var lat := _spread(rk.x, rk.y, 30 * M)
		var spot := _gate_point(sim, g, ART_OUT, lat)
		if UT.stat(ty, "m_kind") == 1:
			# Bolts need a clear flat line to the gate: try further aside.
			var f: Vector2i = sim.gate_face(g)
			for off in [0, 20, -20, 40, -40]:
				var cand := _gate_point(sim, g, ART_OUT, lat + off * M)
				if sim.lof_block(cand.x, cand.y, sim.height_at(cand.x, cand.y) + 1536, f.x, f.y,
						sim.height_at(f.x, f.y) + 1024, 0, 0, 8192) < 0:
					spot = cand
					break
		if BattleAI._d(sim.u_ax[u] - spot.x, sim.u_ay[u] - spot.y) > 12 * M:
			if sim.u_order[u] != O_MOVE or BattleAI._d(sim.u_dx[u] - spot.x, sim.u_dy[u] - spot.y) > 6 * M:
				var face := FM.atan2_a(sim.g_y[g] - spot.y, sim.g_x[g] - spot.x)
				BattleAI._move(sim, u, spot.x, spot.y, face, BattleAI._width(sim, u), 0, 6)
			return
		if sim.u_order[u] != O_ATTACK or sim.u_gtarget[u] != g:
			BattleAI._order(sim, u, {"type": ORDER_ATTACK, "target": -1, "gate": g, "run": 0}, 0)
		return
	var cg: int = sim.cit_gate
	if phase == SP_ASSAULT and cg >= 0 and sim.g_state[cg] == GATE_CLOSED and sim.u_ammo[u] > 0:
		# The citadel's gate, if it is within reach from here.
		var f: Vector2i = sim.gate_face(cg)
		var dcg := BattleAI._d(f.x - sim.u_cx[u], f.y - sim.u_cy[u])
		var reach: int = UT.stat(ty, "m_range") * 92 / 100
		if dcg < reach:
			if sim.u_order[u] != O_ATTACK or sim.u_gtarget[u] != cg:
				BattleAI._order(sim, u, {"type": ORDER_ATTACK, "target": -1, "gate": cg, "run": 0}, 0)
			return
		# Out of reach: bring the battery up (through the breach if need be)
		# to 70 % of its range from the citadel's gate.
		var want := UT.stat(ty, "m_range") * 70 / 100
		var spot := Vector2i(f.x + (sim.u_cx[u] - f.x) * want / maxi(dcg, 1),
			f.y + (sim.u_cy[u] - f.y) * want / maxi(dcg, 1))
		if sim.u_order[u] != O_MOVE or BattleAI._d(sim.u_dx[u] - spot.x, sim.u_dy[u] - spot.y) > 8 * M:
			BattleAI._move(sim, u, spot.x, spot.y, FM.atan2_a(f.y - spot.y, f.x - spot.x), BattleAI._width(sim, u), 0, 6)
		return
	# No gate to shoot: fire at will from where it stands.
	if sim.u_order[u] == O_ATTACK and sim.u_gtarget[u] >= 0:
		BattleAI._order(sim, u, {"type": 3}, 22)  # halt
	if sim.u_fire[u] == 0:
		BattleAI._order(sim, u, {"type": ORDER_FIRE, "on": 1}, 21)


## Working batteries with shots left on side `side`.
static func _art_ready(sim, side: int) -> bool:
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and sim.u_cls[u] == UT.CLS_ART \
				and (sim.u_ammo[u] > 0 or sim.u_reserve[u] > 0):
			for k in sim.u_neng[u]:
				if sim.e_state[sim.u_eng0[u] + k] == 0:
					return true
	return false


## Rank of foot unit u among its side's ready foot by distance to (x, y)
## (ties: index).
static func _near_rank(sim, u: int, x: int, y: int) -> int:
	var du := BattleAI._d(sim.u_cx[u] - x, sim.u_cy[u] - y)
	var k := 0
	for o in sim.n_units:
		if o == u or sim.u_side[o] != sim.u_side[u] or sim.u_state[o] != U_READY:
			continue
		var c: int = sim.u_cls[o]
		if c != UT.CLS_INF and c != UT.CLS_PIKE:
			continue
		var d := BattleAI._d(sim.u_cx[o] - x, sim.u_cy[o] - y)
		if d < du or (d == du and o < u):
			k += 1
	return k


## Foot units that hack at the gate: heavy first, then light, spears, pikes
## (by unit index within a type); two of them, or every one once the
## attackers have no battery left.
static func _hack_rank(sim, u: int) -> int:
	var b := UT.base_of(sim.u_type[u])
	var key := 3
	if b == UT.HEAVY:
		key = 0
	elif b == UT.LIGHT:
		key = 1
	elif b == UT.SPEAR:
		key = 2
	var k := 0
	for o in sim.n_units:
		if o == u or sim.u_side[o] != sim.u_side[u] or sim.u_state[o] != U_READY:
			continue
		var c: int = sim.u_cls[o]
		if c != UT.CLS_INF and c != UT.CLS_PIKE:
			continue
		var bo := UT.base_of(sim.u_type[o])
		var ko := 3
		if bo == UT.HEAVY:
			ko = 0
		elif bo == UT.LIGHT:
			ko = 1
		elif bo == UT.SPEAR:
			ko = 2
		if ko < key or (ko == key and o < u):
			k += 1
	return k


static func _att_foot(sim, u: int, phase: int) -> void:
	var side: int = sim.u_side[u]
	if phase == SP_PURSUE:
		var r := _router(sim, u, 80 * M)
		if r >= 0:
			if sim.u_order[u] != O_ATTACK or sim.u_target[u] != r:
				BattleAI._attack(sim, u, r, 1)
			return
		_storm(sim, u)
		return
	if phase == SP_ASSAULT:
		_storm(sim, u)
		return
	var g: int = sim.ai_gate[side]
	if g < 0:
		return
	# Hack at the gate: with no battery from the start, else after a while
	# of bombardment.
	var hackers := 2
	if not _art_ready(sim, side):
		hackers = 99 if sim.tick - sim.ai_t[side] > 2 * HACK_AFTER else 2
	elif sim.tick - sim.ai_t[side] < HACK_AFTER:
		hackers = 0
	if _hack_rank(sim, u) < hackers:
		BattleAI._set_mode(sim, u, A_HACK)
		if _engaged(sim, u):
			return
		if sim.u_gtarget[u] != g:
			var far := BattleAI._d(sim.u_cx[u] - sim.g_ox[g], sim.u_cy[u] - sim.g_oy[g]) > 40 * M
			BattleAI._order(sim, u, {"type": ORDER_ATTACK, "target": -1, "gate": g,
				"run": 1 if far and sim.u_cls[u] != UT.CLS_PIKE else 0}, 0)
		return
	BattleAI._set_mode(sim, u, A_WAIT)
	# Defenders outside the walls near us: fight them.
	var t := _nearest_outside(sim, u, 40 * M)
	if t >= 0:
		if not _engaged(sim, u):
			BattleAI._attack(sim, u, t, 1)
		return
	var rk := _rank(sim, u, func(o): return sim.u_cls[o] == UT.CLS_INF or sim.u_cls[o] == UT.CLS_PIKE)
	var spot := _gate_point(sim, g, STAGE_OUT, _spread(rk.x, rk.y, 34 * M))
	var face := FM.atan2_a(sim.g_y[g] - spot.y, sim.g_x[g] - spot.x)
	_go_home(sim, u, spot.x, spot.y, face, 10)


## Nearest ready defender unit (not on a wall) outside the settlement
## within r of unit u.
static func _nearest_outside(sim, u: int, r: int) -> int:
	var best := -1
	var best_d := r
	for o in sim.n_units:
		if sim.u_side[o] == sim.u_side[u] or sim.u_state[o] != U_READY or sim.u_wall[o] > 0:
			continue
		if (sim.veg_bits(sim.u_cx[o], sim.u_cy[o]) & MapGen.V_URBAN) != 0:
			continue
		var d := BattleAI._d(sim.u_cx[o] - sim.u_cx[u], sim.u_cy[o] - sim.u_cy[u])
		if d < best_d:
			best = o
			best_d = d
	return best


## Assault: attack a defender (not on a wall) within STORM_R, else make for
## the plaza (an open town: first the street mouth given to this unit).
static func _storm(sim, u: int) -> void:
	BattleAI._set_mode(sim, u, A_STORM)
	if _engaged(sim, u):
		return
	var best := -1
	var best_d := STORM_R
	# At the plaza with it still contested: go for the nearest defender off
	# the walls wherever he is (no stand-off at the plaza).
	# (All out, the units still go for the plaza when no defender is near:
	# hunting the last defenders all over the town let them hold out.)
	if BattleAI._d(sim.u_cx[u] - sim.plaza[0], sim.u_cy[u] - sim.plaza[1]) < sim.plaza[3] + 15 * M \
			and sim.cap_t == 0:
		best_d = 1 << 30
	var cg: int = sim.cit_gate
	var cit_shut: bool = cg >= 0 and sim.g_state[cg] == GATE_CLOSED
	for o in sim.n_units:
		if sim.u_side[o] == sim.u_side[u] or sim.u_state[o] != U_READY or sim.u_wall[o] > 0:
			continue
		if cit_shut and BattleAI._d(sim.u_cx[o] - sim.cit_x, sim.u_cy[o] - sim.cit_y) < sim.cit_r:
			continue  # behind the citadel's shut gate
		var d := BattleAI._d(sim.u_cx[o] - sim.u_cx[u], sim.u_cy[o] - sim.u_cy[u])
		if d >= best_d:
			continue
		# Spread out: every other unit of ours already on it counts as 25 m
		# more (a whole army queuing on one unit jams the streets).
		var crowd := 0
		for f in sim.n_units:
			if f != u and sim.u_side[f] == sim.u_side[u] and sim.u_state[f] == U_READY \
					and sim.u_order[f] == O_ATTACK and sim.u_target[f] == o:
				crowd += 1
		d += crowd * SPREAD
		if d < best_d:
			best = o
			best_d = d
	if best >= 0:
		if sim.u_order[u] != O_ATTACK or sim.u_target[u] != best:
			BattleAI._attack(sim, u, best, 1 if best_d < 25 * M else 0)
		return
	if cit_shut:
		# The citadel is shut: the three foot units nearest its gate hack at
		# it, the rest gather before it.
		var c: int = sim.u_cls[u]
		if (c == UT.CLS_INF or c == UT.CLS_PIKE) and _near_rank(sim, u, sim.g_x[cg], sim.g_y[cg]) < 3:
			if sim.u_gtarget[u] != cg:
				BattleAI._order(sim, u, {"type": ORDER_ATTACK, "target": -1, "gate": cg, "run": 0}, 0)
			return
		var rkc := _rank(sim, u, func(o): return sim.u_cls[o] == UT.CLS_INF or sim.u_cls[o] == UT.CLS_PIKE)
		var cspot := _gate_point(sim, cg, 20 * M, _spread(rkc.x % 5, mini(rkc.y, 5), 14 * M))
		var cface := FM.atan2_a(sim.g_y[cg] - cspot.y, sim.g_x[cg] - cspot.x)
		_go_home(sim, u, cspot.x, cspot.y, cface, 8)
		return
	var px: int = sim.plaza[0]
	var py: int = sim.plaza[1]
	if sim.n_gates == 0 and sim.u_ai_x[u] == 0:
		# Open town: by the streets, shared out.
		var lay: Dictionary = sim.map_info["city"]
		var mouths: Array = lay.get("mouths", [])
		if not mouths.is_empty():
			var rk := _rank(sim, u, func(o): return sim.u_cls[o] == UT.CLS_INF or sim.u_cls[o] == UT.CLS_PIKE)
			var st: Array = mouths[rk.x % mouths.size()]
			var mx: int = int(st[0]) * M
			var my: int = int(st[1]) * M
			if BattleAI._d(sim.u_ax[u] - mx, sim.u_ay[u] - my) > 15 * M:
				var f := FM.atan2_a(py - my, px - mx)
				if sim.u_order[u] != O_MOVE or BattleAI._d(sim.u_dx[u] - mx, sim.u_dy[u] - my) > 6 * M:
					BattleAI._move(sim, u, mx, my, f, BattleAI._width(sim, u), 0, 3)
				return
			sim.u_ai_x[u] = 1
	# Into the plaza (spread a little so several units fit).
	var rk2 := _rank(sim, u, func(o): return sim.u_cls[o] == UT.CLS_INF or sim.u_cls[o] == UT.CLS_PIKE)
	var off: int = _spread(rk2.x % 4, mini(rk2.y, 4), sim.plaza[2] / 2)
	var tx: int = px + off
	var ty: int = py
	var far := BattleAI._d(tx - sim.u_ax[u], ty - sim.u_ay[u])
	var face: int = FM.atan2_a(ty - sim.u_ay[u], tx - sim.u_ax[u]) if far > 10 * M else sim.u_face[u]
	# Run while no defender is near (pikes walk: running breaks their order).
	var run := 1 if far > 40 * M and sim.u_cls[u] != UT.CLS_PIKE else 0
	_go_run(sim, u, tx, ty, face, 6, run)


static func _att_missile(sim, u: int, phase: int) -> void:
	var side: int = sim.u_side[u]
	if sim.u_fire[u] == 0 and sim.u_ammo[u] > 0:
		BattleAI._order(sim, u, {"type": ORDER_FIRE, "on": 1}, 21)
	var g: int = sim.ai_gate[side]
	if phase == SP_PURSUE:
		var r := _router(sim, u, 40 * M)
		if r >= 0 and sim.u_ammo[u] <= 0:
			if sim.u_order[u] != O_ATTACK or sim.u_target[u] != r:
				BattleAI._attack(sim, u, r, 1)
		return
	if phase == SP_ASSAULT and (sim.ai_prog[2] != 0 or _no_foot(sim, side) or sim.u_ammo[u] <= 0):
		_storm(sim, u)
		return
	BattleAI._set_mode(sim, u, A_COVER)
	if g < 0:
		if sim.n_gates == 0:
			# Open town: stand off the edge facing it.
			var lay: Dictionary = sim.map_info["city"]
			var cx: int = int(lay["cx"]) * M
			var cy: int = int(lay["cy"]) * M
			var rk0 := _rank(sim, u, func(o): return sim.u_cls[o] == UT.CLS_MISSILE)
			var ox: int = sim.u_ax[u]
			var oy: int = sim.u_ay[u]
			var dd := maxi(BattleAI._d(ox - cx, oy - cy), 1)
			var want := int(lay["r0"]) * M * 112 / 100 + 50 * M
			var tx := clampi(cx + (ox - cx) * want / dd + _spread(rk0.x, rk0.y, 20 * M), 8 * M, sim.field_w - 8 * M)
			var ty := clampi(cy + (oy - cy) * want / dd, 8 * M, sim.field_h - 8 * M)
			if dd > want + 10 * M:
				_go_home(sim, u, tx, ty, FM.atan2_a(cy - ty, cx - tx), 10)
		return
	var out := COVER_OUT
	if phase == SP_ASSAULT:
		out = 40 * M  # follow up to the breach
	if UT.stat(sim.u_type[u], "m_arc") == 0 and phase == SP_APPROACH:
		out = STAGE_OUT  # javelins wait with the foot
	var rk := _rank(sim, u, func(o): return sim.u_cls[o] == UT.CLS_MISSILE)
	var spot := _gate_point(sim, g, out, _spread(rk.x, rk.y, 26 * M))
	var face := FM.atan2_a(sim.g_y[g] - spot.y, sim.g_x[g] - spot.x)
	_go_home(sim, u, spot.x, spot.y, face, 10)


static func _att_cav(sim, u: int, phase: int) -> void:
	var side: int = sim.u_side[u]
	if phase == SP_PURSUE:
		var r := _router(sim, u, 200 * M)
		if r >= 0:
			if sim.u_order[u] != O_ATTACK or sim.u_target[u] != r:
				BattleAI._attack(sim, u, r, 1)
			return
	if phase == SP_ASSAULT and (sim.ai_prog[2] != 0 or _no_foot(sim, side)):
		_storm(sim, u)
		return
	BattleAI._set_mode(sim, u, A_CAVOUT)
	if _engaged(sim, u):
		return
	var t := _nearest_outside(sim, u, 100 * M)
	if t >= 0:
		if sim.u_order[u] != O_ATTACK or sim.u_target[u] != t:
			BattleAI._attack(sim, u, t, 1)
		return
	var g: int = sim.ai_gate[side]
	if g < 0:
		return
	var rk := _rank(sim, u, func(o): return sim.u_cls[o] == UT.CLS_CAV)
	var lat := (90 + rk.x / 2 * 30) * M * (1 if rk.x % 2 == 0 else -1)
	var spot := _gate_point(sim, g, STAGE_OUT + 20 * M, lat)
	var face := FM.atan2_a(sim.g_y[g] - spot.y, sim.g_x[g] - spot.x)
	_go_home(sim, u, spot.x, spot.y, face, 12)


## Nearest routing enemy within r that can be reached (not on a wall).
static func _router(sim, u: int, within: int) -> int:
	var best := -1
	var best_d := within * within
	for o in sim.n_units:
		if sim.u_side[o] == sim.u_side[u] or sim.u_state[o] != U_ROUTING or sim.u_wall[o] > 0:
			continue
		var d := BattleAI._dist2(sim, u, o)
		if d < best_d:
			best = o
			best_d = d
	return best
