extends SceneTree
## Headless campaign rules test.
##   godot --headless --script res://tests/campaign_test.gd
## Data sanity (adjacency symmetric and connected, rosters valid), JSON
## round trip keeps the hash, turn resolution is deterministic (twice, and
## across a save / load in the middle), and unit checks of the rules:
## movement and sea lanes, peace blocking, economy sums, building and
## recruitment gating by level and tier, recruits arriving, replenishment,
## merge / split / disband, battle scenario and outcome mapping, conquest
## and retreat, elimination, victory. Exits 0 on success, 1 on failure.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const UT := preload("res://sim/unit_types.gd")

var fails := 0


func _init() -> void:
	_data()
	_round_trip()
	_determinism()
	_movement()
	_economy()
	_building()
	_recruiting()
	_replenish()
	_armies()
	_battles()
	_end_conditions()
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


func _check(cond: bool, what: String) -> void:
	if cond:
		print("PASS ", what)
	else:
		printerr("FAIL ", what)
		fails += 1


func _r(key: String) -> int:
	return CData.region_index(key)


func _f(key: String) -> int:
	return CData.faction_index(key)


func _new(humans: Array = []) -> Dictionary:
	return CState.new_campaign("test", 4242, humans)


func _data() -> void:
	_check(CData.region_count() == 36 and CData.faction_count() == 8, "36 regions, 8 factions")
	var sym := true
	for r in CData.region_count():
		for e in CData.adjacent(r):
			if CData.link(int(e[0]), r) != int(e[1]):
				sym = false
	_check(sym, "adjacency is symmetric")
	var seen := {0: true}
	var q := [0]
	while not q.is_empty():
		var r: int = q.pop_back()
		for e in CData.adjacent(r):
			if not seen.has(int(e[0])):
				seen[int(e[0])] = true
				q.append(int(e[0]))
	_check(seen.size() == 36, "every region reachable (%d)" % seen.size())
	var ok := true
	for k in CData.ROSTERS:
		for line in CData.ROSTERS[k]:
			for key in CData.ROSTERS[k][line]:
				if key != "" and (UT.index_of(key) < 0 or UT.line_of(UT.index_of(key)) != line):
					ok = false
					printerr("  bad roster entry %s %s %s" % [k, line, key])
	_check(ok, "rosters name existing unit types of the right line")
	var st := _new()
	var indep := 0
	for r in 36:
		if CState.owner(st, r) < 0:
			indep += 1
	_check(indep == 12, "12 independent regions at the start (%d)" % indep)
	_check(CState.dip(st, _f("rome"), _f("epirus")) == CState.WAR and CState.dip(st, _f("carthage"), _f("syracuse")) == CState.WAR
		and CState.dip(st, _f("rome"), _f("carthage")) == CState.PEACE, "starting wars")


func _round_trip() -> void:
	var st := _new([0, 1])
	for t in 3:
		st = CTurn.resolve_turn(st, [])
		while str(st["phase"]) == "battles":
			var b: Dictionary = st["battles"][0]
			st = CTurn.apply_battle(st, int(b["id"]), CBattle.formula(st, b))
	var text := CState.to_json(st)
	var back := CState.from_json(text)
	_check(not back.is_empty() and CState.state_hash(back) == CState.state_hash(st),
		"JSON round trip keeps the hash (%s)" % CState.hash_text(st))
	_check(CState.to_json(back) == text, "JSON round trip is byte-identical")
	_check(CState.from_json("{\"format\": \"x\"}").is_empty(), "foreign JSON is refused")


func _play(st: Dictionary, turns: int, mid_save: int) -> Dictionary:
	for t in turns:
		if t == mid_save:
			st = CState.from_json(CState.to_json(st))
		var subs: Array = []
		for h in st["humans"]:
			var orders: Array = []
			for a in CState.armies_of(st, int(h)):
				var tg := CRules.move_targets(st, a)
				if not tg.is_empty():
					orders.append({"t": "move", "army": int(a["id"]), "to": tg[(t + int(a["id"])) % tg.size()]})
			subs.append(CTurn.submission(st, int(h), orders))
		st = CTurn.resolve_turn(st, subs)
		while str(st["phase"]) == "battles":
			var b: Dictionary = st["battles"][0]
			st = CTurn.apply_battle(st, int(b["id"]), CBattle.formula(st, b))
	return st


func _determinism() -> void:
	var a := _play(_new([0]), 12, -1)
	var b := _play(_new([0]), 12, -1)
	var c := _play(_new([0]), 12, 6)
	_check(CState.state_hash(a) == CState.state_hash(b), "same inputs, same state after 12 turns (%s)" % CState.hash_text(a))
	_check(CState.state_hash(a) == CState.state_hash(c), "save / load in the middle changes nothing (%s)" % CState.hash_text(c))
	var d := _play(CState.new_campaign("test", 999, [0]), 12, -1)
	_check(CState.state_hash(a) != CState.state_hash(d), "a different seed diverges")


func _movement() -> void:
	var st := _new([_f("rome")])
	var rome := _f("rome")
	var a: Dictionary = CState.armies_of(st, rome)[0]  # in Latium
	_check(int(a["r"]) == _r("latium"), "Rome's first army starts in Latium")
	_check(CRules.can_move(st, a, _r("etruria")) == "", "move to an adjacent own region")
	_check(CRules.can_move(st, a, _r("apulia")) != "", "no move to a non-adjacent region")
	_check(CRules.can_move(st, a, _r("sardinia")) != "", "Sardinia (Carthage, at peace) is blocked: " + CRules.can_move(st, a, _r("sardinia")))
	_check(CData.link(_r("latium"), _r("sardinia")) == 1, "Latium-Sardinia is a sea lane")
	var pv := CTurn.preview(st, rome, [{"t": "war", "to": _f("carthage")}, {"t": "move", "army": int(a["id"]), "to": _r("sardinia")}])
	_check((pv["errors"] as Array).is_empty() and (pv["moves"] as Array).size() == 1, "declaring war opens the sea lane to Sardinia")
	var st2 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [{"t": "war", "to": _f("carthage")},
		{"t": "move", "army": int(a["id"]), "to": _r("sardinia")}])])
	var b := CState.battle_at(st2, _r("sardinia"))
	_check(not b.is_empty() and (b["att"] as Array).has(int(a["id"])) and str(st2["phase"]) == "battles",
		"crossing the sea lane into Sardinia makes a pending battle")
	var a2 := CState.army(st2, int(a["id"]))
	_check(CRules.can_move(st2, a2, _r("corsica")) != "", "an army in a pending battle cannot move")
	var o2 := CTurn.resolve_turn(st2, [])
	_check(int(o2["turn"]) == int(st2["turn"]), "resolve_turn refuses while battles are pending")


func _economy() -> void:
	var st := _new([_f("rome")])
	var rome := _f("rome")
	var inc := CRules.income(st, rome)
	var want := 0
	for r in CState.regions_of(st, rome):
		want += int(CData.REGIONS[r]["wealth"]) * CData.WEALTH_INCOME + int(CData.LEVEL_INCOME[int(st["regions"][r]["level"])])
		want += CState.building(st, r, CData.FARM) * CData.FARM_INCOME + CState.building(st, r, CData.MARKET) * CData.MARKET_INCOME
	_check(int(inc["regions"]) == want and int(inc["trade"]) == 0, "region income sums (%d)" % want)
	var up := CRules.upkeep(st, rome)
	var t0 := int(st["factions"][rome]["treasury"])
	var st2 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [])])
	_check(int(st2["factions"][rome]["treasury"]) == t0 + int(inc["total"]) - up,
		"treasury after a turn = before + income - upkeep (%d + %d - %d)" % [t0, int(inc["total"]), up])
	CState.set_dip(st, rome, _f("carthage"), CState.TRADE)
	_check(int(CRules.income(st, rome)["trade"]) > 0, "a trade agreement adds income (%d)" % int(CRules.income(st, rome)["trade"]))
	# Debt: units desert.
	st["factions"][rome]["treasury"] = -5000
	var men0 := 0
	for a in CState.armies_of(st, rome):
		men0 += CState.men(a)
	CRules.end_of_turn(st)
	var men1 := 0
	for a in CState.armies_of(st, rome):
		men1 += CState.men(a)
	_check(men1 < men0, "a turn ending in debt costs men (%d -> %d)" % [men0, men1])


func _building() -> void:
	var st := _new([_f("rome")])
	var rome := _f("rome")
	var sam := _r("samnium")  # village
	_check(CRules.apply_order(st, rome, {"t": "build", "r": sam, "chain": CData.BARRACKS}) == "", "village builds barracks 1")
	_check(CRules.apply_order(st, rome, {"t": "build", "r": sam, "chain": CData.MARKET}) != "", "one construction at a time")
	var st2 := CTurn.resolve_turn(st, [])
	_check(CState.building(st2, sam, CData.BARRACKS) == 1, "barracks 1 done after one turn")
	_check(CRules.build_info(st2, rome, sam, CData.BARRACKS).has("why"), "a village cannot build level 2: " + str(CRules.build_info(st2, rome, sam, CData.BARRACKS).get("why", "")))
	_check(CRules.apply_order(st2, rome, {"t": "build", "r": sam, "chain": CData.STABLES}) != "", "village slots are full (farm + barracks)")
	var lat := _r("latium")
	st2["factions"][rome]["treasury"] = 10000
	var t0 := int(st2["factions"][rome]["treasury"])
	_check(CRules.apply_order(st2, rome, {"t": "build", "r": lat, "chain": CData.BARRACKS}) == "", "city builds barracks 2")
	_check(int(st2["factions"][rome]["treasury"]) == t0 - int(CData.CHAINS[CData.BARRACKS]["cost"][1]), "the cost is paid")
	var s3 := CTurn.resolve_turn(st2, [])
	_check(CState.building(s3, lat, CData.BARRACKS) == 1, "level 2 takes two turns (still 1 after one)")
	s3 = CTurn.resolve_turn(s3, [])
	_check(CState.building(s3, lat, CData.BARRACKS) == 2, "level 2 done after two turns")
	# Growth.
	var s4 := _new([rome])
	s4["regions"][sam]["growth"] = int(CData.GROWTH_TO[1]) - 1
	CRules.end_of_turn(s4)
	_check(int(s4["regions"][sam]["level"]) == CData.TOWN, "a village grows into a town")


func _recruiting() -> void:
	var st := _new([_f("rome")])
	var rome := _f("rome")
	var lat := _r("latium")
	_check(CRules.recruit_check(st, rome, lat, "heavy") == "", "Roma recruits heavy swords (barracks 1)")
	_check(CRules.recruit_check(st, rome, lat, "principes") != "", "principes need barracks 2: " + CRules.recruit_check(st, rome, lat, "principes"))
	_check(CRules.recruit_check(st, rome, lat, "pike") != "", "pikes are not in Rome's roster")
	_check(CRules.recruit_check(st, rome, lat, "bolt") != "", "bolts need a workshop")
	CState._add_building(st["regions"][lat], CData.BARRACKS, 2, 99)
	_check(CRules.recruit_check(st, rome, lat, "principes") == "", "barracks 2 unlocks principes (tier 2)")
	_check(CRules.recruit_check(st, rome, lat, "extraordinarii") != "", "tier 3 needs barracks 3")
	st["factions"][rome]["treasury"] = 10000
	for k in 3:
		CRules.apply_order(st, rome, {"t": "recruit", "r": lat, "unit": "heavy"})
	_check(CRules.recruit_check(st, rome, lat, "heavy") != "", "a city recruits 3 units a turn")
	var before := CState.unit_count(CState.armies_of(st, rome)[0])
	var st2 := CTurn.resolve_turn(st, [])
	var after := CState.unit_count(CState.army(st2, int(CState.armies_of(st, rome)[0]["id"])))
	_check(after == mini(before + 3, CData.ARMY_MAX), "recruits join the army in the region next turn (%d -> %d)" % [before, after])


func _replenish() -> void:
	var st := _new([_f("rome")])
	var rome := _f("rome")
	var a: Dictionary = CState.armies_of(st, rome)[0]
	a["units"][0]["n"] = 40
	CRules.end_of_turn(st)
	var lvl := CState.building(st, int(a["r"]), CData.BARRACKS)
	var want := 40 + 100 * (CData.REPLENISH_BASE + CData.REPLENISH_PER_LEVEL * lvl) / 100
	_check(int(a["units"][0]["n"]) == want, "replenishment in a region with barracks %d: 40 -> %d" % [lvl, int(a["units"][0]["n"])])


func _armies() -> void:
	var st := _new([_f("rome")])
	var rome := _f("rome")
	var a: Dictionary = CState.armies_of(st, rome)[0]
	var n0 := CState.unit_count(a)
	var nid := CRules.new_army_id(st, rome)
	_check(CRules.apply_order(st, rome, {"t": "split", "army": int(a["id"]), "units": [0, 1], "new": nid}) == "", "split two units off")
	var b := CState.army(st, nid)
	_check(not b.is_empty() and CState.unit_count(b) == 2 and CState.unit_count(a) == n0 - 2, "the new army has them")
	_check(CRules.apply_order(st, rome, {"t": "merge", "army": nid, "into": int(a["id"])}) == "" and CState.unit_count(a) == n0, "merge back")
	_check(CRules.apply_order(st, rome, {"t": "disband", "army": int(a["id"]), "units": [0]}) == "" and CState.unit_count(a) == n0 - 1, "disband a unit")
	var big := CState.army(st, int(a["id"]))
	while CState.unit_count(big) < CData.ARMY_MAX:
		(big["units"] as Array).append({"t": "heavy", "n": 100})
	var other: Dictionary = CState.armies_of(st, rome)[1]
	other["r"] = int(big["r"])
	_check(CRules.apply_order(st, rome, {"t": "merge", "army": int(other["id"]), "into": int(big["id"])}) != "", "no merge past 12 units")


func _battles() -> void:
	var st := _new([_f("rome")])
	var rome := _f("rome")
	var a: Dictionary = CState.armies_of(st, rome)[1]  # Samnium
	var st2 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [{"t": "move", "army": int(a["id"]), "to": _r("apulia")}])])
	var b := CState.battle_at(st2, _r("apulia"))
	_check(not b.is_empty(), "attacking Apulia (Epirus) makes a pending battle")
	if b.is_empty():
		return
	var built := CBattle.build(st2, b, rome)
	var sc: Dictionary = built["scenario"]
	var sim := BattleSim.new()
	sim.setup(sc, int(built["seed"]))
	_check(sim.n_units == (built["map"] as Array).size() and sim.n_units > 0, "battle scenario sets up (%d units, %d soldiers, %dx%d m)" % [sim.n_units, sim.n, int(sc["width_m"]), int(sc["height_m"])])
	var att0 := 0
	for k in sim.n_units:
		if sim.u_side[k] == 0:
			att0 += 1
	_check(att0 == CState.unit_count(CState.army(st2, int(a["id"]))), "the human attacker is sim side 0 with all its units")
	_check(sc["terrain"].has("features") == (CState.walls(st2, _r("apulia")) > 0), "walls put the defenders on a ridge")
	var built2 := CBattle.build(st2, b, rome)
	_check(str(built2) == str(built), "the scenario is a pure function of the state")
	# Fake result: attackers win, defenders all killed.
	var res := sim.result()
	res["winner"] = 0
	for u in res["units"]:
		if int(u["side"]) == 1:
			u["killed"] = int(u["started"])
			u["remaining"] = 0
	var out := CBattle.outcome_from_result(built, res, "fought")
	var st3 := CTurn.apply_battle(st2, int(b["id"]), out)
	_check(CState.owner(st3, _r("apulia")) == rome and str(st3["phase"]) == "plan", "the winner takes Apulia; planning resumes")
	var ep_army_gone := true
	for x in CState.armies_of(st3, _f("epirus")):
		if int(x["r"]) == _r("apulia"):
			ep_army_gone = false
	_check(ep_army_gone, "the beaten defenders are gone from Apulia")
	# Attacker loses: retreats to where it came from.
	res["winner"] = 1
	var out2 := CBattle.outcome_from_result(built, res, "fought")
	var st4 := CTurn.apply_battle(st2, int(b["id"]), out2)
	var a4 := CState.army(st4, int(a["id"]))
	_check(not a4.is_empty() and int(a4["r"]) == _r("samnium"), "a beaten attacker retreats to its origin")
	_check(CState.owner(st4, _r("apulia")) == _f("epirus"), "the defenders keep Apulia")
	# Formula.
	var fo := CBattle.formula(CState.copy(st2), b)
	_check(fo.has("winner") and (fo["units"] as Array).size() > 0, "formula outcome")


func _end_conditions() -> void:
	var st := _new([_f("rome")])
	var ep := _f("epirus")
	var rome := _f("rome")
	for r in CState.regions_of(st, ep):
		st["regions"][r]["owner"] = rome
	CRules.check_eliminations(st)
	_check(not CState.alive(st, ep) and CState.armies_of(st, ep).is_empty(), "a faction without regions is eliminated")
	var n := 0
	for r in 36:
		if n < 20:
			st["regions"][r]["owner"] = rome
			n += 1
	for key in ["zeugitana", "macedonia"]:
		st["regions"][_r(key)]["owner"] = rome
	CRules.check_victory(st)
	_check(int(st["winner"]) == 1 and str(st["phase"]) == "over", "20 regions with 3 key cities win")
	var s2 := _new([_f("rome"), _f("greeks")])
	for r in CState.regions_of(s2, _f("greeks")):
		s2["regions"][r]["owner"] = _f("macedon")
	CRules.check_eliminations(s2)
	CRules.check_victory(s2)
	_check(int(s2["winner"]) == 0, "the players lose if either is eliminated")
