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
##   mirrored (--fair=N).

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")

const UP := Scenarios.FACE_UP
const DOWN := Scenarios.FACE_DOWN
const LEFT := Scenarios.FACE_LEFT
const ATTACK := BattleSim.ORDER_ATTACK

var seeds := 20
var only := ""
var max_ticks := 3000
var fair_n := 0       # --fair=N: only the mirrored-fairness check, N seeds
var seed0 := 0        # --seed0=K: first seed index (for sharding --fair runs)
var fair_variants: Array = ["side0_first", "side1_first"]  # --fair-variants=a,b


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
	var t0 := Time.get_ticks_msec()
	if fair_n > 0:
		_fairness(fair_n)
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
	_section("Mirrored fairness: identical units face each other, both attack (bottom side 0 vs top side 1, both unit orders)")
	_mirror_duels()
	_section("Full battle")
	_full_battles()
	print("\n(done in %.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit(0)


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


func _scenario(units: Array, orders: Array) -> Dictionary:
	return {"width_m": 300, "height_m": 300, "ai_sides": [], "units": units, "orders": orders}


func _skip(name: String) -> bool:
	return only != "" and name.find(only) < 0


## Run a scripted duel over the seeds. `focus` >= 0 reports that unit's
## fate in detail (rout tick, losses).
func _duel(name: String, units: Array, orders: Array, focus: int = -1) -> void:
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
		sim.setup(_scenario(units, orders), 1000 + s * 7919)
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
			var sim := BattleSim.new()
			sim.setup(scn, 77 + s * 31)
			while sim.tick < 12000 and sim.winner < 0:
				sim.step()
			wins[sim.winner if sim.winner >= 0 else 2] += 1
			var r: Dictionary = sim.result()
			for side in 2:
				killed[side] += int(r["sides"][side]["killed"])
		print("FAIR %s n=%d bottom(side0)=%d top(side1)=%d draw=%d killed0=%d killed1=%d" % [
			variant, n, wins[0], wins[1], wins[2], killed[0], killed[1]])


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
