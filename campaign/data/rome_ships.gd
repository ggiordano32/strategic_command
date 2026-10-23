extends RefCounted
## Ships of the Rome pack (R2, Rome's navy; docs/design/sea.md "Rome's navy").
## Referenced from campaign/data/rome.gd as SHIPS: a Rome campaign has fleets
## on the Caribbean machinery (campaign/cfleet.gd, csea.gd, clanes.gd, the sea
## battles of cseabattle.gd with the galleys of sim/sea_types.gd). The shape
## is west_ships.gd's (its header says what each row field means); this file
## says only what differs. Read through CData.ships_on() / ship_rows() /
## ship_const().
##
## Differences from the West: the ships are oared galleys (lembos, trireme,
## quinquereme; "oars" 1: the wind does not change their pace) and one
## sailing merchantman (corbita); the sim rows are the same keys. A galley has
## no guns, so her worth in the auto-resolve formula is the row's "power"
## (CFleet.ship_power: hull and crew alone would make a trireme a sloop's
## tenth). The sea lanes stay open to armies (LANES_FOR_ARMIES 1: the West's
## islands are crossed on fleets only; Rome's lanes also carry armies as
## before, a fleet can carry them besides). No flota, no pirates, no
## hurricanes, no captains: the constants of those systems are the "off" value
## the rules accept (an empty list, a 100 % factor); the rules read them with
## defaults and the machinery is off while STORM_BOX / CAPTAIN_NAMES /
## FLOTA_PARTS are empty.

## The sea look (game/sea_look.gd): 1 palms and the Caribbean palette, 0 the
## Mediterranean.
const TROPIC := 0
## 1: the nav grid keeps the pack's SEA_LANES as army links (cgrid.gd).
const LANES_FOR_ARMIES := 1

const ALL := ["rome", "carthage", "macedon", "epirus", "greeks", "syracuse", "iberians", "gauls"]
const NOT_ROME := ["carthage", "macedon", "epirus", "greeks", "syracuse", "iberians", "gauls"]

## Rows: hull is the sim row's hull / 10 (as the West's), crew the sim row's;
## speed in movement points a turn (the West brigantine's 370 for the lembos,
## the frigate's 340 for the trireme, a little less for the big quinquereme
## and the slow merchantman).
const ROWS: Array[Dictionary] = [
	{"key": "lembos", "name": "Lembos", "cost": 250, "upkeep": 15, "guns": 0, "hull": 12, "crew": 50, "speed": 370,
		"cap": 0, "coastal": 1, "oars": 1, "yard": 0, "storm": 0, "power": 110,
		"factions": ALL,
		"desc": "The light Illyrian galley: fast, a handful of marines, no ram worth the name. Never far from a coast; any port of ours can launch one."},
	{"key": "trireme", "name": "Trireme", "cost": 500, "upkeep": 30, "guns": 0, "hull": 26, "crew": 200, "speed": 340,
		"cap": 1, "coastal": 0, "oars": 1, "yard": 1, "storm": 0, "power": 240,
		"factions": ALL,
		"desc": "Three banks of oars and a bronze ram: the Mediterranean's warship. Rows whatever the wind and carries one company."},
	{"key": "quinquereme", "name": "Quinquereme", "cost": 900, "upkeep": 50, "guns": 0, "hull": 42, "crew": 300, "speed": 320,
		"cap": 1, "coastal": 0, "oars": 1, "yard": 2, "storm": 0, "power": 440,
		"factions": ["rome"],
		"desc": "The big galley with the corvus, a boarding bridge that turns a sea battle into a land battle: Rome's answer to the Punic fleets."},
	{"key": "quinquereme_p", "name": "Punic quinquereme", "cost": 900, "upkeep": 50, "guns": 0, "hull": 44, "crew": 300, "speed": 320,
		"cap": 1, "coastal": 0, "oars": 1, "yard": 2, "storm": 0, "power": 420,
		"factions": NOT_ROME,
		"desc": "The great galley of Carthage and the Greek cities: a heavy ram and better crews, no corvus."},
	{"key": "corbita", "name": "Corbita", "cost": 300, "upkeep": 10, "guns": 0, "hull": 30, "crew": 30, "speed": 260,
		"cap": 2, "coastal": 0, "oars": 0, "yard": 0, "storm": 0,
		"factions": ALL,
		"desc": "A round-hulled sailing merchantman: slow, no fight in her, room for two companies. Sails with the wind and must be escorted."},
]

## Coastal ships keep to sea cells within this many cells (Chebyshev) of land.
const COASTAL_CELLS := 2

## A north-westerly (the mistral and the summer sea breeze), lighter than the
## trades; the reach table is the West's (the galleys ignore it).
const WIND_FROM_DEG := 315
const WIND_STRENGTH := 55
const WIND_PCT: Array[int] = [125, 115, 100, 75, 60]

## Shipyards at the start: [region key, level]. Rome, Carthage and Macedon
## (the three navies, and Syracuse, the great naval power of the west) at level 2, every other faction at 1, each in its
## capital when that has a harbour (CFleet.harbour: a coast cell within
## HARBOUR_MAX of the settlement; Athens, Pella and the rest, not only the
## regions on a sea lane), else at the faction's nearest harbour of its own
## (Gergovia and Numantia lie inland: Narbo and Saguntum).
const START_YARDS: Array = [
	["latium", 2], ["zeugitana", 2], ["macedonia", 2], ["epirus", 1], ["attica", 1], ["sicilia_or", 2],
	["edetania", 1], ["volcae", 1],
]

## Fleets at the start: [faction key, region key (in its dock), [ship keys]].
const START_FLEETS: Array = [
	["carthage", "zeugitana", ["quinquereme_p", "quinquereme_p", "trireme", "trireme", "trireme"]],
	["rome", "latium", ["quinquereme", "trireme", "trireme"]],
	["macedon", "macedonia", ["trireme", "trireme"]],
	["epirus", "epirus", ["trireme", "lembos"]],
	["greeks", "attica", ["trireme", "lembos"]],
	["syracuse", "sicilia_or", ["trireme", "trireme", "lembos"]],
	["iberians", "edetania", ["trireme", "lembos"]],
	["gauls", "volcae", ["trireme", "lembos"]],
]

# Trade at sea and blockades (campaign/csea.gd, clanes.gd). SEA_TRADE_PCT 50
# (2026-10-23; was the West's 100): a Mediterranean port's income is not all
# sea-borne trade, so a blockade cuts BLOCKADE_CUT_PCT (the West's) of half of it.
const SEA_TRADE_PCT := 50
const BLOCKADE_CELLS := 3
const BLOCKADE_CUT_PCT := 75
const BLOCKADE_TAKE_PCT := 40
const PIRATE_TAKE_PCT := 80
const PRIZE_PCT := 25
const PIRATE_PRIZE_PCT := 50
const TREASURE_TAKEN_PCT := 70

# Off in this pack: no flota, no pirates, no hurricanes, no captains.
const FLOTA_PARTS: Array = []
const FLOTA_MEET := ""
const FLOTA_EXIT: Array[int] = []
const PIRATE_LAND_PCT := 100
const PIRATE_UPKEEP_PCT := 100
const PIRATE_ESCAPE_PCT := 100
const HAVEN_UNITS: Array[String] = []
const HAVEN_REPAIR := 0
const STORM_BOX: Array[int] = []
const STORM_FORM_PCT: Array[int] = [0, 0]
const CAPTAIN_NAMES: Array[String] = []
const FAME_TIERS: Array[int] = [20, 45, 75]
const FAME_TIER_NAMES: Array[String] = ["", "", "", ""]
const FEAR_PCT: Array[int] = [0, 0, 0, 0]
const STRIKE_LOSS := 0
const STRIKE_TAKEN := 0
const GALLEON_NAMES: Array[String] = []
const ESCORT_INFAMY: Array[int] = []

# Sea battles fought in real time.

## Crews by faction key: [gunnery %, boarding %] (the sim's q and bq). Rome's
## strength is the corvus, not the oarsmen: Carthage and the Greek cities row
## better; the hill peoples board.
const SEA_CREWS := {"rome": [92, 105], "carthage": [112, 100], "macedon": [100, 100], "epirus": [100, 100],
	"greeks": [110, 105], "syracuse": [110, 105], "iberians": [88, 112], "gauls": [85, 112]}
const SEA_WIND_VAR := 30
const SEA_ISLAND_PCT := 20
const SEA_FEAR_FOE := 15
const SEA_TIME_LIMIT := 900
