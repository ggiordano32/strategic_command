extends SceneTree
## Custom battles (game/custom/custom_setup.gd), headless:
##   godot --headless --script res://tests/custom_battle_test.gd
## Every template and a few hand-made setups (two armies a side, Player 2 on
## the enemy side, a settlement, funds) build into a scenario the same way
## twice (and the same after a JSON round trip, as the relay passes it on),
## with a player for every unit of a human side and the AI on the others;
## the battle deploys (the player places a unit, readies) and runs; the
## setup checks refuse what cannot be played; siege equipment (ladders, a
## ram) and the battle time limit reach the scenario; a unit's special
## ammunition kind ("ak") and a wagon's stock of its army's kinds ("aks")
## reach the sim, survive the online setup's JSON round trip and change the
## scenario hash both peers compare; one unit of each light horse and
## slinger row builds on a field and shoots (its weapon's kind, skirmish on,
## the Balearics' lead bullets); scorpions (with heavy bolts) and
## gastraphetes build on a field and both shoot. River crossings: "River
## crossing: ford / bridge" gives the scenario its "river" key from the map
## seed (side 2, or the fortified side, holding the far bank), the
## deployment zones end short of the water, the sim builds the crossing map
## (its camp at the crossing when fortified); none on a settlement map or
## without the option; a ford and a bridge battle run. Heroes and agents:
## a side's character toggles (all six a side) reach the scenario's "chars",
## cost their price, build into one-man units after the scenario's own
## (commanded by the side's player, the AI's on its side) on a field and in
## a settlement, and the result rows carry "char" / "alive".

const CS := preload("res://game/custom/custom_setup.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const FM := preload("res://sim/fixed_math.gd")
const Lockstep := preload("res://sim/lockstep.gd")
const UT := preload("res://sim/unit_types.gd")
const CoopSession := preload("res://game/net/coop_session.gd")
const Terrain := preload("res://sim/terrain.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const MapGen := preload("res://sim/mapgen.gd")
const SeaSim := preload("res://sim/sea_sim.gd")

var _ok := true


func _fail(msg: String) -> void:
	_ok = false
	printerr("FAIL " + msg)


func _init() -> void:
	var setups := {}
	for id in CS.TEMPLATES:
		setups["template " + id] = CS.template(id, 11)
	var two := CS.default_setup(5)
	two["sides"][0]["armies"].append({"ctrl": "ai", "units": [["spear", 100], ["archer", 80], ["bolt", 16]]})
	two["sides"][1]["armies"][0]["ctrl"] = "p2"
	two["sides"][1]["armies"].append({"ctrl": "p2", "units": [["phalangites", 120], ["companions", 60]]})
	setups["two armies a side, head-to-head"] = two
	var town := CS.default_setup(6)
	town["map"]["kind"] = "settlement"
	town["map"]["walls"] = 2
	town["map"]["def"] = 0
	town["sides"][0]["armies"][0]["units"].append(["javelin", 60])
	setups["settlement, players defend"] = town
	var storm := CS.default_setup(8)
	storm["map"]["kind"] = "settlement"
	storm["map"]["walls"] = 3
	storm["map"]["level"] = 2
	storm["map"]["ladders"] = 1
	storm["map"]["ram"] = 1
	storm["map"]["towers"] = 2
	storm["time"] = 1800
	setups["settlement, players storm with ladders, a ram and two siege towers, 30 min"] = storm
	var works := CS.default_setup(9)
	works["map"]["works"] = 2
	works["map"]["fortified"] = 1
	setups["field works, side 2 fortified"] = works
	var coop := CS.default_setup(7)
	coop["sides"][0]["armies"].append({"ctrl": "p2", "units": [["heavy2", 100], ["cav3", 60]]})
	setups["co-op"] = coop
	var ammo := _ammo_setup()
	setups["wagon and fire arrows, head-to-head"] = ammo
	var ammo_town: Dictionary = _ammo_setup()
	ammo_town["map"]["kind"] = "settlement"
	ammo_town["map"]["walls"] = 1
	setups["wagon and fire arrows, settlement"] = ammo_town
	var mant := CS.default_setup(12)
	mant["sides"][0]["mantlets"] = 4
	mant["sides"][1]["mantlets"] = 2
	setups["mantlets 4 / 2, field"] = mant
	var mant_town: Dictionary = JSON.parse_string(JSON.stringify(mant))
	mant_town["map"]["kind"] = "settlement"
	mant_town["map"]["walls"] = 1
	mant_town["map"]["ladders"] = 1
	setups["mantlets 4 / 2, settlement"] = mant_town
	var ford := CS.default_setup(13)
	ford["map"]["river"] = 0
	ford["map"]["fortified"] = 1
	setups["river crossing: a ford, side 2 fortified at it"] = ford
	var bridge := CS.default_setup(14)
	bridge["map"]["river"] = 1
	setups["river crossing: a bridge"] = bridge
	var chf := CS.default_setup(15)
	for sd in 2:
		for k in CS.CHAR_KEYS:
			CS.toggle_char(chf, sd, k)
	setups["heroes and agents, all six a side, field"] = chf
	var cht: Dictionary = JSON.parse_string(JSON.stringify(chf))
	cht["map"]["kind"] = "settlement"
	cht["map"]["walls"] = 1
	setups["heroes and agents, all six a side, settlement"] = cht
	for name in setups:
		var st: Dictionary = setups[name]
		var a := CS.build(st)
		var b := CS.build(JSON.parse_string(JSON.stringify(st)))
		if a.has("error"):
			_fail("%s: %s" % [name, a["error"]])
			continue
		if JSON.stringify([a["scenario"], a["seed"], a["home"]]) != JSON.stringify([b["scenario"], b["seed"], b["home"]]):
			_fail("%s: built differently after a JSON round trip" % name)
		var sc: Dictionary = a["scenario"]
		var home: Array = a["home"]
		var n_scn: int = (sc["units"] as Array).size()
		var walled: bool = str(st["map"].get("kind", "")) == "settlement" and int(st["map"].get("walls", 0)) > 0
		if home.size() != n_scn + (1 if walled else 0):
			_fail("%s: home has %d entries for %d units" % [name, home.size(), n_scn])
			continue
		for i in n_scn:
			var side := int(sc["units"][i]["side"])
			var human := not (sc["ai_sides"] as Array).has(side)
			if human != (int(home[i]) >= 0):
				_fail("%s: unit %d of side %d has player %d" % [name, i, side, int(home[i])])
				break
		_run(name, a)
	# Siege equipment and the time limit reach the scenario: equipment
	# objects (CS.LADDER_SETS sets of ladders and a ram), not units, so no
	# home entry of their own (only the towers' trailing one).
	var sb := CS.build(storm)
	var lad := 0
	var ram := 0
	var tws := 0
	for e in (sb["scenario"].get("equip", []) as Array):
		if int(e[0]) == BattleSim.EQ_LADDERS:
			lad += 1
		elif int(e[0]) == BattleSim.EQ_RAM:
			ram += 1
		elif int(e[0]) == BattleSim.EQ_TOWER:
			tws += 1
	var n_sc: int = (sb["scenario"]["units"] as Array).size()
	if lad != CS.LADDER_SETS or ram != 1 or tws != 2 or (sb["home"] as Array).size() != n_sc + 1 \
			or int(sb["scenario"].get("time_limit", 0)) != 1800:
		_fail("storm: %d ladder sets, %d rams, %d siege towers, %d home entries for %d units, time limit %s" % [lad, ram,
			tws, (sb["home"] as Array).size(), n_sc, str(sb["scenario"].get("time_limit", 0))])
	else:
		var tsim := BattleSim.new()
		tsim.setup(sb["scenario"], int(sb["seed"]))
		var tq := 0
		for q in tsim.n_eq:
			if tsim.q_kind[q] == BattleSim.EQ_TOWER and tsim.q_state[q] == BattleSim.Q_GROUND \
					and tsim.q_hp[q] == BattleSim.EQ_HP[BattleSim.EQ_TOWER]:
				tq += 1
		# Walls 1: the option gives no towers (they serve walls 2-3).
		var low: Dictionary = JSON.parse_string(JSON.stringify(storm))
		low["map"]["walls"] = 1
		var lb := CS.build(low)
		var low_t := 0
		for e in (lb["scenario"].get("equip", []) as Array):
			if int(e[0]) == BattleSim.EQ_TOWER:
				low_t += 1
		if tq != 2 or low_t != 0:
			_fail("storm: %d siege towers on the ground at the start (walls 1: %d)" % [tq, low_t])
		else:
			print("PASS storm with siege towers: 2 on the ground at the start (%d hit points each), none at walls 1" % BattleSim.EQ_HP[BattleSim.EQ_TOWER])
	_check_works()
	_check_ammo(ammo, "field")
	_check_ammo(ammo_town, "settlement")
	_check_light_missile()
	_check_light_art()
	_check_mantlets(mant, mant_town)
	_check_river(ford, bridge)
	_check_chars(chf, cht)
	# Checks.
	var bad := CS.default_setup(1)
	bad["sides"][1]["armies"] = []
	if CS.check(bad, false) == "":
		_fail("a side without an army was accepted")
	var rich := CS.default_setup(1)
	rich["funds"] = 1
	rich["sides"][0]["armies"][0]["units"].append(["companions", 60])
	if CS.check(rich, false) == "":
		_fail("a side over its funds was accepted")
	if CS.check(CS.default_setup(1), true) == "":
		_fail("online without an army for Player 2 was accepted")
	var three := CS.default_setup(1)
	three["sides"][0]["armies"].append({"ctrl": "p2", "units": [["heavy", 100]]})
	three["sides"][1]["armies"][0]["ctrl"] = "p2"
	if CS.check(three, true) == "":
		_fail("a player on both sides was accepted")
	# Solo: Player 2's armies on the other side become the AI's.
	var solo := CS.build(two, true)
	if not (solo["scenario"]["ai_sides"] as Array).has(1):
		_fail("solo: Player 2's side is not the AI's")
	_check_sea()
	_check_occupy()
	_check_play_scenarios()
	_check_lof()
	await _check_names()
	print("RESULT: %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


## Buildings block a flat shot (docs/design/battle_sim.md, as built 2026-11-06), on tests/lof_probe.gd's town case (a
## 60-man line 40 m off a pike block standing 8 m behind the outermost house of a West open town): a musket line
## ordered to attack has no line of fire at the start, takes no shot while it has none, walks round the house (the
## fire spot) and shoots once it has one, its balls not drawn across a house; on fire at will it neither shoots
## nor moves; a bow line lobs over the house (the lob's range cut) from where it stands.
func _check_lof() -> void:
	var Probe = load("res://tests/lof_probe.gd")
	for mode in ["atk", "faw"]:
		var sim := BattleSim.new()
		sim.setup(Probe.scenario("musket", "town", 40, mode), 7)
		if mode == "atk":
			sim.queue_order(BattleSim.make_attack_order(0, 0, 1, 0))
		sim.step()
		if sim.lof_units(0, 1):
			_fail("lof: the musket line has a line of fire through the house at the start")
		var x0: int = sim.u_cx[0]
		var y0: int = sim.u_cy[0]
		var first := -1
		var moved_first := 0
		var thru := 0
		var shots := 0
		for k in 600:
			var tb: int = sim.tick
			var had: bool = sim.lof_units(0, 1)
			sim.step()
			if sim.stat_shots > shots:
				if first < 0:
					first = k
					moved_first = int(Vector2(sim.u_cx[0] - x0, sim.u_cy[0] - y0).length()) / 1024
					if not had and not sim.lof_units(0, 1):
						_fail("lof: the musket line fired with no line of fire (tick %d)" % k)
				for p in sim.pr_t0.size():
					if sim.pr_t0[p] == tb and sim.pr_unit[p] == 0 \
							and Probe.crosses_house(sim, sim.pr_sx[p], sim.pr_sy[p], sim.pr_x[p], sim.pr_y[p]):
						thru += 1
				shots = sim.stat_shots
		var moved := int(Vector2(sim.u_cx[0] - x0, sim.u_cy[0] - y0).length()) / 1024
		if mode == "atk":
			if first < 0 or moved_first < 5 or sim.stat_lof_walk == 0:
				_fail("lof: the attack order did not walk round the house for a line (first shot tick %d, walked %d m, walk ticks %d)" % [first, moved_first, sim.stat_lof_walk])
			if thru * 10 > shots:
				_fail("lof: %d of %d balls drawn across a house" % [thru, shots])
		elif shots > 0 or moved > 2:
			_fail("lof: fire at will with no line shot %d balls or moved %d m" % [shots, moved])
	var sb := BattleSim.new()
	sb.setup(Probe.scenario("bow", "town", 40, "atk"), 7)
	sb.queue_order(BattleSim.make_attack_order(0, 0, 1, 0))
	sb.step()
	if not sb.lob_over_wall(0, 1):
		_fail("lof: the bow line's shot over the house is not a lob")
	var bx: int = sb.u_cx[0]
	var by: int = sb.u_cy[0]
	for k in 100:
		sb.step()
	if sb.stat_shots == 0 or int(Vector2(sb.u_cx[0] - bx, sb.u_cy[0] - by).length()) / 1024 > 3:
		_fail("lof: the bow line did not lob over the house from where it stands (%d shots)" % sb.stat_shots)
	print("lof: checked (musket walk, fire at will, bow lob)")
	_check_cover2()


## Cover and line of fire, second pass (docs/design/battle_sim.md "Cover and line of fire, second pass (as built,
## 2026-11-06)"): (1) light cover is real for a musket line: behind a 1.3 m yard wall shot from beyond it loses a
## quarter fewer men or more in 30 s than in the open (about half, measured), from the open side nothing; (2) the fire
## spot is scored: a tall wall before the target, a low wall on the far side of the two ways round: the spot is the
## covered one (without the low wall, the other), and the line walks there and fires; (3) the siege AI's short step:
## a defending musket line with no line of fire at a seen attacker in reach steps under 14 m to a spot with one.
func _check_cover2() -> void:
	const AP := preload("res://sim/ai_profile.gd")
	const SiegeAI := preload("res://sim/siege_ai.gd")
	var Probe = load("res://tests/lof_probe.gd")
	# (1) Light cover.
	var lost := {}
	var line_stops := {}
	for cs in ["open", "front", "behind"]:
		var tot := 0
		var stops := 0
		for sd in [1, 2]:
			var rk := []
			if cs != "open":
				for x in range(180, 221, 2):
					rk.append([x, 163, 1, 13])
			var sy := 233 if cs != "behind" else 90
			var sc := {"width_m": 400, "height_m": 400, "ai_sides": [], "orders": [], "los": 1, "time_limit": 600,
				"terrain": {"kind": Terrain.K_FLAT, "rocks": rk},
				"units": [Scenarios.unit(0, UT.index_of("musketeers"), 60, 200, sy, Scenarios.FACE_UP if cs != "behind" else Scenarios.FACE_DOWN, 15),
					Scenarios.unit(1, UT.index_of("musketeers"), 40, 200, 160, Scenarios.FACE_DOWN, 10)]}
			var sim := BattleSim.new()
			sim.setup(sc, sd)
			sim.queue_order(BattleSim.make_fire_order(0, 1, 0))
			for k in 300:
				sim.step()
			tot += sim.u_count0[1] - sim.u_alive[1]
			stops += sim.stat_line_stop
		lost[cs] = tot
		line_stops[cs] = stops
	if lost["front"] * 4 > lost["open"] * 3 or line_stops["front"] == 0:
		_fail("cover2: a musket line behind a yard wall lost %d in 30 s against %d in the open (%d balls stopped)" % [lost["front"], lost["open"], line_stops["front"]])
	if line_stops["behind"] != 0:
		_fail("cover2: the yard wall behind the line stopped %d balls from the open side" % line_stops["behind"])
	# (2) The scored fire spot.
	var spots := {}
	for low in [0, -1]:
		var rk2 := []
		for x in range(190, 211, 2):
			for yy in [130, 132, 134, 136]:
				rk2.append([x, yy, 1, 50])
		if low != 0:
			for x in range(200 + low * 31 - 8, 200 + low * 31 + 9, 2):
				rk2.append([x, 152, 1, 13])
		var sc2 := {"width_m": 400, "height_m": 400, "ai_sides": [], "orders": [], "los": 1, "time_limit": 600,
			"terrain": {"kind": Terrain.K_FLAT, "rocks": rk2},
			"units": [Scenarios.unit(0, UT.index_of("musketeers"), 40, 200, 165, Scenarios.FACE_UP, 10),
				Scenarios.unit(1, UT.index_of("w_pikemen"), 40, 200, 100, Scenarios.FACE_DOWN, 10),
				Scenarios.unit(0, UT.index_of("musketeers"), 10, 300, 60, Scenarios.FACE_DOWN, 5)]}
		var s2 := BattleSim.new()
		s2.setup(sc2, 3)
		s2.queue_order(BattleSim.make_attack_order(0, 0, 1, 0))
		s2.step()
		var sp: Vector3i = s2.fire_spot(0, 1)
		var face := FM.atan2_a(s2.u_cy[1] - sp.y, s2.u_cx[1] - sp.x)
		spots[low] = [sp, s2.cover_rating_front(sp.x, sp.y, face, 4 * 1024, s2.cover_who(0))]
		var x0: int = s2.u_cx[0]
		for k in 400:
			s2.step()
		if s2.stat_shots == 0 or absi(s2.u_cx[0] - x0) < 15 * 1024:
			_fail("cover2: the line did not walk round the wall to its spot and fire (low %d: %d shots, %d m aside)" % [low, s2.stat_shots, absi(s2.u_cx[0] - x0) / 1024])
	var sp0: Vector3i = spots[0][0]
	var sp1: Vector3i = spots[-1][0]
	if sp0.z == 0 or sp1.z == 0 or (sp0.x > 200 * 1024) == (sp1.x > 200 * 1024) or int(spots[-1][1]) < 1:
		_fail("cover2: the fire spot did not take the side with cover (open %s, with the low wall %s cover %d)" % [str(sp0), str(sp1), int(spots[-1][1])])
	# (3) The siege AI's step for a line.
	var sc3: Dictionary = Probe.town("musket", 40, "atk")
	var us: Array = sc3["units"]
	us[1]["type"] = UT.index_of("musketeers")
	us.append(Scenarios.unit(1, UT.index_of("musketeers"), 10, (int(us[0]["x_m"]) + int(us[1]["x_m"])) / 2 + 30,
		(int(us[0]["y_m"]) + int(us[1]["y_m"])) / 2, 0, 5))
	# (Third pass: the defender's front men see past the house from its post, LOF_MEN_ALL; the step is checked with only
	# its middle read, as the second pass built it.)
	var scr3: Script = BattleSim
	scr3.set("LOF_MEN_ALL", 0)
	var s3 := BattleSim.new()
	s3.setup(sc3, 7)
	s3.step()
	var hx: int = s3.u_ax[1]
	var hy: int = s3.u_ay[1]
	var kn := AP.row(AP.AVERAGE, 1)
	while (s3.tick + 7) % SiegeAI.S_LOF_STEP_EVERY >= kn[AP.UNIT_THINK]:
		s3.step()
	var lof0: bool = s3.lof_units(1, 0)
	SiegeAI._lof_step(s3, 1, kn, hx, hy)
	for k in 150:
		s3.step()
	var moved := int(Vector2(s3.u_ax[1] - hx, s3.u_ay[1] - hy).length()) / 1024
	var lof1: bool = s3.lof_units(1, 0)
	scr3.set("LOF_MEN_ALL", 1)
	if lof0 or not lof1 or moved > 22 or moved < 2:  # (third pass: a 20 m leash, S_LOF_LEASH)
		_fail("cover2: the defender's step for a line (line before %s, after %s, moved %d m)" % [str(lof0), str(lof1), moved])
	print("cover2: checked (light cover %d / %d lost, spot %s / %s, step %d m)" % [lost["front"], lost["open"], str(sp0), str(sp1), moved])
	_check_cover3()


## Cover and line of fire, third pass (2026-11-06; docs/design/battle_sim.md "Cover and line of fire, third pass"):
## (1) under fire the walk to a fire spot stops at LOF_SPOT_FIRE_GOOD of five front points (a musket line attacking a
## musket company behind a house fires sooner and walks less than stopping at four); (2) a formed line whose middle is
## behind a wall but whose flank files see takes the target and fires (it did not with only its middle read); (3) the
## cover chip's sim side: the units that shot at a unit (cover_shooters), and a house is no cover from its own garrison.
func _check_cover3() -> void:
	var Probe = load("res://tests/lof_probe.gd")
	var scr: Script = BattleSim
	var was_good: int = BattleSim.LOF_SPOT_FIRE_GOOD
	var res := {}
	for good in [was_good, 4]:
		scr.set("LOF_SPOT_FIRE_GOOD", good)
		var ft := 0
		var wk := 0
		for dist in [40, 60, 100]:
			var sc: Dictionary = Probe.town("musket", dist, "atk")
			sc["units"][1]["type"] = UT.index_of("musketeers")
			var sim := BattleSim.new()
			sim.setup(sc, 7)
			sim.queue_order(BattleSim.make_attack_order(0, 0, 1, 0))
			var x0: int = sim.u_cx[0]
			var y0: int = sim.u_cy[0]
			var first := 900
			for k in 900:
				sim.step()
				if sim.stat_shots > 0:
					for p in sim.pr_t0.size():
						if sim.pr_t0[p] == sim.tick - 1 and sim.pr_unit[p] == 0 and sim.pr_t1[p] >= sim.tick:
							first = k
							break
				if first < 900:
					break
			ft += first
			wk += int(Vector2(sim.u_cx[0] - x0, sim.u_cy[0] - y0).length()) / 1024
		res[good] = [ft, wk]
	scr.set("LOF_SPOT_FIRE_GOOD", was_good)
	if int(res[was_good][0]) >= int(res[4][0]) or int(res[was_good][1]) >= int(res[4][1]):
		_fail("cover3: under fire the walk did not stop sooner at %d of 5 (first shots %s ticks, walked %s m) than at 4 (%s, %s)" % [
			was_good, res[was_good][0], res[was_good][1], res[4][0], res[4][1]])
	# (2) A partly seeing line: lof_probe's pikes half behind the house (moved out to x 226 / 230 m), a spotter of its
	# side seeing them: the line's middle has no line past the house corner, its left files have.
	var lines := {}
	for men_all in [0, 1]:
		scr.set("LOF_MEN_ALL", men_all)
		var shots := 0
		var lofs := 0
		for c in [[226, 60], [230, 40]]:
			var sc2: Dictionary = Probe.scenario("musket", "half", int(c[1]), "faw")
			sc2["units"][1]["x_m"] = int(c[0])
			sc2["units"].append(Scenarios.unit(0, UT.index_of("w_pikemen"), 20, 300, 230, 512, 10))
			var s2 := BattleSim.new()
			s2.setup(sc2, 3)
			s2.queue_order(BattleSim.make_fire_order(0, 0, 1))
			s2.step()
			if s2.lof_units(0, 1):
				lofs += 1
			for k in 200:
				s2.step()
			shots += s2.stat_shots
		lines[men_all] = [lofs, shots]
	scr.set("LOF_MEN_ALL", 1)
	if int(lines[0][0]) != 0 or int(lines[1][0]) != 2 or int(lines[1][1]) == 0 or int(lines[0][1]) != 0:
		_fail("cover3: the partly seeing line (middle only: lines %d of 2, %d shots; its front men too: %d of 2, %d shots)" % [
			lines[0][0], lines[0][1], lines[1][0], lines[1][1]])
	# (3) The chip's threats: who shot at the unit, and no cover from a garrison's own house.
	var sc3 := {"width_m": 400, "height_m": 400, "ai_sides": [], "orders": [], "los": 1, "time_limit": 600,
		"terrain": {"kind": Terrain.K_FLAT},
		"units": [Scenarios.unit(0, UT.index_of("musketeers"), 40, 200, 230, Scenarios.FACE_UP, 10),
			Scenarios.unit(1, UT.index_of("musketeers"), 40, 200, 160, Scenarios.FACE_DOWN, 10)]}
	var s3 := BattleSim.new()
	s3.setup(sc3, 2)
	s3.queue_order(BattleSim.make_fire_order(0, 1, 1))
	s3.queue_order(BattleSim.make_fire_order(0, 0, 0))
	var none0: bool = s3.cover_shooters(0, 30).is_empty()
	for k in 200:
		s3.step()
	var sh: PackedInt32Array = s3.cover_shooters(0, 30)
	if not none0 or sh.size() != 1 or sh[0] != 1:
		_fail("cover3: cover_shooters (before %s, after %s)" % [str(none0), str(sh)])
	var st: BattleSim = BattleSim.new()
	st.setup(Probe.town("musket", 40, "atk"), 7)
	var skipped := 0
	var houses := 0
	for b in st.ob_dx.size():
		var face := FM.atan2_a(st.ob_iy[b] - st.ob_dy[b], st.ob_ix[b] - st.ob_dx[b])
		if st.cover_rating(st.ob_dx[b], st.ob_dy[b], face, BattleSim.COVW_LINE) != 2:
			continue
		houses += 1
		if st.cover_rating(st.ob_dx[b], st.ob_dy[b], face, BattleSim.COVW_LINE, b) == 0:
			skipped += 1
	if houses == 0 or skipped * 2 < houses:
		_fail("cover3: a house gave cover from its own garrison (%d of %d door steps still covered)" % [houses - skipped, houses])
	# (4) Rubble with some height: a breach's heap 3 m before a musket line shot at from beyond (cells turned to
	# rubble where the yard wall's rocks were laid), against flat rubble (RUBBLE_H 0) and from the open side.
	var was_h: int = BattleSim.RUBBLE_H
	var rlost := {}
	var rrate := {}
	for cs in ["flat", "heap", "behind"]:
		scr.set("RUBBLE_H", 0 if cs == "flat" else was_h)
		var tot := 0
		for sd in [1, 2]:
			var rk2 := []
			for x in range(180, 221, 2):
				rk2.append([x, 163, 1, 13])
			var sy := 233 if cs != "behind" else 90
			var sc4 := {"width_m": 400, "height_m": 400, "ai_sides": [], "orders": [], "los": 1, "time_limit": 600,
				"terrain": {"kind": Terrain.K_FLAT, "rocks": rk2},
				"units": [Scenarios.unit(0, UT.index_of("musketeers"), 60, 200, sy, Scenarios.FACE_UP if cs != "behind" else Scenarios.FACE_DOWN, 15),
					Scenarios.unit(1, UT.index_of("musketeers"), 40, 200, 160, Scenarios.FACE_DOWN, 10)]}
			var s4 := BattleSim.new()
			s4.setup(sc4, sd)
			for c in s4.obs.size():
				if MapGen.is_land(s4.obs[c]):
					s4.obs[c] = MapGen.C_RUBBLE
					s4.rub_n += 1
			if sd == 1:
				rrate[cs] = s4.cover_rating_front(s4.u_ax[1], s4.u_ay[1], FM.atan2_a(s4.u_cy[0] - s4.u_ay[1], s4.u_cx[0] - s4.u_ax[1]), 4 * 1024, BattleSim.COVW_LINE)
			s4.queue_order(BattleSim.make_fire_order(0, 1, 0))
			for k in 300:
				s4.step()
			tot += s4.u_count0[1] - s4.u_alive[1]
		rlost[cs] = tot
	scr.set("RUBBLE_H", was_h)
	if rlost["heap"] * 4 > rlost["flat"] * 3 or int(rrate["heap"]) != 1 or int(rrate["flat"]) != 0 or int(rrate["behind"]) != 0:
		_fail("cover3: rubble as cover (lost behind the heap %d, flat rubble %d, shot from the open side %d; ratings %s)" % [
			rlost["heap"], rlost["flat"], rlost["behind"], str(rrate)])
	print("cover3: checked (stop under fire %s against %s, partly seeing line %s, shooters %s, garrison houses %d / %d, rubble lost %s ratings %s)" % [
		str(res[was_good]), str(res[4]), str(lines), str(sh), skipped, houses, str(rlost), str(rrate)])


## The three play scenarios in the Tests and benchmarks menu (docs/AI.md 44.1, 44.5, 44.6; 2026-11-05): each has a
## title, is listed in Scenarios.IDS, and loads and runs 60 s (600 ticks) of both AI sides with units moving and
## both sides still on the field, without a script error.
func _check_play_scenarios() -> void:
	for id in ["play_field", "salvo_field", "ambush_field"]:
		if not Scenarios.IDS.has(id) or Scenarios.title(id) == id:
			_fail("%s: not listed in the menu with a title" % id)
			continue
		var sim := BattleSim.new()
		sim.setup(Scenarios.make(id), 7)
		var x0: Array = []
		for u in sim.n_units:
			x0.append(sim.u_cy[u])
		for _t in 600:
			sim.step()
		var moved := 0
		var alive := [0, 0]
		for u in sim.n_units:
			if sim.u_cy[u] != x0[u]:
				moved += 1
			if sim.u_alive[u] > 0:
				alive[sim.u_side[u]] += 1
		if moved < sim.n_units / 2 or alive[0] == 0 or alive[1] == 0:
			_fail("%s: after 60 s %d of %d units moved, alive %s" % [id, moved, sim.n_units, str(alive)])


## Per-side unit names (west.gd UNIT_NAMES): a Miskito side's list and the battle HUD's cards name its units
## Miskito; the other side keeps the row names; Rome has no Names button.
func _check_names() -> void:
	const CustomBattle := preload("res://game/custom/custom_battle.gd")
	const PackView := preload("res://game/campaign/pack_view.gd")
	const BattleScr := preload("res://game/battle.gd")
	var st := CS.default_setup(3)
	CS.set_pack(st, "west")
	st["sides"][0]["armies"][0]["units"] = [["musketeers", 100], ["native_warriors", 80], ["chieftain", 40]]
	st["sides"][1]["armies"][0]["units"] = [["musketeers", 100], ["native_warriors", 80]]
	if CS.names_of(st, 0) != "" or CS.unit_label(st, 0, "musketeers") != "Musketeers":
		_fail("names: a side with no choice keeps the row names")
	st["sides"][0]["names"] = "miskito"
	if CS.unit_label(st, 0, "musketeers") != "Miskito Musketmen" or CS.unit_label(st, 0, "chieftain") != "King's Guard" \
			or CS.unit_label(st, 1, "musketeers") != "Musketeers":
		_fail("names: a Miskito side's labels (%s / %s)" % [CS.unit_label(st, 0, "musketeers"), CS.unit_label(st, 1, "musketeers")])
	var rs := CS.default_setup(3)
	rs["sides"][0]["names"] = "miskito"
	if CS.names_of(rs, 0) != "":
		_fail("names: Rome has no per-side names")
	# The setup screen: the side's army list.
	var cb: Control = CustomBattle.new()
	cb.setup = st.duplicate(true)
	root.add_child(cb)
	await process_frame
	await process_frame
	cb._rebuild()
	await process_frame
	var texts: Array[String] = []
	for l in cb.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	var joined := "\n".join(texts)
	if not joined.contains("Miskito Musketmen") or not joined.contains("King's Guard"):
		_fail("names: the Miskito side's list shows Miskito Musketmen and King's Guard")
	var nb := cb.find_child("custom_names_0", true, false)
	if nb == null or not (nb as Button).text.contains("Miskito"):
		_fail("names: the Names button of side 1 reads Miskito")
	cb.queue_free()
	# The battle: the HUD cards.
	var built := CS.build(st, true)
	PackView.use_pack("west")
	var bt = BattleScr.new()
	bt.custom_scenario = built["scenario"]
	bt.seed_value = 5
	bt.side_name_fkeys = [CS.names_of(st, 0), CS.names_of(st, 1)]
	root.add_child(bt)
	for k in 8:
		await process_frame
	var mis := 0
	var plain := 0
	for u in bt.hud._cards:
		var nm: String = bt.hud._faces[u].name_text
		if bt.sim.u_side[u] == 0 and bt.sim.u_otype[u] == UT.index_of("musketeers") and nm.contains("Musketmen"):
			mis += 1
		if bt.sim.u_side[u] == 0 and bt.sim.u_otype[u] == UT.index_of("chieftain") and nm.contains("King's Guard"):
			plain += 1
	var sides_ok: bool = bt.hud.unit_faction.size() == bt.sim.n_units
	bt.free()
	PackView.use_pack("rome")
	if mis != 1 or plain != 1 or not sides_ok:
		_fail("names: the HUD cards name the Miskito side's musketeers Musketmen (%d) and the King's Guard (%d)" % [mis, plain])
	else:
		print("PASS names: a Miskito side shows its names in the setup list and the HUD cards")


## (N3a) The West setting's sea battle: the default builds a sea scenario
## (Player 1's side 0, the AI's side 1) the same twice, a coast and an
## island reach its land, the upwind start its layout; an empty side is
## refused; the battle runs to a decision.
func _check_sea() -> void:
	var st := CS.default_setup(5)
	CS.set_pack(st, "west")
	st["sea"] = CS.sea_default()
	var a := CS.build_sea(st)
	var b := CS.build_sea(JSON.parse_string(JSON.stringify(st)))
	if a.has("error") or str(a) != str(b) or int(a["scenario"].get("sea", 0)) != 1 or a["scenario"]["ai_sides"] != [0, 1]:
		_fail("sea: the default sea battle does not build the same twice: %s" % str(a.get("error", "")))
		return
	st["sea"]["water"] = 2
	st["sea"]["start"] = "gauge0"
	var c := CS.build_sea(st)
	if int(c["scenario"]["land"]["kind"]) != 2 or str(c["scenario"]["layout"]) != "gauge0":
		_fail("sea: the coast and the upwind start do not reach the scenario")
	st["sea"]["ships"][1] = []
	if CS.sea_check(st) == "":
		_fail("sea: a side without ships was accepted")
	var sim := SeaSim.new()
	var scn: Dictionary = a["scenario"]
	scn["ai_sides"] = [1, 1]
	sim.setup(scn, int(a["seed"]))
	while sim.ended == 0 and sim.tick < 9300:
		sim.step()
	if sim.ended == 0:
		_fail("sea: the custom sea battle was not decided")
	else:
		print("PASS sea: the custom sea battle builds the same twice and is decided in %d s (side %d)" % [sim.tick / 10, sim.winner])
	# (R2) Rome's setting: the five galley and merchant rows on offer, its own default (3 triremes and a quinquereme a side).
	var rs := CS.default_setup(5)
	rs["sea"] = CS.sea_default("rome")
	var ra := CS.build_sea(rs)
	var rl := CS.sea_ships("rome")
	if ra.has("error") or rl != ["lembos", "trireme", "quinquereme", "quinquereme_p", "corbita"] or CS.sea_ships("west") != CS.SEA_SHIPS \
			or (ra["scenario"]["units"] as Array).size() != 8 or int(ra["scenario"]["wind_deg"]) != 315:
		_fail("sea: Rome's custom sea setup (ships on offer, default fleets, north-westerly)")
		return
	CS.set_pack(rs, "west")
	if (rs["sea"]["ships"][0] as Array)[0] != "frigate":
		_fail("sea: switching the setting did not reset the fleets")
		return
	for k in rl:
		var rsim := SeaSim.new()
		var sc := CS.build_sea({"sea": {"on": 1, "ships": [[k, "trireme"], ["trireme", k]], "wind": 315, "str": 55, "water": 0, "start": "ns"},
			"sides": [{}, {}], "seed": 3})
		if sc.has("error"):
			_fail("sea: %s" % str(sc["error"]))
			return
		(sc["scenario"] as Dictionary)["ai_sides"] = [1, 1]
		rsim.setup(sc["scenario"], 3)
		while rsim.ended == 0 and rsim.tick < 9300:
			rsim.step()
		if rsim.ended == 0:
			_fail("sea: a battle with a %s was not decided" % k)
			return
	print("PASS sea: Rome's custom sea setup lists the five rows and fights with each of them")


## Player 1: archers with fire arrows, javelinmen with none, a supply
## train; Player 2: bolts with heavy bolts, a hand cart; an AI army with a
## wagon and no kinds.
func _ammo_setup() -> Dictionary:
	var st := CS.default_setup(9)
	var a0: Array = [["heavy", 100], ["archer", 80, "fire_arrows"], ["javelin", 60], ["wagon3", 10]]
	st["sides"][0]["armies"][0]["units"] = a0
	st["sides"][1]["armies"][0]["ctrl"] = "p2"
	st["sides"][1]["armies"][0]["units"] = [["spear", 100], ["bolt", 16, "heavy_bolts"], ["wagon", 8],
		["archer", 80, "heavy_bolts"]]  # (not a kind for bows: ignored)
	st["sides"][1]["armies"].append({"ctrl": "ai", "units": [["heavy", 100], ["wagon2", 8]]})
	return st


func _check_ammo(st: Dictionary, what: String) -> void:
	var fire := UT.ammo_index("fire_arrows")
	var heavy := UT.ammo_index("heavy_bolts")
	# Helpers.
	var e: Array = ["archer", 80]
	CS.set_unit_ak(e, fire)
	if CS.unit_ak(e) != fire or CS.unit_ak(["javelin", 60, "fire_arrows"]) >= 0:
		_fail("ammo %s: unit_ak / set_unit_ak" % what)
	CS.set_unit_ak(e, -1)
	if e.size() != 2:
		_fail("ammo %s: clearing the kind left %s" % [what, str(e)])
	# Online: the setup as the relay passes it on builds the same scenario,
	# with the same hash, and a different kind gives a different hash.
	var a := CS.build(st)
	var rt: Dictionary = JSON.parse_string(JSON.stringify(st))
	var b := CS.build(rt)
	var ha := CoopSession.scenario_hash(a["scenario"], int(a["seed"]), a["home"])
	var hb := CoopSession.scenario_hash(b["scenario"], int(b["seed"]), b["home"])
	if ha != hb or str(rt["sides"][0]["armies"][0]["units"][1][2]) != "fire_arrows":
		_fail("ammo %s: the online setup does not round-trip (%s / %s)" % [what, ha, hb])
	var other: Dictionary = st.duplicate(true)
	other["sides"][0]["armies"][0]["units"][1].resize(2)
	var c := CS.build(other)
	if CoopSession.scenario_hash(c["scenario"], int(c["seed"]), c["home"]) == ha:
		_fail("ammo %s: the kind does not change the scenario hash" % what)
	# The scenario's keys.
	var sc: Dictionary = a["scenario"]
	var arch := -1
	var bolt := -1
	var aks := {}   # type key -> "aks"
	for i in (sc["units"] as Array).size():
		var ud: Dictionary = sc["units"][i]
		var key := UT.key_of(int(ud["type"]))
		if key == "archer" and int(ud["side"]) == 0:
			arch = i
			if int(ud.get("ak", -1)) != fire:
				_fail("ammo %s: the archers' ak is %s" % [what, str(ud.get("ak"))])
		elif key == "archer" and ud.has("ak"):
			_fail("ammo %s: bows carry heavy bolts" % what)
		elif key == "bolt":
			bolt = i
			if int(ud.get("ak", -1)) != heavy:
				_fail("ammo %s: the bolts' ak is %s" % [what, str(ud.get("ak"))])
		elif key.begins_with("wagon"):
			aks[key] = ud.get("aks", [])
	if str(aks.get("wagon3")) != str([fire]) or str(aks.get("wagon")) != str([heavy]) or str(aks.get("wagon2")) != "[]":
		_fail("ammo %s: wagon stocks %s" % [what, str(aks)])
	# Field: the wagon stands in a rear line behind the rest of its army
	# (Scenarios.army_layout), not in the infantry line.
	if what == "field":
		var hh := int(sc["height_m"]) / 2
		var wy := -1
		var deepest := -1
		for ud in sc["units"]:
			if int(ud["side"]) != 0:
				continue
			var depth := absi(int(ud["y_m"]) - hh)
			if UT.stat(int(ud["type"]), "wagon") >= 0:
				wy = depth
			else:
				deepest = maxi(deepest, depth)
		if wy <= deepest:
			_fail("ammo %s: the wagon stands %d m from the middle, not behind its army (%d m)" % [what, wy, deepest])
	# The sim: the archers' kind, the battery's engines' kind, the wagons' stock.
	var sim = BattleSim.new()
	sim.setup(sc, int(a["seed"]))
	if sim.u_sk[arch] != fire:
		_fail("ammo %s: sim archers carry kind %d" % [what, sim.u_sk[arch]])
	if sim.u_eg[bolt] < 0 or sim.eg_sk[sim.u_eg[bolt]] != heavy:
		_fail("ammo %s: sim battery's engines carry no heavy bolts" % what)
	var found := 0
	for q in sim.n_eq:
		if sim.q_kind[q] != BattleSim.EQ_WAGON:
			continue
		var key := UT.key_of(sim.u_type[sim.q_unit[q]])
		var pct := UT.wagon_stat(UT.stat(sim.u_type[sim.q_unit[q]], "wagon"), "stock_pct")
		var want_fire := 1600 * pct / 100 * 33 / 100 if key == "wagon3" else 0
		var want_heavy := 22 * pct / 100 * 33 / 100 if key == "wagon" else 0
		if sim.wagon_stock(q, fire) != want_fire or sim.wagon_stock(q, heavy) != want_heavy \
				or sim.wagon_stock(q, UT.ammo_index("arrows")) != 1600 * pct / 100:
			_fail("ammo %s: %s stocks fire %d heavy %d" % [what, key, sim.wagon_stock(q, fire), sim.wagon_stock(q, heavy)])
		found += 1
		print("  %s: %s stocks arrows %d, fire arrows %d, heavy bolts %d" % [what, key,
			sim.wagon_stock(q, UT.ammo_index("arrows")), sim.wagon_stock(q, fire), sim.wagon_stock(q, heavy)])
	if found != 3:
		_fail("ammo %s: %d wagons in the sim" % [what, found])
	print("PASS ammo %s: archers kind %d, battery kind %d, hash %s" % [what, sim.u_sk[arch], sim.eg_sk[sim.u_eg[bolt]], ha])


## Missile cavalry and slingers (docs/DESIGN.md "Missile cavalry and
## slingers"): one unit of each row on side 0 (the Balearics with lead
## bullets), each told to attack a foot unit of the AI's, on an open field: each builds
## with its weapon's standard kind (javelins, sling stones), skirmish on and
## the riders mounted, and each has thrown or slung within 4 minutes.
func _check_light_missile() -> void:
	var rows := ["cav_jav", "numidians", "tarentines", "gallic_horse", "iberian_horse", "slinger", "balearic",
		"rhodians", "iberian_slingers"]
	var st := CS.default_setup(12)
	st["deploy"] = 0
	st["map"]["terrain"] = Terrain.K_FLAT
	st["map"]["woods"] = 0
	var a0: Array = []
	for k in rows:
		var e: Array = [k, UT.size_of(UT.index_of(k))]
		if k == "balearic":
			e.append("lead_bullets")
		a0.append(e)
	st["sides"][0]["armies"][0]["units"] = a0
	st["sides"][1]["armies"][0]["units"] = [["heavy", 100], ["light", 100], ["light", 100], ["spear", 100]]
	var b := CS.build(st)
	if b.has("error"):
		_fail("light missile: %s" % b["error"])
		return
	var sc: Dictionary = b["scenario"]
	# Each of ours is told to attack an enemy unit (the battle AI's use of
	# them is the AI's business, docs/AI.md); the AI fights side 1.
	var foes: Array = []
	for i in (sc["units"] as Array).size():
		if int(sc["units"][i]["side"]) == 1:
			foes.append(i)
	var orders: Array = []
	for i in (sc["units"] as Array).size():
		if int(sc["units"][i]["side"]) == 0:
			orders.append(Scenarios.attack(1, i, int(foes[orders.size() % foes.size()]), 1))
	sc["orders"] = orders
	sc["ai_sides"] = [1]
	var sim = BattleSim.new()
	sim.setup(sc, int(b["seed"]))
	var jav := UT.ammo_index("javelins")
	var sling := UT.ammo_index("sling")
	var lead := UT.ammo_index("lead_bullets")
	var units := {}   # row key -> sim unit
	var full := {}
	for u in sim.n_units:
		var key := UT.key_of(sim.u_type[u])
		if sim.u_side[u] == 0 and rows.has(key):
			units[key] = u
			full[key] = sim.u_ammo[u]
	if units.size() != rows.size():
		_fail("light missile: %d of %d rows in the sim" % [units.size(), rows.size()])
		return
	for k in rows:
		var u: int = units[k]
		var horse: bool = UT.line_of(sim.u_type[u]) == "cav_missile"
		var want := jav if horse else sling
		if sim.t_m_ak[sim.u_type[u]] != want or sim.u_skirm[u] != 1 or sim.u_cls[u] != UT.CLS_MISSILE \
				or (sim.t_mount[sim.u_type[u]] == UT.MOUNT_HORSE) != horse:
			_fail("light missile: %s builds with kind %d (want %d), skirmish %d, mount %d" % [k,
				sim.t_m_ak[sim.u_type[u]], want, sim.u_skirm[u], sim.t_mount[sim.u_type[u]]])
		if sim.u_sk[u] != (lead if k == "balearic" else -1):
			_fail("light missile: %s carries special kind %d" % [k, sim.u_sk[u]])
	var t := 0
	while t < 2400:
		sim.step()
		t += 1
		if t % 100 == 0:
			var all := true
			for k in rows:
				if sim.u_ammo[units[k]] >= int(full[k]):
					all = false
			if all:
				break
	var out: Array[String] = []
	for k in rows:
		var shots: int = int(full[k]) - sim.u_ammo[units[k]]
		if shots <= 0:
			# (Nine skirmishing rows in one crowd: one that fell back from the
			# AI's foot has no order left and shoots only at what comes within
			# its range past its friends, and in some battles nothing does (at
			# HEAD of 2026-10-30 two of eight neighbouring seeds; with pursuit
			# as a unit, docs/AI.md 46, the AI's foot chasing the other
			# skirmishers, this seed). Such a row is tried alone against the
			# AI's light foot: it must shoot there. Since 2026-10-30 (docs/AI.md
			# 47) a skirmisher that falls back keeps its attack order and takes
			# it up again; seeds +0..+7 still leave one row without a shot at
			# three of them, before and after: horse javelins (40 m) fall back
			# from foot within 30 m before they close to range.)
			var alone := _light_missile_alone(k, int(b["seed"]))
			out.append("%s 0 (alone %d)" % [k, alone])
			if alone <= 0:
				_fail("light missile: %s never shot in %d ticks, nor alone against light foot" % [k, t])
		else:
			out.append("%s %d" % [k, shots])
	print("PASS light missile: shots by tick %d: %s" % [t, ", ".join(out)])


## One light missile row alone (attack order, skirmish stance) against the
## AI's 100 light foot on a flat field: its shots in 1,500 ticks.
func _light_missile_alone(k: String, sd: int) -> int:
	var st := CS.default_setup(12)
	st["deploy"] = 0
	st["map"]["terrain"] = Terrain.K_FLAT
	st["map"]["woods"] = 0
	var e: Array = [k, UT.size_of(UT.index_of(k))]
	if k == "balearic":
		e.append("lead_bullets")
	st["sides"][0]["armies"][0]["units"] = [e]
	st["sides"][1]["armies"][0]["units"] = [["light", 100]]
	var b := CS.build(st)
	if b.has("error"):
		return 0
	var sc: Dictionary = b["scenario"]
	var mine := -1
	var foe := -1
	for i in (sc["units"] as Array).size():
		if int(sc["units"][i]["side"]) == 0 and mine < 0:
			mine = i
		elif int(sc["units"][i]["side"]) == 1 and foe < 0:
			foe = i
	sc["orders"] = [Scenarios.attack(1, mine, foe, 1)]
	sc["ai_sides"] = [1]
	var sim = BattleSim.new()
	sim.setup(sc, sd)
	var full: int = sim.u_ammo[mine]
	for i in 1500:
		sim.step()
		if sim.u_ammo[mine] < full:
			break
	return full - sim.u_ammo[mine]


## Light artillery (docs/DESIGN.md "Light artillery"): scorpions carrying
## heavy bolts and gastraphetes on side 0 of an open field, the AI's foot
## coming at them: both build (a battery of six engines with the heavy
## bolts, the belly-bows flat-shooting missile foot with arrows) and both
## shoot within 4 minutes (the battery at will, the belly-bows on an attack
## order).
func _check_light_art() -> void:
	var st := CS.default_setup(13)
	st["deploy"] = 0
	st["map"]["terrain"] = Terrain.K_FLAT
	st["map"]["woods"] = 0
	st["sides"][0]["armies"][0]["units"] = [["scorpions", 12, "heavy_bolts"], ["gastraphetes", 80], ["spear", 100]]
	st["sides"][1]["armies"][0]["units"] = [["heavy", 100], ["light", 100], ["spear", 100]]
	var b := CS.build(st)
	if b.has("error"):
		_fail("light art: %s" % b["error"])
		return
	var sc: Dictionary = b["scenario"]
	var foes: Array = []
	var sco := -1
	var gas := -1
	for i in (sc["units"] as Array).size():
		var key := UT.key_of(int(sc["units"][i]["type"]))
		if int(sc["units"][i]["side"]) == 1:
			foes.append(i)
		elif key == "scorpions":
			sco = i
		elif key == "gastraphetes":
			gas = i
	if sco < 0 or gas < 0:
		_fail("light art: rows missing from the scenario (%d, %d)" % [sco, gas])
		return
	sc["orders"] = [Scenarios.attack(1, gas, int(foes[0]), 0)]
	sc["ai_sides"] = [1]
	var sim = BattleSim.new()
	sim.setup(sc, int(b["seed"]))
	var su: int = -1
	var gu: int = -1
	for u in sim.n_units:
		if sim.u_side[u] == 0 and UT.key_of(sim.u_type[u]) == "scorpions":
			su = u
		elif sim.u_side[u] == 0 and UT.key_of(sim.u_type[u]) == "gastraphetes":
			gu = u
	if su < 0 or gu < 0 or sim.u_neng[su] != 6 or sim.u_cls[su] != UT.CLS_ART \
			or sim.eg_sk[sim.u_eg[su]] != UT.ammo_index("heavy_bolts") or sim.u_cls[gu] != UT.CLS_MISSILE \
			or sim.t_m_arc[sim.u_type[gu]] != 0 or sim.t_m_ak[sim.u_type[gu]] != UT.ammo_index("arrows") or sim.u_skirm[gu] != 0:
		_fail("light art: built wrong (battery %d with %d engines, belly-bows %d)" % [su, sim.u_neng[su] if su >= 0 else -1, gu])
		return
	var a0: int = sim.u_ammo[su]
	var g0: int = sim.u_ammo[gu]
	var t := 0
	while t < 2400:
		sim.step()
		t += 1
		if t % 100 == 0 and sim.u_ammo[su] < a0 and sim.u_ammo[gu] < g0:
			break
	if sim.u_ammo[su] >= a0 or sim.u_ammo[gu] >= g0:
		_fail("light art: by tick %d scorpions shot %d, gastraphetes %d" % [t, a0 - sim.u_ammo[su], g0 - sim.u_ammo[gu]])
		return
	print("PASS light art: 6 scorpions with heavy bolts and flat-shooting gastraphetes built; by tick %d the scorpions shot %d bolts, the gastraphetes %d" % [
		t, a0 - sim.u_ammo[su], g0 - sim.u_ammo[gu]])


## Deploy (place one unit of each human side, ready) and fight a little,
## through the lockstep layer with every player present.
## Mantlets (any map): each side's count reaches the scenario and the sim
## stands them, whole, before that side's missile troops and engines where
## the scenario puts them (an AI side's deployment moves its units after);
## a setup without them has no key.
func _check_mantlets(field: Dictionary, town: Dictionary) -> void:
	if CS.build(CS.default_setup(12))["scenario"].has("mantlets"):
		_fail("mantlets: a setup without them puts the key in the scenario")
		return
	for st in [field, town]:
		var b := CS.build(st)
		var sc: Dictionary = b["scenario"]
		if str(sc.get("mantlets", [])) != str([4, 2]):
			_fail("mantlets %s: scenario key %s" % [str(st["map"]["kind"]), str(sc.get("mantlets", []))])
			continue
		var sim := BattleSim.new()
		sim.setup(sc, int(b["seed"]))
		var per := [0, 0]
		var near := 0
		for q in sim.n_eq:
			if sim.q_kind[q] != BattleSim.EQ_MANTLET:
				continue
			if sim.q_state[q] != BattleSim.Q_GROUND or sim.q_hp[q] != BattleSim.mantlet_hp(sim.q_len[q]):  # (a line at its unit's frontage)
				continue
			per[sim.q_side[q]] += 1
			for ud in sc["units"]:
				var c := UT.cls(int(ud["type"]))
				if int(ud["side"]) == sim.q_side[q] and (c == UT.CLS_MISSILE or c == UT.CLS_ART) \
						and FM.approx_len(int(ud["x_m"]) * 1024 - sim.q_x[q], int(ud["y_m"]) * 1024 - sim.q_y[q]) <= 12 * 1024 + sim.q_len[q] / 2:
					near += 1
					break
		if per[0] != 4 or per[1] != 2 or near != 6:
			_fail("mantlets %s: standing %s, %d by a missile unit or engine" % [str(st["map"]["kind"]), str(per), near])
		else:
			print("PASS mantlets %s: 4 and 2 standing at the start (%d hit points a 6 m of line), each before a missile unit or engine of its side at its frontage" % [
				str(st["map"]["kind"]), BattleSim.MANTLET_HP])


func _run(name: String, b: Dictionary) -> void:
	var sc: Dictionary = b["scenario"]
	var players: Array = []
	for p in b["home"]:
		if int(p) >= 0 and not players.has(int(p)):
			players.append(int(p))
	var ls := Lockstep.new()
	ls.setup(sc, int(b["seed"]), b["home"], players, 0)
	var sim = ls.sim
	# The towers the sim added belong to the defending side's lead player
	# (the trailing home entry), the ram to the attackers' (a scenario unit).
	var n_scn: int = (sc["units"] as Array).size()
	var towers := 0
	for u in range(n_scn, sim.n_units):
		if sim.is_tower(u):
			towers += 1
			if ls.u_home[u] != int(b["home"][n_scn]):
				_fail("%s: tower %d has home %d, not %d" % [name, u, ls.u_home[u], int(b["home"][n_scn])])
				break
	if (b["home"] as Array).size() > n_scn:
		var def_side: int = sim.city_def
		var lead := -1
		for u in n_scn:
			if int(sc["units"][u]["side"]) == def_side and ls.u_home[u] >= 0:
				lead = ls.u_home[u]
				break
		if towers > 0 and lead != int(b["home"][n_scn]):
			_fail("%s: towers go to %d, the defenders' lead player is %d" % [name, int(b["home"][n_scn]), lead])
	var n := {}
	var deploy: bool = sim.phase == BattleSim.PHASE_DEPLOY
	var t0 := Time.get_ticks_msec()
	for f in 300:
		for p in players:
			var os: Array = []
			if f == 2:
				for u in sim.n_units:
					if ls.u_cmd[u] == p:
						os.append({"f": f, "type": BattleSim.ORDER_PLACE, "unit": u, "x": sim.u_ax[u] + 5 * 1024,
							"y": sim.u_ay[u], "facing": sim.u_face[u], "files": 10})
						break
			if f == 5:
				os.append({"f": f, "type": BattleSim.ORDER_READY})
			n[p] = int(n.get(p, 0)) + 1
			ls.receive({"p": p, "n": n[p], "k": f, "o": os})
		ls.advance()
	if deploy and sim.phase != BattleSim.PHASE_BATTLE:
		_fail("%s: the deployment did not end when everyone was ready" % name)
	if sim.tick < 200:
		_fail("%s: the battle hardly ran (tick %d)" % [name, sim.tick])
	print("PASS %s: %d units, %d soldiers, players %s, AI sides %s, deploy %s, %d ticks in %d ms" % [name, sim.n_units,
		sim.n, str(players), str(sc["ai_sides"]), str(deploy), sim.tick, Time.get_ticks_msec() - t0])


## Field works options (DESIGN.md "Field works and the fortified camp"):
## "works" 2 gives each side 4 stakes lines and 2 caltrop fields (as a
## Workshop 2), "fortified" 1 a camp round side 1 and its own 2 lines and a
## field on top; the sim builds them (stowed, the camp standing); none on a
## settlement map or without the options.
func _check_works() -> void:
	var st := CS.default_setup(9)
	st["map"]["works"] = 2
	st["map"]["fortified"] = 1
	var b := CS.build(st)
	var sc: Dictionary = b["scenario"]
	var sim := BattleSim.new()
	sim.setup(sc, int(b["seed"]))
	var cnt := {}
	for q in sim.n_eq:
		var key := "%d/%d/%d" % [sim.q_side[q], sim.q_kind[q], sim.q_state[q]]
		cnt[key] = int(cnt.get(key, 0)) + 1
	var plain := CS.build(CS.default_setup(9))
	var town := CS.default_setup(9)
	town["map"]["kind"] = "settlement"
	town["map"]["works"] = 2
	town["map"]["fortified"] = 1
	var tb := CS.build(town)
	var s0 := "0/%d/%d" % [BattleSim.EQ_STAKES, BattleSim.Q_STOWED]
	var c0 := "0/%d/%d" % [BattleSim.EQ_CALTROPS, BattleSim.Q_STOWED]
	var s1 := "1/%d/%d" % [BattleSim.EQ_STAKES, BattleSim.Q_FIXED]  # (the AI side places its own at the start)
	var c1 := "1/%d/%d" % [BattleSim.EQ_CALTROPS, BattleSim.Q_FIXED]
	var r1 := "1/%d/%d" % [BattleSim.EQ_RAMPART, BattleSim.Q_FIXED]
	var d1 := "1/%d/%d" % [BattleSim.EQ_DITCH, BattleSim.Q_FIXED]
	if str(sc.get("stakes", [])) != str([4, 6]) or str(sc.get("caltrops", [])) != str([2, 3]) \
			or int(sc.get("fortified", -1)) != 1 or int(cnt.get(s0, 0)) != 4 or int(cnt.get(c0, 0)) != 2 \
			or int(cnt.get(s1, 0)) != 6 or int(cnt.get(c1, 0)) != 3 or int(cnt.get(r1, 0)) < 4 or int(cnt.get(d1, 0)) < 4 \
			or (plain["scenario"] as Dictionary).has("stakes") or (plain["scenario"] as Dictionary).has("fortified") \
			or (tb["scenario"] as Dictionary).has("fortified") or (tb["scenario"] as Dictionary).has("stakes"):
		_fail("field works: scenario stakes %s caltrops %s fortified %s, pieces %s" % [str(sc.get("stakes")),
			str(sc.get("caltrops")), str(sc.get("fortified")), str(cnt)])
		return
	print("PASS field works: options give side 1 (fortified) 6 stakes lines and 3 caltrop fields, side 0 (the player) 4 and 2 to place, the AI's placed; the camp's %d palisade sections and %d ditch runs stand; none without the options or on a settlement map" % [
		int(cnt.get(r1, 0)), int(cnt.get(d1, 0))])



## River crossings (DESIGN.md "River crossings"): the option's scenario key,
## zones short of the water, the crossing map and the camp at it.
func _check_river(ford: Dictionary, bridge: Dictionary) -> void:
	var fb := CS.build(ford)
	var bb := CS.build(bridge)
	var fsc: Dictionary = fb["scenario"]
	var bsc: Dictionary = bb["scenario"]
	var plain := CS.build(CS.default_setup(13))
	var town: Dictionary = JSON.parse_string(JSON.stringify(ford))
	town["map"]["kind"] = "settlement"
	var tb := CS.build(town)
	var fr: Dictionary = fsc.get("river", {})
	var br: Dictionary = bsc.get("river", {})
	if fr.is_empty() or br.is_empty() or int(fr["kind"]) != 0 or int(br["kind"]) != 1 or int(fr["bank"]) != 1 \
			or int(br["bank"]) != 1 or (plain["scenario"] as Dictionary).has("river") \
			or (tb["scenario"] as Dictionary).has("river"):
		_fail("river: ford key %s, bridge key %s, plain %s, settlement %s" % [str(fr), str(br),
			str((plain["scenario"] as Dictionary).has("river")), str((tb["scenario"] as Dictionary).has("river"))])
		return
	var sim := BattleSim.new()
	sim.setup(fsc, int(fb["seed"]))
	var g: Dictionary = sim.riv
	var zone_wet := 0
	for z in fsc["deploy_zones"]:
		var s := int(z[0])
		for x in range(int(z[2]), int(z[4]) + 1, 8):
			var e := MapGen.river_edge(g, x, s)
			# side 0's zone below the water, side 1's above it
			if (s == 0 and int(z[3]) * 100 < e) or (s == 1 and int(z[5]) * 100 > e):
				zone_wet += 1
	var ramp := 0
	for q in sim.n_eq:
		if sim.q_kind[q] == BattleSim.EQ_RAMPART:
			ramp += 1
	var bsim := BattleSim.new()
	bsim.setup(bsc, int(bb["seed"]))
	var bridge_cells := 0
	for c in bsim.rv.size():
		if bsim.rv[c] == MapGen.R_BRIDGE:
			bridge_cells += 1
	if sim.riv_on == 0 or zone_wet != 0 or ramp < 4 or bsim.riv_on == 0 or bridge_cells <= 0 or sim.riv_box[2] <= sim.riv_box[0]:
		_fail("river: riv_on %d / %d, zone samples in or across the water %d, camp sections %d, bridge cells %d" % [
			sim.riv_on, bsim.riv_on, zone_wet, ramp, bridge_cells])
		return
	print("PASS river crossing option: a ford (side 2 fortified at it: %d palisade sections) and a bridge (%d cells) from the map seed, the zones short of the water, none without the option or on a settlement map" % [
		ramp, bridge_cells])


## Heroes and agents (docs/DESIGN.md "Heroes and agents"): the toggles reach
## the scenario, cost their price, become one-man character units after the
## scenario's own (Player 1's on side 1, the AI's on side 2), and the result
## rows carry "char" and "alive".
func _check_chars(field: Dictionary, town: Dictionary) -> void:
	var plain := CS.default_setup(15)
	var extra := CS.side_cost(field, 0) - CS.side_cost(plain, 0)
	var want := 0
	for k in CS.CHAR_KEYS:
		want += UT.price_of(UT.index_of(k))
	if extra != want:
		_fail("chars: the six cost %d, want %d" % [extra, want])
		return
	for st in [field, town]:
		var b := CS.build(st)
		var sc: Dictionary = b["scenario"]
		var lists: Array = sc.get("chars", [])
		if lists.size() != 2 or (lists[0] as Array).size() != 6 or (lists[1] as Array).size() != 6:
			_fail("chars: the scenario's chars are %s" % str(lists))
			return
		var players: Array = []
		for p in b["home"]:
			if int(p) >= 0 and not players.has(int(p)):
				players.append(int(p))
		var ls := Lockstep.new()
		ls.setup(sc, int(b["seed"]), b["home"], players, 0)
		var sim = ls.sim
		var n_scn: int = (sc["units"] as Array).size()
		var kinds := [[], []]
		var homes := [[], []]
		for u in range(n_scn, sim.n_units):
			if sim.u_char[u] != 0:
				kinds[sim.u_side[u]].append(sim.u_char[u])
				homes[sim.u_side[u]].append(ls.u_home[u])
		var r: Dictionary = sim.result()
		var rows := 0
		for row in r["units"]:
			if int(row.get("char", 0)) == 1 and int(row.get("alive", -1)) == 1:
				rows += 1
		var human: int = 0 if not (sc["ai_sides"] as Array).has(0) else 1
		if str(kinds[0]) != str([1, 2, 3, 4, 5, 6]) or str(kinds[1]) != str([1, 2, 3, 4, 5, 6]) or rows != 12 \
				or str(homes[human]) != str([0, 0, 0, 0, 0, 0]) or str(homes[1 - human]) != str([-1, -1, -1, -1, -1, -1]):
			_fail("chars (%s): kinds %s, homes %s, %d result rows" % [str(st["map"]["kind"]), str(kinds), str(homes), rows])
			return
		print("PASS chars (%s): six characters a side after the %d scenario units, kinds %s, Player 1 commands side %d's, the AI the other's; %d result rows with char 1 / alive 1; +%d gold a side" % [
			str(st["map"]["kind"]), n_scn, str(kinds[0]), human + 1, rows, extra])


## Occupy (slice 2c) is on in every West custom town (walls 0-3 and every plan
## as set: the West offers walls 0-2 and no Oppidum, an old setup is fitted) and
## off in Rome's.
func _check_occupy() -> void:
	var bad := ""
	for pack in ["west", "rome"]:
		for walls in 4:
			for plan in 5:
				var st := CS.default_setup(6)
				CS.set_pack(st, pack)
				st["map"]["kind"] = "settlement"
				st["map"]["walls"] = walls
				st["map"]["plan"] = plan
				var b := CS.build(st)
				if b.has("error"):
					bad += " %s w%d p%d: %s" % [pack, walls, plan, str(b["error"])]
					continue
				var sim := BattleSim.new()
				sim.setup(b["scenario"], int(b["seed"]))
				var want := 1 if pack == "west" else 0
				if sim.occ_on != want:
					bad += " %s walls %d plan %d occ_on %d;" % [pack, walls, plan, sim.occ_on]
	if bad != "":
		_fail("occupy:" + bad)
	else:
		print("PASS occupy: occ_on 1 on every West custom town (walls 0-3 and plans fitted to open towns), 0 on Rome's")
