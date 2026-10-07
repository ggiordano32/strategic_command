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
## Siege equipment and wall towers (docs/AI.md 13), every level:
##   ram       goes at the gate the army goes for (Skilled: waits first for
##             the towers by it to be silenced, at most S_RAM_WAIT) and
##             batters it; it never storms.
##   ladders   against walls of S_LADDER_WALLS or more (any walls without
##             working artillery), S_LADDER_AFTER into the approach or once
##             the gate is below 85 %, the S_LADDER_UNITS heaviest foot units
##             carrying ladders climb the land wall within 140 m of that gate
##             where it is weakest (metres from the gate + S_LADDER_DEF_W per
##             defender on the walls within 40 m, x 60 per working tower
##             within 60 m; one unit a stretch); once up they go down into
##             the town to the inside of the nearest closed gate and unbar it.
##   batteries shoot the towers within S_COUNTER_BAT of the gate first.
##   towers    (defenders) shoot the ram, then batteries, then men at a gate
##             or on the ladders, in reach (S_TOWER_FOCUS), else at will.
##   reply     (defenders, S_ESC_REPLY) a reserve foot unit goes up onto a
##             stretch where attackers climb or stand, and fights them.
## With a working ram, the foot do not hack at the gate.
## Profiles: the distances, times and ratios above are knobs of the side's
## skill / personality profile (sim/ai_profile.gd, the S_* knobs and the
## field AI's shared ones), read as kn[AP.X] with kn = AP.of(sim, side).
## Easy: hacks at the nearest gate with everything from the start (no
## bombardment first), storming foot run after routers (M_CHASE), reserves
## react late (and sometimes a think later still: M_LATE_FLANK), gates are
## closed late and
## sometimes not at all (M_GATE_OPEN), wall units come down late and the
## citadel is taken only when attackers inside outnumber the defenders
## twice (S_CIT_OUTNUMBER_PCT); attackers may withdraw early (M_EARLY_WD).

const FM := preload("res://sim/fixed_math.gd")
const UT := preload("res://sim/unit_types.gd")
const BattleAI := preload("res://sim/battle_ai.gd")
const MapGen := preload("res://sim/mapgen.gd")
const AP := preload("res://sim/ai_profile.gd")

const M := 1024

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

# BattleSim's siege values (u_stair while going up ladders; a ram's crew).
const ST_LADDER := 4
const ST_LADDER_GO := 5
const RAM_MEN := 6

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
const A_RAM := 30       # attacking ram
const A_LADDER := 31    # attacking foot going up the ladders (then into the town to unbar a gate)
const A_TOWER := 32     # defending tower engine
const A_ESC := 33       # defender sent up against ladder men (u_ai_y = the attacking unit)
const A_BREACH := 34    # defender holding the inside of a breached gate beside it (u_ai_x / u_ai_y = post)



static func think(sim) -> void:
	var tick: int = sim.tick
	var kn0 := AP.of(sim, 0)
	var kn1 := AP.of(sim, 1)
	var unit_period := PackedInt32Array([kn0[AP.UNIT_THINK], kn1[AP.UNIT_THINK]])
	for side in 2:
		if sim.ai_sides[side] != 0 and tick % (kn0 if side == 0 else kn1)[AP.ARMY_THINK] == 0:
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
		if (k + tick) % unit_period[side] != 0:
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
	var kn := AP.of(sim, side)
	if side == sim.city_def:
		if phase != SD_HOLD:
			sim.ai_phase[side] = SD_HOLD
			sim.ai_t[side] = sim.tick
			for u in sim.n_units:
				if sim.u_side[u] == side and sim.u_state[u] == U_READY:
					_classify_defender(sim, u)
		_close_gates(sim, side)
		if sim.sg_on != 0 and kn[AP.S_ESC_REPLY] != 0:
			_esc_reply(sim, side)
		if sim.cit_r > 0:
			_citadel(sim, side)
		if kn[AP.SK_MEM] != 0:
			_sk_defend(sim, side, kn)
		if kn[AP.S_BREACH_HOLD] != 0:
			_breach_hold(sim, side, kn)
		return
	# Attackers. Clearly lost: withdraw (as in the field).
	var own := BattleAI._strength(sim, side)
	var foe := BattleAI._strength(sim, 1 - side)
	if sim.tick > kn[AP.WD_MIN_TICK] and foe > 0 and (own * 100 < foe * kn[AP.WD_FOE_PCT] \
			or (own * 100 < BattleAI._start_strength(sim, side) * kn[AP.S_BEATEN_PCT] and own < foe)):
		sim.queue_order({"tick": sim.tick, "type": ORDER_WITHDRAW_ALL, "side": side,
			"player": BattleAI.AI_PLAYER_BASE + side, "seq": 9000})
		sim.ai_phase[side] = P_WITHDRAW
		sim.ai_t[side] = sim.tick
		sim.stat_ai[8] += 1
		return
	# Mistake: giving up while still in the fight (once a battle).
	if kn[AP.WD_EARLY_PCT] > 0 and sim.tick > kn[AP.WD_MIN_TICK] and foe > 0 and own * 100 < foe * kn[AP.WD_EARLY_PCT] \
			and BattleAI._mistake_once(sim, side, AP.M_EARLY_WD, kn):
		BattleAI.withdraw_all(sim, side, 9000)
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
	var stall: int = kn[AP.S_STALL_TICKS]
	if prog >= sim.ai_prog[0] + kn[AP.S_STALL_PROG] or (phase == SP_APPROACH and sim.tick - sim.ai_t[side] < 2 * kn[AP.S_HACK_AFTER]):
		# (The first four minutes of the approach - the batteries setting up
		# and bombarding, then the foot hacking - never count as a stall.)
		sim.ai_prog[0] = maxi(prog, sim.ai_prog[0])
		sim.ai_prog[1] = sim.tick
	elif phase == SP_ASSAULT and sim.tick - sim.ai_t[side] > kn[AP.S_ASSAULT_ALL] and sim.ai_prog[2] == 0:
		sim.ai_prog[2] = 1  # four minutes into the assault: everything goes in
	elif sim.tick - sim.ai_prog[1] > stall and (sim.ai_prog[2] == 0 \
			or sim.tick - sim.ai_prog[1] > 2 * stall):
		var foe_g := _ground_strength(sim, 1 - side)
		if sim.ai_prog[2] == 0 and own * 100 >= foe_g * kn[AP.S_ALLOUT_PCT]:
			sim.ai_prog[2] = 1  # all out
			sim.ai_prog[1] = sim.tick
		elif sim.ai_prog[2] != 0 and own * 100 >= foe_g * kn[AP.S_KEEP_PCT]:
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
				(sim.u_cls[u] == UT.CLS_INF or sim.u_cls[u] == UT.CLS_PIKE) and not sim.is_ram(u):
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
	var hp_w := AP.of(sim, side)[AP.S_GATE_HP_W]
	var best := -1
	var best_s := 0
	for g in sim.n_gates:
		if sim.g_state[g] != GATE_CLOSED or sim.g_cit[g] != 0:
			continue
		var s: int = BattleAI._d(sim.g_ox[g] - c.x, sim.g_oy[g] - c.y) / M + sim.g_hp[g] / 100 * hp_w / 100
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
	var kn := AP.of(sim, side)
	var close_r := kn[AP.S_CLOSE_R]
	for g in sim.n_gates:
		if sim.g_state[g] != GATE_OPEN or sim.g_cit[g] != 0:
			continue
		if kn[AP.SK_SALLY_R] > 0 and BattleAI._sd(sim, side, AP.SD_SALLY) == g + 1:
			continue  # our sally is out through it
		for o in sim.n_units:
			if sim.u_side[o] == side or sim.u_state[o] != U_READY:
				continue
			if BattleAI._d(sim.u_cx[o] - sim.g_x[g], sim.u_cy[o] - sim.g_y[g]) < close_r:
				if BattleAI._mistake(sim, side, AP.M_GATE_OPEN, kn):
					break  # left open this time
				sim.queue_order({"tick": sim.tick, "type": ORDER_GATE, "unit": any, "gate": g, "on": 1,
					"player": BattleAI.AI_PLAYER_BASE + side, "seq": 8000 + g})
				break


# ------------------------------------------------------------- defenders ---

static func _classify_defender(sim, u: int) -> void:
	if sim.u_wall[u] > 0:
		BattleAI._set_mode(sim, u, A_WALLU)
		return
	for g in sim.n_gates:
		if sim.g_cit[g] == 0 and BattleAI._d(sim.u_ax[u] - sim.g_ix[g], sim.u_ay[u] - sim.g_iy[g]) \
				< AP.of(sim, sim.u_side[u])[AP.S_GATE_POST_R]:
			BattleAI._set_mode(sim, u, A_GATE)
			sim.u_ai_y[u] = g
			sim.u_ai_x[u] = 0
			return
	BattleAI._set_mode(sim, u, A_RESERVE)
	sim.u_ai_x[u] = sim.u_ax[u]
	sim.u_ai_y[u] = sim.u_ay[u]


static func _defender(sim, u: int) -> void:
	if sim.sg_on != 0 and sim.is_tower(u):
		_tower(sim, u)
		return
	var mode: int = sim.u_ai[u]
	var kn := AP.of(sim, sim.u_side[u])
	if mode == A_ESC:
		_esc_unit(sim, u)
		return
	if kn[AP.SK_MEM] != 0 and _sk_defender(sim, u, kn):
		return
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
	if mode == A_BREACH:
		_breach_unit(sim, u)
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
	if _nearest_attacker(sim, u, sim.u_cx[u], sim.u_cy[u], AP.of(sim, sim.u_side[u])[AP.S_OFFWALL_R], true) < 0:
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
	var kn := AP.of(sim, side)
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
			if BattleAI._d(sim.u_cx[o] - sim.g_x[g], sim.u_cy[o] - sim.g_y[g]) < kn[AP.S_CIT_LOST_R]:
				lost = true
			if (sim.veg_bits(sim.u_cx[o], sim.u_cy[o]) & MapGen.V_URBAN) != 0:
				att += sim.u_alive[o]
		if not lost and att * 100 <= dfn * kn[AP.S_CIT_OUTNUMBER_PCT]:
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
					and BattleAI._d(sim.u_cx[o] - sim.g_x[g], sim.u_cy[o] - sim.g_y[g]) < kn[AP.S_CIT_SHUT_R]:
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
	var best_d: int = sim.cit_r + AP.of(sim, sim.u_side[u])[AP.S_CIT_REACT]
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
	var kn := AP.of(sim, sim.u_side[u])
	var t := _nearest_attacker(sim, u, gx, gy, kn[AP.S_GATE_REACT], false)
	if t >= 0:
		BattleAI._attack(sim, u, t, 0)
		return
	if sim.g_state[g] == GATE_BROKEN:
		# The gate has fallen and nobody is at it: hold the street behind.
		var t2 := _nearest_attacker(sim, u, gx, gy, kn[AP.S_STREET_R], true)
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
	var kn := AP.of(sim, sim.u_side[u])
	var t := _nearest_attacker(sim, u, hx, hy, kn[AP.S_RESERVE_R], true)
	if t >= 0 and sim.u_cls[u] != UT.CLS_ART:
		if sim.u_cls[u] == UT.CLS_MISSILE and sim.u_ammo[u] > 0:
			return  # shoot from the post (fire at will)
		if (sim.u_order[u] != O_ATTACK or sim.u_target[u] != t) \
				and BattleAI._mistake(sim, sim.u_side[u], AP.M_LATE_FLANK, kn):
			return  # attackers in the streets, noticed late
		var run_r := kn[AP.S_RESERVE_RUN]
		BattleAI._attack(sim, u, t, 1 if BattleAI._dist2(sim, u, t) < run_r * run_r else 0)
		return
	var face: int = FM.atan2_a(sim.g_y[0] - hy, sim.g_x[0] - hx) if sim.n_gates > 0 else sim.u_dface[u]
	_go_home(sim, u, hx, hy, face, 10)


## Hold the breach (S_BREACH_HOLD; units do not pass through each other,
## so attackers come out of a gateway one unit at a time): once a gate is
## open or broken with attackers within 100 m of it, the reserve foot unit
## nearest each of two posts inside the wall, S_BREACH_LAT either side of
## the gate (on open ground of the town's side), takes it (A_BREACH); with
## the gate's guard in the street behind the gate they close the mouth of
## the gateway on three sides. Once per breached gate (ai_gate of the
## defending side remembers it).
static func _breach_hold(sim, side: int, kn: PackedInt32Array) -> void:
	var ag := -1
	for g in sim.n_gates:
		if sim.g_cit[g] == 0 and sim.g_state[g] != GATE_CLOSED \
				and _attackers_near(sim, side, sim.g_x[g], sim.g_y[g], 100 * M) > 0:
			ag = g
			break
	if ag < 0:
		return
	if kn[AP.S_GUARD_JOIN] > 0:
		_guards_join(sim, side, ag, kn)
	if sim.ai_gate[side] == ag:
		return
	sim.ai_gate[side] = ag
	var dir: int = sim.g_dir[ag]
	var c := FM.cos_a(dir)
	var sn := FM.sin_a(dir)
	var gi := Vector2i(sim.g_ix[ag], sim.g_iy[ag])
	var piece: int = sim.reach_at(gi.x, gi.y)
	for lr in [1, -1]:
		# Along the wall (across the gate's outward direction), a little in.
		var post := Vector2i(-1, -1)
		for inw in [0, 4, 8]:
			var lat: int = kn[AP.S_BREACH_LAT] * lr
			var px: int = gi.x - (c * inw * M + sn * lat) / FM.TRIG_ONE
			var py: int = gi.y - (sn * inw * M - c * lat) / FM.TRIG_ONE
			if sim.obs_kind(px, py) == MapGen.C_OPEN and (sim.nav_at(px, py) & MapGen.NAV_GROUND) != 0 \
					and sim.reach_at(px, py) == piece:
				post = Vector2i(px, py)
				break
		if post.x < 0:
			continue
		var best := -1
		var bd := 0
		for u in sim.n_units:
			if sim.u_side[u] != side or sim.u_state[u] != U_READY or sim.u_ai[u] != A_RESERVE:
				continue
			var cl: int = sim.u_cls[u]
			if cl != UT.CLS_INF and cl != UT.CLS_PIKE:
				continue
			var d := BattleAI._d(sim.u_cx[u] - post.x, sim.u_cy[u] - post.y)
			if best < 0 or d < bd:
				best = u
				bd = d
		if best < 0:
			return
		BattleAI._set_mode(sim, best, A_BREACH)
		sim.u_ai_x[best] = post.x
		sim.u_ai_y[best] = post.y
		BattleAI._count(sim, side, AP.C_SIEGE)


## The guards of the other gates with no attacker within S_GUARD_JOIN of
## their gate come to the breach (gate ag): reserves posted 30 m inside it
## (the plaza if that is not open ground of the town), so the whole army
## fights where the attackers come in.
static func _guards_join(sim, side: int, ag: int, kn: PackedInt32Array) -> void:
	var dir: int = sim.g_dir[ag]
	var c := FM.cos_a(dir)
	var sn := FM.sin_a(dir)
	var piece: int = sim.reach_at(sim.g_ix[ag], sim.g_iy[ag])
	var k := 0
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY or sim.u_ai[u] != A_GATE:
			continue
		var g: int = sim.u_ai_y[u]
		if g == ag or _attackers_near(sim, side, sim.g_x[g], sim.g_y[g], kn[AP.S_GUARD_JOIN]) > 0:
			continue
		# Posts spread behind the breach (30 m in, 12 m apart), the plaza
		# where that is not open ground of the town.
		var back := (30 + 12 * (k / 3)) * M
		var lat := ((k % 3) - 1) * 12 * M
		var px: int = sim.g_ix[ag] - (c * back + sn * lat) / FM.TRIG_ONE
		var py: int = sim.g_iy[ag] - (sn * back - c * lat) / FM.TRIG_ONE
		if sim.obs_kind(px, py) != MapGen.C_OPEN or sim.reach_at(px, py) != piece:
			px = sim.plaza[0] + lat
			py = sim.plaza[1]
		k += 1
		BattleAI._set_mode(sim, u, A_RESERVE)
		sim.u_ai_x[u] = px
		sim.u_ai_y[u] = py
		BattleAI._count(sim, side, AP.C_SIEGE)


## A unit holding beside a breached gate: attack attackers that come within
## S_BREACH_REACT of its post (out of the gateway), else back to the post
## facing the gate's mouth.
static func _breach_unit(sim, u: int) -> void:
	if _engaged(sim, u):
		return
	var side: int = sim.u_side[u]
	var kn := AP.of(sim, side)
	var hx: int = sim.u_ai_x[u]
	var hy: int = sim.u_ai_y[u]
	var t := _nearest_attacker(sim, u, hx, hy, kn[AP.S_BREACH_REACT], false)
	if t >= 0 and sim.u_wall[t] == 0:
		if sim.u_order[u] != O_ATTACK or sim.u_target[u] != t:
			BattleAI._attack(sim, u, t, 0)
		return
	var g: int = sim.ai_gate[side]
	var face: int = sim.u_dface[u]
	if g >= 0:
		face = FM.atan2_a(sim.g_iy[g] - hy, sim.g_ix[g] - hx)
	_go_home(sim, u, hx, hy, face, 6)


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
	var kn := AP.of(sim, side)
	if mode != BattleAI.A_RETIRE and sim.u_alive[u] * 100 < sim.u_count0[u] * kn[AP.RETIRE_ALIVE_PCT] \
			and sim.u_morale[u] < kn[AP.RETIRE_MORALE]:
		BattleAI._retire(sim, u)
		return
	if mode == BattleAI.A_RETIRE:
		if sim.tick - sim.u_ai_t[u] < kn[AP.RETIRE_TICKS] or sim.u_order[u] != O_NONE:
			return
		if sim.u_routs[u] == 0 and sim.u_alive[u] * 100 < sim.u_count0[u] * kn[AP.RETIRE_ALIVE_PCT]:
			BattleAI._count(sim, side, AP.C_SAVED)
		BattleAI._set_mode(sim, u, A_WAIT)
	if sim.sg_on != 0 and sim.is_ram(u):
		_att_ram(sim, u, phase)
	elif cls == UT.CLS_ART:
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
	var kn := AP.of(sim, side)
	BattleAI._set_mode(sim, u, A_SART)
	var ty: int = sim.u_type[u]
	var full: int = sim.u_neng[u] * UT.stat(ty, "m_ammo")
	# Refilling or getting into / out of it: as in the field.
	if sim.u_refill[u] != 0:
		if BattleAI._art_threatened(sim, u) or sim.u_ammo[u] * 100 >= full * kn[AP.REFILL_FULL_PCT]:
			BattleAI._order(sim, u, {"type": ORDER_REFILL, "on": 0}, 23)
		return
	if sim.u_rprog[u] > 0:
		return
	if sim.u_ammo[u] * 100 <= full * kn[AP.REFILL_LOW_PCT] and BattleAI._can_refill(sim, u) and not BattleAI._art_threatened(sim, u) \
			and sim.u_order[u] != O_MOVE:
		BattleAI._order(sim, u, {"type": ORDER_REFILL, "on": 1}, 23)
		return
	var g: int = sim.ai_gate[side]
	if phase == SP_APPROACH and g >= 0 and sim.g_state[g] == GATE_CLOSED and sim.u_ammo[u] > 0:
		var rk := _rank(sim, u, func(o): return sim.u_cls[o] == UT.CLS_ART)
		var lat := _spread(rk.x, rk.y, kn[AP.S_ART_SPREAD])
		var spot := _gate_point(sim, g, kn[AP.S_ART_OUT], lat)
		if UT.stat(ty, "m_kind") == 1:
			# Bolts need a clear flat line to the gate: try further aside.
			var f: Vector2i = sim.gate_face(g)
			for off in [0, 20, -20, 40, -40]:
				var cand := _gate_point(sim, g, kn[AP.S_ART_OUT], lat + off * M)
				if sim.lof_block(cand.x, cand.y, sim.height_at(cand.x, cand.y) + 1536, f.x, f.y,
						sim.height_at(f.x, f.y) + 1024, 0, 0, 8192) < 0:
					spot = cand
					break
		if BattleAI._d(sim.u_ax[u] - spot.x, sim.u_ay[u] - spot.y) > 12 * M:
			if sim.u_order[u] != O_MOVE or BattleAI._d(sim.u_dx[u] - spot.x, sim.u_dy[u] - spot.y) > 6 * M:
				var face := FM.atan2_a(sim.g_y[g] - spot.y, sim.g_x[g] - spot.x)
				BattleAI._move(sim, u, spot.x, spot.y, face, BattleAI._width(sim, u), 0, 6)
			return
		if kn[AP.SK_WALL_ART] > 0 and _sk_wall_target(sim, u, g, kn):
			return
		if sim.sg_on != 0 and kn[AP.S_COUNTER_BAT] > 0:
			var tw := _tower_near_gate(sim, u, g, kn[AP.S_COUNTER_BAT], true)
			if tw >= 0:
				if sim.u_order[u] != O_ATTACK or sim.u_target[u] != tw:
					BattleAI._attack(sim, u, tw, 0)
				return
		if sim.u_order[u] != O_ATTACK or sim.u_gtarget[u] != g:
			BattleAI._order(sim, u, {"type": ORDER_ATTACK, "target": -1, "gate": g, "run": 0}, 0)
		return
	var cg: int = sim.cit_gate
	if phase == SP_ASSAULT and cg >= 0 and sim.g_state[cg] == GATE_CLOSED and sim.u_ammo[u] > 0:
		# The citadel's gate, if it is within reach from here.
		var f: Vector2i = sim.gate_face(cg)
		var dcg := BattleAI._d(f.x - sim.u_cx[u], f.y - sim.u_cy[u])
		var reach: int = UT.stat(ty, "m_range") * kn[AP.S_ART_REACH_PCT] / 100
		if dcg < reach:
			if sim.u_order[u] != O_ATTACK or sim.u_gtarget[u] != cg:
				BattleAI._order(sim, u, {"type": ORDER_ATTACK, "target": -1, "gate": cg, "run": 0}, 0)
			return
		# Out of reach: bring the battery up (through the breach if need be)
		# to 70 % of its range from the citadel's gate.
		var want := UT.stat(ty, "m_range") * kn[AP.S_ART_CLOSE_PCT] / 100
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
		if sim.sg_on != 0 and (sim.u_ai[o] == A_LADDER or sim.is_ram(o)):
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
	var kn := AP.of(sim, side)
	if phase == SP_PURSUE:
		var r := _router(sim, u, kn[AP.S_FOOT_ROUTER_R])
		if r >= 0:
			if sim.u_order[u] != O_ATTACK or sim.u_target[u] != r:
				BattleAI._attack(sim, u, r, 1)
				BattleAI._count(sim, side, AP.C_INF_CHASE)
			return
		_storm(sim, u)
		return
	if phase == SP_ASSAULT:
		_storm(sim, u)
		return
	var g: int = sim.ai_gate[side]
	if g < 0:
		return
	if sim.sg_on != 0 and sim.u_lad[u] != 0 and (sim.u_ai[u] == A_LADDER \
			or (_ladder_time(sim, side, g, kn) and _ladder_rank(sim, u) < kn[AP.S_LADDER_UNITS])):
		_escalade(sim, u, g, kn)
		return
	# Hack at the gate: with no battery from the start, else after a while
	# of bombardment.
	var hackers: int = kn[AP.S_HACKERS]
	if not _art_ready(sim, side):
		hackers = 99 if sim.tick - sim.ai_t[side] > 2 * kn[AP.S_HACK_AFTER] else kn[AP.S_HACKERS]
	elif sim.tick - sim.ai_t[side] < kn[AP.S_HACK_AFTER]:
		hackers = 0
	if sim.sg_on != 0 and _ram_ready(sim, side):
		hackers = 0  # the ram breaks the gate
	if _hack_rank(sim, u) < hackers:
		BattleAI._set_mode(sim, u, A_HACK)
		if _engaged(sim, u):
			return
		if sim.u_gtarget[u] != g:
			var far := BattleAI._d(sim.u_cx[u] - sim.g_ox[g], sim.u_cy[u] - sim.g_oy[g]) > kn[AP.S_HACK_RUN]
			BattleAI._order(sim, u, {"type": ORDER_ATTACK, "target": -1, "gate": g,
				"run": 1 if far and sim.u_cls[u] != UT.CLS_PIKE else 0}, 0)
		return
	BattleAI._set_mode(sim, u, A_WAIT)
	# Defenders outside the walls near us: fight them.
	var t := _nearest_outside(sim, u, kn[AP.S_OUTSIDE_R])
	if t >= 0:
		if not _engaged(sim, u):
			BattleAI._attack(sim, u, t, 1)
		return
	var rk := _rank(sim, u, func(o): return sim.u_cls[o] == UT.CLS_INF or sim.u_cls[o] == UT.CLS_PIKE)
	var spot := _gate_point(sim, g, kn[AP.S_STAGE_OUT], _spread(rk.x, rk.y, kn[AP.S_FOOT_SPREAD]))
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
	var kn := AP.of(sim, sim.u_side[u])
	if kn[AP.MK_BASE + AP.M_CHASE] > 0 and (sim.u_order[u] != O_ATTACK or sim.u_target[u] < 0 \
			or sim.u_state[sim.u_target[u]] != U_ROUTING):
		# Mistake: storming foot run after a routing defender near them.
		var r := _router(sim, u, kn[AP.S_STORM_R])
		if r >= 0 and BattleAI._mistake(sim, sim.u_side[u], AP.M_CHASE, kn):
			BattleAI._attack(sim, u, r, 1)
			BattleAI._count(sim, sim.u_side[u], AP.C_INF_CHASE)
			return
	var spread: int = kn[AP.S_SPREAD]
	var best := -1
	var best_d: int = kn[AP.S_STORM_R]
	# At the plaza with it still contested: go for the nearest defender off
	# the walls wherever he is (no stand-off at the plaza).
	# (All out, the units still go for the plaza when no defender is near:
	# hunting the last defenders all over the town let them hold out.)
	if BattleAI._d(sim.u_cx[u] - sim.plaza[0], sim.u_cy[u] - sim.plaza[1]) < sim.plaza[3] + kn[AP.S_PLAZA_HUNT] \
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
		d += crowd * spread
		if d < best_d:
			best = o
			best_d = d
	if best >= 0:
		if sim.u_order[u] != O_ATTACK or sim.u_target[u] != best:
			BattleAI._attack(sim, u, best, 1 if best_d < kn[AP.S_STORM_RUN] else 0)
		return
	if cit_shut:
		# The citadel is shut: the three foot units nearest its gate hack at
		# it, the rest gather before it.
		var c: int = sim.u_cls[u]
		if (c == UT.CLS_INF or c == UT.CLS_PIKE) and _near_rank(sim, u, sim.g_x[cg], sim.g_y[cg]) < kn[AP.S_CIT_HACKERS]:
			if sim.u_gtarget[u] != cg:
				BattleAI._order(sim, u, {"type": ORDER_ATTACK, "target": -1, "gate": cg, "run": 0}, 0)
			return
		var rkc := _rank(sim, u, func(o): return sim.u_cls[o] == UT.CLS_INF or sim.u_cls[o] == UT.CLS_PIKE)
		var cspot := _gate_point(sim, cg, kn[AP.S_CIT_GATHER], _spread(rkc.x % 5, mini(rkc.y, 5), kn[AP.S_CIT_SPREAD]))
		var cface := FM.atan2_a(sim.g_y[cg] - cspot.y, sim.g_x[cg] - cspot.x)
		_go_home(sim, u, cspot.x, cspot.y, cface, 8)
		return
	if kn[AP.SK_STORM_STAGGER] != 0 and _sk_storm_wait(sim, u, kn):
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
	var run := 1 if far > kn[AP.S_PLAZA_RUN] and sim.u_cls[u] != UT.CLS_PIKE else 0
	_go_run(sim, u, tx, ty, face, 6, run)


static func _att_missile(sim, u: int, phase: int) -> void:
	var side: int = sim.u_side[u]
	var kn := AP.of(sim, side)
	if sim.u_fighting[u] > 0:
		BattleAI._count(sim, side, AP.C_MISSILE_CAUGHT)
	if sim.u_fire[u] == 0 and sim.u_ammo[u] > 0:
		BattleAI._order(sim, u, {"type": ORDER_FIRE, "on": 1}, 21)
	var g: int = sim.ai_gate[side]
	if phase == SP_PURSUE:
		var r := _router(sim, u, kn[AP.S_MIS_ROUTER_R])
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
			var want := int(lay["r0"]) * M * kn[AP.S_OPEN_PCT] / 100 + kn[AP.S_OPEN_OUT]
			var tx := clampi(cx + (ox - cx) * want / dd + _spread(rk0.x, rk0.y, 20 * M), 8 * M, sim.field_w - 8 * M)
			var ty := clampi(cy + (oy - cy) * want / dd, 8 * M, sim.field_h - 8 * M)
			if dd > want + 10 * M:
				_go_home(sim, u, tx, ty, FM.atan2_a(cy - ty, cx - tx), 10)
		return
	var out: int = kn[AP.S_COVER_OUT]
	if phase == SP_ASSAULT:
		out = kn[AP.S_MIS_BREACH]  # follow up to the breach
	if UT.stat(sim.u_type[u], "m_arc") == 0 and phase == SP_APPROACH:
		out = kn[AP.S_STAGE_OUT]  # javelins wait with the foot
	var rk := _rank(sim, u, func(o): return sim.u_cls[o] == UT.CLS_MISSILE)
	var spot := _gate_point(sim, g, out, _spread(rk.x, rk.y, kn[AP.S_MIS_SPREAD]))
	var face := FM.atan2_a(sim.g_y[g] - spot.y, sim.g_x[g] - spot.x)
	_go_home(sim, u, spot.x, spot.y, face, 10)


static func _att_cav(sim, u: int, phase: int) -> void:
	var side: int = sim.u_side[u]
	var kn := AP.of(sim, side)
	if phase == SP_PURSUE:
		var r := _router(sim, u, kn[AP.S_CAV_ROUTER_R])
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
	var t := _nearest_outside(sim, u, kn[AP.S_CAV_OUTSIDE_R])
	if t >= 0:
		if sim.u_order[u] != O_ATTACK or sim.u_target[u] != t:
			BattleAI._attack(sim, u, t, 1)
		return
	var g: int = sim.ai_gate[side]
	if g < 0:
		return
	var rk := _rank(sim, u, func(o): return sim.u_cls[o] == UT.CLS_CAV)
	var lat := (kn[AP.S_CAV_WING] + rk.x / 2 * kn[AP.S_CAV_WING_STEP]) * M * (1 if rk.x % 2 == 0 else -1)
	if kn[AP.SK_FEINT] != 0 and phase == SP_APPROACH:
		# The feint: the riders show themselves before another gate.
		var fg := _sk_feint_gate(sim, g)
		if fg >= 0:
			if BattleAI._mem(sim, u, AP.MU_X) == 0:
				BattleAI._mset(sim, u, AP.MU_X, 1)
				BattleAI._count(sim, side, AP.C_SIEGE)
			g = fg
			lat = (rk.x * 2 - (rk.y - 1)) * 15 * M
	var spot := _gate_point(sim, g, kn[AP.S_STAGE_OUT] + kn[AP.S_CAV_BACK], lat)
	var face := FM.atan2_a(sim.g_y[g] - spot.y, sim.g_x[g] - spot.x)
	_go_home(sim, u, spot.x, spot.y, face, 12)


# ------------------------------------------------------ Skilled (step 3) ---
# Settlement behaviours only a profile with the SK_* knobs runs (docs/AI.md
# 11); memory in BattleSim.ai_mem (BattleAI._mem / _sd).

## Defenders, army level: read which gate is attacked (the one being
## damaged, else one open or broken with attackers near, else the one
## nearest the attackers), shift idle wall units toward it, bring missile
## troops down before it falls, move the reserves' posts up behind it,
## and sally against a weak, isolated party outside a gate.
static func _sk_defend(sim, side: int, kn: PackedInt32Array) -> void:
	var ag := _sk_attacked_gate(sim, side)
	if ag >= 0:
		if kn[AP.SK_WALL_SHIFT] != 0:
			_sk_wall_shift(sim, side, ag, kn)
		if kn[AP.SK_MIS_DOWN_PCT] > 0:
			_sk_mis_down(sim, side, ag, kn)
		if kn[AP.SK_BREACH] != 0:
			_sk_breach_posts(sim, side, ag)
	if kn[AP.SK_SALLY_R] > 0:
		_sk_sally(sim, side, kn)


static func _sk_attacked_gate(sim, side: int) -> int:
	var best := -1
	var best_t: int = sim.tick - 300
	for g in sim.n_gates:
		if sim.g_cit[g] != 0:
			continue
		if sim.g_state[g] != GATE_CLOSED and _attackers_near(sim, side, sim.g_x[g], sim.g_y[g], 100 * M) > 0:
			return g
		if sim.g_state[g] == GATE_CLOSED and sim.g_hit_t[g] > best_t:
			best = g
			best_t = sim.g_hit_t[g]
	if best >= 0:
		return best
	# Nobody at a gate yet: the gate nearest the attackers' army.
	var c := _army_centre(sim, 1 - side)
	var bd := 0
	for g in sim.n_gates:
		if sim.g_cit[g] != 0:
			continue
		var d := BattleAI._d(sim.g_x[g] - c.x, sim.g_y[g] - c.y)
		if best < 0 or d < bd:
			best = g
			bd = d
	return best


## Ready attacking units within r of (x, y).
static func _attackers_near(sim, side: int, x: int, y: int, r: int) -> int:
	var n := 0
	for o in sim.n_units:
		if sim.u_side[o] != side and sim.u_state[o] == U_READY \
				and BattleAI._d(sim.u_cx[o] - x, sim.u_cy[o] - y) < r:
			n += 1
	return n


## Wall missile units with nobody in range, on a stretch more than 80 m
## from the attacked gate, move along to the stretch nearest it (at most
## two units a stretch). In transit: MU_X 10 + stretch.
static func _sk_wall_shift(sim, side: int, ag: int, _kn: PackedInt32Array) -> void:
	var gx: int = sim.g_x[ag]
	var gy: int = sim.g_y[ag]
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY or sim.u_ai[u] != A_WALLU:
			continue
		if sim.u_wall[u] == 0 or sim.u_stair[u] != 0 or sim.u_order[u] == O_MOVE or sim.u_ammo[u] <= 0 \
				or sim.u_cls[u] != UT.CLS_MISSILE:
			continue
		var sg0: int = sim.u_wall[u] - 1
		if sim._seg_off(sg0, gx, gy) <= 80 * M or _anyone_in_range(sim, u):
			continue
		var best := -1
		var bd := 0
		for sg in sim.ws_x0.size():
			if (sim.ws_fl[sg] & MapGen.SEG_CIT) != 0 or sg == sg0:
				continue
			var occ := 0
			for o in sim.n_units:
				if sim.u_side[o] == side and sim.u_state[o] == U_READY \
						and (sim.u_wall[o] == sg + 1 or BattleAI._mem(sim, o, AP.MU_X) == 10 + sg):
					occ += 1
			if occ >= 2:
				continue
			var d: int = sim._seg_off(sg, gx, gy)
			if d >= sim._seg_off(sg0, gx, gy):
				continue
			if best < 0 or d < bd:
				best = sg
				bd = d
		if best < 0:
			continue
		var p: Vector2i = sim.seg_pt(sim, best, sim.seg_t(sim, best, gx, gy))
		BattleAI._mset(sim, u, AP.MU_X, 10 + best)
		BattleAI._order(sim, u, {"type": 1, "x": p.x, "y": p.y, "facing": sim.ws_dir[best],
			"width": BattleAI._width(sim, u), "run": 1}, 2)
		BattleAI._count(sim, side, AP.C_SIEGE)


static func _anyone_in_range(sim, u: int) -> bool:
	for o in sim.n_units:
		if sim.u_side[o] != sim.u_side[u] and sim.u_state[o] == U_READY \
				and sim._unit_dist(u, o) <= sim.range_vs(u, o):
			return true
	return false


## Wall missile units within 60 m of the attacked gate come down to the
## street behind it when the gate is below SK_MIS_DOWN_PCT % of its hit
## points (before it falls and the stairs are cut off).
static func _sk_mis_down(sim, side: int, ag: int, kn: PackedInt32Array) -> void:
	if sim.g_state[ag] != GATE_CLOSED or sim.g_hp[ag] * 100 >= sim.g_hp0[ag] * kn[AP.SK_MIS_DOWN_PCT]:
		return
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY or sim.u_ai[u] != A_WALLU:
			continue
		if sim.u_wall[u] == 0 or sim.u_stair[u] != 0 or sim.u_order[u] == O_MOVE or sim.u_cls[u] != UT.CLS_MISSILE:
			continue
		if BattleAI._d(sim.u_cx[u] - sim.g_x[ag], sim.u_cy[u] - sim.g_y[ag]) > 60 * M:
			continue
		var p: Vector2i = sim.wall_inside(sim.u_wall[u] - 1, sim.u_cx[u], sim.u_cy[u])
		BattleAI._order(sim, u, {"type": 1, "x": p.x, "y": p.y, "facing": (sim.g_dir[ag] + 512) & 1023,
			"width": BattleAI._width(sim, u), "run": 1}, 2)
		BattleAI._count(sim, side, AP.C_SIEGE)


## Reserves' posts move up behind the attacked gate once it is below half
## its hit points (or open / broken), so they counter-charge the breach
## (MU_X 20: moved).
static func _sk_breach_posts(sim, side: int, ag: int) -> void:
	if sim.g_state[ag] == GATE_CLOSED and sim.g_hp[ag] * 2 >= sim.g_hp0[ag]:
		return
	var dir: int = sim.g_dir[ag]
	var k := 0
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY or sim.u_ai[u] != A_RESERVE:
			continue
		if sim.u_cls[u] == UT.CLS_MISSILE or sim.u_cls[u] == UT.CLS_ART or BattleAI._mem(sim, u, AP.MU_X) == 20:
			continue
		var hx: int = sim.u_ai_x[u]
		var hy: int = sim.u_ai_y[u]
		if BattleAI._d(hx - sim.g_ix[ag], hy - sim.g_iy[ag]) < 60 * M:
			continue
		var back := (25 + 12 * (k / 2)) * M
		var lat := (8 * M) * (1 if k % 2 == 0 else -1)
		var c := FM.cos_a(dir)
		var sn := FM.sin_a(dir)
		var px: int = sim.g_ix[ag] - (c * back + sn * lat) / FM.TRIG_ONE
		var py: int = sim.g_iy[ag] - (sn * back - c * lat) / FM.TRIG_ONE
		if (sim.veg_bits(px, py) & MapGen.V_URBAN) == 0 or sim.obs_kind(px, py) != MapGen.C_OPEN:
			continue
		sim.u_ai_x[u] = px
		sim.u_ai_y[u] = py
		BattleAI._mset(sim, u, AP.MU_X, 20)
		BattleAI._count(sim, side, AP.C_SIEGE)
		k += 1


## Sally: a closed gate with a weak party of attackers within SK_SALLY_R
## outside it and no other attackers within 2.5 times that: if the foot
## and riders within 60 m inside it are 1.5 times as strong, the gate opens
## and they go out at them (MU_X 30), back in after 45 s or when nobody is
## left near; the gate is shut again by the usual rule once they are in.
static func _sk_sally(sim, side: int, kn: PackedInt32Array) -> void:
	var r := kn[AP.SK_SALLY_R]
	var cur := BattleAI._sd(sim, side, AP.SD_SALLY) - 1
	if cur >= 0:
		if sim.tick - BattleAI._sd(sim, side, AP.SD_SALLY_T) > 450 \
				or _attackers_near(sim, side, sim.g_ox[cur], sim.g_oy[cur], 2 * r) == 0 or sim.g_state[cur] == GATE_BROKEN:
			BattleAI._sdset(sim, side, AP.SD_SALLY, 0)
			for u in sim.n_units:
				if sim.u_side[u] == side and BattleAI._mem(sim, u, AP.MU_X) == 30:
					BattleAI._mset(sim, u, AP.MU_X, 0)
		return
	for g in sim.n_gates:
		if sim.g_cit[g] != 0 or sim.g_state[g] != GATE_CLOSED:
			continue
		var ox: int = sim.g_ox[g]
		var oy: int = sim.g_oy[g]
		var near := _attackers_near(sim, side, ox, oy, r)
		if near == 0 or _attackers_near(sim, side, ox, oy, r * 5 / 2) != near:
			continue
		var att := 0
		for o in sim.n_units:
			if sim.u_side[o] != side and sim.u_state[o] == U_READY and BattleAI._d(sim.u_cx[o] - ox, sim.u_cy[o] - oy) < r:
				att += sim.u_alive[o] * UT.stat(sim.u_type[o], "cost")
		var dfn := 0
		var party: Array = []
		for u in sim.n_units:
			if sim.u_side[u] != side or sim.u_state[u] != U_READY or sim.u_wall[u] != 0:
				continue
			var c: int = sim.u_cls[u]
			if c == UT.CLS_MISSILE or c == UT.CLS_ART or sim.u_ai[u] == A_CIT:
				continue
			if BattleAI._d(sim.u_cx[u] - sim.g_ix[g], sim.u_cy[u] - sim.g_iy[g]) < 60 * M:
				dfn += sim.u_alive[u] * UT.stat(sim.u_type[u], "cost")
				party.append(u)
		if party.is_empty() or dfn * 100 < att * 150:
			continue
		sim.queue_order({"tick": sim.tick, "type": ORDER_GATE, "unit": party[0], "gate": g, "on": 0,
			"player": BattleAI.AI_PLAYER_BASE + side, "seq": 8000 + g})
		for u in party:
			BattleAI._mset(sim, u, AP.MU_X, 30)
		BattleAI._sdset(sim, side, AP.SD_SALLY, g + 1)
		BattleAI._sdset(sim, side, AP.SD_SALLY_T, sim.tick)
		BattleAI._count(sim, side, AP.C_SIEGE)
		return


## Defender unit think, Skilled parts first: a sallying unit goes at the
## nearest attacker outside its gate; a wall unit in transit to another
## stretch keeps going. Returns true when it handled the unit.
static func _sk_defender(sim, u: int, kn: PackedInt32Array) -> bool:
	var x := BattleAI._mem(sim, u, AP.MU_X)
	if x == 30:
		var g := BattleAI._sd(sim, sim.u_side[u], AP.SD_SALLY) - 1
		if g < 0:
			BattleAI._mset(sim, u, AP.MU_X, 0)
			return false
		if _engaged(sim, u):
			return true
		var t := _nearest_attacker(sim, u, sim.g_ox[g], sim.g_oy[g], 2 * kn[AP.SK_SALLY_R], false)
		if t >= 0:
			if sim.u_order[u] != O_ATTACK or sim.u_target[u] != t:
				BattleAI._attack(sim, u, t, 1)
			return true
		return false
	if x >= 10 and x < 20 and sim.u_ai[u] == A_WALLU:
		if sim.u_wall[u] == x - 9:
			BattleAI._mset(sim, u, AP.MU_X, 0)  # there
			return false
		if sim.u_wall[u] == 0 and (sim.u_stair[u] != 0 or sim.u_order[u] == O_MOVE):
			return true  # on its way along the streets to the other stretch
		if sim.u_order[u] != O_MOVE and sim.u_stair[u] == 0:
			BattleAI._mset(sim, u, AP.MU_X, 0)  # stopped short: it stays where it is
	return false


## Attacking batteries in their first SK_WALL_ART ticks at the gate shoot
## the wall units over it (within 60 m of it and in reach), if any.
static func _sk_wall_target(sim, u: int, g: int, kn: PackedInt32Array) -> bool:
	var side: int = sim.u_side[u]
	if sim.tick - sim.ai_t[side] > kn[AP.SK_WALL_ART] + 2 * kn[AP.S_HACK_AFTER] / 3:
		return false
	var ty: int = sim.u_type[u]
	var rng := UT.stat(ty, "m_range")
	var mn := UT.stat(ty, "m_min")
	var best := -1
	var bd := 0
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] != U_READY or sim.u_wall[o] == 0:
			continue
		var d := BattleAI._d(sim.u_cx[o] - sim.g_x[g], sim.u_cy[o] - sim.g_y[g])
		if d > 60 * M or not sim._art_in_range(u, o, mn, rng):
			continue
		if best < 0 or d < bd:
			best = o
			bd = d
	if best < 0:
		return false
	if sim.u_order[u] != O_ATTACK or sim.u_target[u] != best:
		BattleAI._attack(sim, u, best, 0)
	return true


## Storming foot outside the walls wait before the breach while three or
## more of ours are already crowding the street just inside it.
static func _sk_storm_wait(sim, u: int, _kn: PackedInt32Array) -> bool:
	var g: int = sim.ai_gate[sim.u_side[u]]
	if g < 0 or (sim.veg_bits(sim.u_cx[u], sim.u_cy[u]) & MapGen.V_URBAN) != 0:
		return false
	var crowd := 0
	for o in sim.n_units:
		if o != u and sim.u_side[o] == sim.u_side[u] and sim.u_state[o] == U_READY \
				and BattleAI._d(sim.u_cx[o] - sim.g_ix[g], sim.u_cy[o] - sim.g_iy[g]) < 25 * M:
			crowd += 1
	if crowd < 3:
		return false
	var spot := _gate_point(sim, g, 30 * M, _spread(_rank(sim, u, func(o): return sim.u_cls[o] == UT.CLS_INF \
		or sim.u_cls[o] == UT.CLS_PIKE).x % 3, 3, 20 * M))
	_go_home(sim, u, spot.x, spot.y, FM.atan2_a(sim.g_y[g] - spot.y, sim.g_x[g] - spot.x), 8)
	return true


## The other closed outer gate nearest gate g (the feint's), or -1.
static func _sk_feint_gate(sim, g: int) -> int:
	var best := -1
	var bd := 0
	for k in sim.n_gates:
		if k == g or sim.g_cit[k] != 0 or sim.g_state[k] != GATE_CLOSED:
			continue
		var d := BattleAI._d(sim.g_x[k] - sim.g_x[g], sim.g_y[k] - sim.g_y[g])
		if best < 0 or d < bd:
			best = k
			bd = d
	return best


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


# ------------------------------------------------ siege equipment, towers ---
# docs/AI.md 13. Runs only in battles with siege equipment or tower engines
# (sim.sg_on), so the others play exactly as before.

## The side has a ram that can still work a gate.
static func _ram_ready(sim, side: int) -> bool:
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and sim.is_ram(u) \
				and sim.u_alive[u] >= RAM_MEN:
			return true
	return false


## The ram: at the gate the army goes for (Skilled first waits, out of the
## towers' reach, for the towers by the gate to be silenced, at most
## S_RAM_WAIT into the approach); once the gate is down it stays outside.
static func _att_ram(sim, u: int, phase: int) -> void:
	var side: int = sim.u_side[u]
	var kn := AP.of(sim, side)
	BattleAI._set_mode(sim, u, A_RAM)
	var g: int = sim.ai_gate[side]
	if phase != SP_APPROACH or g < 0 or sim.g_state[g] != GATE_CLOSED:
		if sim.u_order[u] == O_MOVE and sim.u_gtarget[u] >= 0:
			BattleAI._order(sim, u, {"type": 3}, 22)  # halt
		return
	if kn[AP.S_RAM_WAIT] > 0 and sim.tick - sim.ai_t[side] < kn[AP.S_RAM_WAIT] \
			and _tower_near_gate(sim, -1, g, 40 * M, false) >= 0:
		var spot := _gate_point(sim, g, kn[AP.S_STAGE_OUT], 0)
		_go_home(sim, u, spot.x, spot.y, FM.atan2_a(sim.g_y[g] - spot.y, sim.g_x[g] - spot.x), 10)
		return
	if sim.u_gtarget[u] != g:
		BattleAI._order(sim, u, {"type": ORDER_ATTACK, "target": -1, "gate": g, "run": 0}, 0)
		BattleAI._count(sim, side, AP.C_SIEGE)


## An enemy tower engine still working (crew, engine, shots) within r of
## gate g's face, nearest it first; with battery u (>= 0, `reach`) only one
## it can shoot from where it stands. -1 none.
static func _tower_near_gate(sim, u: int, g: int, r: int, reach: bool) -> int:
	var f: Vector2i = sim.gate_face(g)
	var side: int = sim.u_side[u] if u >= 0 else 1 - sim.city_def
	var best := -1
	var bd := r
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] != U_READY or not sim.is_tower(o) or sim.u_ammo[o] <= 0:
			continue
		var d := BattleAI._d(sim.u_ax[o] - f.x, sim.u_ay[o] - f.y)
		if d >= bd:
			continue
		if reach:
			var ty: int = sim.u_type[u]
			if not sim._art_in_range(u, o, UT.stat(ty, "m_min"), UT.stat(ty, "m_range")):
				continue
			if UT.stat(ty, "m_kind") == 1 and not sim.lof_units(u, o):
				continue
		best = o
		bd = d
	return best


## Time for the ladders: S_LADDER_AFTER into the approach, or sooner once
## gate g is under attack (below 85 % of its hit points), so the defenders
## have two places to hold at once; never against a low wall
## (S_LADDER_WALLS) while the engines work.
static func _ladder_time(sim, side: int, g: int, kn: PackedInt32Array) -> bool:
	if sim.city_walls < kn[AP.S_LADDER_WALLS] and _art_ready(sim, side):
		return false  # the engines will have the gate down before the ladders are up
	if sim.tick - sim.ai_t[side] >= kn[AP.S_LADDER_AFTER]:
		return true
	return sim.g_hp[g] * 100 < sim.g_hp0[g] * 85


## Rank of ladder unit u among its side's ready infantry carrying ladders
## (heavy, light, spears; then by index).
static func _ladder_rank(sim, u: int) -> int:
	if sim.u_cls[u] != UT.CLS_INF:
		return 99
	var key := _foot_key(sim, u)
	var k := 0
	for o in sim.n_units:
		if o == u or sim.u_side[o] != sim.u_side[u] or sim.u_state[o] != U_READY or sim.u_lad[o] == 0:
			continue
		if sim.u_cls[o] != UT.CLS_INF:
			continue
		var ko := _foot_key(sim, o)
		if ko < key or (ko == key and o < u):
			k += 1
	return k


static func _foot_key(sim, u: int) -> int:
	var b := UT.base_of(sim.u_type[u])
	if b == UT.HEAVY:
		return 0
	if b == UT.LIGHT:
		return 1
	if b == UT.SPEAR:
		return 2
	return 3


## A ladder unit: on the ground outside, to the weakest stretch near gate g
## (_ladder_spot); climbing, on; up, down into the town to the inside of the
## nearest closed outer gate (it unbars it); inside with no closed gate
## left, it storms.
static func _escalade(sim, u: int, g: int, kn: PackedInt32Array) -> void:
	BattleAI._set_mode(sim, u, A_LADDER)
	var st: int = sim.u_stair[u]
	if st == ST_LADDER or st == ST_LADDER_GO:
		return
	if _engaged(sim, u):
		return
	var inside: bool = sim.u_wall[u] > 0 or st == 1
	if not inside:
		var ra: int = sim.reach_at(sim.u_ax[u], sim.u_ay[u])
		for k in sim.n_gates:
			if sim.g_cit[k] == 0 and ra >= 0 and sim.reach_at(sim.g_ix[k], sim.g_iy[k]) == ra:
				inside = true
				break
	if inside:
		var tg := -1
		var bd := 0
		for k in sim.n_gates:
			if sim.g_cit[k] != 0 or sim.g_state[k] != GATE_CLOSED:
				continue
			var d := BattleAI._d(sim.g_ix[k] - sim.u_cx[u], sim.g_iy[k] - sim.u_cy[u])
			if tg < 0 or d < bd:
				tg = k
				bd = d
		if tg < 0:
			_storm(sim, u)
			return
		if sim.u_gtarget[u] != tg:
			BattleAI._order(sim, u, {"type": ORDER_ATTACK, "target": -1, "gate": tg, "run": 1}, 0)
		return
	var p := _ladder_spot(sim, u, g, kn)
	if p.z < 0:
		return
	if sim.u_order[u] == O_MOVE and BattleAI._d(sim.u_dx[u] - p.x, sim.u_dy[u] - p.y) < 4 * M:
		return
	var far := BattleAI._d(sim.u_cx[u] - p.x, sim.u_cy[u] - p.y) > 60 * M
	BattleAI._order(sim, u, {"type": 1, "x": p.x, "y": p.y, "facing": sim.ws_dir[p.z],
		"width": BattleAI._width(sim, u), "run": 1 if far else 0}, 2)
	BattleAI._count(sim, sim.u_side[u], AP.C_SIEGE)


## Where ladder unit u climbs: the middle of a land-wall stretch within 140
## m of gate g with a foot it can reach, scored by metres from the gate plus
## S_LADDER_DEF_W per defending man on the walls within 40 m of it and 60
## per working tower within 60 m, a stretch another of ours is on (or bound
## for) 200 m more. (x, y, stretch); stretch -1 none.
static func _ladder_spot(sim, u: int, g: int, kn: PackedInt32Array) -> Vector3i:
	var best := Vector3i(0, 0, -1)
	var best_s := 0
	var side: int = sim.u_side[u]
	for sg in sim.ws_x0.size():
		if (sim.ws_fl[sg] & (MapGen.SEG_SEA | MapGen.SEG_CIT)) != 0:
			continue
		var p: Vector2i = sim.seg_pt(sim, sg, sim.seg_len(sim, sg) / 2)
		var dg := BattleAI._d(p.x - sim.g_x[g], p.y - sim.g_y[g])
		if dg > 140 * M:
			continue
		var sc := dg / M
		for o in sim.n_units:
			if sim.u_state[o] != U_READY or o == u:
				continue
			if sim.u_side[o] != side:
				if sim.u_wall[o] == 0:
					continue
				var dd := BattleAI._d(sim.u_cx[o] - p.x, sim.u_cy[o] - p.y)
				if sim.is_tower(o):
					if dd < 60 * M and sim.u_ammo[o] > 0:
						sc += 60 * kn[AP.S_LADDER_DEF_W]
				elif dd < 40 * M:
					sc += sim.u_alive[o] * kn[AP.S_LADDER_DEF_W]
			elif sim.u_wall[o] == sg + 1 or ((sim.u_stair[o] == ST_LADDER_GO or sim.u_stair[o] == ST_LADDER) \
					and sim.u_sseg[o] == sg):
				sc += 200
		if best.z >= 0 and sc >= best_s:
			continue
		if not sim.ladder_ok(sim, u, sg, p.x, p.y):
			continue
		best = Vector3i(p.x, p.y, sg)
		best_s = sc
	return best


## A tower's engine (defenders): with S_TOWER_FOCUS it picks, in reach and
## safe to shoot, the ram, then batteries, then men at a gate's face, on a
## ladder or up on the wall (nearest first in each class); else it fires at
## will.
static func _tower(sim, u: int) -> void:
	BattleAI._set_mode(sim, u, A_TOWER)
	var kn := AP.of(sim, sim.u_side[u])
	if sim.u_fire[u] == 0:
		BattleAI._order(sim, u, {"type": ORDER_FIRE, "on": 1}, 21)
	if kn[AP.S_TOWER_FOCUS] == 0 or sim.u_ammo[u] <= 0:
		return
	var ty: int = sim.u_type[u]
	var mn := UT.stat(ty, "m_min")
	var rng := UT.stat(ty, "m_range")
	var best := -1
	var best_s := 0
	for o in sim.n_units:
		if sim.u_side[o] == sim.u_side[u] or sim.u_state[o] != U_READY or sim.u_alive[o] <= 0:
			continue
		var cls := 0
		if sim.is_ram(o):
			cls = 3
		elif sim.u_cls[o] == UT.CLS_ART:
			cls = 2
		elif sim.u_wall[o] > 0 or sim.u_stair[o] == ST_LADDER:
			cls = 1
		else:
			for k in sim.n_gates:
				if sim.g_state[k] == GATE_CLOSED and sim.g_cit[k] == 0 \
						and BattleAI._d(sim.u_cx[o] - sim.g_ox[k], sim.u_cy[o] - sim.g_oy[k]) < 25 * M:
					cls = 1
					break
		if cls == 0:
			continue
		var sc := cls * 100000 - BattleAI._d(sim.u_cx[o] - sim.u_cx[u], sim.u_cy[o] - sim.u_cy[u]) / M
		if best >= 0 and sc <= best_s:
			continue
		if not sim._art_in_range(u, o, mn, rng) or not sim.art_safe(u, o):
			continue
		best = o
		best_s = sc
	if best >= 0:
		if sim.u_order[u] != O_ATTACK or sim.u_target[u] != best:
			BattleAI._attack(sim, u, best, 0)
	elif sim.u_order[u] == O_ATTACK:
		BattleAI._order(sim, u, {"type": 3}, 22)  # halt: fire at will


## Defenders, army level: each attacking unit climbing or up on the wall
## without a defender sent against it gets the nearest reserve foot unit
## (infantry that may man the walls), sent up onto its stretch.
static func _esc_reply(sim, side: int) -> void:
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] != U_READY:
			continue
		if sim.u_stair[o] != ST_LADDER and sim.u_wall[o] == 0:
			continue
		var taken := false
		for d in sim.n_units:
			if sim.u_side[d] == side and sim.u_state[d] == U_READY and sim.u_ai[d] == A_ESC and sim.u_ai_y[d] == o:
				taken = true
				break
		if taken:
			continue
		var best := -1
		var bd := 0
		for d in sim.n_units:
			if sim.u_side[d] != side or sim.u_state[d] != U_READY or sim.u_ai[d] != A_RESERVE:
				continue
			if sim.u_cls[d] != UT.CLS_INF or not sim.can_man_walls(sim, d) or sim.u_wall[d] > 0 or _engaged(sim, d):
				continue
			var dd := BattleAI._d(sim.u_cx[d] - sim.u_cx[o], sim.u_cy[d] - sim.u_cy[o])
			if best < 0 or dd < bd:
				best = d
				bd = dd
		if best < 0:
			return
		BattleAI._set_mode(sim, best, A_ESC)
		sim.u_ai_y[best] = o
		_esc_send(sim, best, o)
		BattleAI._count(sim, side, AP.C_SIEGE)


## Send defender u up onto the stretch attacking unit o climbs or holds, at
## the point nearest o's men.
static func _esc_send(sim, u: int, o: int) -> void:
	var sg: int = sim.u_wall[o] - 1
	if sg < 0:
		return
	var p: Vector2i = sim.seg_pt(sim, sg, sim.seg_t(sim, sg, sim.u_cx[o], sim.u_cy[o]))
	BattleAI._order(sim, u, {"type": 1, "x": p.x, "y": p.y, "facing": sim.ws_dir[sg],
		"width": BattleAI._width(sim, u), "run": 1}, 2)


## A defender sent against ladder men: up and fighting while they are on the
## wall (following them to another stretch); once they are gone (dead, down
## into the town, back down the ladders) it comes down and holds the foot of
## the stair as a reserve.
static func _esc_unit(sim, u: int) -> void:
	var o: int = sim.u_ai_y[u]
	var on: bool = o >= 0 and o < sim.n_units and sim.u_state[o] == U_READY \
		and (sim.u_wall[o] > 0 or sim.u_stair[o] == ST_LADDER)
	if not on:
		var sg: int = sim.u_wall[u] - 1
		BattleAI._set_mode(sim, u, A_RESERVE)
		if sg >= 0 and sim.u_stair[u] == 0:
			var p: Vector2i = sim.wall_inside(sg, sim.u_cx[u], sim.u_cy[u])
			sim.u_ai_x[u] = p.x
			sim.u_ai_y[u] = p.y
		else:
			sim.u_ai_x[u] = sim.u_ax[u]
			sim.u_ai_y[u] = sim.u_ay[u]
		return
	if sim.u_stair[u] != 0 or sim.u_order[u] == O_MOVE:
		return  # on its way up
	if sim.u_wall[u] != sim.u_wall[o]:
		_esc_send(sim, u, o)
