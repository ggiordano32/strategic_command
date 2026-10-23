# Campaign rules (goals, campaign layer, story, milestones, risks, future)

Moved verbatim from `docs/DESIGN.md` on 2026-10-22 (the docs split; index in `docs/DESIGN.md` and `docs/design/README.md`). Design sections first, then the "as built" sections in date order.

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
- **Trade along the sea lanes (agreed and built 2026-10-22, both packs):** every sea lane between two ports pays
  (level_a + level_b) x 4 gold a turn (a pack row may override), half to each end port's owner, as the income's "trade
  lanes" part. A fleet at war with a port's owner that lies on the lane at the end of a turn raids it: the lane pays 60 %
  less and the raider's owner takes half of the cut; a blockaded or besieged port's half is not paid. Raiding and
  blockading are voyages to a station (orders `fraid`, `fblockade`), so a navy is the weaker side's play (raids) and
  the stronger side's (blockades); the treasure fleet sails along its lane, which is where a raider meets it. Rome's
  lanes pay the same way and will carry its navy. As built: docs/CAMPAIGN.md "Lane trade, raids and blockades".
- Armies recruit in owned settlements, limited by the military buildings present.
- Missile units come from the Range (owner 2026-10-23): every non-siege missile line (archers, javelins, slingers, buccaneers, and now **musketeers**: Range of their tier, 1 for musketeers, 2 for the veterans) is made at the Range, not the Barracks; mounted missile units (camel archers, light horse, pistoleers, cuirassiers) keep the Stables for the horse and also need a Range 1. Artillery stays the Workshop. Capitals start with a Range 1, towns do not (a town needs one built to raise musketeers).
- **Reuse:** the campaign layer is meant to carry a different game later
  (the American West). Everything specific to the Mediterranean is data:
  regions, routes, sea lanes, factions, rosters, starts and numbers in
  `campaign/cdata.gd`, the coastlines and territories in
  `game/campaign/map_geo.gd`, from which `tools/campaign_grid.gd`
  generates the nav grid (`campaign/data/grid_data.gd`). The rules
  (`campaign/crules.gd`, `cgrid.gd`, `cai.gd`) read only those tables.

### Diplomacy

- States per faction pair: war, peace, trade agreement.
- The two players are permanently allied.
- AI accepts or refuses proposals from a simple score (relative strength, war weariness, shared enemies).
- Team victory option (2026-10-23, owner: a few AI team-ups ended the game early): the creation setting `team_regions` (1 default, the old rule: the regions of every member of the players' team count toward the regions and key cities to win; 0: only the regions the human players hold count, AI factions that joined the team do not; co-op players always count). Stored in `settings` only when 0 (absent reads 1, no `CState.VERSION` bump); `CRules.victory_progress` / `_check_victory_teams` honour it; the Goals panel says which rule is on. The victory goal is otherwise `victory_regions` (default 20) with `victory_capitals` (default 3) key cities.

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

### Fog of war on the overworld (as built 2026-10-17, state format 8)

Owner's decisions: a player sees, Rome 2 style, its own regions and their
land neighbours, 1 cell round its armies (2 from a hill or ridge), fleets (5 cells round a fleet at sea, 2026-10-23: a masthead lookout; 3 before)
and agents in a city, 2 round its cities (their waters too), and (2026-10-22) the sea
within 2 cells of the coast of each coastal region of its own, 3 for a region with a
harbour or walls 3; a team shares its sight. Out of sight the map shows the **last known** owner and faded
markers of the armies and fleets last seen there (with the turn), never
the live pieces, and no list, panel, battle, raid warning or chronicle
line tells of what is unseen. The AI sees everything. Rules half:
`campaign/csight.gd` computes sight from the state every time (never
stored) and keeps each faction's memory in the state (`factions[f].mem`:
last-known owner and turn per region, at most 400 last-seen markers),
written at the end of each turn and after each battle; the rules never
read sight, so the play is exactly the format 7 play. A campaign option
`fog` (on by default) lets the view show everything (the sandbox, tests).
Details: CAMPAIGN.md "Fog of war".

**The view (as built 2026-10-17, `game/campaign/fog_view.gd`, `fog_layer.gd`).** The sight of the planner's team is
computed once per sight change (a new state, another planner, the setting; `FogView.update`, never per tap) and read
through `FogView` helpers. The fog is one grid-sized texture over the map, trees and towns and under the overlay: a
dark blue-grey wash (66 % at most) where nothing is seen, a one-cell soft edge (3x3 blur, bilinear), the sea beyond the
map's edge fogged too. Region fill and the owner band use the owner as last seen (never-seen land: neutral, no border,
no name; its settlement a grey dot). Armies, fleets, sieges, blockades, wrecks and battle swords are drawn only when
seen, so an unseen piece cannot be tapped; last-seen markers (`CSight.markers`) are faded dashed shields / hulls with
the count and "tN", a tap says "last seen on turn N". Enemy zones, attack links, raid lines and the replay only cover
seen armies. A region out of sight opens a short panel and bar card (owner as last seen, the turn). Diplomacy shows
regions as last seen and the army as far as seen, the chronicle uses `CSight.event_seen`, the Battles list the visible
battles, Goals the key cities as last seen. Creation: "Fog of war: on / off" button beside the other options
(`settings.fog`); testing aid `--all-seeing`. Not covered: the town models' buildings (TownPlan) still follow the true
state.

### The campaign AI's odds as win chances (as built 2026-10-22)

The campaign AI (format 6) decides attacks, sieges, sallies, landings, screens and retreats on the auto-resolve
formula's predicted win chance (`CBattle.odds_of`, the pack's `WIN_EXP` curve) rather than on strength ratios, so the
thresholds keep their meaning whenever the formula is refitted: Easy / Average / Skilled attack at 45 / 55 / 65 % and
retreat (lift a siege, fall back, give up a screen, shelter) below 20 / 30 / 35 %; armies are committed until the chance
reaches 85 / 90 % (Average / Skilled), a siege is preferred to a storm on arrival short of that, and below the threshold
the AI gathers or musters instead. The campaign's AI aggression setting shifts every threshold by 10 points (Calm +10,
Aggressive -10). Skilled never shelters inside the walls. Measured with `tests/ai_odds_probe.gd`; numbers, tables and
the head-to-head in docs/AI.md 12.1.
