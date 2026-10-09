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
##             and go back to it when there are none (until the layout).
##   layout    (S_MOUTH, docs/AI.md 16) once the attacked gate is read from
##             the field (_read_gate: batteries' and the ram's targets,
##             ladders, attacking foot massing before it; Easy: only once it
##             is hit), the reserve's foot and that gate's guard stack up in
##             its inner mouth (A_MOUTH: the front across the gateway's
##             inner end facing out, the rest behind it; they fight
##             attackers who come out of the gateway), the riders and the
##             stack's tail hold the plaza (A_PLAZA: they attack attackers
##             reaching it), the guards of quiet gates join the stack (a
##             rider or a small guard stays as the token; a second attack
##             gets a unit back), wall missile units shift over the gate,
##             and a tired front is relieved by the unit behind it.
##   gates     an open gate with attackers within 100 m is closed (with
##             S_SHUT_EMPTY: any open gate with nobody of ours in its mouth,
##             a sally's once it is out; reopened for ours coming back).
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

# BattleSim's siege values (u_stair while going up ladders; siege
# equipment kinds and states, its orders).
const ST_LADDER := 4
const ST_LADDER_GO := 5
const EQ_LADDERS := 1
const EQ_RAM := 2
const Q_GROUND := 0
const Q_CARRIED := 1
const Q_PLANTED := 2
const Q_WRECKED := 3
const ORDER_PICKUP := 14
const ORDER_DROP := 15

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
const A_MOUTH := 34     # defender in the stack at the attacked gate's inner mouth (u_ai_x = gate, u_ai_y = place, 0 the front)
const A_PLAZA := 35     # defender holding the plaza (the plaza reserve)



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
			if sim.ai_sides[side] != 0 and sim.u_amok[u] != 0 and (k + tick) % unit_period[side] == 0:
				BattleAI.amok_think(sim, u)  # (docs/AI.md 19)
			continue
		if (k + tick) % unit_period[side] != 0:
			continue
		if sim.ai_phase[side] == P_WITHDRAW or sim.u_order[u] == O_WITHDRAW:
			continue
		if sim.u_hand[u] >= 0:
			continue  # a war dog pack (the settlement AI never releases one: docs/AI.md 21)
		var kn := kn0 if side == 0 else kn1
		if BattleAI.is_wagon(sim, u):
			BattleAI.wagon_think(sim, u, kn)  # (docs/AI.md 18)
			continue
		if sim.u_cls[u] == UT.CLS_MISSILE and sim.n_eq > 0 and BattleAI.resupply(sim, u, kn):
			continue
		if side == sim.city_def:
			_defender(sim, u)
		else:
			_attacker(sim, u)
		if sim.spec_kind(u) >= 0 and sim.u_gtarget[u] < 0:
			BattleAI.ammo_pick(sim, u, kn)  # (docs/AI.md 18)


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
		if kn[AP.S_MOUTH] != 0 and sim.ai_cit[side] == 0:
			_layout(sim, side, kn)  # (in the citadel: the town is lost)
		if kn[AP.SK_MEM] != 0:
			_sk_defend(sim, side, kn)
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
	if sim.n_eq > 0:
		_assign_equip(sim, side, phase, kn)


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
## S_SHUT_EMPTY: also any open gate with no unit of ours in its mouth, a
## sally's gate once the party is out (and reopened for units of ours back
## at it, no sally out and no attacker close).
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
	var shut_empty: bool = kn[AP.S_SHUT_EMPTY] != 0
	for g in sim.n_gates:
		if sim.g_cit[g] != 0:
			continue
		var sally: bool = kn[AP.SK_SALLY_R] > 0 and BattleAI._sd(sim, side, AP.SD_SALLY) == g + 1
		if sim.g_state[g] == GATE_CLOSED:
			if shut_empty and not sally and _ours_at_gate(sim, side, g) \
					and _attackers_near(sim, side, sim.g_ox[g], sim.g_oy[g], 20 * M) == 0:
				sim.queue_order({"tick": sim.tick, "type": ORDER_GATE, "unit": any, "gate": g, "on": 0,
					"player": BattleAI.AI_PLAYER_BASE + side, "seq": 8000 + g})
			continue
		if sim.g_state[g] != GATE_OPEN:
			continue
		if sally:
			if shut_empty and not _in_mouth(sim, side, g, true):
				_shut(sim, side, any, g)  # behind the sally
			continue  # our sally is out through it
		if shut_empty and not _in_mouth(sim, side, g, false):
			_shut(sim, side, any, g)  # nobody of ours in its mouth
			continue
		for o in sim.n_units:
			if sim.u_side[o] == side or sim.u_state[o] != U_READY:
				continue
			if BattleAI._d(sim.u_cx[o] - sim.g_x[g], sim.u_cy[o] - sim.g_y[g]) < close_r:
				if BattleAI._mistake(sim, side, AP.M_GATE_OPEN, kn):
					break  # left open this time
				_shut(sim, side, any, g)
				break


static func _shut(sim, side: int, any: int, g: int) -> void:
	sim.queue_order({"tick": sim.tick, "type": ORDER_GATE, "unit": any, "gate": g, "on": 1,
		"player": BattleAI.AI_PLAYER_BASE + side, "seq": 8000 + g})


## A ready unit of ours (the sally's only, if `sally`) in gate g's mouth:
## its middle within 16 m of the gate's faces, or (the sally's) still in
## the town.
static func _in_mouth(sim, side: int, g: int, sally: bool) -> bool:
	var r: int = sim.wall_t / 2 + 16 * M
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY or sim.u_wall[u] != 0:
			continue
		if sally:
			if BattleAI._mem(sim, u, AP.MU_X) != 30:
				continue
			if (sim.veg_bits(sim.u_cx[u], sim.u_cy[u]) & MapGen.V_URBAN) != 0:
				return true
		if BattleAI._d(sim.u_cx[u] - sim.g_x[g], sim.u_cy[u] - sim.g_y[g]) < r:
			return true
	return false


## A ready unit of ours outside the town in gate g's mouth (as _in_mouth:
## back from a sally, wanting in).
static func _ours_at_gate(sim, side: int, g: int) -> bool:
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY or sim.u_wall[u] != 0:
			continue
		if (sim.veg_bits(sim.u_cx[u], sim.u_cy[u]) & MapGen.V_URBAN) != 0:
			continue
		if BattleAI._d(sim.u_cx[u] - sim.g_x[g], sim.u_cy[u] - sim.g_y[g]) < sim.wall_t / 2 + 16 * M:
			return true
	return false


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
	if mode == A_WALLU and sim.u_ai_x[u] > 0:
		# Shifting to stretch u_ai_x - 1 (_wall_shift).
		if sim.u_wall[u] == sim.u_ai_x[u]:
			sim.u_ai_x[u] = 0  # there
		elif sim.u_wall[u] == 0 and (sim.u_stair[u] != 0 or sim.u_order[u] == O_MOVE):
			return  # on its way along the streets to the other stretch
		elif sim.u_order[u] != O_MOVE and sim.u_stair[u] == 0:
			sim.u_ai_x[u] = 0  # stopped short: it stays where it is
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
	if mode == A_MOUTH:
		_mouth_unit(sim, u)
		return
	if mode == A_PLAZA:
		_plaza_unit(sim, u)
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
	var kn := AP.of(sim, sim.u_side[u])
	var t := _nearest_attacker(sim, u, sim.u_cx[u], sim.u_cy[u], kn[AP.S_OFFWALL_R], true)
	if t < 0:
		return
	if _mouth_held(sim, sim.u_side[u], g) and _inward(sim, g, sim.u_cx[t], sim.u_cy[t]) \
			< sim.wall_t / 2 + kn[AP.S_MOUTH_IN] + 8 * M:
		return  # the stack holds the gate's mouth: stay up and shoot
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


# ------------------------------------------------ defenders: the layout ---
# docs/AI.md 16 (part 2c). Once the attacked gate is read from the field
# (the defending side's ai_gate), the foot reserve stacks up in its inner
# mouth (A_MOUTH, u_ai_x the gate, u_ai_y the place in the stack: 0 the
# front across the gateway's inner end, facing out, the rest one behind the
# other inward), the riders and one foot unit hold the plaza (A_PLAZA), the
# guards of the quiet gates join the stack (a rider, or a small guard, left
# as each one's token), a second attack at another gate gets a unit back,
# and the front is relieved by the next unit when it tires.

## The layout, army level (every ARMY_THINK).
static func _layout(sim, side: int, kn: PackedInt32Array) -> void:
	var prev: int = sim.ai_gate[side]
	# Which gates are under attack (_threat), once per think.
	var rr: int = maxi(kn[AP.S_GUARD_JOIN], 120 * M)
	var thr := _threats(sim, side, rr)
	var ag := _read_gate(sim, side, kn, thr)
	if ag < 0:
		return
	if prev < 0:
		_layout_start(sim, side, ag)
	elif prev != ag:
		# The attack moved to another gate: the stack follows it.
		for u in sim.n_units:
			if sim.u_side[u] == side and sim.u_ai[u] == A_MOUTH:
				sim.u_ai_x[u] = ag
	if kn[AP.S_GUARD_JOIN] > 0:
		_pull_guards(sim, side, ag, kn, thr if kn[AP.S_GUARD_JOIN] == rr else _threats(sim, side, kn[AP.S_GUARD_JOIN]))
	if kn[AP.S_WALL_SHIFT] != 0:
		_wall_shift(sim, side, ag)
	_absorb(sim, side, ag)
	_compact(sim, side)
	if kn[AP.S_ROT_PCT] > 0:
		_relieve(sim, side, kn)


## The attacked gate (the defending side's ai_gate, -1 none yet): a gate
## hit in the last 5 s, or open or broken with attackers within 100 m of
## it, at once; else (S_READ_R > 0) the gate the attackers' army points at
## (_field_gate) once it has for S_READ_TICKS. A gate still under attack
## stays the attacked one (a second attack elsewhere: _pull_guards).
static func _read_gate(sim, side: int, kn: PackedInt32Array, thr: PackedByteArray) -> int:
	var ag: int = sim.ai_gate[side]
	var sure := -1
	for g in sim.n_gates:
		if sim.g_cit[g] != 0 or g == ag:
			continue
		if (sim.g_state[g] == GATE_CLOSED and sim.tick - sim.g_hit_t[g] < 50) or (sim.g_state[g] != GATE_CLOSED \
				and _attackers_near(sim, side, sim.g_x[g], sim.g_y[g], 100 * M) > 0):
			sure = g
			break
	var cand := sure
	if cand < 0 and kn[AP.S_READ_R] > 0:
		cand = _field_gate(sim, side, kn)
	var k := side * 2
	if cand < 0 or cand == ag:
		sim.ai_lay[k] = -1
		return ag
	if ag >= 0 and thr[ag] != 0:
		sim.ai_lay[k] = -1
		return ag
	if sim.ai_lay[k] != cand:
		sim.ai_lay[k] = cand
		sim.ai_lay[k + 1] = sim.tick
	if sure < 0 and sim.tick - sim.ai_lay[k + 1] < kn[AP.S_READ_TICKS]:
		return ag
	sim.ai_gate[side] = cand
	sim.ai_lay[k] = -1
	BattleAI._count(sim, side, AP.C_SIEGE)
	return cand


## The outer gate the attackers' army points at, -1 none: each ready
## attacking unit's strength counts for the outer gate nearest it with its
## outside within S_READ_R (a battery or foot ordered at a gate: for that
## gate, twice; a unit carrying the ram or ladders: the gate nearest where
## it goes, twice), each planted ladder set a quarter of the army for the
## gate nearest it; the best gate once it has S_READ_PCT % of the army.
static func _field_gate(sim, side: int, kn: PackedInt32Array) -> int:
	var sc := PackedInt32Array()
	sc.resize(sim.n_gates)
	sc.fill(0)
	var r: int = kn[AP.S_READ_R]
	var total := 0
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] != U_READY:
			continue
		var w: int = sim.u_alive[o] * UT.stat(sim.u_type[o], "cost")
		total += w
		var g: int = sim.u_gtarget[o]
		if g >= 0 and sim.g_cit[g] == 0:
			w *= 2
		elif sim.n_eq > 0 and sim.u_carry[o] >= 0 and sim.u_order[o] == O_MOVE:
			g = _outer_gate_near(sim, sim.u_dx[o], sim.u_dy[o], r)
			w *= 2
		else:
			g = _outer_gate_near(sim, sim.u_cx[o], sim.u_cy[o], r)
		if g >= 0:
			sc[g] += w
	for q in sim.n_eq:
		if sim.q_side[q] != side and sim.q_state[q] == Q_PLANTED:
			var g2 := _outer_gate_near(sim, sim.q_x[q], sim.q_y[q], r)
			if g2 >= 0:
				sc[g2] += total / 4
	var best := -1
	for g in sim.n_gates:
		if sc[g] > 0 and (best < 0 or sc[g] > sc[best]):
			best = g
	if best < 0 or sc[best] * 100 < total * kn[AP.S_READ_PCT]:
		return -1
	return best


## The outer gate whose outside point is nearest (x, y) and within r; -1.
static func _outer_gate_near(sim, x: int, y: int, r: int) -> int:
	var best := -1
	var bd := r
	for g in sim.n_gates:
		if sim.g_cit[g] != 0:
			continue
		var d := BattleAI._d(sim.g_ox[g] - x, sim.g_oy[g] - y)
		if d < bd:
			best = g
			bd = d
	return best


## Per outer gate, under attack (1): hit in the last 30 s, open or broken
## with attackers within 100 m, or attacking foot within r of its outside
## and nearer it than any other outer gate.
static func _threats(sim, side: int, r: int) -> PackedByteArray:
	var t := PackedByteArray()
	t.resize(sim.n_gates)
	t.fill(0)
	for g in sim.n_gates:
		if sim.g_cit[g] != 0:
			continue
		if sim.tick - sim.g_hit_t[g] < 300 or (sim.g_state[g] != GATE_CLOSED \
				and _attackers_near(sim, side, sim.g_x[g], sim.g_y[g], 100 * M) > 0):
			t[g] = 1
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] != U_READY:
			continue
		var c: int = sim.u_cls[o]
		if c == UT.CLS_INF or c == UT.CLS_PIKE:
			var g2 := _outer_gate_near(sim, sim.u_cx[o], sim.u_cy[o], r)
			if g2 >= 0:
				t[g2] = 1
	return t


## The attack is read (gate ag): the reserve's foot and the gate's guard
## form the stack, nearest the gate first (spears 10 m, light foot 40 m
## further back in the reckoning: pikes and heavy foot to the front); the
## riders go to the plaza, and with none the stack's last unit of three or
## more (_compact).
static func _layout_start(sim, side: int, ag: int) -> void:
	var front := _mouth_front(sim, ag, AP.of(sim, side), 0)
	var us := PackedInt32Array()
	var ks := PackedInt32Array()
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY or sim.u_wall[u] != 0 or sim.u_stair[u] != 0:
			continue
		var m: int = sim.u_ai[u]
		if m != A_RESERVE and not (m == A_GATE and sim.u_ai_y[u] == ag):
			continue
		var c: int = sim.u_cls[u]
		if c == UT.CLS_CAV:
			BattleAI._set_mode(sim, u, A_PLAZA)
			continue
		if c != UT.CLS_INF and c != UT.CLS_PIKE:
			continue
		var ty: int = sim.u_type[u]
		var key: int = BattleAI._d(sim.u_ax[u] - front.x, sim.u_ay[u] - front.y) / M + maxi(100 - sim.u_alive[u], 0)
		if ty == UT.SPEAR:
			key += 10
		elif ty == UT.LIGHT:
			key += 40
		elif ty != UT.HEAVY and ty != UT.PIKE:
			key += 20
		# (Insertion by key, then index: a fixed order.)
		var at := us.size()
		while at > 0 and ks[at - 1] > key:
			at -= 1
		us.insert(at, u)
		ks.insert(at, key)
	for i in us.size():
		BattleAI._set_mode(sim, us[i], A_MOUTH)
		sim.u_ai_x[us[i]] = ag
		sim.u_ai_y[us[i]] = i
	BattleAI._count(sim, side, AP.C_SIEGE)


## The guards of quiet gates (no threat within S_GUARD_JOIN) join the
## stack's tail; each such gate keeps a token (A_GATE, u_ai_x 1): a rider
## of ours not fighting, else its guard if it has at most S_TOKEN_MEN men.
## A threatened gate other than ag with no guard but a token gets the
## stack's tail unit back (third place or later, not fighting).
static func _pull_guards(sim, side: int, ag: int, kn: PackedInt32Array, thr: PackedByteArray) -> void:
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY or sim.u_ai[u] != A_GATE or sim.u_ai_x[u] != 0:
			continue
		var g: int = sim.u_ai_y[u]
		if g == ag or sim.g_cit[g] != 0 or thr[g] != 0:
			continue
		var tok := -1
		for o in sim.n_units:
			if sim.u_side[o] == side and sim.u_state[o] == U_READY and sim.u_cls[o] == UT.CLS_CAV \
					and sim.u_wall[o] == 0 and (sim.u_ai[o] == A_PLAZA or sim.u_ai[o] == A_RESERVE) and not _engaged(sim, o):
				tok = o
				break
		if tok < 0 and sim.u_alive[u] <= kn[AP.S_TOKEN_MEN]:
			sim.u_ai_x[u] = 1  # it stays, as the token
			continue
		if tok >= 0:
			BattleAI._set_mode(sim, tok, A_GATE)
			sim.u_ai_y[tok] = g
			sim.u_ai_x[tok] = 1
		BattleAI._set_mode(sim, u, A_MOUTH)
		sim.u_ai_x[u] = ag
		sim.u_ai_y[u] = 98  # the tail (_compact)
		BattleAI._count(sim, side, AP.C_SIEGE)
	for g in sim.n_gates:
		if g == ag or sim.g_cit[g] != 0 or sim.g_state[g] == GATE_BROKEN or thr[g] == 0:
			continue
		var held := false
		var tail := -1
		for u in sim.n_units:
			if sim.u_side[u] != side or sim.u_state[u] != U_READY:
				continue
			if sim.u_ai[u] == A_GATE and sim.u_ai_y[u] == g and sim.u_ai_x[u] == 0:
				held = true
				break
			if sim.u_ai[u] == A_MOUTH and sim.u_ai_y[u] >= 2 and not _engaged(sim, u) \
					and (tail < 0 or sim.u_ai_y[u] > sim.u_ai_y[tail]):
				tail = u
		if held or tail < 0:
			continue
		BattleAI._set_mode(sim, tail, A_GATE)
		sim.u_ai_y[tail] = g
		BattleAI._count(sim, side, AP.C_SIEGE)


## Foot of ours left in reserve (back from a wall reply, down from a wall)
## join the stack's tail, riders the plaza.
static func _absorb(sim, side: int, ag: int) -> void:
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY or sim.u_ai[u] != A_RESERVE \
				or sim.u_wall[u] != 0 or sim.u_stair[u] != 0:
			continue
		var c: int = sim.u_cls[u]
		if c == UT.CLS_CAV:
			BattleAI._set_mode(sim, u, A_PLAZA)
		elif c == UT.CLS_INF or c == UT.CLS_PIKE:
			BattleAI._set_mode(sim, u, A_MOUTH)
			sim.u_ai_x[u] = ag
			sim.u_ai_y[u] = 98


## Number the stack 0, 1, ... in its order (units not ready: 99, so one
## that rallies joins at the tail); a front being relieved (u_ai_y -1 - k)
## goes back once its relief stands at front post k or fights; with nobody
## holding the plaza, the tail of a stack of three or more goes there.
static func _compact(sim, side: int) -> void:
	var us := PackedInt32Array()
	var ks := PackedInt32Array()
	var plz := 0
	var relieved := -1
	for u in sim.n_units:
		if sim.u_side[u] != side:
			continue
		if sim.u_ai[u] == A_PLAZA and sim.u_state[u] == U_READY:
			plz += 1
		if sim.u_ai[u] != A_MOUTH:
			continue
		if sim.u_state[u] != U_READY:
			sim.u_ai_y[u] = 99
			continue
		var key: int = sim.u_ai_y[u]
		if key < 0:
			relieved = u
			continue
		var at := us.size()
		while at > 0 and ks[at - 1] > key:
			at -= 1
		us.insert(at, u)
		ks.insert(at, key)
	for i in us.size():
		sim.u_ai_y[us[i]] = i
	if relieved >= 0:
		var k: int = -1 - sim.u_ai_y[relieved]
		var nf: int = us[k] if k < us.size() else -1
		var done: bool = nf < 0 or sim.u_fighting[nf] > 0
		if not done:
			var fp := _mouth_post(sim, nf, sim.u_ai_x[nf], AP.of(sim, side))
			done = BattleAI._d(sim.u_ax[nf] - fp.x, sim.u_ay[nf] - fp.y) < 4 * M
		if done:
			_relieved_back(sim, side, relieved)
			return
	if plz == 0 and us.size() >= 3 and not _engaged(sim, us[us.size() - 1]):
		BattleAI._set_mode(sim, us[us.size() - 1], A_PLAZA)


## A relieved front goes back: to the plaza, a foot unit holding it
## fresher than it taking the stack's tail; else to the stack's tail.
static func _relieved_back(sim, side: int, f: int) -> void:
	var rf := _morale_pct(sim, f)
	var p := -1
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and sim.u_ai[u] == A_PLAZA \
				and sim.u_cls[u] != UT.CLS_CAV and not _engaged(sim, u) and _morale_pct(sim, u) > rf:
			p = u
			break
	var ag: int = sim.u_ai_x[f]
	if p >= 0:
		BattleAI._set_mode(sim, p, A_MOUTH)
		sim.u_ai_x[p] = ag
		sim.u_ai_y[p] = 98
		BattleAI._set_mode(sim, f, A_PLAZA)
	else:
		sim.u_ai_y[f] = 98
	_compact(sim, side)


## Relieve a front (S_ROT_PCT): one fighting with its morale below that %
## of its type's while the first unit behind the fronts is above it by 15
## points: that unit becomes front k and walks up through it (friends pass
## at half speed: the gateway is never left open); the tired one (u_ai_y
## -1 - k) holds until then and goes back (_compact, _relieved_back).
static func _relieve(sim, side: int, kn: PackedInt32Array) -> void:
	var nfr: int = kn[AP.S_MOUTH_FRONTS]
	var fr := PackedInt32Array()
	fr.resize(nfr)
	fr.fill(-1)
	var r := -1
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and sim.u_ai[u] == A_MOUTH:
			var y: int = sim.u_ai_y[u]
			if y < 0:
				return  # a relief under way
			if y < nfr:
				fr[y] = u
			elif y == nfr:
				r = u
	if r < 0 or _morale_pct(sim, r) < kn[AP.S_ROT_PCT] + 15:
		return
	for k in nfr:
		var f: int = fr[k]
		if f < 0 or _morale_pct(sim, f) >= kn[AP.S_ROT_PCT]:
			continue
		if (sim.u_fighting[f] == 0) != (kn[AP.S_ROT_LULL] != 0):
			continue  # (S_ROT_LULL: only between waves, else only while it fights)
		sim.u_ai_y[f] = -1 - k
		sim.u_ai_y[r] = k
		BattleAI._count(sim, side, AP.C_ROTATION)
		_compact(sim, side)
		return


static func _morale_pct(sim, u: int) -> int:
	return sim.u_morale[u] * 100 / maxi(UT.stat(sim.u_type[u], "morale"), 1)


## Front post k (of S_MOUTH_FRONTS side by side, S_MOUTH_W wide in all) at
## gate g: S_MOUTH_IN inside the wall's inner face, S_MOUTH_BACK further in
## while the gate stands shut (out of the shots at it); z: facing out.
static func _mouth_front(sim, g: int, kn: PackedInt32Array, k: int) -> Vector3i:
	var dir: int = sim.g_dir[g]
	var back: int = sim.wall_t / 2 + kn[AP.S_MOUTH_IN]
	if sim.g_state[g] == GATE_CLOSED:
		back += kn[AP.S_MOUTH_BACK]
	var nfr: int = kn[AP.S_MOUTH_FRONTS]
	var lat: int = (2 * k - (nfr - 1)) * kn[AP.S_MOUTH_W] / (2 * nfr)
	var c := FM.cos_a(dir)
	var s := FM.sin_a(dir)
	return Vector3i(sim.g_x[g] - (c * back + s * lat) / FM.TRIG_ONE, sim.g_y[g] - (s * back - c * lat) / FM.TRIG_ONE, dir)


## Files unit u stands in at its place in the stack (a front: its share of
## S_MOUTH_W) and the depth of its formation then.
static func _stack_files(sim, u: int, kn: PackedInt32Array) -> int:
	var alive: int = maxi(sim.u_alive[u], 1)
	if sim.u_ai_y[u] < kn[AP.S_MOUTH_FRONTS]:
		var w: int = kn[AP.S_MOUTH_W] / kn[AP.S_MOUTH_FRONTS]
		return clampi(w / maxi(UT.stat(sim.u_type[u], "file_sp"), 1), 1, alive)
	return clampi(sim.u_files[u], 1, alive)


static func _stack_depth(sim, u: int, kn: PackedInt32Array) -> int:
	var files := _stack_files(sim, u, kn)
	var ranks: int = (sim.u_alive[u] + files - 1) / files
	return ranks * UT.stat(sim.u_type[u], "rank_sp")


## Unit u's post in the stack at gate g: a front's (u_ai_y below
## S_MOUTH_FRONTS, or -1 - k while relieved: front k's), else behind the
## fronts (the deepest) and every unit before it, 3 m apart, on the gate's
## axis; where that is not open ground of the town, the same distance along
## the way from the gate's inside to the plaza, else the plaza.
static func _mouth_post(sim, u: int, g: int, kn: PackedInt32Array) -> Vector3i:
	var slot: int = sim.u_ai_y[u]
	var nfr: int = kn[AP.S_MOUTH_FRONTS]
	if slot < 0:
		return _mouth_front(sim, g, kn, -1 - slot)
	if slot < nfr:
		return _mouth_front(sim, g, kn, slot)
	var side: int = sim.u_side[u]
	var fd := 0
	var back := 0
	for o in sim.n_units:
		if sim.u_side[o] != side or sim.u_state[o] != U_READY or sim.u_ai[o] != A_MOUTH:
			continue
		var y: int = sim.u_ai_y[o]
		if y >= 0 and y < nfr:
			fd = maxi(fd, _stack_depth(sim, o, kn))
		elif y >= nfr and y < slot:
			back += _stack_depth(sim, o, kn) + 3 * M
	var front := _mouth_front(sim, g, kn, 0)
	var dir: int = sim.g_dir[g]
	var c := FM.cos_a(dir)
	var s := FM.sin_a(dir)
	# (The fronts' middle: front 0 is offset to one side when there are two.)
	var lat0: int = (1 - nfr) * kn[AP.S_MOUTH_W] / (2 * nfr)
	var mx: int = front.x + s * lat0 / FM.TRIG_ONE
	var my: int = front.y - c * lat0 / FM.TRIG_ONE
	back += fd + 3 * M
	var x: int = mx - c * back / FM.TRIG_ONE
	var y2: int = my - s * back / FM.TRIG_ONE
	var piece: int = sim.reach_at(sim.g_ix[g], sim.g_iy[g])
	if _open_at(sim, x, y2, piece):
		return Vector3i(x, y2, dir)
	var px: int = sim.plaza[0]
	var py: int = sim.plaza[1]
	var dx: int = px - sim.g_ix[g]
	var dy: int = py - sim.g_iy[g]
	var l: int = maxi(BattleAI._d(dx, dy), 1)
	var along := mini(back, l)
	x = sim.g_ix[g] + dx * (along / M) / (l / M + 1)
	y2 = sim.g_iy[g] + dy * (along / M) / (l / M + 1)
	if _open_at(sim, x, y2, piece):
		return Vector3i(x, y2, dir)
	return Vector3i(px, py, dir)


## Metres (sim units) point (x, y) lies inside gate g's middle along its
## axis (negative: outside).
static func _inward(sim, g: int, x: int, y: int) -> int:
	return -((x - sim.g_x[g]) * FM.cos_a(sim.g_dir[g]) + (y - sim.g_y[g]) * FM.sin_a(sim.g_dir[g])) / FM.TRIG_ONE


## The stack holds gate g's mouth: g is the side's attacked gate and a
## front of it stands.
static func _mouth_held(sim, side: int, g: int) -> bool:
	if sim.ai_gate[side] != g:
		return false
	var nfr: int = AP.of(sim, side)[AP.S_MOUTH_FRONTS]
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and sim.u_ai[u] == A_MOUTH and sim.u_ai_y[u] < nfr:
			return true
	return false


static func _open_at(sim, x: int, y: int, piece: int) -> bool:
	return sim.obs_kind(x, y) == MapGen.C_OPEN and (sim.nav_at(x, y) & MapGen.NAV_GROUND) != 0 \
		and sim.reach_at(x, y) == piece


## A unit of the stack (A_MOUTH). A front holds its post across the
## gateway's inner end (its men fight whoever comes through); the others
## attack attackers past the fronts' line within S_MOUTH_REACT of their
## post, else hold it, facing out.
static func _mouth_unit(sim, u: int) -> void:
	var side: int = sim.u_side[u]
	var kn := AP.of(sim, side)
	var g: int = sim.u_ai_x[u]
	var post := _mouth_post(sim, u, g, kn)
	var react: int = kn[AP.S_MOUTH_REACT]
	var front: bool = sim.u_ai_y[u] < kn[AP.S_MOUTH_FRONTS]
	if _engaged(sim, u):
		var et: int = sim.u_target[u]
		if BattleAI._d(sim.u_cx[et] - post.x, sim.u_cy[et] - post.y) < 2 * react:
			return
	if not front:
		# Attackers out of the gateway (inside the wall's inner face) within
		# S_MOUTH_REACT of the front's post: the nearest to this unit.
		var fp := _mouth_front(sim, g, kn, 0)
		var t := -1
		var bd := 0
		var line: int = sim.wall_t / 2 + M
		for o in sim.n_units:
			if sim.u_side[o] == side or sim.u_state[o] != U_READY or sim.u_wall[o] != 0:
				continue
			if BattleAI._d(sim.u_cx[o] - fp.x, sim.u_cy[o] - fp.y) >= react \
					or _inward(sim, g, sim.u_cx[o], sim.u_cy[o]) < line:
				continue
			var d := BattleAI._d(sim.u_cx[o] - sim.u_cx[u], sim.u_cy[o] - sim.u_cy[u])
			if t < 0 or d < bd:
				t = o
				bd = d
		if t >= 0:
			if sim.u_order[u] != O_ATTACK or sim.u_target[u] != t:
				BattleAI._attack(sim, u, t, 0)
			return
	var width: int = _stack_files(sim, u, kn) * UT.stat(sim.u_type[u], "file_sp")
	var slack := 3 if front else 6
	if sim.u_order[u] == O_MOVE:
		if BattleAI._d(sim.u_dx[u] - post.x, sim.u_dy[u] - post.y) < 2 * M:
			return
	elif BattleAI._d(sim.u_ax[u] - post.x, sim.u_ay[u] - post.y) < slack * M \
			and absi(FM.angle_diff(sim.u_face[u], post.z)) < 64:
		return
	var far := BattleAI._d(sim.u_ax[u] - post.x, sim.u_ay[u] - post.y) > 40 * M
	BattleAI._order(sim, u, {"type": 1, "x": post.x, "y": post.y, "facing": post.z, "width": width,
		"run": 1 if far and sim.u_cls[u] != UT.CLS_PIKE else 0}, 2)


## The plaza reserve (A_PLAZA): attacks attackers within the plaza's
## radius + S_PLAZA_REACT of its middle (the capture never starts while it
## stands), else holds the plaza (several spread 12 m apart).
static func _plaza_unit(sim, u: int) -> void:
	if _engaged(sim, u):
		return
	var side: int = sim.u_side[u]
	var kn := AP.of(sim, side)
	var px: int = sim.plaza[0]
	var py: int = sim.plaza[1]
	var t := _nearest_attacker(sim, u, px, py, sim.plaza[3] + kn[AP.S_PLAZA_REACT], false)
	if t >= 0 and sim.u_wall[t] == 0:
		if sim.u_order[u] != O_ATTACK or sim.u_target[u] != t:
			BattleAI._attack(sim, u, t, 1 if BattleAI._dist2(sim, u, t) > 25 * 25 * M * M else 0)
		return
	var k := 0
	for o in u:
		if sim.u_side[o] == side and sim.u_state[o] == U_READY and sim.u_ai[o] == A_PLAZA:
			k += 1
	var ag: int = sim.ai_gate[side]
	var face: int = sim.u_dface[u]
	if ag >= 0:
		face = FM.atan2_a(sim.g_iy[ag] - py, sim.g_ix[ag] - px)
	var lat: int = [0, 12, -12][k % 3] * M
	_go_run(sim, u, px + lat, py + (k / 3) * 12 * M, face, 6,
		1 if BattleAI._d(sim.u_ax[u] - px, sim.u_ay[u] - py) > 40 * M and sim.u_cls[u] != UT.CLS_PIKE else 0)


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
	if sim.n_eq > 0 and sim.u_ai[u] == A_RAM and _att_ram(sim, u, phase):
		return
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
		if sim.n_eq > 0 and (sim.u_ai[o] == A_LADDER or sim.u_ai[o] == A_RAM):
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
	if sim.n_eq > 0 and sim.u_ai[u] == A_LADDER:
		_escalade(sim, u, g, kn)
		return
	if sim.n_eq > 0 and sim.u_carry[u] >= 0:
		BattleAI._order(sim, u, {"type": ORDER_DROP}, 24)  # (nothing to do with it)
		return
	# Hack at the gate: with no battery from the start, else after a while
	# of bombardment.
	var hackers: int = kn[AP.S_HACKERS]
	if not _art_ready(sim, side):
		hackers = 99 if sim.tick - sim.ai_t[side] > 2 * kn[AP.S_HACK_AFTER] else kn[AP.S_HACKERS]
	elif sim.tick - sim.ai_t[side] < kn[AP.S_HACK_AFTER]:
		hackers = 0
	if sim.n_eq > 0 and _ram_avail(sim, side) >= 0:
		hackers = 0  # the ram breaks the gate
	if not sim.gate_hackable(sim, g):
		hackers = 0  # iron-bound: nobody hacks at it
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
	if sim.n_eq > 0 and sim.u_carry[u] >= 0:
		BattleAI._order(sim, u, {"type": ORDER_DROP}, 24)  # put it down to fight
		return
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
		# it if swords can break it (walls 0-1) and no ram is coming (the
		# army gives the ram to a unit: _assign_equip); the rest gather before
		# it, out of bow shot when nobody can hurt the gate (they wait for
		# the ram, or for the defenders to come out).
		var c: int = sim.u_cls[u]
		var hack: bool = sim.gate_hackable(sim, cg) and (sim.n_eq == 0 or _ram_avail(sim, sim.u_side[u]) < 0)
		if hack and (c == UT.CLS_INF or c == UT.CLS_PIKE) and _near_rank(sim, u, sim.g_x[cg], sim.g_y[cg]) < kn[AP.S_CIT_HACKERS]:
			if sim.u_gtarget[u] != cg:
				BattleAI._order(sim, u, {"type": ORDER_ATTACK, "target": -1, "gate": cg, "run": 0}, 0)
			return
		var rkc := _rank(sim, u, func(o): return sim.u_cls[o] == UT.CLS_INF or sim.u_cls[o] == UT.CLS_PIKE)
		var gath: int = kn[AP.S_CIT_GATHER] if hack else maxi(kn[AP.S_CIT_GATHER], kn[AP.S_CIT_WAIT])
		var cspot := _gate_point(sim, cg, gath, _spread(rkc.x % 5, mini(rkc.y, 5), kn[AP.S_CIT_SPREAD]))
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
	if kn[AP.AK_FIRE_GATE] != 0 and BattleAI._d(spot.x - sim.u_ax[u], spot.y - sim.u_ay[u]) <= 10 * M:
		_fire_at_gate(sim, u, g)


## Attacking missile unit u with a fire kind, standing at its post: it sets
## the attacked gate g alight (docs/AI.md 18, AK_FIRE_GATE) while the gate is
## shut and in reach of its fire missiles and it has some left. True if so.
static func _fire_at_gate(sim, u: int, g: int) -> bool:
	var sk: int = sim.spec_kind(u)
	if sk < 0 or UT.ammo_stat(sk, "fire") <= 0 or g < 0 or sim.g_state[g] != GATE_CLOSED:
		return false
	if sim.u_order[u] != O_NONE or sim.u_fighting[u] > 0 or sim.special_left(u) <= 0:
		return false
	var gf: Vector2i = sim.gate_face(g)
	var rng: int = UT.stat(sim.u_type[u], "m_range") * UT.ammo_stat(sk, "range") / 100
	if BattleAI._d(gf.x - sim.u_cx[u], gf.y - sim.u_cy[u]) > rng:
		return false
	if sim.u_akind[u] != 1:
		BattleAI._order(sim, u, {"type": BattleAI.ORDER_AMMO, "on": 1}, 27)
	if sim.u_gtarget[u] != g:
		BattleAI._order(sim, u, {"type": ORDER_ATTACK, "target": -1, "gate": g, "run": 0}, 0)
	return true


static func _att_cav(sim, u: int, phase: int) -> void:
	var side: int = sim.u_side[u]
	var kn := AP.of(sim, side)
	if phase == SP_PURSUE:
		var r := _router(sim, u, kn[AP.S_CAV_ROUTER_R])
		if r >= 0:
			if sim.u_order[u] != O_ATTACK or sim.u_target[u] != r:
				BattleAI._attack(sim, u, r, 1)
			return
	# Beasts (a body: elephants) batter the gates of low walls and stay out
	# of the streets (docs/AI.md 19).
	var beast: bool = UT.stat(sim.u_type[u], "body_r") > 0
	if beast and _beast_gate(sim, u, kn):
		return
	if phase == SP_ASSAULT and (sim.ai_prog[2] != 0 or _no_foot(sim, side)) and not (beast and kn[AP.EL_STORM] == 0):
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


## A beast unit of the attackers goes at the attacked gate while it stands
## shut and its row may batter it (EL_GATE; walls up to its gate_walls).
static func _beast_gate(sim, u: int, kn: PackedInt32Array) -> bool:
	var g: int = sim.ai_gate[sim.u_side[u]]
	if kn[AP.EL_GATE] == 0 or g < 0 or sim.g_state[g] != GATE_CLOSED or not sim.gate_hackable(sim, g) \
			or UT.stat(sim.u_type[u], "gate_walls") < sim.city_walls:
		return false
	BattleAI._set_mode(sim, u, A_HACK)
	if not _engaged(sim, u) and sim.u_gtarget[u] != g:
		BattleAI._order(sim, u, {"type": ORDER_ATTACK, "target": -1, "gate": g, "run": 0}, 0)
	return true


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
		if kn[AP.S_WALL_SHIFT] != 0 and kn[AP.S_MOUTH] == 0:
			_wall_shift(sim, side, ag)
		if kn[AP.SK_MIS_DOWN_PCT] > 0 and kn[AP.S_MOUTH] == 0:
			_sk_mis_down(sim, side, ag, kn)  # (with the layout they stay up over the stack)
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
## two units a stretch). In transit: u_ai_x = stretch + 1 (_defender).
static func _wall_shift(sim, side: int, ag: int) -> void:
	var gx: int = sim.g_x[ag]
	var gy: int = sim.g_y[ag]
	# Units on (or making for) each stretch, counted once.
	var nseg: int = sim.ws_x0.size()
	var occ := PackedInt32Array()
	occ.resize(nseg)
	occ.fill(0)
	for o in sim.n_units:
		if sim.u_side[o] != side or sim.u_state[o] != U_READY:
			continue
		var on: int = sim.u_wall[o] - 1
		var to: int = sim.u_ai_x[o] - 1 if sim.u_ai[o] == A_WALLU else -1
		if on >= 0 and on < nseg:
			occ[on] += 1
		if to >= 0 and to < nseg and to != on:
			occ[to] += 1
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
		var d0: int = sim._seg_off(sg0, gx, gy)
		for sg in nseg:
			if (sim.ws_fl[sg] & MapGen.SEG_CIT) != 0 or sg == sg0 or occ[sg] >= 2:
				continue
			var d: int = sim._seg_off(sg, gx, gy)
			if d >= d0:
				continue
			if best < 0 or d < bd:
				best = sg
				bd = d
		if best < 0:
			continue
		var p: Vector2i = sim.seg_pt(sim, best, sim.seg_t(sim, best, gx, gy))
		sim.u_ai_x[u] = best + 1
		occ[best] += 1
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

## A ram of the side that can still work a gate (on the ground or carried
## by one of ours), -1 none.
static func _ram_avail(sim, side: int) -> int:
	for q in sim.n_eq:
		if sim.q_kind[q] != EQ_RAM or sim.q_side[q] != side:
			continue
		if sim.q_state[q] == Q_GROUND or sim.q_state[q] == Q_CARRIED:
			return q
	return -1


## The gate a ram should go at now, -1 none: in the approach the gate the
## army goes for (while shut); in the assault the citadel's gate while it
## is shut against us.
static func _ram_target(sim, side: int, phase: int) -> int:
	if phase == SP_APPROACH:
		var g: int = sim.ai_gate[side]
		return g if g >= 0 and sim.g_state[g] == GATE_CLOSED else -1
	if phase == SP_ASSAULT:
		var cg: int = sim.cit_gate
		return cg if cg >= 0 and sim.g_state[cg] == GATE_CLOSED else -1
	return -1


## Attacking foot unit u may be given a piece of equipment: ready, on the
## ground (not on a wall or a ladder move), not already given one, not
## falling back, not fighting, on the piece's own ground.
static func _equip_free(sim, u: int, side: int, q: int) -> bool:
	if sim.u_side[u] != side or sim.u_state[u] != U_READY or sim.u_wall[u] > 0 or sim.u_stair[u] != 0:
		return false
	var m: int = sim.u_ai[u]
	if m == A_LADDER or m == A_RAM or m == BattleAI.A_RETIRE or sim.u_carry[u] >= 0 or BattleAI.is_wagon(sim, u):
		return false
	if sim.u_fighting[u] > 0:
		return false
	var ra: int = sim.reach_at(sim.u_ax[u], sim.u_ay[u])
	return ra >= 0 and ra == sim.reach_at(sim.q_x[q], sim.q_y[q])


## The unit of ours holding piece q: carrying it, or given it (u_ai_x =
## q + 1 in mode A_RAM / A_LADDER); -1 none.
static func _holder(sim, side: int, q: int) -> int:
	if sim.q_state[q] == Q_CARRIED:
		var c: int = sim.q_unit[q]
		if c >= 0 and sim.u_side[c] == side:
			return c
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and (sim.u_ai[u] == A_RAM or sim.u_ai[u] == A_LADDER) \
				and sim.u_ai_x[u] == q + 1:
			return u
	return -1


## Attackers, army level (docs/AI.md 15): who carries what. The ram goes to
## the foot unit least wanted in the streets (pikes, then light, spears,
## heavy; nearest first) while there is a shut gate for it; up to
## S_LADDER_UNITS ladder sets to the heaviest infantry (heavy, light,
## spears) while ladders are wanted; each planted set gets up to
## S_LADDER_FOLLOW more infantry climbing it. A unit keeps its piece
## (A_RAM / A_LADDER, u_ai_x = piece + 1) until it has no more use for it.
static func _assign_equip(sim, side: int, phase: int, kn: PackedInt32Array) -> void:
	var g: int = sim.ai_gate[side]
	# The ram.
	var rq := _ram_avail(sim, side)
	if rq >= 0 and _ram_target(sim, side, phase) >= 0:
		var h := _holder(sim, side, rq)
		if h >= 0:
			if sim.u_ai[h] != A_RAM:
				BattleAI._set_mode(sim, h, A_RAM)
				sim.u_ai_x[h] = rq + 1
		else:
			var best := -1
			var bk := 0
			for u in sim.n_units:
				var c: int = sim.u_cls[u]
				if (c != UT.CLS_INF and c != UT.CLS_PIKE) or not _equip_free(sim, u, side, rq):
					continue
				var key := _foot_key(sim, u)
				var rk := (3 - key) if c != UT.CLS_PIKE else -1
				var k: int = (rk + 1) * 100000 + BattleAI._d(sim.u_cx[u] - sim.q_x[rq], sim.u_cy[u] - sim.q_y[rq]) / M
				if best < 0 or k < bk:
					best = u
					bk = k
			if best >= 0:
				BattleAI._set_mode(sim, best, A_RAM)
				sim.u_ai_x[best] = rq + 1
				BattleAI._count(sim, side, AP.C_SIEGE)
	if phase != SP_APPROACH or g < 0:
		return
	if sim.city_walls < kn[AP.S_LADDER_WALLS] and _art_ready(sim, side):
		return  # the engines will have the gate down before the ladders are up
	# Ladder parties: the sets on the ground or carried, heaviest infantry
	# first (sets already planted count: S_LADDER_UNITS sets in all).
	var parties := 0
	for q0 in sim.n_eq:
		if sim.q_kind[q0] == EQ_LADDERS and sim.q_side[q0] == side and sim.q_state[q0] == Q_PLANTED:
			parties += 1
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and sim.u_ai[u] == A_LADDER and sim.u_ai_x[u] > 0:
			var q0: int = sim.u_ai_x[u] - 1
			if sim.q_state[q0] != Q_PLANTED:
				parties += 1
	for q in sim.n_eq:
		if sim.q_kind[q] != EQ_LADDERS or sim.q_side[q] != side:
			continue
		if sim.q_state[q] == Q_PLANTED:
			# Followers: more infantry up the planted set.
			var on := 0
			for u in sim.n_units:
				if sim.u_side[u] == side and sim.u_state[u] == U_READY and sim.u_ai[u] == A_LADDER \
						and sim.u_ai_x[u] == q + 1:
					on += 1
			if on >= 1 + kn[AP.S_LADDER_FOLLOW]:
				continue
			var fb := -1
			var fd := 0
			for u in sim.n_units:
				if sim.u_cls[u] != UT.CLS_INF or sim.u_ai[u] != A_WAIT or not _equip_free(sim, u, side, q):
					continue
				var d := BattleAI._d(sim.u_cx[u] - sim.q_x[q], sim.u_cy[u] - sim.q_y[q])
				if fb < 0 or d < fd:
					fb = u
					fd = d
			if fb >= 0:
				BattleAI._set_mode(sim, fb, A_LADDER)
				sim.u_ai_x[fb] = q + 1
				BattleAI._count(sim, side, AP.C_SIEGE)
			continue
		if sim.q_state[q] != Q_GROUND and sim.q_state[q] != Q_CARRIED:
			continue
		if _holder(sim, side, q) >= 0 or parties >= kn[AP.S_LADDER_UNITS]:
			continue
		var best := -1
		var bk := 0
		for u in sim.n_units:
			if sim.u_cls[u] != UT.CLS_INF or not _equip_free(sim, u, side, q):
				continue
			var k: int = _foot_key(sim, u) * 1000 + u
			if best < 0 or k < bk:
				best = u
				bk = k
		if best < 0:
			break
		BattleAI._set_mode(sim, best, A_LADDER)
		sim.u_ai_x[best] = q + 1
		parties += 1
		BattleAI._count(sim, side, AP.C_SIEGE)


## A unit gives up its piece of equipment (puts it down if it carries it)
## and goes back to the foot's usual work.
static func _release(sim, u: int) -> void:
	if sim.u_carry[u] >= 0:
		BattleAI._order(sim, u, {"type": ORDER_DROP}, 24)
	BattleAI._set_mode(sim, u, A_WAIT)


## The ram's unit (A_RAM, u_ai_x = the ram + 1): to the ram and picks it up;
## carrying it, at the gate it goes for (_ram_target; Skilled first waits,
## out of the towers' reach, for the towers by the gate to be silenced, at
## most S_RAM_WAIT into the approach) and batters it. The sim puts the ram
## down once the gate breaks; with no shut gate left for it the unit puts it
## down and fights as the others. Returns true while it handled the unit.
static func _att_ram(sim, u: int, phase: int) -> bool:
	var side: int = sim.u_side[u]
	var kn := AP.of(sim, side)
	var q: int = sim.u_ai_x[u] - 1
	var g := _ram_target(sim, side, phase)
	if q < 0 or q >= sim.n_eq or sim.q_kind[q] != EQ_RAM or g < 0 \
			or (sim.q_state[q] != Q_GROUND and not (sim.q_state[q] == Q_CARRIED and sim.q_unit[q] == u)):
		_release(sim, u)
		return false
	if sim.q_state[q] == Q_GROUND:
		if sim.u_carry[u] >= 0:
			BattleAI._order(sim, u, {"type": ORDER_DROP}, 24)
			return true
		if _engaged(sim, u):
			return true
		if sim.u_pick[u] != q:
			var far := BattleAI._d(sim.u_cx[u] - sim.q_x[q], sim.u_cy[u] - sim.q_y[q]) > 40 * M
			BattleAI._order(sim, u, {"type": ORDER_PICKUP, "equip": q, "run": 1 if far else 0}, 25)
		return true
	# Carrying it.
	if phase == SP_APPROACH and kn[AP.S_RAM_WAIT] > 0 and sim.tick - sim.ai_t[side] < kn[AP.S_RAM_WAIT] \
			and _tower_near_gate(sim, -1, g, 40 * M, false) >= 0:
		var spot := _gate_point(sim, g, kn[AP.S_STAGE_OUT], 0)
		_go_home(sim, u, spot.x, spot.y, FM.atan2_a(sim.g_y[g] - spot.y, sim.g_x[g] - spot.x), 10)
		return true
	if sim.u_gtarget[u] != g:
		BattleAI._order(sim, u, {"type": ORDER_ATTACK, "target": -1, "gate": g, "run": 0}, 0)
		BattleAI._count(sim, side, AP.C_SIEGE)
	return true


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
## have two places to hold at once.
static func _ladder_time(sim, side: int, g: int, kn: PackedInt32Array) -> bool:
	if sim.tick - sim.ai_t[side] >= kn[AP.S_LADDER_AFTER]:
		return true
	return sim.g_hp[g] * 100 < sim.g_hp0[g] * 85


static func _foot_key(sim, u: int) -> int:
	var b := UT.base_of(sim.u_type[u])
	if b == UT.HEAVY:
		return 0
	if b == UT.LIGHT:
		return 1
	if b == UT.SPEAR:
		return 2
	return 3


## A ladder unit (A_LADDER, u_ai_x = its set + 1): on the ground outside, to
## its set and picks it up; carrying it, waits with the foot until ladder
## time, then plants it on the weakest stretch near gate g (_ladder_spot)
## and climbs; a follower climbs the set where it is planted. Once over,
## down into the town to the inside of the nearest closed outer gate (it
## unbars it); inside with no closed gate left, it storms.
static func _escalade(sim, u: int, g: int, kn: PackedInt32Array) -> void:
	var st: int = sim.u_stair[u]
	if st == ST_LADDER or st == ST_LADDER_GO:
		return
	if _engaged(sim, u):
		return
	var inside: bool = sim.u_wall[u] > 0 or st == 1
	if not inside and sim.u_lq[u] >= 0:
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
	var q: int = sim.u_ai_x[u] - 1
	if q < 0 or q >= sim.n_eq or sim.q_kind[q] != EQ_LADDERS or sim.q_state[q] == Q_WRECKED \
			or (sim.q_state[q] == Q_CARRIED and sim.q_unit[q] != u):
		_release(sim, u)
		return
	if sim.q_state[q] == Q_GROUND:
		if sim.u_carry[u] >= 0:
			BattleAI._order(sim, u, {"type": ORDER_DROP}, 24)
			return
		if sim.u_pick[u] != q:
			var far := BattleAI._d(sim.u_cx[u] - sim.q_x[q], sim.u_cy[u] - sim.q_y[q]) > 40 * M
			BattleAI._order(sim, u, {"type": ORDER_PICKUP, "equip": q, "run": 1 if far else 0}, 25)
		return
	var p := Vector3i(sim.q_wx[q], sim.q_wy[q], sim.q_seg[q])
	if sim.q_state[q] == Q_CARRIED:
		if not _ladder_time(sim, sim.u_side[u], g, kn):
			# Ladders ready: wait with the foot.
			var rk := _rank(sim, u, func(o): return sim.u_cls[o] == UT.CLS_INF or sim.u_cls[o] == UT.CLS_PIKE)
			var spot := _gate_point(sim, g, kn[AP.S_STAGE_OUT], _spread(rk.x, rk.y, kn[AP.S_FOOT_SPREAD]))
			_go_home(sim, u, spot.x, spot.y, FM.atan2_a(sim.g_y[g] - spot.y, sim.g_x[g] - spot.x), 10)
			return
		p = _ladder_spot(sim, u, g, kn)
		if p.z < 0:
			return
	if sim.u_order[u] == O_MOVE and BattleAI._d(sim.u_dx[u] - p.x, sim.u_dy[u] - p.y) < 4 * M:
		return
	var far2 := BattleAI._d(sim.u_cx[u] - p.x, sim.u_cy[u] - p.y) > 60 * M
	BattleAI._order(sim, u, {"type": 1, "x": p.x, "y": p.y, "facing": sim.ws_dir[p.z],
		"width": BattleAI._width(sim, u), "run": 1 if far2 and sim.u_carry[u] < 0 else 0}, 2)
	BattleAI._count(sim, sim.u_side[u], AP.C_SIEGE)


## Where ladder unit u plants its set: the middle of a land-wall stretch
## within 140 m of gate g with a foot it can reach, scored by metres from
## the gate and from the unit plus S_LADDER_DEF_W per defending man on the walls within 40 m
## of it and 60 per working tower within 60 m, a stretch another of ours is
## on, bound for or has ladders planted on 200 m more. (x, y, stretch);
## stretch -1 none.
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
		# (Carrying ladders is slow: the walk there counts as much again.)
		var sc := dg / M + BattleAI._d(p.x - sim.u_cx[u], p.y - sim.u_cy[u]) / M
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
		for q in sim.n_eq:
			if sim.q_state[q] == Q_PLANTED and sim.q_seg[q] == sg:
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
		if sim.carrying(sim, o) == EQ_RAM:
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
			if sim.u_side[d] != side or sim.u_state[d] != U_READY:
				continue
			var dm: int = sim.u_ai[d]
			if dm != A_RESERVE and dm != A_PLAZA and not (dm == A_MOUTH and sim.u_ai_y[d] >= 2):
				continue  # (the stack's front and the unit behind it stay)
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
