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
## gastraphetes build on a field and both shoot.

const CS := preload("res://game/custom/custom_setup.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const FM := preload("res://sim/fixed_math.gd")
const Lockstep := preload("res://sim/lockstep.gd")
const UT := preload("res://sim/unit_types.gd")
const CoopSession := preload("res://game/net/coop_session.gd")
const Terrain := preload("res://sim/terrain.gd")
const Scenarios := preload("res://sim/scenarios.gd")

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
		out.append("%s %d" % [k, shots])
		if shots <= 0:
			_fail("light missile: %s never shot in %d ticks (ammo %d of %d)" % [k, t, sim.u_ammo[units[k]], int(full[k])])
	print("PASS light missile: shots by tick %d: %s" % [t, ", ".join(out)])


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
