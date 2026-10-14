extends RefCounted
## The Rome pack (280 BC, the western Mediterranean): the content tables
## campaign/cdata.gd reads through CData.use_pack("rome"). Moved verbatim
## from cdata.gd (2026-10-13, West pack step 0); the shared enums are in
## cenums.gd. The state stores indices into these tables, so changing them
## changes what a saved Rome campaign means (bump CState.VERSION).

const E := preload("res://campaign/data/cenums.gd")
const FLAT := E.FLAT
const ROLLING := E.ROLLING
const RIDGE := E.RIDGE
const VALLEY := E.VALLEY
const HILL := E.HILL
const ARID := E.ARID
const DRY := E.DRY
const GREEN := E.GREEN
const ROCKY := E.ROCKY
const LATIN := E.LATIN
const GREEK := E.GREEK
const PUNIC := E.PUNIC
const CELTIC := E.CELTIC
const VILLAGE := E.VILLAGE
const TOWN := E.TOWN
const CITY := E.CITY
const AI_BALANCED := E.AI_BALANCED
const RANGE := E.RANGE
const WORKSHOP := E.WORKSHOP

## Pack key (the state's "pack"; absent means "rome").
const KEY := "rome"
## The nav grid (campaign/cgrid.gd; written by tools/campaign_grid.gd).
const GRID := preload("res://campaign/data/grid_data.gd")
## Map projection for CData.sector(): lon x LON_PCT / 1000 (cos of the
## map's middle latitude), lat x 1.
const LON_PCT := 766
## Calendar: START_YEAR counted down (BC) or up (AD), two turns a year.
const START_YEAR := 280
const ERA := "BC"

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
	{"key": "zeugitana", "name": "Zeugitana", "city": "Carthago", "area": "Africa", "terrain": FLAT, "lon": 1032, "lat": 3687, "wealth": 7, "level": CITY, "walls": 2, "land": 1, "ground": ARID, "forest": 5, "culture": PUNIC},
	{"key": "byzacena", "name": "Byzacena", "city": "Hadrumetum", "area": "Africa", "terrain": FLAT, "lon": 1063, "lat": 3582, "wealth": 4, "level": TOWN, "walls": 0, "land": 1, "ground": ARID, "forest": 4, "culture": PUNIC},
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
## AI flavour (docs/AI.md 5): "ai_style" the default personality, written
## into a new campaign's factions[f] when not BALANCED (all BALANCED for
## now: the user wants Carthage CAUTIOUS and the Gauls AGGRESSIVE once
## personalities do something, docs/AI.md 8 step 5); "composition" the
## army style the recruitment and deployment will follow (not read by
## anything yet): {"arms": preferred lines, best first; "art_pct": share of
## artillery in a field army, %; "cav_pct": share of cavalry, %; "upgrade":
## eagerness to recruit higher tiers, 0 late .. 2 early}.
const FACTIONS: Array[Dictionary] = [
	{"key": "rome", "culture": LATIN, "name": "Rome", "adj": "Roman", "color": "c8402f", "capital": "latium",
		"regions": ["latium", "etruria", "campania", "samnium"], "treasury": 1500,
		"armies": [["latium", ["heavy", "heavy", "heavy", "spear", "javelin", "javelin", "cav", "legate"]],
			["samnium", ["heavy", "heavy", "spear", "javelin", "cav", "legate"]]],
		"mix": {"heavy": 45, "spear": 15, "javelin": 20, "cav": 15, "bolt": 5, "general": 4, "dogs": 3, "light_art": 3},
		"ai_style": AI_BALANCED, "composition": {"arms": ["heavy", "spear", "javelin"], "art_pct": 10, "cav_pct": 10, "upgrade": 2}},
	{"key": "carthage", "culture": PUNIC, "name": "Carthage", "adj": "Carthaginian", "color": "7a4fc4", "capital": "zeugitana",
		"regions": ["zeugitana", "byzacena", "sicilia_occ", "sardinia", "baetica"], "treasury": 2200,
		"armies": [["zeugitana", ["spear", "spear", "heavy", "light", "light", "javelin", "cav", "cav", "sufet"]],
			["sicilia_occ", ["spear", "light", "light", "archer", "cav", "sufet"]],
			["baetica", ["light", "light", "javelin", "javelin", "cav", "sufet"]]],
		"mix": {"spear": 25, "heavy": 15, "light": 15, "javelin": 15, "archer": 5, "cav": 25, "camel": 5, "elephant": 5,
			"cav_missile": 5, "sling": 5, "general": 4, "light_art": 3},
		"ai_style": AI_BALANCED, "composition": {"arms": ["cav", "spear", "light"], "art_pct": 0, "cav_pct": 25, "upgrade": 1}},
	{"key": "macedon", "culture": GREEK, "name": "Macedon", "adj": "Macedonian", "color": "e0b02a", "capital": "macedonia",
		"regions": ["macedonia", "thessalia"], "treasury": 1600,
		"armies": [["macedonia", ["pike", "pike", "pike", "cav", "cav", "archer", "light", "javelin", "hetairoi_guard"]]],
		"mix": {"pike": 45, "cav": 20, "archer": 10, "light": 10, "javelin": 10, "stone": 5, "general": 4, "light_art": 3},
		"ai_style": AI_BALANCED, "composition": {"arms": ["pike", "cav", "archer"], "art_pct": 5, "cav_pct": 20, "upgrade": 1}},
	{"key": "epirus", "culture": GREEK, "name": "Epirus", "adj": "Epirote", "color": "e07a2a", "capital": "epirus",
		"regions": ["epirus", "apulia"], "treasury": 1800,
		"armies": [["apulia", ["pike", "pike", "pike", "pike", "cav", "cav", "cav", "light", "javelin", "archer", "hetairoi_guard"]],
			["epirus", ["pike", "light", "javelin", "spear", "hetairoi_guard"]]],
		"mix": {"pike": 40, "cav": 25, "light": 10, "javelin": 10, "archer": 10, "spear": 5, "elephant": 5, "cav_missile": 5,
			"general": 4, "dogs": 3, "light_art": 3},
		"ai_style": AI_BALANCED, "composition": {"arms": ["pike", "cav", "light"], "art_pct": 0, "cav_pct": 25, "upgrade": 1}},
	{"key": "greeks", "culture": GREEK, "name": "Greek League", "adj": "Greek", "color": "3f7fd8", "capital": "attica",
		"regions": ["attica", "achaea", "aetolia"], "treasury": 1600,
		"armies": [["attica", ["spear", "spear", "archer", "light", "javelin", "strategos"]],
			["achaea", ["spear", "spear", "archer", "cav", "strategos"]]],
		"mix": {"spear": 45, "archer": 20, "light": 10, "javelin": 10, "cav": 10, "bolt": 5, "cav_missile": 5, "sling": 5,
			"general": 4, "dogs": 3, "light_art": 3, "belly_bow": 3},
		"ai_style": AI_BALANCED, "composition": {"arms": ["spear", "archer", "light"], "art_pct": 5, "cav_pct": 10, "upgrade": 1}},
	{"key": "syracuse", "culture": GREEK, "name": "Syracuse", "adj": "Syracusan", "color": "2fa8a0", "capital": "sicilia_or",
		"regions": ["sicilia_or", "bruttium"], "treasury": 2200,
		"armies": [["sicilia_or", ["spear", "spear", "spear", "spear", "archer", "archer", "heavy", "heavy", "cav", "bolt", "strategos"]],
			["bruttium", ["spear", "javelin", "light", "strategos"]]],
		"mix": {"spear": 40, "heavy": 15, "archer": 15, "javelin": 10, "cav": 10, "bolt": 5, "stone": 5, "cav_missile": 5,
			"general": 4, "light_art": 3, "belly_bow": 3},
		"ai_style": AI_BALANCED, "composition": {"arms": ["spear", "archer", "heavy"], "art_pct": 10, "cav_pct": 10, "upgrade": 1}},
	{"key": "iberians", "culture": CELTIC, "name": "Iberian Tribes", "adj": "Iberian", "color": "8a5a2b", "capital": "celtiberia",
		"regions": ["celtiberia", "edetania", "carpetania"], "treasury": 1200,
		"armies": [["celtiberia", ["light", "light", "light", "heavy", "javelin", "javelin", "cav", "chieftain"]],
			["edetania", ["light", "light", "javelin", "cav", "chieftain"]]],
		"mix": {"light": 35, "heavy": 20, "javelin": 25, "cav": 15, "spear": 5, "cav_missile": 5, "sling": 5, "general": 4},
		"ai_style": AI_BALANCED, "composition": {"arms": ["light", "javelin", "heavy"], "art_pct": 0, "cav_pct": 15, "upgrade": 0}},
	{"key": "gauls", "culture": CELTIC, "name": "Gallic Tribes", "adj": "Gallic", "color": "3c9a3c", "capital": "arverni",
		"regions": ["arverni", "cisalpina", "volcae"], "treasury": 1200,
		"armies": [["arverni", ["light", "light", "light", "heavy", "cav", "cav", "javelin", "chieftain"]],
			["cisalpina", ["light", "light", "light", "cav", "javelin", "chieftain"]]],
		"mix": {"light": 45, "heavy": 20, "cav": 20, "javelin": 10, "archer": 5, "cav_missile": 5, "general": 4, "dogs": 3},
		"ai_style": AI_BALANCED, "composition": {"arms": ["light", "heavy", "cav"], "art_pct": 0, "cav_pct": 20, "upgrade": 0}},
]

## Rosters: line -> unit type key per tier (1-3); "" = not available.
const ROSTERS := {
	"rome": {"heavy": ["heavy", "principes", "extraordinarii"], "light": ["light", "light2", ""],
		"spear": ["spear", "spear2", "triarii"], "javelin": ["javelin", "javelin2", "javelin3"],
		"cav": ["cav", "cav2", ""], "siege": ["wagon", "wagon2", "wagon3"], "bolt": ["bolt"], "stone": ["stone"],
		"general": ["legate"], "dogs": ["dog_handlers"], "light_art": ["scorpions"]},
	"carthage": {"heavy": ["heavy", "heavy2", ""], "light": ["light", "light2", "light3"],
		"spear": ["spear", "spear2", "sacred_band"], "archer": ["archer", "archer2", ""],
		"javelin": ["javelin", "javelin2", "javelin3"], "cav": ["cav", "cav2", "cav3"],
		"siege": ["wagon", "wagon2", "wagon3"], "bolt": ["bolt"], "stone": ["stone"],
		"camel": ["camel"], "camel_archer": ["camel_archer"], "elephant": ["elephant"],
		"cav_missile": ["cav_jav", "numidians"], "sling": ["slinger", "balearic"], "general": ["sufet"],
		"light_art": ["scorpions"]},
	"macedon": {"pike": ["pike", "phalangites", "silver_shields"], "light": ["light", "light2", ""],
		"archer": ["archer", "archer2", "archer3"], "javelin": ["javelin", "javelin2", ""],
		"cav": ["cav", "cav2", "companions"], "siege": ["wagon", "wagon2", "wagon3"], "bolt": ["bolt"], "stone": ["stone"],
		"general": ["hetairoi_guard"], "light_art": ["scorpions"]},
	"epirus": {"pike": ["pike", "pike2", "chaonians"], "spear": ["spear", "spear2", ""],
		"light": ["light", "light2", ""], "archer": ["archer", "archer2", ""],
		"javelin": ["javelin", "javelin2", ""], "cav": ["cav", "cav2", "agema"], "siege": ["wagon", "wagon2", "wagon3"], "bolt": ["bolt"],
		"elephant": ["elephant"], "cav_missile": ["cav_jav", "tarentines"], "general": ["hetairoi_guard"],
		"dogs": ["dog_handlers"], "light_art": ["scorpions"]},
	"greeks": {"spear": ["spear", "hoplites", "picked_hoplites"], "pike": ["pike", "pike2", ""],
		"archer": ["archer", "archer2", "cretans"], "light": ["light", "light2", ""],
		"javelin": ["javelin", "javelin2", "javelin3"], "cav": ["cav", "cav2", ""],
		"siege": ["wagon", "wagon2", "wagon3"], "bolt": ["bolt"], "stone": ["stone"],
		"cav_missile": ["cav_jav", "tarentines"], "sling": ["slinger", "rhodians"], "general": ["strategos"],
		"dogs": ["dog_handlers"], "light_art": ["scorpions"], "belly_bow": ["gastraphetes"]},
	"syracuse": {"spear": ["spear", "hoplites", "picked_hoplites"], "heavy": ["heavy", "heavy2", ""],
		"archer": ["archer", "archer2", "cretans"], "javelin": ["javelin", "javelin2", ""],
		"light": ["light", "light2", ""], "cav": ["cav", "cav2", ""], "siege": ["wagon", "wagon2", "wagon3"], "bolt": ["bolt"], "stone": ["stone"],
		"cav_missile": ["cav_jav", "tarentines"], "general": ["strategos"], "light_art": ["scorpions"],
		"belly_bow": ["gastraphetes"]},
	"iberians": {"light": ["light", "caetrati", "light3"], "heavy": ["heavy", "scutarii", "heavy3"],
		"javelin": ["javelin", "javelin2", "javelin3"], "spear": ["spear", "spear2", ""],
		"cav": ["cav", "cav2", ""], "siege": ["wagon", "", ""],
		"cav_missile": ["cav_jav", "iberian_horse"], "sling": ["slinger", "iberian_slingers"], "general": ["chieftain"]},
	"gauls": {"light": ["light", "warband", "light3"], "heavy": ["heavy", "heavy2", "gallic_nobles"],
		"spear": ["spear", "spear2", ""], "javelin": ["javelin", "javelin2", ""],
		"archer": ["archer", "", ""], "cav": ["cav", "cav2", "noble_cav"], "siege": ["wagon", "", ""],
		"cav_missile": ["cav_jav", "gallic_horse"], "general": ["chieftain"], "dogs": ["dog_handlers"]},
	"independent": {"spear": ["spear", "spear2", "spear3"], "archer": ["archer", "archer2", "archer3"],
		"heavy": ["heavy", "heavy2", "heavy3"], "light": ["light", "light2", "light3"]},
}

## Starting wars (all other pairs start at peace without trade).
const START_WARS: Array = [["rome", "epirus"], ["carthage", "syracuse"]]

## Special ammunition kinds (sim/unit_types.gd AMMO; docs/DESIGN.md
## "Ammunition kinds"): [kind key, factions (keys), building chain, level].
## A unit recruited by a faction listed, where that building stands at that
## level, carries the first row that rides on its weapon (CRules.ammo_for),
## stored on its unit entry as "ak" (optional key). The Range is the
## fletchers' chain; the Workshop makes the engines' shot.
const AMMO_AVAIL: Array = [
	["fire_arrows", ["greeks", "syracuse", "carthage"], RANGE, 2],
	["fire_javelins", ["iberians", "gauls"], RANGE, 2],
	["lead_bullets", ["carthage", "greeks"], RANGE, 2],
	["heavy_bolts", ["rome", "syracuse"], WORKSHOP, 1],
	["explosive", ["syracuse"], WORKSHOP, 2],
	["fire_pots", ["rome", "carthage", "macedon", "greeks", "syracuse"], WORKSHOP, 2],
]

## Key cities for the default victory condition.
const KEY_CITIES: Array[String] = ["latium", "zeugitana", "macedonia", "sicilia_or", "attica"]

## Character names by culture (12 each), picked with the state's RNG
## (CData.name_list). NAMES_BY_FACTION overrides the culture's list for a
## faction key: the Iberian tribes use their own (their culture is Celtic for
## the buildings). NAMES_DEFAULT: independents and any culture not listed.
const NAMES_LATIN: Array[String] = ["Marcus Valerius", "Gaius Fabius", "Lucius Cornelius", "Quintus Aemilius",
	"Publius Decius", "Titus Manlius", "Aulus Sempronius", "Gnaeus Domitius", "Servius Claudius", "Manius Curius",
	"Spurius Postumius", "Decimus Junius"]
const NAMES_PUNIC: Array[String] = ["Hanno", "Himilco", "Mago", "Hasdrubal", "Bomilcar", "Maharbal", "Adherbal",
	"Gisco", "Hannibal Gisco", "Carthalo", "Sophoniba", "Mutines"]
const NAMES_GREEK: Array[String] = ["Alexandros", "Demetrios", "Philon", "Kleomenes", "Aristides", "Lysandros",
	"Nikanor", "Perdikkas", "Theron", "Xenophon", "Antigonos", "Menelaos"]
const NAMES_CELTIC: Array[String] = ["Brennus", "Vercingos", "Cathbad", "Dumnorix", "Orgetorix", "Viridomarus",
	"Boiorix", "Cativolcus", "Segovax", "Ambiorix", "Teutorix", "Catumandus"]
const NAMES_IBERIAN: Array[String] = ["Indibil", "Mandonio", "Viriato", "Culcas", "Corbis", "Orisson", "Edeco",
	"Moericanos", "Istolatios", "Luxinio", "Abilyx", "Attenes"]
const NAMES: Dictionary = {LATIN: NAMES_LATIN, PUNIC: NAMES_PUNIC, GREEK: NAMES_GREEK, CELTIC: NAMES_CELTIC}
const NAMES_BY_FACTION: Dictionary = {"iberians": NAMES_IBERIAN}
const NAMES_DEFAULT: Array[String] = NAMES_CELTIC
