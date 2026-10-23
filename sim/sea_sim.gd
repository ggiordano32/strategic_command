extends RefCounted
## Real-time sea battle (N3a; docs/DESIGN.md "Sea battles (as built, N3a)").
##
## A sibling of BattleSim, not a mode inside it: a sea battle has a handful
## of ships and no soldiers, so it shares none of BattleSim's per-man
## arrays, maps or engines; keeping it apart leaves every land battle (and
## Rome) byte-identical. It keeps the same discipline and the interface the
## lockstep layer needs (sim/lockstep.gd picks it for a scenario with
## "sea"): integer / fixed-point maths only (sim/fixed_math.gd: 1 m = 1024
## units, angles 0..1023 with 0 along +x and growing toward +y), the sim's
## own xorshift RNG, fixed iteration order (ship index), orders queued with
## (tick, player, seq), state_hash() over every state array, snapshot() /
## restore() of every script variable. A tick is 0.1 s (lockstep runs one
## per frame at 1x).
##
## Ships (index s, the scenario's "units" in order) are pieces with a
## position, a heading (x16 for smooth turns), a speed, a sail setting
## (stop / battle / full), hull, rigging and crew, troops aboard (they fight
## boardings), two broadsides (port 0, starboard 1) each loaded with a shot
## kind and reloading, a mode (hold course, sail to a point, engage a
## target, board a target, flee, hold a heading) and a state (u_state:
## fighting, struck, sunk, taken, fled).
##
## The wind blows from w_from (an angle) at w_str (0-100); it shifts a
## little every WIND_EVERY ticks (seeded, within WIND_SPAN of the start).
## Points of sail (_drive): no drive inside the no-go zone (the row's
## "irons", off the wind), then rising to the best on a broad reach;
## rowed ships ignore the wind. The navigator (_course) beats to windward
## in two tacks (laylines) and turns through the wind when the ship has
## the way for it ("tack" % of its top speed), else wears round; turning
## through the wind she carries her way (TACK_WAY), head to wind otherwise
## she loses it fast; a ship caught in irons without way falls off. Land
## and shoals (a grid from "land": open sea, an island, a coast on the
## sides the campaign cell has land) stop ships; deep-draught ships run
## aground on shoals. Sea room (sea pass 4): probes look down a lane her
## beam wide; a new board is the one with SEA_ROOM_M of clear water ahead,
## she tacks LAYLINE_M short of land or the edge, within LEE_SHORE_M of a
## lee shore she sails along it and never in toward it, and a ship aground
## amidships works off once her bow points at open water. The fleets start
## clear of shoals and land (START_CLEAR_M, the leeward fleet LEE_ROOM_M to
## leeward and on both beams; _layout shifts the lines).
##
## Broadsides: each side fires all its working guns at once when loaded and
## a target lies in its arc (ARC) and in range of the loaded shot: round
## shot breaks the hull (and kills by splinters), chain the rigging (speed),
## grape the crew (short range). Each gun hits at a % by range, target
## size and the gun crew's quality; raking (from ahead or astern of the
## target) kills 1.5-2 x the men. Reload time grows when the crew is too
## thin to work the guns. Round shot can start a fire; a fire the crew does
## not put out can reach the magazine (the ship blows up and scorches her
## neighbours). Hull 0: she sinks.
##
## Boarding: a ship ordered to board sails alongside; close and at a low
## relative speed she grapples, both stop, and the crews fight it out on the
## decks (N3b, "deck melee" below): the defenders strike when the deck is
## lost, or the boarders are thrown back, or both crews are spent and the
## ships drift apart. With the scenario's "deck" 1 the sim does not resolve
## a boarding itself: deck_request() lists the grappled pairs and their
## crews and O_DECK applies an outside melee's result (the N3b hook, kept).
##
## Deck melee (N3b): the two decks side by side as a small grid of
## DECK_CELL_M cells (each ship's length by her beam, masts in the way), the
## boarding party (DECK_BOARD_PCT % of the crew and every soldier aboard)
## against the defenders, as figures of a few men each (at most DECK_FIG a
## side: one is the captain and his mates). Every DECK_EVERY ticks each
## figure, in index order (reversed every other step), strikes the nearest
## enemy figure next to it (men x DECK_KILL_PM x atk / (atk + def), a
## figure on its own deck defending at DECK_BONUS_PCT), else fires its
## pistols / muskets / bows when loaded and in reach (shot % of its men
## hit), else steps a cell toward it. Arms come from the crew kit (the
## faction: ST.DECK_CREWS, the boarding quality bq on top) and the troops'
## unit rows (ST.DECK_LINE_SHOT by line); the captain fights at
## DECK_CAPTAIN_ATK %. Each side's morale falls with its losses (less while
## its captain stands; DECK_CAPT_LOSS when he falls). The defenders strike
## (taken: the existing capture) when their morale is gone or they are
## under DECK_BREAK_DEF % of the boarders; the boarders are thrown back
## when theirs is gone or they are under DECK_BREAK_ATT %; both at once or
## after DECK_MAX_TICKS: both crews are spent and the ships part.
##
## Fire (N3c): a fire has an intensity (s_burn 1..FIRE_MAX) that grows a
## little every second and is fought down by the crew (FIRE_FIGHT x the
## crew's share); it eats the hull by its intensity. Past MAG_LV each
## second rolls (sim RNG) for the magazine: she blows up, holing, killing
## and setting alight her neighbours within BLAST_M. Douse (O_DOUSE, s_douse;
## 2026-10-22): while she burns, all hands to the buckets: her guns neither
## fire nor reload (loaded guns keep their load), the crew fight the fire at
## DOUSE_FIGHT_PCT %, her men in a deck melee strike and fire at
## DOUSE_DECK_PCT %; off by itself the second the fire is out (refused with
## no fire, and for a fire ship). Fire ships (rows with
## "fire"): sailed at a mark (M_FIRE), lit when she can lie the course
## within FS_LIGHT_M, her crew lash the helm and take to the boat at
## FS_ABANDON_M; whatever she touches she grapples (FS_STICK_TICKS) and sets
## alight at FS_FIRE, feeding the blaze while alongside; she burns down
## and sinks. The battle AI sends her at the biggest enemy when the wind
## serves (the mark lies at least FS_SERVES off the wind), else keeps her
## up to windward of it.
##
## Morale: hits, losses and raking lower it, quiet time restores it; a ship
## strikes her colours at 0, or when her crew or hull is nearly gone with an
## enemy near. A struck ship stops and is out of the fight; it is taken by
## the winner when the battle is decided. The battle is decided when a side
## has no ship fighting (sunk, struck, taken or fled off the map edge), or
## at the time limit by the fighting power left (ties: side 1, the
## defender).
##
## Battle AI (sides with ai_sides 1; every ship thinks every 10 ticks,
## staggered): flee to the far edge when beaten, else pick the nearest
## weakest enemy; board (coming up under her stern) when its boarding
## strength, with friends already boarding her, is BOARD_PCT % of the
## target's or more; else engage: from far off by the engagement rule
## (_closing: the weather gauge only for a ship that has it or can take it
## in one board, and she bears down to her range; a leeward ship makes for
## the enemy's lee bow, on a reach when she can, never beating past her;
## a leeward AI fleet whose enemy lies beyond two boards to windward holds
## its line hove to for up to HOLD_TICKS), then keep the broadside on at
## the shot's range, presenting the loaded side, rake when the geometry
## offers it; grape close, chain to cripple (boarders), round otherwise;
## flee when beaten or hopelessly outgunned. Full sail in the fight; no
## grape (a broadside loaded with it cannot fire beyond its short range).
##
## The flight rule (2026-10-21, docs/AI.md "Sea battle AI: the flight
## rule"): every FL_EVERY ticks the battle AI judges its fleet (_fleet_judge):
## its fighting strength (guns x hull % x guns served) against the enemy's
## and the exchange over the last 2 minutes (damage samples fl_hist). Under
## its skill's SEA_FLEE_RATIO (ai_skill: Easy 70, Average 50, Skilled 40 %)
## and losing the exchange, or half its ships crippled and under the ratio +
## FL_CRIP_ADD, the fleet flees (fl_on 1): every ship that can sail away
## (s_ffl) runs for the edge on the heading she leaves the field soonest by
## her polar before the enemy can get there (_escape_goal; a Skilled fleet
## with the gauge keeps it), firing at pursuers as she bears; a dismasted ship
## fights on. A ship off the edge has escaped (S_FLED). No enemy within
## FL_RALLY_M for a minute: it rallies (fl_on 2) and holds, hove to, until one
## comes within FL_HOLD_M (at most HOLD_TICKS); FL_CAP_TICKS of flight with no
## enemy within FL_CLEAR_M: withdrawn (every runner escaped). At the time
## limit a fleet in flight does not hold the field.
##
## Galleys (R1, Rome's navy; docs/design/sea.md "Rome's navy"): rows with
## oars and no guns (ST.is_galley). The sail order (O_SAILS) is the stroke:
## 0 rest, 1 cruise (CRUISE_PCT % of vmax), 2 ramming speed (vmax) while
## the dash meter (s_dash, 1/10 s; the row's "dash" seconds full) lasts: it
## drains 10 a second at ramming speed and refills DASH_FILL a second off
## it; empty, she drops to cruise. A row with a "ram" whose bow meets an
## enemy hull inside her bow cone (RAM_CONE) closing at RAM_MIN or more
## rams (_rams, in _contacts): ram x closing / RAM_DIV hull, x2 with the
## strike within RAM_BEAM of her beam, half to both bow to bow; the rammer
## backs water (speed 0) RAM_BACK ticks and rams again after RAM_COOL. A
## "corvus" ship within grapple reach of an enemy at a relative speed up to
## CORVUS_REL drops the bridge and boards at once (not within CORVUS_COOL
## of her boarders being thrown back); over the corvus the deck bonus
## (DECK_BONUS_PCT) is her boarders', not the defenders' (k_cv). Her "marines" go into the
## troops (kit ST.DECK_MARINES unless given) and throw before contact: every
## `reload` seconds at the nearest enemy within MSL_M, crew only (the deck
## volley's DECK_SHOT_PM). Battle AI: a ram ship sets up SETUP_M off the
## target's beam and runs in at a right angle, dashing the last RUN_M m (for
## her stern quarter when faster: the diekplous), not with a tired crew (the
## meter under a third); a corvus ship closes and boards; a ram-less galley
## (the lembos) keeps clear of ships over twice her hull unless they are
## crippled or her side outnumbers theirs two to one, and engages at
## MSL_STAND; galleys flee straight away from the nearest enemy. The galley
## arrays (GAL_ARRAYS) are hashed only in a battle with a galley (gal_on), so
## every battle without one hashes as before.

const FM := preload("res://sim/fixed_math.gd")
const ST := preload("res://sim/sea_types.gd")
const UT := preload("res://sim/unit_types.gd")

const U := 1024                  # units per metre
const TIME_LIMIT := 9000         # ticks (15 minutes)
const END_TICKS := 60            # after the decision, then `ended`
const FIELD_W := 2400            # metres
const FIELD_H := 1600
const CELL_M := 20               # land grid cell

# Ship states (u_state; 0 is what the lockstep layer calls U_READY).
const S_SAIL := 0
const S_STRUCK := 1
const S_SUNK := 2
const S_TAKEN := 3
const S_FLED := 4
const STATE_NAMES := ["fighting", "struck", "sunk", "taken", "escaped"]

# Modes.
const M_FREE := 0
const M_GOTO := 1
const M_ENGAGE := 2
const M_BOARD := 3
const M_FLEE := 4
const M_HEAD := 5
const M_FIRE := 6       # a fire ship sailing at her mark (s_tgt)

# Orders (types inside the lockstep's sim-order range, avoiding its special
# 8 withdraw-all, 13 ready and 20 works; 7 is what withdraw-all queues).
const O_SAIL := 1       # unit, x, y (metres): sail there (the course is planned by the wind)
const O_TARGET := 2     # unit, target: engage that ship (broadside on, focus fire)
const O_HOLD := 3       # unit: drop the order, hold the course
const O_SAILS := 4      # unit, on: 0 stop (heave to), 1 battle sail, 2 full sail
const O_FIRE := 5       # unit, on: fire at will (1) or only at the ordered target (0)
const O_SHOT := 6       # unit, on: ST.SHOT_* loaded at the next reload
const O_FLEE := 7       # unit: run for the map edge away from the enemy
const O_BOARD := 9      # unit, target: lay her alongside and board
const O_HEAD := 10      # unit, facing (angle 0..1023): hold that heading
const O_DECK := 11      # unit (boarder), target, on (1 boarders won), a, b (crews left): N3b deck result (outside melee, "deck" 1)
const O_LIGHT := 12     # unit (a fire ship): light her now (her crew take to the boat)
const O_DOUSE := 14     # unit, on: 1 all hands to the buckets (only while she burns), 0 back to the guns
const O_LAST := 14

const ARC := 120                 # half-width of a broadside's arc (angle units, ~42 deg)
const SAIL_PCT := [0, 75, 100]
const BOARD_MAX_TICKS := 600
const DECK_BONUS_PCT := 125      # defenders on their own deck
const FIRE_PM := 5               # per mille per round-shot hit: a fire starts
const FIRE_START := 60           # a fire's intensity when it starts (FIRE_MAX at most)
const FIRE_GROW := 25            # intensity a second (+ a roll of up to FIRE_GROW_ROLL)
const FIRE_GROW_ROLL := 20
const FIRE_FIGHT := 45           # intensity a second the crew beats down (at full crew)
const FIRE_MAX := 1000
const DOUSE_FIGHT_PCT := 200     # Douse: the crew fight the fire at this % (guns silent: neither fire nor reload)
const DOUSE_DECK_PCT := 50       # ... and her men strike and fire in a deck melee at this % (the rest at the buckets)
const DOUSE_BOARD_M := 200       # the battle AI does not douse with an enemy this close coming to board her
const FIRE_HULL := 120000        # hull lost a second: hull0 x intensity / FIRE_HULL (at least 1)
const MAG_LV := 500              # past this intensity the magazine may go ...
const MAG_DIV := 4               # ... at (intensity - MAG_LV) / MAG_DIV per mille a second
const BLAST_FIRE := 250          # intensity of the fires a blast starts in its neighbours
const BLAST_M := 70
# Fire ships (N3c).
const FS_LIGHT_M := 200          # lit this close to her mark (when she can lie the course to it)
const FS_ABANDON_M := 80         # her crew lash the helm and take to the boat this close ...
const FS_ABANDON_TICKS := 300    # ... or this long after she is lit
const FS_STICK_TICKS := 250      # her grapnels hold her alongside what she touched
const FS_FIRE := 400             # the intensity she gives what she touches (+ FS_FEED a second alongside)
const FS_FEED := 80
const FS_SPREAD_M := 25          # sparks: ships this close to a burning fire ship catch (FS_SPREAD_PCT % a second)
const FS_SPREAD_PCT := 25
const FS_BURN_PCT := 2           # % of her hull a burning fire ship loses a second
const FS_SERVES := 300           # angle units off the wind the bearing to her mark must be (the wind serves)
# Deck melee (N3b).
const DECK_CELL_M := 2           # metres a deck cell
const DECK_FIG := 24             # figures a side at most (one is the captain)
const FIG := DECK_FIG * 2        # figure slots per boarding (per boarder ship)
const DECK_EVERY := 2            # ticks between deck steps
const DECK_MOVE := 3             # a figure steps a cell every this many deck steps
const DECK_KILL_PM := 14         # per mille of a figure's men killing a man a deck step (even atk / def: half)
const DECK_SHOT_PM := 5          # per mille of a volley's men hitting, per shot % (crowded rails, smoke)
const DECK_MAX_TICKS := 450      # both crews spent: the ships part
const DECK_BOARD_PCT := 75       # % of the boarder's crew that go across (the rest work the ship)
const DECK_BREAK_DEF := 30       # defenders under this % of the boarders: the deck is lost, she strikes
const DECK_BREAK_ATT := 45       # boarders under this % of the defenders: thrown back
const DECK_MOR_LOSS := 100        # morale a side loses for losing all its men (by the share lost)
const DECK_CAPT_LOSS := 30       # morale a side loses when its captain falls
const DECK_RUSH := 10            # boarders' morale on top of their ship's (the rush across)
const TK_MAX := 3                # troop kits a ship (by unit type)
const TKP := 7                   # per kit: pct of the troops, atk, def, shot %, range, volleys, reload
const WIND_EVERY := 300
const WIND_SPAN := 100           # angle units either side of the start wind (~35 deg)
const EDGE_M := 90               # ships keep this far from the edge unless fleeing
const RANGE_PREF := [165, 140, 70]   # metres: the range a ship engages at, by shot
const TACK_WAY := 300            # ticks: how slowly a ship turning through the wind loses her way (12 when she is not turning)
const CLOSE_MARGIN := 24         # angle units off the no-go zone a ship sails close-hauled (~8 deg)
const GAUGE_M := 220             # the weather gauge: a point this far to windward of the enemy
const BOARD_M := 400             # a board (one leg of a beat): the battle AI beats at most two to reach an enemy
const SEA_ROOM_M := 400          # a new board leads the way with this much clear water ahead (if either does)
const LAYLINE_M := 200           # she tacks this far short of land or the field's edge ahead
const LEE_SHORE_M := 250         # land this close to leeward: she sails along it, never in toward it
const START_CLEAR_M := 300       # no shoal (nor land, where the field allows) this close to a start line
const BOARD_PCT := 160          # the battle AI boards when its boarding strength is this % of hers (or more)
const HOLD_TICKS := 1800         # the battle AI's leeward fleet holds its line at most this long (3 min) before it beats up
const LEE_ROOM_M := 500          # the leeward fleet starts with this much clear water to leeward and on both beams
# The flight rule (sea balance, 2026-10-21; docs/AI.md "Sea battle AI: the flight rule"): the battle AI judges its
# fleet every FL_EVERY ticks and breaks off when it is losing.
const EASY := 0                  # ai_skill (the scenario's "ai_skill" per side; sim/ai_profile.gd's levels)
const AVERAGE := 1
const SKILLED := 2
const FL_EVERY := 100            # ticks between the fleet's judgements (and the damage samples)
const FL_HIST := 12              # samples of the exchange kept: the trend over the last 2 minutes
const SEA_FLEE_RATIO := [70, 50, 40]  # by skill: it flees below this % of the enemy's fighting strength (losing the exchange)
const FL_CRIP_ADD := 20          # ... or below that + this % with half its ships crippled or taken
const FL_TREND_MIN := 150        # damage taken in the 2 minutes (1000 = a ship's hull or crew) for a trend at all
const FL_RIG_PCT := 15           # rigging under this %: she cannot sail away (she fights on or strikes)
const FL_RALLY_M := 600          # no enemy this close ...
const FL_RALLY_TICKS := 600      # ... for this long (1 minute): the fleet stops fleeing and holds
const FL_CAP_TICKS := 2400       # fleeing this long (4 minutes) with no enemy within FL_CLEAR_M: withdrawn
const FL_CLEAR_M := 300
const FL_HOLD_M := 800           # rallied, the fleet holds until an enemy comes this close (at most HOLD_TICKS)
# Galleys (R1, Rome's navy). Speeds in the sim's units (1/1024 m a tick: 100 is about 1 m/s).
const CRUISE_PCT := 65           # the cruising stroke (O_SAILS 1), % of vmax; 2 is vmax while the dash meter lasts
const DASH_FILL := 3             # dash meter (1/10 s) refilled a second off ramming speed (it drains 10 a second at it)
const RAM_MIN := 300             # closing speed for a ram (about 2.9 m/s)
const RAM_CONE := 85             # the rammer's bow cone either side of her heading (30 degrees)
const RAM_DIV := 600             # hull damage = ram x closing speed / RAM_DIV
const RAM_BEAM := 128            # the strike within this of a right angle to her keel (45 degrees): x2
const RAM_BACK := 40             # ticks the rammer backs water (speed 0) after the blow
const RAM_COOL := 60             # ticks before she can ram again (a push is not a ram)
const CORVUS_REL := 500          # the corvus drops at a relative speed up to this
const CORVUS_COOL := 300         # ticks after her boarders are thrown back before it drops again
const MSL_M := 60                # the marines' javelins and arrows reach this far before contact
const MSL_STAND := 40            # a galley without a ram engages at this range
const RUN_M := 60                # a ram run dashes the last RUN_M metres (bow to her side)
const SETUP_M := 120             # a ram ship sets up her run this far off the target's beam

# ---- lockstep interface (duck-typed like BattleSim) ----
var n_units := 0
var u_side := PackedInt32Array()
var u_state := PackedInt32Array()
var u_hand := PackedInt32Array()     # always -1 (no war dogs at sea)
var u_pack := PackedInt32Array()
var u_char := PackedInt32Array()
var ch_on := 0
var dep_on := 0
var dep_need := 0
var ai_sides := PackedInt32Array([0, 1])
var ai_skill := PackedInt32Array([AVERAGE, AVERAGE])
var fl_on := PackedInt32Array([0, 0])      # the flight rule, per side: 1 the fleet is fleeing
var fl_t := PackedInt32Array([-1, -1])     # ... since this tick
var fl_far := PackedInt32Array([-1, -1])   # ... with no enemy within FL_RALLY_M since this tick (-1: one is)
var fl_hist := PackedInt32Array()          # FL_HIST damage samples per side (side x FL_HIST + slot)
var gal_on := 0                            # (R1) 1: a galley in the battle (the galley arrays are hashed)
var stat_fl := PackedInt32Array([0, 0, 0, 0])  # view / probe: fleet flights, rallies, withdrawals, wins on the clock refused
var pending_orders: Array = []
var _order_seq := 0

# ---- hashed state ----
var tick := 0
var rng_state := 1
var winner := -1
var decided_tick := -1
var ended := 0
var time_limit := TIME_LIMIT
var field_w := FIELD_W
var field_h := FIELD_H
var seed_value := 1
var w_base := 0
var w_from := 0
var w_goal := 0
var w_str := 80
var deck_on := 0
var ter_hash := 0
var s_type := PackedInt32Array()
var s_x := PackedInt32Array()
var s_y := PackedInt32Array()
var s_h16 := PackedInt32Array()
var s_want := PackedInt32Array()
var s_tdir := PackedInt32Array()
var s_spd := PackedInt32Array()
var s_sail := PackedInt32Array()
var s_hull := PackedInt32Array()
var s_hull0 := PackedInt32Array()
var s_crew := PackedInt32Array()
var s_crew0 := PackedInt32Array()
var s_rig := PackedInt32Array()
var s_rig0 := PackedInt32Array()
var s_troops := PackedInt32Array()
var s_q := PackedInt32Array()
var s_bq := PackedInt32Array()
var s_mor := PackedInt32Array()
var s_mode := PackedInt32Array()
var s_tx := PackedInt32Array()
var s_ty := PackedInt32Array()
var s_tgt := PackedInt32Array()
var s_fire := PackedInt32Array()
var s_shot := PackedInt32Array()
var s_ld := PackedInt32Array()       # 2 per ship: the shot loaded (port, starboard)
var s_rl := PackedInt32Array()       # 2 per ship: reload work left (ticks x 1000)
var s_tack := PackedInt32Array()
var s_grap := PackedInt32Array()
var s_boarder := PackedInt32Array()
var s_bd_t := PackedInt32Array()
var s_bd_wait := PackedInt32Array()
var s_by := PackedInt32Array()
var s_burn := PackedInt32Array()
var s_ground := PackedInt32Array()
var s_hit_t := PackedInt32Array()
var s_end_t := PackedInt32Array()
var s_kills := PackedInt32Array()
var s_blown := PackedInt32Array()
var s_flee_x := PackedInt32Array()
var s_flee_y := PackedInt32Array()
var s_ffl := PackedInt32Array()      # 1: she flees with her fleet (the flight rule), 0 not
var s_lit := PackedInt32Array()      # fire ship: tick she was lit (-1 not)
var s_aband := PackedInt32Array()    # fire ship: 1 once her crew took to the boat
var s_fsg := PackedInt32Array()      # fire ship: the ship she is grappled to (-1)
var s_fs_t := PackedInt32Array()     # ... since this tick
var s_douse := PackedInt32Array()    # 1: all hands fighting her fire (O_DOUSE; off by itself when it is out)
var s_ck_atk := PackedInt32Array()   # crew kit (deck melee): atk, def, shot %, range, volleys, reload
var s_ck_def := PackedInt32Array()
var s_ck_shot := PackedInt32Array()
var s_ck_rng := PackedInt32Array()
var s_ck_sh := PackedInt32Array()
var s_ck_rl := PackedInt32Array()
var s_cq := PackedInt32Array()       # captain's fighting % (a notorious captain more)
var s_tkp := PackedInt32Array()      # troop kits: TK_MAX x TKP per ship
# Deck melee slots, one per boarder ship s (k_*: n_units; k2_*: 2 per ship,
# side 0 the boarders, 1 the defenders; f_*: FIG figures per ship).
var k_on := PackedInt32Array()
var k_t0 := PackedInt32Array()
var k_w := PackedInt32Array()
var k_hb := PackedInt32Array()       # rows of the boarder's deck (rows 0..hb-1, the rail at hb)
var k_ht := PackedInt32Array()       # rows of the defender's deck (rows hb..hb+ht-1)
var k_ax0 := PackedInt32Array()      # first column and length of the boarder's deck
var k_la := PackedInt32Array()
var k_bx0 := PackedInt32Array()      # ... and the defender's
var k_lb := PackedInt32Array()
var k_step := PackedInt32Array()
var k2_mor := PackedInt32Array()
var k2_men0 := PackedInt32Array()
var k2_cap := PackedInt32Array()
var f_n := PackedInt32Array()        # men in the figure (0: none)
var f_side := PackedInt32Array()
var f_x := PackedInt32Array()
var f_y := PackedInt32Array()
var f_kind := PackedInt32Array()     # 0 crew, 1 soldiers, 2 the captain
var f_atk := PackedInt32Array()
var f_def := PackedInt32Array()
var f_shot := PackedInt32Array()
var f_rng := PackedInt32Array()
var f_sh := PackedInt32Array()       # volleys left
var f_rl := PackedInt32Array()
var f_ld := PackedInt32Array()       # ticks to reload (0: ready)
var f_hit := PackedInt32Array()      # view: tick it last struck or fired (not hashed)
# Galleys (R1; hashed when gal_on): the dash meter (1/10 s), the tick of her
# last ram, ticks to her next missile volley, 1: this melee was boarded by the corvus.
var s_dash := PackedInt32Array()
var s_ram_t := PackedInt32Array()
var s_msl := PackedInt32Array()
var s_cv_t := PackedInt32Array()     # tick her boarders were last thrown back (the corvus is hauled up)
var k_cv := PackedInt32Array()

# ---- rebuilt by setup() (not in snapshots) ----
var g_w := 0
var g_h := 0
var g := PackedByteArray()           # 0 sea, 1 shoal, 2 land

# ---- view events and statistics (snapshotted, not hashed) ----
const EV_CAP := 256
const EV_BROADSIDE := 0   # a: ship, b: side (0 port / 1 starboard), c: target, d: hits, e: shot
const EV_BLAST := 1       # a: ship
const EV_GRAPPLE := 2     # a: boarder, c: target
const EV_TAKEN := 3       # a: captor (-1 struck at the end), c: prize
const EV_STRIKE := 4      # a: ship
const EV_SINK := 5        # a: ship
const EV_REPELLED := 6    # a: boarder, c: target
const EV_FIRE := 7        # a: ship
const EV_GROUND := 8      # a: ship
const EV_FLED := 9        # a: ship
const EV_DECK_SHOT := 10  # a: boarder (the melee), b: figure, c: target figure
const EV_CAPTAIN := 11    # a: boarder (the melee), b: side whose captain fell
const EV_LIT := 12        # a: fire ship
const EV_ABANDON := 13    # a: fire ship (her crew take to the boat)
const EV_FS_CONTACT := 14 # a: fire ship, c: the ship she grapples and sets alight
const EV_DECK_END := 15   # a: boarder, c: target, d: 1 taken / 2 thrown back / 3 both spent
const EV_RAM := 16        # a: rammer, b: 0 a blow / 1 on the beam / 2 bow to bow, c: struck, d: hull lost, e: closing speed
const EV_MISSILE := 17    # a: galley, c: target, d: men killed
# (EV_GRAPPLE's b is 1 when the corvus dropped.)
var ev_n := 0
var ev_t := PackedInt32Array()
var ev_k := PackedInt32Array()
var ev_a := PackedInt32Array()
var ev_b := PackedInt32Array()
var ev_c := PackedInt32Array()
var ev_d := PackedInt32Array()
var ev_e := PackedInt32Array()
var stats := {"broadsides": 0, "hits": 0, "rakes": 0, "boardings": 0, "captured": 0, "repelled": 0, "struck": 0,
	"sunk": 0, "fires": 0, "blown": 0, "tacks": 0, "wears": 0, "grounded": 0, "fled": 0, "chain": 0, "grape": 0,
	"deck_fights": 0, "deck_taken": 0, "deck_repelled": 0, "deck_spent": 0, "deck_shots": 0, "deck_ticks": 0,
	"captains_fallen": 0, "fireships": 0, "fire_contacts": 0, "fs_spread": 0, "fire_sunk": 0, "fire_out": 0,
	"douse": 0, "douse_out": 0}


# ------------------------------------------------------------------ setup ---

## Bearing in degrees (0 north, 90 east, clockwise) to a sim angle.
static func bearing_to_angle(deg: int) -> int:
	return (deg * FM.ANGLE_FULL / 360 - FM.ANGLE_QUARTER) & FM.ANGLE_MASK


## Sim angle to a bearing in degrees.
static func angle_to_bearing(a: int) -> int:
	return (((a + FM.ANGLE_QUARTER) & FM.ANGLE_MASK) * 360 / FM.ANGLE_FULL) % 360


## Scenario: {"sea": 1, "width_m", "height_m", "wind_deg" (bearing the wind
## blows from), "wind_str" 0-100, "ai_sides" [0|1, 0|1], "time_limit" (s),
## "deck" 0|1 (1: boardings wait for an outside melee, O_DECK), "land": {"kind": 0 open / 1 island / 2 coast, "dirs" (coast:
## bit i for land toward angle i * 128, 0 east, 2 south, 4 west, 6 north),
## "mseed", optional island "ix", "iy", "ir" metres}, "layout": "ns" | "we" |
## "gauge0" | "gauge1" (where the fleets start when ships have no x / y),
## "units": [{"side", "t" (ship key), optional "x", "y" (m), "head"
## (bearing), "hull", "crew", "rig" (% of the row), "q" (gunnery %), "bq"
## (boarding %), "troops" (men), "mor", "ck" (crew kit: a key of
## ST.DECK_CREWS, the faction), "tk" (the troops by unit type: [[unit key,
## % of the troops], ...], at most TK_MAX), "cq" (the captain's fighting
## %)}]}.
func setup(scn: Dictionary, p_seed: int) -> void:
	seed_value = p_seed
	rng_state = (p_seed * 2654435761 + 12345) & 0x7FFFFFFF
	if rng_state == 0:
		rng_state = 1
	field_w = clampi(int(scn.get("width_m", FIELD_W)), 600, 6000)
	field_h = clampi(int(scn.get("height_m", FIELD_H)), 600, 6000)
	time_limit = int(scn.get("time_limit", TIME_LIMIT / 10)) * 10
	w_base = bearing_to_angle(int(scn.get("wind_deg", 90)))
	w_from = w_base
	w_goal = w_base
	w_str = clampi(int(scn.get("wind_str", 80)), 10, 100)
	deck_on = 1 if int(scn.get("deck", 0)) != 0 else 0
	var ai: Array = scn.get("ai_sides", [0, 1])
	ai_sides = PackedInt32Array([int(ai[0]), int(ai[1])])
	var sk: Array = scn.get("ai_skill", [AVERAGE, AVERAGE])
	ai_skill = PackedInt32Array([clampi(int(sk[0]), EASY, SKILLED), clampi(int(sk[1]), EASY, SKILLED)])
	fl_on = PackedInt32Array([0, 0])
	fl_t = PackedInt32Array([-1, -1])
	fl_far = PackedInt32Array([-1, -1])
	fl_hist.resize(2 * FL_HIST)
	fl_hist.fill(0)
	gal_on = 0
	_make_land(scn.get("land", {}))
	var units: Array = scn.get("units", [])
	n_units = units.size()
	for nm in SHIP_ARRAYS:
		var arr := PackedInt32Array()
		arr.resize(n_units)
		arr.fill(0)
		set(nm, arr)
	s_ld.resize(n_units * 2)
	s_ld.fill(0)
	s_rl.resize(n_units * 2)
	s_rl.fill(0)
	for nm in DECK2_ARRAYS:
		var a2 := PackedInt32Array()
		a2.resize(n_units * 2)
		a2.fill(0)
		set(nm, a2)
	for nm in FIG_ARRAYS:
		var a3 := PackedInt32Array()
		a3.resize(n_units * FIG)
		a3.fill(0)
		set(nm, a3)
	f_hit.resize(n_units * FIG)
	f_hit.fill(-100)
	for nm in GAL_ARRAYS:
		var a4 := PackedInt32Array()
		a4.resize(n_units)
		a4.fill(0)
		set(nm, a4)
	s_tkp.resize(n_units * TK_MAX * TKP)
	s_tkp.fill(0)
	u_hand.resize(n_units)
	u_hand.fill(-1)
	u_pack.resize(n_units)
	u_pack.fill(-1)
	u_char.resize(n_units)
	u_char.fill(0)
	for s in n_units:
		var d: Dictionary = units[s]
		var ty := maxi(ST.index_of(str(d.get("t", "frigate"))), 0)
		s_type[s] = ty
		u_side[s] = clampi(int(d.get("side", 0)), 0, 1)
		u_state[s] = S_SAIL
		s_hull0[s] = ST.stat(ty, "hull")
		s_hull[s] = maxi(s_hull0[s] * clampi(int(d.get("hull", 100)), 1, 100) / 100, 1)
		s_crew0[s] = ST.stat(ty, "crew")
		s_crew[s] = maxi(s_crew0[s] * clampi(int(d.get("crew", 100)), 1, 100) / 100, 1)
		s_rig0[s] = maxi(ST.stat(ty, "rig"), 1)
		s_rig[s] = s_rig0[s] * clampi(int(d.get("rig", 100)), 0, 100) / 100
		s_troops[s] = maxi(int(d.get("troops", 0)), 0) + ST.stat(ty, "marines")
		s_q[s] = clampi(int(d.get("q", 100)), 40, 160)
		s_bq[s] = clampi(int(d.get("bq", ST.stat(ty, "board"))), 40, 200)
		s_mor[s] = clampi(int(d.get("mor", 100)), 20, 150)
		s_sail[s] = 2
		s_fire[s] = 1
		s_tgt[s] = -1
		s_grap[s] = -1
		s_by[s] = -1
		s_end_t[s] = -1
		s_want[s] = -1
		s_hit_t[s] = -1000
		s_flee_x[s] = -1
		s_flee_y[s] = -1
		s_lit[s] = -1
		s_fsg[s] = -1
		s_ram_t[s] = -1000
		s_cv_t[s] = -1000
		s_dash[s] = ST.stat(ty, "dash") * 10
		if ST.stat(ty, "dash") > 0:
			s_sail[s] = 1  # (a galley cruises)
		if ST.is_galley(ty) or ST.stat(ty, "ram") > 0 or ST.stat(ty, "corvus") > 0 or ST.stat(ty, "dash") > 0:
			gal_on = 1
		_setup_kits(s, d)
		if d.has("x") and d.has("y"):
			s_x[s] = int(d["x"]) * U
			s_y[s] = int(d["y"]) * U
		else:
			s_x[s] = -1
		var hd := bearing_to_angle(int(d.get("head", 0)))
		s_h16[s] = hd * 16
		s_spd[s] = _vmax(s) * 55 / 100  # under way when it begins
	_layout(str(scn.get("layout", "ns")), units)
	for s in n_units:
		s_want[s] = s_h16[s] >> 4
	ev_t.resize(EV_CAP)
	ev_k.resize(EV_CAP)
	ev_a.resize(EV_CAP)
	ev_b.resize(EV_CAP)
	ev_c.resize(EV_CAP)
	ev_d.resize(EV_CAP)
	ev_e.resize(EV_CAP)


const SHIP_ARRAYS: Array[String] = ["u_side", "u_state", "s_type", "s_x", "s_y", "s_h16", "s_want", "s_tdir", "s_spd",
	"s_sail", "s_hull", "s_hull0", "s_crew", "s_crew0", "s_rig", "s_rig0", "s_troops", "s_q", "s_bq", "s_mor", "s_mode",
	"s_tx", "s_ty", "s_tgt", "s_fire", "s_shot", "s_tack", "s_grap", "s_boarder", "s_bd_t", "s_bd_wait", "s_by", "s_burn",
	"s_ground", "s_hit_t", "s_end_t", "s_kills", "s_blown", "s_flee_x", "s_flee_y", "s_ffl",
	"s_lit", "s_aband", "s_fsg", "s_fs_t", "s_douse", "s_ck_atk", "s_ck_def", "s_ck_shot", "s_ck_rng", "s_ck_sh", "s_ck_rl", "s_cq",
	"k_on", "k_t0", "k_w", "k_hb", "k_ht", "k_ax0", "k_la", "k_bx0", "k_lb", "k_step"]
const DECK2_ARRAYS: Array[String] = ["k2_mor", "k2_men0", "k2_cap"]
const GAL_ARRAYS: Array[String] = ["s_dash", "s_ram_t", "s_msl", "s_cv_t", "k_cv"]
const FIG_ARRAYS: Array[String] = ["f_n", "f_side", "f_x", "f_y", "f_kind", "f_atk", "f_def", "f_shot", "f_rng", "f_sh",
	"f_rl", "f_ld"]


## The crew kit and the troops' kits of ship s from its scenario entry d.
func _setup_kits(s: int, d: Dictionary) -> void:
	var ck := ST.deck_crew(str(d.get("ck", "navy")))
	s_ck_atk[s] = int(ck["atk"])
	s_ck_def[s] = int(ck["def"])
	s_ck_shot[s] = int(ck["shot"])
	s_ck_rng[s] = int(ck["rng"])
	s_ck_sh[s] = int(ck["shots"])
	s_ck_rl[s] = int(ck["rl"])
	s_cq[s] = clampi(int(d.get("cq", 100)), 50, 250)
	var tk: Array = d.get("tk", []) if d.get("tk") is Array else []
	var k := 0
	for e in tk:
		if k >= TK_MAX or not (e is Array) or (e as Array).size() < 2:
			continue
		var ty := UT.index_of(str(e[0]))
		var pct := clampi(int(e[1]), 0, 100)
		if pct <= 0:
			continue
		var b := (s * TK_MAX + k) * TKP
		s_tkp[b] = pct
		if ty < 0:
			s_tkp[b + 1] = int(ST.DECK_TROOPS["atk"])
			s_tkp[b + 2] = int(ST.DECK_TROOPS["def"])
			s_tkp[b + 3] = int(ST.DECK_TROOPS["shot"])
			s_tkp[b + 4] = int(ST.DECK_TROOPS["rng"])
			s_tkp[b + 5] = int(ST.DECK_TROOPS["shots"])
			s_tkp[b + 6] = int(ST.DECK_TROOPS["rl"])
		else:
			s_tkp[b + 1] = maxi(UT.stat(ty, "attack"), 5)
			s_tkp[b + 2] = maxi(UT.stat(ty, "defence") + UT.stat(ty, "armour") + UT.stat(ty, "shield") / 2, 5)
			var sh: Array = ST.DECK_UNIT_SHOT.get(UT.key_of(ty), ST.DECK_LINE_SHOT.get(UT.line_of(ty), [0, 0, 0, 0]))
			s_tkp[b + 3] = int(sh[0])
			s_tkp[b + 4] = int(sh[1])
			s_tkp[b + 5] = int(sh[2])
			s_tkp[b + 6] = int(sh[3])
		k += 1
	if k == 0 and ST.stat(s_type[s], "marines") > 0:
		# (R1) A galley's marines, no kit given: ST.DECK_MARINES.
		var b2 := s * TK_MAX * TKP
		var msh: Array = ST.DECK_LINE_SHOT.get(str(ST.DECK_MARINES["line"]), [0, 0, 0, 0])
		s_tkp[b2] = 100
		s_tkp[b2 + 1] = int(ST.DECK_MARINES["atk"])
		s_tkp[b2 + 2] = int(ST.DECK_MARINES["def"])
		s_tkp[b2 + 3] = int(msh[0])
		s_tkp[b2 + 4] = int(msh[1])
		s_tkp[b2 + 5] = int(msh[2])
		s_tkp[b2 + 6] = int(msh[3])


func is_tower(_u: int) -> bool:
	return false


## Ships without a position: each side in a line abreast at its end of the
## field (side 0 south / west / downwind, side 1 north / east / upwind for
## "gauge1"), facing the enemy or the nearest point of sail, clear of land.
## Sea room at the start: each fleet's line is shifted (toward the middle
## and / or along the line: the first of _start_shifts() that serves, the
## sideways sign by the seed) so that no shoal or land lies within
## START_CLEAR_M of it and the leeward fleet (the one 200 m or more farther
## downwind; placed first) has LEE_ROOM_M of clear water to leeward and on
## both beams, the fleets staying START_APART_M apart (else the shift with
## the least land in the way). Shoals still within START_CLEAR_M of a ship
## are then cleared to open water (setup rebuilds the grid the same way).
func _layout(kind: String, units: Array) -> void:
	var ax := 0
	var ay := FM.TRIG_ONE  # side 0 is toward +y (south)
	var half := (field_h / 2 - 260) * U
	if kind == "we":
		ax = -FM.TRIG_ONE
		ay = 0
		half = (field_w / 2 - 300) * U
	elif kind == "gauge0" or kind == "gauge1":
		# Along the wind: side g at the upwind end.
		var up := w_from
		if kind == "gauge1":
			up = (w_from + FM.ANGLE_HALF) & FM.ANGLE_MASK
		ax = FM.cos_a(up)
		ay = FM.sin_a(up)
		half = mini(field_w, field_h) / 2 * U - 280 * U
	var lists: Array = [[], []]
	for side in 2:
		for s in n_units:
			if u_side[s] == side and s_x[s] < 0:
				(lists[side] as Array).append(s)
	# The leeward fleet, by the two lines' places along the wind.
	var proj: Array[int] = [0, 0]
	for side in 2:
		var sgn := 1 if side == 0 else -1
		var bx := (sgn * ((ax * (half >> 6)) >> 6)) / U
		var by := (sgn * ((ay * (half >> 6)) >> 6)) / U
		proj[side] = (bx * FM.cos_a(w_from) + by * FM.sin_a(w_from)) >> 12
	var lee := -1
	if absi(proj[0] - proj[1]) >= 200:
		lee = 0 if proj[0] < proj[1] else 1
	var flip := 1 if seed_value % 2 == 0 else -1
	var order: Array[int] = [0, 1]
	if lee == 1:
		order = [1, 0]
	var done: Array[int] = []
	for side in order:
		var list: Array = lists[side]
		if list.is_empty():
			continue
		var shifts := _start_shifts()
		var best_k := 0
		var best_bad := 1 << 30
		for k in shifts.size():
			var sh: Array = shifts[k]
			_place_line(side, list, units, ax, ay, half, int(sh[0]), int(sh[1]) * flip)
			if not _apart(list, done):
				continue
			var bad := _start_bad(list, side == lee)
			if bad < best_bad:
				best_bad = bad
				best_k = k
			if bad == 0:
				break
		var bs: Array = shifts[best_k]
		_place_line(side, list, units, ax, ay, half, int(bs[0]), int(bs[1]) * flip)
		for s in list:
			done.append(s)
	# No shoal within START_CLEAR_M of a start line.
	var cleared := false
	var r := START_CLEAR_M / CELL_M
	for s in done:
		var gx0 := s_x[s] / (CELL_M * U)
		var gy0 := s_y[s] / (CELL_M * U)
		for gy in range(maxi(gy0 - r, 0), mini(gy0 + r + 1, g_h)):
			for gx in range(maxi(gx0 - r, 0), mini(gx0 + r + 1, g_w)):
				if (gx - gx0) * (gx - gx0) + (gy - gy0) * (gy - gy0) <= r * r and g[gy * g_w + gx] == 1:
					g[gy * g_w + gx] = 0
					cleared = true
	if cleared:
		_hash_land()


const START_APART_M := 600


## The shifts tried for a start line, [toward the middle, along the line]
## in metres, the smallest moves first (up to 800 m in, 300 m along).
static func _start_shifts() -> Array:
	var out: Array = []
	for cost in range(0, 1101, 50):
		for du in range(0, 801, 100):
			for dc: int in [0, 150, -150, 300, -300]:
				if du + absi(dc) == cost:
					out.append([du, dc])
	return out


## Side `side`'s ships in `list` in a line abreast at its end of the layout
## axis (ax, ay) `half` from the middle, moved du m toward the middle and dc
## m along the line, each on the nearest clear water, facing the enemy (or
## the nearest point of sail, or her scenario heading).
func _place_line(side: int, list: Array, units: Array, ax: int, ay: int, half: int, du: int, dc: int) -> void:
	var cx := field_w * U / 2
	var cy := field_h * U / 2
	var sgn := 1 if side == 0 else -1
	var hh := half - du * U
	var bx := cx + sgn * ((ax * (hh >> 6)) >> 6) + ((-ay * (dc * U >> 6)) >> 6)
	var by := cy + sgn * ((ay * (hh >> 6)) >> 6) + ((ax * (dc * U >> 6)) >> 6)
	# Across the axis: (-ay, ax).
	for i in list.size():
		var s: int = list[i]
		var off := (i * 2 - (list.size() - 1)) * 55 * U
		var px := bx + ((-ay * (off >> 6)) >> 6)
		var py := by + ((ax * (off >> 6)) >> 6)
		# Stagger: every other ship a little back.
		if i % 2 == 1:
			px += sgn * ((ax * (40 * U >> 6)) >> 6)
			py += sgn * ((ay * (40 * U >> 6)) >> 6)
		var p := _clear_spot(px, py)
		s_x[s] = p[0]
		s_y[s] = p[1]
		var face := FM.atan2_a(-sgn * ay, -sgn * ax)
		if (units[s] as Dictionary).has("head"):
			face = bearing_to_angle(int((units[s] as Dictionary)["head"]))
		s_h16[s] = _sailable(s, face) * 16


## True if every ship in `list` is START_APART_M from every ship in `other`.
func _apart(list: Array, other: Array) -> bool:
	for s: int in list:
		for o: int in other:
			if FM.approx_len(s_x[s] - s_x[o], s_y[s] - s_y[o]) < START_APART_M * U:
				return false
	return true


## How much shoal and land lies in the way of a start line (0: none):
## samples every 40 m within START_CLEAR_M of each ship and, for the
## leeward fleet, along LEE_ROOM_M to leeward and on both beams.
func _start_bad(list: Array, leeward: bool) -> int:
	var bad := 0
	var r := START_CLEAR_M
	for s: int in list:
		var dy := -r
		while dy <= r:
			var dx := -r
			while dx <= r:
				if dx * dx + dy * dy <= r * r and _cell_at(s_x[s] + dx * U, s_y[s] + dy * U) != 0:
					bad += 1
				dx += 40
			dy += 40
		if leeward:
			for a: int in [(w_from + FM.ANGLE_HALF) & FM.ANGLE_MASK, (w_from + FM.ANGLE_QUARTER) & FM.ANGLE_MASK,
					(w_from - FM.ANGLE_QUARTER) & FM.ANGLE_MASK]:
				var m := 40
				while m <= LEE_ROOM_M:
					if _cell_at(s_x[s] + ((FM.cos_a(a) * m) >> 12) * U, s_y[s] + ((FM.sin_a(a) * m) >> 12) * U) != 0:
						bad += 1
					m += 40
	return bad


## The nearest clear water to (x, y) (spiralling toward the centre).
func _clear_spot(x: int, y: int) -> Array:
	var px := x
	var py := y
	var cx := field_w * U / 2
	var cy := field_h * U / 2
	for k in 40:
		if _clear_area(px, py, 50):
			return [px, py]
		px += (cx - px) / 12
		py += (cy - py) / 12
	return [px, py]


func _clear_area(x: int, y: int, r_m: int) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if _cell_at(x + dx * r_m * U, y + dy * r_m * U) != 0:
				return false
	return true


# ------------------------------------------------------------------- land ---

func _make_land(l: Dictionary) -> void:
	g_w = (field_w + CELL_M - 1) / CELL_M
	g_h = (field_h + CELL_M - 1) / CELL_M
	g = PackedByteArray()
	g.resize(g_w * g_h)
	g.fill(0)
	var kind := int(l.get("kind", 0))
	var ms := int(l.get("mseed", 1))
	var ph := PackedInt32Array()
	for k in 6:
		ms = (ms * 1103515245 + 12345) & 0x7FFFFFFF
		ph.append(ms % 1024)
	var cx := field_w / 2
	var cy := field_h / 2
	if kind == 2:
		var dirs := int(l.get("dirs", 0))
		for i in 8:
			if (dirs >> i) & 1 == 0:
				continue
			var a := i * 128
			var dx := FM.cos_a(a)
			var dy := FM.sin_a(a)
			# The edge in that direction (the corner for a diagonal), then the
			# coast that far in, ragged by the noise.
			var edge := (absi(dx) * cx + absi(dy) * cy) >> 12
			var depth := 300 if i % 2 == 0 else 380
			for gy in g_h:
				for gx in g_w:
					var mx := gx * CELL_M + CELL_M / 2
					var my := gy * CELL_M + CELL_M / 2
					var proj := ((mx - cx) * dx + (my - cy) * dy) >> 12
					var along := ((mx - cx) * -dy + (my - cy) * dx) >> 12
					var nz := (FM.sin_a(along * 3 + ph[0]) * 60 + FM.sin_a(along * 7 + ph[1]) * 28 +
						FM.sin_a(along * 17 + ph[2]) * 12) >> 12
					var lim := edge - depth + nz
					var c := gy * g_w + gx
					if proj > lim:
						g[c] = 2
					elif proj > lim - 55 and g[c] == 0:
						g[c] = 1
	if kind == 1 or l.has("ir"):
		var ix := int(l.get("ix", cx + (ph[3] - 512) * field_w / 4096))
		var iy := int(l.get("iy", cy + (ph[4] - 512) * field_h / 3000))
		var ir := int(l.get("ir", 90 + ph[5] % 100))
		for gy in g_h:
			for gx in g_w:
				var mx := gx * CELL_M + CELL_M / 2 - ix
				var my := gy * CELL_M + CELL_M / 2 - iy
				var d := FM.isqrt(mx * mx + my * my)
				var a := FM.atan2_a(my, mx)
				var nz := (FM.sin_a(a * 3 + ph[0]) * ir / 4 + FM.sin_a(a * 5 + ph[2]) * ir / 7) >> 12
				var c := gy * g_w + gx
				if d < ir + nz:
					g[c] = 2
				elif d < ir + nz + 45 and g[c] == 0:
					g[c] = 1
	_hash_land()


func _hash_land() -> void:
	var h := 5381
	for k in g.size():
		h = ((h * 33) ^ g[k]) & 0x7FFFFFFF
	ter_hash = h


func _cell_at(x: int, y: int) -> int:
	if x < 0 or y < 0:
		return 0
	var gx := x / (CELL_M * U)
	var gy := y / (CELL_M * U)
	if gx >= g_w or gy >= g_h:
		return 0
	return g[gy * g_w + gx]


## Land at (x, y) for ship s (a shoal stops deep-draught ships only).
func _blocked(s: int, x: int, y: int) -> bool:
	var v := _cell_at(x, y)
	return v == 2 or (v == 1 and ST.stat(s_type[s], "draft") != 0)


func land_at_m(x_m: int, y_m: int) -> int:
	return _cell_at(x_m * U, y_m * U)


# -------------------------------------------------------------------- rng ---

func _rand() -> int:
	var x := rng_state
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	rng_state = x
	return x


func _roll(n: int) -> int:
	if n <= 1:
		return 0
	return (_rand() & 0x7FFFFFFF) % n


# ----------------------------------------------------------------- orders ---

func queue_order(order: Dictionary) -> void:
	var o := {}
	for k in order:
		o[k] = int(order[k])
	if not o.has("player"):
		o["player"] = 0
	if not o.has("seq"):
		o["seq"] = _order_seq
		_order_seq += 1
	if not o.has("tick"):
		o["tick"] = tick
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
		_order(o)


func _order(o: Dictionary) -> void:
	var s := int(o.get("unit", -1))
	if s < 0 or s >= n_units:
		return
	var typ := int(o.get("type", 0))
	if typ == O_DECK:
		_deck_result(s, int(o.get("target", -1)), int(o.get("on", 0)), int(o.get("a", 0)), int(o.get("b", 0)))
		return
	if u_state[s] != S_SAIL or s_lit[s] >= 0:
		return  # (a lit fire ship goes where her helm is lashed)
	if ST.is_fire(s_type[s]) and (typ == O_TARGET or typ == O_BOARD):
		# A fire ship sent at an enemy: she sails at her and is lit close.
		var tf := int(o.get("target", -1))
		if tf >= 0 and tf < n_units and u_side[tf] != u_side[s] and u_state[tf] == S_SAIL and s_lit[tf] < 0:
			s_mode[s] = M_FIRE
			s_tgt[s] = tf
			s_sail[s] = 2
			s_tack[s] = 0
			s_tdir[s] = 0
		return
	match typ:
		O_LIGHT:
			if ST.is_fire(s_type[s]):
				_light(s)
		O_DOUSE:
			_set_douse(s, int(o.get("on", 1)))
		O_SAIL:
			s_mode[s] = M_GOTO
			s_tx[s] = clampi(int(o.get("x", 0)), 0, field_w) * U
			s_ty[s] = clampi(int(o.get("y", 0)), 0, field_h) * U
			s_tack[s] = 0
			s_tdir[s] = 0
		O_TARGET:
			var t := int(o.get("target", -1))
			if t >= 0 and t < n_units and u_side[t] != u_side[s] and u_state[t] == S_SAIL:
				s_mode[s] = M_ENGAGE
				s_tgt[s] = t
				s_tack[s] = 0
				s_tdir[s] = 0
		O_HOLD:
			s_mode[s] = M_FREE
			s_tgt[s] = -1
			s_tdir[s] = 0
		O_SAILS:
			s_sail[s] = clampi(int(o.get("on", 2)), 0, 2)
		O_FIRE:
			s_fire[s] = 1 if int(o.get("on", 1)) != 0 else 0
		O_SHOT:
			s_shot[s] = clampi(int(o.get("on", 0)), 0, 2)
		O_FLEE:
			s_mode[s] = M_FLEE
			s_flee_x[s] = -1
			s_sail[s] = 2
			s_tdir[s] = 0
		O_BOARD:
			var t2 := int(o.get("target", -1))
			if t2 >= 0 and t2 < n_units and u_side[t2] != u_side[s] and (u_state[t2] == S_SAIL or u_state[t2] == S_STRUCK) \
					and s_lit[t2] < 0:
				s_mode[s] = M_BOARD
				s_tgt[s] = t2
				s_tack[s] = 0
				s_tdir[s] = 0
		O_HEAD:
			s_mode[s] = M_HEAD
			s_tx[s] = int(o.get("facing", 0)) & FM.ANGLE_MASK
			s_tdir[s] = 0


# ------------------------------------------------------------------- step ---

func step() -> void:
	_apply_orders()
	_wind()
	if tick % FL_EVERY == 0 and decided_tick < 0:
		_fleet_judge()
	for s in n_units:
		if (tick + s) % 10 == 0 and ai_sides[u_side[s]] != 0 and u_state[s] == S_SAIL and decided_tick < 0:
			_think(s)
	for s in n_units:
		if (tick + s) % 5 == 0 or s_want[s] < 0:
			_steer(s)
	for s in n_units:
		_move(s)
	if gal_on != 0:
		_stroke()
	_contacts()
	if tick % DECK_EVERY == 0:
		_decks()
	_gunnery()
	if gal_on != 0:
		_missiles()
	if tick % 10 == 0:
		_fires()
		_morale()
	_decide()
	tick += 1


func _wind() -> void:
	if tick > 0 and tick % WIND_EVERY == 0:
		var d := _roll(61) - 30
		w_goal = (w_base + clampi(FM.angle_diff(w_base, w_goal) + d, -WIND_SPAN, WIND_SPAN)) & FM.ANGLE_MASK
	if tick % 4 == 0 and w_from != w_goal:
		w_from = (w_from + (1 if FM.angle_diff(w_from, w_goal) > 0 else -1)) & FM.ANGLE_MASK


func heading(s: int) -> int:
	return (s_h16[s] >> 4) & FM.ANGLE_MASK


func _vmax(s: int) -> int:
	return ST.stat(s_type[s], "vmax") * U / 100


func _irons(s: int) -> int:
	return ST.stat(s_type[s], "irons") * FM.ANGLE_FULL / 360


## Angle off the wind of heading h (0: head to wind, 512: dead downwind).
func off_wind(h: int) -> int:
	return absi(FM.angle_diff(h, w_from))


## Drive % on heading h for ship s (the points of sail).
func drive(s: int, h: int) -> int:
	if ST.stat(s_type[s], "oars") != 0:
		return 100
	var i := _irons(s)
	var off := off_wind(h)
	if off < i:
		return 0
	if off < i + 40:
		return 45 + (off - i) * 35 / 40
	if off < 256:
		return 80 + (off - i - 40) * 20 / maxi(256 - i - 40, 1)
	if off <= 400:
		return 100
	return 100 - (off - 400) * 18 / 112


## Angle off the wind ship s sails close-hauled (as close as the navigator
## lies: CLOSE_MARGIN off her no-go zone).
func close_hauled(s: int) -> int:
	return _irons(s) + CLOSE_MARGIN


## True if ship s can lie a course for (tx, ty) without beating.
func _lies(s: int, tx: int, ty: int) -> bool:
	if ST.stat(s_type[s], "oars") != 0:
		return true
	return absi(FM.angle_diff(w_from, FM.atan2_a(ty - s_y[s], tx - s_x[s]))) >= close_hauled(s)


## A heading near h that ship s can sail (out of the no-go zone).
func _sailable(s: int, h: int) -> int:
	if ST.stat(s_type[s], "oars") != 0:
		return h & FM.ANGLE_MASK
	var c := close_hauled(s)
	var d := FM.angle_diff(w_from, h)
	if absi(d) >= c:
		return h & FM.ANGLE_MASK
	return (w_from + (c if d >= 0 else -c)) & FM.ANGLE_MASK


func target_speed(s: int) -> int:
	if u_state[s] != S_SAIL or s_grap[s] >= 0:
		return 0
	var ty := s_type[s]
	var pct := int(SAIL_PCT[s_sail[s]])
	if ST.stat(ty, "dash") > 0:
		# (R1) The stroke: rest, cruise, ramming speed while the meter lasts; backing water after a ram.
		if tick - s_ram_t[s] < RAM_BACK:
			return 0
		pct = 0 if s_sail[s] == 0 else (100 if s_sail[s] == 2 and s_dash[s] > 0 else CRUISE_PCT)
	var v := _vmax(s) * drive(s, heading(s)) / 100 * pct / 100
	if ST.stat(ty, "oars") != 0:
		v = v * (300 + 700 * s_crew[s] / maxi(s_crew0[s], 1)) / 1000
	else:
		v = v * (250 + 750 * s_rig[s] / s_rig0[s]) / 1000
		v = v * mini(450 + w_str * 7, 1100) / 1000
	var hp := s_hull[s] * 100 / s_hull0[s]
	if hp < 50 and s_lit[s] < 0:
		v = v * (50 + hp) / 100  # (a blazing fire ship runs on till she goes)
	return v


# ------------------------------------------------------------- navigation ---

## The heading ship s steers for a point: straight there when it can lie
## that course, else close-hauled on a tack until the point bears on the
## other tack's layline. Sea room: a new board is the one with clear water
## SEA_ROOM_M ahead (the one she is on when both or neither have it, else
## the longer), and she tacks LAYLINE_M short of land or the edge ahead
## when the other board has more room.
func _course(s: int, tx: int, ty: int) -> int:
	var b := FM.atan2_a(ty - s_y[s], tx - s_x[s])
	if ST.stat(s_type[s], "oars") != 0:
		s_tack[s] = 0
		return b
	var c := close_hauled(s)
	var d := FM.angle_diff(w_from, b)
	if absi(d) >= c:
		s_tack[s] = 0
		return b
	if s_tack[s] == 0:
		var dh := FM.angle_diff(w_from, heading(s))
		var cur := 1 if dh >= 0 else -1
		var r_cur := _clear_run(s, (w_from + cur * c) & FM.ANGLE_MASK, SEA_ROOM_M, false)
		var r_oth := _clear_run(s, (w_from - cur * c) & FM.ANGLE_MASK, SEA_ROOM_M, false)
		s_tack[s] = cur if r_cur >= SEA_ROOM_M or r_cur >= r_oth else -cur
	var hd := (w_from + s_tack[s] * c) & FM.ANGLE_MASK
	var r_on := _clear_run(s, hd, LAYLINE_M, false)
	if r_on < LAYLINE_M:
		var ot := (w_from - s_tack[s] * c) & FM.ANGLE_MASK
		if _clear_run(s, ot, LAYLINE_M, false) > r_on:
			s_tack[s] = -s_tack[s]
			hd = ot
	return hd


## Clear water along heading h for `dist` metres (probes every 40 m) and
## inside the field (EDGE_M from the edges unless `edge_ok`).
func _probe_clear(s: int, h: int, dist: int, edge_ok: bool) -> bool:
	return _clear_run(s, h, dist, edge_ok) >= dist


## Metres of clear water (0 .. dist, in 40 m steps) ship s has ahead on
## heading h: a lane her beam wide plus a margin either side, free of land
## (and of shoals for a deep ship) and inside the field (EDGE_M from the
## edges, heading outward, unless `edge_ok`).
func _clear_run(s: int, h: int, dist: int, edge_ok: bool) -> int:
	var cs := FM.cos_a(h)
	var sn := FM.sin_a(h)
	var w := ST.stat(s_type[s], "beam") / 2 + 12
	var wx := ((-sn * w) >> 12) * U
	var wy := ((cs * w) >> 12) * U
	var m := 40
	while m <= dist:
		var x := s_x[s] + ((cs * m) >> 12) * U
		var y := s_y[s] + ((sn * m) >> 12) * U
		if _blocked(s, x, y) or _blocked(s, x + wx, y + wy) or _blocked(s, x - wx, y - wy):
			return m - 40
		if not edge_ok and (x < EDGE_M * U or y < EDGE_M * U or x > (field_w - EDGE_M) * U or y > (field_h - EDGE_M) * U) \
				and _outward(s, h):
			return m - 40
		m += 40
	return dist


## The bearing of the nearest land (or shoal she cannot cross) within
## LEE_SHORE_M to leeward of ship s (within 60 degrees of dead downwind),
## or -1.
func _lee_shore(s: int) -> int:
	if ST.stat(s_type[s], "oars") != 0:
		return -1
	var dn := (w_from + FM.ANGLE_HALF) & FM.ANGLE_MASK
	var best := -1
	var bd := LEE_SHORE_M + 1
	for k: int in [0, -85, 85, -170, 170]:
		var a := (dn + k) & FM.ANGLE_MASK
		var cs := FM.cos_a(a)
		var sn := FM.sin_a(a)
		var m := 30
		while m <= LEE_SHORE_M and m < bd:
			if _blocked(s, s_x[s] + ((cs * m) >> 12) * U, s_y[s] + ((sn * m) >> 12) * U):
				bd = m
				best = a
				break
			m += 30
	return best


## Heading `want` for ship s, kept off a lee shore: within LEE_SHORE_M of
## land to leeward she never steers in toward it but sails along it (the
## shore abeam, on the side nearer to `want` and her heading) until she is
## clear.
func _off_lee_shore(s: int, want: int) -> int:
	var ls := _lee_shore(s)
	if ls < 0 or absi(FM.angle_diff(want, ls)) >= 300:
		return want
	var best := want
	var bs := 1 << 30
	var h := heading(s)
	for sg: int in [1, -1]:
		var c := _sailable(s, (ls + sg * FM.ANGLE_QUARTER) & FM.ANGLE_MASK)
		var sc := absi(FM.angle_diff(want, c)) + absi(FM.angle_diff(h, c))
		if absi(FM.angle_diff(c, ls)) < 224:
			sc += 1024  # (still in toward it: only if the other is worse)
		if sc < bs:
			bs = sc
			best = c
	return best


func _outward(s: int, h: int) -> bool:
	var cx := field_w * U / 2 - s_x[s]
	var cy := field_h * U / 2 - s_y[s]
	var to_c := FM.atan2_a(cy, cx)
	return absi(FM.angle_diff(h, to_c)) > 256


## Heading h, or the nearest one (in 20 degree steps either way) with clear
## water ahead that ship s can sail.
func _avoid(s: int, h: int, edge_ok: bool) -> int:
	var reach := 120 + ST.stat(s_type[s], "len") * 2
	if _probe_clear(s, h, reach, edge_ok):
		return h
	# (The side she is already turning to first: no swinging either side of
	# an island.)
	var first := 1 if FM.angle_diff(h, heading(s)) >= 0 else -1
	for k in range(1, 9):
		for sg: int in [first, -first]:
			var c := (h + sg * k * 57) & FM.ANGLE_MASK
			if drive(s, c) > 0 and _probe_clear(s, c, reach, edge_ok):
				return c
	return h


func _steer(s: int) -> void:
	if u_state[s] != S_SAIL:
		s_want[s] = heading(s)
		return
	if s_grap[s] >= 0:
		s_want[s] = heading(s)
		return
	var h := heading(s)
	var want := h
	var edge_ok := false
	match s_mode[s]:
		M_FREE:
			want = h
		M_HEAD:
			want = _sailable(s, s_tx[s])
		M_GOTO:
			var dx := s_tx[s] - s_x[s]
			var dy := s_ty[s] - s_y[s]
			if FM.approx_len(dx, dy) < 35 * U:
				s_mode[s] = M_FREE
			else:
				want = _course(s, s_tx[s], s_ty[s])
		M_ENGAGE:
			var t := s_tgt[s]
			if t < 0 or u_state[t] != S_SAIL:
				s_mode[s] = M_FREE
				s_tgt[s] = -1
			else:
				want = _engage_heading(s, t)
		M_BOARD:
			var t2 := s_tgt[s]
			if t2 < 0 or not (u_state[t2] == S_SAIL or u_state[t2] == S_STRUCK) or s_grap[t2] >= 0 or s_lit[t2] >= 0:
				s_mode[s] = M_FREE
				s_tgt[s] = -1
			else:
				want = _board_heading(s, t2)
		M_FLEE:
			edge_ok = true
			if s_flee_x[s] < 0 or tick % 50 == 0:
				if s_ffl[s] != 0:
					_escape_goal(s)
				else:
					_flee_goal(s)
			want = _course(s, s_flee_x[s], s_flee_y[s])
		M_FIRE:
			want = _fire_heading(s)
	if s_lit[s] < 0:
		want = _off_lee_shore(s, want)
	want = _avoid(s, want, edge_ok)
	if absi(FM.angle_diff(want, s_want[s])) > 28:
		s_tdir[s] = 0
	s_want[s] = want


## The range (m) ship s engages at: the loaded shot's (the next one's while
## reloading), at most four fifths of her gun range.
func _want_range(s: int) -> int:
	if ST.is_galley(s_type[s]):
		return MSL_STAND
	var rng := ST.stat(s_type[s], "range")
	return mini(int(RANGE_PREF[s_ld[s * 2]]) if s_rl[s * 2] == 0 else int(RANGE_PREF[s_shot[s]]), rng * 8 / 10)


## Metres ship s lies to windward of ship t (negative: to leeward).
func _upwind_m(s: int, t: int) -> int:
	var dx := (s_x[s] - s_x[t]) / U
	var dy := (s_y[s] - s_y[t]) / U
	return (dx * FM.cos_a(w_from) + dy * FM.sin_a(w_from)) >> 12


## How far to windward (m) side `side` can beat in two boards: BOARD_M x 2
## close-hauled, for its worst sailer to windward (the fleet keeps together).
func _beat_reach(side: int) -> int:
	var r := 1 << 30
	for f in n_units:
		if u_side[f] == side and u_state[f] == S_SAIL and s_lit[f] < 0 and ST.stat(s_type[f], "oars") == 0 \
				and not ST.is_fire(s_type[f]):
			r = mini(r, (2 * BOARD_M * FM.cos_a(close_hauled(f))) >> 12)
	return r if r < (1 << 30) else 0


## Where ship s closes on target t from far off (the engagement rule):
## [kind, x, y]. Kind 0, she has the weather gauge (or can take it in one
## board): she bears down to her range on t's windward side (a point
## GAUGE_M to windward of t when she still has to take the gauge). Kind 1,
## she is to leeward: she makes for t's lee bow (her range off t's lee
## side, a little ahead of her), on a reach when she can lie it, else
## beating, never past t. Kind 2, the battle AI's leeward ship whose enemy
## lies to windward beyond its fleet's two boards' reach: she stops
## beating and holds her line close-hauled, hove to, to receive t (for the
## first HOLD_TICKS: an enemy who keeps the gauge and never comes down is
## then sought out after all, not left to win on the clock).
func _closing(s: int, t: int) -> Array:
	var want_r := _want_range(s)
	if ST.stat(s_type[s], "oars") != 0:
		return [0, s_x[t], s_y[t]]
	var cs := FM.cos_a(w_from)
	var sn := FM.sin_a(w_from)
	var up := _upwind_m(s, t)
	if up >= 0:
		return [0, s_x[t] + ((cs * want_r) >> 12) * U, s_y[t] + ((sn * want_r) >> 12) * U]
	var gx := s_x[t] + ((cs * GAUGE_M) >> 12) * U
	var gy := s_y[t] + ((sn * GAUGE_M) >> 12) * U
	if _lies(s, gx, gy):
		return [0, gx, gy]
	var th := heading(t)
	var k := want_r * 7 / 10
	var lx := s_x[t] - ((cs * k) >> 12) * U + ((FM.cos_a(th) * k) >> 12) * U
	var ly := s_y[t] - ((sn * k) >> 12) * U + ((FM.sin_a(th) * k) >> 12) * U
	if not _lies(s, lx, ly) and ai_sides[u_side[s]] != 0 and tick < HOLD_TICKS and -up - want_r > _beat_reach(u_side[s]):
		return [2, lx, ly]
	return [1, lx, ly]


## Engage target t: close on it from far off by the engagement rule
## (_closing), then keep a broadside on at the loaded shot's range,
## presenting the loaded side; open the range when too close.
func _engage_heading(s: int, t: int) -> int:
	if ST.stat(s_type[s], "ram") > 0 and ST.is_galley(s_type[s]):
		return _ram_heading(s, t)
	var dx := s_x[t] - s_x[s]
	var dy := s_y[t] - s_y[s]
	var d := FM.approx_len(dx, dy) / U
	var bt := FM.atan2_a(dy, dx)
	var want_r := _want_range(s)
	if d > want_r + 220:
		var cl := _closing(s, t)
		if int(cl[0]) == 2:
			s_tack[s] = 0
			return _sailable(s, bt)  # close-hauled, her broadside toward t's approach
		return _course(s, int(cl[1]), int(cl[2]))
	var cands: Array[int] = []
	if d > want_r + 60:
		cands = [(bt + 160) & FM.ANGLE_MASK, (bt - 160) & FM.ANGLE_MASK]
	elif d >= want_r - (15 if ST.is_galley(s_type[s]) else 50):  # (a galley opens inside her missile range)
		cands = [(bt + 256) & FM.ANGLE_MASK, (bt - 256) & FM.ANGLE_MASK]
	else:
		cands = [(bt + 340) & FM.ANGLE_MASK, (bt - 340) & FM.ANGLE_MASK]
	var h := heading(s)
	var best := h
	var bs := 1 << 30
	for i in 2:
		var c := _sailable(s, cands[i])
		# cands[0] (bt + x) puts the target to port, cands[1] to starboard.
		var score := absi(FM.angle_diff(h, c))
		if s_rl[s * 2 + i] > 0:
			score += 160
		if c != cands[i]:
			score += 60
		if score < bs:
			bs = score
			best = c
	return best


func _board_heading(s: int, t: int) -> int:
	var dx := s_x[t] - s_x[s]
	var dy := s_y[t] - s_y[s]
	var d := FM.approx_len(dx, dy) / U
	var galley := ST.is_galley(s_type[s])
	if galley and ST.stat(s_type[s], "corvus") != 0:
		# (R1) The corvus: a ram ship comes in as for a ram (the bridge drops
		# once the blow has stopped her alongside); else straight at her
		# (where she will be), dashing the last RUN_M m.
		if ST.stat(s_type[s], "ram") > 0:
			return _ram_heading(s, t)
		var cl := _lead_point(s, t, d)
		_run_stroke(s, d - ST.stat(s_type[s], "len") / 2 <= RUN_M)
		return FM.atan2_a(int(cl[1]) - s_y[s], int(cl[0]) - s_x[s])
	var th := heading(t)
	var lead := clampi(d * 10 / maxi(s_spd[s] * 10 / U, 2), 0, 60)  # ticks ahead
	var tx := s_x[t] + ((FM.cos_a(th) * s_spd[t]) >> 12) * lead / 4
	var ty := s_y[t] + ((FM.sin_a(th) * s_spd[t]) >> 12) * lead / 4
	if d > 90:
		# Come up under her stern, where her broadsides do not bear.
		var back := ST.stat(s_type[t], "len") / 2 + mini(d / 3, 70)
		var ax := tx - ((FM.cos_a(th) * back) >> 12) * U
		var ay := ty - ((FM.sin_a(th) * back) >> 12) * U
		s_sail[s] = 1 if galley else 2  # (a galley cruises in)
		return _course(s, ax, ay)
	# Close: come up alongside, matching her speed.
	var mine := s_spd[s]
	if mine > s_spd[t] + 200 and d < 45:
		s_sail[s] = 0
	elif mine > s_spd[t] + 120:
		s_sail[s] = 1
	else:
		s_sail[s] = 2
	if d > 30:
		return _sailable(s, FM.atan2_a(ty - s_y[s], tx - s_x[s]))
	return _sailable(s, th)


## A fire ship at her mark: at the mark's place a little ahead (when she can
## lie the course to it, else the tacks); lit inside FS_LIGHT_M when the
## course serves, abandoned (the helm lashed on that heading) inside
## FS_ABANDON_M or FS_ABANDON_TICKS after.
func _fire_heading(s: int) -> int:
	var t := s_tgt[s]
	if t < 0 or u_state[t] != S_SAIL or s_lit[t] >= 0:
		if s_lit[s] < 0:
			s_mode[s] = M_FREE
			s_tgt[s] = -1
		return heading(s)
	var d := FM.approx_len(s_x[t] - s_x[s], s_y[t] - s_y[s]) / U
	var lead := clampi(d * 10 / maxi(s_spd[s] * 10 / U, 2), 0, 80)
	var th := heading(t)
	var tx := s_x[t] + ((FM.cos_a(th) * s_spd[t]) >> 12) * lead
	var ty := s_y[t] + ((FM.sin_a(th) * s_spd[t]) >> 12) * lead
	var b := FM.atan2_a(ty - s_y[s], tx - s_x[s])
	var lies := absi(FM.angle_diff(w_from, b)) >= close_hauled(s)
	s_sail[s] = 2
	if s_lit[s] < 0 and d < FS_LIGHT_M and lies:
		_light(s)
	if s_lit[s] >= 0 and s_aband[s] == 0 and (d < FS_ABANDON_M or tick - s_lit[s] >= FS_ABANDON_TICKS):
		_abandon(s, _sailable(s, b))
		return heading(s) if s_mode[s] != M_HEAD else s_tx[s]
	return _course(s, tx, ty)


## Fire ship s is set alight (by her crew, or by a shot into her
## combustibles): she burns until she sinks; away from her mark her crew
## leave her at once.
func _light(s: int) -> void:
	if s_lit[s] >= 0:
		return
	s_lit[s] = tick
	s_burn[s] = FIRE_MAX
	s_sail[s] = 2
	stats["fireships"] = int(stats["fireships"]) + 1
	_event(EV_LIT, s, 0, s_tgt[s], 0, 0)
	if s_mode[s] != M_FIRE:
		_abandon(s, heading(s))


## Her crew lash the helm on heading h and take to the boat.
func _abandon(s: int, h: int) -> void:
	if s_aband[s] != 0:
		return
	s_aband[s] = 1
	s_crew[s] = 0
	s_mode[s] = M_HEAD
	s_tx[s] = h & FM.ANGLE_MASK
	s_tdir[s] = 0
	_event(EV_ABANDON, s, 0, s_tgt[s], 0, 0)


## Set ship o alight at intensity lv at least (a new fire: the event).
func _ignite(o: int, lv: int) -> void:
	if u_state[o] == S_SUNK or u_state[o] == S_FLED:
		return
	if s_burn[o] == 0:
		stats["fires"] = int(stats["fires"]) + 1
		_event(EV_FIRE, o, 0, -1, 0, 0)
	s_burn[o] = clampi(maxi(s_burn[o], lv), 1, FIRE_MAX)
	if ST.is_fire(s_type[o]) and s_lit[o] < 0:
		_light(o)


func _flee_goal(s: int) -> void:
	if ST.is_galley(s_type[s]) and _galley_flee(s):
		return
	# The edge point (of the four nearest) farthest from the enemy.
	var cands := [[s_x[s], -60 * U], [s_x[s], (field_h + 60) * U], [-60 * U, s_y[s]], [(field_w + 60) * U, s_y[s]]]
	var best := 0
	var bv := -(1 << 60)
	for i in 4:
		var c: Array = cands[i]
		var dmin := 1 << 40
		for e in n_units:
			if u_side[e] != u_side[s] and u_state[e] == S_SAIL:
				dmin = mini(dmin, FM.approx_len(int(c[0]) - s_x[e], int(c[1]) - s_y[e]))
		var own := FM.approx_len(int(c[0]) - s_x[s], int(c[1]) - s_y[s])
		var v := dmin - own * 2
		var b := FM.atan2_a(int(c[1]) - s_y[s], int(c[0]) - s_x[s])
		v -= (100 - drive(s, b)) * 8 * U
		if v > bv:
			bv = v
			best = i
	s_flee_x[s] = int(cands[best][0])
	s_flee_y[s] = int(cands[best][1])


# --------------------------------------------------------------- movement ---

func _turn_rate16(s: int) -> int:
	var ty := s_type[s]
	var r := ST.stat(ty, "turn") * 16384 / 36000
	var half := maxi(_vmax(s) / 2, 1)
	var pct := 25 + 75 * mini(s_spd[s], half) / half
	if ST.stat(ty, "oars") != 0:
		pct = maxi(pct, 60)
	return maxi(r * pct / 100, 1)


func _move(s: int) -> void:
	var st := u_state[s]
	if st == S_SUNK or st == S_FLED:
		return
	var ty := s_type[s]
	if s_grap[s] >= 0:
		_hold_alongside(s)
		return
	if s_fsg[s] >= 0:
		_fs_alongside(s)
		return
	# Turning.
	var h := heading(s)
	var want := s_want[s]
	var oars := ST.stat(ty, "oars") != 0
	var stalled := not oars and off_wind(h) < _irons(s) and s_spd[s] < _vmax(s) * 8 / 100
	if stalled and st == S_SAIL:
		# In irons without way: the wind pushes her bow off.
		var side := 1 if FM.angle_diff(w_from, h) >= 0 else -1
		s_h16[s] = (s_h16[s] + side * 9) & 16383
		s_tdir[s] = 0
	elif st == S_SAIL and want >= 0 and want != h:
		var diff := FM.angle_diff(h, want)
		if s_tdir[s] == 0:
			var dir := 1 if diff > 0 else -1
			if not oars and _crosses_wind(h, diff):
				if s_spd[s] < _vmax(s) * ST.stat(ty, "tack") / 100:
					dir = -dir  # wear round
					stats["wears"] = int(stats["wears"]) + 1
				else:
					stats["tacks"] = int(stats["tacks"]) + 1
			s_tdir[s] = dir
		var rate := _turn_rate16(s)
		var rem16 := 0
		if (diff > 0) == (s_tdir[s] > 0):
			rem16 = absi(diff) * 16
		else:
			rem16 = (FM.ANGLE_FULL - absi(diff)) * 16
		if rem16 <= rate:
			s_h16[s] = want * 16
			s_tdir[s] = 0
		else:
			s_h16[s] = (s_h16[s] + s_tdir[s] * rate) & 16383
	h = heading(s)
	# Speed.
	var tv := target_speed(s)
	var v := s_spd[s]
	if tv > v:
		v += maxi((tv - v) / 40, 1)
	elif tv < v:
		var k := 25
		if not oars and off_wind(h) < _irons(s):
			# Head to wind she loses her way fast, unless she is turning
			# through it (a tack carries her round on her way).
			k = TACK_WAY if s_tdir[s] != 0 else 12
		v -= maxi((v - tv) / k, 1)
	s_spd[s] = maxi(v, 0)
	# Way and leeway.
	var lee := 31 * w_str / 100
	if st != S_SAIL:
		lee = lee * 3 / 2
	var wt := (w_from + FM.ANGLE_HALF) & FM.ANGLE_MASK
	var nx := s_x[s] + ((FM.cos_a(h) * s_spd[s]) >> 12) + ((FM.cos_a(wt) * lee) >> 12)
	var ny := s_y[s] + ((FM.sin_a(h) * s_spd[s]) >> 12) + ((FM.sin_a(wt) * lee) >> 12)
	# The edge: a fleeing ship (or any not fighting) leaves the battle.
	var out := nx < 0 or ny < 0 or nx > field_w * U or ny > field_h * U
	if out:
		if st == S_SAIL and s_mode[s] == M_FLEE:
			u_state[s] = S_FLED
			s_end_t[s] = tick
			stats["fled"] = int(stats["fled"]) + 1
			_event(EV_FLED, s, 0, -1, 0, 0)
			return
		# Held at the edge: she slides along it (and the navigator turns her in).
		nx = clampi(nx, 0, field_w * U)
		ny = clampi(ny, 0, field_h * U)
		s_spd[s] = s_spd[s] * 15 / 16
	# Land: the bow and the hull's middle.
	var half := ST.stat(ty, "len") * U / 2
	var bx := nx + ((FM.cos_a(h) * (half >> 6)) >> 6)
	var by := ny + ((FM.sin_a(h) * (half >> 6)) >> 6)
	if _blocked(s, s_x[s], s_y[s]) and st == S_SAIL:
		# Aground amidships: she works off, slowly and without leeway, once
		# her bow points at open water within 60 m (the steering turns her).
		s_spd[s] = mini(s_spd[s], _vmax(s) / 10)
		var ok := false
		for m: int in [20, 40, 60]:
			if not _blocked(s, s_x[s] + ((FM.cos_a(h) * m) >> 12) * U, s_y[s] + ((FM.sin_a(h) * m) >> 12) * U):
				ok = true
				break
		if ok:
			s_x[s] = clampi(s_x[s] + ((FM.cos_a(h) * s_spd[s]) >> 12), 0, field_w * U)
			s_y[s] = clampi(s_y[s] + ((FM.sin_a(h) * s_spd[s]) >> 12), 0, field_h * U)
		else:
			s_spd[s] = 0
		return
	if _blocked(s, bx, by) or _blocked(s, nx, ny):
		if s_spd[s] > _vmax(s) / 5 and s_ground[s] <= tick:
			s_hull[s] = maxi(s_hull[s] - maxi(s_hull0[s] / 40, 1), 0)
			stats["grounded"] = int(stats["grounded"]) + 1
			_event(EV_GROUND, s, 0, -1, 0, 0)
			s_ground[s] = tick + 50
		s_spd[s] = 0
		if not _blocked(s, nx, ny) and _blocked(s, bx, by):
			# The bow is on the bank: she lies there (the steering turns her off).
			return
		# The middle too: back her off along her wake.
		var px := s_x[s] - ((FM.cos_a(h) * 2 * U) >> 12)
		var py := s_y[s] - ((FM.sin_a(h) * 2 * U) >> 12)
		if not _blocked(s, px, py):
			s_x[s] = px
			s_y[s] = py
		return
	s_x[s] = nx
	s_y[s] = ny


## True if turning from h by the signed diff (the short way) crosses the
## wind's eye.
func _crosses_wind(h: int, diff: int) -> bool:
	var a := FM.angle_diff(h, w_from)
	if diff > 0:
		return a > 0 and a < diff
	return a < 0 and a > diff


## A grappled pair: the defender drifts, the boarder lies alongside her.
func _hold_alongside(s: int) -> void:
	var o := s_grap[s]
	s_spd[s] = s_spd[s] * 7 / 8
	if s_boarder[s] == 0:
		var lee := 20 * w_str / 100
		var wt := (w_from + FM.ANGLE_HALF) & FM.ANGLE_MASK
		var nx := s_x[s] + ((FM.cos_a(wt) * lee) >> 12) + ((FM.cos_a(heading(s)) * s_spd[s]) >> 12)
		var ny := s_y[s] + ((FM.sin_a(wt) * lee) >> 12) + ((FM.sin_a(heading(s)) * s_spd[s]) >> 12)
		if not _blocked(s, nx, ny):
			s_x[s] = clampi(nx, 0, field_w * U)
			s_y[s] = clampi(ny, 0, field_h * U)
		return
	# The boarder: beside her, on the side it came from, heading with her.
	var oh := heading(o)
	var side := 1 if FM.angle_diff(oh, FM.atan2_a(s_y[s] - s_y[o], s_x[s] - s_x[o])) >= 0 else -1
	var gap := (ST.stat(s_type[s], "beam") + ST.stat(s_type[o], "beam")) / 2 + 2
	var pa := (oh + side * 256) & FM.ANGLE_MASK
	var gx := s_x[o] + ((FM.cos_a(pa) * gap) >> 12) * U
	var gy := s_y[o] + ((FM.sin_a(pa) * gap) >> 12) * U
	s_x[s] += (gx - s_x[s]) / 6
	s_y[s] += (gy - s_y[s]) / 6
	var dh := FM.angle_diff(heading(s), oh)
	s_h16[s] = (s_h16[s] + clampi(dh * 16, -40, 40)) & 16383


## A fire ship grappled to ship o: she lies along o's side and goes with her.
func _fs_alongside(s: int) -> void:
	var o := s_fsg[s]
	var oh := heading(o)
	var side := 1 if FM.angle_diff(oh, FM.atan2_a(s_y[s] - s_y[o], s_x[s] - s_x[o])) >= 0 else -1
	var gap := (ST.stat(s_type[s], "beam") + ST.stat(s_type[o], "beam")) / 2 + 2
	var pa := (oh + side * 256) & FM.ANGLE_MASK
	var gx := s_x[o] + ((FM.cos_a(pa) * gap) >> 12) * U
	var gy := s_y[o] + ((FM.sin_a(pa) * gap) >> 12) * U
	s_x[s] += (gx - s_x[s]) / 4
	s_y[s] += (gy - s_y[s]) / 4
	s_spd[s] = s_spd[o]
	var dh := FM.angle_diff(heading(s), oh)
	s_h16[s] = (s_h16[s] + clampi(dh * 16, -48, 48)) & 16383


## Ships too close push apart; boarders grapple their target; a lit fire
## ship grapples whatever she touches and sets it alight.
func _contacts() -> void:
	if gal_on != 0:
		_rams()
	for a in n_units:
		if u_state[a] == S_SUNK or u_state[a] == S_FLED:
			continue
		for b in range(a + 1, n_units):
			if u_state[b] == S_SUNK or u_state[b] == S_FLED:
				continue
			if s_grap[a] == b or s_fsg[a] == b or s_fsg[b] == a:
				continue
			var dx := s_x[b] - s_x[a]
			var dy := s_y[b] - s_y[a]
			var lim := (ST.stat(s_type[a], "len") + ST.stat(s_type[b], "len")) * U * 30 / 100
			if absi(dx) > lim * 2 or absi(dy) > lim * 2:
				continue
			var d := FM.approx_len(dx, dy)
			if d < lim:
				var push := (lim - d) / 2 + 1
				var ang := FM.atan2_a(dy, dx) if d > 0 else (a * 97) & FM.ANGLE_MASK
				var px := (FM.cos_a(ang) * (push >> 4)) >> 8
				var py := (FM.sin_a(ang) * (push >> 4)) >> 8
				if not _blocked(a, s_x[a] - px, s_y[a] - py) and s_grap[a] < 0:
					s_x[a] -= px
					s_y[a] -= py
				if not _blocked(b, s_x[b] + px, s_y[b] + py) and s_grap[b] < 0:
					s_x[b] += px
					s_y[b] += py
				s_spd[a] = s_spd[a] * 9 / 10
				s_spd[b] = s_spd[b] * 9 / 10
	for s in n_units:
		if u_state[s] != S_SAIL or s_mode[s] != M_BOARD or s_grap[s] >= 0:
			continue
		var t := s_tgt[s]
		if t < 0 or s_grap[t] >= 0 or not (u_state[t] == S_SAIL or u_state[t] == S_STRUCK) or s_lit[t] >= 0:
			continue
		var d2 := FM.approx_len(s_x[t] - s_x[s], s_y[t] - s_y[s])
		var reach := ((ST.stat(s_type[s], "len") + ST.stat(s_type[t], "len")) * 40 / 100 + 8) * U
		if d2 > reach:
			continue
		var vx := ((FM.cos_a(heading(s)) * s_spd[s]) >> 12) - ((FM.cos_a(heading(t)) * s_spd[t]) >> 12)
		var vy := ((FM.sin_a(heading(s)) * s_spd[s]) >> 12) - ((FM.sin_a(heading(t)) * s_spd[t]) >> 12)
		if FM.approx_len(vx, vy) > 360 and s_spd[t] > 150:
			continue
		_grapple(s, t, 1 if ST.stat(s_type[s], "corvus") != 0 else 0)
	if gal_on != 0:
		_corvus()
	for s in n_units:
		if s_lit[s] < 0 or s_fsg[s] >= 0 or u_state[s] != S_SAIL:
			continue
		for o in n_units:
			if o == s or u_state[o] == S_SUNK or u_state[o] == S_FLED or s_lit[o] >= 0:
				continue
			var lim2 := ((ST.stat(s_type[s], "len") + ST.stat(s_type[o], "len")) * 45 / 100 + 4) * U
			var ddx := s_x[o] - s_x[s]
			var ddy := s_y[o] - s_y[s]
			if absi(ddx) > lim2 or absi(ddy) > lim2 or FM.approx_len(ddx, ddy) > lim2:
				continue
			s_fsg[s] = o
			s_fs_t[s] = tick
			stats["fire_contacts"] = int(stats["fire_contacts"]) + 1
			_event(EV_FS_CONTACT, s, 0, o, 0, 0)
			_ignite(o, FS_FIRE)
			break


func _grapple(s: int, t: int, cv: int = 0) -> void:
	s_grap[s] = t
	s_grap[t] = s
	s_boarder[s] = 1
	s_boarder[t] = 0
	s_bd_t[s] = tick
	s_mode[s] = M_FREE
	stats["boardings"] = int(stats["boardings"]) + 1
	_event(EV_GRAPPLE, s, cv, t, 0, 0)
	if u_state[t] == S_STRUCK:
		_capture(t, s)
		return
	if deck_on != 0:
		s_bd_wait[s] = 1
	else:
		_deck_open(s, t)
		k_cv[s] = cv


# ------------------------------------------------------------- deck melee ---

## Every DECK_EVERY ticks: each boarding under way fights a deck step.
func _decks() -> void:
	for s in n_units:
		if k_on[s] != 0:
			if s_grap[s] < 0 or s_boarder[s] == 0:
				_deck_close(s)
			else:
				_deck_step(s)


## The deck melee between boarder s and target t begins: the two decks side
## by side (the boarder's rows on top, the rail between), each side's men as
## figures (the boarding party / every defender), the captain at the stern.
func _deck_open(s: int, t: int) -> void:
	var la := clampi(ST.stat(s_type[s], "len") / DECK_CELL_M, 5, 28)
	var lb := clampi(ST.stat(s_type[t], "len") / DECK_CELL_M, 5, 28)
	var w := maxi(la, lb)
	k_on[s] = 1
	k_t0[s] = tick
	k_w[s] = w
	k_hb[s] = clampi(ST.stat(s_type[s], "beam") / DECK_CELL_M, 2, 7)
	k_ht[s] = clampi(ST.stat(s_type[t], "beam") / DECK_CELL_M, 2, 7)
	k_ax0[s] = (w - la) / 2
	k_la[s] = la
	k_bx0[s] = (w - lb) / 2
	k_lb[s] = lb
	k_step[s] = 0
	var base := s * FIG
	for i in FIG:
		f_n[base + i] = 0
	_deck_side(s, 0, s, s_crew[s] * DECK_BOARD_PCT / 100, s_troops[s])
	_deck_side(s, 1, t, s_crew[t], s_troops[t])
	k2_mor[s * 2] = clampi(s_mor[s] + DECK_RUSH, 20, 170)
	k2_mor[s * 2 + 1] = clampi(s_mor[t], 20, 170)
	stats["deck_fights"] = int(stats["deck_fights"]) + 1


## Deck cell (x, y) of melee slot m can be stood on (its ship's deck, not a mast).
func _deck_walk(m: int, x: int, y: int) -> bool:
	var hb := k_hb[m]
	if y < 0 or y >= hb + k_ht[m] or x < 0 or x >= k_w[m]:
		return false
	var mine := y < hb
	var x0 := k_ax0[m] if mine else k_bx0[m]
	var ln := k_la[m] if mine else k_lb[m]
	if x < x0 or x >= x0 + ln:
		return false
	var mid := hb / 2 if mine else hb + k_ht[m] / 2
	if y == mid:
		var ty := s_type[m] if mine else s_type[s_grap[m]]
		for f in _masts(ty):
			if x == x0 + ln / 2 + int(f) * ln / 100:
				return false
	return true


## Mast places of ship type ty: % of the length from amidships toward the bow.
static func _masts(ty: int) -> Array:
	var key := str(ST.row(ty)["key"])
	if ST.stat(ty, "oars") != 0:
		return []
	if key == "sloop":
		return [12]
	if key == "brigantine" or key == "fire_ship":
		return [22, -12]
	return [30, 2, -25]


## Side `side` (0 boarders, 1 defenders) of melee m: ship `ship`'s crew and
## troops as figures, the soldiers at the rail, the crew behind, the captain
## at the stern.
func _deck_side(m: int, side: int, ship: int, crew: int, troops: int) -> void:
	var hb := k_hb[m]
	var rows: Array[int] = []
	if side == 0:
		for y in range(hb - 1, -1, -1):
			rows.append(y)
	else:
		for y in range(hb, hb + k_ht[m]):
			rows.append(y)
	var x0 := k_ax0[m] if side == 0 else k_bx0[m]
	var ln := k_la[m] if side == 0 else k_lb[m]
	# Cells from the rail back, amidships out.
	var cells: Array[int] = []
	for y in rows:
		for k in ln:
			var off := (k + 1) / 2 * (1 if k % 2 == 1 else -1)
			var x := x0 + ln / 2 + off
			if x >= x0 and x < x0 + ln and _deck_walk(m, x, y):
				cells.append(y * 256 + x)
	var base := m * FIG + side * DECK_FIG
	var men := crew + troops
	var cap_n := mini(ST.DECK_CAPTAIN_MEN, crew)
	var nf := mini(DECK_FIG, cells.size())
	k2_men0[m * 2 + side] = men
	k2_cap[m * 2 + side] = 0
	if men <= 0 or nf <= 0:
		return
	# The captain and his mates at the stern (the last row's first cell
	# from the stern end).
	var slot := 0
	if cap_n > 0 and nf >= 2:
		var cy: int = rows[rows.size() - 1]
		var cx := x0 + 1
		if not _deck_walk(m, cx, cy):
			cx = x0 + 2
		cells.erase(cy * 256 + cx)
		_fig(base, cx, cy, side, 2, cap_n, s_ck_atk[ship] * s_bq[ship] / 100 * ST.DECK_CAPTAIN_ATK / 100 * s_cq[ship] / 100,
			s_ck_def[ship] * ST.DECK_CAPTAIN_DEF / 100 * s_cq[ship] / 100, s_ck_shot[ship], s_ck_rng[ship], 2, 10)
		slot = 1
		crew -= cap_n
		nf -= 1
		k2_cap[m * 2 + side] = 1
	var nt := 0
	if troops > 0:
		nt = clampi((nf * troops + men / 2) / maxi(men, 1), 1, nf if crew <= 0 else maxi(nf - 1, 1))
	var nc := nf - nt if crew > 0 else 0
	var ci := 0
	# Soldiers by kit (their % of the troops), then the crew.
	var kits: Array = []
	var pct_sum := 0
	for k in TK_MAX:
		var pct := s_tkp[(ship * TK_MAX + k) * TKP]
		if pct > 0:
			kits.append(k)
			pct_sum += pct
	var left_t := troops
	var left_f := nt
	if kits.is_empty():
		kits = [-1]
		pct_sum = 100
	for ki in kits.size():
		var k: int = kits[ki]
		var b := (ship * TK_MAX + k) * TKP if k >= 0 else -1
		var pct := s_tkp[b] if b >= 0 else 100
		if left_f <= 0 or left_t <= 0:
			break
		var gm := left_t if ki == kits.size() - 1 else mini(troops * pct / maxi(pct_sum, 1), left_t)
		var gf := left_f if ki == kits.size() - 1 else clampi(nt * pct / maxi(pct_sum, 1), 1, left_f)
		left_t -= gm
		left_f -= gf
		gf = mini(gf, gm)
		for i in gf:
			if ci >= cells.size():
				break
			var c := cells[ci]
			ci += 1
			var n := gm / gf + (1 if i < gm % gf else 0)
			if b >= 0:
				_fig(base + slot, c % 256, c / 256, side, 1, n, s_tkp[b + 1], s_tkp[b + 2], s_tkp[b + 3], s_tkp[b + 4],
					s_tkp[b + 5], s_tkp[b + 6])
			else:
				_fig(base + slot, c % 256, c / 256, side, 1, n, int(ST.DECK_TROOPS["atk"]), int(ST.DECK_TROOPS["def"]),
					int(ST.DECK_TROOPS["shot"]), int(ST.DECK_TROOPS["rng"]), int(ST.DECK_TROOPS["shots"]),
					int(ST.DECK_TROOPS["rl"]))
			slot += 1
	nc = mini(nc + maxi(left_f, 0), crew)
	for i in nc:
		if ci >= cells.size():
			break
		var c2 := cells[ci]
		ci += 1
		var n2 := crew / nc + (1 if i < crew % nc else 0)
		_fig(base + slot, c2 % 256, c2 / 256, side, 0, n2, s_ck_atk[ship] * s_bq[ship] / 100, s_ck_def[ship] * s_bq[ship] / 100,
			s_ck_shot[ship], s_ck_rng[ship], s_ck_sh[ship], s_ck_rl[ship])
		slot += 1


func _fig(i: int, x: int, y: int, side: int, kind: int, n: int, atk: int, df: int, shot: int, rng: int, shots: int,
		rl: int) -> void:
	f_n[i] = maxi(n, 0)
	f_x[i] = x
	f_y[i] = y
	f_side[i] = side
	f_kind[i] = kind
	f_atk[i] = maxi(atk, 1)
	f_def[i] = maxi(df, 1)
	f_shot[i] = shot
	f_rng[i] = rng
	f_sh[i] = shots if rng > 0 and shot > 0 else 0
	f_rl[i] = maxi(rl, 10)
	f_ld[i] = 0


## One deck step of the melee of boarder s (see the header).
func _deck_step(s: int) -> void:
	var t := s_grap[s]
	var base := s * FIG
	var w := k_w[s]
	var h := k_hb[s] + k_ht[s]
	var occ := PackedInt32Array()
	occ.resize(w * h)
	occ.fill(-1)
	for i in FIG:
		if f_n[base + i] > 0:
			occ[f_y[base + i] * w + f_x[base + i]] = i
	var stepn := k_step[s]
	k_step[s] = stepn + 1
	var lost := [0, 0]
	var ships := [s, t]
	for kk in FIG:
		var i := kk if stepn % 2 == 0 else FIG - 1 - kk
		var fi := base + i
		if f_n[fi] <= 0:
			continue
		if f_ld[fi] > 0:
			f_ld[fi] = maxi(f_ld[fi] - DECK_EVERY, 0)
		var sd := f_side[fi]
		var best := -1
		var bd := 1 << 20
		for j in FIG:
			var fj := base + j
			if f_n[fj] <= 0 or f_side[fj] == sd:
				continue
			var d := maxi(absi(f_x[fj] - f_x[fi]), absi(f_y[fj] - f_y[fi]))
			if d < bd:
				bd = d
				best = j
		if best < 0:
			continue
		var fb := base + best
		var k := 0
		if bd <= 1:
			# Cold steel: shaken men strike weaker; a man on his own deck defends better.
			var atk := f_atk[fi] * (60 + clampi(k2_mor[s * 2 + sd], 0, 100) * 40 / 100) / 100
			var df := f_def[fb]
			if k_cv[s] != 0:
				if f_side[fb] == 0:
					df = df * DECK_BONUS_PCT / 100  # (over the corvus: the bonus is the boarders')
			elif (f_y[fb] < k_hb[s]) == (f_side[fb] == 0):
				df = df * DECK_BONUS_PCT / 100
			var p := DECK_KILL_PM * 2 * atk / maxi(atk + df, 1)
			if s_douse[ships[sd]] != 0:
				p = p * DOUSE_DECK_PCT / 100  # (her men half at the buckets)
			k = mini((f_n[fi] * p + _roll(1000)) / 1000, f_n[fb])
			f_hit[fi] = tick
		elif f_sh[fi] > 0 and f_ld[fi] == 0 and bd <= f_rng[fi]:
			# A volley: pistols over the rail, muskets, bows.
			var vp := f_shot[fi] * DECK_SHOT_PM
			if s_douse[ships[sd]] != 0:
				vp = vp * DOUSE_DECK_PCT / 100
			k = mini((f_n[fi] * vp + _roll(1000)) / 1000, f_n[fb])
			f_sh[fi] -= 1
			f_ld[fi] = f_rl[fi]
			f_hit[fi] = tick
			stats["deck_shots"] = int(stats["deck_shots"]) + 1
			_event(EV_DECK_SHOT, s, i, best, 0, 0)
		elif (stepn + i) % DECK_MOVE == 0:
			var dx := signi(f_x[fb] - f_x[fi])
			var dy := signi(f_y[fb] - f_y[fi])
			var tries: Array = [[dx, dy], [dx, 0], [0, dy]]
			if dx == 0:
				tries.append([1, dy])
				tries.append([-1, dy])
			elif dy == 0:
				tries.append([dx, 1])
				tries.append([dx, -1])
			for st2 in tries:
				var nx := f_x[fi] + int(st2[0])
				var ny := f_y[fi] + int(st2[1])
				if (int(st2[0]) == 0 and int(st2[1]) == 0) or not _deck_walk(s, nx, ny) or occ[ny * w + nx] >= 0:
					continue
				occ[f_y[fi] * w + f_x[fi]] = -1
				occ[ny * w + nx] = i
				f_x[fi] = nx
				f_y[fi] = ny
				break
		if k <= 0:
			continue
		f_n[fb] -= k
		var vs := 1 - sd
		var sh: int = ships[vs]
		if f_kind[fb] == 1:
			s_troops[sh] = maxi(s_troops[sh] - k, 0)
		else:
			s_crew[sh] = maxi(s_crew[sh] - k, 0)
		s_kills[ships[sd]] += k
		lost[vs] += k
		if f_n[fb] <= 0:
			f_n[fb] = 0
			occ[f_y[fb] * w + f_x[fb]] = -1
			if f_kind[fb] == 2:
				k2_cap[s * 2 + vs] = 0
				k2_mor[s * 2 + vs] -= DECK_CAPT_LOSS
				stats["captains_fallen"] = int(stats["captains_fallen"]) + 1
				_event(EV_CAPTAIN, s, vs, t, 0, 0)
	# Morale: the share of the men lost (less with the captain standing),
	# a little more when outnumbered.
	var men := [0, 0]
	for i in FIG:
		if f_n[base + i] > 0:
			men[f_side[base + i]] += f_n[base + i]
	for sd in 2:
		var l: int = lost[sd]
		if l > 0:
			var dm := l * DECK_MOR_LOSS / maxi(k2_men0[s * 2 + sd], 1)
			if k2_cap[s * 2 + sd] != 0:
				dm = dm * 3 / 4
			k2_mor[s * 2 + sd] -= maxi(dm, 1)
		if int(men[sd]) * 100 < int(men[1 - sd]) * 60:
			k2_mor[s * 2 + sd] -= 1
	var ma: int = men[0]
	var md: int = men[1]
	var age := tick - k_t0[s]
	var def_breaks := md == 0 or k2_mor[s * 2 + 1] <= 0 or md * 100 < ma * DECK_BREAK_DEF
	var att_breaks := ma == 0 or k2_mor[s * 2] <= 0 or (age >= 20 and ma * 100 < md * DECK_BREAK_ATT)
	stats["deck_ticks"] = int(stats["deck_ticks"]) + DECK_EVERY
	if def_breaks and not att_breaks:
		# The deck is lost: she strikes, and is taken.
		_event(EV_DECK_END, s, 0, t, 1, 0)
		stats["deck_taken"] = int(stats["deck_taken"]) + 1
		_capture(t, s)
	elif att_breaks and not def_breaks:
		_event(EV_DECK_END, s, 0, t, 2, 0)
		stats["deck_repelled"] = int(stats["deck_repelled"]) + 1
		_repelled(s, t, 0)
	elif (att_breaks and def_breaks) or age >= DECK_MAX_TICKS:
		# Both crews spent: the grapples are cut and the ships part.
		_event(EV_DECK_END, s, 0, t, 3, 0)
		stats["deck_spent"] = int(stats["deck_spent"]) + 1
		_repelled(s, t, 1)
		s_mor[t] -= 15


## Boarder s's men are back aboard (thrown back, or spent: both = 1).
func _repelled(s: int, t: int, both: int) -> void:
	_ungrapple(s)
	if gal_on != 0:
		s_cv_t[s] = tick
	s_mor[s] -= 15 if both != 0 else 25
	s_mode[s] = M_FREE
	stats["repelled"] = int(stats["repelled"]) + 1
	_event(EV_REPELLED, s, both, t, 0, 0)


func _deck_close(m: int) -> void:
	k_on[m] = 0
	k_cv[m] = 0
	var base := m * FIG
	for i in FIG:
		f_n[base + i] = 0


## Men lost from ship s: troops and crew in proportion.
func _lose_men(s: int, n: int) -> void:
	var tot := s_crew[s] + s_troops[s]
	if tot <= 0 or n <= 0:
		return
	var tl := s_troops[s] * n / tot
	s_troops[s] = maxi(s_troops[s] - tl, 0)
	s_crew[s] = maxi(s_crew[s] - (n - tl), 0)


func _ungrapple(s: int) -> void:
	var t := s_grap[s]
	if k_on[s] != 0:
		_deck_close(s)
	if t >= 0 and k_on[t] != 0:
		_deck_close(t)
	s_grap[s] = -1
	s_boarder[s] = 0
	s_bd_wait[s] = 0
	if t >= 0:
		s_grap[t] = -1
		s_boarder[t] = 0
		s_bd_wait[t] = 0


## Prize p is taken by ship c's side: a prize crew goes across.
func _capture(p: int, c: int) -> void:
	_ungrapple(c)
	u_state[p] = S_TAKEN
	s_by[p] = u_side[c]
	s_end_t[p] = tick
	s_sail[p] = 0
	s_burn[p] = 0
	s_douse[p] = 0
	var pc := clampi(s_crew[c] / 8, 1, 40)
	s_crew[c] = maxi(s_crew[c] - pc, 1)
	s_crew[p] = pc
	s_troops[p] = 0
	s_mode[c] = M_FREE
	s_tgt[c] = -1
	stats["captured"] = int(stats["captured"]) + 1
	_event(EV_TAKEN, c, 0, p, 0, 0)
	_shock(p, 10)


## N3b: the deck melee between boarder s and target t is decided.
func _deck_result(s: int, t: int, won: int, crew_a: int, crew_b: int) -> void:
	if t < 0 or t >= n_units or s_grap[s] != t or s_boarder[s] == 0 or s_bd_wait[s] == 0:
		return  # (only a boarding waiting for an outside melee, scenario "deck" 1)
	s_crew[s] = clampi(crew_a, 0, s_crew[s])
	s_crew[t] = clampi(crew_b, 0, s_crew[t])
	s_bd_wait[s] = 0
	if won != 0:
		_capture(t, s)
	else:
		_ungrapple(s)
		s_mor[s] -= 25
		_event(EV_REPELLED, s, 0, t, 0, 0)


## N3b hook: the grappled pairs waiting for a deck melee (scenario "deck"):
## [{boarder, target, sides, crews, troops, quality}].
func deck_request() -> Array:
	var out: Array = []
	for s in n_units:
		if s_grap[s] >= 0 and s_boarder[s] != 0 and s_bd_wait[s] != 0:
			var t := s_grap[s]
			out.append({"boarder": s, "target": t, "sides": [u_side[s], u_side[t]], "crews": [s_crew[s], s_crew[t]],
				"troops": [s_troops[s], s_troops[t]], "quality": [s_bq[s], s_bq[t]],
				"ships": [str(ST.row(s_type[s])["key"]), str(ST.row(s_type[t])["key"])]})
	return out


# ---------------------------------------------------------------- gunnery ---

func shot_range(s: int, shot: int) -> int:
	var r := ST.stat(s_type[s], "range")
	if shot == ST.SHOT_CHAIN:
		return r * ST.CHAIN_RANGE_PCT / 100
	if shot == ST.SHOT_GRAPE:
		return r * ST.GRAPE_RANGE_PCT / 100
	return r


## Reload speed per mille (the gun crews: MEN_PER_GUN a gun on both sides).
func _crew_rate(s: int) -> int:
	var need := maxi(ST.stat(s_type[s], "guns") * ST.MEN_PER_GUN * 2, 1)
	return clampi(s_crew[s] * 1000 / need, 150, 1000)


func guns_working(s: int) -> int:
	var gn := ST.stat(s_type[s], "guns")
	return maxi(gn * (40 + 60 * s_hull[s] / s_hull0[s]) / 100, 1 if s_hull[s] > 0 else 0)


func _gunnery() -> void:
	for s in n_units:
		if u_state[s] != S_SAIL or ST.stat(s_type[s], "guns") == 0 or s_douse[s] != 0:
			continue  # (dousing: the gun crews are at the buckets; loaded guns keep their load)
		var rate := _crew_rate(s)
		for k in 2:
			var i := s * 2 + k
			if s_rl[i] > 0:
				s_rl[i] = maxi(s_rl[i] - rate, 0)
				continue
			if s_grap[s] >= 0 or decided_tick >= 0:
				continue
			var t := _pick_target(s, k)
			if t >= 0:
				_broadside(s, k, t)


## The target for ship s's broadside k (0 port, 1 starboard): the ordered
## one when it bears, else (fire at will) the nearest enemy in the arc and
## in range of the loaded shot, not masked by a friend.
func _pick_target(s: int, k: int) -> int:
	var h := heading(s)
	var arc := (h - 256 if k == 0 else h + 256) & FM.ANGLE_MASK
	var rng := shot_range(s, s_ld[s * 2 + k]) * U
	var best := -1
	var bd := 1 << 40
	for t in n_units:
		if u_side[t] == u_side[s] or u_state[t] != S_SAIL:
			continue
		var dx := s_x[t] - s_x[s]
		var dy := s_y[t] - s_y[s]
		if absi(dx) > rng or absi(dy) > rng:
			continue
		var d := FM.approx_len(dx, dy)
		if d > rng:
			continue
		if absi(FM.angle_diff(arc, FM.atan2_a(dy, dx))) > ARC:
			continue
		if t != s_tgt[s] and s_fire[s] == 0:
			continue
		var score := d
		if t == s_tgt[s]:
			score -= 1 << 30
		elif s_lit[t] >= 0 and d < 300 * U:
			score -= 1 << 29  # a fire ship bearing down: everything at her
		if score < bd and not _masked(s, t, d):
			bd = score
			best = t
	return best


## A friendly ship lies in the line of fire from s to t (d: distance).
func _masked(s: int, t: int, d: int) -> bool:
	var bt := FM.atan2_a(s_y[t] - s_y[s], s_x[t] - s_x[s])
	for f in n_units:
		if f == s or u_side[f] != u_side[s] or u_state[f] == S_SUNK or u_state[f] == S_FLED:
			continue
		var dx := s_x[f] - s_x[s]
		var dy := s_y[f] - s_y[s]
		var df := FM.approx_len(dx, dy)
		if df >= d or df < 5 * U:
			continue
		var half := (ST.stat(s_type[f], "len") / 2 + 4) * U
		var ang := absi(FM.angle_diff(bt, FM.atan2_a(dy, dx)))
		# The friend's half-length subtends about half / df radians.
		if ang * df < half * 163:
			return true
	return false


func _broadside(s: int, k: int, t: int) -> void:
	var i := s * 2 + k
	var shot := s_ld[i]
	var ty := s_type[s]
	var tt := s_type[t]
	var d := FM.approx_len(s_x[t] - s_x[s], s_y[t] - s_y[s]) / U
	var rng := maxi(shot_range(s, shot), 1)
	var size := 50 + ST.stat(tt, "len") * 50 / 40
	var p := 88 * size / 100 * (100 - 70 * mini(d, rng) / rng) / 100 * s_q[s] / 100
	if shot == ST.SHOT_GRAPE:
		p = p * 120 / 100
	p = clampi(p, 3, 95)
	var guns := guns_working(s)
	var hits := 0
	for n in guns:
		if _roll(100) < p:
			hits += 1
	# Raking: from ahead of her bow or astern, down her length.
	var asp := absi(FM.angle_diff(heading(t), FM.atan2_a(s_y[s] - s_y[t], s_x[s] - s_x[t])))
	var rake := asp < 90 or asp > FM.ANGLE_HALF - 90
	var w := ST.stat(ty, "gun")
	var hull0 := s_hull[t]
	var men := 0
	match shot:
		ST.SHOT_ROUND:
			s_hull[t] -= hits * w
			men = hits * (w + 2) / 5
			for n in hits:
				if s_burn[t] == 0 and _roll(1000) < FIRE_PM * (4 if ST.is_fire(tt) else 1):
					_ignite(t, FIRE_START)
			s_rig[t] -= hits * w / 4
		ST.SHOT_CHAIN:
			s_rig[t] -= hits * w * 2
			s_hull[t] -= hits
			men = hits / 3
			stats["chain"] = int(stats["chain"]) + 1
		_:
			men = hits * (w / 4 + 1)
			s_rig[t] -= hits
			stats["grape"] = int(stats["grape"]) + 1
	if rake:
		# Down her length: round shot 2 x the slaughter, chain 1.5, grape 1.6.
		men = men * [20, 15, 16][shot] / 10
		stats["rakes"] = int(stats["rakes"]) + 1
	men += _roll(hits + 1) if hits > 0 else 0
	s_rig[t] = maxi(s_rig[t], 0)
	var before := s_crew[t] + s_troops[t]
	_lose_men(t, men)
	var lost := before - s_crew[t] - s_troops[t]
	s_kills[s] += lost
	s_hull[t] = maxi(s_hull[t], 0)
	# Morale: the share of hull and men lost, raking, a hit at all.
	if hits > 0:
		var dm := (hull0 - s_hull[t]) * 100 / s_hull0[t] / 2 + lost * 150 / maxi(s_crew0[t], 1) + (3 if rake else 0) + 1
		s_mor[t] -= dm
		s_hit_t[t] = tick
	if s_hull[t] == 0:
		_sink(t)
	s_rl[i] = ST.stat(ty, "reload") * 10 * 1000
	s_ld[i] = s_shot[s]
	stats["broadsides"] = int(stats["broadsides"]) + 1
	stats["hits"] = int(stats["hits"]) + hits
	_event(EV_BROADSIDE, s, k, t, hits, shot)


func _sink(s: int) -> void:
	if u_state[s] == S_SUNK:
		return
	if s_grap[s] >= 0:
		_ungrapple(s_grap[s] if s_boarder[s] == 0 else s)
	u_state[s] = S_SUNK
	s_end_t[s] = tick
	s_spd[s] = 0
	s_burn[s] = 0
	s_douse[s] = 0
	s_fsg[s] = -1
	stats["sunk"] = int(stats["sunk"]) + 1
	_event(EV_SINK, s, 0, -1, 0, 0)
	_shock(s, 12)


## Friends of ship s within 500 m lose heart.
func _shock(s: int, n: int) -> void:
	for f in n_units:
		if f != s and u_side[f] == u_side[s] and u_state[f] == S_SAIL:
			if FM.approx_len(s_x[f] - s_x[s], s_y[f] - s_y[s]) < 500 * U:
				s_mor[f] -= n


# ------------------------------------------------------------ fire, morale ---

func _fires() -> void:
	for s in n_units:
		if s_burn[s] == 0:
			s_douse[s] = 0
			continue
		if u_state[s] == S_SUNK or u_state[s] == S_FLED:
			s_burn[s] = 0
			s_douse[s] = 0
			continue
		if ST.is_fire(s_type[s]):
			_fireship_burn(s)
			continue
		# The fire grows; the crew fight it (by their share of a full crew).
		s_burn[s] += FIRE_GROW + _roll(FIRE_GROW_ROLL + 1)
		s_burn[s] -= fire_fight(s)
		if s_burn[s] <= 0:
			s_burn[s] = 0
			stats["fire_out"] = int(stats["fire_out"]) + 1
			if s_douse[s] != 0:
				s_douse[s] = 0  # (out: back to the guns)
				stats["douse_out"] = int(stats["douse_out"]) + 1
			continue
		s_burn[s] = mini(s_burn[s], FIRE_MAX)
		s_hull[s] = maxi(s_hull[s] - maxi(s_hull0[s] * s_burn[s] / FIRE_HULL, 1), 0)
		if s_hull[s] == 0:
			stats["fire_sunk"] = int(stats["fire_sunk"]) + 1
			_sink(s)
			continue
		if s_burn[s] > MAG_LV and _roll(1000) < (s_burn[s] - MAG_LV) / MAG_DIV:
			_blast(s)


## Intensity a second ship s's crew beat her fire down by: FIRE_FIGHT x the
## crew's share of a full crew, DOUSE_FIGHT_PCT % of that while dousing.
func fire_fight(s: int) -> int:
	var f := FIRE_FIGHT * mini(s_crew[s], s_crew0[s]) / maxi(s_crew0[s], 1)
	return f * DOUSE_FIGHT_PCT / 100 if s_douse[s] != 0 else f


## The Douse order for ship s (on 1 / 0): on only while she burns (not a fire
## ship); off at any time.
func _set_douse(s: int, on: int) -> void:
	if on == 0:
		s_douse[s] = 0
		return
	if s_burn[s] == 0 or ST.is_fire(s_type[s]) or s_douse[s] != 0:
		return
	s_douse[s] = 1
	stats["douse"] = int(stats["douse"]) + 1


## A burning fire ship (a second): she burns down; the ship she is grappled
## to burns the harder for it; sparks catch ships close by.
func _fireship_burn(s: int) -> void:
	if s_lit[s] < 0:
		_light(s)  # (a shot into her combustibles)
	s_burn[s] = FIRE_MAX
	s_hull[s] = maxi(s_hull[s] - maxi(s_hull0[s] * FS_BURN_PCT / 100, 1), 0)
	var o := s_fsg[s]
	if o >= 0:
		if u_state[o] == S_SUNK or u_state[o] == S_FLED or tick - s_fs_t[s] >= FS_STICK_TICKS:
			s_fsg[s] = -1
		else:
			_ignite(o, mini(maxi(s_burn[o], 1) + FS_FEED, FIRE_MAX))
	for o2 in n_units:
		if o2 == s or o2 == o or u_state[o2] == S_SUNK or u_state[o2] == S_FLED or s_lit[o2] >= 0:
			continue
		var r := (FS_SPREAD_M + (ST.stat(s_type[s], "len") + ST.stat(s_type[o2], "len")) / 2) * U
		var dx := s_x[o2] - s_x[s]
		var dy := s_y[o2] - s_y[s]
		if absi(dx) > r or absi(dy) > r or FM.approx_len(dx, dy) > r:
			continue
		if _roll(100) < FS_SPREAD_PCT:
			stats["fs_spread"] = int(stats["fs_spread"]) + 1
			_ignite(o2, 150)
	if s_hull[s] == 0:
		_sink(s)


## The magazine goes up: she is gone, her neighbours scorched (and fired).
func _blast(s: int) -> void:
	s_blown[s] = 1
	stats["blown"] = int(stats["blown"]) + 1
	_event(EV_BLAST, s, 0, -1, 0, 0)
	s_hull[s] = 0
	s_crew[s] = s_crew[s] / 10
	s_troops[s] = s_troops[s] / 10
	_sink(s)
	for f in n_units:
		if f == s or u_state[f] == S_SUNK or u_state[f] == S_FLED:
			continue
		var d := FM.approx_len(s_x[f] - s_x[s], s_y[f] - s_y[s]) / U
		if d >= BLAST_M:
			continue
		s_hull[f] = maxi(s_hull[f] - 140 * (BLAST_M - d) / BLAST_M, 0)
		_lose_men(f, s_crew[f] * (BLAST_M - d) / BLAST_M / 6)
		s_mor[f] -= 20
		if _roll(100) < 50:
			_ignite(f, BLAST_FIRE)
		if s_hull[f] == 0:
			_sink(f)


func _morale() -> void:
	if decided_tick >= 0:
		return
	for s in n_units:
		if u_state[s] != S_SAIL:
			continue
		if tick - s_hit_t[s] > 80 and s_mor[s] < 100:
			s_mor[s] += 1
		if s_grap[s] >= 0 or s_lit[s] >= 0:
			continue  # (a deck fight decides itself; a lit fire ship has nobody aboard)
		var crew_pct := s_crew[s] * 100 / maxi(s_crew0[s], 1)
		var hull_pct := s_hull[s] * 100 / s_hull0[s]
		var near := _enemy_within(s, 400)
		if s_mor[s] <= 0 or (near and (crew_pct < 18 or (hull_pct < 12 and s_rig[s] * 100 / s_rig0[s] < 25))):
			if ST.is_fire(s_type[s]):
				_light(s)  # (a fire ship's volunteers never strike: they fire her)
			else:
				_strike(s)


func _enemy_within(s: int, m: int) -> bool:
	for e in n_units:
		if u_side[e] != u_side[s] and u_state[e] == S_SAIL and s_lit[e] < 0:
			if FM.approx_len(s_x[e] - s_x[s], s_y[e] - s_y[s]) < m * U:
				return true
	return false


func _strike(s: int) -> void:
	if s_grap[s] >= 0:
		_ungrapple(s_grap[s] if s_boarder[s] == 0 else s)
	u_state[s] = S_STRUCK
	s_end_t[s] = tick
	s_sail[s] = 0
	s_mode[s] = M_FREE
	stats["struck"] = int(stats["struck"]) + 1
	_event(EV_STRIKE, s, 0, -1, 0, 0)
	_shock(s, 8)


# ----------------------------------------------------------------- decide ---

func fighting(side: int) -> int:
	var n := 0
	for s in n_units:
		if u_side[s] == side and u_state[s] == S_SAIL and s_lit[s] < 0:
			n += 1
	return n


## Fighting power left on a side (hull x guns of its fighting ships, by
## their crews).
func power(side: int) -> int:
	var p := 0
	for s in n_units:
		if u_side[s] == side and u_state[s] == S_SAIL and s_lit[s] < 0:
			p += (_guns_eq(s) * 10 + s_hull[s] / 10) * (s_hull[s] * 100 / s_hull0[s] + s_crew[s] * 100 /
				maxi(s_crew0[s], 1)) / 200
	return p


func _decide() -> void:
	if decided_tick >= 0:
		if ended == 0 and tick >= decided_tick + END_TICKS:
			ended = 1
		return
	var f0 := fighting(0)
	var f1 := fighting(1)
	var w := -1
	if f0 == 0 or f1 == 0:
		w = 0 if f0 > 0 else 1
	elif tick >= time_limit:
		w = 0 if power(0) > power(1) else 1
		if fl_on[w] == 1 and fl_on[1 - w] != 1:
			w = 1 - w  # (a fleet in flight does not hold the field)
			stat_fl[3] += 1
	if w < 0:
		return
	winner = w
	decided_tick = tick
	for s in n_units:
		if u_state[s] == S_STRUCK and u_side[s] != w:
			u_state[s] = S_TAKEN
			s_by[s] = w
			_event(EV_TAKEN, -1, 0, s, 0, 0)
		elif u_state[s] == S_STRUCK:
			u_state[s] = S_SAIL  # her own side held the field: the colours go up again
			s_mode[s] = M_FREE
			s_mor[s] = maxi(s_mor[s], 40)
		if s_grap[s] >= 0 and s_boarder[s] != 0:
			_ungrapple(s)


# ------------------------------------------------------- the flight rule ---

## Damage side `side` has taken so far (1000 = one ship's hull or crew): hull
## and crew lost by share, and a ship struck or taken counts 1000 more.
func _fl_damage(side: int) -> int:
	var d := 0
	for s in n_units:
		if u_side[s] != side or ST.is_fire(s_type[s]):
			continue
		d += (s_hull0[s] - s_hull[s]) * 1000 / maxi(s_hull0[s], 1) + (s_crew0[s] - s_crew[s]) * 1000 / maxi(s_crew0[s], 1)
		if u_state[s] == S_STRUCK or u_state[s] == S_TAKEN:
			d += 1000
	return d


## Fighting strength of side `side` (the flight rule): guns x hull % x the
## share of the guns her crew can serve, over its ships still fighting.
func _fl_strength(side: int) -> int:
	var p := 0
	for s in n_units:
		if u_side[s] == side and u_state[s] == S_SAIL and s_lit[s] < 0 and not ST.is_fire(s_type[s]):
			var cr := _crew_rate(s)
			if ST.is_galley(s_type[s]):
				cr = clampi(s_crew[s] * 1000 / maxi(s_crew0[s], 1), 150, 1000)
			p += _guns_eq(s) * (s_hull[s] * 100 / s_hull0[s]) * cr / 1000
	return p


## True if ship s can sail away (the flight rule): fighting, not grappled,
## not a fire ship, her rigging FL_RIG_PCT % or more (dismasted: she fights on).
func _fl_can_run(s: int) -> bool:
	return u_state[s] == S_SAIL and s_grap[s] < 0 and s_lit[s] < 0 and not ST.is_fire(s_type[s]) \
			and s_rig[s] * 100 / s_rig0[s] >= FL_RIG_PCT


## An enemy of side `side` within m metres of one of its fighting ships.
func _fl_near(side: int, m: int) -> bool:
	for s in n_units:
		if u_side[s] == side and u_state[s] == S_SAIL and _enemy_within(s, m):
			return true
	return false


## The battle AI's fleet judgement (every FL_EVERY ticks): the damage
## samples for the trend (the last FL_HIST, 2 minutes), then for each AI
## side: fleeing, it rallies when no enemy came within FL_RALLY_M for
## FL_RALLY_TICKS, or withdraws after FL_CAP_TICKS with no enemy within
## FL_CLEAR_M; else it flees when its fighting strength is under its
## skill's SEA_FLEE_RATIO % of the enemy's and it took more damage than it
## dealt in the last 2 minutes (FL_TREND_MIN at least); with half its ships
## crippled or taken, under that ratio + FL_CRIP_ADD and losing the same way.
func _fleet_judge() -> void:
	var slot := (tick / FL_EVERY) % FL_HIST
	var now := [_fl_damage(0), _fl_damage(1)]
	var taken := [int(now[0]) - fl_hist[slot], int(now[1]) - fl_hist[FL_HIST + slot]]
	fl_hist[slot] = int(now[0])
	fl_hist[FL_HIST + slot] = int(now[1])
	for side in 2:
		if ai_sides[side] == 0:
			continue
		if fl_on[side] == 2:
			# Rallied and holding: until an enemy comes within FL_HOLD_M, at most HOLD_TICKS.
			if _fl_near(side, FL_HOLD_M) or tick - fl_t[side] >= HOLD_TICKS:
				fl_on[side] = 0
			continue
		if fl_on[side] == 1:
			_fl_fleeing(side, now)
			continue
		var mine := _fl_strength(side)
		var theirs := _fl_strength(1 - side)
		if mine <= 0 or theirs <= 0:
			continue
		var losing := int(taken[side]) >= FL_TREND_MIN and int(taken[side]) > int(taken[1 - side])
		var ratio := mine * 100 / theirs
		var tot := 0
		var crip := 0
		for s in n_units:
			if u_side[s] != side or ST.is_fire(s_type[s]) or u_state[s] == S_FLED:
				continue
			tot += 1
			if u_state[s] != S_SAIL or s_rig[s] * 100 / s_rig0[s] < 25 or s_hull[s] * 100 / s_hull0[s] < 30 \
					or s_crew[s] * 100 / maxi(s_crew0[s], 1) < 30:
				crip += 1
		var lim: int = SEA_FLEE_RATIO[ai_skill[side]]
		if losing and (ratio < lim or (crip * 2 >= tot and ratio < lim + FL_CRIP_ADD)):
			fl_on[side] = 1
			fl_t[side] = tick
			fl_far[side] = -1
			stat_fl[0] += 1
			_fl_send(side)


## The fleeing fleet of side `side`: every ship that can sail away runs.
func _fl_send(side: int) -> void:
	for s in n_units:
		if u_side[s] == side and _fl_can_run(s) and s_mode[s] != M_FLEE:
			s_mode[s] = M_FLEE
			s_ffl[s] = 1
			s_flee_x[s] = -1
			s_sail[s] = 2
			s_tack[s] = 0
			s_tdir[s] = 0


func _fl_fleeing(side: int, now: Array) -> void:
	_fl_send(side)  # (a ship whose boarding ended runs too)
	if _fl_near(side, FL_RALLY_M):
		fl_far[side] = -1
	elif fl_far[side] < 0:
		fl_far[side] = tick
	if fl_far[side] >= 0 and tick - fl_far[side] >= FL_RALLY_TICKS:
		# The pursuit broke off: the fleet rallies and holds; the trend starts afresh.
		fl_on[side] = 2
		fl_t[side] = tick
		fl_far[side] = -1
		stat_fl[1] += 1
		for k in FL_HIST:
			fl_hist[k] = int(now[0])
			fl_hist[FL_HIST + k] = int(now[1])
		for s in n_units:
			if u_side[s] == side and s_ffl[s] != 0:
				s_ffl[s] = 0
				if u_state[s] == S_SAIL and s_mode[s] == M_FLEE:
					s_mode[s] = M_FREE
					s_sail[s] = 0
		return
	if tick - fl_t[side] >= FL_CAP_TICKS and not _fl_near(side, FL_CLEAR_M):
		# Out of reach long enough: the fleet has withdrawn.
		stat_fl[2] += 1
		for s in n_units:
			if u_side[s] == side and u_state[s] == S_SAIL and s_grap[s] < 0 and s_mode[s] == M_FLEE:
				u_state[s] = S_FLED
				s_end_t[s] = tick
				stats["fled"] = int(stats["fled"]) + 1
				_event(EV_FLED, s, 0, -1, 0, 0)


## Where a ship fleeing with her fleet runs (the flight rule): of 16
## headings she can sail, the one whose way off the field she reaches
## soonest (her drive there, by her polar) before the nearest enemy can,
## with clear water all the way (else the longest run); a Skilled fleet that has the weather gauge keeps
## it (a heading to windward of the beam is preferred).
func _escape_goal(s: int) -> void:
	if ST.is_galley(s_type[s]) and _galley_flee(s):
		return
	var xm := s_x[s] / U
	var ym := s_y[s] / U
	var gauge := false
	if ai_skill[u_side[s]] == SKILLED:
		var near := -1
		var nd := 1 << 40
		for e in n_units:
			if u_side[e] != u_side[s] and u_state[e] == S_SAIL and s_lit[e] < 0:
				var d := FM.approx_len(s_x[e] - s_x[s], s_y[e] - s_y[s])
				if d < nd:
					nd = d
					near = e
		gauge = near >= 0 and _upwind_m(s, near) > 0
	var best_x := 0
	var best_y := 0
	var found := false
	var bv := -(1 << 40)
	for k in 16:
		var h := (k * 64) & FM.ANGLE_MASK
		var dr := drive(s, h)
		if dr <= 0:
			continue
		var c := FM.cos_a(h)
		var sn := FM.sin_a(h)
		var l := 1 << 20
		if c > 0:
			l = mini(l, (field_w + 60 - xm) * 4096 / c)
		elif c < 0:
			l = mini(l, (xm + 60) * 4096 / -c)
		if sn > 0:
			l = mini(l, (field_h + 60 - ym) * 4096 / sn)
		elif sn < 0:
			l = mini(l, (ym + 60) * 4096 / -sn)
		var ex := xm + ((c * l) >> 12)
		var ey := ym + ((sn * l) >> 12)
		var dmin := 1 << 30
		for e in n_units:
			if u_side[e] != u_side[s] and u_state[e] == S_SAIL and s_lit[e] < 0:
				dmin = mini(dmin, FM.approx_len(ex * U - s_x[e], ey * U - s_y[e]) / U)
		var v := dmin - l * 100 / dr
		# Land between her and the edge (a coast along it): no way out there.
		var run := _clear_run(s, h, maxi(l - 60, 40), true)
		if run < l - 60:
			v -= (1 << 20) - run
		if gauge and off_wind(h) < 256:
			v += 200
		if v > bv:
			bv = v
			best_x = ex
			best_y = ey
			found = true
	if not found:
		_flee_goal(s)
		return
	s_flee_x[s] = best_x * U
	s_flee_y[s] = best_y * U


# --------------------------------------------------------------------- AI ---

## The battle AI's decision for ship s (see the header).
func _think(s: int) -> void:
	if s_lit[s] < 0 and not ST.is_fire(s_type[s]):
		_think_douse(s)
	if s_grap[s] >= 0 or s_lit[s] >= 0:
		return
	if ST.is_fire(s_type[s]):
		_think_fire(s)
		return
	var crew_pct := s_crew[s] * 100 / maxi(s_crew0[s], 1)
	var hull_pct := s_hull[s] * 100 / s_hull0[s]
	if s_mode[s] == M_FLEE:
		return
	if fl_on[u_side[s]] == 2:
		s_mode[s] = M_FREE  # (rallied: hove to, holding, till the enemy comes; _fleet_judge)
		s_sail[s] = 0
		return
	var mine := power(u_side[s])
	var theirs := power(1 - u_side[s])
	var outgunned := theirs > mine * 3 and (hull_pct < 75 or crew_pct < 75)
	if ((hull_pct < 28 or crew_pct < 32 or s_mor[s] < 22) and theirs * 10 > mine * 12) or outgunned:
		s_mode[s] = M_FLEE
		s_flee_x[s] = -1
		s_sail[s] = 2
		return
	# Target: near and weak; keep the current one unless another is much better.
	# (R1) A light galley (no ram, no corvus) passes over ships of more than
	# twice her hull unless crippled or her side outnumbers theirs two to one.
	var galley := ST.is_galley(s_type[s])
	var light := galley and ST.stat(s_type[s], "ram") == 0 and ST.stat(s_type[s], "corvus") == 0
	var swarm := light and fighting(u_side[s]) >= 2 * fighting(1 - u_side[s])
	var best := -1
	var bs := 1 << 40
	var cur_score := 1 << 40
	for t in n_units:
		if u_side[t] == u_side[s] or u_state[t] != S_SAIL or s_lit[t] >= 0:
			continue
		var d := FM.approx_len(s_x[t] - s_x[s], s_y[t] - s_y[s]) / U
		var sc := d + s_hull[t] * 300 / s_hull0[t]
		if light:
			var crip_t := s_hull[t] * 100 / s_hull0[t] < 40
			if not crip_t and not swarm and s_hull0[t] > 2 * s_hull0[s]:
				continue
			if crip_t:
				sc -= 300
		if t == s_tgt[s]:
			cur_score = sc
		if sc < bs:
			bs = sc
			best = t
	if best < 0:
		s_mode[s] = M_FREE
		if light and _nearest_enemy(s) >= 0:
			# (R1) Nothing a light galley can take on: she keeps clear, off the field.
			s_mode[s] = M_FLEE
			s_flee_x[s] = -1
			s_sail[s] = 2
		return
	if s_tgt[s] >= 0 and cur_score < (1 << 40) and cur_score <= bs + 150:
		best = s_tgt[s]
	var t2 := best
	var dist := FM.approx_len(s_x[t2] - s_x[s], s_y[t2] - s_y[s]) / U
	# Board when much stronger in men (and close, or she is crippled).
	var my_b := s_crew[s] * s_bq[s] / 100 + s_troops[s] * 12 / 10
	var her_b := (s_crew[t2] * s_bq[t2] / 100 + s_troops[t2] * 12 / 10) * DECK_BONUS_PCT / 100
	# Friends already going for her board with us (a swarm of sloops).
	for f in n_units:
		if f != s and u_side[f] == u_side[s] and u_state[f] == S_SAIL and s_tgt[f] == t2 \
				and (s_mode[f] == M_BOARD or s_grap[f] == t2):
			my_b += s_crew[f] * s_bq[f] / 100 + s_troops[f] * 12 / 10
	var crippled := s_rig[t2] * 100 / s_rig0[t2] < 40 or s_spd[t2] < _vmax(t2) / 4
	var runs := s_mode[t2] == M_FLEE and s_spd[t2] * 10 >= s_spd[s] * 9
	if galley and ST.stat(s_type[s], "corvus") != 0 and not runs and tick - s_cv_t[s] >= CORVUS_COOL:
		my_b = 1 << 30  # (R1) the corvus: she closes and boards (not while it is hauled up after a repulse)
	if my_b * 100 > her_b * BOARD_PCT and not runs and (dist < 260 or crippled or ST.stat(s_type[s], "oars") != 0):
		if s_mode[s] != M_BOARD or s_tgt[s] != t2:
			s_mode[s] = M_BOARD
			s_tgt[s] = t2
			s_tack[s] = 0
			s_tdir[s] = 0
		return
	if s_mode[s] != M_ENGAGE or s_tgt[s] != t2:
		s_mode[s] = M_ENGAGE
		s_tgt[s] = t2
		s_tack[s] = 0
		s_tdir[s] = 0
	s_fire[s] = 1
	if galley:
		if s_sail[s] == 0:
			s_sail[s] = 1  # (the stroke is set by the run: _ram_heading)
		return
	# Full sail in the fight (battle sail only slowed her: flight rule pass); close to the enemy, battle
	# sail with land close to leeward or ahead.
	s_sail[s] = 1 if dist < 320 and (_lee_shore(s) >= 0 or _clear_run(s, heading(s), SEA_ROOM_M, true) < SEA_ROOM_M) else 2
	if dist > _want_range(s) + 220 and int(_closing(s, t2)[0]) == 2:
		s_sail[s] = 1 if _lee_shore(s) >= 0 else 0  # (hove to; under sail near a lee shore)
	# Shot: chain to cripple a ship it means to board, else round. (No grape: a broadside loaded with
	# grape cannot fire beyond its short range, and the probe's AI lost more with it at any range.)
	if s_bq[s] >= 110 and s_rig[t2] * 100 / s_rig0[t2] > 50 and my_b * 100 > her_b * 90 \
			and dist < shot_range(s, ST.SHOT_CHAIN) * 105 / 100:
		s_shot[s] = ST.SHOT_CHAIN
	else:
		s_shot[s] = ST.SHOT_ROUND


# ---------------------------------------------------------- galleys (R1) ---

## The row's guns, or for a galley what stands for them in the fleet's
## strength (power, the flight rule): her ram, marines and boarders.
func _guns_eq(s: int) -> int:
	var ty := s_type[s]
	if not ST.is_galley(ty):
		return ST.stat(ty, "guns")
	return (ST.stat(ty, "ram") + ST.stat(ty, "marines") * 2 + ST.stat(ty, "crew") * ST.stat(ty, "board") / 100) / 20


## The dash meter of every galley: it drains a tenth of a second a tick at
## ramming speed and refills DASH_FILL a second off it; empty, she drops to cruise.
func _stroke() -> void:
	for s in n_units:
		var dm := ST.stat(s_type[s], "dash") * 10
		if dm <= 0:
			continue
		if s_sail[s] == 2 and s_dash[s] > 0 and u_state[s] == S_SAIL and s_grap[s] < 0 and tick - s_ram_t[s] >= RAM_BACK:
			s_dash[s] -= 1
		elif tick % 10 == 0:
			s_dash[s] = mini(s_dash[s] + DASH_FILL, dm)
		if s_dash[s] == 0 and s_sail[s] == 2:
			s_sail[s] = 1  # (the rowers are spent)


## The stroke of a galley on a run: ramming speed when `close` and the
## meter allows (a run under way, or a meter above a third), else cruise.
func _run_stroke(s: int, close: bool) -> void:
	var dm := ST.stat(s_type[s], "dash") * 10
	if close and s_dash[s] > 0 and (s_sail[s] == 2 or s_dash[s] * 3 > dm):
		s_sail[s] = 2
	else:
		s_sail[s] = 1


## Where ship t will be when ship s (d metres off) reaches her: [x, y].
func _lead_point(s: int, t: int, d: int) -> Array:
	var cruise := maxi(_vmax(s) * CRUISE_PCT / 100, 1)
	var lead := clampi(d * U / maxi(s_spd[s], cruise), 0, 80)
	var th := heading(t)
	return [s_x[t] + ((FM.cos_a(th) * s_spd[t]) >> 12) * lead, s_y[t] + ((FM.sin_a(th) * s_spd[t]) >> 12) * lead]


## A ram ship engaging t: set up SETUP_M off the beam of t she is on, then
## (fresh, the ram ready) run in at a right angle to her keel, dashing the
## last RUN_M m; faster than her, for her stern quarter (the diekplous).
func _ram_heading(s: int, t: int) -> int:
	var d := FM.approx_len(s_x[t] - s_x[s], s_y[t] - s_y[s]) / U
	var lp := _lead_point(s, t, d)
	var px: int = lp[0]
	var py: int = lp[1]
	var th := heading(t)
	var ct := FM.cos_a(th)
	var st := FM.sin_a(th)
	var rx := (s_x[s] - px) / U
	var ry := (s_y[s] - py) / U
	var along := (rx * ct + ry * st) >> 12
	var across := (ry * ct - rx * st) >> 12
	var sg := 1 if across >= 0 else -1
	var acr := absi(across)
	var half := ST.stat(s_type[t], "len") / 2
	var aim := 0
	if s_spd[t] > 100 and s_spd[t] * 10 < _vmax(s) * 9:
		aim = -half / 2  # (the diekplous: for her stern quarter)
	var ax := px + ((ct * aim) >> 12) * U
	var ay := py + ((st * aim) >> 12) * U
	var fresh := s_dash[s] > 0 and (s_sail[s] == 2 or s_dash[s] * 3 > ST.stat(s_type[s], "dash") * 10)
	if tick - s_ram_t[s] >= RAM_COOL and fresh and acr >= 10 and absi(along - aim) * 10 <= acr * 7 + half * 10 \
			and d < SETUP_M * 2:
		_run_stroke(s, d - ST.stat(s_type[s], "len") / 2 <= RUN_M)
		return FM.atan2_a(ay - s_y[s], ax - s_x[s])
	s_sail[s] = 1
	var gx := clampi(ax + ((-st * sg * SETUP_M) >> 12) * U, EDGE_M * U, (field_w - EDGE_M) * U)
	var gy := clampi(ay + ((ct * sg * SETUP_M) >> 12) * U, EDGE_M * U, (field_h - EDGE_M) * U)
	return FM.atan2_a(gy - s_y[s], gx - s_x[s])


func _nearest_enemy(s: int) -> int:
	var best := -1
	var bd := 1 << 40
	for e in n_units:
		if u_side[e] != u_side[s] and u_state[e] == S_SAIL and s_lit[e] < 0:
			var d := FM.approx_len(s_x[e] - s_x[s], s_y[e] - s_y[s])
			if d < bd:
				bd = d
				best = e
	return best


## A galley flees straight away from the nearest enemy, to the edge 60 m
## past it (false: no enemy, the usual goal).
func _galley_flee(s: int) -> bool:
	var e := _nearest_enemy(s)
	if e < 0:
		return false
	var h := FM.atan2_a(s_y[s] - s_y[e], s_x[s] - s_x[e])
	var xm := s_x[s] / U
	var ym := s_y[s] / U
	var c := FM.cos_a(h)
	var sn := FM.sin_a(h)
	var l := 1 << 20
	if c > 0:
		l = mini(l, (field_w + 60 - xm) * 4096 / c)
	elif c < 0:
		l = mini(l, (xm + 60) * 4096 / -c)
	if sn > 0:
		l = mini(l, (field_h + 60 - ym) * 4096 / sn)
	elif sn < 0:
		l = mini(l, (ym + 60) * 4096 / -sn)
	s_flee_x[s] = (xm + ((c * l) >> 12)) * U
	s_flee_y[s] = (ym + ((sn * l) >> 12)) * U
	return true


## Rams (in _contacts): a ram ship (the ram ready, not grappled) whose bow
## lies inside an enemy's hull, that hull in her bow cone, closing on it at
## RAM_MIN or more, strikes (_ram); the first such enemy in index order.
## The blows are found first and struck after, so two ships ramming each
## other in one tick both strike (no edge to the lower index); bow to bow
## is one blow to both.
func _rams() -> void:
	var hits := PackedInt32Array()
	for a in n_units:
		var ra := ST.stat(s_type[a], "ram")
		if ra <= 0 or u_state[a] != S_SAIL or s_grap[a] >= 0 or tick - s_ram_t[a] < RAM_COOL:
			continue
		var ha := heading(a)
		var hl := ST.stat(s_type[a], "len") * U / 2
		var px := s_x[a] + ((FM.cos_a(ha) * (hl >> 6)) >> 6)
		var py := s_y[a] + ((FM.sin_a(ha) * (hl >> 6)) >> 6)
		for b in n_units:
			if b == a or u_side[b] == u_side[a] or not (u_state[b] == S_SAIL or u_state[b] == S_STRUCK) or s_lit[b] >= 0:
				continue
			var tb := s_type[b]
			var half_b := ST.stat(tb, "len") * U / 2
			var rx := px - s_x[b]
			var ry := py - s_y[b]
			if absi(rx) > half_b + 4 * U or absi(ry) > half_b + 4 * U:
				continue
			var hb := heading(b)
			var cb := FM.cos_a(hb)
			var sb := FM.sin_a(hb)
			var along := (rx * cb + ry * sb) >> 12
			var across := (ry * cb - rx * sb) >> 12
			if absi(along) > half_b + 2 * U or absi(across) > ST.stat(tb, "beam") * U / 2 + 2 * U:
				continue
			# Her keel abreast of the bow inside the rammer's bow cone.
			var kl := clampi(along, -half_b, half_b)
			var kx := s_x[b] + ((cb * kl) >> 12)
			var ky := s_y[b] + ((sb * kl) >> 12)
			if absi(FM.angle_diff(ha, FM.atan2_a(ky - s_y[a], kx - s_x[a]))) > RAM_CONE:
				continue
			var closing := s_spd[a] - ((s_spd[b] * FM.cos_a(hb - ha)) >> 12)
			if closing < RAM_MIN:
				continue
			hits.append_array([a, b, closing])
			break
	for i in range(0, hits.size(), 3):
		var a2 := hits[i]
		var b2 := hits[i + 1]
		if s_ram_t[a2] == tick or u_state[b2] == S_SUNK:
			continue  # (bow to bow: the other's blow was both; she went down to another blow)
		_ram(a2, b2, hits[i + 2])


## Ship a rams ship b closing at `closing`: ram x closing / RAM_DIV hull,
## doubled on her beam; bow to bow (b's heading within RAM_BEAM of the
## reverse of a's and a in b's bow cone) both take half of the heavier ram's
## blow. The blow halves b's way; the rammer (both, bow to bow, when b has a
## ram) backs water.
func _ram(a: int, b: int, closing: int) -> void:
	var ha := heading(a)
	var hb := heading(b)
	var ra := ST.stat(s_type[a], "ram")
	var rb := ST.stat(s_type[b], "ram")
	var kind := 0
	var dmg := ra * closing / RAM_DIV
	var bow := absi(FM.angle_diff(ha, (hb + FM.ANGLE_HALF) & FM.ANGLE_MASK)) < RAM_BEAM \
			and absi(FM.angle_diff(hb, FM.atan2_a(s_y[a] - s_y[b], s_x[a] - s_x[b]))) <= RAM_CONE
	if bow:
		kind = 2
		dmg = maxi(ra, rb) * closing / (RAM_DIV * 2)
	elif absi(absi(FM.angle_diff(ha, hb)) - FM.ANGLE_QUARTER) <= RAM_BEAM:
		kind = 1
		dmg *= 2
	dmg = maxi(dmg, 1)
	s_ram_t[a] = tick
	s_spd[a] = 0
	s_spd[b] = s_spd[b] / 2  # (the blow checks her way)
	if bow:
		s_spd[b] = 0
		if rb > 0:
			s_ram_t[b] = tick
	stats["rams"] = int(stats.get("rams", 0)) + 1
	if kind == 1:
		stats["rams_beam"] = int(stats.get("rams_beam", 0)) + 1
	elif kind == 2:
		stats["rams_bow"] = int(stats.get("rams_bow", 0)) + 1
	_event(EV_RAM, a, kind, b, dmg, closing)
	_ram_hit(b, dmg)
	if bow:
		_ram_hit(a, dmg)


func _ram_hit(t: int, dmg: int) -> void:
	if u_state[t] == S_SUNK:
		return
	var h0 := s_hull[t]
	s_hull[t] = maxi(s_hull[t] - dmg, 0)
	s_mor[t] -= (h0 - s_hull[t]) * 100 / s_hull0[t] / 2 + 2
	s_hit_t[t] = tick
	if s_hull[t] == 0:
		_sink(t)


## The corvus (in _contacts, after the boarders): a corvus ship within
## grapple reach of an enemy (firing at will, or her ordered target) at a
## relative speed up to CORVUS_REL drops it and boards at once.
func _corvus() -> void:
	for s in n_units:
		if ST.stat(s_type[s], "corvus") == 0 or u_state[s] != S_SAIL or s_grap[s] >= 0 or s_lit[s] >= 0 \
				or tick - s_cv_t[s] < CORVUS_COOL:
			continue
		for t in n_units:
			if u_side[t] == u_side[s] or not (u_state[t] == S_SAIL or u_state[t] == S_STRUCK) or s_grap[t] >= 0 \
					or s_lit[t] >= 0 or ST.is_fire(s_type[t]):
				continue
			if s_fire[s] == 0 and t != s_tgt[s]:
				continue
			var reach := ((ST.stat(s_type[s], "len") + ST.stat(s_type[t], "len")) * 40 / 100 + 8) * U
			var dx := s_x[t] - s_x[s]
			var dy := s_y[t] - s_y[s]
			if absi(dx) > reach or absi(dy) > reach or FM.approx_len(dx, dy) > reach:
				continue
			var vx := ((FM.cos_a(heading(s)) * s_spd[s]) >> 12) - ((FM.cos_a(heading(t)) * s_spd[t]) >> 12)
			var vy := ((FM.sin_a(heading(s)) * s_spd[s]) >> 12) - ((FM.sin_a(heading(t)) * s_spd[t]) >> 12)
			if FM.approx_len(vx, vy) > CORVUS_REL:
				continue
			stats["corvus"] = int(stats.get("corvus", 0)) + 1
			_grapple(s, t, 1)
			break


## Shot % of ship s's troops (their kits by share; no kit: ST.DECK_TROOPS).
func _troop_shot(s: int) -> int:
	var sum := 0
	var acc := 0
	for k in TK_MAX:
		var b := (s * TK_MAX + k) * TKP
		if s_tkp[b] > 0 and s_tkp[b + 4] > 0:
			sum += s_tkp[b]
			acc += s_tkp[b] * s_tkp[b + 3]
		elif s_tkp[b] > 0:
			sum += s_tkp[b]
	if sum == 0:
		return int(ST.DECK_TROOPS["shot"])
	return acc / sum


## Galleys' missiles before contact: every `reload` seconds her troops (the
## marines) throw at the nearest enemy within MSL_M (firing at will, or her
## ordered target), killing crew only: troops x shot % x DECK_SHOT_PM / 1000.
func _missiles() -> void:
	if decided_tick >= 0:
		return
	for s in n_units:
		if not ST.is_galley(s_type[s]) or u_state[s] != S_SAIL or s_grap[s] >= 0:
			continue
		if s_msl[s] > 0:
			s_msl[s] -= 1
			continue
		if s_troops[s] <= 0:
			continue
		var best := -1
		var bd := MSL_M * U + 1
		for t in n_units:
			if u_side[t] == u_side[s] or u_state[t] != S_SAIL or s_lit[t] >= 0 or s_grap[t] >= 0:
				continue
			if s_fire[s] == 0 and t != s_tgt[s]:
				continue
			var dx := s_x[t] - s_x[s]
			var dy := s_y[t] - s_y[s]
			if absi(dx) > MSL_M * U or absi(dy) > MSL_M * U:
				continue
			var d := FM.approx_len(dx, dy)
			if d < bd:
				bd = d
				best = t
		if best < 0:
			continue
		var kills := mini((s_troops[s] * _troop_shot(s) * DECK_SHOT_PM + _roll(1000)) / 1000, s_crew[best])
		s_crew[best] -= kills
		s_kills[s] += kills
		if kills > 0:
			s_mor[best] -= kills * 150 / maxi(s_crew0[best], 1) + 1
			s_hit_t[best] = tick
		s_msl[s] = ST.stat(s_type[s], "reload") * 10
		stats["missiles"] = int(stats.get("missiles", 0)) + 1
		_event(EV_MISSILE, s, 0, best, kills, 0)


## The battle AI's Douse (2026-10-22): with a fire aboard and no enemy about
## to board her (grappled, or one within DOUSE_BOARD_M sailing to board her),
## Easy douses at once; Average when the fire is outgrowing the crew (its
## mean growth over her fight at the current crew share); Skilled when it is
## outgrowing them and no enemy is in either broadside's arc and range, or
## the fire is past 3 / 5 of MAG_LV whatever bears. A boarder coming: back
## to the guns and the deck. Off by itself when the fire is out.
func _think_douse(s: int) -> void:
	if s_burn[s] == 0:
		return
	if _board_threat(s):
		s_douse[s] = 0
		return
	if s_douse[s] != 0:
		return
	var sk := ai_skill[u_side[s]]
	var losing := (FIRE_GROW + FIRE_GROW_ROLL / 2) > fire_fight(s)
	var go := sk == EASY or losing
	if sk == SKILLED and losing and s_burn[s] <= MAG_LV * 3 / 5 and (_pick_target(s, 0) >= 0 or _pick_target(s, 1) >= 0):
		go = false  # (Skilled: the guns first while the magazine is safe)
	if go:
		_set_douse(s, 1)


## An enemy is at ship s: grappled, or one within DOUSE_BOARD_M sailing to board her.
func _board_threat(s: int) -> bool:
	if s_grap[s] >= 0:
		return true
	for e in n_units:
		if u_side[e] == u_side[s] or u_state[e] != S_SAIL or s_mode[e] != M_BOARD or s_tgt[e] != s:
			continue
		var dx := s_x[e] - s_x[s]
		var dy := s_y[e] - s_y[s]
		if absi(dx) < DOUSE_BOARD_M * U and absi(dy) < DOUSE_BOARD_M * U and FM.approx_len(dx, dy) < DOUSE_BOARD_M * U:
			return true
	return false


## The battle AI's fire ship: at the biggest enemy when the wind serves (her
## mark lies FS_SERVES or more off the wind, within reach), else up to
## windward of it, waiting.
func _think_fire(s: int) -> void:
	var best := -1
	var bv := -1
	for t in n_units:
		if u_side[t] == u_side[s] or u_state[t] != S_SAIL or s_lit[t] >= 0 or ST.is_fire(s_type[t]):
			continue
		var v := ST.stat(s_type[t], "guns") * 10 + s_hull[t] / 10
		if v > bv:
			bv = v
			best = t
	if best < 0:
		s_mode[s] = M_FREE
		s_tgt[s] = -1
		return
	var dx := s_x[best] - s_x[s]
	var dy := s_y[best] - s_y[s]
	var d := FM.approx_len(dx, dy) / U
	var serves := off_wind(FM.atan2_a(dy, dx)) >= FS_SERVES
	if s_mode[s] == M_FIRE and s_tgt[s] == best and (serves or d < FS_LIGHT_M * 2):
		return
	if serves and d < 1200:
		s_mode[s] = M_FIRE
		s_tgt[s] = best
		s_sail[s] = 2
		s_tack[s] = 0
		s_tdir[s] = 0
		return
	# Wait up to windward of her for the wind to serve.
	var gx := clampi(s_x[best] + ((FM.cos_a(w_from) * 420) >> 12) * U, (EDGE_M + 40) * U, (field_w - EDGE_M - 40) * U)
	var gy := clampi(s_y[best] + ((FM.sin_a(w_from) * 420) >> 12) * U, (EDGE_M + 40) * U, (field_h - EDGE_M - 40) * U)
	if s_mode[s] != M_GOTO:
		s_tack[s] = 0
		s_tdir[s] = 0
	s_mode[s] = M_GOTO
	s_tgt[s] = best
	s_tx[s] = gx
	s_ty[s] = gy
	s_sail[s] = 1 if d < 700 else 2


# ----------------------------------------------------------------- events ---

func _event(k: int, a: int, b: int, c: int, d: int, e: int) -> void:
	var i := ev_n % EV_CAP
	ev_t[i] = tick
	ev_k[i] = k
	ev_a[i] = a
	ev_b[i] = b
	ev_c[i] = c
	ev_d[i] = d
	ev_e[i] = e
	ev_n += 1


# ----------------------------------------------------------------- result ---

func is_decided() -> bool:
	return decided_tick >= 0


func result() -> Dictionary:
	var units: Array = []
	var sides: Array = []
	for sd in 2:
		sides.append({"side": sd, "ships": 0, "fighting": 0, "sunk": 0, "taken": 0, "struck": 0, "fled": 0,
			"crew0": 0, "crew": 0, "kills": 0})
	for s in n_units:
		var r := {"unit": s, "side": u_side[s], "ship": str(ST.row(s_type[s])["key"]), "hull": s_hull[s],
			"hull0": s_hull0[s], "crew": s_crew[s], "crew0": s_crew0[s], "rig": s_rig[s], "rig0": s_rig0[s],
			"troops": s_troops[s], "state": u_state[s], "by": s_by[s], "kills": s_kills[s], "blown": s_blown[s],
			"lit": 1 if s_lit[s] >= 0 else 0}
		units.append(r)
		var t: Dictionary = sides[u_side[s]]
		t["ships"] = int(t["ships"]) + 1
		t["crew0"] = int(t["crew0"]) + s_crew0[s]
		t["crew"] = int(t["crew"]) + s_crew[s]
		t["kills"] = int(t["kills"]) + s_kills[s]
		match u_state[s]:
			S_SAIL:
				t["fighting"] = int(t["fighting"]) + 1
			S_SUNK:
				t["sunk"] = int(t["sunk"]) + 1
			S_TAKEN:
				t["taken"] = int(t["taken"]) + 1
			S_STRUCK:
				t["struck"] = int(t["struck"]) + 1
			S_FLED:
				t["fled"] = int(t["fled"]) + 1
	return {"sea": 1, "winner": winner, "decided_tick": decided_tick, "ended": ended, "tick": tick, "units": units,
		"sides": sides}


# --------------------------------------------------------------- snapshot ---

const _SNAP_SKIP := {"g": true, "g_w": true, "g_h": true}
const _SNAP_MAGIC := 0x31414553  # "SEA1"


func snapshot() -> PackedByteArray:
	var d := {}
	for p in get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var nm: String = p["name"]
		if _SNAP_SKIP.has(nm):
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


func restore(blob: PackedByteArray) -> bool:
	if blob.size() < 8 or blob.decode_u32(0) != _SNAP_MAGIC:
		return false
	var raw_size := blob.decode_u32(4)
	if raw_size <= 0 or raw_size > 64 << 20:
		return false
	var raw := blob.slice(8).decompress(raw_size, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != raw_size:
		return false
	var v = bytes_to_var(raw)
	if not (v is Dictionary):
		return false
	var d: Dictionary = v
	for k in ["n_units", "ter_hash", "field_w", "field_h", "seed_value"]:
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
	return true


## 32-bit hash of the whole sea battle state.
func state_hash() -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	var head := PackedInt64Array([tick, rng_state, winner, decided_tick, ended, n_units, w_base, w_from, w_goal,
		w_str, ter_hash, time_limit, field_w, field_h, deck_on])
	ctx.update(head.to_byte_array())
	for nm in SHIP_ARRAYS:
		ctx.update((get(nm) as PackedInt32Array).to_byte_array())
	for nm in DECK2_ARRAYS:
		ctx.update((get(nm) as PackedInt32Array).to_byte_array())
	for nm in FIG_ARRAYS:
		ctx.update((get(nm) as PackedInt32Array).to_byte_array())
	ctx.update(s_tkp.to_byte_array())
	ctx.update(s_ld.to_byte_array())
	ctx.update(s_rl.to_byte_array())
	ctx.update(ai_sides.to_byte_array())
	ctx.update(ai_skill.to_byte_array())
	ctx.update(fl_on.to_byte_array())
	ctx.update(fl_t.to_byte_array())
	ctx.update(fl_far.to_byte_array())
	ctx.update(fl_hist.to_byte_array())
	if gal_on != 0:
		for nm in GAL_ARRAYS:
			ctx.update((get(nm) as PackedInt32Array).to_byte_array())
	return ctx.finish().decode_u32(0)
