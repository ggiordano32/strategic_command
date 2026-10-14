extends RefCounted
## Ships of the West pack (N1, fleets on the campaign map; DESIGN "The
## Caribbean pack: ships, pirates, cover, asymmetry"). Referenced from
## campaign/data/west.gd as SHIPS; a pack without a SHIPS script has no
## fleets (Rome keeps its sea lanes). Read through CData.ships_on() /
## CData.ship_rows() / CData.SHIP_*; the rules are in campaign/cfleet.gd.
##
## Ship rows: key, name, cost (gold), upkeep (gold a turn), guns, hull and
## crew (the ship at full strength; a fleet's ships carry hull and crew as %
## of these), speed (movement points a turn on a beam reach: a straight step
## costs 10 there, a diagonal 14), cap (army units carried), coastal (1: only
## on sea cells within COASTAL_CELLS of land), oars (1: rowed, the wind does
## not change its pace), yard (Shipyard level needed; 0: any port of ours,
## no shipyard), factions (faction keys that build it; captured ships of
## other kinds are kept).

const ROWS: Array[Dictionary] = [
	{"key": "sloop", "name": "Sloop", "cost": 300, "upkeep": 15, "guns": 8, "hull": 30, "crew": 60, "speed": 400,
		"cap": 1, "coastal": 0, "oars": 0, "yard": 1,
		"factions": ["new_spain", "tierra_firme", "england", "france", "dutch", "brethren", "miskito"],
		"desc": "Fast and handy, a few light guns: scouting, raiding and one company of men."},
	{"key": "brigantine", "name": "Brigantine", "cost": 500, "upkeep": 25, "guns": 14, "hull": 45, "crew": 90, "speed": 370,
		"cap": 2, "coastal": 0, "oars": 0, "yard": 1,
		"factions": ["england", "france", "dutch", "brethren"],
		"desc": "Two masts and a long reach: the pirates' and the traders' favourite."},
	{"key": "frigate", "name": "Frigate", "cost": 900, "upkeep": 45, "guns": 30, "hull": 70, "crew": 200, "speed": 340,
		"cap": 3, "coastal": 0, "oars": 0, "yard": 2,
		"factions": ["new_spain", "tierra_firme", "england", "france", "dutch"],
		"desc": "A fast warship with a full gun deck: the workhorse of every navy."},
	{"key": "galleon", "name": "Galleon", "cost": 1400, "upkeep": 70, "guns": 40, "hull": 110, "crew": 300, "speed": 240,
		"cap": 6, "coastal": 0, "oars": 0, "yard": 3,
		"factions": ["new_spain", "tierra_firme"],
		"desc": "Slow, high-castled and heavy: a treasure hold and room for a regiment."},
	{"key": "ship_of_the_line", "name": "Ship of the line", "cost": 2000, "upkeep": 100, "guns": 70, "hull": 150, "crew": 500,
		"speed": 280, "cap": 4, "coastal": 0, "oars": 0, "yard": 3,
		"factions": ["england", "dutch"],
		"desc": "Two gun decks and a broadside nothing else on these seas can answer."},
	{"key": "war_canoe", "name": "War canoe", "cost": 120, "upkeep": 5, "guns": 2, "hull": 10, "crew": 40, "speed": 300,
		"cap": 1, "coastal": 1, "oars": 1, "yard": 0,
		"factions": ["itza", "miskito"],
		"desc": "Piraguas and dugouts: rowed, fast along the shore whatever the wind, never out of sight of land."},
]

## Coastal ships keep to sea cells within this many cells (Chebyshev) of land.
const COASTAL_CELLS := 2

## The map's wind (the trade winds; equal to relief_west / tools/geo/carib.json
## WIND, which the view reads through GeoFields.wind_dir()): blowing FROM this
## bearing (degrees, 0 north, 90 east), strength 0-100 (kept for the real-time
## sea battles, N3; the reach table below is for this wind).
const WIND_FROM_DEG := 90
const WIND_STRENGTH := 80
## Pace by heading, % of the beam-reach pace, by the angle between the
## heading and the way the wind blows (0: running before it, 45, 90: on the
## beam, 135: close-hauled, 180: dead into it, made good by tacking).
const WIND_PCT: Array[int] = [125, 115, 100, 75, 60]

## Shipyards at the start: [region key, level] (in the slots of the region,
## over its cap if full).
const START_YARDS: Array = [
	["havana", 3], ["veracruz", 2], ["cartagena", 3], ["portobelo", 1], ["port_royal", 2], ["leogane", 2],
	["new_orleans", 1], ["port_of_spain", 2], ["port_de_paix", 1], ["cabo_gracias", 1],
]

## Fleets at the start: [faction key, region key (in its dock), [ship keys]].
const START_FLEETS: Array = [
	["new_spain", "havana", ["galleon", "frigate", "sloop"]],
	["new_spain", "veracruz", ["galleon"]],
	["new_spain", "santiago_de_cuba", ["frigate"]],
	["tierra_firme", "cartagena", ["galleon", "frigate"]],
	["tierra_firme", "portobelo", ["frigate"]],
	["england", "port_royal", ["frigate", "frigate", "sloop", "sloop"]],
	["france", "leogane", ["frigate", "sloop", "sloop", "sloop"]],
	["france", "new_orleans", ["sloop", "sloop"]],
	["dutch", "port_of_spain", ["frigate", "frigate", "sloop", "sloop"]],
	["brethren", "port_de_paix", ["brigantine", "brigantine", "sloop", "sloop", "sloop"]],
	["brethren", "trujillo", ["sloop", "sloop"]],
	["itza", "valladolid", ["war_canoe", "war_canoe"]],
	["miskito", "cabo_gracias", ["war_canoe", "war_canoe", "war_canoe", "sloop"]],
]
