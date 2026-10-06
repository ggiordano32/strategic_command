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
const Terrain := preload("res://sim/terrain.gd")
const MapGen := preload("res://sim/mapgen.gd")

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
const ORDER_LAST := 11

## Unit fields an order can change; OrderPreview predicts exactly these.
const ORDER_KEYS: Array[String] = ["order", "ax", "ay", "face", "files", "dx", "dy",
	"dface", "target", "run", "fire", "skirm", "deploy", "refill", "gtarget"]

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
const SEPARATION := 717          # 0.7 m: friendly fighters push apart
const CAV_SEPARATION := 1434     # 1.4 m between riders
const CATCH_UP_DIST := 3 * M     # soldiers further than this from slot run
const GRID_SHIFT := 12           # 4 m cells (4096 units)
const EDGE_EXIT := 3 * M / 2     # soldiers this close to the edge leave

# Melee.
const BASE_HIT := 35
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
const E_ABANDONED := 2           # its battery broke or died: out of action
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
const FRIGHT_MAX := 200
const FRIGHT_DECAY := 1          # per tick: a stone's fright (60) lasts 6 s
const FX_CAP := 32               # view: recent stone impacts (not state)
# Refill (artillery): a battery told to refill takes REFILL_FULL ticks to
# settle into it (2 per tick back out), and while it is not back at 0 it
# cannot move, traverse or shoot; once in, crews at their engines bring up
# shots from the battery's finite reserve (m_refill ticks per shot at full
# crew, slower with fewer hands, nothing below the minimum crew).
const REFILL_FULL := 60          # 6 s to settle in, 3 s to get back out

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
const WALL_COVER: Array[int] = [0, 25, 35, 65]  # % of missiles from below stopped by the battlements, by wall level
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
var e_px := PackedInt32Array()      # view only: position last tick (not hashed)
var e_py := PackedInt32Array()

# Battle AI, per side.
var ai_phase := PackedInt32Array([0, 0])
var ai_t := PackedInt32Array([0, 0])
var ai_hold := PackedInt32Array([-1, -1])  # tick the side began holding high ground, -1 not
var ai_gate := PackedInt32Array([-1, -1])  # settlement maps: the gate a side's assault is aimed at
var ai_cit := PackedInt32Array([0, 0])  # settlement maps: the defenders fell back into the citadel (1)
var ai_prog := PackedInt32Array([0, 0, 0])  # settlement maps: deaths + gate damage seen, tick it last changed, all-out (1)

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
var tr_x := PackedInt32Array()       # u * TRAIL + k, oldest first
var tr_y := PackedInt32Array()
var pth_x := PackedInt32Array()      # u * PATH_MAX + k
var pth_y := PackedInt32Array()
var _u_obs := PackedInt32Array()     # scratch: unit near obstacles this tick
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
var pr_tu := PackedInt32Array()       # unit aimed at
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
var stat_parting: int = 0          # free blows at riders / soldiers turning away
var stat_impact_blocked: int = 0   # charge impacts taken on a formed front's shields
## Battle AI decisions by unit mode (BattleAI.A_*), plus [8] army withdrawals,
## [12] holds of high ground, [13] missile / artillery slots moved onto a
## rise, [14] deployments shifted to higher ground.
var stat_ai := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
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


# ---------------------------------------------------------------- setup ---

## scenario = {
##   "width_m": int, "height_m": int,
##   "ai_sides": [side, ...],
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
	ai_phase = PackedInt32Array([0, 0])
	ai_t = PackedInt32Array([0, 0])
	ai_hold = PackedInt32Array([-1, -1])
	ai_gate = PackedInt32Array([-1, -1])
	ai_prog = PackedInt32Array([0, 0, 0])
	ai_cit = PackedInt32Array([0, 0])
	_dist_new = 0
	_setup_terrain(scenario.get("terrain", {}), p_seed)

	_load_types()

	var units: Array = scenario["units"]
	n_units = units.size()
	var total := 0
	n_eng = 0
	for ud in units:
		total += int(ud["count"])
		n_eng += _engines_for(int(ud["type"]), int(ud["count"]))
	n = total
	for arr in _engine_arrays():
		arr.resize(n_eng)
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
	for arr in _map_unit_arrays():
		arr.resize(n_units)
		arr.fill(0)
	for arr in _stair_arrays():
		arr.resize(n_units)
		arr.fill(0)
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
	for u in n_units:
		var ud: Dictionary = units[u]
		var ty := int(ud["type"])
		var cnt := int(ud["count"])
		u_side[u] = int(ud["side"])
		u_type[u] = ty
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
		u_ammo[u] = cnt * t_m_ammo[ty]
		u_hit_t[u] = -1000
		u_charged_t[u] = -1000
		u_slot_base[u] = base
		u_dirty[u] = 1
		u_ai_t[u] = 0
		u_ftarget[u] = -1
		u_shelled_t[u] = -1000
		u_shelled_by[u] = -1
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
				# Staggered: engines are part way through loading.
				e_reload[e] = _rand() % maxi(t_m_reload[ty] * t_crew[ty], 1)
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
			ammo[i] = t_m_ammo[ty] if ne == 0 else 0
		base += cnt

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
	grid_next.resize(n)
	_update_bounds()
	_update_units_stats()
	if ter_on != 0 or obs_on != 0:
		for u in n_units:
			u_h[u] = _unit_elev(u)

	for o in scenario.get("orders", []):
		var od: Dictionary = (o as Dictionary).duplicate()
		if not od.has("player"):
			od["player"] = 50
		queue_order(od)


func _soldier_arrays() -> Array:
	return [pos_x, pos_y, prev_x, prev_y, facing, hp, state, cooldown, unit_of,
		slot_of, target, ammo, chg, struck]


func _soldier_hashed() -> Array:
	return [pos_x, pos_y, facing, hp, state, cooldown, unit_of, slot_of, target,
		ammo, chg, struck]


func _unit_arrays() -> Array:
	return [u_side, u_type, u_cls, u_count0, u_alive, u_state, u_morale, u_routs,
		u_files, u_ax, u_ay, u_face, u_order, u_dx, u_dy, u_dface, u_target,
		u_run, u_fire, u_skirm, u_slot_base, u_contact, u_fighting, u_settled,
		u_dirty, u_cx, u_cy, u_minx, u_miny, u_maxx, u_maxy, u_flee_x, u_flee_y,
		u_moved, u_disorder, u_formed, u_braced, u_mom, u_charge, u_charge_t,
		u_charge_left, u_charge_act, u_down, u_ftarget,
		u_fire_acc, u_fire_ptr, u_ammo, u_hit_t, u_charged_t, u_killed,
		u_withdrawn, u_routed_off, u_recent, u_att, u_def, u_dmg, u_reach, u_nwalls,
		u_ai, u_ai_t, u_ai_x, u_ai_y, u_eng0, u_neng, u_depl, u_deploy, u_fright,
		u_shelled_t, u_shelled_by, u_emove, u_h, u_refill, u_rprog, u_reserve]


## Per-unit arrays of woods and settlement maps (hashed only on those maps,
## so the hash of a plain map is what it always was).
func _map_unit_arrays() -> Array:
	return [u_wall, u_sq, u_gtarget, u_pn, u_pk, u_pgx, u_pgy, u_pep, u_trn]


## Per-unit stair moves and regrouping (maps with buildings or walls;
## hashed only there).
func _stair_arrays() -> Array:
	return [u_stair, u_sseg, u_send, u_st0, u_wx, u_wy, u_lagt]


func _engine_arrays() -> Array:
	return [e_unit, e_x, e_y, e_face, e_hp, e_state, e_reload, e_ammo, e_crew, e_rwork]


## Engines in a unit of `count` soldiers of type ty (0 unless artillery).
static func _engines_for(ty: int, count: int) -> int:
	var crew := UT.stat(ty, "crew")
	if UT.cls(ty) != UT.CLS_ART or crew <= 0:
		return 0
	return maxi(count / crew, 1)


func _projectile_arrays() -> Array:
	return [pr_sx, pr_sy, pr_x, pr_y, pr_t0, pr_t1, pr_unit, pr_tu, pr_next]


func _load_types() -> void:
	var nt := UT.TYPES.size()
	var arrays := [t_cls, t_attack, t_defence, t_armour, t_shield, t_mshield,
		t_damage, t_reach, t_ranks, t_mass, t_walk, t_run, t_hp, t_cooldown,
		t_morale, t_fsp, t_rsp, t_turn, t_brace, t_vs_cav, t_charge, t_sec_att,
		t_sec_def, t_sec_dmg, t_sec_reach, t_m_range, t_m_dmg, t_m_ap, t_m_ammo,
		t_m_reload, t_m_spread, t_m_spread0, t_m_speed, t_m_arc, t_skirm, t_m_vuln, t_m_down,
		t_m_lead, t_m_long, t_crew, t_crew_min, t_m_kind, t_m_min, t_m_pierce, t_m_plough, t_m_blast,
		t_m_fear, t_arc, t_traverse, t_deploy, t_e_hp, t_climb, t_m_hgain, t_m_apex, t_m_reserve, t_m_refill]
	var keys := ["cls", "attack", "defence", "armour", "shield", "mshield",
		"damage", "reach", "ranks_reach", "mass", "walk", "run", "hp", "cooldown",
		"morale", "file_sp", "rank_sp", "turn", "brace", "vs_cav", "charge",
		"sec_attack", "sec_defence", "sec_damage", "sec_reach", "m_range",
		"m_damage", "m_ap", "m_ammo", "m_reload", "m_spread", "m_spread0",
		"m_speed", "m_arc", "skirm", "m_vuln", "m_down", "m_lead", "m_long", "crew", "crew_min",
		"m_kind", "m_min", "m_pierce", "m_plough", "m_blast", "m_fear", "arc", "traverse",
		"deploy", "e_hp", "climb", "m_hgain", "m_apex", "m_reserve", "m_refill"]
	for k in arrays.size():
		var arr: PackedInt32Array = arrays[k]
		arr.resize(nt)
		for t in nt:
			arr[t] = UT.stat(t, keys[k])


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
func range_h(ty: int, hs: int, ht: int) -> int:
	var rng := t_m_range[ty]
	if ter_on == 0 and obs_on == 0:
		return rng
	var cap := rng * RANGE_H_CAP / 100
	return rng + clampi((hs - ht) * t_m_hgain[ty] / 100, -cap, cap)


## Effective range of missile unit u against unit t (centroid heights).
func range_vs(u: int, t: int) -> int:
	return range_h(u_type[u], u_h[u], u_h[t])


## Line of fire over the ground: from (x0, y0) at height z0 to (x1, y1) at
## z1 (absolute heights, sim units), allowing a rise of `apex` above the
## straight line at mid-flight (parabolic), continued `ext` past the end.
## Returns the distance from (x0, y0) at which the ground first rises above
## the flight, or -1 if it is clear. Ground within LOF_SKIP of either end of
## the aimed segment is ignored (the shooter's and target's own footing).
func lof_block(x0: int, y0: int, z0: int, x1: int, y1: int, z1: int, apex: int, ext: int,
		stride: int = LOF_STEP) -> int:
	if ter_on == 0 and map_on == 0:
		return -1
	var dx := x1 - x0
	var dy := y1 - y0
	var d := FM.approx_len(dx, dy)
	if d <= 2 * LOF_SKIP:
		return -1
	var dz := z1 - z0
	var a := LOF_SKIP
	var end := d - LOF_SKIP
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
		d * t_m_apex[ty] / 100, 0, 2 * LOF_STEP)
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
	var h := height_at(x, y)
	if obs_on != 0:
		var k := obs_kind(x, y)
		if k == MapGen.C_WALK or k == MapGen.C_TOWER:
			h += wall_h  # (a man in a tower is a wall unit's, passing through)
		elif k == MapGen.C_STAIR:
			h += wall_h / 2
	return h


## Unit u's height: its ground (or its walkway).
func _unit_elev(u: int) -> int:
	return height_at(u_cx[u], u_cy[u]) + (wall_h if u_wall[u] > 0 else 0)


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
func _stair_leave(u: int, x: int, y: int, mode: int) -> Vector3i:
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
	return Vector2i(tr_x[base + best], tr_y[base + best])


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
	if city_ditch != 0 and (c == UT.CLS_INF or c == UT.CLS_PIKE or c == UT.CLS_MISSILE):
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
			var dt := _dist_table(b)
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
			and FM.approx_len(gx - u_pgx[u], gy - u_pgy[u]) > 12 * M:
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
	if FM.approx_len(wx - u_ax[u], wy - u_ay[u]) <= WP_REACH:
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
func _regroup(u: int) -> void:
	var best := -1
	var best_d := 1 << 40
	var base := u_slot_base[u]
	for s in u_alive[u]:
		var i := slot_soldier[base + s]
		if state[i] >= S_DEAD or (nav_at(pos_x[i], pos_y[i]) & MapGen.NAV_GROUND) == 0:
			continue
		var d := FM.approx_len(pos_x[i] - u_cx[u], pos_y[i] - u_cy[u])
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
	if sq > 0 and u_order[u] != O_NONE and absi(fl - fr) > 2 * M and u_stair[u] != 2:
		# Keep to the middle of the street (a metre at a time: at a corner
		# the free width either side can flip from one check to the next).
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
	if sim.city_on == 0 or sim.ws_x0.size() == 0 or sim.u_side[u] != sim.city_def:
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
	if u_wall[u] > 0 and u_order[u] == O_MOVE:
		_start_descent(u)
		return
	if u_stair[u] == 1:
		return  # still coming down: the new order waits until it is down
	if typ == ORDER_MOVE and u_wall[u] == 0 and u_order[u] == O_MOVE and can_man_walls(self, u):
		var ws := wall_snap(self, u_dx[u], u_dy[u])
		if ws.z >= 0:
			_start_ascent(u, ws.z, ws.x, ws.y)
			return
	if u_stair[u] == 2:
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
				break
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
		for u in n_units:
			if u_side[u] == city_def or u_state[u] != U_READY or u_alive[u] <= 0:
				continue
			var cl := u_cls[u]
			if cl != UT.CLS_INF and cl != UT.CLS_PIKE:
				continue
			if u_order[u] == O_MOVE and u_gtarget[u] != g:
				continue
			if u_maxx[u] < gx - r or u_minx[u] > gx + r or u_maxy[u] < gy - r or u_miny[u] > gy + r:
				continue
			var ty := u_type[u]
			var rate := maxi(t_damage[ty] - GATE_ARMOUR, 2) * GATE_HACK_PCT / maxi(t_cooldown[ty], 1)
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
	u_ax[u] = u_cx[u]
	u_ay[u] = u_cy[u]
	var p := _path_point(u, gx, gy, true)
	var dx := p.x - u_cx[u]
	var dy := p.y - u_cy[u]
	var d := FM.approx_len(dx, dy)
	if d > 0:
		u_flee_x[u] = dx * FM.TRIG_ONE / d
		u_flee_y[u] = dy * FM.TRIG_ONE / d


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


func _apply_orders() -> void:
	if pending_orders.is_empty():
		return
	var due: Array = []
	var rest: Array = []
	for o in pending_orders:
		if int(o["tick"]) <= tick:
			due.append(o)
		else:
			rest.append(o)
	if due.is_empty():
		return
	pending_orders = rest
	due.sort_custom(_order_less)
	for o in due:
		if int(o["type"]) == ORDER_GATE:
			_gate_order(o)
			continue
		for u in order_units(self, o):
			var d := order_fields(self, u)
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
			u_dirty[u] = 1
			u_settled[u] = 0
			if obs_on != 0:
				u_pn[u] = 0  # plan a new path
			if city_on != 0 and ws_e.size() > 0:
				_wall_order(u, int(o["type"]))


## The ORDER_KEYS fields of unit u as a Dictionary.
static func order_fields(sim, u: int) -> Dictionary:
	return {"order": sim.u_order[u], "ax": sim.u_ax[u], "ay": sim.u_ay[u],
		"face": sim.u_face[u], "files": sim.u_files[u], "dx": sim.u_dx[u],
		"dy": sim.u_dy[u], "dface": sim.u_dface[u], "target": sim.u_target[u],
		"run": sim.u_run[u], "fire": sim.u_fire[u], "skirm": sim.u_skirm[u],
		"deploy": sim.u_deploy[u], "refill": sim.u_refill[u], "gtarget": sim.u_gtarget[u]}


## Units an order applies to (in index order): its unit, or every ready unit
## of the side for an army-wide withdrawal. Shared with OrderPreview.
static func order_units(sim, o: Dictionary) -> Array[int]:
	var out: Array[int] = []
	if int(o["type"]) == ORDER_GATE:
		return out  # not a unit order (applied by the sim to the gate)
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
	# Artillery: frontage is set by its engines, and it never runs (the
	# engines are dragged); it does not skirmish.
	var art := UT.cls(ty) == UT.CLS_ART
	# A battery's refill ends with any order to move, shoot, withdraw or
	# set up / pack up (it gets back out first: REFILL_FULL / 2 ticks).
	if art and (typ == ORDER_MOVE or typ == ORDER_ATTACK or typ == ORDER_WITHDRAW \
			or typ == ORDER_WITHDRAW_ALL or typ == ORDER_DEPLOY):
		d["refill"] = 0
	# Walls. A move onto a wall's body, walkway, stair or tower goes to the
	# walkway of the stretch it belongs to (wall_snap); only units that may
	# man the walls take it so (others: a ground move, refused by the view).
	# A unit on a wall holds it: it moves only along its stretch (in its
	# wall line, facing out), anywhere else means down a stair (the sim
	# starts the stair moves when the order is applied: _wall_order), and it
	# does not withdraw or skirmish.
	var wallu: int = sim.u_wall[u] if u < sim.u_wall.size() else 0
	var ws := Vector3i(0, 0, -1)
	if typ == ORDER_MOVE and (wallu > 0 or can_man_walls(sim, u)):
		ws = wall_snap(sim, int(o["x"]), int(o["y"]))
	if wallu > 0:
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
		if not art:
			d["files"] = width_to_files(int(o["width"]), sim.u_alive[u], ty)
		d["run"] = 1 if int(o.get("run", 0)) != 0 and not art else 0
		d["target"] = -1
		d["gtarget"] = -1
		var dx: int = x - d["ax"]
		var dy: int = y - d["ay"]
		if dx * dx + dy * dy <= REFORM_IN_PLACE_DIST * REFORM_IN_PLACE_DIST:
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
			if c != UT.CLS_INF and c != UT.CLS_PIKE:
				return
			var gfp: Vector3i = sim.gate_front(gt, sim.u_side[u])
			d["order"] = O_MOVE
			d["dx"] = gfp.x
			d["dy"] = gfp.y
			d["dface"] = gfp.z
			d["target"] = -1
			d["gtarget"] = gt
			d["run"] = 1 if int(o.get("run", 0)) != 0 else 0
			return
		var t := int(o["target"])
		if t < 0 or t >= sim.n_units or sim.u_side[t] == sim.u_side[u] or sim.u_state[t] >= U_DESTROYED:
			return
		d["order"] = O_ATTACK
		d["target"] = t
		d["gtarget"] = -1
		d["run"] = 1 if int(o.get("run", 0)) != 0 and not art else 0
	elif typ == ORDER_HALT:
		d["order"] = O_NONE
		d["target"] = -1
		d["gtarget"] = -1
		d["dface"] = d["face"]
	elif typ == ORDER_RUN:
		d["run"] = 1 if int(o.get("run", 0)) != 0 and not art else 0
	elif typ == ORDER_FIRE:
		if UT.stat(ty, "m_ammo") > 0:
			d["fire"] = 1 if int(o.get("on", 0)) != 0 else 0
	elif typ == ORDER_SKIRMISH:
		if UT.stat(ty, "m_ammo") > 0 and not art:
			d["skirm"] = 1 if int(o.get("on", 0)) != 0 else 0
	elif typ == ORDER_DEPLOY:
		if art:
			d["deploy"] = 1 if int(o.get("on", 0)) != 0 else 0
	elif typ == ORDER_REFILL:
		if art:
			var on := 1 if int(o.get("on", 0)) != 0 else 0
			d["refill"] = on
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
		d["run"] = 0 if art else 1
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
	_fill_offsets(off_x, u_slot_base[u], alive, files, u_face[u], false, off_y,
		t_fsp[ty], t_rsp[ty])
	if city_on != 0 and n_cmp > 0 and u_stair[u] == 0 and u < _u_obs.size() and _u_obs[u] != 0:
		_project_slots(u)
	u_dirty[u] = 0


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
	var base := u_slot_base[u]
	for s in u_alive[u]:
		var ox := off_x[base + s]
		var oy := off_y[base + s]
		if reach_at(ax + ox, ay + oy) == ra:
			continue
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
	for slot in u_alive[u]:
		var e := w[slot % nw]
		var co := _crew_offset(slot / nw, e_face[e], ty)
		off_x[base + slot] = e_x[e] - u_ax[u] + co.x
		off_y[base + slot] = e_y[e] - u_ay[u] + co.y


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
	if n_gates > 0:
		_update_gates()
	if n_eng > 0:
		_update_artillery()
	_update_missiles()
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


func _update_units() -> void:
	var ton := ter_on != 0
	var mon := map_on != 0
	var oon := obs_on != 0
	for u in n_units:
		u_moved[u] = 0
		if (ton or oon) and u_alive[u] > 0:
			u_h[u] = _unit_elev(u) if oon else height_at(u_cx[u], u_cy[u])
		if oon and u_alive[u] > 0:
			_u_obs[u] = _near_obs(u)
			if u_stair[u] == 1 or u_stair[u] == 3:
				_stair_check(u)
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
			_u_vfac[u] = vf
			if vf < 1000:
				aspeed = aspeed * vf / 1000
				stat_veg_slow += 1
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
		if u_stair[u] == 1:
			order = O_NONE  # waiting at the stair's foot for its men to come down
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
			if d <= aspeed:
				u_ax[u] = wx
				u_ay[u] = wy
				if order == O_MOVE and not via:
					u_order[u] = O_NONE
					if city_on != 0:
						u_dirty[u] = 1  # there: its places again (kept to its own ground)
					if u_stair[u] == 2:
						_climb(u)  # at the stair's foot: up
			else:
				u_ax[u] += dx * aspeed / d
				u_ay[u] += dy * aspeed / d
				# March facing the direction of travel; turn to the final
				# facing for the last stretch.
				if via or d > REFORM_IN_PLACE_DIST:
					want_face = FM.atan2_a(dy, dx)
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
				if oon and u_wall[u] == 0 and u_charge[u] == 0 and u_fighting[u] == 0 \
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
							want_face = FM.atan2_a(vy, vx)
							var mv0 := mini(aspeed, vdd)
							u_ax[u] += vx * mv0 / vdd
							u_ay[u] += vy * mv0 / vdd
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
					var stop := t_m_range[ty] * 17 / 20
					if ton or mon:
						stop = range_vs(u, t) * 17 / 20
						if not lof_units(u, t):
							stop = t_m_range[ty] / 4
						if d > stop and ton:
							aspeed = aspeed * _fac_dir(u, g0, dx, dy, d) / 1000
					if u_wall[u] > 0:
						stop = d  # on the wall: shoot from here or not at all
					elif d > stop and oon and city_on != 0 \
							and unreach_goal(u, t, Vector2i(u_cx[t], u_cy[t])).z != 0:
						stop = d  # in range of a target out of reach: no closer (a wall between)
					if d > stop:
						var mv := mini(aspeed, d - stop)
						u_ax[u] += dx * mv / d
						u_ay[u] += dy * mv / d
				elif (u_fighting[u] == 0 or u_state[t] == U_ROUTING) and d > 0:
					want_face = FM.atan2_a(dy, dx)
					var hw := (u_maxx[t] - u_minx[t]) >> 1
					var hh := (u_maxy[t] - u_miny[t]) >> 1
					var ext := (absi(dx) * hw + absi(dy) * hh) / d
					var stop := ext + M
					if oon:
						# Among buildings a unit stopping short of a deep column
						# may have a corner between its men and the enemy's:
						# press right up to it.
						stop = mini(stop, 4 * M)
					if ton and d > stop:
						aspeed = aspeed * _fac_dir(u, g0, dx, dy, d) / 1000
					if d > stop:
						var mv := mini(aspeed, d - stop)
						u_ax[u] += dx * mv / d
						u_ay[u] += dy * mv / d
				u_dface[u] = want_face
		_turn(u, want_face)
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
		if cls == UT.CLS_CAV:
			# Momentum builds only while charging a target at speed: a run
			# away from a melee (pulling out) does not count as a run-up.
			if u_run[u] != 0 and moved * 10 >= aspeed * 6 and order == O_ATTACK and u_charge[u] == 0:
				var gain := MOM_GAIN
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
		elif cls == UT.CLS_MISSILE:
			if (u + tick) % FIRE_THINK == 0:
				_missile_think(u)
		elif art:
			if (u + tick) % FIRE_THINK == 0:
				_art_think(u)
		_unit_stats(u)


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
	var ty := u_type[u]
	if u_cls[u] == UT.CLS_PIKE and u_formed[u] == 0:
		u_att[u] = t_sec_att[ty]
		u_def[u] = t_sec_def[ty]
		u_dmg[u] = t_sec_dmg[ty]
		u_reach[u] = t_sec_reach[ty]
	else:
		u_att[u] = t_attack[ty]
		u_def[u] = t_defence[ty]
		u_dmg[u] = t_damage[ty]
		u_reach[u] = t_reach[ty]


func _update_units_stats() -> void:
	for u in n_units:
		_unit_stats(u)


## Missile unit behaviour, every FIRE_THINK ticks: skirmish away from close
## melee troops, and choose what to shoot.
func _missile_think(u: int) -> void:
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
	# Fire target.
	var ft := -1
	if u_ammo[u] > 0 and order != O_MOVE and order != O_WITHDRAW:
		var rng := t_m_range[ty]
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
			var hgt := ter_on != 0 or obs_on != 0
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
	if ter_on == 0 and obs_on == 0:
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
			continue

		var ax := u_ax[u]
		var ay := u_ay[u]
		var spd_formed := run if u_run[u] != 0 else walk
		var moved := 0
		var withdrawing := u_order[u] == O_WITHDRAW
		var exit_y := fh - EDGE_EXIT if u_side[u] == 0 else EDGE_EXIT
		# Coast: the defenders withdraw along the shore and leave by a side.
		var side_exit := withdrawing and sea_on != 0 and u_side[u] == city_def
		var is_cav := u_cls[u] == UT.CLS_CAV
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
			stair_mv = u_stair[u] if u_stair[u] == 1 or u_stair[u] == 3 else 0
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
					var sgo := _stair_leave(u, x, y, stair_mv)
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
		var cool := t_cooldown[ty]
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
		var disengage := u_order[u] == O_MOVE or withdrawing
		# Formed pikes strike from their slots with ranks 1..ranks_reach.
		var pike_formed := u_formed[u] != 0
		var pike_ranks := t_ranks[ty] * files
		var fcos := FM.cos_a(face)
		var fsin := FM.sin_a(face)
		var sep := CAV_SEPARATION if is_cav else SEPARATION
		var charging := u_charge[u] != 0
		# Wrap: front-rank soldiers of an engaged attacking unit who have no
		# enemy in reach close on the target unit instead of holding their
		# slot, so a wide unit laps round a narrow face (a flank) rather than
		# leaving most of its men idle.
		var wrap_t := -1
		if u_order[u] == O_ATTACK and u_fighting[u] > 0 and not pike_formed and not shy and not charging:
			wrap_t = u_target[u]
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
					var sgl := _stair_leave(u, x, y, stair_mv)
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
						elif ob and ((tk + i) & 7) == 0 and not _reach_ok(x, y, px[t], py[t]):
							t = -1  # out of reach behind a wall: look again
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
				var d := FM.approx_len(dx, dy)
				var mom := 0
				if is_cav:
					mom = cg[i]
				if d > want:
					# Walk in; charge at the run with momentum, and run down
					# fleeing enemies.
					var stp := walk
					if mom > 0 or st[t] == S_ROUTING:
						stp = run_cap
					else:
						var to := u_order[unit_of[t]]
						if to == O_MOVE or to == O_WITHDRAW:
							stp = run_cap  # run down enemies pulling away
					var step_len := mini(stp, d - want)
					nx = x + dx * step_len / d
					ny = y + dy * step_len / d
					if is_cav and step_len * 3 < run_cap:
						mom = maxi(mom - 15, 0)
				elif d < half_reach and d > 0:
					var back := mini(walk >> 1, half_reach - d)
					nx = x - dx * back / d
					ny = y - dy * back / d
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
						var tmom := cg[t] if u_cls[unit_of[t]] == UT.CLS_CAV else 0
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
					var sgs := _stair_leave(u, x, y, stair_mv)
					if sgs.z != 0:
						dx = sgs.x - x
						dy = sgs.y - y
				if wrap_t >= 0 and front and t < 0:
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
				fc[i] = face
				if is_cav:
					# Riders keep their own momentum a moment after the unit
					# stops, so rear ranks still hit home.
					cg[i] = maxi(umom, cg[i] - 10)
				if t >= 0:
					var ex := px[t] - x
					var ey := py[t] - y
					var in_reach := ex * ex + ey * ey <= reach * reach
					# Only pikemen who can strike hold the block in place, so
					# a block keeps closing until its points reach.
					if in_reach:
						fighting += 1
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
## (front), behind its rear rank (rear) or alongside (flank). Unit-level
## effects (morale, pike disorder, bracing) use this rather than the angle
## between two duellists, so oblique blows inside a frontal melee stay
## frontal.
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


## Melee blow by soldier a at soldier d. `pen` is a hit penalty; `parting`
## is a free blow at the back of a soldier turning away from the fight
## (rear bonus, no shield, no unit-level flank effects).
func _melee(a: int, d: int, pen: int, parting: bool = false) -> void:
	if state[d] >= S_DEAD:
		return
	stat_attacks += 1
	var ua := unit_of[a]
	var ud := unit_of[d]
	var from_def := FM.atan2_a(pos_y[a] - pos_y[d], pos_x[a] - pos_x[d])
	var rel := absi(FM.angle_diff(facing[d], from_def))
	var zone := _zone(ud, pos_x[a], pos_y[a])
	var frontal := rel <= FRONT_ARC
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
	elif rel > REAR_ARC:
		bonus = REAR_BONUS
	elif not frontal:
		bonus = FLANK_BONUS
	var att := u_att[ua]
	var dmg0 := u_dmg[ua]
	var def := u_def[ud]
	var td := u_type[ud]
	# Pikemen caught from the flank or rear fight with the short sword.
	if u_cls[ud] == UT.CLS_PIKE and zone != ZONE_FRONT:
		def = t_sec_def[td]
	if u_cls[ud] == UT.CLS_CAV:
		var vc := t_vs_cav[u_type[ua]]
		att += vc
		dmg0 += vc
	if veg_on != 0:
		# Horses cannot turn and press among trees.
		if u_cls[ua] == UT.CLS_CAV:
			bonus -= VEG_CAV_MELEE[veg_d(pos_x[a], pos_y[a])]
		if u_cls[ud] == UT.CLS_CAV:
			bonus += VEG_CAV_MELEE[veg_d(pos_x[d], pos_y[d])]
	var chance := clampi(BASE_HIT + att - def + bonus - pen, 5, 95)
	if ter_on == 0:
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
	# Morale cares whether the *unit* is hit in the flank or rear (relative
	# to the unit's facing), not how an individual duellist is turned.
	# A blow from beside the formation that the man has turned to face is
	# not a flank attack on the unit (as for charge impacts).
	if zone == ZONE_FLANK and frontal:
		zone = ZONE_FRONT
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
	var g := grade_between(height_at(xd, yd), height_at(xa, ya), FM.approx_len(xa - xd, ya - yd))
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
func _impact(r: int, t: int, mom: int) -> void:
	var ur := unit_of[r]
	var ut := unit_of[t]
	var rty := u_type[ur]
	var td := u_type[ut]
	var zone := _zone(ut, pos_x[r], pos_y[r])
	dbg_impacted[r] = 1
	struck[r] = 1
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
		return
	stat_impacts += 1
	var power := t_charge[rty] * mom / 100
	if ter_on != 0:
		# Riding down onto a man hits harder; riding up at him, weaker.
		var g := grade_between(height_at(pos_x[t], pos_y[t]), height_at(pos_x[r], pos_y[r]),
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
	# reach: the least hurt one (then the nearest), a rule that does not
	# depend on direction (the first found in grid scan order favoured one
	# side of the field) and does not pile every carry-on onto the same men.
	var head: PackedInt32Array = grid_head1 if u_side[ur] == 0 else grid_head0
	var gs := GRID_SHIFT
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
				if j != t and state[j] < S_DOWN:
					var dx := pos_x[j] - x
					var dy := pos_y[j] - y
					if absi(dx) < IMPACT_RADIUS and absi(dy) < IMPACT_RADIUS:
						var d2 := dx * dx + dy * dy
						if best < 0 or hp[j] > hp[best] or (hp[j] == hp[best] and (d2 < best_d \
								or (d2 == best_d and j < best))):
							best = j
							best_d = d2
				j = grid_next[j]
	if best >= 0:
		_impact_victim(r, best, power * 6 / 10, ma, zone)


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
	var tv := u_type[uv]
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
	var arm := t_armour[tv] / 2
	var knock := mini(force + 10, 90)
	if frontal:
		arm = t_armour[tv]
		# (Impacts pile up disorder within a tick, so only morale counts here.)
		var steady := u_morale[uv] >= WAVER
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
	var dmg := maxi(force - arm, 1) * (85 + _rand() % 31) / 100
	if u_state[uv] == U_READY:
		u_morale[uv] -= shock
		_add_disorder(uv, DISORDER_IMPACT)
		u_charged_t[uv] = tick
	var h := hp[v] - dmg
	if h <= 0:
		stat_kills[2] += 1
		_remove(v, GONE_KILLED)
		return true
	hp[v] = h
	if sv != S_DOWN and _rand() % 100 < knock:
		_knock_down(v)
		return true
	if frontal and state[r] < S_DEAD:
		# Still on his feet facing the horse: he strikes back as it arrives.
		_melee(v, r, 0)
	return not (frontal and u_morale[uv] >= WAVER)


func _knock_down(i: int) -> void:
	var st := state[i]
	if st == S_DOWN or st >= S_DEAD:
		return
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
	u_ammo[u] -= ammo[d]
	ammo[d] = 0
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
		var ty := u_type[u]
		var alive := u_alive[u]
		var acc := u_fire_acc[u] + alive
		var reload := t_m_reload[ty]
		var tries := 0
		while acc >= reload and tries < alive:
			acc -= reload
			tries += 1
			var ptr := u_fire_ptr[u] % alive
			u_fire_ptr[u] = ptr + 1
			var i := slot_soldier[u_slot_base[u] + ptr]
			if state[i] != S_FORMED or ammo[i] <= 0:
				continue
			_fire(i, u, ft, ty)
		u_fire_acc[u] = mini(acc, reload)
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


func _fire(i: int, u: int, ft: int, ty: int) -> void:
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
	if ter_on == 0 and map_on == 0:
		if dist > t_m_range[ty] or dist <= 0 or pr_free < 0:
			return
	else:
		if dist <= 0 or pr_free < 0 or not _shot_ok(sx, sy, ax, ay, dist, ty):
			return
	var p := pr_free
	pr_free = pr_next[p]
	pr_count += 1
	ammo[i] -= 1
	u_ammo[u] -= 1
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
	pr_tu[p] = ft
	var b := (tick + flight) % PR_BUCKETS
	pr_next[p] = pr_bucket[b]
	pr_bucket[b] = p


## Hilly maps: a shot from (sx, sy) at (ax, ay), dist apart, is within the
## height-adjusted range and, for a flat weapon, has a line of fire.
func _shot_ok(sx: int, sy: int, ax: int, ay: int, dist: int, ty: int) -> bool:
	var hs := elev_at(sx, sy) if obs_on != 0 else height_at(sx, sy)
	var ha := elev_at(ax, ay) if obs_on != 0 else height_at(ax, ay)
	if dist > range_h(ty, hs, ha):
		return false
	if dist > t_m_range[ty]:
		stat_range_up += 1
	if t_m_arc[ty] == 0 and lof_block(sx, sy, hs + LOF_EYE, ax, ay, ha + LOF_BODY,
			dist * t_m_apex[ty] / 100, 0) >= 0:
		stat_lof_blocked += 1
		return false
	return true


## A projectile lands: the nearest soldier (either side) within his hit radius
## of the landing point takes the hit.
func _land(p: int) -> void:
	var kind := t_m_kind[u_type[pr_unit[p]]]
	if kind == 1:
		_land_bolt(p)
		return
	if kind == 2:
		_land_stone(p)
		return
	var x := pr_x[p]
	var y := pr_y[p]
	var best := -1
	var best_d := 0
	# Soldiers of units near the enemy (melee, friend or foe) are in the grid.
	if stat_grid_soldiers > 0:
		var r := HIT_R_CAV
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
							var hr := HIT_R_CAV if u_cls[unit_of[j]] == UT.CLS_CAV else HIT_R_INF
							if d2 <= hr * hr and (best < 0 or d2 < best_d or (d2 == best_d and j < best)):
								best = j
								best_d = d2
						j = grid_next[j]
	# The unit aimed at, if it is not in the grid: find the slot under the
	# landing point from the formation geometry.
	var tu := pr_tu[p]
	if best < 0 and u_contact[tu] == 0 and u_alive[tu] > 0:
		var j := -1
		if u_state[tu] == U_READY and u_neng[tu] == 0 and u_wall[tu] == 0:
			j = _slot_at(tu, x, y)
		else:
			j = _nearest_in_unit(tu, x, y)
		if j >= 0:
			var dx := pos_x[j] - x
			var dy := pos_y[j] - y
			var hr := HIT_R_CAV if u_cls[tu] == UT.CLS_CAV else HIT_R_INF
			if dx * dx + dy * dy <= hr * hr:
				best = j
	if best >= 0 and map_on != 0:
		# Trees take some of what falls into woods; battlements shelter men
		# on a wall from shots from below.
		var vd := veg_d(x, y)
		if vd > 0:
			var stop: int = VEG_STOP_ARROW[vd] if t_m_arc[u_type[pr_unit[p]]] != 0 else VEG_STOP_JAV[vd]
			if _rand() % 100 < stop:
				stat_veg_stop += 1
				return
		if u_wall[unit_of[best]] > 0 and u_wall[pr_unit[p]] == 0 and _rand() % 100 < WALL_COVER[city_walls]:
			stat_wall_cover += 1
			return
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
	var ty := u_type[pr_unit[p]]
	var ud := unit_of[d]
	var td := u_type[ud]
	if _rand() % 100 >= MISSILE_HIT:
		return
	var from_def := FM.atan2_a(pr_sy[p] - pr_y[p], pr_sx[p] - pr_x[p])
	var sd := state[d]
	var frontal := sd != S_ROUTING and sd != S_DOWN \
		and absi(FM.angle_diff(facing[d], from_def)) <= FRONT_ARC
	if frontal and _rand() % 100 < t_mshield[td]:
		return
	stat_missile_hits += 1
	var arm := t_armour[td] * (100 - t_m_ap[ty]) / 100
	var dmg := maxi(t_m_dmg[ty] - arm, 3) * t_m_vuln[td] / 100 * (85 + _rand() % 31) / 100
	if u_state[ud] == U_READY:
		var unit_rel := absi(FM.angle_diff(u_face[ud], from_def))
		u_morale[ud] -= MORALE_MISSILE_HIT if unit_rel <= FRONT_ARC else MORALE_MISSILE_FLANK
		u_hit_t[ud] = tick
	var h := hp[d] - dmg
	# A horse struck may simply go down, rider and all.
	if h <= 0 or (t_m_down[td] > 0 and _rand() % 100 < t_m_down[td]):
		stat_kills[3] += 1
		_remove(d, GONE_KILLED)
	else:
		hp[d] = h


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
		var rng := t_m_range[ty]
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
		return _clear_line(u, t) and lof_units(u, t)
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
		if u_state[u] != U_READY or u_alive[u] <= 0:
			# Broken or gone: the engines are left where they stand.
			for k in ne:
				var e := e0 + k
				if e_state[e] == E_OK:
					e_state[e] = E_ABANDONED
					e_crew[e] = 0
					u_ammo[u] -= e_ammo[e]
					stat_abandoned += 1
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
		for slot in u_alive[u]:
			var i := slot_soldier[base + slot]
			if state[i] != S_FORMED:
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
		var need := t_m_reload[ty] * t_crew[ty]
		for k in ne:
			var e := e0 + k
			if e_state[e] != E_OK or e_ammo[e] <= 0:
				continue
			if e_crew[e] < t_crew_min[ty]:
				continue  # silent: too few hands
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
	for k in u_neng[u]:
		var e := e0 + k
		if e_state[e] != E_OK or e_ammo[e] >= t_m_ammo[ty] or u_reserve[u] <= 0:
			continue
		more = true
		if e_crew[e] < t_crew_min[ty]:
			continue
		e_rwork[e] += e_crew[e]
		if e_rwork[e] >= need:
			e_rwork[e] -= need
			e_ammo[e] += 1
			u_ammo[u] += 1
			u_reserve[u] -= 1
			stat_refilled += 1
	if not more:
		u_refill[u] = 0


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
	if ter_on == 0 and map_on == 0:
		if dist > t_m_range[ty] or dist < t_m_min[ty] or dist <= 0:
			return false
	elif dist < t_m_min[ty] or dist <= 0 or not _shot_ok(sx, sy, ax, ay, dist, ty):
		return false
	var p := pr_free
	pr_free = pr_next[p]
	pr_count += 1
	e_ammo[e] -= 1
	u_ammo[u] -= 1
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
	pr_tu[p] = ft
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
	if dist < t_m_min[ty] or dist <= 0 or not _shot_ok(sx, sy, gf.x, gf.y, dist, ty):
		return false
	var p := pr_free
	pr_free = pr_next[p]
	pr_count += 1
	e_ammo[e] -= 1
	u_ammo[u] -= 1
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
	pr_tu[p] = -2 - g
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
	if pr_tu[p] <= -2 and _gate_hit(p, GATE_BOLT):
		return
	var u := pr_unit[p]
	var ty := u_type[u]
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
			t_m_plough[ty])
		if blk >= 0:
			a1 = mini(a1, blk)
			stat_bolt_ground += 1
	_sweep(sx, sy, ux, uy, BOLT_SKIP, a1, BOLT_R_INF, BOLT_R_CAV)
	var energy := t_m_dmg[ty]
	var from := FM.atan2_a(-dy, -dx)
	var hits := 0
	_hit_units.fill(-1)
	for k in _sw_n:
		if energy < SHOT_STOP or hits >= t_m_pierce[ty]:
			break
		var v := _sw_v[k]
		if ter_on != 0 or obs_on != 0:
			var vx := e_x[-v - 1] if v < 0 else pos_x[v]
			var vy := e_y[-v - 1] if v < 0 else pos_y[v]
			var rel := z0 + dz * _sw_a[k] / dist - elev_at(vx, vy)
			if rel < BOLT_BODY_LO or rel > BOLT_BODY_HI:
				continue
		if v < 0:
			_engine_hit(-v - 1, energy)
			break
		if state[v] >= S_DEAD:
			continue
		if _rand() % 100 >= 100 - 12 * hits:
			continue  # passes him by
		var td := u_type[unit_of[v]]
		var sv := state[v]
		var sh := 0
		if sv != S_ROUTING and sv != S_DOWN and absi(FM.angle_diff(facing[v], from)) <= FRONT_ARC:
			sh = t_mshield[td] * BOLT_SHIELD_K / 100
		var e1 := energy - sh
		var dmg := maxi(e1 - t_armour[td] * (100 - t_m_ap[ty]) / 100, 1) * t_m_vuln[td] / 100 \
			* (85 + _rand() % 31) / 100
		_art_wound(v, dmg, u, 0)
		energy = e1 - BOLT_BODY - t_armour[td]
		hits += 1
	_art_fright(ty)


## A stone: lobbed over everything, it smashes whoever is within m_blast of
## where it lands, then bounces and ploughs on m_plough along its flight
## through the ranks behind, knocking men down, losing energy with every
## body (STONE_BODY + armour) and every metre. Friend or foe alike. Engines
## it reaches take double damage (counter-battery fire).
func _land_stone(p: int) -> void:
	if pr_tu[p] <= -2 and _gate_hit(p, GATE_STONE):
		return
	var u := pr_unit[p]
	var ty := u_type[u]
	var lx := pr_x[p]
	var ly := pr_y[p]
	var dx := lx - pr_sx[p]
	var dy := ly - pr_sy[p]
	var dist := maxi(FM.approx_len(dx, dy), 1)
	var ux := dx * FM.TRIG_ONE / dist
	var uy := dy * FM.TRIG_ONE / dist
	var blast := t_m_blast[ty]
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
	var energy0 := t_m_dmg[ty]
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
		if hits >= t_m_pierce[ty]:
			break
		var al := _sw_a[k]
		var lt := _sw_l[k]
		var v := _sw_v[k]
		var cav := v >= 0 and u_cls[unit_of[v]] == UT.CLS_CAV
		if al <= blast:
			# Direct hit: within the blast circle round the landing point.
			if al * al + lt * lt > blast * blast:
				continue
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
		var td := u_type[unit_of[v]]
		var dmg := maxi(energy - t_armour[td] * (100 - t_m_ap[ty]) / 100, 1) * t_m_vuln[td] / 100 \
			* (85 + _rand() % 31) / 100
		_art_wound(v, dmg, u, mini(energy / 2 + STONE_KNOCK, 90))
		absorbed += STONE_BODY + t_armour[td]
		hits += 1
	_art_fright(ty)


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
		stat_art_kills += 1
		_remove(v, GONE_KILLED)
		return
	hp[v] = h
	if knock > 0 and _rand() % 100 < knock:
		_knock_down(v)


## Fright for every unit one shot struck (once per unit per shot).
func _art_fright(ty: int) -> void:
	for k in 4:
		var uv := _hit_units[k]
		if uv < 0:
			break
		if u_state[uv] == U_READY:
			u_fright[uv] = mini(u_fright[uv] + t_m_fear[ty], FRIGHT_MAX)


# ---------------------------------------------------------------- morale ---

func _update_morale() -> void:
	for u in n_units:
		var us := u_state[u]
		if us >= U_DESTROYED:
			continue
		var ty := u_type[u]
		var m := u_morale[u]
		var periodic := (u + tick) % TICKS_PER_SECOND == 0
		u_recent[u] -= u_recent[u] >> RECENT_DECAY_SHIFT
		if u_fright[u] > 0:
			u_fright[u] = maxi(u_fright[u] - FRIGHT_DECAY, 0)
		if us == U_READY:
			if u_contact[u] == 0 and u_fighting[u] == 0 and tick - u_hit_t[u] > UNDER_FIRE_TICKS:
				var base_m := t_morale[ty]
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
	u_state[u] = U_ROUTING
	u_routs[u] += 1
	u_sq[u] = 0
	u_gtarget[u] = -1
	if obs_on != 0:
		u_pn[u] = 0
	u_order[u] = O_NONE
	if u_wall[u] > 0:
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


func _check_winner() -> void:
	if winner >= 0:
		if ended == 0:
			var loser_on := 0
			for u in n_units:
				if winner < 2 and u_side[u] != winner and u_state[u] < U_DESTROYED:
					loser_on += 1
			if winner == 2 or loser_on == 0 or tick - decided_tick >= END_AFTER:
				ended = 1
		return
	# A side still fights while it has a ready unit that is not withdrawing.
	var ready := [0, 0]
	for u in n_units:
		if u_state[u] == U_READY and u_order[u] != O_WITHDRAW:
			ready[u_side[u]] += 1
	if ready[0] == 0 and ready[1] > 0:
		winner = 1
	elif ready[1] == 0 and ready[0] > 0:
		winner = 0
	elif (ready[0] == 0 and ready[1] == 0) or tick >= TIME_LIMIT:
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
## withdrew, and are still on the field ("remaining"), plus side totals.
func result() -> Dictionary:
	var units: Array = []
	var sides: Array = []
	for s in 2:
		sides.append({"side": s, "started": 0, "killed": 0, "routed_off": 0,
			"withdrawn": 0, "remaining": 0})
	for u in n_units:
		var r := {"unit": u, "side": u_side[u], "type": u_type[u],
			"started": u_count0[u], "killed": u_killed[u],
			"routed_off": u_routed_off[u], "withdrawn": u_withdrawn[u],
			"remaining": u_alive[u], "state": u_state[u]}
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
	"ws_jx": true, "ws_jy": true, "cmp": true, "n_cmp": true, "g_cmp": true, "_croot": true, "_croot_ep": true}
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
	ctx.update(ai_phase.to_byte_array())
	ctx.update(ai_t.to_byte_array())
	ctx.update(ai_hold.to_byte_array())
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
		if obs_on != 0:
			for arr in _stair_arrays():
				ctx.update((arr as PackedInt32Array).to_byte_array())
		if n_gates > 0:
			ctx.update(g_hp.to_byte_array())
			ctx.update(g_state.to_byte_array())
		ctx.update(ai_prog.to_byte_array())
	var digest := ctx.finish()
	return digest.decode_u32(0)
