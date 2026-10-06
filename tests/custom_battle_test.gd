extends SceneTree
## Custom battles (game/custom/custom_setup.gd), headless:
##   godot --headless --script res://tests/custom_battle_test.gd
## Every template and a few hand-made setups (two armies a side, Player 2 on
## the enemy side, a settlement, funds) build into a scenario the same way
## twice (and the same after a JSON round trip, as the relay passes it on),
## with a player for every unit of a human side and the AI on the others;
## the battle deploys (the player places a unit, readies) and runs; the
## setup checks refuse what cannot be played.

const CS := preload("res://game/custom/custom_setup.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Lockstep := preload("res://sim/lockstep.gd")

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
	var coop := CS.default_setup(7)
	coop["sides"][0]["armies"].append({"ctrl": "p2", "units": [["heavy2", 100], ["cav3", 60]]})
	setups["co-op"] = coop
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
		if home.size() != (sc["units"] as Array).size():
			_fail("%s: home has %d entries for %d units" % [name, home.size(), (sc["units"] as Array).size()])
			continue
		for i in home.size():
			var side := int(sc["units"][i]["side"])
			var human := not (sc["ai_sides"] as Array).has(side)
			if human != (int(home[i]) >= 0):
				_fail("%s: unit %d of side %d has player %d" % [name, i, side, int(home[i])])
				break
		_run(name, a)
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
