extends RefCounted
## Custom battles: the setup (plain JSON-safe data, ints and strings) and
## the battle built from it. Pure and deterministic: both devices of an
## online custom battle build the same scenario from the same setup (the
## relay compares their hashes before the start).
##
## setup = {
##   "v": 1, "seed": int, "deploy": seconds (DEPLOY_CHOICES; -1 unlimited), "funds": FUNDS index,
##   "time": battle time limit in seconds (TIME_CHOICES; absent or 900 = the
##           sim's 15 minutes),
##   "map": {"kind": "field" | "settlement", "terrain": Terrain.K_*, "ground": MapGen.PAL_*,
##           "woods": 0-100, "mseed": int, "plan": MapGen.PLAN_*, "level": 0-2, "walls": 0-3,
##           "coast": 0/1, "def": defending sim side,
##           "ladders": 0/1, "ram": 0/1, "towers": 0-MAX_TOWERS (the attackers' siege
##           equipment, objects on the ground: LADDER_SETS sets of ladders, a ram,
##           siege towers; walls only, siege towers walls 2-3),
##           "works": 0-2 (field maps: both sides' field works as a Workshop of
##           that level, Scenarios.works_allowance), "fortified": -1 none / the
##           sim side standing in a fortified camp (its own works on top),
##           "river": -1 none / 0 ford / 1 bridge (field maps: a river crossing
##           between the armies from the map seed, side 1, or the fortified
##           side, holding the far bank; Scenarios "river")},
##   "sides": [{"skill": AIProfile level, "style": AIProfile personality,
##              "mantlets": 0 / 2 / 4 (MANTLET_CHOICES: that side's mantlets, any map),
##              "armies": [{"ctrl": "p1" | "p2" | "ai", "units": [[type key, men(, ammo kind key)], ...]}, ...]}, x2]
## }
## A unit's optional third element is the special ammunition kind it
## carries (a UnitTypes.AMMO key riding on its weapon; "" or absent: none),
## the scenario's "ak". An ammunition wagon (a type with a "wagon" row)
## stocks the special kinds its own army's units carry (the scenario's
## "aks"), as a campaign army's wagon does.
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

const LADDER_SETS := 3         # the Ladders toggle: sets of ladders (as a campaign siege of two turns)
const MAX_TOWERS := 2          # the Siege towers option: 0, 1 or 2 (as a campaign siege of three / four turns)
const MANTLET_CHOICES := [0, 2, 4]  # a side's Mantlets option (as a campaign siege of two / three turns)
const MAX_ARMIES := 3          # per side
const MAX_UNITS := 12          # per army (the campaign's army size)
const FUNDS := [0, 4500, 7500, 12000]
const FUNDS_NAMES := ["No limit", "Small (4,500)", "Medium (7,500)", "Large (12,000)"]
const DEPLOY_CHOICES := [0, 30, 60, 120, 300, -1]  # s; -1: unlimited (waits for every Ready)
const TIME_CHOICES := [600, 900, 1200, 1800, 2700, 3600, 36000]  # s; 36000: unlimited
const CTRL_NAMES := {"p1": "Player 1", "p2": "Player 2", "ai": "AI"}
## Heroes and agents a side may bring (docs/DESIGN.md "Heroes and agents"):
## a side's "chars" (keys, at most one of each) go in as the scenario's "chars".
const CHAR_KEYS: Array[String] = ["hero_foot", "hero_missile", "hero_cav", "hero_siege", "assassin", "diplomat"]
const FIELD_KINDS := [Terrain.K_FLAT, Terrain.K_ROLLING, Terrain.K_RIDGE, Terrain.K_VALLEY, Terrain.K_HILL,
	Terrain.K_SLOPE]
const SITE_KINDS := [Terrain.K_ROLLING, Terrain.K_FLAT, Terrain.K_HILL, Terrain.K_RIDGE]
## Templates: the sandbox's playable battles and test matchups as setups.
const TEMPLATES: Array[String] = ["skirmish", "battle_2000", "test_cav_archers", "test_cav_spears",
	"test_pike_front", "test_pike_flank", "test_archers_heavy", "test_bolt_pikes", "test_stone_line",
	"test_cav_art", "test_woods", "siege_town", "siege_city"]


## Settings (unit packs, UnitTypes.pack_of): the setup's optional "pack"
## (absent: "rome", so Rome setups are what they always were). The picker
## shows only the pack's rows, in these lines.
const PACKS: Array[String] = ["rome", "west"]
const PACK_NAMES := {"rome": "Rome", "west": "The West"}
const WEST_LINES: Array[String] = ["musket", "pike", "buccaneer", "heavy", "grenadier", "light", "archer", "cav", "pistol",
	"dragoon", "light_gun", "field_gun", "mortar"]
const WEST_ARMY := [["lancers", 60], ["musketeers", 100], ["w_pikemen", 120], ["musketeers", 100],
	["rodeleros", 100], ["buccaneers", 60], ["light_gun", 12], ["pistoleers", 60]]


static func pack_of(st: Dictionary) -> String:
	return str(st.get("pack", "rome"))


## The highest wall level a settlement map of the setup's pack offers. The
## West's towns are open towns with walls 0-2 (MapGen.is_west): walls 3 is the
## walled plans (Rome's), whose houses cannot be held (BattleSim._setup_occ).
static func max_walls(st: Dictionary) -> int:
	return 2 if pack_of(st) == "west" else 3


## The next wall level (cycling 0..max_walls) and the next plan (the West skips
## the Oppidum, the natives' stockade: not an open town, no holdable houses).
static func next_walls(st: Dictionary, w: int) -> int:
	return (w + 1) % (max_walls(st) + 1)


static func next_plan(st: Dictionary, p: int) -> int:
	var n := (p + 1) % (MapGen.PLAN_RING + 1)
	if pack_of(st) == "west" and n == MapGen.PLAN_OPPIDUM:
		n = MapGen.PLAN_RING
	return n


## A West settlement map with walls 3 or the Oppidum plan (an old saved or
## shared setup) is brought to the nearest open town, so Occupy works there.
static func fit_map(st: Dictionary) -> void:
	if pack_of(st) != "west" or not (st.get("map") is Dictionary):
		return
	var mp: Dictionary = st["map"]
	if mp.has("walls"):
		mp["walls"] = mini(int(mp["walls"]), 2)
	if int(mp.get("plan", MapGen.PLAN_RING)) == MapGen.PLAN_OPPIDUM:
		mp["plan"] = MapGen.PLAN_RING


## Switch the setup to pack `pack`: each side's armies become one army of
## the pack's standard layout (Player 1's at the bottom, the AI's at the top).
static func set_pack(st: Dictionary, pack: String) -> void:
	if pack == "rome":
		st.erase("pack")
	else:
		st["pack"] = pack
	var army: Array = WEST_ARMY if pack == "west" else (default_setup(0)["sides"][0]["armies"][0]["units"] as Array)
	for s in 2:
		st["sides"][s]["armies"] = [{"ctrl": "p1" if s == 0 else "ai", "units": army.duplicate(true)}]
	if st.get("sea") is Dictionary:
		st["sea"] = sea_default(pack)  # (R2: the ships on offer follow the setting)
	fit_map(st)


## The picker's lines for pack `pack` (Rome: the base lines with the light
## missile troops, beasts, dogs, engines and generals in their places).
static func picker_lines(pack: String) -> Array:
	if pack == "west":
		return WEST_LINES.duplicate()
	var lines: Array = UT.LINES.duplicate()
	lines.insert(lines.find("javelin") + 1, "sling")
	lines.insert(lines.find("sling") + 1, "dogs")  # War Dogs (handlers; the pack comes with them)
	lines.insert(lines.find("cav") + 1, "cav_missile")
	lines.insert(lines.find("cav_missile") + 1, "camel")  # Camel Riders
	lines.insert(lines.find("camel") + 1, "camel_archer")  # Camel Archers
	lines.insert(lines.find("camel_archer") + 1, "elephant")  # War Elephants
	lines.insert(lines.find("archer") + 1, "belly_bow")  # Gastraphetes
	lines.insert(lines.find("bolt"), "light_art")  # Scorpions (before the bolt throwers)
	lines.append("general")  # the general and his faction variants
	return lines


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
		var e := [UT.key_of(ty), int(ud["count"])]
		var ak := int(ud.get("ak", -1))
		if ammo_choices(ty).has(ak):
			e.append(UT.ammo_text(ak, "key"))
		line.append(e)
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


## Special ammunition kinds (UnitTypes.AMMO rows) a unit of type ty may
## carry: those riding on its weapon ([] for none).
static func ammo_choices(ty: int) -> Array[int]:
	if ty < 0:
		return []
	return UT.ammo_specials(ty)


## The special kind unit entry e carries (-1 none, or not one its weapon takes).
static func unit_ak(e: Array) -> int:
	if e.size() < 3:
		return -1
	var ak := UT.ammo_index(str(e[2]))
	return ak if ammo_choices(UT.index_of(str(e[0]))).has(ak) else -1


## Set (ak -1: clear) the special kind of unit entry e.
static func set_unit_ak(e: Array, ak: int) -> void:
	if e.size() > 2:
		e.resize(2)
	if ak >= 0:
		e.append(UT.ammo_text(ak, "key"))


static func is_wagon(ty: int) -> bool:
	return ty >= 0 and UT.stat(ty, "wagon") >= 0


## The special kinds an army's units carry (ascending): what its wagons stock.
static func army_kinds(army: Dictionary) -> Array:
	var out: Array = []
	for e in army["units"]:
		var ak := unit_ak(e)
		if ak >= 0 and not out.has(ak):
			out.append(ak)
	out.sort()
	return out


static func side_cost(st: Dictionary, s: int) -> int:
	var c := 0
	for a in st["sides"][s]["armies"]:
		for e in a["units"]:
			c += unit_cost(str(e[0]), int(e[1]))
	for k in chars_of(st, s):
		c += unit_cost(str(k), 1)
	return c


## The characters side s brings (CHAR_KEYS order, known rows only).
static func chars_of(st: Dictionary, s: int) -> Array:
	var have: Array = st["sides"][s].get("chars", [])
	var out: Array = []
	for k in CHAR_KEYS:
		if have.has(k) and UT.index_of(k) >= 0:
			out.append(k)
	return out


## Toggle character `key` for side s.
static func toggle_char(st: Dictionary, s: int, key: String) -> void:
	var have: Array = chars_of(st, s)
	if have.has(key):
		have.erase(key)
	else:
		have.append(key)
	st["sides"][s]["chars"] = have


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
	fit_map(st)
	var mp: Dictionary = st["map"]
	var ctrl_of := [[], []]   # per side: per unit (in setup order) its player or -1
	var lists := [[], []]     # per side: [ty, men]
	var extra := [[], []]     # per side: per unit the scenario's ammunition keys ({} none)
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
			var kinds := army_kinds(a)
			for e in a["units"]:
				var ty := UT.index_of(str(e[0]))
				if ty < 0:
					return {"error": "Unknown unit type %s." % str(e[0])}
				lists[s].append([ty, clampi(int(e[1]), 1, UT.size_of(ty) * 2)])
				ctrl_of[s].append(p)
				var x := {}
				if unit_ak(e) >= 0:
					x["ak"] = unit_ak(e)
				if is_wagon(ty) and not kinds.is_empty():
					x["aks"] = kinds.duplicate()
				extra[s].append(x)
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
		if pack_of(st) == "west":
			city["west"] = 1  # (an open Caribbean town: MapGen.is_west, phase W)
			city["coast"] = int(mp.get("coast", 0))
		var ground := int(mp.get("ground", MapGen.PAL_DRY))
		var terr := {"kind": int(mp.get("terrain", Terrain.K_ROLLING)), "seed": int(mp.get("mseed", 1)) * 7 + 3,
			"forest": clampi(int(mp.get("woods", 15)), 0, 100), "ground": ground}
		var equip := {}
		if int(mp.get("ladders", 0)) != 0:
			equip["ladders"] = LADDER_SETS
		if int(mp.get("ram", 0)) != 0:
			equip["ram"] = 1
		var n_tw := clampi(int(mp.get("towers", 0)), 0, MAX_TOWERS)
		if n_tw > 0:
			equip["towers"] = n_tw  # (Scenarios.settlement: walls 2-3 only)
		var r := Scenarios.settlement(city, terr, lists[att_side], lists[def_side], def_side, ai, equip)
		sc = r["scenario"]
		for k in (r["order"] as Array).size():
			var o: Array = r["order"][k]
			var s := att_side if int(o[0]) == 0 else def_side
			home.append(ctrl_of[s][int(o[1])])
			(sc["units"][k] as Dictionary).merge(extra[s][int(o[1])])
		# The city's towers (added by the sim): the defending side's lead player.
		home.append(players[def_side][0] if not (players[def_side] as Array).is_empty() else -1)
	else:
		sc = _field(st, lists, ctrl_of, home, extra)
		sc["ai_sides"] = ai
		sc["terrain"] = {"kind": int(mp.get("terrain", Terrain.K_ROLLING)), "seed": int(mp.get("mseed", 1)),
			"forest": clampi(int(mp.get("woods", 0)), 0, 100), "ground": int(mp.get("ground", MapGen.PAL_GREEN))}
		var fort := int(mp.get("fortified", -1))
		var rk := int(mp.get("river", -1))
		if rk == 0 or rk == 1:
			# A river crossing from the map seed (the same seed, the same
			# river; the ford and the bridge share it).
			var ms := int(mp.get("mseed", 1))
			sc["river"] = {"id": ms, "kind": rk, "seed": (ms * 31 + 17) & 0x7FFFFFFF, "bank": fort if fort == 0 else 1}
		sc["deploy_zones"] = Scenarios.field_zones(sc)
		var wl := clampi(int(mp.get("works", 0)), 0, Scenarios.WORKS_BY_WORKSHOP.size() - 1)
		var stakes := [0, 0]
		var caltrops := [0, 0]
		for s in 2:
			var w := Scenarios.works_allowance(wl, fort == s)
			stakes[s] = w[0]
			caltrops[s] = w[1]
		if stakes[0] + stakes[1] > 0:
			sc["stakes"] = stakes
		if caltrops[0] + caltrops[1] > 0:
			sc["caltrops"] = caltrops
		if fort == 0 or fort == 1:
			sc["fortified"] = fort
	var mt := [mantlets_of(st, 0), mantlets_of(st, 1)]
	if mt[0] + mt[1] > 0:
		sc["mantlets"] = mt  # (the sim stands them before each side's missile and artillery units)
	sc["ai_skill"] = skill
	sc["ai_style"] = style
	var chars := [[], []]
	for s in 2:
		for k in chars_of(st, s):
			(chars[s] as Array).append({"key": k, "name": UT.text(UT.index_of(k), "name")})
	if not (chars[0] as Array).is_empty() or not (chars[1] as Array).is_empty():
		sc["chars"] = chars  # (one-man units the sim adds after the scenario's; commanded by the side's first unit's player)
	var dt := int(st.get("deploy", 0))
	if dt != 0:
		sc["deploy_time"] = dt
	var tl := int(st.get("time", 900))
	if tl >= 60 and tl != 900:
		sc["time_limit"] = tl
	return {"scenario": sc, "seed": int(st.get("seed", 1)) & 0x7FFFFFFF, "home": home, "sides": players}


## Field battle: each side's armies one behind the other (the first in
## front, laid out as the campaign does), side 1 the mirror image of side 0.
static func _field(st: Dictionary, lists: Array, ctrl_of: Array, home: Array, extra: Array) -> Dictionary:
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
				var ud := Scenarios.unit(s, int(lists[s][i][0]), int(lists[s][i][1]), x, y, face)
				ud.merge(extra[s][i])
				units.append(ud)
				home.append(ctrl_of[s][i])
	return {"width_m": width, "height_m": height, "units": units}


## Side s's mantlets (one of MANTLET_CHOICES).
static func mantlets_of(st: Dictionary, s: int) -> int:
	var n := int(st["sides"][s].get("mantlets", 0))
	return n if MANTLET_CHOICES.has(n) else 0


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
		"funds": int(st.get("funds", 0)), "sides": sides, "time": int(st.get("time", 900)),
		"ladders": int(mp.get("ladders", 0)), "ram": int(mp.get("ram", 0)), "towers": int(mp.get("towers", 0)),
		"works": int(mp.get("works", 0)), "fortified": int(mp.get("fortified", -1)),
		"river": int(mp.get("river", -1)),
		"mantlets": [mantlets_of(st, 0), mantlets_of(st, 1)]}


# ------------------------------------------------------------ sea battles ---
# (N3a) The West setting's "Sea battle": the setup's optional "sea" {"on": 1,
# "ships": [[ship keys of side 0], [of side 1]], "wind": bearing it blows
# from, "str": 0-100, "water": 0 open / 1 an island / 2 a coast to the north,
# "start": "ns" | "gauge0" (your fleet upwind) | "gauge1" (downwind)}. Side 0
# is Player 1's, side 1 the battle AI's (solo only). Built for sim/sea_sim.gd.

const SEA_SHIPS: Array[String] = ["sloop", "brigantine", "frigate", "galleon", "ship_of_the_line", "war_canoe", "fire_ship"]
## (R2, Rome's navy) Rome's setting: the oared galleys and the merchantman.
const SEA_SHIPS_ROME: Array[String] = ["lembos", "trireme", "quinquereme", "quinquereme_p", "corbita"]
const SEA_MAX := 8
const SEA_WATER_NAMES := ["Open sea", "An island", "A coast to the north"]
const SEA_START_NAMES := {"ns": "Fleets meet across the wind", "gauge0": "Your fleet upwind (the weather gauge)",
	"gauge1": "Your fleet downwind"}


static func sea_on(st: Dictionary) -> bool:
	return st.get("sea") is Dictionary and int(st["sea"].get("on", 0)) != 0


## The ships on offer in setting `pack` (the West's list unchanged).
static func sea_ships(pack: String) -> Array[String]:
	return SEA_SHIPS_ROME if pack == "rome" else SEA_SHIPS


static func sea_default(pack: String = "west") -> Dictionary:
	if pack == "rome":
		# The Mediterranean: a north-westerly (the pack's WIND_FROM_DEG), triremes and a quinquereme a side.
		return {"on": 1, "ships": [["trireme", "trireme", "trireme", "quinquereme"], ["trireme", "trireme", "trireme", "quinquereme_p"]],
			"wind": 315, "str": 55, "water": 0, "start": "ns"}
	return {"on": 1, "ships": [["frigate", "sloop"], ["frigate", "brigantine"]], "wind": 90, "str": 70, "water": 0,
		"start": "ns"}


static func sea_check(st: Dictionary) -> String:
	var sea: Dictionary = st["sea"]
	for s in 2:
		var n := (sea["ships"][s] as Array).size()
		if n == 0:
			return "Each side needs a ship."
		if n > SEA_MAX:
			return "At most %d ships a side." % SEA_MAX
	return ""


static func build_sea(st: Dictionary) -> Dictionary:
	var why := sea_check(st)
	if why != "":
		return {"error": why}
	var sea: Dictionary = st["sea"]
	var units: Array = []
	for s in 2:
		for k in sea["ships"][s]:
			units.append({"side": s, "t": str(k)})
	var land := {"kind": 0, "mseed": int(st.get("seed", 1)) % 100000}
	match int(sea.get("water", 0)):
		1:
			land["kind"] = 1
		2:
			land["kind"] = 2
			land["dirs"] = (1 << 6) | (1 << 5) | (1 << 7)
	var lay := str(sea.get("start", "ns"))
	if lay == "ns" and int(sea.get("water", 0)) == 2:
		lay = "we"
	var scn := {"sea": 1, "wind_deg": int(sea.get("wind", 90)), "wind_str": int(sea.get("str", 70)), "ai_sides": [0, 1],
		"land": land, "layout": lay, "units": units, "time_limit": int(st.get("time", 900)),
		"ai_skill": [clampi(int(st["sides"][0].get("skill", AIProfile.AVERAGE)), 0, 2), clampi(int(st["sides"][1].get("skill", AIProfile.AVERAGE)), 0, 2)]}
	return {"sea": 1, "scenario": scn, "seed": int(st.get("seed", 1))}
