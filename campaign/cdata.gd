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

const Terrain := preload("res://sim/terrain.gd")
const MapGen := preload("res://sim/mapgen.gd")

const FLAT := Terrain.K_FLAT
const ROLLING := Terrain.K_ROLLING
const RIDGE := Terrain.K_RIDGE
const VALLEY := Terrain.K_VALLEY
const HILL := Terrain.K_HILL
## Ground palettes (battle map and campaign map colour; sim/mapgen.gd).
const ARID := MapGen.PAL_ARID
const DRY := MapGen.PAL_DRY
const GREEN := MapGen.PAL_GREEN
const ROCKY := MapGen.PAL_ROCKY
## Founding cultures (sim/mapgen.gd): a settlement's wall plan is its
## founder's (region "culture", static); factions have a culture for the
## style of what they build and of their shrine (view only).
const LATIN := MapGen.CUL_LATIN
const GREEK := MapGen.CUL_GREEK
const PUNIC := MapGen.CUL_PUNIC
const CELTIC := MapGen.CUL_CELTIC

## Settlement levels.
const VILLAGE := 0
const TOWN := 1
const CITY := 2
const LEVEL_NAMES: Array[String] = ["Village", "Town", "City"]

## Regions: key, region name, settlement, area, terrain, lon, lat (1/100
## degree), wealth (1-7), starting settlement level, starting wall level,
## landmass (view: territory cells only compete within a landmass), ground
## palette (arid Africa and south-east Iberia; dry Greece, southern Italy
## and the islands; green Gaul, northern Italy and Atlantic Iberia; rocky
## mountains), woods coverage 0-100 (battle maps' vegetation) and the
## founding culture (wall plan and the default building style; Iberian and
## Illyrian / Samnite hill peoples use the celtic oppidum).
## Landmasses: 0 Europe, 1 Africa, 2 Sicily, 3 Sardinia, 4 Corsica.
const REGIONS: Array[Dictionary] = [
	{"key": "latium", "name": "Latium", "city": "Roma", "area": "Italy", "terrain": ROLLING, "lon": 1250, "lat": 4190, "wealth": 6, "level": CITY, "walls": 1, "land": 0, "ground": DRY, "forest": 20, "culture": LATIN},
	{"key": "etruria", "name": "Etruria", "city": "Arretium", "area": "Italy", "terrain": HILL, "lon": 1188, "lat": 4346, "wealth": 4, "level": TOWN, "walls": 0, "land": 0, "ground": GREEN, "forest": 45, "culture": LATIN},
	{"key": "campania", "name": "Campania", "city": "Capua", "area": "Italy", "terrain": FLAT, "lon": 1425, "lat": 4108, "wealth": 6, "level": TOWN, "walls": 0, "land": 0, "ground": DRY, "forest": 15, "culture": LATIN},
	{"key": "samnium", "name": "Samnium", "city": "Beneventum", "area": "Italy", "terrain": RIDGE, "lon": 1478, "lat": 4130, "wealth": 3, "level": VILLAGE, "walls": 0, "land": 0, "ground": ROCKY, "forest": 35, "culture": CELTIC},
	{"key": "apulia", "name": "Apulia", "city": "Tarentum", "area": "Italy", "terrain": FLAT, "lon": 1724, "lat": 4047, "wealth": 5, "level": CITY, "walls": 1, "land": 0, "ground": DRY, "forest": 12, "culture": GREEK},
	{"key": "bruttium", "name": "Bruttium", "city": "Rhegium", "area": "Italy", "terrain": HILL, "lon": 1565, "lat": 3811, "wealth": 3, "level": VILLAGE, "walls": 0, "land": 0, "ground": DRY, "forest": 28, "culture": GREEK},
	{"key": "cisalpina", "name": "Gallia Cisalpina", "city": "Mediolanum", "area": "Italy", "terrain": FLAT, "lon": 919, "lat": 4546, "wealth": 4, "level": VILLAGE, "walls": 0, "land": 0, "ground": GREEN, "forest": 45, "culture": CELTIC},
	{"key": "venetia", "name": "Venetia", "city": "Patavium", "area": "Italy", "terrain": FLAT, "lon": 1188, "lat": 4541, "wealth": 3, "level": VILLAGE, "walls": 0, "land": 0, "ground": GREEN, "forest": 50, "culture": LATIN},
	{"key": "sicilia_occ", "name": "Sicilia Occidentalis", "city": "Lilybaeum", "area": "Islands", "terrain": HILL, "lon": 1243, "lat": 3780, "wealth": 4, "level": TOWN, "walls": 1, "land": 2, "ground": DRY, "forest": 10, "culture": PUNIC},
	{"key": "sicilia_or", "name": "Sicilia Orientalis", "city": "Syracusae", "area": "Islands", "terrain": ROLLING, "lon": 1529, "lat": 3707, "wealth": 6, "level": CITY, "walls": 2, "land": 2, "ground": DRY, "forest": 12, "culture": GREEK},
	{"key": "sardinia", "name": "Sardinia", "city": "Caralis", "area": "Islands", "terrain": HILL, "lon": 912, "lat": 3922, "wealth": 3, "level": VILLAGE, "walls": 0, "land": 3, "ground": DRY, "forest": 22, "culture": PUNIC},
	{"key": "corsica", "name": "Corsica", "city": "Aleria", "area": "Islands", "terrain": RIDGE, "lon": 951, "lat": 4210, "wealth": 2, "level": VILLAGE, "walls": 0, "land": 4, "ground": ROCKY, "forest": 40, "culture": GREEK},
	{"key": "baetica", "name": "Baetica", "city": "Gades", "area": "Iberia", "terrain": ROLLING, "lon": -629, "lat": 3653, "wealth": 5, "level": TOWN, "walls": 0, "land": 0, "ground": DRY, "forest": 15, "culture": PUNIC},
	{"key": "contestania", "name": "Contestania", "city": "Mastia", "area": "Iberia", "terrain": HILL, "lon": -98, "lat": 3760, "wealth": 4, "level": VILLAGE, "walls": 0, "land": 0, "ground": ARID, "forest": 6, "culture": PUNIC},
	{"key": "edetania", "name": "Edetania", "city": "Saguntum", "area": "Iberia", "terrain": ROLLING, "lon": -27, "lat": 3968, "wealth": 4, "level": TOWN, "walls": 0, "land": 0, "ground": ARID, "forest": 10, "culture": CELTIC},
	{"key": "ilergetia", "name": "Ilergetia", "city": "Emporion", "area": "Iberia", "terrain": ROLLING, "lon": 312, "lat": 4213, "wealth": 3, "level": VILLAGE, "walls": 0, "land": 0, "ground": DRY, "forest": 20, "culture": GREEK},
	{"key": "celtiberia", "name": "Celtiberia", "city": "Numantia", "area": "Iberia", "terrain": RIDGE, "lon": -244, "lat": 4181, "wealth": 3, "level": TOWN, "walls": 1, "land": 0, "ground": ROCKY, "forest": 25, "culture": CELTIC},
	{"key": "carpetania", "name": "Carpetania", "city": "Toletum", "area": "Iberia", "terrain": FLAT, "lon": -402, "lat": 3986, "wealth": 3, "level": VILLAGE, "walls": 0, "land": 0, "ground": DRY, "forest": 12, "culture": CELTIC},
	{"key": "lusitania", "name": "Lusitania", "city": "Olisipo", "area": "Iberia", "terrain": ROLLING, "lon": -914, "lat": 3872, "wealth": 3, "level": VILLAGE, "walls": 0, "land": 0, "ground": GREEN, "forest": 35, "culture": CELTIC},
	{"key": "gallaecia", "name": "Gallaecia", "city": "Brigantium", "area": "Iberia", "terrain": HILL, "lon": -840, "lat": 4337, "wealth": 2, "level": VILLAGE, "walls": 0, "land": 0, "ground": GREEN, "forest": 50, "culture": CELTIC},
	{"key": "massalia", "name": "Massalia", "city": "Massalia", "area": "Gaul", "terrain": HILL, "lon": 537, "lat": 4330, "wealth": 5, "level": CITY, "walls": 1, "land": 0, "ground": DRY, "forest": 20, "culture": GREEK},
	{"key": "volcae", "name": "Volcae", "city": "Narbo", "area": "Gaul", "terrain": FLAT, "lon": 300, "lat": 4318, "wealth": 3, "level": VILLAGE, "walls": 0, "land": 0, "ground": DRY, "forest": 18, "culture": CELTIC},
	{"key": "arverni", "name": "Arverni", "city": "Gergovia", "area": "Gaul", "terrain": RIDGE, "lon": 309, "lat": 4571, "wealth": 4, "level": TOWN, "walls": 1, "land": 0, "ground": GREEN, "forest": 50, "culture": CELTIC},
	{"key": "allobroges", "name": "Allobroges", "city": "Vienna", "area": "Gaul", "terrain": VALLEY, "lon": 487, "lat": 4552, "wealth": 3, "level": VILLAGE, "walls": 0, "land": 0, "ground": GREEN, "forest": 55, "culture": CELTIC},
	{"key": "macedonia", "name": "Macedonia", "city": "Pella", "area": "Greece", "terrain": ROLLING, "lon": 2252, "lat": 4076, "wealth": 5, "level": CITY, "walls": 1, "land": 0, "ground": DRY, "forest": 25, "culture": GREEK},
	{"key": "thessalia", "name": "Thessalia", "city": "Larissa", "area": "Greece", "terrain": FLAT, "lon": 2242, "lat": 3964, "wealth": 4, "level": TOWN, "walls": 0, "land": 0, "ground": DRY, "forest": 10, "culture": GREEK},
	{"key": "epirus", "name": "Epirus", "city": "Ambracia", "area": "Greece", "terrain": RIDGE, "lon": 2098, "lat": 3916, "wealth": 3, "level": TOWN, "walls": 1, "land": 0, "ground": ROCKY, "forest": 35, "culture": GREEK},
	{"key": "illyria", "name": "Illyria", "city": "Scodra", "area": "Greece", "terrain": HILL, "lon": 1951, "lat": 4207, "wealth": 3, "level": VILLAGE, "walls": 0, "land": 0, "ground": ROCKY, "forest": 40, "culture": CELTIC},
	{"key": "aetolia", "name": "Aetolia", "city": "Thermon", "area": "Greece", "terrain": RIDGE, "lon": 2167, "lat": 3860, "wealth": 3, "level": VILLAGE, "walls": 0, "land": 0, "ground": ROCKY, "forest": 35, "culture": GREEK},
	{"key": "attica", "name": "Attica", "city": "Athenae", "area": "Greece", "terrain": ROLLING, "lon": 2373, "lat": 3798, "wealth": 6, "level": CITY, "walls": 2, "land": 0, "ground": DRY, "forest": 12, "culture": GREEK},
	{"key": "achaea", "name": "Achaea", "city": "Corinthus", "area": "Greece", "terrain": HILL, "lon": 2288, "lat": 3790, "wealth": 5, "level": TOWN, "walls": 1, "land": 0, "ground": DRY, "forest": 18, "culture": GREEK},
	{"key": "laconia", "name": "Laconia", "city": "Sparta", "area": "Greece", "terrain": VALLEY, "lon": 2243, "lat": 3707, "wealth": 3, "level": TOWN, "walls": 0, "land": 0, "ground": DRY, "forest": 20, "culture": GREEK},
	{"key": "zeugitana", "name": "Zeugitana", "city": "Carthago", "area": "Africa", "terrain": FLAT, "lon": 1032, "lat": 3685, "wealth": 7, "level": CITY, "walls": 2, "land": 1, "ground": ARID, "forest": 5, "culture": PUNIC},
	{"key": "byzacena", "name": "Byzacena", "city": "Hadrumetum", "area": "Africa", "terrain": FLAT, "lon": 1064, "lat": 3583, "wealth": 4, "level": TOWN, "walls": 0, "land": 1, "ground": ARID, "forest": 4, "culture": PUNIC},
	{"key": "numidia", "name": "Numidia", "city": "Cirta", "area": "Africa", "terrain": ROLLING, "lon": 661, "lat": 3636, "wealth": 3, "level": VILLAGE, "walls": 0, "land": 1, "ground": ARID, "forest": 10, "culture": PUNIC},
	{"key": "mauretania", "name": "Mauretania", "city": "Tingis", "area": "Africa", "terrain": HILL, "lon": -580, "lat": 3577, "wealth": 2, "level": VILLAGE, "walls": 0, "land": 1, "ground": ARID, "forest": 14, "culture": PUNIC},
]

## Land routes (one turn each way).
const ROUTES: Array = [
	["latium", "etruria"], ["latium", "campania"], ["latium", "samnium"],
	["campania", "samnium"], ["campania", "bruttium"], ["samnium", "apulia"],
	["apulia", "bruttium"], ["etruria", "cisalpina"], ["cisalpina", "venetia"],
	["cisalpina", "allobroges"], ["cisalpina", "massalia"], ["venetia", "illyria"],
	["sicilia_occ", "sicilia_or"],
	["baetica", "contestania"], ["baetica", "carpetania"], ["baetica", "lusitania"],
	["contestania", "edetania"], ["contestania", "carpetania"], ["edetania", "ilergetia"],
	["edetania", "celtiberia"], ["ilergetia", "celtiberia"], ["celtiberia", "carpetania"],
	["carpetania", "lusitania"], ["lusitania", "gallaecia"], ["gallaecia", "celtiberia"],
	["ilergetia", "volcae"],
	["volcae", "massalia"], ["volcae", "arverni"], ["massalia", "allobroges"],
	["arverni", "allobroges"],
	["macedonia", "thessalia"], ["macedonia", "illyria"], ["macedonia", "epirus"],
	["thessalia", "epirus"], ["thessalia", "aetolia"], ["thessalia", "attica"],
	["epirus", "illyria"], ["epirus", "aetolia"], ["aetolia", "attica"],
	["attica", "achaea"], ["achaea", "laconia"],
	["zeugitana", "byzacena"], ["zeugitana", "numidia"], ["byzacena", "numidia"],
	["numidia", "mauretania"],
]

## Sea lanes between ports (one turn; no fleets, no naval battles).
const SEA_LANES: Array = [
	["bruttium", "sicilia_or"], ["sicilia_occ", "zeugitana"], ["sardinia", "zeugitana"],
	["sardinia", "corsica"], ["sardinia", "latium"], ["corsica", "etruria"],
	["corsica", "massalia"], ["ilergetia", "massalia"], ["apulia", "epirus"],
	["apulia", "illyria"], ["baetica", "mauretania"], ["contestania", "numidia"],
	["achaea", "aetolia"], ["sicilia_or", "achaea"],
]

## Factions. Index = faction id in the state; -1 is "independent".
## colour (view), capital region, starting regions, treasury, armies
## (region + unit type keys), and the AI's preferred army make-up
## (line -> weight; lines missing from the roster are ignored).
const FACTIONS: Array[Dictionary] = [
	{"key": "rome", "culture": LATIN, "name": "Rome", "adj": "Roman", "color": "c8402f", "capital": "latium",
		"regions": ["latium", "etruria", "campania", "samnium"], "treasury": 1500,
		"armies": [["latium", ["heavy", "heavy", "heavy", "spear", "javelin", "javelin", "cav"]],
			["samnium", ["heavy", "heavy", "spear", "javelin", "cav"]]],
		"mix": {"heavy": 45, "spear": 15, "javelin": 20, "cav": 15, "bolt": 5}},
	{"key": "carthage", "culture": PUNIC, "name": "Carthage", "adj": "Carthaginian", "color": "7a4fc4", "capital": "zeugitana",
		"regions": ["zeugitana", "byzacena", "sicilia_occ", "sardinia", "baetica"], "treasury": 2200,
		"armies": [["zeugitana", ["spear", "spear", "heavy", "light", "light", "javelin", "cav", "cav"]],
			["sicilia_occ", ["spear", "light", "light", "archer", "cav"]],
			["baetica", ["light", "light", "javelin", "javelin", "cav"]]],
		"mix": {"spear": 25, "heavy": 15, "light": 15, "javelin": 15, "archer": 5, "cav": 25}},
	{"key": "macedon", "culture": GREEK, "name": "Macedon", "adj": "Macedonian", "color": "e0b02a", "capital": "macedonia",
		"regions": ["macedonia", "thessalia"], "treasury": 1600,
		"armies": [["macedonia", ["pike", "pike", "pike", "cav", "cav", "archer", "light", "javelin"]]],
		"mix": {"pike": 45, "cav": 20, "archer": 10, "light": 10, "javelin": 10, "stone": 5}},
	{"key": "epirus", "culture": GREEK, "name": "Epirus", "adj": "Epirote", "color": "e07a2a", "capital": "epirus",
		"regions": ["epirus", "apulia"], "treasury": 1800,
		"armies": [["apulia", ["pike", "pike", "pike", "pike", "cav", "cav", "cav", "light", "javelin", "archer"]],
			["epirus", ["pike", "light", "javelin", "spear"]]],
		"mix": {"pike": 40, "cav": 25, "light": 10, "javelin": 10, "archer": 10, "spear": 5}},
	{"key": "greeks", "culture": GREEK, "name": "Greek League", "adj": "Greek", "color": "3f7fd8", "capital": "attica",
		"regions": ["attica", "achaea", "aetolia"], "treasury": 1600,
		"armies": [["attica", ["spear", "spear", "archer", "light", "javelin"]],
			["achaea", ["spear", "spear", "archer", "cav"]]],
		"mix": {"spear": 45, "archer": 20, "light": 10, "javelin": 10, "cav": 10, "bolt": 5}},
	{"key": "syracuse", "culture": GREEK, "name": "Syracuse", "adj": "Syracusan", "color": "2fa8a0", "capital": "sicilia_or",
		"regions": ["sicilia_or", "bruttium"], "treasury": 2200,
		"armies": [["sicilia_or", ["spear", "spear", "spear", "spear", "archer", "archer", "heavy", "heavy", "cav", "bolt"]],
			["bruttium", ["spear", "javelin", "light"]]],
		"mix": {"spear": 40, "heavy": 15, "archer": 15, "javelin": 10, "cav": 10, "bolt": 5, "stone": 5}},
	{"key": "iberians", "culture": CELTIC, "name": "Iberian Tribes", "adj": "Iberian", "color": "8a5a2b", "capital": "celtiberia",
		"regions": ["celtiberia", "edetania", "carpetania"], "treasury": 1200,
		"armies": [["celtiberia", ["light", "light", "light", "heavy", "javelin", "javelin", "cav"]],
			["edetania", ["light", "light", "javelin", "cav"]]],
		"mix": {"light": 35, "heavy": 20, "javelin": 25, "cav": 15, "spear": 5}},
	{"key": "gauls", "culture": CELTIC, "name": "Gallic Tribes", "adj": "Gallic", "color": "3c9a3c", "capital": "arverni",
		"regions": ["arverni", "cisalpina", "volcae"], "treasury": 1200,
		"armies": [["arverni", ["light", "light", "light", "heavy", "cav", "cav", "javelin"]],
			["cisalpina", ["light", "light", "light", "cav", "javelin"]]],
		"mix": {"light": 45, "heavy": 20, "cav": 20, "javelin": 10, "archer": 5}},
]
const INDEPENDENT := -1
const INDEPENDENT_COLOR := "8c8c84"

## Rosters: line -> unit type key per tier (1-3); "" = not available.
const ROSTERS := {
	"rome": {"heavy": ["heavy", "principes", "extraordinarii"], "light": ["light", "light2", ""],
		"spear": ["spear", "spear2", "triarii"], "javelin": ["javelin", "javelin2", "javelin3"],
		"cav": ["cav", "cav2", ""], "bolt": ["bolt"], "stone": ["stone"]},
	"carthage": {"heavy": ["heavy", "heavy2", ""], "light": ["light", "light2", "light3"],
		"spear": ["spear", "spear2", "sacred_band"], "archer": ["archer", "archer2", ""],
		"javelin": ["javelin", "javelin2", "javelin3"], "cav": ["cav", "cav2", "cav3"],
		"bolt": ["bolt"], "stone": ["stone"]},
	"macedon": {"pike": ["pike", "phalangites", "silver_shields"], "light": ["light", "light2", ""],
		"archer": ["archer", "archer2", "archer3"], "javelin": ["javelin", "javelin2", ""],
		"cav": ["cav", "cav2", "companions"], "bolt": ["bolt"], "stone": ["stone"]},
	"epirus": {"pike": ["pike", "pike2", "chaonians"], "spear": ["spear", "spear2", ""],
		"light": ["light", "light2", ""], "archer": ["archer", "archer2", ""],
		"javelin": ["javelin", "javelin2", ""], "cav": ["cav", "cav2", "agema"], "bolt": ["bolt"]},
	"greeks": {"spear": ["spear", "hoplites", "picked_hoplites"], "pike": ["pike", "pike2", ""],
		"archer": ["archer", "archer2", "cretans"], "light": ["light", "light2", ""],
		"javelin": ["javelin", "javelin2", "javelin3"], "cav": ["cav", "cav2", ""],
		"bolt": ["bolt"], "stone": ["stone"]},
	"syracuse": {"spear": ["spear", "hoplites", "picked_hoplites"], "heavy": ["heavy", "heavy2", ""],
		"archer": ["archer", "archer2", "cretans"], "javelin": ["javelin", "javelin2", ""],
		"light": ["light", "light2", ""], "cav": ["cav", "cav2", ""], "bolt": ["bolt"], "stone": ["stone"]},
	"iberians": {"light": ["light", "caetrati", "light3"], "heavy": ["heavy", "scutarii", "heavy3"],
		"javelin": ["javelin", "javelin2", "javelin3"], "spear": ["spear", "spear2", ""],
		"cav": ["cav", "cav2", ""]},
	"gauls": {"light": ["light", "warband", "light3"], "heavy": ["heavy", "heavy2", "gallic_nobles"],
		"spear": ["spear", "spear2", ""], "javelin": ["javelin", "javelin2", ""],
		"archer": ["archer", "", ""], "cav": ["cav", "cav2", "noble_cav"]},
	"independent": {"spear": ["spear", "spear2", "spear3"], "archer": ["archer", "archer2", "archer3"],
		"heavy": ["heavy", "heavy2", "heavy3"], "light": ["light", "light2", "light3"]},
}
## Display order of lines in recruitment lists.
const LINE_ORDER: Array[String] = ["heavy", "light", "spear", "pike", "archer", "javelin", "cav", "bolt", "stone"]

## Starting wars (all other pairs start at peace without trade).
const START_WARS: Array = [["rome", "epirus"], ["carthage", "syracuse"]]

## Buildings: key, name, max level, cost and build turns per level, and what
## each level does (text for the panel; the numbers are in the rules).
const CHAINS: Array[Dictionary] = [
	{"key": "farm", "name": "Farms", "levels": 3, "cost": [400, 900, 1600], "turns": [1, 2, 3],
		"desc": "+1 growth and +40 income per level"},
	{"key": "market", "name": "Market", "levels": 3, "cost": [500, 1000, 1800], "turns": [1, 2, 3],
		"desc": "+90 income per level; +15% trade income per level"},
	{"key": "barracks", "name": "Barracks", "levels": 3, "cost": [400, 900, 1600], "turns": [1, 2, 3],
		"desc": "Infantry (swords, light, spears, pikes) of tier = level; faster replenishment"},
	{"key": "range", "name": "Range", "levels": 3, "cost": [350, 800, 1400], "turns": [1, 2, 3],
		"desc": "Archers and javelinmen of tier = level; faster replenishment"},
	{"key": "stables", "name": "Stables", "levels": 3, "cost": [500, 1000, 1800], "turns": [1, 2, 3],
		"desc": "Cavalry of tier = level; faster replenishment"},
	{"key": "workshop", "name": "Workshop", "levels": 2, "cost": [600, 1200], "turns": [2, 3],
		"desc": "Level 1 bolt throwers, level 2 stone throwers"},
	{"key": "walls", "name": "Walls", "levels": 3, "cost": [400, 900, 1600], "turns": [2, 2, 3],
		"desc": "+1 garrison unit, better garrison and higher ground for the defenders per level"},
]
const FARM := 0
const MARKET := 1
const BARRACKS := 2
const RANGE := 3
const STABLES := 4
const WORKSHOP := 5
const WALLS := 6
## Military building per line.
const LINE_CHAIN := {"heavy": BARRACKS, "light": BARRACKS, "spear": BARRACKS, "pike": BARRACKS,
	"archer": RANGE, "javelin": RANGE, "cav": STABLES, "bolt": WORKSHOP, "stone": WORKSHOP}
## Workshop level needed per artillery line (other lines: level = tier).
const ART_LEVEL := {"bolt": 1, "stone": 2}
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
const BATTLE_SIDE_MAX := 24      # field units per side in a real-time battle (+ garrison)
const START_YEAR := 280          # BC; two turns a year (summer, winter)

## Key cities for the default victory condition.
const KEY_CITIES: Array[String] = ["latium", "zeugitana", "macedonia", "sicilia_or", "attica"]

static var _region_idx := {}
static var _ports: Array = []
static var _faction_idx := {}
static var _adj: Array = []


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


## "280 BC, summer" for turn t.
static func date_text(turn: int) -> String:
	return "%d BC, %s" % [START_YEAR - turn / 2, "summer" if turn % 2 == 0 else "winter"]
