# AI competency

Design for how the AI plays, how skill levels differ, and how we measure
it. Written 2026-10-06 with the user. Status: **design**; the current AI is
one fixed skill (described in `sim/battle_ai.gd`, `sim/siege_ai.gd` and
`campaign/cai.gd`) that this document treats as roughly the "Average" level.

## 1. Principles

1. **Same rules, same information.** The AI never gets money, units,
   health, ammunition, morale, speed, vision or movement the player does
   not get. Difficulty is competence, not bonuses. Forbidden anywhere:
   income multipliers, free units, upkeep discounts, stat multipliers,
   ammo refills, morale floors, movement bonuses, reading the player's
   unsubmitted orders. (There is no fog of war today, so "same information"
   holds trivially; if fog arrives, the AI obeys it.)
2. **Skill is decision quality.** A better AI notices more, decides sooner,
   plans further, executes finer and makes fewer mistakes. A worse AI is
   not slower units but slower thinking, narrower perception, cruder plans
   and deliberate, plausible errors.
3. **Deterministic.** Every decision, including deliberate mistakes, comes
   from sim/campaign state and the sim's own RNG, so lockstep peers and
   replays agree. Skill settings are integers in the scenario / campaign
   state and are in the hashes.
4. **Two independent axes.** Battle skill and campaign skill are chosen
   separately (Easy / Average / Skilled each), per AI faction or for all.
   An easy overworld AI can be hell on the battlefield and the reverse.
5. **Personality is separate from skill.** Aggressive / balanced /
   cautious is a flavour knob (risk appetite), not a competence knob; a
   cautious Skilled AI is still deadly. Personality can be per faction
   (Carthage cautious and rich; Gauls aggressive).
6. **Average should feel like a decent human.** The benchmark for Average
   is "my friend who has played a few campaigns": knows to flank, forgets
   sometimes, overreaches a little. Skilled is the player who reads the
   battle and punishes you. Easy makes the mistakes a new player makes.

## 2. How skill is expressed (the levers)

Every behaviour below is driven by a small set of per-level knobs. These are
the only things that differ between levels; the behaviour code is shared.

| Lever | Easy | Average | Skilled |
|---|---|---|---|
| Reaction time (think interval, battle) | 3–4 s | 1–2 s | 0.5–1 s |
| Perception radius / what it notices | own unit's immediate contact | unit and neighbours, obvious flank threats | whole field: flanks forming, tired units, morale, ammo on both sides |
| Planning horizon (campaign) | this turn | 2–3 turns | 5+ turns, key cities, victory |
| Execution finesse | one order per unit per phase | re-targets, pull-outs | rotation, kiting, timed charges |
| Discipline | chases routers, over-commits | mostly holds | holds; pursues only with cavalry when safe |
| Risk estimate error | ±40 % (over-confident) | ±15 % | ±5 % |
| Deliberate mistake rate | high, plausible | low | near zero |

"Deliberate mistakes" are drawn from a list of realistic errors (below), each
with a per-level probability, rolled with the sim RNG at decision points. An
Easy AI's mistakes should look like a human's (late reaction, wrong target,
a unit left idle), never like a bug (units marching into the sea).

## 3. Battle competencies

For each competency: what good play is, how the three levels behave, and
how we can measure it. The current AI is noted where it already does this.

### 3.1 Deployment
Good: pikes/heavies centre, spears cover the flanks of the line, missiles
in front with a line of retreat, cavalry on wings or in reserve behind,
artillery with fields of fire; adapts to the enemy's composition (more
cavalry opposite their open flank, spears opposite their cavalry) and to
terrain (crests, woods on a flank as an anchor).
- Easy: fixed template, ignores the enemy's composition and terrain.
- Average: current behaviour (template, shifts onto high ground, keeps
  cavalry/pikes/batteries out of woods).
- Skilled: mirrors the enemy's threats, refuses a flank against woods or a
  slope, holds one or two units in reserve behind the centre.
- Measure: deployment scoring in `tests/matchups.gd` (spears opposite
  enemy cavalry, reserve present).

### 3.2 Approach and skirmish
Good: halt in bow range and shoot if you outshoot; close fast if outshot;
keep the line straight; don't let missiles get caught.
- Easy: marches straight in; missiles get caught by cavalry.
- Average: current (halt line, skirmish, closes if outshot or shelled).
- Skilled: staggers the advance so the line arrives together; pulls
  missiles back through gaps before contact; uses the skirmish phase to
  draw out enemy cavalry and punish it.

### 3.3 Engagement and target choice
Good: pin the enemy's best unit with your steadiest, throw weight at
their weakest, avoid pike fronts, keep local superiority.
- Easy: nearest enemy for everyone; one-on-one; will charge a pike front.
- Average: current (nearest, spears to cavalry, pins pikes and flanks).
- Skilled: assigns matchups (heavy on light, sword on pike flank, avoid
  heavy-on-heavy without a flank), concentrates two units on one, keeps a
  unit uncommitted as the hammer.

### 3.4 Flanking and the rear
Good: once lines meet, cavalry and spare infantry go round; rear charges
break units; defend your own flanks with spears or by refusing them.
- Easy: rarely flanks (low probability per opportunity), reacts to being
  flanked only when the flanked unit is already breaking.
- Average: current (cavalry rides to flank/rear; spears cover).
- Skilled: creates flanks on purpose: pulls a unit back to bend the enemy
  line, then hits the exposed shoulder; rotates a spear unit to a
  threatened flank before the charge lands; counter-charges enemy cavalry
  with its own.
- Measure: flank/rear hits per battle, time from enemy cavalry committing
  to a spear response (`ai_flank` counters already exist).

### 3.5 Cavalry use
Good: charge, pull out, charge again; never into braced spears or pikes;
hunt missiles and artillery; hold a reserve for the pursuit; don't trade
cavalry for infantry.
- Easy: charges frontally, stays in the melee until it breaks, chases
  routers across the map.
- Average: current (flank charges, pull-outs, rides down unguarded
  batteries, won't charge spears).
- Skilled: kites with enemy cavalry to pull it away from its spears;
  timed double charges; keeps one unit back until the enemy routs, then
  rides them down.

### 3.6 Missile use
Good: shoot the most valuable target you can hit without hitting friends;
retreat before contact; use terrain for range; use woods for shelter
against cavalry; save some ammunition for the rout.
- Easy: fires at the nearest; stands until caught; empties the quiver.
- Average: current (fire at will on unengaged enemies, falls back behind
  the line, shelters in woods).
- Skilled: focuses fire to break one unit; targets the enemy's missiles
  first if it outranges them, cavalry when they stop; kites light cavalry
  into spears; keeps a third of its ammunition for routers.

### 3.7 Artillery
Good: deploy with a field of fire, prefer dense standing targets, don't
shoot into melee, refill in lulls, guard the batteries.
- Easy: deploys where it stands; keeps shooting into melee; batteries left
  unguarded.
- Average: current.
- Skilled: pre-sights the enemy's likely halt line; shifts batteries once
  during the battle for the second phase; pulls crews back when threatened.

### 3.8 Reserves and rotation
Good: keep fresh units behind; relieve a tired or badly damaged unit by
engaging with a second unit and pulling the first out before it breaks.
- Easy: everything in at once; no relief; a unit fights to the rout.
- Average: badly mauled units fall back behind the line (current); no
  deliberate reserve.
- Skilled: holds 1–2 units back; rotates: a relief unit engages the same
  enemy, the tired unit pulls out 10 s later and recovers behind the line,
  then returns. Timed so the enemy never gets a free charge on a unit
  pulling out.
- Measure: units saved from breaking (pulled out under 40 % morale and
  recovered), reserves committed per battle.

### 3.9 Morale and chain routs
Good: identify the enemy's weakest unit and break it to shake its
neighbours; protect your own waverers; stop a chain rout by pulling a
wavering unit out of sight of its routing neighbour.
- Easy: unaware of morale.
- Average: targets routing units for pursuit (current, roughly).
- Skilled: reads morale: focuses on a unit near breaking, charges it from
  the rear to guarantee the break, times it so two neighbours waver;
  pulls its own waverers back early.

### 3.10 Terrain and woods
Good: hold the high ground when it has it, don't attack uphill without a
flank, use woods to hide cavalry and shelter missiles, make the enemy
come to you when stronger in missiles.
- Easy: ignores terrain.
- Average: current (shifts onto high ground, holds a 4 m advantage,
  detours steep approaches, keeps cavalry out of woods).
- Skilled: anchors a flank on woods or a slope; baits the enemy up a slope
  with missiles; uses woods to approach a flank unseen (no fog today, so
  "unseen" is only the movement/charge effect; revisit with fog).

### 3.11 Sieges, attacking
Good: break the gate the defenders are weakest at, suppress the walls,
storm with heavies first, bring cavalry in only when the streets are open,
go for the plaza/citadel rather than hunting, know when to give up.
- Easy: attacks the main gate with everything; infantry hack under wall
  fire without cover; never withdraws.
- Average: current (`sim/siege_ai.gd`).
- Skilled: feints at one gate to draw the garrison, breaks another; uses
  artillery on the wall units before the gate; staggers the storm so
  units don't jam one street (the current known weakness); withdraws when
  the odds turn.

### 3.12 Sieges, defending
Good: keep missiles on the walls facing the threat, close gates in time,
hold the inside of a gate with the steadiest unit, counter-attack a breach
with reserves, fall back to the citadel before being cut off, sally against
a weakened attacker.
- Easy: static; gates left open; never falls back to the citadel in time.
- Average: current (walls shoot, gate guards, reserves at the plaza,
  gates closed at 100 m, citadel fall-back).
- Skilled: shifts wall units to the attacked face; pulls missiles down
  before the gate falls; counter-charges the breach with cavalry inside
  the streets' limits; sallies when the attacker splits.

### 3.13 Pursuit and discipline
Good: pursue with cavalry only while safe; infantry re-forms; don't chase
one routing unit while three others fight.
- Easy: everyone chases routers; gets counter-charged.
- Average: mostly holds.
- Skilled: cavalry pursues in pairs; infantry re-forms and faces the next
  threat.

### 3.14 Knowing when to quit
Good: withdraw the army when the battle is lost and the army is worth more
alive (campaign consequence); fight to the end when the city is at stake.
- Easy: fights to annihilation or withdraws too early at random.
- Average: current (withdraws when clearly lost).
- Skilled: withdraws in good order, missiles and cavalry covering, when the
  odds (and the campaign situation passed in: can it retreat, is this the
  capital) say so.

### Deliberate mistakes (battle), rolled per level
Late reaction to a flank; wrong target (nearest instead of weakest);
leaving a unit idle for a phase; chasing routers with infantry; charging a
spear front once; forgetting to pull missiles back; committing the reserve
too early; not closing a gate. Each has a probability per level (Easy high,
Average low, Skilled ~0) and a cooldown so one army doesn't make the same
mistake twice in a row.

## 4. Campaign competencies

### 4.1 Economy and build order
Good: build income first in rich regions, military buildings where you
recruit, walls where you are threatened; don't run a deficit; match upkeep
to income with a reserve for a war.
- Easy: builds whatever is cheapest; overspends into debt; recruits
  piecemeal.
- Average: current (`campaign/cai.gd` build and recruit priorities).
- Skilled: plans a build order per region by wealth and threat; times
  recruitment for the war it intends; keeps a war chest.

### 4.2 Army composition
Good: a balanced army for the enemy it will meet (spears vs cavalry
factions, missiles vs light-infantry factions, artillery for sieges), tier
upgrades where income allows.
- Easy: whatever is available, single-type stacks.
- Average: a fixed balanced template.
- Skilled: composition by target (siege train for a walled city, cavalry
  for raiding, spears against a cavalry-heavy enemy); merges damaged
  armies to full strength before campaigning.

### 4.3 Target selection and expansion
Good: take weak, rich, nearby regions first; key cities when strong
enough; don't open a second front; secure chokepoints.
- Easy: attacks the nearest enemy region regardless of odds.
- Average: current (strength ratio, odds, path cost).
- Skilled: values regions by income, position (chokepoints, ports) and
  victory relevance; sequences conquests so each new region is
  defensible; avoids wars on two fronts.

### 4.4 Concentration of force and support
Good: gather within support range before attacking; attack with two armies
against one; never trickle units in.
- Easy: attacks with whatever is adjacent; armies arrive one turn apart.
- Average: current (gathers a march short of the target, within support
  range, attacks at 130 %).
- Skilled: stages so that support range and zones of control both favour
  it, uses forced march to time arrivals, and attacks the player's
  isolated army when it can bring two to one.

### 4.5 Defence, screening and zones of control
Good: keep a field army between the enemy and your cities; garrison
threatened cities with the stance that fits; use fortify at chokepoints;
don't leave the capital empty.
- Easy: no screening; armies wander; cities left empty.
- Average: current (screens threatened cities, holds regions enemies can
  reach within a turn, fortifies when threatened).
- Skilled: predicts the player's reach next turn and positions so every
  approach crosses a zone of control; shelters a weaker army inside walls
  and sallies with support when the besieger is weaker.

### 4.6 Sieges and relief
Good: assault when the odds are good or the garrison starves and relief is
coming; otherwise wait; lift when a stronger relief approaches; relieve your
own cities with support in range.
- Easy: assaults on arrival; never relieves.
- Average: current (siege at half ratio with a second army near; assault
  at ratio; maintain cap; relieves when odds favour).
- Skilled: times the assault to the garrison's starvation and the player's
  distance; brings artillery for level-3 walls; intercepts the relief army
  in the field with the besiegers plus a screen.

### 4.7 Stances
Good: forced march to arrive a turn early where no fight is expected;
fortify when waiting for the enemy at a chokepoint; raid rich enemy regions
you cannot hold.
- Easy: default stance always.
- Average: current (uses all three with simple triggers).
- Skilled: forced march to catch a retreating or isolated enemy; raids to
  pull the player's army off its line, then strikes elsewhere.

### 4.8 Diplomacy
Good: don't declare war when already stretched; make peace when losing; war
on the player when the player is weak or overextended; trade with everyone
not at war.
- Easy: random-ish wars, never seeks peace.
- Average: current (war ratio limits, peace when losing badly).
- Skilled: declares war when the player's armies are far from the shared
  border; coordinates with its ally's wars; accepts peace to rebuild then
  returns.

### 4.9 Preservation and retreat
Good: an army is worth more than a region; retreat from a lost battle to
rebuild; replenish before fighting again.
- Easy: fights every battle to the end; never replenishes deliberately.
- Average: current (withdraws when clearly losing; replenishes in friendly
  land).
- Skilled: avoids battles at under 50 % odds unless a city is at stake;
  retreats behind a zone of control; rebuilds to full strength first.

### 4.10 Reading the player
Good: react to the player's concentrations (don't leave a city undefended
on the side the player's two armies face); exploit the player's absence
(raid or siege where they are not).
- Easy: no model of the player.
- Average: threat by reach (current).
- Skilled: tracks the player's armies turn to turn and acts on their
  trajectory (where they can be next turn), not just their reach.

### Deliberate mistakes (campaign)
Leaving a city empty for a turn; attacking at bad odds once; over-recruiting
into a deficit; declaring an unwise war; forgetting to garrison a new
conquest. Per-level probabilities as above.

## 5. Personality (orthogonal)

| | Cautious | Balanced | Aggressive |
|---|---|---|---|
| Attack odds threshold | 160 % | 130 % | 110 % |
| War appetite | low | medium | high |
| Raiding | rarely | sometimes | often |
| Battle: commit reserve | late | normal | early |
| Battle: cavalry risk | low | normal | high |

Personality shifts thresholds; skill decides how well the chosen plan is
executed. Default per faction in `cdata` (e.g. Carthage cautious, Gauls
aggressive, Rome balanced); overridable at campaign start.

## 6. Measurement

Competence must be measurable, or "Skilled" is a label.

**Battle (tests/matchups.gd)**
- Skilled vs Easy with identical armies and mirrored maps: Skilled wins
  ≥ 85 %. Skilled vs Average ≥ 65 %. Average vs Easy ≥ 70 %.
- Per-competency counters (many already exist as coverage counters):
  flank/rear hits, pull-outs, rotations, units saved from breaking,
  routers chased by infantry, spears responding to cavalry within N s,
  missiles caught, ammunition left at rout, reserve commits, over-commits.
  Each level has target bands for these.
- Settlement battles: Skilled attacker vs Average defender and the
  reverse, win rates and durations per plan and wall level.

**Campaign (tests/campaign_sim.gd)**
- AI-only campaigns where one faction is Skilled and the rest Average:
  the Skilled faction's expected region count at turn 60 is higher without
  any economic advantage; Easy correspondingly lower. No cheats verified
  by asserting identical income/recruit formulas per level.
- Counters: battles at bad odds, cities left empty when threatened,
  two-front wars, armies trickled, sieges assaulted at starvation vs
  blindly.

**Human**
- Average should beat a first-time player and lose to the user; Skilled
  should beat the user at even odds some of the time. The two humans'
  playtests calibrate the "average human" level.

## 7. Implementation sketch

- **Profiles as data.** `sim/ai_profile.gd`: integer knob tables per level
  (think interval, perception flags, planning depth, mistake
  probabilities per mistake type, thresholds) plus personality offsets.
  The scenario dictionary carries `ai_skill` and `ai_style` per side;
  they are in `state_hash()` and snapshots.
- **Battle AI reads knobs, never branches on level.** `battle_ai.gd` and
  `siege_ai.gd` consult the profile for every threshold and interval; new
  competencies (rotation, kiting, matchup assignment, reserve, morale
  reading, deliberate mistakes) are added as behaviours that the profile
  enables or scales. Mistakes are rolled with the sim RNG at the decision
  point and logged as events for the telemetry counters.
- **Campaign AI likewise.** `campaign/cai.gd` reads a per-faction
  `ai_skill` / `ai_style` from the state (`factions[i]`), chosen on the
  new-campaign screen (one setting for all, or per faction under
  "Advanced"). Campaign skill also sets the battle skill of that
  faction's armies unless overridden ("split" setting).
- **Co-op.** Both humans share the campaign's settings; the battle
  profile travels in the scenario so lockstep peers agree.
- **Telemetry.** Counters per competency in the battle result and the
  campaign events, so phone playtests tell us what the AI actually did.

## 8. Order of work

1. Profiles and knobs, with the current behaviour as "Average" and the
   existing thresholds moved into the table (no behaviour change; hashes
   unchanged at Average).
2. Easy: reaction/perception knobs and the deliberate-mistake roller, both
   battle and campaign. Measure Average vs Easy.
3. Skilled battle: reserves and rotation, matchup assignment, morale
   reading, cavalry kiting and timed charges, staggered storming,
   pull-missiles-before-contact. Measure vs Average.
4. Skilled campaign: trajectory-based threat, staging with support and
   zones, targeted composition, diplomacy timing.
5. Personality table and per-faction defaults; new-campaign UI; split
   setting.
6. Calibrate "Average" against the two humans' playtests.

Open questions for the user are tracked in `docs/STATUS.md` under this
item.
