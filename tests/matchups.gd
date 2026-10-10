extends SceneTree
## Scripted balance matchups (headless regression tool).
##   godot --headless --script res://tests/matchups.gd [-- --seeds=20 --only=pike]
## Each matchup is run over many seeds; prints win rates and average losses.
## Side 0 is always listed first. No AI: orders are scripted.
##
## Targets (docs/DESIGN.md, milestone 2):
##   pikes beat equal-cost swords frontally, lose clearly in flank/rear;
##   a rear cavalry charge breaks or cripples an engaged infantry unit;
##   a frontal charge into braced spears/pikes costs the cavalry heavily;
##   cavalry destroys unprotected archers; archers hurt light troops, do
##   little to heavy shielded infantry from the front, more from flank/rear;
##   no type dominant everywhere; a 2,000 AI battle is decided in ~4-9 min;
##   bolt throwers' full ammunition along a pike block's depth kills roughly
##   15-25% of it and much less of a wide heavy line from the front; stone
##   throwers kill fewer, frighten, and miss small or moving targets; melee
##   troops that reach artillery wreck it quickly; armies stay fair when
##   mirrored (--fair=N; --fair-variants=fort0,fort1 puts that side in its
##   fortified camp: the fitted CData.FORTIFY_DEF_PCT); --only=crossing-fort
##   the same at a ford and a bridge (Scenarios.crossing, side 1 holding).
## Yardsticks (--only=yard, docs/STATUS.md "Field rebalance"): a full load
##   of arrows at 100 m into light infantry or standing cavalry in the open
##   kills about a quarter, into heavy shielded foot from the front under
##   10 %; javelins' load into cavalry 15-25 %, into heavy foot 5-10 %;
##   slingers about two thirds of the archers' kills on unarmoured men,
##   far less on armour; scorpions between archers and bolt throwers on a
##   pike block; bolts pin an advancing unit (it is slowed, not shrugging);
##   camels beat cavalry, elephants break a line and are routed by
##   javelins, dogs run down skirmishers but not heavy foot, light horse
##   loses to archers, a general's aura holds a line, stakes stop a
##   charge, mantlets screen archers.
## Terrain (--only=terrain): holding good high ground against an equal unit
##   is a clear but beatable edge (~60-70% on a moderate slope, more on
##   steep ground); archers on a hill outrange archers below; cavalry hits
##   harder downhill and weaker uphill; flat bolts do not shoot through a
##   crest; a mirror-symmetric map stays even; AI battles on every terrain
##   kind are decided in ~4-9 minutes. --fair=N --fair-terrain=K runs the
##   mirrored battles on a mirror-symmetric generated map of kind K.
## Woods and settlements (--only=maps): woods blunt charges and arrows and
##   break up pike walls; dense woods block flat throws; pikes in a street
##   cannot be flanked and cavalry there has no run-up; gates fall to
##   batteries in a minute or two and to foot more slowly; an open town
##   falls easily to a competent attacker, a level 3 wall needs artillery
##   or a big edge, nothing is impregnable; AI settlement battles end in
##   12 minutes or less, without draws.
## Equal-force sieges (--only=fair-sieges, docs/STATUS.md item 4): a city
##   held by a garrison and field army as strong as the attacker, walls 1-3,
##   ring and polis, with ladders and a ram, artillery only or the full kit
##   of a three-turn siege (row 2); --rows,
##   --walls, --plans shard it, --time-limit=S sets the battle time limit and
##   --tune=NAME=v0,v1,v2,v3 sets a siege lever of BattleSim for the run.
## Skill levels (docs/AI.md 6): --skill=A:B (levels e, a, s or 0, 1, 2) with
##   --fair=N runs the mirrored bench_2000 battles with side 0 at level A
##   and side 1 at B, then swapped (each orientation, so a top / bottom bias
##   cancels), and prints the wins per level, the mirrored bias, durations
##   and the AI's per-competency counters per level ("SKILL" lines; shard
##   with --seed0). With --only=sieges / plans it sets the attacker (A) and
##   the defender (B) of the settlement battles (the plans then also print
##   the Skilled siege moves). --fair-forest=N puts N % woods on the
##   mirrored maps (mirror-symmetric). Tuning aid: --knob=LEVEL:ID=VALUE
##   overrides one knob (sim/ai_profile.gd id) of a level for the run
##   (repeatable), e.g. --knob=s:178=0 runs Skilled without its reserve
##   cavalry (docs/AI.md 11 ablations).

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const AP := preload("res://sim/ai_profile.gd")
const MapGen := preload("res://sim/mapgen.gd")
const FM := preload("res://sim/fixed_math.gd")

const UP := Scenarios.FACE_UP
const DOWN := Scenarios.FACE_DOWN
const LEFT := Scenarios.FACE_LEFT
const ATTACK := BattleSim.ORDER_ATTACK
const M := BattleSim.M

var seeds := 20
var only := ""
var max_ticks := 3000
var fair_n := 0       # --fair=N: only the mirrored-fairness check, N seeds
var seed0 := 0        # --seed0=K: first seed index (for sharding --fair runs)
var fair_variants: Array = ["side0_first", "side1_first"]  # --fair-variants=a,b
var fair_terrain := -1  # --fair-terrain=K: mirrored battles on a symmetric map of kind K
var plans_only: Array = []  # --plans=0,4: settlement plans to run (--only=sieges / plans)
var walls_only: Array = []  # --walls=3: wall levels to run (--only=sieges / plans)
var skill: Array = []       # --skill=A:B: AI skill of side 0 / attacker and side 1 / defender
var fair_forest := 0        # --fair-forest=N: woods coverage N on the mirrored maps (--fair with --skill)
var rows_only: Array = []   # --rows=0,1: fair-sieges rows to run (0 ladders + ram, 1 artillery only, 2 full kit)
var time_limit := 0         # --time-limit=S: battle time limit (s) for the settlement sets (0: default)


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.get_slice("=", 1))
		elif a.begins_with("--only="):
			only = a.get_slice("=", 1)
		elif a.begins_with("--fair="):
			fair_n = int(a.get_slice("=", 1))
		elif a.begins_with("--seed0="):
			seed0 = int(a.get_slice("=", 1))
		elif a.begins_with("--fair-variants="):
			fair_variants = Array(a.get_slice("=", 1).split(","))
		elif a.begins_with("--fair-terrain="):
			fair_terrain = int(a.get_slice("=", 1))
		elif a.begins_with("--walls="):
			for v in a.get_slice("=", 1).split(","):
				walls_only.append(int(v))
		elif a.begins_with("--plans="):
			for v in a.get_slice("=", 1).split(","):
				plans_only.append(int(v))
		elif a.begins_with("--skill="):
			for v in a.get_slice("=", 1).split(":"):
				skill.append(_level(v))
		elif a.begins_with("--fair-forest="):
			fair_forest = int(a.get_slice("=", 1))
		elif a.begins_with("--rows="):
			for v in a.get_slice("=", 1).split(","):
				rows_only.append(int(v))
		elif a.begins_with("--time-limit="):
			time_limit = int(a.get_slice("=", 1))
		elif a.begins_with("--tune="):
			# Tuning aid: --tune=NAME=v0,v1,v2,v3 sets a siege lever of BattleSim
			# (static: WALL_COVER, WALL_RANGE_PCT, GATE_HACK_BY_WALLS, GATE_HP_PCT,
			# LADDER_TICKS, TOWERS_MAX, TOWERS_STONE, GATE_FIRE_CHIP; RAM_DMG,
			# ROUT_INWARD and TOWN_PLACE_LEAD (decimetres) one value).
			_tune(a.get_slice("=", 1), a.get_slice("=", 2))
		elif a.begins_with("--knob="):
			# Tuning aid: --knob=LEVEL:ID=VALUE overrides one knob of a level
			# (all personalities) for this run, e.g. --knob=s:9=0.
			var kv := a.get_slice("=", 1) + "=" + a.get_slice("=", 2)
			var lv := _level(kv.get_slice(":", 0))
			var id := int(kv.get_slice(":", 1).get_slice("=", 0))
			var val := int(kv.get_slice("=", 1))
			AP.row(lv, AP.BALANCED)
			for y in 3:
				var r: PackedInt32Array = AP._tab[lv * 3 + y]
				r[id] = val
				AP._tab[lv * 3 + y] = r
	var t0 := Time.get_ticks_msec()
	if fair_n > 0 and skill.size() == 2:
		_skill_fair(fair_n)
		quit(0)
		return
	if fair_n > 0:
		_fairness(fair_n)
		quit(0)
		return
	if only == "wall-yard":
		_wall_yards()
		quit(0)
		return
	if only == "wall-col":
		_wall_cols()
		quit(0)
		return
	if only == "tiers":
		_tiers()
		quit(0)
		return
	if only == "crossing-fort":
		_section("River crossings: side 1 holds the far bank (Scenarios.crossing), equal armies, AI vs AI, both Average")
		_crossing_fort()
		quit(0)
		return
	if only == "fair-sieges":
		_section("Equal-force sieges (a city, garrison + field army = the attacker's strength), AI vs AI")
		_fair_sieges()
		print("\n(done in %.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
		quit(0)
		return
	if only == "sieges" or only == "plans":
		if only == "sieges":
			_section("Garrison-only defence (town, garrison 3 + walls units of 60) vs the standard 12-unit attacker, AI vs AI")
			_garrison_defence()
			_section("AI vs AI settlement battles (garrison + a 4-unit field army defending)")
			_siege_battles()
		_section("Settlement plans, AI vs AI (a city: garrison + a 4-unit field army vs the standard attacker)")
		_plan_sieges()
		quit(0)
		return
	if only == "maps":
		_maps()
		print("\n(done in %.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
		quit(0)
		return
	_section("Pikes")
	_duel("pike 120 holds vs heavy 100 attacking (front)",
		[_u(0, UT.PIKE, 120, 150, 200, UP), _u(1, UT.HEAVY, 100, 150, 140, DOWN)],
		[_atk(0, 1, 0, 0)])
	_duel("pike 120 advancing into heavy 100 holding (front)",
		[_u(0, UT.PIKE, 120, 150, 200, UP), _u(1, UT.HEAVY, 100, 150, 140, DOWN)],
		[_atk(0, 0, 1, 0)])
	_duel("pike 120 vs light 150 attacking (front)",
		[_u(0, UT.PIKE, 120, 150, 200, UP), _u(1, UT.LIGHT, 150, 150, 140, DOWN, 30)],
		[_atk(0, 1, 0, 0)])
	_duel("pike 120 vs heavy 100 from the flank",
		[_u(0, UT.PIKE, 120, 150, 160, UP), _u(1, UT.HEAVY, 100, 215, 160, LEFT)],
		[_atk(0, 1, 0, 0)])
	_duel("pike 120 vs heavy 100 from the rear",
		[_u(0, UT.PIKE, 120, 150, 160, UP), _u(1, UT.HEAVY, 100, 150, 215, UP)],
		[_atk(0, 1, 0, 0)])
	_duel("pike 120 pinned by heavy 100, light 100 into flank",
		[_u(0, UT.PIKE, 120, 150, 170, UP), _u(1, UT.HEAVY, 100, 150, 130, DOWN),
			_u(1, UT.LIGHT, 100, 215, 180, LEFT)],
		[_atk(0, 1, 0, 0), _atk(150, 2, 0, 0)])
	_section("Cavalry")
	_duel("heavy vs heavy, no cavalry (control)",
		[_u(0, UT.HEAVY, 100, 150, 170, UP), _u(1, UT.HEAVY, 100, 150, 140, DOWN)],
		[_atk(0, 1, 0, 0)], 1)
	_duel("heavy vs heavy, cav 60 hits the enemy rear at 20 s",
		[_u(0, UT.HEAVY, 100, 150, 170, UP), _u(0, UT.CAVALRY, 60, 150, 70, DOWN),
			_u(1, UT.HEAVY, 100, 150, 140, DOWN)],
		[_atk(0, 2, 0, 0), _atk(200, 1, 2, 1)], 2)
	_duel("cav 60 charges braced spears 100 (front)",
		[_u(0, UT.CAVALRY, 60, 150, 220, UP), _u(1, UT.SPEAR, 100, 150, 110, DOWN)],
		[_atk(0, 0, 1, 1)])
	_duel("cav 60 charges braced pikes 120 (front)",
		[_u(0, UT.CAVALRY, 60, 150, 220, UP), _u(1, UT.PIKE, 120, 150, 110, DOWN)],
		[_atk(0, 0, 1, 1)])
	_duel("cav 60 charges heavy 100 standing (front)",
		[_u(0, UT.CAVALRY, 60, 150, 220, UP), _u(1, UT.HEAVY, 100, 150, 110, DOWN)],
		[_atk(0, 0, 1, 1)])
	_duel("cav 60 charges spears 100 in the rear",
		[_u(0, UT.CAVALRY, 60, 150, 220, UP), _u(1, UT.SPEAR, 100, 150, 140, UP)],
		[_atk(0, 0, 1, 1)])
	_duel("cav 60 vs archers 80 (archers shoot first)",
		[_u(0, UT.CAVALRY, 60, 150, 250, UP), _u(1, UT.ARCHER, 80, 150, 90, DOWN)],
		[_atk(0, 0, 1, 1)])
	_duel("cav 60 charge, pull out, charge again vs heavy 100 (front)",
		[_u(0, UT.CAVALRY, 60, 150, 220, UP), _u(1, UT.HEAVY, 100, 150, 110, DOWN)],
		_cycle_charge(0, 1))
	_section("Missiles (archers shoot all their arrows at a unit that stands still)")
	_volley("archers 80 vs light 100 (front)", UT.LIGHT, DOWN)
	_volley("archers 80 vs heavy 100 (front)", UT.HEAVY, DOWN)
	_volley("archers 80 vs heavy 100 (rear)", UT.HEAVY, UP)
	_volley("archers 80 vs pikes 120 (front)", UT.PIKE, DOWN)
	_volley("archers 80 vs cav 60 (front)", UT.CAVALRY, DOWN)
	_duel("javelins 150 vs light 100 attacking them",
		[_u(0, UT.JAVELIN, 150, 150, 200, UP, 30), _u(1, UT.LIGHT, 100, 150, 120, DOWN)],
		[_atk(0, 1, 0, 0), _atk(0, 0, 1, 0)])
	_section("Cavalry charge obliquity: front-rank riders who deliver an impact (vs heavy 100 standing)")
	for deg in [0, 30, 60]:
		_oblique(deg)
	_section("Archers vs cavalry")
	_arch_cav("cav 60 charges archers 80 head-on from max range", "charge")
	_arch_cav("cav 60 standing 100 m from archers 80 (60 s)", "stand")
	_arch_cav("cav 60 walking across 100-130 m from archers 80 (60 s)", "walk")
	_arch_cav("cav 60 charges from the flank, archers shooting infantry", "flank")
	_arch_cav("cav 60 charges from behind, archers shooting infantry", "rear")
	_section("Casualties when a unit breaks: mirror fight, both attack frontally")
	_rout_losses()
	_section("Equal cost (600), both attack: row side wins %")
	_round_robin()
	_section("Artillery")
	_artillery()
	_yardsticks()
	_section("Stone aim: where stones land relative to the target formation")
	_stone_aim()
	_section("Mirrored fairness: identical units face each other, both attack (bottom side 0 vs top side 1, both unit orders)")
	_mirror_duels()
	_section("Full battle")
	_full_battles()
	_section("Terrain")
	_terrain()
	print("\n(done in %.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


func _tune(name: String, vals: String) -> void:
	var arr: Array[int] = []
	for v in vals.split(","):
		arr.append(int(v))
	match name:
		"WALL_COVER":
			BattleSim.WALL_COVER = arr
		"WALL_RANGE_PCT":
			BattleSim.WALL_RANGE_PCT = arr
		"GATE_HACK_BY_WALLS":
			BattleSim.GATE_HACK_BY_WALLS = arr
		"GATE_HP_PCT":
			BattleSim.GATE_HP_PCT = arr
		"LADDER_TICKS":
			BattleSim.LADDER_TICKS = arr
		"TOWERS_MAX":
			BattleSim.TOWERS_MAX = arr
		"TOWERS_STONE":
			BattleSim.TOWERS_STONE = arr
		"RAM_DMG":
			BattleSim.RAM_DMG = arr[0]
		"ROUT_INWARD":
			BattleSim.ROUT_INWARD = arr[0]
		"TOWN_PLACE_LEAD":
			BattleSim.TOWN_PLACE_LEAD = arr[0] * BattleSim.M / 10
		"GATE_FIRE_CHIP":
			BattleSim.GATE_FIRE_CHIP = arr
		_:
			push_error("unknown lever " + name)
	print("TUNE %s = %s" % [name, str(arr)])


func _section(title: String) -> void:
	print("\n=== ", title)


func _u(side: int, ty: int, count: int, x: int, y: int, face: int, files: int = -1) -> Dictionary:
	return Scenarios.unit(side, ty, count, x, y, face, files)


func _atk(tick: int, u: int, t: int, run: int) -> Dictionary:
	return {"tick": tick, "type": ATTACK, "unit": u, "target": t, "run": run}


## Charge, pull back 40 m after 6 s of melee, charge again (three times).
func _cycle_charge(cav: int, target: int) -> Array:
	var o: Array = [_atk(0, cav, target, 1)]
	var t := 190
	for k in 3:
		o.append({"tick": t, "type": BattleSim.ORDER_MOVE, "unit": cav, "x": 150 * 1024,
			"y": 200 * 1024, "facing": UP, "width": 30 * 1024, "run": 1})
		o.append(_atk(t + 120, cav, target, 1))
		t += 260
	return o


func _scenario(units: Array, orders: Array, extra: Dictionary = {}) -> Dictionary:
	var sc := {"width_m": 300, "height_m": 300, "ai_sides": [], "units": units, "orders": orders}
	for k in extra:
		sc[k] = extra[k]
	return sc


func _skip(name: String) -> bool:
	return only != "" and name.find(only) < 0


## Run a scripted duel over the seeds. `focus` >= 0 reports that unit's
## fate in detail (rout tick, losses).
func _duel(name: String, units: Array, orders: Array, focus: int = -1, extra: Dictionary = {}) -> void:
	if _skip(name):
		return
	var wins := [0, 0, 0]
	var lost := [0.0, 0.0]
	var start := [0, 0]
	var t_sum := 0.0
	var focus_rout := 0.0
	var focus_routed := 0
	var focus_loss := 0.0
	for s in seeds:
		var sim := BattleSim.new()
		sim.setup(_scenario(units, orders, extra), 1000 + s * 7919)
		var routed_at := -1
		while sim.tick < max_ticks and sim.ended == 0:
			sim.step()
			if focus >= 0 and routed_at < 0 and sim.u_state[focus] != BattleSim.U_READY:
				routed_at = sim.tick
				focus_loss += 100.0 * sim.u_killed[focus] / sim.u_count0[focus]
		var w: int = sim.winner if sim.winner >= 0 else 2
		wins[w] += 1
		t_sum += (sim.decided_tick if sim.decided_tick >= 0 else sim.tick) / 10.0
		var r: Dictionary = sim.result()
		for side in 2:
			var sd: Dictionary = r["sides"][side]
			start[side] = int(sd["started"])
			lost[side] += int(sd["killed"])
		if routed_at >= 0:
			focus_rout += routed_at / 10.0
			focus_routed += 1
	var line := "%-58s side0 wins %3d%%  side1 %3d%%  draw %3d%%  | killed %5.1f/%d vs %5.1f/%d | decided %5.1f s" % [
		name, wins[0] * 100 / seeds, wins[1] * 100 / seeds, wins[2] * 100 / seeds,
		lost[0] / seeds, start[0], lost[1] / seeds, start[1], t_sum / seeds]
	if focus >= 0:
		line += " | unit %d broke in %d/%d runs" % [focus, focus_routed, seeds]
		if focus_routed > 0:
			line += " at %.1f s with %.0f%% killed" % [focus_rout / focus_routed, focus_loss / focus_routed]
	print(line)


## Archers shoot everything at a target 110 m away that just stands there.
func _volley(name: String, ty: int, face: int) -> void:
	if _skip(name):
		return
	var killed := 0.0
	var wounded_hp := 0.0
	var shots := 0.0
	var hits := 0.0
	var count: int = Scenarios.SIZE[ty]
	for s in seeds:
		var sim := BattleSim.new()
		sim.setup(_scenario([_u(0, UT.ARCHER, 80, 150, 200, UP), _u(1, ty, count, 150, 90, face)], []), 1000 + s * 7919)
		while sim.tick < 1200 and (sim.u_ammo[0] > 0 or sim.projectiles_in_flight() > 0):
			sim.step()
		killed += sim.u_killed[1]
		shots += sim.stat_shots
		hits += sim.stat_missile_hits
		var hp_left := 0
		for i in sim.n:
			if sim.unit_of[i] == 1 and sim.state[i] < BattleSim.S_DEAD:
				hp_left += sim.hp[i]
		wounded_hp += sim.u_alive[1] * UT.stat(ty, "hp") - hp_left
	print("%-58s killed %5.1f of %d | wounds on survivors %6.0f hp | %4.0f shots, %4.0f hits (%.0f%%)" % [
		name, killed / seeds, count, wounded_hp / seeds, shots / seeds, hits / seeds,
		100.0 * hits / maxf(shots, 1.0)])


## Equal-cost unit of each type (cost 600).
func _equal(ty: int) -> int:
	return 600 / UT.stat(ty, "cost")


func _round_robin() -> void:
	if only != "" and only != "rr":
		return
	var types := [UT.HEAVY, UT.LIGHT, UT.SPEAR, UT.PIKE, UT.ARCHER, UT.JAVELIN, UT.CAVALRY]
	var header := "%-9s" % ""
	for b in types:
		header += "%9s" % UT.TYPES[b]["short"]
	print(header)
	var n := maxi(seeds / 2, 4)
	for a in types:
		var line := "%-9s" % UT.TYPES[a]["short"]
		for b in types:
			if a == b:
				line += "%9s" % "-"
				continue
			var wins := 0
			for s in n:
				var units := [_u(0, a, _equal(a), 150, 200, UP, _files(a)),
					_u(1, b, _equal(b), 150, 100, DOWN, _files(b))]
				var orders := [_atk(0, 0, 1, 0), _atk(0, 1, 0, 0), _atk(60, 0, 1, 1), _atk(60, 1, 0, 1)]
				var sim := BattleSim.new()
				sim.setup(_scenario(units, orders), 5000 + s * 104729)
				while sim.tick < max_ticks and sim.winner < 0:
					sim.step()
				if sim.winner == 0:
					wins += 2
				elif sim.winner != 1:
					wins += 1  # draw counts half
			line += "%8d%%" % (wins * 50 / n)
		print(line)


## Same frontage for every foot unit (bigger units stand deeper), so the
## table compares troop types rather than overlap.
func _skip_section(key: String) -> bool:
	return only != "" and only != key


## Fraction of the cavalry front rank that delivers an impact, charging a
## standing heavy unit with the cavalry approaching `deg` degrees off the
## enemy's front normal.
func _oblique(deg: int) -> void:
	if _skip_section("oblique"):
		return
	var frac := 0.0
	var lost := 0.0
	for s in seeds:
		var a := deg_to_rad(deg)
		var tx := 150.0
		var ty := 120.0
		var cx := int(tx + 80.0 * sin(a))
		var cy := int(ty + 80.0 * cos(a))
		var face := int(round(atan2(ty - cy, tx - cx) * 1024.0 / TAU)) & 1023
		var units := [_u(0, UT.CAVALRY, 60, cx, cy, face), _u(1, UT.HEAVY, 100, int(tx), int(ty), DOWN)]
		var sim := BattleSim.new()
		sim.setup(_scenario(units, [_atk(0, 0, 1, 1)]), 3000 + s * 131)
		var files: int = mini(sim.u_files[0], sim.u_alive[0])
		var front: Array = []
		for i in sim.n:
			if sim.unit_of[i] == 0 and sim.slot_of[i] < files:
				front.append(i)
		while sim.tick < 400:
			sim.step()
		var hit := 0
		for i in front:
			if sim.dbg_impacted[i] != 0:
				hit += 1
		frac += float(hit) / front.size()
		lost += sim.u_killed[1]
	print("%2d degrees off the front: %3.0f%% of front-rank riders impact; infantry killed %.1f by 40 s" % [
		deg, 100.0 * frac / seeds, lost / seeds])


func _arch_cav(name: String, mode: String) -> void:
	if _skip_section("archcav"):
		return
	var before := 0.0
	var total := 0.0
	var reached := 0
	var arch_lost := 0.0
	for s in seeds:
		var units: Array
		var orders: Array = []
		# Archers (side 0) at the bottom, cavalry (side 1) above them, so
		# each side's own map edge is behind it.
		match mode:
			"charge":
				units = [_u(0, UT.ARCHER, 80, 150, 240, UP), _u(1, UT.CAVALRY, 60, 150, 95, DOWN)]
				orders = [_atk(0, 1, 0, 1)]
			"stand":
				units = [_u(0, UT.ARCHER, 80, 150, 240, UP), _u(1, UT.CAVALRY, 60, 150, 140, DOWN)]
			"walk":
				units = [_u(0, UT.ARCHER, 80, 150, 240, UP), _u(1, UT.CAVALRY, 60, 40, 130, 0)]
				orders = [{"tick": 0, "type": BattleSim.ORDER_MOVE, "unit": 1, "x": 260 * 1024,
					"y": 125 * 1024, "facing": 0, "width": 30 * 1024, "run": 0}]
			"flank":
				units = [_u(0, UT.ARCHER, 80, 150, 180, UP), _u(1, UT.CAVALRY, 60, 20, 185, 0),
					_u(1, UT.HEAVY, 100, 150, 75, DOWN)]
				orders = [_atk(0, 0, 2, 0), _atk(30, 1, 0, 1)]
			"rear":
				units = [_u(0, UT.ARCHER, 80, 150, 170, UP), _u(1, UT.CAVALRY, 60, 150, 285, UP),
					_u(1, UT.HEAVY, 100, 150, 65, DOWN)]
				orders = [_atk(0, 0, 2, 0), _atk(30, 1, 0, 1)]
		var sim := BattleSim.new()
		sim.setup(_scenario(units, orders), 7000 + s * 977)
		var contact := -1
		var limit := 600 if mode == "stand" or mode == "walk" else 900
		while sim.tick < limit:
			sim.step()
			if contact < 0 and (sim.u_fighting[1] > 0 or sim.stat_impacts + sim.stat_reflects > 0):
				contact = sim.tick
				before += sim.u_killed[1]
				reached += 1
		total += sim.u_killed[1]
		arch_lost += sim.u_killed[0]
	var line := "%-58s riders killed %4.1f of 60" % [name, total / seeds]
	if mode != "stand" and mode != "walk":
		line += " (%4.1f before contact, %d/%d reached); archers killed %4.1f of 80" % [
			before / maxi(reached, 1), reached, seeds, arch_lost / seeds]
	print(line)


## Mirror fights per type: casualties of the side that breaks first, at the
## moment it breaks (percent of its start strength).
func _rout_losses() -> void:
	if _skip_section("rout"):
		return
	for ty in [UT.HEAVY, UT.SPEAR, UT.PIKE, UT.LIGHT, UT.CAVALRY, UT.ARCHER, UT.JAVELIN]:
		var loss := 0.0
		var win_loss := 0.0
		var broke := 0
		var secs := 0.0
		var cnt: int = Scenarios.SIZE[ty]
		for s in seeds:
			var units := [_u(0, ty, cnt, 150, 200, UP, _files(ty)), _u(1, ty, cnt, 150, 100, DOWN, _files(ty))]
			var orders := [_atk(0, 0, 1, 0), _atk(0, 1, 0, 0), _atk(60, 0, 1, 1), _atk(60, 1, 0, 1)]
			var sim := BattleSim.new()
			sim.setup(_scenario(units, orders), 9000 + s * 613)
			while sim.tick < max_ticks:
				sim.step()
				var b := -1
				for u in 2:
					if sim.u_state[u] != BattleSim.U_READY:
						b = u
				if b >= 0:
					loss += 100.0 * sim.u_killed[b] / cnt
					win_loss += 100.0 * sim.u_killed[1 - b] / cnt
					secs += sim.tick / 10.0
					broke += 1
					break
		print("%-8s breaks with %4.0f%% killed (winner has lost %4.0f%%), after %5.1f s; %d/%d fights broke" % [
			UT.TYPES[ty]["short"], loss / maxi(broke, 1), win_loss / maxi(broke, 1), secs / maxi(broke, 1), broke, seeds])


func _files(ty: int) -> int:
	if ty == UT.CAVALRY:
		return 15
	if ty == UT.JAVELIN:
		return 20
	return 25


func _full_battles() -> void:
	if only != "" and only != "full":
		return
	var n := maxi(seeds / 2, 4)
	var times: Array[float] = []
	var wins := [0, 0, 0]
	var t0 := Time.get_ticks_msec()
	for s in n:
		var sim := BattleSim.new()
		sim.setup(Scenarios.make("bench_2000"), 77 + s * 31)
		while sim.tick < 12000 and sim.winner < 0:
			sim.step()
		times.append(sim.tick / 600.0)
		wins[sim.winner if sim.winner >= 0 else 2] += 1
	times.sort()
	var sum := 0.0
	for t in times:
		sum += t
	print("bench_2000 AI vs AI over %d seeds: decided after %.1f min mean (min %.1f, max %.1f); wins %d / %d, draws %d (%.0f s wall)" % [
		n, sum / n, times[0], times[n - 1], wins[0], wins[1], wins[2],
		(Time.get_ticks_msec() - t0) / 1000.0])


## Mirrored fairness: the two armies of bench_2000 are 180-degree mirror
## images, so over many seeds each side should win about half. Run twice:
## with the scenario's unit order (side 0's units first) and with side 1's
## units listed first, which separates index-order effects (who is processed
## first) from geometric or per-side code (top vs bottom).
## Prints machine-readable "FAIR" lines so sharded runs can be summed.
func _fairness(n: int) -> void:
	for variant in fair_variants:
		var wins := [0, 0, 0]
		var killed := [0, 0]
		var mins := 0.0
		var max_min := 0.0
		for k in n:
			var s := seed0 + k
			var scn := Scenarios.make("bench_2000")
			var drop := []
			if variant.begins_with("nocav"):
				drop = [UT.CAVALRY]
			elif variant.begins_with("nomis"):
				drop = [UT.ARCHER, UT.JAVELIN]
			elif variant.begins_with("noart"):
				drop = [UT.BOLT, UT.STONE]
			elif variant.begins_with("foot"):
				drop = [UT.CAVALRY, UT.ARCHER, UT.JAVELIN, UT.BOLT, UT.STONE]
			if not drop.is_empty():
				var keep: Array = []
				for u in scn["units"]:
					if not (int(u["type"]) in drop):
						keep.append(u)
				scn["units"] = keep
			if variant.begins_with("shift"):
				# Move both armies off the 4 m grid cell boundaries.
				for u in scn["units"]:
					u["y_m"] = int(u["y_m"]) + 2
			if variant.ends_with("side1_first"):
				var us: Array = scn["units"]
				var a: Array = []
				for u in us:
					if int(u["side"]) == 1:
						a.append(u)
				for u in us:
					if int(u["side"]) == 0:
						a.append(u)
				scn["units"] = a
			if fair_terrain >= 0:
				scn["terrain"] = {"kind": fair_terrain, "sym": 1}
			if variant.begins_with("fort"):
				# fort0 / fort1: that side stands in its fortified camp (the
				# campaign's fortify stance; CData.FORTIFY_DEF_PCT is fitted to it).
				scn["fortified"] = int(variant.substr(4, 1))
			var sim := BattleSim.new()
			sim.setup(scn, 77 + s * 31)
			while sim.tick < 12000 and sim.winner < 0:
				sim.step()
			wins[sim.winner if sim.winner >= 0 else 2] += 1
			var dt: float = (sim.decided_tick if sim.decided_tick >= 0 else sim.tick) / 600.0
			mins += dt
			max_min = maxf(max_min, dt)
			var r: Dictionary = sim.result()
			for side in 2:
				killed[side] += int(r["sides"][side]["killed"])
		print("FAIR %s n=%d bottom(side0)=%d top(side1)=%d draw=%d killed0=%d killed1=%d minutes_sum=%.1f max=%.1f" % [
			variant, n, wins[0], wins[1], wins[2], killed[0], killed[1], mins, max_min])


## --only=crossing-fort: the equal armies of Scenarios.crossing (side 1
## holding the far bank) at a ford and at a bridge, the holder fortified
## (its camp at the crossing's mouth) or not, `seeds` crossings each (the
## crossing's seed 100 + k): the holder's wins, the attacker's, draws and
## minutes. Fits CData.FORTIFY_DEF_PCT at a crossing (docs/CAMPAIGN.md).
func _crossing_fort() -> void:
	var n := mini(seeds, 10)
	for kind in [0, 1]:
		for fort in [false, true]:
			var w := [0, 0, 0]
			var mins := 0.0
			var killed := [0, 0]
			for k in n:
				var sc := Scenarios.crossing(kind, 100 + seed0 + k, fort)
				var sim := BattleSim.new()
				sim.setup(sc, 4242 + 31 * (seed0 + k))
				while sim.tick < 12000 and sim.winner < 0:
					sim.step()
				w[sim.winner if sim.winner >= 0 and sim.winner < 2 else 2] += 1
				mins += (sim.decided_tick if sim.decided_tick >= 0 else sim.tick) / 600.0
				var r: Dictionary = sim.result()
				for side in 2:
					killed[side] += int(r["sides"][side]["killed"])
			print("CROSS %-6s holder %-10s n=%d holder=%d attacker=%d draw=%d | %4.1f min | killed att %d def %d" % [
				["ford", "bridge"][kind], "fortified" if fort else "open", n, w[1], w[0], w[2], mins / n,
				killed[0] / n, killed[1] / n])


## "e" / "a" / "s" (or 0 / 1 / 2) to a skill level.
static func _level(v: String) -> int:
	match v.to_lower().substr(0, 1):
		"e", "0":
			return AP.EASY
		"s", "2":
			return AP.SKILLED
	return AP.AVERAGE


## Settlement scenarios with --skill: attacker (side 0) A, defender B.
func _with_skill(sc: Dictionary) -> void:
	if skill.size() == 2:
		sc["ai_skill"] = [skill[0], skill[1]]


## --fair=N --skill=A:B: the mirrored bench_2000 battles (flat, or the
## symmetric map of --fair-terrain) with side 0 at level A and side 1 at B,
## then the same seeds swapped. Prints per orientation and in total the wins
## of each level, draws, minutes to decide, and the per-competency counters
## summed per level (AP.COUNTER_NAMES). "SKILL" lines sum across shards.
func _skill_fair(n: int) -> void:
	var la: int = skill[0]
	var lb: int = skill[1]
	var names := ["A=%s" % AP.SKILL_NAMES[la], "B=%s" % AP.SKILL_NAMES[lb]]
	var cnt: Array = []  # per level A, B (plain arrays: packed ones are values)
	for lv in 2:
		var row: Array = []
		row.resize(AP.N_COUNTERS)
		row.fill(0)
		cnt.append(row)
	var tot := [0, 0, 0]  # wins of A, of B, draws
	var mins := 0.0
	var max_min := 0.0
	var withdrew := [0, 0]
	for orient in 2:
		var wins := [0, 0, 0]  # A, B, draw
		for k in n:
			var s := seed0 + k
			var scn := Scenarios.make("bench_2000")
			if fair_terrain >= 0 or fair_forest > 0:
				scn["terrain"] = {"kind": maxi(fair_terrain, 0), "sym": 1}
				if fair_forest > 0:
					scn["terrain"]["forest"] = fair_forest
					scn["terrain"]["seed"] = 900 + s
			var a_side := 0 if orient == 0 else 1
			var sk := [la, lb] if orient == 0 else [lb, la]
			scn["ai_skill"] = sk
			var sim := BattleSim.new()
			sim.setup(scn, 77 + s * 31)
			while sim.tick < 12000 and sim.winner < 0:
				sim.step()
			var w: int = sim.winner
			if w == a_side:
				wins[0] += 1
			elif w == 1 - a_side:
				wins[1] += 1
			else:
				wins[2] += 1
			var dt: float = (sim.decided_tick if sim.decided_tick >= 0 else sim.tick) / 600.0
			mins += dt
			max_min = maxf(max_min, dt)
			for side in 2:
				var lv := 0 if side == a_side else 1
				if sim.ai_phase[side] == 3:
					withdrew[lv] += 1
				for c in AP.N_COUNTERS:
					cnt[lv][c] += sim.stat_aic[side * AP.N_COUNTERS + c]
		print("SKILL orient=%d terrain=%d n=%d %s(side %d) wins=%d %s(side %d) wins=%d draws=%d" % [
			orient, fair_terrain, n, names[0], 0 if orient == 0 else 1, wins[0], names[1], 1 if orient == 0 else 0,
			wins[1], wins[2]])
		for x in 3:
			tot[x] += wins[x]
	print("SKILL total terrain=%d n=%d %s wins=%d %s wins=%d draws=%d minutes_sum=%.1f max=%.1f withdrew=%d,%d" % [
		fair_terrain, 2 * n, names[0], tot[0], names[1], tot[1], tot[2], mins, max_min, withdrew[0], withdrew[1]])
	for lv in 2:
		var parts: Array = []
		for c in AP.N_COUNTERS:
			parts.append("%s=%d" % [AP.COUNTER_NAMES[c], cnt[lv][c]])
		print("SKILLCOUNT terrain=%d %s %s" % [fair_terrain, names[lv], " ".join(parts)])


## Artillery set pieces: (name, units, orders, ticks, mode).
func _artillery() -> void:
	if only != "" and only != "art" and only != "artillery":
		return
	var PI_ := UT.PIKE
	_art_run("bolts 16 (4 engines) vs pikes 120 standing, front, 150 m",
		[_u(0, UT.BOLT, 16, 150, 250, UP), _u(1, PI_, 120, 150, 100, DOWN)], [], 900, 1)
	_art_run("bolts 16 vs heavy 100 standing, front, 150 m",
		[_u(0, UT.BOLT, 16, 150, 250, UP), _u(1, UT.HEAVY, 100, 150, 100, DOWN)], [], 900, 1)
	_art_run("bolts 16 vs pikes 120 standing, shot from the flank",
		[_u(0, UT.BOLT, 16, 280, 95, LEFT, 4), _u(1, PI_, 120, 130, 100, DOWN)], [], 900, 1)
	_art_run("stones 18 (3 engines) vs massed line (heavy, spear, heavy), 200 m",
		[_u(0, UT.STONE, 18, 150, 270, UP), _u(1, UT.HEAVY, 100, 89, 70, DOWN),
			_u(1, UT.SPEAR, 100, 150, 70, DOWN), _u(1, UT.HEAVY, 100, 211, 70, DOWN)], [], 2200, 1)
	_art_run("stones 18 vs pikes 120 standing, 200 m",
		[_u(0, UT.STONE, 18, 150, 270, UP), _u(1, PI_, 120, 150, 70, DOWN)], [], 2200, 1)
	_art_run("stones 18 vs javelins 60 (loose) standing, 200 m",
		[_u(0, UT.STONE, 18, 150, 270, UP), _u(1, UT.JAVELIN, 60, 150, 70, DOWN)], [], 2200, 1)
	_art_run("stones 18 vs cav 60 walking across 180-200 m",
		[_u(0, UT.STONE, 18, 150, 280, UP), _u(1, UT.CAVALRY, 60, 20, 90, 0)],
		[{"tick": 0, "type": BattleSim.ORDER_MOVE, "unit": 1, "x": 280 * 1024, "y": 90 * 1024,
			"facing": 0, "width": 30 * 1024, "run": 0}], 2200, 1)
	_art_run("light 100 attacks bolts 16 from 120 m (engines wrecked)",
		[_u(0, UT.BOLT, 16, 150, 230, UP), _u(1, UT.LIGHT, 100, 150, 110, DOWN)],
		[_atk(0, 1, 0, 1)], 900, 2)
	_art_run("cav 60 charges stones 18 from 230 m (engines wrecked)",
		[_u(0, UT.STONE, 18, 150, 270, UP), _u(1, UT.CAVALRY, 60, 150, 40, DOWN)],
		[_atk(0, 1, 0, 1)], 900, 2)
	_art_run("duel: bolts 16 vs stones 18 at 200 m",
		[_u(0, UT.BOLT, 16, 150, 260, UP), _u(1, UT.STONE, 18, 150, 60, DOWN)], [], 1800, 3)
	_art_run("duel: stones 18 vs stones 18 at 220 m",
		[_u(0, UT.STONE, 18, 150, 270, UP), _u(1, UT.STONE, 18, 150, 50, DOWN)], [], 1800, 3)
	# Equal cost: bolts (400) + stones (540) = 940 vs heavy 100 (600) + archers 68 (340).
	_art_run("duel: stones 18 vs bolts 16 at 260 m (out of bolt range)",
		[_u(0, UT.STONE, 18, 150, 280, UP), _u(1, UT.BOLT, 16, 150, 20, DOWN)], [], 2200, 3)
	_duel("artillery: bolts + stones (940) vs heavy 100 + archers 68 (940), all attack",
		[_u(0, UT.BOLT, 16, 120, 250, UP), _u(0, UT.STONE, 18, 180, 265, UP),
			_u(1, UT.HEAVY, 100, 150, 70, DOWN), _u(1, UT.ARCHER, 68, 150, 85, DOWN)],
		[_atk(0, 2, 0, 0), _atk(0, 3, 1, 0)])


## mode 1: kills over the battery's full ammunition (and peak fright);
## 2: time from first contact until every engine is wrecked; 3: duel.
func _art_run(name: String, units: Array, orders: Array, ticks: int, mode: int) -> void:
	if only != "" and only != "art" and name.find(only) < 0:
		return
	var killed := 0.0
	var shots := 0.0
	var victims := 0.0
	var fright := 0.0
	var routed := 0
	var wreck_t := 0.0
	var wrecked_all := 0
	var lost0 := 0.0
	var lost1 := 0.0
	var eng0 := 0.0
	var eng1 := 0.0
	var start: int = 0
	for s in seeds:
		var sim := BattleSim.new()
		sim.setup(_scenario(units, orders), 4000 + s * 1031)
		start = 0
		for u in sim.n_units:
			if sim.u_side[u] == 1:
				start += sim.u_count0[u]
		var contact := -1
		var peak := 0
		while sim.tick < ticks and sim.ended == 0:
			sim.step()
			for u in sim.n_units:
				if sim.u_side[u] == 1:
					peak = maxi(peak, sim.u_fright[u])
			if mode == 1 and sim.u_ammo[0] <= 0 and sim.projectiles_in_flight() == 0:
				break
			if mode == 2:
				if contact < 0 and sim.u_contact[0] != 0:
					contact = sim.tick
				var ok := 0
				for e in sim.n_eng:
					if sim.e_state[e] == BattleSim.E_OK:
						ok += 1
				if ok == 0:
					wreck_t += (sim.tick - maxi(contact, 0)) / 10.0
					wrecked_all += 1
					break
		var k1 := 0
		for u in sim.n_units:
			if sim.u_side[u] == 1:
				k1 += sim.u_killed[u]
				if sim.u_state[u] != BattleSim.U_READY:
					routed += 1
		killed += k1
		lost0 += sim.u_killed[0]
		lost1 += k1
		shots += sim.stat_bolts + sim.stat_stones
		victims += sim.stat_art_victims
		fright += peak
		for e in sim.n_eng:
			if sim.e_state[e] == BattleSim.E_OK:
				if sim.u_side[sim.e_unit[e]] == 0:
					eng0 += 1
				else:
					eng1 += 1
	var n := float(seeds)
	match mode:
		1:
			print("%-62s killed %5.1f of %d (%4.1f%%) | %4.1f shots, %4.1f struck | peak fright %3.0f | units broke %d" % [
				name, killed / n, start, 100.0 * killed / n / start, shots / n, victims / n, fright / n, routed])
		2:
			print("%-62s all engines wrecked in %d/%d runs, %.1f s after contact | attackers lost %.1f, crews lost %.1f" % [
				name, wrecked_all, seeds, wreck_t / maxi(wrecked_all, 1), lost1 / n, lost0 / n])
		3:
			print("%-62s crews lost %4.1f vs %4.1f | engines left %.1f vs %.1f | shots %.1f" % [
				name, lost0 / n, lost1 / n, eng0 / n, eng1 / n, shots / n])


## Mirrored duels per type, run with side 0's unit listed first and then
## with side 1's first, so a win-rate gap shows either a geometric (top /
## bottom) or a processing-order bias. Over 2 x seeds runs each; for a real
## check use --fair=N (full mirrored AI battles) or many --seeds.
func _mirror_duels() -> void:
	if _skip_section("mirror"):
		return
	for ty in [UT.HEAVY, UT.LIGHT, UT.PIKE, UT.ARCHER, UT.CAVALRY]:
		var bottom := 0
		var top := 0
		var first := 0
		for swap in [false, true]:
			for s in seeds:
				var f := 15 if ty == UT.CAVALRY else 25
				var cnt: int = Scenarios.SIZE[ty]
				var units := [_u(0, ty, cnt, 150, 200, UP, f), _u(1, ty, cnt, 150, 100, DOWN, f)]
				var orders := [_atk(0, 0, 1, 0), _atk(0, 1, 0, 0), _atk(60, 0, 1, 1), _atk(60, 1, 0, 1)]
				if swap:
					units = [units[1], units[0]]
				var sim := BattleSim.new()
				sim.setup(_scenario(units, orders), 20000 + s * 7)
				while sim.tick < max_ticks and sim.winner < 0:
					sim.step()
				if sim.winner == 0 or sim.winner == 1:
					if sim.winner == 0:
						bottom += 1
					else:
						top += 1
					# Unit listed first won?
					if (sim.winner == 0) != swap:
						first += 1
		var n := 2 * seeds
		print("%-8s bottom wins %3d%%  top %3d%%  | unit listed first wins %3d%%  (%d runs)" % [
			UT.TYPES[ty]["short"], bottom * 100 / n, top * 100 / n, first * 100 / n, n])


# --------------------------------------------------------------- terrain ---

const Terrain := preload("res://sim/terrain.gd")
const RAMP_UP_TOP := 768     # ramp rising toward the top of the field (side 1)
const RAMP_UP_BOTTOM := 256  # ... toward the bottom (side 0)


func _scenario_t(units: Array, orders: Array, features: Array) -> Dictionary:
	var sc := _scenario(units, orders)
	sc["terrain"] = {"kind": Terrain.K_CUSTOM, "features": features}
	return sc


## A slope across the whole 300 m field, steepest (grade_pct) through the
## middle third where the units meet, rising toward `dir`.
func _ramp(grade_pct: int, dir: int) -> Array:
	# Smoothstep over 2r = 300 m: steepest grade 1.5 * h / 300.
	return [[Terrain.F_RAMP, 150, 150, 150, grade_pct * 300 / 150, dir]]


func _terrain() -> void:
	if only != "" and only != "terrain":
		return
	_terrain_duels()
	_terrain_archers()
	_terrain_cavalry()
	_terrain_pikes()
	_terrain_artillery()
	_terrain_mirror()
	_terrain_battles()


## Equal heavy 100 vs heavy 100 on a slope: how often the side on higher
## ground wins, (a) both advancing to meet, (b) the higher one holding while
## the lower one climbs to it. Each grade runs with the high side at the top
## and at the bottom (seeds split), so the field's orientation cannot bias it.
func _terrain_duels() -> void:
	for mode in ["meet", "hold"]:
		for g in [0, 5, 10, 15, 25]:
			var hi_wins := 0
			var lo_wins := 0
			var draws := 0
			var hi_lost := 0.0
			var lo_lost := 0.0
			var n := 0
			for flip in 2:
				for s in seeds / 2:
					# Side 1 (top) is high unless flipped.
					var hi_side := 1 if flip == 0 else 0
					var units := [_u(0, UT.HEAVY, 100, 150, 200, UP, 25), _u(1, UT.HEAVY, 100, 150, 100, DOWN, 25)]
					var orders: Array = []
					if mode == "meet":
						orders = [_atk(0, 0, 1, 0), _atk(0, 1, 0, 0), _atk(60, 0, 1, 1), _atk(60, 1, 0, 1)]
					else:
						# The low side climbs; the high one holds its ground.
						var lo_side := 1 - hi_side
						orders = [_atk(0, lo_side, hi_side, 0), _atk(120, lo_side, hi_side, 1)]
					var feats: Array = _ramp(g, RAMP_UP_TOP if hi_side == 1 else RAMP_UP_BOTTOM) if g > 0 else []
					var sim := BattleSim.new()
					sim.setup(_scenario_t(units, orders, feats), 31000 + s * 977 + flip * 7)
					while sim.tick < max_ticks and sim.winner < 0:
						sim.step()
					n += 1
					if sim.winner == hi_side:
						hi_wins += 1
					elif sim.winner == 1 - hi_side:
						lo_wins += 1
					else:
						draws += 1
					hi_lost += sim.u_killed[hi_side]
					lo_lost += sim.u_killed[1 - hi_side]
			print("heavy vs heavy, %-5s slope %2d%%: higher side wins %3d%%, lower %3d%%, draw %3d%% | killed higher %5.1f, lower %5.1f  (%d runs)" % [
				mode, g, hi_wins * 100 / n, lo_wins * 100 / n, draws * 100 / n, hi_lost / n, lo_lost / n, n])


## Archers 80 vs archers 80, 115 m apart, one unit on a 15 m hill: both
## shoot at will until their arrows are gone.
func _terrain_archers() -> void:
	for hill in [false, true]:
		var k_hi := 0.0
		var k_lo := 0.0
		var s_hi := 0.0
		var s_lo := 0.0
		for s in seeds:
			var units := [_u(0, UT.ARCHER, 80, 150, 210, UP), _u(1, UT.ARCHER, 80, 150, 95, DOWN)]
			var feats: Array = [[Terrain.F_BUMP, 150, 222, 80, 15]] if hill else []
			var sim := BattleSim.new()
			sim.setup(_scenario_t(units, [], feats), 32000 + s * 389)
			var shots := [0, 0]
			while sim.tick < 1500 and sim.ended == 0 and (sim.u_ammo[0] > 0 or sim.u_ammo[1] > 0 \
					or sim.projectiles_in_flight() > 0):
				var a0: int = sim.u_ammo[0]
				var a1: int = sim.u_ammo[1]
				sim.step()
				shots[0] += maxi(a0 - sim.u_ammo[0], 0)
				shots[1] += maxi(a1 - sim.u_ammo[1], 0)
			k_hi += sim.u_killed[1]
			k_lo += sim.u_killed[0]
			s_hi += shots[0]
			s_lo += shots[1]
		var n := float(seeds)
		print("archers 80 vs archers 80 at 115 m, %-22s killed by bottom %5.1f (%4.0f arrows), by top %5.1f (%4.0f arrows)" % [
			"bottom on a 15 m hill:" if hill else "flat (control):", k_hi / n, s_hi / n, k_lo / n, s_lo / n])


## Cavalry 60 charging a standing heavy 100 from 110 m down / up a 12% slope
## (and flat): infantry killed by 40 s, riders lost, who won.
func _terrain_cavalry() -> void:
	for mode in ["flat", "downhill", "uphill"]:
		var killed := 0.0
		var lost := 0.0
		var cav_wins := 0
		var impacts := 0.0
		for s in seeds:
			var units := [_u(0, UT.CAVALRY, 60, 150, 220, UP), _u(1, UT.HEAVY, 100, 150, 110, DOWN)]
			var feats: Array = []
			if mode == "downhill":
				feats = _ramp(12, RAMP_UP_BOTTOM)
			elif mode == "uphill":
				feats = _ramp(12, RAMP_UP_TOP)
			var sim := BattleSim.new()
			sim.setup(_scenario_t(units, [_atk(0, 0, 1, 1)], feats), 33000 + s * 131)
			while sim.tick < 400:
				sim.step()
			killed += sim.u_killed[1]
			impacts += sim.stat_impacts
			while sim.tick < max_ticks and sim.winner < 0:
				sim.step()
			lost += sim.u_killed[0]
			if sim.winner == 0:
				cav_wins += 1
		var n := float(seeds)
		print("cav 60 charges heavy 100 standing, %-9s infantry killed by 40 s %5.1f (%4.0f impacts) | riders lost %5.1f | cavalry wins %3d%%" % [
			mode + ":", killed / n, impacts / n, lost / n, cav_wins * 100 / seeds])


## Pike 120 holding against heavy 100 attacking its front: flat, pikes on
## the higher / lower side of a 15% slope, and of a steep 25% one (where
## the wall breaks up more easily); plus heavy 100 pinning the pikes' front
## and light 100 hitting their flank, flat and on the steep slope.
func _terrain_pikes() -> void:
	for mode in ["flat", "pikes above", "pikes below", "pikes above 25%", "pikes below 25%"]:
		var wins := 0
		var kp := 0.0
		var kh := 0.0
		var dis := 0
		for s in seeds:
			var units := [_u(0, UT.PIKE, 120, 150, 200, UP), _u(1, UT.HEAVY, 100, 150, 140, DOWN)]
			var feats: Array = []
			var g := 25 if mode.ends_with("25%") else 15
			if mode.begins_with("pikes above"):
				feats = _ramp(g, RAMP_UP_BOTTOM)
			elif mode.begins_with("pikes below"):
				feats = _ramp(g, RAMP_UP_TOP)
			var sim := BattleSim.new()
			sim.setup(_scenario_t(units, [_atk(0, 1, 0, 0)], feats), 34000 + s * 211)
			while sim.tick < max_ticks and sim.winner < 0:
				sim.step()
				if sim.u_formed[0] == 0 and sim.u_contact[0] != 0:
					dis += 1
			if sim.winner == 0:
				wins += 1
			kp += sim.u_killed[0]
			kh += sim.u_killed[1]
		var n := float(seeds)
		print("pike 120 holds vs heavy 100 attacking, %-16s pikes win %3d%% | killed pikes %5.1f, heavy %5.1f | wall down %4.0f ticks in contact" % [
			mode + ":", wins * 100 / seeds, kp / n, kh / n, dis / n])
	for g in [0, 25]:
		var wins2 := 0
		var lost2 := 0.0
		for s in seeds:
			var units := [_u(0, UT.PIKE, 120, 150, 170, UP), _u(1, UT.HEAVY, 100, 150, 130, DOWN),
				_u(1, UT.LIGHT, 100, 215, 180, LEFT)]
			var feats: Array = _ramp(g, RAMP_UP_BOTTOM) if g > 0 else []
			var sim := BattleSim.new()
			sim.setup(_scenario_t(units, [_atk(0, 1, 0, 0), _atk(150, 2, 0, 0)], feats), 34500 + s * 211)
			while sim.tick < max_ticks and sim.winner < 0:
				sim.step()
			if sim.winner == 0:
				wins2 += 1
			lost2 += sim.u_killed[1] + sim.u_killed[2]
		print("pike 120 (above) pinned by heavy 100, light 100 into flank, %2d%% slope: pikes win %3d%% | attackers killed %5.1f" % [
			g, wins2 * 100 / seeds, lost2 / seeds])


## Bolts against a pike block behind a 6 m crest (explicit order: blocked)
## and against light infantry beside the crest's end; stones landing on
## pikes uphill / downhill of the battery (plough length).
func _terrain_artillery() -> void:
	for target in [2, 3]:
		var shots := 0.0
		var killed := 0.0
		var blocked := 0.0
		for s in seeds:
			var sc := Scenarios.make("test_bolts_crest")
			sc["orders"] = [_atk(0, 0, target, 0)]
			var sim := BattleSim.new()
			sim.setup(sc, 35000 + s * 17)
			while sim.tick < 900:
				sim.step()
			shots += sim.stat_bolts
			killed += sim.u_killed[target]
			blocked += sim.stat_lof_blocked
		var n := float(seeds)
		print("bolts 16 ordered to shoot %-38s %4.1f bolts fired, %4.1f killed, %5.1f refusals (no line of fire)" % [
			"pikes behind a 6 m crest:" if target == 2 else "light infantry clear of the crest:",
			shots / n, killed / n, blocked / n])
	for mode in ["flat", "target uphill", "target downhill"]:
		var killed := 0.0
		var struck := 0.0
		for s in seeds:
			var units := [_u(0, UT.STONE, 18, 150, 270, UP), _u(1, UT.PIKE, 120, 150, 70, DOWN)]
			var feats: Array = []
			if mode == "target uphill":
				feats = _ramp(10, RAMP_UP_TOP)
			elif mode == "target downhill":
				feats = _ramp(10, RAMP_UP_BOTTOM)
			var sim := BattleSim.new()
			sim.setup(_scenario_t(units, [], feats), 36000 + s * 1031)
			while sim.tick < 2400 and (sim.u_ammo[0] > 0 or sim.projectiles_in_flight() > 0):
				sim.step()
			killed += sim.u_killed[1]
			struck += sim.stat_art_victims
		var n := float(seeds)
		print("stones 18 vs pikes 120 standing 200 m away, %-16s killed %5.1f, struck %5.1f" % [
			mode + ":", killed / n, struck / n])


## Mirrored duels on a mirror-symmetric generated map (a hill / valley in
## the middle, the same for both): the bottom side should win about half.
func _terrain_mirror() -> void:
	for kind in [Terrain.K_HILL, Terrain.K_VALLEY, Terrain.K_ROLLING]:
		var bottom := 0
		var top := 0
		var n := 0
		for swap in [false, true]:
			for s in seeds:
				var units := [_u(0, UT.HEAVY, 100, 150, 200, UP, 25), _u(1, UT.HEAVY, 100, 150, 100, DOWN, 25)]
				var orders := [_atk(0, 0, 1, 0), _atk(0, 1, 0, 0), _atk(60, 0, 1, 1), _atk(60, 1, 0, 1)]
				if swap:
					units = [units[1], units[0]]
				var sc := _scenario(units, orders)
				sc["terrain"] = {"kind": kind, "sym": 1, "seed": 500 + s}
				var sim := BattleSim.new()
				sim.setup(sc, 37000 + s * 7)
				while sim.tick < max_ticks and sim.winner < 0:
					sim.step()
				n += 1
				if sim.winner == 0:
					bottom += 1
				elif sim.winner == 1:
					top += 1
		print("heavy mirror duel on a symmetric %-8s map: bottom wins %3d%%, top %3d%%  (%d runs)" % [
			Terrain.KIND_NAMES[kind].to_lower(), bottom * 100 / n, top * 100 / n, n])


## Full AI battles (bench_2000 armies) on each generated terrain kind.
func _terrain_battles() -> void:
	var n := maxi(seeds / 4, 3)
	for kind in [Terrain.K_ROLLING, Terrain.K_RIDGE, Terrain.K_VALLEY, Terrain.K_HILL, Terrain.K_SLOPE]:
		var times: Array[float] = []
		var wins := [0, 0, 0]
		var holds := 0
		for s in n:
			var sc := Scenarios.make("bench_2000")
			sc["terrain"] = {"kind": kind}
			var sim := BattleSim.new()
			sim.setup(sc, 38000 + s * 31)
			while sim.tick < 12000 and sim.winner < 0:
				sim.step()
			times.append(sim.tick / 600.0)
			wins[sim.winner if sim.winner >= 0 else 2] += 1
			holds += sim.stat_ai[12]
		times.sort()
		var sum := 0.0
		for t in times:
			sum += t
		print("AI battle (2,000) on %-8s decided after %.1f min mean (min %.1f, max %.1f); wins %d / %d, draws %d; high-ground holds %d" % [
			Terrain.KIND_NAMES[kind].to_lower() + ":", sum / n, times[0], times[n - 1], wins[0], wins[1], wins[2], holds])


# ------------------------------------------------------------- stone aim ---

## Stones at a 300-man line (heavy, spear, heavy) and a 120 pike block at
## near / mid / long range, standing and advancing on the battery: where
## each stone lands along its flight relative to the soldiers under it
## (front = nearest soldier within 3 m of the line of flight, rear =
## farthest): short (before the front), inside, beyond the rear, or wide
## (no soldier within 3 m of its line at all).
## Yardsticks for the field rebalance (2026-10-09, docs/STATUS.md "Field
## rebalance"): one scripted matchup per missile / new-row intent, so the
## numbers are measured, not guessed (--only=yard; each also by name).
func _yardsticks() -> void:
	if only != "" and not only.begins_with("yard"):
		return
	_section("Yardsticks: missiles (a full load at a target that stands in the open)")
	var sling := UT.index_of("slinger")
	var sco := UT.index_of("scorpions")
	_shoot("yard: archers 80 vs light 120 at 100 m", UT.ARCHER, 80, UT.LIGHT, 120, 100, DOWN)
	_shoot("yard: archers 80 vs cav 60 standing at 100 m", UT.ARCHER, 80, UT.CAVALRY, 60, 100, DOWN)
	_shoot("yard: archers 80 vs heavy 120 at 100 m (front)", UT.ARCHER, 80, UT.HEAVY, 120, 100, DOWN)
	_shoot("yard: slingers 80 vs light 120 at 100 m", sling, 80, UT.LIGHT, 120, 100, DOWN)
	_shoot("yard: slingers 80 vs light 120 at 140 m", sling, 80, UT.LIGHT, 120, 140, DOWN)
	_shoot("yard: slingers 80 vs heavy 120 at 100 m (front)", sling, 80, UT.HEAVY, 120, 100, DOWN)
	_shoot("yard: javelins 60 vs cav 60 at 35 m (front)", UT.JAVELIN, 60, UT.CAVALRY, 60, 35, DOWN)
	_shoot("yard: javelins 60 vs cav 60 walking in from 40 m", UT.JAVELIN, 60, UT.CAVALRY, 60, 40, DOWN, true)
	_shoot("yard: javelins 60 vs light 100 at 35 m (front)", UT.JAVELIN, 60, UT.LIGHT, 100, 35, DOWN)
	_shoot("yard: javelins 60 vs heavy 100 at 35 m (front)", UT.JAVELIN, 60, UT.HEAVY, 100, 35, DOWN)
	_shoot("yard: archers 80 vs pikes 120 at 100 m (flank)", UT.ARCHER, 80, UT.PIKE, 120, 100, LEFT)
	_shoot("yard: archers 80 vs pikes 120 at 100 m (rear)", UT.ARCHER, 80, UT.PIKE, 120, 100, UP)
	_shoot("yard: archers 80 vs heavy 120 at 100 m (flank)", UT.ARCHER, 80, UT.HEAVY, 120, 100, LEFT)
	_shoot("yard: archers 80 vs heavy 120 at 100 m (rear)", UT.ARCHER, 80, UT.HEAVY, 120, 100, UP)
	_shoot("yard: slingers 80 vs pikes 120 at 100 m (flank)", sling, 80, UT.PIKE, 120, 100, LEFT)
	_shoot("yard: slingers 80 vs pikes 120 at 100 m (rear)", sling, 80, UT.PIKE, 120, 100, UP)
	_shoot("yard: slingers 80 vs heavy 120 at 100 m (flank)", sling, 80, UT.HEAVY, 120, 100, LEFT)
	_shoot("yard: slingers 80 vs heavy 120 at 100 m (rear)", sling, 80, UT.HEAVY, 120, 100, UP)
	_shoot("yard: scorpions 12 vs pikes 120 at 150 m (front)", sco, 12, UT.PIKE, 120, 150, DOWN)
	_shoot("yard: archers 80 vs pikes 120 at 150 m (front)", UT.ARCHER, 80, UT.PIKE, 120, 140, DOWN)
	_blast_yard("yard: stones 18 explosive load vs pikes 120 at 150 m")
	_pin("yard: heavy 100 walks 200 m at bolts 16 (pin)", UT.BOLT, 16)
	_pin("yard: heavy 100 walks 200 m at scorpions 12 (pin)", sco, 12)
	_wall_yards()
	_section("Yardsticks: the new rows")
	var camel := UT.index_of("camel")
	var el := UT.index_of("elephant")
	var dh := UT.index_of("dog_handlers")
	var lh := UT.index_of("cav_jav")
	var gen := UT.index_of("general")
	_duel("yard: cav 60 charges cav 60 standing (control)",
		[_u(0, UT.CAVALRY, 60, 150, 200, UP), _u(1, UT.CAVALRY, 60, 150, 80, DOWN)],
		[_atk(0, 1, 0, 1)])
	_duel("yard: cav 60 charges camels 60 standing",
		[_u(0, camel, 60, 150, 200, UP), _u(1, UT.CAVALRY, 60, 150, 80, DOWN)],
		[_atk(0, 1, 0, 1)])
	_duel("yard: camels 60 charge cav 60 standing",
		[_u(0, camel, 60, 150, 200, UP), _u(1, UT.CAVALRY, 60, 150, 80, DOWN)],
		[_atk(0, 0, 1, 1)])
	_duel("yard: elephants 12 charge heavy 100 standing (front)",
		[_u(0, el, 12, 150, 230, UP), _u(1, UT.HEAVY, 100, 150, 110, DOWN)],
		[_atk(0, 0, 1, 1)], 1)
	_duel("yard: elephants 12 vs heavy 100 + javelins 60 x2 on the flanks",
		[_u(0, el, 12, 150, 230, UP), _u(1, UT.HEAVY, 100, 150, 110, DOWN),
			_u(1, UT.JAVELIN, 60, 90, 150, DOWN), _u(1, UT.JAVELIN, 60, 210, 150, DOWN)],
		[_atk(0, 0, 1, 1), _atk(0, 2, 0, 0), _atk(0, 3, 0, 0)], 0)
	_duel("yard: dogs 16 released on javelins 60",
		[_u(0, dh, 16, 150, 200, UP), _u(1, UT.JAVELIN, 60, 150, 140, DOWN)],
		[{"tick": 0, "type": BattleSim.ORDER_FIRE, "unit": 1, "on": 0},
			BattleSim.make_release_order(1, 0, 1)], 1)
	_duel("yard: dogs 16 released on slingers 80",
		[_u(0, dh, 16, 150, 200, UP), _u(1, UT.index_of("slinger"), 80, 150, 140, DOWN)],
		[{"tick": 0, "type": BattleSim.ORDER_FIRE, "unit": 1, "on": 0},
			BattleSim.make_release_order(1, 0, 1)], 1)
	_duel("yard: dogs 16 released on heavy 100",
		[_u(0, dh, 16, 150, 200, UP), _u(1, UT.HEAVY, 100, 150, 140, DOWN)],
		[BattleSim.make_release_order(1, 0, 1)], 1)
	_duel("yard: light horse 60 vs archers 80, both attack",
		[_u(0, lh, 60, 150, 230, UP), _u(1, UT.ARCHER, 80, 150, 90, DOWN)],
		[_atk(0, 0, 1, 0), _atk(0, 1, 0, 0)])
	_duel("yard: light horse 60 vs javelins 60, both attack",
		[_u(0, lh, 60, 150, 230, UP), _u(1, UT.JAVELIN, 60, 150, 120, DOWN)],
		[_atk(0, 0, 1, 0), _atk(0, 1, 0, 0)])
	_duel("yard: heavy vs heavy attacking, no general (control)",
		[_u(0, UT.HEAVY, 100, 150, 170, UP), _u(1, UT.HEAVY, 100, 150, 140, DOWN)],
		[_atk(0, 1, 0, 0)], 1)
	_duel("yard: heavy vs heavy attacking with its general behind",
		[_u(0, UT.HEAVY, 100, 150, 170, UP), _u(1, UT.HEAVY, 100, 150, 140, DOWN),
			_u(1, gen, 30, 150, 124, DOWN)],
		[_atk(0, 1, 0, 0)], 1)
	_duel("yard: cav 60 charges heavy 100 standing (control)",
		[_u(0, UT.CAVALRY, 60, 150, 220, UP), _u(1, UT.HEAVY, 100, 150, 110, DOWN)],
		[_atk(0, 0, 1, 1)])
	_duel("yard: cav 60 charges heavy 100 behind stakes",
		[_u(0, UT.CAVALRY, 60, 150, 220, UP), _u(1, UT.HEAVY, 100, 150, 110, DOWN)],
		[_atk(0, 0, 1, 1)], -1, {"field_works": [[BattleSim.EQ_STAKES, 1, 150, 117, DOWN, 40]]})
	_duel("yard: archers 80 vs archers 80 at 120 m (control)",
		[_u(0, UT.ARCHER, 80, 150, 210, UP), _u(1, UT.ARCHER, 80, 150, 90, DOWN)],
		[_atk(0, 0, 1, 0), _atk(0, 1, 0, 0)])
	_duel("yard: archers 80 behind 4 mantlets vs archers 80 at 120 m",
		[_u(0, UT.ARCHER, 80, 150, 210, UP), _u(1, UT.ARCHER, 80, 150, 90, DOWN)],
		[_atk(0, 0, 1, 0), _atk(0, 1, 0, 0)], -1, {"mantlets": [4, 0]})


## The wall walk (walls 1, flat ground, one unit a side, 20 seeds): the
## climb onto a planted 5-ladder set against men on the walk, and the walk
## fight itself. Per 5 s for 90 s: men of each side within reach of the
## enemy (u_inreach), attackers within 3 m of the ladder top, the files each
## unit holds (files_of) and the men on the walk. Same set-up as the flow
## probe in determinism_test.gd (_flow_ladder_sc). --only=wall-yard or yard.
const WY_T := 6000       # ticks to a decision (600 s)
const WY_SAMP := 50      # sample every 5 s
const WY_N := 18         # samples: 5 s .. 90 s


## Climb set-up: the attackers (side 0) by the ladder approach of the walk
## stretch nearest them, the defenders (side 1) on that stretch's walk at its
## middle (the ladder top). Returns {sc, sg, wx, wy}.
## (city_seed, at_pct: the column set-up below takes the longest stretch with
## a ladder spot at_pct % along it, of another town.)
func _wall_climb_sc(att_ty: int, n_att: int, dfn_ty: int, n_dfn: int, city_seed := 4242, at_pct := -1) -> Dictionary:
	var city := {"seed": city_seed, "level": 2, "walls": 1, "bld": [], "towers": 0}
	var terr := {"kind": Terrain.K_FLAT, "seed": 11, "forest": 0, "ground": 2}
	var r := Scenarios.settlement(city, terr, [[att_ty, n_att]], [[dfn_ty, n_dfn]], 1, [], {"ladders": 1})
	var sc: Dictionary = _wall_keep_one(r["scenario"])
	var probe := BattleSim.new()
	probe.setup(sc, 77)
	var best := -1
	var bd := 0
	var bap := Vector2i.ZERO
	var bmp := Vector2i.ZERO
	for sg in probe.ws_x0.size():
		var mp: Vector2i = BattleSim.seg_pt(probe, sg, BattleSim.seg_len(probe, sg) * (50 if at_pct < 0 else at_pct) / 100)
		var lf: Vector3i = BattleSim.ladder_foot(probe, sg, mp.x, mp.y)
		if lf.z == 0 or not BattleSim.ladder_ok(probe, 0, sg, mp.x, mp.y):
			continue
		var d := absi(mp.x - probe.u_cx[0]) + absi(mp.y - probe.u_cy[0])
		if at_pct >= 0:
			d = -BattleSim.seg_len(probe, sg)  # the longest
		if best < 0 or d < bd:
			best = sg
			bd = d
			bap = BattleSim.ladder_approach(probe, sg, lf.x, lf.y)
			bmp = mp
	var c := FM.cos_a(probe.ws_dir[best])
	var s := FM.sin_a(probe.ws_dir[best])
	var ux: int = (bap.x + c * 12 * M / FM.TRIG_ONE) / M
	var uy: int = (bap.y + s * 12 * M / FM.TRIG_ONE) / M
	for ud in sc["units"]:
		if int(ud["side"]) == 0:
			ud["x_m"] = ux
			ud["y_m"] = uy
			ud["facing"] = (probe.ws_dir[best] + 512) & 1023
			ud["files"] = 15
		else:
			ud["x_m"] = bmp.x / M
			ud["y_m"] = bmp.y / M
			ud["wall"] = best + 1
	sc["equip"] = [[BattleSim.EQ_LADDERS, ux, uy]]
	return {"sc": sc, "wx": bmp.x, "wy": bmp.y, "sg": best}


## Walk-fight set-up: both units on the walk of the longest stretch, the
## attacker 10 m before its middle and the defender 10 m past it (20 m apart).
func _wall_walk_sc(att_ty: int, n_att: int, dfn_ty: int, n_dfn: int) -> Dictionary:
	var city := {"seed": 4242, "level": 2, "walls": 1, "bld": [], "towers": 0}
	var terr := {"kind": Terrain.K_FLAT, "seed": 11, "forest": 0, "ground": 2}
	var r := Scenarios.settlement(city, terr, [[att_ty, n_att]], [[dfn_ty, n_dfn]], 1, [], {})
	var sc: Dictionary = _wall_keep_one(r["scenario"])
	var probe := BattleSim.new()
	probe.setup(sc, 77)
	var best := 0
	for sg in probe.ws_x0.size():
		if BattleSim.seg_len(probe, sg) > BattleSim.seg_len(probe, best):
			best = sg
	var half := BattleSim.seg_len(probe, best) / 2
	var pa: Vector2i = BattleSim.seg_pt(probe, best, half - 10 * M)
	var pd: Vector2i = BattleSim.seg_pt(probe, best, half + 10 * M)
	for ud in sc["units"]:
		if int(ud["side"]) == 0:
			ud["x_m"] = pa.x / M
			ud["y_m"] = pa.y / M
			ud["wall"] = best + 1
		else:
			ud["x_m"] = pd.x / M
			ud["y_m"] = pd.y / M
			ud["wall"] = best + 1
	return {"sc": sc, "sg": best, "len_m": BattleSim.seg_len(probe, best) / M}


## One unit a side only (the settlement also places garrison units).
static func _wall_keep_one(sc: Dictionary) -> Dictionary:
	var keep: Array = []
	var got := [false, false]
	for ud in sc["units"]:
		var sd := int(ud["side"])
		if not got[sd]:
			got[sd] = true
			keep.append(ud)
	sc["units"] = keep
	sc["orders"] = []
	return sc


## Runs one set-up over the seeds and prints the row (and, with `detail`, the
## per-5 s lines). kind: "climb" (the ladder set is planted by side 0 and
## its men go up), "walk" (both on the walk, attacker orders the attack) or
## "field" (open ground, 20 m apart, attacker orders the attack).
func _wall_yard(name: String, kind: String, att_ty: int, n_att: int, dfn_ty: int, n_dfn: int, detail: bool) -> void:
	if only != "wall-yard" and only != "wall-col" and _skip(name):
		return
	var base: Dictionary = {}
	var top := Vector2i.ZERO
	if kind == "climb":
		base = _wall_climb_sc(att_ty, n_att, dfn_ty, n_dfn)
		top = Vector2i(int(base["wx"]), int(base["wy"]))
	elif kind == "walk":
		base = _wall_walk_sc(att_ty, n_att, dfn_ty, n_dfn)
	var wins := [0, 0, 0]
	var lost := [0.0, 0.0]
	var acc := PackedFloat64Array()  # per sample: reach0, reach1, top0, walk0, walk1, files0, files1
	acc.resize(WY_N * 7)
	var first_up := -1.0
	var ended_t := 0.0
	for s in seeds:
		var sc: Dictionary = base["sc"].duplicate(true) if kind != "field" else \
			_scenario([_u(0, att_ty, n_att, 150, 200, UP), _u(1, dfn_ty, n_dfn, 150, 180, DOWN)], [_atk(0, 0, 1, 0)])
		var sim := BattleSim.new()
		sim.setup(sc, 77 + s * 7919)
		var ordered := kind != "climb"
		if kind == "climb":
			sim.queue_order({"tick": 1, "type": BattleSim.ORDER_PICKUP, "unit": 0, "equip": 0, "run": 0, "player": 50})
		elif kind == "walk":
			sim.queue_order(_atk(0, 0, 1, 0))
		while sim.tick < WY_T and sim.ended == 0:
			if kind == "climb" and not ordered and sim.u_carry[0] == 0:
				ordered = true
				sim.queue_order(BattleSim.make_move_order(sim.tick, 0, int(base["wx"]), int(base["wy"]), 768, 20 * M, 0))
			sim.step()
			if kind == "climb" and first_up < 0 and sim.u_stair[0] == BattleSim.ST_LADDER:
				first_up = sim.tick
			if sim.tick % WY_SAMP == 0 and sim.tick <= WY_N * WY_SAMP:
				var k := sim.tick / WY_SAMP - 1
				var r0 := 0.0
				var r1 := 0.0
				var w0 := 0.0
				var w1 := 0.0
				var tp := 0.0
				for u in sim.n_units:
					if sim.u_side[u] == 0:
						r0 += sim.u_inreach[u]
					else:
						r1 += sim.u_inreach[u]
				for u in sim.n_units:
					var base_i: int = sim.u_slot_base[u]
					for sl in sim.u_alive[u]:
						var i: int = sim.slot_soldier[base_i + sl]
						if sim.state[i] >= BattleSim.S_DEAD:
							continue
						var on := sim._on_walk(sim.pos_x[i], sim.pos_y[i])
						if sim.u_side[u] == 0:
							if on:
								w0 += 1
							if kind == "climb" and FM.approx_len(sim.pos_x[i] - top.x, sim.pos_y[i] - top.y) <= 3 * M:
								tp += 1
						elif on:
							w1 += 1
				var f0 := 0.0
				var f1 := 0.0
				for u in sim.n_units:
					if sim.u_side[u] == 0:
						f0 = maxf(f0, sim.files_of(u))
					else:
						f1 = maxf(f1, sim.files_of(u))
				var v := [r0, r1, tp, w0, w1, f0, f1]
				for j in 7:
					acc[k * 7 + j] += v[j]
		var w: int = sim.winner if sim.winner >= 0 else 2
		wins[w] += 1
		ended_t += (sim.decided_tick if sim.decided_tick >= 0 else sim.tick) / 10.0
		var res: Dictionary = sim.result()
		for side in 2:
			lost[side] += int(res["sides"][side]["killed"])
	var line := "%-64s side0 wins %3d%%  side1 %3d%%  draw %3d%% | killed %5.1f vs %5.1f | decided %5.1f s" % [
		name, wins[0] * 100 / seeds, wins[1] * 100 / seeds, wins[2] * 100 / seeds,
		lost[0] / seeds, lost[1] / seeds, ended_t / seeds]
	if kind == "climb":
		line += " | first man up at %.1f s" % (first_up / 10.0 if first_up >= 0 else -1.0)
	print(line)
	if detail:
		print("   t(s)  reach 0/1 | att at ladder top | men on walk 0/1 | files 0/1")
		for k in WY_N:
			print("   %4d   %5.1f / %5.1f   |      %5.1f        |   %5.1f / %5.1f    |  %3.0f / %3.0f" % [
				(k + 1) * 5, acc[k * 7] / seeds, acc[k * 7 + 1] / seeds, acc[k * 7 + 2] / seeds,
				acc[k * 7 + 3] / seeds, acc[k * 7 + 4] / seeds, acc[k * 7 + 5] / seeds, acc[k * 7 + 6] / seeds])


## The wall-walk yardsticks (--only=wall-yard, and inside --only=yard).
func _wall_yards() -> void:
	_section("Yardsticks: the wall walk (walls 1, flat, one 100-unit side a side, 20 seeds)")
	var LI := UT.LIGHT
	var HS := UT.HEAVY
	_wall_yard("yard wall 1: 100 light climb a planted 5-ladder set vs 100 heavy on the walk", "climb", LI, 100, HS, 100, true)
	_wall_yard("yard wall 2: 100 heavy climb a planted 5-ladder set vs 100 light on the walk", "climb", HS, 100, LI, 100, true)
	_wall_yard("yard wall 1b: 100 light climb vs 100 heavy on the walk (as 1, repeat)", "climb", LI, 100, HS, 100, true)
	_wall_yard("yard wall 3: heavy climb vs heavy on the walk (control)", "climb", HS, 100, HS, 100, false)
	_wall_yard("yard wall 4: light climb vs light on the walk (control)", "climb", LI, 100, LI, 100, false)
	_wall_yard("yard wall 5: light attacks heavy, both on the walk 20 m apart", "walk", LI, 100, HS, 100, false)
	_wall_yard("yard wall 6: heavy attacks light, both on the walk 20 m apart", "walk", HS, 100, LI, 100, false)
	_wall_yard("yard wall 7: light attacks heavy, open field 20 m apart (baseline)", "field", LI, 100, HS, 100, false)
	_wall_cols()


## The column on the walk (--only=wall-col, and inside --only=wall-yard / yard).
func _wall_cols() -> void:
	_section("Yardsticks: a column along the walk into men massing at the ladder tops (walls 1, 100 a side)")
	var LI := UT.LIGHT
	var HS := UT.HEAVY
	_wall_col("yard wall 8: heavy along the walk attack 100 light massing at the ladder tops", "attack", LI, HS, true)
	_wall_col("yard wall 9: heavy along the walk moved to the ladder top, into the light", "move", LI, HS, true)
	_wall_yard("yard wall 10: heavy attacks light, open field 20 m apart (baseline)", "field", HS, 100, LI, 100, false)


## The column on the walk (the owner's "fought in 2s ... a feeding machine",
## 2026-10-10): side 0 climbs a planted 5-ladder set onto a stretch nobody
## holds and masses at the ladder tops; side 1 stands on the same walk, its
## line's near end WC_GAP m along from the ladder top, and once WC_UP of
## side 0 are up it is ordered at them along the walk (mode "attack": an
## attack order; "move": a move along its stretch to the ladder top). Per
## 5 s for 90 s from the order: men in reach (u_inreach) per side, men on
## the walk, and the men each side lost in those 5 s.
const WC_GAP := 6        # m from the ladder top to the near end of side 1's line
const WC_UP := 40        # side 0 men up before side 1 is ordered
const WC_CITY := 1234    # a town whose longest stretch (95 m) holds both lines
const WC_AT := 25        # the ladder set planted this % along it


func _wall_col(name: String, mode: String, att_ty: int, dfn_ty: int, detail: bool) -> void:
	if only != "wall-yard" and only != "wall-col" and _skip(name):
		return
	var base: Dictionary = _wall_climb_sc(att_ty, 100, dfn_ty, 100, WC_CITY, WC_AT)
	var sc0: Dictionary = base["sc"]
	var sg: int = base["sg"]
	var probe := BattleSim.new()
	probe.setup(sc0, 77)
	var l := BattleSim.seg_len(probe, sg)
	var tt := BattleSim.seg_t(probe, sg, int(base["wx"]), int(base["wy"]))
	var hl := BattleSim.wall_nf(100) * UT.stat(dfn_ty, "file_sp")
	# Along the stretch toward its longer side from the ladder top.
	var dirn := 1 if l - tt >= tt else -1
	var dp: Vector2i = BattleSim.seg_pt(probe, sg, clampi(tt + dirn * (WC_GAP * M + hl / 2), 0, l))
	for ud in sc0["units"]:
		if int(ud["side"]) == 1:
			ud["x_m"] = dp.x / M
			ud["y_m"] = dp.y / M
	var wins := [0, 0, 0]
	var lost := [0.0, 0.0]
	var acc := PackedFloat64Array()  # per sample: reach0, reach1, walk0, walk1, lost0, lost1
	acc.resize(WY_N * 6)
	var t_ord := 0.0
	var ended_t := 0.0
	for s in seeds:
		var sc: Dictionary = sc0.duplicate(true)
		var sim := BattleSim.new()
		sim.setup(sc, 77 + s * 7919)
		sim.queue_order({"tick": 1, "type": BattleSim.ORDER_PICKUP, "unit": 0, "equip": 0, "run": 0, "player": 50})
		var climbing := false
		var t_ord_k := -1
		var k0 := [0, 0]
		while sim.tick < WY_T and sim.ended == 0:
			if not climbing and sim.u_carry[0] == 0:
				climbing = true
				sim.queue_order(BattleSim.make_move_order(sim.tick, 0, int(base["wx"]), int(base["wy"]), 768, 20 * M, 0))
			sim.step()
			if t_ord_k < 0 and climbing:
				var up := 0
				var bi: int = sim.u_slot_base[0]
				for sl in sim.u_alive[0]:
					var i: int = sim.slot_soldier[bi + sl]
					if sim.state[i] < BattleSim.S_DEAD and sim._on_walk(sim.pos_x[i], sim.pos_y[i]):
						up += 1
				if up >= WC_UP:
					t_ord_k = sim.tick
					t_ord += t_ord_k / 10.0
					if mode == "attack":
						sim.queue_order(_atk(sim.tick, 1, 0, 0))
					else:
						sim.queue_order(BattleSim.make_move_order(sim.tick, 1, int(base["wx"]), int(base["wy"]), 0, 20 * M, 0))
			if t_ord_k >= 0 and (sim.tick - t_ord_k) % WY_SAMP == 0 and sim.tick > t_ord_k and sim.tick - t_ord_k <= WY_N * WY_SAMP:
				var k := (sim.tick - t_ord_k) / WY_SAMP - 1
				var w := [0, 0]
				for u in sim.n_units:
					var bu: int = sim.u_slot_base[u]
					for sl in sim.u_alive[u]:
						var i: int = sim.slot_soldier[bu + sl]
						if sim.state[i] < BattleSim.S_DEAD and sim._on_walk(sim.pos_x[i], sim.pos_y[i]):
							w[sim.u_side[u]] += 1
				var v := [sim.u_inreach[0] if sim.u_state[0] == BattleSim.U_READY else 0,
					sim.u_inreach[1] if sim.u_state[1] == BattleSim.U_READY else 0, w[0], w[1],
					sim.u_killed[0] - k0[0], sim.u_killed[1] - k0[1]]
				k0 = [sim.u_killed[0], sim.u_killed[1]]
				for j in 6:
					acc[k * 6 + j] += v[j]
		var wn: int = sim.winner if sim.winner >= 0 else 2
		wins[wn] += 1
		ended_t += (sim.decided_tick if sim.decided_tick >= 0 else sim.tick) / 10.0
		for sd in 2:
			lost[sd] += sim.u_killed[sd]
	print("%-64s side0 wins %3d%%  side1 %3d%%  draw %3d%% | killed %5.1f vs %5.1f | decided %5.1f s | ordered at %.1f s (stretch %d m)" % [
		name, wins[0] * 100 / seeds, wins[1] * 100 / seeds, wins[2] * 100 / seeds,
		lost[0] / seeds, lost[1] / seeds, ended_t / seeds, t_ord / seeds, l / M])
	if detail:
		print("   t(s)  reach 0/1 | men on walk 0/1 | lost in 5 s 0/1")
		for k in WY_N:
			print("   %4d   %5.1f / %5.1f   |   %5.1f / %5.1f    |  %4.1f / %4.1f" % [
				(k + 1) * 5, acc[k * 6] / seeds, acc[k * 6 + 1] / seeds, acc[k * 6 + 2] / seeds,
				acc[k * 6 + 3] / seeds, acc[k * 6 + 4] / seeds, acc[k * 6 + 5] / seeds])


## A missile unit (side 0) shoots its whole load at a standing target `dist`
## m away (skirmish off, an explicit shoot order): % killed, peak fright,
## how often the target broke.
func _shoot(name: String, sty: int, sn: int, tty: int, tn: int, dist: int, tface: int, walk_in := false) -> void:
	if _skip(name):
		return
	var killed := 0.0
	var fright := 0.0
	var broke := 0
	var shots := 0.0
	for s in seeds:
		var units := [_u(0, sty, sn, 150, 260, UP), _u(1, tty, tn, 150, 260 - dist, tface)]
		var orders := [{"tick": 0, "type": BattleSim.ORDER_SKIRMISH, "unit": 0, "on": 0}, _atk(0, 0, 1, 0)]
		if walk_in:
			# The target walks straight at the shooters and stops 8 m short.
			orders.append(BattleSim.make_move_order(0, 1, 150 * M, 252 * M, DOWN, 30 * M, 0))
		var sim := BattleSim.new()
		sim.setup(_scenario(units, orders), 3000 + s * 4243)
		var peak := 0
		var fired := false
		while sim.tick < 2400:
			sim.step()
			peak = maxi(peak, sim.u_fright[1])
			if sim.projectiles_in_flight() > 0:
				fired = true
			if fired and sim.u_ammo[0] <= 0 and sim.projectiles_in_flight() == 0:
				break
			if sim.u_state[0] != BattleSim.U_READY:
				break
		killed += sim.u_killed[1]
		fright += peak
		shots += sim.stat_shots + sim.stat_bolts
		if sim.u_state[1] != BattleSim.U_READY:
			broke += 1
	print("%-58s killed %5.1f of %d (%4.1f%%) | broke %d/%d | peak fright %3.0f | %4.0f shots" % [
		name, killed / seeds, tn, 100.0 * killed / seeds / tn, broke, seeds, fright / seeds, shots / seeds])


## A stone battery's full load of explosive stones into a standing pike
## block 150 m off, against as many ordinary stones (docs/DESIGN.md
## "Explosive stones: blast and knockback"): killed, struck, knocked.
func _blast_yard(name: String) -> void:
	if _skip(name):
		return
	var r := [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]  # killed, struck, knocked, shots
	for s in seeds:
		var want := -1
		for kind in 2:
			var units := [_u(0, UT.STONE, 18, 150, 260, UP), _u(1, UT.PIKE, 120, 150, 110, DOWN)]
			var orders := [_atk(0, 0, 1, 0)]
			if kind == 0:
				units[0]["ak"] = UT.ammo_index("explosive")
				orders.append({"tick": 0, "type": BattleSim.ORDER_AMMO, "unit": 0, "on": 1})
			var sim := BattleSim.new()
			sim.setup(_scenario(units, orders), 3000 + s * 4243)
			var out := false
			while sim.tick < 3000 and sim.u_state[1] == BattleSim.U_READY:
				var shots: int = sim.stat_ak_shots if kind == 0 else sim.stat_stones
				if not out and (sim.special_left(0) <= 0 if kind == 0 else shots >= want):
					# The load (or as many ordinary stones) is away: no more.
					out = true
					for k in sim.u_neng[0]:
						sim.e_ammo[sim.u_eng0[0] + k] = 0
				if out and sim.projectiles_in_flight() == 0:
					break
				sim.step()
			if kind == 0:
				want = sim.stat_ak_shots
			r[kind][0] += sim.u_killed[1]
			r[kind][1] += sim.stat_blast if kind == 0 else sim.stat_art_victims
			r[kind][2] += sim.stat_blast_knock
			r[kind][3] += sim.stat_ak_shots if kind == 0 else sim.stat_stones
	for kind in 2:
		print("%-58s killed %5.1f of 120 | struck %5.1f | knocked %5.1f | %4.1f shots" % [
			name if kind == 0 else "  (as many ordinary stones)", r[kind][0] / seeds, r[kind][1] / seeds,
			r[kind][2] / seeds, r[kind][3] / seeds])


## Heavy 100 walks 200 m straight at a battery (side 0): seconds to close
## to 30 m with the battery shooting and with it holding fire, men lost.
func _pin(name: String, bty: int, bn: int) -> void:
	if _skip(name):
		return
	var secs := [0.0, 0.0]
	var lost := 0.0
	var fright := 0.0
	var broke := 0
	for s in seeds:
		for shoot in 2:
			var units := [_u(0, bty, bn, 150, 270, UP), _u(1, UT.HEAVY, 100, 150, 60, DOWN)]
			var orders := [BattleSim.make_move_order(0, 1, 150 * M, 240 * M, DOWN, 30 * M, 0)]
			if shoot == 1:
				orders.append(_atk(0, 0, 1, 0))
			else:
				orders.append({"tick": 0, "type": BattleSim.ORDER_FIRE, "unit": 0, "on": 0})
			var sim := BattleSim.new()
			sim.setup(_scenario(units, orders), 3500 + s * 4243)
			var peak := 0
			while sim.tick < 2400 and sim.u_ay[1] < 238 * M and sim.u_state[1] == BattleSim.U_READY:
				sim.step()
				peak = maxi(peak, sim.u_fright[1])
			secs[shoot] += sim.tick / 10.0
			if shoot == 1:
				lost += sim.u_killed[1]
				fright += peak
				if sim.u_state[1] != BattleSim.U_READY:
					broke += 1
	print("%-58s closed in %5.1f s under fire vs %5.1f s unshot | lost %4.1f | broke %d/%d | peak fright %3.0f" % [
		name, secs[1] / seeds, secs[0] / seeds, lost / seeds, broke, seeds, fright / seeds])


func _stone_aim() -> void:
	if only != "" and only != "stoneaim" and only != "art":
		return
	for tgt in ["line", "pikes"]:
		for dist in [100, 200, 270]:
			for mode in ["standing", "advancing"]:
				var c := [0, 0, 0, 0]
				var killed := 0.0
				var n_s := maxi(seeds / 2, 4)
				for s in n_s:
					var y1: int = 280 - dist
					var units: Array = [_u(0, UT.STONE, 18, 150, 285, UP)]
					if tgt == "line":
						units.append_array([_u(1, UT.HEAVY, 100, 89, y1, DOWN), _u(1, UT.SPEAR, 100, 150, y1, DOWN),
							_u(1, UT.HEAVY, 100, 211, y1, DOWN)])
					else:
						units.append(_u(1, UT.PIKE, 120, 150, y1, DOWN))
					var orders: Array = []
					if mode == "advancing":
						for k in range(1, units.size()):
							orders.append({"tick": 0, "type": BattleSim.ORDER_MOVE, "unit": k,
								"x": int(units[k]["x_m"]) * 1024, "y": 230 * 1024, "facing": DOWN,
								"width": 28 * 1024, "run": 0})
					var sim := BattleSim.new()
					sim.setup(_scenario(units, orders), 41000 + s * 101)
					var limit := 1200 if mode == "advancing" else 2400
					while sim.tick < limit and (sim.u_ammo[0] > 0 or sim.projectiles_in_flight() > 0):
						sim.step()
						for k in sim.FX_CAP:
							if sim.fx_t[k] != sim.tick - 1:
								continue
							c[_stone_class(sim, k)] += 1
						if mode == "advancing" and sim.u_ay[1] >= 225 * 1024 and sim.u_order[1] == BattleSim.O_NONE:
							break
					for u in range(1, sim.n_units):
						killed += sim.u_killed[u]
				var tot := maxi(c[0] + c[1] + c[2] + c[3], 1)
				print("stones at %-5s %3d m %-9s: %4d stones  short %3d%%  inside %3d%%  beyond rear %3d%%  wide %3d%% | killed %5.1f per run" % [
					tgt, dist, mode, tot, c[0] * 100 / tot, c[1] * 100 / tot, c[2] * 100 / tot, c[3] * 100 / tot,
					killed / n_s])


## 0 short, 1 inside, 2 beyond the rear, 3 wide (stone impact mark k).
func _stone_class(sim, k: int) -> int:
	var x: int = sim.fx_x[k]
	var y: int = sim.fx_y[k]
	var ux: int = sim.fx_dx[k]
	var uy: int = sim.fx_dy[k]
	var lo := 1 << 40
	var hi := -(1 << 40)
	for i in sim.n:
		if sim.state[i] >= BattleSim.S_DEAD or sim.u_side[sim.unit_of[i]] != 1:
			continue
		var rx: int = sim.pos_x[i] - x
		var ry: int = sim.pos_y[i] - y
		var lat: int = (ry * ux - rx * uy) / 4096
		if absi(lat) > 3 * 1024:
			continue
		var al: int = (rx * ux + ry * uy) / 4096
		lo = mini(lo, al)
		hi = maxi(hi, al)
	if hi < lo:
		return 3
	# al > 0: the soldier is further along the flight than the landing point.
	if lo > 0:
		return 0
	if hi < 0:
		return 2
	return 1


# ----------------------------------------------------------------- tiers ---

## Unit tiers (campaign): for each core line, tier 3 and tier 2 against tier
## 1 at equal numbers (tier 3 should win clearly) and at equal price (the
## cheaper side gets proportionally more men in a wider unit; should be
## roughly even). Melee lines: both units advance into each other; missile
## lines shoot it out at 100 m (then close); cavalry charge each other.
##   godot --headless --script res://tests/matchups.gd -- --only=tiers [--seeds=N]
func _tiers() -> void:
	_section("Unit tiers: higher tier vs tier 1 (side 0 is the higher tier)")
	only = ""
	var lines := [["heavy", UT.HEAVY], ["light", UT.LIGHT], ["spear", UT.SPEAR], ["pike", UT.PIKE],
		["archer", UT.ARCHER], ["javelin", UT.JAVELIN], ["cav", UT.CAVALRY]]
	for l in lines:
		var t1: int = l[1]
		for tier in [3, 2]:
			var hi := UT.index_of("%s%d" % [l[0], tier])
			var n_hi := UT.size_of(hi)
			var gap := 100 if UT.cls(t1) == UT.CLS_MISSILE else 60
			_duel("%s T%d %d vs T1 %d, equal numbers" % [l[0], tier, n_hi, n_hi],
				[_u(0, hi, n_hi, 150, 150 + gap / 2, UP), _u(1, t1, n_hi, 150, 150 - gap / 2, DOWN)],
				[_atk(0, 0, 1, 0), _atk(0, 1, 0, 0)])
			var n_lo := n_hi * UT.price_of(hi) / UT.price_of(t1)
			_duel("%s T%d %d vs T1 %d, equal price" % [l[0], tier, n_hi, n_lo],
				[_u(0, hi, n_hi, 150, 150 + gap / 2, UP), _u(1, t1, n_lo, 150, 150 - gap / 2, DOWN)],
				[_atk(0, 0, 1, 0), _atk(0, 1, 0, 0)])


# ------------------------------------------------- woods and settlements ---

## --only=maps: woods, streets, gates and settlement battles.
func _maps() -> void:
	_section("Woods")
	_woods_cav()
	_woods_cav_archers()
	_woods_volley()
	_woods_pikes()
	_woods_javelins()
	_section("Streets (a 10 m street between two building blocks vs the open)")
	_streets()
	_section("Gates: time to break the main gate (town, no defenders shooting / with the garrison on the walls)")
	_gates()
	_section("Garrison-only defence (town, garrison 3 + walls units of 60) vs the standard 12-unit attacker, AI vs AI")
	_garrison_defence()
	_section("AI vs AI settlement battles (garrison + a 4-unit field army defending)")
	_siege_battles()
	_section("AI vs AI field battles with woods (bench_2000 armies, generated ground, woods 40)")
	_forest_battles()


func _woods_t(units: Array, orders: Array, woods: Array) -> Dictionary:
	var sc := _scenario(units, orders)
	if not woods.is_empty():
		sc["terrain"] = {"kind": 0, "woods": woods}
	return sc


## Cavalry 60 charging a standing heavy 100 whose position (and the last
## 25 m in front of it) is woods of density d.
func _woods_cav() -> void:
	for d in [0, 1, 2, 3]:
		var killed := 0.0
		var lost := 0.0
		var wins := 0
		var impacts := 0.0
		for s in seeds:
			var units := [_u(0, UT.CAVALRY, 60, 150, 220, UP), _u(1, UT.HEAVY, 100, 150, 110, DOWN)]
			var woods: Array = [[150, 110, 40, 25, d]] if d > 0 else []
			var sim := BattleSim.new()
			sim.setup(_woods_t(units, [_atk(0, 0, 1, 1)], woods), 41000 + s * 131)
			while sim.tick < 400:
				sim.step()
			killed += sim.u_killed[1]
			impacts += sim.stat_impacts
			while sim.tick < max_ticks and sim.winner < 0:
				sim.step()
			lost += sim.u_killed[0]
			if sim.winner == 0:
				wins += 1
		var n := float(seeds)
		print("cav 60 charges heavy 100 standing, woods %d: infantry killed by 40 s %5.1f (%4.0f impacts) | riders lost %5.1f | cavalry wins %3d%%" % [
			d, killed / n, impacts / n, lost / n, wins * 100 / seeds])


## Cavalry 60 charging archers 80 (who shoot first) in the open / in dense woods.
func _woods_cav_archers() -> void:
	for d in [0, 3]:
		var wins := 0
		var lost := [0.0, 0.0]
		for s in seeds:
			var units := [_u(0, UT.CAVALRY, 60, 150, 250, UP), _u(1, UT.ARCHER, 80, 150, 90, DOWN)]
			var woods: Array = [[150, 85, 40, 25, d]] if d > 0 else []
			var sim := BattleSim.new()
			sim.setup(_woods_t(units, [_atk(0, 0, 1, 1)], woods), 42000 + s * 137)
			while sim.tick < max_ticks and sim.winner < 0:
				sim.step()
			if sim.winner == 0:
				wins += 1
			lost[0] += sim.u_killed[0]
			lost[1] += sim.u_killed[1]
		var n := float(seeds)
		print("cav 60 vs archers 80, archers in %-10s cavalry wins %3d%% | riders lost %5.1f, archers lost %5.1f" % [
			"the open:" if d == 0 else "dense woods:", wins * 100 / seeds, lost[0] / n, lost[1] / n])


## Archers 80 shoot all their arrows at light 100 standing 110 m away in
## the open / in woods of density d.
func _woods_volley() -> void:
	for d in [0, 1, 2, 3]:
		var killed := 0.0
		var shots := 0.0
		for s in seeds:
			var units := [_u(0, UT.ARCHER, 80, 150, 200, UP), _u(1, UT.LIGHT, 100, 150, 90, DOWN)]
			var woods: Array = [[150, 87, 40, 15, d]] if d > 0 else []
			var sim := BattleSim.new()
			sim.setup(_woods_t(units, [_atk(0, 0, 1, 0)], woods), 43000 + s * 139)
			while sim.tick < 1500 and (sim.u_ammo[0] > 0 or sim.projectiles_in_flight() > 0):
				sim.step()
			killed += sim.u_killed[1]
			shots += sim.stat_shots
		var n := float(seeds)
		print("archers 80 volley at light 100 standing in woods %d: killed %5.1f of 100 (%4.0f arrows)" % [d, killed / n, shots / n])


## Pike 120 pinned by heavy 100 with light 100 into its flank, in the open
## and with all of them in medium woods (the pike wall breaks up).
func _woods_pikes() -> void:
	for d in [0, 2]:
		var wins := 0
		var kp := 0.0
		var ka := 0.0
		for s in seeds:
			var units := [_u(0, UT.PIKE, 120, 150, 170, UP), _u(1, UT.HEAVY, 100, 150, 130, DOWN),
				_u(1, UT.LIGHT, 100, 215, 180, LEFT)]
			var woods: Array = [[150, 160, 90, 60, d]] if d > 0 else []
			var sim := BattleSim.new()
			sim.setup(_woods_t(units, [_atk(0, 1, 0, 0), _atk(150, 2, 0, 0)], woods), 44000 + s * 149)
			while sim.tick < max_ticks and sim.winner < 0:
				sim.step()
			if sim.winner == 0:
				wins += 1
			kp += sim.u_killed[0]
			ka += sim.u_killed[1] + sim.u_killed[2]
		var n := float(seeds)
		print("pike 120 pinned by heavy 100, light 100 into flank, %-14s pikes win %3d%% | pikes lost %5.1f, attackers lost %5.1f" % [
			"open:" if d == 0 else "medium woods:", wins * 100 / seeds, kp / n, ka / n])


## Javelins 60 ordered at light 100 standing 35 m away with 20 m of dense
## woods between them (flat throws are blocked) vs the open.
func _woods_javelins() -> void:
	for d in [0, 3]:
		var killed := 0.0
		var shots := 0.0
		for s in seeds:
			var units := [_u(0, UT.JAVELIN, 60, 150, 165, UP), _u(1, UT.LIGHT, 100, 150, 130, DOWN)]
			var woods: Array = [[150, 147, 40, 10, d]] if d > 0 else []
			var sim := BattleSim.new()
			sim.setup(_woods_t(units, [_atk(0, 0, 1, 0)], woods), 45000 + s * 151)
			while sim.tick < 400:
				sim.step()
			killed += sim.u_killed[1]
			shots += sim.stat_shots
		var n := float(seeds)
		print("javelins 60 ordered at light 100 35 m away, %-26s javelins thrown %5.1f, killed %5.1f" % [
			"open ground between:" if d == 0 else "20 m of dense woods between:", shots / n, killed / n])


func _street_t(units: Array, orders: Array, street: bool) -> Dictionary:
	var sc := _scenario(units, orders)
	if street:
		sc["terrain"] = {"kind": 0, "blocks": [[40, 60, 145, 240], [155, 60, 260, 240]],
			"urban": [[40, 60, 260, 240]]}
	return sc


func _streets() -> void:
	for street in [false, true]:
		var where := "street:" if street else "open:"
		# Pikes hold, heavy attack frontally.
		var w1 := 0
		var k1 := [0.0, 0.0]
		# Pikes pinned frontally, light try to flank.
		var w2 := 0
		var k2 := [0.0, 0.0]
		# Cavalry charges heavy.
		var k3 := 0.0
		var w3 := 0
		for s in seeds:
			var sim := BattleSim.new()
			sim.setup(_street_t([_u(0, UT.PIKE, 120, 150, 180, UP, 8), _u(1, UT.HEAVY, 100, 150, 100, DOWN, 8)],
				[_atk(0, 1, 0, 0)], street), 46000 + s * 157)
			while sim.tick < max_ticks and sim.winner < 0:
				sim.step()
			if sim.winner == 0:
				w1 += 1
			k1[0] += sim.u_killed[0]
			k1[1] += sim.u_killed[1]
			var sim2 := BattleSim.new()
			# The light infantry starts beside the pikes (in the open: on
			# their flank; in the street: beyond the east block).
			sim2.setup(_street_t([_u(0, UT.PIKE, 120, 150, 180, UP, 8), _u(1, UT.HEAVY, 100, 150, 100, DOWN, 8),
				_u(1, UT.LIGHT, 100, 275 if street else 215, 180, LEFT, 10)], [_atk(0, 1, 0, 0), _atk(150, 2, 0, 0)], street),
				47000 + s * 163)
			while sim2.tick < max_ticks and sim2.winner < 0:
				sim2.step()
			if sim2.winner == 0:
				w2 += 1
			k2[0] += sim2.u_killed[0]
			k2[1] += sim2.u_killed[1] + sim2.u_killed[2]
			var sim3 := BattleSim.new()
			sim3.setup(_street_t([_u(0, UT.CAVALRY, 60, 150, 230, UP, 8), _u(1, UT.HEAVY, 100, 150, 120, DOWN, 8)],
				[_atk(0, 0, 1, 1)], street), 48000 + s * 167)
			while sim3.tick < 400:
				sim3.step()
			k3 += sim3.u_killed[1]
			while sim3.tick < max_ticks and sim3.winner < 0:
				sim3.step()
			if sim3.winner == 0:
				w3 += 1
		var n := float(seeds)
		print("pike 120 (8 files) holds vs heavy 100 attacking, %-8s pikes win %3d%% | killed %5.1f / %5.1f" % [
			where, w1 * 100 / seeds, k1[0] / n, k1[1] / n])
		print("pike 120 pinned by heavy 100, light 100 at its side, %-8s pikes win %3d%% | killed %5.1f / %5.1f" % [
			where, w2 * 100 / seeds, k2[0] / n, k2[1] / n])
		print("cav 60 charges heavy 100 (8 files),              %-8s infantry killed by 40 s %5.1f | cavalry wins %3d%%" % [
			where, k3 / n, w3 * 100 / seeds])


## Time to break the main gate of a town at wall levels 1-3: a bolt battery,
## a stone battery (both at the attackers' line, 150 m out) or heavy 100
## hacking; with nobody shooting back, and with the garrison's archers on
## the walls (AI defenders).
func _gates() -> void:
	for walls in [1, 2, 3]:
		for who in ["bolts", "stones", "heavy 100", "light 100"]:
			for fire in [false, true]:
				if fire and who != "heavy 100":
					continue
				var t_sum := 0.0
				var w_sum := 0.0
				var broke := 0
				var shots := 0.0
				var lost := 0.0
				var n_runs := mini(seeds, 10)
				for s in n_runs:
					var att: Array = []
					match who:
						"bolts":
							att = [[UT.BOLT, 16]]
						"stones":
							att = [[UT.STONE, 18]]
						"heavy 100":
							att = [[UT.HEAVY, 100]]
						_:
							att = [[UT.LIGHT, 100]]
					var dfn: Array = [[UT.SPEAR, 60]]
					if fire:
						dfn = [[UT.ARCHER, 48], [UT.ARCHER, 48], [UT.SPEAR, 60]]
					var r := Scenarios.settlement({"seed": 202, "level": 1, "walls": walls, "bld": []},
						{"kind": 0, "seed": 5, "forest": 0}, att, dfn, 1, [1] if fire else [])
					var sc: Dictionary = r["scenario"]
					sc["orders"] = [{"tick": 0, "type": ATTACK, "unit": 0, "target": -1, "gate": 0, "run": 1}]
					var sim := BattleSim.new()
					sim.setup(sc, 49000 + s * 173)
					var first := -1
					while sim.tick < 6000 and sim.g_state[0] == BattleSim.GATE_CLOSED and sim.u_state[0] == BattleSim.U_READY:
						sim.step()
						if first < 0 and sim.g_hit_t[0] >= 0:
							first = sim.tick
					if sim.g_state[0] == BattleSim.GATE_BROKEN:
						broke += 1
						t_sum += sim.tick / 10.0
						w_sum += (sim.tick - first) / 10.0
					shots += sim.stat_bolts + sim.stat_stones
					lost += sim.u_killed[0]
				var line := "walls %d, %-10s%-16s broke the gate %2d/%d" % [walls, who,
					" (under fire)" if fire else "", broke, n_runs]
				if broke > 0:
					line += " at %5.1f s (%5.1f s from the first blow)" % [t_sum / broke, w_sum / broke]
				if who == "bolts" or who == "stones":
					line += " | %4.1f shots" % (shots / n_runs)
				else:
					line += " | men lost %4.1f" % (lost / n_runs)
				print(line)


## Garrison only (town; 3 + walls units of 60: spears, archers, heavy...)
## against the standard 12-unit attacker, AI vs AI, with and without its
## two batteries.
func _garrison_defence() -> void:
	var n_runs := mini(seeds, 10)
	for walls in [0, 1, 2, 3]:
		for arty in [true, false]:
			var aw := 0
			var dr := 0
			var t_sum := 0.0
			var t_max := 0.0
			var att_lost := 0.0
			for s in n_runs:
				var att: Array = []
				for e in Scenarios.SIEGE_ARMY:
					if not arty and UT.cls(int(e[0])) == UT.CLS_ART:
						continue
					att.append(e)
				var dfn: Array = []
				for k in 3 + walls:
					dfn.append([Scenarios.SIEGE_GARRISON[k % Scenarios.SIEGE_GARRISON.size()], 60])
				var r := Scenarios.settlement({"seed": 202 + s, "level": 1, "walls": walls, "bld": [2]},
					{"kind": 1, "seed": 11 + s, "forest": 15, "ground": 2}, att, dfn, 1, [0, 1])
				var sim := BattleSim.new()
				_with_skill(r["scenario"])
				sim.setup(r["scenario"], 50000 + s * 181)
				while sim.tick < sim.time_limit + 10 and sim.winner < 0:
					sim.step()
				var dt: float = (sim.decided_tick if sim.decided_tick >= 0 else sim.tick) / 600.0
				if sim.winner == 0:
					aw += 1
				elif sim.winner == 2 or sim.winner < 0:
					dr += 1
				t_sum += dt
				t_max = maxf(t_max, dt)
				var res := sim.result()
				att_lost += int(res["sides"][0]["killed"])
			print("walls %d, attacker %-17s attacker wins %3d%%, draws %3d%% | decided in %4.1f min (max %4.1f) | attackers killed %5.1f" % [
				walls, "with artillery:" if arty else "without artillery:", aw * 100 / n_runs, dr * 100 / n_runs,
				t_sum / n_runs, t_max, att_lost / n_runs])


## --only=fair-sieges: equal-force sieges (Scenarios.fair_siege: the
## defenders' garrison plus field army as strong as SIEGE_ARMY), ring and
## polis on flat ground, walls 1-3, 10 seeds, both AI sides Average
## (--skill=A:B), the attacker with ladders and a ram (row 0: a siege of two
## turns) or artillery only (row 1: an assault on arrival); row 2, the full
## kit of a three-turn siege: ladders, a ram, 4 mantlets, a siege tower at
## walls 2-3 and a unit of scorpions.
## Targets
## (docs/STATUS.md): walls 3 about 25 % attacker wins, walls 1 about 45 %
## (row 0); row 1 lower at walls 2-3. --plans / --walls / --rows shard it;
## --time-limit=S sets the battle time limit.
func _fair_sieges() -> void:
	var n_runs := mini(seeds, 10)
	var specs := [["ring", MapGen.PLAN_RING], ["polis", MapGen.PLAN_POLIS]]
	for spec in specs:
		if not plans_only.is_empty() and not plans_only.has(int(spec[1])):
			continue
		for walls in [1, 2, 3]:
			if not walls_only.is_empty() and not walls_only.has(walls):
				continue
			for row in 3:
				if not rows_only.is_empty() and not rows_only.has(row):
					continue
				var eq := {"ladders": 3, "ram": 1} if row == 0 else {}  # (a siege of two turns)
				if row == 2:
					# Full kit: what a campaign assault after three siege turns
					# brings (CBattle.siege_equipment: 3 ladder sets, a ram, 4
					# mantlets, a tower at walls 2-3) and the attackers' scorpions.
					eq = {"ladders": 3, "ram": 1, "mantlets": 4, "towers": 1 if walls >= 2 else 0,
						"extra": [[UT.index_of("scorpions"), 12]]}
				var aw := 0
				var dr := 0
				var withdrew := 0
				var t_sum := 0.0
				var t_max := 0.0
				var att_lost := 0.0
				var def_lost := 0.0
				var lad := 0
				var unbar := 0
				var blows := 0
				var tw_down := 0
				var tw_hits := 0
				var tw_kills := 0
				var gate_by := [0, 0, 0]  # broken (artillery / ram / hack), opened from inside counted in unbar
				var caps := 0
				var stuck_max := 0  # longest no-progress count of any unit (u_stuck, ticks)
				var stuck_n := 0    # units past 200 ticks (20 s)
				var stuck_who := ""
				for s in n_runs:
					var sc := Scenarios.fair_siege(700 + s * 41, walls, int(spec[1]), eq)
					if time_limit > 0:
						sc["time_limit"] = time_limit
					_with_skill(sc)
					var sim := BattleSim.new()
					sim.setup(sc, 53000 + s * 197)
					while sim.tick < sim.time_limit + 10 and sim.winner < 0:
						sim.step()
					var dt: float = (sim.decided_tick if sim.decided_tick >= 0 else sim.tick) / 600.0
					if sim.winner == 0:
						aw += 1
					elif sim.winner == 2 or sim.winner < 0:
						dr += 1
					if sim.ai_phase[0] == 3:
						withdrew += 1
					t_sum += dt
					t_max = maxf(t_max, dt)
					var res := sim.result()
					att_lost += int(res["sides"][0]["killed"])
					def_lost += int(res["sides"][1]["killed"])
					lad += sim.stat_ladder_up
					unbar += sim.stat_unbar
					blows += sim.stat_ram_blows
					tw_down += sim.stat_towers_down
					tw_hits += sim.stat_tower_hits
					tw_kills += sim.stat_tower_kills
					caps += sim.stat_capture
					for u in sim.n_units:
						var su: int = sim.stat_stuck_u[u] if u < sim.stat_stuck_u.size() else 0
						if su > 200:
							stuck_n += 1
						if su > stuck_max:
							stuck_max = su
							stuck_who = "seed %d unit %d (side %d, %s)" % [s, u, sim.u_side[u], UT.key_of(sim.u_type[u])]
					if sim.stat_gate_broken > 0:
						if sim.stat_ram_blows > 0:
							gate_by[1] += 1
						elif sim.stat_gate_art > 0:
							gate_by[0] += 1
						else:
							gate_by[2] += 1
				print("%-6s walls %d %-15s attacker %3d%%, defender %3d%%, draws %3d%% (withdrew %d) | %4.1f min (max %4.1f) | killed att %5.1f def %5.1f | ladder men up %5.1f, gates opened from inside %d, ram blows %4.1f, gate broken by art/ram/hack %d/%d/%d | towers hit %4.1f, down %3.1f, killed %5.1f | captures %d/%d | stuck max %d (%s), units past 20 s %d" % [
					spec[0], walls, ["ladders + ram:", "artillery only:", "full kit:"][row], aw * 100 / n_runs,
					(n_runs - aw - dr) * 100 / n_runs, dr * 100 / n_runs, withdrew, t_sum / n_runs, t_max,
					att_lost / n_runs, def_lost / n_runs, float(lad) / n_runs, unbar, float(blows) / n_runs,
					gate_by[0], gate_by[1], gate_by[2], float(tw_hits) / n_runs, float(tw_down) / n_runs, float(tw_kills) / n_runs, caps, n_runs,
					stuck_max, stuck_who, stuck_n])


## The settlement tests AI vs AI over seeds: decided by when, no draws.
func _siege_battles() -> void:
	var n_runs := mini(seeds, 10)
	for spec in [["open village", 0, 0, 3, 1], ["walled town", 1, 1, 2, 1], ["city walls 2", 2, 2, 1, 0],
			["hill city walls 3", 2, 3, 4, 4]]:
		var aw := 0
		var dr := 0
		var t_sum := 0.0
		var t_max := 0.0
		var caps := 0
		for s in n_runs:
			var sc := Scenarios.siege_test(500 + s * 37, int(spec[1]), int(spec[2]), int(spec[3]), int(spec[4]), 1)
			sc["ai_sides"] = [0, 1]
			_with_skill(sc)
			var sim := BattleSim.new()
			sim.setup(sc, 51000 + s * 191)
			while sim.tick < sim.time_limit + 10 and sim.winner < 0:
				sim.step()
			var dt: float = (sim.decided_tick if sim.decided_tick >= 0 else sim.tick) / 600.0
			if sim.winner == 0:
				aw += 1
			elif sim.winner == 2 or sim.winner < 0:
				dr += 1
			caps += sim.stat_capture
			t_sum += dt
			t_max = maxf(t_max, dt)
		print("%-18s attacker wins %3d%%, defender %3d%%, draws %3d%% | decided in %4.1f min (max %4.1f) | plaza captures %d/%d" % [
			spec[0], aw * 100 / n_runs, (n_runs - aw - dr) * 100 / n_runs, dr * 100 / n_runs, t_sum / n_runs, t_max, caps, n_runs])



## Each plan on its representative site at walls 1-3 (a city: garrison +
## a 4-unit field army vs the standard 12-unit attacker), AI vs AI: who
## wins, how long it takes, what it costs the attacker; the original ring
## on the same ground as the baseline.
func _plan_sieges() -> void:
	var n_runs := mini(seeds, 10)
	var specs := [["ring, plain", 4, Terrain.K_FLAT, 0], ["ring, hill (plateau)", 4, Terrain.K_HILL, 0],
		["castrum, plain", 0, Terrain.K_FLAT, 0], ["polis, coastal hill", 1, Terrain.K_HILL, 1],
		["polis, plain", 1, Terrain.K_FLAT, 0], ["punic, coast", 2, Terrain.K_FLAT, 1],
		["oppidum, spur", 3, Terrain.K_RIDGE, 0], ["oppidum, plain", 3, Terrain.K_FLAT, 0]]
	for spec in specs:
		if not plans_only.is_empty() and not plans_only.has(int(spec[1])):
			continue
		for walls in [1, 2, 3]:
			if not walls_only.is_empty() and not walls_only.has(walls):
				continue
			var aw := 0
			var dr := 0
			var t_sum := 0.0
			var t_max := 0.0
			var caps := 0
			var att_lost := 0.0
			var def_lost := 0.0
			var cit_broken := 0
			var cit_shut := 0
			var stairs := 0
			var withdrew := 0
			var sk_moves := [0, 0]
			for s in n_runs:
				var sc := Scenarios.siege_test(700 + s * 41, 2, walls, 2, int(spec[2]), 1, -1, int(spec[1]), int(spec[3]))
				sc["ai_sides"] = [0, 1]
				_with_skill(sc)
				var sim := BattleSim.new()
				sim.setup(sc, 53000 + s * 197)
				while sim.tick < sim.time_limit + 10 and sim.winner < 0:
					sim.step()
				var dt: float = (sim.decided_tick if sim.decided_tick >= 0 else sim.tick) / 600.0
				if sim.winner == 0:
					aw += 1
				elif sim.winner == 2 or sim.winner < 0:
					dr += 1
				if sim.ai_phase[0] == 3:
					withdrew += 1
				caps += sim.stat_capture
				t_sum += dt
				t_max = maxf(t_max, dt)
				var res := sim.result()
				att_lost += int(res["sides"][0]["killed"])
				def_lost += int(res["sides"][1]["killed"])
				if sim.cit_gate >= 0:
					if sim.g_state[sim.cit_gate] == BattleSim.GATE_BROKEN:
						cit_broken += 1
					if sim.ai_cit[1] != 0:
						cit_shut += 1
				stairs += sim.stat_stair_down + sim.stat_stair_rout
				for side in 2:
					sk_moves[side] += sim.stat_aic[side * AP.N_COUNTERS + AP.C_SIEGE]
			var sk_note := ""
			if skill.size() == 2:
				sk_note = " | siege moves att %d def %d" % [sk_moves[0], sk_moves[1]]
			print("%-21s walls %d: attacker wins %3d%%, defender %3d%%, draws %3d%% (withdrew %d) | %4.1f min (max %4.1f) | killed att %5.1f def %5.1f | captures %d/%d | citadel held %d, gate broken %d | stair moves %.1f" % [
				spec[0], walls, aw * 100 / n_runs, (n_runs - aw - dr) * 100 / n_runs, dr * 100 / n_runs, withdrew,
				t_sum / n_runs, t_max, att_lost / n_runs, def_lost / n_runs, caps, n_runs, cit_shut, cit_broken,
				float(stairs) / n_runs] + sk_note)


## Field battles on generated ground with woods: decided, no draws.
func _forest_battles() -> void:
	var n_runs := mini(seeds, 10)
	var dr := 0
	var t_sum := 0.0
	var t_max := 0.0
	var wins := [0, 0]
	var shelters := 0
	for s in n_runs:
		var sc := Scenarios.make("bench_2000")
		sc["terrain"] = {"kind": Terrain.K_RANDOM, "forest": 40, "seed": 900 + s}
		var sim := BattleSim.new()
		sim.setup(sc, 52000 + s * 193)
		while sim.tick < sim.time_limit + 10 and sim.winner < 0:
			sim.step()
		var dt: float = (sim.decided_tick if sim.decided_tick >= 0 else sim.tick) / 600.0
		if sim.winner == 0 or sim.winner == 1:
			wins[sim.winner] += 1
		else:
			dr += 1
		shelters += sim.stat_ai[15]
		t_sum += dt
		t_max = maxf(t_max, dt)
	print("woods 40 on generated ground: bottom wins %d, top %d, draws %d of %d | decided in %4.1f min (max %4.1f) | archers sheltering in woods %d times" % [
		wins[0], wins[1], dr, n_runs, t_sum / n_runs, t_max, shelters])
