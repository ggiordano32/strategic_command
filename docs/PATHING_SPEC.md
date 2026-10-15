# Town and battlefield pathing, pass 2: spec (draft for review, 2026-10-15)

Read-only review of the working tree (HEAD b82cd3b plus the uncommitted cover / LOS
slice 2b). Probes are in `scratchpad/pathspec/` (`jitter.gd`, `trace.gd`, `clear.gd`,
`cells.gd`, outputs in `out/`). Every number below comes from AI vs AI runs, sim seed 7. Line numbers drift: the cover agent is editing `battle_sim.gd` live.

## 1. What was measured

**Jitter metric** (`jitter.gd`). For each man, in each 2 s window: path = the sum of
his steps, net = his displacement. A man-window counts as *jittering* when
path >= 3 m and net < path / 3. *rev/step* is the share of steps that reverse the
previous step. Results are grouped by unit state (rout / move / fight / idle) and by
place (wall, stair, town, near an obstacle, field).

| category | jitter | rev/step | where |
|---|---|---|---|
| **rout / stair 1** (routers coming down off the wall) | **78-80 %** | **79-82 %** | siege_town, siege_city |
| rout / town | 0.1-22 % | up to 29 % | town 22 % (gate huddle) |
| fight / near landform | **18.7 %** | 7.5 % | bench_4000_hills |
| fight / town | 1.7-6.7 % | 5-10 % | punic 6.7 % |
| move / town | 0.7-6.7 % | 1-3 % | village 6.7 % |
| idle / near landform | 3.2 % | **30 %** | battle_2000 (a rallied unit cut by a cliff) |
| move / field, rout / field | 0-1 % | < 1.5 % | baseline |

**Routers that stay put.** A routing unit counts as stationary when its centroid
moves less than 3 m in 10 s. Share of routing unit-seconds spent stationary: polis
38 %, punic 33 %, town 29 %, city 20 %, castrum 9 %, village / hill / oppidum about
1 % (no ROUT_INWARD gates or no final rout). Of the stationary cases: 74 of 98 were
pinned against a house mid-run with the unit strung out 40-210 m, 23 were at a shut
gate's inner point, and 1 was on a stair.

**Blind spot.** The existing no-progress counter (`u_stuck`, landforms harness) does
not count routing units at all (`_stuck_tick` is not called for them). The harness
therefore reports "stuck max 9-37 s, >30 s: 0-1" on exactly the runs above.

**Clearance** (`clear.gd`: men of ready ground units within 6 m of a building,
against the polygons the view draws). Share of men standing inside the drawn
footprint: polis 7.6 %, village 1.9 %, town 1.2 %. Share within 0.3 m of an edge:
1.3-2.0 %. Share within 1 m including inside: polis 16 %, town 7 %. Units that are
moving are the worst: town 3.1 % inside plus 3.9 % within 0.3 m.

## 2. Root causes (file:line refer to `sim/battle_sim.gd` unless noted)

**R1. One flee vector for the whole unit, aimed from its centroid** (the cause of
the visible shaking).
- `_flee_step` (4973-5018) sets `u_ax = u_cx` and computes one unit vector toward
  `_path_point(...)`, or toward the stair foot when `u_stair == 1` (4974-4982).
- Every man then steps along that vector, plus a fixed per-man skew, at 7/8 of the
  run speed (routing loop, 7313-7350).
- *Arrival flip:* when the target point is the stair foot (`stair_pt(...,2)`) or a
  shut gate's inside (`_rout_gate`, 5021), the centroid reaches it and the vector
  flips sign every tick. All the men swing ±0.3-0.4 m in lockstep.
  - Trace, siege_town u14: centroid (278.0, 234.1) ↔ (278.0, 233.8), flee
    (-1061, 3811) ↔ (780, -3928), for 40 s until `STAIR_MAX` (377, 400 ticks)
    ends the stair move.
  - Trace, u17: 60 men at the gate, flipping every tick for the rest of the
    battle.
- *Split units:* men round a corner from the centroid walk straight into the house
  (spread 40-210 m, centroid frozen).

**R2. A router on a stair move ignores the per-man stair trail.** Ready units send
each man along `_stair_leave` / `_stair_goal` (7408, 7871). The routing loop does
not. Men still on the walkway step along the unit vector. The walkway is inside
their mask (`_mask_of` 3563: WALL|GROUND for stair 1), so they never call `_slide`
and so never use its trail. They bob on the walk until `STAIR_MAX`. Six of 22 men
were still up after 30 s.

**R3. Routers slide without memory.** `_slide` drops the trail for routers
(`cnt_n = 0`, 3304-3305) and tries only the two axes.
- A flee vector square onto a face (siege_castrum: flee (0, 4228) into a tower
  beside the gate passage) gives zero motion forever. Men stood at x = 270 and 280
  of a passage open only at 274-278.
- A diagonal into a concave corner gives a 2-cycle.
- The same rule causes `idle / near landform` rev 30 %: men cut off behind a cliff
  oscillate 0.4 m a tick against it (battle_2000 u24, just rallied).

**R4. Final routs have no end state inside a town.** After the plaza falls,
`_update_capture` (4935-4939) routs every defender with `u_routs = MAX_ROUTS + 1`
(no rally). ROUT_INWARD sends them to a shut gate they can never pass. So 13-60 men
at morale 1000 vibrate at the gate until the battle ends. Attackers inside a town
whose ladders are gone have no exit at all: `_plan_path` with `ba < 0` falls back
to "straight on" (3749) and they push into the town wall.

**R5. Rally re-anchors at the centroid.** `_rally` (11079) sets `u_ax = u_cx`. For a
strung-out unit that point can lie behind a cliff or house from half the men. On
landform-only maps the stuck counter and `_regroup` do not run for an idle unit,
so nothing releases them (the u24 case).

**R6. Buildings are rasterised by cell centre.** `_set_rect` (mapgen 2734) and the
quad / round `_poly_cells` (mapgen ~2195, 2232) mark a 2 m cell only if its centre
is inside the polygon. The drawn house therefore overhangs its blocked cells by up
to about 1 m, more on rotated quads (the polis). The men's only test is "cell
passable", so they stand inside the drawn walls. Nothing keeps a body radius off a
face.

**R7. Separation only for fighters and chargers** (7792-7812, 7852-7870).
- Slot-following men, both the fast path (7375-7450) and the non-fighting men of a
  fighting unit, never push apart.
- In a street fight a unit's rear ranks stack onto each other and onto friends
  (`fight/town` rev 7-10 %). `_cap_lead` / `PLACE_SIDE` drag them back.
- In a squeezed street the target search (`_find_target_obs`) and the place caps
  fight each other every few ticks.
- `fight / near landform` 18.7 % comes from the same tug-of-war against a rock:
  find target → slide → lose reach (`_reach_ok`) → search again (7700-7711).

**R8. Weaknesses that will hurt dense West towns.**
- Paths are planned from the anchor only. Men follow places, so in a long street
  the column is right but at corners the rear cuts the corner into the house.
- The fast path ignores `_u_obs` except for the cell test.
- `_squeeze` (3954) samples width in 2 m steps from the anchor only.
- In a city every house is `COV_NONE` (`_cover_cell` 12674-12677:
  `if city_on != 0: return COV_NONE` before the building case). Today there is no
  cover in towns at all.

## 3. Fixes for jitter (phase A)

**A1. Per-man flee on an exit field.**
- Static-per-generation integer distance fields over the 2 m nav grid, Dijkstra
  with costs 10 / 14 (8 neighbours, no corner cutting), PackedInt32Array:
  - `xf_s0` and `xf_s1`: distance to the side's exit cells (own edge rows; the
    coast rule's land edges).
  - `xf_g[g]`, one per outer gate: distance to that gate's inner mouth (refuge).
- A router at cell c steps toward the lowest neighbour (fixed neighbour order, ties
  to the lower index). Keep the existing per-man skew at 1/4 of today's.
- The step is cut by the 2 m nav test exactly as now. The men walk *down* the
  field, so no flip and no square-on stall are possible.
- Unit-level `u_flee_x/y` stays only as the facing for the view and for land_only
  / open maps, which do not change (no field built: `obs_on == 0` or
  `land_only != 0` keep today's code).
- Gate changes bump `nav_epoch` and start a rebuild, budgeted at `XF_CELLS` 6,000
  cells a tick. The new field takes over at a fixed tick (`xf_t0 + XF_TICKS`, with
  `xf_t0` hashed) so peers agree.
- The fields are left out of snapshots and rebuilt synchronously by `restore()`,
  both the live and the pending generation (pure functions of the static map and
  the gate states).

**A2. Router stair descent per man.** In the routing loop, when `u_stair == 1`,
each man still on the walkway or in the stair follows `_stair_goal`, the same call
the ready path uses. Once on the ground he uses A1. `_stair_check` stays as it is.
This removes the 40 s `STAIR_MAX` waits.

**A3. Huddle (an end state for routers who cannot leave).**
- A router whose field value is INF (no exit: attackers inside, ladders gone,
  gates shut) or below `HUDDLE_R` 6 m from a refuge enters huddle (`u_hud`,
  hashed).
- Its places are flowed round the refuge point with `_flow_slots` (125 % density,
  a disc, front toward the nearest enemy) and its men walk to them by slot
  following. They then stand still: `S_ROUTING`, not drawn running, no separation
  needed.
- Huddled men still count as routing (no fighting). Two exits from huddle:
  - Surrender: a final router (`u_routs > MAX_ROUTS`) with a ready enemy within
    `SURR_R` 15 m is removed as captured (new `GONE_SURRENDER` or the existing
    capture path; credit kills as captures).
  - Rally: a router that can still rally does so through the existing rule.
- A trapped attacker with no exit and no refuge huddles at the cell of its field
  basin nearest to it (the lowest-distance-to-enemy-free place: the centroid's
  reach piece, then the man nearest the centroid).

**A4. Rally and regroup anchor on a reachable man.** `_rally` uses `_regroup`'s
choice (the man nearest the centroid on the most-populated reach piece), then flows
the unit's places. The same goes for a charge's re-form and the `_start_rout` →
rally path.

**A5. Slide with memory for everyone.** When `_slide` returns zero motion two ticks
running, the man takes the wall-follow direction (the field gradient where one
exists, else the trail, else +90° of the wanted step, the side fixed by
`i & 1`). He keeps it for `SLIDE_HOLD` 5 ticks (scratch per soldier, rebuilt on
restore as 0: it only shortens a hold, so the rule must not depend on it). Prefer
a hashed `PackedByteArray` `s_wf`, which is cheap and safe.

**A6. Separation for slot-followers in obstacle units.** For units with
`_u_obs != 0`, run the existing every-other-tick separation (sep 0.7 m) on
non-fighting men as well, at half push. The cost is bounded by `checked < 10`.
Field / open units keep the fast path untouched (golden digests unchanged).

**A7. Count routers in the metrics.** The diagnostic `stat_rout_still`
(router-ticks with centroid < 3 m in 10 s while not huddled) is not hashed. Add the
jitter metric of section 1 to a new harness, `tests/pathing_probe.gd`.

## 4. Building clearance (phase B)

- **B1. A clearance field.** At setup (static, skipped in snapshots), a 1 m grid
  `clr` (PackedByteArray) of the distance in decimetres, capped at 25, from each
  1 m cell centre to the nearest *drawn* building / wall / rock face. It is
  computed from the polygons the view draws: a chamfer pass over a 1 m
  rasterisation that marks a cell when any part of it is inside, then two passes.
  A second byte gives the outward direction (8-way code). For a 600 x 600 m map
  that is 360 KB; it is built once.
- **B2. Rules.**
  - (a) A man whose step ends with `clr < CLR_MIN` 0.5 m is pushed out along the
    stored direction by the shortfall. It is integer and applied after the nav
    test (one byte read per moving man near obstacles).
  - (b) Places: `_compute_offsets` / `_flow_slots` treat a 1 m cell with
    `clr < CLR_PLACE` 0.8 m as cut, so a formation lays itself out off the faces.
  - (c) `_squeeze` measures width from `clr` along the cross line (1 m
    resolution, drawn faces), less 2 x `CLR_MIN`.
  - (d) The street graph's edge cost gets `+ (3 m - min clr along it)` x 4. Lanes
    narrower than 3 m clear cost more, so columns keep to streets.
- **B3. Why a soft field and not hard occupancy.** Making the 2 m cells
  conservative (block on any overlap) would close 4 m lanes entirely, move every
  settlement golden and every street graph, and still leave 2 m quantisation. The
  soft field keeps the nav, graph and goldens of the 2 m grid. Only settlement
  battle trajectories move (no pinned golden: check `--only=flow` / `stairs` /
  `cover` and the fair-sieges set).
- **Target:** inside the drawn footprint < 0.2 % of samples, within 0.3 m < 0.5 %
  (today 1.2-7.6 % and 1.3-2.0 %).

## 5. Street fighting with cover (phase C, after slice 2b lands)

**C1. Cover points** (static, built at setup from `map_info.city` and works).
- For each building polygon:
  - each convex corner gives two points, 0.9 m out from each face along the
    corner's bisector. The kind is `CP_CORNER`, for 2 men, and the point protects
    the arc of the two faces (stored as the obstacle's direction, ±70°);
  - each street-facing face longer than 6 m gives a `CP_DOOR` at its middle,
    0.8 m out, for 2 men, protecting ±80° behind the face normal.
- Walls, palisades and field works give `CP_WALL` every 1.4 m along their inner
  side, one man each.
- West props (C4) give `CP_PROP` round carts, barrels and wells, 2-3 men.
- Keep a point only if `clr >= CLR_PLACE` and its 2 m cell is open ground.
- Arrays: `cp_x`, `cp_y`, `cp_dir`, `cp_arc`, `cp_cap`, `cp_kind`, plus a 16 m
  bucket CSR (`cp_b0`, `cp_ix`). Static, skipped in snapshots, deterministic
  order: building order, then corner order.
- **Claims** (hashed): `cp_u` (unit or -1) and `cp_n` (men). Expected 4-10
  thousand points on a big West town, 2 x 4 bytes each.

**C2. Claiming and placing men.**
- A unit in the *Take cover* stance, halted or arrived (not fighting hand to hand),
  runs `_cover_slots(u)` at most every `FLOW_EVERY` ticks. It writes its places
  into the existing `off_x` / `off_y` (the flowed-places mechanism, so following,
  `PLACE_LEAD` and caps all work unchanged).
- Candidates are points within `CP_R` of the anchor: 18 m for cover-trait units,
  10 m for others. They must be unclaimed, or claimed by this unit.
- A point is useful when its protected arc contains the bearing of the threat: the
  engaged target, else the nearest seen enemy unit, else the AI plan's front.
- Score = distance from the man's current place + 4 m if the point has no sight
  line to the threat (it must be able to shoot). Assign greedily, men nearest
  first, in slot order on ties (the ladder lesson: nearest-first, not slot-first).
- Men with no point fill places 1.5 m behind claimed points, in the lee
  (`clr`-checked), or a loose block behind.
- Claims are released on move orders, routs and death (`cp_n` is decremented in
  `_remove`).

**C3. Firing from cover.**
- `_cover_cell` returns `COV_HOUSE` for buildings in cities too: remove the
  `city_on` early-out for `C_BUILDING`, keep the wall rule.
- A man at a claimed point gets that point's cover against shots from inside its
  arc: `COV_CORNER` 55 %, `COV_DOOR` 50 %, `COV_WALL` 50 %, `COV_PROP` 35 %, using
  the existing `COVER_STOP` path.
- His own corner does not block his shot (`COVER_PEEK_OBS` 5 m already exists;
  apply it per man from his point).
- Going to ground works as in 2b (cover units only).
- Line troops at points get the kind's cover at half value. They are not trained
  to use it, which is the asymmetry below.

**C4. Bounding advance** (an order flag on a move, `mv_bound`, plus an AI use).
- The men split into team A (even slot) and team B (odd slot); the state
  `u_bnd` (hashed) is 0/1, the team moving.
- The moving team's places are the next cover cluster along the path, the best
  scored points within `BOUND_LEN` 25 m ahead in the path's direction. The holding
  team keeps its points and fires; `_missile_think` lets only holders fire.
- The bound ends when the movers are at their points or after `BOUND_T` 12 s. Then
  the teams swap. The unit's anchor advances with the movers.
- Line units ordered to bound do it in whole-unit hops (no split): they are not
  trained for it.

**C5. Street melee.**
- When `u_sq > 0` in an urban cell, frontage = `u_sq` files and only ranks 1-2
  search targets. The others hold their places (no wrap, no lead cap override),
  and the existing `WALK_REACH_MAX` 3 cap applies, as on walls.
- Shove: once a second, compare the two sides' men within 4 m behind their fronts.
  The ratio over 1.5 moves the losing front's anchor back 0.3 m/s (the anchor
  step, so the men follow).

**C6. Player orders.** One stance button cycles `Line`, `Take cover`, `Hold
street` (ORDER_STANCE {unit, stance} through the lockstep; `u_stance` hashed):
- *Take cover*: C2. It is the default for cover-trait units in towns and woods.
- *Hold street*: the unit fills the street across its front. Line units squeeze
  to the street width in 3-4 ranks (`_squeeze` forced on). Cover units claim the
  corners and doors on both sides of that street within 12 m.
- A move order with a long press, or the panel's "Advance by bounds" toggle, sets
  `mv_bound`.

**C7. AI (`sim/siege_ai.gd` for towns, `sim/battle_ai.gd` `_cover_spot` for
fields).**
- Defenders of an open town pick *strongpoints*: cover-point clusters on the
  street nodes nearest the attacker's approach (the street graph's distance tables
  from the attacker entry). They put cover-trait units at corners facing open
  streets and line units as *Hold street* blocks behind them.
- Attackers move skirmishers by bounds along the street graph ahead of their line
  units. Line units follow in main streets and charge a strongpoint once its
  defenders are disordered or `u_alive < 60 %`.
- Easy: no bounds, no strongpoints.

## 6. The asymmetry as mechanics

- **Open ground** (no `V_URBAN`, no cover point or woods within 4 m of the man):
  - formed line units (`cover` 0, `u_formed`, `u_sq == 0`) keep full volleys;
  - line units get +15 % morale resistance from supported flanks: a friendly
    formed unit within 20 m on each side, checked once a second;
  - cover units in the open get nothing new (today's loose order already costs
    them in melee).
- **Streets and cover:**
  - line units in an urban cell with `u_sq > 0` gain `STREET_DIS` 3 disorder a
    second (capped at `DISORDERED`), so they lose `u_formed` in narrow streets;
  - their volley is fired by ranks 1-2 only (the others have no line of fire in a
    lane);
  - cover units in urban cells have no disorder gain, keep fire at will and take
    C3 cover;
  - smaller West units (below) squeeze less, so a 40-man buccaneer company fits a
    6 m lane in 6 files x 7 ranks with no penalty, while an 80-man tercio sleeve
    goes to 4 x 20 and is disordered.

## 7. West towns (design input 2026-10-15) and Rome

**Map.**
- West open towns cover 40-60 % of the battle map (today 9-12 %, 25-50 houses).
  Ports run along the shore, with the town in a band 150-250 m deep and the full
  map width.
- A street grid of blocks 24-40 m: main streets 10-12 m, lanes 5-6 m (`clr` >= 2 m
  either side of the centre line), one plaza of 40-60 m with the church, and a
  waterfront quay 12-16 m with moored ships (existing).
- Each block has 3-8 houses (rect / quad), yards and props (carts, barrels, wells:
  small blocked cells plus `CP_PROP`).
- Houses give cover only, no entry, until slice 2c's garrisoned buildings.
- Defences follow the STATUS history check:
  - walls 0: no wall, at most a stake palisade on the landward side (field-works
    pieces, so they burn and can be hacked);
  - walls 1: a harbour fort (a small bastioned work, its own C_WALL / C_WALK
    polygon with stairs) beside the town on the shore, with batteries;
  - walls 2: the fort plus a landward palisade;
  - walls 3: a full bastioned curtain (the existing wall code, star-trace
    outline).
- Natives (Itza and others): palisade villages in jungle cover.

**Cost and budget.**
- With 300-600 buildings: the nav, `clr` and cover-point build at setup is
  estimated at 40-120 ms. Measure it, and keep it below the settlement worst case
  (450 ms).
- The street graph grows to 600-1,000 nodes. `_dist_table` caching keeps per-tick
  cost bounded, but cap tables built per tick (as today) and prefer the A1 exit
  fields for routers, which removes their path planning entirely.
- Per tick:
  - almost every unit becomes `_u_obs` (the slow obstacle path). Today's
    settlements run 1.3-2.3 ms a tick for 1,300-1,650 men on desktop;
  - the budget is <= 3 ms desktop / 12 ms Tab S7 for 1,500 men;
  - A5 / A6 add about 10 % to obstacle units, B2(a) one byte read per moving man,
    C2 runs at most every 10 ticks per unit over <= 40 bucket points;
  - LOS stays per unit once a second (`_update_vis`), but there are 2-3x the units
    with small companies. Stagger it over 2 s when `n_units > 40`.
- Benchmark a West town with `bench_west_town` (1,500 men, 40 units) before and
  after each phase.

**Unit size.**
- West companies of 30-80 men mean 2-3x the units for the same men. Per-unit costs
  scale: AI think, path plans, `_build_occ`, LOS, `_flow_slots`. Keep them on
  their existing staggers.
- Cohesion: `MIN_FILES` 4 is fine. A 30-man unit's frontage in a lane is 5-6 files
  with no squeeze.
- `WALK_REACH_MAX` 3 makes street melee a 3-4 man front, so the shove (C5) decides
  rather than attrition.
- Morale: losses are proportional, so small units break faster per volley. Keep
  the rules but tune `m_fear` per West row in a later balance pass.

**Rome.**
- Rome towns keep their walls and plans. Of this spec, Rome gets the jitter fixes
  (A, all maps with obstacles) and the clearance field (B: the polis' 7.6 %
  in-wall men are worst).
- From C, Rome gets only C3's `COV_HOUSE` in towns for its skirmishers (javelins,
  slingers, which already have `cover` 1) and the C5 street melee.
- No props, no bounding AI, no stance UI changes beyond the stance button (which
  is generic).
- Rome battle goldens are flat / settlement-free and must not move.

## 8. Determinism, performance, tests

- All new state is integer, in fixed index order, and uses only the sim RNG
  (where any is needed; none is planned).
- Hashed: `u_hud`, `u_stance`, `u_bnd`, `mv_bound`, `cp_u`, `cp_n`, `xf_t0`, `s_wf`.
- Static (setup-built, skipped in snapshots): `clr`, `clr_dir`, the `cp_*`
  geometry, the exit fields (rebuilt in `restore()`).
- Check that `tests/lockstep_test.gd` passes, with a snapshot taken mid-rebuild of
  an exit field.
- Flat / field maps without obstacles must be byte for byte unchanged: the four
  golden digests, `custom_battle_test`, `battle_screen_test`, and `campaign_sim`
  hashes.
- **New determinism scenarios** (`tests/determinism_test.gd --only=`):
  - `rout-wall`: a wall unit broken on a stair stretch. Pass when every man is off
    the walk within 15 s and rout jitter < 5 %.
  - `rout-gate`: the plaza captured. Pass when final routers reach the huddle in
    < 30 s, rev/step < 3 %, and surrender when an enemy comes within 15 m.
  - `trapped`: attackers inside, ladders gone. Pass when they huddle with no
    contact against the wall.
  - `street-cover`: 40 buccaneers in *Take cover* at a crossroads vs a 80-man line.
    The buccaneers lose < 50 % of the open-ground losses.
  - `bounds`: a bounding advance of 120 m through a grid. Pass when it arrives,
    holders fired, and no man is inside a footprint.
- Each scenario runs twice and across snapshot / restore, with identical hashes.
- **Pathing probe thresholds** (`tests/pathing_probe.gd`, the sieges plus 10
  campaign-like West towns):
  - rout jitter <= 5 % in every category;
  - stationary routing time <= 5 % (not huddled);
  - fight / town and fight / near-obstacle jitter <= 3 %;
  - inside the drawn footprint <= 0.2 %;
  - `u_stuck` > 30 s: 0;
  - settlement tick mean not above +10 %.

## 9. Phased plan

| phase | content | model | risk | size | depends on |
|---|---|---|---|---|---|
| 0 | `tests/pathing_probe.gd` from these probes; baseline numbers in STATUS | Sonnet | low | S | — |
| A | A1-A7: exit fields, per-man stair rout, huddle / surrender, rally anchor, slide memory, separation for obstacle units | **Opus** (sim core, snapshot / lockstep) | med: settlement trajectories move; the snapshot of a field rebuild | M-L | 0; can land before 2b, but rebase on it |
| B | clearance field, place / squeeze / graph-cost use | **Opus** | med: every settlement battle moves; graph-cost change touches AI pathing | M | A (shares the steering code) |
| C1-C3 | cover points, claims, firing from cover in towns | **Opus** | med | M | **slice 2b committed** (`_cover_from`, `_peek`, `u_gnd`), B (`clr`) |
| C4-C6 | bounds, street melee / shove, stance orders and UI (sim part Opus; view, icons, panel Sonnet) | Opus + Sonnet | med-high (AI / UI scope) | M-L | C1-C3 |
| C7 | AI: strongpoints, bounding skirmishers | **Opus** | high (AI behaviour) | M | C4-C6 |
| W | West open-town map gen (size, grid, plaza, quay, props, palisade / harbour fort by walls level) | Opus (mapgen hashes) + Sonnet (view) | med: new map kinds; setup time | L | B, C1; aligns with slice 2c |
| T | balance: measure (Haiku) then tune (Sonnet) street cover, disorder, the shove, West morale | Haiku / Sonnet | low | S | all |

Phase A alone fixes the user's report (rout on the walls and at the gates). B fixes
the scraping. C and W are the street-fighting design. Slice 2c (garrisoned
buildings, rooftops) builds on C's points and W's blocks.
