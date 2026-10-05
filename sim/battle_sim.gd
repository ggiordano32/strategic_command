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
##   read access to the packed arrays below (view must not write them).
##
## Coordinates: 1 m = 1024 units, x right, y down. Angles 0..1023, 0 = +x,
## increasing clockwise on screen (towards +y). See fixed_math.gd.

const FM := preload("res://sim/fixed_math.gd")
const UT := preload("res://sim/unit_types.gd")
const BattleAI := preload("res://sim/battle_ai.gd")

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

## Unit fields an order can change; OrderPreview predicts exactly these.
const ORDER_KEYS: Array[String] = ["order", "ax", "ay", "face", "files", "dx", "dy",
	"dface", "target", "run", "fire", "skirm", "deploy"]

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
var e_px := PackedInt32Array()      # view only: position last tick (not hashed)
var e_py := PackedInt32Array()

# Battle AI, per side.
var ai_phase := PackedInt32Array([0, 0])
var ai_t := PackedInt32Array([0, 0])

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

# Spatial grid, one per side so target search only walks enemies.
var grid_w: int = 0
var grid_h: int = 0
var grid_head0 := PackedInt32Array()
var grid_head1 := PackedInt32Array()
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
## Battle AI decisions by unit mode (BattleAI.A_*), plus [8] army withdrawals.
var stat_ai := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
var stat_bolts: int = 0        # bolts fired
var stat_stones: int = 0       # stones fired
var stat_art_victims: int = 0  # soldiers struck by artillery
var stat_art_kills: int = 0
var stat_deploys: int = 0      # batteries finished setting up
var stat_packs: int = 0        # batteries finished packing up
var stat_wrecked: int = 0      # engines wrecked
var stat_abandoned: int = 0    # engines abandoned
var stat_engine_hits: int = 0  # shots that struck an engine
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
##   "units": [{"side", "type", "count", "x_m", "y_m", "facing", "files"}, ...],
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
	slot_soldier.resize(n)
	off_x.resize(n)
	off_y.resize(n)
	_rm.resize(n)
	_rm_why.resize(n)
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
		var ne := _engines_for(ty, cnt)
		u_eng0[u] = eng
		u_neng[u] = ne
		if ne > 0:
			# Artillery: files = engines; ammunition belongs to the engines.
			u_files[u] = ne
			u_ammo[u] = ne * t_m_ammo[ty]
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
	grid_next.resize(n)
	_update_bounds()
	_update_units_stats()

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
		u_shelled_t, u_shelled_by, u_emove]


func _engine_arrays() -> Array:
	return [e_unit, e_x, e_y, e_face, e_hp, e_state, e_reload, e_ammo, e_crew]


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
		t_m_lead, t_crew, t_crew_min, t_m_kind, t_m_min, t_m_pierce, t_m_plough, t_m_blast,
		t_m_fear, t_arc, t_traverse, t_deploy, t_e_hp]
	var keys := ["cls", "attack", "defence", "armour", "shield", "mshield",
		"damage", "reach", "ranks_reach", "mass", "walk", "run", "hp", "cooldown",
		"morale", "file_sp", "rank_sp", "turn", "brace", "vs_cav", "charge",
		"sec_attack", "sec_defence", "sec_damage", "sec_reach", "m_range",
		"m_damage", "m_ap", "m_ammo", "m_reload", "m_spread", "m_spread0",
		"m_speed", "m_arc", "skirm", "m_vuln", "m_down", "m_lead", "crew", "crew_min",
		"m_kind", "m_min", "m_pierce", "m_plough", "m_blast", "m_fear", "arc", "traverse",
		"deploy", "e_hp"]
	for k in arrays.size():
		var arr: PackedInt32Array = arrays[k]
		arr.resize(nt)
		for t in nt:
			arr[t] = UT.stat(t, keys[k])


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
			u_dirty[u] = 1
			u_settled[u] = 0


## The ORDER_KEYS fields of unit u as a Dictionary.
static func order_fields(sim, u: int) -> Dictionary:
	return {"order": sim.u_order[u], "ax": sim.u_ax[u], "ay": sim.u_ay[u],
		"face": sim.u_face[u], "files": sim.u_files[u], "dx": sim.u_dx[u],
		"dy": sim.u_dy[u], "dface": sim.u_dface[u], "target": sim.u_target[u],
		"run": sim.u_run[u], "fire": sim.u_fire[u], "skirm": sim.u_skirm[u],
		"deploy": sim.u_deploy[u]}


## Units an order applies to (in index order): its unit, or every ready unit
## of the side for an army-wide withdrawal. Shared with OrderPreview.
static func order_units(sim, o: Dictionary) -> Array[int]:
	var out: Array[int] = []
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
	if typ == ORDER_MOVE:
		var x := clampi(int(o["x"]), 0, sim.field_w)
		var y := clampi(int(o["y"]), 0, sim.field_h)
		var face := int(o["facing"]) & FM.ANGLE_MASK
		if not art:
			d["files"] = width_to_files(int(o["width"]), sim.u_alive[u], ty)
		d["run"] = 1 if int(o.get("run", 0)) != 0 and not art else 0
		d["target"] = -1
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
		var t := int(o["target"])
		if t < 0 or t >= sim.n_units or sim.u_side[t] == sim.u_side[u] or sim.u_state[t] >= U_DESTROYED:
			return
		d["order"] = O_ATTACK
		d["target"] = t
		d["run"] = 1 if int(o.get("run", 0)) != 0 and not art else 0
	elif typ == ORDER_HALT:
		d["order"] = O_NONE
		d["target"] = -1
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
	elif typ == ORDER_WITHDRAW or typ == ORDER_WITHDRAW_ALL:
		d["order"] = O_WITHDRAW
		d["target"] = -1
		d["run"] = 0 if art else 1
		d["dx"] = d["ax"]
		d["dy"] = sim.field_h if sim.u_side[u] == 0 else 0
		d["dface"] = 256 if sim.u_side[u] == 0 else 768


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
	var files := mini(u_files[u], alive)
	var ty := u_type[u]
	_fill_offsets(off_x, u_slot_base[u], alive, files, u_face[u], false, off_y,
		t_fsp[ty], t_rsp[ty])
	u_dirty[u] = 0


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
	var files := maxi(mini(u_files[u], u_alive[u]), 1)
	var ranks := (u_alive[u] + files - 1) / files
	return maxi(ranks - 1, 0) * t_rsp[u_type[u]]


## Half the frontage of a unit's formation in sim units.
func unit_half_width(u: int) -> int:
	var files := maxi(mini(u_files[u], u_alive[u]), 1)
	return (files - 1) * t_fsp[u_type[u]] / 2


# ----------------------------------------------------------------- step ---

func step() -> void:
	_apply_orders()
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
	if n_eng > 0:
		_update_artillery()
	_update_missiles()
	_refresh_offsets()
	_update_morale()
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
	for u in n_units:
		u_moved[u] = 0
		if u_state[u] != U_READY:
			u_formed[u] = 0
			u_braced[u] = 0
			u_mom[u] = 0
			continue
		var ty := u_type[u]
		var cls := u_cls[u]
		var speed := t_run[ty] if u_run[u] != 0 else t_walk[ty]
		var aspeed := (speed * 7) >> 3
		var ax0 := u_ax[u]
		var ay0 := u_ay[u]
		var order := u_order[u]
		var want_face := u_dface[u]
		var art := cls == UT.CLS_ART
		if art and (order == O_MOVE or order == O_WITHDRAW) and u_depl[u] > 0:
			# Packing up first: the battery cannot move until it is packed.
			want_face = u_face[u]
		elif art and order != O_MOVE and order != O_WITHDRAW:
			# Batteries never close on a target: they turn to bring it into
			# their arc (attack order or fire at will) and shoot from here.
			want_face = u_dface[u]
			var at := u_target[u] if order == O_ATTACK else u_ftarget[u]
			if order == O_ATTACK and (at < 0 or u_state[at] >= U_DESTROYED):
				u_order[u] = O_NONE
				u_target[u] = -1
				at = -1
			if at >= 0 and at < n_units and u_state[at] < U_DESTROYED:
				var bear := FM.atan2_a(u_cy[at] - u_cy[u], u_cx[at] - u_cx[u])
				if absi(FM.angle_diff(u_face[u], bear)) > t_arc[ty]:
					want_face = bear
					u_dface[u] = bear
		elif order == O_MOVE or order == O_WITHDRAW:
			var dx := u_dx[u] - u_ax[u]
			var dy := u_dy[u] - u_ay[u]
			var d := FM.isqrt(dx * dx + dy * dy)
			if d <= aspeed:
				u_ax[u] = u_dx[u]
				u_ay[u] = u_dy[u]
				if order == O_MOVE:
					u_order[u] = O_NONE
			else:
				u_ax[u] += dx * aspeed / d
				u_ay[u] += dy * aspeed / d
				# March facing the direction of travel; turn to the final
				# facing for the last stretch.
				if d > REFORM_IN_PLACE_DIST:
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
				if u_charge[u] != 0:
					pass  # riders resolve the charge themselves; anchor waits
				elif cls == UT.CLS_MISSILE and u_ammo[u] > 0:
					# Shoot it: close to most of the range, then stand.
					if d > 0:
						want_face = FM.atan2_a(dy, dx)
					var stop := t_m_range[ty] * 17 / 20
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
					if d > stop:
						var mv := mini(aspeed, d - stop)
						u_ax[u] += dx * mv / d
						u_ay[u] += dy * mv / d
				u_dface[u] = want_face
		_turn(u, want_face)
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
			_deploy_state(u, order, moved)
		var dis := maxi(u_disorder[u] - 2, 0)
		if cls == UT.CLS_PIKE and u_run[u] != 0 and moved > 0:
			dis = maxi(dis, DISORDER_RUN)
		u_disorder[u] = dis
		var steady := dis < DISORDERED and u_morale[u] >= WAVER
		if cls == UT.CLS_PIKE:
			var turning := absi(FM.angle_diff(u_face[u], u_dface[u])) > TURN_DISORDER
			u_formed[u] = 1 if steady and not turning and u_alive[u] >= 2 * mini(u_files[u], u_alive[u]) else 0
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
				u_mom[u] = mini(u_mom[u] + MOM_GAIN, 100)
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
	elif moved == 0 and u_emove[u] == 0 and d < full:
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
			if t >= 0 and u_state[t] < U_DESTROYED and _unit_dist(u, t) <= rng:
				ft = t
		elif u_fire[u] != 0:
			# Fire at will: keep shooting the current target while it stays in
			# range (busy archers do not swing round to every new threat),
			# otherwise the nearest enemy in range, preferring units that are
			# not locked in melee with our own side.
			var cur := u_ftarget[u]
			if cur >= 0 and u_state[cur] < U_DESTROYED and u_side[cur] != u_side[u] \
					and _unit_dist(u, cur) <= rng and (u_fighting[cur] == 0 or not _any_clean_target(u, rng)):
				u_ftarget[u] = cur if t_m_arc[ty] != 0 or _clear_line(u, cur) else -1
				return
			var best := 0
			var best_engaged := true
			for o in n_units:
				if u_side[o] == u_side[u] or u_state[o] >= U_DESTROYED:
					continue
				var d := _unit_dist(u, o)
				if d > rng:
					continue
				var engaged := u_fighting[o] > 0
				if ft < 0 or (best_engaged and not engaged) or (engaged == best_engaged and d < best):
					ft = o
					best = d
					best_engaged = engaged
		if ft >= 0 and t_m_arc[ty] == 0 and not _clear_line(u, ft):
			ft = -1
	u_ftarget[u] = ft


## An enemy in range that is not locked in melee.
func _any_clean_target(u: int, rng: int) -> bool:
	for o in n_units:
		if u_side[o] != u_side[u] and u_state[o] < U_DESTROYED and u_fighting[o] == 0 \
				and _unit_dist(u, o) <= rng:
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
	for u in n_units:
		if u_contact[u] == 0:
			continue
		var head: PackedInt32Array = grid_head0 if u_side[u] == 0 else grid_head1
		var base := u_slot_base[u]
		for s in u_alive[u]:
			var i := slot_soldier[base + s]
			var c := clampi((pos_y[i] >> gs) * gw + (pos_x[i] >> gs), 0, gmax)
			grid_next[i] = head[c]
			head[c] = i
			cnt += 1
	stat_grid_soldiers = cnt


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
		if u_state[u] == U_ROUTING:
			var rs := (run * 7) >> 3
			var flx := u_flee_x[u]
			var fly := u_flee_y[u]
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
		var is_cav := u_cls[u] == UT.CLS_CAV
		var umom := u_mom[u]
		var cg := chg

		var minx := fw
		var maxx := 0
		var miny := fh
		var maxy := 0
		var sumx := 0
		var sumy := 0
		if u_contact[u] == 0 and u_down[u] == 0 and u_charge[u] == 0:
			# Fast path: slot following only (no separation, no search).
			for s in alive:
				var k := base + s
				var i := ss[k]
				var x := px[i]
				var y := py[i]
				var dx := ax + oxs[k] - x
				var dy := ay + oys[k] - y
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
				px[i] = x
				py[i] = y
				sumx += x
				sumy += y
				if x < minx: minx = x
				if x > maxx: maxx = x
				if y < miny: miny = y
				if y > maxy: maxy = y
				if withdrawing and (y > exit_y if exit_y > EDGE_EXIT else y < exit_y):
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
		var tg := target
		var cd := cooldown
		var gnext := grid_next
		var gs := GRID_SHIFT
		var gw := grid_w
		var gmax := grid_w * grid_h - 1
		var tk := tick
		var files := maxi(mini(u_files[u], alive), 1)
		var reach := u_reach[u]
		var want := (reach * 3) >> 2
		var half_reach := reach >> 1
		var cool := t_cooldown[ty]
		var side := u_side[u]
		var enemy_head: PackedInt32Array = grid_head1 if side == 0 else grid_head0
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
					t = _find_target_cone(x, y, SEARCH_FRONT, fcos, fsin, enemy_head)
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
						t = _find_target_cone(x, y, reach, fcos, fsin, enemy_head)
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
				if t < 0:
					# Every rider looks ahead, not just the front rank.
					var wide := front or is_cav
					if lost or (tk + i) % (3 if wide else 7) == 0:
						if wide and not shy:
							t = _find_target(x, y, SEARCH_FRONT, 2, enemy_head)
						else:
							t = _find_target(x, y, rear_r, 2, enemy_head)
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
			px[i] = nx
			py[i] = ny
			counted += 1
			sumx += nx
			sumy += ny
			if nx < minx: minx = nx
			if nx > maxx: maxx = nx
			if ny < miny: miny = ny
			if ny > maxy: maxy = ny
			if withdrawing and (ny > exit_y if exit_y > EDGE_EXIT else ny < exit_y):
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
					if d2 < best_d or (d2 == best_d and j < best):
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
	var chance := clampi(BASE_HIT + att - def + bonus - pen, 5, 95)
	if _rand() % 100 >= chance:
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
			u_disorder[ud] = mini(u_disorder[ud] + DISORDER_REAR_HIT, DISORDER_MAX)
		elif zone == ZONE_FLANK:
			u_morale[ud] -= MORALE_FLANK_HIT
			u_disorder[ud] = mini(u_disorder[ud] + DISORDER_FLANK_HIT, DISORDER_MAX)
	var h := hp[d] - dmg
	if h <= 0:
		stat_kills[0 if frontal else 1] += 1
		_remove(d, GONE_KILLED)
	else:
		hp[d] = h


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
			if u_alive[uv] > 2 * maxi(mini(u_files[uv], u_alive[uv]), 1):
				knock = mini(force + 10, 90) / 2
			else:
				knock = mini(force + 10, 90)
		else:
			knock = mini(force + 10, 90)
	var dmg := maxi(force - arm, 1) * (85 + _rand() % 31) / 100
	if u_state[uv] == U_READY:
		u_morale[uv] -= shock
		u_disorder[uv] = mini(u_disorder[uv] + DISORDER_IMPACT, DISORDER_MAX)
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
	target[d] = -1
	u_ammo[u] -= ammo[d]
	ammo[d] = 0
	var alive := u_alive[u]
	var base := u_slot_base[u]
	var files := maxi(u_files[u], 1)
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
	if dist > t_m_range[ty] or dist <= 0 or pr_free < 0:
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
		if u_state[tu] == U_READY and u_neng[tu] == 0:
			j = _slot_at(tu, x, y)
		else:
			j = _nearest_in_unit(tu, x, y)
		if j >= 0:
			var dx := pos_x[j] - x
			var dy := pos_y[j] - y
			var hr := HIT_R_CAV if u_cls[tu] == UT.CLS_CAV else HIT_R_INF
			if dx * dx + dy * dy <= hr * hr:
				best = j
	if best >= 0:
		_missile_hit(p, best)


## Soldier nearest to (x, y) among the formation slot under that point and
## its neighbours (soldiers are often a little off their slots), or -1.
func _slot_at(u: int, x: int, y: int) -> int:
	var ty := u_type[u]
	var fsp := t_fsp[ty]
	var rsp := t_rsp[ty]
	var alive := u_alive[u]
	var files := maxi(mini(u_files[u], alive), 1)
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
	if u_ammo[u] > 0 and order != O_MOVE and order != O_WITHDRAW:
		var rng := t_m_range[ty]
		var mn := t_m_min[ty]
		if order == O_ATTACK:
			var t := u_target[u]
			if t >= 0 and u_state[t] < U_DESTROYED and _art_in_range(u, t, mn, rng):
				ft = t
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
					if not _art_in_range(u, o, mn, rng) or not art_safe(u, o):
						continue
					var score := 1000 + u_alive[o] * 4 - _unit_dist(u, o) / M
					if u_moved[o] == 0:
						score += 200
					var bear := FM.atan2_a(u_cy[o] - u_cy[u], u_cx[o] - u_cx[u])
					if absi(FM.angle_diff(u_face[u], bear)) <= t_arc[ty]:
						score += 400
					if ft < 0 or score > best_score:
						ft = o
						best_score = score
	u_ftarget[u] = ft


func _art_in_range(u: int, t: int, mn: int, rng: int) -> bool:
	var d := FM.approx_len(u_cx[t] - u_cx[u], u_cy[t] - u_cy[u])
	return d >= mn and _unit_dist(u, t) <= rng


## True when battery u can shoot at t without (probably) hitting friends:
## bolts need a clear line, stones a target with no friends close to it.
## Also used by the battle AI.
func art_safe(u: int, t: int) -> bool:
	if t_m_kind[u_type[u]] == 1:
		return _clear_line(u, t)
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
			else:
				# Traverse toward the target, within the arc of the battery.
				var want := face
				if ft >= 0:
					var bear := FM.atan2_a(u_cy[ft] - e_y[e], u_cx[ft] - e_x[e])
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
		# Shoot: set up, standing, a target, loaded, crewed and on the bearing.
		if u_depl[u] < full or ft < 0 or u_moved[u] != 0:
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
			var bear := FM.atan2_a(u_cy[ft] - e_y[e], u_cx[ft] - e_x[e])
			if absi(FM.angle_diff(e_face[e], bear)) > ALIGN:
				continue
			if _art_fire(e, u, ft, ty):
				e_reload[e] = 0


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
	var ax := pos_x[j]
	var ay := pos_y[j]
	if t_m_lead[ty] != 0:
		var vx := pos_x[j] - prev_x[j]
		var vy := pos_y[j] - prev_y[j]
		for k in 2:
			var fl := FM.approx_len(ax - sx, ay - sy) / spd + 3
			ax = pos_x[j] + vx * fl
			ay = pos_y[j] + vy * fl
	var dx := ax - sx
	var dy := ay - sy
	var dist := FM.approx_len(dx, dy)
	if dist > t_m_range[ty] or dist < t_m_min[ty] or dist <= 0:
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
	var u := pr_unit[p]
	var ty := u_type[u]
	var sx := pr_sx[p]
	var sy := pr_sy[p]
	var dx := pr_x[p] - sx
	var dy := pr_y[p] - sy
	var dist := maxi(FM.approx_len(dx, dy), 1)
	var ux := dx * FM.TRIG_ONE / dist
	var uy := dy * FM.TRIG_ONE / dist
	_sweep(sx, sy, ux, uy, BOLT_SKIP, dist + t_m_plough[ty], BOLT_R_INF, BOLT_R_CAV)
	var energy := t_m_dmg[ty]
	var from := FM.atan2_a(-dy, -dx)
	var hits := 0
	_hit_units.fill(-1)
	for k in _sw_n:
		if energy < SHOT_STOP or hits >= t_m_pierce[ty]:
			break
		var v := _sw_v[k]
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
	_sweep(lx, ly, ux, uy, -blast, t_m_plough[ty], r, maxi(blast, STONE_R_CAV))
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
	u_order[u] = O_NONE
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
	u_morale[u] = RALLY_THRESHOLD
	var e := _nearest_enemy_unit(u, false)
	var face := u_face[u]
	if e >= 0:
		face = FM.atan2_a(u_cy[e] - u_cy[u], u_cx[e] - u_cx[u])
	u_face[u] = face
	u_dface[u] = face
	u_ax[u] = u_cx[u]
	u_ay[u] = u_cy[u]
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


## 32-bit hash of the full simulation state (MD5 of every state array).
func state_hash() -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	# Pending (future) orders are deliberately left out: in lockstep a peer
	# may already hold orders the other has not received yet.
	var header := PackedInt64Array([tick, rng_state, winner, decided_tick, ended,
		n, n_units, pr_free, pr_count, n_eng])
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
	var digest := ctx.finish()
	return digest.decode_u32(0)
