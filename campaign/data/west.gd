extends RefCounted
## The West pack (1650 AD, the Caribbean and the Gulf of Mexico): the content
## tables campaign/cdata.gd reads through CData.use_pack("west"). Same shape as
## campaign/data/rome.gd (see there for what each table means). The 49
## settlements are the ones tools/geo/carib.json bakes (keys, lon / lat and
## landmass must stay equal to it). Units: the West rows of
## sim/unit_types.gd (WEST, slice 2a: pike and shot, buccaneers, natives,
## guns); the general's bodyguard, war dogs and wagons are shared Rome rows.
## Landmasses: 0 North and Central America (Florida to the Darien), 1 South
## America, 2 Cuba, 3 Hispaniola, 4 Jamaica, 5 Puerto Rico, 6 Trinidad.

const E := preload("res://campaign/data/cenums.gd")
const R := preload("res://campaign/data/rome.gd")
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
const AI_CAUTIOUS := E.AI_CAUTIOUS
const AI_BALANCED := E.AI_BALANCED
const AI_AGGRESSIVE := E.AI_AGGRESSIVE
const RANGE := E.RANGE
const WORKSHOP := E.WORKSHOP

const KEY := "west"
const GRID := preload("res://campaign/data/west_grid_data.gd")
## Ships, the wind and the starting fleets (N1 fleets; campaign/cfleet.gd).
## With SHIPS armies cross the sea only on fleets (SEA_LANES stay as data).
const SHIPS := preload("res://campaign/data/west_ships.gd")
## Projection of tools/geo/carib.json: px_lon 94 / px_lat 100 (cos 20 deg).
const LON_PCT := 940
const START_YEAR := 1650
const ERA := "AD"

const REGIONS: Array[Dictionary] = [
	# Mexico and the Gulf
	{"key": "veracruz", "name": "Nueva Veracruz", "city": "Veracruz", "area": "Mexico", "terrain": FLAT, "lon": -9613, "lat": 1920, "wealth": 6, "level": CITY, "walls": 1, "land": 0, "ground": DRY, "forest": 30, "culture": LATIN},
	{"key": "tampico", "name": "Panuco", "city": "Tampico", "area": "Mexico", "terrain": FLAT, "lon": -9786, "lat": 2225, "wealth": 3, "level": TOWN, "walls": 0, "land": 0, "ground": DRY, "forest": 25, "culture": LATIN},
	{"key": "campeche", "name": "Campeche", "city": "San Francisco de Campeche", "area": "Yucatan", "terrain": FLAT, "lon": -9053, "lat": 1985, "wealth": 4, "level": TOWN, "walls": 1, "land": 0, "ground": DRY, "forest": 45, "culture": LATIN},
	{"key": "merida", "name": "Yucatan", "city": "Merida", "area": "Yucatan", "terrain": FLAT, "lon": -8962, "lat": 2097, "wealth": 4, "level": TOWN, "walls": 0, "land": 0, "ground": ARID, "forest": 30, "culture": LATIN},
	{"key": "tayasal", "name": "Peten Itza", "city": "Tayasal", "area": "Yucatan", "terrain": ROLLING, "lon": -8990, "lat": 1693, "wealth": 3, "level": VILLAGE, "walls": 2, "land": 0, "ground": GREEN, "forest": 85, "culture": CELTIC},
	{"key": "belize", "name": "Belize", "city": "Belize", "area": "Central America", "terrain": FLAT, "lon": -8820, "lat": 1750, "wealth": 2, "level": VILLAGE, "walls": 0, "land": 0, "ground": GREEN, "forest": 75, "culture": LATIN},
	{"key": "trujillo", "name": "Honduras", "city": "Trujillo", "area": "Central America", "terrain": ROLLING, "lon": -8600, "lat": 1585, "wealth": 3, "level": VILLAGE, "walls": 0, "land": 0, "ground": GREEN, "forest": 70, "culture": LATIN},
	{"key": "bluefields", "name": "Bluefields Lagoon", "city": "Bluefields", "area": "Central America", "terrain": FLAT, "lon": -8377, "lat": 1201, "wealth": 2, "level": VILLAGE, "walls": 0, "land": 0, "ground": GREEN, "forest": 85, "culture": CELTIC},
	{"key": "cabo_gracias", "name": "Mosquito Coast", "city": "Cabo Gracias a Dios", "area": "Central America", "terrain": FLAT, "lon": -8315, "lat": 1499, "wealth": 2, "level": VILLAGE, "walls": 1, "land": 0, "ground": GREEN, "forest": 80, "culture": CELTIC},
	{"key": "portobelo", "name": "Terra Firma", "city": "Portobelo", "area": "Central America", "terrain": HILL, "lon": -7965, "lat": 955, "wealth": 7, "level": CITY, "walls": 2, "land": 0, "ground": GREEN, "forest": 75, "culture": LATIN},
	{"key": "st_augustine", "name": "La Florida", "city": "San Agustin", "area": "Florida", "terrain": FLAT, "lon": -8131, "lat": 2989, "wealth": 3, "level": CITY, "walls": 1, "land": 0, "ground": GREEN, "forest": 55, "culture": LATIN},
	{"key": "pensacola", "name": "Pensacola", "city": "Pensacola", "area": "Gulf Coast", "terrain": FLAT, "lon": -8724, "lat": 3047, "wealth": 2, "level": VILLAGE, "walls": 0, "land": 0, "ground": GREEN, "forest": 60, "culture": LATIN},
	{"key": "new_orleans", "name": "Louisiana", "city": "Nouvelle-Orleans", "area": "Gulf Coast", "terrain": VALLEY, "lon": -9007, "lat": 2995, "wealth": 4, "level": TOWN, "walls": 0, "land": 0, "ground": GREEN, "forest": 55, "culture": LATIN},
	# Tierra Firme (the Spanish Main)
	{"key": "cartagena", "name": "Cartagena", "city": "Cartagena de Indias", "area": "Spanish Main", "terrain": FLAT, "lon": -7546, "lat": 1039, "wealth": 7, "level": CITY, "walls": 2, "land": 1, "ground": DRY, "forest": 30, "culture": LATIN},
	{"key": "santa_marta", "name": "Santa Marta", "city": "Santa Marta", "area": "Spanish Main", "terrain": HILL, "lon": -7420, "lat": 1124, "wealth": 4, "level": TOWN, "walls": 0, "land": 1, "ground": DRY, "forest": 35, "culture": LATIN},
	{"key": "mompox", "name": "Magdalena", "city": "Santa Cruz de Mompox", "area": "Spanish Main", "terrain": FLAT, "lon": -7443, "lat": 924, "wealth": 4, "level": TOWN, "walls": 0, "land": 1, "ground": GREEN, "forest": 60, "culture": LATIN},
	{"key": "maracaibo", "name": "Maracaibo", "city": "Maracaibo", "area": "Spanish Main", "terrain": FLAT, "lon": -7164, "lat": 1065, "wealth": 4, "level": TOWN, "walls": 0, "land": 1, "ground": DRY, "forest": 35, "culture": LATIN},
	{"key": "coro", "name": "Coro", "city": "Santa Ana de Coro", "area": "Spanish Main", "terrain": ROLLING, "lon": -6968, "lat": 1140, "wealth": 3, "level": VILLAGE, "walls": 0, "land": 1, "ground": ARID, "forest": 12, "culture": LATIN},
	{"key": "la_guaira", "name": "Caracas", "city": "La Guaira", "area": "Spanish Main", "terrain": HILL, "lon": -6693, "lat": 1060, "wealth": 4, "level": TOWN, "walls": 0, "land": 1, "ground": DRY, "forest": 30, "culture": LATIN},
	{"key": "cumana", "name": "Cumana", "city": "Cumana", "area": "Spanish Main", "terrain": FLAT, "lon": -6417, "lat": 1045, "wealth": 3, "level": TOWN, "walls": 1, "land": 1, "ground": ARID, "forest": 15, "culture": LATIN},
	# Cuba
	{"key": "havana", "name": "La Habana", "city": "La Habana", "area": "Cuba", "terrain": FLAT, "lon": -8236, "lat": 2314, "wealth": 7, "level": CITY, "walls": 2, "land": 2, "ground": GREEN, "forest": 25, "culture": LATIN},
	{"key": "puerto_principe", "name": "Camaguey", "city": "Puerto Principe", "area": "Cuba", "terrain": ROLLING, "lon": -7790, "lat": 2138, "wealth": 4, "level": TOWN, "walls": 0, "land": 2, "ground": GREEN, "forest": 20, "culture": LATIN},
	{"key": "santiago_de_cuba", "name": "Oriente", "city": "Santiago de Cuba", "area": "Cuba", "terrain": HILL, "lon": -7583, "lat": 2002, "wealth": 4, "level": TOWN, "walls": 1, "land": 2, "ground": GREEN, "forest": 50, "culture": LATIN},
	# Hispaniola
	{"key": "santo_domingo", "name": "Santo Domingo", "city": "Santo Domingo", "area": "Hispaniola", "terrain": FLAT, "lon": -6990, "lat": 1848, "wealth": 5, "level": CITY, "walls": 1, "land": 3, "ground": GREEN, "forest": 35, "culture": LATIN},
	{"key": "santiago_caballeros", "name": "Cibao", "city": "Santiago de los Caballeros", "area": "Hispaniola", "terrain": VALLEY, "lon": -7070, "lat": 1945, "wealth": 3, "level": TOWN, "walls": 0, "land": 3, "ground": GREEN, "forest": 45, "culture": LATIN},
	{"key": "port_de_paix", "name": "Tortuga Coast", "city": "Port-de-Paix", "area": "Hispaniola", "terrain": HILL, "lon": -7283, "lat": 1994, "wealth": 2, "level": VILLAGE, "walls": 1, "land": 3, "ground": ROCKY, "forest": 50, "culture": LATIN},
	{"key": "leogane", "name": "Saint-Domingue", "city": "Leogane", "area": "Hispaniola", "terrain": FLAT, "lon": -7263, "lat": 1851, "wealth": 3, "level": TOWN, "walls": 1, "land": 3, "ground": GREEN, "forest": 40, "culture": LATIN},
	# Jamaica
	{"key": "port_royal", "name": "Port Royal", "city": "Port Royal", "area": "Jamaica", "terrain": FLAT, "lon": -7691, "lat": 1800, "wealth": 5, "level": TOWN, "walls": 2, "land": 4, "ground": GREEN, "forest": 40, "culture": LATIN},
	{"key": "sevilla_jamaica", "name": "Santiago de la Vega", "city": "Sevilla la Nueva", "area": "Jamaica", "terrain": HILL, "lon": -7705, "lat": 1836, "wealth": 3, "level": VILLAGE, "walls": 0, "land": 4, "ground": GREEN, "forest": 55, "culture": LATIN},
	# Puerto Rico
	{"key": "san_juan", "name": "San Juan Bautista", "city": "San Juan", "area": "Puerto Rico", "terrain": ROLLING, "lon": -6616, "lat": 1840, "wealth": 4, "level": TOWN, "walls": 1, "land": 5, "ground": GREEN, "forest": 35, "culture": LATIN},
	{"key": "san_german", "name": "San German", "city": "San German", "area": "Puerto Rico", "terrain": HILL, "lon": -6705, "lat": 1808, "wealth": 2, "level": VILLAGE, "walls": 0, "land": 5, "ground": GREEN, "forest": 45, "culture": LATIN},
	# Trinidad
	{"key": "port_of_spain", "name": "Trinidad", "city": "Port of Spain", "area": "Trinidad", "terrain": FLAT, "lon": -6150, "lat": 1070, "wealth": 3, "level": VILLAGE, "walls": 1, "land": 6, "ground": GREEN, "forest": 60, "culture": LATIN},
	# Interior and gap settlements (coastal bands; mostly independent)
	{"key": "karankawa", "name": "Karankawa Coast", "city": "Espiritu Santo", "area": "Texas", "terrain": FLAT, "lon": -9690, "lat": 2870, "wealth": 2, "level": VILLAGE, "walls": 0, "land": 0, "ground": DRY, "forest": 35, "culture": CELTIC},
	{"key": "atakapa", "name": "Atakapa", "city": "Atakapa Bayou", "area": "Gulf Coast", "terrain": FLAT, "lon": -9340, "lat": 3040, "wealth": 2, "level": VILLAGE, "walls": 0, "land": 0, "ground": GREEN, "forest": 60, "culture": CELTIC},
	{"key": "natchez", "name": "Natchez", "city": "Grand Village", "area": "Gulf Coast", "terrain": ROLLING, "lon": -9130, "lat": 3120, "wealth": 3, "level": VILLAGE, "walls": 1, "land": 0, "ground": GREEN, "forest": 60, "culture": CELTIC},
	{"key": "choctaw", "name": "Choctaw Towns", "city": "Chickasawhay", "area": "Gulf Coast", "terrain": ROLLING, "lon": -8880, "lat": 3120, "wealth": 3, "level": VILLAGE, "walls": 1, "land": 0, "ground": GREEN, "forest": 65, "culture": CELTIC},
	{"key": "apalachee", "name": "Apalachee", "city": "San Luis de Talimali", "area": "Florida", "terrain": ROLLING, "lon": -8430, "lat": 3040, "wealth": 4, "level": TOWN, "walls": 1, "land": 0, "ground": GREEN, "forest": 55, "culture": LATIN},
	{"key": "calusa", "name": "Calusa", "city": "Mound Key", "area": "Florida", "terrain": FLAT, "lon": -8160, "lat": 2685, "wealth": 2, "level": VILLAGE, "walls": 0, "land": 0, "ground": GREEN, "forest": 50, "culture": CELTIC},
	{"key": "tamaulipas", "name": "Tamaulipas", "city": "Soto la Marina", "area": "Mexico", "terrain": FLAT, "lon": -9800, "lat": 2440, "wealth": 2, "level": VILLAGE, "walls": 0, "land": 0, "ground": DRY, "forest": 25, "culture": CELTIC},
	{"key": "orizaba", "name": "Orizaba", "city": "Orizaba", "area": "Mexico", "terrain": HILL, "lon": -9710, "lat": 1885, "wealth": 4, "level": TOWN, "walls": 0, "land": 0, "ground": GREEN, "forest": 45, "culture": LATIN},
	{"key": "tabasco", "name": "Tabasco", "city": "Villahermosa", "area": "Mexico", "terrain": FLAT, "lon": -9290, "lat": 1790, "wealth": 3, "level": VILLAGE, "walls": 0, "land": 0, "ground": GREEN, "forest": 70, "culture": CELTIC},
	{"key": "valladolid", "name": "Valladolid", "city": "Valladolid", "area": "Yucatan", "terrain": FLAT, "lon": -8820, "lat": 2070, "wealth": 3, "level": VILLAGE, "walls": 1, "land": 0, "ground": ARID, "forest": 35, "culture": CELTIC},
	{"key": "comayagua", "name": "Comayagua", "city": "Comayagua", "area": "Central America", "terrain": HILL, "lon": -8760, "lat": 1445, "wealth": 4, "level": TOWN, "walls": 0, "land": 0, "ground": GREEN, "forest": 50, "culture": LATIN},
	{"key": "granada", "name": "Granada", "city": "Granada", "area": "Central America", "terrain": FLAT, "lon": -8595, "lat": 1193, "wealth": 4, "level": TOWN, "walls": 1, "land": 0, "ground": GREEN, "forest": 50, "culture": LATIN},
	{"key": "talamanca", "name": "Talamanca", "city": "Talamanca", "area": "Central America", "terrain": HILL, "lon": -8290, "lat": 930, "wealth": 2, "level": VILLAGE, "walls": 0, "land": 0, "ground": GREEN, "forest": 85, "culture": CELTIC},
	{"key": "veraguas", "name": "Veraguas", "city": "Santiago de Veraguas", "area": "Central America", "terrain": ROLLING, "lon": -8130, "lat": 860, "wealth": 3, "level": VILLAGE, "walls": 0, "land": 0, "ground": GREEN, "forest": 70, "culture": CELTIC},
	{"key": "darien", "name": "Darien", "city": "Yaviza", "area": "Central America", "terrain": FLAT, "lon": -7790, "lat": 860, "wealth": 2, "level": VILLAGE, "walls": 1, "land": 0, "ground": GREEN, "forest": 85, "culture": CELTIC},
	{"key": "barquisimeto", "name": "Barquisimeto", "city": "Barquisimeto", "area": "Spanish Main", "terrain": ROLLING, "lon": -6930, "lat": 1000, "wealth": 3, "level": TOWN, "walls": 0, "land": 1, "ground": DRY, "forest": 25, "culture": LATIN},
	{"key": "calabozo", "name": "Los Llanos", "city": "Calabozo", "area": "Spanish Main", "terrain": FLAT, "lon": -6740, "lat": 890, "wealth": 2, "level": VILLAGE, "walls": 0, "land": 1, "ground": DRY, "forest": 15, "culture": LATIN},
]

## Land routes (one turn each way): neighbouring settlements on one landmass.
const ROUTES: Array = [
	["tampico", "tamaulipas"], ["tampico", "veracruz"], ["veracruz", "orizaba"], ["veracruz", "tabasco"],
	["tabasco", "campeche"], ["tabasco", "tayasal"], ["campeche", "merida"], ["campeche", "tayasal"],
	["merida", "valladolid"], ["valladolid", "belize"], ["tayasal", "belize"], ["tayasal", "trujillo"],
	["belize", "trujillo"], ["trujillo", "comayagua"], ["trujillo", "cabo_gracias"], ["comayagua", "granada"],
	["cabo_gracias", "bluefields"], ["bluefields", "granada"], ["bluefields", "talamanca"],
	["talamanca", "veraguas"], ["veraguas", "portobelo"], ["portobelo", "darien"],
	["tamaulipas", "karankawa"], ["karankawa", "atakapa"], ["atakapa", "new_orleans"], ["atakapa", "natchez"],
	["natchez", "new_orleans"], ["natchez", "choctaw"], ["choctaw", "new_orleans"], ["choctaw", "pensacola"],
	["new_orleans", "pensacola"], ["pensacola", "apalachee"], ["apalachee", "st_augustine"],
	["apalachee", "calusa"], ["st_augustine", "calusa"],
	["cartagena", "santa_marta"], ["cartagena", "mompox"], ["santa_marta", "mompox"],
	["santa_marta", "maracaibo"], ["mompox", "maracaibo"], ["maracaibo", "coro"], ["maracaibo", "barquisimeto"],
	["coro", "barquisimeto"], ["coro", "la_guaira"], ["barquisimeto", "la_guaira"], ["barquisimeto", "calabozo"],
	["calabozo", "la_guaira"], ["la_guaira", "cumana"], ["calabozo", "cumana"],
	["havana", "puerto_principe"], ["puerto_principe", "santiago_de_cuba"],
	["santo_domingo", "santiago_caballeros"], ["santiago_caballeros", "port_de_paix"],
	["port_de_paix", "leogane"], ["leogane", "santo_domingo"],
	["port_royal", "sevilla_jamaica"], ["san_juan", "san_german"],
]

## Sea lanes between ports (one turn). Every port is on at least one; an
## island's ports reach the mainland and the neighbouring islands.
const SEA_LANES: Array = [
	["havana", "st_augustine"], ["havana", "pensacola"], ["havana", "new_orleans"], ["havana", "veracruz"],
	["havana", "campeche"], ["havana", "santiago_de_cuba"],
	["new_orleans", "pensacola"], ["pensacola", "st_augustine"], ["new_orleans", "veracruz"],
	["tampico", "veracruz"], ["veracruz", "campeche"],
	["campeche", "belize"], ["belize", "trujillo"], ["belize", "port_royal"], ["trujillo", "cabo_gracias"],
	["cabo_gracias", "bluefields"], ["cabo_gracias", "port_royal"], ["bluefields", "portobelo"],
	["portobelo", "cartagena"], ["portobelo", "port_royal"], ["cartagena", "port_royal"],
	["cartagena", "santa_marta"], ["santa_marta", "maracaibo"], ["maracaibo", "coro"], ["coro", "la_guaira"],
	["la_guaira", "cumana"], ["cumana", "port_of_spain"], ["la_guaira", "san_juan"],
	["santiago_de_cuba", "port_royal"], ["santiago_de_cuba", "port_de_paix"], ["port_royal", "leogane"],
	["leogane", "santo_domingo"], ["port_de_paix", "leogane"], ["santo_domingo", "san_german"],
	["santo_domingo", "san_juan"], ["san_juan", "san_german"], ["san_juan", "port_of_spain"],
	["havana", "port_royal"],
	# The Carrera de Indias and the Windward Passage (2026-10-22): Havana is the
	# gathering port for the Tierra Firme fleets.
	["havana", "portobelo"], ["havana", "cartagena"], ["havana", "santo_domingo"],
	["port_royal", "santo_domingo"], ["cartagena", "santo_domingo"],
]

## Lane trade a turn where the Carrera de Indias beats the default ((level_a + level_b) x LANE_BASE, campaign/cdata.gd):
## [port, port, gold] in either order. The silver lanes into Havana and the Windward Passage carry more than
## their ports' size says.
const SEA_LANE_TRADE: Array = [
	["havana", "portobelo", 28], ["havana", "cartagena", 24], ["havana", "veracruz", 24],
	["havana", "santo_domingo", 20], ["port_royal", "portobelo", 20], ["port_royal", "cartagena", 20],
]

## Lanes from a port out to the open sea at the map's edge: [port region key,
## grid x, grid y] (campaign/clanes.gd). The Florida channel: Havana through the
## Straits and up the Gulf Stream to the Atlantic edge, the fleets' way home.
const SEA_LANE_EXITS: Array = [
	["havana", 187, 6],
]

## Factions (see rome.gd). Armies, mixes and compositions in the West rows
## (slice 2a, 2026-10-14). "pirate": 1 (N2, campaign/csea.gd): raiders with
## havens, plunder, sacks, infamy and letters of marque; alive while afloat.
## "no_marque": 1 (N2): grants pirates no letter of marque (the Crown).
## "palette" (a sprite palette key, game/sprite_atlas.gd; the West factions have
## their own, named like the faction) and "blurb" are view-only.
const FACTIONS: Array[Dictionary] = [
	{"key": "new_spain", "culture": LATIN, "name": "New Spain", "adj": "Spanish", "color": "d9a31f", "capital": "havana", "no_marque": 1,
		"palette": "new_spain", "blurb": "Gold-drunk viceroys and iron galleons: the Crown's heavy line holds the Indies, and God help whoever says otherwise.",
		"regions": ["havana", "puerto_principe", "santiago_de_cuba", "veracruz", "tampico", "campeche", "merida", "st_augustine"], "treasury": 1600,
		"armies": [["havana", ["musketeers", "w_pikemen", "musketeers", "rodeleros", "lancers", "light_gun", "general"]],
			["veracruz", ["musketeers", "w_pikemen", "rodeleros", "general"]],
			["santiago_de_cuba", ["w_pikemen", "musketeers", "general"]]],
		"mix": {"musket": 35, "pike": 25, "heavy": 15, "cav": 12, "light_gun": 3, "field_gun": 3, "mortar": 2, "general": 4, "dogs": 2},
		"ai_style": AI_BALANCED, "composition": {"arms": ["musket", "pike", "heavy"], "art_pct": 10, "cav_pct": 10, "upgrade": 2}},
	{"key": "tierra_firme", "culture": LATIN, "name": "Tierra Firme", "adj": "Tierra Firme", "color": "e0702a", "capital": "cartagena", "no_marque": 1,
		"palette": "tierra_firme", "blurb": "The silver coast of the Spanish Main, where every mule-train is a king's ransom and every watchtower a loaded gun.",
		"regions": ["cartagena", "santa_marta", "mompox", "portobelo", "maracaibo", "coro", "la_guaira"], "treasury": 1800,
		"armies": [["cartagena", ["w_pikemen", "musketeers", "musketeers", "rodeleros", "lancers", "lancers", "general"]],
			["portobelo", ["musketeers", "w_pikemen", "lancers", "general"]]],
		"mix": {"musket": 30, "pike": 20, "heavy": 15, "cav": 25, "light_gun": 3, "mortar": 2, "general": 4},
		"ai_style": AI_CAUTIOUS, "composition": {"arms": ["cav", "musket", "pike"], "art_pct": 5, "cav_pct": 25, "upgrade": 1}},
	{"key": "england", "culture": GREEK, "name": "England", "adj": "English", "color": "c8402f", "capital": "port_royal",
		"palette": "england", "blurb": "Roundheads turned rum-runners: a few sturdy pike-blocks, a lot of cannon, and a firm belief that Jamaica is a perfectly good place to be sent for treason.",
		"regions": ["port_royal", "sevilla_jamaica", "belize"], "treasury": 1800,
		"armies": [["port_royal", ["w_pikemen", "w_pikemen", "musketeers", "musketeers", "musketeers", "pistoleers", "pistoleers", "light_gun", "general"]],
			["sevilla_jamaica", ["w_pikemen", "musketeers", "musketeers", "general"]]],
		"mix": {"musket": 37, "pike": 25, "grenadier": 3, "pistol": 17, "dragoon": 3, "light_gun": 5, "field_gun": 3, "mortar": 2, "general": 4},
		"ai_style": AI_BALANCED, "composition": {"arms": ["musket", "pike", "pistol"], "art_pct": 10, "cav_pct": 20, "upgrade": 1}},
	{"key": "france", "culture": GREEK, "name": "France", "adj": "French", "color": "3f7fd8", "capital": "leogane",
		"palette": "france", "blurb": "Lilies, lace and lead shot: the buccaneers of Saint-Domingue fight like cavaliers and drink like musketeers.",
		"regions": ["leogane", "new_orleans"], "treasury": 1600,
		"armies": [["leogane", ["musketeers", "musketeers", "w_pikemen", "buccaneers", "buccaneers", "pistoleers", "general"]],
			["new_orleans", ["musketeers", "w_pikemen", "buccaneers", "general"]]],
		"mix": {"musket": 33, "pike": 20, "buccaneer": 25, "pistol": 12, "dragoon": 3, "mortar": 2, "general": 4},
		"ai_style": AI_BALANCED, "composition": {"arms": ["musket", "buccaneer", "pike"], "art_pct": 0, "cav_pct": 15, "upgrade": 1}},
	{"key": "dutch", "culture": PUNIC, "name": "The Dutch", "adj": "Dutch", "color": "2fa8a0", "capital": "port_of_spain",
		"palette": "dutch", "blurb": "Herring, tulips and a West India Company with a very large ledger: they will sell you the rope and then the gallows.",
		"regions": ["port_of_spain", "cumana"], "treasury": 2200,
		"armies": [["port_of_spain", ["musketeers", "musketeers", "musketeers", "w_pikemen", "w_pikemen", "field_gun", "light_gun", "general"]],
			["cumana", ["musketeers", "musketeers", "w_pikemen", "light_gun", "general"]]],
		"mix": {"musket": 40, "pike": 25, "light_gun": 15, "field_gun": 7, "mortar": 3, "general": 4},
		"ai_style": AI_CAUTIOUS, "composition": {"arms": ["musket", "pike", "light_gun"], "art_pct": 25, "cav_pct": 0, "upgrade": 1}},
	{"key": "brethren", "culture": PUNIC, "name": "Brethren of the Coast", "adj": "Pirate", "color": "4a4a52", "capital": "port_de_paix", "pirate": 1,
		"palette": "brethren", "blurb": "Calico, cutlasses and a black flag over every stolen town: no king, no quarter, and the rum is never, ever finished.",
		"regions": ["port_de_paix", "trujillo"], "treasury": 1500,
		"armies": [["port_de_paix", ["buccaneers", "buccaneers", "cutlass", "cutlass", "musketeers", "light_gun", "general"]],
			["trujillo", ["buccaneers", "cutlass", "cutlass", "general"]]],
		"mix": {"buccaneer": 35, "heavy": 35, "musket": 20, "light_gun": 5, "general": 4},
		"ai_style": AI_AGGRESSIVE, "composition": {"arms": ["buccaneer", "heavy", "musket"], "art_pct": 5, "cav_pct": 0, "upgrade": 0}},
	{"key": "itza", "culture": CELTIC, "name": "Maya Itza", "adj": "Itza", "color": "2f9e5a", "capital": "tayasal",
		"palette": "itza", "blurb": "The last free Maya kingdom, behind its lake and a wall of jungle: obsidian blades, jade crowns and a patience older than Spain.",
		"regions": ["tayasal", "valladolid"], "treasury": 1200,
		"armies": [["tayasal", ["native_warriors", "native_warriors", "native_warriors", "native_warriors", "native_warriors", "native_warriors", "native_bowmen", "native_bowmen", "native_bowmen", "chieftain"]],
			["tayasal", ["native_warriors", "native_warriors", "native_warriors", "native_bowmen", "chieftain"]]],
		"mix": {"light": 52, "heavy": 8, "archer": 35, "general": 4},
		"ai_style": AI_CAUTIOUS, "composition": {"arms": ["light", "archer"], "art_pct": 0, "cav_pct": 0, "upgrade": 0}},
	{"key": "miskito", "culture": CELTIC, "name": "Miskito", "adj": "Miskito", "color": "8a4fc4", "capital": "cabo_gracias",
		"palette": "miskito", "blurb": "Lords of the Mosquito Coast, friends of every English pirate and the dread of every Spanish clerk: harpoon, longboat and a very long memory.",
		"regions": ["cabo_gracias", "bluefields", "talamanca"], "treasury": 1200,
		"armies": [["cabo_gracias", ["native_warriors", "native_warriors", "native_warriors", "native_bowmen", "native_bowmen", "musketeers", "chieftain"]],
			["bluefields", ["native_warriors", "native_warriors", "native_bowmen", "chieftain"]]],
		"mix": {"light": 50, "archer": 30, "musket": 15, "general": 4},
		"ai_style": AI_CAUTIOUS, "composition": {"arms": ["light", "archer", "musket"], "art_pct": 0, "cav_pct": 0, "upgrade": 0}},
]

## Building chains in the West's words (CData.CHAINS; the same keys, levels,
## costs and rules as Rome's, only the texts differ, and the Workshop has a
## third level for the heavy guns; owner 2026-10-23). The Shipyard is added
## by CData (SHIPS).
const CHAINS: Array[Dictionary] = [
	{"key": "farm", "name": "Farms", "levels": 3, "cost": [400, 900, 1600], "turns": [1, 2, 3],
		"desc": "+1 growth and +40 income per level; from level 2 granaries make a siege's supplies last a turn longer"},
	{"key": "market", "name": "Market", "levels": 3, "cost": [500, 1000, 1800], "turns": [1, 2, 3],
		"desc": "+90 income per level; +15% trade income per level"},
	{"key": "barracks", "name": "Barracks", "levels": 3, "cost": [400, 900, 1600], "turns": [1, 2, 3],
		"desc": "Pikemen (veterans at level 2), rodeleros, cutlass men and native warriors, and the general's guard (level 1; one general an army); Miskito canoe raiders (level 1); boarding grenadiers (the Brethren) and holcan (the Itza) at level 2; England's grenadiers at level 3; war dogs (level 1, with Stables 1); faster replenishment"},
	{"key": "range", "name": "Range", "levels": 3, "cost": [350, 800, 1400], "turns": [1, 2, 3],
		"desc": "Musketeers (level 1; veterans level 2), buccaneers (France's coureurs des bois at level 2) and native bowmen; the pistol horse and the dragoons need a Range 1 too; faster replenishment"},
	{"key": "stables", "name": "Stables", "levels": 3, "cost": [500, 1000, 1800], "turns": [1, 2, 3],
		"desc": "Lancers (level 1), pistoleers (level 1, with a Range 1), cuirassiers and the dragoons of England and France (level 2, with a Range 1); faster replenishment"},
	{"key": "workshop", "name": "Workshop", "levels": 3, "cost": [600, 1200, 2000], "turns": [2, 3, 3],
		"desc": "Level 1 falconets (light guns) and the hand cart (ammunition), level 2 culverins and ammunition wagons (with Stables), level 3 heavy guns (24-pounders) and the nations' mortars: siege pieces that breach bastions and shell forts"},
	{"key": "walls", "name": "Walls", "levels": 3, "cost": [400, 900, 1600], "turns": [2, 2, 3],
		"desc": "Stockade, bastions and batteries: +1 garrison unit, better garrison and higher ground for the defenders per level"},
]

## Rosters (slice 2a): pike and shot for the Europeans (Spain's rodeleros and
## lancers, England's pistol horse and cuirassiers, the Dutch guns, France's
## buccaneers and pistoleers), buccaneers and cutlass men for the Brethren,
## warriors and bowmen for the natives (the Miskito with English trade
## muskets). Generals, war dogs and wagons are shared Rome rows.
const ROSTERS := {
	"new_spain": {"musket": ["musketeers", "musketeers2", ""], "pike": ["w_pikemen", "w_pikemen2", ""],
		"heavy": ["rodeleros", "", ""], "cav": ["lancers", "", ""], "light_gun": ["light_gun"], "field_gun": ["field_gun", "heavy_gun"],
		"mortar": ["mortar"], "siege": ["wagon", "wagon2", "wagon3"], "general": ["general"], "dogs": ["dog_handlers"]},
	"tierra_firme": {"musket": ["musketeers", "musketeers2", ""], "pike": ["w_pikemen", "w_pikemen2", ""],
		"heavy": ["rodeleros", "", ""], "cav": ["lancers", "", ""], "light_gun": ["light_gun"], "field_gun": ["", "heavy_gun"],
		"mortar": ["mortar"], "siege": ["wagon", "wagon2", "wagon3"], "general": ["general"]},
	"england": {"musket": ["musketeers", "musketeers2", ""], "pike": ["w_pikemen", "w_pikemen2", ""],
		"pistol": ["pistoleers", "cuirassiers", ""], "light_gun": ["light_gun"], "field_gun": ["field_gun", "heavy_gun"],
		"grenadier": ["grenadiers", "", ""], "dragoon": ["dragoons", "", ""], "mortar": ["mortar"],
		"siege": ["wagon", "wagon2", "wagon3"], "general": ["general"]},
	"france": {"musket": ["musketeers", "musketeers2", ""], "pike": ["w_pikemen", "w_pikemen2", ""],
		"buccaneer": ["buccaneers", "coureurs", ""], "pistol": ["pistoleers", "cuirassiers", ""], "field_gun": ["", "heavy_gun"],
		"dragoon": ["dragoons", "", ""], "mortar": ["mortar"], "siege": ["wagon", "wagon2", "wagon3"], "general": ["general"]},
	"dutch": {"musket": ["musketeers", "musketeers2", ""], "pike": ["w_pikemen", "w_pikemen2", ""],
		"light_gun": ["light_gun"], "field_gun": ["field_gun", "heavy_gun"], "mortar": ["mortar"], "siege": ["wagon", "wagon2", "wagon3"], "general": ["general"]},
	"brethren": {"buccaneer": ["buccaneers", "", ""], "musket": ["musketeers", "", ""], "heavy": ["cutlass", "boarding_grenadiers", ""],
		"light_gun": ["light_gun"], "siege": ["wagon", "", ""], "general": ["general"]},
	"itza": {"light": ["native_warriors", "", ""], "heavy": ["", "holcan", ""], "archer": ["native_bowmen", "", ""], "siege": ["wagon", "", ""],
		"general": ["chieftain"]},
	"miskito": {"light": ["native_warriors", "canoe_raiders", ""], "archer": ["native_bowmen", "", ""], "musket": ["musketeers", "", ""],
		"siege": ["wagon", "", ""], "general": ["chieftain"]},
	"independent": {"musket": ["musketeers", "musketeers2", ""], "pike": ["w_pikemen", "w_pikemen2", ""],
		"light": ["native_warriors", "", ""], "archer": ["native_bowmen", "", ""]},
}

const START_WARS: Array = [
	["new_spain", "england"], ["new_spain", "brethren"], ["tierra_firme", "brethren"],
	["brethren", "dutch"],
]

## (Guns carry no special kinds yet; the native bowmen fire arrows.)
const AMMO_AVAIL: Array = [
	["fire_arrows", ["itza", "miskito"], RANGE, 2],
]

const KEY_CITIES: Array[String] = ["havana", "cartagena", "veracruz", "portobelo", "port_royal", "santo_domingo"]

const NAMES_SPANISH: Array[String] = ["Don Alonso de Mendoza", "Don Diego de Leon", "Don Fernando Ortiz", "Don Rodrigo de Silva",
	"Don Juan de Valdes", "Don Gaspar de Cordoba", "Don Pedro de Alvarado", "Don Luis de Guzman", "Don Hernan de Soto",
	"Don Garcia de Toledo", "Don Esteban Navarro", "Don Alvaro de Bazan"]
const NAMES_ENGLISH: Array[String] = ["Sir Henry Morgan", "Captain William Penn", "Sir Thomas Modyford", "Colonel Edward Doyley",
	"Admiral Robert Venables", "Sir Christopher Myngs", "Captain John Davis", "Lord Francis Willoughby", "Major Thomas Whetstone",
	"Sir William Stapleton", "Captain Edward Mansvelt", "Colonel Thomas Lynch"]
const NAMES_FRENCH: Array[String] = ["Le Chevalier de Fontenay", "Bertrand d'Ogeron", "Le Marquis de Poincy", "Jean-Baptiste du Casse",
	"Monsieur Laurent de Graaf", "Le Comte de Cussy", "Francois Le Clerc", "Pierre le Grand", "Le Vicomte de Rochefort",
	"Michel de Grammont", "Jacques de Pouancay", "Le Baron de Pointis"]
const NAMES_DUTCH: Array[String] = ["Admiral Piet Heyn", "Willem Blauvelt", "Jan van Riebeeck", "Admiral Michiel de Ruyter",
	"Kapitein Adriaen Pater", "Johan Maurits", "Cornelis Jol", "Pieter Stuyvesant", "Abraham Blauvelt", "Hendrik Lonck",
	"Jacob Binckes", "Laurens Prins"]
const NAMES_PIRATE: Array[String] = ["Calico Jack", "Black Bart", "Mad Mary Redtooth", "One-Eyed Ned", "Captain Scarlet",
	"Bloody Ben", "Sawtooth Sal", "Rum-Barrel Roberts", "Hook-Hand Harry", "Blackheart Bess", "Cutlass Kate", "Dead-Man Dick"]
const NAMES_MAYA: Array[String] = ["Kan Ek", "Ahau Chan", "Pakal Balam", "Yax Mut", "Ix Chel", "Kukulcan", "Itzamna Ahau",
	"Balam Ku", "Chac Xib", "Yaxha Tun", "Ahkin Pop", "Zac Nicte"]
const NAMES_MISKITO: Array[String] = ["Oldman", "Jeremy", "Admiral Dawkins", "Captain Bluefield", "Tuktuk Sirpi",
	"Wawa Kiamp", "Yapti Tara", "Sula Kaka", "Tininiska", "Prince Peter", "Kiaki Mairin", "Dilpa Bila"]
const NAMES: Dictionary = {LATIN: NAMES_SPANISH, GREEK: NAMES_ENGLISH, PUNIC: NAMES_DUTCH, CELTIC: NAMES_MAYA}
const NAMES_BY_FACTION: Dictionary = {"france": NAMES_FRENCH, "england": NAMES_ENGLISH, "dutch": NAMES_DUTCH,
	"brethren": NAMES_PIRATE, "itza": NAMES_MAYA, "miskito": NAMES_MISKITO}
const NAMES_DEFAULT: Array[String] = NAMES_SPANISH
