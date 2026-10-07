extends RefCounted
## Custom battles: the setup (plain JSON-safe data, ints and strings) and
## the battle built from it. Pure and deterministic: both devices of an
## online custom battle build the same scenario from the same setup (the
## relay compares their hashes before the start).
##
## setup = {
##   "v": 1, "seed": int, "deploy": seconds (0 / 60 / 120), "funds": FUNDS index,
##   "map": {"kind": "field" | "settlement", "terrain": Terrain.K_*, "ground": MapGen.PAL_*,
##           "woods": 0-100, "mseed": int, "plan": MapGen.PLAN_*, "level": 0-2, "walls": 0-3,
##           "coast": 0/1, "def": defending sim side},
##   "sides": [{"skill": AIProfile level, "style": AIProfile personality,
##              "armies": [{"ctrl": "p1" | "p2" | "ai", "units": [[type key, men], ...]}, ...]}, x2]
## }
## Side 0 deploys at the bottom, side 1 at the top. Controllers: an army of
## Player 1 / Player 2 is commanded by that player; a side with no player's
## army is fought by the battle AI at the side's skill and personality. The
## battle AI commands whole sides (sim/battle_sim.gd ai_sides), so an "AI"
## army on a side that also has a player's army is commanded by that side's
## (lowest) player, like AI allies in campaign co-op.

const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const Terrain := preload("res://sim/terrain.gd")
const MapGen := preload("res://sim/mapgen.gd")
const AIProfile := preload("res://sim/ai_profile.gd")

const MAX_ARMIES := 3          # per side
const MAX_UNITS := 12          # per army (the campaign's army size)
const FUNDS := [0, 4500, 7500, 12000]
const FUNDS_NAMES := ["No limit", "Small (4,500)", "Medium (7,500)", "Large (12,000)"]
const DEPLOY_CHOICES := [0, 60, 120]
const CTRL_NAMES := {"p1": "Player 1", "p2": "Player 2", "ai": "AI"}
const FIELD_KINDS := [Terrain.K_FLAT, Terrain.K_ROLLING, Terrain.K_RIDGE, Terrain.K_VALLEY, Terrain.K_HILL,
	Terrain.K_SLOPE]
const SITE_KINDS := [Terrain.K_ROLLING, Terrain.K_FLAT, Terrain.K_HILL, Terrain.K_RIDGE]
## Templates: the sandbox's playable battles and test matchups as setups.
const TEMPLATES: Array[String] = ["skirmish", "battle_2000", "test_cav_archers", "test_cav_spears",
	"test_pike_front", "test_pike_flank", "test_archers_heavy", "test_bolt_pikes", "test_stone_line",
	"test_cav_art", "test_woods", "siege_town", "siege_city"]


## A plain starting setup: two armies of the campaign's standard layout.
static func default_setup(p_seed: int) -> Dictionary:
	var army := [["cav", 60], ["heavy", 100], ["pike", 120], ["heavy", 100], ["spear", 100], ["archer", 80],
		["javelin", 60], ["cav", 60]]
	return {"v": 1, "seed": p_seed, "deploy": 60, "funds": 0,
		"map": {"kind": "field", "terrain": Terrain.K_ROLLING, "ground": MapGen.PAL_GREEN, "woods": 15,
			"mseed": p_seed % 100000, "plan": MapGen.PLAN_CASTRUM, "level": 1, "walls": 1, "coast": 0, "def": 1},
		"sides": [{"skill": AIProfile.AVERAGE, "style": AIProfile.BALANCED, "armies": [{"ctrl": "p1", "units": army.duplicate(true)}]},
			{"skill": AIProfile.AVERAGE, "style": AIProfile.BALANCED, "armies": [{"ctrl": "ai", "units": army.duplicate(true)}]}]}


## A template (one of TEMPLATES) as a setup: each side's units as one army
## (Player 1 the bottom side, the AI the top).
static func template(id: String, p_seed: int) -> Dictionary:
	var st := default_setup(p_seed)
	var sc := Scenarios.make(id)
	var lists := [[], []]
	for ud in sc["units"]:
		var s := int(ud["side"])
		var ty := int(ud["type"])
		var line: Array = lists[s]
		line.append([UT.key_of(ty), int(ud["count"])])
	for s in 2:
		var all: Array = lists[s]
		var armies: Array = []
		var k := 0
		while k < all.size():
			armies.append({"ctrl": "p1" if s == 0 else "ai", "units": all.slice(k, k + MAX_UNITS)})
			k += MAX_UNITS
		st["sides"][s]["armies"] = armies.slice(0, MAX_ARMIES)
	var terr: Dictionary = sc.get("terrain", {})
	var mp: Dictionary = st["map"]
	if terr.has("city"):
		var c: Dictionary = terr["city"]
		mp["kind"] = "settlement"
		mp["level"] = int(c.get("level", 1))
		mp["walls"] = int(c.get("walls", 1))
		mp["plan"] = int(c.get("plan", MapGen.PLAN_RING))
		mp["coast"] = int(c.get("coast", 0))
		mp["mseed"] = int(c.get("seed", 1))
		mp["def"] = int(c.get("def", 1))
		mp["terrain"] = int(terr.get("kind", Terrain.K_ROLLING))
		mp["ground"] = int(terr.get("ground", MapGen.PAL_DRY))
	else:
		mp["kind"] = "field"
		var k2 := int(terr.get("kind", Terrain.K_FLAT))
		mp["terrain"] = k2 if FIELD_KINDS.has(k2) else Terrain.K_FLAT
		mp["woods"] = 30 if id == "test_woods" else 0
		mp["ground"] = MapGen.PAL_GREEN if id == "test_woods" else MapGen.PAL_DRY
	return st


static func template_title(id: String) -> String:
	return Scenarios.title(id).trim_prefix("Test: ")


## Price of a unit of type key with `men` men (campaign prices).
static func unit_cost(key: String, men: int) -> int:
	var ty := UT.index_of(key)
	if ty < 0:
		return 0
	return UT.price_of(ty) * men / maxi(UT.size_of(ty), 1)


static func side_cost(st: Dictionary, s: int) -> int:
	var c := 0
	for a in st["sides"][s]["armies"]:
		for e in a["units"]:
			c += unit_cost(str(e[0]), int(e[1]))
	return c


## Who controls side s: the players with an army on it ([] = the AI).
static func side_players(st: Dictionary, s: int) -> Array:
	var out: Array = []
	for a in st["sides"][s]["armies"]:
		var c := str(a["ctrl"])
		var p := 0 if c == "p1" else (1 if c == "p2" else -1)
		if p >= 0 and not out.has(p):
			out.append(p)
	out.sort()
	return out


## The side player p fights on (-1: none).
static func side_of_player(st: Dictionary, p: int) -> int:
	for s in 2:
		if side_players(st, s).has(p):
			return s
	return -1


## Problems that stop the battle ("" if none).
static func check(st: Dictionary, online: bool) -> String:
	for s in 2:
		var armies: Array = st["sides"][s]["armies"]
		if armies.is_empty():
			return "Each side needs an army."
		var n := 0
		for a in armies:
			if (a["units"] as Array).size() > MAX_UNITS:
				return "An army has more than %d units." % MAX_UNITS
			n += (a["units"] as Array).size()
		if n == 0:
			return "Each side needs at least one unit."
		var budget: int = FUNDS[clampi(int(st.get("funds", 0)), 0, FUNDS.size() - 1)]
		if budget > 0 and side_cost(st, s) > budget:
			return "Side %d is over its funds (%d of %d)." % [s + 1, side_cost(st, s), budget]
	if side_of_player(st, 0) < 0:
		return "Player 1 needs an army."
	if online and side_of_player(st, 1) < 0:
		return "Player 2 needs an army to play online."
	for s in 2:
		if side_players(st, s).size() > 1 and side_players(st, 1 - s).size() > 0:
			return "Two players on one side and one on the other: not supported."
	return ""


## Build the battle: {scenario, seed, home (per sim unit: player 0 / 1, -1
## the AI), sides [players of side 0, of side 1]} or {error}. solo: Player
## 2's armies count as AI (on Player 1's side: Player 1 commands them).
static func build(st: Dictionary, solo: bool = false) -> Dictionary:
	var why := check(st, false)
	if why != "":
		return {"error": why}
	var mp: Dictionary = st["map"]
	var ctrl_of := [[], []]   # per side: per unit (in setup order) its player or -1
	var lists := [[], []]     # per side: [ty, men]
	var players := [side_players(st, 0), side_players(st, 1)]
	if solo:
		for s in 2:
			players[s] = [0] if (players[s] as Array).has(0) else []
	for s in 2:
		var lead: int = players[s][0] if not (players[s] as Array).is_empty() else -1
		for a in st["sides"][s]["armies"]:
			var c := str(a["ctrl"])
			var p := 0 if c == "p1" else (1 if c == "p2" else -1)
			if not (players[s] as Array).has(p):
				p = lead
			for e in a["units"]:
				var ty := UT.index_of(str(e[0]))
				if ty < 0:
					return {"error": "Unknown unit type %s." % str(e[0])}
				lists[s].append([ty, clampi(int(e[1]), 1, UT.size_of(ty) * 2)])
				ctrl_of[s].append(p)
	var ai: Array = []
	for s in 2:
		if (players[s] as Array).is_empty():
			ai.append(s)
	var skill := [int(st["sides"][0].get("skill", AIProfile.AVERAGE)), int(st["sides"][1].get("skill", AIProfile.AVERAGE))]
	var style := [int(st["sides"][0].get("style", AIProfile.BALANCED)), int(st["sides"][1].get("style", AIProfile.BALANCED))]
	var sc: Dictionary
	var home: Array = []
	if str(mp.get("kind", "field")) == "settlement":
		var def_side := clampi(int(mp.get("def", 1)), 0, 1)
		var att_side := 1 - def_side
		var city := {"seed": int(mp.get("mseed", 1)), "level": clampi(int(mp.get("level", 1)), 0, 2),
			"walls": clampi(int(mp.get("walls", 1)), 0, 3), "bld": [1, 2, 4]}
		if int(mp.get("plan", MapGen.PLAN_RING)) != MapGen.PLAN_RING:
			city["plan"] = int(mp["plan"])
			city["coast"] = int(mp.get("coast", 0))
		var ground := int(mp.get("ground", MapGen.PAL_DRY))
		var terr := {"kind": int(mp.get("terrain", Terrain.K_ROLLING)), "seed": int(mp.get("mseed", 1)) * 7 + 3,
			"forest": clampi(int(mp.get("woods", 15)), 0, 100), "ground": ground}
		var r := Scenarios.settlement(city, terr, lists[att_side], lists[def_side], def_side, ai)
		sc = r["scenario"]
		for o in r["order"]:
			var s := att_side if int(o[0]) == 0 else def_side
			home.append(ctrl_of[s][int(o[1])])
	else:
		sc = _field(st, lists, ctrl_of, home)
		sc["ai_sides"] = ai
		sc["terrain"] = {"kind": int(mp.get("terrain", Terrain.K_ROLLING)), "seed": int(mp.get("mseed", 1)),
			"forest": clampi(int(mp.get("woods", 0)), 0, 100), "ground": int(mp.get("ground", MapGen.PAL_GREEN))}
		sc["deploy_zones"] = Scenarios.field_zones(sc)
	sc["ai_skill"] = skill
	sc["ai_style"] = style
	var dt := int(st.get("deploy", 0))
	if dt > 0:
		sc["deploy_time"] = dt
	return {"scenario": sc, "seed": int(st.get("seed", 1)) & 0x7FFFFFFF, "home": home, "sides": players}


## Field battle: each side's armies one behind the other (the first in
## front, laid out as the campaign does), side 1 the mirror image of side 0.
static func _field(st: Dictionary, lists: Array, ctrl_of: Array, home: Array) -> Dictionary:
	var lays := [[], []]
	var width := 560
	var depth := [0, 0]
	for s in 2:
		var k := 0
		for a in st["sides"][s]["armies"]:
			var n := (a["units"] as Array).size()
			var sub: Array = lists[s].slice(k, k + n)
			var lay := Scenarios.army_layout(sub)
			lays[s].append({"lay": lay, "first": k, "back": depth[s]})
			depth[s] += int(lay["depth"]) + 35
			width = maxi(width, int(lay["width"]) + 160)
			k += n
	var height := 560 + maxi(maxi(depth[0], depth[1]) - 60, 0) * 2
	width -= width % 4
	var units: Array = []
	for s in 2:
		for g in lays[s]:
			var lay: Dictionary = g["lay"]
			for p in lay["placed"]:
				var i := int(g["first"]) + int(p["i"])
				var x := width / 2 + int(p["x"])
				var y := height / 2 + 100 + int(g["back"]) + int(p["back"])
				var face := Scenarios.FACE_UP
				if s == 1:
					x = width - x
					y = height - y
					face = Scenarios.FACE_DOWN
				units.append(Scenarios.unit(s, int(lists[s][i][0]), int(lists[s][i][1]), x, y, face))
				home.append(ctrl_of[s][i])
	return {"width_m": width, "height_m": height, "units": units}


## A one-line summary (telemetry, the lobby).
static func summary(st: Dictionary) -> Dictionary:
	var mp: Dictionary = st["map"]
	var sides: Array = []
	for s in 2:
		var men := 0
		var units := 0
		var ctrl: Array = []
		for a in st["sides"][s]["armies"]:
			ctrl.append(str(a["ctrl"]))
			for e in a["units"]:
				men += int(e[1])
				units += 1
		sides.append({"armies": ctrl, "units": units, "men": men, "cost": side_cost(st, s),
			"skill": int(st["sides"][s].get("skill", 1)), "style": int(st["sides"][s].get("style", 1))})
	return {"map": str(mp.get("kind", "field")), "terrain": int(mp.get("terrain", 0)), "deploy": int(st.get("deploy", 0)),
		"funds": int(st.get("funds", 0)), "sides": sides}
