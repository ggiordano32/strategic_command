extends SceneTree
## Headless campaign rules test.
##   godot --headless --script res://tests/campaign_test.gd
## Data sanity (adjacency symmetric and connected, rosters valid), JSON
## round trip keeps the hash, turn resolution is deterministic (twice, and
## across a save / load in the middle), and unit checks of the rules:
## movement and sea lanes, peace blocking, economy sums, building and
## recruitment gating by level and tier, recruits arriving, replenishment,
## merge / split / disband, battle scenario and outcome mapping, armies
## joining a battle started this turn (side cap, defenders), conquest
## and retreat, elimination, victory. Format 2 (city seeds): a saved format 1
## campaign migrates on load, an unmigrated (online) one plays the same;
## settlement battles on the city's own map, sim side and winner mapping
## for an attacking and a defending human, run to a decision. Format 4
## (sieges): start, join, lift, supplies and starvation, surrender, the
## besieged region's economy, assault / sally / relief battles and their
## outcomes, the odds against the formula, co-op assaults, migration.
## Exits 0 on success, 1 on failure.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const UT := preload("res://sim/unit_types.gd")
const Saves := preload("res://game/campaign/saves.gd")

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
	_joining()
	_format()
	_format3()
	_settlement_battle()
	_sieges()
	_siege_economy()
	_siege_battles()
	_odds()
	_coop_siege()
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
		{"t": "move", "army": int(a["id"]), "to": _r("sardinia"), "mode": CData.MODE_ASSAULT}])])
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
	var st2 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [{"t": "move", "army": int(a["id"]), "to": _r("apulia"), "mode": CData.MODE_ASSAULT}])])
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
	_check(sc["terrain"].has("city") and int(sc["terrain"]["city"]["walls"]) == CState.walls(st2, _r("apulia"))
		and int(sc["terrain"]["city"]["seed"]) == CState.city_seed(st2, _r("apulia")),
		"a settlement battle is fought on the city's own map (walls %d)" % CState.walls(st2, _r("apulia")))
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


## Armies entering a region where a battle started this turn join it (up to
## BATTLE_SIDE_MAX field units a side); a battle from an earlier turn blocks.
func _joining() -> void:
	var st := _new([_f("rome")])
	var rome := _f("rome")
	var a: Dictionary = CState.armies_of(st, rome)[1]  # Samnium
	var nid := CRules.new_army_id(st, rome)
	var sub := CTurn.submission(st, rome, [{"t": "split", "army": int(a["id"]), "units": [0], "new": nid},
		{"t": "move", "army": int(a["id"]), "to": _r("apulia"), "mode": CData.MODE_ASSAULT}, {"t": "move", "army": nid, "to": _r("apulia"), "mode": CData.MODE_ASSAULT}])
	var st2 := CTurn.resolve_turn(st, [sub])
	var b := CState.battle_at(st2, _r("apulia"))
	_check((st2["battles"] as Array).size() == 1 and not b.is_empty() and (b["att"] as Array).has(int(a["id"]))
		and (b["att"] as Array).has(nid), "two armies moving into Apulia together fight one battle side by side")
	var j := CState.army(st2, nid)
	var l := CState.army(st2, int(a["id"]))
	_check(not j.is_empty() and int(j["r"]) == _r("apulia") and int(j["busy"]) == 1
		and int(j["from"]) == int(l["from"]) and int(j["moved"]) == int(l["moved"]),
		"the joining army arrives like the army that started the battle")
	var st2b := CTurn.resolve_turn(st, [sub])
	_check(CState.state_hash(st2) == CState.state_hash(st2b), "joining is deterministic")
	# A battle pending from an earlier turn still blocks.
	var x := {"id": CRules.new_army_id(st2, rome), "f": rome, "r": _r("samnium"), "units": [{"t": "heavy", "n": 100}],
		"from": _r("samnium"), "moved": 0, "busy": 0}
	CRules._insert_army(st2, x)
	_check(CRules.execute_move(st2, CState.army(st2, int(x["id"])), _r("apulia")) == "battle pending there",
		"a battle from an earlier turn still blocks the move")
	# Side cap: 12 + 12 units join, one more is bounced.
	var s3 := _new([_f("rome")])
	var a1: Dictionary = CState.armies_of(s3, rome)[0]
	var a2: Dictionary = CState.armies_of(s3, rome)[1]
	a1["r"] = _r("samnium")
	for arm in [a1, a2]:
		while CState.unit_count(arm) < CData.ARMY_MAX:
			(arm["units"] as Array).append({"t": "heavy", "n": 100})
	var a3id := CRules.new_army_id(s3, rome)
	s3["factions"][rome]["next_army"] = int(s3["factions"][rome]["next_army"]) + 1
	CRules._insert_army(s3, {"id": a3id, "f": rome, "r": _r("samnium"), "units": [{"t": "heavy", "n": 100}],
		"from": _r("samnium"), "moved": 0, "busy": 0})
	var s4 := CTurn.resolve_turn(s3, [CTurn.submission(s3, rome, [{"t": "move", "army": int(a1["id"]), "to": _r("apulia"), "mode": CData.MODE_ASSAULT},
		{"t": "move", "army": int(a2["id"]), "to": _r("apulia"), "mode": CData.MODE_ASSAULT}, {"t": "move", "army": a3id, "to": _r("apulia"), "mode": CData.MODE_ASSAULT}])])
	var b4 := CState.battle_at(s4, _r("apulia"))
	var why := ""
	for e in s4["events"]:
		if str(e["k"]) == "move_failed" and int(e["army"]) == a3id:
			why = str(e["why"])
	_check(not b4.is_empty() and (b4["att"] as Array).size() == 2 and not (b4["att"] as Array).has(a3id)
		and int(CState.army(s4, a3id)["r"]) == _r("samnium") and why == "battle side full",
		"past %d units a side the extra army is bounced (%s)" % [CData.BATTLE_SIDE_MAX, why])
	# Defending: an army moving into its own region attacked this turn joins the defenders.
	var s5 := _new([_f("rome")])
	var ep := _f("epirus")
	var e5 := {"id": CRules.new_army_id(s5, ep), "f": ep, "r": _r("apulia"), "units": [{"t": "heavy", "n": 100}],
		"from": _r("apulia"), "moved": 0, "busy": 0}
	CRules._insert_army(s5, e5)
	var e5a := CState.army(s5, int(e5["id"]))
	_check(CRules.execute_move(s5, e5a, _r("samnium")) == "", "Epirus attacks Samnium")
	var d: Dictionary = CState.armies_of(s5, rome)[0]  # Latium
	_check(CRules.execute_move(s5, d, _r("samnium")) == "", "Rome's army marches to Samnium")
	var b5 := CState.battle_at(s5, _r("samnium"))
	_check(not b5.is_empty() and (b5["def"] as Array).has(int(d["id"])) and (b5["def"] as Array).has(int(a["id"]))
		and int(d["busy"]) == 1, "an army entering its own region attacked this turn joins the defenders")


## Format 2: city seeds, migration of a format 1 save, unmigrated play.
func _format() -> void:
	var nst := _new([0])
	var seeds_ok := int(nst["version"]) == CState.VERSION
	for r in 36:
		if int(nst["regions"][r].get("city_seed", -1)) != CState.default_city_seed(r):
			seeds_ok = false
	_check(seeds_ok, "a new campaign is format %d with a city seed per settlement" % CState.VERSION)
	var distinct := {}
	for r in 36:
		distinct[CState.default_city_seed(r)] = true
	_check(distinct.size() == 36, "the 36 city seeds differ")
	var text := FileAccess.get_file_as_string("res://tests/data/campaign_v1.json")
	_check(text.length() > 100, "the format 1 campaign file is there")
	var raw: Dictionary = CState.normalise(JSON.parse_string(text))
	_check(int(raw["version"]) == 1 and not (raw["regions"][0] as Dictionary).has("city_seed"), "it is a real format 1 state")
	var mig := CState.from_json(text)
	var ok := not mig.is_empty() and int(mig["version"]) == CState.VERSION
	for r in 36:
		if mig.is_empty() or int(mig["regions"][r].get("city_seed", -1)) != CState.default_city_seed(r):
			ok = false
	_check(ok, "from_json migrates format 1 -> %d: every settlement gets its city seed" % CState.VERSION)
	var sv := Saves.parse(JSON.stringify({"state": raw.duplicate(true), "session": {}}))
	_check(not sv.is_empty() and int(sv["state"]["version"]) == CState.VERSION and int(sv["state"]["regions"][5]["city_seed"]) == CState.default_city_seed(5),
		"Saves.parse migrates a saved format 1 campaign")
	var same := true
	for r in 36:
		if CState.city_seed(raw, r) != CState.city_seed(mig, r):
			same = false
	_check(same, "city_seed() of an unmigrated format 1 state (online) equals the migrated value")
	var r1 := CTurn.resolve_turn(raw.duplicate(true), [])
	var r2 := CTurn.resolve_turn(raw.duplicate(true), [])
	_check(int(r1["version"]) == 1 and not (r1["regions"][0] as Dictionary).has("city_seed")
		and not (r1["regions"][0] as Dictionary).has("built") and CState.state_hash(r1) == CState.state_hash(r2), "an unmigrated format 1 state resolves as format 1, deterministically (%s)" % CState.hash_text(r1))
	# Migrated only to format 3 (no sieges: what the previous build made of
	# it), it plays the same turn as the unmigrated one.
	var mig3 := mig.duplicate(true)
	mig3.erase("sieges")
	mig3["version"] = 3
	var r3 := CTurn.resolve_turn(mig3, [])
	var eq := true
	for k in ["turn", "factions", "armies", "dip", "battles", "rng"]:
		if str(r1[k]) != str(r3[k]):
			eq = false
	_check(eq, "the format 3 copy plays the same turn as the unmigrated one")
	_check(int(mig["version"]) == 4 and (mig["sieges"] as Array).is_empty(), "the full migration reaches format 4 with no sieges")
	_check(CState.from_json(JSON.stringify({"format": CState.FORMAT, "version": CState.VERSION + 1})).is_empty(),
		"a newer format is refused")


## Format 3: builder data (who built what), migration of a format 2 state,
## an unmigrated format 2 state playing like its migrated copy.
func _format3() -> void:
	var nst := _new([_f("rome")])
	var ok := int(nst["version"]) >= 3
	for r in 36:
		if not (nst["regions"][r] as Dictionary).has("built") or not (nst["regions"][r]["built"] as Array).is_empty():
			ok = false
	_check(ok, "a new campaign is format 3+ with an empty builder list per settlement")
	var cul_ok := true
	for r in 36:
		if int(CData.REGIONS[r].get("culture", -1)) < 0 or int(CData.REGIONS[r]["culture"]) > 3:
			cul_ok = false
	for f in CData.faction_count():
		if CData.faction_culture(f) < 0:
			cul_ok = false
	_check(cul_ok and CData.region_culture(_r("latium")) == CData.LATIN and CData.region_culture(_r("attica")) == CData.GREEK
		and CData.region_culture(_r("zeugitana")) == CData.PUNIC and CData.region_culture(_r("arverni")) == CData.CELTIC,
		"every region and faction has a culture")
	_check(CData.is_port(_r("zeugitana")) and CData.is_port(_r("massalia")) and not CData.is_port(_r("attica"))
		and not CData.is_port(_r("arverni")), "ports are the regions on sea lanes")
	# A format 2 state (format 3 minus the builder lists).
	var v2 := CState.copy(nst)
	v2["version"] = 2
	for r in 36:
		(v2["regions"][r] as Dictionary).erase("built")
	var mig := CState.from_json(CState.to_json(v2))
	var mok := not mig.is_empty() and int(mig["version"]) == CState.VERSION
	for r in 36:
		if mig.is_empty() or not (mig["regions"][r] as Dictionary).has("built"):
			mok = false
	_check(mok and CState.state_hash(mig) == CState.state_hash(nst), "a format 2 state migrates to format %d (equal to the new campaign)" % CState.VERSION)
	# Builder entries: a building completed and a settlement grown under a
	# new owner are in the owner's style; nothing else changes.
	var st := CState.copy(nst)
	st.erase("sieges")  # format 3 against format 2: no sieges in either
	st["version"] = 3
	var rome := _f("rome")
	var ap := _r("apulia")
	var br := _r("bruttium")
	st["regions"][ap]["owner"] = rome
	st["regions"][ap]["build"] = [CData.MARKET, 2, 1]
	st["regions"][br]["owner"] = rome
	st["regions"][br]["growth"] = int(CData.GROWTH_TO[1]) - 1
	var v2b := CState.copy(st)
	v2b["version"] = 2
	for r in 36:
		(v2b["regions"][r] as Dictionary).erase("built")
	var s1 := CTurn.resolve_turn(st, [])
	var bl: Array = s1["regions"][ap]["built"]
	_check(bl.size() == 1 and int(bl[0][0]) == CData.MARKET and int(bl[0][1]) == 2 and int(bl[0][2]) == CData.LATIN
		and CState.builder_culture(s1, ap, CData.MARKET, 2) == CData.LATIN
		and CState.builder_culture(s1, ap, CData.MARKET, 1) == CData.GREEK, "a market built by Rome in Tarentum is Roman (%s)" % str(bl))
	var gl: Array = s1["regions"][br]["built"]
	_check(int(s1["regions"][br]["level"]) == 1 and gl.size() == 1 and int(gl[0][0]) == -1 and int(gl[0][2]) == CData.LATIN,
		"Rhegium growing into a town under Rome records Roman houses (%s)" % str(gl))
	var cd := CBattle.city_dict(s1, br)
	_check(int(cd["plan"]) == CData.GREEK and int(cd["founder"]) == CData.GREEK and int(cd["owner"]) == CData.LATIN
		and int(cd["banner"]) == rome and str(cd["hstyle"]) == str([CData.GREEK, CData.LATIN, CData.GREEK]) and int(cd["coast"]) == 1,
		"the city dict: Greek plan, coastal, Roman owner, Roman town houses (%s)" % str(cd))
	var cda := CBattle.city_dict(s1, ap)
	var bpos := (cda["bld"] as Array).find(CData.MARKET)
	_check(bpos >= 0 and int(cda["bstyle"][bpos]) == CData.LATIN and (cda["bstyle"] as Array).size() == (cda["bld"] as Array).size(),
		"bstyle follows bld: the market is Roman (%s)" % str(cda))
	_check(CBattle.city_caption(s1, br).ends_with("held by Rome") and CBattle.city_caption(s1, br).begins_with("Greek town"),
		"caption: %s" % CBattle.city_caption(s1, br))
	# The same turn on an unmigrated format 2 copy: no builder keys appear,
	# everything else is the same.
	var s2 := CTurn.resolve_turn(v2b, [])
	_check(int(s2["version"]) == 2 and not (s2["regions"][ap] as Dictionary).has("built"), "an unmigrated format 2 state never gains builder data")
	var eq := true
	for k in ["turn", "factions", "armies", "dip", "battles", "rng"]:
		if str(s1[k]) != str(s2[k]):
			eq = false
	for r in 36:
		for k in ["owner", "level", "slots", "growth", "gar"]:
			if str(s1["regions"][r][k]) != str(s2["regions"][r][k]):
				eq = false
	_check(eq, "the format 2 copy plays the same turn")
	_check(CBattle.city_dict(s2, ap)["bstyle"][bpos] == CData.GREEK, "... and shows the founder's style")
	# Battles on an unmigrated format 2 state and its migrated copy build the
	# same scenario (integers only).
	var w2 := CState.copy(nst)
	w2.erase("sieges")
	w2["version"] = 2
	for r in 36:
		(w2["regions"][r] as Dictionary).erase("built")
	var a: Dictionary = CState.armies_of(w2, rome)[1]
	var sub := [CTurn.submission(w2, rome, [{"t": "move", "army": int(a["id"]), "to": _r("apulia")}])]
	var t2 := CTurn.resolve_turn(w2, sub)
	var w3 := CState.from_json(CState.to_json(w2))
	w3.erase("sieges")  # migrated as far as format 3 (the build that had no sieges)
	w3["version"] = 3
	var t3 := CTurn.resolve_turn(w3, sub)
	var b2 := CState.battle_at(t2, _r("apulia"))
	var b3 := CState.battle_at(t3, _r("apulia"))
	_check(not b2.is_empty() and not b3.is_empty(), "the battle happens on both copies")
	if not b2.is_empty() and not b3.is_empty():
		var sc2: Dictionary = CBattle.build(t2, b2, rome)["scenario"]
		var sc3: Dictionary = CBattle.build(t3, b3, rome)["scenario"]
		_check(str(sc2) == str(sc3), "format 2 and its migrated copy build the same battle scenario")
		_check(_ints_only(sc2["terrain"]["city"]), "the city dict carries only integers (%s)" % str(sc2["terrain"]["city"]))


func _ints_only(v) -> bool:
	if v is int:
		return true
	if v is Array:
		for x in v:
			if not _ints_only(x):
				return false
		return true
	if v is Dictionary:
		for k in v:
			if not _ints_only(v[k]):
				return false
		return true
	return false


## Settlement battles: the city's map, sides for an attacking and a defending
## human, the winner mapping both ways, and an AI battle to a decision.
func _settlement_battle() -> void:
	var st := _new([_f("rome")])
	var rome := _f("rome")
	var a: Dictionary = CState.armies_of(st, rome)[1]  # Samnium
	var st2 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [{"t": "move", "army": int(a["id"]), "to": _r("apulia"), "mode": CData.MODE_ASSAULT}])])
	var b := CState.battle_at(st2, _r("apulia"))
	if b.is_empty():
		_check(false, "settlement battle at Apulia")
		return
	for who in [rome, _f("epirus")]:
		var built := CBattle.build(st2, b, who)
		var sim := BattleSim.new()
		sim.setup(built["scenario"], int(built["seed"]))
		var sim_side: Array = built["sim_side"]
		var att_side: int = sim_side[0]
		var walls := 0
		var mapping := true
		var map: Array = built["map"]
		for k in sim.n_units:
			if sim.u_wall[k] > 0:
				walls += 1
				if sim.u_side[k] != int(sim_side[1]):
					mapping = false
			if sim.u_side[k] != int(sim_side[int(map[k]["side"])]):
				mapping = false
		var tag := "attacking" if who == rome else "defending"
		_check(sim.city_on == 1 and sim.city_def == int(sim_side[1]), "%s human: city map, defenders are sim side %d" % [tag, int(sim_side[1])])
		_check(walls > 0 and mapping, "%s human: %d garrison units on the walls, unit map matches the sim sides" % [tag, walls])
		var human_side := 0
		_check((who == rome and att_side == human_side) or (who != rome and int(sim_side[1]) == human_side),
			"%s human: the human side is sim side 0 (at the bottom)" % tag)
		# The city sits at the defenders' end of the field.
		var city_low: bool = sim.plaza[1] > sim.field_h / 2
		_check(city_low == (int(sim_side[1]) == 0), "%s human: the city is at the defenders' edge" % tag)
		# Winner mapping: the sim's attacker side wins -> campaign attackers (0).
		var res := sim.result()
		res["winner"] = att_side
		_check(int(CBattle.outcome_from_result(built, res, "fought")["winner"]) == 0, "%s human: attackers' sim win maps to campaign attackers" % tag)
		res["winner"] = int(sim_side[1])
		_check(int(CBattle.outcome_from_result(built, res, "fought")["winner"]) == 1, "%s human: defenders' sim win maps to campaign defenders" % tag)
	# AI against AI to a decision (half size, like the fast auto-resolve).
	var built3 := CBattle.build(st2, b, -1, 50)
	var s3 := BattleSim.new()
	s3.setup(built3["scenario"], int(built3["seed"]))
	var t0 := Time.get_ticks_msec()
	while s3.ended == 0 and s3.tick < 9000:
		s3.step()
	var out := CBattle.outcome_from_result(built3, s3.result(), "auto")
	_check(s3.winner == 0 or s3.winner == 1, "AI settlement battle decided (sim winner %d, decided at %d s, %d ms); campaign winner %d" % [
		s3.winner, s3.decided_tick / 10, Time.get_ticks_msec() - t0, int(out["winner"])])
	var st4 := CTurn.apply_battle(st2, int(b["id"]), out)
	_check(str(st4["phase"]) == "plan", "the result applies")


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


# ---------------------------------------------------------------- sieges ---

func _events(st: Dictionary, k: String) -> Array:
	var out: Array = []
	for e in st["events"]:
		if str(e["k"]) == k:
			out.append(e)
	return out


func _sub(st: Dictionary, f: int, orders: Array) -> Array:
	return [CTurn.submission(st, f, orders)]


## A Roman campaign at peace with Epirus (no AI war on Rome before turn 10),
## Rome's first army in Etruria next to Corsica (independent village).
func _siege_start() -> Dictionary:
	var st := _new([_f("rome")])
	CState.set_dip(st, _f("rome"), _f("epirus"), CState.PEACE)
	var a: Dictionary = CState.armies_of(st, _f("rome"))[0]
	a["r"] = _r("etruria")
	return st


func _sieges() -> void:
	var rome := _f("rome")
	var co := _r("corsica")
	var st := _siege_start()
	var a: Dictionary = CState.armies_of(st, rome)[0]
	var aid := int(a["id"])
	_check(CState.sieges_on(st) and CState.owner(st, co) < 0, "a new campaign has sieges; Corsica is independent")
	var s1 := CTurn.resolve_turn(st, _sub(st, rome, [{"t": "move", "army": aid, "to": co}]))
	var sg := CState.siege_at(s1, co)
	_check(CState.battle_at(s1, co).is_empty() and str(s1["phase"]) == "plan" and not sg.is_empty()
		and int(sg["f"]) == rome and int(sg["turn"]) == 0 and int(CState.army(s1, aid)["r"]) == co,
		"a move without a mode lays siege: no battle, a siege record (%s)" % str(sg))
	_check(int(sg["supply"]) == CState.siege_supply(st, co) - 1 and int(sg["held"]) == 1,
		"supplies ran down one turn (%d of %d)" % [int(sg.get("supply", -1)), CState.siege_supply(st, co)])
	var sev := _events(s1, "siege").filter(func(e): return int(e["r"]) == co)
	_check(sev.size() == 1 and int(sev[0]["f"]) == rome, "a siege event")
	var a1 := CState.army(s1, aid)
	_check(CRules.siege_role(s1, a1) == 1 and int(a1["busy"]) == 0, "the army besieges (role 1)")
	_check(CRules.apply_order(CState.copy(s1), rome, {"t": "disband", "army": aid, "units": [0]}) != ""
		and CRules.apply_order(CState.copy(s1), rome, {"t": "split", "army": aid, "units": [0], "new": CRules.new_army_id(s1, rome)}) != "",
		"a besieging army cannot split or disband")
	_check(CRules.can_move(s1, a1, _r("etruria")) == "", "but it can march away")
	_check(CRules.can_assault(s1, rome, co) == "" and CRules.can_sally(s1, rome, co) != "", "Rome may assault Corsica, not sally")
	# A second army joins the siege.
	var b2: Dictionary = CState.armies_of(s1, rome)[1]
	b2["r"] = _r("etruria")
	var bid := int(b2["id"])
	var s2 := CTurn.resolve_turn(s1, _sub(s1, rome, [{"t": "move", "army": bid, "to": co, "mode": CData.MODE_SIEGE}]))
	var sg2 := CState.siege_at(s2, co)
	_check(CRules.besiegers(s2, co).size() == 2 and (sg2["from"] as Array).size() == 2 and CState.battle_at(s2, co).is_empty(),
		"a second army moving in joins the siege (%s)" % str(sg2.get("from", [])))
	# Assault: one settlement battle with both besiegers.
	var pv := CTurn.preview(s2, rome, [{"t": "assault", "r": co}])
	_check((pv["errors"] as Array).is_empty(), "the assault order is valid while planning")
	var s3 := CTurn.resolve_turn(s2, _sub(s2, rome, [{"t": "assault", "r": co}]))
	var b := CState.battle_at(s3, co)
	_check(not b.is_empty() and str(b.get("kind", "")) == "assault" and int(b["settlement"]) == 1
		and (b["att"] as Array).has(aid) and (b["att"] as Array).has(bid) and str(s3["phase"]) == "battles",
		"assault: a pending settlement battle with every besieger (%s)" % str(b))
	var s3b := CTurn.resolve_turn(s2, _sub(s2, rome, [{"t": "assault", "r": co}]))
	_check(CState.state_hash(s3) == CState.state_hash(s3b), "sieges resolve deterministically (%s)" % CState.hash_text(s3))
	if not b.is_empty():
		var built := CBattle.build(s3, b, rome)
		_check((built["scenario"]["terrain"] as Dictionary).has("city"), "the assault is fought on the city's map")
		# Won: Corsica is Rome's, the siege is over.
		var s4 := CTurn.apply_battle(s3, int(b["id"]), {"winner": 0, "mode": "fought", "units": [], "garrison_pct": 0})
		_check(CState.owner(s4, co) == rome and CState.siege_at(s4, co).is_empty() and str(s4["phase"]) == "plan",
			"a won assault takes the city and ends the siege")
		# Lost: the besiegers fall back to Etruria, the siege is lifted.
		var s5 := CTurn.apply_battle(s3, int(b["id"]), {"winner": 1, "mode": "fought", "units": [], "garrison_pct": 80})
		_check(int(CState.army(s5, aid)["r"]) == _r("etruria") and int(CState.army(s5, bid)["r"]) == _r("etruria")
			and CState.siege_at(s5, co).is_empty() and _events(s5, "siege_lifted").size() == 1,
			"a failed assault: the besiegers fall back where they came from and the siege is lifted")
	# Lifting by marching away: one leaves (the siege stays), then the last.
	var l1 := CTurn.resolve_turn(s2, _sub(s2, rome, [{"t": "move", "army": aid, "to": _r("etruria")}]))
	_check(not CState.siege_at(l1, co).is_empty() and CRules.besiegers(l1, co).size() == 1, "one army leaves: the siege goes on")
	var l2 := CTurn.resolve_turn(l1, _sub(l1, rome, [{"t": "move", "army": bid, "to": _r("etruria")}]))
	_check(CState.siege_at(l2, co).is_empty() and _events(l2, "siege_lifted").size() == 1, "the last besieger leaves: the siege is lifted")
	# Assault mode: battle at once, as before sieges.
	var m1 := CTurn.resolve_turn(st, _sub(st, rome, [{"t": "move", "army": aid, "to": co, "mode": CData.MODE_ASSAULT}]))
	_check(not CState.battle_at(m1, co).is_empty() and CState.siege_at(m1, co).is_empty(), "mode 1 assaults at once")
	# A format 3 state ignores the mode: every move into hostile land attacks.
	var v3 := CState.copy(st)
	v3.erase("sieges")
	v3["version"] = 3
	var m3 := CTurn.resolve_turn(v3, _sub(v3, rome, [{"t": "move", "army": aid, "to": co}]))
	_check(not CState.battle_at(m3, co).is_empty() and not m3.has("sieges"), "a format 3 state (online, unmigrated) has no sieges: the move attacks")
	_check(CRules.can_assault(v3, rome, co) != "", "and refuses assault orders")
	# Starvation and surrender: supplies, then 25 points a turn, then the
	# city gives up without a battle.
	var sv := s1
	var supply := CState.siege_supply(st, co)
	var turns := 1
	var surrendered := false
	var gar_seen: Array = []
	while turns < 20 and not surrendered:
		sv = CTurn.resolve_turn(sv, [])
		turns += 1
		gar_seen.append(int(sv["regions"][co]["gar"]))
		surrendered = CState.owner(sv, co) == rome
	var ev := _events(sv, "captured")
	_check(surrendered and turns == supply + 100 / CData.SIEGE_STARVE_PCT and not ev.is_empty() and str(ev[-1].get("how", "")) == "surrendered"
		and CState.siege_at(sv, co).is_empty(),
		"Corsica holds %d turns of supplies, starves (garrison %s) and surrenders after %d turns" % [supply, str(gar_seen), turns])
	_check(_events(sv, "starving").size() > 0 or turns > supply, "starvation is reported")
	var t1 := CState.copy(s1)
	var t2 := CState.copy(s1)
	for k in 4:
		t1 = CTurn.resolve_turn(t1, [])
		t2 = CTurn.resolve_turn(CState.from_json(CState.to_json(t2)), [])
	_check(CState.state_hash(t1) == CState.state_hash(t2), "a siege survives save / load and resolves the same")
	# Migration 3 -> 4.
	var old := CState.copy(_new([rome]))
	old.erase("sieges")
	old["version"] = 3
	var mig := CState.from_json(CState.to_json(old))
	_check(int(mig["version"]) == 4 and (mig["sieges"] as Array).is_empty() and CState.state_hash(mig) == CState.state_hash(_new([rome])),
		"a format 3 state migrates to format 4 with no sieges (equal to a new campaign)")


## Samnium (Rome's) besieged by an Epirote army from Apulia, a Roman army
## inside and one in Latium.
func _besieged_samnium() -> Dictionary:
	var st := _new([_f("rome")])
	var ep := _f("epirus")
	var sa := _r("samnium")
	var e := {"id": CRules.new_army_id(st, ep), "f": ep, "r": _r("apulia"), "units": [{"t": "heavy", "n": 100}, {"t": "heavy", "n": 100},
		{"t": "spear", "n": 100}], "from": -1, "moved": 0, "busy": 0}
	st["factions"][ep]["next_army"] = int(st["factions"][ep]["next_army"]) + 1
	CRules._insert_army(st, e)
	var ea := CState.army(st, int(e["id"]))
	_check(CRules.execute_move(st, ea, sa, CData.MODE_SIEGE) == "" and not CState.siege_at(st, sa).is_empty(), "Epirus lays siege to Samnium")
	ea["moved"] = 0
	return st


func _siege_economy() -> void:
	var st := _besieged_samnium()
	var rome := _f("rome")
	var sa := _r("samnium")
	var inside: Dictionary = CState.armies_of(st, rome)[1]
	_check(int(inside["r"]) == sa and CRules.siege_role(st, inside) == 2, "Rome's army in Samnium is besieged (role 2)")
	_check(CRules.can_move(st, inside, _r("latium")) == "besieged", "it cannot leave except by a sally")
	_check(CRules.region_income(st, sa) == 0, "a besieged region yields no income")
	_check(CRules.recruit_check(st, rome, sa, "hastati") != "" and CRules.recruit_check(st, rome, sa, str(CState.roster_type(rome, "heavy", 1))) == "besieged",
		"and recruits nothing")
	_check(str(CRules.build_info(st, rome, sa, CData.MARKET).get("why", "")) == "besieged", "and builds nothing")
	st["regions"][sa]["build"] = [CData.FARM, 2, 2]
	var gar0 := int(st["regions"][sa]["gar"])
	st["regions"][sa]["gar"] = 50
	var growth0 := int(st["regions"][sa]["growth"])
	CRules.end_of_turn(st)
	_check(int(st["regions"][sa]["build"][2]) == 2, "its construction pauses (not cancelled)")
	_check(int(st["regions"][sa]["gar"]) == 50 and int(st["regions"][sa]["growth"]) == growth0, "its garrison does not recover, nor does it grow")
	st["regions"][sa]["gar"] = gar0
	var men0 := CState.men(inside)
	var ep_a: Dictionary = CRules.besiegers(st, sa)[0]
	var ep_men := CState.men(ep_a)
	CRules.end_of_turn(st)
	_check(CState.men(ep_a) == ep_men, "the besiegers do not replenish")
	var sg := CState.siege_at(st, sa)
	sg["supply"] = 0
	CRules.end_of_turn(st)
	_check(CState.men(inside) < men0 and int(st["regions"][sa]["gar"]) == gar0 - CData.SIEGE_STARVE_PCT,
		"out of supplies: the garrison and the army inside starve (%d -> %d men)" % [men0, CState.men(inside)])
	_check(CState.owner(st, sa) == rome, "no surrender while an army of the owner is inside")
	_check(CRules.can_move(st, ep_a, _r("apulia")) == "" and CRules.can_move(st, CState.armies_of(st, rome)[0], sa) == "",
		"the besiegers may leave; a Roman army may come to the relief")


func _siege_battles() -> void:
	var rome := _f("rome")
	var ep := _f("epirus")
	var sa := _r("samnium")
	# Sally.
	var st := _besieged_samnium()
	var inside: Dictionary = CState.armies_of(st, rome)[1]
	var ep_a: Dictionary = CRules.besiegers(st, sa)[0]
	var eid := int(ep_a["id"])
	var iid := int(inside["id"])
	_check(CRules.can_sally(st, rome, sa) == "", "Rome may sally from Samnium")
	var s1 := CTurn.resolve_turn(st, _sub(st, rome, [{"t": "sally", "r": sa}]))
	var b := CState.battle_at(s1, sa)
	_check(not b.is_empty() and str(b.get("kind", "")) == "sally" and int(b["settlement"]) == 0 and (b["att"] as Array).has(eid)
		and (b["def"] as Array).has(iid) and int(b["def_f"]) == rome,
		"sally: a field battle, the besiegers against the army inside (%s)" % str(b))
	if not b.is_empty():
		var built := CBattle.build(s1, b, rome)
		var gar_side := -1
		var gar_n := 0
		for m in built["map"]:
			if int(m["army"]) < 0:
				gar_side = int(m["side"])
				gar_n += 1
		_check(not (built["scenario"]["terrain"] as Dictionary).has("city") and gar_n > 0 and gar_side == 1
			and int(built["scenario"]["terrain"]["kind"]) == int(CData.REGIONS[sa]["terrain"]),
			"the sally is a field battle on the region's terrain with the garrison riding out on Rome's side (%d units)" % gar_n)
		var sim := BattleSim.new()
		sim.setup(built["scenario"], int(built["seed"]))
		_check(sim.n_units == (built["map"] as Array).size(), "the sally scenario sets up (%d units)" % sim.n_units)
		var won := CTurn.apply_battle(s1, int(b["id"]), {"winner": 1, "mode": "fought", "units": [], "garrison_pct": 70})
		_check(CState.siege_at(won, sa).is_empty() and int(CState.army(won, eid)["r"]) == _r("apulia")
			and int(CState.army(won, iid)["r"]) == sa and int(won["regions"][sa]["gar"]) == 70,
			"a won sally lifts the siege: the besiegers fall back to Apulia, the Romans stay home")
		var lost := CTurn.apply_battle(s1, int(b["id"]), {"winner": 0, "mode": "fought", "units": [], "garrison_pct": 40})
		_check(not CState.siege_at(lost, sa).is_empty() and int(CState.army(lost, iid)["r"]) == sa and int(lost["regions"][sa]["gar"]) == 40
			and CState.owner(lost, sa) == rome, "a lost sally: the siege goes on, the garrison takes its losses, the city holds")
		var drawn := CTurn.apply_battle(s1, int(b["id"]), {"winner": 1, "draw": 1, "mode": "auto", "units": [], "garrison_pct": 40})
		_check(not CState.siege_at(drawn, sa).is_empty(), "a drawn sally leaves the siege in place")
		var fo := CBattle.formula(CState.copy(s1), b)
		_check(fo.has("winner") and int(fo["garrison_pct"]) > 0, "the formula decides a sally (garrison left %d%%)" % int(fo["garrison_pct"]))
	# Relief: Rome's army in Latium marches in.
	var st2 := _besieged_samnium()
	var rel: Dictionary = CState.armies_of(st2, rome)[0]
	var rid := int(rel["id"])
	var r1 := CTurn.resolve_turn(st2, _sub(st2, rome, [{"t": "move", "army": rid, "to": sa}]))
	var rb := CState.battle_at(r1, sa)
	_check(not rb.is_empty() and str(rb.get("kind", "")) == "relief" and int(rb["settlement"]) == 0
		and (rb["def"] as Array).has(rid) and (rb["def"] as Array).has(iid) and (rb["att"] as Array).has(eid),
		"relief: a field battle, the relief and the army inside against the besiegers (%s)" % str(rb))
	if not rb.is_empty():
		var bb := CBattle.build(r1, rb, rome)
		var gs := -1
		for m in bb["map"]:
			if int(m["army"]) < 0:
				gs = int(m["side"])
		_check(gs == 1 and int(bb["sim_side"][1]) == 0, "the garrison rides out with the relief (Rome at the bottom)")
		var w := CTurn.apply_battle(r1, int(rb["id"]), {"winner": 1, "mode": "fought", "units": [], "garrison_pct": 90})
		_check(CState.siege_at(w, sa).is_empty() and int(CState.army(w, rid)["r"]) == sa and int(CState.army(w, eid)["r"]) == _r("apulia"),
			"a won relief lifts the siege; the relief army stands in Samnium")
		var l := CTurn.apply_battle(r1, int(rb["id"]), {"winner": 0, "mode": "fought", "units": [], "garrison_pct": 30})
		_check(not CState.siege_at(l, sa).is_empty() and int(CState.army(l, rid)["r"]) == _r("latium")
			and int(CState.army(l, iid)["r"]) == sa and int(l["regions"][sa]["gar"]) == 30,
			"a lost relief: the relief falls back to Latium, the siege goes on, the garrison's losses stand")
		# Nowhere to go: Latium and Campania are lost meanwhile.
		var n1 := CState.copy(r1)
		n1["regions"][_r("latium")]["owner"] = ep
		n1["regions"][_r("campania")]["owner"] = ep
		var nd := CTurn.apply_battle(n1, int(rb["id"]), {"winner": 0, "mode": "fought", "units": [], "garrison_pct": 30})
		_check(CState.army(nd, rid).is_empty() and _events(nd, "destroyed").size() == 1, "a beaten relief with nowhere to go is destroyed")
		# Besiegers with no friendly neighbour fall back to the nearest friendly region.
		var n2 := CState.copy(r1)
		n2["regions"][_r("apulia")]["owner"] = rome
		var nf := CTurn.apply_battle(n2, int(rb["id"]), {"winner": 1, "mode": "fought", "units": [], "garrison_pct": 90})
		var ea2 := CState.army(nf, eid)
		_check(not ea2.is_empty() and CState.owner(nf, int(ea2["r"])) == ep, "beaten besiegers far from home reach the nearest friendly region (%s)" % (
			CData.REGIONS[int(ea2["r"])]["name"] if not ea2.is_empty() else "destroyed"))
		var r2 := CTurn.resolve_turn(st2, _sub(st2, rome, [{"t": "move", "army": rid, "to": sa}]))
		_check(CState.state_hash(r1) == CState.state_hash(r2), "relief resolves deterministically")


func _odds() -> void:
	var st := _new([_f("rome")])
	var rome := _f("rome")
	var ap := _r("apulia")
	var defs := CState.armies_in(st, ap)
	var last := -1
	var last_loss := 1000
	var mono := true
	var last_band := -1
	for n in range(1, 25):
		var us: Array = []
		for k in n:
			us.append({"t": "heavy", "n": 100})
		var att := [{"id": 1, "f": rome, "r": ap, "units": us, "from": -1, "moved": 0, "busy": 0}]
		var o1 := CBattle.odds(st, att, defs, ap, true)
		if int(o1["win_pm"]) < last or int(o1["att_loss"]) > last_loss + 1 or int(o1["band"]) < last_band:
			mono = false
		last = int(o1["win_pm"])
		last_loss = int(o1["att_loss"])
		last_band = int(o1["band"])
	_check(mono and last > 850 and last_band == 4, "odds grow with the attackers' strength (to %d per mille, band %d)" % [last, last_band])
	# The odds of a battle are the formula's: same strengths, same chance. A
	# close battle: Rome's army in Samnium grows until the odds are about even.
	var a: Dictionary = CState.armies_of(st, rome)[1]
	var units: Array = a["units"]
	while CState.unit_count(a) < CData.ARMY_MAX and int(CBattle.odds(st, [a], defs, ap, true)["win_pm"]) < 450:
		units.append({"t": "heavy", "n": 100})
	var st2 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [{"t": "move", "army": int(a["id"]), "to": ap, "mode": CData.MODE_ASSAULT}])])
	var b := CState.battle_at(st2, ap)
	if b.is_empty():
		_check(false, "a battle for the odds")
		return
	var arm := CRules.battle_armies(st2, b)
	var od := CBattle.odds(st2, arm[0], arm[1], ap, true)
	var s := CBattle.side_strengths(st2, b)
	_check(int(od["win_pm"]) == CBattle.win_chance(s[0], s[1]) and int(od["att"]) == int(s[0]) and int(od["def"]) == int(s[1]),
		"odds() equals the formula's strengths and chance (%d per mille)" % int(od["win_pm"]))
	# Monte Carlo of the formula against the odds' expectation.
	var wins := 0
	var lost := [0, 0]
	var men := [0, 0]
	for sd in 2:
		for x in arm[sd]:
			men[sd] += CState.men(x)
	var runs := 600
	for k in runs:
		var c := CState.copy(st2)
		c["rng"] = 1000 + k * 7919
		var o := CBattle.formula(c, CState.battle(c, int(b["id"])))
		if int(o["winner"]) == 0:
			wins += 1
		for u in o["units"]:
			var sd := 0 if (b["att"] as Array).has(int(u["army"])) else 1
			lost[sd] += int(u["killed"]) + int(u["routed"]) * (100 - CData.ROUT_RETURN) / 100
	var pct := wins * 100 / runs
	var att_l: int = int(lost[0]) * 100 / maxi(int(men[0]) * runs, 1)
	var def_l: int = int(lost[1]) * 100 / maxi(int(men[1]) * runs, 1)
	_check(absi(pct - int(od["win"])) <= 6, "the formula wins %d%% of %d runs; odds say %d%%" % [pct, runs, int(od["win"])])
	_check(absi(att_l - int(od["att_loss"])) <= 4 and (men[1] == 0 or absi(def_l - int(od["def_loss"])) <= 4),
		"expected losses match the formula: attackers %d%% (odds %d%%), defenders %d%% (odds %d%%)" % [att_l, int(od["att_loss"]), def_l, int(od["def_loss"])])
	# A field battle: no walls, no ground, the garrison where it is told.
	var f0 := CBattle.strengths(st2, arm[0], arm[1], ap, false, 1)
	var s0 := CBattle.strengths(st2, arm[0], arm[1], ap, true, 1)
	_check(int(f0[1]) < int(s0[1]) and int(f0[0]) == int(s0[0]), "in the field the garrison has no walls and nobody the ground")


## Co-op: two allied players besiege together; both order the assault: one
## battle, no failed orders.
func _coop_siege() -> void:
	var rome := _f("rome")
	var gr := _f("greeks")
	var co := _r("corsica")
	var st := _new([rome, gr])
	CState.set_dip(st, rome, _f("epirus"), CState.PEACE)
	var a: Dictionary = CState.armies_of(st, rome)[0]
	a["r"] = _r("etruria")
	var g: Dictionary = CState.armies_of(st, gr)[0]
	g["r"] = _r("etruria")
	var s1 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [{"t": "move", "army": int(a["id"]), "to": co}]),
		CTurn.submission(st, gr, [{"t": "move", "army": int(g["id"]), "to": co}])])
	_check(CRules.besiegers(s1, co).size() == 2 and int(CState.siege_at(s1, co)["f"]) == rome, "allies besiege Corsica together")
	_check(CRules.can_assault(s1, gr, co) == "" and CRules.can_assault(s1, rome, co) == "", "either ally may order the assault")
	var s2 := CTurn.resolve_turn(s1, [CTurn.submission(s1, rome, [{"t": "assault", "r": co}]),
		CTurn.submission(s1, gr, [{"t": "assault", "r": co}])])
	var n := 0
	for b in s2["battles"]:
		if int(b["r"]) == co:
			n += 1
			_check((b["att"] as Array).size() == 2 and CRules.battle_humans(s2, b).size() == 2, "the battle holds both allies' armies")
	_check(n == 1 and _events(s2, "order_failed").is_empty(), "both order the assault: one battle, no failed order")
