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
##
## The native ambush (P_AMBUSH, docs/AI.md 44.5) and the Swedish salvo
## (P_SALVO, docs/AI.md 44.6): their own sections below.

const FM := preload("res://sim/fixed_math.gd")
const UT := preload("res://sim/unit_types.gd")
const AP := preload("res://sim/ai_profile.gd")

const M := 1024
const ALL := -1                 # every play (the default of a scenario without "ai_plays")
const P_TERCIO := 0             # bit 0: the tercio (docs/AI.md 44.1)
const P_COUNTERMARCH := 1       # bit 1: the countermarch (docs/AI.md 44.2; its own build)
const P_AMBUSH := 2             # bit 2: the native ambush (docs/AI.md 44.5)
const P_SALVO := 3              # bit 3: the Swedish salvo (docs/AI.md 44.6)
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
const SV_SLACK := 3 * M         # the salvo: a line within SALVO_FIRE_R + this of the target (box to box) is at the range
const SV_BEHIND := 6 * M        # ... the melee foot stand this far behind the lines' rear rank
const SV_WING := 10 * M         # ... the horse stand this far out beyond the outer line's end, level with the lines
const SV_HOLD_T := 600          # ... a walk that has not reached the range in this long (60 s) is given up (reset)
const SV_CLOSE := 40 * M        # ... an enemy charging a salvo line within this (the countermarch's CM_CLOSE): it fires now
const SV_GRACE := 30            # ... a line that has not fired SALVO_WAIT_T + this after the order is left out of it (3 s)

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
const ORDER_HALT := 3
const ORDER_ABILITY := 28
const AI_PLAYER_BASE := 100
const A_LINE := 0
const A_ATTACK := 1
const A_RETIRE := 7
const A_GUARD := 10
const A_RESV := 31
const A_WORKS := 32

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
const PS_SV := 14               # the salvo: 0 not chosen, 1 running, 2 dropped
const PS_SV_PH := 15            # ... its phase: SV_LOOK, SV_HOLD, SV_FIRE, SV_CHARGE
const PS_SV_T := 16             # ... the tick the phase began
const PS_SV_SEEN := 17          # ... the tick its trigger last held (or a salvo ran)
const PS_SV_TGT := 18           # ... the target + 1
const PS_SV_L := 19             # ... the two musket lines + 1 (19, 20; 0 none or lost)
const PS_SV_F := 21             # ... the melee foot + 1 (21, 22)
const PS_SV_H := 23             # ... the horse + 1
const PS_SV_A := 24             # ... each line's shots left at the fire order (24, 25); -1 fired (or left out)
const PS_K := 26

# The ambush's parts (PU_ROLE) and states (PU_STATE), its phases (PS_AMB_PH).
const R_HIDE := 4               # hidden in the main wood
const R_BAIT := 5               # the bait (out in front, or falling back)
const R_FLANK := 6              # hidden in the flank wood (AMBUSH_FLANK)
const R_SKIRM := 7              # missile foot once sprung: the woods' skirmishers (no chase, no melt; hidden again in a new cycle)
const AS_HIDE := 0              # hiding (the bait: standing out)
const AS_FIGHT := 1             # sprung (the bait: falling back)
const AS_MELT := 2              # melting back to its hiding post
const AP_WAIT := 1              # lying in wait, the bait out
const AP_PULL := 2              # the bait falling back
const AP_SPRUNG := 3            # sprung; a melted unit springs again on its own

# The salvo's phases (PS_SV_PH).
const SV_LOOK := 0              # running, no target: the next one the trigger finds
const SV_HOLD := 1              # the lines walk to SALVO_FIRE_R, fire held, the countermarch on Hold
const SV_FIRE := 2              # the fire order given: each line fires every loaded man at once
const SV_CHARGE := 3            # the foot and horse (and on Skilled the lines, with the butt) charge


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
	if kn[AP.SALVO] != 0 and (sim.ai_plays[side] >> P_SALVO) & 1 != 0:
		_sv_army(sim, side, kn)


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
	var sd: int = sim.u_side[u]
	if _ps(sim, sd, PS_SV) == 1 and _ps(sim, sd, PS_SV_PH) != SV_LOOK and sim.u_ai[u] != A_RETIRE \
			and sim.u_ai[u] != A_GUARD:
		var part := sv_part(sim, sd, u)
		if part != 0:
			return _sv_unit(sim, u, part)
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
# once (the sim's ambush strike rewards the first volley or contact); sprung
# missile foot stay in the woods as skirmishers (R_SKIRM). A sprung melee
# unit that has fought AMBUSH_FIGHT_T, is out of a melee and is not winning
# melts back to its post; with every unit home again a new bait goes out. Skilled
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
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and _pm(sim, u, PU_ROLE) >= R_HIDE \
				and _pm(sim, u, PU_ROLE) != R_SKIRM:
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
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_state[u] == U_READY and _pm(sim, u, PU_ROLE) == R_SKIRM \
				and _d(sim.u_ax[u] - _pm(sim, u, PU_X), sim.u_ay[u] - _pm(sim, u, PU_Y)) <= AMB_RUN_R:
			_pmset(sim, u, PU_ROLE, R_HIDE)  # (hidden again for the new cycle)
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
		elif _pm(sim, u, PU_STATE) != AS_HIDE or _pm(sim, u, PU_ROLE) == R_SKIRM:
			continue
		_amb_go(sim, u)


## Unit u springs: the nearest enemy it sees (else the nearest), a charge for
## melee foot; missile foot fire at will and become the woods' skirmishers
## (R_SKIRM, _amb_skirm: they never close, melt or spring again; chasing
## and the melt-spring cycle got bow and sling bands ridden down in the
## open, docs/AI.md 44.5).
static func _amb_go(sim, u: int) -> void:
	var side: int = sim.u_side[u]
	if sim.u_cls[u] == UT.CLS_MISSILE:
		# (missile foot: the woods' skirmishers from now on, R_SKIRM)
		_pmset(sim, u, PU_ROLE, R_SKIRM)
		_pmset(sim, u, PU_STATE, AS_HIDE)
		_order(sim, u, {"type": ORDER_FIRE, "on": 1}, 21)
		_order(sim, u, {"type": ORDER_SKIRMISH, "on": 1}, 20)
		return
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
	if r == R_SKIRM:
		return _amb_skirm(sim, u, kn, hx, hy, face)
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


## A sprung missile foot unit (R_SKIRM): a skirmisher about its post, skirmish
## on (the sim's loose order, fall-back and woods drift) and fire at will at
## what comes in range; it never closes on a target, melts or springs again.
## With an enemy it sees within AMBUSH_PULL_R it is left where its fall-back
## took it; with none, back to its post (run when over AMB_RUN_R away), and
## at its post when a new cycle begins it hides in the line again (R_HIDE).
## Caught in a melee: the ordinary rules.
static func _amb_skirm(sim, u: int, kn: PackedInt32Array, hx: int, hy: int, face: int) -> bool:
	if sim.u_fighting[u] > 0:
		return false
	if sim.u_skirm[u] == 0:
		_order(sim, u, {"type": ORDER_SKIRMISH, "on": 1}, 20)
	if sim.u_fire[u] == 0:
		_order(sim, u, {"type": ORDER_FIRE, "on": 1}, 21)
	if not _enemy_within(sim, u, kn[AP.AMBUSH_PULL_R]):
		var dh := _d(sim.u_ax[u] - hx, sim.u_ay[u] - hy)
		if dh >= AMB_HOME_R:
			_move(sim, u, hx, hy, face, _width(sim, u), 1 if dh > AMB_RUN_R else 0, 3)
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


# ---------------------------------------------------------------- salvo ---
# The Swedish salvo (P_SALVO, docs/AI.md 44.6; knob SALVO): Gustavus
# Adolphus's drill. Running from the first army think whose trigger holds (a
# field battle; the side has two musket lines and a melee foot or horse unit
# free; an enemy foot unit stands within SALVO_RANGE_R, box to box, in front
# of one of its musket lines and is not charging it), a salvo at a time: the
# two lines nearest the target set the countermarch to Hold, fire held, and
# walk to SALVO_FIRE_R of it, the nearest melee foot (two at most) a rank
# behind them and the nearest horse on the outer flank (SV_HOLD); at the
# range (or charged within SV_CLOSE, or in contact) each line is ordered at
# the target and fires every loaded man in one volley (a line still
# reloading waits SALVO_WAIT_T for the fuller volley, then the countermarch's
# Auto fires what is loaded: its last volley, SV_FIRE); the tick after the
# last line's volley the foot and horse charge it, and the lines too with the
# butt (SALVO_MUSKET_CHARGE; else they reload and fire at will: SV_CHARGE).
# SALVO_RESET_T after the charge, or when the target routs, the lines go back
# to Auto (the rolling fire) and the next target may be taken (SV_LOOK). The
# play is dropped for good when the side has fewer than two musket lines or
# no melee unit, or no target has been found for PLAY_DROP_T. The memory is
# the side's (PS_SV_*): the tercio's layout rewrites every unit's PU_* each
# line order, so the salvo keeps its units there, never in PU_*.

## The salvo is running for side `side` with a target (not SV_LOOK).
static func salvo_on(sim, side: int) -> bool:
	return has_mem(sim) and _ps(sim, side, PS_SV) == 1 and _ps(sim, side, PS_SV_PH) != SV_LOOK


## Unit u's part in its side's salvo: 1 a musket line, 2 melee foot, 3 the
## horse; 0 none.
static func sv_part(sim, side: int, u: int) -> int:
	for k in 2:
		if _ps(sim, side, PS_SV_L + k) == u + 1:
			return 1
		if _ps(sim, side, PS_SV_F + k) == u + 1:
			return 2
	return 3 if _ps(sim, side, PS_SV_H) == u + 1 else 0


## A unit of the side free for the salvo: ready, not a wagon or character,
## not mauled, guarding, held in reserve or manning works, not in a melee.
static func _sv_free(sim, u: int) -> bool:
	var a: int = sim.u_ai[u]
	return sim.u_state[u] == U_READY and not _skip(sim, u) and a != A_RETIRE and a != A_GUARD and a != A_RESV \
		and a != A_WORKS and sim.u_fighting[u] == 0


## A musket line free for the salvo (gun foot with shots left).
static func _sv_line(sim, u: int) -> bool:
	return _gun_foot(sim, u) and sim.u_ammo[u] > 0 and _sv_free(sim, u)


## Melee foot (pikes, line or shock foot) or horse (not the general) free for it.
static func _sv_melee(sim, u: int) -> bool:
	var c: int = sim.u_cls[u]
	return (c == UT.CLS_PIKE or c == UT.CLS_INF or c == UT.CLS_CAV) and UT.stat(sim.u_type[u], "cmd_r") <= 0 \
		and _sv_free(sim, u)


## The side's ready musket lines (gun foot with shots, not mauled) and melee
## units (the drop's count: a line or unit in a melee counts).
static func _sv_have(sim, side: int) -> Vector2i:
	var g := 0
	var m := 0
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY or _skip(sim, u) or sim.u_ai[u] == A_RETIRE:
			continue
		var c: int = sim.u_cls[u]
		if _gun_foot(sim, u) and sim.u_ammo[u] > 0:
			g += 1
		elif (c == UT.CLS_PIKE or c == UT.CLS_INF or c == UT.CLS_CAV) and UT.stat(sim.u_type[u], "cmd_r") <= 0:
			m += 1
	return Vector2i(g, m)


## The salvo's trigger: its target, or -1. A field battle (no settlement, no
## town plan); two free musket lines and a free melee unit; an enemy foot
## unit (line or shock foot, pikes, a musket line) the side sees, ready and
## not in a melee, within SALVO_RANGE_R (box to box) in front of one of the
## free lines and not charging it. The nearest such pair, in index order.
static func salvo_target(sim, side: int, kn: PackedInt32Array) -> int:
	if sim.city_on != 0:
		return -1
	var city = sim.map_info.get("city", null)
	if city is Dictionary and int((city as Dictionary).get("tp", 0)) != 0:
		return -1
	var lines: Array = []
	var melee := false
	for u in sim.n_units:
		if sim.u_side[u] != side:
			continue
		if _sv_line(sim, u):
			lines.append(u)
		elif _sv_melee(sim, u):
			melee = true
	if lines.size() < 2 or not melee:
		return -1
	var best := -1
	var bd := 0
	for o in sim.n_units:
		if sim.u_side[o] == side or sim.u_state[o] != U_READY or _skip(sim, o) or sim.u_fighting[o] > 0:
			continue
		var c: int = sim.u_cls[o]
		if not (c == UT.CLS_INF or c == UT.CLS_PIKE or _gun_foot(sim, o)) or sim.hidden_from(o, side):
			continue
		for l in lines:
			var d: int = sim._box_gap(l, o)
			if d > kn[AP.SALVO_RANGE_R] or (best >= 0 and d >= bd):
				continue
			if sim.u_order[o] == O_ATTACK and sim.u_target[o] == l:
				continue  # (charging it: the countermarch's last volley meets it)
			var f: int = sim.u_face[l]
			if (sim.u_cx[o] - sim.u_ax[l]) * FM.cos_a(f) + (sim.u_cy[o] - sim.u_ay[l]) * FM.sin_a(f) <= 0:
				continue  # (not in front of it)
			best = o
			bd = d
	return best


## Each army think while the salvo bit and knob are on: start, the posts,
## the reset and the drop (the volley and the charge: salvo_tick).
static func _sv_army(sim, side: int, kn: PackedInt32Array) -> void:
	var st := _ps(sim, side, PS_SV)
	if st != 0:
		_sv_auto(sim, side)
	if st == 2:
		return
	if st == 1:
		var hv := _sv_have(sim, side)
		if hv.x < 2 or hv.y == 0:
			_sv_reset(sim, side, true)
			return
	var ph := _ps(sim, side, PS_SV_PH)
	if st == 0 or ph == SV_LOOK:
		if _ps(sim, side, PS_AMB) == 1:
			return  # (never while the side lies in ambush)
		var nt := salvo_target(sim, side, kn)
		if st == 1 and nt < 0:
			if sim.tick - _ps(sim, side, PS_SV_SEEN) >= PLAY_DROP_T:
				_sv_reset(sim, side, true)
			return
		if nt < 0:
			return
		_psset(sim, side, PS_SV, 1)
		_sv_begin(sim, side, kn, nt)
		return
	_psset(sim, side, PS_SV_SEEN, sim.tick)
	var t := _ps(sim, side, PS_SV_TGT) - 1
	_sv_prune(sim, side)
	var any := false
	for k in 2:
		if _ps(sim, side, PS_SV_L + k) != 0:
			any = true
	if t < 0 or sim.u_state[t] != U_READY or (not any and ph != SV_CHARGE):
		_sv_reset(sim, side, false)
		return
	if ph == SV_HOLD:
		if sim.tick - _ps(sim, side, PS_SV_T) >= SV_HOLD_T:
			_sv_reset(sim, side, false)  # (it never got there: the target went back)
			return
		_sv_posts(sim, side, kn, t)
	elif ph == SV_CHARGE and sim.tick - _ps(sim, side, PS_SV_T) >= kn[AP.SALVO_RESET_T]:
		_sv_reset(sim, side, false)


## The countermarch back to Auto on every ready musket line of the side
## that is not one of a salvo's under way (a line routing at the reset could
## not take the order; the AI never sets Hold otherwise, docs/AI.md 44.2).
static func _sv_auto(sim, side: int) -> void:
	var on := _ps(sim, side, PS_SV) == 1 and _ps(sim, side, PS_SV_PH) != SV_LOOK
	for u in sim.n_units:
		if sim.u_side[u] != side or sim.u_state[u] != U_READY or not _gun_foot(sim, u) or u >= sim.u_abs.size():
			continue
		if ((sim.u_abs[u] >> (UT.AB_ROLL * 2)) & 3) == UT.AB_HOLD and not (on and sv_part(sim, side, u) == 1):
			_order(sim, u, {"type": ORDER_ABILITY, "ability": UT.AB_ROLL, "state": UT.AB_AUTO, "target": -1}, 29)


## A salvo begins at target t: the two free lines nearest it, the two free
## melee foot and the free horse nearest it; the lines' countermarch to Hold,
## fire held; the posts.
static func _sv_begin(sim, side: int, kn: PackedInt32Array, t: int) -> void:
	for k in range(PS_SV_TGT, PS_K):
		_psset(sim, side, k, 0)
	_psset(sim, side, PS_SV_PH, SV_HOLD)
	_psset(sim, side, PS_SV_T, sim.tick)
	_psset(sim, side, PS_SV_SEEN, sim.tick)
	_psset(sim, side, PS_SV_TGT, t + 1)
	var picked := {}
	for k in 2:
		var l := _sv_nearest(sim, side, t, 0, picked)
		if l >= 0:
			picked[l] = true
			_psset(sim, side, PS_SV_L + k, l + 1)
	for k in 2:
		var f := _sv_nearest(sim, side, t, 1, picked)
		if f >= 0:
			picked[f] = true
			_psset(sim, side, PS_SV_F + k, f + 1)
	var h := _sv_nearest(sim, side, t, 2, picked)
	if h >= 0:
		_psset(sim, side, PS_SV_H, h + 1)
	sim.stat_aic[side * AP.N_COUNTERS + AP.C_PLAY_SALVO] += 1
	for k in 2:
		var l := _ps(sim, side, PS_SV_L + k) - 1
		if l >= 0:
			_order(sim, l, {"type": ORDER_ABILITY, "ability": UT.AB_ROLL, "state": UT.AB_HOLD, "target": -1}, 29)
			if sim.u_fire[l] != 0:
				_order(sim, l, {"type": ORDER_FIRE, "on": 0}, 21)
	_sv_posts(sim, side, kn, t)


## The free unit of kind k (0 a musket line, 1 melee foot, 2 horse) nearest
## target t (box to box; index order), not in `picked`; -1 none.
static func _sv_nearest(sim, side: int, t: int, k: int, picked: Dictionary) -> int:
	var best := -1
	var bd := 0
	for u in sim.n_units:
		if sim.u_side[u] != side or picked.has(u):
			continue
		if k == 0:
			if not _sv_line(sim, u):
				continue
		elif not _sv_melee(sim, u) or (sim.u_cls[u] == UT.CLS_CAV) != (k == 2):
			continue
		var d: int = sim._box_gap(u, t)
		if best < 0 or d < bd:
			best = u
			bd = d
	return best


## Units lost to the salvo (gone, routing, mauled, guarding) leave it.
static func _sv_prune(sim, side: int) -> void:
	for k in range(PS_SV_L, PS_SV_H + 1):
		var u := _ps(sim, side, k) - 1
		if u >= 0 and (sim.u_state[u] != U_READY or sim.u_ai[u] == A_RETIRE or sim.u_ai[u] == A_GUARD \
				or (k < PS_SV_F and sim.u_ammo[u] <= 0)):
			_psset(sim, side, k, 0)
			if k < PS_SV_F:
				_psset(sim, side, PS_SV_A + k - PS_SV_L, -1)


## The salvo's posts (each army think while the lines walk): the lines side
## by side, LINE_GAP apart, their front SALVO_FIRE_R short of the target's
## box along the line from their middle to it, facing it; the melee foot
## SV_BEHIND behind a line's rear rank (one foot unit: behind the middle);
## the horse SV_WING out beyond the line's end on its own side, level.
static func _sv_posts(sim, side: int, kn: PackedInt32Array, t: int) -> void:
	var gap := kn[AP.LINE_GAP]
	var ls: Array = []
	for k in 2:
		var l := _ps(sim, side, PS_SV_L + k) - 1
		if l >= 0:
			ls.append(l)
	if ls.is_empty():
		return
	var mx := 0
	var my := 0
	for l in ls:
		mx += sim.u_ax[l]
		my += sim.u_ay[l]
	mx /= ls.size()
	my /= ls.size()
	var dx: int = sim.u_cx[t] - mx
	var dy: int = sim.u_cy[t] - my
	var d := _d(dx, dy)
	if d <= 0:
		return
	var face := FM.atan2_a(dy, dx)
	var fx := FM.cos_a(face)
	var fy := FM.sin_a(face)
	var rx := -fy
	var ry := fx
	var ext: int = (absi(fx) * (sim.u_maxx[t] - sim.u_minx[t]) / 2 + absi(fy) * (sim.u_maxy[t] - sim.u_miny[t]) / 2) / FM.TRIG_ONE
	var back := ext + kn[AP.SALVO_FIRE_R]
	var px: int = sim.u_cx[t] - fx * back / FM.TRIG_ONE
	var py: int = sim.u_cy[t] - fy * back / FM.TRIG_ONE
	if ls.size() == 2:
		var la: int = ((sim.u_ax[ls[0]] - mx) * rx + (sim.u_ay[ls[0]] - my) * ry) / FM.TRIG_ONE
		var lb: int = ((sim.u_ax[ls[1]] - mx) * rx + (sim.u_ay[ls[1]] - my) * ry) / FM.TRIG_ONE
		if lb < la:
			ls = [ls[1], ls[0]]
	# Lateral offsets (left to right) and the lines' half span.
	var lats: Array = []
	var span := 0
	if ls.size() == 2:
		var w0 := _width(sim, ls[0])
		var w1 := _width(sim, ls[1])
		lats = [-(w0 / 2 + gap / 2), w1 / 2 + gap / 2]
		span = (w0 + gap + w1) / 2
	else:
		lats = [0]
		span = _width(sim, ls[0]) / 2
	var deep := 0
	for k in ls.size():
		var l: int = ls[k]
		var lat: int = lats[k]
		deep = maxi(deep, _depth(sim, l))
		_sv_go(sim, l, px + rx * lat / FM.TRIG_ONE, py + ry * lat / FM.TRIG_ONE, face, 0)
	var foot: Array = []
	for k in 2:
		var f := _ps(sim, side, PS_SV_F + k) - 1
		if f >= 0:
			foot.append(f)
	if foot.size() == 2:
		var fa: int = ((sim.u_ax[foot[0]] - mx) * rx + (sim.u_ay[foot[0]] - my) * ry) / FM.TRIG_ONE
		var fb: int = ((sim.u_ax[foot[1]] - mx) * rx + (sim.u_ay[foot[1]] - my) * ry) / FM.TRIG_ONE
		if fb < fa:
			foot = [foot[1], foot[0]]
	var fb2 := deep + SV_BEHIND
	for k in foot.size():
		var lat: int = lats[k] if foot.size() == ls.size() else 0
		_sv_go(sim, foot[k], px + (rx * lat - fx * fb2) / FM.TRIG_ONE, py + (ry * lat - fy * fb2) / FM.TRIG_ONE, face, 2)
	var h := _ps(sim, side, PS_SV_H) - 1
	if h >= 0:
		var hl: int = ((sim.u_ax[h] - mx) * rx + (sim.u_ay[h] - my) * ry) / FM.TRIG_ONE
		var sg := -1 if hl < 0 else 1
		var lat: int = sg * (span + SV_WING + _width(sim, h) / 2)
		_sv_go(sim, h, px + rx * lat / FM.TRIG_ONE, py + ry * lat / FM.TRIG_ONE, face, 4)


## A salvo unit to its post at the walk (clamped into the field).
static func _sv_go(sim, u: int, x: int, y: int, face: int, k: int) -> void:
	_move(sim, u, clampi(x, 4 * M, sim.field_w - 4 * M), clampi(y, 4 * M, sim.field_h - 4 * M), face, _width(sim, u), 0, k)


## Every tick (BattleAI.think) for an AI side whose salvo runs with a
## target: the walk's end (each line at the range, or one charged within
## SV_CLOSE or in contact: the fire order), the volley (each line's shots
## falling; a line not loaded by SALVO_WAIT_T: the countermarch to Auto, its
## last volley fires what is loaded) and, the tick after the last line has
## fired, the charge.
static func salvo_tick(sim, side: int) -> void:
	if _ps(sim, side, PS_SV) != 1:
		return
	var ph := _ps(sim, side, PS_SV_PH)
	if ph != SV_HOLD and ph != SV_FIRE:
		return
	var t := _ps(sim, side, PS_SV_TGT) - 1
	if t < 0 or sim.u_state[t] != U_READY:
		return  # (the army think resets it)
	var kn := AP.of(sim, side)
	if ph == SV_HOLD:
		var at := true
		var now := false
		var n := 0
		for k in 2:
			var l := _ps(sim, side, PS_SV_L + k) - 1
			if l < 0 or sim.u_state[l] != U_READY:
				continue
			n += 1
			var gp: int = sim._box_gap(l, t)
			if gp > kn[AP.SALVO_FIRE_R] + SV_SLACK and not (sim.u_order[l] == O_NONE and gp <= kn[AP.SALVO_RANGE_R] \
					and sim.tick - _ps(sim, side, PS_SV_T) >= 20):
				at = false
			if sim.u_fighting[l] > 0 or sim.u_contact[l] != 0 or _sv_charged(sim, l):
				now = true
		if n == 0 or not (at or now):
			return
		_psset(sim, side, PS_SV_PH, SV_FIRE)
		_psset(sim, side, PS_SV_T, sim.tick)
		for k in 2:
			var l := _ps(sim, side, PS_SV_L + k) - 1
			if l < 0 or sim.u_state[l] != U_READY:
				_psset(sim, side, PS_SV_A + k, -1)
				continue
			_psset(sim, side, PS_SV_A + k, sim.u_ammo[l])
			_attack(sim, l, t, 0)
		return
	# SV_FIRE: the volleys.
	var dt: int = sim.tick - _ps(sim, side, PS_SV_T)
	var left := false
	for k in 2:
		var a := _ps(sim, side, PS_SV_A + k)
		if a < 0:
			continue
		var l := _ps(sim, side, PS_SV_L + k) - 1
		if l < 0 or sim.u_state[l] != U_READY:
			_psset(sim, side, PS_SV_A + k, -1)
			continue
		if sim.u_ammo[l] < a:
			_psset(sim, side, PS_SV_A + k, -1)  # (fired: every loaded man at once)
			sim.stat_aic[side * AP.N_COUNTERS + AP.C_SALVO_VOLLEY] += 1
			continue
		if dt >= kn[AP.SALVO_WAIT_T] + SV_GRACE:
			_psset(sim, side, PS_SV_A + k, -1)  # (nothing fired: left out)
			continue
		if dt == kn[AP.SALVO_WAIT_T]:
			# Still reloading: the countermarch's Auto fires every loaded man
			# at once (its last volley within CM_CLOSE).
			_order(sim, l, {"type": ORDER_ABILITY, "ability": UT.AB_ROLL, "state": UT.AB_AUTO, "target": -1}, 29)
		left = true
	if left:
		return
	_sv_charge(sim, side, kn, t)


## An enemy foot or horse unit charging salvo line l (an attack order on it)
## within SV_CLOSE.
static func _sv_charged(sim, l: int) -> bool:
	for o in sim.n_units:
		if sim.u_side[o] == sim.u_side[l] or sim.u_state[o] != U_READY or sim.u_order[o] != O_ATTACK \
				or sim.u_target[o] != l or sim.u_cls[o] == UT.CLS_MISSILE or sim.u_cls[o] == UT.CLS_ART:
			continue
		if sim._box_gap(o, l) <= SV_CLOSE:
			return true
	return false


## The charge: the foot and horse at the target at the run; the lines too
## with the butt (SALVO_MUSKET_CHARGE), else they reload and fire at will
## (the countermarch stays on Hold until the reset).
static func _sv_charge(sim, side: int, kn: PackedInt32Array, t: int) -> void:
	_psset(sim, side, PS_SV_PH, SV_CHARGE)
	_psset(sim, side, PS_SV_T, sim.tick)
	sim.stat_aic[side * AP.N_COUNTERS + AP.C_SALVO_CHARGE] += 1
	for k in range(PS_SV_L, PS_SV_H + 1):
		var u := _ps(sim, side, k) - 1
		if u < 0 or sim.u_state[u] != U_READY:
			continue
		if k < PS_SV_F:
			if sim.u_ai[u] != A_RETIRE:
				_order(sim, u, {"type": ORDER_ABILITY, "ability": UT.AB_ROLL, "state": UT.AB_HOLD, "target": -1}, 29)
			if kn[AP.SALVO_MUSKET_CHARGE] != 0:
				_butt_attack(sim, u, t)
			else:
				_order(sim, u, {"type": ORDER_FIRE, "on": 1}, 21)
		else:
			_sv_attack(sim, u, t)
		if sim.u_cls[u] != UT.CLS_CAV and sim.u_ai[u] == A_LINE:
			sim.u_ai[u] = A_ATTACK
			sim.u_ai_t[u] = sim.tick


## The end of a salvo (`drop` false: the next target may be taken) or of the
## play (true): the lines back to Auto (the countermarch), the foot in the
## fight (A_ATTACK), the units back to the ordinary rules.
static func _sv_reset(sim, side: int, drop: bool) -> void:
	for k in 2:
		var l := _ps(sim, side, PS_SV_L + k) - 1
		if l >= 0 and sim.u_state[l] == U_READY:
			_order(sim, l, {"type": ORDER_ABILITY, "ability": UT.AB_ROLL, "state": UT.AB_AUTO, "target": -1}, 29)
	for k in 2:
		var f := _ps(sim, side, PS_SV_F + k) - 1
		if f >= 0 and sim.u_state[f] == U_READY and sim.u_ai[f] == A_LINE:
			sim.u_ai[f] = A_ATTACK
			sim.u_ai_t[f] = sim.tick
	for k in range(PS_SV_TGT, PS_K):
		_psset(sim, side, k, 0)
	_psset(sim, side, PS_SV_PH, SV_LOOK)
	_psset(sim, side, PS_SV_T, sim.tick)
	_psset(sim, side, PS_SV_SEEN, sim.tick)
	if drop:
		_psset(sim, side, PS_SV, 2)


## _issue_line's slots while a salvo runs: its units are the play's.
static func salvo_slots(sim, side: int, slots: Dictionary) -> void:
	for k in range(PS_SV_L, PS_SV_H + 1):
		var u := _ps(sim, side, k) - 1
		if u >= 0:
			slots.erase(u)


## Each unit think of a unit with a part in its side's running salvo. True
## if the play gave it its orders (the ordinary rules are skipped).
static func _sv_unit(sim, u: int, part: int) -> bool:
	var side: int = sim.u_side[u]
	var ph := _ps(sim, side, PS_SV_PH)
	var t := _ps(sim, side, PS_SV_TGT) - 1
	if t < 0 or sim.u_state[t] != U_READY:
		return false
	if ph == SV_HOLD:
		if part == 1:
			if sim.u_fire[u] != 0:
				_order(sim, u, {"type": ORDER_FIRE, "on": 0}, 21)
			return true
		return sim.u_fighting[u] == 0  # (caught: the ordinary rules fight)
	if ph == SV_FIRE:
		return part == 1 or sim.u_fighting[u] == 0
	# SV_CHARGE
	var kn := AP.of(sim, side)
	if part == 1:
		if kn[AP.SALVO_MUSKET_CHARGE] == 0:
			return false  # (reloading, fire at will: the ordinary rules)
		if sim.u_fighting[u] == 0 and not (sim.u_order[u] == O_ATTACK and sim.u_target[u] == t and sim._butt(u)):
			_butt_attack(sim, u, t)
		return true
	if sim.u_fighting[u] > 0:
		return false
	if sim.u_order[u] != O_ATTACK or sim.u_target[u] != t:
		_sv_attack(sim, u, t)
	return true


## The charge of the salvo's foot or horse at t, at the run; riders charge
## home ("charge" 1: a caracole row does not ride a pass at it).
static func _sv_attack(sim, u: int, t: int) -> void:
	var o := {"type": ORDER_ATTACK, "target": t, "run": 1, "ground": 1}
	if sim.u_cls[u] == UT.CLS_CAV:
		o["charge"] = 1
	_order(sim, u, o, 0)


## A musket line's charge with the butt (BattleSim._butt: the attack order
## with "butt" 1 closes it to contact as shock foot).
static func _butt_attack(sim, u: int, t: int) -> void:
	_order(sim, u, {"type": ORDER_ATTACK, "target": t, "run": 1, "ground": 1, "butt": 1}, 0)


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
