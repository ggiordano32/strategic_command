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
  **Decision (2026-10-31): a raided lane is shown to its owners whatever the fog.** The owner of either end port, the
  raider's team and whoever sees the raider are told: the raided lane on the map (`MapOverlay.raided_info`) and the
  chronicle row `lane_raided` (`CSight.event_seen` tells the two owners and the raider by faction, anyone else where they
  see the cell), because an owner knows his trade is being taken, as he sees his own income fall. This is the design, not
  a gap in the fog: there is no separate "a port sees its lane's cells" rule (the 2026-10-22 plan of CITY_R + 1 was never
  built and is dropped), so `csight.gd` stays the one function for what a faction sees (its settlements' CITY_R squares,
  coasts, armies, fleets) and the lanes add nothing to it. A Skilled AI fleet blockades the port its own army besieges
  (`CAIFleet._blockade`: value x 3, reach BLOCKADE_TURNS + 2) and the blockaded port's stores fall by two a turn
  (`CRules._siege_turn`), by one before the blockade stands; `campaign_test _skilled_siege_blockade` plays it (England
  Skilled, Havana besieged, the fleet four turns off: the blockade stands at the end of the fourth turn, the stores falling 1, 1, 1, then 2, 2, 2 a turn), with
  Average and Easy picking another port from there.
- Armies recruit in owned settlements, limited by the military buildings present.
- Missile units come from the Range (owner 2026-10-23): every non-siege missile line (archers, javelins, slingers, buccaneers, and now **musketeers**: Range of their tier, 1 for musketeers, 2 for the veterans) is made at the Range, not the Barracks; mounted missile units (camel archers, light horse, pistoleers, cuirassiers) keep the Stables for the horse and also need a Range 1. Artillery stays the Workshop. Capitals start with a Range 1, towns do not (a town needs one built to raise musketeers).
- **West building chains (owner 2026-10-23: "tier 2 and 3 should have light and heavy cannons in the Caribbean, not rock throwers and siege arrows"):** the West pack has its own `CHAINS` (`campaign/data/west.gd`; the same keys, costs and rules as Rome's, only the texts in Caribbean words, Rome's untouched) and its **Workshop has three levels** (cost 600 / 1200 / 2000, build 2 / 3 / 3 turns): level 1 falconets (light guns) and the hand cart, level 2 culverins and ammunition wagons (with Stables), level 3 **heavy guns** (24-pounders, unit `heavy_gun`, `UNIT_NEEDS` Workshop 3; the second tier of the `field_gun` line, so the AI's best-tier pick takes it when it can; sim row in battle_sim.md "Firearms"). Spain, Tierra Firme, England, France and the Dutch may raise them (Tierra Firme and France only the heavy guns, no culverins); pirates and natives never. The AI's mixes are unchanged (it builds the Workshop as its build-up and general plan do).
- **Reuse:** the campaign layer is meant to carry a different game later
  (the American West). Everything specific to the Mediterranean is data:
  regions, routes, sea lanes, factions, rosters, starts and numbers in
  `campaign/cdata.gd`, the coastlines and territories in
  `game/campaign/map_geo.gd`, from which `tools/campaign_grid.gd`
  generates the nav grid (`campaign/data/grid_data.gd`). The rules
  (`campaign/crules.gd`, `cgrid.gd`, `cai.gd`) read only those tables.

### Diplomacy

- States per faction pair: war, peace, trade agreement, alliance (state format 10: dip ALLIED between factions on different teams, which includes trade; team mates are ALLIED too). Military passage is a treaty on top of peace or trade (10 turns). Trust: repute per faction and regard per pair, both fading (`campaign/cdip.gd`; "Diplomacy: trust, alliances and passage" below).
- The players are allied through the teams (format 7); a team now comes through an alliance (format 10).
- AI accepts or refuses proposals from a score (format 10: regard + repute against each treaty's floor, with the old strength and timing tests kept as a second gate where the plan says so; `CAI.why`, the one place the rule is); it never starts a war on a faction it regards 30 or more, twice as often on one it regards -30 or less, and a threatened AI seeks allies (creation setting `ai_alliances`).
- Team victory option (2026-10-23, owner: a few AI team-ups ended the game early): the creation setting `team_regions` (1 default, the old rule: the regions of every member of the players' team count toward the regions and key cities to win; 0: only the regions the human players hold count, AI factions that joined the team do not; co-op players always count). Stored in `settings` only when 0 (absent reads 1, no `CState.VERSION` bump); `CRules.victory_progress` / `_check_victory_teams` honour it; the Goals panel says which rule is on. The victory goal is otherwise `victory_regions` (default 20) with `victory_capitals` (default 3) key cities.

### Diplomacy: trust, alliances and passage (plan, 2026-10-26; agreed with the owner)

The owner's brief (phone playtests, 2026-10-26): a light version of Rome 2's
trust, where what you do on the board changes how the AI answers you and it
fades with time; a little gold sways it, but only so much; a way to cross a
peaceful faction's land; alliances below the team; the Caribbean's asymmetry
carried by starting treaties. All of it is campaign rules (`campaign/`,
hashed, state format 10) plus the diplomacy screen; the sim is untouched.

**Trust: two numbers, both fading.** Integers in the state, moved by the
rules only, read by the AI's answers and shown on the diplomacy screen.

- `repute [n]`: one number per faction that everyone reads, how it keeps
  its word. Clamped -50..50, moves 1 toward 0 a turn. Falls for a broken
  treaty (war on a trade partner or an ally: -20), an unprovoked war (-10;
  a war joined on an ally's call costs nothing), a sack (-5), a call to arms
  refused or sat out (-5). Rises +2 for a battle fought beside an ally.
- `regard [n*n]`: `regard[a*n+b]` is how `a` regards `b`, what `b` did to
  `a`. Clamped -100..100, moves 1 toward 0 a turn. War declared on us -40
  (and the treaty break above when it was a partner), a city of ours taken
  -15, a town of ours sacked -20, a trespass -2 per army per turn, a call to
  arms refused or sat out -20, trade cancelled -10, an alliance left while
  we are at war -20, peace made +5, a battle fought beside us +10, a gift
  as below. A starting treaty sets +30 both ways.
- Gifts: an order `{"t": "gift", "to": g, "gold": x}` (x >= 50, from the
  treasury) raises `regard[g][f]` by x / 50; the gift share is kept apart in
  `gift [n*n]`, capped at +25 standing, and fades 2 a turn instead of 1, so a
  gift opens a door and cannot hold it open. Nothing to a faction at war.
- `regard_log [n*n]`: the last 4 entries `[turn, delta, why]` per pair, so
  the screen can say why ("they took Trujillo, -15, turn 31").
- Everything that moves a number is an event `{"k": "regard", "a", "b",
  "d", "why"}` / `{"k": "repute", "f", "d", "why"}` for the chronicle.

**How the AI answers (`CAI.why`, the one place the rule is).** The score is
`regard[to][from] + repute[from]`; each treaty needs a floor, and the
existing strength and timing tests stay as a second gate unless said
otherwise: trade >= 0 (its turn and strength tests kept); passage >= 10 and
at peace or trade; alliance >= 25, at peace or trade, and the answering AI
threatened (at war, or a neighbour stronger than it that is not its ally);
team: already allied, regard >= 50 and a battle fought side by side
(`fought [n*n]` counts resolved battles with armies or fleets of both on
one side); the turn count and the strength test of the old team rule go.
Peace keeps its rule. An AI never declares war on a faction it regards >= 30
except by the trespass line below, and its war chance doubles on one it
regards <= -30. Pirates keep the marque as their only peace.

**Alliance** (`dip` value 3, ALLIED, between factions not on one team; team
mates stay ALLIED and on a team). Shared sight (`csight`: the sight of allies
is shared as a team's is), `friendly()` (free entry, docking and repair in
each other's ports, reinforcing each other's battles within range), no
regions counted for victory, no shared victory. Orders: propose
`"alliance"` (needs peace or trade, no war between the two sides),
`{"t": "leave_alliance", "with": g}` with 5 turns' notice (`aleaving [[a, b,
turn]]` like `leaving`); after the notice `dip` falls to TRADE.

- **Call to arms.** When `c` declares war on `a`, or `a` on `c`, every ally
  `b` of `a` gets a proposal `{"what": "call", "from": a, "to": b, "vs": c}`
  the next turn (a human answers in the inbox, an AI by score: it joins when
  its wars are under its MAX_WARS and its strength is at least WAR_RATIO_BUSY
  % of `c`'s, else refuses). Accepting declares war on `c` as "called" (no
  repute loss). Refusing: regard -20, repute -5. Sitting out: an ally `b`
  still at peace with `c` 5 turns after the call, while `a` is at war with
  `c`, counts as refused (same costs) and an AI `a` then leaves the alliance
  at once (event `alliance_left`). Voluntary with a trust cost, as agreed:
  no hard obligation an army four turns away could never meet.
- **AI-to-AI alliances**: creation setting `ai_alliances` (1 default, stored
  only when 0). An AI that is threatened proposes an alliance to the
  neighbour it regards best that is not at war with it or its allies, at
  most 2 allies each, ALLY_PROPOSE % a turn (0 at Easy). The same score
  answers.

**Military passage.** `passage [n*n]`: `passage[a*n+b]` the turn until which
`b` may cross `a`'s land (0 none); proposal `"passage"` grants 10 turns. A
human army may march into a peaceful faction's land without one (today
`can_enter` refuses): a **trespass**, -2 regard per army per turn it stands
there (one event per pair per turn), shown when the move is planned ("a
trespass: -2 a turn, war at -40") and on the map; once `regard[g][f]` is
below -40 an AI `g` declares war on `f` (event `war` with `"why":
"trespass"`). The AI never trespasses: its `can_enter` stays strict, it uses
only passage it holds (asking for passage itself is a later item).

**Starting treaties and the Caribbean asymmetry** (West pack data,
`START_TREATIES` in `west.gd`; Rome has none): the Miskito begin allied and
trading with England, France holds a marque on the Brethren, the Itza begin
with nobody. The Miskito musket line (`TREATY_LINES` in `west.gd`: faction
key -> line -> the faction keys any trade agreement with which unlocks it)
needs a trade agreement with a European nation, so Miskito Musketmen are
there from turn one and lost only by breaking with England ("needs a trade
agreement with a European nation" in the raise dialog). Later item, not in
this build: a European allied with a native faction recruiting that
faction's rows at a shared-border city.

**Build order.** Rules with tests first (state format 10 with a migration
that fills the new arrays with zeros; `campaign_test` cases for every delta,
the fade, the gift cap, each answer floor, the call to arms including
sitting out, leaving with notice, trespass and the trespass war, passage,
the starting treaties, the musket gate, AI-AI alliances on and off; the
determinism check; `campaign_sim` pins move), then the diplomacy screen
(regard and repute per faction with the log lines, Propose trade / passage /
alliance / team, Gift with 100 / 250 / 500, Call to arms when at war, Leave
alliance, the inbox answering calls and alliances, the creation setting, the
trespass toast and map marking, the raise-dialog refusal).

**As built (rules, 2026-10-26; the screen is next).** Built as planned in
`campaign/cdip.gd` (every number of the plan in its const table; the AI's
per-level ALLY_PROPOSE 0 / 15 / 25 % and ALLY_MAX 2 in `cai_profile.gd`),
state format 10 (server StateVersion 10), with these decisions where the
plan left a point open or was changed:

- State keys `repute [n]`, `regard`, `gift`, `passage`, `fought [n*n]`,
  `regard_log [n*n]` (lists of `[turn, delta, why]`), optional `aleaving
  [[a, b, turn]]` and `called [[a, b, c, turn]]` (the calls a human ally has
  not answered: the sitting-out rule reads it); `settings.ai_alliances`
  stored only when 0. A state without `regard` (format 9 and older, an
  unmigrated online campaign) plays the old rules exactly: no trespass, no
  alliances, the old team rule, no treaty lines (`campaign_sim`, which plays
  format 6 by default, and its `--format=8` rows reproduce their pins).
  Migration 9 -> 10 adds zeros; no treaty is applied to a running game.
  `as_format(st, < 10)` undoes the starting treaties of a new campaign.
- Unprovoked war: not an answer to a call and the victim has no army in
  the declarer's land; a war on a trade partner or an ally costs both
  (-30). Declaring war on an ally is allowed (team mates still not): the
  alliance drops with the broken treaty. The trespass war is declared by
  the rules at the end of a turn (`why: "trespass"`), costs no repute and
  needs a trespass that turn.
- The fade: regard = gift share + the rest; the gift share falls 2 a
  turn, the rest 1 toward 0 (a regard of 10 that is all gift is 8 a turn
  later). A gift past the cap still moves the gold. Trespass costs come
  after the fade (the first turn's -2 is exact), and only human armies pay
  (an AI army without passage is sent home by the rules before it could).
- The call to arms is a **defensive pact** (owner, 2026-10-26): when `c`
  declares war on `a`, `a`'s allies are called; when `a` declares war on
  `c`, nobody is (so sitting out only follows a defensive call). An AI ally
  answers at once (`CAI.why "call"`); a call is not posted to an ally that
  is allied to the enemy too.
- Deterrence: the AI's opportunistic war test (and `_unwise_war`) weighs
  the target's bloc, its own strength plus that of each ally not at war
  with the AI already and not allied to it (`CAI.bloc_strength`);
  WAR_RATIO / WAR_RATIO_BUSY unchanged. The pirates' war rule uses no
  strength ratio and is unchanged. Measured (`campaign_sim --format=10`, 6
  x 60): without these two the Spanish-Dutch bloc called each other into
  every war and the Miskito fell in 3 of 6 West seeds, the Greeks in 3 of
  6 Rome seeds; with them no faction falls in 3+ seeds that did not before. Sitting out is
  judged 5 turns after the call (`CDip.CALL_WAIT`, a rule for humans too,
  so in `cdip.gd`, not a per-level knob). A human's unanswered proposal
  expires as others do; the `called` record stays until answered, sat out
  or moot (the war over, the alliance gone).
- AI-AI alliances: the plan's score alone (all regard 0 at the start, no
  source but peace +5 and the battles of allies) never reached the
  alliance floor of 25, so an alliance's score adds `COMMON_ENEMY` 25 when
  both sides are at war with one faction (the old diplomacy bullet's
  "shared enemies"). Pirates sign no alliances. With `ai_alliances` 0 the
  AI still proposes alliances to players.
- The team rule (format 10): no war between the two teams, allied, regard
  >= 50, a battle fought together; formats 7-9 keep the old rule.
  TEAM_ACCEPT_TURNS / TEAM_ACCEPT_PCT remain only for them.
- Shared sight: `csight.gd` reads `CState.friendly` (team or alliance).
  Live-battle guests (`battle_side_of`) and the gifts between players stay
  team-only.
- Starting treaties: a story campaign is created with settings `treaties`
  0 (not stored): none (the Brethren's story gives its own letters).
- The Miskito's fall, diagnosed and the start army (2026-10-29, no
  diplomacy rule changed): 72 West seeds at format 10 (baseline 21
  eliminations of the Miskito): in all 21 the English alliance still
  stood at the death; England never attacked and never sat out (the
  sitting-out rule judges human allies only, `_post_call`; an AI ally
  answers at once); the killers were Tierra Firme (14, from Veraguas
  through Talamanca) and New Spain (6) declaring war themselves, France 1;
  England refused the call as too weak. Answering a call on the pooled
  strength of ally and caller (tried) made it worse (27 of 72: England
  dragged into Tierra Firme's war). The lever that paid is the start: the
  only Miskito region facing Tierra Firme overland, Talamanca, began with
  no army; it now starts with one of four (2 warriors, a bowman, a chief;
  `west.gd`, Cabo Gracias and Bluefields unchanged). 72 seeds: Miskito
  eliminated 21 -> 7 (format 10), 18 -> 12 (format 6); a +1 unit at Cabo
  Gracias and Bluefields alone did nothing (21, 17). Doubling the new
  armies (7 / 7) overshot at format 6. No cooling period for a former
  ally was built: no death followed an ended alliance.

**Answering a call to arms pays (as built, 2026-11-02).** The owner (phone,
the West as the Miskito): "England called me to join in on a war with Terra
Firma as Miskito, but it didn't really benefit my repute or relationship
with England, even as I was taking their towns." Diagnosis (reproduced
headless: England attacked by Tierra Firme, the Miskito called): answering
moved nothing (a "called" war only avoided the unprovoked-war repute);
battles and towns won from the common enemy moved nothing with England
(`on_battle` paid `fought_together` +10 only when both had armies in the
same battle; `on_capture` only cost the loser's regard); the call's
proposal lapses after its turn while its window ("called", sitting out at
5 turns) stays open, and a war order declared inside that window was an
ordinary war: repute -10 "unprovoked war" (-30 on a trade partner); and
the starting treaty's +30 faded 1 a turn the whole time. Ignoring the call
already cost regard -20 and repute -5.

- **Rule** (`campaign/cdip.gd`). Answering a call (the inbox, or any war
  order on the enemy while a call against it is open: `war_answers_call`,
  the war is "called" and answers every open call) keeps faith: the
  caller's regard of the answerer +15 (`REG_KEPT_FAITH`), the answerer's
  repute +5 (`REP_KEPT_FAITH`, the mirror of the refusal), and an
  `answered [[a, b, c, turn]]` record (optional key, absent = none, sorted;
  no `CState.VERSION` bump: a new key with a default read). While the
  record lives (caller and answerer allied, both at war with `c`, all
  alive), each settlement the answerer takes from `c` gives the caller +8
  (`REG_CALL_TOWN`) and every other faction at war with `c` +3
  (`REG_CALL_TOWN_OTHER`), index order; each battle won with `c` on the
  losing side +2 (`REG_CALL_BATTLE`, once per caller and battle). The
  record goes at the caller's (or answerer's) peace with `c` (`on_peace`)
  and at the end of a turn when no longer live, so the gains stop. An AI
  answering an AI's call keeps faith the same way. Ignoring: unchanged
  (regard -20, repute -5, an AI caller leaves).
- **Numbers.** An alliance today earns almost nothing from the rules: 12
  AI seeds x 60 turns at format 10, the positive regard events between
  allies were `fought_together` alone, 1.3 (Rome) / 1.1 (West) a pair per
  ten turns, the mean regard while allied 0.3 / 2.4; so a standing
  alliance is carried by its start, the treaty's +30 (`REG_TREATY`), which
  the fade spends in 30 turns. Answering and taking two towns is 15 + 2 x 8
  = 31, one treaty's worth: it lifts the caller's regard over
  `NO_WAR_REGARD` 30 and the alliance floor 25 by itself, and halfway to
  the team's 50 from a starting treaty. The owner's case: England's regard
  30 -> 45 (answered) -> 47 (a field battle) -> 55 -> 63 (La Guaira, Coro),
  repute 0 -> 5; the Brethren, at war with Tierra Firme, +3 a town.
- **The AI.** No decision code changed (no knob): the caller's higher
  regard feeds `CAI.why`'s score for the answerer's proposals and the
  no-war line as any regard does; the AI's own answer to a call is
  unchanged (`CAI.why "call"`: the gains are not weighed; a knob if ever).
- **The view** (`game/campaign/campaign_panels.gd`). The turn report and the
  battle result show every gain of a call, small ones included: "Kept faith
  with England against Tierra Firme: their regard of you +15.", "Took La
  Guaira from Tierra Firme, England's enemy: England's regard of you +8.",
  "Beat Tierra Firme, England's enemy, in battle: England's regard of you
  +2.", "Your repute: +5 (kept faith with England)."; the regard log on the
  diplomacy screen says "you answered their call to arms", "you took a city
  from their enemy", "you beat their enemy in battle"; the call's inbox
  text adds what answering earns.
- **Measured** (`tests/campaign_sim.gd`, 72 seeds x 60 turns, HEAD ->
  as built; the per-seed diplomacy tallies are in its `--json` line): Rome
  formats 6 and 10 and West format 6 identical seed for seed (no AI call is
  answered in Rome; no diplomacy below format 10); West format 10: 19 of
  72 seeds identical, eliminations 35 -> 35 (Brethren 15, England 2, Itza 9,
  Miskito 9, each unchanged), battles 47.8 -> 47.7 a seed, field 3.5 ->
  3.5, wars 9.75 -> 9.68, calls answered 1.10 -> 1.10, refused 1.86 ->
  1.82, alliances standing at turn 60 3.82 -> 3.82; per seed 1.1 calls kept,
  0.25 towns and 0.25 battles paid. Pins: `campaign_sim --format=10` West
  seeds 1, 4, 5, 6 moved; Rome, formats 6 and 8, `ROME_20` and the AI
  goldens unchanged.

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
- **(2026-11-01) Two armies attacking one.** The owner (West, a native
  faction): "I can't attack when multiple armies attack an army at once. I
  had to back one army off and reattack to get the battle to start", and
  again with three armies on two enemy armies close together. Headless
  probe `tests/multi_attack_probe.gd` (West, the Miskito against Tierra
  Firme; each order through `CTurn.preview` as the view's `set_move6`,
  then `resolve_turn`). Five causes in `campaign/crules.gd`, all silent:
  1. *A battle across a region border vanished.* The battle stands on the
     target's cell, in the target's region; an attacker next to it may stand
     in the neighbouring region. `check_eliminations` (run at the end of the
     turn and after every battle applied) kept a battle only while an
     attacker stood in the battle's region (a rule of the region-hop
     formats), so the battle was dropped and every army freed: no battle.
     Attacking again from a cell in the target's region worked, which reads
     as "back one army off and reattack". On the grid an attacker in the
     battle counts wherever it stands. The AI was hit too: an AI battle
     across a border was dropped when another battle was applied first.
  2. *A second attacker that starts next to the target stood idle.* It
     never steps, so `_step6`'s join does not see it, and `_arrive6`
     skipped a target already busy; support leaves out armies inside a
     settlement and on a siege ring (field armies came in as `reinf` on a
     map edge). `_arrive6` now joins the battle started this turn that a
     target next to it fights in (`_new_battle_of`, `_join6`; a refusal is
     a `move_failed` event). A joiner that does not move records its own
     `from` in the battle (as an attacker of `start_field_battle`) and
     leaves a siege's record alone.
  3. *One battle a region left the attacked army out.* `_contact6` puts an
     army that runs into a free enemy army into the battle already started
     in that region this turn; the army it attacked stayed out (ordered
     1 + 2, the two on X fought Y's battle and X was never fought).
     `_pull_in` now brings the army it ran into, with its side's free
     armies next to it, into that battle on the other side (not for a
     relief, whose battle is the siege's). Enemy armies in adjacent regions
     get a battle each, as before.
  4. *A path went over a target's own cell.* `plan_path` takes the zones of
     the target and its side's armies out of the zone mask, cells included,
     so a march on X could step onto Y's cell (two armies on one cell; with
     cause 1 the battle then vanished). The targets' own cells stay out.
  5. *The zone-of-control lock.* `CGrid.find_path` never entered a zone
     cell, even in the zone the army started in, though `_step6` stops a
     step only on a zone entered from outside: an army next to (or within
     two cells of) enemy army Y could neither march clear nor attack another
     army X ("no route"). `held_zones` takes the zones the army already
     stands in out of the mask for `plan_path` and `reach6` (the reach
     shading), keeping the cells next to that army in (a step there is
     contact) and other armies' zones whole; if a path still fails the
     refusal reads "held in <faction>'s zone of control: attack them or
     march clear of them".
  campaign_test `_grid_two_army_attacks` checks two field attackers, two in
  a town, field and town, two besiegers (the siege's record untouched), two
  targets in one region either order, an attack across a region border, an
  attack on X from next to Y, and marching clear of Y without stepping next
  to it (9 of them FAIL on HEAD). campaign_input_test's merge-glyph set-up
  moved its army out of the enemy's zone (from inside it the merge is now
  allowed). Causes 1, 4 and 5 change the AI's play: the pins move (STATUS).
- **(2026-11-02) The AI reckons with the zones it stands in.** The owner:
  "Let's update the AI's distance estimates", the open item of the bullet
  above. The campaign AI picks two kinds of cells against the side's enemy
  zone mask (`cx["zone"]`, every enemy zone closed): `_toward`'s waypoint
  (about a turn down the destination's distance field, the farthest trail
  cell outside every zone) and `_fall_back`'s refuge (Skilled: a friendly
  field cell or one of our armies, outside every zone). For an army inside
  an enemy zone that mask still read the old lock: a cell in the zone it
  stands in was refused although `plan_path` now lets the march go there.
  Both now take the army's own mask, `CAI._zm_of`: the side's cached mask,
  or for an army inside a zone a copy opened by `CRules.held_zones`, exactly
  as `plan_path` opens it (the zones it stands in passable, the cells next
  to that enemy army and every other army's zone closed). The gathering
  point of an attack (`_attack6`, the lead's trail) keeps the side's mask:
  every gathering army must be able to end its march there, not only the
  lead. `CRules._move_targets6` (the targets list of the view's move menu
  and the test bots) used the plain mask while `reach6` and `plan_path`
  used `held_zones`; it now does too. Nothing else in the AI read the lock:
  its turn estimates (`eta`, `site_dist`, the octile hunt and rally ranges)
  never counted zones, and attack, hunt and siege orders aim at settlements
  and enemy armies, whose zones `plan_path` opens for the march. The case
  is rare: a free AI field army stands in an enemy zone at planning time in
  about 1 army-turn of 1,000 (21 in 6 + 6 seeds), and the changed pick
  showed in 1 seed of 288 (72 seeds x Rome / West x formats 6 / 10); no pin
  moved. Test: campaign_test (the zone set-up of `_grid_two_army_attacks`:
  the AI's mask opens the cell two from Y, keeps the cells next to it).

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

### Amphibious armies (2026-10-23)

A per-type unit trait `amphib` (`sim/unit_types.gd` DEFAULTS, 0 / 1; no row has it yet, the Miskito canoe raiders of the
Caribbean roster batch 1 will be the first). `CRules.amphibious(st, a)`: every unit of army `a` has `amphib` 1 and the
pack has ships; an army with any other unit is not amphibious, and a general's row is left at 0 on purpose, so a general
in the army makes it land-bound. Pack-agnostic rules; in a pack without ships (Rome) nothing changes.

- **Movement.** An amphibious army may step onto the coastal sea (`CFleet.is_sea` cells with `CFleet.coast_dist` <= 1,
  the same water a coastal fleet keeps to; `CFleet.ensure` hands the mask to `CGrid.set_wet`) at foot pace: a water step
  costs `CGrid.WATER_STEP` (20 since 2026-10-27, was 10; x 14 / 10 on a diagonal; the ridge cost, so an army wades only where no land path of lower cost exists), a landing the land cell's own cost. The
  planner is the same: `CGrid.find_path` / `CGrid.reach` take `water` (the neighbour tables `_nbw` / `_nbcw`, built on
  first use, nothing stored in the state), `CRules.plan_path` / `reach6` / `_move_targets6` pass `amphibious`, the march
  preview and the stored `dest_x` / `dest_y` work unchanged. The water is not crossed wider than two cells of coast
  (cells within one cell of land only), so a strait is crossed where the coastal strips meet (Cumana to Port of Spain,
  Cartagena to Darien); the detour rule is not applied to a water march. No zone of control stops an army stepping onto
  water, and an army afloat has none.
- **Afloat.** An army may end its turn on a coastal sea cell; its cell is just a cell (`a["r"]` keeps the region it left).
  Afloat it cannot be attacked by a land army (contact and zones skip it) and cannot attack (a step onto water starts no
  contact; landing on a cell beside an enemy army is the normal contact). It keeps its stored march. Entering or ending
  next to a hostile settlement from the water follows the normal ring / siege / assault rules (a ring cell on the water
  counts as the ring).
- **Fleets.** An afloat army never fights a fleet. An enemy (at war) fleet whose voyage steps within `FLEET_ZONE` (2) of an
  afloat army not in a battle captures it at once: the army is destroyed, event `canoes_sunk` {f, by, army, men, x, y}
  (no sea battle, no RNG; `CFleet.sink_afloat`, called for every step of every voyage in fleet-id order, armies in index
  order). Its own side's fleets, and fleets at peace, do not. A fleet that stays put does not sink an army that paddles
  by (only voyage steps do).
- **AI.** The AI plans marches through the same planner, so an amphibious army ordered across water gets the wide
  passability. Since 2026-10-23 (docs/AI.md 34) its distance estimates for an amphibious army use the water too
  (`CGrid.field(src, sea, water)` and `CGrid.downhill(..., water)`, memoised apart from the land fields; `CAI._sf_of`),
  so it picks targets, raids and staging points the water reaches; its canoe raiders muster as their own band.
- **Auto-merge** (2026-10-23): the end-of-turn merge of idle armies on a settlement (`CRules._auto_merge6`) never
  merges an amphibious army with a land-bound one (the band would lose its trait); a player merges them by order.
- **View.** An afloat army's banner is drawn on its sea cell with a small canoe under it; the hint for a selected
  amphibious army says it may paddle along the coast; fog sees it as an army (by its cell).
- **Old saves / pins.** Nothing stored, no unit has the trait: no `CState.VERSION` bump, every pin unmoved. Tests:
  `tests/campaign_test.gd` `_amphibious`.

### Breached walls on the campaign (as built 2026-10-24, state format 9)

Design agreed by the main session (2026-10-24); the follow-up "repairs cost gold" of siege_and_towns.md
"Destruction: walls and buildings fall (plan)". Until now the walls stood whole again by the next turn.

- **The result.** `BattleSim.result()` carries `"breaches"`: the wall stretches down at the end of a battle on a town
  map (`breached_count()`, those it opened with included; absent when none). `CBattle.outcome_from_result` passes it
  on. The formula (auto-resolve without the sim) breaches nothing, so AI-only play never records one.
- **The state.** A fought settlement battle (an assault or a storm, not a sally, relief or field fight) at a town with
  walls sets the region's `"breach": n` to the result's count (version 9; a state of an older format records none and
  `CState.as_format(st, 8)` drops the key). Optional, absent = 0 (`CState.breach`); hashed as every key.
- **Mending.** At the end of each turn, after the money, each settlement with a breach (regions in index order) mends
  one stretch, its owner paying `CData.WALL_REPAIR` (150 a stretch in Rome, 120 in the West; `CData.wall_repair()`)
  when the treasury holds it, else it waits; an independent town mends one free; none while it is besieged or has a
  battle pending; walls gone (level 0) clear it; the key is erased at 0 (`CRules._mend_walls`).
- **The next battle.** While n > 0 the scenario of a battle at that town gets `"breaches": n` (`CBattle._build_settlement`),
  and `BattleSim._preset_breaches` opens the battle with the n stretches nearest the main gate (the first outer gate; a
  West fort's gate) already breached, as `_breach` leaves one (rubble ground, the breach's way through open), among the
  stretches the battering AI could pick (standing, not facing the sea, the outer wall's or the fort's, with a way
  through), nearest the gate's face first; at setup before any unit, so no man is lost, no RNG is drawn, no stat or
  event; a wall unit the scenario puts on such a stretch stands on the ground. A scenario without the key is the
  battle it always was (the goldens and every pinned run are unmoved).
- **Auto-resolve.** `CBattle.walls_pct` counts the walls one level lower while a breach stands, never more than the
  whole walls' value (Rome's fitted walls 1 row, 87 %, is under its walls 0 row, 93 %: a breach there changes nothing).
  The AI's odds read the same formula, so it sees a breached town as weaker.
- **View.** The region panel's garrison heading adds "walls breached (n)" and a note (what it means, the cost a
  stretch); the realm panel's treasury line adds "wall repairs -N" (`CRules.wall_repairs`).
- **Tests.** campaign_test `_breached_walls` (the outcome and the record, none from the formula or a format 8 state,
  the next scenario's key, walls_pct, one stretch a turn paid, waiting when poor, none while besieged, the end of turn,
  JSON round trip); determinism_test `_check_preset_breach` (`--only=destr`, the full run). Server `StateVersion` 9.

### The tutorial (plan, 2026-10-29; agreed with the owner)

The owner, 2026-10-28: "Does the single player campaign have a tutorial ...
I would like to assume they had never played a Rome style game before." It
has not: the story's prologue teaches sailing, plunder and havens through
events, the hint line and the Keys page explain controls, the sandbox
explains nothing. Three parts, built in this order; the first is the one a
new player meets before anything else.

**1. The guided first campaign** ("Your first command"; a card on the
Campaign page beside the story, and offered once on the first launch).
A scripted Caribbean scenario: England at Port Royal, a fixed seed, the
other factions at peace with the player while the tutorial runs (a campaign
setting `tutorial` 1 the campaign AI reads: no war on the tutorial's faction
while it is set; a new settings key, no format change), the Spanish town of
Sevilla la Nueva as the target. Ten turns, one objective a turn, a pointer
on the map (the overlay's pulse on the thing to tap), a short card at the
top of the screen in the story cards' frame saying what and why, and a gate:
End turn is held until the objective is met, with a "Skip the lesson"
button that completes it and a "Leave the tutorial" that drops into the
free sandbox from the same state. The objectives are view-side checks on
the state (`game/campaign/tutorial.gd`, reading `CState`, never writing it);
the turn resolves as any turn.

| turn | lesson | objective (the gate) |
|---|---|---|
| 1 | The map: regions, your town, the panel, pan and zoom | open Port Royal's panel, then end the turn |
| 2 | Recruiting: the slots a turn, what the buildings unlock | raise two musketeer companies into the garrison |
| 3 | Building: the chains, levels, the slot, growth | start a Range 1 |
| 4 | Moving: the army, movement points, the path, the stop | march the army to the camp outside Sevilla la Nueva |
| 5 | The siege: declare, the siege panel, starve or storm, the odds | lay siege |
| 6 | The battle (the battle tutorial, below) | storm and win |
| 7 | After: occupation, income, upkeep, the Realm page | open Realm, end the turn |
| 8 | Diplomacy: trust, trade, the gift, the alliance | propose a trade agreement to the Dutch |
| 9 | The sea: the fleet, boarding at a lit beach, a sea lane | board the sloop and sail to the Tortuga coast |
| 10 | Goals: the win conditions, the chronicle; then free play | open Goals; the tutorial ends, the campaign continues |

**The battle tutorial** is turn 6's battle with a scripted deployment and
six steps, each a card and a pointer, each gating the next: place the line
(drag the group into the zone), move it forward (tap the ground), fire at
will (the Fire chip, the first chip explained with its long-press
explanation opened for the player once), charge with the horse (tap an
enemy), hold a unit (Halt), and withdraw a broken one (Withdraw, the
confirmation). The AI defender plays Easy with the garrison scripted to
stand; the player's army is given the win by its make-up, not by a rule.

**2. First-time tips** in every mode (the sandbox, the story, online): a
short toast with a "Got it" the first time the player selects an army,
opens a town panel, lays a siege, enters a deployment, meets a chip, boards
a fleet, gets a diplomatic proposal; one sentence each, the same words the
tutorial's cards use; remembered per device (`user://tips.cfg`), reset from
Options ("Show the tips again"). No gate, no pointer.

**3. A "How to play" page** in the main menu and the in-game menu: eight
short sections (the map and the turn, towns and buildings, armies and
recruiting, movement and supply, sieges, battles and the chips, the sea,
diplomacy and goals), the same text the tutorial's cards and the tips draw
from, kept in one place (`game/campaign/howto.gd`) so the three never
disagree.

**Measured** by a playtest with someone who has not played the game, and by
`tests/tutorial_test.gd` driving the ten turns headless (each gate met by
the scripted order, the skip and the leave paths, the tips file written).

### The tutorial (as built, 2026-10-29)

All three parts of the plan are built; every one is view only except the one rules line (the campaign AI's shield).
No `CState.VERSION` bump, no pin moved (`== sim:` / `== simw:` equal `tools/balance/pins.json`: the setting is absent in the
campaign sims).

**One text source (`game/campaign/howto.gd`).** A static table `T` (key to text) with the eight How to play sections
(`SECTIONS`: id, title, three line keys each), the ten lessons (`lesson_<n>_title`, `lesson_<n>`, `lesson_<n>_obj`), the battle
tutorial (`step_1` .. `step_6`, `step_1b`, `step_win`) and the eight tips (`tip_<key>`), plus the cards' button words (`ui_*`).
Every other file reads from it (`tests/tutorial_test.gd` checks they all exist, and that a tip is one sentence).

**The How to play page.** `howto_page.gd` fills any VBox with the eight sections (heading, three lines, a rule). Three homes: the
title menu's page `howto` (entry `home_howto`, between Battles and Options; heading and the kit's trim panel, scrolling like the
Options page; `menu_test` checks it at 886x409, 844x390 and 1280x720), and the in-game Menu of the campaign and of the battle
(entry `menu_howto`, page `howto` in the column, Back returns to the entries).

**First-time tips (`tips.gd`).** `Tips.show(key)` shows the sentence in a toast with a "Got it" the first time a key fires and
remembers it in `user://tips.cfg` (`[seen]`, one key each); keys `army_selected`, `town_opened`, `siege_laid`, `deployment`,
`first_chip`, `fleet_boarded`, `proposal_received`, `battle_won`. A screen registers a presenter (`Tips.presenter`: the campaign
screen's toast, the battle's card at the top left); with none, nothing is shown and nothing is used up. Wired in
`campaign_screen.gd` (`select_army`, `select_region`, `tip_scan()` from `_refresh`: a siege of ours, a fleet carrying an army, a
proposal made to us; the win in `_apply_battle`), `online_ui.gd` (`tip_scan()` after `step()`, so a proposal reaches an online
seat) and `battle.gd` (`_refresh_deploy`: the deployment, `_refresh_actions`: the first selection in the battle, campaign
battles only). Options: "Show the tips again" (`<prefix>_tips_reset`, in the Help row of the title's Options and a Tips row of
the in-game ones) deletes the file. Test mode: a scripted run (Saves' test-run rule) keeps its file in the tests folder
(`user://campaigns/<test folder>/tips.cfg`) and shows no tips unless `Tips.in_tests` is set (`tutorial_test` sets it), so a
tip toast never covers a toast another test waits for. While the tutorial runs `Tips.suppress` is on (its cards say the same).

**The guided first campaign.**
- *Entry.* The Campaign page's first card `card_tutorial` ("Your first command"); `NewCampaign.tutorial_only` (with
  `story_only`) is a setup with a Name row and one Difficulty row (the campaign AI's skill, default Easy; the seed row is hidden,
  the seed is `Tutorial.SEED` 1670); Start makes the state with `Tutorial.make_state` and saves it under a new slot (a second run
  keeps the first save). The first-launch offer is built (follow-ups below).
- *The state* (`Tutorial.make_state`, made once, before the campaign exists): `new_campaign` for England on the West with
  `settings` `tutorial` 1, `tutorial_turns` 10, `ai_battle_skill` 0 (Easy: the tutorial battle is always easy), the chosen
  `ai_campaign_skill`, `deploy_time` -1 (deployment waits for the player). The West start has Sevilla la Nueva (the region
  `sevilla_jamaica`, Santiago de la Vega) English, so the tutorial hands it to New Spain (with Belize: a far English region that
  a Spanish raid would turn into a battle in turn 2), removes England's second army and shapes the one at Port Royal to a pike,
  two musketeers, a horse and the general (the lesson 2 recruits make the four musketeer companies); England starts with 3000
  gold. England and Spain are at war from the West start, and Port Royal's army stands on the ring of Sevilla (two cells away).
- *The rules line.* `cai.gd` `tutorial_shield(st, g)`: `settings.tutorial` is set, `g` is human and `turn < tutorial_turns`.
  The three places the campaign AI declares a war on its own (the opportunistic war, the pirates', the "unwise war" mistake) skip
  such a `g`. The trespass war and the call to arms are shielded too (follow-ups below), and since 2026-10-30 so are the
  attacks under the war that already exists ("The shield covers attacks" below). A 9-turn passive run of the tutorial state gives England no new war and no battle (the test runs it).
- *The lessons* (`game/campaign/tutorial.gd`, a view object of the campaign screen; the card is `tutor_card.gd`, the pointer
  `tutor_pointer.gd`). Where the player is lives in the save's session, key `tutorial` (`n` the lesson 1..10, 11 the closing card,
  `turn` the turn it was last looked at, `done` its objective held when the turn was sent, `region`, `realm`, `goals` the pages
  opened, `left`, `off`); `CState` is never written. Each turn the lesson of `n` is a card at the top left (title "Lesson n of 10:
  ...", the words, the objective, Skip the lesson, Leave the tutorial; a dialog or a battle hides it), a pointer, and a gate:
  `holds_end()` disables the End turn button (tip "Finish the lesson first" with the objective; `end_turn()` also refuses with a
  toast). The lesson advances on the next turn when `done` was set at End turn; lesson 6 advances when Sevilla is English.

| n | lesson | the gate (the objective's check on the plan being made) | the pointer |
|---|---|---|---|
| 1 | The map | Port Royal's panel was opened (`select_region`) | Port Royal |
| 2 | Recruiting | two `recruit` orders for `musketeers*` at Port Royal | the army, then Recruit, then the + button |
| 3 | Building | a `build` order for the Range chain at Port Royal (the town has Range 1: the order is the upgrade to 2) | Port Royal, then Build |
| 4 | Moving | a `move` order ending at `CGrid.camp(sevilla)` | the army, then the camp cell |
| 5 | The siege | a siege laid or a `siege` order, or a `move` to Sevilla's own cell (laying siege on arrival) | the army, then the town |
| 6 | The battle | an `assault` order on Sevilla (or Sevilla already English); the battle tutorial runs in the battle | Assault |
| 7 | After | the Realm page was opened (`show_faction`) | the Realm button |
| 8 | Diplomacy | a `propose` `trade` order to the Dutch | the Diplomacy button |
| 9 | The sea | the army boarded the fleet (a `move` with `fleet`, an `embark` order, or already aboard) and an `fmove` of that fleet ending within 6 cells of Port de Paix's harbour | the army, the fleet, then the sea off Tortuga |
| 10 | Landing | an `fmove` (or `land`) of the fleet to a land cell of the profile's `raid` region (Oriente, Santiago de Cuba), or the army already ashore there | the fleet, then the lit beach nearest Santiago de Cuba's town |
| 11 | Raiding at sea | an `fraid` order of the fleet (a fleet that lies on an enemy lane already raids it, so only the order counts) | the fleet, then its Raid action (`act_raid`) |
| 12 | Raiding on land | a `stance` order to 4 (Raid) for the army, or the army already on a raid | the region's town, then Raid (`act_raid`) |
| 13 | Goals | the Goals page was opened (`show_objectives`) | the Goals button |

  Once the objective holds the pointer goes to End turn. After lesson 13 the card says the lessons are over; "Got it" ends it
  and the campaign is the free sandbox. "Skip the lesson" does the lesson's order for the player (`add_order`, `set_move6`,
  `set_board` + `set_fmove`; for the page lessons it sets the flag), which opens the gate; the player still presses End turn
  (it does not end the turn itself). "Leave the tutorial" sets `left` and the cards stop: the rules have no settings order, so
  `tutorial` stays in the state and the AI's peace runs out by itself at turn 10.
- *The battle tutorial* (`tutorial_battle.gd`, handed to `battle.gd` as `battle.tutorial` by `fight()` when lesson 6 is current
  and the battle is Sevilla's; `battle.gd` calls `tutorial.seen(order)` for every order it queues and `tutorial.update()` with its
  card timer). Six steps, each a card at the top left (Skip, Leave the tutorial) and a pointer on the HUD control or the map spot,
  each gating the next: 1 place the line (a place order in the deployment; then a second card for Start battle), 2 move
  forward (a move order in the battle), 3 fire at will, 4 charge with the horse (an attack order by the cavalry unit that is not
  the general's guard), 5 hold (Halt), 6 withdraw a unit (Withdraw, its confirmation), then a closing card. Step 3: the Fire chip is
  a multi-state chip (a press opens At will / Hold) and the musketeers start at will, so the tutorial selects the musketeers, queues
  a hold-fire order for them (its own order, not counted) and opens the chip's long-press explanation once for the player; the
  step ends when the player's own order has put them back at will. The defender is the village garrison at Easy (the siege AI has
  no `hold` flag for scripted defenders, so Easy alone); the player's four musketeer companies, pike and horse win it in the
  test with every unit attacking.

**What differs from the plan, and why.** The pointer is a control drawn over the interface (`tutor_pointer.gd`, a ring that follows
a Callable answering a screen point: a map cell through `overlay.to_screen`, a button's rectangle), not a `MapOverlay.pulse_at`:
one class serves the map, the interface and the battle HUD, and the overlay is redrawn in parts. The plan's "start a Range 1" is the
upgrade to Range 2 (Port Royal starts with Range 1 and no free slot). Sevilla la Nueva is English in the West data and made Spanish
by the tutorial state, not by a seed (a seed does not change ownership); the camp outside it is three cells from the town, so
lesson 5 lays siege by tapping the town, which the move to the town's cell does. Lesson 9 says "fleet" (the English fleet is two
frigates and two sloops; only the whole fleet carries the army's seven units). "Leave the tutorial" cannot clear the setting (no
rules order for it). Tips also wait during the test runs (above).

**Open.** A playtest with someone who has never played such a game (the measure the plan names); the
battle tutorial's pointer on the long-press explanation of the other chips; the AI's peace after turn 10 (a Spanish attack under the existing war is possible earlier, with Easy the odds are low).

**Follow-ups (as built, 2026-10-29): the first-launch offer, hot seat, online, the whole shield.** View and menu only, apart from
two guards in `cdip.gd`; no `CState.VERSION` bump, no pin moved.
- *The first-launch offer.* `Tips.first_launch_due()`: no `user://first_launch_done` marker, no `user://tips.cfg`, no saved
  campaign. `main.gd` `_first_launch_offer()` (deferred from `_ready`) then shows a card in the lesson cards' frame over the home
  page, "New here? Your first command walks you through a campaign in ten turns." with "Start the tutorial" (opens the tutorial's
  setup, as the Campaign page's card does) and "Not now"; either sets the marker (`Tips.first_launch_done()`). "Show the tips
  again" only forgets the tips, the marker stays. Never in a scripted run (any command-line argument, the tests folder).
  The Campaign page's card is unchanged.
- *Hot seat.* The tutorial setup has a Players row (One / Two on this device). Two humans are England (Port Royal against Sevilla
  la Nueva) and France (Leogane, the region Saint-Domingue, against Cibao, `santiago_caballeros`, which the state hands to Spain at
  war with France, with New Orleans ceded as Belize is). `Tutorial.PROFILES` holds a seat's home, target, trade partner, sail
  town and the words replaced in the lesson text; the lessons, objectives, pointer and skip all read the seat whose turn it is
  (`seat()`), and each human has its own lesson state in the session (`tutorial` for the first, `tutorial<seat>` for the other).
  The battle script goes to whichever human of the battle is on lesson 6 at its own target. A nine-turn passive run gives
  neither human a war or a battle (tested).
- *Online.* The Host screen has a Tutorial toggle (one human picked, West): the state is `Tutorial.make_state` (England, the
  fixed seed, the Host screen's turn timeout), `settings.tutorial` 1. The cards and the End turn gate run on the host's client;
  the lesson state is kept in the online seat's session blob (`online.session["tutorial"]`, sent with the plan). The tutorial runs
  only while the campaign has exactly one human: a second human ends the cards for both (the setting stays, as with Leave).
- *The shield, whole.* `CAI.tutorial_shield(st, g)` is also read by `CDip.end_turn` (the trespass war is not declared on a
  shielded human; the regard still pays for the trespass) and by `CDip._call_allies` / `_answered` (no ally is called to, or joins,
  a war on a shielded human). Tested in `campaign_test` (`_dip_shield`).
- *Open still.* A playtest; the two-player lessons share the tutorial battle but France's board has not been played through by a
  person; a second human cannot join a one-human online campaign today, so that ending is a guard, not a flow.


**(2026-10-30) The shield covers attacks.** The owner's tutorial run had Spain attack the emptied Sevilla la Nueva at the
end of lesson 11's turn (England's only army had sailed to Cuba for the landing and raiding lessons): the pending battle hid
the lesson card and a newcomer would lose the town they had just taken. Now, while `CAI.tutorial_shield(st, g)` holds for a
human `g`, an AI faction at war with `g` plans no move against it: no siege, assault or attack on its settlements, no hunt of
its armies, no landing, no blockade, no raid on its regions, no attack or sortie on its fleets, no raid on a lane that ends
at its port. The AI still garrisons, recruits, fights everyone else, and fights a battle the player brings to it. Where it
is checked: `cai.gd` `_shield(st, f, r)` (the region filter the story havens already used) is also true for a region of a
shielded human, so the attack targets of `_move_grid` (and the idle armies' fair chance, which reads the same list),
`_hunt` (also by the army's owner), `_raid6` (the free army's raid, the amphibious bands' raids, raiders staying on),
`_sieges_grid` (an own siege of a shielded region neither storms nor takes joiners), the older formats' `_move`,
`_move_sieges`, `_move_free` and `_raid`, and in `cai_fleet.gd` `_landing`, `_blockade` and `_stranded` (an army whose
only enemy regions on its land are shielded counts as having nothing to do there) skip it; `cai_fleet.gd` `_prey` and
`_sorties` skip a shielded human's fleets; `_raid` skips a lane `CLanes._tutorial_spared` names. Two rules lines catch what
an AI fleet does by passing: `CSea.update_blockades` sets no blockade by an AI faction on a shielded human's port
(`CSea._tutorial_spared`) and `CLanes.raiders` counts no AI fleet as raiding a lane that ends at one. Every check is
false at once without `settings.tutorial`, so other campaigns play as before (the four pin sets are unchanged); no new
state, no `CState.VERSION` bump; the rules hash moves (online players reload between turns). The Belize / New Orleans
cession of `make_state` stays (saved tutorials keep their state). Tested: `campaign_test` `_dip_shield_attacks` (the
tutorial state with Sevilla English, England's army and ships gone and a strong Spanish army in Sevilla's field: twelve AI
turns at Easy and Skilled bring no battle, siege, raid, blockade or lane raid against England; without the setting Spain
attacks), `tutorial_test` (the lesson-12 settle of a Spanish battle at Sevilla no longer happens). (2026-10-31) Sea contact too: a fleet's
voyage still met any fleet at war within `FLEET_ZONE` of a step, so an AI fleet passing a shielded human's (or lesson 9's
sail, lesson 11's lane station passing an AI fleet) made a sea battle nobody planned. `CFleet.spared(st, a, b)` (the
shield holds and exactly one of the two is human) now keeps such a pair apart: neither fleet's zone blocks the other's
path or turns a voyage ending in it into an attack (`block_mask`, `zone_owner`), a step into it or lying in it at the
turn's end is no sea battle (`execute_moves`' foes, `sea_battle`'s defenders, `end_of_turn`'s pass), and no afloat army
of the other is sunk (`sink_afloat`); a human's own attack order on an AI fleet (the voyage's target) still fights. Off
without the setting and from `tutorial_turns` (the pins unchanged); no state, no VERSION bump, the rules hash moves.
Tested: `campaign_test` `_shield_sea`.

**Lessons inside a popup (2026-10-30, view only).** The owner: recruiting should highlight the unit and then say to end the turn.
Lessons 2 (the army's Recruit list), 3 (the Build list) and 8 (Diplomacy) are done inside a dialog, and the card and ring used to
vanish while it was open. Now `Tutorial.popup_lesson()` keeps them: the card becomes a compact **strip** (`TutorCard.set_strip`:
title and objective line only, no body or buttons, above the dialog's dim) under the top bar, and `show_dialog` / `_fit_dialog`
leave its height free (`Tutorial.reserve_top()`: the room shrinks by it and the dialog is centred below it; no overlap at 1280 x 720
and 844 x 390). `show_dialog` and `close_dialog` call `tutorial.refresh()` so the strip follows the dialog. The ring: lesson 2 on
the + of Musketeers (`recruit_musketeers`), lesson 3 on the Range row (`build_range`), lesson 8 on the partner's header
(`dip_press_<key>`, the key from the seat's profile) and, once it is open, on its Offer trade button (`dip_trade_<key>`); a target
below the fold is scrolled into view (`_dialog_button`, a few tries) and no ring shows while it is clipped. Once the objective holds
the ring moves to the dialog's Close button (`dlg_Close`) and the strip reads "Done: ... Close the list, then press End turn"
(howto `lesson_N_open`); after the dialog closes the card is whole again and the ring is on End turn. **The battle choice:** with the
lesson-6 battle pending (`is_lesson_battle`) the Pending battles dialog keeps the strip ("Press Fight. We walk through the battle
step by step."), the ring is on `fight_<id>`, Auto-resolve is disabled with a tip, and the setting "always auto-resolve" does not
skip the dialog for that battle (`_next_step`). Lesson 9's words say the army boards at the end of the turn and the fleet waits for
it (the rule is another change) and its met line reads "The army boards when the turn ends, then the fleet sails." Tests:
`tests/tutorial_test.gd` plays lessons 2, 3 and 8 and the battle choice through the real buttons; `tests/tutorial_shots.gd` takes
the pictures.
### The native way (as built, 2026-10-31)

The owner, 2026-10-31: "A tutorial on the canoe raiders and poison arrows may be good. Using fire arrows to bring down a gate
or tower also." A second guided battle, standalone (no campaign), view and scenario data only: no sim rule, no state, no battle hash (the rules hash moves: `sim/scenarios.gd` is in it).

- *The scenario* `tutorial_native` (`sim/scenarios.gd` `native_lesson`, title "The native way"): the player (side 0) storms a
  Spanish palisade village, the ring plan at level 0 with walls 1 (city seed 1671, flat green ground): a timber palisade with
  two wooden gates, which fire arrows burn down (`GATE_FIRE_CHIP` walls 1). The West's own walls-1 town is an open town beside
  a harbour fort whose gate is the sim's walls 2 and need not be taken, so it cannot teach the gate. The war party: two native
  bowmen companies of 80 with poisoned arrows, one of 80 with fire arrows (the special kind is the scenario unit's `"ak"`, an
  `UnitTypes.AMMO` row riding on the bow's arrows; any bowmen row can carry either: in the campaign `AMMO_AVAIL` gives poison
  to the Miskito and fire to the Itza at Range 2, so the lesson's party is a Miskito one with an Itza fire company and Holcan),
  two canoe raiders of 60, two warriors of 100 and the Holcan 60 (620 men). The garrison: musketeers 80, colonial militia 80,
  pikemen 60, no guns; the battle AI on Easy (`ai_skill` [0, 0], side 1 only); deployment waits for the player
  (`deploy_time` -1). Measured with the battle AI playing the war party (`tests/native_lesson_probe.gd`, seeds 7000-7007):
  Average 7 of 8 won (the loss at 629 s), Easy 8 of 8; battles of 5 to 7 minutes.
- *The script* `game/campaign/tutorial_native.gd` extends the battle tutorial (`tutorial_battle.gd`, unchanged) and keeps its
  card, pointer, attach and helpers; six steps, words `nstep_1` .. `nstep_6`, `nstep_1b`, `nstep_win`, title
  `nstep_title` "Native lesson %d of 6" (`Howto.nstep(n)`, `Howto.NSTEPS`): 1 place the war party, then Start battle; 2 poisoned
  arrows (the Ammo order to the special kind for a poison company, then a shot: a poison company's arrows spent or a Spaniard
  poisoned, `u_poisoned`); 3 fire arrows on the gate (done when a gate burns or is broken, `g_burn` / `GATE_BROKEN`; the bow
  shoots a gate only from within range, so the pointer marks a spot at 60 % of the fire kind's range before the gate until the
  company is in range or walking there, then the gate); 4 canoe raiders (a run order and a move or attack by a raiders unit);
  5 the storm (attacks by a warriors company and by the Holcan); 6 beat the garrison (no Skip), and on the win the closing card
  with "Back to the menu" (`ui_menu`, which leaves the battle), placed under the Victory banner. Skip and Leave the tutorial as in the first. Pointers: the
  company's card, the Ammo chip and its special row, the Run chip, the gate (the outer gate nearest the war party), the garrison.
- *Entry points.* The Story Campaign page's second card `card_native` "The native way" ("One battle as the Miskito: poisoned
  arrows, fire on the gate, the raiders and the storm."), which starts the scenario through `main.gd` `_start`, and
  `--scenario=tutorial_native` / `?scenario=tutorial_native` the same way; `_start_with` attaches the script, fixes the seed at
  1671 unless `--seed=`, keeps the scenario's map and skill, switches to the West's pack for the names (the Miskito against New
  Spain, put back at the end) and sets `Tips.suppress` until the battle ends. How to play's "Three ways to play" `ways_3` ends
  "The native way, on the Campaign page, is one battle that shows them." Not in the sandbox's test list (`Scenarios.IDS`).
- *Test* `tests/tutorial_native_test.gd`: the words, the scenario's army and kinds, each step driven by the player's orders
  through the HUD calls (the Ammo chip's options, the gate tap, Run), each card's words and pointer, the battle fought out to
  the win and the closing card, Back to the menu, and a second battle for Skip and Leave; `--shots=DIR` in a window saves each
  card. `menu_test` expects three Campaign cards. A card set before its label had wrapped stood screen-tall (both battle
  scripts' step 1): `tutor_card.gd` `setup` now resizes once more after the layout.

**The native lesson's village (as built, 2026-11-01).** The owner: "take a shot at the native lesson's village look". The
village was the antiquity ring with Roman-era houses on a block grid, a cobbled plaza and orchards, and the soldiers wore
the fallback side colours. Now the scenario's city has `"wring": 1`: `MapGen._city_ring` keeps its palisade, two wooden
gates (step 3's fire arrows still burn one), ring road, streets and plaza, and its random draws, so the gates, the fields
and the deployment are where they were; `_wr_fill` fills the inside with the West's building records: a chapel (the
shrine slot), the alcalde's house, a tavern and a store facing the plaza, a guardhouse inside the main gate, houses and a
shop along the two streets, then houses and shacks in the back lots facing the plaza, thinning and poorer toward the
palisade, with wings, lean-tos, yard walls, barrels, crates and carts; the plaza is packed earth, the fields outside garden
plots, the trees palms (seed 1671: 21 buildings, 7 props, 3 yard walls). The view draws them with the West's kit in the
Spanish manner (flat roofs and hips). The sim keeps the ring's rules (no "west": no cover by material, no street give-up,
no house garrisons); the houses are obstacles and the props and yard walls low cover, so the fight inside changes a
little. Measured with the battle AI playing the war party (`tests/native_lesson_probe.gd`, seeds 7000-7007): before,
Average 7 of 8 (the loss at 629 s), Easy 8 of 8; after, Average 7 of 8 (the same seed lost, at 549 s), Easy 8 of 8;
battles of 4.6 to 8.5 minutes; the fire company now sets some houses alight. The soldiers wear their factions' colours:
`Scenarios.west_factions` adds `"unit_faction"` (the campaign faction index per sim unit, `WEST_SIDES`: the Miskito and
New Spain here, also for `west_harbour_assault` and Tayasal's New Spain and Itza) when the West pack is active;
`main.gd` switches to the West pack for those three ids and `battle.gd` copies the key into `Battle.unit_faction`
(view only: the sim never reads it). The mechanism: siege_and_towns.md "The native lesson's village (as built,
2026-11-01)".

### Native siege, and the natives' buildings (plan, 2026-10-29; agreed with the owner 2026-10-28)

The owner: "It's crazy hard to assault cities as the miskito. They have no
siege and no fire units." and "Why can the miskito make stables?" and the
Workshop's cannon icon on a faction with no cannon. The two natives are
different armies (the Itza the jungle kingdom: Holcan, atlatl, fire arrows,
a lake capital; the Miskito the coastal raiders: canoe raiders, maroons,
English muskets, poison arrows, the English alliance) and the walls flatten
them into one problem; the fix splits along their identities. Campaign
rules, sim rows and AI: the West pins move; no state format change.

**Buildings a faction can use (first).** A chain level is offered to a
faction only when a roster row of that faction needs it (`CRules.needs`,
`UNIT_NEEDS`, `AMMO_AVAIL`) or the level is marked for everyone (`FARM`,
`MARKET`, `WALLS`, the port, the `SHIPYARD` at a port, and every chain's
level 1 where a row needs a higher level of it). The list is derived once
at data load per faction (`CData.chain_levels(f)`); `build_info` refuses a
level not in it ("nothing of yours needs it"), the build panel lists only
the levels in it and says what the next level unlocks for this faction, the
campaign AI's build order reads the same list. Natives therefore see no
Stables and no Range 3; the Workshop stays for the wagon and the poles.

**Names and icons per culture.** As the units have per-faction names
(`UNIT_NAMES`), the chains get per-culture names and icons in `west.gd`
(`CHAIN_NAMES` by culture; the default the chain's own): natives: Barracks
"War lodge", Range "Hunting ground", Workshop "Canoe yard", Market "Trading
post", Walls "Palisade" (the walls' kit pieces are already palisade at
level 1), Farm "Milpa" (Itza) / "Gardens" (Miskito). The build panel, the
town plan's kit pieces (`build.py` pieces already pick by culture), the
build icons (`ui_icons.gd`: a lodge, a bow, a canoe, a post) and the unit
book's "needs" texts read the culture's names; Rome and the Europeans
unchanged.

**The Itza: escalade and fire.** *Scaling poles*: a siege equipment row
(the ladders' rules: `Scenarios` equipment, the escalade `_escalade`,
`ST_LADDER`) made at the War lodge 2 rather than a Workshop, carried by any
foot unit of the natives, two per party, climbing at 70 % of a ladder
party's rate and planted in half the time; cost 60 % of ladders. The Holcan
(tier 2 heavy) are the AI's storming party by `_solidity`. Fire arrows stay
at Range 2 (Hunting ground 2).

**The Miskito: the back door.** *Torch raiders*: a new West row in the
`siege` line in place of the wagon (the Miskito keep no wagon: they forage;
`"siege": ["torch_raiders", "", ""]`), tier 1, War lodge 2: 60 light shock
foot with axes and torches, speed as warriors, poor in the open (melee
below warriors, no armour); abilities: *batter* on a gate or a palisade
stretch (the siege guns' batter order, `AB_BATTER`, given a melee form: the
unit at the gate strikes it for `m_obj` 120 a round, a palisade stretch
`m_obj` 80, stone walls nothing), and *fire pots* (`AB_GRENADE`'s path with
the fire kind: thrown at a held house or a shut gate within 20 m, lighting
it at once under the burning-buildings rule; 2 pots a man). The AI's storm
reads torch raiders as a ram (docs/AI.md 3.11 `_assign_equip`: the gate's
party) and as grenadiers for the held houses (AI.md 39). English guns come
through the alliance's call to arms as they do now.

**Measured.** `tests/defend_probe.gd` and `west_walls` with a Miskito and an
Itza attacker added to the plan (today the plan has none); the West
campaign sim on 72 seeds (the natives' eliminations and the towns they
take). Open after: the harbour assault (canoe raiders landing at the quay
inside a port's walls during an assault: a town-map scenario change) and
the lake of Tayasal (its land assault a boat landing, as in 1697).

### Buildings a faction can use, and the natives' buildings (as built, 2026-10-29)

**The rule.** `CData.chain_levels(f)` (cached per faction, cleared by `use_pack_script`) is the highest level of
each chain faction f can build. A level L of chain c is offered when a roster row of f needs `[c, L' >= L]`
(`CData.needs_all(key)`: every `UNIT_NEEDS` entry of the row, else its line's chain at its tier or `ART_LEVEL`,
the same numbers as `CRules.needs`), when a character f may raise needs it (`CHAR_NEEDS` with `CHAR_FACTIONS`:
the natives' shaman, Barracks 1) or an `AMMO_AVAIL` row for f does; the Farm, Market, Walls and the Shipyard are
offered at every level to everyone (the Shipyard still only at a port) and level 1 of a chain is reachable
wherever a higher level is. `build_info` refuses a level above the cap with `{"why": "nothing of yours needs
it", "max": 1}` (after "fully built", before the slot / money checks) and carries `"unlocks"` for the next
level (`CData.chain_unlocks(f, c, level)`): the unit rows and characters of f whose requirement on the chain is
exactly that level, then `"ammo:<kind>"` for each ammunition row. Iterated in `LINE_ORDER` and roster order, no
Dictionary iteration in rules code; no state change. **Which factions:** the cap applies to the factions a pack
lists in `CHAIN_CAP_FACTIONS` (west.gd: `itza`, `miskito`). Applied to everyone the derived caps are not full for
Rome (Rome's Stables 2 of 3 and Range 2 of 3 for factions without elephants / the tier-3 range) nor for the West's
Europeans (Barracks 3 only for England's grenadiers, Range and Stables 2): the owner wanted the natives cut, not
the others, so every other faction, the Brethren and all of Rome keep every level (Rome's pins do not move). The
campaign AI reads the same list: a build-up goal (`_buildup`) for a chain the faction has no use for is skipped,
and a level above the cap is clamped to it, so a capped goal never holds the later goals (Workshop, heroes);
the `want` lists already skip what `build_info` refuses.

| Faction | Barracks | Range | Stables | Workshop | Farm, Market, Walls, Shipyard |
|---|---|---|---|---|---|
| Itza | 2 (Holcan) | 2 (fire arrows) | 0 | 1 (the wagon) | 3 |
| Miskito | 1 (a Barracks 2 comes with the torch raiders) | 2 (poison arrows) | 0 | 1 (the wagon) | 3 |
| every other faction, Rome | full | full | full | full | full |

The caps stop new building only: a building a faction starts with or takes stays (a captured Barracks 2 shows
as "(full)" in the panel).

**Names and icons.** `CHAIN_NAMES` in west.gd (culture -> chain key -> [name, short, icon]; the natives'
culture is `CELTIC`) and `CHAIN_NAMES_F` (faction key over it: the Itza's Milpa, the Miskito's Gardens);
`CData.chain_name(c, f)`, `chain_short`, `chain_icon` fall back to the chain's own (so Rome, the Europeans, the
Brethren and independents are unchanged). War lodge / Lodge (icon `lodge`), Hunting ground / Hunting (`hunting`),
Canoe yard / Canoes (`canoe_yard`), Trading post / Post (`trading_post`), Palisade (`palisade`, the existing
stakes glyph), Milpa / Gardens (`farm`). Read by the build popup, the settlement panel's building list and
tooltips, the city card's chips (short name while building), the "built" event, the unit book's "needs" line and
the ammunition's "who, building level" line (`unit_entry.gd`), the recruit rows' "needs ..." reasons
(`CData.local_text(why, f)`; the rules keep the chains' own words in `recruit_check`) and the roster page's
"Tier n (Building n)" lines. How to play names "barracks (the natives' war lodge)" once.

**The build popup says what a level unlocks.** Under each row: "Unlocks: Musketeers, poisoned arrows" (the
faction's `unit_name`s and the ammunition's names) from `info["unlocks"]`; a level that unlocks nothing says its
effect ("Effect: faster replenishment" for the four military chains, else the first clause of the chain's text:
income, growth, the walls); a row at the cap reads "(full)" and "Nothing of yours needs a higher level". The
button's tooltip is the chain's text plus that line. A chain with no level for the faction and none built is
not listed (the Miskito see no Stables).

**Measured** (West campaign sim, 72 seeds x 60 turns, base 28f5253 against after):

| | format 6 before | format 6 after | format 10 before | format 10 after |
|---|---|---|---|---|
| eliminations (per seed) | 51 (0.71) | 53 (0.74) | 59 (0.82) | 59 (0.82) |
| battles (per seed) | 4035 (56.0) | 4040 (56.1) | 3413 (47.4) | 3413 (47.4) |
| by faction: Brethren / Miskito / Itza / Dutch / English / French | 16 / 19 / 5 / 6 / 3 / 2 | 17 / 19 / 6 / 6 / 3 / 2 | 24 / 18 / 12 / 1 / 1 / 3 | same |
| natives alive with Stables / Range 3 | 0 / 0 (Itza 1 seed of 72 at f10) | 0 / 0 | same | same |
| Miskito alive with Barracks 2 (seeds) | 10 | 4 | 12 | 3 |
| Miskito / Itza Workshop 1+ (seeds alive) | 38 of 53 / 48 of 67 | 38 of 53 / 47 of 66 | 40 of 54 / 46 of 60 | same |

The AI never built Stables or a Range 3 for the natives (their mixes have no horse, the Range build-up goal is
2); the cap is for the player, and the AI's change is the Miskito's Barracks 2 (the ordinary want list upgraded it, now refused). Format 6 pins: unchanged. Format 10: seed 2 moves (`e5625ecc` -> `a89c63d6`); the other
five are as before. Rome `== sim:` and `== sim10:` equal the pins. Another agent's terrain pass moves the West
pins again; re-pin on the merged tree.

### Native siege (as built, 2026-10-29)

The plan's "The Itza: escalade and fire" and "The Miskito: the back door" (the sim rules: docs/design/siege_and_towns.md
"Native siege: scaling poles and the melee batter (as built)"; the row: docs/design/battle_sim.md "Native siege: the torch
raiders (as built)"; the AI: docs/AI.md 45). No state format change.

**Scaling poles.** `CBattle.siege_equipment` adds `"poles": POLE_SETS` (2) to an assault on walls (level 1+) by a faction of
`CData.POLE_FACTIONS` (west.gd: `itza`, `miskito`) that holds a building of `CData.POLE_NEEDS` (`[BARRACKS, 2]`, the War
lodge 2) in any region (`CBattle.poles_of`), on arrival too (no siege needed), beside the ladders, the ram, the mantlets
and the towers a siege builds as for anyone. Where the plan was silent or could not apply: ladders cost nothing in the
campaign (they come with siege turns; the plan took them for a Workshop item), so the poles' "60 % of the ladders' cost"
has nothing to scale; they are what a native army cuts on the march, hence "on arrival". "Two per party" is two poles to
a set (a ladder set has five), the party's climb at 70 % of a ladder party's rate. The natives keep the ladders and the
ram a siege builds (they had them before; poles are taken up after them). The formula's kit (`kit_of`) counts poles as
ladders: WALLS_PCT_WEST's kit 0 and kit 1 columns are equal, so the auto-resolve does not move. The siege panel's line
adds "Scaling poles: 2 sets (from the war lodge)"; the battle screen lists them; the unit book's Settlements page has a
paragraph; the custom battle has a Poles toggle (the West).

**Torch raiders.** The Miskito's `siege` line is `["torch_raiders", "", ""]` (the wagon gone: they forage), the row
needs `[BARRACKS, 2]` (`UNIT_NEEDS`), so `CData.chain_levels` gives the Miskito Barracks 2 (was 1) and no Workshop (was
1: the wagon was the only row that needed it; a Canoe yard a region already has stays). The Itza keep the wagon and
cannot raise torch raiders (not in their roster). `UNIT_NAMES`: "Torch Raiders" / "Torches". Mix: `siege` 5 (light 44 ->
39). The campaign AI's wagon rule takes only a wagon from a siege line (the Miskito's would have been the torch raiders).

**Measured.** West campaign sim, 72 seeds x 60 turns (seeds 1000 + 77 n), d963579 against this build (the natives'
captures from the turn events: "captured" with the native the new owner):

| | format 6 before | format 6 after | format 10 before | format 10 after |
|---|---|---|---|---|
| eliminations (per seed) | 53 (0.74) | 49 (0.68) | 59 (0.82) | 63 (0.88) |
| battles (per seed) | 4040 (56.1) | 4120 (57.2) | 3413 (47.4) | 3548 (49.3) |
| by faction: Brethren / Miskito / Itza / Dutch / English / French | 17 / 19 / 6 / 6 / 3 / 2 | 17 / 18 / 5 / 2 / 4 / 3 | 24 / 18 / 12 / 1 / 1 / 3 | 27 / 21 / 12 / 1 / 2 / 0 |
| towns taken by the Itza / the Miskito | 606 / 250 | 593 / 232 | 371 / 178 | 360 / 179 |
| towns the Itza / the Miskito lost | 256 / 202 | 232 / 190 | 183 / 133 | 181 / 142 |
| native assaults (won): Itza / Miskito | 78 (59) / 44 (28) | 81 (60) / 30 (19) | 88 (64) / 22 (17) | 88 (59) / 27 (19) |
| Miskito alive with a War lodge 2 / a Canoe yard (seeds) | 4 / 38 of 53 | 7 / 4 of 54 | 3 / 40 of 54 | 8 / 6 of 51 |
| torch raider units at the end (seeds with any) | 0 | 13 (5) | 0 | 13 (5) |

Within the seeds' noise everywhere: the campaign never fights the sim (the auto-resolve reads the rows' strength and the
kit, which the poles do not move), and the Miskito AI rarely builds the War lodge 2 that unlocks the torch raiders (7 of
54 seeds); the Workshop it no longer builds is the clear change.

Battles (tools/balance `native_walls_itza` / `native_walls_miskito`: the 16 Spanish towns of west_walls x walls 0-2 x 16
seeds, `tests/town_balance.gd --att=itza|miskito`, the West set defending): **unfinished.** Itza before (d963579, storming
bare): 668 of 768 battles, attacker won walls 0 / 1 / 2 89 % (202 / 228) / 82 % (183 / 224) / 37 % (80 / 216). After: 24
battles (Havana walls 0-1), identical to before on those seeds. The Miskito plan was not run. On these plan towns walls 1-2
have no outer wall (the fort is left be in these sets), so the poles cannot bite; the torch raiders' pots (held houses) can.
To finish: `measure.py` both plans on this tree and on d963579 (the probe file copied there).

**(2026-10-31) The walls measure finished, and a stretch battered.** Both plans now target the six walled native towns
(Tayasal, Cabo Gracias, Natchez, Choctaw, Valladolid, Darien; their oppidum plan has an outer wall, a timber palisade at
walls 1, stone at walls 2) x walls 1-2 x 16 seeds, the West set defending. Itza (poles, no ram): walls 1 / 2 58 / 4 %
attacker wins, 4.7-10.5 / 11.8-15 min to decide, the gate never down at walls 2 (they climb or fail). Miskito (poles
and two torch raider units): 16 / 5 % before the AI change, 18 / 5 % after it (docs/AI.md 51: a second torch raider
unit, or one beside a ram or a burning gate or idle 40 s at the gate, batters the nearest free palisade stretch; a
breach in 16 of 96 walls-1 battles, each before the gate; within the interval). The Miskito storm is weak against the
equal-price Spanish set (Darien 62 %, Natchez 0 %); the campaign never fights it (auto-resolve), so this is a reading
for the owner, not a lever pulled.

**Canoe yard moved to the Shipyard (2026-10-29, owner: "If we have nothing to build in the Workshop then it should go away ... it should come with what we need for Canoes").** The natives' Shipyard is the Canoe yard (the war canoes already launch from it); the Workshop, which only the Itza keep for the wagon, is the Craft house. Data only (`CHAIN_NAMES`); no rule or pin moves.

**Native vessels (as built, 2026-11-01; owner: "There is no need for level 2 and 3 shipyards for the natives, unless we can come up with some heavy vessels for them", then: build them, with the naming fix).** Before, the natives built only the war canoe (yard 0) and the Miskito the sloop (yard 1); the Canoe yard 2 and 3 gave them faster repairs alone. Now (`campaign/data/west_ships.gd` ROWS, `sim/sea_types.gd` rows appended after the corbita so every older row keeps its index):

| Hull | Who | Cost / upkeep | Guns / hull / crew | Pace | Carries | Yard | Storm % | Launch | Power |
|---|---|---|---|---|---|---|---|---|---|
| Piragua (the Kalinago sailing dugout) | Itza, Miskito | 260 / 10 | 1 (a swivel) / 22 / 60 | 330 | 1 | 2 | 30 | 2 | 44 (formula) |
| Great canoe (the Maya trader of 1502) | Itza | 420 / 15 | 0 / 30 / 80 | 300 | 2 | 3 | 35 | 1 | 140 (row) |
| Fire canoe | Itza, Miskito | 90 / 4 | 0 / 8 / 10 | 320 | 0 | 2 | 45 | 2 | 80 (row) |
| Brigantine (the existing row) | + Miskito | 500 / 25 | 14 / 45 / 90 | 370 | 2 | Miskito 3 (`yard_f`), the rest 1 | 12 | 1 | 203 |

All three dugouts are coastal and rowed. Sea sim: piragua len 18, beam 3, vmax 100, turn 110, 1 gun of 3 at 120 m, hull 180,
crew 60, board 160; great canoe len 24, vmax 92, turn 100, hull 260, crew 80, board 150, no gun; fire canoe the fire ship's
numbers in a dugout (len 13, beam 3, rowed, crew 10, hull 60, `fire` 1; irons, tack and rig 0 as every rowed row, where the brief
said "as the fire ship's": a rowed boat has no no-go zone). Boarding uses the crews table (`SEA_CREWS`: the Itza 115 %, the
Miskito 120 %) as for the war canoe.
- *The ally condition.* A ship row may carry `"ally"`: faction key -> faction keys; that faction builds the hull only while it
  trades with or is allied to one of them alive (`CDip.ship_why`, the treaty lines' own test `_trades_with`, shared with
  `line_why`); the row's other factions are not bound. The brigantine's is `{"miskito": ["england"]}` (the Miskito start allied to
  England). Checked at order time (`CFleet.ship_check` after "your people do not build these": "needs a trade agreement or
  alliance with England"), in `CFleet.buildable` (the AI's list) and in the AI's yard raise. Before format 10 (no treaties)
  nothing is refused, as for the treaty lines. `"yard_f"` (faction key -> level, `CData.ship_yard`) gives the Miskito's
  brigantine the Canoe yard 3 while England's stays at the Shipyard 1.
- *Batches.* A queue is one kind: `ship_check` now treats a different key in the queue as limit 1 (two piraguas a turn, but a fire
  canoe behind them waits a turn; before, a mixed queue of two multi-launch kinds would have passed the smallest batch).
- *The sea sim.* `ST.is_galley` excludes rows with `"canoe"` (the four dugouts: rowed, no gun or one, but never Rome's war galleys:
  no cruise stroke, no galley AI or orders bar), so the great canoe and the fire canoe sail and fight as the war canoe always did.
  The fire canoe is a fire ship by her `fire` flag (`ST.is_fire`, which the sim and its AI already read); a rowed fire ship is
  lit at 80 m and abandoned at 25 m (`FS_LIGHT_OARS_M`, `FS_ABANDON_OARS_M`; sea.md "Native vessels"). The one hull-key compare
  in the sim, `_masts` (the deck melee's mast cells: "sloop" one mast, "brigantine" or "fire_ship" two), is now the row's
  optional `"masts"` (`ST.masts`: 1, 2, default 3, rowed 0); it meant the rig (one, two or three masts), not a class of hull.
  The view's rig drawing reads the same (the fire ship now draws her two masts, as the sim always counted them).
- *Names (view only).* The natives' Workshop is the Craft lodge (short Craft, the Workshop's icon); their Shipyard stays the Canoe
  yard (short Canoes, `canoe_yard`) with its own text through `CData.chain_desc` (a fourth field of a `CHAIN_NAMES` entry): what
  each level builds. The Shipyard texts on the panels (the ship dialog's title, tab and line, the section head, the ship rows' sub
  line, the "needs Shipyard n" refusals through `local_text`, the command bar's action) read `chain_name`; the command bar's
  building chips read `chain_short` ("Canoes 2", "Craft 1"), and the shorts still wider than the 52 px chip a chip word
  (`CommandBar.CHIP_SHORT`: Shipyard "Yard", Workshop "Works", Barracks "Barr.", Hunting "Hunt", Palisade "Stakes"; measured: "Shipyard 2"
  56 px, "Workshop 1" 64, "Barracks 2" 56, "Hunting 2" 52, "Palisade 2" 54 against 50 of room), the tip keeps the full name; the build dialog's
  Shipyard row says "Unlocks: Piragua, Fire canoe" (the faction's rows needing that level, a treaty condition named); a ship row
  with an `ally` for the buyer says "while trading with or allied to England". How to play's Three ways line names the new hulls.
- *Power* (`CFleet.ship_power` at full strength): war canoe 38 < piragua 44 < sloop 122 < great canoe 140 < brigantine 203;
  fire canoe 80.
- *AI* (docs/AI.md 52): the natives value warships by that power (piragua over the war canoe), transports by places (the great
  canoe); their best port's yard goes up a level when a better hull needs it (`AI_YARD_UP`; paid from the treasury above half
  the reserve); fire canoes are never bought by
  the campaign AI (as fire ships) and are sailed at a mark by the battle AI through the flag.
- *The Canoe yard needs no town (owner, 2026-11-01: "a dugout yard is a beach and a shed").* `CRules.build_info` skips the
  settlement-level rule (a level n building needs a settlement of level n - 1) for the Shipyard of a faction in
  `west_ships.gd` `YARD_ANY_LEVEL` (the Itza and the Miskito; `CData.yard_any_level`): a native village port raises its Canoe
  yard to 3. Everyone else's Shipyard, and every other chain, keeps the rule.
- *Measured* (`tests/campaign_sim.gd`, West, 72 seeds x 60 turns; format 6 / format 10; before the native vessels -> as built):

| | before | as built |
|---|---|---|
| Itza alive at 60 | 65 / 60 | 62 / 63 |
| Miskito alive at 60 | 60 / 65 | 66 / 63 |
| Itza best Canoe yard 0/1/2/3 at the end (alive) | 36/6/23/0 and 41/2/17/0 | 20/1/26/15 and 30/1/17/15 |
| Miskito best Canoe yard 0/1/2/3 | 5/54/1/0 and 1/61/3/0 | 4/8/46/8 and 2/11/46/4 |
| Itza launched: war canoe / piragua / great canoe | 790/0/0 and 540/0/0 | 388/41/8 and 349/41/10 |
| Miskito launched: war canoe / sloop / piragua / brigantine | 405/378/0/0 and 376/340/0/0 | 410/348/15/6 and 345/281/15/2 |
| Sea battles a seed | 26.7 / 24.8 | 26.9 / 24.8 |

  An intermediate build (yard raise paid from the whole treasury) had the Miskito alive 50 of 72 at format 6; paid from the
  treasury above half the reserve (as built) 66. The West pins move (the natives' purchases); Rome's are unchanged. The rules
  hash moves; no state shape changes (a ship is its key), no `CState.VERSION` bump.


**The raiding lessons and "Three ways to play" (2026-10-30, view and words; `Tutorial.TURNS` 13 is the one value the rules read).** The
owner: "We should teach raiding stances for the army and the ships, we should also have a section that talks about Asymmetry and the
benefits of the nations. I think Pirate vs Native vs European should mostly suffice."
- *Three lessons after the sail, Goals is lesson 13* (`Howto.LESSONS` 13, `Tutorial.DONE_STAGE` 14, the AI's shield 13 turns, "Lesson n of 13").
  **The order is landing, raid at sea, raid on land**, not the plan's raid first: a fleet that raids sails onto a lane and holds it, far
  from any beach, so a raid ordered first would leave the army aboard with no landing in reach; a landing first leaves the fleet empty
  beside the coast and the army ashore, and then both raids can be ordered. The lesson 9 sail waits a turn for the army to board (the
  fleet-waits rule), so lesson 10 begins with the fleet still in port and the army aboard; every coast of the profiles' `raid` region is
  within one turn of both seats' ports (probed: reach turn 0 from Port Royal and from Leogane), so one tap on a lit beach replaces the
  stored voyage with a voyage to a land cell, which lands the troops on arrival (`CFleet.plan` with `landing`; it is an `fmove`, not a
  `land` order, which needs the fleet beside the beach already). `Tutorial.landing_cell()` is that beach: of the raid region's `MapView`
  beach cells that are `land_ok` and touch a sea cell of this turn's reach (`CFleet.reach` 0), the one nearest the town.
- *The raid region.* `PROFILES[i]["raid"]` = `santiago_de_cuba` (the region Oriente, Spanish in the West start; New Spain is at war
  with both seats). Not Tortuga Coast (`port_de_paix`, the Brethren's), not Cibao (unowned for England alone, France's target in the hot
  seat, taken at lesson 6) and not Santo Domingo (unowned in the West start). The lane lessons need nothing from the profile: lanes 28,
  29 and 37 to Santiago de Cuba are hostile to both seats and in reach, and `best_raid(fleet)` picks the richest.
- *Objectives* (table above). Lesson 11 counts only an `fraid` order: after the landing the fleet already lies on a hostile lane, and
  `CLanes.raiders` would make the lesson met before the player did anything. Lesson 12 reads the stance order (`{"t": "stance", "a", "s": 4}`)
  or `CState.stance(a) == 4`. `skip()` does each: `set_fmove` to the landing cell, `set_station(fleet, best_raid(fleet), -1)`,
  `panels._set_stance6(army, 4)`; lesson 9's skip now embarks at once for an army in port (it only knew the march to the beach).
  Words: `lesson_10` .. `lesson_12`, `lesson_10_done` (the met line); the closing card gains "Every nation plays its own way: see Three
  ways to play in How to play."
- *A battle may arrive.* The tutorial's shield covers declared wars only; in the test run Spain attacks the empty Sevilla la Nueva (English since lesson 6)
  at the end of lesson 11's turn, a pending battle that hides the card until it is fought or auto-resolved (the test auto-resolves it).
- *Three ways to play* (the ninth How to play section, `SECTIONS` id `ways`, lines `ways_1` Europeans, `ways_2` Pirates, `ways_3` Natives; the
  title menu, the campaign Menu and the battle Menu all list `SECTIONS`). Every claim is a rule as built: the Europeans (no building cap,
  `chain_levels` full; frigates for all, ships of the line for England and the Dutch only, Spain's galleons carry six, `west_ships.gd`; the
  natives have no gun rows); the Brethren (`CSea`: lane raid `LANE_RAID_TAKE`, sack by policy: `SACK_TURNS` 3 of the town's income and
  `SACK_TREASURY_PCT` of the owner's gold, every building a level down, haven crews `HAVEN_PCT` 20 % cheaper up to 45 % with infamy, `INFAMY_SACK`
  12 a sack, `MARQUE_TURNS` 12 and `MARQUE_BONUS_PCT` 50, "pirates live on while they have a ship"); the Itza and the Miskito (cover on their
  rows, `CHAIN_CAP_FACTIONS`: no Stables, War lodge and Range level 2, `POLE_FACTIONS` scaling poles from a War lodge 2, the Itza's Holcan and fire
  arrows, the Miskito's torch raiders and poison arrows, war canoes land a war party on any beach, `TREATY_LINES` the Miskito musket line).
- *Tips.* `tip_raid` (an army of ours that can raid is selected, or its region is: the Raid action is offered) and `tip_lane_raid` (a
  fleet of ours with a lane to raid is selected), `TIP_KEYS` ten; both wait while the tutorial runs, like the rest.
- *Tests.* `tests/tutorial_test.gd` plays lessons 1 to 13 for England (10: the pointer on the fleet and then the lit beach, the landing;
  11: the pointer on the fleet's Raid button, pressed; 12: the region's Raid button, pressed), a skip run for lessons 9 to 12 from lesson 9,
  France's three objectives on its own orders, nine sections and the `ways_*` lines. `menu_test` expects nine sections.

### Ambush battles (as built, 2026-11-01)

The owner, on a phone: "during an ambush we need to work on the spawn points. One side looks like a bunch of squares and the
other shows placing units right on top of the enemy. We should be able to place in both sides of a narrow marching army with
ambushes." Two faults: `Scenarios.field_zones` gave every unit outside its side's band a box of its own (a flank group was a pile
of squares), and a flank group stood inside the other side's half, so the enemy could deploy onto it.

- **The rule** (`CBattle.is_ambush(st, b)`, a pure function of the state): a field battle (`kind` "field", not a settlement's, not
  a river crossing) whose lead defending army (`b["def"][0]`) is caught on the march: its stance is `ST_FORCED`, or it moved into
  this region this turn (`moved` set and `from` a region other than this one). `moved` and `from` are cleared in `end_turn`, so
  they are exact for the turn's battles; `dest` is not used (it is cleared on arrival). Forced-march morale
  (`FORCED_MORALE_PCT`) applies as before.
- **The column.** The map's axis is horizontal (`y = height / 2`). The defenders (reinforcement armies keep their edge
  placement) stand in column of march, `files` 4 for foot, 3 for cavalry, the engines and wagons as they are, 12 m between units
  (depth = ranks x rank spacing), facing along the axis, heading east unless the lead army came from the east
  (`CData.sector` of its `from` region 1-3: west). Order from the van: half the cavalry (one cavalry unit if there is one), the
  skirmishers, the line infantry, the wagons, the artillery and the general, the rear guard (the last line unit, the rest of the
  cavalry). Width = max(560, column + 2 x 120 m), no 960 m cap; height as before. 
- **The attackers** keep today's line (`_layout`, 100 m off the axis, missile screen 85 m) facing the column: north of it for an
  approach from the north (sectors 7, 0, 1), else south; from the east or west (sectors 2, 6) the line is split in two halves, the
  first half of the line units north and the second south, the cavalry and skirmishers all south.
- **Zones.** The scenario key `"ambush": <sim side>` names the defenders' side. `field_zones` gives that side one strip
  (`|y - height / 2| <= 40`, the whole width) and the attackers two bands, north and south, each from 70 m off the axis to the
  map edge (the player places on both sides of the column). In every battle, plain or ambush, `field_zones` now merges the
  padded (40 m) boxes of a side's units outside its band that touch into one box per group, and cuts each rect (band, strip,
  box) so it holds no enemy unit: the padded box of every enemy unit it reaches is taken out (left / right / above / below
  pieces, slivers under 40 m dropped). The rule is integer maths over arrays in unit order.
- **The sim.** `BattleSim._setup_deploy` does not let the battle AI deploy the ambushed side at tick 0 (its column stands as
  placed, as on settlement maps); a human on that side may still place units inside the strip. The key is read only there.
- **Not changed.** No `CState.VERSION` bump (the state's meaning is unchanged), the rules hash moves (`campaign/` changed),
  scenarios without the key hash as before; auto-resolved battles (the formula) never build the layout.
- Tests: `tests/ambush_test.gd`; shots `tests/amb_shot.gd` (top and oblique deployment views).
