extends RefCounted
## Campaign AI profiles (docs/AI.md sections 2, 4, 5 and 7): every ratio,
## odds cutoff, turn count, budget share and priority weight the campaign
## AI (campaign/cai.gd) decides with, as integer knobs per skill level, plus
## offsets per personality. Same discipline as the rules: integers only, no
## Dictionary iteration in rules code (the tables are arrays, in order).
##
## A faction's knobs are KNOBS[skill] + STYLE[style] (of(st, f)), where
##   skill = factions[f]["ai_skill"] if present, else
##           settings["ai_campaign_skill"] if present, else AVERAGE;
##   style = factions[f]["ai_style"] if present, else BALANCED.
## The keys are only written when not the default (new_campaign), so a
## campaign at Average / Balanced is byte for byte the state it always was
## (same CState.state_hash; no CState.VERSION bump: older states read the
## defaults). settings["ai_battle_skill"] / factions[f]["ai_battle_skill"]
## give the battle AI's skill for that faction's armies (battle_skill()).
##
## Step 1 (October 2026): the AVERAGE column is the AI as it was (every
## value exactly the old constant), every personality offset is 0.
## Step 2 (October 2026): the EASY column: this turn only, cheapest
## buildings, piecemeal single-type recruiting, nearest targets at poor
## odds, no gathering, screens, relief, sieges or stances, random-ish wars
## and no peace, plus the deliberate mistakes (M_*, rolled only where the
## level's MK_BASE + M_* is above 0: Average never draws from the RNG for
## them, so its campaigns are unchanged).
## Step 4 (October 2026): the SKILLED column (docs/AI.md 12): Average's
## thresholds with a few changes (no sheltering inside the walls, battles
## at 50 % odds or better) plus the SK_* behaviours, 0 at Easy and Average
## (those levels never run them and never draw the RNG for them):
## support-aware hunting, rallying spare armies on the main army, staging
## out of the enemy's reach, falling back from danger, storming before a
## relief, intercepting reliefs, counter-composition, war timed to the
## enemy's absence from the border and one front at a time. No mistakes.
##
## Also here: diagnostic counters of what the AI did (docs/AI.md 6), kept
## in a static Dictionary outside the state (never hashed, never read by
## the rules or the AI): count() / counters() / reset_counters().

const EASY := 0
const AVERAGE := 1
const SKILLED := 2
const CAUTIOUS := 0
const BALANCED := 1
const AGGRESSIVE := 2
const SKILL_NAMES: Array[String] = ["Easy", "Average", "Skilled"]
const STYLE_NAMES: Array[String] = ["Cautious", "Balanced", "Aggressive"]

# ------------------------------------------------------------ knob ids ---
# Economy and build order (4.1).
const RESERVE_TURNS := 0        # keep this many turns of upkeep in the bank
const BUILD_BUDGET_PCT := 1     # % of the money above the reserve spent on buildings a turn
const BUILD_CAPITAL_W := 2      # build order: the capital counts this much more region value
const WALLS_THREAT_DIV := 3     # walls where the threat exceeds 1 / this of the defence
const CUT_DEBT_PCT := 4         # in debt: disband until upkeep is at most this % of income
# Army composition and recruitment (4.2).
const UPKEEP_SHARE := 5         # % of income spent on army upkeep at most ...
const WAR_SHARE := 6            # ... plus this at war ...
const CHEST_SHARE := 7          # ... plus this per turn of income in the bank ...
const CHEST_SHARE_MAX := 8      # ... up to this
const RECRUIT_BUILDING_W := 9   # recruiting centre score per military building level ...
const RECRUIT_THREAT_DIV := 10  # ... plus the threat divided by this ...
const RECRUIT_FRONTIER_W := 11  # ... plus this on the frontier
const RECRUIT_MAX := 12         # at most this many recruits a turn
const RECRUIT_RESERVE_DIV := 13 # recruit while the treasury stays above the reserve / this
# Target selection and expansion (4.3).
const VAL_WEALTH := 14          # region value per wealth point ...
const VAL_LEVEL := 15           # ... per settlement level ...
const VAL_KEY := 16             # ... for a key city
const HUMAN_VALUE_PCT := 17     # regions of the players count this % of their value
# Concentration of force and support (4.4).
const ATTACK_RATIO := 18        # % of the target's defence needed to attack (formats 1-5)
const ATTACK_RATIO6 := 19       # ... (format 6, the continuous overworld)
const COMMIT_PCT := 20          # commit armies until this % of the ratio is met
const SIEGE_RATIO_PCT := 21     # lay siege with this % of the ratio (and support near)
const GATHER_PCT := 22          # (6) gather a march short: within this % of a turn's march of the target
const TOWARD_PCT := 23          # (6) marches further than this % of a turn go by a waypoint
const FORCED_HELP := 24         # (6) forced march when it gets a screen there this many turns sooner
# Defence, screening and zones of control (4.5).
const SHELTER_PCT := 25         # shelter inside when our armies are below this % of the threat
const SCREEN_PCT := 26          # an army screens a threatened city if this % of the threat
const SCREEN_NEAR := 27         # (6) a city with a field army within this many cells is screened
# Sieges and relief (4.6).
const SIEGE_PATIENCE := 28      # turns past the supplies a siege is maintained before assault or lift
const SIEGE_ASSAULT_WIN := 29   # % chance to storm a siege that ran out of patience (else lift)
const RELIEF_WIN := 30          # % chance needed to relieve a besieged city (and to stay in the field)
const LIFT_WIN := 31            # lift before a stronger relief army whose odds reach this %
const IDLE_TURNS := 32          # (5, 6) an army idle this long takes a fair chance ...
const IDLE_WIN := 33            # ... of at least this % (lays siege)
# Stances: raids and hunting (4.7).
const RAID_WEALTH := 34         # raid regions of at least this wealth
const HUNT_COST := 35           # (6) points a cell, the AI's estimate of a march across country ...
const HUNT_SLACK := 36          # ... plus this
const HUNT_WIN := 37            # (6) odds to attack an enemy army in the field outside our lands
# Diplomacy (4.8).
const FIRST_WAR_TURN := 38      # no AI declares war before this turn
const FIRST_WAR_ON_PLAYERS := 39
const PLAYER_WAR_GAP := 40      # turns between AI war declarations on the players
const MAX_WARS := 41            # no new war while at war with this many factions
const WAR_CALM_TURNS := 42      # no war on a faction within this many turns of the last change
const WAR_RATIO := 43           # % of a neighbour's strength needed to consider war on it ...
const WAR_RATIO_BUSY := 44      # ... if the neighbour is already at war
const WAR_CHANCE := 45          # % per turn per eligible neighbour ...
const WAR_CHANCE_PLAYERS := 46  # ... on a player
const TRADE_WAR_DIV := 47       # ... divided by this for a trade partner
const BIG_REALM := 48           # realms above this many regions start fewer wars
const PEACE_ASK_TURNS := 49     # seek peace only after this many turns of war ...
const PEACE_ASK_PCT := 50       # ... when below this % of the enemy's strength ...
const PEACE_ASK_LONG := 51      # ... or after this many turns
const PEACE_MIN_TURNS := 52     # accept peace only after this many turns of war ...
const PEACE_ACCEPT_PCT := 53    # ... when below this % of the asker's strength ...
const PEACE_ACCEPT_LONG := 54   # ... or after this many turns ...
const PEACE_ACCEPT_REGIONS := 55  # ... or down to this many regions
const TRADE_ASK_TURNS := 56     # propose trade after this many turns of peace ...
const TRADE_ASK_CHANCE := 57    # ... with this % chance a turn
const TRADE_ACCEPT_TURNS := 58  # accept trade after this many turns of peace ...
const TRADE_ACCEPT_PCT := 59    # ... when below this % of the asker's strength
# Step 2 (Easy): behaviours a level switches off, and the deliberate mistakes.
const BUILD_CHEAPEST := 60      # build the cheapest wanted building first (1) or by priority (0)
const RECRUIT_LEAN_PCT := 61    # % chance a recruit is of the line the faction already has most of
const TARGET_NEAREST := 62      # attack targets: the ones reached this turn first, by value, defence ignored (1)
const GATHER := 63              # gather armies a march short before attacking (1) or let them arrive as they come (0)
const SCREENS := 64             # send armies to screen threatened cities (1) or not (0)
const ASSAULT_ALWAYS := 65      # storm on arrival instead of laying siege (1)
const RELIEVE := 66             # relieve our besieged cities (1) or not (0)
const STANCES := 67             # use fortify, forced march, raiding and sheltering (1) or the default stance only (0)
const OVER_RECRUIT_PCT := 68    # MK_OVER_RECRUIT: army upkeep up to this % of income that turn
const MK_BASE := 69             # MK_BASE + M_*: % chance of that mistake per roll (0: never rolled)
# (6) The mustering rule (an army taking recruits cannot march this turn):
# with every army at a recruiting city planned to march, one of at most this
# many units on a march within our lands stays to take the recruits instead
# (the others march; the recruits raise a new army).
const RECRUIT_HOLD_UNITS := MK_BASE + 5
# Step 4 (Skilled; docs/AI.md 12). 0 for Easy and Average: those levels never
# run these behaviours and never draw the RNG for them.
const SK_SUPPORT := RECRUIT_HOLD_UNITS + 1   # (6) odds count the armies within support range of the battle's cell (both sides)
const SK_HUNT_WIN := SK_SUPPORT + 1          # (6) hunt enemy field armies at these odds (with support; 0: HUNT_WIN)
const SK_RALLY := SK_SUPPORT + 2             # (6) spare armies join / stand by our strongest army within this many turns (0 off)
const SK_SAFE_WIN := SK_SUPPORT + 3          # (6) an army the enemy could attack next turn at these odds falls back to support (0 off)
const SK_SAFE_HOLD := SK_SUPPORT + 4         # (6) ... even an army holding a threatened city (1) or not (0)
const SK_SAFE_GAIN := SK_SUPPORT + 5         # (6) ... only where the enemy's odds are at least this many points lower
const SK_REACH_DEF_PCT := SK_SUPPORT + 6     # (6) a target's defence counts this % of its side's field armies that reach it next turn (0: off; measured even)
const SK_WAR_BORDER_PCT := SK_SUPPORT + 7    # war timing: their border is "weak" when their armies near it are at most this % of ours near theirs (0 off)
const SK_ONE_FRONT := SK_SUPPORT + 8         # at war on two fronts: propose peace on all but the main one (1)
const SK_WAR_WEAK_PCT := SK_SUPPORT + 9      # ... war chance x this % when their border is weak ...
const SK_WAR_GUARDED_PCT := SK_SUPPORT + 10  # ... and x this % when it is not
const SK_STAGE_SAFE := SK_SUPPORT + 11      # (6) gather armies only where the enemy's odds against them next turn stay below this % (0 off)
const SK_INTERCEPT_WIN := SK_SUPPORT + 12    # (6) hunt an army that can relieve a siege of ours at these odds (0 off)
const SK_STORM_RELIEF_WIN := SK_SUPPORT + 13 # (6) storm a siege at these odds when a relief can arrive next turn (0 off)
const SK_COUNTER_MIX := SK_SUPPORT + 14      # recruit: + this weight to spears / pikes against cavalry-heavy enemies (missiles: half, against light foot)
const SK_COUNTER_SHARE := SK_SUPPORT + 15    # ... when that arm is at least this % of the enemies' units
# The military build-up (docs/AI.md 23, October 2026). 0 at Easy: it builds
# as before (and never recruits wagons).
const BU_RANGE := SK_SUPPORT + 16            # Range level wanted at the military centre when the mix has a Range line (0 off)
const BU_WORKSHOP := SK_SUPPORT + 17         # Workshop level wanted there when the mix has engines or WAGON_MIN missile units (0 off)
const BU_BUDGET_PCT := SK_SUPPORT + 18       # % of the money above the reserve the build-up may take a turn
const BU_SAVE := SK_SUPPORT + 19             # while the build-up waits for money, nothing else is built (1)
const WAGON_MIN := SK_SUPPORT + 20           # an army with this many missile / artillery units and no wagon gets one (0 never)
# Teams (version 7): accept a "team" proposal after this many turns at peace
# with the proposer's team, when that team is at most this % of our strength
# (or we are losing a war); propose a team to a player (% chance a turn,
# when we would accept the reverse; 0: never, the default).
const TEAM_ACCEPT_TURNS := SK_SUPPORT + 21
const TEAM_ACCEPT_PCT := SK_SUPPORT + 22
const TEAM_PROPOSE := SK_SUPPORT + 23
const N_KNOBS := SK_SUPPORT + 24

# Deliberate mistakes (docs/AI.md 4, "Deliberate mistakes (campaign)"),
# rolled with CState.rand at the decision point (cai.gd _mistake); each is a
# move a player could make under the same rules.
const M_EMPTY_CITY := 0         # an army that should hold a threatened city of ours marches off
const M_BAD_ODDS := 1           # one attack a turn below the odds the level wants
const M_OVER_RECRUIT := 2       # recruits past its income for a turn (into deficit, then the debt rules)
const M_UNWISE_WAR := 3         # declares war on a stronger neighbour
const M_NO_GARRISON := 4        # the army in a city it took last turn marches off though it is threatened
const N_MISTAKES := 5

## [knob, EASY, AVERAGE, SKILLED]. AVERAGE = the old value; EASY: docs/AI.md
## section 10, "As built: Easy"; SKILLED: section 12.
const KNOBS: Array = [
	# Economy and build order.
	[RESERVE_TURNS, 0, 1, 1],
	[BUILD_BUDGET_PCT, 100, 60, 60],
	[BUILD_CAPITAL_W, 1000, 1000, 1000],
	[WALLS_THREAT_DIV, 1, 2, 2],
	[CUT_DEBT_PCT, 90, 90, 90],
	# Army composition and recruitment.
	[UPKEEP_SHARE, 70, 70, 70],
	[WAR_SHARE, 10, 10, 10],
	[CHEST_SHARE, 10, 10, 10],
	[CHEST_SHARE_MAX, 40, 40, 40],
	[RECRUIT_BUILDING_W, 10, 10, 10],
	[RECRUIT_THREAT_DIV, 500, 500, 500],
	[RECRUIT_FRONTIER_W, 5, 5, 5],
	[RECRUIT_MAX, 1, 12, 12],
	[RECRUIT_RESERVE_DIV, 2, 2, 2],
	# Target selection and expansion.
	[VAL_WEALTH, 100, 100, 100],
	[VAL_LEVEL, 150, 150, 150],
	[VAL_KEY, 300, 300, 300],
	[HUMAN_VALUE_PCT, 100, 90, 90],
	# Concentration of force and support.
	[ATTACK_RATIO, 120, 150, 150],
	[ATTACK_RATIO6, 110, 130, 130],
	[COMMIT_PCT, 100, 130, 130],
	[SIEGE_RATIO_PCT, 50, 50, 50],
	[GATHER_PCT, 75, 75, 75],
	[TOWARD_PCT, 150, 150, 150],
	[FORCED_HELP, 1, 1, 1],
	# Defence, screening and zones of control.
	[SHELTER_PCT, 0, 70, 70],
	[SCREEN_PCT, 80, 80, 80],
	[SCREEN_NEAR, 2, 2, 2],
	# Sieges and relief.
	[SIEGE_PATIENCE, 0, 3, 3],
	[SIEGE_ASSAULT_WIN, 0, 35, 50],
	[RELIEF_WIN, 60, 60, 60],
	[LIFT_WIN, 101, 50, 50],
	[IDLE_TURNS, 3, 3, 3],
	[IDLE_WIN, 20, 35, 50],
	# Stances: raids and hunting.
	[RAID_WEALTH, 99, 4, 4],
	[HUNT_COST, 13, 13, 13],
	[HUNT_SLACK, 10, 10, 10],
	[HUNT_WIN, 50, 70, 70],
	# Diplomacy.
	[FIRST_WAR_TURN, 6, 6, 6],
	[FIRST_WAR_ON_PLAYERS, 10, 10, 10],
	[PLAYER_WAR_GAP, 8, 8, 8],
	[MAX_WARS, 2, 2, 2],
	[WAR_CALM_TURNS, 6, 6, 6],
	[WAR_RATIO, 100, 120, 120],
	[WAR_RATIO_BUSY, 80, 90, 90],
	[WAR_CHANCE, 12, 12, 12],
	[WAR_CHANCE_PLAYERS, 8, 8, 8],
	[TRADE_WAR_DIV, 2, 2, 2],
	[BIG_REALM, 8, 8, 8],
	[PEACE_ASK_TURNS, 999, 6, 6],
	[PEACE_ASK_PCT, 70, 70, 70],
	[PEACE_ASK_LONG, 999, 20, 20],
	[PEACE_MIN_TURNS, 3, 3, 3],
	[PEACE_ACCEPT_PCT, 100, 100, 100],
	[PEACE_ACCEPT_LONG, 18, 18, 18],
	[PEACE_ACCEPT_REGIONS, 2, 2, 2],
	[TRADE_ASK_TURNS, 3, 3, 3],
	[TRADE_ASK_CHANCE, 15, 15, 15],
	[TRADE_ACCEPT_TURNS, 2, 2, 2],
	[TRADE_ACCEPT_PCT, 250, 250, 250],
	[TEAM_ACCEPT_TURNS, 4, 4, 4],
	[TEAM_ACCEPT_PCT, 250, 250, 250],
	[TEAM_PROPOSE, 0, 0, 0],
	# Behaviours a level switches off (Average: as before).
	[BUILD_CHEAPEST, 1, 0, 0],
	[RECRUIT_LEAN_PCT, 70, 0, 0],
	[TARGET_NEAREST, 1, 0, 0],
	[GATHER, 0, 1, 1],
	[SCREENS, 0, 1, 1],
	[ASSAULT_ALWAYS, 1, 0, 0],
	[RELIEVE, 0, 1, 1],
	[STANCES, 0, 1, 1],
	[OVER_RECRUIT_PCT, 130, 100, 100],
	# Deliberate mistakes: % per roll (Average and Skilled: never rolled).
	[MK_BASE + M_EMPTY_CITY, 50, 0, 0],
	[MK_BASE + M_BAD_ODDS, 30, 0, 0],
	[MK_BASE + M_OVER_RECRUIT, 25, 0, 0],
	[MK_BASE + M_UNWISE_WAR, 8, 0, 0],
	[MK_BASE + M_NO_GARRISON, 50, 0, 0],
	# The mustering rule (format 6).
	[RECRUIT_HOLD_UNITS, 0, 2, 2],
	# Skilled (step 4): behaviours only the Skilled level runs.
	[SK_SUPPORT, 0, 0, 1],
	[SK_HUNT_WIN, 0, 0, 75],
	[SK_RALLY, 0, 0, 2],
	[SK_SAFE_WIN, 0, 0, 70],
	[SK_SAFE_HOLD, 0, 0, 0],
	[SK_SAFE_GAIN, 0, 0, 15],
	[SK_REACH_DEF_PCT, 0, 0, 0],
	[SK_WAR_BORDER_PCT, 0, 0, 100],
	[SK_ONE_FRONT, 0, 0, 1],
	[SK_WAR_WEAK_PCT, 0, 0, 200],
	[SK_WAR_GUARDED_PCT, 0, 0, 50],
	[SK_STAGE_SAFE, 0, 0, 70],
	[SK_INTERCEPT_WIN, 0, 0, 60],
	[SK_STORM_RELIEF_WIN, 0, 0, 50],
	[SK_COUNTER_MIX, 0, 0, 20],
	[SK_COUNTER_SHARE, 0, 0, 25],
	# The military build-up and the wagon (Easy: off).
	[BU_RANGE, 0, 2, 2],
	[BU_WORKSHOP, 0, 1, 2],
	[BU_BUDGET_PCT, 0, 100, 100],
	[BU_SAVE, 0, 1, 1],
	[WAGON_MIN, 0, 3, 2],
]

## Personality offsets [knob, CAUTIOUS, BALANCED, AGGRESSIVE] (docs/AI.md 5:
## attack odds 160 / 130 / 110 %, war appetite, raiding). Step 1: all 0.
const STYLE: Array = [
	[ATTACK_RATIO, 0, 0, 0],
	[ATTACK_RATIO6, 0, 0, 0],
	[WAR_CHANCE, 0, 0, 0],
	[WAR_CHANCE_PLAYERS, 0, 0, 0],
	[RAID_WEALTH, 0, 0, 0],
]


static var _tab: Array = []


## Campaign AI skill of faction f (see the header).
static func skill(st: Dictionary, f: int) -> int:
	var s := AVERAGE
	if f >= 0 and f < (st["factions"] as Array).size():
		var fs: Dictionary = st["factions"][f]
		if fs.has("ai_skill"):
			return clampi(int(fs["ai_skill"]), EASY, SKILLED)
	var ss: Dictionary = st.get("settings", {})
	if ss.has("ai_campaign_skill"):
		s = int(ss["ai_campaign_skill"])
	return clampi(s, EASY, SKILLED)


## Personality of faction f (BALANCED when not in the state).
static func style(st: Dictionary, f: int) -> int:
	if f >= 0 and f < (st["factions"] as Array).size():
		return clampi(int((st["factions"][f] as Dictionary).get("ai_style", BALANCED)), CAUTIOUS, AGGRESSIVE)
	return BALANCED


## Battle AI skill for faction f's armies (sim/ai_profile.gd levels; the
## same numbers): factions[f]["ai_battle_skill"], else
## settings["ai_battle_skill"], else AVERAGE. Independents (-1): the setting.
static func battle_skill(st: Dictionary, f: int) -> int:
	if f >= 0 and f < (st["factions"] as Array).size():
		var fs: Dictionary = st["factions"][f]
		if fs.has("ai_battle_skill"):
			return clampi(int(fs["ai_battle_skill"]), EASY, SKILLED)
	var ss: Dictionary = st.get("settings", {})
	return clampi(int(ss.get("ai_battle_skill", AVERAGE)), EASY, SKILLED)


## Faction f's knobs (f < 0: the default profile).
static func of(st: Dictionary, f: int) -> PackedInt32Array:
	if _tab.is_empty():
		_build()
	if f < 0:
		return _tab[AVERAGE * 3 + BALANCED]
	return _tab[skill(st, f) * 3 + style(st, f)]


## Test tool (tests/campaign_sim.gd --knob=): set knob k of skill `level`
## to v for every personality (plus its offset) for the rest of the run.
## Never called by the rules or the AI.
static func set_knob(level: int, k: int, v: int) -> void:
	if _tab.is_empty():
		_build()
	for y in 3:
		var off := 0
		for r in STYLE:
			if int(r[0]) == k:
				off = int(r[1 + y])
		var p: PackedInt32Array = _tab[level * 3 + y]
		p[k] = v + off
		_tab[level * 3 + y] = p


static func _build() -> void:
	var tab: Array = []
	for s in 3:
		var base := PackedInt32Array()
		base.resize(N_KNOBS)
		base.fill(-0x7FFFFFFF)
		for r in KNOBS:
			base[int(r[0])] = int(r[1 + s])
		for k in N_KNOBS:
			if base[k] == -0x7FFFFFFF:
				push_error("cai_profile: knob %d has no value" % k)
		for y in 3:
			var p := base.duplicate()
			for r in STYLE:
				p[int(r[0])] += int(r[1 + y])
			tab.append(p)
	_tab = tab


# ---------------------------------------------- diagnostic counters ------
# docs/AI.md 6 (campaign): what the AI did, per faction. Outside the state:
# never hashed, never read by any decision; tests/campaign_sim.gd prints them.
const C_BAD_ODDS := "attacks_bad_odds"      # attacks / assaults launched with the defence above our strength
const C_EMPTY_CITY := "cities_left_empty"   # threatened cities of ours left with no army in or near them
const C_TWO_FRONTS := "two_front_wars"      # turns at war with two or more factions
const C_TRICKLED := "armies_trickled"       # attacks by a single army while another army was a turn away
# Deliberate mistakes made (M_*), in M_* order.
const C_MK_EMPTY_CITY := "mk_empty_city"
const C_MK_BAD_ODDS := "mk_bad_odds"
const C_MK_OVER_RECRUIT := "mk_over_recruit"
const C_MK_UNWISE_WAR := "mk_unwise_war"
const C_MK_NO_GARRISON := "mk_no_garrison"
const MISTAKE_KEYS: Array[String] = [C_MK_EMPTY_CITY, C_MK_BAD_ODDS, C_MK_OVER_RECRUIT, C_MK_UNWISE_WAR, C_MK_NO_GARRISON]
# Skilled behaviours (step 4), counted when the Skilled code decides them.
const C_SK_TWO_TO_ONE := "sk_two_to_one"    # attacks on an enemy field army with at least twice its strength (support counted)
const C_SK_HUNT_DECLINED := "sk_hunt_declined"  # hunts Average's odds would launch, called off for the target's support
const C_SK_INTERCEPT := "sk_relief_intercepts"  # field attacks on an army that can relieve a siege of ours next turn
const C_SK_TIMED := "sk_timed_arrivals"      # attacks where armies that started a turn apart arrive together
const C_SK_MERGE := "sk_merges"              # spare armies sent to merge into our main army before campaigning
const C_SK_RALLY := "sk_rallies"             # spare armies sent to stand within support of our main army
const C_SK_FALLBACK := "sk_fallbacks"        # armies in danger falling back to support
const C_SK_STORM_RELIEF := "sk_storms_before_relief"  # sieges stormed before a relief that could arrive next turn
const COUNTER_KEYS: Array[String] = [C_BAD_ODDS, C_EMPTY_CITY, C_TWO_FRONTS, C_TRICKLED,
	C_MK_EMPTY_CITY, C_MK_BAD_ODDS, C_MK_OVER_RECRUIT, C_MK_UNWISE_WAR, C_MK_NO_GARRISON,
	C_SK_TWO_TO_ONE, C_SK_HUNT_DECLINED, C_SK_INTERCEPT, C_SK_TIMED, C_SK_MERGE, C_SK_RALLY, C_SK_FALLBACK,
	C_SK_STORM_RELIEF]

static var _counters := {}


static func count(key: String, f: int, n: int = 1) -> void:
	var k := "%s:%d" % [key, f]
	_counters[k] = int(_counters.get(k, 0)) + n


## Totals per counter key (all factions), in COUNTER_KEYS order.
static func totals() -> Array[int]:
	var out: Array[int] = []
	for key in COUNTER_KEYS:
		var t := 0
		for f in 16:
			t += int(_counters.get("%s:%d" % [key, f], 0))
		out.append(t)
	return out


## Counter `key` of faction f alone.
static func counter(key: String, f: int) -> int:
	return int(_counters.get("%s:%d" % [key, f], 0))


static func reset_counters() -> void:
	_counters = {}
