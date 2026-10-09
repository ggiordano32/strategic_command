extends RefCounted
## Deterministic per-soldier battle simulation (milestone 2: infantry, pikes,
## missiles, cavalry charges, morale, withdrawal and a battle AI; artillery).
##
## Rules this file must keep (see CLAUDE.md and docs/DESIGN.md section 5):
## - Integers only. No float appears in state or logic, including setup.
## - Own seeded RNG (xorshift32, explicitly masked to 32 bits).
## - Fixed iteration order: soldiers and units are always visited by index;
##   no Dictionary ordering or object ids are relied on.
## - No per-soldier objects: soldiers are struct-of-arrays in packed arrays,
##   and so are projectiles and artillery engines.
##
## Public API:
##   setup(scenario: Dictionary, seed: int)
##   queue_order(order: Dictionary)   # plain data, ints only, has "tick"
##   step()                           # advance one 10 Hz tick
##   state_hash() -> int              # 32-bit hash of the full sim state
##   result() -> Dictionary           # per-unit outcome (plain ints)
##   snapshot() / restore(blob)       # the whole state (live co-op joins, resyncs)
##   read access to the packed arrays below (view must not write them).
##
## Coordinates: 1 m = 1024 units, x right, y down. Angles 0..1023, 0 = +x,
## increasing clockwise on screen (towards +y). See fixed_math.gd.

const FM := preload("res://sim/fixed_math.gd")
const UT := preload("res://sim/unit_types.gd")
const BattleAI := preload("res://sim/battle_ai.gd")
const SiegeAI := preload("res://sim/siege_ai.gd")
const AIProfile := preload("res://sim/ai_profile.gd")
const Terrain := preload("res://sim/terrain.gd")
const MapGen := preload("res://sim/mapgen.gd")
const Scenarios := preload("res://sim/scenarios.gd")

const TICKS_PER_SECOND := 10
const M := 1024  # sim units per metre

# Soldier states. Everything >= S_DEAD is no longer on the field.
const S_FORMED := 0     # following its formation slot
const S_FIGHTING := 1   # has a melee target
const S_ROUTING := 2    # fleeing
const S_DOWN := 3       # knocked down by a charge; cooldown counts the ticks
const S_DEAD := 4
const S_OFF := 5        # left the field by the map edge (withdrawn or routed)

# Unit states. Everything >= U_DESTROYED is off the field.
const U_READY := 0
const U_ROUTING := 1
const U_DESTROYED := 2  # every soldier killed
const U_LEFT := 3       # no soldiers on the field, some left by the edge
const U_KENNEL := 4     # a war dog pack with its handlers, not on the field (docs/DESIGN.md "War dogs")

# Unit orders (current standing order of a unit).
const O_NONE := 0
const O_MOVE := 1
const O_ATTACK := 2
const O_WITHDRAW := 3

# Order types for queue_order().
const ORDER_MOVE := 1           # unit, x, y, facing, width, run
const ORDER_ATTACK := 2         # unit, target, run (missile units: shoot it)
const ORDER_HALT := 3           # unit
const ORDER_RUN := 4            # unit, run
const ORDER_FIRE := 5           # unit, on (fire at will)
const ORDER_SKIRMISH := 6       # unit, on
const ORDER_WITHDRAW := 7       # unit
const ORDER_WITHDRAW_ALL := 8   # side
const ORDER_DEPLOY := 9         # unit, on (artillery: set up / pack up)
const ORDER_REFILL := 10        # unit, on (artillery: bring up shots from the baggage)
const ORDER_GATE := 11          # unit (any of the defenders'), gate, on (1 close / 0 open)
const ORDER_PLACE := 12         # unit, x, y, facing, files (deployment phase only, inside its side's zone)
const ORDER_READY := 13         # who (deployment phase: player `who` is ready to start)
const ORDER_PICKUP := 14        # unit, equip (siege equipment) or engines (an engine group): go there and pick it up
const ORDER_DROP := 15          # unit (put down the piece it carries where it stands)
const ORDER_AMMO := 16          # unit, on (1: shoot its special ammunition kind, 0: the standard one)
const ORDER_FORAGE := 17        # unit, on (missile troops in woods: make arrows / javelins; cannot move or shoot)
const ORDER_KILL := 18          # unit (a beast running amok: its drivers kill it after its kill_delay)
const ORDER_RELEASE := 19       # unit (handlers), target (an enemy unit): the pack is let loose at it
const ORDER_WORKS := 20         # side, equip (a field work; -1: the first unplaced one of `kind`), x, y, facing, on (1 place / 0 take back); deployment only
const ORDER_LAST := 20

# Battle phase (scenario "deploy_time" > 0 starts in PHASE_DEPLOY, see the
# "deployment phase" section at the end of this file).
const PHASE_BATTLE := 0
const PHASE_DEPLOY := 1
const DZ_RECT := 0     # deployment zone: a rectangle (clamped into)
const DZ_INSIDE := 1   # settlement defenders: open ground inside the walls within the box (refused outside)

## Unit fields an order can change; OrderPreview predicts exactly these.
const ORDER_KEYS: Array[String] = ["order", "ax", "ay", "face", "files", "dx", "dy",
	"dface", "target", "run", "fire", "skirm", "deploy", "refill", "gtarget", "pick", "akind", "forage"]

# Formation geometry (spacing is per unit type, see unit_types.gd).
const FILE_SPACING := 1126  # default, kept for callers that do not pass a type
const RANK_SPACING := 1331
const MIN_FILES := 4
const REFORM_IN_PLACE_DIST := 12 * M  # shorter moves snap the anchor

# Combat geometry.
const CONTACT_MARGIN := 12 * M   # unit bboxes closer than this are "in contact"
const SEARCH_FRONT := 8 * M      # front rank looks this far for enemies
const SEARCH_REAR := 5 * M / 2   # other ranks only react to close enemies ...
const SEARCH_ENGAGED := 9 * M / 2  # ... a little further while their unit fights
                                 # off a charge (riders lapping round meet the
                                 # side files instead of idle rear ranks)
const ENGAGED_AFTER_CHARGE := 150  # ticks after the last charge impact
const TARGET_KEEP_EXTRA := 2 * M
const PLACE_LEAD := 3 * M / 2    # a fighting man walks at most this far ahead of
                                 # his place (along the unit's facing): the
                                 # front rank stays with its body
const PLACE_SIDE := 3 * M        # ... and at most this far to either side of it
const INREACH_EXTRA := M         # a man this close past his reach counts as
                                 # in reach (u_inreach: the anchor stops closing)
const WRAP_GAP := M              # wrap at the anchor level: outer front-rank places curl round the target's flank this far out from it
const PIN_TICKS := 8             # a unit an artillery shot struck is pinned this long (u_shelled_t): its anchor does not advance
const ANCHOR_LEAD := 2 * M       # an engaged unit's anchor closes only while it is
                                 # at most this far beyond its men's middle
                                 # (half the depth ahead of it)
const SEPARATION := 717          # 0.7 m: friendly fighters push apart
const CAV_SEPARATION := 1434     # 1.4 m between riders
const CATCH_UP_DIST := 3 * M     # soldiers further than this from slot run
const GRID_SHIFT := 12           # 4 m cells (4096 units)
const EDGE_EXIT := 3 * M / 2     # soldiers this close to the edge leave

# Melee.
const BASE_HIT := 40             # (35 until the field rebalance, 2026-10-09: melee after "ranks hold together" was too slow)
const FLANK_BONUS := 25
const REAR_BONUS := 40
const DOWN_BONUS := 35           # hitting a knocked-down soldier
const FRONT_ARC := 170           # +-60 degrees
const ZONE_FRONT := 0
const ZONE_FLANK := 1
const ZONE_REAR := 2
const REAR_ARC := 341            # beyond +-120 degrees is rear

# Pikes.
const PIKE_HOLD := 2 * M         # enemies are held this far off the pike front
const PIKE_WALL_EXTRA := 614     # wall extends 0.6 m past the outer files
const PIKE_PRESS := 1024         # held attackers still lunge this much further
const PIKE_PRESS_PEN := 20       # ... at this hit penalty
const DISORDER_MAX := 100
const DISORDERED := 25           # u_disorder at or above this: formation broken
const DISORDER_FLANK_HIT := 6
const DISORDER_REAR_HIT := 10
const DISORDER_IMPACT := 10
const DISORDER_RUN := 30         # pikes running are never formed
const TURN_DISORDER := 40        # pikes more than ~14 degrees off target facing

# Cavalry.
const MOM_GAIN := 4              # momentum per tick charging at speed: full after ~2.5 s (~18 m)
const MOM_LOSS := 34
const CHARGE_MIN := 40           # momentum needed for an impact
const IMPACT_RANGE := 512        # extra reach for the impact check
const IMPACT_RADIUS := 1843      # extra victims within 1.8 m of the rider
const DOWN_TICKS := 15
const CHARGE_TICKS := 50         # a charge resolves within 5 s of contact

# Missiles.
const PR_CAP := 4096             # projectiles in flight at most
const PR_BUCKETS := 128          # landing-tick buckets (flight <= 127 ticks)
const HIT_R_INF := 600           # landing within 0.6 m of a soldier hits him
const HIT_R_CAV := 1100
const MISSILE_HIT := 85          # % of landings on a soldier that strike
const FIRE_THINK := 5            # ticks between fire-target choices
const SKIRM_INF := 30 * M        # skirmishers fall back from infantry this close
const SKIRM_CAV := 55 * M
const SKIRM_BACK := 35 * M

# Artillery. Engines are their own packed arrays (e_*); a battery's soldiers
# are its crews. Crew slot s works engine W[s % nw] (W = the working engines),
# so crews re-man engines as men fall. See docs/DESIGN.md.
const E_OK := 0
const E_WRECKED := 1             # smashed (melee next to it, or a stone)
const E_ABANDONED := 2           # left on the field (dropped, or its crew broke or died): any foot may pick it up
const PICK_ENG := 1 << 16        # u_pick of a unit going to pick up engine group g: PICK_ENG + g
const MAN_DIST := 5 * M          # crew within this of their engine work it
const ENGINE_NEAR := 2 * M       # enemy soldiers this close wreck an engine
const ENGINE_WRECK := 3          # engine hp per tick per enemy soldier (max 6)
const ENGINE_R := 1100           # shots passing this close hit the engine
const PACKED_TURN := 8           # battery wheel rate per tick when packed up
const ALIGN := 9                 # engine within this of the bearing may shoot
const SHOT_STOP := 25            # a shot with less energy left stops
const BOLT_SKIP := 3 * M         # bolts clear the engine's own crew
const BOLT_BODY := 20            # energy a body absorbs (plus its armour)
const BOLT_SHIELD_K := 60        # % of the missile shield taken off a frontal bolt
const BOLT_R_INF := 450          # bolt path half-width for a man ...
const BOLT_R_CAV := 900          # ... and for a horse
const STONE_BODY := 30
const STONE_R_INF := 600         # plough half-width
const STONE_R_CAV := 1000
const STONE_ROLL_LOSS := 5       # energy lost per metre ploughed
const STONE_KNOCK := 20          # knockdown % = energy left / 2 + this
const SWEEP_CAP := 12            # victims considered per shot
# A bursting stone (an ammunition kind with aoe 1; docs/DESIGN.md
# "Explosive stones: blast and knockback"): every man within its blast
# radius is struck, full damage at the centre falling to a third at the
# edge; survivors are thrown outward and lie down a while.
const BLAST_KNOCK_MAX := 30      # men knocked per landing (nearest first)
const BLAST_THROW := 1024        # thrown 1 m ...
const BLAST_THROW_RND := 1024    # ... plus up to 1 m more (sim RNG)
const BLAST_DOWN := 20           # down for 20 ticks ...
const BLAST_DOWN_RND := 11       # ... plus 0-10 (mean 2.5 s); riders and beasts half
const BLAST_DOWN_BIG := 10       # an elephant is not thrown: down 1 s
const FRIGHT_MAX := 200
const FRIGHT_DECAY := 1          # per tick: a stone's fright (60) lasts 6 s
const FX_CAP := 32               # view: recent stone impacts (not state)
# Refill (artillery): a battery told to refill takes REFILL_FULL ticks to
# settle into it (2 per tick back out), and while it is not back at 0 it
# cannot move, traverse or shoot; once in, crews at their engines bring up
# shots from the battery's finite reserve (m_refill ticks per shot at full
# crew, slower with fewer hands, nothing below the minimum crew).
const REFILL_FULL := 60          # 6 s to settle in, 3 s to get back out
# Ammunition kinds and fire (docs/DESIGN.md "Ammunition kinds", "Fire"):
# the kinds are rows of UnitTypes.AMMO (t_k_*); fire is one burning state
# on any wooden thing (a gate, a tower's engine, an engine, ladders, a ram,
# a wagon: g_burn / e_burn / q_burn ticks left), which loses FIRE_CHIP per
# mille of its full hit points every second while it burns.
const FIRE_TICKS := 300          # an object set alight burns 30 s (each new fire missile on it restarts it)
const FIRE_CHIP := 6             # per mille of its full hit points lost a second while burning (18 % a fire)
const FIRE_R := 3 * M            # a fire missile landing this near an engine, ladders, a ram or a wagon (a tower: its radius)
const BURN_UNIT := 40            # a unit a fire missile struck burns this many ticks ...
const BURN_DRAIN := 1            # ... losing this much morale a tick meanwhile
const LADDER_HP := 400           # ladder set hit points (fire)
# Resupply (docs/DESIGN.md "Resupply: foraging and the ammunition wagon").
# Ammunition wagons are equipment (EQ_WAGON, below) that a wagon unit's
# crew pulls (or any foot unit that takes it over). A missile unit or a
# battery told to refill (ORDER_REFILL) near a wagon settles REFILL_FULL
# ticks, then draws from the wagon's stock per kind (q_stock) until full or
# the stock is out; foraging (ORDER_FORAGE) in woods fills its men's
# quivers with the standard kind, slowly. Both go one missile at a time to
# the man next in turn (u_rptr) at WAGON_QUIVER / FORAGE_QUIVER ticks per
# full load of the whole unit (u_racc).
const WAGON_R := 15 * M          # a unit this near the wagon (its bounding box) may refill from it
const WAGON_QUIVER := 300        # ticks for a unit's whole load at the wagon (30 s)
const FORAGE_QUIVER := 1500      # ticks for a unit's whole quiver foraging in woods (2.5 min)
const WAGON_EXPOSED := 15        # % to-hit added to a blow on the flank or rear of men pulling a wagon
const HORSE_R := 3 * M           # missiles landing this near a wagon's horses ...
const HORSE_HIT := 30            # ... strike one this often (% of them)
# Camels and elephants (docs/DESIGN.md "Camels and elephants"); the numbers
# per beast are fields of its row (UnitTypes), these are the sim's own.
const AMOK_MOM := 60             # an amok beast tramples with this momentum ...
const AMOK_EVERY := 5            # ... each beast at most every this many ticks
const AMOK_EDGE := 60 * M        # it veers back from the map edges within this
const AMOK_VEER := 256           # each second it veers up to this either way (90 degrees)

# Terrain height (sim/terrain.gd builds the grid; docs/DESIGN.md "Terrain").
# Grades are Q12: 4096 = a rise of 1 m per metre (100%). Every effect below
# is skipped on a flat map (ter_on == 0), which then plays exactly as before.
const TER_SHIFT := 12            # height grid nodes 4 m apart
const TER_CELL := 4096
const TER_STEEP := 819           # 20%: steep ground
const TER_DOWN_FULL := 410       # downhill speed bonus is full at 10% ...
const TER_DOWN_BONUS := 50       # ... +5% (per mille)
const TER_DOWN_STEEP := 1000     # per mille slower per 100% of grade past steep, downhill
const TER_MIN_FAC := 300         # never below 30% of flat speed (per mille) ...
const TER_MIN_FAC_ART := 200     # ... 20% for artillery
const STEEP_DIS_GAIN := 4        # disorder per tick moving on steep ground (decay 2)
const STEEP_DIS_CAP := 30        # ... up to this (pikes lose the wall, spears the brace)
const PIKE_STEEP_DIS := 150      # % of disorder from hits on a pike block on steep ground
const MELEE_H_K := 80            # to-hit per mille per 100% grade from the striker down to his man
const MELEE_H_CAP := 20          # ... at most +-2% (reached at a 25% grade)
const CHG_H_K := 200             # charge impact % per 100% grade, rider above the victim
const CHG_H_MIN := 55            # uphill impact never below 55% ...
const CHG_H_MAX := 135           # ... downhill at most 135%
const MOM_UP_K := 300            # momentum cap lost per 100% uphill grade (100 -> 40 at 20%)
const MOM_DOWN := 410            # 10% downhill: momentum builds one point a tick faster
const RANGE_H_CAP := 30          # height changes missile range by at most 30%
const LOF_SKIP := 3 * M          # line of fire: ground this close to either end ignored
const LOF_STEP := 4 * M          # ... sampled every 4 m
const LOF_EYE := 1536            # flat weapons leave the hand / engine 1.5 m up ...
const LOF_BODY := 1024           # ... and are aimed at a man's body, 1 m up
const BOLT_BODY_LO := -205       # a bolt strikes a man when it passes between his feet ...
const BOLT_BODY_HI := 2048       # ... and 2 m above the ground under him
const STONE_UP_K := 400          # plough length % lost per 100% uphill grade (10% -> -40%)
const STONE_DOWN_K := 150        # ... gained downhill (10% -> +15%)
const STONE_PLOUGH_MIN := 150    # per mille of the flat plough, at least
const STONE_PLOUGH_MAX := 1300

# Woods (sim/mapgen.gd: tree density 0-3 per 4 m cell; docs/DESIGN.md
# "Battle maps"). Every rule is skipped on a map without trees or
# buildings (map_on == 0), which then plays exactly as before.
## Speed per mille by tree density [none, light, medium, dense], per class
## (infantry, pikes, missile, cavalry, artillery).
const VEG_SPEED := [[1000, 900, 780, 660], [1000, 860, 720, 580], [1000, 900, 790, 680],
	[1000, 800, 620, 460], [1000, 650, 450, 300]]
const VEG_DIS_GAIN: Array[int] = [0, 3, 4, 5]      # disorder per tick moving in woods (decay 2) ...
const VEG_DIS_CAP: Array[int] = [0, 30, 45, 60]    # ... up to this
const VEG_PIKE_FLOOR: Array[int] = [0, 0, 25, 40]  # a pike block in medium or dense woods cannot form
const VEG_MOM_CAP: Array[int] = [100, 80, 60, 40]  # cavalry momentum cap where the unit is
const URBAN_MOM_CAP := 40               # ... and in a settlement's streets (no run-up)
const VEG_IMPACT: Array[int] = [100, 85, 65, 45]   # charge impact % on a man standing in woods
const VEG_CAV_MELEE: Array[int] = [0, 5, 10, 15]  # riders in woods: to-hit lost striking, gained against them
const VEG_STOP_ARROW: Array[int] = [0, 20, 35, 50] # % of arrows landing in woods stopped by the trees
const VEG_STOP_JAV: Array[int] = [0, 10, 20, 30]   # ... javelins (flat: dense woods also block the line)
const VEG_STOP_STONE: Array[int] = [0, 15, 30, 45] # ... stones
const VEG_PLOUGH: Array[int] = [1000, 800, 600, 400]  # stone plough per mille in woods
const TREE_W: Array[int] = [0, 1, 2, 4]            # line of fire: tree depth per 4 m sample ...
const TREE_BLOCK := 8                   # ... a flat shot is blocked past this (8 m of dense woods)

# Settlements (city maps). Buildings, wall bodies and towers are impassable
# 2 m cells; the walkway is only for units placed on the wall; gates are
# passable unless closed. Units follow paths over a street graph.
const GATE_OPEN := 0
const GATE_CLOSED := 1
const GATE_BROKEN := 2
const GATE_ARMOUR := 20          # taken off each blow at a gate
const GATE_HACK_PCT := 25        # % of the rest that a gate takes per man per swing
const GATE_HACKERS := 10         # at most this many men at a gate
const GATE_REACH := 2 * M        # men this close to a closed gate's face hack at it
const GATE_BOLT := 80            # gate hp per bolt that hits it ...
const GATE_STONE := 360          # ... per stone
## Siege levers (docs/DESIGN.md "Siege equipment and wall towers"): static
## so tests/matchups.gd --tune can try values; the game never changes them.
static var WALL_COVER: Array[int] = [0, 25, 45, 70]  # % of missiles from below stopped by the battlements, by wall level (was 25 / 35 / 65)
static var WALL_RANGE_PCT: Array[int] = [0, 0, 15, 15]  # missile troops on a wall reach this % further at men below
const WALL_PARAPET := 614        # parapet top above the walkway (line of fire)
const CAPTURE_TICKS := 600       # attackers hold the plaza this long: the defenders break
const CAPTURE_CLEAR := 12 * M    # ... with no defender unit this far beyond the plaza
const CAPTURE_MEN := 10          # an attacking unit needs this many men to hold it
const PATH_MAX := 24             # waypoints per unit path
const TRAIL := 4                 # waypoints a unit's anchor passed, kept for its stragglers
const WP_REACH := 4 * M          # a waypoint counts as reached this close
const PATH_INF := 1 << 28
const SEARCH_CAP := 64           # settlement maps: a target search looks at most at this many men
const DIST_PER_TICK := 2         # street graph distance tables built per tick at most (the rest wait)
const DITCH_SPEED := 450         # per mille of the speed while crossing a ditch (foot only)
const STAIR_MAX := 400           # a stair move gives up waiting for stragglers after this long
const WALL_RG := 1229            # a unit on a wall stands in two ranks at most this far apart (1.2 m)
const WALL_SNAP := 14 * M        # a move onto wall / tower cells this near a stretch's walkway goes onto it
const WALL_JOIN := 26 * M        # stretches whose ends are this near (through a tower) are joined
const MAN_WALL_R := 60 * M       # "Man the wall": stretches this near the unit
const NAV_TOWER := 8             # passability bit of tower cells: the walkway runs through them (wall units only)
const NAV_WALK := 16             # ... and of the walkway itself (with MapGen.NAV_WALL; a stair has NAV_WALL only)
const CIT_GATE_PCT := 60         # a citadel's gate: % of the outer gates' hit points
const CIT_SIEGE := 1200          # the attackers 3:1 inside the walls this long: the town is lost ...
const CIT_SIEGE_LOSS := 6        # ... lose this much morale a second
const LAG_HOLD := 20 * M         # settlement maps: the anchor slows to a quarter while its men lag this far (+ half its depth)
const LAG_CUT := 8 * M           # ... and counts as cut off past this (+ half its depth) when not fighting
const REGROUP := 100             # ... for this long: the unit regroups where its men are
                                 # (crowds in a breach pile up in a few grid cells)
# Siege equipment and wall towers (docs/DESIGN.md "Siege equipment and wall
# towers"). Walls 2-3 gates shrug off swords; rams and artillery break them.
static var GATE_HACK_BY_WALLS: Array[int] = [25, 25, 1, 1]  # GATE_HACK_PCT by wall level
static var GATE_HP_PCT: Array[int] = [100, 100, 130, 130]   # gate hit points (% of MapGen.GATE_HP) by wall level
const RAM_REACH := 6 * M         # a ram's crew this close outside a closed gate's face works it ...
const RAM_MEN := 6               # ... at least this many of them ...
const RAM_WORK := 480            # ... man-ticks per blow (20 men: a blow every 2.4 s) ...
static var ROUT_INWARD := 1     # defenders routing inside the walls run to the inside of the shut gate farthest from the enemy (1), or toward their map edge, out by any way (0)
static var RAM_DMG := 160        # ... hit points per blow
static var TOWERS_MAX: Array[int] = [0, 0, 6, 8]          # bolt-thrower towers by wall level ...
static var TOWERS_STONE: Array[int] = [0, 0, 0, 2]        # ... and stone-thrower towers
const TOWER_SPACING := 40        # m between towers given engines (a gate's pair excepted)
const TOWER_AMMO_BLD := 5        # a city with this building (cdata "workshop", MapGen.B_WORKSHOP) ...
const TOWER_AMMO_PCT := 150      # ... loads its towers with this % of the shots
const TOWER_BOLT_DMG := 70       # tower hit points per bolt landing on a tower ordered at ...
const TOWER_STONE_DMG := 330     # ... per stone
const LADDER_SET := 5            # ladders in a set (one piece of equipment)
static var LADDER_TICKS: Array[int] = [0, 20, 30, 40]    # ticks per man up one ladder, by wall level
const LADDER_NEAR := 8 * M       # the anchor this close to the foot: the climb begins
const LADDER_AT := 3 * M / 2     # a man this near his ladder's foot, first in its queue, goes up when it is free
const LADDER_QSP := M            # a ladder's queue: two abreast (LADDER_QW apart along the wall), a man every this much back from the foot
const LADDER_QW := 1229          # ... the two files of a queue this far apart (0.6 m either side of the ladder)
const LADDER_QCOST := 1229       # a man choosing his ladder counts each man already in its queue as this much more way
const LADDER_STALL := 300        # men below, a ladder free and nobody at its foot this long: the climb is given up (all come down the ladders)
const LANES_MAX := 8             # most lanes a planted piece has (EQ_LANES)
const LADDER_GAP := 2560         # ladders this far apart along the wall
const UNBAR_MEN := 4             # ladder men this many at the inside of a closed gate ...
const UNBAR_TICKS := 150         # ... for this long open it
const ST_LADDER_GO := 5          # u_stair: marching to a ladder's foot ...
const ST_LADDER := 4             # ... climbing it (u_wall set, men go up a few at a time)
# Siege equipment objects (q_*: docs/DESIGN.md "Siege equipment as objects").
const EQ_LADDERS := 1            # a set of LADDER_SET ladders
const EQ_RAM := 2                # a battering ram
const EQ_WAGON := 3              # an ammunition wagon (q_tier: its UnitTypes.WAGONS row)
const EQ_TOWER := 4              # a rolling siege tower (the helepolis)
const EQ_STAKES := 5             # field works: a line of sharpened stakes (placed in the deployment)
const EQ_CALTROPS := 6           # ... a field of caltrops (hidden from the enemy until crossed)
const EQ_DITCH := 7              # ... a fortified camp's ditch (built by the scenario, "fortified")
const EQ_RAMPART := 8            # ... and its rampart: a low wall whose top is a fighting walk
const EQ_MANTLET := 9            # a mantlet: a wooden missile screen a foot unit carries and sets down
# What each kind of piece is, by EQ_* (index 0 unused); the sim reads these
# fields, never the kind (docs/DESIGN.md "Siege equipment as objects").
## Pieces with a roof: % of the arrows landing on the carriers near it stopped (0: none).
const EQ_ROOF: Array[int] = [0, 0, RAM_ROOF_PCT, RAM_ROOF_PCT, RAM_ROOF_PCT, 0, 0, 0, 0, MANTLET_CARRY_PCT]
## Arrows landing on the carriers this near it are stopped by its roof EQ_ROOF % of the time.
const EQ_ROOF_R: Array[int] = [0, 0, RAM_ROOF_R, RAM_ROOF_R, 8 * M, 0, 0, 0, 0, MANTLET_W]
## Full hit points (a wagon: its tier's).
const EQ_HP: Array[int] = [0, LADDER_HP, RAM_HP, 0, 2000, 400, 300, 0, 900, MANTLET_HP]
## Planted against a stretch, men cross it this many abreast (0: never planted) ...
const EQ_LANES: Array[int] = [0, LADDER_SET, 0, 0, 8, 0, 0, 0, 0, 0]
## ... the lanes this far apart along the wall ...
const EQ_LANE_GAP: Array[int] = [0, LADDER_GAP, 0, 0, 768, 0, 0, 0, 0, 0]
## ... a man up each lane every this many ticks (0: LADDER_TICKS by wall level) ...
const EQ_CLIMB: Array[int] = [0, 0, 0, 0, 16, 0, 0, 0, 0, 0]
## ... and only against walls of at least this level.
const EQ_WALLS: Array[int] = [0, 1, 0, 0, 2, 0, 0, 0, 0, 0]
## Carried: at most this pace (0: none) and this % of the carriers' walk ...
const EQ_PACE: Array[int] = [0, 0, RAM_WALK, 0, 62, 0, 0, 0, 0, 0]
const EQ_WALK_PCT: Array[int] = [0, LADDER_WALK_PCT, 100, 100, 100, 100, 100, 100, 100, 100]
## ... with fewer men than this (0: any number) proportionally slower (at least a quarter).
const EQ_MEN: Array[int] = [0, 0, 0, 0, 40, 0, 0, 0, 0, 0]
## Either side may take it up (else only the side it belongs to).
const EQ_ANY: Array[int] = [0, 0, 0, 1, 1, 0, 0, 0, 0, 1]
## Bolts and stones landing on it hit it.
const EQ_SHOT: Array[int] = [0, 0, 1, 1, 1, 0, 0, 0, 0, 1]
## Planted, it can still be set alight and hit (planted ladders are out of reach).
const EQ_EXPOSED: Array[int] = [0, 0, 0, 0, 1, 0, 0, 0, 0, 0]
## Planted, its middle stands this far out from the foot (its depth / 2).
const EQ_DEPTH2: Array[int] = [0, 0, 0, 0, 3072, 0, 0, 0, 0, 0]
## Enemy foot standing at it on the ground smash it.
const EQ_SMASH: Array[int] = [0, 0, 1, 0, 1, 0, 0, 0, 0, 0]
## A siege engine the defenders' towers and wall archers single out.
const EQ_FOCUS: Array[int] = [0, 0, 1, 0, 1, 0, 0, 0, 0, 0]
## Wall archers with a fire kind single out its carriers (docs/AI.md 15).
const EQ_FIRE_AT: Array[int] = [0, 0, 0, 0, 1, 0, 0, 0, 0, 0]
## Fire takes it (a fire missile near it sets it alight).
const EQ_BURN: Array[int] = [0, 1, 1, 1, 1, 1, 0, 0, 1, 1]
# Screens (docs/DESIGN.md "Mantlets"): standing on the ground (Q_GROUND)
# facing q_face, the piece shelters its side's (q_side) men in the
# rectangle behind it, EQ_SCREEN_W along its line by EQ_SCREEN_D deep, from
# missiles shot from in front of its line.
## % of arrows, sling stones and javelins about to strike a sheltered man stopped ...
const EQ_SCREEN: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, MANTLET_COVER_PCT]
## ... and of bolts (stones go over it or through it: none).
const EQ_SCREEN_BOLT: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, MANTLET_BOLT_PCT]
const EQ_SCREEN_W: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, MANTLET_W]
const EQ_SCREEN_D: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, MANTLET_D]
const MANTLET_COVER_PCT := 60    # a standing mantlet stops this % of the arrows, slings, javelins at the men behind it ...
const MANTLET_BOLT_PCT := 30     # ... and this % of the bolts
const MANTLET_CARRY_PCT := 40    # carried: the carriers within MANTLET_W of it are covered this often (its roof rule)
const MANTLET_HP := 600          # a plank screen: two stones (RAM_STONE_DMG) wreck it
const MANTLET_W := 6 * M         # its width along its line ...
const MANTLET_D := 6 * M         # ... and the depth behind it it shelters
const MANTLET_AHEAD := 2 * M     # at setup it stands this far before its unit's front
# Field works (docs/DESIGN.md "Field works and the fortified camp"): pieces
# fixed where they are put for the battle (Q_FIXED), an oriented rectangle
# q_len along the line (q_face: the way its front faces) by EQ_FW_DEPTH
# across; every man inside one is affected by these fields, never the kind.
## A field work (placed in the deployment or built by the scenario).
const EQ_FW: Array[int] = [0, 0, 0, 0, 0, 1, 1, 1, 1, 0]
## Its length along the line when placed (0: the scenario's) and its depth across.
const EQ_FW_LEN: Array[int] = [0, 0, 0, 0, 0, 20 * M, 10 * M, 0, 0, 0]
const EQ_FW_DEPTH: Array[int] = [0, 0, 0, 0, 0, 3 * M, 10 * M, 4 * M, 4 * M, 0]
## Its own side's men are hindered too (stakes and the ditch are in everyone's
## way; the owner knows where its caltrops lie and climbs its own rampart).
const EQ_OWN: Array[int] = [0, 0, 0, 0, 0, 1, 0, 1, 0, 0]
## Men crossing it move at this % of their pace: foot, and riders / beasts
## (stakes: foot pick their way through at half pace, a horse barely at all).
const EQ_SLOW_FOOT: Array[int] = [100, 100, 100, 100, 100, 50, 60, 45, 100, 100]
const EQ_SLOW_RIDE: Array[int] = [100, 100, 100, 100, 100, 25, 35, 30, 100, 100]
## Ticks an enemy takes to climb across its depth (0: no climb): the rampart,
## 4 m of steep earth bank in 5 s, a short ladder's pace with no ladder.
const EQ_CROSS_T: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 50, 0]
## Charge momentum a rider (horse, camel, elephant) loses each tick inside
## it: 100 stops a charge dead (stakes, the ditch, the rampart's bank).
const EQ_STOP: Array[int] = [0, 0, 0, 0, 0, 100, 25, 100, 100, 0]
## % of a man's full hit points he loses stepping into it: foot, riders,
## beasts (a big body); a charging rider (and his beast) that times
## (100 + momentum) / 100: impaled on the stakes at the gallop.
const EQ_DMG_FOOT: Array[int] = [0, 0, 0, 0, 0, 0, 6, 0, 0, 0]
const EQ_DMG_RIDE: Array[int] = [0, 0, 0, 0, 0, 5, 12, 3, 0, 0]
const EQ_DMG_BEAST: Array[int] = [0, 0, 0, 0, 0, 3, 8, 2, 0, 0]
## A charging rider stepping into it is thrown this % x momentum / 100 of the time.
const EQ_KNOCK: Array[int] = [0, 0, 0, 0, 0, 40, 0, 50, 0, 0]
## Hit points (its stock) used up by each man stepping into it (caltrops).
const EQ_USE: Array[int] = [0, 0, 0, 0, 0, 0, 1, 0, 0, 0]
## Hit points a tick each enemy foot soldier standing inside it hacks off
## (stakes pulled up; at most FW_HACKERS men at once; men crossing do not).
const EQ_HACK: Array[int] = [0, 0, 0, 0, 0, 1, 0, 0, 0, 0]
## Hidden from the enemy until one of its men steps into it (q_seen).
const EQ_HIDE: Array[int] = [0, 0, 0, 0, 0, 0, 1, 0, 0, 0]
## Height of the ground inside it (sim units): the ditch's floor, the
## rampart's fighting step (2 m: a wooden palisade on an earth bank, about
## half walls 1's 5 m walkway; a section burnt down leaves a gap: it is
## wrecked and none of its fields apply). The
## height rules (melee from above, a charge uphill, range from height)
## read it on any map.
const EQ_H: Array[int] = [0, 0, 0, 0, 0, 0, 0, -1536, 2048, 0]
## Its side's men standing on it: % of the missiles from men not on it
## stopped (half walls 1's battlements, WALL_COVER) ...
const EQ_COVER: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 12, 0]
## ... and % of their range more at men not on it (half walls 2-3's
## WALL_RANGE_PCT; walls 1 gives none, a rampart is a fighting platform).
const EQ_RANGE: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 8, 0]
const FW_HACKERS := 12           # men at a piece who hack at it at most ...
const FW_HACK_STILL := M / 32    # ... standing in it (moved less than this in the tick)
const Q_GROUND := 0              # lying where it was put down
const Q_CARRIED := 1             # carried by unit q_unit (at its anchor)
const Q_PLANTED := 2             # ladders against stretch q_seg (foot q_x, q_y; for the battle)
const Q_WRECKED := 3             # a ram smashed (artillery, defenders at it)
const Q_FIXED := 4               # a field work standing where it was put (for the battle)
const Q_STOWED := 5              # a field work its side has not placed (nothing on the field)
const RAM_CREW := 20             # men of the carrying unit who work the ram at most
const RAM_WALK := 123            # a unit carrying the ram walks at most this fast (1.2 m/s) (EQ_PACE) ...
const LADDER_WALK_PCT := 80      # ... one carrying ladders at this % of its walk; neither runs (EQ_WALK_PCT)
const CARRY_MELEE_PCT := 60      # a carrying unit's melee attack and defence (it defends poorly)
const PICK_R := 6 * M            # the anchor this close to a piece on the ground picks it up
const RAM_HP := 2500             # a ram's hit points ...
const RAM_BOLT_DMG := 70         # ... a bolt landing within RAM_HIT_R takes this, a stone ...
const RAM_STONE_DMG := 330
const RAM_HIT_R := 3 * M
const RAM_ROOF_R := 5 * M        # arrows landing on the carriers this near the ram ...
const RAM_ROOF_PCT := 70         # ... are stopped by its roof this often
const RAM_WRECK := 3             # hit points a tick per defender within ENGINE_NEAR of a ram on the ground

# Morale (0..1000).
const MORALE_MAX := 1000
# Morale is lost mainly through casualties: each death costs
# LOSS_PER_DEATH_TOTAL / start size, raised by up to RATE_K x the share of the
# unit killed recently (u_recent, per mille, decaying with a ~3 s time
# constant), so a fast slaughter breaks a unit sooner than a slow grind.
# The standalone flank / rear / charge penalties are deliberately small.
const MORALE_LOSS_PER_DEATH_TOTAL := 1200  # spread over the unit's start size
const MORALE_RATE_K := 3                   # x recent losses (per mille) / 1000
const RECENT_DECAY_SHIFT := 5              # u_recent loses 1/32 per tick
const MORALE_FLANK_HIT := 1                # per hit landing on the unit's flank
const MORALE_REAR_HIT := 2                 # per hit landing on the unit's rear
const MORALE_MISSILE_HIT := 0              # per missile wound (deaths count)
const MORALE_MISSILE_FLANK := 0            # per missile wound, flank or rear
const MORALE_CHARGE_FRONT := 1             # per soldier hit by a charge
const MORALE_CHARGE_FLANK := 2
const MORALE_CHARGE_REAR := 4
const MORALE_REFLECT := 2                  # rider thrown back by braced points
const MORALE_ROUTING_FRIEND := 5           # per routing friend nearby, per second
const MAX_ROUTING_FRIENDS := 2             # cap on friends counted
const ROUTING_FRIEND_RANGE := 30 * M
const MORALE_RECOVER := 2                  # per tick when not engaged
const UNDER_FIRE_TICKS := 30               # no recovery this long after a hit
const ROUT_THRESHOLD := 100
const WAVER := 250
const RALLY_THRESHOLD := 450
const RALLY_SAFE_RANGE := 50 * M
const MAX_ROUTS := 1                       # a unit rallies once; the next rout is final

# Battle end.
const TIME_LIMIT := 9000          # 15 minutes: undecided battles are a draw
const END_AFTER := 600            # pursuit continues 60 s after the decision

# Removal reasons.
const GONE_KILLED := 0
const GONE_WITHDRAWN := 1
const GONE_ROUTED := 2

# ---------------------------------------------------------------- state ---

var tick: int = 0
var seed_value: int = 0
var rng_state: int = 1
var field_w: int = 0
var field_h: int = 0
var ai_sides: PackedInt32Array = PackedInt32Array([0, 0])  # 1 = AI controls side
## AI skill level and personality per side (sim/ai_profile.gd: AIProfile.EASY ..
## SKILLED, CAUTIOUS .. AGGRESSIVE; scenario "ai_skill" / "ai_style"). Hashed
## when not the default (AVERAGE / BALANCED on both sides).
var ai_skill: PackedInt32Array = PackedInt32Array([1, 1])
var ai_style: PackedInt32Array = PackedInt32Array([1, 1])
var winner: int = -1  # -1 undecided, else winning side (2 = draw)
var decided_tick: int = -1
var ended: int = 0    # 1 once the result is final (pursuit over)

# Soldiers (struct of arrays).
var n: int = 0
var pos_x := PackedInt32Array()
var pos_y := PackedInt32Array()
var prev_x := PackedInt32Array()
var prev_y := PackedInt32Array()
var facing := PackedInt32Array()
var hp := PackedInt32Array()
var state := PackedInt32Array()
var cooldown := PackedInt32Array()
var unit_of := PackedInt32Array()
var slot_of := PackedInt32Array()
var target := PackedInt32Array()
var ammo := PackedInt32Array()
var chg := PackedInt32Array()        # cavalry: momentum 0..100 of this rider
var sammo := PackedInt32Array()      # of ammo[i], missiles of his unit's special kind (u_sk)
var struck := PackedInt32Array()     # cavalry: 1 once this rider made contact this charge

# Units (struct of arrays).
var n_units: int = 0
var u_side := PackedInt32Array()
var u_type := PackedInt32Array()
var u_cls := PackedInt32Array()
var u_count0 := PackedInt32Array()
var u_alive := PackedInt32Array()     # soldiers on the field
var u_state := PackedInt32Array()
var u_morale := PackedInt32Array()
var u_routs := PackedInt32Array()
var u_files := PackedInt32Array()
var u_ax := PackedInt32Array()      # formation anchor = front centre
var u_ay := PackedInt32Array()
var u_face := PackedInt32Array()
var u_order := PackedInt32Array()
var u_dx := PackedInt32Array()      # move destination (front centre)
var u_dy := PackedInt32Array()
var u_dface := PackedInt32Array()
var u_target := PackedInt32Array()
var u_run := PackedInt32Array()
var u_fire := PackedInt32Array()      # fire at will
var u_skirm := PackedInt32Array()     # skirmish mode
var u_slot_base := PackedInt32Array()
var u_contact := PackedInt32Array()
var u_fighting := PackedInt32Array()  # soldiers fighting last tick
var u_inreach := PackedInt32Array()  # of them, within reach (+INREACH_EXTRA) of their man
var u_settled := PackedInt32Array()   # every soldier at its slot and idle
var u_dirty := PackedInt32Array()     # slot offsets need recomputing
var u_cx := PackedInt32Array()        # centroid and bbox of living soldiers
var u_cy := PackedInt32Array()
var u_minx := PackedInt32Array()
var u_miny := PackedInt32Array()
var u_maxx := PackedInt32Array()
var u_maxy := PackedInt32Array()
var u_flee_x := PackedInt32Array()    # Q12 unit vector
var u_flee_y := PackedInt32Array()
var u_moved := PackedInt32Array()     # anchor distance moved this tick
var u_disorder := PackedInt32Array()  # 0..100, pikes/braced units lose formation
var u_formed := PackedInt32Array()    # pikes: formation intact (pike wall up)
var u_braced := PackedInt32Array()    # spears/pikes: braced against charges
var u_mom := PackedInt32Array()       # cavalry: unit momentum 0..100
var u_charge := PackedInt32Array()    # cavalry: 1 while a charge resolves rider by rider
var u_charge_t := PackedInt32Array()  # tick the charge made contact
var u_charge_left := PackedInt32Array()  # front-rank riders yet to make contact
var u_charge_act := PackedInt32Array()   # riders still riding in with momentum
var u_down := PackedInt32Array()      # soldiers knocked down
var u_ftarget := PackedInt32Array()   # missiles: unit currently shot at, -1 none
var u_fire_acc := PackedInt32Array()
var u_fire_ptr := PackedInt32Array()
var u_ammo := PackedInt32Array()      # missiles left in the unit
var u_hit_t := PackedInt32Array()     # last tick a missile wounded the unit
var u_charged_t := PackedInt32Array() # last tick the unit was hit by a charge
var u_killed := PackedInt32Array()
var u_recent := PackedInt32Array()    # share killed recently, per mille, decaying
var u_withdrawn := PackedInt32Array()
var u_routed_off := PackedInt32Array()
var u_att := PackedInt32Array()       # effective melee stats this tick
var u_def := PackedInt32Array()
var u_dmg := PackedInt32Array()
var u_reach := PackedInt32Array()
var u_nwalls := PackedInt32Array()    # enemy pike walls near the unit
var u_walls := PackedInt32Array()     # u * 4 + k -> pike unit
var u_ai := PackedInt32Array()        # battle AI: per-unit mode
var u_ai_t := PackedInt32Array()      # battle AI: tick the mode started
var u_ai_x := PackedInt32Array()      # battle AI scratch (cavalry: melee start tick)
var u_ai_y := PackedInt32Array()      # battle AI scratch (unit being flanked or staged on)
var u_eng0 := PackedInt32Array()      # artillery: first engine index
var u_neng := PackedInt32Array()      # artillery: engines (0 for other units)
var u_depl := PackedInt32Array()      # artillery: 0 packed .. deploy ticks = set up
var u_deploy := PackedInt32Array()    # artillery: wants to be set up (order)
var u_fright := PackedInt32Array()    # short-lived morale loss from artillery hits
var u_shelled_t := PackedInt32Array() # last tick an artillery shot hit the unit
var u_shelled_by := PackedInt32Array() # ... fired by this battery
var u_emove := PackedInt32Array()     # artillery: engines still rolling to their places
var u_refill := PackedInt32Array()    # artillery: told to refill (order)
var u_rprog := PackedInt32Array()     # artillery: 0 normal .. REFILL_FULL refilling
var u_reserve := PackedInt32Array()   # artillery: shots left in the baggage
var u_kills := PackedInt32Array()     # enemy soldiers killed by the unit's men (melee, charge, missiles, its engines)
var u_otype := PackedInt32Array()     # the unit's own type (its men: body, melee, morale); u_type is what it does now
var u_eg := PackedInt32Array()        # the engine group it works (-1 none)
var u_oammo := PackedInt32Array()     # its own missiles (u_ammo of a missile unit) while it works engines
var u_sk := PackedInt32Array()        # the special ammunition kind its own weapon carries (UT.AMMO row, -1 none; static)
var u_akind := PackedInt32Array()     # shoot the special kind (1) or the standard one (0): order field "akind"
var u_burn := PackedInt32Array()      # ticks its men burn on (fire missiles): morale drains
var u_forage := PackedInt32Array()    # foraging in woods (order field "forage")
var u_racc := PackedInt32Array()      # refill / forage work toward the next missile
var u_rptr := PackedInt32Array()      # ... the man next in turn
var u_scare := PackedInt32Array()     # horse scare: % of its charge and turn rate it keeps (0: not scared), set each second
var u_amok := PackedInt32Array()      # 1: a beast unit running amok (u_state U_ROUTING)
var u_calm := PackedInt32Array()      # ... ticks it has been alone (calms at its amok_calm)
var u_kill := PackedInt32Array()      # ticks until its drivers kill it (0: no Kill order)
var u_awe := PackedInt32Array()       # 1: inside an enemy's horse scare or fear aura this second (no recovery)
var u_led := PackedInt32Array()       # 1: inside a friendly general's command aura this second (docs/DESIGN.md "The general")
var u_cmdgone := PackedInt32Array()   # 1: this unit's command loss has struck the army (it routed or fell; once)
# War dogs (docs/DESIGN.md "War dogs"; _dog_arrays: hashed only in battles with
# handlers). A handler unit's pack is a unit of its own, made at setup after
# the scenario's units and the towers, kept off the field (U_KENNEL, no men
# alive, its dogs S_OFF with their hp) until released.
var u_pack := PackedInt32Array()      # handlers: their pack's unit (-1 none)
var u_hand := PackedInt32Array()      # a pack: its handlers' unit (-1: not a pack)
var u_kept := PackedInt32Array()      # a pack: dogs with the handlers (in the kennel)
var u_dogt := PackedInt32Array()      # a released pack: ticks with no enemy within its return_r
var u_ret := PackedInt32Array()       # a released pack: 1 running back to its handlers
var slot_soldier := PackedInt32Array()  # u_slot_base[u] + slot -> soldier
var off_x := PackedInt32Array()         # u_slot_base[u] + slot -> offset
var off_y := PackedInt32Array()

# Artillery engines (struct of arrays).
var n_eng: int = 0
var e_unit := PackedInt32Array()
var e_x := PackedInt32Array()
var e_y := PackedInt32Array()
var e_face := PackedInt32Array()
var e_hp := PackedInt32Array()
var e_state := PackedInt32Array()
var e_reload := PackedInt32Array()  # crew-ticks of work toward the next shot
var e_ammo := PackedInt32Array()
var e_crew := PackedInt32Array()    # crew working it this tick
var e_rwork := PackedInt32Array()   # crew-ticks of work toward the next shot refilled
var e_grp := PackedInt32Array()     # the engine group (a battery's engines stay together)
var e_sammo := PackedInt32Array()   # of e_ammo[e], shots of its group's special kind (eg_sk)
var e_burn := PackedInt32Array()    # ticks it burns on (fire)
var e_px := PackedInt32Array()      # view only: position last tick (not hashed)
var e_py := PackedInt32Array()
## Engine groups (docs/DESIGN.md "Artillery": engines are equipment, crews
## are men): the engines of one battery, in battery order. The unit working
## them (eg_op, -1 none: abandoned, neutral), and while abandoned the set-up
## progress, shots left in the baggage and facing they were left with; the
## battery they came with (eg_u0, static), their type (eg_type, static) and
## the side that last worked them (eg_side).
var n_eg: int = 0
var eg_e0 := PackedInt32Array()
var eg_ne := PackedInt32Array()
var eg_type := PackedInt32Array()
var eg_u0 := PackedInt32Array()
var eg_op := PackedInt32Array()
var eg_depl := PackedInt32Array()
var eg_res := PackedInt32Array()
var eg_face := PackedInt32Array()
var eg_side := PackedInt32Array()
var eg_sk := PackedInt32Array()     # the special ammunition kind its engines carry (-1 none; static)

# Battle AI, per side.
var ai_phase := PackedInt32Array([0, 0])
var ai_t := PackedInt32Array([0, 0])
var ai_hold := PackedInt32Array([-1, -1])  # tick the side began holding high ground, -1 not
var ai_gate := PackedInt32Array([-1, -1])  # settlement maps: the gate a side's assault is aimed at
var ai_cit := PackedInt32Array([0, 0])  # settlement maps: the defenders fell back into the citadel (1)
## Settlement maps, defenders' layout (sim/siege_ai.gd _read_gate): per side
## the gate the field points at that is not yet the read one (-1 none) and
## the tick it began to (hashed on settlement maps).
var ai_lay := PackedInt32Array([-1, 0, -1, 0])
var ai_prog := PackedInt32Array([0, 0, 0])  # settlement maps: deaths + gate damage seen, tick it last changed, all-out (1)
## Deliberate mistakes (sim/ai_profile.gd M_*): per side * AIProfile.N_MISTAKES
## + M_*, the tick before which that mistake cannot be made again (0 none).
## Only a level whose mistake chances are above 0 writes it; hashed with the
## AI profiles when they are not the default.
var ai_mist := PackedInt32Array()
## Skilled AI memory (sim/ai_profile.gd MU_* per unit, then SD_* per side):
## sized only when a side's profile asks for it (AIProfile.uses_mem), so it
## is empty, and hashes as nothing, in every other battle.
var ai_mem := PackedInt32Array()

# Terrain: node heights (sim units) on a 4 m grid covering the field, node
# gradients (Q12 grade), built once at setup from the scenario's terrain
# parameters (see sim/terrain.gd). Constant during the battle; ter_hash (MD5
# of the grid and parameters) is part of state_hash() from tick 0.
var ter_on: int = 0
var ter_nx: int = 2
var ter_ny: int = 2
var ter_h := PackedInt32Array()
var ter_gx := PackedInt32Array()
var ter_gy := PackedInt32Array()
var ter_hash: int = 0
var ter_info: Dictionary = {}   # generation parameters (view / telemetry)
var u_h := PackedInt32Array()   # unit: ground height under its centroid (refreshed each tick)
var _u_fac := PackedInt32Array()   # scratch: speed per mille along the unit's facing
var _u_steep := PackedInt32Array() # scratch: unit stands on steep ground

# Woods and settlements (sim/mapgen.gd). Static grids are rebuilt by setup()
# from the scenario (and hashed into ter_hash); gates, the capture clock,
# the units' paths and squeeze are state (hashed on such maps only).
var map_on: int = 0               # woods or buildings: the rules below apply
var veg_on: int = 0               # some trees
var veg := PackedByteArray()      # 4 m cells: MapGen.V_* bits, density in bits 0-1
var veg_w: int = 0
var veg_h: int = 0
var obs_on: int = 0               # buildings / walls
var obs := PackedByteArray()      # 2 m cells: MapGen.C_* kind (static)
var nav := PackedByteArray()      # 2 m cells: MapGen.NAV_* bits (gates change it)
var ob_w: int = 0
var ob_h: int = 0
var obs_c := PackedByteArray()    # 16 m cells: 1 if any obstacle in it (static)
var obs_cd := PackedByteArray()   # ... or in a neighbouring 16 m cell (melee reach checks)
var oc_w: int = 0
var oc_h: int = 0
var map_hash: int = 0
var map_info: Dictionary = {}     # generator output for the view (palette, city layout)
var city_on: int = 0
var city_def: int = -1            # defending side
var city_walls: int = 0
var city_level: int = 0
var wall_h: int = 0               # walkway height (sim units)
var wall_t: int = 0               # wall thickness
var build_h: int = 0              # building height (line of fire)
var plaza := PackedInt32Array([0, 0, 0, 0])  # x, y, half size, capture radius
var cap_t: int = 0                # ticks the attackers have held the plaza
var n_gates: int = 0
var g_x := PackedInt32Array()     # gate centre (on the wall line)
var g_y := PackedInt32Array()
var g_dir := PackedInt32Array()   # outward direction
var g_ox := PackedInt32Array()    # outside / inside points (paths, AI)
var g_oy := PackedInt32Array()
var g_ix := PackedInt32Array()
var g_iy := PackedInt32Array()
var g_hp := PackedInt32Array()    # centi-hp
var g_hp0 := PackedInt32Array()
var g_state := PackedInt32Array() # GATE_*
var g_hit_t := PackedInt32Array() # last tick it was damaged (view)
var g_bb := PackedInt32Array()    # 4 per gate: cell box i0, j0, i1, j1
var ws_x0 := PackedInt32Array()   # wall walkway segments (centre line), outward dir
var ws_y0 := PackedInt32Array()
var ws_x1 := PackedInt32Array()
var ws_y1 := PackedInt32Array()
var ws_dir := PackedInt32Array()
var ng_x := PackedInt32Array()    # street graph: nodes, gate of a gate node (-1), CSR edges
var ng_y := PackedInt32Array()
var ng_gate := PackedInt32Array()
var ng_e0 := PackedInt32Array()
var ng_to := PackedInt32Array()
var ng_w := PackedInt32Array()    # edge length in 1/8 m
var nav_epoch: int = 0            # bumped whenever a gate opens, closes or breaks
var _dist_cache: Dictionary = {}  # derived: graph distances to a node, per epoch
var _dist_epoch: int = -1         # (snapshotted with _dist_have: which tables exist decides who may plan)
var _dist_have := PackedInt32Array()  # nodes whose table this epoch holds, in build order (snapshotted: the budget depends on it)
var _dist_new: int = 0            # tables built this tick (at most DIST_PER_TICK)
var g_hw := PackedInt32Array()    # gate opening half width, m (static)
var g_cit := PackedInt32Array()   # 1: the citadel's gate (static)
var ws_e := PackedInt32Array()    # per segment end (seg * 2 + end) * 6: walkway point E, stair S, foot D (static)
var ws_fl := PackedInt32Array()   # segment flags MapGen.SEG_* (static)
var ws_nb := PackedInt32Array()   # per segment end (seg * 2 + end): the stretch end joined to it through a tower (seg * 2 + end, -1 none; static)
var ws_jx := PackedInt32Array()   # ... and the junction point (in the tower) between them (static)
var cmp := PackedInt32Array()     # settlement maps: each cell's piece of open ground with every gate shut (-1 none, -2 - g gate g's cells; static)
var n_cmp: int = 0
var g_cmp := PackedInt32Array()   # gate g * 4 + k: the pieces next to gate g (-1 none; static)
var _croot := PackedInt32Array()  # derived: each piece's joined piece with the gates as they are (for _croot_ep == nav_epoch)
var _croot_ep: int = -1
var ws_jy := PackedInt32Array()
var agora := PackedInt32Array([0, 0, 0])  # the main square (posts): x, y, half size (static)
var cit_x: int = 0                # the citadel (cit_r 0: none), static
var cit_y: int = 0
var cit_r: int = 0
var cit_gate: int = -1
var sea_on: int = 0               # the sea behind the city (static)
var sea_flee := PackedInt32Array()  # coast: where the defenders leave the field: x, y left, x, y right (static)
var city_ditch: int = 0           # a ditch round the walls (static)
var cit_siege: int = 0            # ticks the attackers have held the town 3:1 (the defenders lose heart)
# Per unit (on such maps; resized always, hashed only there).
var u_wall := PackedInt32Array()     # on the wall: walkway segment + 1 (0 = on the ground)
var u_sq := PackedInt32Array()       # files while squeezed through a street (0 = not)
var u_gtarget := PackedInt32Array()  # gate ordered at (-1 none): batteries shoot it, foot hack it
var u_pn := PackedInt32Array()       # path waypoints (0 = none / replan)
var u_pk := PackedInt32Array()       # current waypoint
var u_pgx := PackedInt32Array()      # goal the path was planned to
var u_pgy := PackedInt32Array()
var u_pep := PackedInt32Array()      # nav_epoch the path was planned in
var u_trn := PackedInt32Array()      # trail: waypoints the anchor passed (0..TRAIL), stragglers follow it
var u_stair := PackedInt32Array()    # 0; 1 going down a stair; 2 marching to a stair to go up; 3 climbing it
var u_sseg := PackedInt32Array()     # ... the wall segment and end (0 / 1) of that stair
var u_send := PackedInt32Array()
var u_st0 := PackedInt32Array()      # ... tick the stair move began
var u_wx := PackedInt32Array()       # going up: the walkway point it was ordered to
var u_wy := PackedInt32Array()
var u_lagt := PackedInt32Array()     # ticks its men have lagged far behind the anchor (regroup after REGROUP)
var u_stuck := PackedInt32Array()    # ticks it has wanted to get on (an order, a climb, men short of their places) and got nowhere
var u_srx := PackedInt32Array()      # ... its men's middle when it last got on (STUCK_DIST)
var u_sry := PackedInt32Array()
var u_sprog := PackedInt32Array()    # ... on a stair move, its men already on the level it goes to (more: it gets on)
var u_flow := PackedInt32Array()     # its places are flowed into the free space (1), else its formation's rectangle (0)
var u_flt := PackedInt32Array()      # ... the tick they were last laid out (an order: long ago)
var tr_x := PackedInt32Array()       # u * TRAIL + k, oldest first
var tr_y := PackedInt32Array()
var pth_x := PackedInt32Array()      # u * PATH_MAX + k
var pth_y := PackedInt32Array()
var _u_obs := PackedInt32Array()     # scratch: unit near obstacles this tick
var _lw_x := PackedInt32Array()      # scratch (by slot, base + s): where a climbing unit's man below waits (_ladder_step, every tick before use)
var _lw_y := PackedInt32Array()
var _fl_mark := PackedInt32Array()   # scratch (2 m cells): stamp << 8 | men placed there by the flow layout now running
var _fl_q := PackedInt32Array()      # scratch: its cells in the order visited
var _fl_stamp: int = 0
var _u_vfac := PackedInt32Array()    # scratch: woods speed factor (per mille) this tick

# Projectiles. A projectile is fired at (sx, sy) on tick t0 and lands at
# (x, y) on tick t1; it is only resolved on landing. Free slots have t1 = -1.
var pr_sx := PackedInt32Array()
var pr_sy := PackedInt32Array()
var pr_x := PackedInt32Array()
var pr_y := PackedInt32Array()
var pr_t0 := PackedInt32Array()
var pr_t1 := PackedInt32Array()
var pr_unit := PackedInt32Array()     # shooter unit
var pr_ty := PackedInt32Array()       # ... its missile type when it shot (a unit may take up or drop engines meanwhile)
var pr_tu := PackedInt32Array()       # unit aimed at
var pr_ak := PackedInt32Array()       # its ammunition kind (UT.AMMO row)
var pr_next := PackedInt32Array()     # bucket / free list link
var pr_bucket := PackedInt32Array()   # landing tick % PR_BUCKETS -> first
var pr_free: int = 0
var pr_count: int = 0

# Unit type stats copied out of UnitTypes for fast indexed access.
var t_cls := PackedInt32Array()
var t_attack := PackedInt32Array()
var t_defence := PackedInt32Array()
var t_armour := PackedInt32Array()
var t_shield := PackedInt32Array()
var t_mshield := PackedInt32Array()
var t_damage := PackedInt32Array()
var t_reach := PackedInt32Array()
var t_ranks := PackedInt32Array()
var t_mass := PackedInt32Array()
var t_walk := PackedInt32Array()
var t_run := PackedInt32Array()
var t_hp := PackedInt32Array()
var t_cooldown := PackedInt32Array()
var t_morale := PackedInt32Array()
var t_fsp := PackedInt32Array()
var t_rsp := PackedInt32Array()
var t_turn := PackedInt32Array()
var t_brace := PackedInt32Array()
var t_vs_cav := PackedInt32Array()
var t_charge := PackedInt32Array()
var t_sec_att := PackedInt32Array()
var t_sec_def := PackedInt32Array()
var t_sec_dmg := PackedInt32Array()
var t_sec_reach := PackedInt32Array()
var t_m_range := PackedInt32Array()
var t_m_dmg := PackedInt32Array()
var t_m_ap := PackedInt32Array()
var t_m_ammo := PackedInt32Array()
var t_m_reload := PackedInt32Array()
var t_m_spread := PackedInt32Array()
var t_m_spread0 := PackedInt32Array()
var t_m_speed := PackedInt32Array()
var t_m_arc := PackedInt32Array()
var t_skirm := PackedInt32Array()
var t_m_vuln := PackedInt32Array()
var t_m_down := PackedInt32Array()
var t_m_spen := PackedInt32Array()  # % of the target's missile shield its missiles go through (javelins)
var t_m_lead := PackedInt32Array()
var t_m_long := PackedInt32Array()
var t_crew := PackedInt32Array()
var t_crew_min := PackedInt32Array()
var t_m_kind := PackedInt32Array()
var t_m_min := PackedInt32Array()
var t_m_pierce := PackedInt32Array()
var t_m_plough := PackedInt32Array()
var t_m_blast := PackedInt32Array()
var t_m_fear := PackedInt32Array()
var t_arc := PackedInt32Array()
var t_traverse := PackedInt32Array()
var t_deploy := PackedInt32Array()
var t_e_hp := PackedInt32Array()
var t_climb := PackedInt32Array()
var t_m_hgain := PackedInt32Array()
var t_m_apex := PackedInt32Array()
var t_m_reserve := PackedInt32Array()
var t_m_refill := PackedInt32Array()
var t_fixed := PackedInt32Array()
var t_m_ak := PackedInt32Array()
var t_mount := PackedInt32Array()
var t_acc := PackedInt32Array()
var t_body_r := PackedInt32Array()
var t_crew_sh := PackedInt32Array()
var t_woods := PackedInt32Array()
var t_tr_n := PackedInt32Array()
var t_tr_r := PackedInt32Array()
var t_tr_pct := PackedInt32Array()
var t_crush := PackedInt32Array()
var t_scare_r := PackedInt32Array()
var t_scare_pct := PackedInt32Array()
var t_scare_mor := PackedInt32Array()
var t_fear_r := PackedInt32Array()
var t_fear_h := PackedInt32Array()
var t_fear_f := PackedInt32Array()
var t_burn_pct := PackedInt32Array()
var t_amok := PackedInt32Array()
var t_amok_r := PackedInt32Array()
var t_amok_calm := PackedInt32Array()
var t_kill_delay := PackedInt32Array()
var t_gate_w := PackedInt32Array()
var t_gate_pct := PackedInt32Array()
var t_cmd_r := PackedInt32Array()
var t_cmd_mor := PackedInt32Array()
var t_cmd_rally := PackedInt32Array()
var t_cmd_loss := PackedInt32Array()
var t_cmd_loss_r := PackedInt32Array()
var t_pack_n := PackedInt32Array()
var t_pack_type := PackedInt32Array()
var t_pack_r := PackedInt32Array()
var t_return_r := PackedInt32Array()
var t_return_t := PackedInt32Array()
var t_nobreak := PackedInt32Array()
var t_scare_am := PackedInt32Array()
var t_as_cav := PackedInt32Array()
var t_chase := PackedInt32Array()
var t_rider := PackedInt32Array()     # derived: builds charge momentum (cavalry, or mounted with a charge)
var t_hit_r := PackedInt32Array()     # derived: a missile landing this near strikes the man (horse, body)
# Beasts in this battle (static, set up from the units: not hashed).
var big_on: int = 0                   # some unit has a big body (body_r): blows measured to its edge
var aura_src := PackedInt32Array()    # units with a horse scare, a fear aura or a command aura
var _hit_rmax: int = HIT_R_CAV        # widest hit radius of any type
var stat_scared: int = 0              # unit-seconds of horses scared
var stat_feared: int = 0              # unit-seconds in a fear aura
var stat_cmd: int = 0                 # unit-seconds in a friendly command aura
var stat_cmd_rally: int = 0           # router-seconds of the command rally bonus
var stat_cmd_falls: int = 0           # generals routed or fallen (the loss struck)
var stat_scare_hits: int = 0          # horse charges into a scaring unit
var stat_crush: int = 0               # impacts that went through braced points
var stat_amok: int = 0                # beast units gone amok
var stat_trampled: int = 0            # men trampled by amok beasts ...
var stat_trample_ff: int = 0          # ... of the beasts' own side
var stat_calmed: int = 0              # amok beasts calmed (alone long enough)
var stat_beast_killed: int = 0        # beasts killed by their drivers
var stat_beast_gate: int = 0          # gate damage by beasts
var dog_on: int = 0                   # some unit carries a war dog pack (static)
var stat_released: int = 0            # packs released
var stat_absorbed: int = 0            # packs back with their handlers
var stat_dog_hunt: int = 0            # packs that went for the nearest enemy on their own
# Ammunition kinds (UnitTypes.AMMO, UnitTypes.AMMO_FIELDS order).
var t_k_base := PackedInt32Array()
var t_k_share := PackedInt32Array()
var t_k_dmg := PackedInt32Array()
var t_k_obj := PackedInt32Array()
var t_k_ap := PackedInt32Array()
var t_k_pierce := PackedInt32Array()
var t_k_range := PackedInt32Array()
var t_k_rate := PackedInt32Array()
var t_k_fear := PackedInt32Array()
var t_k_blast := PackedInt32Array()
var t_k_fire := PackedInt32Array()
var t_k_aoe := PackedInt32Array()

# Spatial grid, one per side so target search only walks enemies.
var grid_w: int = 0
var grid_h: int = 0
var grid_head0 := PackedInt32Array()
var grid_head1 := PackedInt32Array()
var blk_n0 := PackedInt32Array()    # settlement maps: side-0 men in contact per 16 m block (scratch, rebuilt each tick)
var blk_n1 := PackedInt32Array()
var blk_w: int = 0
var _enemy_bn := PackedInt32Array()  # scratch: the block counts of the enemies of the unit being moved
var grid_next := PackedInt32Array()

# Orders waiting for their tick. Each is a Dictionary of ints.
var pending_orders: Array = []
var _order_seq: int = 0

# Scratch (not state): soldiers to take off the field after a unit's loop.
var _rm := PackedInt32Array()
var _rm_why := PackedInt32Array()
var _wall_params := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var _sw_v := PackedInt32Array()   # sweep hits: soldier, or -(engine + 1)
var _sw_a := PackedInt32Array()   # ... distance along the path
var _sw_l := PackedInt32Array()   # ... signed distance across it
var _sw_n: int = 0
var _hit_units := PackedInt32Array([-1, -1, -1, -1])  # units hit by one shot

# Diagnostics (not part of the hashed state).
var stat_attacks: int = 0
var stat_searches: int = 0
var stat_grid_soldiers: int = 0
var stat_shots: int = 0
var stat_missile_hits: int = 0
var stat_impacts: int = 0
var stat_reflects: int = 0
var stat_reflects_aimed: int = 0  # ... of which the unit's ordered target
## Diagnostics: soldier -> 1 once he delivered a charge impact (or was
## thrown back by braced points). Not hashed, never read by the sim.
var dbg_impacted := PackedInt32Array()
var stat_knockdowns: int = 0
## Diagnostics: kills by cause [melee frontal, melee flank/rear/down,
## charge impact, missile, artillery].
var stat_kills := PackedInt32Array([0, 0, 0, 0, 0])
## ... per side of the men killed: side * 5 + cause (not hashed).
var stat_kside := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
## ... of those, per side of the men killed, killed by their own side
## (friendly fire: not in anyone's u_kills). Not hashed.
var stat_ff := PackedInt32Array([0, 0])
var stat_epick: int = 0         # engine groups picked up
var stat_edrop: int = 0         # ... dropped (ordered)
var stat_parting: int = 0          # free blows at riders / soldiers turning away
var stat_impact_blocked: int = 0   # charge impacts taken on a formed front's shields
## Battle AI decisions by unit mode (BattleAI.A_*), plus [8] army withdrawals,
## [12] holds of high ground, [13] missile / artillery slots moved onto a
## rise, [14] deployments shifted to higher ground.
var stat_ai := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
## Per-competency AI counters, side * AIProfile.N_COUNTERS + AIProfile.C_*
## (docs/AI.md 6: flank hits, pull-outs, units saved, spear responses,
## missiles caught, ammunition left at rout ...). Not hashed, never read by
## the sim or the AI.
var stat_aic := PackedInt32Array()
## Diagnostics for stat_aic: per unit, the tick enemy cavalry first came
## within a spear unit's response radius (-1 none near). Never read by a
## decision.
var dbg_cav_seen := PackedInt32Array()
var stat_bolts: int = 0        # bolts fired
var stat_stones: int = 0       # stones fired
var stat_art_victims: int = 0  # soldiers struck by artillery
var stat_art_kills: int = 0
var stat_deploys: int = 0      # batteries finished setting up
var stat_packs: int = 0        # batteries finished packing up
var stat_wrecked: int = 0      # engines wrecked
var stat_abandoned: int = 0    # engines abandoned
var stat_engine_hits: int = 0  # shots that struck an engine
## Terrain diagnostics (not hashed): melee blows with a height bonus for the
## higher man / against the lower, charge impacts downhill / uphill, shots
## and targets refused for want of a line of fire, unit-ticks slowed uphill,
## shots whose range was stretched by height, stones whose plough was
## shortened uphill, bolts stopped by the ground, steep-ground disorder.
var stat_h_melee: int = 0
var stat_charge_down: int = 0
var stat_charge_up: int = 0
var stat_lof_blocked: int = 0
var stat_slow_up: int = 0
var stat_range_up: int = 0
var stat_plough_short: int = 0
var stat_bolt_ground: int = 0
var stat_steep_dis: int = 0
var stat_refills: int = 0        # batteries that settled into refilling
var stat_refilled: int = 0       # shots brought up from the baggage
var stat_refill_broken: int = 0  # refills broken off by melee or rout
## Woods and settlements diagnostics (not hashed): unit-ticks slowed by trees,
## disorder from moving in woods, missiles stopped by trees, flat shots
## blocked by woods or walls, missiles stopped by the battlements, charge
## impacts weakened by trees, paths planned, men stopped by an obstacle,
## squeezes, gate damage by hacking / artillery (hp), gates closed / opened /
## broken, plaza captures.
var stat_veg_slow: int = 0
var stat_veg_dis: int = 0
var stat_veg_stop: int = 0
var stat_tree_lof: int = 0
var stat_obs_lof: int = 0
var stat_wall_cover: int = 0
var stat_veg_impact: int = 0
var stat_paths: int = 0
var stat_clamp: int = 0
var stat_squeeze: int = 0
var stat_gate_hack: int = 0
var stat_gate_art: int = 0
var stat_gate_close: int = 0
var stat_gate_open: int = 0
var stat_gate_broken: int = 0
var stat_capture: int = 0
var stat_stair_down: int = 0      # wall units ordered down a stair
var stat_unreach: int = 0         # unit-ticks attacking a unit out of reach (to the gate / into range)
var stat_stair_up: int = 0        # units that climbed onto a wall
var stat_stair_rout: int = 0      # wall units that routed off by a stair
var stat_ditch: int = 0           # unit-ticks crossing a ditch
var stat_sea_exit: int = 0        # defenders who left a coast map along the shore
var stat_cit_siege: int = 0       # defender unit-seconds of morale lost with the town lost
var stat_regroup: int = 0         # units that regrouped where their cut-off men were
## View only (not state, never read by the sim): ring of recent stone
## impacts for the impact marks: x, y, flight direction (Q12), tick.
var fx_x := PackedInt32Array()
var fx_y := PackedInt32Array()
var fx_dx := PackedInt32Array()
var fx_dy := PackedInt32Array()
var fx_t := PackedInt32Array()
var fx_head: int = 0
## Deployment phase (section at the end of the file). Hashed only when the
## scenario has one (dep_on), so battles without it hash as before.
var phase: int = PHASE_BATTLE
var dep_on: int = 0
var dep_ticks: int = 0      # length of the countdown (ticks)
var dep_left: int = 0       # ticks left while deploying
var dep_need: int = 0       # bit per player who must be ready (0: nobody: ends at once)
var dep_ready: int = 0      # bit per player who is ready
var dep_z := PackedInt32Array()  # zones, 6 per zone: side, kind (DZ_*), x0, y0, x1, y1 (sim units)
var dep_out: int = -1       # settlement maps: the attackers' piece of open ground
## Battle time limit (ticks; scenario "time_limit" in seconds, absent = 900).
## Hashed only when not the default.
var time_limit: int = TIME_LIMIT
## Siege equipment and wall towers (section "siege" at the end). Hashed only
## when the battle has any (sg_on), so battles without them hash as before.
var sg_on: int = 0
var u_carry := PackedInt32Array()   # per unit: the piece of siege equipment it carries (-1 none)
var u_pick := PackedInt32Array()    # ... the piece it is going to pick up (an order field; -1 none)
var u_lq := PackedInt32Array()      # ... the ladder set it goes up / came up by (-1 none)
var u_lfx := PackedInt32Array()     # ladders: the foot (outside the wall) it climbs from
var u_lfy := PackedInt32Array()
var u_lacc := PackedInt32Array()    # the ram's work toward the next blow
var u_trad := PackedInt32Array()    # tower engines: the tower's radius (static)
var g_unbar := PackedInt32Array()   # per gate: ticks ladder men have stood unbarring it
var g_burn := PackedInt32Array()    # per gate: ticks it burns on (fire)
## Some unit or engine carries a kind that sets things alight (set up once).
var fire_on: int = 0
## Siege equipment objects (the attackers' ladder sets and rams), in index
## order: kind (EQ_*), where it is (the foot of planted ladders), state
## (Q_*), the unit carrying it, the stretch planted at (-1), the walkway
## point above planted ladders, hit points (a ram), the climb's work toward
## the next man up (planted ladders), the side it belongs to.
var n_eq: int = 0
var q_kind := PackedInt32Array()
var q_x := PackedInt32Array()
var q_y := PackedInt32Array()
var q_state := PackedInt32Array()
var q_unit := PackedInt32Array()
var q_seg := PackedInt32Array()
var q_wx := PackedInt32Array()
var q_wy := PackedInt32Array()
var q_hp := PackedInt32Array()
var q_lt := PackedInt32Array()       # q * LANES_MAX + k: the tick lane k of planted piece q takes its next man up
var q_side := PackedInt32Array()
var q_burn := PackedInt32Array()    # ticks it burns on (fire)
var q_tier := PackedInt32Array()    # a wagon: its UnitTypes.WAGONS row (-1 not a wagon)
var q_hn := PackedInt32Array()      # ... horses alive
var q_hhp := PackedInt32Array()     # ... the lead horse's hit points
## A wagon's stock: q * UT.AMMO.size() + kind (shots / missiles of each kind).
var q_stock := PackedInt32Array()
var wag_h: int = 0                  # wagon horses alive (all wagons)
## Field works (EQ_FW pieces; section "field works" at the end): hashed
## only when the battle has any (fw_on), so battles without them hash as
## before.
var fw_on: int = 0
var fwh_on: int = 0                 # some field work has a height (a camp's ditch and rampart; static)
var q_face := PackedInt32Array()    # a field work: the way its front faces (angle)
var q_len := PackedInt32Array()     # ... its length along the line (sim units)
var q_seen := PackedInt32Array()    # ... bit per side that knows where it is (caltrops: the enemy once one of its men stepped in)
var u_fws := PackedInt32Array()     # per unit: % of its pace its men in field works had last tick (100 none): its anchor keeps to it ...
var u_fwc := PackedInt32Array()     # ... and to this step a tick (a rampart's climb; 0 none)
## Mantlets (EQ_SCREEN pieces; section "mantlets" at the end): the battle
## has some (set up once). Their facing (q_face) is hashed only then, so
## battles without them hash as before.
var mt_on: int = 0
var stat_mantlet_cover: int = 0     # missiles stopped by a standing mantlet (not hashed)
var stat_fw_cross: int = 0          # men stepping into a field work
var stat_fw_stop: int = 0           # rider-ticks a field work took a charge's momentum
var stat_fw_dmg: int = 0            # hit points field works took off men
var stat_fw_kills: int = 0          # men killed by them
var stat_fw_knock: int = 0          # charging riders thrown at them
var stat_fw_hack: int = 0           # hit points hacked off stakes
var stat_fw_cover: int = 0          # missiles stopped by a rampart's cover
var stat_fw_climb: int = 0          # man-ticks climbing a rampart
var stat_refill_shots: int = 0      # missiles and shots drawn from wagons
var stat_forage: int = 0            # missiles made foraging
var stat_horses_down: int = 0       # wagon horses shot down
var stat_wagon_taken: int = 0       # wagons taken over by another unit
var stat_pickups: int = 0           # pieces picked up
var stat_drops: int = 0             # ... put down (ordered, routing, the gate broken)
var stat_planted: int = 0           # ladder sets planted against a wall
var stat_ram_wrecked: int = 0
var stat_stw_planted: int = 0       # siege towers planted against a wall
var stat_stw_up: int = 0            # men across a siege tower onto the wall
var stat_stw_wrecked: int = 0       # siege towers wrecked (burnt, smashed, shot)
var stat_stw_taken: int = 0         # siege towers taken up by the other side
var stat_ladder_up: int = 0         # men up a ladder
var stat_ladder_done: int = 0       # units wholly up
var stat_flow: int = 0              # flowed layouts of a unit's places
var stat_anchor_kept: int = 0       # anchor steps kept off a wall or a house
var stat_unstick := PackedInt32Array([0, 0, 0, 0])  # stuck releases: places laid afresh, moves ended near, ways replanned, regroups
var stat_ladder_cut: int = 0        # climbs ended with men below (a move outward, the set gone, nobody coming to a free ladder): all came down
var stat_stuck_max: int = 0         # longest u_stuck any unit reached (ticks)
var stat_stuck_u := PackedInt32Array()  # ... per unit (its longest)
var stat_stuck_t := PackedInt32Array()  # ... per unit, ticks stuck in all
var stat_ak_shots: int = 0          # missiles and shots of a special ammunition kind
var stat_ignite: int = 0            # things set alight (gates, engines, equipment)
var stat_burnt: int = 0             # ... burnt down (a gate broken, an engine wrecked, a piece wrecked)
var stat_fire_dmg: int = 0          # hit points burnt off them
var stat_blast: int = 0             # men struck inside the extra blast of a bursting stone (aoe: every man in it)
var stat_blast_knock: int = 0       # men thrown / downed by a bursting stone
var stat_blast_down: int = 0        # ... their down ticks in all
var stat_blast_held: int = 0        # ... throws blocked (a wall, a building, a walk's edge): only downed
var stat_unit_burn: int = 0         # units set burning
var stat_ram_blows: int = 0
var stat_unbar: int = 0             # gates opened from inside
var stat_tower_hits: int = 0        # shots that struck a tower
var stat_towers_down: int = 0       # towers silenced (engine wrecked)
var stat_tower_kills: int = 0       # men killed by the towers' engines

# Units do not pass through each other (docs/DESIGN.md "Unit blocking and
# street fights"). Each tick the footprints of the ready units on the
# ground (their formation rectangle, clipped to where their men are) are
# marked in 4 m cells per side (the soldier grid's cells); an anchor may not
# step into an enemy's footprint (it steers round where there is room, else
# stops there and its men fight), passes through friends at half speed, and
# an attacking unit queues behind friends already fighting its target.
const OCC_FRONT := M              # a footprint reaches this far ahead of the anchor ...
const OCC_PAD := M / 2            # ... this far beyond the outer files and the rear rank
const OCC_MIN := 2 * M            # ... half extents at least this (a thin line still covers a cell)
const OCC_QUEUE := 60 * M         # friends fighting this near the box of the unit we attack are the line we queue behind
const OCC_CORNER := 8 * M         # front corners probed at most this far either side of the anchor
const DODGE: Array[int] = [85, 171]  # steering angles tried when blocked (30, 60 degrees: still getting on)
const DODGE_LOOK := 4 * M         # ... each looked along this far (a cell): room to go round, not a sidestep
const BLK_FRIEND := 1             # u_blk: passing through a friend (half speed)
const BLK_QUEUE := 2              # ... waiting behind friends fighting its target
const BLK_ENEMY := 3              # ... stopped at an enemy's footprint (its men fight)
# Units flow into the space (docs/DESIGN.md "Units flow into the space"),
# maps with buildings or walls only.
const STUCK_DIST := 2 * M         # u_stuck: a unit that wants to get on and whose men's middle has not moved this far ...
const STUCK_CYCLE := 150         # stuck release (_stuck_release), once per this many ticks of u_stuck: ...
const STUCK_FLOW := 50            # ... at this count its places are laid out afresh (flowed round what cuts them) ...
const STUCK_ROUTE := 100          # ... at this one its way is planned again (and kept while it is stuck: no replanning after a moving goal) ...
                                  # ... and at the cycle's end it regroups where its men are (_regroup) and goes on from there
const STUCK_NEAR := 8 * M         # a move stuck this near its destination (STUCK_ROUTE ticks) is over: it stands where it got to
const FLOW_EVERY := 10            # flowed places are laid out again this often (and on an order)
const FLOW_AHEAD := 4 * M         # ... reach at most this far ahead of the anchor
const FLOW_PACK := 125            # ... men pack in them to this % of their formation's density
const FLOW_CELLS := 160           # ... a layout visits at most this many 2 m cells
var u_blk := PackedInt32Array()   # what the anchor met this tick (BLK_*, 0 nothing)
var u_dodge := PackedInt32Array() # the side it steers round an obstacle (-1 / 1, 0 none)
var occ0 := PackedInt32Array()    # derived (rebuilt every other tick, kept in snapshots): side 0's footprints per 4 m cell:
var occ1 := PackedInt32Array()    # units | fighting units << 8 | (first unit + 1) << 16; side 1's
var _blk_u: int = -1              # scratch: the unit an anchor probe met
var _placing := PackedInt32Array() # scratch: units placed by this tick's orders (they do not refuse each other)
var stat_blocked: int = 0         # unit-ticks an anchor stopped at an enemy
var stat_queued: int = 0          # unit-ticks waiting behind fighting friends
var stat_pass: int = 0            # unit-ticks passing through friends
var stat_dodge: int = 0           # unit-ticks steering round a unit


# ---------------------------------------------------------------- setup ---

## scenario = {
##   "width_m": int, "height_m": int,
##   "ai_sides": [side, ...],
##   "ai_skill": [side 0, side 1], "ai_style": [side 0, side 1]   # optional AI
##     profiles (sim/ai_profile.gd; default AVERAGE / BALANCED),
##   "units": [{"side", "type", "count", "x_m", "y_m", "facing", "files", optional
##     "wall", "morale_pct" (starts with that % of its morale)}, ...],
##   "orders": [order, ...]   # optional scripted orders (test scenarios)
## }  x_m/y_m is the front centre of the unit in metres.
func setup(scenario: Dictionary, p_seed: int) -> void:
	seed_value = p_seed
	rng_state = ((p_seed & 0x7FFFFFFF) * 48271 + 0x2545F491) & 0xFFFFFFFF
	if rng_state == 0:
		rng_state = 0x1234567
	tick = 0
	winner = -1
	decided_tick = -1
	ended = 0
	pending_orders = []
	_order_seq = 0
	field_w = int(scenario["width_m"]) * M
	field_h = int(scenario["height_m"]) * M
	ai_sides = PackedInt32Array([0, 0])
	for s in scenario.get("ai_sides", []):
		ai_sides[int(s)] = 1
	ai_skill = PackedInt32Array([AIProfile.AVERAGE, AIProfile.AVERAGE])
	ai_style = PackedInt32Array([AIProfile.BALANCED, AIProfile.BALANCED])
	var sk: Array = scenario.get("ai_skill", [])
	var sy: Array = scenario.get("ai_style", [])
	for s in mini(sk.size(), 2):
		ai_skill[s] = clampi(int(sk[s]), AIProfile.EASY, AIProfile.SKILLED)
	for s in mini(sy.size(), 2):
		ai_style[s] = clampi(int(sy[s]), AIProfile.CAUTIOUS, AIProfile.AGGRESSIVE)
	stat_aic = PackedInt32Array()
	stat_aic.resize(2 * AIProfile.N_COUNTERS)
	stat_aic.fill(0)
	ai_phase = PackedInt32Array([0, 0])
	ai_t = PackedInt32Array([0, 0])
	ai_hold = PackedInt32Array([-1, -1])
	ai_gate = PackedInt32Array([-1, -1])
	ai_prog = PackedInt32Array([0, 0, 0])
	ai_cit = PackedInt32Array([0, 0])
	ai_lay = PackedInt32Array([-1, 0, -1, 0])
	ai_mist = PackedInt32Array()
	ai_mist.resize(2 * AIProfile.N_MISTAKES)
	ai_mist.fill(0)
	_dist_new = 0
	_setup_terrain(scenario.get("terrain", {}), p_seed)

	_load_types()

	time_limit = maxi(int(scenario.get("time_limit", TIME_LIMIT / TICKS_PER_SECOND)), 60) * TICKS_PER_SECOND
	var units: Array = scenario["units"]
	var towers := _siege_towers(scenario)
	if not towers.is_empty():
		# The city's tower engines come after the scenario's own units.
		units = units.duplicate()
		units.append_array(towers)
	# War dogs: each handler unit's pack, a unit of its own after these
	# (kept with its handlers until released).
	var packs := _dog_packs(units)
	dog_on = 1 if not packs.is_empty() else 0
	if dog_on != 0:
		units = units.duplicate()
		units.append_array(packs)
	n_units = units.size()
	var total := 0
	n_eng = 0
	n_eg = 0
	for ud in units:
		total += int(ud["count"])
		var ne0 := _engines_for(int(ud["type"]), int(ud["count"]))
		n_eng += ne0
		if ne0 > 0:
			n_eg += 1
	n = total
	for arr in _engine_arrays():
		arr.resize(n_eng)
		arr.fill(0)
	for arr in _egroup_arrays():
		arr.resize(n_eg)
		arr.fill(0)
	e_px.resize(n_eng)
	e_py.resize(n_eng)
	_sw_v.resize(SWEEP_CAP)
	_sw_a.resize(SWEEP_CAP)
	_sw_l.resize(SWEEP_CAP)
	for arr in [fx_x, fx_y, fx_dx, fx_dy, fx_t]:
		arr.resize(FX_CAP)
		arr.fill(0)
	fx_t.fill(-1000)
	fx_head = 0

	for arr in _soldier_arrays():
		arr.resize(n)
		arr.fill(0)
	for arr in _unit_arrays():
		arr.resize(n_units)
		arr.fill(0)
	u_walls.resize(n_units * 4)
	u_walls.fill(-1)
	dbg_cav_seen.resize(n_units)
	dbg_cav_seen.fill(-1)
	ai_mem = PackedInt32Array()
	if AIProfile.uses_mem(ai_skill, ai_style):
		ai_mem.resize(n_units * AIProfile.MU_K + 2 * AIProfile.SD_K)
		ai_mem.fill(0)
	for arr in _map_unit_arrays():
		arr.resize(n_units)
		arr.fill(0)
	for arr in _stair_arrays():
		arr.resize(n_units)
		arr.fill(0)
	for arr in _flow_arrays():
		arr.resize(n_units)
		arr.fill(0)
	stat_stuck_u.resize(n_units)
	stat_stuck_u.fill(0)
	stat_stuck_t.resize(n_units)
	stat_stuck_t.fill(0)
	for arr in _siege_unit_arrays():
		arr.resize(n_units)
		arr.fill(0)
	for arr in _dog_arrays():
		arr.resize(n_units)
		arr.fill(0)
	u_pack.fill(-1)
	u_hand.fill(-1)
	g_unbar.resize(n_gates)
	g_unbar.fill(0)
	g_burn.resize(n_gates)
	g_burn.fill(0)
	sg_on = 0
	for arr in [u_carry, u_pick, u_lq]:
		arr.fill(-1)
	_setup_equip(scenario, units)
	u_gtarget.fill(-1)
	pth_x.resize(n_units * PATH_MAX)
	pth_x.fill(0)
	pth_y.resize(n_units * PATH_MAX)
	pth_y.fill(0)
	tr_x.resize(n_units * TRAIL)
	tr_x.fill(0)
	tr_y.resize(n_units * TRAIL)
	tr_y.fill(0)
	_u_obs.resize(n_units)
	_lw_x.resize(n)
	_lw_y.resize(n)
	_fl_mark.resize(ob_w * ob_h)
	_fl_mark.fill(0)
	_fl_q.resize(FLOW_CELLS)
	_fl_stamp = 0
	_u_obs.fill(0)
	_u_vfac.resize(n_units)
	_u_vfac.fill(1000)
	slot_soldier.resize(n)
	off_x.resize(n)
	off_y.resize(n)
	_rm.resize(n)
	_rm_why.resize(n)
	_u_fac.resize(n_units)
	_u_fac.fill(1000)
	_u_steep.resize(n_units)
	_u_steep.fill(0)
	dbg_impacted.resize(n)
	dbg_impacted.fill(0)
	target.fill(-1)

	var base := 0
	var eng := 0
	var grp := 0
	for u in n_units:
		var ud: Dictionary = units[u]
		var ty := int(ud["type"])
		var cnt := int(ud["count"])
		u_side[u] = int(ud["side"])
		u_type[u] = ty
		u_otype[u] = ty
		u_eg[u] = -1
		u_cls[u] = t_cls[ty]
		u_count0[u] = cnt
		u_alive[u] = cnt
		u_state[u] = U_READY
		u_morale[u] = t_morale[ty]
		if ud.has("morale_pct"):
			# A unit that starts shaken (the campaign: an army caught on a
			# forced march): this % of its type's morale.
			u_morale[u] = t_morale[ty] * clampi(int(ud["morale_pct"]), 10, 100) / 100
		u_files[u] = clampi(int(ud.get("files", 20)), 1, cnt)
		u_ax[u] = int(ud["x_m"]) * M
		u_ay[u] = int(ud["y_m"]) * M
		u_face[u] = int(ud["facing"]) & FM.ANGLE_MASK
		u_dface[u] = u_face[u]
		u_target[u] = -1
		u_ftarget[u] = -1
		u_order[u] = O_NONE
		u_fire[u] = 1 if t_m_ammo[ty] > 0 else 0
		u_skirm[u] = t_skirm[ty]
		# (Scenario "ammo_pct": it starts with this % of its load; tests.)
		u_ammo[u] = cnt * (t_m_ammo[ty] * clampi(int(ud.get("ammo_pct", 100)), 0, 100) / 100)
		u_hit_t[u] = -1000
		u_charged_t[u] = -1000
		u_slot_base[u] = base
		u_dirty[u] = 1
		u_ai_t[u] = 0
		u_ftarget[u] = -1
		u_shelled_t[u] = -1000
		u_shelled_by[u] = -1
		# A special ammunition kind for its weapon (scenario "ak": a row of
		# UnitTypes.AMMO riding on the type's standard kind).
		var akk := int(ud.get("ak", -1))
		if akk < 0 or akk >= t_k_base.size() or t_k_base[akk] < 0 or t_k_base[akk] != t_m_ak[ty]:
			akk = -1
		u_sk[u] = akk
		if city_on != 0 and int(ud.get("wall", 0)) > 0 and int(ud.get("wall", 0)) <= ws_x0.size():
			# Placed on a wall walkway: it holds that stretch of wall, in
			# its wall line (as a unit sent up there would stand).
			u_wall[u] = int(ud["wall"])
			u_skirm[u] = 0
			var wa := wall_anchor(self, u_wall[u] - 1, u_ax[u], u_ay[u], cnt, ty)
			u_ax[u] = wa.x
			u_ay[u] = wa.y
			u_face[u] = wa.z
			u_dface[u] = wa.z
			u_files[u] = wall_nf(cnt)
		if t_fixed[ty] != 0:
			# A tower's engine: on the tower (a wall unit of the stretch
			# nearest it: its crew keeps to the walkway and towers and the
			# battlements cover it), never moving.
			sg_on = 1
			u_trad[u] = int(ud.get("tower_r", 4)) * M
			u_skirm[u] = 0
			if city_on != 0 and ws_x0.size() > 0:
				var bs := 0
				var bo := 1 << 40
				for sg in ws_x0.size():
					var o := _seg_off(sg, u_ax[u], u_ay[u])
					if o < bo:
						bo = o
						bs = sg
				u_wall[u] = bs + 1
		var ne := _engines_for(ty, cnt)
		u_eng0[u] = eng
		u_neng[u] = ne
		if ne > 0:
			# Artillery: files = engines; ammunition belongs to the engines.
			u_files[u] = ne
			u_ammo[u] = ne * t_m_ammo[ty]
			u_reserve[u] = ne * t_m_reserve[ty]
			u_deploy[u] = 1
			u_depl[u] = t_deploy[ty]  # starts set up
			u_skirm[u] = 0
			var c := FM.cos_a(u_face[u])
			var sn := FM.sin_a(u_face[u])
			for k in ne:
				var e := eng + k
				var lat := ((2 * k - (ne - 1)) * t_fsp[ty]) / 2
				e_unit[e] = u
				e_x[e] = u_ax[u] + ((-lat * sn) / FM.TRIG_ONE)
				e_y[e] = u_ay[u] + ((lat * c) / FM.TRIG_ONE)
				e_face[e] = u_face[u]
				e_hp[e] = t_e_hp[ty]
				e_state[e] = E_OK
				e_ammo[e] = t_m_ammo[ty]
				if t_fixed[ty] != 0 and int(ud.get("tower_ammo", 100)) != 100:
					e_ammo[e] = t_m_ammo[ty] * int(ud["tower_ammo"]) / 100
				e_sammo[e] = e_ammo[e] * t_k_share[akk] / 100 if akk >= 0 else 0
				# Staggered: engines are part way through loading.
				e_reload[e] = _rand() % maxi(t_m_reload[ty] * t_crew[ty], 1)
			if t_fixed[ty] != 0:
				u_ammo[u] = 0
				for k in ne:
					u_ammo[u] += e_ammo[eng + k]
			# The battery's engines are a group it works (equipment: any foot
			# can take it up once it is left on the field).
			for k in ne:
				e_grp[eng + k] = grp
			eg_e0[grp] = eng
			eg_ne[grp] = ne
			eg_type[grp] = ty
			eg_u0[grp] = u
			eg_op[grp] = u
			eg_side[grp] = u_side[u]
			eg_face[grp] = u_face[u]
			eg_sk[grp] = akk  # (the engines carry the special kind; the crews have none)
			u_sk[u] = -1
			u_eg[u] = grp
			grp += 1
			eng += ne
		_compute_offsets(u)
		for s in cnt:
			var i := base + s
			unit_of[i] = u
			slot_of[i] = s
			slot_soldier[base + s] = i
			# Small deterministic jitter so ranks do not look ruled.
			pos_x[i] = u_ax[u] + off_x[base + s] + _rand() % 205 - 102
			pos_y[i] = u_ay[u] + off_y[base + s] + _rand() % 205 - 102
			if u_wall[u] > 0 and obs_kind(pos_x[i], pos_y[i]) != MapGen.C_WALK:
				# On a wall: never jittered off the walkway.
				pos_x[i] = u_ax[u] + off_x[base + s]
				pos_y[i] = u_ay[u] + off_y[base + s]
			facing[i] = u_face[u]
			hp[i] = t_hp[ty]
			state[i] = S_FORMED
			cooldown[i] = 1 + _rand() % t_cooldown[ty]
			target[i] = -1
			ammo[i] = t_m_ammo[ty] * clampi(int(ud.get("ammo_pct", 100)), 0, 100) / 100 if ne == 0 else 0
			sammo[i] = ammo[i] * t_k_share[akk] / 100 if akk >= 0 and ne == 0 else 0
		base += cnt
	if dog_on != 0:
		for u in n_units:
			if units[u].has("pack_of"):
				_kennel_setup(u, int(units[u]["pack_of"]))
	fire_on = 0
	for u in n_units:
		if u_sk[u] >= 0 and t_k_fire[u_sk[u]] > 0:
			fire_on = 1
	for g in n_eg:
		if eg_sk[g] >= 0 and t_k_fire[eg_sk[g]] > 0:
			fire_on = 1
	# Beasts: big bodies, auras (none in most battles: every rule below is skipped).
	big_on = 0
	_hit_rmax = HIT_R_CAV
	aura_src = PackedInt32Array()
	for u in n_units:
		var bty := u_type[u]
		if t_body_r[bty] > 0:
			big_on = 1
		_hit_rmax = maxi(_hit_rmax, t_hit_r[bty])
		if t_scare_r[bty] > 0 or t_fear_r[bty] > 0 or t_cmd_r[bty] > 0:
			aura_src.append(u)

	# Projectile pool: every slot on the free list.
	for arr in _projectile_arrays():
		arr.resize(PR_CAP)
		arr.fill(0)
	pr_t1.fill(-1)
	for p in PR_CAP:
		pr_next[p] = p + 1 if p + 1 < PR_CAP else -1
	pr_free = 0
	pr_count = 0
	pr_bucket.resize(PR_BUCKETS)
	pr_bucket.fill(-1)

	prev_x = pos_x.duplicate()
	prev_y = pos_y.duplicate()
	e_px = e_x.duplicate()
	e_py = e_y.duplicate()
	grid_w = (field_w >> GRID_SHIFT) + 1
	grid_h = (field_h >> GRID_SHIFT) + 1
	grid_head0.resize(grid_w * grid_h)
	grid_head1.resize(grid_w * grid_h)
	blk_w = (field_w >> 14) + 1
	blk_n0.resize(blk_w * ((field_h >> 14) + 1))
	blk_n1.resize(blk_n0.size())
	for arr in [occ0, occ1]:
		arr.resize(grid_w * grid_h)
		arr.fill(0)
	grid_next.resize(n)
	_update_bounds()
	_update_units_stats()
	if ter_on != 0 or obs_on != 0 or fwh_on != 0:
		for u in n_units:
			u_h[u] = _unit_elev(u)

	for o in scenario.get("orders", []):
		var od: Dictionary = (o as Dictionary).duplicate()
		if not od.has("player"):
			od["player"] = 50
		queue_order(od)
	_setup_deploy(scenario)
	if fw_on != 0:
		# The battle AI puts its side's field works in front of its line
		# (after its deployment, if there is one).
		for s in 2:
			if ai_sides[s] != 0:
				BattleAI.place_works(self, s)


func _soldier_arrays() -> Array:
	return [pos_x, pos_y, prev_x, prev_y, facing, hp, state, cooldown, unit_of,
		slot_of, target, ammo, chg, struck, sammo]


func _soldier_hashed() -> Array:
	return [pos_x, pos_y, facing, hp, state, cooldown, unit_of, slot_of, target,
		ammo, chg, struck, sammo]


func _unit_arrays() -> Array:
	return [u_side, u_type, u_cls, u_count0, u_alive, u_state, u_morale, u_routs,
		u_files, u_ax, u_ay, u_face, u_order, u_dx, u_dy, u_dface, u_target,
		u_run, u_fire, u_skirm, u_slot_base, u_contact, u_fighting, u_inreach, u_settled,
		u_dirty, u_cx, u_cy, u_minx, u_miny, u_maxx, u_maxy, u_flee_x, u_flee_y,
		u_moved, u_disorder, u_formed, u_braced, u_mom, u_charge, u_charge_t,
		u_charge_left, u_charge_act, u_down, u_ftarget,
		u_fire_acc, u_fire_ptr, u_ammo, u_hit_t, u_charged_t, u_killed,
		u_withdrawn, u_routed_off, u_recent, u_att, u_def, u_dmg, u_reach, u_nwalls,
		u_ai, u_ai_t, u_ai_x, u_ai_y, u_eng0, u_neng, u_depl, u_deploy, u_fright,
		u_shelled_t, u_shelled_by, u_emove, u_h, u_refill, u_rprog, u_reserve, u_blk, u_dodge,
		u_kills, u_otype, u_eg, u_oammo, u_sk, u_akind, u_burn, u_forage, u_racc, u_rptr,
		u_scare, u_amok, u_calm, u_kill, u_awe, u_led, u_cmdgone]


## Per-unit arrays of woods and settlement maps (hashed only on those maps,
## so the hash of a plain map is what it always was).
func _map_unit_arrays() -> Array:
	return [u_wall, u_sq, u_gtarget, u_pn, u_pk, u_pgx, u_pgy, u_pep, u_trn]


## Per-unit stair moves and regrouping (maps with buildings or walls;
## hashed only there).
func _stair_arrays() -> Array:
	return [u_stair, u_sseg, u_send, u_st0, u_wx, u_wy, u_lagt]


## Per-unit flow state (docs/DESIGN.md "Units flow into the space"; maps
## with buildings or walls; hashed only there).
func _flow_arrays() -> Array:
	return [u_stuck, u_srx, u_sry, u_sprog, u_flow, u_flt]


## Per-unit war dog arrays (hashed only in battles with handlers, so the
## hash of any other battle is what it always was).
func _dog_arrays() -> Array:
	return [u_pack, u_hand, u_kept, u_dogt, u_ret]


func _engine_arrays() -> Array:
	return [e_unit, e_x, e_y, e_face, e_hp, e_state, e_reload, e_ammo, e_crew, e_rwork, e_grp, e_sammo, e_burn]


func _egroup_arrays() -> Array:
	return [eg_e0, eg_ne, eg_type, eg_u0, eg_op, eg_depl, eg_res, eg_face, eg_side, eg_sk]


## Engines in a unit of `count` soldiers of type ty (0 unless artillery).
static func _engines_for(ty: int, count: int) -> int:
	var crew := UT.stat(ty, "crew")
	if UT.cls(ty) != UT.CLS_ART or crew <= 0:
		return 0
	return maxi(count / crew, 1)


func _projectile_arrays() -> Array:
	return [pr_sx, pr_sy, pr_x, pr_y, pr_t0, pr_t1, pr_unit, pr_tu, pr_next, pr_ty, pr_ak]


func _load_types() -> void:
	var nt := UT.TYPES.size()
	var arrays := [t_cls, t_attack, t_defence, t_armour, t_shield, t_mshield,
		t_damage, t_reach, t_ranks, t_mass, t_walk, t_run, t_hp, t_cooldown,
		t_morale, t_fsp, t_rsp, t_turn, t_brace, t_vs_cav, t_charge, t_sec_att,
		t_sec_def, t_sec_dmg, t_sec_reach, t_m_range, t_m_dmg, t_m_ap, t_m_ammo,
		t_m_reload, t_m_spread, t_m_spread0, t_m_speed, t_m_arc, t_skirm, t_m_vuln, t_m_down,
		t_m_lead, t_m_long, t_crew, t_crew_min, t_m_kind, t_m_min, t_m_pierce, t_m_plough, t_m_blast,
		t_m_fear, t_arc, t_traverse, t_deploy, t_e_hp, t_climb, t_m_hgain, t_m_apex, t_m_reserve, t_m_refill,
		t_fixed, t_m_ak, t_mount, t_acc, t_body_r, t_crew_sh, t_woods, t_tr_n, t_tr_r, t_tr_pct, t_crush,
		t_scare_r, t_scare_pct, t_scare_mor, t_fear_r, t_fear_h, t_fear_f, t_burn_pct, t_amok, t_amok_r,
		t_amok_calm, t_kill_delay, t_gate_w, t_gate_pct, t_cmd_r, t_cmd_mor, t_cmd_rally, t_cmd_loss, t_cmd_loss_r,
		t_pack_n, t_pack_type, t_pack_r, t_return_r, t_return_t, t_nobreak, t_scare_am, t_as_cav, t_chase, t_m_spen]
	var keys := ["cls", "attack", "defence", "armour", "shield", "mshield",
		"damage", "reach", "ranks_reach", "mass", "walk", "run", "hp", "cooldown",
		"morale", "file_sp", "rank_sp", "turn", "brace", "vs_cav", "charge",
		"sec_attack", "sec_defence", "sec_damage", "sec_reach", "m_range",
		"m_damage", "m_ap", "m_ammo", "m_reload", "m_spread", "m_spread0",
		"m_speed", "m_arc", "skirm", "m_vuln", "m_down", "m_lead", "m_long", "crew", "crew_min",
		"m_kind", "m_min", "m_pierce", "m_plough", "m_blast", "m_fear", "arc", "traverse",
		"deploy", "e_hp", "climb", "m_hgain", "m_apex", "m_reserve", "m_refill", "fixed", "m_ak",
		"mount", "acc", "body_r", "crew_shoot", "woods_pct", "trample_n", "trample_r", "trample_pct", "crush",
		"scare_r", "scare_pct", "scare_mor", "fear_r", "fear_horse", "fear_foot", "burn_pct", "amok", "amok_r",
		"amok_calm", "kill_delay", "gate_walls", "gate_pct", "cmd_r", "cmd_mor", "cmd_rally", "cmd_loss", "cmd_loss_r",
		"pack_n", "pack_type", "pack_r", "return_r", "return_t", "nobreak", "scare_am", "as_cav", "chase", "m_spen"]
	for k in arrays.size():
		var arr: PackedInt32Array = arrays[k]
		arr.resize(nt)
		for t in nt:
			arr[t] = UT.stat(t, keys[k])
	# Riders: cavalry, and any mounted row with a charge (light horse): they
	# build momentum at the run and charge (the cavalry code path).
	t_rider.resize(nt)
	for t in nt:
		t_rider[t] = 1 if t_cls[t] == UT.CLS_CAV or (t_mount[t] != UT.MOUNT_FOOT and t_charge[t] > 0) else 0
	# Missile hit radius per type: a big body's, a mount's, a man's.
	t_hit_r.resize(nt)
	for t in nt:
		if t_body_r[t] > 0:
			t_hit_r[t] = t_body_r[t]
		elif t_cls[t] == UT.CLS_CAV or (t_mount[t] != UT.MOUNT_FOOT and t_mount[t] != UT.MOUNT_DOG):
			t_hit_r[t] = HIT_R_CAV
		else:
			t_hit_r[t] = HIT_R_INF
	var ka := [t_k_base, t_k_share, t_k_dmg, t_k_obj, t_k_ap, t_k_pierce, t_k_range, t_k_rate, t_k_fear,
		t_k_blast, t_k_fire, t_k_aoe]
	var na := UT.AMMO.size()
	for k in ka.size():
		var arr: PackedInt32Array = ka[k]
		arr.resize(na)
		for a in na:
			arr[a] = UT.ammo_stat(a, UT.AMMO_FIELDS[k])


# -------------------------------------------------------------- terrain ---

## Build the height grid from the scenario's terrain parameters (none or
## kind flat: ter_on stays 0 and every terrain rule is skipped).
func _setup_terrain(terr: Dictionary, p_seed: int) -> void:
	var t := Terrain.build(terr, p_seed, field_w, field_h)
	# Woods and the settlement (a city map turns its heights round too when
	# the defenders are at the bottom).
	var mf := MapGen.build(terr, p_seed, field_w / M, field_h / M, t)
	ter_on = int(t["on"])
	ter_nx = int(t["nx"])
	ter_ny = int(t["ny"])
	ter_h = t["h"]
	var g: Array = Terrain.gradients(ter_h, ter_nx, ter_ny)
	ter_gx = g[0]
	ter_gy = g[1]
	ter_info = {"kind": int(t["kind"]), "seed": int(t["seed"]), "relief_m": int(t["relief_m"]),
		"scale_m": int(t["scale_m"]), "sym": int(t["sym"]), "palette": int(mf["palette"]),
		"forest": int(mf["forest"])}
	_setup_map(mf)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(PackedInt64Array([ter_on, ter_nx, ter_ny, int(t["kind"]), int(t["seed"]),
		int(t["relief_m"]), int(t["scale_m"]), int(t["sym"]),
		Terrain.grid_hash(ter_h, ter_nx, ter_ny, ter_on)]).to_byte_array())
	if map_on != 0:
		ctx.update(PackedInt64Array([map_hash]).to_byte_array())
	ter_hash = ctx.finish().decode_u32(0)


## Ground height (sim units) at (x, y): fixed-point bilinear interpolation
## of the node grid. The whole weighted sum is formed exactly and divided
## once, so the field's 180-degree mirror image samples to the same value.
func height_at(x: int, y: int) -> int:
	if ter_on == 0:
		return 0
	x = clampi(x, 0, field_w)
	y = clampi(y, 0, field_h)
	var cx := x >> TER_SHIFT
	var fx := x & (TER_CELL - 1)
	if cx >= ter_nx - 1:
		cx = ter_nx - 2
		fx = TER_CELL
	var cy := y >> TER_SHIFT
	var fy := y & (TER_CELL - 1)
	if cy >= ter_ny - 1:
		cy = ter_ny - 2
		fy = TER_CELL
	var i := cy * ter_nx + cx
	var hh := ter_h
	var h00 := hh[i]
	var h10 := hh[i + 1]
	var h01 := hh[i + ter_nx]
	var h11 := hh[i + ter_nx + 1]
	var top := h00 * TER_CELL + (h10 - h00) * fx
	var bot := h01 * TER_CELL + (h11 - h01) * fx
	return (top * TER_CELL + (bot - top) * fy) / (TER_CELL * TER_CELL)


## Ground gradient (Q12 grade, x and y) at (x, y): the node gradients
## interpolated like the heights (continuous, antisymmetric when mirrored).
func slope_at(x: int, y: int) -> Vector2i:
	if ter_on == 0:
		return Vector2i.ZERO
	x = clampi(x, 0, field_w)
	y = clampi(y, 0, field_h)
	var cx := x >> TER_SHIFT
	var fx := x & (TER_CELL - 1)
	if cx >= ter_nx - 1:
		cx = ter_nx - 2
		fx = TER_CELL
	var cy := y >> TER_SHIFT
	var fy := y & (TER_CELL - 1)
	if cy >= ter_ny - 1:
		cy = ter_ny - 2
		fy = TER_CELL
	var i := cy * ter_nx + cx
	var j := i + ter_nx
	var w00 := (TER_CELL - fx) * (TER_CELL - fy)
	var w10 := fx * (TER_CELL - fy)
	var w01 := (TER_CELL - fx) * fy
	var w11 := fx * fy
	var den := TER_CELL * TER_CELL
	return Vector2i((ter_gx[i] * w00 + ter_gx[i + 1] * w10 + ter_gx[j] * w01 + ter_gx[j + 1] * w11) / den,
		(ter_gy[i] * w00 + ter_gy[i + 1] * w10 + ter_gy[j] * w01 + ter_gy[j + 1] * w11) / den)


## Grade (Q12, positive = uphill) of the ground at (x, y) along (dx, dy).
func grade_along(x: int, y: int, dx: int, dy: int) -> int:
	var d := FM.approx_len(dx, dy)
	if ter_on == 0 or d <= 0:
		return 0
	var g := slope_at(x, y)
	return (g.x * dx + g.y * dy) / d


## Average grade (Q12) from a ground point at height ha to one at hb, d apart.
static func grade_between(ha: int, hb: int, d: int) -> int:
	return (hb - ha) * FM.TRIG_ONE / maxi(d, M)


## Speed factor (per mille) for unit u moving along (dx, dy) from (x, y):
## slower uphill (the type's climb rate), a little faster on a gentle
## downhill, slower again where it is steep.
func _slope_fac(u: int, x: int, y: int, dx: int, dy: int) -> int:
	var f := _fac_for(u, grade_along(x, y, dx, dy))
	if f < 1000:
		stat_slow_up += 1
	return f


## Speed factor (per mille) of unit u moving along (dx, dy), d long, on
## ground of gradient g.
func _fac_dir(u: int, g: Vector2i, dx: int, dy: int, d: int) -> int:
	var f := _fac_for(u, (g.x * dx + g.y * dy) / maxi(d, 1))
	if f < 1000:
		stat_slow_up += 1
	return f


## Speed factor (per mille) of unit u on a grade s (Q12, + = uphill).
func _fac_for(u: int, s: int) -> int:
	var ty := u_type[u]
	var fac := 1000
	if s > 0:
		# climb = % lost per 10% grade: s * 100 / 4096 * climb * 10 / 10.
		fac = 1000 - s * t_climb[ty] * 100 / FM.TRIG_ONE
	elif s < 0:
		var g := -s
		fac = 1000 + mini(g, TER_DOWN_FULL) * TER_DOWN_BONUS / TER_DOWN_FULL
		if g > TER_STEEP:
			fac -= (g - TER_STEEP) * TER_DOWN_STEEP / FM.TRIG_ONE * (2 if u_cls[u] == UT.CLS_CAV else 1)
	var lo := TER_MIN_FAC_ART if u_cls[u] == UT.CLS_ART else TER_MIN_FAC
	return clampi(fac, lo, 1000 + TER_DOWN_BONUS)


## Missile range of type ty shooting from ground height hs at ground height
## ht: the type's m_hgain % of the height difference, at most RANGE_H_CAP %.
func range_h(ty: int, hs: int, ht: int, pct: int = 100) -> int:
	var rng := t_m_range[ty] * pct / 100
	if ter_on == 0 and obs_on == 0 and fwh_on == 0:
		return rng
	var cap := rng * RANGE_H_CAP / 100
	return rng + clampi((hs - ht) * t_m_hgain[ty] / 100, -cap, cap)


## Effective range of missile unit u against unit t (centroid heights; from
## a wall at men below, WALL_RANGE_PCT further).
func range_vs(u: int, t: int) -> int:
	return range_h(u_type[u], u_h[u], u_h[t], range_pct(u)) + _wall_rb(u, t) + _works_rb(u, t)


## Missile troops on a wall shooting at men not on one: WALL_RANGE_PCT % of
## their range more (0 elsewhere).
func _wall_rb(u: int, t: int) -> int:
	if city_on == 0 or u_wall[u] == 0 or u_wall[t] != 0 or t_cls[u_type[u]] != UT.CLS_MISSILE:
		return 0
	return t_m_range[u_type[u]] * WALL_RANGE_PCT[city_walls] / 100


## Line of fire over the ground: from (x0, y0) at height z0 to (x1, y1) at
## z1 (absolute heights, sim units), allowing a rise of `apex` above the
## straight line at mid-flight (parabolic), continued `ext` past the end.
## Returns the distance from (x0, y0) at which the ground first rises above
## the flight, or -1 if it is clear. Ground within LOF_SKIP of either end of
## the aimed segment is ignored (the shooter's and target's own footing).
func lof_block(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, apex: int, ext: int,
		stride: int = LOF_STEP, skip0: int = 0, skip1: int = LOF_SKIP) -> int:
	if ter_on == 0 and map_on == 0:
		return -1
	var dx := x1 - x0
	var dy := y1 - y0
	var d := FM.approx_len(dx, dy)
	if d <= 2 * LOF_SKIP:
		return -1
	var dz := z1 - z0
	var a := LOF_SKIP
	var end := d - skip1  # (skip1: a tower aimed at is not in its own way)
	if ext > 0:
		end = d + ext
	# Woods and settlements: trees in the way add up (TREE_W per sample);
	# buildings, walls and closed gates stand up from the ground. A shooter
	# on a wall looks over his own battlements.
	if map_on == 0:
		# Plain hilly map: the ground alone (the original tight loop).
		while a <= end:
			var qx := x0 + dx * a / d
			var qy := y0 + dy * a / d
			if qx < 0 or qy < 0 or qx > field_w or qy > field_h:
				return -1
			var qz := z0 + dz * a / d
			if a < d:
				qz += apex * 4 * a / d * (d - a) / d
			if height_at(qx, qy) > qz:
				return a
			a += stride
		return -1
	var tw := 0
	var oskip := LOF_SKIP
	if obs_on != 0 and obs_kind(x0, y0) == MapGen.C_WALK:
		oskip = wall_t + 2 * M
	oskip = maxi(oskip, skip0)  # a tower's engine shoots over its own tower
	while a <= end:
		var px := x0 + dx * a / d
		var py := y0 + dy * a / d
		if px < 0 or py < 0 or px > field_w or py > field_h:
			return -1
		var z := z0 + dz * a / d
		if a < d:
			z += apex * 4 * a / d * (d - a) / d
		var gz := height_at(px, py)
		if obs_on != 0 and a >= oskip:
			var ot := _obs_top(px, py)
			if ot > 0 and gz + ot > z:
				stat_obs_lof += 1
				return a
		if gz > z:
			return a
		if veg_on != 0:
			tw += TREE_W[veg_d(px, py)]
			if tw > TREE_BLOCK:
				stat_tree_lof += 1
				return a
		a += stride
	return -1


## Unit-level line of fire for a flat weapon of unit u at unit t (centroid
## to centroid), or true for weapons that arc over everything.
func lof_units(u: int, t: int) -> bool:
	if ter_on == 0 and map_on == 0:
		return true
	var ty := u_type[u]
	if t_m_arc[ty] != 0:
		return true
	var x0 := u_cx[u]
	var y0 := u_cy[u]
	var x1 := u_cx[t]
	var y1 := u_cy[t]
	var d := FM.approx_len(x1 - x0, y1 - y0)
	var blk := lof_block(x0, y0, u_h[u] + LOF_EYE, x1, y1, u_h[t] + LOF_BODY,
		d * t_m_apex[ty] / 100, 0, 2 * LOF_STEP, _skip0(u), _skip1(t))
	return blk < 0


# ----------------------------------------------- woods and settlements ---

## Load the woods and settlement data built by MapGen (static grids, gates,
## wall segments, the street graph) and hash the static part into map_hash.
func _setup_map(f: Dictionary) -> void:
	veg_on = int(f["veg_on"])
	obs_on = int(f["obs_on"])
	city_on = int(f["city_on"])
	map_on = 1 if veg_on != 0 or obs_on != 0 else 0
	veg_w = int(f["vw"])
	veg_h = int(f["vh"])
	veg = f["veg"] if map_on != 0 else PackedByteArray()
	obs = PackedByteArray()
	nav = PackedByteArray()
	obs_c = PackedByteArray()
	obs_cd = PackedByteArray()
	ob_w = 0
	ob_h = 0
	oc_w = 0
	oc_h = 0
	city_def = -1
	cap_t = 0
	nav_epoch = 0
	n_gates = 0
	_dist_cache = {}
	_dist_epoch = -1
	_dist_have = PackedInt32Array()
	cit_r = 0
	cit_gate = -1
	sea_on = 0
	city_ditch = 0
	cit_siege = 0
	agora = PackedInt32Array([0, 0, 0])
	for arr in [g_x, g_y, g_dir, g_ox, g_oy, g_ix, g_iy, g_hp, g_hp0, g_state, g_hit_t, g_bb,
			ws_x0, ws_y0, ws_x1, ws_y1, ws_dir, ng_x, ng_y, ng_gate, ng_e0, ng_to, ng_w, g_hw, g_cit,
			ws_e, ws_fl, sea_flee, ws_nb, ws_jx, ws_jy]:
		(arr as PackedInt32Array).resize(0)
	map_info = {"palette": int(f["palette"]), "forest": int(f["forest"])}
	if obs_on != 0:
		obs = f["obs"]
		ob_w = int(f["ow"])
		ob_h = int(f["oh"])
		oc_w = (ob_w + 7) >> 3
		oc_h = (ob_h + 7) >> 3
		obs_c.resize(oc_w * oc_h)
		obs_c.fill(0)
		for j in ob_h:
			var row := j * ob_w
			var crow := (j >> 3) * oc_w
			for i in ob_w:
				if obs[row + i] != MapGen.C_OPEN:
					obs_c[crow + (i >> 3)] = 1
		obs_cd.resize(oc_w * oc_h)
		obs_cd.fill(0)
		for j in oc_h:
			for i in oc_w:
				if obs_c[j * oc_w + i] == 0:
					continue
				for dj in range(-1, 2):
					for di in range(-1, 2):
						var jj := j + dj
						var ii := i + di
						if jj >= 0 and ii >= 0 and jj < oc_h and ii < oc_w:
							obs_cd[jj * oc_w + ii] = 1
	if city_on != 0:
		var lay: Dictionary = f["city"]
		map_info["city"] = lay
		city_def = int(lay["def"])
		city_walls = int(lay["walls"])
		city_level = int(lay["level"])
		wall_h = int(lay["wall_h_m"]) * M
		wall_t = int(lay["t"]) * M
		build_h = int(lay["build_h_m"]) * M
		var pl: Array = lay["plaza"]
		plaza = PackedInt32Array([int(pl[0]) * M, int(pl[1]) * M, int(pl[2]) * M, int(pl[3]) * M])
		for gd in lay["gates"]:
			g_x.append(int(gd["x"]) * M)
			g_y.append(int(gd["y"]) * M)
			g_dir.append(int(gd["dir"]))
			g_ox.append(int(gd["ox"]) * M)
			g_oy.append(int(gd["oy"]) * M)
			g_ix.append(int(gd["ix"]) * M)
			g_iy.append(int(gd["iy"]) * M)
			var gcit := int(gd.get("cit", 0))
			# A citadel's gate is an inner wall's: 60 % of the outer gates' hit points.
			var ghp: int = int(lay["gate_hp"]) * (CIT_GATE_PCT if gcit != 0 else 100)
			ghp = ghp * GATE_HP_PCT[city_walls] / 100  # walls 2-3: tougher gates
			g_hp0.append(ghp)
			g_hp.append(ghp)
			g_cit.append(gcit)
			g_hw.append(int(gd.get("hw", MapGen.GATE_HW)))
			# The citadel's gate starts open (its men come and go).
			g_state.append(GATE_OPEN if gcit != 0 else GATE_CLOSED)
			g_hit_t.append(-1000)
			var ext: int = int(lay["t"]) + g_hw[g_hw.size() - 1] + 2
			g_bb.append(maxi((int(gd["x"]) - ext) / 2, 0))
			g_bb.append(maxi((int(gd["y"]) - ext) / 2, 0))
			g_bb.append(mini((int(gd["x"]) + ext) / 2, ob_w - 1))
			g_bb.append(mini((int(gd["y"]) + ext) / 2, ob_h - 1))
		n_gates = g_x.size()
		for sg in lay["segs"]:
			ws_x0.append(int(sg[0]) * M)
			ws_y0.append(int(sg[1]) * M)
			ws_x1.append(int(sg[2]) * M)
			ws_y1.append(int(sg[3]) * M)
			ws_dir.append(int(sg[4]))
			for q in 12:
				ws_e.append(int(sg[5 + q]) * M)
			ws_fl.append(int(sg[17]))
		var ag: Array = lay.get("agora", [int(pl[0]), int(pl[1]), int(pl[2])])
		agora = PackedInt32Array([int(ag[0]) * M, int(ag[1]) * M, int(ag[2]) * M])
		var cd: Dictionary = lay.get("cit", {})
		if not cd.is_empty():
			cit_x = int(cd["x"]) * M
			cit_y = int(cd["y"]) * M
			cit_r = int(cd["rc"]) * M
			cit_gate = int(cd["gate"])
		var sd: Dictionary = lay.get("sea", {})
		if not sd.is_empty():
			sea_on = 1
			for fl in sd["flee"]:
				sea_flee.append(int(fl[0]) * M)
				sea_flee.append(int(fl[1]) * M)
		city_ditch = int(lay.get("ditch", 0))
		var gr: Dictionary = lay["nav"]
		for k in (gr["x"] as PackedInt32Array).size():
			ng_x.append(int(gr["x"][k]) * M)
			ng_y.append(int(gr["y"][k]) * M)
		ng_gate = (gr["gate"] as PackedInt32Array).duplicate()
		ng_e0 = (gr["e0"] as PackedInt32Array).duplicate()
		ng_to = (gr["to"] as PackedInt32Array).duplicate()
		ng_w = (gr["w"] as PackedInt32Array).duplicate()
	if obs_on != 0:
		nav.resize(ob_w * ob_h)
		_rebuild_nav()
		_wall_joins()
		_build_cmp()
	map_hash = 0
	if map_on != 0:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		ctx.update(PackedInt64Array([veg_on, obs_on, city_on, veg_w, veg_h, ob_w, ob_h, city_def,
			city_walls, city_level, wall_h, n_gates, ng_x.size()]).to_byte_array())
		if cit_r > 0 or sea_on != 0 or city_ditch != 0 or ws_e.size() > 0:
			# Settlements with stairs, a citadel, a ditch or the sea (the
			# original maps without them hash as they did).
			ctx.update(PackedInt64Array([cit_x, cit_y, cit_r, cit_gate, sea_on, city_ditch]).to_byte_array())
			for arr in [ws_e, g_hw, g_cit]:
				if (arr as PackedInt32Array).size() > 0:
					ctx.update((arr as PackedInt32Array).to_byte_array())
		if veg.size() > 0:
			ctx.update(veg)
		if obs_on != 0:
			ctx.update(obs)
			if ng_to.size() > 0:
				ctx.update(ng_to.to_byte_array())
			if ws_x0.size() > 0:
				ctx.update(ws_x0.to_byte_array())
		map_hash = ctx.finish().decode_u32(0)


## Passability from the static cells and the gates' states.
func _rebuild_nav() -> void:
	for c in obs.size():
		nav[c] = _nav_of(obs[c])


## Wall stretches joined end to end through a tower (a corner of the wall,
## not a gate): for each stretch end the nearest other stretch end within
## WALL_JOIN whose way to it (along the walkway centre lines to where they
## meet) is all walkway, stair or tower. Static (rebuilt by setup()).
func _wall_joins() -> void:
	var ns := ws_x0.size()
	ws_nb.resize(ns * 2)
	ws_nb.fill(-1)
	ws_jx.resize(ns * 2)
	ws_jx.fill(0)
	ws_jy.resize(ns * 2)
	ws_jy.fill(0)
	for sg in ns:
		for e in 2:
			var p := _seg_end(sg, e)
			var best := -1
			var best_d := WALL_JOIN + 1
			for s2 in ns:
				if s2 == sg:
					continue
				for e2 in 2:
					var q := _seg_end(s2, e2)
					var d := FM.approx_len(q.x - p.x, q.y - p.y)
					if d < best_d:
						best_d = d
						best = s2 * 2 + e2
			if best < 0:
				continue
			var q2 := _seg_end(best / 2, best % 2)
			var j := _seg_meet(sg, best / 2, p, q2)
			if _wall_way(p, j) and _wall_way(j, q2):
				ws_nb[sg * 2 + e] = best
				ws_jx[sg * 2 + e] = j.x
				ws_jy[sg * 2 + e] = j.y
				_open_tower(p, j)
				_open_tower(j, q2)


## End e (0: x0 y0, 1: x1 y1) of walkway segment sg.
func _seg_end(sg: int, e: int) -> Vector2i:
	return Vector2i(ws_x0[sg], ws_y0[sg]) if e == 0 else Vector2i(ws_x1[sg], ws_y1[sg])


## Where the centre lines of segments a and b meet (their ends p, q joined
## through a tower); the midpoint of p and q if they do not meet near them.
func _seg_meet(a: int, b: int, p: Vector2i, q: Vector2i) -> Vector2i:
	var ax := ws_x1[a] - ws_x0[a]
	var ay := ws_y1[a] - ws_y0[a]
	var bx := ws_x1[b] - ws_x0[b]
	var by := ws_y1[b] - ws_y0[b]
	var la := maxi(FM.isqrt(ax * ax + ay * ay), 1)
	var lb := maxi(FM.isqrt(bx * bx + by * by), 1)
	# Unit directions (1/4096) and the cross product of them.
	var ux := ax * 4096 / la
	var uy := ay * 4096 / la
	var vx := bx * 4096 / lb
	var vy := by * 4096 / lb
	var cr := ux * vy - uy * vx
	var mid := Vector2i((p.x + q.x) / 2, (p.y + q.y) / 2)
	if absi(cr) < 4096 * 4096 / 20:
		return mid  # nearly in line
	# p + s * u = q + t * v: s = ((q - p) x v) / (u x v) (sim units).
	var wx := q.x - p.x
	var wy := q.y - p.y
	var s := (wx * vy - wy * vx) / (cr / 4096)
	var j := Vector2i(p.x + ux * s / 4096, p.y + uy * s / 4096)
	if FM.approx_len(j.x - mid.x, j.y - mid.y) > WALL_JOIN:
		return mid
	return j


## Every metre from a to b is walkway, stair or tower (a wall unit's way).
func _wall_way(a: Vector2i, b: Vector2i) -> bool:
	var steps := FM.approx_len(b.x - a.x, b.y - a.y) / M + 1
	for q in steps + 1:
		var k := obs_kind(a.x + (b.x - a.x) * q / steps, a.y + (b.y - a.y) * q / steps)
		if k != MapGen.C_WALK and k != MapGen.C_STAIR and k != MapGen.C_TOWER:
			return false
	return true


## The tower cells within 2 m of the way from a to b (a junction between
## two stretches) become passable to wall units (NAV_TOWER); other towers
## (a gate's, a lone one) stay shut. Static, like the cells.
func _open_tower(a: Vector2i, b: Vector2i) -> void:
	var steps := FM.approx_len(b.x - a.x, b.y - a.y) / M + 1
	for q in steps + 1:
		var ci := (a.x + (b.x - a.x) * q / steps) >> 11
		var cj := (a.y + (b.y - a.y) * q / steps) >> 11
		for dj in range(-1, 2):
			for di in range(-1, 2):
				var i := ci + di
				var j := cj + dj
				if i >= 0 and j >= 0 and i < ob_w and j < ob_h and obs[j * ob_w + i] == MapGen.C_TOWER:
					nav[j * ob_w + i] = NAV_TOWER


## Reachability (settlement maps): the open ground (and ditch) in pieces
## with every gate shut, flood-filled once (4-neighbour); each gate's cells
## and the pieces beside it. With the gates as they are, pieces joined by an
## open or broken gate are one (_roots). Static; the joining is a pure
## function of the gates' states.
func _build_cmp() -> void:
	var nc := ob_w * ob_h
	cmp.resize(nc)
	cmp.fill(-1)
	n_cmp = 0
	g_cmp.resize(n_gates * 4)
	g_cmp.fill(-1)
	_croot_ep = -1
	if city_on == 0:
		return
	var open := MapGen.NAV_GROUND | MapGen.NAV_DITCH
	# Open by cell kind (gates shut), then a flood fill by plain index steps.
	var kind_open := PackedByteArray()
	kind_open.resize(256)
	for k in MapGen.C_GATE:
		kind_open[k] = 1 if (_nav_of(k) & open) != 0 else 0
	var free := PackedByteArray()
	free.resize(nc)
	for c in nc:
		var k := obs[c]
		if k >= MapGen.C_GATE:
			cmp[c] = -2 - (k - MapGen.C_GATE)
		else:
			free[c] = kind_open[k]
	var q := PackedInt32Array()
	q.resize(nc)
	var w := ob_w
	for c0 in nc:
		if free[c0] == 0:
			continue
		var head := 0
		var tail := 1
		q[0] = c0
		free[c0] = 0
		cmp[c0] = n_cmp
		while head < tail:
			var c := q[head]
			head += 1
			var i := c % w
			if i + 1 < w and free[c + 1] != 0:
				free[c + 1] = 0
				cmp[c + 1] = n_cmp
				q[tail] = c + 1
				tail += 1
			if i > 0 and free[c - 1] != 0:
				free[c - 1] = 0
				cmp[c - 1] = n_cmp
				q[tail] = c - 1
				tail += 1
			if c + w < nc and free[c + w] != 0:
				free[c + w] = 0
				cmp[c + w] = n_cmp
				q[tail] = c + w
				tail += 1
			if c >= w and free[c - w] != 0:
				free[c - w] = 0
				cmp[c - w] = n_cmp
				q[tail] = c - w
				tail += 1
		n_cmp += 1
	# The pieces beside each gate's cells.
	for g in n_gates:
		var b := g * 4
		for j in range(g_bb[b + 1], g_bb[b + 3] + 1):
			for i in range(g_bb[b], g_bb[b + 2] + 1):
				if cmp[j * ob_w + i] != -2 - g:
					continue
				for k in 4:
					var ni := i + (1 if k == 0 else (-1 if k == 1 else 0))
					var nj := j + (1 if k == 2 else (-1 if k == 3 else 0))
					if ni < 0 or nj < 0 or ni >= ob_w or nj >= ob_h:
						continue
					var pc := cmp[nj * ob_w + ni]
					if pc < 0:
						continue
					for m in 4:
						if g_cmp[g * 4 + m] == pc:
							break
						if g_cmp[g * 4 + m] == -1:
							g_cmp[g * 4 + m] = pc
							break


## Each piece's joined piece (the lowest index among those joined) with the
## gates as they are now; recomputed when a gate changes.
func _roots() -> PackedInt32Array:
	if _croot_ep == nav_epoch and _croot.size() == n_cmp:
		return _croot
	_croot.resize(n_cmp)
	for k in n_cmp:
		_croot[k] = k
	for g in n_gates:
		if g_state[g] == GATE_CLOSED:
			continue
		for m in range(1, 4):
			var a := g_cmp[g * 4]
			var b := g_cmp[g * 4 + m]
			if a < 0 or b < 0:
				continue
			var ra := _find_root(a)
			var rb := _find_root(b)
			if ra != rb:
				_croot[maxi(ra, rb)] = mini(ra, rb)
	for k in n_cmp:
		_croot[k] = _find_root(k)
	_croot_ep = nav_epoch
	return _croot


func _find_root(k: int) -> int:
	var r := k
	while _croot[r] != r:
		r = _croot[r]
	return r


## The piece of open ground (x, y) belongs to with the gates as they are
## (an open gate's cells: the pieces it joins); -1 if not open ground (a
## wall, a building, the walkway, a shut gate) or no settlement map.
func reach_at(x: int, y: int) -> int:
	if city_on == 0 or n_cmp == 0 or x < 0 or y < 0:
		return -1
	var i := x >> 11
	var j := y >> 11
	if i >= ob_w or j >= ob_h:
		return -1
	var k := cmp[j * ob_w + i]
	var r := _roots()
	if k >= 0:
		return r[k]
	if k <= -2:
		var g := -2 - k
		if g_state[g] == GATE_CLOSED or g_cmp[g * 4] < 0:
			return -1
		return r[g_cmp[g * 4]]
	return -1


## The nearest open point for `mask` to (x, y): itself if open, else the
## middle of the first open 2 m cell in rings of 2 m out to 12 m (each ring
## in index order); else (x, y). Shared with the view.
static func open_snap(sim, x: int, y: int, mask: int) -> Vector2i:
	if (sim.nav_at(x, y) & mask) != 0:
		return Vector2i(x, y)
	var ci := x >> 11
	var cj := y >> 11
	for r in range(1, 7):
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var px := (ci + di) * 2048 + 1024
				var py := (cj + dj) * 2048 + 1024
				if px >= 0 and py >= 0 and (sim.nav_at(px, py) & mask) != 0:
					return Vector2i(px, py)
	return Vector2i(x, y)


## Where a ground unit with its anchor at (ax, ay) goes when ordered to
## (x, y): (x, y, 0) if it can get there; (x', y', 1) the nearest open
## ground of its own piece within 12 m of a tap on a house or a wall; else
## (x', y', 2) the gate on its side that is best on the way (a tap inside a
## shut town: it goes to the gate and holds there); (x, y, 3) if there is
## no way at all (no gate on its side). Read-only (the order rule and the
## preview).
func reach_snap(ax: int, ay: int, x: int, y: int, side: int) -> Vector3i:
	var ru := reach_at(ax, ay)
	if ru < 0:
		return Vector3i(x, y, 0)
	var rd := reach_at(x, y)
	if rd == ru:
		return Vector3i(x, y, 0)
	var ci := x >> 11
	var rings := 7 if rd < 0 else 1  # (open ground of another piece: straight to the gate)
	var cj := y >> 11
	for ring in range(1, rings):
		var best := Vector2i(-1, -1)
		var best_d := 1 << 40
		for dj in range(-ring, ring + 1):
			for di in range(-ring, ring + 1):
				if absi(di) != ring and absi(dj) != ring:
					continue
				var px := ((ci + di) << 11) + 1024
				var py := ((cj + dj) << 11) + 1024
				if reach_at(px, py) != ru:
					continue
				var d := FM.approx_len(px - x, py - y)
				if d < best_d:
					best_d = d
					best = Vector2i(px, py)
		if best.x >= 0:
			return Vector3i(best.x, best.y, 1)
	var gp := gate_way(ru, ax, ay, x, y, side)
	if gp.z >= 0:
		return Vector3i(gp.x, gp.y, 2)
	return Vector3i(x, y, 3)


## The gate a unit of `side` in piece ru goes to on its way to (x, y) from
## (ax, ay): the one whose front on ru's side (where foot stand to hack at
## it) makes the way shortest; (x, y, gate) or z -1 if none.
func gate_way(ru: int, ax: int, ay: int, x: int, y: int, side: int) -> Vector3i:
	var best := Vector3i(0, 0, -1)
	var best_c := 1 << 40
	for g in n_gates:
		for k in 2:
			var f := gate_front(g, side if k == 0 else (city_def if side != city_def else 1 - city_def))
			if reach_at(f.x, f.y) != ru:
				continue
			var c := FM.approx_len(f.x - ax, f.y - ay) + FM.approx_len(x - f.x, y - f.y)
			if c < best_c:
				best_c = c
				best = Vector3i(f.x, f.y, g)
			break
	return best


## Unit u attacking t that it cannot reach (another piece of ground):
## (x, y, 1) a missile unit with shots goes toward it as far as its own
## ground goes (the last point of its piece on the line from t back to it;
## it shoots from range on the way); (x, y, 2) others go to the gate on
## their side nearest t and hold there (attacking foot hack at it while it
## is shut); z 0: it can reach t (or the rule does not apply).
func unreach_goal(u: int, _t: int, goal: Vector2i) -> Vector3i:
	if city_on == 0 or n_cmp == 0 or u_wall[u] > 0:
		return Vector3i.ZERO
	var ru := reach_at(u_ax[u], u_ay[u])
	if ru < 0:
		return Vector3i.ZERO
	var rt := reach_at(goal.x, goal.y)
	if rt == ru:
		return Vector3i.ZERO
	if u_cls[u] == UT.CLS_MISSILE and u_ammo[u] > 0:
		var dx := u_ax[u] - goal.x
		var dy := u_ay[u] - goal.y
		var steps := FM.approx_len(dx, dy) / (2 * M) + 1
		for q in range(1, steps + 1):
			var px := goal.x + dx * q / steps
			var py := goal.y + dy * q / steps
			if reach_at(px, py) == ru:
				return Vector3i(px, py, 1)
		return Vector3i(u_ax[u], u_ay[u], 1)
	if rt < 0:
		return Vector3i.ZERO  # (a man on a wall: as before)
	var gp := gate_way(ru, goal.x, goal.y, goal.x, goal.y, u_side[u])
	if gp.z < 0:
		return Vector3i(u_ax[u], u_ay[u], 2)
	return Vector3i(gp.x, gp.y, 2)


func _nav_of(k: int) -> int:
	if k == MapGen.C_OPEN:
		return MapGen.NAV_GROUND
	if k == MapGen.C_WALK:
		return MapGen.NAV_WALL | NAV_WALK
	# Towers: shut, but those joining two stretches (_wall_joins) let wall
	# units' men through.
	if k == MapGen.C_STAIR:
		return MapGen.NAV_WALL | MapGen.NAV_GROUND
	if k == MapGen.C_DITCH:
		return MapGen.NAV_DITCH
	if k >= MapGen.C_GATE:
		return MapGen.NAV_GROUND if g_state[k - MapGen.C_GATE] != GATE_CLOSED else 0
	return 0


## A gate changed: its cells' passability, and every path is replanned.
func _gate_cells(g: int) -> void:
	var b := g * 4
	for j in range(g_bb[b + 1], g_bb[b + 3] + 1):
		for i in range(g_bb[b], g_bb[b + 2] + 1):
			var c := j * ob_w + i
			if obs[c] == MapGen.C_GATE + g:
				nav[c] = _nav_of(obs[c])
	nav_epoch += 1


## Tree density 0-3 at (x, y).
func veg_d(x: int, y: int) -> int:
	if veg_on == 0:
		return 0
	var i := x >> 12
	var j := y >> 12
	if x < 0 or y < 0 or i >= veg_w or j >= veg_h:
		return 0
	return veg[j * veg_w + i] & MapGen.V_DENS


## Raw vegetation bits at (x, y) (density, urban, ...).
func veg_bits(x: int, y: int) -> int:
	if map_on == 0:
		return 0
	var i := x >> 12
	var j := y >> 12
	if x < 0 or y < 0 or i >= veg_w or j >= veg_h:
		return 0
	return veg[j * veg_w + i]


## Obstacle cell kind (MapGen.C_*) at (x, y).
func obs_kind(x: int, y: int) -> int:
	if obs_on == 0 or x < 0 or y < 0:
		return MapGen.C_OPEN
	var i := x >> 11
	var j := y >> 11
	if i >= ob_w or j >= ob_h:
		return MapGen.C_OPEN
	return obs[j * ob_w + i]


## Passability bits at (x, y) (outside the field: none).
func nav_at(x: int, y: int) -> int:
	if obs_on == 0:
		return MapGen.NAV_GROUND
	if x < 0 or y < 0:
		return 0
	var i := x >> 11
	var j := y >> 11
	if i >= ob_w or j >= ob_h:
		return 0
	return nav[j * ob_w + i]


## Height a man stands at: the ground, or the walkway on a wall.
func elev_at(x: int, y: int) -> int:
	var h := gh_at(x, y)
	if obs_on != 0:
		var k := obs_kind(x, y)
		if k == MapGen.C_WALK or k == MapGen.C_TOWER:
			h += wall_h  # (a man in a tower is a wall unit's, passing through)
		elif k == MapGen.C_STAIR:
			h += wall_h / 2
	return h


## Unit u's height: its ground (or its walkway).
func _unit_elev(u: int) -> int:
	return gh_at(u_cx[u], u_cy[u]) + (wall_h if u_wall[u] > 0 else 0)


## How far an obstacle at (x, y) rises above the ground (line of fire).
func _obs_top(x: int, y: int) -> int:
	var k := obs_kind(x, y)
	if k == MapGen.C_OPEN or k == MapGen.C_DITCH or k == MapGen.C_WATER:
		return 0
	if k == MapGen.C_BUILDING:
		return build_h
	if k == MapGen.C_WALK or k == MapGen.C_STAIR:
		return wall_h
	if k == MapGen.C_TOWER:
		return wall_h + 4 * M
	if k >= MapGen.C_GATE:
		return wall_h + M if g_state[k - MapGen.C_GATE] == GATE_CLOSED else 0
	return wall_h + WALL_PARAPET


## Files of unit u's formation now (squeezed in a street, or as ordered).
func files_of(u: int) -> int:
	return u_sq[u] if u_sq[u] > 0 else u_files[u]


## Unit u is near an obstacle (or on a wall): its men are kept out of
## blocked cells this tick. Coarse 16 m cells round its box and anchor.
func _near_obs(u: int) -> int:
	if u_wall[u] > 0 or u_stair[u] != 0:
		return 1
	var x0 := (mini(u_minx[u], u_ax[u]) - 8 * M) >> 14
	var x1 := (maxi(u_maxx[u], u_ax[u]) + 8 * M) >> 14
	var y0 := (mini(u_miny[u], u_ay[u]) - 8 * M) >> 14
	var y1 := (maxi(u_maxy[u], u_ay[u]) + 8 * M) >> 14
	for j in range(maxi(y0, 0), mini(y1, oc_h - 1) + 1):
		var row := j * oc_w
		for i in range(maxi(x0, 0), mini(x1, oc_w - 1) + 1):
			if obs_c[row + i] != 0:
				return 1
	return 0


## A man of unit u moving from (ox, oy) to (nx, ny) into a cell he may not
## enter: if his unit has a trail (waypoints its anchor passed), he walks
## it (toward the trail point after the one nearest him, or the anchor
## after the newest); else he slides along one axis; else he stays. A man
## already inside a blocked cell may move anywhere (to get out).
func _slide(u: int, ox: int, oy: int, nx: int, ny: int, mask: int) -> Vector2i:
	var on_walk := false
	if u_stair[u] == 1 or u_stair[u] == 3:
		var here := nav_at(ox, oy)
		if (here & (NAV_WALK | NAV_TOWER)) != 0:
			on_walk = true
			mask |= NAV_TOWER  # a man on the walkway may pass a tower (by the junction)
	if (nav_at(ox, oy) & mask) == 0:
		return Vector2i(nx, ny)
	stat_clamp += 1
	var st := maxi(FM.approx_len(nx - ox, ny - oy), M / 4)
	if u_state[u] == U_READY and obs_kind(ox, oy) == MapGen.C_STAIR and (u_stair[u] == 0 or u_stair[u] == 2 \
			or FM.approx_len(stair_pt(u_sseg[u], u_send[u], 1).x - ox, stair_pt(u_sseg[u], u_send[u], 1).y - oy) > 5 * M):
		# In a stair that is not his unit's way (left there after a stair
		# move, or strayed into one): down to its foot (up to its walkway
		# point, his unit being on the wall).
		var fp := _stair_foot(ox, oy, u_wall[u] > 0 and u_stair[u] == 0)
		var fdx := fp.x - ox
		var fdy := fp.y - oy
		var fd := FM.approx_len(fdx, fdy)
		if fd > 0:
			var fx := ox + fdx * mini(st, fd) / fd
			var fy := oy + fdy * mini(st, fd) / fd
			if (nav_at(fx, fy) & mask) != 0:
				return Vector2i(fx, fy)
	if u_wall[u] > 0 and (u_stair[u] == 0 or on_walk):
		# A wall unit spread over two stretches: a man bound for the other
		# stretch goes by the junction in the tower between them.
		var jn := _wall_join(u)
		if jn.z != 0:
			var jx := jn.x - ox
			var jy := jn.y - oy
			var jd := FM.approx_len(jx, jy)
			if jd > M / 2 and jx * (nx - ox) + jy * (ny - oy) > 0:
				var s3 := mini(st, jd)
				var qx := ox + jx * s3 / jd
				var qy := oy + jy * s3 / jd
				if (nav_at(qx, qy) & mask) != 0:
					return Vector2i(qx, qy)
	var cnt_n := u_trn[u]
	if u_state[u] == U_ROUTING and u_stair[u] == 0:
		cnt_n = 0  # the trail lies behind a router: slide along the obstacle instead
	if u_stair[u] == 3 and on_walk:
		cnt_n = 0  # up already: the stair's trail lies behind him
	if cnt_n > 0:
		var base := u * TRAIL
		var best := 0
		var best_d := 1 << 40
		for k in cnt_n:
			var d := FM.approx_len(tr_x[base + k] - ox, tr_y[base + k] - oy)
			if d < best_d:
				best_d = d
				best = k
		var tx := u_ax[u]
		var ty := u_ay[u]
		if u_stair[u] != 0:
			# On a stair move (junction, walkway point, stair, foot): along
			# the trail as in the open (_stair_goal), the anchor past its end.
			var sgo := _stair_goal(u, ox, oy)
			if best + 1 < cnt_n or best_d > 3 * M:
				tx = sgo.x
				ty = sgo.y
		elif best + 1 < cnt_n:
			tx = tr_x[base + best + 1]
			ty = tr_y[base + best + 1]
		elif best_d > 3 * M:
			tx = tr_x[base + best]
			ty = tr_y[base + best]
		var dx := tx - ox
		var dy := ty - oy
		var d2 := FM.approx_len(dx, dy)
		if d2 > 0:
			var s2 := mini(st, d2)
			var px := ox + dx * s2 / d2
			var py := oy + dy * s2 / d2
			if (nav_at(px, py) & mask) != 0:
				return Vector2i(px, py)
			if px != ox and (nav_at(px, oy) & mask) != 0:
				return Vector2i(px, oy)
			if py != oy and (nav_at(ox, py) & mask) != 0:
				return Vector2i(ox, py)
	if nx != ox and (nav_at(nx, oy) & mask) != 0:
		return Vector2i(nx, oy)
	if ny != oy and (nav_at(ox, ny) & mask) != 0:
		return Vector2i(ox, ny)
	return Vector2i(ox, oy)


## The foot (street end) of the stair nearest (x, y) (`top`: its walkway point).
func _stair_foot(x: int, y: int, top: bool = false) -> Vector2i:
	var best := Vector2i(x, y)
	var best_d := 1 << 40
	for k in ws_e.size() / 6:
		var sx := ws_e[k * 6 + 2]
		var sy := ws_e[k * 6 + 3]
		var d := FM.approx_len(sx - x, sy - y)
		if d < best_d:
			best_d = d
			best = Vector2i(ws_e[k * 6], ws_e[k * 6 + 1]) if top else Vector2i(ws_e[k * 6 + 4], ws_e[k * 6 + 5])
	return best


## A man at (x, y) of unit u on a stair move (mode 1 down, 3 up) who is
## still on the level it is leaving (walkway or tower going down, anything
## else going up): where he heads (z 1), else z 0 (he takes his place).
func _stair_leave(u: int, x: int, y: int, mode: int, s: int = 0) -> Vector3i:
	if mode == ST_LADDER:
		# Climbing ladders: a man below waits his turn in his ladder's queue
		# (_ladder_step chose it this tick).
		if _on_walk(x, y):
			return Vector3i.ZERO
		var k := u_slot_base[u] + s
		return Vector3i(_lw_x[k], _lw_y[k], 1)
	var nvh := nav_at(x, y)
	if ((nvh & (NAV_WALK | NAV_TOWER)) != 0) != (mode == 1):
		return Vector3i.ZERO
	var g := _stair_goal(u, x, y)
	return Vector3i(g.x, g.y, 1)


## The cells a man at (x, y) of a unit on a stair move (mode 1 down, 3 up)
## may step into: on the walkway (or in a tower) the walkway and towers, and
## going down the stairs (he leaves the wall only by a stair); elsewhere
## his unit's (`mask`), the walls' cells only near his unit's stair.
func _stair_mask(u: int, x: int, y: int, mask: int, mode: int) -> int:
	if mode == ST_LADDER:
		# Climbing ladders: men up keep to the walkway and towers, men below
		# to the ground.
		return NAV_WALK | NAV_TOWER if _on_walk(x, y) else _ground_mask(u)
	if (nav_at(x, y) & (NAV_WALK | NAV_TOWER)) != 0:
		# Going up he is up: walkway and towers only (not back into the stair).
		return (MapGen.NAV_WALL if mode == 1 else NAV_WALK) | NAV_TOWER
	var sp := stair_pt(u_sseg[u], u_send[u], 1)
	if FM.approx_len(sp.x - x, sp.y - y) > 5 * M:
		return mask & ~MapGen.NAV_WALL  # off the walls but by his unit's stair
	return mask


## Where a man at (x, y) of unit u on a stair move heads along its trail:
## the point after the one he has reached (within 2.5 m) or passed (he is
## nearer the next one than it is), else the nearest; the last point once
## there.
func _stair_goal(u: int, x: int, y: int) -> Vector2i:
	var base := u * TRAIL
	var cnt := u_trn[u]
	if u_stair[u] == 3 and cnt == 3 and obs_kind(x, y) == MapGen.C_STAIR \
			and FM.approx_len(tr_x[base + 1] - x, tr_y[base + 1] - y) <= 4 * M:
		return Vector2i(tr_x[base + 2], tr_y[base + 2])  # on its stair: up onto the walkway
	var best := 0
	var best_d := 1 << 40
	for k in cnt:
		var d := FM.approx_len(tr_x[base + k] - x, tr_y[base + k] - y)
		if d < best_d:
			best_d = d
			best = k
	if best + 1 < cnt:
		var gap := FM.approx_len(tr_x[base + best + 1] - tr_x[base + best], tr_y[base + best + 1] - tr_y[base + best])
		var dn := FM.approx_len(tr_x[base + best + 1] - x, tr_y[base + best + 1] - y)
		if best_d <= 2560 or dn < gap:
			best += 1
	if u_stair[u] == 1 or u_stair[u] == 3:
		# No clear way to it (a wall between: men in a tower on the junction
		# went for the stair through the wall instead of by the walkway point,
		# and stood there until STAIR_MAX): the trail point before it, if
		# that one is clear.
		var mm := _stair_mask(u, x, y, _mask_of(u), u_stair[u])
		if not _way_clear(x, y, tr_x[base + best], tr_y[base + best], mm):
			var b := best - 1
			while b >= 0 and not _way_clear(x, y, tr_x[base + b], tr_y[base + b], mm):
				b -= 1
			if b >= 0:
				best = b
			elif u_stair[u] == 1 and (nav_at(x, y) & NAV_WALK) != 0:
				# On the walkway with no clear way to any of it (a bend of the
				# walkway between): along its stretch's centre line, 4 m at a
				# time, toward the stair's end.
				var sg := u_sseg[u]
				var t0 := seg_t(self, sg, x, y)
				var t1 := maxi(t0 - 4 * M, 0) if u_send[u] == 0 else mini(t0 + 4 * M, seg_len(self, sg))
				return seg_pt(self, sg, t1)
	return Vector2i(tr_x[base + best], tr_y[base + best])


## Every metre from (x0, y0) to (x1, y1) passable for `mask`.
func _way_clear(x0: int, y0: int, x1: int, y1: int, mask: int) -> bool:
	var nk := FM.approx_len(x1 - x0, y1 - y0) / M + 1
	for k in range(1, nk + 1):
		if (nav_at(x0 + (x1 - x0) * k / nk, y0 + (y1 - y0) * k / nk) & mask) == 0:
			return false
	return true


## Append a passed waypoint to unit u's trail (the oldest drops out).
func _trail_push(u: int, x: int, y: int) -> void:
	var base := u * TRAIL
	var cnt_n := u_trn[u]
	if cnt_n > 0 and tr_x[base + cnt_n - 1] == x and tr_y[base + cnt_n - 1] == y:
		return
	if cnt_n >= TRAIL:
		for k in TRAIL - 1:
			tr_x[base + k] = tr_x[base + k + 1]
			tr_y[base + k] = tr_y[base + k + 1]
		cnt_n = TRAIL - 1
	tr_x[base + cnt_n] = x
	tr_y[base + cnt_n] = y
	u_trn[u] = cnt_n + 1


## 1 if a melee search from (x, y) must check for obstacles in the way
## (an obstacle within a 16 m cell of him), else 0.
func _reach_checks(x: int, y: int) -> int:
	if obs_on == 0:
		return 0
	var i := clampi(x >> 14, 0, oc_w - 1)
	var j := clampi(y >> 14, 0, oc_h - 1)
	return obs_cd[j * oc_w + i]


## Two men can reach each other (melee): nothing impassable between them
## (a wall, a closed gate, a building corner). Midpoint and quarter points.
func _reach_ok(x0: int, y0: int, x1: int, y1: int) -> bool:
	# Over ground (or a ditch, a stair's foot) only: a man on a walkway is
	# out of reach from below, and the walkway between two men on either
	# side of a wall is not a way through it.
	var gm := MapGen.NAV_GROUND | MapGen.NAV_DITCH
	if (nav_at((x0 + x1) >> 1, (y0 + y1) >> 1) & gm) == 0:
		# Up on the walls (attackers come up by ladders): man to man along
		# the walkway and towers.
		if sg_on != 0:
			var wb := NAV_WALK | NAV_TOWER
			return (nav_at((x0 + x1) >> 1, (y0 + y1) >> 1) & wb) != 0 and (nav_at(x0, y0) & wb) != 0 \
				and (nav_at(x1, y1) & wb) != 0
		return false
	if (nav_at(x0, y0) & gm) == 0 or (nav_at(x1, y1) & gm) == 0:
		return false
	var dx := x1 - x0
	var dy := y1 - y0
	if absi(dx) + absi(dy) > 3 * M:
		if (nav_at(x0 + dx / 4, y0 + dy / 4) & gm) == 0 or (nav_at(x1 - dx / 4, y1 - dy / 4) & gm) == 0:
			return false
	return true


## A clear line 3 m wide (centre and 1.5 m either side, every metre) for
## ground units from (x0, y0) to (x1, y1).
func _los_fat(x0: int, y0: int, x1: int, y1: int, mask: int = MapGen.NAV_GROUND) -> bool:
	var dx := x1 - x0
	var dy := y1 - y0
	var l := FM.approx_len(dx, dy)
	if l <= 0:
		return (nav_at(x0, y0) & mask) != 0
	var cnt_n := l / M + 1
	var ox := -dy * 1536 / l
	var oy := dx * 1536 / l
	var navg := nav
	var w := ob_w
	var h := ob_h
	var q := 0
	while q <= cnt_n:
		var x := x0 + dx * q / cnt_n
		var y := y0 + dy * q / cnt_n
		# No obstacle within the 16 m cells round here: the next 8 m of the
		# line (and 1.5 m either side) are clear without looking.
		if x > 12 * M and y > 12 * M and x < field_w - 12 * M and y < field_h - 12 * M:
			var ci := x >> 14
			var cj := y >> 14
			if ci < oc_w and cj < oc_h and obs_cd[cj * oc_w + ci] == 0:
				q += 8
				continue
		q += 1
		for k in 3:
			var sx := x + ox * (k - 1)
			var sy := y + oy * (k - 1)
			if sx < 0 or sy < 0:
				return false
			var i := sx >> 11
			var j := sy >> 11
			if i >= w or j >= h or (navg[j * w + i] & mask) == 0:
				return false
	return true


## The cells unit u's men may stand in: the walkway on a wall, both (and
## the stairs) on a stair move, the ground (foot also a ditch) otherwise.
func _mask_of(u: int) -> int:
	if u_stair[u] == 1 or u_stair[u] == 3:
		return MapGen.NAV_WALL | MapGen.NAV_GROUND | MapGen.NAV_DITCH
	if u_wall[u] > 0:
		return MapGen.NAV_WALL | NAV_TOWER
	return _ground_mask(u)


## Ground cells unit u can cross: foot (infantry, pikes, missile troops)
## also a ditch; horses and engines not.
func _ground_mask(u: int) -> int:
	var c := u_cls[u]
	if city_ditch != 0 and (c == UT.CLS_INF or c == UT.CLS_PIKE or c == UT.CLS_MISSILE) and not carries_ram(u):
		return MapGen.NAV_GROUND | MapGen.NAV_DITCH
	return MapGen.NAV_GROUND


## Street graph node usable now (a closed gate's node is not).
func _node_open(k: int) -> bool:
	var g := ng_gate[k]
	return g < 0 or g_state[g] != GATE_CLOSED


## Up to `most` graph nodes near (x, y) with a clear line to it (the nearest
## open node if none is clear), nearest first (ties: lower index).
func _near_nodes(x: int, y: int, most: int = 3, mask: int = MapGen.NAV_GROUND) -> PackedInt32Array:
	var cnt_n := ng_x.size()
	var cand := PackedInt32Array()
	var cd := PackedInt32Array()
	for k in cnt_n:
		if not _node_open(k):
			continue
		var dx := ng_x[k] - x
		var dy := ng_y[k] - y
		var d := FM.approx_len(dx, dy)
		# Insert into the six nearest.
		var pos := cand.size()
		while pos > 0 and (cd[pos - 1] > d or (cd[pos - 1] == d and cand[pos - 1] > k)):
			pos -= 1
		if pos < 6:
			cand.insert(pos, k)
			cd.insert(pos, d)
			if cand.size() > 6:
				cand.resize(6)
				cd.resize(6)
	var out := PackedInt32Array()
	for k in cand.size():
		if _los_fat(x, y, ng_x[cand[k]], ng_y[cand[k]], mask):
			out.append(cand[k])
			if out.size() >= most:
				break
	if out.is_empty() and not cand.is_empty():
		out.append(cand[0])
	return out


## Graph distances (1/8 m) from every node to node `dst` with the gates as
## they are now (Dijkstra, binary heap; cached until a gate changes). At
## most DIST_PER_TICK new tables a tick (unless `force`): past that it
## returns an empty array and the caller keeps its old path for now, so a
## gate falling spreads the work over the next ticks. Which tables exist is
## state (_dist_have: snapshotted, rebuilt by restore()).
func _dist_table(dst: int, force: bool = false) -> PackedInt32Array:
	if _dist_epoch != nav_epoch:
		_dist_cache = {}
		_dist_epoch = nav_epoch
		_dist_have = PackedInt32Array()
	if _dist_cache.has(dst):
		return _dist_cache[dst]
	if not force:
		if _dist_new >= DIST_PER_TICK:
			return PackedInt32Array()
		_dist_new += 1
	_dist_have.append(dst)
	var dist := _dijkstra(dst)
	_dist_cache[dst] = dist
	return dist


func _dijkstra(dst: int) -> PackedInt32Array:
	var cnt_n := ng_x.size()
	var dist := PackedInt32Array()
	dist.resize(cnt_n)
	dist.fill(PATH_INF)
	var heap := PackedInt32Array()
	dist[dst] = 0
	heap.append(dst)  # key = d * 4096 + node
	while not heap.is_empty():
		var top := heap[0]
		var last := heap[heap.size() - 1]
		heap.resize(heap.size() - 1)
		if not heap.is_empty():
			# Sift the last key down from the root.
			var i := 0
			var hn := heap.size()
			while true:
				var c := 2 * i + 1
				if c >= hn:
					break
				if c + 1 < hn and heap[c + 1] < heap[c]:
					c += 1
				if heap[c] >= last:
					break
				heap[i] = heap[c]
				i = c
			heap[i] = last
		var d := top >> 12
		var v := top & 4095
		if d > dist[v]:
			continue
		for e in range(ng_e0[v], ng_e0[v + 1]):
			var to := ng_to[e]
			if not _node_open(to):
				continue
			var nd := d + ng_w[e]
			if nd < dist[to]:
				dist[to] = nd
				var key := nd * 4096 + to
				heap.append(key)
				var j := heap.size() - 1
				while j > 0:
					var par := (j - 1) >> 1
					if heap[par] <= key:
						break
					heap[j] = heap[par]
					j = par
				heap[j] = key
	return dist


## Plan unit u's path from its anchor to (gx, gy): straight if the way is
## clear, else over the street graph (entry node near the anchor, exit node
## near the goal, the cheapest pair), shortcut where the line is clear.
func _plan_path(u: int, gx: int, gy: int) -> void:
	var ax := u_ax[u]
	var ay := u_ay[u]
	var gm := _ground_mask(u)
	var straight := ng_x.is_empty() or _los_fat(ax, ay, gx, gy, gm)
	var srcs := PackedInt32Array()
	var dsts := PackedInt32Array()
	var tables: Array = []
	if not straight:
		srcs = _near_nodes(ax, ay, 3, gm)
		dsts = _near_nodes(gx, gy, 2, gm)  # each exit node needs a distance table
		for b in dsts:
			# (A unit stuck a while gets its table now: with the budget taken
			# by lower units every tick, one went straight at its goal into a
			# house for half a minute.)
			var dt := _dist_table(b, obs_on != 0 and u_stuck[u] >= STUCK_FLOW)
			if dt.is_empty():
				# Over this tick's budget: keep the old path a little longer,
				# or (none yet) head straight for the goal and plan again
				# within half a second.
				if u_pn[u] == 0:
					u_pgx[u] = gx
					u_pgy[u] = gy
					u_pep[u] = -1
					u_pk[u] = 0
					u_pn[u] = 1
					pth_x[u * PATH_MAX] = gx
					pth_y[u * PATH_MAX] = gy
				return
			tables.append(dt)
	stat_paths += 1
	var base := u * PATH_MAX
	u_pgx[u] = gx
	u_pgy[u] = gy
	u_pep[u] = nav_epoch
	u_pk[u] = 0
	u_pn[u] = 1
	pth_x[base] = gx
	pth_y[base] = gy
	if straight:
		return
	var best := PATH_INF
	var ba := -1
	var bb := -1
	var bi := -1
	for di in dsts.size():
		var b := dsts[di]
		var dt: PackedInt32Array = tables[di]
		var tail := FM.approx_len(gx - ng_x[b], gy - ng_y[b]) / 128
		for a in srcs:
			if dt[a] >= PATH_INF:
				continue
			var c := FM.approx_len(ng_x[a] - ax, ng_y[a] - ay) / 128 + dt[a] + tail
			if c < best:
				best = c
				ba = a
				bb = b
				bi = di
	if ba < 0:
		return  # no way round (every gate shut): straight on
	var dtb: PackedInt32Array = tables[bi]
	var k := 0
	var cur := ba
	pth_x[base] = ng_x[cur]
	pth_y[base] = ng_y[cur]
	k = 1
	while cur != bb and k < PATH_MAX - 1:
		var nxt := -1
		var nv := PATH_INF
		for e in range(ng_e0[cur], ng_e0[cur + 1]):
			var to := ng_to[e]
			if not _node_open(to):
				continue
			var c2 := ng_w[e] + dtb[to]
			if c2 < nv or (c2 == nv and to < nxt):
				nv = c2
				nxt = to
		if nxt < 0 or dtb[nxt] >= dtb[cur]:
			break
		cur = nxt
		pth_x[base + k] = ng_x[cur]
		pth_y[base + k] = ng_y[cur]
		k += 1
	pth_x[base + k] = gx
	pth_y[base + k] = gy
	u_pn[u] = k + 1
	# Shortcut: skip waypoints the anchor can already see past.
	var pk := 0
	while pk + 1 < u_pn[u] - 1 and _los_fat(ax, ay, pth_x[base + pk + 1], pth_y[base + pk + 1], gm):
		pk += 1
	u_pk[u] = pk
	# Where the unit is now heads its trail (stragglers make for it first).
	_trail_push(u, ax, ay)


## The way a unit's anchor at (ax, ay) would go to (gx, gy) through the
## streets (planned as _plan_path plans it, but read-only: no state, no
## cache): the waypoints, interleaved x, y, (gx, gy) last; empty if every
## way there is shut. For the view (route previews, refusals).
func route_to(ax: int, ay: int, gx: int, gy: int, gm: int = MapGen.NAV_GROUND) -> PackedInt32Array:
	var out := PackedInt32Array()
	if ng_x.is_empty() or _los_fat(ax, ay, gx, gy, gm):
		out.append_array([gx, gy])
		return out
	var srcs := _near_nodes(ax, ay, 3, gm)
	var dsts := _near_nodes(gx, gy, 2, gm)
	var best := PATH_INF
	var ba := -1
	var bt := PackedInt32Array()
	var bb := -1
	for b in dsts:
		var dt := _dijkstra(b)
		var tail := FM.approx_len(gx - ng_x[b], gy - ng_y[b]) / 128
		for a in srcs:
			if dt[a] >= PATH_INF:
				continue
			var c := FM.approx_len(ng_x[a] - ax, ng_y[a] - ay) / 128 + dt[a] + tail
			if c < best:
				best = c
				ba = a
				bb = b
				bt = dt
	if ba < 0:
		return out
	var cur := ba
	out.append_array([ng_x[cur], ng_y[cur]])
	var k := 1
	while cur != bb and k < PATH_MAX - 1:
		var nxt := -1
		var nv := PATH_INF
		for e in range(ng_e0[cur], ng_e0[cur + 1]):
			var to := ng_to[e]
			if not _node_open(to):
				continue
			var c2 := ng_w[e] + bt[to]
			if c2 < nv or (c2 == nv and to < nxt):
				nv = c2
				nxt = to
		if nxt < 0 or bt[nxt] >= bt[cur]:
			break
		cur = nxt
		out.append_array([ng_x[cur], ng_y[cur]])
		k += 1
	out.append_array([gx, gy])
	# Shortcut as _plan_path does: skip waypoints it can already see past.
	var pk := 0
	var cnt := out.size() / 2
	while pk + 1 < cnt - 1 and _los_fat(ax, ay, out[(pk + 1) * 2], out[(pk + 1) * 2 + 1], gm):
		pk += 1
	return out.slice(pk * 2)


## Keep unit u's path to (gx, gy) current: replan when there is none, a gate
## changed, or (`moving_goal`, at most once a second) the goal moved 12 m;
## look past the next waypoint now and then. Returns the point to head for.
func _path_point(u: int, gx: int, gy: int, moving_goal: bool) -> Vector2i:
	if u_pn[u] == 0 or (u_pep[u] != nav_epoch and (u + tick) % 5 == 0):
		# (A gate changed: replans are spread over half a second.)
		_plan_path(u, gx, gy)
	elif moving_goal and (u + tick) % 10 == 0 \
			and FM.approx_len(gx - u_pgx[u], gy - u_pgy[u]) > (12 * M if u_stuck[u] < STUCK_ROUTE else 48 * M):
		# (Stuck: it keeps the way it has unless the goal is far off it; a
		# goal jumping about, a unit split round a house, had it plan, turn
		# back a step, plan again, for minutes.)
		_plan_path(u, gx, gy)
	elif not moving_goal and (u_pgx[u] != gx or u_pgy[u] != gy):
		_plan_path(u, gx, gy)
	var base := u * PATH_MAX
	var k := u_pk[u]
	var last := u_pn[u] - 1
	if k >= last:
		return Vector2i(gx, gy)
	var wx := pth_x[base + k]
	var wy := pth_y[base + k]
	var wd := FM.approx_len(wx - u_ax[u], wy - u_ay[u])
	if wd <= WP_REACH and (wd <= M or _way_clear(u_ax[u], u_ay[u], pth_x[base + k + 1] if k + 1 < last else gx,
			pth_y[base + k + 1] if k + 1 < last else gy, _ground_mask(u))):
		# (Reached, unless the way on to the next is not straight from here:
		# then on to the waypoint itself. A unit 3.5 m to the side of one
		# went for the next straight into a house's corner, 2026-10-09.)
		_trail_push(u, wx, wy)
		k += 1
		u_pk[u] = k
	elif (u + tick) % 5 == 0 and k + 1 <= last:
		var b1 := base + k + 1
		var nxx := pth_x[b1] if k + 1 < last else gx
		var nxy := pth_y[b1] if k + 1 < last else gy
		if FM.approx_len(nxx - u_ax[u], nxy - u_ay[u]) < 60 * M and _los_fat(u_ax[u], u_ay[u], nxx, nxy, _ground_mask(u)):
			_trail_push(u, wx, wy)
			k += 1
			u_pk[u] = k
	if k >= last:
		return Vector2i(gx, gy)
	return Vector2i(pth_x[base + k], pth_y[base + k])


## Unit u's men are cut off from its anchor (a wall or houses between): the
## anchor goes back to the man nearest their centre (on open ground) and
## the unit plans its way again from there.
func _regroup(u: int, back: bool = false) -> void:
	var best := -1
	var best_d := 1 << 40
	var base := u_slot_base[u]
	var ra := reach_at(u_ax[u], u_ay[u])
	for s in u_alive[u]:
		var i := slot_soldier[base + s]
		if state[i] >= S_DEAD or (nav_at(pos_x[i], pos_y[i]) & MapGen.NAV_GROUND) == 0:
			continue
		var d := FM.approx_len(pos_x[i] - u_cx[u], pos_y[i] - u_cy[u])
		if back:
			# (Stuck release, its men strung out: back to the man farthest
			# from the anchor on its own ground, so the stragglers stuck
			# behind a house walk on with it.)
			if ra >= 0 and reach_at(pos_x[i], pos_y[i]) != ra:
				continue
			d = -FM.approx_len(pos_x[i] - u_ax[u], pos_y[i] - u_ay[u])
		if d < best_d:
			best_d = d
			best = i
	u_lagt[u] = 0
	if best < 0:
		return
	u_ax[u] = pos_x[best]
	u_ay[u] = pos_y[best]
	u_pn[u] = 0
	u_trn[u] = 0
	u_sq[u] = 0
	u_dirty[u] = 1
	u_settled[u] = 0
	stat_regroup += 1


## Where unit u heads to reach enemy unit t on a settlement map: its centre,
## or (when that lies in a wall or a house: its men are split round it) its
## anchor, else its man nearest to u.
func _attack_goal(u: int, t: int) -> Vector2i:
	var gm := _ground_mask(u)
	if (nav_at(u_cx[t], u_cy[t]) & gm) != 0:
		return Vector2i(u_cx[t], u_cy[t])
	if (nav_at(u_ax[t], u_ay[t]) & gm) != 0:
		return Vector2i(u_ax[t], u_ay[t])
	var best := Vector2i(u_cx[t], u_cy[t])
	var best_d := 1 << 40
	var base := u_slot_base[t]
	for s in u_alive[t]:
		var i := slot_soldier[base + s]
		if state[i] >= S_DEAD or (nav_at(pos_x[i], pos_y[i]) & gm) == 0:
			continue
		var dd := FM.approx_len(pos_x[i] - u_ax[u], pos_y[i] - u_ay[u])
		if dd < best_d:
			best_d = dd
			best = Vector2i(pos_x[i], pos_y[i])
	return best


## Squeeze: a unit whose front line would not fit between the obstacles
## either side of its anchor closes files to the width there (at least
## MIN_FILES), and opens out again once there is room (2 m to spare).
func _squeeze(u: int) -> void:
	var ty := u_type[u]
	var fsp := t_fsp[ty]
	var want := mini(u_files[u], u_alive[u])
	var half := want * fsp / 2 + M
	var c := FM.cos_a(u_face[u])
	var s := FM.sin_a(u_face[u])
	var ax := u_ax[u]
	var ay := u_ay[u]
	if (nav_at(ax, ay) & MapGen.NAV_GROUND) == 0:
		return
	var fl := 0
	var fr := 0
	var stp := 2 * M
	while fl < half and (nav_at(ax + s * (fl + stp) / FM.TRIG_ONE, ay - c * (fl + stp) / FM.TRIG_ONE) & MapGen.NAV_GROUND) != 0:
		fl += stp
	while fr < half and (nav_at(ax - s * (fr + stp) / FM.TRIG_ONE, ay + c * (fr + stp) / FM.TRIG_ONE) & MapGen.NAV_GROUND) != 0:
		fr += stp
	var width := fl + fr + M
	var sq := 0
	if width < want * fsp:
		sq = clampi(width / fsp, mini(MIN_FILES, want), want)
		if sq >= want:
			sq = 0
	elif u_sq[u] > 0 and width < want * fsp + 2 * M:
		sq = u_sq[u]  # not quite room yet
	if sq != u_sq[u]:
		if sq > 0 and u_sq[u] == 0:
			stat_squeeze += 1
		u_sq[u] = sq
		u_dirty[u] = 1
		u_settled[u] = 0
	if sq > 0 and u_order[u] != O_NONE and absi(fl - fr) > 2 * M and u_stair[u] != 2 \
			and not (u_order[u] == O_MOVE and FM.approx_len(u_dx[u] - ax, u_dy[u] - ay) <= REFORM_IN_PLACE_DIST):
		# Keep to the middle of the street (a metre at a time: at a corner
		# the free width either side can flip from one check to the next).
		# Not on the last stretch of a move (it faces its final way there,
		# so the shift went back along its way and it never arrived: units
		# 2-3 m short of their places for minutes, 2026-10-09).
		var sh := clampi((fr - fl) / 2, -M, M)
		u_ax[u] = clampi(ax - s * sh / FM.TRIG_ONE, 0, field_w)
		u_ay[u] = clampi(ay + c * sh / FM.TRIG_ONE, 0, field_h)


## Walls (how a unit stands on one, where a move onto one goes). Static
## where the order rule and the view's preview need them (`sim` is the
## BattleSim), so the preview draws exactly what the sim will do.

## Length of walkway segment sg (sim units, at least 1).
static func seg_len(sim, sg: int) -> int:
	var dx: int = sim.ws_x1[sg] - sim.ws_x0[sg]
	var dy: int = sim.ws_y1[sg] - sim.ws_y0[sg]
	return maxi(FM.isqrt(dx * dx + dy * dy), 1)


## How far along segment sg (x, y) lies, clamped to the segment.
static func seg_t(sim, sg: int, x: int, y: int) -> int:
	var dx: int = sim.ws_x1[sg] - sim.ws_x0[sg]
	var dy: int = sim.ws_y1[sg] - sim.ws_y0[sg]
	var l := seg_len(sim, sg)
	return clampi(((x - sim.ws_x0[sg]) * dx + (y - sim.ws_y0[sg]) * dy) / l, 0, l)


## The point t along segment sg's walkway centre line.
static func seg_pt(sim, sg: int, t: int) -> Vector2i:
	var l := seg_len(sim, sg)
	return Vector2i(sim.ws_x0[sg] + (sim.ws_x1[sg] - sim.ws_x0[sg]) * t / l,
		sim.ws_y0[sg] + (sim.ws_y1[sg] - sim.ws_y0[sg]) * t / l)


## Unit u may go up on the walls: a defending foot or missile unit on a
## map with walkways (attackers never: no ladders yet; no horses, pikes or
## engines).
static func can_man_walls(sim, u: int) -> bool:
	if sim.city_on == 0 or sim.ws_x0.size() == 0 or sim.u_side[u] != sim.city_def or carrying(sim, u) != 0:
		return false
	var c: int = sim.u_cls[u]
	return c == UT.CLS_INF or c == UT.CLS_MISSILE


## A move to (x, y) on the wall: if (x, y) is on a wall's body, walkway,
## stair, tower or gate tower, the walkway point of the stretch it belongs
## to (the nearest stretch within WALL_SNAP of it, ties to the lower index;
## the nearest point of its centre line), as (x, y, stretch); else stretch
## -1. A gateway, the ground and the sea are not the wall.
static func wall_snap(sim, x: int, y: int) -> Vector3i:
	if sim.city_on == 0 or sim.ws_x0.size() == 0:
		return Vector3i(x, y, -1)
	var k: int = sim.obs_kind(x, y)
	if k != MapGen.C_WALL and k != MapGen.C_WALK and k != MapGen.C_TOWER and k != MapGen.C_STAIR:
		return Vector3i(x, y, -1)
	var best := -1
	var best_o := WALL_SNAP + 1
	for sg in sim.ws_x0.size():
		var o: int = sim._seg_off(sg, x, y)
		if o < best_o:
			best_o = o
			best = sg
	if best < 0:
		return Vector3i(x, y, -1)
	var p := seg_pt(sim, best, seg_t(sim, best, x, y))
	return Vector3i(p.x, p.y, best)


## Files of a unit `count` strong on a wall: two ranks (one man: one).
static func wall_nf(count: int) -> int:
	return maxi((count + 1) / 2, 1)


## A unit `count` strong of type ty taking stretch sg at (x, y): its anchor
## (on the walkway centre line, facing out). It stands in two ranks centred
## on (x, y), moved along so the whole line is on the stretch; a line longer
## than the stretch fills it and goes on through a tower onto the joined
## stretch on the side nearer (x, y): its anchor is then (x, y) itself.
static func wall_anchor(sim, sg: int, x: int, y: int, count: int, ty: int) -> Vector3i:
	var l := seg_len(sim, sg)
	var w := wall_nf(count) * UT.stat(ty, "file_sp")
	var t := seg_t(sim, sg, x, y)
	if w <= l:
		t = clampi(t, w / 2, l - (w - w / 2))
	var p := seg_pt(sim, sg, t)
	return Vector3i(p.x, p.y, sim.ws_dir[sg])


## The end of stretch sg a line too long for it goes on from (anchor at
## (ax, ay)): the nearer end if a stretch is joined there, else the other;
## -1 if neither end is joined.
static func spill_end(sim, sg: int, ax: int, ay: int) -> int:
	var e := 0 if 2 * seg_t(sim, sg, ax, ay) < seg_len(sim, sg) else 1
	if sim.ws_nb[sg * 2 + e] < 0:
		e = 1 - e
	return e if sim.ws_nb[sg * 2 + e] >= 0 else -1


## The file positions of a wall line: `nf` files fsp apart on the walkway
## centre lines, anchored at (ax, ay) on stretch sg (see wall_anchor):
## (x, y, stretch) per file, in order along the wall. Files that fit on
## neither stretch stand at the line's two ends, alternately.
static func wall_files_at(sim, sg: int, ax: int, ay: int, nf: int, fsp: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var l := seg_len(sim, sg)
	var fit := l / fsp
	if nf <= fit:
		var t0 := clampi(seg_t(sim, sg, ax, ay) - nf * fsp / 2, 0, l - nf * fsp)
		for k in nf:
			var p := seg_pt(sim, sg, t0 + fsp / 2 + k * fsp)
			out.append_array([p.x, p.y, sg])
		return out
	fit = maxi(fit, 1)
	var t1 := (l - fit * fsp) / 2 + fsp / 2
	var e := spill_end(sim, sg, ax, ay)
	var main := PackedInt32Array()
	for k in fit:
		var p := seg_pt(sim, sg, clampi(t1 + k * fsp, 0, l))
		main.append_array([p.x, p.y, sg])
	var side := PackedInt32Array()  # the joined stretch's files, from the junction outward
	if e >= 0:
		var nb: int = sim.ws_nb[sg * 2 + e]
		var s2 := nb / 2
		var l2 := seg_len(sim, s2)
		var n2 := mini(nf - fit, l2 / fsp)
		for k in n2:
			var t2 := fsp / 2 + k * fsp
			var p2 := seg_pt(sim, s2, t2 if nb % 2 == 0 else l2 - t2)
			side.append_array([p2.x, p2.y, s2])
	if e == 0:
		# Along the wall: the joined stretch (far end first), then this one.
		for k in range(side.size() / 3 - 1, -1, -1):
			out.append_array([side[k * 3], side[k * 3 + 1], side[k * 3 + 2]])
		out.append_array(main)
	else:
		out.append_array(main)
		out.append_array(side)
	var have := out.size() / 3
	for k in nf - have:
		var q := 0 if k % 2 == 0 else have - 1
		out.append_array([out[q * 3], out[q * 3 + 1], out[q * 3 + 2]])
	return out


## Where the men of a unit `count` strong of type ty stand on a wall,
## anchored at (ax, ay) on stretch sg: interleaved x, y per slot (absolute).
## Two ranks either side of the walkway's centre line (at most WALL_RG
## apart; the back rank's last files centred), each man moved to the
## nearest walkway cell if his place falls off it.
static func wall_slots(sim, sg: int, ax: int, ay: int, count: int, ty: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(count * 2)
	if count <= 0:
		return out
	var nf := wall_nf(count)
	var files := wall_files_at(sim, sg, ax, ay, nf, UT.stat(ty, "file_sp"))
	var half := mini(UT.stat(ty, "rank_sp"), WALL_RG) / 2
	var back_n := count - nf
	for s in count:
		var r := s / nf
		var f := s - r * nf
		var off := half
		if r > 0:
			off = -half
			f += (nf - back_n) / 2
		if count == 1:
			off = 0
		var fx := files[f * 3]
		var fy := files[f * 3 + 1]
		var dir: int = sim.ws_dir[files[f * 3 + 2]]
		var nx := FM.cos_a(dir)
		var ny := FM.sin_a(dir)
		var px := fx + nx * off / FM.TRIG_ONE
		var py := fy + ny * off / FM.TRIG_ONE
		if sim.obs_kind(px, py) != MapGen.C_WALK:
			# Off the walkway (the grid is 2 m): the nearest walkway spot.
			for q in WALL_NUDGE.size() / 2:
				var a: int = WALL_NUDGE[q * 2]
				var b: int = WALL_NUDGE[q * 2 + 1]
				var qx := fx + (nx * a - ny * b) / FM.TRIG_ONE
				var qy := fy + (ny * a + nx * b) / FM.TRIG_ONE
				if sim.obs_kind(qx, qy) == MapGen.C_WALK:
					px = qx
					py = qy
					break
		out[s * 2] = px
		out[s * 2 + 1] = py
	return out


## Tries for a man off the walkway: (out, along) from his file's point.
const WALL_NUDGE: Array[int] = [0, 0, 512, 0, -512, 0, 0, 512, 0, -512, 512, 512, -512, 512,
	512, -512, -512, -512, 1024, 0, -1024, 0, 0, 1024, 0, -1024]


## Wall unit u spread over two stretches: the junction its men pass by (z 1),
## else z 0.
func _wall_join(u: int) -> Vector3i:
	var sg := u_wall[u] - 1
	if wall_nf(u_alive[u]) * t_fsp[u_type[u]] <= seg_len(self, sg):
		return Vector3i.ZERO
	var e := spill_end(self, sg, u_ax[u], u_ay[u])
	if e < 0:
		return Vector3i.ZERO
	return Vector3i(ws_jx[sg * 2 + e], ws_jy[sg * 2 + e], 1)


## Formation offsets of wall unit u (its wall line, see wall_slots).
func _wall_offsets(u: int) -> void:
	var sl := wall_slots(self, u_wall[u] - 1, u_ax[u], u_ay[u], u_alive[u], u_type[u])
	var base := u_slot_base[u]
	for s in u_alive[u]:
		off_x[base + s] = sl[s * 2] - u_ax[u]
		off_y[base + s] = sl[s * 2 + 1] - u_ay[u]


## (x, y) is on unit u's own stretch of wall (a move there keeps it on it).
func on_own_stretch(u: int, x: int, y: int) -> bool:
	return u_wall[u] > 0 and wall_snap(self, x, y).z == u_wall[u] - 1


## Where a wall unit at (x, y) on stretch sg comes down to ("Come down"):
## the foot of the stretch's stair nearer (x, y), in the street just inside
## the wall (the stair it goes down by; nothing in the way from there).
func wall_inside(sg: int, x: int, y: int) -> Vector2i:
	return stair_pt(sg, descent_end(self, sg, x, y, false, 0, 0), 2)


## "Man the wall" for unit u on the ground: the walkway point it goes to,
## (x, y, stretch): of the stretches within MAN_WALL_R of its anchor, the one
## nearest the nearest enemy unit (ties: the lower index), at its point
## nearest the unit; stretch -1 if there is none (or u may not man walls).
## Read-only: the view turns it into an ordinary move order.
static func man_wall_target(sim, u: int) -> Vector3i:
	if not can_man_walls(sim, u) or sim.u_wall[u] > 0:
		return Vector3i(0, 0, -1)
	var ax: int = sim.u_ax[u]
	var ay: int = sim.u_ay[u]
	var en := -1
	var en_d := 0
	for t in sim.n_units:
		if sim.u_side[t] == sim.u_side[u] or sim.u_state[t] >= U_DESTROYED or sim.u_alive[t] <= 0:
			continue
		var d := FM.approx_len(sim.u_cx[t] - ax, sim.u_cy[t] - ay)
		if en < 0 or d < en_d:
			en = t
			en_d = d
	var best := -1
	var best_s := 0
	for sg in sim.ws_x0.size():
		if sim._seg_off(sg, ax, ay) > MAN_WALL_R:
			continue
		var sc: int = sim._seg_off(sg, sim.u_cx[en], sim.u_cy[en]) if en >= 0 else sim._seg_off(sg, ax, ay)
		if best < 0 or sc < best_s:
			best = sg
			best_s = sc
	if best < 0:
		return Vector3i(0, 0, -1)
	var p := seg_pt(sim, best, seg_t(sim, best, ax, ay))
	return Vector3i(p.x, p.y, best)


## Files a unit forms coming down off a wall: its normal block (a quarter
## of its men, a third for missile troops; at least 4).
static func ground_files(ty: int, alive: int) -> int:
	var f := alive / (3 if UT.cls(ty) == UT.CLS_MISSILE else 4)
	return clampi(f, mini(MIN_FILES, maxi(alive, 1)), maxi(alive, 1))


## How far (x, y) lies from segment sg's walkway centre line (sim units; past
## its ends counts too).
func _seg_off(sg: int, x: int, y: int) -> int:
	var x0 := ws_x0[sg]
	var y0 := ws_y0[sg]
	var dx := ws_x1[sg] - x0
	var dy := ws_y1[sg] - y0
	var l := maxi(FM.isqrt(dx * dx + dy * dy), 1)
	var t := ((x - x0) * dx + (y - y0) * dy) / l
	var o := absi(((x - x0) * dy - (y - y0) * dx) / l)
	var past := maxi(maxi(-t, t - l), 0)
	return maxi(o, past)


## The walkway segment (of the outer wall or the citadel's) that (x, y)
## lies on (within 3 m of its centre line), or -1.
func walk_seg_at(x: int, y: int) -> int:
	var best := -1
	var best_o := 3 * M + 1
	for sg in ws_x0.size():
		var o := _seg_off(sg, x, y)
		if o < best_o:
			best_o = o
			best = sg
	return best


## Stair point q (0 walkway E, 1 stair S, 2 foot D) of segment sg's end e.
func stair_pt(sg: int, e: int, q: int) -> Vector2i:
	var b := (sg * 2 + e) * 6 + q * 2
	return Vector2i(ws_e[b], ws_e[b + 1])


## Where defenders leave the field on a coast map: the shore's end on the
## side nearer x.
func sea_exit(x: int) -> Vector2i:
	if sea_flee.size() < 4:
		return Vector2i(x, 0 if city_def == 1 else field_h)
	var k := 0 if absi(x - sea_flee[0]) <= absi(x - sea_flee[2]) else 2
	return Vector2i(sea_flee[k], sea_flee[k + 1])


## After an order is applied on a settlement map with walls: a wall unit
## ordered off its stretch goes down a stair; a defending foot or missile
## unit ordered onto a wall (the order rule has put its destination on the
## walkway: see wall_snap) goes up one (via the street to its foot); any
## other order ends a march to a stair.
func _wall_order(u: int, typ: int) -> void:
	if u_stair[u] == ST_LADDER and typ == ORDER_MOVE and u_order[u] == O_MOVE:
		_ladder_move(u)  # climbing: a move (along its stretch the order rule kept it climbing)
		return
	if u_stair[u] == ST_LADDER and u_order[u] != O_WITHDRAW:
		return  # climbing: other orders wait (fire and run apply)
	if u_wall[u] > 0 and u_order[u] == O_WITHDRAW and u_side[u] != city_def:
		_ladder_down(u)  # back down the ladders and away
		return
	if u_wall[u] > 0 and u_order[u] == O_MOVE:
		_start_descent(u)
		return
	if typ == ORDER_MOVE and u_wall[u] == 0 and u_order[u] == O_MOVE and may_ladder(self, u):
		var wl := wall_snap(self, u_dx[u], u_dy[u])
		if wl.z >= 0:
			var lq := ladder_set_for(self, u, wl.z, wl.x, wl.y)
			if lq >= 0:
				_start_ladder(u, lq, wl.z, wl.x, wl.y)
				return
	if u_stair[u] == 1:
		return  # still coming down: the new order waits until it is down
	if typ == ORDER_MOVE and u_wall[u] == 0 and u_order[u] == O_MOVE and can_man_walls(self, u):
		var ws := wall_snap(self, u_dx[u], u_dy[u])
		if ws.z >= 0:
			_start_ascent(u, ws.z, ws.x, ws.y)
			return
	if (u_stair[u] == 2 or u_stair[u] == ST_LADDER_GO) and typ != ORDER_RUN and typ != ORDER_FIRE \
			and typ != ORDER_SKIRMISH:
		if u_stair[u] == ST_LADDER_GO:
			u_lq[u] = -1
		u_stair[u] = 0


## Which end's stair a unit on stretch sg (its men about (cx, cy)) goes
## down by: the one that minimises the walk to it plus (`moving`) the way
## from its foot to (dx, dy). Shared with the view's preview.
static func descent_end(sim, sg: int, cx: int, cy: int, moving: bool, dx: int, dy: int) -> int:
	var best_e := 0
	var best_c := 1 << 40
	for e in 2:
		var ep: Vector2i = sim.stair_pt(sg, e, 0)
		var dp: Vector2i = sim.stair_pt(sg, e, 2)
		var c := FM.approx_len(ep.x - cx, ep.y - cy)
		if moving:
			c += FM.approx_len(dx - dp.x, dy - dp.y)
		if c < best_c:
			best_c = c
			best_e = e
	return best_e


## Which end's stair a unit on the ground at (ax, ay) climbs to reach (x, y)
## on stretch sg: the one that minimises the way to its foot plus the walk
## along the wall. Shared with the view's preview.
static func ascent_end(sim, sg: int, ax: int, ay: int, x: int, y: int) -> int:
	var best_e := 0
	var best_c := 1 << 40
	for e in 2:
		var ep: Vector2i = sim.stair_pt(sg, e, 0)
		var dp: Vector2i = sim.stair_pt(sg, e, 2)
		var c := FM.approx_len(dp.x - ax, dp.y - ay) + FM.approx_len(x - ep.x, y - ep.y)
		if c < best_c:
			best_c = c
			best_e = e
	return best_e


## Wall unit u goes down: along its walkway to the stair at the end that
## suits where it is going, down the stair, and waits at its foot until its
## men are down (its order then goes ahead).
func _start_descent(u: int) -> void:
	var sg := u_wall[u] - 1
	var best_e := descent_end(self, sg, u_cx[u], u_cy[u], u_order[u] == O_MOVE or u_order[u] == O_WITHDRAW,
		u_dx[u], u_dy[u])
	var jn := _wall_join(u)
	_stair_set(u, sg, best_e, 1)
	if jn.z != 0:
		# Spread over two stretches: the men on the other one come by the
		# junction in the tower first (trail junction, walkway, stair, foot).
		var base := u * TRAIL
		for q in range(3, 0, -1):
			tr_x[base + q] = tr_x[base + q - 1]
			tr_y[base + q] = tr_y[base + q - 1]
		tr_x[base] = jn.x
		tr_y[base] = jn.y
		u_trn[u] = 4
	if u_state[u] == U_ROUTING:
		stat_stair_rout += 1
	else:
		stat_stair_down += 1
	u_wall[u] = 0
	var dp2 := stair_pt(sg, best_e, 2)
	var sp := stair_pt(sg, best_e, 1)
	u_ax[u] = dp2.x
	u_ay[u] = dp2.y
	u_face[u] = FM.atan2_a(dp2.y - sp.y, dp2.x - sp.x)
	u_sq[u] = 0
	u_dirty[u] = 1
	u_settled[u] = 0


## A defending unit on the ground goes up onto segment sg at (x, y): it
## marches to the foot of the stair nearer to it (counting the walk along
## the wall), then climbs.
func _start_ascent(u: int, sg: int, x: int, y: int) -> void:
	var best_e := ascent_end(self, sg, u_ax[u], u_ay[u], x, y)
	u_sseg[u] = sg
	u_send[u] = best_e
	u_stair[u] = 2
	u_st0[u] = tick
	u_wx[u] = x
	u_wy[u] = y
	var dp2 := stair_pt(sg, best_e, 2)
	u_dx[u] = dp2.x
	u_dy[u] = dp2.y
	u_pn[u] = 0


## Stair move state and the trail its men follow (walkway point, stair,
## foot; reversed going up).
func _stair_set(u: int, sg: int, e: int, mode: int) -> void:
	u_sseg[u] = sg
	u_send[u] = e
	u_stair[u] = mode
	u_st0[u] = tick
	var base := u * TRAIL
	for q in 3:
		var p := stair_pt(sg, e, q if mode == 1 else 2 - q)
		if q == 1:
			p = _stair_cell(p.x, p.y)
		tr_x[base + q] = p.x
		tr_y[base + q] = p.y
	u_trn[u] = 3
	u_pn[u] = 0
	u_sprog[u] = 0


## The middle of the stair cell nearest (x, y) (within 2 cells; else (x, y)):
## a stair point can fall on a cell's edge, where a man heading for it
## along a wall cannot reach it.
func _stair_cell(x: int, y: int) -> Vector2i:
	var ci := x >> 11
	var cj := y >> 11
	var best := Vector2i(x, y)
	var best_d := 1 << 40
	for dj in range(-2, 3):
		for di in range(-2, 3):
			var i := ci + di
			var j := cj + dj
			if i < 0 or j < 0 or i >= ob_w or j >= ob_h or obs[j * ob_w + i] != MapGen.C_STAIR:
				continue
			var cx := (i << 11) + 1024
			var cy := (j << 11) + 1024
			var d := FM.approx_len(cx - x, cy - y)
			if d < best_d:
				best_d = d
				best = Vector2i(cx, cy)
	return best


## At the foot of its stair: up it goes (onto the walkway at the point it
## was ordered to, facing out).
func _climb(u: int) -> void:
	var sg := u_sseg[u]
	_stair_set(u, sg, u_send[u], 3)
	stat_stair_up += 1
	u_wall[u] = sg + 1
	var wa := wall_anchor(self, sg, u_wx[u], u_wy[u], u_alive[u], u_type[u])
	u_files[u] = wall_nf(u_alive[u])
	u_ax[u] = wa.x
	u_ay[u] = wa.y
	u_face[u] = wa.z
	u_dface[u] = wa.z
	u_order[u] = O_NONE
	u_target[u] = -1
	u_gtarget[u] = -1
	u_run[u] = 0
	u_skirm[u] = 0
	u_sq[u] = 0
	u_dirty[u] = 1
	u_settled[u] = 0


## A stair move is over once every man is off the walkway (going down) or
## on it (going up), or after STAIR_MAX ticks.
func _stair_check(u: int) -> void:
	var down := u_stair[u] == 1
	var done := tick - u_st0[u] > STAIR_MAX
	if not done:
		done = true
		var across := 0
		var base := u_slot_base[u]
		for s in u_alive[u]:
			var i := slot_soldier[base + s]
			if state[i] >= S_DEAD:
				continue
			var k := obs_kind(pos_x[i], pos_y[i])
			# Down once off the walkway (a stair's cells are the street's too),
			# up once on it (or passing a tower).
			var on_wall := k == MapGen.C_WALK or k == MapGen.C_TOWER
			if on_wall == down:
				done = false
			else:
				across += 1
		if across > u_sprog[u]:
			u_sprog[u] = across
			u_stuck[u] = 0  # (men across: the stair move gets on)
	if not done:
		return
	u_stair[u] = 0
	u_trn[u] = 0
	u_pn[u] = 0
	u_settled[u] = 0
	if down and u_state[u] == U_READY and u_order[u] == O_MOVE and can_man_walls(self, u):
		# Down from one stretch, bound for another: up again.
		var ws := wall_snap(self, u_dx[u], u_dy[u])
		if ws.z >= 0:
			_start_ascent(u, ws.z, ws.x, ws.y)


## Gate g's state change from an order (defenders only): closing needs the
## gate's cells clear of men; a broken gate stays broken.
func _gate_order(o: Dictionary) -> void:
	var g := int(o.get("gate", -1))
	var u := int(o.get("unit", -1))
	if city_on == 0 or g < 0 or g >= n_gates or u < 0 or u >= n_units or u_side[u] != city_def:
		return
	if g_state[g] == GATE_BROKEN:
		return
	var want := GATE_CLOSED if int(o.get("on", 1)) != 0 else GATE_OPEN
	if want == g_state[g]:
		return
	if want == GATE_CLOSED and gate_busy(g):
		return
	g_state[g] = want
	if want == GATE_CLOSED:
		stat_gate_close += 1
	else:
		stat_gate_open += 1
	_gate_cells(g)


## Someone stands in gate g's cells.
func gate_busy(g: int) -> bool:
	var b := g * 4
	var x0 := g_bb[b] * 2 * M
	var y0 := g_bb[b + 1] * 2 * M
	var x1 := (g_bb[b + 2] + 1) * 2 * M
	var y1 := (g_bb[b + 3] + 1) * 2 * M
	for u in n_units:
		if u_alive[u] <= 0 or u_maxx[u] < x0 or u_minx[u] > x1 or u_maxy[u] < y0 or u_miny[u] > y1:
			continue
		var base := u_slot_base[u]
		for s in u_alive[u]:
			var i := slot_soldier[base + s]
			if state[i] < S_DEAD and obs_kind(pos_x[i], pos_y[i]) == MapGen.C_GATE + g:
				return true
	return false


func _break_gate(g: int) -> void:
	g_state[g] = GATE_BROKEN
	g_hp[g] = 0
	stat_gate_broken += 1
	_gate_cells(g)


## Where (x, y) is relative to gate g: [along the wall, outward] (sim units).
func gate_frame(g: int, x: int, y: int) -> Vector2i:
	var c := FM.cos_a(g_dir[g])
	var s := FM.sin_a(g_dir[g])
	var rx := x - g_x[g]
	var ry := y - g_y[g]
	return Vector2i((ry * c - rx * s) / FM.TRIG_ONE, (rx * c + ry * s) / FM.TRIG_ONE)


## The point an attacker aims at to hit gate g: the middle of its outer face.
func gate_face(g: int) -> Vector2i:
	var out := wall_t / 2
	return Vector2i(g_x[g] + FM.cos_a(g_dir[g]) * out / FM.TRIG_ONE,
		g_y[g] + FM.sin_a(g_dir[g]) * out / FM.TRIG_ONE)


## Where a unit stands to hack at gate g (outside for attackers, inside for
## defenders), facing it.
func gate_front(g: int, side: int) -> Vector3i:
	var sgn := 1 if side != city_def else -1
	var d := wall_t / 2 + M + M / 4
	var c := FM.cos_a(g_dir[g])
	var s := FM.sin_a(g_dir[g])
	return Vector3i(g_x[g] + sgn * c * d / FM.TRIG_ONE, g_y[g] + sgn * s * d / FM.TRIG_ONE,
		(g_dir[g] + (512 if sgn > 0 else 0)) & FM.ANGLE_MASK)


## A projectile aimed at a gate lands: within its face (and 1.5 m round) it
## damages the gate. Returns true if it struck the gate.
func _gate_hit(p: int, dmg: int) -> bool:
	var g := -2 - pr_tu[p]
	if g < 0 or g >= n_gates or g_state[g] != GATE_CLOSED:
		return false
	var f := gate_frame(g, pr_x[p], pr_y[p])
	if absi(f.x) > g_hw[g] * M + 1536 or absi(f.y) > wall_t / 2 + 1536:
		return false
	g_hp[g] -= dmg * 100
	g_hit_t[g] = tick
	stat_gate_art += dmg
	if g_hp[g] <= 0:
		_break_gate(g)
	return true


## Men hack at closed gates: foot soldiers (not missile troops, cavalry or
## crews) of the attacking side within GATE_REACH of the gate's face, of a
## unit that is not marching past (standing, attacking, or ordered at the
## gate); each takes off (damage - GATE_ARMOUR) x GATE_HACK_PCT% per swing.
func _update_gates() -> void:
	var hack_pct: int = GATE_HACK_BY_WALLS[city_walls]
	for g in n_gates:
		if g_state[g] != GATE_CLOSED:
			continue
		var reach_x := g_hw[g] * M + M
		var reach_y := wall_t / 2 + GATE_REACH
		var men := 0
		var dmg := 0
		var gx := g_x[g]
		var gy := g_y[g]
		var r := wall_t + MapGen.GATE_HW * M + 6 * M
		if sg_on != 0:
			_siege_gate(g)
			if g_state[g] != GATE_CLOSED:
				continue
		if not gate_hackable(self, g):
			continue  # bound with iron: swords do nothing (a ram or artillery)
		for u in n_units:
			if u_side[u] == city_def or u_state[u] != U_READY or u_alive[u] <= 0:
				continue
			var cl := u_cls[u]
			if cl != UT.CLS_INF and cl != UT.CLS_PIKE and t_gate_w[u_otype[u]] < city_walls:
				continue  # (foot hack; beasts batter the gates of low walls)
			if u_order[u] == O_MOVE and u_gtarget[u] != g:
				continue
			if u_maxx[u] < gx - r or u_minx[u] > gx + r or u_maxy[u] < gy - r or u_miny[u] > gy + r:
				continue
			var ty := u_otype[u]
			if sg_on != 0 and u_carry[u] >= 0:
				continue  # carrying: no hacking (the ram works the gate itself: _siege_gate)
			var rate := maxi(t_damage[ty] - GATE_ARMOUR, 2) * hack_pct / maxi(t_cooldown[ty], 1)
			if cl != UT.CLS_INF and cl != UT.CLS_PIKE:
				rate = rate * t_gate_pct[ty] / 100
				stat_beast_gate += 1
			var base := u_slot_base[u]
			for s in u_alive[u]:
				var i := slot_soldier[base + s]
				if state[i] != S_FORMED and state[i] != S_FIGHTING:
					continue
				var f := gate_frame(g, pos_x[i], pos_y[i])
				if absi(f.x) <= reach_x and absi(f.y) <= reach_y:
					men += 1
					dmg += rate
					if men >= GATE_HACKERS:
						break
			if men >= GATE_HACKERS:
				break
		if men > 0:
			g_hp[g] -= dmg
			g_hit_t[g] = tick
			stat_gate_hack += dmg
			if g_hp[g] <= 0:
				_break_gate(g)


## The plaza: attackers holding it (a ready unit of CAPTURE_MEN or more with
## its centre in it, no ready defender unit within CAPTURE_CLEAR beyond it)
## for CAPTURE_TICKS break the defenders. Counted once a second.
func _update_capture() -> void:
	if city_on == 0 or winner >= 0 or tick % TICKS_PER_SECOND != 0:
		return
	_town_lost()
	var px := plaza[0]
	var py := plaza[1]
	var r := plaza[3]
	var held := false
	var contested := false
	var rc := r + CAPTURE_CLEAR
	for u in n_units:
		if u_state[u] != U_READY:
			continue
		var dx := u_cx[u] - px
		var dy := u_cy[u] - py
		if u_side[u] == city_def:
			if u_wall[u] == 0 and absi(dx) <= rc and absi(dy) <= rc:
				contested = true
		elif u_alive[u] >= CAPTURE_MEN and absi(dx) <= r and absi(dy) <= r:
			held = true
	if held and not contested:
		cap_t += TICKS_PER_SECOND
	else:
		cap_t = 0
	if cap_t >= CAPTURE_TICKS:
		stat_capture += 1
		for u in n_units:
			if u_side[u] == city_def and u_state[u] == U_READY:
				_start_rout(u)
				u_routs[u] = MAX_ROUTS + 1  # the city has fallen: no rally


## The town is lost: while the attackers' men inside the walls outnumber
## the defenders' ready men 3 to 1, after CIT_SIEGE ticks every defending
## unit (on the walls, in a citadel or anywhere) loses CIT_SIEGE_LOSS
## morale a second and does not recover. Counted once a second.
func _town_lost() -> void:
	var att := 0
	var dfn := 0
	for u in n_units:
		if u_state[u] != U_READY:
			continue
		if u_side[u] == city_def:
			if t_fixed[u_type[u]] == 0:
				dfn += u_alive[u]
		elif (veg_bits(u_cx[u], u_cy[u]) & MapGen.V_URBAN) != 0:
			att += u_alive[u]
	if dfn > 0 and att >= 3 * dfn:
		cit_siege += TICKS_PER_SECOND
	else:
		cit_siege = 0
	if cit_siege < CIT_SIEGE:
		return
	for u in n_units:
		if u_side[u] == city_def and u_state[u] == U_READY:
			# (Behind level 3 walls they hold out twice as long.)
			u_morale[u] -= CIT_SIEGE_LOSS if city_walls < 3 else CIT_SIEGE_LOSS / 2
			u_hit_t[u] = tick  # no recovering meanwhile
			stat_cit_siege += 1


## Routing unit u on a settlement map: run along a path to its own edge
## (round the walls and out through a gate), else straight away.
func _flee_step(u: int) -> void:
	if u_stair[u] == 1:
		# Off the wall first: to the foot of the nearest stair.
		var dp := stair_pt(u_sseg[u], u_send[u], 2)
		var ddx := dp.x - u_cx[u]
		var ddy := dp.y - u_cy[u]
		var dd := FM.approx_len(ddx, ddy)
		if dd > 0:
			u_flee_x[u] = ddx * FM.TRIG_ONE / dd
			u_flee_y[u] = ddy * FM.TRIG_ONE / dd
		return
	var gx := u_cx[u]
	var gy := field_h if u_side[u] == 0 else 0
	if sea_on != 0 and u_side[u] == city_def:
		# Not into the sea: along the shore to the land's edge.
		var fp := sea_exit(u_cx[u])
		gx = fp.x
		gy = fp.y
	if ROUT_INWARD != 0 and u_side[u] == city_def and n_gates > 0 \
			and (veg_bits(u_cx[u], u_cy[u]) & MapGen.V_URBAN) != 0:
		var rg := -1
		if u_pn[u] > 0 and (u + tick) % TICKS_PER_SECOND != 0:
			# (The gate is chosen again once a second; meanwhile the one the
			# path goes to, while it is still shut.)
			for g in n_gates:
				if g_ix[g] == u_pgx[u] and g_iy[g] == u_pgy[u] and g_state[g] == GATE_CLOSED and g_cit[g] == 0:
					rg = g
					break
		if rg < 0:
			rg = _rout_gate(u)
		if rg >= 0:
			gx = g_ix[rg]
			gy = g_iy[rg]
	u_ax[u] = u_cx[u]
	u_ay[u] = u_cy[u]
	var p := _path_point(u, gx, gy, true)
	var dx := p.x - u_cx[u]
	var dy := p.y - u_cy[u]
	var d := FM.approx_len(dx, dy)
	if d > 0:
		u_flee_x[u] = dx * FM.TRIG_ONE / d
		u_flee_y[u] = dy * FM.TRIG_ONE / d


## A defending router inside the walls: the inside of the shut outer gate
## on its own ground farthest from any enemy (not out through the breach
## into the attackers); -1 none (no shut gate, or enemies within 30 m of
## every one).
func _rout_gate(u: int) -> int:
	var piece := reach_at(u_cx[u], u_cy[u])
	var best := -1
	var bd := 30 * M
	for g in n_gates:
		if g_cit[g] != 0 or g_state[g] != GATE_CLOSED or reach_at(g_ix[g], g_iy[g]) != piece:
			continue
		var near := 1 << 30
		for o in n_units:
			if u_side[o] != u_side[u] and u_state[o] == U_READY:
				near = mini(near, FM.approx_len(g_ix[g] - u_cx[o], g_iy[g] - u_cy[o]))
		if near > bd:
			best = g
			bd = near
	return best


## Tree depth along a flat shot from (x0, y0) to (x1, y1): the distance at
## which the woods in the way (TREE_W per 4 m sample, LOF_SKIP from either
## end ignored) pass TREE_BLOCK, or -1.
func tree_block(x0: int, y0: int, x1: int, y1: int, ext: int = 0) -> int:
	if veg_on == 0:
		return -1
	var dx := x1 - x0
	var dy := y1 - y0
	var d := FM.approx_len(dx, dy)
	if d <= 2 * LOF_SKIP:
		return -1
	var a := LOF_SKIP
	var end := d - LOF_SKIP + ext
	var w := 0
	while a <= end:
		w += TREE_W[veg_d(x0 + dx * a / d, y0 + dy * a / d)]
		if w > TREE_BLOCK:
			return a
		a += LOF_STEP
	return -1


## How far a stone ploughs from (x, y) along (ux, uy) (Q12) before a
## building or wall stops it (at most `len`).
func _obs_run(x: int, y: int, ux: int, uy: int, length: int) -> int:
	var a := 0
	while a < length:
		if obs_kind(x + ux * a / FM.TRIG_ONE, y + uy * a / FM.TRIG_ONE) != MapGen.C_OPEN:
			return a
		a += 2 * M
	return length


# ------------------------------------------------------------------ rng ---

func _rand() -> int:
	var x := rng_state
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	rng_state = x
	return x


# --------------------------------------------------------------- orders ---

static func make_move_order(p_tick: int, unit: int, x: int, y: int, face: int,
		width: int, run: int) -> Dictionary:
	return {"tick": p_tick, "type": ORDER_MOVE, "unit": unit, "x": x, "y": y,
		"facing": face, "width": width, "run": run}


static func make_attack_order(p_tick: int, unit: int, target_unit: int, run: int) -> Dictionary:
	return {"tick": p_tick, "type": ORDER_ATTACK, "unit": unit,
		"target": target_unit, "run": run}


static func make_halt_order(p_tick: int, unit: int) -> Dictionary:
	return {"tick": p_tick, "type": ORDER_HALT, "unit": unit}


static func make_run_order(p_tick: int, unit: int, run: int) -> Dictionary:
	return {"tick": p_tick, "type": ORDER_RUN, "unit": unit, "run": run}


static func make_fire_order(p_tick: int, unit: int, on: int) -> Dictionary:
	return {"tick": p_tick, "type": ORDER_FIRE, "unit": unit, "on": on}


static func make_skirmish_order(p_tick: int, unit: int, on: int) -> Dictionary:
	return {"tick": p_tick, "type": ORDER_SKIRMISH, "unit": unit, "on": on}


static func make_withdraw_order(p_tick: int, unit: int) -> Dictionary:
	return {"tick": p_tick, "type": ORDER_WITHDRAW, "unit": unit}


static func make_withdraw_all_order(p_tick: int, side: int) -> Dictionary:
	return {"tick": p_tick, "type": ORDER_WITHDRAW_ALL, "side": side}


static func make_deploy_order(p_tick: int, unit: int, on: int) -> Dictionary:
	return {"tick": p_tick, "type": ORDER_DEPLOY, "unit": unit, "on": on}


static func make_refill_order(p_tick: int, unit: int, on: int) -> Dictionary:
	return {"tick": p_tick, "type": ORDER_REFILL, "unit": unit, "on": on}


## Queue an order. Orders are applied at the start of order["tick"] (or the
## next step if that tick has passed). Within a tick they apply in order of
## (player, seq); "player" defaults to 0 and "seq" to a local counter. For
## lockstep both peers must supply the same player/seq values.
func queue_order(order: Dictionary) -> void:
	# Orders are plain data: force every value to int so a float that slipped
	# in from the view can never reach sim state.
	var o := {}
	for k in order:
		o[k] = int(order[k])
	if not o.has("player"):
		o["player"] = 0
	if not o.has("seq"):
		o["seq"] = _order_seq
		_order_seq += 1
	pending_orders.append(o)


static func _order_less(a: Dictionary, b: Dictionary) -> bool:
	if int(a["tick"]) != int(b["tick"]):
		return int(a["tick"]) < int(b["tick"])
	if int(a["player"]) != int(b["player"]):
		return int(a["player"]) < int(b["player"])
	return int(a["seq"]) < int(b["seq"])


## Apply the orders due; orders of players >= max_player stay pending (the
## deployment phase: scripted and AI orders wait for the battle).
func _apply_orders(max_player: int = 1 << 30) -> void:
	if pending_orders.is_empty():
		return
	var due: Array = []
	var rest: Array = []
	for o in pending_orders:
		if int(o["tick"]) <= tick and int(o["player"]) < max_player:
			due.append(o)
		else:
			rest.append(o)
	if due.is_empty():
		return
	pending_orders = rest
	due.sort_custom(_order_less)
	_placing = PackedInt32Array()
	for o in due:
		if int(o["type"]) == ORDER_PLACE:
			_placing.append(int(o.get("unit", -1)))
	for o in due:
		if int(o["type"]) == ORDER_READY:
			if phase == PHASE_DEPLOY:
				dep_ready |= 1 << clampi(int(o.get("who", 0)), 0, 30)
			continue
		if int(o["type"]) == ORDER_GATE:
			if phase != PHASE_DEPLOY:
				_gate_order(o)
			continue
		if int(o["type"]) == ORDER_WORKS:
			if phase == PHASE_DEPLOY:
				_works_order(o)
			continue
		if int(o["type"]) == ORDER_KILL:
			# (A routing unit: not through the unit order rules.)
			var ku := int(o.get("unit", -1))
			if phase != PHASE_DEPLOY and kill_refusal(self, ku) == "":
				u_kill[ku] = t_kill_delay[u_type[ku]]
			continue
		if int(o["type"]) == ORDER_RELEASE:
			# (The pack is a unit of its own: the handlers' orders do not change.)
			var hu := int(o.get("unit", -1))
			var rt := int(o.get("target", -1))
			if phase != PHASE_DEPLOY and release_refusal(self, hu, rt) == "":
				_unleash(hu, rt)
			continue
		for u in order_units(self, o):
			var d := order_fields(self, u)
			var o0 := u_order[u]  # (the order it had: an attack after an attack keeps its way)
			apply_order_rule(self, u, d, o)
			u_order[u] = int(d["order"])
			u_ax[u] = int(d["ax"])
			u_ay[u] = int(d["ay"])
			u_face[u] = int(d["face"])
			u_files[u] = int(d["files"])
			u_dx[u] = int(d["dx"])
			u_dy[u] = int(d["dy"])
			u_dface[u] = int(d["dface"])
			u_target[u] = int(d["target"])
			u_run[u] = int(d["run"])
			u_fire[u] = int(d["fire"])
			u_skirm[u] = int(d["skirm"])
			u_deploy[u] = int(d["deploy"])
			u_refill[u] = int(d["refill"])
			u_gtarget[u] = int(d["gtarget"])
			u_pick[u] = int(d["pick"])
			u_akind[u] = int(d["akind"])
			u_forage[u] = int(d["forage"])
			u_dirty[u] = 1
			u_settled[u] = 0
			if obs_on != 0:
				u_flt[u] = -FLOW_EVERY  # (an order: its places are laid out afresh)
			if dog_on != 0 and u_hand[u] >= 0:
				u_ret[u] = 0  # a pack given an order: no longer on its way back
				u_dogt[u] = 0
			if int(o["type"]) == ORDER_DROP:
				_drop(u)
				if n_eng > 0 and u_eg[u] >= 0:
					_drop_engines(u)
			elif u_pick[u] >= 0:
				_pick_check(u)
			if int(o["type"]) == ORDER_PLACE:
				if int(d.get("placed", 0)) != 0:
					_place_unit(u, int(d.get("wall", 0)))
				continue
			if obs_on != 0:
				if not (o0 == O_ATTACK and u_order[u] == O_ATTACK):
					u_pn[u] = 0  # plan a new path
				# (An attack after an attack keeps its way: _path_point plans again
				# once the goal has moved off it. The AI retargeting every second
				# had a unit at a corner plan from scratch, turn back to the
				# street graph's entry node behind it, and never get on.)
			if city_on != 0 and ws_e.size() > 0:
				_wall_order(u, int(o["type"]))
	_placing = PackedInt32Array()


## The ORDER_KEYS fields of unit u as a Dictionary.
static func order_fields(sim, u: int) -> Dictionary:
	return {"order": sim.u_order[u], "ax": sim.u_ax[u], "ay": sim.u_ay[u],
		"face": sim.u_face[u], "files": sim.u_files[u], "dx": sim.u_dx[u],
		"dy": sim.u_dy[u], "dface": sim.u_dface[u], "target": sim.u_target[u],
		"run": sim.u_run[u], "fire": sim.u_fire[u], "skirm": sim.u_skirm[u],
		"deploy": sim.u_deploy[u], "refill": sim.u_refill[u], "gtarget": sim.u_gtarget[u],
		"pick": sim.u_pick[u], "akind": sim.u_akind[u], "forage": sim.u_forage[u]}


## Units an order applies to (in index order): its unit, or every ready unit
## of the side for an army-wide withdrawal. Shared with OrderPreview.
static func order_units(sim, o: Dictionary) -> Array[int]:
	var out: Array[int] = []
	if int(o["type"]) == ORDER_GATE or int(o["type"]) == ORDER_KILL or int(o["type"]) == ORDER_RELEASE \
			or int(o["type"]) == ORDER_WORKS:
		return out  # not a unit order (applied by the sim to the gate; the drivers of an amok beast; a pack)
	if int(o["type"]) == ORDER_WITHDRAW_ALL:
		var side := int(o.get("side", -1))
		for u in sim.n_units:
			if sim.u_side[u] == side and sim.u_state[u] == U_READY:
				out.append(u)
		return out
	var u := int(o.get("unit", -1))
	if u >= 0 and u < sim.n_units and sim.u_state[u] == U_READY:
		out.append(u)
	return out


## The order rules, applied to `d` (unit fields named in ORDER_KEYS). The sim
## applies orders through this, and OrderPreview predicts not-yet-applied
## orders through the same function, so the two can never disagree.
static func apply_order_rule(sim, u: int, d: Dictionary, o: Dictionary) -> void:
	var typ := int(o["type"])
	var ty: int = sim.u_type[u]
	# Deployment phase: units are placed (ORDER_PLACE), not moved; only the
	# standing settings (run, fire at will, skirmish, artillery set up) may
	# change. A placement outside the deployment phase does nothing.
	if typ == ORDER_PLACE:
		if sim.phase == PHASE_DEPLOY:
			place_rule(sim, u, d, o)
		return
	if sim.phase == PHASE_DEPLOY and typ != ORDER_RUN and typ != ORDER_FIRE and typ != ORDER_SKIRMISH \
			and typ != ORDER_DEPLOY and typ != ORDER_AMMO:
		return
	if (typ == ORDER_WITHDRAW or typ == ORDER_WITHDRAW_ALL) and u < sim.u_hand.size() and sim.u_hand[u] >= 0:
		return  # a war dog pack does not leave the field (it runs back to its handlers)
	if typ == ORDER_AMMO:
		# Which ammunition: its special kind (on 1) or the standard one.
		if sim.spec_kind(u) >= 0:
			d["akind"] = 1 if int(o.get("on", 0)) != 0 else 0
		return
	# Siege: a tower's engine only shoots (at a unit, at will) or holds; a
	# unit climbing ladders goes on climbing (or withdraws back down them).
	if UT.stat(ty, "fixed") != 0 and typ != ORDER_ATTACK and typ != ORDER_HALT and typ != ORDER_FIRE \
			and typ != ORDER_AMMO:
		return
	if u < sim.u_stair.size() and sim.u_stair[u] == ST_LADDER and typ != ORDER_FIRE and typ != ORDER_RUN \
			and typ != ORDER_WITHDRAW and typ != ORDER_WITHDRAW_ALL and typ != ORDER_MOVE:
		return
	# Siege equipment: a unit goes to a piece and picks it up (ORDER_PICKUP);
	# putting it down (ORDER_DROP) is the sim's (no order field changes). A
	# unit carrying a piece never runs and attacks no unit (the ram's
	# carriers go at gates); any other order forgets a pick-up.
	var carry: int = sim.u_carry[u] if u < sim.u_carry.size() else -1
	if typ == ORDER_PICKUP and o.has("engines"):
		var g := int(o["engines"])
		if engine_refusal(sim, u, g) != "":
			return
		var at := engines_at(sim, g)
		d["order"] = O_MOVE
		d["dx"] = at.x
		d["dy"] = at.y
		var gdx: int = at.x - int(d["ax"])
		var gdy: int = at.y - int(d["ay"])
		d["dface"] = FM.atan2_a(gdy, gdx) if gdx != 0 or gdy != 0 else int(d["face"])
		d["target"] = -1
		d["gtarget"] = -1
		d["run"] = 1 if int(o.get("run", 0)) != 0 and carry < 0 else 0
		d["pick"] = PICK_ENG + g
		return
	if typ == ORDER_PICKUP:
		var q := int(o.get("equip", -1))
		if pickup_refusal(sim, u, q) != "":
			return
		d["order"] = O_MOVE
		d["dx"] = sim.q_x[q]
		d["dy"] = sim.q_y[q]
		var pdx: int = sim.q_x[q] - int(d["ax"])
		var pdy: int = sim.q_y[q] - int(d["ay"])
		d["dface"] = FM.atan2_a(pdy, pdx) if pdx != 0 or pdy != 0 else int(d["face"])
		d["target"] = -1
		d["gtarget"] = -1
		d["run"] = 1 if int(o.get("run", 0)) != 0 and carry < 0 else 0
		d["pick"] = q
		return
	if typ == ORDER_DROP:
		return
	if typ == ORDER_MOVE or typ == ORDER_ATTACK or typ == ORDER_HALT or typ == ORDER_WITHDRAW \
			or typ == ORDER_WITHDRAW_ALL:
		d["pick"] = -1
	if carry >= 0:
		if typ == ORDER_ATTACK and (int(o.get("gate", -1)) < 0 or sim.q_kind[carry] != EQ_RAM):
			return  # carrying: it does not attack (put it down first); the ram goes at gates
		if typ == ORDER_RUN:
			return
	# Artillery: frontage is set by its engines, and it never runs (the
	# engines are dragged); it does not skirmish.
	var art := UT.cls(ty) == UT.CLS_ART
	var mis := UT.cls(ty) == UT.CLS_MISSILE
	# A battery's refill ends with any order to move, shoot, withdraw or
	# set up / pack up (it gets back out first: REFILL_FULL / 2 ticks); so
	# do missile troops' refill at a wagon and their foraging.
	if (art or mis) and (typ == ORDER_MOVE or typ == ORDER_ATTACK or typ == ORDER_WITHDRAW \
			or typ == ORDER_WITHDRAW_ALL or typ == ORDER_DEPLOY or typ == ORDER_HALT):
		if typ != ORDER_HALT:
			d["refill"] = 0
		d["forage"] = 0
	# Walls. A move onto a wall's body, walkway, stair or tower goes to the
	# walkway of the stretch it belongs to (wall_snap); only units that may
	# man the walls take it so (others: a ground move, refused by the view).
	# A unit on a wall holds it: it moves only along its stretch (in its
	# wall line, facing out), anywhere else means down a stair (the sim
	# starts the stair moves when the order is applied: _wall_order), and it
	# does not withdraw or skirmish.
	var wallu: int = sim.u_wall[u] if u < sim.u_wall.size() else 0
	var ws := Vector3i(0, 0, -1)
	var lad := wallu == 0 and may_ladder(sim, u)
	if typ == ORDER_MOVE and (wallu > 0 or can_man_walls(sim, u) or lad):
		ws = wall_snap(sim, int(o["x"]), int(o["y"]))
		if lad and ws.z >= 0 and ladder_set_for(sim, u, ws.z, ws.x, ws.y) < 0:
			ws = Vector3i(0, 0, -1)  # no way up there: an ordinary move
	# Attackers up the ladders withdraw back down them (the wall rule below
	# keeps defenders on their wall).
	var lad_down: bool = wallu > 0 and sim.u_side[u] != sim.city_def \
		and (typ == ORDER_WITHDRAW or typ == ORDER_WITHDRAW_ALL)
	if wallu > 0 and not lad_down:
		if typ == ORDER_WITHDRAW or typ == ORDER_WITHDRAW_ALL or typ == ORDER_SKIRMISH:
			return
		if typ == ORDER_MOVE and ws.z == wallu - 1:
			var wa := wall_anchor(sim, ws.z, ws.x, ws.y, sim.u_alive[u], ty)
			d["files"] = wall_nf(sim.u_alive[u])
			d["ax"] = wa.x
			d["ay"] = wa.y
			d["face"] = wa.z
			d["dface"] = wa.z
			d["order"] = O_NONE
			d["target"] = -1
			d["gtarget"] = -1
			d["run"] = 0
			return
		if typ == ORDER_MOVE:
			# Off the wall (down by a stair and on through the streets, in its
			# normal block at most), or onto another stretch (down, then up).
			d["order"] = O_MOVE
			d["dx"] = ws.x if ws.z >= 0 else clampi(int(o["x"]), 0, sim.field_w)
			d["dy"] = ws.y if ws.z >= 0 else clampi(int(o["y"]), 0, sim.field_h)
			d["dface"] = sim.ws_dir[ws.z] if ws.z >= 0 else int(o["facing"]) & FM.ANGLE_MASK
			d["files"] = mini(width_to_files(int(o["width"]), sim.u_alive[u], ty), ground_files(ty, sim.u_alive[u]))
			d["run"] = 1 if int(o.get("run", 0)) != 0 else 0
			d["target"] = -1
			d["gtarget"] = -1
			return
	elif ws.z >= 0:
		# Up onto the wall: to the stair's foot, up, along to the point
		# (always a march, however near: the way up is by the stair; it
		# turns to the wall at the top).
		d["order"] = O_MOVE
		d["dx"] = ws.x
		d["dy"] = ws.y
		d["dface"] = sim.ws_dir[ws.z]
		d["run"] = 1 if int(o.get("run", 0)) != 0 else 0
		d["target"] = -1
		d["gtarget"] = -1
		return
	if typ == ORDER_MOVE:
		var x := clampi(int(o["x"]), 0, sim.field_w)
		var y := clampi(int(o["y"]), 0, sim.field_h)
		var face := int(o["facing"]) & FM.ANGLE_MASK
		if sim.city_on != 0 and sim.n_cmp > 0:
			# Where it can get to: open ground of its own piece (a tap on a
			# house: beside it), else the gate on its side on the way (a tap
			# inside a shut town: it goes to the gate and holds there).
			var rs: Vector3i = sim.reach_snap(int(d["ax"]), int(d["ay"]), x, y, sim.u_side[u])
			if rs.z == 1 or rs.z == 2:
				x = rs.x
				y = rs.y
			d["snap"] = rs.z
		elif sim.obs_on != 0 and (sim.nav_at(x, y) & sim._ground_mask(u)) == 0:
			# Maps with buildings but no town: a tap on a house goes beside
			# it (the nearest open 2 m cell within 12 m, rings in index
			# order), so the anchor does not stop at its edge short of it.
			var op := open_snap(sim, x, y, sim._ground_mask(u))
			x = op.x
			y = op.y
		if not art:
			d["files"] = width_to_files(int(o["width"]), sim.u_alive[u], ty)
		d["run"] = 1 if int(o.get("run", 0)) != 0 and not art and carry < 0 else 0
		d["target"] = -1
		d["gtarget"] = -1
		var dx: int = x - d["ax"]
		var dy: int = y - d["ay"]
		# (Among buildings only with a clear way from its men to there: else
		# a march, whose trail its men follow; snapped behind a house corner,
		# men stood on the far side of it for minutes, 2026-10-09.)
		if dx * dx + dy * dy <= REFORM_IN_PLACE_DIST * REFORM_IN_PLACE_DIST \
				and (sim.obs_on == 0 or sim._los_fat(sim.u_cx[u], sim.u_cy[u], x, y, sim._ground_mask(u))):
			d["ax"] = x
			d["ay"] = y
			# Slow-turning formations (pikes) wheel to the new facing.
			if UT.stat(ty, "turn") == 0:
				d["face"] = face
			d["order"] = O_NONE
		else:
			d["order"] = O_MOVE
			d["dx"] = x
			d["dy"] = y
		d["dface"] = face
	elif typ == ORDER_ATTACK:
		var gt := int(o.get("gate", -1))
		if gt >= 0:
			# At a gate: batteries shoot it, foot go to its face and hack at
			# it; nobody else can (and only the attackers).
			if sim.city_on == 0 or gt >= sim.n_gates or sim.u_side[u] == sim.city_def \
					or sim.g_state[gt] != GATE_CLOSED:
				return
			if art:
				d["order"] = O_ATTACK
				d["target"] = -1
				d["gtarget"] = gt
				d["run"] = 0
				return
			var c := UT.cls(ty)
			if c == UT.CLS_MISSILE and carry < 0 and wallu == 0:
				# Missile troops shoot at it from where they stand (fire
				# missiles set it alight; others glance off).
				d["order"] = O_NONE
				d["target"] = -1
				d["gtarget"] = gt
				d["dx"] = d["ax"]
				d["dy"] = d["ay"]
				d["dface"] = FM.atan2_a(sim.g_y[gt] - int(d["ay"]), sim.g_x[gt] - int(d["ax"]))
				d["run"] = 0
				return
			var gfp: Vector3i = sim.gate_front(gt, sim.u_side[u])
			if carry < 0 and u < sim.u_lq.size() and sim.u_lq[u] >= 0 and (wallu > 0 \
					or sim.reach_at(int(d["ax"]), int(d["ay"])) == sim.reach_at(sim.g_ix[gt], sim.g_iy[gt])):
				gfp = sim.gate_front(gt, sim.city_def)  # over the wall by ladders: its inside, to unbar it
				if c == UT.CLS_CAV or c == UT.CLS_ART:
					return
			elif carry < 0 and (c != UT.CLS_INF and c != UT.CLS_PIKE and UT.stat(ty, "gate_walls") < sim.city_walls \
					or not gate_hackable(sim, gt)):
				return  # (only foot hack, beasts batter low walls' gates, and only at a gate swords can break)
			d["order"] = O_MOVE
			d["dx"] = gfp.x
			d["dy"] = gfp.y
			d["dface"] = gfp.z
			d["target"] = -1
			d["gtarget"] = gt
			d["run"] = 1 if int(o.get("run", 0)) != 0 and carry < 0 else 0
			return
		var t := int(o["target"])
		if t < 0 or t >= sim.n_units or sim.u_side[t] == sim.u_side[u] or sim.u_state[t] >= U_DESTROYED:
			return
		d["order"] = O_ATTACK
		d["target"] = t
		d["gtarget"] = -1
		d["run"] = 1 if int(o.get("run", 0)) != 0 and not art and carry < 0 else 0
	elif typ == ORDER_HALT:
		d["order"] = O_NONE
		d["target"] = -1
		d["gtarget"] = -1
		d["dface"] = d["face"]
	elif typ == ORDER_RUN:
		d["run"] = 1 if int(o.get("run", 0)) != 0 and not art and carry < 0 else 0
	elif typ == ORDER_FIRE:
		if UT.stat(ty, "m_ammo") > 0:
			d["fire"] = 1 if int(o.get("on", 0)) != 0 else 0
	elif typ == ORDER_SKIRMISH:
		if UT.stat(ty, "m_ammo") > 0 and not art:
			d["skirm"] = 1 if int(o.get("on", 0)) != 0 else 0
	elif typ == ORDER_DEPLOY:
		if art:
			d["deploy"] = 1 if int(o.get("on", 0)) != 0 else 0
	elif typ == ORDER_FORAGE:
		if int(o.get("on", 0)) == 0:
			d["forage"] = 0
		elif forage_refusal(sim, u) == "":
			# Making arrows in the woods: it stands, does not shoot.
			d["forage"] = 1
			d["refill"] = 0
			d["order"] = O_NONE
			d["target"] = -1
			d["gtarget"] = -1
			d["dx"] = d["ax"]
			d["dy"] = d["ay"]
			d["dface"] = d["face"]
	elif typ == ORDER_REFILL:
		if art or (mis and carry < 0 and wallu == 0):
			var on := 1 if int(o.get("on", 0)) != 0 else 0
			d["refill"] = on
			d["forage"] = 0
			if on != 0:
				# Stand and resupply: stop moving and shooting.
				d["order"] = O_NONE
				d["target"] = -1
				d["dx"] = d["ax"]
				d["dy"] = d["ay"]
				d["dface"] = d["face"]
	elif typ == ORDER_WITHDRAW or typ == ORDER_WITHDRAW_ALL:
		d["order"] = O_WITHDRAW
		d["target"] = -1
		d["gtarget"] = -1
		d["run"] = 0 if art or carry >= 0 else 1
		d["dx"] = d["ax"]
		d["dy"] = sim.field_h if sim.u_side[u] == 0 else 0
		d["dface"] = 256 if sim.u_side[u] == 0 else 768
		if sim.sea_on != 0 and sim.u_side[u] == sim.city_def:
			# The sea is behind the defenders: off along the shore.
			var fp: Vector2i = sim.sea_exit(int(d["ax"]))
			d["dx"] = fp.x
			d["dy"] = fp.y
			d["dface"] = 512 if fp.x < sim.field_w / 2 else 0


# ------------------------------------------------------------ formation ---

## Number of files for a requested frontage (sim units).
static func width_to_files(width: int, alive: int, ty: int = 0) -> int:
	var fsp := UT.stat(ty, "file_sp")
	var f := (width + fsp / 2) / fsp
	return clampi(f, mini(MIN_FILES, maxi(alive, 1)), maxi(alive, 1))


## Frontage (sim units) of `files` files of type `ty`.
static func files_to_width(files: int, ty: int = 0) -> int:
	return files * UT.stat(ty, "file_sp")


## Offsets (interleaved x, y) of `count` slots relative to the front-centre
## anchor for a formation with `files` files facing `face`. Rows fill from
## the front; the last, partial rank is centred.
static func formation_offsets(count: int, files: int, face: int, ty: int = 0) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(count * 2)
	if UT.cls(ty) == UT.CLS_ART:
		# Engines in a row, crews round them (the preview of a battery).
		var c := FM.cos_a(face)
		var s := FM.sin_a(face)
		var ne := maxi(files, 1)
		for slot in count:
			var k := slot % ne
			var lat := ((2 * k - (ne - 1)) * UT.stat(ty, "file_sp")) / 2
			var ex := (-lat * s) / FM.TRIG_ONE
			var ey := (lat * c) / FM.TRIG_ONE
			var co := _crew_offset(slot / ne, face, ty)
			out[slot * 2] = ex + co.x
			out[slot * 2 + 1] = ey + co.y
		return out
	_fill_offsets(out, 0, count, files, face, true, PackedInt32Array(),
		UT.stat(ty, "file_sp"), UT.stat(ty, "rank_sp"))
	return out


static func _fill_offsets(out: PackedInt32Array, base: int, count: int, files: int,
		face: int, interleaved: bool, out_y: PackedInt32Array, fsp: int, rsp: int) -> void:
	files = maxi(files, 1)
	var c := FM.cos_a(face)
	var s := FM.sin_a(face)
	var full_ranks := count / files
	var last := count - full_ranks * files
	for slot in count:
		var rank := slot / files
		var file := slot - rank * files
		var k := files
		if rank == full_ranks:
			k = last
		var lat := ((2 * file - (k - 1)) * fsp) / 2
		var back := rank * rsp
		# forward = (c, s), right = (-s, c); offset = lat * right - back * forward
		var ox := (-back * c - lat * s) / FM.TRIG_ONE
		var oy := (-back * s + lat * c) / FM.TRIG_ONE
		if interleaved:
			out[base + slot * 2] = ox
			out[base + slot * 2 + 1] = oy
		else:
			out[base + slot] = ox
			out_y[base + slot] = oy


func _compute_offsets(u: int) -> void:
	var alive := u_alive[u]
	if alive <= 0:
		return
	if u_neng[u] > 0:
		_art_offsets(u)
		u_dirty[u] = 0
		return
	if u_wall[u] > 0:
		_wall_offsets(u)
		u_dirty[u] = 0
		return
	var files := mini(files_of(u), alive)
	var ty := u_type[u]
	# (Also coming down a stair, at its foot: before 2026-10-09 the block
	# stood across the wall there, men whose places lay on the walkway stayed
	# up, and the stair move waited its STAIR_MAX for them.)
	var flow := obs_on != 0 and u < _u_obs.size() and _u_obs[u] != 0
	if flow and u_flow[u] != 0 and tick - u_flt[u] < FLOW_EVERY:
		u_dirty[u] = 0  # (flowed a moment ago: the places stand; the dead's drop off the end)
		return
	_fill_offsets(off_x, u_slot_base[u], alive, files, u_face[u], false, off_y,
		t_fsp[ty], t_rsp[ty])
	if flow:
		_flow_slots(u)
	elif obs_on != 0:
		u_flow[u] = 0
	if not flow and city_on != 0 and n_cmp > 0 and u_stair[u] == 0 and u < _u_obs.size() and _u_obs[u] != 0:
		_project_slots(u)
	if u_contact[u] != 0 and occ0.size() > 0:
		_slots_off_enemy(u)
	u_dirty[u] = 0


## No man's place inside an enemy unit's footprint: such places move back
## (away from the unit's front) 2 m at a time, at most 8 m. Only when the
## offsets are recomputed with an enemy near, never per tick.
func _slots_off_enemy(u: int) -> void:
	var theirs: PackedInt32Array = occ1 if u_side[u] == 0 else occ0
	var gw := grid_w
	var gmax := grid_w * grid_h - 1
	var ax := u_ax[u]
	var ay := u_ay[u]
	var bx := -FM.cos_a(u_face[u]) * 2 * M / FM.TRIG_ONE
	var by := -FM.sin_a(u_face[u]) * 2 * M / FM.TRIG_ONE
	var base := u_slot_base[u]
	for s in u_alive[u]:
		var x := ax + off_x[base + s]
		var y := ay + off_y[base + s]
		# (On the seam - the enemy's cells reach ours there - it keeps its place:
		# only a place a cell deep in the enemy's footprint moves.)
		if theirs[clampi((y >> 12) * gw + (x >> 12), 0, gmax)] == 0 \
				or theirs[clampi(((y - 2 * by) >> 12) * gw + ((x - 2 * bx) >> 12), 0, gmax)] == 0:
			continue
		for q in 4:
			x += bx
			y += by
			if theirs[clampi((y >> 12) * gw + (x >> 12), 0, gmax)] == 0:
				break
		if obs_on != 0 and (nav_at(x, y) & _mask_of(u)) == 0:
			continue  # (back there is a wall or a house: it keeps its place)
		off_x[base + s] = x - ax
		off_y[base + s] = y - ay


## Units flow into the space (docs/DESIGN.md "Units flow into the space";
## maps with buildings or walls, foot only): unit u's formation rectangle
## (just laid out in off_x / off_y) is kept where it is whole. Where it is
## cut (places across a wall, in a house, on another piece of ground), or
## where the unit stands squeezed in a corridor fighting or queuing behind
## friends (it presses: all its places flow), the cut places are laid out
## again over the free 2 m cells nearest the anchor: a flood from the
## anchor's cell (neighbours +x, -x, +y, -y; open ground of its own, at
## most FLOW_AHEAD ahead of the anchor and, ahead of it, no other unit's
## footprint; at most FLOW_CELLS cells), each cell taking up to its share
## of men at FLOW_PACK % of the formation's density, places in slot order
## (the front rank nearest the anchor). Men keep to PLACE_LEAD / PLACE_SIDE
## of these places, so a column pressing into a gateway mouth spreads
## along it, a unit cut by a house corner goes round it, and the unit forms
## its rectangle again once that is whole. u_flow says which; u_flt when
## (the places stand FLOW_EVERY ticks, re-laid then or on an order).
func _flow_slots(u: int) -> void:
	var base := u_slot_base[u]
	var alive := u_alive[u]
	var ax := u_ax[u]
	var ay := u_ay[u]
	var gm := _ground_mask(u)
	var city := city_on != 0 and n_cmp > 0
	# The flood starts at the anchor's cell, else (the anchor at a house's
	# edge) the nearest open cell round it (rings of 2 m, in index order).
	var a0 := Vector2i(ax, ay)
	if (nav_at(ax, ay) & gm) == 0:
		a0 = Vector2i(-1, -1)
		for r in range(1, 3):
			for dj in range(-r, r + 1):
				for di in range(-r, r + 1):
					if a0.x < 0 and maxi(absi(di), absi(dj)) == r \
							and (nav_at(ax + di * 2048, ay + dj * 2048) & gm) != 0:
						a0 = Vector2i(ax + di * 2048, ay + dj * 2048)
	var ra := reach_at(a0.x, a0.y)
	if a0.x < 0 or (city and ra < 0):
		u_flow[u] = 0
		if city:
			_project_slots(u)
		return
	var press := u_blk[u] == BLK_QUEUE or (u_sq[u] > 0 and u_fighting[u] > 0)
	# Which places are cut.
	var cut := PackedInt32Array()
	if press:
		cut.resize(alive)
		for s in alive:
			cut[s] = s
	else:
		for s in alive:
			var x := ax + off_x[base + s]
			var y := ay + off_y[base + s]
			if (reach_at(x, y) != ra) if city else (nav_at(x, y) & gm) == 0:
				cut.append(s)
	if cut.is_empty():
		u_flow[u] = 0
		return
	u_flow[u] = 1
	u_flt[u] = tick
	var ty := u_type[u]
	var cap := clampi(4194304 * FLOW_PACK / 100 / maxi(t_fsp[ty] * t_rsp[ty], 1), 1, 6)
	_fl_stamp += 1
	if _fl_stamp >= 1 << 22:
		_fl_stamp = 1
		_fl_mark.fill(0)
	var stp := _fl_stamp << 8
	var mk := _fl_mark
	var obw := ob_w
	var obh := ob_h
	if not press:
		# The whole places take their cells' room first.
		var cj := 0
		for s in alive:
			if cj < cut.size() and cut[cj] == s:
				cj += 1
				continue
			var x := ax + off_x[base + s]
			var y := ay + off_y[base + s]
			var k := clampi(y >> 11, 0, obh - 1) * obw + clampi(x >> 11, 0, obw - 1)
			mk[k] = (mk[k] + 1) if (mk[k] & ~255) == stp else stp + 1  # (count bits 0-3; cap <= 6)
	var fc := FM.cos_a(u_face[u])
	var fs := FM.sin_a(u_face[u])
	var mine: PackedInt32Array = occ0 if u_side[u] == 0 else occ1
	var theirs: PackedInt32Array = occ1 if u_side[u] == 0 else occ0
	var gw := grid_w
	var gmax := grid_w * grid_h - 1
	var q := _fl_q
	var k0 := clampi(a0.y >> 11, 0, obh - 1) * obw + clampi(a0.x >> 11, 0, obw - 1)
	q[0] = k0
	var qn := 1
	var qh := 0
	mk[k0] = ((mk[k0] & 15) if (mk[k0] & ~255) == stp else 0) | stp | 16  # (16: queued)
	var need := cut.size()
	var ci := 0
	var spots := [Vector2i(-512, -512), Vector2i(512, 512), Vector2i(512, -512), Vector2i(-512, 512),
		Vector2i(0, 0), Vector2i(0, -768)]
	while qh < qn and ci < need:
		var k := q[qh]
		qh += 1
		var ki := k % obw
		var kj := k / obw
		# Men into this cell (its room after the whole places in it).
		var used := mk[k] & 15
		if used < cap:
			var cx := ki * 2048 + 1024
			var cy := kj * 2048 + 1024
			while used < cap and ci < need:
				var s := cut[ci]
				var sp: Vector2i = spots[used]
				off_x[base + s] = cx + sp.x - ax
				off_y[base + s] = cy + sp.y - ay
				used += 1
				ci += 1
			mk[k] = stp | 16 | used
		# On to its neighbours.
		for nb in 4:
			if qn >= FLOW_CELLS:
				break
			var ni := ki + (1 if nb == 0 else (-1 if nb == 1 else 0))
			var nj := kj + (1 if nb == 2 else (-1 if nb == 3 else 0))
			if ni < 0 or nj < 0 or ni >= obw or nj >= obh:
				continue
			var kk := nj * obw + ni
			var mv := mk[kk]
			if (mv & ~255) == stp and (mv & 16) != 0:
				continue  # (queued already)
			if (nav[kk] & gm) == 0:
				continue
			var nx := ni * 2048 + 1024
			var ny := nj * 2048 + 1024
			var fwd := ((nx - ax) * fc + (ny - ay) * fs) / FM.TRIG_ONE
			if fwd > FLOW_AHEAD:
				continue
			if fwd > 0:
				# Ahead of the anchor: not into another unit's footprint.
				var oc := clampi((ny >> 12) * gw + (nx >> 12), 0, gmax)
				if theirs[oc] != 0:
					continue
				var w := mine[oc]
				if w != 0 and (((w >> 16) - 1) != u or (w & 255) > 1):
					continue
			mk[kk] = ((mv & 15) if (mv & ~255) == stp else 0) | stp | 16
			q[qn] = kk
			qn += 1
	if ci < need:
		# (No more room near: the rest keep their places, brought in to
		# their own ground as before.)
		if city:
			for t in range(ci, need):
				_project_one(u, cut[t], ra)
	stat_flow += 1


## Settlement maps: a man's place that falls across a wall, in a house or on
## ground of another piece than the anchor's comes in toward the anchor to
## the first open ground of its piece (his side of the anchor), so no man
## tries for a place he cannot reach. Only when the offsets are recomputed
## (an order, a turn, the end of a move), never per tick.
func _project_slots(u: int) -> void:
	var ax := u_ax[u]
	var ay := u_ay[u]
	var ra := reach_at(ax, ay)
	if ra < 0:
		return
	for s in u_alive[u]:
		_project_one(u, s, ra)


## Place s of unit u (anchor on piece ra) in toward the anchor to the first
## open ground of its piece (_project_slots).
func _project_one(u: int, s: int, ra: int) -> void:
	var ax := u_ax[u]
	var ay := u_ay[u]
	var base := u_slot_base[u]
	var ox := off_x[base + s]
	var oy := off_y[base + s]
	if reach_at(ax + ox, ay + oy) == ra:
		return
	var steps := FM.approx_len(ox, oy) / M + 1
	var q := 1
	while q <= steps:
		var px := ox * (steps - q) / steps
		var py := oy * (steps - q) / steps
		if reach_at(ax + px, ay + py) == ra or q == steps:
			off_x[base + s] = px
			off_y[base + s] = py
			break
		q += 1


## Where crew member j of an engine stands, relative to the engine facing
## `face`: beside and behind it (stone throwers are bigger).
static func _crew_offset(j: int, face: int, ty: int) -> Vector2i:
	var back := 0
	var side := 0
	match j:
		0: back = 1400; side = -900
		1: back = 1400; side = 900
		2: back = 2500; side = -500
		3: back = 2500; side = 500
		4: back = 300; side = -1400
		5: back = 300; side = 1400
		_: back = 3400 + (j - 6) * 900; side = 0
	if UT.stat(ty, "m_kind") == 2:
		back = back * 3 / 2
		side = side * 3 / 2
	var c := FM.cos_a(face)
	var s := FM.sin_a(face)
	return Vector2i((-back * c - side * s) / FM.TRIG_ONE, (-back * s + side * c) / FM.TRIG_ONE)


## Working engines of battery u (wrecked / abandoned ones are skipped); all
## of them if none works, so the crew still has places to stand.
func _working_engines(u: int) -> PackedInt32Array:
	var w := PackedInt32Array()
	var e0 := u_eng0[u]
	for k in u_neng[u]:
		if e_state[e0 + k] == E_OK:
			w.append(e0 + k)
	if w.is_empty():
		for k in u_neng[u]:
			w.append(e0 + k)
	return w


## Crew slots of battery u: slot s works engine W[s % nw] and stands round
## it (relative to where the engine actually is and how it is turned).
func _art_offsets(u: int) -> void:
	var w := _working_engines(u)
	var nw := w.size()
	var base := u_slot_base[u]
	var ty := u_type[u]
	var cap := _crew_cap(u)
	for slot in u_alive[u]:
		var e := w[slot % nw]
		var j := slot / nw
		var co := _crew_offset(j, e_face[e], ty) if j < cap else _spare_offset(j - cap, e_face[e], ty)
		off_x[base + slot] = e_x[e] - u_ax[u] + co.x
		off_y[base + slot] = e_y[e] - u_ay[u] + co.y


## Men of unit u who work each of its engines at most. A battery working
## engines of its own kind: all of them (its survivors re-man the engines
## left, as always); other men taking up engines: the engines' full crew,
## the rest stand behind (_spare_offset) and do not work them.
func _crew_cap(u: int) -> int:
	return 1 << 20 if u_otype[u] == u_type[u] else t_crew[u_type[u]]


## Where spare man k (beyond the crew) of an engine stands: in rows of four
## behind it.
static func _spare_offset(k: int, face: int, ty: int) -> Vector2i:
	var back := (5600 if UT.stat(ty, "m_kind") == 2 else 4400) + (k / 4) * 1200
	var side := (k % 4) * 1100 - 1650
	var c := FM.cos_a(face)
	var s := FM.sin_a(face)
	return Vector2i((-back * c - side * s) / FM.TRIG_ONE, (-back * s + side * c) / FM.TRIG_ONE)


## Depth (front to back) of a unit's formation in sim units.
func unit_depth(u: int) -> int:
	var files := maxi(mini(files_of(u), u_alive[u]), 1)
	var ranks := (u_alive[u] + files - 1) / files
	return maxi(ranks - 1, 0) * t_rsp[u_type[u]]


## Half the frontage of a unit's formation in sim units.
func unit_half_width(u: int) -> int:
	var files := maxi(mini(files_of(u), u_alive[u]), 1)
	return (files - 1) * t_fsp[u_type[u]] / 2


# ----------------------------------------------------------------- step ---

func step() -> void:
	if phase == PHASE_DEPLOY:
		_deploy_step()
		return
	_dist_new = 0
	_apply_orders()
	if city_on != 0:
		SiegeAI.think(self)
	else:
		BattleAI.think(self)
	_apply_orders()  # AI orders are queued for this tick
	prev_x = pos_x.duplicate()
	prev_y = pos_y.duplicate()
	if n_eng > 0:
		e_px = e_x.duplicate()
		e_py = e_y.duplicate()
	_update_units()
	_update_contacts()
	_build_grid()
	_update_soldiers()
	if fw_on != 0:
		_update_works()
	if n_eq > 0:
		_update_equip()
	if n_gates > 0:
		_update_gates()
	if n_eng > 0:
		for u in n_units:
			if u_pick[u] >= PICK_ENG:
				_pick_check(u)  # going to take up engines left on the field
		_update_artillery()
	if veg_on != 0 or sg_on != 0:
		_update_supply()
	_update_missiles()
	if fire_on != 0:
		_update_fire()
	_refresh_offsets()
	_update_morale()
	if city_on != 0:
		_update_capture()
	_check_winner()
	tick += 1


## Turn unit u's formation toward `want`, limited by the type's turn rate.
func _turn(u: int, want: int) -> void:
	var diff := FM.angle_diff(u_face[u], want)
	var rate := t_turn[u_type[u]]
	if u_neng[u] > 0 and u_depl[u] == 0:
		rate = PACKED_TURN
	if rate > 0 and u_scare[u] > 0:
		rate = maxi(rate * u_scare[u] / 100, 1)  # horses balking at camels near
	if rate == 0:
		if absi(diff) > 3:
			u_face[u] = want
			u_dirty[u] = 1
		return
	if diff == 0:
		return
	if absi(diff) <= rate:
		u_face[u] = want
	elif diff > 0:
		u_face[u] = (u_face[u] + rate) & FM.ANGLE_MASK
	else:
		u_face[u] = (u_face[u] - rate) & FM.ANGLE_MASK
	u_dirty[u] = 1


# ------------------------------------------------------ unit footprints ---

## Mark every ready ground unit's footprint in the 4 m cells of its side
## (occ0 / occ1): its formation rectangle (the anchor at its front centre,
## OCC_FRONT ahead, OCC_PAD beyond its outer files and rear rank, half
## extents at least OCC_MIN), the cells whose centre lies inside it and
## within its men's box (padded): per unit, row by row (each row's run of
## cells worked out from the rectangle's edges), never per soldier.
## Routing units, units on a wall or a stair, ladder parties climbing and
## tower engines are not obstacles. Units in index order, so the first unit
## of a cell is the lowest index (a pure function of the state).
func _build_occ() -> void:
	occ0.fill(0)
	occ1.fill(0)
	var o0 := occ0
	var o1 := occ1
	var gw := grid_w
	var gh := grid_h
	var ust := u_state
	var ual := u_alive
	var uwl := u_wall
	var ustr := u_stair
	var uty := u_type
	var usd := u_side
	var ufi := u_fighting
	var ubk := u_blk
	var mnx := u_minx
	var mxx := u_maxx
	var mny := u_miny
	var mxy := u_maxy
	var uax := u_ax
	var uay := u_ay
	var ufc := u_face
	var ucl := u_cls
	for u in n_units:
		var alive := ual[u]
		if ust[u] != U_READY or alive <= 0 or uwl[u] > 0 or ustr[u] != 0:
			continue
		var ty := uty[u]
		if t_fixed[ty] != 0:
			continue
		var occ: PackedInt32Array = o0 if usd[u] == 0 else o1
		# (Units waiting behind fighting friends count as the line too, so the
		# next ones queue behind them rather than in them. u_blk is last tick's.)
		var add := 257 if ufi[u] > 0 or ubk[u] == BLK_QUEUE else 1
		var own := (u + 1) << 16
		# Cells of the men's box (padded; beasts by their bodies too).
		var pad := OCC_PAD + t_body_r[ty]
		var i0 := maxi((mnx[u] - pad) >> 12, 0)
		var i1 := mini((mxx[u] + pad) >> 12, gw - 1)
		var j0 := maxi((mny[u] - pad) >> 12, 0)
		var j1 := mini((mxy[u] + pad) >> 12, gh - 1)
		if ucl[u] == UT.CLS_ART:
			# A battery: its engines and crews stand round the line of engines;
			# the men's box is close enough.
			for j in range(j0, j1 + 1):
				var row := j * gw
				for i in range(i0, i1 + 1):
					var v := occ[row + i]
					occ[row + i] = (v + add) if v >= 65536 else (v + add) | own
			continue
		# The formation rectangle in the unit's frame: along its facing
		# f in [-back, OCC_FRONT], across it l in [-hw, hw] (x 4096).
		# (unit_half_width / unit_depth inlined.)
		var files := maxi(mini(u_sq[u] if u_sq[u] > 0 else u_files[u], alive), 1)
		var c := FM.cos_a(ufc[u])
		var s := FM.sin_a(ufc[u])
		var hw := maxi((files - 1) * t_fsp[ty] / 2 + t_fsp[ty] / 2 + OCC_PAD, OCC_MIN)
		var back := maxi(((alive + files - 1) / files - 1) * t_rsp[ty] + t_rsp[ty] / 2 + OCC_PAD,
			2 * OCC_MIN - OCC_FRONT)
		var fmax := OCC_FRONT * 4096
		var fmin := -back * 4096
		var lmax := hw * 4096
		var ax := uax[u]
		var ay := uay[u]
		# Rows of the rectangle's own box too.
		var ey := ((s if s >= 0 else -s) * (back + OCC_FRONT) + (c if c >= 0 else -c) * 2 * hw) / 8192
		var my := ay + s * (OCC_FRONT - back) / 8192
		j0 = maxi(j0, (my - ey - 2048) >> 12)
		j1 = mini(j1, (my + ey - 2048) >> 12)
		var dy := j0 * 4096 + 2048 - ay
		for j in range(j0, j1 + 1):
			# Along the row (x' = x - ax): f = x' c + dy s, l = -x' s + dy c.
			var fb := dy * s
			var lb := dy * c
			dy += 4096
			var xlo := -(1 << 40)
			var xhi := 1 << 40
			if c > 0:
				xlo = (fmin - fb) / c
				xhi = (fmax - fb) / c
			elif c < 0:
				xlo = (fmax - fb) / c
				xhi = (fmin - fb) / c
			elif fb < fmin or fb > fmax:
				continue
			if s > 0:
				xlo = maxi(xlo, (lb - lmax) / s)
				xhi = mini(xhi, (lb + lmax) / s)
			elif s < 0:
				xlo = maxi(xlo, (lb + lmax) / s)
				xhi = mini(xhi, (lb - lmax) / s)
			elif lb < -lmax or lb > lmax:
				continue
			if xlo > xhi:
				continue
			# Cells whose centre (i * 4 m + 2 m) lies in [ax + xlo, ax + xhi].
			var ia := maxi(-((2048 - ax - xlo) >> 12), i0)
			var ib := mini((ax + xhi - 2048) >> 12, i1)
			var row := j * gw
			for k in range(row + ia, row + ib + 1):
				var v := occ[k]
				occ[k] = (v + add) if v >= 65536 else (v + add) | own


## What unit u's anchor would meet stepping from (ox, oy) to (x, y), its
## front corners (rx, ry) either side (t: the unit it attacks, -1 none): BLK_ENEMY (an
## enemy's footprint it is not already inside and backing out of), BLK_QUEUE
## (u attacks and is not fighting: friends fighting near its target ahead),
## BLK_FRIEND (another friend's footprint: half speed), 0 free. _blk_u: the
## unit met.
func _occ_probe(u: int, ox: int, oy: int, x: int, y: int, rx: int, ry: int, t: int) -> int:
	var gw := grid_w
	var gmax := grid_w * grid_h - 1
	var mine: PackedInt32Array = occ0 if u_side[u] == 0 else occ1
	var theirs: PackedInt32Array = occ1 if u_side[u] == 0 else occ0
	var sx := x - ox
	var sy := y - oy
	# Enemy footprints: the anchor and the two front corners (rx, ry out).
	for q in 3:
		var px := x
		var py := y
		var qx := ox
		var qy := oy
		if q == 1:
			px += rx; py += ry; qx += rx; qy += ry
		elif q == 2:
			px -= rx; py -= ry; qx -= rx; qy -= ry
		var v := theirs[clampi((py >> 12) * gw + (px >> 12), 0, gmax)]
		if v == 0:
			continue
		var b := (v >> 16) - 1
		# Already inside it (it came to us, or our men are mixed with its):
		# moving away from its centre is allowed.
		if theirs[clampi((qy >> 12) * gw + (qx >> 12), 0, gmax)] != 0 \
				and sx * (qx - u_cx[b]) + sy * (qy - u_cy[b]) >= 0:
			continue
		_blk_u = b
		return BLK_ENEMY
	var k := clampi((y >> 12) * gw + (x >> 12), 0, gmax)
	var w := mine[k]
	if w == 0:
		return 0
	var cnt := w & 255
	var own := (w >> 16) - 1
	if cnt == 1 and own == u:
		return 0
	if t >= 0 and u_fighting[u] == 0 and ((w >> 8) & 255) > 0 and u_fighting[t] > 0 \
			and x >= u_minx[t] - OCC_QUEUE and x <= u_maxx[t] + OCC_QUEUE \
			and y >= u_miny[t] - OCC_QUEUE and y <= u_maxy[t] + OCC_QUEUE:
		# Friends are fighting our target here: the line; wait behind it.
		_blk_u = own if own != u else -1
		return BLK_QUEUE
	_blk_u = own if own != u else -1
	return BLK_FRIEND


## Unit u's anchor steps from (ox, oy) toward (nx, ny) (t: the unit it
## attacks, -1 a move): into an enemy's footprint it may not (it steers
## round it if there is room: 30 or 60 degrees off with a free cell beyond,
## on the side it chose first, never round its own target; else it stops
## there, except into its own target while none of its men is within reach
## of his man yet), behind friends
## fighting its target it waits (or goes round them), through other friends
## it goes at half speed. Sets u_blk / u_dodge. Returns where it gets to.
func _anchor_step(u: int, ox: int, oy: int, nx: int, ny: int, t: int, spd: int) -> Vector2i:
	var p := _anchor_step0(u, ox, oy, nx, ny, t, spd)
	if obs_on == 0 or (p.x == ox and p.y == oy):
		return p
	# Maps with buildings or walls: the anchor keeps to ground its men can
	# stand on (from open ground it does not step into a wall or a house:
	# along one axis, else it stays). A path's shortcut past a wall's corner
	# had an anchor cut through it, its men left on the other side.
	var gm := _ground_mask(u)
	if (nav_at(p.x, p.y) & gm) != 0 or (nav_at(ox, oy) & gm) == 0:
		return p
	stat_anchor_kept += 1
	# Along the obstacle: the whole step on the axis it goes most along,
	# else the other (the sign of its way on that axis).
	var sx := p.x - ox
	var sy := p.y - oy
	var l := FM.approx_len(sx, sy)
	var ax1 := Vector2i(ox + (l if sx > 0 else -l), oy)
	var ay1 := Vector2i(ox, oy + (l if sy > 0 else -l))
	var first := ax1 if absi(sx) >= absi(sy) else ay1
	var second := ay1 if absi(sx) >= absi(sy) else ax1
	if (absi(sx) >= absi(sy) and sx != 0) or (absi(sy) > absi(sx) and sy != 0):
		if (nav_at(first.x, first.y) & gm) != 0:
			return first
	if (absi(sx) >= absi(sy) and sy != 0) or (absi(sy) > absi(sx) and sx != 0):
		if (nav_at(second.x, second.y) & gm) != 0:
			return second
	# Square against it: no way along it from here. Its way is planned again
	# (now and then): the path's straight stretch to its next waypoint was
	# found clear from where it was, not from here.
	if (tick + u) % 10 == 0:
		u_pn[u] = 0
	return Vector2i(ox, oy)


func _anchor_step0(u: int, ox: int, oy: int, nx: int, ny: int, t: int, spd: int) -> Vector2i:
	var sx := nx - ox
	var sy := ny - oy
	if sx == 0 and sy == 0:
		return Vector2i(nx, ny)
	# Front corners: across the unit's facing, at most OCC_CORNER out.
	var hw := mini(unit_half_width(u), OCC_CORNER)
	var rx := -FM.sin_a(u_face[u]) * hw / FM.TRIG_ONE
	var ry := FM.cos_a(u_face[u]) * hw / FM.TRIG_ONE
	# Nothing there (most steps): straight on.
	var gw := grid_w
	var gmax := grid_w * grid_h - 1
	var theirs: PackedInt32Array = occ1 if u_side[u] == 0 else occ0
	var mine: PackedInt32Array = occ0 if u_side[u] == 0 else occ1
	var ci := clampi((ny >> 12) * gw + (nx >> 12), 0, gmax)
	if theirs[ci] == 0 and mine[ci] == 0 and theirs[clampi(((ny + ry) >> 12) * gw + ((nx + rx) >> 12), 0, gmax)] == 0 \
			and theirs[clampi(((ny - ry) >> 12) * gw + ((nx - rx) >> 12), 0, gmax)] == 0:
		u_dodge[u] = 0
		return Vector2i(nx, ny)
	var k := _occ_probe(u, ox, oy, nx, ny, rx, ry, t)
	if k <= BLK_FRIEND:
		u_dodge[u] = 0
		u_blk[u] = k
		if k == BLK_FRIEND:
			stat_pass += 1
			return _half_step(ox, oy, sx, sy, spd)
		return Vector2i(nx, ny)
	var b := _blk_u
	if k == BLK_ENEMY and b == t and (u_inreach[u] == 0 or t_chase[u_type[u]] != 0):
		# Its own target, and none of its men within reach yet (they keep
		# to within PLACE_LEAD of their places): press on into contact.
		u_dodge[u] = 0
		u_blk[u] = 0
		return Vector2i(nx, ny)
	if not (k == BLK_ENEMY and b == t):
		# Round it: first on the side chosen before, else away from its
		# centre (the side it lies less on).
		var side := u_dodge[u]
		if side == 0:
			side = 1
			if b >= 0 and sx * (u_cy[b] - oy) - sy * (u_cx[b] - ox) > 0:
				side = -1
		var gm := _ground_mask(u) if obs_on != 0 else 0
		var sl := maxi(FM.approx_len(sx, sy), 1)
		for a in DODGE:
			for sd in [side, -side]:
				var ca := FM.cos_a(a)
				var sa: int = FM.sin_a(a) * sd
				var dx := (sx * ca - sy * sa) / FM.TRIG_ONE
				var dy := (sx * sa + sy * ca) / FM.TRIG_ONE
				var px := clampi(ox + dx, 0, field_w)
				var py := clampi(oy + dy, 0, field_h)
				# Room that way: a cell further on is free too.
				var lx := clampi(ox + dx * DODGE_LOOK / sl, 0, field_w)
				var ly := clampi(oy + dy * DODGE_LOOK / sl, 0, field_h)
				if gm != 0 and ((nav_at(px, py) & gm) == 0 or (nav_at(lx, ly) & gm) == 0):
					continue
				var k2 := _occ_probe(u, ox, oy, px, py, rx, ry, t)
				if k2 <= BLK_FRIEND and _occ_probe(u, ox, oy, lx, ly, rx, ry, t) <= BLK_FRIEND:
					u_dodge[u] = sd
					u_blk[u] = k
					stat_dodge += 1
					if k2 == BLK_FRIEND:
						return _half_step(ox, oy, px - ox, py - oy, spd)
					return Vector2i(px, py)
	u_blk[u] = k
	if k == BLK_ENEMY:
		stat_blocked += 1
	else:
		stat_queued += 1
	return Vector2i(ox, oy)


## A step (sx, sy) from (ox, oy) through friends: at most half the speed.
func _half_step(ox: int, oy: int, sx: int, sy: int, spd: int) -> Vector2i:
	var l := FM.approx_len(sx, sy)
	var h := maxi(spd / 2, 1)
	if l <= h:
		return Vector2i(ox + sx, oy + sy)
	return Vector2i(ox + sx * h / l, oy + sy * h / l)


func _update_units() -> void:
	var ton := ter_on != 0
	var mon := map_on != 0
	var oon := obs_on != 0
	if (tick & 1) == 0:
		_build_occ()  # (every other tick: footprints move little in 0.2 s)
	for u in n_units:
		u_moved[u] = 0
		u_blk[u] = 0
		if (ton or oon or fwh_on != 0) and u_alive[u] > 0:
			u_h[u] = _unit_elev(u) if oon or fwh_on != 0 else height_at(u_cx[u], u_cy[u])
		if oon and u_alive[u] > 0:
			_u_obs[u] = _near_obs(u)
			if u_stair[u] == 1 or u_stair[u] == 3:
				_stair_check(u)
			elif u_stair[u] == ST_LADDER and u_state[u] == U_READY:
				_ladder_step(u)
		if u_state[u] != U_READY:
			u_formed[u] = 0
			u_braced[u] = 0
			u_mom[u] = 0
			if u_rprog[u] > 0 or u_refill[u] != 0:
				stat_refill_broken += 1  # routed: the refill is abandoned
				u_rprog[u] = 0
				u_refill[u] = 0
			if oon and u_state[u] == U_ROUTING and u_alive[u] > 0:
				_flee_step(u)
			continue
		var ty := u_type[u]
		var cls := u_cls[u]
		var speed := t_run[ty] if u_run[u] != 0 else t_walk[ty]
		if sg_on != 0 and u_carry[u] >= 0:
			# Carrying siege equipment: no running, the piece's pace (the
			# ram's, a little below the walk with ladders, a siege tower's
			# slower still and slower again with too few men pushing); a
			# wagon at its pace (its horses alive: theirs; none: the crew's).
			var cq := u_carry[u]
			if q_kind[cq] == EQ_WAGON:
				speed = UT.wagon_pace(q_tier[cq], q_hn[cq])
			else:
				speed = carry_pace(t_walk[ty], q_kind[cq], u_alive[u])
		var aspeed := (speed * 7) >> 3
		# Woods under the anchor: slower, and (below) disorder and a lower
		# momentum cap; settlement streets cap a charge too.
		var vd := 0
		var urban := false
		if mon:
			var vb := veg_bits(u_ax[u], u_ay[u])
			vd = vb & MapGen.V_DENS
			urban = (vb & MapGen.V_URBAN) != 0
			var vf: int = VEG_SPEED[cls][vd]
			if vd > 0 and t_woods[ty] != 100:
				vf = maxi(1000 - (1000 - vf) * t_woods[ty] / 100, 100)  # (camels, elephants among trees)
			_u_vfac[u] = vf
			if vf < 1000:
				aspeed = aspeed * vf / 1000
				stat_veg_slow += 1
		if fw_on != 0 and (u_fws[u] < 100 or u_fwc[u] > 0):
			# Men in field works (stakes, caltrops, a ditch, a rampart's
			# bank): the formation keeps to their pace.
			aspeed = aspeed * u_fws[u] / 100
			if u_fwc[u] > 0:
				aspeed = mini(aspeed, u_fwc[u])
		if tick - u_shelled_t[u] < PIN_TICKS and u_run[u] == 0 and city_on == 0 and u_order[u] != O_WITHDRAW \
				and u_fighting[u] == 0 and u_charge[u] == 0 and cls != UT.CLS_ART:
			# Pinned: a unit just struck by an artillery shot goes to ground
			# for 0.8 s (docs/DESIGN.md "Artillery"): its anchor does not
			# advance, so a unit walking into a battery's fire is held (not
			# one running in: a charge or a rush goes through; field maps
			# only: wall and tower engines are the siege block's).
			aspeed = 0
		if city_ditch != 0 and obs_kind(u_ax[u], u_ay[u]) == MapGen.C_DITCH:
			# Crossing the ditch (foot only): slowly.
			aspeed = aspeed * DITCH_SPEED / 1000
			_u_vfac[u] = _u_vfac[u] * DITCH_SPEED / 1000
			stat_ditch += 1
		var lag := 0
		if oon and _u_obs[u] != 0 and u_fighting[u] == 0 and u_charge[u] == 0 and u_wall[u] == 0 \
				and u_stair[u] == 0:
			lag = FM.approx_len(u_cx[u] - u_ax[u], u_cy[u] - u_ay[u]) - unit_depth(u) / 2
		if lag > LAG_CUT:
			# Among walls and houses: slow down for the men strung out
			# behind (they follow the trail of waypoints the anchor passed);
			# still cut off from the anchor after REGROUP ticks (a wall or
			# houses between): regroup where they are.
			if lag > LAG_HOLD:
				aspeed /= 4
			u_lagt[u] += 1
			if u_lagt[u] >= REGROUP:
				_regroup(u)
		elif u_lagt[u] != 0:
			u_lagt[u] = 0
		var ax0 := u_ax[u]
		var ay0 := u_ay[u]
		var order := u_order[u]
		if u_stair[u] == 1 or u_stair[u] == ST_LADDER:
			order = O_NONE  # waiting at the stair's foot for its men to come down; climbing (a move waits)
		var want := lag > LAG_CUT  # (u_stuck: it wants to get on; its men short of their places)
		var want_face := u_dface[u]
		var art := cls == UT.CLS_ART
		# Ground under the anchor (hilly maps; one lookup serves the whole
		# tick: movement, formation and charge momentum).
		var g0 := slope_at(u_ax[u], u_ay[u]) if ton else Vector2i.ZERO
		if art and u_rprog[u] > 0:
			# Refilling (or getting into / out of it): it stands, does not
			# turn, and moves on only once it is back out.
			want_face = u_face[u]
		elif art and (order == O_MOVE or order == O_WITHDRAW) and u_depl[u] > 0:
			# Packing up first: the battery cannot move until it is packed.
			want_face = u_face[u]
		elif art and order != O_MOVE and order != O_WITHDRAW:
			# Batteries never close on a target: they turn to bring it into
			# their arc (attack order or fire at will) and shoot from here.
			want_face = u_dface[u]
			var at := u_target[u] if order == O_ATTACK else u_ftarget[u]
			var gt := u_gtarget[u] if order == O_ATTACK else -1
			if gt >= 0:
				# Shooting at a gate: turn to bring it into the arc; done once
				# it is open or broken.
				at = -1
				if gt >= n_gates or g_state[gt] != GATE_CLOSED:
					u_order[u] = O_NONE
					u_gtarget[u] = -1
				else:
					var gf := gate_face(gt)
					var gbear := FM.atan2_a(gf.y - u_cy[u], gf.x - u_cx[u])
					if absi(FM.angle_diff(u_face[u], gbear)) > t_arc[ty]:
						want_face = gbear
						u_dface[u] = gbear
			elif order == O_ATTACK and (at < 0 or u_state[at] >= U_DESTROYED):
				u_order[u] = O_NONE
				u_target[u] = -1
				at = -1
			if at >= 0 and at < n_units and u_state[at] < U_DESTROYED:
				var bear := FM.atan2_a(u_cy[at] - u_cy[u], u_cx[at] - u_cx[u])
				if absi(FM.angle_diff(u_face[u], bear)) > t_arc[ty]:
					want_face = bear
					u_dface[u] = bear
		elif order == O_MOVE or order == O_WITHDRAW:
			# On a settlement map the anchor follows a path through the
			# streets and gates (waypoints before the destination).
			var wx := u_dx[u]
			var wy := u_dy[u]
			var via := false
			if oon and u_wall[u] == 0:
				var wp := _path_point(u, u_dx[u], u_dy[u], false)
				if wp.x != wx or wp.y != wy:
					via = true
					wx = wp.x
					wy = wp.y
			var dx := wx - u_ax[u]
			var dy := wy - u_ay[u]
			var d := FM.isqrt(dx * dx + dy * dy)
			if ton and d > 0:
				aspeed = aspeed * _fac_dir(u, g0, dx, dy, d) / 1000
			var arrive := d <= aspeed
			var mnx := wx if arrive else u_ax[u] + dx * aspeed / d
			var mny := wy if arrive else u_ay[u] + dy * aspeed / d
			if d > 0:
				want = true
				# Other units in the way: round them, through friends slowly.
				var ms := _anchor_step(u, u_ax[u], u_ay[u], mnx, mny, -1, aspeed)
				if ms.x != mnx or ms.y != mny:
					arrive = false
					mnx = ms.x
					mny = ms.y
			if arrive:
				u_ax[u] = wx
				u_ay[u] = wy
				if order == O_MOVE and not via:
					u_order[u] = O_NONE
					if city_on != 0:
						u_dirty[u] = 1  # there: its places again (kept to its own ground)
					if u_stair[u] == 2:
						_climb(u)  # at the stair's foot: up
					elif u_stair[u] == ST_LADDER_GO:
						_ladder_start(u)  # at the foot of the wall: up the ladders
			else:
				u_ax[u] = mnx
				u_ay[u] = mny
				# March facing the direction of travel; turn to the final
				# facing for the last stretch.
				if via or d > REFORM_IN_PLACE_DIST:
					want_face = FM.atan2_a(dy, dx)
				if u_stair[u] == ST_LADDER_GO and order == O_MOVE and _ladder_reached(u):
					# Near enough the foot (its men cannot all fit between the
					# anchor and the wall): up the ladders from here.
					u_order[u] = O_NONE
					_ladder_start(u)
		elif order == O_ATTACK:
			var t := u_target[u]
			if t < 0 or u_state[t] >= U_DESTROYED:
				u_order[u] = O_NONE
				u_target[u] = -1
				u_dface[u] = u_face[u]
				want_face = u_face[u]
			else:
				var dx := u_cx[t] - u_ax[u]
				var dy := u_cy[t] - u_ay[u]
				var d := FM.isqrt(dx * dx + dy * dy)
				want_face = u_face[u]  # engaged: hold the facing
				# Settlement map: go round by the streets while the target
				# cannot be reached straight.
				var via := false
				var held := false
				# (u_inreach, not u_fighting: men holding to their places
				# leave the closing to the anchor, which goes by the streets.)
				if oon and u_wall[u] == 0 and u_charge[u] == 0 and u_inreach[u] == 0 \
						and not (cls == UT.CLS_MISSILE and u_ammo[u] > 0 and d <= range_vs(u, t)):
					var goal := _attack_goal(u, t)
					if city_on != 0:
						# Out of reach (another piece of ground: a shut gate
						# between): to the gate (melee), or as near as its own
						# ground goes (missile troops, shooting once in range).
						var ug := unreach_goal(u, t, goal)
						if ug.z != 0:
							goal = Vector2i(ug.x, ug.y)
							held = true
							stat_unreach += 1
					var wp := _path_point(u, goal.x, goal.y, true)
					var gd := FM.approx_len(goal.x - u_ax[u], goal.y - u_ay[u])
					if wp.x != goal.x or wp.y != goal.y or (held and gd > M / 4):
						via = true
						var vx := wp.x - u_ax[u]
						var vy := wp.y - u_ay[u]
						var vdd := FM.isqrt(vx * vx + vy * vy)
						if vdd > 0:
							want = true
							want_face = FM.atan2_a(vy, vx)
							var mv0 := mini(aspeed, vdd)
							var vs := _anchor_step(u, u_ax[u], u_ay[u], u_ax[u] + vx * mv0 / vdd,
								u_ay[u] + vy * mv0 / vdd, t, aspeed)
							u_ax[u] = vs.x
							u_ay[u] = vs.y
				if via:
					pass
				elif held:
					# At the gate (or as near as it gets): it holds there, its
					# places now and then kept to its own ground.
					if (tick + u) % 10 == 0:
						u_dirty[u] = 1
				elif u_charge[u] != 0:
					pass  # riders resolve the charge themselves; anchor waits
				elif u_wall[u] > 0 and cls != UT.CLS_MISSILE:
					pass  # on the wall: it holds its stretch
				elif cls == UT.CLS_MISSILE and u_ammo[u] > 0:
					# Shoot it: close to most of the range, then stand. On
					# hilly ground the range is the height-adjusted one, and a
					# flat thrower with a crest in the way keeps closing.
					if d > 0:
						want_face = FM.atan2_a(dy, dx)
					var stop := mrange(u) * 17 / 20
					if ton or mon:
						stop = range_vs(u, t) * 17 / 20
						if not lof_units(u, t):
							stop = mrange(u) / 4
						if d > stop and ton:
							aspeed = aspeed * _fac_dir(u, g0, dx, dy, d) / 1000
					if u_wall[u] > 0:
						stop = d  # on the wall: shoot from here or not at all
					elif d > stop and oon and city_on != 0 \
							and unreach_goal(u, t, Vector2i(u_cx[t], u_cy[t])).z != 0:
						stop = d  # in range of a target out of reach: no closer (a wall between)
					if d > stop:
						want = true
						var mv := mini(aspeed, d - stop)
						var ss := _anchor_step(u, u_ax[u], u_ay[u], u_ax[u] + dx * mv / d, u_ay[u] + dy * mv / d,
							t, aspeed)
						u_ax[u] = ss.x
						u_ay[u] = ss.y
				elif d > 0 and (u_state[t] == U_ROUTING or t_chase[ty] != 0 or (u_inreach[u] == 0 and (u_fighting[u] == 0 \
						or ((u_ax[u] - u_cx[u]) * dx + (u_ay[u] - u_cy[u]) * dy) / d <= unit_depth(u) / 2 + ANCHOR_LEAD))):
					# Closing until a man is within reach of his (its men
					# walk at most PLACE_LEAD ahead of their places), but not
					# away from its men while they fight (their men out of
					# reach, it waits for them); after a routing target it
					# goes on, at the run: pursuit is the unit's move, not
					# its men's.
					want_face = FM.atan2_a(dy, dx)
					if u_state[t] == U_ROUTING and u_run[u] == 0 and not (sg_on != 0 and u_carry[u] >= 0):
						aspeed = aspeed * t_run[ty] / maxi(t_walk[ty], 1)
					var hw := (u_maxx[t] - u_minx[t]) >> 1
					var hh := (u_maxy[t] - u_miny[t]) >> 1
					var ext := (absi(dx) * hw + absi(dy) * hh) / d
					var stop := ext + M
					if t_chase[ty] != 0:
						stop = M  # a pack: into the middle of its quarry (scattered routers too)
					if oon:
						# Among buildings a unit stopping short of a deep column
						# may have a corner between its men and the enemy's:
						# press right up to it.
						stop = mini(stop, 4 * M)
					if ton and d > stop:
						aspeed = aspeed * _fac_dir(u, g0, dx, dy, d) / 1000
					if d > stop:
						want = true
						var mv := mini(aspeed, d - stop)
						var ms2 := _anchor_step(u, u_ax[u], u_ay[u], u_ax[u] + dx * mv / d, u_ay[u] + dy * mv / d,
							t, aspeed)
						u_ax[u] = ms2.x
						u_ay[u] = ms2.y
				u_dface[u] = want_face
		_turn(u, want_face)
		if oon and u_flow[u] != 0 and tick - u_flt[u] >= FLOW_EVERY and (order != O_NONE or u_contact[u] != 0 or u_face[u] != u_dface[u]):
			u_dirty[u] = 1  # flowed and on the go: laid out again (the cut may have changed)
		elif oon and u_flow[u] == 0 and _u_obs[u] != 0 and (tick + u) % FLOW_EVERY == 0 \
				and (u_blk[u] == BLK_QUEUE or (u_sq[u] > 0 and u_fighting[u] > 0)):
			u_dirty[u] = 1  # queuing behind friends, or fighting squeezed in a corridor: it packs (_flow_slots)
		if oon and _u_obs[u] != 0 and u_wall[u] == 0 and not art and (u + tick) % 3 == 0:
			_squeeze(u)
		elif u_sq[u] != 0 and (not oon or _u_obs[u] == 0):
			u_sq[u] = 0  # out of the streets: open out again
			u_dirty[u] = 1
		u_ax[u] = clampi(u_ax[u], 0, field_w)
		u_ay[u] = clampi(u_ay[u], 0, field_h)
		var mdx := u_ax[u] - ax0
		var mdy := u_ay[u] - ay0
		var moved := FM.approx_len(mdx, mdy)
		u_moved[u] = moved
		if oon:
			if want or u_stair[u] != 0 or u_stuck[u] != 0:
				_stuck_tick(u, want)
			else:
				u_srx[u] = u_cx[u]  # (nothing to get on with: the counter rests)
				u_sry[u] = u_cy[u]
		if u_dirty[u] != 0:
			_compute_offsets(u)
			u_settled[u] = 0
		if order != O_NONE or u_face[u] != u_dface[u]:
			u_settled[u] = 0

		# Formation state.
		if art:
			_refill_state(u, order, moved)
			if u_rprog[u] == 0:
				_deploy_state(u, order, moved)
		elif u_refill[u] != 0 or u_rprog[u] > 0:
			_refill_state(u, order, moved)  # (missile troops at a wagon)
		var dis := maxi(u_disorder[u] - 2, 0)
		if cls == UT.CLS_PIKE and u_run[u] != 0 and moved > 0:
			dis = maxi(dis, DISORDER_RUN)
		var s_face := 0
		if ton:
			# Ground under the formation: steepness, the grade along its
			# facing, and the speed factor its men fight and close at.
			_u_steep[u] = 1 if FM.approx_len(g0.x, g0.y) >= TER_STEEP else 0
			s_face = (g0.x * FM.cos_a(u_face[u]) + g0.y * FM.sin_a(u_face[u])) / FM.TRIG_ONE
			_u_fac[u] = _fac_for(u, s_face)
			# Moving across steep ground loosens a formation a little.
			if moved > 0 and _u_steep[u] != 0 and dis < STEEP_DIS_CAP and cls != UT.CLS_CAV \
					and not art:
				dis = mini(dis + STEEP_DIS_GAIN, STEEP_DIS_CAP)
				stat_steep_dis += 1
		if vd > 0 and cls != UT.CLS_CAV and not art:
			# Woods break up a formation as it moves through them; pikes
			# cannot stand formed in medium or dense woods.
			if moved > 0 and dis < VEG_DIS_CAP[vd]:
				dis = mini(dis + VEG_DIS_GAIN[vd], VEG_DIS_CAP[vd])
				stat_veg_dis += 1
			if cls == UT.CLS_PIKE:
				dis = maxi(dis, VEG_PIKE_FLOOR[vd])
		u_disorder[u] = dis
		var steady := dis < DISORDERED and u_morale[u] >= WAVER
		if cls == UT.CLS_PIKE:
			var turning := absi(FM.angle_diff(u_face[u], u_dface[u])) > TURN_DISORDER
			u_formed[u] = 1 if steady and not turning and u_alive[u] >= 2 * mini(files_of(u), u_alive[u]) else 0
		else:
			u_formed[u] = 0
		# Braced: spears standing still in formation; pikes whenever formed.
		var braced := 0
		if t_brace[ty] > 0 and steady:
			if cls == UT.CLS_PIKE:
				braced = u_formed[u]
			elif moved == 0 and order != O_MOVE and order != O_WITHDRAW:
				braced = 1
		u_braced[u] = braced
		if t_rider[ty] != 0:
			# Momentum builds only while charging a target at speed: a run
			# away from a melee (pulling out) does not count as a run-up.
			# (Cavalry, and mounted missile troops with a charge.)
			if u_run[u] != 0 and moved * 10 >= aspeed * 6 and order == O_ATTACK and u_charge[u] == 0:
				var gain := t_acc[ty]  # (MOM_GAIN for horses; beasts get going slower)
				var cap := 100
				if ton:
					# Uphill a charge cannot build full momentum; a good
					# downhill run builds it faster.
					if s_face > 0:
						cap = maxi(100 - s_face * MOM_UP_K / FM.TRIG_ONE, CHARGE_MIN)
					elif s_face <= -MOM_DOWN:
						gain += 1
				if mon:
					cap = mini(cap, VEG_MOM_CAP[vd])
					if urban:
						cap = mini(cap, URBAN_MOM_CAP)
				u_mom[u] = mini(u_mom[u] + gain, cap)
			else:
				u_mom[u] = maxi(u_mom[u] - MOM_LOSS, 0)
			_charge_state(u)
			if t_m_ammo[ty] > 0 and (u + tick) % FIRE_THINK == 0:
				_missile_think(u)  # (an elephant's crew shoots from its back; light horse)
		elif cls == UT.CLS_MISSILE:
			if (u + tick) % FIRE_THINK == 0:
				_missile_think(u)
		elif art:
			if (u + tick) % FIRE_THINK == 0:
				_art_think(u)
		_unit_stats(u)


## Unit u's no-progress counter (maps with buildings or walls): while it
## wants to get on (a move or an attack still closing, a stair or ladder
## move, its men short of their places) and is not fighting at its full
## frontage (half its front rank within reach) nor waiting by rule in a
## queue behind friends, u_stuck counts the ticks its men's middle stays
## within STUCK_DIST of where it last got on; otherwise it is 0. Read by
## the stuck release; stat_stuck_* for the probes.
func _stuck_tick(u: int, want: bool) -> void:
	var st := u_stair[u]
	if st == 1 or st == 3 or st == ST_LADDER:
		want = true
	if want and (u_blk[u] == BLK_QUEUE or u_charge[u] != 0 \
			or u_inreach[u] * 2 >= mini(files_of(u), u_alive[u])):
		want = false
	if not want or FM.approx_len(u_cx[u] - u_srx[u], u_cy[u] - u_sry[u]) > STUCK_DIST:
		u_stuck[u] = 0
		u_srx[u] = u_cx[u]
		u_sry[u] = u_cy[u]
		return
	var k := u_stuck[u] + 1
	u_stuck[u] = k
	stat_stuck_t[u] += 1
	if k > stat_stuck_u[u]:
		stat_stuck_u[u] = k
		if k > stat_stuck_max:
			stat_stuck_max = k
	_stuck_release(u, k)


## Stuck release (docs/DESIGN.md "Units flow into the space"): unit u has
## got nowhere for k ticks (u_stuck). Each STUCK_CYCLE ticks of it: at
## STUCK_FLOW its places are laid out afresh (they flow round what cuts
## them); at STUCK_ROUTE its way is planned again (a move this near its
## destination, or to ground it can no longer reach, is over instead: it
## stands where it got to); at the cycle's
## end its anchor comes back to its men (_regroup: the man nearest their
## middle, on open ground) and it plans its way from there, its places
## flowing round him. Nothing is moved but the anchor and the places: no man
## steps through a wall or an enemy. Not on a wall, a stair or its ladders
## (those moves end by their own rules; a march to a stair's or a ladder's
## foot is a ground move and is released) nor a routing unit (it does not
## count).
func _stuck_release(u: int, k: int) -> void:
	var st := u_stair[u]
	if u_wall[u] > 0 or st == 1 or st == 3 or st == ST_LADDER:
		return
	var c := k % STUCK_CYCLE
	if c == STUCK_FLOW:
		u_flt[u] = -FLOW_EVERY
		u_dirty[u] = 1
		u_settled[u] = 0
		stat_unstick[0] += 1
	elif c == STUCK_ROUTE:
		if u_order[u] == O_MOVE and st == 0 and (FM.approx_len(u_dx[u] - u_ax[u], u_dy[u] - u_ay[u]) <= STUCK_NEAR \
				or (city_on != 0 and reach_at(u_dx[u], u_dy[u]) != reach_at(u_ax[u], u_ay[u]))):
			# (Or it cannot get there any more: a gate shut since, its goal on
			# another piece of ground; it went straight at it into a house.)
			u_order[u] = O_NONE
			stat_unstick[1] += 1
		else:
			u_pn[u] = 0
			stat_unstick[2] += 1
		u_flt[u] = -FLOW_EVERY
		u_dirty[u] = 1
		u_settled[u] = 0
	elif c == 0:
		_regroup(u, FM.approx_len(u_cx[u] - u_ax[u], u_cy[u] - u_ay[u]) - unit_depth(u) / 2 > LAG_HOLD)
		u_flt[u] = -FLOW_EVERY
		stat_unstick[3] += 1


## Cavalry charge state. A running cavalry unit with momentum that comes
## into contact charges: from then on each rider resolves the charge himself
## (see _update_soldiers) while the anchor waits. The charge ends when every
## front-rank rider has made contact, no rider is still riding in, the time
## runs out or another order is given; the formation then re-forms where the
## riders are.
func _charge_state(u: int) -> void:
	if u_charge[u] != 0:
		var over := u_order[u] != O_ATTACK or tick - u_charge_t[u] > CHARGE_TICKS \
			or (tick > u_charge_t[u] + 1 and (u_charge_left[u] == 0 or u_charge_act[u] == 0))
		if over:
			u_charge[u] = 0
			var depth := unit_depth(u)
			u_ax[u] = clampi(u_cx[u] + (FM.cos_a(u_face[u]) * depth / 2 / FM.TRIG_ONE), 0, field_w)
			u_ay[u] = clampi(u_cy[u] + (FM.sin_a(u_face[u]) * depth / 2 / FM.TRIG_ONE), 0, field_h)
			u_dface[u] = u_face[u]
			u_dirty[u] = 1
			_compute_offsets(u)
		return
	if u_order[u] == O_ATTACK and u_mom[u] >= CHARGE_MIN and u_contact[u] != 0:
		u_charge[u] = 1
		u_charge_t[u] = tick
		u_charge_left[u] = 1
		u_charge_act[u] = 1
		var base := u_slot_base[u]
		for s in u_alive[u]:
			struck[slot_soldier[base + s]] = 0


## Refill counter: settling in while the battery stands with a refill order,
## backing out (twice as fast) once the order is gone; broken off at once
## when the battery is caught in melee.
func _refill_state(u: int, order: int, moved: int) -> void:
	var r := u_rprog[u]
	if u_cls[u] != UT.CLS_ART and u_refill[u] != 0 and (order != O_NONE or moved > 0):
		u_refill[u] = 0  # missile troops moved off (skirmishing): the refill is given up
	if u_fighting[u] > 0 and (r > 0 or u_refill[u] != 0):
		stat_refill_broken += 1
		u_refill[u] = 0
		u_rprog[u] = 0
		return
	if u_refill[u] != 0:
		if r < REFILL_FULL and moved == 0 and u_emove[u] == 0 and order == O_NONE:
			r += 1
			if r == REFILL_FULL:
				stat_refills += 1
	elif r > 0:
		r = maxi(r - 2, 0)
	if r != u_rprog[u]:
		u_settled[u] = 0
	u_rprog[u] = r


## Artillery set-up counter: packing up while the battery has to move (or is
## told to pack), setting up while it stands still and wants to shoot.
func _deploy_state(u: int, order: int, moved: int) -> void:
	var full := t_deploy[u_type[u]]
	var d := u_depl[u]
	if order == O_MOVE or order == O_WITHDRAW or u_deploy[u] == 0:
		if d > 0:
			d = maxi(d - 2, 0)
			u_settled[u] = 0
			if d == 0:
				stat_packs += 1
	elif moved == 0 and u_emove[u] == 0 and d < full and (veg_on == 0 or veg_d(u_ax[u], u_ay[u]) < 3):
		d += 1
		u_settled[u] = 0
		if d == full:
			stat_deploys += 1
	u_depl[u] = d


## Effective melee stats of unit u this tick (pikes switch weapons).
func _unit_stats(u: int) -> void:
	var ty := u_otype[u]  # (the men's own weapons, also while they work engines)
	if t_cls[ty] == UT.CLS_PIKE and u_formed[u] == 0:
		u_att[u] = t_sec_att[ty]
		u_def[u] = t_sec_def[ty]
		u_dmg[u] = t_sec_dmg[ty]
		u_reach[u] = t_sec_reach[ty]
	else:
		u_att[u] = t_attack[ty]
		u_def[u] = t_defence[ty]
		u_dmg[u] = t_damage[ty]
		u_reach[u] = t_reach[ty]
	if sg_on != 0 and u_carry[u] >= 0:
		# Carrying siege equipment: it defends itself poorly.
		u_att[u] = u_att[u] * CARRY_MELEE_PCT / 100
		u_def[u] = u_def[u] * CARRY_MELEE_PCT / 100


func _update_units_stats() -> void:
	for u in n_units:
		_unit_stats(u)


## Missile unit behaviour, every FIRE_THINK ticks: skirmish away from close
## melee troops, and choose what to shoot.
func _missile_think(u: int) -> void:
	if sg_on != 0 and u_carry[u] >= 0:
		u_ftarget[u] = -1  # carrying siege equipment: no shooting, no skirmishing
		return
	var ty := u_type[u]
	var order := u_order[u]
	# Skirmish mode: fall back from approaching infantry or cavalry.
	if u_skirm[u] != 0 and order != O_WITHDRAW and u_fighting[u] * 4 < u_alive[u]:
		var threat := -1
		var best := 0
		for o in n_units:
			if u_side[o] == u_side[u] or u_state[o] != U_READY or u_cls[o] == UT.CLS_MISSILE:
				continue
			var dx := u_cx[o] - u_cx[u]
			var dy := u_cy[o] - u_cy[u]
			var lim := SKIRM_CAV if u_cls[o] == UT.CLS_CAV else SKIRM_INF
			var d := FM.approx_len(dx, dy)
			if d < lim and (threat < 0 or d < best):
				threat = o
				best = d
		if threat >= 0:
			var ex := u_cx[u] - u_cx[threat]
			var ey := u_cy[u] - u_cy[threat]
			var d := maxi(FM.approx_len(ex, ey), 1)
			var tx := clampi(u_ax[u] + ex * SKIRM_BACK / d, 5 * M, field_w - 5 * M)
			var ty2 := clampi(u_ay[u] + ey * SKIRM_BACK / d, 5 * M, field_h - 5 * M)
			if FM.approx_len(tx - u_ax[u], ty2 - u_ay[u]) > 4 * M:
				u_order[u] = O_MOVE
				u_target[u] = -1
				u_dx[u] = tx
				u_dy[u] = ty2
				u_dface[u] = FM.atan2_a(-ey, -ex)
				u_run[u] = 1
				u_settled[u] = 0
				u_ftarget[u] = -1
				return
	if u_refill[u] != 0 or u_rprog[u] > 0 or u_forage[u] != 0:
		u_ftarget[u] = -1  # refilling at a wagon or foraging: no shooting
		return
	# Fire target.
	var ft := -1
	var gt := u_gtarget[u]
	if gt >= 0 and order == O_NONE:
		# Told to shoot at a gate: while it stands shut and in range
		# (_gate_volleys), nothing else.
		if gt >= n_gates or g_state[gt] != GATE_CLOSED:
			u_gtarget[u] = -1
		elif _gate_shot_ok(u, gt):
			u_ftarget[u] = -1
			return
	if u_ammo[u] > 0 and order != O_MOVE and order != O_WITHDRAW:
		var rng := mrange(u)
		if order == O_ATTACK:
			var t := u_target[u]
			if t >= 0 and u_state[t] < U_DESTROYED and _in_range(u, t, rng):
				ft = t
		elif u_fire[u] != 0:
			# Fire at will: keep shooting the current target while it stays in
			# range (busy archers do not swing round to every new threat),
			# otherwise the nearest enemy in range, preferring units that are
			# not locked in melee with our own side.
			var cur := u_ftarget[u]
			if cur >= 0 and u_state[cur] < U_DESTROYED and u_side[cur] != u_side[u] \
					and _in_range(u, cur, rng) and (u_fighting[cur] == 0 or not _any_clean_target(u, rng)):
				u_ftarget[u] = cur if t_m_arc[ty] != 0 or (_clear_line(u, cur) and lof_units(u, cur)) else -1
				return
			var best := 0
			var best_engaged := true
			var flat_lof := (ter_on != 0 or map_on != 0) and t_m_arc[ty] == 0
			var hgt := ter_on != 0 or obs_on != 0 or fwh_on != 0
			for o in n_units:
				if u_side[o] == u_side[u] or u_state[o] >= U_DESTROYED:
					continue
				var d := _unit_dist(u, o)
				if d > rng and (not hgt or d > range_vs(u, o)):
					continue
				var engaged := u_fighting[o] > 0
				if ft < 0 or (best_engaged and not engaged) or (engaged == best_engaged and d < best):
					# Thrown flat: skip enemies behind a crest.
					if flat_lof and not lof_units(u, o):
						continue
					ft = o
					best = d
					best_engaged = engaged
		if ft >= 0 and t_m_arc[ty] == 0 and not _clear_line(u, ft):
			ft = -1
		if ft >= 0 and not lof_units(u, ft):
			stat_lof_blocked += 1
			ft = -1
	u_ftarget[u] = ft


## Unit t within missile unit u's range (`rng` on a flat map; on hilly
## ground the height-adjusted range).
func _in_range(u: int, t: int, rng: int) -> bool:
	var d := _unit_dist(u, t)
	if ter_on == 0 and obs_on == 0 and fwh_on == 0:
		return d <= rng
	return d <= range_vs(u, t)


## An enemy in range that is not locked in melee.
func _any_clean_target(u: int, rng: int) -> bool:
	for o in n_units:
		if u_side[o] != u_side[u] and u_state[o] < U_DESTROYED and u_fighting[o] == 0 \
				and _in_range(u, o, rng):
			return true
	return false


## Distance between unit centroids less the target's half extent (cheap).
func _unit_dist(u: int, t: int) -> int:
	var dx := u_cx[t] - u_cx[u]
	var dy := u_cy[t] - u_cy[u]
	var ext := mini(u_maxx[t] - u_minx[t], u_maxy[t] - u_miny[t]) >> 1
	return maxi(FM.approx_len(dx, dy) - ext, 0)


## True when no other friendly unit stands between u and t (flat throws).
func _clear_line(u: int, t: int) -> bool:
	var x0 := u_cx[u]
	var y0 := u_cy[u]
	var x1 := u_cx[t]
	var y1 := u_cy[t]
	var side := u_side[u]
	for o in n_units:
		if o == u or u_side[o] != side or u_state[o] >= U_DESTROYED:
			continue
		var minx := u_minx[o]
		var maxx := u_maxx[o]
		var miny := u_miny[o]
		var maxy := u_maxy[o]
		if maxi(x0, x1) < minx or mini(x0, x1) > maxx or maxi(y0, y1) < miny or mini(y0, y1) > maxy:
			continue
		for k in range(1, 8):
			var px := x0 + (x1 - x0) * k / 8
			var py := y0 + (y1 - y0) * k / 8
			if px >= minx and px <= maxx and py >= miny and py <= maxy:
				return false
	return true


func _update_contacts() -> void:
	for u in n_units:
		u_contact[u] = 0
		u_nwalls[u] = 0
	for a in n_units:
		if u_state[a] >= U_DESTROYED:
			continue
		var sa := u_side[a]
		var ax0 := u_minx[a] - CONTACT_MARGIN
		var ax1 := u_maxx[a] + CONTACT_MARGIN
		var ay0 := u_miny[a] - CONTACT_MARGIN
		var ay1 := u_maxy[a] + CONTACT_MARGIN
		for b in range(a + 1, n_units):
			if u_side[b] == sa or u_state[b] >= U_DESTROYED:
				continue
			if u_maxx[b] < ax0 or u_minx[b] > ax1 or u_maxy[b] < ay0 or u_miny[b] > ay1:
				continue
			# Two routing units do not need the grid for each other.
			if u_state[a] == U_ROUTING and u_state[b] == U_ROUTING:
				continue
			u_contact[a] = 1
			u_contact[b] = 1
			# Pike walls hold back enemies close to them.
			if u_formed[b] != 0 and u_nwalls[a] < 4:
				u_walls[a * 4 + u_nwalls[a]] = b
				u_nwalls[a] += 1
			if u_formed[a] != 0 and u_nwalls[b] < 4:
				u_walls[b * 4 + u_nwalls[b]] = a
				u_nwalls[b] += 1
	for u in n_units:
		if u_contact[u] != 0:
			u_settled[u] = 0


func _build_grid() -> void:
	grid_head0.fill(-1)
	grid_head1.fill(-1)
	var gs := GRID_SHIFT
	var gw := grid_w
	var gmax := grid_w * grid_h - 1
	var cnt := 0
	var blk := obs_on != 0
	if blk:
		blk_n0.fill(0)
		blk_n1.fill(0)
	var bmax := blk_n0.size() - 1
	for u in n_units:
		if u_contact[u] == 0:
			continue
		var head: PackedInt32Array = grid_head0 if u_side[u] == 0 else grid_head1
		var bn: PackedInt32Array = blk_n0 if u_side[u] == 0 else blk_n1
		var base := u_slot_base[u]
		for s in u_alive[u]:
			var i := slot_soldier[base + s]
			var c := clampi((pos_y[i] >> gs) * gw + (pos_x[i] >> gs), 0, gmax)
			grid_next[i] = head[c]
			head[c] = i
			cnt += 1
			if blk:
				bn[clampi((pos_y[i] >> 14) * blk_w + (pos_x[i] >> 14), 0, bmax)] += 1
	stat_grid_soldiers = cnt


## Settlement maps: no enemy man (of the unit being moved: _enemy_bn) in
## the 16 m blocks covering the square of half side r round (x, y), so a
## search there finds nobody (scratch counts from _build_grid).
func _none_near(x: int, y: int, r: int) -> bool:
	var bn := _enemy_bn
	var bh := bn.size() / blk_w
	for by in range(maxi((y - r) >> 14, 0), mini((y + r) >> 14, bh - 1) + 1):
		for bx in range(maxi((x - r) >> 14, 0), mini((x + r) >> 14, blk_w - 1) + 1):
			if bn[by * blk_w + bx] != 0:
				return false
	return true


func _update_soldiers() -> void:
	# Hot loop. Iterates unit by unit, slot by slot (a fixed order), with all
	# per-unit values hoisted into typed locals. Settled units are skipped
	# outright; units not near an enemy take a tight slot-following path.
	var px := pos_x
	var py := pos_y
	var fc := facing
	var st := state
	var ss := slot_soldier
	var oxs := off_x
	var oys := off_y
	var fw := field_w
	var fh := field_h
	var tone := FM.TRIG_ONE  # fixed-point divisor: truncation is symmetric under mirroring (>> floors)
	# Forward or reverse unit order, chosen by the sim's RNG each tick, so
	# neither side gains from acting first. (Alternating by tick parity was
	# not enough: mirrored armies meet on a tick whose parity is set by the
	# geometry, so the same side always went first in the clash.)
	var nu := n_units
	var flip := (_rand() & 1) != 0
	for k_u in nu:
		var u := nu - 1 - k_u if flip else k_u
		var alive := u_alive[u]
		if alive <= 0 or u_settled[u] != 0:
			continue
		var base := u_slot_base[u]
		var ty := u_type[u]
		var walk := t_walk[ty]
		var run := t_run[ty]
		var face := u_face[u]
		var n_rm := 0
		# Settlement maps: men of a unit near an obstacle are kept out of
		# blocked cells (walls, buildings, closed gates; the walkway is only
		# for wall units and they never leave it).
		var ob := obs_on != 0 and _u_obs[u] != 0
		var navg := nav
		var obw := ob_w
		var obw1 := ob_w - 1
		var obh1 := ob_h - 1
		var mask := _mask_of(u) if obs_on != 0 else MapGen.NAV_GROUND
		if u_state[u] == U_ROUTING:
			var rs := (run * 7) >> 3
			var flx := u_flee_x[u]
			var fly := u_flee_y[u]
			if ter_on != 0:
				rs = rs * _slope_fac(u, u_cx[u], u_cy[u], flx, fly) / 1000
			if map_on != 0:
				rs = rs * VEG_SPEED[u_cls[u]][veg_d(u_cx[u], u_cy[u])] / 1000
			var rminx := fw
			var rmaxx := 0
			var rminy := fh
			var rmaxy := 0
			var rsx := 0
			var rsy := 0
			for s in alive:
				var i := ss[base + s]
				var jitter := ((i * 37) & 15) - 7  # per-soldier spread
				var fx := flx - fly * jitter / 24
				var fy := fly + flx * jitter / 24
				var x := clampi(px[i] + ((fx * rs) / tone), 0, fw)
				var y := clampi(py[i] + ((fy * rs) / tone), 0, fh)
				if ob and (navg[mini(y >> 11, obh1) * obw + mini(x >> 11, obw1)] & mask) == 0:
					var sl := _slide(u, px[i], py[i], x, y, mask)
					x = sl.x
					y = sl.y
				px[i] = x
				py[i] = y
				fc[i] = FM.atan2_a(fy, fx)
				if st[i] == S_DOWN:
					st[i] = S_ROUTING
				rsx += x
				rsy += y
				rminx = mini(rminx, x)
				rmaxx = maxi(rmaxx, x)
				rminy = mini(rminy, y)
				rmaxy = maxi(rmaxy, y)
				if x < EDGE_EXIT or y < EDGE_EXIT or x > fw - EDGE_EXIT or y > fh - EDGE_EXIT:
					_rm[n_rm] = i
					_rm_why[n_rm] = GONE_ROUTED
					n_rm += 1
			_set_bounds(u, rsx / alive, rsy / alive, rminx, rminy, rmaxx, rmaxy)
			_flush_removals(n_rm)
			if u_amok[u] != 0 and u_alive[u] > 0:
				_amok_trample(u)
			continue

		var ax := u_ax[u]
		var ay := u_ay[u]
		var spd_formed := run if u_run[u] != 0 else walk
		var moved := 0
		var withdrawing := u_order[u] == O_WITHDRAW
		var exit_y := fh - EDGE_EXIT if u_side[u] == 0 else EDGE_EXIT
		# Coast: the defenders withdraw along the shore and leave by a side.
		var side_exit := withdrawing and sea_on != 0 and u_side[u] == city_def
		var is_cav := t_rider[u_type[u]] != 0
		var umom := u_mom[u]
		var cg := chg

		var minx := fw
		var maxx := 0
		var miny := fh
		var maxy := 0
		var sumx := 0
		var sumy := 0
		# On a stair move, a man still on the level his unit is leaving (the
		# walkway or a tower going down, the ground going up) walks its trail
		# (junction, walkway point, stair, foot or back), not straight at his
		# new place (under or over the wall).
		var stair_mv := 0
		if ob:
			stair_mv = u_stair[u] if u_stair[u] == 1 or u_stair[u] == 3 or u_stair[u] == ST_LADDER else 0
		if u_contact[u] == 0 and u_down[u] == 0 and u_charge[u] == 0:
			# Fast path: slot following only (no separation, no search).
			for s in alive:
				var k := base + s
				var i := ss[k]
				var x := px[i]
				var y := py[i]
				var dx := ax + oxs[k] - x
				var dy := ay + oys[k] - y
				if stair_mv != 0:
					var sgo := _stair_leave(u, x, y, stair_mv, s)
					if sgo.z != 0:
						dx = sgo.x - x
						dy = sgo.y - y
				fc[i] = face
				if is_cav:
					cg[i] = umom
				if dx == 0 and dy == 0:
					if st[i] != S_FORMED:
						st[i] = S_FORMED
					sumx += x
					sumy += y
					if x < minx: minx = x
					if x > maxx: maxx = x
					if y < miny: miny = y
					if y > maxy: maxy = y
					continue
				moved += 1
				st[i] = S_FORMED
				# Inline approx_len (alpha max plus beta min).
				var adx := dx if dx >= 0 else -dx
				var ady := dy if dy >= 0 else -dy
				var d: int
				if adx > ady:
					d = adx - (adx >> 5) + ((ady * 3) >> 3) + (ady >> 6)
				else:
					d = ady - (ady >> 5) + ((adx * 3) >> 3) + (adx >> 6)
				var spd := spd_formed if d <= CATCH_UP_DIST else run
				if d <= spd:
					x = clampi(x + dx, 0, fw)
					y = clampi(y + dy, 0, fh)
				else:
					x = clampi(x + dx * spd / d, 0, fw)
					y = clampi(y + dy * spd / d, 0, fh)
				var mm := mask if stair_mv == 0 else _stair_mask(u, px[i], py[i], mask, stair_mv)
				if ob and (navg[mini(y >> 11, obh1) * obw + mini(x >> 11, obw1)] & mm) == 0:
					var sl2 := _slide(u, px[i], py[i], x, y, mm)
					x = sl2.x
					y = sl2.y
				px[i] = x
				py[i] = y
				sumx += x
				sumy += y
				if x < minx: minx = x
				if x > maxx: maxx = x
				if y < miny: miny = y
				if y > maxy: maxy = y
				if withdrawing and ((y > exit_y if exit_y > EDGE_EXIT else y < exit_y) \
						or (side_exit and (x < 8 * M or x > fw - 8 * M))):
					_rm[n_rm] = i
					_rm_why[n_rm] = GONE_WITHDRAWN
					n_rm += 1
			_set_bounds(u, sumx / alive, sumy / alive, minx, miny, maxx, maxy)
			u_fighting[u] = 0
			u_inreach[u] = 0
			if moved == 0 and u_order[u] == O_NONE and u_dirty[u] == 0 and u_face[u] == u_dface[u]:
				u_settled[u] = 1
			_flush_removals(n_rm)
			continue

		# Contact path: target search, melee, separation, slot following.
		if ter_on != 0:
			# Men close, charge and keep up at the pace the ground allows
			# along the unit's facing.
			var fac := _u_fac[u]
			walk = walk * fac / 1000
			run = run * fac / 1000
			spd_formed = spd_formed * fac / 1000
		if map_on != 0 and _u_vfac[u] < 1000:
			# ... and the woods allow.
			var vfac := _u_vfac[u]
			walk = walk * vfac / 1000
			run = run * vfac / 1000
			spd_formed = spd_formed * vfac / 1000
		var tg := target
		var cd := cooldown
		var gnext := grid_next
		var gs := GRID_SHIFT
		var gw := grid_w
		var gmax := grid_w * grid_h - 1
		var tk := tick
		var files := maxi(mini(files_of(u), alive), 1)
		var reach := u_reach[u]
		var want := (reach * 3) >> 2
		var half_reach := reach >> 1
		var cool := t_cooldown[u_otype[u]]
		var side := u_side[u]
		var enemy_head: PackedInt32Array = grid_head1 if side == 0 else grid_head0
		_enemy_bn = blk_n1 if side == 0 else blk_n0
		var own_head: PackedInt32Array = grid_head0 if side == 0 else grid_head1
		var keep_front := (SEARCH_FRONT + TARGET_KEEP_EXTRA) * (SEARCH_FRONT + TARGET_KEEP_EXTRA)
		# Missile troops with ammunition, and gun crews, only defend
		# themselves at close range.
		var shy := (u_cls[u] == UT.CLS_MISSILE and u_ammo[u] > 0) or u_cls[u] == UT.CLS_ART
		var rear_r := SEARCH_REAR
		if u_fighting[u] > 0 and not shy and tick - u_charged_t[u] < ENGAGED_AFTER_CHARGE:
			rear_r = SEARCH_ENGAGED
		var keep_rear := (rear_r + TARGET_KEEP_EXTRA) * (rear_r + TARGET_KEEP_EXTRA)
		# (A move stopped by an enemy in the way fights where it stands.)
		var disengage := (u_order[u] == O_MOVE and u_blk[u] != BLK_ENEMY) or withdrawing
		# Formed pikes strike from their slots with ranks 1..ranks_reach.
		var pike_formed := u_formed[u] != 0
		var pike_ranks := t_ranks[ty] * files
		var fcos := FM.cos_a(face)
		var fsin := FM.sin_a(face)
		var sep := CAV_SEPARATION if is_cav else SEPARATION
		var bigb := big_on != 0
		if bigb and t_body_r[ty] > 0:
			sep = 2 * t_body_r[ty]  # beasts keep their bodies apart
		var charging := u_charge[u] != 0
		# Wrap: front-rank soldiers of an engaged attacking unit who have no
		# enemy in reach close on the target unit instead of holding their
		# slot, so a wide unit laps round a narrow face (a flank) rather than
		# leaving most of its men idle.
		var wrap_t := -1
		if u_order[u] == O_ATTACK and u_fighting[u] > 0 and not pike_formed and not shy and not charging:
			wrap_t = u_target[u]
		# Wrap at the anchor level (2026-10-09): when the target is narrower
		# than this unit, the places of its front-rank files out beyond the
		# target's flank curl forward round it (as far as they stand out, at
		# most the target's depth), so those men's lead and side caps keep
		# them along its flank instead of idle beyond it (_curl). Computed
		# from the target's bounding box each tick: no state.
		var wr_tl := 0
		var wr_lim := 0
		var wr_dep := 0
		if wrap_t >= 0:
			var whx := (u_maxx[wrap_t] - u_minx[wrap_t]) >> 1
			var why := (u_maxy[wrap_t] - u_miny[wrap_t]) >> 1
			var wcx := (u_maxx[wrap_t] + u_minx[wrap_t]) >> 1
			var wcy := (u_maxy[wrap_t] + u_miny[wrap_t]) >> 1
			wr_tl = ((wcy - ay) * fcos - (wcx - ax) * fsin) / FM.TRIG_ONE
			wr_lim = (absi(fsin) * whx + absi(fcos) * why) / FM.TRIG_ONE + WRAP_GAP
			wr_dep = 2 * ((absi(fcos) * whx + absi(fsin) * why) / FM.TRIG_ONE) + WRAP_GAP
		var sk := struck
		var ch_left := 0
		var ch_act := 0
		var nwalls := u_nwalls[u]
		var wp := _wall_params
		for w in nwalls:
			var p := u_walls[u * 4 + w]
			wp[w * 5] = FM.cos_a(u_face[p])
			wp[w * 5 + 1] = FM.sin_a(u_face[p])
			wp[w * 5 + 2] = u_ax[p]
			wp[w * 5 + 3] = u_ay[p]
			wp[w * 5 + 4] = unit_half_width(p) + PIKE_WALL_EXTRA
		var run_cap := run
		var fighting := 0
		var inreach := 0
		# Fighting men keep to within PLACE_LEAD ahead of their places (not
		# on a stair or ladder move, not on a wall: those follow their own
		# trails).
		var lead_cap := stair_mv == 0 and not (ob and u_wall[u] != 0)
		var reach_in := reach + INREACH_EXTRA
		var counted := 0
		# Slots can be reshuffled by deaths inside this loop (gap filling), so
		# walk a snapshot of the slot list.
		var order := ss.slice(base, base + alive)
		# Men with no target and no search due this tick (in a unit that is
		# not charging, not a formed pike block, not wrapping round its
		# target and not held off by pike walls) only follow their slot:
		# they take a short path with exactly the full one's result.
		var lean := not charging and not pike_formed
		for s in alive:
			var i := order[s]
			var sti := st[i]
			if sti >= S_DEAD:
				continue
			var x := px[i]
			var y := py[i]
			var nx := x
			var ny := y
			if sti == S_DOWN:
				# Knocked down: lie still until the timer runs out.
				var c0 := cd[i] - 1
				if c0 <= 0:
					st[i] = S_FORMED
					cd[i] = cool
					u_down[u] -= 1
				else:
					cd[i] = c0
				counted += 1
				sumx += x
				sumy += y
				if x < minx: minx = x
				if x > maxx: maxx = x
				if y < miny: miny = y
				if y > maxy: maxy = y
				continue
			var slot := slot_of[i]
			if lean and tg[i] < 0 and (tk + i) % (3 if slot < files or is_cav else 7) != 0 \
					and (wrap_t < 0 or slot >= files):
				var kl := base + slot
				var ldx := ax + oxs[kl] - x
				var ldy := ay + oys[kl] - y
				if stair_mv != 0:
					var sgl := _stair_leave(u, x, y, stair_mv, slot)
					if sgl.z != 0:
						ldx = sgl.x - x
						ldy = sgl.y - y
				if ldx != 0 or ldy != 0:
					var ld := FM.approx_len(ldx, ldy)
					var lspd := spd_formed if ld <= CATCH_UP_DIST else run
					if ld <= lspd:
						nx = x + ldx
						ny = y + ldy
					else:
						nx = x + ldx * lspd / ld
						ny = y + ldy * lspd / ld
				fc[i] = face
				if is_cav:
					cg[i] = maxi(umom, cg[i] - 10)
				st[i] = S_FORMED
				for w in nwalls:
					var lw5 := w * 5
					var lpc := wp[lw5]
					var lps := wp[lw5 + 1]
					var lrx := nx - wp[lw5 + 2]
					var lry := ny - wp[lw5 + 3]
					var lf := (lrx * lpc + lry * lps) / tone
					if lf >= PIKE_HOLD or lf <= -M:
						continue
					var llat := (lry * lpc - lrx * lps) / tone
					var lhw := wp[lw5 + 4]
					if llat > lhw or llat < -lhw:
						continue
					var lpush := PIKE_HOLD - lf
					nx += (lpc * lpush) / tone
					ny += (lps * lpush) / tone
				nx = clampi(nx, 0, fw)
				ny = clampi(ny, 0, fh)
				var mml := mask if stair_mv == 0 else _stair_mask(u, x, y, mask, stair_mv)
				if ob and (navg[mini(ny >> 11, obh1) * obw + mini(nx >> 11, obw1)] & mml) == 0:
					var sll := _slide(u, x, y, nx, ny, mml)
					nx = sll.x
					ny = sll.y
				px[i] = nx
				py[i] = ny
				counted += 1
				sumx += nx
				sumy += ny
				if nx < minx: minx = nx
				if nx > maxx: maxx = nx
				if ny < miny: miny = ny
				if ny > maxy: maxy = ny
				if withdrawing and ((ny > exit_y if exit_y > EDGE_EXIT else ny < exit_y) \
						or (side_exit and (nx < 8 * M or nx > fw - 8 * M))):
					_rm[n_rm] = i
					_rm_why[n_rm] = GONE_WITHDRAWN
					n_rm += 1
				continue
			var front := slot < files
			var t := tg[i]
			if disengage:
				# Turning away from a melee: the man he was fighting gets a
				# free blow at his back (once: the target is dropped now).
				if t >= 0 and st[t] == S_FIGHTING:
					var pdx := px[t] - x
					var pdy := py[t] - y
					var pr := u_reach[unit_of[t]] + IMPACT_RANGE
					if pdx * pdx + pdy * pdy <= pr * pr:
						_melee(t, i, 0, true)
						if st[i] >= S_DEAD:
							continue
				t = -1
			elif charging:
				# Charging rider: keep his man, else look ahead (forward cone)
				# for the nearest enemy to ride at.
				if t >= 0 and st[t] >= S_DEAD:
					t = -1
				if t < 0 and ((tk + i) & 1) == 0:
					t = _find_target_cone_obs(x, y, SEARCH_FRONT, fcos, fsin, enemy_head) if ob \
						else _find_target_cone(x, y, SEARCH_FRONT, fcos, fsin, enemy_head)
			elif pike_formed:
				if slot < pike_ranks:
					if t >= 0:
						if st[t] >= S_DEAD:
							t = -1
						else:
							var kx := px[t] - x
							var ky := py[t] - y
							if kx * kx + ky * ky > (reach + M) * (reach + M):
								t = -1
					if t < 0 and (tk + i) % 3 == 0:
						t = _find_target_cone_obs(x, y, reach, fcos, fsin, enemy_head) if ob \
							else _find_target_cone(x, y, reach, fcos, fsin, enemy_head)
				else:
					t = -1
			else:
				var lost := false
				if t >= 0:
					if st[t] >= S_DEAD:
						t = -1
						lost = true
					else:
						var ddx := px[t] - x
						var ddy := py[t] - y
						if ddx * ddx + ddy * ddy > (keep_front if front and not shy else keep_rear):
							t = -1
							lost = true
						elif ob and (((tk + i) & 1) == 0 or ddx * ddx + ddy * ddy <= reach_in * reach_in) \
								and not _reach_ok(x, y, px[t], py[t]):
							# Out of reach behind a wall (or a gate, a corner): look
							# again (every other tick: nobody stands fighting a wall;
							# every tick once he is within reach, so no blow goes
							# through it).
							t = -1
							lost = true
				if t < 0:
					# Every rider looks ahead, not just the front rank.
					var wide := front or is_cav
					# (Among buildings, half the men who just lost their man look
					# again at once and the rest at their next turn: a unit
					# breaking off or dying set off a burst of searches.)
					if (lost and (not ob or ((tk + i) & 1) == 0)) or (tk + i) % (3 if wide else 7) == 0:
						if wide and not shy:
							t = _find_target_obs(x, y, SEARCH_FRONT, 2, enemy_head) if ob \
								else _find_target(x, y, SEARCH_FRONT, 2, enemy_head)
						else:
							t = _find_target_obs(x, y, rear_r, 2, enemy_head) if ob \
								else _find_target(x, y, rear_r, 2, enemy_head)
			tg[i] = t

			if t >= 0 and not pike_formed:
				# Fighting: close to reach, face the target, swing on cooldown.
				fighting += 1
				st[i] = S_FIGHTING
				var dx := px[t] - x
				var dy := py[t] - y
				var dl := FM.approx_len(dx, dy)
				var d := dl
				if bigb:
					d = maxi(dl - t_body_r[u_type[unit_of[t]]], 0)  # a big body is reached at its edge
				var mom := 0
				if is_cav:
					mom = cg[i]
				if d <= reach_in:
					inreach += 1
				if d > want:
					# Walk in; charge at the run with momentum, and run after
					# fleeing enemies - but only as far as PLACE_LEAD ahead of
					# his place: further pursuit is the unit's (its anchor
					# follows a routing target).
					var stp := walk
					if mom > 0 or st[t] == S_ROUTING:
						stp = run_cap
					else:
						var to := u_order[unit_of[t]]
						if to == O_MOVE or to == O_WITHDRAW:
							stp = run_cap  # run down enemies pulling away
					var step_len := mini(stp, d - want)
					nx = x + dx * step_len / dl
					ny = y + dy * step_len / dl
					if lead_cap and mom == 0:
						var kc := base + slot
						var pl := Vector2i(ax + oxs[kc], ay + oys[kc])
						if wrap_t >= 0 and slot < files:
							pl = _curl(pl.x, pl.y, ax, ay, fcos, fsin, wr_tl, wr_lim, wr_dep)
						var cap := _cap_lead(x, y, nx, ny, pl.x, pl.y, fcos, fsin, PLACE_SIDE)
						nx = cap.x
						ny = cap.y
					if is_cav and step_len * 3 < run_cap:
						mom = maxi(mom - 15, 0)
				elif d < half_reach and dl > 0:
					var back := mini(walk >> 1, half_reach - d)
					nx = x - dx * back / dl
					ny = y - dy * back / dl
					if is_cav:
						mom = maxi(mom - 15, 0)
				fc[i] = FM.atan2_a(dy, dx)
				# Keep friendly fighters from stacking (every other tick).
				if ((tk + i) & 1) == 0:
					var c := clampi((ny >> gs) * gw + (nx >> gs), 0, gmax)
					var j := own_head[c]
					var checked := 0
					while j >= 0 and checked < 10:
						if j != i and st[j] < S_DEAD:
							var sx := nx - px[j]
							var sy := ny - py[j]
							if absi(sx) < sep and absi(sy) < sep:
								var sd := FM.approx_len(sx, sy)
								if sd < sep:
									if sd == 0:
										sx = (i & 1) * 2 - 1
										sy = 0
										sd = 1
									var push := (sep - sd) >> 1
									nx += sx * push / sd
									ny += sy * push / sd
						j = gnext[j]
						checked += 1
				if is_cav:
					if mom >= CHARGE_MIN and d <= reach + IMPACT_RANGE:
						# Two charging riders meeting head-on strike each other
						# at once, so the unit that happens to be processed
						# first this tick does not win the clash by
						# knocking the other down before he strikes.
						var tmom := cg[t] if t_rider[u_type[unit_of[t]]] != 0 else 0
						_impact(i, t, mom)
						if tmom >= CHARGE_MIN and st[t] < S_DEAD:
							_impact(t, i, tmom)
							cg[t] = 0
						mom = 0
						sk[i] = 1
					elif d <= reach:
						sk[i] = 1  # in contact (no momentum left to hit with)
					cg[i] = mom
					if st[i] >= S_DEAD:
						continue  # thrown back onto the points and killed
				var c2 := cd[i] - 1
				if st[t] >= S_DEAD:
					tg[i] = -1  # the impact killed it
				elif c2 <= 0:
					if d <= reach and st[i] == S_FIGHTING:
						_melee(i, t, 0)
						c2 = cool + _rand() % 4
					elif nwalls > 0 and d <= reach + PIKE_PRESS and st[i] == S_FIGHTING:
						# Pressed against the points: grab a pike shaft, lunge.
						_melee(i, t, PIKE_PRESS_PEN)
						c2 = cool + _rand() % 4
					else:
						c2 = 1 + ((tk + i) & 3)
				cd[i] = c2
			elif charging:
				# Riding in: straight on along the charge, at the run, spreading
				# round friends who have stopped.
				st[i] = S_FORMED
				nx = x + ((fcos * run_cap) / tone)
				ny = y + ((fsin * run_cap) / tone)
				fc[i] = face
				var c4 := clampi((ny >> gs) * gw + (nx >> gs), 0, gmax)
				var j4 := own_head[c4]
				var checked4 := 0
				while j4 >= 0 and checked4 < 10:
					if j4 != i and st[j4] < S_DEAD:
						var sx4 := nx - px[j4]
						var sy4 := ny - py[j4]
						if absi(sx4) < sep and absi(sy4) < sep:
							var sd4 := FM.approx_len(sx4, sy4)
							if sd4 < sep:
								if sd4 == 0:
									sx4 = (i & 1) * 2 - 1
									sy4 = 0
									sd4 = 1
								var push4 := sep - sd4
								nx += sx4 * push4 / sd4
								ny += sy4 * push4 / sd4
					j4 = gnext[j4]
					checked4 += 1
			else:
				# Slot following (formed pikes strike from here too).
				var k := base + slot_of[i]
				var dx := ax + oxs[k] - x
				var dy := ay + oys[k] - y
				if stair_mv != 0:
					var sgs := _stair_leave(u, x, y, stair_mv, slot_of[i])
					if sgs.z != 0:
						dx = sgs.x - x
						dy = sgs.y - y
				var wrapping := wrap_t >= 0 and front and t < 0
				if wrapping:
					dx = u_cx[wrap_t] - x
					dy = u_cy[wrap_t] - y
				if dx != 0 or dy != 0:
					var d := FM.approx_len(dx, dy)
					var spd := spd_formed if d <= CATCH_UP_DIST else run
					if d <= spd:
						nx = x + dx
						ny = y + dy
					else:
						nx = x + dx * spd / d
						ny = y + dy * spd / d
					if wrapping and lead_cap:
						# Lapping round: sideways, not out ahead of the line
						# (of its place curled round the target's flank).
						var plw := _curl(ax + oxs[k], ay + oys[k], ax, ay, fcos, fsin, wr_tl, wr_lim, wr_dep)
						var capw := _cap_lead(x, y, nx, ny, plw.x, plw.y, fcos, fsin, 1 << 30)
						nx = capw.x
						ny = capw.y
				fc[i] = face
				if is_cav:
					# Riders keep their own momentum a moment after the unit
					# stops, so rear ranks still hit home.
					cg[i] = maxi(umom, cg[i] - 10)
				if t >= 0:
					var ex := px[t] - x
					var ey := py[t] - y
					var rch := reach + t_body_r[u_type[unit_of[t]]] if bigb else reach
					var in_reach := ex * ex + ey * ey <= rch * rch
					# Only pikemen who can strike hold the block in place, so
					# a block keeps closing until its points reach.
					if in_reach:
						fighting += 1
						inreach += 1
					st[i] = S_FIGHTING
					var c3 := cd[i] - 1
					if c3 <= 0:
						if in_reach:
							_melee(i, t, 0)
							c3 = cool + _rand() % 4
						else:
							c3 = 1 + ((tk + i) & 3)
					cd[i] = c3
				else:
					st[i] = S_FORMED
			if charging:
				if sk[i] == 0:
					if slot < files:
						ch_left += 1
					if cg[i] >= CHARGE_MIN:
						ch_act += 1
			# Enemy pike walls: no stepping inside the points while the pike
			# formation is intact and facing this way.
			if nwalls > 0:
				for w in nwalls:
					var w5 := w * 5
					var pc := wp[w5]
					var ps := wp[w5 + 1]
					var rx := nx - wp[w5 + 2]
					var ry := ny - wp[w5 + 3]
					var f := (rx * pc + ry * ps) / tone
					if f >= PIKE_HOLD or f <= -M:
						continue
					var lat := (ry * pc - rx * ps) / tone
					var hw := wp[w5 + 4]
					if lat > hw or lat < -hw:
						continue
					var push2 := PIKE_HOLD - f
					nx += (pc * push2) / tone
					ny += (ps * push2) / tone
			nx = clampi(nx, 0, fw)
			ny = clampi(ny, 0, fh)
			var mm3 := mask if stair_mv == 0 else _stair_mask(u, x, y, mask, stair_mv)
			if ob and (navg[mini(ny >> 11, obh1) * obw + mini(nx >> 11, obw1)] & mm3) == 0:
				var sl3 := _slide(u, x, y, nx, ny, mm3)
				nx = sl3.x
				ny = sl3.y
			px[i] = nx
			py[i] = ny
			counted += 1
			sumx += nx
			sumy += ny
			if nx < minx: minx = nx
			if nx > maxx: maxx = nx
			if ny < miny: miny = ny
			if ny > maxy: maxy = ny
			if withdrawing and ((ny > exit_y if exit_y > EDGE_EXIT else ny < exit_y) \
					or (side_exit and (nx < 8 * M or nx > fw - 8 * M))):
				_rm[n_rm] = i
				_rm_why[n_rm] = GONE_WITHDRAWN
				n_rm += 1
		u_fighting[u] = fighting
		u_inreach[u] = inreach
		if charging:
			u_charge_left[u] = ch_left
			u_charge_act[u] = ch_act
		if counted > 0:
			_set_bounds(u, sumx / counted, sumy / counted, minx, miny, maxx, maxy)
		_flush_removals(n_rm)


func _flush_removals(count: int) -> void:
	for k in count:
		var i := _rm[k]
		if state[i] < S_DEAD:
			_remove(i, _rm_why[k])


## Nearest living enemy within radius r, scanning (2*cr+1)^2 cells.
func _find_target(x: int, y: int, r: int, cr: int, head: PackedInt32Array) -> int:
	stat_searches += 1
	var gs := GRID_SHIFT
	var cx := x >> gs
	var cy := y >> gs
	var best := -1
	var best_d := r * r + 1
	var px := pos_x
	var py := pos_y
	var st := state
	var nxt := grid_next
	var gw := grid_w
	for gy in range(maxi(cy - cr, 0), mini(cy + cr, grid_h - 1) + 1):
		var row := gy * gw
		for gx in range(maxi(cx - cr, 0), mini(cx + cr, gw - 1) + 1):
			var j := head[row + gx]
			while j >= 0:
				if st[j] < S_DEAD:
					var dx := px[j] - x
					var dy := py[j] - y
					var d2 := dx * dx + dy * dy
					# Tie-break on index so the result never depends on
					# list order.
					if (d2 < best_d or (d2 == best_d and j < best)):
						best_d = d2
						best = j
				j = nxt[j]
	return best


## Nearest living enemy within radius r inside the forward cone (fc, fs Q12
## facing): ahead of the soldier and no further to the side than ahead + 2 m.
func _find_target_cone(x: int, y: int, r: int, fc: int, fs: int, head: PackedInt32Array) -> int:
	stat_searches += 1
	var gs := GRID_SHIFT
	var cr := (r >> gs) + 1
	var cx := x >> gs
	var cy := y >> gs
	var best := -1
	var best_d := r * r + 1
	var px := pos_x
	var py := pos_y
	var st := state
	var nxt := grid_next
	var gw := grid_w
	var tone := FM.TRIG_ONE  # fixed-point divisor: truncation is symmetric under mirroring (>> floors)
	for gy in range(maxi(cy - cr, 0), mini(cy + cr, grid_h - 1) + 1):
		var row := gy * gw
		for gx in range(maxi(cx - cr, 0), mini(cx + cr, gw - 1) + 1):
			var j := head[row + gx]
			while j >= 0:
				if st[j] < S_DEAD:
					var dx := px[j] - x
					var dy := py[j] - y
					var d2 := dx * dx + dy * dy
					if d2 < best_d or (d2 == best_d and j < best):
						var f := (dx * fc + dy * fs) / tone
						var lat := absi((dy * fc - dx * fs) / tone)
						if f > 0 and lat < f + 2 * M:
							best_d = d2
							best = j
				j = nxt[j]
	return best


## Settlement maps: _find_target that does not reach through walls, gates or
## building corners and looks at most at SEARCH_CAP men.
func _find_target_obs(x: int, y: int, r: int, cr: int, head: PackedInt32Array) -> int:
	stat_searches += 1
	if _none_near(x, y, r):
		return -1
	var ob := _reach_checks(x, y)
	var budget := SEARCH_CAP
	var gs := GRID_SHIFT
	var cx := x >> gs
	var cy := y >> gs
	var best := -1
	var best_d := r * r + 1
	var px := pos_x
	var py := pos_y
	var st := state
	var nxt := grid_next
	var gw := grid_w
	# Rings of cells outward from his own; past a ring no cell can hold a
	# nearer man than one already found (each is a whole cell further).
	var gh1 := grid_h - 1
	var gw1 := gw - 1
	for k in cr + 1:
		if k >= 2 and best >= 0 and best_d < ((k - 1) << gs) * ((k - 1) << gs):
			break
		var gy := maxi(cy - k, 0)
		var gy1 := mini(cy + k, gh1)
		while gy <= gy1:
			var row := gy * gw
			var edge_y := gy == cy - k or gy == cy + k
			var cdy := maxi(maxi((gy << gs) - y, y - (((gy + 1) << gs) - 1)), 0)
			cdy *= cdy
			# Off the ring's top and bottom rows only its two side cells.
			var gx := maxi(cx - k, 0) if edge_y else cx - k
			var gx1 := mini(cx + k, gw1)
			var gstep := 1 if edge_y else maxi(2 * k, 1)
			gy += 1
			if cdy > best_d:
				continue
			while gx <= gx1:
				var gxc := gx
				gx += gstep
				if gxc < 0:
					continue
				var j := head[row + gxc]
				if j < 0:
					continue
				# Skip a cell no part of which is nearer than the best so far
				# (or the search radius).
				var cdx := maxi(maxi((gxc << gs) - x, x - (((gxc + 1) << gs) - 1)), 0)
				if cdx * cdx + cdy > best_d:
					continue
				while j >= 0 and budget > 0:
					budget -= 1
					if st[j] < S_DEAD:
						var dx := px[j] - x
						var dy := py[j] - y
						var d2 := dx * dx + dy * dy
						# Tie-break on index so the result never depends on
						# list order. (Not through a wall, gate or building.)
						if (d2 < best_d or (d2 == best_d and j < best)) and (ob == 0 or _reach_ok(x, y, px[j], py[j])):
							best_d = d2
							best = j
					j = nxt[j]
	return best


## Settlement maps: _find_target_cone likewise (see _find_target_obs).
## Nearest living enemy within radius r inside the forward cone (fc, fs Q12
## facing): ahead of the soldier and no further to the side than ahead + 2 m.
func _find_target_cone_obs(x: int, y: int, r: int, fc: int, fs: int, head: PackedInt32Array) -> int:
	stat_searches += 1
	if _none_near(x, y, r):
		return -1
	var ob := _reach_checks(x, y)
	var budget := SEARCH_CAP
	var gs := GRID_SHIFT
	var cr := (r >> gs) + 1
	var cx := x >> gs
	var cy := y >> gs
	var best := -1
	var best_d := r * r + 1
	var px := pos_x
	var py := pos_y
	var st := state
	var nxt := grid_next
	var gw := grid_w
	var tone := FM.TRIG_ONE  # fixed-point divisor: truncation is symmetric under mirroring (>> floors)
	var gh1 := grid_h - 1
	var gw1 := gw - 1
	for k in cr + 1:
		if k >= 2 and best >= 0 and best_d < ((k - 1) << gs) * ((k - 1) << gs):
			break
		var gy := maxi(cy - k, 0)
		var gy1 := mini(cy + k, gh1)
		while gy <= gy1:
			var row := gy * gw
			var edge_y := gy == cy - k or gy == cy + k
			var cdy := maxi(maxi((gy << gs) - y, y - (((gy + 1) << gs) - 1)), 0)
			cdy *= cdy
			# Off the ring's top and bottom rows only its two side cells.
			var gx := maxi(cx - k, 0) if edge_y else cx - k
			var gx1 := mini(cx + k, gw1)
			var gstep := 1 if edge_y else maxi(2 * k, 1)
			gy += 1
			if cdy > best_d:
				continue
			while gx <= gx1:
				var gxc := gx
				gx += gstep
				if gxc < 0:
					continue
				var j := head[row + gxc]
				if j < 0:
					continue
				# Skip a cell no part of which is nearer than the best so far
				# (or the search radius).
				var cdx := maxi(maxi((gxc << gs) - x, x - (((gxc + 1) << gs) - 1)), 0)
				if cdx * cdx + cdy > best_d:
					continue
				while j >= 0 and budget > 0:
					budget -= 1
					if st[j] < S_DEAD:
						var dx := px[j] - x
						var dy := py[j] - y
						var d2 := dx * dx + dy * dy
						if d2 < best_d or (d2 == best_d and j < best):
							var f := (dx * fc + dy * fs) / tone
							var lat := absi((dy * fc - dx * fs) / tone)
							if f > 0 and lat < f + 2 * M and (ob == 0 or _reach_ok(x, y, px[j], py[j])):
								best_d = d2
								best = j
					j = nxt[j]
	return best


## Where (x, y) is relative to unit u's formation: ahead of its front line
## (front), behind its rear rank (rear) or alongside (flank). Melee blows
## (shield, flank / rear to-hit bonus, morale, pike disorder) and bracing
## use this rather than the angle between two duellists, so oblique blows
## inside a frontal melee stay frontal and a man turned to face a flanker
## is still taken in the flank.
func _zone(u: int, x: int, y: int) -> int:
	if u_state[u] != U_READY:
		return ZONE_REAR
	var c := FM.cos_a(u_face[u])
	var s := FM.sin_a(u_face[u])
	var rx := x - u_ax[u]
	var ry := y - u_ay[u]
	var f := (rx * c + ry * s) / FM.TRIG_ONE
	if f >= -M:
		# Beside the end of the line rather than ahead of it: flank.
		var lat := absi((ry * c - rx * s) / FM.TRIG_ONE)
		if f < 2 * M and lat > unit_half_width(u) + 2 * M:
			return ZONE_FLANK
		return ZONE_FRONT
	if f < -(unit_depth(u) + M):
		return ZONE_REAR
	return ZONE_FLANK


## Wrap at the anchor level: the place (plx, ply) of a front-rank man of a
## unit (anchor ax, ay, facing c, s) engaged with a target whose middle is
## `tl` to the side of the anchor and which reaches `lim` either side of
## it: a place standing out beyond that by e curls forward by f = min(e,
## dep) and in by f, round the target's flank (the line bends into an L).
static func _curl(plx: int, ply: int, ax: int, ay: int, c: int, s: int, tl: int, lim: int, dep: int) -> Vector2i:
	var rel := ((ply - ay) * c - (plx - ax) * s) / FM.TRIG_ONE - tl
	var e := absi(rel) - lim
	if e <= 0:
		return Vector2i(plx, ply)
	var f := mini(e, dep)
	var sg := 1 if rel > 0 else -1
	return Vector2i(plx + (c * f + sg * s * f) / FM.TRIG_ONE, ply + (s * f - sg * c * f) / FM.TRIG_ONE)


## A fighting man's step from (x, y) to (nx, ny), cut so it takes him no
## further than PLACE_LEAD ahead of his place (plx, ply) along the unit's
## facing (c, s), nor further than `side` to either side of it. Only the
## part of the step that goes beyond is cut, and a man already beyond is
## not pulled back, just stops going further that way.
static func _cap_lead(x: int, y: int, nx: int, ny: int, plx: int, ply: int, c: int, s: int,
		side: int) -> Vector2i:
	var rx := nx - x
	var ry := ny - y
	var ox := x - plx
	var oy := y - ply
	var sf := (rx * c + ry * s) / FM.TRIG_ONE
	if sf > 0:
		var over := (ox * c + oy * s) / FM.TRIG_ONE + sf - PLACE_LEAD
		if over > 0:
			over = mini(over, sf)
			nx -= c * over / FM.TRIG_ONE
			ny -= s * over / FM.TRIG_ONE
	var sl := (ry * c - rx * s) / FM.TRIG_ONE
	if sl != 0:
		var l1 := (oy * c - ox * s) / FM.TRIG_ONE + sl
		var cut := 0
		if sl > 0 and l1 > side:
			cut = mini(l1 - side, sl)
		elif sl < 0 and l1 < -side:
			cut = maxi(l1 + side, sl)
		if cut != 0:
			nx += s * cut / FM.TRIG_ONE
			ny -= c * cut / FM.TRIG_ONE
	return Vector2i(nx, ny)


## Melee blow by soldier a at soldier d. `pen` is a hit penalty; `parting`
## is a free blow at the back of a soldier turning away from the fight
## (rear bonus, no shield, no unit-level flank effects).
func _melee(a: int, d: int, pen: int, parting: bool = false) -> void:
	if state[d] >= S_DEAD:
		return
	stat_attacks += 1
	var ua := unit_of[a]
	var ud := unit_of[d]
	# Front, flank or rear by where the attacker stands relative to the
	# defender's *unit* (its line and facing), not how the struck man is
	# turned: the shield, the to-hit bonus and the morale hit all follow it.
	var zone := _zone(ud, pos_x[a], pos_y[a])
	var frontal := zone == ZONE_FRONT
	var bonus := 0
	var sd := state[d]
	if parting:
		stat_parting += 1
		frontal = false
		bonus = REAR_BONUS
		zone = ZONE_FRONT
	elif sd == S_ROUTING:
		frontal = false
		bonus = REAR_BONUS
	elif sd == S_DOWN:
		frontal = false
		bonus = DOWN_BONUS
	elif zone == ZONE_REAR:
		bonus = REAR_BONUS
	elif zone == ZONE_FLANK:
		bonus = FLANK_BONUS
	if bonus > 0 and sg_on != 0 and u_carry[ud] >= 0 and q_kind[u_carry[ud]] == EQ_WAGON:
		bonus += WAGON_EXPOSED  # men in the traces of a wagon, hit from the side or behind
	var att := u_att[ua]
	var dmg0 := u_dmg[ua]
	var def := u_def[ud]
	var td := u_otype[ud]  # (the men's own arms and armour, whatever they work)
	# Pikemen caught from the flank or rear fight with the short sword.
	if u_cls[ud] == UT.CLS_PIKE and zone != ZONE_FRONT:
		def = t_sec_def[td]
	if u_cls[ud] == UT.CLS_CAV or t_as_cav[td] != 0:
		var vc := t_vs_cav[u_otype[ua]]
		att += vc
		dmg0 += vc
	if veg_on != 0:
		# Horses cannot turn and press among trees.
		if u_cls[ua] == UT.CLS_CAV:
			bonus -= VEG_CAV_MELEE[veg_d(pos_x[a], pos_y[a])]
		if u_cls[ud] == UT.CLS_CAV:
			bonus += VEG_CAV_MELEE[veg_d(pos_x[d], pos_y[d])]
	var chance := clampi(BASE_HIT + att - def + bonus - pen, 5, 95)
	if ter_on == 0 and fwh_on == 0:
		if _rand() % 100 >= chance:
			return
	else:
		# Hilly map: the same roll at per-mille resolution, so a small slope
		# gives a small edge (a whole percent is already a lot in a long
		# frontal fight).
		var cpm := clampi(chance * 10 + _height_bonus(a, d), 50, 950)
		if _rand() % 1000 >= cpm:
			return
	if frontal and _rand() % 100 < t_shield[td]:
		return
	var dmg := maxi(dmg0 - t_armour[td], 4)
	dmg = dmg * (85 + _rand() % 31) / 100
	# Morale and disorder: the same unit-relative zone.
	if sd != S_ROUTING and u_state[ud] == U_READY:
		if zone == ZONE_REAR:
			u_morale[ud] -= MORALE_REAR_HIT
			_add_disorder(ud, DISORDER_REAR_HIT)
		elif zone == ZONE_FLANK:
			u_morale[ud] -= MORALE_FLANK_HIT
			_add_disorder(ud, DISORDER_FLANK_HIT)
	var h := hp[d] - dmg
	if h <= 0:
		stat_kills[0 if frontal else 1] += 1
		stat_kside[u_side[ud] * 5 + (0 if frontal else 1)] += 1
		_credit(ua, ud)
		_remove(d, GONE_KILLED)
	else:
		hp[d] = h


## Melee to-hit bonus (per mille) for soldier a striking soldier d from
## higher ground (negative from below): MELEE_H_K per 100% of the grade
## between them, capped at MELEE_H_CAP. Only called on hilly maps.
func _height_bonus(a: int, d: int) -> int:
	var xa := pos_x[a]
	var ya := pos_y[a]
	var xd := pos_x[d]
	var yd := pos_y[d]
	var g := grade_between(gh_at(xd, yd), gh_at(xa, ya), FM.approx_len(xa - xd, ya - yd))
	var b := clampi(g * MELEE_H_K / FM.TRIG_ONE, -MELEE_H_CAP, MELEE_H_CAP)
	if b != 0:
		stat_h_melee += 1
	return b


## Add disorder to unit u; a pike block on steep ground loses its order
## more easily (PIKE_STEEP_DIS %).
func _add_disorder(u: int, amt: int) -> void:
	if ter_on != 0 and _u_steep[u] != 0 and u_cls[u] == UT.CLS_PIKE:
		amt = amt * PIKE_STEEP_DIS / 100
	u_disorder[u] = mini(u_disorder[u] + amt, DISORDER_MAX)


## Cavalry impact: rider r with momentum mom reaches enemy soldier t.
## Beasts (their rows' fields): a braced front still takes crush % of an
## elephant's charge; the impact carries on into trample_n more men within
## trample_r (a horse: one, 1.8 m, 60 %); horses scared by camels near
## (u_scare) hit at that %, and a horse charging a unit with a horse scare
## hits at its scare_pct and loses heart.
func _impact(r: int, t: int, mom: int) -> void:
	var ur := unit_of[r]
	var ut := unit_of[t]
	var rty := u_otype[ur]
	var td := u_otype[ut]
	var zone := _zone(ut, pos_x[r], pos_y[r])
	dbg_impacted[r] = 1
	struck[r] = 1
	var through := 100
	if zone == ZONE_FRONT and u_braced[ut] != 0 and state[t] != S_ROUTING:
		# Braced points: the impact is turned back on the rider.
		stat_reflects += 1
		if u_target[ur] == ut:
			stat_reflects_aimed += 1
		var back := t_brace[td] * mom / 100
		back = maxi(back * (85 + _rand() % 31) / 100 - t_armour[rty] / 2, 1)
		u_morale[ur] -= MORALE_REFLECT
		if _rand() % 100 < 40:
			_knock_down(r)
		var h := hp[r] - back
		if h <= 0:
			_remove(r, GONE_KILLED)
		else:
			hp[r] = h
		if t_crush[rty] == 0 or state[r] >= S_DEAD:
			return
		# A beast's weight carries on into the points all the same.
		through = t_crush[rty]
		stat_crush += 1
	stat_impacts += 1
	var power := t_charge[rty] * mom / 100
	if through != 100:
		power = power * through / 100
	if u_scare[ur] > 0:
		power = power * u_scare[ur] / 100  # a horse that smells camels near
	if t_mount[rty] == UT.MOUNT_HORSE and t_scare_r[td] > 0:
		# Charging camels: the horse shies at the last moment.
		power = power * t_scare_pct[td] / 100
		u_morale[ur] -= MORALE_REFLECT
		stat_scare_hits += 1
	if ter_on != 0 or fwh_on != 0:
		# Riding down onto a man hits harder; riding up at him, weaker.
		var g := grade_between(gh_at(pos_x[t], pos_y[t]), gh_at(pos_x[r], pos_y[r]),
			FM.approx_len(pos_x[r] - pos_x[t], pos_y[r] - pos_y[t]))
		var f := clampi(100 + g * CHG_H_K / FM.TRIG_ONE, CHG_H_MIN, CHG_H_MAX)
		if f > 100:
			stat_charge_down += 1
		elif f < 100:
			stat_charge_up += 1
		power = power * f / 100
	if veg_on != 0:
		# Into a man standing in woods: the trees break the charge.
		var vdv := veg_d(pos_x[t], pos_y[t])
		if vdv > 0:
			power = power * VEG_IMPACT[vdv] / 100
			stat_veg_impact += 1
	var ma := t_mass[rty]
	if not _impact_victim(r, t, power, ma, zone):
		return  # stopped by a man who stood his ground in a steady front
	# The horse breaks through and carries on into another soldier within
	# reach (a beast into several): the least hurt one (then the nearest), a
	# rule that does not depend on direction (the first found in grid scan
	# order favoured one side of the field) and does not pile every carry-on
	# onto the same men.
	var head: PackedInt32Array = grid_head1 if u_side[ur] == 0 else grid_head0
	var gs := GRID_SHIFT
	var rad := t_tr_r[rty]
	var carry := power * t_tr_pct[rty] / 100
	var hit := PackedInt32Array([t])
	for k in t_tr_n[rty]:
		if k > 0 and state[r] >= S_DEAD:
			return  # (a horse carries on into its one man as it always did)
		var x := pos_x[r]
		var y := pos_y[r]
		var cx := x >> gs
		var cy := y >> gs
		var best := -1
		var best_d := 0
		for gy in range(maxi(cy - 1, 0), mini(cy + 1, grid_h - 1) + 1):
			for gx in range(maxi(cx - 1, 0), mini(cx + 1, grid_w - 1) + 1):
				var j := head[gy * grid_w + gx]
				while j >= 0:
					if state[j] < S_DOWN and (k == 0 and j != t or k > 0 and not hit.has(j)):
						var dx := pos_x[j] - x
						var dy := pos_y[j] - y
						if absi(dx) < rad and absi(dy) < rad:
							var d2 := dx * dx + dy * dy
							if best < 0 or hp[j] > hp[best] or (hp[j] == hp[best] and (d2 < best_d \
									or (d2 == best_d and j < best))):
								best = j
								best_d = d2
					j = grid_next[j]
		if best < 0:
			return
		hit.append(best)
		_impact_victim(r, best, carry, ma, zone)


## One soldier v hit by rider r's charge (power before direction and mass).
## Direction is judged per victim: a soldier who has the rider in front of
## him, or who is free to turn to him (not fighting someone else) and is not
## taken from behind, meets the charge frontally even when the rider has
## lapped round the end of the line. Only riders who really reach the side or
## the back of their man get the flank / rear multiplier. A frontal impact on
## a steady formed unit is met by the shield (blocked: half force), armour
## counts in full, the ranks behind steady the man (half knockdown chance),
## and the soldier strikes back at the horse as it arrives.
## Returns true if the horse broke through (the man was killed or knocked
## down, or was not standing in a steady front facing it).
func _impact_victim(r: int, v: int, power: int, ma: int, zone: int) -> bool:
	var uv := unit_of[v]
	var tv := u_otype[uv]
	var sv := state[v]
	var md := t_mass[tv]
	var from_v := FM.atan2_a(pos_y[r] - pos_y[v], pos_x[r] - pos_x[v])
	var rel := absi(FM.angle_diff(facing[v], from_v))
	var tv_t := target[v]
	var free := tv_t < 0 or unit_of[tv_t] == unit_of[r]
	var ready := u_state[uv] == U_READY and sv != S_ROUTING and sv != S_DOWN
	var dirmul := 100
	var shock := MORALE_CHARGE_FRONT
	var frontal := false
	if not ready:
		dirmul = 160
		shock = MORALE_CHARGE_REAR
	elif rel <= FRONT_ARC or (free and rel <= REAR_ARC and zone != ZONE_REAR):
		frontal = true
	elif zone == ZONE_REAR or rel > REAR_ARC:
		dirmul = 160
		shock = MORALE_CHARGE_REAR
	else:
		dirmul = 130
		shock = MORALE_CHARGE_FLANK
	var force := power * dirmul / 100 * ma / (ma + md)
	if dirmul > 100 and ready:
		stat_aic[u_side[unit_of[r]] * AIProfile.N_COUNTERS + AIProfile.C_FLANK_HIT] += 1
	var arm := t_armour[tv] / 2
	var knock := mini(force + 10, 90)
	# A beast (crush) goes through shields and the ranks behind: no man stops it.
	var crush := t_crush[u_otype[unit_of[r]]] > 0
	if frontal:
		arm = t_armour[tv]
		# (Impacts pile up disorder within a tick, so only morale counts here.)
		var steady := u_morale[uv] >= WAVER and not crush
		if steady:
			if _rand() % 100 < t_shield[tv]:
				force /= 2  # taken on the shield
				stat_impact_blocked += 1
			# Ranks behind brace the man: harder to bowl over.
			if u_alive[uv] > 2 * maxi(mini(files_of(uv), u_alive[uv]), 1):
				knock = mini(force + 10, 90) / 2
			else:
				knock = mini(force + 10, 90)
		else:
			knock = mini(force + 10, 90)
	if big_on != 0 and t_body_r[tv] > 0:
		knock = 0  # a big body stands (and stops the rider: below)
	var dmg := maxi(force - arm, 1) * (85 + _rand() % 31) / 100
	if u_state[uv] == U_READY:
		u_morale[uv] -= shock
		_add_disorder(uv, DISORDER_IMPACT)
		u_charged_t[uv] = tick
	var h := hp[v] - dmg
	if h <= 0:
		stat_kills[2] += 1
		stat_kside[u_side[uv] * 5 + 2] += 1
		_credit(unit_of[r], uv)
		_remove(v, GONE_KILLED)
		return true
	hp[v] = h
	if sv != S_DOWN and _rand() % 100 < knock:
		_knock_down(v)
		return true
	if frontal and state[r] < S_DEAD:
		# Still on his feet facing the horse: he strikes back as it arrives.
		_melee(v, r, 0)
	return crush or not (frontal and u_morale[uv] >= WAVER)


func _knock_down(i: int) -> void:
	var st := state[i]
	if st == S_DOWN or st >= S_DEAD:
		return
	if big_on != 0 and t_body_r[u_otype[unit_of[i]]] > 0:
		return  # nothing bowls over an elephant
	stat_knockdowns += 1
	if st == S_ROUTING:
		return  # routers keep running; the hit was enough
	state[i] = S_DOWN
	target[i] = -1
	cooldown[i] = DOWN_TICKS + _rand() % 10
	var u := unit_of[i]
	u_down[u] += 1
	u_settled[u] = 0


## Take soldier d off the field: killed, withdrawn or routed off the edge.
## A soldier of unit ud killed by the men (or engines) of unit k: an enemy
## counts in k's u_kills, a friend in stat_ff.
func _credit(k: int, ud: int) -> void:
	if k < 0 or k >= n_units:
		return
	if u_side[k] != u_side[ud]:
		u_kills[k] += 1
	else:
		stat_ff[u_side[ud]] += 1


func _remove(d: int, why: int) -> void:
	if state[d] >= S_DEAD:
		return  # already off the field
	var u := unit_of[d]
	if state[d] == S_DOWN:
		u_down[u] -= 1
	if why == GONE_KILLED:
		hp[d] = 0
		state[d] = S_DEAD
		u_killed[u] += 1
		var c0 := maxi(u_count0[u], 1)
		u_recent[u] += 1000 / c0
		u_morale[u] -= MORALE_LOSS_PER_DEATH_TOTAL * (1000 + MORALE_RATE_K * u_recent[u]) / (1000 * c0)
	else:
		state[d] = S_OFF
		if why == GONE_WITHDRAWN:
			u_withdrawn[u] += 1
		else:
			u_routed_off[u] += 1
		if sea_on != 0 and u_side[u] == city_def:
			stat_sea_exit += 1
	target[d] = -1
	if u_eg[u] >= 0:
		u_oammo[u] -= ammo[d]  # (working engines: his own arrows go with him)
	else:
		u_ammo[u] -= ammo[d]
	ammo[d] = 0
	sammo[d] = 0
	var alive := u_alive[u]
	var base := u_slot_base[u]
	var files := maxi(files_of(u), 1)
	# Fill the gap: the soldier behind steps forward, repeatedly, so the hole
	# ends at the back; then the last slot fills it to keep slots compact.
	var hole := slot_of[d]
	while hole + files < alive:
		var mover := slot_soldier[base + hole + files]
		slot_soldier[base + hole] = mover
		slot_of[mover] = hole
		hole += files
	var last := alive - 1
	if hole != last:
		var mover2 := slot_soldier[base + last]
		slot_soldier[base + hole] = mover2
		slot_of[mover2] = hole
	slot_soldier[base + last] = -1
	slot_of[d] = -1
	alive -= 1
	u_alive[u] = alive
	u_dirty[u] = 1
	u_settled[u] = 0
	if alive <= 0:
		if why == GONE_KILLED and (t_cmd_loss[u_type[u]] > 0 or t_cmd_loss_r[u_type[u]] > 0):
			_cmd_fall(u)  # the general's last man falls
		u_state[u] = U_LEFT if u_withdrawn[u] + u_routed_off[u] > 0 else U_DESTROYED
		u_order[u] = O_NONE
		u_target[u] = -1
		u_ftarget[u] = -1
		u_down[u] = 0


func _set_bounds(u: int, cx: int, cy: int, minx: int, miny: int, maxx: int, maxy: int) -> void:
	u_cx[u] = cx
	u_cy[u] = cy
	u_minx[u] = minx
	u_miny[u] = miny
	u_maxx[u] = maxx
	u_maxy[u] = maxy


## Recompute slot offsets of units whose formation changed this tick
## (deaths shrink the last rank).
func _refresh_offsets() -> void:
	for u in n_units:
		if u_dirty[u] != 0 and u_state[u] == U_READY and u_alive[u] > 0:
			_compute_offsets(u)


## Full recompute of centroids and bounding boxes (setup only; during play
## _update_soldiers maintains them as it moves soldiers).
func _update_bounds() -> void:
	for u in n_units:
		var alive := u_alive[u]
		if alive <= 0:
			continue
		if u_settled[u] != 0 and u_dirty[u] == 0:
			continue
		var base := u_slot_base[u]
		var i0 := slot_soldier[base]
		var minx := pos_x[i0]
		var maxx := minx
		var miny := pos_y[i0]
		var maxy := miny
		var sx := 0
		var sy := 0
		for s in alive:
			var i := slot_soldier[base + s]
			var x := pos_x[i]
			var y := pos_y[i]
			sx += x
			sy += y
			if x < minx:
				minx = x
			elif x > maxx:
				maxx = x
			if y < miny:
				miny = y
			elif y > maxy:
				maxy = y
		u_cx[u] = sx / alive
		u_cy[u] = sy / alive
		u_minx[u] = minx
		u_maxx[u] = maxx
		u_miny[u] = miny
		u_maxy[u] = maxy
		if u_dirty[u] != 0 and u_state[u] == U_READY:
			_compute_offsets(u)


# -------------------------------------------------------------- missiles ---

func _update_missiles() -> void:
	# Fire.
	for u in n_units:
		var ft := u_ftarget[u]
		if ft < 0:
			continue
		if u_state[u] != U_READY or u_ammo[u] <= 0 or u_state[ft] >= U_DESTROYED or u_alive[ft] <= 0:
			u_ftarget[u] = -1
			continue
		if u_moved[u] != 0:
			continue  # no shooting on the move
		if u_cls[u] == UT.CLS_ART:
			continue  # engines shoot in _update_artillery (men working them keep their own arrows)
		var ty := u_type[u]
		var alive := u_alive[u]
		var shooters := alive * t_crew_sh[ty]  # (an elephant: its crew)
		var acc := u_fire_acc[u] + shooters
		var ks := u_sk[u]
		var kstd := t_m_ak[ty]
		var pref := ks >= 0 and u_akind[u] != 0
		var reload := t_m_reload[ty] * t_k_rate[ks if pref else kstd] / 100 if kstd >= 0 else t_m_reload[ty]
		var tries := 0
		var high := t_crew_sh[ty] > 1  # shooters on a beast's back shoot while it fights
		while acc >= reload and tries < shooters:
			acc -= reload
			tries += 1
			var ptr := u_fire_ptr[u] % alive
			u_fire_ptr[u] = ptr + 1
			var i := slot_soldier[u_slot_base[u] + ptr]
			if (state[i] != S_FORMED and not (high and state[i] == S_FIGHTING)) or ammo[i] <= 0:
				continue
			_fire(i, u, ft, ty, _shot_kind(i, ks, kstd, pref))
		u_fire_acc[u] = mini(acc, reload)
	if city_on != 0:
		_gate_volleys()
	# Land everything due this tick.
	var b := tick % PR_BUCKETS
	var p := pr_bucket[b]
	pr_bucket[b] = -1
	while p >= 0:
		var nxt := pr_next[p]
		if pr_t1[p] == tick:
			_land(p)
			pr_t1[p] = -1
			pr_next[p] = pr_free
			pr_free = p
			pr_count -= 1
		else:
			# Not due yet (cannot happen while flight < PR_BUCKETS): keep.
			pr_next[p] = pr_bucket[b]
			pr_bucket[b] = p
		p = nxt


## The kind soldier i shoots: the one his unit means (pref: its special
## kind ks, else the standard kstd) while he has it, else the other.
func _shot_kind(i: int, ks: int, kstd: int, pref: bool) -> int:
	if ks < 0:
		return kstd
	var sp := sammo[i] > 0
	var st := ammo[i] > sammo[i]
	return ks if sp and (pref or not st) else kstd


func _fire(i: int, u: int, ft: int, ty: int, ak: int = -1) -> void:
	var talive := u_alive[ft]
	var j := slot_soldier[u_slot_base[ft] + _rand() % talive]
	var sx := pos_x[i]
	var sy := pos_y[i]
	# Lead the target: aim where it will be after the flight, from its
	# movement this tick (all integer; two passes refine the flight time).
	var vx := pos_x[j] - prev_x[j]
	var vy := pos_y[j] - prev_y[j]
	var spd := t_m_speed[ty]
	var ax := pos_x[j]
	var ay := pos_y[j]
	for k in 2:
		var fl := FM.approx_len(ax - sx, ay - sy) / spd + 3
		ax = pos_x[j] + vx * fl
		ay = pos_y[j] + vy * fl
	var dx := ax - sx
	var dy := ay - sy
	var dist := FM.approx_len(dx, dy)
	var rp := t_k_range[ak] if ak >= 0 else 100
	if ter_on == 0 and map_on == 0 and fwh_on == 0:
		if dist > t_m_range[ty] * rp / 100 or dist <= 0 or pr_free < 0:
			return
	else:
		if dist <= 0 or pr_free < 0 or not _shot_ok(sx, sy, ax, ay, dist, ty, 0, _skip1(ft),
				_wall_rb(u, ft) + _works_rb(u, ft), rp):
			return
	var p := pr_free
	pr_free = pr_next[p]
	pr_count += 1
	ammo[i] -= 1
	u_ammo[u] -= 1
	if ak >= 0 and t_k_base[ak] >= 0:
		sammo[i] -= 1
		stat_ak_shots += 1
	stat_shots += 1
	facing[i] = FM.atan2_a(dy, dx)
	# Scatter: lateral error, and a larger error along the line of flight.
	var spread := t_m_spread0[ty] + dist * t_m_spread[ty] / 1000
	var lat := (_rand() % (spread + 1) + _rand() % (spread + 1)) - spread
	var lon := ((_rand() % (spread + 1) + _rand() % (spread + 1)) - spread) * 3 / 2
	var ux := dx * FM.TRIG_ONE / dist
	var uy := dy * FM.TRIG_ONE / dist
	var lx := ax + ((ux * lon - uy * lat) / FM.TRIG_ONE)
	var ly := ay + ((uy * lon + ux * lat) / FM.TRIG_ONE)
	var flight := clampi(dist / t_m_speed[ty] + 3, 3, PR_BUCKETS - 1)
	pr_sx[p] = sx
	pr_sy[p] = sy
	pr_x[p] = clampi(lx, 0, field_w)
	pr_y[p] = clampi(ly, 0, field_h)
	pr_t0[p] = tick
	pr_t1[p] = tick + flight
	pr_unit[p] = u
	pr_ty[p] = ty
	pr_tu[p] = ft
	pr_ak[p] = ak
	var b := (tick + flight) % PR_BUCKETS
	pr_next[p] = pr_bucket[b]
	pr_bucket[b] = p


## Hilly maps: a shot from (sx, sy) at (ax, ay), dist apart, is within the
## height-adjusted range and, for a flat weapon, has a line of fire.
func _shot_ok(sx: int, sy: int, ax: int, ay: int, dist: int, ty: int, skip0: int = 0,
		skip1: int = LOF_SKIP, wb: int = 0, rp: int = 100) -> bool:
	var hs := elev_at(sx, sy) if obs_on != 0 else gh_at(sx, sy)
	var ha := elev_at(ax, ay) if obs_on != 0 else gh_at(ax, ay)
	if dist > range_h(ty, hs, ha, rp) + wb:
		return false
	if dist > t_m_range[ty] * rp / 100:
		stat_range_up += 1
	if t_m_arc[ty] == 0 and lof_block(sx, sy, hs + LOF_EYE, ax, ay, ha + LOF_BODY,
			dist * t_m_apex[ty] / 100, 0, LOF_STEP, skip0, skip1) >= 0:
		stat_lof_blocked += 1
		return false
	return true


## A projectile lands: the nearest soldier (either side) within his hit radius
## of the landing point takes the hit.
func _land(p: int) -> void:
	if fire_on != 0 and pr_ak[p] >= 0 and t_k_fire[pr_ak[p]] > 0:
		_ignite(p)
	var kind := t_m_kind[pr_ty[p]]
	if kind == 1:
		_land_bolt(p)
		return
	if kind == 2:
		_land_stone(p)
		return
	if wag_h > 0 and _horse_hit(p):
		return  # struck a wagon's horse
	var x := pr_x[p]
	var y := pr_y[p]
	var best := -1
	var best_d := 0
	# Soldiers of units near the enemy (melee, friend or foe) are in the grid.
	if stat_grid_soldiers > 0:
		var r := _hit_rmax
		var gs := GRID_SHIFT
		var gx0 := maxi((x - r) >> gs, 0)
		var gx1 := mini((x + r) >> gs, grid_w - 1)
		var gy0 := maxi((y - r) >> gs, 0)
		var gy1 := mini((y + r) >> gs, grid_h - 1)
		for side in 2:
			var head: PackedInt32Array = grid_head0 if side == 0 else grid_head1
			for gy in range(gy0, gy1 + 1):
				for gx in range(gx0, gx1 + 1):
					var j := head[gy * grid_w + gx]
					while j >= 0:
						if state[j] < S_DEAD:
							var dx := pos_x[j] - x
							var dy := pos_y[j] - y
							var d2 := dx * dx + dy * dy
							var hr := t_hit_r[u_type[unit_of[j]]]
							if d2 <= hr * hr and (best < 0 or d2 < best_d or (d2 == best_d and j < best)):
								best = j
								best_d = d2
						j = grid_next[j]
	# The unit aimed at, if it is not in the grid: find the slot under the
	# landing point from the formation geometry.
	var tu := pr_tu[p]
	if best < 0 and tu >= 0 and u_contact[tu] == 0 and u_alive[tu] > 0:
		var j := -1
		if u_state[tu] == U_READY and u_neng[tu] == 0 and u_wall[tu] == 0:
			j = _slot_at(tu, x, y)
		else:
			j = _nearest_in_unit(tu, x, y)
		if j >= 0:
			var dx := pos_x[j] - x
			var dy := pos_y[j] - y
			var hr := t_hit_r[u_type[tu]]
			if dx * dx + dy * dy <= hr * hr:
				best = j
	if best >= 0 and map_on != 0:
		# Trees take some of what falls into woods; battlements shelter men
		# on a wall from shots from below.
		var vd := veg_d(x, y)
		if vd > 0:
			var stop: int = VEG_STOP_ARROW[vd] if t_m_arc[pr_ty[p]] != 0 else VEG_STOP_JAV[vd]
			if _rand() % 100 < stop:
				stat_veg_stop += 1
				return
		var ub := unit_of[best]
		if u_wall[ub] > 0 and u_wall[pr_unit[p]] == 0 and (u_stair[ub] != ST_LADDER or _on_walk(pos_x[best], pos_y[best])) \
				and _rand() % 100 < WALL_COVER[city_walls]:
			stat_wall_cover += 1
			return
	if best >= 0 and (map_on != 0 or mt_on != 0) and sg_on != 0:
		# (Roofs count on plain maps only in battles with mantlets: the others play as before.)
		var uc := u_carry[unit_of[best]]
		if uc >= 0 and EQ_ROOF[q_kind[uc]] != 0 \
				and FM.approx_len(pos_x[best] - q_x[uc], pos_y[best] - q_y[uc]) <= EQ_ROOF_R[q_kind[uc]] \
				and _rand() % 100 < EQ_ROOF[q_kind[uc]]:
			return  # on the ram's (the wagon's) roof, under the carried mantlet
	if best >= 0 and fwh_on != 0 and _works_cover(pr_sx[p], pr_sy[p], best):
		return  # behind the palisade
	if best >= 0 and mt_on != 0 and _screen_cover(pr_sx[p], pr_sy[p], best, false):
		return  # behind a mantlet
	if best >= 0:
		_missile_hit(p, best)


## Soldier nearest to (x, y) among the formation slot under that point and
## its neighbours (soldiers are often a little off their slots), or -1.
func _slot_at(u: int, x: int, y: int) -> int:
	var ty := u_type[u]
	var fsp := t_fsp[ty]
	var rsp := t_rsp[ty]
	var alive := u_alive[u]
	var files := maxi(mini(files_of(u), alive), 1)
	var c := FM.cos_a(u_face[u])
	var s := FM.sin_a(u_face[u])
	var rx := x - u_ax[u]
	var ry := y - u_ay[u]
	var back := -((rx * c + ry * s) / FM.TRIG_ONE)
	var lat := (ry * c - rx * s) / FM.TRIG_ONE
	if back < -2 * rsp:
		return -1
	var full := alive / files
	var rank0 := clampi((back + rsp / 2) / rsp if back >= 0 else 0, 0, full)
	var base := u_slot_base[u]
	var best := -1
	var best_d := 0
	for rank in range(maxi(rank0 - 1, 0), mini(rank0 + 1, full) + 1):
		var k := files
		if rank == full:
			k = alive - full * files
		if k <= 0:
			continue
		var num := 2 * lat + (k - 1) * fsp + fsp
		var file0 := clampi(num / (2 * fsp) if num >= 0 else 0, 0, k - 1)
		for file in range(maxi(file0 - 1, 0), mini(file0 + 1, k - 1) + 1):
			var slot := rank * files + file
			if slot >= alive:
				continue
			var i := slot_soldier[base + slot]
			var dx := pos_x[i] - x
			var dy := pos_y[i] - y
			var d2 := dx * dx + dy * dy
			if best < 0 or d2 < best_d:
				best = i
				best_d = d2
	return best


func _nearest_in_unit(u: int, x: int, y: int) -> int:
	var base := u_slot_base[u]
	var best := -1
	var best_d := 0
	for s in u_alive[u]:
		var i := slot_soldier[base + s]
		var dx := pos_x[i] - x
		var dy := pos_y[i] - y
		var d2 := dx * dx + dy * dy
		if best < 0 or d2 < best_d:
			best = i
			best_d = d2
	return best


func _missile_hit(p: int, d: int) -> void:
	var ty := pr_ty[p]
	var ud := unit_of[d]
	var td := u_otype[ud]
	if _rand() % 100 >= MISSILE_HIT:
		return
	var from_def := FM.atan2_a(pr_sy[p] - pr_y[p], pr_sx[p] - pr_x[p])
	var sd := state[d]
	var frontal := sd != S_ROUTING and sd != S_DOWN \
		and absi(FM.angle_diff(facing[d], from_def)) <= FRONT_ARC
	if frontal and _rand() % 100 < t_mshield[td] * (100 - t_m_spen[ty]) / 100:
		return  # (a javelin's weight drives through part of the shields: m_spen)
	stat_missile_hits += 1
	var k := pr_ak[p]
	var ap := clampi(t_m_ap[ty] + t_k_ap[k], 0, 100) if k >= 0 else t_m_ap[ty]
	var arm := t_armour[td] * (100 - ap) / 100
	var md := t_m_dmg[ty] * t_k_dmg[k] / 100 if k >= 0 else t_m_dmg[ty]
	var dmg := maxi(md - arm, 3) * t_m_vuln[td] / 100 * (85 + _rand() % 31) / 100
	if u_state[ud] == U_READY:
		var unit_rel := absi(FM.angle_diff(u_face[ud], from_def))
		u_morale[ud] -= MORALE_MISSILE_HIT if unit_rel <= FRONT_ARC else MORALE_MISSILE_FLANK
		u_hit_t[ud] = tick
		if k >= 0:
			_kind_shock(ud, k)
	var h := hp[d] - dmg
	# A horse struck may simply go down, rider and all.
	if h <= 0 or (t_m_down[td] > 0 and _rand() % 100 < t_m_down[td]):
		stat_kills[3] += 1
		stat_kside[u_side[ud] * 5 + 3] += 1
		_credit(pr_unit[p], ud)
		_remove(d, GONE_KILLED)
	else:
		hp[d] = h


# ------------------------------------------------------ ammunition kinds ---
# docs/DESIGN.md "Ammunition kinds": a unit's weapon shoots its standard
# kind (t_m_ak of what it uses now) and may carry one special kind (u_sk for
# its own weapon, eg_sk for engines), a share of the load per man (sammo) or
# per engine (e_sammo). ORDER_AMMO picks which it means to shoot (u_akind);
# a man (an engine) out of that kind shoots the other.

## The special kind of the weapon unit u uses now (its engines' while it
## works engines, else its own), -1 none.
func spec_kind(u: int) -> int:
	if u_neng[u] > 0 and u_eg[u] >= 0:
		return eg_sk[u_eg[u]]
	return u_sk[u]


## The kind unit u means to shoot (-1: no missile weapon).
func cur_kind(u: int) -> int:
	var sk := spec_kind(u)
	if sk >= 0 and u_akind[u] != 0:
		return sk
	return t_m_ak[u_type[u]]


## Range of unit u's missiles in % of its weapon's, by the kind it means to shoot.
func range_pct(u: int) -> int:
	var k := cur_kind(u)
	return t_k_range[k] if k >= 0 else 100


## Missile range of unit u (flat ground) with the kind it means to shoot.
func mrange(u: int) -> int:
	return t_m_range[u_type[u]] * range_pct(u) / 100


## Missiles (shots) of its special kind unit u has left: its men's, or its
## working engines' while it works engines.
func special_left(u: int) -> int:
	var n_s := 0
	if u_neng[u] > 0:
		for k in u_neng[u]:
			var e := u_eng0[u] + k
			if e_state[e] == E_OK:
				n_s += e_sammo[e]
		return n_s
	if u_sk[u] < 0:
		return 0
	var base := u_slot_base[u]
	for s in u_alive[u]:
		n_s += sammo[slot_soldier[base + s]]
	return n_s


## A missile of kind k struck unit ud: its fear, and its fire sets the men
## burning (their morale drains while it lasts). `fear`: false when the
## caller added the kind's fear already (artillery fright).
func _kind_shock(ud: int, k: int, fear: bool = true) -> void:
	if fear and t_k_fear[k] > 0:
		u_morale[ud] -= t_k_fear[k]
	if t_k_fire[k] > 0:
		if u_burn[ud] == 0:
			stat_unit_burn += 1
		u_burn[ud] = BURN_UNIT


## A fire missile (projectile p) lands: each wooden thing within reach of
## where it fell catches fire with its kind's chance: a shut or open gate
## (its face), an engine (a tower's: anywhere on the tower), ladders on the
## ground or carried, a ram, a wagon. Index order; the RNG is drawn only
## for things in reach.
func _ignite(p: int) -> void:
	var k := pr_ak[p]
	var ch := t_k_fire[k]
	var x := pr_x[p]
	var y := pr_y[p]
	for g in n_gates:
		if g_state[g] == GATE_BROKEN:
			continue
		var f := gate_frame(g, x, y)
		if absi(f.x) > g_hw[g] * M + 1536 or absi(f.y) > wall_t / 2 + 3 * M:
			continue
		if _rand() % 100 < ch:
			if g_burn[g] == 0:
				stat_ignite += 1
			g_burn[g] = FIRE_TICKS
	for e in n_eng:
		if e_state[e] == E_WRECKED:
			continue
		var r := FIRE_R
		var eu := e_unit[e]
		if eu >= 0 and eu < n_units and t_fixed[u_type[eu]] != 0:
			r = u_trad[eu] + M
		if absi(e_x[e] - x) > r or absi(e_y[e] - y) > r:
			continue
		if _rand() % 100 < ch:
			if e_burn[e] == 0:
				stat_ignite += 1
			e_burn[e] = FIRE_TICKS
	for q in n_eq:
		if q_state[q] == Q_WRECKED or (q_state[q] == Q_PLANTED and EQ_EXPOSED[q_kind[q]] == 0):
			continue  # (planted ladders stand against the wall, out of reach)
		if EQ_BURN[q_kind[q]] == 0 or q_state[q] == Q_STOWED:
			continue  # (iron, earth; not on the field)
		if EQ_FW[q_kind[q]] != 0:
			# A field work: anywhere along it (within FIRE_R of its middle line).
			var fe := fw_extent(q)
			if absi(q_x[q] - x) > fe.x + FIRE_R or absi(q_y[q] - y) > fe.y + FIRE_R \
					or not _fw_near(q, x, y, FIRE_R):
				continue
		else:
			var qc := eq_centre(q)
			if absi(qc.x - x) > FIRE_R or absi(qc.y - y) > FIRE_R:
				continue
		if _rand() % 100 < ch:
			if q_burn[q] == 0:
				stat_ignite += 1
			q_burn[q] = FIRE_TICKS


## Full hit points of piece q (fire chips a share of them).
func _eq_hp0(q: int) -> int:
	if q_kind[q] == EQ_WAGON:
		return _wagon_hp0(q)
	return EQ_HP[q_kind[q]]


## The middle of piece q: where it lies or its carriers' anchor; planted,
## EQ_DEPTH2 out from its foot (a siege tower's body before the wall).
func eq_centre(q: int) -> Vector2i:
	var k := q_kind[q]
	if q_state[q] != Q_PLANTED or EQ_DEPTH2[k] == 0 or q_seg[q] < 0:
		return Vector2i(q_x[q], q_y[q])
	var dir := ws_dir[q_seg[q]]
	return Vector2i(q_x[q] + FM.cos_a(dir) * EQ_DEPTH2[k] / FM.TRIG_ONE,
		q_y[q] + FM.sin_a(dir) * EQ_DEPTH2[k] / FM.TRIG_ONE)


## Piece q is destroyed (burnt, smashed): put down by whoever carried it.
func _eq_wreck(q: int) -> void:
	var u := q_unit[q]
	if u >= 0 and u_carry[u] == q:
		u_carry[u] = -1
	if q_state[q] == Q_PLANTED:
		# A planted siege tower falls: men still crossing it come back down.
		for o in n_units:
			if u_lq[o] == q and u_stair[o] == ST_LADDER and u_state[o] == U_READY:
				_ladder_down(o)
	if q_kind[q] == EQ_TOWER:
		stat_stw_wrecked += 1
	q_unit[q] = -1
	q_state[q] = Q_WRECKED
	q_hp[q] = 0
	q_burn[q] = 0
	_wagon_lost(q)


## Burning things, once a tick: each loses FIRE_CHIP per mille of its full
## hit points every second until the fire is out (FIRE_TICKS after the last
## fire missile on it) or it is gone: a gate breaks, an engine is wrecked
## (a tower falls with it), a piece of equipment is wrecked.
func _update_fire() -> void:
	var sec := tick % TICKS_PER_SECOND == 0
	for g in n_gates:
		if g_burn[g] <= 0:
			continue
		g_burn[g] -= 1
		if g_state[g] == GATE_BROKEN:
			g_burn[g] = 0
			continue
		if sec:
			var chip := maxi(g_hp0[g] * FIRE_CHIP / 1000, 100)
			g_hp[g] -= chip
			g_hit_t[g] = tick
			stat_fire_dmg += chip / 100
			if g_hp[g] <= 0:
				_break_gate(g)
				g_burn[g] = 0
				stat_burnt += 1
	for e in n_eng:
		if e_burn[e] <= 0:
			continue
		e_burn[e] -= 1
		if e_state[e] == E_WRECKED:
			e_burn[e] = 0
			continue
		if sec:
			var chip := maxi(t_e_hp[eg_type[e_grp[e]]] * FIRE_CHIP / 1000, 1)
			e_hp[e] -= chip
			stat_fire_dmg += chip
			if e_hp[e] <= 0:
				if e_state[e] == E_OK:
					_wreck(e)
				else:
					e_state[e] = E_WRECKED
					e_hp[e] = 0
				e_burn[e] = 0
				stat_burnt += 1
	for q in n_eq:
		if q_burn[q] <= 0:
			continue
		q_burn[q] -= 1
		if q_state[q] == Q_WRECKED:
			q_burn[q] = 0
			continue
		if sec:
			var chip := maxi(_eq_hp0(q) * FIRE_CHIP / 1000, 1)
			q_hp[q] -= chip
			stat_fire_dmg += chip
			if q_hp[q] <= 0:
				_eq_wreck(q)
				stat_burnt += 1


## Missile unit u (told to shoot at gate g) can reach its face from where
## it stands with the kind it means to shoot.
func _gate_shot_ok(u: int, g: int) -> bool:
	if g < 0 or g >= n_gates or g_state[g] != GATE_CLOSED or u_ammo[u] <= 0:
		return false
	var gf := gate_face(g)
	return FM.approx_len(gf.x - u_cx[u], gf.y - u_cy[u]) <= mrange(u)


## Missile units told to shoot at a gate (gtarget, standing): volleys at its
## face as at a unit (no lead, the same rate and scatter). Only fire
## missiles do anything to a gate (they may set it alight).
func _gate_volleys() -> void:
	for u in n_units:
		var g := u_gtarget[u]
		if g < 0 or u_cls[u] != UT.CLS_MISSILE or u_order[u] != O_NONE or u_state[u] != U_READY:
			continue
		if u_moved[u] != 0 or u_ftarget[u] >= 0 or not _gate_shot_ok(u, g):
			continue
		var ty := u_type[u]
		var alive := u_alive[u]
		var acc := u_fire_acc[u] + alive
		var ks := u_sk[u]
		var kstd := t_m_ak[ty]
		var pref := ks >= 0 and u_akind[u] != 0
		var reload := t_m_reload[ty] * t_k_rate[ks if pref else kstd] / 100 if kstd >= 0 else t_m_reload[ty]
		var tries := 0
		while acc >= reload and tries < alive:
			acc -= reload
			tries += 1
			var ptr := u_fire_ptr[u] % alive
			u_fire_ptr[u] = ptr + 1
			var i := slot_soldier[u_slot_base[u] + ptr]
			if state[i] != S_FORMED or ammo[i] <= 0:
				continue
			_fire_gate(i, u, g, ty, _shot_kind(i, ks, kstd, pref))
		u_fire_acc[u] = mini(acc, reload)


## Soldier i of missile unit u shoots at gate g's face (kind k).
func _fire_gate(i: int, u: int, g: int, ty: int, k: int) -> void:
	if pr_free < 0:
		return
	var gf := gate_face(g)
	var sx := pos_x[i]
	var sy := pos_y[i]
	var dx := gf.x - sx
	var dy := gf.y - sy
	var dist := FM.approx_len(dx, dy)
	var rp := t_k_range[k] if k >= 0 else 100
	if dist <= 0 or not _shot_ok(sx, sy, gf.x, gf.y, dist, ty, 0, LOF_SKIP, 0, rp):
		return
	var p := pr_free
	pr_free = pr_next[p]
	pr_count += 1
	ammo[i] -= 1
	u_ammo[u] -= 1
	if k >= 0 and t_k_base[k] >= 0:
		sammo[i] -= 1
		stat_ak_shots += 1
	stat_shots += 1
	facing[i] = FM.atan2_a(dy, dx)
	var spread := t_m_spread0[ty] + dist * t_m_spread[ty] / 1000
	var lat := (_rand() % (spread + 1) + _rand() % (spread + 1)) - spread
	var lon := ((_rand() % (spread + 1) + _rand() % (spread + 1)) - spread) * 3 / 2
	var ux := dx * FM.TRIG_ONE / dist
	var uy := dy * FM.TRIG_ONE / dist
	var flight := clampi(dist / t_m_speed[ty] + 3, 3, PR_BUCKETS - 1)
	pr_sx[p] = sx
	pr_sy[p] = sy
	pr_x[p] = clampi(gf.x + ((ux * lon - uy * lat) / FM.TRIG_ONE), 0, field_w)
	pr_y[p] = clampi(gf.y + ((uy * lon + ux * lat) / FM.TRIG_ONE), 0, field_h)
	pr_t0[p] = tick
	pr_t1[p] = tick + flight
	pr_unit[p] = u
	pr_ty[p] = ty
	pr_tu[p] = -2 - g
	pr_ak[p] = k
	var b := (tick + flight) % PR_BUCKETS
	pr_next[p] = pr_bucket[b]
	pr_bucket[b] = p


# ---------------------------------------------------------------- resupply ---
# docs/DESIGN.md "Resupply: foraging and the ammunition wagon".

## The ammunition wagon unit u may refill from: within WAGON_R of its
## bounding box, not wrecked, standing (anyone's: crew gone, left) or
## pulled by a unit of u's side; the nearest, ties to the lower index. -1 none.
func _wagon_for(u: int) -> int:
	var best := -1
	var bd := 0
	for q in n_eq:
		if q_kind[q] != EQ_WAGON or q_state[q] == Q_WRECKED:
			continue
		if q_state[q] == Q_CARRIED and (q_unit[q] < 0 or u_side[q_unit[q]] != u_side[u]):
			continue
		var gx := maxi(maxi(u_minx[u] - q_x[q], q_x[q] - u_maxx[u]), 0)
		var gy := maxi(maxi(u_miny[u] - q_y[q], q_y[q] - u_maxy[u]), 0)
		var d := maxi(gx, gy)
		if d <= WAGON_R and (best < 0 or d < bd):
			best = q
			bd = d
	return best


## (For the AI and the view: _wagon_for as a public call.)
func wagon_for(u: int) -> int:
	return _wagon_for(u)


## Shots / missiles of kind k left in wagon q.
func wagon_stock(q: int, k: int) -> int:
	if q < 0 or q >= n_eq or k < 0:
		return 0
	return q_stock[q * UT.AMMO.size() + k]


## Why unit u cannot forage ("" if it can): missile troops (not working
## engines, not carrying, not on a wall), ready, standing in woods.
static func forage_refusal(sim, u: int) -> String:
	if sim.u_state[u] != U_READY:
		return "Not now"
	if sim.u_cls[u] != UT.CLS_MISSILE or UT.stat(sim.u_type[u], "m_ammo") <= 0:
		return "Only archers and javelinmen make their own missiles"
	if sim.u_carry[u] >= 0:
		return "Carrying something: put it down first (Drop)"
	if sim.u_wall[u] > 0:
		return "Not on a wall"
	if sim.veg_d(sim.u_ax[u], sim.u_ay[u]) <= 0:
		return "Only in woods"
	return ""


## Missile p (an arrow or javelin) lands by a wagon's team: one horse is
## struck HORSE_HIT % of the time (the missile is spent on it). True if so.
func _horse_hit(p: int) -> bool:
	var x := pr_x[p]
	var y := pr_y[p]
	for q in n_eq:
		if q_kind[q] != EQ_WAGON or q_hn[q] <= 0 or q_state[q] == Q_WRECKED:
			continue
		var hx := q_x[q]
		var hy := q_y[q]
		var c := q_unit[q]
		if q_state[q] == Q_CARRIED and c >= 0:
			# The team is in front of the wagon (the crew's facing).
			hx += FM.cos_a(u_face[c]) * 3 * M / FM.TRIG_ONE
			hy += FM.sin_a(u_face[c]) * 3 * M / FM.TRIG_ONE
		if absi(hx - x) > HORSE_R or absi(hy - y) > HORSE_R:
			continue
		if _rand() % 100 >= HORSE_HIT:
			return false
		var k := pr_ak[p]
		var ty := pr_ty[p]
		var md := t_m_dmg[ty] * t_k_dmg[k] / 100 if k >= 0 else t_m_dmg[ty]
		_horse_wound(q, md * 120 / 100)  # (a big target: as a horse's m_vuln)
		return true
	return false


## Wagon q's lead horse takes dmg; at 0 it is down (the next one leads).
func _horse_wound(q: int, dmg: int) -> void:
	q_hhp[q] -= dmg
	if q_hhp[q] <= 0:
		q_hn[q] -= 1
		wag_h -= 1
		stat_horses_down += 1
		q_hhp[q] = UT.wagon_stat(q_tier[q], "horse_hp") if q_hn[q] > 0 else 0


## Once a tick: units foraging make missiles, missile units settled at a
## wagon draw from it.
func _update_supply() -> void:
	for u in n_units:
		if u_forage[u] != 0:
			if u_state[u] != U_READY:
				u_forage[u] = 0
			else:
				_forage_step(u)
		elif u_rprog[u] == REFILL_FULL and u_cls[u] == UT.CLS_MISSILE and u_state[u] == U_READY:
			_wagon_refill(u)


## Missile unit u, settled at a wagon: missiles come up one at a time to
## the man next in turn short of a full load (a unit's whole load in
## WAGON_QUIVER ticks): its special kind first, up to its share, then the
## standard kind, then the special kind again; until every man is full or
## the wagon has nothing for them (the order ends).
func _wagon_refill(u: int) -> void:
	var q := _wagon_for(u)
	var ty := u_type[u]
	var full := t_m_ammo[ty]
	var kstd := t_m_ak[ty]
	var alive := u_alive[u]
	if q < 0 or kstd < 0 or full <= 0 or alive <= 0:
		u_refill[u] = 0
		return
	var nak := UT.AMMO.size()
	var ks := u_sk[u]
	var sfull := full * t_k_share[ks] / 100 if ks >= 0 else 0
	u_racc[u] += alive * full
	var give := u_racc[u] / WAGON_QUIVER
	u_racc[u] -= give * WAGON_QUIVER
	var idle := 0
	var base := u_slot_base[u]
	while give > 0 and idle < alive:
		var ptr := u_rptr[u] % alive
		u_rptr[u] = ptr + 1
		var i := slot_soldier[base + ptr]
		var k := -1
		if ammo[i] < full:
			if ks >= 0 and sammo[i] < sfull and q_stock[q * nak + ks] > 0:
				k = ks
			elif q_stock[q * nak + kstd] > 0:
				k = kstd
			elif ks >= 0 and q_stock[q * nak + ks] > 0:
				k = ks
		if k < 0:
			idle += 1
			continue
		idle = 0
		give -= 1
		q_stock[q * nak + k] -= 1
		ammo[i] += 1
		u_ammo[u] += 1
		if k == ks:
			sammo[i] += 1
		stat_refill_shots += 1
	if idle >= alive:
		u_refill[u] = 0  # every man full, or nothing more for them


## Missile unit u foraging in woods: its men make missiles of the standard
## kind for their own quivers (the whole unit's in FORAGE_QUIVER ticks).
## It stops when hit, in melee, moved or out of the woods, or once full.
func _forage_step(u: int) -> void:
	if u_fighting[u] > 0 or tick - u_hit_t[u] <= 1 or tick - u_charged_t[u] <= 1 or u_order[u] != O_NONE \
			or u_moved[u] > 0 or u_neng[u] > 0 or veg_d(u_ax[u], u_ay[u]) <= 0:
		u_forage[u] = 0
		return
	var ty := u_type[u]
	var full := t_m_ammo[ty]
	var alive := u_alive[u]
	if full <= 0 or alive <= 0:
		u_forage[u] = 0
		return
	u_racc[u] += alive * full
	var give := u_racc[u] / FORAGE_QUIVER
	u_racc[u] -= give * FORAGE_QUIVER
	var idle := 0
	var base := u_slot_base[u]
	while give > 0 and idle < alive:
		var ptr := u_rptr[u] % alive
		u_rptr[u] = ptr + 1
		var i := slot_soldier[base + ptr]
		if ammo[i] >= full:
			idle += 1
			continue
		idle = 0
		give -= 1
		ammo[i] += 1
		u_ammo[u] += 1
		stat_forage += 1
	if idle >= alive:
		u_forage[u] = 0  # every quiver full


# ------------------------------------------------------------- artillery ---

## Battery fire choice, every FIRE_THINK ticks. An attack order shoots that
## unit whatever is in the way (the player's call). Fire at will keeps its
## target while it stays good, else picks the best one: in range and not
## inside the minimum range, preferring targets already in the arc, big and
## standing still, and refusing any shot that would hit friends (a bolt's
## line crossing a friendly unit; a stone landing near friends).
func _art_think(u: int) -> void:
	var ty := u_type[u]
	var order := u_order[u]
	var ft := -1
	if u_ammo[u] > 0 and order != O_MOVE and order != O_WITHDRAW and u_rprog[u] == 0:
		var rng := mrange(u)
		var mn := t_m_min[ty]
		if order == O_ATTACK and u_gtarget[u] >= 0:
			pass  # shooting at a gate (_update_artillery)
		elif order == O_ATTACK:
			var t := u_target[u]
			if t >= 0 and u_state[t] < U_DESTROYED and _art_in_range(u, t, mn, rng):
				ft = t
				if not lof_units(u, t):
					stat_lof_blocked += 1
					ft = -1  # a crest in the way: the bolts would bury themselves
		elif u_fire[u] != 0:
			var cur := u_ftarget[u]
			if cur >= 0 and u_state[cur] < U_DESTROYED and u_side[cur] != u_side[u] \
					and _art_in_range(u, cur, mn, rng) and art_safe(u, cur):
				ft = cur
			else:
				var best_score := 0
				for o in n_units:
					if u_side[o] == u_side[u] or u_state[o] >= U_DESTROYED or u_alive[o] <= 0:
						continue
					if not _art_in_range(u, o, mn, rng):
						continue
					var score := 1000 + u_alive[o] * 4 - _unit_dist(u, o) / M
					if u_moved[o] == 0:
						score += 200
					var bear := FM.atan2_a(u_cy[o] - u_cy[u], u_cx[o] - u_cx[u])
					if absi(FM.angle_diff(u_face[u], bear)) <= t_arc[ty]:
						score += 400
					# The (dearer) safety and line-of-fire test only for a
					# target that would be chosen.
					if (ft < 0 or score > best_score) and art_safe(u, o):
						ft = o
						best_score = score
	u_ftarget[u] = ft


func _art_in_range(u: int, t: int, mn: int, rng: int) -> bool:
	var d := FM.approx_len(u_cx[t] - u_cx[u], u_cy[t] - u_cy[u])
	if ter_on != 0 or obs_on != 0:
		rng = range_vs(u, t)
	return d >= mn and _unit_dist(u, t) <= rng


## True when battery u can shoot at t without (probably) hitting friends:
## bolts need a clear line (no friends, no crest), stones a target with no
## friends close to it. Also used by the battle AI.
func art_safe(u: int, t: int) -> bool:
	if t_m_kind[u_type[u]] == 1:
		# (A tower's engine shoots over its friends on the walls and below.)
		return (t_fixed[u_type[u]] != 0 or _clear_line(u, t)) and lof_units(u, t)
	var side := u_side[u]
	var margin := 15 * M
	for o in n_units:
		if u_side[o] != side or u_state[o] >= U_DESTROYED or o == u:
			continue
		if u_minx[o] - margin > u_maxx[t] or u_maxx[o] + margin < u_minx[t] \
				or u_miny[o] - margin > u_maxy[t] or u_maxy[o] + margin < u_miny[t]:
			continue
		return false
	return true


## Batteries: engines roll with the packed battery, traverse within the arc
## toward the target once set up, are worked by the crew standing at them,
## are wrecked by enemy soldiers next to them, and shoot when loaded.
func _update_artillery() -> void:
	for u in n_units:
		var ne := u_neng[u]
		if ne == 0:
			continue
		var e0 := u_eng0[u]
		var ty := u_type[u]
		if t_fixed[ty] != 0 and u_state[u] == U_READY and u_alive[u] > 0 and e_state[e0] != E_OK:
			_tower_fall(u)
		if u_state[u] != U_READY or u_alive[u] <= 0:
			# Broken or gone: the engines are left where they stand.
			for k in ne:
				var e := e0 + k
				if e_state[e] == E_OK:
					e_state[e] = E_ABANDONED
					e_crew[e] = 0
					u_ammo[u] -= e_ammo[e]
					stat_abandoned += 1
					e_unit[e] = eg_u0[e_grp[e]]
			continue
		var full := t_deploy[ty]
		var packed := u_depl[u] == 0
		var face := u_face[u]
		var c := FM.cos_a(face)
		var sn := FM.sin_a(face)
		var esp := t_fsp[ty]
		var spd := t_walk[ty] * 2
		var ft := u_ftarget[u]
		# Aim: the unit fired at, or the face of the gate ordered at.
		var gt := u_gtarget[u] if u_order[u] == O_ATTACK else -1
		if gt >= 0 and (gt >= n_gates or g_state[gt] != GATE_CLOSED):
			gt = -1
		var aim := gt >= 0 or ft >= 0
		var tx := 0
		var tyy := 0
		if gt >= 0:
			var gf := gate_face(gt)
			tx = gf.x
			tyy = gf.y
		elif ft >= 0:
			tx = u_cx[ft]
			tyy = u_cy[ft]
		var moving := 0
		var changed := false
		for k in ne:
			var e := e0 + k
			e_crew[e] = 0
			if e_state[e] != E_OK:
				continue
			if packed:
				var lat := ((2 * k - (ne - 1)) * esp) / 2
				var sx := u_ax[u] + ((-lat * sn) / FM.TRIG_ONE)
				var sy := u_ay[u] + ((lat * c) / FM.TRIG_ONE)
				var dx := sx - e_x[e]
				var dy := sy - e_y[e]
				if dx != 0 or dy != 0:
					var d := FM.approx_len(dx, dy)
					if d <= spd:
						e_x[e] = sx
						e_y[e] = sy
					else:
						e_x[e] += dx * spd / d
						e_y[e] += dy * spd / d
						moving += 1
					changed = true
				if e_face[e] != face:
					e_face[e] = face
					changed = true
			elif u_rprog[u] == 0:
				# Traverse toward the target, within the arc of the battery.
				var want := face
				if aim:
					var bear := FM.atan2_a(tyy - e_y[e], tx - e_x[e])
					var off := clampi(FM.angle_diff(face, bear), -t_arc[ty], t_arc[ty])
					want = (face + off) & FM.ANGLE_MASK
				var diff := FM.angle_diff(e_face[e], want)
				if diff != 0:
					var trav := t_traverse[ty]
					e_face[e] = want if absi(diff) <= trav else (e_face[e] + (trav if diff > 0 else -trav)) & FM.ANGLE_MASK
					changed = true
		u_emove[u] = moving
		if changed:
			_art_offsets(u)
		# Manning: crew standing (not fighting) at their engine work it.
		var w := _working_engines(u)
		var nw := w.size()
		var base := u_slot_base[u]
		var cap := _crew_cap(u)
		for slot in u_alive[u]:
			var i := slot_soldier[base + slot]
			if state[i] != S_FORMED or slot / nw >= cap:
				continue
			var e := w[slot % nw]
			if e_state[e] != E_OK:
				continue
			var dx := pos_x[i] - e_x[e]
			var dy := pos_y[i] - e_y[e]
			if dx * dx + dy * dy <= MAN_DIST * MAN_DIST:
				e_crew[e] += 1
		# Enemy soldiers next to an engine smash it.
		if u_contact[u] != 0:
			var head: PackedInt32Array = grid_head1 if u_side[u] == 0 else grid_head0
			for k in ne:
				var e := e0 + k
				if e_state[e] != E_OK:
					continue
				var near := _count_near(e_x[e], e_y[e], ENGINE_NEAR, head, 6)
				if near > 0:
					e_hp[e] -= near * ENGINE_WRECK
					if e_hp[e] <= 0:
						_wreck(e)
		if u_rprog[u] == REFILL_FULL:
			_refill_work(u)
			continue
		# Shoot: set up, standing, a target, loaded, crewed and on the bearing.
		if u_depl[u] < full or not aim or u_moved[u] != 0 or u_rprog[u] > 0:
			continue
		var need0 := t_m_reload[ty] * t_crew[ty]
		for k in ne:
			var e := e0 + k
			if e_state[e] != E_OK or e_ammo[e] <= 0:
				continue
			if e_crew[e] < t_crew_min[ty]:
				continue  # silent: too few hands
			var ek := _eng_kind(e, u)
			var need := need0 * t_k_rate[ek] / 100 if ek >= 0 else need0
			if e_reload[e] < need:
				e_reload[e] = mini(e_reload[e] + e_crew[e], need)
			if e_reload[e] < need:
				continue
			var bear := FM.atan2_a(tyy - e_y[e], tx - e_x[e])
			if absi(FM.angle_diff(e_face[e], bear)) > ALIGN:
				continue
			var fired := _art_fire_gate(e, u, gt, ty) if gt >= 0 else _art_fire(e, u, ft, ty)
			if fired:
				e_reload[e] = 0


## A refilling battery: each working engine short of its full load gains
## the work of the crew standing at it (none below the minimum crew); a
## shot comes up from the reserve every m_refill x full crew. When nothing
## more can come up (engines full or the reserve empty) the order ends.
func _refill_work(u: int) -> void:
	var ty := u_type[u]
	var need := t_m_refill[ty] * t_crew[ty]
	var e0 := u_eng0[u]
	var more := false
	# An ammunition wagon near (docs/DESIGN.md "The ammunition wagon"): shots
	# of the engines' special kind (up to its share) and, once the baggage
	# is empty, of the standard kind come from its stock; with the engines
	# full it tops up the baggage too.
	var w := _wagon_for(u) if sg_on != 0 else -1
	var nak := UT.AMMO.size()
	var kstd := t_m_ak[ty]
	var g := u_eg[u]
	var ks := eg_sk[g] if g >= 0 and g < n_eg else -1
	var sfull := t_m_ammo[ty] * t_k_share[ks] / 100 if ks >= 0 else 0
	for k in u_neng[u]:
		var e := e0 + k
		if e_state[e] != E_OK or e_ammo[e] >= t_m_ammo[ty]:
			continue
		var wsp := w >= 0 and ks >= 0 and e_sammo[e] < sfull and q_stock[w * nak + ks] > 0
		var wst := w >= 0 and kstd >= 0 and q_stock[w * nak + kstd] > 0
		if u_reserve[u] <= 0 and not wsp and not wst:
			continue
		more = true
		if e_crew[e] < t_crew_min[ty]:
			continue
		e_rwork[e] += e_crew[e]
		if e_rwork[e] >= need:
			e_rwork[e] -= need
			e_ammo[e] += 1
			u_ammo[u] += 1
			if wsp:
				q_stock[w * nak + ks] -= 1
				e_sammo[e] += 1
				stat_refill_shots += 1
			elif u_reserve[u] > 0:
				u_reserve[u] -= 1
			else:
				q_stock[w * nak + kstd] -= 1
				stat_refill_shots += 1
			stat_refilled += 1
	if not more and w >= 0 and kstd >= 0 and u_reserve[u] < u_neng[u] * t_m_reserve[ty] \
			and q_stock[w * nak + kstd] > 0:
		more = true
		u_racc[u] += 1
		if u_racc[u] >= 10:
			u_racc[u] = 0
			u_reserve[u] += 1
			q_stock[w * nak + kstd] -= 1
			stat_refill_shots += 1
	if not more:
		u_refill[u] = 0


# ------------------------------------------------- engines as equipment ---
# docs/DESIGN.md "Artillery": a battery's engines are a group (eg_*) that
# its unit works. ORDER_DROP leaves them where they stand, abandoned and
# neutral (hit points, shots, set-up state and the baggage's shots kept),
# and the men fight on as plain foot (a battery's crews with light
# infantry's pace and formation, their own arms). ORDER_PICKUP with
# "engines" sends any foot unit of either side to an abandoned group; it
# works it as a battery of that kind (the engine type's range, reload,
# crew, set-up, traverse, refill; men beyond the crew stand behind), and
# its own missiles wait until it drops them. A battery that breaks or dies
# leaves its engines abandoned. Tower engines are fixed (never dropped or
# taken up).

## Engine group g is left on the field: no ready unit works it. (A battery
## that broke and rallied stands by its abandoned engines as before, still
## theirs: Drop, then a pick-up, mans them again.)
func engines_free(g: int) -> bool:
	var op := eg_op[g]
	return op < 0 or u_state[op] != U_READY or u_eg[op] != g


## Where engine group g stands: the middle of its engines (a battery's
## anchor, the front centre of its line of engines).
static func engines_at(sim, g: int) -> Vector2i:
	var ne: int = sim.eg_ne[g]
	var e0: int = sim.eg_e0[g]
	var sx := 0
	var sy := 0
	for k in ne:
		sx += sim.e_x[e0 + k]
		sy += sim.e_y[e0 + k]
	return Vector2i(sx / maxi(ne, 1), sy / maxi(ne, 1))


## Why unit u cannot take up engine group g ("" if it can): foot of either
## side (not horses, not a unit already working engines or carrying siege
## gear, not on a wall), the engines left on the field and not all wrecked,
## not a tower's. Shared with the view.
static func engine_refusal(sim, u: int, g: int) -> String:
	if g < 0 or g >= sim.n_eg:
		return "Nothing to pick up there"
	if UT.stat(sim.eg_type[g], "fixed") != 0:
		return "Tower engines stay on their towers"
	if not sim.engines_free(g):
		if sim.eg_op[g] == u:
			return "It works these engines already"
		if sim.u_side[sim.eg_op[g]] == sim.u_side[u]:
			return "Another unit works these engines"
		return "The enemy works these engines: drive the crews off first"
	var whole := false
	for k in sim.eg_ne[g]:
		if sim.e_state[sim.eg_e0[g] + k] != E_WRECKED:
			whole = true
	if not whole:
		return "The engines are wrecked"
	var c: int = sim.u_cls[u]
	if c == UT.CLS_CAV:
		return "Cavalry cannot work engines"
	if c == UT.CLS_ART:
		return "Already working engines: drop them first (Drop)"
	if sim.u_wall[u] > 0 or sim.u_stair[u] != 0:
		return "Down off the wall first"
	if sim.u_carry[u] >= 0:
		return "Carrying siege equipment: put it down first (Drop)"
	var at := engines_at(sim, g)
	var ra: int = sim.reach_at(sim.u_ax[u], sim.u_ay[u])
	var rg: int = sim.reach_at(at.x, at.y)
	if ra >= 0 and rg >= 0 and ra != rg:
		return "No way to them from here"
	return ""


## (For the battle AI, which does not load this script: engine_refusal is
## "" / engines_at, as instance calls.)
func may_take_engines(u: int, g: int) -> bool:
	return engine_refusal(self, u, g) == ""


func engines_xy(g: int) -> Vector2i:
	return engines_at(self, g)


## Unit u (going to take up engine group g) is within PICK_R of it: it takes
## them up there; a group taken or wrecked meanwhile is forgotten.
func _pick_engines(u: int, g: int) -> void:
	if g >= n_eg or u_state[u] != U_READY or engine_refusal(self, u, g) != "":
		u_pick[u] = -1
		return
	var at := engines_at(self, g)
	if FM.approx_len(u_ax[u] - at.x, u_ay[u] - at.y) > PICK_R:
		return
	var prev := eg_op[g]
	if prev >= 0 and prev != u and u_eg[prev] == g:
		_to_plain(prev)  # the crew that broke or died: off its engines
	_to_engines(u, g)
	u_pick[u] = -1
	stat_epick += 1


## Unit u works engine group g from now on: a battery of the engines' type
## (u_type), its men's own type kept (u_otype), its own missiles put aside.
func _to_engines(u: int, g: int) -> void:
	var ty := eg_type[g]
	var at := engines_at(self, g)
	u_oammo[u] = u_ammo[u]
	u_type[u] = ty
	u_cls[u] = t_cls[ty]
	u_eg[u] = g
	u_eng0[u] = eg_e0[g]
	u_neng[u] = eg_ne[g]
	u_files[u] = eg_ne[g]
	u_ax[u] = at.x
	u_ay[u] = at.y
	u_face[u] = eg_face[g]
	u_dface[u] = eg_face[g]
	u_dx[u] = at.x
	u_dy[u] = at.y
	u_order[u] = O_NONE
	u_target[u] = -1
	u_ftarget[u] = -1
	u_gtarget[u] = -1
	u_run[u] = 0
	u_skirm[u] = 0
	u_fire[u] = 1
	u_sq[u] = 0
	u_depl[u] = eg_depl[g]
	u_deploy[u] = 1
	u_refill[u] = 0
	u_rprog[u] = 0
	u_emove[u] = 0
	u_reserve[u] = eg_res[g]
	u_fire_acc[u] = 0
	u_formed[u] = 0
	u_braced[u] = 0
	u_ammo[u] = 0
	u_akind[u] = 0
	for k in eg_ne[g]:
		var e := eg_e0[g] + k
		if e_state[e] == E_ABANDONED:
			e_state[e] = E_OK
		e_crew[e] = 0
		if e_state[e] == E_OK:
			e_unit[e] = u
			u_ammo[u] += e_ammo[e]
	eg_op[g] = u
	eg_side[g] = u_side[u]
	if obs_on != 0:
		u_pn[u] = 0
	u_dirty[u] = 1
	u_settled[u] = 0


## Unit u stops working its engines (they are left where they stand,
## abandoned) and fights on as plain men: its own type, a battery's crews
## at light infantry's pace and formation; its own missiles back.
func _to_plain(u: int) -> void:
	var g := u_eg[u]
	if g >= 0 and eg_op[g] == u:
		_release(g, u)
	u_eg[u] = -1
	var ot := u_otype[u]
	var ty := UT.LIGHT if t_cls[ot] == UT.CLS_ART else ot
	u_type[u] = ty
	u_cls[u] = t_cls[ty]
	u_eng0[u] = 0
	u_neng[u] = 0
	u_ammo[u] = u_oammo[u]
	u_oammo[u] = 0
	u_reserve[u] = 0
	u_depl[u] = 0
	u_deploy[u] = 0
	u_refill[u] = 0
	u_rprog[u] = 0
	u_emove[u] = 0
	u_fire_acc[u] = 0
	u_ftarget[u] = -1
	u_akind[u] = 0
	u_fire[u] = 1 if t_m_ammo[ty] > 0 else 0
	u_skirm[u] = t_skirm[ty] if u_wall[u] == 0 else 0
	u_files[u] = ground_files(ty, maxi(u_alive[u], 1))
	if u_state[u] == U_READY:
		u_order[u] = O_NONE
		u_dx[u] = u_ax[u]
		u_dy[u] = u_ay[u]
		u_dface[u] = u_face[u]
		u_target[u] = -1
		u_gtarget[u] = -1
		if obs_on != 0:
			u_pn[u] = 0
	u_dirty[u] = 1
	u_settled[u] = 0


## Engine group g, worked by unit u until now, is left on the field: its
## working engines abandoned (neutral), with the set-up state, facing and
## the baggage's shots they had.
func _release(g: int, u: int) -> void:
	eg_op[g] = -1
	eg_depl[g] = u_depl[u]
	eg_res[g] = u_reserve[u]
	eg_face[g] = u_face[u]
	for k in eg_ne[g]:
		var e := eg_e0[g] + k
		if e_state[e] == E_OK:
			e_state[e] = E_ABANDONED
			stat_abandoned += 1
		e_crew[e] = 0
		e_unit[e] = eg_u0[g]  # (the view draws a group by the battery it came with)


## ORDER_DROP for a unit working engines (not a tower's): it leaves them.
func _drop_engines(u: int) -> void:
	var g := u_eg[u]
	if g < 0 or u_state[u] != U_READY or t_fixed[eg_type[g]] != 0 or eg_op[g] != u:
		return
	_to_plain(u)
	stat_edrop += 1


## Enemy soldiers (in grid `head`) within r of (x, y), counting up to cap.
func _count_near(x: int, y: int, r: int, head: PackedInt32Array, cap: int) -> int:
	var cnt := 0
	var gs := GRID_SHIFT
	var r2 := r * r
	for gy in range(maxi((y - r) >> gs, 0), mini((y + r) >> gs, grid_h - 1) + 1):
		for gx in range(maxi((x - r) >> gs, 0), mini((x + r) >> gs, grid_w - 1) + 1):
			var j := head[gy * grid_w + gx]
			while j >= 0:
				var sj := state[j]
				if sj < S_ROUTING or sj == S_FIGHTING:
					var dx := pos_x[j] - x
					var dy := pos_y[j] - y
					if dx * dx + dy * dy <= r2:
						cnt += 1
						if cnt >= cap:
							return cnt
				j = grid_next[j]
	return cnt


func _wreck(e: int) -> void:
	if e_state[e] != E_OK:
		return
	var u := e_unit[e]
	e_state[e] = E_WRECKED
	e_hp[e] = 0
	e_crew[e] = 0
	u_ammo[u] -= e_ammo[e]
	stat_wrecked += 1
	u_dirty[u] = 1
	u_settled[u] = 0


## The kind engine e (worked by u) shoots next: its group's special kind
## while it has one and u means to shoot it (or has nothing else), else the
## standard kind.
func _eng_kind(e: int, u: int) -> int:
	var kstd := t_m_ak[u_type[u]]
	var g := e_grp[e]
	var ks := eg_sk[g] if g >= 0 and g < n_eg else -1
	if ks < 0 or e_sammo[e] <= 0:
		return kstd
	return ks if u_akind[u] != 0 or e_ammo[e] <= e_sammo[e] else kstd


## Engine e takes a shot of kind k from its load.
func _eng_spend(e: int, u: int, k: int) -> void:
	e_ammo[e] -= 1
	u_ammo[u] -= 1
	if k >= 0 and t_k_base[k] >= 0:
		e_sammo[e] -= 1
		stat_ak_shots += 1


## Engine e of battery u shoots at unit ft: at a random man of it (bolts lead
## him, stones do not), with scatter. Returns false if no shot was possible.
func _art_fire(e: int, u: int, ft: int, ty: int) -> bool:
	var talive := u_alive[ft]
	if talive <= 0 or pr_free < 0:
		return false
	var j := slot_soldier[u_slot_base[ft] + _rand() % talive]
	var sx := e_x[e]
	var sy := e_y[e]
	var spd := t_m_speed[ty]
	# Stones aim at the near face of the formation along the line to that
	# man (the front rank facing the battery, else the nearest edge), not at
	# the man himself: a stone landing among the rear ranks mostly flies on
	# beyond them.
	var bx := pos_x[j]
	var by := pos_y[j]
	if t_m_kind[ty] == 2:
		var nf := _near_face(ft, sx, sy, bx, by)
		bx = nf.x
		by = nf.y
	var ax := bx
	var ay := by
	var lead := t_m_lead[ty]
	if lead != 0:
		var vx := pos_x[j] - prev_x[j]
		var vy := pos_y[j] - prev_y[j]
		if t_m_kind[ty] == 2:
			# Stones lead the unit's movement, not one man's (men shuffling
			# up to fill gaps would throw a slow stone metres long).
			var v := _unit_velocity(ft)
			vx = v.x
			vy = v.y
		for k in 2:
			var fl := (FM.approx_len(ax - sx, ay - sy) / spd + 3) * lead / 100
			ax = bx + vx * fl
			ay = by + vy * fl
	var dx := ax - sx
	var dy := ay - sy
	var dist := FM.approx_len(dx, dy)
	var k := _eng_kind(e, u)
	var rp := t_k_range[k] if k >= 0 else 100
	if ter_on == 0 and map_on == 0:
		if dist > t_m_range[ty] * rp / 100 or dist < t_m_min[ty] or dist <= 0:
			return false
	elif dist < t_m_min[ty] or dist <= 0 or not _shot_ok(sx, sy, ax, ay, dist, ty, _skip0(u), _skip1(ft), 0, rp):
		return false
	var p := pr_free
	pr_free = pr_next[p]
	pr_count += 1
	_eng_spend(e, u, k)
	if t_m_kind[ty] == 1:
		stat_bolts += 1
	else:
		stat_stones += 1
	var spread := t_m_spread0[ty] + dist * t_m_spread[ty] / 1000
	var lat := (_rand() % (spread + 1) + _rand() % (spread + 1)) - spread
	var lon := ((_rand() % (spread + 1) + _rand() % (spread + 1)) - spread) * 3 / 2
	if lon > 0:
		lon = lon * t_m_long[ty] / 100
	var ux := dx * FM.TRIG_ONE / dist
	var uy := dy * FM.TRIG_ONE / dist
	var lx := ax + ((ux * lon - uy * lat) / FM.TRIG_ONE)
	var ly := ay + ((uy * lon + ux * lat) / FM.TRIG_ONE)
	var flight := clampi(dist / spd + 3, 3, PR_BUCKETS - 1)
	pr_sx[p] = sx
	pr_sy[p] = sy
	pr_x[p] = clampi(lx, 0, field_w)
	pr_y[p] = clampi(ly, 0, field_h)
	pr_t0[p] = tick
	pr_t1[p] = tick + flight
	pr_unit[p] = u
	pr_ty[p] = ty
	pr_tu[p] = ft
	pr_ak[p] = k
	var b := (tick + flight) % PR_BUCKETS
	pr_next[p] = pr_bucket[b]
	pr_bucket[b] = p
	return true


## Engine e of battery u shoots at the face of gate g (no lead; the same
## scatter). Returns false if no shot was possible.
func _art_fire_gate(e: int, u: int, g: int, ty: int) -> bool:
	if pr_free < 0:
		return false
	var sx := e_x[e]
	var sy := e_y[e]
	var gf := gate_face(g)
	var dx := gf.x - sx
	var dy := gf.y - sy
	var dist := FM.approx_len(dx, dy)
	var k := _eng_kind(e, u)
	var rp := t_k_range[k] if k >= 0 else 100
	if dist < t_m_min[ty] or dist <= 0 or not _shot_ok(sx, sy, gf.x, gf.y, dist, ty, _skip0(u), LOF_SKIP, 0, rp):
		return false
	var p := pr_free
	pr_free = pr_next[p]
	pr_count += 1
	_eng_spend(e, u, k)
	if t_m_kind[ty] == 1:
		stat_bolts += 1
	else:
		stat_stones += 1
	var spread := t_m_spread0[ty] + dist * t_m_spread[ty] / 1000
	var lat := (_rand() % (spread + 1) + _rand() % (spread + 1)) - spread
	var lon := ((_rand() % (spread + 1) + _rand() % (spread + 1)) - spread) * 3 / 2
	if lon > 0:
		lon = lon * t_m_long[ty] / 100
	var ux := dx * FM.TRIG_ONE / dist
	var uy := dy * FM.TRIG_ONE / dist
	var flight := clampi(dist / t_m_speed[ty] + 3, 3, PR_BUCKETS - 1)
	pr_sx[p] = sx
	pr_sy[p] = sy
	pr_x[p] = clampi(gf.x + ((ux * lon - uy * lat) / FM.TRIG_ONE), 0, field_w)
	pr_y[p] = clampi(gf.y + ((uy * lon + ux * lat) / FM.TRIG_ONE), 0, field_h)
	pr_t0[p] = tick
	pr_t1[p] = tick + flight
	pr_unit[p] = u
	pr_ty[p] = ty
	pr_tu[p] = -2 - g
	pr_ak[p] = k
	var b := (tick + flight) % PR_BUCKETS
	pr_next[p] = pr_bucket[b]
	pr_bucket[b] = p
	return true


## Mean movement of unit t's soldiers over the last tick.
func _unit_velocity(t: int) -> Vector2i:
	var base := u_slot_base[t]
	var n_a := u_alive[t]
	var vx := 0
	var vy := 0
	for s in n_a:
		var i := slot_soldier[base + s]
		vx += pos_x[i] - prev_x[i]
		vy += pos_y[i] - prev_y[i]
	n_a = maxi(n_a, 1)
	return Vector2i(vx / n_a, vy / n_a)


## Near face of unit t seen from (sx, sy) along the line to (px, py): the
## point on that line 1 m inside the nearest of t's soldiers within 2.5 m of
## the line (the line's own end if none is).
func _near_face(t: int, sx: int, sy: int, px: int, py: int) -> Vector2i:
	var dx := px - sx
	var dy := py - sy
	# Exact length: approx_len (up to 4% off) would put the projections
	# metres out at 200 m.
	var d := maxi(FM.isqrt(dx * dx + dy * dy), 1)
	var ux := dx * FM.TRIG_ONE / d
	var uy := dy * FM.TRIG_ONE / d
	var near := (dx * ux + dy * uy) / FM.TRIG_ONE
	var base := u_slot_base[t]
	for s in u_alive[t]:
		var i := slot_soldier[base + s]
		var rx := pos_x[i] - sx
		var ry := pos_y[i] - sy
		var lt := (ry * ux - rx * uy) / FM.TRIG_ONE
		if lt > 2560 or lt < -2560:
			continue
		var al := (rx * ux + ry * uy) / FM.TRIG_ONE
		if al < near:
			near = al
	near += M / 2
	return Vector2i(sx + ux * near / FM.TRIG_ONE, sy + uy * near / FM.TRIG_ONE)


## Everything within reach of a straight path: the segment from (x0, y0) +
## a0 to + a1 along the Q12 unit vector (ux, uy). Soldiers count within r
## (rc for horses) across the path, working engines within ENGINE_R. Results
## in _sw_v / _sw_a / _sw_l (_sw_n of them), nearest along the path first,
## at most SWEEP_CAP. Units are culled by their bounding boxes first, so a
## shot only looks at the soldiers of units its path really crosses.
func _sweep(x0: int, y0: int, ux: int, uy: int, a0: int, a1: int, r: int, rc: int) -> void:
	_sw_n = 0
	var one := FM.TRIG_ONE
	var px0 := x0 + ((ux * a0) / one)
	var py0 := y0 + ((uy * a0) / one)
	var px1 := x0 + ((ux * a1) / one)
	var py1 := y0 + ((uy * a1) / one)
	var pad := maxi(maxi(r, rc), ENGINE_R) + M
	var bx0 := mini(px0, px1) - pad
	var bx1 := maxi(px0, px1) + pad
	var by0 := mini(py0, py1) - pad
	var by1 := maxi(py0, py1) + pad
	for u in n_units:
		if u_alive[u] <= 0 or u_state[u] >= U_DESTROYED:
			continue
		if u_maxx[u] < bx0 or u_minx[u] > bx1 or u_maxy[u] < by0 or u_miny[u] > by1:
			continue
		# Bounding box wholly to one side of the path: skip.
		var lo := 0
		var hi := 0
		for corner in 4:
			var cx := u_minx[u] if (corner & 1) == 0 else u_maxx[u]
			var cy := u_miny[u] if (corner & 2) == 0 else u_maxy[u]
			var lt := ((cy - y0) * ux - (cx - x0) * uy) / one
			if corner == 0 or lt < lo:
				lo = lt
			if corner == 0 or lt > hi:
				hi = lt
		if lo > pad or hi < -pad:
			continue
		var rr := rc if u_cls[u] == UT.CLS_CAV else r
		var base := u_slot_base[u]
		for s in u_alive[u]:
			var i := slot_soldier[base + s]
			if state[i] >= S_DEAD:
				continue
			var rx := pos_x[i] - x0
			var ry := pos_y[i] - y0
			var al := (rx * ux + ry * uy) / one
			if al < a0 or al > a1:
				continue
			var lt2 := (ry * ux - rx * uy) / one
			if lt2 > rr or lt2 < -rr:
				continue
			_sw_insert(i, al, lt2)
	for e in n_eng:
		if e_state[e] != E_OK:
			continue
		var rx := e_x[e] - x0
		var ry := e_y[e] - y0
		var al := (rx * ux + ry * uy) / one
		if al < a0 or al > a1:
			continue
		var lt3 := (ry * ux - rx * uy) / one
		if absi(lt3) <= ENGINE_R:
			_sw_insert(-(e + 1), al, lt3)


func _sw_insert(v: int, al: int, lt: int) -> void:
	var k := _sw_n
	if k >= SWEEP_CAP:
		if al >= _sw_a[SWEEP_CAP - 1]:
			return
		k = SWEEP_CAP - 1
	else:
		_sw_n += 1
	# Shift larger entries down; ties keep index order (deterministic).
	while k > 0 and (_sw_a[k - 1] > al or (_sw_a[k - 1] == al and _sw_v[k - 1] > v)):
		_sw_v[k] = _sw_v[k - 1]
		_sw_a[k] = _sw_a[k - 1]
		_sw_l[k] = _sw_l[k - 1]
		k -= 1
	_sw_v[k] = v
	_sw_a[k] = al
	_sw_l[k] = lt


## A bolt: flat, so it flies at body height along its whole line from the
## engine, through the aim point and on (m_plough) until its energy is
## spent. Anyone on the line, friend or foe, is struck in turn: a frontal
## shield takes some of the energy (BOLT_SHIELD_K % of the missile shield),
## armour is mostly pierced, each body absorbs BOLT_BODY + armour, and later
## men are less likely to be struck. An engine on the line stops it.
func _land_bolt(p: int) -> void:
	var k := pr_ak[p]
	var ob := t_k_obj[k] if k >= 0 else 100
	if pr_tu[p] <= -2 and _gate_hit(p, GATE_BOLT * ob / 100):
		return
	if sg_on != 0:
		if _tower_hit(p, TOWER_BOLT_DMG * ob / 100):
			return  # into the tower's masonry
		if n_eq > 0:
			_ram_hit(pr_x[p], pr_y[p], RAM_BOLT_DMG * ob / 100)
	var u := pr_unit[p]
	var ty := pr_ty[p]
	var sx := pr_sx[p]
	var sy := pr_sy[p]
	var dx := pr_x[p] - sx
	var dy := pr_y[p] - sy
	var dist := maxi(FM.approx_len(dx, dy), 1)
	var ux := dx * FM.TRIG_ONE / dist
	var uy := dy * FM.TRIG_ONE / dist
	var a1 := dist + t_m_plough[ty]
	var z0 := 0
	var dz := 0
	if ter_on != 0 or map_on != 0:
		# Over hilly ground the bolt flies a straight line from the engine to
		# the aim point and on: the ground stops it where it rises above that
		# line, and it passes over (or under) men it is not at body height for.
		# Woods, walls and buildings stop it too.
		z0 = elev_at(sx, sy) + LOF_EYE
		dz = elev_at(pr_x[p], pr_y[p]) + LOF_BODY - z0
		var blk := lof_block(sx, sy, z0, pr_x[p], pr_y[p], z0 + dz, dist * t_m_apex[ty] / 100,
			t_m_plough[ty], LOF_STEP, _skip0(u))
		if blk >= 0:
			a1 = mini(a1, blk)
			stat_bolt_ground += 1
	_sweep(sx, sy, ux, uy, maxi(BOLT_SKIP, _skip0(u)), a1, BOLT_R_INF, BOLT_R_CAV)
	var energy := t_m_dmg[ty] * t_k_dmg[k] / 100 if k >= 0 else t_m_dmg[ty]
	var pierce := t_m_pierce[ty] * t_k_pierce[k] / 100 if k >= 0 else t_m_pierce[ty]
	var ap := clampi(t_m_ap[ty] + t_k_ap[k], 0, 100) if k >= 0 else t_m_ap[ty]
	var from := FM.atan2_a(-dy, -dx)
	var hits := 0
	_hit_units.fill(-1)
	for sk in _sw_n:
		if energy < SHOT_STOP or hits >= pierce:
			break
		var v := _sw_v[sk]
		if ter_on != 0 or obs_on != 0:
			var vx := e_x[-v - 1] if v < 0 else pos_x[v]
			var vy := e_y[-v - 1] if v < 0 else pos_y[v]
			var rel := z0 + dz * _sw_a[sk] / dist - elev_at(vx, vy)
			if rel < BOLT_BODY_LO or rel > BOLT_BODY_HI:
				continue
		if v < 0:
			_engine_hit(-v - 1, energy)
			break
		if state[v] >= S_DEAD:
			continue
		if _rand() % 100 >= 100 - 12 * hits:
			continue  # passes him by
		if mt_on != 0 and _screen_cover(sx, sy, v, true):
			break  # into a mantlet
		var td := u_otype[unit_of[v]]
		var sv := state[v]
		var sh := 0
		if sv != S_ROUTING and sv != S_DOWN and absi(FM.angle_diff(facing[v], from)) <= FRONT_ARC:
			sh = t_mshield[td] * BOLT_SHIELD_K / 100
		var e1 := energy - sh
		var dmg := maxi(e1 - t_armour[td] * (100 - ap) / 100, 1) * t_m_vuln[td] / 100 \
			* (85 + _rand() % 31) / 100
		_art_wound(v, dmg, u, 0)
		energy = e1 - BOLT_BODY - t_armour[td]
		hits += 1
	_art_fright(ty, k)


## A stone: lobbed over everything, it smashes whoever is within m_blast of
## where it lands, then bounces and ploughs on m_plough along its flight
## through the ranks behind, knocking men down, losing energy with every
## body (STONE_BODY + armour) and every metre. Friend or foe alike. Engines
## it reaches take double damage (counter-battery fire).
func _land_stone(p: int) -> void:
	var ak := pr_ak[p]
	var ob := t_k_obj[ak] if ak >= 0 else 100
	if pr_tu[p] <= -2 and _gate_hit(p, GATE_STONE * ob / 100):
		return
	if sg_on != 0:
		_tower_hit(p, TOWER_STONE_DMG * ob / 100)  # (and it smashes on among the crew)
		if n_eq > 0:
			_ram_hit(pr_x[p], pr_y[p], RAM_STONE_DMG * ob / 100)
	var u := pr_unit[p]
	var ty := pr_ty[p]
	var lx := pr_x[p]
	var ly := pr_y[p]
	var dx := lx - pr_sx[p]
	var dy := ly - pr_sy[p]
	var dist := maxi(FM.approx_len(dx, dy), 1)
	var ux := dx * FM.TRIG_ONE / dist
	var uy := dy * FM.TRIG_ONE / dist
	var blast0 := t_m_blast[ty]
	var blast := blast0 + t_k_blast[ak] if ak >= 0 else blast0
	if ak >= 0 and t_k_aoe[ak] != 0:
		_land_blast(u, ty, ak, lx, ly, ux, uy, blast)
		return
	var r := maxi(blast, STONE_R_INF)
	var plough := t_m_plough[ty]
	if ter_on != 0:
		# A stone bouncing on uphill stops sooner; downhill it rolls further.
		var g := grade_along(lx, ly, ux, uy)
		var pf := 1000
		if g > 0:
			pf = 1000 - g * STONE_UP_K * 10 / FM.TRIG_ONE
			stat_plough_short += 1
		elif g < 0:
			pf = 1000 - g * STONE_DOWN_K * 10 / FM.TRIG_ONE
		plough = plough * clampi(pf, STONE_PLOUGH_MIN, STONE_PLOUGH_MAX) / 1000
	if map_on != 0:
		# Trees catch some stones and slow the rest; walls and houses stop
		# the plough.
		var vd := veg_d(lx, ly)
		if vd > 0:
			if _rand() % 100 < VEG_STOP_STONE[vd]:
				stat_veg_stop += 1
				return
			plough = plough * VEG_PLOUGH[vd] / 1000
		if obs_on != 0:
			plough = _obs_run(lx, ly, ux, uy, plough)
	_sweep(lx, ly, ux, uy, -blast, plough, r, maxi(blast, STONE_R_CAV))
	var energy0 := t_m_dmg[ty] * t_k_dmg[ak] / 100 if ak >= 0 else t_m_dmg[ty]
	var pierce := t_m_pierce[ty] * t_k_pierce[ak] / 100 if ak >= 0 else t_m_pierce[ty]
	var ap := clampi(t_m_ap[ty] + t_k_ap[ak], 0, 100) if ak >= 0 else t_m_ap[ty]
	var hits := 0
	_hit_units.fill(-1)
	# View: impact mark (not state).
	fx_x[fx_head] = lx
	fx_y[fx_head] = ly
	fx_dx[fx_head] = ux
	fx_dy[fx_head] = uy
	fx_t[fx_head] = tick
	fx_head = (fx_head + 1) % FX_CAP
	var absorbed := 0
	for k in _sw_n:
		if hits >= pierce:
			break
		var al := _sw_a[k]
		var lt := _sw_l[k]
		var v := _sw_v[k]
		var cav := v >= 0 and u_cls[unit_of[v]] == UT.CLS_CAV
		if al <= blast:
			# Direct hit: within the blast circle round the landing point.
			if al * al + lt * lt > blast * blast:
				continue
			if blast > blast0 and al * al + lt * lt > blast0 * blast0:
				stat_blast += 1  # (inside a bursting stone's wider blast only)
		elif absi(lt) > (STONE_R_CAV if cav else STONE_R_INF):
			continue
		var energy := energy0 - absorbed - maxi(al, 0) * STONE_ROLL_LOSS / M
		if energy < SHOT_STOP:
			break
		if v < 0:
			_engine_hit(-v - 1, energy * 2)
			break
		if state[v] >= S_DEAD:
			continue
		var td := u_otype[unit_of[v]]
		var dmg := maxi(energy - t_armour[td] * (100 - ap) / 100, 1) * t_m_vuln[td] / 100 \
			* (85 + _rand() % 31) / 100
		_art_wound(v, dmg, u, mini(energy / 2 + STONE_KNOCK, 90))
		absorbed += STONE_BODY + t_armour[td]
		hits += 1
	_art_fright(ty, ak)


## A bursting stone (ammunition kind with aoe; docs/DESIGN.md "Explosive
## stones: blast and knockback"): no plough. Every man within `blast` of
## the landing point is struck (armour as for a stone), the damage falling
## from full at the centre to a third at the edge; engines within it take
## double (as a stone). Then the survivors, nearest first (ties: index
## order), at most BLAST_KNOCK_MAX of them, are thrown outward
## BLAST_THROW + rand BLAST_THROW_RND (riders and beasts half; an elephant
## not at all) unless a wall, a building or a walk's edge is in the way,
## and lie down (S_DOWN, cooldown = ticks left; riders and beasts half,
## an elephant BLAST_DOWN_BIG).
func _land_blast(u: int, ty: int, ak: int, lx: int, ly: int, ux: int, uy: int, blast: int) -> void:
	var energy0 := t_m_dmg[ty] * t_k_dmg[ak] / 100
	var ap := clampi(t_m_ap[ty] + t_k_ap[ak], 0, 100)
	_hit_units.fill(-1)
	fx_x[fx_head] = lx
	fx_y[fx_head] = ly
	fx_dx[fx_head] = ux
	fx_dy[fx_head] = uy
	fx_t[fx_head] = tick
	fx_head = (fx_head + 1) % FX_CAP
	var r := maxi(blast, 1)
	var r2 := r * r
	# Gather the men inside, nearest first (ties: lower index).
	var vs := PackedInt32Array()
	var ds := PackedInt32Array()
	for v in n_units:
		if u_alive[v] <= 0 or u_state[v] >= U_DESTROYED:
			continue
		if u_maxx[v] < lx - r - M or u_minx[v] > lx + r + M or u_maxy[v] < ly - r - M or u_miny[v] > ly + r + M:
			continue
		var base := u_slot_base[v]
		for s in u_alive[v]:
			var i := slot_soldier[base + s]
			if state[i] >= S_DEAD:
				continue
			var rx := pos_x[i] - lx
			var ry := pos_y[i] - ly
			if absi(rx) > r or absi(ry) > r or rx * rx + ry * ry > r2:
				continue
			var d := FM.approx_len(rx, ry)
			var k := vs.size()
			vs.append(i)
			ds.append(d)
			while k > 0 and (ds[k - 1] > d or (ds[k - 1] == d and vs[k - 1] > i)):
				vs[k] = vs[k - 1]
				ds[k] = ds[k - 1]
				k -= 1
			vs[k] = i
			ds[k] = d
	for e in n_eng:
		if e_state[e] != E_OK:
			continue
		var erx := e_x[e] - lx
		var ery := e_y[e] - ly
		if absi(erx) <= r and absi(ery) <= r and erx * erx + ery * ery <= r2:
			var ed := mini(FM.approx_len(erx, ery), r)
			_engine_hit(e, energy0 * 2 * (3 * r - 2 * ed) / (3 * r))
	# Strike them all, nearest first.
	for k in vs.size():
		var v := vs[k]
		if state[v] >= S_DEAD:
			continue
		var d := mini(ds[k], r)
		var energy := energy0 * (3 * r - 2 * d) / (3 * r)
		var td := u_otype[unit_of[v]]
		var dmg := maxi(energy - t_armour[td] * (100 - ap) / 100, 1) * t_m_vuln[td] / 100 \
			* (85 + _rand() % 31) / 100
		stat_blast += 1
		_art_wound(v, dmg, u, 0)
	# Throw and down the survivors, nearest first.
	var knocked := 0
	for k in vs.size():
		if knocked >= BLAST_KNOCK_MAX:
			break
		var v := vs[k]
		if state[v] >= S_DEAD:
			continue
		knocked += 1
		_blast_throw(v, lx, ly, ux, uy)
	_art_fright(ty, ak)


## Soldier v, caught in a blast at (lx, ly) (flight direction ux, uy): thrown
## outward and knocked down (see _land_blast).
func _blast_throw(v: int, lx: int, ly: int, ux: int, uy: int) -> void:
	var uv := unit_of[v]
	var td := u_otype[uv]
	var big := big_on != 0 and t_body_r[td] > 0
	var half := t_cls[td] == UT.CLS_CAV or t_mount[td] != UT.MOUNT_FOOT
	stat_blast_knock += 1
	var dist := 0
	if not big:
		dist = BLAST_THROW + _rand() % BLAST_THROW_RND
		if half:
			dist /= 2
	var down := BLAST_DOWN_BIG
	if not big:
		down = BLAST_DOWN + _rand() % BLAST_DOWN_RND
		if half:
			down /= 2
	if dist > 0:
		var x := pos_x[v]
		var y := pos_y[v]
		var rx := x - lx
		var ry := y - ly
		var l := FM.approx_len(rx, ry)
		if l <= 0:
			rx = ux
			ry = uy
			l = FM.approx_len(rx, ry)
		if l > 0:
			var nx := clampi(x + rx * dist / l, 0, field_w)
			var ny := clampi(y + ry * dist / l, 0, field_h)
			# Only over the kind of ground he stands on (no passing through a
			# wall, a gate or a building, nor off a walkway with nothing below).
			var okm := nav_at(x, y) & _mask_of(uv)
			if okm != 0 and (nav_at((x + nx) >> 1, (y + ny) >> 1) & okm) != 0 and (nav_at(nx, ny) & okm) != 0:
				pos_x[v] = nx
				pos_y[v] = ny
			else:
				stat_blast_held += 1
	var st := state[v]
	if st == S_ROUTING:
		return  # thrown, but he keeps running
	stat_blast_down += down
	if st == S_DOWN:
		cooldown[v] = maxi(cooldown[v], down)
		return
	state[v] = S_DOWN
	target[v] = -1
	cooldown[v] = down
	u_down[uv] += 1
	u_settled[uv] = 0


func _engine_hit(e: int, energy: int) -> void:
	stat_engine_hits += 1
	e_hp[e] -= energy
	if e_hp[e] <= 0:
		_wreck(e)


## An artillery shot (fired by battery `by`) strikes soldier v for dmg;
## knock: knockdown chance if he survives.
func _art_wound(v: int, dmg: int, by: int, knock: int) -> void:
	var uv := unit_of[v]
	stat_art_victims += 1
	if u_state[uv] == U_READY:
		u_hit_t[uv] = tick
		u_shelled_t[uv] = tick
		u_shelled_by[uv] = by
		for k in 4:
			if _hit_units[k] == uv:
				break
			if _hit_units[k] < 0:
				_hit_units[k] = uv
				break
	var h := hp[v] - dmg
	if h <= 0:
		stat_kills[4] += 1
		stat_kside[u_side[unit_of[v]] * 5 + 4] += 1
		_credit(by, uv)
		stat_art_kills += 1
		if t_fixed[u_type[by]] != 0:
			stat_tower_kills += 1
		_remove(v, GONE_KILLED)
		return
	hp[v] = h
	if knock > 0 and _rand() % 100 < knock:
		_knock_down(v)


## Fright for every unit one shot struck (once per unit per shot), plus
## its ammunition kind's fear and fire.
func _art_fright(ty: int, ak: int = -1) -> void:
	var fear := t_m_fear[ty] + (t_k_fear[ak] if ak >= 0 else 0)
	for k in 4:
		var uv := _hit_units[k]
		if uv < 0:
			break
		if u_state[uv] == U_READY:
			u_fright[uv] = mini(u_fright[uv] + fear, FRIGHT_MAX)
			if ak >= 0 and t_k_fire[ak] > 0:
				_kind_shock(uv, ak, false)


# ---------------------------------------------------------------- morale ---

func _update_morale() -> void:
	if aura_src.size() > 0 and tick % TICKS_PER_SECOND == 0:
		_update_auras()
	if dog_on != 0 and tick % TICKS_PER_SECOND == 0:
		_update_packs()
	for u in n_units:
		var us := u_state[u]
		if us >= U_DESTROYED:
			continue
		var ty := u_type[u]
		if t_fixed[ty] != 0:
			continue  # a tower's crew stays at its engine
		if u_kill[u] > 0:
			# The drivers were told to kill their beasts: done when the time is up.
			u_kill[u] -= 1
			if u_kill[u] == 0:
				_driver_kill(u)
				continue
		var m := u_morale[u]
		var periodic := (u + tick) % TICKS_PER_SECOND == 0
		u_recent[u] -= u_recent[u] >> RECENT_DECAY_SHIFT
		if u_burn[u] > 0:
			# Fire missiles set its men burning: heart drains till it is out
			# (a beast's much faster: burn_pct).
			u_burn[u] -= 1
			if us == U_READY:
				m -= BURN_DRAIN * t_burn_pct[u_otype[u]] / 100
		if u_fright[u] > 0:
			u_fright[u] = maxi(u_fright[u] - FRIGHT_DECAY, 0)
		if us == U_READY:
			if u_contact[u] == 0 and u_fighting[u] == 0 and tick - u_hit_t[u] > UNDER_FIRE_TICKS and u_awe[u] == 0:
				var base_m := t_morale[u_otype[u]]
				var cap := base_m - (u_count0[u] - u_alive[u]) * base_m / (2 * u_count0[u])
				if m < cap:
					m = mini(m + MORALE_RECOVER, cap)
			if periodic:
				var routing_near := 0
				for o in n_units:
					if o != u and u_side[o] == u_side[u] and u_state[o] == U_ROUTING:
						var dx := u_cx[o] - u_cx[u]
						var dy := u_cy[o] - u_cy[u]
						if absi(dx) < ROUTING_FRIEND_RANGE and absi(dy) < ROUTING_FRIEND_RANGE:
							routing_near += 1
				m -= MORALE_ROUTING_FRIEND * mini(routing_near, MAX_ROUTING_FRIENDS)
			u_morale[u] = clampi(m, -MORALE_MAX, MORALE_MAX)
			# Artillery fright counts against morale while it lasts.
			if m - u_fright[u] < ROUT_THRESHOLD:
				_start_rout(u)
		elif u_amok[u] != 0:
			# Running amok: erratic, never rallying; it calms once alone.
			if periodic:
				if _anyone_near(u, t_amok_r[u_otype[u]]):
					u_calm[u] = 0
				else:
					u_calm[u] += TICKS_PER_SECOND
				if u_calm[u] >= t_amok_calm[u_otype[u]]:
					_calm(u)
					continue
				_amok_veer(u)
			u_morale[u] = clampi(m, -MORALE_MAX, MORALE_MAX)
		else:  # routing
			if periodic:
				var e := _nearest_enemy_unit(u, true)
				var safe := true
				if e >= 0:
					var dx := u_cx[u] - u_cx[e]
					var dy := u_cy[u] - u_cy[e]
					var d := FM.isqrt(dx * dx + dy * dy)
					safe = d > RALLY_SAFE_RANGE
					_set_flee(u, dx, dy, d)
				if safe:
					m += 40
			u_morale[u] = clampi(m, -MORALE_MAX, MORALE_MAX)
			# u_routs counts this rout too: a unit may rally from its first
			# MAX_ROUTS routs; after that the rout is final.
			if m >= RALLY_THRESHOLD and u_routs[u] <= MAX_ROUTS and u_alive[u] * 5 >= u_count0[u]:
				_rally(u)


## Flee direction: away from the threat (dx, dy, length d), bent toward the
## side's own map edge.
func _set_flee(u: int, dx: int, dy: int, d: int) -> void:
	var fx := 0
	var fy := 0
	if d > 0:
		fx = dx * FM.TRIG_ONE / d
		fy = dy * FM.TRIG_ONE / d
	fy += FM.TRIG_ONE * 2 if u_side[u] == 0 else -FM.TRIG_ONE * 2
	var l := maxi(FM.isqrt(fx * fx + fy * fy), 1)
	u_flee_x[u] = fx * FM.TRIG_ONE / l
	u_flee_y[u] = fy * FM.TRIG_ONE / l


func _nearest_enemy_unit(u: int, ready_only: bool) -> int:
	var best := -1
	var best_d := 0
	for o in n_units:
		if u_side[o] == u_side[u] or u_state[o] >= U_DESTROYED:
			continue
		if ready_only and u_state[o] != U_READY:
			continue
		var dx := u_cx[o] - u_cx[u]
		var dy := u_cy[o] - u_cy[u]
		var d2 := dx * dx + dy * dy
		if best < 0 or d2 < best_d:
			best = o
			best_d = d2
	return best


func _start_rout(u: int) -> void:
	if t_fixed[u_type[u]] != 0:
		return  # a tower's crew stays at its engine
	if t_nobreak[u_otype[u]] != 0:
		return  # (a war dog pack never breaks)
	if u_cls[u] == UT.CLS_MISSILE:
		stat_aic[u_side[u] * AIProfile.N_COUNTERS + AIProfile.C_AMMO_AT_ROUT] += u_ammo[u]
		stat_aic[u_side[u] * AIProfile.N_COUNTERS + AIProfile.C_MISSILE_ROUTS] += 1
	u_state[u] = U_ROUTING
	u_routs[u] += 1
	if t_cmd_loss[u_type[u]] > 0 or t_cmd_loss_r[u_type[u]] > 0:
		_cmd_fall(u)  # the general flees: the army is shaken
	if t_amok[u_otype[u]] != 0:
		u_amok[u] = 1  # a beast breaking runs amok (below: its first veer)
		u_calm[u] = 0
		stat_amok += 1
	u_sq[u] = 0
	u_gtarget[u] = -1
	if obs_on != 0:
		u_pn[u] = 0
	u_order[u] = O_NONE
	if sg_on != 0 and u_carry[u] >= 0:
		_drop(u)  # routing: whatever it carries is left where it is
	if u_wall[u] > 0 and u_side[u] != city_def and u_lq[u] >= 0:
		_ladder_down(u)  # up the ladders: back down them
	elif u_wall[u] > 0:
		_start_descent(u)  # off the wall by the nearest stair
	elif u_stair[u] == 2:
		u_stair[u] = 0
	u_target[u] = -1
	u_ftarget[u] = -1
	u_settled[u] = 0
	u_morale[u] = 0
	u_down[u] = 0
	# Flee away from the nearest enemy and toward the own edge.
	var e := _nearest_enemy_unit(u, false)
	if e >= 0:
		var dx := u_cx[u] - u_cx[e]
		var dy := u_cy[u] - u_cy[e]
		_set_flee(u, dx, dy, FM.isqrt(dx * dx + dy * dy))
	else:
		_set_flee(u, 0, 0, 0)
	if u_amok[u] != 0:
		_amok_veer(u)
	var base := u_slot_base[u]
	for s in u_alive[u]:
		var i := slot_soldier[base + s]
		state[i] = S_ROUTING
		target[i] = -1


func _rally(u: int) -> void:
	u_state[u] = U_READY
	if obs_on != 0:
		u_pn[u] = 0
	u_morale[u] = RALLY_THRESHOLD
	var e := _nearest_enemy_unit(u, false)
	var face := u_face[u]
	if e >= 0:
		face = FM.atan2_a(u_cy[e] - u_cy[u], u_cx[e] - u_cx[u])
	u_face[u] = face
	u_dface[u] = face
	u_ax[u] = u_cx[u]
	u_ay[u] = u_cy[u]
	if u_stair[u] == 1:
		var dp := stair_pt(u_sseg[u], u_send[u], 2)
		u_ax[u] = dp.x  # still coming down: gather at the stair's foot
		u_ay[u] = dp.y
	u_order[u] = O_NONE
	u_run[u] = 0
	u_dirty[u] = 1
	u_settled[u] = 0
	u_disorder[u] = DISORDERED
	_compute_offsets(u)
	var base := u_slot_base[u]
	for s in u_alive[u]:
		var i := slot_soldier[base + s]
		state[i] = S_FORMED
		target[i] = -1


## Horse scare and fear auras, once a second: each ready unit within an
## enemy aura source's radius (box to box) takes its effects: horses
## (mount 1) near a scaring unit keep its scare_pct of their charge and
## turn rate (u_scare, until the next second) and lose its scare_mor; any
## unit without a fear aura of its own near a fear source loses its
## fear_horse (horses) or fear_foot a second. Command (the fear aura
## inverted, docs/DESIGN.md "The general"): a friendly unit within a ready
## general's cmd_r (not his own) gains the best cmd_mor a second, up to the
## morale rest would bring it back to (also fighting and under fire); a
## routing one (not amok) the best cmd_rally. Sources in index order.
func _update_auras() -> void:
	for u in n_units:
		if u_state[u] != U_READY or u_alive[u] <= 0:
			u_scare[u] = 0
			u_awe[u] = 0
			u_led[u] = 0
			if u_state[u] == U_ROUTING and u_alive[u] > 0 and u_amok[u] == 0:
				var rb := _cmd_near(u)
				if rb > 0:
					u_led[u] = 1
					u_morale[u] = mini(u_morale[u] + rb, MORALE_MAX)
					stat_cmd_rally += 1
			continue
		var tu := u_otype[u]
		var horse := t_mount[tu] == UT.MOUNT_HORSE
		var keep := 0
		var loss := 0
		var feared := false
		var held := 0
		for src in aura_src:
			if src == u or u_state[src] != U_READY or u_alive[src] <= 0:
				continue
			var sty := u_type[src]
			if u_side[src] == u_side[u]:
				if t_cmd_r[sty] > 0 and t_cmd_mor[sty] > held and _box_gap(src, u) <= t_cmd_r[sty]:
					held = t_cmd_mor[sty]
				continue
			var gap := _box_gap(src, u)
			var scared := horse if t_scare_am[sty] < 0 else t_armour[tu] <= t_scare_am[sty]
			if scared and t_scare_r[sty] > 0 and gap <= t_scare_r[sty]:
				keep = t_scare_pct[sty] if keep == 0 else mini(keep, t_scare_pct[sty])
				loss += t_scare_mor[sty]
			if t_fear_r[sty] > 0 and t_fear_r[tu] == 0 and gap <= t_fear_r[sty]:
				loss += t_fear_h[sty] if horse else t_fear_f[sty]
				feared = true
		u_scare[u] = keep
		u_awe[u] = 1 if keep > 0 or feared else 0  # (no recovery of heart meanwhile)
		u_led[u] = 1 if held > 0 else 0
		if keep > 0:
			stat_scared += 1
		if feared:
			stat_feared += 1
		if loss > 0:
			u_morale[u] -= loss
		if held > 0:
			stat_cmd += 1
			var base_m := t_morale[tu]
			var cap := base_m - (u_count0[u] - u_alive[u]) * base_m / (2 * u_count0[u])
			if u_morale[u] < cap:
				u_morale[u] = mini(u_morale[u] + held, cap)


## The best rally bonus (cmd_rally) of a ready friendly general within his
## cmd_r of routing unit u (0 none).
func _cmd_near(u: int) -> int:
	var best := 0
	for src in aura_src:
		if src == u or u_side[src] != u_side[u] or u_state[src] != U_READY or u_alive[src] <= 0:
			continue
		var sty := u_type[src]
		if t_cmd_r[sty] > 0 and t_cmd_rally[sty] > best and _box_gap(src, u) <= t_cmd_r[sty]:
			best = t_cmd_rally[sty]
	return best


## General u routed or lost his last man: every other friendly unit on the
## field (ready or routing) loses his cmd_loss, those within his cmd_r his
## cmd_loss_r instead; once a battle (u_cmdgone). The rout follows at the
## next morale update.
func _cmd_fall(u: int) -> void:
	var ty := u_type[u]
	if t_cmd_loss[ty] <= 0 and t_cmd_loss_r[ty] <= 0 or u_cmdgone[u] != 0:
		return
	u_cmdgone[u] = 1
	stat_cmd_falls += 1
	for o in n_units:
		if o == u or u_side[o] != u_side[u] or u_alive[o] <= 0 or u_state[o] >= U_DESTROYED:
			continue
		var hit := t_cmd_loss_r[ty] if _box_gap(u, o) <= t_cmd_r[ty] else t_cmd_loss[ty]
		u_morale[o] = clampi(u_morale[o] - hit, -MORALE_MAX, MORALE_MAX)


## Gap between the boxes of units a and b (0 overlapping).
func _box_gap(a: int, b: int) -> int:
	var dx := maxi(maxi(u_minx[a] - u_maxx[b], u_minx[b] - u_maxx[a]), 0)
	var dy := maxi(maxi(u_miny[a] - u_maxy[b], u_miny[b] - u_maxy[a]), 0)
	return FM.approx_len(dx, dy)


## Any other unit (either side, routing too) on the field within r of u's box.
func _anyone_near(u: int, r: int) -> bool:
	for o in n_units:
		if o != u and u_alive[o] > 0 and u_state[o] < U_DESTROYED and _box_gap(u, o) <= r:
			return true
	return false


## An amok beast veers: up to AMOK_VEER either way (the sim's RNG), back
## toward the middle of the field when near an edge.
func _amok_veer(u: int) -> void:
	var a := FM.atan2_a(u_flee_y[u], u_flee_x[u])
	if u_cx[u] < AMOK_EDGE or u_cx[u] > field_w - AMOK_EDGE or u_cy[u] < AMOK_EDGE or u_cy[u] > field_h - AMOK_EDGE:
		a = FM.atan2_a(field_h / 2 - u_cy[u], field_w / 2 - u_cx[u])
	a = (a + _rand() % (2 * AMOK_VEER + 1) - AMOK_VEER) & FM.ANGLE_MASK
	u_flee_x[u] = FM.cos_a(a)
	u_flee_y[u] = FM.sin_a(a)


## An amok beast left alone long enough: its rider has it in hand again.
func _calm(u: int) -> void:
	u_amok[u] = 0
	u_calm[u] = 0
	stat_calmed += 1
	_rally(u)


## Each beast of amok unit u tramples (every AMOK_EVERY ticks) every man of
## any other unit, friend or foe, within its body and a metre: a charge
## impact at AMOK_MOM (kills of friends count as friendly fire). Units and
## men in index order.
func _amok_trample(u: int) -> void:
	var ty := u_type[u]
	var rr := t_body_r[ty] + M
	var power := t_charge[ty] * AMOK_MOM / 100
	var base := u_slot_base[u]
	var beasts := slot_soldier.slice(base, base + u_alive[u])
	for i in beasts:
		if state[i] >= S_DEAD or (tick + i) % AMOK_EVERY != 0:
			continue
		var x := pos_x[i]
		var y := pos_y[i]
		for o in n_units:
			if o == u or u_alive[o] <= 0 or u_state[o] >= U_DESTROYED:
				continue
			if u_maxx[o] < x - rr or u_minx[o] > x + rr or u_maxy[o] < y - rr or u_miny[o] > y + rr:
				continue
			var ob := u_slot_base[o]
			var men := slot_soldier.slice(ob, ob + u_alive[o])
			for v in men:
				if state[v] >= S_DEAD:
					continue
				var dx := pos_x[v] - x
				var dy := pos_y[v] - y
				if absi(dx) > rr or absi(dy) > rr or dx * dx + dy * dy > rr * rr:
					continue
				stat_trampled += 1
				if u_side[o] == u_side[u]:
					stat_trample_ff += 1
				_impact_victim(i, v, power, t_mass[ty], _zone(o, x, y))
				if state[i] >= S_DEAD:
					break
			if state[i] >= S_DEAD:
				break


## The drivers of unit u kill their beasts (the Kill order's delay is up).
func _driver_kill(u: int) -> void:
	var base := u_slot_base[u]
	var beasts := slot_soldier.slice(base, base + u_alive[u])
	for i in beasts:
		if state[i] < S_DEAD:
			stat_beast_killed += 1
			_remove(i, GONE_KILLED)
	u_amok[u] = 0


## Why unit u's drivers cannot be told to kill their beasts ("" they can):
## only a beast unit running amok, once.
static func kill_refusal(sim, u: int) -> String:
	if u < 0 or u >= sim.n_units or sim.u_alive[u] <= 0:
		return "no unit"
	if UT.stat(sim.u_type[u], "kill_delay") <= 0:
		return "not a beast"
	if sim.u_amok[u] == 0:
		return "only when running amok"
	if sim.u_kill[u] > 0:
		return "already ordered"
	return ""


# ------------------------------------------------------------- war dogs ---
# docs/DESIGN.md "War dogs". A handler row (pack_n > 0) carries a pack of
# pack_n dogs a man of row pack_type: a unit of its own, made at setup after
# every other unit and kept with its handlers (U_KENNEL: no men on the field,
# its dogs S_OFF with their hp) until ORDER_RELEASE lets it loose at an enemy
# unit. Released, it fights (never breaking: nobreak); with no live target it
# goes for the nearest enemy within its return_r; once none has been within
# return_r for return_t it runs back to its handlers and rejoins them (the
# dogs still alive go back in the kennel, ready for another release). A pack
# whose handlers are gone or broken fights on and then stands.

const RETURN_GAP := 3 * M  # a returning pack this near its handlers (box to box) is back


## The pack units for scenario units `units` (dictionaries): one per handler
## unit, after them, "pack_of" naming the handlers.
static func _dog_packs(units: Array) -> Array:
	var out: Array = []
	for h in units.size():
		var ud: Dictionary = units[h]
		var ty := int(ud["type"])
		var pn := UT.stat(ty, "pack_n")
		var pt := UT.stat(ty, "pack_type")
		if pn <= 0 or pt < 0:
			continue
		out.append({"type": pt, "count": maxi(int(ud["count"]) * pn, 1), "side": int(ud["side"]),
			"x_m": int(ud["x_m"]), "y_m": int(ud["y_m"]), "facing": int(ud["facing"]), "files": 8, "pack_of": h})
	return out


## Setup: pack unit p of handlers h goes in the kennel.
func _kennel_setup(p: int, h: int) -> void:
	u_hand[p] = h
	u_pack[h] = p
	var base := u_slot_base[p]
	for s in u_count0[p]:
		var i := base + s
		state[i] = S_OFF
		slot_of[i] = -1
		slot_soldier[base + s] = -1
		target[i] = -1
	u_kept[p] = u_count0[p]
	u_alive[p] = 0
	u_state[p] = U_KENNEL
	u_order[p] = O_NONE


## Why handlers h cannot release their pack at enemy unit t ("" they can).
static func release_refusal(sim, h: int, t: int) -> String:
	if h < 0 or h >= sim.n_units or sim.u_state[h] != U_READY or sim.u_alive[h] <= 0:
		return "no unit"
	var p: int = sim.u_pack[h]
	if p < 0:
		return "no dogs"
	if sim.u_state[p] != U_KENNEL:
		return "the pack is out"
	if sim.u_kept[p] <= 0:
		return "no dogs left"
	if sim.u_wall[h] > 0 or sim.u_stair[h] != 0:
		return "not from the wall"
	if t < 0 or t >= sim.n_units or sim.u_side[t] == sim.u_side[h] or sim.u_state[t] >= U_DESTROYED \
			or sim.u_alive[t] <= 0:
		return "no target"
	var r: int = sim.t_pack_r[sim.u_otype[h]]
	if sim._box_gap(h, t) > r:
		return "too far (%d m)" % (r / M)
	return ""


static func make_release_order(p_tick: int, unit: int, target_unit: int) -> Dictionary:
	return {"tick": p_tick, "type": ORDER_RELEASE, "unit": unit, "target": target_unit}


## Dogs ready to be released by unit h (0: none, or no pack).
func pack_left(h: int) -> int:
	var p := u_pack[h] if h >= 0 and h < n_units else -1
	if p < 0:
		return 0
	return u_kept[p]


## Handlers h let their pack loose at enemy unit t: every dog in the kennel
## comes out among the handlers' men and runs at it.
func _unleash(h: int, t: int) -> void:
	var p := u_pack[h]
	var base := u_slot_base[p]
	var k := 0
	for s in u_count0[p]:
		var i := base + s
		if state[i] == S_OFF and hp[i] > 0:
			slot_soldier[base + k] = i
			slot_of[i] = k
			k += 1
	for s in range(k, u_count0[p]):
		slot_soldier[base + s] = -1
	if k == 0:
		return
	var face := FM.atan2_a(u_cy[t] - u_cy[h], u_cx[t] - u_cx[h])
	u_alive[p] = k
	u_kept[p] = 0
	u_state[p] = U_READY
	u_morale[p] = t_morale[u_otype[p]]
	u_files[p] = clampi((k + 3) / 4, 1, k)
	u_ax[p] = u_cx[h]
	u_ay[p] = u_cy[h]
	u_dx[p] = u_cx[h]
	u_dy[p] = u_cy[h]
	u_face[p] = face
	u_dface[p] = face
	u_order[p] = O_ATTACK
	u_target[p] = t
	u_ftarget[p] = -1
	u_run[p] = 1
	u_disorder[p] = 0
	u_formed[p] = 0
	u_braced[p] = 0
	u_mom[p] = 0
	u_charge[p] = 0
	u_down[p] = 0
	u_fighting[p] = 0
	u_contact[p] = 0
	u_inreach[p] = 0
	u_scare[p] = 0
	u_awe[p] = 0
	u_ret[p] = 0
	u_dogt[p] = 0
	u_wall[p] = 0
	u_stair[p] = 0
	u_lagt[p] = 0
	if obs_on != 0:
		u_pn[p] = 0
	u_dirty[p] = 1
	u_settled[p] = 0
	_compute_offsets(p)
	# Out among the handlers' men (ground they stand on), a little apart.
	var hb := u_slot_base[h]
	var ha := maxi(u_alive[h], 1)
	for s in k:
		var i := slot_soldier[base + s]
		var j := slot_soldier[hb + s % ha]
		var ring := s / ha
		pos_x[i] = clampi(pos_x[j] + (ring % 2) * 512 - 256, 0, field_w)
		pos_y[i] = clampi(pos_y[j] + ((ring + 1) % 2) * 512 - 256, 0, field_h)
		prev_x[i] = pos_x[i]
		prev_y[i] = pos_y[i]
		facing[i] = face
		state[i] = S_FORMED
		target[i] = -1
		cooldown[i] = 1 + s % maxi(t_cooldown[u_type[p]], 1)
		chg[i] = 0
		struck[i] = 0
	_bounds_of(p)
	if ter_on != 0 or obs_on != 0 or fwh_on != 0:
		u_h[p] = _unit_elev(p)
	stat_released += 1


## Centroid and box of unit u from its men (a released pack).
func _bounds_of(u: int) -> void:
	var base := u_slot_base[u]
	var alive := u_alive[u]
	var i0 := slot_soldier[base]
	var minx := pos_x[i0]
	var maxx := minx
	var miny := pos_y[i0]
	var maxy := miny
	var sx := 0
	var sy := 0
	for s in alive:
		var i := slot_soldier[base + s]
		sx += pos_x[i]
		sy += pos_y[i]
		minx = mini(minx, pos_x[i])
		maxx = maxi(maxx, pos_x[i])
		miny = mini(miny, pos_y[i])
		maxy = maxi(maxy, pos_y[i])
	_set_bounds(u, sx / alive, sy / alive, minx, miny, maxx, maxy)


## Released packs, once a second (units in index order): the return rule,
## the hunt for the nearest enemy, the absorb at the handlers.
func _update_packs() -> void:
	for p in n_units:
		var h := u_hand[p]
		if h < 0 or u_state[p] != U_READY or u_alive[p] <= 0:
			continue
		var ty := u_otype[p]
		var home := u_state[h] == U_READY and u_alive[h] > 0 and u_wall[h] == 0
		if u_ret[p] != 0:
			if not home:
				# The handlers are gone or broken: it stands where it is.
				u_ret[p] = 0
				u_order[p] = O_NONE
				u_dx[p] = u_ax[p]
				u_dy[p] = u_ay[p]
				continue
			if _box_gap(p, h) <= RETURN_GAP:
				_absorb(p)
			else:
				_pack_to(p, h)  # (the handlers may have moved)
			continue
		var t := u_target[p] if u_order[p] == O_ATTACK else -1
		if t >= 0 and u_state[t] < U_DESTROYED and u_alive[t] > 0:
			u_dogt[p] = 0
			continue
		var e := _nearest_foe_within(p, t_return_r[ty])
		if e >= 0:
			u_dogt[p] = 0
			if u_order[p] != O_MOVE:
				# Nothing to bite: the nearest enemy it sees.
				u_order[p] = O_ATTACK
				u_target[p] = e
				u_run[p] = 1
				u_dirty[p] = 1
				u_settled[p] = 0
				if obs_on != 0:
					u_pn[p] = 0
				stat_dog_hunt += 1
			continue
		u_dogt[p] += TICKS_PER_SECOND
		if u_dogt[p] >= t_return_t[ty] and home:
			u_ret[p] = 1
			_pack_to(p, h)


## The nearest enemy unit (ready or routing, box to box) within r of unit u, -1 none.
func _nearest_foe_within(u: int, r: int) -> int:
	var best := -1
	var bd := 0
	for o in n_units:
		if u_side[o] == u_side[u] or u_state[o] >= U_DESTROYED or u_alive[o] <= 0:
			continue
		var g := _box_gap(u, o)
		if g <= r and (best < 0 or g < bd):
			best = o
			bd = g
	return best


## Pack p runs back to its handlers h.
func _pack_to(p: int, h: int) -> void:
	u_order[p] = O_MOVE
	u_target[p] = -1
	u_dx[p] = u_cx[h]
	u_dy[p] = u_cy[h]
	u_dface[p] = u_face[h]
	u_run[p] = 1
	u_dirty[p] = 1
	u_settled[p] = 0
	if obs_on != 0:
		u_pn[p] = 0


## Pack p is back with its handlers: its dogs go back in the kennel.
func _absorb(p: int) -> void:
	var base := u_slot_base[p]
	for s in u_alive[p]:
		var i := slot_soldier[base + s]
		state[i] = S_OFF
		target[i] = -1
		slot_of[i] = -1
		slot_soldier[base + s] = -1
	u_kept[p] = u_alive[p]
	u_alive[p] = 0
	u_state[p] = U_KENNEL
	u_order[p] = O_NONE
	u_target[p] = -1
	u_ftarget[p] = -1
	u_ret[p] = 0
	u_dogt[p] = 0
	u_fighting[p] = 0
	u_contact[p] = 0
	u_inreach[p] = 0
	u_down[p] = 0
	stat_absorbed += 1


func _check_winner() -> void:
	if winner >= 0:
		if ended == 0:
			var loser_on := 0
			for u in n_units:
				if winner < 2 and u_side[u] != winner and u_state[u] < U_DESTROYED and t_fixed[u_type[u]] == 0 \
						and u_hand[u] < 0:
					loser_on += 1
			if winner == 2 or loser_on == 0 or tick - decided_tick >= END_AFTER:
				ended = 1
		return
	# A side still fights while it has a ready unit that is not withdrawing
	# (a tower's engine does not hold a city on its own, nor a war dog pack
	# the field).
	var ready := [0, 0]
	for u in n_units:
		if u_state[u] == U_READY and u_order[u] != O_WITHDRAW and t_fixed[u_type[u]] == 0 and u_hand[u] < 0:
			ready[u_side[u]] += 1
	if ready[0] == 0 and ready[1] > 0:
		winner = 1
	elif ready[1] == 0 and ready[0] > 0:
		winner = 0
	elif (ready[0] == 0 and ready[1] == 0) or tick >= time_limit:
		winner = 2  # mutual destruction / both gone / time out
	if winner >= 0:
		decided_tick = tick


# ---------------------------------------------------------------- query ---

func alive_count(side: int = -1) -> int:
	var c := 0
	for u in n_units:
		if side < 0 or u_side[u] == side:
			c += u_alive[u]
	return c


func is_ai_side(side: int) -> bool:
	return ai_sides[side] != 0


## Projectiles in flight.
func projectiles_in_flight() -> int:
	return pr_count


## Battle outcome as plain data, for the result screen and the campaign:
## per unit how many soldiers started, were killed, routed off the field,
## withdrew, and are still on the field ("remaining"), and how many enemies
## its men killed ("kills"), plus side totals.
func result() -> Dictionary:
	var units: Array = []
	var sides: Array = []
	for s in 2:
		sides.append({"side": s, "started": 0, "killed": 0, "routed_off": 0,
			"withdrawn": 0, "remaining": 0})
	for u in n_units:
		var r := {"unit": u, "side": u_side[u], "type": u_otype[u],
			"started": u_count0[u], "killed": u_killed[u],
			"routed_off": u_routed_off[u], "withdrawn": u_withdrawn[u],
			"remaining": u_alive[u], "state": u_state[u], "kills": u_kills[u]}
		if u_hand[u] >= 0:
			# A war dog pack: its handlers' unit (its dogs with them count as remaining).
			r["pack_of"] = u_hand[u]
			r["remaining"] = u_alive[u] + u_kept[u]
		units.append(r)
		var t: Dictionary = sides[u_side[u]]
		for k in ["started", "killed", "routed_off", "withdrawn", "remaining"]:
			t[k] = int(t[k]) + int(r[k])
	return {"winner": winner, "decided_tick": decided_tick, "ended": ended,
		"tick": tick, "units": units, "sides": sides}


# ------------------------------------------------------------- snapshot ---

## Left out of snapshots: rebuilt identically by setup() from the same
## scenario and seed (the unit type tables t_*, the terrain grid) or
## view-only diagnostics that are large.
const _SNAP_SKIP := {"ter_h": true, "ter_gx": true, "ter_gy": true, "ter_info": true,
	"dbg_impacted": true, "veg": true, "obs": true, "obs_c": true, "obs_cd": true, "map_info": true,
	"ws_x0": true, "ws_y0": true, "ws_x1": true, "ws_y1": true, "ws_dir": true, "ng_x": true,
	"ng_y": true, "ng_gate": true, "ng_e0": true, "ng_to": true, "ng_w": true, "_dist_cache": true,
	"g_hw": true, "g_cit": true, "ws_e": true, "ws_fl": true, "sea_flee": true, "ws_nb": true,
	"ws_jx": true, "ws_jy": true, "_lw_x": true, "_lw_y": true, "_fl_mark": true, "cmp": true, "n_cmp": true, "g_cmp": true, "_croot": true, "_croot_ep": true}
const _SNAP_MAGIC := 0x31534353  # "SCS1"


## The whole simulation state as a compressed blob: every script variable
## (state arrays, scratch, RNG, tick, pending orders, diagnostics) except the
## ones setup() rebuilds. restore() on a sim set up with the same scenario
## and seed continues exactly as this one would (same hash, same future):
## used by live co-op battles for joining mid-battle, reconnects and desync
## recovery. Taken between steps.
func snapshot() -> PackedByteArray:
	var d := {}
	for p in get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var nm: String = p["name"]
		if nm.begins_with("t_") or _SNAP_SKIP.has(nm):
			continue
		d[nm] = get(nm)
	var raw := var_to_bytes(d)
	var z := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var out := PackedByteArray()
	out.resize(8)
	out.encode_u32(0, _SNAP_MAGIC)
	out.encode_u32(4, raw.size())
	out.append_array(z)
	return out


## Load a snapshot() blob into this sim, which must have been set up with
## the same scenario and seed. Returns false (and changes nothing) if the
## blob is damaged or belongs to another battle.
func restore(blob: PackedByteArray) -> bool:
	if blob.size() < 8 or blob.decode_u32(0) != _SNAP_MAGIC:
		return false
	var raw_size := blob.decode_u32(4)
	if raw_size <= 0 or raw_size > 256 << 20:
		return false
	var raw := blob.slice(8).decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != raw_size:
		return false
	var v = bytes_to_var(raw)
	if not (v is Dictionary):
		return false
	var d: Dictionary = v
	for k in ["n", "n_units", "n_eng", "ter_hash", "field_w", "field_h", "seed_value"]:
		if not d.has(k) or int(d[k]) != int(get(k)):
			return false
	var names := {}
	for p in get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			names[p["name"]] = true
	for k in d:
		if not names.has(k) or typeof(d[k]) != typeof(get(k)):
			return false
	for k in d:
		set(k, d[k])
	_croot_ep = -1  # (derived from the gates: recomputed on use)
	# Derived path distances: the tables this sim held (they decide which
	# units may plan this tick), for the gates as they are here.
	_dist_cache = {}
	if _dist_epoch == nav_epoch:
		for dst in _dist_have:
			_dist_cache[dst] = _dijkstra(dst)
	return true


## 32-bit hash of the full simulation state (MD5 of every state array).
func state_hash() -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	# Pending (future) orders are deliberately left out: in lockstep a peer
	# may already hold orders the other has not received yet.
	var header := PackedInt64Array([tick, rng_state, winner, decided_tick, ended,
		n, n_units, pr_free, pr_count, n_eng, ter_hash])
	ctx.update(header.to_byte_array())
	for arr in _soldier_hashed():
		ctx.update((arr as PackedInt32Array).to_byte_array())
	for arr in _unit_arrays():
		ctx.update((arr as PackedInt32Array).to_byte_array())
	ctx.update(u_walls.to_byte_array())
	ctx.update(slot_soldier.to_byte_array())
	ctx.update(off_x.to_byte_array())
	ctx.update(off_y.to_byte_array())
	for arr in _projectile_arrays():
		ctx.update((arr as PackedInt32Array).to_byte_array())
	ctx.update(pr_bucket.to_byte_array())
	if n_eng > 0:
		for arr in _engine_arrays():
			ctx.update((arr as PackedInt32Array).to_byte_array())
		for arr in _egroup_arrays():
			ctx.update((arr as PackedInt32Array).to_byte_array())
		if sg_on == 0:
			ctx.update(u_pick.to_byte_array())  # (engine pick-ups; with siege gear it is hashed below)
	ctx.update(ai_phase.to_byte_array())
	ctx.update(ai_t.to_byte_array())
	ctx.update(ai_hold.to_byte_array())
	if ai_skill[0] != AIProfile.AVERAGE or ai_skill[1] != AIProfile.AVERAGE \
			or ai_style[0] != AIProfile.BALANCED or ai_style[1] != AIProfile.BALANCED:
		# AI profiles other than the default (the default hashes as before).
		ctx.update(ai_skill.to_byte_array())
		ctx.update(ai_style.to_byte_array())
		ctx.update(ai_mist.to_byte_array())
		if not ai_mem.is_empty():
			ctx.update(ai_mem.to_byte_array())
	if map_on != 0:
		# Woods / settlement maps only (a plain map hashes as it always did).
		for arr in _map_unit_arrays():
			ctx.update((arr as PackedInt32Array).to_byte_array())
		ctx.update(pth_x.to_byte_array())
		ctx.update(pth_y.to_byte_array())
		ctx.update(tr_x.to_byte_array())
		ctx.update(tr_y.to_byte_array())
		ctx.update(PackedInt64Array([cap_t, nav_epoch, n_gates, ai_gate[0], ai_gate[1]]).to_byte_array())
		if cit_r > 0:
			ctx.update(ai_cit.to_byte_array())
		if city_on != 0:
			ctx.update(PackedInt64Array([cit_siege]).to_byte_array())
			ctx.update(ai_lay.to_byte_array())
		if obs_on != 0:
			for arr in _stair_arrays():
				ctx.update((arr as PackedInt32Array).to_byte_array())
			for arr in _flow_arrays():
				ctx.update((arr as PackedInt32Array).to_byte_array())
		if n_gates > 0:
			ctx.update(g_hp.to_byte_array())
			ctx.update(g_state.to_byte_array())
			ctx.update(g_burn.to_byte_array())
		ctx.update(ai_prog.to_byte_array())
	if dep_on != 0:
		# The deployment phase (battles without one hash as before).
		ctx.update(PackedInt64Array([phase, dep_ticks, dep_left, dep_need, dep_ready, dep_out]).to_byte_array())
		ctx.update(dep_z.to_byte_array())
	if time_limit != TIME_LIMIT:
		ctx.update(PackedInt64Array([time_limit]).to_byte_array())
	if sg_on != 0:
		# Siege equipment and tower engines (battles without them hash as before).
		for arr in _siege_unit_arrays():
			ctx.update((arr as PackedInt32Array).to_byte_array())
		if n_gates > 0:
			ctx.update(g_unbar.to_byte_array())
		if n_eq > 0:
			for arr in _equip_arrays():
				ctx.update((arr as PackedInt32Array).to_byte_array())
			ctx.update(q_lt.to_byte_array())
			ctx.update(q_stock.to_byte_array())
			if fw_on != 0:
				# Field works (battles without them hash as before).
				for arr in [q_face, q_len, q_seen, u_fws, u_fwc]:
					ctx.update((arr as PackedInt32Array).to_byte_array())
			if mt_on != 0:
				# Mantlets: which way each stands (battles without them hash as before).
				ctx.update(q_face.to_byte_array())
	if dog_on != 0:
		# War dogs (battles without handlers hash as before).
		for arr in _dog_arrays():
			ctx.update((arr as PackedInt32Array).to_byte_array())
	var digest := ctx.finish()
	return digest.decode_u32(0)


# ------------------------------------------------------- deployment phase ---
# A scenario with "deploy_time" (seconds) > 0 starts in PHASE_DEPLOY, as in
# Total War: nothing moves, shoots or loses heart; the players place their
# units inside their side's zone (ORDER_PLACE, applied at once: the men
# stand in their new places on the next step) and say they are ready
# (ORDER_READY). The battle starts at tick 0 once every player in dep_need
# is ready or the countdown (in deployment steps of a tick each) runs out.
# `tick` stays 0 meanwhile, so the battle's own timings (scripted orders,
# the AI's clocks, the time limit) start with the battle. AI sides deploy
# at once on field maps (the battle AI's deployment, its units placed where
# it sends them), so the players see the enemy line; on settlement maps the
# scenario's placement stands. Scripted and AI orders wait for the battle.
#
# Scenario keys: "deploy_time" (s), "deploy_need" (bit per player who must
# be ready; default 1 = player 0, or 0 when both sides are AI), and
# "deploy_zones": [[side, kind, x0_m, y0_m, x1_m, y1_m], ...] (DZ_RECT: a
# rectangle a placement is clamped into; DZ_INSIDE: settlement defenders,
# open ground inside the walls within the box - a placement elsewhere is
# refused; defenders who may man the walls are placed on a walkway when the
# point is on a wall). Without zones each side gets its half of the field
# beyond 30 m from the centre line.

func _setup_deploy(sc: Dictionary) -> void:
	phase = PHASE_BATTLE
	dep_on = 0
	dep_ticks = 0
	dep_left = 0
	dep_need = 0
	dep_ready = 0
	dep_z = PackedInt32Array()
	dep_out = -1
	var secs := int(sc.get("deploy_time", 0))
	if secs <= 0:
		return
	dep_on = 1
	dep_ticks = secs * TICKS_PER_SECOND
	dep_left = dep_ticks
	dep_need = int(sc.get("deploy_need", 0 if ai_sides[0] != 0 and ai_sides[1] != 0 else 1))
	var zones: Array = sc.get("deploy_zones", [])
	if zones.is_empty():
		for s in 2:
			var sy := 0
			var cnt := 0
			for u in n_units:
				if u_side[u] == s:
					sy += u_ay[u] / M
					cnt += 1
			var bottom := cnt > 0 and sy / cnt > field_h / M / 2
			var mid := field_h / M / 2
			zones.append([s, DZ_RECT, 0, mid + 30, field_w / M, field_h / M] if bottom else [s, DZ_RECT, 0, 0, field_w / M, mid - 30])
	for z in zones:
		var za: Array = z
		dep_z.append_array([int(za[0]), int(za[1]), int(za[2]) * M, int(za[3]) * M, int(za[4]) * M, int(za[5]) * M])
	if city_on != 0:
		for u in n_units:
			if u_side[u] != city_def:
				dep_out = _piece0(u_ax[u], u_ay[u])
				if dep_out >= 0:
					break
	if city_on == 0 and (ai_sides[0] != 0 or ai_sides[1] != 0):
		# The AI deploys now: its orders of tick 0, its units put where it
		# sends them (kept to its zone).
		var keep := pending_orders
		pending_orders = []
		BattleAI.think(self)
		_apply_orders()
		pending_orders.append_array(keep)
		for u in n_units:
			if ai_sides[u_side[u]] == 0 or u_state[u] != U_READY or u_order[u] != O_MOVE:
				continue
			var p := deploy_clamp(self, u_side[u], u_dx[u], u_dy[u])
			if p.z != 0:
				u_ax[u] = p.x
				u_ay[u] = p.y
				u_face[u] = u_dface[u]
			u_order[u] = O_NONE
			_place_unit(u, 0)
	phase = PHASE_DEPLOY


func _deploy_step() -> void:
	_dist_new = 0
	_apply_orders(50)
	if dep_left > 0:
		dep_left -= 1
	if dep_left <= 0 or dep_need == 0 or (dep_ready & dep_need) == dep_need:
		phase = PHASE_BATTLE
		dep_left = 0


## Seconds of the countdown left (deployment phase), else 0.
func deploy_secs_left() -> int:
	return (dep_left + TICKS_PER_SECOND - 1) / TICKS_PER_SECOND if phase == PHASE_DEPLOY else 0


## The raw piece of open ground at (x, y) with every gate shut (-1: none).
func _piece0(x: int, y: int) -> int:
	if n_cmp == 0 or x < 0 or y < 0:
		return -1
	var i := x >> 11
	var j := y >> 11
	if i >= ob_w or j >= ob_h:
		return -1
	return maxi(cmp[j * ob_w + i], -1)


## Where a placement of a unit of `side` at (x, y) goes: (x, y, 1) inside
## its zone, (x', y', 1) clamped into the nearest rectangle of its zone,
## (x, y, 0) refused (outside a settlement zone). No zone: the field.
static func deploy_clamp(sim, side: int, x: int, y: int) -> Vector3i:
	var best := Vector3i(clampi(x, 0, sim.field_w), clampi(y, 0, sim.field_h), 1)
	var best_d := -1
	var z: PackedInt32Array = sim.dep_z
	for k in range(0, z.size(), 6):
		if z[k] != side:
			continue
		var cx := clampi(x, z[k + 2], z[k + 4])
		var cy := clampi(y, z[k + 3], z[k + 5])
		if z[k + 1] == DZ_INSIDE:
			if cx == x and cy == y and sim._piece0(x, y) >= 0 and sim._piece0(x, y) != sim.dep_out:
				return Vector3i(x, y, 1)
			if best_d < 0:
				best = Vector3i(x, y, 0)
			continue
		var dd := (cx - x) * (cx - x) + (cy - y) * (cy - y)
		if dd == 0:
			return Vector3i(x, y, 1)
		if best_d < 0 or dd < best_d:
			best_d = dd
			best = Vector3i(cx, cy, 1)
	return best


## The placement rule (ORDER_PLACE in the deployment phase), on the order
## fields d; shared with OrderPreview. Sets d["placed"] = 1 (and d["wall"]:
## the walkway segment + 1, 0 the ground) when the unit is placed.
static func place_rule(sim, u: int, d: Dictionary, o: Dictionary) -> void:
	if UT.stat(sim.u_type[u], "fixed") != 0:
		return  # a tower's engine stays on its tower
	var side: int = sim.u_side[u]
	var ty: int = sim.u_type[u]
	var alive: int = sim.u_alive[u]
	var x := int(o.get("x", d["ax"]))
	var y := int(o.get("y", d["ay"]))
	var face := int(o.get("facing", d["face"])) & FM.ANGLE_MASK
	if can_man_walls(sim, u):
		var ws := wall_snap(sim, x, y)
		if ws.z >= 0:
			var wa := wall_anchor(sim, ws.z, ws.x, ws.y, alive, ty)
			d["ax"] = wa.x
			d["ay"] = wa.y
			d["face"] = wa.z
			d["files"] = wall_nf(alive)
			d["wall"] = ws.z + 1
			_placed(d)
			return
	var p := deploy_clamp(sim, side, x, y)
	if p.z == 0:
		return
	if sim.city_on != 0 and sim.n_cmp > 0 and sim._piece0(p.x, p.y) < 0:
		return  # a house, a wall, a gateway
	var nf: int = d["files"]
	if UT.cls(ty) != UT.CLS_ART:
		var f := int(o.get("files", d["files"]))
		if sim.u_wall[u] > 0 and not o.has("files"):
			f = ground_files(ty, alive)
		nf = clampi(f, mini(MIN_FILES, maxi(alive, 1)), maxi(alive, 1))
	if not place_clear(sim, u, p.x, p.y, face, nf):
		return  # inside another unit
	d["ax"] = p.x
	d["ay"] = p.y
	d["face"] = face
	d["files"] = nf
	d["wall"] = 0
	_placed(d)


## A unit u placed with its anchor at (x, y), facing `face`, `files` wide,
## is not inside another unit on the ground (units do not pass through each
## other): neither formation's middle lies within the other's rectangle.
static func place_clear(sim, u: int, x: int, y: int, face: int, files: int) -> bool:
	var ty: int = sim.u_type[u]
	var alive: int = maxi(sim.u_alive[u], 1)
	var f := clampi(files, 1, alive)
	var hw: int = (f - 1) * UT.stat(ty, "file_sp") / 2 + M / 2
	var dep: int = ((alive + f - 1) / f - 1) * UT.stat(ty, "rank_sp") + M / 2
	var c := FM.cos_a(face)
	var s := FM.sin_a(face)
	var mx := x - c * dep / 2 / FM.TRIG_ONE
	var my := y - s * dep / 2 / FM.TRIG_ONE
	# (Units placed in the same batch - a group dragged together - and units
	# with a placement still pending go where they are sent: not obstacles.)
	var moving := {}
	for k in sim._placing:
		moving[k] = true
	for po in sim.pending_orders:
		if int(po["type"]) == ORDER_PLACE:
			moving[int(po.get("unit", -1))] = true
	for o in sim.n_units:
		if o == u or sim.u_state[o] != U_READY or sim.u_alive[o] <= 0 or sim.u_wall[o] > 0 \
				or UT.stat(sim.u_type[o], "fixed") != 0 or moving.has(o):
			continue
		var oc := FM.cos_a(sim.u_face[o])
		var os := FM.sin_a(sim.u_face[o])
		var ohw: int = sim.unit_half_width(o) + M / 2
		var odep: int = sim.unit_depth(o) + M / 2
		# Our middle in its rectangle?
		var dx: int = mx - sim.u_ax[o]
		var dy: int = my - sim.u_ay[o]
		var fw := (dx * oc + dy * os) / FM.TRIG_ONE
		var lt := (-dx * os + dy * oc) / FM.TRIG_ONE
		if fw <= M and fw >= -odep and absi(lt) <= ohw:
			return false
		# Its middle in ours?
		var omx: int = sim.u_ax[o] - oc * odep / 2 / FM.TRIG_ONE
		var omy: int = sim.u_ay[o] - os * odep / 2 / FM.TRIG_ONE
		dx = omx - x
		dy = omy - y
		fw = (dx * c + dy * s) / FM.TRIG_ONE
		lt = (-dx * s + dy * c) / FM.TRIG_ONE
		if fw <= M and fw >= -dep and absi(lt) <= hw:
			return false
	return true


static func _placed(d: Dictionary) -> void:
	d["dface"] = d["face"]
	d["dx"] = d["ax"]
	d["dy"] = d["ay"]
	d["order"] = O_NONE
	d["target"] = -1
	d["gtarget"] = -1
	d["refill"] = 0
	d["placed"] = 1


## Put unit u's men (and engines) in their places at its anchor (the
## deployment phase), on the walkway segment wall - 1 (0: the ground).
func _place_unit(u: int, wall: int) -> void:
	var ty := u_type[u]
	if wall > 0:
		if u_wall[u] == 0:
			u_skirm[u] = 0
		u_wall[u] = wall
	elif u_wall[u] > 0:
		u_wall[u] = 0
		u_skirm[u] = t_skirm[ty]
	u_stair[u] = 0
	u_pn[u] = 0
	u_trn[u] = 0
	u_dx[u] = u_ax[u]
	u_dy[u] = u_ay[u]
	u_dface[u] = u_face[u]
	var ne := u_neng[u]
	if ne > 0:
		var c := FM.cos_a(u_face[u])
		var sn := FM.sin_a(u_face[u])
		for k in ne:
			var e := u_eng0[u] + k
			var lat := ((2 * k - (ne - 1)) * t_fsp[ty]) / 2
			e_x[e] = u_ax[u] + ((-lat * sn) / FM.TRIG_ONE)
			e_y[e] = u_ay[u] + ((lat * c) / FM.TRIG_ONE)
			e_face[e] = u_face[u]
			e_px[e] = e_x[e]
			e_py[e] = e_y[e]
	if obs_on != 0 and u < _u_obs.size():
		_u_obs[u] = _near_obs(u)
	_compute_offsets(u)
	var base := u_slot_base[u]
	for s in u_alive[u]:
		var i := slot_soldier[base + s]
		pos_x[i] = u_ax[u] + off_x[base + s]
		pos_y[i] = u_ay[u] + off_y[base + s]
		prev_x[i] = pos_x[i]
		prev_y[i] = pos_y[i]
		facing[i] = u_face[u]
		state[i] = S_FORMED
		target[i] = -1
	u_settled[u] = 0
	_update_bounds()
	if ter_on != 0 or obs_on != 0 or fwh_on != 0:
		u_h[u] = _unit_elev(u)


# ---------------------------------------------------------------- siege ---
# Siege equipment and wall towers (docs/DESIGN.md "Siege equipment and wall
# towers"). Cities are held by attrition at the wall, not by any bonus for
# standing inside it:
# - Tower engines: a walls-2/3 city mounts bolt throwers on its towers (by
#   the outer gates and at intervals) and, at walls 3, two stone throwers
#   on its biggest towers: immobile artillery units of the defenders
#   (UT "fixed"), on the tower as wall units, with a fixed load of shots
#   (more with a workshop), crews that can be shot, and a tower that enemy
#   batteries batter down (a shot aimed at the tower landing within it).
# - Siege equipment (q_*, scenario "equip"): the attackers' ladder sets and
#   rams are objects on the ground. Any attacking foot unit picks one up
#   (ORDER_PICKUP: it goes to it), carries it at its anchor (slowly, never
#   running, attacking nobody, defending poorly) and puts it down
#   (ORDER_DROP; routing or wiped out, it is left where they were).
# - Ladders: a unit carrying a set ordered onto a stretch of wall from
#   outside marches to the foot of the wall there (ST_LADDER_GO), plants
#   it (for the battle) and climbs (ST_LADDER); any infantry or missile
#   unit of its side ordered onto that stretch later climbs there too. The
#   men go up one at a time per ladder (LADDER_TICKS by wall level, the
#   set's five ladders shared by all who climb it), arriving on the walkway
#   where they fight the defenders; once all are up it is a wall unit
#   (down into the town by a stair; withdrawing or routing: back down the
#   ladders). Men who came up by ladders at the inside of a closed gate
#   unbar it.
# - The ram: carried to a closed gate's outer face (an outer gate, or the
#   citadel's from the town) its carriers batter it (RAM_DMG every RAM_WORK
#   man-ticks of at most RAM_CREW men) and put it down once it breaks;
#   walls-2/3 gates do not yield to swords at all (gate_hackable). Tower
#   bolts and stones can wreck it, defenders standing at it smash it.
# - The siege tower (EQ_TOWER): pushed like the ram (slower, slower again
#   with fewer than EQ_MEN men), planted against a walls-2/3 stretch like a
#   ladder set and crossed EQ_LANES abreast by any unit of either side;
#   anyone takes it up off the ground; it burns and is battered even
#   planted (EQ_EXPOSED). All of it by the per-kind EQ_* fields.
# All of it is state hashed when the battle has any (sg_on).

func _siege_unit_arrays() -> Array:
	return [u_carry, u_pick, u_lq, u_lfx, u_lfy, u_lacc, u_trad]


func _equip_arrays() -> Array:
	return [q_kind, q_x, q_y, q_state, q_unit, q_seg, q_wx, q_wy, q_hp, q_side, q_burn, q_tier, q_hn, q_hhp]


## The engines a walls-2/3 city mounts on its towers, as scenario unit
## dictionaries of the defending side (appended after the scenario's own
## units): bolt throwers on the towers by the outer gates, then on others
## nearest the main gate at least TOWER_SPACING m apart (TOWERS_MAX in
## all); at walls 3 first stone throwers on the biggest towers not by a
## gate (TOWERS_STONE). None on a citadel's towers or on the sea wall. City
## key "towers": 0 leaves them out; a workshop in "bld" loads them with
## TOWER_AMMO_PCT % of the shots. The generator's tower list in order,
## integers only.
func _siege_towers(sc: Dictionary) -> Array:
	var out: Array = []
	if city_on == 0 or city_walls < 2 or not map_info.has("city"):
		return out
	var cd: Dictionary = (sc.get("terrain", {}) as Dictionary).get("city", {})
	if int(cd.get("towers", 1)) == 0:
		return out
	var t_ammo := 100
	for b in cd.get("bld", []):
		if int(b) == TOWER_AMMO_BLD:
			t_ammo = TOWER_AMMO_PCT
	var lay: Dictionary = map_info["city"]
	var cx := int(lay["cx"])
	var cy := int(lay["cy"])
	var cit: Dictionary = lay.get("cit", {})
	var gates: Array = lay["gates"]
	var mx := cx
	var my := cy
	for gd in gates:
		if int(gd.get("cit", 0)) == 0:
			mx = int(gd["x"])
			my = int(gd["y"])
			break
	var cand: Array = []  # [x, y, r, by a gate, distance to the main gate]
	for tw in lay["towers"]:
		var x := int(tw[0])
		var y := int(tw[1])
		var r := int(tw[2])
		if not cit.is_empty() and FM.approx_len(x - int(cit["x"]), y - int(cit["y"])) < int(cit["rc"]) + r + 4:
			continue  # the citadel's
		var dx := x - cx
		var dy := y - cy
		var l := maxi(FM.isqrt(dx * dx + dy * dy), 1)
		if obs_kind((x + dx * (r + 12) / l) * M, (y + dy * (r + 12) / l) * M) == MapGen.C_WATER:
			continue  # on the sea wall
		var at_gate := 0
		for gd in gates:
			if int(gd.get("cit", 0)) != 0 or int(gd.get("tr", 0)) <= 0:
				continue
			if FM.approx_len(x - int(gd["x"]), y - int(gd["y"])) <= int(gd["hw"]) + 2 * int(gd["tr"]) + 2:
				at_gate = 1
		cand.append([x, y, r, at_gate, FM.approx_len(x - mx, y - my)])
	var order: Array = []
	for k in cand.size():
		order.append(k)
	order.sort_custom(func(a, b): return int(cand[a][4]) < int(cand[b][4]) \
		or (int(cand[a][4]) == int(cand[b][4]) and a < b))
	var picked: Array = []  # [candidate, type]
	var n_st: int = TOWERS_STONE[city_walls]
	if n_st > 0:
		var big: Array = order.duplicate()
		big.sort_custom(func(a, b): return int(cand[a][2]) > int(cand[b][2]) \
			or (int(cand[a][2]) == int(cand[b][2]) and (int(cand[a][4]) < int(cand[b][4]) \
			or (int(cand[a][4]) == int(cand[b][4]) and a < b))))
		for k in big:
			if picked.size() >= n_st:
				break
			if int(cand[k][3]) != 0 or not _tower_clear(cand, picked, k, 30):
				continue
			picked.append([k, UT.TOWER_STONE])
	var n_b: int = TOWERS_MAX[city_walls]
	var n_bolt := 0
	for pass_n in 2:
		for k in order:
			if n_bolt >= n_b:
				break
			var gate_t := int(cand[k][3]) != 0
			if gate_t != (pass_n == 0):
				continue
			var taken := false
			for pk in picked:
				if int(pk[0]) == k:
					taken = true
			if taken or (not gate_t and not _tower_clear(cand, picked, k, TOWER_SPACING)):
				continue
			picked.append([k, UT.TOWER_BOLT])
			n_bolt += 1
	for pk in picked:
		var c: Array = cand[int(pk[0])]
		var ty: int = pk[1]
		var face := FM.atan2_a(int(c[1]) - cy, int(c[0]) - cx)
		out.append({"side": city_def, "type": ty, "count": UT.stat(ty, "crew"), "x_m": int(c[0]),
			"y_m": int(c[1]), "facing": face, "files": 1, "tower_r": int(c[2]), "tower_ammo": t_ammo,
			"ak": int(sc.get("tower_ak", -1))})  # (setup keeps it where it rides on the engine's kind)
	return out


## Candidate k of _siege_towers is at least `gap` m from every tower picked.
static func _tower_clear(cand: Array, picked: Array, k: int, gap: int) -> bool:
	for pk in picked:
		var c: Array = cand[int(pk[0])]
		if FM.approx_len(int(c[0]) - int(cand[k][0]), int(c[1]) - int(cand[k][1])) < gap:
			return false
	return true


## Unit u is a tower's engine.
func is_tower(u: int) -> bool:
	return t_fixed[u_type[u]] != 0


## Siege equipment at setup: scenario "equip" [[kind (EQ_*), x_m, y_m],
## ...], the attackers' (the side not defending the city), on the ground
## where the scenario puts them (behind the attackers' line). Only on a
## settlement map with walls; any piece makes the battle a siege-gear one
## (sg_on).
func _setup_equip(sc: Dictionary, units: Array) -> void:
	var lst: Array = sc.get("equip", [])
	if city_on == 0 or ws_x0.size() == 0:
		lst = []
	# Ammunition wagons (any map): one per wagon unit, on its men's
	# shoulders (carried) where it stands, after the scenario's pieces.
	var wag: Array[int] = []
	for u in units.size():
		if UT.stat(int(units[u]["type"]), "wagon") >= 0:
			wag.append(u)
	var fws := _field_works(sc, units)
	var mts := _mantlets_at_setup(sc, units)
	n_eq = lst.size() + wag.size() + fws.size() + mts.size()
	for arr in _equip_arrays():
		arr.resize(n_eq)
		arr.fill(0)
	for arr in [q_face, q_len, q_seen]:
		arr.resize(n_eq)
		arr.fill(0)
	q_lt.resize(n_eq * LANES_MAX)
	q_lt.fill(0)
	q_unit.fill(-1)
	q_seg.fill(-1)
	q_tier.fill(-1)
	var nak := UT.AMMO.size()
	q_stock.resize(n_eq * nak)
	q_stock.fill(0)
	for q in lst.size():
		var e: Array = lst[q]
		var ek := int(e[0])
		q_kind[q] = ek if ek == EQ_RAM or ek == EQ_TOWER else EQ_LADDERS
		q_x[q] = clampi(int(e[1]) * M, 0, field_w)
		q_y[q] = clampi(int(e[2]) * M, 0, field_h)
		q_state[q] = Q_GROUND
		q_hp[q] = EQ_HP[q_kind[q]]
		q_side[q] = 1 - city_def
	for k in wag.size():
		var q := lst.size() + k
		var u := wag[k]
		var ud: Dictionary = units[u]
		var w := UT.stat(int(ud["type"]), "wagon")
		q_kind[q] = EQ_WAGON
		q_tier[q] = w
		q_x[q] = clampi(int(ud["x_m"]) * M, 0, field_w)
		q_y[q] = clampi(int(ud["y_m"]) * M, 0, field_h)
		q_state[q] = Q_CARRIED
		q_unit[q] = u
		u_carry[u] = q
		q_side[q] = int(ud["side"])
		q_hp[q] = UT.wagon_stat(w, "hp")
		q_hn[q] = UT.wagon_stat(w, "horses")
		q_hhp[q] = UT.wagon_stat(w, "horse_hp")
		# Stock: each standard kind's hand-cart amount x the tier's %; each
		# special kind it carries (scenario "aks": its army's) that x the
		# kind's share.
		var pct := UT.wagon_stat(w, "stock_pct")
		for a in nak:
			if UT.ammo_stat(a, "base") < 0:
				q_stock[q * nak + a] = UT.ammo_stat(a, "wagon") * pct / 100
		for ak in ud.get("aks", []):
			var a := int(ak)
			var b := UT.ammo_stat(a, "base")
			if a >= 0 and a < nak and b >= 0:
				q_stock[q * nak + a] = UT.ammo_stat(b, "wagon") * pct / 100 * UT.ammo_stat(a, "share") / 100
	# Field works (field maps): after the siege pieces and the wagons.
	fw_on = 1 if not fws.is_empty() else 0
	fwh_on = 0
	u_fws.resize(n_units)
	u_fws.fill(100)
	u_fwc.resize(n_units)
	u_fwc.fill(0)
	var q0 := lst.size() + wag.size()
	for k in fws.size():
		var f: Array = fws[k]
		var q := q0 + k
		q_kind[q] = int(f[0])
		q_side[q] = int(f[1])
		q_x[q] = int(f[2])
		q_y[q] = int(f[3])
		q_face[q] = int(f[4])
		q_len[q] = int(f[5])
		q_state[q] = int(f[6])
		q_hp[q] = EQ_HP[q_kind[q]]
		q_seen[q] = (1 << q_side[q]) if EQ_HIDE[q_kind[q]] != 0 else 3
		if EQ_H[q_kind[q]] != 0:
			fwh_on = 1
	# Mantlets (any map): last, standing before their units.
	mt_on = 1 if not mts.is_empty() else 0
	var qm := q0 + fws.size()
	for k in mts.size():
		var m: Array = mts[k]
		var q := qm + k
		q_kind[q] = EQ_MANTLET
		q_side[q] = int(m[0])
		q_x[q] = int(m[1])
		q_y[q] = int(m[2])
		q_face[q] = int(m[3])
		q_state[q] = Q_GROUND
		q_hp[q] = EQ_HP[EQ_MANTLET]
		q_seen[q] = 3
	wag_h = 0
	for q in n_eq:
		wag_h += q_hn[q]
	if n_eq > 0:
		sg_on = 1


## Full hit points of wagon q (its tier's).
func _wagon_hp0(q: int) -> int:
	return UT.wagon_stat(q_tier[q], "hp")


## Piece q, if a wagon, is lost: its stock with it.
func _wagon_lost(q: int) -> void:
	if q_kind[q] != EQ_WAGON:
		return
	var nak := UT.AMMO.size()
	for a in nak:
		q_stock[q * nak + a] = 0


## The pace (per tick) of a unit walking at `walk` carrying a piece of kind
## k (not a wagon) with `men` men: EQ_WALK_PCT of the walk, at most EQ_PACE,
## and with fewer than EQ_MEN men that times men / EQ_MEN (at least a
## quarter). Shared with the view.
static func carry_pace(walk: int, k: int, men: int) -> int:
	var sp := walk * EQ_WALK_PCT[k] / 100
	if EQ_PACE[k] > 0:
		sp = mini(sp, EQ_PACE[k])
	var need := EQ_MEN[k]
	if need > 0 and men < need:
		sp = sp * maxi(men, need / 4) / need
	return sp


## Unit u carries the ram.
func carries_ram(u: int) -> bool:
	var c := u_carry[u]
	return c >= 0 and q_kind[c] == EQ_RAM


## What unit u carries: 0 nothing, else its kind (EQ_*).
static func carrying(sim, u: int) -> int:
	if u >= sim.u_carry.size() or sim.u_carry[u] < 0:
		return 0
	return sim.q_kind[sim.u_carry[u]]


## Ladders unit u goes up by (a set: LADDER_SET; a siege tower: its lanes), 0 if it is not on a ladder move.
static func ladders_of(sim, u: int) -> int:
	if u >= sim.u_lq.size() or sim.u_lq[u] < 0:
		return 0
	return EQ_LANES[sim.q_kind[sim.u_lq[u]]]


## Why unit u cannot pick up piece q ("" if it can): attacking foot (not
## horses or engines) on the ground, carrying nothing, the piece on the
## ground and on its own ground. Shared with the view.
static func pickup_refusal(sim, u: int, q: int) -> String:
	if q < 0 or q >= sim.n_eq:
		return "Nothing to pick up there"
	var k: int = sim.q_kind[q]
	var wag: bool = k == EQ_WAGON
	if sim.q_side[q] != sim.u_side[u] and EQ_ANY[k] == 0:
		return "Only the attackers use siege equipment"
	if sim.q_state[q] == Q_PLANTED:
		if EQ_EXPOSED[k] != 0:
			return "A planted siege tower stays against the wall: order foot onto that wall to cross"
		return "Planted ladders stay against the wall: order foot onto that wall to climb"
	if sim.q_state[q] == Q_WRECKED:
		if EQ_SCREEN[k] != 0:
			return "The mantlet is wrecked"
		return "The wagon is wrecked" if wag else ("The siege tower is wrecked" if EQ_LANES[k] > 0 else "The ram is wrecked")
	if sim.q_state[q] == Q_CARRIED:
		if wag and sim.u_side[sim.q_unit[q]] != sim.u_side[u]:
			return "The enemy has this wagon: drive its men off first"
		return "Another unit carries it"
	var c: int = sim.u_cls[u]
	if c == UT.CLS_CAV:
		return "Cavalry cannot pull a wagon" if wag else "Cavalry cannot carry siege equipment"
	if c == UT.CLS_ART:
		return "Engines cannot carry siege equipment"
	if EQ_SCREEN[k] != 0 and sim.t_mount[sim.u_type[u]] != UT.MOUNT_FOOT:
		return "Only men on foot carry a mantlet"
	if sim.u_wall[u] > 0 or sim.u_stair[u] != 0:
		return "Down off the wall first"
	if sim.u_carry[u] >= 0:
		return "Already carrying something: put it down first (Drop)"
	var ra: int = sim.reach_at(sim.u_ax[u], sim.u_ay[u])
	var rq: int = sim.reach_at(sim.q_x[q], sim.q_y[q])
	if ra >= 0 and rq >= 0 and ra != rq:
		return "No way to it from here"
	return ""


## Unit u (going to pick up u_pick) is within PICK_R of it: it picks it up
## and stops there; a piece gone meanwhile (taken, wrecked) is forgotten.
func _pick_check(u: int) -> void:
	var q := u_pick[u]
	if q < 0:
		return
	if q >= PICK_ENG:
		_pick_engines(u, q - PICK_ENG)
		return
	if u_state[u] != U_READY or q_state[q] != Q_GROUND or u_carry[u] >= 0 or u_wall[u] > 0:
		u_pick[u] = -1
		return
	if FM.approx_len(u_ax[u] - q_x[q], u_ay[u] - q_y[q]) > PICK_R:
		return
	q_state[q] = Q_CARRIED
	q_unit[q] = u
	u_carry[u] = q
	u_pick[u] = -1
	u_run[u] = 0
	u_refill[u] = 0
	u_forage[u] = 0
	if EQ_ANY[q_kind[q]] != 0 and q_side[q] != u_side[u]:
		q_side[q] = u_side[u]  # taken over by the other side
		if q_kind[q] == EQ_WAGON:
			stat_wagon_taken += 1
		elif EQ_SCREEN[q_kind[q]] == 0:
			stat_stw_taken += 1
	if u_order[u] == O_MOVE:
		u_order[u] = O_NONE
		u_dx[u] = u_ax[u]
		u_dy[u] = u_ay[u]
	u_settled[u] = 0
	stat_pickups += 1


## Unit u puts down what it carries, at its anchor (where it stands); a
## mantlet stands facing the way the unit faces.
func _drop(u: int) -> void:
	var q := u_carry[u]
	if q < 0:
		return
	u_carry[u] = -1
	q_state[q] = Q_GROUND
	q_unit[q] = -1
	q_x[q] = clampi(u_ax[u], 0, field_w)
	q_y[q] = clampi(u_ay[u], 0, field_h)
	if EQ_SCREEN[q_kind[q]] != 0:
		q_face[q] = u_face[u]
	stat_drops += 1


## Siege equipment once a tick: a carried piece goes with its carriers'
## anchor (left where it is if they are gone or routed); planted ladders
## make ready the next man up (a set brings one up every LADDER_TICKS /
## LADDER_SET ticks between all the units climbing it); a ram on the
## ground is smashed by defenders standing at it; units going to pick a
## piece up take it once there.
func _update_equip() -> void:
	for q in n_eq:
		var st := q_state[q]
		if st == Q_CARRIED:
			var u := q_unit[q]
			if u < 0 or u_state[u] != U_READY or u_alive[u] <= 0 or u_carry[u] != q:
				if u >= 0 and u_carry[u] == q:
					u_carry[u] = -1
				if u >= 0 and EQ_SCREEN[q_kind[q]] != 0:
					q_face[q] = u_face[u]
				q_state[q] = Q_GROUND
				q_unit[q] = -1
				stat_drops += 1
			else:
				q_x[q] = u_ax[u]
				q_y[q] = u_ay[u]
		elif st == Q_GROUND and EQ_SMASH[q_kind[q]] != 0:
			# The enemy at a ram or siege tower left on the ground smash it (a sally).
			var qx := q_x[q]
			var qy := q_y[q]
			var r := ENGINE_NEAR
			var men := 0
			for u in n_units:
				if u_side[u] == q_side[q] or u_state[u] != U_READY or u_alive[u] <= 0 or u_wall[u] > 0:
					continue
				if u_maxx[u] < qx - r or u_minx[u] > qx + r or u_maxy[u] < qy - r or u_miny[u] > qy + r:
					continue
				var base := u_slot_base[u]
				for s in u_alive[u]:
					var i := slot_soldier[base + s]
					if state[i] < S_DEAD and absi(pos_x[i] - qx) <= r and absi(pos_y[i] - qy) <= r:
						men += 1
			if men > 0:
				q_hp[q] -= RAM_WRECK * mini(men, 6)
				if q_hp[q] <= 0:
					q_state[q] = Q_WRECKED
					if q_kind[q] == EQ_RAM:
						stat_ram_wrecked += 1
					else:
						stat_stw_wrecked += 1
	for u in n_units:
		if u_pick[u] >= 0 and u_pick[u] < PICK_ENG:
			_pick_check(u)


## A bolt or stone landing at (x, y) within RAM_HIT_R of a ram (carried or
## on the ground) takes dmg off it; at 0 it is wrecked (dropped).
func _ram_hit(x: int, y: int, dmg: int) -> void:
	for q in n_eq:
		var kq := q_kind[q]
		var st := q_state[q]
		if EQ_SHOT[kq] == 0 or (st != Q_GROUND and st != Q_CARRIED and (st != Q_PLANTED or EQ_EXPOSED[kq] == 0)):
			continue
		var qc := eq_centre(q)
		if absi(qc.x - x) > RAM_HIT_R or absi(qc.y - y) > RAM_HIT_R:
			continue
		if kq == EQ_WAGON and q_hn[q] > 0:
			_horse_wound(q, dmg)  # (the team in the traces takes it too)
		q_hp[q] -= dmg
		if q_hp[q] <= 0:
			_eq_wreck(q)
			if kq == EQ_RAM:
				stat_ram_wrecked += 1


## Ticks between men up each lane of planted piece q: its kind's EQ_CLIMB,
## else (ladders) LADDER_TICKS by wall level.
static func climb_per(sim, q: int) -> int:
	var c: int = EQ_CLIMB[sim.q_kind[q]]
	return c if c > 0 else LADDER_TICKS[sim.city_walls]


## Swords can break gate g (walls 0-1: GATE_HACK_BY_WALLS of a few per cent
## or more); walls-2/3 gates are bound with iron and yield only to a ram or
## artillery, so foot are never sent at them (nobody hacks at a wall).
static func gate_hackable(sim, _g: int) -> bool:
	return GATE_HACK_BY_WALLS[sim.city_walls] >= 5


## Unit u may go up a wall by ladders: an attacking foot unit on the ground
## (not carrying the ram) that carries a ladder set (pikes too: they plant
## it but do not climb) or, infantry and missile troops, with a set of its
## side planted somewhere. Which stretch: ladder_set_for.
static func may_ladder(sim, u: int) -> bool:
	if sim.n_eq == 0 or sim.city_on == 0 or sim.ws_x0.size() == 0:
		return false
	if sim.u_wall[u] > 0:
		return false
	var att: bool = sim.u_side[u] != sim.city_def
	var c: int = sim.u_cls[u]
	var k := carrying(sim, u)
	if k != 0:
		if EQ_LANES[k] == 0 or sim.city_walls < EQ_WALLS[k] or not att:
			return false
		return c == UT.CLS_INF or c == UT.CLS_MISSILE or c == UT.CLS_PIKE
	if c != UT.CLS_INF and c != UT.CLS_MISSILE:
		return false
	var ra: int = -2
	for q in sim.n_eq:
		if sim.q_state[q] != Q_PLANTED:
			continue
		if att and sim.q_side[q] == sim.u_side[u]:
			return true
		if EQ_ANY[sim.q_kind[q]] != 0:
			# A planted siege tower serves either side: defenders only from
			# outside the walls (the tower's foot on their own ground).
			if att:
				return true
			if ra == -2:
				ra = sim.reach_at(sim.u_ax[u], sim.u_ay[u])
			if ra >= 0 and sim.reach_at(sim.q_x[q], sim.q_y[q]) == ra:
				return true
	return false


## The ladder set unit u would go up stretch sg by, ordered to its walkway
## point (x, y): the set it carries (planted there: a foot outside the wall
## it can reach), else a set of its side already planted on sg (its foot
## reachable; infantry and missile troops), -1 none.
static func ladder_set_for(sim, u: int, sg: int, x: int, y: int) -> int:
	if not may_ladder(sim, u) or sg < 0:
		return -1
	var c: int = sim.u_carry[u]
	if c >= 0:
		return c if ladder_ok(sim, u, sg, x, y) else -1
	var ra: int = sim.reach_at(sim.u_ax[u], sim.u_ay[u])
	for q in sim.n_eq:
		if sim.q_state[q] == Q_PLANTED and sim.q_seg[q] == sg \
				and (sim.q_side[q] == sim.u_side[u] or EQ_ANY[sim.q_kind[q]] != 0) \
				and ra >= 0 and sim.reach_at(sim.q_x[q], sim.q_y[q]) == ra:
			return q
	return -1


## The foot of the ladders against stretch sg at its walkway point (x, y):
## out along the stretch's outward direction past the wall's outer face, a
## metre onto the open ground (or ditch) beyond, as (x, y, 1); z 0 if a
## tower, gate or the sea is in the way, or the stretch is the citadel's or
## the sea's. Shared with the view's preview.
static func ladder_foot(sim, sg: int, x: int, y: int) -> Vector3i:
	if sg < 0 or (sim.ws_fl[sg] & (MapGen.SEG_SEA | MapGen.SEG_CIT)) != 0:
		return Vector3i(x, y, 0)
	var c := FM.cos_a(sim.ws_dir[sg])
	var s := FM.sin_a(sim.ws_dir[sg])
	var a := 0
	var lim: int = sim.wall_t + 6 * M
	while a <= lim:
		a += M / 2
		var k: int = sim.obs_kind(x + c * a / FM.TRIG_ONE, y + s * a / FM.TRIG_ONE)
		if k == MapGen.C_OPEN or k == MapGen.C_DITCH:
			var fx := x + c * (a + M) / FM.TRIG_ONE
			var fy := y + s * (a + M) / FM.TRIG_ONE
			if (sim.nav_at(fx, fy) & (MapGen.NAV_GROUND | MapGen.NAV_DITCH)) == 0:
				return Vector3i(x, y, 0)
			return Vector3i(fx, fy, 1)
		if k != MapGen.C_WALL and k != MapGen.C_WALK:
			return Vector3i(x, y, 0)
	return Vector3i(x, y, 0)


## A ladder move for unit u to walkway point (x, y) of stretch sg is
## possible: a foot outside the wall there on the unit's own ground.
static func ladder_ok(sim, u: int, sg: int, x: int, y: int) -> bool:
	var lf := ladder_foot(sim, sg, x, y)
	if lf.z == 0:
		return false
	var ra: int = sim.reach_at(sim.u_ax[u], sim.u_ay[u])
	return ra >= 0 and sim.reach_at(lf.x, lf.y) == ra


## Unit u goes up stretch sg by ladder set q: the set it carries, to be
## planted below walkway point (x, y), or a set already planted there (its
## foot and walkway point). It marches to the foot of the wall.
func _start_ladder(u: int, q: int, sg: int, x: int, y: int) -> void:
	var lf := Vector3i(q_x[q], q_y[q], 1)
	if q_state[q] == Q_PLANTED:
		sg = q_seg[q]
		x = q_wx[q]
		y = q_wy[q]
	else:
		lf = ladder_foot(self, sg, x, y)
	u_lq[u] = q
	u_sseg[u] = sg
	u_stair[u] = ST_LADDER_GO
	u_st0[u] = tick
	u_wx[u] = x
	u_wy[u] = y
	u_lfx[u] = lf.x
	u_lfy[u] = lf.y
	# It marches to a point a few metres out from the foot (open ground the
	# street paths reach: a foot squeezed beside a tower has no clear line
	# to any path node) and goes up from within LADDER_NEAR of the foot.
	var ap := ladder_approach(self, sg, lf.x, lf.y)
	u_dx[u] = ap.x
	u_dy[u] = ap.y
	u_dface[u] = (ws_dir[sg] + 512) & FM.ANGLE_MASK
	u_pn[u] = 0


## Where a unit going up ladders with their foot at (fx, fy) against
## stretch sg marches to (its men then walk to their ladders from there):
## out from the foot along the stretch's outward direction, the first point
## at least 5 m out on firm ground with room round it (2.5 m every way:
## clear of a tower's corner; past a ditch: the street paths go round a
## ditch, men wade it) with nothing but ground or ditch back to the foot,
## at most 24 m out; else the foot. Shared with the view's preview.
static func ladder_approach(sim, sg: int, fx: int, fy: int) -> Vector2i:
	var c := FM.cos_a(sim.ws_dir[sg])
	var s := FM.sin_a(sim.ws_dir[sg])
	var gd := MapGen.NAV_GROUND | MapGen.NAV_DITCH
	for d in range(1, 25):
		var x: int = fx + c * d * M / FM.TRIG_ONE
		var y: int = fy + s * d * M / FM.TRIG_ONE
		var nv: int = sim.nav_at(x, y)
		if (nv & gd) == 0:
			break  # (a tower, a house, the sea: stop at the last good point)
		if d >= 5 and (nv & MapGen.NAV_DITCH) == 0 and (nv & MapGen.NAV_GROUND) != 0 \
				and (sim.nav_at(x + 2560, y) & gd) != 0 and (sim.nav_at(x - 2560, y) & gd) != 0 \
				and (sim.nav_at(x, y + 2560) & gd) != 0 and (sim.nav_at(x, y - 2560) & gd) != 0:
			return Vector2i(x, y)
	return Vector2i(fx, fy)


## Unit u on its way to its ladders' foot is near enough to start: its
## anchor within LADDER_NEAR of the foot with nothing in the way (a march
## along the wall would otherwise end pressing its men into it).
func _ladder_reached(u: int) -> bool:
	var fx := u_lfx[u]
	var fy := u_lfy[u]
	var ax := u_ax[u]
	var ay := u_ay[u]
	if FM.approx_len(ax - fx, ay - fy) > LADDER_NEAR:
		return false
	var gm := MapGen.NAV_GROUND | MapGen.NAV_DITCH
	for k in range(1, 5):
		if (nav_at(ax + (fx - ax) * k / 4, ay + (fy - ay) * k / 4) & gm) == 0:
			return false
	return true


## At the foot of the wall: a set it carries is planted there (for the
## battle); then the climb begins (not pikes: they stand). The unit takes
## the stretch (its wall line at the point it was ordered to); its men go
## up one at a time per ladder (_ladder_step).
func _ladder_start(u: int) -> void:
	var sg := u_sseg[u]
	var q := u_lq[u]
	if q >= 0 and u_carry[u] == q:
		u_carry[u] = -1
		q_unit[q] = -1
		q_state[q] = Q_PLANTED
		q_seg[q] = sg
		q_x[q] = u_lfx[u]
		q_y[q] = u_lfy[u]
		q_wx[q] = u_wx[u]
		q_wy[q] = u_wy[u]
		stat_planted += 1
		if q_kind[q] == EQ_TOWER:
			stat_stw_planted += 1
	if q < 0 or q_state[q] != Q_PLANTED or u_cls[u] == UT.CLS_PIKE:
		u_stair[u] = 0  # (pikes plant the ladders but do not climb)
		u_lq[u] = -1
		return
	u_stair[u] = ST_LADDER
	u_st0[u] = tick
	u_wall[u] = sg + 1
	var wa := wall_anchor(self, sg, u_wx[u], u_wy[u], u_alive[u], u_type[u])
	u_files[u] = wall_nf(u_alive[u])
	u_ax[u] = wa.x
	u_ay[u] = wa.y
	u_face[u] = wa.z
	u_dface[u] = wa.z
	u_order[u] = O_NONE
	u_target[u] = -1
	u_gtarget[u] = -1
	u_run[u] = 0
	u_skirm[u] = 0
	u_sq[u] = 0
	u_trn[u] = 0
	u_pn[u] = 0
	u_dirty[u] = 1
	u_settled[u] = 0



## Ladder k's foot of climbing unit u (k of n ladders, LADDER_GAP apart
## along the wall about the unit's foot point).
func _ladder_k_foot(u: int, k: int, n_l: int) -> Vector2i:
	var dir := ws_dir[u_sseg[u]]
	var gap: int = EQ_LANE_GAP[q_kind[u_lq[u]]] if u_lq[u] >= 0 else LADDER_GAP
	var off := (2 * k - (n_l - 1)) * gap / 2
	return Vector2i(u_lfx[u] - FM.sin_a(dir) * off / FM.TRIG_ONE, u_lfy[u] + FM.cos_a(dir) * off / FM.TRIG_ONE)


## Ladder k's foot of planted set q (LADDER_SET ladders LADDER_GAP apart
## along its stretch about the set's foot). For the view.
func set_ladder_foot(q: int, k: int) -> Vector2i:
	var dir := ws_dir[q_seg[q]]
	var off := (2 * k - (EQ_LANES[q_kind[q]] - 1)) * EQ_LANE_GAP[q_kind[q]] / 2
	return Vector2i(q_x[q] - FM.sin_a(dir) * off / FM.TRIG_ONE, q_y[q] + FM.cos_a(dir) * off / FM.TRIG_ONE)


## (x, y) is on a walkway or in a tower.
func _on_walk(x: int, y: int) -> bool:
	var k := obs_kind(x, y)
	return k == MapGen.C_WALK or k == MapGen.C_TOWER


## A climbing unit, once a tick (docs/DESIGN.md "Units flow into the
## space"): each man still below picks a ladder of the set, nearest men
## first (the way to its foot plus LADDER_QCOST for each man already in its
## queue; ties to the lower ladder) and waits in its queue, two abreast back from
## the foot (_lw_x / _lw_y, read by _stair_leave). Every ladder takes the
## first man of its queue up once he is within LADDER_AT of its foot and
## the ladder is free (q_lt: a man up each lane every climb_per ticks, all
## lanes at once); he steps onto the walkway above his ladder, defenders
## there or not (a rule holding a ladder whose top was crowded was tried
## and dropped: it cut defended escalades from 77 to 55 men up). Once every man is up the climb is over (a move given while
## climbing then goes on, down a stair); with a ladder free and nobody at
## its foot for LADDER_STALL ticks the climb is given up and all come back
## down the ladders (_ladder_down): no man is ever left below.
## (Until 2026-10-09 the next man was the first in slot order within
## LADDER_NEAR of the set's middle, so men waiting farther off never went
## up while the unit refused orders.)
func _ladder_step(u: int) -> void:
	var q := u_lq[u]
	if q < 0 or q_state[q] != Q_PLANTED:
		_ladder_down(u)  # (the set is gone)
		stat_ladder_cut += 1
		return
	var base := u_slot_base[u]
	var alive := u_alive[u]
	var n_l := clampi(ladders_of(self, u), 1, LANES_MAX)
	var sg := u_sseg[u]
	var per := climb_per(self, q)
	var gm := _ground_mask(u)
	var oc := FM.cos_a(ws_dir[sg])  # (outward from the wall)
	var os := FM.sin_a(ws_dir[sg])
	var lfx := PackedInt32Array()
	var lfy := PackedInt32Array()
	var ltx := PackedInt32Array()
	var lty := PackedInt32Array()
	var ok := PackedInt32Array()
	var qn := PackedInt32Array()
	for arr in [lfx, lfy, ltx, lty, ok, qn]:
		arr.resize(n_l)
		arr.fill(0)
	var n_ok := 0
	for k in n_l:
		var f := _ladder_k_foot(u, k, n_l)
		var top := seg_pt(self, sg, seg_t(self, sg, f.x, f.y))
		if obs_kind(top.x, top.y) != MapGen.C_WALK:
			top = Vector2i(u_wx[u], u_wy[u])
		lfx[k] = f.x
		lfy[k] = f.y
		ltx[k] = top.x
		lty[k] = top.y
		if (nav_at(f.x, f.y) & gm) != 0:
			ok[k] = 1
			n_ok += 1
	if n_ok == 0:
		# (No lane's foot on open ground: the set's own foot, which is.)
		var kc := n_l / 2
		ok[kc] = 1
		lfx[kc] = u_lfx[u]
		lfy[kc] = u_lfy[u]
	# Men below, in slot order.
	var keys := PackedInt32Array()
	for s in alive:
		var i := slot_soldier[base + s]
		if state[i] >= S_DEAD:
			continue
		var x := pos_x[i]
		var y := pos_y[i]
		if _on_walk(x, y):
			continue
		_lw_x[base + s] = x
		_lw_y[base + s] = y
		if state[i] == S_DOWN:
			continue  # (lying where he fell: no queue yet)
		keys.append(s)
	var below := keys.size()
	if below == 0:
		var still := false
		for s in alive:
			var i := slot_soldier[base + s]
			if state[i] < S_DEAD and not _on_walk(pos_x[i], pos_y[i]):
				still = true  # (a man knocked down below: wait for him)
		if not still:
			u_stair[u] = 0
			u_settled[u] = 0
			u_dirty[u] = 1
			stat_ladder_done += 1
			if u_order[u] == O_MOVE and u_state[u] == U_READY:
				_start_descent(u)  # (a move given while it climbed: on from the wall)
		return
	var lat_x := -os  # (along the wall)
	var lat_y := oc
	var climbed := 0
	var free := false  # some ladder free and nobody at its foot
	for key in keys:
		var s := int(key)
		var i := slot_soldier[base + s]
		var x := pos_x[i]
		var y := pos_y[i]
		var bk := -1
		var bc := 0
		for k in n_l:
			if ok[k] == 0:
				continue
			var c := FM.approx_len(x - lfx[k], y - lfy[k]) + qn[k] * LADDER_QCOST
			if bk < 0 or c < bc:
				bk = k
				bc = c
		var j := qn[bk]
		if j == 0 and tick >= q_lt[q * LANES_MAX + bk]:
			if FM.approx_len(x - lfx[bk], y - lfy[bk]) <= LADDER_AT:
				# Up he goes: onto the walkway above his ladder.
				q_lt[q * LANES_MAX + bk] = tick + per
				pos_x[i] = ltx[bk]
				pos_y[i] = lty[bk]
				prev_x[i] = ltx[bk]
				prev_y[i] = lty[bk]
				facing[i] = ws_dir[sg]
				target[i] = -1
				state[i] = S_FORMED
				climbed += 1
				stat_ladder_up += 1
				if EQ_EXPOSED[q_kind[q]] != 0:
					stat_stw_up += 1
				continue
			free = true
		qn[bk] = j + 1
		var sd := LADDER_QW if (j & 1) != 0 else -LADDER_QW
		var bkd := (j >> 1) * LADDER_QSP
		_lw_x[base + s] = lfx[bk] + (lat_x * sd + oc * bkd) / FM.TRIG_ONE
		_lw_y[base + s] = lfy[bk] + (lat_y * sd + os * bkd) / FM.TRIG_ONE
	if climbed > 0:
		u_settled[u] = 0
		u_st0[u] = tick
		u_stuck[u] = 0  # (men up: the climb gets on)
		return
	if not free:
		# Every ladder busy (a man just went up it): the men below
		# wait their turn in the queues, by rule (not stuck, not stalled).
		u_st0[u] = tick
		u_blk[u] = BLK_QUEUE
		return
	if tick - u_st0[u] > LADDER_STALL:
		_ladder_down(u)  # nobody comes to a free ladder: all back down, the unit on the ground again
		stat_ladder_cut += 1


## A move given to unit u while it climbs (the order rule took it, as for
## a unit on its stretch: u_order O_MOVE to u_dx / u_dy). Out on the
## ladders' side (its foot's ground), or nobody up yet: the men up come back
## down the ladders and the unit goes from the foot, all together. Inland or
## onto another stretch: the men below go on climbing (in their wall line)
## and once all are up it goes on from the wall (_ladder_step).
func _ladder_move(u: int) -> void:
	var base := u_slot_base[u]
	var up := 0
	for s in u_alive[u]:
		var i := slot_soldier[base + s]
		if state[i] < S_DEAD and _on_walk(pos_x[i], pos_y[i]):
			up += 1
	var rf := reach_at(u_lfx[u], u_lfy[u])
	var ws := wall_snap(self, u_dx[u], u_dy[u])
	if up == 0 or (ws.z < 0 and rf >= 0 and reach_at(u_dx[u], u_dy[u]) == rf):
		var fl := u_files[u]
		_ladder_down(u)
		u_files[u] = fl  # (the frontage it was ordered to)
		stat_ladder_cut += 1
		return
	var wa := wall_anchor(self, u_sseg[u], u_wx[u], u_wy[u], u_alive[u], u_type[u])
	u_files[u] = wall_nf(u_alive[u])
	u_ax[u] = wa.x
	u_ay[u] = wa.y
	u_face[u] = wa.z
	u_dface[u] = wa.z
	u_dirty[u] = 1


## An attacking unit up a ladder (or climbing) comes back down the ladders
## at once (withdrawing or routing): its men on the walkway step down to
## the foot, and it is a ground unit again.
func _ladder_down(u: int) -> void:
	var base := u_slot_base[u]
	var n_l := maxi(ladders_of(self, u), 1)
	for s in u_alive[u]:
		var i := slot_soldier[base + s]
		if state[i] >= S_DEAD or (nav_at(pos_x[i], pos_y[i]) & (MapGen.NAV_GROUND | MapGen.NAV_DITCH)) != 0:
			continue
		var f := _ladder_k_foot(u, s % n_l, n_l)
		pos_x[i] = f.x
		pos_y[i] = f.y
		prev_x[i] = f.x
		prev_y[i] = f.y
		target[i] = -1
	u_wall[u] = 0
	u_stair[u] = 0
	u_trn[u] = 0
	u_pn[u] = 0
	u_sq[u] = 0
	u_ax[u] = u_lfx[u]
	u_ay[u] = u_lfy[u]
	u_files[u] = ground_files(u_type[u], u_alive[u])
	u_dirty[u] = 1
	u_settled[u] = 0
	_update_bounds()


## Settlement maps with siege equipment, a closed gate g each tick: a unit
## carrying the ram with its men at the gate's outer face (RAM_MEN or more
## within RAM_REACH, RAM_CREW of them counted) batters it (RAM_DMG every
## RAM_WORK man-ticks; once it breaks they put the ram down, free to
## fight); men who came over the wall by ladders at its inner face
## (UNBAR_MEN or more) open it after UNBAR_TICKS. The outer face of a
## citadel's gate is the town side.
func _siege_gate(g: int) -> void:
	var reach_x := g_hw[g] * M + M
	var out_y := wall_t / 2 + RAM_REACH
	var in_y := wall_t / 2 + GATE_REACH + M
	var gx := g_x[g]
	var gy := g_y[g]
	var r := wall_t + MapGen.GATE_HW * M + RAM_REACH + 4 * M
	var inside := 0
	for u in n_units:
		if u_side[u] == city_def or u_state[u] != U_READY or u_alive[u] <= 0:
			continue
		var ram := carries_ram(u)
		if not ram and u_lq[u] < 0:
			continue
		if u_order[u] == O_MOVE and u_gtarget[u] != g:
			continue
		if u_maxx[u] < gx - r or u_minx[u] > gx + r or u_maxy[u] < gy - r or u_miny[u] > gy + r:
			continue
		var men := 0
		var base := u_slot_base[u]
		for s in u_alive[u]:
			var i := slot_soldier[base + s]
			if state[i] != S_FORMED and state[i] != S_FIGHTING:
				continue
			var f := gate_frame(g, pos_x[i], pos_y[i])
			if absi(f.x) > reach_x:
				continue
			if ram:
				if f.y >= 0 and f.y <= out_y:
					men += 1
			elif f.y < 0 and -f.y <= in_y:
				inside += 1
		if ram and men >= RAM_MEN:
			u_lacc[u] += mini(men, RAM_CREW)
			if u_lacc[u] >= RAM_WORK:
				u_lacc[u] -= RAM_WORK
				g_hp[g] -= RAM_DMG * 100
				g_hit_t[g] = tick
				stat_ram_blows += 1
				if g_hp[g] <= 0:
					_break_gate(g)
					_drop(u)  # through: the crew puts the ram down and is free to fight
					if u_order[u] == O_MOVE and u_gtarget[u] == g:
						u_order[u] = O_NONE
					u_gtarget[u] = -1
					return
	if inside >= UNBAR_MEN:
		g_unbar[g] += 1
		if g_unbar[g] >= UNBAR_TICKS:
			g_unbar[g] = 0
			g_state[g] = GATE_OPEN
			stat_unbar += 1
			stat_gate_open += 1
			_gate_cells(g)
	elif g_unbar[g] > 0:
		g_unbar[g] = 0


## A shot aimed at tower engine unit pr_tu[p] lands within its tower: the
## tower takes dmg (its engine's hit points; wrecked at 0, the crew lost
## with it). Returns true if it struck the tower.
func _tower_hit(p: int, dmg: int) -> bool:
	var t := pr_tu[p]
	if t < 0 or t >= n_units or t_fixed[u_type[t]] == 0 or u_neng[t] == 0 or u_alive[t] <= 0:
		return false
	var e := u_eng0[t]
	if e_state[e] != E_OK:
		return false
	var dx := pr_x[p] - u_ax[t]
	var dy := pr_y[p] - u_ay[t]
	var r := u_trad[t] + M
	if dx * dx + dy * dy > r * r:
		return false
	stat_tower_hits += 1
	stat_engine_hits += 1
	e_hp[e] -= dmg
	if e_hp[e] <= 0:
		_wreck(e)
	return true


## A tower whose engine is wrecked is lost with its crew.
func _tower_fall(u: int) -> void:
	stat_towers_down += 1
	var base := u_slot_base[u]
	while u_alive[u] > 0:
		_remove(slot_soldier[base + u_alive[u] - 1], GONE_KILLED)


## Line of fire: ground or masonry this near the shooter's end ignored (a
## tower's engine shoots over its own tower).
func _skip0(u: int) -> int:
	return u_trad[u] + M if u >= 0 and u < u_trad.size() and u_trad[u] > 0 else 0


## ... and this near the far end (a tower aimed at is not in its own way).
func _skip1(t: int) -> int:
	return u_trad[t] + M if t >= 0 and t < u_trad.size() and u_trad[t] > 0 else LOF_SKIP


# ---------------------------------------------------------- field works ---
# Field works (docs/DESIGN.md "Field works and the fortified camp"): pieces
# of the q_* tables whose kind has EQ_FW, fixed where they stand for the
# battle (Q_FIXED; Q_STOWED: not placed). Every rule reads the per-kind
# fields, never the kind:
# - Stakes and caltrops: each side's entitlement (scenario "stakes" /
#   "caltrops": [side 0, side 1]) starts stowed; in the deployment phase a
#   player places, moves, turns or takes back its own (ORDER_WORKS, applied
#   at once like ORDER_PLACE, kept to the side's zone); the battle AI places
#   its side's at the start (BattleAI.place_works). Scenario "field_works"
#   [[kind, side, x_m, y_m, facing, len_m], ...] stand placed from the start.
# - The fortified camp (scenario "fortified": side): Scenarios.camp builds a
#   ditch and a rampart round the side's units, both field works with a
#   height (EQ_H): the height rules (melee from above, a charge uphill,
#   range from height) read it on any map (fwh_on); the rampart is climbed
#   slowly by the enemy (EQ_CROSS_T) and shelters and lifts its side's
#   missile troops (EQ_COVER, EQ_RANGE); the ditch slows everyone and stops
#   charges.
# - Each tick (_update_works, after the men have moved) a man inside a piece
#   is slowed (EQ_SLOW_*, EQ_CROSS_T: his step this tick cut short), takes a
#   wound stepping in (EQ_DMG_*, more at the gallop; a charging rider may be
#   thrown, EQ_KNOCK), uses up its stock (EQ_USE), takes a rider's charge
#   momentum (EQ_STOP) and, if he is enemy foot, hacks at it (EQ_HACK).
#   Hidden pieces (EQ_HIDE) become known to a side once one of its men has
#   stepped in (q_seen; the view draws them for the sides that know).
#   Stakes burn (EQ_BURN).
# Only on field maps (no settlement). All of it hashed when the battle has
# any (fw_on).

## The field works of scenario sc (units: the battle's unit dictionaries):
## [kind, side, x, y, facing, len, state] (sim units), placed ones first,
## then each side's unplaced entitlement.
func _field_works(sc: Dictionary, units: Array) -> Array:
	var out: Array = []
	if city_on != 0:
		return out
	var lst: Array = (sc.get("field_works", []) as Array).duplicate()
	if sc.has("fortified"):
		var fs := int(sc["fortified"])
		if fs == 0 or fs == 1:
			lst.append_array(Scenarios.camp(units, field_w / M, field_h / M, fs))
	for e in lst:
		var k := int(e[0])
		var s := int(e[1])
		if k <= 0 or k >= EQ_FW.size() or EQ_FW[k] == 0 or s < 0 or s > 1:
			continue
		var ln := int(e[5]) * M if (e as Array).size() > 5 and int(e[5]) > 0 else EQ_FW_LEN[k]
		out.append([k, s, clampi(int(e[2]) * M, 0, field_w), clampi(int(e[3]) * M, 0, field_h),
			int(e[4]) & FM.ANGLE_MASK, maxi(ln, M), Q_FIXED])
	for key in ["stakes", "caltrops"]:
		var k := EQ_STAKES if key == "stakes" else EQ_CALTROPS
		var ent: Array = sc.get(key, [])
		for s in mini(ent.size(), 2):
			for j in clampi(int(ent[s]), 0, 16):
				out.append([k, s, 0, 0, 0, EQ_FW_LEN[k], Q_STOWED])
	return out


## Field work q covers the point (x, y): inside its oriented rectangle.
func fw_inside(q: int, x: int, y: int) -> bool:
	var dx := x - q_x[q]
	var dy := y - q_y[q]
	var hl := q_len[q] >> 1
	var hd := EQ_FW_DEPTH[q_kind[q]] >> 1
	var r := hl + hd
	if dx > r or dx < -r or dy > r or dy < -r:
		return false
	var c := FM.cos_a(q_face[q])
	var s := FM.sin_a(q_face[q])
	var f := (dx * c + dy * s) / FM.TRIG_ONE
	if f > hd or f < -hd:
		return false
	var l := (dy * c - dx * s) / FM.TRIG_ONE
	return l <= hl and l >= -hl


## Half extents (x, y) of field work q's rectangle's bounding box.
func fw_extent(q: int) -> Vector2i:
	var hl := q_len[q] >> 1
	var hd := EQ_FW_DEPTH[q_kind[q]] >> 1
	var c := absi(FM.cos_a(q_face[q]))
	var s := absi(FM.sin_a(q_face[q]))
	return Vector2i((c * hd + s * hl) / FM.TRIG_ONE + 1, (s * hd + c * hl) / FM.TRIG_ONE + 1)


## The first standing field work at (x, y) with a non-zero `field` (an
## EQ_* table) of side `side` (-1 either), or -1.
func works_at(x: int, y: int, field: Array[int], side: int = -1) -> int:
	for q in n_eq:
		if q_state[q] != Q_FIXED or field[q_kind[q]] == 0 or (side >= 0 and q_side[q] != side):
			continue
		if fw_inside(q, x, y):
			return q
	return -1


## Height of the field works at (x, y) (a camp's ditch and rampart).
func _fw_h(x: int, y: int) -> int:
	var q := works_at(x, y, EQ_H)
	return EQ_H[q_kind[q]] if q >= 0 else 0


## Ground height with the field works (sim units).
func gh_at(x: int, y: int) -> int:
	if fwh_on == 0:
		return height_at(x, y)
	return height_at(x, y) + _fw_h(x, y)


## Missile troops of u standing on their side's rampart shooting at men
## not on one: EQ_RANGE % of their range more (0 elsewhere).
func _works_rb(u: int, t: int) -> int:
	if fwh_on == 0 or t_cls[u_type[u]] != UT.CLS_MISSILE:
		return 0
	var q := works_at(u_cx[u], u_cy[u], EQ_RANGE, u_side[u])
	if q < 0 or works_at(u_cx[t], u_cy[t], EQ_RANGE) >= 0:
		return 0
	return t_m_range[u_type[u]] * EQ_RANGE[q_kind[q]] / 100


## A missile shot from (sx, sy) striking soldier v: stopped by the cover of
## a field work of v's side he stands on (EQ_COVER), unless the shooter
## stands on one too.
func _works_cover(sx: int, sy: int, v: int) -> bool:
	var q := works_at(pos_x[v], pos_y[v], EQ_COVER, u_side[unit_of[v]])
	if q < 0 or works_at(sx, sy, EQ_COVER) >= 0:
		return false
	if _rand() % 100 < EQ_COVER[q_kind[q]]:
		stat_fw_cover += 1
		return true
	return false


## The placement rule for a field work (ORDER_WORKS, deployment phase only;
## shared with the view's preview): the piece it moves (its "equip", or the
## first stowed piece of "kind" of `side`), and where it goes. Returns
## Vector4i(piece, x, y, facing) with piece -1 when refused; "on" 0 takes
## the piece back (x, y unchanged).
static func works_rule(sim, o: Dictionary) -> Vector4i:
	var no := Vector4i(-1, 0, 0, 0)
	if sim.phase != PHASE_DEPLOY or sim.fw_on == 0:
		return no
	var side := int(o.get("side", -1))
	var q := int(o.get("equip", -1))
	if q < 0:
		var k := int(o.get("kind", -1))
		for j in sim.n_eq:
			if sim.q_kind[j] == k and sim.q_side[j] == side and sim.q_state[j] == Q_STOWED:
				q = j
				break
	if q < 0 or q >= sim.n_eq or sim.q_side[q] != side or EQ_FW[sim.q_kind[q]] == 0 \
			or EQ_H[sim.q_kind[q]] != 0:
		return no  # (a camp's ditch and rampart are the scenario's)
	if sim.q_state[q] != Q_STOWED and sim.q_state[q] != Q_FIXED:
		return no
	if int(o.get("on", 1)) == 0:
		return Vector4i(q, sim.q_x[q], sim.q_y[q], sim.q_face[q])
	var p := deploy_clamp(sim, side, int(o.get("x", sim.q_x[q])), int(o.get("y", sim.q_y[q])))
	if p.z == 0:
		return no
	return Vector4i(q, p.x, p.y, int(o.get("facing", sim.q_face[q])) & FM.ANGLE_MASK)


## Apply a field works order (deployment phase).
func _works_order(o: Dictionary) -> void:
	var r := works_rule(self, o)
	if r.x < 0:
		return
	var q := r.x
	if int(o.get("on", 1)) == 0:
		q_state[q] = Q_STOWED
		return
	q_state[q] = Q_FIXED
	q_x[q] = r.y
	q_y[q] = r.z
	q_face[q] = r.w


## Field works, once a tick after the men have moved (see the section).
func _update_works() -> void:
	u_fws.fill(100)
	u_fwc.fill(0)
	for q in n_eq:
		var k := q_kind[q]
		if q_state[q] != Q_FIXED or EQ_FW[k] == 0:
			continue
		var qx := q_x[q]
		var qy := q_y[q]
		var ext := fw_extent(q)
		var own_too := EQ_OWN[k] != 0
		var cross := EQ_CROSS_T[k]
		var climb_step := EQ_FW_DEPTH[k] / cross if cross > 0 else 0
		var hackers := 0
		for u in n_units:
			if u_alive[u] <= 0 or u_state[u] >= U_DESTROYED:
				continue
			var own := u_side[u] == q_side[q]
			if own and not own_too:
				continue
			if u_maxx[u] < qx - ext.x - M or u_minx[u] > qx + ext.x + M \
					or u_maxy[u] < qy - ext.y - M or u_miny[u] > qy + ext.y + M:
				continue
			var ty := u_type[u]
			var beast := t_body_r[ty] > 0
			var rider := not beast and (t_cls[ty] == UT.CLS_CAV or t_mount[ty] == UT.MOUNT_HORSE \
				or t_mount[ty] == UT.MOUNT_CAMEL)
			var slow := EQ_SLOW_RIDE[k] if rider or beast else EQ_SLOW_FOOT[k]
			var dmg_pct := EQ_DMG_BEAST[k] if beast else (EQ_DMG_RIDE[k] if rider else EQ_DMG_FOOT[k])
			var charger := t_rider[ty] != 0
			var hacks := EQ_HACK[k] > 0 and not own and not rider and not beast and u_state[u] == U_READY \
				and t_cls[ty] != UT.CLS_ART
			var base := u_slot_base[u]
			var order := slot_soldier.slice(base, base + u_alive[u])
			for i in order:
				if state[i] >= S_DEAD or not fw_inside(q, pos_x[i], pos_y[i]):
					continue
				u_fws[u] = mini(u_fws[u], slow)
				if climb_step > 0 and not own:
					u_fwc[u] = climb_step if u_fwc[u] == 0 else mini(u_fwc[u], climb_step)
				var mx := pos_x[i] - prev_x[i]
				var my := pos_y[i] - prev_y[i]
				if hacks and state[i] != S_DOWN and absi(mx) + absi(my) < FW_HACK_STILL:
					hackers += 1  # (standing at it, not crossing)
				if mx != 0 or my != 0:
					if slow < 100:
						mx = mx * slow / 100
						my = my * slow / 100
					if climb_step > 0 and not own:
						var ml := FM.approx_len(mx, my)
						if ml > climb_step:
							mx = mx * climb_step / ml
							my = my * climb_step / ml
						stat_fw_climb += 1
					pos_x[i] = prev_x[i] + mx
					pos_y[i] = prev_y[i] + my
				if charger and EQ_STOP[k] > 0 and (chg[i] > 0 or u_mom[u] > 0):
					var mom := chg[i]
					chg[i] = maxi(chg[i] - EQ_STOP[k], 0)
					u_mom[u] = maxi(u_mom[u] - EQ_STOP[k], 0)
					stat_fw_stop += 1
					if fw_inside(q, prev_x[i], prev_y[i]):
						continue
					# Riding into it at the gallop: impaled, thrown.
					if mom > 0 and EQ_KNOCK[k] > 0 and not beast and _rand() % 100 < EQ_KNOCK[k] * mom / 100:
						_knock_down(i)
						stat_fw_knock += 1
					if dmg_pct > 0:
						_fw_wound(i, ty, dmg_pct * (100 + mom) / 100)
					_fw_step_in(q, u)
					continue
				if fw_inside(q, prev_x[i], prev_y[i]):
					continue
				# Stepping in.
				if dmg_pct > 0:
					_fw_wound(i, ty, dmg_pct)
				_fw_step_in(q, u)
		if hackers > 0:
			var h := EQ_HACK[k] * mini(hackers, FW_HACKERS)
			q_hp[q] -= h
			stat_fw_hack += h
		if q_hp[q] <= 0 and (EQ_USE[k] > 0 or EQ_HACK[k] > 0):
			_eq_wreck(q)


## A man of unit u stepped into field work q: counted, its stock used, it
## is no longer hidden from his side.
func _fw_step_in(q: int, u: int) -> void:
	stat_fw_cross += 1
	q_seen[q] |= 1 << u_side[u]
	if EQ_USE[q_kind[q]] > 0:
		q_hp[q] -= EQ_USE[q_kind[q]]


## Soldier i (type ty) loses pct % of his type's full hit points to a field work.
func _fw_wound(i: int, ty: int, pct: int) -> void:
	if state[i] >= S_DEAD:
		return
	var d := maxi(t_hp[ty] * pct / 100, 1)
	stat_fw_dmg += d
	var h := hp[i] - d
	if h <= 0:
		stat_fw_kills += 1
		_remove(i, GONE_KILLED)
	else:
		hp[i] = h


## Field work q is known to `side` (drawn for it): its own, or one not
## hidden, or one its men have found.
func works_known(q: int, side: int) -> bool:
	return q_side[q] == side or EQ_HIDE[q_kind[q]] == 0 or (q_seen[q] & (1 << side)) != 0


## A side's field works left to place / placed: Vector2i(stowed, fixed) of kind k.
func works_count(side: int, k: int) -> Vector2i:
	var r := Vector2i.ZERO
	for q in n_eq:
		if q_kind[q] == k and q_side[q] == side:
			if q_state[q] == Q_STOWED:
				r.x += 1
			elif q_state[q] == Q_FIXED:
				r.y += 1
	return r


## (x, y) lies within r of field work q's rectangle (along it, across it).
func _fw_near(q: int, x: int, y: int, r: int) -> bool:
	var dx := x - q_x[q]
	var dy := y - q_y[q]
	var c := FM.cos_a(q_face[q])
	var s := FM.sin_a(q_face[q])
	var f := absi((dx * c + dy * s) / FM.TRIG_ONE)
	var l := absi((dy * c - dx * s) / FM.TRIG_ONE)
	return f <= (EQ_FW_DEPTH[q_kind[q]] >> 1) + r and l <= (q_len[q] >> 1) + r


# --------------------------------------------------------------- mantlets ---
# docs/DESIGN.md "Mantlets". A mantlet (EQ_MANTLET) is a piece in the q_*
# tables like the ram: a plank screen about 6 m wide that any foot unit of
# either side carries (EQ_ANY; at its walk, EQ_WALK_PCT) and sets down with
# ORDER_DROP at its anchor, facing the way the unit faces (q_face); picked up
# again with ORDER_PICKUP. Standing (Q_GROUND) it shelters the men of the
# side that last carried it (q_side) in the rectangle behind it from
# missiles shot from in front of its line (EQ_SCREEN: arrows, slings and
# javelins; EQ_SCREEN_BOLT: bolts; stones none); carried, its carriers
# near it are covered by the roof rule (EQ_ROOF). Wooden (EQ_BURN), hit by
# bolts and stones landing on it (EQ_SHOT, _ram_hit). Scenario key
# "mantlets": [side 0 count, side 1 count], set up standing before the
# side's missile and artillery units (mt_on; battles without hash as
# before).

## The scenario's mantlets as [side, x, y, facing] (sim units): each side's
## count (at most 8) dealt in turn to its missile and artillery units in
## index order (no such unit: any of its units; tower engines never),
## standing MANTLET_AHEAD before the unit's front facing its way, side by
## side when a unit gets more than one.
func _mantlets_at_setup(sc: Dictionary, units: Array) -> Array:
	var out: Array = []
	var nm: Array = sc.get("mantlets", [])
	if nm.size() < 2:
		return out
	for s in 2:
		var cnt := clampi(int(nm[s]), 0, 8)
		if cnt == 0:
			continue
		var mis: Array[int] = []
		var any: Array[int] = []
		for u in units.size():
			var ud: Dictionary = units[u]
			var ty := int(ud["type"])
			if int(ud["side"]) != s or UT.stat(ty, "fixed") != 0:
				continue
			any.append(u)
			if UT.cls(ty) == UT.CLS_MISSILE or UT.cls(ty) == UT.CLS_ART:
				mis.append(u)
		if mis.is_empty():
			mis = any
		var nc := mis.size()
		if nc == 0:
			continue
		for k in cnt:
			var ud: Dictionary = units[mis[k % nc]]
			var per := (cnt - k % nc + nc - 1) / nc
			var lat := (2 * (k / nc) - (per - 1)) * (MANTLET_W + M) / 2
			var face := int(ud["facing"]) & FM.ANGLE_MASK
			var c := FM.cos_a(face)
			var sn := FM.sin_a(face)
			var x := int(ud["x_m"]) * M + (c * MANTLET_AHEAD - sn * lat) / FM.TRIG_ONE
			var y := int(ud["y_m"]) * M + (sn * MANTLET_AHEAD + c * lat) / FM.TRIG_ONE
			out.append([s, clampi(x, 0, field_w), clampi(y, 0, field_h), face])
	return out


## A missile shot from (sx, sy) about to strike soldier v: a standing
## mantlet of his side he is sheltered behind (within EQ_SCREEN_W / 2 of its
## middle along its line, up to EQ_SCREEN_D behind it), the shooter in
## front of its line, stops it EQ_SCREEN % of the time (a bolt:
## EQ_SCREEN_BOLT). One screen at most a missile (the first in index order).
func _screen_cover(sx: int, sy: int, v: int, bolt: bool) -> bool:
	var side := u_side[unit_of[v]]
	var px := pos_x[v]
	var py := pos_y[v]
	for q in n_eq:
		var k := q_kind[q]
		var pct: int = EQ_SCREEN_BOLT[k] if bolt else EQ_SCREEN[k]
		if pct <= 0 or q_state[q] != Q_GROUND or q_side[q] != side:
			continue
		var dx := px - q_x[q]
		var dy := py - q_y[q]
		var r: int = EQ_SCREEN_D[k] + EQ_SCREEN_W[k]
		if dx > r or dx < -r or dy > r or dy < -r:
			continue
		var c := FM.cos_a(q_face[q])
		var s := FM.sin_a(q_face[q])
		var f := (dx * c + dy * s) / FM.TRIG_ONE
		if f > 0 or f < -EQ_SCREEN_D[k]:
			continue  # not behind it
		var l := (dy * c - dx * s) / FM.TRIG_ONE
		if l > EQ_SCREEN_W[k] >> 1 or l < -(EQ_SCREEN_W[k] >> 1):
			continue
		if ((sx - q_x[q]) * c + (sy - q_y[q]) * s) / FM.TRIG_ONE <= 0:
			continue  # shot from behind its line: the screen does not stand in the way
		if _rand() % 100 < pct:
			stat_mantlet_cover += 1
			return true
		return false
	return false
