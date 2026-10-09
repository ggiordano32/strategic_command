# Strategic Command — Design Doc (draft 1)

A 2D, sprite-based, co-op grand strategy game inspired by Rome 2: Total War,
built in Godot 4 for web and mobile. Campaign turns are played asynchronously
in short sessions; battles are real time and can be fought solo or together.

Status: draft for discussion. Items marked **OPEN** are undecided, items marked
**VERIFY** are technical assumptions to test before relying on them.

## 1. Goals and non-goals

Goals (v1):

- Two players, allied, against AI factions. Co-op only.
- A campaign turn fits in a 15 minute session, and neither player blocks the other for long.
- Real-time battles where player skill beats auto-resolve.
- Per-soldier combat: every soldier has health, can block, and takes individual hits.
- Must-have battle mechanics: pikes, missiles, cavalry charges, morale, retreat.
- Runs in a browser on Android and iPhone (installed to home screen), plus desktop.

Non-goals (v1): head-to-head play, friend controlling the enemy army, generals,
family/politics, agents, naval combat, accounts, anti-cheat,
original art.

## 2. Campaign layer

### Turn structure

- Simultaneous planning: each player issues orders for their own faction at any time.
- The turn resolves when both players have submitted. AI factions then move.
- Whichever client submits last runs the resolution and the AI turn, then uploads the new state.
- Turn timeout is a campaign setting: disabled (always wait), or one of several
  durations (e.g. 12 h, 24 h, 48 h, 72 h). When it expires the waiting player
  may force-resolve; the absent player's faction simply holds position.

### Map and economy

- Continuous overworld (state format 6, October 2026): regions with one
  settlement each over a static nav grid (cells of 0.2 deg of latitude,
  square on the map); armies stand anywhere on it. The older formats were a
  region-node map (settlements connected by routes); online campaigns of
  those formats still play that way.
- Each region has one settlement with a small number of building slots.
- Buildings come in a few chains: economy, military (unlocks units), growth/order.
- Resources: money and one growth/population value. Upkeep for armies.
- Armies recruit in owned settlements, limited by the military buildings present.
- **Reuse:** the campaign layer is meant to carry a different game later
  (the American West). Everything specific to the Mediterranean is data:
  regions, routes, sea lanes, factions, rosters, starts and numbers in
  `campaign/cdata.gd`, the coastlines and territories in
  `game/campaign/map_geo.gd`, from which `tools/campaign_grid.gd`
  generates the nav grid (`campaign/data/grid_data.gd`). The rules
  (`campaign/crules.gd`, `cgrid.gd`, `cai.gd`) read only those tables.

### Movement (continuous overworld, as built October 2026, state format 6)

- Armies stand on cells and march 8-connected paths to a destination cell
  (A*, ties by cell index) within movement points a turn by their slowest
  arm (foot 200, cavalry only 300, with artillery 150; a cell costs 10 on
  open ground, 15 hills, 20 ridges, +5 in heavy woods, diagonals 14/10);
  marches continue on later turns. Rome to Tarentum: two turns on foot, one
  for cavalry. Sea lanes join port cells (a full turn's points).
- Zones of control: every army in the field holds a circle of 2 cells
  (fortified 3); paths keep out of enemy zones unless that army is the
  target. An army stepping next to an enemy army attacks it: a field battle
  on that cell. Moves resolve in rounds (one step per army, by id), so
  armies meet where they plausibly meet.
- Moving onto a hostile settlement lays siege from its ring (or storms it
  on arrival); onto your own settlement goes inside the walls; an army
  inside moving onto a besieger sallies; marching on your own besieged city
  relieves it.
- Stances: default, forced march (+50% points, cannot attack, fights badly
  if caught), fortify (immobile, wider zone, longer support reach, a
  defender's bonus), raiding (-30% points, takes half the income of the
  enemy region it stands in).
- Friendly armies within 4 cells (fortified 6) of a battle join it and
  deploy on the map edge facing where they stand. The view shows the reach
  area, zones, support (yellow) and attack (red) lines, paths with this
  turn's end marked, and replays the turn's steps. Details: CAMPAIGN.md
  "The continuous overworld".

### Diplomacy

- States per faction pair: war, peace, trade agreement.
- The two players are permanently allied.
- AI accepts or refuses proposals from a simple score (relative strength, war weariness, shared enemies).

### Settlement attacks

- v1: attacking a settlement is a field battle in which the garrison joins the defender.
- As built (October 2026): every settlement has its own battle map with
  streets, walls and gates (section 4 "Battle maps: woods and settlements").
  Ladders, a ram and tower engines since 2026-10-07 (section 4 "Siege
  equipment and wall towers"); siege towers are later.
- Sieges (as built, October 2026, state format 4; CAMPAIGN.md "Sieges and
  battle odds"): marching into a hostile settlement lays siege by default
  (Assault, the battle at once, is one tap away). Since format 5 (free
  movement) marching in raids, and laying siege or storming is chosen;
  since format 6 (the overworld) moving onto the city lays siege from its
  ring and besiegers also go hungry once the city's supplies run out. A siege cuts the city's
  income, recruiting, building and growth, runs down its supplies (2-4
  turns by level, +1 with granaries) and then starves the garrison until it
  surrenders. Each turn the besiegers may storm it (a settlement battle),
  the defenders may sally, and an army of the owner's side marching in
  relieves it; sallies and reliefs are field battles on the region's
  terrain with the garrison riding out. Every battle shows its odds (the
  battle formula's prediction) as a balance-of-power bar.

## 3. Pending battles

A battle created during planning or resolution becomes a *pending battle* on
the campaign state rather than blocking the turn. It can be resolved by:

1. Auto-resolve.
2. Solo real-time battle against the AI (pause and slow-motion allowed).
3. Live co-op battle after pinging the other player.

Rules:

- The turn cannot advance past a pending battle; it must be resolved first.
- Battles the player starts during their own planning can be fought immediately.
- Battles started by the AI wait for the affected player's next session.
- Armies within reinforcement range join the battle, including the ally's.
- If the ally's army is in range and they are offline, the present player
  chooses per battle: wait for the ally (the battle stays pending and they are
  pinged), or take command of the ally's army (the ally is notified).

## 4. Battle layer

### Scale targets

- Unit: 60–120 soldiers. Army: up to ~10 units.
- v1 target: 2,000 soldiers on the field at 30+ fps on a mid-range phone browser.
- Stretch: 4,000 (two allied armies against two enemy armies).
- Battle length: 5–10 minutes.

### Control in co-op

- Each player controls their own army by default.
- Units can be gifted to the other player at any time and gifted back.
- Reinforcing armies arrive from the map edge matching their campaign position.
- As built (milestone 5): see section 5 "Live battles: as built".

### Per-soldier combat model

Each soldier has: position, facing, hp, state (formed, fighting, knocked down,
routing, dead), attack cooldown. Stats come from the unit type: melee attack,
melee defence, armour, shield block (frontal arc only), weapon damage, reach,
mass, speed.

- **Melee hit:** attacker rolls attack against defender's defence; a hit then
  tests the shield (only if the blow comes from the defender's frontal arc),
  then armour reduces damage, then hp drops. Flank and rear hits skip the
  shield and get a bonus.
- **Pikes:** reach is long enough that ranks 1–4 can all strike the same front.
  An enemy approaching the front must pass through that reach zone, taking
  attacks from several ranks before their own weapon is in range, and is held
  at distance while the formation is intact. Pikes turn slowly and fight
  poorly once flanked or disordered.
- **Cavalry charge:** on contact, impact damage and knockdown scale with speed
  and mass against each soldier hit. Charging the front of braced spears or
  pikes applies the impact to the cavalry instead.
- **Missiles:** each arrow gets a landing point (aim plus scatter) and landing
  tick when fired. On landing, the nearest soldier within his hit radius of
  the point (friend or foe) takes a hit roll, shield test by direction, then
  armour. No per-frame arrow physics.
- **Morale:** tracked per unit, not per soldier. Driven by casualties, flank
  and rear attacks, charges received, and nearby routing friends. A broken
  unit routs; it may rally if left alone.
- **Retreat:** a unit ordered to withdraw leaves by the map edge and survives
  into the campaign. An army can withdraw as a whole.
- **Aftermath:** the campaign stores headcount and experience per unit, not
  per-soldier hp.

### Performance design

Per-soldier simulation is the main cost, so the sim is built around it:

- No node per soldier. State lives in flat packed arrays (struct of arrays).
- Rendering uses one MultiMesh for all soldiers (and one for missiles) with
  the sprite and tint chosen in a shader; the sim's packed arrays reach the
  GPU with native calls only (two paths, see "8. Art").
- Fixed simulation tick at 10 Hz; rendering interpolates to display rate.
- Soldiers in a formed unit that is not near an enemy only move toward their
  formation slot. They skip collision and target search entirely.
- A uniform spatial grid handles neighbour and target lookup for soldiers that
  are near enemies.
- Attack cooldowns are staggered so only a fraction of fighting soldiers
  resolve an attack on any tick.
- The sim core sits behind a narrow interface (orders in, state arrays out) so
  it can be ported from GDScript to a C++ GDExtension if profiling demands it.
- **VERIFY:** GDScript throughput for 2,000–4,000 soldiers on iPhone Safari.
- **VERIFY:** GDExtension in web exports on iOS Safari, as the fallback.

### Battle AI

- Unit-level behaviours: hold line, advance, flank with cavalry, skirmish with
  missiles, protect flanks, rout pursuit.
- An army-level planner picks a deployment and assigns behaviours.
- Every threshold and interval it uses comes from a skill / personality
  profile (`sim/ai_profile.gd`; design in `docs/AI.md`). Easy (built)
  thinks slower, notices less, ignores terrain and makes deliberate,
  plausible mistakes rolled with the sim's RNG (lockstep-safe). Skilled
  (built, `docs/AI.md` section 11) keeps a foot and a cavalry reserve and
  commits them when the enemy wavers, rotates tired units, assigns
  matchups, focuses missile fire, reads morale, ammunition and where enemy
  riders are heading, and in sieges shifts wall units, counter-charges the
  breach and sallies; its memory is hashed sim state (`ai_mem`), and it
  never gets anything a player does not.

### Milestone 2: mechanics as built

Numbers are the current data in `sim/unit_types.gd` and constants in
`sim/battle_sim.gd`; `tests/matchups.gd` is the balance regression tool.

**Unit types.** Heavy swords, light infantry, spearmen, pikemen, archers,
javelinmen, shock cavalry, bolt throwers, stone throwers. Behaviour classes:
infantry, pike, missile, cavalry, artillery (see **Artillery** below). Spacing is per type (pikes 1.0 x 1.1 m, archers 1.3 x 1.6 m,
javelins 1.8 x 2.0 m loose, cavalry 2.0 x 3.0 m). Equal-cost units (cost per
soldier: heavy 6, light 4, spear 5, pike 5, archer 5, javelin 4, cavalry 10)
are the reference for balance.

| Type | Att | Def | Arm | Shield / vs missiles | Dmg | Reach | HP | Run m/s | Special |
|---|---|---|---|---|---|---|---|---|---|
| Heavy swords | 40 | 35 | 14 | 40% / 70% | 42 | 1.3 | 100 | 3.6 | |
| Light infantry | 36 | 26 | 4 | 15% / 40% | 36 | 1.2 | 85 | 4.4 | |
| Spearmen | 15 | 30 | 9 | 35% / 55% | 30 | 2.2 | 90 | 3.6 | brace 55, +20 vs cavalry |
| Pikemen | 34 | 40 | 8 | 20% / 30% | 30 | 5.5 | 90 | 3.0 | 4 ranks strike, brace 80, sword 18/16/24 |
| Archers | 18 | 16 | 3 | 0 / 0 | 24 | 1.0 | 75 | 4.0 | 140 m, 40 arrows (was 20), 4 s reload |
| Javelinmen | 28 | 22 | 3 | 20% / 35% | 28 | 1.2 | 80 | 4.2 | 40 m, 6 javelins (was 4), 2.8 s reload |
| Shock cavalry | 36 | 28 | 10 | 20% / 15% | 32 | 1.6 | 150 | 8.2 | mass 400, charge 70, turns 90 deg in 1.6 s; arrows x1.2, 9% of hits down the horse |
| Bolt throwers (crew) | 14 | 14 | 3 | 0 / 0 | 22 | 1.0 | 75 | 0.8 packed | 4 engines x 4 crew, cost 25/crew |
| Stone throwers (crew) | 14 | 14 | 3 | 0 / 0 | 22 | 1.0 | 75 | 0.7 packed | 3 engines x 6 crew, cost 30/crew |

**Flank and rear** are judged by where the attacker stands relative to the
defending *unit* (its anchor and facing: ahead of its front line, behind its
rear rank, or alongside / beyond the end of the line; `BattleSim._zone`), not
by the angle between two duellists or how the struck man is turned. One
function decides it for every melee blow: the shield (frontal blows only),
the to-hit bonus (+25 flank, +40 rear), the morale and disorder hit and the
pike's short sword. Oblique blows inside a frontal melee stay frontal, and a
man at the end of the line who turns to face a flanker is still taken in the
flank (until 2026-10-09 the shield and bonus used the man's own facing, so
men drawn out of the line took 40-65 % of their blows "from the side").

**Ranks hold together in melee** (2026-10-09). A fighting man walks in on his
enemy only as far as `PLACE_LEAD` (1.5 m) ahead of his place in the
formation, measured along the unit's facing, and `PLACE_SIDE` (3 m) to
either side of it (`BattleSim._cap_lead`: only the part of a step that goes
beyond is cut; a man already beyond stops going further rather than being
pulled back). The search ranges are unchanged (the front rank still picks a
man up to 8 m ahead, keeps him to 10 m), so "fighting" (`u_fighting`, which
the AI reads) still means engaged; what moves the fight forward is the
anchor: an attacking unit keeps closing until one of its men is within
reach + 1 m of his man (`u_inreach`, hashed), then stands. It may step into
its own target's footprint to get there (unit blocking, below), and while
its men are engaged elsewhere it does not walk away from them (it closes
only while it is at most half its depth + 2 m ahead of its men's middle,
`ANCHOR_LEAD`). On settlement maps the street path is taken while no man is
in reach (it was: while none fights). A unit standing without an order
holds its ground: its front rank leans out at most 1.5 m. Wrapping (below)
is capped ahead the same way (not sideways), so wrapping men lap round
sideways, not out ahead of the line. Not capped: riders with charge
momentum, men on a stair or ladder move, units on a wall. Before this a unit's front rank walked up to
8-17 m ahead of rank 2 (gap mean 6-9 m), enemy men got into the gap, and
half a unit chased routers 100 m off while the rest stood at the marker.

**Pursuit is the unit's move.** Men do not run after routers beyond the
cap. A unit whose attack target is routing advances its anchor after it
(the in-reach stop does not apply) at the run, so pursuit happens when the
player orders an attack on a routing unit or the AI does (it already targets
routers once no formed enemy is nearer, docs/AI.md 3.13).

**Wrapping.** Front-rank soldiers of an engaged attacking unit who have no
enemy within reach close on the target unit instead of holding their slots,
so a wide unit laps round a narrow face (a flank) instead of leaving most of
its men idle. Formed pikemen only count as "fighting" (which holds the unit's
anchor) while their target is within pike reach, so two pike blocks close
until their points meet.

**Moving disengages.** A unit with a move (or withdraw) order does not fight:
its soldiers drop their targets and follow their slots. This is what lets
cavalry pull out and units withdraw; to fight, halt or attack. Soldiers whose
target is routing or pulling away close at the run, within the 1.5 m lead
above. Turning away costs a
*parting blow*: on the tick a soldier disengages, the enemy he was fighting
(if still fighting and within reach) gets one free blow at his back (rear
bonus, no shield). This is what makes pulling cavalry out of a melee cost
riders.

**Pikes.** While the formation is *formed* (not disordered, morale at least
shaken, not turning more than ~14 degrees, at least two ranks, not running):
- Ranks 1-4 strike from their slots at enemies in a forward cone within 5.5 m;
  the soldiers do not leave formation to fight.
- A pike wall holds enemy soldiers 2 m off the front line across the frontage
  (+0.6 m). Swords (1.3 m) cannot reach; held attackers lunge at -20 to hit
  with 1 m extra reach, so pikes take a few losses. Spears (2.2 m) can just
  reach.
- Pikes turn at ~1 degree per tick (90 degrees in ~8.5 s) and are unformed
  while turning; reform-in-place orders wheel slowly too.
- Disorder (0-100, decays 2/tick, formed below 25): +4 per flank hit, +6 per
  rear hit, +10 per charge impact; running sets it to 30.
- Unformed, or hit from flank/rear: secondary weapon (short sword, attack 18,
  defence 16, damage 24, reach 1 m), no multi-rank strikes, no wall.
- A formed pike block counts as braced (moving or not).

**Cavalry charge.** A unit with an attack order running with its anchor at
>= 60% of run speed builds momentum (+4/tick to 100: a full charge needs
~2.5 s, about 18 m, of run-up; 40 for any impact after ~7 m); running away
under a move order (pulling out) builds none. Each rider carries his own
momentum. When
a charging unit (attack order, momentum >= 40) comes into contact, the charge
resolves rider by rider: the anchor waits and the facing is held (cavalry
turns at most ~5.6 degrees per tick), riders with a man ride at him at the
run, and riders without one ride straight on along the charge, steering for
the nearest enemy in a forward cone, spreading round friends who have stopped.
The charge ends when every front-rank rider has made contact, no rider is
still riding in with momentum, 5 s have passed or another order is given; the
formation then re-forms where the riders stand. (Before this, the first
contact stopped the anchor and riders without a target slot-followed it and
stalled: at 30 degrees off the front only a third of the front rank struck.)
A rider with momentum >= 40 reaching an enemy delivers an impact to that
soldier; if the horse breaks through (that man is killed or knocked down,
or was not standing steady facing it) it carries on into one more within
1.8 m at 60% power (the least hurt, then nearest: a rule that does not
depend on direction). Two charging riders meeting head-on strike each other
at once.
- Direction is judged per victim, not per rider position: a soldier who has
  the rider within his frontal arc, or is free to turn to him (not fighting
  someone else) and is not taken from behind, meets the charge *frontally*,
  even when the rider has lapped round the end of the line. Otherwise x1.3
  (flank) or x1.6 (rear, beyond 120 degrees of his facing, or into routers
  and men already down).
- force = charge x momentum x direction x m_rider / (m_rider + m_victim).
  Flank / rear: damage = force - armour / 2, knockdown force + 10% (cap 90%).
- Frontal into a steady unit (morale above wavering): the shield may take it
  (shield % chance: half force), armour counts in full, the ranks behind hold
  the man up (half knockdown chance while the unit has more than two ranks),
  and a man still on his feet strikes back at the horse at once (a normal
  melee blow). Frontal into a wavering unit: full knockdown chance.
- Knocked-down soldiers lie for 1.5-2.5 s: they cannot act and are hit at
  +35 with no shield.
- Into the *front* of a braced spear unit (standing still, formed, steady) or
  a formed pike block the impact is turned back: the rider takes brace x
  momentum damage, may fall (40%), and loses morale.
- Momentum is spent on impact, so a stuck charge becomes an ordinary (weak)
  cavalry melee; pulling out (parting blows) and charging again after a new
  run-up restores it.
- While a unit fights off a charge (15 s after the last impact) its rear
  ranks look for enemies within 4.5 m instead of 2.5 m, so riders lapping
  round the side files meet the men behind instead of idle ranks.

Tuning pass result (October 2026; `tests/matchups.gd`, 20 seeds; before ->
after): 60 cavalry charging a standing 100 heavy swords kill by 40 s, at 0 /
30 / 60 degrees off the front: 33 / 97 / 100 -> 23 / 35 / 47 (the riders then lose the melee and break;
at 60 degrees, where many riders do reach the side, the infantry sometimes
breaks). Charge, pull out
and charge again three times vs heavy 100 from the front: cavalry won 100%
(lost 11 riders, killed 92) -> cavalry loses 100% (loses 50 riders, kills
54: costlier than the infantry at equal cost, never a clean win). Kept: 100%
of the front rank strikes at 0/30/60 degrees; a rear charge into an engaged
heavy unit breaks it in all runs at 35% losses; braced spears / pikes throw
back the charge (23 / 26 riders lost); cavalry destroys unprotected archers
and loses ~23% charging them head-on from maximum range. The heavy-vs-heavy
control and the break-point table are unchanged; the equal-cost round robin
moved only within its 10-seed noise.

**Missiles.** Projectiles live in a 4,096-slot pool of packed arrays (fire
point and tick, landing point and tick, shooter and target unit) bucketed by
landing tick; nothing happens in flight. A firing unit fires `alive / reload`
shots per tick round-robin through its soldiers (only standing, formed
soldiers with ammunition shoot; no shooting while the unit moves). Each shot
aims at a random soldier of the target unit, led by his movement over the
flight time (integer, two refinement passes); scatter is a triangular error of
(base + distance x per-mille) sideways and 1.5x that along the flight. On
landing, the nearest soldier within 0.6 m (1.1 m for horses) is hit: units in
contact are searched through the melee grid (so friendly fire into melees
happens), the aimed-at unit otherwise through its formation slot geometry
(the slot under the point and its neighbours, nearest soldier wins).
85% of those strike; a frontal arrival can be stopped by the missile shield;
armour is reduced by armour piercing. Archers arc over friends; javelins are
thrown flat and a javelin unit only throws when no other friendly unit stands
between it and the target. Fire at will (default on) picks the nearest enemy
in range, preferring units not locked in melee; hold fire stops automatic
shooting, while an explicit attack order on an enemy ("shoot that unit")
still shoots. Fire at will keeps its current target while it stays in range
(switching only if that target gets locked in melee and a clean one exists),
so archers busy with infantry do not swing round to cavalry coming in from
the side. Horses are big, exposed targets: cavalry takes x1.2 missile damage
and 9% of hits bring the horse down outright, so 80 archers kill ~12 of 60
riders charging head-on from maximum range, ~30 standing or walking in range
for a minute, and none arriving while they shoot something else. Missile
troops with ammunition (and artillery crews) only fight soldiers within 2.5 m.
The pool has 128 landing-tick buckets (flights up to 12.7 s, for stones).
Skirmish mode (default on for javelins, off for archers): a unit falls back
35 m when non-missile enemies come within 30 m (55 m for cavalry).

Ammunition (October 2026, after "everything runs out of ammo fairly
quickly"): archers 20 -> 40 arrows, javelins 4 -> 6 (8 was tried: in the
equal-cost duels javelinmen then kited even spearmen to death), bolts 7 ->
11 and stones 10 -> 15 per engine, plus the artillery refill (one more
load). Kills by cause in 12 AI battles (bench_2000, flat / random
terrain), before -> after: missiles 6% -> 10% / 3% -> 6%, artillery 6% ->
8% / 3% -> 4%; battles 5.0 -> 4.6 min / 5.2 -> 5.5 min, no draws. Kept:
archers' full 40 arrows into the front of heavy 100 kill 2.6 (was 0.7);
cavalry charging archers head-on loses ~14 of 60 and wins; artillery
(940) still loses every time to heavy 100 + archers 68. Changed: in the
equal-cost open-field duels javelinmen now beat pikes and archers by
kiting them (spears and heavy still beat them), and javelins 150 beat
light 100 every time (was 65%).

**Artillery.** A battery is a unit whose soldiers are the crews (since
2026-10-09 its engines are equipment the crews can leave and any foot can
take up: "Engines are equipment, crews are men" below); its
engines are their own packed arrays (`e_*`: position, facing, hp, state
working / wrecked / abandoned, reload work, ammunition, crew at it), hashed
with everything else. Files = engines, laid out in a row (bolts 7 m apart,
stones 10 m); crew slot s works engine W[s % nw] of the working engines W, so
as men fall or engines are wrecked the survivors re-man the rest.

| | Bolt throwers (scorpions) | Stone throwers (onagers) |
|---|---|---|
| Battery | 4 engines x 4 crew (cost 400) | 3 engines x 6 crew (cost 540) |
| Range / minimum | 230 m / 15 m, flat | 290 m / 60 m, lobbed over friends |
| Shots per engine | 11 (was 7), + 11 in reserve | 15 (was 10), + 15 in reserve |
| Refill at full crew | 6.5 s per bolt (~70 s a load) | 6 s per stone (~90 s a load) |
| Reload at full crew | 7.5 s (silent below 2 crew) | 15 s (silent below 3 crew) |
| Flight | 55 m/s, leads moving targets | 28 m/s, leads the unit's movement 90% |
| Aim | a random man of the target | the near face of the target along the line to a random man, 0.5 m in |
| Scatter (triangular, x1.5 along) | 0.3 m + 1% of range | 1.5 m + 4.8% of range (was 4%); long errors halved |
| Shot energy / armour piercing | 120 / 80% | 130 / 50% |
| Arc / traverse | +-25 deg / ~10 deg/s | +-20 deg / ~7 deg/s |
| Set up / pack up | 6 s / 3 s | 12 s / 6 s |
| Engine hp | 160 | 260 |
| Fright per hit | 15 | 60 |

- *Deployed / packed.* `u_depl` counts 0 (packed) .. set-up time (ready).
  A battery shoots only when set up and standing; a move or withdraw order
  first packs it up (twice as fast as setting up), then it moves at 0.7-0.8
  m/s (never runs) with the engines rolling to their places, and on arrival
  sets up again. The Deploy order (`deploy` 0/1, an order key like `fire`)
  packs up and keeps it packed, or sets it up. Chosen over "cannot move once
  deployed" because the AI has to keep its batteries behind an advancing
  line and the player has to be able to re-site them; the set-up time is the
  price.
- *Arc.* Engines traverse within +-arc of the battery's facing; a target
  outside it (attack order, or fire at will's choice) makes the battery wheel
  (2 angle units per tick deployed, 8 packed). An engine fires when loaded,
  crewed and within ~3 degrees of the target's bearing.
- *Crew and reload.* Each tick an engine gains reload work equal to the crew
  standing (not fighting) within 5 m of it; a shot needs reload x full crew,
  so fewer hands mean slower fire and below the minimum it falls silent.
  Engines start part loaded (staggered).
- *Fire control* as other missile units: fire at will (default), hold fire,
  explicit attack = shoot that unit. Fire at will prefers big standing targets
  in the arc and refuses unsafe shots: bolts need a clear unit-to-unit line
  (as javelins), stones a target with no friendly unit within 15 m. An
  explicit order shoots regardless (the player's call; friendly fire is real).
- *Bolts* are resolved at landing along their whole flat line, from 3 m in
  front of the engine through the aim point and 25 m on: every soldier within
  0.45 m of the line (0.9 m for horses), friend or foe, is a candidate in
  order of distance. Each later man is 12% less likely to be struck; a
  frontal shield absorbs 60% of its missile-shield value from the energy;
  damage = energy left - armour x 20%; each body then absorbs 20 + armour.
  At most 5 men; a working engine on the line stops the bolt (and takes the
  energy as damage). Rule for friends: a bolt flies at body height the whole
  way, so friends in the line are hit just like enemies (resolved with
  everyone where they stand at landing time).
- *Stone aim* (October 2026, after "they hurl behind the enemy very
  often"): each stone used to aim at a random man anywhere in the
  formation, with no lead and a symmetric along-flight error of up to
  +-1.5x the spread, so a third of the stones landed beyond the rear of a
  standing line and two thirds or more beyond an advancing one. Now it aims
  at the near face of the formation along the line to a random man (the
  nearest soldier within 2.5 m of that line, 0.5 m in; computed with an
  exact length, since `approx_len`'s 4% error is metres at 200 m), leads by
  90% of the unit's mean movement (not one man's, who may be shuffling up
  to fill a gap), and keeps only half of a long error: a short stone lands
  in front and ploughs into the front ranks. Stones landing beyond the
  rear (`tests/matchups.gd -- --only=stoneaim`, 300-man line / 120 pikes at
  100 / 200 / 270 m): standing 38/36/35% -> 7/19/27% and 28/33/30% ->
  5/19/19%; advancing 66/71/82% -> 1/9/22% and 67/76/79% -> 3/12/24%.
  Killed per 30 stones, standing: line 22.6/20.0/15.8 -> 33.7/22.6/17.8,
  pikes 27.3/18.8/16.2 -> 37.0/24.2/17.7 (scatter widened from 4% to 4.8%
  to keep mid and long range near the old band; close range is deadlier).
  Advancing targets are now hit (line 3.5/7.7/4.3 -> 8.2/22.8/16.4):
  marching steadily in range of stones is no longer safe.
- *Stones* land at the scattered point: everyone within 0.9 m is struck, then
  the stone ploughs 9 m on along its flight through anyone within 0.6 m
  (1.0 m horses), losing 5 energy per metre and 30 + armour per body, at most
  6 men; damage = energy - armour x 50%, knockdown (energy / 2 + 20)%. No
  shield helps. An engine in the path takes double damage (counter-battery).
- *Refill* (order `ORDER_REFILL`, the action bar's "Refill" button with
  batteries selected): each battery carries one more full load in its
  baggage (`m_reserve` per engine, shown on its card as shots + reserve).
  Told to refill, a standing battery settles in over 6 s (`REFILL_FULL`
  ticks; it stops moving and shooting at once); once in, each working
  engine short of its load gains the work of the crew standing at it and a
  shot comes up every `m_refill` x full crew (bolts 6.5 s, stones 6 s at
  full crew; slower with fewer hands, nothing below the minimum crew). It
  cannot move, turn, traverse or shoot from the moment it starts settling
  until it is back out (3 s, twice as fast as settling). Any move, shoot,
  withdraw or Deploy order ends it (after the 3 s); melee or a rout breaks
  it off at once; it ends by itself when the engines are full or the
  reserve is empty. A finite reserve (rather than unlimited refills): in a
  5-10 minute battle one extra load roughly doubles a battery's shooting,
  and with a limit, when to spend the minute is a decision, and an
  unattended battery cannot fire for the whole battle. The AI refills when
  a battery is empty or below a quarter, or below three quarters with
  nothing in range, if no enemy melee unit is within 35 m (or coming for
  it within 100 m), and stops when threatened or once three quarters full
  with a target in range; it never refills a battery whose engines are
  all wrecked or abandoned. View: card "To refill 40%" / "REFILLING" /
  "Leaving refill" and blue shot count, a blue ammunition ring under the
  marker (dashed while settling in / out), "REFILLING 60%" on the Orders
  overlay; the paused preview covers the order like every other.
- *Engines* are wrecked at 0 hp: enemy soldiers within 2 m (counted through
  the melee grid, up to 6) take 3 hp each per tick, so a unit that reaches a
  battery wrecks it in seconds. A battery that routs or dies leaves its
  engines on the field, abandoned (no longer for good: see below).
- *Engines are equipment, crews are men* (built 2026-10-09, decided with
  the user; Rome 2's model). A battery's engines are a group (`eg_*`:
  first engine, count, type, the unit working it `eg_op`, and while
  abandoned the set-up progress, baggage shots and facing they were left
  with; `e_grp` per engine) that the unit works. **Drop** (`ORDER_DROP`,
  the ladders' and ram's order and button) leaves them where they stand,
  abandoned and neutral (hit points, shots, packed / set-up state kept);
  the crews fight on as plain men (`u_type` light infantry for pace,
  formation and class, their own body and arms: `u_otype`). **Pick up**
  (`ORDER_PICKUP` with `"engines": g`; tap the engines with a unit
  selected; `u_pick` = `PICK_ENG` + g): any foot unit of either side (not
  cavalry, not one carrying siege gear or already working engines, not on
  a wall) marches to them and, within 6 m, works them: it becomes a
  battery of the engines' type (`u_type`: range, reload, shots per engine,
  traverse, set-up, packed pace, refill, crew and minimum crew), its own
  missiles put aside (`u_oammo`) until it drops them again; its men keep
  their own melee, armour and morale (`u_otype`); men beyond the full crew
  stand in rows behind and do not work them (a battery working engines of
  its own kind keeps the old rule: all its men re-man what is left). A
  capture is the same pick-up by the enemy. A battery that breaks leaves
  them abandoned at once (free to anyone while it runs; one that rallies
  first stands by them as before, and can Drop and take them up again). Tower
  engines stay fixed. A shot in flight keeps the type it was fired with
  (`pr_ty`). The battle AI's missile units out of ammunition take up their
  own side's abandoned engines within 60 m (AI.md 17); AI batteries never
  drop. View: a grey marker with the engine's symbol and a dashed ring over
  free engines, "TAKE UP THE BOLT / STONE THROWERS" in the order preview,
  "on bolts" on the card, the engines drawn in the colours of the unit
  working them. Tests: determinism `--only=engines`, lockstep siege (B's
  battery leaves its engines, A's archers take them up and leave them,
  snapshots on the way), input_test (Drop, tap to take up).
- *Kills per unit* (`u_kills`, 2026-10-09, hashed): enemies killed by the
  unit's men in melee, by charge impacts, missiles, its engines (credited
  to the unit working them when the shot was fired) and a tower's engine
  (the tower unit); friendly fire is counted apart (`stat_ff`, not hashed).
  `result()` rows carry `"kills"`; a fought campaign battle's outcome rows
  too (an optional key the rules ignore), shown on the battle screen's
  cards.
- *Fright.* Each shot that strikes a unit adds its fear (bolt 15, stone 60,
  cap 200) to `u_fright`, which decays 1 per tick and counts against morale
  only for the rout check and the displayed state: a stone tips a wavering
  unit over but does not break a steady one; deaths still do the real work.
- *Cost*: the sweep culls units by bounding box against the path, so a shot
  looks only at soldiers of units its line really crosses; shots are few.

Numbers (`tests/matchups.gd`, 20 seeds): a bolt battery's full 28 bolts
along the depth of a standing 120-pike block from 150 m kill 26 (22%); into
the front of a standing heavy 100 only 6 (6%); along the block from its
flank 54 (45%). Stones (30) into a standing massed line (heavy, spear, heavy)
at 200 m kill 19 of 300 with peak fright ~120 and no unit broken; into a
standing pike block 21 (18%); loose javelins 15 of 60; cavalry walking across
1.4 of 60. Light infantry reaching a bolt battery wrecks every engine 5 s
after contact; cavalry charging stones wrecks them in 1.4 s (crews rout).
Duels: bolts beat stones at 200 m (all 3 stone engines lost), stones beat
bolts from 260 m (outranged), stones vs stones even. Both batteries (940)
lose to heavy 100 + archers 68 (940) in every run. Full 2,000 AI battles
with a bolt and a stone battery a side: 5.0 min mean (4.0-6.3), artillery
~3-8% of all kills.

**Morale** is driven mainly by casualties: each death costs 1200 / start
size, raised by up to 3x the share of the unit killed recently (decaying
with a ~3 s time constant), so a fast slaughter breaks a unit sooner than a
slow grind. Small extra penalties: -1 per hit on the flank, -2 on the rear,
-1 / -2 / -4 per soldier hit by a charge from front / flank / rear, -5 per
second per routing friend within 30 m (at most two). Missile wounds cost
nothing by themselves (the deaths do), but a unit hit in the last 3 s does
not recover. Flank and rear attacks do their work through kills: +25 / +40 to
hit, no shield, and pike disorder +6 / +10 per hit. Base morale sets the
class gap; in an even frontal fight units break at about: heavy 58%, spear
53%, pike 55%, cavalry 39%, archers 40%, javelins 34%, light 35% killed. A
broken unit may rally once if left alone (a milestone 1 off-by-one had made
rallying impossible); the second rout is final. Fatigue was left out:
cavalry already loses its edge once its momentum is spent, and nothing else
needed it.

**Retreat and battle end.** Withdraw (unit) and Withdraw army orders send
units at the run to their own map edge (side 0 bottom, side 1 top); soldiers
leave the field there and count as *withdrawn*. Routers flee away from the
nearest enemy, bent toward their own edge, and leave the field at any edge as
*routed off*. A side is beaten when it has no ready, non-withdrawing unit;
pursuit then continues until the loser has no one left on the field or 60 s
pass (`ended`). Undecided battles are a draw after 15 minutes.
`BattleSim.result()` returns plain ints per unit (started, killed, routed off,
withdrawn, remaining, state) and per side, for the result screen and the
campaign.

**Battle AI as built** (`sim/battle_ai.gd`, both armies think on the same
tick once a second, units once a second staggered by their index within
their side; state in hashed sim arrays): deploy pikes centre, solid infantry
next, light outward, cavalry on the wings, missiles 15 m ahead, second line
after 8 units; advance to a halt line in bow range and skirmish (unless
clearly outshot) for up to ~2 minutes or until three quarters of the arrows
are gone; engage when the lines are within 60 m. Infantry attack the nearest
enemy, spears take on nearby cavalry; nobody walks into a formed pike front
if it can be helped: one unit pins, the others go round to a flank staging
point and attack from there. Cavalry waits on the wings, charges unprotected
missile troops or enemy cavalry threatening the line at any time, and once
the lines meet picks engaged enemies, riding to a flank/rear staging point if
the approach would hit a braced or fresh front; after 5 s of melee it pulls
out 45 m and charges again; it rides down routers. Archers fire only while an
unengaged enemy is in range (no shooting into their own melee) and move
behind the line when it engages. Units below 30% strength and shaken fall
back 60 m and rejoin after 30 s; cavalry under arrows while waiting rides
down the shooters if nobody guards them and otherwise pulls out of range,
and prefers archers that are shooting at something else; the army withdraws
when its fighting strength is under 30% of the enemy's, or under a fifth of
its own starting strength while weaker than the enemy (empty batteries count
almost nothing). The lines engage when their *foot* are within 60 m
(cavalry raids and batteries no longer flip the whole army into melee).
Every number in this paragraph (think intervals, distances, ratios, target
scores) is a knob of the side's AI profile, `sim/ai_profile.gd` (skill
Easy / Average / Skilled, personality Cautious / Balanced / Aggressive;
the values here are the Average / Balanced row), carried per side in the
scenario (`ai_skill`, `ai_style`); the settlement AI and the campaign AI
(`campaign/cai_profile.gd`) likewise. See `docs/AI.md` "As built: profiles",
"As built: Easy" and "As built: Skilled" (the Skilled level adds reserves,
rotation, matchup assignment, focus fire and the other behaviours switched
on by its SK_* knobs, which are off for Easy and Average).
Artillery: bolts deploy at the ends of the first line (clear, flat field of
fire), stones 25 m behind the centre; a battery keeps its place while it
has targets in range and friends within 30 m, otherwise packs up to follow
its slot when that is 30 m away; it shoots the best safe target (soldiers x
cost, enemy batteries +900, pikes x1.5 for bolts, standing x4/3, cavalry
halved, moving targets halved for stones), and halts rather than shoot into
friends; empty batteries fall back once and stay there. One unit (spears,
else light, else heavy; only with at least five foot units) guards the
first battery from a post beside it and attacks any non-missile enemy within
70 m of it, rejoining the fight once the battery is gone or empty. Cavalry
rides down unguarded batteries (and engaged ones once the lines meet);
cavalry shelled while waiting charges the battery if unguarded, otherwise
steps 40 m out of its arc; a side shelled by stronger artillery stops
skirmishing and closes; retired units shelled while idle step aside.

**Benchmarks** (desktop, Ryzen 7 5800X, AI vs AI, mixed armies with
artillery, seed 42). With terrain height (October 2026): bench_4000 (flat)
mean 2.87 ms, p95 4.12, max 5.6-5.7 (the AI's `_plan()` now reads the sim
arrays through typed locals: 280 -> 75 us per call, ~0.06 ms off the mean);
bench_4000_hills mean 2.6-2.7, p95 4.2-4.4, max 6.2-6.4 (budget 3.23 /
6.45: the worst ticks are the AI army ticks and deployment, close to the
limit); bench_2000 1.30 / 2.58. Before terrain: 4,000 soldiers mean 2.93 ms per tick (milestone 1
infantry-only: 2.15; before artillery 2.26), p95 4.25 (3.46), max 6.12
(4.30): within 1.5x. 2,000: mean 1.31, max 2.67. Artillery costs ~0.12 ms
per tick at 4,000 (profile_phases); the rest of the rise is a different,
more continuously engaged battle (cavalry raids now make contact from tick
~450). Units take turns
acting first within a tick (forward or reverse unit order, chosen by the sim
RNG each tick).

**Mirrored fairness** (`tests/matchups.gd -- --fair=N` runs bench_2000, two
180-degree mirror-image armies, as given and with side 1's units listed
first; the default run also has mirrored duels per type). Before this pass
the bottom army won 58% of 420 battles. Causes found and removed, each
confirmed by its own probe: (1) the two AI armies thought 5 ticks apart;
(2) unit think phases were staggered by global unit index, so the army listed
second reacted sooner after each army decision (the side listed first lost
57-69% of foot-only battles); now staggered by index within the side;
(3) forward / reverse unit order alternated by tick parity, and mirrored
armies meet on a tick whose parity the geometry fixes, so the same side
always acted first in a head-on cavalry clash (60 vs 60 mirror: 367 / 178);
now chosen by the RNG, and two charging riders strike each other at once;
(4) the scenario laid both sides out with the same integer maths, leaving
the top line 1 m and its screen and rear row 6 m off the mirror image
(scripted foot-only battles: bottom ahead 57%, 50.8% after); side 1 is now
the exact mirror of side 0; (5) direction-dependent rounding and scan
order: fixed-point `>> 12` (floors) replaced by `/ 4096` (truncates,
antisymmetric), and the charge's extra victim is no longer the first found
in grid scan order. Result: top army wins 51.4% (as given) and 49.8% (side 1 listed first) of
420 battles each, 50.6% overall; mirrored duels per type within noise.

### Terrain height: as built

Numbers are the constants in `sim/battle_sim.gd` ("Terrain" block) and the
per-type fields `climb`, `m_hgain`, `m_apex` in `sim/unit_types.gd`;
`tests/matchups.gd -- --only=terrain` measures them.

**Height field.** `sim/terrain.gd` builds an integer height grid with nodes
4 m apart over the field (heights in sim units, 1 m = 1024, lowest node 0)
once at setup, from the scenario's `terrain` dictionary (all ints): `kind`
(flat, rolling, ridge, valley, hill, slope; random = one of those five from
the seed; custom = only hand-placed features), `seed` (-1 = the battle
seed), `relief_m`, `scale_m` (0 = the kind's default), `sym` (exactly
symmetric under the 180-degree rotation that swaps the armies; fairness
tests) and `features` (hand-placed: round hill or hollow, ridge or valley
along a segment, one-sided ramp). Generation composes features with smooth
integer profiles (a (1 - d^2/r^2)^2 bell computed from squared distances,
no square root; a smoothstep ramp), uses its own xorshift RNG (never the
sim's), and takes 3-7 ms for a 560 x 600 m field on the desktop. Defaults
keep the steepest ground of a playable map around 15-25% (rolling 9 m over
~95 m features, ridge 12 m, valley 10 m, hill 16 m, slope 18 m) plus low
(1 m), broad undulations. The grid's MD5 and the parameters form
`ter_hash`, which is in the `state_hash()` header: two peers that built
different maps disagree at tick 0. Nothing is transmitted; the campaign
will pass kind + seed (or features). No `terrain` key, or kind flat:
`ter_on` = 0 and every terrain rule is skipped, so flat battles are
bit-for-bit those of the build before terrain (golden trajectory digests in
`tests/determinism_test.gd`). The AI vs AI benchmarks stay flat;
`bench_4000_hills` is the fixed hilly benchmark (rolling, terrain seed 4242,
generator version 1: changing the generator changes it).

**Sampling.** `height_at` is fixed-point bilinear: the whole weighted sum
is formed exactly and divided once, so the mirrored point of a symmetric
map gives exactly the same height; `slope_at` interpolates node gradients
(central differences) the same way, antisymmetric under mirroring. Field
sizes are multiples of 4 m so mirrored points fall in mirrored cells. The
determinism test checks 16,000 points, gradients, grades and line-of-fire
results on four symmetric maps for exact symmetry. Lookups cost 0.2-0.6 us
on the desktop.

**Where lookups happen.** Not per soldier per tick: slope effects on
movement are per unit (one slope and one height lookup per unit per tick,
at the anchor and centroid); soldiers then move at their unit's pace.
Per-soldier lookups happen only per melee blow (2), per charge impact (2),
per shot (2, plus the line-of-fire samples for flat weapons) and per bolt
victim.

| Rule | As built |
|---|---|
| Uphill | speed -`climb`% per 10% of grade along the direction of travel (the unit's facing in melee): light, javelins 13; archers 14; heavy, spears 15; pikes 17; cavalry 24; packed bolts 40, stones 45. Never below 30% (artillery 20%) |
| Downhill | +5% at 10% and gentler; beyond 20%, -1% per 1% of extra grade (cavalry twice) |
| Steep ground (>= 20%) | moving across it adds 4 disorder a tick (decay 2) up to 30: a pike block's wall comes down, spears cannot brace while moving there. A pike block standing on it takes 150% disorder from flank, rear and charge hits |
| Melee | the man striking down gets +0.8% to hit per 10% of grade between the two (height difference over their distance), at most +-2% (25%); rolled per mille on hilly maps so small slopes give small edges |
| Charge impact | rider above the victim: +20% per 10% of grade, at most +35%; below: down to -45% |
| Charge momentum | uphill the cap falls by 3 per 1% of grade (40, the minimum for any impact, at 20%); 10% or more downhill builds 5 a tick instead of 4 |
| Missile range | + `m_hgain`% of the height difference shooter - target: arrows and stones 1.5 m per metre, javelins 1.0, bolts 0.6; at most +-30% of the range. Target choice uses unit centroid heights; each shot the shooter's and aim point's |
| Line of fire | flat weapons (javelins, bolts): the straight line from 1.5 m above the shooter's ground to 1 m above the aim point's, allowed to rise `m_apex`% of the distance at mid-flight (javelins 10%, bolts 2%), sampled every 4 m (8 m for target choice), ground within 3 m of either end ignored. Fire at will skips hidden targets; an explicit order on one is refused (missile infantry walks to a quarter of its range until it can see; a battery waits) |
| Bolts | stopped where the ground rises above the line (also over the 25 m plough); strike only men the line passes between 0.2 m below and 2 m above their feet (a bolt shot down a hill passes over men below its line) |
| Stones | plough length -40% per 10% uphill (at least 15%), +15% per 10% downhill (at most 130%) |
| Arrows | arc over everything; only the range changes |

**AI** (all through player orders; hilly maps only, flat decisions
unchanged): deployment shifts up to 30 m aside, back or forward when that
line stands 2 m higher; while skirmishing the line halts on a crest short
of its halt line if that is 1.5 m higher and still within reach; an army
whose foot stand 4 m or more above the enemy holds its ground (at most 4
minutes, and only while not clearly outshot or outgunned by artillery) and
its foot attack only enemies within 25 m until a third of them are
fighting, then the battle is on everywhere; infantry whose last 35 m to the
target climb more than 15% goes round to the target's flank if that final
approach is at most two thirds as steep and the detour at most 1.7x as
long (once per target, `A_DETOUR`); cavalry target scores lose 60 per % of
uphill grade; archers, javelins and batteries take the highest spot within
12 m aside / 10 m back or forward of their slot if 1 m higher, bolt sites
with a line of fire to the enemy counting 4 m higher; a bolt battery whose
targets in range are all behind a crest moves to the first nearby spot
(forward first) from which it sees the nearest enemy. Cheap: the bolt
siting walks candidate spots from the highest down and stops once no lower
spot can win (16 m samples), and a battery that is staying put skips it.

**View.** `game/terrain_layer.gd` builds an RGBA8 texture once per battle:
the 4 m sim grid upsampled to 2 m with a Catmull-Rom midpoint rule, height
as 16 bits in R/G, hill shade (light from the upper left, relief exaggerated
2.5x) in B, A reserved for vegetation. `game/terrain.gdshader` draws the
whole field in one pass: it fetches the four nodes with `texelFetch`
(nearest; no float textures, no reliance on filtering precision), decodes
and interpolates in highp, tints by height (+-22 m around the mean height,
slightly darker and cooler low, lighter and warmer high), applies the soft
shade (at most about +-30% brightness), draws contours every 2 m (every fifth darker) about 1 px wide at
any zoom via `fwidth`, fading them out where they would be packed closer
than ~6 px (minor) / ~8 px (major), with levels set half an interval off the
commonest height so a plain never lies on a line, and the faint 50 m grid
(kept, toned down to 4.5% white, now 1 px at any zoom). Flat maps draw the
old colour and grid. Soldiers are not shaded by height (not needed; the
contours and shading read well under them). The overlay shows the selected
missile unit's and battery's range bent by height (radius per direction:
range against the ground under that point, two refinements), "uphill /
downhill N%" on the selected unit's attack line and move destination when
the average slope is 4% or more, and a flat shot blocked by the ground as a
broken red line to the crest, a red cross there and "NO LINE OF FIRE".

**Measured** (`tests/matchups.gd`, 20 seeds unless noted):
- Equal heavy 100 vs heavy 100 on a slope, side above wins (60 runs per
  cell, high side at the top and at the bottom equally; flat control 55%):
  both advancing to meet 56 / 63 / 66 / 88% at 5 / 10 / 15 / 25% grade;
  the higher one holding while the lower climbs 57 / 64 / 70 / 84%. (Before
  tuning, whole-percent to-hit steps gave 80% at only 5%; hence the
  per-mille roll.)
- Archers 80 vs archers 80, 115 m apart: flat 32 / 31 killed; the unit on
  a 15 m hill kills 42 and loses 7 (the lower one is mostly out of range).
- Cavalry 60 charging a standing heavy 100 across a 12% slope: infantry
  killed by 40 s 23 flat, 29 downhill, 12 uphill (same 45 impacts; riders
  lost ~25 either way; the cavalry still loses to a steady heavy front).
- Pike 120 holding against heavy 100: wins every time on flat and on 15% /
  25% slopes either way; losses 9 flat, 4-5 above, 11-14 below. Pinned and
  flanked on a 25% slope the block does far less damage (2 attackers killed
  vs 45 flat), mostly because the pinning unit climbs slowly and the
  flankers arrive first; the steep-ground disorder rule itself adds little
  (2.9 without it).
- Bolts ordered at a pike block behind a 6 m crest: 0 fired (refused every
  time); at light infantry clear of the crest: 28 fired, 29 killed.
- Stones on a pike block on a 10% slope: struck 37 uphill, 40 flat, 43
  downhill (killed 17.6 / 18.4 / 18.8).
- Mirrored AI battles (bench_2000) on mirror-symmetric generated maps,
  60 seeds x both unit orders: hill 62 bottom / 58 top, rolling 62 / 58, no
  draws; on flat maps, same seeds 0-119: 132 / 108 (identical to the build
  before terrain, battle by battle: this 55% is pre-existing on this seed
  range; the earlier 840-battle figure was 50.6%).
- AI battles on generated terrain (60 runs, 12 per kind): decided in 3.5-
  7.7 min (mean 4.3-5.8 per kind), no draws.
- Flat: every earlier matchup line is unchanged.
- Benchmarks: see below.

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
  skirmish, and only wall units may enter the walkway (attackers only by
  ladders: see "Siege equipment and wall towers"). Since the October 2026 wall-orders fix: a move order onto a
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
  sent up (see "Stairs" below). Battlements stop 25 / 45 / 70 % (wall level
  1 / 2 / 3; 35 % at every level before round 3) of missiles that would
  hit a man on a wall from below. Lines of fire (flat shots) are blocked by
  buildings (4-6 m), walls (walkway + 0.6 m parapet), towers (+4 m) and
  closed gates; a shooter on a wall looks over his own battlements. Arrows
  and stones arc over everything; a stone's plough stops at a building or
  wall.
- *Gates*: start closed. The defenders may open or close one (order
  `ORDER_GATE`, any of their units; closing is refused while anyone stands
  in it; a broken gate stays broken). Hit points 1,800 / 2,700 / 3,800 by
  wall level (walls 2-3 x 130 % since 2026-10-07: "Siege equipment and
  wall towers"). Batteries ordered at a gate (`ORDER_ATTACK` with `gate`)
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
the wall" (view) sends a unit to the stretch within 60 m nearest the
nearest enemy (`man_wall_target`); "Come down" to the foot of its nearer
stair (`wall_inside`). Attackers climb only by ladders ("Siege equipment
and wall towers"). State
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


### Deployment phase (as built, October 2026)

Total War's deployment: before the fighting, each player places their
army inside their side's zone, sees the enemy's line, and says ready.
Code: `sim/battle_sim.gd` (section "deployment phase" at the end of the
file, plus small hooks in `setup`, `step`, `_apply_orders`,
`apply_order_rule`, `state_hash`), `sim/lockstep.gd`, `sim/scenarios.gd`
(`field_zones`, settlement zones), the view (`game/battle.gd` `_queue` /
`_deploy_ready` / `_refresh_deploy`, `game/hud.gd` deployment bar,
`game/overlay.gd` zones).

- **Scenario keys.** `deploy_time` (seconds; 0 or absent = none, so every
  existing scenario plays and hashes exactly as before: golden digests
  unchanged), `deploy_need` (bit per player who must be ready; default
  player 0, or nobody when both sides are AI), `deploy_zones`
  `[[side, kind, x0, y0, x1, y1], ...]` in metres: kind 0 a rectangle a
  placement is clamped into, kind 1 (settlement defenders) the open ground
  inside the walls within the box (a placement elsewhere is refused). No
  zones: each side's half beyond 30 m from the centre line.
- **Zones as built.** Field battles (campaign, custom): each side's part of
  the field from 30 m beyond the centre line to its edge, plus a 40 m box
  round every unit of the side standing outside that band (armies arriving
  on a flank). Settlements: the attackers the approach band (from 40 m
  ahead of their front to their map edge); the defenders inside the walls
  (any piece of open ground with every gate shut other than the attackers'
  piece, within the walls' box: citadels included) and on the walkways;
  an open town: a square round it.
- **Phase.** `phase` is `PHASE_DEPLOY` from setup while `dep_left` (sim
  ticks) > 0. A deployment step applies the players' orders (scripted
  orders, player 50, and AI orders wait for the battle), counts down, and
  ends the phase when every player in `dep_need` is ready
  (`dep_ready`), nobody needs to be, or the countdown reaches 0. Nothing
  else runs: no movement, shooting, morale; `tick` stays 0, so the battle's
  own clocks (scripted orders, AI timings, the time limit) start with the
  battle. All of it is hashed (only when `dep_on`) and in snapshots.
- **Orders.** `ORDER_PLACE {unit, x, y, facing, files}` (deployment only):
  the order rule `place_rule` (shared with the preview) clamps the point
  into the zone (or refuses it), refuses a house / wall / gateway on
  settlement maps, puts a defender who may man the walls straight onto the
  walkway when the point is on a wall (`wall_snap` + `wall_anchor`, two
  ranks), and the sim stands the men in their places at once
  (`_place_unit`: soldiers, engines, bounds). In the deployment the other
  orders are refused except the standing settings (run, fire at will,
  skirmish, artillery set up). `ORDER_READY {who}`. The view maps its
  ordinary gestures (tap, line drag, group move) to placements, so there
  is nothing new to learn; attack orders flash "orders wait for the
  battle".
- **AI sides** deploy at the start on field maps: the battle AI's tick-0
  thinking runs in setup and its units are placed where it sends them (kept
  to its zone), so the player sees the enemy line; on settlement maps the
  scenario's placement (walls, gates, plaza) stands and the siege AI starts
  with the battle.
- **Lockstep.** Placements are ordinary sim orders for one's own units;
  ready is the sim's ORDER_READY with the issuing player as `who`.
  `Lockstep` keeps `sim.dep_need` = the players taking part (set at the
  start, a dropped player's bit cleared, an admitted player's set), so the
  battle never waits for someone who has gone; the countdown keeps it
  bounded anyway. Pausing (a vote in co-op) stops the countdown.
- **View.** The zones (own blue and filled, the enemy's red outline), a bar
  under the top buttons: "Deployment 0:42", who is ready / "Waiting for X",
  Start battle (solo) / Ready (live), Enter key; the unit book and the
  controls do not pause a live battle (as before).
- **Campaign.** New-campaign screen "Deployment time: none / 1 min / 2 min"
  (default 1 min), stored as `settings.deploy_time` only when set (read with
  a default of none: no `CState.VERSION` change; online campaigns made
  before have none). `CBattle.build` gives a battle fought by players
  (`human_f >= 0`) the phase and its zones; auto-resolve (`human_f = -1`)
  ignores it. A live co-op battle opens its lobby as before and goes into
  the deployment when the host starts.

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

- **Hard gates.** Walls-2/3 gates have `GATE_HP_PCT` 130 % of their old
  hit points (3,510 / 4,940) and take `GATE_HACK_BY_WALLS` 1 % instead of
  25 % per sword blow (a few hours of hacking): they yield to rams and
  artillery. Walls 0-1 gates are unchanged.
- **Tower engines** (walls 2-3; city key `towers`: 0 leaves them out). At
  setup the sim appends engine units of the defenders (UT "fixed") on the
  generator's towers (`map_info.city.towers`, in order): bolt throwers on
  the towers flanking each outer gate first, then on others nearest the
  main gate at least 40 m apart, 6 in all at walls 2 and 8 at walls 3; at
  walls 3 first two stone throwers on the biggest towers not by a gate
  (`_siege_towers`). None on a citadel's towers or on the sea wall. Each is
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
  player gets its card like a battery's (no Deploy / Refill). It does not
  count toward a side's standing units (`_check_winner`) or the town-lost
  count.
- **Siege equipment as objects** (part 2b, 2026-10-07; replaces part 1's
  per-unit ladders flag and the ram unit; Rome 2's model). Scenario
  `equip` `[[kind, x_m, y_m], ...]` (`EQ_LADDERS` a set of 5 ladders,
  `EQ_RAM`), the attackers', on the ground behind their line
  (`Scenarios.settlement(..., {"ladders": sets, "ram": n})`, 12 m apart).
  Sim arrays `q_kind / q_x / q_y / q_state (GROUND, CARRIED, PLANTED,
  WRECKED) / q_unit / q_seg / q_wx / q_wy / q_hp / q_acc / q_side`, per
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
    it (`q_acc`). Climb, walkway fighting, the way down (`_ladder_down`)
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

### Ammunition kinds and fire (as built, 2026-10-09)

Data in `sim/unit_types.gd` `AMMO` (rows referenced by index; a second
theme replaces the table, not code). A type's weapon shoots its standard
kind (`m_ak`); a unit may carry one special kind riding on it (its row's
`base`), a fixed `share` of its load per man (`sammo`) or per engine
(`e_sammo`). ORDER_AMMO (`u_akind`, hashed) picks which it means to shoot;
a man or engine out of that kind shoots the other. Each field is applied
generically: `dmg` (vs men and engines), `obj` (vs gates, towers, rams,
ladders, wagons), `ap`, `pierce`, `range`, `rate` (reload), `fear` (morale
per man hit; artillery: added fright), `blast` (extra radius), `fire`.

| Kind | On | Share | Dmg | Obj | Range | Rate | Fear | Blast | Fire | Pays with |
|---|---|---|---|---|---|---|---|---|---|---|
| Fire arrows | arrows | 33 | 70 | 100 | 85 | 125 | 3 | - | 35 | damage, range, rate |
| Heavy bolts | bolts | 33 | 135 (+10 ap, 140 pierce) | 150 | 75 | 140 | - | - | - | range, rate |
| Fire javelins | javelins | 33 | 75 | 100 | 85 | 120 | 3 | - | 35 | damage, range, rate |
| Fire pots | stones | 33 | 55 | 200 | 90 | 110 | 30 | - | 70 | damage vs men |
| Explosive stones | stones | 20 | 100 (130 pierce) | 50 | 85 | 125 | 40 | +1.5 m | - | walls, range, rate, share |
| Lead bullets | sling stones | 33 | 130 (+20 ap) | 100 | 85 | 100 | - | - | - | range, share |

**Fire** is one state on any wooden thing: a gate (`g_burn`), an engine or
a tower's engine (`e_burn`), ladders on the ground or carried, a ram, a
wagon (`q_burn`). A fire missile landing within reach (a gate's face, 3 m
of an engine or piece, a tower's radius) sets it alight with its `fire`
chance; it burns FIRE_TICKS (30 s, restarted by each new fire missile)
losing FIRE_CHIP (0.6 %) of its full hit points a second: a gate breaks, an
engine is wrecked (a tower falls), a piece is wrecked (a wagon's stock
lost). Planted ladders do not burn (out of reach). A man hit by a fire
missile sets his unit burning (BURN_UNIT 4 s, 1 morale a tick). Missile
troops can be told to shoot a gate (tap it): only fire missiles do
anything to it. HUD: an Ammo toggle (V) like Fire / Skirmish; cards and
the battle screen name the kind; the unit book lists the kinds and who
carries them. Campaign: `CData.AMMO_AVAIL` (faction, building: the Range
for arrows and javelins, the Workshop for shot), stored on the unit entry
as `"ak"` (optional key); a city's tower engines carry the owner's kind
for them (scenario `tower_ak`).

### Resupply: foraging and the ammunition wagon (as built, 2026-10-09)

**Foraging** (ORDER_FORAGE, `u_forage`): archers and javelinmen standing
in woods make missiles of the standard kind for their own quivers, a whole
unit's load in FORAGE_QUIVER (2.5 min); they cannot move or shoot, and
stop when hit, in melee, moved (or skirmishing away), out of the woods or
full. HUD: Forage (J), shown only in woods.

**The wagon** is a unit (crew: `WAGON_CREW`, line "siege") whose men pull
a piece of equipment (`EQ_WAGON`, created at setup, carried). Tiers are
data (`UnitTypes.WAGONS`):

| Tier | Unit | Horses | Pace (0 / 1 / 2 horses) | Hit points | Horse hp | Stock | Auto-resolve |
|---|---|---|---|---|---|---|---|
| 1 | Hand Cart | 0 | 0.9 m/s | 600 | - | 100 % | +6 % |
| 2 | Ammunition Wagon | 1 | 0.9 / 1.3 m/s | 800 | 240 | 150 % | +9 % |
| 3 | Supply Train | 2 | 0.9 / 1.3 / 2.0 m/s | 1000 | 240 each | 220 % | +12 % |

Stock at 100 %: 1,600 arrows, 240 javelins, 22 bolts, 16 stones, 1,600
sling stones (AMMO `wagon`), and of each special kind of its army a share of its base's.
Horses are hit boxes in front of the wagon (arrows / javelins landing
within 3 m strike one 30 % of the time; bolts and stones near it hit
wagon and team); a dead horse slows it to the next pace. Crew gone: the
wagon stands where it is; **any foot unit of either side may take it**
(tap it): it pulls it at the wagon's pace, cannot attack or shoot, fights
at the carrier penalty and +15 % to-hit against it from the flank or rear;
Drop any time. Roofed like the ram. **Refill** generalised: a missile unit
or battery near a wagon (15 m) told to refill settles REFILL_FULL ticks,
then draws a missile at a time (its special kind up to its share, then the
standard kind) until full or the stock is out (a unit's whole load in 30
s); a battery's engines draw from it once their baggage is empty and the
baggage is topped up from it after. Campaign: recruited from the Workshop
(cart: Workshop 1; one horse: Workshop 2 + Stables 1; two: Workshop 2 +
Stables 2), counts 20 % of its price as strength, and adds its tier's %
to the army's missile and artillery strength in auto-resolve.

### Camels and elephants (as built, 2026-10-09)

Rows of `sim/unit_types.gd` `BEASTS` (lines "camel", "camel_archer",
"elephant"; one tier each) with generic fields any row could use: `mount`
(0 foot, 1 horse, 2 camel, 3 elephant), `files0`, `acc` (momentum per tick),
`body_r`, `crew_shoot`, `woods_pct`, `trample_n` / `_r` / `_pct`, `crush`,
the horse scare `scare_r` / `scare_pct` / `scare_mor`, the fear aura
`fear_r` / `fear_horse` / `fear_foot`, `burn_pct`, `amok` / `amok_r` /
`amok_calm`, `kill_delay`, `gate_walls` / `gate_pct`. Numbers chosen once
(shock cavalry the yardstick), not tuned:

| | Camel Riders | Camel Archers | War Elephants (12) |
|---|---|---|---|
| Run / turn 90 deg / full momentum | 6.5 m/s / 2.1 s / 3.3 s | 6.2 m/s / 2.1 s | 6.0 m/s / 4.3 s / 5 s |
| Att / def / armour / hp | 32 / 34 / 8 / 150 | 20 / 24 / 4 / 140 | 34 / 20 / 10 / 2500 a beast |
| Mass / charge | 450 / 45 | 450 / - | 2200 / 85, into 4 more men within 4 m at 80 %; 50 % through braced points |
| Missiles | - | 110 m bow, 30 arrows | 2 javelin men a beast, 50 m, 16 shots |
| Aura | horse scare 30 m: 70 %, 2 morale/s | the same | fear 25 m: horses 6, others 2 morale/s |
| Other | woods 150 % | woods 150 %, skirmish | woods 200 %, fire drains 200 %, gates of walls 0-1 at 6 men's rate |
| Price | 540 | 480 | 960 |

- **Horse scare** (once a second, box to box): enemy units on horses within
  `scare_r` keep `scare_pct` of their charge power and turn rate
  (`u_scare`) and lose `scare_mor` a second; a horse charging a unit with a
  scare hits at its `scare_pct` and loses heart (the shy). Camels vs spears
  are riders like any (vs_cav, braced points).
- **Fear aura**: enemy units within `fear_r` (but those with an aura of
  their own) lose `fear_horse` / `fear_foot` a second. A unit inside any
  aura recovers no morale (`u_awe`).
- **Elephants**: one soldier per beast, a big body (`body_r` 1.5 m): blows
  reach its edge, missiles within it strike it, never knocked down, its
  footprint padded by it; shields and the ranks behind do not stop its
  charge (`crush`); its crew shoots from its back while it fights.
- **Amok**: an `amok` row breaking runs amok (`u_amok`, routing): it veers
  at random each second (back from the edges), tramples every man of any
  unit, its own side's too, within its body and a metre (every 0.5 s a
  beast, an impact at 60 % momentum; friends count as friendly fire) and
  never rallies. **Calming** (the user's rule): once no unit of either side
  has been within `amok_r` (50 m) for `amok_calm` (20 s) it calms and its
  rider takes control (rallied at the rally threshold); any unit near
  resets the count. **Kill elephant** (`ORDER_KILL`, only an amok unit):
  its drivers kill every beast after `kill_delay` (5 s).
- HUD: "Kill elephant" in the bottom row while one of ours runs amok; cards
  read "Amok"; the soldier layers draw a camel and an elephant sprite on
  both paths; unit icons 10-12; the unit book lists the rows and a line of
  their beast facts. AI: docs/AI.md 19. Campaign: docs/CAMPAIGN.md rosters.
- Not modelled: fatigue (camels "tire slower") and arid ground (no such
  penalty exists).

### Missile cavalry and slingers (as built, 2026-10-09)

Data only (no sim change): rows of `sim/unit_types.gd` `LIGHT_MISSILE`
(lines "cav_missile", "sling"; base rows appended after `BEASTS`) with
faction variants in `LIGHT_MISSILE_TIERS`, derived like `TIERS` (tier 2:
`TIER_DELTA`, `TIER_PRICE` cav_missile 125 % / sling 120 %, the row's `add`
and `price_add`). Both are `CLS_MISSILE` with skirmish on by default; the
riders `mount` 1 (horse), drawn with the cavalry sprite; slingers drawn
with the archers' sprite, their stones with the arrow (any `m_arc` 1
missile draws as one). A new standard kind **Sling stones** (`AMMO` 9, a
hand cart carries 1,600) and a special kind **Lead bullets** on it.
Numbers chosen once, not tuned (yardsticks: shock cavalry, camel archers,
javelinmen, archers):

| | Light Horse (`cav_jav`) | Slingers (`slinger`) |
|---|---|---|
| Size / price | 60 / 480 (camel archers' price; shock cavalry 600) | 80 / 320 (archers 400 less the weak shot against armour) |
| Run / turn 90 deg | 8.6 m/s (shock cavalry 8.2) / 1.3 s (1.6) | 4.2 m/s (javelinmen's) |
| Att / def / armour / hp / morale | 24 / 22 / 4 / 130 / 620 (no lance, unarmoured, smaller horse) | 18 / 16 / 2 / 75 / 560 (archers' body, no armour) |
| Missile | javelins 40 m, 38 dmg, 50 ap, 5 a man, 3 s (javelinmen 42 / 60 / 6 / 2.8 s: thrown from a moving horse) | sling 150 m (bow 140), 28 dmg, 0 ap, 40 a man, 3 s (bow 30 / 25 ap / 4 s) |
| Other | mshield 25, woods 180 % (about the cavalry's), climb 24, needs Stables + Range 1 | loose order 1.6 x 1.8 m, lobbed over friends |

"Good against unarmoured" falls out of the damage rule (`damage - armour x
(100 - ap) %`): 25 a hit on armour 3 (arrows 28, but a stone every 3 s, not
4), 14 on the heavy swords' 14 (arrows 20). Lead bullets: a third of the
bag, 130 % damage, +20 ap, 85 % range (Range 2: Carthage, the Greeks).
Variants (tier 2; +3 missile damage unless said): Numidian Horse
(Carthage: +0.2 m/s run, quicker turn, +1 javelin, +10 % price), Tarentine
Horse (Greeks, Epirus, Syracuse: +10 mshield), Gallic Light Horse (+3 att,
+2 dmg), Iberian Light Horse (+2 def, +1 armour); Balearic Slingers
(Carthage: tighter spread, +10 %), Rhodian Slingers (Greeks: +2 missile
damage, +10 m range, +10 %), Iberian Slingers (+2 missile damage, +2 att). Campaign: docs/CAMPAIGN.md rosters.

- Not expressed: a damage bonus against armour 0-2 (no such field: low
  damage and no ap give it).
- Fixed with the general (2026-10-09): the riders' small charge (any
  mounted row with `charge` > 0 builds momentum and charges by the cavalry
  code path, `BattleSim.t_rider`; Light Horse `charge` 30, shock cavalry
  70, camels 45; camel archers have none); sling stones and lead bullets
  draw as small grey bullets (projectile kind 4, a third flag bit); armies
  of riders on horses or camels (light horse, camel archers) march at horse
  pace (`CState.max_mp`).

### The general (as built, 2026-10-09)

The command aura is the fear aura inverted: generic fields of any row
(`sim/unit_types.gd`), checked in the same once-a-second aura pass
(`BattleSim._update_auras`; the aura sources now include `cmd_r` rows, so
a battle without one runs no new code):

- `cmd_r` 40 m (box to box): friendly units within it (not his own) gain
  `cmd_mor` 5 morale a second, also fighting and under fire, up to what
  rest would bring them back to (the recovery cap); a routing friend
  within it (not amok) gains `cmd_rally` 40 a second more toward rallying,
  also with an enemy near. Several generals do not stack (the best).
  `u_led` (hashed) marks a unit inside this second.
- `cmd_loss` 120 / `cmd_loss_r` 250: when the general's unit routs or its
  last man is killed (once a battle, `u_cmdgone`, hashed), every other
  friendly unit on the field loses 120 morale at once, those within his
  `cmd_r` 250; the routs follow at the next morale update.
- `cmd_pct` 8: campaign auto-resolve, his army's strength +8 % while he
  has men (`CState.strength`).

Rows: one base row of its own line "general" (`UnitTypes.GENERAL`, after
the light missile rows) and faction variants at tier 1 (`GENERAL_TIERS`,
the variant mechanism of `LIGHT_MISSILE_TIERS`; `_derived` takes tier 1
with no `TIER_DELTA` and the base price). Numbers chosen once from Guard
Cavalry (cav3: 46 / 38 / 16 / 162 hp / 900 morale / charge 80, 60 men
for 1,260), not tuned:

| | General's Bodyguard (`general`) |
|---|---|
| Men / price | 30 / 1,200 (Guard Cavalry's price for half the men: the aura pays for the rest) |
| Att / def / armour / hp / morale | 44 / 40 / 16 / 160 / 950 (picked riders guarding one man; almost never breaks) |
| Charge / run / mass | 75 / 8.2 m/s / 420 (the wings' pace) |
| Shield / mshield | 25 / 20 (shields held over the general) |
| Campaign | `str_pct` 50 (his riders), `cmd_pct` 8 |

Variants (names short): Legate's Guard (Rome, +2 def), Sufet's Guard
(Carthage, +5 charge), Royal Hetairoi (Macedon, Epirus: +6 charge, +2
att), Strategos' Guard (Greeks, Syracuse: +5 mshield), Chieftain's Guard
(Iberians, Gauls: +4 damage, -2 def); and Bodyguard Cavalry (never
recruited: a campaign army's second general serves on as these, the same
riders with the `cmd_*` fields cleared). Layouts (`Scenarios.army_layout`,
`CBattle._layout`) put him in the row behind the centre. View: unit icon 15
(a standard: pole, crossbar, banner, a wreath on top), UI icon "general"
(the same) as a gold mark on his HUD card and on his battle-screen card,
the unit book's "Command aura" row and a line of his command facts; the
custom battle picker lists the generals (and, since this change, camels,
camel archers and elephants). Battle AI: docs/AI.md 20; campaign:
docs/CAMPAIGN.md "The general".

- Not modelled: a named general, his traits or death and succession in
  the campaign (his unit's men are what the outcome rows carry: a beaten
  army may lose him); the general in the settlement AI (`siege_ai.gd`
  uses him as any rider).

### War dogs (as built, 2026-10-09)

A handler unit carries a pack; the pack is a unit of its own that the sim
keeps with its handlers until released. Generic fields of any row
(`sim/unit_types.gd`): `pack_n` (dogs a man), `pack_type` (the pack's
row, from `pack_key`), `pack_r` (release range, box to box), `return_r` /
`return_t` (the return rule), `nobreak`, `scare_am` (the scare's armour
cut-off), `as_cav` (spears' vs_cav applies against it), `chase` (its
anchor runs on into its quarry); mount 4 (`MOUNT_DOG`: a man's small body
for missiles and footprint, its own sprite). Rows `UnitTypes.DOGS`
(appended after the general's: every other index unchanged). Numbers
chosen once (light infantry, archers, slingers, javelinmen the yardsticks),
not tuned:

| | War Dogs (`dog_handlers`, line "dogs") | War Dog Pack (`war_dogs`, line "dog_pack", never recruited) |
|---|---|---|
| Men / price | 16 handlers, 2 dogs each / 384 (slingers' 320 for the dogs, plus weak men) | 32 (16 x 2) / in the handlers' price |
| Att / def / armour / hp / morale | 20 / 18 / 2 / 75 / 520 (archers' body, a knife) | 40 / 22 / 0 / 45 / never breaks |
| Damage / reach / cooldown | 22 / 1.2 m / 1 s | 34 (31 on armour 3, 20 on armour 14) / 0.9 m / 0.8 s |
| Pace | light infantry's (1.6 / 4.4 m/s) | 2 / 9 m/s (faster than any rider) |
| Other | release range 80 m | scare 15 m on armour 4 or less, 4 morale/s; returns when no enemy within 30 m for 5 s; spears' +20 vs riders applies |

- **The pack unit is pre-created** (not grown mid-battle): at setup, after
  the scenario's units and the towers, one unit per handler unit of its
  `pack_type` with `count x pack_n` dogs (`BattleSim._dog_packs`); it
  starts in the kennel (`U_KENNEL` 4, at or above `U_DESTROYED` so every
  "on the field" test skips it; no men alive, its dogs `S_OFF` with their
  hp). `n` and `n_units` never change, so `snapshot()` / `restore()` and
  the lockstep work as before; the dog arrays (`u_pack`, `u_hand`,
  `u_kept`, `u_dogt`, `u_ret`) are hashed only when a battle has handlers
  (`dog_on`), so every other battle hashes as before.
- **Release** (`ORDER_RELEASE` 19: unit, target; `release_refusal`): the
  handlers ready, off the walls, dogs in the kennel, an enemy unit within
  `pack_r`. The dogs come out among the handlers' men (slots rebuilt from
  the dogs still alive), the pack attacks the target at the run. The
  handlers keep their own unit and orders.
- **Fighting**: the pack never routs (`nobreak`); with `chase` its anchor
  presses into the middle of its target and runs after it whatever it does
  (skirmishers falling back, routers: the unit-level pursuit of the melee
  fix, which against a scattered router stopped too short); with no live
  target it goes for the nearest enemy within `return_r` (unless it was
  given a move).
- **Return** (the elephants' calming rule reused, once a second): no live
  target and no enemy within `return_r` for `return_t` -> it runs back to
  its handlers and, within 3 m of them, is absorbed (the dogs alive go
  back in the kennel; a second release is possible). An order to the pack
  cancels a return. A pack whose handlers are dead, routed or on a wall
  fights on and then stands. The pack does not withdraw and does not hold
  the field (`_check_winner` ignores it).
- **Scare** (`scare_am` >= 0): the horse scare's fields strike any enemy
  unit with armour at most `scare_am` (light troops), horses or not; the
  camels' scare keeps `scare_am` -1 (horses only). Elephants (armour 10)
  ignore it, and the dogs' bites hardly scratch them. The elephants' fear
  aura strikes the pack as foot (`fear_foot`); the pack never breaks, so
  it changes nothing.
- View: the HUD's Release button (UI icon "release", key U; "Release: 32
  dogs", phone-compact "32 dogs") for selected handlers with dogs in the
  kennel; then a tap on an enemy unit releases (any other tap cancels);
  the handlers' card shows the dogs left ("out" while loose); the pack has
  its own card and marker only while loose ("With handlers" otherwise);
  unit icons 16 (handlers) / 17 (pack), soldier sprite 11 (a dog) on both
  render paths; unit book rows "Dogs a man", "Release range", "Returns,
  none within" and a line of the pack facts; the custom picker lists the
  handlers. The battle screen shows the pack's kills under the handlers
  (`CBattle.outcome_from_result` adds the pack's row, `pack_of`).
- Battle AI: docs/AI.md 21. Campaign: docs/CAMPAIGN.md rosters.
- Not modelled: dogs lost in a battle are not a campaign loss (the pack is
  made again from the handlers' men); the pack in a siege (the settlement
  AI never releases; a player may).

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

## 5. Networking

### Live battles: deterministic lockstep

Per-soldier state is too large to stream, so only orders are sent.

- Both clients run the same simulation from the same seed and apply the same
  orders on the same tick. Orders are scheduled a few ticks ahead (~200 ms).
- The sim uses integer / fixed-point maths only, its own seeded RNG, and fixed
  iteration order. No floats, no engine physics, no dictionary-order dependence.
- Clients exchange a state hash every second. On mismatch, the host sends a
  full snapshot and the other client resumes from it. The same path handles
  reconnects.
- Side benefits: tiny bandwidth, replays, and solo battles use the same code.
- Transport: WebSocket relay through the server.

### Live battles: as built (milestone 5, 2026-10-05)

Code: `sim/lockstep.gd` (deterministic, no networking), `sim/battle_sim.gd`
`snapshot()` / `restore()`, `game/net/coop_session.gd` (the client side of
the protocol), `game/net/live_room.gd` (the WebSocket), `game/coop_hud.gd`
(the co-op UI), `server/internal/server/rooms.go` (the relay). Protocol,
messages and limits: `docs/SERVER.md` section 17.

**Frames.** Lockstep time is counted in frames of 100 ms of wall time,
separate from sim ticks. A frame applies its inputs, then, unless paused,
adds the speed (quarter ticks: any q from 1 to 16, 0.25x to 4x, 4 = 1x) to an
accumulator and steps the sim once per 4. So pause and speed are lockstep
state, orders keep a wall-time delay whatever the speed, and frames (and
input messages) keep flowing while paused, which is what lets a resume vote
land.

**Inputs and marks.** Every input (a sim order, or a control input: pause /
speed request, answer, gift, admit) carries the frame it executes on, `f`.
A player's inputs go out in numbered messages `{n, k, o}` whose mark `k`
promises no more inputs for frames `<= k`; one goes out each frame with
`k = frame + delay` (delay 0 while alone, otherwise 2-12 frames from the
measured round trip: `ceil((srtt + 4 rttvar + 50 ms) / 100 ms)`, 3 to start;
200-300 ms on a normal connection). A frame runs only when every player
taking part has a mark at or past it, so all peers apply the same inputs on
the same frame, in (frame, player, message, index) order. Own messages are
applied locally when sent (no round trip added to one's own orders); the
relay's echo is dropped as a duplicate by message number, which also makes
any replay of the stream harmless. Late input (for a frame its sender had
already promised) is dropped by every peer alike.

**Command table.** `u_cmd` (who commands each unit), `u_away` (for whom a
unit is held) and `u_home` (who commands it by default: the campaign faction
of the unit if it is a human of the battle, other friendly units the lowest
human faction) live in the lockstep layer and are hashed with the sim. A sim
order counts only from the player commanding the unit at its frame; an army
withdrawal withdraws only the issuer's units; a player not taking part
orders nothing. Units of a human who is not there at the start are held for
them by the host; admitting that player gives them back (unless they chose
"Join, X keeps my army").

**Gifts** are inputs (`C_GIFT unit to`), valid only from the unit's
commander to a player taking part; gifting back is the same input. The
selected units' action row has "Gift to <ally>".

**Pause and speed by vote.** Requests and answers are inputs. A request
applies at once if only one player takes part; otherwise it waits until the
other player asks for the same thing (tapping Pause, or the same speed) or
taps Accept on the chip under the control (the requester's colour and
"Rome Pause?", "Rome proposes 2.5x"); Decline clears it; asking again withdraws it. Applied on the
same frame for everyone. A speed vote is the value the player releases the
speed slider at (any quarter step 1..16; the command rules refuse others). Solo battles keep immediate pause and speed; the
unit book and the controls page no longer pause a co-op battle.

**Joining.** "Fight" / "Fight together" on a battle with both armies opens
the room (lobby; the ally gets the Discord ping) and the battle view shows
both armies deployed behind the lobby panel. The ally's battle list shows
"Live now ... Join battle" (and "Join, X keeps my army"). The host starts
3 s after everyone is in, or alone with Start now. Joining a running battle
(or rejoining): a snapshot (sim + lockstep state + receipt state, about 86
KB at 4,000 soldiers) comes through the relay from a player who has the
battle, the joiner restores it, replays the stream after it, catches up by
stepping fast, says "ready", and the host admits it (an input) - from that
frame on the battle also waits for the joiner's input.

**Disconnects.** The sim waits for a missing player's input ("Waiting for
Carthage..." after 1 s). If that player is disconnected (or silent for 8 s)
and the wait reaches 10 s, the other gets "Carthage has disconnected:
Continue without Carthage / Wait". Continue asks the relay to drop them: a
stream event fixing the frame after their last mark from which they are not
awaited, and their units go to the remaining player, held for them. When
they come back they rejoin like a joiner and get their units back. If both
drop, the room is kept for 90 s (the last cached snapshot lets the first to
come back resume); after that it closes and the battle is an ordinary
pending battle again (a half-played battle is not persisted; it restarts
from the beginning). A page that comes back from the background resumes by
replay, or by snapshot when more than 10 s behind.

**Desync detection.** Every peer sends its lockstep hash every 10 frames
(tests: every frame); a mismatch is logged to telemetry (`coop_desync` with
both hashes and the frame) and on the server (`LIVE DESYNC`), shown briefly
("Out of step: resyncing"), and the non-host resyncs from a host snapshot.

**Result.** At the end every peer computes the result and sends its hash
(compared; `coop_result_mismatch` if different). Going back to the campaign
after the decision: the host uploads the outcome (the existing outbox with
retries; it tells the others first, so a player who becomes host later does
not upload again); others just leave. Leaving mid-battle: your units go to
the remaining player and the host role moves if you were host; the last
player leaving mid-battle uploads a forfeit as in a solo battle. Any seat
that took part may upload the result (the server records who took part).

**Hashed state.** Golden digests are unchanged: the sim is untouched apart
from `snapshot()` / `restore()`, and the lockstep state is hashed in
`Lockstep.state_hash()` (the sim's hash plus frame, pause, speed, votes, who
takes part, the command table), which solo play never uses. A solo battle
through the lockstep layer with one player is bit-for-bit the plain sim
(tested).

**Telemetry:** `coop_start`, `coop_net` (every 10 s: round trip, delay,
waits, messages, reconnects), `coop_wait` (waits of 0.5 s or more),
`coop_catchup`, `coop_snapshot` (sent / restored, bytes, ms),
`coop_resync`, `coop_desync`, `coop_drop`, `coop_continue`, `coop_admit`,
`coop_result`, `coop_result_mismatch`, `coop_leave` (with the session
stats).

### Custom battles and head-to-head (as built, October 2026)

Start screen > Custom battle (`game/custom/custom_battle.gd`, the setup and
its scenario `game/custom/custom_setup.gd`, server `docs/SERVER.md` section
18).

- **Setup** (plain JSON): the map (field: terrain kind, ground palette,
  woods %, seed; settlement: plan, site, level, walls, coast, seed and which
  side defends), the deployment time (none / 1 / 2 min), equal funds per
  side (none / 4,500 / 7,500 / 12,000 at campaign prices, Total War style),
  and two sides of 1-3 armies of up to 12 units each, picked from the whole
  roster (every line, tier and faction elite) with their prices. Each army
  is commanded by Player 1, Player 2 or the AI; each side has an AI skill
  (Easy / Average / Skilled) and personality used when the AI fights it.
  Templates: the sandbox's playable battles and test matchups (cav vs
  archers, pikes, artillery, woods, two settlements), each side one army.
- **Build.** Deterministic: armies one behind another per side, laid out as
  the campaign does (`Scenarios.army_layout`), side 1 the mirror image;
  settlements through `Scenarios.settlement`; `home` (who commands each
  unit) from the controllers. The sim's battle AI commands whole sides
  (`ai_sides`; per-side profile), so: a side with no player's army is the
  AI's; an "AI" army on a side that also has a player's army is commanded
  by that side's (lowest) player, as AI allies are in campaign co-op; the
  skill / personality is per side, not per army (decision kept for now:
  changing it means per-army AI in `sim/battle_ai.gd`). Not supported: two
  players on one side and one on the other (only two players anyway).
- **Solo:** Play solo starts at once (with the deployment phase); Player 2's
  armies count as the AI's (on Player 1's side: Player 1 commands them).
  The player may be on either side (side 2 deploys at the top; the view
  is not turned round).
- **Online:** Play online creates a custom battle room (setup, 6-character
  code, seat token); the friend types the code under Join. The lobby shows
  the code, both players (connected, ready), co-op or head-to-head. The host
  owns the setup (every change goes to the relay with compare-and-swap on
  its revision and comes back to both); Player 2 may only change the units
  of Player 2's armies. Any change clears both players' Ready; the host's
  Start battle needs every connected player ready at the current revision
  with the same scenario hash (else "the two devices build this battle
  differently"). Then the battle opens on both with the live session:
  deployment, battle, results as in campaign co-op. Leaving goes back to
  the custom screen.
- **Head-to-head in the lockstep layer.** Every player belongs to the side
  of the units they command by default. Gifts only to a player of the
  same side (the Gift button only offers an ally). Pause and speed are
  still votes of everyone taking part. A player who is away at the start,
  drops, leaves or is continued without: their units go to a player of
  their own side taking part (the one the server named, if they are on
  that side), otherwise the battle AI takes their side over
  (`sim.ai_sides`, hashed in `Lockstep.state_hash` with `ai_take`;
  mid-battle on a field map it advances from where the army stands rather
  than deploying again) and hands it back when that player is admitted
  again. Results are per side (the result panel: your army / enemy).
- **Telemetry:** `custom_room` (create / join with a setup summary),
  `custom_start`, `custom_battle` at the end (setup summary, winner, my
  side, online, per-side totals), `deploy_ready`, `battle_start`.

### Campaign: save-store server

- The server stores the campaign state as a versioned blob, accepts turn
  submissions, relays battle traffic, and sends notifications.
- Game rules run on the clients; the server does not validate them.
- Optimistic versioning: an upload based on a stale version is rejected and
  the client refetches.
- Notifications via Discord webhook: "your turn", "battle pending", "join now?".
- Identity: a shared campaign code plus a per-player token. No accounts.
- Hosting: a container on the Proxmox server behind HTTPS (required for
  WebSocket from a browser and for home-screen install).
- Stack: a single Go binary with SQLite (HTTP for campaign saves, WebSocket
  for the battle relay), run in a container behind the existing reverse proxy.

### Campaign server: as built (milestone 4, 2026-10-05)

Details in `docs/SERVER.md`. In short:

- Go 1.27 + SQLite (pure Go driver), one static binary that also serves the
  web build (brotli: the 39 MB wasm goes out as 7 MB) and the telemetry
  endpoint; Dockerfile, compose file and systemd unit for the Proxmox host.
- Every state version is kept with what produced it (the submissions, or a
  battle's outcome), so any version can be replayed, inspected or rolled
  back to.
- Identity: a 6-character join code (no lookalike characters, case-free)
  claims the ally's seat and stops working once both seats are taken; each
  device holds its own seat token; an 8-character device code (30 minutes)
  moves a seat to another device. Optional server-wide invite key.
- Turn flow: submit (replaceable, withdrawable); the last submitter's client
  resolves and uploads; another open client resolves after a few seconds if
  nobody did. One upload per version wins; the others adopt it.
- Turn timeout: the deadline starts at the turn's first submission; after it
  the waiting player may resolve without the absent one (who holds).
- Pending battles: leases (2 minutes, heartbeats) so only one device
  resolves a battle; with the ally's army in it the present player chooses
  Wait for ally (pinged) or Take command (told); "Ask to join now" is the
  live-battle invitation (the live battle itself is milestone 5). Results
  are kept on the device until the server confirms them.
- Live updates by long-poll (works through Caddy, in iOS Safari and in
  Godot's HTTPRequest); an authenticated WebSocket echo endpoint is where the
  milestone 5 relay will go.
- Determinism safety net: a client re-runs every version another device
  made from its parent and inputs and reports a different hash.
- Discord notifications per campaign (your turn, waiting for you, turn
  resolved with battles, take command, ping, deadline, won / lost), rate
  limited, deduplicated, never blocking.

## 6. Platforms and tooling

- Working model: design decisions are made in the main session; code
  generation and other delegated work run on Opus (see `CLAUDE.md`).

- Godot 4 (latest stable), GDScript, Compatibility renderer.
- Web export is the primary target; installable as a PWA on both phones.
- Native Android build is optional later. Native iOS is out of scope.
- **VERIFY:** early smoke test of a web export on the iPhone (performance,
  audio unlock, memory limits, behaviour when the tab is backgrounded).

## 7. Touch controls (to prototype first)

- Tap a unit or its banner card to select; unit cards along the bottom edge.
- Drag from a selected unit to draw the destination line: length sets width,
  direction sets facing.
- Tap an enemy to attack; double tap to run/charge.
- Two-finger pan and pinch zoom.
- Pause and speed controls. Solo: immediate. Co-op: by vote, as in Rome 2. A
  requested pause or speed change shows the requester's icon under that
  control and takes effect only when the other player agrees. Requests and
  agreements are lockstep orders, so the change lands on the same tick for both.
- Group buttons for "select all infantry / cavalry / missiles".

HUD as built (October 2026, after "the buttons are too large ... double
stack the cards"): the UI is laid out in logical pixels and
`game/ui_scale.gd` sets the window's logical size from the device: one
logical pixel is 0.88 CSS px on a touch screen (a 42 px button is ~37 CSS
px, ~7 mm on the user's phone) and 0.82 CSS px with a mouse (normal
desktop sizes on any monitor), times an S / M / L setting (0.85 / 1 / 1.18,
menu "UI size", saved in `user://settings.cfg`). CSS size and touch come
from `window.innerWidth` and `matchMedia("(pointer: coarse)")` on the web,
the screen scale and DisplayServer natively; stretch stays canvas_items, so
the battlefield is drawn at full window resolution. Never laid out smaller
than 800 x 400 logical. A 780 x 360 CSS phone is 886 x 409 logical; a
1920 x 1080 desktop 2341 x 1317; 3840 x 2160 at DPR 1 4682 x 2634.
Top bar (right): Withdraw army (tap twice), Units, Orders, Pause, speed,
Menu (the speed button shows the speed in force and opens a popover with a
labelled slider, 0.25x to 4x in quarter steps, ticks at 0.25 / 0.5 / 1 / 2 /
3 / 4 and the live value; solo it applies while dragging, + / - keys step
between the ticks); the readout (left) is one short line (fps, battle clock), tap for the
full readout below the bar (benchmarks open it). Bottom: one row with the
group buttons (left) and the selection's actions (right), then the unit
cards, wrapping into the fewest rows: 84-136 logical px wide, 34 tall;
from two rows on they become narrow (symbol and number only) if that saves
a row. 26 units: two rows on the phone, one on a desktop; 40 fit in three
rows on the phone. A card shows the symbol, short name and number, a
headcount bar with the count and a short state word (artillery: set-up /
refill state), ammunition at the bar's right (batteries: shots + reserve),
an orange edge under fire or charge, a white frame when selected, yellow
when routing, orange text wavering, grey when gone. Screenshots:
`docs/screenshots/hud_*.png`. Reordering the cards: drag a card (mouse: a plain
drag; touch: hold it still 0.35 s until it lifts, bigger and brighter with
a shadow and a gold rim, then drag; a quick touch drag does nothing) and
drop it between two cards (a ghost follows the pointer, a gold bar marks
the slot); a long press released without moving opens the unit book as
before (`game/drag_reorder.gd`, shared with the campaign army card). The
order is the strip's own view mapping (display position -> sim unit
index; the sim's unit indices never change, nothing reaches the sim or
lockstep: per player, per battle, co-op peers may differ), kept for the
whole battle (book, controls page, pause); All / Inf / Missile / Cav
select in that order, so the first card of the group becomes the primary
unit. Screenshot (phone, mid-drag): `docs/screenshots/reorder_phone.png`. Testing aids: `--ui-dpr=X --ui-touch=0/1
--ui-size=S|M|L` emulate a device, `--shot=file.png` saves the window,
`--menu-tests`, `--refill=U`.

Start menu: the three battles, then Terrain, Replay, Unit book, UI size,
Fullscreen and a folded "Tests and benchmarks" section with the other 16.

Built in milestone 2: group buttons All / Inf / Missile / Cav and a "+ Add"
toggle (taps on cards or units add to / remove from the selection; Shift on
desktop). A selected group moves together on a ground tap, keeping relative
positions and wheeling to face the direction of travel; a drawn line lines the
group up along it, left to right in their current order, each unit's frontage
in proportion to its soldiers, 2 m apart. Action buttons for the selection:
Run, Halt, Fire (at will / hold, missile troops), Skirmish (on / off), Withdraw;
"Withdraw army" asks for a second tap within 3 s. Tapping an enemy with
missile troops selected orders them to shoot it. Unit cards show ammunition.
The selected missile unit shows its range circle and current target line;
unit markers show a class sign, an orange ring under missile fire, a red
flash when charged, a chevron for charging cavalry, a bar when braced, and an
arrow when withdrawing. All orders, including the new ones, are predicted by
the view through the sim's own order-rule function while paused.

Artillery controls: batteries sit under the **Missile** group button (they
shoot, take Fire orders and stand behind the line; a sixth group button
would crowd the bar on a phone). A **Deploy: on / off** action button
appears when batteries are selected (set up to shoot / pack up and stay
packed); Run and Skirmish are hidden for a battery alone. Tapping an enemy
orders "shoot it"; tapping ground moves (it packs up first). The battery card
reads e.g. "Bolts 2 16/16 / eng 4/4 28 shots / Ready Steady" (Packed,
Moving, Set up 40%, Packing 40%). The selected battery shows its firing arc
as a sector from minimum to maximum range, both range circles faintly, and
its current target; its marker has a ring that fills while it sets up. The
Orders overlay adds "PACKED UP" and "HOLD FIRE" labels; the paused preview
covers the Deploy order like every other. Engines are extra instances of the
soldier MultiMesh (no extra draw call); bolts (long, flat) and stones (big,
round, swelling at the top of their arc) go through the projectile shader;
stone impacts leave a 1.5 s dust ring and furrow drawn by the overlay from a
small view-only ring buffer in the sim (not state). Unit book pages for both
types show an Artillery stat section and derived tags.

Terrain controls: the menu's "Terrain:" button cycles the ground for the
three playable battles (random from the seed, flat, rolling, ridge, valley,
hill, slope; tests keep their own), "Replay (seed N)" restarts the last
battle with the same seed and ground, and `?terrain=ridge&seed=N` /
`--terrain= --seed=` do the same from the URL / command line. The readout
shows the terrain kind and seed. The unit book's last page, "Terrain",
explains the rules with the sim's numbers; unit pages carry terrain tags
derived from the data (climb rate, range per height, flat weapons blocked
by crests, charge up / downhill, pike wall on steep ground). Testing aids:
`--force-terrain=K` (any scenario), `--attack=U:T`.

Unit symbols and unit book: every unit type has a symbol (drawn with canvas
primitives in `game/unit_icons.gd`) used for the field markers (disc in the
side colour, yellow when routing) and on the unit cards. The unit book
(`game/unit_book.gd`, from the menu and the "Units" button in battle, which
pauses solo play and restores the previous pause state on close) shows one
page per type via `game/unit_entry.gd`, a self-contained control taking a type
id, meant to be reused as the campaign recruitment card. Stats are read from
the sim's unit type data, shown as numbers in metres / m/s / seconds plus bars
scaled to the best value among all types; special-rule tags are derived from
the data; only the role, description and good / countered-by prose is
hand-written (display-only fields in `sim/unit_types.gd`, never read by the
sim). Long press (or right click) on a unit card opens its page without
selecting or ordering anything.

### Controls additions (2026-10-05, as built)

- All inputs are listed in one table, `game/controls.gd` (action, section,
  touch, mouse, default keys); the Controls page (main menu, battle "Keys",
  campaign Menu, F1) renders it, and the battle and campaign keyboard
  handling read their keys from it. No rebinding yet.
- Shift / Ctrl / Cmd + click adds to the selection on the field and on
  cards. It did not work before because cards ignored modifiers and the field
  read the key state; modifiers are now read from the mouse event itself.
- Symbol markers are hit targets first (radius 2.3x the marker on touch,
  1.7x with a mouse), so a marker floating over a neighbouring unit selects
  its own unit; long press (touch) or right click on a unit opens its book page.
- "None" button with the group buttons deselects; Esc too.
- Keys: Space / P pause, + / - speed, 1-4 and Ctrl+A group selects, R run,
  H halt, F fire, K skirmish, Shift+D deploy, Y refill, O orders overlay,
  W A S D / arrows pan, Page Up / Down zoom, B book, F3 readout, F11 fullscreen.
- Mouse drag on empty ground with nothing selected (or with Shift) draws a
  selection box; pan with right / middle drag or keys (left-drag pan with
  nothing selected is gone on desktop; touch still pans with one finger).
- Group move: three fingers on the screen with units selected; after 24 px
  of movement or 8 degrees of twist a ghost of every unit's destination
  (real frontage, depth and facing) follows the touches' centre and twist;
  lifting a finger places the group (move orders keeping each unit's
  frontage, relative position and facing), a fourth finger cancels, small
  movements issue nothing. Desktop: Alt + left drag (or hold G and drag, for
  systems where Alt-drag moves windows); wheel or Q / E turns 15 degrees;
  right click or Esc cancels. Works paused (the usual order preview).
  Telemetry counters three_finger_move, alt_drag_move, group_rotate,
  group_rotate_placed, group_move_cancelled.

## 8. Art

- Placeholder top-down sprites, tinted per faction, until the game is proven fun.
- Per unit type: idle, walk, attack, die. One sprite sheet each.

Ground: a topographic-map look from one shader (see "Terrain height: as
built"): thin 2 m contours, soft hill shading from the upper left, a subtle
tint by height, the faint 50 m grid. Screenshots in `docs/screenshots/`.

Milestone 2 placeholder: one procedurally drawn atlas with nine top-down
greyscale sprites (sword and shield, spear, long pike, bow, javelins, horse
and rider, gun crew, bolt thrower, stone thrower; cells 6 x 2.5 m), tinted per side and state in the shader; each sprite has its own
quad size so pikes and horses are long. Still one MultiMesh draw call for all
soldiers, plus one for missiles in flight.

Soldier rendering has two paths with identical output (`game/soldier_layer.gd`,
`game/soldiers.gdshaderinc`, `game/projectiles.gdshaderinc`):

- **Texture (default, cheapest):** per tick the sim's int arrays are copied
  as raw bytes into an RGBA8 data texture (one texel per int32); the vertex
  shader fetches and decodes them per instance (texelFetch) and interpolates
  between ticks. About 0.23 ms a tick at 4,000 men natively.
- **CPU-fed (compatible fallback):** the same arrays are converted to floats
  and interleaved into the MultiMesh buffer, one bulk upload per tick
  (positions, previous positions, facing, state through the instance
  transform, read back as MODEL_MATRIX with `skip_vertex_transform`; sprite
  and side / selected / under fire in INSTANCE_CUSTOM, filled per unit run);
  missiles are re-uploaded only when one is fired or lands, and only the
  slots in use. No texture fetch, uniform array or int uniform in the vertex
  stage. About 0.5 ms a tick at 4,000 men natively.

Chrome on an Adreno 650 tablet (ANGLE on GLES) drew nothing from the texture
path (Firefox on the same tablet did). A battle's self-check renders only the
soldier layers around the biggest unit offscreen ~30 frames in (telemetry
`soldier_probe` with `drawn`, `men`, `path`); zero pixels with men alive on
the texture path switches to the CPU-fed path at once, probes again, and
remembers it in `user://settings.cfg [video] soldiers=cpu` for later
battles. The home menu's "Soldiers: auto / compatible" button sets the same
preference; `--soldiers=cpu|gpu` (or `?soldiers=` in the URL) forces a path
for testing and `--soldier-probe-fail` fakes a failing texture path.

Icons (2026-10-09, phase 1): every UI icon is drawn in code by
`game/ui_icons.gd` (80 icons, no asset files), one line style matching the
unit glyphs: round-capped strokes 0.16 of the half-size, the glyph filling
90% of its cell, one colour. An icon is a `VecIcon` (a Texture2D drawing
vector strokes through the RenderingServer), so it is crisp at any UI scale,
sits in a Button's `icon` and takes the button's icon colour per state
(Kit sets them to the text colour; disabled is an opaque grey). Size follows
the text (13 px text: 18 px icon, 15: 20, 17: 22). Kit helpers:
`icon_button(text, icon, ...)`, `set_icon`, `tint_icon`, `icon_label`,
`label_icon` (a content margin plus a draw hook: the label keeps its name,
text and wrapping) and `section(text, icon)`. Text stays beside the icon
everywhere except Undo, Deselect and Menu (bare, with tooltips). The top bar
reads faction, season icon + year, treasury, income; Deselect / Undo / End
turn are one bottom-right row. Gallery: `tests/icon_gallery.gd` writes
`docs/screenshots/icons.png`; before / after: `docs/screenshots/icons_*_phone_*.png`.

## 9. Milestones

1. **Battle sandbox.** Deterministic per-soldier sim, MultiMesh rendering,
   touch controls, infantry melee, morale. Benchmark on both phones.
2. **Full battle mechanics.** Pikes, missiles, cavalry, retreat, battle AI.
   Done: pike walls and multi-rank pikes, archers and javelins with
   projectiles, cavalry charges and knockdowns, bracing, withdrawal and the
   per-unit battle result, the battle AI, multi-select and group moves,
   mixed-army and test scenarios, balance matchups (`tests/matchups.gd`).
   Deferred: horse archers, fatigue, and line-of-sight past friends for
   javelins at soldier level (it is checked unit to unit).
   Then terrain height (see "Terrain height: as built"); vegetation and map
   generation from the campaign map come with milestone 3.
   Then (battle depth): artillery (bolt and stone throwers) as above.
3. **Minimal campaign.** Small map, armies, recruitment, buildings, economy,
   pending battles, auto-resolve, campaign AI, diplomacy states.
4. **Async backend.** Save store, turn submission, Discord pings, hosted on Proxmox.
5. **Live co-op battles.** Lockstep over the relay, unit gifting, reinforcements,
   desync recovery. Built 2026-10-05 (section 5 "Live battles: as built");
   reinforcements arriving from the map edge are still to do.
   Battle maps with character (woods, settlement maps with walls and gates,
   ground palettes, stronger shading): built October 2026 (section 4).
6. **Depth.** Siege equipment (ladders, towers), more factions and units, tech, enemy-control mode.

## 10. Main risks

1. Per-soldier sim performance in a phone browser.
2. Touch controls for real-time tactics.
3. Battle AI good enough to be worth fighting.
4. Keeping the sim deterministic as features are added.
5. Scope creep in the campaign layer.

## 11. Future themes: the American West (not started)

Once the Rome game is where we want it, the same engine should carry a
second, fantastical American West campaign with hammed-up factions. It is a
content pack over the existing engine, added non-destructively: nothing in
the Rome data changes, and the shared sim, campaign rules, lockstep, server
and tooling are untouched except for the new mechanics below. It is also the
stress test for the sprite pipeline (section 8).

**Factions (sketch).** Many distinct tribes (Comanche as the best cavalry,
Iroquois woodland infantry, Apache raiders who win by attrition); colonists
as a militia spectrum (Crockett-style frontiersmen with rifles and cover,
cheap brittle farmers, mounted rangers, Quakers as a non-combat campaign
bonus); Mexican militia and lancers; French trappers (woods, rivers, trade
with tribes); the British Empire as the "Roman" line-and-artillery faction;
Spanish horses and mercenaries as a recruitable market; Chinese medicine
men (healing, morale), explosives (sapper gear using the equipment objects)
and the railroad. Faction character comes from stat tables and per-faction
AI profiles, the way skill profiles work today.

**What carries over.** Campaign core (regions, armies, async turns,
proposals, gifting, sieges as a fort holding out); the battle sim
(formations, morale, occupancy grid, equipment objects, artillery); siege
structure (a stockade fort is a walls-1 city, blockhouses are towers with a
cannon); ammunition types and the ammunition wagon (ball, buckshot, shell,
dynamite, wagon trains); animal roles (mustang vs draft horse is the
camel/horse split with different numbers); AI profiles.

**New mechanics.**
1. Firearms: a volley mode on the missile code (long reload, high damage,
   morale shock, smoke); rifles slow and accurate, pistols a cavalry melee
   bonus.
2. Cover and line of sight: terrain that reduces hits and blocks sight
   (woods, rocks, buildings), reusing the wall shelter knob; makes ambush and
   "fighting from the trees" real tactics.
3. A railroad graph laid over the region map: buildable, raidable, a
   movement and supply network.

**Preparation while building Rome.** Keep unit types, ammunition, buildings,
animals and faction AI knobs as data tables rather than code branches, so a
theme is a data folder plus its art. Smaller units (companies of 30 to 80)
mean every balance number is re-fitted; the fit-the-formula tooling from the
siege work is what calibrates a new theme. Victory conditions for tribes
(land and buffalo, not cities) are the open design problem.
