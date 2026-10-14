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
## no shipyard), storm (N2b: % chance a hurricane's core sinks it at sea),
## factions (faction keys that build it; captured ships of other kinds are
## kept).

const ROWS: Array[Dictionary] = [
	{"key": "sloop", "name": "Sloop", "cost": 300, "upkeep": 15, "guns": 8, "hull": 30, "crew": 60, "speed": 400,
		"cap": 1, "coastal": 0, "oars": 0, "yard": 1, "storm": 8,
		"factions": ["new_spain", "tierra_firme", "england", "france", "dutch", "brethren", "miskito"],
		"desc": "Fast and handy, a few light guns: scouting, raiding and one company of men."},
	{"key": "brigantine", "name": "Brigantine", "cost": 500, "upkeep": 25, "guns": 14, "hull": 45, "crew": 90, "speed": 370,
		"cap": 2, "coastal": 0, "oars": 0, "yard": 1, "storm": 12,
		"factions": ["england", "france", "dutch", "brethren"],
		"desc": "Two masts and a long reach: the pirates' and the traders' favourite."},
	{"key": "frigate", "name": "Frigate", "cost": 900, "upkeep": 45, "guns": 30, "hull": 70, "crew": 200, "speed": 340,
		"cap": 3, "coastal": 0, "oars": 0, "yard": 2, "storm": 16,
		"factions": ["new_spain", "tierra_firme", "england", "france", "dutch"],
		"desc": "A fast warship with a full gun deck: the workhorse of every navy."},
	{"key": "galleon", "name": "Galleon", "cost": 1400, "upkeep": 70, "guns": 40, "hull": 110, "crew": 300, "speed": 240,
		"cap": 6, "coastal": 0, "oars": 0, "yard": 3, "storm": 35,
		"factions": ["new_spain", "tierra_firme"],
		"desc": "Slow, high-castled and heavy: a treasure hold and room for a regiment."},
	{"key": "ship_of_the_line", "name": "Ship of the line", "cost": 2000, "upkeep": 100, "guns": 70, "hull": 150, "crew": 500,
		"speed": 280, "cap": 4, "coastal": 0, "oars": 0, "yard": 3, "storm": 18,
		"factions": ["england", "dutch"],
		"desc": "Two gun decks and a broadside nothing else on these seas can answer."},
	{"key": "war_canoe", "name": "War canoe", "cost": 120, "upkeep": 5, "guns": 2, "hull": 10, "crew": 40, "speed": 300,
		"cap": 1, "coastal": 1, "oars": 1, "yard": 0, "storm": 45,
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
const FLOTA_GOLD := 600
## (N2b) The flota's capitana (its first galleon) carries the big chest.
const FLOTA_CAPITANA_GOLD := 1800
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


# ------------------------------------------------------------------ N2b ---
# Hurricanes, notorious captains, named treasure galleons (campaign/cstorm.gd,
# campaign/ccaptain.gd, campaign/csea.gd; docs/CAMPAIGN.md "Hurricanes,
# captains and named galleons (N2b)").

## Hurricanes. The season is the summer turn (CData.date_text: even turns).
## At the end of the turn before it, 0-2 storms form (STORM_FORM_PCT: the
## chance of at least one, of a second) in STORM_BOX [x0, y0, x1, y1] (cells,
## east of the Lesser Antilles), heading west or west-north-west (16-point
## compass headings, 12 W), at STORM_SPEED [min, max] centi-cells a turn,
## radius STORM_R [min, max] cells, for STORM_LIFE [min, max] moves. Each
## move (at the end of a turn) turns it clockwise by one point (recurving
## north) at STORM_CURVE_PCT % (STORM_CURVE_NORTH_PCT % north of row
## STORM_NORTH_Y); the forecast cone is the two headings it may take.
## Over land it shrinks a cell (not below STORM_R_MIN_LAND). At
## STORM_SWERVE_PCT % a move swerves a point beyond the cone (forecasts fail).
const STORM_FORM_PCT: Array[int] = [65, 15]
const STORM_BOX: Array[int] = [174, 62, 186, 92]
const STORM_SPEED: Array[int] = [3000, 4200]
const STORM_R: Array[int] = [4, 6]
const STORM_LIFE: Array[int] = [2, 3]
const STORM_CURVE_PCT := 35
const STORM_CURVE_NORTH_PCT := 60
const STORM_NORTH_Y := 50
const STORM_R_MIN_LAND := 3
const STORM_SWERVE_PCT := 12
## Damage. The core is the inner STORM_CORE_PCT % of the radius; the edge
## hits at STORM_EDGE_PCT % of the core. A ship at sea in the core sinks at
## its row's "storm" % (x (200 - hull %) / 100); a survivor loses
## STORM_HULL + rand STORM_HULL_RAND hull and half that crew. In a friendly
## harbour (within CFleet.PORT_CELLS) all of it is STORM_PORT_PCT %.
## A port in its path loses STORM_TRADE_PCT % of a turn's sea trade (core)
## and a building level at STORM_BUILD_PCT % (core); armies ashore lose
## STORM_MEN_PCT % of their men (core).
const STORM_CORE_PCT := 55
const STORM_EDGE_PCT := 40
const STORM_HULL := 12
const STORM_HULL_RAND := 20
const STORM_PORT_PCT := 20
const STORM_TRADE_PCT := 100
const STORM_BUILD_PCT := 20
const STORM_MEN_PCT := 6
## The Spanish named their hurricanes for the saint of the day they struck.
const STORM_NAMES: Array[String] = ["San Lorenzo", "Santa Ana", "San Bartolomé", "San Mateo", "San Miguel", "Santa Rosa",
	"San Roque", "San Hipólito", "Santa Clara", "San Felipe", "San Ciriaco", "Santa Lucía", "San Calixto", "San Francisco",
	"San Agustín", "Santa Mónica", "San Jerónimo", "Santiago", "San Ramón", "Santa Teresa", "San Lucas", "Santa Úrsula"]

## Notorious captains (pirate fleets). A pirate fleet without a captain gets
## one at the end of a turn: a captain of its faction ashore, else a new one
## at CAPT_RISE_PCT % (at most CAPT_MAX alive a faction; the start fleets
## have theirs). Fame 0..100: + FAME_WIN a sea battle won, + FAME_PRIZE a
## ship taken, + FAME_TREASURE a treasure galleon, + FAME_SACK a sack.
## Tiers at FAME_TIERS (Known, Feared, Legend): haven crews CAPT_HAVEN_PCT %
## cheaper a tier (the faction's most famous); a Legend brings one more
## recruit a turn to the havens; in a sea battle a captain's fleet counts
## FEAR_PCT[tier] % more; a Feared captain's foes strike their colours
## sooner (a beaten ship is lost STRIKE_LOSS more %, taken STRIKE_TAKEN more %).
## His fleet destroyed: killed at CAPT_KILLED_PCT %, captured at
## CAPT_CAPTURED_PCT %, else he escapes ashore (a storm: drowned at
## CAPT_DROWN_PCT %). A captive is hanged (fame >= HANG_FAME, or by a coin
## toss) at Port Royal when the captor holds it or is friendly to whoever
## does, else at the captor's capital; else ransomed for RANSOM_BASE +
## RANSOM_FAME x fame when his faction can pay (else hanged). The nations
## pay a bounty of BOUNTY_PER x fame for a captain of fame >= BOUNTY_FAME
## killed or captured.
const CAPT_RISE_PCT := 35
const CAPT_MAX := 4
const FAME_MAX := 100
const FAME_WIN := 2
const FAME_PRIZE := 3
const FAME_TREASURE := 10
const FAME_SACK := 10
const FAME_TIERS: Array[int] = [20, 45, 75]
const FAME_TIER_NAMES: Array[String] = ["", "Known", "Feared", "Legend"]
const CAPT_HAVEN_PCT := 5
const FEAR_PCT: Array[int] = [0, 5, 10, 20]
const STRIKE_LOSS := 10
const STRIKE_TAKEN := 20
const CAPT_KILLED_PCT := 40
const CAPT_CAPTURED_PCT := 45
const CAPT_DROWN_PCT := 65
const HANG_FAME := 40
const RANSOM_BASE := 150
const RANSOM_FAME := 10
const BOUNTY_FAME := 25
const BOUNTY_PER := 12
const HANG_PORT := "port_royal"
## A few of the real ones, more of the rule of cool.
const CAPTAIN_NAMES: Array[String] = ["\"Calico\" Jack Rackham", "\"Black\" Bart Roberts", "Anne \"the Fury\" Bonny",
	"Mary \"No Quarter\" Read", "François \"the Butcher\" l'Olonnais", "Henry \"the Sacker\" Morgan",
	"Roche \"the Rock\" Brasiliano", "Michel \"le Basque\"", "Pierre \"le Grand\"", "Ned \"Blackbeard\" Teach",
	"Laurens \"Lorencillo\" de Graaf", "\"One-Eyed\" Willem Visser", "Jacquotte \"Back from the Dead\" Delahaye",
	"Diego \"el Mulato\" Grillo", "\"Red\" Rodrigo Sangre", "\"Iron Hook\" Hendrik Vos", "Bartolomeu \"the Portuguese\"",
	"\"Long\" Ben Avery", "\"Black Sam\" Bellamy", "\"Bloody\" Bess Blackwood", "\"Cannonball\" Kate Kildare",
	"\"Dead-Eye\" Dirk Hals", "Jean \"the Unhangable\" Hamlin", "\"Thunder\" Tom Tew", "\"Hellfire\" Hugh Harker",
	"\"Barracuda\" Bram Jansz", "\"Silver-Tongue\" Sebastián Cruz", "\"Gallows\" Gil Gaspard", "Ingrid \"Ironsides\" Lund",
	"\"Saltwater\" Solomon Pike", "\"Grinning\" Gaston Roux", "\"Mad Dog\" Mercer", "\"Powder\" Polly Pruett",
	"\"Gentleman\" Giles Fairfax", "\"Shark-Tooth\" Sancho", "\"Firebrand\" Fenna de Wit"]

## Named treasure galleons: each flota galleon takes a name (none afloat
## twice); its first (the capitana) carries FLOTA_CAPITANA_GOLD. A treasure
## galleon sunk leaves a wreck on the map (the last WRECKS_MAX are kept).
## The Crown adds an escort frigate to each part of the flota for each of
## ESCORT_INFAMY reached by the most infamous pirates afloat.
const GALLEON_NAMES: Array[String] = ["Nuestra Señora de Atocha", "Santa Margarita", "San José",
	"Nuestra Señora de las Maravillas", "San Felipe", "Santísima Trinidad", "Nuestra Señora de la Concepción", "San Pedro",
	"Santa Rosa", "Nuestra Señora del Rosario", "San Diego", "Jesús María", "Santo Cristo de Maracaibo",
	"San Francisco Javier", "Nuestra Señora de Guadalupe", "San Juan Bautista", "Espíritu Santo", "San Cristóbal",
	"Santiago el Mayor", "La Bruja de Plata", "El Dragón de Oro", "El Sol de Potosí", "La Reina de las Indias",
	"Nuestra Señora de la Plata", "San Martín del Mar", "La Golondrina Dorada"]
const WRECKS_MAX := 12
const ESCORT_INFAMY: Array[int] = [30, 60]
