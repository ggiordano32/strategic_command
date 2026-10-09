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
## Format 5 (free movement): path costs and Dijkstra ties, movement points
## by composition, the sea lane rule, rounds (armies meeting half-way),
## interception by field armies only (garrison stance and allies never
## block), raiding income, a siege start fought in the field first, support
## by range over land with its map edge, retreat along the path, multi-turn
## marches and cancel, migration 4 -> 5 and from format 1, determinism, a
## format 4 state ignoring the new orders. Format 6 (the continuous
## overworld): the nav grid (every region has cells, settlements on their
## region, each landmass connected, routes joined, ports on the coast),
## path search (deterministic, around enemy zones of control, into the
## target's), points and partial marches across turns, contact in rounds
## (converging and head-on: the lower id moves first and attacks), sieges
## by moving onto a city (and storming on arrival), sally and relief by
## moving onto a besieger, support by radius with the bearing, stances
## (forced march, fortify, raiding) and the raiders' income, migration
## 5 -> 6 and from the format 1 file, the step log, determinism; merging
## by marching onto an army (same turn, following it across turns, the cap,
## the army gone), the exchange order both ways (an army emptied is gone),
## the arrange order (a permutation of the army's units: validation, JSON
## numbers, the preview, a split after it, determinism, format 5 too),
## gifts to an allied human (taking refused, the event), recruiting into
## an army and raising a new one (slots shared, the cap, wrong / allied
## region and besieged refused, mustering refuses the march and keeps the
## stored destination, old-form orders muster their army too, one raised
## army that the end-of-turn gathering leaves apart that turn), recruits
## collecting in one army, the end-of-turn merge of idle armies in a city.
## Gifts between the players: a free city gift at resolution (garrison and
## buildings kept), a priced offer accepted / declined the next turn (the
## city and the money move together), the buyer's offer, refusals (an army
## of the giver in the city at acceptance, the treasury short), a money
## gift, the AI left out, determinism.
## Exits 0 on success, 1 on failure.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const UT := preload("res://sim/unit_types.gd")
const Saves := preload("res://game/campaign/saves.gd")
const CP := preload("res://campaign/cai_profile.gd")
const CAI := preload("res://campaign/cai.gd")

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
	_paths()
	_rounds()
	_interception()
	_raiding()
	_siege_start_field()
	_support_range()
	_persist()
	_format5()
	_end_conditions()
	# Format 6: the continuous overworld.
	_grid()
	_grid_paths()
	_grid_turns()
	_grid_contact()
	_grid_siege()
	_grid_sally_relief()
	_grid_siege_equipment()
	_grid_support()
	_grid_stances()
	_grid_raiding()
	_grid_migration()
	_grid_steps()
	_grid_determinism()
	_grid_merge()
	_grid_exchange()
	_grid_arrange()
	_grid_gift()
	_city_gifts()
	_grid_recruit_collect()
	_grid_recruit_army()
	_grid_auto_merge()
	_ammo_wagon()
	_beasts()
	_light_missile()
	_general()
	_war_dogs()
	_ai_skilled()
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


## A new campaign as format 5 (region hops): the tests below up to
## _format5 check the rules of formats 1-5, which online campaigns of those
## formats still play. Format 6 (the continuous overworld): _new6 and the
## tests from _grid on.
func _new(humans: Array = []) -> Dictionary:
	return CState.as_format(CState.new_campaign("test", 4242, humans), 5)


func _new6(humans: Array = [], sd: int = 4242) -> Dictionary:
	return CState.new_campaign("test", sd, humans)


## A copy of st as an older format would have it (format v: no free
## movement below 5, no sieges below 4, no builder data below 3).
func _downgrade(st: Dictionary, v: int) -> Dictionary:
	var c := CState.copy(st)
	if v < 5:
		for a in c["armies"]:
			for k in ["mp", "dest", "mode", "stance", "idle"]:
				(a as Dictionary).erase(k)
		for b in c["battles"]:
			(b as Dictionary).erase("edge")
	if v < 4:
		c.erase("sieges")
	if v < 3:
		for rs in c["regions"]:
			(rs as Dictionary).erase("built")
	c["version"] = v
	return c


## The owner's armies in region r withdraw inside the walls (version 5: so
## an attack on r is a settlement battle, not a field battle first).
func _inside(st: Dictionary, r: int) -> void:
	for a in CState.armies_in(st, r):
		if CState.friendly(st, int(a["f"]), CState.owner(st, r)):
			a["stance"] = CData.STANCE_GARRISON


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
	var st := _new6([0, 1])
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
			st = CState.from_json(CState.to_json(st), int(st["version"]))
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
	_check(CRules.can_move(_downgrade(st, 4), a, _r("apulia")) != "", "format 4: no move to a non-adjacent region")
	_check(CRules.can_move(st, a, _r("apulia")) == "", "format 5: a march to a region two away")
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
	_inside(st, _r("apulia"))
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
	var seeds_ok := int(nst["version"]) == 5 and int(_new6()["version"]) == CState.VERSION
	for r in 36:
		if int(nst["regions"][r].get("city_seed", -1)) != CState.default_city_seed(r):
			seeds_ok = false
	_check(seeds_ok, "a new campaign (as format 5) has a city seed per settlement")
	var distinct := {}
	for r in 36:
		distinct[CState.default_city_seed(r)] = true
	_check(distinct.size() == 36, "the 36 city seeds differ")
	var text := FileAccess.get_file_as_string("res://tests/data/campaign_v1.json")
	_check(text.length() > 100, "the format 1 campaign file is there")
	var raw: Dictionary = CState.normalise(JSON.parse_string(text))
	_check(int(raw["version"]) == 1 and not (raw["regions"][0] as Dictionary).has("city_seed"), "it is a real format 1 state")
	var mig := CState.from_json(text, 5)
	var ok := not mig.is_empty() and int(mig["version"]) == 5
	for r in 36:
		if mig.is_empty() or int(mig["regions"][r].get("city_seed", -1)) != CState.default_city_seed(r):
			ok = false
	_check(ok, "from_json migrates format 1 -> 5: every settlement gets its city seed")
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
	var mig3 := _downgrade(mig, 3)
	var r3 := CTurn.resolve_turn(mig3, [])
	var eq := true
	for k in ["turn", "factions", "armies", "dip", "battles", "rng"]:
		if str(r1[k]) != str(r3[k]):
			eq = false
	_check(eq, "the format 3 copy plays the same turn as the unmigrated one")
	_check(int(sv["state"]["version"]) == CState.VERSION and (sv["state"]["sieges"] as Array).is_empty(), "the full migration reaches format %d with no sieges" % CState.VERSION)
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
	var mig := CState.from_json(CState.to_json(v2), 5)
	var mok := not mig.is_empty() and int(mig["version"]) == 5
	for r in 36:
		if mig.is_empty() or not (mig["regions"][r] as Dictionary).has("built"):
			mok = false
	_check(mok and CState.state_hash(mig) == CState.state_hash(nst), "a format 2 state migrates to format 5 (equal to the new campaign)")
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
	var w3 := CState.from_json(CState.to_json(w2), 5)
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
	_inside(st, _r("apulia"))
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


# --------------------------------------------------------- free movement ---

func _army(st: Dictionary, f: int, key: String, units: Array) -> Dictionary:
	var id := CRules.new_army_id(st, f)
	st["factions"][f]["next_army"] = int(st["factions"][f]["next_army"]) + 1
	var us: Array = []
	for t in units:
		us.append({"t": t, "n": UT.size_of(UT.index_of(t))})
	CRules._insert_army(st, {"id": id, "f": f, "r": _r(key), "units": us, "from": -1, "moved": 0, "busy": 0})
	return CState.army(st, id)


## Movement points, path costs, Dijkstra ties, the sea lane rule.
func _paths() -> void:
	var st := _new([_f("rome")])
	var rome := _f("rome")
	_check(CState.moves_on(st) and CData.move_cost(_r("campania")) == 10 and CData.move_cost(_r("samnium")) == 15
		and CData.move_cost(_r("etruria")) == 20 and CData.move_cost(_r("apulia")) == 10,
		"entry costs: flat 10, ridge 15, hill with woods 45% 20, flat 10")
	var foot := _army(st, rome, "latium", ["heavy", "cav"])
	var cav := _army(st, rome, "latium", ["cav", "cav"])
	var art := _army(st, rome, "latium", ["heavy", "bolt"])
	_check(CState.max_mp(foot) == CData.MP_FOOT and CState.max_mp(cav) == CData.MP_CAV and CState.max_mp(art) == CData.MP_ART,
		"points by the slowest arm: foot %d, cavalry only %d, with artillery %d" % [CState.max_mp(foot), CState.max_mp(cav), CState.max_mp(art)])
	var rf := CRules.reach(st, foot)
	_check(int(rf["t"][_r("samnium")]) == 0 and int(rf["m"][_r("samnium")]) == 5 and int(rf["t"][_r("apulia")]) == 1,
		"foot from Latium: Samnium this turn (5 left), Apulia next turn: Italy in two turns")
	var rc := CRules.reach(st, cav)
	_check(int(rc["t"][_r("apulia")]) == 0 and CRules.path_of(rc, _r("apulia")) == [_r("samnium"), _r("apulia")],
		"cavalry from Latium reach Apulia in one turn by Samnium")
	var ra := CRules.reach(st, art)
	_check(int(ra["t"][_r("etruria")]) == 0 and int(ra["m"][_r("etruria")]) == 0,
		"an army with full points can always make one hop (artillery into wooded Etruria, 20 > 15)")
	# Sea lane: needs full points. Latium -> Sardinia (war with Carthage).
	CState.set_dip(st, rome, _f("carthage"), CState.WAR)
	rf = CRules.reach(st, foot)
	_check(int(rf["t"][_r("sardinia")]) == 0 and int(rf["m"][_r("sardinia")]) == 0, "with full points the sea lane to Sardinia is this turn, using them all")
	foot["mp"] = 5
	rf = CRules.reach(st, foot)
	_check(int(rf["t"][_r("sardinia")]) == 1, "with points spent the sea lane waits for next turn")
	# Ties by region index: Contestania -> Celtiberia by Edetania (14) or
	# Carpetania (17), both 10 + 15: Edetania, the lower index.
	var ib := _f("iberians")
	var ia := _army(st, ib, "contestania", ["light"])
	var ri := CRules.reach(st, ia)
	_check(CRules.path_of(ri, _r("celtiberia")) == [_r("edetania"), _r("celtiberia")] and int(ri["t"][_r("celtiberia")]) == 1,
		"equal paths: the one through the lower region index (Edetania): %s" % str(CRules.path_of(ri, _r("celtiberia"))))
	# Peace blocks passage; a multi-turn destination is a valid order.
	_check(CRules.can_move(st, CState.armies_of(st, rome)[0], _r("cisalpina")).begins_with("at peace"), "no march into a land at peace")
	var rv := CRules.reach(st, CState.armies_of(st, rome)[0])
	_check(not CRules.path_of(rv, _r("venetia")).has(_r("cisalpina")) and CRules.path_of(rv, _r("venetia")).has(_r("illyria")),
		"nor through it: to Venetia by Apulia and the sea to Illyria, not through Gaul")
	_check(CRules.move_targets(st, cav, true).has(_r("apulia")) and not CRules.move_targets(st, foot, true).has(_r("apulia"))
		and CRules.move_targets(st, CState.armies_of(st, rome)[0]).has(_r("apulia")), "move targets: all reachable, or this turn's")


## Rounds: two hostile armies marching at each other meet half-way.
func _rounds() -> void:
	var st := _new([_f("rome")])
	var rome := _f("rome")
	var ep := _f("epirus")
	var a: Dictionary = CState.armies_of(st, rome)[0]  # Latium
	var other: Dictionary = CState.armies_of(st, rome)[1]
	other["r"] = _r("etruria")  # out of Samnium
	var e := _army(st, ep, "apulia", ["pike", "pike", "cav"])
	CRules.execute_moves(st, [[int(e["id"]), _r("latium"), ep, CData.MODE_MARCH, 0], [int(a["id"]), _r("apulia"), rome, CData.MODE_MARCH, 0]])
	var bs: Array = st["battles"]
	_check(bs.size() == 1 and int(bs[0]["r"]) == _r("samnium") and str(bs[0]["kind"]) == "field" and int(bs[0]["settlement"]) == 0,
		"Rome to Apulia and Epirus to Latium meet in Samnium: one field battle there (%s)" % str(bs))
	if bs.size() == 1:
		_check((bs[0]["att"] as Array) == [int(e["id"])] and (bs[0]["def"] as Array) == [int(a["id"])] and int(bs[0]["def_f"]) == rome,
			"round 1: Rome (lower id) reached Samnium first, Epirus ran into it")
		_check(int(a["dest"]) == -1 and int(a["r"]) == _r("samnium") and int(CState.army(st, int(e["id"]))["r"]) == _r("samnium"),
			"both stand in Samnium; a march without persist forgets its destination")


## Interception: a field army stops an army entering; garrison stance and
## allies do not.
func _interception() -> void:
	var rome := _f("rome")
	var ep := _f("epirus")
	var st := _new([rome, _f("greeks")])
	var a: Dictionary = CState.armies_of(st, rome)[1]  # Samnium
	var e: Dictionary = CState.armies_in(st, _r("apulia"))[0]
	_inside(st, _r("apulia"))
	_check(CState.stance(e) == CData.STANCE_GARRISON, "the Epirote army in Tarentum is inside the walls")
	var s1 := CState.copy(st)
	CRules.execute_moves(s1, [[int(a["id"]), _r("apulia"), rome, CData.MODE_MARCH, 0]])
	_check((s1["battles"] as Array).is_empty() and int(CState.army(s1, int(a["id"]))["r"]) == _r("apulia")
		and CState.siege_at(s1, _r("apulia")).is_empty(), "an army inside the walls does not block: Rome marches into Apulia, no battle, no siege")
	var s2 := CState.copy(st)
	CState.army(s2, int(e["id"]))["stance"] = CData.STANCE_FIELD
	CRules.execute_moves(s2, [[int(a["id"]), _r("apulia"), rome, CData.MODE_SIEGE, 0]])
	var b := CState.battle_at(s2, _r("apulia"))
	_check(not b.is_empty() and str(b.get("kind", "")) == "field" and (b["att"] as Array).has(int(a["id"]))
		and (b["def"] as Array).has(int(e["id"])) and CState.siege_at(s2, _r("apulia")).is_empty(),
		"a field army intercepts: a field battle, no siege yet")
	_check(int(CState.army(s2, int(a["id"]))["dest"]) == _r("apulia") and int(CState.army(s2, int(a["id"]))["mode"]) == CData.MODE_SIEGE,
		"the army keeps its siege intent for after the battle")
	if not b.is_empty():
		var built := CBattle.build(s2, b, rome)
		var gar := 0
		for m in built["map"]:
			if int(m["army"]) < 0:
				gar += 1
		_check(gar == 0 and not (built["scenario"]["terrain"] as Dictionary).has("city")
			and int(built["scenario"]["terrain"]["kind"]) == int(CData.REGIONS[_r("apulia")]["terrain"])
			and int(built["scenario"]["terrain"]["forest"]) == int(CData.REGIONS[_r("apulia")]["forest"]),
			"the interception is a field battle on the region's ground and woods, without the garrison")
		var od := CBattle.battle_odds(s2, b)
		var fo := CBattle.formula(CState.copy(s2), b)
		_check(int(od["def"]) == CState.strength(CState.army(s2, int(e["id"]))) and int(fo["garrison_pct"]) == int(s2["regions"][_r("apulia")]["gar"]),
			"its odds and the formula leave the garrison out")
		# Won by Rome: Epirus falls back, the siege begins.
		var w := CTurn.apply_battle(s2, int(b["id"]), {"winner": 0, "mode": "fought", "units": [], "garrison_pct": 0})
		_check(int(CState.army(w, int(e["id"]))["r"]) != _r("apulia") and not CState.siege_at(w, _r("apulia")).is_empty()
			and int(w["regions"][_r("apulia")]["gar"]) == 100 and CState.owner(w, _r("apulia")) == ep,
			"won: the defenders fall back, the siege begins, the garrison is untouched and Tarentum not taken")
		# Lost: Rome retreats along its path (Samnium).
		var l := CTurn.apply_battle(s2, int(b["id"]), {"winner": 1, "mode": "fought", "units": [], "garrison_pct": 0})
		_check(int(CState.army(l, int(a["id"]))["r"]) == _r("samnium") and int(CState.army(l, int(e["id"]))["r"]) == _r("apulia")
			and int(CState.army(l, int(a["id"]))["dest"]) == -1, "lost: the attacker falls back the way it came")
	# Retreat along a longer path: cavalry from Latium caught in Apulia go back to Samnium.
	var s3 := CState.copy(st)
	CState.army(s3, int(e["id"]))["stance"] = CData.STANCE_FIELD
	var c := _army(s3, rome, "latium", ["cav", "cav"])
	CState.army(s3, int(a["id"]))["r"] = _r("campania")
	CRules.execute_moves(s3, [[int(c["id"]), _r("apulia"), rome, CData.MODE_MARCH, 0]])
	var b3 := CState.battle_at(s3, _r("apulia"))
	if not b3.is_empty():
		var l3 := CTurn.apply_battle(s3, int(b3["id"]), {"winner": 1, "mode": "fought", "units": [], "garrison_pct": 0})
		_check(int(CState.army(l3, int(c["id"]))["r"]) == _r("samnium"), "a beaten army retreats to the previous region on its path (Samnium, not Latium)")
	else:
		_check(false, "cavalry intercepted in Apulia")
	# Allies never block: a Greek (allied player) army standing in Campania.
	var s4 := CState.copy(st)
	var g: Dictionary = CState.armies_of(s4, _f("greeks"))[0]
	g["r"] = _r("campania")
	var la: Dictionary = CState.armies_of(s4, rome)[0]
	CRules.execute_moves(s4, [[int(la["id"]), _r("campania"), rome, CData.MODE_MARCH, 0]])
	_check((s4["battles"] as Array).is_empty() and int(la["r"]) == _r("campania"), "an allied army never blocks")
	# Through a besieged... no: peace. An army at peace cannot enter (as before).
	_check(CRules.can_enter(st, rome, _r("cisalpina")) != "", "armies at peace cannot enter")


## Raiding: an enemy army without a siege halves the region's income.
func _raiding() -> void:
	var st := _new([_f("rome")])
	var rome := _f("rome")
	var ap := _r("apulia")
	_inside(st, ap)
	var full := CRules.region_income(st, ap)
	var a: Dictionary = CState.armies_of(st, rome)[1]
	var s1 := CTurn.resolve_turn(st, _sub(st, rome, [{"t": "move", "army": int(a["id"]), "to": ap, "mode": CData.MODE_MARCH}]))
	var here := int(CState.army(s1, int(a["id"]))["r"]) == ap and CState.battle_at(s1, ap).is_empty()
	_check(here and CState.siege_at(s1, ap).is_empty() and CRules.raider(s1, ap) == rome,
		"mode march: Rome stands in Apulia without a siege, raiding")
	if here:
		_check(CRules.region_income(s1, ap) == full / 2, "the owner gets half its income (%d of %d)" % [CRules.region_income(s1, ap), full])
		var ep := _f("epirus")
		var inc := int(CRules.income(s1, ep)["regions"])
		var s2 := CState.copy(s1)
		CState.army(s2, int(a["id"]))["r"] = _r("samnium")
		_check(int(CRules.income(s2, ep)["regions"]) - inc == full - full / 2, "and gets it back when the raiders leave")
		# Laying siege from inside: an order.
		var pv := CTurn.preview(s1, rome, [{"t": "siege", "r": ap}])
		_check((pv["errors"] as Array).is_empty() and CRules.can_siege(s1, rome, ap) == "", "the siege order is valid from inside")
		var s3 := CState.copy(s1)
		for x in CState.armies_in(s3, ap):
			if int(x["f"]) == ep:
				x["stance"] = CData.STANCE_GARRISON
		var r3 := CTurn.resolve_turn(s3, _sub(s3, rome, [{"t": "siege", "r": ap}]))
		_check(not CState.siege_at(r3, ap).is_empty() or not CState.battle_at(r3, ap).is_empty(),
			"ordering the siege lays it (or fights the field armies first)")
		_check(CRules.region_income(r3, ap) == 0 or not CState.battle_at(r3, ap).is_empty(), "besieged: no income at all")


## A siege laid where enemy field armies stand: a field battle first (the
## garrison stays in), the siege only after it is won.
func _siege_start_field() -> void:
	var st := _new([_f("rome")])
	var rome := _f("rome")
	var ep := _f("epirus")
	var ap := _r("apulia")
	var a: Dictionary = CState.armies_of(st, rome)[1]
	a["r"] = ap
	for e in CState.armies_in(st, ap):
		if int(e["f"]) == ep:
			e["stance"] = CData.STANCE_FIELD
	_check(CRules.order_siege(st, rome, ap) == "", "Rome orders a siege of Tarentum with Epirus's army in the field there")
	var b := CState.battle_at(st, ap)
	_check(not b.is_empty() and str(b.get("kind", "")) == "field" and CState.siege_at(st, ap).is_empty()
		and int(a["dest"]) == ap and int(a["mode"]) == CData.MODE_SIEGE, "the field army is fought first; no siege yet")
	if not b.is_empty():
		var w := CTurn.apply_battle(st, int(b["id"]), {"winner": 0, "mode": "formula", "units": [], "garrison_pct": 0})
		_check(not CState.siege_at(w, ap).is_empty() and int(CState.army(w, int(a["id"]))["dest"]) == -1,
			"won: the siege begins afterwards")
		var l := CTurn.apply_battle(st, int(b["id"]), {"winner": 1, "mode": "formula", "units": [], "garrison_pct": 0})
		_check(CState.siege_at(l, ap).is_empty() and int(CState.army(l, int(a["id"]))["r"]) != ap, "lost: no siege, Rome falls back")
	# Garrison stance armies are inside: the siege starts at once and they are besieged.
	var s2 := _new([_f("rome")])
	var a2: Dictionary = CState.armies_of(s2, rome)[1]
	a2["r"] = ap
	_inside(s2, ap)
	_check(CRules.order_siege(s2, rome, ap) == "" and not CState.siege_at(s2, ap).is_empty() and (s2["battles"] as Array).is_empty()
		and CRules.besieged_armies(s2, ap).size() == 1, "armies inside the walls are besieged at once")


## Support by range: unmoved field armies within a turn's march over land
## join, with the map edge they come from; sea lanes never count.
func _support_range() -> void:
	var st := _new([_f("rome")])
	var rome := _f("rome")
	var ep := _f("epirus")
	var sa := _r("samnium")
	var defender: Dictionary = CState.armies_of(st, rome)[1]  # Samnium, field
	var lat: Dictionary = CState.armies_of(st, rome)[0]       # Latium, 15 points away
	var sar := _army(st, rome, "sardinia", ["heavy"])         # across a sea lane only
	var cap := _army(st, rome, "campania", ["heavy"])
	cap["stance"] = CData.STANCE_GARRISON                     # inside Capua's walls
	var far := _army(st, rome, "etruria", ["heavy"])          # Etruria -> Latium -> Samnium: 35
	var e := _army(st, ep, "apulia", ["pike", "pike", "cav"])
	CRules.execute_moves(st, [[int(e["id"]), sa, ep, CData.MODE_MARCH, 0]])
	var b := CState.battle_at(st, sa)
	_check(not b.is_empty() and (b["def"] as Array).has(int(defender["id"])), "Epirus runs into Rome's field army in Samnium")
	if b.is_empty():
		return
	CRules.add_reinforcements(st, b)
	var rf: Array = b["reinf"]
	_check(rf.has(int(lat["id"])) and not rf.has(int(sar["id"])) and not rf.has(int(cap["id"])) and not rf.has(int(far["id"])),
		"support by range: Latium's army joins; Sardinia (sea), Capua's garrison stance and Etruria (too far) do not (%s)" % str(rf))
	var edge := -2
	for pr in b.get("edge", []):
		if int(pr[0]) == int(lat["id"]):
			edge = int(pr[1])
	_check(edge == 6 and CData.sector(sa, _r("latium")) == 6 and CData.sector(sa, _r("apulia")) == 3,
		"the Latium army comes from the west (sector %d); Epirus from the south-east" % edge)
	var built := CBattle.build(st, b, rome)
	var sc: Dictionary = built["scenario"]
	var w := int(sc["width_m"])
	var h := int(sc["height_m"])
	var ok := true
	var n := 0
	for k in (built["map"] as Array).size():
		var m: Dictionary = built["map"][k]
		if int(m["army"]) != int(lat["id"]):
			continue
		n += 1
		var u: Dictionary = sc["units"][k]
		# Attackers (from the south-east) at the top: west is down and right.
		if int(u["y_m"]) < h - CBattle.EDGE_IN - 60 or int(u["x_m"]) <= w / 2:
			ok = false
	_check(n == CState.unit_count(lat) and ok, "the Latium army deploys on the map edge it comes from (bottom right, %d units, field %dx%d)" % [n, w, h])
	var sim := BattleSim.new()
	sim.setup(sc, int(built["seed"]))
	_check(sim.n_units == (built["map"] as Array).size(), "the scenario with an edge group sets up (%d units)" % sim.n_units)
	var b2 := CBattle.build(st, b, -1)
	_check(str(b2["scenario"]) == str(CBattle.build(st, b, -1)["scenario"]), "and is a pure function of the state")
	# A format 4 copy: land-adjacent reinforcement as before (Latium is next to Samnium; Campania too).
	var v4 := _downgrade(_new([rome]), 4)
	var d4: Dictionary = CState.armies_of(v4, rome)[1]
	var e4 := {"id": CRules.new_army_id(v4, ep), "f": ep, "r": _r("apulia"), "units": [{"t": "heavy", "n": 100}], "from": -1, "moved": 0, "busy": 0}
	CRules._insert_army(v4, e4)
	_check(CRules.execute_move(v4, CState.army(v4, int(e4["id"])), sa, CData.MODE_ASSAULT) == "", "format 4: Epirus attacks Samnium")
	var b4 := CState.battle_at(v4, sa)
	CRules.add_reinforcements(v4, b4)
	_check((b4["reinf"] as Array).has(int(CState.armies_of(v4, rome)[0]["id"])) and not b4.has("edge") and not d4.has("stance"),
		"format 4: the land neighbour reinforces, no edges, no stances")


## Multi-turn marches: the destination is kept and walked on; cancel.
func _persist() -> void:
	var rome := _f("rome")
	var st := _new([rome])
	var a: Dictionary = CState.armies_of(st, rome)[0]  # Latium
	var aid := int(a["id"])
	var co := _r("corsica")
	var s1 := CTurn.resolve_turn(st, _sub(st, rome, [{"t": "move", "army": aid, "to": co, "mode": CData.MODE_MARCH, "persist": 1}]))
	var a1 := CState.army(s1, aid)
	_check(int(a1["r"]) == _r("etruria") and int(a1["dest"]) == co and int(a1["mode"]) == CData.MODE_MARCH and int(a1["mp"]) == CState.max_mp(a1),
		"turn 1: Etruria (20 points), still marching to Corsica; points back at the end of the turn")
	var s2 := CTurn.resolve_turn(s1, [])
	var a2 := CState.army(s2, aid)
	_check(int(a2["r"]) == co and int(a2["dest"]) == -1, "turn 2: with no orders it crosses to Corsica and arrives")
	var c2 := CTurn.resolve_turn(s1, _sub(s1, rome, [{"t": "cancel_move", "army": aid}]))
	_check(int(CState.army(c2, aid)["r"]) == _r("etruria") and int(CState.army(c2, aid)["dest"]) == -1, "cancel_move: it stays in Etruria")
	var n1 := CTurn.resolve_turn(st, _sub(st, rome, [{"t": "move", "army": aid, "to": co, "mode": CData.MODE_MARCH}]))
	_check(int(CState.army(n1, aid)["r"]) == _r("etruria") and int(CState.army(n1, aid)["dest"]) == -1, "without persist the march ends where the points run out")
	var o2 := CTurn.resolve_turn(s1, _sub(s1, rome, [{"t": "move", "army": aid, "to": _r("latium"), "mode": CData.MODE_MARCH}]))
	_check(int(CState.army(o2, aid)["r"]) == _r("latium") and int(CState.army(o2, aid)["dest"]) == -1, "a new order replaces the stored march")
	# Siege shortcut over two turns: lays siege on arrival.
	var g1 := CTurn.resolve_turn(st, _sub(st, rome, [{"t": "move", "army": aid, "to": co, "mode": CData.MODE_SIEGE, "persist": 1}]))
	var g2 := CTurn.resolve_turn(g1, [])
	_check(not CState.siege_at(g2, co).is_empty() and int(CState.army(g2, aid)["r"]) == co, "a persisting siege march lays siege on arrival")
	_check(CState.state_hash(g2) == CState.state_hash(CTurn.resolve_turn(CState.from_json(CState.to_json(g1), 5), [])),
		"a stored march survives save / load and resolves the same")
	_check(CState.state_hash(s1) == CState.state_hash(CTurn.resolve_turn(st, _sub(st, rome, [{"t": "move", "army": aid, "to": co, "mode": CData.MODE_MARCH, "persist": 1}]))),
		"free movement resolves deterministically (%s)" % CState.hash_text(s1))


## Format 5: migration, older formats unchanged.
func _format5() -> void:
	var rome := _f("rome")
	var nst := _new([rome])
	var keys := true
	for a in nst["armies"]:
		for k in ["mp", "dest", "mode", "stance", "idle"]:
			if not (a as Dictionary).has(k):
				keys = false
	_check(int(nst["version"]) == 5 and keys, "a new campaign is format 5: every army has points, dest, mode, stance")
	var v4 := _downgrade(nst, 4)
	var mig := CState.from_json(CState.to_json(v4), 5)
	_check(not mig.is_empty() and CState.state_hash(mig) == CState.state_hash(nst), "a format 4 state migrates to format 5 (equal to a new campaign)")
	var v1 := CState.from_json(FileAccess.get_file_as_string("res://tests/data/campaign_v1.json"), 5)
	var ok := not v1.is_empty() and int(v1["version"]) == 5
	for a in v1.get("armies", []):
		if int(a.get("mp", -1)) != CState.max_mp(a) or int(a.get("stance", -1)) != CData.STANCE_FIELD or int(a.get("dest", 0)) != -1:
			ok = false
	_check(ok, "the format 1 save migrates to format 5 with full points and field stances")
	# A format 4 state: one hop a turn, the new orders refused.
	var a: Dictionary = CState.armies_of(v4, rome)[0]
	_check(CRules.apply_order(CState.copy(v4), rome, {"t": "stance", "a": int(a["id"]), "s": 1}) != ""
		and CRules.apply_order(CState.copy(v4), rome, {"t": "cancel_move", "army": int(a["id"])}) != ""
		and CRules.can_siege(v4, rome, _r("apulia")) != "", "format 4 refuses stance, cancel_move and siege orders")
	var r4 := CTurn.resolve_turn(v4, _sub(v4, rome, [{"t": "move", "army": int(a["id"]), "to": _r("apulia"), "persist": 1}]))
	var a4 := CState.army(r4, int(a["id"]))
	_check(int(r4["version"]) == 4 and int(a4["r"]) == _r("latium") and not a4.has("mp") and not a4.has("dest"),
		"format 4: a two-region move fails and no free movement keys appear")
	# Stance orders (format 5).
	var s := CState.copy(nst)
	var la: Dictionary = CState.armies_of(s, rome)[0]
	_check(CRules.apply_order(s, rome, {"t": "stance", "a": int(la["id"]), "s": 1}) == "" and CState.stance(la) == CData.STANCE_GARRISON,
		"stance: inside the walls of Roma")
	la["r"] = _r("apulia")
	la["stance"] = CData.STANCE_FIELD
	_check(CRules.apply_order(s, rome, {"t": "stance", "a": int(la["id"]), "s": 1}) == "not your settlement", "not inside an enemy's walls")


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
			and CState.siege_at(s5, co).is_empty() and _events(s5, "siege_lifted").filter(func(e): return int(e["r"]) == co).size() == 1,
			"a failed assault: the besiegers fall back where they came from and the siege is lifted")
	# Lifting by marching away: one leaves (the siege stays), then the last.
	var l1 := CTurn.resolve_turn(s2, _sub(s2, rome, [{"t": "move", "army": aid, "to": _r("etruria")}]))
	_check(not CState.siege_at(l1, co).is_empty() and CRules.besiegers(l1, co).size() == 1, "one army leaves: the siege goes on")
	var l2 := CTurn.resolve_turn(l1, _sub(l1, rome, [{"t": "move", "army": bid, "to": _r("etruria")}]))
	_check(CState.siege_at(l2, co).is_empty() and _events(l2, "siege_lifted").filter(func(e): return int(e["r"]) == co).size() == 1,
		"the last besieger leaves: the siege is lifted")
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
		t2 = CTurn.resolve_turn(CState.from_json(CState.to_json(t2), 5), [])
	_check(CState.state_hash(t1) == CState.state_hash(t2), "a siege survives save / load and resolves the same")
	# Migration 3 -> 4.
	var old := _downgrade(_new([rome]), 3)
	var mig := CState.from_json(CState.to_json(old), 5)
	_check(int(mig["version"]) == 5 and (mig["sieges"] as Array).is_empty() and CState.state_hash(mig) == CState.state_hash(_new([rome])),
		"a format 3 state migrates to format 5 with no sieges (equal to a new campaign)")


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
	_inside(st, ap)
	var defs := CState.armies_in(st, ap)
	var last := -1
	var last_loss := 1000
	var mono := true
	var last_band := -1
	for n in range(1, 31):  # (to 30: the defenders have their general since 2026-10-09)
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


# ------------------------------------------------- format 6: the overworld ---

const CGrid := preload("res://campaign/cgrid.gd")


## A format 6 test state with no armies: Rome (a player) at war with Epirus.
func _empty6() -> Dictionary:
	var st := _new6([_f("rome")])
	st["armies"] = []
	return st


## A new army of faction f on cell c.
func _put(st: Dictionary, f: int, c: int, units: Array) -> Dictionary:
	var id := CRules.new_army_id(st, f)
	st["factions"][f]["next_army"] = int(st["factions"][f]["next_army"]) + 1
	var us: Array = []
	for t in units:
		us.append({"t": t, "n": UT.size_of(UT.index_of(t))})
	var a := {"id": id, "f": f, "r": CGrid.region(c), "units": us, "from": -1, "moved": 0, "busy": 0}
	CState.place(a, c)
	CRules._insert_army(st, a)
	return CState.army(st, id)


## A row of n passable cells of region r (left to right), away from its
## settlement; [] if none.
func _row(r: int, n: int) -> Array:
	var site := CGrid.site(r)
	for c in CGrid.cells_of(r):
		var ok := true
		var out: Array = []
		for k in n:
			var d := CGrid.at(CGrid.cx(c) + k, CGrid.cy(c))
			if d < 0 or CGrid.region(d) != r or CGrid.cheb(d, site) < 2 or (k > 0 and CGrid.step_cost(out[-1], d) <= 0):
				ok = false
				break
			out.append(d)
		if ok:
			return out
	return []


func _move6(a: Dictionary, c: int, extra: Dictionary = {}) -> Dictionary:
	var o := {"t": "move", "army": int(a["id"]), "x": CGrid.cx(c), "y": CGrid.cy(c), "persist": 1}
	for k in extra:
		o[k] = extra[k]
	return o


func _grid() -> void:
	CGrid.ensure()
	var ok := true
	var site_ok := true
	for r in CData.region_count():
		if CGrid.cells_of(r).is_empty():
			ok = false
		if CGrid.region(CGrid.site(r)) != r or CGrid.region(CGrid.camp(r)) != r:
			site_ok = false
	_check(ok, "every region has cells on the grid (%d x %d, %d px)" % [CGrid.width(), CGrid.height(), CGrid.cell_px()])
	_check(site_ok, "every settlement and camp cell lies in its region")
	# Each landmass is one connected piece (steps only), and every land route joins.
	var comp := PackedInt32Array()
	comp.resize(CGrid.count())
	comp.fill(-1)
	var parts := 0
	for s in CGrid.count():
		if not CGrid.passable(s) or comp[s] >= 0:
			continue
		comp[s] = parts
		var q: Array[int] = [s]
		var qi := 0
		while qi < q.size():
			var u := q[qi]
			qi += 1
			for k in 8:
				var v := CGrid.at(CGrid.cx(u) + CGrid.DX[k], CGrid.cy(u) + CGrid.DY[k])
				if v >= 0 and comp[v] < 0 and CGrid.step_cost(u, v) > 0:
					comp[v] = parts
					q.append(v)
		parts += 1
	_check(parts == 5, "five land components, one per landmass (%d)" % parts)
	var routes := true
	for pair in CData.ROUTES:
		if comp[CGrid.site(CData.region_index(pair[0]))] != comp[CGrid.site(CData.region_index(pair[1]))]:
			routes = false
	_check(routes, "every land route's settlements are connected on the grid")
	var ports := true
	for r in CData.region_count():
		var pc := CGrid.port(r)
		if CData.is_port(r) != (pc >= 0) or (pc >= 0 and (CGrid.region(pc) != r or CGrid.links(pc).is_empty())):
			ports = false
	_check(ports, "ports: a coastal cell of the region with its sea lanes")
	_check(CGrid.step_cost(CGrid.site(_r("bruttium")), CGrid.site(_r("sicilia_or"))) == 0
		and CGrid.region(CGrid.site(_r("sicilia_or"))) == _r("sicilia_or"), "Sicily is not joined to Italy by land")


func _grid_paths() -> void:
	var st := _empty6()
	var rome := _f("rome")
	var foot := _put(st, rome, CState.field_cell(_r("latium")), ["heavy", "heavy", "spear"])
	var cav := _put(st, rome, CState.field_cell(_r("latium")), ["cav", "cav"])
	var art := _put(st, rome, CState.field_cell(_r("latium")), ["heavy", "bolt"])
	_check(CState.max_mp6(foot) == CData.MP6_FOOT and CState.max_mp6(cav) == CData.MP6_CAV and CState.max_mp6(art) == CData.MP6_ART,
		"points by the slowest arm (%d, %d, %d)" % [CState.max_mp6(foot), CState.max_mp6(cav), CState.max_mp6(art)])
	var tar := CGrid.site(_r("apulia"))
	var pf := CRules.plan_path(st, foot, tar)
	var pc := CRules.plan_path(st, cav, tar)
	_check(not pf.has("why") and int(pf["t"][-1]) == 1 and str(pf["aim"]["kind"]) == "siege",
		"foot from Latium reaches Tarentum's walls next turn (%d cells): Italy in two turns" % (pf.get("path", []) as Array).size())
	_check(not pc.has("why") and int(pc["t"][-1]) == 0, "cavalry gets there this turn")
	_check(CGrid.cheb(int(pf["path"][-1]), tar) == 1, "the march ends next to the city (its ring), not in it")
	var p2 := CRules.plan_path(st, foot, tar)
	_check(str(p2["path"]) == str(pf["path"]), "the path search is deterministic")
	# An enemy army across the way: the path goes round its zone of control,
	# unless it is the target.
	var row := _row(_r("lusitania"), 11)
	_check(row.size() == 11, "a row of 11 cells in Lusitania (independent)")
	if row.size() < 11:
		return
	var st2 := _empty6()
	var a := _put(st2, rome, row[0], ["heavy", "heavy"])
	var e := _put(st2, _f("epirus"), row[5], ["spear", "spear"])
	var pa := CRules.plan_path(st2, a, row[10])
	var clear := not pa.has("why")
	if clear:
		for c in pa["path"]:
			if CGrid.within(CState.cell(e), int(c), CRules.zone_r(st2, e)):
				clear = false
	_check(clear, "a march past an enemy army keeps out of its zone of control (%d cells)" % (pa.get("path", []) as Array).size())
	var pt := CRules.plan_path(st2, a, CState.cell(e), int(e["id"]))
	_check(not pt.has("why") and str(pt["aim"]["kind"]) == "attack" and CGrid.cheb(int(pt["path"][-1]), CState.cell(e)) == 1,
		"a march on the enemy army goes straight at it and ends next to it")
	_check(CRules._can_move6(st2, a, row[4]) != "", "a cell inside an enemy's zone is not a destination: " + CRules._can_move6(st2, a, row[4]))


func _grid_turns() -> void:
	var st := _empty6()
	var rome := _f("rome")
	var foot := _put(st, rome, CState.field_cell(_r("latium")), ["heavy", "heavy", "spear"])
	var id := int(foot["id"])
	var tar := CGrid.site(_r("apulia"))
	var s1 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [_move6(foot, tar)])])
	var a1 := CState.army(s1, id)
	_check(CGrid.cheb(CState.cell(a1), tar) > 1 and int(a1["dest_x"]) == CGrid.cx(tar) and int(a1["mp"]) == CState.max_mp6(a1),
		"after one turn the march is under way: destination kept, points back to full")
	var s2 := CTurn.resolve_turn(s1, [CTurn.submission(s1, rome, [])])
	var a2 := CState.army(s2, id)
	_check(CGrid.cheb(CState.cell(a2), tar) == 1 and not CState.siege_at(s2, _r("apulia")).is_empty() and int(a2["dest_x"]) == -1,
		"the second turn it arrives without a new order and lays siege to Tarentum")
	var s3 := CTurn.resolve_turn(s1, [CTurn.submission(s1, rome, [{"t": "cancel_move", "army": id}])])
	_check(CState.cell(CState.army(s3, id)) == CState.cell(a1) and int(CState.army(s3, id)["dest_x"]) == -1, "cancel_move stops it")
	# Sea lanes: a full turn's points at the port, landing at the other port.
	var st4 := _empty6()
	var b := _put(st4, rome, CGrid.port(_r("apulia")), ["heavy"])
	st4["regions"][_r("apulia")]["owner"] = rome
	var land := CGrid.port(_r("epirus"))
	var pb := CRules.plan_path(st4, b, CGrid.camp(_r("epirus")))
	_check(not pb.has("why") and (pb["path"] as Array).has(land) and int(pb["t"][(pb["path"] as Array).find(land)]) == 0
		and int(pb["m"][(pb["path"] as Array).find(land)]) == 0, "from Tarentum's port across the lane to Epirus: it lands this turn with no points left")


func _grid_contact() -> void:
	var row := _row(_r("lusitania"), 11)
	if row.size() < 11:
		return
	var rome := _f("rome")
	var ep := _f("epirus")
	# Converging: Rome's army attacks Epirus's army, which marches west past it.
	var st := _empty6()
	var a := _put(st, rome, row[0], ["heavy", "heavy", "heavy"])
	var e := _put(st, ep, row[10], ["spear", "spear"])
	# Epirus is AI: give it the march through the rules directly.
	var s1 := CState.copy(st)
	CRules.execute_moves6(s1, [[int(a["id"]), CState.cell(e), rome, CData.MODE_SIEGE, 1, int(e["id"])],
		[int(e["id"]), row[0], ep, CData.MODE_SIEGE, 0, -1]])
	var b: Dictionary = s1["battles"][0] if not (s1["battles"] as Array).is_empty() else {}
	_check(not b.is_empty() and (b["att"] as Array).has(int(a["id"])) and (b["def"] as Array).has(int(e["id"]))
		and str(b.get("kind", "")) == "field", "converging: the army that attacks is the attacker of the field battle")
	if not b.is_empty():
		var bc := CGrid.at(int(b["x"]), int(b["y"]))
		_check(bc == CState.cell(CState.army(s1, int(e["id"]))) and CGrid.cheb(CState.cell(CState.army(s1, int(a["id"]))), bc) == 1,
			"the battle is on the defender's cell, the attacker next to it")
		_check(int(b["r"]) == _r("lusitania") and CGrid.region(bc) == int(b["r"]), "the battle's region is its cell's")
	# The marching Epirotes did not walk into Rome's zone (they were not
	# attacking): they stopped at its edge or were caught.
	var ea := CState.army(s1, int(e["id"]))
	_check(not ea.is_empty(), "the defender is there")
	# Head-on: both target each other; the lower id moves first and attacks.
	var st2 := _empty6()
	var a2 := _put(st2, rome, row[0], ["heavy", "heavy"])
	var e2 := _put(st2, ep, row[10], ["spear", "spear"])
	var mv := [[int(a2["id"]), CState.cell(e2), rome, 0, 0, int(e2["id"])], [int(e2["id"]), CState.cell(a2), ep, 0, 0, int(a2["id"])]]
	var h1 := CState.copy(st2)
	CRules.execute_moves6(h1, mv)
	var h2 := CState.copy(st2)
	CRules.execute_moves6(h2, mv)
	var hb: Dictionary = h1["battles"][0] if not (h1["battles"] as Array).is_empty() else {}
	var lower := mini(int(a2["id"]), int(e2["id"]))
	_check(not hb.is_empty() and (hb["att"] as Array).has(lower), "head-on: one battle, the lower army id (moving first in each round) attacks")
	_check(CState.state_hash(h1) == CState.state_hash(h2), "head-on contact is deterministic")
	var meet := CGrid.cx(CGrid.at(int(hb.get("x", 0)), int(hb.get("y", 0))))
	_check(not hb.is_empty() and meet > CGrid.cx(row[0]) and meet < CGrid.cx(row[10]), "they meet between their starting cells (x %d)" % meet)
	# Zones: a march that is not an attack stops at the edge of an enemy
	# zone that moves into its way (its path was planned round the zones as
	# the phase began).
	var n3 := CGrid.at(CGrid.cx(row[3]), CGrid.cy(row[3]) - 3)
	if CGrid.passable(n3) and CGrid.region(n3) == _r("lusitania"):
		var st3 := _empty6()
		var a3 := _put(st3, rome, n3, ["heavy"])
		var e3 := _put(st3, ep, row[10], ["spear"])
		CRules.execute_moves6(st3, [[int(a3["id"]), row[3], rome, 0, 0, -1], [int(e3["id"]), row[0], ep, 0, 1, -1]])
		var e4 := CState.army(st3, int(e3["id"]))
		_check((st3["battles"] as Array).is_empty() and CState.cell(e4) == row[6] and int(e4["dest_x"]) == CGrid.cx(row[0]),
			"a march (no attack) stops at the edge of an enemy zone that moved into its way; no battle, it keeps its destination")
	else:
		_check(false, "a cell three north of the row for the zone test")


func _grid_siege() -> void:
	var rome := _f("rome")
	var st := _empty6()
	var ap := _r("apulia")
	var site := CGrid.site(ap)
	var start := -1
	for c in CGrid.disc(site, 4):
		if CGrid.region(c) == ap and CGrid.cheb(c, site) == 4 and CGrid.passable(c):
			start = c
			break
	var a := _put(st, rome, start, ["heavy", "heavy", "heavy", "spear"])
	var s1 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [_move6(a, site)])])
	var a1 := CState.army(s1, int(a["id"]))
	_check(not CState.siege_at(s1, ap).is_empty() and CGrid.cheb(CState.cell(a1), site) == 1 and CRules.siege_role(s1, a1) == 1,
		"moving onto Tarentum lays siege: the army stops on the ring and besieges it")
	_check((s1["battles"] as Array).is_empty(), "no battle the turn the siege is laid")
	var s2 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [_move6(a, site, {"mode": CData.MODE_ASSAULT})])])
	var b := CState.battle_at(s2, ap)
	_check(not b.is_empty() and int(b["settlement"]) == 1 and (b["att"] as Array).has(int(a["id"])) and CGrid.at(int(b["x"]), int(b["y"])) == site,
		"with mode assault it storms the city on arrival (a settlement battle at the city's cell)")
	# Siege panel orders: assault from the ring; withdraw by marching away.
	var s3 := CTurn.resolve_turn(s1, [CTurn.submission(s1, rome, [{"t": "assault", "r": ap}])])
	_check(str(CState.battle_at(s3, ap).get("kind", "")) == "assault", "the besieger's Assault order storms it")
	var away := CGrid.at(CGrid.cx(start), CGrid.cy(start))
	var s4 := CTurn.resolve_turn(s1, [CTurn.submission(s1, rome, [_move6(a1, away)])])
	_check(CState.siege_at(s4, ap).is_empty() and (_events(s4, "siege_lifted") as Array).size() == 1, "marching away (Withdraw) lifts the siege")
	# Out of supplies, the besiegers lose men too.
	var s5 := CState.copy(s1)
	s5["sieges"][0]["supply"] = 0
	var men0 := CState.men(CState.army(s5, int(a["id"])))
	CRules.end_of_turn(s5)
	var men1 := CState.men(CState.army(s5, int(a["id"])))
	_check(men1 < men0 and men1 >= men0 * (100 - CData.SIEGE_BESIEGER_PCT - 1) / 100 - 4,
		"besiegers lose about %d%% a turn once the city starves (%d -> %d)" % [CData.SIEGE_BESIEGER_PCT, men0, men1])


func _grid_sally_relief() -> void:
	var rome := _f("rome")
	var ep := _f("epirus")
	var sa := _r("samnium")
	var site := CGrid.site(sa)
	var st := _empty6()
	var inside := _put(st, rome, site, ["heavy", "heavy", "heavy"])
	var ring := CState.ring_cell(sa, 4)
	var e := _put(st, ep, ring, ["spear", "spear"])
	CRules.start_siege(st, sa, e, _r("apulia"))
	_check(CRules.siege_role(st, inside) == 2 and CRules.siege_role(st, e) == 1 and CRules.besieged_armies(st, sa).size() == 1,
		"an army on its settlement's cell is inside the besieged walls")
	_check(CRules._can_move6(st, inside, CGrid.camp(_r("latium"))) == "besieged", "the besieged cannot march off")
	var s1 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [_move6(inside, CState.cell(e), {"tgt": int(e["id"])})])])
	var b := CState.battle_at(s1, sa)
	_check(str(b.get("kind", "")) == "sally" and (b["def"] as Array).has(int(inside["id"])) and (b["att"] as Array).has(int(e["id"])),
		"an army inside moving onto a besieger rides out: a sally (the besiegers attack in the record)")
	# Relief: an army outside marches on its own besieged city.
	var st2 := CState.copy(st)
	st2["armies"].erase(CState.army(st2, int(inside["id"])))
	var rel := _put(st2, rome, CState.field_cell(_r("latium")), ["heavy", "heavy", "heavy", "cav"])
	var s2 := CTurn.resolve_turn(st2, [CTurn.submission(st2, rome, [_move6(rel, site)])])
	var b2 := CState.battle_at(s2, sa)
	_check(str(b2.get("kind", "")) == "relief" and (b2["def"] as Array).has(int(rel["id"])) and int(b2["settlement"]) == 0,
		"an army marching on its besieged city runs into the besiegers: a relief, a field battle")
	if not b2.is_empty():
		var built := CBattle.build(s2, b2, rome)
		var gar := false
		for m in built["map"]:
			if int(m["army"]) < 0:
				gar = true
		_check(gar, "the garrison rides out with the relief")


## Siege equipment by siege length (docs/CAMPAIGN.md "Siege equipment"):
## an assault on arrival brings nothing, after a turn of siege ladders for
## the foot, after two a ram; derived from the siege entry (no state of its
## own). The battle time limit setting reaches the scenario.
func _grid_siege_equipment() -> void:
	var rome := _f("rome")
	var ep := _f("epirus")
	var ap := _r("apulia")
	var st := _empty6()
	st["regions"][ap]["owner"] = rome
	var e := _put(st, ep, CState.ring_cell(ap, 4), ["heavy", "light", "archer", "cav"])
	CRules.start_siege(st, ap, e, _r("bruttium"))
	var b := CRules.start_siege_battle(st, ap, "assault")
	_check(not b.is_empty() and CBattle.siege_equipment(st, b).is_empty() and CBattle.siege_turns(st, ap) == 0,
		"an assault on arrival brings neither ladders nor a ram")
	var h0 := CState.state_hash(st)
	var sg := CState.siege_at(st, ap)
	var t0 := int(sg["turn"])
	sg["turn"] = t0 - 1
	var eq1 := CBattle.siege_equipment(st, b)
	_check(int(eq1.get("ladders", 0)) == 2 and not eq1.has("ram"), "after a turn of siege: two sets of ladders")
	sg["turn"] = t0 - 2
	var eq2 := CBattle.siege_equipment(st, b)
	_check(int(eq2.get("ladders", 0)) == 3 and int(eq2.get("ram", 0)) == 1, "after two turns: three sets of ladders and a ram")
	_check(CBattle.equipment_text(st, ap).contains("ram"), "the siege panel line names the ram")
	# Siege towers (4f.1): walls 2-3 only, one after three turns, two after four.
	var slots0: Array = (st["regions"][ap]["slots"] as Array).duplicate(true)
	var tw := {}
	for wl in [1, 2, 3]:
		_set_walls(st, ap, wl)
		for n in [2, 3, 4, 6]:
			sg["turn"] = t0 - n
			tw["%d/%d" % [wl, n]] = int(CBattle.siege_equipment(st, b).get("towers", 0))
	_check(str(tw) == str({"1/2": 0, "1/3": 0, "1/4": 0, "1/6": 0, "2/2": 0, "2/3": 1, "2/4": 2, "2/6": 2,
		"3/2": 0, "3/3": 1, "3/4": 2, "3/6": 2}), "siege towers by walls / siege turns: %s" % str(tw))
	_set_walls(st, ap, 2)
	sg["turn"] = t0 - 2
	_check(CBattle.equipment_text(st, ap).contains("siege tower next turn"), "the siege panel line: " + CBattle.equipment_text(st, ap))
	sg["turn"] = t0 - 3
	var tb := CBattle.build(st, b, -1)
	var n_tw := 0
	for eq_e in (tb["scenario"].get("equip", []) as Array):
		if int(eq_e[0]) == BattleSim.EQ_TOWER:
			n_tw += 1
	_check(n_tw == 1 and CBattle.equipment_text(st, ap).contains("a siege tower"),
		"after three turns at walls 2: a siege tower on the ground (%d); %s" % [n_tw, CBattle.equipment_text(st, ap)])
	st["regions"][ap]["slots"] = slots0
	sg["turn"] = t0 - 2
	var built := CBattle.build(st, b, -1)
	var lad := 0
	var ram := 0
	for eq_e in (built["scenario"].get("equip", []) as Array):
		if int(eq_e[0]) == 1:
			lad += 1
		elif int(eq_e[0]) == 2:
			ram += 1
	_check(lad == 3 and ram == 1 and (built["map"] as Array).size() == (built["scenario"]["units"] as Array).size(),
		"the assault's scenario: %d sets of ladders and %d ram on the ground (objects, not units), the result map unchanged" % [lad, ram])
	_check(not built["scenario"].has("time_limit"), "no time limit setting: the sim's 15 minutes")
	st["settings"]["time_limit"] = 1800
	_check(int(CBattle.build(st, b, -1)["scenario"].get("time_limit", 0)) == 1800, "the battle time setting reaches the scenario")
	sg["turn"] = t0
	st["settings"].erase("time_limit")
	_check(CState.state_hash(st) == h0, "deriving the equipment changes no state")
	var nc := CState.new_campaign("t", 7, [rome], {"time_limit": 900})
	var nc2 := CState.new_campaign("t", 7, [rome], {"time_limit": 2700})
	_check(not (nc["settings"] as Dictionary).has("time_limit") and int(nc2["settings"]["time_limit"]) == 2700,
		"time_limit is stored only when longer than 15 minutes")


## Region r's walls set to level wl (a test helper: its walls slot).
func _set_walls(st: Dictionary, r: int, wl: int) -> void:
	for sl in st["regions"][r]["slots"]:
		if int(sl[0]) == CData.WALLS:
			sl[1] = wl
			return
	(st["regions"][r]["slots"] as Array).append([CData.WALLS, wl])


func _grid_support() -> void:
	var row := _row(_r("lusitania"), 11)
	if row.size() < 11:
		return
	var rome := _f("rome")
	var ep := _f("epirus")
	var st := _empty6()
	var a := _put(st, rome, row[0], ["heavy", "heavy"])
	var e := _put(st, ep, row[3], ["spear", "spear"])
	var near := _put(st, rome, CGrid.at(CGrid.cx(row[3]), CGrid.cy(row[3]) - 3), ["heavy"]) if CGrid.passable(CGrid.at(CGrid.cx(row[3]), CGrid.cy(row[3]) - 3)) else {}
	var far := _put(st, rome, row[10], ["heavy"])
	var efar := _put(st, ep, row[7], ["javelin"])
	CRules.execute_moves6(st, [[int(a["id"]), CState.cell(e), rome, 0, 0, int(e["id"])]])
	var b: Dictionary = st["battles"][0] if not (st["battles"] as Array).is_empty() else {}
	_check(not b.is_empty(), "the field battle starts")
	if b.is_empty():
		return
	CRules.add_reinforcements(st, b)
	var bc := CGrid.at(int(b["x"]), int(b["y"]))
	var reinf: Array = b["reinf"]
	_check(not near.is_empty() and reinf.has(int(near["id"])), "a friendly army %d cells away supports it" % (CGrid.cheb(bc, CState.cell(near)) if not near.is_empty() else -1))
	_check(reinf.has(int(efar["id"])), "an enemy army 4 cells away supports its side")
	_check(not reinf.has(int(far["id"])), "one %d cells away does not (support radius %d)" % [CGrid.cheb(bc, CState.cell(far)), CData.SUPPORT])
	var edge := -2
	for pr in b["edge"]:
		if int(pr[0]) == int(near.get("id", -1)):
			edge = int(pr[1])
	_check(edge == CGrid.sector(bc, CState.cell(near)) and edge == 0, "its map edge is its bearing from the battle (north: %d)" % edge)
	var built := CBattle.build(st, b, rome)
	_check(int(built["scenario"]["height_m"]) > 560, "the field grows on the reinforcements' edge")
	# Fortified: support + 2.
	var st2 := _empty6()
	var a2 := _put(st2, rome, row[0], ["heavy", "heavy"])
	var e2 := _put(st2, ep, row[3], ["spear", "spear"])
	var f2 := _put(st2, rome, row[9], ["heavy"])
	f2["stance"] = CData.ST_FORTIFY
	CRules.execute_moves6(st2, [[int(a2["id"]), CState.cell(e2), rome, 0, 0, int(e2["id"])]])
	CRules.add_reinforcements(st2, st2["battles"][0])
	_check((st2["battles"][0]["reinf"] as Array).has(int(f2["id"])), "a fortified army supports from 6 cells")


func _grid_stances() -> void:
	var rome := _f("rome")
	var ep := _f("epirus")
	var row := _row(_r("lusitania"), 11)
	if row.size() < 11:
		return
	var st := _empty6()
	var a := _put(st, rome, row[0], ["heavy", "heavy"])
	var e := _put(st, ep, row[8], ["spear"])
	var full := CState.max_mp6(a)
	_check(CRules.apply_order(st, rome, {"t": "stance", "a": int(a["id"]), "s": CData.ST_FORCED}) == "" and int(a["mp"]) == full * 3 / 2,
		"forced march: half as many points again (%d)" % int(a["mp"]))
	_check(CRules.zone_r(st, a) == 0, "an army on a forced march has no zone of control")
	_check(CRules._can_move6(st, a, CState.cell(e), int(e["id"])).begins_with("on a forced march"), "an army on a forced march cannot attack")
	var od1 := CBattle.odds(st, [e], [a], int(a["r"]), false, -1)
	a["stance"] = CData.ST_DEFAULT
	var od0 := CBattle.odds(st, [e], [a], int(a["r"]), false, -1)
	_check(int(od1["win"]) > int(od0["win"]), "an army caught on a forced march fights worse (%d%% vs %d%% against it)" % [int(od1["win"]), int(od0["win"])])
	# Caught on a forced march: its units start shaken in the battle.
	a["stance"] = CData.ST_FORCED
	CRules.execute_moves6(st, [[int(e["id"]), CState.cell(a), ep, 0, 0, int(a["id"])]])
	var b: Dictionary = st["battles"][0] if not (st["battles"] as Array).is_empty() else {}
	var shaken := false
	if not b.is_empty():
		for u in CBattle.build(st, b, rome)["scenario"]["units"]:
			if int(u.get("morale_pct", 100)) == CData.FORCED_MORALE_PCT:
				shaken = true
	_check(shaken, "an army caught on a forced march starts the battle with %d%% morale" % CData.FORCED_MORALE_PCT)
	# Fortify: no moves, a wider zone, the defender's bonus.
	var st2 := _empty6()
	var f2 := _put(st2, rome, row[0], ["heavy", "heavy"])
	var e2 := _put(st2, ep, row[8], ["heavy", "heavy"])
	var o0 := CBattle.odds(st2, [e2], [f2], int(f2["r"]), false, -1)
	_check(CRules.apply_order(st2, rome, {"t": "stance", "a": int(f2["id"]), "s": CData.ST_FORTIFY}) == "", "fortify")
	_check(CRules._can_move6(st2, f2, row[3]) == "fortified" and CRules.zone_r(st2, f2) == CData.ZOC + 1, "a fortified army cannot move; its zone is one wider")
	var o1 := CBattle.odds(st2, [e2], [f2], int(f2["r"]), false, -1)
	_check(int(o1["win"]) < int(o0["win"]), "attacking a fortified army is harder (%d%% vs %d%%)" % [int(o1["win"]), int(o0["win"])])
	f2["moved"] = 1
	f2["stance"] = CData.ST_DEFAULT
	_check(CRules.apply_order(st2, rome, {"t": "stance", "a": int(f2["id"]), "s": CData.ST_FORTIFY}) != "", "an army that moved this turn cannot fortify")
	# Raiding: fewer points.
	var r3 := _put(st2, rome, row[5], ["heavy"])
	_check(CRules.apply_order(st2, rome, {"t": "stance", "a": int(r3["id"]), "s": CData.ST_RAID}) == "" and int(r3["mp"]) == CState.max_mp6({"units": r3["units"]}) * CData.RAID_MP_PCT / 100,
		"raiding: %d%% points" % CData.RAID_MP_PCT)


func _grid_raiding() -> void:
	var rome := _f("rome")
	var st := _empty6()
	var ep := _f("epirus")
	var ap := _r("apulia")
	var inc0 := CRules.income(st, ep)
	var mine0 := CRules.income(st, rome)
	var base := CRules.region_income(st, ap)
	var a := _put(st, rome, CGrid.camp(ap), ["heavy", "heavy"])
	_check(CRules.raider(st, ap) == -1, "an army in enemy land in the default stance does not raid")
	a["stance"] = CData.ST_RAID
	_check(CRules.raider(st, ap) == rome and CRules.region_income(st, ap) == base - base * CData.RAID_PCT / 100,
		"in the raiding stance it takes %d%% of Apulia's income" % CData.RAID_PCT)
	var inc1 := CRules.income(st, ep)
	var mine1 := CRules.income(st, rome)
	_check(int(mine1["raid"]) == base * CData.RAID_PCT / 100 and int(mine1["total"]) - int(mine0["total"]) == int(mine1["raid"]),
		"the raider's realm gains it (%d)" % int(mine1["raid"]))
	_check(int(inc1["regions"]) < int(inc0["regions"]), "the owner's income falls (%d -> %d)" % [int(inc0["regions"]), int(inc1["regions"])])
	var s1 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [])])
	_check(int(s1["factions"][rome]["income"]) == int(mine1["total"]), "the end of turn pays it")


func _grid_migration() -> void:
	var v5 := _new([_f("rome")])
	var la := _r("latium")
	var a: Dictionary = CState.armies_of(v5, _f("rome"))[0]
	a["stance"] = CData.STANCE_GARRISON
	var raider: Dictionary = CState.armies_of(v5, _f("rome"))[1]
	raider["r"] = _r("apulia")
	var mig := CState.from_json(CState.to_json(v5))
	_check(int(mig["version"]) == 6, "a format 5 save migrates to format 6")
	var ok := true
	for m in mig["armies"]:
		if not m.has("x") or CGrid.region(CState.cell(m)) != int(m["r"]) or m.has("dest") or int(m["mp"]) != CState.max_mp6(m):
			ok = false
	_check(ok, "every army stands on a cell of its region with full points")
	var ma := CState.army(mig, int(a["id"]))
	var mr := CState.army(mig, int(raider["id"]))
	_check(CState.cell(ma) == CGrid.site(la) and CRules.inside(mig, ma) and int(ma["stance"]) == CData.ST_DEFAULT,
		"an army inside the walls is on its settlement's cell")
	_check(CState.cell(mr) == CGrid.camp(_r("apulia")) and int(mr["stance"]) == CData.ST_RAID, "an army in enemy land raids from its camp")
	var other: Dictionary = CState.armies_of(mig, _f("carthage"))[0]
	_check(CGrid.cheb(CState.cell(other), CGrid.site(int(other["r"]))) == 1, "the others stand in the field next to their settlement")
	var v1 := CState.from_json(FileAccess.get_file_as_string("res://tests/data/campaign_v1.json"))
	var ok1 := not v1.is_empty() and int(v1["version"]) == 6
	for m in v1.get("armies", []):
		if not m.has("x"):
			ok1 = false
	_check(ok1, "the format 1 save migrates all the way to format 6")
	var r1 := CTurn.resolve_turn(v1, [])
	var r2 := CTurn.resolve_turn(CState.from_json(FileAccess.get_file_as_string("res://tests/data/campaign_v1.json")), [])
	_check(CState.state_hash(r1) == CState.state_hash(r2) and int(r1["turn"]) == int(v1["turn"]) + 1, "and resolves a turn deterministically")
	_check(CRules.apply_order(v5, _f("rome"), {"t": "stance", "a": int(raider["id"]), "s": CData.ST_RAID}) != "", "a format 5 state refuses the new stances")


func _grid_steps() -> void:
	var st := _empty6()
	var rome := _f("rome")
	var a := _put(st, rome, CState.field_cell(_r("latium")), ["heavy"])
	var b := _put(st, rome, CState.field_cell(_r("etruria")), ["cav"])
	var s1 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [_move6(a, CGrid.camp(_r("campania"))), _move6(b, CGrid.camp(_r("latium")))])])
	var ev := _events(s1, "moves")
	_check(ev.size() >= 1, "the turn's steps are logged")
	if ev.is_empty():
		return
	var steps: Array = ev[0]["steps"]
	var last := {}
	var order_ok := true
	var prev := -1
	for sp in steps:
		last[int(sp[0])] = CGrid.at(int(sp[1]), int(sp[2]))
	_check(int(last.get(int(a["id"]), -1)) == CState.cell(CState.army(s1, int(a["id"]))) and int(last.get(int(b["id"]), -1)) == CState.cell(CState.army(s1, int(b["id"]))),
		"each army's last logged step is where it ends")
	_check(int(steps[0][0]) == int(a["id"]) and int(steps[1][0]) == int(b["id"]), "steps go round by round, armies by id")
	if order_ok and prev < 0:
		pass
	var s2 := CTurn.resolve_turn(s1, [])
	var old := 0
	for e in s2["events"]:
		if str(e["k"]) == "moves" and int(e["turn"]) < int(s1["turn"]):
			old += 1
	_check(old == 0, "only the last turn's step log is kept")


func _grid_determinism() -> void:
	var a := _play(_new6([0]), 12, -1)
	var b := _play(_new6([0]), 12, -1)
	var c := _play(_new6([0]), 12, 6)
	_check(CState.state_hash(a) == CState.state_hash(b), "format 6: same inputs, same state after 12 turns (%s)" % CState.hash_text(a))
	_check(CState.state_hash(a) == CState.state_hash(c), "format 6: save / load in the middle changes nothing (%s)" % CState.hash_text(c))
	_check(_plain(a), "format 6: the state holds only ints, strings, arrays and dictionaries (no floats, no packed arrays)")


func _plain(v) -> bool:
	if v is int or v is String:
		return true
	if v is Array:
		for x in v:
			if not _plain(x):
				return false
		return true
	if v is Dictionary:
		for k in v:
			if not (k is String) or not _plain(v[k]):
				return false
		return true
	return false


# ------------------------------------- format 6: merge, exchange, gifts ---

## Regions of Italy given to faction f (a clear road for the merge tests).
func _italy(st: Dictionary, f: int) -> void:
	for key in ["latium", "etruria", "campania", "samnium", "apulia", "bruttium", "umbria"]:
		if _r(key) >= 0:
			st["regions"][_r(key)]["owner"] = f


## Building chain c of region r at level lvl (the slot set or added).
func _set_bld(st: Dictionary, r: int, c: int, lvl: int) -> void:
	for sl in st["regions"][r]["slots"]:
		if int(sl[0]) == c:
			sl[1] = lvl
			return
	(st["regions"][r]["slots"] as Array).append([c, lvl])


## Ammunition kinds and the wagon in the campaign (docs/DESIGN.md
## "Ammunition kinds", "The ammunition wagon"): which special kind a new
## unit carries comes from the faction and a building (CData.AMMO_AVAIL),
## stored on the unit entry ("ak"); the wagon is a recruited unit (the
## Workshop, Stables for the horses), given and exchanged like any; it
## adds to the army's strength (auto-resolve) and carries its army's
## special kinds into a battle ("aks").
func _ammo_wagon() -> void:
	var rome := _f("rome")
	var cart := _f("carthage")
	var greeks := _f("greeks")
	var lat := _r("latium")
	var att := _r("attica")
	var st := _new6([rome, cart])
	_set_bld(st, lat, CData.WORKSHOP, 0)
	_check(CRules.ammo_for(st, rome, lat, "bolt") == "", "kinds: no Workshop, plain bolts")
	_set_bld(st, lat, CData.WORKSHOP, 1)
	_check(CRules.ammo_for(st, rome, lat, "bolt") == "heavy_bolts", "kinds: Rome with a Workshop: heavy bolts")
	_check(CRules.ammo_for(st, rome, lat, "stone") == "", "kinds: fire pots need Workshop 2")
	_check(CRules.ammo_for(st, rome, lat, "javelin") == "", "kinds: Rome's javelinmen carry none")
	_set_bld(st, att, CData.RANGE, 1)
	_check(CRules.ammo_for(st, greeks, att, "archer") == "", "kinds: Greek archers with a Range 1: none")
	_set_bld(st, att, CData.RANGE, 2)
	_check(CRules.ammo_for(st, greeks, att, "archer") == "fire_arrows", "kinds: Greek archers with a Range 2: fire arrows")
	_check(CRules.ammo_for(st, rome, att, "archer") == "", "kinds: not for a faction not listed")
	# Recruiting a wagon and a battery (heavy bolts on its entry).
	st["factions"][rome]["treasury"] = 6000
	_check(CRules.recruit_check(st, rome, lat, "wagon") == "", "wagon: the hand cart with a Workshop 1")
	_check(CRules.recruit_check(st, rome, lat, "wagon2") == "needs Workshop 2", "wagon: one horse needs Workshop 2 (%s)" % CRules.recruit_check(st, rome, lat, "wagon2"))
	_set_bld(st, lat, CData.WORKSHOP, 2)
	_set_bld(st, lat, CData.STABLES, 1)
	_check(CRules.recruit_check(st, rome, lat, "wagon2") == "", "wagon: one horse with Workshop 2 and Stables 1")
	_check(CRules.recruit_check(st, rome, lat, "wagon3") == "needs Stables 2", "wagon: two horses need Stables 2 (%s)" % CRules.recruit_check(st, rome, lat, "wagon3"))
	var subs := [CTurn.submission(st, rome, [{"t": "recruit", "r": lat, "unit": "wagon2"},
		{"t": "recruit", "r": lat, "unit": "bolt"}]), CTurn.submission(st, cart, [])]
	var r1 := CTurn.resolve_turn(st, subs)
	var r2 := CTurn.resolve_turn(st, [subs[1], subs[0]])
	var wag := false
	var hb := false
	for a in CState.armies_of(r1, rome):
		for u in a["units"]:
			if str(u["t"]) == "wagon2" and not u.has("ak"):
				wag = true
			if str(u["t"]) == "bolt" and str(u.get("ak", "")) == "heavy_bolts":
				hb = true
	_check(wag and hb, "recruited: a wagon, and a battery whose entry carries heavy bolts (wagon %s, heavy bolts %s)" % [wag, hb])
	_check(CState.state_hash(r1) == CState.state_hash(r2) and _plain(r1), "kinds and wagons resolve deterministically, plain data")
	var rt := CState.from_json(CState.to_json(r1))
	_check(not rt.is_empty() and CState.state_hash(rt) == CState.state_hash(r1), "the unit entry's kind survives a JSON round trip")
	# Gift (exchange) of a wagon to the ally.
	var sg := _new6([rome, cart])
	sg["armies"] = []
	_italy(sg, rome)
	var c0 := CState.field_cell(lat)
	var mine := _put(sg, rome, c0, ["wagon", "heavy"])
	var theirs := _put(sg, cart, c0, ["archer"])
	var gs := [CTurn.submission(sg, rome, [{"t": "exchange", "from": int(mine["id"]), "to": int(theirs["id"]), "units": [0]}]),
		CTurn.submission(sg, cart, [])]
	var g1 := CTurn.resolve_turn(sg, gs)
	_check(str(_keys(CState.army(g1, int(theirs["id"])))) == str(["archer", "wagon"]), "a wagon is given to the ally like any unit (%s)" % str(_keys(CState.army(g1, int(theirs["id"])))))
	# Auto-resolve: the wagon is a little strength and a missile bonus.
	var arch := {"units": [{"t": "archer", "n": 80, "ak": "fire_arrows"}]}
	var with_w := {"units": [{"t": "archer", "n": 80, "ak": "fire_arrows"}, {"t": "wagon2", "n": 8}]}
	var s0 := CState.strength(arch)
	var w2 := UT.index_of("wagon2")
	var s1 := CState.strength(with_w)
	_check(s1 == s0 + 8 * UT.price_of(w2) / UT.size_of(w2) * UT.stat(w2, "str_pct") / 100 + s0 * UT.wagon_stat(1, "bonus_pct") / 100,
		"auto-resolve strength: archers %d, with a wagon %d" % [s0, s1])
	# A battle with the wagon: the formula, and the scenario (its army's kinds).
	var sb := _new6([rome])
	sb["armies"] = []
	_italy(sb, rome)
	var am := _put(sb, rome, c0, ["heavy", "archer", "wagon"])
	am["units"][1]["ak"] = "fire_arrows"
	var en := _put(sb, _f("epirus"), c0, ["spear", "spear"])
	var b := {"id": 1, "r": lat, "att": [int(am["id"])], "def": [int(en["id"])], "reinf": [], "att_f": rome,
		"def_f": _f("epirus"), "kind": "field", "settlement": 0}
	var fo := CBattle.formula(CState.copy(sb), b)
	_check(fo.has("winner") and (fo["units"] as Array).size() == 5, "auto-resolve with a wagon (formula: %d unit rows)" % (fo["units"] as Array).size())
	var built := CBattle.build(sb, b, rome)
	var sc: Dictionary = built["scenario"]
	var wu: Dictionary = {}
	var au: Dictionary = {}
	for ud in sc["units"]:
		if int(ud["type"]) == UT.index_of("wagon"):
			wu = ud
		if int(ud["type"]) == UT.ARCHER:
			au = ud
	_check(int(au.get("ak", -1)) == UT.ammo_index("fire_arrows") and str(wu.get("aks", [])) == str([UT.ammo_index("fire_arrows")]),
		"the battle: the archers' kind and the wagon's stock of it (%s / %s)" % [str(au.get("ak", -1)), str(wu.get("aks", []))])
	var sim := BattleSim.new()
	sim.setup(sc, int(built["seed"]))
	var q: int = sim.n_eq - 1
	_check(sim.n_eq == 1 and sim.q_kind[q] == BattleSim.EQ_WAGON and sim.wagon_stock(q, UT.ammo_index("fire_arrows")) > 0,
		"the sim: a wagon with fire arrows in its stock")
	for t in 200:
		sim.step()
	_check(sim.tick == 200, "the battle with a wagon runs")


## Camels and elephants in the campaign (docs/CAMPAIGN.md, rosters):
## Carthage recruits camels with Stables 1 (camel archers a Range 1 too)
## and elephants with Stables 3, Epirus elephants, Rome neither; a turn
## recruiting them resolves the same in either submission order and
## survives JSON; elephants march at the foot's pace; auto-resolve counts
## them by price (a field battle with them resolves and its scenario runs).
func _beasts() -> void:
	var rome := _f("rome")
	var cart := _f("carthage")
	var epi := _f("epirus")
	var zeu := _r("zeugitana")
	var epr := _r("epirus")
	var st := _new6([rome, cart])
	st["factions"][cart]["treasury"] = 9000
	st["factions"][epi]["treasury"] = 9000
	_set_bld(st, zeu, CData.STABLES, 0)
	_set_bld(st, zeu, CData.RANGE, 0)
	_check(CRules.recruit_check(st, cart, zeu, "camel") == "needs Stables 1", "camels need Stables 1 (%s)" % CRules.recruit_check(st, cart, zeu, "camel"))
	_set_bld(st, zeu, CData.STABLES, 1)
	_check(CRules.recruit_check(st, cart, zeu, "camel") == "", "camels with Stables 1 (%s)" % CRules.recruit_check(st, cart, zeu, "camel"))
	_check(CRules.recruit_check(st, cart, zeu, "camel_archer") == "needs Range 1", "camel archers need a Range (%s)" % CRules.recruit_check(st, cart, zeu, "camel_archer"))
	_check(CRules.recruit_check(st, cart, zeu, "elephant") == "needs Stables 3", "elephants need Stables 3 (%s)" % CRules.recruit_check(st, cart, zeu, "elephant"))
	_set_bld(st, zeu, CData.STABLES, 3)
	_set_bld(st, zeu, CData.RANGE, 1)
	_check(CRules.recruit_check(st, cart, zeu, "elephant") == "" and CRules.recruit_check(st, cart, zeu, "camel_archer") == "",
		"elephants with Stables 3, camel archers with a Range 1")
	_check(CRules.recruit_check(st, rome, _r("latium"), "camel") == "not in your roster", "Rome has no camels")
	_set_bld(st, epr, CData.STABLES, 3)
	_check(CRules.recruit_check(st, epi, epr, "elephant") == "", "Epirus recruits elephants (%s)" % CRules.recruit_check(st, epi, epr, "elephant"))
	_check(CRules.recruit_check(st, epi, epr, "camel") == "not in your roster", "Epirus has no camels")
	var lines := []
	for o in CRules.recruit_options(st, cart, zeu):
		if str(o["line"]) in ["camel", "camel_archer", "elephant"]:
			lines.append(str(o["t"]))
	_check(str(lines) == str(["camel", "camel_archer", "elephant"]), "Carthage's recruit list shows them (%s)" % str(lines))
	var subs := [CTurn.submission(st, rome, []), CTurn.submission(st, cart, [{"t": "recruit", "r": zeu, "unit": "elephant"},
		{"t": "recruit", "r": zeu, "unit": "camel"}])]
	var r1 := CTurn.resolve_turn(st, subs)
	var r2 := CTurn.resolve_turn(st, [subs[1], subs[0]])
	var got := []
	for a in CState.armies_of(r1, cart):
		for u in a["units"]:
			if str(u["t"]) in ["camel", "elephant"]:
				got.append("%s:%d" % [str(u["t"]), int(u["n"])])
	got.sort()
	_check(str(got) == str(["camel:60", "elephant:12"]), "recruited a camel unit and an elephant unit (%s)" % str(got))
	_check(CState.state_hash(r1) == CState.state_hash(r2) and _plain(r1), "beasts resolve deterministically, plain data")
	var rt := CState.from_json(CState.to_json(r1))
	_check(not rt.is_empty() and CState.state_hash(rt) == CState.state_hash(r1), "beasts survive a JSON round trip")
	_check(CState.max_mp({"units": [{"t": "cav", "n": 60}, {"t": "camel", "n": 60}]}) == CData.MP_CAV
		and CState.max_mp({"units": [{"t": "cav", "n": 60}, {"t": "elephant", "n": 12}]}) == CData.MP_FOOT,
		"riders on camels keep the cavalry's pace, elephants the foot's")
	var el := UT.index_of("elephant")
	_check(CState.strength({"units": [{"t": "elephant", "n": 12}]}) == UT.price_of(el),
		"auto-resolve: a full elephant unit counts its price (%d)" % CState.strength({"units": [{"t": "elephant", "n": 12}]}))
	var sb := _new6([cart])
	sb["armies"] = []
	_italy(sb, cart)
	var c0 := CState.field_cell(_r("latium"))
	var am := _put(sb, cart, c0, ["spear", "elephant", "camel", "camel_archer"])
	var en := _put(sb, rome, c0, ["heavy", "cav"])
	var b := {"id": 1, "r": _r("latium"), "att": [int(am["id"])], "def": [int(en["id"])], "reinf": [], "att_f": cart,
		"def_f": rome, "kind": "field", "settlement": 0}
	var fo := CBattle.formula(CState.copy(sb), b)
	_check(fo.has("winner") and (fo["units"] as Array).size() == 6, "auto-resolve with camels and elephants (%d unit rows)" % (fo["units"] as Array).size())
	var built := CBattle.build(sb, b, cart)
	var sim := BattleSim.new()
	sim.setup(built["scenario"], int(built["seed"]))
	var ne := 0
	for u in sim.n_units:
		if sim.u_type[u] == el:
			ne += sim.u_alive[u]
	for t in 200:
		sim.step()
	_check(ne == 12 and sim.tick == 200, "the battle with elephants and camels runs (%d elephants)" % ne)


## Light horse and slingers in the campaign (docs/CAMPAIGN.md, rosters):
## the faction rows behind the "cav_missile" and "sling" lines; light horse
## needs Stables of its tier and a Range 1, slingers the Range of their
## tier; Rome and Macedon have neither; the Balearics carry lead bullets
## from a Range 2, Iberian light horse fire javelins; a turn recruiting them
## resolves the same in either submission order and survives JSON;
## auto-resolve counts them by price and a field battle with them runs.
func _light_missile() -> void:
	var cart := _f("carthage")
	var zeu := _r("zeugitana")
	var st := _new6([_f("rome"), cart])
	st["factions"][cart]["treasury"] = 9000
	var want := {"carthage": ["numidians", "balearic"], "greeks": ["tarentines", "rhodians"],
		"epirus": ["tarentines", ""], "syracuse": ["tarentines", ""], "iberians": ["iberian_horse", "iberian_slingers"],
		"gauls": ["gallic_horse", ""], "rome": ["", ""], "macedon": ["", ""]}
	for fk in want:
		var f := _f(fk)
		var got := [CState.roster_type(f, "cav_missile", 2), CState.roster_type(f, "sling", 2)]
		var base_ok: bool = CState.roster_type(f, "cav_missile", 1) == ("cav_jav" if got[0] != "" else "") \
			and CState.roster_type(f, "sling", 1) == ("slinger" if got[1] != "" else "")
		_check(str(got) == str(want[fk]) and base_ok, "%s: light horse / slingers %s" % [fk, str(got)])
	_set_bld(st, zeu, CData.STABLES, 0)
	_set_bld(st, zeu, CData.RANGE, 0)
	_check(CRules.recruit_check(st, cart, zeu, "cav_jav") == "needs Stables 1", "light horse needs Stables 1 (%s)" % CRules.recruit_check(st, cart, zeu, "cav_jav"))
	_check(CRules.recruit_check(st, cart, zeu, "slinger") == "needs Range 1", "slingers need a Range 1 (%s)" % CRules.recruit_check(st, cart, zeu, "slinger"))
	_set_bld(st, zeu, CData.STABLES, 1)
	_check(CRules.recruit_check(st, cart, zeu, "cav_jav") == "needs Range 1", "light horse needs a Range 1 too (%s)" % CRules.recruit_check(st, cart, zeu, "cav_jav"))
	_set_bld(st, zeu, CData.RANGE, 1)
	_check(CRules.recruit_check(st, cart, zeu, "cav_jav") == "" and CRules.recruit_check(st, cart, zeu, "slinger") == "",
		"light horse with Stables 1 and Range 1, slingers with Range 1")
	_check(CRules.recruit_check(st, cart, zeu, "numidians") == "needs Stables 2", "Numidians need Stables 2 (%s)" % CRules.recruit_check(st, cart, zeu, "numidians"))
	_check(CRules.recruit_check(st, cart, zeu, "balearic") == "needs Range 2", "Balearics need Range 2 (%s)" % CRules.recruit_check(st, cart, zeu, "balearic"))
	_check(CRules.ammo_for(st, cart, zeu, "slinger") == "", "no lead bullets from a Range 1")
	_set_bld(st, zeu, CData.STABLES, 2)
	_set_bld(st, zeu, CData.RANGE, 2)
	_check(CRules.recruit_check(st, cart, zeu, "numidians") == "" and CRules.recruit_check(st, cart, zeu, "balearic") == "",
		"Numidians with Stables 2, Balearics with Range 2")
	_check(CRules.ammo_for(st, cart, zeu, "balearic") == "lead_bullets" and CRules.ammo_for(st, cart, zeu, "numidians") == "",
		"Carthage's slingers carry lead bullets from a Range 2, its riders nothing special (%s / %s)" % [
			CRules.ammo_for(st, cart, zeu, "balearic"), CRules.ammo_for(st, cart, zeu, "numidians")])
	var ib := _f("iberians")
	var cel := _r("celtiberia")
	_set_bld(st, cel, CData.RANGE, 2)
	_check(CRules.ammo_for(st, ib, cel, "iberian_horse") == "fire_javelins" and CRules.ammo_for(st, ib, cel, "iberian_slingers") == "",
		"Iberian riders carry fire javelins from a Range 2, Iberian slingers no lead")
	_check(CRules.recruit_check(st, _f("rome"), _r("latium"), "cav_jav") == "not in your roster"
		and CRules.recruit_check(st, _f("rome"), _r("latium"), "slinger") == "not in your roster", "Rome has neither")
	_check(CRules.recruit_check(st, cart, zeu, "tarentines") == "not in your roster", "Carthage has no Tarentines")
	var lines := []
	for o in CRules.recruit_options(st, cart, zeu):
		if str(o["line"]) in ["cav_missile", "sling"]:
			lines.append(str(o["t"]))
	_check(str(lines) == str(["balearic", "slinger", "numidians", "cav_jav"]), "Carthage's recruit list shows them (%s)" % str(lines))
	var subs2 := [CTurn.submission(st, cart, [{"t": "recruit", "r": zeu, "unit": "numidians"},
		{"t": "recruit", "r": zeu, "unit": "balearic"}]), CTurn.submission(st, _f("rome"), [])]
	var r2 := CTurn.resolve_turn(st, subs2)
	var r3 := CTurn.resolve_turn(st, [subs2[1], subs2[0]])
	var got2 := []
	for a in CState.armies_of(r2, cart):
		for u in a["units"]:
			if str(u["t"]) in ["numidians", "balearic"]:
				got2.append("%s:%d:%s" % [str(u["t"]), int(u["n"]), str(u.get("ak", ""))])
	got2.sort()
	_check(str(got2) == str(["balearic:80:lead_bullets", "numidians:60:"]), "recruited Numidians and Balearics (%s)" % str(got2))
	_check(CState.state_hash(r2) == CState.state_hash(r3) and _plain(r2), "light missile recruits resolve deterministically, plain data")
	var rt := CState.from_json(CState.to_json(r2))
	_check(not rt.is_empty() and CState.state_hash(rt) == CState.state_hash(r2), "light missile recruits survive a JSON round trip")
	var lh := UT.index_of("cav_jav")
	_check(CState.strength({"units": [{"t": "cav_jav", "n": 60}]}) == UT.price_of(lh),
		"auto-resolve: a full light horse unit counts its price (%d)" % CState.strength({"units": [{"t": "cav_jav", "n": 60}]}))
	var sb := _new6([cart])
	sb["armies"] = []
	_italy(sb, cart)
	var c0 := CState.field_cell(_r("latium"))
	var am := _put(sb, cart, c0, ["spear", "cav_jav", "numidians", "slinger", "balearic"])
	var en := _put(sb, _f("rome"), c0, ["heavy", "cav"])
	var b := {"id": 1, "r": _r("latium"), "att": [int(am["id"])], "def": [int(en["id"])], "reinf": [], "att_f": cart,
		"def_f": _f("rome"), "kind": "field", "settlement": 0}
	var fo := CBattle.formula(CState.copy(sb), b)
	_check(fo.has("winner") and (fo["units"] as Array).size() == 7, "auto-resolve with light horse and slingers (%d unit rows)" % (fo["units"] as Array).size())
	var built := CBattle.build(sb, b, cart)
	var sim := BattleSim.new()
	sim.setup(built["scenario"], int(built["seed"]))
	var nl := 0
	for u in sim.n_units:
		if UT.line_of(sim.u_type[u]) in ["cav_missile", "sling"]:
			nl += 1
	for t in 200:
		sim.step()
	_check(nl == 4 and sim.tick == 200, "the battle with light horse and slingers runs (%d units)" % nl)


## War dogs (docs/CAMPAIGN.md rosters, docs/DESIGN.md "War dogs"): the line
## "dogs" for Epirus, the Greeks, Rome and the Gauls; Barracks 1 and Stables
## 1; a turn recruiting them resolves the same in either order and survives
## JSON; auto-resolve counts the handlers' price (the pack's in it); a
## fought battle builds the pack from the handlers and the outcome credits
## the pack's kills to the handlers' row.
func _war_dogs() -> void:
	var have := {"epirus": true, "greeks": true, "rome": true, "gauls": true}
	var ok := true
	for f in CData.FACTIONS.size():
		var fk := str(CData.FACTIONS[f]["key"])
		if (CState.roster_type(f, "dogs", 1) == "dog_handlers") != have.has(fk):
			ok = false
	_check(ok, "war dogs in the rosters of Epirus, the Greeks, Rome and the Gauls only")
	var rome := _f("rome")
	var lat := _r("latium")
	var st := _new6([rome, _f("epirus")])
	st["factions"][rome]["treasury"] = 9000
	_set_bld(st, lat, CData.STABLES, 0)
	_check(CRules.recruit_check(st, rome, lat, "dog_handlers") == "needs Stables 1",
		"war dogs need Stables 1 (%s)" % CRules.recruit_check(st, rome, lat, "dog_handlers"))
	_set_bld(st, lat, CData.STABLES, 1)
	_set_bld(st, lat, CData.BARRACKS, 0)
	_check(CRules.recruit_check(st, rome, lat, "dog_handlers") == "needs Barracks 1",
		"war dogs need Barracks 1 too (%s)" % CRules.recruit_check(st, rome, lat, "dog_handlers"))
	_set_bld(st, lat, CData.BARRACKS, 1)
	_check(CRules.recruit_check(st, rome, lat, "dog_handlers") == "", "war dogs with Barracks 1 and Stables 1")
	_check(CRules.recruit_check(st, _f("carthage"), _r("zeugitana"), "dog_handlers") == "not in your roster",
		"Carthage has no war dogs")
	var subs := [CTurn.submission(st, rome, [{"t": "recruit", "r": lat, "unit": "dog_handlers"}]),
		CTurn.submission(st, _f("epirus"), [])]
	var r2 := CTurn.resolve_turn(st, subs)
	var r3 := CTurn.resolve_turn(st, [subs[1], subs[0]])
	var n_dogs := 0
	for a in CState.armies_of(r2, rome):
		for u in a["units"]:
			if str(u["t"]) == "dog_handlers":
				n_dogs += int(u["n"])
	_check(n_dogs == 16, "recruited 16 war dog handlers (%d)" % n_dogs)
	_check(CState.state_hash(r2) == CState.state_hash(r3) and _plain(r2), "war dog recruits resolve deterministically, plain data")
	var rt := CState.from_json(CState.to_json(r2))
	_check(not rt.is_empty() and CState.state_hash(rt) == CState.state_hash(r2), "war dog recruits survive a JSON round trip")
	var dh := UT.index_of("dog_handlers")
	_check(CState.strength({"units": [{"t": "dog_handlers", "n": 16}]}) == UT.price_of(dh),
		"auto-resolve: the handlers count their price, the pack's in it (%d)" % UT.price_of(dh))
	var sb := _new6([rome])
	sb["armies"] = []
	_italy(sb, rome)
	var c0 := CState.field_cell(_r("latium"))
	var am := _put(sb, rome, c0, ["heavy", "dog_handlers"])
	var en := _put(sb, _f("carthage"), c0, ["javelin", "archer"])
	var b := {"id": 1, "r": _r("latium"), "att": [int(am["id"])], "def": [int(en["id"])], "reinf": [], "att_f": rome,
		"def_f": _f("carthage"), "kind": "field", "settlement": 0}
	var fo := CBattle.formula(CState.copy(sb), b)
	_check(fo.has("winner") and (fo["units"] as Array).size() == 4, "auto-resolve with war dogs (%d unit rows)" % (fo["units"] as Array).size())
	var built := CBattle.build(sb, b, rome)
	var sim := BattleSim.new()
	sim.setup(built["scenario"], int(built["seed"]))
	var h := -1
	for u in sim.n_units:
		if sim.u_pack[u] >= 0:
			h = u
	_check(h >= 0 and sim.n_units == (built["scenario"]["units"] as Array).size() + 1,
		"the battle builds the pack from the handlers (handlers %d, %d units)" % [h, sim.n_units])
	var res := sim.result()
	var pk: int = sim.u_pack[h] if h >= 0 else -1
	for r in res["units"]:
		if int(r["unit"]) == pk:
			r["kills"] = 7  # (as if the pack had killed seven)
	var out := CBattle.outcome_from_result(built, res, "fought")
	var hk := -1
	for e in out["units"]:
		if int(e["army"]) == int(am["id"]) and int(e["unit"]) == 1:
			hk = int(e.get("kills", -1))
	_check(hk == 7 and (out["units"] as Array).size() == 4, "a fought outcome credits the pack's kills to its handlers (%d)" % hk)


## The general (docs/CAMPAIGN.md "The general"): every starting army has
## one (its faction's variant); Barracks 1 recruits him; recruiting refuses
## a second for an army (and a second a turn at one settlement); armies
## that come together keep the first and the others serve on as plain
## bodyguards; he adds cmd_pct to his army in auto-resolve; riders-only
## armies (light horse, camel archers) march at horse pace.
func _general() -> void:
	var want := {"rome": "legate", "carthage": "sufet", "macedon": "hetairoi_guard", "epirus": "hetairoi_guard",
		"greeks": "strategos", "syracuse": "strategos", "iberians": "chieftain", "gauls": "chieftain"}
	var st0 := _new6([])
	var ok := true
	var n_armies := 0
	for a in st0["armies"]:
		var fk := str(CData.FACTIONS[int(a["f"])]["key"])
		n_armies += 1
		if CState.generals(a) != 1 or not _keys(a).has(want[fk]) or CState.roster_type(int(a["f"]), "general", 1) != want[fk]:
			ok = false
	_check(ok and n_armies > 0, "each of the %d starting armies has one general, its faction's" % n_armies)
	CData.no_generals = true
	var st0b := _new6([])
	CData.no_generals = false
	var none := 0
	for a in st0b["armies"]:
		none += CState.generals(a)
	_check(none == 0, "the test switch no_generals starts the armies without them")
	# Recruiting: Barracks 1; one an army; one a turn at a settlement.
	var rome := _f("rome")
	var lat := _r("latium")
	var st := _empty6()
	_italy(st, rome)
	st["factions"][rome]["treasury"] = 20000
	var site := CGrid.site(lat)
	var withg := _put(st, rome, site, ["heavy", "legate"])
	var nog := _put(st, rome, CState.field_cell(lat), ["heavy"])  # (not in town: no auto-merge)
	_set_bld(st, lat, CData.BARRACKS, 0)
	_check(CRules.recruit_check(st, rome, lat, "legate") == "needs Barracks 1", "a general needs Barracks 1 (%s)" % CRules.recruit_check(st, rome, lat, "legate"))
	_set_bld(st, lat, CData.BARRACKS, 1)
	_check(CRules.recruit_check(st, rome, lat, "legate") == "", "with Barracks 1 Rome raises a Legate's Guard")
	_check(CRules.recruit_check(st, rome, lat, "sufet") == "not in your roster", "not another faction's general")
	var s1 := CState.copy(st)
	_check(CRules.apply_order(s1, rome, {"t": "recruit", "r": lat, "unit": "legate", "army": int(withg["id"])}) == "the army already has a general",
		"a second general for an army is refused")
	_check(CRules.apply_order(s1, rome, {"t": "recruit", "r": lat, "unit": "legate", "army": int(nog["id"])}) == "",
		"a general for an army without one")
	_check(CRules.apply_order(s1, rome, {"t": "recruit", "r": lat, "unit": "legate", "new": 1}) == "a general is already raised here this turn",
		"a second general at one settlement in a turn is refused")
	var s2 := CTurn.resolve_turn(s1, [CTurn.submission(s1, rome, [])])
	var gens := []
	for a in CState.armies_of(s2, rome):
		gens.append(CState.generals(a))
	_check(CState.generals(CState.army(s2, int(nog["id"]))) == 1 and CState.generals(CState.army(s2, int(withg["id"]))) == 1,
		"the recruit joined the army without a general (%s)" % str(gens))
	# An old-form recruit (no army named) goes to an army without a general.
	var s3 := CState.copy(st)
	_check(CRules.apply_order(s3, rome, {"t": "recruit", "r": lat, "unit": "legate"}) == "", "an old-form general recruit")
	var s3b := CTurn.resolve_turn(s3, [CTurn.submission(s3, rome, [])])
	var two := 0
	for a in CState.armies_of(s3b, rome):
		if CState.generals(a) > 1:
			two += 1
	_check(two == 0 and CState.generals(CState.army(s3b, int(nog["id"]))) == 1, "it joined the army without one")
	# Armies coming together: the first general stays, the next becomes a plain bodyguard.
	var sm := CState.copy(st)
	var g2 := _put(sm, rome, site, ["spear", "legate"])
	_check(CRules.apply_order(sm, rome, {"t": "merge", "army": int(g2["id"]), "into": int(withg["id"])}) == "",
		"two armies with generals may merge")
	var mk := _keys(CState.army(sm, int(withg["id"])))
	_check(str(mk) == str(["heavy", "legate", "spear", "bodyguard"]) and CState.generals(CState.army(sm, int(withg["id"]))) == 1,
		"the merged army keeps one general, the other serves on as a plain bodyguard (%s)" % str(mk))
	var bg := UT.index_of("bodyguard")
	_check(bg >= 0 and UT.stat(bg, "cmd_r") == 0 and UT.stat(bg, "cmd_pct") == 0 and UT.stat(bg, "attack") == UT.stat(UT.index_of("general"), "attack"),
		"the plain bodyguard: the same riders without the aura")
	var sx := CState.copy(st)
	var g3 := _put(sx, rome, site, ["spear", "legate"])
	_check(CRules.apply_order(sx, rome, {"t": "exchange", "from": int(g3["id"]), "to": int(withg["id"]), "units": [1]}) == "",
		"a general handed to an army that has one")
	_check(CState.generals(CState.army(sx, int(withg["id"]))) == 1 and _keys(CState.army(sx, int(withg["id"]))).has("bodyguard"),
		"... serves on as a plain bodyguard (%s)" % str(_keys(CState.army(sx, int(withg["id"])))))
	# Auto-resolve: +cmd_pct while he has men.
	var plain := {"units": [{"t": "heavy", "n": 100}, {"t": "spear", "n": 100}]}
	var led := {"units": [{"t": "heavy", "n": 100}, {"t": "spear", "n": 100}, {"t": "legate", "n": 30}]}
	var dead := {"units": [{"t": "heavy", "n": 100}, {"t": "spear", "n": 100}, {"t": "legate", "n": 0}]}
	var lg := UT.index_of("legate")
	var s_own := 30 * UT.price_of(lg) / 30 * UT.stat(lg, "str_pct") / 100
	_check(CState.strength(led) == (CState.strength(plain) + s_own) * (100 + UT.stat(lg, "cmd_pct")) / 100
		and CState.strength(dead) == CState.strength(plain),
		"auto-resolve: the general's army +%d %% (%d against %d), nothing once his men are gone" % [UT.stat(lg, "cmd_pct"),
			CState.strength(led), CState.strength(plain)])
	_check(_plain(s2) and CState.state_hash(CState.from_json(CState.to_json(s2))) == CState.state_hash(s2),
		"generals in the state: plain data, JSON round trip")
	# A battle with generals on both sides runs.
	var sb := _new6([rome])
	sb["armies"] = []
	_italy(sb, rome)
	var c0 := CState.field_cell(lat)
	var am := _put(sb, rome, c0, ["heavy", "legate"])
	var en := _put(sb, _f("epirus"), c0, ["pike", "hetairoi_guard"])
	var b := {"id": 1, "r": lat, "att": [int(am["id"])], "def": [int(en["id"])], "reinf": [], "att_f": rome,
		"def_f": _f("epirus"), "kind": "field", "settlement": 0}
	var fo := CBattle.formula(CState.copy(sb), b)
	var built := CBattle.build(sb, b, rome)
	var sim := BattleSim.new()
	sim.setup(built["scenario"], int(built["seed"]))
	var ng := 0
	for u in sim.n_units:
		if UT.stat(sim.u_type[u], "cmd_r") > 0:
			ng += 1
	for t in 300:
		sim.step()
	_check(fo.has("winner") and ng == 2 and sim.tick == 300, "auto-resolve and a fought battle with a general a side (%d)" % ng)
	# March pace: riders only, horses or camels.
	var lh := {"units": [{"t": "cav_jav", "n": 60}, {"t": "camel_archer", "n": 60}, {"t": "legate", "n": 30}]}
	var mixed := {"units": [{"t": "cav_jav", "n": 60}, {"t": "heavy", "n": 100}]}
	var el := {"units": [{"t": "cav", "n": 60}, {"t": "elephant", "n": 12}]}
	_check(CState.max_mp(lh) == CData.MP_CAV and CState.max_mp(mixed) == CData.MP_FOOT and CState.max_mp(el) == CData.MP_FOOT,
		"light horse and camel archers march at horse pace, foot or elephants at the foot's")
	CData.old_mp = true
	_check(CState.max_mp(lh) == CData.MP_FOOT, "(the old_mp test switch: the foot's pace, as before)")
	CData.old_mp = false


func _keys(a: Dictionary) -> Array:
	var out: Array = []
	for u in a["units"]:
		out.append(str(u["t"]))
	return out


func _grid_merge() -> void:
	var st := _empty6()
	var rome := _f("rome")
	_italy(st, rome)
	var a := _put(st, rome, CState.field_cell(_r("latium")), ["heavy", "spear"])
	var b := _put(st, rome, CState.field_cell(_r("campania")), ["cav", "cav", "heavy"])
	var ida := int(a["id"])
	var idb := int(b["id"])
	var mo := {"t": "move", "army": idb, "join": ida, "persist": 1}
	_check(CRules.apply_order(CState.copy(st), rome, mo) == "", "a march to merge into one's own army is a valid order")
	var pv := CTurn.preview(st, rome, [mo])
	_check((pv["errors"] as Array).is_empty() and (pv["moves"] as Array).size() == 1 and int(pv["moves"][0][5]) == ida,
		"the plan preview carries the merge target")
	var pp := CRules.plan_path(st, b, CState.cell(a), -1, CData.MODE_SIEGE, {}, 12, ida)
	_check(not pp.has("why") and str(pp["aim"]["kind"]) == "merge" and int(pp["t"][-1]) == 0, "its path ends next to the army this turn (kind merge)")
	var s1 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [mo])])
	var a1 := CState.army(s1, ida)
	_check(CState.army(s1, idb).is_empty() and not a1.is_empty() and str(_keys(a1)) == str(["heavy", "spear", "cav", "cav", "heavy"]),
		"same turn: the mover merged in, its units after the target's (%s)" % str(_keys(a1)))
	_check(CState.cell(a1) == CState.cell(a) and int(a1["id"]) == ida, "the target keeps its id and cell")
	# Across turns: the target marches off north; the mover follows it.
	var st2 := _empty6()
	_italy(st2, rome)
	var t2 := _put(st2, rome, CState.field_cell(_r("latium")), ["heavy"])
	var m2 := _put(st2, rome, CState.field_cell(_r("bruttium")), ["spear", "spear"])
	var away := CState.field_cell(_r("etruria"))
	var s2 := CTurn.resolve_turn(st2, [CTurn.submission(st2, rome, [_move6(t2, away),
		{"t": "move", "army": int(m2["id"]), "join": int(t2["id"]), "persist": 1}])])
	var m2b := CState.army(s2, int(m2["id"]))
	_check(not m2b.is_empty() and int(m2b.get("dest_army", -1)) == int(t2["id"]), "not there yet: the mover keeps following (dest_army)")
	var cur := s2
	var turns := 1
	while turns < 6 and not CState.army(cur, int(m2["id"])).is_empty():
		cur = CTurn.resolve_turn(cur, [CTurn.submission(cur, rome, [])])
		turns += 1
	var t2b := CState.army(cur, int(t2["id"]))
	_check(CState.army(cur, int(m2["id"])).is_empty() and CState.unit_count(t2b) == 3 and CGrid.cheb(CState.cell(t2b), away) <= 1,
		"it caught up and merged after %d turns, where the target went" % turns)
	_check(_plain(s2), "a stored merge march is plain data")
	# The cap.
	var st3 := _empty6()
	_italy(st3, rome)
	var big := _put(st3, rome, CState.field_cell(_r("latium")), ["heavy", "heavy", "heavy", "heavy", "heavy", "heavy", "heavy", "heavy"])
	var five := _put(st3, rome, CState.field_cell(_r("campania")), ["spear", "spear", "spear", "spear", "spear"])
	_check(CRules.apply_order(CState.copy(st3), rome, {"t": "move", "army": int(five["id"]), "join": int(big["id"]), "persist": 1}) == "too many units to merge",
		"merging past %d units is refused: too many units to merge" % CData.ARMY_MAX)
	# The target gone (disbanded this turn): the move ends with a note.
	var st4 := _empty6()
	_italy(st4, rome)
	var t4 := _put(st4, rome, CState.field_cell(_r("latium")), ["heavy"])
	var m4 := _put(st4, rome, CState.field_cell(_r("bruttium")), ["spear"])
	var s4 := CTurn.resolve_turn(st4, [CTurn.submission(st4, rome, [{"t": "disband", "army": int(t4["id"]), "units": [0]},
		{"t": "move", "army": int(m4["id"]), "join": int(t4["id"]), "persist": 1}])])
	var m4b := CState.army(s4, int(m4["id"]))
	var gone_ev := false
	for e in _events(s4, "move_failed"):
		if int(e["army"]) == int(m4["id"]):
			gone_ev = true
	_check(not m4b.is_empty() and CState.cell(m4b) == CState.cell(m4) and not m4b.has("dest_army") and gone_ev,
		"the army to merge into is gone: the mover stays and is told")
	# Merging into a besieger from its ring is allowed (the merge order too).
	var st5 := _empty6()
	var ep := _f("epirus")
	var r5 := _r("epirus")
	var ring := []
	for k in 8:
		var c := CGrid.at(CGrid.cx(CGrid.site(r5)) + CGrid.DX[k], CGrid.cy(CGrid.site(r5)) + CGrid.DY[k])
		if c >= 0 and CGrid.passable(c) and CGrid.step_cost(CGrid.site(r5), c) > 0:
			ring.append(c)
	_check(int(st5["regions"][r5]["owner"]) == ep and ring.size() >= 2, "Epirus has two ring cells")
	if ring.size() >= 2:
		var s1a := _put(st5, rome, ring[0], ["heavy"])
		var s1b := _put(st5, rome, ring[1], ["spear"])
		CRules.start_siege(st5, r5, s1a, -1)
		if CGrid.cheb(ring[0], ring[1]) <= 1:
			_check(CRules.siege_role(st5, s1b) == 1 and CRules.apply_order(st5, rome, {"t": "merge", "army": int(s1b["id"]), "into": int(s1a["id"])}) == "",
				"two besiegers side by side merge")


func _grid_exchange() -> void:
	var st := _empty6()
	var rome := _f("rome")
	_italy(st, rome)
	var c0 := CState.field_cell(_r("latium"))
	var a := _put(st, rome, c0, ["heavy", "heavy", "spear"])
	var c1 := -1
	for k in 8:
		var c := CGrid.at(CGrid.cx(c0) + CGrid.DX[k], CGrid.cy(c0) + CGrid.DY[k])
		if c >= 0 and CGrid.passable(c) and CGrid.step_cost(c0, c) > 0 and CGrid.site_region(c) < 0:
			c1 = c
			break
	var b := _put(st, rome, c1, ["cav", "cav"])
	var ida := int(a["id"])
	var idb := int(b["id"])
	var x := {"t": "exchange", "from": ida, "to": idb, "units": [0], "back": [1]}
	var s1 := CState.copy(st)
	_check(CRules.apply_order(s1, rome, x) == "", "exchange between neighbouring armies")
	_check(str(_keys(CState.army(s1, ida))) == str(["heavy", "spear", "cav"]) and str(_keys(CState.army(s1, idb))) == str(["cav", "heavy"]),
		"both ways: the units given go after the kept ones (%s / %s)" % [str(_keys(CState.army(s1, ida))), str(_keys(CState.army(s1, idb)))])
	var s2 := CState.copy(st)
	_check(CRules.apply_order(s2, rome, {"t": "exchange", "from": idb, "to": ida, "units": [0, 1]}) == ""
		and CState.army(s2, idb).is_empty() and CState.unit_count(CState.army(s2, ida)) == 5, "an army that gives all its units is gone")
	var s3 := CState.copy(st)
	CState.place(CState.army(s3, idb), CState.field_cell(_r("campania")))
	_check(CRules.apply_order(s3, rome, x) == "not together", "armies apart cannot trade units")
	var s4 := CState.copy(st)
	for k in 9:
		(CState.army(s4, ida)["units"] as Array).append({"t": "heavy", "n": 100})
	_check(CRules.apply_order(s4, rome, {"t": "exchange", "from": idb, "to": ida, "units": [0]}) == "more than %d units" % CData.ARMY_MAX,
		"the receiving army stays within %d units" % CData.ARMY_MAX)
	_check(CRules.apply_order(CState.copy(st), rome, {"t": "exchange", "from": ida, "to": idb, "units": [0, 0]}) == "bad units", "repeated indices are refused")
	# Through a turn: deterministic, the preview shows the counts.
	var pv := CTurn.preview(st, rome, [x])
	_check(CState.unit_count(CState.army(pv["state"], ida)) == 3 and CState.unit_count(CState.army(pv["state"], idb)) == 2
		and str(_keys(CState.army(pv["state"], idb))) == str(["cav", "heavy"]), "the plan preview applies the exchange")
	var r1 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [x])])
	var r2 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [x])])
	_check(CState.state_hash(r1) == CState.state_hash(r2), "an exchange resolves deterministically")


func _grid_arrange() -> void:
	var st := _empty6()
	var rome := _f("rome")
	var cart := _f("carthage")
	_italy(st, rome)
	var a := _put(st, rome, CState.field_cell(_r("latium")), ["heavy", "spear", "cav", "light"])
	var id := int(a["id"])
	var x := {"t": "arrange", "army": id, "order": [2, 0, 3, 1]}
	var s1 := CState.copy(st)
	_check(CRules.apply_order(s1, rome, x) == "" and str(_keys(CState.army(s1, id))) == str(["cav", "heavy", "light", "spear"]),
		"arrange puts the units in the new order (%s)" % str(_keys(CState.army(s1, id))))
	var bad := [[0, 1, 2], [0, 1, 2, 3, 4], [0, 0, 1, 2], [0, 1, 2, 4], [-1, 0, 1, 2], [0, 1, 2, 1.5], "0123", [0, 1, 2, "3"]]
	var refused := 0
	for b in bad:
		if CRules.apply_order(CState.copy(st), rome, {"t": "arrange", "army": id, "order": b}) == "bad order":
			refused += 1
	_check(refused == bad.size(), "a list that is not a permutation of the units is refused (%d of %d)" % [refused, bad.size()])
	var s2 := CState.copy(st)
	_check(CRules.apply_order(s2, rome, {"t": "arrange", "army": id, "order": [2.0, 0.0, 3.0, 1.0]}) == ""
		and str(_keys(CState.army(s2, id))) == str(["cav", "heavy", "light", "spear"]), "JSON numbers (floats) are accepted")
	_check(CRules.apply_order(CState.copy(st), cart, x) == "no such army", "another faction's army is refused")
	var s3 := CState.copy(st)
	CState.army(s3, id)["busy"] = 1
	_check(CRules.apply_order(s3, rome, x) == "in a battle", "an army in a battle is refused")
	# The plan preview, and a split after it takes the arranged units.
	var sp := {"t": "split", "army": id, "units": [0], "new": CRules.new_army_id(st, rome)}
	var pv := CTurn.preview(st, rome, [x, sp])
	_check((pv["errors"] as Array).is_empty() and str(_keys(CState.army(pv["state"], id))) == str(["heavy", "light", "spear"])
		and str(_keys(CState.army(pv["state"], int(sp["new"])))) == str(["cav"]), "the preview applies it; a later split counts in the new order")
	# Through a turn: applied, deterministic, the same after a JSON trip.
	var sub := CTurn.submission(st, rome, [x])
	var r1 := CTurn.resolve_turn(st, [sub])
	var r2 := CTurn.resolve_turn(st, [sub])
	var r3 := CTurn.resolve_turn(st, [JSON.parse_string(JSON.stringify(sub))])
	_check(str(_keys(CState.army(r1, id))) == str(["cav", "heavy", "light", "spear"]), "the turn applies the arrangement")
	_check(CState.state_hash(r1) == CState.state_hash(r2) and CState.state_hash(r1) == CState.state_hash(r3),
		"an arrangement resolves deterministically (also from a JSON submission)")
	_check(_plain(r1), "the state stays plain data")
	# Format 5 (and older): the same order.
	var st5 := _new([rome])
	var a5: Dictionary = CState.armies_of(st5, rome)[0]
	var n5 := CState.unit_count(a5)
	var rev: Array = []
	for k in n5:
		rev.append(n5 - 1 - k)
	var want: Array = _keys(a5)
	want.reverse()
	var r5 := CTurn.resolve_turn(st5, _sub(st5, rome, [{"t": "arrange", "army": int(a5["id"]), "order": rev}]))
	_check(n5 > 1 and str(_keys(CState.army(r5, int(a5["id"])))) == str(want), "format 5: the arrangement applies as well")


func _grid_gift() -> void:
	var rome := _f("rome")
	var cart := _f("carthage")
	var st := _new6([rome, cart])
	st["armies"] = []
	_italy(st, rome)
	var c0 := CState.field_cell(_r("latium"))
	var mine := _put(st, rome, c0, ["heavy", "heavy", "spear"])
	var theirs := _put(st, cart, c0, ["cav"])
	var ai := _put(st, _f("epirus"), c0, ["spear"])
	var g := {"t": "exchange", "from": int(mine["id"]), "to": int(theirs["id"]), "units": [0, 2]}
	_check(CRules.exchange_check(st, rome, int(mine["id"]), int(theirs["id"]), [0, 2]) == "", "a gift of two units to the ally's army is allowed")
	_check(CRules.exchange_check(st, rome, int(theirs["id"]), int(mine["id"]), [0]) == "no such army", "taking the ally's units is not (from must be ours)")
	_check(CRules.exchange_check(st, rome, int(mine["id"]), int(theirs["id"]), [0], [0]) == "cannot take an ally's units", "nor in return for a gift")
	_check(CRules.exchange_check(st, rome, int(mine["id"]), int(ai["id"]), [0]) == "not a friendly army", "no gifts to an AI faction")
	var subs := [CTurn.submission(st, rome, [g]), CTurn.submission(st, cart, [])]
	var r1 := CTurn.resolve_turn(st, subs)
	var r2 := CTurn.resolve_turn(st, [subs[1], subs[0]])
	var t1 := CState.army(r1, int(theirs["id"]))
	_check(CState.unit_count(t1) == 3 and str(_keys(t1)) == str(["cav", "heavy", "spear"]) and CState.unit_count(CState.army(r1, int(mine["id"]))) == 1,
		"the ally's army has the gift after the turn (%s)" % str(_keys(t1)))
	_check(CState.state_hash(r1) == CState.state_hash(r2), "both clients resolve the gift the same (submission order does not matter)")
	var ev := _events(r1, "gift")
	_check(ev.size() == 1 and int(ev[0]["f"]) == rome and int(ev[0]["to"]) == cart and int(ev[0]["n"]) == 2 and int(ev[0]["r"]) == _r("latium"),
		"a gift event for the receiver")
	# A whole army as a gift.
	var s3 := CState.copy(st)
	_check(CRules.apply_order(s3, rome, {"t": "exchange", "from": int(mine["id"]), "to": int(theirs["id"]), "units": [0, 1, 2]}) == ""
		and CState.army(s3, int(mine["id"])).is_empty() and CState.unit_count(CState.army(s3, int(theirs["id"]))) == 4,
		"giving the whole army: the giver's army is gone")


func _gift_setup() -> Dictionary:
	var rome := _f("rome")
	var cart := _f("carthage")
	var st := _new6([rome, cart])
	st["armies"] = []
	_italy(st, rome)
	st["factions"][rome]["treasury"] = 1000
	st["factions"][cart]["treasury"] = 1000
	return st


func _city_gifts() -> void:
	var rome := _f("rome")
	var cart := _f("carthage")
	var epi := _f("epirus")
	var cap := _r("campania")
	var st := _gift_setup()
	(st["regions"][cap]["slots"] as Array).append([CData.MARKET, 1])
	var gar := int(st["regions"][cap]["gar"])
	_check(CRules.gift_region_check(st, rome, cap, cart, 0) == "", "Rome may give Capua to the allied player")
	_check(CRules.gift_region_check(st, rome, cap, epi, 0) == "only between allied players", "not to an AI faction")
	_check(CRules.gift_region_check(st, rome, _r("zeugitana"), cart, 0) == "not the giver's city", "nor a city not ours")
	_check(CRules.gift_region_check(st, rome, cap, cart, 5000) != "", "nor for more than the receiver has")
	_check(CRules.gift_money_check(st, rome, cart, 2000) == "not enough money" and CRules.gift_money_check(st, rome, epi, 10) != ""
		and CRules.gift_money_check(st, rome, cart, 0) != "", "money: the treasury, a human ally, an amount")
	# A free gift: at resolution, garrison and buildings kept.
	var free := {"t": "gift_region", "r": cap, "to": cart, "price": 0}
	var subs := [CTurn.submission(st, rome, [free]), CTurn.submission(st, cart, [])]
	var r1 := CTurn.resolve_turn(st, subs)
	var r1b := CTurn.resolve_turn(st, [subs[1], subs[0]])
	_check(CState.owner(r1, cap) == cart and CState.building(r1, cap, CData.MARKET) == 1 and int(r1["regions"][cap]["gar"]) >= gar,
		"a free gift: Capua is Carthage's after the turn, its market and garrison kept")
	var ev := _events(r1, "gift_region")
	_check(ev.size() == 1 and int(ev[0]["f"]) == rome and int(ev[0]["to"]) == cart and int(ev[0]["price"]) == 0 and _events(r1, "captured").is_empty(),
		"one gift_region event, no capture")
	_check(CState.state_hash(r1) == CState.state_hash(r1b), "the gift resolves the same on both clients")
	# A priced gift: a proposal, accepted next turn.
	var priced := {"t": "gift_region", "r": cap, "to": cart, "price": 300}
	var t1 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [priced]), CTurn.submission(st, cart, [])])
	var prop: Dictionary = {}
	for p in t1["proposals"]:
		if p.has("kind"):
			prop = p
	_check(CState.owner(t1, cap) == rome and not prop.is_empty() and str(prop["kind"]) == "offer_city" and int(prop["from"]) == rome
		and int(prop["to"]) == cart and int(prop["r"]) == cap and int(prop["price"]) == 300, "a priced gift is an offer to Carthage, Capua still Roman")
	_check(CRules.apply_order(CState.copy(st), rome, priced) == "" and CRules.gift_region_check(t1, rome, cap, cart, 0) == "",
		"the offer is valid as an order")
	var s2 := CState.copy(st)
	CRules.apply_order(s2, rome, priced)
	_check(CRules.apply_order(s2, rome, priced) == "already offered this turn", "one offer per city per turn")
	var pid := int(prop.get("id", -1))
	var tr_r := int(t1["factions"][rome]["treasury"])
	var tr_c := int(t1["factions"][cart]["treasury"])
	var acc := [CTurn.submission(t1, rome, []), CTurn.submission(t1, cart, [{"t": "accept_offer", "id": pid}])]
	var t2 := CTurn.resolve_turn(t1, acc)
	var t2b := CTurn.resolve_turn(t1, [acc[1], acc[0]])
	_check(CState.owner(t2, cap) == cart and _events(t2, "gift_region").size() == 1 and int(_events(t2, "gift_region")[0]["price"]) == 300,
		"accepted: Capua is Carthage's")
	_check(CState.state_hash(t2) == CState.state_hash(t2b), "the handshake resolves the same on both clients")
	_check(CRules.apply_order(CState.copy(t1), rome, {"t": "accept_offer", "id": pid}) == "no such offer"
		and CRules.apply_order(CState.copy(t1), cart, {"t": "answer", "id": pid, "accept": 1}) == "no such proposal",
		"only the receiver answers, and not by the AI-proposal answer")
	# The money moved with it: compare against a turn where Carthage declined.
	var dec := CTurn.resolve_turn(t1, [CTurn.submission(t1, rome, []), CTurn.submission(t1, cart, [{"t": "decline_offer", "id": pid}])])
	_check(CState.owner(dec, cap) == rome and _events(dec, "city_declined").size() == 1, "declined: Capua stays Roman, an event says so")
	var noans := CTurn.resolve_turn(t1, [CTurn.submission(t1, rome, []), CTurn.submission(t1, cart, [])])
	var x1 := CState.copy(t1)
	_check(CRules.apply_order(x1, cart, {"t": "accept_offer", "id": pid}) == "" and CState.owner(x1, cap) == cart
		and int(x1["factions"][cart]["treasury"]) == tr_c - 300 and int(x1["factions"][rome]["treasury"]) == tr_r + 300,
		"the city and the money move together (300)")
	var lapsed := false
	for p in noans["proposals"]:
		lapsed = lapsed or int(p["id"]) == pid
	_check(not lapsed, "an unanswered offer lapses after its turn")
	# Refusal at acceptance: an army of the giver now stands in the city.
	var t1a := CState.copy(t1)
	_put(t1a, rome, CGrid.site(cap), ["spear"])
	var ra := CTurn.resolve_turn(t1a, [CTurn.submission(t1a, rome, []), CTurn.submission(t1a, cart, [{"t": "accept_offer", "id": pid}])])
	var rf := _events(ra, "city_refused")
	_check(CState.owner(ra, cap) == rome and rf.size() == 1 and str(rf[0]["why"]).contains("army"), "refused at acceptance: an army of the giver in the city")
	_check(CRules.gift_region_check(t1a, rome, cap, cart, 0).contains("army"), "and the check says so")
	# Refusal at acceptance: the treasury no longer covers it.
	var t1m := CState.copy(t1)
	t1m["factions"][cart]["treasury"] = 100
	var rm := CTurn.resolve_turn(t1m, [CTurn.submission(t1m, rome, []), CTurn.submission(t1m, cart, [{"t": "accept_offer", "id": pid}])])
	rf = _events(rm, "city_refused")
	_check(CState.owner(rm, cap) == rome and rf.size() == 1 and str(rf[0]["why"]).contains("cannot pay"), "refused at acceptance: Carthage cannot pay")
	# The buyer's offer: Carthage asks for Capua, Rome accepts.
	var bo := {"t": "buy_region", "r": cap, "price": 200}
	var b1 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, []), CTurn.submission(st, cart, [bo])])
	var bp := -1
	for p in b1["proposals"]:
		if p.has("kind") and str(p["kind"]) == "ask_city" and int(p["to"]) == rome and int(p["from"]) == cart:
			bp = int(p["id"])
	_check(bp >= 0, "an offer to buy is a proposal to the owner")
	var b2 := CTurn.resolve_turn(b1, [CTurn.submission(b1, rome, [{"t": "accept_offer", "id": bp}]), CTurn.submission(b1, cart, [])])
	_check(CState.owner(b2, cap) == cart and int(_events(b2, "gift_region")[0]["f"]) == rome, "the owner accepts: Capua is Carthage's")
	_check(CRules.buy_region_check(st, cart, cap, 0) == "name a price" and CRules.buy_region_check(st, epi, cap, 10) != "", "a buyer names a price and is the ally")
	# Money.
	var m1 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [{"t": "gift_money", "to": cart, "amount": 400}]), CTurn.submission(st, cart, [])])
	var m0 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, []), CTurn.submission(st, cart, [])])
	_check(int(m1["factions"][rome]["treasury"]) == int(m0["factions"][rome]["treasury"]) - 400
		and int(m1["factions"][cart]["treasury"]) == int(m0["factions"][cart]["treasury"]) + 400 and _events(m1, "gift_money").size() == 1,
		"a money gift moves 400 at resolution")
	# The AI: never offered (orders from an AI faction are refused) and its
	# answers to AI proposals ignore these entries.
	_check(CRules.apply_order(CState.copy(st), epi, {"t": "gift_money", "to": rome, "amount": 1}) != ""
		and CRules.apply_order(CState.copy(st), epi, {"t": "gift_region", "r": _r("epirus"), "to": rome, "price": 0}) != "",
		"an AI faction cannot give or be given")
	_check(CState.state_hash(CState.from_json(CState.to_json(t1))) == CState.state_hash(t1),
		"the offer survives a JSON round trip")


## A unit key faction f can recruit in r now.
func _recruitable(st: Dictionary, f: int, r: int) -> String:
	for o in CRules.recruit_options(st, f, r):
		if bool(o["ok"]):
			return str(o["t"])
	return ""


func _grid_recruit_collect() -> void:
	var rome := _f("rome")
	var st := _empty6()
	var lat := _r("latium")
	st["factions"][rome]["treasury"] = 20000
	var key := _recruitable(st, rome, lat)
	_check(key != "", "Roma can recruit (%s)" % key)
	if key == "":
		return
	var s1 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [{"t": "recruit", "r": lat, "unit": key}, {"t": "recruit", "r": lat, "unit": key}])])
	var mine := CState.armies_of(s1, rome)
	_check(mine.size() == 1 and CState.unit_count(mine[0]) == 2 and CState.cell(mine[0]) == CGrid.site(lat), "two recruits form one army inside the walls")
	var s2 := CTurn.resolve_turn(s1, [CTurn.submission(s1, rome, [{"t": "recruit", "r": lat, "unit": key}])])
	mine = CState.armies_of(s2, rome)
	_check(mine.size() == 1 and CState.unit_count(mine[0]) == 3, "next turn's recruit joins it")
	# A 1-unit army already standing idle in the city: the end of the turn
	# gathers it in too.
	var s3 := CState.copy(s2)
	var extra := _put(s3, rome, CGrid.site(lat), [key])
	var s4 := CTurn.resolve_turn(s3, [CTurn.submission(s3, rome, [{"t": "recruit", "r": lat, "unit": key}])])
	mine = CState.armies_of(s4, rome)
	_check(mine.size() == 1 and CState.unit_count(mine[0]) == 5 and CState.army(s4, int(extra["id"])).is_empty(),
		"recruits and an idle army in the city end in one army (%d armies)" % mine.size())


func _grid_auto_merge() -> void:
	var rome := _f("rome")
	var st := _empty6()
	var lat := _r("latium")
	var site := CGrid.site(lat)
	var a := _put(st, rome, site, ["heavy", "heavy", "heavy", "heavy", "heavy", "heavy", "heavy", "heavy"])
	var b := _put(st, rome, site, ["spear", "spear", "spear", "spear", "spear"])
	var c := _put(st, rome, site, ["cav", "cav"])
	var d := _put(st, rome, site, ["cav"])
	d["stance"] = CData.ST_FORTIFY
	var e := _put(st, rome, CState.field_cell(lat), ["spear"])
	var e2 := _put(st, rome, CState.field_cell(lat), ["spear"])
	var s1 := CTurn.resolve_turn(st, [])
	_check(CState.army(s1, int(c["id"])).is_empty() and CState.unit_count(CState.army(s1, int(a["id"]))) == 10,
		"idle armies in a city merge at the end of the turn into the lowest id")
	_check(not CState.army(s1, int(b["id"])).is_empty() and CState.unit_count(CState.army(s1, int(b["id"]))) == 5,
		"one that would pass %d units stays apart" % CData.ARMY_MAX)
	_check(not CState.army(s1, int(d["id"])).is_empty(), "another stance stays apart")
	_check(not CState.army(s1, int(e["id"])).is_empty() and not CState.army(s1, int(e2["id"])).is_empty(), "armies in the field are not merged")
	# One with a march stored is not idle.
	var st2 := _empty6()
	var p := _put(st2, rome, site, ["heavy"])
	var q := _put(st2, rome, site, ["spear"])
	var far := CState.field_cell(_r("bruttium"))
	_italy(st2, rome)
	var s2 := CTurn.resolve_turn(st2, [CTurn.submission(st2, rome, [_move6(q, far)])])
	_check(not CState.army(s2, int(q["id"])).is_empty() and not CState.army(s2, int(p["id"])).is_empty(), "an army marching off is not merged")
	var r1 := CTurn.resolve_turn(st, [])
	_check(CState.state_hash(r1) == CState.state_hash(s1), "the end-of-turn merge is deterministic")


## Version 6 recruiting into armies: {r, unit, army} and {r, unit, new: 1}.
func _grid_recruit_army() -> void:
	var rome := _f("rome")
	var lat := _r("latium")
	var site := CGrid.site(lat)
	var st := _empty6()
	_italy(st, rome)
	st["factions"][rome]["treasury"] = 50000
	var key := _recruitable(st, rome, lat)
	_check(key != "" and int(CData.RECRUITS_PER_TURN[int(st["regions"][lat]["level"])]) == 3, "Roma recruits 3 a turn (%s)" % key)
	if key == "":
		return
	var price := UT.price_of(UT.index_of(key))
	var a := _put(st, rome, site, ["heavy", "spear"])
	var nb := -1
	for k in 8:
		var c := CGrid.at(CGrid.cx(site) + CGrid.DX[k], CGrid.cy(site) + CGrid.DY[k])
		if c >= 0 and CGrid.passable(c) and CGrid.region(c) >= 0:
			nb = c
			break
	var b := _put(st, rome, nb, ["cav"])
	var ida := int(a["id"])
	var idb := int(b["id"])
	var far := _put(st, rome, CState.field_cell(_r("bruttium")), ["spear"])
	# Validation.
	var p := CState.copy(st)
	_check(CRules.apply_order(p, rome, {"t": "recruit", "r": lat, "unit": key, "army": ida}) == "", "recruit into the army in the city")
	_check(int(p["factions"][rome]["treasury"]) == 50000 - price and str(CRules.queue_of(p, lat)) == str([[key, ida]]),
		"paid now, queued for that army (%s)" % str(CRules.queue_of(p, lat)))
	_check(CRules.mustering(p, ida) and not CRules.mustering(p, idb), "that army is mustering, the other is not")
	_check(CRules.apply_order(p, rome, {"t": "recruit", "r": lat, "unit": key, "army": idb}) == "", "an army next to the settlement recruits too")
	_check(CRules.apply_order(p, rome, {"t": "recruit", "r": lat, "unit": key, "new": 1}) == "", "a new army: the third slot")
	_check(CRules.apply_order(p, rome, {"t": "recruit", "r": lat, "unit": key, "army": ida}) == "recruitment full this turn",
		"the slots are shared by the armies and the new army")
	_check(CRules.apply_order(p, rome, {"t": "recruit", "r": lat, "unit": key}) == "recruitment full this turn", "and by the old form")
	_check(CRules.apply_order(CState.copy(st), rome, {"t": "recruit", "r": lat, "unit": key, "army": int(far["id"])}) == "not at the settlement",
		"an army away from the city cannot recruit there")
	_check(CRules.apply_order(CState.copy(st), rome, {"t": "recruit", "r": lat, "unit": key, "army": ida, "new": 1}) == "bad order",
		"army and new together are refused")
	_check(CRules.apply_order(CState.copy(st), rome, {"t": "recruit", "r": lat, "unit": key, "army": 999999}) == "no such army", "an unknown army is refused")
	# The cap counts the recruits already queued for the army.
	var p2 := CState.copy(st)
	var big := CState.army(p2, ida)
	for i in CData.ARMY_MAX - 3:
		(big["units"] as Array).append({"t": "spear", "n": 100})
	_check(CRules.apply_order(p2, rome, {"t": "recruit", "r": lat, "unit": key, "army": ida}) == "", "an army of 11 takes one recruit")
	_check(CRules.apply_order(p2, rome, {"t": "recruit", "r": lat, "unit": key, "army": ida}) == "the army is full",
		"not a second: %d units with the queued recruit" % CData.ARMY_MAX)
	# An allied player's city does not recruit for us.
	var st3 := _new6([rome, _f("carthage")])
	st3["armies"] = []
	var cart := _f("carthage")
	CState.set_dip(st3, rome, cart, CState.ALLIED)
	var camp := _r("campania")
	st3["regions"][camp]["owner"] = cart
	var ra := _put(st3, rome, CGrid.site(camp), ["heavy"])
	_check(CRules.recruit_region(st3, ra) == -1, "an allied city is not a recruiting place for us")
	_check(CRules.apply_order(st3, rome, {"t": "recruit", "r": camp, "unit": key, "army": int(ra["id"])}) == "not your region",
		"recruiting into our army at an ally's city is refused")
	_check(CRules.recruit_region(st, a) == lat and CRules.recruit_region(st, b) == lat and CRules.recruit_region(st, far) != lat,
		"recruit_region: on or next to our settlement (%d %d %d)" % [CRules.recruit_region(st, a), CRules.recruit_region(st, b), CRules.recruit_region(st, far)])
	# A turn: two armies and a new army share the slots.
	var orders := [{"t": "recruit", "r": lat, "unit": key, "army": ida}, {"t": "recruit", "r": lat, "unit": key, "army": idb},
		{"t": "recruit", "r": lat, "unit": key, "new": 1}]
	var s1 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, orders)])
	var s1b := CTurn.resolve_turn(st, [CTurn.submission(st, rome, orders)])
	_check(CState.state_hash(s1) == CState.state_hash(s1b), "recruiting into armies is deterministic")
	_check(CState.unit_count(CState.army(s1, ida)) == 3 and CState.unit_count(CState.army(s1, idb)) == 2, "each army gets its recruit")
	var raised: Array = []
	for x in CState.armies_of(s1, rome):
		if int(x["id"]) not in [ida, idb, int(far["id"])]:
			raised.append(x)
	_check(raised.size() == 1 and CState.unit_count(raised[0]) == 1 and CState.cell(raised[0]) == site,
		"the new army forms inside the walls (%d raised)" % raised.size())
	_check(not raised.is_empty() and not CState.army(s1, ida).is_empty() and CState.cell(CState.army(s1, ida)) == site,
		"the raised army is not gathered into the army in the city the turn it is raised")
	var no_qa := true
	for rs in s1["regions"]:
		no_qa = no_qa and not rs.has("qa") and (rs["queue"] as Array).is_empty()
	_check(no_qa, "no queue (and no qa) is left after the turn")
	var back := CState.from_json(CState.to_json(s1), int(s1["version"]))
	_check(CState.state_hash(back) == CState.state_hash(s1), "the state survives a JSON round trip")
	if not raised.is_empty():
		var s2 := CTurn.resolve_turn(s1, [])
		_check(CState.army(s2, int(raised[0]["id"])).is_empty() and CState.unit_count(CState.army(s2, ida)) == 4,
			"idle on the city's cell next turn, it gathers into the army there")
	# Several "new" recruits in one turn form one army.
	var s3 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [{"t": "recruit", "r": lat, "unit": key, "new": 1},
		{"t": "recruit", "r": lat, "unit": key, "new": 1}])])
	var n3 := CState.armies_of(s3, rome).size()
	_check(n3 == 4, "two new-army recruits raise one army (%d armies, was 3)" % n3)
	# Mustering: the army taking recruits does not march; its march is kept.
	var dest := CState.field_cell(_r("campania"))
	var s4 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [{"t": "recruit", "r": lat, "unit": key, "army": ida}, _move6(a, dest)])])
	var a4 := CState.army(s4, ida)
	var mf := _events(s4, "move_failed")
	_check(CState.cell(a4) == site and CState.unit_count(a4) == 3, "an army taking recruits stays where it is and gets them")
	_check(mf.size() == 1 and str(mf[0]["why"]) == "mustering" and int(mf[0]["army"]) == ida, "the move is refused: mustering")
	_check(int(a4.get("dest_x", -1)) == CGrid.cx(dest) and int(a4.get("dest_y", -1)) == CGrid.cy(dest), "its destination is kept")
	var s5 := CTurn.resolve_turn(s4, [])
	_check(CState.cell(CState.army(s5, ida)) != site, "next turn it marches on")
	var pv := CTurn.preview(st, rome, [{"t": "recruit", "r": lat, "unit": key, "army": ida}, _move6(a, dest)])
	_check((pv["errors"] as Array).size() == 1 and str(pv["errors"][0][1]) == "mustering", "the plan preview refuses its move: mustering")
	# The old form musters the army it will join.
	var p6 := CState.copy(st)
	_check(CRules.apply_order(p6, rome, {"t": "recruit", "r": lat, "unit": key}) == "" and str(CRules.queue_of(p6, lat)) == str([[key, ida]]),
		"an old-form recruit is queued for the first army at the city (%s)" % str(CRules.queue_of(p6, lat)))
	var s6 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [{"t": "recruit", "r": lat, "unit": key}, _move6(a, dest)])])
	_check(CState.cell(CState.army(s6, ida)) == site and CState.unit_count(CState.army(s6, ida)) == 3, "and that army musters too")
	_check(CState.cell(CState.army(s6, idb)) == nb, "the army next to it was free (it did not move without orders)")
	# Older formats do not know the targets.
	var o5 := CState.as_format(_new6([rome]), 5)
	o5["factions"][rome]["treasury"] = 50000
	var a5: Dictionary = CState.armies_of(o5, rome)[0]
	_check(CRules.apply_order(o5, rome, {"t": "recruit", "r": int(a5["r"]), "unit": key, "army": int(a5["id"])}) == "bad order",
		"format 5 refuses a recruit into an army")
	# Besieged: no recruiting, in any form.
	var sa := _r("samnium")
	var st7 := _empty6()
	st7["factions"][rome]["treasury"] = 50000
	var inside := _put(st7, rome, CGrid.site(sa), ["heavy"])
	var e := _put(st7, _f("epirus"), CState.ring_cell(sa, 4), ["spear", "spear"])
	CRules.start_siege(st7, sa, e, _r("apulia"))
	var k7 := _recruitable(st, rome, sa)
	if k7 == "":
		k7 = key
	_check(CRules.apply_order(st7, rome, {"t": "recruit", "r": sa, "unit": k7, "army": int(inside["id"])}) == "besieged"
		and CRules.apply_order(st7, rome, {"t": "recruit", "r": sa, "unit": k7, "new": 1}) == "besieged",
		"a besieged city recruits nothing (into an army or a new one)")


## The Skilled campaign AI (docs/AI.md 12): deterministic, its behaviours
## run, the knobs only it has are 0 at Easy and Average, the per-faction
## override is read, and Average / Easy campaigns are what they were before
## it existed (golden hashes and RNG state from the commit before step 4).
func _ai_skilled() -> void:
	# Average and Easy unchanged: an AI-only campaign of 20 turns, every
	# faction Average, then with Macedon Easy. (Without the camel and
	# elephant lines in the mixes, 2026-10-09: recruiting them is the only
	# change since.)
	CAI.no_beasts = true
	CData.no_generals = true  # (and without the starting generals, 2026-10-09)
	var g := CState.new_campaign("test", 4242, [])
	for t in 20:
		g = CTurn.resolve_turn(g, [])
	_check(CState.hash_text(g) == "63ea40c5" and int(g["rng"]) == 3394658370,
		"Average plays and draws the RNG exactly as before step 4 (%s, rng %d)" % [CState.hash_text(g), int(g["rng"])])
	var ge := CState.new_campaign("test", 4242, [])
	ge["factions"][_f("macedon")]["ai_skill"] = CP.EASY
	for t in 20:
		ge = CTurn.resolve_turn(ge, [])
	_check(CState.hash_text(ge) == "1379013c" and int(ge["rng"]) == 694925818,
		"an Easy faction plays exactly as before step 4 (%s, rng %d)" % [CState.hash_text(ge), int(ge["rng"])])
	CAI.no_beasts = false
	CData.no_generals = false
	# Knobs: every Skilled-only knob is 0 at Easy and Average.
	var zero := true
	for k in range(CP.SK_SUPPORT, CP.N_KNOBS):
		for lv in [CP.EASY, CP.AVERAGE]:
			for r in CP.KNOBS:
				if int(r[0]) == k and int(r[1 + lv]) != 0:
					zero = false
	_check(zero, "the Skilled knobs (SK_*) are 0 for Easy and Average")
	# The per-faction override over the campaign setting.
	var ov := CState.new_campaign("test", 4242, [], {"ai_campaign_skill": CP.EASY})
	ov["factions"][2]["ai_skill"] = CP.SKILLED
	_check(CP.skill(ov, 2) == CP.SKILLED and CP.skill(ov, 1) == CP.EASY and CP.of(ov, 2)[CP.SK_SUPPORT] == 1
		and CP.of(ov, 1)[CP.SK_SUPPORT] == 0, "factions[f].ai_skill overrides settings.ai_campaign_skill (Skilled knobs for that faction only)")
	# Determinism with Skilled factions and a player: same inputs, same state;
	# a save / load in the middle changes nothing.
	var s0 := _new6([0])
	for f in range(1, CState.nf()):
		s0["factions"][f]["ai_skill"] = CP.SKILLED
	var a := _play(CState.copy(s0), 16, -1)
	var b := _play(CState.copy(s0), 16, -1)
	var c := _play(CState.copy(s0), 16, 8)
	_check(CState.state_hash(a) == CState.state_hash(b), "Skilled: same inputs, same state after 16 turns (%s)" % CState.hash_text(a))
	_check(CState.state_hash(a) == CState.state_hash(c), "Skilled: save / load in the middle changes nothing (%s)" % CState.hash_text(c))
	var avg := _play(_new6([0]), 16, -1)
	_check(CState.state_hash(a) != CState.state_hash(avg), "Skilled factions play differently from Average ones")
	_check(_plain(a), "Skilled: the state holds only ints, strings, arrays and dictionaries")
	# One resolution from the same state and submissions, twice.
	var subs := [CTurn.submission(a, 0, [])]
	if str(a["phase"]) == "plan":
		_check(CState.state_hash(CTurn.resolve_turn(a, subs)) == CState.state_hash(CTurn.resolve_turn(a, subs)),
			"Skilled: one turn from the same state and submissions gives the same hash")
	# The Skilled behaviours run (counters, outside the state): an AI-only
	# campaign, every faction Skilled.
	CP.reset_counters()
	var sk := CState.new_campaign("test", 4242, [], {"ai_campaign_skill": CP.SKILLED})
	for t in 60:  # (60 turns since the generals, 2026-10-09: an army in danger falls back later)
		sk = CTurn.resolve_turn(sk, [])
	var used: Array = []
	for key in [CP.C_SK_TWO_TO_ONE, CP.C_SK_HUNT_DECLINED, CP.C_SK_TIMED, CP.C_SK_MERGE, CP.C_SK_RALLY, CP.C_SK_FALLBACK]:
		var n := 0
		for f in CState.nf():
			n += CP.counter(key, f)
		used.append("%s %d" % [key, n])
		_check(n > 0, "Skilled behaviour used in 60 AI turns: %s (%d)" % [key, n])
	var mk := 0
	for key in CP.MISTAKE_KEYS:
		for f in CState.nf():
			mk += CP.counter(key, f)
	_check(mk == 0, "Skilled makes no deliberate mistakes (%d)" % mk)
	CP.reset_counters()
