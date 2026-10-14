extends RefCounted
## A tiny content pack for tests/pack_test.gd (not under campaign/data/, so
## CData.use_pack cannot find it: the test installs it with
## CData.use_pack_script). Two regions, two factions, an "AD" calendar.

const E := preload("res://campaign/data/cenums.gd")

const KEY := "dummy"
const GRID := preload("res://tests/data/dummy_grid.gd")
const LON_PCT := 940
const START_YEAR := 1650
const ERA := "AD"

const REGIONS: Array[Dictionary] = [
	{"key": "north", "name": "North", "city": "Nordby", "area": "Test", "terrain": E.FLAT, "lon": -9000, "lat": 2000,
		"wealth": 3, "level": E.TOWN, "walls": 0, "land": 0, "ground": E.GREEN, "forest": 10, "culture": E.LATIN},
	{"key": "south", "name": "South", "city": "Sudby", "area": "Test", "terrain": E.HILL, "lon": -8900, "lat": 1900,
		"wealth": 3, "level": E.VILLAGE, "walls": 0, "land": 0, "ground": E.DRY, "forest": 50, "culture": E.GREEK},
]
const ROUTES: Array = [["north", "south"]]
const SEA_LANES: Array = []
const FACTIONS: Array[Dictionary] = [
	{"key": "nords", "culture": E.LATIN, "name": "Nords", "adj": "Nordic", "color": "c8402f", "capital": "north",
		"regions": ["north"], "treasury": 1000, "armies": [], "mix": {"spear": 100},
		"ai_style": E.AI_BALANCED, "composition": {"arms": ["spear"], "art_pct": 0, "cav_pct": 0, "upgrade": 0}},
	{"key": "suds", "culture": E.GREEK, "name": "Suds", "adj": "Sudish", "color": "3f7fd8", "capital": "south",
		"regions": ["south"], "treasury": 1000, "armies": [], "mix": {"spear": 100},
		"ai_style": E.AI_BALANCED, "composition": {"arms": ["spear"], "art_pct": 0, "cav_pct": 0, "upgrade": 0}},
]
const ROSTERS := {
	"nords": {"spear": ["spear", "", ""]},
	"suds": {"spear": ["spear", "", ""]},
	"independent": {"spear": ["spear", "spear2", "spear3"]},
}
const START_WARS: Array = [["nords", "suds"]]
const AMMO_AVAIL: Array = []
const KEY_CITIES: Array[String] = ["north"]
const NAMES_A: Array[String] = ["Alpha"]
const NAMES_B: Array[String] = ["Beta"]
const NAMES: Dictionary = {E.LATIN: NAMES_A}
const NAMES_BY_FACTION: Dictionary = {"suds": NAMES_B}
const NAMES_DEFAULT: Array[String] = NAMES_A
