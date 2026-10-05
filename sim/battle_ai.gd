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

const FM := preload("res://sim/fixed_math.gd")
const UT := preload("res://sim/unit_types.gd")

const M := 1024
const THINK_PERIOD := 10
const CHARGE_RANGE := 35 * M
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
# (stat_ai[12] holds of high ground, [13] slots moved onto a rise,
# [14] deployments shifted to higher ground)

const LINE_GAP := 4 * M
const LINE2_BACK := 35 * M
const MISSILE_AHEAD := 15 * M
const MAX_LINE := 8
const SKIRMISH_HALT := 105 * M   # line halts this far from the enemy line
const ENGAGE_DIST := 60 * M
const SKIRMISH_TICKS := 1100     # from deployment, march included
const REPLAN_DIST := 15 * M
const FLANK_OUT := 14 * M
const CAV_MELEE_TICKS := 50      # pull out after this long in melee
const CAV_PULL_DIST := 45 * M
const UNPROTECTED := 30 * M
const CAV_THREAT := 60 * M
const RETIRE_TICKS := 300        # a retired unit rejoins after 30 s
const ART_BACK := 25 * M         # stone throwers stand this far behind the line
const ART_MOVE := 30 * M         # batteries only move for a gain this big
const GUARD_OUT := 14 * M        # guard post: beside the battery, outward
const GUARD_RANGE := 70 * M      # guard attacks enemies this close to the battery
const SHELLED_TICKS := 60        # "being shelled": hit by artillery this recently
const REFILL_SAFE := 35 * M      # a battery refills with no enemy melee unit this close ...
const REFILL_WATCH := 100 * M    # ... and none this close coming for it
# Terrain.
const HOLD_DH := 4 * M           # hold when the line stands this far above the enemy ...
const HOLD_TICKS := 2400         # ... for at most 4 minutes
const HOLD_REACT := 25 * M       # holding foot attack enemies this close
const DETOUR_GRADE := 614        # 15%: a steeper final approach is avoided ...
const DETOUR_MIN := 35 * M       # ... (its last 35 m) when the target is at least this far
const DETOUR_LONG := 17          # ... by a detour at most 1.7x as long (tenths)
const CREST_GAIN := 1536         # halt on ground 1.5 m higher than the planned halt line
const DEPLOY_SHIFT := 30 * M     # deployment may shift this far ...
const DEPLOY_GAIN := 2 * M       # ... to stand this much higher
const RISE_LAT := 12 * M         # missile / artillery slots look this far aside ...
const RISE_GAIN := 1024          # ... for ground 1 m higher
const LINE_SPAN := 30 * M        # line height: sampled every 30 m across +-60 m


static func think(sim) -> void:
	var tick: int = sim.tick
	# Both armies think on the same tick, from the same state (their orders
	# are applied together after this), so neither side always reacts to
	# the other's last decision.
	if tick % THINK_PERIOD == 0:
		for side in 2:
			if sim.ai_sides[side] != 0:
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
		if (k + tick) % THINK_PERIOD != 0:
			continue
		if sim.ai_phase[side] == P_WITHDRAW or sim.u_order[u] == O_WITHDRAW:
			continue
		_unit_think(sim, u)


# ------------------------------------------------------------ army level ---

static func _army_think(sim, side: int) -> void:
	var phase: int = sim.ai_phase[side]
	if phase == P_WITHDRAW:
		return
	var own := _strength(sim, side)
	var foe := _strength(sim, 1 - side)
	if foe <= 0:
		return
	# Clearly lost: little left that can fight against a strong enemy, or a
	# fifth of the army left and the enemy stronger.
	if sim.tick > 600 and (own * 100 < foe * 30 or (own * 100 < _start_strength(sim, side) * 20 and own < foe)):
		sim.queue_order({"tick": sim.tick, "type": ORDER_WITHDRAW_ALL, "side": side,
			"player": AI_PLAYER_BASE + side, "seq": 9000})
		sim.ai_phase[side] = P_WITHDRAW
		sim.ai_t[side] = sim.tick
		sim.stat_ai[8] += 1
		return
	var plan := _plan(sim, side)
	if plan.is_empty():
		return
	if phase == P_DEPLOY:
		var dcx: int = plan["cx"]
		var dcy: int = plan["cy"]
		if sim.ter_on != 0:
			var spot := _deploy_spot(sim, plan)
			if spot.x != dcx or spot.y != dcy:
				sim.stat_ai[14] += 1
			dcx = spot.x
			dcy = spot.y
		_issue_line(sim, side, plan, dcx, dcy, true)
		sim.ai_phase[side] = P_ADVANCE
		sim.ai_t[side] = sim.tick
		return
	if phase == P_ENGAGE:
		if sim.ai_hold[side] >= 0 and not _keep_holding(sim, side):
			sim.ai_hold[side] = -2  # over for good
		return
	if phase == P_ADVANCE:
		var gap: int = plan["gap"]
		var halt := 0
		# Halt in bow range and shoot unless clearly outshot.
		var mine := _missile_power(sim, side)
		var skirmishing: bool = mine > 0 and mine * 10 >= _missile_power(sim, 1 - side) * 7 \
			and sim.tick - sim.ai_t[side] < SKIRMISH_TICKS and _ammo_left(sim, side)
		# Shelled by artillery stronger than ours: standing still only feeds
		# it, so close the distance instead.
		if skirmishing and _shelled(sim, side) and _art_power(sim, 1 - side) > _art_power(sim, side):
			skirmishing = false
		if skirmishing:
			halt = SKIRMISH_HALT
		if gap < ENGAGE_DIST or (halt == 0 and gap < ENGAGE_DIST + 20 * M):
			sim.ai_phase[side] = P_ENGAGE
			sim.ai_t[side] = sim.tick
			for u in sim.n_units:
				if sim.u_side[u] == side and sim.u_ai[u] == A_LINE and sim.u_cls[u] != UT.CLS_MISSILE:
					sim.u_ai[u] = A_ATTACK
			return
		# Halt line: `halt` short of the enemy front, never backwards.
		var fx: int = plan["fx"]
		var fy: int = plan["fy"]
		var adv := maxi(gap - maxi(halt, ENGAGE_DIST - 10 * M), 0)
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
				adv = _crest_advance(sim, plan, adv, gap, halt)
		var cx: int = plan["cx"] + (fx * adv / FM.TRIG_ONE)
		var cy: int = plan["cy"] + (fy * adv / FM.TRIG_ONE)
		_issue_line(sim, side, plan, cx, cy, false)


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
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY \
				and sim.tick - sim.u_shelled_t[u] < SHELLED_TICKS:
			return true
	return false


static func _ammo_left(sim, side: int) -> bool:
	var have := 0
	var full := 0
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and sim.u_cls[u] == UT.CLS_MISSILE:
			have += sim.u_ammo[u]
			full += sim.u_count0[u] * UT.stat(sim.u_type[u], "m_ammo")
	return full > 0 and have * 4 > full


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


## Line infantry (infantry or pikes).
static func _is_foot(sim, u: int) -> bool:
	return sim.u_cls[u] == UT.CLS_INF or sim.u_cls[u] == UT.CLS_PIKE


static func _bbox_gap(sim, a: int, b: int) -> int:
	var gx := maxi(maxi(sim.u_minx[b] - sim.u_maxx[a], sim.u_minx[a] - sim.u_maxx[b]), 0)
	var gy := maxi(maxi(sim.u_miny[b] - sim.u_maxy[a], sim.u_miny[a] - sim.u_maxy[b]), 0)
	return maxi(gx, gy)


## Line positions: pikes in the centre, other infantry outward, cavalry on
## the wings, missiles in front. Within a role, units keep their left-to-right
## order so the redeployment does not cross over.
static func _issue_line(sim, side: int, plan: Dictionary, cx: int, cy: int, deploy: bool) -> void:
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
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY:
			continue
		if not deploy and sim.u_ai[u] != A_LINE and sim.u_ai[u] != A_HOLD and sim.u_ai[u] != A_ART:
			continue
		var c: int = sim.u_cls[u]
		if c == UT.CLS_PIKE:
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
		if k < MAX_LINE:
			line1.append(order[k])
		else:
			line2.append(order[k])
	var slots := {}  # unit -> [lateral, back]
	var half1 := _place_centre_out(sim, line1, 0, slots)
	_place_centre_out(sim, line2, LINE2_BACK, slots)
	# Bolt throwers at the ends of the first line (a clear, flat field of
	# fire), then cavalry beyond them.
	var lw := half1 + LINE_GAP
	var rw := half1 + LINE_GAP
	for k in bolts.size():
		var u: int = bolts[k]
		var w := _width(sim, u)
		if k % 2 == 0:
			slots[u] = [-(lw + w / 2), 0]
			lw += w + LINE_GAP
		else:
			slots[u] = [rw + w / 2, 0]
			rw += w + LINE_GAP
	lw += 10 * M - LINE_GAP
	rw += 10 * M - LINE_GAP
	# Stone throwers behind the centre (they lob over the line).
	var stotal := 0
	for u in stones:
		stotal += _width(sim, u) + LINE_GAP
	var sxx := -stotal / 2
	for u in stones:
		var w := _width(sim, u)
		slots[u] = [sxx + w / 2, ART_BACK]
		sxx += w + LINE_GAP
	for k in cav.size():
		var u: int = cav[k]
		var w := _width(sim, u)
		if k % 2 == 0:
			slots[u] = [-(lw + w / 2), 0]
			lw += w + LINE_GAP
		else:
			slots[u] = [rw + w / 2, 0]
			rw += w + LINE_GAP
	# Missiles spread in front of the centre.
	var total := 0
	for u in mis:
		total += _width(sim, u) + LINE_GAP
	var x := -total / 2
	for u in mis:
		var w := _width(sim, u)
		slots[u] = [x + w / 2, -MISSILE_AHEAD]
		x += w + LINE_GAP
	# Keep left-to-right order within each role.
	for group in [pikes, inf, cav, mis, bolts, stones]:
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
		# A battery that has targets and friends close by stays put.
		var stay: bool = art and not deploy and (sim.u_refill[u] != 0 or sim.u_rprog[u] > 0 \
			or (_protected(sim, u) and _art_has_target(sim, u)))
		if sim.ter_on != 0 and (sim.u_cls[u] == UT.CLS_MISSILE or art) and not stay:
			var rp := _rise(sim, u, px, py, rx, ry, fx, fy, plan)
			if rp.x != px or rp.y != py:
				sim.stat_ai[13] += 1
			px = rp.x
			py = rp.y
		if art:
			# Batteries only pack up for a worthwhile move: at deployment,
			# and to keep up with the line as it advances.
			var far := 25 * M if deploy else ART_MOVE
			if not stay and _d(px - sim.u_ax[u], py - sim.u_ay[u]) > far and sim.u_ammo[u] > 0:
				_move(sim, u, px, py, face, _width(sim, u), 0, seq)
		else:
			_move(sim, u, px, py, face, _width(sim, u), 0, seq)
		seq += 1
		if sim.u_cls[u] == UT.CLS_MISSILE and sim.u_skirm[u] == 0:
			_order(sim, u, {"type": ORDER_SKIRMISH, "on": 1}, 20)
		if deploy:
			var mode := A_LINE
			if sim.u_cls[u] == UT.CLS_CAV:
				mode = A_HOLD
			elif sim.u_cls[u] == UT.CLS_ART:
				mode = A_ART
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
static func _place_centre_out(sim, units: Array, back: int, slots: Dictionary) -> int:
	if units.is_empty():
		return 0
	var total := 0
	for u in units:
		total += _width(sim, u) + LINE_GAP
	total -= LINE_GAP
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
		x += w + LINE_GAP
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
	# Badly mauled: fall back behind the line once.
	if mode != A_RETIRE and sim.u_alive[u] * 100 < sim.u_count0[u] * 30 and sim.u_morale[u] < 350:
		_retire(sim, u)
		return
	if mode == A_RETIRE:
		# Back in the fight once it has fallen back and had time to recover
		# (or rallied after a rout). Standing idle under artillery fire, it
		# steps out of the battery's arc.
		if sim.u_order[u] == O_NONE and sim.tick - sim.u_shelled_t[u] < SHELLED_TICKS:
			_sidestep(sim, u, sim.u_shelled_by[u])
			return
		if sim.tick - sim.u_ai_t[u] < RETIRE_TICKS or sim.u_order[u] != O_NONE:
			return
		if cls == UT.CLS_ART and sim.u_ammo[u] <= 0:
			# An empty battery stays out of the way, refilling if it can.
			if sim.u_refill[u] == 0 and sim.u_rprog[u] == 0 and _can_refill(sim, u) \
					and not _art_threatened(sim, u):
				_order(sim, u, {"type": ORDER_REFILL, "on": 1}, 23)
			return
		_set_mode(sim, u, A_ATTACK if cls != UT.CLS_CAV else A_HOLD)
		mode = sim.u_ai[u]
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
	var back := 60 * M
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
	var cur := -1
	if sim.u_order[u] == O_ATTACK:
		cur = sim.u_target[u]
	# Engaged with a ready enemy: keep fighting it.
	if cur >= 0 and sim.u_fighting[u] > 0 and sim.u_state[cur] == U_READY:
		return
	if mode == A_DETOUR:
		var dt: int = sim.u_ai_y[u]
		if dt >= 0 and sim.u_state[dt] == U_READY:
			var arrived: bool = sim.u_order[u] != O_MOVE \
				or _d(sim.u_ax[u] - sim.u_dx[u], sim.u_ay[u] - sim.u_dy[u]) < 8 * M
			if not arrived and sim.tick - sim.u_ai_t[u] < 400 and sim.u_contact[u] == 0:
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
			var arrived: bool = sim.u_order[u] != O_MOVE or _d(sim.u_ax[u] - sx, sim.u_ay[u] - sy) < 8 * M
			if not arrived and sim.tick - sim.u_ai_t[u] < 300 and sim.u_formed[t] != 0:
				return
			_attack(sim, u, t, 1)
			_set_mode(sim, u, A_ATTACK)
			return
		_set_mode(sim, u, A_ATTACK)
	var best := -1
	# Spears turn on cavalry close by.
	if UT.stat(sim.u_type[u], "vs_cav") > 0:
		best = _nearest(sim, u, UT.CLS_CAV, 40 * M)
	if best < 0:
		best = _nearest_enemy(sim, u, true)
	if best < 0:
		best = _nearest_enemy(sim, u, false)
	if best < 0:
		return
	# Formed enemy pikes: do not walk into the points if it can be helped.
	if sim.u_formed[best] != 0 and sim.u_cls[u] != UT.CLS_PIKE and _frontal(sim, best, u):
		var pinned := false
		for o in sim.n_units:
			if o != u and sim.u_side[o] == sim.u_side[u] and sim.u_order[o] == O_ATTACK \
					and sim.u_target[o] == best and sim.u_state[o] == U_READY:
				pinned = true
				break
		if pinned:
			_flank(sim, u, best)
			return
		var alt := _nearest_not(sim, u, best)
		if alt >= 0 and _dist2(sim, u, alt) * 4 <= _dist2(sim, u, best) * 9:
			best = alt
	if sim.ter_on != 0:
		# Holding high ground: let the enemy come.
		if sim.ai_hold[sim.u_side[u]] >= 0 and _bbox_gap(sim, u, best) > HOLD_REACT \
				and sim.u_fighting[u] == 0:
			return
		if sim.u_ai_x[u] != best + 1 and sim.u_fighting[u] == 0 and _detour(sim, u, best):
			return
	var run := 1 if _dist2(sim, u, best) < CHARGE_RANGE * CHARGE_RANGE else 0
	if best != cur or run != sim.u_run[u]:
		_attack(sim, u, best, run)
	_set_mode(sim, u, A_ATTACK)


## Send u round to the flank of enemy unit t, then attack.
static func _flank(sim, u: int, t: int) -> void:
	var tf: int = sim.u_face[t]
	var c := FM.cos_a(tf)
	var s := FM.sin_a(tf)
	var hw: int = (mini(sim.u_files[t], sim.u_alive[t]) * UT.stat(sim.u_type[t], "file_sp")) / 2
	var lat: int = (((sim.u_cy[u] - sim.u_ay[t]) * c - (sim.u_cx[u] - sim.u_ax[t]) * s) / FM.TRIG_ONE)
	var sgn := 1 if lat >= 0 else -1
	var out := sgn * (hw + FLANK_OUT)
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
	if mode == A_PULL:
		var arrived: bool = sim.u_order[u] != O_MOVE
		if not arrived and tick - sim.u_ai_t[u] < 100:
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
			elif tick - sim.u_ai_x[u] > CAV_MELEE_TICKS:
				_pull_out(sim, u, t)
			return
		elif _is_braced_front(sim, t, u) and _dist2(sim, u, t) > 20 * M * 20 * M:
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
			if arrived or tick - sim.u_ai_t[u] > 250 or not _is_braced_front(sim, t, u) and not _frontal(sim, t, u):
				_attack(sim, u, t, 1)
				_set_mode(sim, u, A_CHARGE)
			return
	# Under arrows while waiting: ride down the shooters if nobody guards
	# them, otherwise get out of their fire.
	if tick - sim.u_hit_t[u] < 30:
		var shooter := _shooting_at(sim, u)
		if shooter >= 0:
			if not _protected(sim, shooter):
				_attack(sim, u, shooter, 1)
				_set_mode(sim, u, A_CHARGE)
			else:
				_pull_out(sim, u, shooter)
			return
	# Shelled while waiting: ride down the battery if nobody guards it,
	# otherwise get out of its arc.
	if tick - sim.u_shelled_t[u] < 30:
		var bat: int = sim.u_shelled_by[u]
		if bat >= 0 and sim.u_state[bat] == U_READY:
			if not _protected(sim, bat):
				_attack(sim, u, bat, 1)
				_set_mode(sim, u, A_CHARGE)
			else:
				_sidestep(sim, u, bat)
			return
	# Hold: look for a target.
	var pick := _cav_pick(sim, u, phase)
	if pick < 0:
		return
	if _frontal(sim, pick, u) and (UT.stat(sim.u_type[pick], "brace") > 0 or sim.u_fighting[pick] == 0) \
			and sim.u_cls[pick] != UT.CLS_MISSILE and sim.u_cls[pick] != UT.CLS_CAV \
			and sim.u_cls[pick] != UT.CLS_ART and sim.u_state[pick] == U_READY:
		_stage(sim, u, pick)
	else:
		_attack(sim, u, pick, 1)
		_set_mode(sim, u, A_CHARGE)


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
	var out := sgn * (hw + 25 * M)
	var back: int = sim.unit_depth(t) + 20 * M
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
	# Bias toward our own side of the field.
	dy += (40 * M) if sim.u_side[u] == 0 else (-40 * M)
	var d := maxi(_d(dx, dy), 1)
	var px := clampi(sim.u_cx[u] + dx * CAV_PULL_DIST / d, 6 * M, sim.field_w - 6 * M)
	var py := clampi(sim.u_cy[u] + dy * CAV_PULL_DIST / d, 6 * M, sim.field_h - 6 * M)
	var face := FM.atan2_a(sim.u_cy[t] - py, sim.u_cx[t] - px)
	_move(sim, u, px, py, face, _width(sim, u), 1, 0)
	_set_mode(sim, u, A_PULL)


## Best cavalry target: unprotected missile troops, enemy cavalry near our
## flank, then (once the lines meet) engaged enemies, then routers.
static func _cav_pick(sim, u: int, phase: int) -> int:
	var side: int = sim.u_side[u]
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
				score = 1000
		elif cls == UT.CLS_MISSILE and not _protected(sim, t):
			# Best while their arrows go elsewhere; riding in under their
			# fire costs riders, so only from close or as a lesser choice.
			score = 4000 if sim.u_ftarget[t] != u or d < 50 else 2600
		elif cls == UT.CLS_ART and not _protected(sim, t):
			score = 4200  # an unguarded battery: wreck it
		elif cls == UT.CLS_ART and phase == P_ENGAGE:
			score = 2200
		elif cls == UT.CLS_CAV and _threatens(sim, t, side):
			score = 3500
		elif phase == P_ENGAGE and sim.u_fighting[t] > 0:
			score = 3000 if not _is_braced_front(sim, t, u) else 2500
		elif phase == P_ENGAGE and cls == UT.CLS_MISSILE:
			score = 2000
		if score == 0:
			continue
		score -= d * 4
		if sim.ter_on != 0:
			# Charging uphill costs momentum and impact: prefer level or
			# downhill targets (60 points per % of climb).
			var g: int = sim.grade_between(sim.u_h[u], sim.u_h[t], maxi(d, 1) * M)
			if g > 0:
				score -= g * 6000 / FM.TRIG_ONE
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


## Enemy unit t has a ready melee friend close by.
static func _protected(sim, t: int) -> bool:
	for o in sim.n_units:
		if o == t or sim.u_side[o] != sim.u_side[t] or sim.u_state[o] != U_READY:
			continue
		if sim.u_cls[o] == UT.CLS_MISSILE:
			continue
		if _bbox_gap(sim, o, t) < UNPROTECTED:
			return true
	return false


## Enemy cavalry t is close to one of our units that is not cavalry.
static func _threatens(sim, t: int, side: int) -> bool:
	for o in sim.n_units:
		if sim.u_side[o] != side or sim.u_state[o] != U_READY or sim.u_cls[o] == UT.CLS_CAV:
			continue
		if _bbox_gap(sim, o, t) < CAV_THREAT:
			return true
	return false


static func _missile_think(sim, u: int, phase: int) -> void:
	var side: int = sim.u_side[u]
	if sim.u_skirm[u] == 0:
		_order(sim, u, {"type": ORDER_SKIRMISH, "on": 1}, 20)
	if sim.u_ammo[u] <= 0:
		# Out of ammunition: finish off routers nearby, otherwise keep clear.
		var r := _nearest_routing(sim, u, 40 * M)
		if r >= 0:
			if sim.u_order[u] != O_ATTACK or sim.u_target[u] != r:
				_attack(sim, u, r, 1)
		elif sim.u_ai[u] != A_RETIRE and phase == P_ENGAGE:
			_retire(sim, u)
		return
	# Hold fire unless an unengaged enemy is in range.
	var rng := UT.stat(sim.u_type[u], "m_range")
	var clean := false
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] >= U_DESTROYED:
			continue
		if sim.u_fighting[o] == 0 and sim._in_range(u, o, rng):
			clean = true
			break
	var want := 1 if clean else 0
	if sim.u_fire[u] != want:
		_order(sim, u, {"type": ORDER_FIRE, "on": want}, 21)
	# Once the lines meet, archers move behind the line.
	if phase == P_ENGAGE and sim.u_ai[u] == A_LINE and UT.stat(sim.u_type[u], "m_arc") != 0:
		var plan := _plan(sim, side)
		if not plan.is_empty():
			var fx: int = plan["fx"]
			var fy: int = plan["fy"]
			var cx: int = plan["cx"]
			var cy: int = plan["cy"]
			var ahead: int = (((sim.u_ax[u] - cx) * fx + (sim.u_ay[u] - cy) * fy) / FM.TRIG_ONE)
			if ahead > -25 * M:
				var back: int = ahead + 40 * M
				var px: int = clampi(sim.u_ax[u] - (fx * back / FM.TRIG_ONE), 4 * M, sim.field_w - 4 * M)
				var py: int = clampi(sim.u_ay[u] - (fy * back / FM.TRIG_ONE), 4 * M, sim.field_h - 4 * M)
				_move(sim, u, px, py, plan["face"], _width(sim, u), 0, 0)
		_set_mode(sim, u, A_ATTACK)
	elif phase == P_ENGAGE and sim.u_ai[u] == A_LINE:
		_set_mode(sim, u, A_ATTACK)


# ------------------------------------------------------------ artillery ---

## Battery: shoot the best safe target in range; with none in range, move up
## behind the line; out of ammunition or engines, get out of the way.
static func _art_think(sim, u: int, phase: int) -> void:
	var side: int = sim.u_side[u]
	var ty: int = sim.u_type[u]
	# Refilling from the baggage: carry on unless threatened, or three
	# quarters full again with something to shoot.
	var full: int = sim.u_neng[u] * UT.stat(ty, "m_ammo")
	if sim.u_refill[u] != 0:
		if _art_threatened(sim, u) or (sim.u_ammo[u] * 4 >= full * 3 and _art_has_target(sim, u)):
			_order(sim, u, {"type": ORDER_REFILL, "on": 0}, 23)
		return
	if sim.u_rprog[u] > 0:
		return  # still getting out of it
	if sim.u_order[u] != O_MOVE and _can_refill(sim, u) and not _art_threatened(sim, u) \
			and (sim.u_ammo[u] * 4 <= full or (sim.u_ammo[u] * 4 < full * 3 and not _art_has_target(sim, u))):
		_order(sim, u, {"type": ORDER_REFILL, "on": 1}, 23)
		return
	if sim.u_ammo[u] <= 0:
		if sim.u_ai[u] != A_RETIRE:
			_retire(sim, u)
		return
	if sim.u_order[u] == O_MOVE:
		return  # moving up with the line: set up again on arrival
	var rng := UT.stat(ty, "m_range")
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
			score += 900  # silence their batteries
		if bolt and oc == UT.CLS_PIKE:
			score = score * 3 / 2  # deep and dense: bolts go through ranks
		if oc == UT.CLS_CAV:
			score = score / 2  # fast and spread out
		if sim.u_moved[o] == 0:
			score = score * 4 / 3
		elif not bolt:
			score = score / 2  # stones cannot lead a moving target
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
	var back := ART_BACK if not bolt else 0
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
	if _d(px - sim.u_ax[u], py - sim.u_ay[u]) > ART_MOVE:
		_move(sim, u, px, py, plan["face"], _width(sim, u), 0, 0)


## Battery u has an enemy unit within its range band.
static func _art_has_target(sim, u: int) -> bool:
	var ty: int = sim.u_type[u]
	var rng := UT.stat(ty, "m_range")
	var mn := UT.stat(ty, "m_min")
	for o in sim.n_units:
		if sim.u_side[o] != sim.u_side[u] and sim.u_state[o] == U_READY \
				and sim._art_in_range(u, o, mn, rng):
			return true
	return false


## Battery u has shots in its baggage and a working engine short of its
## full load (abandoned or wrecked engines cannot be refilled).
static func _can_refill(sim, u: int) -> bool:
	if sim.u_reserve[u] <= 0:
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
	for o in sim.n_units:
		if sim.u_side[o] == sim.u_side[u] or sim.u_state[o] != U_READY:
			continue
		var c: int = sim.u_cls[o]
		if c == UT.CLS_MISSILE or c == UT.CLS_ART:
			continue
		var g := _bbox_gap(sim, u, o)
		if g < REFILL_SAFE or (g < REFILL_WATCH and sim.u_order[o] == O_ATTACK and sim.u_target[o] == u):
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
		if c != UT.CLS_INF:
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
	if best < 0 or melee < 5:
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
	var out: int = sgn * (sim.unit_half_width(b) + sim.unit_half_width(g) + GUARD_OUT)
	var px: int = sim.u_ax[b] + (rx * out / FM.TRIG_ONE) + (fx * 5 * M / FM.TRIG_ONE)
	var py: int = sim.u_ay[b] + (ry * out / FM.TRIG_ONE) + (fy * 5 * M / FM.TRIG_ONE)
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
	var cur := -1
	if sim.u_order[g] == O_ATTACK:
		cur = sim.u_target[g]
	if cur >= 0 and sim.u_state[cur] == U_READY and sim.u_fighting[g] > 0:
		return
	var threat := -1
	var td := GUARD_RANGE * GUARD_RANGE
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
			_attack(sim, g, threat, 1 if td < CHARGE_RANGE * CHARGE_RANGE else 0)
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
	# Perpendicular to the line of fire, toward our own side of the field.
	var px: int = -dy * 40 * M / d
	var py: int = dx * 40 * M / d
	var own := 1 if sim.u_side[u] == 0 else -1
	if py * own < 0:
		px = -px
		py = -py
	var x := clampi(sim.u_cx[u] + px, 6 * M, sim.field_w - 6 * M)
	var y := clampi(sim.u_cy[u] + py, 6 * M, sim.field_h - 6 * M)
	_move(sim, u, x, y, sim.u_face[u], _width(sim, u), 1, 4)


# -------------------------------------------------------------- terrain ---

## Mean ground height across a line centred on (x, y) running along (rx, ry)
## (Q12 unit vector): five samples LINE_SPAN apart.
static func _line_h(sim, x: int, y: int, rx: int, ry: int) -> int:
	var sum := 0
	for k in range(-2, 3):
		var px := clampi(x + rx * k * LINE_SPAN / FM.TRIG_ONE, 0, sim.field_w)
		var py := clampi(y + ry * k * LINE_SPAN / FM.TRIG_ONE, 0, sim.field_h)
		sum += sim.height_at(px, py)
	return sum / 5


## Deployment centre: the plan's, or a spot up to DEPLOY_SHIFT aside, back or
## forward whose line stands DEPLOY_GAIN higher (best first, in a fixed order).
static func _deploy_spot(sim, plan: Dictionary) -> Vector2i:
	var cx: int = plan["cx"]
	var cy: int = plan["cy"]
	var fx: int = plan["fx"]
	var fy: int = plan["fy"]
	var rx := -fy
	var ry := fx
	var best := Vector2i(cx, cy)
	var best_h := _line_h(sim, cx, cy, rx, ry) + DEPLOY_GAIN - 1
	var margin := 50 * M
	for c in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
			Vector2i(-1, -1), Vector2i(1, -1)]:
		var lat: int = c.x * DEPLOY_SHIFT
		var fwd: int = c.y * DEPLOY_SHIFT
		var x := cx + (rx * lat + fx * fwd) / FM.TRIG_ONE
		var y := cy + (ry * lat + fy * fwd) / FM.TRIG_ONE
		if x < margin or y < margin or x > sim.field_w - margin or y > sim.field_h - margin:
			continue
		var h := _line_h(sim, x, y, rx, ry)
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
	return own >= 0 and foe >= 0 and own - foe >= HOLD_DH and _hold_ok(sim, side)


static func _keep_holding(sim, side: int) -> bool:
	if sim.tick - sim.ai_hold[side] > HOLD_TICKS or not _hold_ok(sim, side):
		return false
	# Once a third of our foot is fighting, the battle is on everywhere.
	var foot := 0
	var fighting := 0
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and _is_foot(sim, u):
			foot += 1
			if sim.u_fighting[u] > 0:
				fighting += 1
	return fighting * 3 < foot


static func _hold_ok(sim, side: int) -> bool:
	var mine := _missile_power(sim, side)
	var theirs := _missile_power(sim, 1 - side)
	if theirs * 10 > mine * 13 + 200:
		return false  # clearly outshot: waiting only feeds their archers
	if _shelled(sim, side) and _art_power(sim, 1 - side) > _art_power(sim, side):
		return false
	return true


## Advance while skirmishing: stop short on clearly higher ground (a crest)
## still within reach of the enemy, else go the whole way.
static func _crest_advance(sim, plan: Dictionary, adv: int, gap: int, halt: int) -> int:
	var cx: int = plan["cx"]
	var cy: int = plan["cy"]
	var fx: int = plan["fx"]
	var fy: int = plan["fy"]
	var rx := -fy
	var ry := fx
	var full_h := _line_h(sim, cx + fx * adv / FM.TRIG_ONE, cy + fy * adv / FM.TRIG_ONE, rx, ry)
	var best := adv
	var best_h := full_h + CREST_GAIN - 1
	for k in 4:
		var a := adv * k / 4
		if gap - a > halt + 40 * M:
			continue  # too far from the enemy to shoot from there
		var h := _line_h(sim, cx + fx * a / FM.TRIG_ONE, cy + fy * a / FM.TRIG_ONE, rx, ry)
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
	# Candidate spots (the slot itself first) and their ground heights.
	var cx := PackedInt32Array([px])
	var cy := PackedInt32Array([py])
	var ch := PackedInt32Array([sim.height_at(px, py)])
	for c in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		var lat: int = c.x * RISE_LAT
		var fwd: int = c.y * 10 * M
		var x := clampi(px + (rx * lat + fx * fwd) / FM.TRIG_ONE, 4 * M, sim.field_w - 4 * M)
		var y := clampi(py + (ry * lat + fy * fwd) / FM.TRIG_ONE, 4 * M, sim.field_h - 4 * M)
		cx.append(x)
		cy.append(y)
		ch.append(sim.height_at(x, y))
	if not bolt:
		var b := 0
		var bs := ch[0] + RISE_GAIN - 1
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
		if ch[k] + 4 * M <= top:
			break
		if _sees_enemy(sim, u, cx[k], cy[k], ch[k], plan):
			score[k] += 4 * M
			break
	var best := 0
	var best_s := score[0] + RISE_GAIN - 1
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
	if d < DETOUR_MIN:
		return false
	var px0: int = sim.u_cx[t] - dx * DETOUR_MIN / d
	var py0: int = sim.u_cy[t] - dy * DETOUR_MIN / d
	var g: int = sim.grade_between(sim.height_at(px0, py0), sim.u_h[t], DETOUR_MIN)
	if g <= DETOUR_GRADE:
		return false
	var tf: int = sim.u_face[t]
	var c := FM.cos_a(tf)
	var s := FM.sin_a(tf)
	var hw: int = sim.unit_half_width(t) + 25 * M
	var depth: int = sim.unit_depth(t) / 2
	var best := Vector2i(-1, -1)
	var best_g := g * 2 / 3  # must be clearly gentler
	for sgn in [-1, 1]:
		var out: int = sgn * hw
		var px := clampi(sim.u_ax[t] + ((-s * out - c * depth) / FM.TRIG_ONE), 6 * M, sim.field_w - 6 * M)
		var py := clampi(sim.u_ay[t] + ((c * out - s * depth) / FM.TRIG_ONE), 6 * M, sim.field_h - 6 * M)
		var l1 := _d(px - sim.u_cx[u], py - sim.u_cy[u])
		var l2 := _d(sim.u_cx[t] - px, sim.u_cy[t] - py)
		if (l1 + l2) * 10 > d * DETOUR_LONG:
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


# ------------------------------------------------------------- helpers ---

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
	if _d(x - ox, y - oy) < REPLAN_DIST / 3 and absi(FM.angle_diff(sim.u_dface[u], face)) < 24 \
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
