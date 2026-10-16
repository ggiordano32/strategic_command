extends RefCounted
## Ship types of the real-time sea battle (sim/sea_sim.gd; docs/DESIGN.md
## "Sea battles (as built, N3a)"). Data only, integers. The keys are the
## campaign's ship keys (campaign/data/west_ships.gd), so a campaign fleet's
## ships go into a battle by key; the campaign rows hold the strategic
## numbers (cost, upkeep, places, pace a turn), these the battle's.
##
## Rule of cool over reality: speeds about twice a real ship's, gun ranges
## and broadsides compressed so a frigate duel decides in a few minutes.
##
## Fields:
##   len, beam   metres (drawing, collision, target size)
##   vmax        top speed in dm/s on the best point of sail, full sail
##   turn        rate of turn in deg/s x 10 with steerage way
##   irons       half-angle of the no-go zone, degrees off the wind (0: rowed)
##   tack        % of top speed needed to tack (turn through the wind);
##               slower, a ship wears (turns away through downwind)
##   guns        guns a side (a broadside)
##   gun         damage of one hit (shot weight)
##   range       metres (round shot; chain at CHAIN_RANGE_PCT, grape at
##               GRAPE_RANGE_PCT of it)
##   hull, crew  at 100 % (the campaign ship's h / c are % of these)
##   rig         rigging points (chain shot; speed falls with it)
##   reload      seconds to reload a broadside with a full gun crew
##   draft       0 shallow (crosses shoals), 1 deep (runs aground on them)
##   oars        1 rowed: the wind does not drive it
##   board       boarding quality %
##   fire        1: a fire ship (no guns; sailed at the enemy, lit, abandoned
##               by her skeleton crew; she sets alight whatever she touches)

const ROWS: Array[Dictionary] = [
	{"key": "sloop", "name": "Sloop", "len": 20, "beam": 6, "vmax": 95, "turn": 90, "irons": 42, "tack": 25,
		"guns": 4, "gun": 4, "range": 220, "hull": 300, "crew": 60, "rig": 200, "reload": 10, "draft": 0, "oars": 0,
		"board": 105},
	{"key": "brigantine", "name": "Brigantine", "len": 26, "beam": 7, "vmax": 88, "turn": 72, "irons": 50, "tack": 30,
		"guns": 7, "gun": 5, "range": 240, "hull": 450, "crew": 90, "rig": 280, "reload": 11, "draft": 0, "oars": 0,
		"board": 105},
	{"key": "frigate", "name": "Frigate", "len": 40, "beam": 10, "vmax": 82, "turn": 55, "irons": 62, "tack": 35,
		"guns": 15, "gun": 8, "range": 280, "hull": 700, "crew": 200, "rig": 420, "reload": 12, "draft": 1, "oars": 0,
		"board": 100},
	{"key": "galleon", "name": "Galleon", "len": 44, "beam": 13, "vmax": 60, "turn": 34, "irons": 70, "tack": 45,
		"guns": 20, "gun": 9, "range": 270, "hull": 1100, "crew": 300, "rig": 520, "reload": 17, "draft": 1, "oars": 0,
		"board": 110},
	{"key": "ship_of_the_line", "name": "Ship of the line", "len": 54, "beam": 15, "vmax": 68, "turn": 40, "irons": 66,
		"tack": 40, "guns": 35, "gun": 12, "range": 300, "hull": 1500, "crew": 500, "rig": 700, "reload": 14, "draft": 1,
		"oars": 0, "board": 100},
	{"key": "war_canoe", "name": "War canoe", "len": 13, "beam": 3, "vmax": 98, "turn": 120, "irons": 0, "tack": 0,
		"guns": 1, "gun": 3, "range": 120, "hull": 100, "crew": 40, "rig": 0, "reload": 8, "draft": 0, "oars": 1,
		"board": 120},
	# (N3c) An old hull filled with tar, brimstone and brushwood, crewed by a
	# dozen volunteers who light her and take to the boat.
	{"key": "fire_ship", "name": "Fire ship", "len": 22, "beam": 6, "vmax": 95, "turn": 70, "irons": 50, "tack": 30,
		"guns": 0, "gun": 0, "range": 0, "hull": 420, "crew": 14, "rig": 180, "reload": 10, "draft": 0, "oars": 0,
		"board": 60, "fire": 1},
]

const CHAIN_RANGE_PCT := 80
const GRAPE_RANGE_PCT := 40
const MEN_PER_GUN := 4        # gun crew a side for a full-speed reload

const SHOT_ROUND := 0         # the hull (and splinters among the crew)
const SHOT_CHAIN := 1         # the rigging: speed
const SHOT_GRAPE := 2         # the crew, at short range
const SHOT_NAMES := ["Round shot", "Chain shot", "Grape"]

# ---- deck melee (N3b; sim/sea_sim.gd "deck melee") ----
## The sailors' arms by crew kit (a scenario ship's "ck": the faction key;
## anything else "navy"): atk / def (melee, armour and buckler counted in
## def), shot (% of the men hitting with a pistol / musket / bow volley),
## rng (cells of DECK_CELL_M), shots (volleys before it is cold steel only;
## 0: none), rl (ticks to reload between them).
const DECK_CREWS := {
	"navy": {"atk": 26, "def": 22, "shot": 18, "rng": 3, "shots": 1, "rl": 0, "arms": "cutlass and pistol"},
	"england": {"atk": 27, "def": 24, "shot": 22, "rng": 3, "shots": 1, "rl": 0, "arms": "cutlass, pistol and pike"},
	"dutch": {"atk": 27, "def": 24, "shot": 22, "rng": 3, "shots": 1, "rl": 0, "arms": "cutlass, pistol and pike"},
	"france": {"atk": 30, "def": 22, "shot": 20, "rng": 3, "shots": 1, "rl": 0, "arms": "boarding axe and pistol"},
	"new_spain": {"atk": 28, "def": 28, "shot": 14, "rng": 3, "shots": 1, "rl": 0, "arms": "sword and buckler"},
	"tierra_firme": {"atk": 28, "def": 28, "shot": 14, "rng": 3, "shots": 1, "rl": 0, "arms": "sword and buckler"},
	"brethren": {"atk": 34, "def": 22, "shot": 28, "rng": 3, "shots": 2, "rl": 0, "arms": "cutlass, axe and a brace of pistols"},
	"miskito": {"atk": 30, "def": 20, "shot": 14, "rng": 6, "shots": 3, "rl": 25, "arms": "club, spear and bow"},
	"itza": {"atk": 30, "def": 22, "shot": 12, "rng": 6, "shots": 3, "rl": 25, "arms": "obsidian club and bow"},
}
## Soldiers aboard (troops without a kit): musket and bayonet.
const DECK_TROOPS := {"atk": 26, "def": 24, "shot": 24, "rng": 6, "shots": 2, "rl": 120}
## Troops by their unit line (sim/unit_types.gd "line"): their volley at deck
## range [shot %, cells, volleys, reload ticks]; atk / def from the row
## (attack; defence + armour + shield / 2).
const DECK_LINE_SHOT := {"musket": [26, 7, 2, 120], "buccaneer": [34, 8, 2, 140], "pistol": [30, 3, 2, 0],
	"archer": [12, 6, 3, 25], "javelin": [16, 3, 1, 0], "sling": [10, 5, 2, 20]}
const DECK_CAPTAIN_ATK := 250  # % of his crew's atk (the captain and his mates: CAPTAIN_MEN men)
const DECK_CAPTAIN_DEF := 200
const DECK_CAPTAIN_MEN := 3


static func deck_crew(ck: String) -> Dictionary:
	return DECK_CREWS.get(ck, DECK_CREWS["navy"])


static func is_fire(i: int) -> bool:
	return stat(i, "fire") != 0


static func index_of(key: String) -> int:
	for i in ROWS.size():
		if str(ROWS[i]["key"]) == key:
			return i
	return -1


static func row(i: int) -> Dictionary:
	return ROWS[clampi(i, 0, ROWS.size() - 1)]


static func stat(i: int, k: String) -> int:
	return int(row(i).get(k, 0))


static func name_of(i: int) -> String:
	return str(row(i)["name"])
