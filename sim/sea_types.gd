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
]

const CHAIN_RANGE_PCT := 80
const GRAPE_RANGE_PCT := 40
const MEN_PER_GUN := 4        # gun crew a side for a full-speed reload

const SHOT_ROUND := 0         # the hull (and splinters among the crew)
const SHOT_CHAIN := 1         # the rigging: speed
const SHOT_GRAPE := 2         # the crew, at short range
const SHOT_NAMES := ["Round shot", "Chain shot", "Grape"]


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
