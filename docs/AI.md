# AI competency

Design for how the AI plays, how skill levels differ, and how we measure
it. Written 2026-10-06 with the user. Status: **design, steps 1-4 built**
(profiles as data, section 9; Easy, section 10; Skilled battle and
settlement AI, section 11; Skilled campaign AI, section 12); Average is the one fixed
skill the AI had before (described in `sim/battle_ai.gd`,
`sim/siege_ai.gd` and `campaign/cai.gd`), which this document treats as
roughly the "Average" level.

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

Personality also covers **how a faction fields its armies**, so a late-game
Roman army feels different from a late-game Gallic one at the same skill:
a per-faction composition style in `cdata` (preferred arms and tiers, how
much artillery, how much cavalry, how early it upgrades) that the campaign
AI's recruitment follows and the battle AI's deployment template reflects.
Rome: heavy infantry lines, spears on the flanks, artillery for sieges.
Gauls: swords and cavalry, light on missiles, early aggression. Carthage:
cavalry and mercenary-style mixes, elephants when they exist, keeps a war
chest. Greeks: pike centre, missiles, strong walls. Skill decides how well
the style is executed, not which style is used.

**Data shape** (in `campaign/cdata.gd` FACTIONS, step 1: present, not yet
read by anything):

```
"ai_style": AI_BALANCED,        # AI_CAUTIOUS 0 / AI_BALANCED 1 / AI_AGGRESSIVE 2
"composition": {
    "arms": ["heavy", "spear", "javelin"],  # preferred lines (CData.LINE_ORDER keys), best first
    "art_pct": 10,               # share of artillery in a field army, %
    "cav_pct": 10,               # share of cavalry, %
    "upgrade": 2,                # eagerness to recruit higher tiers: 0 late, 1 normal, 2 early
}
```

`ai_style` is copied into a new campaign's `factions[f]` when it is not
Balanced (every faction is Balanced for now; Carthage Cautious and the
Gauls Aggressive come with step 5). `composition` complements the existing
`mix` weights (which recruitment already follows).

**Decisions (user, 2026-10-06):** if fog of war is ever added the AI obeys
it like the player; the difficulty knobs (battle, campaign) are global
(Easy / Average / Skilled) with per-faction overrides under an Advanced
tab; personalities and composition styles are per faction by default and
should be felt without touching Advanced; the order of work in section 8
stands.

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

The user's decisions on the open questions are recorded in section 5.

## 9. As built: profiles (step 1, 2026-10-06)

No behaviour change: at Average / Balanced every hash is the old one
(determinism golden digests and final hashes, campaign_sim per-seed
hashes, the siege matchups).

**Battle and settlement AI: `sim/ai_profile.gd`.** `KNOBS` rows
`[knob, EASY, AVERAGE, SKILLED]` (Average = the old constant; Easy and
Skilled copies for now), `STYLE` rows `[knob, CAUTIOUS, BALANCED,
AGGRESSIVE]` of offsets (all 0; the rows mark what personality will move:
when to quit, cavalry risk, how long to stand and shoot). Behaviour code
reads `kn[AP.X]` with `kn = AP.of(sim, side)` and never branches on the
level. 148 knobs by competency: reaction 4 (army and unit think intervals,
re-order thresholds), deployment 5, approach and skirmish 8, engagement 2,
flanking 4, cavalry 26 (timings, distances and the target scores),
missiles 3, artillery 18 (incl. target scores and refill thresholds),
reserves 3, morale 1, terrain and woods 23, withdrawal 3, pursuit 4,
sieges attacking 34, sieges defending 10. Ratios that were fractions
like 4/3 or 2/3 are NUM / DEN knob pairs so Average is exact.

**Scenario and sim state.** The scenario carries `"ai_skill": [s0, s1]`
and `"ai_style": [s0, s1]` per sim side (absent = Average / Balanced).
`BattleSim.ai_skill` / `ai_style` are hashed by `state_hash()` only when
not the default (so every old scenario hashes as before) and survive
`snapshot()` / `restore()` (`tests/lockstep_test.gd` checks both). The
co-op scenario hash (`CoopSession.scenario_hash`) covers the whole
scenario, so peers with different profiles refuse to start.

**Campaign AI: `campaign/cai_profile.gd`.** Same layout, 60 knobs:
economy 5, recruitment 9, targets 4, concentration 7, defence and screens
3, sieges and relief 6, raids and hunting 4, diplomacy 22. A faction's
skill is `factions[f].ai_skill`, else `settings.ai_campaign_skill`, else
Average; its style `factions[f].ai_style`, else Balanced; its armies'
battle skill `factions[f].ai_battle_skill`, else `settings.ai_battle_skill`,
else Average. These keys are written only when not the default (no
`CState.VERSION` bump; older states read the defaults).
`campaign/cbattle.gd` puts the AI side's lead faction's battle skill and
style into the scenario (the players' sides Average / Balanced).

**UI.** New campaign: a "Difficulty" row, Battle AI and Campaign AI
(Easy / Average / Skilled, default Average; Easy and Skilled said "(soon)"
and played like Average until steps 2 and 3; Easy is real since step 2,
section 10). Sandbox: an "AI:" button for both AI sides. Per-faction
overrides (Advanced) come later.

**Counters (section 6).** Battle: `BattleSim.stat_aic[side *
AP.N_COUNTERS + AP.C_*]`, not hashed, never read by a decision: flank /
rear charge hits, cavalry pull-outs, rotations (0 until step 3), units
saved (fell back mauled and returned without breaking), routers chased by
foot, spear responses to cavalry and the ticks they took, missile
unit-thinks in melee, ammunition left at rout over missile routs, reserve
commits (0 until step 3). Campaign: `CP.count()` into a static dictionary
outside the state (attacks at bad odds, threatened cities left empty,
faction-turns at war on two fronts, armies trickled in), printed per seed
by `tests/campaign_sim.gd`.

**Left hard-coded on purpose:** constants mirrored from the sim (order
types, states, the frontal arc, line-of-fire heights), map-edge clamps,
the fixed candidate patterns of spot searches (`_clear_spot`, `_rise`,
`_art_resite`, `_shelter`'s 20 / 40 m rings, woods sampling every 8 m),
order sequence numbers, arrival / slack tolerances of `_go_home` and
battery positioning, the citadel's capacity (2 m2 a man), and in the
campaign `FIELD_SEA` (a property of the memoised distance fields) and
the `ai_aggression` setting's clamp.


## 10. As built: Easy (step 2, 2026-10-06)

Average / Balanced is byte for byte what it was: determinism golden
digests and every Average run's final hash, `campaign_sim` 6 x 60 per-seed
hashes and `matchups --only=sieges` equal to HEAD. A mistake whose chance
is 0 at a level is never rolled (no RNG draw), and the new sim array
`ai_mist` is hashed only with a non-default profile. Easy plays by the
same rules with the same information: no stat, income, ammunition,
morale, vision or movement difference anywhere; everything it does is an
order a player could give.

**Battle knobs (`sim/ai_profile.gd` EASY column).** Reaction: army thinks
every 3.5 s, units every 3 s (staggered), re-orders only for a 25 m /
48-unit facing change. Perception: spears turn on cavalry within 20 m
(Average 40), cavalry answers enemy riders near our foot within 25 m
(60); missiles never shelter in woods. Deployment: no shift onto high
ground, no rise for missiles and batteries, no clear-spot search in woods
(`CLEAR_SPOT` 0), batteries deploy where they stand, up to 12 foot in the
first line. Approach: skirmishes at most 40 s from deployment (march
included: in practice it marches straight in), missile troops never put
in skirmish mode (`MIS_SKIRM` 0: they stand until caught). Engagement:
takes another target than a formed pike front only if it is nearer than
110 % (Average 150 %), goes round a pinned pike front only 30 % of the
time (`FLANK_PCT`). Cavalry: charges a formed, unengaged front head on
(`CAV_STAGE_FRONT` 0), engaged braced fronts score like any engaged
enemy, routers score 5,000 (Average 1,000: it chases them across the
field), no uphill or woods penalties. Reserves: no fall-back of mauled
units (`RETIRE_ALIVE_PCT` 0). Withdrawal: only below 15 % of the
enemy's strength (or 10 % of its own start), else fights on.
Sieges: hacks at the nearest gate with four foot units from the start
(no bombardment first), all in after 1 minute of assault, routers chased
200 m; defending, reserves react within 60 m, gates are closed at 40 m,
wall units come down at 15 m, the citadel is taken only when attackers
inside outnumber the defenders twice (`S_CIT_OUTNUMBER_PCT` 200) or are
within 10 m of its gate.

**Deliberate mistakes (battle), % per roll at the decision point, with a
3 s cooldown per side and mistake (`MK_COOLDOWN` 30 ticks, in
`BattleSim.ai_mist`):** late reaction (a spear or cavalry unit ignores
enemy riders near it, a town's reserve attackers in the streets near its
post, this think) 50; wrong target (cavalry rides at the
nearest enemy foot instead of the target it chose) 15; a line unit left
idle for up to 60 s when the lines meet (`A_IDLE`, back in at once if
attacked) 50; foot chasing a router nearer than the fight (until it is
gone or rallies; storming foot in a town likewise) 90; a charge into a braced or pike front (cavalry, and
foot that do not avoid a formed pike front) 35; archers not pulled back
behind the line when it engages 60; the cavalry thrown head on at the
enemy line before the lines meet (once a battle) 15; a gate left open this
think with attackers near (defending) 50; withdrawing while still in the
fight, below 75 % of the enemy's strength (once a battle) 35. Counted in
`stat_aic` (`mk_*`).

**Not as the design said, and why.** Measured against Average with
identical armies, several "Easy" behaviours of section 3 turned out to be
*stronger* than Average's own competence in this sim, so Easy keeps the
Average value there:
- cavalry staying in melee (no pull-outs): Easy won ~57 % of mirrored
  battles with it; Easy cavalry pulls out like Average;
- batteries left unguarded: an unguarded battery lures Average's cavalry
  (its highest target score) away from the line and frees a foot unit;
  Easy guards its batteries;
- firing at will into melee (missiles not holding fire): Easy holds fire
  like Average;
- "nearest instead of chosen" for batteries and cavalry, and the whole
  line charging from too far: both made Easy win more (nearest = sooner
  impact; there is no fatigue, so an early charge only catches Average's
  skirmishers). The wrong-target mistake became "cavalry rides at the
  nearest enemy *foot*" and committing early became "the cavalry reserve
  thrown at the enemy line", both at low rates.
These say as much about Average as about Easy: its pull-outs, battery
guard, skirmish halt and target scoring cost it against a blunt opponent.
Step 3 (Skilled) should start there.

**Battle measurement** (`matchups --fair=50 --skill=a:e`, bench_2000,
identical mirrored armies, each seed in both orientations, 100 battles):

| | Average wins | Easy | draws | mean / max min | Average top / bottom |
|---|---|---|---|---|---|
| flat | 74 % | 25 % | 1 | 5.6 / 15.0 | 41 / 33 of 50 |
| symmetric hill (`--fair-terrain=4`) | 71 % | 29 % | 0 | 5.5 / 10.3 | 40 / 31 of 50 |
| Easy vs Easy, flat | 50 / 50 | | 0 | 5.2 / 14.3 | |

(Average vs Average on the same seeds: 50 / 50, top side 58 %: the bias
is the scenario's, not the levels'.) Counters per 100 battles, Average /
Easy (flat): flank or rear hits 2,277 / 2,576, cavalry pull-outs 561 /
353, units saved 13 / 0, routers chased by foot 0 / 347, spear responses
59 / 16 (mean 22 / 32 ticks after the riders came within the spears'
radius), missile unit-thinks in melee 1,353 / 957, arrows left per missile
rout 550 / 957 (Easy's archers break with full quivers), mistakes: late
flank 111, wrong target 79, idle 94, chase 663, spear charge 304, archers
left forward 49, cavalry committed early 20, early withdrawal 22.

**Settlements** (`--only=plans --plans=4,1 --walls=W --skill=A:B`, 10
seeds, a city with garrison and a 4-unit field army against the standard
12-unit attacker; attacker wins at walls 1 / 2 / 3, mean minutes):

| | Average vs Average | Easy attacker | Easy defender |
|---|---|---|---|
| ring, plain | 100 / 100 / 100 %, 5.6 / 6.2 / 7.7 | 100 / 90 / 90 %, 4.1 / 4.7 / 4.9 | 100 / 100 / 80 %, 5.5 / 6.6 / 8.1 |
| ring, hill | 100 / 100 / 80 %, 6.1 / 6.5 / 8.0 | 100 / 90 / 80 %, 4.5 / 5.3 / 5.9 | 100 / 90 / 90 %, 6.0 / 6.9 / 8.1 |
| polis, coastal hill | 100 / 100 / 60 %, 7.8 / 9.2 / 11.9 | 100 / 80 / 80 %, 6.0 / 8.4 / 8.7 | 100 / 70 / 60 %, 9.7 / 9.1 / 10.9 |
| polis, plain | 100 / 100 / 90 %, 8.2 / 9.1 / 9.9 | 100 / 80 / 70 %, 6.1 / 7.8 / 7.5 | 100 / 70 / 90 %, 9.4 / 9.5 / 11.1 |

The Easy attacker storms sooner (hacking from the start) and fails a
little more often behind walls 2-3, but still wins most settlement battles
with the standard attacker (never 0 %). An Easy defender does not make a
city easier to take in this sample (10 seeds: a difference of one battle
is noise): the walls, the gate guards and the citadel do the work, and a
late reaction in the streets costs little. Draws stay at or below
Average's (at most 10 % against its 30 % on the coastal polis at walls 3).

**Campaign knobs (`campaign/cai_profile.gd` EASY column).** No reserve,
all money above it on buildings, the cheapest wanted building first
(`BUILD_CHEAPEST`), walls only when the threat exceeds the whole defence;
one recruit a turn, 70 % of them of the line it already has most of
(`RECRUIT_LEAN_PCT`); targets reached this turn first, by value, defence
not weighed (`TARGET_NEAREST`), attack at 110 % (Average 130 %), commit
only to 100 % of that; no gathering: armies go as they are and arrive a
turn apart (`GATHER` 0); storm on arrival (`ASSAULT_ALWAYS`), never lift,
never relieve (`RELIEVE` 0), no screens (`SCREENS` 0), the default stance
only (`STANCES` 0: no fortify, forced march, raids or sheltering); idle
armies take 20 % odds, hunt field armies at 50 %; regions of the players
valued like any; wars on neighbours at 100 % of their strength, never
asks for peace. Mistakes, % per roll (`CState.rand`, Average never
draws): an army that should hold a threatened city marches off 50; the
same for a city taken last turn (conquest not garrisoned) 50; one attack a
turn below the odds 30; a turn of recruiting up to 130 % of income 25; a
war on a stronger neighbour 8 a turn when one qualifies. Counted with
`CP.count` (`mk_*`), printed by `campaign_sim`.

**Mustering (format 6, commit 20fa43e).** The planner moves armies before
it recruits, since an army taking recruits cannot march that turn (the
same rule as the player's). `RECRUIT_HOLD_UNITS` (Easy 0, Average and
Skilled 2): when every army at a recruiting city is planned to march, one
of at most this many units on a march within the AI's own lands stays to
take the recruits instead; the others march and the recruits raise a new
army. At 0 the AI never holds a unit back, so its recruits always start
as new one- or two-unit armies.

**Campaign measurement** (`campaign_sim --seeds=6 --turns=60`, rules of
commit 857c275; one faction Easy at a time, the others Average; regions
at 15 / 30 / 60, mean of 6 seeds, eliminations by turn 60):

| faction | Average (all Average) | that faction Easy |
|---|---|---|
| Rome | 4.0 / 4.2 / 6.3, 0 out | 3.5 / 3.8 / 5.8, 2 out (turns 14, 21) |
| Carthage | 5.0 / 4.5 / 3.2, 3 out | 6.0 / 7.8 / 6.2, 2 out (48, 25) |
| Macedon | 2.7 / 1.7 / 2.0, 4 out | 2.7 / 2.5 / 4.7, 2 out |
| Epirus | 3.0 / 2.0 / 1.3, 2 out | 3.3 / 2.8 / 5.3, 1 out |
| Greeks | 4.5 / 6.3 / 8.8, 0 out | 4.2 / 6.7 / 9.2, 0 out |
| Syracuse | 4.2 / 4.3 / 2.0, 3 out | 4.2 / 4.5 / 6.2, 3 out |
| Iberians | 4.8 / 5.3 / 6.8, 1 out | 5.3 / 4.3 / 4.5, 2 out |
| Gauls | 6.8 / 7.7 / 5.5, 0 out | 5.5 / 5.0 / 2.8, 2 out |
| all 48 runs | 4.38 / 4.50 / 4.50, 13 out | 4.33 / 4.69 / 5.58, 14 out |

**The campaign target is not met:** an Easy faction is about as big as
the same faction at Average at turns 15 and 30 and on average bigger at
60, with one more elimination in 48 runs. Rome, Iberia and the Gauls end
smaller, the weak eastern factions and Carthage larger. Two things block
it. The world is chaotic (one faction's level changes every war; the
spread between seeds is far larger than the difference measured), and,
as in battle, the Average campaign AI's caution costs it about as much as
Easy's mistakes: gathering a march short, screening cities, laying siege
and waiting, and holding threatened regions keep its armies from
conquering, while a faction that storms the nearest region on arrival
snowballs once it survives the first wars. Earlier variants made this
plain: with Easy's first draft (attack at 80 %, three wars, more upkeep)
Easy factions ended at 7.1 regions against Average's 4.5; Average's
screens and gathering given back to Easy cost it a region; economic
handicaps (one recruit a turn, everything on buildings) are what bring it
back to par. Step 4 should look at Average's passivity first; a
calibration with humans (step 6) will say which of the two is wrong.

All-AI campaigns at Easy (every faction) run as fast as at Average (40-60
ms a turn), with three times the battles (185-211 against 45-86) and
largest realms of 9-16 regions at turn 60. Mistakes over 6 x 60 turns
(all Easy): city left empty 121, attack at bad odds 41, over-recruiting
120, unwise war 3, conquest not garrisoned 8.

**Lockstep and determinism.** `tests/lockstep_test.gd`: two peers against
an Easy enemy AI, with a third joining mid-battle by snapshot, are hash
equal on every frame and the enemy makes mistakes; AI battles with both
sides Easy (a field battle and a walled city) restore from snapshots at
three points and run on identically. `tests/determinism_test.gd`: Easy
runs (both sides on a flat field, Easy against Average on a hill, an Easy
attacker and an Easy defender of a walled city) are identical on repeat,
diverge for another seed and make mistakes; an Easy field battle and an
Easy-defended city are in the snapshot round trips.

**UI.** Easy is selectable without "(soon)" on the new-campaign
Difficulty row (Battle AI and Campaign AI) and on the sandbox "AI:"
button; Skilled still says "(soon)" and plays like Average. (Step 3:
Skilled battle AI built, section 11.)


## 11. As built: Skilled (step 3, 2026-10-06)

Average and Easy are byte for byte what they were: determinism golden
digests and every Average / Easy run's final hash, `matchups
--only=sieges`, and `matchups --fair=50 --skill=a:e` (flat 74 / 25 / 1
draw, hill 71 / 29, the same counters) equal HEAD. Every Skilled behaviour
is switched on by an `SK_*` knob (`sim/ai_profile.gd`, ids 166-207) that
is 0 for Easy and Average, so those levels never run it, never draw the
RNG for it and keep no Skilled memory. No behaviour code branches on the
level. Skilled has no deliberate mistakes (all `M_*` 0). It plays by the
same rules with the same information: everything it reads is on the field
(positions, facings, how fast a unit moves, men, morale and ammunition,
who is fighting, a gate's damage), never an enemy's orders, and
everything it does is an order a player could give.

**Memory.** `BattleSim.ai_mem` (one new array in `sim/battle_sim.gd`, the
only sim change): `AP.MU_K` = 4 ints per unit (matchup target, melee
start men / relief unit, enemy men at contact / relief tick, role: reserve,
rotated out, reserve rider, released guard, wall unit in transit, moved
reserve post, sallying) and `AP.SD_K` = 4 per side (sally gate and tick,
reserve riders released, withdrawal began). It is sized only when a
side's profile has `SK_MEM` (`AP.uses_mem`), so it is empty, and hashes
as nothing, in every other battle; it is in `state_hash()` with the
profiles and in `snapshot()` / `restore()` like every script variable.
(The lockstep profile check's hash for a [Skilled, Easy] scenario and the
snapshot size, +8 bytes, changed accordingly.)

**Behaviours (field, `sim/battle_ai.gd` section "Skilled").**
- Reserves (3.8): one foot unit (light first, never pikes;
  `SK_RESERVE` 1) deploys and keeps station 30 m behind the centre
  (`A_RESV`; fights only what comes within 25 m). It commits to relieve
  the most tired unit of the line, or as the hammer on an enemy unit
  engaged with ours and near breaking (morale under 400) within 80 m
  (round its flank if its front faces us). One cavalry unit (`SK_CAV_RESERVE`
  1, with two or more) only counter-charges riders on our flank, finishes
  wavering units or rides down routers until the enemy's first line unit
  or rider breaks (or our other riders are gone); then it is free.
- Rotation (3.8): a foot unit fighting with morale under 40 % of its
  type's is relieved by the reserve, which attacks the same enemy; once the
  relief has fought 6 s and no free enemy riders are within 60 m, the
  tired unit falls back 60 m, recovers 30 s and becomes the reserve.
  Own waverers (morale under 300, not fighting) next to a routing friend
  fall back the same way (3.9).
- Matchup assignment (3.3): each army think, a greedy pass over (free foot
  unit, enemy) pairs, best score first (ties: lower unit, then target):
  1 point per metre nearer, +20 a good matchup (foot on missiles or
  artillery, heavy on light, spears on riders), -40 heavy on an unengaged
  heavy, -80 a formed pike front, +30 a flank or rear on an enemy engaged
  with ours, +5 per 10 morale under 400, -4 per % of climb, +25 the target
  it already goes for, +35 an enemy nobody of ours is on yet (pin every
  enemy first), +25 a second unit on one, -25 per unit beyond. Candidates
  within 120 % of the nearest enemy's distance + 5 m; foot never chase
  riders (spears may).
- Cavalry (3.5): after the 5 s of melee it pulls out only if it is not
  winning (the enemy lost under 150 % of its own losses since contact),
  else stays and judges again; pursuit in pairs (+600 for a router another
  rider is after); a staged rider waits up to 8 s for a partner staging on
  the same target (timed double charge); +1,500 for enemy riders caught in
  a melee (counter-charge); +5 per morale point under 400 for an engaged
  enemy (the finishing charge, 3.9).
- Missiles (3.6): focus fire, one order for the target chosen from those in
  range and not in a melee: enemy missiles we outrange +500, halted riders
  +400 (moving -300), shields facing us -6 per % of missile shield, +2 per
  morale point under 400, +250 per other missile unit on it; flat throws
  only with a clear line. Archers go back behind the line when enemy foot
  come within 70 m during the advance (Average: when the lines meet).
- Spears (3.4): the spear response reads where riders are heading (their
  facing and pace 3 s ahead), so spears turn before the charge lands (mean
  response 9 ticks against Average's 50).
- Artillery (3.7): the battery guard joins the fight once the lines meet
  while no enemy riders are free within 150 m of the battery, and goes back
  when free riders come within 100 m; crews of a battery with an enemy
  melee unit within 35 m (riders 70 m) and no melee friend near pull back
  60 m and return like a mauled unit.
- Deployment (3.1): with the enemy's riders massed toward one end of our
  line (their mean more than 20 m off our centre), the spears take that end;
  on maps with woods the line shifts up to 40 m aside (20 m steps, nearest
  first) to rest a flank on woods with the line itself clear.
- Terrain (3.10): holds high ground from 0.5 m above the enemy (Average
  4 m; `HOLD_DH`), and the matchup score's climb penalty.
- Withdrawal (3.14): foot and batteries withdraw first, cavalry and
  missile troops keep covering for 15 s, then everyone goes.

**Behaviours (settlements, `sim/siege_ai.gd` section "Skilled").**
Attacking: the cavalry waits before another gate during the approach (the
feint); storming foot outside the walls wait before the breach while three
of ours crowd the street just inside it (staggered storm). Defending: the
attacked gate is read from the field (the gate being damaged, else an
open or broken one with attackers near, else the one nearest the
attackers); wall missile units with nobody in range shift along to the
stretches nearest it (two a stretch at most); wall missile units within
60 m of it come down to the street behind it when it is below a quarter of
its hit points; once it is below half (or open / broken) the reserves'
posts move up behind it (counter-charge the breach); and a closed gate
with a weak party of attackers within 60 m and nobody else within 150 m
opens for a sally by the foot and riders within 60 m inside it if they are
1.5 times as strong (back after 45 s or when no attackers are left near;
the usual rule shuts the gate).

**Knob values (SKILLED column; Easy and Average 0 for every `SK_*`).**
Reaction and every Average threshold are kept, except `HOLD_DH` 0.5 m.
`SK_ASSIGN` 1, `SK_ASSIGN_REACH` 120 %, `SK_ASSIGN_SLACK` 5 m,
`SK_SC_PAIR` 25, `SK_SC_MATCH` 20, `SK_SC_BAD` 40, `SK_SC_FLANK` 30,
`SK_SC_MORALE` 5, `SK_BREAK_MORALE` 400, `SK_SC_UPHILL` 4, `SK_SC_STICK`
25, `SK_SC_COVER` 35; `SK_PULL_READ` 1, `SK_WIN_PCT` 150; `SK_CAV_RESERVE`
1, `SK_CAV_PAIR` 600, `SK_PAIR_WAIT` 80 ticks, `SK_CAV_COUNTER` 1,500;
`SK_FOCUS` 1, `SK_AMMO_KEEP_PCT` 0; `SK_GUARD_CAV_R` 150 m, `SK_ART_PULL`
1; `SK_RESERVE` 1, `SK_RESERVE_BACK` 30 m, `SK_ROTATE` 1,
`SK_ROT_MORALE_PCT` 40, `SK_ROT_DELAY` 60 ticks, `SK_ROT_SAFE_R` 60 m,
`SK_WAVER_PULL` 300; `SK_MIS_EARLY_R` 70 m, `SK_SPEAR_LEAD` 30 ticks;
`SK_MIRROR` 1, `SK_ANCHOR` 40 m; `SK_WD_COVER` 150 ticks; sieges
`SK_STORM_STAGGER` 1, `SK_FEINT` 1, `SK_WALL_ART` 0, `SK_WALL_SHIFT` 1,
`SK_MIS_DOWN_PCT` 25, `SK_BREACH` 1, `SK_SALLY_R` 60 m.

**Not as the design said, and why (measured).**
- Reaction: Skilled thinks every second like Average. Thinking every
  0.5 s lost 7 points against Average (more re-orders, the same plans);
  Skilled reacts sooner by reading more (where riders head, morale,
  who is free), not by thinking more often.
- The two reserves are the heart of it: switching off the cavalry reserve
  took Skilled from 64 % to 34 % against Average, the foot reserve to 38 %.
  Two reserve riders (33 %) or two reserve foot units (46 %) were worse.
- A pair bonus on formed targets (both riders onto one unit) cost 8
  points: pairs are for pursuit only; the timed double charge happens when
  two riders stage on one target anyway.
- Shooting the wall units over the gate before the gate
  (`SK_WALL_ART`, built) slowed the storm and lost walls-3 battles
  (32 of 40 against 36 without): off.
- Keeping a third of the arrows for routers (`SK_AMMO_KEEP_PCT`, built)
  was even on the flat and cost 6 points on hills: off.
- The matchup pass with a wide reach (150 % + 15 m) was worth nothing
  against Average and cost 10 points against Easy and on hills (units
  walked past one enemy to reach another); the tight reach, the "pin
  every enemy first" bonus, stickiness and the climb penalty made it pay.
- A permanent battery guard is right (no guard at all: 34 %); releasing
  it while no riders are free near the battery is the Skilled refinement.
- Not built: bending the enemy line by pulling a unit back, kiting enemy
  riders away from their spears, baiting riders into spears during the
  skirmish, a staggered advance (the line already advances as one
  formation), reading the enemy's approach to skip the skirmish halt
  (switching the halt off measured even), pre-sighting the halt line and
  shifting batteries for the second phase, baiting uphill with missiles,
  approaching a flank through woods, and a slope anchor (woods only).
  Sieges "withdraw when the odds turn" uses Average's thresholds.

**Battle measurement** (`matchups --fair=N --skill=s:X`, bench_2000,
identical mirrored armies, every seed in both orientations; woods:
`--fair-forest=40`, a mirror-symmetric flat map with 40 % woods;
"top / bottom" are the Skilled side's wins in each orientation):

| | battles | Skilled wins | other | draws | mean / max min | Skilled bottom / top |
|---|---|---|---|---|---|---|
| vs Average, flat | 200 | **72 %** | 28 % | 0 | 5.0 / 9.2 | 67 / 77 of 100 |
| vs Average, hill (`--fair-terrain=4`) | 200 | **67 %** | 33 % | 0 | 6.0 / 13.7 | 68 / 66 of 100 |
| vs Average, woods | 100 | **67 %** | 33 % | 0 | 5.1 / 8.5 | 36 / 31 of 50 |
| vs Easy, flat | 100 | **92 %** | 8 % | 0 | 4.2 / 8.0 | 47 / 45 of 50 |
| vs Easy, hill | 100 | **89 %** | 10 % | 1 | 4.9 / 15.0 | 44 / 45 of 50 |
| vs Easy, woods | 100 | **95 %** | 5 % | 0 | 4.4 / 11.6 | 48 / 47 of 50 |
| Skilled vs Skilled, flat | 100 | 50 / 50 | | 0 | 5.6 / 7.0 | |
| Skilled vs Skilled, hill | 100 | 50 / 50 | | 0 | 6.5 / 11.7 | |
| Skilled vs Skilled, woods | 100 | 50 / 50 | | 0 | 5.7 / 7.3 | |

(Average vs Average: 50 / 50, no draws, 5.1 / 8.2 min flat, 5.2 / 8.2
woods.) Targets: Skilled vs Average 65 % and vs Easy 85 % on flat and
hilly maps (and woods): met. Skilled vs Skilled ends every battle, no
draws (Average vs Average: none either), a little longer than Average's
(the reserves). Noise: a 200-battle rate has a standard error of about
3.4 points, a 100-battle one about 4.5.

Counters per 200 flat battles, Skilled / Average: flank or rear charge
hits 4,396 / 4,300; cavalry pull-outs 838 / 625, melees stayed in because
winning 281; rotations 159; units saved (rotated, pulled back wavering or
mauled, back unbroken) 29 / 1; reserve commits (foot and riders) 441;
timed double charges 181; spear responses 278 (mean 9 ticks after the
riders came near) / 252 (50 ticks); missile unit-thinks in melee
2,386 / 4,915; missile routs 167 / 392 (arrows left per missile rout
836 / 849); focus-fire orders 27,081; waverers pulled back 64; battery
pull-backs 258; routers chased by foot 0 / 0. On the hill: rotations 115,
saved 53 / 2, released battery guards 123, spear response 16 / 53 ticks.

**Settlements** (`--only=plans --plans=4,1 --walls=W --skill=A:B`, 10
seeds; attacker wins at walls 1 / 2 / 3, mean minutes):

| | Average vs Average | Skilled attacker | Skilled defender |
|---|---|---|---|
| ring, plain | 100 / 100 / 100 %, 5.6 / 6.2 / 7.7 | 100 / 100 / 100 %, 5.8 / 6.1 / 7.7 | 100 / 100 / 90 %, 5.9 / 6.9 / 8.8 |
| ring, hill | 100 / 100 / 80 %, 6.1 / 6.5 / 8.0 | 100 / 100 / 80 %, 6.5 / 7.0 / 7.9 | 100 / 100 / 40 %, 6.4 / 7.8 / 9.7 |
| polis, coastal hill | 100 / 100 / 60 %, 7.8 / 9.2 / 11.9 | 100 / 80 / 90 %, 8.7 / 10.3 / 10.8 | 100 / 80 / 80 %, 7.7 / 10.4 / 10.0 |
| polis, plain | 100 / 100 / 90 %, 8.2 / 9.1 / 9.9 | 100 / 90 / 90 %, 8.5 / 9.5 / 8.9 | 100 / 90 / 70 %, 8.0 / 10.0 / 11.5 |

At walls 3 the Skilled defender holds 12 of 40 (7 defender wins, 5
draws; attackers win 28) against Average's 7 (3 wins, 4 draws; attackers
33): measurably harder to take.
A Skilled attacker takes 36 of 40 at walls 3 (Average 33), a little more
slowly at walls 1-2 on the polis (the feint and the waits before the
breach), and fails in three polis battles at walls 2 (two defender wins,
one draw) that Average's attacker won. Walls-3
ablations, attacker wins of 40 against the full Skilled defender's 28:
without the wall shift 34, without the breach posts 35, without the sally
31, without bringing missiles down 30. Against the Skilled attacker's 32
(then with the wall bombardment on): without the staggered storm 28,
without the feint 31, without the wall bombardment 36.

**Frame cost** (`tests/benchmark.gd --skill=s`, both sides Skilled,
against HEAD's Average, ms per tick on the desktop): bench_4000 mean
2.87 / 2.85, worst 7.04 / 6.32; bench_4000_hills 3.12 / 3.18, worst
6.65 / 6.46; bench_4000_city 3.11 / 2.89, worst 6.07 / 7.27. Every Skilled
read is per unit (no per-man loop); the matchup pass is units x enemies
once a second per army.

**Determinism and lockstep.** `tests/determinism_test.gd`: Skilled runs
(both sides on a flat field, Skilled against Average on a hill, Average
against Skilled on a woods map, a Skilled attacker and a Skilled defender
of a walled city) are identical on repeat, diverge for another seed and
use their Skilled behaviours ("skilled" coverage); the flat, woods and
both city runs are in the snapshot round trips. `tests/lockstep_test.gd`:
AI battles with Skilled sides (both on a field; Skilled attacker; Skilled
defender) restored from snapshots at three points run on identically; two
peers against a Skilled enemy, with a third joining mid-battle by
snapshot, are hash equal on every frame.

**Tools.** `matchups --fair-forest=N` (woods on the mirrored maps) and
`--knob=LEVEL:ID=VALUE` (override one knob for a run: the ablations
above); the settlement plans print the Skilled siege moves with
`--skill`; `benchmark --skill=e|a|s`.

**UI.** Battle AI "Skilled" without "(soon)" on the new-campaign
Difficulty row and the sandbox "AI:" button; the Campaign AI row still
says "Skilled (soon)" (step 4).


## 12. As built: Skilled campaign (step 4, 2026-10-07)

Average and Easy are byte for byte what they were: `campaign_sim --seeds=6
--turns=60` per-seed hashes all-Average (056bfc4c 7e5be9e9 4ddf4d22
27da886c 892fc13f 01cad53e), all-Easy and each faction Easy in turn (54
hashes), and `--format=5`, equal HEAD; `tests/campaign_test.gd` pins an
AI-only Average campaign and one with an Easy faction (20 turns: hash and
`rng` state from the commit before step 4). Every Skilled behaviour hangs
off an `SK_*` knob (`campaign/cai_profile.gd`, ids 75-90) that is 0 for
Easy and Average, so those levels never run it and never draw the RNG for
it (the test checks the column); no code branches on the level. Skilled has
no deliberate mistakes. No state change: no new keys, `CState.VERSION`
stays 6, the AI keeps no memory between turns (everything it reads is
recomputed from the state each turn).

**Same rules, same information.** Skilled reads only the state every
player sees (positions, strengths, stances, sieges, diplomacy, the
enemies' unit lines) and acts only through the orders a player has (move,
move to merge, stance, recruit, build, propose, declare). No income, unit,
movement or sight difference. (As at every level, the AI plans in step 5
of `cturn`, after the players' moves of the turn have been walked: it
sees where they went, never their orders. This is the pipeline's, not
Skilled's.)

**Knobs (SKILLED column; Easy and Average 0 for every `SK_*`).** Average's
values except `SHELTER_PCT` 0 (never shelters inside the walls), `IDLE_WIN`
50 and `SIEGE_ASSAULT_WIN` 50 (no battle under even odds unless a city is
at stake). `SK_SUPPORT` 1, `SK_HUNT_WIN` 75; `SK_RALLY` 2 turns;
`SK_SAFE_WIN` 70, `SK_SAFE_HOLD` 0, `SK_SAFE_GAIN` 15; `SK_STAGE_SAFE` 70;
`SK_INTERCEPT_WIN` 60; `SK_STORM_RELIEF_WIN` 50; `SK_COUNTER_MIX` 20,
`SK_COUNTER_SHARE` 25 %; `SK_WAR_BORDER_PCT` 100, `SK_WAR_WEAK_PCT` 200,
`SK_WAR_GUARDED_PCT` 50; `SK_ONE_FRONT` 1; `SK_REACH_DEF_PCT` 0 (built,
off).

**Behaviours (`campaign/cai.gd`, format 6).**
- Two to one, support counted (4.4): a hunt of an enemy field army counts
  the target's friends that would join as support (`_supporters`: in the
  field, not forced, within `support_r` of its cell, the rules'
  `_support6`) and goes at 75 % odds outside our lands (Average 70 %
  against the lone army: it walks into support). Counted: attacks at
  twice the defence or more, hunts called off for the support.
- Concentration (4.2, 4.4): spare armies (nothing else to do this turn)
  within two turns of our strongest army march to merge into it while the
  two fit in one army (a "join" move, the order players have), else to
  stand by it within support range (`_rally`); the armies arriving
  together then merge at the start of the next turn. Gathering points for
  an attack (Average's "a march short") are taken further back when the
  enemy could fall on the gathering armies there next turn at 70 % odds
  (`SK_STAGE_SAFE`, from `_danger`); the armies then strike together
  (counted when two or more attack one settlement in the same turn).
- Reading the enemy (4.10, 4.9): `_foes6` / `_danger` estimate, for any
  cell, every enemy field army that can reach it next turn (the hunters'
  own estimate: 13 points a cell + 10) against our army there and our
  armies within support range, stances counted. A free army (not holding
  a threatened city) the enemy could attack at 70 % falls back to the
  friendly field cell or army it reaches this turn where the odds are at
  least 15 points lower (`_fall_back`).
- Sieges and relief (4.6): a siege of ours is stormed at 50 % odds when a
  relief army can reach the city next turn (`_relief_soon`; Average waits
  for the ratio or starvation); an army that can relieve a city we besiege
  is hunted at 60 % (intercept in the field).
- Composition (4.2): recruitment's mix gains +20 for spears (or pikes)
  when cavalry is at least 25 % of the enemies' units, +10 for archers /
  javelins against light foot (`_counter_mix`; lines the faction does not
  field are not added; no artillery: see below).
- Diplomacy (4.3, 4.8): war on an eligible neighbour (Average's ratio and
  pacing) is twice as likely when its field armies that can reach our
  settlements next turn are at most as strong as ours that can reach its
  own (`_border_weak`), half as likely otherwise. At war on two fronts or
  more it offers peace to every enemy but the one whose regions its armies
  reach most (`_one_front`; the other side answers by its own rule, a
  player is asked).

**Measurement** (`campaign_sim --seeds=6 --turns=60 --skill-f=<faction>:s`,
one faction Skilled at a time, the others Average; regions at 15 / 30 / 60,
mean of 6 seeds, eliminations by turn 60 with the turn; the Average and
Easy columns are the same seeds at HEAD):

| faction | all Average | that faction Easy | that faction Skilled |
|---|---|---|---|
| Rome | 6.5 / 6.8 / 3.7, 2 out (31, 57) | 4.3 / 2.7 / 4.3, 1 out (19) | 6.8 / 7.7 / 9.5, 1 out (41) |
| Carthage | 5.5 / 5.0 / 7.2, 1 out (21) | 4.7 / 3.3 / 4.7, 3 out | 5.5 / 6.5 / 10.2, 0 out |
| Macedon | 2.3 / 2.8 / 4.5, 4 out | 3.2 / 4.3 / 8.7, 0 out | 2.3 / 2.7 / 4.2, 2 out (17, 19) |
| Epirus | 1.5 / 1.0 / 0.0, 6 out | 5.5 / 5.3 / 7.2, 1 out (33) | 2.8 / 1.5 / 0.7, 5 out |
| Greeks | 5.2 / 5.7 / 7.8, 2 out (41, 34) | 3.8 / 4.8 / 7.7, 0 out | 4.8 / 6.2 / 10.2, 0 out |
| Syracuse | 3.2 / 3.8 / 1.5, 5 out | 3.0 / 2.0 / 0.7, 4 out | 3.0 / 3.3 / 3.8, 1 out (51) |
| Iberians | 5.0 / 4.7 / 3.7, 2 out (50, 31) | 4.3 / 4.8 / 6.5, 1 out (33) | 5.0 / 4.5 / 5.3, 1 out (26) |
| Gauls | 5.0 / 5.7 / 7.3, 0 out | 5.2 / 5.5 / 5.7, 0 out | 5.5 / 5.0 / 7.5, 2 out (54, 24) |
| all 48 runs | 4.27 / 4.44 / 4.46, 22 out | 4.25 / 4.10 / 5.67, 10 out | **4.48 / 4.67 / 6.42, 12 out** |

The same with 24 seeds (1000 + 77k, k < 24; 192 runs a column), which is
what the design decisions below were measured on (standard error of the
turn-60 mean about 0.3 regions):

| faction | all Average | that faction Skilled |
|---|---|---|
| Rome | 6.0 / 6.2 / 5.3, 6 out | 6.3 / 7.6 / 10.2, 1 out |
| Carthage | 5.7 / 7.0 / 9.2, 3 out | 5.2 / 6.9 / 9.5, 1 out |
| Macedon | 2.8 / 3.2 / 4.0, 10 out | 2.8 / 2.9 / 3.7, 8 out |
| Epirus | 1.7 / 1.0 / 0.5, 18 out | 2.7 / 1.9 / 1.1, 15 out |
| Greeks | 4.8 / 5.4 / 6.9, 4 out | 4.8 / 6.5 / 10.7, 1 out |
| Syracuse | 3.1 / 3.4 / 2.1, 14 out | 3.1 / 3.7 / 4.2, 6 out |
| Iberians | 5.0 / 4.1 / 3.0, 9 out | 5.0 / 5.1 / 6.8, 2 out |
| Gauls | 5.2 / 5.2 / 4.8, 6 out | 5.8 / 5.0 / 6.4, 7 out |
| all | 4.30 / 4.45 / 4.48, 70 out | **4.47 / 4.95 / 6.58, 41 out** |

Target (+30 % regions at turn 60, fewer eliminations, no faction worse):
**+47 %** (24 seeds; +44 % on 6) and 41 eliminations against 70. Rome,
the Greeks, Syracuse and the Iberians end clearly larger, the Gauls
larger (with one more elimination in 24 runs), Carthage and Epirus a
little larger, **Macedon not**: 3.7 regions against 4.0 at turn 60 (fewer
eliminations, 8 against 10), within its noise (one faction's 24-run
mean: about 0.6) but not better. Most of the gain comes late (turn 15
+4 %, 30 +11 %, 60 +47 %): Skilled factions survive their early wars and
keep growing. Skilled against Easy (the same faction Easy): larger
overall (6.42 against 5.67) and in five factions, but Easy Macedon,
Epirus and the Iberians end larger (Macedon and Epirus far larger): for the weak
eastern factions Easy's blunt aggression (wars at 100 %, no peace,
storming on arrival) wins more than Skilled's care; Easy's own target
(smaller than Average) was already not met in step 2.

Battles and captures of the watched faction (24 seeds, the 8 factions'
192 runs summed; Average / Skilled): field battles attacking won 186 /
197, lost 99 / 45; defending won 99 / 240, lost 186 / 628; settlements
stormed 1,169 / 1,435 (lost 182 / 267); settlements defended won 125 /
101, lost 885 / 749; armies destroyed 270 / 107; turns at war on two
fronts 2,205 / 1,952. Every region changes hands by storm: no AI siege
ran to a surrender at any level. Skilled loses more field battles as a
defender (its armies stand fortified outside a threatened city instead of
inside it) but far fewer armies, fewer regions, and takes more.

Counters (`CP.count`, 24 seeds, the 8 Skilled factions): attacks at
twice the defence (support counted) 546, hunts called off for the
target's support 354, relief intercepts 5, timed arrivals (two or more
armies storming together) 481, merges into the main army 656, armies
sent to stand by it 3,971, fall-backs from danger 137, storms before a
relief 28, attacks at bad odds 0, deliberate mistakes 0.

**What decided it (ablations, 24 seeds, turn-60 regions and
eliminations of the Skilled faction; Average 4.48, 70 out).**
- Sheltering inside the walls is Average's worst habit: Average with only
  `SHELTER_PCT` 0 ends at 5.25 (52 out), with no stances at all 5.35;
  every Skilled variant with sheltering back fell to 4.4-5.5 and 63-73
  out. An army inside a city is lost with the city (88 % of attacked
  settlements fall: the attacker only comes at 130 %); outside, fortified,
  it adds its zone and support and survives a defeat. So Skilled never
  shelters (the design's "shelter a weaker army inside walls and sally
  with support" is switched off, `SHELTER_PCT` 0).
- One front at a time: without it 5.94 / 52 out, with it 6.11 / 46 (turns
  on two fronts 2,276 against 1,371 before the war timing).
- War timing: a hard rule (no war unless their border is weak) cost
  conquests (6.11 against 6.43 without); as a preference (x2 / x0.5) 6.86
  / 38 out, the largest single step after sheltering.
- Support-aware hunting: without it 6.24 against 6.43 (both without the
  war timing): small, kept. The rally: within noise either way (6.86 /
  42 out without it, 6.86 / 38 with it; it is the "merge before
  campaigning"), kept at 2 turns (1 turn: 6.60).
- Falling back with armies that hold a threatened city: 4.94 / 60 out
  (the city falls): `SK_SAFE_HOLD` 0; free armies only (5.97 against
  5.91 without).
- Staging out of reach, storming before a relief, the 50 % floor and the
  counter-composition were each within noise (6.53, 6.81, 6.69, 6.24 with
  each off, against 6.58 with all); they are the competencies the design
  asks for and cost nothing measurable, so they stay on.
- A target's defence counting the enemy armies that reach it next turn
  (`SK_REACH_DEF_PCT`, "strike where they are not"): at 50 % 5.44, 100 %
  5.70, 25 % 5.93 against 5.97 off: fewer conquests as well as fewer
  losses. Built, off.
- Economy (upkeep share 60, building budget 80 %, no reserve, chest
  shares), attack ratio 110-150, commitment 100-200 %, gathering 50 %,
  screens, relief odds, hunting odds, siege patience 4-5: all within noise
  of the configuration above; Skilled keeps Average's values. Siege
  patience never matters: AI sieges end by storm or lift before it.

**Not built.** Artillery for walled cities (a battery slows an army to
150 points a turn, and the formula that resolves AI battles ignores
composition, so it cannot be measured here; it needs the battle sim);
valuing regions by position (chokepoints, ports) and victory relevance;
positioning so that every approach to a threatened city crosses a zone
of control (the danger model is used for falling back and staging only;
Average's screens and fortify stand); tracking armies across turns
(trajectories: there is no AI memory in the state, and adding one would
change the save format); a war chest and build order by wealth / threat;
coordinating with an ally's wars; sallies with support. Section 5's
personalities and composition styles are step 5.

**Frame cost** (`campaign_sim --seeds=6 --turns=60`, desktop, one process):
every faction Average 17.1 ms a turn (worst 28.8, first turn 130 for the
memoised distance fields), every faction Skilled 23.5 ms (worst 37.3):
about 0.8 ms per Skilled faction-turn. The Skilled reads are per army
against the enemy armies (no per-cell search beyond Average's): hunting
and danger O(ours x theirs), the border test O(armies x regions) per war
candidate.

**Determinism.** `tests/campaign_test.gd` (`_ai_skilled`): with every AI
faction Skilled and a player, the same inputs give the same state after
16 turns, a save / load in the middle changes nothing, one turn from the
same state and submissions gives the same hash, the state stays plain
(ints, strings, arrays, dictionaries), Skilled plays differently from
Average; in 40 AI-only turns the Skilled behaviours run (two to one,
hunts declined, timed arrivals, merges, rallies, fall-backs, all above
0) and no mistake is made; the `SK_*` knobs are 0 at Easy and Average;
`factions[f].ai_skill` overrides `settings.ai_campaign_skill`.
`campaign_sim --skill=skilled --twice` is deterministic.

**Tools.** `campaign_sim --knob=LEVEL:ID=VALUE` overrides one knob for a
run (`CP.set_knob`, test only; the ablations above), and for each faction
with a skill set it prints and sums its battles (field / settlement,
attacking / defending, won / lost), regions gained and lost (and lost
within 3 turns of taking them) and armies destroyed.

**UI.** New campaign: "Campaign AI: Skilled" without "(soon)"; the
tooltip says what it does. Per-faction overrides (Advanced) are step 5.

## 13. As built: siege equipment and wall towers (2026-10-07)

The settlement AI uses and answers the siege gear of docs/DESIGN.md
"Siege equipment and wall towers" (`sim/siege_ai.gd`, section "siege
equipment, towers"). It runs only in battles with towers, ladders or a ram
(`sim.sg_on`), so every other battle plays and hashes as before. New knobs
(`sim/ai_profile.gd`, Easy / Average / Skilled; personality offsets 0):

| Knob | E / A / S | What |
|---|---|---|
| `S_LADDER_UNITS` | 1 / 2 / 3 | attacking foot units carrying ladders sent up (heavy, light, spears; then by index) |
| `S_LADDER_DEF_W` | 0 / 1 / 3 | stretch choice: metres from the gate + this per defender on the walls within 40 m (and x 60 per working tower within 60 m) |
| `S_LADDER_AFTER` | 0 / 1200 / 1200 | ladders go this many ticks into the approach, or once the gate is below 85 % |
| `S_LADDER_WALLS` | 1 / 2 / 2 | with working artillery, ladders only against walls of this level or more (without: any) |
| `S_TOWER_FOCUS` | 0 / 1 / 1 | towers pick the ram, batteries, men at a gate / on ladders / up on the walls (else fire at will) |
| `S_COUNTER_BAT` | 40 / 60 / 90 m | attacking batteries shoot working towers this near the gate before the gate |
| `S_ESC_REPLY` | 0 / 1 / 1 | a reserve foot unit is sent up onto every stretch with ladder men on it |
| `S_RAM_WAIT` | 0 / 0 / 900 | the ram waits (out of reach) for the towers within 40 m of the gate to be silenced, at most this long |

Modes (`u_ai`): `A_RAM` 30, `A_LADDER` 31 (kept once given: climbing, then
down into the town to the inner face of the nearest closed gate to unbar
it, storming when none is left), `A_TOWER` 32, `A_ESC` 33 (a defender sent
against ladder men; `u_ai_y` = the attacking unit; once they are gone it
comes down to the foot of its stair as a reserve). With a ram that can
still work a gate no foot hack at it. Counted in `C_SIEGE` (ladder orders,
the ram sent, replies). Measured: docs/STATUS.md (fair-sieges table).

## 14. As built: street fights (2026-10-07)

Units no longer pass through each other (docs/DESIGN.md "Unit blocking and
street fights"). The battle and settlement AI needed no change to work
with it: their attack orders queue behind friends already fighting the
target (the reserve waits behind the line), moves pass through friends at
half speed, and paths never target ground a unit cannot reach (as
before). New knobs (`sim/ai_profile.gd`), on for Skilled only:

| Knob | E / A / S | What |
|---|---|---|
| `S_BREACH_HOLD` | 0 / 0 / 1 | once a gate is open or broken with attackers within 100 m, the reserve foot unit nearest each of two posts inside the wall either side of it holds that post (`A_BREACH` 34, `u_ai_x` / `u_ai_y` the post; the defending side's `ai_gate` remembers the gate) |
| `S_BREACH_LAT` | 14 / 14 / 14 m | ... the posts this far along the wall from the gate's middle (open ground of the town, up to 8 m in) |
| `S_BREACH_REACT` | 22 / 22 / 22 m | ... and they attack attackers this close to their post (those coming out of the gateway), else go back to it facing the gate |
| `S_GUARD_JOIN` | 0 / 0 / 120 m | ... and the guards of the other gates with no attacker this near their gate become reserves posted behind the breach (30 m in, 12 m apart; the plaza if that is not open ground) |

Tried at Average in the equal-force sieges (`--knob=a:216=1 --knob=a:219=122880`,
10 seeds a row): walls 1 ring 100 / 100 % either way, polis 80 / 100 %
(100 / 100 without); walls 2 ring 30 / 70 % (60 / 60), walls 3 ring 0 /
10 % (30 / 10), with more draws. The defenders killed more attackers
(ring walls 1: 372 against 269) but the breach holders, two or three units
against the whole assault, died at the gate. Left on for Skilled as a
Skilled habit; Easy and Average play as without them.

## 15. Siege equipment knobs (part 2b, 2026-10-07)

Ladders and the ram are objects any attacking foot unit carries, plants
or batters with, and drops (docs/DESIGN.md "Siege equipment and wall
towers"). `sim/siege_ai.gd` assigns the ram to the least street-worthy
foot unit (pikes first) and ladder sets to the heaviest infantry, up to
`S_LADDER_UNITS` including planted sets; `S_LADDER_FOLLOW` (0 / 1 / 1)
sends that many extra infantry up each planted set; `S_LADDER_AFTER` is
300 ticks (carrying is slow); `S_CIT_WAIT`: at a shut walls-2/3 gate with
no ram the AI waits 50 m out instead of hacking (iron gates ignore
swords at every level). Skilled's wait-for-towers rule is unchanged.
