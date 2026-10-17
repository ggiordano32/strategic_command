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
- Relief shading (view only, 2026-10-10): the map bakes once an elevation
  field from the grid (ridge 2, hill 1, else 0), blurs it over about 4 cells,
  lights it from the north-west and draws it as one bilinear texture over the
  land, under borders, rivers, roads and armies; slopes facing the light are
  pale and warm, the others dark. The hill hatch marks stay, lighter. No state
  or rules change.
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
| Javelinmen | 28 | 22 | 3 | 20% / 35% | 28 | 1.2 | 80 | 4.2 | 40 m, 6 javelins (was 4), 2.8 s reload, through 15% of a missile shield (`m_spen`, 2026-10-09) |
| Shock cavalry | 36 | 28 | 10 | 20% / 15% | 32 | 1.6 | 150 | 8.2 | mass 400, charge 70, turns 90 deg in 1.6 s; arrows x1.2, 9% of hits down the horse |
| Bolt throwers (crew) | 14 | 14 | 3 | 0 / 0 | 22 | 1.0 | 75 | 0.8 packed | 4 engines x 4 crew, cost 25/crew |
| Stone throwers (crew) | 14 | 14 | 3 | 0 / 0 | 22 | 1.0 | 75 | 0.7 packed | 3 engines x 6 crew, cost 30/crew |

**Flank and rear** are judged by where the attacker stands relative to the
defending *unit* (its anchor and facing: ahead of its front line, behind its
rear rank, or alongside / beyond the end of the line; `BattleSim._zone`), not
by the angle between two duellists or how the struck man is turned. One
function decides it for every melee blow: the shield (frontal blows only),
the to-hit bonus (+35 flank, +50 rear; +25 / +40 until the field
rebalance of 2026-10-09, when the base to-hit `BASE_HIT` also went 35 -> 40), the morale and disorder hit and the
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

**Wrap at the anchor level** (field rebalance, 2026-10-09). With men capped
to 1.5 m ahead / 3 m aside of their places, a wide line's outer files stood
idle beyond a narrow enemy's flank (three units on a 10-man pike remnant
had 3 men in reach). Now, while a unit attacks and is engaged (`wrap_t`),
the place of each front-rank man whose file stands out beyond the
target's bounding box (plus `WRAP_GAP` 1 m) by e curls forward by f =
min(e, the target's depth + 1 m) and in by f (`BattleSim._curl`): the line
bends into an L round the target's flank and the caps apply to the curled
place, so those men fight it from the flank (+35 to hit, no shield). No
state: computed each tick from the target's bounding box.

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
| Fright per hit | 22 (15 until 2026-10-09) + pins 0.8 s | 60 + pins 0.8 s |

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
  goes on as plain men and may take them up again: until 2026-10-10 it
  stood by them, its men held at their places round engines that no longer
  rolled, so a rallied battery ordered on never moved again; the same for
  a battery whose engines are all wrecked; settlement maps only, the field
  keeps the old rule until the field pass re-records its battles). Tower
  engines stay fixed. A shot in flight keeps the type it was fired with
  (`pr_ty`). The battle AI's missile units out of ammunition take up their
  own side's abandoned engines within 60 m (AI.md 17); AI batteries never
  drop. View: a grey marker with the engine's symbol and a dashed ring over
  free engines, "TAKE UP THE BOLT / STONE THROWERS" in the order preview,
  "on bolts" on the card, the engines drawn in the colours of the unit
  working them. Tests: determinism `--only=engines`, lockstep siege (B's
  battery leaves its engines, A's archers take them up and leave them,
  snapshots on the way), input_test (Drop, tap to take up).
- *Light artillery* (built 2026-10-09, STATUS 4f.3; not tuned). Two plain
  rows (`UnitTypes.LIGHT_ART`, appended after the war dogs), no new sim
  code. **Scorpions** (`scorpions`, line "light_art", CLS_ART): a battery
  of six small bolt engines with two crew each (12 men, `crew_min` 1),
  4 m apart; the crews carry them, so the packed pace is the row's `walk`
  (1.5 m/s, archers 1.5, Bolt Throwers 0.8) and `deploy` 15 (1.5 s to set
  up, under a second to pack); 160 m (70 % of Bolt Throwers' 230), 90
  damage (75 % of 120; tuned 2026-10-09 from 72, which never killed a
  pikeman outright: a full load on a 120-pike block 12.5 -> 17.5 %) at 70 ap, a bolt goes through at most 2 men
  (`m_pierce` 2; heavy bolts' 140 % is still 2), 5 s a bolt, 8 bolts an
  engine plus 8 in the baggage, engines of 60 hp (Bolt Throwers 160),
  396 a unit (Archers and Bolt Throwers both cost 400). Engines as
  equipment apply unchanged: the crew drops them, any foot takes them up
  and walks them at the row's pace. Heavy bolts ride on their bolts
  (`AMMO_AVAIL`). A new generic field `carried` (1: the crews carry the
  engines) is read only by the AI and the campaign: the siege AI brings
  them up with the assault (AI.md 15) and they never count as a gate
  breaker; an army with them marches at the foot's pace (`CState.max_mp`).
  **Gastraphetes** (`gastraphetes`, line "belly_bow", CLS_MISSILE; Greeks
  and Syracuse, Range 2): 80 belly-bowmen, archers' body, 160 m (archers
  140), 48 damage at 50 ap (an arrow 30 / 25, a scorpion bolt 72 / 70),
  10 s a shot (2.5 x the bow), 20 shots, flat (`m_arc` 0, `m_apex` 3: a
  clear line past friends and over the ground, like javelins and bolts),
  no skirmish, arrows as their kind (fire arrows ride on them, a wagon
  refills them; drawn as arrows), 400 a unit. View: unit icons 18 (a
  small engine on a tripod) and 19 (a bow on a stock with the belly rest);
  the scorpions draw with the bolt thrower's engine sprite (no sprite of
  their own yet). Test: determinism `--only=light_art`.
- *Kills per unit* (`u_kills`, 2026-10-09, hashed): enemies killed by the
  unit's men in melee, by charge impacts, missiles, its engines (credited
  to the unit working them when the shot was fired) and a tower's engine
  (the tower unit); friendly fire is counted apart (`stat_ff`, not hashed).
  `result()` rows carry `"kills"`; a fought campaign battle's outcome rows
  too (an optional key the rules ignore), shown on the battle screen's
  cards.
- *Fright.* Each shot that strikes a unit adds its fear (bolt 22, tuned
  2026-10-09 from 15; scorpions 15, from 8; stone 60, cap 200) to
  `u_fright`, which decays 1 per tick and counts against morale
  only for the rout check and the displayed state: a stone tips a wavering
  unit over but does not break a steady one; deaths still do the real work.
- *Pinning* (field rebalance, 2026-10-09, after "bolt throwers feel almost
  useless in the field"): a unit an artillery shot strikes goes to ground
  for `PIN_TICKS` (0.8 s, from `u_shelled_t`): its anchor does not advance.
  Only walking units on field maps (a charge or a rush at the run goes
  through; units fighting, withdrawing or charging are not held; wall and
  tower engines in sieges do not pin). Heavy 100 walking 200 m at a bolt
  battery closes in 183 s instead of 157 s (scorpions 180 s), losing 12
  men (`matchups --only=yard`).
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
not recover. Flank and rear attacks do their work through kills: +35 / +50 to
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

**Battlefield look (2026-10-10, view only; the overworld's relief as the model).**
Ground: the height texture's A channel now holds the grade (rise / run, 0 to
0.8) and a thin lit crest line along ridges goes into the shade; the shader
adds low-frequency colour patches (hash noise, 58 m / 21 m / 3 m, lusher or
drier and stonier by palette: `lush` / `dry` / `rock` / `sand` in
`ground_palette.gd`) so flat fields are not one colour, slope darkening,
bare rock above grade 0.2 to 0.5 and, on maps with 14 m or more of relief,
above 80% of the height range (the notional tree line), less in woods.
Water (sea and river) has depth tint, two ripple layers and glints moving
with the shader's `TIME`; the ford's pale shallows have a current; wet sand
(a third channel of the sea / river textures) lies 2 to 4 m along the banks.
Vegetation: woods keep the sim's placement; inside them size (saplings, old
giants), species (stands of 8 x 8 cells lean to one kind, pines on high
ground) and edge bushes vary by hash. Non-gameplay cover, at most
`EXTRA_CAP` = 1900 glyphs in all, in two MultiMeshes on the trees' shader
(atlas kinds 4 tuft, 5 reeds, 6 willow, 7 bush): tufts, scrub (dry slopes)
and bushes in clumps on clear ground, reeds on the banks and the ford's
edges, willows up the banks, and orchard rows beyond a settlement's walls;
the low cover is drawn under the soldiers (z_index -1; the ground layer is
-2) and does not fade, the willows and orchards with the trees over them.
Settlement surroundings (`city_draw.gd` `plan_surround`, laid out once from
the map hash on the sim's veg grid): a dirt track from each outer gate to
the map edge (meandering), and ploughed, crop, stubble and fallow patches
and orchards 26 to 120 m beyond the walls, never on streets, the ditch,
woods, water, the deployment zones, the attackers' approach (45 m round the
approach point), within 16 m of siege equipment, on slopes over 2.2 m
across or on a track; drawn as ground decals by `terrain_layer.gd`. Houses
have a contact and a long shadow, a ridge with a lit edge and tile courses;
walls and towers a dark footing line; gates posts, a lintel, planks and
studs; the plaza worn patches and joints. The preview of a settlement
(`city_preview.gd`) shares the houses, walls and gates and has the colour
patches. Measured (desktop, RTX 3070): +0.0 to +0.3 ms a frame; bakes: ground
100-160 ms, trees 70-80 ms.


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
the wall" (view) sends a unit to the stretch within 60 m nearest the
nearest enemy (`man_wall_target`); "Come down" to the foot of its nearer
stair (`wall_inside`). Attackers climb by ladders from outside ("Siege
equipment and wall towers") and, since the 2026-10-15 stairs fix (it was
"Attackers cannot use the stairs once inside"), by the inner stairs once
inside: an attacking foot or missile unit on the ground whose ground
(gates as they are) reaches a foot of the stretch's stairs (`att_stairs`)
takes a move onto the wall as defenders do (order rule, so preview and
peers agree; "Man the wall" too). Inside the walls (its anchor's piece
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


### Battle kit walls, towers and gates (as built, Level 1 phase 1, 2026-10-14)

Look: variant A (grounded painterly) by the user's choice; B (tabletop diorama) stays an option
for a later `[video] battle_look` setting, so `game/battlekit.gdshader` keeps `rim`, `outline`,
`sat`, `contrast`, `amb`, `key` as uniforms (A is the default; B's values are in the shader header).

The settlement's walls, towers and gates on the battle map are Blender kit pieces
(`tools/battlekit/build.py`: `wall_<t>_<pp>` for the sim's five (thickness, parapet) pairs, `pal_<t>`,
`tower_round` / `tower_sq` / `tower_timber`, `gate_c|o|b`, `pgate_c|o|b`; `bastion` is packed but unused:
the map generator has no star trace yet). `tools/battlekit/pack.py` crops and packs them into
`assets/battlekit/atlas_albedo.png` + `atlas_nrm.png` (8 px/m; normal xy, height, mask class) and
the 4 px/m pre-lit `atlas_low.png`, and writes `game/battlekit_atlas.gd` (anchors, rects).
`game/battlekit.gd` (child of `CityLayer`) turns `sim.map_info["city"]` into instances: walls tiled
along each polygon edge (x scaled to the edge, the variant picked so the walkway sits where men stand),
a gate piece over the wall at each gate (state from `sim.g_state`, a flash while struck), towers
from the sim's tower list (the gate towers are in it). High: one MultiMesh and `battlekit.gdshader`
(NW key, normal turned by the instance angle, culture palette by the mask class: Latin, Greek, Punic,
Celtic, Spanish colonial, native). Low / CPU path: the same instances through `draw_texture_rect_region`
from the pre-lit atlas, no shader, no shadow layer. `game/battlekit_shadow.gd` bakes a cast shadow + AO
from the pieces' heights (0.5 m grid, one multiplied sprite), re-baking only the window round a gate
that breaks. Stairs and banners are drawn above the kit (`CityDraw.draw_over`); the campaign's city
preview keeps the old polygon drawing (`draw_static` without `kit`). Testing aids: `--no-kit` (old
look), `--no-kit-shadow`, `--kit-culture=N`, `--city-info`. The crenellated round tower is the
default; the roofed round tower (read as a ball at game scale) is not used. View only.

### Battle look: diorama default, kit houses / trees / rocks, splatted ground (as built, Level 1 phases 2-6, 2026-10-14)

`[video] battle_look = diorama | painterly` in user://settings.cfg (default **diorama**; `--battle-look=` for
a session; a "Battle look" button on the settings row in `game/main.gd`; read at battle start; `game/battle_look.gd`
holds the values: diorama amb 0.50, key 0.88, rim 0.22, outline 0.55, sat 1.22, contrast 1.12; painterly 0.66 /
0.55 / 0.05 / 0.24 / 0.86 / 1.04). All view only.

- **Houses and props** (`battlekit.gd` `_build_houses`): every `lay["buildings"]` footprint (rect, quad or round) gets a
  kit piece scaled and turned to it (long axis along the footprint's long side, a hash flips it 180 degrees): gable /
  hip / L / long houses by aspect and size, `hut_round` / `hut_thatch` for round shapes and Celtic / native styles,
  `temple` (Latin, Greek, Punic) / `church` (Spanish colonial) / `longhouse` for the shrine, `longhouse` for
  barracks, stables, range, a gable_l workshop, a grid of `stall` over a market; a `well` over the agora's fountain and
  four stalls at its corners. Culture palettes through the mask classes (`i_cul` per instance; `--kit-culture=N`
  forces one). The old polygon houses are no longer drawn on the battle map (`draw_static` with `kit`).
- **Streets** (`city_streets.gd`, under the kit): one 0.5 m texture painted from the sim's own `lay["streets"]` segments (gate to plaza, main streets, lanes; width from the segment) and the agora square, plus the lanes between blocks (free ground within 3 m of any footprint); cobbles with a curb for Latin / Greek / Punic / colonial towns, packed dirt for Celtic / native. Houses are chosen by footprint aspect (hip, gable s / m / l, longhouse) so nothing is squashed; markets are filled with scaled stalls. build.py's `house()` bug (ridge along y swapped the roof against the walls) avoided by making the long side x. Hill shade is softer in the diorama look (no dark band).
- **Rocks and cliffs**: a second `BattleKit` (`setup_land`) under `land_layer.gd`: one rock piece per boulder
  (a / b / c by radius), cliff pieces laid along each cliff's brow every 6.5 m, the piece's lower side to the downhill
  normal. `--no-kit` keeps the drawn ones.
- **Trees** (`tree_layer.gd`, `trees_kit.gdshader`): the woods and orchards keep their positions, clustering, fading over
  men and occupancy texture; each instance is now a kit tree (broadleaf a / b / c, pine a / b, bush, palm a / b)
  by kind and shade, lit by the normal atlas, tinted toward the palette's tree colours, its cast shadow sampled from
  its own silhouette shifted south-east; palms replace broadleaf / pine / olive when `CData.pack == "west"` (or
  `--tropic`). The ground cover under the men (tufts, reeds) keeps the old glyph shader.
- **Shadow and AO**: houses, towers, walls, gates, rocks and cliffs are instances of the same `BattleKit`, so
  `battlekit_shadow.gd` bakes them all (0.5 m cells in a settlement, 1 m for the land kit via `shadow_cell`).
  Trees do not enter the bake (40,000 would be too slow): the tree shader draws its own shadow.
- **Splatted ground** (`terrain.gdshader`, `terrain_layer.gd` `_splat`, `tools/battlekit/pack_ground.py`): six 256 px
  tiles in `assets/battlekit/ground/` (grass, dry, dirt, rock, sand, plough; 64 m a tile, mipmaps made at load): grass
  or dry grass modulates the palette colour; dirt for settlement ground, streets and plazas; plough on fields; rock where
  the existing slope / height rule says; sand on wet ground; contours and the 50 m grid fade back. At most 2-4 tiles per
  pixel. Graphics Low: no tiles (the flat ground as before).
- **Board** (`board_layer.gd`, diorama only): a wooden table 900 m beyond the field and a 4 m bevelled board edge
  lit from the north-west with a soft shadow; **light depth of field** (`battle_dof.gd`, High only, diorama only): the
  outer part of the screen blurred a little, under the HUD. `--no-board`, `--no-dof`, `--no-splat`, `--no-kit` test
  switches.
- **Low / CPU path**: houses, rocks and cliffs draw from the pre-lit `atlas_low.png` (roof palette tint by modulate), the
  trees from the same low atlas in `trees_kit.gdshader` (no normals, own shadow), no baked shadow, no splat, no DoF.
- Atlas now 1024 x 1024 with 47 pieces (`pack.py`; frames rendered with `build.py --ppm 8`): about 4 + 4 MB albedo /
  normal, 1 MB low, ground tiles about 2 MB with mipmaps.

### Battle look: relief, cliff faces, fields, Punic roofs, board (as built, 2026-10-14, second pass)

- **Ground relief** (`terrain_layer.gd`, `terrain.gdshader`): the dark ring round hills was the valley darkening
  (ground lower than the 24 m round it, so every hill foot got a band, plus the grade darkening): it is off in the
  diorama look (`valley_max` 0, 0.07 painterly). The hill shade is a clearer NW hillshade from the 2 m height field
  (diorama relief exaggeration 5.5, shade 0.95; painterly 4.2 / 0.8, softer and realistic); shaded slopes darken
  less than lit ones brighten. Diorama only (`terrace` uniform): stepped height bands on the 2 m contour lattice (a
  band's own elevation tint, a touch lighter each step, a lit or shaded riser at each edge by the hill shade),
  and a slope tone (steep grass turns to earth before it turns to rock). Bands fade where they crowd (zoomed out).
- **Cliffs** (`land_layer.gd`): one continuous face along the cliff polyline, corner-cut (Chaikin x2) so curves stay
  curved: lit brow line, rock tile (the ground `rock.png`) mapped along the length, darker toward the foot, strata
  courses, ribs, a talus gradient with fallen stones, soft drop shadow; drawn with `draw_primitive` quads (no
  triangulation). Rocks stay kit pieces; `battlekit.gd` `setup_land` no longer places `cliff_m`. `--land-info` prints
  each cliff's start.
- **Fields** (`city_draw.gd` `draw_surround`): furrows, rows and edges follow the field's long axis; plough = ridge and
  furrow, crop = shaded green rows, stubble = pale dashes, fallow = weeds; a headland and a hedge of round bushes or a
  post-and-rail fence round every field (drawn, not kit pieces). All of a field is batched into a few
  `draw_multiline_colors` calls and one mesh (single draw calls cost 5 ms a frame on bench_4000_city).
- **Punic houses**: `house_flat_s` / `house_flat_m` in `build.py` (plaster block, parapet, earth roof deck, cornice,
  roof stair head or a smaller upper room, a water jar), packed (49 pieces, atlas still 1024 x 1024), used for culture
  style 2 (`_house_piece`). Shader tables are 64 entries now (`rects[]`, `anch[]`), no longer 48.
- **Board** (`board_layer.gd`): bevel 6 m in two faces with a flat lip, mitred corners, grain, a pale rim on the
  lit sides, a soft shadow on the table (28 falloff rings, drawn as rings only), table of planks with seams and grain
  (detail to 450 m out; the board's own span is not painted, it is under the ground).
- Frame time bench_4000_city High GPU paused (1920x1080, mean of 8 s): 4.76 ms before, 4.8 ms after.

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

### Units flow into the space (as built, 2026-10-09)

Why: playtests had units jam at walls and buildings (a unit 87 of 90 up a
wall and frozen, refusing orders; one ladder of five in use; units wedged
between a house and a friend; attackers unable to press out of a gateway).
A unit was a rigid rectangle. This build is for chokepoints in general
(gateways, breaches, ladder feet, tower ramps, stairs, streets, a house's
corner), on maps with buildings or walls only (`obs_on`): field battles
play and hash exactly as before (golden digests unchanged). Code:
`sim/battle_sim.gd` (`_stuck_tick`, `_stuck_release`, `_flow_slots`,
`_ladder_step`, `_ladder_move`, `_anchor_step`, `open_snap`, `_way_clear`),
probe `tests/determinism_test.gd --only=flow`, `tests/matchups.gd
--only=fair-sieges` (stuck columns).

- **Measurement: the no-progress counter.** `u_stuck` (hashed, with its
  reference point `u_srx` / `u_sry` and `u_sprog`): ticks a unit has wanted
  to get on (a move, an attack still closing, a march to a stair or ladder,
  a stair or ladder move, or its men more than `LAG_CUT` behind their
  places) while its men's middle stayed within `STUCK_DIST` 2 m of where it
  last got on, and it was neither fighting at its frontage (half its front
  rank within reach) nor waiting by rule (`BLK_QUEUE`, a ladder queue with
  every ladder busy). A man reaching the walkway (a climb) or the other
  level (a stair move, `u_sprog`) is progress. Diagnostics (not hashed):
  `stat_stuck_max`, per unit `stat_stuck_u` (longest) and `stat_stuck_t`
  (ticks in all).
- **Ladders** (`_ladder_step`; replaces the shared `q_acc` pool and the
  slot-fixed wait spots). Every man still below picks a ladder of the set,
  the men nearest a ladder's foot first (ties: lower slot; in slot order
  until 2026-10-10, see below): the way to its foot plus `LADDER_QCOST` 1.2 m for each man
  already in its queue (ties to the lower ladder), and waits in its queue, two abreast
  (`LADDER_QW` 0.6 m either side) a metre apart back from the foot. Each
  ladder takes its first man up when he is within `LADDER_AT` 8 m of its
  foot (1.5 m until 2026-10-10) and it is free: `q_lt` (hashed, per planted piece and lane) holds
  the tick each lane takes its next man, `climb_per` ticks after the last,
  all lanes at once (the set's throughput as before: `LADDER_TICKS` per
  ladder); he steps onto the walkway whoever stands there. (A rule holding
  a ladder whose top was crowded with the climbers' own men was tried and
  dropped: probe (b) walls 1 fell from 77 men up / 20 defenders killed to
  55 / 4; with 4 men in 1.5 m 68 / 15, 6 in 2 m 67 / 12, off 75 / 17.) A move order is taken
  while climbing (`_ladder_move`): along its stretch the line slides and
  the climb goes on; out on the foot's side (or nobody up yet) the men up
  come back down the ladders and the whole unit goes; inland or onto
  another stretch the men below go on climbing and the unit goes on from
  the wall once all are up. With a ladder free and nobody coming to it for
  `LADDER_STALL` 30 s the climb is given up (all come down the ladders;
  `stat_ladder_cut`). No man is left below a wall unit.
  **Fix (siege pass, 2026-10-10):** after this build a defended escalade
  killed far fewer defenders (probe (b), 8 sim seeds, men up / defenders
  killed: before the build walls 1 88 / 42, walls 2 66 / 16; with it 78 /
  22 and 56 / 4). Bisected inside `_ladder_step` (the old step restored
  in the current tree gave 90 / 44 and 66 / 15): under fire the queues
  were assigned in slot order and every death refills slots from behind,
  so who stood first at each ladder changed every few ticks and the
  ladders stood idle a fifth of the climb (360 idle lane-ticks a battle,
  the queue's first man 3 m off the foot on average). Nearest-first order
  and `LADDER_AT` 8 m (the old step's reach): 88 / 38 and 60 / 7. The rest
  of the walls-2 gap is the old step's arrivals, which repeated the top of
  the ladder whose man had just died (any man to any top at the set's
  rate: friends within 3 m of an arrival 3.4-5.1 against 1.6 now); only
  that unphysical rule restores it (65 / 14), so it is not rebuilt.
- **Slots that flow** (`_flow_slots`, from `_compute_offsets`, units near
  obstacles on the ground or at a stair's foot). The rectangle is laid out
  as before; places that are cut (across a wall, in a house, on another
  piece of ground) are laid out again by a flood from the anchor's 2 m
  cell (the nearest open cell if the anchor is at a house's edge):
  neighbours +x, -x, +y, -y, open ground of the unit's mask, at most
  `FLOW_AHEAD` 4 m ahead of the anchor and, ahead of it, no other unit's
  footprint; each cell takes up to its share of men at `FLOW_PACK` 125 % of
  the formation's density (whole places in it count first); places in slot
  order, so the front rank is nearest the anchor. A unit queuing behind
  friends (`BLK_QUEUE`), or squeezed in a corridor and fighting, flows all
  its places (it packs to the front: the queue zone at a gateway, a breach
  or a street). `PLACE_LEAD` / `PLACE_SIDE` are measured from the flowed
  place, so men press forward because their places do. Budget: a flowed
  unit is laid out again at most every `FLOW_EVERY` 10 ticks (and on any
  order); in between deaths only drop places off the end; a flood visits at
  most `FLOW_CELLS` 160 cells and stops once every cut place has room.
  `u_flow` / `u_flt` hashed; the cell marks are scratch (stamped, not in
  snapshots).
- **Stuck release** (`_stuck_release`, every `STUCK_CYCLE` 150 ticks of
  `u_stuck`): at 50 the places are flowed afresh; at 100 the way is planned
  again (and while stuck a moving goal no longer replans it unless it moved
  48 m; the street graph's distance tables are built at once for it), or a
  move within `STUCK_NEAR` 8 m of its destination, or to ground no longer
  reachable (a gate shut since), ends where it got to (since 2026-10-10
  also a march to a stair's foot, and any move with no way through the
  street graph: a pocket reached by an alley too narrow for its 3 m line;
  a fair siege's 60 wall archers come down into one marched at a house for
  the rest of the battle); at 150 the anchor
  goes back to its men (`_regroup`; the man farthest back on its own
  ground when they are strung out past `LAG_HOLD`) and goes on from there.
  Only the anchor and the places move: no man steps through a wall or an
  enemy. Not on a wall, a stair or its ladders; routing units do not count.
- **Movement bugs the counter found** (each a long freeze in the
  fair-sieges set): the street squeeze's keep-to-the-middle shift is not
  applied on a move's last 12 m (the unit faces its final way there and the
  shift pushed it back along its way: defenders 2-3 m short of their stack
  places for minutes); an attack order after an attack keeps its path (the
  AI retargeting every second had a unit at a corner replan, turn back to
  an entry node behind it and never get on); a unit coming down a stair
  forms on the ground at the foot (its block stood across the wall, men
  whose places were on the walkway stayed up until `STAIR_MAX`); men on a
  stair move take the trail point before the next one when the way to it
  is not clear (men in a junction tower went for the stair through the
  wall), and men on the walkway with no clear way go along the stretch's
  centre line; a ground anchor does not step into a wall or a house (it
  slides along it, or plans again; a shortcut past a corner had anchors cut
  through walls, their men left on the other side); a waypoint counts as
  reached only with a clear way on to the next; a short move among
  buildings snaps the anchor only with a clear way from the men (else it
  marches, its men on its trail); a tap on a house on a map without a town
  goes beside it (`open_snap`).
- **The column on the walk (2026-10-10).** Owner's playtest: his heavy
  infantry moving along a wall walk "fought in 2s" while light infantry up
  the ladders "made a ball on the front 2 and killed them like a feeding
  machine". Yardstick `tests/matchups.gd --only=wall-col` (also in
  `--only=wall-yard`): 100 light climb a 5-ladder set a quarter of the way
  along a 95 m stretch nobody holds; 100 heavy stand on that walk (their
  line's near end 6 m from the ladder top) and are ordered at them once 40
  are up ("yard wall 8": an attack order; "yard wall 9": a move along the
  stretch to the ladder top); the open-field heavy-vs-light baseline is
  "yard wall 10". Before: a wall unit with an attack order held its
  stretch, its men walked in unbounded (no lead cap on walls), the
  climbers' line was laid centred on the ladder top through the heavy's,
  and nothing limited how many enemies stood at one man: light men in
  reach 23.5 against 7.5 heavy 5 s after the order, heavy lost 13 men in
  those 5 s, 35 light / 22.9 heavy killed in all (20 seeds; open field
  37.2 / 9.9). Three rules, on walls and in streets only (field battles
  hash as before):
  - *Column*: a wall unit (foot) attacking a unit on its own stretch, or
    on the stretch joined to it through a tower, whose middle is ahead of
    its line (beyond its line's middle by more than half its length less
    4 m) goes along the walk at it (`_wall_col_goal`): its anchor becomes
    its head (`_wall_col_head`), which walks along the centre line toward
    its man's middle (on a joined stretch: the tower end) while none of
    its men is in reach and never past the enemy's front; `u_flow` 2.
  - *Cut line*: any wall unit in contact whose centred line would reach
    into walk held by an enemy ahead of it (the enemy's 3rd man nearest it
    along the stretch, so one man slipped past does not move it;
    `_wall_front`) has its line laid behind that front instead
    (`WALL_FRONT_GAP` 1 m short of it); `u_flow` 3. Both layouts are the
    wall line's two files packed at `FLOW_PACK` % of the file spacing,
    closer where the walk behind is short (down to `WALL_PACK_MIN` 0.5 m),
    re-laid every `FLOW_EVERY` ticks (`_wall_offsets`); their men keep to
    `PLACE_SIDE` 3 m along the walk of their places (the "Ranks hold
    together" cap, which walls had been exempt from), both files search
    as the front rank, and they do not wrap.
  - *Reach cap* (`WALK_REACH_MAX` 3, the one new balance number): a man
    on a wall walk (or a tower) of a wall unit, or of a unit squeezed in a
    street (`u_sq`), is within reach of at most 3 enemies (two abreast and
    one behind each on a 4 m walk). At the start of the soldier update the
    men already in reach of such a man are counted, the first 3 by unit
    and slot order kept (`_reach_cap_count`, scratch `_rc_tk` / `_rc_n` /
    `_rc_ok`, stamped by tick, not in snapshots); a man whose man is full
    neither steps in nor strikes and looks for another, and the target
    search passes over full men (`_find_target_obs`).
  After: 5 s after the order light 6.7 / heavy 2.7 in reach, heavy lost
  6.2 in those 5 s and 1-2.5 a 5 s after; in all 37.8 light / 22.1 heavy
  killed, decided at 75 s instead of 40 (a grind at the walk's width, no
  ball; the light keep about 1.5 times the heavy's men in reach, packed
  closer at the ladder tops, so the heavy win about 1.7 : 1 against 3.8 :
  1 in the open). Side effects: the existing wall yardsticks (20 seeds)
  barely move (heavy climbing against light on the walk lose 12 instead of
  19); the `--only=flow` ladder probe with 60 defenders above: attackers
  lost 40 -> 25 at walls 1, 51 -> 50 at walls 2 (defenders lost 39 -> 40,
  8 -> 18); the street fight probe is unchanged. Equal-force fair
  sieges (both Average, 10 seeds, attacker wins before -> after), ladders
  + ram / full kit: ring walls 1 20 -> 20 / 40 -> 50 %, walls 2 0 -> 20
  / 20 -> 20 %; polis walls 1 40 -> 60 / 40 -> 60 %, walls 2 30 -> 10 / 10
  -> 30 % (escalades a little easier; within 10-seed noise cell by cell).
  Tick cost bench_4000_city 3.77 -> 3.96 ms a tick (+5 %; engaged 4.73 ->
  5.01, the battle 110 ticks longer). No new hashed array: the anchor,
  offsets and `u_flow` (now 0-3) were hashed already.
- **AI**: no AI rule or knob changed (docs/AI.md 25).
- **Measured** (`--only=flow` set pieces, HEAD with the counter only ->
  this build): a 90-man heavy unit up a 5-ladder set, no defenders: walls 1
  all up in 360 -> 369 ticks, walls 2 540 -> 568 (the first men walk into
  their queues), 5 ladders in use at once, a mean of 4.7 -> 4.4-4.6; a move
  given as the last man went up was refused and left the unit split 40 up
  / 50 below at walls 2, now taken (the unit whole). With 60 defenders on
  the walkway both versions rout back down after half their men (none left
  below); men up 77 / 57 -> 75 / 56, defenders lost 20 / 12 -> 17 / 2. A unit ordered across a house's corner never formed (53 men more
  than 3 m off their places) -> formed in place round it. Four units
  through one gate, the street fight: unchanged. Equal-force fair sieges
  (full kit, both Average, 10 seeds, ring / polis walls 1-2): units stuck
  past 20 s 8 / 20 / 29 / 31 -> 2 / 3 / 6 / 12, longest 3629 / 4255 /
  2232 / 2906 -> 257 / 368 / 2466 / 854 ticks (not yet under 200: men in a
  narrow alley the 3 m path line cannot use, stair approaches with
  stragglers far behind, defenders moving through their own stack, a
  battery). Tick cost: see docs/STATUS.md.

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
  piece. Streets are sandy earth with the plaza paved
  (`city_streets.gd`), the town's ground trodden only within about 8 m of
  houses and roads (`terrain_layer.gd` `_west_built`, view only; the sim's
  V_URBAN covers the whole band), palms on any West map.
- **Not built (open).** (The fort's inside, its garrison and guns and units
  holding houses came with slice 2c.) The palisade does not burn or get
  hacked; piers are scenery (the rules
  see the sea); moored ships are not drawn on the battle map; native
  towns keep the oppidum; walls 3 keeps the walled plans.
- **Measured.** See docs/STATUS.md (the pathing probe, the cover probe,
  set-up and tick cost).

### Fight jitter and stuck units (as built, pathing phase J, 2026-10-16)

Why: phase C's target (fight jitter near obstacles and in town at most
3 %) was not met (4.7-5.1 % near obstacles, 3.1-6.1 % in town), and seeds
8-10 showed 2-5 stuck runs over 30 s (docs/STATUS.md, phases C1-C7 and
W). Attribution (scratchpad `pathJ/jat3.gd`: each jittering man-window of
a unit in contact split by what moved the man: his place by slot change,
unit turn, anchor move or re-lay, a target, or neither) and per-tick
traces found these causes, all on maps with obstacles:

- **2-cycles against a face** (the largest share; battle_2000's men cut
  off behind a cliff 10 %): a man's step toward his place is slid or
  pushed back by the nav test, the slide, the unit's trail or the
  clearance push, and the next step undoes it (the lean and the full
  contact paths slid by different rules; a field man pinned at a drawn
  corner). Every tick, 0.3-0.5 m each way.
- **Units turning in a fight**: most foot turn at once (`turn` 0), so any
  wobble of the bearing to the target threw every place round the
  anchor; a one-tick facing flip at a move's first step swung the outer
  files 15 m.
- **Re-lays of flowed places**: a flowed unit in contact was laid out
  again every second (or on any death or turn), and the flood from the
  same cell gave its men other cells as the footprints round it moved.
- **The street middle shift against the path**: a squeezed unit on the
  go with an enemy near shifted its anchor up to 1 m to the street's
  middle every 3 ticks while its path pulled it back at a corner; its
  facing swung 86 degrees every 3 ticks for half a minute.
- **The lag regroup cycle**: a unit whose men came on slowly through a
  crowded lane regrouped every 10 s (`REGROUP`): its anchor jumped back
  among them, its places were laid out afresh and the front men turned
  about.
- **An anchor sliding along a house** toward a waypoint across it
  swung 0.3 m a tick, either side of the waypoint's line.
- **The skirmish dance**: a skirmishing missile unit the sim fell back
  from a threat (its march facing away, then about to face it) was sent
  back to its post by the AI the next second, and so on; storming units
  at the plaza's hunt radius turned between a defender and the plaza
  every second think.

Stuck runs over 30 s had their own causes: West skirmishers with an attack
order on a defender in range but behind houses closed straight into a
house (no line of fire: they did not go by the streets); an attacker kept
closing on a target 54 m off while its men fought another unit at a gate;
stragglers 40-90 m from their places in a pocket the straight step, the
slide and the trail did not lead out of; a unit's men split by a shut gate
counted as stuck for ever; lone routers pinned at a house's drawn corner
the exit field ran past (its 2 m cell open, the clearance push sending
them back each tick); 36 of 38 routers shut in a court pressing a wall
while two ran.

Code: `sim/battle_sim.gd` (`_step_guard`, `_face_held`, `_flow_due`,
`_gather`, `_via_goal`, `_via_on`, `_via_dst`, `_asl_step`,
`_xf_tight_build`; hooks
in `_turn`, `_update_units`, `_update_soldiers`, `_compute_offsets`,
`_flow_slots`, `_squeeze`, `_anchor_step`, `_stuck_tick`,
`_stuck_release`, `_xf_begin`, `_xf_unit`), `sim/siege_ai.gd`
(`_at_hand`, `_watchdog`, `_skirm_back`, `_bound_storm`, `_storm`,
`think`), `tests/lockstep_test.gd` (three peers: refusals compared at a
common frame), `tests/pathing_probe.gd` (comment). Field and
open maps are untouched: every rule is gated on obstacles (`obs_on`, a
unit near obstacles `_u_obs`), so the four flat golden digests hold.

- **Step guard.** Per man in a unit near obstacles (the fast path and
  the contact lean and full paths; not on a stair move) the last step is
  kept (`s_ls`: the step, 12 bits a
  component, and a stall count; written inline for an open step, the
  guard called only for a changed one). A step that was changed by the nav test, the slide or the
  clearance push and that would undo the last one (more than 120 degrees
  from it) is not taken: he stands, at most `GUARD_T` 20 ticks running;
  then the step is taken (a dead end the trail leads back out of). An
  open step (straight at his place or his man) is always taken. Standing
  at his place clears it. This is the per-man step floor: nobody swings
  between a face and his place.
- **Facing deadband.** A unit among obstacles in a fight or shooting
  (contact, a fire target; not on a wall, not a battery, not on a stair)
  holds its facing while the wanted one is within `FACE_DB` 34 (12
  degrees). An attack holds only from rest (`u_face == u_dface`): a turn
  once begun is finished, to the bearing as it moves, so the facing
  reverses only after the bearing swings 2 x FACE_DB (the C1-C7 agent's
  20-degree hard hold left units stuck facing away; this does not). A
  move in contact keeps its march facing within the band. Foot that turn
  at once (`turn` 0) turn at most `OBS_TURN` 16 a tick there (90 degrees
  in 1.6 s, the cavalry's rate): a facing that swings for a tick no
  longer throws the places round.
- **Falling back facing the enemy.** A move in contact among obstacles
  whose way runs more than 90 degrees off its ordered facing (a
  skirmisher falling back, a unit backing off) keeps the ordered facing
  instead of the march facing: no about-face at the start and the end of
  each fall-back, its places swinging round with it.
- **Re-lay only on a change.** A flowed unit stores the anchor's 2 m cell
  and its facing and squeeze when flowed (`u_flx`, `u_flf`). On the go it
  is laid out again each `FLOW_EVERY` only if one changed (the cell, two
  cells off in a fight; the facing past FACE_DB / 2; the squeeze; on the
  move with no enemy near: as before). In a fight a death or a few degrees of turn no longer lays
  out its places afresh (`_compute_offsets`); an order or the stuck
  release (`u_flt` < 0) does as before. The squeeze keeps its files when
  the count would change by one in contact (hysteresis), and the street
  middle shift is not made with an enemy near (Hold street lines standing
  still shift as before).
- **The lag regroup waits for slow men.** The regroup after `REGROUP` 100
  ticks cut off happens only once the men's middle has stopped
  (`u_stuck` >= `REGROUP_GO` 30): men still coming through a crowded lane
  are waited for (a quarter pace past `LAG_HOLD`).
- **Anchor along an obstacle.** The anchor's step along a wall or a house
  (`_anchor_step`, one axis) that undoes its last such step (`u_asl`) is
  not taken; it stands and its way is planned again (every 5 ticks).
- **Missile troops go round.** A missile unit with an attack order in
  range of its target in a town but with no line of fire (houses between)
  goes by the street graph as melee does (`mlof`: one line-of-fire trace
  a tick serves both checks); with a line of fire it stands and shoots as
  before.
- **Stragglers.** (1) At the stuck release's `STUCK_ROUTE` step, men more
  than `LAG_CUT` from their places on the anchor's ground get a trail: the
  street route (`route_to`) from the farthest of them to the anchor
  becomes the unit's `TRAIL` (`_gather`); a standing unit whose only men
  short of their places are on ground it cannot reach (a shut gate
  between) is not counted as stuck. (2) A man of a unit whose anchor
  stands, more than `VIA_FAR` 12 m from his place with no clear line to
  it (the 2 m cells along it,
  `_way_clear`) who has not got a metre nearer in the last second walks
  the street graph node by node (`s_via`: his next node, or below 0 his
  distance at the last look; the target node `u_gnode`, nearest the
  anchor): from the node near him down that node's distance table, until
  he has a clear line or is within VIA_FAR; checked once a second a man
  (a node he no longer sees is chosen again; the unit's node is found
  again once the anchor is VIA_FAR off it). A man going round a house's
  corner to his cover spot is not a straggler (the first cut, on any man
  with no line, sent buccaneers in the street-cover set piece the long
  way round: 34 -> 38 lost, now 32).
- **Routers.** The exit fields leave out open cells whose middle is
  nearer a drawn house face than `CLR_MIN` (`_xf_tight`, static, built
  once at set-up: 8-10 ms), so no field way runs where the clearance push
  sends a man back; a router whose field step is still pushed back tries
  the directions 45 then 90 degrees off the field's, then the slide
  memory. A routing unit down its side's field huddles where most of its
  men are when fewer than a quarter of them have a way out (was: none).
- **AI (`sim/siege_ai.gd`).** `_at_hand`: an attacking unit fighting with
  its men while its order's target is over `AT_HAND_FAR` 20 m off (box to
  box) attacks the enemy within `AT_HAND_NEAR` 4 m of it instead. West
  skirmishers by bounds (`_bound_storm`) pick a defender they have a line
  of fire at first, and keep an attack whose target just went out of
  sight `UNSEEN_T` 6 s before picking again (a visible target, else on by
  bounds). A skirmishing missile unit (`u_skirm`) with a foot or horse
  enemy within the sim's skirmish distance + `SKIRM_HYST` 10 m gets no
  order (`_skirm_back`): the sim's fall-back runs (the AI sent it back to
  its post every second and the sim fell it back again). The stuck
  watchdog (`_watchdog`, every AI unit on maps with
  obstacles): a unit whose middle has not got on for `WD_T` 20 s
  (`u_stuck`) while not fighting, not shooting, not on a wall, stair or
  carrying, has its order planned again once each 20 s: an attack goes
  for the nearest other enemy unit its side sees on its own ground (none:
  it halts, and its mode's rule gives it a fresh order from where it
  stands), a move halts likewise. Storming units at the contested plaza
  hunt a defender anywhere from within its radius + S_PLAZA_HUNT as
  before, and keep after one out to 2 x S_PLAZA_HUNT further (a unit
  turned back to the plaza at the edge and for the defender again every
  second think, its anchor swinging 0.1 m a tick).
- **Statistics.** `stat_stuck_u` (the probes' stuck runs) counts a unit's
  no-progress time only while none of its men is fighting
  (`stat_stuck_r`); the release itself runs on `u_stuck` as before. A
  unit at a gate whose men fight in turn is in the fight, not stuck.
- **State.** Hashed on maps with obstacles: `s_ls`, `s_via` (per man),
  `u_flx`, `u_flf`, `u_asl`, `u_gnode` (in `_flow_arrays`); all in
  snapshots. `_xf_tight` is static (skipped in snapshots, rebuilt on
  first use). Diagnostics (not hashed): `stat_guard`, `stat_gather`,
  `stat_via`, `stat_asl`, `stat_ai_wd`, `stat_stuck_r`.
- **Measured.** See docs/STATUS.md (the pathing probe at seeds 7-10, the
  cover probe, cost).

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
  panel's **Occupy** button (key I): every selected foot unit into the
  nearest free building within 60 m; **Leave** once one holds a building.
- **Not built.** Ships offshore for the sea guns; a sally from the fort
  (the defenders never open the sally port); the garrison does not come
  down to help the town; men inside a building do not fight room to room
  (the door's pairing is the whole melee); timber buildings do not burn
  with men in them; galleries on the governor's house (only the tavern's
  front counts as a gallery); the AI's own buildings for skirmishers (only
  the musket lines go in).
- **Measured.** See docs/STATUS.md (slice 2c).

### Compact unit cards (as built, 2026-10-09)

View only: `game/unit_traits.gd` derives everything from the unit rows, so a
new row gets it free. A unit card (`Kit.UnitRow`: recruit lists, army cards,
the raise picker, exchange, garrison) has three lines: the name with up to
three **trait** glyphs (siege, shock, anti-cavalry, fearsome, armour piercing,
long range, skirmish, fire for the viewer's faction, beast, fast; tap =
one-line toast), a green row (good against) and a red row (weak against) of
the six enemy **class** glyphs (foot, spear, horse, missile, beast, engine),
and five **pips** (attack, defence, armour, missile, speed, four segments,
scaled against the best of the unit's class; speed and missile against all
rows). The rule table is in the file's head comment; the unit book page and
the battle card tooltip show the same. Recruit lists and the raise picker sit
under collapsible class headers with the best tier of each line and a
"+n tiers" chip for the lower ones; an army card opens with a composition
strip (class glyphs with unit counts) that folds the unit rows (armies of up
to six units start open). Fold state is per session, never in the campaign
state.

### The command bar (overworld selection, as built 2026-10-15)

View only (`game/campaign/command_bar.gd`; no rules path, no `campaign/`
change): what is selected shows as cards along the bottom of the screen
instead of the side panel's long list (user: "just a big list on the right ...
like Rome"). **Army:** a leader card (faction emblem, the hero's name or
"X army", men, units of the cap, movement left, stance, upkeep, supply in a
siege, a status line: holding / marching and when it arrives / besieging),
a strip of **unit cards** (symbol, tier pips, up to three trait glyphs, a
strength bar with men / full; a tap picks it for Split / Disband, a long
press opens its page, hovering shows the full compact row; planned recruits
as dimmed "joins" cards) and a grid of **icon actions** with a label under
each (Stance cycles March / Forced / Fortify / Raid, Siege / Assault on
arrival, Cancel, Split, Merge, Exchange, Recruit, Disband, Board, Sally,
Details). **City:** city card, garrison cards, building chips (icon and
level; a tap says what it does), Recruit (the raise picker), Build, City map,
Assault / Continue / Withdraw for a besieger, Besiege and Raid at an enemy
city, Sally for the besieged. **Fleet:** a card per ship (hull and crew),
Cancel voyage, Board, Join. An action that cannot be done is greyed and says
why on hover and on a tap. Every button calls what the side panel's buttons
call (`add_order`, `set_move_mode`, `_set_stance6`, ...). **Details** opens
the old full panel in the side panel, which now opens only on demand (and
for Build / Recruit into an army, which scroll to their section there); its
Close hides it and keeps the selection. Layout: full width at the bottom,
132 px (96 on a phone: narrower than 700 or lower than 560 logical px, one
horizontally scrolling row); the map key buttons, the End turn row, the hint
and the toasts rise above it while it shows. Versions before 6 keep the side
panel only. Testing aids: `--details` / `--no-bar` (the old behaviour).

**Round 2 (2026-10-16, owner's tablet playtest).** *Recruit popup tabs:* the
city's Recruit opens `show_raise` on **Army** or, with nothing to raise and a
yard to build in, **Shipyard** (tabs only in a pack with ships at a port of
ours; greyed "needs a Shipyard"); the Shipyard tab lists the ship rows (cost,
guns, hull, crew, carries, pace, upkeep, yard level, the reason when not
buildable), the queued ship with X and the fleets in the harbour; "Build ship"
adds the same `ship` order; a fleet in port gets a **Shipyard** action. *Drag
on the bar:* `DragReorder` over the unit cards (mouse: press and move; touch:
hold until it lifts; ghost and gold slot mark), drop = `_arrange(id, from,
to)`; a hold without a move opens the unit page; a short tap still picks the
card for Split. Dragging onto another army or the Exchange action is not
built (reorder only). *Build popup:* queue on top with Cancel, a row per
chain (icon, "Farms 1 -> 2", cost and turns, first clause of the description,
the reason greyed), a tap queues the `build` order. *Details thinned:* the
army panel keeps the count, characters, the march line and the movement
points; the city panel keeps income / growth, sea notes, armies here,
characters, what it trains, the siege section (odds and orders text) and
gifts; units, order, Split, Disband, Exchange, Merge, stance, recruits,
Board, Cancel, siege orders, the garrison, buildings, raise and the
shipyard are on the bar or in a popup, each order in one place. A planned new
army's X is in the Recruit popup; a planned recruit into an army is a dimmed
card (tap cancels). Testing aid `--popup=build:key|raise:key|ship:key|recruit:N`.

**Tap latency (2026-10-16, owner's Tab S7: "almost any selection has a visible
delay").** A tap is answered in the frame it lands in, and that frame only does
what the tap changed; the rest follows in later frames. Rules of the view
(`game/campaign/`, nothing in `campaign/` or `sim/`):
- *The map is not drawn again for a selection.* The selected army's reach is
  its own child node of the map (`map_view._reach_node`, under the pulse
  tints) and the selected region's outline another (`_sel_node`, over the
  edges, under the coast); `set_reach` / `set_selected_region` redraw only
  those, and `set_reach` keeps the outlines when the reach is the same.
  `map_view.refresh_state()` redraws the territories and edges only when an
  owner changed (the only part of the state the map shows).
- *The overlay redraws only the parts a selection changed:* on the same state
  (`_refresh_map6` keeps the state, campaign and planner it last drew, plus a
  few counts) `overlay.redraw_parts(paths, fleets, armies)` redraws the paths
  (with zones, links, badges) when they differ, the fleets when the selected
  fleet, voyages or sea reach differ, the armies when the merge glyphs differ,
  the halo always; settlements never. A new state (an order, a resolved turn)
  still redraws all six parts. The drag preview redraws only the paths.
- *An army's reach comes one frame later:* `select_army` shows the bar, the
  halo and the hint in the tap's frame; its reach (the rules' `reach6` and
  the outlines), zones, links and merge glyphs are computed in the first
  frame after the tap's frame (a process-frame count, deterministic and
  headless-safe; on the web the page has shown the bar before the work
  starts).
- *The command bar is built once per frame* for the same selection, state,
  plan, panel and window (`_refresh_bar` signature; a tap used to build it
  twice: `show_side`, then `_refresh_map`).
- *Icons are textures:* `game/campaign/icon_raster.gd` draws each vector icon
  (`game/ui_icons.gd`) once, in white, into an atlas (a SubViewport rendered
  only when an icon is added; premultiplied blend so the atlas is straight
  alpha) at the screen's physical pixel size, and the bar's actions, unit
  card trait glyphs, `Kit.set_icon` buttons and `Kit.label_icon` labels draw
  one tinted quad (the first frame an icon size is asked for it is drawn as
  vectors). The bar's icons are asked for when the screen opens. Greyed icons
  no longer show darker overlaps where strokes cross.
- *A plan edit is saved 1.5 s later* (`save_plan`: one save for a burst of
  taps; flushed by `save()`, End turn, leaving the screen, the window losing
  focus or closing, a hot-seat hand-over); `add_order` hands its preview to
  `_replan` instead of computing it twice.
- *End turn answers at once:* the turn resolves two frames after the tap,
  under a "Resolving the turn" dialog drawn first.
Measure with `--prof-tap[=N]` (also `?prof-tap=N` in the web build's URL,
e.g. `?campaign=rome&prof-tap=3`; `game/campaign/tap_prof.gd`) or
`tests/tap_latency.gd` on a desktop; numbers in STATUS "Overworld tap latency".

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
| Explosive stones | stones | 20 | 100 (aoe) | 50 | 85 | 125 | 40 | +3.12 m (4 m round) | - | walls, range, rate, share |
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

### Explosive stones: blast and knockback (as built, 2026-10-09)

Owner: "is the blast any different from the rocks? They should do an area
of effect and knock back some of the soldiers". An ammunition kind with
`aoe` 1 (only Explosive stones) replaces the stone's plough and pierce
(`_land_blast`); ordinary stones keep theirs. Numbers chosen once:

- **Area**: the blast is the stone's `m_blast` (0.9 m) + the kind's
  `blast` 3196 = 4 m round the landing point. Every man inside is struck
  (friend or foe; no cap): energy = stone damage x kind `dmg` x (3R - 2d)
  / 3R (full at the centre, a third at the edge), less armour (`ap` as
  for stones; no shield), x vulnerability, x 85-115 %. Engines inside take
  double (as a stone). Gates, towers and rams as before (`obj`). Trees do
  not catch it, slopes do not matter (no plough).
- **Knockback**: the survivors, nearest first (ties: index order), at
  most `BLAST_KNOCK_MAX` 30 per landing, are thrown outward from the
  landing point (straight on along the flight if dead centre)
  `BLAST_THROW` 1 m + RNG 0-1 m (`BLAST_THROW_RND`) and lie down
  (`S_DOWN`, the existing knocked-down state; its timer is the hashed
  per-man `cooldown`) `BLAST_DOWN` 20 + RNG 0-10 ticks (`BLAST_DOWN_RND`;
  mean 2.5 s). Riders and beasts (cavalry class or not on foot): half the
  throw and half the time; elephants (big bodies) are not thrown and lie
  1 s (`BLAST_DOWN_BIG` 10). A man already down keeps the longer timer; a
  router is thrown but keeps running. The throw is taken only if its
  midpoint and its end are on the same kind of ground he stands on (his
  unit's mask: no passing a wall, a shut gate or a building, no stepping
  off a walkway or into a ditch); else he stays where he is, only down.
- **Down** (as any knocked-down man): no moving (his place waits; the
  formation closes up only for the dead), no attacking, not counted in
  `u_inreach`, no shield against missiles, `DOWN_BONUS` to be hit in melee
  (35, beside the rear's 40: kept). The unit's `u_down` counts them.
- **Fear**: the kind's 40 on top of the stone's 60, once per unit struck
  (every man in the blast is struck, so downed men count).
- **View**: the effects pass's blast ring (now 4 m) and smoke; a downed
  man is already drawn lying (turned 90 degrees, darker, smaller) on both
  the GPU and CPU paths (state 3 in `soldiers.gdshaderinc`).
- Probe (`determinism_test --only=blast`, battery 18 men into a 160-man
  pike block at 150 m, 120 s): 7 bursts, 23 men struck and 14 knocked a
  burst, mean down 25 ticks, 27 men more than 1.5 m off their places
  right after a burst (most 44); ordinary stones none knocked.
  Yardstick (`matchups --only=yard`, 20 seeds): the explosive load (8.7
  shots) kills 58.0 of 120 pikes (136 struck, 78 knocked) against 8.1
  killed by as many ordinary stones (not tuned).

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
| Missile | javelins 40 m, 38 dmg, 50 ap, 5 a man, 3 s (javelinmen 42 / 60 / 6 / 2.8 s: thrown from a moving horse); through 10 % of a shield (`m_spen`, tuned 2026-10-09; javelinmen 15) | sling 150 m (bow 140), 28 dmg, 0 ap, 40 a man, 3 s (bow 30 / 25 ap / 4 s) |
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

### Firearms (as built, West slice 2a, 2026-10-14)

Row fields (`sim/unit_types.gd`, generic, defaults keep every Rome row as it
was): `m_gun` 1 a powder weapon; `m_volley_r` fire at will holds the volley
beyond it (0: 70 % of `m_range`); `m_spread2` scatter growing with the
square of the distance (a smoothbore: fair at 60 m, wild at 100 m);
`m_obj` a bolt's damage to gates, towers and rams in % (roundshot breaches).
Sim (`BattleSim._gun_unit`): a gun missile unit (foot or rider) reloads as
a body (`u_fire_acc` counts to `m_reload`, half speed on the move; it starts
loaded) and fires a volley: every man in formation with a charge fires on
one tick (flat, `m_arc` 0: a clear line past friends). Foot stand to fire,
riders fire on the move (pistols at ~25 m in the charge). Fire at will
holds the volley at a target beyond `m_volley_r` unless it is coming on
(ordered to attack this unit, or its men moved toward it this tick) or the
unit was ordered to attack it. The first ball of a volley that reaches a
unit frightens it once (`m_fear` into `u_fright`, +50 % on horse, camel,
elephant): hashed `u_vf_u` / `u_vf_t` (the volley's unit and fire tick),
only with `gun_on` (a scenario unit has a gun row). Guns (artillery) are
bolt-path engines (`m_kind` 1: pierce, plough, per-shot fright) with
`m_gun` 1 for the view and `m_obj` for gates. Rome byte-identity:
`kty_n` (the width of the hashed `u_kills_ty`) is `UnitTypes.ROME_N`
unless a West row fights. View: gun smoke (`game/gun_smoke.gd`, shared with
the sea view): soft baked cloud sprites (one generated atlas, lit from the NW,
grey-blue shade, one texture so the canvas batches them) that roll off the
muzzles into a continuous bank, expand, rise and drift with a fixed wind over
10 s; a flame-tongue muzzle flash with a glow; a gun engine adds a ring of
smoke and a ground dust kick; a capped lingering haze builds over a long
firefight. Diorama tints it cotton-white, painterly grey. Graphics Low: fewer
puffs, no ring, dust or haze. The `musket` and
`cannon` clips (`stat_volleys`, `stat_cannon`). Later: smoke that blocks
aim in the sim (cover and line of sight: built, "Cover and line of sight"), gun ammunition kinds
and wagon refills (an `AMMO` row would change the hashed wagon stock
width: needs the same gating).

### Cover and line of sight (as built, West slice 2b, 2026-10-15)

The "Cover (battle, slice 2b)" paragraph of "The Caribbean pack" made
playable. Rule of cool with a real anchor: the irregulars of the Indies
(buccaneers, Miskito and Maya warriors, frontier skirmishers) fought from
behind trees and rocks and ambushed from the forest; the tercio and the
English and Dutch foot stood in formation and won by volley discipline.
Code: `sim/battle_sim.gd` (section "cover and line of sight": `_setup_vis`,
`sight_line`, `_update_vis`, `_seen`, `_cover_from`, `_cover_stops`,
`_ambush`, `cover_state`; hooks in `_land`, `_missile_hit`, `_fire`,
`_art_fire`, `_update_contacts`, `_update_units`, `_missile_think`,
`_art_think`, `lof_block`, `_obs_top`, `hidden_from`), `sim/unit_types.gd`
(`cover`), `sim/battle_ai.gd` (`_plan`, `_cover_spot`, `_probe`),
`sim/mapgen.gd` (terrain key `rocks`), `sim/scenarios.gd` (`test_ambush`,
`test_cover`), `game/overlay.gd`, `game/soldier_layer.gd`,
`game/tree_layer.gd`.

**Both packs (decided 2026-10-15).** Line of sight applies to every battle
whose map has sight blockers (woods, buildings, rocks, cliffs): woods
hiding men is right for Rome too, and the AI's and the player's rules stay
one. Scenario key `los` 0 turns it off (tests; the maps' fire rules then
are exactly as before 2b). No pinned golden moved: the four flat-map
trajectory digests have no blockers (`vis_on` 0, nothing new hashed or
drawn), the campaign auto-resolves (campaign_sim hashes unchanged). What
changed without a pin: every woods, landform and settlement battle (the
determinism runs' final hashes, e.g. test_woods, ai_woods, siege_*,
bench_4000_hills). Rome rows with `cover`: javelinmen and slingers (and
their tiers and variants: the skirmishers); archers, the line and the
horse have none.

**The cover trait** (`cover` 1; West: buccaneers, cutlass men, native
warriors, native bowmen; Rome: javelin and sling lines; 0 everywhere
else). On a map with cover (`cov_on`: sight blockers and a cover unit):
- *Cover by kind* (`_cover_from`, per man, against the shooter's
  position): woods under him `COV_WOODS` 45 %, a rock or cliff cell 2 or
  4 m toward the shooter `COV_ROCK` 60 %, a building `COV_HOUSE` 50 %, a
  wall / tower / gate `COV_WALL` 50 % (a man on a walkway: the
  battlements' `WALL_COVER` as everyone, nothing more), a field's hedges
  `COV_FIELD` 25 % (on a settlement map woods, rocks and, since pathing
  phase C3, houses; walls and hedges there wait for 2c): that share of soldiers' missiles and balls about to
  strike him is stopped (`COVER_STOP`; after the trees' and the
  battlements' share everyone gets). Artillery shot (bolts, stones,
  roundshot) is not covered. (Pathing phase C0: on maps with obstacles a
  flat shot is stopped by the rock, house or wall itself, traced along the
  grid, and those kinds no longer roll for it: "Real cover" below.)
- *Going to ground* (`_cover_unit`, once a second): a cover unit with half
  its men or more in cover (`_cover_at`: woods or hedges under him, or an
  obstacle 2 m off eight ways or 4 m four ways), formed, not moving, not
  fighting, two checks running (`GROUND_STILL`) has gone to ground
  (`u_gnd`): `GROUND_STOP` 35 % of what still gets through is stopped as
  well, and an order that moves it (move, withdraw, a melee attack, the
  skirmish fall-back) first costs `RISE_T` 1.5 s getting up (the anchor
  waits). Gone to ground in cover it is concealed as in woods (below).
- *Firing from cover*: a cover unit's own trees within `COVER_PEEK` 12 m
  and a house corner within `COVER_PEEK_OBS` 5 m do not block its flat
  shots (line troops in a wood shoot through 8 m of dense trees at most,
  as before). For everyone, a rock or cliff within `LAND_NEAR` 5 m of the
  shooter or the target is cover, not a screen: the shot goes over it
  (and a cover man there takes the 60 %).
- Line troops get nothing new: in the same rocks a musket line loses
  exactly what it loses in the open (`--only=cover`).

**Line of sight** (`vis_on`; hashed `u_seen`, `u_rev`, `u_hid0`, `u_amb`,
`u_ambt`, `u_revt`; `u_seer` snapshotted only):
- *Blockers* (static grids built at setup from the map, so both lockstep
  peers hold the same; left out of snapshots): the veg grid's 4 m cells
  carry the trees' weight (`TREE_W`) and how far a field map's building
  (5 m), an outcrop (its height, 1.6-2.8 m) or a cliff (half its face)
  rises; a summed-area table answers "anything in this box". Walls, gates
  and a settlement's houses do not block sight (both sides know what stands
  behind a town wall and in its streets; they still stop shots; houses and
  rooftops are slice 2c's: measured, letting them hide units turned the
  fitted sieges over). The bare ground does not block sight
  (crests block fire, as before).
- *A sight line* (`sight_line`): from the observer's eye (1.7 m above its
  centroid's ground) to the target's body (1 m), 4 m samples: the trees
  along it add up past `TREE_BLOCK` (the first `VIS_PEEK` 12 m round the
  eye left out: a unit at a wood's edge looks out), or a building, rock or
  cliff rises above it (a rock within `LAND_NEAR` of either end does not).
- *Seen* (`_seen`, each unit once a second, staggered by index, fixed
  order): it shot within `REVEAL_T` 5 s, it is in contact; an enemy unit
  within `VIS_NEAR` 20 m (box to box) sees it; a unit in woods (its
  centroid) or a cover unit gone to ground in cover is seen only by enemies
  within `VIS_WOODS` 40 m; else any enemy unit with a sight line to it (the
  last one that saw it is asked first: cost only). A shot (a man's missile,
  a volley, an engine) reveals the shooter at once.
- *Hidden* (`hidden_from(u, side)`, the assassin's rule generalised): the
  view does not draw it for that side; the sim's fire at will and the
  batteries skip it; an attack order on it holds flat weapons (they cannot
  aim) while arrows and stones are lobbed blind at `BLIND_SPREAD` 200 %
  scatter; a melee attack order goes on.
- *Ambush*: a unit hidden at least `AMBUSH_HID` 5 s and then seen (it broke
  cover, an enemy came near, it shot) ambushes for `AMBUSH_T` 10 s: the
  first volley that reaches an enemy unit (`_missile_hit`) or the first
  contact with one (`_update_contacts`) strikes it with `AMBUSH_MOR` 200
  morale and `AMBUSH_DIS` 40 disorder at once (each unit at most once in
  10 s).

**Battle AI** (docs/AI.md): every target choice already went through
`hidden_from`; the army plan reckons the enemy centre and the gap between
the lines from the enemies it sees (all of them only when it sees none);
cover troops take the nearest cover within 30 m of their line slot
(`_cover_spot`: deployed there they lie in ambush on defence); line troops
ignore cover; foot with no enemy in sight while some hide probe the
nearest wood toward the enemy (`_probe`, `PROBE_PCT` 25 % a think).

**View.** Hidden enemies are not drawn (soldiers, markers; their canopy is
not thinned over them: `tree_layer` skips them); own cover units carry a
leaf at the marker's lower left (outline: in cover; filled: gone to
ground) and a closed eye while the enemy does not see them; a unit seen
after hiding gets a spreading ring (1.5 s); an attack order on a target
gone out of sight says "TARGET OUT OF SIGHT: HOLDING FIRE" (flat) or
"SHOOTING BLIND" (arcs) and draws no line to it; a blocked line of fire
shows "NO LINE OF FIRE" as before (now also for rocks and cliffs).

**Numbers** (`--only=cover` set pieces, 6 seeds, 90 s, a musket line 90 m
from 60 buccaneers in two ranks, a boulder line 3 m in front of them):

| buccaneers | killed by the line, holding fire | killed, duelling (line lost) |
|---|---|---|
| in the open | 25.3 / 60 | 22.5 (41.7 / 100) |
| behind rocks, standing | 15.3 | 13.7 (44.8) |
| behind rocks, gone to ground | 1.3 (hidden after 2 s) | 9.3 (46.0) |
| line musketeers there instead | 35.0 open = 35.0 rocks | 32.2 = 32.2 |

Ambush (`test_ambush`-like set piece): 100 native warriors hidden in a
wood 990 ticks, never aimed at; charging at 60 m they are seen as they
leave the trees; on contact the musket line takes -200 morale and wavers.

Cost (time per tick, HEAD -> 2b, same machine, one run each):
bench_4000_hills 4.42 -> 4.45 ms, the same with 45 % forest 4.50 -> 4.61,
bench_4000_city 4.23 -> 4.34, bench_2000 (flat, no blockers) 1.48 = 1.48.
Settlements: Punic siege, both AI, seeds 1-6: the attacker won 1 (5 draws)
with line of sight against 3 (3 draws) without; more defenders left.

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

### River crossings (as built, 2026-10-10)

A field battle fought over a river crossing (STATUS item 3, the user's
design of 2026-10-09; pontoon bridges are not in this build) gets the
crossing's own map. Code: `sim/mapgen.gd` (`river_geom`, `river_y` /
`river_cy` / `river_edge` / `river_reach` / `river_mouth`, `river_rises`,
`river_carve`, `_river`), `sim/terrain.gd` (the crossing's ground),
`sim/battle_sim.gd` (section "river crossings": `river_at`, `_update_ford`,
`FORD_SPEED`), `sim/scenarios.gd` (`river_units`, `camp(..., river)`,
`field_zones`, `crossing()`), `sim/battle_ai.gd` (section "river
crossings"), `game/terrain_layer.gd` + `game/terrain.gdshader` (water, the
ford), `game/city_layer.gd` (`draw_bridge`), `game/campaign/city_preview.gd`
(`for_crossing`), `game/campaign/battle_screen.gd` (the pre-battle preview),
`game/custom/` ("River crossing: none / ford / bridge"). Probe:
`tests/determinism_test.gd --only=crossing`.

- **Scenario key** `"river": {id, kind (0 ford / 1 bridge), seed, bank}`
  (campaign/cbattle.gd sets it when the attackers came over a crossing;
  `bank` is the sim side holding the far bank, the defenders). Field maps
  only (ignored with a city). Battles without it hash and play as before.
- **The map, frozen per crossing.** Everything comes from the key's seed
  (MapGen's own xorshift): the river's half width, a main bend whose apex
  (toward the far bank) is at the crossing plus a small wiggle, the
  crossing's place (within 40 m of the centre line), the ford's width, a
  low rise on each bank; the ground's relief (the region's kind) and woods
  are drawn from the crossing's seed too, round the field's centre (the
  terrain's own seed is not used). A ford and a bridge of one seed share
  their river. Generated in a canonical frame (the far bank at the top)
  and turned 180 degrees when side 0 holds it, so the attackers always
  come from their own edge (the test checks the turned map is exactly the
  same crossing). The same id gives the same map; the river, the heights
  and the crossing do not depend on the field size (the woods' thresholds
  do a little: they are quantiles over the whole field).
- **Numbers (chosen once):** river 20-40 m wide (`RIV_HW` 10-20 m half
  width); main bend 8-18 m over 320-480 m, wiggle 2-5 m over 100-160 m;
  ford 12-20 m wide (`FORD_W`, even); bridge 6 m (`BRIDGE_W`); river bed
  and ford 2 m below the plain rising to it over 16 m from the water
  (`RIV_DEPTH`, `RIV_BANK`: the bank's steepest grade ~19 %, under the
  steep-ground 20 %); a rise on each bank 3-6 m high, 45-70 m radius, its
  top 45-80 m back from the water (`RISE_*`); no trees within 6 m of the
  water or 40 m of the crossing either side; `FORD_SPEED` = `DITCH_SPEED`
  450 per mille.
- **Cells.** The water is `C_WATER` in obs (the sea's kind: nav 0, so no
  man steps into it and melee does not reach across it; missiles fly over,
  line of fire ignores it); ford and bridge cells are open ground. The rv
  grid (2 m, `R_WATER` / `R_FORD` / `R_BRIDGE`; static, hashed into
  `ter_hash` with obs and the way across) tells the ford. The obstacle
  machinery of settlement maps applies near the river (men kept out of
  blocked cells, the street squeeze, flowing slots, the stuck release).
- **The way across.** A small graph (MapGen, final frame) like a town's
  street graph: a row of nodes along each bank (14 m from the water, every
  30 m), the crossing's two mouths (5 m beyond the water) and its middle;
  edges up to 48 m with a clear 3 m line. Paths, routers (they run to their
  edge by it: a router on the wrong bank goes back over the crossing) and
  the AI's orders all use the existing `_plan_path` / `route_to`.
- **Ford** (`_update_ford`, after the men moved, units near the ford's box
  only): a man in a ford cell has his step cut to `FORD_SPEED` (a step cut
  short past the ford's corner that would end in the water leaves him where
  he was); a rider there loses his charge's momentum (`chg` and `u_mom` to
  0, `EQ_STOP` 100-like, `stat_ford_stop`); `u_frd` (per unit, hashed when
  there is a river) marks units with men in it, and such a unit's anchor
  (or one whose anchor is in the ford) keeps to `FORD_SPEED` and its
  momentum cap is 0. Horses wade too (unlike the town ditch). No cover in
  the ford: it is open ground (no trees, no works). Height: the men in it
  stand 2 m below the plain, so the bank's defenders strike down and shoot
  from height through the usual rules.
- **Bridge:** normal pace, one unit wide. A unit's path goes over its
  middle node; on the span the street squeeze closes its files to the 6 m
  (at least 4 files) and it opens out on the far side; units behind it
  queue at the mouth (`BLK_QUEUE`, flowing their slots into the space
  before it), so the army crosses as a column a unit at a time (AI battle,
  seed 12345: 78 squeezes, 515 unit-ticks queued, longest no-progress 109
  ticks; the ford's 14 m: 76 / 569 / 112).
- **Deployment** (`Scenarios.river_units`, applied by the sim at setup, so
  campaign and custom scenarios need no geometry): the far bank's holder
  is moved along its bank to face the crossing (its middle on the mouth,
  kept 10 m inside the field); any unit of either side whose box comes
  within 10 m (`RIV_KEEP`) of the water is moved straight back onto its
  own bank (a flank arrival included). `field_zones` ends each side's zone
  10 m (`RIV_ZONE`) short of the water on its side.
- **Fortified at the crossing** (`"fortified"` = the holder): its line is
  brought up so the camp's front rampart (`CAMP_PAD` 14 m beyond its box)
  stands `RIV_CAMP` 14 m from the crossing's exit, or `RIV_CAMP_DRY` 8 m
  clear of the water all along the camp if that is further (the ditch dry):
  14-18 m on the generated maps; `camp(..., river)` builds it with no
  sally gaps in the front facing the water and one in each flank (and the
  back's as before). The attackers come out of the ford or off the bridge
  under the rampart's archers into the ditch. A fortified army not at a
  crossing (or the other side fortified) gets the camp as before.
- **AI** (minimal; no knob or counter changed): the holder holds where it
  deployed with the camp's rule and time (`ai_hold` from the deployment,
  `_camp_keep`: `CAMP_HOLD`, until a third of its foot fights; its foot
  attack only enemies within `HOLD_REACT`), fortified or not (Easy, whose
  `CAMP_HOLD` is 0, advances as before). The attacker, while most of its
  foot (men) is on its own bank, skirmishes from there (its line
  `RIV_FORM` 30 m back from its own mouth while the skirmish rule holds),
  then sends its line to form `RIV_FORM` beyond the far mouth: every unit's
  way goes over the crossing (in column at a bridge), and the lines engage
  by the usual rule as they meet. No hint is needed for the paths.
- **View.** Water drawn from a 1 m texture of the river's own line (soft
  coverage, so the bank is smooth; the sim's 2 m cells lie within a metre
  of it) in the sea's colour and ripple with a light shore band; the ford
  as pale shallows over gravel with ripple streaks across the current; the
  bridge as a stone span with parapets, paving courses, cutwaters and
  abutments (`CityLayer.draw_bridge`). The campaign's pre-battle screen
  shows the crossing's map (`CityPreview.for_crossing`: ground, woods,
  river, ford or bridge, the attackers' way over) with "A river crossing
  by a ford / bridge: the defenders hold the far bank (, fortified at the
  crossing)". Custom battles: "River crossing: none / ford / bridge" on
  field maps (the river from the map seed; side 2, or the fortified side,
  holds the far bank).
- **Measured** (`--only=crossing`, crossing 7, battle seed 4242, both sides
  Average AI, 3000 ticks): 50 attackers on the far bank at tick 2100 over
  the ford (alive 599 / 787, undecided), 1399 over the bridge (455 / 630,
  the holder won), 1648 over the ford against the fortified camp (714 /
  671); nobody ever in the water (routers included); 60 cavalry charging
  through the ford at heavy foot standing at its exit reach them with
  momentum 0 and no impact (the same charge without the river: momentum 84,
  51 impacts). Setup ~40 ms (map, heights, way across). Field battles
  without the key: the golden digests unchanged.
- **Not modelled / gaps:** pontoon bridges (designed, STATUS item 3); the
  map follows the battle's sides (the far bank is the holder's), not the
  river's geography; the attacker's units cross as each gets there (no
  waiting to form the whole army on the far bank); the holder's cavalry
  may still charge over the crossing; the bridge cannot be broken or
  burnt; no balance run (crossing row in the equal-force harness: later).

### Heroes and agents (as built, battle side, 2026-10-10)

STATUS 8a. Characters are one-man units the scenario adds; the campaign
side (recruiting, attaching, wounds, ransoms) is docs/CAMPAIGN.md's. The
general's command aura is the model: generic row fields read in the
once-a-second aura pass, every rule skipped in a battle without characters
(`ch_on`), so every other battle plays and hashes as before.

**Rows** (`sim/unit_types.gd` `CHARS`, appended after the light artillery:
every other index unchanged; `"char": 1`, `"char_kind"` `UT.CK_*`; size 1;
`upkeep_pct` 0, `str_pct` 0; `char_pct` the auto-resolve bonus). Numbers
chosen once (Guard Cavalry / Agema 46 / 40 / armour 16 the hero
yardstick), not tuned:

| Key | Name | Kind | Price | Body | Aura (`ch_r`) |
|---|---|---|---|---|---|
| `hero_foot` | Champion | 1, foot, infantry | 1,500 | 46 / 40 / 16, shield 40, hp 600, light infantry's pace, `duel` +35 to-hit | 40 m: foot units' to-hit +15 % (`au_hit`), +3 morale a second (`au_mor`) |
| `hero_missile` | Master of Archers | 2, horse, missile | 1,500 | 46 / 40 / 16, hp 600, a 160 m bow (40 dmg, 40 ap, 60 shots, scatter 25) | 40 m: missile units' and engines' range +10 % (`au_rng`), scatter -20 % (`au_spr`) |
| `hero_cav` | Master of Horse | 3, horse, cavalry | 1,500 | 46 / 40 / 16, hp 600, charge 80 | 40 m: riders' (horse, camel, elephant) charge impact +20 % (`au_mom`), routing riders +40 a second (`au_rally`) |
| `hero_siege` | Master Engineer | 4, horse, cavalry | 1,500 | 46 / 40 / 16, hp 600, charge 40 | the whole side (siege works are spread out: no radius): ladder ticks 80 % (`au_climb` 25: 25 % faster), engine reload work 83 % (`au_reload` 20), ram / siege tower battering 75 % (`au_batter` 25) |
| `assassin` | Assassin | 5, foot | 800 | 30 / 20 / 3, hp 80 (a weak light man), `hidden` | none |
| `diplomat` | Diplomat | 6, foot, `unarmed` | 800 | attack 0 / 15 / 2, hp 100 | 30 m: any friendly unit's fear losses x 50 % (`au_steady`) |

Heroes: `char_pct` 6 (campaign auto-resolve), never break (`nobreak`,
morale 1000), riders `m_down` 1 (a lucky arrow), `fall_r` 60 m,
`fall_loss` 120, `fall_gain` 60. Agents `char_pct` 0. Unit icons 20 / 21 /
22 (`game/unit_icons.gd` draws them with `game/ui_icons.gd`'s crown,
dagger and scroll; the battle markers use `Overlay.draw_char_glyph`).

**Scenario key `"chars"`**: per side a list of `{"key", "name"}` (an Array
of two lists, or a Dictionary "0" / "1"). Setup (`BattleSim._char_units`)
adds each as a one-man unit after the scenario's own units (before the
towers and the dog packs), side 0's list then side 1's: heroes 25 m
(`CH_BACK`) behind the mean of their side's unit fronts, 8 m apart; the
assassin 15 m (`CH_REAR`) behind the side's rearmost unit beyond its left
flank, the diplomat beyond its right; facing as the side does; on maps
with buildings onto the nearest open ground. They never count toward
holding the field (`_check_winner`); the lockstep gives them to the player
of their side's first scenario unit. Result rows (only with characters):
every row `"surrendered"` (men taken prisoner); a character's row `"char"`
1, `"kind"`, `"alive"` (0 only if he was killed: withdrawn or still
standing is alive), `"ci"` (his place in his side's list); side totals
`"prisoners"` (enemy men this side took) and `"surrendered"`.

**State** (`_char_arrays`, hashed only with `ch_on`; snapshot-safe as
script variables): `u_char` (kind), `u_aura` (`AU_*` bits this second),
`u_hidden`, `u_cho` / `u_cht` / `u_chk` / `u_chf` (the act, its target,
its work ticks or an attempt's outcome, flags acted / tried / inside),
`u_chcd` (parley wait), `u_hold` (held by a parley until tick), `u_surr`;
per side `ch_sg` (a siege hero on the field this second), `ch_pris`.

**Auras** (`_update_auras`, sources: rows with `ch_r` and the siege hero):
a friendly unit (not the hero's own) within `ch_r` box to box gets the
kind's bit; several heroes of one kind do not stack. Effects: `_melee`
(`raw * (100 + au_hit) / 100`, plus the attacker's `duel`), the foot hero's
morale up to the recovery cap (as `cmd_mor`), `range_pct` / `_fire` /
`_art_fire` (range and scatter), `_impact` (power), the routing branch
(rally), `climb_pct` / `reload_pct` / `batter_pct` for the siege hero's
side (ladder step, `_update_artillery`, `_ram_hit` and the smash of a ram
or tower on the ground), and the steadying aura on the elephants' / camels'
/ dogs' aura losses, the routing-friends loss and artillery fright in the
rout test.

**A hero falls** (his man killed: `_remove` -> `_ch_fall`): units of his
side within `fall_r` lose `fall_loss` morale at once, the enemy's there
gain `fall_gain`. Battery fire at will adds 3,000 to a hero's score; tower
engines rank him with the ram's crew.

**Assassin.** Hidden (`u_hidden`) while he has not acted and no enemy unit
is within `SEEN_R` 10 m of him (box to box) unless he stands in woods;
hidden from that side's view and AI (`hidden_from`: markers, taps, the
AI's and the sim's target lists) and he never seeks a fight (his unit's
contact is cleared). Orders (lockstep inputs; `char_refusal` shared by the
sim, the view and the AI; any unit order to him calls his act off):
- `ORDER_SABOTAGE` 21 {unit, eg | gate}. An enemy engine group (not a
  tower's): he walks (runs) to its nearest engine not wrecked; within
  `SAB_R` 6 m of it (the crews stand round it) he wrecks one every
  `SABOTAGE_T` 5 s (`stat_sabotage`; abandoned ones too). A shut gate
  (attackers only): he walks to its outer face; within 5 m he is over the
  wall beside it, onto its inner face (or he is inside already), and
  unbars it in `SAB_UNBAR` 15 s there (the ladder men's UNBAR time).
- `ORDER_ATTEMPT` 22 {unit, target: an enemy character or a general's unit
  whose command has not fallen}; once a battle. He walks to within
  `ATTEMPT_R` 3 m of the target's nearest man and rolls once (the sim's
  RNG): `ATTEMPT_PCT` 40 % that man is killed (a general's unit: the
  general, `_cmd_fall`: the army's command loss and his aura gone),
  `ATTEMPT_WOUND` 30 % wounded (half his row's hit points), else nothing;
  `u_chk` keeps 1 / 2 / 3. A wound (2026-10-13) marks the target
  `CHF_WOUNDED` in his `u_chf` (hashed with the character arrays): a
  hero's aura then reaches half as far (`_ch_reach`: half his `ch_r`, the
  aura pass and `_ch_near`), a general's command is gone for the battle
  (`u_cmdgone` set: no `cmd_mor`, no rally, `_cmd_near` skips him, and no
  `cmd_loss` later; he is no longer an attempt target). Only an attempt's
  wound counts, not hit points lost otherwise.
- Acting reveals him for good; `CAPTURE_N` 3 enemy men formed or fighting
  within `CAPTURE_R` 1.5 m of him (once a second) take him (he dies).

**Diplomat.** Unarmed (never seeks a fight); his steadying aura above.
`ORDER_PARLEY` 23 {unit, target}: an enemy unit routing or below
`PARLEY_MOR` 25 % of its row's morale (a garrison on a wall only while the
plaza is being held, `cap_t` > 0; not a character, a tower or a pack), and
not within `PARLEY_WAIT` 30 s of a refused one. He walks to within
`PARLEY_R` 20 m (routers within `PARLEY_SEE` 80 m of him stop for his white
flag and do not rally meanwhile); then for `PARLEY_T` 5 s it, he and every
unit within 20 m of either hold (`u_hold`: no melee, anchors and routers
stand; missiles still fly, so only missiles can kill him then); then one
roll: `PARLEY_PCT` 60 % routing / `PARLEY_PCT_W` 35 % wavering (0 if it has
recovered) it surrenders: its men leave the field (`GONE_SURR`, `u_surr`,
the unit `U_LEFT`; `ch_pris` of his side += men; a general's
unit taken: `_cmd_fall`); else it fights on.

**View**: markers with a gold rim and the glyph (our hidden assassin
faded, the enemy's not drawn and not tappable), a white flag while the
diplomat goes to parley, a ring filling over a parley / sabotage /
unbarring; Sabotage / Attempt / Parley buttons in the HUD's order row
(`hud.char_buttons`, with the other order toggles) for a selected assassin
or diplomat, keys Shift+B / T / Shift+P (`game/controls.gd`): press, then
tap the target; a key no selected character can take, or a refused
target, is flashed with `char_refusal`'s reason; the enemy's hidden
assassin is not drawn by the soldier layer either (`viewer_side`: men of a
unit `hidden_from` it get the off-field state, both GPU and CPU paths); the unit book's own page per row and a "Heroes and agents"
page; the custom battle setup a toggle per character per side (their
price counts against the funds). Battle AI: docs/AI.md 27.

- Done 2026-10-13: the soldier layer's hidden-assassin skip, the HUD
  buttons and keys, a wounded hero's half aura and a wounded general's
  lost command, the Skilled AI's sabotage (docs/AI.md 27).
- Not built / gaps: prisoners only by parley (no capture of routers
  otherwise); sabotage reaches batteries and gates only (not rams or
  siege towers: the sim has no such target).

### Reinforcements (as built, 2026-10-13)

STATUS item 7, first half (owner: "so we can get a third army into the
mix"). Before, `CData.BATTLE_SIDE_MAX` 24 field units a side capped a
battle: `CBattle._build0` stopped adding units at 24 and the campaign rules
bounced an army that would push a side past it ("battle side full").

- **No bounce** (`campaign/crules.gd`): every army that would join a
  battle joins it (moving in, `_join6` / `join_battle`, support by range or
  radius, every besieger of an assault, every army of the side at a
  storming). `BATTLE_SIDE_MAX` is now the field slots: `CBattle.field_split`
  takes a side's armies in join order (b "att" / "def", then "reinf"), each
  army's units in index order; the first 24 units with men take the field,
  the rest are **reserves**, in that order. The pre-battle card says
  "Arriving: n units" (`battle_screen.gd`, card `on` 2).
- **Where they wait.** Field battles: a reserve stands at its army's map
  edge (its `b["edge"]` sector, turned as the version 5 placement), else
  its side's own end; one `_layout` per edge group (`_reserve_groups`).
  Settlement battles (`_settlement_reserves`): the attackers' at the
  attackers' map edge behind their army, the defenders' on the plaza
  (agora) inside the walls, 14 m apart, facing the main gate.
- **In the sim** (`sim/battle_sim.gd`, section "reinforcements"): a
  scenario unit with `"reserve": 1` is set up at its spot and put off the
  field (`U_RESERVE` 5: no men alive, its men `S_OFF`, its engines
  `E_RESERVE` 3, a wagon it carries stays with it), like the war dog
  kennel: unit and soldier counts are fixed at setup, so arrays never
  grow. Once a second, before the AI thinks, for side 0 then 1, while the
  side still fights (no army withdrawal, its AI not withdrawing) and the
  battle is undecided, the side's first reserve (unit order) **arrives**
  when the side's units on the field (ready or routing; not characters,
  dog packs or tower engines) are fewer than its slots `rsv_cap` (its
  units on the field at setup: 24, or 24 + the garrison) and `REINF_GAP`
  5 s have passed since its last arrival; or, from `REINF_TIME` 120 s,
  with the field full, one every `REINF_SLOW` 10 s up to
  `REINF_FIELD_MAX` 30 on the field (6 over the 24 slots). It enters
  formed in its set-up formation, with the morale it was set up with
  (a forced march's cut stays). A pure function of the sim state: no new
  lockstep input. Hashed only when the battle has reserves (`rsv_on`):
  `rsv_cap`, `rsv_last`, `rsv_stop`, `u_arr` (arrival tick); every field
  battle without reserves hashes as before (the four goldens unchanged).
  Snapshot / restore carry them (script variables).
- **Control.** A reserve is its army's faction's unit (`CBattle.controllers`,
  the multi-human model); the battle AI takes an AI side's arrivals with
  its next think (`u_ai` reset to the line; `_issue_line` gives them slots,
  in the engagement they attack). AI strength counts a side's open reserves
  (`BattleAI._strength`: a side with reinforcements coming is not "clearly
  lost"); the start strength counts them from their arrival.
- **Outcome.** A side with reserves to come still fights (`_check_winner`).
  `result()` reports a reserve that never arrived with all its men
  remaining (`"reserve": 1`), so its campaign rows are killed 0, n
  unchanged. Auto-resolve counts every army at full strength as before
  (`CBattle.strengths` never capped). An army withdrawal (`ORDER_WITHDRAW_ALL`)
  stops the side's arrivals.
- **View.** Reserve cards are hidden until they arrive; the HUD shows
  "Arriving: n units" (and the enemy's) and a 3 s "Reinforcements: <Adj>
  army" note (scenario unit key `label`, view only); their engines and
  wagons are not drawn while off the field.
- **Cost.** `bench_4000_reinf` (`Scenarios.reinf_battle`: 36 units, 24 + 12
  reserves, against 24): 3.58 ms a tick mean, 3.89 engaged, against
  bench_4000's 3.13 (3.07 before the change; same battle, noise).
- **Open:** the ambush stance (item 7's second half); a battle of many
  armies sets up every reserve's men in the arrays (no cap on armies); no
  choice of which units wait (join order).

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
of the unit if it is a human of the battle, other units of a side with
players that side's lowest player friendly to them; `CBattle` "controller")
live in the lockstep layer and are hashed with the sim. A sim
order counts only from the player commanding the unit at its frame; an army
withdrawal withdraws only the issuer's units; a player not taking part
orders nothing. Units of a human who is not there at the start are held for
them by the host; admitting that player gives them back (unless they chose
"Join, X keeps my army").

**Gifts** are inputs (`C_GIFT unit to`), valid only from the unit's
commander to a player taking part on the unit's side; gifting back is the
same input. The selected units' action row has "Gift to <ally>" (several
team-mates on the side: "Gift to...", a picker of them).

**Pause and speed by vote.** Requests and answers are inputs. A request
applies at once if only one player takes part; otherwise it is a vote of
the players taking part (hashed yes / no bit masks): the requester counts
as yes, asking for the same thing (tapping Pause, or the same speed) or
Accept on the chip is yes, Decline is no; it carries when more than half
of the players taking part say yes and is cleared (the state kept) when
that can no longer happen (a tie keeps the current state); a drop
re-counts it. With two players this is the old rule: the other player asks
for the same thing or taps Accept on the chip under the control (the requester's colour and
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

**Several humans (N-player campaigns, 2026-10-13).** Every human with an
army in the battle, on either side, may join, and every alive human on
the team of a side's lead faction without an army there (a guest:
`CRules.battle_guests`, given units by a team-mate; `guest_side` passes
their sim side to `Lockstep.setup`, which keeps each player's side in the
hashed `p_side`). The relay admits up to 8. Each player commands their
own faction's units (`controller`); a side with a player is not the battle
AI's in a live battle (`CoopSession.live_ai_sides` trims the scenario's
`ai_sides`; the AI takes a side over only while none of its players takes
part, as in head-to-head custom battles); units of a player who is absent
are held by the keeper, a player of the same side taking part (the host
if it is one, else the first by faction index). Gifts go to any team-mate
taking part on the same side. Votes are by majority (above). The view
fights from the player's own side (`player_side`); the HUD strip lists the
players (colour, name, "(enemy)" for the other side), unit cards carry a
band in their commander's colour when a side has several players, and the
lobby lists every eligible human. Tested: `tests/lockstep_test.gd` (three
peers, 13), `tests/live_team_e2e.py` (three headless clients through the
relay), `campaign_test` `_team_battles`, Go `TestRoomManyPeers`. Not
built: per-army battle AI for AI allies on a side with players (the sim's
AI commands whole sides, so they stay with the side's lowest player);
three or more players in custom battles (seats 0 / 1).

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

### Distribution (agreed and built 2026-10-17)

The game ships on itch.io as a web build (HTTPS, any origin) and as desktop builds (Windows, Linux, macOS) that carry the game server (`scserver`) beside the game. The game server is also a standalone Docker image anyone can run (API and live relay, no web build); There is no public relay: the default server (built into the client so a fresh install works) is one self-host among many. Online campaigns and live battles always go through a game server: the default one, a friend's by address, or one the player hosts from the desktop build ("Host a server"). The server holds no rules (see SERVER.md); the client refuses a server built for another `CState.VERSION`, and a seat token goes only to the server it was issued by. Browsers can only call HTTPS servers (mixed content), so an itch.io player needs the default server or a self-hosted one behind a domain; desktop players can use plain HTTP on a LAN, a forwarded port or a tunnel such as Tailscale. A server serves other sites only when its owner lists their origins (`SC_ALLOWED_ORIGINS`); by default it answers its own origin.

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

**Fire and blast effects (view only, 2026-10-09)**: nothing here is sim state
or in any hash; it is all read from arrays the view already has. A fire
missile in flight (its slot's `pr_ak` has `fire` > 0: fire arrows, javelins,
pots) draws a hot head and a flame tail fading to smoke: the projectile
shaders get the slot's kind (GPU: texture block 8 and a `fire_mask`
uniform; CPU: +16 on the missile's flag) and enlarge the quad behind the
head. `overlay.gd` walks the sim's landing buckets once per tick, follows the
fire, explosive and stone missiles, and a slot that is gone landed at its
aim point: a fire missile leaves 0.4 s of sparks and flame and 2 s of drifting
smoke, an explosive stone a flash, a ring out to its blast radius (`m_blast`
+ the kind's `blast`) in 0.5 s and 3 s of smoke, a plain stone a dust puff.
The effects are one capped list (64, blasts kept over sparks; a volley landing
in one 2 m cell gives one effect), advanced by the view clock so they fade
while the sim is paused, and drawn in the overlay's single `_draw` pass. A
unit with `u_burn` > 0 carries a flame on every 7th man (at most 12) with a
thread of smoke, and burning gates, engines and equipment send up a smoke
column. Cost on a 4-battery, 2-archer-unit fire test: about 0.8 ms of view
time per frame at the cap.

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
- Ordering into crowds (2026-10-13): with units selected, a plain tap on one of
  our own units is a MOVE to that point (a "Move" flash); a long press
  (350 ms; a held click on desktop) or a double tap on it selects it
  (tight pick: its marker or footprint only), Shift / Ctrl-click adds as
  before; a tap on an enemy attacks; with nothing selected a tap selects.
  Drag with a selection always draws the order line (box select only with an
  empty selection or Shift). With a selection the long press selects instead of
  opening the unit book (cards and enemy units still do). Constants and rules:
  top of `game/battle.gd`.
- Campaign battles have no field result panel: a 1.5 s Victory / Defeat / Draw
  banner (tap to skip), then back to the campaign's own result screen. Custom
  battles and the sandbox keep the panel.
- Keys: Space / P pause, + / - speed, 1-4 and Ctrl+A group selects, R run,
  H halt, F fire, K skirmish, Shift+D deploy, Y refill, O orders overlay,
  W A S D / arrows pan, Page Up / Down zoom, B book, F3 readout, F11 fullscreen.
- Mouse (Total War: Rome scheme, 2026-10-13; real mouse only, touch unchanged):
  left click a unit selects it (Shift / Ctrl adds or removes), left click on
  empty ground deselects, left drag draws a selection box (Shift adds);
  right click on the ground moves the whole selection there keeping its
  shape (`_group_move`: the group's centre goes to the point, each unit keeps
  its offset from it, turned with the group if the travel is a big turn;
  one unit: a plain move), right click on an enemy attacks, on one of ours
  moves to that point, double right click runs / charges; right drag lays
  the selection out along the dragged line (the drag-to-line rule of touch:
  left to right in current order, files fitted to the width, facing
  perpendicular toward the side dragged from; preview as for touch); in the
  deployment phase the same buttons place units. Middle drag pans (right
  drag pans when nothing is selected), also keys; wheel zooms. A unit's book
  page is on the card / B key. Gates, engines, equipment and the targeting
  modes (Release, Sabotage...) still take a left click.
- Two-finger tap deselects all (touch, battle only): both fingers down within
  120 ms, both up within 250 ms of the first touch, each moved under 12 px;
  pinch / pan motion cancels it (`TWO_TAP_*` in `game/battle.gd`).
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

### Sprite pipeline (step 1a, 2026-10-13)

Owner's direction: all art made by us from text, consistent across frames
and angles because it comes from 3D. `tools/sprites/` (README there):
`spec.json` describes units as parts lists over a shared rig; `build.py`
(Blender 5.2, headless, EEVEE on the GPU) builds each part as a chunky
low-poly mesh (bmesh boxes with bevels, spheres, cylinders, cones, a curved
scutum), rigidly parents it to a bone (no skinning), keyframes the actions
from pose functions shared by every humanoid (and one set for horses: a
rider's bones live in the horse's armature, prefix `r.`), and renders each
frame orthographic at 24 px per metre (`ATLAS_PX_PER_M`) in three passes:
**shade** (toon lighting in three flat bands with an ambient floor, a key
light fixed in camera space from the top left, a mild lighter-when-higher
term; faction parts white), **mask** (R primary, G secondary, B accent) and
**pattern** (the cloth check). `pack.py` (stdlib Python) hardens the alpha,
adds a 1 px dark outline, crops each action to its frames' union, packs one
shade + one mask sheet per unit (mask A = 255 - 128 x check, never 0) and
writes `assets/sprites/manifest.json` (frame rects, anchor = the man's
feet, fps, loop, palettes). Recolour: `rgb = shade x ((1 - r - g - b) +
r x mix(primary, pattern, check x pattern_k) + g x secondary + b x
accent)`.

Built: Heavy Swords (Roman: curved scutum with rim and boss, crested
helmet with neck guard, plated shoulders, gladius), Spearmen (hoplite:
round shield with rim and emblem, Corinthian helmet with a tall crest,
2.9 m spear), Shock Cavalry (horse with a saddle cloth and trim, rider
with crested helmet, round shield, 3.6 m lance). Actions: idle 1, walk 6
(leg and arm swing, shield bob, body bob), attack 4 (wind-up, twist and
thrust, recover), death 3 (falls on his back; the horse rolls on its
side). Palettes: Rome red / gold / bronze; Carthage white / Tyrian purple
/ silver; the Gauls green / ochre / iron with a blue check on cloaks and
saddle cloths. The same models render isometric: the Heavy Swords walk at
32 degrees elevation in 8 directions (`iso_heavy_swords_*`), so a bird's-eye
view is a camera change, not new art. Total output 184 KB; a full build
takes about 14 s. Preview: `tools/sprites/preview/preview.tscn` (1x, about
12 px a man, about 7 px a man, rotated blocks, iso). Wired into the battle
in step 1b (below).

### Sprite pipeline (step 1b, 2026-10-13)

The rendered sprites are in the battle. **Art fixes** first (owner's
notes on 1a): the horse is chunkier from above (broader barrel, chest and
rump, thicker neck and head, a larger muzzle and ears) and its legs splay
outward as they swing, so hooves show beside the barrel; the death no
longer rolls the horse onto its side (which read as a standing horse in
profile) but sinks it flat on its belly, legs splayed out both sides, neck
and head laid down on their side, the rider thrown clear. (1a built the
right legs on the left legs' bones, so they moved as one pair; fixed: the
gait is diagonal now.) Infantry heads and shields are a few % bigger to
read at 7 px a man. A fourth set, **Pikemen**, is the Spearmen with a
5.6 m sarissa and a smaller shield.

**Atlas.** `pack.py` packs every set's frames into one pair,
`assets/sprites/atlas_shade.png` and `atlas_mask.png` (1024 x 332; every
frame starts on a 4 px step with a 4 px gutter so mip levels up to 2 never
mix frames; imported lossless with mipmaps). It also generates
`game/sprite_atlas.gd` (the frame table, the palettes) and
`game/sprite_frames.gdshaderinc` (the same table as shader constants).
The table: per set and action (idle, walk, attack, death) frame 0's rect
(x0, y0, w, h) and (anchor x, anchor y, step, frames); frame k is at x0 + k
x step. The manifest keeps the same numbers for tools.

**Which set.** A display field on the unit rows, `sprite_set` (0 = the
procedural sprite, `sprite`): 1 Heavy Swords for the heavy and light
lines, 2 Spearmen for spear lines, 3 Pikemen for pike lines, 4 Shock
Cavalry for every horse row (cavalry, missile cavalry, generals). Archers,
javelins, slingers, camels, elephants, dogs, artillery crews and engines,
wagons and characters keep their procedural sprites until their own sets
are built (`tools/sprites/README.md`).

**Palettes per faction**, not per side: Rome, Carthage, Macedon (saffron,
crimson), Epirus (violet, cream), the Greek League (sky blue, white),
Syracuse (teal, gold), the Iberians (undyed white with a crimson check),
the Gauls. A campaign battle passes CBattle's `unit_faction` to the
battle; a unit without one takes its side's (the most common among its
side's units, else the faction whose roster alone has its units, else Rome
for side 0 and Carthage for side 1: scenarios and custom battles). The
side shows by the unit markers and the selection tint, not on the men.

**Shaders** (`game/soldiers.gdshaderinc`). An atlas man's action comes
from his state: dead, the death's last frame (the corpse layer); knocked
down, its middle frame; fighting, or his unit shooting while he stands,
attack; moving (more than 2 cm a tick) or routing (1.6 x faster), walk;
else idle. The frame comes from the view clock `now` (ticks, interpolated:
the soldier materials get it with `alpha`) plus a phase fract(index x
0.618), so a block does not step in lockstep; nothing is written to the
sim. The texture path reads the table from a uniform array (`frame_tab`),
the unit's set, palette and shooting from its flags (bits 12-15, 16-19,
3); the CPU-fed path from constants (an if chain, as `sprite_rect`), with
INSTANCE_CUSTOM.z = set + 16 x palette and .w = the instance's index. The
fragment stage recolours by the mask from a 4 x 8 palette texture with the
1a formula and folds the state tints (routing, knocked down, under fire,
selected, corpse) into one multiply-add. Still one MultiMesh draw call per
soldier layer; the probe is unchanged. Rendering only the soldiers of one
frame offscreen on both paths gives identical pixels (sub-pixel edge
differences far from the origin predate the atlas). Frame time at 4,000
men is unchanged within noise on this desktop; Graphics Low keeps the
animation (holding it measured no cheaper).

**Missile sets (step 1c, 2026-10-13).** Four more sets on the shared
humanoid rig, each with a pose variant (spec `pose`) replacing the shared
attack: 5 **Archers** (cloth tunic, coloured cap, quiver, bow in the off
hand; attack = draw, full draw, release, recover; the string is a V to the
drawing hand and the arrow is aimed at the bow, both re-aimed per frame by
build.py "cord" parts), 6 **Javelinmen** (leather cap with a band, small
round shield, two javelins in the off hand and one in the throwing hand;
attack = wind-up behind the head, step, release (the javelin vanishes),
follow-through), 7 **Slingers** (the javelin body without shield or
javelins; cord and pouch on a new `weapon.R` bone that whirls overhead for
the shot; a stone bag), 8 **Gastraphetes** (the archer body behind a stocked
belly-bow held in both hands; a lean and a kick). `sprite_set` 5-8 sit on
the archer, javelin, slinger and gastraphetes base rows (tiers, Cretans and
faction rows inherit); camel archers, hero rows, dogs and engines stay
procedural. Testing aid: `--factions=syracuse,carthage` sets the two sides'
palettes in a sandbox battle.

**Beasts, engines and wagons (step 1d, 2026-10-13).** Seven more sets and
three props. 9 **War Elephant** (a rig of its own: barrel body, thick legs,
a three-bone trunk curled forward, flapping ears, tusks; a faction
caparison and bronze frontlet, a howdah with shields hung on its sides, a
driver on the neck and two javelin men standing in the howdah; build.py
units may carry several `riders`, each with its own pose (`stand`,
`fall: roll`); walk = a slow lateral amble with ear flap, trunk and tail
sway; attack = trunk up and across, then the head down for the tusk gore
with a lunge, the crew throwing; death = the whole beast, head and trunk
included, rolls onto its side, legs out, the crew rolled off with the
howdah; amok reuses the walk at the routing rate), 10 **Camel** and 11
**Camel Archer** (the horse's animation on a camel rig: hump, long neck;
turbaned rider with sword and shield, or the archers' rider with the
archer pose), 12 **Engine Crew** (the javelin body without weapons; attack
= cranking the winch; on every battery, tower engine and wagon crew row),
and three **engine sets** on a new display field `engine_set`: 13 Bolt
Thrower (tripod, stock and slide, two springs with bronze washers, arms, a
V string to the claw, a faction plate; also the tower bolt thrower), 14
Stone Thrower (onager: wheeled frame, skein, one arm with sling and stone,
padded faction buffer, spoked winch; also the tower onager), 15 Scorpion
(the bolt thrower at 60 %, carried shoulder high on two poles, legs
folded, while it moves). Engines: walk = packed / carried; wrecked = the
death's last frame (toppled, an arm snapped, scorched); the **firing cycle
follows the sim**: the view gives each working engine of a shooting unit
a state 9-12 from its `e_reload` (0 loaded, 1 just shot, 2 / 3 winding),
so the release frame shows on the tick the bolt or stone leaves (view
state only, read from the sim). An abandoned engine is a state of its own
(8: idle frame, darkened, on the corpse layer) instead of drawing as a
wreck. Texture path: flags bits 20-23 = engine set; CPU path: the engines'
runs carry engine set + 16 x palette in INSTANCE_CUSTOM.z; the procedural
engine sprite stays the fallback (engine_set 0). **Props** (`atlas.props`:
hand cart, wagon, draught horse; fixed colours, no faction mask) are
packed in the same atlas but drawn by `game/overlay.gd` from the shade
sheet (a child node with mipmaps under the overlay's lines; `PROPS` in
sprite_atlas.gd): the cart or the wagon (walk frames while it moves, the
wreck), its horses ahead (a dead horse lies, the death's last frame); the
stock bar stays. The atlas is 1024 x 1184 (15 sets + 3 props): the 4-bit
set fields are full, so a further set needs a wider field (palette and set
share bits 12-19). Still procedural: dogs, characters, and the siege
equipment drawn in overlay.gd (ladders, ram, siege tower, mantlets: the
next step, as props like the wagon).

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

### The Caribbean pack: ships, pirates, cover, asymmetry (agreed 2026-10-14)

The West pack's first setting is the Caribbean and Gulf, 1650 (slice 1 as
built: STATUS "The West pack, slice 1"). The user's decisions on
2026-10-14: sea battles are **real time with the wind**; pirates are
**raiders with havens**; armies cross the sea by **embarking on fleets**.
Battle balance waits until ships, cover and asymmetry are in.

**Fleets (campaign, West pack only; Rome keeps its sea lanes).** Ship
rows are data (pack "west"): sloop (fast, few guns, carries 1 unit),
brigantine, frigate (carries 3), galleon (slow, heavy, a treasure hold,
carries 6), ship of the line (England / Dutch top tier), and piraguas /
war canoes (Miskito, Itza: coastal water only, fast, carry 1). A fleet is
a campaign piece on sea cells with the overworld's continuous movement.
Its reach per turn depends on the heading against the map's baked wind
(`relief_west` WIND: the trade winds from the east), so running west is
quick and beating east is slow; integers only, from the grid's sea cells.
An army boards a fleet in port or on a coast cell beside it, up to the
fleet's capacity, moves at the fleet's pace and lands on any coast cell
(a landing takes the rest of the turn). Enemy fleets in reach intercept;
transports in a lost sea battle are sunk or captured with the men on
board. Ports build and repair ships (a shipyard chain); a long time at sea
costs a little crew (scurvy).

**Trade and the treasure fleet.** Each port's trade income travels by
sea: an enemy fleet blockading a port (on its approach cells) cuts it and
takes a share as plunder. Every few turns Spain's flota gathers galleons
at Veracruz and Portobelo, meets at Havana and sails off the map east;
whatever arrives pays a large sum, and whatever is intercepted is the
richest prize on the map.

**Pirates (the Brethren of the Coast).** Income is mostly plunder:
intercepted trade, blockade shares, the flota, and **sacking** coastal
towns (a landing and a battle; a won sack takes gold and wrecks buildings
without occupying). They hold a few **havens** (Port-de-Paix for Tortuga)
where crews recruit cheaply. A pirate faction is not eliminated while it
has a ship. **Infamy** rises with every sack and prize: more recruits
flock in, and the nations hunt them harder. **Letters of marque**: a
nation can hire them by treaty (privateering), so they leave that nation
alone and plunder its enemies at a bonus. AI pirates prefer weak, rich
targets.

**Sea battles (real time).** Ships are sim pieces with fixed-point
positions and headings that sail by the battle's wind (from the campaign
wind at the spot), with points of sail, tacking and stays. They fire
broadsides from their sides at range (round shot for the hull, chain for
the rigging, grape for the crew), take hull / rig / crew damage, and
grapple to board; a boarding becomes a deck melee in the existing soldier
sim. Forts and shore batteries fire on ships; ships can bombard shore
units in coastal land battles. Auto-resolve stays available and is fitted
to the real-time results.

**Cover (battle, slice 2b).** A unit trait `cover` (natives, buccaneers,
frontier militia, skirmishers): in woods, rocks, walls, fields and
buildings those men go to ground behind what is there and take far fewer
hits (missiles and guns), and they fire from cover. Line infantry (Spain's
tercios, English and Dutch foot) do not take cover: they stand in
formation, and their strengths are volley discipline, morale and pike
protection. Line of sight: woods, rocks and buildings block sight and
shots, so ambush works.

**Asymmetry (to design per faction).** Spain: rich, forts, tercios, the
flota, slow galleons. England and the Dutch: navies, trade, ships of the
line, strong guns. France: buccaneers, alliances with natives,
privateers. The Brethren: the pirate loop above. Itza: jungle, cover,
ambush, a lake fortress, no need of ships. Miskito: canoe raids, English
muskets by trade, friends of pirates.

### Sea battles (as built, N3a, 2026-10-14)

The "Sea battles (real time)" paragraph above, first playable version
(campaign hand-off: CAMPAIGN.md "Sea battles fought (N3a)"). Rule of cool on
real seamanship: ships sail by the wind, beat to windward in tacks, fight
with broadsides and boarders, strike their colours; speeds are about twice
a real ship's and ranges compressed so a frigate duel decides in a few
minutes.

- **A sibling sim, not a mode of BattleSim** (`sim/sea_sim.gd`, types
  `sim/sea_types.gd`): a sea battle has a handful of ships and no soldiers,
  so it shares none of BattleSim's per-man arrays, maps, engines or AI;
  apart, every land battle stays byte-identical (Rome goldens untouched).
  It keeps the same discipline and the interface the lockstep layer uses
  (`sim/lockstep.gd` picks it for a scenario with `"sea": 1`): integers and
  `FixedMath` (1 m = 1024, angles 0..1023), its own xorshift RNG, ship-index
  order, orders queued by (tick, player, seq), `state_hash()` over every
  state array, `snapshot()` / `restore()` of every script variable (the land
  grid rebuilt by `setup`), `result()`; a tick is 0.1 s.
- **Ships** (rows by the campaign keys: sloop, brigantine, frigate,
  galleon, ship of the line, war canoe): length and beam, top speed (sloop
  9.5 m/s ... galleon 6.0; canoes 9.8 rowed), rate of turn (sloop 9 deg/s
  ... galleon 3.4, slower without way), the no-go angle off the wind (sloop
  42 deg, brigantine 50, frigate 62, ship of the line 66, galleon 70; canoes
  none), the speed % needed to tack, guns a broadside (4 / 7 / 15 / 20 / 35
  / 1), shot weight, range (220-300 m; chain 80 %, grape 40 %), hull, crew,
  rigging, reload (10-17 s with a full gun crew), draught (deep ships run
  aground on shoals), boarding quality. State per ship: position, heading
  (x16), speed, sail (stop / battle 75 % / full), hull, crew, rig, troops
  aboard, gunnery and boarding quality, morale, mode (hold course, sail to a
  point, engage, board, flee, hold a heading), each broadside's loaded shot
  and reload, grapple, fire, captor.
- **Wind** from the scenario's bearing and strength; every 30 s it shifts a
  few degrees (seeded, within 35 deg of the start). **Points of sail**: no
  drive in the no-go zone, 45-80 % close-hauled, best (100 %) from the beam
  to the broad reach, 82 % dead before it; leeway pushes everything
  downwind. **Navigator** (every ship, any mode): straight to the goal when
  it can lie the course, else close-hauled on its tack to the layline then
  the other tack (the view draws exactly these legs); it turns through the
  wind when it has the way (tacking), else wears round; caught in irons
  without way the bow falls off; probes ahead turn it from land, shoals (deep
  ships) and the field's edge.
- **Broadsides**: a side (port / starboard, a 42 deg arc either side of the
  beam) fires all its working guns (fewer as the hull goes) when loaded and
  an enemy bears in range of its shot, the ordered target first, else (fire
  at will) the nearest, never through a friend. Each gun hits at 88 % x
  target size x (1 - 0.7 x range / max range) x gunnery quality. Round shot:
  hull, splinters among the crew, a little rigging, 0.5 % a hit to start a
  fire; chain: rigging (speed); grape: crew. Raking (from within 32 deg of
  her bow or stern) kills 2.5 x. Reload slows with too few men at the guns
  (4 a gun, both sides). A fire burns the hull until the crew puts it out (14
  % a second at full crew); each second 1.5 % (3 % after 30 s) the magazine
  goes: she blows up, her neighbours within 70 m are holed, lose men and
  catch fire. Hull 0: she sinks.
- **Boarding**: ordered (or the AI) to board, a ship sails alongside,
  matching speed; within (lengths x 0.4 + 8) m at under 3.5 m/s relative
  speed she grapples, both stop and drift together; each second the
  boarders (crew x boarding quality + troops x 1.2) and defenders (the same,
  x 125 % on their own deck) lose 5-8 % of the other's strength; the
  defenders are taken under 40 % of the boarders, the boarders thrown back
  under 50 % of the defenders or after 60 s. The prize gets a prize crew
  (an eighth of the captor's, at most 40). A struck ship laid alongside is
  taken at once. **N3b hook**: scenario `"deck": 1` stops the sim resolving
  a grapple; `deck_request()` lists the grappled pairs (ships, sides, crews,
  troops, qualities: the data a deck melee in BattleSim needs) and the
  order `O_DECK` (boarder, target, won, crews left) applies the melee's
  result, through the lockstep like any order.
- **Morale and the end**: hits lower morale by the share of hull and men
  lost (raking more), a ship struck, sunk or taken nearby by 8-12; quiet time
  restores it. A ship strikes at 0, or with under 18 % of her crew (or 12 %
  hull and a wrecked rig) with an enemy within 400 m; struck, she stops and
  is out of the fight. A side with no ship fighting has lost (fled ships
  escaped); at the time limit the fighting power left decides (ties: the
  defenders). The loser's struck ships are taken; the winner's hoist their
  colours again.
- **Battle AI** (each ship every second, staggered): run for the edge away
  from the enemy (preferring a fast point of sail) when beaten (hull < 28 %,
  crew < 32 % or morale < 22 and the enemy stronger); else the nearest
  weakest enemy (kept unless another is much better); board when its
  boarding strength (with friends already boarding her) is 1.6 x hers and
  she is close or crippled (not a ship outrunning it); else engage: beyond
  ~600 m beat up to a point 220 m to windward of her (the weather gauge),
  then hold the broadside on at the loaded shot's range, presenting the
  loaded side, opening when too close (raking comes from the geometry);
  grape inside grape range on a manned ship, chain when it means to board
  her and she is in chain range, else round; battle sail inside 320 m.
- **Water**: a land grid of 20 m cells (sea, shoal, land) from the scenario's
  `land`: open sea, an island (a ragged blob with a shoal ring), or a coast
  along the sides given (the campaign cell's land neighbours), ragged by
  integer sine noise, with shoals off it; ships start clear of it.
- **Orders** (types inside the lockstep's sim-order range): `O_SAIL` x, y;
  `O_TARGET` target; `O_HOLD`; `O_SAILS` 0-2; `O_FIRE` on; `O_SHOT` kind;
  `O_FLEE` (what the lockstep's army withdrawal sends); `O_BOARD` target;
  `O_HEAD` facing; `O_DECK` (N3b).
- **View** (`game/sea_battle.gd`, touch first): tap a ship of yours (double
  tap: the fleet; long-press drag: a box), tap the sea to sail (several
  ships spread in a line abreast; the planned course drawn with its tack),
  tap an enemy to engage, Board armed then an enemy to board; one finger
  pans, two pinch, the wheel zooms; the bottom bar: Full sail / Battle sail
  / Heave to, Round / Chain / Grape, Fire at will, Board, Hold course, Flee;
  the left column your ships (hull, crew, rig bars, both broadsides'
  reload); the wind rose; speed II / 1x / 2x / 4x; Leave (a defeat). Drawn:
  waves running before the wind, land and shoals (the grid smoothed),
  top-down hulls 1.5 x their size (to read on a phone) with gunports, a
  rail in the faction colour, masts and square sails braced round with the
  wind and bellied by the drive (a sloop's boom swings to leeward), torn
  and shot away with the rigging, furled when hove to or struck; the
  ensign (white when struck, the captor's when taken); wakes; broadside
  smoke and muzzle flashes along the firing side drifting with this battle's
  wind (the land battle's gun-smoke look), shot streaks, splashes for
  misses and splinters for hits; fires with smoke columns; the magazine
  blast (fireball, shock ring, pall, wreckage); sinking; grapples; the
  selected ship's broadside arcs and reach. Messages: grapples, prizes,
  strikes, sinkings, fires, groundings, escapes.
- **Custom battle**: the West setting's "Sea battle" (solo): ships per side
  (up to 8), wind direction and strength, water (open / island / a coast),
  start (across the wind, your fleet upwind or downwind).
- **Measured** (`determinism_test --only=sea`): STATUS "N3a".
- **Later**: smoke blocking aim, shore batteries and forts firing on
  ships, ships bombarding shore units, the formula fitted to these results,
  sea battle art (the miniatures at headings), sounds of the sea. (Live
  co-op at sea, N3b deck melees and N3c fire ships: built, below.)

### Sea battles: live co-op, deck melee, fire ships (as built, N3b / N3c, 2026-10-16)

The three follow-ons to N3a (campaign hand-off: CAMPAIGN.md "Sea battles
fought", the co-op, deck melee and fire ship bullets).

- **Live co-op at sea** (milestone 5 rules unchanged: everything shared
  lives in the sim or the lockstep, changes only by lockstep inputs): the
  lockstep already ran a SeaSim; what was missing is the room and the view.
  `CSeaBattle.build` gives `controller` / `battle` / `sim_side` as
  `CBattle.build` does, so `CoopSession` takes a sea battle unchanged
  (`live_ai_sides` keeps a sea scenario's per-side AI flags, its telemetry
  no longer reads a soldier count from a SeaSim). `CampaignScreen.fight_live`
  opens a sea battle's room like a land battle's (`_fight_sea_live`), and
  `game/sea_battle.gd` runs in co-op the way `game/battle.gd` does: it
  follows the lockstep's sim (rebinding on start and on a snapshot restore,
  events not replayed), interpolates by the session's frame clock, sends
  orders through `coop.issue()` for the ships this player commands only (a
  tap or a card of a team-mate's ship says whose it is; double tap and box
  take only your own), II and the speeds are votes (II asks to pause or
  resume; a speed while paused also asks to resume; choosing the speed in
  force withdraws your proposal), Gift in the orders bar hands the selected
  ships to a team-mate (the picker with several), the card column carries
  each ship's commander colour once a team-mate takes part, the co-op HUD
  (`game/coop_hud.gd`: roster strip, lobby, waiting / catching up / resync,
  vote chips with Accept / Decline, Continue without a disconnected player)
  sits over it through a small shim of the land HUD's names, Leave says who
  gets your ships, Continue at the end waits for the final frame, and
  `coop_exit_result()` is what the campaign screen uploads (the host once;
  the last player's forfeit of their own side). Testing aids:
  `--coop-start-alone`, `--coop-auto-exit`. Not reachable from the Online
  battles list until `online_ui.gd` stops gating "Fight together" off for
  sea battles (CAMPAIGN.md).
- **Deck melee (N3b): an integer crew-against-crew melee inside the sea
  sim**, not the land sim. Reusing BattleSim for a deck would have meant a
  second simulation nested in every sea battle (its own map, snapshot and
  hash, its result fed back by an O_DECK input that some peer would have to
  issue), for a fight of a few dozen groups on a 2 m grid; inside the sea
  sim it is a few hundred integer operations a deck step, hashed, in
  snapshots and in lockstep by construction. The N3b hook stays: scenario
  `"deck": 1` still parks a grapple for an outside melee (`deck_request()`,
  `O_DECK`, now refused unless a boarding is waiting for one).
  - **The deck**: both ships side by side as a grid of `DECK_CELL_M` 2 m
    cells, each ship her length by her beam (5-28 by 2-7 cells), the
    boarder's rows above the rail, the defender's below, masts in the way.
  - **The men** as figures of a few men each, at most `DECK_FIG` 24 a side:
    the boarding party (`DECK_BOARD_PCT` 75 % of the crew and every soldier
    aboard) against every defender; the soldiers at the rail, the crew
    behind, the captain and two mates at the stern. Arms: the crew kit by
    faction (`ST.DECK_CREWS`: the Brethren cutlass, axe and a brace of
    pistols 34 / 22 and two volleys; Spain sword and buckler 28 / 28;
    France boarding axes 30 / 22; England and the Dutch cutlass, pistol and
    pike 27 / 24; Miskito and Itza clubs and bows with three volleys) times
    the ship's boarding quality; soldiers by their unit rows (attack;
    defence + armour + shield / 2) and their line's volley
    (`ST.DECK_LINE_SHOT`: muskets 26 % at 7 cells, buccaneers 34 % at 8,
    pistols, bows); soldiers without a kit musket and bayonet; the captain
    at `DECK_CAPTAIN_ATK` 250 % (x the campaign captain's `cq`).
  - **A deck step** every `DECK_EVERY` 2 ticks, figures in index order
    (reversed every other step): strike the nearest enemy figure next to
    it (each man kills at `DECK_KILL_PM` 14 per mille x 2 atk / (atk +
    def); a figure on its own deck defends at `DECK_BONUS_PCT` 125 %;
    shaken men strike weaker), else fire a loaded volley in reach (shot %
    x `DECK_SHOT_PM` 5 per mille a man), else step a cell toward it (every
    `DECK_MOVE` 3 steps). Losses come off the ship's crew or troops at once.
  - **Heart**: each side's morale starts from its ship's (boarders +10),
    falls by the share of its men lost (`DECK_MOR_LOSS` 100 for all of
    them; a quarter less while its captain stands), `DECK_CAPT_LOSS` 30
    when he falls, a little each step when outnumbered. **The end**: the
    defenders strike (the deck is lost: the existing capture, a prize crew
    across) when their heart is gone or they are under `DECK_BREAK_DEF` 30
    % of the boarders; the boarders are thrown back (their ship's morale
    -25) when theirs is gone or they are under `DECK_BREAK_ATT` 45 % (after
    2 s); both at once, or `DECK_MAX_TICKS` 45 s: both crews are spent, the
    grapnels are cut and the ships part (-15 each). Ships in a deck fight
    do not strike by the ordinary rule (the deck decides).
  - Measured (probe runs, two ships laid alongside at the start): strong pirates take a
    weakened brigantine in 4-6 s, an even pair fights 15-28 s before the
    boarders are thrown back, a sloop boarding a frigate is thrown back in
    2 s, an English frigate with musketeers boarding a galleon with
    rodeleros is thrown back in 6-9 s.
  - **View**: an inset at the top right (a tap centres the pair) draws both
    decks in the diorama look (planking with seams, a grating, rails in the
    ships' colours, masts, grapnel lines across the gap), each figure as a
    little crowd of up to five men in its ship's colour (soldiers with a
    crossbelt, the captain ringed in gold), easing from cell to cell, cold
    steel sparks where it struck, powder smoke from volleys, each side's
    men and heart and "captain down"; the outcome stays 2.5 s. Sounds:
    `melee` while it lasts, `musket` per volley, `unit_break` / a horn at
    the end. Events `EV_DECK_SHOT`, `EV_CAPTAIN`, `EV_DECK_END`.
- **Fire (N3c)**: a fire has an intensity (`s_burn` 1..`FIRE_MAX` 1000):
  a hit's fire starts at 60, grows 25-45 a second and the crew beat it down
  by `FIRE_FIGHT` 45 x their share of a full crew (a full crew puts a small
  fire out in a few seconds, a thin one cannot); it eats the hull by its
  intensity (`FIRE_HULL`). **Magazines**: past `MAG_LV` 500 each second
  rolls (the sim RNG) (intensity - 500) / 4 per mille: she blows up, holes,
  kills and fires (at 250, half the time) her neighbours within `BLAST_M`
  70 m (N3a rolled 1.5-3 % a second from the first spark).
- **Fire ships (N3c)**: a ship row (`fire_ship`: 22 m, 9.5 m/s, no guns,
  hull 420, a crew of 14, `fire` 1). Ordered at an enemy (a tap with her
  selected; `O_TARGET` / `O_BOARD` become `M_FIRE`) she sails at the mark's
  place a little ahead, is lit inside `FS_LIGHT_M` 200 m when she can lie
  the course, her crew lash the helm and take to the boat inside
  `FS_ABANDON_M` 80 m (or `FS_ABANDON_TICKS` 30 s after); "Light her"
  (`O_LIGHT`) fires her at once; a fire ship that would strike, or that a
  shot sets alight (4 x a ship's chance), fires instead. Lit, she burns at
  `FIRE_MAX` (2 % of her hull a second, no hull penalty to her speed),
  takes no orders, does not count as fighting, is everyone's first target
  within 300 m; whatever she touches (either side) she grapples for
  `FS_STICK_TICKS` 25 s and sets alight at `FS_FIRE` 400, feeding its fire
  `FS_FEED` 80 a second; sparks catch ships within `FS_SPREAD_M` 25 m at 25
  % a second. **Battle AI**: a fire ship goes for the biggest enemy (guns
  and hull) when the wind serves (the mark lies at least `FS_SERVES` ~105
  deg off the wind, within 1.2 km), else waits 420 m up to windward of it.
  Measured (`determinism_test --only=sea`, the fireship set piece over 8
  seeds): lit in 8, reached and fired her mark in 6, magazines blown in 5;
  a Spanish line ahead to leeward: 2 contacts in 6 seeds (the line's
  broadsides sink the rest first). **View**: a tarred hull with brushwood
  and barrels; lit, flame tongues lean downwind along her length (by the
  fire's intensity on any burning ship), embers blow off, a black column;
  her crew's boat pulls away; orders drawn in orange with her lighting
  ring; messages; `burst` on lighting and contact. Custom battle: the fire
  ship is in the ship list.
- **Help on the sea screen**: every order has a one-line tooltip and a
  long-press card, sail and shot changes show a hint, and the Ship book
  (top bar) explains points of sail, sails (speed only), shot kinds,
  boarding, striking, fire and every ship row, all from the sim's own
  numbers (view only, `game/sea_book.gd`).
- **Determinism and cost**: all the new state (fire ship, crew kit, troop
  kit, melee slot and figure arrays) is in `state_hash()` (so in
  `Lockstep.state_hash()`) and in snapshots (script variables); `f_hit`
  (when a figure last struck, for the sparks) is view data, not hashed.
  Desktop: 60-70 us a tick, 160 us during a deck melee (worst 300 us);
  `state_hash` 26-30 us; a snapshot 1.6-1.9 KB.

### Story campaign: "The Brethren's Due" (agreed 2026-10-14; steps 1-2 built 2026-10-15, see "as built" below)

A single-player (co-op optional) story campaign on the Caribbean pack that
teaches how the world works through events the player must answer, not
"go here, do this" tasks. Agreed with the user: **swashbuckling with a dark
edge**, **about 45 turns** (4-6 hours), **three endings**, **co-op as an
option**.

**Premise (c. 1665).** You are a pirate crew's quartermaster; turn 1 opens
the morning your captain, Josiah Vane, is hanged at Port Royal. The crew
votes you captain and you slip out on one battered sloop with a Spanish
guardacosta on your tail. Hidden goal: Vane's dying words of "a free port
where no flag but ours flies" -- a pirate republic the nations must
recognise (after Nassau, 1706-18), revealed only in Act 3, foreshadowed by
the pages of Vane's logbook.

**Characters (they talk the player through the game).** Mercy Teague, the
quartermaster: blunt, the crew's voice (plunder, shares, morale, mutiny;
"The crew votes, Captain. Remember that."). Isaac Lindo, a Port Royal fence
and fixer: smooth, amoral (selling plunder, the letter of marque,
diplomacy; whose side is he on?). Josiah Vane, dead: his logbook pages
teach sailing and the wind and reveal the goal.

**Antagonists.** Don Rodrigo de Mendoza, admiral of the Armada de
Barlovento (Spain's real anti-pirate Windward Fleet): patient, honourable,
personal once you take his treasure; his patrols grow with infamy.
Governor Sir Thomas Ashby of Jamaica: the patron who issues your letter of
marque and sells you out when England makes peace with Spain (the real
Treaty of Madrid, 1670). "Le Boucher" Jean-Baptiste Nau (after
L'Olonnais): a cruel, charismatic rival for crews and fame whose
atrocities bring Spanish reprisals on every pirate.

**Beats.** Prologue (turns 1-4, the tutorial): the chase (run west with
the wind or turn and fight: sailing, a first sea battle), the hungry crew
(a prize or a fishing village: plunder and shares), Tortuga (the first
haven: crews). Act 1 "Brethren" (5-15): the crew's purse pressure
(grumbling, desertion, mutiny threat), hurricane season (shelter or risk an
unguarded prize), Le Boucher's massacre brings a Spanish punitive raid on
Tortuga (defend the haven: a land battle), then hunt him or join him.
Act 2 "The Commission" (15-30): Lindo brokers Ashby's letter of marque
(English ports, plunder bonuses); the flota at Havana (build a real
fleet, ally the Miskito and other captains); Mendoza's Armada hunts you
and blockades your havens; midpoint twist: peace between England and
Spain, the letter revoked, Port Royal shut, a price on your head (escape
the harbour under fire if you are there). Act 3 "The Free Port" (30-45):
the goal revealed (hold a fortified haven for N turns, a fleet able to
beat the Armada, enough plunder to buy recognition); the Brethren council
(persuade, buy or beat the rival captains, Le Boucher if alive); the great
raid on Cartagena or Panama to fund it (forts, street fighting); the
finale: Mendoza's Armada attacks the free port, a combined sea and harbour
battle. Endings: **the Republic** (you hold), **the Pardon** (take the
King's pardon and betray the Brethren to Ashby: rich, safe, despised),
**the Legend** (you go down fighting; the chronicle sings of it).

**Pressures, not quests.** The screen shows running pressures instead of a
quest log: the crew's purse (turns since plunder), the Armada's attention
(infamy), patron favour, the hurricane season clock, haven safety. Events
fire when they cross thresholds or when the scripted actors move. An event
arrives as news with 2-3 responses and consequences ("A Spanish frigate
lies careened at Isla de Pinos, helpless. Mercy wants her; Lindo says it is
bait."). Characters speak on first sight of a mechanic, when a pressure
rises and after big results: they react, they do not assign. Le Boucher,
Mendoza and the flota act on their own clocks, so the player is always
answering someone else's move.

**Co-op (optional).** The partner is a second captain of the same
Brethren: their own ships and crew, one shared story. Story choices are a
**crew vote** between the two captains (agree: it passes; disagree: Mercy
calls the vote by each captain's fame and crew, and the loser's crew
grumbles). The endings can split: one captain may take the Pardon and
betray the other, who fights on (the dark edge).

**Build (later; about 4-5 steps).** A scripted West campaign: a fixed
start state; a data-driven event system (conditions on the state, choices,
effects) that is deterministic and in the campaign rules, so it works
online and in co-op; a dialogue panel with portraits; the pressure
display; the scripted actors (Le Boucher, Mendoza's Armada, Ashby's
favour) as AI factions with story hooks. Everything else reuses the
existing systems.

**As built, step 1 (2026-10-15): the story engine, the Prologue and Act 1, solo.**
- **Engine** (`campaign/cstory.gd`, campaign rules: integers, the state's
  RNG, arrays in index order). The script is data
  (`campaign/data/story_brethren.gd`): characters (name, role, badge
  colour), the start, the pressures' numbers and the events. An event has
  `when` (all must hold: turn range, flags set / not set, a pressure at or
  below a threshold, the attention, a captain's fleet near a region, a
  region owned / lost, the hurricane season, a storm on the map, a siege by
  or of the player, any plunder, plunder within N turns, an actor alive or
  gone, gold, a timer, ships), or is fired only when scheduled (`if`
  re-checked when due); `once` (default) or `every N` turns; lines
  `[speaker, text]`; effects on firing; 0-3 choices, each with a hint, a
  `need` (greyed with a reason when not met), a reply and effects; a
  chronicle line; a map focus. Effects: gold, plunder (counts as plunder),
  a pressure, infamy, fame, flags, schedule an event N turns on (0: at
  once), timers, the act, crew / hull %, companies joining at a region,
  losing the weakest ship, gambles (also by fame), spawn / place / goal /
  home / hold / chase / release / remove / join a scripted actor, a sea
  battle with an actor now, a raid (an army lands and storms a settlement
  now: a land battle), a story sack, the flagship's stored voyage, a
  hurricane east of the flagship, war / peace.
- **State**: one optional key `story` (key, y0 years added to the
  calendar, act, `cap` the captains = human factions, pressures, flags,
  fired, sched, timers, pending, log, actors, battles opened, plunder seen,
  mercy). Normal campaigns never get it (and no fleet gets `sto`), so Rome
  and West are byte-identical. `CData.year_shift` (set by `use_state`)
  moves the calendar: the story starts in summer 1665.
- **Flow**: events fire at the end of a turn (after the turn number moves
  on), after a choice and after a battle. A choice waits like a pending
  battle: `resolve_turn` refuses while any is pending; `CStory.answer(st,
  f, id, k)` is a pure function like `apply_battle` (each pending entry
  names the captain who answers: two captains fit, the co-op crew vote is a
  later step). A choice that opens a battle sets phase "battles". Battles
  the story opened, or with an actor's fleet in them, set `won_<tag>` /
  `lost_<tag>` (read from the battle's event); AI-only losses set
  `gone_<tag>`. A captain left with no ship and no land is spared by
  `check_eliminations` while rescues are left (2): a battered sloop at the
  haven and "Cast ashore".
- **Scripted actors**: fleets tagged `sto` that the AI's fleet plans skip
  (`cai_fleet.gd`: plans, merges, debt scuttling); the story moves them in
  step 5 of the turn: `chase` (the nearest captain's fleet, until a turn,
  then home), `hunt` (the Armada: a captain's fleet within 25 + attention
  cells while the attention is 35+, else its home port), `goal`, `home`
  (then back to the AI), `hold`; a `ttl` removes one. The guardacosta San
  Telmo (a New Spain sloop) chases the player for three turns; Mendoza's
  Armada de Barlovento (two frigates and a sloop at Havana) hunts by
  attention; Le Boucher is a French fleet (L'Olonnais sailed under a French
  commission from Tortuga) the story moves; Ashby is England with the
  favour pressure.
- **Pressures** (end of turn): the crew's purse +6 a turn without plunder
  (+2 while 300+ shares are owed), - plunder / 6 (max 60); shares owed +
  half of plunder; Spain's grudge (heat) -1 a turn; attention = infamy +
  heat; the haven drifts 5 a turn toward 40 + 15 a walls level + 15 with
  an army of ours there - attention / 4 (0 when lost); favour moves only by
  events; the hurricane clock is read from the season and the storms (no
  state). Lindo's fence (a timer): plunder pays 25 % more.
- **Start**: the West pack, the Brethren played; the player holds only
  Tortuga (Port-de-Paix; Trujillo goes independent), 200 gold, infamy 5,
  peace with the Dutch, England and France; one sloop (hull and crew 70)
  off Port Royal with a company of cutlass men aboard, under "The Captain";
  victory at 30 regions / 5 great cities.
- **Script** (state turns 0-14): Gallows Point; the chase (run west with
  the wind: the flagship's voyage, the San Telmo gives up; fight: a sea
  battle now; bluff: a 55 % gamble, else a battle with the first broadside
  hers); Vane's logbook on the trades; the hungry crew (the Santa Catalina
  becalmed off Cabo Cruz for three turns with 250 in silver, or the fishing
  village: 120 plunder and infamy, or tighten belts); Tortuga on arrival
  (crews: buy a round, promise shares, volunteers); Lindo's letter (his
  fence, pay Vane's debt, burn it); Act One; the purse's grumbling (40),
  desertion (65) and the crew's vote (85; a speech is a gamble by fame);
  Le Boucher arrives (turn 5); the hurricane (season, turns 6-10: shelter,
  the treasure nao in the storm's path, or ride it out); Maracaibo
  sacked (turn 8); the warning (turn 9) and the Spanish reprisal on
  Tortuga a turn later (four companies land and storm it: a land battle);
  Mendoza's letter (attention 30) and the Armada sailing (35); strangers
  in Tortuga (haven below 30); Le Boucher's bargain (turn 12: hunt him at
  the Ile-a-Vache, join him, or let him go); End of Act One (turn 14).
  First-sight logbook pages: the wind, shares, havens, hurricanes, walls.
- **Balance probes** (formula): the San Telmo fight is won about 70 %; the
  reprisal holds 13 % with only the garrison, 30 % / 53 % / 73 % with one /
  two / three companies of ours in Tortuga; Le Boucher careened at the
  Ile-a-Vache (hull 50 %, crew 60 %) beats a lone sloop every time and loses
  to two of ours about 63 %.
- **View** (`game/campaign/story_view.gd`): the dialogue panel (a
  coloured initial badge per character, name, role, the lines; the
  narrator in parchment colour; choices with their hints; on a short screen
  the scene and the choices are two pages), the reply, "Look at the map"
  (the strip's Decide button reopens it; End turn does too); the pressures
  strip under the top bar (five gauges, colour by danger; a tap opens the
  story log with each pressure explained); the story log (also Realm >
  Story log); captions over the story's fleets, the haven's safety ring and
  the lair while it is hunted; the map centres on what an event is about.
  New campaign screen: "Story: The Brethren's Due" (offline). Chronicle
  lines for the story's big moments. Testing aids: `--story=seed[:turns]`,
  `--story-seen=N`, `--story-choices`, `--story-log`.

**As built, step 2 (2026-10-15): Act 2, Act 3 and the three endings, solo.**
- **Script** (`campaign/data/story_brethren.gd`, state turns; about 60 new
  events). Act 2 "The Commission" (15-29): the Armada refitted (it hunts
  from attention 30, respawned if Act 1 sank it); Ashby's commission
  through Lindo (needs patron favour 30, or 400 gold to buy his signature,
  or "No flag but ours": England's real letter of marque, `CSea.grant`,
  with England at war with both Spains so Spanish plunder pays +50 %);
  the flota (Lindo's news at 16-18 with three ways to a fleet: buy a
  brigantine, the Miskito, steal a ship; the careened frigate at Isla de
  Pinos, 50 % bait with the Armada behind the island; King Jeremy's war
  canoes and warriors; Tom Hesketh's Ranger for shares or gold); the real
  flota at Havana (hunt it: a sea battle when within 3 cells of any of its
  fleets, or shadow it for a straggling galleon, or let it go; taken,
  silver, Mendoza's vow and a frigate more); the Armada blockading
  Tortuga at attention 40 (break it, wait, or bribe a captain); the
  Treaty of Madrid (turn 22): peace England-Spain, the letter revoked,
  war with England, favour 0, the Armada hunts from 20; at Port Royal,
  run the gauntlet (a sea battle) or slip out (a gamble by fame); Ashby's
  price on your head (HMS Oxford chases you 4 turns); Lindo's loyalty
  (outbid Ashby, trust him: a 55 % gamble, or cut him off); Le Boucher
  as your ally (his church-burning: look away, rebuke him, cast him out
  to Spain) or as a rival (hunt him, sell his careening place to
  Mendoza); End of Act Two. Act 3 "The Free Port" (30-44): Vane's last
  pages reveal the goal (raise the walls with gold or with the crew);
  Lindo's or Mercy's arithmetic; Tortuga retaken if lost (from Act 2);
  Le Boucher returns (frigate and brigantine) or, if he sailed with you,
  turns his coat and sells your walls to Mendoza; the Brethren council
  (a speech: gamble by fame; buy the votes, 600; or beat Le Boucher in
  Tortuga road before them all: a sea battle, then he hangs at low
  tide); won, Hesketh, Black Ned Corbin's two ships and four companies;
  split, half the captains go to Le Boucher; the great raid (Cartagena
  1500 plunder or Portobelo 1000; off the harbour storm it at dawn: a
  land battle with a quarter of the defenders caught asleep, or bribe a
  gate for 300: half of them and the walls a level lower; six companies
  of the Brethren land with whoever is aboard); the King's pardon (36-41,
  every 3 turns: take it, keep the letter, burn it); recognition when the
  chest is full (the Dutch squadron in the road: the Armada loses its
  strongest ship, two companies); Mendoza's last letter (38: the Armada
  gathers with a galleon); the night before (40: meet them at sea, fight
  from the walls with three companies more, or a kept pardon); the
  finale (41): the Armada attacks the fleet in Tortuga road (a sea
  battle, the fort's batteries with us), then lands 3 companies after a
  win, 7 after a loss, 6 against the walls; at sea with no port left, a
  last sea battle. Endings: **the Republic** (the finale's land battle
  held), **the Legend** (lost; or the last sea battle; or every captain
  gone: `END_OVER`), **the Pardon** (1500 gold, peace with England and
  Spain, infamy gone, favour 100); turn 44 without one: the Republic if
  Tortuga is ours with 2 parts of the goal, else the Legend.
  Tips (first sight): letters of marque, the flota, blockades, a sea fight
  (real time or at once), walls and forts, the free port. Characters
  added: Jeremy (King of the Mosquito Coast), Tom Hesketh. `MERCY` 3.
- **The free port** (`CStory.fp_parts`): fort (Tortuga held with walls 2+,
  unblockaded, unbesieged, 5 turns; lost resets it), fleet (the captains'
  power at least 80 % of the Armada's: in Tortuga road with walls 2 the
  batteries make that about 85 % to win), chest (1500 gold: plunder
  since the reveal and what events pay in). State `story.fp {held, gold}`.
- **Engine** (`campaign/cstory.gd`). Conditions: flota / noflota, blockaded,
  capt / nocapt (a captain the story made, `captains[].sto`), fp / fp_ge,
  walls_ge, fame_ge, sea_pending, any [...]. Effects: dip2 (two other
  factions), marque / unmarque, ship (joins the flagship), actor_add /
  actor_lose / actor_att / until / blockade (a new actor mode: lie off a
  port until a turn, then hunt), build (a chain level), slight (walls
  down), assault (the captain storms a settlement now: a story landing
  party plus everyone aboard within 5 cells), weaken, desert (a story
  captain of ours becomes an actor of another faction), free_port,
  fp_gold, ending; spawn takes a home; sea_battle takes a tag and "they
  attack" (the captain defends: port batteries count). A battle opened by
  sea_battle / raid / assault sets `bt_<tag>`; a raid on a settlement with
  someone else's battle pending waits for it (`story.rq`, this turn); a
  hunting or chasing actor rests 3 turns after a battle (`rest`); the
  flota's fleets are tagged "flota" in story battles (`hunt_flota`).
  `_ending`: `story.end`, `end_t`, flags `ended` / `end_<k>`, the stats
  counted, every actor released, nothing pending or scheduled, no event
  after it: the campaign plays on as a sandbox. `story.sx` (ships taken,
  towns sacked, battles won / lost) is counted from each turn's events.
  Outside cstory: `cturn.resolve_turn` calls `CStory.end_turn` also when
  the game is over (the story's Legend), `cfleet.end_of_turn` launches no
  ship into a story fleet (`sto`). All new state is lazy and story-only:
  Rome and West are byte-identical (`CState.VERSION` unchanged).
- **View** (`story_view.gd`): the Free port gauge (shown once revealed; its
  tooltip and the story log list the three parts and their progress), the
  favour text after the treaty, captions for the new actors, prizes in
  gold, the flota once seen, a dashed ring on the great raid's target, the
  haven captioned "the free port"; the ending screen (title, a line, the
  epilogue paragraph, "What became of them": a fate for each of the seven
  characters by ending and flags, "The Captain's account": plunder, ships
  taken, towns sacked, fame, battles won / lost, infamy; "Continue in the
  sandbox" or "The story so far"; the log has "The ending" after it);
  `campaign_screen._next_step` shows the story's news before pending
  battles and the ending before the game-over panel.
- **Testing aids**: `game/campaign/story_autoplay.gd` plays a story headless
  (choices by path: first, random, or scripted for the Republic, the
  Pardon, the Legend; the scripted captain wins his battles except the
  Legend's finale; fleets sail for the raid, a weaker prize, else home; a
  sloop when shipless and buccaneers at the haven). `--story=seed:turns
  --story-path=... --story-show=ID|ending`.
- **Balance** (formula; `scratchpad` probes). Sea (power x 85-115 % roll,
  defenders in their port x (110 + 15 x walls) %): the Pinos frigate and
  the straggler are sure for an Act 2 fleet (sloop, brigantine, two
  canoes, about 400), a lone sloop never; a flota part (galleon and
  frigate, about 840) needs an Act 3 fleet (about 1070: 97 %), the whole
  flota (about 2100) is out of reach; HMS Oxford falls to the Act 2 fleet
  (98 %); Le Boucher at the council (about 610) 45 % with Hesketh, sure
  with the council's ships; the finale Armada (about 1630) against an Act
  3 fleet in Tortuga road 26 %, against a strong one (about 1690) 100 %,
  recognised (no galleon, about 1060) 100 %. Land: the finale with walls
  2 against 6 companies holds 22 / 59 / 83 / 92 % with 0 / 2 / 4 / 6
  companies of ours (3 after a sea win: 69-99 %; 7 after a loss: 16-88
  %); the great raid on turn-0 garrisons by surprise 2-18 %, with the
  bribe Cartagena 23 / 41 / 60 % and Portobelo 37 / 57 / 74 % with 0 / 2 /
  4 companies of ours aboard (the AI's armies there by then vary a lot:
  the preview shows the odds). Random-choice bots on the formula end in
  the Legend most often (the sandbox's nations take an ungarrisoned
  Tortuga), sometimes the Pardon.
- **Checked**: `tests/story_test.gd` PASS (step 1's checks; step 2's
  effects one by one; the three scripted paths reach their endings,
  twice the same and through JSON every turn, seven fates each; 8 seeds
  x 45 turns of random choices end in one of the three), campaign_test,
  pack_test, campaign_sim hashes unchanged, online_e2e (Rome, West), go
  test, check_scripts. Open: co-op (the crew vote), portraits, the story
  online, a real-time playtest of the finale.

**As built, step 3 (2026-10-16): co-op crew vote, the story online, portraits.**
- **Two captains** (`CStory.new_story(name, seed, settings, key, coop)`): the
  lead is the Brethren (Tortuga's owner), the partner plays the **Miskito**
  faction (script `PARTNER`, `PARTNER_START`: "Captain Rook", a sloop
  "Mosquito Queen" with a company of warriors off Port Royal, the Cabo
  Gracias a Dios as his haven and a small garrison; peace with England,
  France and the Dutch, war with Spain; the West pack gets no new faction, so
  solo and sandbox hashes are untouched). Humans are allies (one team).
- **The vote** (pure, in `campaign/cstory.gd`): with two living captains a
  fired choice's pending entry carries `v: []` (votes `[captain, choice]`,
  in arrival order); solo entries have no `v` and are byte-identical to
  before. `answer(st, f, pid, k)` records f's vote (a captain votes once;
  `need` conditions apply per voter) and returns the state with the choice
  still open; the turn does not resolve (`blocked`). When every living
  captain has voted: **agree: it passes**; **disagree: Mercy calls it by
  weight** (`vote_weight`: 10 per point of the captain's best fame, 1 per
  10 % of each ship's crew, 1 per 10 men aboard or in his armies; **a tie goes
  to the lead**), the heavier side's choice carries, the flag `crew_split` is
  set and the **loser's crew grumbles** (-6 % crew and men). Effects apply to
  the lead captain (the script is written for one "you": Tortuga, gold,
  units); crew, hull, fame and infamy effects apply to the partner too. The log
  entry keeps `v` (both votes) and `w` (the winner's faction, -1 when they
  agreed); the story log, the vote result dialog and the epilogue read it. A
  vote whose last captain falls is settled by the other's (`settle_ready`,
  run by `check`). The order of the votes does not change the result.
- **View** (`story_view.gd`): the choice shows "Your vote, <captain>" and the
  other captain's vote once it is in; hot seat hands the device to whoever
  has not voted (`--story-nohand` skips it for screenshots); after the last
  vote a result dialog shows both votes with their portraits, Mercy's word
  (one mind / split, who carried it) and the winner's reply. Online, a voted
  captain sees "Waiting for <captain>"; the read markers live in the seat's
  session.
- **Online** (`game/net/online_campaign.gd` `answer_story`; server kind
  `"story"`): the client runs `CStory.answer` and uploads the state with the
  version it came from (compare-and-swap; on a conflict the answer is
  re-applied to the newer state while it still applies); the server checks
  only that the turn did not change, no pending battle vanished, the hash
  changed and the seat is alive, stores `{f, pid, k}` as the inputs, and
  reads `story.pending` for notifications ("the crew is voting" mentions the
  captain still owed an answer, `StateMeta.StoryWaiting`). Other clients
  re-run each vote from its parent (`verify`); `resolve_now` and the
  auto-resolve refuse while a choice is open. New campaign screen: "Two
  captains (hot seat)" and, online, "The Brethren's Due: two captains".
  `statemeta` needed only the `story` block (no faction change: battles are
  read from armies and fleets as before).
- **Portraits** (`game/story_portrait.gd`, vector like the faction emblems):
  Mercy, Lindo, Vane, Mendoza, Ashby, Le Boucher, Jeremy, Hesketh, the crew,
  the Captain and Captain Rook; `tests/portrait_gallery.gd` renders the contact
  sheet at 96 and 48 px. Shown next to every spoken line, in the vote
  dialogs and on the choice cards (the portrait of whoever answers in the
  choice's `say`). A character without a portrait shows its faction's mark
  (`CHARS` `mark`), else the coloured initial.
- **Format**: `CState.VERSION` is **not** bumped: the new keys (`v` on a
  pending entry, `v` / `w` on log entries, a second captain in `cap`) only
  appear in a co-op story, which did not exist; every earlier state means
  what it did. The rules hash changes (online clients must reload).
- **Tests**: `story_test.gd` (the vote: one vote leaves it open and the turn
  held, agree, split by weight, tie to the lead, order independence, JSON,
  45 turns of votes twice the same and through JSON every turn),
  `tests/story_online_e2e.py` (two captains through a scratch server: 14 votes
  through compare-and-swap, one simultaneous conflict re-applied, the split
  vote settled by weight, B re-ran all 23 steps with no mismatch, a refused
  empty answer, the Discord mention), Go `TestParseStateStoryWaiting`.
- **Tortuga on random paths, and the haven shield (2026-10-16)**: random-choice
  bots (30 seeds, 45 turns) lost Tortuga by turn 20 in 21 of 30 runs (27 by
  turn 45): the sandbox's Spain, France and Tierra Firme besieged a 3-company
  haven. Rule (`CStory.shielded`, gated on `st.has("story")`, read by
  `cai.gd` `_shield` and `cai_fleet.gd`): the AI of a nation does not march
  on, siege, assault, raid, hunt in, land against or blockade a captain's
  haven (the script's HAVEN, and the partner's `PARTNER_START` regions) unless
  provoked: the Spanish nations (`SPANISH`) when the captains' attention is
  at the Armada's hunt threshold (35) or more; any nation for 8 turns after
  a captain sacked or blockaded one of its ports (`prov`, recorded by
  `_tally`; a blockade still on counts). England is released by the Treaty;
  the Legend ending lifts the shield, the Republic and the Pardon keep it.
  The story's own attacks (reprisal, hunters, finale, blockade) are effects
  and ignore it; fleets at sea still fight. Reprisal data: ignored warning
  three Spanish companies, heeded warning two (the fort sinks boats).
  Result, 30 seeds: lost by turn 20 21 -> 4, by turn 45 27 -> 9; while the
  story runs 9 (five ignored the warning, two lost the finale, one sold out
  at the Treaty, one provoked Spain). Sandbox hashes unchanged.
- **Provocation taught (2026-10-16)**: Mercy explains the shield in her own voice
  (data `story_brethren.gd`): at attention 20 ("Mendoza keeps a ledger ... page one"),
  at 35 ("The Armada ... weighed anchor"), before a sack (the `SACK_TIP` line on a
  port's card in the overworld), once per nation after the first sack or blockade
  ("{nation} will remember that for a season") and when it cools after 8 turns,
  and the Treaty ("England has leave to come for Tortuga"). Events can be about a
  nation: scheduled entries carry a third item (the faction), the log entry and
  pending entry an `x`, and the view fills `{nation}` / `{adj}`; `act: -1` means the
  current act. `prov` entries are `{f, t, w, r, n}`. **Grudges**: `CStory.grudges`
  lists provoked nations (why, port, turns left) and the attention toward Spain;
  the story log has a Grudges block (attention bar with the 35 mark "the Armada
  sails", one row per nation with its emblem) and a haven's city card says
  "Shielded: no nation holds a grudge" or "At risk: <nations>". **Punitive
  landing**: the first sack of a nation's port schedules a warning line ("Sails off
  the cape") and, 3-5 turns later (moved clear of the turn-10 reprisal by 3 turns),
  two companies of that nation's line troops (`PUNITIVE`) storm the haven (an
  effect, so the shield does not stop it); once per nation, later provocations
  lift the shield as before. No ship is sent (the landing is a raid effect).
  Measured with the 30-seed probe (a sack of a Spanish port forced at turn 14 in
  every seed, since random bots never sack): the landing came in 24 seeds, won
  by the garrison in all but 4 (2 of them where other Spanish troops had joined
  it); with the sack by France 7 landings, 1 lost. Without a forced sack the
  rates are the shield's (4 by turn 20, 9 by 45).
- **Open**: the partner is the Miskito (a story-specific faction would need a
  pack change); effects other than crew, hull, fame and infamy go to the lead
  only; a divided ending (one captain takes the Pardon, the other fights on)
  is not built; no phone look at the vote dialogs.

### Overworld: real geography and the landscape layer (as built, 2026-10-10)

## STATUS row
- Real geography (view data + static grid, no state change, `CState.VERSION` 6): the overworld is fitted to ETOPO 2022 elevation (NOAA, public domain) and Natural Earth 1:10m coasts and rivers (public domain). `tools/geo_fit.py` (+ `tools/geo/med.json`: window, projection, cell size, settlements, rivers; the Mediterranean is only the default config) writes `geo_rome.gd` (was `map_geo.gd`) LANDS / ISLANDS / RIVERS, `campaign/data/elev_data.gd` (per cell mean / max / relief / distance to river / class plain-rolling-valley-hill-ridge) and `game/campaign/relief_data.gd` (0.025 degree fine elevation, slope, relief); `campaign_grid.gd` derives hill / ridge from the real class (434 hill, 140 ridge override cells; was 200 / 215 from hand areas, now deleted) and asserts every settlement is on its landmass and every sea-lane port is a coast cell. Terrain view renders the real relief (hillshade + subtle hypsometric tint + crest line, one cached texture; `geo_fields.gd` serves elevation / slope / class to the view). Nudged: Carthago, Hadrumetum by 0.01-0.02 degrees. Re-pinned: campaign_test goldens (3007c1ab / 4197043257, be6e10a3 / 3786296811) and the Tarentum march rows (from Venetia). campaign_sim --seeds=6 --turns=60: hash 8562cf3a (HEAD 803bf309); no collapse; Epirus is eliminated in 5 of 6 seeds (3 of 6 at HEAD), Macedon in 0 (2 of 6). Sea depth (2026-10-17): the same ETOPO download gives `DEPTH` (one byte per fine sample, mean depth of the DEM's sea samples: 1 m steps to 30 m, then logarithmic to about 3000 m; decode in the `tools/geo_fit.py` header, `GeoFields.depth_at(p)`), baked for both packs (`--depth-only --dem`); `water.gdshader` colours the sea by it (sandy turquoise under 8 m, the shelf the earlier blue to 200 m, darker and more saturated to the deep, a faint shelf-break line where steep; the 3 / 8 km contour lines are gone), so the Bahama and Campeche banks, the Mosquito coast, the Gulf of Batabano and the Adriatic / Aegean shelves read as pale shallows.
- The overworld sea (2026-10-13, view only, third pass, `water.gdshader` + `sea_waves.gd`): printed-map look kept (thin calm shallow band, sharp 1 px contour lines at 3 / 8 km, crisp 1.6 px coast outline) with **waves** and **surf**. Waves (pass 4, 2026-10-13, after the user found pass 3 uniform and too large): five directional trains (56 / 39 / 27 / 18 / 12 map px at 0 / +30 / -28 / +45 / -40 degrees from the wind, speed about 6 sqrt(L/46), none dominant), Stokes-like sines whose phase warp and group envelope are value noise (not periodic), times a drifting gust field (noise at 650 / 300 px, 0.25..1.15: rough and glassy patches) on a wind that veers up to 0.4 rad (noise at 800 px); 7 noise samples a fragment shared by the trains; `tests/sea_waves_test.gd`; lit as a normal map from the NW (soft crests and troughs, a very small glint), damped near the coast and in sheltered water, each train fading out when under about 6 screen px; motion slow (phase speed 4.5-6 map px/s). Surf: breaker lines (3 km apart) advancing and fading in a 2.5-7 km zone, broken by noise gaps, plus a ragged swash at the waterline, only where the baked **exposure** says the sea reaches the coast (half the fetch along the wind, three rays, half the openness all round, 16 rays; heads of bays, lees of islands and the Tyrrhenian side under a NW wind get almost none), stronger on steep shores (baked `SHORE`); zoomed out the lines become a dim ragged edge; sparse whitecaps on high crests only in strongly exposed open sea; the 3 km contour fades where there is foam. `[map] water = low` (and Graphics Low): depth tint and contours, static. **Reuse for ships and other maps:** `GeoFields.wind_dir()` / `wind_strength()` / `exposure(p)` / `shore_steep(p)` come from `relief_data.gd` (`WIND_FROM_DEG`, `WIND_STRENGTH`, `EXPOSURE`, `SHORE`), baked by `tools/geo_fit.py` from the config key `"wind": {"from_deg", "strength"}` (`med.json` 315 / 100, the mistral; a Caribbean config says 90, the trade winds from the east; `python3 -I tools/geo_fit.py --config X --exposure-only` re-bakes only these from the COAST and SLOPE already in the file). `SeaWaves.height(p, t)`, `normal(p, t)` and `amp(p)` are the CPU twin of the shader (same trains; `SeaWaves.t` is the clock `map_view` also sends the shader). A ship sprite sits on it: its lift is `height * amp * k`, pitch and roll are the normal's components on its hull axes (times `amp`), its heading is its own; its wake is a `Line2D` of stern positions kept in world space that widen and fade over a few seconds (no drift with the sea: the waves are a phase pattern, not moving water), and the hull is drawn above the water node, below labels and armies. Nothing of this is in any hashed state.
- Graphics quality (2026-10-13, view only, `game/quality.gd`): `user://settings.cfg [video] quality = auto | high | low` (home settings row; `--quality=` overrides). Auto is Low when the soldier probe chose the CPU path (Chrome on the Tab S7) or when the first 3 s of a battle average under 40 fps (session only, toast "Graphics set to Low for speed"). Low: the ground shader's `low` uniform drops the noise patches, grain and the sea / ford animation; the settlement surroundings are flat-tinted fields and one-line tracks (`CityDraw.draw_surround(..., low)`); the tree layer hides the cover MultiMesh (tufts, scrub, bushes, reeds, willows) and the orchard rows (`visible_instance_count`), gameplay woods stay; the overworld sea is the still `hi = 0` water and the landscape tree / speckle mesh is skipped below zoom 0.9 (the relief texture stays). All switch live in a battle (the auto downgrade) and apply on the next battle / map open from Settings.

**Map table style (as built, 2026-10-14).** `[map] style = auto | table | relief` (Settings
button "Map", `--map-style=`): auto is the table for the West pack and the relief for Rome
(Rome in relief is pixel-identical to before). Table: `table_land.gdshader` draws the land
(brighter palette, 4-level posterised hillshade from the real elevation, ink contours,
sand coast band); the sea (`water.gdshader` `table = 1`) has five clean depth bands with softer
waves; the owner wash is 15 % with a stronger inked border; `table_frame.gd` adds the parchment
frame, vignette and an optional tilt-shift (`--map-tilt=0|1`, off on Low). Settlements and
fleets are painted miniatures (`minis_layer.gd`, tools/structures; exaggerated scale, tile
about 88 px x sqrt(zoom) wide, shown from zoom 0.55, ships from 0.35): base by culture and
size, harbour (port), slipway (Shipyard level), walls (palisade / stone / star fort), ships by
heading; the overlay keeps names, banners and hit areas.

**Overworld towns modelled into the landscape (as built, 2026-10-15, step 1; view only).** A town is no longer
a sprite but kit pieces placed on the real terrain.
- **Kit pieces** (`tools/structures/gen_spec.py` "pieces", `build.py` frame "auto", `pack.py`): `p_<piece>__y<k>`
  at 8 yaws (k * 45 degrees, front towards the south at k = 0; half-turn symmetric pieces 4, round ones 1, big
  landmarks 1 to 4): houses by culture and wall colour (colonial tile roof S / M, adobe flat roof, native hut /
  palapa / chief hut, Maya house and pyramid, haven shack / tent, Roman house / hovel / temple / basilica),
  chapel, church, cathedral, mansion, fort, fountain, well, walls (palisade, stone, bastion: straight 6 m, post /
  tower / bastion point, gate), quay, pier, crane, warehouse, shed, slipway, lighthouse, beached boats, trees and
  palms. Camera and light as before (52 degrees, NW, no bases, diorama finish). Atlases: big 2048 x 1024 (pieces
  at 4.2 px a metre, ships at 128) about 14.7 MB of video memory with its mask, small 2048 x 256 (pieces 1.97 px a
  metre) about 3.1 MB; Graphics Low loads the small one only.
- **Plan** (`town_plan.gd`, pure view, deterministic from the region index): `site(r)` is the static layout: the
  footprint (24 radii, cut by the coast field, steep ground and the half way line to the neighbours; the centre is
  shifted up to 8 px for the best fit), the way up the slope, the sea direction and shore points, street axis
  (along the contour on a hill, along the shore at a harbour, else seeded), 3 to 7 street polylines that follow
  the contour, house slots along the streets (growth order: nearest the plaza first) plus infill, ring slots for
  huts, the church spot (inland / uphill), the citadel on the highest ground, field and orchard sites on gentle
  ground. `plan(st, r)` is what the state shows: size by level (0.62 / 0.8 / 1.0 of the footprint), houses chosen by
  culture, the harbour only for a port and only when the shore is within reach (quays on the real shoreline, piers,
  warehouses, the lighthouse on the most seaward point, boats, the slipway and shed when the shipyard is built),
  walls walked round the footprint as a lattice path in 8 directions with towers and a gate where the main street
  leaves (the harbour side left open). One metre is 1.2 px at every zoom, so the town scales with the map and
  never outgrows its land. 49 plans cost about 350 ms once.
- **Draw** (`town_layer.gd`): a child of the screen's `world` (map transform: pan and zoom are free), one canvas
  item per town, drawn again only when its plan changes or the atlas size flips at a zoom threshold (only the
  towns on screen, 8 a frame), pieces sorted by y together with the map trees in the ring just outside the cleared
  ground. Overlay questions (label lift, banner side, fleet spot in the harbour's water, hit rectangle) come from
  `minis_layer.gd` statics fed by the plan. `minis_layer.gd` now only draws ships.
- **Ground** (`town_paint.gd`, `table_land.gdshader` uniform `towns`): the whole town ground (feathered clearing,
  packed earth, streets and plaza, ploughed fields and orchards, fallow meadow, tracks to the road lines, quays)
  and the cast shadows of every piece are painted once into a transparent SubViewport texture (2 world px a texel,
  3 on Low) when the map loads and again when a town changes; the land shader mixes it in before the hillshade, so
  it is lit like the land and has no patch edge. `footprint.gd` is gone: no redraw on zoom or pan.
  `landscape.gd` clears the forest inside each footprint and field and hands the ring trees to the town.
- **Landscape trees and rocks as models** (`landtrees.gd`, `landtrees.gdshader`, not Graphics Low): the map's
  tree kinds (broadleaf x3, pine x3, scrub x2, cypress, palm x2 in the tropics) and rocks (x3, crag) from the
  atlas, one MultiMesh at the old dots' positions and sizes, tinted by the palette, sorted by y; both atlas sizes
  are prepared as instance buffers at bake, a zoom threshold swaps one buffer. Their cast shadows are baked into
  the same ground texture. Low keeps the mesh dots.
- **One map look** (`map_look.gdshaderinc`, `map_look.gd`): the terrain, pieces, ships and trees include the same
  constants (north-west light, ink colour, four light bands) and share one gradient-map LUT and one tiling grain
  texture sampled in screen space; the pieces' light is snapped to the terrain's bands, saturation 1.16 after
  the LUT, the coast ink on silhouettes. Graphics Low: LUT and saturation only (no bands, no grain).
- Costs (desktop, `cbench.gd`: steady frame at zoom 1.2 and a sweep 0.6 - 2.4 - 0.6, vsync off): the map is redrawn
  on zoom only after a 35 % change or when the zoom settles (the old path redrew it on every pan or zoom frame);
  High: steady 7.8 ms (HEAD 10.1), sweep worst frame 28 ms (HEAD 54), 7 of 400 frames over 16 ms (HEAD 399, the
  rest of the sweep averages 11 ms against 35); Low: steady 8.4 ms (HEAD 8.0, +4.7 %), sweep worst 33 ms, 8 over.
  The frames still over 16 ms are the map's own few redraws. After repacking the atlas run `godot --headless
  --import`. Not yet seen on the Tab S7. Step 2: landmarks (El Morro, Cartagena's walls, Tayasal's temple), growth
  polish, ships' baked contact shadow (they keep the per-frame one).
- **Follow-up (2026-10-15, view only).** (1) A tap anywhere on a town's model (an ellipse over `Minis.model_rect`,
  `MapOverlay._town_at`, nearest centre when two overlap) is a tap on its node for every map action
  (`settlement_at`); banners and fleets still win; a fleet tapped onto a town sails to its harbour cell.
  `tests/town_tap_test.gd`. (2) Army banners at a modelled town stand on land: `_side_spot` tries the side away from
  the harbour, the other side, below, above (each nearer in steps) and takes the first whose banner corners are on land
  (`Geo.region_at`, cached per zoom); the armies' cells were on land (Syracusae's site cell is the town's), it was the
  side offset pushing banners onto the water. (3) Too much sand: `table_land.gdshader` had the coast band inverted
  (`1 - smoothstep` made all low flat land sand); now a band along the coast, warm tint of the shader and LUT eased,
  wooded ARID / DRY regions less sandy in `landscape.gd`. (4) Close towns push their centres apart (scoring term
  in `_make_site`), overlapping labels stack upwards. (5) Native kit: `longhouse`, `rack`, `stilt_house`,
  `maya_platform` pieces (gen_spec.py, atlas repacked), native villages 11 / 17 / 22 huts, council longhouse from
  level 1, drying racks, more garden fields, stilt houses on the shore; Maya temple platforms by the plaza.

- **Step 2: landmarks and visible growth (2026-10-15, view only).** Rule of cool mixed with reality: slightly exaggerated,
  instantly readable silhouettes. (1) **Landmark pieces** (gen_spec.py "landmarks and growth", diorama finish, asymmetric
  ones at 4 yaws, the rest at 1; the big atlas is now 2048 x 1152, `pack.py` rounds the height to 64): `morro` (El Morro of
  Havana, triangular on its rock with the lighthouse), `fuerza`, `san_felipe` (terraced hill fort), `morro_sj` (San Juan, tiers
  + sentry boxes), `harbour_fort` (square, four towers, sea battery: Portobelo's two forts and every West port's first fort),
  `san_marcos` (star fort in its moat), `alcazar` (Santo Domingo), `ulua` (fortress on its rock island in the roads),
  `itza_temple` (Tayasal, the tallest silhouette), `fort_charles`, `tavern`, `gallows`, `rock_fort` + `careened` (Port-de-Paix),
  `baluarte` (Campeche's walls), `twin_cathedral` (Merida), Rome: `capitol`, `byrsa`, `cothon` (circular naval harbour),
  `euryalus`, `acropolis`, `greek_temple` (Massalia; Alexandria is not a region). `town_plan.LM` maps a region key to its
  landmarks (where: harbour mouth headland / other end / highest ground / offshore rock / between plaza and sea / a row
  along the shore / by the water; least walls `wl`, least level `lv`); `_landmarks` places them before the houses (which
  keep clear: collision radii in `PD`), the lighthouse step is skipped when the Morro has one. They show whatever the owner
  (tinted to it, so a captured Spanish fort stays) and need walls >= 1 (San Marcos 2, Cartagena's long sea walls 2 with a
  baluarte every fourth piece). Cartagena's walls, Campeche's walls (bastioned with baluartes from walls 1, harbour
  open), Merida's cathedral, Santo Domingo's cathedral from level 1 and Rome's Capitol from level 1 replace the generic
  piece. (2) **Growth** (all read-only from the state, `TownPlan.facts` / `sig`; deterministic per region so a town keeps
  its layout and gains houses): level (houses 8 / 16 / 28 in towns, a second street ring `s["ring_road"]` with houses
  along it from level 1, the church / cathedral as before), **walls in the West** follow the walls history: 1 a harbour
  fort beside an open port (inland towns a palisade), 2 the fort plus a stone curtain on the landward side, 3 the full
  curtain with bastions (Rome: palisade / stone / bastions; natives get more watch posts from 2), shipyard level (1 a
  slipway + shed + crane, 2 a second slipway across the quay, 3 a second crane and a second shed), market level and town
  level (a warehouse more from market 2; moored ships in the roads: `_moored`, up to 3, drawn from the ship atlas with a soft
  shadow, none counted in the label extents), a **sack** (`regions[r].sacked`, up to 8 turns: 55 / 30 / 12 % of the houses
  burnt, smoke column, fading by age), a **siege** (`CState.siege_at`: a ring of tents, guns and flags outside the
  footprint in the besieger's colour, items may carry a faction as a 4th element). The layer's signature is
  `TownPlan.sig`; the ground and shadows repaint only when a plan changes. Gallery and strips in the session scratchpad
  `towns3/`.

- **Step 2b: ships, camps, neighbours (2026-10-15).** Fleet spot (`water`) is found by `_find_water` (open water searched
  seawards along the harbour side, disc tested against the coast field). Moored ships (`_moored`): at most 2, whole hull
  footprint wet with a margin (`_hull_wet`), searched seawards, spaced from each other and from the fleet spot, on the
  side opposite the fleet row; yaws 2 / 6 (bow-on slivers) are never used, a hull takes the nearest of the other six to
  the quay. A port with no open water has no ships. New pieces `camp_tent` (off-white canvas ridge tent, faction pennant),
  `camp_fire`, `camp_stakes`, `camp_earth` (gun mound), bigger `camp_flag`; `_siege_camp` uses 30 slots on land only,
  stakes / earthworks with guns and flags facing the walls, tent rows behind (a third row where the coast cuts the ring),
  campfires. Neighbours within 2.2 town radii shrink both footprints (down to 0.42) and the centre never drifts toward
  them. `tests/town_plan_test.gd` checks every West and Rome port.

### Audio (as built, 2026-10-10)

## DESIGN paragraph (Audio)
Sound is view-only: nothing in `sim/` or `campaign/` knows about it and nothing
is hashed. `game/audio.gd` (autoload `Audio`, reached through the static
helpers of `preload("res://game/audio.gd")`) holds a pool of 14 sample
players on buses Master <- Effects / Ambient (Effects <- five pan buses with
a Panner each). The battle reads sim counters and states after each tick
(melee `stat_attacks`, `stat_impacts`, `stat_shots`, `stat_bolts` /
`stat_stones`, `stat_crush` / `stat_amok`, `stat_released`, `u_state`
transitions, `u_stair`, gate `g_hp` / `g_state`, artillery landings from the
`pr_*` buckets, `u_burn` for the fire loop) and plays at most one clip per
event bucket per 100 ms (CAPS in audio.gd), at a volume and pan from the
event's distance and side from the camera centre. The overworld plays on
`Kit.button` clicks, orders placed / refused, end of turn, turn resolved,
battle pending (also the online notification in `OnlineCampaign._adopt`),
and the chime for treaty / trade / gift orders. Ambient beds: a battle bed
(wind and a distant march) and a map bed (quiet wind), 3 s seamless loops.
Web: nothing plays until the first tap / click / key. Volumes
(master 80 / effects 100 / ambient 60 %) and mute are in
`user://settings.cfg [audio]`, set from the home page's sound row.
Clips are generated by `tools/make_sounds.py` (numpy, fixed seeds, 22,050 Hz
mono 16-bit, about 1.3 MB for 29 files in `game/sounds/`).
