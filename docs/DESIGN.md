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

- Region-node map (settlements connected by routes), straight top-down.
- Each region has one settlement with a small number of building slots.
- Buildings come in a few chains: economy, military (unlocks units), growth/order.
- Resources: money and one growth/population value. Upkeep for armies.
- Armies recruit in owned settlements, limited by the military buildings present.

### Diplomacy

- States per faction pair: war, peace, trade agreement.
- The two players are permanently allied.
- AI accepts or refuses proposals from a simple score (relative strength, war weariness, shared enemies).

### Settlement attacks

- v1: attacking a settlement is a field battle in which the garrison joins the defender.
- As built (October 2026): every settlement has its own battle map with
  streets, walls and gates (section 4 "Battle maps: woods and settlements").
  Climbing walls, siege towers and ladders are later.

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
- Rendering uses one MultiMesh per unit type with the animation frame chosen
  in a shader, so a unit type is a single draw call.
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

**Flank and rear** for morale, disorder and bracing are judged by where the
attacker stands relative to the defending formation (ahead of its front line,
behind its rear rank, or alongside / beyond the end of the line), not by the
angle between two duellists, so oblique blows inside a frontal melee stay
frontal. Shields and the per-hit flank bonus still use the individual
soldier's facing, and a blow from beside the formation that the man has
turned to face does not count as a flank attack on the unit.

**Wrapping.** Front-rank soldiers of an engaged attacking unit who have no
enemy within reach close on the target unit instead of holding their slots,
so a wide unit laps round a narrow face (a flank) instead of leaving most of
its men idle. Formed pikemen only count as "fighting" (which holds the unit's
anchor) while their target is within pike reach, so two pike blocks close
until their points meet.

**Moving disengages.** A unit with a move (or withdraw) order does not fight:
its soldiers drop their targets and follow their slots. This is what lets
cavalry pull out and units withdraw; to fight, halt or attack. Soldiers whose
target is routing or pulling away chase at the run. Turning away costs a
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

**Artillery.** A battery is a unit whose soldiers are the crews; its
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
  battery wrecks it in seconds. A battery that routs or dies abandons its
  engines for good (no capture).
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
  (missile range from height, line of fire), a move order within 7 m of
  their stretch is projected onto it (facing out), they never withdraw or
  skirmish, and only wall units may enter the walkway (no climbing for
  attackers). Since October 2026 towers are stairs: a move order off the
  stretch takes the unit down the stair at one of its ends and on through
  the streets, routers leave the wall the same way, and defenders can be
  sent up (see "Stairs" below). Battlements stop 35 % of missiles that would
  hit a man on a wall from below. Lines of fire (flat shots) are blocked by
  buildings (4-6 m), walls (walkway + 0.6 m parapet), towers (+4 m) and
  closed gates; a shooter on a wall looks over his own battlements. Arrows
  and stones arc over everything; a stone's plough stops at a building or
  wall.
- *Gates*: start closed. The defenders may open or close one (order
  `ORDER_GATE`, any of their units; closing is refused while anyone stands
  in it; a broken gate stays broken). Hit points 1,800 / 2,700 / 3,800 by
  wall level. Batteries ordered at a gate (`ORDER_ATTACK` with `gate`)
  shoot its outer face: a bolt landing within it (1.5 m round) takes 80 hp,
  a stone 360. Foot (not missile troops, cavalry or crews) of the attackers
  standing at a closed gate (within 2 m of its face, not marching past)
  hack at it: each of at most 10 men takes (damage - 20) x 25 % per swing.
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
the attacker sends the selected batteries or foot at it. Sandbox:
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
  the main gate at the end of a **funnel**: the wall turns in 30-38 m at an
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
A defending infantry or missile unit on the ground ordered onto a walkway
(within 3 m of a stretch's centre line) marches to the foot of the better
stair, climbs (trail foot -> stair -> walkway) and takes the stretch at the
ordered point. Attackers never climb (no ladders or towers yet). State
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
the standard 12-unit attacker, AI vs AI, 8 seeds a row; wins attacker /
defender / draws %, minutes to decide, attackers / defenders killed):

| Plan, site | walls 1 | walls 2 | walls 3 |
|---|---|---|---|
| ring, plain (baseline) | 100/0/0, 7.6 min, 349/429 | 100/0/0, 10.3, 470/545 | 100/0/0, 9.4, 473/599 |
| ring, hill (plateau) | 100/0/0, 10.1, 367/498 | 87/12/0, 10.0, 436/478 | 100/0/0, 11.2, 485/558 |
| castrum, plain (ditch at 3) | 100/0/0, 5.4, 291/293 | 100/0/0, 6.9, 386/333 | 75/25/0, 8.5, 476/401 |
| polis, coastal hill | 87/0/12, 10.9, 403/595 | 75/0/25, 11.5, 400/674 | 62/25/12, 12.3, 498/631 |
| polis, plain | 87/0/12, 11.0, 418/562 | 75/25/0, 10.7, 444/607 | 25/37/37, 12.8, 491/559 |
| punic, coast | 100/0/0, 9.1, 383/611 | 87/12/0, 10.7, 466/650 | 25/50/25, 12.1, 550/552 |
| oppidum, spur | 75/0/25, 9.9, 404/523 | 50/37/12, 11.5, 503/597 | 12/50/37, 11.7, 600/441 |
| oppidum, plain | 50/0/50, 11.2, 405/428 | 62/25/12, 10.0, 575/539 | 12/37/50, 13.8, 583/386 |

- The citadel and the funnel cost the attacker more than the plain ring:
  longer battles, more draws and defender wins, and (oppidum) more
  attackers killed; with a citadel the defenders fall back into it in 7-8
  of 8 battles and the attackers broke its gate in 1-8 of 8; captures
  come from the plaza (castrum, ring, oppidum) or not at all (citadels:
  the defenders were destroyed or broke first).
- **Not degenerate at walls 1-2, too strong at walls 3** for the citadel
  and oppidum plans: at walls 3 the attacker wins 12-25 %, and the oppidum
  and polis draw up to 50 % at the 15-minute limit. The draws are a slow
  grind (about 10 defenders a minute die at a funnel gate or the citadel's
  8 m gate, where only a few men at a time can fight), not a deadlock.
  Open: tune before relying on walls 3 in the campaign (see STATUS).
- Castrum on a plain with a ditch: foot use the causeways; in a scripted
  crossing heavy foot wade it (119 unit-ticks in it), riders never enter.
- Benchmarks (before -> after, mean / p95 / max ms per tick):
  bench_4000 2.71 / 4.57 / 5.89 -> 2.73 / 4.62 / 6.15 (code unchanged on
  flat maps: noise); bench_4000_hills 2.99 / 4.26 / 6.20 -> 3.07 / 4.45 /
  6.80 (likewise); bench_4000_city 2.80 / 4.95 / 7.68 -> 2.83 / 4.92 / 7.49
  (now decided at 8.4 min); new bench_4000_polis (coastal hill, acropolis)
  2.87 / 4.77 / 7.38-9.51, setup 141 ms; new bench_4000_castrum (plain,
  walls 3) 2.86 / 5.04 / 7.36, setup 109 ms. No worst tick builds a path
  table any more (at most 2 a tick); the ticks over the 6.45 ms budget are
  a plateau of the crowded breach melee (~250-320 obstacle-checked target
  searches a tick, 6.4-7.4 ms over ~150 ticks), not a spike.
- Auto-resolve wall time (`tests/campaign_battles.gd --only=timing`, before
  -> after): 12 v 12 full 5.4 / 6.4 -> 6.8 / 6.1 s, half 3.7 / 3.4 -> 4.3 /
  3.9 s; 24 v 24 full 12.2 / 12.5 -> 15.3 / 13.7 s, half (used) 7.2 / 7.1
  -> 2.9 / 2.8 s (those two now end at 3.5 min); per tick 10-20 % dearer.
- Generation: 15-110 ms a map (punic cities with walls 3 and a ditch the
  most), terrain 5-40 ms.


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
adds the speed (quarter ticks: 2 / 4 / 8 / 16 for 0.5x / 1x / 2x / 4x) to an
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
"Rome Pause?"); No clears it; asking again withdraws it. Applied on the
same frame for everyone. Solo battles keep immediate pause and speed; the
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
Menu; the readout (left) is one short line (fps, battle clock), tap for the
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
`docs/screenshots/hud_*.png`. Testing aids: `--ui-dpr=X --ui-touch=0/1
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
