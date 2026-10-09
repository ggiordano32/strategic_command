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
## value exactly the old constant); every personality offset is 0.
## Step 2 (October 2026): the EASY column (docs/AI.md section 9, "As built:
## Easy"): slower thinking, narrower perception, no terrain sense, no
## pull-outs, no reserve or relief, and the deliberate mistakes (M_*, rolled
## only where the level's MK_BASE + M_* is above 0, so Average and Skilled
## never draw from the RNG for them).
## Step 3 (October 2026): the SKILLED column (docs/AI.md section 11, "As
## built: Skilled"): Average's values where they measured best, plus the
## SK_* behaviours (0 = off for Easy and Average: those levels never run
## them, never draw the RNG for them and keep no Skilled memory, so they
## play and hash exactly as before).
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
# Step 2 (Easy): behaviours a level switches off, and the deliberate mistakes.
const CLEAR_SPOT := 148        # deployment: cavalry, pikes, batteries in woods look for a clear spot (1) or not (0)
const CAV_STAGE_FRONT := 149   # cavalry goes round a formed, unengaged front (1) or charges it head on (0)
const FLANK_PCT := 150         # % chance a unit facing a pinned pike front goes round to its flank
const WD_EARLY_PCT := 151      # below this % of the enemy's strength, MK_EARLY_WD is rolled (once a battle)
const IDLE_TICKS := 152        # a unit left idle (MK_IDLE) waits this long unless it is attacked
const MK_COOLDOWN := 153       # after a mistake, the side cannot make that mistake again for this long
const S_CIT_OUTNUMBER_PCT := 154  # defenders go into the citadel when the attackers inside the walls exceed this % of them
const MIS_SKIRM := 155         # missile troops are put in skirmish mode (evade charges) (1) or never (0)
const MIS_CLEAN := 156         # missile troops hold fire unless an unengaged enemy is in range (1) or shoot at will (0)
const MK_BASE := 157           # MK_BASE + M_*: % chance of that mistake per roll (0: never rolled)
# Step 3 (Skilled): behaviours a level switches on (0 = off: Easy and
# Average never run them, never draw from the RNG for them and never write
# BattleSim.ai_mem). Ids after the mistakes (MK_BASE + N_MISTAKES = 166).
const SK_MEM := 166            # the side keeps Skilled memory (BattleSim.ai_mem) (1) or none (0)
const SK_ASSIGN := 167         # foot targets come from the army's matchup pass (1) or each unit's nearest (0)
const SK_ASSIGN_REACH := 168   # ... candidates up to this % of the nearest enemy's distance ...
const SK_ASSIGN_SLACK := 169   # ... plus this
const SK_SC_PAIR := 170        # ... score for a second attacker on a target already engaged (concentration)
const SK_SC_MATCH := 171       # ... score for a good matchup (heavy on light, spears on cavalry, foot on missiles)
const SK_SC_BAD := 172         # ... penalty for a bad one (a formed pike front, heavy on unengaged heavy)
const SK_SC_FLANK := 173       # ... for a target engaged by ours that we would hit in the flank or rear
const SK_SC_MORALE := 174      # target scores (foot, cavalry, missiles): per 10 morale under SK_BREAK_MORALE
const SK_BREAK_MORALE := 175   # "near breaking": morale below this
const SK_PULL_READ := 176      # cavalry pulls out of a melee only when not winning it (1) or always (0) ...
const SK_WIN_PCT := 177        # ... winning: the enemy lost at least this % of what it lost since contact
const SK_CAV_RESERVE := 178    # cavalry units held back until the enemy wavers or routs (only counter-charges)
const SK_CAV_PAIR := 179       # cavalry target score for a target another of ours is charging or staging on
const SK_PAIR_WAIT := 180      # ... a staged rider waits at most this long for its partner to arrive
const SK_FOCUS := 181          # missile troops pick one target together (1) or fire at will (0)
const SK_AMMO_KEEP_PCT := 182  # missile troops keep this % of their missiles for routers and riders
const SK_GUARD_CAV_R := 183    # a battery guard joins the fight with no enemy cavalry this close to the battery (0: always guards)
const SK_RESERVE := 184        # foot units held in reserve behind the centre
const SK_RESERVE_BACK := 185   # ... this far behind the line
const SK_ROTATE := 186         # rotation: a relief unit takes over a tired unit's fight (1) or none (0) ...
const SK_ROT_MORALE_PCT := 187 # ... tired: morale below this % of its type's
const SK_ROT_DELAY := 188      # ... the tired unit pulls out this long after the relief engages
const SK_ROT_SAFE_R := 189     # ... unless enemy cavalry is this close
const SK_WAVER_PULL := 190     # own wavering units (morale below this) near a routing friend, not fighting, fall back
const SK_MIS_EARLY_R := 191    # missile troops go back behind the line with enemy foot this close (0: when the lines meet)
const SK_SPEAR_LEAD := 192     # spears watch enemy cavalry where it will be in this many ticks
const SK_ART_PULL := 193       # a battery whose crew is threatened and unguarded pulls back (1) or stays (0)
const SK_CAV_COUNTER := 194    # cavalry counter-charges enemy cavalry engaged with our units (score)
const SK_WD_COVER := 195       # withdrawing in good order: cavalry and missiles cover for this long
const SK_STORM_STAGGER := 196  # sieges, attacking: storming units spread over the streets (1) or all to the plaza (0)
const SK_FEINT := 197          # ... a feint: waiting foot units show at another gate
const SK_WALL_ART := 198       # ... batteries shoot the wall units over the gate before the gate (ticks)
const S_WALL_SHIFT := 199      # sieges, defending: idle wall missile units shift to the stretches by the attacked gate (1; was Skilled's SK_WALL_SHIFT)
const SK_MIS_DOWN_PCT := 200   # ... wall missile units come down when the gate is below this % of its hit points
const SK_BREACH := 201         # ... reserves counter-charge the breach (1)
const SK_SALLY_R := 202        # ... sally against an isolated attacker this close to a gate (0: never)
const SK_MIRROR := 203         # deployment: the spears take the end of the line facing the enemy's riders (1)
const SK_ANCHOR := 204         # deployment: shift the line up to this far aside to rest a flank on woods (0: never)
const SK_SC_UPHILL := 205      # matchup score: less this per % of climb to the target
const SK_SC_STICK := 206       # matchup score for the target the unit already goes for (no flip-flopping)
const SK_SC_COVER := 207       # matchup score for a target none of ours is on yet (pin every enemy first)
# Siege equipment and wall towers (docs/AI.md 13; every level runs them).
const S_LADDER_UNITS := 208    # attacking foot units sent up the ladders (heaviest first)
const S_LADDER_DEF_W := 209    # ... the stretch: metres from the gate plus this many per defender on it
const S_LADDER_AFTER := 210    # ... sent this long into the approach
const S_TOWER_FOCUS := 211     # defending towers pick the ram, batteries, men at the gate or on ladders (1) or fire at will (0)
const S_COUNTER_BAT := 212     # attacking batteries shoot towers this near the gate first (0: never)
const S_ESC_REPLY := 213       # defenders send a foot unit up against ladder men (1) or not (0)
const S_RAM_WAIT := 214        # the ram waits for the gate's towers to be silenced at most this long into the approach
const S_LADDER_WALLS := 215    # with working artillery, ladders only against walls of this level or more (no artillery: any)
# Street fights (docs/AI.md 14; units do not pass through each other).
# Sieges, defending: the layout at the attacked gate (docs/AI.md 16, part 2c;
# ids 216-219 were part 2a's Skilled breach hold, folded into it).
const S_MOUTH := 216           # the foot reserve stacks up in the attacked gate's inner mouth, plaza reserve behind (1) or the old reserves (0)
const S_MOUTH_IN := 217        # ... the front's anchor this far inside the wall's inner face
const S_MOUTH_REACT := 218     # ... units of the stack attack attackers (inside the gate's outer face) this close to their post
const S_GUARD_JOIN := 219      # ... the guards of gates with no attacking foot this near (and not hit) join the stack (0: they stay)
# Siege equipment as objects, shut inner gates (docs/AI.md 15).
const S_LADDER_FOLLOW := 220   # attacking infantry sent up a planted ladder set after its own party
const S_CIT_WAIT := 221        # attackers before a shut gate nobody can hurt wait this far from it
const S_READ_R := 222          # the attacked gate read from the field: attacking foot within this of a gate, batteries' / the ram's / ladders' gate (0: only once it is hit or open)
const S_READ_PCT := 223        # ... once that gate has at least this % of the attackers' strength ...
const S_READ_TICKS := 224      # ... for this long (hit or open: at once)
const S_MOUTH_W := 225         # the stack's front unit stands this wide across the gateway's inner end
const S_PLAZA_REACT := 226     # the plaza reserve attacks attackers within the plaza's radius + this
const S_ROT_PCT := 227         # the front is relieved by the next unit of the stack below this % of its type's morale (0: never)
const S_SHUT_EMPTY := 228      # an open gate with no unit of ours in its mouth is shut, a sally's behind it (1) or only with attackers near (0)
const S_TOKEN_MEN := 229       # a quiet gate keeps a rider as its token, else its guard if at most this many men
const S_MOUTH_FRONTS := 230    # the stack's front: this many units side by side across the gateway's inner end
const S_MOUTH_BACK := 231      # ... standing this much further in while the gate is shut (out of the shots at it)
const S_ROT_LULL := 232        # ... the front is relieved only between waves, not fighting (1), or only while it fights (0)
const N_KNOBS := 233

# Deliberate mistakes (docs/AI.md 3, "Deliberate mistakes"), rolled with the
# sim's RNG at the decision point (battle_ai.gd _mistake): each is an order a
# player could give. Per side, a mistake made cannot recur for MK_COOLDOWN
# (BattleSim.ai_mist, hashed when a profile is not the default).
const M_LATE_FLANK := 0        # spears / cavalry ignore an enemy cavalry threat, a town reserve attackers near it, this think
const M_WRONG_TARGET := 1      # cavalry rides at the nearest enemy foot instead of the target it chose
const M_IDLE := 2              # a line unit is left idle when the lines engage
const M_CHASE := 3             # foot chase a routing enemy instead of the fight
const M_SPEAR_CHARGE := 4      # cavalry charges a braced front, or foot walk into a formed pike front
const M_MIS_FORGET := 5        # archers are not pulled back behind the line when the lines meet
const M_COMMIT_EARLY := 6      # the cavalry (the reserve) charges the enemy line before the lines meet (once a battle)
const M_GATE_OPEN := 7         # a defender's gate is not closed this time with attackers near
const M_EARLY_WD := 8          # the army withdraws while still in the fight (once a battle)
const N_MISTAKES := 9
const MISTAKE_NAMES: Array[String] = ["late_flank", "wrong_target", "idle", "chase", "spear_charge",
	"mis_forget", "commit_early", "gate_open", "early_wd"]

## [knob, EASY, AVERAGE, SKILLED], grouped by competency (docs/AI.md 3.x).
## AVERAGE = the old constant; SKILLED = AVERAGE (step 3 changes it).
const KNOBS: Array = [
	# Reaction (2: think interval).
	[ARMY_THINK, 35, 10, 10],
	[UNIT_THINK, 30, 10, 10],
	[REPLAN_DIST, 25 * M, 15 * M, 15 * M],
	[REPLAN_FACE, 48, 24, 24],
	# Deployment (3.1).
	[LINE_GAP, 4 * M, 4 * M, 4 * M],
	[LINE2_BACK, 35 * M, 35 * M, 35 * M],
	[MISSILE_AHEAD, 15 * M, 15 * M, 15 * M],
	[MAX_LINE, 12, 8, 8],
	[WING_GAP, 10 * M, 10 * M, 10 * M],
	# Approach and skirmish (3.2).
	[SKIRMISH_HALT, 105 * M, 105 * M, 105 * M],
	[ENGAGE_DIST, 60 * M, 60 * M, 60 * M],
	[ENGAGE_RUSH, 20 * M, 20 * M, 20 * M],
	[HALT_SHORT, 10 * M, 10 * M, 10 * M],
	[SKIRMISH_TICKS, 400, 1100, 1100],
	[SKIRMISH_MISSILE_PCT, 70, 70, 70],
	[SKIRMISH_AMMO_PCT, 5, 25, 25],
	[SHELLED_TICKS, 60, 60, 60],
	# Engagement and target choice (3.3).
	[CHARGE_RANGE, 35 * M, 35 * M, 35 * M],
	[SPEAR_CAV_R, 20 * M, 40 * M, 40 * M],
	# Flanking and the rear (3.4).
	[PIKE_ALT_PCT, 110, 150, 150],
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
	[CAV_THREAT, 25 * M, 60 * M, 60 * M],
	[CAV_SC_ROUTER, 5000, 1000, 1000],
	[CAV_SC_MISSILE, 4000, 4000, 4000],
	[CAV_SC_MISSILE_FIRE, 2600, 2600, 2600],
	[CAV_MISSILE_CLOSE, 50, 50, 50],
	[CAV_SC_BATTERY, 4200, 4200, 4200],
	[CAV_SC_BATTERY_GUARDED, 2200, 2200, 2200],
	[CAV_SC_CAV_THREAT, 3500, 3500, 3500],
	[CAV_SC_ENGAGED, 3000, 3000, 3000],
	[CAV_SC_ENGAGED_BRACED, 3000, 2500, 2500],
	[CAV_SC_MISSILE_LATE, 2000, 2000, 2000],
	[CAV_SC_DIST, 4, 4, 4],
	[CAV_SC_UPHILL, 0, 6000, 6000],
	[CAV_SC_WOODS_PATH, 0, 30, 30],
	[CAV_SC_WOODS_AT, 0, 600, 600],
	# Missile use (3.6).
	[MIS_BEHIND, 25 * M, 25 * M, 25 * M],
	[MIS_FALLBACK, 40 * M, 40 * M, 40 * M],
	[SHELTER_CAV_R, 0, 70 * M, 70 * M],
	# Artillery (3.7).
	[ART_BACK, 25 * M, 25 * M, 25 * M],
	[ART_MOVE, 30 * M, 30 * M, 30 * M],
	[ART_DEPLOY_MOVE, 1000 * M, 25 * M, 25 * M],
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
	[RETIRE_ALIVE_PCT, 0, 30, 30],
	[RETIRE_TICKS, 300, 300, 300],
	[RETIRE_BACK, 60 * M, 60 * M, 60 * M],
	# Morale and chain routs (3.9).
	[RETIRE_MORALE, 350, 350, 350],
	# Terrain and woods (3.10).
	[HOLD_DH, 1000 * M, 4 * M, M / 2],
	[HOLD_TICKS, 2400, 2400, 2400],
	[HOLD_REACT, 25 * M, 25 * M, 25 * M],
	[HOLD_OUTSHOT_PCT, 130, 130, 130],
	[HOLD_OUTSHOT_SLACK, 200, 200, 200],
	[HOLD_FIGHT_DIV, 3, 3, 3],
	[DETOUR_GRADE, 1 << 20, 614, 614],
	[DETOUR_MIN, 35 * M, 35 * M, 35 * M],
	[DETOUR_LONG, 17, 17, 17],
	[DETOUR_OUT, 25 * M, 25 * M, 25 * M],
	[DETOUR_GENTLE_NUM, 2, 2, 2],
	[DETOUR_GENTLE_DEN, 3, 3, 3],
	[DETOUR_TIMEOUT, 400, 400, 400],
	[CREST_GAIN, 1000 * M, 1536, 1536],
	[CREST_REACH, 40 * M, 40 * M, 40 * M],
	[DEPLOY_SHIFT, 0, 30 * M, 30 * M],
	[DEPLOY_GAIN, 2 * M, 2 * M, 2 * M],
	[DEPLOY_MARGIN, 50 * M, 50 * M, 50 * M],
	[RISE_LAT, 12 * M, 12 * M, 12 * M],
	[RISE_FWD, 10 * M, 10 * M, 10 * M],
	[RISE_GAIN, 1000 * M, 1024, 1024],
	[RISE_LOF_BONUS, 0, 4 * M, 4 * M],
	[LINE_SPAN, 30 * M, 30 * M, 30 * M],
	# Knowing when to quit (3.14).
	[WD_MIN_TICK, 600, 600, 600],
	[WD_FOE_PCT, 15, 30, 30],
	[WD_START_PCT, 10, 20, 20],
	# Pursuit and discipline (3.13).
	[MIS_ROUTER_R, 40 * M, 40 * M, 40 * M],
	[S_FOOT_ROUTER_R, 200 * M, 80 * M, 80 * M],
	[S_MIS_ROUTER_R, 40 * M, 40 * M, 40 * M],
	[S_CAV_ROUTER_R, 200 * M, 200 * M, 200 * M],
	# Sieges, attacking (3.11).
	[S_BEATEN_PCT, 20, 35, 35],
	[S_STAGE_OUT, 160 * M, 160 * M, 160 * M],
	[S_ART_OUT, 165 * M, 165 * M, 165 * M],
	[S_COVER_OUT, 110 * M, 110 * M, 110 * M],
	[S_HACK_AFTER, 0, 1200, 1200],
	[S_HACKERS, 4, 2, 2],
	[S_LADDER_UNITS, 1, 2, 3],
	[S_LADDER_DEF_W, 0, 1, 3],
	[S_LADDER_AFTER, 0, 300, 300],
	[S_TOWER_FOCUS, 0, 1, 1],
	[S_COUNTER_BAT, 40 * M, 60 * M, 90 * M],
	[S_ESC_REPLY, 0, 1, 1],
	[S_RAM_WAIT, 0, 0, 900],
	[S_LADDER_WALLS, 1, 2, 2],
	[S_LADDER_FOLLOW, 0, 1, 1],
	[S_CIT_WAIT, 50 * M, 50 * M, 50 * M],
	[S_STORM_R, 45 * M, 45 * M, 45 * M],
	[S_SPREAD, 25 * M, 25 * M, 25 * M],
	[S_STALL_TICKS, 1500, 1500, 1500],
	[S_STALL_PROG, 10, 10, 10],
	[S_ASSAULT_ALL, 600, 2400, 2400],
	[S_ALLOUT_PCT, 120, 120, 120],
	[S_KEEP_PCT, 150, 150, 150],
	[S_GATE_HP_W, 0, 4, 4],
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
	[S_RESERVE_R, 60 * M, 140 * M, 140 * M],
	[S_RESERVE_RUN, 30 * M, 30 * M, 30 * M],
	[S_CLOSE_R, 40 * M, 100 * M, 100 * M],
	[S_OFFWALL_R, 15 * M, 40 * M, 40 * M],
	[S_CIT_LOST_R, 10 * M, 30 * M, 30 * M],
	[S_CIT_SHUT_R, 25 * M, 25 * M, 25 * M],
	[S_CIT_REACT, 8 * M, 8 * M, 8 * M],
	[S_CIT_OUTNUMBER_PCT, 200, 100, 100],
	# The layout at the attacked gate (part 2c).
	[S_MOUTH, 0, 1, 1],
	[S_MOUTH_IN, 2 * M, 2 * M, 2 * M],
	[S_MOUTH_REACT, 24 * M, 24 * M, 24 * M],
	[S_GUARD_JOIN, 0, 120 * M, 120 * M],
	[S_READ_R, 0, 220 * M, 260 * M],
	[S_READ_PCT, 0, 50, 35],
	[S_READ_TICKS, 0, 100, 30],
	[S_MOUTH_W, 20 * M, 20 * M, 20 * M],
	[S_PLAZA_REACT, 20 * M, 20 * M, 20 * M],
	[S_ROT_PCT, 0, 40, 60],
	[S_SHUT_EMPTY, 0, 1, 1],
	[S_TOKEN_MEN, 60, 60, 60],
	[S_MOUTH_FRONTS, 1, 1, 1],
	[S_MOUTH_BACK, 0, 0, 20 * M],
	[S_ROT_LULL, 0, 0, 1],
	# Behaviours a level switches off (Average: on, as before).
	[CLEAR_SPOT, 0, 1, 1],
	[MIS_SKIRM, 0, 1, 1],
	[MIS_CLEAN, 1, 1, 1],
	[CAV_STAGE_FRONT, 0, 1, 1],
	[FLANK_PCT, 30, 100, 100],
	[WD_EARLY_PCT, 75, 0, 0],
	[IDLE_TICKS, 600, 600, 600],
	# Deliberate mistakes: % per roll (Average and Skilled: never rolled).
	[MK_COOLDOWN, 30, 100, 100],
	[MK_BASE + M_LATE_FLANK, 50, 0, 0],
	[MK_BASE + M_WRONG_TARGET, 15, 0, 0],
	[MK_BASE + M_IDLE, 50, 0, 0],
	[MK_BASE + M_CHASE, 90, 0, 0],
	[MK_BASE + M_SPEAR_CHARGE, 35, 0, 0],
	[MK_BASE + M_MIS_FORGET, 60, 0, 0],
	[MK_BASE + M_COMMIT_EARLY, 15, 0, 0],
	[MK_BASE + M_GATE_OPEN, 50, 0, 0],
	[MK_BASE + M_EARLY_WD, 35, 0, 0],
	# Skilled behaviours (step 3; 0 = off).
	[SK_MEM, 0, 0, 1],
	[SK_ASSIGN, 0, 0, 1],
	[SK_ASSIGN_REACH, 0, 0, 120],
	[SK_ASSIGN_SLACK, 0, 0, 5 * M],
	[SK_SC_PAIR, 0, 0, 25],
	[SK_SC_MATCH, 0, 0, 20],
	[SK_SC_BAD, 0, 0, 40],
	[SK_SC_FLANK, 0, 0, 30],
	[SK_SC_MORALE, 0, 0, 5],
	[SK_BREAK_MORALE, 0, 0, 400],
	[SK_PULL_READ, 0, 0, 1],
	[SK_WIN_PCT, 0, 0, 150],
	[SK_CAV_RESERVE, 0, 0, 1],
	[SK_CAV_PAIR, 0, 0, 600],
	[SK_PAIR_WAIT, 0, 0, 80],
	[SK_FOCUS, 0, 0, 1],
	[SK_AMMO_KEEP_PCT, 0, 0, 0],
	[SK_GUARD_CAV_R, 0, 0, 150 * M],
	[SK_RESERVE, 0, 0, 1],
	[SK_RESERVE_BACK, 0, 0, 30 * M],
	[SK_ROTATE, 0, 0, 1],
	[SK_ROT_MORALE_PCT, 0, 0, 40],
	[SK_ROT_DELAY, 0, 0, 60],
	[SK_ROT_SAFE_R, 0, 0, 60 * M],
	[SK_WAVER_PULL, 0, 0, 300],
	[SK_MIS_EARLY_R, 0, 0, 70 * M],
	[SK_SPEAR_LEAD, 0, 0, 30],
	[SK_ART_PULL, 0, 0, 1],
	[SK_CAV_COUNTER, 0, 0, 1500],
	[SK_WD_COVER, 0, 0, 150],
	[SK_STORM_STAGGER, 0, 0, 1],
	[SK_FEINT, 0, 0, 1],
	[SK_WALL_ART, 0, 0, 0],
	[S_WALL_SHIFT, 0, 1, 1],
	[SK_MIS_DOWN_PCT, 0, 0, 25],
	[SK_BREACH, 0, 0, 1],
	[SK_SALLY_R, 0, 0, 60 * M],
	[SK_MIRROR, 0, 0, 1],
	[SK_ANCHOR, 0, 0, 40 * M],
	[SK_SC_UPHILL, 0, 0, 4],
	[SK_SC_STICK, 0, 0, 25],
	[SK_SC_COVER, 0, 0, 35],
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
const C_MISTAKE := 11          # C_MISTAKE + M_*: deliberate mistakes made
const C_CAV_STAY := C_MISTAKE + N_MISTAKES  # cavalry stayed in a melee it was winning (Skilled)
const C_DOUBLE := C_CAV_STAY + 1   # timed double charges (two riders on one target within a few seconds)
const C_FOCUS := C_CAV_STAY + 2    # missile focus-fire orders
const C_GUARD_FREE := C_CAV_STAY + 3  # battery guards sent into the fight (no cavalry threat)
const C_WAVER_PULL := C_CAV_STAY + 4  # own waverers pulled back from a routing neighbour
const C_SIEGE := C_CAV_STAY + 5    # siege moves: feints, wall shifts, missiles down, breach charges, sallies
const C_ART_PULL := C_CAV_STAY + 6  # battery crews pulled back from an enemy coming for them
const N_COUNTERS := C_CAV_STAY + 7
const COUNTER_NAMES: Array[String] = ["flank_hits", "pull_outs", "rotations", "saved", "inf_chase",
	"spear_resp", "spear_resp_ticks", "missile_caught", "ammo_at_rout", "missile_routs", "reserve_commits",
	"mk_late_flank", "mk_wrong_target", "mk_idle", "mk_chase", "mk_spear_charge", "mk_mis_forget",
	"mk_commit_early", "mk_gate_open", "mk_early_wd", "cav_stay", "double_charges", "focus_orders",
	"guard_free", "waver_pull", "siege_moves", "art_pull"]

# Skilled memory layout (BattleSim.ai_mem): MU_K ints per unit, then SD_K
# per side at n_units * MU_K + side * SD_K.
const MU_ASSIGN := 0           # matchup target + 1 (0 none)
const MU_A0 := 1               # cavalry: own men at the start of this melee; rotation: relief unit + 1
const MU_T0 := 2               # cavalry: the enemy's men then; rotation: tick the relief engaged
const MU_X := 3                # role: 1 reserve, 2 rotated out, 3 reserve cavalry, 4 + b: released guard of battery b
const MU_K := 4
const SD_SALLY := 0            # settlement defenders: a sally is out through this gate + 1
const SD_COMMIT := 1           # the reserve cavalry has been released (1)
const SD_WD := 2               # withdrawal in good order began at this tick + 1
const SD_SALLY_T := 3          # ... the sally began at this tick
const SD_K := 4


static var _tab: Array = []


## True when either side's profile keeps Skilled memory (SK_MEM).
static func uses_mem(skill: PackedInt32Array, style: PackedInt32Array) -> bool:
	for s in 2:
		if row(skill[s], style[s])[SK_MEM] != 0:
			return true
	return false


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
