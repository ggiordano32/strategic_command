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

### Lobbing over a wall (as built, 2026-11-02)

Why (the owner's phone playtest, besieging a city): "Archers are now very
powerful against units that are in the city. If the city defender can only
put a couple of archers in range on the wall, a stack of 5 archers outside
can overwhelm them. If the units want to hit an enemy close to the wall on
the inside, they should need to be way closer to send a volley up and back
down." And later: "I know armies sieging cities brought large cohorts of
archers historically, so this isn't a bad thing, I just want to make sure
the game is still fun to play." So the besiegers' archers are not blunted;
they pay in position: to reach men behind the wall they must come well
inside the wall archers' reach.

**The rule.** An arcing soldier weapon (`m_arc` 1 with no crew and no
engines: archers, slingers, camel archers, the elephant's javelin men, the
master of archers, grenadiers, torch raiders, the native bowmen and every
tier row of them) fired by a unit on the ground at a unit on the ground
across a standing wall stretch or a shut gate reaches `ARC_OVER_WALL_PCT`
(60) % of its range: the shot goes up steeply and comes down. Both ways:
archers inside shooting out over their own wall at men on the ground
outside are cut the same, which keeps the defenders' archers up on the walk
where they belong. Not cut: fire from a unit on a wall (the walk shoots
down at men below with `WALL_RANGE_PCT` as before), fire at a unit on a
wall (the battlements' `WALL_COVER` as before), a unit on a ladder move or
a siege tower (`u_lq`), tower engines (`fixed`), and artillery (stone
throwers and mortars have crews: they lob over everything at full range).
"Across a wall": the straight line between the two units' middles crosses
a wall body, walkway, stair or tower cell, or a shut gate's cell, sampled
every `ARC_WALL_STEP` (4 m) on the 2 m obstacle grid (a wall band is 8-12 m
thick, so a sample always lands in it); rubble (a breach) and an open or
broken gate let the line through. With 140 m bows the lob reaches 84 m;
the archers on a walls-2 walk reach 161 m plus the height (`m_hgain`), so
the lobbers stand far inside their answer (the number must stay below
100 / (100 + `WALL_RANGE_PCT`), 87 %).

**Where it is read.** One place decides: `range_vs(u, t)` cuts its range
when `lob_over_wall(u, t)`; `lobber(u)` is the shooter half,
`wall_cross_at(x0, y0, x1, y1)` the line (the distance of the first wall
sample, -1 none). So `_in_range`, fire at will's target scan (an extra test
for targets within the flat range but past the lob: "too far to lob over
the wall"), the attack order's closing (`stop` is 85 % of `range_vs`, so a
unit told to shoot a man behind the wall walks in to the lob's reach, or as
near as its ground goes), the battle AI's hold-fire and artillery scans and
the siege AI's `_anyone_in_range` all see the cut range. Each shot
(`_fire`) and the per-man aim (`_pm_sight`) cut `rp` the same way, by the
units' middles (one decision per unit pair, not per man). The siege AI's
defenders under fire (`_df_safe`) count a spot behind a wall past a field
shooter's lob as safe. No new state: two constants (`ARC_OVER_WALL_PCT` a
static var like the other siege levers, `ARC_WALL_STEP`); the obstacle grid
and the gate states it reads are hashed already.

**The view.** The range ring (`overlay.gd` `_draw_range`) pulls in where it
crosses a wall: beyond the wall it is the lob's radius (or the wall itself
where the lob falls short of it). An attack order on a man behind the wall
out of the lob's reach says "TOO FAR TO LOB OVER THE WALL: MOVING CLOSER"
where it said "MOVING INTO RANGE".

**Measured** (a scratch probe, 8 seeds, a walls-2 castrum at level 2: five
archer units of 80 outside with two heavy and two spear 100, against two
archers 80 and three spear 100; men; "exchange" is the attacking archers'
kills of the wall archers : the wall archers' kills of the attacking
archers):

| case | ARC % | attacker wins | attacking archers' kills (men on the wall / on the ground) | their losses | wall archers' kills / losses | exchange |
|---|---|---|---|---|---|---|
| both AI, the full siege | before | 8 / 8 | 151 (84 / 67) | 241 | 216 / 141 | 0.56 |
| | 50 | 8 / 8 | 135 (89 / 46) | 219 | 209 / 136 | 0.56 |
| | 60 | 8 / 8 | 138 (88 / 50) | 219 | 209 / 137 | 0.57 |
| archers stood 95 m off the gate, 6 min, no assault | before | | 112 (52 / 60) | 237 | 208 / 102 | 0.49 |
| | 50 | | 63 (57 / 6) | 211 | 188 / 55 | 0.29 |
| 70 m off | before | | 135 (52 / 84) | 232 | 203 / 113 | 0.56 |
| | 50 | | 62 (56 / 6) | 211 | 188 / 54 | 0.28 |
| | 60 | | 73 (56 / 17) | 237 | 207 / 65 | 0.31 |
| 50 m off | before | | 136 (55 / 80) | 258 | 245 / 101 | 0.41 |
| | 50 | | 93 (67 / 26) | 252 | 239 / 70 | 0.29 |
| | 60 | | 124 (58 / 66) | 250 | 237 / 80 | 0.34 |
| | 65 | | 125 (59 / 66) | 254 | 241 / 83 | 0.35 |

What it shows: the rule takes away the stand-off's kills of men behind the
wall (95 m off: 60 -> 6; 70 m: 84 -> 17), and gives them back to archers
that walk in (50 m off at 60 %: 66 of 80). The fire at the walk is
untouched (52-67 men either way). The exchange with the wall's archers
was already against the besiegers before the rule (0.41-0.56: two units on
the walk shoot down into deep blocks on the ground while the besiegers'
arrows at a two-deep line on a narrow walk mostly miss, and the battlements
take 15 %); the rule lowers it further only because the besiegers no
longer pick off the wall's archers when they come down to the street
behind the wall. 60 was chosen over 50: at 50 the lob reaches 70 m and
archers 50 m off the wall still lose two thirds of their kills behind it;
60 (84 m) keeps the stand-off safe for the men inside and lets archers who
close in do their work, all of it inside the wall archers' 161 m. The AI's
full siege barely moves (8 / 8 either way, 6.3 -> 6.4 min): its archers
stand 110 m off the gate (`S_COVER_OUT`) and shoot the walk.

The equal-force sieges (`tools/balance` `rome_walls`, 6 Rome towns x walls
1-3 x 8 seeds, 144 battles, code 4822cadaad -> 19ed1045b0): attacker wins
71 / 40 / 31 % -> 75 / 50 / 38 % (walls 1 / 2 / 3; pooled 47 -> 54 %), no
cell beyond its interval (the 32-seed reference of 2026-10-31 was
73 / 41 / 31). The lean toward the attacker is the rule's other half: the
defenders' archers on the ground behind the wall lob out at 60 % of their
range, and the attacking archers no longer shoot at men behind the wall
from their post either; walls 2 moved most (Sicily 38 -> 75, Arverni
0 -> 25, Latium 88 -> 100, Attica 25 -> 12), on 8 seeds a cell is +-28.
Campaign pins unchanged (battles settle by formula).

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


The siege AI's covering archers walk in to a stand inside the lob's reach once the walls before their post
are clear (2026-11-02, `S_LOB_PCT`): siege_and_towns.md "Archers walk in to lob over the wall (as built,
2026-11-02)", docs/AI.md 56.

### Guns on a tower fire over their own parapet (as built, 2026-11-02)

The owner, defending a West harbour-fort town (Portobelo) against the AI on a phone: "If cannons are on a wall they
should not be blocked by their own tower, they should be able to fire on armies out in the field." The fort's guns
(`UT.FORT_GUN` on the trace's platforms, wall units of their stretch) drew their lines to the attackers red with "NO
LINE OF FIRE", the gun by the gate too.

- **Cause.** `lof_block` ignored obstacles near the shooter only for a man whose own cell is a walkway (`wall_t` + 2 m)
  or within a tower engine's `tower_r` + 1 m (`_skip0`, 5 m for a fort gun). A fort gun stands on its platform's wall
  body (`C_WALL`) 7 m inside the round corner tower that the sim stands at every turreted vertex (radius 11-15 m,
  `MapGen.fort_towers`; its cells' top `wall_h` + 4 m, the gun's eye `wall_h` + 1.5 m), so its line out met its own
  tower 11 m away and stopped there. On Portobelo at walls 1 two of the four guns had a line to no attacker at the
  start and the fort's guns fired 1 shot in 8 battles at walls 1 and 1 at walls 2.
- **The rule** (`own_works_skip`, read by `lof_block` for every caller: `lof_units` (fire at will, the artillery scan
  and `art_safe`, the attack order), the men's own lines, `_shot_ok`, the siege and battle AI's spot tests and the
  overlay's preview, which now also passes `_skip0` / `_skip1`). A shooter standing on a wall's body, walkway, stair,
  gate or tower cell shoots from its top: along its line, the structure it stands on does not block: wall cells up to
  `wall_t` + `OWN_WALL_EXTRA` (2 m) from it (its stretch and the parapet: the walkway's old rule, now for every works
  cell), the first tower whose cells begin within `OWN_TOWER_NEAR` (10 m: the tower it stands on or beside) and the wall
  cells within 2 m past that tower; nor does the ground under those cells (a wall across a slope). The first cell that
  is not its own ends it: another tower (a gun on the north tower does not shoot through the south tower), a wall cell
  farther on (the far side of the fort), a house or open ground; terrain crests, rocks, cliffs and trees beyond block as
  before. Agrees with the lob rule (`lob_over_wall` already exempts fire from a wall unit and tower engines). No knob,
  no new state.
- **Measured** (`tools/balance`, 8 seeds, before a clean copy of HEAD; the zone change of the same day is not in these battles, which have no deployment phase). The fort guns (a scratch probe, the session scratchpad siege/fortgun_probe.gd: AI against AI, walls 1 / 2, 8 seeds): Portobelo shots 1 / 1 -> 163 / 151, kills 0 / 0 -> 315 / 326 (attacker wins 4 / 1 -> 1 / 0); Cartagena 101 / 164 -> 109 / 158 shots, 287 / 351 -> 299 / 327 kills; Havana identical (its guns were not blocked). `west_walls` attacker wins pooled walls 0 / 1 / 2 52 / 44 / 27 -> 52 / 34 / 27 % (overall 41 -> 38 %); two cells beyond their interval, both walls 1: Portobelo 50 -> 12 %, St. Augustine 75 -> 25 %. `rome_walls` walls 1 / 2 / 3 71 / 48 / 40 -> 75 / 52 / 42 % (overall 53 -> 56 %, no cell beyond its interval: the walk men near a tower). No tuning round (under the 8-point stop overall; the walls-1 drop is the owner's call). campaign_pins Rome and West MATCH (battles settle by formula); settlement battle hashes move where a man or gun on the works shoots; the rules hash moves; no VERSION bump).
- **Tests.** determinism_test `--only=deploy` `_check_tower_gun_lof` (Portobelo walls 1: each fort gun whose line out
  from the fort crosses its own tower within 10 m has a line of fire into the field; a line from it through another
  tower of the fort 30 m or more away stops at that tower).
- **Known.** The seaward curtain's gun on Portobelo stands on a walk whose ground is 2.8 m while the fort's pad is 25.5
  m (the walls cross the fall to the shore), so landward it still sees nothing (out of its sector anyway); a walk unit
  within 10 m of a tower now shoots past that tower's body; the fort guns' 60-degree sector (`FORT_GUN_SECTOR`) is
  unchanged.

### Shots strike the walls they cross (as built, 2026-11-06)

The owner: "the cannons and rock throwers should impact the walls if the collision would pass through a wall or
palisade. Right now the rock thrower can tend to go through walls-2 towers in order to hit the units right against the
wall. Overall it is working great though."

**What was there.** An engine's stone (`m_kind` 2: stone throwers, the tower engines' stones, mortars) flew to its
scattered landing point whatever stood between: "lobbed over everything" (`lob_over_wall` exempts crews), so a stone
aimed at men pressed against the inside of a wall came down among them through the wall, a walls-2 tower or a shut gate.
A flat ball or bolt (`m_kind` 1: field guns, the fort guns, the ships' batteries, bolt throwers) was already traced
(`_land_bolt`'s `lof_block` with its 2 % apex) and stopped at the first wall, house, crest or tree it met, doing a
stretch or a building its hit points there (`_destr_hit`), but a shut gate or a tower that stopped it took nothing (a
gate only from a shot aimed at it, `_gate_hit`; towers have no hit points). Arrows and musket balls stop at faces
already ("Buildings block a flat shot").

**The rule** (sim; one decision at launch, deterministic, no new per-unit state).
- *The arc.* An engine's stone flies the parabola the views draw (`projectiles.gdshaderinc`'s `hk` 0.28 for stones):
  its rise above the straight line at mid-flight `STONE_APEX_PCT` 28 % of the distance (a 120 m shot tops out 34 m up,
  coming down at about 48 degrees), from `LOF_EYE` over the engine's footing (`elev_at`: a tower engine at its walk) to
  `LOF_BODY` over the landing point's. `arc_strike` samples it every `ARC_STRIKE_STEP` 2 m (the obstacle grid's cell:
  a palisade is one or two cells) from past the engine's own works (`_skip0`, `own_works_skip`: a tower engine and a
  fort gun shoot over their own parapet) to the landing point, against the top of each standing work (`_arc_meets`:
  wall body and walk `wall_h` + the parapet, a tower `wall_h` + 4 m, a shut gate `wall_h` + 1 m, over the cell's own
  ground; a stair flight half the walk, its middle; rubble, an open or a broken gate let it through; houses, rocks and
  the ground do not stop a stone, as before), and backs the first hit to the face by half metres.
- *The strike.* `_art_strike` (called by `_art_fire`, `_art_fire_gate` and `_art_fire_at` for every engine stone when
  `ARC_STRIKE_ON` and the map has works): the aim is untouched (the player or the AI may still aim at men behind a wall;
  the scatter as before); if the scattered flight meets a work, the slot's landing point becomes the strike, its flight
  shortened in proportion (at least 3 ticks), and `pr_wh` (per slot, the strike's height above the ground + 1) marks it.
  On landing (`_land_stone`) a struck stone does to the work what a stone landing on it does (`GATE_STONE` x the
  ammunition's `t_k_obj`, a bursting shell's blast added), through `_works_strike`: a shut gate's cell its gate
  (`g_hp`, `_break_gate`), a wall or walk cell its stretch (`_destr_hit`: hit points, `_breach`), a tower's cell the
  stretch the tower joins (towers stand, siege_and_towns.md: the nearest standing stretch within `STRIKE_TOWER_R` 16 m
  takes the blow); the defenders' own stones do their works no harm (as `_destr_hit`). Nobody behind it is touched (no
  plough); if it struck within `STRIKE_TOP` 2 m of the work's top, the men standing on works within its direct hit
  (`m_blast`, at least `STONE_R_INF`) round the spot are struck as men where a stone lands (`_strike_men`: the same
  damage and knock-down; the engine and men on the ground are not). A bursting shell bursts at the face (`_land_blast`
  as before). Suppression (`_supp_art`) still counts the crash near the men it was aimed at.
- *Flat balls* keep their trace (it was right); where `_land_bolt`'s trace stops at a shut gate or a tower,
  `_works_strike` now does the gate or the tower's stretch the same `GATE_BOLT` x `t_k_obj` x `m_obj` it did to a
  stretch (a culverin's ball into a shut gate: 360 of its 2,700 hit points).
- *The aim* (docs/AI.md 73): the artillery target scans (`BattleAI`'s battery scan; `_art_think`'s fire at will, any
  side's) score a target whose stone the arc cannot reach (`art_arc_strike`: from the battery's first engine at the
  target's near face, as `_art_fire` aims) at `ART_ARC_PCT` % (knob 373: Easy 100, Average and Skilled 10): the AI
  prefers what it can hit; Easy keeps shooting at the men and hits the wall. An attack order still shoots (and batters
  the wall). The siege AI's batter targets (`_art_fire_wall`, `_art_fire_gate`, the batter order's point) are
  unchanged; their stones meet the aimed stretch or gate first and do the same damage (a stone aimed at a stretch's walk
  may now strike its outer parapet: the same stretch).
- *The preview* (`overlay._draw_wall_strike`): a stone battery's attack line whose arc meets a work draws to the strike
  (a red burst there, faint beyond) and says "THE SHOT WILL STRIKE THE WALL".
- *State.* `pr_wh` (hashed from the first strike, `strk_used`, so battles where no stone strikes a work hash as before;
  reset at landing; in snapshots as every script variable); the view's impact ring gains `fx_k` / `fx_r` / `fx_h`
  (view only, art_pipeline.md "The stone rolls and breaks (as built, 2026-11-06)"). Stats `stat_strikes`,
  `stat_strike_dmg`. `ARC_STRIKE_ON` (static, 1) is the probes' before / after switch.

**Measured** (a scratch probe, session scratchpad `proj/strike_probe.gd`: a Rome town (level 1, flat) at walls 1 / 2 / 3
and a West walls-1 palisade, a stone battery (18 men, three engines) at 80 / 120 / 160 m out from 60 spearmen whose
middle stands 4 m inside the wall's inner face (their front rank about 1 m from it), an attack order for 90 s, no AI,
the towers' engines holding; 4 seeds, 72 stones a row; "inside" = stones that came down inside the walls; wall hp all
the stones did to the works; a stretch breaches at 1,200 / 2,000 / 3,000 hp, after which the rubble lets the rest
through):

| case | m | before: inside / wall hp / men lost | after: inside / strikes / wall hp / men lost |
|---|---|---|---|
| Rome walls 1 | 80 | 63 / 2,520 / 79 | 49 / 17 / 5,760 / 54 |
| | 120 | 57 / 4,320 / 59 | 46 / 11 / 5,760 / 53 |
| | 160 | 48 / 5,400 / 52 | 42 / 10 / 5,760 / 47 |
| Rome walls 2 | 80 | 62 / 2,880 / 76 | 36 / 28 / 8,640 / 50 |
| | 120 | 53 / 5,040 / 67 | 37 / 22 / 8,640 / 42 |
| | 160 | 47 / 5,760 / 52 | 32 / 22 / 8,640 / 31 |
| Rome walls 3 | 80 | 66 / 1,440 / 82 | 30 / 36 / 12,960 / 40 |
| | 120 | 50 / 6,840 / 56 | 23 / 35 / 12,960 / 28 |
| | 160 | 52 / 5,400 / 47 | 26 / 35 / 12,960 / 19 |
| West palisade | 80 | 64 / 1,080 / 74 | 47 / 25 / 8,280 / 48 |
| | 120 | 55 / 3,240 / 49 | 41 / 28 / 8,640 / 32 |
| | 160 | 46 / 4,320 / 40 | 35 / 18 / 9,360 / 29 |

Behind a tower (`--tower=1`: the men 20 m in from a tower's middle, the battery out along the stretch's normal): walls 2
at 80 m men lost 74 -> 62 (18 strikes), walls 3 88 -> 41 (31). A culverin (three guns) at the same men fires nothing,
before and after: no line at body height over the wall (the flat rule, unchanged). Aimed at 60 archers on the walk
(`proj/strike_probe_walk.gd`, before on a clean HEAD copy): stones strike 2-16 of 72 (scattered short into the outer
face), walk men lost within noise (walls 2 at 120 m 171 -> 175 of 240); a culverin's balls identical to HEAD (29 shots,
the same wall hp and losses: they strike the parapet only where they did). The custom_battle_test set pieces
(`_check_strike`, Rome seed 303, 700 ticks): a battery 120 m out at men 14 m inside a walls-2 tower: 13 stones, 7 struck
the tower, its stretch lost 1,080 hp, 2 men lost (with `ARC_STRIKE_ON` 0: none struck, 11 lost); from 160 m at men 30 m
inside the palisade: 13 stones, none struck, 11 lost; a ball put in flight at men behind the shut gate: the gate 2,700 ->
2,340 hp, nobody behind hit.

**Balance** (`tools/balance`, 8 seeds, HEAD 7dc9d5dd4b -> cfab5167b4): `rome_walls` attacker wins walls 1 / 2 / 3 75 / 50 /
42 -> 75 / 46 / 42 (overall 56 -> 54, within 8 points; cells beyond their interval zeugitana w3 -38 and massalia w1 -38;
mean wall damage a battle 3,867 -> 3,844, wall shots 10.4 -> 8.4, defenders killed 534 -> 529, attackers 524 -> 509): the
attackers' artillery kills fewer behind the wall, its damage now goes into the works instead. `west_walls` was still
running at hand-off (71 of 96 jobs; its before is the fort tuning worktree's HEAD run of the same code hash).
Knob (`proj/scan_probe.gd`, a battery on fire at will, 60 men at the wall and 30 men 35 m further in): Easy fires at
the 60 and strikes the wall (walls 2 at 80 m 24 strikes, 53 lost of the 60, 0 of the 30); Average turns to the 30 at
walls 2 and 3 (0 strikes, 40 lost) and at the palisade splits; at Rome walls 1 the scan judges the near face reachable
and keeps the 60 (as Easy).

**Tests.** custom_battle_test `_check_strike` (above; the repeat identical); battle_screen_test `_roll_cases` (the
view); determinism_test's `over_walls` (a stone battery outside walls 2 at a unit in the plaza: its stones still land
inside) and the rest as listed in STATUS.

**Known.** The arc is the views' parabola, one for every engine stone (a mortar lobs no higher than a stone thrower);
a tower's blow goes into the neighbouring stretch (towers have no hit points); the rampart and stakes of the field works
are not in the obstacle grid and stop nothing (as before); houses do not stop a lobbed stone (it lands on the roof as
before); a stone aimed at a point is decided at launch, so a gate opened while it flies still stops it; flat balls are
still traced at landing (a scattered ball that strikes before its landing point is drawn flying on to it).

### Buildings block a flat shot (as built, 2026-11-06)

Why (the owner, a beauty pass on the battlefield): "I want to start to look at buildings being in the way when rounds
are fired from a distance, and that units have to get around the building for line of sight before firing at an
enemy." And: "We can use some Company of Heroes examples for line of fire and cover on the battlefield. I want it to
be that type of experience if possible."

**What was there (the diagnosis, tests/lof_probe.gd).** A flat shot was already blocked by a house, wall, tower or
shut gate at three levels: the unit's choice (`lof_units` in fire at will and the attack order), each man's shot
(`_shot_ok` -> `lof_block`, which reads `_obs_top`) and the ball reaching a man (`_flat_block`). So a musket line on
fire at will never shot through a house and took another target with a line (the LOF_MEN cover men kept). Four gaps:
(1) a ball scattered past a corner whose line crossed a house flew on through it and landed beyond when no man stood
near its landing point (53 of 82 balls drawn across the house at 40 m in the probe's town case, 120 s); (2) an attack order
on a target with no line closed along the street path toward the target (contact if need be, `HIDDEN_CLOSE_ON`) until
some line opened, and on a field map with house blocks (`city_on` 0: tests only) walked straight into the house and
stood there; (3) bows and slings lobbed over houses at their full range; (4) the AI's musket lines (`_mis_close`) took
the nearest enemy in sight whatever stood between, and focus fire checked the line only on hilly maps (`ter_on`).

**The rule.**
- *Flat shots stop at the obstacle* (`_fire`, `lof_works_block`): a flat soldier's ball (`m_arc` 0, `m_kind` 0:
  muskets, arquebuses, pistols, crossbows, javelins) whose straight line from the man to its scattered landing point
  meets a house, wall, tower or shut gate (sampled every 2 m, the obstacle grid's cell; back to its face by half
  metres) ends its flight at the face (`stat_flat_cut`); not from or at a held building or a wall's walk (the
  garrison's and the battlements' rules as before). Engines and guns (`m_kind` 1, the field guns and the ships'
  batteries) were already stopped there by `_land_bolt`'s trace.
- *Walking round for a line* (the attack order's closing move): a flat-weapon unit with an attack order whose
  target it sees but has no line of fire to, the first thing in the way being a house, wall, tower or shut gate
  (`lof_works_block` from its middle), goes to its *fire spot* (`fire_spot`): rings `LOF_SPOT_STEP` 4 m apart round
  its anchor out to `LOF_WALK` 40 m, on each ring the target's bearing first and then either side alternately, the
  first open spot (its ground) within 85 % of `range_vs` (where the closing move stops) from whose middle (half its
  depth back) and `LOF_SPOT_SIDE` 3 m either side the line to the target is clear. The path planner takes it there
  (the gate rule's `held` goal), it faces the target and stands. The spot is kept (`u_fsx`, `u_fsy`, `u_fst` target +
  1; hashed with the map arrays, in snapshots) and searched again when the target changes or, once a second, when it
  no longer serves; there with its men up and still no line, the next ring round. None within 40 m: the closing
  move as before (by the streets toward the target). Fire at will does not walk: it shoots what it has a line to.
- *Arcing weapons lob over a house* (`lob_over_wall`, `house_close_at`): an arcing soldier weapon from the ground
  whose line between the middles crosses a building within `HOUSE_LOB_NEAR` 12 m of the target's middle reaches
  `ARC_OVER_WALL_PCT` (60) % of its range, as over a wall (not from or at a held building). The range ring is not
  cut for houses (only for walls, as before); the attack order's out-of-reach label says "TOO FAR TO LOB OVER THE
  HOUSES: MOVING CLOSER".
- *The preview* (`game/overlay.gd` `_draw_blocked`): a flat unit's attack order with no line draws the red cross and
  "NO LINE OF FIRE" at the obstacle as before; with a fire spot, "NO LINE OF FIRE: MOVING AROUND", its way to the
  spot (a dashed amber line and a ring) and the line on to the target.
- *The AI* (docs/AI.md 65): `LOF_PICK` (350): a musket line's target (`_mis_close`) is the nearest enemy it has a
  line of fire to; one behind a house only when it has none (then the attack order walks round); focus fire checks
  the line on maps with houses too. Easy 0 (the nearest, as before).

**Cover like Company of Heroes (what exists, what was added).** Cover was already directional for everything that
stands up: `_cover_from` reads the 2 m cell 2 and 4 m from the man *toward the shooter* (a house, a wall in the field,
a rock or cliff), so a man behind a house corner is covered against fire from beyond it and not from the open side;
flat shots are traced and stopped by the obstacle itself (real cover, phase C0). Woods cover a man standing in them
from every side (correct: he is inside), and a field's hedges (`COV_FIELD`, an area of the veg grid with no hedge
lines) count whichever way the shot comes: the one non-directional kind (no hedge geometry to read; left as is). The
values are unchanged (`COVER_STOP`: woods 45, rock 60, house 50, wall 50, field 25, rubble 60 %). Tiers, as the
player reads them: heavy (a house, a wall, a rock or cliff 2 m tall or more between him and the way he faces: stops a
flat shot outright, `CS_H_LINE`) and light (woods, a lower rock, rubble, a field's hedges). The low wall exists: a West
town's yard walls are 1.3 m rock cells (`_w_lowwall`), light cover, directional like a rock; no new kind was added.
Added:
- `cover_rating(x, y, face)` (2 heavy, 1 light, 0 open; directional, `_cover_from`'s kinds) and
  `cover_rating_front` (five men along a front: heavy when half have heavy cover, light when half have some).
- *The order preview's cover mark* (`_draw_dest_cover`): dragging a move order, a small shield (the stance icon) by
  the right end of each unit's destination front, green for heavy cover, yellow for light, none in the open.
- *Cover spots at the order's destination*: a unit in Take cover with no enemy in sight now lays out its cover spots
  against the way it was ordered to face (`_cs_threat`: before, none until an enemy was seen), so its men settle on
  the covered side of the house or wall it was sent to.
- *The AI's cover spots* (`COVER_DIR` 351): cover troops' spots (`_cover_spot`) take the best `cover_rating` against
  their front (heavy first) instead of any cover round the man. Easy 0.

**Measured.** Probe (tests/lof_probe.gd, the town case, 120 s, HEAD -> after): a musket line
40 m off pikes behind a house, attack order: shots 82 -> 313, pikes lost 16 -> 29, balls drawn across the house 53 ->
4, first shot at 27 s both (it walks 34 m round); at 120 m: 117 -> 69 shots, 17 -> 5 lost, first shot 80 -> 87 s (it
fires from a spot 48 m off past the corner, many balls cut at the corner, where HEAD walked on by the streets); fire
at will with no line: no shot and no move both; the field block's half-hidden case 40 -> 80 shots, 9 -> 18 lost; a
bow line at 120 m: 964 -> 814 shots (the house lob's reach), at 40 m unchanged. Balance (tools/balance, 8 seeds,
before a clean copy of HEAD 1ec92d9e00, after ba60e5fba9): `west_walls` 38 -> 41 % (walls 0 / 1 / 2: 52 / 34 / 27
-> 58 / 35 / 29), no pooled cell beyond its interval; cells beyond: havana w1 50 -> 12, port_royal w2 12 -> 50,
veracruz w0 50 -> 100, santo_domingo w2 50 -> 88, merida w1 38 -> 88; `west_named` 35 -> 39 % (57 / 38 / 9 -> 59 / 36
/ 23, walls 2 pooled +14 beyond its interval; the same cells and tayasal w0 38 -> 0); `rome_walls` 56 -> 61 % (75 /
52 / 42 -> 79 / 56 / 48), no cell beyond; `open_town` attackers 79 -> 75 % (havana 38 -> 25), defenders' L3 133 ->
157. Ablation (port_royal, santo_domingo, veracruz walls 2, 24 battles; 21 % before, 54 % after): the fire spot off
29 %, the defenders' walk off 54 %, the attackers' walk off 29 %, the walk for houses only (not walls) 54 %, the AI
knobs off 54 %, the Take cover fallback off 54 %: the shift is the attackers' shooters walking round houses inside
the town for a line. Street cover (determinism `--only=street`): 23 lost at the mouth vs 58 in the open both, killed
86 -> 93. Cost: bench_2000 3.43 / 3.18 -> 3.31 / 2.22 ms a tick, bench_4000_city 4.92 / 4.79 -> 4.75 / 4.84 (two
paired runs; noise). Pins: campaign pins MATCH (Rome and West, 6 seeds); no flat golden moved (the rule needs a map
with obstacles).

**Tests.** custom_battle_test `_check_lof` (the probe's town case: the musket line has no line at the start, takes no
shot without one, walks round for one on an attack order and fires, under a tenth of its balls drawn across a house;
on fire at will it neither shoots nor moves; the bow line lobs over the house from where it stands).
tests/lof_probe.gd (the table), tests/lof_shot.gd (the shots, both views).

**Known.** The fire spot is the nearest by the target's bearing first, so the line often walks up close to
the target's side of the house (10-15 m in the shots), and from a corner many of its balls are cut by the corner (a
line of 20 files is wider than the view past a house); at 120 m in the probe it shot fewer and killed fewer than
HEAD's walk by the streets. West sieges at walls 2 favour the attacker more (west_named +14 points pooled, beyond its
interval: the attackers' shooters get lines in the streets). Field-map house blocks (tests only) hide a target behind
them, so flat fire holds and the AI does not engage there. The range ring is not cut for houses. The AI's arcing
units are unchanged (fire at will); only musket lines (`_mis_close`) and focus fire use `LOF_PICK`. No device check.

### Cover like Company of Heroes (plan, 2026-11-06)

What the owner's model has that this build does not, each with its cost (agent-days) and what it needs from the sim:
- *Suppression* (2-3 days): a unit under heavy fire pins (fires slower, moves at a crawl, cannot charge) and recovers
  when the fire stops. Needs a hashed per-unit suppression meter fed by near misses and hits in `_land` (shots landing
  within a few metres of its men, the cover kind lowering the gain), decayed per tick; read by `_gun_unit` / the
  reload, the anchor's speed and the charge; the AI's attack choices (do not send pinned units) and a HUD state chip.
  Balance: the gun lines' duels and the sieges must be re-measured (it is a new damage channel).
- *Negative cover* (1 day): open ground worse than open (a road, a bridge, a ford, shallow water: men there take
  more), a third tier the preview shows red. Needs a `COV_EXPOSED` kind with a negative stop (an extra hit chance in
  `_land`'s hit roll), read from the road / river grids; the preview's mark gets a red crossed shield.
- *Cover icons for every object under the cursor* (1-2 days, view only): hovering any ground shows the cover a man
  there would have against the nearest enemy (or the selected unit's facing), per object (the house's sides, a wall,
  a rock). Needs nothing new in the sim (`cover_rating` answers it); the overlay needs a hover path on phones (a
  long press) and a cache per 2 m cell.
- *Garrison windows with sight arcs* (3-4 days): a held building's men fire only from windows on the sides facing the
  enemy, each window an arc, and the preview draws the arcs. Needs window positions per building (MapGen's house
  plans), per-window firing slots for `_occ_aim` / `_fire`, the arcs checked in `_pm_cand`; the siege fits and the
  town fights re-measured.
- *The AI's flanking of cover* (2-3 days): an AI attacker facing a unit in heavy cover sends a unit round to fire at
  it from its open side (`cover_rating` from the flank) instead of trading volleys at the front. Needs a flank spot
  search (fire_spot's rings with a cover test from the spot), a knob, and the open-town and siege measures.

### Cover and line of fire, second pass (as built, 2026-11-06)

Why: the evaluation of the first pass (session scratchpad `eval/eval.md`) graded light cover *broken* for line troops
and the fire spot, the AI in towns and the preview *weak*; the main session chose its gaps 1-3, 5 and the cheap parts
of 4 and 7, plus the older straggler bug (its gap 9).

**1. Light cover is real for line troops** (`_flat_block`, `_line_cover_stops`, `_line_man`). A man of the line (foot
without the cover trait, on the ground: not on a wall's walk, not at a held building's windows, not a ship's hull) is
still traced to his head (`LOF_HEAD`) for the ball's flight; when that line is clear, the same line to his chest
(`LOF_CHEST` 1.2 m, straight from the muzzle) is traced, and a low wall, rock or hedge it meets shelters him:
`LINE_LOW_STOP` 60 % of those balls stop there (the cover trait's rock value; the dust at that point as any stopped
ball). Directional by the trace itself: only from beyond the obstacle. Not within `EXPOSE_T` of his own shot (he is up
over it, as cover men). Woods: a man of the line in dense woods with woods 2 m toward the shooter (not at the wood's
edge facing out: the directional rule where the wood has an edge, all-round inside it) stops `LINE_WOODS_STOP` 25 % of
flat balls on top of the trees' `VEG_STOP_JAV`; a field's hedges (field maps) `LINE_FIELD_STOP` 15 %, from every side
as `COV_FIELD`. Arrows and stones: unchanged. Cover men keep their better numbers (traced to the body, `COVER_STOP`).
On wherever the map has the obstacle or the wood (not only with cover troops present, `cov_on`).
- *The shield and the chips know the troop type* (`cover_rating(x, y, face, who)`, `cover_who`): `COVW_COVER` as
  before; `COVW_LINE` light only from what the rules above give (woods with woods toward the bearing, a rock chest high
  `CS_H` toward it, rubble, hedges); `COVW_RIDER` heavy only. No yellow where the unit gets nothing.
- *Take cover reaches farther and uses the yard walls*: standing with no order a Take cover unit's men take spots
  within `CS_R_TAKE` 13 m of their places (was `CS_R` 10 m), the check for obstacles near reaching as far
  (`_obs_within`), and line troops in cover take chest-high cover (`CS_H`, was 2 m only).
- *The unit-level line of fire* (`lof_units`) samples every `LOF_STEP` (4 m, as each man's shot does) on maps with
  obstacles (was 8 m: a yard wall or a thin house slipped between the samples and the unit "had a line" none of its
  men had, stood and fired nothing).

**2. The fire spot is scored** (`fire_spot`, `_spot_lit`, `_fire_spot_kept`, `_fire_spot_on`). Candidates: the
anchor itself, then rings `LOF_SPOT_STEP` 4 m apart to `LOF_WALK` 40 m (the target's bearing first, then either side).
A spot serves when the unit's middle (half its depth back: where `lof_units` looks from) has a line of fire, and is
counted by `LOF_FRONT_N` 5 points (the middle and 1 m behind the front at half and the whole half-width either side,
each on open ground: a yard wall is walked round, not stood in); `LOF_SPOT_MIN` 2 of them. Score (lower is better):
the walk (straight; the path planner in this tree has no enemy term: the concurrent movement pass adds one) +
`LOF_SPOT_MISS` 10 m per point without a line - `LOF_SPOT_HEAVY` 10 m for heavy cover along the front facing the target
(light half; `cover_rating_front` for its troop type) + `LOF_SPOT_CLOSE_PCT` 50 % of the ground given toward the target
+ each metre nearer the target than `LOF_SPOT_NEAR` 30 m. Spots that cannot beat the best so far are not traced (a
ring is cut once its radius less the cover bonus is past the best), at most `LOF_SPOT_BUDGET` 600 traces a search
(the first pass's worst case was 570). The search is triggered by a house, wall, tower, shut gate *or a rock or yard
wall* in the way (`lof_works_block(..., rocks)`).
- *Stable:* the kept spot is checked once a second and kept while `LOF_SPOT_KEEP` 1 point still has a line (a new
  search only when it no longer serves; it never drops to "none" while the spot holds). There with its men up and still
  no line from its middle: the next rings round (from 8 m). None found: searched again after a second, then every
  `LOF_SPOT_RETRY` 3 s (was every second).
- *On to the spot:* a unit whose middle gets a line on its way goes on to the spot unless, checked once a second,
  `LOF_SPOT_GOOD` 4 of the 5 points have a line where it stands with cover as good as the spot's (then it stops there).
  A wide line with no full line anywhere within 40 m stops at the best partial; it does not narrow (not built).

**3. The siege AI reads lines and cover** (docs/AI.md 66; every town battle runs `SiegeAI`, so `LOF_PICK` and
`COVER_DIR` of note 65 were dead there): `S_LOF_PICK` (a storming flat-weapon shooter counts a defender it has no line to
`S_LOF_PUSH` 40 m farther), `S_COVER_DIR` (a West skirmisher's strongpoint scores the cover facing the street mouth),
`S_LOF_STEP` 12 m (a defending musket line at its post with attackers in its reach and a line at none of them steps to
the best fire spot within 12 m of the post, and back once they are gone).

**4. The view** (docs/design/ui.md "Cover chips and hittable marks (as built, 2026-11-06)"): a cover chip on every
marker, hittable / blocked marks on the enemies in reach of the selected missile unit, the range ring cut at houses,
the preview's text on a plate at 12 CSS px, the preview reading the sim's kept spot.

**5. The straggler** (`_free_mem`, the slide memory `s_wf`): when a slide's hold ran out, the memory kept its
direction, so a man's next step back toward his place read as "the 2-cycle a corner makes" and started a new hold
away from it, without end while the cell that way was open: after a unit halted, one or two men walked off at about
3.8 m/s to the map's edge (the evaluation's 8 of 497 far men over 20 seeds; seed 7 two men 165 m off). The renewed
hold is now tagged (bit 128) and clears the memory when it runs out: once per slide. The town cover check's tolerance
for line men off their places is back to a twentieth.

**Measured** (the evaluation's probes re-run, before = a clean copy of HEAD 2f17d34; tables in the session scratchpad
`cover2/tab/`).
- *Light cover* (`cover_field2`, 40 musketeers 3 m behind a 20 m line of rocks, 60 musketeers at 70 m on fire at will, 3
  seeds; lost in 30 s / per 100 shots): open 51 / 11.1; behind the 1.3 m yard wall from beyond 51 / 11.1 -> 26 / 4.7
  (-49 % in 30 s, -58 % a shot); from the open side 77 / 13.6 both (nothing); behind a 2.5 m wall 1 / 0.8 -> 1 / 0.7;
  in woods (sight off) 47 / 9.8 -> 43 / 7.8; buccaneers unchanged (yard wall 8 -> 9, woods 34 -> 34).
- *Take cover* (`snap`, 40 men ordered short of a 20 m wall, men in cover after 30 s): musketeers 6 m short of the 2.5
  m wall 30 -> 36 heavy, of the yard wall 0 -> 36 light; 11 m short 0 -> 24 (both walls); buccaneers 11 m short 0 -> 14.
- *The walk* (`lof_grid`, 81 attack cases: 3 towns x 40 / 80 / 120 m x 0 / 30 / 60 degrees x 40 / 80 / 120 men, 120
  s): kills 1,046 -> 1,388 (+33 %), shots 21,243 -> 23,563, balls cut at a house face 38.9 -> 36.0 %, drawn across an
  obstacle 7.5 -> 7.3 %, the first shot later: 20 -> 29 s (40 m 7 -> 17, 80 m 11 -> 21, 120 m 43 -> 49: the line walks
  on to a spot with a line across its front and cover instead of firing from the first partial line); spot to target 69
  -> 71 m.
- *The AI standing with no line* (`ai_idle_fair2`, West level-2 town, AI against AI, 4 seeds x 300 s, unit-seconds of
  AI musket units standing with a seen enemy in reach and no line, sampled every 4 m for both trees): walls 0 1,530 ->
  1,781, of which garrisons at windows (the unit-level line from a held building's middle, while its men shoot per
  window) 1,220 -> 1,421, the rest 310 -> 360; walls 2 1,670 -> 1,428. The defenders' step seldom finds a spot within 12
  m in the streets (in the debug run 2 of 38 standing samples had one): the step is built and tested (custom_battle_test)
  but does not move this number.
- *The straggler* (`town_line`, 20 seeds): men more than 3 m off their places 8 / 493 -> 1 / 493 (the one a man still
  walking in, 6 m off).
- *Balance* (tools/balance, 8 seeds unless said; before dd665f87cd, after a42dd92c7e): `open_town` 16 seeds 85 -> 85 %
  (8 seeds 75 -> 88: noise, the second 8 seeds 96 -> 83); `west_named` 39 -> 42 % (walls 0 / 1 / 2: 59 / 36 / 23 -> 57 /
  50 / 20; the first pass's walls-2 shift, 9 -> 23, comes back a little, to 20); `west_walls` 41 -> 43 % (58 / 35 / 29
  -> 60 / 41 / 28); `rome_walls` 61 -> 55 % (79 / 56 / 48 -> 79 / 48 / 38); all within the 8-point gate. Cells beyond
  their interval: west havana w1 +50, cartagena w0 -50 / w1 +38, port_royal w0 +62 / w1 -38 / w2 -38, veracruz w0 -62,
  st_augustine w0 +38, san_juan w2 +50; rome zeugitana w3 -50, attica w1 -38, sicilia_or w2 -38. Ablations: the 4 m
  unit-level stride at wall walks took Rome walls 2-3 to 38 / 23 (56 / 48 before), so wall fights keep the 8 m line;
  light cover off and `S_LOF_PICK` off change nothing at Rome walls 2-3 (+0 / +4 points); in `open_town` (8 seeds,
  88 % with all) light cover off 75 %, the step off 88 %.
- *Cost* (tests/benchmark.gd, paired runs, mean ms a tick, before -> after): bench_2000 2.16 -> 2.13, bench_4000_city
  5.33 -> 5.03, and the new **bench_west_muskets** (a West open town, 8 musket lines of 60 a side, both AI, 1,500
  ticks: `-- --scen=bench_west_muskets --max-ticks=1500`) 1.90 -> 2.19, **+15 %, over the +10 % budget**. Instrumented,
  `lof_units` and `fire_spot` together cost about 0.11 ms a tick there (44 searches, 1,447 traces in 1,500 ticks); the
  straggler fix alone accounts for about half of the rise (reverted in a copy: 2.04: men keep retrying their places
  instead of walking off), the rest is spread (each rule off alone stays within 2.1-2.3: the battle itself changes); the
  path searches double (998 -> 2,048: lines walking to spots). Left for the main session's call.
- *Pins:* campaign pins MATCH (Rome and West, 6 seeds); no flat golden moved (the rules need a map with obstacles); the
  rules hash moves.

**Tests.** custom_battle_test `_check_lof` and `_check_cover2` (the light cover stop from beyond and none from the open
side, the scored spot taking the covered way round and the line firing from it, the siege AI's step for a line);
battle_screen_test `_cover_cases`; determinism_test's town cover check back to a twentieth.

**Gaps of the evaluation closed and open.** Closed: 1 (light cover for line troops, the shield by troop type); 2
(scored, stable spots, yard walls, the budget and the retry); 3 (the siege AI's line pick, cover direction and the
defenders' step); 5 (the cover chip on every marker) and of 4 the readable preview, the hittable marks and the ring cut
at houses; 7 (the search budget, the West musket benchmark); 9 (the straggler). Open: fire at will does not prefer an
uncovered target (gap 6); lines never fire on the move and the walk ignores exposure beyond the closing penalty (gap
8: the movement pass's enemy term); a wide line does not narrow at a corner; the per-enemy marks and the chip are not
on the unit card; suppression, negative cover, cursor-hover cover icons, garrison window arcs and the AI's flanking of
cover (the plan above); no device check.

### Cover and line of fire, third pass (as built, 2026-11-06)

Why: the second evaluation (session scratchpad `eval2/eval2.md`, its probes in `eval2/probes/`) found the walk to the
fire spot losing more than it bought against shooters (own losses before the first shot 18 -> 230 in its 81 cases
against a musket company, the kill exchange 1.31 -> 1.00), lines that partly see not shooting (street defenders with
men who had a line shot in 4 % of their seconds), the cover chip misleading in towns, the defenders' step held to 12 m
and the West musket town benchmark +30 %. The main session chose its gaps 1-7; suppression is next.

**1. The walk under fire** (`fire_spot`, `_fs_expose`, `_fire_spot_on`, `_lof_under_fire`).
- *Exposure in the score:* each candidate spot pays for the enemy's fronts it sees (the path planner's zones of
  "Paths clear of the enemy", `_rt_zones`: a shooter's front +-45 degrees within its range +300 % a metre, a melee
  front 15 m deep +100 %, boxes shut; none held back for a goal): `LOF_SPOT_EXP_PCT` 50 % of the extra cost of each
  metre of the straight walk (sampled every `LOF_SPOT_EXP_STEP` 4 m) plus `LOF_SPOT_EXP_AT` 3 m for each 100 % of
  fronts over the spot; a walk or spot in an enemy's box is no candidate. The zones are found and narrowed to the
  searched ground once a search. Not by routing the walk through the planner (the evaluation's move orders to the same
  spots lost 183 men against 97).
- *Stop sooner under fire:* a unit is under fire when a missile wounded it within `LOF_FIRE_T` 3 s or its target (a
  missile unit with shot left) has it in reach. On its way with a line it stops where it stands at
  `LOF_SPOT_FIRE_GOOD` 2 of the 5 front points with a line (4 otherwise, `LOF_SPOT_GOOD`); the brief's 3 measured
  worse (exchange 1.07, 75 lost before the first shot; 2: 1.24-1.29, 57-62); the reach for that check and the
  closing move under fire is `LOF_FIRE_STAND_PCT` 90 % of its range (85 % otherwise: closing from its target's reach
  to 85 % of its own cost the line 18 s and 23 m under fire in 18 of the 81 cases).
- *Stable on arrival:* the middle of the line is now one of the five points (no longer required: `_spot_lit` under
  `LOF_MEN_ALL`), so a line that arrives with its front men seeing fires; with none of its sampled men seeing it searches
  the next rings as before.

**2. Lines that partly see shoot** (`lof_units`, `LOF_MEN_ALL`). When its middle has no line, every unit now tries
`LOF_MEN` 4 of its men (before: only units at cover spots): a formed unit's front rank (files 0, a third, two thirds,
the last), a garrison's men at its windows (past the door's `OCC_DOOR_N`), cover spots as before; a unit with any of
them seeing takes the target, and each man's shot still needs his own line (so only those who see fire). The answer is
cached per unit pair between soldier moves (`_lofc`, an epoch bumped at each step's start, after the soldiers move,
after the cover and characters' passes and on restore; derived, not in snapshots).

**3. The cover chip tells the truth** (docs/design/ui.md "Cover chips and hittable marks", third pass): the sim notes
each unit's two latest shooters (`_shot_note` at every missile launched at a unit; `u_sbu0` / `u_sbt0` / `u_sbu1` /
`u_sbt1`, hashed with the map arrays, read by no rule) and answers `cover_shooters(u, within)`; `cover_rating` /
`cover_rating_front` take `skip_b`, a building whose cells do not count (the house a garrison holds: `held_building`).
The view rates against those shooters (3 s), the worst of them, else the nearest enemy; shows nothing for open ground;
the cut range ring loses its spikes.

**4. The defenders' step** (docs/AI.md 67): `S_LOF_LEASH` 20 m (the search round where it stands, and the farthest
from its post) and `S_LOF_HOME` (back to the post once it has no line there and no spot within the leash, or no
attacker in its reach), Easy 0.

**5. Cost** (`tests/benchmark.gd`'s bench_west_muskets built by hand, 1,500 ticks, seed 42; profiled with timers
wrapped round ~40 functions in a scratch copy). The biggest costs on HEAD were the stragglers' `_near_nodes` (a scan
of every street-graph node, 0.25 ms a tick: now 16 m buckets searched ring by ring, the same six nodes), the
separation's `_sep_push` (0.16 ms) and the slides (`_slide`, 0.19 ms); of this pass's own work, `lof_block` (per call
about 20 us) and the step's searches. Built: `_near_nodes` bucketed; `lof_block` reads the obstacle and wood cells
inline (an open cell skips `_obs_top`, flat ground skips `height_at`); `_sep_push` and the slide's trail loop keep
their arrays in locals; `lof_units` cached as above; the exposure's zones selected once a search. All but the cache
and the exposure are the same answers (the benchmark's state hashes equal every 300 ticks before and after them).
Measured (3 rounds each, the same machine, back to back): 2f17d34 (before the first pass) 1.91 ms a tick, HEAD 2.51
(+31 %), this pass 2.30 (+20 %): still over the brief's +15 % (2.20). The exact savings take HEAD's own battle from 2.51
to about 2.29; this pass's behaviour costs some of it back (a different battle: lines that partly see fire, more
units on the move, 888 men alive at 1,500 ticks against 811; the step's 20 m searches and the men's line traces,
`lof_units` about 4 traces an answer it cannot take from the cache). Profile (timers, a loaded machine, ms a tick HEAD
-> this pass): `_near_nodes` 0.42 -> 0.05, `_via_goal` 0.45 -> 0.08, `_slide` 0.31 -> 0.24, `_sep_push` 0.26 -> 0.25,
`lof_block` 0.17 -> 0.14 (7.0 calls a tick against 5.3), `fire_spot` with its exposure 0.02 -> 0.08 (the step's
searches), `_lof_step` 0.04 -> 0.11, the soldiers of units on the move 1.27 -> 1.52 (9.8 such units a tick against 8.8).

**6. Rubble has some height** (the owner, added to the pass: "Rubble should have some height to hide behind").
Rubble cells (a breached wall's, a fallen house's; a broken gate leaves no rubble cells, its opening stays open) now
stand `RUBBLE_H` 1.3 m (a yard wall's height; static var, 0 = flat as before) for the lines of fire (`_obs_top`,
`_cell_top`): a ball traced to a man of the line's head (1.74 m) passes over; the chest line (1.2 m) meets the heap and
`LINE_LOW_STOP` 60 % of those balls stop; a cover man's body line (1.0 m) is stopped as by a low rock; arcing weapons as
before (their apex clears it; `COV_RUBLINE`'s `COVER_STOP` is 0, so no extra roll). Directional: rubble within
`RUBBLE_SKIP` 1.5 m of either end of a trace is the man's footing, not his cover, and within `LAND_NEAR` 5 m of either
man it never blocks the unit-level line (as rocks: cover, not a wall between). A man standing in rubble keeps the old
all-round roll (`RUBBLE_COVER_PCT`). `cover_rating` counts a heap toward the threat as light for line and cover troops
(`COV_RUBLINE`, chest high), so the chip and the destination shield know it. View: in the oblique view the rubble is
drawn heaped to that height (the kit's High pass lifts each stone, `draw_rubble(..., up)`; the Low pass, which drew
no rubble in the oblique view at all, draws it straight on the board, `draw_rubble_ob`); the top view unchanged.
Measured (custom_battle_test `_check_cover3` (4): 40 musketeers 3 m behind a 20 m heap, 60 at 70 m on fire at will,
2 seeds, lost in 30 s): flat rubble 37, the heap 21 (-43 %; the yard wall in the same set piece 51 -> 26); the rating
light from beyond, none from the open side. Breach fights (this pass with rubble against items 1-5 alone, same seeds): rome_walls 57 -> 59 % (walls 2 48 -> 52, 3 40 ->
42: a small lean to the attackers, who crouch in the breach's rubble on its inside), west_walls 47 -> 46 % (walls 2
31 -> 29: the defenders), open_town 85 -> 87 (16 seeds), west_named 35 -> 37; no cell beyond its interval from rubble
alone.

**Measured** (the evaluation's probes re-run on this tree; before = HEAD 22496cc, its numbers equal to the evaluation's
"after"; tables and shots in the session scratchpad `cover3/`).
- *The walk* (`spot_eval2` + `lof_grid`, 81 cases, 120 s; against 40 musketeers that shoot back): own losses before
  the first shot 230 -> 62 (the first pass 18), all own losses 1,052 -> 775 (602), kills 1,051 -> 959 (789), the exchange
  1.00 -> 1.24 (1.31), the first line 19.9 -> 15.3 s and the first shot 28.8 -> 21.3 s (18.6), the walk 45 -> 27 m (25),
  spot changes 1.20 -> 0.65 a case (cases with 2 or more 23 -> 13), balls cut at a face 45.7 -> 46.8 %. Against pikes
  (no fire back: four points as before): kills 1,388 -> 1,269 (the first pass 1,046), first shot 29.0 -> 27.1 s, walk 48
  -> 38 m, spot changes 1.54 -> 0.57 (29 -> 12 cases). The end spot in cover facing the target: 0 of 81 still.
- *The walk past a musket line on the side* (`walk_exposure85`, 13 cases, an enemy musket line 85 m off the walk):
  own lost 97 -> 112 (12 comparable cases 74 -> 112: two Rome cases stop sooner inside that line's front and lose 21
  and 48; the others 74 -> 43), arrived 4 -> 6.
- *Lines that partly see* (`idle_class`, 8 West town battles, AI against AI, the probe's fixed middle-or-cover-spot
  measure): street defenders standing with no line 268 -> 38 unit-seconds at walls 0, 247 -> 128 at walls 2; garrisons
  read "no line" 1,401 -> 920 (shot within the next second 28 -> 31 %).
- *The chip* (`chip_truth3`, the same battles, line troops, lost per 100 balls aimed at the unit): heavy against its
  shooters 3.4, none against its shooters 13.9, none against a shooting garrison 19.6 (before: heavy against the
  nearest when that was a garrison 26.2, the lie; it is now 11 unit-seconds with no loss).
- *Balance* (tools/balance, 8 seeds unless said; before 8928aae7de = HEAD, after 06075aadbc = this pass with rubble;
  items 1-5 alone 947ed96d64): `open_town` 16 seeds 83 -> 87 % (items 1-5 85); `west_named` 40 -> 37 % (walls 0 / 1 / 2:
  57 / 45 / 20 -> 55 / 38 / 18; items 1-5 35); `west_walls` 39 -> 46 % (58 / 38 / 21 -> 69 / 41 / 29; items 1-5 47, the
  pooled row just beyond its interval: the attackers' musket lines now fire from partial lines and stop sooner under
  fire); `rome_walls` 56 -> 59 % (75 / 52 / 40 -> 83 / 52 / 42; items 1-5 57); all within the 8-point gate, west_walls at
  its edge. Cells beyond their interval: west granada w0 +38, santiago_de_cuba w1 +50; rome sicilia_or w2 -38.
- Tests: custom_battle_test `_check_cover3` (rubble as cover: (4) above; the stop under fire: three of lof_probe's town cases fire sooner and walk
  less than stopping at four; the partly seeing line: lof_probe's half-hidden pikes, middle only no line and no shot,
  front men a line in both cases and shots; `cover_shooters`; a house no cover from its own garrison at 180 of 180
  door steps) and `_check_cover2`'s step check (run with only the middle read; the leash 22 m); battle_screen_test (the
  chip against a shooter, the ring's opening).

**Still open** (for the next evaluation): the exchange against a musket target 1.24 (below the first pass's 1.31: the
target's own front men now see and shoot too); no spot ends in cover facing the target (0 of 81: the cover bonus
still equals one unlit point); balls cut at a face 47 % against muskets (no narrowing at a corner); a line stopping
early inside a second enemy's front loses more (walk_exposure85's two Rome cases); fire at will still takes the
nearest target; no firing on the move; the chip not on the unit card and no legend; garrison arcs, negative cover,
cursor icons, flanking; suppression (next); the West musket benchmark at +20 % (the brief's +15 % not reached: the
next levers are the men's line traces (an answer kept across ticks while nobody moved far) and the separation's
grid); rubble has no heap in the top view and no unit card mention; no device check.

### Cover and line of fire, fourth pass (as built, 2026-11-06)

Why: the third evaluation (session scratchpad `eval3/eval3.md`, its probes in `eval3/probes/`) found lines never
fighting from cover (0 of 81 walks ended in cover; 12 of 2,538 serving spots had any facing the target), a West
breach's heap blinding both sides while its chip said "light", a line standing inside a third enemy's front (two
Rome cases of `walk_exposure85` lost 21 and 48) and the West musket benchmark +23 % over the base. The main session
chose its gaps 1-3 and the two cost levers; suppression is the fifth pass (eval3's one-page design is its brief's
basis); narrowing at corners, garrison arcs, negative cover, cursor icons and the chip on the unit card wait.

**1. Lines fight from cover** (`_line_cover`, `_cs_ok`, `_cs_threat`, `_cover_places`; `LINE_COVER_ON`). A line of
missile foot in the Line stance with shot left, standing (no order, or an attack order with its anchor still: at its
fire spot, or where its walk stopped with a line), shot at or wounded by a missile within `LINE_COVER_IN` 3 s, lays
its men out on the cover spots of Take cover's per-man machinery within `CS_R_TAKE` 13 m: the lee of each 2 m cell
rising 1.2 m (`CS_H`) toward the unit that shot at it last (`u_sbu0`, else its target), at a corner's edge (he leans
out round it to shoot, `_lean`) or in the lee of what he fires over (lower than `CS_H_LINE` 2 m: a yard wall, a
fence, a heap; not a house face's middle, where he could not shoot); no rows behind (`CS_DEEP`), and not on rubble
behind rubble (in the heap it is his footing). The rest keep their places. Its men hold the spots while shot at
within `LINE_COVER_HOLD` 10 s or while the unit that last shot at it still has shot and it in its reach
(`_shoots_at`: men behind a yard wall are soon hidden from far shooters (`_seen`), who then hold their fire; a hold
on the fire alone flapped every 10 s); back to the formation when it moves off, the threat is gone or it fights. A
unit in cover reads its anchor's line first (`lof_units`: where its fire spot was judged). Both sides get it: a
halted line under fire (the AI's street defenders, a player's line on a halt) as much as one at its fire spot.

**2. A breach's heap no longer blinds both sides** (`lof_block`, `RUBBLE_AIM_BLOCK`). A West breach's rubble is the
stretch's whole footprint, 10-13 m deep, beyond `LAND_NEAR` of both lines, and the 1.3 m heap blocked the aim (to the
body, 1.0 m: the unit-level line, each man's shot, the spot search, the AI's lines). Now a rubble cell blocks the aim
only where it would stop a ball at the man's head (the aimed line raised to `LOF_HEAD` at its end); below that the
heap is the ball's (`_flat_block`: the chest line's `LINE_LOW_STOP` 60 %, a cover man's body). A man below a town's
bank (the walled West towns stand about 2 m above the ground outside) with the heap on its edge stays hidden, as his
balls would be stopped too. View: the top view's rubble gets a heap mark (`CityDraw._rubble_heap`): the crest
cells lit, the slope cells (an open side) in shade, big blocks heaped on the crest with hard shadows, the heap's
shadow cast to the south east outside its open sides, a dark edge along every open side and a pale crest along the
north and west ones; the oblique view as the third pass built it (shots `cover4/shots/rubble_top_before.png`,
`rubble_top_after.png`, 844 x 390).

**3. A line inside a third enemy's front** (`_third_fronts`, `_fire_spot_on`, `_stand_move`, `_return_shooter`;
`STAND_CHECK_ON`, `RETURN_FIRE_ON`; maps with houses or landforms, `obs_on`).
- *The stand-here check:* the fronts of the enemy shooters other than the target (`_third_fronts`: within the
  shooter's arc and range and `RT_MARGIN`, with a line of fire there, a garrison all round; `RT_FIRE_PCT` each) where
  a unit on its way would stop (`_fire_spot_on`'s "good here") may not cost more than at its kept spot; a unit
  standing with a line that a non-target shot at within 3 s and that stands in such fronts searches a fire spot every
  `LOF_SPOT_RETRY` 3 s (`fire_spot`, scored with the fronts) and walks there when those fronts cost less (`_stand_move`).
- *Return fire:* a unit standing on an attack order, shot at within 3 s by a unit other than its target while its
  target cannot shoot back (`_shoots_at`) or it has no line to it, takes that shooter as its fire target (in reach,
  seen, a clear line and a line of fire; not a garrison at its windows); kept while that unit shot at it within
  `RF_HOLD` 6 s; the order's target is unchanged and comes back once the shooter stops. It changes only what the unit
  shoots, never where it goes. Its volleys at that shooter fire at any range (`_gun_unit`: not held to `m_volley_r`
  as fire at will's are). Fire at will prefers the unit shooting at it the same way. Tried and dropped: returning
  fire on the way once wounded (`walk_exposure85` lost 152 men against 112, the lines stopping to trade inside the
  side line's front), and standing to answer while closing on the target, garrisons included (open_town 88 -> 75 %
  with lines from cover; 81 without it: the storms stalled answering windows).

**4. Cost** (bench_west_muskets, `tests/benchmark.gd`'s scenario built by hand, 1,500 ticks, seed 42; timers wrapped
round ~45 functions in a scratch copy).
- *`lof_units`' answer kept across ticks* (`_lof_age`, `_lofc`, `_lofv`, `_lofr`): until either unit changes (its
  anchor moved this tick, its centre moved more than `LOFC_MOVE` 1 m or it turned more than `LOFC_TURN` 11 degrees
  since its stamp, a man fell, its cover spots, building or wall changed, `LOFC_LIFE` 2 s) or the obstacles change
  (`rub_n`, the gates); aged at the step's start and after the soldiers move; only the sim's calls inside `step`
  write it (the view's and probes' calls read it or trace); it is in the snapshot (a restored copy goes on with the
  same answers; `lockstep_test`). A unit on the move is traced afresh as before: kept across 2 m of a moving unit's
  drift, the 81 walks lost 872 men against 775 (stale answers on the way); as built, the cache alone moves them
  775 -> 768 lost, kills 959 -> 899 (a different, chaotic fight). Profile: `lof_units` 0.057 -> 0.024 ms a tick,
  `lof_block` 0.085 -> 0.054, the ageing 0.02.
- *The separation:* 6d3a81a's per-man search already walks a 2 m grid of the men where two units' boxes meet
  (`_mx_grid`); the box test only picks the pairs. Built, bit-exact (state hashes every 300 ticks equal on
  bench_west_muskets, bench_4000_city, bench_2000): the search inlined into the soldiers' loop with its arrays
  hoisted (`_sep_push` gone: 400-430 calls a tick in the city benchmark, about 2.8 us each with the call), and a cell
  holding only the man's own unit skipped (`mx_cu`). bench_4000_city's first 3,000 ticks 6.63 -> 6.35 ms a tick.
- *Measured* (3 paired rounds, a quiet machine, ms a tick): bench_west_muskets 2e16e7f (the base) 1.85, HEAD 2.30
  (+24 %), this pass 2.28 (+23 %; the brief's +15 %, 2.13, missed: the cache and the inlined search save about
  0.1 ms, the new behaviour spends most of it again: `_cover_places` 0.02, the ageing 0.01, more units on the move,
  58 path plans against 43); through `tests/benchmark.gd` 2.33 -> 2.28; bench_2000 2.13 -> 2.08 (the same battle);
  bench_4000_city 5.95 -> 6.30 over the whole battle, which now runs 6,000 ticks against 5,211 (a longer street
  fight), 6.60 -> 6.30 over the same first 3,000 ticks.
- *The men's step for moving units* (the next lever): `_update_soldiers` is 1.45 ms of 2.35 instrumented (62 %;
  HEAD 1.53 of 2.44); of it the slides 0.16, `_via_goal` 0.06, the clearance 0.07, the step guard 0.04, the separation
  now inside it; the rest, about 1.1 ms, is the loop itself over 9-10 units on the move a tick (each man's step toward
  his place, the nav and reach tests, the bounds). What it would take: a fast path for a man already on his place
  with his unit's anchor still (most men of a standing line: skip the step maths and the nav test), the nav test by
  cell index computed once per man rather than per probe, and the per-unit hoists the routing branch already has;
  about a day with the bit-exact hash check, perhaps 0.2-0.3 ms.

**Measured** (the third evaluation's probes re-run; before = a clean copy of HEAD d63e468, its numbers equal to the
evaluation's; tables and shots in the session scratchpad `cover4/`).
- *Lines from cover* (`spot_eval4`, eval2's `spot_eval2` with men-in-cover counts; lof_grid's 81 cases, 120 s, a
  musket company target 8 m behind a house that shoots back): cases with men on cover spots 0 -> 24 of 81; of the 8
  cases where `cover_cands` found a covered spot that serves, 0 -> 5 (men in cover against the target 0.2 -> 0.9 on
  average), own lost 128 -> 110, kills 152 -> 156, the exchange 1.19 -> 1.42; of the 25 others with cover within 13 m,
  0 -> 19, own lost 227 -> 207, the exchange 1.34 -> 1.34. Over all 81: own lost 775 -> 892, kills 959 -> 852, the
  exchange 1.24 -> 0.96, lost before the first shot 62 -> 65, first shot 21.3 -> 21.4 s: the halted target, a musket
  company behind a house under fire, now fights from that house's corners too.
- *The breach* (`breach_rub` / `breach_off`, 40 musketeers 3-10 m from a breach's middle, 60 on fire at will, 3 seeds,
  lost in 30 s): West walls 1, the line inside (on the town's higher ground), shooters 40 m out: 0-5 lost with the
  shooters on it 0-1 s -> 24-39 with them on it 30 s (flat rubble 45-55: the heap now shelters as light cover, about
  -30 %); the line outside, below the bank: 0 as before (hidden by the bank and heap; flat 52-63); Rome walls 2 inside:
  13-16 (third pass 16-22; flat 38-49).
- *The third enemy* (`walk_exposure85s`, 12 cases, own lost until arrival or 90 s, the side line B's losses added):
  the two Rome cases 21 -> 21 (it walks 27 s to its spot with no line inside B's front: neither rule applies) and
  48 -> 40, B 0 -> 24 (it returns fire; no spot within 40 m is out of B's front, so the stand-here walk never
  starts); the others 43 -> 45 (west_l2 80 m 60 degrees 2 -> 5); all 112 -> 106, B 0 -> 29. Not the 0 and 13 of the
  second pass, which never had a line there.
- *Balance* (tools/balance, 8 seeds, open_town 16; before 06075aadbc = HEAD, after 036ee5e010): `open_town` 88 -> 81 %
  (havana 81 -> 75, cartagena 100 -> 81, santo_domingo 81 -> 88); `west_named` 37 -> 36 % (walls 0 / 1 / 2: 55 / 38 /
  18 -> 55 / 36 / 18); `west_walls` 46 -> 41 % (69 / 41 / 29 -> 61 / 31 / 30: back from the third pass's edge, the
  third pass's 39 before it); `rome_walls` 59 -> 56 % (83 / 52 / 42 -> 77 / 52 / 40); all within the 8-point gate.
  Cells beyond their interval: veracruz w1 -50 (75 -> 25), campeche w2 +50, santiago_de_cuba (all -25), new_orleans w1
  -38, arverni w1 -38. Ablations on open_town (16 seeds, the build before return fire lost its stand and garrisons,
  75 %): lines from cover off 83, return fire and the stand-here check off 81, the cache off 75; as built 81. Lines
  from cover lean to the defenders in open towns (they stand; the attackers walk).
- Tests: custom_battle_test `_check_cover4` (lines from cover: 56 men in the wall's lee against 0 with it off, 26 lost
  against 38, back to the formation once the threat ends; the breach: both lines have a line of fire across a West
  breach's heap, the line shoots, 21 lost behind the heap against 30 over flat rubble; `_third_fronts` in front 300,
  behind 0, the target's own 0; return fire: the side line answered and lost men, off it kept its target and lost
  none); determinism_test's cover check runs the line rules with `LINE_COVER_ON` 0 and adds the town line taking
  spots with it on (no cover rolls); battle_screen_test's rubble case (the top view's heap marks on all 118 cells of a
  breach, none on the oblique path).

**Still open** (for the next evaluation): the 81-case exchange fell to 0.96 because both sides now fight from cover
(the attacker's own covered cases rose to 1.42); a line walking to its spot inside a third enemy's front with no line
yet still walks under its fire (Rome 80 m 0 degrees, 21 lost); the stand-here walk rarely finds a spot out of a
musket line's 120 m front; a West line below the town's bank behind a breach is hidden while its chip says light;
the breach heap shelters a line on the town's side about -30 % (a yard wall -49 %); men in cover are hidden from far
shooters (`_seen` at the body), so a line in cover is soon not shot at (the CoH reading would keep it visible);
`lof_units`' cache moves chaotic fights (kills -6 % over the 81 cases with it alone); bench_west_muskets +22 % (the men's
step is the next lever); narrowing at corners; firing on the move; fire at will ignores cover; garrison arcs, negative
cover, cursor icons, the chip on the unit card; suppression (the fifth pass); no device check.

### Suppression (as built, 2026-11-06)

Why: the fifth pass of line of fire and cover (the owner: a Company of Heroes kind of experience, built in passes with an
evaluation between each). The third evaluation's one-page design (session scratchpad `eval3/eval3.md`) is the brief's
basis: a meter fed by near misses and hits, cut by cover; suppressed and pinned states; a chip and a stand-in crouch; the
AI flanking pinned units and falling back to cover. Not morale: a channel of its own (`sim/battle_sim.gd` "suppression"
block, `_supp_*`).

**On or off.** A profile knob, `AP.SUPPRESS` (docs/AI.md 69: Easy 0, Average and Skilled 1); the battle has suppression
(`sup_on`) only when both sides' profiles have it (`_supp_setup`; `SUPP_FORCE` -1 / 0 / 1 for tests and probes), so the
tutorial and Easy play exactly as before. Its arrays (`u_sup` the meter, `u_sus` the state, `u_sut` the last gain,
`u_suc` / `u_sct` the cover class and its stamp, `u_sfb` the AI's fallback) are script variables (in every snapshot)
and hashed from the first gain on (`sup_used`), so a battle with no suppression hashes as before.

**Who.** Foot: missile foot, foot, pikes. Riders have the volley fright (`u_fright`) and are not suppressed; engines'
crews, ships, heroes and agents, tower crews and men carrying or pushing siege gear or on their way to take it up (ladders, a ram, a siege
tower, a mantlet: with them slowed, lockstep_test's siege tower was never planted) neither. A unit in a melee is in the melee's rules: its
meter empties and it has no state.

**The meter** (0-`SUPP_MAX` 1000, integers):
- *Gain* (`_supp_land`, in `_land` before any cover stop; `_supp_art` at the start of `_land_bolt` / `_land_stone`): a
  flat ball or an arrow aimed at a unit that lands within `SUPP_NEAR` 3 m of its men's box adds `SUPP_MISS` 8, a hit on
  one of its men `SUPP_HIT` 16 (a ball that finds another unit's man suppresses that unit); an engine's ball, bolt or
  stone aimed at it landing within `SUPP_ART_R` 6 m of the box `SUPP_ART` 60. Scaled by the shooter's weapon: powder
  `SUPP_W_GUN` 100 %, bows `SUPP_W_BOW` 20 % (archers shoot two to three times as many missiles as a musket line: at
  50 % a bow line pinned a musket line before muskets pinned anything), other flat missiles (slings, javelins,
  crossbows) `SUPP_W_FLAT` 40 %; and by the unit's cover against that shooter (`_supp_cover`, rated once a second at
  gain time: a held building or a wall's walk heavy, else `cover_rating_front` along its front toward the shooter for
  its troop type, a house the shooter holds not counting, men on cover spots at least light): light `SUPP_COVER_L`
  66 %, heavy `SUPP_COVER_H` 33 %. A friend's ball does not suppress.
- *Decay* (`_supp_tick`, each tick after morale): `SUPP_DECAY_PM` 4 per mille of the meter every tick (under fire too,
  so a steady fire holds the meter where its gain balances the decay, about 250 x the gain a tick), plus `SUPP_DECAY`
  4 a tick once `SUPP_QUIET` 2 s pass with no gain; both doubled in heavy cover.
- *States* with hysteresis: suppressed at `SUPP_T_SUP` 400 until below `SUPP_T_SUP_OUT` 250; pinned at `SUPP_T_PIN` 800
  until below `SUPP_T_PIN_OUT` 500 (then suppressed).

**What the states do.**
- *Fire:* suppressed `SUPP_FIRE_SUP` 70 % of the rate, pinned `SUPP_FIRE_PIN` 35 %: the bow accumulator's shooters, a gun
  line's reload and its rolling fire's clock (`_gun_unit`: they run on that share of the ticks, `(tick % 20) * 5 < %`),
  each man's reload in fire at will (`_pm_unit`).
- *Movement* (the anchor's speed): suppressed: no running and no charge (the walk, `SUPP_SPEED_SUP` 100 %); pinned: a
  move or withdraw order at the walk, any other order (an attack's approach, a fire spot's walk) a crawl at
  `SUPP_SPEED_PIN` 60 % of the walk. `SUPP_PIN_HOLD` 1 holds a pinned unit's approach outright (the eval's and the
  brief's "does not move except to fall back or on a player's order"): built and measured, open_town 81 -> 62 %, and
  left off (below).
- *Morale:* pinned loses `SUPP_MORALE_PIN` 2 a second and recovers none (no rout from the meter by itself).
- The player's Hold and Withdraw work as before (a pinned unit withdraws at the walk).

**The AI** (docs/AI.md 69): knobs 366-368, Easy 0. `SUPP_FALLBACK`: a pinned AI unit (not on a wall, in a building or
carrying gear) walks to the nearest cover against its shooter within `SUPP_FALL_R` 15 m (`supp_cover_spot`: rings
5 m apart, 12 bearings, heavy before light, not toward the shooter) and stands there while suppressed, at most
`SUPP_FALL_HOLD` 30 s. `SUPP_FLANK_PCT` (Average 50, Skilled 75): BattleAI's melee unit whose target is pinned in front
of it and more than 25 m off goes round its flank first (`_flank`); SiegeAI's storming foot count a pinned defender
`SUPP_PULL` 20 m nearer (the streets leave no room to go round). `SUPP_HOLD`: a missile unit keeps a suppressed or
pinned target (`_supp_held`). Measured as a block on open_town: the AI knobs off 60 % against 62 % on (noise).

**The view** (docs/design/ui.md "Suppression chips"): a chip at the marker's upper right (one yellow chevron
suppressed, two red pinned, at least 9 CSS px), the state first on the unit card's strip and in the tokens, "PINNED:
CANNOT CHARGE" / "PINNED: SHOOTING FROM HERE" on a pinned unit's attack line, and the men's stand-in crouch (the figure
squashed toward its feet to 76 % / 60 % of its height, a little darker; both soldier paths and the 3D view).

**The tuning round** (one, as the brief allowed). The first build (pinned held its approach, suppressed walked at 75 %,
other flat missiles 60 %) measured open_town 81 -> 62 %, beyond the 8-point gate; ablations on open_town (16 seeds,
48 battles each): suppression off 81 (the hashes of HEAD), no movement effects at all 85, pinned crawling at 50 %
instead of held 73, the AI knobs off 60 (the AI's use is not what costs the storms); the walk's slowing is the
attackers' loss (they cross open streets under fire from windows, heavy cover the garrisons barely feel). Built:
suppressed walks at full pace (no running, no charge), pinned crawls at 60 % on anything but a move or withdraw order;
`SUPP_W_FLAT` 60 -> 40 (the natives' slings and darts). Then two fixes the tests found: men with siege gear (and on
their way to it) exempt (lockstep_test's tower), and the fallback after a play's part (`Plays.unit_think` first).

**Measured** (before = a clean copy of HEAD 61aa44e; tables and shots in the session scratchpad `sup/`).
- *Set pieces* (`sup/probes/sup_probe.gd`, 100 musketeers a side 60 m apart on open ground, both on fire at will, 120 s,
  8 seeds; shots and men lost a side, HEAD -> now): muskets against muskets in the open: both suppressed by the first
  volley (0.6-1.0 s), side 1 suppressed 42 s of its 120, pinned in 2 of 8 at the opening; shots 426 / 426 -> 428 / 383,
  lost 67 / 68 -> 60 / 64. Side 1 behind a yard wall (1.3 m rocks 3 m before it): the open line suppressed at once and
  pinned in 4 of 8 at about 16 s, the wall line suppressed only 5 s of 120 and never pinned; shots 397 / 559 -> 205 /
  334, lost 73 / 35 -> 55 / 20 (the exchange for the wall 2.1 -> 2.75). Bows (100 archers) against muskets: the
  archers suppressed by the first volley and pinned in 5 of 8 at about 28 s, the musketeers suppressed in 6 of 8 at
  about 28 s, never pinned; shots 1,486 / 374 -> 1,254 / 398, lost 52 / 68 -> 53 / 57 (the archers' edge at 60 m
  gone). One-sided, the target holding its fire for 40 s: muskets in the open suppress it within 0.6 s and pin it in
  7 of 8 at about 27 s (pinned 5 s of the 40; it breaks at about 28 s with 52 lost either way); behind the yard wall
  suppressed 21 s of 40, never pinned, clear 8.4 s after the fire stops; bows suppress at 13.6 s and pin in 4 of 8 at
  33 s.
- *The 81-case spot probe* (`spot_eval4`, 40-man companies at 40-120 m): unchanged within a man (own lost 892 -> 891,
  kills 852 -> 850, exchange 0.96 -> 0.95; the covered-spot cases 1.42 -> 1.41): 40-man lines' fire never reaches the
  suppressed threshold there (the meters peak at 30-90); suppression is a matter of mass fire.
- *Balance* (tools/balance, 8 seeds, open_town 16; before 036ee5e010 = HEAD, after 13ae9d821d; the play-order fix after
  it touches only BattleAI field units in a play, the town plans run SiegeAI): `open_town` 81 -> 75 % (havana 75 -> 81,
  santo_domingo 88 -> 62, cartagena 81 -> 81; the first build 62); `west_named` 36 -> 42 % (walls 0 / 1 / 2: 55 / 36 /
  18 -> 62 / 38 / 25); `west_walls` 41 -> 45 % (61 / 31 / 30 -> 64 / 38 / 32); `rome_walls` 56 -> 56 % (77 / 52 / 40
  the same pooled); all within the 8-point gate. Cells beyond their interval: veracruz w0 +38 and w1 +50, campeche w1
  +38, cumana w2 +38, puerto_principe w0 -38. The lean: in open towns to the defenders (attackers cross streets under
  window fire; garrisons in heavy cover feel a third of the gain and lose it twice as fast), in walled West towns to
  the attackers (probably: the defenders' street lines and wall-foot companies stand in the open or behind yard walls under the
  storm's massed musket fire; on a wall's walk heavy). The natives' field edge (`asym_field`, 48 seeds, Spanish wins):
  25 -> 23 (natives 22 -> 24, a draw 1 -> 1); `asym_field2` 47 -> 46: the natives' bows (20 %) and slings (40 %) barely
  suppress a musket line, the Spanish volleys suppress the native foot but the charge only loses its run.
- Pins: campaign pins MATCH 12 / 12 (battles settle by formula); the flat goldens: bench_2000 re-recorded
  (78c42d10a48ff37c -> a780489f8f1cfd55: its lines suppressed and pinned), skirmish, test_cav_art and test_stone_line
  unchanged; the rules hash moves.
- Cost (paired, a quiet machine, ms a tick, HEAD -> now): the West musket town (`bench_wm`, 3 rounds) 2.27 -> 2.27;
  through `tests/benchmark.gd` (2 rounds) bench_west_muskets 2.30 / 2.31 -> 2.28 / 2.27, bench_2000 2.07 -> 2.10 (+1.4 %,
  a different battle: 4,191 ticks against 4,061), bench_4000_city 6.26 / 6.27 -> 6.05 / 6.09 (5,831 ticks against
  6,000); all within the +5 % budget (one box test and an add per landed ball, a cover rating a second per unit shot
  at, a pass over the units with a meter).
- Tests: custom_battle_test `_check_suppress` (the meter: suppressed within 0.6 s in the open, its average 473 in the open
  against 252 behind the yard wall, 5 s quiet from 800: 768 open against 550 in heavy cover, clear 7 s after the fire
  stops; a musket line held suppressed fires 200 shots in 33 s against 275; a pinned rodelero block on an attack order
  crawls 7 m in 10 s against 34 m, a move order 12 m (the walk); Easy: `sup_on` 0, no meter, the state hash as with
  `SUPP_FORCE` 0); battle_screen_test `_supp_cases` (top, oblique, 3D); lockstep_test (Average battles now suppress:
  snapshot / restore and two peers equal); roles_sim_test's countermarch last-volley check and determinism_test's
  salvo set piece run with `SUPP_FORCE` 0 (dated notes: the charging rodeleros, suppressed, met the last volley in the
  melee; the salvo lines stepping back at the walk never reached their posts in the window); determinism_test's
  golden for bench_2000 re-recorded.

**Still open** (for the next evaluation): the brief's "pinned does not move except to fall back or on a player's
order" is built as a knob (`SUPP_PIN_HOLD`) and left off for balance (pinned crawls at 60 %); suppression bites only
under mass fire (a 40-man company at 80 m never suppresses: the 81 spot cases unchanged); garrisons in heavy cover are
nearly immune, so open towns lean to the defenders and the AI storm has no way to suppress a window (grenades,
artillery, flanking a house: the next AI step); the field AI's flank of a pinned unit is the old `_flank` (no cover
test from the flank spot); the siege AI only prefers pinned defenders; the crouch is a squash (a real pose is an art
task, about an agent-day); men in cover hidden from far shooters stop being shot at, so they recover (CoH keeps
them visible); no negative cover; no device check.

### Suppression, second pass (as built, 2026-11-06)

Why: the fourth evaluation (session scratchpad `eval4/eval4.md`) found suppressed common and pinned a flash: the quiet
decay emptied the meter inside a musket's 12 s reload (763 after a volley, 226 by 12 s), so a pin lasted about 5 s; the
pinned target still suppressed the men charging it, so waiting for the pin never paid; garrisons were immune (peak
269-325 against the 400 threshold) and the AI's pin tools made no measurable difference. The sixth and last planned pass
of line of fire, cover and suppression (the owner: a Company of Heroes kind of experience): its gaps 1-3 and the
legibility (docs/design/ui.md "Suppression chips, second pass"). Sim statics in the "suppression" block of
`sim/battle_sim.gd`; one AI knob (docs/AI.md 71).

**A pin is a state** (`SUPP_QUIET_RELOAD` 1, `SUPP_HOLD_MAX` 90). Each gain also stamps `u_suh` = the tick + the
shooter's reload (`t_m_reload` of the ball's type, at most `SUPP_HOLD_MAX` 9 s; an engine 0) + `SUPP_QUIET`; the quiet
decay (`SUPP_DECAY` 4 a tick) starts only once the tick passes it, so a line between volleys is still under fire; the
per-mille decay runs as before. The two candidates measured on sup_grid and sup_loop (8 seeds): eval4's "no quiet decay
at all" (`SUPP_DECAY` 0) and the reload hold pinned alike (a silent line at 60 m 8 / 8 at 17.1 s), but with no quiet
decay one company kept a yard-wall line suppressed 82 % of 60 s (35 % with the hold, 10 % before) and a meter took
about 12 s longer to clear; the hold was kept. The full reload (12 s) took open_town 75 -> 88 % (beyond the gate; the
ablations: the garrison rule off 88, the hold not given to units in heavy cover, `SUPP_HOLD_COVER` 1, 88, the hold off
75: the defenders' street lines staying pinned), so the hold is capped: 6 s 75 %, 9 s 81 % (kept; `SUPP_HOLD_COVER`
stays 2, no effect measured).

**The loop pays** (`SUPP_SHARE` 1, `SUPP_CHARGE_FREE` 1).
- A suppressed or pinned shooter's balls feed suppression at its fire share (70 / 35 %, `_supp_share`), in the state it
  was in when it shot (`u_spv` / `u_sst`: the state before the latest change and its tick; a ball in flight when its
  shooter is pinned still counts in full, so two lines firing on the same tick do not depend on the unit order).
- A melee unit (no missiles) on an attack order whose target is pinned gains nothing from that target's fire, and its
  own suppression does not slow it (it may run and charge): the charge into a pinned unit keeps its run.

**Garrisons can be suppressed, never pinned** (`SUPP_GARRISON` 1): a held building's men keep the 33 % gain, but their
decay is no longer doubled and their meter stops at `SUPP_T_PIN` - 1 (a wall's walk and men behind a house keep the
doubled decay and can be pinned).

**The AI** (docs/AI.md 71): `SUPP_FLANK_TIME` (371; Easy 0): the field flank of a pinned unit only when the melee unit
can run 150 % of the gap before the pin lapses with no further fire (`supp_pin_left`: the decay run forward).

**Measured** (before = a clean copy of 4efb39b; 8 seeds; tables in the session scratchpad `sup2/out/`).
- *Set pieces* (`sup_grid`, 100 or 40 musketeers, 60 s; target's time pinned / suppressed, before -> after): a silent
  line at 60 m pinned 6 / 8 at 26.5 s -> 8 / 8 at 17.9 s, pinned 6 -> 19 % (it breaks at about 28 s either way); a
  duel at 40 m pinned 12 -> 23 % / suppressed 7 -> 8 %; a duel at 60 m suppressed 33 -> 80 %, pinned 2 -> 5 % (the
  suppressed line's fire suppresses at 70 %, so both stay suppressed rather than pinned); one company on a yard-wall
  line never pins it (40 m suppressed 14 -> 25 %, 60 m 10 -> 22 %, lost 16 -> 16); two companies pin it 8 / 8 at
  60 m, pinned 42 -> 49 % of the time; a 40-man company suppresses a silent 40-man line at 60 m in 0 -> 6 of 8 (peak
  342 -> 547; still never pinned) and pins a 100-man block at 40 m in 8 / 8 (never before); 100 bows against 100
  muskets: the musketeers suppressed in 3 / 8 -> never (the archers, suppressed by the first volleys, suppress at 70 %);
  at 100 m nothing, as before (the matchlock volley range).
- *The loop* (`sup_loop`, 2 x 60 musketeers against 100 behind a yard wall at 60 m, 120 pikes; before -> after):
  charge at once: contact 39.7 -> 42.3 s, the target pinned at contact 3 of 7 -> 7 of 7, pikes lost before contact
  23.4 -> 23.4; charge when pinned: the pin at 22.8 -> 18.0 s, contact 57.6 -> 48.8 s, pinned at contact 3 of 6 ->
  4 of 4 (the rest broke first: routed 64.8 -> 49.4 s), lost before contact 24.3 -> 24.8. The charge after the pin
  takes 30.8 s from the order against 34.8 (the pikes run, 2.2 m/s; before they walked once suppressed), and the
  target stays pinned until they arrive. Waiting still does not beat going at once on contact time: the charge at once
  also arrives on a pinned target now (the target is pinned at about 18 s, the pikes' crawl turns into a run then),
  and the pikes' losses are the opening volley at the standing block (from 90 m, out of range, they lose none either
  way; `sup_loop2`: waiting at 90 m, contact at 62.2 s with the target pinned 5 of 5, against 40.8 s at once).
- *Garrisons* (`sup_town`, 8 West AI town battles): the peak meter at walls 0 269 -> 603 (suppressed, below the cap),
  walls 2 325 -> 271; garrison unit-seconds under fire suppressed 0 -> 77 (their losses then 0.5 per 100 balls);
  foot outside buildings under fire with a suppression chip 5.6 -> 10.4 % (pinned 15 -> 22 unit-seconds); men lost
  attackers / defenders 920 / 1,252 -> 723 / 1,047. The AI knobs 366-369 off: 715 / 1,052, one fallback fewer: the
  siege AI's fallback and hold still make no measurable difference in towns (the hold's targets are seldom pinned
  there, and a garrison never is).
- *The field flank* (`sup_flank`, 8 cases, 180 s): flank orders 108 -> 17 (166 with `SUPP_FLANK_TIME` off), contacts
  4 -> 0 (1 off): the orders that could not arrive are gone, and two companies now break the pinned target by fire
  before any melee unit gets there (the rodeleros' 70 m yard-wall case routed 60.3 -> 53.0 s).
- *Balance* (tools/balance, 8 seeds, open_town 16; before f7c585b9d9 = 4efb39b, after fd979a6bbc): `open_town` 75 ->
  81 % (cartagena 81 -> 100, havana 81 -> 69, santo_domingo 62 -> 75); `west_named` 42 -> 41 (walls 0 / 1 / 2: 62 / 38 /
  25 -> 57 / 50 / 16); `west_walls` 45 -> 45 (64 / 38 / 32 -> 60 / 48 / 26); `rome_walls` 56 -> 56 (77 / 52 / 40 ->
  75 / 50 / 42); every plan within the 8-point gate, the walls-1 rows of the West beyond it (+11, +12) and walls 2 -6,
  -9. Cells beyond their interval: veracruz w0 -62 and w2 -38, port_royal w1 +62, new_orleans w1 +38, campeche w1 -50,
  cumana w2 -38. The natives' field edge (`asym_field`, 48 seeds, Spanish wins) 23 -> 22 (natives 24 -> 25), `asym_field2` 46 -> 47.
- Pins: campaign pins MATCH 12 / 12; the flat goldens: bench_2000 re-recorded (a780489f8f1cfd55 -> a98576372a5d8e8d),
  skirmish, test_cav_art and test_stone_line unchanged; the rules hash moves.
- Cost: paired rounds on a loaded machine (load 10), ms a tick, before -> after: the West musket town (`bench_wm`, 3
  rounds) 2.42 -> 2.39; through `tests/benchmark.gd` (2 rounds; the first round's "before" for the last two
  benchmarks an outlier, 7.14 / 3.11) bench_2000 2.26 / 2.27 -> 2.23 / 2.22, bench_4000_city 6.62 -> 6.44 / 6.71,
  bench_west_muskets 2.46 -> 2.45 / 2.51; all within the +5 % budget (a stamp per gain, a lookup per landed ball,
  `supp_pin_left` only when the AI considers a flank).
- Tests: custom_battle_test `_check_suppress2` (the pin held 300 of 300 ticks in 3 seeds against 147 with the first
  pass's quiet; a charge into a pinned line 34 m in 10 s against the crawl's 7 m, a pinned line's hit feeds it nothing;
  a garrison peaks at 796, suppressed, a heavy-cover line outside 992, pinned; 2 s quiet from 700: 580 against 466);
  roles_sim_test's countermarch set pieces (Auto, Hold, Use now and `_cm_walk`) and determinism_test's town line
  (`LINE_COVER_ON` 0) run with `SUPP_FORCE` 0 (dated notes: the pike block, pinned through the reloads, broke at 48.6 s
  and Hold fired six volleys, not seven; the town line was pinned 18 s and routed, its runners "off their places").

**Still open:** waiting for the pin does not beat charging at once in contact time (both arrive on a
pinned target now; the measure that would show the loop is a charge across the target's fire before the pin, which
the set pieces do not separate from the opening volley); the AI's town tools (fallback, hold, the siege pull) still
measure as noise; a garrison is suppressed only under massed fire (two companies) and the AI has no way to aim at
windows on purpose; the field flank rarely reaches a target because fire breaks it first; the duel tends to mutual
suppression rather than one side pinned (the share rule); the crouch is the placed quad, not a pose (a kneel / crouch
action in the sheets: pose functions, a re-pack, the oblique sheets and the 3D cards, about an agent-day of art);
negative cover, garrison fire arcs, cursor icons, narrowing at corners, the +22 % step cost of the cover passes; no
device check. The evaluation loop stops here: what remains is feel, for the owner's phone.

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
| Line of fire | flat weapons (javelins, bolts): the straight line from 1.5 m above the shooter's ground to 1 m above the aim point's, allowed to rise `m_apex`% of the distance at mid-flight (javelins 10%, bolts 2%), sampled every 4 m (8 m for target choice), ground within 3 m of either end ignored. Fire at will skips hidden targets; an explicit order on one is refused (missile infantry walks on until it can see, a target the side does not see counting as hidden, at worst into contact, and on a landform map goes round a cliff by the path; a battery waits; `HIDDEN_CLOSE_ON`, docs/AI.md 48: it used to stop at a quarter of its range and stand there for good with its target behind a crest or a cliff) |
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
  an open town: a square round it. `field_zones` merges a side's flank
  boxes that touch into one box per group and cuts every rect so it holds
  no enemy unit (the 40 m box round each enemy it reaches taken out). A
  scenario key `"ambush": s` (campaign ambush, campaign_rules.md "Ambush
  battles"): `field_zones` gives side s a strip along the map's axis and
  the other side two bands, one each side of it, and `_setup_deploy` does
  not deploy side s with the AI (its column stands as placed).
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

**Sight linger (2026-10-27).** The owner's "units pop in and out of
sight" (docs/STATUS.md, the line-of-sight plan; the view's last-seen ghost
is the other half). Two rules, no new sight traces:
- *Linger*: a unit an enemy's eyes saw (an enemy near enough, a sight
  line, contact) that a check then finds unseen, in battle, stays seen
  `VIS_LINGER` 30 ticks (3 s) more in the open, `VIS_LINGER_WOODS` 15 (in
  woods or a cover unit gone to ground in cover, the test `_seen` uses;
  checks come every `VIS_T` 10, so 2 s in practice), then hides as before
  (`u_hid0`, the ambush clock and the reveal flash unchanged; lingering
  checks count neither as hidden nor as a reveal). Once a hiding: the
  grant (`u_lin`, the tick it began; hashed with the other `_vis_arrays`,
  so flat maps hash as before) is earned again only by an enemy's eyes.
  While the armies deploy a unit hides at once and the hiding spends it.
  A shot's reveal (`REVEAL_T`) neither earns nor spends it: a unit hidden
  when it shot hides at once when the reveal runs out (the 5 s already
  lingered); one the enemy saw before it shot lingers after the reveal if
  the enemy has lost it by then (the reveal skips the sight lines, so
  "seen meanwhile" is "seen before the shot").
- *The band* (hysteresis): a unit that is seen stays seen by an enemy
  within `VIS_NEAR` + `VIS_WOODS_OUT` 10 m (30 m), in woods `VIS_WOODS` +
  10 m (50 m), box to box; an unseen one still needs 20 m / 40 m.

Test: determinism `--only=linger`. Measured (48 seeds, before = HEAD):
asym_woods Spanish wins 1 -> 0 (natives 46 -> 47, draws 1), reveals per
battle 33.1 -> 28.4 (-14 %), hidden checks 3455 -> 3277, 13.8 lingers a
battle; asym_field 42 = 42 (no sight blockers). Hidings in asym_woods (12
seeds): 307 in woods / 19 in the open -> 234 / 4, and reveals within 3 s
of a hiding (the flicker) 51 -> 5. Most of the remaining reveals are real
(a unit hidden for longer than 3 s). With the open-ground linger alone
(woods hiding at once) asym_woods did not move at all (33.1 reveals a
battle): 94 % of its hidings are in woods. What moved: no pinned golden
(the four flat maps have no blockers); every determinism run on a map
with sight blockers has a new final hash (u_lin is hashed and the AI sees
differently: test_woods, the siege_* and west_town runs, battle_2000@2,
bench_2000@3 / @4, the river crossings).

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

### Pursuit as a unit (as built, 2026-10-30)

Why: the owner, playtesting: a unit chasing a unit gets close enough for
its first line to break off and fight while the other keeps fleeing; it
is far less effective than pushing in with the whole unit, it gets split
up, and then acts oddly when repositioned. Measured first
(`tests/chase_probe.gd`, docs/AI.md 46): against routers or a unit
walking away the attacker's anchor stopped 1 m short of the target's box
edge, measured with the box's half depth from its centre, so behind the
real rear edge of a strung-out target, and its front rank, capped at
`PLACE_LEAD` ahead of its places, stood just out of reach (100 light
after routing heavy: 0 kills in 60 s; horse after routing light: 11
kills, then 35 s of nothing); after a target moving away (not routing)
the anchor held while any man was within `INREACH_EXTRA` of his man, so
the men stood at reach + 1 m and never struck (100 heavy at the run
after 100 light walking away: 12 men "in reach", 0 blows, 0 kills); and
after routers the anchor ran (7/8 of the run) while its men walked to
within 3 m of their places (`CATCH_UP_DIST`), so the whole unit trailed
3 m behind its places. Code: `sim/battle_sim.gd` (`_chase_mode`,
`reform_anchor`; hooks in `_update_units`, the attack branch's closing,
`_anchor_step0`, `_update_soldiers`, `_apply_unit`, `apply_order_rule`).
Each rule has its switch (static, 1 on): `CHASE_BACK_ON`,
`CHASE_PUSH_ON`, `CHASE_PACE_ON`, `CHASE_RUN_ON`, `CHASE_REFORM_ON`.
**Not on settlement maps** (`CHASE_TOWN_ON` 0; since docs/AI.md 47 the
town rules of `CHASE_TOWN` 1, below): built on every map they
moved the town battles beyond their intervals (Rome walls 1-3 attackers
47 -> 60 %, docs/AI.md 46), so there the battles play as before; on
field maps (open, woods, landforms, hamlets) they apply.

- **Moving away.** Every `CHASE_DT` 10 ticks each unit's centre is
  sampled (`u_hx`, `u_hy`) and its movement since the last sample kept
  (`u_vx`, `u_vy`). An attacker pursues (`_chase_mode`, `u_chase` this
  tick): 2 when its target routs; 1 when fewer than a quarter of the
  target's men fight and its centre went `CHASE_AWAY_MIN` 0.5 m or more
  away from the attacker's anchor over the last sample (0.5 m/s; the
  target's own movement, so an anchor keeping pace does not switch it
  off).
- **Push** (`CHASE_PUSH_ON`): a pursuer's anchor stops 1 m from the
  target's centre (the pack's rule), not 1 m short of its box edge; it
  may step into its own target's footprint with men in reach while it
  pursues. The second and third ranks reach men too.
- **Pace** (`CHASE_PACE_ON`): "wait for my men" (the anchor holding while
  a man is in reach, or while its men fight and it is ahead of them)
  applies only to a target that is not moving away; after one moving away
  the anchor keeps closing at its own walk or run (the run flag as
  ordered; after routers at the run as before).
- **Men run with their places** (`CHASE_RUN_ON`): while its anchor runs
  after routers (no run order), its men's formed pace is the run, not the
  walk. Not in the brief; the rear leash needs it (without it every man
  is 2.7-3 m behind his place and the leash drops them all: 0 kills in
  the probe's rout and horse cases).
- **Rear leash** (`CHASE_BACK_ON`, `PLACE_BACK` 3 m): while its anchor
  moves (or it pursues), a fighting man more than `PLACE_BACK` behind his
  place along the facing lets his man go and makes for it; he looks for a
  man again only within `PLACE_LEAD` of it (no new per-man state: the
  band between is the hysteresis). Not on a wall or a stair, in a
  building, carrying, a pack (`t_chase`), a formed pike block or a charge
  (those paths do not reach it). `stat_chase_back` counts man-ticks.
- **Re-form on the men** (`CHASE_REFORM_ON`, `reform_anchor`): a new move
  or attack (not a move to within `REFORM_IN_PLACE_DIST` of the current
  destination, not an attack on the current target, so the AI's repeated
  orders do not trigger it) to a ground unit (not artillery, a wall or a
  stair unit, carrying, in a building, a pack) whose men's middle is more
  than `REFORM_IN_PLACE_DIST` from its block's centre, or whose men spread
  along its facing over twice its depth, first puts its anchor (the
  block's front centre) on its men: the block centred on their middle
  (among obstacles, off its ground: the man nearest their middle,
  `_anchor_man`). It is in the order prediction (`apply_order_rule`), so
  OrderPreview shows it. The lag regroup (`REGROUP`) does not fire within
  `REFORM_QUIET` 50 ticks of a re-form (`u_rft`). `stat_reform`.
- **State.** `u_hx`, `u_hy`, `u_vx`, `u_vy`, `u_chase`, `u_rft` (per unit,
  in `_unit_arrays`: hashed everywhere, in snapshots). With every switch
  0 the battles play as before the change (the probe's numbers equal
  HEAD's) but the state hash differs by the new arrays.
- **Missile units.** None of the rules changes a missile unit's own
  conduct (with ammunition it takes the shooting branch, never pursues;
  checked by switch after `tests/custom_battle_test.gd` "light missile"
  failed at its seed: the AI's foot pursuing fallen-back skirmishers left
  one row with nothing in range; the test now tries such a row alone,
  docs/AI.md 46.5).
- **Measured.** docs/AI.md 46 (the probe per rule, the harness, the
  pins).
- **Towns, the pursuit bonus, the skirmisher's order (2026-10-30,
  docs/AI.md 47).** `CHASE_TOWN` replaces `CHASE_TOWN_ON` (0 none of the
  rules on a settlement map, 1 the town rules, 2 the field's). The town
  rules: pace and push only after routers (`_chase_mode` gives 0 for a
  target merely moving away); the push's stop not in a gate, on a wall
  cell or rubble, in a house or within `OCC_DOOR_R` of a held building's
  door step (`_push_stop_ok`: there the stop short of the box edge, as
  before); re-form only for an order whose `player` is below
  `BattleAI.AI_PLAYER_BASE` (the AI's orders never re-form in a town);
  the leash and the run as in the field (`CHASE_TOWN_LEASH`,
  `CHASE_TOWN_RUN`, 1). The pursuit bonus (`CHASE_FULL_RUN_ON`): an anchor
  after routers at its men's full run (8/7 of the old pace), routers at
  7/8 of theirs, so a unit gains on routers of its own type; field only
  (`CHASE_FULL_RUN_TOWN` 0). The skirmisher's order (`SKIRM_RESUME_ON`,
  `u_ptarget` hashed, in snapshots): a skirmisher falling back under an
  attack order keeps the target; with the fall-back done and no threat
  near it takes the order up again if the target lives, is within 150 %
  of its range and is not attacking it, else it fires at will; a new
  move / attack / halt / withdraw clears it. The flat goldens skirmish and
  bench_2000 moved with the bonus.

### Filtering through a friendly unit (as built, 2026-11-02)

The owner: "Take a look at unit filtering when moving through friendly squads." Diagnosis (`tests/pass_probe.gd`,
a unit of side 0 marched 80 m through a standing friend 40 m ahead, no enemy near): the anchor crossed the friend's
footprint at half speed (`BLK_FRIEND`, `_half_step`) and the men walked straight through the friend's men: away from
an enemy the men only follow their places (the fast path keeps no distance from other units' men; the friendly
separation lives in the contact path only), so two lines of the same spacing passed file inside file, men drawn on
top of one another (a musket line through a musket line: 4,975 man-ticks with two men of the two units within 0.5 m,
2,300 under 0.25 m, closest 0.00 m; a column 3,795; lancers through foot 971; foot through lancers 2,123; Rome's heavy
foot 6,330), the standing unit never moved, no slot changed hands and both came out in order; the pass cost the mover
3.2 s on a 68 s march (the half speed while its anchor was inside the friend's 4 m cells).

Rule (`sim/battle_sim.gd`, "Filtering through a friendly unit": `_mix_ok`, `_mix_build`, `_mix_pairs`,
`_mix_cross`, `_mix_grid`, `_mix_r`, `_mix_step`, `_mix_give`; hooks in `step` and the fast path of
`_update_soldiers`). **Only a real crossing.** Every `PASS_THINK` 8 ticks the units on the move (not settled; the
anchor moved this tick or a move or attack order stands) are paired with friends whose boxes come within `PASS_BOX`
2 m (the broad phase), and a pair mixes only when the mover crosses the friend (`_mix_cross`): the line down the
mover's middle, from `PASS_AHEAD` 3 m ahead of its front back to its rear rank (or its box's rearmost corner, men left
behind their places), enters the friend's formation rectangle (`PASS_CROSS` 0.3 m round it, in the friend's frame).
A friend marching shoulder to shoulder, beside or behind, whose rectangle the mover's line never enters, is left
exactly as before. Both must be formed, ready, on the ground, out of contact, not charging, not on a wall, stair or
ladder, not in a building, no engines, not afloat, not a hero or an agent (`u_char`: a character's handful of men
slips through files as before; they walk to their posts through their own lines all battle, and the lines giving way
to each changed the AI battles' course: determinism_test `chars` lost its diplomat's parley), in a field battle (not a
settlement battle: there files interleave as before; a build that only kept it away from walls and houses still
moved the storms through crossings in the open approach and the plaza, rome_walls walls 1 / 2 71 / 48 -> 85 / 65 and
four west_walls cells beyond their intervals, all back with the filtering off), and not within 4 m of a rock or a
cliff (`_u_obs`). Between searches the pairs found stand while both can still mix. Only
the men within `PASS_REACH` 1 m of where the two boxes overlap (`u_mxr`) take part, in a 2 m grid (`MX_SHIFT`).
**The men.** A man is on the move while his unit's anchor moved this tick or he is further than `PASS_MOVING` 0.25 m
from his place; else he stands. A man looks round every other tick (by his index); on the move, with a man of
another friendly unit within their joint room (`PASS_R_FOOT` 0.3 m a man on foot, `PASS_R_RIDER` 0.5 m a rider, a
beast its body: two men on foot keep 0.6 m, a rider and a man 0.8 m) and `PASS_LOOK` 0.25 m, he keeps only the part
of his step along his unit's facing and goes sideways at most `PASS_SLIDE` 0.125 m a tick: toward the middle of the
gap between the files of the standing friend nearest him (to his right when square behind a file), so a file
threads a gap as a file, and away from men of a friend also on the move (two units crossing pass right hand to right
hand); a man just ahead within their room holds him back to at least `PASS_KEEP_PCT` 25 % of his step; between his
looks, a man further than `PASS_ODD` 3 cm off his file's line keeps going straight ahead. A standing man with a
moving man of another friendly unit within their room and `PASS_LOOK` stands (his place does not pull him back) and
side-steps across the mover's unit's facing, away from him, at most `PASS_GIVE` 0.1 m a tick; between his looks one
stood aside stays aside; when they are by, his place pulls him back. Nobody changes slots. The slowdown stays the
anchor's: `PASS_PCT` 50 % of its speed while the anchor crosses another friend's footprint (the constant names the
old half step; unchanged, so the pass costs what it did). No state of its own: the pairs, the overlap rectangles and
the grid are scratch rebuilt from the positions (snapshot-covered as script variables; restore runs on identically).
Untouched: the contact path (melee push, pursuit's contact, the friendly separation of fighting men), routers, wall
and stair units, ladders, men in buildings, settlement battles, skirmishers' loose order. The AI
does not reason about passes (no eta or route uses the pass speed beyond the anchor's half step it always had), so
no knob.

Measured (the same probe after; in brackets man-ticks under 0.25 m, before -> after): a line through a line 4,975 ->
78 man-ticks within 0.5 m (2,300 -> 0), closest 0.00 -> 0.47 m, the standing men aside up to 0.32 m; a column through
a line 3,795 -> 105 (1,820 -> 0), closest 0.41 m; lancers through foot 971 -> 31 (288 -> 0), closest 0.39 m; foot
through lancers 2,123 -> 0 (636 -> 0), closest 0.67 m; Rome's heavy 6,330 -> 113 (3,150 -> 0), closest 0.40 m;
musketeers through a pike block 3,354 -> 785 (736 -> 0; the pike files 0.9 m apart are narrower than two men's room,
so the pikes give way and the musketeers squeeze), closest 0.45 m; pass times unchanged (line 70.9 s against 67.7 s
clear, column 70.9, lancers 45.2 against 43.2, foot through lancers 77.4 against 67.7); after every pass every man
stands in his own place. Battles (field): the asymmetry probe, Spanish wins, `asym_field` 46 -> 43 of 96 seeds, `asym_field2` 47 -> 45 of 48;
the filtering alone (the countermarch's walk off) 27 -> 31 and 47 -> 44 of 48; the countermarch alone 12 -> 12 and
24 -> 23 of 24. Settlement battles do not filter, so `tools/balance` town plans move only by the pistols' walk (below,
"The countermarch (as built, 2026-11-02)"); rome_walls plays exactly as before. Cost: `bench_2000`, 1,500 ticks headless, 2.44 s -> 2.64 s (+8 %;
the first build, which mixed any unit on the move within 0.5 m of a friend every tick, +36 %).

The exit-field restore (fixed with it). `_xf_restore` rebuilt the routers' exit fields from today's `nav`, but a
generation is built from the `nav` of the tick it began; a breach's or a fallen house's rubble since then made the
restored copy's fields differ (`siege_city@ai~ae` in `determinism_test` diverged 112 of 360 ticks once the battle's
course moved). Each generation now keeps the `nav` it began from (`xf_nav_l` live, `xf_nav_p` pending; script
variables, so in snapshots) and restore rebuilds from those.

Tests: `tests/roles_sim_test.gd --only=pass` (the four passes; two lines marching shoulder to shoulder and one 4 m
behind another never mix). Shots: `tests/pass_probe.gd --png=DIR` (top-view dots at the moments the mover's anchor
crosses 207 ... 180 m, and the worst tick).

(2026-11-06) Since "Filtering always on (as built, 2026-11-06)" below, the crossing filters for heroes and agents
and near rocks too (settlement battles still interleave by the crossing's rule, measured there), and every man of a
unit out of contact keeps his room from any other unit's men, towns included; the crossing rule above is otherwise
unchanged.

### Filtering always on (as built, 2026-11-06)

The owner: "the filtering should be active all the time, not just when one of the troops are in combat or
stationary". Two parts (`sim/battle_sim.gd`, "Filtering always on": `_sep_ok`, `_sep_r`, `_sep_build`, `_sep_rect`,
`_mx_grid`, `_sep_push`, the second pass at the end of the fast path of `_update_soldiers`).

**The crossing.** `_mix_ok` lost two exclusions: heroes and agents (`u_char`; determinism_test `chars`, the diplomat's
parley that failed in 2026-11-02's first build, passes) and units within 4 m of a rock or a cliff (`_u_obs`); the
man's step after a threading still goes through the nav test and the slide. The settlement exclusion stays, by
measurement (one exception, kept minimal: the crossing's machinery, not the separation): with the crossing in towns
the defenders falling back through one another into the acropolis were held by the 25 % step hold and the threading
(determinism_test "shut inner gate": the acropolis shut at tick 4,081 instead of 901 and the ram was never sent; with
the crossing out of towns shut at 901 and the ram sent at 1,507; HEAD 901 and 1,477). In towns the separation below keeps the men of two units apart. The crossing itself (`_mix_cross`, the
threading through files, the side-step, `PASS_PCT` at the anchor, the 25 % hold) is as it was.

**The separation.** Beside the crossing, every man of a unit out of contact keeps his room from every other unit's
men, friend or enemy (`_sep_r`: `SEP_R_FOOT` 0.23 m a man on foot, two keep 0.45 m centre to centre; `SEP_R_RIDER`
0.4 m; a beast its `body_r`). Every `SEP_THINK` 2 ticks the units that may (`_sep_ok`: ready, out of contact, not
charging or knocked about, not on a wall, stair or ladder, not in a building, no engines, not afloat, not a ship;
towns and characters included) are paired when their boxes come within their joint room and `SEP_BOX` 0.3 m (not
both settled); the strip where the two boxes meet, that much round it, is the pair's region (`u_spr`), and only men
in it are in the grid (`mx_head`, 2 m cells, shared with the crossing; rebuilt every tick while a crossing runs, else
on even ticks). After a unit's men have made their steps (and the nav test), each man in its region looks every
other tick (by his index) and is moved out of every other unit's man within their joint room by the whole overlap,
at most `SEP_NUDGE` 0.085 m a tick (`_sep_push`; two men on one spot part across his unit's facing, the lower index
to the left); a move into a blocked cell is dropped. Between his looks, a man of a standing unit who stepped back
from a nudge to within `SEP_NUDGE` of his place goes back where he stood, and a man held where he stood is at rest,
so a unit beside another settles. No slowdown, no hold, no knob: the anchor moves as before (the march speed is
HEAD's to the tick). Melee keeps its own push (the contact path is untouched), routers, wall and ladder men and men
in buildings as before. No state of its own: the pairs, the regions and the grid are scratch rebuilt from the
positions (script variables, so in snapshots; lockstep_test passes).

Measured (`tests/march_probe.gd`, HEAD -> after; closest two men of different units over the march, man-ticks under
0.4 m / under 0.25 m, the anchors' arrival): two musket lines side by side with their flank files 0.4 m apart 0.39 m,
2,808 / 0 -> 0.39 m, 1,342 / 0 (the places themselves 0.4 m apart: between his looks a marching man steps back to
his place), 67.7 -> 67.7 s; the same with the flank files on one line (places overlapping by a file) 0.00 m, 2,808 /
2,808 -> 0.00 m, 242 / 202 (the first seconds), 67.7 s; a column 0.3 m behind a line 0.29 m, 167 / 0 -> 0.34 m, 8 / 0,
70.4 s; four companies of 60 crowding a walls-0 oppidum's streets to its plaza 0.01 m, 14,623 / 2,966 -> 0.01 m,
11,546 / 976 (the street's walls squeeze them: a nudge into a house is dropped), 238.0 s both. The crossing probe
(`tests/pass_probe.gd`, closest m and man-ticks within 0.5 m, HEAD -> after): line 0.47 / 78 -> 0.47 / 67, column 0.41
/ 105 -> 0.42 / 100, lancers through foot 0.39 / 31 -> 0.39 / 4, Rome's heavy 0.40 / 113 -> 0.43 / 99, musketeers
through pikes 0.45 / 785 -> 0.46 / 783; pass times unchanged. Cost: the separation alone on the same course (its
pushes computed and dropped) about 5 % of a bench_2000 tick; the first build (every man every tick, the region 1.5 m
round the boxes, the pushes inside the soldier loop) cost 11 %, the second pass and the grid on even ticks halved it.

The ladder queue's spots (found with it). `_ladder_start` now puts each man's waiting spot (`_lw_x` / `_lw_y`,
scratch, not in snapshots) where he stands: until `_ladder_step` first ran for a new climb the men below walked one
tick toward another climb's spots (or the origin), so a restored copy went its own way (lockstep_test siege diverged
138 ticks after its 2,915 snapshot once the battle's course moved).

### Paths clear of the enemy (as built, 2026-11-06)

The owner: "pathing, the units should take a path that doesn't cross them in front of the enemy or through the enemy
to get into a building or to a location." Code: `sim/battle_sim.gd`, "Paths clear of the enemy": `_rt_pct`,
`_rt_zones`, `_rz_add`, `_rz_sel`, `_rz_in`, `_rt_cost`, `_rt_seg`, `_rt_eval`, `_rt_way`, `_rt_stale`, `_seg_box`,
`_rt_point`, `_rt_plan`, `_rt_graph`, `_rt_smooth`, `_rt_grid`; docs/AI.md 64.

**Who.** A unit under a move order (a point, a building's door: ORDER_OCCUPY is a move to it, a wall's stair foot),
formed, out of contact, on the ground, carrying no siege gear, not by water (the amphibious planner as before), not
in a building (`_rt_pct`); an AI side's units take a way at most `AP.RT_DETOUR_PCT` % longer than the plain one in a
field battle (Easy 0: the plain way; Average and Skilled 50) and `AP.RT_TOWN_PCT` in a settlement battle (0 at every
skill: the siege AI's storms slipping round the defenders by the side streets moved west_walls walls 0 from 52 to 71 %
attacker wins; docs/AI.md 64), a player's `RT_DETOUR_HUMAN` 50 everywhere (scenario `rt_human`: the ambush set piece
of determinism_test sets 0 so its company marches straight into the ambush). Attacks (they must go at the enemy),
pursuit, routers, withdrawals, the ladder, ram, pole and tower carriers, men on a wall, a stair or a ladder, the
column march's shape, the sortie's attack orders and the ships of 9ce2837 plan as before.

**The zones** (`_rt_zones`, when the way is planned): each enemy unit its side sees (not hidden), formed, not routing,
on the ground, not in a building or on a wall: its box and `RT_MARGIN` 4 m and the unit's own half width (at most
`RT_OWN` 6 m: the anchor is its front's middle) can not be crossed; in front of a shooting unit with ammunition (its
facing +-45 degrees, `RT_ARC`, or its own arc if wider, within its range and `RT_MARGIN`) a metre costs `RT_FIRE_PCT`
300 % more; in front of a melee unit (its width and `RT_MARGIN` either side, `RT_FRONT` 15 m deep) `RT_FRONT_PCT`
100 % more. A zone holding the goal is left out (the unit means to go there), a box holding the anchor too.

**The plan** (`_rt_plan`). The path is planned as before (straight, or over the street graph); if that way touches no
zone nothing changes. Else a way round is searched: over the street graph's nodes where the map has one (`_rt_graph`,
A*: an edge costs its length and its dearest metre's %, sampled every `RT_STEP` 2 m; edges through a box are shut;
the distance tables `_dist_table` are not used or changed), else over a grid of the open field (`_rt_grid`, cells
`RT_CELL` 4 m, coarser to stay within `RT_CELLS` 4,000 in the rectangle round the anchor and the goal with room for
the detour, 8 neighbours, at most `RT_EXPAND` 4,000 cells), shortcut where the straight line is clear and no dearer
(`_los_fat` on maps with obstacles), at most `PATH_MAX` waypoints. It is taken when it is through no box, at most the
detour % longer and cheaper; when the plain way goes through an enemy's box, any way round at most twice the detour
% longer is taken. `u_rtd` marks a way round (no shortcut past its waypoints, `_path_point`). On the open field the
unit follows it by `_rt_point` (the same path arrays; reached at `WP_REACH`). Every `RT_REPLAN` 20 ticks the rest of
the way is looked over (`_rt_stale`: an enemy's box with its margins now across a leg, tested segment against box)
and the plan is made again; a firing line turning onto the way does not re-plan (the way would swing with every turn).

**State.** `u_rtd` and, on a plain map, the path arrays (`u_pn`, `u_pk`, `u_pgx`, `u_pgy`, `u_pep`, `pth_x`, `pth_y`)
are hashed once `rt_used` (some unit planned with a zone near); battles where none did hash as before. Snapshots carry
them (script variables); the zones and the searches are scratch.

**What reads it.** Only the plan of a unit on a move. The AI's estimates read no path (BattleAI and SiegeAI use
straight distances and the anchor), the stragglers' `_via_goal` and the view's `route_to` (route preview, refusals)
use the plain street graph, so the AI's choices are unchanged by the term; only the way its units walk.

Measured (`tests/route_probe.gd`, HEAD -> after; the anchor's way, men lost on the way, the outcome; shots
`--png=DIR`): 60 rodeleros ordered past the front of a 100-man musket line facing across their way (70 m off) walked
straight in front of it, 104 m, 35 men lost, routed -> went round out of its reach, 312 m against the plain 271 m
(+15 %), 0 lost, arrived; a defending musket company sent into a house in west_village with the enemy's company
standing on the plain way to its door walked into it, 91 m, 29 lost, held in the melee short of the door -> went round
the block by the south and west, 315 m against 180 m (the through-an-enemy limit), 24 lost passing 10 m from the
company (a musket line's 120 m reach covers any way to that door), inside; the same rodeleros sent to a point 70 m
behind a musket line facing them (the line turns to its target, so no way round is out of its fire) 85 m, 37 lost,
routed -> round the flank of its range, 199 m, 38 lost, routed. An attack order on that line goes straight at it
(no plan round, the anchor within 0.8 m of the straight line). Cost: the plans on the same course about 2 % of a
bench_2000 tick (the look-overs test only the boxes, segment against box).

Battles (tools/balance, 8 seeds, before a clean copy of HEAD, the whole change: the separation, the crossing for
heroes and near rocks, the paths; attacker wins %, pooled): open_town 79 -> 88 (19 -> 21 of 24; Havana 38 -> 62, no
cell beyond its interval); west_named 35 -> 37 (walls 0 / 1 / 2 57 / 38 / 9 -> 62 / 34 / 14); west_walls 38 -> 40
(52 / 34 / 27 -> 57 / 37 / 27); rome_walls 56 -> 51 (75 / 52 / 42 -> 69 / 50 / 35); the asymmetry probe (Spanish
wins of 48) asym_field 23 -> 25, asym_field2 45 -> 47. Cells beyond their intervals: Havana walls 1 50 -> 12, Veracruz
walls 0 50 -> 100, Cumana walls 2 100 -> 50, St Augustine all walls 21 -> 46, Attica walls 1 100 -> 62. The tuning round
(the first build): the siege AI going round in towns moved west_walls walls 0 52 -> 81 (the separation alone 52 -> 52,
the paths alone 52 -> 71), hence `RT_TOWN_PCT` 0; the crossing in towns, hence its settlement exclusion kept.
Campaign pins match (battles settle by formula); the flat goldens skirmish, bench_2000 and test_stone_line
re-recorded (test_cav_art unchanged).

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

Display names of the rows the Itza, Miskito and Brethren share are per faction (`UNIT_NAMES` in `campaign/data/west.gd`; `ui.md`, per-faction unit names).

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

## The Caribbean roster, batch 2 (plan, 2026-10-24)

Batch 1 gave each side one or two pieces of its own; batch 2 fills the gaps the asymmetry principle shows: Spain
has no horse shot for the field it is meant to own, the Dutch have no specialist at all, the nations have no cheap
garrison filler, the pirates have no gun they can bring ashore, and the natives have only bowmen and clubs where
history gives them darts, stones and poison. Seven West rows and one ammunition kind; every row has a `role`
(the roles' behaviours of step 2 apply unchanged: skirmishers in loose order and cover, horse skirmishers
caracoling). Each is a West row, a sprite set (the 6-bit field has 34 of 64 used), a roster and AI entry in
`campaign/data/west.gd`, a UNIT_NEEDS entry, a book page and a custom battle list entry.

- **Mounted arquebusiers** (New Spain and Tierra Firme; Stables 1 + Range 1; `horse_skirmish`): Spain's horse
  shot. `cls` cav, an arquebus (musket range, the dragoons' reload), the step-2 caracole and pistols-at-contact
  brace; melee between dragoons and lancers, armour light, cost a little above dragoons. Played: ride to the
  flank of a native party in the open and shoot it out of cover's reach; charge only the routed. The field piece
  that makes the Spanish the side to beat in the open.
- **Marines** (England and the Dutch; Barracks 2 and a Port 1 in the town; `line`): disciplined shot with the
  deck bonus of `DECK_CREWS`, morale a step above musketeers, melee the musketeers' plus a quarter, a musket at
  the musketeers' reload, fewer rounds, cost between musketeers and grenadiers. Played: the landing party that
  holds a beach or a quay, and the nations' answer to pirate boarders. The Dutch's first specialist.
- **Landed naval guns** (the Brethren and the Dutch; Workshop 1 and a Port 1; `guns_field`): a ship's demi-cannon
  on a sledge: the heavy gun's shot (400 or more, so the destruction AI counts it a wall breaker and batters with
  it when the side has no mortar), range the field gun's, reload slower, moves at half the field gun's pace,
  crew the heavy gun's, cost below the heavy gun. Played: hauled up from the boats to knock a hole in a fort; the
  pirates' siege answer without a Workshop 3.
- **Colonial militia** (every nation; Barracks 1; `line`): cheap, numerous (the largest West foot count), a musket
  at a slow reload, poor accuracy, morale low, melee weak, armour none, upkeep half the musketeers'. Played: the
  garrison that holds a wall and a gate; in the field it fires one volley and runs. Gives the nations numbers
  without giving them quality, so a raid still bites.
- **Maroons** (the Brethren and the Miskito; Barracks 1; `skirmish`): escaped-slave communities, machetes and a
  few muskets: `cover`, ambush, the coureurs' woods pace, a short musket (the buccaneers' accuracy, 60 % of
  their range, few rounds), melee the best of any skirmisher (near cutlass men), morale high in woods (the
  cover trait's bonus), armour none. Played: the ambush party that also wins the brawl in the trees; useless
  in a line.
- **Atlatl darts** (Itza; Range 1; `skirmish`): dart throwers. Range 45 m, a dart that ignores light armour
  (`m_ap` or the javelins' armour rule, whichever exists), 8 darts, fast reload, `cover`, melee the native
  warriors' minus a step, cost low. Played: from the tree line at a column's flank; the Itza's reach past the
  bowmen's.
- **Slingers** (Itza and Miskito; Barracks 1; `skirmish`): Rome's slinger row re-costed for the West (range 80 m,
  harass, a stone's morale bite), `cover`, cheapest West row. Played: the screen that makes a Spanish column
  halt and deploy, then is gone.
- **Poisoned arrows** (an ammunition kind for the native bowmen, Itza and Miskito; Range 2; in `AMMO_AVAIL`
  beside the fire arrows): a struck man who is not killed is poisoned; a poisoned unit loses one man every
  `POISON_T` (20 s) per 8 poisoned men and 2 morale with each, until no poisoned men remain (sim: a per-unit
  poisoned count and a tick, packed arrays, hashed only when any unit is poisoned, snapshotted). Damage per hit
  a third below the plain arrow. Played: a party that took a volley from the trees keeps bleeding as it marches;
  the natives win by what happens after the ambush, not during it.

**The AI.** `AI_SPECIALISTS` gains maroons, atlatl, slingers and mounted arquebusiers; `AI_BUILDUP_LINES` gains
marines and the landed guns (they need a Port). Colonial militia go to the garrison mix, never the field army's
first pick. The battle AI already caracoles, seeks cover and batters.

**Order of work.** (1) Sprites for all seven (Sonnet; poses and props; atlas rebuilt; `soldier_facing_test` both
paths) and (2) the poison ammunition in the sim (Opus; small; hashed; `tests/roles_sim_test.gd` or a sibling)
in parallel; then (3) the rows, rosters, needs, AI lists, book pages, custom battle lists, tests and the West
pins (Sonnet); then (4) the harness before / after (west_named, open_town, west_walls) and the asymmetry probe
with the Spanish army given mounted arquebusiers and the natives slingers and atlatl (`asym_field` /
`asym_woods` get a second army pair), read against the principle.

### Batch 2 measured (2026-10-24)

The harness before (c4f39dd) and after the rows (c1c6dcd) is identical in every cell of west_named (336 battles),
west_walls (768) and open_town (24): the plan armies field none of the new rows. The asymmetry probe gained a
second army pair, `asym_woods2` / `asym_field2` (`Scenarios.asym(woods, true)`: the Spanish swap a musketeers
block for 40 mounted arquebusiers on the flank, the natives a canoe raiders for 70 slingers and the holcan for
60 atlatl; costs 2,780 vs 2,770). On 48 seeds (seed0 16): woods natives 46 / Spanish 1 / 1 draw (first pair 47 / 0 /
1); field Spanish 45 / natives 3 (first pair 39 / 9). The principle holds with the new pieces: the horse shot adds
nothing in the trees and rides down the slingers and darts in the open; the natives' cheap missile foot does not
rescue them in the field. Watch the field edge (94 %) against the plan's "clearly favoured": it is on the far side.

### Poisoned arrows (as built, 2026-10-24)

- **The kind.** `UnitTypes.AMMO` row 13 `poison_arrows` ("poison"), riding on arrows (base 0), a third of the
  quiver (share 33), 67 % damage and 67 % against gates and towers, range and reload as arrows, no fear or fire;
  a new generic AMMO field `poison` (1) read into `t_k_poison`. The custom battle picker offers it wherever fire
  arrows are offered (`ammo_specials`: every special riding on arrows). The unit book line says "poisons".
- **The campaign grant** (owner 2026-10-24): one special arrow per native nation, split by faction. West
  `AMMO_AVAIL`: `["fire_arrows", ["itza"], RANGE, 2]` (the city builders, sieges) and
  `["poison_arrows", ["miskito"], RANGE, 2]` (the raiders). (A unit carries one special kind, the first
  matching row: `CRules.ammo_for`.)
- **The poison.** A man struck by a poison kind and not killed adds one to his unit's `u_poisoned` (at most its
  men alive); the first sets `u_poison_t` to `POISON_T` 200 ticks (20 s). `_poison_pass` (after the missiles and
  fire, before morale; only once `poi_on` is set) in unit index order: the count is clipped to the men alive;
  when the clock runs out the unit loses d = `max(poisoned / POISON_PER 8, 1)` men, each also `POISON_MOR` 2
  morale on top of a death's own loss, and r = `poisoned / POISON_RECOVER 4` men recover (no morale); the count
  falls by d + r and the clock restarts while any remain. About a third of the men poisoned die in the end; no
  RNG. The deaths are missile kills in the stats and credited (`u_kills`) to the unit that poisoned it last
  (`u_poison_by`); `stat_poison_hits`, `stat_poison_dead` are diagnostics (the result screen lists no causes, so
  no line there).
- **Accepted simplifications.** The poison is a count per unit, not per man: a man hit twice counts twice
  (capped at the men alive), and the men who die are taken from the back of the unit's slots, not the wounded.
- **State.** `poi_on`, `u_poisoned`, `u_poison_t`, `u_poison_by` (packed, per unit): hashed only once `poi_on`
  is set (a battle where nobody is poisoned hashes as before); snapshot / restore by the script-variable capture.
- **AI.** `BattleAI.ammo_suits`: a poison kind suits a target (not artillery) whose armour is under `AK_ARMOUR`;
  the standard arrow otherwise.
- **View.** A green strip down the right edge of a poisoned unit's card and "N poisoned" in its summary.
- **Tests.** `tests/poison_test.gd`: 40 bowmen shoot 120 native warriors for 30 s and cease fire; plain arrows
  (88 hits): no losses after the shooting stops (117 -> 117); poisoned arrows (92 men poisoned): 112 alive at
  36 s, 93 at 140 s, 27 dead of poison (all credited to the bowmen), 8 still poisoned; snapshot / restore
  mid-bleed and a repeat run identical. Goldens and battle pins unmoved; two wagon run hashes moved only because
  `q_stock` (hashed) has one more column per wagon for the new kind (siege_eq_ring3 b0378b37 -> d4f9a12c,
  siege_eq_polis2~sa 83ff7f7b -> 708664df; every coverage line equal). West campaign pins moved on the seeds
  where Miskito raise bowmen at a Range 2 (the unit entries now store `"ak": "poison_arrows"`; docs/STATUS.md).

### The Caribbean roster, batch 2 (as built, 2026-10-24)

Seven rows after the mortar in `UnitTypes.WEST_LATE` (every earlier index unchanged; `pack_test _batch2`), sprite sets
34-40 of `art_pipeline.md` (the naval gun draws its crew from set 25 and its engine from set 36). Every row has a
`role`. The poisoned arrows of the same batch are built (above). Derivations, relative to the rows named:

| Row (key) | Line, role | Buildings (`UNIT_NEEDS`) | Who | Men, cost | Melee | Missile |
|---|---|---|---|---|---|---|
| Mounted Arquebusiers (`mounted_arquebusiers`) | `dragoon` (tier 1), `horse_skirmish` | Stables 1 + Range 1 | New Spain, Tierra Firme | 40, 11 (440) | cls cav; attack 28, defence 25, armour 5, damage 30, hp 135, morale 680, charge 30, lancers' walk 2.2 / run 8.6; `pistols` 2 | the dragoons' musket exactly (120 m, 120, 20 rounds, reload 24 s) |
| Marines (`marines`) | `marine`, `line` | Barracks 2 + Shipyard 1 | England, the Dutch | 80, 7 (560) | attack 28, defence 22, damage 32, armour 5, hp 90, morale 740 | the musketeers' musket, 16 rounds |
| Landed Naval Guns (`naval_gun`) | `naval_gun`, `guns_field` | Workshop 1 + Shipyard 1 | the Brethren, the Dutch | 12 (3 pieces of 4), 50 (600) | crews as the heavy gun's | roundshot: 450 m, damage 400, 8 rounds, reload 48 s, `m_obj` 550, walk 0.3, deploy 20 s, `e_hp` 360 |
| Colonial Militia (`colonial_militia`) | `militia`, `line` | Barracks 1 | all five nations | 140, 3 (420) | attack 16, defence 14, armour 0, damage 22, hp 75, morale 380 | fowling piece: 100 m, damage 110, 12 rounds, reload 18 s, `m_spread2` 175; `upkeep_pct` 70 |
| Maroons (`maroon` line: `maroons`) | `maroon`, `skirmish` | Barracks 1 | the Brethren, the Miskito | 60, 5 (300) | attack 38, defence 24, damage 38, armour 0, hp 90, morale 660, `cover`, `woods_pct` 45 | short musket: 84 m, 130, 10 rounds, reload 20 s, the buccaneers' accuracy |
| Atlatl Dart Throwers (`atlatl`) | `javelin` (tier 1), `skirmish` | Range 1 | Itza | 60, 4 (240) | attack 32, defence 22, damage 30, armour 1, hp 80, morale 600, `cover`, `woods_pct` 60 | dart: 45 m, damage 40, `m_ap` 80, 8 darts, reload 2.4 s |
| Slingers (`w_slingers`) | `sling` (tier 1), `skirmish` | Barracks 1 | Itza, Miskito | 70, 3 (210) | Rome's slingers' (18 / 16, damage 22, hp 75), `cover`, `woods_pct` 60 | Rome's sling (stone `m_ak` 9, damage 28, 40 stones, reload 3 s) at 80 m, `m_fear` 20 |

**Derivations.**
- **Mounted arquebusiers.** Melee between dragoons (26 / 24, damage 28, hp 130, morale 660, charge 25) and lancers (36 / 26,
  34, 140, 740, 75): 28 / 25, 30, 135, 680, charge 30; armour 5 (dragoons 4, lancers 6). Missile: the dragoons' musket
  and reload unchanged (the plan: musket range, the dragoons' reload); the `pistols` 2 key is what gives the
  pistol brace (`AB_PISTOL`) and, with `horse_skirmish` and a firearm in the cavalry class, the caracole (`AB_CARACOLE`),
  exactly as the dragoons are tagged. Cost 11 a man, a tenth above the dragoons' 10 (440 a unit against 400).
- **Marines.** Melee the musketeers' (22 / 18, damage 26) plus a quarter: 28 / 22, damage 32; armour 5 (musketeers 4); hp
  90 (85); morale 740, a step above the musketeers' 640 and a little under the cutlass men's 700-plus rows (the boarding
  grenadiers 700; the step is 100). The musket is the musketeers' (range, damage, reload 12 s, accuracy), rounds 16 (20).
  Cost 7 a man in a unit of 80 = 560, between the musketeers (6 a man, 600 a unit) and the grenadiers (8 a man, 480 a
  unit) on both measures. The deck bonus of `DECK_CREWS`: a marine kit in `ST.DECK_LINE_SHOT` (`marine`: 30 % hits, 7
  cells, 2 volleys, reload 100 ticks, against the musket line's 26 / 7 / 2 / 120); the militia's (`militia`: 20 / 7 / 2 /
  160) is worse. (The Brethren's / nations' `DECK_CREWS` sailors' kits are unchanged: the bonus belongs to the troops'
  per-line volley, as batch 1's grenadier and dragoon lines.)
- **Landed naval guns.** The heavy gun's shot (420, `m_ap` 100) a little under, 400, so the destruction AI counts it a wall
  breaker: the AI's `BATTER_HEAVY` is a wall damage of 400 (`80 % x m_obj`), so `m_obj` 550 gives 440 (the heavy gun's 700
  gives 560, culverins 450 gives 360). Range the culverins' 450 m (heavy guns 520); reload 48 s (culverins 40, heavy 52);
  walk 0.3 m/s, half the culverins' 0.6 (heavy 0.4); crew 4, `crew_min` 2 as the heavy gun; 8 rounds (10) for what the
  boats carried; deploy 20 s (culverins 18, heavy 24); `e_hp` 360 (320 / 400). Cost 50 a crew man = 600 a unit (heavy
  720, culverins 480). `ART_LEVEL["naval_gun"]` = 1 (the unit book's "Workshop 1").
- **Colonial militia.** Size 140, the largest West foot unit (pikemen 120). Melee a step and more below the
  musketeers: 16 / 14 (22 / 18), damage 22, armour 0, hp 75, morale 380 (640). A poor musket: range 100 m (120), damage
  110, 12 rounds (20), reload 18 s (12 s, "slow"), `m_spread2` 175 (135, "poor accuracy"). Cost 3 a man = 420 a unit
  (musketeers 600). Upkeep half the musketeers': the campaign upkeep is `price x 15 % x upkeep_pct`, so 420 x 15 % = 63
  x 70 % = 44 a turn against the musketeers' 90 (49 %).
- **Maroons.** The skirmisher with the best blade: 38 / 24, damage 38 (cutlass men 40 / 26, buccaneers 28 / 22), hp 90,
  armour 0, `cover` 1 (ambush and the cover bonus to morale; row morale 660 to sit under the coureurs' 680). Woods pace
  45, the coureurs' (`pack_test` now asserts both are 15 points better than any other row). Musket the buccaneers'
  accuracy (`m_spread2` 100, damage 130) at 84 m (60 % of 140), 10 rounds, reload 20 s. Cost 5 a man (the cutlass men's).
- **Atlatl.** Melee the native warriors' (38 / 24, damage 36, hp 85, morale 620) a step down: 32 / 22, damage 30, hp 80,
  600, armour 1. The dart is the Rome javelin's row (40 m, damage 42, `m_ap` 60, 6 a man, `m_spen` 15, reload 2.8 s)
  with range 45 m, damage 40, `m_ap` 80 ("ignores light armour": the armour-piercing percentage, as the javelin's is 60),
  8 darts, reload 2.4 s. Cost 4 a man = 240 (the warriors').
- **Slingers.** Rome's slinger row (`slinger`: 18 / 16, armour 2, damage 22, hp 75, morale 560, 40 stones, reload 3 s,
  accuracy 50 / 1024, stone ammunition 9, `m_arc` 1, skirm, cover) with the plan's West range of 80 m (Rome 150 m),
  `m_fear` 20 for the stone's morale bite, woods pace 60 (the natives') and a cost of 3 a man in a unit of 70 = 210
  (Rome's 4 a man, 80 = 320): the cheapest West row (canoe raiders and the atlatl 240).

**Lines, slots and chains (where the plan was silent).**
- **Four new lines**, `marine`, `naval_gun`, `militia`, `maroon` (so each is its own mix key; none could share a place in
  a main line without hiding batch 1's specialists, because `_mix_type` falls to the line's main unit and a second
  specialist in the same line would hide the first); `CData.LINE_CHAIN` Barracks, Workshop, Barracks, Barracks;
  `LINE_ORDER` after the musketeers (marine, militia), the buccaneers (maroon) and the field guns (naval_gun);
  `ART_LEVEL` naval_gun 1; the unit book's building table and the custom picker's `WEST_LINES` likewise (the picker also
  gains `javelin` and `sling`, which now hold West rows). The mounted arquebusiers take the dragoon line, the atlatl the
  javelin line and the slingers the sling line (Rome's, a Range line: their Barracks 1 comes from `UNIT_NEEDS`).
- **Port.** There is no "Port" building: the pack's Shipyard (`CData.SHIPYARD`, built at harbour regions only, level 1
  = the smaller hulls) is the port requirement. A marine or a naval gun can only be raised in a harbour with a Shipyard.
  The AI's build-up (`AI_BUILDUP_LINES`) raises only the line's first requirement (Barracks 2 / Workshop 1); the Shipyard
  comes from the fleet AI's own yard-building (`cai_fleet`), which builds one at its best port. If the military centre
  is inland, the AI's marines wait.
- **Rosters.** New Spain and Tierra Firme: `dragoon` ["mounted_arquebusiers"], `militia`; England: `marine`, `militia`;
  France: `militia`; the Dutch: `marine`, `naval_gun`, `militia`; the Brethren: `naval_gun`, `maroon`; the Itza: `javelin`
  ["atlatl"], `sling`; the Miskito: `maroon`, `sling`.
- **AI mixes** (sums as before; the share comes from the nearest line): New Spain cav 12 -> 9 + dragoon 3; Tierra Firme cav
  25 -> 21 + dragoon 4; England musket 37 -> 34 + marine 3; the Dutch musket 40 -> 35 + marine 5 and field_gun 7 -> 5 +
  naval_gun 2; the Brethren buccaneer 35 -> 31 + maroon 4, light_gun 5 -> 2 + naval_gun 3; the Itza light 52 -> 45 +
  sling 7, archer 35 -> 27 + javelin 8; the Miskito light 50 -> 44 + sling 6, musket 15 -> 10 + maroon 5. The plan named no
  shares; these are small, from the nearest line. `AI_SPECIALISTS` += maroons, atlatl, w_slingers, mounted_arquebusiers
  (no effect for now: none shares a line with a main unit, so `_mix_type` returns each at once and the mix share is the
  limit); `AI_BUILDUP_LINES` += marine, naval_gun.
- **Colonial militia in the garrison only.** The AI's recruiting works through the mix and the militia are in no mix, so
  the field armies never raise them; the campaign garrison (`CRules.garrison`) is a rule of its own, and its
  `missile` place now tries the `militia` line before `musket` (`_garrison_type`: at a tier-1 garrison, an unwalled
  village or town; cities and walls 2+ keep the veterans). Rome has no `militia` line, so its garrisons are unchanged.
  The player may recruit them (Barracks 1).
- **Chains' texts**: the West Barracks, Range, Stables and Workshop descriptions name the new units.
- **Tests.** `pack_test _batch2` (rosters, exact buildings, indices, sets, the gun's wall damage, costs, ability bits,
  garrison, picker, mixes), `roles_test` (the seven roles).

## The Caribbean roster, batch 3: the characters (plan, 2026-10-24)

The West has no characters: the six rows of `UT.CHARS` (the four heroes, the assassin, the diplomat; "Heroes
and agents (as built)") carry no pack and the campaign's character rules (`campaign/cchars.gd`, `CHAR_NEEDS`,
the AI's heroes and diplomats) are Rome's. Batch 3 gives the West four characters of its own on the same
machinery, one per kind of side, judged against the asymmetry principle; the sim gains two small generic fields
and the rest is data. Every row is a West character row (`"char": 1`, `"pack": "west"`, appended after the
existing CHARS so no index moves), a sprite set through the pipeline, a `CHAR_NEEDS` entry, a book page, a
custom battle toggle, and the campaign AI raising it as it raises Rome's.

- **Sea Captain** (England, France, the Dutch, the Brethren; Shipyard 1; hero, `CK_FOOT`'s rules with a role
  filter): the Champion's body (46 / 40 / armour 10, hp 600, `duel`, never breaks) in a sea coat with a cutlass
  and a pistol brace (the pistols ability); his aura (40 m) reaches only units whose role is `skirmish` or
  `shock` and the marines (new row field `au_roles`: a list of roles the aura applies to; empty = every unit as
  today): +15 % to-hit, +3 morale a second. On the campaign, a fleet carrying him sails with its captain's quality
  one step higher (`CCaptain` reads the army's characters; auto-resolve at sea too), `char_pct` 6. Played: the
  pirates' and the nations' landing-party leader; useless to a pike block.
- **Privateer** (England, France, the Dutch, the Brethren; Market 2; agent, the assassin's rules unchanged:
  hidden, Sabotage of batteries and gates, Attempt on a general or hero, taken by a crowd): the assassin row
  re-skinned (a hat, a dark coat, a knife and a pistol); price 800. Played: ashore before the assault, he spikes
  the fort's guns and unbars the gate for the boarders.
- **Missionary** (New Spain, Tierra Firme, France; Market 1; agent, the diplomat's rules): the diplomat row in a
  robe with a cross, unarmed, the steadying aura (30 m, fear losses halved); his Parley succeeds more often
  against native units (new row field `parley_vs`: a list of packs or roles, here the natives' rows, with
  `parley_bonus` +25 points on both rolls), and on the campaign a missionary standing in a native region of ours
  adds public order as a Market does (if the campaign has public order; else nothing and say so). Played: the
  Spanish answer to a native war party that will not stand: talk it off the field.
- **Shaman** (Itza "Ah Kin", Miskito "Sukia", one row `shaman`; Barracks 1; hero, `CK_FOOT`'s rules with the role
  filter): a weak body (30 / 25 / armour 0, hp 300, no `duel`, never breaks), feathers and a staff; his aura
  (40 m, `au_roles` `skirmish` and `shock`) +15 % to-hit and +3 morale a second, and a second effect the Champion
  lacks: enemy units within 30 m of him take the elephants' kind of fright, +1 fear a second (`au_fear`: a new
  aura bit on the rout test, the steadying aura halves it as it halves the beasts'). `char_pct` 4. Played: in the
  trees behind the war party; the natives' morale answer to the tercio's.

**The AI.** `CData.CHAR_NEEDS` for the West rows; `cai.gd`'s hero kinds map the West: a sea captain to the
armies of the coast nations and the Brethren, a shaman to the natives' war parties, a missionary at Skilled as
the diplomat is raised; privateers never (as assassins). The battle AI's character use (docs/AI.md 27) applies by
kind unchanged.

**Order of work.** (1) Sprites for the four (Sonnet) and (2) the sim fields `au_roles`, `au_fear`, `parley_vs` /
`parley_bonus`, and the campaign hooks (the fleet captain's quality from a sea captain aboard; the missionary's
public order if the rule exists) on Opus, in parallel; then (3) the rows, `CHAR_NEEDS`, the AI's kinds, the book
pages, the custom battle toggles, tests and the West pins (Sonnet). Then the campaign_sim pacing on 72 seeds and
a probe battle each: a shaman with the natives in `asym_field2` (does the Spanish edge narrow a little without
flipping), a sea captain with the pirates on a deck, a missionary's parley against a wavering war party.

### Batch 3 sim and campaign hooks (as built, 2026-10-24)

Step (2) of the order of work: generic fields only, no West rows (the rows come next). Every field defaults to
today's behaviour (no row sets one), so every hash, golden and pin is unmoved. Tests: `tests/chars_test.gd` (Rome's
Champion and Diplomat given the fields for the run: roles, fear, parley, snapshot) and `campaign_test` `_sea_cq`.

- **`au_roles`** (character row, an Array; default empty = every unit as before). A list of role keys
  (`UT.ROLES`), and, beyond the plan, pack names and row keys (a unit's own key or its base row's: the sea
  captain's "and the marines", whose role is `line`); `UT.row_named(lst, ty)` decides. The sim builds a row-match
  table per listing row in `_load_types` (`t_aur_i` offsets into `ch_match`, nt bytes a table, static) and
  `_ch_serves(sty, tu)` (the unit's own type, `u_otype`) gates the friendly aura bit in `_update_auras` and
  `_ch_near` (the cavalry hero's rally of routing riders). The kind's own filter (`_ch_bit`: foot for `CK_FOOT`)
  still applies on top: a `CK_FOOT` row's `au_roles` can only narrow it among foot.
- **`au_fear`** / **`au_fear_r`** (character row, ints; default 0). A new bit `AU_FEAR` 16 in `u_aura`, set in
  `_update_auras` on every ready ENEMY unit that is not a character within `au_fear_r` (box to box; 30 m, `AU_FEAR_R`,
  when a row gives `au_fear` without a radius; half for a wounded hero, as his aura's) of a ready hero with
  `au_fear` > 0: `au_fear` is added to the second's aura loss beside the elephants' / camels' `fear_foot` /
  `fear_horse`, and it counts as feared (`u_awe`: no recovery of heart meanwhile, `stat_feared`), as the beasts'
  fright does. The diplomat's steadying aura halves that loss as it halves the beasts' (the same line). A row with
  `au_fear` is an aura source (`aura_src`). Hashed through `u_aura` (only with `ch_on`); the static `t_au_fear`
  / `t_au_fear_r` are rebuilt by setup. Morale scale: the elephants' `fear_foot` is 2 a second.
- **`parley_vs`** (an Array: role keys, pack names, row keys, as `au_roles`) and **`parley_bonus`** (points;
  default 0) on a diplomat-kind row. `BattleSim.parley_bonus(dty, tu)`: the bonus when the row's list names the
  target's own type (`u_otype`), else 0 (`t_pv_i` / `t_pv_b`, static). In `_ch_parley` it is added to the roll's
  percentage, routing (`PARLEY_PCT` 60) or wavering (`PARLEY_PCT_W` 35), and clamped to 95 (a recovered unit's 0
  stays 0). The roll itself is the same draw of the sim's RNG, so on a given seed the bonus only turns refusals into
  surrenders. The book's parley text (`game/unit_book.gd`) still quotes the plain 60 / 35: the rows' pages should add
  the bonus. Note: the natives are no pack of their own (their rows are `"pack": "west"`), so the missionary's list
  names their row keys (or roles).
- **`sea_cq`** (character row, campaign; default absent). `CCaptain.sea_step(st, fl)`: the best `sea_cq` among the
  fit characters (`CChars.fit`) attached to the armies a fleet carries (`fl["carry"]`, `CChars.of_army`; the
  character travels with his army as before, `sweep` keeps a carried army's characters). `CCaptain.fleet_tier(st,
  fl)`: the captain's fame tier (0 without a captain: the nations' fleets) plus that step, at most the top tier
  (`FAME_TIERS.size()`, Legend). Every read of the captain's quality for a sea battle now goes through it:
  `cseabattle.build` (a fleet counts as Feared for `SEA_FEAR_FOE` at tier 2+; the ships' `"cq"` = 100 + `CAPT_CQ` 20
  x tier, the deck melee's captain's fighting %; the ships' `"mor"` through `fear_pct`), `CCaptain.fear_pct` (the
  power % in the sea auto-resolve, `CFleet._side_power`, and the morale above; `FEAR_PCT` by `fleet_tier`, still 0
  for a fleet with neither captain nor step, and for a state without captains unless a step applies) and
  `CFleet.resolve`'s strike rule (the winners' best `fleet_tier` 2+: `STRIKE_LOSS` / `STRIKE_TAKEN`; the most famous
  captain still names the prize money). The player's and the AI's fleets alike (both build or auto-resolve here).
  Fame, bounties and the view's tier names read the captain alone, unchanged.
- **`order_bonus`** (the missionary's public order): not built. The campaign has no public order or unrest rule
  per region (a Market gives income and trade only, `crules.gd`), so there is nothing to add to; the plan's "if the
  rule exists" applies.

Open for the rows step: the battle AI places a `CK_FOOT` hero in "the second line" behind the line centre
(`battle_ai.gd`, docs/AI.md 27) whatever his `au_roles`; a sea captain or shaman wants the AI to post him behind
units his list names. The AI's parley pick does not weigh `parley_bonus`. (Both built 2026-10-24, docs/AI.md 39: `BattleAI._aura_centre`, `CH_PARLEY_BONUS`.)


### The Caribbean roster, batch 3 (as built, 2026-10-24)

Step (3) of the order of work: the four West character rows and everything round them. Sim untouched (the fields
were built in "Batch 3 sim and campaign hooks"); Rome's hashes, goldens and all four Rome pins unmoved; the West's
two campaign pins moved (the AI now raises the West's own characters, not Rome's six).

- **Rows** (`UT.WEST_LATE`, appended after `w_slingers`: no index moves; `"pack": "west"`, `"char": 1`, `role`
  `command`, one man each, `"sprite_set"` 41-44 so the soldier layer draws the new men, not the procedural figure;
  `"icon"` 35-38 and a view-only `"glyph"`):

| Key | Kind | Price | Body | Fields |
|---|---|---|---|---|
| `sea_captain` | `CK_FOOT` | 1,500 | 46 / 40, armour 10, no shield, hp 600, `duel` 35, `nobreak`, `pistols` 2 | `au_hit` 15, `au_mor` 3 within 40 m, `au_roles` skirmish, shock, marines; `sea_cq` 1; `char_pct` 6; the Champion's fall numbers |
| `privateer` | `CK_ASSASSIN` | 800 | the assassin's: 30 / 20 / 3, hp 80, hidden | none |
| `missionary` | `CK_DIPLOMAT` | 800 | the diplomat's: 0 / 15 / 2, hp 100, unarmed | `au_steady` 50 within 30 m; `parley_vs` native_warriors, native_bowmen, canoe_raiders, holcan, atlatl, w_slingers (not the maroons); `parley_bonus` 25: the parley is 85 % routing / 60 % wavering against them (60 / 35 otherwise) |
| `shaman` | `CK_FOOT` | 1,200 | 30 / 25, armour 0, hp 300, no `duel`, `nobreak` | `au_hit` 15, `au_mor` 3 within 40 m, `au_roles` skirmish, shock; `au_fear` 1, `au_fear_r` 30 m; `char_pct` 4; the Champion's fall numbers |

  The book names the shaman Ah Kin (Itza) and Sukia (Miskito) in its text; the row's name is "Shaman".
- **Campaign**: `CData.CHAR_NEEDS` sea captain Shipyard 1, privateer Market 2, missionary Market 1, shaman Barracks 1.
  `CData.CHAR_FACTIONS` lists who may raise the West's four (sea captain and privateer: England, France, the Dutch, the
  Brethren; missionary: New Spain, Tierra Firme, France; shaman: Itza, Miskito); `CChars.allowed(kind, f)` is true for a
  West kind only in the West pack for those factions, and for Rome's six only outside the West pack (so Rome's six
  never appear in the West and the West's four never in Rome); `CChars.recruit_check` refuses the rest with "not for
  your people". `CChars.KINDS` lists the ten (Rome's six first), `slot_of` maps sea captain and shaman to the hero slot,
  privateer to the assassin's, missionary to the diplomat's (one hero, one agent of each slot per army as before);
  `kinds_for(f)` is what the recruit page lists; `slot_name` shows "Privateer" / "Missionary" in the West.
- **The AI** (docs/AI.md 38): `_hero_kind_of(f, army)` in the West is a sea captain for the coast nations and the
  Brethren, a shaman for the natives, nothing for the Spanish; the Skilled diplomat raise is a missionary for the
  factions that may; privateers never; the build-up goal for heroes is the shaman's Barracks 1 (Rome's Barracks 2 is
  Rome only; the sea captain's Shipyard comes from the fleet AI).
- **View**: `Overlay.draw_char_glyph` takes the row's `glyph` (hat, knife, cross, feathers: four new `ui_icons.gd` icons) on
  the gold-rimmed disc; the unit cards' corner mark (`UnitTraits.char_icon`), the army card, the command bar and the
  recruit rows use the same glyphs; unit icons 35-38 in `unit_icons.gd`. The HUD's act chips follow the kind unchanged.
- **Book**: a page per row from the row's text; "Heroes and agents" for the West (`UnitBook.chars_help_west`) names the four
  and quotes their numbers, the missionary's parley as 60 / 35 plus 25 (85 / 60); `UnitTraits.char_text` knows `au_fear`,
  `parley_bonus`, `sea_cq` and the role filter.
- **Custom battle**: `CustomSetup.char_keys(setup)` is Rome's six or the West's four (`WEST_CHAR_KEYS`); `chars_of`,
  the cost against the funds and the setup screen's toggles follow it; switching the setting clears a side's characters.
- **Tests**: `tests/pack_test.gd` `_batch3` (the rows and numbers, indices, CHAR_NEEDS, the faction x kind table with every
  building at 3 and a level short, Rome refusing the four and allowing its six, the AI's hero kinds, the custom battle for
  both packs with prices and a built battle, 40 AI turns raising only sea captains / shamans); `tests/chars_test.gd` `west`
  (the real rows in the sim: the role filter on West units, the shaman's fear, the missionary's bonus turns native refusals
  into surrenders and changes no pike block's).

Choices where the plan was silent: the sea captain's `au_roles` name the marines by their row key
(their role is `line`); the missionary's order bonus is not built (no public order); the shaman's reach is 1126 (a
staff) against the Champion's 1331 and his damage 30; the AI gives every army of the coast nations a sea captain (it does not check that
the army fields skirmishers, shock troops or marines); the Spanish get no hero (they raised Rome's six before). Open: the
battle AI posts a `CK_FOOT` hero behind the line centre whatever his `au_roles` (docs/AI.md 27); the AI's parley pick
ignores `parley_bonus`; no probe battles yet (a shaman with the natives in `asym_field2`, a sea captain with the pirates on
a deck, a missionary against a wavering war party); the sets have only the melee pose (no pistol or staff poses).


### Batch 3 measured (2026-10-24)

Three probes with new scenario ids only (`asym_field2s`, `asym_woods2s`, `probe_parley`, `probe_parley0`, `probe_deck`,
`probe_deck0` in `sim/scenarios.gd`; `tests/asym_probe.gd` forwards `--scen` and now prints parley tries and prisoners);
no existing scenario or hash moved.

- **The shaman in the field.** `asym(woods, true)` plus Ah Kin with the natives, 48 seeds (seed0 16), Spanish /
  natives / draws: field 45 / 3 / 0 without him, 37 / 10 / 1 with him; woods 1 / 46 / 1 without, 1 / 47 / 0 with
  him. He narrows the field edge from 94 % to 77 % and does not flip it; in the woods he adds one win to a side that
  already takes 96 %.
- **The missionary against a wavering war party.** `probe_parley`: Spanish 120 pikes, 100 musketeers, 60 lancers
  (plus Fray Tomas) against 3 x 100 warriors and 2 x 80 bowmen, flat, both AI Average, 24 seeds. With him: Spanish
  20 / natives 4; natives surrendered in 20 of 24 battles (1,441 men, 36 parley tries, 28 succeeded, tries in 23
  battles). Without him (`probe_parley0`): Spanish 17 / natives 7, no surrender, no parley. The battle AI does send the
  missionary to parley (its rolls carry the bonus because `_ch_parley` applies `parley_bonus` to whatever target the AI picked; only the
  AI's choice of target ignores it, still an open item).
- **The sea captain.** Decks are the sea sim's own (`sim/sea_sim.gd`), which takes no `"chars"`, so `probe_deck` runs
  on flat open ground: Brethren (2 cutlass, 2 buccaneers, 1 boarding grenadiers: 2,260) against 2 marines and
  musketeers 100 + 90 (2,260), both AI, 24 seeds. Brethren / marines+shot / draws: 6 / 17 / 1 with Calico Jack, 7 /
  16 / 1 without. The captain's champion aura makes no measurable difference (his sea_cq only works at sea).

Reading against the asymmetry principle: the one character who moves the field is the shaman, and the
move is the right size (the Spanish keep a clear edge in the open, the natives keep the woods); the missionary is the
strongest piece measured, a campaign-scale prisoner machine rather than a battle-winner (+3 Spanish wins, 20 of 24
battles with prisoners); the sea captain is neutral in a land fight, as designed.

### The tribes' tier-2 rows (as built, 2026-11-02)

The owner, playing the natives: "Can we have level 2 warriors and canoe men and maroons for the tribes?" Three rows
appended after `WEST_LATE` as `WEST_TIERS2` in `sim/unit_types.gd` (derived by `_derived` from the tier-1 row named
by `of`, so no earlier index moves: `FORT_GUN` 90 and `ROME_N` 76 as before, `UT.TYPES` 111 -> 114; the equites
rows' trick, TIERS, cannot derive from West rows). They draw the tier-1 row's sprite set (23, 31, 38), keep its
ammunition, size, abilities and the Canoe Captains' `amphib`.

| Row | Name (short) | Of | Line | Attack / defence / armour / hp / morale / damage | Price | Needs |
|---|---|---|---|---|---|---|
| `native_warriors2` | War Band (War Band; "Itza War Band" / "Miskito War Band" by faction) | `native_warriors` 38 / 24 / 2 / 85 / 620 / 36 | `light`, slot 2 | 43 / 29 / 5 / 91 / 690 / 38 | 560 (400 x 140 %) | War lodge 2 |
| `canoe_raiders2` | Canoe Captains (Canoe Capt.) | `canoe_raiders` 38 / 24 / 2 / 85 / 620 / 34, javelin 42 | `canoe`, slot 2 | 43 / 29 / 5 / 91 / 690 / 36, javelin 45 (`m_damage` +3) | 288 (240 x 120 %) | War lodge 2 (`UNIT_NEEDS`; the raiders keep their Barracks 1) |
| `maroon_vets` | Cimarron Veterans (Cimarrons) | `maroons` 38 / 24 / 0 / 90 / 660 / 38, `m_reload` 200 | `maroon`, slot 2 | 43 / 29 / 3 / 96 / 730 / 40, `m_reload` 180 (-20) | 375 (300 x 125 %) | War lodge 2 |

Ratios: exactly the existing tier-2 rows' (`TIER_DELTA` 2: attack +5, defence +5, armour +3, hp +6, morale +70,
damage +2). The prices follow each arm's pair: warriors the light line's 140 % (`light2`), the canoe men the
javelinmen's 120 % with `javelin2`'s +3 `m_damage` (`TIER_PRICE` "canoe" 120), the maroons the musketeers' 125 % with
`musketeers2`'s -20 `m_reload` (`TIER_PRICE` "maroon" 125). Ammunition (the Miskito's poisoned arrows are a bowmen
rule, untouched), abilities and roles as tier 1. The holcan stay the Itza's separate heavy line (tier 2, War lodge 2,
360 a unit of 60): they are a picked heavy unit, not the Itza's warriors' veterans, and the Itza get War Band in the
light line's second slot beside them.

Rosters (`campaign/data/west.gd`): Itza `light` ["native_warriors", "native_warriors2", ""]; Miskito `light` the same,
`maroon` ["maroons", "maroon_vets", ""] (the Brethren's `maroon` stays ["maroons"]: "for the tribes" read as the tribes
only), and a new `canoe` line ["canoe_raiders", "canoe_raiders2", ""]. The canoe raiders sat in the Miskito's `light`
slot 2 already (tier 2 by name, a Barracks 1 by `UNIT_NEEDS`), so there was no slot for their veterans: the row's line
is now `canoe` (`CData.LINE_ORDER` after `light`, `LINE_CHAIN` Barracks) and the Miskito's mix splits `light` 39 into
`light` 28 and `canoe` 11 (the raiders were about the AI's 30 % specialist share of the line). The chain cap needs no
change: the Itza already build a War lodge 2 (holcan) and the Miskito one (torch raiders), so `CHAIN_CAP_FACTIONS`
stands. The AI raises them through `MIX_LIVE` and `_best_type` (best tier a centre allows) with no `cai.gd` change.

Measured (`campaign_sim`, West, 72 seeds x 60 turns, before = HEAD 5be2425, `tests/campaign_sim.gd` now also counts
the tribes' recruits):

| | format 6 before -> after | format 10 before -> after |
|---|---|---|
| eliminations (England / France / Dutch / Brethren / Itza / Miskito) | 4 / 0 / 5 / 16 / 9 / 6 -> 3 / 0 / 6 / 16 / 4 / 10 | 2 / 0 / 0 / 15 / 9 / 9 -> 0 / 2 / 1 / 22 / 8 / 5 |
| total | 40 -> 39 | 35 -> 38 |
| battles / field battles a seed | 60.6 / 6.0 -> 57.7 / 5.8 | 47.8 / 3.5 -> 48.5 / 3.5 |
| War Band raised (Itza / Miskito) | 8 / 7 | 33 / 58 |
| Canoe Captains / Cimarron Veterans raised (Miskito) | 3 / 1 | 30 / 9 |

The AI seldom reaches a War lodge 2 (Itza warriors 1,633 against 8 War Bands at format 6), so the rows are mostly the
player's; the eliminations swing both ways by seed (the rows change the unit keys, so every trajectory differs), no
single faction beyond what unrelated changes have moved it (Dutch 2 -> 7 once, the Brethren 22 of 72 here at format 10
against 15). No tuning round was run. Asymmetry probe (`tests/asym_probe.gd --tier2`: the natives' warriors and canoe
raiders swapped for the new rows, 48 seeds, seed0 16; the natives' army costs more): `asym_woods` natives 48 of 48
either way; `asym_field` Spanish / natives / draws 26 / 21 / 1 -> 20 / 27 / 1.

Pins: West format 6, 8 and 10 moved (Rome, ROME_20 and the AI goldens unchanged); no `CState.VERSION` bump; the rules
hash moves. Known: the AI rarely raises the rows (it seldom builds a War lodge 2); the Cimarron Veterans' numbers
follow the musketeers' pair, the maroons' own pace and woods traits untouched; the Canoe Captains are amphibious like
the raiders; the unit cards show the tier rows by name (a short "Canoe Capt.").

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
### Roles, step 1 (as built, 2026-10-23)

Data and view only: no sim rule reads a role, no hash moves. `sim/unit_types.gd`: the `role` key on every row of both
packs (tiers inherit their base row's; a tier row may state its own, as `warband`), `UT.role(ty)`, `UT.role_info(ty)`,
`UT.ROLES` (key -> name, short, glyph, colour, two-line "plays", filter group), `UT.ROLE_ORDER`, `UT.FILTER_GROUPS`,
`UT.filter_group(ty)`. The rows' former display text key `role` ("Line infantry") is now `what` (the unit entry's line).
`tests/roles_test.gd` asserts every row has a role in the table and prints the roster. The view is in `ui.md`
("Role badges ...").

Choices where the plan was silent or ambiguous: the plan lists "heavy swords" under `shock` and "Rome's swords" under
`line`; Rome's formed swordsmen (heavy, its tiers, principes, extraordinarii, scutarii, Gallic nobles) and light infantry
are `line` (they hold a front), the Gallic Warband `shock`. Missile infantry (`missile`) selects with Skirm. Camel archers
`horse_skirmish`; the camel riders and elephants `beast`; war dogs (handlers and the released pack) `shock`; the wagons
`command` (no better of the ten; they select with Line); Cuirassiers `horse_skirmish` (a tier of the pistoleers).

| Role | Rome | West |
| --- | --- | --- |
| line | heavy, heavy2, heavy3, principes, extraordinarii, scutarii, gallic_nobles, light, light2, light3, caetrati, spear, spear2, spear3, triarii, sacred_band, hoplites, picked_hoplites, pike, pike2, pike3, phalangites, silver_shields, chaonians | musketeers, musketeers2, w_pikemen, w_pikemen2 |
| skirmish | javelin, javelin2, javelin3, slinger, balearic, rhodians, iberian_slingers | buccaneers, native_bowmen, coureurs, canoe_raiders |
| missile | archer, archer2, archer3, cretans, gastraphetes | none |
| shock | warband, dog_handlers, war_dogs | rodeleros, cutlass, native_warriors, grenadiers, boarding_grenadiers, holcan |
| horse_shock | cav, cav2, cav3, equites, equites_extra, companions, agema, noble_cav, bodyguard | lancers |
| horse_skirmish | cav_jav, numidians, tarentines, gallic_horse, iberian_horse, camel_archer | pistoleers, cuirassiers, dragoons |
| guns_field | bolt, tower_bolt, scorpions | light_gun, field_gun, fort_gun |
| guns_siege | stone, tower_stone | heavy_gun, mortar |
| command | general, legate, sufet, hetairoi_guard, strategos, chieftain, hero_foot, hero_missile, hero_cav, hero_siege, assassin, diplomat, wagon, wagon2, wagon3 | none |
| beast | camel, elephant | none |

### Roles, step 2 (as built, 2026-10-23)

The behaviours of "Behaviours (step 2, sim)". Code: `sim/unit_types.gd` (`SKIRM_FILE_SP` / `SKIRM_RANK_SP`, `AB_*`,
`abilities()`, the rows' `pistols` and `grenades` keys), `sim/battle_sim.gd` (section "roles, step 2 (abilities)":
`_setup_roles`, `make_ability_order`, `ability_refusal`, `ability_state`, `_ability_order`, `_batter_now`,
`batter_pick`, `bld_tgt`, `ob_aim`, `_pistol`, `_pistol_pass`, `_gren_hold`, `_gren_block`, `_gren_gate`,
`_car_order`, `_caracole`, `_car_attack`, `_car_back`, `_car_halt`, `_skd_ok`, `_skd_places`; hooks in
`_apply_orders`, `order_units`, `_apply_unit`, `_order_rule` (the attack order's `"bld"`), `_compute_offsets`, `step`,
`_update_soldiers` (the two blow sites, the reload skip, `shy`), `_missile_think`, `_gate_volleys`, the attack
movement, `_charge_state`, `_gun_unit`, the battery's aim and fire (`_art_fire_at`), `state_hash`), `sim/battle_ai.gd`
(`_attack`), `sim/ai_profile.gd` (knobs 283-284, docs/AI.md 36), test `tests/roles_sim_test.gd`, probe
`tests/asym_probe.gd` with the scenarios `asym_woods` / `asym_field` (`Scenarios.asym`). No HUD work: the chips are
step 3, folded into the battle UI pass; Auto is every unit's default, so play is untouched without an order.

**The ability table.** `UT.abilities(ty)`: a bit per `AB_PISTOL` (rows with `pistols` > 0: buccaneers, coureurs,
pistoleers and the cuirassiers by inheritance, dragoons), `AB_GRENADE` (rows whose standard ammunition is the grenade:
grenadiers, boarding grenadiers; or a row with `grenades` > 0, the hook for the buccaneers later: no row sets it and
no sim rule reads its count yet), `AB_CARACOLE` (horse_skirmish rows of the cavalry class with a firearm: pistoleers,
cuirassiers, dragoons; Rome's light horse are missile-class skirmishers already and keep their rule), `AB_BATTER`
(guns_siege: stone throwers, heavy guns, mortars; a tower's engine refused). State per unit `u_abs` (2 bits an
ability: Auto 0, Hold 1, Use now 2) and `u_abt` (the Use now target), changed only by `ORDER_ABILITY` 28
(`make_ability_order(tick, unit, ability, state, target)`; through the lockstep like any unit order, the issuer must
command the unit; applied beside the gate orders, not through the order rules, so waypoints and the order preview
are untouched; Use now refused in the deployment phase). Hashed from the first ability order on (`ab_on`).

**Skirmish: loose order and cover drift.** Every `skirmish` row stands at least 1.8 m x 2.0 m (the javelinmen's; a
floor in `_build_types`): native bowmen (1.3 x 1.6 before) and Rome's slingers (1.6 x 1.8) open up, the rest had it.
Drift (`skd_on`: woods on the map and a skirmish unit; `u_skc` hashed): a skirmish unit in the Cover stance, standing
(no order, or shooting its attack target from where it stands), not in contact, on the ground, with no obstacle
cover spots of its own (`u_cvb`), is checked once a second; while it qualifies its places are laid out with every
place not in woods moved to the nearest free spot of a woods cell within `SKD_R` 8 m (a 4 m veg cell holds four, 1 m
off its middle each way; places in slot order, spots nearest first). A unit that stops qualifying lays its places
out again. An AI side drifts only with `R_SK_DRIFT`. `line` keeps today's partial cover (no change).

**Pistols at contact** (`pis_on`; per man `s_pis` loaded, `s_prl` reloading until; `u_pptr` per unit; hashed). Every
man of a pistol unit starts with his brace (2). In a melee, while he has a pistol loaded and is not reloading, his
blow (both blow sites of the contact path) is a pistol shot instead: `PIS_HIT` 70 % (no to-hit roll, no shield),
`PIS_DMG` 90 less half the armour (x 85-115 %), `PIS_MOR` 4 morale off the struck man's unit hit or miss; so his
first two melee rounds are pistols, then the blade. The rotation (`_pistol_pass`, each unit every `PIS_THINK` 10
ticks): a front-rank man fighting with both spent changes slots with the next loaded, formed, untargeted man of the
rear ranks (`u_pptr` round them) and reloads for `PIS_RELOAD` 300 ticks; a stepped-back reloading man takes a target
only within his reach; a spent man not fighting reloads where he stands; out of the fight a part-spent brace is
topped up; with no loaded man behind he fights on with the blade. Hold: blades only, no rotation. Pistol shots are
separate from the unit's missile ammunition (the buccaneers' muskets, the pistoleers' ranged brace). Measured
(`roles_sim_test` pistols: 60 buccaneers without rounds against 100 musketeers, 120 s): 63 shots, 41 hits, 29
kills, 29 changes of place, 32 braces reloaded.

**Grenades.** Auto (the batch 1 missile path as the trigger): fire at will throws only at a "formed block"
(`_gren_block`: a ready unit of `GREN_BLOCK` 30 men or more, not disordered, not horse) or a unit holding a building;
an attack order's target is thrown at as before; standing with nothing to throw at, attackers take the nearest shut
gate in reach and in a clear throw as their target (`_gren_gate`, then `_gate_volleys`). Hold: nothing thrown, and the
unit fights as shock foot (not "shy" in a melee; an attack order closes to contact). Use now with a target: an attack
order at that unit (or gate `-2 - g`), thrown whatever its size. Measured (60 grenadiers 15 m from musketeers, 30 s):
Auto at 100 men 10 thrown, Hold 0, Auto at 20 men 0, Use now at the 20 men 7.

**Caracole** (`car_on`; `u_car` phase, `u_crt` target, `u_crk` phase tick, `u_crv` last volley; hashed). An attack
order on a unit by a caracole rider (not `"charge": 1`, the ability not on Hold) is a caracole: (1) the riders close
to `CAR_STOP_PCT` 75 % of their range from the target (the missile stand-off of the attack movement; no charge starts
while closing) and fire their volley (riders fire on the move: `_gun_unit` marks `u_crv`); (2) after it, or at
contact, they ride back at the run to `CAR_BACK` 40 m beyond their depth from the target, at most `CAR_RETIRE_T` 20 s;
(3) back, facing it, pistol riders (range <= 30 m) reload their brace over `CAR_RELOAD` 30 s (the missile rounds back
to the row's), musket riders wait for their volley's reload; at least `CAR_WAIT_MIN` 3 s; then the next pass. A target
that routs or is locked in a melee with ours is charged (the attack goes on; the riders fall on an engaged flank or
run down the broken); caught in contact while back, they fight; muskets spent, they stand. Another attack on the same
target while riding back or reloading changes nothing (the AI re-orders every second); any other order but run, fire,
skirmish, ammunition and stance ends it. Hold: the attack is a charge, as before; Use now with a target: a caracole at
it. Measured (60 pistoleers against 100 musketeers without rounds, 240 s): six passes, volley at 23 m, back to 54 m,
no charge; on Hold a charge.

**Batter.** Use now on a guns_siege battery of the attackers: target -1 the stretch `batter_pick` gives (the
destruction AI's `SiegeAI._batter_stretch` by the shut gate nearest the battery, else the nearest standing stretch not
facing the sea), a stretch index, or a building `-2 - b`. A stretch is the existing wall attack order (`"wall"`); a
building is the new `"bld"` key of the attack order (`u_gtarget` = `BLD_TGT` -100,000 - building; aim point `ob_aim`,
the middle of its cells; the battery turns to it, `_art_fire_at` shoots it until it falls, `stat_bld_shots`). Hold
stops a battering under way (men again); Auto is today's (men, or what it was ordered at). Field guns have no batter.
Measured (siege_test 32, walls 1, stone throwers): the stretch picked breached in 6 shots; a house 193 m off fell in 7.

**Asymmetry probe** (`asym_woods` / `asym_field`: Spanish musketeers x 2, pikemen, rodeleros, lancers, 2,940, side 0;
natives warriors x 3, bowmen x 2, canoe raiders x 3, holcan, 2,920; both AI Average; 400 x 400 m; woods a band from
60 m to 300 m with dense patches, the natives in it), side-0 (Spanish) wins of 16 seeds, HEAD -> step 2: woods 0 -> 0
(natives win all), field 14 -> 11 (one draw). No pistol, grenade or caracole unit is in either army, so the field's
change is the bowmen's loose order (fewer struck by a volley: a native favour the principle does not ask for in the
open; within the noise of 16 seeds, but the direction is noted); the AI's skirmishers in these battles never stood
still in the Cover stance long enough to drift (`stat_skd_men` 0: the AI keeps them moving).

**Harness** (`tools/balance`, attacker wins %, HEAD `9a48e65d64` -> `051401e46c`; no cell beyond its interval):
rome_walls (16 seeds) pooled walls 1 / 2 / 3: 74 -> 74, 44 -> 41, 20 -> 19 (Sicilia walls 2 75 -> 56 the largest
cell); west_named (16) walls 0 / 1 / 2: 49 -> 54, 36 -> 33, 14 -> 12 (Cartagena and Veracruz walls 1 -25, Havana walls
0 and Port Royal walls 1 +19); open_town (8, walls 0, Average): Santo Domingo 100 -> 100, Havana 25 -> 12, Cartagena
100 -> 88. Determinism: the flat goldens and every open-field run unmoved; 15 run hashes moved (woods and towns with
skirmishers or pistol units: test_woods, ai_woods~as, the siege@ai runs, siege_eq_ring3, siege_eq_polis2~sa; not pinned
constants); lockstep hashes and the campaign_sim pins unmoved (the campaign never runs the sim; it reads the rows).

**Choices where the plan was silent.** Pistols are a brace separate from missile ammunition; pistoleers, cuirassiers
and dragoons got the brace too (the plan named "pistoleers, dragoons" for pistols; the brief adds cuirassiers). The
caracole is for cavalry-class riders only (Rome's horse javelins already skirmish as missile troops); its own volley
uses the unit's missile weapon; pistol riders reload it on the way back. Charging stays an order: the attack order's
`"charge": 1` (or Hold) until the HUD's chips. Grenades' Auto "formed block" is 30 men; the attack order is still
honoured on Auto (the player's explicit choice); Hold makes grenadiers shock foot. The batter order reuses the
destruction AI's stretch choice; buildings needed their own target (no AI uses it). The drift radius is 8 m ("a few
metres": 6 m left a front rank 7 m from a wood's cells out). No unit stat was changed for the probe.

#### The countermarch (as built, 2026-10-27)

docs/AI.md 44.2. Ability `UT.AB_ROLL` ("Countermarch") on the West gun foot rows that stand in a line (`m_gun`,
missile class, foot, a man a weapon, not a skirmish row: musketeers and their tier, marines, colonial militia; not
the buccaneers, coureurs or maroons, not riders, guns or any Rome row). Auto / Hold / Use now through
`ORDER_ABILITY` as the others; Use now takes no target. Code: `sim/battle_sim.gd` `_setup_cm`, `_cm_rolls`,
`_cm_unit`, hooks in `_gun_unit` and `_missile_hit`. State (`cm_on`: a unit with the ability in the battle; sized and
hashed only then, so Rome battles hash as before; snapshot-covered as script variables): per unit `u_cmc` a reload
clock (counts as `u_fire_acc` does, full speed standing, half on the move, uncapped), `u_cmr` the rank pointer,
`u_cmt` the clock of its next rank volley, `u_cml` the clock of the line's last shot, `u_cmv` the tick of its last
rank volley; per man `s_cms` the clock at his last shot (loaded `m_reload` after it). Not on Hold (and on an AI side
only with `CM_AUTO`), with a fire target and standing: fire at will's held volley applies to every volley; a **full
volley** of every loaded man (formed, a charge, loaded) when the line has stood loaded a full reload (its last shot
two reloads ago: the opening volley) or, on Auto, when the target is within `CM_CLOSE` 40 m or the unit is in a melee
(the last volley); after it the drill restarts from the front rank one reload on. Else the rank `u_cmr` (slots `s /
files`, files as the formation stands) fires its loaded men when the clock reaches `u_cmt`, and the next rank comes
`ceil(m_reload / ranks)` later: each man fires once a reload, a cycle of the ranks the shots of a volley. A rank
volley frightens its target once (`u_vf_u` / `u_vf_t` as a volley) at `CM_FEAR_PCT` 50 % of `m_fear` (riders' +50 %
first). Hold: the volleys as before (they also stamp `s_cms`, so a switch back to Auto does not fire men just fired).
Per-man fire (`_pm_on`: in a building, on a wall, the Cover or Hold-street stance of cover troops) runs before
`_gun_unit` and is untouched. Stats: `stat_cm_rank`, `stat_cm_full`, `stat_cm_fright`. Tests:
`tests/roles_sim_test.gd --only=countermarch`. Since 2026-11-02 the men change places as they fire ("The
countermarch (as built, 2026-11-02)" below).

#### The countermarch (as built, 2026-11-02)

The owner, from a phone playtest: "The rotating linemen don't actually rotate, just the shots move down the rows one
at a time. The soldiers should swap positions in the unit to fire." Diagnosis: the 2026-10-27 drill moved a rank
pointer (`u_cmr`) down the slots and fired that rank's men where they stood, so a musket line stood still while its
fire walked through the ranks. Rule: the men walk, the drill's clock does not change. Each rank volley is now fired
by the front rank; after it, in every file whose front man fired, he files to the rear of his file and the men behind
him step up a rank (`_cm_file_back`: `slot_soldier` / `slot_of` along the file; the last, partial rank is centred, so
its man nearest the file's line closes that file). Moving the fired man to the rear of his own file is the cheaper of
the two ways the slot machinery offers and reads better than the loaded rank pushing up through the gaps: one slot
cycle per file, the rest of the file only steps a rank forward, and a man fires once a reload because a file of
`ranks` men brings him back to the front after `ranks` volleys of `ceil(m_reload / ranks)` (a shorter file beside a
partial rank: its front man is not yet loaded at his turn, so he does not fire and that file waits a turn, which is
exactly the partial rank's share of today's cycle). The walk itself (`s_rtw` per man, `_rt_goal`): he turns about,
side-steps half a file spacing into the gap to his file's right, walks straight back down it at the walk (never the
catch-up run) until level with his new place (`CM_BACK_DONE` 0.3 m, `CM_GAP_TOL` 0.1 m), then steps into it; the men
stepping up walk straight forward in their file. The unit's anchor, facing and box do not move. It walks only while
`_cm_walks`: formed and standing on the ground of a field battle (not a settlement battle: there a town's houses
decide whose shots are blocked, and the front rank always firing made buccaneers at a street mouth lose 17 % more
against a line in the plaza, 106 -> 124 men over 16 seeds, the street-cover pin of `determinism_test`; so in towns
the line fires by ranks where it stands, as before), not within 4 m of a rock or cliff, at least two ranks deep, not in contact or fighting, not a
bound's holding team, not on a wall, a stair, a ladder or in a building, its places its formation's rectangle (not
flowed into a street, squeezed, in cover or drifting into trees); otherwise the pointer fires the rank where it stands
as before. Full volleys (the opening one, the last one within `CM_CLOSE` or in a melee) and Hold never walk; a unit
on the move does not fire by ranks at all. A shot landing on a line whose men walked in the last `CM_WALK_T` (8 s,
`u_cmk`) is resolved against the man nearest the landing point instead of the slot under it (`_land`; a walking man is off
his slot, so the slot lookup missed him and the walking line was harder to hit). The pistols' change of places at
contact (`_pistol_pass`) uses the same walk: the spent man goes back down the gap beside his file (in the contact
path's slot following), the loaded man steps up; in towns as in the field (the buccaneers' and pistoleers' fights at a
breach or a gate: `tools/balance` west_walls walls 0 / 1 / 2 52 / 33 / 30 -> 52 / 44 / 27, San Juan walls 1 12 -> 62
beyond its interval; with this walk off the walls-1 plan reads 33 and San Juan 12 again, so it is the pistols' walk:
the spent man side-steps out of the front before he walks back, rather than straight through the man coming up;
west_named pooled 59 / 30 / 14 -> 57 / 39 / 9 with no cell beyond its interval, open_town 75 -> 79). Riders' caracole is a unit-level ride and is untouched; bows and
slings have no countermarch (they shoot over the ranks). State: `s_rtw` (sized with `cm_on` or `pis_on`), hashed from
the first walking man on (`rt_on`), snapshot-covered as a script variable; `stat_cm_files` counts the walks. No AI
decision changes (the drill's cadence is the same), so no knob. Measured (`tests/cm_probe.gd`, 100 musketeers in 4
ranks shooting a 900-man pike block 70 m off for two minutes): shots a minute 500 / 500 before and after, 98 men 490 /
490, 90 men 450 / 450 (identical cadence), kills a minute 205 / 195 -> 220 / 211 (100 men), 206 / 206 -> 207 / 194
(98), 202 / 171 -> 193 / 174 (90): within the noise of where the balls land; a Hold line shooting a walking line
(8 seeds, 60 s, 100 against 100): 437 -> 430 kills; the closest two men of the walking line 0.59 m; the box's middle
and width unchanged. Tests: `tests/roles_sim_test.gd --only=countermarch` (every man stands in the front rank at one
of the first five rank volleys; a walking man keeps 0.4 m from every man of his line; the footprint and facing stay
put; nobody walks on Hold, on the move or in the melee of the rodeleros' charge), `--only=pistols` (the stepped-back
man walks). Shots: `tests/cm_probe.gd --png=DIR`.

#### The charge with the butt (as built, 2026-10-29)

docs/AI.md 44.6 (the Swedish salvo, Skilled). An attack order with `"butt"` 1 on a countermarch row (a West line
musketeer) closes it to contact and it fights as shock foot (not shy in a melee, as grenades held) while that attack
order lasts; any other order but run, fire, skirmish, ammunition or stance ends it (`_butt_order` after each unit
order, `_butt`; the two hooks are the attack's "shoot it: close to most of the range" branch and the melee's `shy`).
State: `u_butt` per unit, sized with `cm_on`, hashed from the first such order (`butt_on`), so every battle without
one hashes as before; snapshot-covered as script variables. No player order carries it yet (no chip): the AI's only.

### Native siege: the torch raiders (as built, 2026-10-29)

docs/design/campaign_rules.md "Native siege, and the natives' buildings (plan)". One row after the shaman, the last
of `UnitTypes.WEST_LATE` (every earlier index unchanged; `pack_test _native_siege`), sprite set 45 (art_pipeline.md
"The torch raiders' set"). The sim rules (the melee batter, the fire pots, the scaling poles):
docs/design/siege_and_towns.md "Native siege: scaling poles and the melee batter (as built)".

| Row (key) | Line, role | Buildings (`UNIT_NEEDS`) | Who | Men, cost | Melee | Missile |
|---|---|---|---|---|---|---|
| Torch Raiders (`torch_raiders`; the Miskito's "Torch Raiders" / "Torches") | `siege` (tier 1, in place of the wagon), `shock` | Barracks 2 (the War lodge) | Miskito | 60, 7 (420) | cls missile (the throw runs for missile class, as the grenadiers); attack 34, defence 20 (native warriors 38 / 24), damage 32 (36), armour 0, shield 0, hp 85, morale 600 (620), the warriors' walk 1.75 / run 4.7 m/s, `cover`, `woods_pct` 60; `batter` 1: the batter ability's melee form, `m_obj` 120 a blow at a gate, 80 at a palisade stretch | fire pots (`m_ak` 7, `fire_pots`: lobbed `m_kind` 2, fire 70, 55 % against men), 2 a man, 25 m x the kind's 90 % = 22.5 m, damage 100, reload 12 s, `m_fear` 40, `grenades` 1: the grenade ability (Auto: held houses and shut gates only) |

**Derivations.** The plan: "60 light shock foot with axes and torches, speed as warriors, poor in the open (melee
below warriors, no armour)": attack, defence and damage a step under the warriors' (-4 / -4 / -4), their pace, no
armour or shield. Price "about a warriors' company": 7 a man x 60 = 420 (warriors 400). Range: the plan's 20 m left a
held house out of reach (`range_vs` from below its windows: the set piece stopped at 19 m and never threw); 25 m, the
grenadiers' row, gives about 20 m at a house. The `batter` field is new (DEFAULTS 0); `abilities` gives `AB_BATTER`
for it as for `guns_siege`. Campaign: the Miskito's `siege` line (they keep no wagon: they forage), their mix `siege` 5.

### Amphibious units and the sea gate (as built, 2026-10-31)

The native siege's later entries (docs/STATUS.md "Native siege"): the harbour assault (canoe raiders landing at the
quay inside a port's walls) and the lake of Tayasal (the Itza's home defence by canoe). The row trait `amphib` (the
canoe raiders; campaign_rules.md "Amphibious armies") now also counts in the battle sim. Code: `sim/battle_sim.gd`
section "amphibious units, the sea gate" (`amph_on`, `NAV_WATER`, `AMPHIB_PCT`, `_amph_carve`, `_setup_amph`,
`reach_u`, `_update_wet`, `afloat`, `_build_aw`, `_plan_path_amph`, `_route_amph`) and its hooks (`_nav_of`,
`_ground_mask`, `_plan_path`, `route_to`, `unreach_goal`, `reach_snap`, the order rule's gate branch, `_siege_gate`,
`place_rule`, the anchor's pace, `_update_missiles`, `_pm_unit`, the missile attack's closing); the AI: docs/AI.md 50;
the scenarios `west_harbour_assault` and `tayasal` (`sim/scenarios.gd` `harbour_assault`, `tayasal`).

- **When.** `amph_on` is 1 for a battle with a unit whose row has `amphib` 1 on a map with water (`C_WATER`: the sea of
  a coastal settlement, a West port's harbour, a river); off, nothing below happens and every battle hashes as before
  (the tutorial_native village has no water: unchanged). Static, from the scenario.
- **Water is ground for amphibious units.** With `amph_on`, `C_WATER` cells carry `NAV_WATER` (32) and an amphibious
  unit's ground mask (`_ground_mask`, so every man step, slot flow, line check and open-point search) includes it;
  other units never enter water (their masks are unchanged, an order onto water snaps to their own ground as before).
  The river's channel is the same kind of cell, so canoes cross rivers anywhere too.
- **Afloat.** `_update_wet` (once a tick after the men moved, after the ford) cuts the step of each amphibious man on
  water to `AMPHIB_PCT` 60 % (a cut step that would end where he may not stand leaves him where he was) and counts
  them in `u_wet` (per unit, hashed while `amph_on`; captured by `snapshot()` as every script variable). A unit with
  most of its men on water is `afloat`: its anchor keeps to 60 % of its pace, it gives no volleys, and on an attack
  order a missile unit does not stop at its range on the water but closes to land (then shoots). A man on water never
  shoots and his reload waits (`_pm_unit`), cannot strike or be struck in melee (`_reach_ok` wants ground under both
  men) and is shot at as a man in the open (no cover on water). Measured (tests/harbour_test.gd): 18 m afloat
  against 30 m ashore in 20 s (62 %).
- **The sea gate is a water passage.** `MapGen._harbour` draws a sea gate in the longest stretch of a coastal plan's
  sea wall (the Rome plans and the natives' oppidum; the West's walled plan at walls 3, which is one of them). With
  `amph_on`, `_amph_carve` (setup, before the passability) turns the sea wall's cells within `GATE_HW` - 1 m of the
  gate's line, from the wall's inner face out to the water, into `C_WATER`: an 8 m channel. Only amphibious units use
  it, from the water onto the quay (the ring road inside) and back; it is no gate object, so it cannot be shut,
  battered or burnt, and shots pass through it as through any opening. `harb` keeps its outside point (8 m beyond the
  water's edge), its inside point (8 m inside the inner face) and the gate's middle (static, rebuilt by setup). The
  mole stays scenery. A West open town (walls 0-2) has no sea wall: its quay is open water already, so a canoe lands
  on it anywhere (nothing added).
- **Reach.** The pieces of ground (`cmp`) do not change. `_setup_amph` floods the water bodies (`a_body`) and records
  the pieces each touches (`a_bp0`, `a_up`); `reach_u(u, x, y)` is `reach_at` for every unit but an amphibious one,
  for which the pieces a water body touches are one (with the gates as they are: `_aroots`, a pure cache by
  `nav_epoch`). The order rule's move snap (`reach_snap(..., u)`), `unreach_goal` and the stuck watchdog's "no way
  there any more" read `reach_u`, so a raider ordered from outside the walls to the quay goes by water instead of to a
  shut gate.
- **Paths.** The street graph is unchanged. `_build_aw` (setup) makes the amphibious graph: the street graph's nodes
  and edges, then water nodes every 8 cells (16 m) on water at least 4 m and at most 70 m from land, then the sea
  gate's three points; each new node is joined to every node before it within 40 m with a clear 3 m way over ground or
  water, a paddled edge costing 100 / 60 of its length. An amphibious unit plans on it (`_plan_path_amph`,
  `route_to` with a mask carrying `NAV_WATER`); its distance tables are built when wanted (no per-tick budget, so the
  cache `_adist` is not state). The harbour assault's map: 119 street nodes, 271 in all, 2,886 edges; set-up 370 ms
  (as without).
- **Landing and unbarring.** An amphibious unit landed inside the walls may unbar a shut outer gate as ladder men do
  (the order rule sends it to the gate's inside face; `_siege_gate`, now also run with `amph_on` and no siege gear,
  counts its men there: `UNBAR_MEN` 4 for `UNBAR_TICKS` 15 s); `g_unbar` is hashed with `amph_on` as with siege gear.
- **Deployment.** An amphibious unit may be placed on water cells of its side's zone (`place_rule`: water passes where
  other units need open ground of a piece); a zone without water leaves it ashore. The scenarios place theirs: the
  harbour assault's raiders start afloat off the left shore.
- **The view.** Nothing new: men on water draw as men anywhere (the sea is ground drawn under the soldiers in both
  views; screenshots: men afloat upright on the sea in the oblique view); the paths hatch shows the channel open.
  The passage is drawn (view only, from `sim.harb`): the top view paints it as water over the wall strip, from the
  wall's inner face out to the sea, with the wall's two cut ends as dark edges (`CityDraw.draw_sea_passage`, called by
  `battlekit.gd`'s `_RubbleDraw._draw` and the Low path's `_LowDraw._draw` where the rubble is drawn); the oblique
  wall mesh is cut there like a gate's opening, with end caps (`battlekit.gd` `_ob_walls`, a cut from `sim.harb`),
  between the sea gate's two towers. The kit has no water-gate piece: two wall ends with the water between.
- **The open quay.** A West open town on the sea (no sea gate) gets a quay landing (`_find_quay`, static, setup
  under `amph_on`: `quay`): the open cell beside the water inside the town on the plaza's ground nearest the plaza,
  at least `QUAY_FORT_R` 60 m beyond the harbour fort's bastions, moved `QUAY_IN` 12 m inland; and on such a map
  the amphibious graph's paddled edges within 60 m of the fort's bastions cost `QUAY_FORT_PCT` 400 %, so canoes go
  round the fort's fire where the water allows (the AI: docs/AI.md 50).

Open: a landing into a
breach or onto the mole is not modelled; routers afloat follow no flow field over water (they head for their edge).

### A fleet at the shore (design and cost, 2026-11-05; built the same day: "A fleet at the shore (as built, 2026-11-05)" below)

The third choice at a contested landing (campaign_rules.md "The defender's choice at a landing: fight at sea, stand
off, support the shore"): the fleet's ships lie off the coast in the land battle for the region, their guns firing as
shore batteries and their crews landing by boat. The brief built it only if it reused the harbour assault's amphibious
machinery ("Amphibious units and the sea gate (as built)"); it does not, so it stopped after the stand-off. What the
sim and the campaign have today, read for this:

- **No boats in the land sim.** The harbour assault's canoes are men: an amphibious unit's men stand on `C_WATER`
  cells at 60 % pace and are drawn as men anywhere (the session scratchpad `shore/harbour_boats_top.png` and
  `harbour_boats_oblique.png`: the Miskito raiders upright on the sea off the quay, no hull). There is no ship entity,
  no fixed-position unit, no hull on the water to aim at, and no ship sprite in either battle view (the sea battle's
  hulls live in `sim/sea_sim.gd` and `game/sea_battle.gd`, a different sim).
- **Only port towns' battles have the sea.** A settlement battle of a coastal region (`CBattle.city_dict` `coast` 1)
  has the sea, the shore and (an open West town) the quay (`_find_quay`, `sea_on`); a field battle
  (`CBattle._build0`, non-settlement) has no water at all, so the "field battle on the beach" has no coast to put a
  ship on.
- **No land battle the turn of the landing.** The troops land and may march next turn; the land battle for the region
  is next turn's siege, assault or interception (or later). A supporting fleet must keep its choice across the turn
  (a fleet key such as `sh` [region, the turn], dropped when it sails or the region's battle is resolved).
- **The landing party has no men of its own.** A defender's docked fleet usually carries no troops (the sea sim's deck
  troops are the armies aboard, `CSeaBattle.build`'s `share = men x cap / capacity`); its men are the ships' crews
  (frigate 200, sloop 60, piragua 60, war canoe 40), which the campaign keeps as a crew % per ship.

The design, if the owner wants it built (settlement battles of port towns only in a first cut):

1. **A ship battery unit** (sim, new): a row trait `ship` on a fixed unit placed on water cells off the quay or the
   shore by the side's zone (`place_rule`: water as for `amphib`), which never moves (the order rule and both AIs
   refuse moves; its anchor is fixed), shooting with the landed naval guns' numbers (shot 400, range 450 m, reload
   48 s) a gun pair per 8 of the hull's `guns` (frigate 30 -> 4 guns, sloop 8 -> 1, the canoes 0-2 -> none, so a
   native fleet supports only by landing), under the artillery scan and the player's attack orders; its "men" the gun
   crews (4 a gun); silenced when they are down, which the campaign reads as hull and crew damage. Hashed state: the
   unit as any unit; no new arrays beyond a trait. About 300-500 lines in `sim/battle_sim.gd` (placement, the fixed
   anchor, the line of fire from the water, the AI scans), with determinism, lockstep and snapshot checks.
2. **The Land order**: a lockstep order on the ship that releases its landing party, a reserve unit built with the
   battle (`CBattle._settlement_reserves` already holds reserves that arrive mid-battle), amphibious, entering at the
   ship's cell and paddling to the quay as the harbour raiders do: European crews as marines (`marines` row, 80 a
   unit; the men a quarter of the crew, frigate 50, sloop 15, so three ships make one unit), native crews as canoe
   raiders (`canoe_raiders`, a piragua 15, a war canoe 10). New: the order, the reserve's entry point on water, the
   button on the ship's card. About 150 lines sim + 100 view.
3. **The view**: a ship sprite on the water in both views (the sea battle's hull sprites scaled to the land map), the
   batteries' range ring, the Land button. About 200-300 lines and an art check.
4. **The campaign**: the choice as the outcome mode "support" (the landing goes ahead as in the stand-off, the fleets
   keep their place in the port with `sh`); `CBattle.build` adds each supporting fleet's batteries and parties to its
   side of the next settlement battle of the region; `outcome_from_result` maps the battery's and the party's losses
   back to the ship's crew and hull; the auto-resolve formula a modest term (each supporting ship's guns x a weight
   fitted from 8-seed probes, capped at 10 % of the side's strength); the report "Your fleet at X supported the
   shore: N men landed, M lost, the guns fired". The attacker's transports alike (the AI by a knob). About 300 lines
   and campaign_test checks; the pins move (the AI uses it).

Cost in all: about two to three agent days, the larger part in the sim and the view (a new unit kind and a hull on the
water are exactly the pieces the amphibious machinery lacks), then the measure (a town battle with a frigate and two
sloops, and a native piragua and two war canoes, against an AI landing of 8-12 units) and the campaign runs. A smaller
alternative: no ships on the map, the support as campaign-only effects (the guns as a bombardment of the besiegers
before the battle, like the siege's attrition, and the crews as a garrison unit for the battle, raised from the
crews and paid back after it): a day, no sim change, but nothing to see or command in the battle.

### A fleet at the shore (as built, 2026-11-05)

The owner: "let's do the full build of the shore and landing." Built as the design above, the sim part here (the campaign
part: campaign_rules.md "Support the shore (as built, 2026-11-05)"; the AI: docs/AI.md 62 and 62; the ship on the board:
art_pipeline.md "(2026-11-05) The ship on the board"). The amphibious machinery carried it: a hull is a fixed unit on
water cells (the tower engines' `fixed` rule, standing on water by the amphibious units' ground mask), and its landing
party is an amphibious unit held off the field like a reinforcement until its order.

- **Rows** (`sim/unit_types.gd` `SHIP_ROWS`, appended after every other row: no index moves; `UT.SHIP_GUNS`,
  `SHIP_BOAT`, `SHIP_MARINES`; new row field `ship`). `ship_guns` ("Ship's Broadside"): fixed artillery, the landed naval
  guns' numbers (shot 400, AP 100, range 450 m, minimum 30 m, reload 48 s, `m_obj` 550), four men a gun (two to work
  it), 20 shots a gun, `e_hp` 1200, cost 0. `ship_boat` ("Ship's Hands"): a fixed hull with no guns (her hands, 4).
  `ship_marines` ("Landing Party"): the marines' row, amphibious. A native crew lands as canoe raiders (their row).
- **The scenario's "ships"** (`Scenarios.ship_entry`: side, campaign ship key, the gun pairs `(guns x hull % + 4) / 8`
  (frigate 30 -> 4, sloop 8 -> 1, war canoe 2 / piragua 1 -> 0), `men` the landing party (25 % of the crew aboard:
  frigate 50, sloop 15, piragua 15, war canoe 10), `ptype` its row, `hands` 4, `len` / `beam` from the sea sim's row,
  optional `ctl` (the controller) and `f` (the view's colours)). `BattleSim._ship_units` (setup, after the map) puts
  each on the water: cells 4 m beyond the hull's half beam from the land and at most 70 m out (`SHIP_SHORE_M`,
  `SHIP_FAR_M`), the hull inside the map, 8 m clear of the other hulls end to end, nearest its side's point: the
  defenders' landing (the West open town's quay, else the sea gate's outside, else the plaza), the attackers' the end of
  the shore away from the harbour fort (else from the quay); the keel along the shore, the battery facing the land; at
  most 12 ships (`SHIP_MAX`). A map without water (`amph_on` off, a field battle) takes none: `shp_none`, result
  `ships_none`. The party is set up 6 m beyond the hull's side toward the land, aboard (`_to_reserve`).
- **The hull** never moves (the order rule lets a fixed unit only attack, halt, fire, ammunition; both AIs leave it),
  its men stand on the water (`_ground_mask` adds `NAV_WATER` for a `ship` row), out of every melee (`_reach_ok` wants
  ground under both men); the order rule refuses an attack order at a hull from a unit with nothing to shoot, and the
  field and siege AIs' nearest-enemy and storm picks skip hulls. Its guns fire under the artillery rules (fire at will,
  the attack order, the line of fire with the hull's half length skipped at both ends, `u_trad`). A shot aimed at a hull
  landing on it (within its half length) strikes the working gun nearest its fall (`_ship_gun_hit`, the tower's
  `TOWER_BOLT_DMG` / `TOWER_STONE_DMG` x the shot's `m_obj`: three naval-gun or six fort-gun hits silence a gun); every
  gun wrecked, the hull is out of the fight with her gun crews (`_tower_fall`). Her gunners can be shot.
- **ORDER_LAND** (29, `ORDER_LAST`; unit: the hull; a lockstep input as any unit order: only its commander's is
  applied, `Lockstep._sim_order`): `land_refusal` (shared with the Land chip: not a ship, no party, ashore already, out
  of the fight, the deployment) or `_ship_land`: the party arrives formed beside the hull (the reinforcement's `_arrive`,
  the side's reserve clock left alone) and is given a move at the run to its landing (`sh_lx` / `sh_ly`: the defenders'
  quay or sea-gate inside, the attackers' the open ground nearest the hull 8 m inland); paddling at `AMPHIB_PCT` it
  lands and is a unit like any other. A party aboard is no reserve (`held_party`: out of `reserves_left`, the arrival
  rule and the AI's strength).
- **State and hash.** Static: `shp_on`, `sh_side`, `sh_unit`, `sh_party`, `sh_x` / `sh_y` / `sh_head`, `sh_len` /
  `sh_beam`, `sh_key`, `sh_ctl`, `sh_src`, `sh_lx` / `sh_ly`; state (hashed while `shp_on`, captured by snapshot):
  `sh_land`, `sh_shots`, `sh_idle` (the AI's memory), `u_ship`. A battle without ships hashes as before (the units'
  kill table keeps its width unless a ship row fights: `kty_n`). `result()` "ships": per ship her scenario index
  (`src`), side, key, guns, gunners and their losses, kills, shots, the gun deck's hits (% of its hit points), silenced,
  the men landed, killed and their kills.
- **Lockstep** (`sim/lockstep.gd`): a hull's and its party's commander is the ship's `ctl` (CBattle: the human of her
  fleet's faction, else the lowest human of her side friendly to it, else -1), or the player of her side's first
  scenario unit when none is given. lockstep_test "--only=shore": two peers sharing the defenders, the Land of the
  frigate by its player, a sloop's from the other player refused alike, 1300 frames equal, a third peer restored mid-paddle
  equal; determinism_test "--only=shore"; tests/shore_test.gd.

**Measured** (tests/shore_probe.gd: `Scenarios.shore_battle`, west_port's map at walls 1, the West attackers' ten
companies (about 750 men) landed and marching on the garrison WEST_DEF (nine companies, about 560), both sides Average,
seeds 8100-8107, the 15-minute limit; the fleets: navy a frigate and two sloops, native a piragua and two war canoes):

| Fleets (defenders / attackers) | Attacker wins | Defenders' guns: shots, kills | Attackers' guns: shots, kills | Defenders' parties: landed, lost, their kills | Attackers' parties: landed, lost, their kills | Guns silenced (def / att ships) |
|---|---|---|---|---|---|---|
| none / none | 7 of 8 | - | - | - | - | - |
| navy / none | 5 of 8 | 1, 5 | - | 640, 190, 329 | - | 0 |
| native / none | 6 of 8 | (no guns) | - | 280, 125, 11 | - | - |
| none / navy | 8 of 8 | - | 65, 108 | - | 640, 463, 161 | 2 of 24 (att) |
| navy / navy | 6 of 8 | 178, 0 | 194, 22 | 640, 327, 431 | 640, 478, 82 | 20 / 18 of 24 |

(8 battles a row; 640 men landed = 80 a battle: the frigate's 50 and the sloops' 15 each; the natives' 35 a battle.) The
defenders' guns lie by the quay behind the houses and find almost nothing to shoot (1 shot in 8 battles) until enemy
ships come: then they duel them (178 shots, the hulls' hits, no men). Their parties go ashore once the town is stormed
(the lancers reach the streets in the first 15 s) and hold the quay: 329 kills for 190 lost, and the attackers' wins
7 -> 5 of 8. The attackers' ships, at the far end of the shore, shoot the waterfront and the defenders' parties afloat
(108 kills) and their parties storm along it (161 kills, 463 lost): 7 -> 8 of 8. Both fleets: the ships silence each
other (20 and 18 of 24 gun decks) and the attackers' guns take the defenders' parties on the water. Intervals at 8
seeds are about +-30 points: the probe shows the parts work, it does not rank them. The harbour assault
(`harbour_test`), the west_walls and rome_walls plans and every battle without "ships" play and hash as before (no
ship row, `kty_n` kept; the plans carry no ships).

Open: the defenders' ships lie by the quay behind the town, so their guns see little but the waterfront and the
water (the attackers' ships and parties); the parties' landing is a move order (a player may redirect it once afloat);
a hull is never boarded and never sunk in the land battle (silenced at worst); Rome's fleets do not support the shore
(the pack's ships script has no `SHORE_SUPPORT`; Rome's galleys have no guns and no marines row); the Land chip lands
all of one ship's party at once (no partial landings).
