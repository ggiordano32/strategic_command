extends RefCounted
## The play library (docs/AI.md 44): scripted historical tactics the battle
## AI (sim/battle_ai.gd) runs on top of its ordinary rules. A play has a
## trigger (the side's composition, the ground, the enemy's shape), a few
## posts and orders, and a counter in the battle's AI telemetry
## (BattleSim.stat_aic, AIProfile.C_PLAY_*). Deterministic like the rest of
## the AI: integers, no RNG, units in index order; its memory is a tail of
## BattleSim.ai_mem (hashed and snapshotted with it) that exists only in a
## battle where a play can run (wants_mem: an AI side with PLAYS_ON, a play
## bit and a gun foot unit; no Rome row has a gun, so a Rome battle never
## has it and hashes as before).
##
## Which plays: the scenario's "ai_plays" [side 0, side 1] bit mask
## (BattleSim.ai_plays; ALL when absent: custom battles and scenario keys);
## the campaign fills it from the faction's row (CData.PLAYS, west.gd).
## AIProfile.PLAYS_ON (Easy 0) switches the library; each play has its knob.
## A play starts once, in the deployment or at the first army think whose
## trigger holds (one C_PLAY_* count), and is dropped for good when its
## trigger has been gone PLAY_DROP_T; its units go back to the ordinary rules.
##
## The tercio (P_TERCIO, docs/AI.md 44.1; knob TERCIO): a field battle, the
## side has a pike unit and a gun foot unit (BattleAI.line_gun) and the enemy
## fields a rider unit. Each pike unit of
## the first line (not the battery guard's) stands as a block max(TERCIO_FILES,
## isqrt(men)) files wide; up to two gun units a block are its sleeves at
## its front corners (beside it, their front rank level with its front);
## other gun units stand in the line between the blocks (one block: beside
## the sleeves), the line's other foot outward of them, the wings shifted
## by as much (post_line: the slots _issue_line made). Under horse
## (unit_think): enemy riders closing on a sleeve (an attack order on it
## within 2 x TERCIO_HORSE_R, or riders within TERCIO_HORSE_R moving toward
## it) send it to the block's rear corner (TERCIO_REAR behind its rear rank)
## firing at will; TERCIO_CLEAR_T with none closing and it returns to the
## front corner. A block with riders closing from a flank (off its front by
## more than TERCIO_FLANK) within TERCIO_TURN_R turns in place to face them,
## and holds the turn until none have closed for TERCIO_CLEAR_T.

const FM := preload("res://sim/fixed_math.gd")
const UT := preload("res://sim/unit_types.gd")
const AP := preload("res://sim/ai_profile.gd")

const M := 1024
const ALL := -1                 # every play (the default of a scenario without "ai_plays")
const P_TERCIO := 0             # bit 0: the tercio (docs/AI.md 44.1)
const P_COUNTERMARCH := 1       # bit 1: the countermarch (docs/AI.md 44.2; its own build)
const P_AMBUSH := 2             # bit 2: the native ambush (docs/AI.md 44.5)
const PLAY_DROP_T := 300        # a play is dropped when its trigger has been gone this long (30 s)
const TERCIO_CLEAR_T := 100     # sleeves return / a block turns back after this long with no riders closing (10 s)
const TERCIO_TURN_R := 60 * M   # a block turns to face riders closing from a flank this near
const TERCIO_FLANK := 128       # ... off its front by more than this (1024 = a full turn: 45 degrees)
const TERCIO_REAR := 10 * M     # sheltering sleeves stand this far behind the block's rear rank
const AMB_REACH := 240 * M      # the ambush's wood: searched this far ahead of the side's centre ...
const AMB_RUN_R := 30 * M       # a hiding unit farther than this from its post runs to it
const AMB_STEP := 8 * M         # ... sampled this often along each line
const AMB_HIDE_IN := 8 * M      # the hidden line's anchors stand this far inside the woods' front
const AMB_BAIT_AHEAD := 30 * M  # the bait stands this far out in front of the woods' front
const AMB_PASSED := 20 * M      # an enemy unit this far past the woods' front springs the ambush
const AMB_HOME_R := 8 * M       # a melting / falling back unit this near its hiding post is home
const AMB_WAIT_T := 1800        # a cycle with no spring this long (3 min): the play is dropped
const AMB_WIN_PCT := 50        # winning: the enemy lost this % of our losses since the spring, or more ...
const AMB_LOSS_PCT := 33        # ... and the unit lost less than this % of its men since it sprang

# Mirrored from BattleSim / BattleAI (preloading either here would be circular).
const U_READY := 0
const U_DESTROYED := 2
const O_NONE := 0
const O_MOVE := 1
const O_ATTACK := 2
const ORDER_MOVE := 1
const ORDER_ATTACK := 2
const ORDER_FIRE := 5
const ORDER_SKIRMISH := 6
const AI_PLAYER_BASE := 100
const A_LINE := 0
const A_ATTACK := 1
const A_RETIRE := 7
const A_GUARD := 10

# The plays' memory: a tail of BattleSim.ai_mem after the Skilled memory
# (n_units * AP.MU_K + 2 * AP.SD_K), PU_K ints per unit then PS_K per side.
const PU_ROLE := 0              # tercio part: 0 none, 1 block, 2 left sleeve, 3 right sleeve; ambush: R_HIDE, R_BAIT, R_FLANK
const PU_OF := 1                # a sleeve's block + 1; ambush: its men when it sprang
const PU_STATE := 2             # 1: a sleeve sheltering behind its block / a block turned to a flank; ambush: AS_*
const PU_T := 3                 # the tick riders were last seen closing on it; ambush: the tick it sprang
const PU_X := 4                 # ambush: its hiding post (anchor) in the woods
const PU_Y := 5
const PU_K := 6
const PS_TERCIO := 0            # 0 not chosen, 1 running, 2 dropped
const PS_TERCIO_T := 1          # the tick it started
const PS_TERCIO_SEEN := 2       # the tick its trigger last held
const PS_AMB := 4               # the ambush: 0 not chosen, 1 running, 2 dropped
const PS_AMB_PH := 5            # ... its phase: AP_WAIT, AP_PULL, AP_SPRUNG
const PS_AMB_T := 6             # ... the tick this cycle began (the bait went out)
const PS_AMB_SEEN := 7          # ... the tick its trigger last held
const PS_AMB_X := 8             # ... the woods' front point (the hidden line's centre is AMB_HIDE_IN behind it)
const PS_AMB_Y := 9
const PS_AMB_FACE := 10         # ... the facing toward the enemy it was laid with
const PS_AMB_O0 := 11           # ... the side's men when it last sprang
const PS_AMB_E0 := 12           # ... the enemy's men then
const PS_K := 14

# The ambush's parts (PU_ROLE) and states (PU_STATE), its phases (PS_AMB_PH).
const R_HIDE := 4               # hidden in the main wood
const R_BAIT := 5               # the bait (out in front, or falling back)
const R_FLANK := 6              # hidden in the flank wood (AMBUSH_FLANK)
const AS_HIDE := 0              # hiding (the bait: standing out)
const AS_FIGHT := 1             # sprung (the bait: falling back)
const AS_MELT := 2              # melting back to its hiding post
const AP_WAIT := 1              # lying in wait, the bait out
const AP_PULL := 2              # the bait falling back
const AP_SPRUNG := 3            # sprung; a melted unit springs again on its own


# --------------------------------------------------------------- memory ---

## A play can run in this battle: some AI side has PLAYS_ON, a play bit and
## a gun foot unit (scenario rows `units`), or the ambush's bit and knob and
## a West cover foot row (no Rome row is one). Decides whether ai_mem gets
## the plays' tail (BattleSim.setup).
static func wants_mem(sim, units: Array) -> bool:
	for s in 2:
		if sim.ai_sides[s] == 0 or sim.ai_plays[s] == 0 or AP.of(sim, s)[AP.PLAYS_ON] == 0:
			continue
		var amb: bool = (sim.ai_plays[s] >> P_AMBUSH) & 1 != 0 and AP.of(sim, s)[AP.AMBUSH] != 0
		for ud in units:
			if int(ud["side"]) == s and (_gun_type(int(ud["type"])) or (amb and _cover_foot_type(int(ud["type"])))):
				return true
	return false


## Appends the plays' tail to sim.ai_mem (sized for the Skilled memory first).
static func add_mem(sim) -> void:
	var at: int = sim.n_units * AP.MU_K + 2 * AP.SD_K
	sim.ai_mem.resize(at + sim.n_units * PU_K + 2 * PS_K)
	for k in range(at, sim.ai_mem.size()):
		sim.ai_mem[k] = 0


static func has_mem(sim) -> bool:
	return sim.ai_mem.size() == sim.n_units * (AP.MU_K + PU_K) + 2 * (AP.SD_K + PS_K)


static func _pm(sim, u: int, k: int) -> int:
	return sim.ai_mem[sim.n_units * AP.MU_K + 2 * AP.SD_K + u * PU_K + k]


static func _pmset(sim, u: int, k: int, v: int) -> void:
	sim.ai_mem[sim.n_units * AP.MU_K + 2 * AP.SD_K + u * PU_K + k] = v


static func _ps(sim, side: int, k: int) -> int:
	return sim.ai_mem[sim.n_units * (AP.MU_K + PU_K) + 2 * AP.SD_K + side * PS_K + k]


static func _psset(sim, side: int, k: int, v: int) -> void:
	sim.ai_mem[sim.n_units * (AP.MU_K + PU_K) + 2 * AP.SD_K + side * PS_K + k] = v


## The tercio is running for side `side`.
static func tercio_on(sim, side: int) -> bool:
	return has_mem(sim) and _ps(sim, side, PS_TERCIO) == 1


## The side's tercio role of unit u (PU_ROLE; 0 without the plays' memory).
static func role(sim, u: int) -> int:
	return _pm(sim, u, PU_ROLE) if has_mem(sim) else 0


## Unit u's PU_STATE (1: a sleeve sheltering, a block turned).
static func state(sim, u: int) -> int:
	return _pm(sim, u, PU_STATE) if has_mem(sim) else 0


# ----------------------------------------------------------- army level ---

## Each army think (BattleAI._army_think, after the plan is read): start the
## plays whose trigger holds, drop those whose trigger has been gone
## PLAY_DROP_T.
static func army_think(sim, side: int, plan: Dictionary = {}) -> void:
	if not has_mem(sim):
		return
	var kn := AP.of(sim, side)
	if kn[AP.PLAYS_ON] == 0:
		return
	if kn[AP.TERCIO] != 0 and (sim.ai_plays[side] >> P_TERCIO) & 1 != 0 and _ps(sim, side, PS_AMB) != 1:
		_tercio_army(sim, side)
	if kn[AP.AMBUSH] != 0 and (sim.ai_plays[side] >> P_AMBUSH) & 1 != 0 and _ps(sim, side, PS_TERCIO) != 1:
		_amb_army(sim, side, kn, plan)


static func _tercio_army(sim, side: int) -> void:
	var st := _ps(sim, side, PS_TERCIO)
	if st == 2:
		return
	var trig := tercio_trigger(sim, side)
	if trig:
		_psset(sim, side, PS_TERCIO_SEEN, sim.tick)
	if st == 0 and trig:
		_psset(sim, side, PS_TERCIO, 1)
		_psset(sim, side, PS_TERCIO_T, sim.tick)
		sim.stat_aic[side * AP.N_COUNTERS + AP.C_PLAY_TERCIO] += 1
	elif st == 1 and not trig and sim.tick - _ps(sim, side, PS_TERCIO_SEEN) >= PLAY_DROP_T:
		_psset(sim, side, PS_TERCIO, 2)
		for u in sim.n_units:
			if sim.u_side[u] == side:
				_clear(sim, u)


## The tercio's trigger: a field battle (no settlement, no town plan); the
## side has a ready pike unit (not guarding the batteries) and a ready gun
## foot unit; the enemy shows a ready rider unit (one it sees). (Riders
## only, the owner's choice after the measure, docs/AI.md 44.1: against foot
## alone the deep block cost the natives' battle.)
static func tercio_trigger(sim, side: int) -> bool:
	if sim.city_on != 0:
		return false
	var city = sim.map_info.get("city", null)
	if city is Dictionary and int((city as Dictionary).get("tp", 0)) != 0:
		return false
	var pike := false
	var gun := false
	var rider := false
	for u in sim.n_units:
		if sim.u_state[u] != U_READY or _skip(sim, u):
			continue
		var c: int = sim.u_cls[u]
		if sim.u_side[u] == side:
			if c == UT.CLS_PIKE and sim.u_ai[u] != A_GUARD:
				pike = true
			if _gun_foot(sim, u):
				gun = true
		elif c == UT.CLS_CAV and not sim.hidden_from(u, side):
			rider = true
	return pike and gun and rider


# ------------------------------------------------------------ formation ---

## The tercio's layout (BattleAI._issue_line, after its slots are made and
## before the orders): `line1` the first line's units, `slots` unit ->
## [lateral, back] (a block's gets its width as a third value), `guard` the
## pike that will guard the batteries (deployment; -1 none). Sheltering
## sleeves and turned blocks are taken out of the slots (unit_think has
## them). Does nothing unless the side's tercio runs.
static func post_line(sim, side: int, line1: Array, slots: Dictionary, guard: int) -> void:
	if not tercio_on(sim, side):
		return
	var kn := AP.of(sim, side)
	var gap := kn[AP.LINE_GAP]
	var row: Array = []
	for u in line1:
		if slots.has(u):
			row.append(u)
	row.sort_custom(func(a: int, b: int) -> bool:
		var la: int = slots[a][0]
		var lb: int = slots[b][0]
		return la < lb or (la == lb and a < b))
	var blocks: Array = []
	var guns: Array = []
	var lrest: Array = []
	var rrest: Array = []
	for u in row:
		if sim.u_cls[u] == UT.CLS_PIKE and u != guard:
			blocks.append(u)
		elif _gun_foot(sim, u):
			guns.append(u)
		elif int(slots[u][0]) < 0:
			lrest.append(u)
		else:
			rrest.append(u)
	var nb := blocks.size()
	var ng := guns.size()
	var roles := {}  # unit -> [role, of]
	if nb > 0 and ng > 0:
		# Old extents: the whole row's and the core's (blocks and guns).
		var old_l := 0
		var old_r := 0
		var core_l := 0
		var core_r := 0
		var first := true
		var cfirst := true
		for u in row:
			var w := _width(sim, u)
			var a: int = int(slots[u][0]) - w / 2
			var b: int = int(slots[u][0]) + w / 2
			if first or a < old_l:
				old_l = a
			if first or b > old_r:
				old_r = b
			first = false
			if blocks.has(u) or guns.has(u):
				if cfirst or a < core_l:
					core_l = a
				if cfirst or b > core_r:
					core_r = b
				cfirst = false
		# Sleeves: block k % nb's outer side on the first pass, its inner
		# side on the second (a block in the left half: left is outer).
		var sl: Array = []
		var sr: Array = []
		sl.resize(nb)
		sr.resize(nb)
		sl.fill(false)
		sr.fill(false)
		var nsl := mini(ng, 2 * nb)
		for k in nsl:
			var i := k % nb
			var outer_left := 2 * i + 1 <= nb
			if (k < nb) == outer_left:
				sl[i] = true
			else:
				sr[i] = true
		var extra := ng - nsl
		# The sequence left to right: -1 a gun (assigned in lateral order),
		# else a block; per gun its role and block.
		var seq: Array = []
		var gr: Array = []  # per gun place: [role, block]
		if nb == 1:
			for k in extra / 2:
				seq.append(-1)
				gr.append([0, -1])
		for i in nb:
			if sl[i]:
				seq.append(-1)
				gr.append([2, blocks[i]])
			seq.append(blocks[i])
			if sr[i]:
				seq.append(-1)
				gr.append([3, blocks[i]])
			if nb > 1 and i < nb - 1:
				var share := extra / (nb - 1) + (1 if i < extra % (nb - 1) else 0)
				for k in share:
					seq.append(-1)
					gr.append([0, -1])
		if nb == 1:
			for k in extra - extra / 2:
				seq.append(-1)
				gr.append([0, -1])
		var units: Array = []
		var widths: Array = []
		var total := 0
		var gk := 0
		for e in seq:
			var u: int = e
			var w := 0
			if u < 0:
				u = guns[gk]
				w = _width(sim, u)
				var r: Array = gr[gk]
				if int(r[0]) != 0:
					roles[u] = [int(r[0]), int(r[1])]
				gk += 1
			else:
				w = block_files(sim, u, kn) * UT.stat(sim.u_type[u], "file_sp")
				roles[u] = [1, -1]
			units.append(u)
			widths.append(w)
			total += w + gap
		total -= gap
		var x := (core_l + core_r) / 2 - total / 2
		var new_l := x
		for k in units.size():
			var u: int = units[k]
			var w: int = widths[k]
			if sim.u_cls[u] == UT.CLS_PIKE:
				slots[u] = [x + w / 2, int(slots[u][1]), w]
			else:
				slots[u] = [x + w / 2, int(slots[u][1])]
			x += w + gap
		var new_r := x - gap
		# The line's other foot outward of the core, in their order.
		for k in range(lrest.size() - 1, -1, -1):
			var u: int = lrest[k]
			var w := _width(sim, u)
			slots[u] = [new_l - gap - w / 2, int(slots[u][1])]
			new_l -= gap + w
		for u in rrest:
			var w := _width(sim, u)
			slots[u] = [new_r + gap + w / 2, int(slots[u][1])]
			new_r += gap + w
		# The wings (cavalry, bolt throwers: slots level with the line,
		# beyond it) keep their distance from its ends.
		var keys := slots.keys()
		keys.sort()
		for u in keys:
			if row.has(u) or int(slots[u][1]) != 0:
				continue
			var lat: int = slots[u][0]
			if lat < old_l:
				slots[u] = [lat + new_l - old_l, 0]
			elif lat > old_r:
				slots[u] = [lat + new_r - old_r, 0]
	# Roles: set, kept (with their state) or cleared, in index order.
	for u in sim.n_units:
		if sim.u_side[u] != side:
			continue
		var r: Array = roles.get(u, [0, -1])
		if _pm(sim, u, PU_ROLE) != int(r[0]) or _pm(sim, u, PU_OF) != int(r[1]) + 1:
			_clear(sim, u)
			_pmset(sim, u, PU_ROLE, int(r[0]))
			_pmset(sim, u, PU_OF, int(r[1]) + 1)
		if _pm(sim, u, PU_ROLE) != 0 and _pm(sim, u, PU_STATE) != 0:
			slots.erase(u)  # (sheltering or turned: unit_think's)


## A tercio block's files: max(TERCIO_FILES, isqrt(men)), at most its men.
static func block_files(sim, u: int, kn: PackedInt32Array) -> int:
	var men: int = sim.u_alive[u]
	return clampi(maxi(kn[AP.TERCIO_FILES], FM.isqrt(men)), 1, maxi(men, 1))


# ------------------------------------------------------------ unit level ---

## Each unit think (BattleAI._unit_think, before the class rules): a unit
## with a part in its side's running tercio. True if the play gave it its
## orders this think (the ordinary rules are skipped).
static func unit_think(sim, u: int) -> bool:
	if not has_mem(sim):
		return false
	var r := _pm(sim, u, PU_ROLE)
	if r >= R_HIDE:
		if _ps(sim, sim.u_side[u], PS_AMB) != 1 or sim.u_ai[u] == A_RETIRE or sim.u_ai[u] == A_GUARD:
			return false
		return _amb_unit(sim, u, r)
	if r == 0 or _ps(sim, sim.u_side[u], PS_TERCIO) != 1:
		return false
	if sim.u_ai[u] == A_RETIRE or sim.u_ai[u] == A_GUARD:
		return false
	if r == 1:
		return _block_think(sim, u)
	return _sleeve_think(sim, u, r)


static func _sleeve_think(sim, u: int, r: int) -> bool:
	var b := _pm(sim, u, PU_OF) - 1
	if b < 0 or sim.u_state[b] != U_READY or sim.u_fighting[u] > 0:
		return false
	var side: int = sim.u_side[u]
	var kn := AP.of(sim, side)
	var near := false
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] != U_READY or sim.u_cls[o] != UT.CLS_CAV or _skip(sim, o):
			continue
		if not sim.hidden_from(o, side) and _closing(sim, o, u, kn[AP.TERCIO_HORSE_R]):
			near = true
			break
	if near:
		_pmset(sim, u, PU_T, sim.tick)
	var st := _pm(sim, u, PU_STATE)
	if st == 0:
		if not near:
			return false
		_pmset(sim, u, PU_STATE, 1)
	elif not near and sim.tick - _pm(sim, u, PU_T) >= TERCIO_CLEAR_T:
		_pmset(sim, u, PU_STATE, 0)
		var fp := sleeve_post(sim, u, b, r, false)
		_move(sim, u, fp.x, fp.y, sim.u_face[b], _width(sim, u), 0, 7)
		return true
	var p := sleeve_post(sim, u, b, r, true)
	_move(sim, u, p.x, p.y, sim.u_face[b], _width(sim, u), 1, 7)
	if sim.u_fire[u] == 0:
		_order(sim, u, {"type": ORDER_FIRE, "on": 1}, 21)
	return true


## A sleeve's post beside block b (its anchor, the front centre, facing as
## the block): `rear` false the front corner (beside the block, the front
## ranks level), true the rear corner (TERCIO_REAR behind its rear rank).
static func sleeve_post(sim, u: int, b: int, r: int, rear: bool) -> Vector2i:
	var kn := AP.of(sim, sim.u_side[u])
	var gap := kn[AP.LINE_GAP]
	var face: int = sim.u_face[b]
	var fx := FM.cos_a(face)
	var fy := FM.sin_a(face)
	var rx := -fy
	var ry := fx
	var bw := _width(sim, b)
	var sw := _width(sim, u)
	var sgn := -1 if r == 2 else 1
	var lat := sgn * (bw / 2 + gap + sw / 2)
	var back := 0
	if rear:
		lat = sgn * maxi(bw / 2, sw / 2 + gap / 2)
		back = _depth(sim, b) + TERCIO_REAR
	var px: int = sim.u_ax[b] + (rx * lat - fx * back) / FM.TRIG_ONE
	var py: int = sim.u_ay[b] + (ry * lat - fy * back) / FM.TRIG_ONE
	return Vector2i(clampi(px, 4 * M, sim.field_w - 4 * M), clampi(py, 4 * M, sim.field_h - 4 * M))


static func _block_think(sim, u: int) -> bool:
	if sim.u_fighting[u] > 0:
		return false
	var side: int = sim.u_side[u]
	var best := -1
	var bd := 0
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] != U_READY or sim.u_cls[o] != UT.CLS_CAV or _skip(sim, o):
			continue
		if sim.hidden_from(o, side) or not _closing(sim, o, u, TERCIO_TURN_R):
			continue
		var d := _d(sim.u_cx[o] - sim.u_cx[u], sim.u_cy[o] - sim.u_cy[u])
		if d < TERCIO_TURN_R and (best < 0 or d < bd):
			best = o
			bd = d
	var st := _pm(sim, u, PU_STATE)
	if best >= 0:
		_pmset(sim, u, PU_T, sim.tick)
		var a := ((FM.atan2_a(sim.u_cy[best] - sim.u_cy[u], sim.u_cx[best] - sim.u_cx[u]) + 8) >> 4 << 4) & FM.ANGLE_MASK
		if absi(FM.angle_diff(sim.u_face[u], a)) > TERCIO_FLANK:
			# Turn in place (about the block's centre) to face the riders.
			var h := _depth(sim, u) / 2
			var px: int = clampi(sim.u_cx[u] + FM.cos_a(a) * h / FM.TRIG_ONE, 4 * M, sim.field_w - 4 * M)
			var py: int = clampi(sim.u_cy[u] + FM.sin_a(a) * h / FM.TRIG_ONE, 4 * M, sim.field_h - 4 * M)
			_move(sim, u, px, py, a, _width(sim, u), 0, 6)
			_pmset(sim, u, PU_STATE, 1)
			return true
		return st == 1
	if st == 1:
		if sim.tick - _pm(sim, u, PU_T) < TERCIO_CLEAR_T:
			return true
		_pmset(sim, u, PU_STATE, 0)
	return false


## Enemy rider o closing on unit u: an attack order on it within 2 r, or
## within r with its order taking it nearer to u (a move's end point or its
## attack target nearer u than it is).
static func _closing(sim, o: int, u: int, r: int) -> bool:
	var d := _d(sim.u_cx[o] - sim.u_cx[u], sim.u_cy[o] - sim.u_cy[u])
	if sim.u_order[o] == O_ATTACK and sim.u_target[o] == u:
		return d < 2 * r
	if d >= r:
		return false
	var tx := 0
	var ty := 0
	if sim.u_order[o] == O_MOVE:
		tx = sim.u_dx[o]
		ty = sim.u_dy[o]
	elif sim.u_order[o] == O_ATTACK and sim.u_target[o] >= 0:
		tx = sim.u_cx[sim.u_target[o]]
		ty = sim.u_cy[sim.u_target[o]]
	else:
		return false
	return _d(tx - sim.u_cx[u], ty - sim.u_cy[u]) < d


# --------------------------------------------------------------- ambush ---
# The native ambush from cover with a feigned retreat (P_AMBUSH, docs/AI.md
# 44.5; knob AMBUSH). Laid once at the first army think its trigger holds and
# a wood lies between the lines (on the side's half): the side's foot hide
# along the woods' front toward the enemy (AMB_HIDE_IN inside it, fire held, skirmish off), a bait
# (AMBUSH_BAIT units: a skirmisher, else the smallest) stands AMB_BAIT_AHEAD
# out in front. An enemy unit within AMBUSH_PULL_R of the bait: it falls back
# to its hiding post at the walk. An enemy unit within AMBUSH_SPRING_R of a
# hidden unit (box to box), one that has seen a hidden unit, or one
# AMB_PASSED past the woods' front: every hidden unit and the bait attack at
# once (the sim's ambush strike rewards the first volley or contact). A
# sprung unit that has fought AMBUSH_FIGHT_T, is out of a melee and is not winning melts back to
# its post; with every unit home again a new bait goes out. Skilled
# (AMBUSH_FLANK): half the hidden units take a second wood on the enemy's
# flank. Dropped when its trigger has been gone PLAY_DROP_T, at once when no
# foot is left to hide, and when a cycle has waited AMB_WAIT_T for a spring.

## The ambush is running for side `side`.
static func ambush_on(sim, side: int) -> bool:
	return has_mem(sim) and _ps(sim, side, PS_AMB) == 1


## The ambush's trigger (while it runs): a field battle (no settlement, no
## town plan) with woods and line of sight; the side has a ready West cover
## foot unit (a hider: _amb_foot) and the enemy a ready line foot or horse
## unit. Its start needs a wood between the lines too (_amb_woods).
static func ambush_trigger(sim, side: int) -> bool:
	if sim.city_on != 0 or sim.veg_on == 0 or sim.vis_on == 0:
		return false
	var city = sim.map_info.get("city", null)
	if city is Dictionary and int((city as Dictionary).get("tp", 0)) != 0:
		return false
	var cov := false
	var line := false
	for u in sim.n_units:
		if sim.u_state[u] != U_READY or _skip(sim, u):
			continue
		if sim.u_side[u] == side:
			if _amb_foot(sim, u) and _cover_foot_type(sim.u_otype[u]):
				cov = true
		else:
			var c: int = sim.u_cls[u]
			if c == UT.CLS_INF or c == UT.CLS_PIKE or c == UT.CLS_CAV or _gun_foot(sim, u):
				line = true
	return cov and line


static func _amb_army(sim, side: int, kn: PackedInt32Array, plan: Dictionary) -> void:
	var st := _ps(sim, side, PS_AMB)
	if st == 2:
		return
	var trig := ambush_trigger(sim, side)
	if st == 0:
		if not trig or plan.is_empty():
			return
		var w := _amb_woods(sim, plan, 0, false)
		if w.is_empty():
			return
		_psset(sim, side, PS_AMB, 1)
		_psset(sim, side, PS_AMB_SEEN, sim.tick)
		_psset(sim, side, PS_AMB_X, int(w[0]))
		_psset(sim, side, PS_AMB_Y, int(w[1]))
		_psset(sim, side, PS_AMB_FACE, int(plan["face"]))
		sim.stat_aic[side * AP.N_COUNTERS + AP.C_PLAY_AMBUSH] += 1
		_amb_lay(sim, side, kn, plan, w)
		_amb_cycle(sim, side, kn)
		return
	if trig:
		_psset(sim, side, PS_AMB_SEEN, sim.tick)
	var hiders := 0
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and _pm(sim, u, PU_ROLE) >= R_HIDE:
			hiders += 1
	if hiders == 0 or (not trig and sim.tick - _ps(sim, side, PS_AMB_SEEN) >= PLAY_DROP_T):
		_amb_drop(sim, side)
		return
	var ph := _ps(sim, side, PS_AMB_PH)
	if ph == AP_SPRUNG:
		# Back to lying in wait once every unit is home and hiding.
		for u in sim.n_units:
			if sim.u_side[u] == side and sim.u_state[u] == U_READY and _pm(sim, u, PU_ROLE) >= R_HIDE \
					and _pm(sim, u, PU_STATE) != AS_HIDE:
				return
		_amb_cycle(sim, side, kn)
		return
	if sim.tick - _ps(sim, side, PS_AMB_T) >= AMB_WAIT_T:
		_amb_drop(sim, side)  # (nobody came: the ordinary rules)
		return
	if _amb_springs(sim, side, kn):
		_amb_spring(sim, side)
		return
	# The bait: falls back when an enemy unit comes within AMBUSH_PULL_R;
	# lost while lying in wait: a new one goes out (one back home after
	# falling back stays hidden: the line waits for the spring).
	var out := false
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY or _pm(sim, u, PU_ROLE) != R_BAIT:
			continue
		out = true
		if _pm(sim, u, PU_STATE) == AS_HIDE and _enemy_within(sim, u, kn[AP.AMBUSH_PULL_R]):
			_pmset(sim, u, PU_STATE, AS_FIGHT)  # (falling back: unit_think)
			_psset(sim, side, PS_AMB_PH, AP_PULL)
	if not out and ph == AP_WAIT:
		_amb_bait(sim, side, kn)


## A new cycle: lying in wait with a new bait out.
static func _amb_cycle(sim, side: int, kn: PackedInt32Array) -> void:
	_psset(sim, side, PS_AMB_PH, AP_WAIT)
	_psset(sim, side, PS_AMB_T, sim.tick)
	_amb_bait(sim, side, kn)


## Picks AMBUSH_BAIT baits from the hiding units: skirmishers first, then the
## fewest men, then index.
static func _amb_bait(sim, side: int, kn: PackedInt32Array) -> void:
	for k in kn[AP.AMBUSH_BAIT]:
		var best := -1
		var bk := 0
		for u in sim.n_units:
			if sim.u_side[u] != side or sim.u_state[u] != U_READY or sim.u_fighting[u] > 0:
				continue
			var r := _pm(sim, u, PU_ROLE)
			if (r != R_HIDE and r != R_FLANK) or _pm(sim, u, PU_STATE) != AS_HIDE or sim.u_ai[u] == A_RETIRE:
				continue
			var key: int = sim.u_alive[u] + (0 if UT.stat(sim.u_type[u], "skirm") != 0 else 100000)
			if best < 0 or key < bk:
				best = u
				bk = key
		if best < 0:
			return
		_pmset(sim, best, PU_ROLE, R_BAIT)
		_pmset(sim, best, PU_STATE, AS_HIDE)


## The spring: an enemy foot unit (_amb_prey) within AMBUSH_SPRING_R of a
## hidden unit at its post (box to box), such a unit in contact or fighting,
## or an enemy foot unit AMB_PASSED past the woods' front (along the facing
## the ambush was laid with). Riders scouting ahead do not spring it (one
## that finds a hidden unit fights it alone).
static func _amb_springs(sim, side: int, kn: PackedInt32Array) -> bool:
	var face := _ps(sim, side, PS_AMB_FACE)
	var fx := FM.cos_a(face)
	var fy := FM.sin_a(face)
	var wx := _ps(sim, side, PS_AMB_X)
	var wy := _ps(sim, side, PS_AMB_Y)
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] != U_READY or not _amb_prey(sim, o):
			continue
		if ((sim.u_cx[o] - wx) * fx + (sim.u_cy[o] - wy) * fy) / FM.TRIG_ONE < -AMB_PASSED:
			return true
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY:
			continue
		var r := _pm(sim, u, PU_ROLE)
		if (r != R_HIDE and r != R_FLANK) or _pm(sim, u, PU_STATE) != AS_HIDE:
			continue
		if _d(sim.u_ax[u] - _pm(sim, u, PU_X), sim.u_ay[u] - _pm(sim, u, PU_Y)) > AMB_RUN_R:
			continue  # (still on its way: not hidden yet; attacked, it fights on its own)
		if sim.u_fighting[u] > 0 or sim.u_contact[u] != 0 or _amb_near(sim, u, kn[AP.AMBUSH_SPRING_R]):
			return true
	return false


## An enemy unit that springs the ambush: foot (the main body), not riders
## scouting ahead, batteries, wagons or characters.
static func _amb_prey(sim, o: int) -> bool:
	var c: int = sim.u_cls[o]
	return (c == UT.CLS_INF or c == UT.CLS_PIKE or c == UT.CLS_MISSILE) and not _skip(sim, o)


## Every hiding unit and the bait attack at once.
static func _amb_spring(sim, side: int) -> void:
	_psset(sim, side, PS_AMB_PH, AP_SPRUNG)
	_psset(sim, side, PS_AMB_O0, _men(sim, side))
	_psset(sim, side, PS_AMB_E0, _men(sim, 1 - side))
	sim.stat_aic[side * AP.N_COUNTERS + AP.C_AMB_SPRING] += 1
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY or _pm(sim, u, PU_ROLE) < R_HIDE:
			continue
		if _pm(sim, u, PU_ROLE) == R_BAIT:
			_pmset(sim, u, PU_ROLE, R_HIDE)
		elif _pm(sim, u, PU_STATE) != AS_HIDE:
			continue
		_amb_go(sim, u)


## Unit u springs: the nearest enemy it sees (else the nearest), a charge for
## melee foot; missile foot fire at will, and close only with no target in
## range.
static func _amb_go(sim, u: int) -> void:
	var side: int = sim.u_side[u]
	_pmset(sim, u, PU_STATE, AS_FIGHT)
	_pmset(sim, u, PU_T, sim.tick)
	_pmset(sim, u, PU_OF, sim.u_alive[u])
	sim.u_ai[u] = A_ATTACK
	sim.u_ai_t[u] = sim.tick
	var t := -1
	var td := 0
	var tseen := false
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] != U_READY or _skip(sim, o):
			continue
		var seen: bool = not sim.hidden_from(o, side)
		var d := _d(sim.u_cx[o] - sim.u_cx[u], sim.u_cy[o] - sim.u_cy[u])
		if t < 0 or (seen and not tseen) or (seen == tseen and d < td):
			t = o
			td = d
			tseen = seen
	if sim.u_cls[u] == UT.CLS_MISSILE:
		if sim.u_fire[u] == 0:
			_order(sim, u, {"type": ORDER_FIRE, "on": 1}, 21)
		if t >= 0 and not sim._in_range(u, t, sim.mrange(u)):
			_attack(sim, u, t, 0)
	elif t >= 0:
		_attack(sim, u, t, 1)


static func _amb_drop(sim, side: int) -> void:
	_psset(sim, side, PS_AMB, 2)
	for u in sim.n_units:
		if sim.u_side[u] == side and _pm(sim, u, PU_ROLE) >= R_HIDE:
			_clear(sim, u)
			if sim.u_state[u] == U_READY and sim.u_ai[u] != A_RETIRE:
				sim.u_ai[u] = A_ATTACK
				sim.u_ai_t[u] = sim.tick


## The ambush's wood: along lines parallel to the plan's facing (lateral 0,
## -40, 40, ... 120 m from the side's centre, fixed order), the last wooded
## sample (every AMB_STEP) from the centre up to AMB_REACH ahead and no
## further than halfway to the enemy's centre (the hiders get there first): the woods' front toward the
## enemy on the first line that has one. [x, y, lateral] or []. `flank`:
## the flank wood instead, lateral 120-200 m on the side away from `wlat`
## (wlat 0: right first), its line at least 100 m from the main wood's.
static func _amb_woods(sim, plan: Dictionary, wlat: int, flank: bool) -> Array:
	var cx: int = plan["cx"]
	var cy: int = plan["cy"]
	var fx: int = plan["fx"]
	var fy: int = plan["fy"]
	var rx := -fy
	var ry := fx
	var de: int = ((int(plan["ex"]) - cx) * fx + (int(plan["ey"]) - cy) * fy) / FM.TRIG_ONE
	var lim := mini(AMB_REACH, de / 2)
	var lats: Array = [0, -40, 40, -80, 80, -120, 120]
	if flank:
		var sg := -1 if wlat > 0 else 1
		lats = []
		for l in [120, 160, 200]:
			lats.append(sg * l)
			lats.append(-sg * l)
	for l in lats:
		var lat: int = l * M
		if flank and absi(lat - wlat) < 100 * M:
			continue
		var front := -1
		var k := 0
		while k <= lim:
			var x := cx + (fx * k + rx * lat) / FM.TRIG_ONE
			var y := cy + (fy * k + ry * lat) / FM.TRIG_ONE
			if x >= 4 * M and y >= 4 * M and x <= sim.field_w - 4 * M and y <= sim.field_h - 4 * M \
					and sim.veg_d(x, y) > 0 and sim.nav_at(x, y) != 0:
				front = k
			k += AMB_STEP
		if front >= 0:
			return [cx + (fx * front + rx * lat) / FM.TRIG_ONE, cy + (fy * front + ry * lat) / FM.TRIG_ONE, lat]
	return []


## Lays the hidden line: the side's foot (_amb_foot) in their lateral order,
## side by side LINE_GAP apart, centred AMB_HIDE_IN behind the woods' front
## `w`, each post moved to the nearest wooded spot (_amb_spot); with
## AMBUSH_FLANK and a flank wood, the half toward it there (R_FLANK).
static func _amb_lay(sim, side: int, kn: PackedInt32Array, plan: Dictionary, w: Array) -> void:
	var fx: int = plan["fx"]
	var fy: int = plan["fy"]
	var rx := -fy
	var ry := fx
	var cx: int = plan["cx"]
	var cy: int = plan["cy"]
	var units: Array = []
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and _amb_foot(sim, u) \
				and sim.u_ai[u] != A_RETIRE and sim.u_ai[u] != A_GUARD:
			units.append(u)
	units.sort_custom(func(a: int, b: int) -> bool:
		var la: int = ((sim.u_ax[a] - cx) * rx + (sim.u_ay[a] - cy) * ry) / FM.TRIG_ONE
		var lb: int = ((sim.u_ax[b] - cx) * rx + (sim.u_ay[b] - cy) * ry) / FM.TRIG_ONE
		return la < lb or (la == lb and a < b))
	var groups: Array = [[units, w, R_HIDE]]
	if kn[AP.AMBUSH_FLANK] != 0 and units.size() >= 2:
		var fw := _amb_woods(sim, plan, int(w[2]), true)
		if not fw.is_empty():
			var nf: int = units.size() / 2
			var main: Array = []
			var fl: Array = []
			for k in units.size():
				# (the half on the flank wood's side of the line)
				var toward: bool = (k >= units.size() - nf) if int(fw[2]) > int(w[2]) else (k < nf)
				if toward:
					fl.append(units[k])
				else:
					main.append(units[k])
			groups = [[main, w, R_HIDE], [fl, fw, R_FLANK]]
	var gap := kn[AP.LINE_GAP]
	for g in groups:
		var us: Array = g[0]
		var gw: Array = g[1]
		var hx: int = int(gw[0]) - fx * AMB_HIDE_IN / FM.TRIG_ONE
		var hy: int = int(gw[1]) - fy * AMB_HIDE_IN / FM.TRIG_ONE
		var total := 0
		for u in us:
			total += _width(sim, u) + gap
		total -= gap
		var x := -total / 2
		for u in us:
			var wd := _width(sim, u)
			var lat := x + wd / 2
			x += wd + gap
			var p := _amb_spot(sim, u, hx + rx * lat / FM.TRIG_ONE, hy + ry * lat / FM.TRIG_ONE, fx, fy, rx, ry, lat)
			_clear(sim, u)
			_pmset(sim, u, PU_ROLE, int(g[2]))
			_pmset(sim, u, PU_STATE, AS_HIDE)
			_pmset(sim, u, PU_X, p.x)
			_pmset(sim, u, PU_Y, p.y)


## A hiding post for unit u near (px, py): wooded at its anchor and half its
## depth behind; else 8-32 m further back, else 10-40 m toward the line's
## centre (lat's other way), at the front or 16 m back (fixed order); else
## the spot.
static func _amb_spot(sim, u: int, px: int, py: int, fx: int, fy: int, rx: int, ry: int, lat: int) -> Vector2i:
	var h := _depth(sim, u) / 2
	var sg := -1 if lat > 0 else 1
	var cands: Array = [Vector2i(0, 0), Vector2i(0, 8), Vector2i(0, 16), Vector2i(0, 24), Vector2i(0, 32)]
	for l in [10, 20, 30, 40]:
		cands.append(Vector2i(sg * l, 0))
		cands.append(Vector2i(sg * l, 16))
	for c in cands:
		var x := clampi(px + (rx * c.x - fx * c.y) * M / FM.TRIG_ONE, 4 * M, sim.field_w - 4 * M)
		var y := clampi(py + (ry * c.x - fy * c.y) * M / FM.TRIG_ONE, 4 * M, sim.field_h - 4 * M)
		if sim.veg_d(x, y) > 0 and sim.veg_d(x - fx * h / FM.TRIG_ONE, y - fy * h / FM.TRIG_ONE) > 0 \
				and sim.nav_at(x, y) != 0:
			return Vector2i(x, y)
	return Vector2i(clampi(px, 4 * M, sim.field_w - 4 * M), clampi(py, 4 * M, sim.field_h - 4 * M))


## _issue_line's slots while the side's ambush runs: its units are the
## play's (unit_think), not the line's.
static func amb_slots(sim, side: int, slots: Dictionary) -> void:
	for u in sim.n_units:
		if sim.u_side[u] == side and _pm(sim, u, PU_ROLE) >= R_HIDE:
			slots.erase(u)


## Each unit think of a unit with a part in its side's running ambush. True
## if the play gave it its orders (the ordinary rules are skipped).
static func _amb_unit(sim, u: int, r: int) -> bool:
	var side: int = sim.u_side[u]
	var kn := AP.of(sim, side)
	var st := _pm(sim, u, PU_STATE)
	var face := _ps(sim, side, PS_AMB_FACE)
	var hx := _pm(sim, u, PU_X)
	var hy := _pm(sim, u, PU_Y)
	if st == AS_FIGHT and r != R_BAIT:
		# Sprung: the ordinary rules fight; after AMBUSH_FIGHT_T, out of a
		# melee and not winning: melt.
		if sim.tick - _pm(sim, u, PU_T) < kn[AP.AMBUSH_FIGHT_T] or sim.u_fighting[u] > 0 or _amb_winning(sim, u):
			return false
		_pmset(sim, u, PU_STATE, AS_MELT)
		sim.u_ai[u] = A_LINE
		sim.stat_aic[side * AP.N_COUNTERS + AP.C_AMB_MELT] += 1
		_move(sim, u, hx, hy, face, _width(sim, u), 1, 3)
		_hold(sim, u)
		return true
	if sim.u_fighting[u] > 0:
		if r == R_BAIT:
			return false  # (caught: the ordinary rules; the spring check sees the enemy near)
		_amb_go(sim, u)  # (found and attacked: it fights)
		sim.stat_aic[side * AP.N_COUNTERS + AP.C_AMB_SPRING] += 1
		return false
	if st == AS_MELT:
		if _d(sim.u_ax[u] - hx, sim.u_ay[u] - hy) < AMB_HOME_R or sim.u_order[u] == O_NONE:
			_pmset(sim, u, PU_STATE, AS_HIDE)
			_pmset(sim, u, PU_T, sim.tick)  # (home: it strikes again after AMBUSH_FIGHT_T)
		else:
			_move(sim, u, hx, hy, face, _width(sim, u), 1, 3)
		_hold(sim, u)
		return true
	if r == R_BAIT:
		if st == AS_FIGHT:
			# Falling back to its hiding post at the walk (the run with an
			# enemy within AMBUSH_SPRING_R); home: it hides again.
			if _d(sim.u_ax[u] - hx, sim.u_ay[u] - hy) < AMB_HOME_R:
				_pmset(sim, u, PU_ROLE, R_HIDE)
				_pmset(sim, u, PU_STATE, AS_HIDE)
				_hold(sim, u)
				return true
			var run := 1 if _enemy_within(sim, u, kn[AP.AMBUSH_SPRING_R]) else 0
			_move(sim, u, hx, hy, face, _width(sim, u), run, 4)
			return true
		# Out in front of the woods' front, in sight, shooting if it can.
		var fx := FM.cos_a(face)
		var fy := FM.sin_a(face)
		var bx := clampi(_ps(sim, side, PS_AMB_X) + fx * AMB_BAIT_AHEAD / FM.TRIG_ONE, 4 * M, sim.field_w - 4 * M)
		var by := clampi(_ps(sim, side, PS_AMB_Y) + fy * AMB_BAIT_AHEAD / FM.TRIG_ONE, 4 * M, sim.field_h - 4 * M)
		_move(sim, u, bx, by, face, _width(sim, u), 1 if _d(sim.u_ax[u] - bx, sim.u_ay[u] - by) > AMB_RUN_R else 0, 5)
		if sim.u_cls[u] == UT.CLS_MISSILE and sim.u_fire[u] == 0:
			_order(sim, u, {"type": ORDER_FIRE, "on": 1}, 21)
		return true
	# Hiding: at its post, fire held, no skirmish fall-back; after a spring
	# (a melted unit, home), an enemy within AMBUSH_SPRING_R springs it
	# again, and so does AMBUSH_FIGHT_T hidden with an enemy foot unit within
	# AMBUSH_PULL_R (it strikes again while the others fight near by).
	if _ps(sim, side, PS_AMB_PH) == AP_SPRUNG and (_amb_near(sim, u, kn[AP.AMBUSH_SPRING_R]) \
			or (sim.tick - _pm(sim, u, PU_T) >= kn[AP.AMBUSH_FIGHT_T] and _amb_near(sim, u, kn[AP.AMBUSH_PULL_R]))):
		_amb_go(sim, u)
		sim.stat_aic[side * AP.N_COUNTERS + AP.C_AMB_SPRING] += 1
		return true
	var dh := _d(sim.u_ax[u] - hx, sim.u_ay[u] - hy)
	if dh >= AMB_HOME_R:
		_move(sim, u, hx, hy, face, _width(sim, u), 1 if dh > AMB_RUN_R else 0, 3)
	_hold(sim, u)
	return true


## Fire held and no skirmish fall-back (hiding).
static func _hold(sim, u: int) -> void:
	if sim.u_fire[u] != 0:
		_order(sim, u, {"type": ORDER_FIRE, "on": 0}, 21)
	if sim.u_skirm[u] != 0:
		_order(sim, u, {"type": ORDER_SKIRMISH, "on": 0}, 20)


## A sprung unit is winning (it fights on): one that has lost no man since it
## sprang while enemy foot is within AMBUSH_PULL_R of it; else since the side
## last sprang the enemy lost AMB_WIN_PCT of the side's losses or more and
## the unit lost under AMB_LOSS_PCT of its men since it sprang.
static func _amb_winning(sim, u: int) -> bool:
	var side: int = sim.u_side[u]
	var own: int = _ps(sim, side, PS_AMB_O0) - _men(sim, side)
	var theirs: int = _ps(sim, side, PS_AMB_E0) - _men(sim, 1 - side)
	var lost: int = _pm(sim, u, PU_OF) - sim.u_alive[u]
	if lost <= 0:
		# Not fought yet: it carries on while enemy foot is within
		# AMBUSH_PULL_R (else back to cover: the next cycle's bait draws them).
		return _amb_near(sim, u, AP.of(sim, side)[AP.AMBUSH_PULL_R])
	return theirs * 100 >= own * AMB_WIN_PCT and lost * 100 < _pm(sim, u, PU_OF) * AMB_LOSS_PCT


## A ready enemy foot unit (_amb_prey) within r of unit u (box to box).
static func _amb_near(sim, u: int, r: int) -> bool:
	for o in sim.n_units:
		if sim.u_side[o] != sim.u_side[u] and sim.u_state[o] == U_READY and _amb_prey(sim, o) and sim._box_gap(u, o) <= r:
			return true
	return false


## A ready enemy unit the side sees within r of unit u (centroids).
static func _enemy_within(sim, u: int, r: int) -> bool:
	var side: int = sim.u_side[u]
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] != U_READY or _skip(sim, o) or sim.hidden_from(o, side):
			continue
		if _d(sim.u_cx[o] - sim.u_cx[u], sim.u_cy[o] - sim.u_cy[u]) < r:
			return true
	return false


## The side's men on the field (ready or routing; not wagons or characters).
static func _men(sim, side: int) -> int:
	var n := 0
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] < U_DESTROYED and not _skip(sim, u):
			n += sim.u_alive[u]
	return n


## A foot unit that can hide: foot, pikes or missile foot (not horse, guns,
## wagons, characters or the general).
static func _amb_foot(sim, u: int) -> bool:
	var c: int = sim.u_cls[u]
	return (c == UT.CLS_INF or c == UT.CLS_PIKE or c == UT.CLS_MISSILE) and not _skip(sim, u) \
		and UT.stat(sim.u_type[u], "cmd_r") <= 0


## A West foot row with the cover trait (Rome's skirmishers have it too, so
## the West's rows only: no Rome battle lays an ambush).
static func _cover_foot_type(ty: int) -> bool:
	var c := UT.cls(ty)
	return ty >= UT.ROME_N and UT.stat(ty, "cover") != 0 \
		and (c == UT.CLS_INF or c == UT.CLS_PIKE or c == UT.CLS_MISSILE)


# -------------------------------------------------------------- helpers ---

static func _clear(sim, u: int) -> void:
	for k in PU_K:
		_pmset(sim, u, k, 0)


## A gun foot row (BattleAI.line_gun: a gun that does not skirmish), not horse or a battery.
static func _gun_type(ty: int) -> bool:
	return UT.stat(ty, "m_gun") != 0 and UT.stat(ty, "skirm") == 0 \
		and UT.cls(ty) != UT.CLS_CAV and UT.cls(ty) != UT.CLS_ART


static func _gun_foot(sim, u: int) -> bool:
	return _gun_type(sim.u_type[u])


## Wagons and characters (BattleAI.is_wagon / is_char) are no part of a play's count.
static func _skip(sim, u: int) -> bool:
	return UT.stat(sim.u_otype[u], "wagon") >= 0 or (sim.ch_on != 0 and sim.u_char[u] != 0)


static func _width(sim, u: int) -> int:
	var files := mini(sim.u_files[u], sim.u_alive[u])
	return files * UT.stat(sim.u_type[u], "file_sp")


## Depth of unit u's formation front to rear rank (sim units).
static func _depth(sim, u: int) -> int:
	var files := maxi(mini(sim.u_files[u], sim.u_alive[u]), 1)
	var ranks: int = (sim.u_alive[u] + files - 1) / files
	return maxi(ranks - 1, 0) * UT.stat(sim.u_type[u], "rank_sp")


static func _d(dx: int, dy: int) -> int:
	return FM.approx_len(dx, dy)


## (BattleAI._order / _move: the same orders, the same skip of a move the
## unit already has.)
static func _order(sim, u: int, o: Dictionary, k: int) -> void:
	if sim.u_hand[u] >= 0:
		return
	o["tick"] = sim.tick
	o["unit"] = u
	o["player"] = AI_PLAYER_BASE + sim.u_side[u]
	o["seq"] = u * 32 + k
	sim.queue_order(o)


static func _move(sim, u: int, x: int, y: int, face: int, width: int, run: int, k: int) -> void:
	var ox: int = sim.u_dx[u] if sim.u_order[u] == O_MOVE else sim.u_ax[u]
	var oy: int = sim.u_dy[u] if sim.u_order[u] == O_MOVE else sim.u_ay[u]
	var kn := AP.of(sim, sim.u_side[u])
	if _d(x - ox, y - oy) < kn[AP.REPLAN_DIST] / 3 and absi(FM.angle_diff(sim.u_dface[u], face)) < kn[AP.REPLAN_FACE] \
			and sim.u_order[u] != O_ATTACK:
		return
	_order(sim, u, {"type": ORDER_MOVE, "x": x, "y": y, "facing": face, "width": width,
		"run": run, "ground": 1}, 1 + k % 8)


## (BattleAI._attack, without the caracole riders' charge flag: the ambush
## has no riders.)
static func _attack(sim, u: int, t: int, run: int) -> void:
	_order(sim, u, {"type": ORDER_ATTACK, "target": t, "run": run, "ground": 1}, 0)
