extends RefCounted
## Campaign state: one JSON-serialisable Dictionary (string keys; ints,
## strings, arrays and dictionaries only, no floats, no bools), so a whole
## campaign saves, loads and (milestone 4) uploads as one blob. This file
## creates a new campaign, (de)serialises and hashes the state, and holds the
## read-only queries the rules, the AI and the view share. Rules that change
## the state are in crules.gd.
##
## Determinism: everything is integer; iteration is always over arrays in
## index order; dictionaries are only used for lookups by key, never iterated
## by the rules (JSON load does not keep key order). The state carries its own
## RNG ("rng", xorshift32) used by the rules and the AI.
##
## Format (VERSION 5; version 1 has no city_seed, versions 1-2 no builder
## data "built", versions 1-3 no "sieges", versions 1-4 no free movement
## (army mp / dest / mode / stance / idle); older states are migrated on
## load, see migrate()), all top-level keys:
##   format "strategic_command_campaign", version, name, seed, turn (0 =
##   280 BC summer), phase ("plan" | "battles" | "over"), rng,
##   settings {victory_regions, victory_capitals, turn_timeout_h, autoresolve
##     ("ask" | "auto"), ai_aggression (50-150, %)},
##   humans [faction ...] (permanently allied),
##   factions [{alive, treasury, next_army, income, upkeep, war_turns}]
##     indexed like CData.FACTIONS,
##   dip [n*n] 0 war / 1 peace / 2 trade / 3 allied; dip_turn [n*n] turn of
##     the last change,
##   regions [{owner (-1 independent), level, growth, slots [[chain, level]],
##     build [chain, level, turns_left] or [], queue [unit keys], gar (garrison
##     strength %), city_seed (the settlement's battle map seed: fixed for
##     good, so a city always looks the same; see default_city_seed),
##     built [[chain, level, culture]...] (version 3: who built what, in
##     order: a building chain's level completing, chain -1 = the settlement
##     growing to that level; the culture of the owner then, MapGen.CUL_*;
##     view only: post-conquest buildings in the owner's style; anything
##     not listed is in the founder's style, see builder_culture)}]
##     indexed like CData.REGIONS,
##   armies [{id, f, r, units [{t: unit key, n: men}], from (region it came
##     from this turn, -1), moved (0/1), busy (0/1: committed to a battle);
##     version 5: mp (movement points left this turn), dest (-1 or the
##     region it is marching to over several turns), mode (what it does on
##     arriving at dest: MODE_SIEGE, MODE_ASSAULT, MODE_MARCH), stance
##     (STANCE_FIELD, STANCE_GARRISON), idle (turns without moving: the AI)}]
##     sorted by id,
##   battles [pending battle, see crules.gd], next_battle,
##   sieges [{r, f (besieging faction), turn (started), supply (turns of
##     supplies left), held (turns maintained without an assault), from
##     [[army id, region it came from]...]}] sorted by region (version 4;
##     a state without the key plays without sieges, see sieges_on),
##   proposals [{id, from, to, what, turn}] (AI proposals to humans),
##   next_proposal, events [{turn, k, ...}] (what happened, for the turn
##   summary), winner (-1 none, 1 players won, 0 players lost), stats {}.

const CData := preload("res://campaign/cdata.gd")
const UT := preload("res://sim/unit_types.gd")

const FORMAT := "strategic_command_campaign"
const VERSION := 5
## Oldest format this build reads (older states are migrated on load).
const MIN_VERSION := 1

const WAR := 0
const PEACE := 1
const TRADE := 2
const ALLIED := 3
const DIP_NAMES: Array[String] = ["War", "Peace", "Trade", "Allied"]

const DEFAULT_SETTINGS := {"victory_regions": 20, "victory_capitals": 3, "turn_timeout_h": 0,
	"autoresolve": "ask", "ai_aggression": 100}
const TIMEOUT_CHOICES := [0, 12, 24, 48, 72]


## A new campaign. humans: faction indices (1 or 2).
static func new_campaign(p_name: String, p_seed: int, humans: Array, settings: Dictionary = {}) -> Dictionary:
	var n_f := CData.faction_count()
	var st := {"format": FORMAT, "version": VERSION, "name": p_name, "seed": p_seed, "turn": 0,
		"phase": "plan", "winner": -1}
	var rng := ((p_seed & 0x7FFFFFFF) * 1103515245 + 12345) & 0xFFFFFFFF
	st["rng"] = rng if rng != 0 else 0x5EED
	var s := DEFAULT_SETTINGS.duplicate()
	for k in settings:
		s[k] = settings[k]
	st["settings"] = s
	var hs: Array = []
	for h in humans:
		hs.append(int(h))
	hs.sort()
	st["humans"] = hs
	var regions: Array = []
	for r in CData.region_count():
		var rd: Dictionary = CData.REGIONS[r]
		regions.append({"owner": -1, "level": int(rd["level"]), "growth": int(CData.GROWTH_TO[int(rd["level"])]),
			"slots": [], "build": [], "queue": [], "gar": 100, "city_seed": default_city_seed(r),
			"built": []})
		var wall_lvl := int(rd["walls"])
		if wall_lvl > 0:
			(regions[r]["slots"] as Array).append([CData.WALLS, wall_lvl])
	var factions: Array = []
	var armies: Array = []
	for f in n_f:
		var fd: Dictionary = CData.FACTIONS[f]
		var fs := {"alive": 1, "treasury": int(fd["treasury"]), "next_army": 1, "income": 0,
			"upkeep": 0, "war_turns": 0}
		factions.append(fs)
		for key in fd["regions"]:
			var r := CData.region_index(key)
			regions[r]["owner"] = f
			var start: Array = CData.START_TOWN
			var lvl := int(regions[r]["level"])
			if key == fd["capital"]:
				start = CData.START_CAPITAL_CITY if lvl == CData.CITY else CData.START_CAPITAL_TOWN
			elif lvl == CData.CITY:
				start = CData.START_CITY
			elif lvl == CData.VILLAGE:
				start = [[CData.FARM, 1]]
			for b in start:
				if b[0] == CData.MARKET and lvl < CData.CITY and key != fd["capital"]:
					continue
				_add_building(regions[r], int(b[0]), int(b[1]), slot_count(r, lvl))
		for ad in fd["armies"]:
			var units: Array = []
			for k in ad[1]:
				var ty := UT.index_of(k)
				assert(ty >= 0, "unknown unit " + str(k))
				units.append({"t": k, "n": UT.size_of(ty)})
			var na := {"id": f * 100000 + int(fs["next_army"]), "f": f,
				"r": CData.region_index(ad[0]), "units": units, "from": -1, "moved": 0, "busy": 0}
			army_defaults(na)
			armies.append(na)
			fs["next_army"] = int(fs["next_army"]) + 1
	armies.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	st["regions"] = regions
	st["factions"] = factions
	st["armies"] = armies
	var dip_arr: Array = []
	var dip_turn: Array = []
	for i in n_f * n_f:
		dip_arr.append(PEACE)
		dip_turn.append(0)
	st["dip"] = dip_arr
	st["dip_turn"] = dip_turn
	for w in CData.START_WARS:
		set_dip(st, CData.faction_index(w[0]), CData.faction_index(w[1]), WAR)
	for a in hs:
		for b in hs:
			if a != b:
				set_dip(st, a, b, ALLIED)
	st["battles"] = []
	st["next_battle"] = 1
	st["sieges"] = []
	st["proposals"] = []
	st["next_proposal"] = 1
	st["events"] = []
	st["stats"] = {"battles": 0, "battles_formula": 0, "battles_auto": 0, "battles_fought": 0}
	return st


static func _add_building(rs: Dictionary, chain: int, level: int, slots: int) -> void:
	for s in rs["slots"]:
		if int(s[0]) == chain:
			s[1] = maxi(int(s[1]), level)
			return
	if (rs["slots"] as Array).size() < slots:
		(rs["slots"] as Array).append([chain, level])


# ------------------------------------------------------- serialisation ---

static func to_json(st: Dictionary) -> String:
	return JSON.stringify(st, "", true)


## Parse a saved state. Returns {} on failure (bad JSON, wrong format or a
## newer version). Numbers come back from JSON as floats: normalise() turns
## every integral float back into an int.
static func from_json(text: String) -> Dictionary:
	var v = JSON.parse_string(text)
	if not (v is Dictionary):
		return {}
	var st: Dictionary = normalise(v)
	if str(st.get("format", "")) != FORMAT or int(st.get("version", 0)) > VERSION \
			or int(st.get("version", 0)) < MIN_VERSION:
		return {}
	return migrate(st)


## Bring a state of an older format up to VERSION (in place; returns it).
## 4 -> 5: free movement: every army gets full points, no destination,
## field stance (army_defaults).
## 3 -> 4: no sieges yet (an empty "sieges" list switches the siege rules on).
## 2 -> 3: every settlement gets an empty builder list "built".
## 1 -> 2: every settlement gets its city_seed (default_city_seed, the same
## value a new campaign gives it, so migrating on two devices agrees).
## Online campaigns are not migrated (the server keeps the format a campaign
## was created with): rules read city_seed() which falls back to the same
## default, so a format 1 state plays exactly like its migrated copy.
static func migrate(st: Dictionary) -> Dictionary:
	if int(st.get("version", 0)) < 2:
		var regions: Array = st.get("regions", [])
		for r in regions.size():
			var rs: Dictionary = regions[r]
			if not rs.has("city_seed"):
				rs["city_seed"] = default_city_seed(r)
		st["version"] = 2
	if int(st.get("version", 0)) < 3:
		# 2 -> 3: builder data; an empty list = everything in the founder's
		# style (exactly what an unmigrated state shows).
		var regions3: Array = st.get("regions", [])
		for r in regions3.size():
			var rs3: Dictionary = regions3[r]
			if not rs3.has("built"):
				rs3["built"] = []
		st["version"] = 3
	if int(st.get("version", 0)) < 4:
		if not st.has("sieges"):
			st["sieges"] = []
		st["version"] = 4
	if int(st.get("version", 0)) < 5:
		for a in st.get("armies", []):
			army_defaults(a)
		st["version"] = 5
	return st


## Free movement keys of a version 5 army (missing ones only): full points,
## no destination, march mode, field stance, not idle.
static func army_defaults(a: Dictionary) -> void:
	if not a.has("mp"):
		a["mp"] = max_mp(a)
	if not a.has("dest"):
		a["dest"] = -1
	if not a.has("mode"):
		a["mode"] = CData.MODE_MARCH
	if not a.has("stance"):
		a["stance"] = CData.STANCE_FIELD
	if not a.has("idle"):
		a["idle"] = 0


## Free movement rules apply (state version 5 and later). An unmigrated
## online campaign of format 1-4 keeps one region a turn, entering hostile
## land lays siege or attacks, and land-adjacent reinforcement.
static func moves_on(st: Dictionary) -> bool:
	return int(st.get("version", 0)) >= 5


## Movement points a turn of army a (its slowest arm): cavalry only MP_CAV,
## any artillery MP_ART, else MP_FOOT.
static func max_mp(a: Dictionary) -> int:
	var all_cav := true
	var units: Array = a.get("units", [])
	for u in units:
		var c := UT.cls(unit_type(u))
		if c == UT.CLS_ART:
			return CData.MP_ART
		if c != UT.CLS_CAV:
			all_cav = false
	return CData.MP_CAV if all_cav and not units.is_empty() else CData.MP_FOOT


## Points army a has left this turn.
static func mp(a: Dictionary) -> int:
	return int(a.get("mp", max_mp(a)))


static func stance(a: Dictionary) -> int:
	return int(a.get("stance", CData.STANCE_FIELD))


## Note that chain `chain` (-1: the settlement itself) reached `level` in
## region r, built by its owner now (independent: the founder's culture).
## Only states of format 3 keep this (an unmigrated online format 1-2 state
## never gains the key, so every client on it computes the same state).
static func record_built(st: Dictionary, r: int, chain: int, level: int) -> void:
	var rs: Dictionary = st["regions"][r]
	if not rs.has("built"):
		return
	(rs["built"] as Array).append([chain, level, owner_culture(st, r)])


## Culture of region r's owner (independent: the founder's).
static func owner_culture(st: Dictionary, r: int) -> int:
	var o := owner(st, r)
	return CData.faction_culture(o) if o >= 0 else CData.region_culture(r)


## Culture that built level `level` of chain `chain` (-1: the settlement
## level) in region r: the last matching builder entry, else the founder.
static func builder_culture(st: Dictionary, r: int, chain: int, level: int) -> int:
	var rs: Dictionary = st["regions"][r]
	var out := CData.region_culture(r)
	var b: Array = rs.get("built", [])
	for e in b:
		if int(e[0]) == chain and int(e[1]) == level:
			out = int(e[2])
	return out


## The battle map seed a settlement is given when its campaign starts
## (derived from the region index only: every campaign has the same Roma).
static func default_city_seed(r: int) -> int:
	var h := (r + 1) * 2654435761 + 0x5CA1AB1E
	h = (h ^ (h >> 15)) * 0x2C1B3C6D
	return (h ^ (h >> 12)) & 0x7FFFFFFF


## Settlement r's battle map seed (stored, or the default for a format 1
## state, which is the same number).
static func city_seed(st: Dictionary, r: int) -> int:
	var rs: Dictionary = st["regions"][r]
	return int(rs.get("city_seed", default_city_seed(r)))


## Deep copy with floats turned into ints (JSON numbers) and bools into 0/1.
static func normalise(v):
	if v is float:
		return int(v)
	if v is bool:
		return 1 if v else 0
	if v is Array:
		var out: Array = []
		for x in v:
			out.append(normalise(x))
		return out
	if v is Dictionary:
		var out := {}
		for k in v:
			out[str(k)] = normalise(v[k])
		return out
	return v


## 32-bit hash of the whole state (MD5 of the canonical JSON: keys sorted).
static func state_hash(st: Dictionary) -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(to_json(st).to_utf8_buffer())
	return ctx.finish().decode_u32(0)


static func hash_text(st: Dictionary) -> String:
	return "%08x" % state_hash(st)


static func copy(st: Dictionary) -> Dictionary:
	return st.duplicate(true)


# ------------------------------------------------------------------ rng ---

## Uniform integer in 0..n-1 from the state's RNG (advances it).
static func rand(st: Dictionary, n: int) -> int:
	var x: int = int(st["rng"])
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	x &= 0xFFFFFFFF
	if x == 0:
		x = 0x5EED
	st["rng"] = x
	return x % maxi(n, 1)


# -------------------------------------------------------------- queries ---

static func nf() -> int:
	return CData.faction_count()


static func dip(st: Dictionary, a: int, b: int) -> int:
	if a == b:
		return ALLIED
	if a < 0 or b < 0:
		return WAR  # independents can always be attacked (they never act)
	return int(st["dip"][a * nf() + b])


static func set_dip(st: Dictionary, a: int, b: int, v: int) -> void:
	var n := nf()
	st["dip"][a * n + b] = v
	st["dip"][b * n + a] = v
	st["dip_turn"][a * n + b] = int(st.get("turn", 0))
	st["dip_turn"][b * n + a] = int(st.get("turn", 0))


static func dip_since(st: Dictionary, a: int, b: int) -> int:
	return int(st["turn"]) - int(st["dip_turn"][a * nf() + b])


static func at_war(st: Dictionary, a: int, b: int) -> bool:
	if a == b or (a < 0 and b < 0):
		return false
	return dip(st, a, b) == WAR


## Same side: the same faction, or allied (the human players).
static func friendly(st: Dictionary, a: int, b: int) -> bool:
	if a < 0 or b < 0:
		return a == b
	return a == b or dip(st, a, b) == ALLIED


static func is_human(st: Dictionary, f: int) -> bool:
	return f >= 0 and (st["humans"] as Array).has(f)


static func alive(st: Dictionary, f: int) -> bool:
	return f >= 0 and int(st["factions"][f]["alive"]) != 0


static func owner(st: Dictionary, r: int) -> int:
	return int(st["regions"][r]["owner"])


static func army_index(st: Dictionary, id: int) -> int:
	var arr: Array = st["armies"]
	for i in arr.size():
		if int(arr[i]["id"]) == id:
			return i
	return -1


static func army(st: Dictionary, id: int) -> Dictionary:
	var i := army_index(st, id)
	return st["armies"][i] if i >= 0 else {}


static func armies_in(st: Dictionary, r: int) -> Array:
	var out: Array = []
	for a in st["armies"]:
		if int(a["r"]) == r:
			out.append(a)
	return out


static func armies_of(st: Dictionary, f: int) -> Array:
	var out: Array = []
	for a in st["armies"]:
		if int(a["f"]) == f:
			out.append(a)
	return out


static func regions_of(st: Dictionary, f: int) -> Array[int]:
	var out: Array[int] = []
	for r in CData.region_count():
		if owner(st, r) == f:
			out.append(r)
	return out


static func battle_at(st: Dictionary, r: int) -> Dictionary:
	for b in st["battles"]:
		if int(b["r"]) == r:
			return b
	return {}


## Siege rules apply (state version 4 and later: the state has "sieges").
## An unmigrated online campaign of format 1-3 has no sieges: every move
## into a hostile region assaults at once, exactly as those builds did.
static func sieges_on(st: Dictionary) -> bool:
	return st.has("sieges")


## The siege of region r ({} if none).
static func siege_at(st: Dictionary, r: int) -> Dictionary:
	if not st.has("sieges"):
		return {}
	for sg in st["sieges"]:
		if int(sg["r"]) == r:
			return sg
	return {}


## Turns of supplies a settlement holds when a siege starts: SIEGE_SUPPLY by
## level, +1 with granaries (farms at SIEGE_GRANARY_FARM or more).
static func siege_supply(st: Dictionary, r: int) -> int:
	var s := int(CData.SIEGE_SUPPLY[int(st["regions"][r]["level"])])
	if building(st, r, CData.FARM) >= CData.SIEGE_GRANARY_FARM:
		s += 1
	return s


static func battle(st: Dictionary, id: int) -> Dictionary:
	for b in st["battles"]:
		if int(b["id"]) == id:
			return b
	return {}


static func unit_type(u: Dictionary) -> int:
	return UT.index_of(str(u["t"]))


static func unit_count(a: Dictionary) -> int:
	return (a["units"] as Array).size()


static func men(a: Dictionary) -> int:
	var n := 0
	for u in a["units"]:
		n += int(u["n"])
	return n


## Level of building chain c in region r (0 = none).
static func building(st: Dictionary, r: int, c: int) -> int:
	for s in st["regions"][r]["slots"]:
		if int(s[0]) == c:
			return int(s[1])
	return 0


static func slot_count(r: int, level: int) -> int:
	return int(CData.SLOTS[level]) + (CData.CAPITAL_SLOTS if CData.is_capital(r) else 0)


static func walls(st: Dictionary, r: int) -> int:
	return building(st, r, CData.WALLS)


## Unit type key for line at tier for faction f ("" if not in its roster).
static func roster_type(f: int, line: String, tier: int) -> String:
	var ro: Dictionary = CData.roster(f)
	if not ro.has(line):
		return ""
	var tiers: Array = ro[line]
	if tier < 1 or tier > tiers.size():
		return ""
	return str(tiers[tier - 1])


## Unit upkeep per turn (a unit costs its full upkeep whatever its strength).
static func upkeep_of(ty: int) -> int:
	return UT.price_of(ty) * CData.UPKEEP_PCT / 100


## Military strength of an army (men weighted by price per man; the AI and
## the battle formula use it).
static func strength(a: Dictionary) -> int:
	var s := 0
	for u in a["units"]:
		var ty := unit_type(u)
		s += int(u["n"]) * UT.price_of(ty) / maxi(UT.size_of(ty), 1)
	return s
