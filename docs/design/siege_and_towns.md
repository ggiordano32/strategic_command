# Siege and towns

Moved verbatim from `docs/DESIGN.md` on 2026-10-22 (the docs split; index in `docs/DESIGN.md` and `docs/design/README.md`). Design sections first, then the "as built" sections in date order.

### Battle maps: woods and settlements (as built, October 2026)

Code: `sim/mapgen.gd` (generation), the "Woods" / "Settlements" constants
and the "woods and settlements" section of `sim/battle_sim.gd` (rules,
paths, gates, capture), `sim/siege_ai.gd` (AI on city maps),
`sim/scenarios.gd` (`settlement()`, `siege_test()`, `bench_city()`),
`campaign/cbattle.gd` (campaign settlement battles). Measured with
`tests/matchups.gd -- --only=maps` (and `--only=sieges`).

**Generation.** Everything is built at setup from the scenario's `terrain`
dictionary (integers only, MapGen's own xorshift, never the sim's RNG), so
both lockstep peers build the same map; the static grids are hashed into
`ter_hash` (in `state_hash()` from tick 0) only when the map has trees or
buildings, so a plain map's hash is what it always was. New keys: `forest`
(woods coverage 0-100, region data), `woods` (hand-placed rectangles, tests),
`ground` (palette, view only), `blocks` / `urban` (hand-placed buildings,
tests) and `city` ({seed, level, walls, bld, def}).
- *Woods* (any map): a 4 m cell grid aligned with the height grid, tree
  density 0-3. Big smooth blobs (4 + forest/10 of them) plus small ones that
  break up the edges, a height term (+40 per metre above the mean, so edges
  follow the contours and woods favour rises), then thresholds read off the
  histogram so that forest x 0.55 % of the map is wooded (a quarter of that
  dense, 55 % medium or denser). The centre 70 % of both deployment bands is
  kept clear. `sym` maps get symmetric woods.
- *Settlements* (city maps): generated in a canonical frame round the
  city's own centre (defenders at the top, main gate facing the attackers
  at the bottom), then turned 180 degrees if the defenders are sim side 0;
  so a city looks the same whatever the field size or side. Footprint: a
  polygon of 7-10 vertices (angles and radii from the seed) of radius 60 /
  85 / 115 m for village / town / city. The block grid (blocks 16-28 m,
  streets 4-6 m, lots of ~10 m, a house per lot less a metre all round) is
  laid out by the seed over the largest footprint, so a town grows into the
  same city; 62 / 76 / 88 % of lots are built. Landmarks by the plaza and
  the main gate from the buildings present (temple for towns and cities,
  market stoa, range, workshop, barracks, stables). A central plaza (half
  size 12 / 16 / 22 m), main streets (6-8 m) from each gate (or, for an
  open town, out of the town in 3-4 directions) to the plaza, a 6 m ring
  road inside the wall. Walls (level 1-3): thickness 8 / 10 / 12 m (outer
  parapet 2 / 2 / 4 m, walkway 4 m, inner face), walkway 5 / 7 / 9 m high,
  round towers at every vertex and either side of each gate; 2-4 gates (5 -
  wall level, at most 2 + settlement level): the edge facing the attackers
  first, then left, right, top; gate opening 8 m. Outside: orchards (trees,
  density 1) and fields at village / town level with walls 0-1, cleared
  ground within 60 m of walls level 2-3, the approach and the attackers'
  deployment kept free of trees. Hill and ridge country: the city stands on
  a plateau (a flat-topped rise of 3/4 of the kind's relief, falling off
  over 70 m), and every city's footprint is levelled (relief damped to a
  quarter). (This is the original ring, `PLAN_RING`, still the default
  without a plan; campaign settlements now use their founder's plan on
  their own site: see "Settlement plans, sites and owners" below.) Generation takes 15-50 ms for the map and 6-15 ms for heights
  on the desktop (cached, so the scenario builder and the sim share it).
- *Street graph* for paths: nodes at the gates (outside, gate, inside), a
  ring outside the walls (20 m steps, clear of the towers), the ring road,
  the plaza, the main streets and the street grid's crossings; edges join
  nodes up to 48 m apart with a 3 m wide clear line (a gate's cells only
  for edges to its own node, so a closed gate cuts exactly that node);
  pieces left apart are joined by the shortest clear line. 50-160 nodes.

**Woods (rules).**

| Rule | Light / medium / dense |
|---|---|
| Speed (infantry, pikes, missile, cavalry, artillery), per mille | 900 / 780 / 660; 860 / 720 / 580; 900 / 790 / 680; 800 / 620 / 460; 650 / 450 / 300 |
| Disorder moving in woods (decay 2 a tick) | +3 / +4 / +5 a tick up to 30 / 45 / 60: a pike wall drops, spears cannot brace |
| Pikes standing in woods | medium or dense: disorder at least 25 / 40 (never formed: short swords) |
| Cavalry momentum cap where the unit is | 80 / 60 / 40 (settlement streets: 40, no run-up) |
| Charge impact on a man standing in woods | 85 / 65 / 45 % |
| Riders fighting in woods | -5 / -10 / -15 to hit, and +5 / +10 / +15 to be hit |
| Arrows landing in woods stopped by trees | 20 / 35 / 50 % (javelins 10 / 20 / 30 %) |
| Stones landing in woods | 15 / 30 / 45 % stopped, plough 80 / 60 / 40 % |
| Flat shots (javelins, bolts) | tree depth along the line 1 / 2 / 4 per 4 m sample, blocked past 8 (8 m of dense, 16 m of medium woods); also for the AI's target choice |
| Batteries | cannot set up in dense woods |
| Morale | no change |

Only on maps with trees: one lookup per unit per tick (anchor), per blow
and impact of a rider or into a man in woods, per missile landing; never
per soldier on open ground.

**Settlements (rules).**
- *Obstacles*: a 2 m cell grid (building, wall body, walkway, tower, gate
  g) and a passability grid (ground / wall walkway bits; a closed gate is
  impassable). The men of a unit whose box (plus 8 m) touches a 16 m cell
  with an obstacle are kept out of cells they may not enter: a blocked man
  walks the unit's *trail* (the last 4 waypoints its anchor passed; toward
  the one after the nearest, or the anchor), else slides along one axis,
  else stays; a man inside a blocked cell may move out. Units away from
  obstacles pay nothing.
- *Paths*: the anchor of a unit with a move or attack order goes straight
  if a 3 m wide line is clear, else over the street graph (entry node near
  it, exit node near the goal, the cheapest pair by graph distance; Dijkstra
  per exit node, cached until a gate changes), shortcut where the line is
  clear; replanned when a gate opens, closes or breaks, when the order
  changes, or (attacking) when the target moved 12 m (at most once a
  second). Routers on a city map run along a path to their own edge.
- *Reachability* (October 2026 playtest: "the formation goes past the
  walls ... sliding along the wall in clumps"): the open ground (and ditch)
  is flood-filled once into pieces with every gate shut (`cmp`, static, ~20
  ms at setup); an open or broken gate joins the pieces beside it (union
  of the pieces, recomputed only when a gate changes: a pure function of
  the gates, not state). A move order (order rule, so preview, sim and
  lockstep peers agree) to ground the unit cannot reach goes, for a tap on
  a house or wall, to the nearest open ground of its own piece within 12 m,
  else to the front of the gate on its side that makes the way shortest,
  where it holds ("No way in: moving to the gate"; attacking foot standing
  there hack it). An attack on a unit in another piece: melee units go to
  the gate on their side nearest the target and hold (attacking foot hack
  it; once it breaks the pieces join and they go in); missile troops with
  shots go only as far as their own ground goes toward it, stand once in
  range and shoot ("Moving into range"; flat throwers without a line of
  fire show "No line of fire" as before; batteries never move to attack).
  The AI's attack orders follow the same rule. A ground unit's places
  (anchor + offset) on ground of another piece than its anchor's, or in a
  wall or house, are pulled in toward the anchor to the first open ground
  of its piece whenever its offsets are recomputed (an order, a turn, the
  end of a move, every second while holding at a gate); no per-tick cost.
- *Squeeze*: every third tick a unit near obstacles measures the free width
  either side of its anchor; if its front would not fit it closes files to
  the width (at least 4) and keeps to the middle of the street, and opens
  out again with 2 m to spare. Pikes in a street are strong frontally and
  cannot be flanked (geometry); cavalry in streets has no run-up (momentum
  cap 40).
- *Melee* is not possible through a wall, closed gate or building corner
  (the midpoint and quarter points must be passable).
- *Walls*: units placed on a wall (garrison missile troops, by the scenario
  builder) stand on the walkway: their height is the ground + 5 / 7 / 9 m
  (missile range from height, line of fire), they never withdraw or
  skirmish, and only wall units may enter the walkway (attackers by
  ladders, see "Siege equipment and wall towers", or, once inside, by the
  inner stairs: see "Stairs"). Since the October 2026 wall-orders fix: a move order onto a
  wall's body, walkway, stair, tower or gate tower goes to the nearest
  walkway point of that stretch (`wall_snap`: the nearest stretch within 14
  m, in the order rule, so preview, sim and both lockstep peers agree; only
  defending foot and missile units; others get a ground move the view
  refuses with a reason). A wall unit stands in its *wall line*
  (`wall_anchor` / `wall_slots`): two ranks along the walkway at most 1.2 m
  apart either side of its centre line, centred on the ordered point and
  moved along so the line fits on the stretch; a line longer than the
  stretch fills it and goes on through the tower onto the stretch joined
  there (`ws_nb`: ends within 26 m whose way along the centre lines is all
  walkway / tower; towers are passable to wall units only, bit
  `NAV_TOWER`), surplus files at the ends; a man whose place falls off the
  walkway cells takes the nearest walkway spot. The same line for garrison
  units at the start and for units sent up. A move onto its own stretch
  slides it along; anywhere else is down a stair (onto the ground in its
  normal block, at most a quarter of its men wide, a third for missile
  troops). Since October 2026 towers are stairs: a move order off the
  stretch takes the unit down the stair at one of its ends and on through
  the streets, routers leave the wall the same way, and defenders can be
  sent up (see "Stairs" below). Battlements stop 25 / 25 / 40 % (wall level
  1 / 2 / 3; tuned 2026-10-10, were 25 / 45 / 70; 35 % at every level before round 3) of missiles that would
  hit a man on a wall from below. Lines of fire (flat shots) are blocked by
  buildings (4-6 m), walls (walkway + 0.6 m parapet), towers (+4 m) and
  closed gates; a shooter on a wall looks over his own battlements. Arrows
  and stones arc over everything; a stone's plough stops at a building or
  wall.
- *Gates*: start closed. The defenders may open or close one (order
  `ORDER_GATE`, any of their units; closing is refused while anyone stands
  in it; a broken gate stays broken). Hit points 1,800 / 2,700 / 3,800 by
  wall level (x 100 % at every level, tuned 2026-10-10; walls 2-3 x 130 %
  from 2026-10-07: "Siege equipment and wall towers"). A burning gate loses
  `GATE_FIRE_CHIP` 1.5 / 0.8 / 0.6 % of its hit points a second at walls
  1 / 2 / 3 (a walls-1 gate is wood: about 70 s of fire; tuned 2026-10-10). Batteries ordered at a gate (`ORDER_ATTACK` with `gate`)
  shoot its outer face: a bolt landing within it (1.5 m round) takes 80 hp,
  a stone 360. Foot (not missile troops, cavalry or crews) of the attackers
  standing at a closed gate (within 2 m of its face, not marching past)
  hack at it: each of at most 10 men takes (damage - 20) x 25 % per swing
  (1 % at walls 2-3 since 2026-10-07; rams and engines break those).
  An order at a gate for foot moves them to its face.
- *Capture*: if the attackers hold the plaza (a ready unit of 10 or more
  men with its centre in the capture zone, the plaza's half size + 6 m) with
  no ready defender unit off the walls within 12 m more, for a continuous
  60 s, every defender unit breaks for good. The battle then ends as any
  other (`BattleSim.result()`, so the campaign applies it unchanged).

**Hashing, snapshots.** Static grids and the graph are rebuilt by setup()
(left out of snapshots); gates, the capture clock, nav (passability),
paths, trails, squeeze, wall placement and gate orders are state, hashed on
woods / settlement maps only, and round-trip through snapshot / restore.

**AI.** Field battles with woods (`sim/battle_ai.gd`, maps with trees
only): cavalry, pikes and batteries whose deployment slot is in woods take
the nearest clear spot within 30 m; cavalry target scores lose 30 per tree
step along the way and 600 per step where the target stands; archers and
javelins with enemy cavalry within 70 m step into medium or dense woods
within 40 m; flat shots through dense woods are refused by the sim.
Settlement battles (`sim/siege_ai.gd`) - see its header: attackers form up
out of the wall archers' reach before the gate they go for (an open or
broken one first, else the weakest / nearest), batteries 165 m out shoot
it, archers 110 m out shoot the walls, the two heaviest foot units hack at
it when there is no battery (or after 2 minutes of bombardment); once a
gate is open or broken (or the town is open) the foot storm in (attack
defenders within 45 m, else make for the plaza; at a still-contested
plaza, the nearest defender anywhere), archers follow to the breach,
cavalry waits outside until the defenders break, then pursues; with no
foot left, or 4 minutes into the assault, everything goes in; nothing
dying for 2.5 minutes: all in if 1.2x stronger, else withdraw. Defenders
never withdraw: wall units shoot, a solid foot unit holds the inside of
each gate (attacks within 25 m of it), the rest hold the plaza and main
street (attack attackers inside the settlement within 140 m), open gates
are shut when attackers come within 100 m. No sallies.

**View.** `game/ground_palette.gd` holds the palettes (plain, arid, dry,
green, rocky: base, low / high tint, contour colour, tree shades), shared
by the battle ground and the campaign map. `game/terrain.gdshader` /
`terrain_layer.gd`: palette from `ter_info["palette"]`; stronger hill shade
(relief exaggerated 3.4x, strength 0.6, lit slopes at 70% so crests do not
wash out), the height tint spanning the map's own relief (5-22 m), valley
floors slightly darker (heights blurred over 24 m on the CPU), and a second
4 m texture from `sim.veg` for the forest floor, paving inside settlements,
lighter main streets and plaza, striped fields; a plain map on the plain
palette looks as before. `game/tree_layer.gd` + `trees.gdshader`: one
MultiMesh of top-down canopies (four kinds, shades by palette: olive, scrub
and cypress on arid / dry ground, oak and pine on green / rocky), 0.45 /
1.05 / 1.65 trees per 4 m cell, orchards in rows, placed from a view RNG
seeded with `ter_hash`; canopies fade to 28% over soldiers through an
occupancy texture rebuilt each tick from the unit boxes (~0.1 ms).
`game/city_layer.gd`: roofs by building kind with shadows, stone walls
with walkway, parapet and merlons, round towers, the plaza; a small gates
node redrawn each tick (closed / open / rubble, flash when hit). Overlay:
gate hp bars, "Plaza held N / 60 s" with a ring, woods stretches and
"woods" in the move hint, men shown green in woods / red in walls in the
drag preview, "BREAK THE GATE" / "SHOOT THE GATE". Tapping a gate: the
defender opens / shuts it (refused with a message if men stand in it);
the attacker sends the selected batteries or foot at it. A tap in a
gate's doorway (its opening + 1 m along the wall, the wall + 1.5 m each
side, at least a marker's touch radius) is about the gate before any unit
marker or box; for the defender it toggles the gate whatever is selected
(the selection stays, nothing moves). Sandbox:
"Ground:" choice and a "Settlement battle" row (seed, village / town /
city, walls 0-3, terrain, attack / defend). Unit book: "Woods" on the
Terrain page and a "Settlements and sieges" page, numbers read from the
constants. Campaign map: regions tinted by their ground (lightened) under
the owner colour with an owner band along the borders, a stone wall ring
with towers by wall level, and the region panel's "View battle map" (a
static render of the settlement's map as it stands, `game/campaign/
city_preview.gd`). Screenshots: `docs/screenshots/maps_*.png`.

**Measured** (`tests/matchups.gd -- --only=maps --seeds=10`, desktop):
- Woods, cavalry 60 charging a standing heavy 100 (infantry killed by 40 s
  / riders lost): open 23.9 / 24.7, light 14.4 / 25.7, medium 5.3 / 25.5,
  dense 1.6 / 25.7 (the cavalry loses every time anyway).
- Cavalry 60 against archers 80 who shoot first: in the open riders lost
  12.5, in dense woods 16.4; the cavalry still wins (archers in melee are
  archers): woods blunt the charge, they do not make archers safe.
- Archers 80 emptying their quivers at light 100 standing 110 m off:
  killed 56 open, 44 / 41 / 25 in light / medium / dense woods.
- Pike 120 pinned by heavy 100 with light 100 into its flank: open, pikes
  lost 53, attackers 45; in medium woods (no pike wall) pikes lost 60 and
  killed none. Pikes do not belong in woods.
- Javelins 60 ordered at light 100 35 m off: 328 thrown, 13 killed across
  open ground; 0 thrown through 20 m of dense woods.
- Streets (10 m between two blocks; units of 8 files): pikes holding
  against heavy 100 win 100% open and in the street; pinned by heavy with
  light 100 at their side: open, pikes lost 54 / attackers 33; in the
  street the light cannot get round (pikes lost 13 / attackers 62);
  cavalry 60 charging heavy 100 kills 18.6 by 40 s in the open, 8.6 in the
  street.
- Gates (main gate of a town; time from the first blow; 10 runs): walls 1
  bolts 44 s (26 shots), stones 45 s (12), heavy 100 40 s, light 100 45 s;
  walls 2 bolts 68 s (39), stones 69 s (16), heavy 60 s, light 68 s; walls
  3 one bolt battery's 44 bolts are not enough (it must refill), stones
  107 s (24), heavy 127 s, light 145 s. Heavy 100 hacking with no cover
  under two units of archers on the walls: breaks a level 1 gate (losing
  21 men), routs before breaking level 2 and 3 gates (the AI covers its
  hackers with archers).
- Garrison only (town; 3 + walls units of 60 men) against the standard
  12-unit attacker (about 1,000 men), AI vs AI, 10 runs each: the attacker
  wins every time, no draws; with / without artillery, minutes to decide:
  walls 0 4.3 / 4.3, walls 1 4.6 / 3.4, walls 2 5.1 / 5.1, walls 3 5.9 /
  5.2; attackers killed 79-169, rising with the walls. (12 units against 6
  small ones is a big edge; a level 3 wall makes it costly, not
  impossible.)
- AI vs AI settlement battles (garrison plus a 4-unit field army against
  the standard attacker, 10 seeds each): open village attacker 100%, 4.3
  min (max 5.2); walled town 100%, 6.4 (10.0); city walls 2 90% (one
  defender win after the attackers withdrew), 7.6 (10.5); hill city walls
  3 100%, 8.9 (11.7); no draws; the plaza capture decides 9 / 9 / 10 of
  the walled battles. Campaign auto-resolve (`tests/campaign_battles.gd
  --only=timing`, now a settlement battle): 12 v 12 7.2-9.9 min of battle,
  4-6 s wall full size; 24 v 24 7.3-8.2 min, 12-13 s full, 7.3 s half size;
  no draws.
- Field battles with woods (bench_2000 armies, generated ground, woods 40,
  10 seeds): 6 / 4 bottom / top, no draws, 5.7 min (max 9.5); archers took
  shelter in woods 125 times.
- Plain maps (no woods or buildings) play bit for bit as before: the golden
  digests and every determinism run's final hash, hilly ones included, equal
  those of the previous build; the woods / settlement rules are behind
  `map_on` / `obs_on` / `veg_on`.
- Benchmarks (desktop, same session; before -> after): bench_4000 mean
  2.61-2.63 -> 2.63-2.66 ms, max 5.74-5.78 -> 5.76-5.98; bench_4000_hills
  2.91-2.92 -> 2.99-3.01, max 6.05-6.28 -> 6.20-6.21; new bench_4000_city
  (3,882 soldiers, 24 attacking units against 26 in a walled city) mean
  2.69, p95 4.73, max 7.8 ms (setup 94 ms), decided at 11.5 min. Its worst
  ticks are the first build of a graph distance table after a gate falls
  (~0.7 ms each, then cached) on top of fighting in the crowded breach (a
  target search there looks at no more than 64 men).

### Settlement plans, sites and owners (as built, October 2026)

Why: in the first playtest of the city maps every walled settlement was the
same round ring, and 17 of 36 regions put it on a levelled plateau, so
nearly every siege was the same hill fort. Now the wall plan comes from the
settlement's founding culture, the ground from the region, the sea from the
ports, and the current owner shows in banners, the shrine and new buildings.

Code: `sim/mapgen.gd` (`plan_outline`, `_city_plan`, `_houses_*`,
`_harbour`, `_segments` / `_stairs`, `_ditch`, `coast_params` /
`shore_y`, `site_of`, `describe`), `sim/terrain.gd` (`_city_ground`:
`_rise`, `_spur`, the citadel's knoll, the sea floor), `sim/battle_sim.gd`
(stairs, ditch, sea, citadel gate, `_attack_goal`, path budget),
`sim/siege_ai.gd` (wall units off a lost stretch, the citadel), `sim/
scenarios.gd` (`siege_test(..., plan, coast)`, `siege_castrum` /
`siege_polis` / `siege_punic` / `siege_oppidum`, `bench_4000_polis` /
`bench_4000_castrum`), `campaign/cbattle.gd` (`city_dict`, `city_caption`),
`game/city_draw.gd` (one drawing module for the battle map, the campaign
preview and `tools/city_dump.gd`). Pictures: `docs/screenshots/
settlements_*.png`.

**Scenario keys** (city dictionary, integers only): geometry `seed`,
`level`, `walls`, `bld`, `def`, `plan` (`PLAN_CASTRUM` 0 latin,
`PLAN_POLIS` 1 greek, `PLAN_PUNIC` 2 punic, `PLAN_OPPIDUM` 3 celtic,
`PLAN_RING` 4 the original ring = the default), `coast` (0/1); view only
(copied into the layout, read by no rule, in no hash): `founder`, `owner`
(cultures), `banner` (faction index; -1 independent, -2 none: side
colours), `bstyle` (culture that built each `bld` entry), `hstyle` (culture
of the houses that came with settlement level 0, 1, 2). The site is
`MapGen.site_of(kind, city seed)`: flat -> plain, hill -> hill, ridge ->
spur, rolling -> plain or a gentle hill by a seed bit, valley -> plain.

**Plans** (one seeded generator each; the draws come in a fixed order
whatever the level and walls, so a town grows into the same city; footprint
radius 60 / 85 / 115 m as before):
- *Castrum*: a rectangle (half width 76-84 %, half depth 70-80 % of the
  radius), square corners or rounded (a 10-16 % chamfer), square towers at
  the corners and every 28-40 m along the sides (interval towers stand out
  from the wall; the walkway runs past them), gates at the ends of the two
  main streets (cardo and decumanus) that cross at the forum in the middle:
  3-4 gates (2 for a village; none on the sea side), regular square insulae
  (20-26 m, streets 4-5 m), built 6 % denser.
- *Polis*: an irregular outline (8-11 corners, radius 82-114 %), the agora
  15-28 % of the radius off the centre toward the front, two street grids
  at 25-45 degrees to each other meeting on a seam through the agora
  (long blocks 16-20 x 30-38 m: wedge-shaped blocks along the seam), 2-4
  gates, round towers, an **acropolis** at a back corner (front corner on a
  coast) on a knoll 9 m high.
- *Punic*: a regular polygon (6-8 corners, radius 94-106 %), walls 2 m
  thicker, square towers every 18-24 m on the land side, two land gates
  (front and one side), dense small blocks (14-20 x 20-28 m, streets 3-4
  m, built 10 % denser), a **citadel** (Byrsa) inland on a 6 m knoll, the
  main square pushed away from it.
- *Oppidum*: an oval (98-108 % x 78-90 %) with a kidney's dent at the back,
  the main gate at the end of a **funnel**: the wall turns in 20-26 m at an
  offset point of the front, one arm longer than the other, big round
  towers at its mouth, the gate in its inner edge, so men at the gate are
  shot from both arms; a second (back) gate in half of the towns and
  cities; round houses (3-5 m) in clusters along bent lanes round a large
  open middle; on a rise (a 5 m flat-topped rise on a plain, the old
  plateau on a hill, the spur on a ridge).
- *Ring*: the original generator, unchanged apart from the stairs.
- *Citadel* (polis and punic towns and cities with walls): a hexagonal wall
  ring of radius 20-24 m (punic 21-25; towns 2 m less) with the outer
  wall's thickness, towers at four corners and one gate facing the agora,
  fitted inside the outer wall (turned up to 150 degrees and pulled in
  toward the centre until it fits; the agora gives way if it must), on its
  knoll. Its interior (about 26-34 m across) is kept open; its gate starts
  **open**. 45 of 48 polis / punic towns and cities in the generator survey
  got one (the misses: small coastal punic towns with walls 3).
- *Enclosed fields*: oppida at village and town level and every village:
  houses only in the middle (the footprint shrunk by 25-35 m), the ring
  between them and the wall is 12 m patches of gardens and pens (field
  bits, open ground) and a few orchards (trees, density 1).
- *Villages* have a small shrine; a walled village's wall is drawn as a
  timber palisade (the rules are a level-1 wall's).

**Sites** (`sim/terrain.gd` `_city_ground`):
- *Plain*: the region's own relief round the city, the footprint levelled
  to a quarter; a straight road out of the main gate with orchards either
  side (26 m strips from 35 m, or 60 m at walls 2-3, out to 40 m before the
  attackers); at walls 3 a **ditch** 6 m wide 24-30 m outside the wall
  line (`C_DITCH`): foot cross it at 45 % speed, horses and engines cannot
  enter it; a causeway (the gate's width + 4 m either side) leads to each
  outer gate; the street graph gets a ring beyond the ditch and nodes at
  the causeways' ends.
- *Hill*: a rise of 10-15 m (rolling country: 6-8 m) centred 35 % of the
  radius behind the centre, its radius 2 x rmax + 60 m toward the main
  gate (the gentle side with the road) and rmax + 45 m elsewhere (about
  10-13 % at the walls), the footprint levelled only to 55 % (the town
  tilts with the hill: no plateau).
- *Spur*: high ground 12-16 m over the city's disc, a neck as wide as 90 %
  of the city running down to a plateau beyond the main gate (where the
  attackers deploy, at the same height), falling off over 45 m on every
  other side (up to ~40 %); levelled to 35 %. Every gate but the main one
  is a **postern**: a 4 m opening without towers.
- *Coast* (regions in `SEA_LANES`, any site): the shore runs straight
  across behind the city at 42-56 % of the radius behind its centre (slope
  up to 5 %), bending and waving beyond the city; everything above it is
  sea (`C_WATER`, `V_WATER`): nobody walks on it, shots fly over it, routed
  or withdrawing defenders go along the shore to the nearer side edge and
  leave there. The wall polygon is cut along the shore (the sea wall: no
  gates, no wall units placed on it, towers where it meets the land
  walls); a sea gate in its longest stretch and a mole with an elbow
  running out from it are scenery (wall cells: it cannot be attacked or
  used). The sea floor is 1.5 m below the lowest land.

**Stairs.** Every walkway stretch has a stair 3 m in from each end (next to
a tower, gatehouse or corner): the wall's inner face there (`C_STAIR`, 4 m
wide) is passable both to the walkway and the street, and its foot is on
the ring road. A unit on a wall:
- ordered to a point more than 7 m off its stretch: it is a descent. It
  picks the end that minimises (its men to the walkway point) + (the foot
  to the destination), its anchor waits at the foot while its men walk the
  walkway to the stair and down (they follow a trail walkway point ->
  stair -> foot), and once every man is off the walkway (or after 40 s)
  the order goes ahead through the streets. A destination on another
  stretch: down, then up.
- routing: down the nearest stair, then away as any router.
A defending infantry or missile unit on the ground ordered onto a wall
(see Walls: any wall cell of a stretch) marches to the foot of the better
stair (always a march, however near: no reforming in place under the
wall), climbs (trail foot -> stair -> walkway) and takes the stretch at the
ordered point in its wall line. On a stair move a man still on the level
his unit is leaving follows the trail (`_stair_goal`; a unit spread over
two stretches puts the junction in the tower first going down); men on the
walkway keep to walkway and towers; a stair counts as down, not up. "Man
the wall" (view): since 2026-10-23 there are no Man the wall / Come down
buttons: a click or tap on a wall stretch (`BattleSim.wall_stretch_at`, the
stretch `wall_snap` finds under the point: body, walkway, stair, tower)
sends each selected unit that may to THAT stretch, a move to its point
nearest the click facing `ws_dir`, `wall_refusal` flashing why not (the
tapped stretch lights briefly on touch); a click in a gate's doorway stays
the gate's, a click or tap on the street or ground is an ordinary move and
brings men down by a stair. M still sends a unit to the stretch within 60 m
nearest the nearest enemy (`man_wall_target`), Shift+M to the foot of its
nearer stair (`wall_inside`) (keyboard only; the `man_wall` counter counts
every wall click as well). Attackers climb by ladders from outside ("Siege
equipment and wall towers") and, since the 2026-10-15 stairs fix (it was
"Attackers cannot use the stairs once inside"), by the inner stairs once
inside: an attacking foot or missile unit on the ground whose ground
(gates as they are) reaches a foot of the stretch's stairs (`att_stairs`)
takes a move onto the wall as defenders do (order rule, so preview and
peers agree; a wall click too). Inside the walls (its anchor's piece
with every gate shut holds a stair foot: `att_inside`) it always uses the
stairs, never out to ladders; outside, ladders on that stretch first, else
a stair its ground reaches (a broken gate), else an ordinary move. An
attack by attacking infantry inside on a unit on the wall is a march up
the stair the enemy's stretch reaches by (its line at the stair's head),
then an attack along the walk (`_climb` keeps the target: the column on
the walk). An attacker on the wall withdraws or routs back down its ladders
only on the stretch they stand against (`by_ladders`), else down a stair;
ladder climbers come down into the town by a stair as before. A walkway
point that lies in its stair's own cells (some stretch ends) is passed 2 m
on toward the walk going up (men had stood there until `STAIR_MAX`).
`--only=stairs` in tests/determinism_test.gd. The AI does not send
attackers up the stairs: its move and attack orders carry `"ground": 1`,
which keeps an attacker on the ground (a storming unit's move onto a wall
cell had sent it to a stair); its storming units fight in the town. State
`u_stair` / `u_sseg` / `u_send` / `u_st0` / `u_wx` / `u_wy` is hashed on
walled settlement maps and survives snapshots.

**Citadel capture.** With a citadel the capture zone (`plaza`) is the
citadel's interior square (half size radius - wall/2 - 3 m, + 6 m): the
attackers must hold it 60 s with no ready defender off the walls within 12
m more (the rule as before), so they need its gate too. The agora is just
the main square (`agora`: the defenders' posts and the shrine).

**AI.**
- Defenders: a wall unit whose nearest outer gate is open or broken, with
  an attacking unit inside the walls within 40 m, comes down by a stair
  and runs to a post in the citadel (if its gate is not shut) or at the
  agora; when the town is lost (an attacker within 30 m of the citadel's
  gate, or more attacking men inside the walls than defending men off
  them) the defenders fall back into the citadel - as many as it holds
  (about 1.5 men per square metre of its interior: wall units first, then
  missile troops, then the others by index; the rest fight on in the town)
  - and shut its gate once those are in or an attacker is within 25 m of
  it (never on men standing in it). In the citadel they attack attackers
  who get in and missile troops shoot from their posts.
- Attackers: the citadel's gate is never chosen as a breach or for the
  approach; once in the town with the citadel shut, the three heaviest foot
  units hack at its gate, the others fight defenders in the town and
  gather 20 m before it, batteries within reach shoot it.
- Both: on settlement maps a unit moving among walls and houses waits for
  its men when their centre lags more than 20 m + half its depth behind
  the anchor (they follow its trail); attackers make for a reachable point
  of their target (its centre, else its anchor, else its man nearest them)
  so a unit split round a house or a wall can still be reached; squeezed
  units keep to the middle of a street a metre at a time (the old jump
  could flip from side to side at a corner and stall the unit); a unit
  whose men stay strung out for 10 s regroups (its anchor goes back to the
  man nearest their centre and it plans its way again); a blocked routing
  man slides along the obstacle instead of walking the unit's trail (which
  lies behind him); a man left in a stair after a stair move walks to its
  foot.
- Balance pass (October 2026, after the first plan table showed walls-3
  citadels and oppida at 12-25 % attacker wins and up to 50 % draws; each
  change from a diagnosed freeze or grind):
  - melee reach must cross ground (or ditch, stair foot) cells: men on
    either side of a wall had targeted each other over the walkway and
    tried for ever to close; a kept target is dropped once out of reach;
  - a unit counts as cut off when its men are 8 m + half its depth from
    the anchor while not fighting, and regroups after 10 s (it slows to a
    quarter only past 20 m);
  - storming units spread over the defenders (each other unit already on
    one counts as 25 m more) and, with no defender within 45 m, go for the
    plaza even when all out (hunting the last defenders anywhere had let
    them hold out); hunting anywhere only at a contested plaza;
  - **the town is lost**: while the attackers' men inside the walls are 3
    times the defenders' ready men, after 2 minutes every defending unit
    (walls and citadel included) loses 6 morale a second and does not
    recover (`_town_lost`, hashed counter `cit_siege`);
  - a citadel's gate has 60 % of the outer gates' hit points; batteries out
    of reach move up to 70 % of their range from it;
  - the oppidum's funnel is 20-26 m deep and 8 m wider at its gate edge, and
    an oppidum gets no ditch (it would run into the funnel and leave one
    causeway under fire from both arms);
  - the attacker withdraws below 35 % of its starting strength when weaker
    than the defenders (was 20 %); all out and stalled 5 more minutes it
    withdraws unless 1.5x stronger;
  - every gate in the street graph is joined to its own outside and inside
    points (a citadel's short gate edge had cut its interior off the graph,
    so units sent to its plaza went "straight on" into walls);
  - settlement-map target searches scan rings of cells outward and stop
    once nothing nearer can remain (same nearest man, except that the
    64-man budget is spent on nearer cells first).
- Round 3 (2026-10-06): battlement cover by wall level 25 / 35 / 65 %
  (was 35 % at every level) and, behind level 3 walls, "the town is lost"
  drains 3 morale a second instead of 6. Walls 3, 8 seeds (attacker /
  defender / draw %): ring plain 100/0/0, ring hill 100/0/0, castrum
  100/0/0, polis coastal 87/0/12, polis plain 87/0/12, punic 100/0/0,
  oppidum spur 62/37/0, oppidum plain 75/12/12. The cover barely moves the
  easy plans: the attackers' losses come from the street fighting, not
  from shooting at the walls; a 60-85 % band on every plan needs a lever
  in the town fight (open). The stall clock now starts only after 4
  minutes of approach (bombarding, then hacking): with the rate-based
  stall the attacker had given up during the approach.
- Breach performance (round 3), no behaviour change except where noted:
  enemy men per 16 m block counted in `_build_grid` so a settlement search
  with no enemy near returns at once; searches skip cells that cannot hold
  anyone nearer than the best so far (budget order changes: noted); a lean
  branch for men who only follow their slot (hash-identical); line-of-sight
  checks skip 8 m at a time through obstacle-free 16 m blocks
  (hash-identical); on settlement maps half the men who just lost their
  target search at once and the rest at their next regular search (a
  behaviour change: it halves the search bursts when a unit breaks).
  Idle machine, mean / p95 / max ms: bench_4000_city 2.80 / 5.18 / 6.70,
  polis 2.97 / 4.74 / 6.48, castrum 2.85 / 4.89 / 6.41 (were 2.95 / 5.94 /
  7.56, 3.18 / 5.36 / 7.55, 3.10 / 5.72 / 8.54); in the same session the
  unchanged flat bench_4000 measured 2.89 / 4.79 / 7.78 (2.65 / 4.45 /
  5.88 an hour earlier), so the maxima carry ~1 ms of machine noise.
- Attackers' stall watch: under 10 defenders killed (a gate's 100 hp
  counts as one) in 2.5 minutes is a stall (it used to be any death at
  all, so a trickle of losses kept a hopeless assault going): all out if
  1.2x stronger, else withdraw; all out and stalled 5 more minutes:
  withdraw.

**Owner dressing (view only).** Banners in the owner faction's colour on
the gate towers, the citadel and the agora (independent grey; sandbox: the
defending side's colour); the owner's shrine on the agora (in the temple's
footprint: Roman podium temple, Greek colonnaded temple, Punic walled
precinct, Celtic sacred enclosure); roofs by the culture that built each
building or settlement level (Roman red tile, Greek pale tile, Punic flat
white, Celtic thatch). The campaign remembers who built what (state format
3, CAMPAIGN.md); the region panel's "View battle map" shows it all with a
caption ("Greek city on a coastal hill, held by Rome").

**Performance.** Street graph distance tables (one Dijkstra per exit node,
~0.7 ms) are built at most two a tick: a unit whose table is not ready
keeps its old path (or, with none, heads straight for its goal) and plans
again within half a second. Which tables exist is state for the budget's
sake (`_dist_have`, `_dist_epoch` are snapshotted; `restore()` rebuilds
them), so lockstep peers and restored copies plan the same units on the
same ticks.

**Measured** (desktop, Ryzen 7 5800X; `tests/matchups.gd -- --only=plans
--seeds=8`: a city held by its garrison and a 4-unit field army against
the standard 12-unit attacker, AI vs AI, 8 seeds a row; attacker /
defender / draw %, mean minutes to decide). First table as the plans
landed, second after the balance pass:

| Plan, site | walls 1 | walls 2 | walls 3 |
|---|---|---|---|
| ring, plain (baseline) | 100/0/0, 7.6 -> 100/0/0, 5.7 | 100/0/0, 10.3 -> 100/0/0, 5.8 | 100/0/0, 9.4 -> 100/0/0, 7.4 |
| ring, hill (plateau) | 100/0/0, 10.1 -> 100/0/0, 5.9 | 87/12/0, 10.0 -> 100/0/0, 6.8 | 100/0/0, 11.2 -> 87/12/0, 7.7 |
| castrum, plain (ditch at 3) | 100/0/0, 5.4 -> 100/0/0, 4.7 | 100/0/0, 6.9 -> 100/0/0, 5.2 | 75/25/0, 8.5 -> 100/0/0, 6.3 |
| polis, coastal hill | 87/0/12, 10.9 -> 100/0/0, 7.6 | 75/0/25, 11.5 -> 87/12/0, 9.1 | 62/25/12, 12.3 -> 100/0/0, 9.6 |
| polis, plain | 87/0/12, 11.0 -> 100/0/0, 7.7 | 75/25/0, 10.7 -> 87/12/0, 9.0 | 25/37/37, 12.8 -> 100/0/0, 9.0 |
| punic, coast | 100/0/0, 9.1 -> 100/0/0, 7.8 | 87/12/0, 10.7 -> 100/0/0, 9.5 | 25/50/25, 12.1 -> 75/25/0, 10.4 |
| oppidum, spur | 75/0/25, 9.9 -> 100/0/0, 6.9 | 50/37/12, 11.5 -> 87/12/0, 7.6 | 12/50/37, 11.7 -> 75/12/12, 8.5 |
| oppidum, plain | 50/0/50, 11.2 -> 100/0/0, 6.5 | 62/25/12, 10.0 -> 75/25/0, 7.9 | 12/37/50, 13.8 -> 50/37/12, 8.9 |

- After the pass: draws at most 1 in 8 (two oppidum rows at walls 3),
  every row decided in 4.7-10.4 minutes on average; at walls 3 the
  attacker wins 50-100 %: the oppidum on a plain is still the hardest (50
  %), the ring, castrum and polis are now easy (87-100 %, as the ring
  already was before). A 60-80 % band at walls 3 on every plan would need
  stronger walls-3 defences (rules), not a weaker AI: left open.
- The citadel and the funnel still cost the attacker more than the ring
  (polis / punic kill 600-670 defenders but take 8-10 min; the oppidum
  costs up to 490 attackers at walls 3 against 370 for the ring).
- Castrum on a plain with a ditch: foot use the causeways; in a scripted
  crossing heavy foot wade it (119 unit-ticks in it), riders never enter.
- Benchmarks (mean / p95 / max ms per tick; milestone start -> plans
  landed -> after the balance pass, the last under load from another
  agent's runs, max values +-1 ms): bench_4000 2.71 / 4.57 / 5.89 -> 2.73 /
  4.62 / 6.15 -> 2.80 / 4.70 / 7.23 (flat code unchanged: noise);
  bench_4000_city 2.80 / 4.95 / 7.68 -> 2.83 / 4.92 / 7.49 -> 2.95 / 5.94 /
  7.56; bench_4000_polis - / 2.87 / 4.77 / 7.38 -> 3.18 / 5.36 / 7.55;
  bench_4000_castrum - / 2.86 / 5.04 / 7.36 -> 3.10 / 5.72 / 8.54. No worst
  tick builds a path table. The breach ticks are volume: ~1,600 men inside
  a unit-level contact box take the full per-man contact path (~3 µs each)
  while only ~200 target searches, ~115 slides and ~14 blows happen a tick;
  the balance pass puts more men in the town at once, so p95 rose. The fix
  is per-man contact gating (or splitting the tick), not search: open.
- Auto-resolve wall time (`tests/campaign_battles.gd --only=timing`;
  start -> plans -> balance pass, the last under load): 12 v 12 full 5.4 /
  6.4 -> 6.8 / 6.1 -> 6.2 / 8.0 s; half 3.7 / 3.4 -> 4.3 / 3.9 -> 3.9 / 3.9
  s; 24 v 24 full 12.2 / 12.5 -> 15.3 / 13.7 -> 15.2 / 14.3 s; half (used)
  7.2 / 7.1 -> 2.9 / 2.8 -> 3.2 / 3.0 s.
- Generation: 15-110 ms a map (punic cities with walls 3 and a ditch the
  most), terrain 5-40 ms.

### Siege equipment and wall towers (as built, 2026-10-07)

Why: the Skilled campaign AI found that an army was better off fortified
outside a city than inside it, and in the sim walls-3 attackers won 87-100 %
of the 1.5-2:1 `siege_test` battles. The user's decision: **no stat bonus
for standing inside walls**; a city holds by attrition at the wall and a
slow street fight. This is part 1 of three (docs/STATUS.md "Where we are
headed" item 4): attrition at the wall. Code: `sim/battle_sim.gd` (section
"siege" at the end, plus hooks in setup, the order rule, `_wall_order`,
`_update_units`, `_update_soldiers` (the ladder climb's per-man goal and
mask through `_stair_leave` / `_stair_mask`), `_update_gates`, the line of
fire, `_land`, `_land_bolt` / `_land_stone`, morale, `_check_winner`,
`state_hash`), `sim/unit_types.gd` (SPECIAL: `tower_bolt`, `tower_stone`,
`ram`), `sim/siege_ai.gd` (section "siege equipment, towers"),
`sim/scenarios.gd` (`settlement(..., equip)`, `fair_siege`),
`campaign/cbattle.gd` (`siege_equipment`, `equipment_text`, `_time_limit`),
the view (`game/battle.gd`, `game/order_preview.gd`, `game/overlay.gd`,
`game/custom/*`, `game/main.gd`, new-campaign and siege panel).

- **Hard gates.** Walls-2/3 gates had `GATE_HP_PCT` 130 % of their old
  hit points (3,510 / 4,940; tuned 2026-10-10: 100 / 100 %, 2,700 / 3,800:
  a walls-3 gate falls to the ram 8-9 times in 10 and its blows scale with
  the hit points; a walls-2 gate falls to the batteries, whose time did
  not change between 100 / 85 / 70 %) and take `GATE_HACK_BY_WALLS` 1 % instead of
  25 % per sword blow (a few hours of hacking): they yield to rams and
  artillery. Walls 0-1 gates are unchanged.
- **Tower engines** (walls 2-3; city key `towers`: 0 leaves them out). At
  setup the sim appends engine units of the defenders (UT "fixed") on the
  generator's towers (`map_info.city.towers`, in order): bolt throwers on
  the towers flanking each outer gate first, then on others nearest the
  main gate at least 40 m apart, 6 in all at walls 2 and 8 at walls 3
  (tuned 2026-10-10: 3 and 4, `TOWERS_MAX`); at
  walls 3 first two stone throwers on the biggest towers not by a gate
  (one since 2026-10-16, `TOWERS_STONE`: forts leftovers) (`_siege_towers`). None on a citadel's towers or on the sea wall. Each is
  one engine (bolt: crew 4, 20 bolts, 180 m, reload 6 s; stone: crew 6, 12
  stones, 280 m) with a fixed load, 150 % with a Workshop in the city's
  `bld` (cdata chain `workshop`, MapGen.B_WORKSHOP: the campaign's own
  building list, no new key). The unit is a wall unit of the nearest
  stretch (its crew keeps to walkway and towers; battlements cover them),
  never moves, packs, refills or loses heart; it shoots over its own tower
  (the line of fire ignores the tower's own cells, `_skip0`) and over
  friends (bolts need no clear line past friendly units). It is gone when
  its crew is dead or its engine (the tower) is wrecked: a bolt ordered at
  it landing within the tower takes `TOWER_BOLT_DMG` 70, a stone
  `TOWER_STONE_DMG` 330 (900 / 1,200 hit points; the crew falls with it).
  The order rule lets a tower only shoot (a unit, at will) or halt; the
  player gets its engines as one card per kind ("Bolt towers x6": shots
  left, crew alive; a tap cycles through them, the camera follows, the panel
  says "Wall engine: fixed, shoots on its own") and the pre-battle card lists
  "Wall engines (up to)" with the Workshop note (no Deploy / Refill). It does not
  count toward a side's standing units (`_check_winner`) or the town-lost
  count.
- **Siege equipment as objects** (part 2b, 2026-10-07; replaces part 1's
  per-unit ladders flag and the ram unit; Rome 2's model). Scenario
  `equip` `[[kind, x_m, y_m], ...]` (`EQ_LADDERS` a set of 5 ladders,
  `EQ_RAM`), the attackers', on the ground behind their line
  (`Scenarios.settlement(..., {"ladders": sets, "ram": n})`, 12 m apart).
  Sim arrays `q_kind / q_x / q_y / q_state (GROUND, CARRIED, PLANTED,
  WRECKED) / q_unit / q_seg / q_wx / q_wy / q_hp / q_side (`q_acc` until 2026-10-09, now `q_lt` per lane)`, per
  unit `u_carry`, `u_pick` (an order field: "pick"), `u_lq` (the set it
  climbs / came up by); hashed with the other siege arrays (`sg_on`),
  in snapshots. Orders `ORDER_PICKUP` (unit, equip: it marches to the
  piece and takes it within 6 m; any attacking foot, pikes too, not
  horses or engines, carrying nothing) and `ORDER_DROP` (put down at its
  anchor). A carried piece rides at the carriers' anchor; they walk (the
  ram at 1.2 m/s, ladders 80 % of the walk), never run, attack no unit
  (the ram's carriers go at gates), shoot nothing and fight at 60 % attack
  and defence; routing or wiped out they leave it where it is.
  - **Ladders**: carriers ordered onto a stretch from outside march to a
    point out from its foot (`ladder_approach`: 5-24 m out on firm ground
    with room round it, past a ditch), go up from within `LADDER_NEAR` of
    the foot (`_ladder_reached`), plant the set there for the battle and
    climb (pikes plant but do not climb); any infantry or missile unit of
    theirs ordered onto that stretch later climbs the same set. The set
    brings a man up every `LADDER_TICKS` / 5 ticks between all who climb
    it (`q_acc`; since 2026-10-09 each ladder its own man every
    `LADDER_TICKS`, `q_lt`, queues at the feet, orders taken while
    climbing: "Units flow into the space"). Climb, walkway fighting, the way down (`_ladder_down`)
    and unbarring a gate from inside (men who came up by ladders) as
    before. Bug B fixed: a unit whose last leg ran along the wall arrived
    pressing its men into it (the anchor never reached the foot, its men
    could not form there, it regrouped and shuffled) and a foot squeezed
    by a tower got no clear line to a path node (long detours);
    `tests/ladder_probe.gd` checks every stretch of every plan x site x
    coast x wall level.
  - **The ram**: carriers ordered at a closed gate (an outer gate, or the
    citadel's from the town) go to its outer face; up to `RAM_CREW` 20 of
    their men there batter it (`RAM_DMG` every `RAM_WORK` man-ticks), and
    they put it down once it breaks. It has `RAM_HP` 2,500: a bolt landing
    within 3 m takes 70, a stone 330, defenders standing at a ram on the
    ground smash it; its roof stops 70 % of the arrows landing on carriers
    within 5 m of it.
  - **The siege tower** (the helepolis; STATUS 4f.1, built 2026-10-09):
    `EQ_TOWER`, a piece in the same tables. What a piece is lives in
    per-kind fields indexed by `EQ_*` (`EQ_ROOF`, `EQ_ROOF_R`, `EQ_HP`,
    `EQ_LANES`, `EQ_LANE_GAP`, `EQ_CLIMB`, `EQ_WALLS`, `EQ_PACE`,
    `EQ_WALK_PCT`, `EQ_MEN`, `EQ_ANY`, `EQ_SHOT`, `EQ_EXPOSED`,
    `EQ_DEPTH2`, `EQ_SMASH`, `EQ_FOCUS`, `EQ_FIRE_AT`); the sim reads the
    fields, ladders and the ram keep their old numbers through them. The
    tower: about 6 x 6 m (`EQ_DEPTH2` 3 m), 2,000 hit points (the biggest
    wagon's 1,000 twice: a frame of twice the timber; seven stones or 29
    bolts wreck it, a fire chips 18 % as for anything wooden), roofed
    (70 % of the arrows on the men within 8 m of it, a whole unit pushes
    it, where the ram's 20 men fit in 5 m). Pushed at most 0.6 m/s (half
    the ram's pace: twice its mass for twice its crew) by a unit of 40 men
    or more, slower with fewer (pace x men / 40, at least a quarter: it
    crawls) (`carry_pace`). Planted like a ladder set (tap a stretch from
    outside with its pushers: they push it to the wall's foot), but only
    against walls 2-3 (`EQ_WALLS`: walls 1 have ladders; the view refuses
    "too low for a siege tower"); then it is a wide fast ladder: men cross
    8 abreast (`EQ_LANES`, 0.75 m apart along the wall), a man a lane every
    16 ticks (`EQ_CLIMB`; one man every 2 ticks in all, 5 a second, whatever
    the wall's height: three times a ladder set's 1.7 a second at walls 2,
    four times its 1.25 at walls 3). The pushers cross first, then any
    infantry or missile unit ordered onto that stretch, of either side
    (`EQ_ANY`; the defenders only from outside the walls, the tower's foot
    on their own ground). Carriers drop it (`ORDER_DROP`); anyone picks it
    up (`ORDER_PICKUP`), the enemy too (it becomes theirs, `q_side`); a
    planted tower stays (refused). Wooden and exposed even planted
    (`EQ_EXPOSED`: its middle 3 m out from the foot, `eq_centre`): fire
    missiles set it alight (the fire state `q_burn`), bolts and stones
    landing within 3 m of its middle batter it (70 / 330), the enemy's foot
    at it on the ground smash it like the ram; when a planted tower is
    wrecked, men still crossing it come back down (`_ladder_down`).
    Scenario `equip` kind 4; `Scenarios.settlement(..., {"towers": n})`
    puts them in a row of their own 14 m behind the ladders and ram (the
    attackers' edge), walls 2-3 only. View: a tall box with its storeys
    and a ramp (raised while moving, down onto the walkway when planted),
    burning flicker, a marker with the siege tower symbol and a dashed
    ring while it lies on the ground, previews "PUSH THE SIEGE TOWER",
    "PLANT THE SIEGE TOWER HERE", "ACROSS THE SIEGE TOWER", "CROSSING: n OF
    m OVER", cards "pushing a tower", Drop as for any piece; custom battles
    "Siege towers: 0 / 1 / 2" (walls 2-3); the campaign's equipment line
    names them.
- **Field artillery is equipment too** (2026-10-09): a battery's engines
  are dropped and taken up with the same orders and UI as ladders and the
  ram, by either side (section "Artillery", "Engines are equipment, crews
  are men"); the towers' engines stay fixed.
- **No blows at walls** (bug C): walls-2/3 gates do not yield to swords
  at all (`gate_hackable`: the order rule refuses foot at them, the sim
  skips their hacking, the AI never sends hackers); a man holding a target
  he cannot reach (behind a wall, a gate or a corner) drops it within two
  ticks (was eight), so no unit stands "fighting" a wall.
- **Battle time limit**: scenario `time_limit` (seconds, at least 60;
  absent = 900, the old fixed 15 minutes), hashed only when not 900. The
  HUD clock shows "m:ss / limit"; a draw by time says so.
- **Hashing, snapshots.** `u_lad`, `u_lfx`, `u_lfy`, `u_lacc` (ladder work /
  ram work), `u_trad` and `g_unbar` are state, hashed only when the battle
  has a tower, ladders or a ram (`sg_on`); towers add units and engines,
  which are hashed as any. Battles without them (field battles, walls 0-1
  cities) hash exactly as before.
- **AI** (`docs/AI.md` 13, every level): the ram goes at the gate the army
  goes for (Skilled first waits up to 90 s for the towers by it to be
  silenced); with a working ram no foot hack. Ladders: against walls 2-3
  (any walls without working artillery; Easy any) the 1 / 2 / 3 heaviest
  ladder-carrying foot units go after 2 minutes, or once the gate is below
  85 %, to the stretch within 140 m of the gate scored by distance +
  defenders on the walls within 40 m + working towers within 60 m (one
  unit a stretch); once up they go down to unbar the nearest closed gate.
  Batteries shoot the working towers within 40 / 60 / 90 m of the gate
  before the gate. Defending towers pick the ram, then batteries, then men
  at a gate, on ladders or up on the walls (Easy: fire at will); a reserve
  foot unit goes up against every ladder party (not Easy).
- **Campaign** (`docs/CAMPAIGN.md` "Siege equipment"): an assault after a
  siege of a full turn brings ladders for the attackers' foot, of two
  turns a ram too (`CBattle.siege_equipment`, from the siege entry's turn;
  no state, VERSION 6); `settings.time_limit` (new-campaign "Battle time:
  15 / 20 / 30 / 45 min", stored only when longer than 15). Custom battles:
  Ladders / Ram toggles (settlement with walls) and Battle time; the
  sandbox settlement row: siege kit and minutes.
- **Levers** (static in `BattleSim` so `tests/matchups.gd --tune=NAME=...`
  can try values; the game never changes them): `WALL_COVER` 25 / 45 / 70
  % (was 25 / 35 / 65), `WALL_RANGE_PCT` 0 / 15 / 15 % (missile troops on a
  wall reach that much further at men below), `GATE_HP_PCT`,
  `GATE_HACK_BY_WALLS`, `LADDER_TICKS`, `TOWERS_MAX`, `TOWERS_STONE`,
  `RAM_DMG`. Walls-1 values are the old ones (walls-1 battles hash as
  before): raising its cover to 50-60 % and its range by 20-30 % moved the
  equal-force walls-1 siege by 10 points at most.
- **Measured** (`tests/matchups.gd -- --only=fair-sieges`: a city held by
  its garrison and a field army as strong as SIEGE_ARMY, ring and polis on
  flat ground, both AI Average, 10 seeds; attacker wins with ladders and a
  ram / with artillery only): walls 1 100 / 100 %, walls 2 60 / 10 % (ring)
  and 50 / 10 % (polis), walls 3 50 / 0 % (ring) and 10 / 0 % (polis; 20 %
  draws, stand-offs at the acropolis that 30 minutes do not settle);
  battles 6-11 min mean, walls 3 up to the 15 minute limit. Tower engines
  kill 40-95 men a battle; 1-3.5 towers are battered down. Walls 1 misses
  the 45 % target: no towers, a gate artillery breaks in two minutes; it is
  decided in the streets (part 2). The 1.5-2:1 `--only=plans` attackers
  (artillery, no ladders or ram) now win walls 3 0-30 % (castrum 70 %),
  were 60-100 %. Tick cost: bench_4000_city (walls 2: 6 towers) mean 3.15
  ms (2.84 before, same session), p95 5.7 (5.5), worst 7.0-7.1 (7.2-8.1:
  machine noise).

### Unit blocking and street fights (as built, 2026-10-07)

Why: units walked straight through each other, so a column storming a
town went through the defenders in the streets and a street fight was
over as soon as it started ("cities must be worth defending", part 2a).
Code: "unit footprints" in `sim/battle_sim.gd` (`_build_occ`, `_occ_probe`,
`_anchor_step`), `_slots_off_enemy`, `place_clear`; `sim/siege_ai.gd`
`_breach_hold` / `_guards_join` (since replaced by the defender layout,
below). Everywhere (field and city maps).
- **The press in a town (tuned 2026-10-10).** On settlement maps a
  fighting man may get `TOWN_PLACE_LEAD` 10 m ahead of his place instead
  of the field's `PLACE_LEAD` 1.5 m ("Ranks hold together"): in a gateway
  or a street the formation's places stand in the walls and houses, and
  with the field's cap a column coming out of a gateway fought only with
  the men at its places, against a stack that had its whole frontage.
  Measured: equal-force walls-1 sieges (ladders + ram) went from 40 / 50 %
  (ring / polis) to 0 / 30 % with the melee commit 15ef028 (bisected over
  the day's commits); 3 m gave 0-30 %, 10 m 40-60 %, no cap 70-100 %.
  Re-measured after "Units flow into the space" (2026-10-10, full kit,
  10 seeds): 10 m ring / polis walls 1 40 / 40 %, the field's 1.5 m
  10 / 30 %; kept.
- **Footprints.** At the start of each tick's unit update every ready unit
  on the ground (not routing, not on a wall, a stair or its ladders, not a
  tower's engine) marks its footprint in the 4 m cells of the soldier
  grid, one array per side (`occ0` / `occ1`, derived state rebuilt every
  other tick and carried in snapshots, not hashed): its formation rectangle (anchor at the front
  centre, 1 m ahead, 0.5 m beyond the outer files and the rear rank, half
  extents at least 2 m) clipped to its men's box, row by row (each row's
  run of cells from the rectangle's edges: per unit, never per soldier;
  batteries: the men's box). A cell holds the number of units, the number
  of them fighting or queued, and the first (lowest) unit.
- **Anchors.** Wherever a unit's anchor moves (a move or withdrawal, an
  attack, a path through the streets, missile troops closing to range),
  the step is probed at the anchor and its two front corners (across its
  facing, at most 8 m out; a step with all four cells empty goes on at
  once). Into an *enemy's* footprint it may not step: it steers round it
  (30 or 60 degrees off, on the side it chose before, else away from the
  enemy's middle, only with a free cell 4 m on that way; never
  round the unit it attacks) or stops there (`u_blk` BLK_ENEMY; since
  2026-10-09 not at its own target's footprint while none of its men is
  within reach: it presses on into contact, "Ranks hold together"). A unit
  already inside an enemy's cells (it came to us) may back away from its
  middle. A move stopped by an enemy fights where it stands (its men do
  not disengage). Through a *friend's* footprint it goes at half speed
  (BLK_FRIEND: files interleave, so streets and gateways never deadlock).
  A unit attacking, not itself fighting, whose target is fighting, waits
  behind friends fighting or already waiting within 60 m of the target's
  box (BLK_QUEUE) unless it can go round them: the queue behind the line
  in a street, a second line behind the first in the field. `u_blk` and
  `u_dodge` (the side chosen) are hashed unit arrays.
- **Places.** When a unit's offsets are recomputed with an enemy near, a
  man's place a cell deep inside an enemy's footprint moves back 2 m at a
  time (at most 8 m); places on the seam stay. Men at the seam fight as
  before; no soldier-level separation was needed (men close only to 3/4 of
  their reach of their man).
- **Street frontage.** The squeeze (above, "Settlements (rules)") already
  clamps a unit's files to the free width either side of its anchor in any
  corridor (streets, gateways, causeways); with blocking a 10 m street now
  holds one unit a side at a time and the rest queue behind. The drag
  clamp (one rank at most) stays.
- **Deployment.** A placement whose formation's middle lies in another
  ground unit (or another's middle in it) is refused (`place_clear`, in the
  order rule; units placed in the same batch or with a placement pending
  do not count); the view says "Another unit stands there".
- **AI.** Pathing and storming need nothing new: the queue is the AI's
  reserve waiting behind the line. Skilled defenders (knobs `S_BREACH_HOLD`
  1, `S_GUARD_JOIN` 120 m; 0 at Easy / Average, see docs/AI.md 14): once a
  gate is breached, the reserve foot nearest two posts along the wall 14 m
  either side of it hold them and charge attackers coming out of the
  gateway within 22 m, and the guards of gates with no attacker within
  120 m come to posts behind the breach. Measured at Average both cost the
  defenders more than they gained above walls 1 and did not move walls 1.
- **Measured** (desktop; docs/STATUS.md has the tables): a 10 m street,
  three heavy units of 60 a side: one unit a side fights at a time, 28 /
  25 killed in 150 s; a light unit through a standing heavy one 629 ticks
  against 574 round it; four units through one open gate together all
  arrive. Gate rush (a spear unit holding the gateway): foot ordered to the
  plaza stop at it and fight there, never get behind it, and the plaza
  clock never starts; riders at the run stop at it too (and break on the
  braced spears); with the spear 14 m inside both stop at it and fight
  (the path's way round, the ring road, is not taken: the anchor steers
  round only where a free cell lies 4 m on). (An earlier build that probed
  the front corners along the step instead of across the facing let the
  riders slip round by the ring road and take the plaza.)
- **Defender layout (part 2c, 2026-10-08).** The settlement AI now uses
  the narrow end (docs/AI.md 16): once it reads the attacked gate from the
  field (batteries' and the ram's targets, ladders, attacking foot massing
  before it; Easy keeps the old reserves), the defenders' foot stack up in
  that gate's inner mouth, the front unit across the gateway's inner end
  facing out and the rest behind it, ready to fall on anything that comes
  out past it; the guards of the quiet gates join the stack (a rider or a
  small guard left as each gate's token, a unit sent back if a second
  attack develops there); the riders and the stack's tail hold the plaza
  and counter-attack anyone reaching it; wall archers keep to the stretches
  over the gate; a tired front is relieved by the unit behind it (Average
  while it fights, Skilled between waves); open gates with nobody in their
  mouth are shut, a sally's behind it. One rule changed with it: a
  defending unit that routs inside the walls runs to the inside of the shut
  gate farthest from the enemy instead of along the street paths to its
  map edge, which had led routers out through the breach into the
  attackers queuing there (`BattleSim.ROUT_INWARD`, a lever like the wall
  levers). Equal-force walls 1 went from 80-100 % attacker wins to 30-60 %
  (10 seeds; 46-60 % over 30); walls 2-3 now go to the defender 80-100 %
  of the time, below their targets (docs/STATUS.md item 4).

### Field works and the fortified camp (as built, 2026-10-09)

Stakes, caltrops and the fortify stance's camp (STATUS item 4f, point 2;
asked for by the co-op partner). Code: `sim/battle_sim.gd` (per-kind
tables `EQ_*` and the section "field works" at the end), `sim/scenarios.gd`
(`camp`, `works_allowance`), `sim/battle_ai.gd` ("field works"),
`sim/lockstep.gd`, `campaign/cbattle.gd` (`works_of`, `workshop_level`),
`game/works_layer.gd`, `game/battle.gd` / `game/hud.gd` (palette),
`game/overlay.gd` (ghosts), `game/campaign/battle_screen.gd` (the card line).

- **Pieces.** Four new kinds in the `q_*` tables: `EQ_STAKES`,
  `EQ_CALTROPS`, `EQ_DITCH`, `EQ_RAMPART`. A field work is an oriented
  rectangle: middle `q_x / q_y`, `q_face` (the way its front faces),
  `q_len` along the line, `EQ_FW_DEPTH` across. States `Q_FIXED` (standing
  for the battle) and `Q_STOWED` (its side has not placed it). Every rule
  reads the kind's fields, never the kind:

  | field | stakes | caltrops | ditch | rampart | meaning |
  |---|---|---|---|---|---|
  | `EQ_FW_LEN` | 20 m | 10 m | scenario | scenario | length when placed |
  | `EQ_FW_DEPTH` | 3 m | 10 m | 4 m | 4 m | depth across |
  | `EQ_OWN` | 1 | 0 | 1 | 0 | its own side is hindered too |
  | `EQ_SLOW_FOOT / _RIDE` | 50 / 25 % | 60 / 35 % | 45 / 30 % | - | pace inside (foot / riders and beasts) |
  | `EQ_CROSS_T` | - | - | - | 50 ticks | an enemy climbs its 4 m in 5 s |
  | `EQ_STOP` | 100 | 25 | 100 | 100 | charge momentum lost a tick inside |
  | `EQ_DMG_FOOT / _RIDE / _BEAST` | 0 / 5 / 3 % | 6 / 12 / 8 % | 0 / 3 / 2 % | - | % of full hp stepping in; a charging rider x (100 + momentum) / 100 |
  | `EQ_KNOCK` | 40 | - | 50 | - | % x momentum / 100 a charging horse is thrown |
  | `EQ_HP` / `EQ_USE` | 400 / - | 300 / 1 a man | - | 900 | hit points; caltrops: a stock used up a man at a time |
  | `EQ_HACK` | 1 | - | - | - | hp a tick per enemy foot soldier standing in it (12 at most) |
  | `EQ_BURN` | 1 | 0 | 0 | 1 | fire takes it (wooden) |
  | `EQ_HIDE` | 0 | 1 | 0 | 0 | hidden from the enemy until one of its men steps in |
  | `EQ_H` | - | - | -1.5 m | +2 m | height of the ground inside it |
  | `EQ_COVER` / `EQ_RANGE` | - | - | - | 12 / 8 % | its side's men on it: missiles from men not on one stopped; missile range more |

  Rationale, once: stakes stop horses dead and cost a rider a few % of
  his hit points (more at the gallop) but only make foot pick their way;
  caltrops are the horse's and the elephant's bane and are trodden in;
  the rampart is a makeshift wooden palisade on an earth bank (Rome 2's
  fortified army), about half a walls-1 wall: 2 m against walls 1's 5 m,
  half walls 1's battlement cover (25 -> 12 %), half walls 2-3's range
  bonus (walls 1 has none); the ditch is the settlement ditch's pace
  (`DITCH_SPEED` 45 %). **Needs tuning** (no balance run): all of these.
- **Each tick** (`_update_works`, after the men moved; in index order of
  pieces, units, slots): a man inside a piece has his step this tick cut
  to its pace (`EQ_SLOW_*`) and, an enemy on a rampart, to the climb
  (`EQ_CROSS_T`); his formation's anchor keeps to the slowest pace its men
  had (`u_fws`, `u_fwc`, hashed) so the unit does not run ahead and drag
  them through. Stepping in (he was outside last tick) he is wounded and
  uses up the stock; a rider loses `EQ_STOP` momentum each tick inside
  (`chg` and the unit's `u_mom`: a charge that meets stakes or the ditch
  has nothing left to hit with). Enemy foot standing in stakes (moved less
  than `FW_HACK_STILL` this tick, i.e. not crossing) hack them down. A
  piece at 0 hp (hacked, used up, burnt) is wrecked: no effect any more (a
  palisade section burnt down is a gap). Fire: a fire missile within
  `FIRE_R` of a wooden piece's rectangle sets it alight (`EQ_BURN`), the
  existing fire chip burns it.
- **Height.** A camp's ditch and rampart have `EQ_H`; with any (`fwh_on`)
  the ground height every height rule reads is `gh_at` = terrain + the
  works' height: melee from above / below (`_height_bonus`, per-mille
  roll), the charge uphill (`_impact`), range from height (`range_h`,
  `_shot_ok`, unit elevations), on a flat map too. Missile troops whose
  middle is on their rampart get `EQ_RANGE` % more at men not on one
  (`_works_rb`); a missile striking a man on his side's rampart from a
  shooter not on one is stopped `EQ_COVER` % of the time
  (`_works_cover`). Line of fire ignores the works.
- **Scenario keys.** `"stakes"` / `"caltrops"`: [side 0, side 1] pieces
  each side gets to place (stowed at setup); `"field_works"`: [[kind, side,
  x_m, y_m, facing, len_m], ...] standing from the start (tests);
  `"fortified"`: side, the camp `Scenarios.camp` builds round that side's
  units: a rampart 14 m beyond their box on the front and both flanks and
  behind them when there is room (12 m) before its map edge, in sections
  of at most 20 m (each burns on its own), **open gaps only** (no gates:
  two 10 m gaps in the front, one in the back), the ditch 4 m outside it
  (round the front corners). Field maps only (no settlement). Battles
  without any of these keys hash and play exactly as before (`fw_on`).
- **Deployment.** `ORDER_WORKS {side, equip | kind, x, y, facing, on}`
  (deployment phase only; `works_rule`, shared with the view's ghosts):
  places the first stowed piece of `kind` (or moves / turns piece `equip`)
  inside the side's zone (clamped), or takes it back (`on` 0); the camp's
  pieces are the scenario's. Live: the lockstep feeds it with the issuer's
  side (`side_of`), so a player places only their own side's works. The
  battle AI places its side's at the start (AI.md 22). Once the battle
  starts they stay where they are.
- **Visibility.** `q_seen`: bit per side that knows a piece (its own; any
  piece not hidden; caltrops once an enemy man stepped in). Both peers
  hash the same bits; the view draws a piece only for a side that knows it
  (`works_known`).
- **Entitlement** (`Scenarios.works_allowance`): by Workshop level 0 / 1 /
  2: none / 2 stakes lines / 4 lines and 2 caltrop fields (a workshop's
  carpenters and smiths), plus a fortified army's own 2 lines and 1 field
  (cut on the spot, whatever its workshop). Campaign: each side by its
  lead faction's best Workshop over its regions; custom battles: "Field
  works: none / 2 stakes / 4 stakes, 2 caltrops" for both sides and
  "Fortified: none / side 1 / side 2".
- **View.** `game/works_layer.gd` under the soldiers (both soldier paths):
  the ditch dark, the rampart an earth bank with a palisade of posts and a
  plank along its outer edge (charred stumps once burnt down), stakes a
  row of short diagonal stakes leaning at the enemy, caltrops scattered
  dots (fewer as used up) for sides that know them; fire flicker as for
  other wooden things. Deployment palette under the deployment bar:
  "Stakes n" / "Caltrops n" (left to place), "Rotate", "Remove" (toggles);
  armed, a tap in the zone places a piece facing the enemy, a drag lays a
  stakes line along it ("STAKES FACE THIS WAY" preview), a second tap on a
  placed stakes line turns it an eighth, Remove takes one back; pending
  placements are drawn as ghosts where the rule puts them. The campaign's
  pre-battle card: "The defenders are fortified: ..." and "Field works
  (placed in the deployment): attackers ...; defenders ...". UI icons
  stakes, caltrops, palisade, rotate.
- **Not modelled / gaps:** the AI does not read the enemy's works (its
  cavalry may charge stakes; it never hacks stakes or burns the palisade on
  purpose); no stakes or camps in settlement battles; a placed piece may
  overlap units or other pieces (the first piece in index order counts
  where two overlap); the palisade does not block movement (the climb and
  the ditch do the work) and nobody can be ordered "onto" it like a wall.

### Mantlets (as built, 2026-10-09)

A moveable wooden missile screen (STATUS item 4f, point 4): a plank
shield on a frame about 6 m wide that a foot unit carries and sets down
facing the enemy; its side's men behind it are sheltered from missiles
coming through it. The ram's roof generalised. Code: `sim/battle_sim.gd`
(per-kind tables, section "mantlets" at the end, hooks in `_land`,
`_land_bolt`, `_drop`, `_update_equip`, `pickup_refusal`, `state_hash`),
`sim/siege_ai.gd` (section "mantlets"), `sim/scenarios.gd` (`settlement`
"mantlets"), `campaign/cbattle.gd` (`MANTLETS`, `siege_equipment`,
`equipment_text`), `game/campaign/battle_screen.gd` (`mantlet_line`),
`game/custom/*` (per-side option), `game/overlay.gd` (`_draw_mantlet`),
`game/hud.gd` / `game/battle.gd` (texts), `game/ui_icons.gd` ("mantlet").

- **Piece.** `EQ_MANTLET` 9 in the `q_*` tables, a column in every per-kind
  table; the rules read the fields, never the kind. States `Q_GROUND`
  (standing at `q_x / q_y` facing `q_face`, sheltering), `Q_CARRIED`,
  `Q_WRECKED`; no planted state. `ORDER_DROP` leaves it standing at the
  unit's anchor (the middle of its front) facing the unit's facing (also
  when its carriers rout or die); `ORDER_PICKUP` (or a tap on it) carries
  it. Any foot unit of either side (`EQ_ANY`: taken by the enemy it
  becomes theirs, `q_side`); not cavalry, camels, elephants, engines, and
  no mounted or dog row ("Only men on foot carry a mantlet"). Carriers
  walk at their walk, never run, shoot nothing and fight at 60 % (as for
  any piece). New fields:

  | field | mantlet | meaning |
  |---|---|---|
  | `EQ_HP` (`MANTLET_HP`) | 600 | hit points: two stones (330) or nine bolts (70) landing within 3 m wreck it |
  | `EQ_ROOF` / `EQ_ROOF_R` | 40 % / 6 m | carried: arrows landing on its carriers this near it stopped (the roof rule; `EQ_ROOF` now holds the % per kind, ram / wagon / tower 70) |
  | `EQ_SCREEN` (`MANTLET_COVER_PCT`) | 60 % | standing: arrows, sling stones and javelins about to strike a sheltered man stopped |
  | `EQ_SCREEN_BOLT` (`MANTLET_BOLT_PCT`) | 30 % | ... bolts (the bolt ends in the screen); stones 0 % |
  | `EQ_SCREEN_W` / `EQ_SCREEN_D` | 6 m / 6 m | the sheltered rectangle: 6 m along its line, 6 m deep behind it (since 2026-10-10 along its line `q_len`, the carrying unit's frontage: "Siege equipment usability") |
  | `EQ_WALK_PCT`, `EQ_ANY`, `EQ_SHOT`, `EQ_BURN` | 100, 1, 1, 1 | walking pace, either side, bolts / stones hit it, fire takes it |

- **Shelter rule** (`_screen_cover`): a missile about to strike a man
  (`_land` after the wall, roof and palisade covers; `_land_bolt` for each
  man on the bolt's line) is stopped by the first standing mantlet (index
  order) of the man's side whose rectangle he is in, if the shooter
  stands in front of its line, `EQ_SCREEN` / `EQ_SCREEN_BOLT` % of the
  time (`stat_mantlet_cover`, not hashed). Men on either side may stand by
  it; only the back is sheltered. Line of sight is unaffected; stopped
  arrows do not damage it. Fire missiles set it alight as any wooden
  piece; bolts and stones landing on it batter it (`_ram_hit`).
  Carried: the roof rule (`EQ_ROOF` 40 % within 6 m; on plain maps the
  roof is read only in battles with mantlets, so others play as before).
- **Scenario / entitlement.** Key `"mantlets": [side 0, side 1]` (at most
  8 each): at setup standing `MANTLET_AHEAD` 2 m before the side's missile
  and artillery units (dealt in turn, side by side 7 m apart; none: any
  unit of the side; tower engines never), facing their way, after every
  other piece (`mt_on`; `q_face` is hashed then, battles without the key
  hash as before). Campaign: an assault after 2 siege turns brings 2,
  after 3 four (any wall level; `CBattle.MANTLETS`, no state); campaign
  field battles none. Custom battles: "Mantlets: none / 2 / 4" per side,
  field and settlement maps.
- **AI** (docs/AI.md 23): the settlement attackers carry them to 2 m
  before their missile units' posts on the line they shoot the wall from
  (one a unit, the middle first), then before their scorpion batteries,
  the rest before the heavy batteries (none of those: 60 m from the
  attacked gate), and set them down facing the wall; a set one is carried
  again only when its line moves. The defenders and the field battle AI
  do not use them.
- **View.** A brown plank bar 6 m wide across its facing with a lighter
  plank face on its front and two posts behind; carried, at the carriers'
  front; charred with a cross when wrecked; fire flicker as for other
  wooden things (`_draw_fires`). Pick-up preview "PICK UP THE MANTLET",
  card "carrying a mantlet", "Taking the mantlet", Drop as for any piece.
  UI icon "mantlet" (custom option, the pre-battle card's "Mantlets: n for
  the attackers ..." line). Overlay drawing, both soldier paths.
- **Measured once** (scratch probe, fair siege walls 1 ring, ladders + ram,
  3 seeds, 4 attacker mantlets vs none): see STATUS. In a field set piece
  (two 80-archer units shooting at will, two mantlets before one) the
  screened unit lost 11 men in 75 s against 32 without, 39 arrows stopped.
- **Not modelled / gaps:** the defenders and the field AI ignore them; no
  sheds (a roofed mantlet against stones); enemy foot do not smash a
  standing mantlet (only fire, bolts and stones); one screen per missile;
  a mantlet does not block movement or line of sight. **Needs tuning (not
  done):** every number above.

### Siege equipment usability (as built, 2026-10-10)

The owner's playtest notes (STATUS, 2026-10-09): siege equipment could only
be taken up once the battle ran, a 6 m mantlet covered a few files and
nothing showed where to stand, and carriers walked in their ordinary block.
Three parts. Code: `sim/battle_sim.gd` (`EQ_CARRY_F`, `carry_files`,
`_base_files` / `files_of`, `deploy_pick_rule`, `pickup_refusal`'s
deployment checks, `_drop` / `_mantlet_set`, `mantlet_len`, `mantlet_hp`,
`_screen_near`, `_mantlets_at_setup`, `_place_unit`, `_apply_orders`),
the view (`game/battle.gd` `_queue` / `_tap_equip` / `_refresh_wall_buttons`,
`game/overlay.gd` `_fv` / `_draw_mantlet` / `_draw_mantlet_cover`,
`game/hud.gd` `carry_note`), tests `tests/determinism_test.gd --only=carry`,
`tests/lockstep_test.gd --only=siege` (`_test_lockstep_siege_deploy`).

- **Pick up and drop in the deployment phase.** `ORDER_PICKUP {unit,
  equip}` is accepted in the deployment (`deploy_pick_rule`, shared with
  the order preview, like `place_rule` / `works_rule`): a unit of the side
  that owns a piece lying in its zone takes it at once and is placed with
  its anchor at the piece, facing as it faces, in the piece's carry
  pattern; refused (`pickup_refusal`, the view's flash) for the other
  side's piece ("Not your side's: take it in the battle"), a piece outside
  the zone, or a placement inside another unit ("Another unit stands
  there": pieces lie in a row behind the line, so a column taking the ram
  may cover the siege tower behind it). The carrier and the piece then
  move as a pair with `ORDER_PLACE` (the placement is checked in the carry
  pattern; the piece follows the anchor in `_place_unit`). `ORDER_DROP` in
  the deployment puts the piece down where the unit stands and stands the
  men in their ordered formation at once. Engines are still taken up in
  the battle only. Through the lockstep as ordinary unit orders; nothing
  new is hashed (the pieces and `u_carry` already are). The view lets
  Pick up (a tap on a piece with units selected) and Drop through in the
  deployment ("Assigned to the ladders: a file a ladder (5)"); the order
  preview draws the pending pair (the unit's footprint in its pattern at
  the piece). There is no separate Pick up button: the tap is it. The AI
  does not pre-assign in the deployment (the siege AI starts with the
  battle on settlement maps; its plan counters are unchanged).
- **Carry patterns.** While a unit carries a piece its formation's files
  are the piece's (`files_of` -> `_base_files` -> `carry_files`, derived
  from the piece's kind each tick, no hashed field of its own; `u_files`
  keeps the ordered frontage, so the unit reforms into it when it puts the
  piece down). Every formation rule that reads the files (offsets, the
  flow and queue code of "Units flow into the space", the squeeze, the
  occupancy grid, depth / width) sees the pattern. Pick-up, drop, a
  wreck, planting and a rout lay the places out afresh (`_carry_changed`).

  | piece | `EQ_CARRY_F` | pattern |
  |---|---|---|
  | ladders | `LADDER_SET` 5 | a file a ladder behind the set |
  | ram | `RAM_FILES` 4 | a column behind it, the crew at the beam |
  | siege tower | 8 (its lanes) | a column behind it, ready to cross |
  | mantlet | 0: its line's length / the carriers' file spacing | the ranks behind the panels |
  | wagon | `WAGON_FILES` 4 | a column with it (its crew of 8-10: two or three ranks) |

  The HUD shows it beside the order buttons ("Carrying a ram: column of
  4", "Carrying ladders: a file a ladder (5)", "Pushing a siege tower:
  column of 8", "Carrying a mantlet: 20 files behind the panels", "With
  the wagon: column of 4"); the drag preview draws a carrier's ghost in
  its pattern.
- **Mantlets sized for a unit.** A mantlet put down (an order, its
  carriers routing or gone) becomes a line of panels along the carrying
  unit's front at its ordered frontage: `q_len` = files x file spacing,
  at least `MANTLET_W` 6 m, at most `MANTLET_MAX` 40 m (`mantlet_len`);
  the cover rectangle is that long by `EQ_SCREEN_D` 6 m deep behind it
  (`_screen_cover` reads `q_len`); full hit points `MANTLET_HP` 600 a 6 m
  (`mantlet_hp`; re-sized, it keeps its share of them); a bolt or stone
  landing within `RAM_HIT_R` of its line (`_screen_near`) hits it. Still
  one piece (one `q_*` entry, `q_len` as the field works use it, now
  hashed with `q_face` when the battle has mantlets); picked up again it
  is carried as one piece, its carriers in as many files as the line is
  long. Scenario `mantlets` at setup: each laid before its unit at that
  unit's frontage (shared side by side when a unit gets more than one).
  80 archers in 20 files put down a 26 m line (2,599 hit points). View:
  the plank bar drawn at the length (carried too, before the front rank);
  a selected unit carrying one shows the cover it would give if put down
  now (dashed), and the primary selected unit shows the cover behind its
  side's standing mantlets. The siege AI is unchanged: its carriers' own
  frontage gives the width.
- **Measured** (`--only=carry`, 80 archers under 80 enemy archers shooting
  at will for 60 s): a 26 m line stopped 174 missiles and the unit lost 18
  men; a 6 m line before the same unit (put down in 4 files, then the unit
  placed again in its 20) stopped 42 and it lost 40.
- **Gaps:** the AI does not take pieces up in the deployment; the group
  move (three fingers) ghost draws the ordered frontage, not the pattern;
  a wagon's column is not drawn alongside the wagon (the wagon rides at
  the anchor like every piece).

**Roads, rivers and hills (2026-10-09, static data, still format 6).** The
grid carries three layers baked from hand-drawn lines on the map: a
terrain override per cell (hill 15 / ridge 20 where a range is rougher
than its region's own terrain; the Alps' foot is ridge, the high Alps stay
unclaimed land), a road flag (a road cell costs 6, so a road is two thirds
again as fast as open ground: the Via Appia takes foot from Roma to
Tarentum in one turn) and rivers as edges between cells: a step across a
river is not a step except at a named crossing, a ford costing 5 more
than the cell entered and a bridge nothing extra; a diagonal never crosses.
Every search reads one step table, so paths, reach, the AI's distance
fields and the move preview obey it without their own code. Rivers end
on a coast, so the land on either bank stays connected round the source;
the crossings decide where armies meet. A field battle fought across a
crossing carries the crossing (id, ford or bridge, a seed from the id
alone, the bank the defender holds) for the dedicated crossing map, and a
battle on a hill cell is fought on hill ground, so high ground on the
overworld is a real position.

### Battle-map landforms and shaped settlements (as built, slice 2d, 2026-10-14)

Why (user, 2026-10-14): "The towns also don't need to be perfectly
circular. They can have some shape to them. ... Cliffs, rock outcroppings
and forest formed with the landscape that the towns were built around or
actually look like they utilize would really add to the visuals."

Code: `sim/landforms.gd` (new: cliffs, outcrops, sea cliffs, the pocket
check, the woods' terrain terms), `sim/mapgen.gd` (`build`: landforms on
field, crossing and settlement maps, the field graph `_field_nav` /
`_graph`, `_river_cells`, `_blob_long`, `shape_of` / `shape_pm`, the
shaped outlines in `plan_outline`, `_flip_land`), `sim/terrain.gd`
(`_rise` / `_spur` follow the town's shape), `sim/battle_sim.gd` (cell
kinds `C_ROCK` / `C_CLIFF`, `obs_hi`, `land_only`, `obs_sat`, the field
graph, squeeze, placement), `game/land_layer.gd` (new: drawing),
`game/terrain_layer.gd`, `game/tree_layer.gd`.

**Scenario key.** `terrain.landforms`: 1 (default) or 0 (the maps exactly
as before this slice: no landforms, the old woods, round outlines; for
tests and set pieces). Landforms need generated hilly ground: kinds
rolling, ridge, valley, hill, slope (a campaign battle's kind is its
region's terrain or its cell's hill / ridge override, so the campaign's
real relief drives them); never on flat, custom or `sym` maps. The ring
plan (`PLAN_RING`, the sandbox default) and the castrum keep their
outlines; no rules or keys change for the campaign (`CState.VERSION`
unchanged; `campaign/` untouched).

**Generation** (integers only, `sim/landforms.gd`'s own xorshift, fixed
order; built once at setup with the rest of the map, canonical frame, so
both lockstep peers build the same and nothing is sent):
- *Cliffs*: seeds among the steepest 6 % of the height nodes (and at
  least 10 % grade), best of 14 draws; traced both ways along the contour
  (2 m steps, turning at most 13 degrees a step and 105 in all, so a cliff
  never curls round) while the ground stays two thirds that steep, 26-64
  m drawn, kept if 16 m or more; cells within 2.2 m of the line become
  `C_CLIFF` (a band about 4 m wide). Most per kind (flat, rolling,
  ridge, valley, hill, slope): 0 / 1 / 3 / 2 / 2 / 2 (half to all of
  that drawn), one more on rocky ground. Each point carries its downhill
  angle and a face height (1.4-4.5 m from the grade; view, and the field
  slice 2b will read for sight).
- *Sea cliffs* (coastal settlements on a hill or spur, or rocky ground):
  runs of 30-70 m along the shore just inland of the water, gaps 18-40 m,
  never by the city (its width + 40 m each side) or its approach.
- *Outcrops*: 0 / 5 / 12 / 6 / 10 / 8 by kind, x 1.0 / 1.25 / 1.1 / 0.7 /
  1.5 by palette (plain, arid, dry, green, rocky), 75-125 % of that drawn;
  each the best of 8 draws by grade, height above the ground round it
  (crests) and a random term; a boulder of radius 1-3 m and up to two of
  1 m against it (`C_ROCK`, 2-8 m across); 4 in 10 get a second outcrop
  10-16 m away (they come in groups).
- *Clearances*: 18 m from the field's edges; a cliff 12 m, an outcrop 7 m
  (plus its size) from every other landform, the deployment areas (the
  centre 70 % of both deployment bands on a field map; the approach
  corridor and the attackers' ground on a settlement map), a settlement's
  fields and orchards, its walls (half the wall + a tower + 18 m outside
  the outline; past the ditch at walls 3; 1.4 x the radius round an open
  town), the sea and a river (its half width + 8 m, the crossing's 60 m
  approaches). Landforms therefore never close off ground between
  themselves, the edges, walls or water; a flood fill from the attackers'
  ground (4 m blocks, gates open) drops any cliff that would anyway.
- *Woods that follow the land* (every map with landforms and woods): the
  big blobs of the old generator lie along the contour where they grow
  (1.7 x long, 0.6 x wide, amplitude 800), then terrain terms instead of
  the old "woods favour rises" one: +70 a metre a 4 m cell lies below the
  mean of the 52 m round it (valley floors and hollows, up to 450), +12 a
  metre below the map's mean (200), +140 on the lower slopes (5-18 %
  grade), -260 on steep faces (over 22 %), the lee of the ridges (a wind
  drawn from the seed: up to +220 on ground falling away with it), a band
  along a river's banks (4-45 m from the water, up to +320), a fine hash
  noise (+-120) for ragged edges; no trees on rock, nor within 4 m of a
  cliff. The histogram thresholds are as before, so a map's woods cover
  the same share (forest x 0.55 %). The settlement's cleared ground,
  fields, orchards and approach stay as they were.
- *Graph*: on a field map with landforms, a lattice of nodes 48 m apart
  on open ground plus nodes round each landform (beyond a cliff's ends,
  8 m either side of it, 5 m round an outcrop), edges as the street
  graph's (clear 3 m lines up to 48 m, pieces joined); on a crossing the
  landforms' nodes join the river's graph; on a settlement map the street
  graph's `extra` nodes. Generation (desktop): field maps 70-85 ms (8 ms
  before); settlements 132 ms mean, 450 ms worst over 1,728 plan x site x
  coast x walls x level x seed maps (66 / 136 ms before); `_join_components`
  now picks its candidate pairs one at a time instead of sorting them all
  (the same pairs in the same order: maps without landforms are byte for
  byte as before, graphs included).

**Rules.** Rock and cliff cells are impassable to everyone (`_nav_of` 0);
units path round them over the graph (the settlement maps' path code:
straight where a 3 m line is clear), their men flow round them (`_flow_slots`,
`_slide`), a move or a deployment placement on one goes to the nearest
open ground (`open_snap`). Missiles passed over them (`_obs_top` 0) until
slice 2b gave them cover and sight ("Cover and line of sight": an outcrop
or half a cliff's face now stops flat shots and sight beyond 5 m of
either man); `obs_hi` (static) is 0 on maps whose
obstacles are only water, rock and cliff with line of sight off (`los`
0), so lines of fire there keep the tight ground-only loop. A rock or cliff on one side of a unit is not a
street: `_squeeze` closes files only for a gap with something on both
sides. On a field map whose only obstacles are landforms (`land_only`,
static): routers flee as in the open (the settlement maps' path to the
edge is not used), a unit is "near an obstacle" (`_u_obs`: its men
checked against the cells, flows, squeeze, lag) only with a landform
within 4 m of its box and anchor (4 m cells, `land_sat`; elsewhere 16 m
cells and 8 m as before), the stuck counter runs only for units near a
landform (so the stuck release never regroups a unit in the open), the
anchor's obstacle check is skipped away from them, and men search for
targets and keep them as in the open (no reach test over a boulder or a
cliff's foot, no 16 m block counts; a man in the fight blocked by one
moves along it on one axis or stays, without `_slide`'s trail walk).
`_near_obs` reads a summed-area
table of the 16 m obstacle cells (`obs_sat`, static, the same answer as
the old scan). The cells are in `obs`
and so in `map_hash` (state hash from tick 0); the view data
(`map_info["land"]`) is not hashed (derived); new statics are rebuilt by
setup and left out of snapshots.

**Shaped settlements.** `shape_of(city, kind)` (its own draws from the
city seed, so every other draw of the plan is as it was): a radius per
mille by angle = 1000 - elongation x cos 2a + three harmonics (10-70, 40-100,
20-65 per mille), less its mean. A spur town runs long down the spur
(elongation 140-210: narrow across, long toward the neck), a hill town
and a town on the shore along the contours or the shore (-70..-140,
-90..-150), others +-60. Applied to the polis (vertex radius 90-106 % x
shape), punic (94-106 % x shape) and oppidum (the oval x shape, its
funnel included) outlines, at most the old 112 % of the radius (field
sizes unchanged). The ground follows: the hill's rise and the spur's
edge use the same shape (the brow 32 m behind the walls instead of 45 on
a hill), so the walls trace the brow; the acropolis / Byrsa goes to the
high point (on a hill or spur: within 25-70 of straight back, the hill's
top at 40 % of the radius), the main street grid of a hill polis / punic
town runs along the contours (a third of its angle). Gates, towers,
stairs, wall stretches, posterns, the coast cut, the citadel fitting and
the street graph are the existing polygon code, unchanged.

**View** (`game/land_layer.gd`, a child of the terrain layer after its
decals: over the ground, under the cover, trees, works and soldiers;
drawn once): a cliff is a soft drop shadow down the slope, a face band
(1.6 m + 0.7 x its height wide, lighter at the brow and darker at the
foot, shaded by how it turns to the light from the upper left, tapered
at its ends), hachures (rock ribs and gullies, about every metre), scree
at the foot, a dark lip and a lit brow line; an outcrop is a shadow and
irregular boulders (nine-sided, radius jittered) with a lit facet, a top
highlight, a crack and an outline. Rock colour: the palette's rock a
fifth toward its ground. Graphics Low draws faces, boulders, shadows and
the brow only (live). The ground cover glyphs (tufts, scrub) skip rock
cells. Both soldier render paths are unaffected (canvas drawing).
Also fixed here: the sea and the ditch had not been drawn since the
2026-10-10 visual upgrade (the shader's `sea_on` was never set); coastal
towns show their sea again.

**Measured** (desktop, another agent's runs alongside; scratch harness
`landforms/harness.gd`: AI vs AI, 5 min field / 10 min settlement
battles, before -> after on the same scenario):
- No golden changed: `determinism_test`, `custom_battle_test`,
  `battle_screen_test`, `lockstep_test`, `campaign_test`, `pack_test` pass
  unchanged (their pinned trajectories are flat or settlement-free maps);
  `campaign_sim` hashes unchanged (cdc1d805 32b83031 23f9ed4f 3237d82d
  a42fc685 b6fe6c2e: the campaign auto-resolves without the battle sim).
  Maps with `landforms: 0`, flat maps and `sym` maps are byte for byte as
  before (heights, woods, cells, graphs, outlines; 54 maps checked).
- Sanity, 17 scenarios + 30 campaign-like maps a pack (regions drawn
  from each pack, half settlements on their own ground, plan and coast
  with ladders, a ram and a tower; a third of the field battles at a
  crossing): Rome 14 cliffs and 97 outcrops on 15 field maps, 29 / 97
  round 15 settlements; West (mostly flat) 2 / 20 and 20 / 48; no unit
  unreachable at the start (flood from side 0, gates open) on any map;
  units stuck over 30 s 3 -> 3 (scenarios; the crossings' as before),
  Rome fields 1 -> 2, settlements 7 -> 3, West 1 -> 2 / 0 -> 1; sieges
  decided in 10 minutes 12 -> 12 (Rome), 14 -> 14 (West), mean minutes
  unchanged. Long sieges (20 min, 6 city seeds each): polis on a hill
  3/1/2 (attacker / defender / draw) -> 4/2/0, oppidum on a spur 6/0/0 ->
  5/1/0, punic coastal hill 4/2/0 -> 4/1/1; every scenario siege decided.
  Ladder probe (`tests/ladder_probe.gd --quick --plans=1,2,3`): 853 of
  853 points the rule allows climbed (835 of 835 before).
- Settlement survey (1,728 maps): outer gates identical on every map,
  citadels 548 -> 544.
- Time per tick: the harness means, field / settlement, Rome +6.2 % /
  +2.3 %, West +4.8 % / +13.3 % (one jammed oppidum gate fight; a West map
  with no landforms read +40 % from load alone), scenarios +2.5 % / +3.4
  %. Same armies, 12 maps (4 terrain seeds x ridge, hill, rolling),
  landforms on vs off: +7.9 % ridge, +8.5 % hill, +1.6 % rolling (+6.0 %
  all); the battles differ, the cost is men meeting rocks (`_slide`:
  0.12 ms a tick on a ridge map before the cheaper fight slide, which
  took the ridge / hill figures from +11.5 % to +8 %), paths and flowed
  places near them (~0.05 ms). Over the slice's +5 % aim on ridge and
  hill maps: fewer outcrops in the battle band, or a cheaper slide for
  marching men, would bring it down. `bench_4000_hills` (3 outcrops): phases
  within 1 %.

**Open.** No settlement stands on a river (city maps have no river;
river crossings are field maps): "a town on a river bend" needs a city
+ river map. The campaign's "View battle map" preview
(`game/campaign/city_preview.gd`) shows the new outlines but not the
rocks and cliffs. Cliffs do not change the height grid (no step: they
sit on the steepest existing ground). Cover and sight from rocks, cliffs
and woods: slice 2b.

### Routs among walls and houses (as built, pathing phase A, 2026-10-15)

Why: playtests showed routers shaking on the walls and at the gates
(docs/PATHING_SPEC.md sections 1-2: rout jitter 78-80 % of men coming off
a wall, 22 % in a town; routing units stationary 20-38 % of their time in
the polis / punic / town / city sieges; a router never counted as stuck).
Root causes R1-R5 of the spec: one flee vector for the whole unit aimed
from its centroid (it flipped sign every tick at a stair foot or a shut
gate), routers on a stair move ignoring the stair's trail, slides without
memory (a face met square on, a concave corner), no end state for routers
with no way out, rally anchored on the centroid. Code: `sim/battle_sim.gd`
(section "routers: exit fields, huddle": `_xf_restart`, `_xf_tick`,
`_xf_begin`, `_xf_next`, `_xf_build`, `_xf_restore`, `_xf_dir`, `_xf_unit`,
`_hud_start`, `_hud_step`, `_huddle_slots`, `_anchor_man`, `_rout_stats`,
`_slide_mem`, `_free_mem`; hooks in `_flee_step`, the routing loop of
`_update_soldiers`, `_slide`, `_rally`, `_regroup`, `_charge_state`,
`_gate_cells`, `restore`, `result`). Probe `tests/pathing_probe.gd`;
set pieces `tests/determinism_test.gd --only=rout`.

- **Exit fields (A1).** On settlement maps (`obs_on`, not landform-only
  maps) the sim keeps integer distance fields over the 2 m nav grid: per
  side to its exit cells (its own edge row; a coast's defenders: the land
  at either side edge) and per outer gate shut to its inner mouth (the
  refuge of `ROUT_INWARD`, kept to the ground inside: its piece with every
  gate shut). A flood over the 4 neighbours, 10 a step (so distances along
  the grid; a man steps toward the lowest of his cell's 8 neighbours, a
  diagonal only where both cells beside the corner are open, ties to the
  lower direction). Each man of a routing unit walks down its field at
  the unit's run (the old per-man skew at a quarter); at an exit cell he
  runs on over the edge, at the refuge he stops. Down a field there is no
  flip and no square-on stall. A man off the field (a blocked cell, a gate
  shut since) steps onto its lowest neighbour, else takes the unit's flee
  vector, which stays for the view's facing and on maps without fields
  (field and landform-only maps play their routs exactly as before).
- **Generations.** The fields of a generation are pure functions of the
  static map and the gates' states (`xf_gl` live, `xf_gp` building, bit g
  gate g open). A gate opening, closing or breaking (`_gate_cells`) starts
  a new generation at `xf_t0 = tick`; it builds `XF_CELLS` 1,000 cells a
  tick (about 0.4 ms desktop; 45-80 ms of work a generation on the siege
  maps) and takes over at `xf_t0 + XF_TICKS` 250, finished then at once if
  need be, so peers agree whatever their speed; meanwhile routers walk the
  last generation (none in the first 25 s: the old flee vector). Hashed:
  `xf_t0`, `xf_gl`, `xf_gp`; the fields themselves are derived (skipped in
  snapshots; `restore()` rebuilds the live and the building generation in
  full, 50-80 ms each).
- **Refuge (defenders inside, `ROUT_INWARD`).** The shut gate is chosen by
  `_rout_gate` as before (on its own ground, farthest from any enemy, none
  within 30 m), from the stair's foot for a unit still coming down, and
  then kept (`u_xg`, hashed) until its gate opens (before, the choice was
  made again every second and flipped as the enemy moved: men turned about
  every 5 s); with none, one is looked for every 5 s.
- **Off the wall man by man (A2).** A routing unit on a stair move sends
  each man still on the walkway, a tower or the stair along the stair's
  trail (`_stair_goal`, the call the ready path uses) with the stair's
  cell mask; once on the ground he takes the exit field. `_stair_check` is
  unchanged. (Before: the unit's vector to the stair foot flipped about
  the centroid and men bobbed on the walk until `STAIR_MAX`, 40 s.)
- **Huddle and surrender (A3).** Once a second a routing unit with fields:
  when half its men on the ground are within `HUDDLE_R` (6 m along the
  grid) of its refuge it huddles there (`u_hud` 2 + g, hashed); when none
  of them has a way out (no exit, no refuge reachable: attackers in a shut
  town, ladders gone) it huddles where it is (`u_hud` 1), round its man
  nearest its men's middle on the piece most of them stand on. Huddle
  places: the open cells round the point (a flood, `FLOW_PACK` 125 %
  density, in slot order), the men walking to them at the walk (a
  straggler farther than 12 m from the refuge walks down its field first)
  and then standing, facing the nearest enemy; still `S_ROUTING` (no
  fighting). Out again when its gate opens or the live fields show an exit.
  A final router (`u_routs > MAX_ROUTS`: the plaza fallen) huddled with a
  ready enemy within `SURR_R` 15 m (box to box) gives up: its men leave the
  field as prisoners (`GONE_SURR`, `u_surr`; `result()` reports
  "surrendered" for such a unit). A router that may still rally does so by
  the existing rule. Beasts running amok never huddle.
- **Rally and regroup anchor on a reachable man (A4).** `_rally` (not on a
  stair move), `_regroup` and a charge's re-form whose point falls in a rock
  or a house put the anchor on the man nearest the men's middle on the
  piece most of them stand on (`_anchor_man`), the places flowing round
  what cuts them.
- **Slide with memory (A5).** Per man `s_wf` (a byte, hashed with the
  other obstacle-map state): his last slide's direction, a hold count and
  "stalled last time". Stalled twice running, or sliding back the way his
  last slide went (the 2-cycle of a concave corner), he follows the
  obstacle for `SLIDE_HOLD` 5 ticks: 90 degrees off his wanted step (the
  side he went along it last, else by i & 1), else 135, then the other
  side; a later open step straight back against the way the slide took him
  (the bounce between a corner and a place behind it) becomes such a hold
  too (`_free_mem`). For routers and for the men of standing units (no
  order) away from the enemy; not for men in contact (it made the fights
  at rocks jitter more: 4-5 -> 6-7 % over three seeds), nor on walls,
  stairs or ladders (their own rules).
- **Separation near obstacles (A6).** Men following their places in units
  near obstacles push apart from friends closer than `SEP_SLOT` 0.5 m (a
  quarter push; below the flowed places' 0.57 m and any formation's
  spacing): in contact units every other tick against the contact grid
  (`checked < 10`); otherwise every fourth tick against the man beside and
  the one ahead in the formation (no grid: checking four neighbours every
  other tick cost 10-20 % of a siege tick). Field and open-ground units
  keep the fast path untouched (the golden digests did not move).
- **Routers in the stuck metrics (A7).** A router not huddled whose men's
  middle stays within `STUCK_DIST` counts in `stat_stuck_u` /
  `stat_stuck_max` as a ready unit does, and from 10 s on in
  `stat_rout_still` (diagnostics, not hashed).
- **Measured** (`tests/pathing_probe.gd`, AI vs AI, seed 7, 8 sieges plus
  battle_2000 and bench_4000_hills; see docs/STATUS.md for the table):
  rout jitter 78.8 % (stair) / 6.0 % (town) -> 0.0 / 0.3 %; routing time
  stationary 9.3 -> 0.0 %; stuck over 30 s 18 -> 0 (longest router 149 ->
  0 s, ready 189 -> 26 s); idle near obstacles rev/step 22 -> 2.6 %;
  fights near obstacles 4.2 -> 4.8 % (seeds 8-10: 3.8-4.9 -> 3.9-4.9 %;
  phase C's target is 3 %); inside the drawn footprints 3.5 -> 3.4 %
  (phase B). A balance side effect: in the walls-3 ring siege with a ram
  ("siege_eq_ring3") the gate falls later (battle seeds 1-4: 2499-3493
  ticks, was 2440-2753; at seed 12345 the ram is burnt and the battery
  breaks the gate at 5446, was the ram at 2503); without the exit fields
  it plays as before. Determinism: `--only=rout`
  (rout-wall: off the walk in 9.4 s, rout jitter 0 %; rout-gate: huddled at
  the refuge 19 s after the break, rev/step 0.1 %, all 60 gave up once the
  heavy foot came within 15 m; trapped: huddled in 0.1 s and standing),
  each identical on repeat and across a snapshot taken while a generation
  builds (in rout-gate after a gate broke).

### Clearance off the houses (as built, pathing phase B, 2026-10-15)

Why: men stood inside the drawn houses (docs/PATHING_SPEC.md R6: houses
are rasterised to the 2 m nav grid by cell centre, so a drawn outline
overhangs its blocked cells by up to about 1 m, more on turned quads; the
men's only test was "cell passable"): 3.35 % of the probe's men near a
house stood inside its footprint (polis 7.6 % in the spec's survey), 1.66 %
more within 0.3 m of a face. The nav grid, the street graph's nodes and
every golden stay as they were (spec B3: no conservative 2 m blocking).
Code: `sim/battle_sim.gd` (section "clearance off the houses": `_clr_build`,
`_clr_exact`, `_clr_near`, `_clr_push`, `_clr_places`, `_clr_ok`,
`_near_cl`, `_clr_graph`, `clr_at`; hooks in the four movement paths of
`_update_soldiers`, `_compute_offsets`, `_flow_slots`, `_huddle_slots`,
`_squeeze`, `setup`).

- **The field (B1).** At setup, on maps with drawn buildings (a
  settlement's `map_info.city.buildings`: rectangles, turned quads, round
  houses; or a field map's terrain `blocks`), a 1 m grid: per cell within
  3 m of a building, the exact integer distance from its centre to the
  nearest one (a byte, 3 cm steps, negative inside, capped at 3 m) and
  which building (and a second one where another is within 1.5 m as near:
  in a lane between two houses a man may be nearer either). A man's
  clearance is then measured against those buildings' exact outlines (a
  rectangle's sides and corners, a quad's edges, a round house as its
  circle), with the outward normal; the byte is only the cheap test
  (a cell whose centre is 1.22 m or more off any face needs nothing).
  Built in 6-45 ms (polis / punic, turned quads, the most), skipped in
  snapshots (a function of the map; nothing new is hashed). The face of a
  wall, a tower or a rock is not in it (walls keep their ladder and stair
  rules; landform maps are unchanged).
- **Men off the faces (B2a).** In all four movement paths (routers, the
  slot-following fast path, the lean path and the contact path), after
  his step and the nav test, a man nearer a drawn face than `CLR_MIN`
  0.5 m is put out along its normal to exactly 0.5 m, if he may stand
  there (else he stays). A man pulled in by his place therefore stands
  still on that line (no bounce), and one walking along a face slides
  along it. Not on walls, stairs and ladders (their own rules), and only
  for units whose box comes within 3 m of a house (`_near_cl`, a
  summed-area table of 4 m cells). A standing unit's man pushed back to
  where he stood (a face square across his way to a place behind the
  house) counts as stalled against an obstacle and takes the slide
  memory's wall-follow (phase A5).
- **Places off the faces (B2b).** A formation's place nearer a face than
  0.5 m counts as cut and is laid out again by the flow (`_flow_slots`);
  the flow's and the huddle's spots (`_huddle_slots`) nearer than
  `CLR_PLACE` 0.8 m stay empty; the places left between 0.5 and 0.8 m are
  put out to 0.8 m (else as far as open ground allows, at least 0.53 m),
  so men reach their places without being pushed and their units settle.
  At setup every unit (not on a wall, not a battery) on such a map lays
  its places out again at the end of the first tick, when it knows what is
  near it, and a unit dropped with its anchor inside a house has the
  anchor moved to the nearest open ground (rings of 2 m, up to 16 m): the
  castrum's defenders stood in their barracks, a polis file in a
  house, all battle.
- **Squeeze (B2c).** Among drawn houses `_squeeze` measures the street's
  width a metre at a time to where a man would stand 0.5 m off a face
  (before: 2 m nav cells), so a column closes files to the street a man
  can actually use.
- **Street graph (B2d).** At setup each edge of a settlement's street graph
  costs `CLR_EDGE` 4 m more per metre its line passes nearer than 3 m to a
  drawn face (the nearest of the 1 m cells along it), so planned routes
  keep to the wide streets; lanes stay usable. Symmetric, static (the graph
  weights are rebuilt by setup, not in snapshots).
- **Measured** (`tests/pathing_probe.gd`, seed 7, 8 sieges + battle_2000 +
  bench_4000_hills; see docs/STATUS.md for the table): inside the drawn
  footprints 3.35 -> 0.00 % (within 0.3 m 1.66 -> 0.07 %); phase A's
  metrics hold (rout jitter <= 0.3 %, stationary routers 0 %, stuck over
  30 s 0); fights near obstacles 4.8 -> 4.7 %, in town 2.8 -> 3.1 %. Cost:
  setup +6-45 ms; the 8 sieges' tick means summed +10 % at seed 7, +6 %
  over seeds 1-4 (3,000 ticks; the battles differ, the pushes themselves
  are 0.03-0.09 ms a tick).

### Real cover: flat shots stop at walls (as built, pathing phase C0, 2026-10-15)

Why (docs/PATHING_SPEC.md addendum 1, the user): "once a unit is close to
cover the individual soldiers move to better their cover and actually get
behind cover. And the bullets can't pass through walls, they must actually
hit the soldiers." Open ground favours the line, cover and towns the
skirmishers. Code: `sim/battle_sim.gd` (section "real cover (phase C0)":
`_flat_block`, `_lean`, `_trace`, `_cover_seek`, `_cs_ok`, `_cs_threat`,
`_cover_places`, `_cell_top`; hooks in `_land`, `_fire`, `_cover_stops`,
`_compute_offsets`, `_obs_top`, `_setup_vis`, `step`), `sim/scenarios.gd`
(`test_cover_town`, `test_cover_rocks`, `cover_town`), `game/overlay.gd`
(`_blocked_shots`), probe `tests/cover_probe.gd`, set pieces
`tests/determinism_test.gd --only=cover`.

- **Where.** `ft_on` (static): a map with an obstacle grid on which
  something stands up from the ground (houses, walls, towers, gates, rocks,
  cliffs) and scenario key `los` not 0. Flat maps, woods-only maps and
  `los` 0 play exactly as before (the four flat golden digests and the
  campaign auto-resolve do not move).
- **Flat shots traced (`_flat_block`, `_trace`).** A flat soldier's missile
  (`m_arc` 0: balls, javelins, sling stones; arrows and artillery keep their
  rules) about to strike a man is traced from the shooter's hand (1.5 m up)
  to the man along the 2 m obstacle grid: an integer DDA visits each cell
  the segment crosses, in order (one look at a 16 m summed-area table first:
  a box with no obstacle costs nothing more). The first cell whose obstacle
  (`_cell_top`: a house's height, 5 m on a field map's blocks; a wall,
  tower, shut gate; a rock's or a cliff's height) stands above the line
  there (with the shot's parabolic apex, as the line of fire) stops the
  ball: no hit, a puff of dust there in the view (`bk_x` / `bk_y`, a ring of
  the last 32, not hashed). The line ends at a cover man's body (1 m: he
  crouches behind his cover) or at a line man's head (`LOF_HEAD` 1.7 m: he
  stands upright in his ranks, reloading too), so a 1.6 m boulder line
  covers a skirmisher and not a musketeer, a 2.4 m rock or a house both.
  Skipped near the shooter as his line of fire skips it (his own
  battlements, 3 m, a cover man's corner `COVER_PEEK_OBS` 5 m, a rock
  within `LAND_NEAR` 5 m); near the man struck only when he stands on a
  wall (the battlements' `WALL_COVER` roll as before) or shot within
  `EXPOSE_T` 1 s (up over or round his cover: the same distances as his own
  shot's). The cover kinds rock, house and wall no longer roll their
  `COVER_STOP` for a flat shot (the trace replaced them); woods and going to
  ground keep their rolls, and so do arrows against every kind. Cost:
  only balls that reach a man are traced; 7-16 microseconds a 100 m trace
  in a town or a rocky field (desktop).
- **Field maps' houses.** On a field map with hand-placed `blocks` the
  houses had no height for fire (`build_h` 0: shots passed through them);
  with `ft_on` they stand `VIS_BUILD_H` 5 m (`_obs_top`) for the line of
  fire too.
- **Per-man cover (`_cover_seek`, `_cover_places`; `cs_on`: `ft_on` and a
  unit with the cover trait).** Once a second (staggered) a cover unit
  standing (no order, not in contact, not fighting, on the ground, near
  obstacles) looks for its threat (its fire target, else the nearest enemy
  unit it sees within 250 m) and keeps its bearing (`u_cvb`, hashed); its
  places are laid out again only when that bearing turns more than
  `CS_TURN` 40 degrees (no jitter), and back to its formation on an order,
  contact or a fight (a threat gone out of sight leaves the spots standing).
  The layout (`_compute_offsets`, after the flow and the clearance): every
  2 m cell within reach rising `CS_H` 1.2 m or more gives spots on its far
  side from the threat, `CS_BACK` 1.5 m behind its middle (0.5 m off its
  face, put further out off a drawn house face): at the cover's edge (the
  cell beside it across the line to the threat open) one spot `CS_LAT`
  0.45 m toward that open side, where the man leans out to shoot (two for
  a lone boulder); otherwise one in the middle of the face's lee, taken
  after the edges (`CS_LEE`: as if 6 m farther; he is safe there but has
  no shot). Only open ground of the unit's own piece. Each man may take a
  spot within `CS_R` 8 m of his formation place; men nearest a spot first
  (then slot, then spot order), one man a spot; the others keep their
  places. The places are the unit's flowed places (`off_x` / `off_y`), so
  following, caps, separation and the clearance push work unchanged; a
  death lays them out again round the men already in cover. A unit with
  spots is hit through `_nearest_in_unit` (its men are not on the
  formation's grid). Line units (no cover trait) never take spots and keep
  their ranks.
- **Leaning out (`_lean`).** A man of a unit with spots whose shot is
  blocked from where he stands tries a point `LEAN` 1.2 m to either side
  of the line (left first) on open ground with nothing standing in the
  first 8 m toward his target, and shoots from there; for `EXPOSE_T` after
  his shot a ball at him that his cover would stop is traced to where he
  leans instead.
- **Hashed:** `s_shot` (per man, the tick of his last shot) and `u_cvb`,
  only with `ft_on`; nothing else new is hashed (`bk_*`, `stat_flat_*`,
  `stat_cs_men`, `stat_lean` are diagnostics). Snapshots carry them as
  script variables.
- **Measured** (`tests/cover_probe.gd`, 100 musketeers 90 m off a 60-man
  unit, 90 s, 4 seeds; ratio = defenders lost / attackers lost; HEAD ->
  C0):

| defender, ground | buccaneers (cover) | line musketeers |
|---|---|---|
| open | 0.51 = 0.51 | 1.02 = 1.02 |
| scattered rocks 1.6-2.4 m | 0.26 -> 0.27 (rolls -> physics) | 0.77 -> 0.67 (tall rocks now stop balls) |
| hamlet (field-map blocks) | 0.18 -> 0.09 (houses were transparent) | 0.82 -> 0.25 |
| Punic town, a main street's mouth | 1.16 -> 0.96 | 1.48 -> 1.41 |

  `--only=cover` set pieces: buccaneers behind a continuous 1.6 m boulder
  line lose 16 over 4 seeds against 87 in the open (2b's rolls: 34), 7
  balls stopped by the rocks; a line musketeer unit there loses 32
  = 32 in the open (their heads show over the rocks), takes no spots,
  none off its places; in the Punic town the buccaneers put 92 men to
  spots over the battle, lean out for 8 shots, 12 of 36 stand behind cover
  at the end (a line there: 0 of 19) and lose 24 to the line's 32 (a line
  in their place: 41 lost, 23 killed). Identical on repeat and across
  snapshot / restore.

### Street fighting: stances, bounds, the press in a lane (as built, pathing phases C1-C7, 2026-10-15)

Why (the user): "Open fields favor the lines of soldiers where cover and
cities can favor the skirmishing units"; street-to-street fighting from
cover. docs/PATHING_SPEC.md section 5. Code: `sim/battle_sim.gd` (section
"street fighting (phases C1-C7)": `stance_ok`, `_bnd_still`,
`_bound_tick`, `_bound_set`, `_bound_cover`, `_bound_in`, `_hold_files`,
`_cs_taken`, `_shove`, `_press_n`; hooks in `_cs_ok`, `_cs_threat`,
`_cover_seek`, `_cover_places`, `_cover_cell`, `_squeeze`,
`_update_units`, `_update_soldiers`, `_missile_think`,
`_update_missiles`, `_gun_unit`, `_fire`, `_flat_block`, the order rule),
`sim/siege_ai.gd` (`_street_ai`, `_strongpoint`, `_bound_storm`,
`_sp_wait`), `sim/scenarios.gd` (`street_bounds`, `test_street_bounds`,
`test_street_ai`, `cover_town` sizes), `game/hud.gd` / `game/battle.gd` /
`game/controls.gd` / `game/ui_icons.gd` (the Stance and Bounds buttons),
`game/overlay.gd` (`FX_CHIP`), set pieces `tests/determinism_test.gd
--only=street`, lockstep `tests/lockstep_test.gd --only=street`.

- **Stances (C6).** `u_stance` per unit: `STANCE_LINE` (keep the
  formation; line troops' default), `STANCE_COVER` (Take cover: cover
  troops' default), `STANCE_HOLD` (Hold street). ORDER_STANCE {unit,
  stance} through the lockstep like any order (an ORDER_KEY, so the order
  preview predicts it); foot only (`stance_ok`: infantry, pikes, foot
  missile troops; not horse, engines, heroes). A scenario unit may carry
  "stance". Hashed (`_stn_arrays`: `u_stance`, `u_bound`, `u_bnd`, `u_bt`,
  `u_bx`, `u_by`) once an order changed a stance or a bound (`stn_on`), so
  a battle without such an order hashes as before (the flat goldens).
- **Take cover (C2, the C0 leftovers).** The cover spots are phase C0's
  (`_cover_places`: spots in the lee of the 2 m cells that stand up,
  against the threat's bearing; at the edges a man leans out to shoot).
  Now any foot unit in Take cover uses them (cover troops in Hold street
  too) when standing (no order, a halt), when shooting its attack order's
  target from where it stands (missile troops in range, not moving), or
  halted in a bound. The threat: its attack target, else its fire target,
  else the nearest enemy it sees within 250 m; with none, a bound faces
  the way on and Hold street its front. Line troops in Take cover stand
  upright (the trace goes to their head, C0): only cover `CS_H_LINE` 2 m
  tall or more gives them spots (houses, walls, big rocks), and they have
  no peek past a corner (`COVER_PEEK_OBS` is the cover trait's).
  - *Rows behind (C2's "men with no point fill in behind").* Each spot
    has `CS_DEEP` 2 more spots `CS_ROW` 1.2 m further back in the same
    lee, taken after the faces (cost `CS_LEE` + 1-2 m): the men with no
    edge or face of their own stand behind the men who have one instead
    of in the open street. Measured: 40 buccaneers at the town's street
    mouth against 80 musketeers lost 62 without the rows, 34 with them
    (4 seeds; 63 in the open).
  - *Claims across units.* A spot within `CS_CLAIM` 0.8 m of another
    unit's man, or of another unit's cover place, is taken (`_cs_taken`,
    from the hashed positions and places: no new state). No two units on
    one rock; a unit laying out takes what is free, units keep what they
    hold.
  - *Face men to the edges.* A unit holding spots lays them out again
    every `CS_RELAY` 5 s (men at their spots keep them: nearest first), so
    a man in a face's middle (no shot) takes an edge the fallen left free,
    and spots another unit took since are given up.
- **Cover in town (C3).** A town's houses are cover (`_cover_cell`
  `COV_HOUSE` for buildings in settlements too; walls keep their rule):
  cover troops among houses count as in cover, can go to ground there
  (`GROUND_STOP`, concealment as in woods) and arrows (arced) roll the
  house's `COVER_STOP`; flat shots are traced as in C0. Per-point kinds
  (`COV_CORNER` 55 %, `COV_DOOR` 50 %, half value for line troops) were
  not built: with C0 the flat shots meet the real faces, and the rolls
  stay for arrows only.
- **Cover points (C1): not built as a table.** The spec's static points
  (`cp_*`: building corners, doors, wall points, props, with arcs and
  hashed claims) would duplicate C0's spot finder, which already gives
  the corners (edges) and faces of every house, wall, rock and field
  block from the real 2 m cells, laid out against the actual threat, with
  the clearance push off the drawn faces; claims are done on the places
  (above). Props (carts, barrels, wells) come with phase W's West towns.
- **Bounding advance (C4).** A move order with "bound": 1 (the Bounds
  toggle; foot on the ground). Cover troops split by soldier index: the
  even men go with the anchor (`u_bnd` 1) at most `BOUND_LEN` 25 m,
  stopping once past `BOUND_MIN` 10 m where something stands up within
  6 m of the anchor (`_bound_cover`), or after `BOUND_T` 12 s; then they
  settle into the cover spots round it (2), and the odd men, who stood and
  shot meanwhile, come up to theirs (3) until they are within
  `BOUND_NEAR` 2 m of their places on average (or `BOUND_T`); and on. The
  team holding does not move (`_update_soldiers` fast path) and is the
  only one to shoot (`_update_missiles`, `_gun_unit`: a bounding unit
  shoots while its anchor moves; fire at will picks targets on such a
  move, `_missile_think`); it leans out round its cover as at a spot.
  Line troops hop as a whole (1) and halt `BOUND_PAUSE` 4 s to fire (4).
  Contact (an enemy within 12 m), a wall, a stair or carrying ends the
  bound (it marches on as usual); arrival, any new order (not run, fire,
  ammunition) or the skirmish fall-back too. A bounding unit is not slowed
  for its men strung out (`lag`) and hits on it are found man by man.
- **Street melee (C5).** A unit squeezed in a town's street (`u_sq` > 0,
  `V_URBAN` under its anchor; not on walls or stairs) fights with its
  first `STREET_RANKS` 2 ranks: the men behind keep their places and take
  on only a man within their reach; it does not lap round (no wrap). The
  `WALK_REACH_MAX` cap of squeezed units stood already. The shove: once a
  second (`SHOVE_T`) a unit standing in a lane (no order) and fighting
  counts its men and its nearest fighting enemy's within `SHOVE_R` 4 m of
  the other's box; outnumbered 3 : 2 it gives `SHOVE_STEP` 0.3 m of
  ground (its anchor back from the enemy, onto open ground), so its rear
  ranks step back and its front follows. Units with an order (attackers
  closing) are not pushed: their anchors close again.
- **Hold street (C6).** Line troops standing (not on a move) measure the
  street across their front out to `HOLD_SPAN` 20 m either side
  (`_squeeze`); bounded on both sides, they take its width in files, at
  least three ranks deep (`_hold_files`: width / file spacing, between
  `MIN_FILES` and men / 3), and move to its middle; in the open nothing
  changes. They count as squeezed (C5's ranks, the reach cap). Cover
  troops in Hold street take spots as in Take cover within `CS_R_HOLD`
  12 m of their places, facing their front with no threat in sight.
- **AI (C7; `sim/siege_ai.gd`; West rows only, an open town, not Easy;
  Rome's sieges keep their fitted play).** Defenders: at the first
  classification a West unit's reserve post becomes a strongpoint
  (`_strongpoint`): the mouths sorted by distance from the attackers'
  centre; skirmishers with missiles, then other cover troops, then line
  troops each take the next mouth in turn; cover troops stand
  `SP_COVER_PCT` 30 % of the way in from the mouth to the plaza (the next
  one at a mouth `SP_STEP` 15 % further in), line troops at `SP_LINE_PCT`
  60 % in the Hold street stance; their reserve rules then apply
  (shooters shoot from the post). Attackers in the assault: West cover
  troops with missiles (`_bound_storm`) shoot a defender within 85 % of
  their range (an attack order: they stand, Take cover puts the men at the
  corners), else go by bounds to their street's mouth and on to the
  plaza; West line foot storming (`_sp_wait`) halt while a strongpoint (a
  defending unit holding cover spots, with `SP_WORN` 60 % of its men or
  more and not disordered) is within `SP_WAIT_R` 70 m, until the
  skirmishers have worn it down or the army goes all out. Field battles:
  `battle_ai.gd`'s `_cover_spot` as before (cover troops' default Take
  cover now also covers them when they shoot an attack target).
- **View.** The order panel has Stance (Line / Cover / Hold, key C) and
  Bounds (on / off, key B: while on, the player's move orders for foot go
  by bounds) with their icons. A ball stopped by a wall, house or rock
  shows a pale flash, chips and a 1.6 s dust cloud at least a few pixels
  across (`FX_CHIP`, was the stone's 0.8 s puff).
- **Section 6 (asymmetry mechanics) not built:** street disorder for
  line units (`STREET_DIS`), volleys by ranks 1-2 in a lane and the
  flank-support morale bonus in the open would move Rome's fitted sieges
  and field battles (section 7 keeps Rome to C3 and C5); left for the
  balance phase T.
- **Measured.** See docs/STATUS.md (the balance table, the pathing probe,
  cost).

### West open towns (as built, pathing phase W, 2026-10-16)

Why (the user, docs/PATHING_SPEC.md section 7 and addendum 2): "it would
make more sense that the city covers a larger section of the map", mostly
unwalled (real walls only where the history check says); "the buildings
may not be so symmetrical and perfectly placed. They still follow the road,
but saloons and taverns and shops and food stores would be not perfectly
shaped and follow the land a bit more." Code: `sim/mapgen.gd` (section
"West open towns (phase W)": `is_west`, `west_coast`, `west_outline`,
`_city_west`, `_w_trace` / `_w_road`, `_w_lots`, `_w_put`, `_w_extras`,
`_w_lowwall`, `_w_prop`, `_w_stakes`, `_w_graph`, `_w_join`, `_w_flip`),
`sim/terrain.gd` (`_west_ground`), `sim/battle_sim.gd` (`sea_boats`,
`wt_on`, `_street_giveup`, `bld_g` and `TIMBER_PASS`, the props' and yard
walls' heights in `_land_heights`, `CLR_MARGIN_W`), `sim/scenarios.gd`
(`west_town`, the West holds and deployment zone in `settlement`),
`campaign/cbattle.gd` (`city_dict`: "west"), `game/custom/custom_setup.gd`,
`game/battlekit.gd` (`_build_west`, `_west_fort`, palettes 6 and 7),
`game/city_streets.gd`, `game/terrain_layer.gd` (`_west_built`),
`game/tree_layer.gd`, `tools/battlekit/build.py` (`PIECES_W`).

- **Which towns.** A settlement whose city dictionary has "west": 1 (the
  West pack's `CBattle.city_dict`, a West custom battle, the `west_*`
  scenarios), walls 0-2 and a European founder (`MapGen.is_west`). Native
  towns (founder Celtic: Itza, Miskito) keep the oppidum (round huts, a
  palisade at walls 1+, in jungle); walls 3 (only by building in the
  campaign; no West region starts with it) keeps the walled plans (the
  history check's full curtain). Rome, Greek and Punic maps never take this
  path: their dictionaries have no "west" key (`city_params` adds it only
  when given), so their maps, pins and goldens are as they were.
- **Frame and size.** The town is a band along the top of the canonical
  frame (the shore, or the top of the field inland), `W_HW` 190 / 245 / 300 m
  half wide and `W_D` 150 / 205 / 255 m deep by level, on a field at least
  `W_FW` 440 / 560 / 680 m wide (wider only for a very wide attacking
  army; the town does not change with the armies), with `W_APPROACH` 95 m
  from its landward edge to the attackers' front. It covers 32 % of the map
  (village) to 39-46 % (towns and cities; V_URBAN share). The outline: the
  shore (or the top), the sides, a landward edge with two waves and a lean,
  its ends rounded.
- **Ground (`_west_ground`).** The country's own relief round the town
  (hills and ridges as rolling country), kept at 60 % over the band so the
  town follows the land; the plaza level; on hill and ridge country a rise
  of 8-16 m from the shore to the landward edge (the town climbs from the
  harbour, the attackers come down to it); the fort on a 3-6 m knoll; the
  sea lowered below the shore.
- **The fort (walls 1-2).** A bastioned square (`fh` 11 / 14 / 17 m, four
  diamond bastions) at one end of the quay with its sea face in the water,
  or inland on the high back corner; roads and lots keep 8 m off it. (Slice
  2c: a fort with an inside, its guns and garrison: "Forts and fighting
  from buildings".) Walls 2 adds
  a stake palisade 9 m beyond the landward edge, two cells deep, with a gap
  at every road (`_w_stakes`; records that match their cells exactly).
- **Landforms and big trees.** On rolling or rougher ground the landforms
  (`Land.place`: cliffs, outcrops) are placed first, kept off the quay, the
  plaza, the fort and the attackers' ground but free to fall in the town's
  outer parts; 5-12 big trees (palm clumps, ceibas) stand in yards. The
  roads bend round all of them.
- **Roads (`_w_trace`).** Traced `W_STEP` 10 m a step toward each
  waypoint, at most 96 angle units off the goal's bearing in one go: of
  seven headings (0, +-40, +-90, +-150) the first whose disc of half the
  road's width + 1 m is free (a summed-area look first), cheapest by its
  turn plus (on the high street, the lower street and the lanes) its rise:
  along the contours. The quay (`W_QUAY` 12-16 m) along the shore (inland:
  a 7 m back street); the high street (`W_MAIN` 8-12 m) through the plaza
  on a winding rail; on towns and cities a lower street at 58-70 % of the
  depth; cross streets every 50-90 m from the quay to 22 m past the
  landward edge (7-10 m wide; their upper and lower halves often a dog-leg
  apart at the high street; some start at the high street; 34 units of
  bend a step); lanes (`W_LANE` 6 m) between neighbouring cross streets,
  one to three per gap, some left out. The cross streets' outer ends and
  the high street's two ends are the street mouths, nearest the attackers'
  line first (Scenarios' holders, the C7 strongpoints).
- **The plaza and its landmarks.** A square of 36 / 46 / 56 m (`W_PLAZA`)
  on the high street. Right after the quay and the high street (before
  the other roads, which then bend round them, their ground blocked 2 m
  round): the church on the plaza's seaward side (else the other), the
  governor's house (towns and cities) on the opposite side, a guardhouse
  at a corner (Barracks), each facing the plaza; its well and stalls are
  scenery.
- **Lots (`_w_lots`, `_w_put`).** Along each road, both sides, in a fixed
  order: a density 8-96 (`_w_dens`: high at the quay and round the plaza,
  low at the landward edge and the ends) decides whether a lot is built,
  its kind and its setback (0-1 m in the core, up to 6 m at the edge) and
  gap (0-2 m plus up to 14 m at the edge). Kinds by road and density:
  warehouses, chandlers, taverns, food stores on the quay; shops, taverns,
  stores on the high street; houses (stores, shops, taverns among them) on
  the cross streets; houses and shacks on the lanes; shacks where it thins
  out. Each kind has its frontage, depth and height (`_w_size`: shack 5-7
  x 4-6 m, 3 m; house 7-11 x 6-9, 4-5 m; tavern 10-14 x 8-11, 6 m;
  warehouse 14-22 x 9-13, 6-7 m; governor 18-22 x 13-16, 7-8 m) and its
  material (`_w_mat`: Spanish towns 60 % masonry houses, English, French
  and Dutch 35 %; warehouses 70 % stone; shacks, lean-tos and stakes
  timber; church, governor and fort stone). A building is turned with the
  road at that point plus -5 to +5 degrees (more at the edge) and, on a
  slope, up to 9 degrees toward the nearer of the contour's axes (lots
  step with the slope); its front edge is set back clear of the road
  whatever the turn. It is placed only where its cells are inside the
  town, off the roads, the blocked ground and other buildings, `W_PAD` 3 m
  clear of other buildings all round (no slivers a man could jam in), on
  ground rising at most `W_SLOPE` 3 m across it; else tried at 3/4 size,
  else the lot is skipped. Its blocked cells are those within 0.6 m of its
  drawn outline (so no man stands inside a drawn house: the footprint
  metric). Extras: a back wing (an L) on taverns, warehouses, the
  governor's house and big houses, overlapping the house by a metre; a
  lean-to against a side; a yard behind (a low wall along its back and
  one side, the other open; 2 cells clear of other buildings); barrels,
  crates or a cart at a tavern's, store's, chandler's or warehouse's door
  on a wide street; goods along the quay's sea side. The hill city 343
  buildings, towns and port cities 170-260, villages about 90.
- **Cover by material.** Each building record carries its height (dm) and
  material (`MAT_STONE` / `MAT_TIMBER`, record entries 15 and 16); the
  layout's `bmat` grid gives every building cell both (static, `bld_g` in
  the sim, not in snapshots). The line of fire and sight read a West
  house's own height (`_cell_top`, `_obs_top`); a flat ball stopped by a
  timber cell goes through it `TIMBER_PASS` 35 % of the time (one roll of
  the sim's RNG, then traced on past the timber; stone stops it), counted
  in `stat_wood_pass`. Props (barrels 1.1 m, crates 1.2, carts 1.4, wells
  1.0) and yard walls (1.3 m) are rock cells (`C_ROCK`) of their own
  heights (`_land_heights`), so a crouching skirmisher takes cover behind
  a cart or a yard wall (C0's spot finder: 1.2 m and up) and a standing
  musketeer is not covered by them.
- **The street graph (`_w_graph`).** Nodes every other road point (about
  20 m), the plaza and its corners, a line 16 m outside the landward edge,
  round the fort, round the landforms, a 16 m lattice over the open
  ground between the lots where a man stands 2 m clear (so a unit in a
  back yard sees a node: before it, the planner fell back on a node behind
  a house), and a 48 m lattice over the open ground round the town; edges
  up to `W_EDGE` 34 m with a clear 3 m line (candidates from buckets, in
  index order); pieces joined to the plaza's by the shortest clear line
  within 64 m (`_w_join`, bucketed; a yard no line reaches stays apart).
  400-600 nodes, 800-1,700 edges.
- **Routers.** Defenders routing in a coastal West town also leave by the
  boats: open ground beside the sea is an exit of their side's exit field
  (`sea_boats`), and a man who reaches it is off the field (before: a
  300 m run along the shore through the enemy to a side edge). In any West
  town a router not huddled, with a ready enemy within `SURR_R` 15 m, gives
  up when its men's middle has stood within 2 m for `GIVEUP_T` 8 s or the
  enemy has been that near `GIVEUP_CAUGHT` 10 s on end (`_street_giveup`,
  `u_gu`; its men are taken as the A3 huddle's are): caught in the
  streets with no gate to huddle at. Hashed on West maps only (`wt_on`:
  `stat_rs_*`, `u_gu`).
- **Clearance (phase B) on West maps.** Computed 2 m round each house
  (`CLR_MARGIN_W`; 3 m elsewhere) and not inside its blocked cells (no man
  stands there): 260 -> 113 ms for the city. `_clr_exact` no longer builds
  an array per call (identical results; every map).
- **AI (`sim/siege_ai.gd`, West towns only).** Attacking missile units
  waiting off an open West town stand off its landward edge in front of
  where they are (the open-town rule's ring round the town's centre would
  put the band's flanks inside it); attacking skirmishers going by bounds
  (C7's `_bound_storm`) and line foot storming by the streets head for the
  plaza once they are nearer it than their street's mouth is (they went
  back out through the streets to reach their mouth first, into the
  friends coming in: a jam).
- **Scenarios.** Holders at each mouth stand 18 m inside it, facing out;
  the defenders deploy in the town's box. `west_village` (Spanish fishing
  village, flat, coast), `west_town` (Spanish port town, rolling, fort),
  `west_city` (Spanish hill port, fort and palisade), `west_inland`
  (English inland town, rolling), `west_port` (Dutch port city, flat,
  fort), `west_hill_village` (Spanish ridge village, fort on the hill),
  `bench_west_town` (1,680 men in 40 units), `bench_4000_west`.
- **View.** `game/battlekit.gd` `_build_west`: each kind its piece, turned
  so its street front (porch, gallery, awning, goods) faces the road:
  `tavern` (a gallery with a lean roof, the sign on its bracket, barrels),
  `shop` (flat roof, striped awning, counter), `store` (hipped, a canopy,
  sacks and barrels), `warehouse` (stone, loading doors, hoist beams,
  crates), `chandler` (framed timber, rope coils, an anchor), `shack`
  (palm thatch), `leanto`, `governor` (four tiled wings round a patio with
  a fountain and a tree, an arcade, the flag), `lowwall`, `stakes`,
  `crates`, `pier` (new Blender pieces, `tools/battlekit/build.py`
  `PIECES_W`, packed after the others: the atlas stays 1024 x 1024, 61 of
  the shader's 64 rects); houses in the founder's manner (Spanish flat
  roofs and hips, English, French and Dutch gables), painted by a hash of
  their place in three palettes (colonial, ochre under dark red tiles,
  pale blue under terracotta; culture slots 6 and 7, unused before); the
  fort as curtain pieces and four bastions round a keep; the jetties as
  pier pieces. Shadows come from `battlekit_shadow.gd` as for every kit
  piece. Streets are pale packed earth with a darker rim, the alleys
  between houses a warmer darker earth, the plaza paved, clipped to the
  sim's open cells with a dark footing under every house (2026-10-22,
  "Reading a town battle" under Controls additions; `city_streets.gd`), the town's ground trodden only within about 8 m of
  houses and roads (`terrain_layer.gd` `_west_built`, view only; the sim's
  V_URBAN covers the whole band), palms on any West map.
- **Not built (open).** (The fort's inside, its garrison and guns and units
  holding houses came with slice 2c.) The palisade does not burn or get
  hacked; piers are scenery (the rules
  see the sea); moored ships are not drawn on the battle map; native
  towns keep the oppidum; walls 3 keeps the walled plans.
- **Measured.** See docs/STATUS.md (the pathing probe, the cover probe,
  set-up and tick cost).

### Balance pass T (as built, 2026-10-16)

The change pass after the measurement report (scratchpad `balT/MEASURE.md`;
the harnesses `balT/t/t1.gd`, `f.gd`, `aib.gd` and `balT/siege_run.gd`).
Stance kept: no stat bonus for standing inside walls; numbers chosen once
from measurements; the results are in docs/STATUS.md (balance pass T).

- **Firearm armies in the field** (`sim/battle_ai.gd` `_plan`,
  `_missile_think`, `_no_line`, `_mis_close`). The plan anchors on the
  line: foot, pikes and now a musket line (`line_gun`: a gun row that does
  not skirmish), so the West line is musketeers and pikes; an army with no
  line at all anchors on its other missile foot (plan key `skirm_line`) and
  its gap counts them. Once the lines engage, a musket line, and every
  missile unit of an army with no line, attacks the nearest enemy unit it
  sees that is not locked in a melee (the sim closes it to 85 % of its range
  and it stands shooting); nobody free in sight, it fires at will where it
  stands. Before: two all-missile armies never planned and stood 100 m apart
  for 30 minutes. Rome armies with foot are unchanged (the flat goldens
  hold).
- **Buccaneers' scatter** (`sim/unit_types.gd`, one West field):
  `m_spread2` 60 -> 100 (11.5 m at 100 m, 4.7 m at 60 m; the musketeers'
  135: 15 / 6 m). Aimed fire stays deadly at street range; in the open at
  70-100 m the volume of a musket line wins the firefight.
- **Per-man fire at will in cover** (`sim/battle_sim.gd` `_pm_on`,
  `_pm_unit`, `_pm_keep`, `_pm_cand`, `_pm_find`, `_pm_sight`; owner,
  2026-10-16). On a map with the obstacle grid (`ft_on`) a missile unit of
  guns or bows in Take cover (cover troops also in Hold street) fires man by
  man, never in volleys: each man reloads on his own clock (`s_rl`: the tick
  of his last shot; loaded `m_reload` later) and fires at his own target
  man (`s_tgt`, sticky while he lives, his unit is seen and in range). A man
  with no target looks only every `PM_K` 10 ticks (offset by his index; a
  look that found nobody waits `PM_K_FAIL` 30): the enemy units in reach of
  his unit's box (`_pm_cand`, once a tick for the unit), `PM_SAMPLE` 6 men of
  each, nearest first (units in a melee last), and traces the C0 line of
  fire from where he stands or leans out to at most `PM_TRY` 3 of them. A
  man in a face's lee has no line and holds his fire. The shots carry no
  volley fright and ignore the volley range (`m_volley_r` is the line's
  rule); an attack order limits the men to its target's men. Line troops,
  and every unit on a map without obstacles, keep the volleys. `s_tgt`,
  `s_rl` are hashed with `s_shot` (ft_on) and go through snapshot / restore.
  Cost: 0.65 ms a tick in bench_4000_west (the search and its traces; per
  man a target search costs about 30-60 us; the per-cell visibility cache is
  the next step if it grows).
- **Cover from the first volley** (`_cover_snap`; `CS_R` 8 -> 10 m). On the
  battle's first step a cover unit with a threat in sight lays out its
  cover spots and its men stand in them, gone to ground if half are in
  cover (they used to walk there under the first volley). Men take spots
  within 10 m of their places (more men off the open street).
- **Line of fire from the men in cover** (`lof_units`). A unit at cover
  spots whose middle has no line of fire to a target has one if any of
  `LOF_MEN` 4 of its men, spread through its slots, has: a strongpoint whose
  middle stood behind a house never chose a target.
- **Skirmishers fall back from guns closing on them** (`_missile_think`
  in the sim, `_skirm_back` in the settlement AI): a gun unit with an
  attack order on a skirmisher counts as a threat within `SKIRM_INF` as foot
  does (musketeers walked up to 15 m of buccaneers in a town).
- **West street posts** (`sim/siege_ai.gd` `_sp_cover`, `_cover_score`,
  `_reserve`, `_strongpoint`). A skirmisher's strongpoint is chosen where
  the cover is: points on the mouth-to-plaza line (its percentage -10 to +20
  in 5 % steps) and `SP_LAT_STEP` 6 m either side (3 steps), scored by the
  2 m cells within 10 m rising 1.2 m or more with open ground beside them,
  less 2 per step from the plain point (west_town's plain post stood in an
  open yard). A West defender further than `SP_RUN_R` 30 m from its post
  goes there at the run (it walked 120 m and met the first volley on the
  way). Line troops hold the open town's streets at `SP_LINE_PCT` 40 % of
  the way to the plaza (was 60); with works (walls 1 the fort, 2 the fort
  and the palisade, whose gaps are the street mouths) the defence is in
  depth: skirmishers cover the mouths from the corners (30 %), the line
  holds the inner streets at `SP_PAL_LINE_PCT` 80 %. Measured choices: lines
  at the gaps (15 %) lost 16 of 16, at 40 / 50 / 60 % in the open towns the
  attackers won 69 / 12 / 31 %.
- **Sieges: trapped routers do not rally** (`RALLY_TRAPPED`,
  `_update_morale`). Defenders routing inside the walls (`ROUT_INWARD`) do
  not rally while an attacking unit stands in the town's streets; the
  attackers' routers run off the field, so an even fight at the breach
  went to the side whose routers came back. (`ROUT_INWARD` 0 measured the
  same and was not taken: phase A's huddle stays.)
- **Battlements** (`WALL_COVER`): walls 2-3 stop 15 / 25 % of missiles from
  below (was 25 / 40; walls 1 25).
- **A battery standing by its engines is not stuck** (`_update_units`):
  its spare men's rows behind its last working engine may be blocked; the
  probe counted it 40 s stuck.
- **Tried, not kept:** ladder parties going on with the escalade once the
  gate is down (they climbed stretches 100 m off and died on the walls:
  walls 2-3 0 of 16); attacking archers pulling back out of the walls'
  reach after a lost duel (20 % down and 2 to 1 against: no gain in the
  wins, the duel with the walls was over in a minute and the battlements'
  cover never came into play); the all-out four minutes sooner; two fewer
  towers; `ROUT_INWARD` 0; line of sight off (the same results: sight is
  not what tilted the sieges).

### Forts and fighting from buildings (as built, West slice 2c, 2026-10-16)

Why (the owner, 2026-10-14 and 2026-10-16): "there were no castles": the
West's walls become forts and towns where men fight from buildings and
rooftops, the rooftops and balconies built on the per-man fire at will (a
man on a roof is a man with a higher eye and shot line). Code:
`sim/mapgen.gd` (section "the harbour fort (slice 2c)": `fort_trace`,
`_f_w`, `_w_fort`, `_w_fort_bld`; `west_outline`'s fort, `_w_graph`'s fort
nodes, `F_*`, `B_MAGAZINE`), `sim/terrain.gd` (the knoll and its levelled
parade), `sim/battle_sim.gd` (`fort_on`, `n_outer`, `fort_cmp`, `in_fort`,
`_fort_capture`, `_fort_guns`, `FORT_GUN_SECTOR` in `_art_in_range`, the
capture rule in `_update_capture`, the result's "fort"; section "fighting
from buildings (slice 2c)": `_setup_occ`, `occupy_refusal`, `occupy_near`,
`_occ_enter`, `_occ_leave`, `_occ_offsets`, `_occ_soldiers`, `_occ_door`,
`_occ_stop`, `_occ_aim`, `_occ_win`, ORDER_OCCUPY in the order rule, hooks
in `elev_at`, `_unit_elev`, `_pm_on`, `_pm_unit`, `_pm_find`, `_fire`,
`_land`, `_flat_block`, `_cs_ok`, `_compute_offsets`, `_base_files`,
`_update_units`, `_update_soldiers`, the attack goal at a door), `sim/unit_types.gd`
(`FORT_ROWS`: the fort gun, the last row), `sim/siege_ai.gd` (`_fort_gates`,
`_fort_choice`, `_fort_party`, the building posts; docs/AI.md 29),
`sim/battle_ai.gd` (the musket line's reserve), `sim/scenarios.gd` (the
garrison, `fort_storm`, id `west_fort_storm`), `campaign/cbattle.gd` /
`campaign/crules.gd` ("fort_holds"), `game/battlekit.gd` (the trace drawn as
walls, the magazine piece), `game/overlay.gd` (held buildings, the fort's
parade), `game/hud.gd` / `game/battle.gd` / `game/controls.gd` (Occupy),
`tools/battlekit/build.py` (`b_magazine`), set pieces `tests/determinism_test.gd
--only=fort` / `--only=occupy`, `tests/lockstep_test.gd --only=occupy`.

- **The harbour fort (walls 1-2 West towns).** A square trace with a flanked
  bastion at each corner (curtain, flank `F_F` 6 m, face, salient `F_B`
  13-15 m out, face, flank, gorge `F_G` 9 m from the corner), the square's
  half side `F_H` 24 / 27 / 30 m by level: 20 vertices, low thick walls
  (`F_T` 10 m: a 2 m parapet, a 4 m walkway `F_WALL_H` 6 m up, an earth
  rampart behind), on a 3-6 m knoll whose top is levelled for the parade and
  whose sides are the glacis. Its seaward curtain stands on the shore (the
  sea bastions in the water). The sim's wall machinery as for any wall (a
  citadel ring: `cit_*`, `g_cit`; `fort_on`): walkway stretches cut 7 m from
  the salients, 4 m from the flanks' corners, 2 m from the gorges (12 m and
  longer only: the bastions' faces always, the curtains at towns and
  cities), joined round the corners; a stair at both ends of every stretch
  down to the parade; the main gate in the curtain toward the town (open at
  the start: the garrison comes and goes), a sally port (a postern, shut) in
  the far one, both with the walls-2 gate's hit points (swords barely hurt
  them: the ram or guns); the ditch (`F_DITCH` 6 m, 2 m beyond the wall's
  outer face) round the land faces with a causeway at each gate (men cross
  it slowly, horses and engines not at all). Its wall level for the rules is
  `F_WALLS` 2 (ladders 3 s a man, battlements stop 15 %, +15 % range from
  the walk). On the parade: the barracks along the far curtain and the
  powder magazine in its seaward corner (a new kit piece). The street graph
  gets each gate's three nodes, the parade every 8 m and every stair's foot.
  The town's roads and lots keep clear of the fort and its ditch.
- **A landmark's own trace** (campaign towns' plan forts, 2026-10-20): the same fort on the piece's outline (the Morro's triangle,
  San Marcos's bastioned square), DESIGN "Fort traces from the piece".
- **Its guns.** A fort gun (UT.FORT_GUN: a fixed long gun, crew 4, 260 m,
  roundshot that bounds 40 m, a shot in 40 s, 16 a gun; the tower engines'
  rules: it turns, is shot at, its crew on the walk) on each landward
  bastion's salient and on the seaward curtain (inland forts: all four
  salients). It fires through its embrasure only: within `FORT_GUN_SECTOR`
  60 degrees of the way its platform faces out from the fort's middle (the
  bastions sweep the glacis, the approaches and the town's streets in their
  arc; the sea gun waits for ships: a later sea battle on the same map).
- **The garrison.** The best musket companies (missile foot with guns and
  without the cover trait, by tier, then men; one, two in a city, always one
  left for the streets) stand on the fort's land stretches nearest the
  attackers; the rest of the army holds the town (C7's posts, defence in
  depth with works). The garrison fires man by man from the parapet: on West
  maps wall units of guns or bows fire at will each with his own target and
  line of fire from the walkway's height (`_pm_on`), their range the
  height-gained one. Units on the parade hold it. **The sally (forts
  leftovers, 2026-10-16):** each garrison company stands as two units, its
  guard (a quarter rounded up, `Scenarios.FORT_GUARD_MIN` 10 men or more, on
  the land stretch farthest from the attackers) and its sally company (when
  that is `FORT_SALLY_MIN` 20 or more; one army entry: `order` lists the
  guard as [1, i, 1] and `CBattle.outcome_from_result` adds its fates to the
  company's row). While the streets hold the company shoots from the
  parapets; when the street line breaks or the attackers hold the plaza's
  approach it goes down and out by the main gate, in Line, onto the street
  post nearest it; a ram or ladders near the gate bring it back up. The
  guard keeps the fort held (the result's `fort`, the campaign's
  `fort_holds`). A player does the same with the two units and the gate
  order (AI.md 29). The fort's stairs and street graph (fixed with it):
  a bastion's stair whose foot lies in a pocket the way does not reach is
  taken last going down or up (`FORT_STAIR_OFF`), and a fort's graph nodes
  without edges (feet of such stairs) are no way in or out (`_near_nodes`).
- **Taking the town, the fort holding.** The town's plaza is still the
  capture zone: held CAPTURE_TICKS, the town's defenders rout as before, but
  the fort's (on its walls or its parade, `in_fort`: the parade is its own
  piece of ground with the gates shut, `fort_cmp`) do not; the battle is
  then the attackers' (`winner`, `decided_tick`) and the result carries
  `fort` {held 1, men (the garrison's then, gun crews left out), gate,
  taken}. The fort itself falls when an attacking unit of `CAPTURE_MEN` holds
  its parade with none of the garrison on it for `FORT_CAP_TICKS` 30 s: its
  garrison routs and does not rally (walls do not hold a fort whose inside
  is lost). **Campaign:** `CBattle.outcome_from_result` puts `fort_holds` 1
  in the outcome when the town fell with the fort holding; `CRules.apply_outcome`
  then does not hand the settlement over (no capture, no sack): the fort's
  men are its garrison (at least 10 %), the beaten field armies retreat as
  usual and the siege goes on (assault again, or starve it out); the event
  carries `fort_holds`. No state format change (no new key in the state;
  the auto-resolve never sets it, so campaign_sim is unchanged).
- **Fighting from buildings.** `ORDER_OCCUPY` {unit, building} (a lockstep
  input; refused for horse, engines, units on a wall or carrying, a building
  another unit holds): foot go to the building's door step and, there 3 s
  with no enemy on them, go in. A building that can be held: a West town's
  house, tavern, store, warehouse, chandler, shop, the church, the governor's
  house, the guardhouse, 3.5 m tall or more, with a door step on open ground
  and 4 firing places or more (the fort's own buildings not). Its firing
  places: every 1.5 m round its faces from 1.2 m in from each corner, 0.4 m
  inside the face (none at the door): at the windows (a pitched roof:
  `OCC_WIN_DROP` 2.2 m below the top) or behind the parapet of a flat roof (on
  it: a Spanish town's flat-roofed houses, as the view draws them, shops, the
  governor's house), on a tavern's front gallery. A held building's cells
  stand its men at that level (`elev_at`, `_unit_elev`), so every rule of
  height reads it: their range, their line of fire over the street, the
  sight lines. Inside, slot by slot: the door's two men (just inside its
  frame), the firing places in order, the rest waiting inside; a fallen
  man's place is taken by the last man (one rank: `_base_files`), so the men
  at the windows step up from inside. Every unit of missile foot holding a
  building fires man by man (`_pm_on`) from its firing places only, each
  with his own sight line from his window or roof edge; a ball at a man
  there is traced as any (other houses between still stop it; his own
  building's walls near him are `_occ_stop`'s) and then stopped by the wall
  or parapet he keeps behind `OCC_STOP` 70 % of the time, `OCC_STOP_EXP` 25 %
  within EXPOSE_T of his own shot (up at the window, over the parapet; a
  gallery 45 / 20 %), arrows and stones 25 % on a flat roof or a gallery, 75
  % at a window; a man inside is not hit; artillery's roundshot hits as
  anywhere. Volleys at the unit pick a man at a window (`_occ_aim`). **The
  door**: enemy men on the door step (`OCC_DOOR_R` 2.5 m) are paired with the
  door's men, one each, nearest first, and fight on their own clocks
  (`_melee` both ways): a two-man front; nobody else reaches the men inside
  (their cells are no ground: the melee search does not reach through
  walls). An attack on a unit in a building goes at its door step (the
  attack goal; men with missiles shoot at the windows instead). The unit
  comes out by the door (its men onto the step, three abreast) on a move,
  a withdrawal, a rout, an attack by men without missiles to shoot, or
  another building's order; a building is free again when its unit leaves
  or dies. Hashed with `occ_on` (a West town with buildings that can be
  held): `u_occ`, `u_ocg`, `u_oct`, `ob_u`; the buildings' geometry is
  static (setup, skipped in snapshots).
- **The AI.** docs/AI.md 29: the garrison and its gate, the attackers'
  choice (storm the fort as well, or take the town round it), the musket
  lines' street posts in buildings (at most `SP_OCC_MAX` 1 a side), the
  attackers clearing a held house first at its door (`OCC_STORM_PULL`) and
  shooting men in the open before men at windows (`OCC_SHOOT_PUSH`), and in
  field battles the musket line's reserve and counter-charge. A held house
  beset at its door (`OCC_PRESS_MEN` 8 enemy men within `OCC_PRESS_R` 7 m of
  its step) loses `OCC_PRESS` 12 morale a second without recovering; men in
  a house do not contest the square (`_update_capture`).
- **Walls 3 (balance T's leftover), measured, no rule kept.** The suggested
  rule (the attackers' routers stop at their camp, 50 m behind their start
  line, and rally there as the defenders' do inside) never triggered: in the
  equal-force walls-3 sieges the attackers' routers already rally on the
  approach (5-9 rallies a battle against the defenders' 1-3; 0-84 men routed
  off the field), and the ring and polis results were identical with and
  without it. The attackers lose by attrition at the walls (490-585 killed
  against 210-450) and withdraw beaten (`S_BEATEN_PCT`); the lever is the
  approach and the walls' fire, not the routing (docs/STATUS.md). **Then
  (forts leftovers, 2026-10-16):** the attrition is at the gate, not the
  ladders (hardly used): the walls-3 stone towers shoot the batteries, the
  ram's crew and the crowd before the gate, the gate falls later and the
  attackers storm the mouth stack 2 to 3; `TOWERS_STONE` at walls 3 2 -> 1
  gives the equal-force full-kit sieges 25 % (12 before).
- **View.** The fort is drawn as walls along its trace (the kit's
  `wall_10_2`, its gates and stairs as any wall's), its interior buildings
  as kit pieces (the new `magazine`; the barracks a flat-roofed block), its
  guns as engines; a held building's outline in its side's colour and its
  door step marked, the fort's parade being taken as an arc with its time
  (`game/overlay.gd`); men in a building stand along its roof edge and
  windows (the diorama look: men on the parapet, muskets out). The order
  panel's **Occupy** button (key I): arms a pick (2026-10-22: the
  buildings the selection may take light up, a hover or a first tap shows
  one's sight fans, a click or second tap sends the men in, the others of
  the selection to the nearest free ones within 60 m; "Reading a town
  battle" under Controls additions); **Leave** once one holds a building.
- **Not built.** Ships offshore for the sea guns; a sally from the fort
  (the defenders never open the sally port); the garrison does not come
  down to help the town; men inside a building do not fight room to room
  (the door's pairing is the whole melee); timber buildings do not burn
  with men in them; galleries on the governor's house (only the tavern's
  front counts as a gallery); the AI's own buildings for skirmishers (only
  the musket lines go in).
- **Measured.** See docs/STATUS.md (slice 2c).

### The town plan (shared), phase A, 2026-10-20

The city on the map is the city you fight in (owner, 2026-10-20: "use the buildings from the overworld city and actually build the
battlefield with those same features"). Two generators (the overworld's `town_plan.gd`, the battle's `sim/mapgen.gd`) become one plan.
Phase A is data and a pure function; the battle map reads it in phase C.

- **Bake.** `tools/town_bake.gd` runs the overworld generator once per pack (floats allowed there: it is committed data) and writes
  `campaign/data/town_sites_<pack>.gd`, a `SITES` dictionary by region key. Everything is an integer in centimetres in the town's local
  frame (origin the town centre, x east, y south: the frame the pieces use; a metre of a piece is 1.2 map px). Rome 36 towns, 138 KB; West
  49 towns, 187 KB.
- **Site** (`CTown.site(r)`, decimetres): `foot` (48 vertices, the full footprint), `shore` (the harbour shore polyline, [] inland), `mouth0`
  / `mouth1` (the shore's seaward end and its other end), `high` (the highest ground in the outer footprint), `sea_dir` (0..1023
  anticlockwise from east, -1 inland), `streets` (segments), `plaza`, `lots` (`[x, y, yaw, size, hh, burn]` in fill order; `hh` and `burn` are
  the colour / sack hashes, baked so the view does not depend on rounding), `steep` (16 sectors), `coast` (48 x 48 land bits at 25 m a
  cell centred on the town; the footprint is only about three cells across, the shore polyline is the fine detail). Extras for the
  overworld view (`CTown.baked(r)` in centimetres: `rad`, `fields`, `ring`, `ring_road`, `clear_r`, ...).
- **Plan** (`CTown.plan(st, r)`, a pure function of the baked site and the state's facts; JSON-plain, identical on every client):
  `kind` (town / native / maya / haven / roman), `level`, `walls`, `harbour`, `shipyard`, `owner`, `scale` (per mille: 620 / 800 / 1000 by
  level, x 0.92 for native / Maya / haven), `foot` (scaled, the full size towards the harbour), `wall` (the wall trace at 0.93 of the
  footprint; open on the harbour side; [] at walls 0 and at a West harbour's walls 1, which has a fort beside an open town), `gates`,
  `landmarks` (`{p, x, y, yaw, w, d, h, fort, kind}`: forts (`fort` 1, a fort with an inside for the 2c machinery), civic, the sea wall,
  props), `civic` (the plaza piece). `CTown.PD` (piece sizes) and `CTown.LM` (landmarks by region key) moved here from `town_plan.gd`.
- **View.** `TownPlan.site(r, true)` rebuilds its site dictionary from the baked record (so every draw reads the shared data); the old
  generator stays for the legacy region-hop view and for the bake.

### The town plan (shared), phase C: the battle map from the plan, 2026-10-20

A campaign settlement battle is fought on the overworld town. `CTown.battle_plan(st, r)` turns `plan(st, r)` and the site's shape
into the battle map's canonical frame (the sea up, or an inland town's back: away from its main street's far end; the attackers
down; the plaza at the origin; decimetres, integers only: piece names and kinds are indices of `MapGen.TP_NAMES` / `TP_KINDS` /
`TP_LKINDS`) and `CBattle.city_dict` carries it as the city's `tp`. `sim/mapgen.gd` builds the map from it (`tp_geom`); scenario keys and
custom battles carry no plan and keep the generators.

- **Scale** (`tp_scale`): as much town as the generated maps (a West open town 85 % of its band's area; a walled plan its culture's
  outline: the castrum's rectangle 2.4 r2, the others' disc, r = `R_LEVEL`), a West town's plaza to its landward edge at most 66 % of the
  band's depth (the generated band's own: the street fight as long) and drawn out along the shore up to 1.5 times that scale for the
  rest of its area (no wider than the band), a walled plan's span at most 3.2 radii. Landmark pieces keep their kit size (civic and
  props x 1.25; a fort with an inside the 2c trace's size).
- **Shore**: the plan's harbour shore (scaled, along x) is a table after the coast_params layout (`shore_y`, `TP_TAG`), with the
  seed's two waves on it; beyond its ends it runs on the end's slope. It moves seaward where the plaza and the quay need room.
- **West open towns** (walls 0-2): the footprint is the outline (its landward and top sides per metre for `_w_bot` / `_w_top`), the
  plan's main street is the high street, its other streets (and the ring road from level 1) are cross streets traced round what
  stands, the generated cross streets, second street and lanes fill the gaps (no generated cross street within 30 m of a plan street's mouth), the plan's house slots
  are the first houses (the lot filler does the rest), street ends beyond the landward edge are the mouths.
- **Walled plans** (Rome, West walls 3): every fourth footprint point is the walls' trace (towers by the culture's plan), points on the
  shore are the sea wall, the plaza at the plan's; the citadel stands at the landmark fort (else, for a polis or Punic town, on the high
  ground); the culture's street lattice inside.
- **Landmarks**: the town's fort with an inside (`tp_fort_pick`: a fort of its own table first, not the governor's alcazar; else the
  generic harbour fort; else the generic city fort) is the 2c fort on the piece's own trace (since 2026-10-20, "Fort traces from the
  piece" below: the Morro's triangle, San Marcos's bastioned square, scaled to the area of the 2c square 85-115 % of the generated one
  by the piece's size; turned with its gate to the plaza; on the shore with its seaward line on the waterline; the Ulua out on the
  water with a causeway 8 m wide to the shore and its gate to it). On a walled plan the fort is the citadel ring (still the culture's
  six-sided ring under the piece). Every other landmark is a solid
  stone body of the piece's size at its place (`B_PIECE`, or `B_FORT` for a second fort, `B_TAVERN` / `B_GOVERNOR` where it can be
  held); the plaza's civic piece is the town's church (`B_TEMPLE`, held as any church) or the owner's shrine; Cartagena's sea wall is a
  2 m stone run on the waterline with its baluartes. Bodies carry entry 17 = 1 (drawn as their piece).
- **View**: the layout's `pieces` (`[piece, x, y, front angle, scale per mille, radius, 1 = the fort with an inside]`) are drawn from the
  battle kit's block 2 (`BattleKit.draw_piece`, the pre-lit atlas) by a node of the kit under its walls and houses (`city_draw.gd
  draw_pieces`; the preview draws them in `draw_static`); a fort's piece lies under the kit's walls at the trace's scale and turn (its
  rock and corner towers show, the walls on its rampart).

### Fort traces from the piece (as built, 2026-10-20)

Owner (Havana's Morro): the fort's wall ring was the generic 2c bastioned square laid over the Morro's triangle, so the piece showed
through and the walls did not follow it. Each landmark fort's trace now comes from its own piece's outline.

- **Data.** `tools/battlekit/fort_trace.py` (pure Python, from the minis' geometry `tools/structures/spec.json`, the parts lists the kit
  pieces are built from) takes each fort piece's rampart: the boxes and polygons of coquina, brick or stone standing within 2 m of the
  ground (else the lowest masonry body: the rock fort's top), unites their footprints and keeps the corner towers (a masonry cylinder
  on a vertex: its radius). Salients: a bastion is a run of convex vertices between reflex ones, its point the run's middle vertex, or
  with an even run the middle edge (a turned-square bastion's flat nose); with no reflex vertex every corner. The gate edge: the
  longest of the edges facing the piece's front most (a quarter of the longest or more). Output in the piece frame of
  `BattleKit.piece_foot` (metres, y down, the front at -y): `trace` in each piece's `_frames/<piece>.json` (`build.py` adds it after
  rendering a fort piece) and the generated `sim/fort_traces.gd` (decimetres: vertices, salient flags, interior angles, tower radii,
  the gate edge, the parade's centre = the centroid, the area), which the sim reads (the sim does not read the view) and
  `BattleKit.piece_trace(name)` reads for the view. Built: Morro triangle (3 salients, towers r 3.1 m), Morro of San Juan 26 x 14
  rectangle (4), Fuerza square with four flat-nosed bastions (16 vertices), San Felipe triangle (3), harbour fort rectangle (4,
  towers), San Marcos square with four bastions (24 vertices: shoulder, nose, nose, shoulder, flank, gorge), Ulua rectangle with four
  bastions (16), Fort Charles rectangle (4), rock fort (its top, 4), the generic city fort square (4, towers).
- **The fort on it** (`MapGen.tp_fort_shape` / `tr_shape`, `_tp_fort_tr`, `_w_fort_tr`; plan towns' forts at walls 1-2, the 2c
  machinery otherwise unchanged; the generated maps' forts keep the square). Scaled to the 2c square's area (its `F_H` / `F_B` by
  level and the piece's size), the piece drawn at that scale (`pieces` entry: the trace's origin, its turn, its scale); a flank shorter
  than 12 m (San Marcos's) is dropped, its face and curtain run on to meet. Turned with its gate edge to the plaza (the Ulua's to the
  shore); on the shore the edge the seaward ray from its origin crosses lies on the waterline (its seaward point at least 4 m inside
  the map). The walls (`_wall_band`) on its edges; its corner towers round C_TOWER outside the walk (the walk turns the corner
  through them); an acute salient's parade tip narrower than 3 m is rampart; the main gate in the middle of the gate edge, the sally
  port in the edge most nearly opposite (24 m or longer, not on the sea); stretches cut 7 m short of a salient (an acute one's by its
  cotangent, 18 m at most), 4 m of another convex corner, 2 m of a flat nose's ends and a reflex corner (a slanted stretch's end cell
  made walk); the parade is the open ground reached from inside the main gate, open ground it does not reach is rampart at the walk's
  level (a bastion's terreplein, the inner face beside it too; shut in by a building: solid); the ditch round the land edges; the
  barracks along the longest other edge, the magazine on the sally port's edge a quarter along; guns on the landward salients (2 m in,
  or a flat nose's middle) and on the most seaward edge; the citadel's middle (cit x, y: the guns' embrasure arcs, `fort_cmp`) the
  parade's centre. The knoll's parade is levelled inside the trace and 2 m round it (`terrain.gd`). Nav: ring nodes at the trace's
  reach, parade nodes over it.
- **Agreement** with the overworld (`tests/town_plan_test.gd`): for every region and every level 0-2, walls 0-3 the landmark set and
  its turn round the town are the same in `CTown.plan` and `TownPlan._build`, the civic piece too (`CTown` follows the overworld's
  rules: the generic level 2 fort / tower 14 m from the church in centimetres, no church outside the town). Known: Port Royal's
  gallows and waterfront taverns, where the overworld's `_put` finds water on the live coast field (the fix: `_build` placing
  landmarks at `CTown.plan`'s points).

### Balance pass on plan maps (as built, 2026-10-20)

The walls rows retuned on the campaign towns' plan maps (STATUS "Balance pass on plan maps" has the tables). Measured with
`tests/town_balance.gd --town=<pack>:<key>` over 16 Spanish West towns, the brief's set (Havana, Cartagena, Port Royal, Veracruz, Santo
Domingo, a native and a Maya town) and six Rome towns, 16 seeds each. A town's own result swings widely (the West street fight is an
attrition race the attackers quit near even losses; generated maps swing as much), so the targets are read on the pooled towns. All of
it applies to plan maps only (a city with `tp`); scenario keys and custom battles are unchanged.

- **Street mouths.** A generated cross street of a plan town that stops short of the landward edge (the fort's ground or a landmark in
  its way) is traced from the edge inward instead and reversed: it keeps its street mouth (Havana walls 1-2 had 2 mouths, now 6).
- **The approach round a fort in the road.** A plan's fort landward of the plaza and within its reach + `W_LANE_CLEAR` 60 m of the
  attackers' road (Cartagena's San Felipe on the high ground) moves the road (`att_x`: the attackers' deployment and the mouths' order)
  to the fort's far side, its reach + 60 m from it.
- **The walls-2 palisade** (`_tp_palisade`): 9 m outside the plan's whole landward side, up its flanks (a 4-connected line of 2 m cells),
  broken by buildings and the sea; where a road crosses, its gap is narrowed to its middle `W_PAL_GAP` 2 cells (4 m), stakes across the
  rest. (The generated palisade's column-by-column run broke on a round plan's flanks and left every road's full width open.)
- **A plan oppidum's main gate.** A walled plan of the oppidum culture (natives, the Maya, the Gauls) gets its main gate facing the
  attackers (`g_want` 256 first), as the other plans: the plan has no funnel, and had no gate at all.
- **Attackers press on in an open campaign town** (AI.md 29): `S_BEATEN_TOWN_PCT` 25 % in place of `AP.S_BEATEN_PCT` 35 % (Average,
  Hard) for the attackers of a plan map with no outer gates (West walls 0-2).

**Rome walls 1-2 (2026-10-22, AI.md 33).** On a walled Rome plan the defenders' street stack behind the breach holds at most `S_ROME_STACK` 4 units (the rest hold the plaza) and the storm's non-pike foot outside the houses attack at the run. Rome pooled attacker wins at 32 seeds, walls 1 / 2 / 3: 36 / 27 / 21 -> 58 / 35 / 23 % (targets 56 / 38 / 25). The West and generated maps are untouched by construction. Open: the citadel fight on the Greek and Punic plans (the plaza is the citadel), the castrum at walls 2, gate HP at walls 2.

## Destruction: walls and buildings fall (plan, agreed 2026-10-23)

The owner, 2026-10-23: "Cannons being able to damage and destroy walls and buildings. Occupied buildings that fall
should kill the units that are still inside. Same with falling wall sections. This should affect both Rome and
Caribbean sides." Gates already have hit points and break (`g_hp`, `GATE_BROKEN`); wall stretches, towers and houses
are indestructible, and a flat shot that meets a wall or a house stops dead (`bk_*`, a puff of dust). Rome 2 lets
onagers breach walls and artillery level buildings; this plan does the same, in the sim, deterministic, hashed.

**Wall stretches.** Every walkway segment (`ws_*`) gets hit points `ws_hp` / `ws_hp0` (centi-hp like the gates) from
the walls level: 1,200 / 2,000 / 3,000 for walls 1 / 2 / 3 (a fort trace's wall the same by its level), and a state
`ws_state` (standing / breached) with `ws_hit_t` for the view. Damage comes from missiles with `m_obj` (what a gate
takes: a stone 360, a culverin 450, a heavy gun 700, a bolt 80, a mortar shell as its blast stat) when a flat shot is
stopped by the stretch's wall cells (`bk_*` records where; the shot that hits a wall damages the stretch that owns
the cell) or an arcing shot lands on the stretch's cells; a ram at a wall is not in this plan (rams stay for gates).
At 0 the stretch is **breached**: its cells become passable rubble at the broken gate's cost (the nav masks change as
they do for a broken gate: look at `GATE_BROKEN`'s path), the parapet is gone (no wall height, cover or
missile-stopping on those cells), the men on it at that moment each die with BREACH_KILL_PCT (60 %) chance (the
sim's RNG, index order) and the rest are thrown to the nearest ground cell inside the wall, shaken (`u_hit_t`, a
morale blow); a stretch's stairs and the towers at its ends stand (towers are not destructible in this plan). Events:
`stat_breaches`, an event for the view (`EV_BREACH` with the stretch) for dust and rubble; the Chronicle / result
panel counts breaches.

**Buildings.** Every house of a town (`ob_*` for the holdable ones in the West; the same table extended to every
building piece so Rome's houses count, with `ob_ok` 0 where they cannot be held) gets `ob_hp` / `ob_hp0` by its
footprint (300 + 60 per cell, a stone house of a Rome capital 1.5x: whatever the plan records say of its material;
keep it simple and say what was chosen) and a state (standing / rubble). The same missiles damage it (a flat shot
stopped by the house, an arcing shot or blast landing on it; a mortar shell hurts buildings most). At 0 it
**collapses**: the unit holding it loses COLLAPSE_KILL_PCT (70 %) of its men (each man with that chance, RNG, index
order), the rest come out at the door shaken; the footprint becomes rubble: passable at the rubble cost, no longer
holdable, no line-of-sight block (half if cheap: say), and the cover trait still works in it (ruins). Fire is not in
this plan (fire pots burning a house down is a later item; note it). `stat_collapses`, `EV_COLLAPSE`.

**View.** `battlekit.gd` draws a breached stretch as a gap of rubble between its towers (a new piece state like the
gate's broken look: fallen stone, a dust haze fading over 10 s via the overlay's FX_BLAST ring at the moment) and a
collapsed house as a rubble footprint in `city_draw.gd` / `city_layer.gd` (both styles, Low graphics too); the Paths
overlay hatches rubble as walkable-slow; the unit card of a unit inside a building shows the building's hit points
as a small bar when it is under fire. The result panel lists breaches and collapses.

**Determinism and hashes.** All new arrays are sim state captured by `snapshot()` / `restore()` automatically and
hashed in `state_hash()` only when `city_on` (so open-field battle hashes do not move); the fortified scenarios'
determinism and custom battle pins move and are re-pinned. `tests/lockstep_test.gd` must pass.

**AI (a follow-up, after the sim lands).** Besieging artillery aims at the stretch nearest the planned assault (or
the gate's flanks) until it breaches, then the assault treats the breach as an entry like a broken gate; the defender
moves men off a stretch under heavy fire and out of a building below a third of its hit points. Campaign: walls
damaged in a battle are repaired by the next turn (no persistence in this plan; a later item: repairs cost gold).
Balance: re-run `tools/balance` rome_walls and west_walls after; breaching should make the attacker's odds against
walls 2-3 rise a few points, not flip them.

**Owner's addition (2026-10-23).** "The rubble should leave a patch that allows for low cover": a breached stretch's
and a fallen building's cells are a terrain patch of kind rubble with low cover (cover-trait units as among rocks,
other foot RUBBLE_COVER_PCT 35 % of it, riders none), no line-of-sight block, a Key row and a Paths legend line.

### Destruction (as built, 2026-10-23)

Code: `sim/battle_sim.gd` section "destruction" (`_setup_destr`, `_destr_graph`, `_destr_restore`, `_destr_at`,
`_destr_hit`, `_breach`, `_breach_throw`, `_collapse`, `rubble_at`, `occ_hp_pm`; hooks in `_land_bolt`,
`_land_stone`, `_land`, `_nav_of`, `_obs_top` / `_cell_top`, `_obs_run`, `_cover_at` / `_cover_from`, the march
speed, `_node_open`, `_roots`, `reach_at`, `wall_snap`, `spill_end` / `ws_join`, `_wall_col_goal`, `_climb`,
`_ladder_start`, the occupy refusals, `restore()`, `state_hash()`), `sim/mapgen.gd` (`C_RUBBLE` 32, never set by
the generator), the view (`game/battlekit.gd` `_RubbleDraw` / `fallen` / `_rubble_changed`,
`game/battlekit_shadow.gd` `rebake_rect`, `game/city_draw.gd` `rubble_cells` / `draw_rubble`,
`game/city_layer.gd` the no-kit rubble and the Paths mask, `game/overlay.gd` FX_RUIN and `_destr_events`,
`game/hud.gd` the card's building bar and the Paths tooltip, `game/battle.gd` `destr_line` and `--demo-breach`,
`game/unit_book.gd` "Breaches and ruins"), test `tests/determinism_test.gd` `_check_destr` (`--only=destr`).

**Hit points (centi-hp, as the gates).** A stretch: WS_HP 1,200 / 2,000 / 3,000 by the walls level (a West fort's
trace the same by its level). Its cells: every wall-body and walkway cell (C_WALL / C_WALK) within the wall's
thickness of a walkway stretch's centre line goes to the nearest stretch (`ws_cell`); wall cells with no walkway
stretch near (a citadel ring without a walkway, short spans between close towers) belong to none and stand, as do
towers, stairs and gates. A building: every record of the layout (`map_info` city "buildings", index order: Rome's
houses, temples, markets too; `ob_ok` is unchanged, so what can be held is as before) owns its C_BUILDING cells
(rect: the cell centre inside; quad: the outline grown 0.6 m, as `occ_bg`; round: the radius + 1 m; then two
passes give a stray cell to the building beside it; every building cell ends with an owner on the maps checked).
Its hit points: OB_HP_BASE 300 + OB_HP_CELL 60 per cell; a West stone house (record material not timber) x
OB_STONE_PCT 150 %; timber and every Rome house 100 % (the Rome records carry no material; "a stone house of a
Rome capital 1.5x" was not built: say if wanted).

**Damage.** What a gate takes from the same shot, from the attacking side only (the defenders' own shots never
hurt their walls: their towers' engines fire out over them; buildings are hurt by either side): a flat shot
(`_land_bolt`) stopped by the line of fire (`lof_block`) at a stretch's or building's cell, looked for at the stop
point and 1 and 2 m on: GATE_BOLT 80 x ammunition `obj` % x the type's `m_obj` % (a bolt 80, a falconet 160, a
culverin 360, a fort gun 240); a lobbed stone or shell landing on one (`_land_stone`, not when it struck a tower):
GATE_STONE 360 x `obj` %, plus DESTR_BLAST_K 60 per metre of blast for a bursting (aoe) shell (the stand-in for "a
mortar shell as its blast stat": mortars are not in the roster yet); on a building a lobbed shot does OB_ARC_PCT
150 % (through the roof). So a stretch breaches after 4 / 6 / 9 culverin or stone hits (walls 1 / 2 / 3), 15 / 25 /
38 bolts; a 20-cell Rome house falls after 3 stones.

**Breach.** `ws_state` 1, `ws_hp` 0, `stat_breaches`, `rub_n` + 1, the event EV_BREACH (stretch) in the view ring
`ev_k / ev_a / ev_t` (EV_N 32; not hashed, like `bk_*`). The men standing on the stretch's cells (every unit on a
wall or a stair, soldier index order) each die with BREACH_KILL_PCT 60 (the sim's RNG; credited to the shooter's
unit). The cells become C_RUBBLE: nav ground (as a broken gate's cells), no height for the line of fire or the
walkway, no cover from the wall. A unit on the stretch (or climbing a stair or ladder to it) is a ground unit again
(`u_wall` / `u_stair` 0, no order, files at most half its men); its survivors on the stretch, a joined stretch's
walkway, a tower or a ladder are thrown down inside (`_breach_throw`: from their place along the stretch, in past
the walkway to the first ground that is not rubble, else beside the stretch's inside point), those at a ladder's or
stair's foot stay; a unit on another stretch that had men on this one takes them back to its anchor. A tower's
engine crew (a wall unit of the stretch beside its tower) stays: the tower stands. Shaken: `u_hit_t` and
DESTR_MORALE 150. `nav_epoch` + 1 (paths replanned, routers' exit fields restarted). Joins: `ws_join` (a breached
stretch is joined to nothing), `wall_snap` skips it (a tap on the rubble is a ground move), nobody climbs to it
(`_climb`, `_ladder_start`). The way in: per stretch (not facing the sea) a closed pair of street graph nodes
inside and outside its middle (`ng_gate` -2 - stretch, joined to each other and to the four nearest nodes in
clear sight on each side; open when breached: `_node_open`), and the pieces of open ground beside its cells
(`ws_cmp`) joined in `_roots` once it is breached, so `reach_at` / `reach_snap` / the planner see one piece.

**Collapse.** `ob_state` 1, `stat_collapses`, EV_COLLAPSE. The unit holding it (West, `ob_u`) loses each man with
COLLAPSE_KILL_PCT 70 (RNG, index order), the rest come out at the door (`_occ_leave`), no order, shaken
(DESTR_MORALE); units sent to it lose the errand. Its cells are rubble; it cannot be held again ("it has fallen").

**Rubble.** C_RUBBLE cells: ground for everyone (horses too), the march at RUBBLE_SPEED 600 per mille with the
anchor on it, no line-of-fire or sight block (sight in towns never used the houses), stones plough on through it.
Low cover (the owner's addition): a cover-trait man standing in it has COV_RUBBLE, COVER_STOP 60 (as COV_ROCK),
gone-to-ground on top as anywhere; any other foot man (not a rider, not on a wall) there has a missile or ball
stopped with COVER_STOP x RUBBLE_COVER_PCT 35 % = 21 % (`stat_rubble_stop`); artillery and melee unchanged. Fire
pots burning a house down are a later item.

**State and hashes.** New sim state `ws_hp`, `ws_hp0`, `ws_state`, `ws_hit_t`, `ob_hp`, `ob_hp0`, `ob_state`,
`ob_hit_t`, `rub_n`, the events ring and the stats are script variables (snapshotted); `ws_hp`, `ws_state`,
`ob_hp`, `ob_state` are hashed with `city_on` only (open-field hashes unmoved). Static (setup; out of snapshots):
`ws_cell`, `ob_cell`, `ws_cmp`, `ob_cmp`, `ws_in`, `obs0` (the generator's cells; `restore()` writes the fallen
pieces' rubble back onto `obs` from it, `nav` is snapshotted), the breach nodes in the street graph. Before any
breach the closed nodes are never used, so the paths are as before; the fortified hashes move by the hashed
arrays.

**View.** The kit (High and Low) draws the rubble over the wall strip and the houses before it, under the gates
and towers: a dusty bed a little wider than each 2 m cell with broken stones by a hash of the cell (4 a cell with
shadows on High, 2 on Low); a fallen building's pieces are hidden (zero-size instance on High, skipped on Low) and
its shadow and the wall strip's under a breach are baked again. The drawn style without the kit draws the same
rubble on the gates node. At the moment of the fall the overlay puts FX_BLAST dust rings along the stretch (four)
or on the house and an FX_RUIN haze fading over 10 s; a gate-break sound plays. The Paths hatch: rubble in a
sparser amber hatch the other way (mask value 128), rebuilt when rubble appears; its tooltip: "Red: cannot be
crossed. Amber: rubble: slow going, low cover (a breached wall, a fallen house)". The battle has no map Key: the
Key row is the book's "Breaches and ruins" paragraph (Settlements and sieges page). The unit card of a unit holding
a building hit in the last 30 s has a thin bar for the building's hit points over its headcount bar (red below a
third) and "building N%" in its summary. The end dialog and the result panel title add "N wall stretch(es)
breached, N building(s) fallen, N men lost in the ruins". Testing aid: `--demo-breach` (the first wall unit's
stretch and the three buildings nearest it knocked down).

**AI.** Untouched (the follow-up stands). It does not crash or misuse rubble: its wall orders to a breached stretch
become ground moves into the breach, its ladder parties at a breached stretch stand at the foot, and its paths use
a breach once open like any street.

**Tests.** `tests/determinism_test.gd --only=destr` (also in the full run): stretches breach after 4 / 6 / 9
culverin-weight hits (walls 1 / 2 / 3, three city seeds each); 139 of 208 men on them lost (66 %); with the gates
shut an attacking foot unit gets in through a breach (tick 1,160); stone throwers ordered at a wall unit take 2,880
off its stretch; a held West house falls after 7 lobbed hits and its company loses 243 of 320 (75 %, four seeds),
the rest out on the ground, the house unholdable and rubble; arrows are stopped 17 % of the time at a man without
the cover trait in rubble (0 % in the open; want about 21), 61 % at a cover man there (rocks 60); a breach repeats
exactly and survives snapshot / restore. The flat goldens and every open-field run hash are unmoved; the fortified
runs' final hashes moved (cit_ops, gate_ops, siege_castrum / city / hill / oppidum / polis / punic / village@ai,
siege_eq_ring3; not pinned constants, so nothing re-pinned).

**Harness** (`tools/balance`, attacker wins %, 16 seeds; HEAD `5eef2c9eee` -> `d4109e6517`): rome_walls pooled walls 1
/ 2 / 3: 58 -> 58, 34 -> 32, 25 -> 24 (no cell beyond its interval); west_walls pooled walls 0 / 1 / 2: 53 -> 54,
38 -> 39, 31 -> 34 (none beyond its interval). The aim (walls 2-3 up a few points) is not met in Rome and only
just in the West: the AI does not aim at walls yet, so breaches come only from shots at men on them. It is the AI
follow-up's to deliver.

### Destruction AI (as built, 2026-10-23)

The follow-up of "Destruction (as built)": the battle AI uses breaches. Code: `sim/siege_ai.gd` section
"destruction AI" (`_wall_dmg`, `_can_batter`, `_batter_stretch`, `_batter_for`, `_batter_spot`, `_wall_breach`,
`_breach_go`, `_battered`, `_leave_ruin`, `_cover_near`, `_plug_breaches`, `_plug_unit`, `_cit_breached`; hooks in
`_army`, `_att_art`, `_storm`, `_defender`, `_strongpoint`, `_wall_shift`), `sim/battle_sim.gd` (the wall target
order and its fire path: `wall_tgt`, `ws_aim`, `ws_way`, `ws_side_pt`, `_art_fire_wall`, WS_AIM_OUT,
`stat_wall_shots`), knobs `sim/ai_profile.gd` 275-282 (docs/AI.md 35). Stateless: every choice is made again each
think from hashed state (the stretches' and buildings' hit points and hit ticks, the units), so no new AI memory.

**The order.** An attack order with `"wall": stretch` (artillery of the attackers only, a standing stretch, a town
map) sets the battery on the stretch: `u_gtarget` = -2 - stretch (the breach graph nodes' convention; -1 none, a
gate >= 0, so every place that clears or tests a gate target is unchanged). The battery turns to it and its engines
shoot its aim point (`ws_aim`: the stretch's middle; a lobbed shot on the walkway's centre line, a flat one WS_AIM_OUT
2 m outside the outer face at body height, its line running on into the masonry), with the gate shot's spread and
range rules (`_art_fire_wall`); the shot does its work where it lands as any (`_land_bolt` / `_land_stone`). The
order ends when the stretch is breached. A player could give the same order; no UI for it yet.

**Batter the wall.** In the approach, with the attacked gate shut, a battery batters (`_batter_for`) when
`S_BATTER` is on, it is within `S_BATTER_T` of the approach's start, its standard shot does `S_BATTER_DMG` or more
to a wall (a bolt 80 never; falconets 160, culverins 360, stones 360, heavy guns 560, a bursting shell 360 + its
blast), it is a breaker (a lobbing engine or a flat gun of BATTER_HEAVY 400 or more) or the side has no breaker
(lighter flat guns only then), it is within the side's `S_BATTER_PCT` share (by unit index), and its shots left at
BATTER_HIT_PCT 40 % hits would breach the stretch (else it shoots men as before). The stretch (`_batter_stretch`,
the same for every battery so they focus): standing, with a way through it (`ws_way`), not facing the sea, not the
citadel's, its middle within BATTER_GATE_R 100 m of the attacked gate's face; nearest the gate, a stretch already
hurt counting 1 m nearer per 10 hit points off. The battery shoots from its place on the gate's firing line when
the aim point is within 85 % of its range from there (a lobbing engine) and, for a flat gun, in clear line; else it
stands `S_ART_OUT` (at most 85 % of its range) out from the aim point along the wall's outward line, spread as
before, a flat gun stepping up to 40 m aside for a clear line (a first build always moved there: a polis stone
battery crossing the walls' front lost its crew to the towers' engines).
Counter-battery fire at the towers by the gate comes first, as before. If the gate falls first, a battery whose
stretch is already hurt finishes it from where it stands while no breach is open (a second way in). In the assault,
with the citadel's gate (or a stormed West fort's gate) shut, the same rule batters the citadel's wall (SEG_CIT) or
the fort's beside that gate. Battering counts as the attack's progress for the stall watch (as gate damage).

**Assault through the breach.** A breached stretch with a way through (not the citadel's, not facing the sea; a
West fort's only when it is stormed) is an entry like a broken gate: the approach turns to the assault
(`ai_gate` stays the plan's gate). The `S_BREACH_UNITS` foot units of the side outside the town nearest the
breach's outside point (no shock role exists yet: the nearest foot, ties by index) go in through it at the run to
the rubble's inside edge, then storm as any (`_breach_go`); as they get in the next nearest follow, the rest storm
by the streets as before (their paths use the breach once open). Ladders are not used there. A new breach in a
running assault is picked up on the next think (the choice is stateless). A breach in the citadel's wall makes its
shut gate no longer keep the storm out (`_cit_breached`).

**Defenders.** A defender wall unit (not a tower's crew) on a stretch under `S_WALL_LEAVE_PCT` of its hit points and
hit within 10 s goes to a stretch joined to it through a tower that stands unbattered with fewer than two units of
ours on it, else down to the ground 8 m behind its place (then a reserve there); wall shifts skip a battered or
breached stretch. A unit holding a building under `S_RUIN_LEAVE_PCT` of its hit points comes out to the best cover
within 24 m of its door (`_cover_near`, the strongpoint score) and holds it; such a building is not taken up again
(`_strongpoint`). The plug (`S_PLUG`, army level): each breach of the walls with a way through gets `S_PLUG` units
of ours, the nearest first: reserve foot (A_RESERVE, A_PLAZA) or foot of the stack at a gate still shut (A_MOUTH:
it waits for a gate nobody breaks), not fighting, not in a building, not on a wall; they become A_PLUG 38 and stand
side by side PLUG_GAP 14 m apart along the rubble's inside edge facing out, fight attackers within 25 m of it, and
go back to it when led more than 75 m off.

**Knobs** (`ai_profile.gd` 275-282, Easy / Average / Skilled): `S_BATTER` 0 / 1 / 1, `S_BATTER_DMG` 150, `S_BATTER_PCT`
0 / 100 / 100, `S_BATTER_T` 0 / 4,800 / 4,800 ticks, `S_BREACH_UNITS` 2 / 3 / 4, `S_WALL_LEAVE_PCT` 0 / 33 / 33,
`S_RUIN_LEAVE_PCT` 0 / 33 / 33, `S_PLUG` 0 / 4 / 4. Easy never batters, never leaves a stretch or a building and
never plugs; it does send its two nearest foot through a breach that opens.

**Measured and tuned** (`tools/balance`, attacker wins % pooled by walls level; before `c53664c3b6`). Build 1
(batteries moved before the stretch, one plug): rome_walls 58 / 32 / 24 -> 70 / 52 / 26. Build 2 (from the gate's
firing line when it reaches: the polis stone battery no longer crosses the towers' front, one plug): 88 / 65 / 47, a
breach in 95 of 96 battles a level, 0.5-1 min before the gate used to fall: the breach beats the defenders' stack
waiting at the gate mouth. Tuned (two knobs): `S_BATTER_T` 4,800 -> 2,400 (8 seeds, build 1) cut walls 3 (the
latest breaches) far more than walls 2 and went back to 4,800; `S_PLUG` 1 -> 3 / 4 / 5 (8 seeds) 92 / 44 / 38, 81 / 52 /
23, 60 / 29 / 19; kept 4. `S_BATTER_PCT` does not bite in Rome (one stone-thrower unit a side; the share is by unit).
Final (16 seeds, `a6c41d737a`): rome_walls walls 1 / 2 / 3 58 -> 74 (beyond its interval), 32 -> 44, 24 -> 20; by
town the swings are large both ways (Latium walls 2 6 -> 75, Sicilia 38 -> 75, Zeugitana walls 1 25 -> 69; Arverni
walls 2 81 -> 12, walls 1 62 -> 31). A stretch was breached in 96 / 95 / 95 of 96 battles a level, before the gate in 95 / 94 / 86 (median 1.3 / 2.5 / 3.2
min). west_walls walls 0 / 1 / 2: 54 -> 51, 39 -> 38, 34 -> 34 (Port Royal walls 0 75 -> 44 the one cell beyond its
interval: the building rules); no West battery battered in 768 battles: the West plan towns have no outer wall
(`n_outer` 0) and the fort is left be (`ai_fort` 1) in these sets, so the 1 / 5 breaches at walls 1 / 2 came from
shots at men. The aim (walls 2-3 up 5-10, not flipped): walls 2 +11,
walls 3 missed (-4), walls 1 over (+16).

**Tests.** `tests/determinism_test.gd --only=destr_ai` (also in `--only=destr` and the full run), `_check_destr_ai`:
AI against AI, walls-1 fair sieges with no kit (seeds 41-43): the stone throwers breach a stretch within
DAI_BREACH_T 4,200 ticks, an attacker is on the breach's rubble within DAI_ENTER_T 1,800 of it, and the defender unit
on the battered stretch was off it when it fell (one a seed at least). The fortified runs' final hashes moved;
coverage needs updated where the way in is now a breach (siege_city@ai and siege_oppidum@ai: `wall_shots`,
`breaches` for `gate_art`, `gate_broken`; siege_polis@ai and siege_eq_polis2~sa: `breaches` for `gate_broken`;
siege_eq_ring3: `breaches` for `gate_broken` and no `tower_hits`, the early breach starts the assault and the bolts
shoot men); the layout check counts a breach as the gate's fall and a plug's counter-attack as the plaza reserve's.
Final hashes (before -> after): siege_city@ai e64e86f4 -> 7799cda0, siege_castrum@ai a8819f1e -> 68824802,
siege_polis@ai 1a227d83 -> 440bd398, siege_punic@ai b321be2e -> 19c6aebe, siege_oppidum@ai 5eed0f81 -> 90f45c33,
siege_city@ai~ea 3e1f6181 -> 055dd17d, ~ae 3a92750b -> 624a7a33, ~sa 3a5fb759 -> f9166c03, ~as 60cd3d58 -> 2d3e366c,
siege_eq_ring3 2463e9e1 -> 9edb502b, siege_eq_polis2~sa c8c13afd -> 652dfe0e; the goldens, every open-field run,
gate_ops, cit_ops, siege_village@ai and siege_hill@ai unmoved.
