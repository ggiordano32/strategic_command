extends RefCounted
## Battle AI profiles (docs/AI.md sections 2, 5 and 7): every threshold,
## think interval, stagger, distance, ratio and target score the battle AI
## (sim/battle_ai.gd) and the settlement AI (sim/siege_ai.gd) decide with,
## as integer knobs per skill level, plus offsets per personality.
##
## A side's knobs are KNOBS[skill] + STYLE[style] (of(sim, side)); the
## scenario carries "ai_skill" and "ai_style" per sim side (BattleSim keeps
## them in ai_skill / ai_style, in state_hash() when not the default).
## Behaviour code reads knobs and never branches on the level: a later level
## changes numbers here, or enables a behaviour by a knob.
##
## Step 1 (October 2026): the AVERAGE column is the AI as it was (every
## value exactly the old constant), and EASY and SKILLED are copies of it
## (placeholders, so nothing changes yet); every personality offset is 0.
## Integers only (sim units: M = 1024 per metre, ticks of 0.1 s; *_PCT in
## percent of the thing named).
##
## Also here: the indices of the per-competency diagnostic counters
## (BattleSim.stat_aic, per side; never read by the sim or the AI).

const M := 1024

const EASY := 0
const AVERAGE := 1
const SKILLED := 2
const SKILL_NAMES: Array[String] = ["Easy", "Average", "Skilled"]
const CAUTIOUS := 0
const BALANCED := 1
const AGGRESSIVE := 2
const STYLE_NAMES: Array[String] = ["Cautious", "Balanced", "Aggressive"]

# ------------------------------------------------------------ knob ids ---
# Reaction (how often the army and each unit think; how big a change of
# plan is worth a new order).
const ARMY_THINK := 0          # army decisions every this many ticks
const UNIT_THINK := 1          # each unit thinks every this many ticks (staggered by its index)
const REPLAN_DIST := 2         # a move within a third of this of the current one is not re-ordered ...
const REPLAN_FACE := 3         # ... nor one facing within this (1024 = full turn)
# Deployment.
const LINE_GAP := 4            # gap between units in the line
const LINE2_BACK := 5          # second line this far behind the first
const MISSILE_AHEAD := 6       # missile screen this far in front of the line
const MAX_LINE := 7            # foot units in the first line
const WING_GAP := 8            # cavalry wings this far beyond the line (and the bolt throwers)
# Approach and skirmish.
const SKIRMISH_HALT := 9       # the line halts this far from the enemy line to shoot
const ENGAGE_DIST := 10        # lines this close: engage
const ENGAGE_RUSH := 11        # ... or this much further when not halting to shoot
const HALT_SHORT := 12         # the advance stops ENGAGE_DIST less this short of the enemy
const SKIRMISH_TICKS := 13     # skirmish at most this long from deployment (march included)
const SKIRMISH_MISSILE_PCT := 14  # skirmish while our missile power is at least this % of theirs ...
const SKIRMISH_AMMO_PCT := 15  # ... and more than this % of our arrows are left
const SHELLED_TICKS := 16      # "being shelled": hit by artillery within this many ticks
# Engagement and target choice.
const CHARGE_RANGE := 17       # foot run at a target this close
const SPEAR_CAV_R := 18        # spears turn on enemy cavalry this close
# Flanking and the rear.
const PIKE_ALT_PCT := 19       # facing a formed pike front, take another target up to this % as far
const FLANK_OUT := 20          # a flanking unit goes this far beyond the end of the enemy's line
const FLANK_ARRIVE := 21       # arrived at a flank (or detour) point when this close
const FLANK_TIMEOUT := 22      # attack anyway after this many ticks on the way to a flank
# Cavalry.
const CAV_MELEE_TICKS := 23    # cavalry pulls out after this long in melee
const CAV_PULL_DIST := 24      # ... this far
const CAV_PULL_BIAS := 25      # ... biased this much toward our own side of the field
const CAV_PULL_TICKS := 26     # ... and holds again after this long
const CAV_STAGE_TICKS := 27    # charges from a staging point after at most this long
const CAV_RESTAGE_DIST := 28   # a charge into a front that turned its points is broken off beyond this
const CAV_STAGE_OUT := 29      # staging point: this far beyond the target's flank ...
const CAV_STAGE_BACK := 30     # ... and this far back past its rear ranks
const CAV_ARROW_REACT := 31    # waiting cavalry reacts to arrows that hit it within this many ticks
const CAV_SHELL_REACT := 32    # ... and to artillery
const UNPROTECTED := 33        # a unit with no ready melee friend this close is unprotected
const CAV_THREAT := 34         # enemy cavalry this close to our foot threatens our flank
const CAV_SC_ROUTER := 35      # cavalry target scores: routers (once the lines meet)
const CAV_SC_MISSILE := 36     # ... unprotected missile troops
const CAV_SC_MISSILE_FIRE := 37  # ... ditto, shooting at this unit from afar
const CAV_MISSILE_CLOSE := 38  # ... "from afar": further than this (metres)
const CAV_SC_BATTERY := 39     # ... an unguarded battery
const CAV_SC_BATTERY_GUARDED := 40  # ... a guarded battery (once the lines meet)
const CAV_SC_CAV_THREAT := 41  # ... enemy cavalry threatening our flank
const CAV_SC_ENGAGED := 42     # ... an engaged enemy (once the lines meet)
const CAV_SC_ENGAGED_BRACED := 43  # ... ditto, a braced front toward us
const CAV_SC_MISSILE_LATE := 44  # ... protected missile troops (once the lines meet)
const CAV_SC_DIST := 45        # ... less this per metre away
const CAV_SC_UPHILL := 46      # ... less this per 100% of climb (Q12 grade)
const CAV_SC_WOODS_PATH := 47  # ... less this per tree density step along the way
const CAV_SC_WOODS_AT := 48    # ... less this per density step where the target stands
# Missile use.
const MIS_BEHIND := 49         # once the lines meet, archers less than this behind the line ...
const MIS_FALLBACK := 50       # ... fall back this far behind where they are
const SHELTER_CAV_R := 51      # archers / javelins with enemy cavalry this close shelter in woods
# Artillery.
const ART_BACK := 52           # stone throwers stand this far behind the line
const ART_MOVE := 53           # batteries only move for a gain this big ...
const ART_DEPLOY_MOVE := 54    # ... (at deployment: this big)
const GUARD_OUT := 55          # guard post: beside the battery, outward, this far ...
const GUARD_FWD := 56          # ... and this far forward
const GUARD_RANGE := 57        # the guard attacks enemies this close to the battery
const GUARD_MIN_MELEE := 58    # a guard is spared only with this many melee units
const REFILL_SAFE := 59        # a battery refills with no enemy melee unit this close ...
const REFILL_WATCH := 60       # ... and none this close coming for it
const REFILL_LOW_PCT := 61     # refill at or below this % of a full load ...
const REFILL_FULL_PCT := 62    # ... (or below this with no target), stop at this % with a target
const ART_SC_BATTERY := 63     # artillery target score: + this for an enemy battery
const ART_SC_PIKE_PCT := 64    # ... bolts at pikes: this %
const ART_SC_CAV_PCT := 65     # ... cavalry: this %
const ART_SC_STILL_NUM := 66   # ... a standing target: times NUM / DEN
const ART_SC_STILL_DEN := 67
const ART_SC_MOVING_PCT := 68  # ... stones at a moving target: this %
const SIDESTEP := 69           # idle units under artillery fire step this far out of its arc
# Reserves and rotation.
const RETIRE_ALIVE_PCT := 70   # a unit below this % of its men ...
const RETIRE_TICKS := 71       # ... falls back (RETIRE_MORALE) and rejoins after this long
const RETIRE_BACK := 72        # ... this far behind where it is
# Morale.
const RETIRE_MORALE := 73      # ... with morale below this (0..1000)
# Terrain and woods.
const HOLD_DH := 74            # hold when the line stands this far above the enemy ...
const HOLD_TICKS := 75         # ... for at most this long
const HOLD_REACT := 76         # holding foot attack enemies this close
const HOLD_OUTSHOT_PCT := 77   # stop holding when their missile power exceeds ours by this % ...
const HOLD_OUTSHOT_SLACK := 78 # ... plus this many shooters
const HOLD_FIGHT_DIV := 79     # ... or once 1 / this of our foot is fighting
const DETOUR_GRADE := 80       # a steeper final approach (Q12 grade) is avoided ...
const DETOUR_MIN := 81         # ... (its last stretch this long) when the target is at least this far
const DETOUR_LONG := 82        # ... by a detour at most this many tenths as long
const DETOUR_OUT := 83         # ... to a point this far beyond the target's flank
const DETOUR_GENTLE_NUM := 84  # ... climbing less than NUM / DEN of the straight approach
const DETOUR_GENTLE_DEN := 85
const DETOUR_TIMEOUT := 86     # ... attack anyway after this long on the way
const CREST_GAIN := 87         # skirmishing, halt on ground this much higher than the halt line ...
const CREST_REACH := 88        # ... within this of the halt line
const DEPLOY_SHIFT := 89       # deployment may shift this far ...
const DEPLOY_GAIN := 90        # ... to stand this much higher
const DEPLOY_MARGIN := 91      # ... staying this far from the map edge
const RISE_LAT := 92           # missile / artillery slots look this far aside ...
const RISE_FWD := 93           # ... and this far back / forward ...
const RISE_GAIN := 94          # ... for ground this much higher
const RISE_LOF_BONUS := 95     # a bolt spot with a line of fire to the enemy counts this much higher
const LINE_SPAN := 96          # line height: sampled every this far across the line
# Withdrawal (knowing when to quit).
const WD_MIN_TICK := 97        # never withdraw before this tick
const WD_FOE_PCT := 98         # withdraw when our strength is below this % of theirs ...
const WD_START_PCT := 99       # ... or below this % of our own start and below theirs
# Pursuit and discipline.
const MIS_ROUTER_R := 100      # missile troops out of ammunition finish off routers this close
# Sieges, attacking.
const S_BEATEN_PCT := 101      # attackers withdraw below this % of their start (and weaker)
const S_STAGE_OUT := 102       # waiting line from the gate's face
const S_ART_OUT := 103         # batteries' firing line
const S_COVER_OUT := 104       # archers' line
const S_HACK_AFTER := 105      # bombardment ticks before the foot hack anyway
const S_HACKERS := 106         # foot units hacking at the gate
const S_STORM_R := 107         # assault: attack defenders this close
const S_SPREAD := 108          # ... each other unit of ours on a defender counts as this much further
const S_STALL_TICKS := 109     # under S_STALL_PROG defenders killed / gate damage for this long: a stall
const S_STALL_PROG := 110
const S_ASSAULT_ALL := 111     # after this long in the assault every unit goes in
const S_ALLOUT_PCT := 112      # a stall: all out with this % of the defenders' strength off the walls ...
const S_KEEP_PCT := 113        # ... still stalled all out: keep at it with this %, else withdraw
const S_GATE_HP_W := 114       # gate choice: metres per 100 hit points
const S_ART_SPREAD := 115      # batteries this far apart
const S_ART_REACH_PCT := 116   # a battery shoots the citadel's gate within this % of its range ...
const S_ART_CLOSE_PCT := 117   # ... else comes up to this % of its range
const S_HACK_RUN := 118        # hackers run to the gate from further than this
const S_OUTSIDE_R := 119       # waiting foot fight defenders outside the walls this close
const S_FOOT_SPREAD := 120     # waiting foot this far apart
const S_PLAZA_HUNT := 121      # at the contested plaza (its radius + this) hunt defenders anywhere
const S_STORM_RUN := 122       # storming foot run at defenders this close
const S_CIT_HACKERS := 123     # foot units hacking at the citadel's gate
const S_CIT_GATHER := 124      # the rest gather this far before it ...
const S_CIT_SPREAD := 125      # ... this far apart
const S_PLAZA_RUN := 126       # storming foot run to the plaza from further than this
const S_MIS_SPREAD := 127      # covering archers this far apart
const S_MIS_BREACH := 128      # ... in the assault, this far from the breach
const S_OPEN_PCT := 129        # open town: archers stand off at this % of its radius ...
const S_OPEN_OUT := 130        # ... plus this
const S_CAV_OUTSIDE_R := 131   # cavalry rides at defenders outside the walls this close
const S_CAV_WING := 132        # cavalry waits this many metres to the side of the gate ...
const S_CAV_WING_STEP := 133   # ... each further pair this many more
const S_CAV_BACK := 134        # ... and this much further out than the foot
const S_FOOT_ROUTER_R := 135   # pursuit: foot attack routers this close
const S_MIS_ROUTER_R := 136    # ... missile troops out of ammunition
const S_CAV_ROUTER_R := 137    # ... cavalry
# Sieges, defending.
const S_GATE_POST_R := 138     # foot this close inside a gate hold it
const S_GATE_REACT := 139      # gate guards attack attackers this close to the gate
const S_STREET_R := 140        # ... a broken gate: attackers in the town this close
const S_RESERVE_R := 141       # reserves attack attackers inside this close to their post
const S_RESERVE_RUN := 142     # ... running at those this close
const S_CLOSE_R := 143         # close an open gate with attackers this close
const S_OFFWALL_R := 144       # wall units come down with attackers in the town this close
const S_CIT_LOST_R := 145      # attackers this close to the citadel's gate: into the citadel
const S_CIT_SHUT_R := 146      # ... and it is shut with attackers this close
const S_CIT_REACT := 147       # in the citadel, attack attackers within its radius + this
const N_KNOBS := 148

## [knob, EASY, AVERAGE, SKILLED], grouped by competency (docs/AI.md 3.x).
## Step 1: every row has EASY = SKILLED = AVERAGE = the old constant.
const KNOBS: Array = [
	# Reaction (2: think interval).
	[ARMY_THINK, 10, 10, 10],
	[UNIT_THINK, 10, 10, 10],
	[REPLAN_DIST, 15 * M, 15 * M, 15 * M],
	[REPLAN_FACE, 24, 24, 24],
	# Deployment (3.1).
	[LINE_GAP, 4 * M, 4 * M, 4 * M],
	[LINE2_BACK, 35 * M, 35 * M, 35 * M],
	[MISSILE_AHEAD, 15 * M, 15 * M, 15 * M],
	[MAX_LINE, 8, 8, 8],
	[WING_GAP, 10 * M, 10 * M, 10 * M],
	# Approach and skirmish (3.2).
	[SKIRMISH_HALT, 105 * M, 105 * M, 105 * M],
	[ENGAGE_DIST, 60 * M, 60 * M, 60 * M],
	[ENGAGE_RUSH, 20 * M, 20 * M, 20 * M],
	[HALT_SHORT, 10 * M, 10 * M, 10 * M],
	[SKIRMISH_TICKS, 1100, 1100, 1100],
	[SKIRMISH_MISSILE_PCT, 70, 70, 70],
	[SKIRMISH_AMMO_PCT, 25, 25, 25],
	[SHELLED_TICKS, 60, 60, 60],
	# Engagement and target choice (3.3).
	[CHARGE_RANGE, 35 * M, 35 * M, 35 * M],
	[SPEAR_CAV_R, 40 * M, 40 * M, 40 * M],
	# Flanking and the rear (3.4).
	[PIKE_ALT_PCT, 150, 150, 150],
	[FLANK_OUT, 14 * M, 14 * M, 14 * M],
	[FLANK_ARRIVE, 8 * M, 8 * M, 8 * M],
	[FLANK_TIMEOUT, 300, 300, 300],
	# Cavalry (3.5).
	[CAV_MELEE_TICKS, 50, 50, 50],
	[CAV_PULL_DIST, 45 * M, 45 * M, 45 * M],
	[CAV_PULL_BIAS, 40 * M, 40 * M, 40 * M],
	[CAV_PULL_TICKS, 100, 100, 100],
	[CAV_STAGE_TICKS, 250, 250, 250],
	[CAV_RESTAGE_DIST, 20 * M, 20 * M, 20 * M],
	[CAV_STAGE_OUT, 25 * M, 25 * M, 25 * M],
	[CAV_STAGE_BACK, 20 * M, 20 * M, 20 * M],
	[CAV_ARROW_REACT, 30, 30, 30],
	[CAV_SHELL_REACT, 30, 30, 30],
	[UNPROTECTED, 30 * M, 30 * M, 30 * M],
	[CAV_THREAT, 60 * M, 60 * M, 60 * M],
	[CAV_SC_ROUTER, 1000, 1000, 1000],
	[CAV_SC_MISSILE, 4000, 4000, 4000],
	[CAV_SC_MISSILE_FIRE, 2600, 2600, 2600],
	[CAV_MISSILE_CLOSE, 50, 50, 50],
	[CAV_SC_BATTERY, 4200, 4200, 4200],
	[CAV_SC_BATTERY_GUARDED, 2200, 2200, 2200],
	[CAV_SC_CAV_THREAT, 3500, 3500, 3500],
	[CAV_SC_ENGAGED, 3000, 3000, 3000],
	[CAV_SC_ENGAGED_BRACED, 2500, 2500, 2500],
	[CAV_SC_MISSILE_LATE, 2000, 2000, 2000],
	[CAV_SC_DIST, 4, 4, 4],
	[CAV_SC_UPHILL, 6000, 6000, 6000],
	[CAV_SC_WOODS_PATH, 30, 30, 30],
	[CAV_SC_WOODS_AT, 600, 600, 600],
	# Missile use (3.6).
	[MIS_BEHIND, 25 * M, 25 * M, 25 * M],
	[MIS_FALLBACK, 40 * M, 40 * M, 40 * M],
	[SHELTER_CAV_R, 70 * M, 70 * M, 70 * M],
	# Artillery (3.7).
	[ART_BACK, 25 * M, 25 * M, 25 * M],
	[ART_MOVE, 30 * M, 30 * M, 30 * M],
	[ART_DEPLOY_MOVE, 25 * M, 25 * M, 25 * M],
	[GUARD_OUT, 14 * M, 14 * M, 14 * M],
	[GUARD_FWD, 5 * M, 5 * M, 5 * M],
	[GUARD_RANGE, 70 * M, 70 * M, 70 * M],
	[GUARD_MIN_MELEE, 5, 5, 5],
	[REFILL_SAFE, 35 * M, 35 * M, 35 * M],
	[REFILL_WATCH, 100 * M, 100 * M, 100 * M],
	[REFILL_LOW_PCT, 25, 25, 25],
	[REFILL_FULL_PCT, 75, 75, 75],
	[ART_SC_BATTERY, 900, 900, 900],
	[ART_SC_PIKE_PCT, 150, 150, 150],
	[ART_SC_CAV_PCT, 50, 50, 50],
	[ART_SC_STILL_NUM, 4, 4, 4],
	[ART_SC_STILL_DEN, 3, 3, 3],
	[ART_SC_MOVING_PCT, 50, 50, 50],
	[SIDESTEP, 40 * M, 40 * M, 40 * M],
	# Reserves and rotation (3.8).
	[RETIRE_ALIVE_PCT, 30, 30, 30],
	[RETIRE_TICKS, 300, 300, 300],
	[RETIRE_BACK, 60 * M, 60 * M, 60 * M],
	# Morale and chain routs (3.9).
	[RETIRE_MORALE, 350, 350, 350],
	# Terrain and woods (3.10).
	[HOLD_DH, 4 * M, 4 * M, 4 * M],
	[HOLD_TICKS, 2400, 2400, 2400],
	[HOLD_REACT, 25 * M, 25 * M, 25 * M],
	[HOLD_OUTSHOT_PCT, 130, 130, 130],
	[HOLD_OUTSHOT_SLACK, 200, 200, 200],
	[HOLD_FIGHT_DIV, 3, 3, 3],
	[DETOUR_GRADE, 614, 614, 614],
	[DETOUR_MIN, 35 * M, 35 * M, 35 * M],
	[DETOUR_LONG, 17, 17, 17],
	[DETOUR_OUT, 25 * M, 25 * M, 25 * M],
	[DETOUR_GENTLE_NUM, 2, 2, 2],
	[DETOUR_GENTLE_DEN, 3, 3, 3],
	[DETOUR_TIMEOUT, 400, 400, 400],
	[CREST_GAIN, 1536, 1536, 1536],
	[CREST_REACH, 40 * M, 40 * M, 40 * M],
	[DEPLOY_SHIFT, 30 * M, 30 * M, 30 * M],
	[DEPLOY_GAIN, 2 * M, 2 * M, 2 * M],
	[DEPLOY_MARGIN, 50 * M, 50 * M, 50 * M],
	[RISE_LAT, 12 * M, 12 * M, 12 * M],
	[RISE_FWD, 10 * M, 10 * M, 10 * M],
	[RISE_GAIN, 1024, 1024, 1024],
	[RISE_LOF_BONUS, 4 * M, 4 * M, 4 * M],
	[LINE_SPAN, 30 * M, 30 * M, 30 * M],
	# Knowing when to quit (3.14).
	[WD_MIN_TICK, 600, 600, 600],
	[WD_FOE_PCT, 30, 30, 30],
	[WD_START_PCT, 20, 20, 20],
	# Pursuit and discipline (3.13).
	[MIS_ROUTER_R, 40 * M, 40 * M, 40 * M],
	[S_FOOT_ROUTER_R, 80 * M, 80 * M, 80 * M],
	[S_MIS_ROUTER_R, 40 * M, 40 * M, 40 * M],
	[S_CAV_ROUTER_R, 200 * M, 200 * M, 200 * M],
	# Sieges, attacking (3.11).
	[S_BEATEN_PCT, 35, 35, 35],
	[S_STAGE_OUT, 160 * M, 160 * M, 160 * M],
	[S_ART_OUT, 165 * M, 165 * M, 165 * M],
	[S_COVER_OUT, 110 * M, 110 * M, 110 * M],
	[S_HACK_AFTER, 1200, 1200, 1200],
	[S_HACKERS, 2, 2, 2],
	[S_STORM_R, 45 * M, 45 * M, 45 * M],
	[S_SPREAD, 25 * M, 25 * M, 25 * M],
	[S_STALL_TICKS, 1500, 1500, 1500],
	[S_STALL_PROG, 10, 10, 10],
	[S_ASSAULT_ALL, 2400, 2400, 2400],
	[S_ALLOUT_PCT, 120, 120, 120],
	[S_KEEP_PCT, 150, 150, 150],
	[S_GATE_HP_W, 4, 4, 4],
	[S_ART_SPREAD, 30 * M, 30 * M, 30 * M],
	[S_ART_REACH_PCT, 92, 92, 92],
	[S_ART_CLOSE_PCT, 70, 70, 70],
	[S_HACK_RUN, 40 * M, 40 * M, 40 * M],
	[S_OUTSIDE_R, 40 * M, 40 * M, 40 * M],
	[S_FOOT_SPREAD, 34 * M, 34 * M, 34 * M],
	[S_PLAZA_HUNT, 15 * M, 15 * M, 15 * M],
	[S_STORM_RUN, 25 * M, 25 * M, 25 * M],
	[S_CIT_HACKERS, 3, 3, 3],
	[S_CIT_GATHER, 20 * M, 20 * M, 20 * M],
	[S_CIT_SPREAD, 14 * M, 14 * M, 14 * M],
	[S_PLAZA_RUN, 40 * M, 40 * M, 40 * M],
	[S_MIS_SPREAD, 26 * M, 26 * M, 26 * M],
	[S_MIS_BREACH, 40 * M, 40 * M, 40 * M],
	[S_OPEN_PCT, 112, 112, 112],
	[S_OPEN_OUT, 50 * M, 50 * M, 50 * M],
	[S_CAV_OUTSIDE_R, 100 * M, 100 * M, 100 * M],
	[S_CAV_WING, 90, 90, 90],
	[S_CAV_WING_STEP, 30, 30, 30],
	[S_CAV_BACK, 20 * M, 20 * M, 20 * M],
	# Sieges, defending (3.12).
	[S_GATE_POST_R, 20 * M, 20 * M, 20 * M],
	[S_GATE_REACT, 25 * M, 25 * M, 25 * M],
	[S_STREET_R, 60 * M, 60 * M, 60 * M],
	[S_RESERVE_R, 140 * M, 140 * M, 140 * M],
	[S_RESERVE_RUN, 30 * M, 30 * M, 30 * M],
	[S_CLOSE_R, 100 * M, 100 * M, 100 * M],
	[S_OFFWALL_R, 40 * M, 40 * M, 40 * M],
	[S_CIT_LOST_R, 30 * M, 30 * M, 30 * M],
	[S_CIT_SHUT_R, 25 * M, 25 * M, 25 * M],
	[S_CIT_REACT, 8 * M, 8 * M, 8 * M],
]

## Personality offsets [knob, CAUTIOUS, BALANCED, AGGRESSIVE], added to the
## skill's value (docs/AI.md 5: risk appetite). BALANCED is always 0. Step
## 1: every offset is 0 (the rows mark the knobs personality will move:
## when to quit, cavalry risk, how long to stand and shoot).
const STYLE: Array = [
	[WD_FOE_PCT, 0, 0, 0],
	[WD_START_PCT, 0, 0, 0],
	[S_BEATEN_PCT, 0, 0, 0],
	[CAV_SC_ENGAGED_BRACED, 0, 0, 0],
	[SKIRMISH_TICKS, 0, 0, 0],
]

# --------------------------------------------- diagnostic counters ------
# BattleSim.stat_aic[side * N_COUNTERS + C_*] (docs/AI.md 6): what the AI
# (or the side, for C_FLANK_HIT / C_AMMO_AT_ROUT) did. Diagnostics only:
# never read by the sim or the AI, not in state_hash().
const C_FLANK_HIT := 0         # charge impacts on the flank or rear of a ready enemy (any side)
const C_PULL_OUT := 1          # cavalry pull-outs from a melee
const C_ROTATION := 2          # a relief unit took over a tired unit's fight (none yet)
const C_SAVED := 3             # units that fell back mauled and returned to the fight
const C_INF_CHASE := 4         # foot ordered at a routing enemy
const C_SPEAR_RESP := 5        # spears turning on enemy cavalry ...
const C_SPEAR_RESP_T := 6      # ... ticks since that cavalry came within SPEAR_CAV_R (sum)
const C_MISSILE_CAUGHT := 7    # missile unit-thinks spent in melee
const C_AMMO_AT_ROUT := 8      # missiles left in missile units when they routed (sum) ...
const C_MISSILE_ROUTS := 9     # ... over this many routs
const C_RESERVE_COMMIT := 10   # reserves committed (none yet)
const N_COUNTERS := 11
const COUNTER_NAMES: Array[String] = ["flank_hits", "pull_outs", "rotations", "saved", "inf_chase",
	"spear_resp", "spear_resp_ticks", "missile_caught", "ammo_at_rout", "missile_routs", "reserve_commits"]


static var _tab: Array = []


## The knobs of sim side `side` (its scenario's ai_skill / ai_style).
static func of(sim, side: int) -> PackedInt32Array:
	if _tab.is_empty():
		_build()
	return _tab[sim.ai_skill[side] * 3 + sim.ai_style[side]]


## The knobs of a skill level and personality.
static func row(skill: int, style: int) -> PackedInt32Array:
	if _tab.is_empty():
		_build()
	return _tab[clampi(skill, EASY, SKILLED) * 3 + clampi(style, CAUTIOUS, AGGRESSIVE)]


static func _build() -> void:
	# (Packed arrays are values: each row is filled in a local, then stored.)
	var tab: Array = []
	for s in 3:
		var base := PackedInt32Array()
		base.resize(N_KNOBS)
		base.fill(-0x7FFFFFFF)
		for r in KNOBS:
			base[int(r[0])] = int(r[1 + s])
		for k in N_KNOBS:
			if base[k] == -0x7FFFFFFF:
				push_error("ai_profile: knob %d has no value" % k)
		for y in 3:
			var p := base.duplicate()
			for r in STYLE:
				p[int(r[0])] += int(r[1 + y])
			tab.append(p)
	_tab = tab
