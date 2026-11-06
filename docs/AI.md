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

As built (2026-10-09): pursuit is a unit move, not something the men do on
their own. Fighting men keep within 1.5 m of their places (docs/DESIGN.md
"Ranks hold together in melee"), so a unit only follows routers when its
attack order targets a routing unit; the sim then runs its anchor after
them. The AI needed no change: foot already re-target the nearest formed
enemy when theirs routs and attack routers only when none is nearer (the
Easy "chase" mistake sends them after a nearer router on purpose), cavalry
ride routers down by attack order (pairs at Skilled), and missiles out of
ammunition and storming foot attack routers by order. Units with no attack
order (holding, waiting in reserve) no longer lose men to a chase.

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
- Trust-driven answers and AI alliances (state format 10, 2026-10-26;
  `campaign/cdip.gd`, `docs/design/campaign_rules.md` "Diplomacy: trust,
  alliances and passage"): `CAI.why` scores an offer as regard[to][from] +
  repute[from] (wars declared, cities taken, sacks, trespass, calls refused,
  cancelled trade and gifts move them; both fade a point a turn) and needs
  a floor per treaty: trade 0 (before its old timing and strength tests),
  passage 10, alliance 25 (+25 when both are at war with one faction) and
  the answering AI threatened (at war, or a stronger neighbour that is not
  friendly), a team allied with regard 50 and a battle fought together.
  An ally's call to arms (a defensive pact: only the attacked side's allies
  are called) is joined while the AI has fewer than MAX_WARS
  wars and WAR_RATIO_BUSY % of the enemy's strength, else refused at a
  cost. The AI never starts a war on a faction it regards 30 or more and
  doubles its chance on one it regards -30 or less, and weighs a target
  with its allies that would answer a defensive call (`bloc_strength`); it answers a trespasser
  it regards below -40 with war. A threatened AI with fewer than ALLY_MAX
  (2) allies proposes an alliance ALLY_PROPOSE % a turn (Easy 0, Average
  15, Skilled 25) to the neighbour it regards best that is at war with
  none of its side; with the creation setting `ai_alliances` 0 it asks
  only players. Old formats (an unmigrated online campaign) keep the old
  rules.
- Wars the AI can cover (format 10, 2026-10-27, section 43; Average and
  Skilled, Easy unchanged): no war while a region of ours that the
  target's armies (or a current enemy's) reach next turn holds less than
  WAR_COVER_PCT (50 / 60) % of that strength; a trade partner needs
  WAR_RATIO x WAR_PARTNER_PCT (105 / 110) % and, Skilled, no other war on;
  a second war only while every war is winning; stretched (two wars or a
  region lost in 5 turns) the war won least asks peace below
  STRETCH_PEACE_PCT (100) % of the enemy after PEACE_MIN_TURNS.
- The Miskito's pacing (2026-10-29, no AI rule changed): traced on 72 West
  seeds at format 10, the Miskito's 21 eliminations were all wars the
  neighbours declared (Tierra Firme 14, New Spain 6, France 1) with the
  English alliance standing; `bloc_strength` counts England's strength in
  the deterrence while `why "call"` refuses it as too weak, and letting
  the call count the caller's strength too (tried) raised the deaths to 27.
  Fixed in the data, not the AI: a Miskito army at Talamanca at the start
  (21 -> 7 at format 10, 18 -> 12 at format 6; campaign_rules.md "Diplomacy
  ... as built"). `campaign_sim --trace-faction` now prints the route of each
  capture (sea if the capturer landed there in the last 8 turns) and
  "ALLIANCE LOST ally: reason".

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
- Fog of war (state format 8, 2026-10-17, owner's decision; replaces the
  2026-10-06 "AI obeys fog of war"): the campaign AI sees everything; it
  never reads `campaign/csight.gd`, which only limits what players are shown.

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

**Field rebalance (2026-10-09; `--fair=20`, 40 battles each, flat).**
After "ranks hold together" (DESIGN.md) the numbers above no longer held:
Skilled vs Average 60 %, Average vs Easy 67.5 % (3 draws), the Average
mirror 22-17-1 at 8.4 / 15.0 min mean / max. The rebalance (to-hit 40,
flank / rear +35 / +50, the wrap at the anchor level, bolts pin, and here:
a missile unit that fell back out of ammunition and still has no wagon,
woods, engines or routers near withdraws instead of standing at its own
edge, which kept beaten armies on the field to the limit) gives: Average
mirror 20-20-0, 7.1 / 12.2 min; Average vs Easy **77.5 %** (1 draw);
Skilled vs Average **40 %** (55 % before the flank / rear bonus went up:
below the 65 % target, not fixed; Skilled's reserves and rotation seem to
cost more than they gain once melee is faster). Knobs `WG_EMPTY_PCT`,
`AK_WAVER_PCT` and the 60 m take-up radius were kept.

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
values except `SHELTER_PCT` 0 (never shelters inside the walls; back to
Average's 70 on 2026-10-10 once the formula's walls term covers the
armies inside, section 26 / CAMPAIGN.md "The formula"), `IDLE_WIN`
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

### 12.1 Addendum: odds as win chances (2026-10-22)

The auto-resolve refit (`campaign/cbattle.gd`, commit c94d4a9: `WIN_EXP` Rome 10 / West 7, was 3) made the formula's
win curve much steeper, so the strength ratios the AI attacked with no longer meant what they did on the cube law:
130 % of the defence estimate (`ATTACK_RATIO6`, Average and Skilled) was a 69 % chance on the cube and is 93 % (Rome) /
86 % (West) now. Format 6 (the overworld; every current campaign) now decides on the formula's own output, the
attacker's win chance (`CBattle.odds_of`), so a threshold keeps its meaning when the curve is refitted again. Formats
1-5 keep their ratios.

**The thresholds** (`campaign/cai_profile.gd`; ids 101-105 new; a retreat threshold on the enemy's chance is 100 less
ours):

| Knob | Easy | Average | Skilled | Was (E / A / S) |
|---|---|---|---|---|
| `ATTACK_WIN` assault / storm a siege / sally / land from a fleet at our chance | 45 | 55 | 65 | ratio 110 / 130 / 130 % |
| `COMMIT_WIN` armies sent (strongest first) until our chance reaches | 45 | 85 | 90 | 100 / 130 / 130 % of the ratio |
| `SIEGE_WIN` lay siege (more armies coming) at our chance against the full kit | 45 (assaults) | 30 | 35 | 50 % of the ratio |
| `IDLE_WIN` an idle army takes a target at | 45 | 55 | 65 | 20 / 35 / 50 |
| `RELIEF_WIN` relieve a besieged city; hunt in our own lands at | 45 | 55 | 65 | 60 / 60 / 60 |
| `HUNT_WIN` / `SK_HUNT_WIN` hunt a field army at (unchanged) | 50 | 70 | 75 (support counted) | same |
| `SK_INTERCEPT_WIN` hunt a relief army at | - | - | 65 | 60 |
| `SK_STORM_RELIEF_WIN` storm a siege before a relief at (unchanged) | - | - | 50 | same |
| `LIFT_WIN` lift a siege when the relief's chance reaches (ours below) | 80 (20) | 70 (30) | 65 (35) | 101 / 50 / 50 |
| `SIEGE_ASSAULT_WIN` at the end of patience storm, else lift, at | 0 (always) | 30 | 35 | 0 / 35 / 50 |
| `SK_SAFE_WIN` / `SK_STAGE_SAFE` fall back / stage elsewhere when the enemy's chance reaches (ours below) | - | - | 65 (35) | 70 |
| `SCREEN_WIN` an army screens a threatened city when its chance standing fortified is at least | 20 | 30 | 35 | 80 % of the threat |
| `SHELTER_WIN` shelter inside the walls when that chance is below | 20 (no stances) | 30 | 0 (never) | 70 % of the threat |

Attack at 45 / 55 / 65 %, retreat below 20 / 30 / 35 %. The aggression setting (Calm 70, Normal 100, Aggressive 130)
shifts every threshold by 10 points (`CAI._thr`: our chance needed, -10 when aggressive; `_thr_foe`: the enemy's
chance that makes us retreat, +10); a knob of 0 (off) or above 100 (never) is not shifted. It no longer scales a ratio.

**How the chance is computed.** An attack on a settlement (`_attack6`, `CAI._odds_on`): the formula's strengths of the
armies against the settlement's defenders (garrison, armies at the site, ground, walls against no kit: a storm on
arrival), plus what the AI's defence estimate adds (half the hostile armies in the land neighbours, `SK_REACH_DEF_PCT`
when on). Assault with the armies there now when their chance is at least `ATTACK_WIN`; but when a siege is possible
(more armies a turn away or two here, at least `SIEGE_WIN` against the full kit) the AI storms on arrival only from
`COMMIT_WIN`, else it lays siege (the old order: a siege below the overwhelming storm). Else it gathers a march short
when the armies there and a turn away together reach `ATTACK_WIN`, and otherwise musters (holds, recruits, rallies:
the frontier march and the mustering rule as before). A siege of ours is stormed at `ATTACK_WIN` with the kit the
siege has built (`_storm_win`, `CBattle.kit_of`; it used the no-kit odds before), a sally from a besieged city of ours at
`ATTACK_WIN` (field odds), a landing from a fleet (`cai_fleet.gd _landing`, was `LAND_PCT` 110) at `ATTACK_WIN` on the
estimate. Screening and sheltering read `_stand_win`: our chance standing fortified (`FORTIFY_DEF_PCT`, the field
defender's edge) against the threat. Easy keeps its designed habits below its threshold: the one-roll-a-turn mistake
at bad odds (`M_BAD_ODDS`), armies sent piecemeal without gathering (the first arrives alone), and a siege at the end
of patience is always stormed (committed).

**Skilled never shelters** (`SHELTER_WIN` 0, as at step 4 before 2026-10-10): the refitted walls give the armies inside
no more than the field (Rome `WALLS_PCT` 93 / 87 / 96 at walls 0-2), and the ablation says so: Skilled vs Average,
24 seeds mixed, with Skilled sheltering at 35 % Rome 5.32 / 3.55 regions, West 6.07 / 6.16; never sheltering Rome
6.04 / 2.80, West 6.33 / 5.91.

**Measurement** (`tests/ai_odds_probe.gd`: AI-only campaigns as `campaign_sim` plays them, the decision log
`CP.log_on` outside the state; every faction at one skill, 12 seeds x 60 turns, seeds 1000 + 77 n; "attacks" are the
launched assaults, storms, hunts, idle attacks and Easy's rushes and mistakes that met a battle that turn, actual won %
of those fought; HEAD -> after):

| | Easy Rome | Easy West | Average Rome | Average West | Skilled Rome | Skilled West |
|---|---|---|---|---|---|---|
| attacks (fought won / lost) | 1492 / 592 -> 1398 / 680 | 1323 / 745 -> 1370 / 759 | 618 / 57 -> 569 / 45 | 643 / 30 -> 652 / 94 | 611 / 29 -> 801 / 51 | 617 / 18 -> 758 / 56 |
| mean predicted / actual won % | 83 / 72 -> 83 / 67 | 71 / 64 -> 72 / 64 | 97 / 92 -> 96 / 93 | 94 / 96 -> 94 / 87 | 98 / 95 -> 98 / 94 | 96 / 97 -> 95 / 93 |
| launched under 55 % predicted | 640 -> 650 | 847 -> 908 | 13 -> 0 | 37 -> 0 | 11 -> 1 | 14 -> 2 |
| refused that the formula would win > 70 % | 113 -> 98 | 140 -> 115 | 162 -> 82 | 179 -> 42 | 91 -> 96 | 229 -> 44 |
| sieges started / taken / lifted | 0 | 0 | 72 / 42 / 27 -> 65 / 48 / 16 | 105 / 80 / 21 -> 65 / 44 / 20 | 109 / 76 / 31 -> 38 / 23 / 14 | 94 / 83 / 9 -> 44 / 31 / 13 |
| armies destroyed | 141 -> 85 | 72 -> 53 | 104 -> 128 | 76 -> 74 | 130 -> 66 | 74 -> 23 |
| field battles | 1351 -> 1391 | 779 -> 944 | 157 -> 112 | 61 -> 62 | 104 -> 309 | 33 -> 217 |
| battles a campaign | 192 -> 191 | 177 -> 184 | 57.2 -> 52.2 | 55.2 -> 62.0 | 53.7 -> 68.9 | 52.3 -> 67.7 |

Predicted chances are bimodal (the
curve is steep: 30-70 % is a strength ratio of 0.92-1.09 in Rome), so most launched attacks sit at 95-100 % at every
level; the thresholds move the edge. By predicted band, after (launched / actual won %): Average Rome 55-64 21 / 95,
65-79 42 / 60, 80-94 135 / 90, 95+ 791 / 94; Average West 55-64 61 / 47, 65-79 87 / 70, 80-94 215 / 82, 95+ 953 / 96.
Average and Skilled now launch nothing under their threshold but a starving siege's storm with a relief near; Easy's
attacks under 45 % are its mistakes and piecemeal arrivals. Skilled campaigns fight far more field battles (its armies
stand fortified outside instead of inside), lose half the armies and fewer sieges are laid (the AI storms on arrival
from 85-90 % where it used to lay siege up to 93 %).

**Pacing at Average** (the `campaign_sim` pin set, 6 seeds x 60; 12 and 24 seeds for the noise; the band of the roads
row: 40-60 battles a campaign, no faction out before turn 10 in more than 1 of 6, Macedon out in at most 3 of 6):

| | Rome HEAD | Rome after | West HEAD | West after |
|---|---|---|---|---|
| battles a campaign, 6 seeds (range) | 54.2 (46-59) | 51.0 (43-69) | 58.0 (36-82) | 64.3 (48-105) |
| 12 / 24 seeds | 57.2 / 56.5 | 52.2 / 54.1 | 55.2 / 53.8 | 62.0 / 60.0 |
| eliminations, 6 seeds | 15: mace 5, epir 3, gaul 3, syra 2, gree 1, iber 1 | 15: epir 5, syra 5, cart 1, gaul 1, gree 1, mace 1, rome 1 | 6: bret 2, itza 2, misk 2 | 5: bret 2, itza 2, engl 1 |
| Macedon out, 6 / 12 / 24 seeds | 5 / 8 / 14 | 1 / 6 / 11 | - | - |
| out before turn 10 | 0 | 0 | 0 | 0 |
| largest faction at 60 (mean) | 11.2 | 12.0 | 16.7 | 16.8 |

Rome is back in the band (Macedon 1 of 6; Carthage out once in 6). West is at its top: 60.0 a campaign over 24 seeds,
the 6-seed pin set 64.3 because of one seed (1308, 105 battles: two AIs taking one border town back and forth); the
median is 57.5. Two variants tried for it (Average `SIEGE_WIN` 20, `COMMIT_WIN` 95) moved the 12-seed mean by less
than its noise (about 4 battles) and were not kept.

**Skilled against Average** (`ai_odds_probe --mixed`: per seed every other faction Skilled, each faction plays both;
24 seeds, 96 faction-seeds a skill; regions at turn 60, eliminations):

| | Rome Average | Rome Skilled | West Average | West Skilled |
|---|---|---|---|---|
| HEAD | 4.08, 36 out | 4.75, 31 out | 5.67, 10 out | 6.56, 13 out |
| after | 2.80, 38 out | **6.04, 29 out** | 5.91, 11 out | **6.33**, 16 out |

Skilled beats Average in both packs; in Rome by far more than before, in the West by less (+0.42 regions, a standard
error of about 0.6, and more eliminations). The West's flatter curve makes Skilled's 65 % cost more tempo: with Skilled
at 60 % the West reads 6.61 / 5.64 (10 / 16 out) and Rome 6.72 / 2.19; at 55 % (Average's) 6.46 / 5.78, Rome 4.95 /
3.86. Kept at 65 as briefed; 60 is the lever if the West's margin should grow.

**Guard rails.** `campaign_sim` 6 x 60 re-pinned (STATUS pins), `--twice` deterministic both packs; `campaign_test`
(the Average / Easy goldens as format 7 `519bcec8` / rng 2959563086 and `9f1555b0` / 3720338208; new
`_ai_odds_thresholds`: the table above, the aggression shift, the attack's chance is the formula's); `pack_test`
`ROME_20` `91b91238`, V7 `4a93a2f1`; `campaign_input_test` (Rome) and `check_scripts` pass. Online clients compare
the rules hash: `campaign/` changed.

### 12.2 Garrisons against landings (2026-10-23)

With the Rome pack's fleets (R2) Syracuse fell in 6 of 6 `campaign_sim` seeds (5 before turn 20) and the Greeks and
Macedon more often: the AI's threat to a city counted only the enemy armies that could march to it, so a coastal city
looked safe while a Punic fleet lay a day's sail off with an army beside it, and an army crossed a sea lane (Rome:
`LANES_FOR_ARMIES`) or boarded a fleet leaving its cities bare. The format-6 AI (`campaign/cai.gd`,
`campaign/cai_fleet.gd`) now counts the sea the way it counts the land; integers, the state only, index order, no RNG.

- **Landing threat** (`CAI._sea_threat`, in `_context6`: cx `"sea"` added to `"thr"`): for each coastal region of
  ours (`CFleet.beach`), every hostile fleet whose straight-line voyage to the beach at its pace (the fleet AI's
  `_turns`) ends within `SEA_GUARD_TURNS` turns after this one adds what it can land there: the troops it carries,
  plus `SEA_LIFT_PCT` of the strongest army of its side that fits its free room and can board, one beside it
  (`CFleet.near_fleet`: aboard and away this turn, the fleet AI's own transport) or within a turn's sail of it (fetched,
  lands a turn later). Fleets at war count in full; Skilled also counts `SEA_PEACE_PCT` of a fleet of a faction merely at
  peace with it (no trade, no alliance: a likely war). The flota and story fleets do not count. The same pass gives cx
  `"far"`: the threat a turn later still.
- **Holding** (`_hold`): an army in a city of ours stays when the city's defence without it is below the threat,
  now landing threat included (counted `sea_garrisons` when the landing threat alone holds it).
- **Leaving the landmass** (`CAI.needed_home`, `SEA_AWAY_PCT`): an army may not plan anything on another landmass
  (its etas there are set to never: no attack, siege, idle target or frontier march across a sea lane) nor be picked
  by the fleet AI for transport, while some region of ours on its landmass that it reaches this turn would keep less
  than `SEA_AWAY_PCT` % of its `"far"` threat in defence without it (its garrison and armies in it, plus our other
  free armies that reach it this turn). It cannot be back sooner than the landing it leaves the city to.
- **Ferrying** (`CAIFleet._ferry_safe`, `FERRY_ODDS_PCT`): no army boards, and a loaded fleet does not sail to land,
  while the fleets at war that reach the fleet's cell, the embarkation point or the landing beach and the halfway
  cell of the voyage this turn have more than 100 / `FERRY_ODDS_PCT` times the carrier's power (summed per cell; the
  sea-battle rolls are 85-116 %). A loaded fleet with nowhere safe to land waits, or runs for port when a stronger
  enemy is near (`_danger`, as an empty fleet). Counted `ferries_refused` (with the transports refused by
  `needed_home`).
- **Screens and stances** answer the armies' threat only (`SEA_SCREEN` 0, built, off): with the landing threat in
  them every coastal city drew a screen and the West fought 52 battles a campaign instead of 56.

| Knob (`cai_profile.gd`, ids 106-111) | Easy | Average | Skilled |
|---|---|---|---|
| `SEA_GUARD_TURNS` landings counted within this many turns after this one (`-1` off; leaving counts one more) | 0 | 0 | 0 |
| `SEA_LIFT_PCT` an empty fleet counts this % of an army of its side that can board | 0 | 100 | 100 |
| `SEA_PEACE_PCT` a fleet of a neighbour at peace counts this % | 0 | 0 | 50 |
| `FERRY_ODDS_PCT` ferry only with at least this % of the power of the fleets at war near the route (0 off) | 0 | 80 | 100 |
| `SEA_AWAY_PCT` leave the landmass only while what stays covers this % of the threat a turn ahead (0 off) | 0 | 120 | 150 |
| `SEA_SCREEN` screens and stances answer the landing threat too | 0 | 0 | 0 |

Easy keeps its habits: it holds only against a loaded fleet that can land this turn, and sails and crosses regardless.

**Measured** (`campaign_sim`, all Average; 6 seeds = the pin set, 24 seeds 1000 + 77 k for the noise; eliminations with
the turn; HEAD = the R2 commit):

| | Rome HEAD | Rome after | West HEAD | West after |
|---|---|---|---|---|
| battles a campaign, 6 seeds (range) | 53.2 (45-58) | 49.5 (38-71) | 64.3 (48-105) | 54.5 (45-60) |
| 24 seeds | 53.3 | 50.8 | 62.2 | 56.7 |
| field battles, 6 seeds | 10.0 | 7.5 | 5.3 | 4.5 |
| eliminations, 6 seeds | 20: syra 6 (11, 12, 12, 17, 18, 44), epir 5, gree 4, mace 3, rome 1, gaul 1 | 8: epir 4 (17, 34, 41, 48), mace 2 (45, 46), syra 1 (27), iber 1 (43) | 5: bret 2, itza 2, engl 1 | 8: misk 3, bret 2, engl 1, dutc 1, itza 1 |
| eliminations, 24 seeds | 81: syra 21 (18 before turn 20), epir 20, mace 14, gaul 9, gree 7, rome 5, iber 3, cart 2 | 45: epir 18, mace 7, gaul 6, syra 5 (27-60), iber 4, rome 2, cart 2, gree 1 | 19: itza 9, bret 7, engl 2, misk 1 | 17: misk 6, bret 5, engl 2, dutc 2, itza 2 |
| earliest elimination, 24 seeds | turn 11 (syra) | turn 11 (epir) | 24 | 21 |
| ships launched / sea battles / landings a campaign, 6 seeds | 51.8 / 20.3 / 12.8 | 64.5 / 28.8 / 10.5 | 80.8 / 51.3 / 30.5 | 75.2 / 49.7 / 22.2 |

Ablations (12 seeds, Average): the landing threat alone (holds and screens, without `SEA_AWAY_PCT` and the ferry
rule) made Syracuse worse (12 of 12, 11 of them at turns 8-17: an army held Bruttium against the fleet while the main
army still crossed to Africa and the capital fell by land); `SEA_AWAY_PCT` is what keeps it (3 of 12 at 150, 5 of 12 at 100 with two before turn 20,
6 of 12 at 125); `SEA_LIFT_PCT` 50 let Syracuse fall in 9 of 12; landings counted a turn further (`SEA_GUARD_TURNS` 1)
cost the West about 9 battles a campaign (6 seeds); screens on the landing threat 4 more. Skilled (6 seeds, all Skilled): Rome battles
72.5 -> 57.5, eliminations 10 -> 12 (Syracuse 2 -> 0), landings 11.5 -> 5.7 a campaign; West 69.3 -> 64.5, 8 -> 7,
landings 28.0 -> 18.5. Easy (all Easy, 6 seeds): Rome 180 -> 188 battles, 17 -> 17 eliminations; West 178 -> 200, 9 -> 9.

**Final choice (same day, after the Rome data follow-up: Syracuse's start fleet 2 triremes + a lembos, Rome
`SEA_TRADE_PCT` 50):** `SEA_AWAY_PCT` 120 at Average (Skilled 150, Easy 0). 24 seeds, Rome: battles 46.5, eliminations
63 (15.8 per 6 seeds), Syracuse 8 of 24, none before turn 23; West: battles 60.2, eliminations 18, landings 21.7 a
campaign (150 with the same data: Rome 51.3 battles, 61 eliminations, Syracuse 13 of 24 with three at turn 16; West
56.7, 17). The measured tables above are for 150 before the data change.

**Not reached / open (at 150, before the data change).** Rome's eliminations are now below the 15-18 the pacing aimed at (8 on the pin set, 11 per 6
seeds over 24): Syracuse, the Greeks and Macedon survive, Epirus still falls (18 of 24, from turn 11). The root of
Syracuse's early falls was also its money: from turn 1 a Punic fleet blockades Syracuse's harbour (cheb 3 of its
start dock; 337 of its 910 a turn, `SEA_TRADE_PCT` 100 x `BLOCKADE_CUT_PCT` 75 of Sicilia Orientalis' wealth income)
and its start army and fleet cost 1121 a turn against 577, so the debt rules disband half its army by turn 3 whatever the
AI does; the garrison rules only stop it from walking the rest overseas. A Rome `SEA_TRADE_PCT` of 40 (a data change, tried
and not kept) did not save it either (5-6 of 6 before `SEA_AWAY_PCT` existed). Frame cost: Rome about 30 ms -> 41 ms a turn mean (6
seeds, one process; partly the larger realms and armies alive), West about 54 -> 60 ms.

### 12.3 Docking (2026-10-23)

The fleet AI (`campaign/cai_fleet.gd`, item 9 of its header) docks: at the end of its planning every free fleet with no job
and nothing aboard that lies on the dock of a port of ours (a pirate: a patron's, an ally's too) gets an at-once `fdock`,
and a home voyage (item 7) carries the dock region as the sixth element of its move tuple, so it docks on arriving. Any
voyage the AI plans casts a docked fleet off (`CFleet.execute_moves`); docked enemy fleets are not prey (`_prey`: nothing
to fight behind the mole). No knob; the pins moved (docs/STATUS.md).

### 12.4 Sorties (2026-10-23)

Docking (12.3) halved the AI's sea battles: a docked fleet cannot be attacked, and it never came out against an enemy fleet
lying off its own port. `CAIFleet._sorties` (item 10 of the `cai_fleet.gd` header) runs each turn after the transports and
the landings, before the attacks: for each port (region order) where fleets of ours (a pirate: also at a patron's or an
ally's port) lie docked, the strongest of them (lowest id on ties; docked fleets on one cell are merged by `_merge` at the
start of the act) that is empty, not in a pending battle and at a mean hull of at least `BLOCKADE_HULL` sorties: an fmove
tuple after the target (`tgt` = its id), which casts it off and fights on the way. Targets: enemy fleets at war, not docked
nor busy, within `BLOCKADE_CELLS` + `SORTIE_REACH` of the harbour, that it reaches this turn (straight line at its pace),
out of the storms' cones, along the coast for a coastal fleet. A fleet within `BLOCKADE_CELLS` ("lying off the port", on the
blockade's ground whether or not it holds the blockade) needs `SORTIE_ODDS_PCT`; one beyond it (merely passing) needs
`SORTIE_HUNT_PCT` (0: never). The odds are our fleet's power against the enemy's at the spot (`_sortie_foe`): every fleet at
war with us within `FLEET_ZONE` + 1 of the target, not docked, not busy (`CFleet.sea_battle` gathers the whole zone), times
the target's own port's guns (`PORT_DEF_PCT` + `PORT_WALL_PCT` x walls) when it lies within `PORT_CELLS` of a harbour of its
own. Our side gets no port bonus: the sortie is the attacker, and `CFleet.resolve` gives the bonus to the defender only.
Choice: the port's blockader's fleets (`CSea.blockader`) first, then the others lying off it, then the passing; the weakest
enemy at the spot, then the lowest id. Counted `sorties`. The next turn the fleet follows the ordinary rules (prey, blockade,
home; it docks again when it comes home).

| Knob (`cai_profile.gd`, ids 112-114) | Easy | Average | Skilled |
|---|---|---|---|
| `SORTIE_ODDS_PCT` sortie against a fleet lying off the port with at least this % of the enemy's power at the spot (0 never) | 0 | 110 | 100 |
| `SORTIE_REACH` targets within `BLOCKADE_CELLS` + this many cells of the harbour | 0 | 1 | 2 |
| `SORTIE_HUNT_PCT` ... and against one merely passing (beyond `BLOCKADE_CELLS`) at this % (0 never) | 0 | 0 | 130 |

**Measured** (`campaign_sim` 6 x 60, all Average, the pin seeds; HEAD = the victory-counts / Range commit `3a2dc87`, means a
campaign, eliminations counted over the 6 seeds):

| | Rome HEAD | Rome after | West HEAD | West after |
|---|---|---|---|---|
| battles | 47.3 | 47.5 | 50.8 | 50.8 |
| eliminations (per 6) | 10 | 10 | 1 | 1 |
| sea battles | 10.8 | 10.0 | 27.5 | 27.5 |
| landings | 8.7 | 8.5 | 23.7 | 23.7 |
| sorties | 0 | 0.3 | 0 | 0.8 |

All Skilled (6 seeds): Rome 64.8 -> 65.8 battles, 14 -> 18 eliminations, sea battles 13.0 -> 14.0, 1.0 sorties a campaign;
the West unchanged (78.0 battles, 8 eliminations, 20.0 sea battles; 0.5 sorties, hashes unmoved). Average `SORTIE_ODDS_PCT`
tried at 100 and 90 (`--knob=a:112=`, below the 110 floor, as a probe only): Rome 10.0 / 10.7 sea battles, the West 29.0
(1.7 sorties a campaign); kept at 110.

**Why so few** (probe, all Average, 6 seeds a pack: every docked fleet with an enemy fleet in reach, a turn each): our docked
fleet had 110 % of the enemy at the spot in 3 of 222 cases in Rome and 7 of 91 in the West; it had less than 70 % in 208 of
222 and 73 of 91. An AI fleet only comes to lie off a port when it outguns its guard by `SAFE_PCT` 130 (all the guard's
fleets within `GUARD_CELLS`, docked ones included), and a blockade only holds while the blockader is stronger than the
owner's fleets there, so the fleet off a port is almost never one the port's fleet outguns. The West's few sorties were the
attacks `_prey` (`ATTACK_PCT` 140) would have made anyway: its hashes did not move. The sea battles Docking removed were the
enemy's attacks on fleets now docked, not sorties the docked side declined; this rule does not bring them back.

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

Siege towers (4f.1, 2026-10-09): against walls 2-3 each tower of the
attackers on the ground is given at once (it is slow; no waiting for
ladder time) to the free infantry unit with the most men (`S_TOWER_CREW`
1; Easy 0: the nearest, which may be too few to push it at full pace),
mode `A_LADDER` with the piece, so `_escalade` runs it: pick it up, push
it to the stretch `_ladder_spot` picks (near the attacked gate, few
defenders, not one already taken), plant it, cross, then down to unbar a
gate; ladder parties and the ram go on beside it (towers do not count
against `S_LADDER_UNITS`). A planted tower gets `S_TOWER_FOLLOW` (1 / 2 /
3) more infantry crossing it (`_follow`, shared with ladders). Defenders:
tower engines count a tower's pushers with the ram's (`S_TOWER_FOCUS`,
stones and bolts landing by it batter it); wall missile units with fire
missiles left shoot at the nearest pushing crew in reach (`AK_FIRE_WOOD`,
`_wall_fire_tower`; `ammo_pick` then switches them to the fire kind) and
go back to fire at will once none is.

Light artillery (4f.3, 2026-10-09): batteries whose row has `carried`
(scorpions; never by name) are not gate breakers: `_art_ready` ignores
them, so they neither hold the hackers back nor stop the ladders going up
(`S_LADDER_WALLS`), and they march with the ladder-and-ram army (they walk
at foot pace). In the approach `_att_art` sets them up at
`min(S_ART_OUT, range x S_LART_PCT %)` from the attacked gate (85 %: 136 m
for scorpions; the heavy batteries stay on the 165 m line), spread among
themselves, a clear flat line sought as for bolts; there they shoot the
enemy wall unit nearest the gate within `S_LART_WALL_R` (Average 80 m,
Skilled 120 m) that they reach (`_lart_wall_target`), else the gate. Easy
(`S_LART_PCT` 0) leaves them where they stand, firing at will (also at a
citadel). The field battle AI uses them like any bolt battery; the
campaign AI recruits them through the mixes only (`light_art` 3, Greek and
Syracusan `belly_bow` 3; `CAI.BEAST_LINES`; `CData.no_light_art` /
`campaign_sim --no-light-art` leaves both out), and a mix with
`light_art` builds a Workshop. Gastraphetes are missile foot to both AIs.
Not tuned: whether 136 m is outside the wall archers' reach (it is not
on walls 2-3 with their range bonus).

## 16. Defender layout (part 2c, 2026-10-08)

Why (part 2a's traces): equal-force walls 1 went to the attacker 80-100 %
of the time. About 300 defender men guarded the three gates nobody
attacked and never fought; the reserves marched down the main street into
attackers already spread out inside the gate; the plaza capture then broke
everyone. Code: `sim/siege_ai.gd`, section "defenders: the layout"
(`_layout` and what it calls, `_mouth_unit`, `_plaza_unit`,
`_close_gates`); one sim rule in `sim/battle_sim.gd` (`_rout_gate`, below).

- **Reading the attacked gate** (`_read_gate`, the defending side's
  `ai_gate`): at once for a gate hit in the last 5 s or open / broken with
  attackers within 100 m; otherwise (`S_READ_R` > 0) the gate the attackers'
  army points at (`_field_gate`): every ready attacking unit counts its
  strength for the outer gate nearest it within `S_READ_R` (a battery or
  foot ordered at a gate: that gate, twice; a unit carrying the ram or
  ladders: the gate nearest where it goes, twice; each planted ladder set a
  quarter of the army for the gate nearest it), and a gate holding
  `S_READ_PCT` % of the army for `S_READ_TICKS` is read. A gate still under
  attack stays the attacked one. In the walls-1 fair sieges Average reads
  it at 10 s; the gate falls 50-230 s later. `ai_lay` (per side: the gate the field
  points at and since when) is new hashed state on settlement maps.
- **The stack** (`A_MOUTH` 34, `u_ai_x` the gate, `u_ai_y` the place; was
  part 2a's `A_BREACH`): at the read, the reserve's foot and the attacked
  gate's guard, nearest first (spears count 10 m, light foot 40 m further,
  and 1 m per man under 100: heavy foot and pikes of full strength in
  front). Place 0, the front, stands `S_MOUTH_IN` inside the wall's inner
  face on the gate's axis, `S_MOUTH_W` wide, facing out (Skilled
  `S_MOUTH_BACK` further in while the gate is shut, out of the shots at it);
  its men fight whoever comes through the gateway (it is never given an
  attack order: an attack would draw it into the gateway). The others stand
  one behind the other inward (each unit's depth + 3 m; where that is not
  open ground, along the way from the gate to the plaza) and attack the
  nearest attacker out of the gateway (inside the wall's inner face) within
  `S_MOUTH_REACT` of the front's post. Units that rally, come down from a
  wall or back from a wall reply join the tail. Wall units over the gate
  stay up while the front stands (they came down with attackers within 40 m
  in the town); idle wall missile units shift to the stretches by the gate
  (`S_WALL_SHIFT`, Skilled's old `SK_WALL_SHIFT`, now without Skilled
  memory: `u_ai_x` = stretch + 1 in transit).
- **Quiet gates** (`_pull_guards`, `S_GUARD_JOIN`): a gate not hit for 30 s
  with no attacking foot within `S_GUARD_JOIN` nearer it than any other
  outer gate is quiet; its guard joins the stack's tail and leaves a token
  (`A_GATE`, `u_ai_x` 1): a rider of ours not fighting, else the guard
  itself if it has at most `S_TOKEN_MEN` men. A threatened gate with no
  guard but a token gets the stack's last unit (third place or later, not
  fighting) back. In the ring fair siege all three guards (280 men) leave
  at the read (10 s): two stand in their places in the stack 25-35 s
  later, the last (the stack's tail) holds the plaza, the riders are the
  tokens.
- **Plaza reserve** (`A_PLAZA` 35): the riders (not tokens) and, with none,
  the tail of a stack of three or more; they attack any attacker within
  the plaza's radius + `S_PLAZA_REACT` (the capture clock never runs while
  one stands) and otherwise hold the plaza.
- **Relief** (`_relieve`): a front whose morale is under `S_ROT_PCT` % of
  its type's, the unit behind it 15 points above that: the unit behind
  becomes the front and walks up through it (friends pass at half speed, so
  the gateway is never open); the old front (`u_ai_y` -1) holds until its
  relief stands at the post or fights, then goes to the plaza (a foot unit
  holding the plaza, fresher, takes the stack's tail) or to the tail.
  Average does it while the front fights (`S_ROT_LULL` 0); Skilled only
  between waves (`S_ROT_LULL` 1), at 60 %.
- **Gates** (`_close_gates`, `S_SHUT_EMPTY`): an open outer gate with no
  unit of ours within 16 m of its faces is shut (not only with attackers
  within `S_CLOSE_R`); a Skilled sally's gate is shut once the party is out
  of the town and the gate, and a shut gate is opened for units of ours
  back at it with no attacker within 20 m of it and no sally out.
- **Folded part 2a knobs**: ids 216-219 are now `S_MOUTH`, `S_MOUTH_IN`,
  `S_MOUTH_REACT`, `S_GUARD_JOIN` (`S_BREACH_LAT` / `S_BREACH_REACT` and
  the posts either side of the gate are gone; the `--knob=a:216=1` runs in
  section 14 refer to the old meaning). With the layout, Skilled's
  `SK_MIS_DOWN_PCT` (wall missiles down before the gate falls) and its own
  wall shift do not run; `SK_BREACH` finds no reserves to move.
- **Sim rule: routers inside the walls** (`BattleSim._rout_gate`, lever
  `ROUT_INWARD` 1, `--tune=ROUT_INWARD=0` for the old rule): a defending
  unit routing inside the walls runs to the inside of the shut outer gate
  on its own ground farthest from any enemy (chosen again once a second),
  not toward its map edge; with no shut gate, or enemies within 30 m of
  every one, as before. Before, the street paths to the edge led routers
  out through the breach into the attackers queuing there (most of the
  defenders' dead were men cut down from behind); they rally there or are
  caught inside. Any defending side (AI or player), every settlement map.

Knobs (`sim/ai_profile.gd`; personality offsets 0):

| Knob | E / A / S | What |
|---|---|---|
| `S_MOUTH` (216) | 0 / 1 / 1 | the layout (Easy keeps the old reserves) |
| `S_MOUTH_IN` (217) | 2 / 2 / 2 m | the front's anchor this far inside the wall's inner face |
| `S_MOUTH_REACT` (218) | 24 / 24 / 24 m | the stack's other units attack attackers out of the gateway this close to the front's post |
| `S_GUARD_JOIN` (219) | 0 / 120 / 120 m | quiet gates' guards join the stack (quiet: no attacking foot this near, nearer it than another gate) |
| `S_READ_R` (222) | 0 / 220 / 260 m | the attacked gate read from the field within this (0: only once hit or open) |
| `S_READ_PCT` (223) | 0 / 50 / 35 | ... once that gate has this % of the attackers' strength ... |
| `S_READ_TICKS` (224) | 0 / 100 / 30 | ... for this long |
| `S_MOUTH_W` (225) | 20 / 20 / 20 m | the front's frontage |
| `S_PLAZA_REACT` (226) | 20 / 20 / 20 m | the plaza reserve attacks attackers within the plaza's radius + this |
| `S_ROT_PCT` (227) | 0 / 40 / 60 | the front is relieved below this % of its type's morale (0: never) |
| `S_SHUT_EMPTY` (228) | 0 / 1 / 1 | open gates with nobody of ours in the mouth are shut (sallies: behind them) |
| `S_TOKEN_MEN` (229) | 60 / 60 / 60 | a quiet gate's guard this small stays as its token when no rider can |
| `S_MOUTH_FRONTS` (230) | 1 / 1 / 1 | units side by side at the front |
| `S_MOUTH_BACK` (231) | 0 / 0 / 20 m | the stack stands this much further in while the gate is shut |
| `S_ROT_LULL` (232) | 0 / 0 / 1 | relief only between waves (1) or only while the front fights (0) |
| `S_WALL_SHIFT` (199) | 0 / 1 / 1 | idle wall missile units shift to the stretches by the attacked gate |

Measured (`tests/matchups.gd --only=fair-sieges`, both Average, 10 seeds;
attacker wins, draws, mean / max minutes; HEAD 7cc3fd8 -> now):

| City | Ladders + ram | Artillery only |
|---|---|---|
| ring, walls 1 | 100 % (7.2 / 8.0) -> 40 % (8.3 / 11.0) | 100 % (7.1 / 8.0) -> 30 % (8.2 / 11.4) |
| ring, walls 2 | 50 % (8.8 / 10.7) -> 20 % (9.0 / 12.8) | 20 % (9.7 / 12.0) -> 20 % (9.8 / 12.1) |
| ring, walls 3 | 20 %, 10 % draws (10.1 / 15.0) -> 0 % (9.5 / 11.7) | 40 % (10.3 / 14.6) -> 0 % (10.6 / 13.7) |
| polis, walls 1 | 80 %, 20 % draws (11.0 / 15.0) -> 50 %, 20 % draws (11.5 / 15.0) | 100 % (10.0 / 14.5) -> 60 %, 20 % draws (10.2 / 15.0) |
| polis, walls 2 | 50 % (11.0 / 13.9) -> 20 % (9.0 / 11.4) | 40 %, 20 % draws (10.7 / 15.0) -> 0 %, 10 % draws (9.1 / 15.0) |
| polis, walls 3 | 20 %, 10 % draws (11.9 / 15.0) -> 10 % (9.5 / 10.7) | 0 %, 50 % draws (11.4 / 15.0) -> 0 % (9.9 / 12.8) |

Walls 3 with a 30 minute limit: ring 20 % (10 % draws) / 40 % -> 0 / 0 %,
polis 30 % / 10 % (40 % draws) -> 10 / 0 % (nothing reaches 15 minutes now:
the attackers withdraw). Over 30 seeds, walls 1: ring 46 / 46 %, polis
53 / 60 %. Defender skill at walls 1 (Average attackers; 10 seeds, ladders
+ ram / artillery only; 30 seeds in brackets): Easy ring 80 / 70 % (73 /
70), polis 20 / 20 % (36 / 50); Average as above; Skilled ring 0 / 10 %,
polis 50 / 30 %.

Findings (30-seed runs at walls 1 unless said):
- The layout without the router rule: ring 70 / 100 %, polis 80 / 80 %
  (10 seeds); routers running out through the breach were most of the
  defenders' dead. With it but without the layout (`--knob=a:216=0`): ring
  93 / 93 %, polis 60 / 70 %.
- A unit at the front fights a column of several attacking units that
  pass through each other in the gateway: in a scripted probe one heavy
  unit of 100 at the mouth breaks even against one attacking heavy unit,
  and routs first against two or four. The stack's other units therefore
  attack whatever comes out of the gateway (`S_MOUTH_REACT`; ring walls 1
  went from 53-73 % to 20-26 % with it, before the other choices below).
- A relief while the front fights costs more than it gains (the old
  front's men turn away and take free blows, the relief arrives through
  it): ring 50 / 53 % with Average's swap, 20 / 30 % with no relief at all,
  26 / 30 % relieving only between waves. Average keeps the swap (the
  brief), Skilled relieves between waves; this is most of the Skilled /
  Average gap in the ring.
- Standing back while the gate is shut (Skilled) keeps the front out of
  the shots at the gate: ring 26 / 20 % with it for Average, 50 / 53 %
  without.
- Tried and dropped: two units side by side at the front (ring 66 / 70 %,
  polis 66 / 50 %); the stack waiting beside the gate along the wall
  instead of in a column (16-32 m out: equal or worse, and in reach of the
  attackers' archers at the breach); the relieved front stepping aside
  along the wall; Average's citadel fallback made later (no change).
- Walls 2-3 now go to the defender far more often than their targets
  (about 50 % and 25 %): the attackers lose 200-300 men at the wall before
  the breach (towers, wall archers) and can no longer win the street. The
  wall levers are not what holds them: walls 2-3 with walls-1 values
  (no towers, cover 25 %, no range bonus, gate hit points 100 %) were
  still 0-10 % (ring) and 20-30 % (polis). Without the router rule ring
  walls 2-3 were 80 / 40 % and 20 / 0 %. Not tuned further (attackers
  unchanged; see docs/STATUS.md item 4).

Re-measured 2026-10-09 / 2026-10-10 (siege pass, docs/STATUS.md "Siege
pass (2026-10-10)"): after the melee commit 15ef028 ("ranks hold
together") the stack at the mouth won almost every walls-1 street fight
(ring 0 %, polis 30 %; bisected); the sim lever `TOWN_PLACE_LEAD` 10 m
(DESIGN.md "Unit blocking and street fights") restores walls 1 (after the
movement build, full kit: 40 / 40 % with it, 10 / 30 % at the field's
1.5 m). The layout knobs were scanned against it first (`S_MOUTH_IN` 10 /
18 m, `S_MOUTH_REACT` 8 m, `S_GUARD_JOIN` 0) and moved little. Knobs
unchanged. Final equal-force table (both Average, 10 seeds; ladders + ram
/ artillery only / full kit): ring walls 1 20 / 60 / 40 %, walls 2 0 / 20
/ 20 %, walls 3 0 / 0 / 0 %; polis walls 1 40 / 40 / 40 %, walls 2 30 /
30 / 10 %, walls 3 30 / 10 / 50 %. Easy defenders (full kit, walls 1 / 2):
ring 80 / 0 %, polis 40 / 20 % (Average 40 / 20, 40 / 10): weaker only in
the ring at walls 1 (no Easy mistake added: not measured to a cause). Where
the attackers lose at walls 2-3 (deaths by place, 10 seeds, full kit):
290-350 men outside the walls (their archers to the last man, 110-130,
and the ram's and ladders' carriers) against 55-65 defenders outside and
60-110 on the walls; inside the town the attackers kill more than they
lose (ring walls 2 394 / 208). The gate falls at about 125 s at walls 1,
200 s at walls 2, 290 s at walls 3 (ring), the storm going in with 840 /
740 / 660 attackers left; the walls-2 gate's time does not change with its
hit points (100 / 85 / 70 %: the batteries' setting up and their duel with
the wall towers, `S_COUNTER_BAT`, set it; counter-battery off: 20-30 s
sooner and no more wins).

## 17. Engines left on the field (2026-10-09)

Engines are equipment (docs/DESIGN.md "Artillery", "Engines are equipment,
crews are men"). The battle AI (`sim/battle_ai.gd`, `_take_engines`, field
maps only) adds one rule: a missile unit out of ammunition with no router
to chase, not fighting and not in contact, takes up the nearest abandoned
engine group last worked by its own side within `ENGINE_TAKE_R` 60 m (an
`ORDER_PICKUP`, then it is a battery to the AI). AI batteries never drop
their engines; the settlement AI (`siege_ai.gd`) has no such rule; nobody
recaptures enemy engines. No knob, no tuning.

## 18. Ammunition kinds and resupply (2026-10-09)

Knobs in `sim/ai_profile.gd` (E / A / S). A unit with a special kind
shoots it at the targets its fields suit (`BattleAI.ammo_pick`, also
called for every unit by the settlement AI): a fire kind at wooden
targets (batteries, towers, carriers of a ram, ladders or a wagon) and,
with fear or fire, at wavering units; a harder-hitting kind at armour and
batteries; a bursting kind at big units and batteries.

| Knob | E / A / S | What |
|---|---|---|
| `AK_USE` | 0 / 1 / 1 | switch kinds at all |
| `AK_FIRE_WOOD` | 0 / 1 / 1 | fire kinds at wooden targets |
| `AK_WAVER_PCT` | 0 / 35 / 50 | fear / fire kinds at units below this % of their morale |
| `AK_ARMOUR` | 999 / 12 / 9 | harder-hitting kinds at this much armour |
| `AK_BLAST_MEN` | 9999 / 80 / 60 | bursting kinds at units this big |
| `AK_FIRE_GATE` | 0 / 1 / 1 | attacking missile units with a fire kind, at their post, shoot the attacked gate alight |
| `WG_BACK` | 40 / 40 / 50 m | the wagon stands this far behind the army's centre (or by a battery out of shots) |
| `WG_THREAT` | 0 / 40 / 60 m | enemy melee this near the wagon: the nearest free melee unit goes for it |
| `WG_FLEE` | 25 / 25 / 35 m | the wagon draws back from enemies this near |
| `WG_EMPTY_PCT` | 0 / 15 / 30 | missile units below this % go to a wagon of ours within `WG_RANGE` (150 m) and refill |
| `FORAGE_AI` | 0 / 1 / 1 | an empty missile unit in woods, no wagon, no enemy near, forages |

Wagon crews are kept out of the line, guards and ladder parties
(`BattleAI.is_wagon`); the campaign AI recruits wagons only by
section 24's rule (its `_any_type` still skips them). None of it runs without kinds or wagons, so
every older battle plays as before, except that empty missile units in
woods may now forage.

## 19. Camels and elephants (2026-10-09)

By the rows' fields, never by name (`sim/battle_ai.gd` `_cav_pick`,
`_cav_think`, `amok_think`; `sim/siege_ai.gd` `_att_cav`, `_beast_gate`).
Knobs in `sim/ai_profile.gd` (E / A / S):

| Knob | E / A / S | What |
|---|---|---|
| `CAMEL_HORSE` | 0 / 4500 / 5000 | a rider with a horse scare scores enemy horse cavalry this (the screen) |
| `EL_LINE` | 0 / 4300 / 4300 | a rider with a fear aura scores enemy formed foot this (at the line) |
| `EL_PIKE` | 0 / 0 / 1500 | ... less this for pikes and braced spears |
| `EL_NO_STAGE` | 0 / 1 / 1 | ... and charges the front, never riding round to a flank first |
| `EL_KILL_R` | 0 / 30 m / 60 m | an amok beast of ours this near a unit of ours: Kill elephant |
| `EL_GATE` | 0 / 1 / 1 | settlement attackers: beasts batter the attacked gate where they can (walls up to `gate_walls`) |
| `EL_STORM` | 1 / 0 / 0 | ... and go into the streets with the storm (0: they stay outside) |

At Easy camels and elephants are plain riders (and Easy storms the
streets with its elephants: a mistake). Elephants deploy on the wings like
cavalry (the battle AI's line); the custom and settlement layouts
(`Scenarios.army_layout`) put them 30 m ahead of the line. The campaign AI
recruits them through its factions' mixes only (`CAI.BEAST_LINES`;
`_any_type` never falls back on them). Nothing runs without such rows, so
every older battle plays as before.

## 20. The general (2026-10-09)

By the row's command aura (`cmd_r`, `BattleAI.is_general`), never by
name; field battles (`sim/battle_ai.gd` `_general_think`; the settlement
AI uses him as a rider). With `GEN_THINK` on he is left out of the line
(`_issue_line`) and of the Skilled reserve cavalry, and each think: if
committed (`A_CHARGE`) he sees the charge through and pulls out after
`GEN_MELEE`, but does not pursue a broken target; otherwise he rides to
the nearest unit of ours within `GEN_RALLY_R` that is routing (not on its
final rout) or below `GEN_RALLY_MOR` and stays by it (12 m behind it,
inside half his aura); else charges the nearest enemy unit within
`GEN_CHARGE_R` that is below `GEN_CHARGE_MOR` and fighting ours (not a
braced front toward him: the decisive charge); else keeps his post
`GEN_BACK` behind the centre of the main line. Counters `gen_rally`,
`gen_charge`. Easy's mistake: `GEN_THINK` 0, he is a plain rider in the
line, charges with the first cavalry (and with the commit-early mistake).

| Knob | E / A / S | What |
|---|---|---|
| `GEN_THINK` | 0 / 1 / 1 | keep him back and commit him only as below (0: any rider) |
| `GEN_BACK` | 30 / 30 / 25 m | his post behind the line's centre |
| `GEN_RALLY_MOR` | 0 / 300 / 400 | ride to a unit of ours below this morale (or routing) ... |
| `GEN_RALLY_R` | 0 / 120 / 160 m | ... this near him |
| `GEN_CHARGE_MOR` | 0 / 200 / 260 | charge an enemy unit below this morale, fighting ours ... |
| `GEN_CHARGE_R` | 0 / 100 / 140 m | ... this near him |
| `GEN_MELEE` | 150 / 150 / 100 ticks | pull out of the melee after this long |

Determinism `--only=general` (battle_2000, a general a side, flat, seed
720): Average keeps him behind the line until the lines meet, rides to
rally 12 times and makes 3 decisive charges in 2,400 ticks (both generals
fall by then: not tuned); Easy sends him in at tick 348, before the lines
meet (491). The campaign AI keeps a few through its mixes ("general" 4,
`CAI.BEAST_LINES`).

## 21. War dogs (2026-10-09)

By the row's fields (a handler row has `pack_n` / `pack_type`; a pack is a
unit with `u_hand` set), never by name (`sim/battle_ai.gd` `dog_think`,
`dog_prey`). Field battles: handlers with their dogs in the kennel release
them (ORDER_RELEASE) at the nearest enemy unit within `DOG_R` (and the
row's `pack_r`) that the pack is good against: a routing unit (not a big
body), missile troops, a battery's crew (CLS_ART) or a wagon; never formed
foot, spears, riders or elephants. Otherwise the handlers are plain weak
foot in the line. The AI never orders a released pack (`_order` drops
orders for it; `think` and `_issue_line` skip it): the sim's own rules run
it (it goes for the nearest enemy within `return_r` when its target is
gone, runs home once none has been within `return_r` for `return_t`, and
is recalled by that rule only). Easy's mistake: `DOG_ANY` 1, the first
enemy unit within `DOG_R` in index order, whatever it is (heavy foot,
spears, elephants included). The settlement AI never releases a pack (the
handlers are plain foot there; inside walls a pack would only find the
streets): `siege_ai.gd` skips packs. Counter `dog_release`.

| Knob | E / A / S | What |
|---|---|---|
| `DOG_R` | 60 / 60 / 75 m | release at prey this near the handlers (the row's `pack_r`, 80 m, caps it) |
| `DOG_ANY` | 1 / 0 / 0 | release at the first enemy in range, whatever it is (Easy's mistake) |

The campaign AI recruits them through the mixes only ("dogs" 3 for Rome,
Epirus, the Greeks and the Gauls; `CAI.BEAST_LINES`; `CData.no_dogs` /
`campaign_sim --no-dogs` sets the weight to 0). Not tuned.

## 22. Field works and the fortified camp (2026-10-09)

Knobs `FW_PLACE` (Easy 0 none, Average 1, Skilled 2), `FW_AHEAD` (10 m),
`FW_CAMP` (Easy 0, else 1), `CAMP_HOLD` (6,000 ticks). At the start (after
its deployment) the battle AI puts its side's unplaced stakes and caltrops
before its line (`place_works`): a fortified side first before its
camp's gaps (beyond the ditch); Average across the centre, stakes
`FW_AHEAD` before the front, caltrops 12 m further; Skilled before each
missile unit and the ends of the foot line first, its caltrops just
beyond the flanks where riders come round. A side standing in its own camp
(a rampart of its side and `FW_CAMP`) deploys into it (`_camp_deploy`):
missile troops on the front rampart in two ranks, skirmish off, standing
and shooting (mode `A_WORKS` until out of missiles), foot just inside the
gaps (then a row behind the middle), the rest behind; it holds (`ai_hold`,
the high-ground hold's machinery: foot only go for enemies within
`HOLD_REACT`) until a third of its foot fights or `CAMP_HOLD` runs out, then
fights as usual. Easy ignores the works (deploys as anywhere, places
none). The AI never reads the enemy's works (no cheats: caltrops are
hidden; stakes it could see are not avoided yet: a gap).


## 23. Mantlets (2026-10-09)

Mantlets are wooden missile screens (docs/DESIGN.md "Mantlets"). The
settlement AI's attackers (`sim/siege_ai.gd`, section "mantlets"; every
level, no knob, no tuning) use them in the approach: at army level
(`_assign_mantlets`, from `_assign_equip` once a gate is picked) each of
the side's mantlets on the ground away from its place, held by nobody,
goes to the nearest spare foot unit that may carry it (light infantry or
missile troops first, then any foot; never the ram's unit, a tower's or a
ladder party, never the general), mode `A_MANTLET` 36 (`u_ai_x` = piece +
1). Its place (`_mantlet_spot`), `MANTLET_BEFORE` 2 m toward the
attacked gate from the front of the unit it screens: one a missile unit
(archers, slingers, javelins) at the post `_att_missile` sends it to on
its shooting line (the cover line `S_COVER_OUT`; javelins the waiting
line), the middle of the line first; then one a scorpion battery where
it sets up (not Easy's, left where they stand); the rest before the heavy
batteries (stone / bolt throwers, index order, side by side
`MANTLET_GAP` 7 m apart) where they set up; none of those: a line
`MANTLET_OUT` 60 m from the gate. The unit (`_att_mantlet`) picks it up,
walks it there facing the gate, drops it (it stands facing the unit's
way) and goes back to its plan (`A_WAIT`). A mantlet on its place's line
(its distance from the gate within `MANTLET_SET_R` 8 m of the place's) is
left alone: it is carried again only when the line it screens moves (a
new gate). The approach over, the piece wrecked or
the unit caught in a fight: it drops it where it is and fights. Counted
in `C_SIEGE`.

Since 2026-10-10 (docs/DESIGN.md "Siege equipment usability") a set-down
mantlet is a line of panels at its carrying unit's frontage (6-40 m): the
AI's plan is unchanged and its carriers' own frontage gives the width; it
does not take pieces up in the deployment phase (the siege AI starts with
the battle).

Gaps: the defenders ignore mantlets (they neither carry their own nor
shoot or burn the attackers'); the field battle AI (`battle_ai.gd`) does
not use them (a side's mantlets stand where the setup put them, before its
missile units, and the line advances past them; carrying them forward
with the missile line was left out).

Measured with the full kit (4 mantlets, a tower at walls 2-3, scorpions;
2026-10-10 siege pass): see section 16's final table; the screens' own
share was not isolated (the attackers' archers behind them still die to
the last man in the duel with the walls).

## 24. Campaign build-up: Range 2, the Workshop and the wagon (2026-10-09)

Measured before (`campaign_sim` 6 seeds x 60 turns, all Average): no AI
faction built a Workshop in any seed, and only 9 of the 25 factions holding
4+ regions at turn 40 had a Range 2. So no wagons, scorpions, gastraphetes
or Workshop ammunition kinds. The reasons, in `_build`:

- **No slot.** Every capital city starts with all 6 slots full (walls,
  farm, barracks, range, stables, market); a capital town fills its 5 the
  same way (no market) and spends the slot it gets as a city on the market.
  Towns and cities fill theirs with farm, market and barracks first. The
  Workshop came last in the want list, so a slot was never left for it (no
  order removes a building).
- **Priority and budget.** Average builds in priority order (walls, farm,
  market, then the military chains), one building a region a turn, from 60 %
  of the money above the reserve. The capital worked through farm 2-3 and
  market 2-3 (900-1800 each) first, and while those were over budget the
  money went to cheap level-1 farms and markets in other regions. Range 2
  was never wanted for itself.

As built (`campaign/cai.gd` `_buildup`, `_build`, `_recruit`):

- **The build-up goes first.** Its next building: a Range up to `BU_RANGE`
  when the mix has a Range line (archers, javelins, slingers, belly-bows),
  then a Workshop up to `BU_WORKSHOP` when the mix has engines (bolt, stone,
  scorpions) or the faction fields `WAGON_MIN` missile / artillery units
  (for the wagon), then (2026-10-13) Barracks 2 when it raises heroes
  (`CHAR_HERO` > 0: Average, Skilled; heroes need Barracks 2,
  `CData.CHAR_NEEDS`), so the AI fields heroes; the same site, wait and
  budget rules. Each goes at the first centre (capital or town; richest
  and capital first, the build order's sort) that already has that
  building, else the first with a free slot. It waits while that centre
  lacks a farm, or a market while it has more than one free slot (the
  economy first, then the chain). It may spend `BU_BUDGET_PCT` of the money
  above the reserve; while it waits for money (`BU_SAVE`) nothing else is
  built that turn; and a centre whose last free slot the build-up needs
  builds nothing new there but walls.
- **The wagon.** Before the usual recruiting, each army holding this turn
  (not planned to march) with `WAGON_MIN` missile / artillery units (a unit
  type with a missile kind, `m_ak`, not a wagon) and no wagon gets one: the
  best tier of its "siege" line the buildings allow, at a recruiting centre
  with a Workshop it stands at, into that army (`"army": id`, as
  `_recruit_order` gives it), within the usual upkeep cap and reserve. One
  wagon an army. Version 6 only.
- **A line at another centre.** When the line the mix asks for cannot be
  raised at the recruiting centre in hand (no Workshop for scorpions or bolt
  throwers, no Range 2 for gastraphetes), it is raised at the next
  recruiting centre that can (before: the centre's first other type, so the
  engines' share never grew).
- **Ammunition kinds** need no order: a missile unit takes the kind of the
  first `CData.AMMO_AVAIL` row for its faction whose building stands where
  it is recruited (`CRules.ammo_for`, stored as "ak"). The build-up gives
  the kinds; units raised elsewhere, and older units, carry none.

| Knob | E / A / S | What |
|---|---|---|
| `BU_RANGE` | 0 / 2 / 2 | Range level wanted at the military centre (0 off) |
| `BU_WORKSHOP` | 0 / 1 / 2 | Workshop level wanted there (0 off) |
| `BU_BUDGET_PCT` | 0 / 100 / 100 | % of the money above the reserve the build-up may take a turn |
| `BU_SAVE` | 0 / 1 / 1 | while it waits for money nothing else is built |
| `WAGON_MIN` | 0 / 3 / 2 | missile / artillery units in an army for a wagon (0 never) |

(2026-10-23: the mortar counts as an engine, and the pack's build-up lines raise the Workshop / Barracks to level 3:
section 34.)

Easy builds and recruits as before (all 0). Test switch `CAI.no_buildup`
(`campaign_sim --no-buildup`; set in `campaign_test`'s step-4 goldens):
none of the above; with it the 6x60 hashes are the old ones
(`7dbe4251 a56c5e4f b1ee756c 0e0d3920 9c156d00 b3ae1fa9`).

Measured after (6 x 60, Average; hashes `324307b6 bb0532b7 b9e5ae32
0bf0a9f8 b77014f8 481344a4`): at turn 40, 28 of 29 factions with 4+
regions have a Range 2 and 26 a Workshop 1; 42 Workshops finished over the
seeds (0 before); alive at turn 60: 13 wagons, 5 scorpions, 6 gastraphetes
and 141 missile units with a special kind (23 before). Pacing of the same
order: battles 57-82 a seed (58-75 before), largest faction 9-15 regions at
60 (11-13), units on the map at turn 60 179-254 (196-255), treasury ranges
alike. Skilled (2 x 60) reaches Workshop 2. Not tuned. Gaps: kinds only on
units raised at the building's centre; no refit of older units; the
Workshop is often not at the capital (its slots are full), so engines and
wagons are raised away from the main army's usual centre.

## 25. Units flow into the space (2026-10-09)

No AI rule or knob changed (docs/DESIGN.md "Units flow into the space").
What the AI's units now do differently comes from the sim: an attack order
given to a unit already attacking keeps its path (the AI retargets every
second; a fresh plan each time had units at corners turn back to an entry
node behind them and never get on), a unit stuck past `STUCK_ROUTE` keeps
its path against a moving goal unless it moved 48 m, a move stuck near its
destination or to ground no longer reachable (a gate the defenders shut
since) ends where the unit got to, a short move among buildings marches
when there is no clear way from the men, and a unit climbing ladders takes
a move order (the AI gives none: `_escalade` leaves climbing units alone).
The siege coverage cases still see every behaviour of sections 13-16
(the `--only=layout` case moved to fair-siege seed 2: in seed 1 the attack
now stalls at the gate and nobody reaches the plaza reserve in 4,500
ticks).


## 26. Siege pass: the Skilled storm, engines taken up, wall shifts (2026-10-10)

- **Skilled no longer staggers the storm** (`SK_STORM_STAGGER` 1 -> 0 for
  Skilled). Measured cause (2026-10-09): a staggered storm sends the units
  into the town one by one, each into the stack at the gate mouth (traces:
  90-300 men inside at a time against Average's 450 at once); ablation at
  ring / polis walls 1, full kit: stagger off 0 / 20 -> 70 / 40 %; feint,
  ram wait, ladder units, memory, reserve, rotation off: unchanged. After
  the movement build (2026-10-10, 10 seeds, full kit walls 1 / 2): Skilled
  attacker vs Average ring 50 / 10 %, polis 40 / 30 % (Average attacker 40
  / 20, 40 / 10).
- **The settlement AI takes up engines** (`sim/siege_ai.gd`, the unit
  dispatcher): a missile unit of either side out of ammunition, on the
  ground, takes up its side's engines whose crew broke or died within
  `ENGINE_TAKE_R` 60 m (`BattleAI._take_engines`, as the field AI).
  Recapturing the enemy's engines is not built (gap). Not measured on its
  own.
- **Wall shifts stay off the citadel** (`_wall_shift`): a wall missile unit
  on a citadel stretch is not sent to an outer stretch (the citadel's gate
  is shut in a siege; a polis walls-3 seed's 60 acropolis archers came
  down, could not get through and marched at a house all battle).
- Gaps left: the AI reading enemy field works (cavalry charging stakes
  head-on, the camp assaulted at a gap) is not built; the defenders and the
  field AI still ignore mantlets; attacking archers fight the wall duel to
  the last man (no pull-back when losing it); a fortified holder at a
  crossing stays in its camp at the mouth and loses more than an open one
  (CAMPAIGN.md formula notes; docs/STATUS.md "Siege pass (2026-10-10)").


## 27. Heroes and agents in battle (2026-10-10)

The battle side of STATUS 8a (docs/DESIGN.md "Heroes and agents"). A
side's characters (`BattleSim.u_char`) are routed by both dispatchers
(`BattleAI.think`, `SiegeAI.think`) to `BattleAI.char_think` and take no
part in the army plan: `_issue_line`, `_plan` (both centroids), `_strength`
/ `_start_strength`, `_is_foot`, the settlement AI's ground strength,
`_no_foot`, `_defenders_standing`, `_classify_defender`, the gate-sally
weights and `_equip_free` (no character carries a ram or ladders) all skip
them. Knobs (`sim/ai_profile.gd`, Easy / Average / Skilled):

| Knob | E / A / S | Meaning |
|---|---|---|
| `CH_ATTEMPT` | 0 / 0 / 1 | the assassin makes his one attempt on an enemy general (`is_general`, command not fallen) within `CH_ATTEMPT_R` of him |
| `CH_ATTEMPT_R` | 60 m | ... box to box |
| `CH_PARLEY_R` | 0 / 80 / 80 m | the diplomat parleys the nearest routing enemy unit this near that `char_refusal` accepts (0: never) |
| `CH_BACK` | 15 m | how far a hero keeps behind the unit he goes with |
| `CH_SAB_R` | 0 / 0 / 120 m | the assassin, before he has acted (once), sabotages the nearest enemy battery this near him (0: never) |
| `CH_SAB_GUARD` | 20 m | ... one with no ready enemy foot unit this near its engines (box to point): unescorted |

- **Heroes never charge alone**: no attack order is ever given to one; idle
  (`_char_post`, at each unit think) each keeps `CH_BACK` (+ half the
  unit's depth) behind the nearest friendly unit of his field, along the
  army's facing: the cavalry hero behind a cavalry unit (the reserve, then
  the wings as they go in), the missile hero behind a missile unit, the
  siege hero behind a battery (none: twice `CH_BACK` behind the line), the
  champion `CH_BACK` + 10 m behind the main line's centre (the second
  line). His own men fight whatever reaches him (the sim's melee); a hero
  fighting within 20 m of his post is left to it.
- **The assassin** (Skilled only, by `CH_ATTEMPT`): an enemy general within
  60 m: `ORDER_ATTEMPT` (counter `C_CH_ATTEMPT`); otherwise he shadows the
  line 15 m behind its left of centre (an enemy general posted 30 m behind
  his own line comes within reach once the lines meet). Else (2026-10-13,
  Skilled by `CH_SAB_R`, while he has not acted: so once) the nearest
  enemy battery (an engine group `char_refusal` accepts: not a tower's,
  not all wrecked) within 120 m with no enemy foot within 20 m of its
  engines: `ORDER_SABOTAGE` (counter `C_CH_SABOTAGE`). Gates, rams and
  siege towers are not his targets.
- **The diplomat** (Average, Skilled): the nearest routing enemy unit within
  80 m that may be asked: `ORDER_PARLEY` (counter `C_CH_PARLEY`); otherwise
  he keeps 30 m behind the line's right. Routers within `PARLEY_SEE` 80 m of
  a diplomat coming for them stop and wait (the sim), so he reaches them.
- **Settlement maps**: the attackers' characters keep posts as above; the
  defenders' stand where they were placed (they still parley / attempt).
  The tower engines rank a hero in reach with the ram's crew (class 3,
  nearest first); the field batteries' fire-at-will adds 3,000 to a hero's
  score; `BattleAI._art_think` already prefers one (one man at his price,
  1,500, against a unit's men times their cost).
- **Hidden units**: `sim.hidden_from(o, side)` is skipped by
  `_nearest_enemy`, `_nearest_not`, `_nearest`, `_nearest_routing`,
  `_cav_pick`, the missile clean-target check, `_art_think`, the tower's
  target choice and `_nearest_attacker`; the sim's own fire-at-will
  (`_missile_think`, `_art_think`) skips them too.
- Measured (`tests/determinism_test.gd --only=chars`, battle_2000 with a
  general and all six characters a side, 1,800 ticks): Average heroes
  behind their foot line in 109 of 118 samples (9 more than 10 m ahead:
  the cavalry hero with the wings), no attack order, 7 of 8 heroes alive,
  2 parleys (1 surrender: 35 prisoners, 1 refused), no attempt; Skilled 2
  attempts, 3 parleys. Sabotage (`--only=chars` J, their bolt battery 80 m
  from him, 90 s): Skilled sent once, 2 engines wrecked; Average never;
  Skilled with their heavy foot beside the battery: never.
- Gaps: the AI does not pull a hero out of a losing
  fight or shield him from missile fire; no aura knob per kind (the posts
  are the knob: each hero stands where his aura counts).

## 28. Cover and line of sight (West slice 2b, 2026-10-15)

docs/DESIGN.md "Cover and line of sight". The battle AI plays by what its
side sees (`BattleSim.hidden_from`, now also a unit no unit of that side
sees): every target choice (fire at will, cavalry, foot, batteries, the
missile units' "hold fire unless a clean target") skips hidden enemies, as
it did the hidden assassin. `_plan` reckons the enemy centre and the gap
between the lines from the enemies it sees, all of them only when it sees
none (it knows roughly where the enemy army is, not which unit stands
where). Cover troops (`cover` rows) take the nearest cover within 30 m of
their line slot (`_cover_spot`: woods, a rock, house or wall within 2 m, a
hedge; fixed order of offsets), so on defence they deploy into it and lie
hidden until they shoot (the ambush placement); line troops ignore cover.
Foot in the engagement with no enemy in sight while some hide probe the
nearest wood toward the enemy (`_probe`: 40-160 m ahead, up to 120 m
aside, `PROBE_PCT` 25 % a think, at a walk). Counters `stat_ai[16]` (cover
spots taken), `stat_ai[17]` (probes). Not built: the AI remembering where
it last saw a unit; deliberate ambush orders (hold fire until the enemy is
close) beyond going to ground; probing with cavalry.

## 29. Forts, buildings held, the musket line's reserve (West slice 2c, 2026-10-16)

docs/DESIGN.md "Forts and fighting from buildings". All of it orders a player
could give (ORDER_OCCUPY, ORDER_GATE, attack and move orders).

- **The fort's garrison (defenders, `sim/siege_ai.gd`).** The scenario puts
  the best musket companies on the fort's land stretches (`Scenarios.settlement`);
  they are wall units (`A_WALLU`: they stand and shoot, per man from the
  parapet) and stay up (`_off_wall` finds no outer gate). Units placed on its
  parade hold it (`A_CIT`, `_cit_guard`). The fort's guns are tower engines
  (`_tower`: the ram, ladder parties, men at the gate, else fire at will). The
  gate (`_fort_gates`) stays open while no attacker is within `FORT_SHUT_R`
  45 m and none carries a ram or ladders, then it is shut for good; the sally
  port is never opened. The rest of the army holds the town as before (C7's
  street posts); a reserve sent up against ladder men comes only from the
  fort's own garrison (`_esc_reply`).
- **The attackers' choice (`_fort_choice`, once, `ai_fort` hashed).** Storm the
  fort as well as the town (2) only with a ram, ladders or guns of their own and
  when the fort holds `FORT_STORM_PCT` 35 % of the defenders' strength or more
  (or they are `FORT_STORM_ODDS` 250 % as strong as all the defenders); else
  take the town round it (1): the storming foot leave the fort's men alone
  (`_storm`), the ram does not go at its gate, the guns shoot the town's
  defenders. Storming: the ram goes at the fort's gate once it is shut, the
  ladder parties at its land stretches in the assault (`_assign_equip`,
  `_escalade` with the fort's gate), storming foot within `FORT_FOLLOW_R` of a
  planted set climb it too (`_follow`), and the men over the wall or through
  the gate (`_fort_party`: in the fort, or foot of the two units nearest its
  open gate) take its parade and hold it till it falls (FORT_CAP_TICKS).
  (2026-11-05: the edge by kit, poles and a ram as well as guns, and the storm
  going on past the town's fall: note 58.)
- **Buildings held (street AI).** A West musket line's street post becomes
  the building nearest it (door step within `SP_OCC_R` 24 m, `SP_OCC_MIN` 10
  firing places or more): it is sent in (ORDER_OCCUPY) and its reserve rule
  keeps it there, firing at will (`_reserve`). Storming foot that attack it
  go at its door (the sim's attack goal is the door step). (Not as first
  written: attacking line foot do not wait off a held building as off a
  strongpoint; `_sp_wait` keys on cover spots, `u_cvb`, which men at windows
  never have. Section 31.)
- **The musket line's reserve (field battles, West rows, `sim/battle_ai.gd`).**
  Melee foot and horse counter-charge (`_counter_target`) enemy foot or horse
  within `CC_REACH` 140 m that fight one of theirs or are charging one (an
  attack order within `CC_CLOSE` 60 m of it); they do not charge an enemy
  musket line that is free and shooting (`_gun_line_free`: shots left, not in a
  melee, 60 % of its men or more, morale 500 or more) while the enemy still has
  melee to throw (`_melee_left`) for the first `CC_HOLD_T` 3 minutes of the
  engagement: foot halt behind their line, horse pull out of its fire. The
  battery guard (`_pick_guard`) counts a West army's musket lines toward
  `GUARD_MIN_MELEE` and takes pikes first (they stop horse).
- **Forts leftovers (2026-10-16).** *The sally* (`_fort_sally`, `A_FSALLY`):
  the garrison company stands as two units (the guard, a quarter of it and 10
  men or more, on the land stretch farthest from the attackers); the bigger
  (`_fort_sally_unit`) is the sally company. On the parapets it shoots as any
  wall unit; when the sally is due (`_fort_sally_due`: the plaza's capture
  running, a ready attacking unit of `CAPTURE_MEN` within the plaza's box +
  `CAPTURE_CLEAR` + `FORT_SALLY_APP` 30 m, or half the West line units holding
  the streets routing or gone) and no ram or ladders are within `FORT_BACK_R`
  60 m of the main gate, it takes Line stance and goes down and out to the
  street post nearest the gate (`_fort_sally_post`: a ready street unit's
  post off the fort; none, the plaza), at the run while farther than
  `SP_RUN_R`; there it holds and shoots (melee only out of shots). A ram or
  ladders within `FORT_BACK_R` of the gate send it back up its stretch for
  good (u_ai_x 0 up, 1 out, 2 going back, 3 back). `_fort_gates` opens the
  gate for it going out (still in the fort) or coming back (outside), when
  nobody is within `FORT_SHUT_R` and no ram or ladders within `FORT_BACK_R`;
  while it is out the gate is not shut against a ram or ladders far off.
  *The attackers' guns* (`_town_gun`, taking the town round the fort): the
  nearest ready town defender (not in the fort, not a tower) they reach and
  may shoot safely, fire at will off; none, they hold their fire (they had
  shot the garrison on its parapet from out of its reach). *Field (West
  rows):* a unit out of ammunition that has fallen back and cannot refill,
  forage or take up engines stays on the field (Rome's leave it, the
  2026-10-09 rule); horse do not pick a target within a free musket line's
  range + `GUN_COVER_PAD` 30 m (`_gun_covered`), counter-charges excepted.

- **Balance pass on plan maps (2026-10-20).** Attackers in an open campaign
  town (a plan map, `tp`, with no outer gates: the West's walls 0-2) give
  the battle up below `S_BEATEN_TOWN_PCT` 25 % of their start strength (and
  weaker than the defenders) rather than `AP.S_BEATEN_PCT` 35 % (Easy keeps
  20 %): the street fight is an attrition race they used to quit near even
  losses (16 West towns, walls 0 40 -> 52 %, walls 1 26 -> 41 %). Scenario
  keys and custom battles (generated maps) keep 35 %. Leaving a bypassed
  fort's garrison out of the defenders' strength was measured (+2-3
  points) and not kept.

## 30. Sea battle AI: the leeward fleet (sea pass 4, 2026-10-17)

The sea battle AI (`sim/sea_sim.gd` `_think`, `_closing`; DESIGN "Sea
battles: the leeward fleet") lives in the sea sim, apart from the land
battle AI above. What it does since sea pass 4 (the owner: the downwind
fleet grounds and never engages; measured with `tests/sea_probe.gd`):

- **Target and stance** as in N3a (nearest weakest enemy, flee when
  beaten, grape close, chain to cripple a ship it means to board).
- **Boards** when its boarding strength (with friends already boarding the
  same ship) is `BOARD_PCT` 130 % of hers (was 160 %), she is close or
  crippled and not outrunning it.
- **Closing from far off, by the wind**: a ship that has the weather gauge
  bears down to her range on the enemy's windward side (no hovering up to
  windward); a ship that can fetch the gauge on one board takes it; a
  leeward ship makes for the enemy's lee bow, on a reach when she can,
  never beating past the enemy. A leeward fleet whose enemy lies to
  windward beyond two boards' reach (its worst sailer to windward) stops
  beating and heaves to in line, close-hauled toward the enemy, to receive
  it; after `HOLD_TICKS` (3 min) it beats up anyway, so a player who keeps
  the gauge and never comes cannot win on the clock.
- **Seamanship it shares with the player's ships** (the navigator): sea
  room ahead when choosing a board, tacking short of land, never steering
  in toward a lee shore within 250 m, working off a bank, tacks that carry
  their way.
- **Measured** (24 seeds, mirrored fleets, AI both sides): side 1 wins
  9-14 of 24 by layout (96 seeds: 37-55 of 96, 44-50 with the side order
  swapped, so mostly noise; before 34-56, 56 across the wind and 34 on
  the campaign's coasts); groundings 238 -> 37 over 120 battles; the
  leeward fleet fires first within 0.99-1.08 x the windward fleet's time.
  Open: a scripted player who sends every ship at the nearest enemy and
  never flees wins 15-19 of 24 against it (11-15 before): its flight rule
  is the suspect (sea balance follow-ons). Measured in section 32: not
  the flight but battle sail, grape and eager boarding.

## 31. Open West towns: out of the houses' reach, bounded waits (2026-10-21)

The owner (tablet, West campaign, walls 0): the AI armies do not push into
towns with no walls; they sit just in range of his musket companies, which
he puts in the houses at the street mouths (ORDER_OCCUPY, fire at will),
and get picked off. Measured with `tests/open_town_probe.gd` (a campaign
town on its own plan at walls 0, the West sets' armies, the AI attacking,
the defender scripted like the owner: every musket company in the building
nearest a street mouth, the rest on the plaza; `--occ=mixed`: musketeers in
houses, buccaneers in cover a quarter of the way in from the mouths).
Diagnosis: not the C7 wait. `_sp_wait` keys on cover spots (`u_cvb`), which
a unit in a building never has, so the storming line foot went at the
doors at once (first at a door 1.2-1.3 min after contact). The halted
units in reach were the attacking **musket lines in the open-town
stand-off band** (`A_COVER`: `S_OPEN_PCT` / `S_OPEN_OUT`, 50-70 m off the
landward edge), well inside a house's 120 m, standing there until all out
(`S_ASSAULT_ALL`, 4 minutes into the assault): 316 of 351 unit-seconds
halted in reach a battle. Against buccaneers in cover the C7 wait did
happen (87 unit-seconds a battle, Havana 180), unbounded.

As built (`sim/siege_ai.gd`; West rows only, Rome untouched):

- **The band out of reach** (walls 0, a town with no works): the band
  point of an attacking missile unit is moved out, down the field, of the
  reach (range + `GUN_COVER_PAD` 30 m) of every defender it sees shooting
  from cover (a held building, cover spots: `_out_of_cover_reach`); none
  out of reach before the field's edge: it goes in with the storm.
- **The musket lines go in** (walls 0): `SP_BAND_T` 90 s into the assault
  the band's missile units storm (`_storm`) with the foot, as at all out,
  rather than standing out of reach for 4 minutes. All of them at once.
- **The C7 wait is bounded** (all West open towns): a line unit waiting off
  a strongpoint goes in on it at the run `SP_WAIT_T` 90 s after the first
  of ours began waiting on that strongpoint, or at once when it loses
  `SP_FIRE_PCT` 5 % of its men within a `SP_FIRE_T` 20 s mark while
  waiting; every unit of ours waiting on the same strongpoint goes with it
  (the street goes in together), and a unit that went in waits no more
  (memory in `u_ai_y` / `u_ai_t` of the `A_STORM` unit, hashed).

Tried and not kept: the wait's trigger moved out to the strongpoint's
reach + pad, a unit already inside it going in at once (the brief's first
choice): the buccaneers' reach is longer than the distance they are seen
at, so it ended the wait outright (3 unit-seconds) and won no more; West
musket lines going in by bounds as the skirmishers do (`_bound_storm`)
from the start: they stood in reach in the streets instead (14 of 24
against 19); the band out of reach and the 90 s storm at walls 1-2 (the
fort, the palisade): AI against AI walls 1 41 -> 52 %, walls 2 33 -> 42 %,
so both are gated to walls 0. Average and Skilled play these towns alike
(no Skilled knob is reached in an open town's assault): the probe's
results are identical at both.

Measured (probe, 3 towns: Havana, Cartagena, Santo Domingo, 8 seeds each,
per battle; before -> after): owner's defence, attacker wins 19 -> 17 of
24, attacking line units halted within 120 m of a held house 351 -> 76
unit-seconds (the band's 316 -> 28), their mean distance 94 -> 106 m,
attackers killed 392 -> 370, 10.4 -> 9.4 minutes; `--occ=mixed` wins 16 ->
18, halted in reach 330 -> 58, the C7 wait 87 -> 26 unit-seconds, first at
a door 1.2 -> 0.9 min. AI against AI (`tests/town_balance.gd`, 16 Spanish
towns, 16 seeds): walls 0 / 1 / 2 55 / 41 / 33 -> 52 / 39 / 33 %; the
brief's seven towns 60 / 45 / 25 -> 57 / 46 / 21 %; Rome rows identical.

## 32. Sea battle AI: the flight rule (sea balance, 2026-10-21)

Open since sea pass 4 (section 30): a scripted player who sends every ship
at the nearest enemy and never flees (`tests/sea_probe.gd --modes=order`)
won 15-19 of 24 equal-force battles against the AI; the suspect was the
AI's flight. **Measured first, it was not**: with the AI never fleeing at
all the player still won 81 of 120 (83 with). The AI lost the exchange
itself (it dealt 79-93 % of the damage it took). Ablations (24 seeds x 5
layouts, player wins of 120, from 83): full sail in the fight 75 (the AI
dropped to battle sail inside 320 m, 75 % speed, and was out-sailed);
round shot only 76 (a broadside loaded with grape cannot fire beyond its
short range, and reloads only by firing); no boarding 73 (130 % boarded
too often); all three 53; nearest target, no hold, no per-ship flight:
no change. Over 192 seeds x 5: grape for a ship that means to board 544
of 960 against round 514 to 534; the boarder loading grape at any range
716, in grape range 619, at 80 m 595; focus fire (friends' target first)
542-550 against 544. So the fight was mended as well as the flight.

As built (`sim/sea_sim.gd`; state hashed and snapshotted):

- **The flight rule** (`_fleet_judge`, every `FL_EVERY` 10 s per AI
  side): fighting strength (guns x hull % x the share of the guns its
  crew can serve, ships still fighting) against the enemy's, and the
  exchange over the last 2 minutes (`fl_hist`: damage samples, hull and
  crew lost by share, a ship struck or taken a whole ship). It flees when
  under its skill's `SEA_FLEE_RATIO` and it took more than it dealt
  (`FL_TREND_MIN` at least), or with half its ships crippled (rigging
  under 25 %, hull or crew under 30 %) or taken, under that ratio +
  `FL_CRIP_ADD` 20 and losing the same way. Fleeing (`fl_on` 1), every
  ship that can sail away (`s_ffl`; not grappled, rigging 15 % or more:
  a dismasted ship fights on or strikes) runs for the edge on the
  heading, of 16, by which she leaves the field soonest at her polar's
  drive before the nearest enemy can reach that point, with clear water
  all the way (`_escape_goal`; a Skilled fleet with the weather gauge
  prefers a heading to windward of the beam); her broadsides fire at
  pursuers as they bear (fire at will). Off the edge she has escaped
  (`S_FLED`; the campaign's `FATE_FLED`: the ship survives). The pursuer
  chases by the ordinary engagement rule.
- **Rally**: no enemy within `FL_RALLY_M` 600 m for `FL_RALLY_TICKS` 1
  minute, the fleet stops fleeing (`fl_on` 2) and holds, hove to, until
  an enemy comes within `FL_HOLD_M` 800 m (at most `HOLD_TICKS` 3 min);
  the trend starts afresh, so it fights again and flees again only if it
  loses again.
- **The end**: as before a side with no ship fighting has lost, so a fleet
  that got away loses the field with its ships saved; `FL_CAP_TICKS` 4
  minutes of flight with no enemy within `FL_CLEAR_M` 300 m and its
  runners are withdrawn (escaped); at the time limit a fleet in flight
  never holds the field on power.
- **Profiles**: `ai_skill` per side from the scenario (as BattleSim;
  default Average): `SEA_FLEE_RATIO` Easy 70, Average 50, Skilled 40 %.
  No scenario passes it yet (campaign and custom sea battles play
  Average).
- **The fight**: full sail in the fight (battle sail only within 320 m of
  the enemy with land within 250 m to leeward or 400 m ahead: full sail
  there doubled the groundings); no grape from the AI (chain for a ship
  meaning to board, else round; a player's ships still load what they are
  told); `BOARD_PCT` 130 -> 160 (N3a's value). The per-ship flight (a
  wrecked ship runs when its side is weaker) is unchanged.

Knob, 192 seeds x 5 layouts against the never-fleeing player (before the
near-land sail rule): the ratio at 60 / 50 / 40 %: player wins 554 / 544 /
539 of 960, AI ships lost 855 / 877 / 907, escaped 407 / 355 / 309; no
fleet flight 533 / 953 / 241; the crippled trigger off / +20 / +50: 534 /
544 / 579 wins, 904 / 877 / 849 lost. Flight buys ships with battles: a
fleet that escapes concedes the field to a player who never quits.

Measured (before -> after; `tests/sea_probe.gd`, wind 60-120 deg, layouts
ns / we / gauge0 / gauge1 / camp):

- **Never-fleeing player**, 24 seeds: player wins 15 / 17 / 16 / 16 / 19
  (83 of 120) -> 8 / 13 / 14 / 16 / 13 (64); AI ships lost 151 -> 96,
  escaped 37 -> 43; the AI's exchange 79-93 -> 80-114 %; boardings 41 ->
  39. 96 seeds: 67 / 53 / 70 / 58 / 60 (308 of 480) -> 50 / 54 / 57 /
  56 / 55 (272), AI ships lost 551 -> 438, escaped 136 -> 165. By skill
  (96 x 5, after): Easy 280 wins, 398 lost, 229 escaped; Average 272 /
  438 / 165; Skilled 272 / 452 / 149.
- **AI against AI**, 96 seeds x 5 and the side order swapped: side 0
  wins 246 + 240 -> 257 + 233 of 960 (noise); groundings 133 + 110 ->
  121 + 114; 24 seeds: side 1 wins 59 -> 53 of 120, groundings 37 -> 17.
- **Player hove to** (the AI must come), 24 seeds: AI wins 80 -> 79 of
  120.
- Groundings against the never-fleeing player (96 x 5): the AI's 83 ->
  45, the player's 120 -> 108.

**Open**: the target (12 of 24 or fewer on every layout) is met on ns
and we only; with the gauge the scripted player still wins 14-16 of 24
(57 of 96 at gauge0, 56 at gauge1 and in the campaign's waters). The
exchange is now even (97-106 % over 96 seeds): what is left is that any
flight concedes the field, and the player never flees. Passing the
campaign faction's skill into sea battles is a follow-on.

### 32.1 Addendum: Douse (2026-10-22)

The owner asked for a Douse order ("lets add a douse to the list"). The
rule (`sim/sea_sim.gd` `O_DOUSE` 14 {unit, on}, `s_douse` hashed and
snapshotted): while on, the ship's guns neither fire nor reload (a loaded
broadside keeps its load), the crew fight the fire at `DOUSE_FIGHT_PCT`
200 % (`fire_fight`: 45 x 2 x the crew share against a mean growth of 35
a second, so a crew of 39 % still gains, against 78 % without), and her
men in a deck melee strike and fire at `DOUSE_DECK_PCT` 50 % (a grappled
ship may douse; the outside melee of scenario "deck" 1 is not touched).
It turns off by itself the second the fire is out, and when she sinks or
is taken; refused with no fire and for a fire ship. It goes through the
lockstep as every other ship order (`_sim_order`, the issuer's own ship
only).

The battle AI (`_think_douse`, every think, before the grappled / fleeing
returns): no douse with an enemy at her (grappled, or one within
`DOUSE_BOARD_M` 200 m sailing to board her; a dousing ship stops when
one comes). Easy douses at once on any fire; Average when the fire is
outgrowing the crew (mean growth over `fire_fight` at the current crew);
Skilled when it is outgrowing them and nothing is in either broadside's
arc and range, or once the fire is past 3 / 5 of `MAG_LV` (300) whatever
bears (without that, a Skilled ship always in action never doused and
blew up as before). Off when it is out.

Measured (`tests/sea_probe.gd`, 24 seeds x 5 layouts, before -> after;
the probe's new fire line):

- **AI against AI** (and the side order swapped): fires 67 + 71 -> 55 +
  74, put out 8 + 11 -> 42 + 53; ships lost burning 47 + 46 -> 12 + 10;
  magazines 47 + 44 -> 12 + 10; side 0 wins 67 + 61 -> 72 + 59 of 240
  (noise; the unswapped run was 67 / 53 before too).
- **Never-fleeing player** (`--modes=order`; the player never douses):
  player wins 64 -> 62 of 120, AI ships lost 96 -> 86, escaped 43 -> 46,
  AI ships lost burning 25 -> 6, the AI's exchange 100 -> 106 %.
- **Player hove to**: AI wins 79 -> 81, AI ships lost burning 14 -> 4,
  exchange 110 -> 118 %.
- **By skill** (AI against AI, both sides that skill): ships lost burning
  Easy 36 -> 8, Average 47 -> 12, Skilled 46 -> 18; douse orders 53 / 42
  / 47, fires out while dousing 46 / 35 / 25; exchange 93 / 95 / 94 %.
  Easy loses fewest ships to fire: its guns go silent for every fire,
  which costs it nothing measurable here.
- Nothing else moved beyond noise (battle length, boardings, groundings).
  `tests/sea_checks.gd` flight() now counts 8 seeds (fled 8 / 8, 5
  escaped, 8 held): over seeds 1-4, 2 of the 4 escapes were the companion
  of a ship whose magazine blew; doused, she survives to strike and both
  are taken (seeds 1-16: 10 escapes before, 8 after).

## 33. Rome walls 1-2: the street stack and the storm's run (2026-10-22)

Measured first (32 seeds, the six Rome plan towns Athens / Carthage / Syracuse /
Rome / Massalia / Arverni, equal force): pooled attacker wins walls 1 / 2 / 3 =
36 / 27 / 21 % (targets 56 / 38 / 25; generated maps 56 / 27 / 21). The gate
fell in 0.9-3 min at walls 1; 650-814 of ~1,030 defenders then stood in the
street stack at the first mouth behind it; almost nobody was inside 30-60 s
after the breach (the ladder parties never climbed at walls 1 because the
engines broke the gate first); the attackers lost 250-320 men in the 30 m
outside the gate and 95-150 at the gate inside, and broke with 28-30 % left
(the 35 % withdrawal fired in 4 of 576 battles). On the Greek and Punic plans
the plaza is the citadel.

Levers measured one at a time (8 then 16 then 32 seeds) and what stayed:
- *Storm flow:* ladder parties kept at their escalade beside the gate 35/29 ->
  19/4 (dropped); a second wave held 40 m out while the gateway is full: no
  change (dropped); **kept:** on a Rome plan the storm's foot other than pikes
  outside the houses attack at the run (35/29 -> 40/42 at 8 seeds).
- *The defenders' street stack:* a reaction range of 8 m 35/29 -> 40/27
  (dropped); narrower mouths (gate + 4 / 8 / 10 m) overshoot walls 1 or walls 3
  (dropped); **kept:** `S_ROME_STACK` 4: the stack behind the breach holds at
  most 4 units and the not-fighting tail holds the plaza (`_compact`, no relief
  under way), 39/29/23 -> 52/32/24 at 16 seeds.
- *Gate hit points at walls 2:* queued, not run (the siege pass found the
  battery time did not move with gate HP). *Withdrawal rule:* not a lever
  (fires in 4 of 576). *Citadel:* diagnosed only: with the two levers the
  attackers break the citadel gate far more often (Carthage 6 -> 25 of 32,
  Syracuse 7 -> 24, Massalia 13 -> 28) and then lose inside the Byrsa
  (Carthage 7 wins of 25 that reached the plaza).

Kept (levers 1 + 2, `_rome_plan`: `n_outer > 0`, a plan town, not the West),
32 seeds: walls 1 / 2 / 3 = 36 / 27 / 21 -> **58 / 35 / 23 %**; by town
after: 78 / 22 / 72 / 56 / 47 / 75, 47 / 16 / 41 / 9 / 16 / 81, 16 / 9 / 22 /
28 / 31 / 34. No new sim state; the West, generated maps and scenario keys
untouched by construction; campaign_sim pins unchanged. Open: the Punic and
Greek citadel fight, Rome's castrum at walls 2 (38 -> 9 %: the plaza fight
against the stack's tail), gate HP at walls 2, Carthage the low outlier.

## 34. The West AI after the Caribbean batch 1 (2026-10-23)

Measured first (`campaign_sim` West, all Average, 60 turns; 24 seeds by `--seed0=0/6/12/18` shards of 6): HEAD
53.3 battles a seed, 15 eliminations in 24 seeds (the six pin seeds: 55.7 and 1), 22.8 landings. Nobody raised a
mortar or a grenadier (the build-up stopped at Workshop 1 / Barracks 2: New Spain and Tierra Firme best Workshop 1.0,
England 0.8); the Miskito raised only canoe raiders (13 a campaign, 3 warriors), France more coureurs than
buccaneers; raider-only armies existed about 5 army-turns a campaign and an afloat army planned with land fields only
(every settlement INF from a sea cell: it stood still). As built (`campaign/cai.gd`, `cai_profile.gd` ids 115-119,
the pack lists `CData.AI_BUILDUP_LINES` / `AI_SPECIALISTS` in `campaign/data/west.gd`; Rome has neither, so Rome is
unchanged by construction: its 6 x 60, format 8, `ROME_20` and the goldens did not move):

- **Build-up lines.** `_wants_engines` counts the mortar. After its usual goals the build-up (section 24) raises, at
  the same military centre, the chain of each pack build-up line the mix holds (the West: `mortar` -> Workshop 3,
  `grenadier` -> Barracks 3) to the level its first roster tier needs (`_line_entry`, `CRules.needs`), up to
  `BU_LINE_MAX`, in a faction of at least `BU_LINE_REGIONS` regions. Such a goal never holds the rest of the building
  (`BU_SAVE` does not apply: it is built when the build-up's budget covers it), so the economy is not starved for a
  2,000-gold Workshop 3.
- **A Range first.** A recruiting centre (capital or town) without a Range puts it first in its wants when one Range
  line has at least `RANGE_FIRST_PCT` % of the mix (towns start with a Barracks only; the West's main line, the
  musket, is raised at the Range). Rome's largest Range line is 25 %.
- **Specialists.** `_mix_type`: the mix recruiting takes the best tier the centre allows, but a line's specialist
  (`AI_SPECIALISTS`: canoe raiders, boarding grenadiers, coureurs) only while the faction holds fewer than
  `SPECIALIST_PCT` % of the line's units (armies and queues) as that specialist; else the best tier below it there
  (the warriors, cutlass men, buccaneers). The Itza holcan are the only unit of their line, not a specialist.
- **Bands.** `AMPHIB_BAND`: an amphibious recruit (the canoe raiders) joins only an amphibious army at the
  settlement, else raises a new one (`"new": 1`); other recruits never join a band; a region whose unnamed recruits
  would mix with a band's this turn waits a turn; the AI's `_merge` and the wagon skip bands, and the rules'
  end-of-turn auto-merge (`CRules._auto_merge6`) no longer merges an amphibious army with a land-bound one (a rule,
  pack-agnostic; docs/design/campaign_rules.md "Amphibious armies"). Each free band may also raid on its own (the
  richest region at war it reaches this turn that no army threatens beyond its strength), besides the faction's one
  raid a turn.
- **Water distances.** An amphibious army plans with distance fields over the coastal water (`CGrid.field(src,
  sea, true)`, `CGrid.downhill(..., true)`, the water tables of `CGrid._water_tables`; `CAI._sf_of`,
  `_water_fields`): its turns to every settlement (the targets, raids, screens, the frontier march), the threat it
  poses to the other side's cities (`_context6`, `_reach_def`, `_border_weak`), `_reaches`, `eta`, the "toward"
  waypoint and the staging trail. The fields are static memos like the land ones (no state; the same on every
  client), built once on the first amphibious army: about 0.3 s once (a turn of 388 ms against 69 ms in seed 1000),
  mean turn time unchanged within the machine's load (24 seeds 116 -> 105 ms; Rome 73 -> 68). Test switch
  `CAI.no_water` (`campaign_sim --no-water`).

| Knob (`cai_profile.gd`, ids 115-119) | Easy | Average | Skilled |
|---|---|---|---|
| `BU_LINE_MAX` | 0 | 3 | 3 |
| `BU_LINE_REGIONS` | 0 | 3 | 3 |
| `RANGE_FIRST_PCT` | 0 | 30 | 30 |
| `SPECIALIST_PCT` | 100 (as before) | 30 | 30 |
| `AMPHIB_BAND` | 0 | 1 | 1 |

Easy builds and recruits as before, but for two pack-agnostic pieces: France and Tierra Firme now want a Workshop
(the mortar counts as an engine) and an amphibious army plans by the water and keeps out of the auto-merge.

Measured per change (the six pin seeds, West, Average; each step as built, the later pieces switched off by
`--knob` / `--no-water`):

| Step | Battles | Eliminated | Landings |
|---|---|---|---|
| HEAD | 55.7 | 1 (Miskito 44) | 23.8 |
| + build-up lines and a Range first (`--knob=a:118=100 --knob=a:119=0 --no-water`) | 54.0 | 5 | 20.0 |
| + specialists (`--knob=a:119=0 --no-water`) | 53.7 | 2 | 22.3 |
| + bands, land fields (`--no-water`; before the auto-merge exemption) | 58.3 | 3 | 23.8 |
| + water fields (before the auto-merge exemption) | 61.3 | 5 | 24.2 |
| + bands kept out of the auto-merge (as built) | 53.3 | 5 | 21.5 |

24 seeds, HEAD -> as built: battles 53.3 -> 54.9 a seed, eliminations 15 -> 18 (the Brethren 3 -> 4, the Dutch
1 -> 2, England 0 -> 1, France 1 -> 2, the Itza 5 -> 4, the Miskito 5 -> 5), landings 22.8 -> 20.8, sea battles
27.1 -> 28.9; best Workshop New Spain / Tierra Firme 1.0 / 1.0 -> 2.6 / 2.7, mortars 0 -> 0.2 / 0.5 a campaign,
heavy guns 0 -> 0.3 (New Spain); Ranges finished 30.1 -> 39.6 a campaign, farms 21.9 -> 16.9 and markets 23.8 ->
15.5 (the build-up's price), regions held alike (New Spain 13.5 -> 13.2, Tierra Firme 13.0 -> 13.8); the Miskito
raise warriors 3.4 -> 10.1 and raiders 13.0 -> 5.3, France buccaneers 2.0 -> 3.8 and coureurs 3.8 -> 2.6;
amphibious army-turns about 5 -> 61 a campaign, afloat at a turn's end 1.8, a town taken from the water once in 24
campaigns.

Knobs probed for the pacing (24 seeds; battles / eliminations / landings): `SPECIALIST_PCT` 30 / 40 / 50 = 54.9 / 18
/ 20.8, 51.5 / 17 / 21.4, 55.0 / 22 / 22.0 (not monotone: the seed noise); `RANGE_FIRST_PCT` 0 = 52.1 / 19 / 22.2.
Kept 30 and 30. No knob shared with Rome was touched, so the battles stay below the 56-64 the six pin seeds once
showed (24 seeds put HEAD at 53.3 too).

Open: England reaches Barracks 3 almost never (best Barracks 1.8; no grenadier in the 24 campaigns, one at
`SPECIALIST_PCT` 50: 5 regions and the Workshop goals first), the mortar's 2-3 % mix share gives a piece or none; the bands mostly sit in the Miskito
capital, held there by the landing threat (`_hold`, section 12.2), and take a town from the water once in 24
campaigns; the 0.3 s water-field build is a one-off on the web too (not measured there).

## 35. Destruction AI: battering the walls, the breach, the defenders (2026-10-23)

The battle AI's follow-up of the destruction sim (docs/design/siege_and_towns.md "Destruction AI (as built)", the
rules in full). `sim/siege_ai.gd` section "destruction AI", the wall target order in `sim/battle_sim.gd`; no new AI
memory (each choice is made again every think from the hashed hit points and units). Moves counted in `C_SIEGE`.

- **Batter the wall**: attacking batteries that break walls (lobbing engines, flat guns of 400 a shot; lighter flat
  guns only when the side has none; bolts never) shoot the stretch nearest the attacked gate (within 100 m, with a
  way through it once breached) until it is breached, from before that stretch; they finish a hurt stretch if the
  gate fell first, and batter the citadel's or a stormed fort's wall by its shut gate.
- **The breach is an entry**: the assault begins; the `S_BREACH_UNITS` foot nearest the breach go in through it.
- **Defenders**: off a stretch being battered down (under `S_WALL_LEAVE_PCT`, hit in the last 10 s) to a joined
  stretch or the ground behind; out of a building under `S_RUIN_LEAVE_PCT` to the nearest cover; `S_PLUG` reserve (or waiting
  stack) foot units plug each breach.

| Knob (`ai_profile.gd`, ids 275-282) | Easy | Average | Skilled |
|---|---|---|---|
| `S_BATTER` | 0 | 1 | 1 |
| `S_BATTER_DMG` | 150 | 150 | 150 |
| `S_BATTER_PCT` | 0 | 100 | 100 |
| `S_BATTER_T` (ticks) | 0 | 4800 | 4800 |
| `S_BREACH_UNITS` | 2 | 3 | 4 |
| `S_WALL_LEAVE_PCT` | 0 | 33 | 33 |
| `S_RUIN_LEAVE_PCT` | 0 | 33 | 33 |
| `S_PLUG` | 0 | 4 | 4 |

Measured (16 seeds, attacker wins %): rome_walls walls 1 / 2 / 3 58 / 32 / 24 -> 74 / 44 / 20 (a breach in 95 % of the
battles, nearly always before the gate); west_walls walls 0 / 1 / 2 54 / 39 / 34 -> 51 / 38 / 34 (no West battery
battered: the plan towns have no outer wall and the fort was left be). Tuned: `S_PLUG` 1 -> 4 (with one plug the
breach beat the stack waiting at the shut gate: 88 / 65 / 47; 3 / 4 / 5 plugs at 8 seeds 92 / 44 / 38, 81 / 52 / 23,
60 / 29 / 19); `S_BATTER_T` 2,400 tried and reverted (it cut walls 3 more than walls 2). Open: walls 3 not up (19 ->
33 in section 39), walls 1
up 16, large per-town swings (Arverni down), the West fort stormed with guns, a shock role for the breach party.

## 36. Roles, step 2: the AI and the role behaviours (2026-10-23)

The battle AI's part of docs/design/battle_sim.md "Roles, step 2 (as built)" (the rules in full there). Most of the
behaviours are the sim's own triggers on Auto (every unit's default), so the AI gets them by giving the orders it
gave before; two knobs decide where a level keeps the old play. No new AI memory.

- **Skirmishers** seek cover and skirmish: the sim's drift draws a standing skirmish unit's men in the Cover stance
  into the woods within 8 m (`R_SK_DRIFT`; the existing `_cover_spot` and skirmish fall-back are unchanged).
- **Horse_skirmish caracoles**: the AI's attack orders by pistoleers, cuirassiers and dragoons are caracoles (close,
  fire, ride back, reload, again); a target that breaks or is locked in a melee with ours is charged by the sim's
  rule, so the AI's flank attacks on engaged units still go home. Easy (`R_CARACOLE` 0) sends `"charge": 1` on every
  attack by them (the old charge). Re-ordering the same target each second does not reset a pass.
- **Grenades Auto**: thrown at blocks, held buildings and a shut gate in reach (the sim's trigger); no knob.
- **Pistols**: always Auto (the rotation is the sim's).
- **Batter** as already built (section 35, `S_BATTER`); the player's batter order reuses its stretch choice.

| Knob (`ai_profile.gd`, ids 283-284) | Easy | Average | Skilled |
|---|---|---|---|
| `R_CARACOLE` | 0 | 1 | 1 |
| `R_SK_DRIFT` | 0 | 1 | 1 |

Measured with the sim rules (16 seeds, attacker wins %): rome_walls 74 / 44 / 20 -> 74 / 41 / 19, west_named walls
0 / 1 / 2 49 / 36 / 14 -> 54 / 33 / 12 (none beyond its interval); the asymmetry probe (Spanish wins of 16) woods 0 -> 0,
field 14 -> 11. Open: the AI's skirmishers rarely stand still long enough to drift in a field battle (`stat_skd_men` 0
in the probe); the AI never uses Hold or Use now (the grenades' Use now at a gate, the batter at buildings: built in
section 39 for sieges) nor the caracole's charge flag above Easy.

## 37. The West AI after the Caribbean batch 2: mix lines that can be raised (2026-10-24)

(Asked for as "section 36"; 36 was taken by the roles' AI.) The 6 pin seeds went from 5 eliminations before batch 2
to 2 after, with battles alike, and the two suspects were (a) the mixes diluted for the new rows, (b) marines and
naval guns needing a Shipyard the build-up never builds. Measured first (`campaign_sim` West, all Average, 60 turns;
144 seeds as six `--seed0` shards of 24; a probe copy counted every recruit by the line picked and every capture by
taker and victim):

- **No pacing drop.** Before batch 2 (`c4f39dd`) 89 eliminations in 144 seeds, 53.9 battles a seed, 19.4 sea
  crossings; batch 2 (`101c39f`) 85, 54.5, 19.3; the Spanish held 12.3 / 12.8 regions at turn 60 before (New Spain /
  Tierra Firme) and 12.5 / 13.1 after. The three 24-seed blocks before batch 2 had 18, 9 and 20 eliminations: the
  pin seeds' 5 -> 2 is seed noise. Restoring only the old mixes on top of batch 2, per group (Spain; the natives; the
  others), gave 16, 22 and 21 in the first 24 seeds (batch 2 there: 12, all old mixes 17), so no mix stands out.
- **(b) is not it.** England's and the Dutch capitals, Port Royal and Port of Spain, hold a Shipyard 2 by turn 5
  (seed 1000 trace), and the fleet AI builds one at its best port. What the Dutch marines lack is a Barracks 2 there
  (the Dutch seldom reach it), and England's marine line never got picked: its share (3) ties with the grenadier's,
  which comes first in `LINE_ORDER` and is dead (Barracks 3). A probe that built the Shipyard and the line's other
  building at a harbour centre, port lines first in `AI_BUILDUP_LINES`, changed nothing (72 seeds: 42 eliminations
  against 41, Shipyards finished 11 -> 12, no more marines); not kept.
- **The real defect: dead lines take the pick.** `_next_line` picks the mix line furthest below its share; a line
  no recruiting centre has the buildings for stays furthest below for ever, its recruit is "" and the region raises
  `_any_type` (the first unit its recruit options allow: pikemen, rodeleros, warriors). Share of recruits raised that
  way at batch 2: New Spain 20 % (the field guns), Tierra Firme 17 % (the mortars), England 43 % (the grenadiers),
  France 25 % (the dragoons), the Dutch 51 % (the marines 30 % of the picks: batch 2's new dead line), the Brethren
  15 %, the Itza 71 % (the holcan); the Miskito 1 %. Before batch 2 the same, the Dutch 35 %. So the mixes were
  largely not what the armies were made of (the Spanish rodeleros and England's pikemen came from the fallback).

As built: **`MIX_LIVE`** (`cai_profile.gd` id 120, `SK_SUPPORT + 45`; Easy 0, Average 1, Skilled 1). In a pack with
`CData.AI_LIVE_MIX` (the West's `west.gd` sets 1; Rome has none, so Rome is unchanged by construction) `_recruit`
first collects the mix lines some recruiting centre (the regions it scores: a military building, no battle) has every
building for, at any tier of the roster (`_live_lines`, `_has_buildings`: `CRules.needs` and `UNIT_NEEDS`, buildings
only, not money or the queue), and `_next_line` picks only among those (none live: every line, as before). A dead
line's share goes to the rest in proportion; it comes back the turn its buildings stand. The mixes, rosters, unit
stats, the build-up and the garrison rule are untouched (militia stay out of every field mix).

| Knob (`cai_profile.gd`, id 120) | Easy | Average | Skilled |
|---|---|---|---|
| `MIX_LIVE` | 0 (as before) | 1 | 1 |

Measured, 144 seeds, batch 2 -> as built: eliminations 85 -> 88 (before batch 2 89; the Brethren 33 -> 32, the
Miskito 23 -> 21, the Itza 18 -> 23, the Dutch 7 -> 6, England 3 -> 4, France 1 -> 2), battles 54.5 -> 55.5 a seed,
sea crossings 19.3 -> 19.5, captures 23.3 -> 23.8 a campaign; regions at turn 60 New Spain 12.5 -> 12.1, Tierra Firme
13.1 -> 13.2 (the Spanish stay the two largest; Tierra Firme takes 5.0 regions a campaign, the most). Fallback
recruits 0-4 % for every side. Units standing at turn 60 (72 seeds, per surviving faction): marines England 0 ->
0.7, the Dutch 0.5 -> 0.8; naval guns the Dutch 0 -> 0.3, the Brethren 0 -> 0.1; the Itza atlatl 0.8 -> 4.5 and
slingers 0.7 -> 3.9 (warriors 27.9 -> 21.3, bowmen 9.5 -> 13.2); New Spain rodeleros 10.5 -> 6.7 and pikemen 7.6 ->
8.2, light guns 1.0 -> 1.5, war dogs 0.2 -> 1.1; England pikemen 6.5 -> 4.8, pistoleers 3.2 -> 4.3, light guns
0.8 -> 1.5. The 6 pin seeds: eliminations 2 (Itza 58, Brethren 59) -> 4 (Miskito 57; Brethren 58, Itza 23; Miskito
28), battles 53.7 -> 52.5, sea crossings 19.8 -> 19.8. Mean turn time alike (57-80 ms a seed against 56-73, on a
loaded machine).

Also measured and not kept: the main lines restored to their pre-batch-2 weights with the new rows' shares taken
from the second line (New Spain heavy 15 -> 12, cav 9 -> 12; Tierra Firme heavy 15 -> 11, cav 21 -> 25; England
musket 34 -> 37, pike 25 -> 22; the Dutch musket 35 -> 40, pike 25 -> 20, light gun 15 -> 13, field gun 5 -> 7; the
Brethren buccaneer 31 -> 35, heavy 35 -> 31; the Itza light 45 -> 52, sling 7 -> 3, archer 27 -> 28, javelin 8 ->
4; the Miskito light 44 -> 50, sling 6 -> 3, archer 30 -> 27) on top of `MIX_LIVE`: 78 eliminations in 144 seeds,
54.6 battles.

Open: the pin seeds swing 2-5 eliminations on noise alone; pacing claims want 72+ seeds (`tools/balance` or six
`--seed0` shards). The Dutch rarely reach the Barracks 2 their marines need; the holcan, grenadiers and mortars
still wait for buildings the build-up seldom finishes (their shares now go to the live lines meanwhile).


## 38. The West's characters (2026-10-24)

(37 is the West AI after batch 2.) The campaign AI raised Rome's six characters in the West before batch 3 (the same
`_characters` code, Barracks 2 for heroes); the West now has four of its own (docs/design/battle_sim.md "The Caribbean
roster, batch 3 (as built)") and Rome's six are refused there (`CChars.allowed`). No new knob: `CHAR_HERO` (Average,
Skilled) and `CHAR_DIPLOMAT` (Skilled) keep their meaning.

- **Heroes** (`_hero_kind_of(f, army)`): in the West a sea captain for England, France, the Dutch and the Brethren, a shaman
  for the Itza and the Miskito, none for New Spain and Tierra Firme (they raised Rome's heroes before). Every army of
  `CHAR_HERO` units or more at a city with the building gets one, as before, when the money stays above the reserve. A sea
  captain needs a Shipyard 1 in the city the army stands in (the fleet AI already builds one at the nations' best port; the
  build-up adds no Shipyard goal); a shaman a Barracks 1, which the build-up goal now asks of the natives' centre (it asked
  every faction Barracks 2 in the West before; Rome's goal is unchanged).
- **Agents**: the Skilled diplomat is a missionary, for New Spain, Tierra Firme and France (the factions that may raise
  one; the others and the natives raise none). Privateers never, as assassins never.
- **In battle** the character AI (section 27) is by kind and unchanged: a sea captain or shaman (`CK_FOOT`) is posted behind
  the line centre, whatever his `au_roles`; the missionary parleys as the diplomat does (the pick does not weigh the bonus).
  (Both since section 39: posted behind the units his aura serves; the pick prefers a target of the bonus.)

Measured, `campaign_sim` West, all Average, 60 turns (before = HEAD 158f4c2): the 6 pin seeds eliminations 4 -> 2,
battles 52.5 -> 52.3 a seed; 72 seeds (three `--seed0` shards of 24) eliminations 43 -> 50, battles 54.5 -> 51.8 a seed,
characters raised 5.4 -> 4.8 a campaign, sea battles 26.6 -> 27.6, landings 21.5 -> 19.6; eliminated by faction (before ->
after): the Brethren 17 -> 14, the Miskito 10 -> 14, the Itza 12 -> 12, the Dutch 1 -> 8, France 2 -> 1, England 1 -> 0, New
Spain 0 -> 1. The Dutch swing is the largest and the only one outside the earlier 144-seed spread (6 in 144 at section 37);
the Spanish lose their heroes' `char_pct` 6 in auto-resolve, the coast nations and natives keep a hero at 6 and 4. Not
tuned; Rome unmoved (the Rome pins are identical).


## 39. Battle AI loose ends after batch 3 (2026-10-24)

The battle AI's open items from batch 3 (docs/design/battle_sim.md "The Caribbean roster, batch 3 (as built)"), from
roles step 2 (section 36: "the AI never uses Hold or Use now") and from the destruction AI (section 35: "walls 3 not
up"). Battle AI only: no unit stat, no sim rule; no new AI memory (every choice is read again each think from hashed
state: the ability table `u_abs` / `u_abt`, hit points, units).

- **Heroes posted by their aura.** A `CK_FOOT` hero whose row lists `au_roles` (the sea captain: skirmish, shock,
  marines; the shaman: skirmish, shock) stands `CH_BACK` behind the middle of the ready friendly units his aura serves
  (`BattleAI._aura_centre`: `_ch_bit` and `_ch_serves`, as the sim's aura; not characters, wagons or generals), along
  the army's facing, re-posted at every think as they move; none of them on the field: behind the line centre as before
  (`CH_BACK` + 10 m). Rome's heroes (no `au_roles`) are unchanged. No knob (every level).
- **The parley pick weighs `parley_bonus`** (`CH_PARLEY_BONUS`): of the routing enemy units in reach that may be asked,
  one the diplomat's row gives a bonus against comes first (the missionary: the natives), the nearest among them; else
  the nearest as before.
- **Grenades in a siege** (`R_GREN_SIEGE`; rows with the grenade ability attacking a town, `SiegeAI._gren_siege`): Use
  now at the nearest shut gate in reach and in a clear throw (`BattleSim._gren_gate`; not a West fort left be), else at
  the nearest enemy unit holding a building in range; with neither, Hold in the approach while outside the town (no
  grenade thrown at a block on the way) and Auto after. In the approach, with the attacked gate shut and the side's foot
  hacking it or its ram at it, they go up to 80 % of their range from the gate's face and throw once in reach; in the
  assault they storm with the foot (they were held 110 m out with the archers before, out of their 25 m reach). The
  ability order is given only when the wanted state differs.
- **The batter at buildings** (`R_BATTER_BLD`, metres; `SiegeAI._batter_bld`): an attacking siege battery (the batter
  ability: stone throwers, heavy guns, mortars) in the assault with no stretch to batter Uses now its batter on the
  building held by an enemy unit (standing) whose middle lies within `R_BATTER_BLD` of the storm's route (from the
  side's way in, the breach's inside edge, else the attacked gate, else the army's middle, to the plaza) and within
  `S_ART_REACH_PCT` of its range from where it stands, the nearest the way in first; when that building falls (or its
  men leave and none qualifies) back to Auto.
- **Walls 3 under the destruction AI** (siege logs first, then the change). Rome's harness at HEAD (`48a6eef61b`, 16
  seeds): walls 1 / 2 / 3 74 / 41 / 19 %; at walls 3 18 attacker wins, 55 defender wins, 23 draws of 96, a breach in 95
  of 96 (83 before the gate fell). A probe (`fair_siege` as the harness, 6 towns x 4 seeds at walls 3, the defenders'
  AI modes and men every 20 s from the first breach, kills per defender mode) found:
  - **The guessed lever is not it.** The gate stack does not wait at the shut gate while the breach is stormed: the
    plug takes the stack's foot (A_MOUTH at a shut gate counts as free, nearest first), so 20 s after the breach the
    four plugs (357-374 men) are the stack's units. In 9 of the 11 breach-first battles traced in full the stack was
    empty then; in Attica's two (a stack of six) two units (160-218 men) stayed at the gate. More men at the breach
    (the stack's tail peeling off to it) would only make the plug stronger, and the plug is what holds (next).
  - **The plug holds the deep breach.** In 7 of 24 the attackers never had 100 men inside (all four Arverni seeds,
    Attica 3, Zeugitana 1 and 3): they bled at the rubble. Kills by defender mode (Arverni seeds 0-1): walls
    3 the plugs 376 / 413, the wall units 178 / 83, the towers 20 / 9; walls 1 the plugs 155 / 187 and the plaza
    reserve 104 / 159 (the attackers got through and fought the reserve). Walls 3's rubble is 12 m deep (`WALL_T` 8 /
    10 / 12) against 8 at walls 1, so four plugs side by side at its inner edge meet the storm while it is still on the
    slow rubble.
  - **The rest are the endgame.** 5 of 24 were won; in 12 the attackers got in (160-530 men inside at the most) and
    did not win in the 15 minutes (5 draws, 7 losses); in 8 of those 12 the citadel was shut and holding at the end
    (Massalia, Sicilia, Attica, Zeugitana: its Byrsa is the plaza, so the capture cannot start while it holds), with
    routers penned in by the shut gates.
  - **Zeugitana's breach in a tower.** Punic walls carry large towers: 6 of the 7-9 Zeugitana stretches at walls 3 have the
    breach's outside point (`ws_side_pt`, where the breach's graph node stands) inside a tower's cells, so a breach
    there is unreachable: seed 1 at walls 3 breached such a stretch at 4:20 and its storm stood against the tower for
    the rest of the battle (a draw, no fighting).
- **The change** (two knobs):
  - `S_PLUG_DEEP` (thickness; Easy 0, Average / Skilled 12 m): at a breach in walls that thick or more (walls 3; the
    Punic walls 2) the last of its plugs (by index, of two or more) is a second line `PLUG_BACK` 20 m further in,
    fighting what comes within `PLUG_REACT` of its own post; the first three hold the rubble's edge as before.
  - `S_BATTER_OPEN` (Easy 0, Average / Skilled 1): `_batter_stretch` skips a stretch whose breach's outside point is
    not open ground (a tower's cells). The player's batter order's own pick (`batter_pick`) uses the same choice.
  - Tried (6 towns x 16 seeds at walls 3 unless said): one plug fewer at a deep breach (S_PLUG 3 there): walls 3 19
    -> 36, walls 1 / 2 74 / 43 (the full plan), Attica 12 -> 56 and Latium 25 -> 62, Arverni unmoved 12; the second
    line instead: 19 -> 33 with Arverni 12 -> 44 (kept: in the target and spread over more towns); `S_BATTER_OPEN`
    alone: walls 3 unmoved (Zeugitana 0 -> 0: its stall turns into the gate's assault and the Byrsa endgame).

| Knob (`ai_profile.gd`, ids 285-289) | Easy | Average | Skilled |
|---|---|---|---|
| `CH_PARLEY_BONUS` | 0 | 1 | 1 |
| `R_GREN_SIEGE` | 0 | 1 | 1 |
| `R_BATTER_BLD` | 0 | 40 m | 40 m |
| `S_PLUG_DEEP` | 0 | 12 m | 12 m |
| `S_BATTER_OPEN` | 0 | 1 | 1 |

Measured (`tools/balance`, 16 seeds, attacker wins %, HEAD `48a6eef61b` -> `7780896732`; the code as committed differs
only in comments, hash `bcf88fc68a`): rome_walls walls 1 / 2 / 3
74 / 41 / 19 -> 74 / 39 / 33 (pooled 44 -> 49); walls 1 identical in every town (8 m walls: no rule here bites), walls 2
moved only in Zeugitana (Punic walls 2 are 12 m: 38 -> 25, within its interval); walls 3 per town Zeugitana 0 -> 12
(in 4 of 16 the stretch by the attacked gate had its outside point in a tower: no battering now, the gate's assault
instead: 3 draws and a loss, against 2 draws and 2 losses by the stalled breach; its 2 wins are the second line's), Attica 12 -> 31, Sicilia 44
-> 25, Latium 25 -> 62, Massalia 19 -> 25, Arverni 12 -> 44 (Latium and Arverni beyond their intervals); median
minutes to decide at walls 3 9.6 -> 11.0. west_walls walls 0 / 1 / 2 49 / 37 / 28 -> 49 / 37 / 28,
identical in every town (no West wall is 12 m thick, the plan towns have no outer wall to batter, and the sets field
no grenadiers, siege guns or characters). The tests: `chars_test` `ai` (the sea
captain 13 m off his units' middle and behind them, Rome's Champion 95 m off it; with none of his units, both behind the
line centre; the missionary's parley at the native band, Rome's diplomat's at the nearer pike block), `roles_sim_test`
`ai` (grenadiers Hold 980 ticks of the approach, up to 31 m from the gate being hacked, Auto once it falls; set by a shut
gate, Use now and 31 thrown in 15 s; a mortar battery's Use now at a held building in a West town, 3 shots, then Auto;
Easy no ability order and no building shot). Determinism: 3 of the 45 run hashes moved, all AI sieges at 12 m walls
(siege_castrum@ai `5a3dd8f5` -> `27b9ec5b`, siege_punic@ai `dfb56818` -> `97da0b57`, siege_eq_ring3 `d4f9a12c` ->
`c4a9f1db`; siege_punic@ai now takes the town by a breach with its gate still shut, so its coverage asks `breaches`
for `gate_broken`); the flat goldens, every open-field run and the campaign AI goldens unmoved; lockstep unmoved.

Open: the walls-3 endgame (a citadel shut and holding at the time limit in 8 of 24 traced battles; Carthage's Byrsa is
its plaza; routers penned in by shut gates keep their units on the field); the Punic towers' breach points (a sim
matter: `ws_side_pt` can fall in a tower's cells; the AI only avoids battering such a stretch); per-town swings at walls
3 stay large (Sicilia down 19, Latium up 38); the harness fields no grenadiers, mortars, held buildings or characters,
so items 1-2 are measured by the tests only.

## 40. The Dutch after batch 3, England's grenadiers (2026-10-24)

Measured on 144 West seeds (six `--seed0` shards of 24, 60 turns, all Average) with a probe
copy of `campaign_sim` that tallied each faction's characters and their gold, its recruits and their gold, who took
whose regions, the buildings finished per faction and the sea battles fought with a `sea_cq` character aboard.

**The Dutch.** Before batch 3 (`158f4c2`) the Dutch were eliminated in 6 of 144 seeds, after it (`9f4eb17`) in 21
(the 72-seed 1 -> 8 was real: shards 3-5 went 5 -> 13). Tierra Firme finished them in 20 of the 21. Two causes:

- **A 1,500-gold sea captain.** The Dutch raised 1.06 sea captains a campaign (0.33 heroes before: Rome's needed a
  Barracks 2), 1,583 gold of a treasury of about 900, and recruited 8.2 units a campaign against 14.1 (4,981 gold
  against 8,821); at turn 10 they held 2.8 regions against 3.9. England and France raised 0.9 and 0.5. His aura
  serves skirmishers, shock troops and marines, and a coast nation's army is pike and musket. `sea_cq` did nothing
  that mattered: fleets carrying a captain fought 0.07 of the Dutch sea battles a campaign.
- **The Barracks 2 goal.** Batch 3 kept the build-up's hero goal (Barracks 2 at the military centre) for the natives
  only (as a shaman's Barracks 1); the coast nations lost it, and with it the Barracks 2 their marines and veteran
  pikes need (England's best Barracks 2 in 97 of 140 surviving campaigns before, 21 of 144 after; marines at turn 60
  0.7 -> 0.1).

Ablations, 144 seeds (Dutch eliminated / all eliminations / battles a seed): HEAD 21 / 97 / 51.3; a money floor (a
character only with his price left in the bank) 12 / 97 / 55.6; the aura rule alone at 20 / 34 / 50 % 12-13 / 80 /
54.7-54.9 (the same seeds); the Barracks 2 goal alone 19 / 93 / 51.7; both 8 / 91 / 56.1 (Barracks 2 for every West
faction, the natives too, 9 / 94). Before batch 3: 6 / 88 / 55.5.

**England's grenadiers.** No grenadier in 144 campaigns, none of them reached Barracks 3 (HEAD). Three things stood in
the way: the Barracks 2 above; the mortar's Workshop 3 goal came first in `AI_BUILDUP_LINES`, so the grenadier's goal
was never looked at while the Workshop waited (the goals are tried in order and the first unmet one is the build-up's
step); and a build-up step is paid from the money above the reserve (a turn's upkeep), about 1,000 of England's 1,800,
less than a Barracks 3 (1,600). Measured on top of the two Dutch fixes (Barracks 3 reached / campaigns with a
grenadier raised, of 144): grenadier line first 23 (of the survivors) / not counted (0.2 standing at turn 60 a
survivor); and saving for the Barracks 3 (BU_SAVE) 46 / 29; first and the Barracks 3 from the whole treasury 89 / 73; first and every Barracks step
from the whole treasury (as built) 121 / 105. The same rule for the mortars' Workshop steps too reached Barracks 3 in
136 and a grenadier in 128 but thinned England's line (units raised 20.4 -> 18.2, England eliminated 3 -> 6) and the
Spanish guns ate the Dutch (9 -> 15): not kept.

As built (`campaign/cai.gd`, `cai_profile.gd` ids 121-122, `campaign/data/west.gd`):

- **`CHAR_AURA_PCT`** (id 121; Easy 0, Average 34, Skilled 34): a hero whose row lists `au_roles` (the West's sea
  captain and shaman) is raised only for an army whose units his aura serves (`UT.row_named`) are at least that % of
  its units (`_aura_serves`). Rome's heroes list none: Rome unchanged.
- **The Barracks 2 goal** for every faction that raises heroes, as before batch 3, but the natives', who keep the
  shaman's Barracks 1.
- **Grenadiers first**: `AI_BUILDUP_LINES` = grenadier, mortar, marine, naval gun.
- **`BU_LINE_TREASURY`** (id 122; Easy 0, Average 1, Skilled 1): a build-up step on the Barracks when a pack build-up
  line needs its level 3 (England's grenadiers) is paid from the whole treasury, the reserve left out (a one-off
  building; upkeep is paid from the income). Not the Workshop (above).

| Knob (`cai_profile.gd`, ids 121-122) | Easy | Average | Skilled |
|---|---|---|---|
| `CHAR_AURA_PCT` | 0 | 34 | 34 |
| `BU_LINE_TREASURY` | 0 | 1 | 1 |

Measured, 144 seeds, HEAD -> as built (before batch 3 in brackets): eliminations 97 -> 88 (88), the Dutch 21 -> 9 (6),
the Brethren 28 -> 34 (32), the Itza 24 -> 14 (23), the Miskito 22 -> 28 (21), England 0 -> 3 (4), France 1 -> 0 (2),
New Spain 1 -> 0 (0); battles 51.3 -> 54.2 (55.5) a seed. Characters a campaign: Dutch sea captains 1.06 -> 0, English
0.88 -> 0.03, French 0.48 -> 0.02, the Brethren's 0.12 -> 0.19, shamans Itza 1.10 -> 1.31, Miskito 1.15 -> 1.11.
England: Barracks 2 built in 128 campaigns (median turn 20.5), Barracks 3 in 121 (median turn 29), a grenadier raised
in 105 of 144 campaigns, 1.2 a campaign (0.9 standing at turn 60 a survivor); units raised 22.9 -> 20.4 (20.8 before
batch 3), regions at turn 30 4.8 -> 4.7, its line at turn 60 musketeers 8.3, pikemen 6.3, pistoleers 4.4, marines 0.8;
mortars still 0 a campaign. The Dutch recruit 8.2 -> 13.5 units a campaign (14.1), hold 4.2 regions at turn 30
(4.2). Rome is unchanged by construction (its pins are identical).

Open: the sea captain is now an AI hero of the Brethren only (their armies are buccaneers and cutlass men); a coast
nation raises one only for a marine-heavy army. The mortar line waits for a Workshop 3 the build-up seldom pays
(England 6 of 141 at turn 60). The Itza / Miskito swing (24 / 22 -> 14 / 28) is within the spread of the earlier
144-seed runs (section 37: 18-23 / 21-23).

## 41. Rome under the diplomacy rules (2026-10-27)

The format-10 pins (6 x 60) had Rome eliminated in 2 of 6 seeds (1077 at turn 45, 1385 at turn 57), the format-6
and format-8 pins in 0 of 6. Diagnosis: **variance, nothing changed.**

1. The two deaths (`campaign_sim --format=10 --trace-faction=rome`, new): in 1077 Rome, at war with nobody since
   turn 33, declared war on its trade partner Gaul at turn 35 (repute -30: a treaty break and an unprovoked war),
   lost Roma the next turn and Aleria and Arretium the turn after (strength 17,449 -> 5,507 by turn 39); Carthage
   (turn 41) and the Greeks (turn 42) declared on a two-region Rome. In 1385 Rome declared three wars itself, on
   its trade partners Syracuse (turn 23) and Macedon (turn 29) and on the Greeks (turn 40; repute -49), took
   Syracuse; Gaul declared on a Rome busy with two wars at turn 44 (Gaul 28,137 against Rome 21,518, the
   WAR_RATIO_BUSY 90 test on its own strength) and took Arretium, Roma and Capua in one turn, the Greeks the south.
   Both are the military AI over-reaching and leaving its core open, which the format-8 runs show as well.
2. The diplomacy rules in those two seeds: no call to arms brought anyone in against Rome (in 1077 Rome's ally
   Syracuse refused both of Rome's calls, "too weak", and Macedon refused Epirus' call against Rome, "wars
   enough"; in 1385 Rome had no ally and no call was posted). The common-enemy alliances that formed (Macedon-
   Epirus at turn 24 in 1077, before Rome's war on Epirus; Gaul-Iberia at turn 22 and Macedon-Greeks at turn 44 in
   1385) brought no faction into a war: Gaul's alliance with Iberia only made Gaul's bloc (46,074) too strong for
   Rome to attack. Deterrence never stopped a Rome war in the traces.
3. The first divergence from format 8 is at turn 1-3 and is not a decision: `_seek_ally` draws from the state's RNG
   for every threatened AI, so every later roll differs (Rome's treasury at turn 3 is 1,114 against 1,186; in 1077
   the turn-5 Rome-Carthage trade of format 8 never happens, and Carthage declares war at turn 9). From there the
   seeds are different histories, which is why the deaths fall on different seeds in every run.
4. Rome's deaths over more seeds (seeds 1000 + 77 n): 12 seeds, format 6 1, format 8 1, format 10 2, format 10
   with `ai_alliances` 0 2 (each on a different seed: 1847 / 1847 / 1077, 1385 / 1154, 1770); 48 seeds, format 8
   7, format 10 10, `ai_alliances` 0 9; 96 seeds, format 8 18 (19 %), format 10 20 (21 %), median turn of death 46
   against 44.5. The six format-8 pin seeds were the lucky draw (18.8 % a seed gives 0 of 6 in 29 % of draws).
5. All factions, 96 seeds, format 8 -> 10: eliminations 217 -> 239 (2.26 -> 2.49 a seed, sd 1.05 / 1.25; about
   1.3 standard errors), Rome 18 -> 20, Carthage 14 -> 12, Macedon 29 -> 35, Epirus 79 -> 73, Greeks 5 -> 10,
   Syracuse 33 -> 34, Iberia 9 -> 21, Gauls 30 -> 34. 48 seeds without AI alliances: 120 against 121 with them, so
   the alliances are not what moves it either. Iberia's 9 -> 21 is the one row worth watching in a later pass.

No rule changed; the format-10 pins stand (`5af35d0f 16aa22f3 97e93bf2 81dc9f4d cc80b514 96159b8e`). `campaign_sim`
gained `--trace-faction=KEY` (that faction's wars, peace, trade, alliances, calls answered and sat out, cities
gained and lost, and a line a turn: regions, treasury, armies, strength, repute, each enemy's strength / bloc
strength, allies) and `--ai-alliances=0|1` (the creation setting); neither moves a hash.

## 42. The defending pike under musket fire (2026-10-27)

The owner (phone, West campaign, attacking Caribbean cities): "the standard city defenders position a pike out
front, who just gets annihilated every time the player places a line of musketeers right at the front of his
preparation zone."

**Probe** (`tests/defend_probe.gd`): a West campaign town on its own plan (as `town_balance.gd --town=west:<key>`),
the West sets' armies, the defenders the siege AI (Average), the attackers scripted like the owner: in the
deployment phase every musket-armed foot company (2 musketeers, 2 buccaneers) is placed in one line along the front
edge of the attackers' zone, fire at will, then Hold stance; the rest 40 m behind; nobody moves for 4 minutes, then
the attackers become the AI and assault. Per battle: the defenders' men down before the first melee contact by class
(pike, shock, line musket, skirmisher), how many street posts at the start lie within a line gun's range, the result.
Havana, Cartagena, Cumana x walls 0 / 1 / 2 x 8 seeds.

**Diagnosis.** Not the posts: the scenario's placement. `Scenarios.settlement` puts the solid units (pikes first:
`_gate_rank`) 18 m inside each street mouth facing out ("street-mouth holders", phase W). The AI only sets the street
posts (`_classify_defender` -> `_strongpoint`: line units `SP_LINE_PCT` 40 % / `SP_PAL_LINE_PCT` 80 % of the way to
the plaza) at its first army think, which on a city map runs at the battle's first tick: `_setup_deploy` lets the field
AI deploy (`city_on == 0`) but not the settlement AI, so through the whole deployment phase the defenders stand where
the scenario dropped them. The attackers' zone (`Scenarios.settlement`: from 40 m ahead of their front) reaches the
street mouths, so the player's line stood about 20 m from the pike. Traced (Cumana walls 1, seed 0): the first volleys
of four companies at 21 m left the pike 30 of 120 and routing 2 s into the battle, its post 153 m behind it. The
street posts themselves were also inside the guns' reach at walls 0 (7 of 7 units' posts within a line gun's range,
the pike's 102-116 m from the line; at walls 1-2 3 of 6, the pike's 171-188 m out of it). Nothing then moved a unit
out of the fire: the defenders' `_reserve` rule only looks at attackers inside the town (`V_URBAN`, within
`S_RESERVE_R` 140 m of the post); missile units shoot from the post, the rest go back to it. The field AI's
"shelled: get out of the arc" rule (`battle_ai.gd`, artillery only) never runs on a settlement map (`SiegeAI.think`
replaces `BattleAI.think`), and nothing in either AI reads musket hits (`u_hit_t`).

As built (`sim/siege_ai.gd` "defenders under musket fire", `sim/battle_sim.gd` `_setup_deploy`; West street defenders
only: `_street_ai` and `_street_row`; Rome's sieges and the walls, gate, tower, fort and citadel rules untouched):

- **Set out in the deployment** (`S_DEF_ZONE`): an AI town defence classifies its units in `_setup_deploy`
  (`SiegeAI.deploy_defenders`, the orders a player gives: posts, buildings, stances) and its street units are placed
  at their posts (open ground; not kept to the zone, which at walls 1-2 is the fort's box), as the field AI deploys.
  Only battles with a deployment phase (a human in the battle); AI against AI never has one.
- **Posts out of the zone's reach** (`S_DEF_ZONE`): a street post (`_strongpoint`, line and cover troops) is moved
  toward the plaza in `DF_ZONE_STEP` 5 % steps (at most `SP_PCT_MAX` 95 %) until it is farther than the attackers'
  longest foot / horse gun range + `DF_ZONE_PAD` 15 m from their deployment zone (`_df_zone_reach`, `_df_zone_d`);
  a skirmisher's cover candidates (`_sp_cover`) within that reach are skipped. The section 31 stand-off reasoning,
  mirrored: out of the reach of where the guns can stand.
- **Under fire** (`S_DEF_FIRE`, `_df_fire` from `_reserve`): a street unit (not in a building, not at cover spots,
  not fighting) hit by a missile within `DF_HIT_T` 15 s while enemy shooters stand in the field with it in range
  (seen, ready, with shots, off the walls, not on urban ground, not moving: `_df_shooters`): a musket line answers
  from the building nearest its post within `DF_OCC_R` 40 m (ORDER_OCCUPY; not one about to fall); a pike or shock
  unit with `DF_CHARGE_MEN` 50 % of its men charges the nearest of them within its run x their reload (at most
  `DF_RELOAD_MAX` 12 s) x `DF_CHARGE_PCT` 150 % (pikes 55 m, rodeleros 72 m, cutlass men 83 m) when no enemy horse or
  pike stands within `DF_GUARD_R` 45 m of it (`A_DCHARGE` 39, its post kept in u_ai_x / u_ai_y; back to the post at
  the run when its target breaks or goes, or after `DF_CHARGE_T` 45 s with no contact); else, when its post is in
  their reach, it falls back along its street (`_df_back`: points `DF_FB_STEP` 8 m apart toward the plaza, and 6 /
  12 m to either side, the first step with a point out of every shooter's range + `DF_PAD` 15 m or out of its sight,
  the most cover there by `_cover_score`; none: the plaza), which becomes its post. Shooters coming into the town are
  left to the reserve's own rule (they are attackers inside within 140 m).
- **Knobs** (`ai_profile.gd` ids 290-291): `S_DEF_FIRE` and `S_DEF_ZONE`, Easy 0 / Average 1 / Skilled 1. Easy keeps
  the old behaviour as a deliberate mistake (its defenders already had no street posts: `_street_ai` excludes Easy).
  No new hashed state: the charge's memory is the unit's mode and post (`u_ai`, `u_ai_x`, `u_ai_y`, `u_ai_t`);
  `stat_ai` grew one slot for the new mode (not hashed).

Measured (probe, 24 battles a walls level, per battle; before -> after):

| Walls | Attacker wins | Defenders down before contact | of them pikes / shock / musket / skirmish | Posts in a line gun's range | Attackers down before contact |
|---|---|---|---|---|---|
| 0 | 22 -> 10 of 24 | 207 -> 52 | 98 / 42 / 25 / 42 -> 0 / 20 / 23 / 8 | 6.7 of 7 -> 0 | 135 -> 61 |
| 1 | 20 -> 5 of 24 | 196 -> 44 | 90 / 26 / 31 / 48 -> 1 / 10 / 24 / 9 | 3.0 of 6 -> 0 | 135 -> 89 |
| 2 | 11 -> 8 of 24 | 160 -> 52 | 71 / 22 / 12 / 54 -> 1 / 10 / 23 / 17 | 3.0 of 6 -> 0 | 155 -> 95 |

Per town (attacker wins of 8, walls 0 / 1 / 2): Havana 8 / 8 / 2 -> 0 / 1 / 2, Cartagena 7 / 4 / 1 -> 5 / 0 / 0,
Cumana 7 / 8 / 8 -> 5 / 4 / 6. The posts now stand 162-200 m from the line. Traced with `--step=60` / `100` (the
line walks in a minute after the start and halts; Havana walls 0, one seed): at 60 m the line stood 121-144 m from the
posts and did not shoot; at 100 m it stood on the town's ground and the reserve's own rule went at it.

AI against AI (`tools/balance`, west_walls, 16 Spanish towns x 16 seeds, attacker wins %; only `S_DEF_FIRE` acts
there, no deployment phase): walls 0 / 1 / 2 49 / 37 / 28 -> 39 / 31 / 27 (pooled 38 -> 33; walls 0 beyond the
interval, in the attackers' disfavour); cells beyond the interval: New Orleans walls 0 62 -> 6, Portobelo walls 1
81 -> 50, Santiago de Cuba walls 2 88 -> 38, Port Royal walls 2 12 -> 50, St Augustine walls 2 19 -> 88. In AI
battles the attackers' stand-off band (`A_COVER`) and the defenders' street units at their scenario places trade fire
at the start; the defenders now fall back out of it or into a house. open_town (the scripted house defender): identical
in every cell (the rule plays for AI defenders only). Rome rows untouched.

Open: walls 0 AI against AI is now 39 % (section 31 had it at 52); if the owner wants it back near half, the lever is
`S_DEF_FIRE`'s fall back at walls 0 in AI-only battles, not the deployment rules.

## 43. Wars the AI can cover (2026-10-27)

Acting on section 41: the AI declared wars it could not cover (Rome on its trade partner Gaul with Roma empty, Gaul
taking it the next turn; Rome's three wars on partners in a row, then Gaul on a Rome fighting two). Four rules in
`CAI.diplomacy`, state format 10 only (`CDip.on`: formats 6-9 play as before, their pins unmoved), each behind a knob
of `campaign/cai_profile.gd` that is 0 (or neutral) at Easy, so Easy's random-ish wars and its unwise-war mistake
(which rolls before these rules and against its own candidates) are unchanged:

1. **The core covered** (`war_covered`, after the war roll succeeds; a refusal is counted `wars_uncovered` and the
   next candidate is tried): every region of ours whose settlement an army of the target, or of a faction already at
   war with us, reaches within WAR_COVER_TURNS turns (the static distance fields and the army's default march, as the
   threat by reach) holds WAR_COVER_PCT % of the strength reaching it: its garrison and the armies in it
   (`defence`) and our free armies that reach it this turn. Average 50 % / 1 turn, Skilled 60 % / 1 turn.
2. **A partner needs a better case**: a war on a trade partner (a treaty break, repute -30 with the unprovoked war)
   needs WAR_RATIO (or WAR_RATIO_BUSY) x WAR_PARTNER_PCT / 100: Average 105, Skilled 110; Skilled also never starts
   one while another war is on (WAR_PARTNER_SOLO).
3. **One war at a time unless winning** (WAR_ONE_AT_A_TIME, Average and Skilled): no new war while any current war
   is not winning: winning is a region taken from that enemy and none lost to it in the last 5 turns, or the enemy
   under PEACE_ACCEPT_PCT (100) % of our strength. MAX_WARS stays the hard cap.
4. **Peace when stretched** (STRETCH_PEACE_PCT 100, Average and Skilled): with two wars, or a region lost in the
   last 5 turns, the war won least (the most regions lost to that enemy in 5 turns, then the strongest) asks peace
   after PEACE_MIN_TURNS (not PEACE_ASK_TURNS) when we are below STRETCH_PEACE_PCT % of its strength; the other
   side answers by its own rule (`why("peace")`). Skilled's `_one_front` stays as it was. Extending `_one_front` to
   Average was measured and dropped: it keeps the war on the enemy pressed hardest, ties to the weakest, so it turned
   the European nations of the West on the natives (eliminations 31 -> 45 over 48 West seeds, Itza 6 -> 11, Miskito
   5 -> 10); the war-won-least ask did not.

The brief's numbers (cover 60 / 80 % with 1 / 2 turns, partner 130 / 150) cut too many wars: Average Rome battles
46.6 -> 32.9 a seed and the largest realm at 60 12.9 -> 10.7; Skilled battles 59 -> 34. The knobs above are where the
deaths fall and the fighting holds best (Rome, 96 seeds, Average): cover 40 % gives battles -15 %, Rome 16, Epirus 66;
50 % gives -18 %, Rome 11, Epirus 62; 60 % -20 %, Rome 13, Epirus 57. Partner 130 alone cost 7 battles a seed.

Measured (`campaign_sim --format=10`, 60 turns, seeds 1000 + 77 n; before = c38c823):

| Rome, Average, 96 seeds | before | after |
|---|---|---|
| eliminated: Rome | 20 | 11 |
| Carthage | 12 | 7 |
| Macedon | 35 | 34 |
| Epirus | 73 | 62 |
| Greeks | 10 | 7 |
| Syracuse | 34 | 24 |
| Iberia | 21 | 14 |
| Gauls | 34 | 25 |
| eliminations a seed | 2.49 | 1.92 |
| battles a seed | 46.6 | 38.2 (-18 %) |
| largest at 15 / 30 / 60 | 7.17 / 9.14 / 12.94 | 7.21 / 8.72 / 11.58 |
| first win (20 regions, 3 key cities) | 4 seeds (median turn 59) | 2 (57) |

The first 48 of those seeds: eliminations 121 -> 98 (Rome 10 -> 6, Epirus 36 -> 30, Macedon 19 -> 21), battles 46.0 ->
38.2, largest at 60 13.6 -> 11.5.

| West, Average, 48 seeds | before | after |
|---|---|---|
| eliminated: England / France / Dutch | 3 / 0 / 0 | 1 / 0 / 1 |
| Brethren | 17 | 15 |
| Itza | 6 | 7 |
| Miskito | 5 | 3 |
| eliminations a seed | 0.65 | 0.56 |
| battles a seed | 52.1 | 46.7 (-10 %) |
| largest at 15 / 30 / 60 | 9.77 / 12.44 / 14.81 | 9.83 / 12.31 / 13.96 |

Skilled (Rome, 96 seeds, every faction Skilled): eliminations 2.35 -> 2.01 a seed (Rome 7 -> 11, Macedon 70 -> 61,
Epirus 69 -> 59, Gauls 26 -> 16, Syracuse 16 -> 20), battles 59.2 -> 46.4 (-22 %), largest at 60 12.4 -> 10.8.
Skilled at the brief's 80 % over 2 turns: battles 34, largest at 60 9.1, Rome 13 deaths.

What it does and does not fix (traces, `--trace-faction`): Epirus's own over-reach deaths (Epirus declaring a war
and dying in it) fell 8 -> 2 of 48 seeds, Macedon's 14 -> 7 of 96. The rest of Epirus's deaths (28 of 30 after) are
wars made on it: the scenario war with Rome (Rome takes Ambracia by turn 11 and Tarentum by turn 17-22, 10 of the 30
deaths, and refuses peace: it is the stronger) and later wars on a one-region rump by the Greeks, Macedon and
Syracuse; Macedon's are mostly the Greeks' wars on it (13 -> 20 of 96, the Greeks no longer spending themselves
elsewhere). The cover rule protects the side that
declares, not its victim; Epirus needs the strategic fix of "Rome start budgets" (STATUS), not this. The format 6 and
8 pins are unmoved; the format 10 pins, `ROME_20` and the AI goldens moved (STATUS "Verification pins").

## 44. The play library (plan, 2026-10-27; agreed with the owner)

The owner wants the battle AI to try historical tactics, and asked whether a
learned model could drive armies. Two layers, in this order: **scripted
plays** first (this section), a **learned chooser** of plays later, only if
the plays prove out (section 44.4). A play is a named tactic the battle AI
runs on top of its existing rules: a trigger (the side's composition, the
ground, the enemy's shape), a faction weighting, a few orders and posts, and
a name in the battle's telemetry so the counters and the chronicle can say
"the Spanish formed a tercio". Plays are explainable and tunable per level;
learning the tactics themselves from scratch is where the cost and the risk
were, and the library removes that.

**Framework (`sim/plays.gd`, static like `BattleAI`, called from
`BattleAI._army_think` after the plan is read; nothing in the campaign).**

- A side's plays are a bit mask `ai_plays` in the scenario (`[side 0, side
  1]`, as `ai_skill`; default every bit; hashed and in snapshots like
  `ai_skill`). Bit 0 the tercio, bit 1 the countermarch; later plays take the
  next bits. The campaign fills it from the faction's row (`west.gd`
  `PLAYS`: Spain tercio and countermarch, England, France and the Dutch the
  countermarch, the natives and the Brethren none yet; Rome every bit, which
  is a no-op: no Rome row has a gun and no play triggers without one). Custom
  battles and scenario keys get every bit.
- `AIProfile.PLAYS_ON` (id 300): 0 Easy, 1 Average, 1 Skilled. A play reads
  its own knobs (ids 301-309 the tercio, 310-319 the countermarch); the AI
  never branches on the level.
- Per-side memory through `_sd` / `_sdset` (the play running, its start
  tick), per-unit through `_mem` (the unit's part in it); all hashed as the
  AI memory already is. A play is chosen once in the deployment or at the
  first think with a trigger and dropped when its trigger is gone for
  `PLAY_DROP_T` 30 s; its units go back to the ordinary rules.
- Telemetry: one counter per play started (`_count`), the battle result's
  AI counters as the other competencies; a line in the battle's chronicle
  where the view has one (the builder checks; no new HUD element).
- Rome byte-identity: every play's trigger needs a gun foot unit; the Rome
  goldens, pins and `ROME_20` do not move. The West pins may move only by the
  countermarch (the campaign's AI battles are auto-resolved, so they should
  not; if they do, the cause is reported before the patch).

### 44.1 The tercio (plan)

The Spanish square: a deep pike block with the shot in "sleeves" at its
corners, the muskets retiring under the pikes when horse comes on.

- **Trigger.** A field battle (no town plan, not a sea battle), the side
  has a pike unit (`cls` pike) and a gun foot unit (`BattleAI.line_gun`),
  and the enemy fields a rider unit or more melee foot than the side has.
- **Formation.** Each pike unit stands as a block: files `max(TERCIO_FILES,
  isqrt(men))` (knob id 302, default 8; 120 pikes stand 10 by 12). Up to two
  gun units per block are its sleeves, posted at its front corners one unit
  width out, their front rank level with the block's; gun units beyond two a
  block form the ordinary line between the blocks. The line, reserves and
  the Skilled mirror are otherwise as they are: the play post-processes the
  slots `_issue_line` made.
- **Under horse.** A rider unit closing on a sleeve (an attack order on it,
  or riders within `TERCIO_HORSE_R` 80 m, id 303, moving toward it) sends the
  sleeves to the block's rear corners (10 m behind the block's rear rank,
  flat line of fire past friends keeps them shooting); the block turns to
  face a charger coming from a flank within 60 m. With no closing riders
  within the reach for 10 s the sleeves return to the front corners. Pikes
  already stop horse; the play's worth is that the shot is never caught in
  the open.
- **Interplay.** `_gun_covered` (horse keep out of a free musket line's
  reach) and `_counter_target` read the sleeves as any gun line; the
  battery guard still takes a pike first, the play never takes the guard's
  pike. Knob `TERCIO` id 301: 0 Easy, 1 Average, 1 Skilled.
- **Measure.** A new AI-against-AI field pair `play_field` (`sim/scenarios.gd`
  and `tests/asym_probe.gd`: the Spanish with 2 pike, 4 musket companies and 2
  horse against an English army of 6 musket companies, 1 pike, 2 horse and a
  falconet battery; 48 seeds) run with the Spanish bit on and off: the
  Spanish wins with the tercio up, and `asym_field` (natives, no horse, more
  melee foot: the play triggers) not below 40 of 48 Spanish wins. Reported as
  a before / after table; the balance harness plans unmoved.

### 44.1 The tercio (as built, 2026-10-27)

**Framework.** `sim/plays.gd` (static `Plays`, self-contained: it mirrors the
few BattleAI helpers it needs, as BattleAI mirrors the sim's constants, so no
preload cycle). `BattleAI._army_think` calls `Plays.army_think` right after the
plan is read (a play starts, or is dropped); `_issue_line` calls
`Plays.post_line` after the reassignment by lateral and before the orders (a
slot may carry a third value, the unit's width); `_unit_think` calls
`Plays.unit_think` before the class rules (true: the play gave the orders).
Scenario key `ai_plays` `[side 0, side 1]`, `Plays.ALL` = -1 (every bit) when
absent; bit 0 `P_TERCIO`, bit 1 `P_COUNTERMARCH` (defined, unused here).
`BattleSim.ai_plays` is parsed next to `ai_style`, hashed only when a side is
not -1 and snapshotted as a script variable. Memory: a tail of
`BattleSim.ai_mem` after the Skilled memory (`PU_K` 4 ints a unit: role
0 none / 1 block / 2 left sleeve / 3 right sleeve, its block + 1, state, the
tick riders were last seen closing; `PS_K` 4 a side: the tercio's state 0 / 1
running / 2 dropped, its start tick, the tick its trigger last held). The tail
exists only when an AI side has `PLAYS_ON`, a play bit and a gun foot unit
(`Plays.wants_mem` at setup); `MU_K` / `SD_K` are unchanged, so Skilled memory
is laid out and hashed as before, and `state_hash()` hashes `ai_mem` at the
default profile too when it is not empty (only the plays' tail makes it so).
Counter `AP.C_PLAY_TERCIO` ("play_tercio", once a battle per side). The battle
view has no chronicle or notice line for AI events: no HUD element added.
Campaign: `west.gd` `PLAYS` (new_spain and tierra_firme 3, england, france,
dutch 2, brethren, itza, miskito 0), `CData.PLAYS` / `CData.plays_of(f)`
(a pack without the table, Rome: -1; a West faction not listed and the
independents: 0); `cbattle._ai_profiles` returns the plays too and both
scenario builders put `ai_plays` in only when a side is not -1 (Rome
scenarios unchanged; the table is data, not state: no `CState.VERSION` bump).

**The tercio as built.** Trigger (`tercio_trigger`, each army think): no
settlement map (`city_on` 0, no `tp`), a ready pike unit not guarding a
battery and a ready gun foot unit (`m_gun`, not skirmishing, not horse or a
battery), and the enemy shows a ready rider unit (one hidden from the side
does not count). **Riders only**: the plan's second clause (more enemy melee
foot than the side's) was dropped after the measure below (the owner's
choice, option c). Started at the first army think the trigger holds (the
deployment's, in a field battle), dropped for good when it has been gone
`PLAY_DROP_T` (no enemy rider unit left ready and seen for 30 s). Layout
(`post_line`, each `_issue_line` while it runs): the first line's pikes (not
the would-be guard: `_pick_guard` was split into the pure `_guard_choice`,
used here at the deployment) are blocks of `max(TERCIO_FILES, isqrt(men))`
files; sleeves go block by block, the outer side first (a block in the left
half: left), then the inner side, so with fewer than two guns a block every
block gets an outer sleeve first; the guns beyond take the gaps between blocks
evenly (one block: half each side outside the sleeves); the guns are given
their places in their left-to-right order; the core is centred where the old
core was, the line's other foot outward of it in their order, and the wings
(cavalry, bolt throwers at the line's level) shifted by the change of the
line's ends. A sleeve's front post: beside its block, lateral `bw / 2 +
LINE_GAP + sw / 2`, front rank level. Under horse (`unit_think`, each unit
think): a rider closing on a sleeve (an attack order on it within 2 x
`TERCIO_HORSE_R`, or within `TERCIO_HORSE_R` with its move end or attack
target nearer the sleeve than it is) sends it running to the rear corner
(lateral `max(bw / 2, sw / 2 + LINE_GAP / 2)`, the block's depth +
`TERCIO_REAR` behind its front, facing as the block) with fire at will on;
`TERCIO_CLEAR_T` with none closing and it is sent back to the front post
(then the ordinary rules: in the engagement the musket line closes as
before). A block with a rider closing within `TERCIO_TURN_R` more than
`TERCIO_FLANK` off its front turns in place about its centre to face it, and
holds while riders keep closing, `TERCIO_CLEAR_T` after. A sheltering sleeve
or a turned block is left out of `_issue_line`'s orders. A sleeve or block in
a melee, mauled (A_RETIRE) or guarding is left to the ordinary rules.

Knobs (`ai_profile.gd`; ids 292-299 are a gap, `KNOB_GAPS`, read as 0):
`PLAYS_ON` 300 (Easy 0 / Average 1 / Skilled 1), `TERCIO` 301 (0 / 1 / 1),
`TERCIO_FILES` 302 (Easy 8, never used / Average 14 / Skilled 14: 120 pikes
stand 14 x 9; the plan's 8, 10 x 12, measured worse), `TERCIO_HORSE_R` 303
(80 m all). Constants
(`plays.gd`): `PLAY_DROP_T` 300 ticks (30 s), `TERCIO_CLEAR_T` 100 (10 s),
`TERCIO_TURN_R` 60 m, `TERCIO_FLANK` 128 (45 degrees), `TERCIO_REAR` 10 m.

**Measured** (`tests/asym_probe.gd`, 48 seeds from 5000, both sides Average;
new `--plays=MASK` sets the Spanish side's bits; `play_field` new in
`sim/scenarios.gd`: the Spanish 2 pike, 4 musket companies, 2 lancers, 4,680,
against 6 English musket companies of 80, 1 pike, 2 pistoleers of 50 and a
falconet battery, 4,840, 600 x 400 m open; the English with `ai_plays` 2, as
England's campaign row). Spanish wins of 48, "off" the bit off (the battle as
before the play):

| build | play_field off | play_field on | asym_field off | asym_field on |
|---|---|---|---|---|
| as built: riders only, 14 files | 31 | 43 | 39 | 39 (every battle as off) |
| plan trigger, 8 files (10 x 12) | 31 | 32 | 39 | 27 |
| plan trigger, 12 files | | 40 | | 33 |
| plan trigger, 14 files | | 43 | | 32 |
| plan trigger, 16 files | | 33 | | 38 |
| plan trigger, 20 files (the old frontage) | | | | 39 |

Why: at the plan's 8 files the play gained nothing against the English and
cost 12 battles against the natives (`asym_field`: no horse, more melee
foot, so the plan's second clause started it). At 20 files `asym_field` was
exactly the off result: the loss was the block's depth alone (a narrow deep
block gives up frontage to the warriors' swarm, and with no riders the
sleeves never shelter). Against the English the gain peaked at 12-14 files
(48 seeds: about +-3 wins of noise; the curve is not smooth). Riders only
and 14 files keeps the gain where there is horse and leaves the natives'
battle untouched (the play never starts there).

**Open.** The sleeves keep their corners only until the lines engage (then
the ordinary musket rules take them forward); no play line in the battle view
(it has no notice line for AI events); TERCIO_FILES' curve is noisy and was
swept only on these two pairs.

### 44.2 The countermarch (plan)

The Dutch drill: the ranks fire in turn so the line keeps up a rolling fire
instead of one volley a reload. In the sim's model every man reloads in
parallel, so the countermarch is a **unit ability** whose worth is how the
fire lands, not how many shots are fired.

- **Sim (`sim/battle_sim.gd`, West gun foot rows only: `m_gun` 1, foot, a
  crew of 1).** Ability `UT.AB_ROLL` ("Countermarch": Auto / Hold / Use now,
  through `ORDER_ABILITY` as the others, hashed in the ability table). With
  rolling fire on, the unit's ranks (slot `s / u_files`) fire one rank every
  `m_reload / ranks` ticks in turn (`u_cmr` the rank pointer, hashed only
  with `gun_on`); a man fires only with a charge and loaded as now; shots
  and ammunition a reload are the same as a volley's. A rank's volley
  frightens its target as a volley does (`m_fear` into `u_fright`, once per
  rank volley) at `CM_FEAR_PCT` 50 % of `m_fear`, so a rolling fire keeps the
  target's fright topped up through `FRIGHT_DECAY` where a volley spikes and
  fades. The last volley: an enemy melee unit closing within `CM_CLOSE` 40 m
  fires every loaded man at once, and the rolling fire resumes after. Fire
  at will's volley range and the held-volley rule apply to each rank's
  volley. Per-man fire (`_pm_on`: in buildings, on walls, in cover) is
  unchanged: the ability does nothing there. No retiring fire at the walk in
  this step (open: a line that gives ground firing).
- **Auto.** Rolling fire while the fire target is beyond `CM_CLOSE` and the
  unit is not in a melee; the opening volley of a loaded line that has
  waited a full reload is a full volley (the drill starts after it).
- **AI.** `CM_AUTO` (id 311: 0 Easy, 1 Average, 1 Skilled; bit 1 of
  `ai_plays`): every AI gun foot line on Auto; a street line in the open
  rolls, a company in a building does not. Counted once per battle per
  side.
- **Player.** The ability chip on gun foot companies (Auto / Hold / Use now
  as the pistols and grenades: `game/ability_chip.gd`, the Keys "Chips"
  section, the unit book's page line "Countermarch: rolling fire by ranks"),
  the custom battle as any ability.
- **Measure.** `asym_field`, `play_field` (44.1), `open_town` and
  `west_walls` with the bit on and off, before / after tables; the expected
  move is small and toward the shooters. `tests/defend_probe.gd` re-run: the
  owner's musket line is a player unit on Auto, so its numbers move; reported.

### 44.2 The countermarch (as built, 2026-10-27)

The sim rule in full: docs/design/battle_sim.md "The countermarch (as built)". Code: `sim/battle_sim.gd`
(`_setup_cm`, `_cm_rolls`, `_cm_unit`; hooks in `_gun_unit`, `_missile_hit`, `state_hash`), `sim/unit_types.gd`
(`AB_ROLL` 4, `AB_N` 5, `abilities()`), `sim/ai_profile.gd` (`CM_AUTO`, `C_CM`), the view (`game/hud.gd`,
`game/battle.gd`, `game/ui_icons.gd` glyph `countermarch`, `game/controls.gd` Keys "Chips", `game/unit_entry.gd`),
test `tests/roles_sim_test.gd --only=countermarch`.

- **Who.** `UT.AB_ROLL` on West rows with `m_gun`, missile class, foot, crew <= 1 and **not a skirmish row**
  (`skirm` 0): musketeers (and veterans), marines, colonial militia. Buccaneers, coureurs and maroons have none
  (loose-order skirmishers; the asymmetry principle: no native or pirate line that trades volleys); riders, guns
  and every Rome row none.
- **Sim.** A reload clock per unit (`u_cmc`, counts as `u_fire_acc`: half speed on the move) and a per-man stamp
  (`s_cms`) make "a man fires only loaded" exact: each man once a reload, ranks shuffled by casualties or not. Full
  volley of every loaded man: the opening (the line's last shot two reloads ago: it has stood loaded a full reload)
  and, on Auto, the last volley (fire target within `CM_CLOSE` or the unit in a melee; any target, which is the Auto
  rule "rolling while the target is beyond CM_CLOSE"); then the drill restarts from the front rank a reload later.
  Else one rank (slot / files) every `ceil(m_reload / ranks)` of the clock, front to rear. Rank volleys frighten at
  `CM_FEAR_PCT`. Hold: the volleys as before. Use now: rolling at any range and in a melee (no last volley); it
  takes no target. Per-man fire (`_pm_on`) untouched, so a company in a building, on a wall or a cover row in the
  Cover / Hold-street stance does not roll; a street line in the open does.
- **State.** `cm_on` (static: a unit with the ability); `u_cmc`, `u_cmr`, `u_cmt`, `u_cml`, `u_cmv`, `s_cms` sized
  and hashed only with it (Rome: empty, unhashed). Snapshots carry them (script variables).
- **AI.** No orders: the sim reads `CM_AUTO` for an AI side (`_cm_rolls`, as `R_SK_DRIFT` is read in `_skd_ok`), so
  an AI line is on Auto unless the knob is 0 (then it volleys as on Hold); neither AI ever sets Hold on it. The
  merge with 44.1 (2026-10-27) added the side's `ai_plays` bit 1 (`Plays.P_COUNTERMARCH`) to the same test: the
  campaign's PLAYS table gives it to Spain, England, France and the Dutch, not to the natives or the Brethren. Counted once a battle a side (`C_CM`, "countermarch" in
  `COUNTER_NAMES`) at the side's first rank volley.
- **Player.** The ability chip right after Fire, Auto / Hold / Use now (Use now set at once, no pick), the Keys
  "Chips" line, the unit page's "Countermarch: rolling fire by ranks". The custom battle needed nothing.

| Knob / constant | Value |
|---|---|
| `CM_AUTO` (`ai_profile.gd` id 311) | Easy 0, Average 1, Skilled 1 |
| `CM_FEAR_PCT` (`battle_sim.gd`) | 50 % of `m_fear` per rank volley |
| `CM_CLOSE` | 40 m |
| rank interval | `ceil(m_reload / ranks)`: musketeers 120 ticks / 4 ranks = 3 s |
| ids 292-310 | no knob yet (`KNOB_GAPS`, filled 0; the tercio's 300-309 come with 44.1) |

Set piece (100 musketeers, 25 x 4, at a pike block 70 m off, 90 s): Auto an opening of 100 shots, then 25 a rank
every 30 ticks (pointer 0, 1, 2, 3, 0 ...), 750 shots against 800 by volleys over the same ticks (a cycle of four
ranks = one volley's 100; the difference is the last cycle's ranks still to fire), fright jumps 60 (opening) / 30
(each rank); rodeleros charging home take the last volley at 34 m; Easy AI 0 rank volleys, Average counted once.

Measured, before (HEAD `e5dbd18`, sim hash `ee70ed3705`) -> after (`40eb64271d`):

| Probe | Before | After |
|---|---|---|
| asym_field, Spanish wins of 48 | 39 (1 draw) | 42 (0 draws) |
| open_town attacker wins % (8 seeds): Cartagena / Havana / Santo Domingo | 88 / 12 / 100 | 88 / 0 / 100 |
| west_walls pooled attacker wins %, walls 0 / 1 / 2 (16 towns x 16) | 39 / 31 / 27 | 52* / 37 / 29 |
| west_walls men lost a battle, walls 0: attackers / defenders | 462 / 433 | 439 / 432 |
| defend_probe attacker wins of 24, walls 0 / 1 / 2 | 10 / 5 / 8 | 10 / 5 / 9 |
| defend_probe defenders down before contact, walls 0 / 1 / 2 | 52 / 44 / 52 | 52 / 44 / 52 |

west_walls cells beyond the interval: Santo Domingo walls 0 6 -> 44, Santiago de Cuba walls 0 50 -> 94, Cumana walls
2 69 -> 94, St Augustine walls 2 88 -> 56. defend_probe per town (wins of 8, walls 0 / 1 / 2): Havana 0 / 1 / 2 ->
0 / 1 / 2, Cartagena 5 / 0 / 0 -> 5 / 1 / 0, Cumana 5 / 4 / 6 -> 5 / 3 / 7; nothing before contact moved (the line
stands out of the posts' reach since section 42, so it does not fire before the assault).

**Diagnosis of west_walls walls 0 (+12, beyond the interval).** Not the fright: with `CM_FEAR_PCT` 100 walls 0 is 51 %.
With the defenders never rolling (diagnostic only) it is 55 %: the gain is the attackers' field lines, which roll,
against defenders who mostly fire per man from houses (no change) and whose pikes and shock charge the shooters
(`S_DEF_FIRE`) into a fire with no reload gap and a last volley; the attackers lose 23 fewer men a battle, the
defenders as many as before. That is the drill doing what it is for, toward the shooters. No fix was kept: the move
puts AI-against-AI walls 0 back near section 31's 52 % (section 42 left 39 % as an open item). Walls 1-2 within the
interval.

Open: retiring fire at the walk (a line that gives ground firing); a Use now that fires the last volley on demand
instead; if walls 0 should stay near 40 % the lever is the defenders' charge distance against a rolling line
(`DF_CHARGE_PCT`), not the drill; the icon gallery (`tests/icon_gallery.gd`) is not regenerated.

### 44.3 Later plays (not yet)

The pirate boarding rush at sea, the caracole as a play (the ability
exists). Each after the first two prove out in the harness. (The native
ambush from cover with a feigned retreat into it: built, 44.5. The Swedish
salvo, three ranks firing as one, then the charge: built, 44.6, and measured
worse than no play on both pairs; open there.)

Note 2026-11-05: the plays are battle-AI behaviours (`sim/plays.gd`), not scenario keys: nothing "planned as a custom setup" was missing. The three
measure fields that exist, `play_field` (the tercio), `salvo_field` and `ambush_field`, were reachable only from `tests/asym_probe.gd`; they are now
listed in `Scenarios.IDS` with titles ("Plays: ...") in the Tests and benchmarks menu, and `tests/custom_battle_test.gd _check_play_scenarios` loads each,
runs 60 s of AI against AI and checks that units move and both sides survive. The pirate boarding rush at sea and the caracole as a play are still not
built: they need sim code (a sea AI order for the boarding run in `sim/sea_sim.gd`'s AI, or a land play on the countermarch's `AB_ROLL`), hashed state
and a measure, so they are left as written above.

### 44.4 The learned chooser (not yet)

Once plays exist, a tiny model has a sensible job: which play, when, from a
feature vector (composition shares, ground, enemy shape, the odds) to a play
id; an int8 multi-layer perceptron evaluated in integer maths in the sim,
trained from self-play on the balance harness, with the rules of this
section as the fallback when it picks nothing. Deterministic and small; its
cost is explainability, which the plays' names in the telemetry keep.

### 44.5 The native ambush (as built, 2026-10-29)

The ambush from cover with a feigned retreat into it: bit 2 of `ai_plays`
(`Plays.P_AMBUSH`), the Itza's and the Miskito's row in `west.gd` `PLAYS` (4;
the others unchanged). Code: `sim/plays.gd` (the ambush section), hooks in
`sim/battle_ai.gd` (`_army_think` passes the plan to `Plays.army_think`;
`_issue_line` leaves the play's units out of its orders, `Plays.amb_slots`;
`_unit_think` reaches it through `Plays.unit_think`), knobs and counters in
`sim/ai_profile.gd`, scenario `ambush_field` in `sim/scenarios.gd`, probe
flags `--plays1=` and `--trace-amb` in `tests/asym_probe.gd`, test `determinism_test.gd
--only=plays` (`_check_ambush`).

- **Trigger** (`ambush_trigger`, each army think): no settlement, no town
  plan, woods (`veg_on`) and line of sight (`vis_on`) on the map; the side
  has a ready **West** foot row with the cover trait (Rome's javelinmen and
  slingers have the trait too, so `ty >= UT.ROME_N`: no Rome battle can lay
  it, and `Plays.wants_mem` gives the plays' memory to a side with the bit,
  the knob and such a row); the enemy has a ready line foot, pike, gun foot
  or rider unit. It starts at the first army think where the trigger holds
  and **a wood lies between the lines on the side's half** (`_amb_woods`:
  along lines parallel to the plan's facing, lateral 0, -40, 40 ... 120 m
  from the side's centre in that order, the last wooded sample every 8 m
  from the centre up to `AMB_REACH` 240 m ahead and no further than halfway
  to the enemy's centre: the woods' front toward the enemy, on the first
  line that has one). Never with the tercio running (the two take turns:
  neither starts while the other runs).
- **Lie in wait.** Every ready foot unit of the side (foot, pikes, missile
  foot; not the general, wagons, characters, a retiring or guarding unit),
  in its lateral order, is laid side by side `LINE_GAP` apart, centred
  `AMB_HIDE_IN` 8 m behind the woods' front, each post moved to the nearest
  spot wooded at its anchor and half its depth behind (8-32 m back, else
  10-40 m toward the centre; `_amb_spot`); it runs there when over
  `AMB_RUN_R` 30 m away, holds its fire, skirmish off (no fall-back). The
  bait (`AMBUSH_BAIT` units: skirmish rows first, then the fewest men)
  stands `AMB_BAIT_AHEAD` 30 m out in front of the woods' front, in the
  open, fire at will on.
- **The bait falls back** when an enemy unit the side sees comes within
  `AMBUSH_PULL_R` (centroids) of it: to its own post in the hidden line at
  the walk (the run with an enemy within `AMBUSH_SPRING_R`); home, it hides
  as the others. One that is lost while lying in wait is replaced; one back
  home is not (the line waits for the spring).
- **Spring** (army think): an enemy **foot** unit within `AMBUSH_SPRING_R`
  (box to box) of a hidden unit standing at its post (within 30 m of it), a
  hidden unit at its post in contact or fighting, or an enemy foot unit
  `AMB_PASSED` 20 m past the woods' front (along the facing the ambush was
  laid with). Riders do not spring it (a lancer company scouting ahead blew
  every ambush in `ambush_field` before this rule; one that finds a hidden
  unit fights it alone: a hidden unit attacked springs on its own). Every
  hidden unit and the bait attack at once (`_amb_go`): the nearest enemy
  the side sees (else the nearest), a charge for melee foot; missile foot
  fire at will and become the woods' skirmishers (below). The sim's ambush
  strike (`u_amb`: hidden 5 s, then seen) does the rest. The side's and the
  enemy's men are noted.
- **Missile foot after the spring** (2026-10-29, the `asym_woods2` fix):
  a sprung bow, sling, dart or gun band takes the part `R_SKIRM`
  (`_amb_skirm`): skirmish on (the sim's loose order, fall-back and woods
  drift), fire at will, no attack order (it never closes on a target), no
  melt and no spring again. With an enemy it sees within `AMBUSH_PULL_R` it
  stays where its fall-back took it; with none it goes back to its post, and
  one at its post (within `AMB_RUN_R`) when a new cycle begins hides in the
  line again (`R_HIDE`). It does not count as a hider: a side whose melee
  foot are all gone drops the play. Caught in a melee, the ordinary rules.
- **Fight, melt.** A sprung melee unit is the ordinary rules' (`u_ai` A_ATTACK)
  until it has fought `AMBUSH_FIGHT_T` since it sprang; then, out of a melee
  and **not winning**, it melts: runs back to its post, fire held, hides.
  Winning: a unit that has lost no man since it sprang while enemy foot is
  within `AMBUSH_PULL_R` of it; else the enemy lost `AMB_WIN_PCT` 50 % of
  the side's losses since the spring or more and the unit lost under
  `AMB_LOSS_PCT` 33 % of its men. Home, a melted unit springs again on its
  own with enemy foot within `AMBUSH_SPRING_R`, or after `AMBUSH_FIGHT_T`
  hidden with enemy foot within `AMBUSH_PULL_R` (it strikes again while the
  others fight near by). With every unit home and hiding, a new cycle: a new
  bait goes out, lying in wait again.
- **Drop** (for good; the units back to the ordinary rules, A_ATTACK): the
  trigger gone `PLAY_DROP_T` 30 s, no foot left to hide (at once), or a
  cycle with no spring for `AMB_WAIT_T` 3 min (nobody came: the ordinary
  rules, as before the play).
- **Skilled** (`AMBUSH_FLANK`): a second wood on the enemy's flank
  (`_amb_woods` flank: lateral 120, 160, 200 m on the side away from the
  main wood's line, at least 100 m from it) takes the half of the hidden
  units on its side (`R_FLANK`); the spring is the same for both.
- **Memory** (the plays' tail of `ai_mem`, hashed and snapshotted as
  before; its layout grew: `PU_K` 4 -> 6, `PS_K` 4 -> 14, so every battle
  with the plays' memory hashes differently, none pinned): per unit the
  part (`R_HIDE` 4, `R_BAIT` 5, `R_FLANK` 6, `R_SKIRM` 7; the tercio's are 1-3), the men
  when it sprang, the state (`AS_HIDE`, `AS_FIGHT`, `AS_MELT`), the tick it
  sprang / got home, its post; per side the ambush's state, phase
  (`AP_WAIT`, `AP_PULL`, `AP_SPRUNG`), the cycle's start, the trigger's last
  tick, the woods' front point and facing, the men of both sides at the
  spring. Integers, index order, no RNG.
- **Counters** (`stat_aic`, diagnostics): `play_ambush` (laid, once a battle
  a side), `amb_spring` (the line sprung, or one unit again), `amb_melt`.

| Knob (`ai_profile.gd`) | Easy | Average | Skilled |
|---|---|---|---|
| `AMBUSH` 320 | 0 | 1 | 1 |
| `AMBUSH_BAIT` 321 | 1 | 1 | 1 |
| `AMBUSH_PULL_R` 322 | 120 m | 120 m | 120 m |
| `AMBUSH_SPRING_R` 323 | 40 m | 40 m | 40 m |
| `AMBUSH_FIGHT_T` 324 | 200 (20 s) | 200 | 200 |
| `AMBUSH_FLANK` 325 | 0 | 0 | 1 |

Ids 312-319 and 326-329 are gaps (`KNOB_GAPS`, read 0). Constants
(`plays.gd`): `AMB_REACH` 240 m, `AMB_STEP` 8 m, `AMB_HIDE_IN` 8 m,
`AMB_BAIT_AHEAD` 30 m, `AMB_PASSED` 20 m, `AMB_RUN_R` 30 m, `AMB_HOME_R`
8 m, `AMB_WAIT_T` 1800 (3 min), `AMB_WIN_PCT` 50, `AMB_LOSS_PCT` 33.

**Measured** (`tests/asym_probe.gd`, 48 seeds from 5000, both sides Average,
`--plays1=0` off / `-1` on; "lost" the natives' men lost a battle, "Spanish
lost" theirs, strikes the sim's ambush strikes, either side; new
`ambush_field`: the Spanish column, lancers 60, 4 musket companies of 100,
a pike block of 120, up a lane between two woods, x 90-210 and 390-510 m,
y 210-390 m, at 4 warrior bands of 100 and 2 bow bands of 80 beyond them,
600 x 600 m):

| Probe | Spanish / natives / draws | natives lost | Spanish lost | length s | reveals | strikes | springs / melts a battle |
|---|---|---|---|---|---|---|---|
| asym_woods off | 0 / 47 / 1 | 258 | 263 | 430 | 28.4 | 12.5 | |
| asym_woods on | 0 / 48 / 0 | 168 | 281 | 320 | 26.8 | 10.0 | 2.1 / 1.8 |
| asym_woods on, missile foot fix | 0 / 47 / 1 | 110 | 249 | 239 | 19.8 | 7.7 | 1.6 / 0.8 |
| asym_woods2 off | 2 / 44 / 2 | 280 | 264 | 492 | 32.4 | 15.9 | |
| asym_woods2 on | 13 / 35 / 0 | 395 | 311 | 522 | 37.0 | 11.2 | 9.7 / 10.6 |
| asym_woods2 on, missile foot fix | 3 / 44 / 1 | 289 | 289 | 430 | 32.6 | 9.9 | 2.5 / 1.6 |
| asym_field off = on | 42 / 6 / 0 | 471 | | 319 | 0 | 0 | never laid (no woods): every battle identical |
| ambush_field off | 42 / 6 / 0 | 277 | 189 | 301 | 2.3 | 0.06 | |
| ambush_field on | 35 / 13 / 0 | 314 | 228 | 387 | 14.5 | 5.4 | 10.0 / 10.2 |
| ambush_field on, missile foot fix | 29 / 16 / 3 | 301 | 245 | 401 | 13.9 | 4.3 | 6.4 / 6.2 |

Skilled natives in `ambush_field` (12 seeds, the Spanish Average): 0 of 12
on and off; the flank wood is taken in all 12; in most of them the column
halts south of the woods and the play is dropped by `AMB_WAIT_T`.

The builds measured (natives' wins of 48, the play on):

| Build | asym_woods | asym_woods2 | ambush_field |
|---|---|---|---|
| first: posts at the walk, the front up to 60 m short of the enemy, melt anywhere (a melee too) | 17 (13 draws) | | 2 |
| front halfway, run to posts, melt only out of a melee | 43 | | 9 |
| foot only spring, only units at their posts | 39 | | 17 |
| `AMB_WIN_PCT` 100 -> 50; the bait home stays hidden | 46 | 8 | 20 |
| far melee units stay hidden at the spring (not kept: draws) | 42 (6 draws) | | 19 (3 draws) |
| unfought units never melt; melted units strike again after 20 s | 47 | 35 | 6 |
| ... again only with enemy foot within 120 m | 47 | 35 | 7 |
| ... unfought units melt when not winning (as before) | 47 | 12 | 14 |
| **as built**: unfought units melt only with no enemy foot within 120 m | **48** | **35** | **13** |
| riders spring it (a halted gun rider shooting a hidden unit, or riders 5 s within 40 m of a hidden post), lying in wait only | 48 | 35 | 13 (every battle as built: it never fired first) |
| ... and a hiding unit after the spring too (not kept) | 48 | 34 | 15 |
| ... and against riders a line foot bait, no bait when the woods face the enemy's advance (not kept) | 47 (1 Spanish) | 27 (5 draws) | 6 |

Reading. In the woods band (`asym_woods`) the play does what it is for: the
natives win as before with 35 % fewer losses, the Spanish lose more, the
battles are 25 % shorter. In `ambush_field` the natives' wins double (6 ->
13) and the Spanish keep 35 of 48 (the floor was 12); the natives lose more
men a battle (277 -> 314) because they now fight it out instead of breaking
on the open lane, and the Spanish lose a fifth more. `asym_woods2` (the
mounted arquebusiers and the slingers) was a regression: 44 -> 35 wins (fixed below: 44). Its
counts: springs and melts near 10 a battle (2 in `asym_woods`), reveals up
32 -> 37, strikes down 16 -> 11: the line springs, fights piecemeal, melts
and springs again, and the ambush strikes fewer than the ordinary rules'
own woods fighting did. Both fixes tried within the plan moved it 8 -> 35 at
the cost of `ambush_field`; the as-built rule keeps both gains it could. A
second round (the coordinator's, target 42 of 48 with `ambush_field` at 10 or
better) tested the riders as the cause: riders standing near a hidden post
or shooting a hidden unit spring it, and against riders a line foot bait or
none. The riders' spring changed nothing while lying in wait (not one battle
differed) and within the noise after the spring (35 -> 34, `ambush_field` 13
-> 15); the bait change cost every probe (27, 6, 47). Neither reached the
target, so the build is as before: the riders are not what costs
`asym_woods2`. The Spanish
line's countermarch was not what beat it: in `asym_woods2` the Spanish lose
more men with the play on (264 -> 311).

**The `asym_woods2` fix (2026-10-29, third round).** A per-unit trace in
the probe (`--trace-amb`: every 10 s each native unit's part, state, metres
from its post, hidden flag, target and losses, each Spanish unit's place;
at the end a table per type: men lost by the part's state, kills, springs,
melts, and the Spanish kills by the killed men's type) found it was not the
slingers and darts as such but every missile band in the line. The
natives' extra losses (280 off -> 395 on a battle) fell on the sprung
missile foot: bowmen 7 -> 68, canoe raiders 19 -> 40, slingers 7 -> 19 (59,
34 and 18 of them lost in the fight state), and the Spanish lancers did it
(their kills of bowmen 3 -> 36 a battle, slingers 1 -> 16, canoe raiders 7
-> 20; the lancers' own losses 56 -> 38). The spring's attack order sent a
missile band with no target in range toward the nearest enemy, often the
lancers riding on the bait, out of the woods; it melted and sprang again
(each band 1-3 springs and melts a battle) instead of skirmishing from
cover as the ordinary rules do (the play off: bowmen lose 7). The warriors
also chased the lancers into the open, where the rodeleros' kills of them
rose 27 -> 69. Between springs the Spanish foot stood 40-80 m out in the
open shooting at the slingers' bait and whatever it revealed.

Three variants (48 seeds, the play on; natives' wins, natives' losses a battle):

| Variant | asym_woods2 | asym_woods | ambush_field |
|---|---|---|---|
| as built (before) | 35 (395) | 48 (168) | 13 (314) |
| 1. missile foot never hide: skirmishers 24 m inside the woods, fire at will, never spring or melt; baits from them too | 45 (240) | 48 (94) | 6 (303) |
| 2. ... their fire held until the line springs (or they are seen) | 42 (331) | 48 (98) | 4 (305) |
| **3. kept**: missile foot hide in the line and spring with it (the first volley), then the woods' skirmishers (`R_SKIRM`) | **44 (289)** | **47 (110)** | **16 (301)** |

Kept variant 3, the only one inside the bounds (`asym_woods2` 42 or better,
`asym_woods` 46, `ambush_field` 10): Spanish / natives / draws 3 / 44 / 1,
0 / 47 / 1 and 29 / 16 / 3 (the measured table above). In `ambush_field`
the bows' hidden first volley is what variants 1 and 2 lost (the warriors'
kills 133 -> 92 a battle without it). Not built: a respring delay
(`AMBUSH_RESPRING_T`, ids 326-329 stay gaps), a spring needing two hidden
units near, the melt's "winning" read over the whole side; the cycle fell
from near 10 springs a battle to 2.5 without them.

**Open.** `asym_woods2` natives' losses stay a little above the play off
(289 against 280; the warriors still chase riders into the open: a sprung
unit's target is the nearest enemy seen, riders too); the Skilled flank never won a
battle in `ambush_field` (the Spanish Average column does not come in); a
spring has no chronicle line (no view element, as the tercio).

### 44.6 The Swedish salvo (as built, 2026-10-29)

Gustavus Adolphus's drill: a musket line holds its fire, closes to point
blank, fires every loaded man in one volley (three ranks as one) and the
pike and horse charge in behind it. Bit 3 of `ai_plays` (`Plays.P_SALVO`),
England's, France's and the Dutch rows in `west.gd` `PLAYS` (2 -> 10; Spain
not: its drill is the tercio; the natives and the Brethren not). Code:
`sim/plays.gd` (the salvo section), knobs and counters in
`sim/ai_profile.gd`, two hooks in `sim/battle_ai.gd` (`think` calls
`Plays.salvo_tick` every tick for an AI side, so the charge follows the
volley to the tick; `_issue_line` leaves the salvo's units out of its
orders, `Plays.salvo_slots`) and one sim rule in `sim/battle_sim.gd` (the
charge with the butt, below; docs/design/battle_sim.md "The charge with the
butt"); scenario `salvo_field` in `sim/scenarios.gd`; the probe's SALVO line
in `tests/asym_probe.gd`; test `determinism_test.gd --only=plays`
(`_check_salvo`).

- **Trigger** (`salvo_target`, each army think while the play runs and has
  no target): no settlement, no town plan; the side has two free musket
  lines (gun foot with shots, `_gun_foot`; not mauled, guarding, held in
  reserve, manning works or in a melee) and a free melee unit (pikes, line
  or shock foot, horse; not the general); an enemy foot unit (line or shock
  foot, pikes, a musket line) the side sees, ready and not in a melee,
  within `SALVO_RANGE_R` (box to box) **in front of** one of the free lines
  and not charging it (an attack order on it: the countermarch's last
  volley meets that). The nearest such pair, in index order, is the target.
  The play starts at the first army think with a target (never while the
  side lies in ambush).
- **Hold** (`SV_HOLD`): the two free lines nearest the target, the two free
  melee foot nearest it and the nearest free horse are the salvo's
  (`PS_SV_*` in the side's memory; the tercio's layout rewrites every unit's
  `PU_*` at each line order, so the salvo keeps its units there). The lines'
  countermarch goes to Hold and fire at will off; each army think the posts:
  the lines side by side `LINE_GAP` apart, their front `SALVO_FIRE_R` short
  of the target's box along the line from their middle to it, facing it,
  at the walk; the foot `SV_BEHIND` 6 m behind a line's rear rank (one foot
  unit: behind the middle); the horse `SV_WING` 10 m out beyond the outer
  line's end on its own side, level. A walk that has not got there in
  `SV_HOLD_T` 60 s is given up (the reset).
- **Salvo** (`SV_FIRE`, `salvo_tick`): when every line is within
  `SALVO_FIRE_R` + `SV_SLACK` 3 m of the target (or has stopped within
  `SALVO_RANGE_R`), or a line is in contact, fighting or charged by enemy
  foot or horse within `SV_CLOSE` 40 m, each line is ordered at the target
  (an attack order: at 25 m it stands and shoots). On Hold its next volley
  is the body volley: every formed man with a charge in one tick, the sim's
  `_gun_unit`; the two lines fire within `FIRE_THINK` (0.5 s) of each other,
  each as the sim's staggered fire think picks the target up. A line still
  reloading at the order waits for its volley up to `SALVO_WAIT_T`; then its
  countermarch goes to Auto, whose last volley (the target within
  `CM_CLOSE`) fires every man loaded by his own clock: what is loaded. A
  line that has fired nothing `SV_GRACE` 3 s after that is left out.
- **Charge** (`SV_CHARGE`): the tick after the last line's volley the foot
  and horse are ordered at the target at the run (riders with `"charge"` 1:
  a caracole row charges home, it does not ride a pass); the lines with
  `SALVO_MUSKET_CHARGE` charge it too with the butt (the sim rule below),
  else they reload and fire at will (back to the ordinary rules, the
  countermarch still on Hold). The foot become `A_ATTACK`.
- **Reset**: `SALVO_RESET_T` after the charge, the target routing or gone,
  both lines lost before the volley, or the walk timed out: the lines'
  countermarch back to Auto, the units back to the ordinary rules, the next
  target may be taken (`SV_LOOK`). Every army think while the play has run,
  any ready musket line of the side on Hold that is not in a salvo under way
  is set back to Auto (a line routing at the reset cannot take the order;
  the AI never sets Hold otherwise).
- **Drop** (for good, `PS_SV` 2, after the reset's orders): the side has
  fewer than two ready musket lines with shots or no melee unit, or no
  target has been found for `PLAY_DROP_T` 30 s.
- **With the other plays**: the tercio may run beside it (a salvo line that
  is a sleeve or a pike block that is a salvo foot unit is the salvo's while
  it runs: `unit_think` asks the salvo first); never while the side lies in
  ambush. The countermarch is on Hold on the salvo's lines while it runs.
- **Memory** (the plays' tail; `PS_K` 14 -> 26: every battle with the plays'
  memory hashes differently, none pinned): per side the state, phase, phase
  tick, trigger tick, target, the two lines, two foot and the horse, the
  lines' shots left at the fire order. Integers, index order, no RNG.
- **Counters** (`stat_aic`, diagnostics): `play_salvo` (a target taken),
  `salvo_volley` (a line's salvo fired), `salvo_charge`.

| Knob (`ai_profile.gd`) | Easy | Average | Skilled |
|---|---|---|---|
| `SALVO` 330 | 0 | 1 | 1 |
| `SALVO_RANGE_R` 331 | 60 m | 60 m | 60 m |
| `SALVO_FIRE_R` 332 | 25 m | 25 m | 25 m |
| `SALVO_WAIT_T` 333 | 50 (5 s) | 50 | 50 |
| `SALVO_MUSKET_CHARGE` 334 | 0 | 0 | 1 |
| `SALVO_RESET_T` 335 | 300 (30 s) | 300 | 300 |

Ids 326-329 are a gap (`KNOB_GAPS`); 336-339 are the redesign's knobs (below; `N_KNOBS` 340).
Constants (`plays.gd`): `SV_SLACK` 3 m, `SV_BEHIND` 6 m, `SV_WING` 10 m,
`SV_HOLD_T` 600 (60 s), `SV_CLOSE` 40 m, `SV_GRACE` 30 (3 s).

**The set piece** (`_check_salvo`: two English musket companies 55 m from a
standing pike block of 240, a pike block behind them, pistoleers on the
flank, Average): started at once; the lines on Hold, fire held, not a shot
on the walk; the fire order at 25-27 m; each line's volley every formed
loaded man in one tick (100 of 100), the two a tick apart (ticks 248, 249);
the charge at 250 (the volley + 1); the 240 lose 71 men to the two volleys;
the reset when the block routs, the lines on Auto the same tick. Skilled:
the lines charge with the butt and reach contact; against 240 pikes they
are thrown back off the field (a butt charge into an unbroken pike block
loses).

**Measured** (`tests/asym_probe.gd`, 48 seeds from 5000, both sides
Average; the English side 1 with `--plays1=2` off / `10` on, the Spanish of
`play_field` with `--plays=7` (their default is every bit, so they would run
the salvo too); `salvo_field` new: the Spanish 3 musket companies of 100, 2
pike blocks of 120 and 60 lancers, 3,540, against the English 4 musket
companies of 100, a pike block of 120 and 50 pistoleers, 3,500, 600 x 400 m
open; the English wins of 48, the men lost a battle, the English salvo
lines' losses while walking in (fire held), the salvos and volleys a
battle):

| Probe | English wins (Spanish / draws) | English lost | Spanish lost | lines lost walking in | salvos / volleys |
|---|---|---|---|---|---|
| salvo_field off | 38 (10 / 0) | 270 | 390 | | |
| salvo_field on (as built) | 16 (32 / 0) | 374 | 376 | 18.8 | 2.58 / 4.12 |
| play_field off | 16 (32 / 0) | 506 | 490 | | |
| play_field on (as built) | 7 (41 / 0) | 536 | 456 | 21.8 | 2.85 / 4.10 |
| asym_field, the Spanish without the bit (`--plays=7`) | natives 6 (42 / 0) | | | | every battle as before the play |

`play_field` off is every battle as before the play (HEAD `306af30`);
`asym_field --plays=7` likewise (the Spanish side's default there is every
bit; with it the Spanish run the salvo against the natives and fall 42 ->
31 wins, natives' losses 471 -> 487, the Spanish 217 -> 264: not their row's
play, measured for information).

**The target missed.** The English lose 22 more battles of 48 in
`salvo_field` and 9 more in `play_field`, with more men lost, and the
Spanish lose fewer. Not the closing: the lines lose 19-22 men a battle
walking in. A per-phase diagnostic (16 seeds, `salvo_field`) found the
salvo itself trades well (in its phases the Spanish lose 203 men a battle,
the English 175), and the loss comes after it: the English musketeers' dead
double (133 -> 256 a battle), killed by the Spanish musketeers (103 -> 163:
the lines are left at 25 m, in the Spanish line's last-volley range, for
the rest of the battle) and the lancers (24 -> 66), while the English pike's
kills of lancers fall 21 -> 5: the pike and horse spent on the charge no
longer screen the lines, and with the English melee gone the Spanish
melee is no longer held back from the musket lines (section 29's reserve
rule, `_melee_left`). The targets: pike blocks 30, musket companies 10 (of
40 salvos in 16 battles).

Two changes within the plan were tried (48 seeds each, the play on):

| Variant | salvo_field English wins (lost / Spanish lost) | play_field English wins (lost / Spanish lost) | salvos / volleys a battle (salvo_field) |
|---|---|---|---|
| as built | 16 (374 / 376) | 7 (536 / 456) | 2.58 / 4.12 |
| A. a shorter closing: `SALVO_RANGE_R` 40 m | 28 (311 / 393) | 11 (507 / 473) | 1.25 / 1.08 |
| B. the horse charges first (at the fire order) | 18 (362 / 388) | 5 (532 / 445) | 2.42 / 3.81 |

Two diagnostic variants beyond the plan (not kept), to test the reading below:

| Variant | salvo_field English wins (lost / Spanish lost) | play_field English wins (lost / Spanish lost) |
|---|---|---|
| C. the lines alone: no foot or horse in the salvo | 21 (370 / 394) | 6 (537 / 464) |
| E. the horse only, the foot kept back as the lines' screen | 25, 1 draw (366 / 405) | 7 (536 / 461) |

Neither reaches the target; A is better only because fewer salvos happen.
The build keeps the plan's values. Keeping the melee back (C, E) helps a little in `salvo_field` and not at all in `play_field`, so the larger cost is the lines left at point blank after the volley (the Spanish musketeers' kills of English musketeers +60 a battle), not the charge.

**Open.** The play costs the English battles on both pairs as built; until
it is redesigned the PLAYS rows can go back to 2 (one line). Leads, not
built: after the volley the lines step back out of the enemy's last-volley
range to reload (or re-form on the line); the charge only with the horse,
the pike kept as the lines' screen (variant E above); no salvo at a pike
block (the targets were three in four pike blocks; the volley there is
worth most, the charge least). Skilled's butt charge was not measured on
the pairs (the set piece shows it losing to an unbroken block).

### 44.6 Redesign (2026-10-30)

The leads above built and measured in four steps (`sim/plays.gd` the salvo
section only; no hook changed in `battle_ai.gd` or `battle_sim.gd`; knobs
336-339 in `sim/ai_profile.gd`; `tests/asym_probe.gd` gains `--knob=ID:VALUE`,
a knob set in every profile row for a variant's measure without an edit).

- **The target** (`SALVO_TARGET`): 1 (every level) never a pike block or a
  braced unit (`u_braced`); 2 shooters only (gun foot); both take a musket
  line or a shaken (morale below `SV_SHAKEN` 500, `BattleAI.CC_SHAKEN`) or
  disordered (`u_disorder` at `SV_DISORDER` 25, `BattleSim.DISORDERED`)
  unit before other foot; nothing in reach, no salvo. 0 is the build above.
- **The step back** (`SALVO_BACK_R`, 45 m; 0 the build above): the tick
  after the volley (the charge, `SV_CHARGE`) the lines walk to posts
  `SALVO_BACK_R` short of the target's box (`_sv_posts` mode 1), fire held,
  the countermarch on Hold; at `SALVO_BACK_R` - `SV_SLACK` (box to box), at
  their post, the target gone, or caught on the way (contact, a melee,
  charged within `SV_CLOSE`) each line is `SB_POST` (`PS_SV_A` in the charge):
  re-formed where it stands facing the target (a move that short re-forms
  in place), the countermarch on Auto, fire at will, held there until the
  reset. With foot that charged (`SALVO_PIKE_CHARGE` 1), the charge's end
  (the rout or `SALVO_RESET_T`) is the reform (`SV_REFORM`): the foot not in
  a melee walk back to `SV_BEHIND` behind the lines' rear rank, the horse to
  the ordinary rules; the reset when every such foot unit is within
  `SV_HOME` 8 m of its post or after `SV_REFORM_T` 20 s.
- **The screen kept** (`SALVO_PIKE_CHARGE`: 0 Average, 1 Skilled): at 0 only
  the horse charges the volleyed unit; the foot stay `SV_BEHIND` behind the
  lines (behind their step-back posts in the charge) and charge an enemy
  foot or horse unit charging a salvo line within `SV_SCREEN_R` 60 m (or
  fighting one), back to their post once it is gone or 120 m off.
- **The run** (`SALVO_RUN_R`, 0 every level): the lines close the last this
  many metres at the run.
- Skilled keeps `SALVO_MUSKET_CHARGE` 1: its lines charge with the butt and
  do not step back (not measured on the pairs).

| Knob (`ai_profile.gd`) | Easy | Average | Skilled |
|---|---|---|---|
| `SALVO_TARGET` 336 | 1 | 1 | 1 |
| `SALVO_BACK_R` 337 | 45 m | 45 m | 45 m |
| `SALVO_PIKE_CHARGE` 338 | 0 | 0 | 1 |
| `SALVO_RUN_R` 339 | 0 | 0 | 0 |

Constants (`plays.gd`): `SV_SHAKEN` 500, `SV_DISORDER` 25, `SV_REFORM_T`
200 (20 s), `SV_HOME` 8 m, `SV_SCREEN_R` 60 m. Phases: `SV_REFORM` 4;
a line's step back `SB_BACK` 1, `SB_POST` 2. The memory's layout is
unchanged (`PS_K` 26).

**Measured** (as above; the English wins of 48 seeds from 5000, the English
lost / the Spanish lost a battle; 144 seeds from 5000 where given, the
measure that tells the variants apart, a 48-seed count moving by 3 or so
between near-equal variants). Steps 2 to 4 were measured with the lines
halted where the walk back left them, still facing away from the target;
the build turns them to face it (last rows).

| Variant | salvo_field | play_field | 144 seeds (sf / pf) |
|---|---|---|---|
| the bit off | 38 (270 / 390) | 16 (506 / 490) | 109 / 48 |
| as built (2026-10-29) | 16 (374 / 376) | 7 (536 / 456) | |
| 1. `SALVO_TARGET` 1 | 31 (332 / 409) | 8 (523 / 449) | |
| 1. `SALVO_TARGET` 2 | 31, the same battles | 8, the same | |
| 1 + 2. the step back to 55 m, the pike charging (with the reform) | 32 (317 / 398) | 15 (526 / 487) | 85 / 47 |
| 1 + 2 + 3. the pike held as the screen | 28 (312 / 385) | 15 (526 / 488) | 93 / 45 |
| + 4. the run for the last 20 m (pike held) | 32 (301 / 382) | 15 (527 / 505) | 98 / 41 |
| + 4. the run (pike charging) | 29 (322 / 395) | 15 (525 / 501) | |
| `SALVO_BACK_R` 35 / 40 / 45 / 70 m (pike held) | 45 m: 32 (302 / 384) | 45 m: 16 (508 / 504) | 89 / 32, 94 / 46, 98 / 48, 84 / 34 |
| 45 m, the pike charging / with the run | | | 80 / 48, 90 / 48 |
| **kept**: 45 m, the pike held, the lines facing the target at their post | **28 (302 / 362)** | **19 (507 / 510)** | **88 / 44** |

Tried and not kept (144 seeds unless given): the step back by 6 m hops
re-formed in place every 4 s, facing the enemy (no turn about): 87 / 18
(held at the post), 86 / 34 (released to the ordinary rules at it); the
kept build holding its fire at the post: 88 / 20; the lines released to the
ordinary rules at their post (walk back): pf 36; a "quiet" rule (no salvo
starts, and one walking in is called off, while an enemy foot or horse unit
within 80 m of the lines is in a melee or charging one of the side's units;
96 seeds, off 72 / 35): 72 / 30, the play nearly never firing (0.35 salvos,
0.05 volleys a battle); the fire order at 43 m (outside the enemy's last
volley), step back 55 or 70 m: 30 / 31 of 48 on salvo_field; `SALVO_RANGE_R`
40 m: 38 of 48 with 0.27 salvos a battle (the play mostly idle).

**Reading.** Step 1 is most of the gain (no salvo into a pike block: the
volley where the charge loses), the step back the rest on play_field (8 ->
15-19), where the Spanish now lose more men than with the bit off (510
against 490). salvo_field stays short (28-32 of 48 against 38; 88-98 of 144
against 109): a salvo there mostly starts beside a melee (the Spanish pike
coming on), and the two lines that hold their fire for the walk in stop the
rolling fire that held it off; calling the salvo off near a melee leaves no
salvo at all. The halted-facing-away step back measured best (98 / 48 of
144) but leaves the lines with their backs to the enemy for up to 30 s; the
kept build faces them about (88 / 44).

**Kept, the bit off.** The build keeps the redesign at the knobs above; the
target is met on play_field (19 of 48, at or above 16, the Spanish losses
up) and missed on salvo_field (28 against 38), so England, France and the
Dutch stay at `PLAYS` 2 (`west.gd`); custom battles and scenario keys get
the play. `asym_field` and the campaign are unchanged (the four
`campaign_sim` hash lines equal the pins). Test: `determinism_test.gd
--only=plays` (`_check_salvo`): the set piece's target is now 300 rodeleros
(no salvo at a lone pike block, checked); Average: the pike never charges
and stays behind the lines, the lines step back at least 5 m with fire held
and are on Auto at their post; Skilled: the pike and the lines (the butt)
charge; Average with `SALVO_PIKE_CHARGE` 1 (the row changed for the run):
the reform, the pike walking back, the reset within `SV_REFORM_T`.

## 45. Native siege: poles and torch raiders (2026-10-29)

The AI side of docs/design/campaign_rules.md "Native siege (as built)" and docs/design/siege_and_towns.md "Native
siege: scaling poles and the melee batter (as built)". Code: `sim/siege_ai.gd` (`_ladderish`, `_torch_gate`,
`_foot_key`, the exclusions in `_batter_bld` and `_assign_mantlets`), `sim/ai_profile.gd` (`R_TORCH_GATE`),
`campaign/cai.gd` (the wagon rule), `campaign/data/west.gd` (the Miskito's mix).

1. **Poles are ladders.** Every rule that reads ladders reads `EQ_LADDERS` or `EQ_POLES` (`_ladderish`): the ladder
   parties of `_assign_equip` (`S_LADDER_UNITS` sets in all, planted ones counted, `S_LADDER_FOLLOW` followers),
   `_escalade`, the fort's shut-the-gate and sally-back rules (ladders near the gate). The scenario lists the poles
   after the ladders, so a storm with both takes the ladders first (they climb faster).
2. **The storming party.** `_foot_key` (the ladder parties' heaviest-first key) gave every West row the same key 3,
   so the ladders went to infantry by unit index (the Itza's warriors before their Holcan). The West's `heavy` line
   (rodeleros, cutlass men, the Holcan) is now key 0 (Rome's heavy); the Spanish attack lists, whose only infantry
   are rodeleros and cutlass men, choose as before. `_solidity` (the field line's order) is not what picks the
   party and is unchanged.
3. **Torch raiders as the ram** (`_torch_gate`, from `_att_missile` before the grenadiers' rule; `R_TORCH_GATE`
   Easy 0 / Average 1 / Skilled 1). Attacking a town, in the approach with the attacked gate (`ai_gate`) shut, or in
   the assault with the citadel's gate or a stormed West fort's gate (`ai_fort` 2) shut, and no ram of the side
   able to work a gate (`_ram_avail`): the batter ability's Use now at that gate (the men go to its face and
   strike it, `_update_mbat`); else back to Auto. Not engaged; ordered only when the wanted state differs
   (stateless). With a ram on the field the ram's unit breaks the gate and the torch raiders are grenadiers.
4. **Torch raiders as grenadiers.** Otherwise the AI.md 39 rule (`_gren_siege`, `R_GREN_SIEGE`) runs for their pots:
   Hold in the approach outside the town, Use now at a shut gate in reach or at an enemy unit holding a building
   within range, Auto in the town (where Auto throws only at held buildings and shut gates). While battering they
   stay on Auto and throw their pots at the gate they stand at (fire). They are never given the ram, a ladder set or
   a mantlet, nor the siege guns' building batter (`_batter_bld` skips a melee batter).
5. **Campaign.** Poles come with the assault (CBattle.siege_equipment, a War lodge 2: docs/design/campaign_rules.md),
   so the AI takes them as it takes ladders (4.6): nothing to buy, the assault decision's kit (`kit_of`) counts them as
   ladders (WALLS_PCT_WEST's kit 0 and 1 columns are equal). The Miskito's mix has `siege` 5 (from `light` 44 -> 39):
   the torch raiders, raised through the mix (`MIX_LIVE`: only once a recruiting centre has a War lodge 2, which the
   build-up's want list then builds: the Barracks cap is 2 with the row). The wagon rule (`WAGON_MIN`, AI.md 23) takes
   only a wagon row from the siege line (the Miskito's is the torch raiders: no wagon). Not in `AI_SPECIALISTS`: the
   line has no main unit below them.

Knob: `R_TORCH_GATE` (292, from the play library's unused 292-299; `KNOB_GAPS` now 293-299). Tests:
`tests/roles_sim_test.gd --only=native` (the AI at Average batters a walls-2 oppidum's gate with them and it falls;
Easy gives no ability order), `tests/determinism_test.gd --only=native`.

## 46. Pursuit as a unit (2026-10-30)

**The owner's report:** "a unit can get really split up if they are chasing a unit and get close enough for the
first line to break off and start attacking, as the other unit keeps fleeing 2 things happen. 1 the unit is way less
affective than it could be if it pushed and attacked with the entire unit that is fleeing. 2 the unit gets split
up, and then starts acting a little weird when trying to reposition this split up unit."

Sim only (no AI rule or knob changed); as built in docs/design/battle_sim.md "Pursuit as a unit (as built,
2026-10-30)". Code: `sim/battle_sim.gd` (`_chase_mode`, `reform_anchor`, the attack branch's closing, `_anchor_step0`,
the man step's rear leash). Probe: `tests/chase_probe.gd`.

1. **The reading, checked by the probe first.** Flat open ground, scripted orders, 8 seeds, 60 s from the order then a
   move 40 m to the flank at the run for 30 s. Set pieces: *brk* 100 heavy attack 100 heavy face to face, the target
   routs at 15 s; *rout* 100 light attack 100 heavy routing 15 m ahead; *walk* 100 heavy (at the run) attack 100
   light walking away under a move order; *cav* a horse unit attacks 100 light routing 40 m ahead; *skirm* (West)
   100 native warriors (at the run) attack 80 native bowmen in skirmish mode. What HEAD did:
   - (a) *Routing target.* The anchor ran after it but stopped at the target's box edge + 1 m measured with the box's
     half depth from its centre: a router box is long ahead and short behind its centre, so the stop was 3-4 m
     behind the real rear men, and the front rank, capped at `PLACE_LEAD` 1.5 m ahead of its places, stood just out
     of reach for the whole chase (*rout*: 0.1 kills in 60 s; *cav*: 11 kills in the first 10 s of contact, then 35 s
     at 5-8 m with no blow). The main session's guess that fighters fall behind a running block was not what the
     probe showed in the open: **after routers the anchor runs (7/8 of the run) while its men walk** (`u_run` 0: the
     formed pace is the walk within `CATCH_UP_DIST` 3 m of a place), so the whole unit trails 2.7-2.9 m behind its
     places. An anchor runs at 7/8 of its men's run and routers at 7/8 of theirs: a type never gains on routers of
     its own speed (*brk*: only the men in contact when it broke kill; 18 kills, all within 10 s of the break).
   - (b) *Target moving away (not routing).* Confirmed and worse than a stutter: the anchor holds while any man is
     within `INREACH_EXTRA` (reach + 1 m) of his man, so the men stand at reach + 1 m, never within reach, and the
     anchor moves only when they drop out of it (*walk*: 12.5 men "in reach", 0 blows, 0 kills in 60 s; *skirm*: the
     same against bowmen falling back, 0 kills).
   - (c) *Reposition.* In the open the move is taken cleanly (14-16 s to formed for a 40 m move at the run, no anchor
     jump; the march faces its way, so the facing turns twice). The REGROUP jump the brief names fires only among
     obstacles (`LAG_CUT`, `oon`); not reproduced on open ground.
2. **The rules** (each with its switch, static, 1 on; constants in `sim/battle_sim.gd` next to `ANCHOR_LEAD`):
   - *Moving away* (`_chase_mode`): each unit's centre sampled every `CHASE_DT` 10 ticks (`u_hx`, `u_hy`, the
     movement since `u_vx`, `u_vy`); a target routs (2), or fewer than a quarter of its men fight and its centre went
     `CHASE_AWAY_MIN` 0.5 m or more away from the attacker's anchor over the last sample (1). The target's own
     movement: the brief's "distance grew" would switch off as soon as the anchor kept pace.
   - *Push* (`CHASE_PUSH_ON`): a pursuer's anchor stops 1 m from the target's centre (the pack's stop) and may step
     into its target's footprint with men in reach.
   - *Pace* (`CHASE_PACE_ON`): "wait for my men" only against a target not moving away; otherwise the anchor keeps
     closing at its own walk or run (it then follows the target at the target's speed).
   - *Men run with their places* (`CHASE_RUN_ON`, not in the brief): its anchor running after routers, its men's
     formed pace is the run. The rear leash needs it: without it every man is 2.7-3 m behind his place and the
     leash drops them all.
   - *Rear leash* (`CHASE_BACK_ON`, `PLACE_BACK` 3 m): while the anchor moves (or it pursues) a fighting man more than
     3 m behind his place lets his man go and makes for it; he takes a man again within `PLACE_LEAD` of it. Not on
     walls, stairs, in a building, carrying, a pack, a formed pike block, a charge.
   - *Re-form on the men* (`CHASE_REFORM_ON`, `reform_anchor`): a new move or attack (not a move to about the same
     point, not an attack on the same target: the AI's repeated orders) to a unit whose men's middle is more than
     `REFORM_IN_PLACE_DIST` from its block or whose men spread along the facing over twice its depth puts the anchor
     on the men first (the block centred on their middle); no lag regroup within `REFORM_QUIET` 50 ticks of one.
   - *Settlement maps* (`CHASE_TOWN_ON` 0): none of the rules on a settlement map (`city_on`), see 4.
3. **Probe, before -> after** (8 seeds; spread: the attacker's men along its facing, m; from place: mean m; in reach:
   men within reach + 1 m; strikes: blows a second; kills in 60 s; the reposition's seconds to 90 % within 2 m and
   its largest anchor step in a tick):

   | Case | spread | from place | in reach | strikes/s | kills 60 s | reform s / step m |
   |---|---|---|---|---|---|---|
   | brk | 7.8 -> 6.3 | 2.4 -> 0.9 | 10.4 -> 10.7 | 4.2 -> 4.2 | 18.2 -> 18.6 | 16 / 0.31 -> 16 / 0.31 |
   | rout | 7.0 -> 5.1 | 2.9 -> 1.0 | 0.9 -> 10.0 | 0.0 -> 3.6 | 0.1 -> 31.5 | 14 / 0.38 -> 14 / 0.38 |
   | walk | 5.2 -> 4.3 | 0.3 -> 0.6 | 12.5 -> 2.7 | 0.0 -> 1.4 | 0.0 -> 25.1 | 16 / 0.31 -> 16 / 0.31 |
   | cav | 12.7 -> 10.0 | 2.7 -> 1.7 | 2.0 -> 5.8 | 0.9 -> 3.0 | 10.8 -> 42.6 | 8 / 0.72 -> 8 / 0.72 |
   | skirm | 5.7 -> 5.5 | 0.7 -> 1.2 | 0.2 -> 7.2 | 0.0 -> 2.2 | 0.0 -> 41.0 | 13 / 0.41 -> 13 / 0.60 |

   One rule off (kills in 60 s, rout / walk / cav / skirm; all on 31.5 / 25.1 / 42.6 / 41.0): back off 28.0 / 25.0 /
   46.9 / 36.5 (spread rout 5.1 -> 6.8; skirm's reposition re-forms, one 3.0 m anchor step); push off 4.1 / 24.9 /
   15.1 / 5.9; pace off 31.5 / 0.0 / 42.6 / 0.0; run off 0.0 / 25.1 / 0.0 / 41.0 (the leash without the run); reform
   off unchanged in the open (no unit is strung out at 60 s with the other rules on). With all switches 0 the probe
   reproduces HEAD exactly. *brk* does not change: heavy cannot catch heavy routers.
4. **Harness** (HEAD `7a43b72c88` -> this build `28061e061f`, `tools/balance/measure.py`, both packs). Built first
   with the rules on every map: `rome_walls` attackers 47.2 -> 60.4 % (walls 1 70 -> 83, 2 40 -> 60, 3 32 -> 38;
   five cells beyond their intervals), `open_town` 67 -> 92 % (Havana 25 -> 75 *). Walls 2 with one rule off: back
   59, push 60, pace 48, run 53, reform 47 (and reform off on all walls 59 %): no one rule; pace and the re-form most
   (in a siege the AI re-targets its storming units often, 40-130 re-forms a battle, and defenders falling back are
   now pursued). So the rules are off on settlement maps (`CHASE_TOWN_ON` 0): with that, `rome_walls` 47.2 % (70 /
   40 / 32) and `open_town` 67 % are HEAD's to the battle, `west_walls` 38 % (walls 0 / 1 / 2: 52 / 34 / 27) as HEAD's: the result lines of all three town plans equal HEAD's line for line. The campaign pins of all four sets
   (Rome, rome10, West, west10) are unchanged (the campaign's battles are auto-resolved). Fight jitter and stuck runs
   (`tests/pathing_probe.gd`, seeds 7-10, before -> after): fight jitter (town / near obstacles) 1.8 / 2.0 / 1.9 /
   2.0 % -> 1.8 / 2.0 / 1.9 / 2.2 % (seed 10's near-obstacle field maps), stuck runs over 30 s 2 / 1 / 1 / 1 -> the
   same, rout jitter and stationary routers within 0.1 %. Field balance (`tests/matchups.gd`, 20 seeds, scripted):
   every winner and decision time of the set pieces is as before (the battle is decided at the break); what follows
   the break kills more (pike 120 taken in the flank 58.7 -> 95.0 killed, from the rear 77.8 -> 104.9; a horse charge
   into an engaged unit's rear 45.8 -> 82.0; horse into archers 49.7 -> 75.8; the rear charge into spears 50.2 ->
   78.3); the equal-cost grid moves only where a melee unit runs down skirmishers: light vs javelins 30 -> 100 %,
   spear vs javelins 20 -> 40 %, javelins vs light 70 -> 10 % (light infantry's own card says "skirmishers they can
   run down"); spear vs pike 0 -> 10 %, pike vs spear 100 -> 90 %. `bench_2000` AI vs AI (10 seeds) decided after 7.4
   -> 6.7 min, wins 5 / 5 as before; the hill-terrain AI battles 4.5-9.7 min as before (rolling 5.6 -> 5.0).
5. **The light missile check (2026-10-30, after the merge).** `tests/custom_battle_test.gd` "light missile" (nine
   skirmishing rows of ours with attack orders against the AI's four foot units) failed: "tarentines never shot in
   2400 ticks". By switch: back off or push off passes, pace / run / reform off still fail. No rule touches a missile
   unit's own conduct: the Tarentines never pursue (`u_chase` 0 throughout; a missile unit with ammunition takes the
   shooting branch, not the closing one), and with the enemy standing (no AI) every row's shots are the same with all
   switches on or off. What changed is the AI's foot: they now run after the skirmishers that fall back (pace), and
   at this seed the Tarentines, whose attack order ends when they fall back (`_missile_think`, as before), were left
   with nothing within 40 m past their friends for the rest of the run. The check was fragile before the change too:
   at HEAD with seeds +1..+7 it failed at two of eight (the Tarentines at +5 and +7), with the rules at three. Fixed
   in the test, not the sim: a row that has not shot in the crowd is tried alone against the AI's 100 light foot
   and must shoot there (it does, every seed tried, both builds). No sim change, so the probe (the kills table in 3),
   the goldens, the pins and the harness are unchanged. Open: a skirmisher that fell back forgets its attack order
   and stands; horse javelins in a crowd often have no clear line (`_clear_line`) to a target at 36 m.
6. **Open.** Pursuit in towns (the rules are built and switchable: `CHASE_TOWN_ON` 1 is the ungated build; a town
   version needs its own design, perhaps pace only for routers and no re-form for AI orders); the reposition
   "acting weird" among obstacles (REGROUP) is not reproduced in the open probe, and with the rules off in towns
   it is as before; equal-speed pursuers never close on routers (an anchor at 7/8 of the run; the owner may want a
   pursuit bonus); field battles are not in the harness plans (the matchups above are the field check).

## 47. Pursuit in towns, the pursuit bonus, the skirmisher's order (2026-10-30)

Three follow-ups to 46, agreed with the owner; sim only. Code: `sim/battle_sim.gd` (`CHASE_TOWN`,
`CHASE_TOWN_LEASH`, `CHASE_TOWN_RUN`, `_chase_mode`, `_push_stop_ok`, `reform_anchor`; `CHASE_FULL_RUN_ON`,
`CHASE_FULL_RUN_TOWN`; `SKIRM_RESUME_ON`, `u_ptarget`, `_missile_think`). Probe: `tests/chase_probe.gd` (new case
*town*, switches `--town=0|1|2`, `--off=...,bonus,resume,tbonus,tleash,trun`).

1. **Pursuit in towns** (`CHASE_TOWN`, replaces `CHASE_TOWN_ON`: 0 none of the rules on a settlement map, the 46
   build; **1 the town rules**, the default; 2 every rule as in the field). With 1, on a settlement map:
   - *Pace and push only after routers*: `_chase_mode` returns 2 for a routing target and 0 for everything else
     (a defender falling back or withdrawing is not "moving away" there), so "wait for my men" and the box-edge
     stop hold against it as before 46.
   - *The push's stop* (`_push_stop_ok`): after routers the anchor stops 1 m from their centre only where that
     point is open ground (or ditch); in a gate, on any wall cell (body, walk, tower, stair), on rubble, in a
     house, or within `OCC_DOOR_R` of a held building's door step it stops 1 m short of the box edge as before
     (and a target holding a building is still fought at its door, the occupation rule).
   - *Re-form only for a player's order*: `reform_anchor` reads the order's own `player` (AI orders carry
     `BattleAI.AI_PLAYER_BASE + side`, `sim/battle_ai.gd` `_order`, also used by `siege_ai.gd` and `plays.gd`); an
     order from player >= 100 never re-forms in a town. The hash depends on nothing but the order (the preview and
     scripted orders count as a player's). In the field the AI's orders re-form as in 46.
   - *Leash and run* on as in the field (`CHASE_TOWN_LEASH`, `CHASE_TOWN_RUN`, both 1; switches kept for the
     alternative below).
2. **The pursuit bonus** (`CHASE_FULL_RUN_ON`): an anchor after a routing target closes at 8/7 of its old pace, its
   men's full run (with the woods, slope and carry rules as before); routers keep 7/8 of theirs, so a unit now
   gains on routers of its own type. **Field only** (`CHASE_FULL_RUN_TOWN` 0): with it in towns too the town
   plans' pooled rows held but two West towns moved beyond their intervals as a whole (San Juan 25 -> 50 % *,
   Granada 25 -> 48 % *) and `open_town` read 67 -> 79 %; field-only, no town's whole column is flagged.
3. **The skirmisher's order** (`SKIRM_RESUME_ON`, `u_ptarget`: per unit, hashed, in snapshots): a missile unit in
   skirmish mode that falls back from a threat while under an attack order keeps the target as pending; on a later
   think with no order, no threat within `SKIRM_INF` / `SKIRM_CAV` and fewer than a quarter of its men fighting it
   takes the attack order up again (walk) if the target lives, it has ammunition and the target is within
   `SKIRM_RESUME_PCT` 150 % of its range, **and the target is not attacking it**; else it fires at will. Any new
   move, attack, halt or withdraw order clears the pending target. `stat_skirm_resume`.

**What differs from the brief, and why.**
- *The hunt exception (3)*: built as briefed, `tests/matchups.gd` "javelins 150 vs light 100 attacking them" went
  100 % -> 80 % wins (20 % draws, decided 113 -> 162 s) and the equal-cost grid moved (spear vs javelins 40 -> 90 %,
  javelins vs spear 90 -> 70 %): javelins that resumed walked back at the unit hunting them. Not resuming against a
  target that attacks them restores every one of those rows exactly.
- *The bonus is field-only (2)*, see above.
- *The town probe disagrees with the leash and the run in towns (1d)*, see 4; the harness does not, so they are
  on as briefed, with switches.
- *The light missile crowd still fails at three seeds of eight (3)*, see 5.

4. **Numbers: probe** (8 seeds; kills of the target in 60 s, and the other columns as in 46.3; HEAD = this build
   with `--off=bonus --town=0`, which reproduces 46's table exactly):

   | Case | spread m | from place m | in reach | strikes/s | kills 60 s | reform s / step m / within 2 m |
   |---|---|---|---|---|---|---|
   | brk | 6.3 -> 6.2 | 0.9 -> 1.5 | 10.7 -> 17.8 | 4.2 -> 6.7 | 18.6 -> 50.1 | 16 / 0.31 / 100 % as before |
   | rout | 5.1 -> 5.0 | 1.0 -> 1.3 | 10.0 -> 13.4 | 3.6 -> 5.3 | 31.5 -> 48.8 | as before |
   | walk | 4.3 -> 5.5 | 0.6 -> 1.5 | 2.7 -> 2.7 | 1.4 -> 1.4 | 25.1 -> 25.1 | 16 / 0.31 -> 1.00 (a re-form; the target routs at ~12 s and the heavy cannot catch light routers) |
   | cav | 10.0 -> 10.0 | 1.7 -> 1.9 | 5.8 -> 7.0 | 3.0 -> 3.3 | 42.6 -> 45.8 | as before |
   | skirm | 5.5 -> 5.5 | 1.2 -> 1.2 | 7.2 -> 7.3 | 2.2 -> 2.2 | 41.0 -> 40.1 | 13 / 0.60 -> 0.47 |
   | town | 36.8 -> 43.2 | 7.7 -> 8.2 | 7.0 -> 5.0 | 4.6 -> 3.1 | 43.9 -> 28.0 | 18.7 (7/8) -> 18.6 (5/8) / 25.8 -> 34.5 / 95 -> 73 % |

   *town*: a Rome town (walls 1, flat, town seed = battle seed 11..88), 60 heavy defenders in the main gate's
   opening (open), routing into the town, 100 light storming from 8 m outside; no AI. The men of the bonus are 0.3-0.6
   m further from their places (their anchor at their own full run, they cannot gain on it) but in reach of nearly
   twice as many routers: heavy now catches heavy routers (*brk*). Town variants (kills / within 2 m at 30 s of the
   reposition): HEAD (`--town=0`) 43.9 / 95 %; the town rules 28.0 / 73 %; leash off 38.1 / 93 %; leash and run off
   46.5 / 82 %; with the bonus in towns 37.8 / 76 %; every rule as in the field (`--town=2`) 28.5 / 77 %; push off
   27.5 / 76 %; re-form off 28.0 / 73 %. **The rear leash costs the town chase most**: a unit through a gate is a
   column 40 m long with its men 8 m from their places (`TOWN_PLACE_LEAD` 10 m lets them run ahead), and a fighting
   man 3 m behind his place lets his man go. The reposition's 34.5 m step is the re-form on the men (9.1 m with it
   off), the unit deep in the streets after the chase.
5. **Light missile crowd** (`tests/custom_battle_test.gd`'s battle at its seed +0..+7): a row that never shot in
   2,400 ticks at 3 of 8 seeds without the resume rule (the Tarentines at +0, +3, +4) and at 3 of 8 with it (the
   Tarentines at +1 and +4, the javelin horse at +3); with the retry-alone fallback 0 of 8 in both (every such row
   shoots alone). The rule works (1-5 resumes a battle) but does not cure the crowd: horse javelins reach 40 m and
   fall back from foot within 30 m (`SKIRM_INF`), closing only to 34 m (17/20 of range), so in a crowd the foot
   coming on is inside 30 m before the javelins are in range, and they do not shoot while falling back; after a
   35 m fall-back the target is usually beyond 1.5 x 40 m (250 % was tried: 6 seeds of 8 fail). The test keeps its
   fallback (comment updated).
6. **Harness** (before: HEAD `7a43b72c88`, the town plans equal to it line for line, 46.4; after: this build).
   Pooled attacker wins: `rome_walls` 47 -> 50 % (walls 1 / 2 / 3: 70 -> 74, 40 -> 40, 32 -> 36; no cell flagged);
   `west_walls` 38 -> 41 % (walls 0 / 1 / 2: 52 -> 56, 34 -> 38, 27 -> 28; three single cells of 48 flagged, havana
   w0 75 -> 44, santo_domingo w1 50 -> 81, new_orleans w0 6 -> 31, no town's whole column); `open_town` 67 -> 71 %
   (88 -> 100, 88 -> 75, 25 -> 38, each inside). Single flagged cells move from build to build (the other variants
   below flag other towns): the town battles are chaotic at 16 seeds. Variants measured: the brief's build (bonus
   in towns, no hunt exception) rome 48 % (74 / 41 / 29), west 40 % (48 / 42 / 29; san_juan and granada flagged
   as a whole, santiago_de_cuba w0), open_town 79 %; leash and run off in towns (bonus field-only) rome 48 % (76 /
   36 / 30), west 38 % (54 / 33 / 25; five single cells flagged), open_town 79 %. Every pooled cell of every
   variant is inside its interval.
7. **Field** (`tests/matchups.gd`, 20 seeds, against HEAD): every winner and decision time of the set pieces as
   before, and the equal-cost grid and the javelin duel identical; kills after the break up: pike 120 from the flank
   95.0 -> 102.0, heavy vs heavy control 56.9 -> 60.4, with its general behind 69.7 -> 77.2, rear charge into
   spears 78.3 -> 79.3 (pike from the rear 104.9 -> 103.3, horse into archers 75.8 -> 74.9). `bench_2000` AI vs AI
   (10 seeds) decided after 6.7 -> 6.1 min, wins 5 / 5 -> 3 / 7; hill-terrain AI battles 5.6-7.8 min (rolling 5.0
   -> 5.6, valley 7.0 -> 7.8). The flat goldens skirmish and bench_2000 move with the bonus only (the town rules and
   the resume leave them; re-recorded).
8. **Pins and checks.** The campaign pins of all four sets (rome, rome10, west, west10) are unchanged (auto-resolved
   battles). `tests/pathing_probe.gd` seeds 7-10, before -> after: fight jitter (town / near obstacles, the worse)
   1.8 / 2.0 / 1.9 / 2.2 % -> 1.8 / 1.7 / 1.7 / 1.7 %; stuck runs over 30 s 2 / 1 / 1 / 1 -> 1 / 1 / 4 / 1 (seed 9:
   siege_town two units 38 s, siege_oppidum one 30 s, west_hill_village one as before; the longest still 38 s);
   rout jitter and stationary routers within their limits. Stuck runs move with any change in towns: at the brief's
   build west_city seed 10 held one unit 84 s and siege_town seed 7 two, and either went with any one town piece
   switched off. `tests/determinism_test.gd`: `siege_punic@ai` (seed 12345) no longer exercises `gate_art`: the storm
   now takes the town by its breach before the batteries turn on the gate (winner 0 at 6500 ticks, alive 316 / 199;
   before 357 / 174 undecided; battle seed 3 the same in this build); dropped from that run's list, `gate_ops` keeps
   it. (With the bonus in towns it was `siege_city@ai`'s `wall_cover` instead: these counters follow the battle.)
9. **Open.** The leash and the run in towns (the probe's town chase kills 28 with them, 47 without, HEAD 44; the
   harness holds both ways: `CHASE_TOWN_LEASH` / `CHASE_TOWN_RUN` 0 is the alternative, the owner's call after a
   town playtest); horse javelins in a crowd (range against `SKIRM_INF`, no shot while falling back: a skirmish
   rule of its own); the reposition after a town chase (73 % of the men within 2 m at 30 s, HEAD 95 %).

## 48. Units that stand at a hill line (2026-10-30)

The owner (a West campaign battle, the hills pass): "if two units approach each other right at a hill line, they
kinda just stand there and don't engage. I had to manually move the unit forward and once they contacted the enemy
they began to engage." Sim only. Code: `sim/battle_sim.gd` (`HIDDEN_CLOSE_ON`, the attack branch of
`_update_units`: `mlof`, the path condition, the missile stop). Probe: `tests/hill_probe.gd` (grounds flat, ramp,
steep, crest, step on a custom 400 x 400 m field and cliff on generated ridge maps with landforms; modes one / both
/ ai; `--off` the build before; `--check` the regression, PASS / FAIL).

1. **Reproduction.** Melee rows (heavy, rodeleros, native warriors, West pikemen) engaged on every ground and in
   every mode, before and after (results identical line for line). The fault is the **musket lines** (musketeers,
   marines, colonial militia, buccaneers; flat weapons with a line-of-fire rule) under an attack order:
   - *Crest* (a 5 m ridge between them; A at the foot 62 m off, B just behind the crest, no order): A closed to
     31.1 m (a quarter of its 125 m range) with no line of fire and stood there; B, fire at will, skips hidden
     targets. 100 / 100 men alive after 180 s, `u_order` 2, moved 0, nobody fighting.
   - *Cliff* (8 generated cliffs, A 50 m below on the fall line, B 50 m above): at terrain seed 9 A stood 103 m off
     with a line of fire but the target not seen by its side (`u_seen` 0; the cliff blocks sight), so `_pm_cand`
     never gave a shot, while the closing looked at the line of fire only; at terrain seed 4 A walked straight into
     the cliff (on a landform map a missile unit in range never took the path: the exemption `city_on == 0 or
     land_only != 0`), was stuck, regrouped back and stood 64 m off. With both sides ordered onto each other (the
     owner's case) the seed-4 pair stood 62 m apart for good, both unseen; the AI's line the same (56.7 m).
2. **Cause** (lines in the attack branch): `if not mlof: stop = mrange(u) / 4` ("walks to a quarter of its range
   until it can see": it stops there whether or not it sees), `mlof = lof_units(u, t)` without the sight rule the
   shooting uses (`_unseen`), and `not (mis and d <= range_vs(u, t) and (mlof or city_on == 0 or land_only != 0))`
   keeping a hidden target's shooter off the path on field maps with cliffs. Not the cause: the 2D contact test,
   the charge uphill, the steep-ground disorder, the AI's hold-the-heights rule or the pursuit rules (46-47).
3. **Rule as built** (`HIDDEN_CLOSE_ON` 1, a static switch): a missile unit under an attack order whose target it
   has no line of fire to, **or that its side does not see** (`vis_on` and `u_seen` 0), walks on until it sees,
   at worst into contact (the stop a melee unit closes to: the target's half box along the way + 1 m), and on a
   landform map goes round by the path (`land_only` no longer exempt). Once it sees, the old stop (17/20 of the
   height-adjusted range) holds and it stands and fires. No new state (the switch is static).
4. **Numbers** (`tests/hill_probe.gd`, musketeers both sides, 180 s, men alive A / B, before -> after): crest one
   100 / 100 -> 81 / 27; cliff seed 4 one 100 / 100 -> 24 / 41, both 100 / 100 -> 44 / 46, ai 100 / 100 -> 25 /
   36; cliff seed 9 one 100 / 100 -> 47 / 7; flat, ramp, steep, step, crest both / ai and the other cliffs
   identical. `--check`: before FAIL (3), after PASS. Only part 1 or only part 2 (sight, path) leaves seed 4 one /
   ai standing.
5. **Checks.** `tests/determinism_test.gd`, `tests/lockstep_test.gd`, `tests/custom_battle_test.gd` PASS; the
   campaign pins of all four sets unchanged (auto-resolved battles).
6. **Open.** Not measured: the AI vs AI hill benchmarks and `tests/matchups.gd -- --only=terrain` (musket lines
   on hilly maps now close on hidden targets; the AI's own attack orders on them move too). A javelin or bolt row
   with an attack order on a hidden target follows the same rule (batteries still wait).

## 49. The tutorial's shield covers attacks (2026-10-30)

The guided first campaign shielded its human only from new wars (`CAI.tutorial_shield`), and Spain, at war with England
from the West start, attacked the emptied Sevilla la Nueva mid-lesson. Now the campaign AI plans as if a shielded human
had no reachable targets while the shield holds (`settings.tutorial`, the human, `turn < tutorial_turns`): the region
filter `CAI._shield(st, f, r)` (the story havens' filter) is true for the human's regions, which covers the attack
targets of `_move_grid` and the idle armies' fair chance, `_hunt`, `_raid6`, the landings (`cai_fleet.gd` `_landing`), the
blockades (`_blockade`) and the ferry's "nothing to do on this land" (`_stranded`); `_hunt` also skips the human's armies
wherever they stand, `_prey` and `_sorties` its fleets, the lane raid (`_raid`) any lane ending at its port, and an own
siege of its region (`_sieges_grid`) neither storms nor gathers. Defence is untouched: threats, danger, screens, stances
and the fall-back still count the human's forces as hostile. Rules side, so a passing AI fleet does not do by accident
what the planner refrains from: no AI blockade of the human's ports (`CSea.update_blockades`) and no AI lane raid on its
lanes (`CLanes.raiders`). Off without the setting (pins unchanged). Design and test: `docs/design/campaign_rules.md`
"The tutorial (as built)", "(2026-10-30) The shield covers attacks".

## 50. The harbour: canoes through the sea gate, the quay, the sortie (2026-10-31)

The AI side of docs/design/battle_sim.md "Amphibious units and the sea gate (as built)" (the native siege's later
entries, docs/STATUS.md "Native siege"). Code: `sim/siege_ai.gd` section "the harbour" (`_harbour_att`,
`_harb_storm`, `_harbour_def`, `_hsortie_target`, `_hsortie_landing`, `_quay_guard`, `_hsortie_unit`, `_harb_in`,
`_harb_stage`), `sim/ai_profile.gd` (`R_HARBOUR`). One rule, `R_HARBOUR` (293, from the unused 293-299; `KNOB_GAPS`
now 294-299): Easy 0, Average 1, Skilled 1. Without it (Easy) amphibious units fight on land as before and the
garrison ignores canoes afloat.

1. **Attackers by water** (`_harbour_att`, from `_attacker` before the class rules; mode `A_HARB` 40). An attacking
   amphibious unit (not on a wall, not in the pursuit) whose quay inside the sea gate (`_harb_in`: `HARB_IN` 24 m in
   from the passage's inside point, open ground of the inside's piece) is on another piece of ground than its own
   (walls between) but within its reach by water (`reach_u`) paddles at the run to a staging point on the water
   `HARB_STAGE` 45 m out beyond the passage (`u_ai_x` 1), waits there for the storm (the side's assault phase, or
   `HARB_WAIT` 60 s after it got there: `u_ai_y` 1, `u_ai_t`), then goes in through the passage to the quay (2).
   Landed (its anchor on the inside's piece: 3) it turns its skirmish off and storms as a ladder party does once over
   the wall: to the inside of the nearest shut outer gate, which its men unbar (`UNBAR_MEN` 4 for 15 s; the order
   rule's new branch for amphibious units inside), else into the town (`_storm`, mode `A_STORM`).
   **The open quay** (2026-10-31, the coordinator's follow-up): a West open town at walls 0-2 (the campaign's real
   Caribbean ports: a harbour fort beside an open quay) has no sea gate; its landing is the sim's `quay`
   (BattleSim `_find_quay`: beside the water inside the town, nearest the plaza, 60 m or more beyond the fort's
   bastions). Under `R_HARBOUR` the same rule runs with the quay as the landing: an amphibious attacker more than
   `QUAY_NEAR` 40 m from it paddles round (the amphibious graph makes the water within 60 m of the fort's bastions 4
   times dearer, so the canoes keep off its guns where a way allows) to a staging point `HARB_STAGE` out to sea from the
   quay, goes in, and has landed once its anchor is within `QUAY_LANDED` 25 m of the quay and it is not afloat; it then
   storms from the quay side (no shut outer gate: `_storm`). tests/harbour_test.gd: on west_port's map (walls 1) with
   the Miskito party the raiders land on the quay (tick 1210) and a defender holds it.
2. **The quay's company** (`_harbour_def` from the defender's `_army`; mode `A_HQUAY` 41). An enemy amphibious unit
   seen afloat within `HARB_SEE_R` 150 m of the sea gate's outside point (an open quay: of a point 10 m out from it),
   or landed on the sea gate's quay: one company of the
   town's reserve, plaza or gate stack (not on a wall, not amphibious) holds the quay, the nearest missile unit with
   ammunition first, else the nearest foot; one at a time (a new one once it is gone). It attacks attackers within
   `HARB_QUAY_R` 35 m of the quay (a missile company: within 90 % of its range, afloat ones too, shooting into the
   passage; foot never at men afloat: no blows on the water), else stands on the quay facing the sea gate (it is where
   the canoes land, so they land into it).
3. **The sortie** (`_harbour_def`, `_hsortie_unit`; mode `A_HSORTIE` 42). While the walls hold (every outer gate shut,
   no land stretch breached), each own amphibious unit in the town or on its walls (a wall company comes down by a
   stair first) sorties once: when an attacking missile unit or battery stands within `HSORTIE_R` 250 m of an outer
   gate (`_hsortie_target`: the nearest to it), it paddles out of the sea gate to the open cell beside the water on
   that target's ground nearest it, at least `HSORTIE_WALL_R` 60 m from the sea gate and `HSORTIE_IN` 20 m on toward
   the target (`_hsortie_landing`; `u_ai_y` the cell, `u_ai_x` 1), lands (2) and attacks that target (or the nearest
   attacker within `HSORTIE_FIGHT_R` 120 m, shooters and engines first) for at most `HSORTIE_FIGHT_T` 60 s from its
   landing (hit and run: then, or with nobody left, it breaks off and goes back in by the sea gate to the quay (3),
   fighting only attackers within 40 m once it is within 60 m of the quay). A unit that has sortied never sorties
   again (the mode stays).

Measured (tests/harbour_probe.gd, both sides AI at the skill, 8 seeds 8100-8107, 15-minute limit):
| Scenario | Average | Easy | Notes |
|---|---|---|---|
| `west_harbour_assault` (garrison 89 / 89 / 89 / 59) | 5 of 8 attacker wins | 0 of 8 (8 draws at the limit) | the canoes landed in every Average battle (116-161 s) and unbarred a gate in 6; the quay's company posted at 27 s; one man a company more or less moves 2-4 battles (87-90 a company pooled: 21 of 40); the battle turns on whether the torch raiders' fire pots burn the main gate in the first 90 s. Easy: no fire-pot order, no canoes by water, warriors cannot hack a walls-3 gate: nobody gets in |
| `tayasal` (the Itza at half strength, the sortie's hit and run) | 3 of 8 (seeds 8108-8115: 4 of 8; 7 of 16) | 7 of 8 | the sortie lands in every Average battle; the garrison was not the lever (the Itza at 40-60 % 0-3 of 8, the Spanish 25-30 % stronger 0-2 of 8, walls 1 1-2 of 8) |

**The harbour assault's Easy** is 0 of 8, every battle a draw at the limit, by design: Easy has no `R_HARBOUR` (its
canoe raiders fight on land), no torch raiders' ability order (`R_TORCH_GATE` 0) and warriors cannot hack a walls-3
gate, so nobody gets in and the garrison never sallies.

**Tayasal's sortie, tuned** (the coordinator's follow-up, 2026-10-31; 8 seeds 8100-8107 on Average unless noted; the
Itza at half strength):

| Sortie variant | Spanish wins |
|---|---|
| as first built (nearest shooters or guns, fights to the end) | 3 of 8 (8 of 24 over 8100-8123) |
| the guns only | 1 of 8 |
| landing 120 / 200 / 300 m or more from its target (seen and met) | 3 / 3 / 2 of 8 |
| one company sorties a battle | 3 of 8 |
| one company, landing 200 m off | 3 of 8 |
| hit and run 15 / 30 / 45 s, then back in | 6 / 6 (8108-8115: 5) / 6 (8108-8115: 4) of 8 |
| hit and run 30 s, guns only / one company / landing 200 m off | 6 / 6 / 6 of 8 |
| **hit and run 60 s (kept: `HSORTIE_FIGHT_T` 600)** | **3 of 8 (8108-8115: 4 of 8; 7 of 16, 44 %)** |
| hit and run 75 / 90 s | 6 / 6 of 8 |

The kept setting is the one in the band over 16 seeds (44 %); on the standard eight it is 3 of 8. The curve is noisy
(15-45 s and 75-90 s both give 6 of 8): what decides a battle is whether the Spanish shooters break when the canoes
land in their flank, and a sortie that stays in the fight longer than a minute is cut down before it can come back.

## 51. The torch raiders batter a palisade stretch (2026-10-31)

The open item of note 45 ("the AI batters only the attacked gate, never a stretch"). Code: `sim/siege_ai.gd`
`_torch_stretch` (with `TORCH_AT_R` 15 m, `TORCH_WAIT` 400 ticks) and its call in `_torch_gate`; under `R_TORCH_GATE`
(292: Easy 0, so Easy is unchanged; no new knob). No new sim state.

- **When.** In the approach, the attacked gate shut, on a walls-1 ring (`BattleSim.mbat_palisade`: stone takes nothing
  from the melee batter, so walls 2-3, the citadel and the West fort never qualify), a melee batter unit (the torch
  raiders) leaves the gate to a stretch when the gate already has a batterer (the side's ram still able to work it,
  `_ram_avail`, or another batter unit sent at it: of two at the gate the lower index keeps it), or the gate burns
  (`g_burn`: the fire finishes it), or the unit has stood within 15 m of the gate's face 40 s (its `A_HACK` mode's
  `u_ai_x` holds the tick it got there) with no hit on the gate in the last 40 s.
- **Which stretch.** The standing palisade stretch nearest the gate (middle within `BATTER_GATE_R` 100 m, a way
  through it once breached, its outside point on open ground, not facing the sea) that no other unit of the side is
  battering (`u_gtarget` -2 - stretch: a battery or another batter unit): one unit a stretch, as the ladder parties.
  The batter's Use now at it (the men go to its outside face, `_update_mbat`: 80 a blow, 1,200 at walls 1). A stretch
  the unit already batters stays its own (the choice is sticky through the order, not memory).
- **After.** The breach is an entry (note 35): the assault begins and the unit storms through it as through the gate
  (`_torch_gate` is the gate party only in the approach). With a ram on a palisade the torch raiders now batter a
  stretch where before they were only grenadiers; with no free stretch they keep the old rule.

Measured (`tools/balance` `native_walls_miskito`, now the six walled native towns: Tayasal, Cabo Gracias, Natchez,
Choctaw, Valladolid, Darien x walls 1-2 x 16 seeds, the West set defending): attacker wins walls 1 / 2 16 / 5 -> 18 / 5 %
(within the interval); at walls 1 a stretch breached in 16 of 96 battles (none before), every one before the gate,
the gate's median fall 54 -> 65 s (one company fewer at it); walls 2 identical (stone). `native_walls_itza`
identical (no torch raiders). Test: `tests/roles_sim_test.gd --only=native` (two torch raider units at a walls-1
oppidum gate: the second batters a stretch, breached before the gate falls).

## 52. The natives buy their new vessels and raise the Canoe yard (2026-11-01)

The native vessels (`docs/design/campaign_rules.md` "Native vessels (as built, 2026-11-01)"). Code: `campaign/cai_fleet.gd`
`_build`, `_ship_value`, `_yard_up`; data `west_ships.gd` `AI_YARD_UP` (["itza", "miskito"]); the sea AI's dugout think in
`sim/sea_sim.gd` (`docs/design/sea.md` "The dugouts close and board"). No new state.

- **What to buy.** `_ship_value(row, transport, f)`: a transport is valued by places then guns, as before; a warship by guns
  then places, as before, except for the factions of the pack's `AI_YARD_UP`, valued by the formula's power at full strength
  (`CFleet.ship_power`) then places. The dugouts board rather than shoot: by guns the war canoe (2) would beat the piragua
  (1) forever. Everyone else (the Europeans, the Brethren, Rome's galleys, all `guns` 0) keeps the old order, so the Rome pins
  and the Easy golden do not move. Fire rows are still skipped (the fire canoe as the fire ship).
- **The yard.** For an `AI_YARD_UP` faction, before buying, `_yard_up` raises the Shipyard of its best port (the ports sorted
  as before: yard level, capital, value) a level, instead of a ship that turn, when a row of its people (not a fire row,
  `CDip.ship_why` passing, `CData.ship_yard` above the port's level) is worth more in the turn's mode than the best its yards
  build now (money aside), and `build_info` allows the level within the treasury above half the reserve (the natives' money
  above the whole reserve rarely reaches a level 2's 1,000; with the whole treasury the Miskito were eliminated in 10 more
  seeds of 72 at format 6). It runs also when the money above the reserve is gone (the rest of `_build` then stops). A native
  Canoe yard needs no town or city (`YARD_ANY_LEVEL`, the owner's call), so the Miskito's village ports reach 2 and 3.
- **Fire canoes in battle.** Nothing new: the battle AI's fire-ship play (M_FIRE) keys on `ST.is_fire`.

Measured (West campaign sim, 72 seeds x 60 turns, format 6 / 10, before the native vessels -> as built): Itza alive 65 / 60
-> 62 / 63, Miskito 60 / 65 -> 66 / 63; best Canoe yard 3 at the end: Itza 0 -> 15 / 15 seeds, Miskito 0 -> 8 / 4 (Canoe yard 2:
Miskito 1 / 3 -> 46 / 46); launched: Itza piraguas 41 / 41, great canoes 8 / 10, war canoes 790 -> 388 / 540 -> 349; Miskito
piraguas 15 / 15, brigantines 6 / 2, sloops 378 -> 348 / 340 -> 281. Test: `campaign_test` `_native_vessels` (the AI Itza at a
Canoe yard 3 with no fleet order a great canoe; at a Canoe yard 1 in a town they raise it to 2; a European faction never
raises by this rule; a Miskito village raises its Canoe yard to 3, an English village's Shipyard 2 needs a town).

## 53. Dugouts board as a pack: the target and the join (2026-11-01)

The joint boarding (`docs/design/sea.md` "Joint boarding by dugouts (as built, 2026-11-01)"). Code: `sim/sea_sim.gd` `_think`
(the target scan), `_join_of` (the gate), `_contacts`, `_steer` (M_BOARD). New hashed state `s_join`, `s_jw`, `k_jl`, `k_dw`
(the sim's, no AI state).

- **The target (the pack).** Note 52's target (the fewest defenders) sent the dugouts one by one at the war canoe while the
  gunned ships cut their crews. Now a dugout scores each enemy by her broadside weight (`guns` x `gun`: the brigantine 35, the
  sloop 16, the war canoe 3) and admits her when the side's free dugout pack (every dugout of the side sailing, not grappled,
  not a fire row or lit, plus those already grappled to her) has a boarding strength of `CANOE_PACK_PCT` (100) % of her
  defenders with the deck bonus; the heaviest admitted broadside wins, ties by distance (score `d - weight x 100000`); none
  admitted: the fewest defenders as before (scored above every admitted ship). Every dugout of a side computes the same pack,
  so they converge on one ship.
- **The decision.** She boards at `CANOE_BOARD_PCT` 100 % of her strength, with friends boarding or grappled to that ship
  counted in (`my_b`), as before. A grappled target no longer ends her run: M_BOARD steering dropped any target with `s_grap`
  set, and `_contacts` would not grapple it; now both pass when `_join_of` finds a melee of her side on that ship (the target
  a defender, its first boarder of her side with `k_on`, no outside melee), and in reach she joins instead of grappling. Any
  other ship (a European, a galley) still drops a grappled target.
- **Measured** (`SeaChecks`, 8 seeds, both sides AI, canoe wins, canoes_eq / canoes): before 1 / 5 (33 boardings at equal
  gold); joining alone (the share left at 75) 1 / 8; joining + `CANOE_DECK_PCT` 95: 2 / 8 (25 boardings, 6 joins), with
  `CANOE_BOARD_PCT` 60 / 80: 2, 130: 1 (kept at 100); + the pack's target (as built): 3 / 5 (27 boardings, 5 joins). Before the
  pack's target the canoes took the war canoe first and the sloop's and brigantine's guns cut their crews until they struck
  (crew under 18 % with an enemy near) or were boarded in turn.

## 54. The AI reckons with the zones it stands in (2026-11-02)

The open item of the attack fixes (`docs/design/campaign_rules.md` "(2026-11-01) Two armies attacking one", cause 5, and
"(2026-11-02) The AI reckons with the zones it stands in"; the owner: "Let's update the AI's distance estimates"). Code:
`campaign/cai.gd` `_zm_of`, `_toward`, `_fall_back`; `campaign/crules.gd` `_move_targets6`.

- **What read the old lock.** Two pickers test cells against the side's enemy zone mask (`cx["zone"]`): `_toward`'s waypoint
  (the farthest cell about a turn down the destination's distance field outside every zone) and `_fall_back`'s refuge
  (Skilled, `SK_SAFE_WIN`). `plan_path` now lets an army inside an enemy zone move within it (`CRules.held_zones`), so for that
  army the shared mask refused cells its march can reach.
- **The change.** `_zm_of(st, f, a, cx)`: the side's cached mask, or, when army a stands inside an enemy zone, a copy with the
  zones it stands in opened by `held_zones` (the cells next to that enemy army and every other army's zone stay closed), the
  same mask `plan_path` searches. `_toward` and `_fall_back` use it. The gathering point of `_attack6` keeps the side's mask
  (all the gathering armies must be able to end there). `_move_targets6` (the view's move targets, the test bots) opens the
  zones it stands in as `reach6` does.
- **What did not need it.** The turn estimates (`eta`, `site_dist`, the static settlement fields) and the octile ranges of the
  hunt, rally and support never counted zones; attack, hunt, siege and relief orders aim at settlements or enemy armies, whose
  zones `plan_path` opens for the march.
- **Measured** (campaign sim, 72 seeds x 60 turns, Rome and West, formats 10 and 6): 287 of 288 final hashes equal; the one
  that differs (Rome format 6, seed 6236) keeps its eliminations (battles 76 -> 64). Eliminations, battles a seed, field
  battles and armies trickled in are unchanged per pack and format; the pins and goldens hold. A free AI field army stands in
  an enemy zone at planning time in about 1 army-turn of 1,000 (format 10, 6 seeds a pack: 6 Rome, 15 West), and in 12 seeds of
  each pack and format neither picker met one (the opened mask was never built): those armies are planned elsewhere (attack,
  hunt, siege) or hold. The AI was hardly ever trapped by its own reckoning; the march itself was (fixed 2026-11-01). Test:
  `campaign_test` `_grid_two_army_attacks` (the AI's mask opens the cell two from the enemy, keeps the cells next to it).
## 55. Archers close in to lob over a wall (2026-11-02)

(Numbered 55, not 54: another change may take 54 in parallel.) The battle rule is `docs/design/battle_sim.md` "Lobbing
over a wall (as built, 2026-11-02)": an arcing soldier weapon from the ground at men on the ground across a standing wall
or a shut gate reaches `ARC_OVER_WALL_PCT` (60) % of its range. The AI needed no rule of its own, only the cut range where
it reads a range:

- **Through `range_vs`.** Every AI test that goes through `sim._in_range` or `sim.range_vs` (the battle AI's hold-fire
  scan, the grenade siege scan, `_anyone_in_range`, the artillery scans, which the rule leaves alone)
  now sees the cut range for a target behind a wall, and so does the attack order's closing in the sim (`stop` 85 % of
  `range_vs`): a missile unit sent at a man behind the wall walks in to the lob's reach, or as near as its ground goes.
  Fire at will at a post shoots the walk (not cut) and men behind the wall only within the lob.
- **The defenders under fire** (`siege_ai._df_safe`, `S_DEF_FIRE`): a spot behind a wall past a field shooter's lob
  (`mrange x ARC_OVER_WALL_PCT / 100 + DF_PAD`, `sim.lobber`, `sim.wall_cross_at`) is safe, so the reserve no longer
  falls back further than the shooters can reach.
- **Not changed:** the besiegers' archer post (`_att_missile`, `S_COVER_OUT` 110 m off the attacked gate): from there
  the walk is in reach, the street behind the wall is not. Measured (8 seeds, the owner's case, both AI): the attacker
  wins 8 / 8 before and after, 6.3 -> 6.4 min; the attacking archers kill 151 -> 138 men (on the wall 84 -> 88, behind
  it 67 -> 50). A post that walks in to lob at the men behind the gate once the walk is clear is open.
- **Equal-force sieges** (`rome_walls`, 8 seeds, 144 battles): attacker wins 71 / 40 / 31 % -> 75 / 50 / 38 % (walls 1 /
  2 / 3), no cell beyond its interval.

## 56. Covering archers walk in to lob over the wall (2026-11-02)

The open of note 55: the besiegers' archer post (`_att_missile`, `S_COVER_OUT` 110 m off the attacked gate) reaches
the walk, not the men on the ground behind the wall, and the archers never left it, so the AI's own sieges lost reach
against defenders standing inside. The rule: siege_and_towns.md "Archers walk in to lob over the wall (as built,
2026-11-02)".

- **When.** In the approach (the attacked gate shut), every unit think (1 s), for a covering missile unit that lobs
  (`sim.lobber`) with ammunition and not in a melee: no enemy unit on the walls within its range (`mrange`) of its
  post. A man on the walk there means the post as before (it shoots him from there); the post is the reference, not
  where the unit stands, so the decision does not flicker as it walks.
- **Where** (`SiegeAI._lob_stand`): the nearest enemy on the ground behind the wall (from the post; seen, not in a
  building, not on a ladder or tower; the line crosses a wall or a shut gate) at `S_LOB_PCT` % of `range_vs` (the lob
  cut and heights counted) on the line from it to the post, half the post's spread to the side; off the gate's axis
  by `LOB_LANE` 15 m out to `S_COVER_OUT` (the ram and the hackers), then within `LOB_MAX_PCT` 95 % of the lobbed
  range or none; open ground the post reaches (outside); not within `LOB_EQ_R` 20 m of the side's planted ladders or
  poles or its siege towers; not in the reach (`range_vs` + `DF_PAD`) of enemy wall shooters with more than half the
  men of all the side's lobbers (`LOB_ODDS` 2). Any of these fails: the post. A re-manned walk or a target gone too
  deep sends the unit back to the post the next think.
- **Knob** `S_LOB_PCT` (294; Easy 0 = keep the post, a deliberate mistake; Average and Skilled 85, the attack order's
  closing). The constants are `LOB_*` in sim/siege_ai.gd. No new state; the defenders are unchanged (their archers
  stand on the walk, which the lob does not cut; a defender lobbing out from the ground is rare in their layout).
- **Measured** (8 seeds, `lob_probe` from note 55: walls-2 castrum, 5 archers 80 + 4 foot with ladders and a ram
  against 2 archers 80 + 3 spear, both AI; "behind" the attacking archers' kills of men on the ground):

| case | attacker wins | min | archers' kills (walk / behind) | archers' losses | wall archers' kills / losses | forward share of approach |
|---|---|---|---|---|---|---|
| the probe, before | 8 / 8 | 6.4 | 138 (88 / 50) | 219 | 209 / 137 | 0 |
| after | 8 / 8 | 6.2 | 141 (89 / 52) | 218 | 209 / 137 | about 1 % (0-4) |
| wall archers 30 men a unit, before | 8 / 8 | 6.1 | 98 (35 / 64) | 60 | 52 / 52 | 0 |
| after | 8 / 8 | 5.1 | 231 (30 / 201) | 72 | 57 / 48 | about 48 % |

  In the owner's case the walk stays manned until the ram breaks the gate (4.2 min), so the archers keep the post;
  where the walk is cleared they go in and kill three times as many men behind the wall for 12 more losses.
  `rome_walls` (8 seeds, 144 battles): attacker wins 75 / 50 / 38 / all 54 -> 71 / 48 / 40 / 53 % (walls 1 / 2 /
  3), no cell beyond its interval. Open: men in buildings are not lobbed at; the stand is from the unit's middle.

## 57. A docked fleet meets a landing at the sortie's odds (2026-11-02)

The rule is docs/design/campaign_rules.md "A landing is contested, and a fleet puts to sea when its port falls (as
built, 2026-11-02)": a landing in a region whose port holds a docked fleet at war with the landing side is a sea battle
first. The one AI decision it adds is the defender's: `CAIFleet.fights_landing(st, g, pd, pa)` (item 11 of the
`cai_fleet.gd` header), called by the rules (`CFleet._contest`) for an AI faction's docked fleets. They come out when
their power there with the port's guns (`pd`, `CFleet._side_power` as the defender) is at least `SORTIE_ODDS_PCT` % of
the landing side's (`pa`: the transport and the friendly fleets in its zone); else they stay behind the mole and the
troops land (and, if the town then falls, the fleets put to sea). No new knob: the sortie's odds (Easy 0 = never, a
deliberate mistake; Average 110; Skilled 100). The landing side's AI is unchanged: its landings already skip a beach
whose approach lies in an enemy zone (`_approach`) and a route that fleets at war, docked ones included, outgun beyond
`FERRY_ODDS_PCT` (`_ferry_safe`).

## 58. The defender's choice at a landing (2026-11-05)

The rule is docs/design/campaign_rules.md "The defender's choice at a landing: fight at sea, stand off, support the
shore (as built, 2026-11-05; the stand-off only)": a human defender of a contested landing may now stand off (no sea
battle, the troops land, the ships stay in port). The AI defender's choice was already this one and is unchanged: note
57's `CAIFleet.fights_landing` at the sortie's odds (`SORTIE_ODDS_PCT`: Easy 0 never fights, Average 110, Skilled 100);
below them the fleet stays behind the mole, which is the stand-off. No new knob, no change to any AI decision, so the
pins and goldens do not move. The third choice, support the shore, is designed and not built (battle_sim.md "A fleet
at the shore (design and cost, 2026-11-05; not built)"); when it is, the AI's knobs it would add: the defender's
support when its fleet is below the sortie's odds but has guns or crews to give, the defender's crews landing when the
walls are stormed or the guns have no targets, and the attacker's transports landing their crews by the assault's odds.
## 59. The West's tribes seldom fight each other (2026-11-05)

The diagnosis and the measure are in docs/design/campaign_rules.md "The Itza after the sea rules (as built,
2026-11-05)": after the 2026-11-02 sea rules the two tribal AIs were each other's chief killers (the Miskito took the
Itza's last town in 26 of their 49 deaths over 288 campaigns, the Itza the Miskito's in 14 of 27), though the Itza and
the Miskito never met in 1650 (Spanish Yucatan, Honduras and Nicaragua lie between). Code: `CAI.diplomacy` (the
opportunistic war) and `CAI._unwise_war` (Easy's mistake); data `west.gd` `AI_KIN` ([["itza", "miskito"]]),
`CData.AI_KIN`, `CData.kin(f, g)`. No new state.

- **The rule.** An opportunistic war on a faction of the AI's own kin group (`CData.kin`) needs `KIN_WAR_PCT` % of the
  ratio it would need against anyone else (`WAR_RATIO`, or `WAR_RATIO_BUSY` when the target is already at war, after
  the trade partner's `WAR_PARTNER_PCT`); 0 never; 100 as anyone else. Above 100 the unwise-war mistake never picks
  kin. A call to arms against kin is answered as before (none was seen in the measure), and a player may make war on
  either tribe as on anyone. Rome has no `AI_KIN`, so nothing changes there (its pins, `ROME_20` and the goldens did
  not move).

| Knob (`cai_profile.gd`, id `SK_SUPPORT + 56` = 131) | Easy | Average | Skilled |
|---|---|---|---|
| `KIN_WAR_PCT` | 100 (as before) | 200 | 200 |

Measured (`campaign_sim`-equal probe, West, 144 seeds (seed indices 0-71 and 100-171) x 60 turns, all Average; the
Itza / Miskito eliminations): HEAD f6 18 / 19, f10 31 / 8; `KIN_WAR_PCT` 0 (never) f6 3 / 3, f10 12 / 5; 200 (as built)
f6 4 / 5, f10 12 / 6. Kin wars at 200: Miskito on the Itza 31 -> 3 (f6) and 38 -> 3 (f10), the Itza on the Miskito
85 -> 11 and 5 -> 0. No European faction or the Brethren moved beyond the two intervals combined. Test:
`campaign_test` `_ai_kin`.
## 60. Poles and a ram storm the fort; the campaign AI reads the walls (2026-11-05)

The owner: "I like poles and ram, that fits our actual use case and will match what the player would be doing." The
rules: docs/design/siege_and_towns.md "Poles and a ram storm the fort (as built, 2026-11-05)" (the battle) and
docs/design/campaign_rules.md "The formula knows the fort and the walls, and the natives' weights refit (as built,
2026-11-05)" (the campaign).

- **The edge by kit** (`SiegeAI._fort_need`, used by `_fort_choice` at the first think and by `fort_press`): guns of
  the side's own `S_FORT_GUN_PCT` (297), a ram `S_FORT_RAM_PCT` (296; with `S_FORT_BATTER` (299) a gate batterer or
  fire missiles against a walls-1 fort's timber gate count as a ram), ladders or scaling poles `S_FORT_POLES_PCT`
  (295): % of the defenders' men x cost, the lowest of the kits the side has; no kit, no storm. The fort's
  `FORT_STORM_PCT` 35 % share still storms with any kit.
- **Pressing on** (`S_FORT_PRESS`, 298; `SiegeAI.fort_press`, called once by `BattleSim._update_capture` when the
  plaza falls): an AI side that storms the fort keeps the battle going past the town (the sim decides it when the
  fort is cleared, the storm gives up or time runs out, the attackers' either way); one that chose the town weighs
  the storm again against the fort's garrison alone at its kit's edge. A human side never presses.
- **Knobs.** Easy 250 / 250 / 250, press 0, batter 0 (the slice 2c rule exactly, a deliberate mistake: its storms
  still end at the plaza); Average and Skilled 180 / 150 / 120, press 1, batter 1. The ids 295-299 were a knob gap.
- **The campaign AI** (`campaign/cai.gd`): the storm odds read the walls' hard rule (`CBattle.walls_shut`: stone ring,
  no breach, no ladders, poles, ram, tower, guns, batterer, grenades or fire): `_odds_on` on arrival (kit 0) and
  `_storm_win` with the siege's kit give 0 % when there is no way in, so the AI sits down before such walls instead of
  storming on arrival, and one army alone may begin the siege (`_attack6`: `can_siege` also when the walls are shut;
  the siege brings ladders after a turn). The fort town's rule is not read by the AI's odds (a won battle there still
  beats the garrison and keeps the siege).
- **Measured**: the fort storm table in siege_and_towns.md; the campaign in campaign_rules.md.

## 61. The tribes' ambitions (2026-11-05)

The rule and the measure are in docs/design/campaign_rules.md "The tribes' ambitions (as built, 2026-11-05)". The owner:
"can we give the tendency for the tribes to strike a treaty and desire to move north along the coast? While the Miskito
want to move south to push out the Terra Firma?"

- **Code:** `CAI.diplomacy` (`_kin_treaty`, the war order), `CAI.why` (the kin's trade), `_move_grid` (target values,
  the idle pick, the frontier march), `_build` (`_amb_build`). Helpers: `ambition_next`, `ambition_foe`,
  `ambition_pct`, `_amb_value`, `_amb_target`. Test switch: `CAI.no_amb_march`.
- **Data:** `west.gd` `AI_AMBITION`, `CData.AI_AMBITION`, `CData.ambition_regions(f)`, `CData.ambition_treaty(f)`.
  No new state.

The parts:

- **The treaty.** An AI whose treaty is "kin" proposes a trade agreement to each kin faction it is at peace with, every
  turn (a human kin on turns 1, 11, 21, ...). It never proposes an alliance. An alliance at format 10 took the Miskito
  out of England's side in the war sums (`bloc_strength`) and out of the calls to arms (`_call_allies`), which opened
  Belize to the Itza: England was eliminated in 11 of 144 campaigns against 2. The kin answers by `why()`: no strength
  test, and the trust floor lowered by `AMB_TREATY`. The kin rule (`KIN_WAR_PCT`, note 59) is what stops the kin wars.
- **The war.** `ambition_foe(st, f)` is the holder of the first list region that is not f's, not independent, not kin
  and not friendly. It is tried first in the opportunistic war loop, its chance x `AMB_WAR_PCT` %. Everything else is
  as for any war: the ratio, `WAR_CALM_TURNS`, `WAR_COVER_PCT`, one war at a time, the kin rule.
- **The targets.** `ambition_pct` gives `AMB_TARGET_PCT` x (n - i) / n for the list's i-th region. The attack plans'
  value and the idle armies' pick read `_amb_value`. The rest of the free armies march to the frontier region facing
  the first list region not friendly (`_amb_target`), when one is in reach; else to the nearest frontier, as before. An
  army already on the frontier, or held, stays.
- **The spend.** `_amb_build`: a War lodge 2 at the first centre with a Barracks, once it is a town; then a Shipyard 2
  at the first port when the next region lies on a landmass where f holds nothing. It is paid before the build-up when
  the treasury stays at (100 - `AMB_SPEND_PCT`) % of the reserve or more.

| Knob (`cai_profile.gd`) | id | Easy | Average | Skilled |
|---|---|---|---|---|
| `AMB_TREATY` | `SK_SUPPORT + 57` = 132 | 0 | 25 | 25 |
| `AMB_TARGET_PCT` | 133 | 0 | 100 | 100 |
| `AMB_WAR_PCT` | 134 | 0 | 150 | 150 |
| `AMB_SPEND_PCT` | 135 | 0 | 50 | 50 |

**Measured** (144 seeds x 60, West, format 6 / format 10):

- **Eliminated, before -> as built:** Itza 4 / 12 -> 6 / 2, Miskito 5 / 6 -> 8 / 3, England 9 / 2 -> 10 / 1, Brethren
  18 / 38 -> 29 / 24.
- **The treaty:** struck in every campaign, on turn 3.
- **The Miskito:** Veraguas captures 63 -> 161 / 28 -> 124, Portobelo 39 -> 61 / 24 -> 41.
- **The Itza:** at format 10, Belize and Merida did not move.
- **The Brethren's rise at format 6** follows `AMB_TARGET_PCT`: 29 as built, 21 at 0 or at 50 (at 50 the Miskito's
  gains vanish). `AMB_SPEND_PCT` 0 gives 28 and the frontier march off gives 30. Accepted.
- **Rounds:** the alliance with `AMB_WAR_PCT` 300, 150 and 100, then trade at 150 (kept).

Test: `campaign_test` `_ai_ambition`.
## 62. The ships off the shore in the land battle (2026-11-05)

The rule is docs/design/battle_sim.md "A fleet at the shore (as built, 2026-11-05)" (the owner: "let's do the full
build of the shore and landing"). Code: `sim/ship_ai.gd` (`ShipAI.think`), handed every ready unit of an AI side that
is a ship's hull or her landing party by `BattleAI.think` and `SiegeAI.think` before their own rules; it queues only
the orders a player can give (fire at will, an attack, ORDER_LAND) and its memory is the hashed `sh_idle`.

- **The guns.** Fire at will on; with `SH_FOCUS` an enemy ship in reach first, then an enemy battery (nearest first,
  with a line of fire: the tower engines' `_tower` scan), else at will.
- **The defenders' landing party** goes ashore (ORDER_LAND) with `SH_LAND_DEF` once the town is stormed (an attacker
  not afloat in its streets or on its walls) or her guns have had nothing to shoot at for `SH_IDLE_T` (a hull with no
  guns: at once). Landed after the army's first think, `SiegeAI` classifies it as any defender (it holds where it
  landed, the quay: `A_RESERVE`).
- **The attackers' landing party** goes ashore once its side storms (`SiegeAI` `SP_ASSAULT`; the field: `P_ENGAGE`)
  while the side's strength (men x cost, the hulls and the parties aboard left out) is under `SH_LAND_ATT_PCT` % of the
  enemy's. Ashore, `SiegeAI` sends it storming for the plaza from where it landed (`A_STORM` with `u_ai_x` 1: by the
  nearest way, not round to the army's street mouths); the harbour's canoe rules (`_harbour_att`, the sortie) leave the
  parties alone.
- **Nobody walks at a hull.** The field AI's nearest-enemy picks (`_nearest_enemy`, `_nearest_not`, `_nearest`) and the
  siege AI's (`_nearest_attacker`, `_nearest_outside`, `_storm`) skip hulls; the order rule refuses an attack order at
  one from a unit with nothing to shoot.

| Knob (`sim/ai_profile.gd`, ids 340-343; `N_KNOBS` 344) | Easy | Average | Skilled |
|---|---|---|---|
| `SH_LAND_DEF` | 0 (never) | 1 | 1 |
| `SH_IDLE_T` (ticks) | 600 | 600 | 450 |
| `SH_LAND_ATT_PCT` | 0 (never) | 300 | 400 |
| `SH_FOCUS` | 0 | 1 | 1 |

Easy keeps its crews aboard and fires at will (a deliberate mistake). Measured: battle_sim.md "A fleet at the shore (as
built, 2026-11-05)"; tests/shore_test.gd (Average lands, Easy never does).

## 63. The campaign AI supports the shore (2026-11-05)

The rule is docs/design/campaign_rules.md "Support the shore (as built, 2026-11-05)". Two choices, both through
`CAIFleet.supports_shore(st, g, attacker)`, called by the rules:

- **The defender** (`CFleet._contest`): a docked fleet that stays behind the mole at a landing (below note 57's sortie
  odds) supports the land battle for the region with `SHORE_DEF` (event how `support`), else it only stays in port.
- **The attacker** (`CFleet.land`): a transport that has landed troops on an enemy's port town (within `SHORE_CELLS` of
  it) stays off the beach for the battle with `SHORE_ATT`.
- **Holding.** A fleet supporting the shore holds its place (`CAIFleet.act`: marked used before the flota, transport,
  landing, sortie, attack, blockade and home jobs; only a hurricane's run comes first), for this turn and the next, and
  on while the town it lies off is besieged (the assault).

| Knob (`campaign/cai_profile.gd`) | Easy | Average | Skilled |
|---|---|---|---|
| `SHORE_DEF` (`SK_SUPPORT + 61`) | 0 | 1 | 1 |
| `SHORE_ATT` (`SK_SUPPORT + 62`) | 0 | 1 | 1 |

Measured: campaign_rules.md "Support the shore (as built, 2026-11-05)".

## 64. Units on a move go round the enemy (2026-11-06)

The rule is docs/design/battle_sim.md "Paths clear of the enemy (as built, 2026-11-06)" (the owner: "pathing, the
units should take a path that doesn't cross them in front of the enemy or through the enemy to get into a building
or to a location"). It lives in the sim's path planning (`_rt_plan`, called by `_plan_path` on maps with a street
graph and by `_rt_point` on the open field), so a player's unit and an AI's unit on a move order plan alike; the AI's
part is two knobs, the detour a unit of an AI side accepts (`_rt_pct`):

| Knob (`sim/ai_profile.gd`, ids 344-345; `N_KNOBS` 346) | Easy | Average | Skilled |
|---|---|---|---|
| `RT_DETOUR_PCT` (field battles: % longer than the plain way; twice that round an enemy's box in the way) | 0 (the plain way) | 50 | 50 |
| `RT_TOWN_PCT` (the same in a settlement battle, the siege AI) | 0 | 0 | 0 |

A player's units take `RT_DETOUR_HUMAN` 50 everywhere (scenario key `rt_human`, a test's set piece only). Easy walks
the plain way across the enemy's front (a deliberate mistake). `RT_TOWN_PCT` is 0 at every skill by measurement: the
siege AI's storm and plaza moves are laid out by street mouths, and letting them slip round the defenders by the side
streets moved west_walls walls 0 from 52 to 71 % attacker wins (16 towns x 8 seeds; the separation alone 52 -> 52);
going round in towns stays the players' (the owner's ask), and a later siege-AI pass may raise it.
What reads the enemy term: only the plan of a unit under a move order (a point, a building's door, a wall's stair),
when the order is given, when its path is planned again (a gate or the goal changed) and every `RT_REPLAN` 20 ticks
when an enemy's box has come across the rest of its way. The AI's own estimates do not: `BattleAI` and `SiegeAI`
read no path (their distances are straight lines and the arrival checks the anchor), the street graph's distance
tables (`_dist_table`, the stragglers' `_via_goal`) and `route_to` (the view's route preview and refusals) are the
plain graph as before, so the AI's choices do not change with the term; only the way its units walk does. Attack
orders, pursuit, routers, withdrawals, the siege gear's carriers, units on a wall, a stair or a ladder, in contact,
in a building or afloat (the amphibious planner) plan as before.
## 65. Buildings block a flat shot: the target with a line, cover facing the enemy (2026-11-06)

(Numbered 65: 60-64 are taken or claimed in parallel.) The battle rule is docs/design/battle_sim.md "Buildings block a
flat shot (as built, 2026-11-06)"; the sim's attack order walks round a house to a spot with a line of fire
(`fire_spot`, `LOF_WALK` 40 m), so the AI needs only to choose well:

- **`LOF_PICK`** (350). A flat-weapon missile unit on a map with houses or walls (`lof_pick`): `_mis_close` (the
  musket lines and an army with no line, once engaged) keeps its attack target while it has a line of fire to it;
  otherwise it takes the nearest enemy in sight it has a line to (`sim.lof_units`, tried only for enemies nearer than
  the best so far), and an enemy behind a house only when none has a line (it keeps the one it has: the sim walks
  round). The order is given again only when the target changes. Focus fire (`_sk_focus`) skips targets with no
  line on maps with houses too (before, only on hilly maps).
- **`COVER_DIR`** (351). Cover troops' spots in the line (`_cover_spot`) take the best `sim.cover_rating` against
  their front (heavy before light, the first in the fixed order), the same evaluation as the order preview's cover
  mark, instead of any cover round the man (`_cover_at`), which put men on the enemy's side of a house.

| Knob (`sim/ai_profile.gd`, ids 350-351; `N_KNOBS` 352, gap 344-349) | Easy | Average | Skilled |
|---|---|---|---|
| `LOF_PICK` | 0 (the nearest, as before) | 1 | 1 |
| `COVER_DIR` | 0 (any cover, as before) | 1 | 1 |

Easy shoots at the nearest and takes any cover (deliberate mistakes). Measured: battle_sim.md (as built).

## 66. The siege AI reads lines and cover (2026-11-06)

(Numbered 66: 64 may be taken by the movement pass.) The battle rules are docs/design/battle_sim.md "Cover and line of
fire, second pass (as built, 2026-11-06)". Every settlement battle runs `SiegeAI.think` instead of `BattleAI.think`,
so note 65's `LOF_PICK` and `COVER_DIR` never ran where the houses are (the evaluation: knobs on and off identical over
4 open-town seeds), and defending musket lines held their posts with enemies in reach and no line for minutes
(1,413 unit-seconds in its probe, 568 before the first pass).

- **`S_LOF_PICK`** (360). A storming flat-weapon missile unit with shot left (`_storm`'s target pick) counts a
  defender within its range it has no line of fire to (`sim.lof_units`) `S_LOF_PUSH` 40 m farther: the ones it can
  hit first, a hidden one only when no other is near (then the sim's attack order walks round for a line).
- **`S_COVER_DIR`** (361). A West skirmisher's strongpoint (`_sp_cover`) adds `SP_COVER_DIR_W` 10 per step of the
  cover facing its street mouth (`sim.cover_rating_front` for its troop type: heavy 2, light 1) to the cover cells round
  it.
- **`S_LOF_STEP`** (362). A defending flat-weapon missile unit at its post (`_reserve`, `_lof_step`) with attackers it
  sees in its reach: with a line at one of them it shoots from where it stands; with none it steps to the best fire
  spot (`sim.fire_spot`, the scored search) within 12 m of its post, facing the nearest, looked for at most every 3 s;
  while attackers are in reach it does not go home; once they are gone it does. Attackers inside the town (the old
  "shoot from the post") and in the field before it both count.

| Knob (`sim/ai_profile.gd`, ids 360-362; `N_KNOBS` 363, gap 352-359) | Easy | Average | Skilled |
|---|---|---|---|
| `S_LOF_PICK` | 0 (the nearest, as before) | 1 | 1 |
| `S_COVER_DIR` | 0 (the cover cells only) | 1 | 1 |
| `S_LOF_STEP` | 0 (stands) | 12 m | 12 m |

Easy as before (deliberate mistakes). Measured: battle_sim.md (as built): the storming shooters' pick and the
strongpoints' cover move no balance cell measurably (`S_LOF_PICK` off, on the build that still had the 4 m stride at
walls: Rome walls 2-3 38 / 23 -> 42 / 23); the defenders' step finds a spot within 12 m in few street posts (the AI's
no-line standing barely moves), and in `open_town` (8 seeds) turning it off gave 88 % as with it.
