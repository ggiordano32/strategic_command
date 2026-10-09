extends RefCounted
## Deterministic battle AI (milestone 2).
##
## Runs inside BattleSim.step() and acts only by queueing the same orders a
## player can give, so it stays lockstep-safe. Its memory lives in sim arrays
## (ai_phase / ai_t per side; u_ai, u_ai_t, u_ai_x, u_ai_y per unit) that are
## covered by state_hash().
##
## Army level (each side once a second):
##   DEPLOY   form a line: pikes centre, other infantry outward, cavalry on the
##            wings, missile troops 15 m in front (second line if wide).
##   ADVANCE  march the line to a halt line. Unless clearly outshot, the line
##            halts in bow range and skirmishes (up to SKIRMISH_TICKS, or
##            until most arrows are spent); otherwise it closes. Switches to ENGAGE when the lines are close.
##   ENGAGE   units pick their own targets (below).
##   WITHDRAW the battle is clearly lost: the whole army withdraws.
## Unit level (each unit once a second, staggered):
##   infantry  attack the nearest enemy; spears go for nearby cavalry; avoid
##             formed pike fronts: pin with one unit, send others to a flank.
##   cavalry   wait on the wing; charge unprotected missile troops or enemy
##             cavalry threatening the flank at any time; once the lines meet,
##             ride round to the flank or rear of engaged enemies and charge;
##             pull out after a few seconds of melee and charge again; never
##             charge a braced spear or pike front.
##   missiles  skirmish mode on; fire at will only while an unengaged enemy is
##             in range (no shooting into our own melee); move behind the line
##             once it engages; with no ammunition, keep out of the way.
##   artillery deploy where the field of fire is clear (bolts at the end of
##             the line, stones behind the centre); stay put while anything is
##             in range, pick dense, valuable, standing targets and never one
##             a shot would carry into friends; move up only when nothing is in
##             range; one spear (or light) unit guards the batteries.
##             An empty or low battery with nothing near it refills from its
##             baggage (also in a lull, below three quarters), and stops
##             when threatened or once three quarters full with a target in
##             range.
##   cavalry   also rides down enemy batteries left without a guard.
##   shelled   an army shelled by stronger enemy artillery closes instead of
##             standing to skirmish; idle units under fire get out of the arc.
##   all       badly mauled units fall back behind the line.
## Terrain (hilly maps only; on a flat map none of this changes a decision):
##   deploy    the army shifts its deployment up to 30 m onto higher ground;
##   advance   while skirmishing the line halts on a crest short of the halt
##             line if one is clearly higher;
##   hold      an army whose line stands 4 m or more above the enemy's holds
##             its ground (up to HOLD_TICKS, while not outshot or outgunned)
##             and its foot only attack enemies that come close, until a
##             third of them are fighting;
##   detour    infantry whose last 35 m to its target climb more than 15%
##             goes round to a clearly gentler flank approach if one is
##             close (A_DETOUR), once per target;
##   cavalry   prefers targets it does not have to charge uphill;
##   missiles  archers, javelins and batteries take the highest spot near
##             their slot; bolt throwers want a line of fire past crests,
##             and a battery whose targets are all behind a crest moves.
## Woods (maps with trees only):
##   deploy    cavalry, pikes and batteries whose slot is in woods take the
##             nearest clear spot within 30 m;
##   cavalry   target scores lose 30 per tree density step along the way
##             (8 m samples) and 600 per step where the target stands;
##   missiles  archers and javelins threatened by cavalry within 70 m step
##             into woods (medium or dense) within 40 m if any.
##   (Flat shots through dense woods are refused by the sim's line of fire.)
## Profiles: every threshold, interval, distance and score above is a knob
## of the side's skill / personality profile (sim/ai_profile.gd, read as
## `kn[AP.X]` with kn = AP.of(sim, side)); the names in capitals above are
## those knobs. Behaviour never branches on the level itself.
## Easy (docs/AI.md 9): knobs switch behaviours off (CLEAR_SPOT, MIS_SKIRM,
## CAV_STAGE_FRONT, FLANK_PCT, terrain sense by out-of-reach thresholds,
## RETIRE_ALIVE_PCT 0) and the deliberate mistakes (AP.M_*) are rolled with
## the sim's RNG at their decision points (_mistake / _mistake_once): a
## spear or cavalry unit ignoring enemy riders this think, cavalry riding at
## the nearest foot instead of its chosen target, a line unit left idle when
## the lines meet (A_IDLE), foot chasing a router (marked in u_ai_y), a
## charge into a braced or pike front, archers not pulled back, the cavalry
## thrown at the enemy line before the lines meet, a gate left open, an
## early withdrawal. Each is an order a player could give; a side cannot
## repeat one within MK_COOLDOWN (BattleSim.ai_mist, hashed with a
## non-default profile). A level with a mistake's chance at 0 never rolls
## it (no RNG draw), so Average plays exactly as before.
## Skilled (docs/AI.md 11): behaviours switched on by the SK_* knobs (0 for
## Easy and Average, so they never run there), with their memory in the
## hashed sim array ai_mem (MU_* per unit, SD_* per side; empty unless a
## profile has SK_MEM): a foot reserve behind the centre (A_RESV) that
## relieves the most tired unit of the line (rotation: the tired unit
## pulls out once the relief has fought SK_ROT_DELAY, with no free enemy
## riders near, recovers and becomes the reserve) or hammers an enemy unit
## near breaking; a cavalry reserve that only counter-charges riders on our
## flank or finishes wavering units until the enemy's first line unit or
## rider breaks; matchup assignment for the foot (_sk_assign: a greedy pass
## over unit pairs each army think); cavalry that stays in a melee it is
## winning, pursues in pairs, prefers riders caught in a melee and units
## near breaking; missile focus fire; spears that read where riders are
## heading; archers back behind the line before contact; the battery guard
## released while no enemy riders are free near the battery; own waverers
## pulled away from a routing neighbour; deployment that puts the spears
## at the end facing the enemy's riders; withdrawal in good order. All of
## it orders a player could give, read from what a player sees.

const FM := preload("res://sim/fixed_math.gd")
const UT := preload("res://sim/unit_types.gd")
const AP := preload("res://sim/ai_profile.gd")

const M := 1024
const AI_PLAYER_BASE := 100  # order "player" id so AI orders sort after humans

# Sim constants mirrored here (preloading battle_sim.gd would be circular).
const U_READY := 0
const U_ROUTING := 1
const U_DESTROYED := 2
const O_NONE := 0
const O_MOVE := 1
const O_ATTACK := 2
const O_WITHDRAW := 3
const ORDER_MOVE := 1
const ORDER_ATTACK := 2
const ORDER_HALT := 3
const ORDER_FIRE := 5
const ORDER_SKIRMISH := 6
const ORDER_WITHDRAW := 7
const ORDER_WITHDRAW_ALL := 8
const ORDER_REFILL := 10
const ORDER_PICKUP := 14
const ORDER_AMMO := 16
const ORDER_FORAGE := 17
const ORDER_DROP := 15
const EQ_WAGON := 3            # (BattleSim's siege equipment kinds and states)
const Q_GROUND := 0
const Q_CARRIED := 1
const Q_WRECKED := 3
const WAGON_TAKE_R := 60 * M   # a wagon crew without its wagon takes up one on the ground this near
const PICK_ENG := 1 << 16      # (BattleSim.PICK_ENG: u_pick of a unit going to take up engines)
const ENGINE_TAKE_R := 60 * M  # missile units out of ammunition take up their side's abandoned engines this near
const FRONT_ARC := 170
const LOF_EYE := 1536
const LOF_BODY := 1024
const LOF_STEP := 4 * 1024

# Army phases.
const P_DEPLOY := 0
const P_ADVANCE := 1
const P_ENGAGE := 2
const P_WITHDRAW := 3

# Unit modes.
const A_LINE := 0      # follows the army plan
const A_ATTACK := 1
const A_FLANK := 2     # moving to a flank staging point
const A_HOLD := 3      # cavalry waiting
const A_STAGE := 4     # cavalry riding to a staging point
const A_CHARGE := 5
const A_PULL := 6      # cavalry pulling out of a melee
const A_RETIRE := 7    # mauled unit falling back
# (stat_ai[8] counts army withdrawals)
const A_ART := 9       # artillery battery
const A_GUARD := 10    # infantry guarding the batteries
const A_DETOUR := 11   # infantry going round a steep slope to a gentler approach
const A_IDLE := 30     # line unit left idle by a mistake (M_IDLE) until IDLE_TICKS or attacked
const A_RESV := 31     # Skilled: foot held in reserve behind the centre (SK_RESERVE)
# (stat_ai[12] holds of high ground, [13] slots moved onto a rise,
# [14] deployments shifted to higher ground)


static func think(sim) -> void:
	var tick: int = sim.tick
	var kn0 := AP.of(sim, 0)
	var kn1 := AP.of(sim, 1)
	var unit_period := PackedInt32Array([kn0[AP.UNIT_THINK], kn1[AP.UNIT_THINK]])
	# Both armies think on the same tick, from the same state (their orders
	# are applied together after this), so neither side always reacts to
	# the other's last decision.
	for side in 2:
		if sim.ai_sides[side] != 0 and tick % (kn0 if side == 0 else kn1)[AP.ARMY_THINK] == 0:
			_army_think(sim, side)
	if sim.ai_sides[0] == 0 and sim.ai_sides[1] == 0:
		return
	# Units think in turn, staggered by their index *within their own side*,
	# so both armies react to their army's decisions on the same schedule.
	# (Staggering by global index made the army listed second react a few
	# ticks sooner after each decision, and it won ~60% of mirrored battles.)
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
		_unit_think(sim, u)


# ------------------------------------------------------------ army level ---

static func _army_think(sim, side: int) -> void:
	var phase: int = sim.ai_phase[side]
	if phase == P_WITHDRAW:
		if AP.of(sim, side)[AP.SK_WD_COVER] > 0:
			_wd_cover_end(sim, side)
		return
	var own := _strength(sim, side)
	var foe := _strength(sim, 1 - side)
	if foe <= 0:
		return
	var kn := AP.of(sim, side)
	# Clearly lost: little left that can fight against a strong enemy, or a
	# fifth of the army left and the enemy stronger.
	if sim.tick > kn[AP.WD_MIN_TICK] and (own * 100 < foe * kn[AP.WD_FOE_PCT] \
			or (own * 100 < _start_strength(sim, side) * kn[AP.WD_START_PCT] and own < foe)):
		if kn[AP.SK_WD_COVER] > 0:
			_wd_cover_start(sim, side)
			return
		sim.queue_order({"tick": sim.tick, "type": ORDER_WITHDRAW_ALL, "side": side,
			"player": AI_PLAYER_BASE + side, "seq": 9000})
		sim.ai_phase[side] = P_WITHDRAW
		sim.ai_t[side] = sim.tick
		sim.stat_ai[8] += 1
		return
	# Mistake: withdrawing while still in the fight (rolled once a battle,
	# the first time the army is clearly the weaker).
	if kn[AP.WD_EARLY_PCT] > 0 and sim.tick > kn[AP.WD_MIN_TICK] and own * 100 < foe * kn[AP.WD_EARLY_PCT] \
			and _mistake_once(sim, side, AP.M_EARLY_WD, kn):
		withdraw_all(sim, side, 9000)
		return
	var plan := _plan(sim, side)
	if plan.is_empty():
		return
	if phase == P_DEPLOY:
		var dcx: int = plan["cx"]
		var dcy: int = plan["cy"]
		if sim.ter_on != 0:
			var spot := _deploy_spot(sim, side, plan)
			if spot.x != dcx or spot.y != dcy:
				sim.stat_ai[14] += 1
			dcx = spot.x
			dcy = spot.y
		if sim.veg_on != 0 and kn[AP.SK_ANCHOR] > 0:
			var an := _sk_anchor(sim, side, plan, dcx, dcy, kn)
			dcx = an.x
			dcy = an.y
		_issue_line(sim, side, plan, dcx, dcy, true)
		sim.ai_phase[side] = P_ADVANCE
		sim.ai_t[side] = sim.tick
		return
	if phase == P_ENGAGE:
		if sim.ai_hold[side] >= 0 and not _keep_holding(sim, side):
			sim.ai_hold[side] = -2  # over for good
		if kn[AP.SK_MEM] != 0:
			_sk_army(sim, side, kn, plan)
		return
	if phase == P_ADVANCE:
		var gap: int = plan["gap"]
		var halt := 0
		# Halt in bow range and shoot unless clearly outshot.
		var mine := _missile_power(sim, side)
		var skirmishing: bool = mine > 0 and mine * 100 >= _missile_power(sim, 1 - side) * kn[AP.SKIRMISH_MISSILE_PCT] \
			and sim.tick - sim.ai_t[side] < kn[AP.SKIRMISH_TICKS] and _ammo_left(sim, side)
		# Shelled by artillery stronger than ours: standing still only feeds
		# it, so close the distance instead.
		if skirmishing and _shelled(sim, side) and _art_power(sim, 1 - side) > _art_power(sim, side):
			skirmishing = false
		if skirmishing:
			halt = kn[AP.SKIRMISH_HALT]
		var engage_d := kn[AP.ENGAGE_DIST]
		var engage := gap < engage_d or (halt == 0 and gap < engage_d + kn[AP.ENGAGE_RUSH])
		# Mistake: the cavalry, the army's reserve, is thrown at the enemy
		# line before the lines meet (once a battle, once the armies are
		# within twice the bow-range halt line).
		if not engage and gap < 2 * kn[AP.SKIRMISH_HALT] and _mistake_once(sim, side, AP.M_COMMIT_EARLY, kn):
			_commit_cavalry(sim, side)
		if engage:
			sim.ai_phase[side] = P_ENGAGE
			sim.ai_t[side] = sim.tick
			for u in sim.n_units:
				if sim.u_side[u] == side and sim.u_ai[u] == A_LINE and sim.u_cls[u] != UT.CLS_MISSILE:
					if _mistake(sim, side, AP.M_IDLE, kn):
						_set_mode(sim, u, A_IDLE)  # left standing while the line goes in
					else:
						sim.u_ai[u] = A_ATTACK
			if kn[AP.SK_MEM] != 0:
				_sk_army(sim, side, kn, plan)
			return
		# Halt line: `halt` short of the enemy front, never backwards.
		var fx: int = plan["fx"]
		var fy: int = plan["fy"]
		var adv := maxi(gap - maxi(halt, engage_d - kn[AP.HALT_SHORT]), 0)
		if sim.ter_on != 0:
			# High ground: hold it while the enemy comes up; otherwise, while
			# skirmishing, stop on a crest short of the halt line.
			if sim.ai_hold[side] >= 0:
				if _keep_holding(sim, side):
					adv = 0
				else:
					sim.ai_hold[side] = -2
			elif sim.ai_hold[side] == -1 and _start_hold(sim, side):
				sim.ai_hold[side] = sim.tick
				sim.stat_ai[12] += 1
				adv = 0
			if sim.ai_hold[side] < 0 and halt > 0 and adv > 0:
				adv = _crest_advance(sim, side, plan, adv, gap, halt)
		var cx: int = plan["cx"] + (fx * adv / FM.TRIG_ONE)
		var cy: int = plan["cy"] + (fy * adv / FM.TRIG_ONE)
		_issue_line(sim, side, plan, cx, cy, false)
		if kn[AP.SK_MEM] != 0:
			_sk_army(sim, side, kn, plan)


## The commit-early mistake: every waiting cavalry unit charges the
## nearest enemy foot unit head on, and sees the charge through.
static func _commit_cavalry(sim, side: int) -> void:
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY or sim.u_cls[u] != UT.CLS_CAV or sim.u_ai[u] != A_HOLD:
			continue
		var t := _nearest_foot(sim, u)
		if t < 0:
			continue
		_attack(sim, u, t, 1)
		_set_mode(sim, u, A_CHARGE)
		sim.u_ai_y[u] = 1  # no going round


## Nearest ready enemy line unit (infantry or pikes) to u, or -1.
static func _nearest_foot(sim, u: int) -> int:
	var best := -1
	var best_d := 0
	for o in sim.n_units:
		if sim.u_side[o] == sim.u_side[u] or sim.u_state[o] != U_READY:
			continue
		if sim.u_cls[o] != UT.CLS_INF and sim.u_cls[o] != UT.CLS_PIKE:
			continue
		var d := _dist2(sim, u, o)
		if best < 0 or d < best_d:
			best = o
			best_d = d
	return best


## Fighting strength of a side: ready, non-withdrawing soldiers times cost.
static func _strength(sim, side: int) -> int:
	var s := 0
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and sim.u_order[u] != O_WITHDRAW:
			var cost := UT.stat(sim.u_type[u], "cost")
			if sim.u_cls[u] == UT.CLS_ART and sim.u_ammo[u] <= 0 and sim.u_reserve[u] <= 0:
				cost = 2  # crews with nothing left to shoot
			s += sim.u_alive[u] * cost
	return s


static func _start_strength(sim, side: int) -> int:
	var s := 0
	for u in sim.n_units:
		if sim.u_side[u] == side:
			s += sim.u_count0[u] * UT.stat(sim.u_type[u], "cost")
	return s


static func _missile_power(sim, side: int) -> int:
	var s := 0
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and sim.u_ammo[u] > 0 \
				and sim.u_cls[u] == UT.CLS_MISSILE:
			s += sim.u_alive[u]
	return s


## Artillery strength of a side: working engines (bolt 1, stone 2).
static func _art_power(sim, side: int) -> int:
	var s := 0
	for e in sim.n_eng:
		var u: int = sim.e_unit[e]
		if sim.u_side[u] == side and sim.e_state[e] == 0 and sim.e_ammo[e] > 0 \
				and sim.u_state[u] == U_READY:
			s += UT.stat(sim.u_type[u], "m_kind")
	return s


## Some unit of the side was hit by artillery within SHELLED_TICKS.
static func _shelled(sim, side: int) -> bool:
	var within := AP.of(sim, side)[AP.SHELLED_TICKS]
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY \
				and sim.tick - sim.u_shelled_t[u] < within:
			return true
	return false


static func _ammo_left(sim, side: int) -> bool:
	var have := 0
	var full := 0
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and sim.u_cls[u] == UT.CLS_MISSILE:
			have += sim.u_ammo[u]
			full += sim.u_count0[u] * UT.stat(sim.u_type[u], "m_ammo")
	return full > 0 and have * 100 > full * AP.of(sim, side)[AP.SKIRMISH_AMMO_PCT]


## Army geometry: own centre, facing toward the enemy, gap between fronts.
## (Hot at army-think ticks: the sim arrays are read through typed locals,
## since every untyped sim.u_* lookup in the O(units^2) gap loop is slow.)
static func _plan(sim, side: int) -> Dictionary:
	var nu: int = sim.n_units
	var st: PackedInt32Array = sim.u_state
	var sd: PackedInt32Array = sim.u_side
	var cl: PackedInt32Array = sim.u_cls
	var al: PackedInt32Array = sim.u_alive
	var uax: PackedInt32Array = sim.u_ax
	var uay: PackedInt32Array = sim.u_ay
	var ucx: PackedInt32Array = sim.u_cx
	var ucy: PackedInt32Array = sim.u_cy
	var ox := 0
	var oy := 0
	var on := 0
	var ex := 0
	var ey := 0
	var en := 0
	for u in nu:
		if st[u] != U_READY:
			continue
		var w := al[u]
		if sd[u] == side:
			# The plan is anchored on the main line (missile screens and
			# cavalry out on the wings would pull it about).
			var c := cl[u]
			if c == UT.CLS_MISSILE or c == UT.CLS_CAV or c == UT.CLS_ART:
				continue
			ox += uax[u] * w
			oy += uay[u] * w
			on += w
		else:
			ex += ucx[u] * w
			ey += ucy[u] * w
			en += w
	if on == 0 or en == 0:
		return {}
	ox /= on
	oy /= on
	ex /= en
	ey /= en
	var dx := ex - ox
	var dy := ey - oy
	var d := maxi(FM.isqrt(dx * dx + dy * dy), 1)
	# Quantise the facing so small drifts do not cause new orders.
	var face := ((FM.atan2_a(dy, dx) + 8) >> 4 << 4) & FM.ANGLE_MASK
	var fx := FM.cos_a(face)
	var fy := FM.sin_a(face)
	# Gap: closest approach between the two armies' foot (cavalry raids and
	# batteries do not decide when the lines engage).
	var gap := d
	var mnx: PackedInt32Array = sim.u_minx
	var mny: PackedInt32Array = sim.u_miny
	var mxx: PackedInt32Array = sim.u_maxx
	var mxy: PackedInt32Array = sim.u_maxy
	for u in nu:
		if sd[u] != side or st[u] != U_READY:
			continue
		var cu := cl[u]
		if cu != UT.CLS_INF and cu != UT.CLS_PIKE:
			continue
		var ax0 := mnx[u]
		var ax1 := mxx[u]
		var ay0 := mny[u]
		var ay1 := mxy[u]
		for o in nu:
			if sd[o] == side or st[o] != U_READY or cl[o] == UT.CLS_CAV:
				continue
			var gx := maxi(maxi(mnx[o] - ax1, ax0 - mxx[o]), 0)
			var gy := maxi(maxi(mny[o] - ay1, ay0 - mxy[o]), 0)
			gap = mini(gap, maxi(gx, gy))
	return {"cx": ox, "cy": oy, "face": face, "fx": fx, "fy": fy, "gap": gap, "ex": ex, "ey": ey}


## Line infantry (infantry or pikes; not a wagon's crew).
static func _is_foot(sim, u: int) -> bool:
	return (sim.u_cls[u] == UT.CLS_INF or sim.u_cls[u] == UT.CLS_PIKE) and not is_wagon(sim, u)


## Unit u is an ammunition wagon's crew (kept out of the line: docs/AI.md 18).
static func is_wagon(sim, u: int) -> bool:
	return UT.stat(sim.u_otype[u], "wagon") >= 0


static func _bbox_gap(sim, a: int, b: int) -> int:
	var gx := maxi(maxi(sim.u_minx[b] - sim.u_maxx[a], sim.u_minx[a] - sim.u_maxx[b]), 0)
	var gy := maxi(maxi(sim.u_miny[b] - sim.u_maxy[a], sim.u_miny[a] - sim.u_maxy[b]), 0)
	return maxi(gx, gy)


## Line positions: pikes in the centre, other infantry outward, cavalry on
## the wings, missiles in front. Within a role, units keep their left-to-right
## order so the redeployment does not cross over.
static func _issue_line(sim, side: int, plan: Dictionary, cx: int, cy: int, deploy: bool) -> void:
	var kn := AP.of(sim, side)
	var line_gap := kn[AP.LINE_GAP]
	var face: int = plan["face"]
	var fx: int = plan["fx"]
	var fy: int = plan["fy"]
	var rx := -fy  # right = (-sin, cos)
	var ry := fx
	var pikes: Array = []
	var inf: Array = []
	var cav: Array = []
	var mis: Array = []
	var bolts: Array = []
	var stones: Array = []
	var resv: Array = []  # Skilled: reserve foot and cavalry behind the centre
	if deploy and kn[AP.SK_MEM] != 0:
		_sk_pick_reserves(sim, side, kn)
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY:
			continue
		if not deploy and sim.u_ai[u] != A_LINE and sim.u_ai[u] != A_HOLD and sim.u_ai[u] != A_ART \
				and sim.u_ai[u] != A_RESV:
			continue
		if is_wagon(sim, u):
			continue  # (the wagon keeps behind the army: wagon_think)
		var c: int = sim.u_cls[u]
		if kn[AP.SK_RESERVE] > 0 and _sk_reserve_slot(sim, u, deploy, kn):
			resv.append(u)
		elif c == UT.CLS_PIKE:
			pikes.append(u)
		elif c == UT.CLS_CAV:
			cav.append(u)
		elif c == UT.CLS_MISSILE:
			mis.append(u)
		elif c == UT.CLS_ART:
			if UT.stat(sim.u_type[u], "m_kind") == 1:
				bolts.append(u)
			else:
				stones.append(u)
		else:
			inf.append(u)
	# Infantry: solid types next to the pikes, lighter ones outward.
	inf.sort_custom(func(a: int, b: int) -> bool:
		var ka := _solidity(sim.u_type[a])
		var kb := _solidity(sim.u_type[b])
		return ka > kb or (ka == kb and a < b))
	var line1: Array = []
	var line2: Array = []
	var order: Array = pikes.duplicate()
	order.append_array(inf)
	for k in order.size():
		if k < kn[AP.MAX_LINE]:
			line1.append(order[k])
		else:
			line2.append(order[k])
	var slots := {}  # unit -> [lateral, back]
	var half1 := _place_centre_out(sim, line1, 0, slots, line_gap)
	_place_centre_out(sim, line2, kn[AP.LINE2_BACK], slots, line_gap)
	# Bolt throwers at the ends of the first line (a clear, flat field of
	# fire), then cavalry beyond them.
	var lw := half1 + line_gap
	var rw := half1 + line_gap
	for k in bolts.size():
		var u: int = bolts[k]
		var w := _width(sim, u)
		if k % 2 == 0:
			slots[u] = [-(lw + w / 2), 0]
			lw += w + line_gap
		else:
			slots[u] = [rw + w / 2, 0]
			rw += w + line_gap
	lw += kn[AP.WING_GAP] - line_gap
	rw += kn[AP.WING_GAP] - line_gap
	# Stone throwers behind the centre (they lob over the line).
	var stotal := 0
	for u in stones:
		stotal += _width(sim, u) + line_gap
	var sxx := -stotal / 2
	for u in stones:
		var w := _width(sim, u)
		slots[u] = [sxx + w / 2, kn[AP.ART_BACK]]
		sxx += w + line_gap
	for k in cav.size():
		var u: int = cav[k]
		var w := _width(sim, u)
		if k % 2 == 0:
			slots[u] = [-(lw + w / 2), 0]
			lw += w + line_gap
		else:
			slots[u] = [rw + w / 2, 0]
			rw += w + line_gap
	# Missiles spread in front of the centre.
	var total := 0
	for u in mis:
		total += _width(sim, u) + line_gap
	var x := -total / 2
	for u in mis:
		var w := _width(sim, u)
		slots[u] = [x + w / 2, -kn[AP.MISSILE_AHEAD]]
		x += w + line_gap
	# Reserves behind the centre, side by side.
	var rtotal := 0
	for u in resv:
		rtotal += _width(sim, u) + line_gap
	var rx0 := -rtotal / 2
	for u in resv:
		var w := _width(sim, u)
		slots[u] = [rx0 + w / 2, kn[AP.SK_RESERVE_BACK]]
		rx0 += w + line_gap
	if deploy and kn[AP.SK_MIRROR] != 0:
		_sk_mirror(sim, side, line1, slots, cx, cy, rx, ry)
	# Keep left-to-right order within each role.
	for group in [pikes, inf, cav, mis, bolts, stones, resv]:
		_reassign_by_lateral(sim, group, slots, cx, cy, rx, ry)
	var seq := 0
	var keys := slots.keys()
	keys.sort()  # index order, never Dictionary order
	for u in keys:
		var s: Array = slots[u]
		var lat: int = s[0]
		var back: int = s[1]
		var px := cx + ((rx * lat - fx * back) / FM.TRIG_ONE)
		var py := cy + ((ry * lat - fy * back) / FM.TRIG_ONE)
		px = clampi(px, 4 * M, sim.field_w - 4 * M)
		py = clampi(py, 4 * M, sim.field_h - 4 * M)
		var art: bool = sim.u_cls[u] == UT.CLS_ART
		if sim.veg_on != 0 and kn[AP.CLEAR_SPOT] != 0 and (art or sim.u_cls[u] == UT.CLS_CAV or sim.u_cls[u] == UT.CLS_PIKE):
			var cp := _clear_spot(sim, px, py, rx, ry, fx, fy)
			px = cp.x
			py = cp.y
		# A battery that has targets and friends close by stays put.
		var stay: bool = art and not deploy and (sim.u_refill[u] != 0 or sim.u_rprog[u] > 0 \
			or (_protected(sim, u, side) and _art_has_target(sim, u)))
		if sim.ter_on != 0 and (sim.u_cls[u] == UT.CLS_MISSILE or art) and not stay:
			var rp := _rise(sim, u, px, py, rx, ry, fx, fy, plan)
			if rp.x != px or rp.y != py:
				sim.stat_ai[13] += 1
			px = rp.x
			py = rp.y
		if art:
			# Batteries only pack up for a worthwhile move: at deployment,
			# and to keep up with the line as it advances.
			var far := kn[AP.ART_DEPLOY_MOVE] if deploy else kn[AP.ART_MOVE]
			if not stay and _d(px - sim.u_ax[u], py - sim.u_ay[u]) > far and sim.u_ammo[u] > 0:
				_move(sim, u, px, py, face, _width(sim, u), 0, seq)
		else:
			_move(sim, u, px, py, face, _width(sim, u), 0, seq)
		seq += 1
		if sim.u_cls[u] == UT.CLS_MISSILE and sim.u_skirm[u] == 0 and kn[AP.MIS_SKIRM] != 0:
			_order(sim, u, {"type": ORDER_SKIRMISH, "on": 1}, 20)
		if deploy:
			var mode := A_LINE
			if sim.u_cls[u] == UT.CLS_CAV:
				mode = A_HOLD
			elif sim.u_cls[u] == UT.CLS_ART:
				mode = A_ART
			elif resv.has(u):
				mode = A_RESV
			sim.u_ai[u] = mode
			sim.u_ai_t[u] = sim.tick
			sim.stat_ai[mode] += 1
	if deploy and not (bolts.is_empty() and stones.is_empty()):
		_pick_guard(sim, side, bolts[0] if not bolts.is_empty() else stones[0])


static func _solidity(ty: int) -> int:
	if ty == UT.HEAVY:
		return 3
	if ty == UT.SPEAR:
		return 2
	return 1


static func _width(sim, u: int) -> int:
	var files := mini(sim.u_files[u], sim.u_alive[u])
	return files * UT.stat(sim.u_type[u], "file_sp")


## Lay units out from the centre: first in the middle, then alternately
## right and left. Returns the half width used.
static func _place_centre_out(sim, units: Array, back: int, slots: Dictionary, line_gap: int) -> int:
	if units.is_empty():
		return 0
	var total := 0
	for u in units:
		total += _width(sim, u) + line_gap
	total -= line_gap
	# Order: centre-out sequence mapped to left-to-right positions.
	var n := units.size()
	var pos: Array = []
	pos.resize(n)
	var left := (n - 1) / 2
	var right := left + 1
	for k in n:
		if k % 2 == 0:
			pos[left] = units[k]
			left -= 1
		else:
			pos[right] = units[k]
			right += 1
	var x := -total / 2
	for u in pos:
		var w := _width(sim, u)
		slots[u] = [x + w / 2, back]
		x += w + line_gap
	return total / 2


static func _reassign_by_lateral(sim, group: Array, slots: Dictionary, cx: int, cy: int,
		rx: int, ry: int) -> void:
	if group.size() < 2:
		return
	var lat_of := func(u: int) -> int:
		return ((sim.u_ax[u] - cx) * rx + (sim.u_ay[u] - cy) * ry) / FM.TRIG_ONE
	# Group units by role and preserve their current left-to-right order.
	var by_unit := group.duplicate()
	by_unit.sort_custom(func(a: int, b: int) -> bool:
		var la: int = lat_of.call(a)
		var lb: int = lat_of.call(b)
		return la < lb or (la == lb and a < b))
	# Slots are only swapped between units of the same width class (same
	# type), so frontages stay where the layout put them.
	var by_slot := group.duplicate()
	by_slot.sort_custom(func(a: int, b: int) -> bool:
		var sa: int = slots[a][0]
		var sb: int = slots[b][0]
		return sa < sb or (sa == sb and a < b))
	var orig := {}
	for u in group:
		orig[u] = slots[u]
	for k in by_unit.size():
		var u: int = by_unit[k]
		var v: int = by_slot[k]
		if sim.u_type[u] == sim.u_type[v]:
			slots[u] = orig[v]


# ------------------------------------------------------------ unit level ---

static func _unit_think(sim, u: int) -> void:
	var side: int = sim.u_side[u]
	var phase: int = sim.ai_phase[side]
	var cls: int = sim.u_cls[u]
	var mode: int = sim.u_ai[u]
	var kn := AP.of(sim, side)
	if is_wagon(sim, u):
		wagon_think(sim, u, kn)
		return
	# Badly mauled: fall back behind the line once.
	if mode != A_RETIRE and sim.u_alive[u] * 100 < sim.u_count0[u] * kn[AP.RETIRE_ALIVE_PCT] \
			and sim.u_morale[u] < kn[AP.RETIRE_MORALE]:
		_retire(sim, u)
		return
	if mode == A_RETIRE:
		# Back in the fight once it has fallen back and had time to recover
		# (or rallied after a rout). Standing idle under artillery fire, it
		# steps out of the battery's arc.
		if sim.u_order[u] == O_NONE and sim.tick - sim.u_shelled_t[u] < kn[AP.SHELLED_TICKS]:
			_sidestep(sim, u, sim.u_shelled_by[u])
			return
		if sim.tick - sim.u_ai_t[u] < kn[AP.RETIRE_TICKS] or sim.u_order[u] != O_NONE:
			return
		if cls == UT.CLS_ART and sim.u_ammo[u] <= 0:
			# An empty battery stays out of the way, refilling if it can.
			if sim.u_refill[u] == 0 and sim.u_rprog[u] == 0 and _can_refill(sim, u) \
					and not _art_threatened(sim, u):
				_order(sim, u, {"type": ORDER_REFILL, "on": 1}, 23)
			return
		if sim.u_routs[u] == 0 and sim.u_alive[u] * 100 < sim.u_count0[u] * kn[AP.RETIRE_ALIVE_PCT]:
			_count(sim, side, AP.C_SAVED)  # fell back mauled and returns without having broken
		elif kn[AP.SK_MEM] != 0 and sim.u_routs[u] == 0 and _mem(sim, u, AP.MU_X) == 2:
			_count(sim, side, AP.C_SAVED)  # rotated out (or pulled back wavering) and back unbroken
		_set_mode(sim, u, A_ATTACK if cls != UT.CLS_CAV else A_HOLD)
		if kn[AP.SK_MEM] != 0 and _mem(sim, u, AP.MU_X) == 2:
			# Recovered behind the line: it is the reserve now (rotation).
			_mset(sim, u, AP.MU_X, 0)
			if kn[AP.SK_RESERVE] > 0 and _is_foot(sim, u):
				_mset(sim, u, AP.MU_X, 1)
				_set_mode(sim, u, A_RESV)
		mode = sim.u_ai[u]
	if mode == A_IDLE:
		# Left idle (a mistake): until IDLE_TICKS have passed or it is attacked.
		if sim.tick - sim.u_ai_t[u] < kn[AP.IDLE_TICKS] and sim.u_fighting[u] == 0 and sim.u_contact[u] == 0:
			return
		_set_mode(sim, u, A_ATTACK)
		mode = A_ATTACK
	if cls != UT.CLS_CAV and UT.stat(sim.u_type[u], "vs_cav") > 0:
		_watch_cav(sim, u, kn[AP.SPEAR_CAV_R])
	if mode == A_RESV:
		_resv_think(sim, u, kn)
		return
	if cls == UT.CLS_CAV:
		_cav_think(sim, u, phase)
	elif cls == UT.CLS_MISSILE:
		_missile_think(sim, u, phase)
	elif cls == UT.CLS_ART:
		_art_think(sim, u, phase)
	elif mode == A_GUARD:
		_guard_think(sim, u)
	elif phase == P_ENGAGE or mode != A_LINE:
		_melee_think(sim, u)


static func _retire(sim, u: int) -> void:
	var side: int = sim.u_side[u]
	var back := AP.of(sim, side)[AP.RETIRE_BACK]
	var y: int = sim.u_ay[u] + (back if side == 0 else -back)
	y = clampi(y, 4 * M, sim.field_h - 4 * M)
	var face := 768 if side == 0 else 256
	_move(sim, u, sim.u_ax[u], y, face, _width(sim, u), 1, 0)
	_set_mode(sim, u, A_RETIRE)


static func _set_mode(sim, u: int, mode: int) -> void:
	if sim.u_ai[u] != mode:
		sim.stat_ai[mode] += 1
		sim.u_ai[u] = mode
		sim.u_ai_t[u] = sim.tick
		sim.u_ai_x[u] = 0
		sim.u_ai_y[u] = 0


static func _melee_think(sim, u: int) -> void:
	var mode: int = sim.u_ai[u]
	var side: int = sim.u_side[u]
	var kn := AP.of(sim, side)
	if kn[AP.SK_GUARD_CAV_R] > 0 and _mem(sim, u, AP.MU_X) >= 4 and _sk_reguard(sim, u, kn):
		return
	var spear := UT.stat(sim.u_type[u], "vs_cav") > 0
	var cur := -1
	if sim.u_order[u] == O_ATTACK:
		cur = sim.u_target[u]
	# Engaged with a ready enemy: keep fighting it.
	if cur >= 0 and sim.u_fighting[u] > 0 and sim.u_state[cur] == U_READY:
		return
	# Chasing a router (a mistake): after it until it is gone or rallies.
	if cur >= 0 and sim.u_state[cur] == U_ROUTING and sim.u_ai_y[u] == -(cur + 2):
		return
	if mode == A_DETOUR:
		var dt: int = sim.u_ai_y[u]
		if dt >= 0 and sim.u_state[dt] == U_READY:
			var arrived: bool = sim.u_order[u] != O_MOVE \
				or _d(sim.u_ax[u] - sim.u_dx[u], sim.u_ay[u] - sim.u_dy[u]) < kn[AP.FLANK_ARRIVE]
			if not arrived and sim.tick - sim.u_ai_t[u] < kn[AP.DETOUR_TIMEOUT] and sim.u_contact[u] == 0:
				return
			_attack(sim, u, dt, 1)
			_set_mode(sim, u, A_ATTACK)
			sim.u_ai_x[u] = dt + 1  # this target's approach is settled
			return
		_set_mode(sim, u, A_ATTACK)
		mode = A_ATTACK
	if mode == A_FLANK:
		var t: int = sim.u_target[u] if sim.u_order[u] == O_ATTACK else sim.u_ai_y[u]
		if t >= 0 and sim.u_state[t] == U_READY:
			var sx: int = sim.u_dx[u]
			var sy: int = sim.u_dy[u]
			var arrived: bool = sim.u_order[u] != O_MOVE or _d(sim.u_ax[u] - sx, sim.u_ay[u] - sy) < kn[AP.FLANK_ARRIVE]
			if not arrived and sim.tick - sim.u_ai_t[u] < kn[AP.FLANK_TIMEOUT] and sim.u_formed[t] != 0:
				return
			_attack(sim, u, t, 1)
			_set_mode(sim, u, A_ATTACK)
			return
		_set_mode(sim, u, A_ATTACK)
	var best := -1
	# Spears turn on cavalry close by.
	if spear:
		if kn[AP.SK_SPEAR_LEAD] > 0:
			best = _sk_cav_lead(sim, u, kn[AP.SPEAR_CAV_R], kn[AP.SK_SPEAR_LEAD])
		else:
			best = _nearest(sim, u, UT.CLS_CAV, kn[AP.SPEAR_CAV_R])
		if best >= 0 and best != cur and _mistake(sim, side, AP.M_LATE_FLANK, kn):
			return  # a late reaction: carries on as it was this think
		if best >= 0 and best != cur:
			_count(sim, side, AP.C_SPEAR_RESP)
			if sim.dbg_cav_seen.size() > u and sim.dbg_cav_seen[u] >= 0:
				_count(sim, side, AP.C_SPEAR_RESP_T, sim.tick - sim.dbg_cav_seen[u])
	var chase := false
	if best < 0 and kn[AP.SK_ASSIGN] != 0:
		var a := _mem(sim, u, AP.MU_ASSIGN) - 1
		if a >= 0 and sim.u_state[a] == U_READY:
			best = a
	if best < 0:
		best = _nearest_enemy(sim, u, true)
		if best >= 0 and kn[AP.MK_BASE + AP.M_CHASE] > 0:
			# Mistake: a routing enemy closer than the fight draws the foot after it.
			var r := _nearest_enemy(sim, u, false)
			if r >= 0 and sim.u_state[r] == U_ROUTING and _dist2(sim, u, r) < _dist2(sim, u, best) \
					and _mistake(sim, side, AP.M_CHASE, kn):
				best = r
				chase = true
	if best < 0:
		best = _nearest_enemy(sim, u, false)
	if best < 0:
		return
	# Formed enemy pikes: do not walk into the points if it can be helped
	# (unless the mistake is to walk into them).
	if sim.u_formed[best] != 0 and sim.u_cls[u] != UT.CLS_PIKE and _frontal(sim, best, u) \
			and not _mistake(sim, side, AP.M_SPEAR_CHARGE, kn):
		var pinned := false
		for o in sim.n_units:
			if o != u and sim.u_side[o] == sim.u_side[u] and sim.u_order[o] == O_ATTACK \
					and sim.u_target[o] == best and sim.u_state[o] == U_READY:
				pinned = true
				break
		if pinned and _chance(sim, kn[AP.FLANK_PCT]):
			_flank(sim, u, best)
			return
		var alt := _nearest_not(sim, u, best)
		var alt_pct := kn[AP.PIKE_ALT_PCT]
		if alt >= 0 and _dist2(sim, u, alt) * 10000 <= _dist2(sim, u, best) * (alt_pct * alt_pct):
			best = alt
	if sim.ter_on != 0:
		# Holding high ground: let the enemy come.
		if sim.ai_hold[side] >= 0 and _bbox_gap(sim, u, best) > kn[AP.HOLD_REACT] \
				and sim.u_fighting[u] == 0:
			return
		if sim.u_ai_x[u] != best + 1 and sim.u_fighting[u] == 0 and _detour(sim, u, best):
			return
	var cr := kn[AP.CHARGE_RANGE]
	var run := 1 if _dist2(sim, u, best) < cr * cr else 0
	if best != cur or run != sim.u_run[u]:
		_attack(sim, u, best, run)
		if sim.u_state[best] == U_ROUTING:
			_count(sim, side, AP.C_INF_CHASE)
	_set_mode(sim, u, A_ATTACK)
	if chase:
		sim.u_ai_y[u] = -(best + 2)


## Send u round to the flank of enemy unit t, then attack.
static func _flank(sim, u: int, t: int) -> void:
	var tf: int = sim.u_face[t]
	var c := FM.cos_a(tf)
	var s := FM.sin_a(tf)
	var hw: int = (mini(sim.u_files[t], sim.u_alive[t]) * UT.stat(sim.u_type[t], "file_sp")) / 2
	var lat: int = (((sim.u_cy[u] - sim.u_ay[t]) * c - (sim.u_cx[u] - sim.u_ax[t]) * s) / FM.TRIG_ONE)
	var sgn := 1 if lat >= 0 else -1
	var out := sgn * (hw + AP.of(sim, sim.u_side[u])[AP.FLANK_OUT])
	var depth: int = sim.unit_depth(t)
	var px: int = sim.u_ax[t] + ((-s * out - c * depth / 2) / FM.TRIG_ONE)
	var py: int = sim.u_ay[t] + ((c * out - s * depth / 2) / FM.TRIG_ONE)
	px = clampi(px, 4 * M, sim.field_w - 4 * M)
	py = clampi(py, 4 * M, sim.field_h - 4 * M)
	# Face the enemy's flank on arrival.
	var face := FM.atan2_a(sim.u_ay[t] - py, sim.u_ax[t] - px)
	_move(sim, u, px, py, face, _width(sim, u), 1, 0)
	_set_mode(sim, u, A_FLANK)
	sim.u_ai_y[u] = t


## True when unit `from` is in the frontal arc of unit t.
static func _frontal(sim, t: int, from: int) -> bool:
	var ang := FM.atan2_a(sim.u_cy[from] - sim.u_cy[t], sim.u_cx[from] - sim.u_cx[t])
	return absi(FM.angle_diff(sim.u_face[t], ang)) <= FRONT_ARC


static func _cav_think(sim, u: int, phase: int) -> void:
	var mode: int = sim.u_ai[u]
	var tick: int = sim.tick
	var side: int = sim.u_side[u]
	var kn := AP.of(sim, side)
	if mode == A_PULL:
		var arrived: bool = sim.u_order[u] != O_MOVE
		if not arrived and tick - sim.u_ai_t[u] < kn[AP.CAV_PULL_TICKS]:
			return
		_set_mode(sim, u, A_HOLD)
		mode = A_HOLD
	if mode == A_CHARGE:
		var t: int = sim.u_target[u] if sim.u_order[u] == O_ATTACK else -1
		if t < 0 or sim.u_state[t] >= U_DESTROYED:
			_set_mode(sim, u, A_HOLD)
			mode = A_HOLD
		elif sim.u_state[t] == U_ROUTING:
			return  # ride them down
		elif sim.u_fighting[u] > 0:
			if sim.u_ai_x[u] == 0:
				sim.u_ai_x[u] = tick
				if kn[AP.SK_PULL_READ] != 0:
					_mset(sim, u, AP.MU_A0, sim.u_alive[u])
					_mset(sim, u, AP.MU_T0, sim.u_alive[t])
			elif tick - sim.u_ai_x[u] > kn[AP.CAV_MELEE_TICKS]:
				if kn[AP.SK_PULL_READ] != 0 and _sk_winning(sim, u, t, kn):
					# Winning this melee: stay, and judge again after as long.
					_count(sim, side, AP.C_CAV_STAY)
					sim.u_ai_x[u] = tick
					_mset(sim, u, AP.MU_A0, sim.u_alive[u])
					_mset(sim, u, AP.MU_T0, sim.u_alive[t])
				else:
					_pull_out(sim, u, t)
			return
		elif sim.u_ai_y[u] == 1:
			return  # charging a braced front on purpose (a mistake): no going round
		elif _is_braced_front(sim, t, u) and _dist2(sim, u, t) > kn[AP.CAV_RESTAGE_DIST] * kn[AP.CAV_RESTAGE_DIST]:
			# The target turned its points toward us: go round.
			_stage(sim, u, t)
			return
		else:
			return
	if mode == A_STAGE:
		var t: int = sim.u_ai_y[u]
		if t < 0 or sim.u_state[t] >= U_DESTROYED:
			_set_mode(sim, u, A_HOLD)
		else:
			var arrived: bool = sim.u_order[u] != O_MOVE
			if arrived or tick - sim.u_ai_t[u] > kn[AP.CAV_STAGE_TICKS] or not _is_braced_front(sim, t, u) and not _frontal(sim, t, u):
				if kn[AP.SK_CAV_PAIR] > 0 and _sk_wait_partner(sim, u, t, kn):
					return
				_attack(sim, u, t, 1)
				_set_mode(sim, u, A_CHARGE)
				if kn[AP.SK_CAV_PAIR] > 0:
					_sk_count_double(sim, u, t)
			return
	# Under arrows while waiting: ride down the shooters if nobody guards
	# them, otherwise get out of their fire.
	if tick - sim.u_hit_t[u] < kn[AP.CAV_ARROW_REACT]:
		var shooter := _shooting_at(sim, u)
		if shooter >= 0:
			if not _protected(sim, shooter, side):
				_attack(sim, u, shooter, 1)
				_set_mode(sim, u, A_CHARGE)
			else:
				_pull_out(sim, u, shooter)
			return
	# Shelled while waiting: ride down the battery if nobody guards it,
	# otherwise get out of its arc.
	if tick - sim.u_shelled_t[u] < kn[AP.CAV_SHELL_REACT]:
		var bat: int = sim.u_shelled_by[u]
		if bat >= 0 and sim.u_state[bat] == U_READY:
			if not _protected(sim, bat, side):
				_attack(sim, u, bat, 1)
				_set_mode(sim, u, A_CHARGE)
			else:
				_sidestep(sim, u, bat)
			return
	# Hold: look for a target.
	var pick := _cav_pick(sim, u, phase)
	if pick < 0:
		return
	if kn[AP.SK_CAV_RESERVE] > 0 and _mem(sim, u, AP.MU_X) == 3 and not _sk_reserve_cav_may(sim, u, pick, kn):
		return  # the reserve waits for the enemy to waver (or for riders on our flank)
	if sim.u_cls[pick] == UT.CLS_CAV and sim.u_state[pick] == U_READY and _mistake(sim, side, AP.M_LATE_FLANK, kn):
		return  # enemy riders on our flank, noticed late
	if not _is_foot(sim, pick) and sim.u_state[pick] == U_READY and _mistake(sim, side, AP.M_WRONG_TARGET, kn):
		# The nearest enemy foot instead of the chosen target.
		var near := _nearest_foot(sim, u)
		if near >= 0:
			pick = near
	if _frontal(sim, pick, u) and (UT.stat(sim.u_type[pick], "brace") > 0 or sim.u_fighting[pick] == 0) \
			and sim.u_cls[pick] != UT.CLS_MISSILE and sim.u_cls[pick] != UT.CLS_CAV \
			and sim.u_cls[pick] != UT.CLS_ART and sim.u_state[pick] == U_READY:
		var braced := UT.stat(sim.u_type[pick], "brace") > 0
		if braced and _mistake(sim, side, AP.M_SPEAR_CHARGE, kn):
			_attack(sim, u, pick, 1)  # straight into the points
			_set_mode(sim, u, A_CHARGE)
			sim.u_ai_y[u] = 1
		elif braced or kn[AP.CAV_STAGE_FRONT] != 0:
			_stage(sim, u, pick)
		else:
			_attack(sim, u, pick, 1)  # head on into a formed front
			_set_mode(sim, u, A_CHARGE)
	else:
		_attack(sim, u, pick, 1)
		_set_mode(sim, u, A_CHARGE)
		if kn[AP.SK_CAV_PAIR] > 0:
			_sk_count_double(sim, u, pick)


static func _is_braced_front(sim, t: int, from: int) -> bool:
	return UT.stat(sim.u_type[t], "brace") > 0 and sim.u_state[t] == U_READY and _frontal(sim, t, from)


static func _stage(sim, u: int, t: int) -> void:
	# Ride to a point off the target's flank (the side nearer to us), level
	# with its rear ranks, then charge from there.
	var tf: int = sim.u_face[t]
	var c := FM.cos_a(tf)
	var s := FM.sin_a(tf)
	var hw: int = (mini(sim.u_files[t], sim.u_alive[t]) * UT.stat(sim.u_type[t], "file_sp")) / 2
	var lat: int = (((sim.u_cy[u] - sim.u_ay[t]) * c - (sim.u_cx[u] - sim.u_ax[t]) * s) / FM.TRIG_ONE)
	var sgn := 1 if lat >= 0 else -1
	var kn := AP.of(sim, sim.u_side[u])
	var out := sgn * (hw + kn[AP.CAV_STAGE_OUT])
	var back: int = sim.unit_depth(t) + kn[AP.CAV_STAGE_BACK]
	var px: int = sim.u_ax[t] + ((-s * out - c * back) / FM.TRIG_ONE)
	var py: int = sim.u_ay[t] + ((c * out - s * back) / FM.TRIG_ONE)
	px = clampi(px, 6 * M, sim.field_w - 6 * M)
	py = clampi(py, 6 * M, sim.field_h - 6 * M)
	var face := FM.atan2_a(sim.u_cy[t] - py, sim.u_cx[t] - px)
	_move(sim, u, px, py, face, _width(sim, u), 1, 0)
	_set_mode(sim, u, A_STAGE)
	sim.u_ai_y[u] = t


static func _pull_out(sim, u: int, t: int) -> void:
	var dx: int = sim.u_cx[u] - sim.u_cx[t]
	var dy: int = sim.u_cy[u] - sim.u_cy[t]
	var kn := AP.of(sim, sim.u_side[u])
	# Bias toward our own side of the field.
	dy += kn[AP.CAV_PULL_BIAS] if sim.u_side[u] == 0 else -kn[AP.CAV_PULL_BIAS]
	var d := maxi(_d(dx, dy), 1)
	var px := clampi(sim.u_cx[u] + dx * kn[AP.CAV_PULL_DIST] / d, 6 * M, sim.field_w - 6 * M)
	var py := clampi(sim.u_cy[u] + dy * kn[AP.CAV_PULL_DIST] / d, 6 * M, sim.field_h - 6 * M)
	var face := FM.atan2_a(sim.u_cy[t] - py, sim.u_cx[t] - px)
	_move(sim, u, px, py, face, _width(sim, u), 1, 0)
	if sim.u_ai[u] != A_PULL:
		_count(sim, sim.u_side[u], AP.C_PULL_OUT)
	_set_mode(sim, u, A_PULL)


## Best cavalry target: unprotected missile troops, enemy cavalry near our
## flank, then (once the lines meet) engaged enemies, then routers.
static func _cav_pick(sim, u: int, phase: int) -> int:
	var side: int = sim.u_side[u]
	var kn := AP.of(sim, side)
	var best := -1
	var best_score := 0
	for t in sim.n_units:
		if sim.u_side[t] == side or sim.u_state[t] >= U_DESTROYED:
			continue
		var d := _d(sim.u_cx[t] - sim.u_cx[u], sim.u_cy[t] - sim.u_cy[u]) / M
		var score := 0
		var cls: int = sim.u_cls[t]
		if sim.u_state[t] == U_ROUTING:
			if phase == P_ENGAGE:
				score = kn[AP.CAV_SC_ROUTER]
		elif cls == UT.CLS_MISSILE and not _protected(sim, t, side):
			# Best while their arrows go elsewhere; riding in under their
			# fire costs riders, so only from close or as a lesser choice.
			score = kn[AP.CAV_SC_MISSILE] if sim.u_ftarget[t] != u or d < kn[AP.CAV_MISSILE_CLOSE] \
				else kn[AP.CAV_SC_MISSILE_FIRE]
		elif cls == UT.CLS_ART and not _protected(sim, t, side):
			score = kn[AP.CAV_SC_BATTERY]  # an unguarded battery: wreck it
		elif cls == UT.CLS_ART and phase == P_ENGAGE:
			score = kn[AP.CAV_SC_BATTERY_GUARDED]
		elif cls == UT.CLS_CAV and _threatens(sim, t, side):
			score = kn[AP.CAV_SC_CAV_THREAT]
		elif phase == P_ENGAGE and sim.u_fighting[t] > 0:
			score = kn[AP.CAV_SC_ENGAGED] if not _is_braced_front(sim, t, u) else kn[AP.CAV_SC_ENGAGED_BRACED]
		elif phase == P_ENGAGE and cls == UT.CLS_MISSILE:
			score = kn[AP.CAV_SC_MISSILE_LATE]
		if score == 0:
			continue
		if kn[AP.SK_MEM] != 0:
			score += _sk_cav_bonus(sim, u, t, kn)
		score -= d * kn[AP.CAV_SC_DIST]
		if sim.ter_on != 0:
			# Charging uphill costs momentum and impact: prefer level or
			# downhill targets (60 points per % of climb).
			var g: int = sim.grade_between(sim.u_h[u], sim.u_h[t], maxi(d, 1) * M)
			if g > 0:
				score -= g * kn[AP.CAV_SC_UPHILL] / FM.TRIG_ONE
		if sim.veg_on != 0:
			# Woods break a charge: prefer targets in the open, reached
			# across open ground.
			score -= _woods_cost(sim, sim.u_cx[u], sim.u_cy[u], sim.u_cx[t], sim.u_cy[t]) * kn[AP.CAV_SC_WOODS_PATH]
			score -= sim.veg_d(sim.u_cx[t], sim.u_cy[t]) * kn[AP.CAV_SC_WOODS_AT]
		if best < 0 or score > best_score:
			best = t
			best_score = score
	return best


## Enemy missile unit currently shooting at unit u, or -1.
static func _shooting_at(sim, u: int) -> int:
	for o in sim.n_units:
		if sim.u_side[o] != sim.u_side[u] and sim.u_state[o] == U_READY and sim.u_ftarget[o] == u:
			return o
	return -1


## Unit t has a ready melee friend close by (as side `judge` sees it).
static func _protected(sim, t: int, judge: int) -> bool:
	var r := AP.of(sim, judge)[AP.UNPROTECTED]
	for o in sim.n_units:
		if o == t or sim.u_side[o] != sim.u_side[t] or sim.u_state[o] != U_READY:
			continue
		if sim.u_cls[o] == UT.CLS_MISSILE:
			continue
		if _bbox_gap(sim, o, t) < r:
			return true
	return false


## Enemy cavalry t is close to one of our units that is not cavalry.
static func _threatens(sim, t: int, side: int) -> bool:
	var r := AP.of(sim, side)[AP.CAV_THREAT]
	for o in sim.n_units:
		if sim.u_side[o] != side or sim.u_state[o] != U_READY or sim.u_cls[o] == UT.CLS_CAV:
			continue
		if _bbox_gap(sim, o, t) < r:
			return true
	return false


## A missile unit out of ammunition and not fighting: engines of its side
## left on the field (a battery broke or died) within ENGINE_TAKE_R of it
## are worth taking up (docs/AI.md 17). Orders the pick-up (once); true
## while it goes for them.
static func _take_engines(sim, u: int) -> bool:
	if sim.n_eg == 0 or sim.u_fighting[u] > 0 or sim.u_contact[u] != 0:
		return false
	if sim.u_pick[u] >= PICK_ENG:
		return true  # on its way
	var best := -1
	var bd := 0
	for g in sim.n_eg:
		if sim.eg_side[g] != sim.u_side[u] or not sim.engines_free(g) or not sim.may_take_engines(u, g):
			continue
		var at: Vector2i = sim.engines_xy(g)
		var d := _d(at.x - sim.u_cx[u], at.y - sim.u_cy[u])
		if d <= ENGINE_TAKE_R and (best < 0 or d < bd):
			best = g
			bd = d
	if best < 0:
		return false
	_order(sim, u, {"type": ORDER_PICKUP, "engines": best, "run": 0}, 26)
	return true


static func _missile_think(sim, u: int, phase: int) -> void:
	var side: int = sim.u_side[u]
	var kn := AP.of(sim, side)
	if sim.u_fighting[u] > 0:
		_count(sim, side, AP.C_MISSILE_CAUGHT)
	if sim.u_skirm[u] == 0 and kn[AP.MIS_SKIRM] != 0:
		_order(sim, u, {"type": ORDER_SKIRMISH, "on": 1}, 20)
	if sim.u_forage[u] != 0:
		return  # making missiles in the woods (the sim stops it if attacked)
	if sim.u_ammo[u] > 0 and resupply(sim, u, kn):
		return
	if sim.u_ammo[u] <= 0:
		# Out of ammunition: finish off routers nearby, refill at a wagon of
		# ours or forage in the woods, take up engines its side left near by,
		# otherwise keep clear.
		var r := _nearest_routing(sim, u, kn[AP.MIS_ROUTER_R])
		if r >= 0:
			if sim.u_order[u] != O_ATTACK or sim.u_target[u] != r:
				_attack(sim, u, r, 1)
		elif resupply(sim, u, kn) or forage(sim, u, kn):
			pass
		elif _take_engines(sim, u):
			pass
		elif sim.u_ai[u] != A_RETIRE and phase == P_ENGAGE:
			_retire(sim, u)
		return
	if kn[AP.SK_MIS_EARLY_R] > 0 and phase == P_ADVANCE and sim.u_ai[u] == A_LINE and _sk_mis_early(sim, u, kn):
		return
	# Hold fire unless an unengaged enemy is in range.
	var rng: int = sim.mrange(u)
	var clean := kn[AP.MIS_CLEAN] == 0  # (0: fire at will regardless)
	for o in sim.n_units:
		if clean:
			break
		if sim.u_side[o] == side or sim.u_state[o] >= U_DESTROYED:
			continue
		if sim.u_fighting[o] == 0 and sim._in_range(u, o, rng):
			clean = true
			break
	var want := 1 if clean else 0
	if sim.u_fire[u] != want:
		_order(sim, u, {"type": ORDER_FIRE, "on": want}, 21)
	if sim.veg_on != 0 and _shelter(sim, u):
		return
	# Once the lines meet, archers move behind the line.
	if phase == P_ENGAGE and sim.u_ai[u] == A_LINE and UT.stat(sim.u_type[u], "m_arc") != 0:
		var plan := _plan(sim, side)
		if not plan.is_empty():
			var fx: int = plan["fx"]
			var fy: int = plan["fy"]
			var cx: int = plan["cx"]
			var cy: int = plan["cy"]
			var ahead: int = (((sim.u_ax[u] - cx) * fx + (sim.u_ay[u] - cy) * fy) / FM.TRIG_ONE)
			if ahead > -kn[AP.MIS_BEHIND] and _mistake(sim, side, AP.M_MIS_FORGET, kn):
				pass  # left out in front of the line (a mistake)
			elif ahead > -kn[AP.MIS_BEHIND]:
				var back: int = ahead + kn[AP.MIS_FALLBACK]
				var px: int = clampi(sim.u_ax[u] - (fx * back / FM.TRIG_ONE), 4 * M, sim.field_w - 4 * M)
				var py: int = clampi(sim.u_ay[u] - (fy * back / FM.TRIG_ONE), 4 * M, sim.field_h - 4 * M)
				_move(sim, u, px, py, plan["face"], _width(sim, u), 0, 0)
		_set_mode(sim, u, A_ATTACK)
	elif phase == P_ENGAGE and sim.u_ai[u] == A_LINE:
		_set_mode(sim, u, A_ATTACK)
	if kn[AP.SK_FOCUS] != 0:
		_sk_focus(sim, u, kn)
	ammo_pick(sim, u, kn)


# ------------------------------------------------------------ artillery ---

## Battery: shoot the best safe target in range; with none in range, move up
## behind the line; out of ammunition or engines, get out of the way.
static func _art_think(sim, u: int, phase: int) -> void:
	var side: int = sim.u_side[u]
	var kn := AP.of(sim, side)
	var ty: int = sim.u_type[u]
	# Refilling from the baggage: carry on unless threatened, or three
	# quarters full again with something to shoot.
	var full: int = sim.u_neng[u] * UT.stat(ty, "m_ammo")
	var low: int = full * kn[AP.REFILL_LOW_PCT]
	var enough: int = full * kn[AP.REFILL_FULL_PCT]
	if sim.u_refill[u] != 0:
		if _art_threatened(sim, u) or (sim.u_ammo[u] * 100 >= enough and _art_has_target(sim, u)):
			_order(sim, u, {"type": ORDER_REFILL, "on": 0}, 23)
		return
	if sim.u_rprog[u] > 0:
		return  # still getting out of it
	if sim.u_order[u] != O_MOVE and _can_refill(sim, u) and not _art_threatened(sim, u) \
			and (sim.u_ammo[u] * 100 <= low or (sim.u_ammo[u] * 100 < enough and not _art_has_target(sim, u))):
		_order(sim, u, {"type": ORDER_REFILL, "on": 1}, 23)
		return
	if sim.u_ammo[u] <= 0:
		if sim.u_ai[u] != A_RETIRE:
			_retire(sim, u)
		return
	if kn[AP.SK_ART_PULL] != 0 and sim.u_ai[u] != A_RETIRE and _sk_art_pull(sim, u, kn):
		return
	if sim.u_order[u] == O_MOVE:
		return  # moving up with the line: set up again on arrival
	var rng: int = sim.mrange(u)
	var mn := UT.stat(ty, "m_min")
	var bolt := UT.stat(ty, "m_kind") == 1
	var best := -1
	var best_score := 0
	var any_in_range := false
	var blocked := 0  # in range but behind a crest (bolts on hilly ground)
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] != U_READY or sim.u_alive[o] <= 0:
			continue
		if not sim._art_in_range(u, o, mn, rng):
			continue
		any_in_range = true
		var ot: int = sim.u_type[o]
		var score: int = sim.u_alive[o] * UT.stat(ot, "cost")
		var oc: int = sim.u_cls[o]
		if oc == UT.CLS_ART:
			score += kn[AP.ART_SC_BATTERY]  # silence their batteries
		if bolt and oc == UT.CLS_PIKE:
			score = score * kn[AP.ART_SC_PIKE_PCT] / 100  # deep and dense: bolts go through ranks
		if oc == UT.CLS_CAV:
			score = score * kn[AP.ART_SC_CAV_PCT] / 100  # fast and spread out
		if sim.u_moved[o] == 0:
			score = score * kn[AP.ART_SC_STILL_NUM] / kn[AP.ART_SC_STILL_DEN]
		elif not bolt:
			score = score * kn[AP.ART_SC_MOVING_PCT] / 100  # stones cannot lead a moving target
		score -= sim._unit_dist(u, o) / M
		# Safety (friends in the way; a crest for bolts) only for a target
		# that would be chosen: the line of fire test is the dear part.
		if best < 0 or score > best_score:
			if not sim.art_safe(u, o):
				if bolt and sim.ter_on != 0 and not sim.lof_units(u, o):
					blocked += 1
				continue  # the shot would carry into friends or into the ground
			best = o
			best_score = score
	if best >= 0:
		if sim.u_order[u] != O_ATTACK or sim.u_target[u] != best:
			_attack(sim, u, best, 0)
		if sim.u_fire[u] == 0:
			_order(sim, u, {"type": ORDER_FIRE, "on": 1}, 21)
		ammo_pick(sim, u, kn, best)
		return
	if sim.u_order[u] == O_ATTACK:
		# Nothing safe to shoot: stop (an attack order shoots regardless).
		_order(sim, u, {"type": ORDER_HALT}, 22)
	if blocked > 0 and _art_resite(sim, u):
		return
	if any_in_range or phase != P_ENGAGE:
		return
	# Nothing in range: move up to where the plan wants batteries.
	var plan := _plan(sim, side)
	if plan.is_empty():
		return
	var fx: int = plan["fx"]
	var fy: int = plan["fy"]
	var back := kn[AP.ART_BACK] if not bolt else 0
	var px: int = clampi(plan["cx"] - (fx * back / FM.TRIG_ONE) + (sim.u_cx[u] - plan["cx"]) / 4,
		6 * M, sim.field_w - 6 * M)
	var py: int = clampi(plan["cy"] - (fy * back / FM.TRIG_ONE) + (sim.u_cy[u] - plan["cy"]) / 4,
		6 * M, sim.field_h - 6 * M)
	if bolt:
		# Bolts keep to their side of the line, level with it.
		var rx := -fy
		var ry := fx
		var lat: int = ((sim.u_cx[u] - plan["cx"]) * rx + (sim.u_cy[u] - plan["cy"]) * ry) / FM.TRIG_ONE
		px = clampi(plan["cx"] + (rx * lat / FM.TRIG_ONE), 6 * M, sim.field_w - 6 * M)
		py = clampi(plan["cy"] + (ry * lat / FM.TRIG_ONE), 6 * M, sim.field_h - 6 * M)
	if _d(px - sim.u_ax[u], py - sim.u_ay[u]) > kn[AP.ART_MOVE]:
		_move(sim, u, px, py, plan["face"], _width(sim, u), 0, 0)


## Battery u has an enemy unit within its range band.
static func _art_has_target(sim, u: int) -> bool:
	var ty: int = sim.u_type[u]
	var rng: int = sim.mrange(u)
	var mn := UT.stat(ty, "m_min")
	for o in sim.n_units:
		if sim.u_side[o] != sim.u_side[u] and sim.u_state[o] == U_READY \
				and sim._art_in_range(u, o, mn, rng):
			return true
	return false


## Battery u has shots in its baggage and a working engine short of its
## full load (abandoned or wrecked engines cannot be refilled).
static func _can_refill(sim, u: int) -> bool:
	if sim.u_reserve[u] <= 0 and (sim.n_eq == 0 or sim.wagon_for(u) < 0):
		return false
	var full := UT.stat(sim.u_type[u], "m_ammo")
	for k in sim.u_neng[u]:
		var e: int = sim.u_eng0[u] + k
		if sim.e_state[e] == 0 and sim.e_ammo[e] < full:
			return true
	return false


## Battery u is threatened: an enemy melee unit (not missile troops or
## artillery) within REFILL_SAFE of it, or one coming for it (attacking it)
## within REFILL_WATCH. A fight 30 m ahead of a battery is not a threat to it.
static func _art_threatened(sim, u: int) -> bool:
	var kn := AP.of(sim, sim.u_side[u])
	var safe := kn[AP.REFILL_SAFE]
	var watch := kn[AP.REFILL_WATCH]
	for o in sim.n_units:
		if sim.u_side[o] == sim.u_side[u] or sim.u_state[o] != U_READY:
			continue
		var c: int = sim.u_cls[o]
		if c == UT.CLS_MISSILE or c == UT.CLS_ART:
			continue
		var g := _bbox_gap(sim, u, o)
		if g < safe or (g < watch and sim.u_order[o] == O_ATTACK and sim.u_target[o] == u):
			return true
	return false


## One infantry unit (spears first, else light, else heavy) guards battery b.
static func _pick_guard(sim, side: int, b: int) -> void:
	var best := -1
	var best_k := 0
	var melee := 0
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY:
			continue
		var c: int = sim.u_cls[u]
		if c != UT.CLS_INF or is_wagon(sim, u):
			if c == UT.CLS_PIKE:
				melee += 1
			continue
		melee += 1
		var k := 1
		if UT.stat(sim.u_type[u], "vs_cav") > 0:
			k = 3
		elif sim.u_type[u] == UT.LIGHT:
			k = 2
		if best < 0 or k > best_k or (k == best_k and _dist2(sim, u, b) < _dist2(sim, best, b)):
			best = u
			best_k = k
	if best < 0 or melee < AP.of(sim, side)[AP.GUARD_MIN_MELEE]:
		return  # too small an army to spare a guard
	_set_mode(sim, best, A_GUARD)
	sim.u_ai_y[best] = b
	_guard_post(sim, best, b)


## Guard post: beside battery b on its outer side (away from the army's
## centre), a little forward, facing the enemy.
static func _guard_post(sim, g: int, b: int) -> void:
	var side: int = sim.u_side[g]
	var plan := _plan(sim, side)
	if plan.is_empty():
		return
	var fx: int = plan["fx"]
	var fy: int = plan["fy"]
	var rx := -fy
	var ry := fx
	var lat: int = ((sim.u_ax[b] - plan["cx"]) * rx + (sim.u_ay[b] - plan["cy"]) * ry) / FM.TRIG_ONE
	var sgn := 1 if lat >= 0 else -1
	var kn := AP.of(sim, side)
	var out: int = sgn * (sim.unit_half_width(b) + sim.unit_half_width(g) + kn[AP.GUARD_OUT])
	var px: int = sim.u_ax[b] + (rx * out / FM.TRIG_ONE) + (fx * kn[AP.GUARD_FWD] / FM.TRIG_ONE)
	var py: int = sim.u_ay[b] + (ry * out / FM.TRIG_ONE) + (fy * kn[AP.GUARD_FWD] / FM.TRIG_ONE)
	px = clampi(px, 6 * M, sim.field_w - 6 * M)
	py = clampi(py, 6 * M, sim.field_h - 6 * M)
	_move(sim, g, px, py, plan["face"], _width(sim, g), 0, 3)


## Guard: attack any enemy that comes near the battery, then go back to the
## post. With the battery gone, join the fight.
static func _guard_think(sim, g: int) -> void:
	var b: int = sim.u_ai_y[g]
	if b < 0 or sim.u_state[b] != U_READY or sim.u_ammo[b] <= 0:
		_set_mode(sim, g, A_ATTACK)
		return
	if AP.of(sim, sim.u_side[g])[AP.SK_GUARD_CAV_R] > 0 and _sk_release_guard(sim, g, b):
		return
	var cur := -1
	if sim.u_order[g] == O_ATTACK:
		cur = sim.u_target[g]
	if cur >= 0 and sim.u_state[cur] == U_READY and sim.u_fighting[g] > 0:
		return
	var kn := AP.of(sim, sim.u_side[g])
	var threat := -1
	var td := kn[AP.GUARD_RANGE] * kn[AP.GUARD_RANGE]
	for o in sim.n_units:
		if sim.u_side[o] == sim.u_side[g] or sim.u_state[o] != U_READY:
			continue
		if sim.u_cls[o] == UT.CLS_MISSILE or sim.u_cls[o] == UT.CLS_ART:
			continue
		var d := _dist2(sim, b, o)
		if d < td:
			threat = o
			td = d
	if threat >= 0:
		if cur != threat:
			_attack(sim, g, threat, 1 if td < kn[AP.CHARGE_RANGE] * kn[AP.CHARGE_RANGE] else 0)
		return
	if sim.u_order[g] == O_ATTACK or sim.u_order[g] == O_NONE:
		_guard_post(sim, g, b)


## Step out of battery b's arc: 40 m sideways, away from its line of fire.
static func _sidestep(sim, u: int, b: int) -> void:
	if b < 0:
		return
	var dx: int = sim.u_cx[u] - sim.u_cx[b]
	var dy: int = sim.u_cy[u] - sim.u_cy[b]
	var d := maxi(_d(dx, dy), 1)
	var step := AP.of(sim, sim.u_side[u])[AP.SIDESTEP]
	# Perpendicular to the line of fire, toward our own side of the field.
	var px: int = -dy * step / d
	var py: int = dx * step / d
	var own := 1 if sim.u_side[u] == 0 else -1
	if py * own < 0:
		px = -px
		py = -py
	var x := clampi(sim.u_cx[u] + px, 6 * M, sim.field_w - 6 * M)
	var y := clampi(sim.u_cy[u] + py, 6 * M, sim.field_h - 6 * M)
	_move(sim, u, x, y, sim.u_face[u], _width(sim, u), 1, 4)


# -------------------------------------------------------------- terrain ---

## Mean ground height across a line centred on (x, y) running along (rx, ry)
## (Q12 unit vector): five samples `span` (LINE_SPAN) apart.
static func _line_h(sim, x: int, y: int, rx: int, ry: int, span: int) -> int:
	var sum := 0
	for k in range(-2, 3):
		var px := clampi(x + rx * k * span / FM.TRIG_ONE, 0, sim.field_w)
		var py := clampi(y + ry * k * span / FM.TRIG_ONE, 0, sim.field_h)
		sum += sim.height_at(px, py)
	return sum / 5


## Deployment centre: the plan's, or a spot up to DEPLOY_SHIFT aside, back or
## forward whose line stands DEPLOY_GAIN higher (best first, in a fixed order).
static func _deploy_spot(sim, side: int, plan: Dictionary) -> Vector2i:
	var kn := AP.of(sim, side)
	var span := kn[AP.LINE_SPAN]
	var shift := kn[AP.DEPLOY_SHIFT]
	var cx: int = plan["cx"]
	var cy: int = plan["cy"]
	var fx: int = plan["fx"]
	var fy: int = plan["fy"]
	var rx := -fy
	var ry := fx
	var best := Vector2i(cx, cy)
	var best_h := _line_h(sim, cx, cy, rx, ry, span) + kn[AP.DEPLOY_GAIN] - 1
	var margin := kn[AP.DEPLOY_MARGIN]
	for c in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
			Vector2i(-1, -1), Vector2i(1, -1)]:
		var lat: int = c.x * shift
		var fwd: int = c.y * shift
		var x := cx + (rx * lat + fx * fwd) / FM.TRIG_ONE
		var y := cy + (ry * lat + fy * fwd) / FM.TRIG_ONE
		if x < margin or y < margin or x > sim.field_w - margin or y > sim.field_h - margin:
			continue
		var h := _line_h(sim, x, y, rx, ry, span)
		if h > best_h:
			best = Vector2i(x, y)
			best_h = h
	return best


## Weighted mean ground height of a side's ready units (foot only, or every
## non-cavalry unit).
static func _side_height(sim, side: int, foot_only: bool) -> int:
	var sd: PackedInt32Array = sim.u_side
	var st: PackedInt32Array = sim.u_state
	var cl: PackedInt32Array = sim.u_cls
	var hh: PackedInt32Array = sim.u_h
	var al: PackedInt32Array = sim.u_alive
	var sum := 0
	var w := 0
	for u in sim.n_units:
		if sd[u] != side or st[u] != U_READY:
			continue
		var c := cl[u]
		if c == UT.CLS_CAV or c == UT.CLS_ART or (foot_only and c == UT.CLS_MISSILE):
			continue
		sum += hh[u] * al[u]
		w += al[u]
	return sum / w if w > 0 else -1


## Start holding: our foot stand HOLD_DH above the enemy army, and standing
## still would not just feed the enemy's archers or artillery.
static func _start_hold(sim, side: int) -> bool:
	var own := _side_height(sim, side, true)
	var foe := _side_height(sim, 1 - side, false)
	return own >= 0 and foe >= 0 and own - foe >= AP.of(sim, side)[AP.HOLD_DH] and _hold_ok(sim, side)


static func _keep_holding(sim, side: int) -> bool:
	var kn := AP.of(sim, side)
	if sim.tick - sim.ai_hold[side] > kn[AP.HOLD_TICKS] or not _hold_ok(sim, side):
		return false
	# Once a third of our foot is fighting, the battle is on everywhere.
	var foot := 0
	var fighting := 0
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and _is_foot(sim, u):
			foot += 1
			if sim.u_fighting[u] > 0:
				fighting += 1
	return fighting * kn[AP.HOLD_FIGHT_DIV] < foot


static func _hold_ok(sim, side: int) -> bool:
	var mine := _missile_power(sim, side)
	var theirs := _missile_power(sim, 1 - side)
	var kn := AP.of(sim, side)
	if theirs * 100 > mine * kn[AP.HOLD_OUTSHOT_PCT] + kn[AP.HOLD_OUTSHOT_SLACK] * 10:
		return false  # clearly outshot: waiting only feeds their archers
	if _shelled(sim, side) and _art_power(sim, 1 - side) > _art_power(sim, side):
		return false
	return true


## Advance while skirmishing: stop short on clearly higher ground (a crest)
## still within reach of the enemy, else go the whole way.
static func _crest_advance(sim, side: int, plan: Dictionary, adv: int, gap: int, halt: int) -> int:
	var kn := AP.of(sim, side)
	var span := kn[AP.LINE_SPAN]
	var cx: int = plan["cx"]
	var cy: int = plan["cy"]
	var fx: int = plan["fx"]
	var fy: int = plan["fy"]
	var rx := -fy
	var ry := fx
	var full_h := _line_h(sim, cx + fx * adv / FM.TRIG_ONE, cy + fy * adv / FM.TRIG_ONE, rx, ry, span)
	var best := adv
	var best_h := full_h + kn[AP.CREST_GAIN] - 1
	for k in 4:
		var a := adv * k / 4
		if gap - a > halt + kn[AP.CREST_REACH]:
			continue  # too far from the enemy to shoot from there
		var h := _line_h(sim, cx + fx * a / FM.TRIG_ONE, cy + fy * a / FM.TRIG_ONE, rx, ry, span)
		if h > best_h:
			best = a
			best_h = h
	return best


## Missile and artillery slot: the highest spot within RISE_LAT aside or a
## little back / forward (bolts: one with a line of fire to the enemy
## counts 4 m higher), if RISE_GAIN higher than the slot itself.
static func _rise(sim, u: int, px: int, py: int, rx: int, ry: int, fx: int, fy: int,
		plan: Dictionary) -> Vector2i:
	var bolt: bool = sim.u_cls[u] == UT.CLS_ART and UT.stat(sim.u_type[u], "m_kind") == 1
	var kn := AP.of(sim, sim.u_side[u])
	var gain := kn[AP.RISE_GAIN]
	var bonus := kn[AP.RISE_LOF_BONUS]
	# Candidate spots (the slot itself first) and their ground heights.
	var cx := PackedInt32Array([px])
	var cy := PackedInt32Array([py])
	var ch := PackedInt32Array([sim.height_at(px, py)])
	for c in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var lat: int = c.x * kn[AP.RISE_LAT]
		var fwd: int = c.y * kn[AP.RISE_FWD]
		var x := clampi(px + (rx * lat + fx * fwd) / FM.TRIG_ONE, 4 * M, sim.field_w - 4 * M)
		var y := clampi(py + (ry * lat + fy * fwd) / FM.TRIG_ONE, 4 * M, sim.field_h - 4 * M)
		cx.append(x)
		cy.append(y)
		ch.append(sim.height_at(x, y))
	if not bolt:
		var b := 0
		var bs := ch[0] + gain - 1
		for k in range(1, 9):
			if ch[k] > bs:
				b = k
				bs = ch[k]
		return Vector2i(cx[b], cy[b])
	# Score = height, + 4 m for a bolt battery's line of fire to the enemy.
	# The line test is the dear part: walk the spots from the highest down
	# (ties: in candidate order) and stop once no lower spot can win.
	var order: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8]
	order.sort_custom(func(a: int, b: int) -> bool: return ch[a] > ch[b] or (ch[a] == ch[b] and a < b))
	var score := ch.duplicate()
	var top := ch[order[0]]
	for k in order:
		if ch[k] + bonus <= top:
			break
		if _sees_enemy(sim, u, cx[k], cy[k], ch[k], plan):
			score[k] += bonus
			break
	var best := 0
	var best_s := score[0] + gain - 1
	for k in range(1, 9):
		if score[k] > best_s:
			best = k
			best_s = score[k]
	return Vector2i(cx[best], cy[best])


## Line of fire from a battery spot to the enemy army's centre (coarse,
## 16 m samples: a siting heuristic, not the shot itself).
static func _sees_enemy(sim, u: int, x: int, y: int, h: int, plan: Dictionary) -> bool:
	var ex: int = plan["ex"]
	var ey: int = plan["ey"]
	var d := _d(ex - x, ey - y)
	var apex: int = d * UT.stat(sim.u_type[u], "m_apex") / 100
	return sim.lof_block(x, y, h + LOF_EYE, ex, ey, sim.height_at(ex, ey) + LOF_BODY, apex, 0,
		4 * LOF_STEP) < 0


## Infantry about to attack t up a steep slope (the last DETOUR_MIN of the
## straight approach climbing more than DETOUR_GRADE): go round to the flank
## of t whose approach is clearly gentler, if that detour is not too long.
## Returns true if a detour was ordered.
static func _detour(sim, u: int, t: int) -> bool:
	var dx: int = sim.u_cx[t] - sim.u_cx[u]
	var dy: int = sim.u_cy[t] - sim.u_cy[u]
	var d := _d(dx, dy)
	var kn := AP.of(sim, sim.u_side[u])
	var dmin := kn[AP.DETOUR_MIN]
	if d < dmin:
		return false
	var px0: int = sim.u_cx[t] - dx * dmin / d
	var py0: int = sim.u_cy[t] - dy * dmin / d
	var g: int = sim.grade_between(sim.height_at(px0, py0), sim.u_h[t], dmin)
	if g <= kn[AP.DETOUR_GRADE]:
		return false
	var tf: int = sim.u_face[t]
	var c := FM.cos_a(tf)
	var s := FM.sin_a(tf)
	var hw: int = sim.unit_half_width(t) + kn[AP.DETOUR_OUT]
	var depth: int = sim.unit_depth(t) / 2
	var best := Vector2i(-1, -1)
	var best_g := g * kn[AP.DETOUR_GENTLE_NUM] / kn[AP.DETOUR_GENTLE_DEN]  # must be clearly gentler
	for sgn in [-1, 1]:
		var out: int = sgn * hw
		var px := clampi(sim.u_ax[t] + ((-s * out - c * depth) / FM.TRIG_ONE), 6 * M, sim.field_w - 6 * M)
		var py := clampi(sim.u_ay[t] + ((c * out - s * depth) / FM.TRIG_ONE), 6 * M, sim.field_h - 6 * M)
		var l1 := _d(px - sim.u_cx[u], py - sim.u_cy[u])
		var l2 := _d(sim.u_cx[t] - px, sim.u_cy[t] - py)
		if (l1 + l2) * 10 > d * kn[AP.DETOUR_LONG]:
			continue
		var hp: int = sim.height_at(px, py)
		var g1: int = sim.grade_between(sim.u_h[u], hp, l1)
		var g2: int = sim.grade_between(hp, sim.u_h[t], l2)
		var worst := maxi(g1, g2)
		if worst < best_g:
			best = Vector2i(px, py)
			best_g = worst
	if best.x < 0:
		return false
	var face := FM.atan2_a(sim.u_cy[t] - best.y, sim.u_cx[t] - best.x)
	_move(sim, u, best.x, best.y, face, _width(sim, u), 0, 5)
	_set_mode(sim, u, A_DETOUR)
	sim.u_ai_y[u] = t
	return true


## A bolt battery whose targets are all behind a crest: move to the first
## spot (forward first, then aside) from which the nearest enemy can be
## seen. Returns true if it was ordered to move.
static func _art_resite(sim, u: int) -> bool:
	var t := _nearest_enemy(sim, u, true)
	if t < 0:
		return false
	var dx: int = sim.u_cx[t] - sim.u_cx[u]
	var dy: int = sim.u_cy[t] - sim.u_cy[u]
	var d := maxi(_d(dx, dy), 1)
	var fx := dx * FM.TRIG_ONE / d
	var fy := dy * FM.TRIG_ONE / d
	var rx := -fy
	var ry := fx
	var apex: int = d * UT.stat(sim.u_type[u], "m_apex") / 100
	var zt: int = sim.u_h[t] + LOF_BODY
	for c in [Vector2i(0, 25), Vector2i(-30, 10), Vector2i(30, 10), Vector2i(0, 50),
			Vector2i(-40, 30), Vector2i(40, 30)]:
		var x := clampi(sim.u_cx[u] + (rx * c.x + fx * c.y) * M / FM.TRIG_ONE, 6 * M, sim.field_w - 6 * M)
		var y := clampi(sim.u_cy[u] + (ry * c.x + fy * c.y) * M / FM.TRIG_ONE, 6 * M, sim.field_h - 6 * M)
		if _d(sim.u_cx[t] - x, sim.u_cy[t] - y) < UT.stat(sim.u_type[u], "m_min"):
			continue
		var z: int = sim.height_at(x, y) + LOF_EYE
		if sim.lof_block(x, y, z, sim.u_cx[t], sim.u_cy[t], zt, apex, 0, 2 * LOF_STEP) < 0:
			var face := FM.atan2_a(sim.u_cy[t] - y, sim.u_cx[t] - x)
			_move(sim, u, x, y, face, _width(sim, u), 0, 6)
			return true
	return false


# --------------------------------------------------------------- woods ---

## Sum of tree densities along a line, sampled every 8 m.
static func _woods_cost(sim, x0: int, y0: int, x1: int, y1: int) -> int:
	var d := _d(x1 - x0, y1 - y0)
	var n := d / (8 * M)
	var c := 0
	for k in range(1, n + 1):
		c += sim.veg_d(x0 + (x1 - x0) * k / (n + 1), y0 + (y1 - y0) * k / (n + 1))
	return c


## The nearest spot to (px, py) without trees: the spot itself, else up to
## 30 m aside or 10-20 m back (fixed order), else the spot.
static func _clear_spot(sim, px: int, py: int, rx: int, ry: int, fx: int, fy: int) -> Vector2i:
	if sim.veg_d(px, py) == 0:
		return Vector2i(px, py)
	for c in [Vector2i(-10, 0), Vector2i(10, 0), Vector2i(0, 10), Vector2i(-20, 0), Vector2i(20, 0),
			Vector2i(-10, 10), Vector2i(10, 10), Vector2i(-30, 0), Vector2i(30, 0), Vector2i(0, 20)]:
		var x := clampi(px + (rx * c.x - fx * c.y) * M / FM.TRIG_ONE, 4 * M, sim.field_w - 4 * M)
		var y := clampi(py + (ry * c.x - fy * c.y) * M / FM.TRIG_ONE, 4 * M, sim.field_h - 4 * M)
		if sim.veg_d(x, y) == 0:
			return Vector2i(x, y)
	return Vector2i(px, py)


## Missile unit u with enemy cavalry within 70 m and no woods of its own:
## step into medium or dense woods within 40 m (8 directions, 20 / 40 m),
## the spot furthest from the riders. Returns true if it was ordered to move.
static func _shelter(sim, u: int) -> bool:
	if sim.veg_d(sim.u_cx[u], sim.u_cy[u]) >= 2 or sim.u_order[u] == O_MOVE:
		return false
	var cav := _nearest(sim, u, UT.CLS_CAV, AP.of(sim, sim.u_side[u])[AP.SHELTER_CAV_R])
	if cav < 0:
		return false
	var best := Vector2i(-1, -1)
	var best_d := 0
	for r in [20, 40]:
		for k in 8:
			var a: int = k * 128
			var x := clampi(sim.u_cx[u] + FM.cos_a(a) * r * M / FM.TRIG_ONE, 4 * M, sim.field_w - 4 * M)
			var y := clampi(sim.u_cy[u] + FM.sin_a(a) * r * M / FM.TRIG_ONE, 4 * M, sim.field_h - 4 * M)
			if sim.veg_d(x, y) < 2:
				continue
			var dc := _d(x - sim.u_cx[cav], y - sim.u_cy[cav])
			if best.x < 0 or dc > best_d:
				best = Vector2i(x, y)
				best_d = dc
		if best.x >= 0:
			break
	if best.x < 0:
		return false
	var face := FM.atan2_a(sim.u_cy[cav] - best.y, sim.u_cx[cav] - best.x)
	_move(sim, u, best.x, best.y, face, _width(sim, u), 1, 7)
	sim.stat_ai[15] += 1
	return true


# ------------------------------------------------------ Skilled (step 3) ---
# Behaviours only a profile with the SK_* knobs on runs (docs/AI.md 11).
# Their memory is BattleSim.ai_mem (MU_* per unit, SD_* per side), hashed
# and snapshotted with the sim; it exists only when a side's profile has
# SK_MEM. Every decision reads what a player sees (positions, facings,
# men, morale and ammunition shown on the unit cards, what is fighting);
# every action is an order a player could give.

static func _mem(sim, u: int, k: int) -> int:
	return sim.ai_mem[u * AP.MU_K + k]


static func _mset(sim, u: int, k: int, v: int) -> void:
	sim.ai_mem[u * AP.MU_K + k] = v


static func _sd(sim, side: int, k: int) -> int:
	return sim.ai_mem[sim.n_units * AP.MU_K + side * AP.SD_K + k]


static func _sdset(sim, side: int, k: int, v: int) -> void:
	sim.ai_mem[sim.n_units * AP.MU_K + side * AP.SD_K + k] = v


## Deployment: SK_RESERVE foot units (light ones first, they are quick to
## a flank; then the least solid) are held behind the centre (MU_X 1), and
## with two or more riders one cavalry unit is the reserve (MU_X 3) that
## only counter-charges until the enemy wavers. Small armies keep all.
static func _sk_pick_reserves(sim, side: int, kn: PackedInt32Array) -> void:
	var foot: Array = []
	var cav: Array = []
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY:
			continue
		if _is_foot(sim, u):
			foot.append(u)
		elif sim.u_cls[u] == UT.CLS_CAV:
			cav.append(u)
	var want := kn[AP.SK_RESERVE]
	if foot.size() >= 4 + want:
		foot.sort_custom(func(a: int, b: int) -> bool:
			var ka := _resv_key(sim, a)
			var kb := _resv_key(sim, b)
			return ka < kb or (ka == kb and a > b))
		for k in want:
			_mset(sim, foot[k], AP.MU_X, 1)
	if kn[AP.SK_CAV_RESERVE] > 0 and cav.size() >= 2:
		for k in mini(kn[AP.SK_CAV_RESERVE], cav.size()):
			_mset(sim, cav[cav.size() - 1 - k], AP.MU_X, 3)


static func _resv_key(sim, u: int) -> int:
	var b := UT.base_of(sim.u_type[u])
	if b == UT.LIGHT:
		return 0
	if sim.u_cls[u] == UT.CLS_PIKE:
		return 9  # a pike block is a line unit, never the reserve
	return _solidity(sim.u_type[u])


static func _sk_reserve_slot(sim, u: int, deploy: bool, _kn: PackedInt32Array) -> bool:
	return _mem(sim, u, AP.MU_X) == 1 and _is_foot(sim, u) and (deploy or sim.u_ai[u] == A_RESV)


## Deployment mirrors the enemy's threats: with the enemy's riders massed
## toward one end of our line, the spears take that end.
static func _sk_mirror(sim, side: int, line1: Array, slots: Dictionary, cx: int, cy: int, rx: int, ry: int) -> void:
	var bias := 0
	var men := 0
	for o in sim.n_units:
		if sim.u_side[o] != side and sim.u_state[o] == U_READY and sim.u_cls[o] == UT.CLS_CAV:
			bias += ((sim.u_cx[o] - cx) * rx + (sim.u_cy[o] - cy) * ry) / FM.TRIG_ONE / M * sim.u_alive[o]
			men += sim.u_alive[o]
	if absi(bias) <= men * 20:
		return  # (balanced: their riders' mean is within 20 m of our centre)
	var sgn := 1 if bias > 0 else -1
	var spear := -1
	var end := -1
	for u in line1:
		if spear < 0 and UT.stat(sim.u_type[u], "vs_cav") > 0:
			spear = u
		if end < 0 or sgn * int(slots[u][0]) > sgn * int(slots[end][0]):
			end = u
	if spear < 0 or end == spear or sim.u_cls[end] == UT.CLS_PIKE:
		return
	var tmp: Array = slots[spear]
	slots[spear] = slots[end]
	slots[end] = tmp


## Deployment: shift the line up to SK_ANCHOR aside (20 m steps, the
## nearest first) so that one end rests on woods (medium or dense trees
## within 12 m beyond it) while the line itself stands clear; else as is.
static func _sk_anchor(sim, side: int, plan: Dictionary, cx: int, cy: int, kn: PackedInt32Array) -> Vector2i:
	var half := 0
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and _is_foot(sim, u) and _mem(sim, u, AP.MU_X) != 1:
			half += _width(sim, u) + kn[AP.LINE_GAP]
	half = mini(half, kn[AP.MAX_LINE] * 30 * M) / 2
	var fx: int = plan["fx"]
	var fy: int = plan["fy"]
	var rx := -fy
	var ry := fx
	var step := 20 * M
	var n := kn[AP.SK_ANCHOR] / step
	for k in n * 2 + 1:
		var lat := (k + 1) / 2 * step * (1 if k % 2 == 1 else -1)
		var x := cx + rx * lat / FM.TRIG_ONE
		var y := cy + ry * lat / FM.TRIG_ONE
		if x < 50 * M or y < 50 * M or x > sim.field_w - 50 * M or y > sim.field_h - 50 * M:
			continue
		var clear := true
		for j in 5:
			var o := -half + half * j / 2
			if sim.veg_d(x + rx * o / FM.TRIG_ONE, y + ry * o / FM.TRIG_ONE) >= 2:
				clear = false
				break
		if not clear:
			continue
		for sgn in [-1, 1]:
			var o: int = sgn * (half + 12 * M)
			if sim.veg_d(x + rx * o / FM.TRIG_ONE, y + ry * o / FM.TRIG_ONE) >= 2:
				return Vector2i(x, y)
	return Vector2i(cx, cy)


## Army level, every army think from the advance on.
static func _sk_army(sim, side: int, kn: PackedInt32Array, plan: Dictionary) -> void:
	if sim.ai_phase[side] == P_ENGAGE:
		if kn[AP.SK_ASSIGN] != 0:
			_sk_assign(sim, side, kn)
		if kn[AP.SK_RESERVE] > 0 or kn[AP.SK_ROTATE] != 0:
			_sk_reserves(sim, side, kn, plan)
		if kn[AP.SK_WAVER_PULL] > 0:
			_sk_waverers(sim, side, kn)
	if kn[AP.SK_CAV_RESERVE] > 0 and _sd(sim, side, AP.SD_COMMIT) == 0 and _sk_enemy_shaken(sim, side):
		_sdset(sim, side, AP.SD_COMMIT, 1)
		for u in sim.n_units:
			if sim.u_side[u] == side and _mem(sim, u, AP.MU_X) == 3:
				_mset(sim, u, AP.MU_X, 0)
				_count(sim, side, AP.C_RESERVE_COMMIT)


## The enemy wavers: a line unit or rider of theirs has broken, or none of
## our other riders is left to fight.
static func _sk_enemy_shaken(sim, side: int) -> bool:
	var others := 0
	for u in sim.n_units:
		var c: int = sim.u_cls[u]
		if sim.u_side[u] == side:
			if c == UT.CLS_CAV and sim.u_state[u] == U_READY and _mem(sim, u, AP.MU_X) != 3:
				others += 1
			continue
		if (c == UT.CLS_INF or c == UT.CLS_PIKE or c == UT.CLS_CAV) and sim.u_state[u] != U_READY:
			return true
	return others == 0


## Matchup assignment: the army's free foot units (not fighting a ready
## enemy) are given targets by a greedy pass over (unit, target) pairs,
## best score first (ties: lower unit, then lower target), each pick
## raising or lowering the others' scores for that target (a second unit
## on an engaged target is welcome, a third is not). Score: nearness
## (1 per metre), good / bad matchups, a flank or rear on an engaged enemy,
## an enemy near breaking. Candidates: within SK_ASSIGN_REACH % of the
## nearest enemy's distance plus SK_ASSIGN_SLACK. The units' own thinks use
## the assignment (MU_ASSIGN) instead of the nearest enemy.
static func _sk_assign(sim, side: int, kn: PackedInt32Array) -> void:
	var us: Array = []
	var ts: Array = []
	var cnt := {}  # target -> our units on it already
	for u in sim.n_units:
		if sim.u_state[u] != U_READY:
			continue
		if sim.u_side[u] != side:
			ts.append(u)
			continue
		if sim.u_order[u] == O_ATTACK and sim.u_target[u] >= 0 and sim.u_state[sim.u_target[u]] == U_READY \
				and (sim.u_fighting[u] > 0 or not _is_foot(sim, u) or sim.u_ai[u] != A_ATTACK):
			var t: int = sim.u_target[u]
			cnt[t] = int(cnt.get(t, 0)) + 1
			continue
		if _is_foot(sim, u) and sim.u_ai[u] == A_ATTACK:
			us.append(u)
			_mset(sim, u, AP.MU_ASSIGN, 0)
	if us.is_empty() or ts.is_empty():
		return
	var brk := kn[AP.SK_BREAK_MORALE]
	# Static part of every candidate pair's score.
	var pu := PackedInt32Array()
	var pt := PackedInt32Array()
	var ps := PackedInt32Array()
	for u in us:
		var dn := -1
		for t in ts:
			var d := _d(sim.u_cx[t] - sim.u_cx[u], sim.u_cy[t] - sim.u_cy[u])
			if dn < 0 or d < dn:
				dn = d
		var reach := dn * kn[AP.SK_ASSIGN_REACH] / 100 + kn[AP.SK_ASSIGN_SLACK]
		var spear := UT.stat(sim.u_type[u], "vs_cav") > 0
		var heavy := UT.base_of(sim.u_type[u]) == UT.HEAVY
		for t in ts:
			var d := _d(sim.u_cx[t] - sim.u_cx[u], sim.u_cy[t] - sim.u_cy[u])
			if d > reach:
				continue
			var tc: int = sim.u_cls[t]
			if tc == UT.CLS_CAV and not spear:
				continue  # foot do not chase riders
			var sc := -d / M
			var tb := UT.base_of(sim.u_type[t])
			if tc == UT.CLS_MISSILE or tc == UT.CLS_ART or (heavy and tb == UT.LIGHT) or (spear and tc == UT.CLS_CAV):
				sc += kn[AP.SK_SC_MATCH]
			var engaged: bool = sim.u_fighting[t] > 0
			if sim.u_formed[t] != 0 and sim.u_cls[u] != UT.CLS_PIKE and _frontal(sim, t, u) and not engaged:
				sc -= 2 * kn[AP.SK_SC_BAD]  # a formed pike front
			elif heavy and tb == UT.HEAVY and not engaged:
				sc -= kn[AP.SK_SC_BAD]  # heavy on heavy without a flank
			if engaged and not _frontal(sim, t, u):
				sc += kn[AP.SK_SC_FLANK]
			if sim.u_order[u] == O_ATTACK and sim.u_target[u] == t:
				sc += kn[AP.SK_SC_STICK]
			var mo: int = sim.u_morale[t]
			if mo < brk:
				sc += (brk - mo) / 10 * kn[AP.SK_SC_MORALE]
			if sim.ter_on != 0:
				var g: int = sim.grade_between(sim.u_h[u], sim.u_h[t], maxi(d, M))
				if g > 0:
					sc -= g * 100 / FM.TRIG_ONE * kn[AP.SK_SC_UPHILL]
			pu.append(u)
			pt.append(t)
			ps.append(sc)
	var done := {}
	var left := us.size()
	while left > 0:
		var bi := -1
		var bs := 0
		for i in pu.size():
			var u := pu[i]
			if done.has(u):
				continue
			var t := pt[i]
			var c := int(cnt.get(t, 0))
			var sc := ps[i]
			if c == 0:
				sc += kn[AP.SK_SC_COVER]
			elif c == 1:
				sc += kn[AP.SK_SC_PAIR]
			else:
				sc -= kn[AP.SK_SC_PAIR] * c
			if bi < 0 or sc > bs:
				bi = i
				bs = sc
		if bi < 0:
			break
		var bu := pu[bi]
		var bt := pt[bi]
		done[bu] = true
		left -= 1
		cnt[bt] = int(cnt.get(bt, 0)) + 1
		_mset(sim, bu, AP.MU_ASSIGN, bt + 1)


## Reserves and rotation (army level, lines engaged).
static func _sk_reserves(sim, side: int, kn: PackedInt32Array, plan: Dictionary) -> void:
	var tick: int = sim.tick
	# Tired units being relieved: out once the relief has fought ROT_DELAY,
	# and only with no enemy riders near the way back.
	for f in sim.n_units:
		if sim.u_side[f] != side or sim.u_state[f] != U_READY or _mem(sim, f, AP.MU_A0) <= 0 or sim.u_cls[f] == UT.CLS_CAV:
			continue
		var r := _mem(sim, f, AP.MU_A0) - 1
		if sim.u_state[r] != U_READY or sim.u_order[r] != O_ATTACK:
			_mset(sim, f, AP.MU_A0, 0)
			_mset(sim, f, AP.MU_T0, 0)
			continue
		if sim.u_fighting[r] > 0 and _mem(sim, f, AP.MU_T0) == 0:
			_mset(sim, f, AP.MU_T0, tick)
		var t0 := _mem(sim, f, AP.MU_T0)
		if t0 > 0 and tick - t0 >= kn[AP.SK_ROT_DELAY] and _sk_safe(sim, f, kn):
			_retire(sim, f)
			_mset(sim, f, AP.MU_X, 2)
			_mset(sim, f, AP.MU_A0, 0)
			_mset(sim, f, AP.MU_T0, 0)
	var rk := 0
	for r in sim.n_units:
		if sim.u_side[r] != side or sim.u_state[r] != U_READY or sim.u_ai[r] != A_RESV:
			continue
		if sim.u_fighting[r] > 0:
			continue
		# Relieve the most tired unit of the line.
		if kn[AP.SK_ROTATE] != 0:
			var f := _sk_tired(sim, side, kn)
			if f >= 0:
				var e: int = sim.u_target[f]
				_attack(sim, r, e, 1)
				_set_mode(sim, r, A_ATTACK)
				_mset(sim, r, AP.MU_X, 0)
				_mset(sim, f, AP.MU_A0, r + 1)
				_mset(sim, f, AP.MU_T0, 0)
				_count(sim, side, AP.C_ROTATION)
				_count(sim, side, AP.C_RESERVE_COMMIT)
				continue
		# The hammer: an enemy engaged with ours and near breaking.
		var h := _sk_hammer_target(sim, r, kn)
		if h >= 0:
			if _frontal(sim, h, r) and sim.u_fighting[h] > 0:
				_flank(sim, r, h)
			else:
				_attack(sim, r, h, 1)
				_set_mode(sim, r, A_ATTACK)
			_mset(sim, r, AP.MU_X, 0)
			_count(sim, side, AP.C_RESERVE_COMMIT)
			continue
		# Keep station behind the centre of the line.
		if sim.u_order[r] != O_ATTACK and not plan.is_empty():
			var fx: int = plan["fx"]
			var fy: int = plan["fy"]
			var back := kn[AP.SK_RESERVE_BACK]
			var lat := rk * (_width(sim, r) + kn[AP.LINE_GAP]) * (1 if rk % 2 == 0 else -1)
			var px := clampi(plan["cx"] - fx * back / FM.TRIG_ONE - fy * lat / FM.TRIG_ONE, 4 * M, sim.field_w - 4 * M)
			var py := clampi(plan["cy"] - fy * back / FM.TRIG_ONE + fx * lat / FM.TRIG_ONE, 4 * M, sim.field_h - 4 * M)
			if _d(px - sim.u_ax[r], py - sim.u_ay[r]) > 20 * M:
				_move(sim, r, px, py, plan["face"], _width(sim, r), 0, 2)
		rk += 1


## The most tired unit of the line (fighting a ready enemy, morale under
## SK_ROT_MORALE_PCT % of its type's), not yet being relieved; -1 none.
static func _sk_tired(sim, side: int, kn: PackedInt32Array) -> int:
	var best := -1
	var best_r := 0
	for f in sim.n_units:
		if sim.u_side[f] != side or sim.u_state[f] != U_READY or not _is_foot(sim, f):
			continue
		if sim.u_fighting[f] == 0 or sim.u_order[f] != O_ATTACK or _mem(sim, f, AP.MU_A0) > 0:
			continue
		var e: int = sim.u_target[f]
		if e < 0 or sim.u_state[e] != U_READY:
			continue
		var base := UT.stat(sim.u_type[f], "morale")
		var ratio: int = sim.u_morale[f] * 100 / maxi(base, 1)
		if ratio >= kn[AP.SK_ROT_MORALE_PCT]:
			continue
		if best < 0 or ratio < best_r:
			best = f
			best_r = ratio
	return best


## An enemy unit engaged with ours, near breaking, within 80 m of r; -1 none.
static func _sk_hammer_target(sim, r: int, kn: PackedInt32Array) -> int:
	var best := -1
	var best_m := 0
	var reach := 80 * M
	for e in sim.n_units:
		if sim.u_side[e] == sim.u_side[r] or sim.u_state[e] != U_READY or sim.u_fighting[e] == 0:
			continue
		if sim.u_cls[e] == UT.CLS_CAV or sim.u_morale[e] >= kn[AP.SK_BREAK_MORALE]:
			continue
		if _bbox_gap(sim, r, e) > reach:
			continue
		if best < 0 or sim.u_morale[e] < best_m:
			best = e
			best_m = sim.u_morale[e]
	return best


## No enemy riders (ready, not fighting) within SK_ROT_SAFE_R of unit f.
static func _sk_safe(sim, f: int, kn: PackedInt32Array) -> bool:
	return _sk_free_cav_near(sim, f, sim.u_cx[f], sim.u_cy[f], kn[AP.SK_ROT_SAFE_R]) < 0


## Nearest ready enemy rider not in a melee within r of (x, y); -1 none.
static func _sk_free_cav_near(sim, u: int, x: int, y: int, r: int) -> int:
	var best := -1
	var best_d := r
	for o in sim.n_units:
		if sim.u_side[o] == sim.u_side[u] or sim.u_state[o] != U_READY or sim.u_cls[o] != UT.CLS_CAV \
				or sim.u_fighting[o] > 0:
			continue
		var d := _d(sim.u_cx[o] - x, sim.u_cy[o] - y)
		if d < best_d:
			best = o
			best_d = d
	return best


## Reserve foot: fight what comes within HOLD_REACT, else hold (the army
## moves it).
static func _resv_think(sim, u: int, kn: PackedInt32Array) -> void:
	var cur: int = sim.u_target[u] if sim.u_order[u] == O_ATTACK else -1
	if cur >= 0 and sim.u_state[cur] == U_READY:
		return
	var t := _nearest_enemy(sim, u, true)
	if t >= 0 and _bbox_gap(sim, u, t) < kn[AP.HOLD_REACT]:
		_attack(sim, u, t, 1)


## Own waverers (morale under SK_WAVER_PULL, not fighting) next to a routing
## friend fall back out of its sight before they catch it.
static func _sk_waverers(sim, side: int, kn: PackedInt32Array) -> void:
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY or sim.u_fighting[u] > 0:
			continue
		var c: int = sim.u_cls[u]
		if c == UT.CLS_CAV or c == UT.CLS_ART or sim.u_morale[u] >= kn[AP.SK_WAVER_PULL]:
			continue
		var m: int = sim.u_ai[u]
		if m == A_RETIRE or m == A_RESV or m == A_GUARD:
			continue
		for o in sim.n_units:
			if o == u or sim.u_side[o] != side or sim.u_state[o] != U_ROUTING:
				continue
			if absi(sim.u_cx[o] - sim.u_cx[u]) < 30 * M and absi(sim.u_cy[o] - sim.u_cy[u]) < 30 * M:
				_retire(sim, u)
				_mset(sim, u, AP.MU_X, 2)
				_count(sim, side, AP.C_WAVER_PULL)
				break


## Cavalry pull-out read: winning the melee (the enemy lost at least
## SK_WIN_PCT % of our losses since contact, and some men).
static func _sk_winning(sim, u: int, t: int, kn: PackedInt32Array) -> bool:
	var own: int = _mem(sim, u, AP.MU_A0) - sim.u_alive[u]
	var theirs: int = _mem(sim, u, AP.MU_T0) - sim.u_alive[t]
	return theirs > 0 and theirs * 100 >= own * kn[AP.SK_WIN_PCT]


## The reserve rider may take this target: riders threatening our flank,
## an engaged enemy near breaking, a router.
static func _sk_reserve_cav_may(sim, u: int, t: int, kn: PackedInt32Array) -> bool:
	if sim.u_state[t] == U_ROUTING:
		return true
	if sim.u_cls[t] == UT.CLS_CAV and _threatens(sim, t, sim.u_side[u]):
		return true
	return sim.u_fighting[t] > 0 and sim.u_morale[t] < kn[AP.SK_BREAK_MORALE]


## Cavalry target score additions: an engaged enemy near breaking (the
## finishing charge), enemy riders caught in a melee (counter-charge), a
## target another of our riders is going for (pairs).
static func _sk_cav_bonus(sim, u: int, t: int, kn: PackedInt32Array) -> int:
	var b := 0
	if sim.u_state[t] == U_READY and sim.u_fighting[t] > 0:
		var brk := kn[AP.SK_BREAK_MORALE]
		if sim.u_morale[t] < brk:
			b += (brk - sim.u_morale[t]) * kn[AP.SK_SC_MORALE]
		if sim.u_cls[t] == UT.CLS_CAV:
			b += kn[AP.SK_CAV_COUNTER]
	if kn[AP.SK_CAV_PAIR] > 0 and sim.u_state[t] == U_ROUTING:
		# Pursuit in pairs (a pair bonus on formed targets drew both riders
		# onto one unit and lost more than it won).
		for o in sim.n_units:
			if o == u or sim.u_side[o] != sim.u_side[u] or sim.u_state[o] != U_READY or sim.u_cls[o] != UT.CLS_CAV:
				continue
			if (sim.u_ai[o] == A_STAGE and sim.u_ai_y[o] == t) \
					or (sim.u_ai[o] == A_CHARGE and sim.u_order[o] == O_ATTACK and sim.u_target[o] == t):
				b += kn[AP.SK_CAV_PAIR]
				break
	return b


## A staged rider waits (up to SK_PAIR_WAIT after arriving) for a partner
## still riding to stage on the same target, so both hit together.
static func _sk_wait_partner(sim, u: int, t: int, kn: PackedInt32Array) -> bool:
	if sim.u_order[u] == O_MOVE:
		return false
	if sim.u_ai_x[u] == 0:
		sim.u_ai_x[u] = sim.tick
	if sim.tick - sim.u_ai_x[u] >= kn[AP.SK_PAIR_WAIT] or kn[AP.SK_PAIR_WAIT] <= 0:
		return false
	for o in sim.n_units:
		if o != u and sim.u_side[o] == sim.u_side[u] and sim.u_state[o] == U_READY and sim.u_ai[o] == A_STAGE \
				and sim.u_ai_y[o] == t and sim.u_order[o] == O_MOVE:
			return true
	return false


static func _sk_count_double(sim, u: int, t: int) -> void:
	for o in sim.n_units:
		if o != u and sim.u_side[o] == sim.u_side[u] and sim.u_state[o] == U_READY and sim.u_ai[o] == A_CHARGE \
				and sim.u_order[o] == O_ATTACK and sim.u_target[o] == t and sim.tick - sim.u_ai_t[o] <= 20:
			_count(sim, sim.u_side[u], AP.C_DOUBLE)
			return


## Battery guard: with the lines engaged and no enemy riders free within
## SK_GUARD_CAV_R of the battery, the guard joins the fight (remembering
## its battery, MU_X 4 + b). Returns true if it was released.
static func _sk_release_guard(sim, g: int, b: int) -> bool:
	var side: int = sim.u_side[g]
	if sim.ai_phase[side] != P_ENGAGE or sim.u_fighting[g] > 0:
		return false
	var kn := AP.of(sim, side)
	if _sk_free_cav_near(sim, g, sim.u_cx[b], sim.u_cy[b], kn[AP.SK_GUARD_CAV_R]) >= 0:
		return false
	_set_mode(sim, g, A_ATTACK)
	_mset(sim, g, AP.MU_X, 4 + b)
	_count(sim, side, AP.C_GUARD_FREE)
	return true


## A released guard goes back to its battery when free enemy riders come
## within two thirds of SK_GUARD_CAV_R of it. Returns true if it did.
static func _sk_reguard(sim, u: int, kn: PackedInt32Array) -> bool:
	var b := _mem(sim, u, AP.MU_X) - 4
	if sim.u_state[b] != U_READY or sim.u_ammo[b] <= 0:
		_mset(sim, u, AP.MU_X, 0)
		return false
	if sim.u_fighting[u] > 0:
		return false
	if _sk_free_cav_near(sim, u, sim.u_cx[b], sim.u_cy[b], kn[AP.SK_GUARD_CAV_R] * 2 / 3) < 0:
		return false
	_set_mode(sim, u, A_GUARD)
	sim.u_ai_y[u] = b
	_mset(sim, u, AP.MU_X, 0)
	_guard_post(sim, u, b)
	return true


## Archers go back behind the line before contact: enemy foot within
## SK_MIS_EARLY_R during the advance (Average waits for the lines to meet).
static func _sk_mis_early(sim, u: int, kn: PackedInt32Array) -> bool:
	if UT.stat(sim.u_type[u], "m_arc") == 0:
		return false
	var near := false
	for o in sim.n_units:
		if sim.u_side[o] != sim.u_side[u] and sim.u_state[o] == U_READY and _is_foot(sim, o) \
				and _bbox_gap(sim, u, o) < kn[AP.SK_MIS_EARLY_R]:
			near = true
			break
	if not near:
		return false
	var plan := _plan(sim, sim.u_side[u])
	if plan.is_empty():
		return false
	var fx: int = plan["fx"]
	var fy: int = plan["fy"]
	var ahead: int = (((sim.u_ax[u] - plan["cx"]) * fx + (sim.u_ay[u] - plan["cy"]) * fy) / FM.TRIG_ONE)
	if ahead > -kn[AP.MIS_BEHIND]:
		var back: int = ahead + kn[AP.MIS_FALLBACK]
		var px: int = clampi(sim.u_ax[u] - (fx * back / FM.TRIG_ONE), 4 * M, sim.field_w - 4 * M)
		var py: int = clampi(sim.u_ay[u] - (fy * back / FM.TRIG_ONE), 4 * M, sim.field_h - 4 * M)
		_move(sim, u, px, py, plan["face"], _width(sim, u), 0, 0)
	_set_mode(sim, u, A_ATTACK)
	return false


## Focus fire: one target for the army's missile troops, chosen from the
## enemies in range and not in a melee: enemy missile troops we outrange,
## halted riders, a unit near breaking, a target others already shoot;
## shields facing us count against. With nothing worth an order, back to
## fire at will.
static func _sk_focus(sim, u: int, kn: PackedInt32Array) -> void:
	if sim.u_ammo[u] <= 0 or sim.u_fighting[u] > 0:
		return
	var order: int = sim.u_order[u]
	if order == O_MOVE or order == O_WITHDRAW:
		return
	var ty: int = sim.u_type[u]
	var rng := UT.stat(ty, "m_range")
	var flat := UT.stat(ty, "m_arc") == 0
	var brk := kn[AP.SK_BREAK_MORALE]
	var best := -1
	var bs := 0
	for o in sim.n_units:
		if sim.u_side[o] == sim.u_side[u] or sim.u_state[o] != U_READY or sim.u_fighting[o] > 0 or sim.u_alive[o] <= 0:
			continue
		if not sim._in_range(u, o, rng):
			continue
		var sc: int = 1000 - sim._unit_dist(u, o) / M * 2
		var oc: int = sim.u_cls[o]
		if oc == UT.CLS_MISSILE:
			if UT.stat(sim.u_type[o], "m_range") < rng:
				sc += 500
		elif oc == UT.CLS_CAV:
			sc += 400 if sim.u_moved[o] == 0 else -300
		if _frontal(sim, o, u):
			sc -= UT.stat(sim.u_type[o], "mshield") * 6
		if sim.u_morale[o] < brk:
			sc += (brk - sim.u_morale[o]) * 2
		for f in sim.n_units:
			if f != u and sim.u_side[f] == sim.u_side[u] and sim.u_cls[f] == UT.CLS_MISSILE \
					and sim.u_order[f] == O_ATTACK and sim.u_target[f] == o:
				sc += 250
		if best >= 0 and sc <= bs:
			continue
		if flat and not sim._clear_line(u, o):
			continue
		if sim.ter_on != 0 and not sim.lof_units(u, o):
			continue
		best = o
		bs = sc
	if best >= 0 and kn[AP.SK_AMMO_KEEP_PCT] > 0 and sim.u_cls[best] != UT.CLS_CAV \
			and sim.u_ammo[u] * 100 < sim.u_count0[u] * UT.stat(ty, "m_ammo") * kn[AP.SK_AMMO_KEEP_PCT]:
		best = -1  # the last of the missiles are kept for routers and riders
		var r := _nearest_routing(sim, u, rng)
		if r >= 0:
			best = r
		elif sim.u_fire[u] != 0:
			_order(sim, u, {"type": ORDER_FIRE, "on": 0}, 21)
	if best < 0:
		if order == O_ATTACK:
			_order(sim, u, {"type": ORDER_HALT}, 22)
		return
	if order != O_ATTACK or sim.u_target[u] != best:
		_attack(sim, u, best, 0)
		_count(sim, sim.u_side[u], AP.C_FOCUS)


## Battery crews pull back when an enemy melee unit (foot or riders, not
## fighting) is within REFILL_SAFE of the battery, or riders within twice
## that, and no melee friend of ours is near it (it packs up and falls
## back behind the line; it comes back like a mauled unit). Judged from
## positions only, never from the enemy's orders. Returns true if so.
static func _sk_art_pull(sim, u: int, kn: PackedInt32Array) -> bool:
	if sim.u_fighting[u] > 0 or _protected(sim, u, sim.u_side[u]):
		return false
	var near := false
	for o in sim.n_units:
		if sim.u_side[o] == sim.u_side[u] or sim.u_state[o] != U_READY or sim.u_fighting[o] > 0:
			continue
		var c: int = sim.u_cls[o]
		if c == UT.CLS_MISSILE or c == UT.CLS_ART:
			continue
		var r := kn[AP.REFILL_SAFE] * (2 if c == UT.CLS_CAV else 1)
		if _bbox_gap(sim, u, o) < r:
			near = true
			break
	if not near:
		return false
	_retire(sim, u)
	_count(sim, sim.u_side[u], AP.C_ART_PULL)
	return true


## Spears read where enemy riders are going: the nearest ready rider that
## is within r of the spears now or will be in `lead` ticks at its current
## pace along its facing; -1 none.
static func _sk_cav_lead(sim, u: int, r: int, lead: int) -> int:
	var best := -1
	var best_d := r * r
	for o in sim.n_units:
		if sim.u_side[o] == sim.u_side[u] or sim.u_state[o] != U_READY or sim.u_cls[o] != UT.CLS_CAV:
			continue
		var step: int = sim.u_moved[o] * lead
		var px: int = sim.u_cx[o] + FM.cos_a(sim.u_face[o]) * step / FM.TRIG_ONE
		var py: int = sim.u_cy[o] + FM.sin_a(sim.u_face[o]) * step / FM.TRIG_ONE
		var d := mini(_dist2(sim, u, o), (px - sim.u_cx[u]) * (px - sim.u_cx[u]) + (py - sim.u_cy[u]) * (py - sim.u_cy[u]))
		if d < best_d:
			best = o
			best_d = d
	return best


## Withdrawal in good order: the foot and the batteries go first, the
## cavalry and missile troops keep covering for SK_WD_COVER, then they go.
static func _wd_cover_start(sim, side: int) -> void:
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY:
			continue
		var c: int = sim.u_cls[u]
		if c != UT.CLS_CAV and c != UT.CLS_MISSILE:
			_order(sim, u, {"type": ORDER_WITHDRAW}, 24)
	sim.ai_phase[side] = P_WITHDRAW
	sim.ai_t[side] = sim.tick
	sim.stat_ai[8] += 1
	_sdset(sim, side, AP.SD_WD, sim.tick + 1)


static func _wd_cover_end(sim, side: int) -> void:
	var t0 := _sd(sim, side, AP.SD_WD)
	if t0 <= 0 or sim.tick - (t0 - 1) < AP.of(sim, side)[AP.SK_WD_COVER]:
		return
	_sdset(sim, side, AP.SD_WD, 0)
	sim.queue_order({"tick": sim.tick, "type": ORDER_WITHDRAW_ALL, "side": side,
		"player": AI_PLAYER_BASE + side, "seq": 9000})


# ------------------------------------------------------------- helpers ---

## Deliberate mistake m (AP.M_*) of side `side` at a decision point: rolled
## with the sim's RNG at the profile's chance (MK_BASE + m, %), unless the
## side made it within MK_COOLDOWN. A level whose chance is 0 never rolls
## (no RNG draw: Average plays exactly as before). Counted in stat_aic.
static func _mistake(sim, side: int, m: int, kn: PackedInt32Array) -> bool:
	var p := kn[AP.MK_BASE + m]
	if p <= 0:
		return false
	var i := side * AP.N_MISTAKES + m
	if sim.tick < sim.ai_mist[i]:
		return false
	if int(sim._rand()) % 100 >= p:
		return false
	sim.ai_mist[i] = sim.tick + kn[AP.MK_COOLDOWN]
	_count(sim, side, AP.C_MISTAKE + m)
	return true


## As _mistake, for a mistake a side gets one chance at per battle: the
## first roll uses it up, made or not.
static func _mistake_once(sim, side: int, m: int, kn: PackedInt32Array) -> bool:
	if kn[AP.MK_BASE + m] <= 0:
		return false
	var i := side * AP.N_MISTAKES + m
	if sim.ai_mist[i] != 0:
		return false
	var made: bool = int(sim._rand()) % 100 < kn[AP.MK_BASE + m]
	sim.ai_mist[i] = 0x7FFFFFFF
	if made:
		_count(sim, side, AP.C_MISTAKE + m)
	return made


## A pct % chance with the sim's RNG (100 or more: always, without a draw).
static func _chance(sim, pct: int) -> bool:
	if pct >= 100:
		return true
	if pct <= 0:
		return false
	return int(sim._rand()) % 100 < pct


## The whole army withdraws (ORDER_WITHDRAW_ALL; phase P_WITHDRAW).
static func withdraw_all(sim, side: int, seq: int) -> void:
	sim.queue_order({"tick": sim.tick, "type": ORDER_WITHDRAW_ALL, "side": side,
		"player": AI_PLAYER_BASE + side, "seq": seq})
	sim.ai_phase[side] = P_WITHDRAW
	sim.ai_t[side] = sim.tick
	sim.stat_ai[8] += 1


## Per-competency diagnostic counter (BattleSim.stat_aic; never read back).
static func _count(sim, side: int, c: int, n: int = 1) -> void:
	sim.stat_aic[side * AP.N_COUNTERS + c] += n


## Diagnostics for the spear response counter: the tick enemy cavalry first
## came within r of spear unit u (dbg_cav_seen, -1 none near). Never read by
## any decision.
static func _watch_cav(sim, u: int, r: int) -> void:
	if sim.dbg_cav_seen.size() <= u:
		return
	if _nearest(sim, u, UT.CLS_CAV, r) >= 0:
		if sim.dbg_cav_seen[u] < 0:
			sim.dbg_cav_seen[u] = sim.tick
	else:
		sim.dbg_cav_seen[u] = -1


# ---------------------------------------------------------------- resupply ---
# docs/AI.md 18. The wagon keeps WG_BACK behind the army's centre (or goes
# to a battery out of shots), draws back from enemies within WG_FLEE and
# calls the nearest free melee unit on enemies within WG_THREAT; missile
# units below WG_EMPTY_PCT of their load go to a wagon of ours within
# WG_RANGE that has their kind and refill; an empty missile unit in woods
# with none forages (FORAGE_AI).

## Wagon unit u (its crew) thinks.
static func wagon_think(sim, u: int, kn: PackedInt32Array) -> void:
	var side: int = sim.u_side[u]
	var q: int = sim.u_carry[u]
	if q < 0 or sim.q_kind[q] != EQ_WAGON:
		# Without its wagon: take up the nearest one standing within reach.
		if sim.u_pick[u] >= 0:
			return
		var best := -1
		var bd := 0
		for q2 in sim.n_eq:
			if sim.q_kind[q2] != EQ_WAGON or sim.q_state[q2] != Q_GROUND:
				continue
			var d := _d(sim.q_x[q2] - sim.u_cx[u], sim.q_y[q2] - sim.u_cy[u])
			if d <= WAGON_TAKE_R and (best < 0 or d < bd) and sim.pickup_refusal(sim, u, q2) == "":
				best = q2
				bd = d
		if best >= 0:
			_order(sim, u, {"type": ORDER_PICKUP, "equip": best, "run": 0}, 25)
		return
	var qx: int = sim.q_x[q]
	var qy: int = sim.q_y[q]
	var thr := -1
	var td := 0
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] != U_READY:
			continue
		var c: int = sim.u_cls[o]
		if c == UT.CLS_MISSILE or c == UT.CLS_ART:
			continue
		var d := _d(sim.u_cx[o] - qx, sim.u_cy[o] - qy)
		if thr < 0 or d < td:
			thr = o
			td = d
	if thr >= 0 and kn[AP.WG_THREAT] > 0 and td <= kn[AP.WG_THREAT]:
		_wagon_guard(sim, u, thr)
	var back_dir := 1 if side == 0 else -1  # toward its own edge
	var face := 768 if side == 0 else 256
	if thr >= 0 and td <= kn[AP.WG_FLEE]:
		var ny: int = clampi(sim.u_ay[u] + back_dir * 30 * M, 6 * M, sim.field_h - 6 * M)
		_move(sim, u, sim.u_ax[u], ny, face, _width(sim, u), 0, 2)
		return
	# A battery of ours out of shots with an empty baggage: to it.
	var bat := -1
	var bbd := 0
	if kn[AP.WG_EMPTY_PCT] > 0:
		for b in sim.n_units:
			if sim.u_side[b] != side or sim.u_state[b] != U_READY or sim.u_neng[b] <= 0 \
					or UT.stat(sim.u_type[b], "fixed") != 0 or sim.u_reserve[b] > 0:
				continue
			var full: int = sim.u_neng[b] * UT.stat(sim.u_type[b], "m_ammo")
			if sim.u_ammo[b] * 100 >= full * kn[AP.WG_EMPTY_PCT]:
				continue
			var d := _d(sim.u_cx[b] - qx, sim.u_cy[b] - qy)
			if d <= kn[AP.WG_RANGE] and (bat < 0 or d < bbd):
				bat = b
				bbd = d
	if bat >= 0:
		var bx: int = sim.u_cx[bat]
		var by: int = clampi(sim.u_cy[bat] + back_dir * 8 * M, 6 * M, sim.field_h - 6 * M)
		if _d(bx - sim.u_ax[u], by - sim.u_ay[u]) > 6 * M:
			_move(sim, u, bx, by, face, _width(sim, u), 0, 2)
		return
	# Behind the army's centre.
	var plan := _plan(sim, side)
	if plan.is_empty():
		return
	var fx: int = plan["fx"]
	var fy: int = plan["fy"]
	var px: int = clampi(plan["cx"] - (fx * kn[AP.WG_BACK] / FM.TRIG_ONE), 6 * M, sim.field_w - 6 * M)
	var py: int = clampi(plan["cy"] - (fy * kn[AP.WG_BACK] / FM.TRIG_ONE), 6 * M, sim.field_h - 6 * M)
	if _d(px - sim.u_ax[u], py - sim.u_ay[u]) > 10 * M:
		_move(sim, u, px, py, plan["face"], _width(sim, u), 0, 2)


## Enemy unit t comes for the wagon of unit w: the nearest free melee unit
## of ours (not fighting, not falling back, not a wagon) within 120 m goes
## for it.
static func _wagon_guard(sim, w: int, t: int) -> void:
	var side: int = sim.u_side[w]
	var best := -1
	var bd := 0
	for f in sim.n_units:
		if sim.u_side[f] != side or sim.u_state[f] != U_READY or f == w or is_wagon(sim, f):
			continue
		var c: int = sim.u_cls[f]
		if c == UT.CLS_MISSILE or c == UT.CLS_ART or sim.u_fighting[f] > 0 or sim.u_ai[f] == A_RETIRE:
			continue
		if sim.u_order[f] == O_ATTACK and sim.u_target[f] == t:
			return  # someone is on it
		var d := _d(sim.u_cx[f] - sim.u_cx[t], sim.u_cy[f] - sim.u_cy[t])
		if d <= 120 * M and (best < 0 or d < bd):
			best = f
			bd = d
	if best >= 0:
		_attack(sim, best, t, 1)


## Missile unit u low on missiles (below WG_EMPTY_PCT of its load): to a
## wagon of ours within WG_RANGE with its kind, then refill there; true
## while it does (it stays refilling until threatened or full).
static func resupply(sim, u: int, kn: PackedInt32Array) -> bool:
	if kn[AP.WG_EMPTY_PCT] <= 0 or sim.n_eq == 0 or sim.u_cls[u] != UT.CLS_MISSILE:
		return false
	if sim.u_fighting[u] > 0 or sim.u_carry[u] >= 0 or sim.u_wall[u] > 0:
		return false
	if sim.u_refill[u] != 0 or sim.u_rprog[u] > 0:
		if _art_threatened(sim, u):
			_order(sim, u, {"type": ORDER_REFILL, "on": 0}, 23)
			return false
		return true
	var ty: int = sim.u_type[u]
	var full: int = sim.u_alive[u] * UT.stat(ty, "m_ammo")
	if full <= 0 or sim.u_ammo[u] * 100 >= full * kn[AP.WG_EMPTY_PCT] or _art_threatened(sim, u):
		return false
	var kstd := UT.stat(ty, "m_ak")
	var side: int = sim.u_side[u]
	var best := -1
	var bd := 0
	for q in sim.n_eq:
		if sim.q_kind[q] != EQ_WAGON or sim.q_state[q] == Q_WRECKED or sim.wagon_stock(q, kstd) <= 0:
			continue
		if sim.q_state[q] == Q_CARRIED and sim.u_side[sim.q_unit[q]] != side:
			continue
		if sim.q_state[q] == Q_GROUND and sim.q_side[q] != side:
			continue  # (an enemy's wagon left standing: not the AI's habit)
		var d := _d(sim.q_x[q] - sim.u_cx[u], sim.q_y[q] - sim.u_cy[u])
		if d <= kn[AP.WG_RANGE] and (best < 0 or d < bd):
			best = q
			bd = d
	if best < 0:
		return false
	if sim.wagon_for(u) == best:
		_order(sim, u, {"type": ORDER_REFILL, "on": 1}, 23)
		return true
	# To the wagon, on its near side.
	var dx: int = sim.u_cx[u] - sim.q_x[best]
	var dy: int = sim.u_cy[u] - sim.q_y[best]
	var dd := maxi(_d(dx, dy), 1)
	var tx: int = clampi(sim.q_x[best] + dx * 6 * M / dd, 4 * M, sim.field_w - 4 * M)
	var tyy: int = clampi(sim.q_y[best] + dy * 6 * M / dd, 4 * M, sim.field_h - 4 * M)
	_move(sim, u, tx, tyy, sim.u_face[u], _width(sim, u), 0, 3)
	return true


## Missile unit u with nothing left, standing in woods, no enemy near:
## it makes missiles there (FORAGE_AI). True if it forages.
static func forage(sim, u: int, kn: PackedInt32Array) -> bool:
	if kn[AP.FORAGE_AI] == 0 or sim.veg_on == 0:
		return false
	if sim.u_forage[u] != 0:
		return true
	if sim.forage_refusal(sim, u) != "" or _art_threatened(sim, u):
		return false
	_order(sim, u, {"type": ORDER_FORAGE, "on": 1}, 28)
	return true


# ------------------------------------------------------ ammunition kinds ---
# docs/AI.md 18. A unit with a special ammunition kind shoots it at the
# targets its fields suit (no per-kind code): a fire kind at wooden things
# and, with any fear or fire, at wavering units; a harder-hitting kind
# (damage or pierce above the standard) at armour and batteries; a bursting
# kind at big units and batteries. Otherwise the standard kind. Knobs AK_*.

## Unit u's choice of ammunition against its target t (default: what it
## shoots at or is told to attack); orders the change if any.
static func ammo_pick(sim, u: int, kn: PackedInt32Array, t: int = -1) -> void:
	var sk: int = sim.spec_kind(u)
	if sk < 0:
		return
	var want := 0
	if kn[AP.AK_USE] != 0:
		if t < 0:
			t = sim.u_target[u] if sim.u_order[u] == O_ATTACK else sim.u_ftarget[u]
		if t < 0 or sim.u_state[t] != U_READY:
			return  # nothing to choose for: keep what it has
		want = 1 if ammo_suits(sim, sk, t, kn) else 0
	if sim.u_akind[u] != want:
		_order(sim, u, {"type": ORDER_AMMO, "on": want}, 27)


## Ammunition kind k suits shooting at unit t (by the kind's fields).
static func ammo_suits(sim, k: int, t: int, kn: PackedInt32Array) -> bool:
	var fire := UT.ammo_stat(k, "fire")
	var art: bool = sim.u_neng[t] > 0
	var carry: bool = sim.sg_on != 0 and sim.u_carry[t] >= 0
	if fire > 0 and kn[AP.AK_FIRE_WOOD] != 0 and (art or carry):
		return true
	var ot: int = sim.u_otype[t]
	if (fire > 0 or UT.ammo_stat(k, "fear") > 0) \
			and sim.u_morale[t] * 100 < UT.stat(ot, "morale") * kn[AP.AK_WAVER_PCT]:
		return true
	if UT.ammo_stat(k, "blast") > 0 and (art or sim.u_alive[t] >= kn[AP.AK_BLAST_MEN]):
		return true
	if (UT.ammo_stat(k, "dmg") > 100 or UT.ammo_stat(k, "pierce") > 100) \
			and (art or UT.stat(ot, "armour") >= kn[AP.AK_ARMOUR]):
		return true
	return false


static func _order(sim, u: int, o: Dictionary, k: int) -> void:
	o["tick"] = sim.tick
	o["unit"] = u
	o["player"] = AI_PLAYER_BASE + sim.u_side[u]
	o["seq"] = u * 32 + k
	sim.queue_order(o)


static func _attack(sim, u: int, t: int, run: int) -> void:
	_order(sim, u, {"type": ORDER_ATTACK, "target": t, "run": run}, 0)


## Move, skipped when the unit is already headed there.
static func _move(sim, u: int, x: int, y: int, face: int, width: int, run: int, k: int) -> void:
	var ox: int = sim.u_dx[u] if sim.u_order[u] == O_MOVE else sim.u_ax[u]
	var oy: int = sim.u_dy[u] if sim.u_order[u] == O_MOVE else sim.u_ay[u]
	var kn := AP.of(sim, sim.u_side[u])
	if _d(x - ox, y - oy) < kn[AP.REPLAN_DIST] / 3 and absi(FM.angle_diff(sim.u_dface[u], face)) < kn[AP.REPLAN_FACE] \
			and sim.u_order[u] != O_ATTACK:
		return
	_order(sim, u, {"type": ORDER_MOVE, "x": x, "y": y, "facing": face, "width": width,
		"run": run}, 1 + k % 8)


static func _d(dx: int, dy: int) -> int:
	return FM.approx_len(dx, dy)


static func _dist2(sim, a: int, b: int) -> int:
	var dx: int = sim.u_cx[b] - sim.u_cx[a]
	var dy: int = sim.u_cy[b] - sim.u_cy[a]
	return dx * dx + dy * dy


static func _nearest_enemy(sim, u: int, ready_only: bool) -> int:
	var best := -1
	var best_d := 0
	var side: int = sim.u_side[u]
	for o in sim.n_units:
		if sim.u_side[o] == side:
			continue
		var s: int = sim.u_state[o]
		if s >= U_DESTROYED or (ready_only and s != U_READY):
			continue
		var d := _dist2(sim, u, o)
		if best < 0 or d < best_d:
			best = o
			best_d = d
	return best


static func _nearest_not(sim, u: int, skip: int) -> int:
	var best := -1
	var best_d := 0
	var side: int = sim.u_side[u]
	for o in sim.n_units:
		if o == skip or sim.u_side[o] == side or sim.u_state[o] != U_READY:
			continue
		if sim.u_formed[o] != 0 and _frontal(sim, o, u):
			continue
		var d := _dist2(sim, u, o)
		if best < 0 or d < best_d:
			best = o
			best_d = d
	return best


static func _nearest(sim, u: int, cls: int, within: int) -> int:
	var best := -1
	var best_d := within * within
	var side: int = sim.u_side[u]
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] != U_READY or sim.u_cls[o] != cls:
			continue
		var d := _dist2(sim, u, o)
		if d < best_d:
			best = o
			best_d = d
	return best


static func _nearest_routing(sim, u: int, within: int) -> int:
	var best := -1
	var best_d := within * within
	var side: int = sim.u_side[u]
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] != U_ROUTING:
			continue
		var d := _dist2(sim, u, o)
		if d < best_d:
			best = o
			best_d = d
	return best
