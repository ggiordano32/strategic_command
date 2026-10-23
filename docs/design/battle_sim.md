# Battle sim

Moved verbatim from `docs/DESIGN.md` on 2026-10-22 (the docs split; index in `docs/DESIGN.md` and `docs/design/README.md`). Design sections first, then the "as built" sections in date order.

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
smoke and a ground dust kick; **a puff and a flash with every shot (2026-10-23)**:
the overlay's missile walk (`_tr_note`) sees each new gun missile (men's
or an engine's) and puts the puff at its start toward its target (men in
line or at will, a bound's holding team, riders: all alike; one puff a cell
a second keeps a volley of 80 a bank, not a wall), and notes the shooter
unit's shot tick (`Overlay.shot_t`, view only); the soldier layer turns it
into the flag bits 16 fired (under `FLASH_TICKS` = 3 ticks, 0.3 s) and 32
gun unit. The sprite sets' attack frame 1 is the muzzle flash: a gun man
aiming or reloading (8 shooting) plays frames 0, 2, 3 slowly (about a third
of the attack rate) and shows frame 1 only in the fired window; the old
volley-restart check (`_gun_volleys`, formed men only) is gone; a capped lingering haze builds over a long
firefight. Diorama tints it cotton-white, painterly grey. Graphics Low: fewer
puffs, no ring, dust or haze. The `musket` and
`cannon` clips (`stat_volleys`, `stat_cannon`). Later: smoke that blocks
aim in the sim (cover and line of sight: built, "Cover and line of sight"), gun ammunition kinds
and wagon refills (an `AMMO` row would change the hashed wagon stock
width: needs the same gating).

**Heavy guns (West, owner 2026-10-23).** `heavy_gun` ("Heavy Guns", short 24-pdrs), line `field_gun` (its second tier), icon 29, the cannon sprite and engine sets as the culverins; a row after the fort gun (`UnitTypes.WEST_LATE`, so every earlier row index is unchanged). The West artillery now: falconets (light_gun, Workshop 1: size 12, 300 m, damage 230, reload 25 s, 360 a unit), culverins (field_gun, Workshop 2: 450 m, damage 320, reload 40 s, `m_obj` 450, 480 a unit), heavy guns (Workshop 3): size 12 (three pieces, four gunners each), range 520 m, damage 420, ap 100, pierce 10, plough 60 m, fear 90, `m_obj` 700 (the wall breaker), reload 52 s, walk 0.4 m/s, deploy 24 s, 10 shots and 10 in reserve, e_hp 400, cost 60 (720 a unit). Raised by the nations only.

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

## The Caribbean roster, batch 1 (plan, agreed 2026-10-23)

The owner, 2026-10-23: "The different units for different armies is exactly where I want to go with it. They
should feel like they need to be played differently." Rome has about thirty rows, the Caribbean twelve (plus the
heavy guns of the same day). The aim is not thirty Caribbean rows but two or three units per side that nobody else
has, so a Spanish army, an English one, a pirate crew and a Miskito war party read differently on the field. Three
batches; the first (six units and the mortar) is agreed, the second (mounted arquebusiers, marines, landed naval
guns, colonial militia, maroons) and the third (a sea captain hero, a privateer, a missionary) wait for play.

**Batch 1.** Every unit is a West row (`sim/unit_types.gd`, `"pack": "west"`), a sprite set through the pipeline
(`tools/sprites/spec.json`, a pose and props each; the set id field is 5 bits with 26 of 31 used, so the pipeline
widens it to 6 bits or shares a set where the pose allows), an AI mix entry (`campaign/data/west.gd`), a unit book
page and a custom battle list entry. The sim already has what they need (the blast missile, the cover trait and
ambush, arcing fire, no shooting on the move) except two small traits noted below.

- **Grenadiers** (England; Barracks 3): elite foot (attack and morale between rodeleros and cutlass men, armour
  light) with a lobbed grenade: `m_kind` arc, `m_range` 25 m, `m_min` 6 m, blast radius 3 m (the `blast` ammo stat),
  4 grenades, reload 15 s, `m_obj` enough to hurt a door in a few throws; the answer to pike blocks, held buildings
  and a gate's press. Played: brought up behind the shot, thrown in at the moment of contact.
- **Dragoons** (England and France; Stables 2 + Range 1): horse-paced foot: `cls` cav for pace and footprint, a
  musket at twice the musketeers' reload, no fire on the move (the sim's rule), weak in melee, cheap to lose. Played:
  the flank-and-harass piece, a line of fire where the foot cannot be in time.
- **Coureurs des bois** (France; Range 2): woodsmen with `cover`, ambush and the new trait **woods pace** (a per-type
  factor on the move cost of woods and scrub, `t_wood_pct`, the sim's path costs; integers, deterministic, other units
  untouched); a musket at the buccaneers' accuracy, fewer rounds. Played: through the trees where no line can follow,
  into the flank, out again.
- **Boarding grenadiers** (the Brethren; a haven's Barracks 2): cutlass men with two grenades each (as the grenadiers'
  but 15 m and two), the deck bonus of `DECK_CREWS`; deadly in a melee and at a gate, brittle under fire. Played: the
  pirates' door-opener, by sea or by land.
- **Canoe raiders** (Miskito; Barracks 1): light foot with `cover` and javelins, fast, and the new campaign trait
  **amphibious** (`campaign/`: an army of only amphibious units moves along coastal sea cells within one cell of land
  at foot pace without a fleet and lands anywhere; `CGrid` / `CFleet.coastal_link`; pack-agnostic, hashed only when an
  army has the trait). Played: raids from the water on an undefended coast, gone before the column arrives.
- **Holcan warriors** (Itza; Barracks 2): shock foot with obsidian-edged clubs: high attack and charge, fear on the
  charge, no armour, morale high while winning; the Itza's one unit that can break a line. Played: held back, then
  thrown at a flank or a shaken unit.
- **Mortars** (the nations; Workshop 3): an engine (one set) with `m_arc` high, `m_range` 300 m, `m_min` 60 m, a
  blast shell, slow reload, poor against anything moving; fires over walls into forts and held buildings. Played:
  the siege answer the Caribbean lacked; the player who brings none assaults bastions the hard way.

**Order of work.** (1) Sprites for all seven (one agent: the set field widened to 6 bits if needed, the poses, the
atlas rebuilt, `soldier_facing_test` on both paths); (2) the two sim traits (woods pace; the grenade is the existing
blast missile with an arc) and the campaign's amphibious move (Opus for the hashed paths); (3) the rows, AI mixes,
unit book, custom battle lists, recruit chains, tests and the West pins (Sonnet). Then a playtest and the AI's use of
each piece (grenades at a gate, dragoons on a flank, mortars at a siege) as follow-ups.

### The Caribbean roster, batch 1 (as built, 2026-10-23)

Seven rows after the heavy gun in `UnitTypes.WEST_LATE` (so every earlier index, the fort gun's and the heavy gun's
included, is unchanged; `pack_test _batch1`), sprite sets 27-33 of `art_pipeline.md`, two new ammunition kinds appended
to `AMMO` (indices 11 and 12; `grenade` and `shell`, both standard kinds, `base` -1, `aoe` 1: every man within the
burst is struck, full damage at the centre to a third at the edge, the survivors thrown and down, no plough). Their
`obj` is the stone's gate / tower damage (360) times 27 % and 111 %: about 96 and 400 a hit, the row's `m_obj` (120,
500) at the bolt's 80 per 100. The row `m_obj` itself is stored for the destruction build; the lobbed landing reads
the kind's `obj`, not the row's.

| Row (key) | Line, tier | Buildings | Who | Men, cost | Melee | Missile |
|---|---|---|---|---|---|---|
| Grenadiers (`grenadiers`) | `grenadier`, 1 | Barracks 3 (West Barracks has 3 levels) | England | 60, 8 (480 a unit) | attack 41, defence 30, armour 5, hp 95, morale 900, walk 1.45 / run 4.1 | grenade: 25 m, min 6 m, 4 a man, reload 15 s, damage 150, burst 3 m, fear 80, `m_obj` 120 |
| Dragoons (`dragoons`) | `dragoon`, 1 | Stables 2 + Range 1 | England, France | 40, 10 (400) | cls cav, mount horse, attack 26, defence 24, charge 25, hp 130, walk 2.2 / run 8.6 (lancers') | musket as the musketeers' (120 m, damage 120, 20 a man) at reload 24 s (twice), `m_gun`, no fire on the move |
| Coureurs des Bois (`coureurs`) | `buccaneer`, 2 | Range 2 | France | 50, 8 (400) | as buccaneers (attack 28, morale 680), `cover` 1, skirmishing | buccaneer musket (140 m, 130, `m_spread2` 100), 22 rounds (buccaneers 24); `woods_pct` 45 (native warriors and bowmen 60 were the best) |
| Boarding Grenadiers (`boarding_grenadiers`) | `heavy`, 2 | Barracks 2 | the Brethren | 60, 7 (420) | the cutlass men's exactly (40 / 26, armour 3, hp 90, morale 700, cover) | grenade: 15 m, min 3 m, 2 a man, reload 12 s |
| Canoe Raiders (`canoe_raiders`) | `light`, 2 | Barracks 1 (`UNIT_NEEDS`) | Miskito | 60, 4 (240) | attack 38, defence 24, walk 1.85 / run 5.0 (warriors 1.75 / 4.8), `cover` 1, `amphib` 1 | the Rome javelinmen's javelin (40 m, damage 42, ap 60, 6 a man) |
| Holcan Warriors (`holcan`) | `heavy`, 2 | Barracks 2 | Itza | 60, 6 (360) | attack 46, defence 26, damage 46, armour 0, hp 100, morale 900 | none |
| Mortars (`mortar`) | `mortar`, 1 | Workshop 3 (`ART_LEVEL`) | New Spain, Tierra Firme, England, France, the Dutch | 12 (3 pieces of 4), 50 (600) | crews as the guns' | shell: 300 m, min 60 m, 8 a piece, reload 60 s, damage 200, burst 4 m, `m_arc` 1 (over walls), spread 6 % + 2 m, speed 30 m/s, `m_obj` 500, walk 0.4, deploy 24 s, `e_hp` 320 |

**What differs from the plan.**
- **Class.** The grenadiers, boarding grenadiers and canoe raiders are `cls` missile, not infantry: the sim runs the fire
  logic (`_missile_think`, `_update_missiles`, the stand-off at 85 % of the range) for missile, cavalry and artillery
  classes only, so an infantry-class unit with `m_ammo` never shoots. As missile troops they stand off and throw, and with
  the ammunition gone they close and fight (their melee is the row's). The holcan stay infantry.
- **Minimum range.** `m_min` was read for artillery only. `BattleSim._in_range` now refuses a target nearer than the
  unit's `m_min` (default 0: no other foot or horse row has one), so grenadiers do not throw at men in contact with them.
  Per-man `_fire` still does not check it.
- **Slots.** The roster is tier-indexed: the coureurs take the buccaneer line's second place (Range 2), the boarding
  grenadiers and the holcan the heavy line's second place (Barracks 2), the canoe raiders the light line's second place
  but with Barracks 1 through `UNIT_NEEDS` (as `heavy_gun` does for the Workshop). The AI recruits the highest place it
  can, so the French AI raises coureurs at a Range 2, the Brethren's boarding grenadiers at a Barracks 2, the Miskito's
  canoe raiders everywhere (their warriors stay in the starting armies and the player's list). Since the West AI pass
  (2026-10-23, docs/AI.md 34) the three are the pack's `AI_SPECIALISTS`: the AI raises them for `SPECIALIST_PCT` (30 %)
  of their line and the line's main unit otherwise, and the canoe raiders muster as their own amphibious band.
- **No charge-fear stat for foot.** `fear_r` / `fear_foot` is a standing aura (elephants) and `charge` the horse's
  impact; the holcan's shock is their attack and damage alone.
- **Icons.** The rows reuse existing glyphs (24, 28, 26, 25, 32, 32, 29); the new tier-2 rows carry the tier chevron.
- **Deck fights.** `ST.DECK_LINE_SHOT` gained the `grenadier` and `dragoon` lines and `ST.DECK_UNIT_SHOT` (by unit key) the
  boarding grenadiers, whose line is the cutlass men's; the Brethren's `DECK_CREWS` kit is unchanged.
- **AI mixes** (sums as before; the new line's share is taken from its nearest line): New Spain light_gun 5 -> 3 + mortar 2;
  Tierra Firme light_gun 5 -> 3 + mortar 2; England musket 40 -> 37 + grenadier 3, pistol 20 -> 17 + dragoon 3, field_gun
  5 -> 3 + mortar 2; France musket 35 -> 33 + mortar 2, pistol 15 -> 12 + dragoon 3; the Dutch field_gun 10 -> 7 + mortar 3;
  the Itza light 60 -> 52 + heavy 8 (holcan). The Brethren and the Miskito have their units inside existing lines.
  `composition` is untouched (the new lines are not main arms). The AI's build-up asks for a Workshop of at most level 2
  and a Barracks 2, so it does not yet build the Workshop 3 or Barracks 3 the mortars and grenadiers need (follow-up;
  done 2026-10-23: the pack's `AI_BUILDUP_LINES`, docs/AI.md 34).
- **Lists.** `LINE_ORDER` has `grenadier` after heavy, `dragoon` after pistol and `mortar` after the field guns;
  `WEST_LINES` (the custom picker) and the unit book's building table likewise; the West `CHAINS` texts name the new units
  where they are built. The unit book reads the rows by itself.

## Roles and abilities (plan, agreed 2026-10-23)

The owner, 2026-10-23: units should fall into categories a player reads at a glance, richer than ranged versus
melee ("skirmishers vs linemen"), so the asymmetry of the sides can grow without a lesson per unit; abilities such
as grenades should be automatic in sensible situations and triggerable by hand; the battle UI is crowded and will be
reworked around that. Agreed as proposed, in three steps.

**Roles.** A `role` key on every unit row, one of: `line` (musketeers and veterans, pikemen, Rome's swords, spears,
pikes: hold formation, volley or at will, partial cover with some men ducking, no explosives, the blade when
engaged), `skirmish` (buccaneers, coureurs, native bowmen, canoe raiders, javelinmen, slingers: loose order, every
man to cover, occupy houses, ambush, fall back when charged with Skirmish on, short abilities), `missile` (archers,
gastraphetes: formed volleys at range, no cover craft, helpless in melee), `shock` (rodeleros, cutlass men, holcan,
grenadiers, boarding grenadiers, heavy swords, war dogs: the charge, a breach, a door, a gate; poor at holding),
`horse_shock` (lancers, shock cavalry), `horse_skirmish` (pistoleers, dragoons, light horse, camel archers: ride
in, fire, retire; charge only when ordered), `guns_field` (bolt throwers, scorpions, falconets, culverins: at men),
`guns_siege` (stone throwers, heavy guns, mortars: at walls and buildings), `command` (generals, heroes, agents),
`beast` (elephants, camel riders). The book keeps "beats" / "loses to"; each role has a two-line "plays as" on a
Roles page of the Key and in the book, a badge glyph and a colour band on the unit card and the selection bar; the
selection filters become Line / Skirmish / Shock / Horse / Guns. **Step 1 is data and view only**: the key on every
row (both packs; a test asserts every row has one), the badges, filters, book grouping, the Roles page; no sim
change, no hash moves.

**Behaviours (step 2, sim).** `skirmish`: loose order by default (wider spacing) and cover seeking (each man drifts
to the nearest cover point within a few metres when halted in the Cover stance); `line` keeps today's partial cover;
**pistols at contact** (an ability on buccaneers, coureurs, pistoleers, dragoons: a point-blank shot in each of a
man's first two melee rounds, then the blade; a man with both pistols spent steps back a rank and reloads over
30 s while a loaded man steps forward, on the shooter-pointer rotation); **grenades as an ability** (grenadiers,
boarding grenadiers, later buccaneers: thrown automatically at a formed block, a held door or a gate when the unit
closes to range; the plain missile path of batch 1 becomes the Auto trigger); **caracole** for `horse_skirmish`
(ride to pistol range, fire, retire, on the bounds logic); `guns_siege` target walls and buildings when ordered to
batter. All deterministic, hashed, snapshotted; the AI learns each role once (the AI follow-up of destruction and
the roles' triggers are one piece of work).

**Abilities and the HUD (step 3).** Every ability has three states: Auto (the default, with its trigger), Hold
(saved), Use now (arms a target pick, as Occupy lights the buildings). Halt, Run and Withdraw stay fixed; the rest of
the bottom-right row becomes ability chips the selected unit's role has: `line` Fire at will, Stance, Formation;
`skirmish` Skirmish, Occupy, Grenades, Ambush; `shock` Charge, Grenades; `horse_skirmish` Caracole, Charge;
`guns_*` Target (men / walls / buildings), Ammo. A chip cycles its three states on tap; the unit card shows the role
badge and the chips' states; the Key's Roles page explains each role in two lines.

**The asymmetry principle (owner, 2026-10-23).** "Exaggeration founded in history": each side's roles are pushed
past the historical record in the direction history points, so the sides play differently rather than as
re-skinned mirrors. The test case: the natives can win a fight against the Spanish if played correctly (woods,
cover, ambush, the water, a raid and gone), and head-on in an open field the Spanish really come out on top (the
tercio's pike and shot, the line's volleys, the horse). The roster expansion (batches 2-3) and the role behaviours
(step 2) are judged against this: a native army should have no unit that stands in a line and trades volleys, and a
Spanish army none that melts into the trees; the pirates sit between (boarders and marksmen, no line); England,
France and the Dutch share the line and differ in their specialists.
