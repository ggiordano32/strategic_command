extends SceneTree
## Equal-force sieges on the shared town plan (docs/DESIGN.md "The town plan (shared)", phase C): the same
## armies, seeds and city dictionary fought on the generated map (--old) and on the overworld town's plan
## (CTown.battle_plan put in the city as "tp"), so the walls rows can be compared map for map.
##   godot --headless --script res://tests/town_balance.gd -- --set=west_town|west_city|polis|castrum
##       [--walls=0,1,2] [--seeds=16] [--seed0=0] [--old]
## West sets (walls 0-2, both sides the West attack list WEST_ATT, AI against AI, Average; walls 1-2 the
## attackers bring three ladder sets and a ram, a two-turn siege): west_town = Scenarios.west_town(12, 1, ...)
## on Cartagena's plan at level 1, west_city = west_town(13, 2, ...) on Havana's plan at level 2. Rome sets
## (walls 1-3, Scenarios.fair_siege, the full kit of a three-turn siege): polis on Athens' plan, castrum on
## Rome's (Latium's). Prints per wall level the attacker's wins, draws, minutes to decide, the men killed.
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTown := preload("res://campaign/ctown.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const MapGen := preload("res://sim/mapgen.gd")
const Terrain := preload("res://sim/terrain.gd")
const UT := preload("res://sim/unit_types.gd")


func _initialize() -> void:
	var set_name := "west_town"
	var walls_l: Array = []
	var seeds := 16
	var seed0 := 0
	var old := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--set="):
			set_name = a.get_slice("=", 1)
		elif a.begins_with("--walls="):
			for w in a.get_slice("=", 1).split(","):
				walls_l.append(int(w))
		elif a.begins_with("--seeds="):
			seeds = int(a.get_slice("=", 1))
		elif a.begins_with("--seed0="):
			seed0 = int(a.get_slice("=", 1))
		elif a == "--old":
			old = true
	var west := set_name.begins_with("west")
	if walls_l.is_empty():
		walls_l = [0, 1, 2] if west else [1, 2, 3]
	for walls in walls_l:
		var aw := 0
		var dr := 0
		var t_sum := 0.0
		var k_att := 0
		var k_def := 0
		var builds := 0
		for s in range(seed0, seed0 + seeds):
			var sc := _scenario(set_name, int(walls), s, old)
			var sim := BattleSim.new()
			sim.setup(sc, 53000 + s * 197)
			if int((sim.map_info.get("city", {}) as Dictionary).get("tp", 0)) == 1:
				builds += 1
			while sim.tick < sim.time_limit + 10 and sim.winner < 0:
				sim.step()
			var dt: float = (sim.decided_tick if sim.decided_tick >= 0 else sim.tick) / 600.0
			if sim.winner == 0:
				aw += 1
			elif sim.winner == 2 or sim.winner < 0:
				dr += 1
			t_sum += dt
			var res := sim.result()
			k_att += int(res["sides"][0]["killed"])
			k_def += int(res["sides"][1]["killed"])
		print("TOWNBAL %s %s walls %d: attacker %d / %d (%d %%), draws %d, %.1f min, killed att %.0f def %.0f (plan maps %d)" % [
			set_name, "old" if old else "plan", walls, aw, seeds, aw * 100 / maxi(seeds, 1), dr, t_sum / maxi(seeds, 1),
			float(k_att) / maxi(seeds, 1), float(k_def) / maxi(seeds, 1), builds])
	quit(0)


## The campaign town's plan at this level and walls (CTown.battle_plan).
func _tp(pack: String, key: String, level: int, walls: int) -> Dictionary:
	CData.use_pack(pack)
	var st := CState.new_campaign("bal", 5, [], {}, [], pack)
	var r := CData.region_index(key)
	st["regions"][r]["level"] = level
	var got := false
	for sl in st["regions"][r]["slots"]:
		if int(sl[0]) == CData.WALLS:
			sl[1] = walls
			got = true
	if not got:
		st["regions"][r]["slots"].append([CData.WALLS, walls])
	return CTown.battle_plan(st, r)


func _scenario(set_name: String, walls: int, s: int, old: bool) -> Dictionary:
	if set_name.begins_with("west"):
		var city_l := set_name == "west_city"
		var level := 2 if city_l else 1
		var att: Array = []
		for e in Scenarios.WEST_ATT:
			att.append([UT.index_of(str(e[0])), int(e[1])])
		var dfn: Array = att.duplicate(true)
		var kind := Terrain.K_HILL if city_l else Terrain.K_ROLLING
		var ground := MapGen.PAL_DRY if city_l else MapGen.PAL_GREEN
		var cseed := 13 if city_l else 12
		var terr := {"kind": kind, "seed": cseed * 7 + 3, "forest": MapGen.PALETTE_FOREST[ground] + 20, "ground": ground}
		var city := {"seed": cseed, "level": level, "walls": walls, "bld": [1, 2, 4], "plan": MapGen.CUL_LATIN, "coast": 1,
			"founder": MapGen.CUL_LATIN, "west": 1}
		if not old:
			city["tp"] = _tp("west", "havana" if city_l else "cartagena", level, walls)
		var eq := {"ladders": 3, "ram": 1} if walls > 0 else {}
		return Scenarios.settlement(city, terr, att, dfn, 1, [0, 1], eq)["scenario"]
	# Rome: fair_siege's city with the plan of a town of its culture.
	var plan := MapGen.PLAN_POLIS if set_name == "polis" else MapGen.PLAN_CASTRUM
	var eq2 := {"ladders": 3, "ram": 1, "mantlets": 4, "towers": 1 if walls >= 2 else 0,
		"extra": [[UT.index_of("scorpions"), 12]]}
	if old:
		return Scenarios.fair_siege(700 + s * 41, walls, plan, eq2)
	return Scenarios.fair_siege(700 + s * 41, walls, plan, eq2, _tp("rome", "attica" if plan == MapGen.PLAN_POLIS else "latium", 2, walls))
