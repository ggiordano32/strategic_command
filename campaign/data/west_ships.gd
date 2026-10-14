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

# ------------------------------------------------------------------- N2 ---
# Trade at sea, blockades, the flota and the pirate loop (campaign/csea.gd;
# docs/CAMPAIGN.md "Trade, blockades, the flota and pirates (N2)").

## A port's trade travels by sea: SEA_TRADE_PCT % of its wealth income plus
## its markets' income. An enemy fleet at war within BLOCKADE_CELLS
## (Chebyshev) of its harbour, stronger than the owner's side there,
## blockades it: the owner loses BLOCKADE_CUT_PCT % of that trade a turn and
## the blockader takes BLOCKADE_TAKE_PCT % of what is lost (a pirate
## PIRATE_TAKE_PCT %).
const SEA_TRADE_PCT := 100
const BLOCKADE_CELLS := 3
const BLOCKADE_CUT_PCT := 75
const BLOCKADE_TAKE_PCT := 40
const PIRATE_TAKE_PCT := 80

## A ship taken in a sea battle pays its captor PRIZE_PCT % of its cost
## (a pirate PIRATE_PRIZE_PCT %); a treasure galleon its treasure besides.
## A lost treasure ship is taken (not sunk) at least TREASURE_TAKEN_PCT %.
const PRIZE_PCT := 25
const PIRATE_PRIZE_PCT := 50
const TREASURE_TAKEN_PCT := 70

## The flota: from turn FLOTA_FIRST, every FLOTA_EVERY turns, the treasure
## galleons gather (at the end of the turn before) in the docks of
## FLOTA_PARTS [origin region, faction it pays, [ship keys]] (a part sails
## while its origin is held by that faction or the flota's owner), sail to
## FLOTA_MEET's dock (Havana; parts that arrive wait up to FLOTA_WAIT turns
## for the others and join), then to FLOTA_EXIT [x, y] (a cell of the open
## sea on the map's north edge: home to Spain by the Gulf Stream), where it
## leaves the map. Each galleon carries FLOTA_GOLD (paid to its faction on
## arrival, or to whoever takes it); crews thin at FLOTA_CREW %. Owned by
## FLOTA_OWNER (else the first part's faction alive); sailed by the rules,
## not by its owner's orders.
const FLOTA_FIRST := 4
const FLOTA_EVERY := 8
const FLOTA_OWNER := "new_spain"
const FLOTA_PARTS: Array = [
	["veracruz", "new_spain", ["galleon", "galleon"]],
	["portobelo", "tierra_firme", ["galleon", "galleon"]],
]
const FLOTA_MEET := "havana"
const FLOTA_WAIT := 2
const FLOTA_EXIT: Array[int] = [96, 0]
const FLOTA_GOLD := 900
const FLOTA_CREW := 50

## Pirates (factions with "pirate": 1, the Brethren). Their regions yield
## PIRATE_LAND_PCT % of the usual income; their crews sail for shares, so
## their upkeep (ships and men) is PIRATE_UPKEEP_PCT %. A pirate faction is
## not eliminated while it has a ship.
const PIRATE_LAND_PCT := 75
const PIRATE_UPKEEP_PCT := 50
## Beaten pirate ships scatter: each is lost at this % of the usual chance
## (fast hulls, no colours to defend).
const PIRATE_ESCAPE_PCT := 50

## Sacking: a pirate army that wins an assault on a port (a region with a
## harbour) may sack it instead of taking it (policy: the faction's
## "sack_pol" 0 auto (the AI's rule: hold while it has fewer than
## PIRATE_HOLD regions, else sack), 1 sack, 2 hold). The sack takes
## SACK_TURNS turns of the region's income and SACK_TREASURY_PCT % of its
## owner's treasury (at most SACK_TREASURY_MAX); every building loses a
## level, the growth is halved; the owner keeps it. A region sacked in the
## last SACK_COOLDOWN turns yields a quarter (and the AI leaves it alone).
const PIRATE_HOLD := 2
const SACK_TURNS := 3
const SACK_TREASURY_PCT := 15
const SACK_TREASURY_MAX := 1000
const SACK_COOLDOWN := 8

## Havens (pirate-held ports): HAVEN_UNITS are HAVEN_PCT % cheaper (+ 1 %
## per 5 infamy, at most HAVEN_MAX_PCT %); one more recruit a turn per
## HAVEN_RECRUIT_INFAMY infamy (at most 2); pirate ships there repair
## HAVEN_REPAIR more.
const HAVEN_UNITS: Array[String] = ["buccaneers", "cutlass"]
const HAVEN_PCT := 20
const HAVEN_MAX_PCT := 45
const HAVEN_RECRUIT_INFAMY := 30
const HAVEN_REPAIR := 10

## Infamy (pirates, 0..INFAMY_MAX): + INFAMY_SACK a sack, + INFAMY_PRIZE a
## ship taken (+ INFAMY_TREASURE a treasure galleon), + 1 a port blockaded a
## turn; - INFAMY_DECAY a turn. The nations' AI hunts pirates harder by it.
const INFAMY_MAX := 100
const INFAMY_SACK := 12
const INFAMY_PRIZE := 3
const INFAMY_TREASURE := 8
const INFAMY_DECAY := 1

## Letters of marque (a treaty between a nation and a pirate faction): at
## peace with each other for MARQUE_TURNS turns (then it lapses; war breaks
## it); the pirates' plunder from the nation's enemies at war is
## MARQUE_BONUS_PCT % more. The AI nation offers one (MARQUE_ASK_CHANCE % a
## turn) while at war with another nation; an AI pirate accepts while the
## nation has such an enemy and it holds no other letter; an AI nation
## grants one asked for while its infamy is under MARQUE_INFAMY_MAX.
const MARQUE_TURNS := 12
const MARQUE_BONUS_PCT := 50
const MARQUE_ASK_CHANCE := 15
const MARQUE_INFAMY_MAX := 60
