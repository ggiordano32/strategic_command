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
## scenario hash both peers compare.

const CS := preload("res://game/custom/custom_setup.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Lockstep := preload("res://sim/lockstep.gd")
const UT := preload("res://sim/unit_types.gd")
const CoopSession := preload("res://game/net/coop_session.gd")

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
	storm["time"] = 1800
	setups["settlement, players storm with ladders and a ram, 30 min"] = storm
	var coop := CS.default_setup(7)
	coop["sides"][0]["armies"].append({"ctrl": "p2", "units": [["heavy2", 100], ["cav3", 60]]})
	setups["co-op"] = coop
	var ammo := _ammo_setup()
	setups["wagon and fire arrows, head-to-head"] = ammo
	var ammo_town: Dictionary = _ammo_setup()
	ammo_town["map"]["kind"] = "settlement"
	ammo_town["map"]["walls"] = 1
	setups["wagon and fire arrows, settlement"] = ammo_town
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
	for e in (sb["scenario"].get("equip", []) as Array):
		if int(e[0]) == BattleSim.EQ_LADDERS:
			lad += 1
		elif int(e[0]) == BattleSim.EQ_RAM:
			ram += 1
	var n_sc: int = (sb["scenario"]["units"] as Array).size()
	if lad != CS.LADDER_SETS or ram != 1 or (sb["home"] as Array).size() != n_sc + 1 \
			or int(sb["scenario"].get("time_limit", 0)) != 1800:
		_fail("storm: %d ladder sets, %d rams, %d home entries for %d units, time limit %s" % [lad, ram,
			(sb["home"] as Array).size(), n_sc, str(sb["scenario"].get("time_limit", 0))])
	_check_ammo(ammo, "field")
	_check_ammo(ammo_town, "settlement")
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
	print("RESULT: %s" % ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)


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


## Deploy (place one unit of each human side, ready) and fight a little,
## through the lockstep layer with every player present.
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
