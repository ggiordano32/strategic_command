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
family/politics, agents, naval combat, walled sieges, accounts, anti-cheat,
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
- Later: walls and gates.

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
| Archers | 18 | 16 | 3 | 0 / 0 | 24 | 1.0 | 75 | 4.0 | 140 m, 20 arrows, 4 s reload |
| Javelinmen | 28 | 22 | 3 | 20% / 35% | 28 | 1.2 | 80 | 4.2 | 40 m, 4 javelins, 2.8 s reload |
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
| Shots per engine | 7 | 10 |
| Reload at full crew | 7.5 s (silent below 2 crew) | 15 s (silent below 3 crew) |
| Flight | 55 m/s, leads moving targets | 28 m/s, no leading |
| Scatter (triangular, x1.5 along) | 0.3 m + 1% of range | 1.5 m + 4% of range |
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
- *Stones* land at the scattered point: everyone within 0.9 m is struck, then
  the stone ploughs 9 m on along its flight through anyone within 0.6 m
  (1.0 m horses), losing 5 energy per metre and 30 + armour per body, at most
  6 men; damage = energy - armour x 50%, knockdown (energy / 2 + 20)%. No
  shield helps. An engine in the path takes double damage (counter-battery).
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
artillery, seed 42): 4,000 soldiers mean 2.93 ms per tick (milestone 1
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

## 8. Art

- Placeholder top-down sprites, tinted per faction, until the game is proven fun.
- Per unit type: idle, walk, attack, die. One sprite sheet each.

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
   Deferred: horse archers, fatigue, terrain, and line-of-sight for javelins
   at soldier level (it is checked unit to unit).
   Then (battle depth): artillery (bolt and stone throwers) as above.
3. **Minimal campaign.** Small map, armies, recruitment, buildings, economy,
   pending battles, auto-resolve, campaign AI, diplomacy states.
4. **Async backend.** Save store, turn submission, Discord pings, hosted on Proxmox.
5. **Live co-op battles.** Lockstep over the relay, unit gifting, reinforcements,
   desync recovery.
6. **Depth.** Walled sieges, more factions and units, tech, enemy-control mode.

## 10. Main risks

1. Per-soldier sim performance in a phone browser.
2. Touch controls for real-time tactics.
3. Battle AI good enough to be worth fighting.
4. Keeping the sim deterministic as features are added.
5. Scope creep in the campaign layer.
