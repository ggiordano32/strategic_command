extends RefCounted
## Static campaign data (milestone 3): regions, land routes, sea lanes,
## factions, rosters, starting positions, buildings, settlement levels and
## the economy's numbers. Pure data plus a few cached lookups; the rules are
## in crules.gd. Nothing here is saved: the state stores indices into these
## tables (regions, factions, chains) and unit type keys (sim/unit_types.gd),
## so changing these tables changes what a saved campaign means (bump
## CState.VERSION when an index changes).
##
## Map coordinates: settlements carry real longitude / latitude in 1/100
## degree (view only: the map projects them); terrain is a sim/terrain.gd kind.
##
## Content packs (West pack step 0, 2026-10-13): the map's content (REGIONS,
## ROUTES, SEA_LANES, FACTIONS, ROSTERS, START_WARS, AMMO_AVAIL, KEY_CITIES,
## the calendar, the names, the nav grid) comes from a pack script
## campaign/data/<pack>.gd (rome.gd, the default) and lives in static vars
## of the same names; the economy, the buildings and the shared enums
## (campaign/data/cenums.gd, re-exported here) are the same for every pack.
## One pack is active per process: use_state(st) switches to a state's pack
## (its "pack" key, absent = "rome"); the rules' entry points
## (CTurn.resolve_turn / apply_battle, CState.new_campaign / migrate) call
## it first. Every switch bumps `gen` and clears the derived caches here and
## in cgrid / crules / cai / cbattle (their pack_reset()).

const E := preload("res://campaign/data/cenums.gd")
const _ROME := preload("res://campaign/data/rome.gd")
## Scripts whose derived caches depend on the pack (pack_reset() on a
## switch). Loaded at switch time, not preloaded: they preload this file.
const _DERIVED: Array[String] = ["res://campaign/cgrid.gd", "res://campaign/crules.gd",
	"res://campaign/cai.gd", "res://campaign/cbattle.gd", "res://campaign/cfleet.gd"]

const FLAT := E.FLAT
const ROLLING := E.ROLLING
const RIDGE := E.RIDGE
const VALLEY := E.VALLEY
const HILL := E.HILL
## Ground palettes (battle map and campaign map colour; sim/mapgen.gd).
const ARID := E.ARID
const DRY := E.DRY
const GREEN := E.GREEN
const ROCKY := E.ROCKY
## Founding cultures (sim/mapgen.gd): a settlement's wall plan is its
## founder's (region "culture", static); factions have a culture for the
## style of what they build and of their shrine (view only).
const LATIN := E.LATIN
const GREEK := E.GREEK
const PUNIC := E.PUNIC
const CELTIC := E.CELTIC

## Settlement levels.
const VILLAGE := E.VILLAGE
const TOWN := E.TOWN
const CITY := E.CITY
const LEVEL_NAMES: Array[String] = ["Village", "Town", "City"]

## AI personalities (campaign/cai_profile.gd CAUTIOUS / BALANCED / AGGRESSIVE).
const AI_CAUTIOUS := E.AI_CAUTIOUS
const AI_BALANCED := E.AI_BALANCED
const AI_AGGRESSIVE := E.AI_AGGRESSIVE

## The active pack (the key of campaign/data/<pack>.gd) and a counter bumped
## on every switch (view caches compare it).
static var pack := "rome"
static var gen := 0
## Years added to the calendar (a story campaign's "y0", campaign/cstory.gd;
## set by use_state, 0 for every other campaign).
static var year_shift := 0

## Pack content (see campaign/data/rome.gd for each table's meaning).
## REGIONS: key, name, city, area, terrain, lon, lat, wealth, level, walls,
## land, ground, forest, culture. FACTIONS: key, culture, name, adj, color,
## capital, regions, treasury, armies, mix, ai_style, composition. ROSTERS:
## faction key (and "independent") -> line -> unit type key per tier.
## AMMO_AVAIL: [kind, faction keys, chain, level]. GRID: the nav grid script
## (W, H, CELL_PX, ROWS, TERRAIN, ...). LON_PCT: the map's lon scale (x/1000)
## for sector(). START_YEAR / ERA ("BC" counts down, "AD" up).
static var REGIONS: Array[Dictionary] = _ROME.REGIONS
static var ROUTES: Array = _ROME.ROUTES
static var SEA_LANES: Array = _ROME.SEA_LANES
## Sea lanes from a port out to the open sea at the map's edge: [port region key, grid x, grid y] (the sea cell
## nearest that cell; campaign/clanes.gd routes them). Optional in a pack (none: Rome).
static var SEA_LANE_EXITS: Array = []
## Trade value a turn of single lanes, [port region key, port region key, gold] rows (either order) overriding the default
## (level_a + level_b) x LANE_BASE (campaign/clanes.gd). Optional in a pack (none: the default everywhere).
static var SEA_LANE_TRADE: Array = []
static var FACTIONS: Array[Dictionary] = _ROME.FACTIONS
static var ROSTERS: Dictionary = _ROME.ROSTERS
static var START_WARS: Array = _ROME.START_WARS
static var AMMO_AVAIL: Array = _ROME.AMMO_AVAIL
static var KEY_CITIES: Array[String] = _ROME.KEY_CITIES
static var START_YEAR: int = _ROME.START_YEAR
static var ERA: String = _ROME.ERA
static var LON_PCT: int = _ROME.LON_PCT
static var GRID: GDScript = _ROME.GRID
static var NAMES: Dictionary = _ROME.NAMES
static var NAMES_BY_FACTION: Dictionary = _ROME.NAMES_BY_FACTION
static var NAMES_DEFAULT: Array[String] = _ROME.NAMES_DEFAULT

const INDEPENDENT := -1
const INDEPENDENT_COLOR := "8c8c84"

## Display order of lines in recruitment lists.
## (The West pack's lines: musket after the pikes, buccaneer after the
## javelins, pistol after the cavalry, its guns before the bolt throwers.)
const LINE_ORDER: Array[String] = ["heavy", "light", "spear", "pike", "musket", "archer", "belly_bow", "sling", "javelin",
	"buccaneer", "dogs", "cav", "pistol", "cav_missile", "camel", "camel_archer", "elephant", "general", "light_art",
	"light_gun", "field_gun", "bolt", "stone", "siege"]

## Buildings: key, name, max level, cost and build turns per level, and what
## each level does (text for the panel; the numbers are in the rules).
## CHAINS is the active pack's list: these seven, plus the Shipyard
## (SHIPYARD, index 7) in a pack with ships (use_pack_script).
const BASE_CHAINS: Array[Dictionary] = [
	{"key": "farm", "name": "Farms", "levels": 3, "cost": [400, 900, 1600], "turns": [1, 2, 3],
		"desc": "+1 growth and +40 income per level; from level 2 granaries make a siege's supplies last a turn longer"},
	{"key": "market", "name": "Market", "levels": 3, "cost": [500, 1000, 1800], "turns": [1, 2, 3],
		"desc": "+90 income per level; +15% trade income per level"},
	{"key": "barracks", "name": "Barracks", "levels": 3, "cost": [400, 900, 1600], "turns": [1, 2, 3],
		"desc": "Infantry (swords, light, spears, pikes) of tier = level, and the general's bodyguard (level 1; one general an army); war dogs (level 1, with Stables 1); faster replenishment"},
	{"key": "range", "name": "Range", "levels": 3, "cost": [350, 800, 1400], "turns": [1, 2, 3],
		"desc": "Archers, slingers and javelinmen of tier = level (light horse needs a Range 1 too; Greek belly-bows a Range 2); faster replenishment"},
	{"key": "stables", "name": "Stables", "levels": 3, "cost": [500, 1000, 1800], "turns": [1, 2, 3],
		"desc": "Cavalry and light horse of tier = level (camels from level 1 for some peoples, war elephants at level 3); faster replenishment"},
	{"key": "workshop", "name": "Workshop", "levels": 2, "cost": [600, 1200], "turns": [2, 3],
		"desc": "Level 1 bolt throwers, scorpions and the hand cart (ammunition), level 2 stone throwers and ammunition wagons (with Stables); heavy bolts, fire pots and explosive stones for some peoples"},
	{"key": "walls", "name": "Walls", "levels": 3, "cost": [400, 900, 1600], "turns": [2, 2, 3],
		"desc": "+1 garrison unit, better garrison and higher ground for the defenders per level"},
]
## The Shipyard (packs with ships only; ports only): builds and repairs
## ships, level = the ships' yard level (campaign/data/<pack>_ships.gd).
const SHIPYARD_CHAIN := {"key": "shipyard", "name": "Shipyard", "levels": 3, "cost": [500, 1000, 1800], "turns": [1, 2, 3],
	"desc": "Ships of yard level = level (sloops and brigantines 1, frigates 2, galleons and ships of the line 3); faster repairs in port"}
const SHIPYARD := 7
static var CHAINS: Array[Dictionary] = BASE_CHAINS
## The active pack's ships script (campaign/data/<pack>_ships.gd: ROWS, the
## wind, the starting fleets and yards), null without ships.
static var SHIPS: GDScript = null
static var _ship_idx := {}
static var _ship_c := {}  # the SHIPS script's constants (read once a pack)
const FARM := E.FARM
const MARKET := E.MARKET
const BARRACKS := E.BARRACKS
const RANGE := E.RANGE
const STABLES := E.STABLES
const WORKSHOP := E.WORKSHOP
const WALLS := E.WALLS
## Military building per line.
const LINE_CHAIN := {"heavy": BARRACKS, "light": BARRACKS, "spear": BARRACKS, "pike": BARRACKS,
	"archer": RANGE, "javelin": RANGE, "cav": STABLES, "bolt": WORKSHOP, "stone": WORKSHOP, "siege": WORKSHOP,
	"camel": STABLES, "camel_archer": STABLES, "elephant": STABLES, "cav_missile": STABLES, "sling": RANGE,
	"general": BARRACKS, "dogs": BARRACKS, "light_art": WORKSHOP, "belly_bow": RANGE,
	"musket": BARRACKS, "buccaneer": RANGE, "pistol": STABLES, "light_gun": WORKSHOP, "field_gun": WORKSHOP}
## Buildings a unit type needs where they differ from its line's chain at
## its tier (the ammunition wagons: the Workshop, and Stables for the
## horses): key -> [[chain, level], ...], all of them.
## Camels: Stables 1 (camel archers a Range 1 too); elephants: Stables 3.
## Light horse: Stables of its tier and a Range 1 (javelins, as the camel
## archers' bows); slingers need only their line's Range of their tier.
## War dogs: Barracks 1 (their line) and Stables 1 (the kennels are kept
## with the horses): every capital has both from the start, towns not.
## Gastraphetes (the Greek belly-bow): a Range 2 (a workshop-made weapon).
const UNIT_NEEDS := {"wagon": [[WORKSHOP, 1]], "wagon2": [[WORKSHOP, 2], [STABLES, 1]],
	"wagon3": [[WORKSHOP, 2], [STABLES, 2]], "camel": [[STABLES, 1]], "camel_archer": [[STABLES, 1], [RANGE, 1]],
	"elephant": [[STABLES, 3]], "cav_jav": [[STABLES, 1], [RANGE, 1]], "numidians": [[STABLES, 2], [RANGE, 1]],
	"tarentines": [[STABLES, 2], [RANGE, 1]], "gallic_horse": [[STABLES, 2], [RANGE, 1]],
	"iberian_horse": [[STABLES, 2], [RANGE, 1]], "dog_handlers": [[BARRACKS, 1], [STABLES, 1]],
	"gastraphetes": [[RANGE, 2]]}
## Workshop level needed per artillery line (other lines: level = tier).
const ART_LEVEL := {"bolt": 1, "stone": 2, "light_art": 1, "light_gun": 1, "field_gun": 2}
## Buildings standing at the start: capitals and the other regions per level.
const START_CAPITAL_CITY := [[FARM, 1], [BARRACKS, 1], [RANGE, 1], [STABLES, 1], [MARKET, 1]]
const START_CAPITAL_TOWN := [[FARM, 1], [BARRACKS, 1], [RANGE, 1], [STABLES, 1]]
const START_TOWN := [[FARM, 1], [BARRACKS, 1]]
const START_CITY := [[FARM, 1], [MARKET, 1], [BARRACKS, 1]]

## Settlement levels: slots (capitals +2), highest building level, recruits
## per turn, income, garrison units (before walls).
const SLOTS := [2, 3, 4]
const CAPITAL_SLOTS := 2
const RECRUITS_PER_TURN := [1, 2, 3]
const LEVEL_INCOME := [0, 80, 200]
const GARRISON_UNITS := [2, 3, 4]
## Growth points to reach town and city; growth per turn is 1 + farm level
## (+1 for wealth 5 or more).
const GROWTH_TO := [0, 18, 45]

## Economy.
const WEALTH_INCOME := 60        # per wealth point per turn
const FARM_INCOME := 40          # per farm level
const MARKET_INCOME := 90        # per market level
const TRADE_BASE := 80           # per trade partner per turn ...
const TRADE_PER_REGION := 15     # ... plus this per region of the smaller partner ...
const TRADE_CAP := 260           # ... at most this, then +15% per market level of ours (max 3)
const UPKEEP_PCT := 15           # unit upkeep per turn, % of its price
const GARRISON_SIZE_PCT := 60    # garrison units are this % of a full unit
const INDEPENDENT_EXTRA_UNITS := 2  # independent garrisons are bigger ...
const INDEPENDENT_SIZE_PCT := 90      # ... and their units nearly full size
const GARRISON_REGEN := 25       # garrison strength regained per turn (% points)
const CAPTURED_GARRISON := 30    # a captured settlement's new garrison starts at this %
const CORRUPTION_FREE := 6      # regions before running a realm costs income ...
const CORRUPTION_PCT := 4        # ... this % per region beyond ...
const CORRUPTION_MAX := 40       # ... at most
const DEBT_DESERTION := 10       # % of men every unit loses in a turn ending in debt
const REPLENISH_BASE := 8        # % of full strength regained per turn in friendly land
const REPLENISH_PER_LEVEL := 6   # + this per level of the line's building in the region
const ROUT_RETURN := 70          # % of routed-off soldiers who rejoin after a battle
const ARMY_MAX := 12             # units per army
## The general (docs/CAMPAIGN.md "The general"): every starting army has
## one (the "armies" lists above), an army holds at most one (CRules), the
## AI mixes keep a few ("general" 4). Test switches, never set by the game:
## no_generals (tests/campaign_sim.gd --no-generals, the campaign_test AI
## goldens) starts the armies without them and the AI recruits none;
## old_mp (--old-mp) marches armies at the pace counted before 2026-10-09
## (only CLS_CAV as cavalry: light horse and camel archers at the foot's).
static var no_generals := false
## no_dogs (tests/campaign_sim.gd --no-dogs): the AI recruits no war dogs
## (their mix weight 0), to show that only their recruitment changes a run.
static var no_dogs := false
## no_light_art (tests/campaign_sim.gd --no-light-art): the AI recruits no
## scorpions or gastraphetes (mix weight 0), the same proof for them.
static var no_light_art := false
static var old_mp := false
const BATTLE_SIDE_MAX := 24      # field units per side in a real-time battle (+ garrison)
## Sieges (state version 4). Turns a besieged settlement's supplies last per
## level (village, town, city), +1 with farms at SIEGE_GRANARY_FARM or more
## (granaries); then the garrison loses SIEGE_STARVE_PCT strength points and
## the owner's armies inside SIEGE_STARVE_ARMY_PCT of their men every turn.
const SIEGE_SUPPLY := [2, 3, 4]
const SIEGE_GRANARY_FARM := 2
const SIEGE_STARVE_PCT := 25
const SIEGE_STARVE_ARMY_PCT := 10
## Move modes: lay siege (default) or assault at once; version 5: march
## (enter without attacking the settlement: raiding in enemy land).
const MODE_SIEGE := 0
const MODE_ASSAULT := 1
const MODE_MARCH := 2
## Free movement (state version 5). Movement points per turn by the army's
## slowest arm: cavalry only MP_CAV, with artillery MP_ART (not scorpions: "carried"), else MP_FOOT.
## Entering a region costs by its terrain (move_cost); a sea lane needs full
## points and uses them all; a hop costing more than the points left needs
## full points (so an army can always make one hop a turn).
const MP_FOOT := 20
const MP_CAV := 30
const MP_ART := 15
const COST_OPEN := 10          # flat, rolling, valley
const COST_ROUGH := 15         # hill, ridge
const COST_WOODS := 5          # extra into a region with woods coverage >= WOODS_HEAVY
const WOODS_HEAVY := 40
## Stances (version 5): in the field (blocks and intercepts enemy movement,
## supports battles in range) or inside the walls of a friendly settlement.
const STANCE_FIELD := 0
const STANCE_GARRISON := 1
## Continuous overworld (state version 6, campaign/cgrid.gd). Armies stand
## on cells of a static nav grid (campaign/data/grid_data.gd, generated from
## the map by tools/campaign_grid.gd) and walk 8-connected paths; a cell
## costs by its region's terrain (GRID_COST, + GRID_WOODS in heavy woods), a
## diagonal step 14/10 of that. Roads, rivers and hills (2026-10-09, still
## format 6: static data only): a hill / ridge cell (the grid's terrain
## override) costs GRID_COST of that kind; a road cell GRID_ROAD (never more
## than its terrain); a river edge cannot be stepped across except at a
## crossing: a ford costs GRID_FORD on top of the cell entered, a bridge
## nothing extra. Movement points a turn by the slowest arm.
const GRID_COST := {FLAT: 10, ROLLING: 10, VALLEY: 10, HILL: 15, RIDGE: 20}
const GRID_WOODS := 5
const GRID_ROAD := 6
const GRID_FORD := 5
## Crossing kinds (the grid's CROSS list; the battle scenario's "river" key).
const CROSS_FORD := 0
const CROSS_BRIDGE := 1
const MP6_FOOT := 200
const MP6_CAV := 300
const MP6_ART := 150
## Zone of control (cells, a circle: dx^2 + dy^2 <= r^2 + r): paths may not
## enter an enemy army's zone unless that army is the target. Support: a
## friendly army within this radius of a battle's cell joins it.
const ZOC := 2
const SUPPORT := 4
## Stances (version 6; one selector on the army card). Forced march: +50%
## points, cannot attack or lay siege, fights badly if caught. Fortify:
## cannot move, zone +1, support +2, a defender bonus. Raiding: -30%
## points, takes RAID_PCT of the income of the enemy region it stands in.
## (Version 5's 1, inside the walls, is a position in version 6: an army on
## its settlement's cell is inside.)
const ST_DEFAULT := 0
const ST_FORCED := 2
const ST_FORTIFY := 3
const ST_RAID := 4
const STANCE_NAMES := {0: "Default", 2: "Forced march", 3: "Fortify", 4: "Raiding"}
const FORCED_MP_PCT := 150
const RAID_MP_PCT := 70
const RAID_PCT := 50
## Sea lanes (2026-10-22, campaign/clanes.gd): a lane pays (level_a + level_b) x LANE_BASE gold a turn (SEA_LANE_TRADE
## rows override), half to each end port's owner; a fleet at war with an end port's owner lying on a lane cell at the
## end of the turn raids it: the lane pays LANE_RAID_PCT % less, the raider's owner takes LANE_RAID_TAKE % of the cut.
const LANE_BASE := 4
const LANE_RAID_PCT := 60
const LANE_RAID_TAKE := 50
const FORTIFY_DEF_PCT := 119   # formula / odds: fortified defenders' strength (fitted 2026-10-10: an Average army in its camp beat an equal one 25 of 40 (13 / 20 on 2026-10-09, 12 / 20 on 2026-10-10 against a mirrored 10 / 20), (62.5 / 37.5)^(1/3) = 1.19; was 125)
const FORCED_DEF_PCT := 75     # ... an army caught on a forced march
const FORCED_MORALE_PCT := 75  # battle: its units start with this % of their morale
## Besiegers lose this % of their men a turn once the city's supplies are gone.
const SIEGE_BESIEGER_PCT := 5

static var _region_idx := {}
static var _ports: Array = []
static var _faction_idx := {}
static var _adj: Array = []




# ------------------------------------------------------------------ packs ---

## A pack key names a script campaign/data/<key>.gd that declares KEY = key.
static func has_pack(key: String) -> bool:
	if key == pack:
		return true
	if key.is_empty() or not key.is_valid_ascii_identifier() or key != key.to_lower():
		return false
	var path := "res://campaign/data/%s.gd" % key
	if not ResourceLoader.exists(path):
		return false
	var s = load(path)
	return s is GDScript and str((s as GDScript).get_script_constant_map().get("KEY", "")) == key


## Make pack `key` active (no-op when it already is). An unknown pack is an
## error (push_error, assert) and leaves the active pack as it was.
static func use_pack(key: String) -> void:
	if key == pack:
		return
	if not has_pack(key):
		push_error("CData.use_pack: unknown pack \"%s\"" % key)
		assert(false, "unknown pack %s" % key)
		return
	use_pack_script(key, load("res://campaign/data/%s.gd" % key))


## Switch to the pack of state st ("pack", absent = "rome").
static func use_state(st: Dictionary) -> void:
	use_pack(str(st.get("pack", "rome")))
	var sto = st.get("story", null)
	year_shift = int((sto as Dictionary).get("y0", 0)) if sto is Dictionary else 0


## Install pack script p under key (use_pack's work; tests may hand it a
## pack of their own). Clears the caches here and the derived ones.
static func use_pack_script(key: String, p: GDScript) -> void:
	var c := p.get_script_constant_map()
	REGIONS = c["REGIONS"]
	ROUTES = c["ROUTES"]
	SEA_LANES = c["SEA_LANES"]
	SEA_LANE_EXITS = c.get("SEA_LANE_EXITS", [])
	SEA_LANE_TRADE = c.get("SEA_LANE_TRADE", [])
	FACTIONS = c["FACTIONS"]
	ROSTERS = c["ROSTERS"]
	START_WARS = c["START_WARS"]
	AMMO_AVAIL = c["AMMO_AVAIL"]
	KEY_CITIES = c["KEY_CITIES"]
	START_YEAR = int(c["START_YEAR"])
	ERA = str(c["ERA"])
	LON_PCT = int(c["LON_PCT"])
	GRID = c["GRID"]
	NAMES = c["NAMES"]
	NAMES_BY_FACTION = c["NAMES_BY_FACTION"]
	NAMES_DEFAULT = c["NAMES_DEFAULT"]
	SHIPS = c.get("SHIPS", null)
	_ship_c = SHIPS.get_script_constant_map() if SHIPS != null else {}
	if SHIPS != null:
		var ch: Array[Dictionary] = BASE_CHAINS.duplicate()
		ch.append(SHIPYARD_CHAIN)
		CHAINS = ch
	else:
		CHAINS = BASE_CHAINS
	_ship_idx = {}
	pack = key
	gen += 1
	_region_idx = {}
	_ports = []
	_faction_idx = {}
	_adj = []
	for path in _DERIVED:
		(load(path) as GDScript).call("pack_reset")


## The active pack has ships (fleets on the sea; no sea lanes for armies).
static func ships_on() -> bool:
	return SHIPS != null


## Ship rows of the active pack (campaign/data/<pack>_ships.gd ROWS), [] without.
static func ship_rows() -> Array[Dictionary]:
	if SHIPS == null:
		return []
	var rows: Array[Dictionary] = _ship_c["ROWS"]
	return rows


## A constant of the active pack's ships script (the wind, the start).
static func ship_const(key: String, default = null):
	if SHIPS == null:
		return default
	return _ship_c.get(key, default)


## Index of ship row `key` (-1 unknown).
static func ship_index(key: String) -> int:
	if _ship_idx.is_empty():
		var rows := ship_rows()
		for i in rows.size():
			_ship_idx[str(rows[i]["key"])] = i
	return int(_ship_idx.get(key, -1))


## Ship row `key` ({} unknown).
static func ship_row(key: String) -> Dictionary:
	var i := ship_index(key)
	return ship_rows()[i] if i >= 0 else {}


static func region_count() -> int:
	return REGIONS.size()


static func faction_count() -> int:
	return FACTIONS.size()


static func region_index(key: String) -> int:
	if _region_idx.is_empty():
		for r in REGIONS.size():
			_region_idx[str(REGIONS[r]["key"])] = r
	return int(_region_idx.get(key, -1))


static func faction_index(key: String) -> int:
	if _faction_idx.is_empty():
		for f in FACTIONS.size():
			_faction_idx[str(FACTIONS[f]["key"])] = f
	return int(_faction_idx.get(key, -1))


## Neighbours of region r: Array of [region, kind] (0 land route, 1 sea
## lane), sorted by region index (fixed order for the rules and the AI).
static func adjacent(r: int) -> Array:
	if _adj.is_empty():
		var adj: Array = []
		for k in REGIONS.size():
			adj.append([])
		for kind in 2:
			var list: Array = ROUTES if kind == 0 else SEA_LANES
			for pair in list:
				var a := region_index(pair[0])
				var b := region_index(pair[1])
				assert(a >= 0 and b >= 0, "bad route %s" % str(pair))
				adj[a].append([b, kind])
				adj[b].append([a, kind])
		for k in REGIONS.size():
			(adj[k] as Array).sort_custom(func(x, y): return x[0] < y[0])
		_adj = adj
	return _adj[r]


## 0 land route, 1 sea lane, -1 not adjacent.
static func link(a: int, b: int) -> int:
	for e in adjacent(a):
		if int(e[0]) == b:
			return int(e[1])
	return -1


## Movement points it costs to enter region r (version 5): COST_OPEN for
## flat, rolling and valley ground, COST_ROUGH for hills and ridges, plus
## COST_WOODS with woods coverage of WOODS_HEAVY or more.
static func move_cost(r: int) -> int:
	var k := int(REGIONS[r]["terrain"])
	var c := COST_ROUGH if k == HILL or k == RIDGE else COST_OPEN
	if int(REGIONS[r]["forest"]) >= WOODS_HEAVY:
		c += COST_WOODS
	return c


## Compass sector (0 N, 1 NE, 2 E ... 7 NW) of region `from` seen from
## region `at` (the map's projection: lon x LON_PCT / 1000, lat x 1), -1 if the same.
static func sector(at: int, from: int) -> int:
	var dx := (int(REGIONS[from]["lon"]) - int(REGIONS[at]["lon"])) * LON_PCT / 1000
	var dy := int(REGIONS[from]["lat"]) - int(REGIONS[at]["lat"])  # north positive
	if dx == 0 and dy == 0:
		return -1
	var ax := absi(dx)
	var ay := absi(dy)
	# tan(67.5 deg) = 2.414: mostly vertical / horizontal, else a diagonal.
	if ay * 1000 >= ax * 2414:
		return 0 if dy > 0 else 4
	if ax * 1000 >= ay * 2414:
		return 2 if dx > 0 else 6
	if dx > 0:
		return 1 if dy > 0 else 3
	return 7 if dy > 0 else 5


## Founding culture of region r (MapGen.CUL_*).
static func region_culture(r: int) -> int:
	return int(REGIONS[r]["culture"])


## Culture of faction f (-1 for independents).
static func faction_culture(f: int) -> int:
	return -1 if f < 0 else int(FACTIONS[f]["culture"])


## Region r is a port (on a sea lane): its settlement stands on the coast.
static func is_port(r: int) -> bool:
	if _ports.is_empty():
		var p: Array = []
		for k in REGIONS.size():
			p.append(0)
		for pair in SEA_LANES:
			p[region_index(pair[0])] = 1
			p[region_index(pair[1])] = 1
		_ports = p
	return int(_ports[r]) != 0


static func roster(f: int) -> Dictionary:
	if f < 0:
		return ROSTERS["independent"]
	return ROSTERS[FACTIONS[f]["key"]]


static func faction_name(f: int) -> String:
	return "Independent" if f < 0 else str(FACTIONS[f]["name"])


static func faction_color(f: int) -> Color:
	return Color(INDEPENDENT_COLOR if f < 0 else str(FACTIONS[f]["color"]))


static func is_capital(r: int) -> bool:
	var key: String = REGIONS[r]["key"]
	for f in FACTIONS:
		if f["capital"] == key:
			return true
	return false


## "280 BC, summer" for turn t (an "AD" pack counts the years up).
static func date_text(turn: int) -> String:
	var y := START_YEAR - turn / 2 if ERA == "BC" else START_YEAR + year_shift + turn / 2
	return "%d %s, %s" % [y, ERA, "summer" if turn % 2 == 0 else "winter"]


# ------------------------------------------------ heroes and agents (8a) ---
## Characters (campaign/cchars.gd): a hero (Champion, Master of Archers,
## Master of Horse, Master Engineer), an assassin and a diplomat ride with an
## army without taking a unit slot (one of each slot per army). Unit rows are
## in sim/unit_types.gd; these are the campaign rules' numbers.
const CHAR_WOUND_TURNS := 5      # a character who fell in a battle is out this many turns
const CHAR_LOST_TURNS := 3       # ... one whose army was destroyed, after he reached a city of ours
const PRISONER_RANSOM := 5       # gold a man for a winner's prisoners, paid at the end of the turn
## Where each kind is recruited: [building chain, level] (hero Barracks 2,
## assassin Market 2, diplomat Market 1). One character recruit a turn per region.
const CHAR_NEEDS := {"hero_foot": [BARRACKS, 2], "hero_missile": [BARRACKS, 2], "hero_cav": [BARRACKS, 2],
	"hero_siege": [BARRACKS, 2], "assassin": [MARKET, 2], "diplomat": [MARKET, 1]}


## The name list of faction f (the pack's NAMES_BY_FACTION for its key, else
## its culture's list; an independent: NAMES_DEFAULT).
static func name_list(f: int) -> Array[String]:
	if f < 0:
		return NAMES_DEFAULT
	var by: Array[String] = NAMES_BY_FACTION.get(str(FACTIONS[f]["key"]), NAMES.get(faction_culture(f), NAMES_DEFAULT))
	return by
