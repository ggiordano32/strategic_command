# Strategic Command — Status and Handover

Last updated: 2026-10-07 (cities worth defending, part 2b: siege equipment as objects, the ladder shuffle and wall-punching bugs; part 2a: units do not pass through each other, street fights; part 1: tower engines, ladders, a ram, hard gates, the battle time limit; earlier 2026-10-06: deployment phase and custom battles built; the continuous campaign overworld built, state format 6; free campaign movement built; sieges and battle odds built on the campaign map; settlement variety built 2026-10-05). Read this first, then `docs/DESIGN.md` for the full
design and `CLAUDE.md` for working rules. Update this file whenever a
milestone lands or the plan changes.

## What this is

A 2D, top-down, co-op grand strategy game inspired by Rome 2: Total War, in
Godot 4 (GDScript), played in a browser on phones and desktops. Two friends
play an asynchronous turn-based campaign against AI factions and fight
real-time battles solo or together. Built for two players first; accounts,
anti-cheat and original art only if it proves fun.

## Where we are

| Milestone | State |
|---|---|
| 1. Battle sandbox | Done, committed (`6b3a1cf`), playtested on an Android phone |
| 2. Full battle mechanics | Done, committed (`49c1022`), playtested; tuning pass included |
| Unit symbols and unit book | Done, committed (`49c1022`) |
| Artillery (bolt and stone throwers) | Committed (`49c1022`), not yet playtested |
| Terrain height | Built, **not yet committed**, playtested ("feels good so far") |
| Playtest round (HUD scale, stones, ammo, refill) | Built, **not yet committed**, not yet playtested |
| 3. Minimal campaign | Built 2026-10-05, **not committed**, not yet playtested (see below) |
| 4. Async backend (Go + SQLite) | Committed (`fad7399`); port 8060 runs it; first phone playtest done (live battles were missing) |
| 5. Live co-op battles (lockstep) | Built 2026-10-05, **not committed**; tested headless, end to end and in two headless Chromiums; the 8060 server binary is not yet updated; not yet played on phones |
| Battle maps with character (woods, city maps, palettes, shading) | Committed (`3522fd2`); not yet played on phones |
| Settlement variety (plans, sites, coasts, citadels, stairs, owners) | Built 2026-10-05, **not committed**; tested headless; not yet played on phones |
| Sieges and battle odds (campaign, state format 4) | Built 2026-10-06, **not committed**; tested headless and windowed; not yet played on phones |
| Free campaign movement (state format 5) | Built 2026-10-06, **not committed**; tested headless and windowed; not yet played on phones |
| Wall orders, drag clamp, reachability (playtest fixes) | Built 2026-10-06, **not committed**; tested headless and windowed; not yet played on phones |
| Continuous campaign overworld (state format 6) | Built 2026-10-06, **not committed**; tested headless and windowed; not yet played on phones |
| Deployment phase and custom battles (solo, co-op, head-to-head) | Built 2026-10-06 on a branch; tested headless, end to end and windowed; not yet played on phones |
| Cities worth defending, part 1 (tower engines, ladders, ram, hard gates, battle time limit) | Built 2026-10-07, **not committed**; tested headless and windowed; not yet played on phones |
| Cities worth defending, part 2a (units do not pass through each other, street fights) | Built 2026-10-07, **not committed**; tested headless (and the windowed input tests); not yet played on phones |
| Cities worth defending, part 2b (siege equipment as objects; ladder and wall-punching fixes) | Built 2026-10-07, **not committed**; tested headless, windowed input test, live_e2e; not yet played on phones |
| 6. Depth (siege towers, tech, more factions) | Not started |

### What exists

- **Battle sim** (`sim/`): deterministic, integer-only, per-soldier, 10 Hz.
  Nine unit types (heavy swords, light infantry, spearmen, pikemen, archers,
  javelinmen, shock cavalry, bolt throwers, stone throwers); melee with
  shields, armour and flank/rear bonuses; multi-rank pikes; projectiles with
  friendly fire; cavalry charges with knockdown and brace reflection;
  artillery engines with crews, set-up / pack-up, piercing bolts and
  ploughing stones; morale, routing, withdrawal; a battle
  AI that only issues orders; a plain-data battle result for the campaign.
- **Terrain height** (`sim/terrain.gd`, built 2026-10-05): an integer
  height grid (4 m nodes) generated from kind + seed + a few parameters
  (flat, rolling, ridge, valley, hill, slope, or hand-placed features),
  hashed into `state_hash()`; slopes slow units (cavalry and artillery most),
  higher ground helps in melee, charges hit harder downhill, missiles reach
  further from above, javelins and bolts are blocked by crests, stones
  plough less uphill; the AI uses high ground. Drawn as a contour map with
  hill shading in one shader. Details in DESIGN.md "Terrain height: as built".
- **View and controls** (`game/`): one-draw-call soldier rendering from a data
  texture, touch and mouse controls, multi-select, show-all-orders overlay,
  instant order preview while paused, unit symbols, unit book, HUD, telemetry.
- **Tests** (`tests/`): determinism, benchmark, scripted input (needs a
  window), balance matchups across seeds.
- **Tools** (`tools/`): web export, HTTPS dev server with telemetry logging,
  playtest report, script warning check, server build / run scripts.
- **Server** (`server/`, milestone 4): one Go binary with SQLite that serves
  the web build (brotli), the telemetry endpoint and the online co-op
  campaign API; Discord notifications; Dockerfile and deployment files.
  Reference: `docs/SERVER.md`. Client side: `game/net/`,
  `game/campaign/online_ui.gd`.

### What has been proven

- GDScript is fast enough: 4,000 soldiers cost about 9 ms mean, 30 ms worst
  per 100 ms tick on a Snapdragon 865 phone browser (milestone 1 build).
- The sim is deterministic across devices: an Android phone, a Linux desktop
  browser and the native Linux build produced identical hashes for the
  fixed-seed benchmark (milestone 1 build).
- The touch control scheme works; the user likes it.

### In progress right now

**Cities must be worth defending, part 2b: siege equipment as objects
(built 2026-10-07).** As built in DESIGN.md "Siege equipment and wall
towers" (the "Siege equipment as objects" and "No blows at walls"
bullets). In short:
- Ladders (sets of 5) and the ram are objects on the ground behind the
  attackers' line (scenario `equip`; campaign: 2 sets after a turn of
  siege, 3 sets and a ram after two; custom Ladders: 3 sets, Ram: 1;
  sandbox kit 1 / 2 likewise). Any attacking foot unit picks one up (tap
  it; `ORDER_PICKUP`), carries it slowly (no running, no attacking, 60 %
  melee), puts it down (Drop button, X; `ORDER_DROP`; routing leaves it);
  ladders are planted on the stretch the carriers are sent to (for the
  battle) and any infantry / missile unit ordered onto that stretch then
  climbs them; the ram's carriers batter a gate (outer, or the citadel's
  from the town) and put it down when it breaks; towers can wreck the ram
  (2,500 hp). The RAM unit type and the per-unit ladders flag are gone;
  co-op: no commander for equipment (whoever's unit carries it), only the
  towers' trailing home entry. UI: pieces drawn on the ground / carried /
  planted, previews "PICK UP LADDERS / THE RAM", "PLANT LADDERS HERE",
  "RAM THE GATE", cards "carrying ladders / ram", refusals, unit book.
  AI (every level): `_assign_equip` gives the ram to the least street-worthy
  foot (pikes first) and ladder sets to the heaviest infantry (S_LADDER_UNITS),
  `S_LADDER_FOLLOW` more infantry climb each planted set, ladder spots are
  scored by the walk too, `S_LADDER_AFTER` 300 (was 1200: carrying is slow).
- Bug B fixed (the unit marched along the wall to the foot and shuffled: its
  anchor never "arrived", its men could not form between it and the wall,
  it regrouped; a foot by a tower got no clear line to a path node): the
  climb starts within 8 m of the foot, units march to an approach point out
  from it. `tests/ladder_probe.gd`: 108 maps (5 plans x 4 sites x coast x
  walls 1-3), 2,432 points the rule allows, 2,432 climbed, 0 failed; 250
  refused (225 tower / gate / sea, 21 citadel, 4 no ground out there).
- Bug C fixed: walls-2/3 gates do not yield to swords (order rule, sim and
  AI); men drop a target they cannot reach within two ticks (was eight;
  1,758 man-ticks "fighting across a wall" in the reproduction -> ~0); the
  AI facing a shut citadel gate brings the ram, hacks only a walls-0/1 gate,
  else waits 50 m out (`S_CIT_WAIT`). Determinism `--only=equipment`
  (scripted pick-up / drop / plant / climb / ram with snapshot mid-carry;
  the shut inner gate), lockstep `--only=siege` (late joiner mid-carry, a
  set dropped by one peer picked up by the other).
- Measured (`--only=fair-sieges`, both Average, 10 seeds, ladders + ram
  row now 3 sets and a ram; attacker wins, mean / max min; da9ff24 ->
  now): ring walls 1 100 % (7.2 / 8.9) -> 100 % (7.2 / 8.0), walls 2 60 %
  -> 50 % (8.8 / 10.7), walls 3 20 % -> 20 %, 10 % draws (10.1 / 15.0);
  polis walls 1 90 % -> 80 %, 20 % draws (11.0 / 15.0), walls 2 70 % ->
  50 % (11.0 / 13.9), walls 3 10 % -> 20 %, 10 % draws (11.9 / 15.0).
  Artillery only: ring 100 / 20 / 40 % (was 100 / 60 / 10), polis 100 /
  40 / 0 % (was 100 / 30 / 0). Walls 3 at 30 min, ladders + ram /
  artillery: ring 20 / 40 %, polis 30 / 10 %. Gates at walls 2-3 now fall
  mostly to the ram (walls 3: 10 of 10). No tuning was done (scope).
  Field battles hash exactly as before (golden digests), so `--fair` is
  unchanged. Tick cost (same session, alternating, worst of two runs):
  bench_4000_city mean 3.35-3.44 -> 3.26-3.27 ms, p95 5.5 -> 5.8-6.0, worst
  7.4 -> 8.3-9.3; polis 3.19-3.28 -> 3.05-3.07, p95 5.6-5.8 -> 6.6-6.7,
  worst 7.0-9.3 -> 10.1-12.1; castrum 3.48-3.56 -> 2.85-2.90, p95 6.7-6.8
  -> 6.0-6.2, worst 8.5-8.8 -> 8.7-9.5 (different battles: no hacking at
  iron gates, the ram; the two-tick reach recheck alone costs ~0.05 ms).
- **Next (decided): part 2c, the walls-1 defender layout (former D: hold the
  attacked gate's inner mouth early, quiet gates' guards to the breach,
  plaza reserve) and the fair-sieges calibration**; then artillery engines
  as pick-up-able equipment with crews as men (decided with the user).

**Cities must be worth defending, part 2a: units do not pass through each
other (built 2026-10-07).** As built in DESIGN.md "Unit blocking and street
fights", AI.md section 14. In short: every ready ground unit's footprint
(its formation rectangle, clipped to its men) is marked in 4 m cells per
side, every other tick, per unit; an anchor never steps into an enemy's
footprint (it steers 30-60 degrees round it where there is room, else stops
and its men fight, a move included), passes through friends at half speed,
and an attacking unit waits behind friends already fighting (or waiting)
near its target: a 10 m street holds one unit a side, the rest queue. Men's
places a cell deep in an enemy are moved back; no soldier-level separation
was needed. The street squeeze (frontage clamped to the corridor) already
existed. Deployment placements inside another unit are refused ("Another
unit stands there"). Skilled defenders hold the inside of a breached gate
(posts either side of it) and bring the idle gate guards to the breach
(knobs `S_BREACH_HOLD`, `S_GUARD_JOIN`, off at Easy / Average: at Average
they did not move walls 1 and cost the defenders above it).
- Measured (`--only=fair-sieges`, both Average, 10 seeds; attacker wins,
  draws, mean / max minutes; before -> after):

  | City | Ladders + ram | Artillery only |
  |---|---|---|
  | ring, walls 1 | 100 % (6.4 / 6.9) -> 100 % (7.2 / 8.9) | 100 % (6.3 / 7.4) -> 100 % (7.1 / 8.1) |
  | ring, walls 2 | 60 % (8.6 / 11.2) -> 60 % (8.6 / 9.6) | 10 % (8.7 / 10.1) -> 60 % (10.4 / 11.9) |
  | ring, walls 3 | 50 % (9.2 / 10.3) -> 20 % (9.5 / 10.7) | 0 % (10.0 / 12.8) -> 10 %, 10 % draws (9.7 / 15.0) |
  | polis, walls 1 | 100 % (8.2 / 10.6) -> 90 %, 10 % draws (10.5 / 15.0) | 100 % (8.7 / 12.6) -> 100 % (9.1 / 11.0) |
  | polis, walls 2 | 50 %, 10 % draws (11.2 / 15.0) -> 70 %, 10 % draws (12.5 / 15.0) | 10 % (9.1 / 14.3) -> 30 %, 30 % draws (10.8 / 15.0) |
  | polis, walls 3 | 10 %, 20 % draws (10.9 / 15.0) -> 10 %, 40 % draws (12.7 / 15.0) | 0 %, 10 % draws (9.2 / 15.0) -> 0 %, 40 % draws (12.0 / 15.0) |

  Walls 3 with a 30 minute limit (before -> after): ring 50 / 0 % -> 20 /
  20 %, polis 10 % (20 % draws) / 0 % (10 %) -> 30 % (20 %) / 30 % (0 %).
  **Walls 1 still misses its 45 % target (100 %)**: blocking works (the
  attackers queue through the gateway and fight a unit at a time) but the
  defenders lose the exchange about 2.4 : 1 anyway: a third of their
  strength (the guards of the three gates not attacked, about 300 men)
  never fights, their reserves march down the main street into the
  attackers spread out inside the gate (the narrow end is theirs, not the
  attackers'), and the plaza capture then breaks everyone. That is AI
  disposition, not movement rules (the Skilled breach hold / guard join did
  not fix it at Average either); next step for the main session.
- Field (`--fair=50`, 100 battles each): Average vs Average 50 / 50, no
  draws, 5.14 -> 5.40 min mean (+5 %), max 8.2 -> 8.0; Average vs Easy 74
  % (1 draw) -> 79 %; Skilled vs Average 77 -> 76 %. bench_4000 (one seed)
  now meets 96 s later (the lines pass through their own missile screen and
  second line at half speed) and lasts 9.3 instead of 5.7 min.
- Tick cost (desktop, same session, before -> after; different battles, so
  the whole-run figures move with what happens): the unit phase +0.18 ms
  (bench_4000 0.26 -> 0.43, bench_4000_city 0.76 -> 0.95: the footprints
  ~0.08 ms a tick averaged, the anchor probes the rest); bench_4000 mean
  2.91 -> 2.35 ms, p95 4.8 -> 5.0, worst 6.5-6.8 -> 6.5-7.1; city 3.31 ->
  3.42, p95 6.0 -> 5.6, worst 8.6-8.7 -> 7.5-8.2; polis 3.23 -> 3.25, worst
  8.4-9.6 -> 7.1; castrum 3.02 -> 3.55, p95 5.5 -> 6.8, worst 8.0-9.0 ->
  9.0-9.6.
- Tests: determinism `--only=blocking` (street fight, pass-through, gate
  jam, gate rush in the gateway and 14 m inside, foot and riders) and the
  re-recorded skirmish / bench_2000 golden digests; lockstep street fight
  with a late joiner; campaign_sim hashes unchanged.

**Cities must be worth defending, part 1: attrition at the wall (built
2026-10-07).** As built in DESIGN.md section 4 "Siege equipment and wall
towers", AI.md section 13, CAMPAIGN.md "Siege equipment". No stat bonus
for standing inside walls. In short:
- Walls-2/3 cities mount **tower engines** (UT `tower_bolt` / `tower_stone`):
  bolt throwers on the towers by the gates and at intervals (6 / 8), at
  walls 3 two stone throwers on the biggest towers; immobile, fixed shots
  (+50 % with a Workshop), crews that can be shot, towers batteries can
  batter down (counter-battery); a card each for the defending player
  (fire / hold, target by tap); the AI defender focuses the ram, batteries,
  men at the gate and on ladders; the AI attacker batters the towers by the
  gate first.
- **Hard gates**: walls-2/3 gates 130 % hit points and 1 % of the old sword
  rate (walls 0-1 unchanged). **Ladders**: attacking foot carrying them tap
  a stretch of wall from outside, march to its foot and climb, a man per
  ladder every 2 / 3 / 4 s (walls 1 / 2 / 3), arriving on the walkway one
  at a time and fighting there, exposed to the walls and towers; once up,
  down into the town to unbar a gate from inside. **Ram**: a slow roofed
  engine unit; at a gate's face it breaks a walls-3 gate in about a
  minute and a half. Battlement cover 25 / 45 / 70 % (was 25 / 35 / 65),
  wall archers reach 15 % further at men below at walls 2-3 (walls 1
  unchanged). AI at every skill uses and answers all of it (knobs
  `S_LADDER_*`, `S_TOWER_FOCUS`, `S_COUNTER_BAT`, `S_ESC_REPLY`,
  `S_RAM_WAIT`).
- **Campaign**: an assault after a siege of a turn brings ladders, of two
  a ram (derived from the siege entry's turn; no state change, VERSION 6);
  siege panel line "Siege equipment: ..."; auto-resolve formula untouched
  (campaign_sim 6 x 60 hashes equal HEAD's). **Battle time limit**:
  scenario `time_limit` (absent = 900 s, hashed only when not), campaign
  `settings.time_limit` ("Battle time: 15 / 20 / 30 / 45 min"), custom
  battles (Battle time; Ladders / Ram toggles), sandbox settlement row
  (siege kit, minutes); HUD clock "m:ss / limit".
- Measured (`tests/matchups.gd -- --only=fair-sieges`, equal strength,
  both AI Average, 10 seeds; attacker wins, mean / max minutes):

  | City | Ladders + ram (siege of 2 turns) | Artillery only (on arrival) |
  |---|---|---|
  | ring, walls 1 | 100 % (6.4 / 6.9) | 100 % (6.3 / 7.4) |
  | ring, walls 2 | 60 % (8.6 / 11.2) | 10 % (8.7 / 10.1) |
  | ring, walls 3 | 50 % (9.2 / 10.3) | 0 % (10.0 / 12.8) |
  | polis, walls 1 | 100 % (8.2 / 10.6) | 100 % (8.7 / 12.6) |
  | polis, walls 2 | 50 %, 10 % draws (11.2 / 15.0) | 10 % (9.1 / 14.3) |
  | polis, walls 3 | 10 %, 20 % draws (10.9 / 15.0) | 0 %, 10 % draws (9.2 / 15.0) |

  Walls 3: about 30 % with ladders and a ram (target 25 %), none on
  arrival; walls 2: 55 % / 10 %. **Walls 1 misses its target (100 %
  against 45 %)**: walls 1 has no towers and its gate falls to artillery
  in about two minutes, so the battle is decided in the street fight and
  the plaza capture; the wall levers moved it 10 points at most (cover 50
  / 60 %, range +20 / 30 % tried) and were left at the old values (walls-1
  battles hash as before). That is part 2's job (units that do not pass
  through each other, the slow street fight). The polis's walls-3 draws
  are stand-offs at the acropolis: a 30 minute limit leaves the same 20 %
  undecided. Ladder parties go up (80-140 men a battle) but rarely live to
  unbar a gate (towers and wall archers shoot the queues); the ram
  breaks most walls-3 gates.
- The 1.5-2:1 sets changed as expected (attackers have artillery but no
  ladders or ram there): `--only=plans` walls 3 attacker wins (before ->
  after) ring plain 100 -> 20 %, ring hill 80 -> 30 %, castrum 90 -> 70 %,
  polis coastal 60 -> 10 %, polis plain 90 -> 10 %, punic 60 -> 0 %,
  oppidum spur 80 -> 20 %, oppidum plain 60 -> 30 %; walls 2 ring 100 ->
  80 / 100 %, castrum 100 -> 100 %, polis 100 -> 40 / 40 %, punic 90 -> 10
  %, oppidum 90 -> 50 / 70 %; walls 1 unchanged. `--only=sieges`:
  garrison-only walls 2 / 3 with artillery 100 -> 90 / 50 % (draws 10 /
  50 %), without artillery 100 -> 0 % (all draws: no way in without a ram
  or engines, by design); city walls 2 90 -> 60 %, hill city walls 3 100
  -> 20 %. Battles run longer (walls 3 9-14 min mean, several to the 15
  minute limit).
- Tick cost (`benchmark.gd`, same session, base / new): bench_4000_city
  mean 2.84 / 3.15 ms, p95 5.54 / 5.72, max 7.18-8.11 / 7.01-7.08 (the
  6.5 ms target is missed by the base too on this machine today);
  bench_4000_polis max 6.64 / 7.52, castrum (walls 3) 5.99 / 7.64;
  bench_4000 unchanged (6.14 / 6.22).
- Determinism: every golden digest and the final hash of every field
  battle and walls-0/1 city (`siege_village`, `gate_ops`, `cit_ops`,
  `siege_oppidum`) equal HEAD's; walls-2/3 cities changed (towers, gates,
  cover). New runs `siege_eq_ring3` (walls 3, ladders, ram, towers, 20 min
  limit) and `siege_eq_polis2~sa` (ladders, a Workshop, Skilled attacker),
  snapshot / restore; lockstep: snapshot mid-climb, two peers plus a late
  joiner on the walls-3 siege.
- **Open / next:** walls 1 (part 2); escalade rarely unbars a gate in AI
  play (the parties die at the wall; a Skilled timing or more ladders may
  help); the polis's acropolis stand-offs; in live co-op the towers belong
  to nobody (they fire at will); play it on phones (tower cards, ladder
  taps, the ram). Screenshot `docs/screenshots/siege_ladders_ram_phone.png`.

**Deployment phase and custom battles (built 2026-10-06).** As built in
DESIGN.md section 4 "Deployment phase" and section 5 "Custom battles and
head-to-head"; server: SERVER.md section 18. In short:
- Battles may open with a Total War deployment phase (scenario
  `deploy_time`): the clock stands at 0, nothing moves or shoots, players
  place their units inside their zone (`ORDER_PLACE`: the ordinary tap /
  line / group gestures, clamped into the zone on the field, inside the
  walls or onto a walkway in a defended town) and press Start battle /
  Ready (`ORDER_READY`); it ends when every player is ready or the
  countdown runs out. AI sides show their line from the start (field
  maps). Zones drawn; a bar with the countdown and who is ready. Campaign:
  new-campaign "Deployment time: none / 1 / 2 min" (default 1 min;
  `settings.deploy_time`, no VERSION bump; older and online campaigns
  made before have none; auto-resolve ignores it); live co-op goes from
  the lobby into the deployment.
- Custom battles (start screen and sandbox page): field or settlement
  map, two sides of 1-3 armies of up to 12 units from the whole roster with
  campaign prices and optional equal funds, controllers Player 1 / Player
  2 / AI (skill and personality per side), deployment time, templates (the
  sandbox's battles and test matchups). Solo at once; online by a custom
  battle room (code, lobby where Player 2 may edit Player 2's armies, both
  Ready, the host starts): co-op on one side or head-to-head.
- Head-to-head in the lockstep layer: players have sides; gifts only to
  the same side; a dropped / leaving / absent player's units go to a
  player of their side, else the battle AI takes the side (handed back on
  return); votes unchanged.
- Server: `POST /api/custom`, `POST /api/custom/join`, WebSocket
  `/api/custom/{code}/ws` (lobby `setup` / `lobby` messages, then the live
  relay); memory only; `api: 3`.
- Tests: determinism_test (deployment: field and town, repeat and
  snapshot / restore mid-deployment and mid-battle, clamping, refusals,
  walls, AI line, countdown; golden digests unchanged), lockstep_test
  (deploy co-op with an early ready and a join during the deployment;
  head-to-head with the countdown, refused enemy placements and gifts, a
  drop with AI takeover and return; a drop during the deployment),
  custom_battle_test (every template and hand-made setups build
  identically and run), live_e2e (the three campaign battles now with a
  10 s deployment, plus a custom head-to-head and a custom co-op battle
  over the real server), go test (custom rooms), check_scripts,
  input_test, campaign_input_test.
- Decisions to know: the battle AI commands whole sides, so an "AI" army
  on a side with a player's army is commanded by that player, and AI
  skill / personality is per side; the side-2 player sees the map
  unrotated (their army at the top); the server never checks the setup
  (the clients' scenario hashes must agree before the start).
- **Open / next:** play it on the phones (placing by touch, the zone and
  bar on a small screen, the lobby); per-army AI on a mixed side; turning
  the view for the top side; mirrored-fairness (53-55 % bottom bias)
  matters more head-to-head; a lobby chat / rematch button.

**Continuous campaign overworld (built 2026-10-06, uncommitted).** Design
agreed with the user; rules, numbers, grid format, orders, state, AI and
pacing as built in CAMPAIGN.md "The continuous overworld (version 6)". In
short:
- A static nav grid (`campaign/data/grid_data.gd`, 138 x 70 cells of 20 map
  px, generated from the map by `tools/campaign_grid.gd`): armies stand on
  cells and march A* paths (foot 200 points, cavalry 300, artillery 150; a
  cell 10-20 by terrain, diagonals 14/10; Roma -> Tarentum two turns on
  foot, one for cavalry), continuing on later turns; sea lanes port to
  port.
- Zones of control (2 cells, 3 fortified): paths keep out of enemy zones
  unless attacking; a step next to an enemy army is a field battle on its
  cell (rounds, armies by id: the lower id attacks head-on); one battle
  per region. Moving onto a hostile city lays siege from its ring (or
  storms it on arrival); onto your own: inside the walls; inside a
  besieged city onto a besieger: a sally; on your own besieged city: a
  relief. Besiegers lose 5 % a turn once the city starves. Support within
  4 cells (6 fortified), deploying from its bearing. Stances: default,
  forced march, fortify, raiding (takes half the region's income).
- AI with static distance fields per settlement: sieges, hunting enemy
  field armies, attacks with gathering a march short of the target,
  raids, screens, forced marches, fortifying; ~16-19 ms a full AI turn
  (first turn ~130 ms for the fields). Pacing (6 seeds x 60 turns):
  largest at turn 30 median 8 (before 10), no faction reaches the victory
  size by 60, field battles 6-27 a campaign (before 1-7); deterministic.
- State format 6; 5 -> 6 migration (local saves); unmigrated online
  campaigns of formats 1-5 play exactly as before (6 AI campaigns x 60
  turns from format 5 give HEAD's hashes; format 4 HEAD's table). No server
  change; the server binary needs no restart.
- The battle sim gained an optional per-unit `morale_pct` scenario key (an
  army caught on a forced march); existing scenarios unchanged
  (determinism_test PASS).
- View (phone first): armies at their cells, the reach area, enemy zones,
  yellow support and red attack lines, tap-then-tap planning (enemy army =
  attack, city = siege or inside, land = march; same spot = cancel) with
  Undo, drag from an army to plan (elsewhere pans), paths solid / dashed
  with the end-of-turn ring and an intent badge, one stance selector, the
  siege panel's Assault / Continue siege / Withdraw, a skippable replay of
  the turn's steps. The move-mode toast, the stance toggle, Maintain and
  Sally are gone for format 6. Screenshots
  `docs/screenshots/overworld_phone_*.png`.
- Tests: campaign_test (format 6 suite: grid, paths, zones, turns, contact,
  sieges, sally / relief, support, stances, raiding, migration, step log,
  determinism; the older suites on format 5 states), campaign_sim
  (`--format=5`, `--twice`), campaign_solo, campaign_battles,
  campaign_input_test (windowed; v6 and v5 parts), check_scripts,
  determinism_test, online_e2e (scratch port 8077), go test.
  `tests/touch_scroll_test.gd` fails two recruit-list scroll checks, the
  same on HEAD (not from this change).
- **Merging, exchanging and gifting (fixed after the playtest "lots of 1
  and 2 stacks at the same location", 2026-10-06, uncommitted):** tap your
  other army to merge (marches to it and follows it over the turns), the
  `exchange` order and panel (also gifts to the allied player), Merge into /
  Exchange units at the top of the army card, recruits and idle armies in a
  city gather into one army at the end of the turn (CAMPAIGN.md "Merging,
  exchanging, gifts"). No version bump; AI pacing unchanged within noise.
  Open: try it on the phones.
- **AI and the mustering rule; merge glyphs (2026-10-06, uncommitted):** the
  campaign AI (format 6) plans moves before recruits and never recruits
  into an army it marches (holds a small one or raises a new army):
  refused "mustering" AI moves 37-57 per seed -> 0 (CAMPAIGN.md
  "Recruiting into armies"); the merge plus only shows where a tap would
  merge (`merge_why`: the real merge / join / path checks, cached per
  selection and plan).
- **Reordering units by drag and drop (2026-10-06, commit 0babb12):** battle
  card strip: drag a card (touch: long press until it lifts, then drag) to
  a new place; a view-only display order per player and battle (nothing in
  the sim or lockstep), All / Inf / Missile / Cav select in it. Campaign
  army card: the same gesture on unit rows plans an `arrange` order
  (step 2, any format, one per army and turn, Undo per drag); it sets the
  order units take the field in. Shared helper `game/drag_reorder.gd`;
  `TouchScroll.hold` keeps a lifted row from scrolling. On a touch screen
  the long press on a card or army row now opens the unit page on release
  (after the lift) instead of while held. No state version bump (a new
  order type). Controls page rows `card_reorder`, `map_army_reorder`.
  Screenshot `docs/screenshots/reorder_phone.png`. Open: try it on the
  phones (the 0.35 s lift, the long press -> book on release).
- **Gate doorway taps (phone playtest fix, 2026-10-07, view only):** gate
  doorway taps win over unit markers and toggle for the defender whatever
  is selected (`game/battle.gd` `_gate_doorway`; tests in `input_test.gd`).
- **Open / next:** play it on the phones (tap-tap planning, drags, the
  replay; whether a tap inside an enemy zone should become an attack
  instead of a refusal); the version 5 testing aids `--camp-raid`,
  `--camp-intercept`, `--camp-attack` are not adapted to format 6;
  fortify has no real-battle effect yet (odds and formula only);
  forced march: morale only, no smaller deployment; siege equipment over
  turns; roads / rivers / fords as grid overrides; Epirus still falls in
  most AI-only seeds and Rome in 2 of 6.

**Wall orders (phone playtest fixes, built 2026-10-06, uncommitted).**
Report: "loading on or off a wall is difficult. It doesn't display where
the units may go, and they don't seem to fit; once I pulled the javelins
down I couldn't get them back on the wall." Found: (1) only a tap within
3 m of a walkway's centre line counted as "up the wall" (a 6 m band of an
8-16 m wall plus towers); a tap on the parapet, inner face or a tower was a
ground move to a blocked spot; (2) a unit standing near the wall (inside
the 12 m reform distance, e.g. just pulled down) ordered up only reformed
in place and never climbed; (3) wall units stood in up to 3 ranks of 2 m
(off the 4 m walkway: 25-60 % of the men of every garrison unit stood in
wall cells) and the whole line turned with its target; on stretches of
12-20 m they piled 5-6 deep. Fixed (rules in `sim/battle_sim.gd`, DESIGN.md
"Walls" / "Stairs"):
- any tap on a wall's body, walkway, stair, tower or gate tower snaps to
  the nearest walkway point of its stretch (`wall_snap`, in the order rule:
  preview and sim agree; lockstep peers snap the same raw input); the way
  up is always a march to the stair;
- the wall line: two ranks (at most 1.2 m apart) along the walkway, centred
  on the tap, clamped to the stretch, spilling through a tower onto the
  joined stretch (towers passable to wall units only), surplus at the
  ends; garrison units start in it; men never jittered off the walkway;
- coming down: in the unit's normal block (`ground_files`); men on a stair
  move follow the stair's trail (junction, walkway, stair, foot);
- view: the predicted wall line, stretch(es), stair (ringed) and route
  (dashed) going up and coming down, and the ground footprint below;
  stretch under the mouse lit; refusals ("Cavalry cannot man walls", "No
  ladders yet...", "No way to a stair..."); buttons "Man the wall" (M:
  nearest stretch within 60 m, the one nearest the enemy) and "Come down"
  (Shift+M: the nearer stair's foot); Controls page and unit book updated.
  Screenshots `docs/screenshots/walls_order_up_phone.png`, `..._down_phone.png`.
- Drag clamp: a formation line is at most one rank long (men x file
  spacing, a group: the sum plus gaps); the line stops following the finger
  there (solid end caps, "ONE RANK"); the order rule already capped files
  at the men alive.
- Reachability (same playtest, attacking a city: "the formation goes past
  the walls ... sliding along the wall in clumps"): pieces of open ground
  with the gates as connectors; moves to unreachable ground go to the
  nearest own ground (a tap on a house / wall) or to the gate on the unit's
  side and hold there; attacks on a unit inside: melee to the gate (attacking
  foot hack it, go in once it breaks), missile troops only as far as their
  ground goes and shoot from range; places kept to the anchor's ground.
  Captions "No way in: moving to the gate", "Moving into range". DESIGN.md
  "Settlements (rules)" / Reachability. Benchmarks (run side by side with
  HEAD, so noisy): city 2.71 -> 2.87 ms mean (p95 5.1 -> 5.6), polis 2.87
  -> 3.05, castrum 2.76 -> 2.98; setup +20-30 ms.
- Tests: determinism_test "wall orders" (down and back up by walkway,
  parapet, tower and Man the wall; spill; repeat + snapshot), "drag
  clamp" and "reachability" (tap into a shut town holds at the gate with no
  man strung out; attack on a unit inside: to the gate, hack, in once
  broken; archers shoot from outside; no place off its ground); flat golden
  digests unchanged; every settlement hash changed (the open village too,
  from the reachability rules); lockstep (both sides, both maps) and
  input_test pass.

**Free campaign movement (built 2026-10-06, uncommitted).** Design agreed
with the user; rules, orders, state, AI, pacing as built in CAMPAIGN.md
"Free movement (version 5)". In short:
- Movement points by the slowest arm (foot 20, cavalry only 30, with
  artillery 15); entering a region costs 10 open / 15 hill or ridge, +5 in
  heavy woods; a sea lane needs full points and takes them all. A move is
  a destination: cheapest path (Dijkstra, ties by region index), walked in
  rounds (every army's k-th hop, by id), continued on later turns
  (`persist`, `dest` on the army; `cancel_move`).
- Enemy field armies stop armies entering their region: a field battle
  (kind "field", no garrison). Entering enemy land raids it (owner gets
  half the income); `siege` / `assault` are orders from inside, a move's
  mode is the "on arrival" shortcut (field armies there are fought first).
  Stance: in the field / inside the walls (`stance` order).
- Support by range over land within a turn's points; reinforcements deploy
  on the map edge they come from in field battles (explicit positions; no
  sim change).
- AI: multi-hop targets, concentrate before attacking, raids, screens,
  stances, no dithering (idle 3 turns). Pacing close to format 4 (largest
  at turn 30 median 10 vs 11 over 10 seeds, eliminations median 4); AI turn
  ~13 ms mean, ~19 ms worst.
- State format 5; 4 -> 5 migration; unmigrated online campaigns of formats
  1-4 play exactly as before (6 AI campaigns x 60 turns from format 4 give
  HEAD's hashes). No server change; the server binary needs no restart.
- Tests: campaign_test (paths, rounds, interception, raiding, siege start
  in the field, support by range with edges, retreat, persistence, 4 -> 5
  migration), campaign_sim (`--format=4`, pacing table, `--twice`),
  campaign_solo, campaign_input_test, online_e2e, go test. Screenshots
  `docs/screenshots/move_phone_*.png`.
- **Open / next:** play on the phones (is raiding by default right; toast
  and army card on a small screen); reinforcements arriving mid-battle;
  edge arrival in settlement battles; Epirus now falls in every AI-only
  seed; interceptions are few in AI-only play (1-7 a campaign).

**Sieges and battle odds (built 2026-10-06, uncommitted).** Design agreed
with the user; rules, orders, state and AI as built in CAMPAIGN.md
"Sieges and battle odds". In short:
- A move into a hostile settlement lays siege by default (no battle); the
  move toast and the army panel make Assault (today's battle at once) one
  tap away. Besiegers stay until ordered away, cannot merge / split /
  disband; armies of their side that move in later join. Each turn the
  besieger may order `assault` (settlement battle, every besieger
  attacks), the defender `sally` (field battle on the region's terrain,
  garrison and armies inside riding out); an army of the owner's side
  moving in is a relief (field battle, the garrison and the armies inside
  on its side). Lost sally / relief by the besiegers lifts the siege and
  sends them home (or to the nearest friendly region); a beaten relief
  falls back or is destroyed.
- Besieged: no income, no recruits, construction and growth paused, no
  garrison recovery; supplies 2 / 3 / 4 turns (village / town / city, +1
  with farms 2: granaries), then the garrison loses 25 points and the
  armies inside 10% of their men a turn; no garrison and no army inside =
  surrender to the besiegers ("surrendered" event).
- `CBattle.odds()`: the formula's prediction (strengths, chance, expected
  losses, band) for any two groups of armies; shown as a two-colour
  balance-of-power bar in the siege panel (assault / sally / relief), the
  pending-battle cards and the region panel of an enemy settlement with
  armies ordered into it. Map: a ring of tents in the besieger's colour;
  siege moves drawn orange, assaults red.
- AI: assault at its attack ratio, else lay siege when another army can
  join within two turns; assault a starving city with a relief near; lift
  before a stronger relief; maintain at most supplies + 3 turns; sally at
  the ratio; relieve at 60%.
- State format 4 (top-level `sieges`); 3 -> 4 migration adds an empty list.
  Online campaigns of formats 1-3 stay as they are and play without sieges,
  byte-identical to the previous build (checked: 6 AI campaigns x 60 turns
  give the same final hashes as HEAD + the join fix). No server change; the
  live server binary needs no restart for this.
- Tests: campaign_test (sieges: start, join, lift, starvation, surrender,
  economy, assault / sally / relief battles and outcomes, odds against the
  formula, co-op assault, format 4 migration), campaign_input_test (Assault
  now toast, Assault / Maintain, Sally), campaign_sim `--twice` (determinism)
  and `--no-sieges`, campaign_solo (a siege policy), online_e2e, go test.
  Screenshots `docs/screenshots/siege_phone_*.png`.
- **Open / next:** play it on the phones (is the default siege right for
  players who expect a battle; the toast on a small screen); AI sallies are
  rare (0 in 6 AI campaigns: the garrison fights without walls) and AI
  sieges end by assault or lift, not starvation (patience cap); tune after
  play. Pending battles resolve after the end of turn (as before), so a
  siege with a battle pending skips that turn's supplies and starvation.

**Settlement variety (built 2026-10-05, uncommitted).** After the
playtest of the city maps (liked; every walled town looked the same round
hill fort; wall archers could not leave a wall). Design as built: DESIGN.md
section 4 "Settlement plans, sites and owners"; save format: CAMPAIGN.md
"Version 3". In short:
- Wall plan by founding culture (static `culture` per region): castrum
  (latin), polis with acropolis (greek), punic with citadel, oppidum with
  a funnel gate (celtic); the original ring stays for the sandbox tests.
  Sites by terrain: plain (ditch at walls 3), hill (a rise, no plateau),
  spur (posterns); ports have the sea behind (sea wall, scenery sea gate
  and mole, defenders retreat along the shore). Enclosed fields in
  villages and small oppida.
- Bug fixed: towers are stairs. Wall units can be ordered down (and
  defenders up), routers leave the wall by a stair; the AI pulls wall
  archers off a lost stretch.
- Citadels: the capture zone is inside; attackers must break two gates;
  the defenders fall back into it (as many as fit) and shut it.
- Owner dressing (view): banners, the owner's shrine, roofs by who built
  what (state format 3 with builder data; online formats 1-3 readable).
- Path tables at most 2 a tick; several street-fighting fixes (squeeze
  centring, regroup, reachable attack goals, routers not walking the
  trail, stair stragglers, rate-based stall).
- Verified: determinism PASS (golden digests and every flat / hill / woods
  hash unchanged; new runs per plan, a scripted citadel / stairs set
  piece, sea / ditch / style checks; settlement runs changed: stairs,
  street fixes); lockstep PASS (coastal polis, players attacking and
  defending with stair moves); campaign_test / solo / input tests,
  input_test, check_scripts, go test, online_e2e, live_e2e PASS.
- Balance pass (2026-10-06, uncommitted): diagnosed freezes and grinds
  fixed (melee over walls, cut-off units, everyone on one target, hunting
  instead of taking the plaza, a citadel cut off the street graph) plus
  "the town is lost" morale, weaker citadel gates, a shallower oppidum
  funnel without ditch, quicker withdrawal when beaten. Draws now at most
  1 in 8, battles 5-10 min; see DESIGN.md "Balance pass".
- Round 3: breach searches and paths made cheaper (p95 4.7-5.2 ms, worst
  6.4-6.7 ms on the city benches); battlement cover by wall level; the
  stall clock waits out the approach; check_scripts no longer writes an
  override.cfg into the shared checkout.
- **Open / next:** walls 3 was still easy for ring / castrum / polis (87-100 %
  attacker wins); since 2026-10-07 the tower engines, hard gates and
  stronger battlements make walls 2-3 cost the attacker (see "Cities must
  be worth defending, part 1" above; walls 1 open); breach melee
  still 5.4-5.9 ms p95 and 7.5-8.5 ms worst at 4,000 soldiers (volume of
  men in contact: per-man contact gating is the next step); play it on
  phones (look of the sea, shrines, banners; the stair orders by touch).

**Battle maps with character (built 2026-10-05, committed in `3522fd2`).** CAMPAIGN.md
"Later" item 1. Design as built: DESIGN.md section 4 "Battle maps: woods
and settlements" (rules, numbers, AI, view, measurements). In short:
- Woods on any map (region coverage 0-100, density 0-3 per 4 m cell): slow
  units (artillery and cavalry most), disorder formed units (pike walls
  drop), blunt charges, stop arrows and stones, block flat shots; riders
  fight badly in them. The field AI keeps cavalry, pikes and batteries out
  and shelters archers from cavalry in them.
- Every settlement battle on the settlement's own map from a fixed
  `city_seed` (+ level, walls, buildings, region ground): streets and
  houses, plaza, walls with walkway and towers, 2-4 gates with hp,
  orchards and fields outside; paths through the streets, squeeze in
  narrow streets, missile troops on the walls, gates shut / opened /
  broken (artillery or hacking foot), plaza capture (60 s) breaks the
  defenders. Siege AI for both sides (`sim/siege_ai.gd`). The campaign's
  ridge stand-in for walls is gone.
- Ground palettes by region (arid / dry / green / rocky) on the battle map
  and the campaign map; stronger height shading; trees as one MultiMesh
  fading over soldiers; the city drawn in one static layer; gate taps;
  sandbox Ground and Settlement battle choices; unit book pages; the region
  panel's "View battle map".
- Campaign state format 2 (`city_seed`), local saves migrated on load;
  online campaigns stay format 1 on the server and play identically (no
  server change; see CAMPAIGN.md "State format").
- Verified: determinism test PASS (golden digests and every earlier run's
  hash unchanged; woods / village / city / hill city / scripted gate runs
  identical on repeat and across snapshot / restore); lockstep test PASS
  (with a walled town, players attacking and defending); live_e2e PASS and
  online_e2e PASS on scratch servers; campaign tests PASS (v1 save
  migrates); matchups `--only=maps` (no draws, settlement battles decided
  in 4-12 min); benchmarks bench_4000 2.65 / 6.0 ms, hills 3.0 / 6.2,
  bench_4000_city 2.69 / 7.8 (max over budget: first path tables after a
  gate falls).
- **Not yet done / next:** play it on the phones (look of the ground,
  trees and city on real screens; WebGL2 cost of the tree quads and the
  second ground texture; ground texture build 0.1 s on the desktop, maybe
  0.3-0.4 s on a phone); city benchmark spikes on phones; sallies; siege
  equipment.

**Milestone 5, live co-op battles (built 2026-10-05, uncommitted).** Why:
in the first online playtest one player started a battle and the other's
join button only returned them to the map. Now a battle with both armies is
fought live: the host opens a lobby (the ally is pinged), the ally taps
"Join battle", each commands their own army, as in Rome 2 co-op. Design as
built: DESIGN.md section 5 "Live battles: as built"; relay protocol:
SERVER.md section 17. In short:
- Deterministic lockstep over the server's WebSocket relay: only inputs
  travel, each for a frame a few frames ahead (delay from the round trip,
  2-12 frames of 100 ms; none while alone), the sim waits for a missing
  player's input. `sim/lockstep.gd` holds the frame, pause / speed and their
  votes, who takes part, and the command table, all hashed;
  `BattleSim.snapshot()` / `restore()` for joins, reconnects and desyncs.
  Golden digests unchanged.
- Gifts and gifts back, pause and speed by vote (chips under the controls:
  Accept / No), ally's unit cards framed in their colour and not orderable,
  a co-op strip (players, host, connection, round trip), waiting / catching
  up / resync indicators, lobby, Continue / Wait when the ally has been gone
  10 s (their units come to you, held for them; they get them back when they
  return), mid-battle join and rejoin by snapshot, host handover, result
  uploaded once by the host (any seat that took part may upload it).
- Server: rooms in memory (`rooms.go`) holding the battle's claim while in
  use, sequence-numbered stream with replay buffer, snapshot cache, roles,
  rate and size limits; battle list shows "Live now" with Join battle;
  `api: 2`. New table `battle_live` (created at start, nothing else changes
  in the database).
- Verified: `go test ./...` (rooms: entry and auth, ordering, reconnect and
  replay, drop / continue / ready, snapshots and cache, leave and host
  handover, lease renewal, upload by a seat that took part);
  `tests/lockstep_test.gd` (snapshot round trips on 6 scenarios up to 4,056
  soldiers; two peers through a simulated relay with different latencies
  and timing, every frame equal, with refused orders, gifts, votes, a drop,
  takeover and readmission, and a third peer joining mid-battle; solo
  through the lockstep layer = plain sim); `tests/live_e2e.py` (the Go
  server and two headless Godot clients fight three battles over real
  WebSockets: lobby join, mid-battle join, disconnect + takeover + return;
  hash equal on every frame on both, results uploaded once, both end on the
  server's state: PASS); `server/cmd/webcheck -live` (the web export in two
  headless Chromiums: lobby join, 600 frames hash-equal every frame,
  rejoin mid-battle from a snapshot: PASS); `tests/live_shots.py`
  (screenshots, and the real game as host uploading through its campaign
  screen). Screenshots `docs/screenshots/live_phone_*.png`.
- Numbers: snapshot 86-89 KB at 4,056 soldiers (36 KB at 2,000; 15-30 KB
  for small battles), ~10 ms to take and 2 ms to restore natively; on the
  local machine round trips 6-7 ms and no waits at delay 2; in headless
  Chromium 40-45 ms round trips (frame time included) and waits of up to
  ~170 ms when frames were run 4x faster than real time.
- **Not yet done / next:** restart the 8060 server with the new binary (the
  web build is already the new one); play it on the two phones; watch
  `coop_*` telemetry (round trips and waits on cellular, iOS Safari with
  the screen locked, backgrounded tabs); reinforcements arriving from the
  map edge; spectating without an army.

**Milestone 4, async backend and online co-op (built 2026-10-05,
committed in `fad7399`; 8060 runs the Go server behind Caddy, WebSocket
upgrade checked on the real domain).** Everything is in `docs/SERVER.md` (API, data model,
concurrency, notifications, deployment, security) and `docs/CAMPAIGN.md`
"Online play" (the screens). In short:
- Server: Go 1.27.1 (installed at user level in `~/.local/go`, checksum
  verified) + `modernc.org/sqlite`; static files with no-cache + ETag and
  precompressed wasm (39.5 MB -> 7.1 MB brotli); telemetry identical to
  `serve_web.py`; campaigns with every state version kept, join codes,
  per-device seat tokens (hashed), device codes, submissions with
  unsubmit, compare-and-swap uploads (one per version wins, an identical
  replay is "already"), turn deadline from the first submission with forced
  resolution, battle leases with heartbeats, Wait for ally / Take command /
  Ask to join, per-seat session blobs, long-poll change feed, WebSocket echo
  (milestone 5 relay goes there), history and rollback, determinism reports,
  Discord webhook notifications (queued, rate limited, deduplicated),
  invite key, rate limits, same-origin only, backups every 6 h.
- Client: Online co-op / Join / Continue-with-badges on the main menu, the
  share page, Submit turn and the waiting panel, the online battles list,
  the Online dialog (device code, Discord, timeout, history, rollback),
  Play online for a local campaign, offline cache, battle-result outbox,
  determinism check of the ally's results. Local play unchanged.
- Fixed on the way (affects every browser build): `main.gd` compared the
  iOS check's result `== true`, but this Godot build returns a JS boolean as
  an int, and int == bool is a runtime error that silently aborted the
  start screen's `_ready` before the URL shortcuts (`?scenario=` etc.). Also
  on the web `HTTPRequest` must not gunzip again what the browser already
  decompressed.
- Verified: `go test ./...` (API, races, timeouts, leases, rate limits,
  notifier); `python3 tests/online_e2e.py` (two headless Godot clients, 10
  turns, battles, a resolve race, a device switch, a forced turn, network
  failures, Discord messages: PASS); `server/cmd/webcheck` (two headless
  Chromium browsers on the web export: create, join, WebSocket echo,
  submit, resolve, long-poll pickup: PASS); the container image builds and
  runs (Podman). Screenshots `docs/screenshots/online_*.png`.
- **Not yet done / next:** (8060 is switched and an invite key is set.)
  Keep playing it on the Android phone and the iPhone (share link, typing a code, device code to the
  desktop, background tabs and long-poll on iOS Safari); move to the
  Proxmox host. No token
  revocation UI, no campaign deletion yet.

**Milestone 3, campaign layer (built 2026-10-05, uncommitted, not yet
playtested).** Everything is in `docs/CAMPAIGN.md` (as built: rules,
numbers, map and adjacency, tier table, state and order formats for
milestone 4). In short:
- `campaign/` pure deterministic rules: 36 regions, 45 land routes, 14 sea
  lanes, 8 factions + 12 independent regions, two turns a year from 280 BC,
  simultaneous orders then AI, economy with buildings / trade / upkeep /
  debt / corruption, settlement growth, 7 building chains, recruitment by
  building level and tier, replenishment, merge / split / disband, 12-unit
  armies, reinforcements, garrisons and walls, conquest, retreat,
  elimination, victory; campaign AI and diplomacy; state as one JSON blob
  with a hash.
- Unit tiers: 31 derived unit types (tiers 2-3 of the seven core lines plus
  faction elites: principes, triarii, phalangites, silver shields,
  companions, sacred band, hoplites, scutarii, Gallic nobles...), with
  gold-chevron tier marks; the nine base types are unchanged (golden
  digests unchanged).
- `game/campaign/`: map screen (drawn coastlines, territories, routes,
  armies, planned moves), region / army / realm / diplomacy / battles /
  summary / goals panels, hot seat with hand-over, save slots with autosave,
  export / import as text, new-campaign screen; battles fought in the
  battle view or auto-resolved by the battle sim AI vs AI.
- Main menu reorganised (Campaign / Battle sandbox / Unit book / Controls);
  Controls page from one bindings table; battle additions: Shift / Ctrl
  click multi-select (also on cards), symbol markers as hit targets first,
  None (deselect) button, keyboard shortcuts, mouse drag-box select,
  three-finger / Alt+drag (or G+drag) group move with rotation and ghost
  preview, field long-press / right-click for the unit book.
- Web: manifest + icons for install (no service worker, so never a stale
  build); iPhone Safari tab told to use Share > Add to Home Screen.
- Playtest fixes (2026-10-05, after the first phone playtest, which went
  well): every list scrolls by dragging anywhere in it, buttons included
  (`game/touch_scroll.gd`, used by all scroll areas; taps fire on release
  only if the finger did not scroll; fling; long press on unit rows opens
  the unit page; scroll bars thin on touch); neighbouring regions an army
  cannot enter are shown dark and crossed, and tapping one explains why with
  a Diplomacy shortcut; the region panel says whether its owner is at war or
  peace with you. Test: `godot --resolution 1560x720 --script
  res://tests/touch_scroll_test.gd`.
- Needs: a phone playtest of everything above; three-finger gestures on real
  phones; auto-resolve time on a phone; campaign pacing with real players.

Playtest feedback round (2026-10-05, built, uncommitted):
1. HUD scaled by device (`game/ui_scale.gd`: touch 0.88, mouse 0.82 CSS px
   per logical px, menu "UI size" S / M / L), compact unit cards wrapping
   into rows (no scrolling: 26 units in 2 rows on the phone, 1 on a
   desktop), actions in one row above the cards, Withdraw army in the top
   bar, one-line collapsible readout, grouped start menu with folded Tests.
   Screenshots `docs/screenshots/hud_*.png` (phone 780x360 CSS, 1920x1080,
   3840x2160). Unverified on the real phone and the 4K monitor.
2. Stone throwers aim at the near face of the target, lead its movement and
   land short rather than over (beyond-the-rear 28-82% -> 1-27%).
3. More ammunition (archers 40, javelins 6, bolts 11, stones 15 per engine).
4. Artillery Refill order: one more load in the baggage, ~70-90 s to bring
   up, cannot move or shoot meanwhile; the AI uses it.
Details and numbers in DESIGN.md (Artillery "Stone aim", "Refill";
Missiles "Ammunition"; section 7 "HUD as built").

Terrain height (built 2026-10-05, uncommitted): needs a phone playtest of
the look (contours, shading, readability of units on top) and of the
WebGL2 terrain shader on the Android phone and an iPhone; the playable
battles now get random terrain (menu "Terrain:" button to choose, "Replay"
for the same seed and ground, `?terrain=ridge&seed=N` on the URL). Four
terrain test scenarios are on the menu. Flat battles play exactly as
before (checked against the previous build).

Earlier (committed in `49c1022`):

A tuning pass from playtest feedback (built, uncommitted):

1. Cavalry charges resolve per rider and lap around the enemy front instead of
   the whole unit stopping when a few riders make contact.
2. Archers must be able to kill cavalry in the open (suspected cause: arrows
   aimed at where a fast target was, not where it will be).
3. Units rout later and mainly because of casualties taken: heavy infantry,
   spears and pikes hold to roughly 50-60% losses in an even frontal fight,
   light and missile troops to 30-35%. Flank and rear attacks should break
   units by killing soldiers, not by a large instant morale penalty.
4. Follow-up (2026-10-05): cavalry was too strong against the front of
   formed heavy infantry. Fixed by causes: impact direction judged per
   victim (men who face or can turn to the rider take it frontally), frontal
   impacts into a steady unit meet shields / full armour / support from the
   ranks behind and a strike back, a full charge needs ~18 m of run-up (no
   momentum from running away), and turning away from a melee costs a free
   blow; a horse only carries on into a second man when it breaks through.
   60 cavalry into a standing heavy 100 at 30 / 60 degrees: 97 / 100 killed
   -> 35 / 47, and the riders mostly lose; repeated frontal charging went
   from a 100% cavalry win to a costly loss. Details and the keep-list
   in `docs/DESIGN.md` (Cavalry charge).
5. Mirrored fairness: the bottom army won ~58% of 420 mirrored AI battles.
   Causes found and removed (each confirmed with its own probe): the AI
   armies thought 5 ticks apart; unit think phases followed the global unit
   index (the army listed second reacted sooner); unit processing order
   alternated by tick parity, which the mirrored geometry fixed at contact
   (one side always struck first in cavalry clashes); the scenario left the
   top army 1-6 m off the mirror image; and some direction-dependent
   rounding / scan order. Now 50.6% top over 840 battles (both unit orders).
   Check with `godot --headless --script res://tests/matchups.gd -- --fair=N`.

### Open items

- Campaign bug fixed (2026-10-05, from play): two armies ordered into the
  same enemy region in one turn (Lilybaeum -> Carthago by sea) fought
  separately: the second was bounced by "battle pending there". Now an
  army entering a region whose battle started this turn joins it (attackers
  or defenders, 24 field units a side, else "battle side full"); AI attacks
  that commit several armies now arrive together too. Sea-lane neighbours
  still do not reinforce passively (open: whether they should).
- iPhone Safari (iOS 18.7) ran the 4,000 benchmark on the terrain build at a
  steady 60 fps (sim 3.1 ms mean, 7 ms worst per tick) and the terrain shader
  works there. It only rotates to landscape when opened from the home screen
  ("Add to Home Screen"); a Safari tab cannot force orientation.
- **iPhone determinism is not yet cross-checked** against another device on
  the same build. Run the same fixed-seed benchmark on the iPhone and one
  other device and compare with `tools/playtest_report.py`.
- The user reports performance is good on every device tried so far.
- Occasional frame hitches at 4,000 soldiers (a whole sim tick runs inside one
  frame). Fix by spreading tick work across frames if it becomes annoying.
- "A unit with a move order does not fight" was chosen so cavalry can pull out
  and units can retreat. Unconfirmed that it feels right in play.
- The game is reachable at `https://strategiccommand.ggior32.dev` through the
  user's Caddy reverse proxy, which holds a real certificate and forwards
  plain HTTP to the dev server on port 8060. The dev server is not hardened
  and only lives as long as the session that started it.
- Install support (2026-10-05): the export writes `manifest.json` and
  192 / 512 px icons (tools/make_web_icons.gd), standalone, landscape. No
  service worker: Godot's PWA worker answers from its cache first, which
  could serve a stale build, so there is no offline play. Android Chrome
  offers install without a worker (unverified on the user's phone).
- A mild top/bottom bias may remain in mirrored AI battles (53-55% on some
  seed ranges, 50.6% on another). Settle before head-to-head play.
- Deferred battle features: fatigue, horse archers, a manual brace
  toggle, siege equipment (ladders, towers) and climbing walls, sallies,
  spreading tick work across frames; terrain visibility (hiding behind
  hills or in woods).
- Terrain: phone GPU behaviour of `game/terrain.gdshader` is unverified
  (desktop GL only); the AI's high-ground behaviour (hold, detour, rises)
  is unplaytested; menu buttons are 44 px tall to fit the new entries.
- Artillery is unplaytested: look and readability of engines, bolts, stones
  and impact marks on a phone; whether the Deploy button and set-up times
  feel right; whether AI batteries and guards behave sensibly in play.
- bench_4000 (two armies a side) now runs ~10 min to a decision (2,000:
  ~5 min); the AI's second line and batteries could be looked at.

## Where we are headed

Agreed with the user on 2026-10-06, in this order (milestones 1-5, battle
maps, settlement variety, sieges, free movement and the wall/reachability
fixes are all landed; see "Where we are"):

1. **Continuous overworld** (in progress): Rome 2-style positions on a
   campaign grid, paths and range shapes, zones of control, siege by moving
   onto a city, support by radius with lines, stances (forced march,
   fortify, raiding), turn animation; campaign layer kept data-driven so it
   can be reused for a different setting (the user has an American West
   game in mind on the same engine).
2. **Phone round on the overworld**, then a tuning pass from what it shows.
3. **Roads, rivers and crossings** as grid-cell overrides (historic roads,
   rivers as barriers with fords and bridges; ford battles on the battle
   map).
4. **Cities must be worth defending** (agreed 2026-10-07, moved ahead of
   everything else after the Skilled campaign AI found that an army is
   better off fortified outside a city than inside it: in the formula
   only the garrison gets the wall bonus (+15 % a level) while a fortified
   field army gets +25 %, 88 % of attacked cities fall, no AI siege has
   ever ended in surrender; in the sim walls-3 attackers win 87-100 % of
   the 1.5-2:1 `siege_test` battles). Principles: **no stat bonus for
   standing inside walls**; defence is attrition at the wall and a slow,
   narrow street fight. In three parts, all sim-first, the formula fitted
   to the sim afterwards, none a save-format change:
   1. **Done 2026-10-07: attrition at the wall** (see "In progress right
      now" for the table: walls 3 about 30 % with ladders and a ram, none
      on arrival; walls 1 missed, 100 %). As agreed: wall archers hit
      harder from the battlements (cover / height levers), **arrow towers
      at walls 2** shooting siege bolts and **two stone throwers mounted
      on walls 3**, immobile garrison engines with a fixed ammunition
      load (+ammo from a building inside), crews that can be shot and
      towers that batteries can duel; walls-2/3 gates nearly immune to
      hand weapons and somewhat tougher; **attacker siege equipment:
      ladders** (foot units climb the wall from outside, slower the higher
      the wall level) **and a ram** (a slow engine unit the gate yields
      to), earned by siege turns in the campaign (optional key on the
      siege entry, no format bump) and chosen in custom battles, so
      without artillery you bring ladders and a ram or starve them (added
      2026-10-07); a **battle time limit setting** (today a fixed 15 min
      `BattleSim.TIME_LIMIT`) in the campaign settings, custom battles
      and the sandbox so long sieges can run. Calibration target: an
      **equal-force siege matchup set**, walls 3 equal strength ->
      attacker about 25 %, walls 1 about 45 %.
   2. **Units do not pass through each other** (part 2a done 2026-10-07:
      blocking, queueing, street frontage, gate rush; walls 1 still 100 %,
      see "In progress right now"; open: the defenders' disposition at
      walls 1, the rest of this item): unit-level blocking first (an enemy unit's footprint is impassable
      in the 4 m pathing grid, frontage clamps to the corridor a unit is
      in, friendly units pass through each other at half speed so streets
      never deadlock), soldier-level separation only at the contact seam
      if it still reads wrong; walls thicker and walls-2/3 cities 15-20 %
      larger inside, measured against the city tick budget; stone
      throwers over the walls at the army inside. Then siege equipment
      over turns (ladders / towers after 2-3 turns), suburbs and river
      sites, sallies from inside.
   3. **Fit the formula** to the measured siege results across force
      ratios (a walls term for the armies inside is a prediction of the
      sim, not a bonus), turn the campaign AI's shelter knob back on and
      re-run the AI tables.
4b. **Battle screen on the overworld** (agreed 2026-10-07, next build
   after part 2b, before part 2c): one screen in two states, used for
   auto-resolve and fought battles alike. *Pre-battle* (replaces the
   auto / fight choice): a map preview at the top (the settlement drawn
   from its seed via `city_preview.gd`, or the field's terrain kind and
   woods, with both deployment edges marked); both sides' compositions
   as rows of unit cards (icon, men, tier) with a **health bar under
   each card** (current men vs full strength), attackers left, defenders
   right, grouped by army and faction, garrison and support armies
   included; a siege equipment line (ladder sets, ram, towers); the odds
   bar and the existing buttons (Auto-resolve / Fight / siege choices).
   *Result* (after auto-resolve, and after a fought battle): a big
   VICTORY / DEFEAT / DRAW with the one-line outcome (city taken / held,
   army destroyed, withdrew), labelled "Auto-resolved" or "Fought"; below
   it, per side, the same card rows with survivors vs fielded as the
   health bar (lost part marked) and kills beside each unit, totals at
   the foot; Continue. Fought battles take the sim's tallies, auto-resolve
   the formula's per-unit losses.
5. **Elephants**, then camels, chariots, war dogs.
6. **AI competency** (`docs/AI.md`): Easy / Average / Skilled on two
   independent axes (battle, campaign) plus personality, no cheats ever;
   skill is reaction, perception, planning, execution and deliberate
   plausible mistakes. Decided 2026-10-06: AI obeys fog of war if it ever
   exists; difficulty global with per-faction Advanced overrides;
   personalities and army composition styles per faction by default.
   **Step 1 done (2026-10-06): profiles as data, no behaviour change.**
   `sim/ai_profile.gd` (148 battle / settlement knobs) and
   `campaign/cai_profile.gd` (60 campaign knobs), Average / Balanced = the
   old values exactly (Easy and Skilled rows are copies for now); scenario
   `ai_skill` / `ai_style` per side (hashed only when not default, kept by
   snapshots), campaign `settings.ai_battle_skill` / `ai_campaign_skill`
   and `factions[i].ai_skill` / `ai_battle_skill` / `ai_style` (written
   only when not default: no `CState.VERSION` bump); new-campaign
   "Difficulty" row and sandbox "AI:" button (Easy / Skilled marked
   "soon"); per-competency counters (`BattleSim.stat_aic`, campaign
   `CP.count`, printed by `campaign_sim`); `cdata` FACTIONS `ai_style`
   (all Balanced) and `composition` placeholders. Verified: determinism
   golden digests and all final hashes, campaign_sim 6x60 per-seed
   hashes, sieges, campaign_test / solo / battles equal to HEAD.
   **Step 2 done (2026-10-06): Easy, battle and campaign** (`docs/AI.md`
   section 10). Battle: slower thinking, narrower perception, no terrain
   sense, marches straight in, archers never in skirmish mode, no
   fall-back of mauled units, chases routers, plus a deliberate-mistake
   roller on the sim RNG (9 mistakes, per-side cooldowns in hashed
   `BattleSim.ai_mist`; lockstep and snapshot tested). Average beats Easy
   74 % (flat) / 71 % (hill) of mirrored battles; Easy vs Easy 50 / 50,
   no draws. Campaign: cheapest builds, one recruit a turn, nearest
   targets, no gathering / screens / relief / stances, storms on arrival,
   no peace, 5 mistakes on `CState.rand`; an Easy faction ends about as
   big as at Average (target not met: Average's caution costs it as much,
   see AI.md). Several "Easy" behaviours (no pull-outs, unguarded
   batteries, nearest targets, early charge) beat Average and were kept
   at Average: a lead for step 3. Average / Balanced byte-identical
   (determinism, sieges, campaign_sim hashes). UI: Easy without "(soon)".
   **Step 3 done (2026-10-06): Skilled battle and settlement AI** (`docs/AI.md` section 11; reserves, rotation, matchups, focus fire, siege wall shift / breach / sally; beats Average 72 % flat, 67 % hill, Easy 89-95 %; Easy / Average byte-identical).
   **Step 4 done (2026-10-07): Skilled campaign AI** (`docs/AI.md` section 12; `SK_*` knobs in `campaign/cai_profile.gd`, 0 at Easy / Average): never shelters inside the walls (fortifies outside), support-aware hunting at two to one, spare armies merge into / stand by the main army, staging and falling back out of the enemy's reach next turn, storming before a relief, counter-composition, war when the neighbour's armies are away from the border, peace offers to close a second front; no mistakes. One faction Skilled ends turn 60 with +47 % regions over 24 seeds (6.58 against 4.48; +44 % on 6) and 41 eliminations against 70; Macedon not better (3.7 against 4.0, noise). ~0.8 ms per Skilled faction-turn. Average / Easy byte-identical (campaign_sim hashes; golden hash and RNG in campaign_test); no state change, VERSION 6. UI: Campaign AI Skilled without "(soon)". `campaign_sim --knob=` for ablations. Next: step 5 (personalities and composition styles per faction, the Advanced per-faction UI, the split setting).
7. **Mid-battle reinforcements** from the map edge; ambush stance once
   hidden information in an async game is designed.
8. **Shared empire** (both humans running one faction).
9. **Server to Proxmox** via `server/deploy/docker-compose.yml` (Podman),
   plus delete-campaign and revoke-device admin. Independent; whenever the
   user wants the server off the dev machine.
10. **Sprite animation pipeline**: parts + procedural motion workflow and
    tooling, written up in `docs/ART_PIPELINE.md`. Last on purpose: the
    symbolic soldiers stay until the game is in a good state.

Further out: the American West game as a data set and roster on the same
campaign engine; a 3D client remains possible without sim or campaign
changes (view-only), but art cost, not code, is the deciding factor.

## Decisions already made (do not reopen without the user)

- Co-op only for now; head-to-head and controlling the enemy army come later.
- Simultaneous turn planning; the turn resolves when both have submitted.
  Turn timeout is a campaign setting (off, or one of several durations).
- Battles never block silently: they become pending and are resolved by
  auto-resolve, solo real-time, or live co-op.
- If the ally's army is in range and they are offline, the present player
  chooses per battle: wait for them, or take command of their army.
- In co-op battles each player commands their own army; units can be gifted
  and gifted back. Pause and speed changes need both players to agree.
- Per-soldier combat (health, blocking, individual hits) is a hard requirement.
- Live battles use deterministic lockstep, so the sim must stay integer-only.
- Game rules run on the clients; the server stores saves and relays traffic.
- No generals, family, politics, agents or naval combat in the first version.
- Web first (Godot export with threads off). Notifications through Discord.

## How to run things

```sh
# Campaign tests
godot --headless --script res://tests/campaign_test.gd      # rules, determinism, JSON
godot --headless --script res://tests/campaign_sim.gd -- --seeds=6 --turns=60   # AI pacing (format 6; --format=5 the region-hop rules)
#   campaign_sim: --skill=easy|average|skilled, --skill-f=rome:s (one faction), --knob=s:ID=VALUE (ablation), --twice
godot --headless --script res://tools/campaign_grid.gd [-- --check --png=/tmp/grid.png]  # regenerate / check the nav grid
godot --headless --script res://tests/campaign_solo.gd      # 20 turns of a player policy
godot --headless --script res://tests/campaign_battles.gd   # auto-resolve timing, formula calibration
godot --script res://tests/campaign_input_test.gd           # needs a window
godot --headless --script res://tests/matchups.gd -- --only=tiers   # tier balance
# Campaign testing aids: -- --campaign=rome[,greeks][:seed] --sim-turns=N
#   --camp-attack=N:region --camp-fight --select-army=N --select-region=key
#   --cam-zoom=Z --dialog=battles|summary|diplomacy|realm|goals --new-campaign
#   --controls --ios-tab; battle: --demo-ghost=deg

# Tests
godot --headless --script res://tests/determinism_test.gd
godot --headless --script res://tests/benchmark.gd
godot --headless --script res://tests/matchups.gd
godot --headless --script res://tests/matchups.gd -- --fair=100   # mirrored AI battles
godot --headless --script res://tests/matchups.gd -- --only=terrain  # terrain effect sizes
godot --headless --script res://tests/matchups.gd -- --fair=50 --fair-terrain=4  # mirrored, symmetric hill map
godot --headless --script res://tests/matchups.gd -- --only=maps     # woods, streets, gates, settlement battles
godot --headless --script res://tests/matchups.gd -- --only=sieges   # settlement battles only
godot --headless --script res://tests/matchups.gd -- --only=plans --seeds=8 [--plans=0,4]   # each wall plan at walls 1-3
godot --headless --script res://tests/matchups.gd -- --only=fair-sieges [--plans=4 --walls=3 --rows=0 --time-limit=1800 --tune=WALL_COVER=0,25,45,70]
#   equal-force sieges, ladders + ram (row 0) or artillery only (row 1); shard by plan / walls / row
godot --headless --script res://tests/probe_maps.gd -- --scen=siege_town --png=1500 --out=/tmp  # siege debug pictures
godot --headless --script res://tests/ladder_probe.gd [-- --walls=2 --plans=4 --quick]   # every stretch climbable as the preview says (~7 min)
godot --headless --script res://tools/city_dump.gd -- --out=/tmp --seed=1234   # generated settlements to PNG
# Sandbox URL / command line: --siege=seed:level:walls[:ground[:kind[:defend[:plan[:coast[:equip[:time]]]]]]], --ground=N, --no-trees
#   (equip 0 none, 1 three ladder sets, 2 three ladder sets and a ram; time = battle time limit in s)
godot --script res://tests/input_test.gd        # needs a window
tools/check_scripts.sh                           # GDScript warnings as errors (in a scratch copy of the
                                                 # project: safe while other Godot runs use this checkout)

# Live co-op battles (milestone 5)
godot --headless --script res://tests/lockstep_test.gd   # snapshots, two peers, mid-battle join (-- --quick)
python3 tests/live_e2e.py --port 8077            # two headless clients, three live battles + two custom battles
python3 tests/live_e2e.py --port 8077 --only-custom   # just the custom head-to-head and co-op battles (~90 s)
godot --headless --script res://tests/custom_battle_test.gd   # custom setups build and run
godot --headless --script res://tests/deploy_view_test.gd     # deployment through the battle view
python3 tests/custom_shots.py --port 8081         # phone screenshots: setup, deployment, head-to-head lobby (needs a window)
# Testing aids: -- --custom (the custom battle screen), --custom-solo, --custom-template=test_cav_archers,
#   --custom-join=CODE; web: ?custom=CODE
python3 tests/live_shots.py                      # phone screenshots of the co-op UI (needs a window)
(cd server && PATH=$HOME/.local/go/bin:$PATH go run ./cmd/webcheck -url http://127.0.0.1:8074 -live)
                                                 # two headless Chromiums, live battle (serve a web export there)

# Server (milestone 4; see docs/SERVER.md)
tools/build_server.sh --test                     # go vet + go test + build build/server/scserver
SC_BUILD_OUT=build/server-test/scserver tools/build_server.sh   # elsewhere (tests do this)
tools/run_server.sh 8070                         # serve build/web + API + telemetry on a port
python3 tests/online_e2e.py                      # two headless clients against a test server (~30 s)
(cd server && PATH=$HOME/.local/go/bin:$PATH go run ./cmd/webcheck -url http://127.0.0.1:8070)
                                                 # the web export in two headless Chromiums

# Web build and playtest server
tools/export_web.sh                              # writes build/web
python3 tools/serve_web.py 8060                  # plain HTTP, behind Caddy
python3 tools/serve_web.py 8443 --cert .certs/dev.crt --key .certs/dev.key
                                                 # self-signed, direct on the LAN
python3 tools/playtest_report.py                 # summarise playtest_logs/
```

- Godot's web build needs a secure context, so phones must use HTTPS. The
  self-signed certificate in `.certs/` (gitignored) is created with
  `openssl req -x509 -newkey rsa:2048 -nodes -days 365 -keyout .certs/dev.key
  -out .certs/dev.crt -subj "/CN=strategic-command-dev"
  -addext "subjectAltName=IP:<lan ip>,IP:127.0.0.1,DNS:localhost"`.
  Each browser shows a warning once; accept it.
- `?scenario=bench_4000` on the URL jumps straight into a scenario;
  `&seed=N&terrain=ridge` fixes the seed and ground of a playable battle
  (flat, rolling, ridge, valley, hill, slope, random). The battle's seed
  and terrain kind are shown in the top-left readout. Benchmark
  scenarios use a fixed seed so hashes can be compared between devices, but
  only between builds with the same `sim:` hash in the build stamp.
- Web export templates for Godot 4.7.2 (no-threads variants only) are in
  `~/.local/share/godot/export_templates/4.7.2.stable/`.
- Playtest telemetry lands in `playtest_logs/` (gitignored).

## How we work

- Design, architecture and review happen in the main session with the user.
  Code generation is delegated to the latest Opus model (see `CLAUDE.md`).
- The loop: build, re-export, the user playtests on their phone against the
  dev server, telemetry plus their impressions drive the next change.
- Commit only when the user says so.
