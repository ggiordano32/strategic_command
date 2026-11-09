extends SceneTree
## Weather duels (docs/design/battle_sim.md "Weather in battle (as built, 2026-11-09)"), headless:
##   godot --headless --script res://tests/wx_duel.gd [-- --seeds=8 --only=musket --wx=clear,fog]
## Four matchups at each weather (the scenario's "weather"; sim/wx.gd), over the seeds; side A stands on side 0 in even
## seeds and side 1 in odd ones (the top / bottom bias cancels): musket v musket, musket v bow, a horse charge v pikes,
## 3 guns v a walled town's gate. Prints A's wins and draws, both sides' men lost, the battle's length, the shots
## (missiles and gun volleys or engine shots) and the first shot's distance. The point (the plan): rain hurts powder
## more than bows, fog shortens the fights; not that a side flips. Exits 0; --check fails on a clear-day hash that is
## not the battle's without the key (the weather absent hashes as before) or a repeat that diverges.

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const Terrain := preload("res://sim/terrain.gd")

var seeds := 8
var only := ""
var wxs := ["clear", "rain", "downpour", "blizzard", "fog"]
var max_ticks := 9000
var check := false
var fails := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.get_slice("=", 1))
		elif a.begins_with("--only="):
			only = a.get_slice("=", 1)
		elif a.begins_with("--wx="):
			wxs = Array(a.get_slice("=", 1).split(","))
		elif a == "--check":
			check = true
	# [name, A key, B key, men A, men B, gap m, A attacks, B attacks, A runs]
	var cases := [
		["musket v musket", "musketeers", "musketeers", 100, 100, 200, true, true, false],
		["musket v bow", "musketeers", "native_bowmen", 100, 100, 200, true, true, false],
		["horse charge v pikes", "lancers", "w_pikemen", 60, 120, 160, true, false, true],
	]
	print("weather   | case                 | A wins | draws | men lost A v B   | length | shots (both) | 1st shot m")
	for c in cases:
		if only != "" and str(c[0]).find(only) < 0:
			continue
		for w in wxs:
			_case(c, str(w))
	if only == "" or "guns".find(only) >= 0 or only.find("gun") >= 0:
		for w in wxs:
			_guns(str(w))
	if only == "" or only == "ai":
		for id in ["bench_west_muskets", "west_town", "battle_2000"]:
			for w in wxs:
				_ai(id, str(w))
	if check:
		_check()
		print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


func _sc(c: Array, vs: int, w: String) -> Dictionary:
	var ta := UT.index_of(str(c[1]))
	var tb := UT.index_of(str(c[2]))
	var gap := int(c[5])
	var units := []
	for s in 2:
		var a := s == vs
		var y := 200 + gap / 2 if s == 0 else 200 - gap / 2
		units.append(Scenarios.unit(s, ta if a else tb, int(c[3]) if a else int(c[4]), 150, y, Scenarios.FACE_UP if s == 0 else Scenarios.FACE_DOWN))
	var orders := []
	if bool(c[6]):
		orders.append(Scenarios.attack(0, vs, 1 - vs, 1 if bool(c[8]) else 0))
	if bool(c[7]):
		orders.append(Scenarios.attack(0, 1 - vs, vs, 0))
	var sc := {"width_m": 300, "height_m": 400, "ai_sides": [], "units": units, "orders": orders}
	if w != "":
		sc["weather"] = w
	return sc


func _case(c: Array, w: String) -> void:
	var win := 0
	var draw := 0
	var lost := [0, 0]
	var t_sum := 0
	var shots := 0
	var first_d := 0
	var first_n := 0
	for k in seeds:
		var vs := k & 1
		var sim := BattleSim.new()
		sim.setup(_sc(c, vs, w), 4242 + k * 7919)
		var seen := false
		var last := 0
		while sim.tick < max_ticks and sim.ended == 0:
			sim.step()
			if not seen and sim.stat_shots > 0:
				seen = true
				first_d += sim._unit_dist(0, 1) / BattleSim.M
				first_n += 1
			last = sim.stat_shots
		if sim.winner == vs:
			win += 1
		elif sim.winner < 0:
			draw += 1
		lost[0] += sim.u_count0[vs] - sim.u_alive[vs]
		lost[1] += sim.u_count0[1 - vs] - sim.u_alive[1 - vs]
		shots += last
		t_sum += (sim.decided_tick if sim.decided_tick >= 0 else sim.tick) / 10
	print("%-9s | %-20s | %5d%% | %4d%% | %6.1f v %6.1f | %5d s | %12d | %s" % [w, c[0], win * 100 / seeds, draw * 100 / seeds,
		float(lost[0]) / seeds, float(lost[1]) / seeds, t_sum / seeds, shots / seeds,
		("%d" % (first_d / first_n)) if first_n > 0 else "-"])


## 3 culverin batteries ordered at a walls-2 town's gate (the town held by a spear unit), 240 s: the gate's hit
## points lost (%), the gun shots, the first shot's distance to the gate.
func _guns(w: String) -> void:
	var gun := UT.index_of("field_gun")
	var lost_pct := 0
	var shots := 0
	var broke := 0
	var fd := 0
	var fn := 0
	for k in seeds:
		var city := {"seed": 303 + k, "level": 1, "walls": 2, "bld": [1, 2, 4]}
		var terr := {"kind": Terrain.K_FLAT, "seed": (303 + k) * 7 + 3, "forest": 0, "ground": 1}
		var att := [[gun, UT.size_of(gun)], [gun, UT.size_of(gun)], [gun, UT.size_of(gun)]]
		var sc: Dictionary = Scenarios.settlement(city, terr, att, [[UT.SPEAR, 60]], 1, [])["scenario"]
		sc.erase("deploy_zones")
		if w != "":
			sc["weather"] = w
		var orders := []
		for u in 3:
			var o := Scenarios.attack(0, u, -1, 0)
			o["gate"] = 0
			orders.append(o)
		sc["orders"] = orders
		var sim := BattleSim.new()
		sim.setup(sc, 77 + k * 31)
		var hp0: int = sim.g_hp[0]
		var seen := false
		while sim.tick < 2400 and sim.ended == 0:
			sim.step()
			if not seen and sim.stat_cannon > 0:
				seen = true
				fd += FM_len(sim.u_cx[0] - sim.g_x[0], sim.u_cy[0] - sim.g_y[0]) / BattleSim.M
				fn += 1
		lost_pct += (hp0 - maxi(sim.g_hp[0], 0)) * 100 / maxi(hp0, 1)
		shots += sim.stat_cannon
		if sim.g_state[0] == BattleSim.GATE_BROKEN:
			broke += 1
	print("%-9s | %-20s | gate broken %d of %d | gate hp lost %3d%% | shots %4d | 1st shot %s m" % [w, "3 guns v gate", broke, seeds,
		lost_pct / seeds, shots / seeds, ("%d" % (fd / fn)) if fn > 0 else "-"])


## Both sides under the battle AI (Scenarios.make(id)), 2 seeds: the winner, the length, the shots (missiles, gun
## shots): the AI's range and sight reads must keep it firing in every weather (no stand-off out of reach).
func _ai(id: String, w: String) -> void:
	var wins := [0, 0, 0]
	var t_sum := 0
	var shots := 0
	var guns := 0
	var n := 2
	for k in n:
		var sc: Dictionary = Scenarios.make(id)
		sc["ai_sides"] = [0, 1]
		if w != "":
			sc["weather"] = w
		var sim := BattleSim.new()
		sim.setup(sc, 900 + k * 17)
		while sim.tick < max_ticks and sim.ended == 0:
			sim.step()
		wins[sim.winner if sim.winner >= 0 else 2] += 1
		t_sum += (sim.decided_tick if sim.decided_tick >= 0 else sim.tick) / 10
		shots += sim.stat_shots
		guns += sim.stat_cannon + sim.stat_stones
	print("%-9s | AI %-18s | side 0 / 1 / none %d / %d / %d | length %4d s | shots %6d | gun shots %4d" % [w, id, wins[0], wins[1], wins[2],
		t_sum / n, shots / n, guns / n])


static func FM_len(dx: int, dy: int) -> int:
	return int(sqrt(float(dx) * dx + float(dy) * dy))


## --check: the clear day without the key and with "clear" or a season hash alike; a downpour differs and repeats.
func _check() -> void:
	var c: Array = ["musket v bow", "musketeers", "native_bowmen", 100, 100, 200, true, true, false]
	var hs := []
	for w in ["", "clear", "overcast,summer", "downpour,wet", "downpour,wet"]:
		var sim := BattleSim.new()
		sim.setup(_sc(c, 0, w), 99)
		for i in 900:
			sim.step()
		hs.append(sim.state_hash())
	if hs[0] != hs[1] or hs[0] != hs[2]:
		print("FAIL: a clear day / overcast hashes apart from no weather: %s" % str(hs))
		fails += 1
	if hs[3] == hs[0]:
		print("FAIL: a downpour hashes as the clear day")
		fails += 1
	if hs[3] != hs[4]:
		print("FAIL: the downpour's repeat diverged")
		fails += 1
