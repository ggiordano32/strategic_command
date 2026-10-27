# Strategic Command — Status and Handover

Last updated: 2026-10-22 (docs split: this file is now the short current state; the dated rows and paragraphs moved verbatim to `docs/history/`, `docs/DESIGN.md` is an index over `docs/design/`). Read this first, then `docs/DESIGN.md` (the index) and the area file you need under `docs/design/`, and `CLAUDE.md` for working rules. Update this file whenever a milestone lands or the plan changes: add the new dated row at the top of the newest `docs/history/<month>.md` table, and change only the current list, the open items and the pins here. `python3 tools/docs_check.py` proves a docs move lost nothing.

## What this is

A 2D, top-down, co-op grand strategy game inspired by Rome 2: Total War, in
Godot 4 (GDScript), played in a browser on phones and desktops. Two friends
play an asynchronous turn-based campaign against AI factions and fight
real-time battles solo or together. Built for two players first; accounts,
anti-cheat and original art only if it proves fun.

## Where we are headed

**The goal (agreed 2026-10-16).** The real game is the Caribbean and the
Americas. Rome was the framework for getting the control system right and
stays in as a nod to Rome 2 and familiar content to play with friends;
Creative Assembly already did Rome well, so depth goes into the Caribbean
campaign first, and Rome gets its own polish / detail pass only after the
Caribbean details are worked out. Engine fixes (pathing, jitter, city map
generation, cover) flow back to the Mediterranean campaign for free.

1. **The Caribbean pack, playable:** the 45-turn Brethren story to its
   three-way ending, co-op optional, sea battles with live co-op, forts
   with an inside. Done when the owner finishes the story once as the
   Brethren.
2. **Rome, finished, as the control check:** a full co-op campaign on
   phones to a decisive end without a bug that needs the developer; the
   device pass and the balance numbers serve this.
3. **Someone outside plays it:** a named public build, guided first turns,
   a settings pass. Done when a stranger reaches turn 10 unaided.
4. **Distribution D (built 2026-10-17):** the game on itch.io (web +
   desktop), the game server as a Docker image players can run, "Host a
   server" in the desktop build; browser players need HTTPS servers (see
   "Distribution (D)" below).
5. **A navy for Rome (agreed 2026-10-22, after the Caribbean polish):** the
   Rome pack has no fleets. Galleys in the sea sim (trireme / quinquereme /
   lembos: oared polars that barely care about the wind, ramming, the corvus
   for boarding, an oared-ship AI), Rome fleets / ports / transports on the
   campaign reusing the Caribbean fleet machinery, Rome sea battle maps. The
   ocean trade lanes (drawn with the map work of 2026-10-22; their trade,
   raids and blockades built the same day, row "Lane trade, raids and
   blockades") are written pack-agnostic so Rome's navy uses them as the
   Caribbean does. The plan (R1 galleys in the sim, R2 Rome fleets on the
   campaign, R3 maps) is `docs/design/sea.md` "Rome's navy (plan)"; R1
   started 2026-10-23; R3 built 2026-10-24.

## The current list

Thursday's list (2026-10-22), all landed on 2026-10-22 and committed (the last three in the night of the 23rd); the original wording is in `docs/history/overview.md`.

| # | Item | State |
|---|---|---|
| 1 | Relief map city markers, banners at towns, less fog off our own coast | Landed (`8c648f7`): history row "Overworld markers, banners at towns, coastal sight" |
| 2 | Roads for the West, the pathing detour rule, ocean trade lanes on both maps | Landed (`8c648f7`): row "West roads, sea lanes as routes, the pathing detour rule" |
| 3 | Sea battle look (bathymetry water, wind crests, foam, beach and cliff shore), Douse | Landed (`1cfff51`): rows "Sea battle look", "Sea battles: Douse" |
| 4 | Faction crests through Klein 4B from the drawn marks | Landed (`cac8cda`): row "Faction crests" |
| 5 | UI theme pass 2 (battle HUD, sea screen) | Landed (`3d71680`): row "In-game UI theme, pass 2" |
| 6 | Rome walls 1-2 | Landed (`07b9d27`): row "Rome walls 1-2 balance pass" |
| 7 | Same day, owner requests: waypoints (`f690bdf`), reading a town battle (`4fc9b9d`), men turn to their march (`1431401`), beaches and cliffs (`bd50be8`), table sea on the bathymetry (`53da70e`), ships popping while panning (`80a4376`), ambient beds (`8e7986c`, `62e1969`) | Landed |
| 8 | Auto-resolve refit (the formula fitted to fought sieges and field battles) | Landed (`c94d4a9`): row "Auto-resolve refit" |
| 9 | Lane rules: trade along the sea lanes, raiding and blockading (`fraid`, `fblockade`), the flota on its lane, the AI's raids | Landed (`630a398`): row "Lane trade, raids and blockades" |
| 10 | Campaign AI odds as win chances after the refit (attack 45 / 55 / 65 %, retreat below 20 / 30 / 35 %) | Landed (`68a3016`): row "Campaign AI odds as win chances" |

Night of 2026-10-23 (all committed, live in build 20261023T121643Z): the owner's two phone bugs (`5a01126`), side-step and back-step frames (`8d63588`), the input test's footprint steps repaired (`ec36343`), the balance harness (`483dbe2`), and the Rome navy R1 galleys (`ea6bb14`) and R2 Rome fleets (`11297d9`) with the AI's garrisons against landings (`20e1ede`, `0886d03`).

Next, in order (the open items of the list; detail in the areas below): (00) roles and abilities (agreed 2026-10-23, `docs/design/battle_sim.md` "Roles and abilities (plan)": step 1 role tags, badges, filters, book, the Roles page (built 2026-10-23); step 2 the behaviours in the sim (built 2026-10-23: skirmishers' loose order and woods drift, the ability table with Auto / Hold / Use now by `ORDER_ABILITY`, pistols at contact and their reload rotation, grenades' Auto trigger, the caracole, the batter order at walls and buildings; AI knobs 283-284, docs/AI.md 36; "Roles, step 2 (as built)"); open from step 2: the asymmetry probe (`tests/asym_probe.gd`, `asym_woods` / `asym_field`) on 48 fresh seeds (seed0 16) has the natives winning 47 of 48 in the woods and the Spanish 39 of 48 in the field (the 16-seed drop 14 -> 11 was noise); to be re-read when batch 2 gives the Spanish their specialists. The AI uses Hold / Use now: built 2026-10-24 for sieges only (grenadiers Hold in the approach and Use now at a shut gate or a held building, siege batteries' batter at a held building on the storm's route; docs/AI.md 39), none in field battles, the caracole's charge flag still Easy only; step 3 the HUD's ability chips BUILT 2026-10-24 with the battle HUD pass (`docs/design/ui.md` "The battle HUD pass (as built)": `game/ability_chip.gd`, Halt / Run / Withdraw fixed, chips per role in one fixed order, More with a grid popover, the phone capsule with role glyphs, the cards' state strip, the Keys "Chips" section, `tests/hud_fit_test.gd`; open: Pistols are Auto / Hold only (the sim reads no Use now for them), field guns have no Target chip, the device check on the phone; plan was 2026-10-24, `docs/design/ui.md` "The battle HUD pass (plan)": the compact capsule with role glyphs, Halt / Run / Withdraw fixed, ability chips Auto / Hold / Use now per role, More for the overflow, the cards' state strip, hud_fit_test; the owner moved it ahead of batch 3 on 2026-10-24); chip options built 2026-10-24 (the owner: a tap on a multi-state chip opens an options popover above it instead of cycling; keys still cycle; `docs/design/ui.md` "Chip options (as built)"), (0) the Caribbean roster, batch 2 (plan 2026-10-24; sprites, the poisoned arrows and the seven rows built 2026-10-24, `docs/design/battle_sim.md` "The Caribbean roster, batch 2 (as built)": mounted arquebusiers, marines, landed naval guns, colonial militia, maroons, atlatl darts, slingers; measured 2026-10-24: the harness before / after (west_named, open_town, west_walls) identical in every cell (the plan armies field none of the new rows); the asymmetry probe on the second army pair `asym_woods2` / `asym_field2` (the Spanish with mounted arquebusiers, the natives with slingers and atlatl, 48 seeds) natives 46 / 48 in the woods, the Spanish 45 / 48 in the field (39 / 48 without the new pieces): the principle holds and the field edge grew; West AI after batch 2 done 2026-10-24 (docs/AI.md 37: the "pacing drop" 5 -> 2 eliminations on the pin seeds was seed noise, 144 seeds 89 before batch 2, 85 after; the Shipyards stand at the English and Dutch capitals; the real defect was mix lines no centre could raise taking the recruiting pick and turning into any unit, 15-71 % of the recruits; `MIX_LIVE` (id 120, Average / Skilled) picks among the lines that can be raised: 144 seeds 88 eliminations, 55.5 battles, marines and naval guns now raised; open: the Dutch seldom reach their marines' Barracks 2, pacing claims want 72+ seeds)), then batch 3, the characters (BUILT 2026-10-24: `docs/design/battle_sim.md` "The Caribbean roster, batch 3 (as built)": sea captain, privateer, missionary, shaman as West rows after the slingers, sprite sets 41-44, `CHAR_NEEDS` / `CHAR_FACTIONS` / `CChars.allowed` (Rome's six never in the West, the West's four never in Rome), the AI's sea captains / shamans / missionaries (docs/AI.md 38), glyphs hat / knife / cross / feathers, the book page, the custom battle toggles; West pins moved (72 seeds: eliminations 43 -> 50, battles 54.5 -> 51.8, the Dutch 1 -> 8 eliminations the one swing outside the earlier spread), Rome unmoved; the battle AI's hero posts by `au_roles` and the parley pick by the bonus built 2026-10-24 (docs/AI.md 39); the probe battles done 2026-10-24 (the shaman narrows the field edge 45 -> 37 of 48, the missionary forces surrenders in 20 of 24, the sea captain neutral ashore; battle_sim.md "Batch 3 measured"); open: the missionary has no public-order effect (the campaign has none), pacing wants a second look at the Dutch); batch 1 built 2026-10-23 (agreed 2026-10-23: grenadiers, dragoons, coureurs des bois, boarding grenadiers, canoe raiders, holcan warriors and mortars; `docs/design/battle_sim.md` "The Caribbean roster, batch 1"), (1) the Rome navy's R3 BUILT 2026-10-24 (`docs/design/sea.md` "Rome's navy R3 (as built)": props, the lane check `tests/sea_lanes_test.gd`, oared map sprites; open: the first-mover edge of identical fleets is index order in the sim, not the ns geometry, a sim pass; Gades - Tingis has no sea cell), (2) device checks on the Tab S7 / phone of the week (fog look and markers, sea top bar, Game server page, `?prof-tap=3`, waypoints, the Paths overlay, crests, the raid / blockade taps and the raided-lane look), (3) Hunyuan characters wired in, (4) sea balance follow-ons, (5) auto-resolve refit to pass T and the Rome walls results.

## Open items by area

One bullet per open item pulled from the rows' **Open:** texts; the bracket names the archive row (or paragraph) that holds the detail, in `docs/history/2026-10.md` unless it says `overview`. Bullets about "not played on a phone / tablet" are collected under Tests and devices.

### Battle sim
- Waypoints: no keyboard key; the Orders overlay (all units) does not draw chains; three-finger group moves still replace. [row "Battle waypoints"]
- Men turn to their march: engines and routed men keep the sim's facing. [row "Men turn to their march"]
- Mid-battle reinforcements: ambush stance; no cap on the number of armies in a battle; no choice of which units wait. [row "Mid-battle reinforcements"]
- The column on the walk: the residual 1.7 : 1 exchange; yards 5 / 6 (two wall lines on one walk) still draw with no blows. [row "The column on the walk"]
- Siege towers, field works, light artillery need tuning (tower pace and start, every field-works number, every number of both artillery rows, the AI cavalry does not avoid stakes). [rows "Siege towers", "Field works and the fortified camp", "Light artillery"]
- Cover and sight: smoke does not block sight; the AI does not remember last-seen positions or hold fire for an ambush; artillery shot ignores cover; cover by the unit's centroid. [paragraph "Slice 2b, cover and line of sight"]
- Lanes: men in a lane still walk to a new slot after each death; the stragglers' routing takes the street graph's 3 m lines; the watchdog may repeat a stuck move. [paragraph "Pathing pass 2, fight jitter and stuck units (phase J)"]
- Compact unit cards: the battle matchup mark (a hook in `game/battle.gd`). [row "Compact unit cards"]
- General open items still standing: iPhone determinism is not cross-checked, deferred battle features (fatigue, horse archers, a manual brace), artillery unplaytested. [overview, "### Open items"]

### Siege AI and towns

- Destruction AI (2026-10-23, landed: `docs/design/siege_and_towns.md` "Destruction AI (as built)", docs/AI.md 35): besieging batteries batter the stretch by the attacked gate until it breaches, the breach is an entry (the nearest foot go in through it), defenders leave a battered stretch and a failing building, four reserve / stack units plug the breach. rome_walls 58 / 32 / 24 -> 74 / 44 / 20 (a breach in 95 % of battles; walls 3 not up, walls 1 up 16, per-town swings large both ways: Latium walls 2 6 -> 75, Arverni walls 2 81 -> 12); west_walls 54 / 39 / 34 -> 51 / 38 / 34 with no West battering at all (the plan towns have no outer wall, the fort is left be in these sets). Walls 3 19 -> 33 on 2026-10-24 (docs/AI.md 39; walls 1 74 unmoved, walls 2 41 -> 39; west_walls identical in every cell): the guessed lever (the gate stack waiting at the shut gate) was not it, the plug takes the stack's units; the four plugs held the 12 m rubble, so at a breach in walls 12 m thick or more the last plug is a second line 20 m further in (`S_PLUG_DEEP`), and no stretch is battered whose breach's outside point lies in a tower (`S_BATTER_OPEN`, Punic towns). Open: the walls-3 endgame (a citadel shut and holding at the time limit in 8 of 24 traced battles; Carthage's Byrsa is its plaza), the Punic breach points in towers (a sim matter), the per-town swings (Sicilia walls 3 -19, Latium +38), the West fort stormed with guns, a shock role for the breach party, a player order for "batter the wall". Later: campaign repair costs for breached walls.
- The defending pike under musket fire (2026-10-27, landed: docs/AI.md 42, owner's phone playtest): the AI town defence stood at the scenario's places through the deployment (the pike 18 m inside a street mouth, about 20 m from a musket line at the front of the attackers' zone) and nothing moved a unit out of fire from shooters in the field. Now its posts are set and taken in the deployment, beyond the guns' reach from the attackers' zone, and a street unit under such fire answers from a building, charges or falls back (`S_DEF_ZONE`, `S_DEF_FIRE`, ids 290-291; Easy off). `tests/defend_probe.gd` (3 towns x walls 0-2 x 8): defenders down before contact 207 / 196 / 160 -> 52 / 44 / 52 (pikes 98 / 90 / 71 -> 0 / 1 / 1), attacker wins 22 / 20 / 11 -> 10 / 5 / 8 of 24. west_walls 49 / 37 / 28 -> 39 / 31 / 27 (walls 0 beyond the interval, toward the defender); open_town identical. Open: whether AI-against-AI walls 0 at 39 % wants the fall back toned down there; a device check.
- Rome walls 1-2: the Greek / Punic citadel fight (the plaza is the citadel), Rome's castrum at walls 2 (38 -> 9 %), gate HP at walls 2 untested, Carthage the outlier; the long runs belong on the balance harness `tools/balance`. [row "Rome walls 1-2 balance pass"]
- Forts leftovers: West walls 1 and 2 both at 41 % (45 / 35 wanted), the charger results are 30-minute draws, two bastion guns never bear on the town; no sally from the fort in every case, men in a house do not fight room to room. [paragraph "Forts leftovers"]
- Burning buildings (2026-10-24, landed: `docs/design/siege_and_towns.md` "Fire (as built, 2026-10-24)"): a timber building struck by fire arrows or javelins rolls once per 5 s window at 35 % (a fire pot lights it at once), it burns down in 90 s and falls by the collapse, the men inside lose 4 morale a second and come out to cover below 50 %, no one may go in, it lights timber neighbours (within one 2 m cell, not "sharing an edge": West houses almost never touch) 15 % every 20 s. Open town with two Itza-style fire-arrow bowmen companies added to the attackers (scratch probe, 24 battles): 2.2 houses burnt a battle (of 4 held), attackers 23 -> 22 of 24 (within noise); the standard open_town plan has no fire missiles and is unmoved. Open: the AI aiming fire at houses (attackers) and avoiding timber houses against fire troops (defenders), putting fires out.
- Plan maps: walls 3 citadels on the trace, the natives' walls 2, per-town spread (a 32-seed look at the extreme towns), `S_BEATEN_TOWN_PCT` unification with the generated maps' 35 %. [paragraphs "Balance pass on plan maps", "Fort traces from the piece"]
- Equal-force walls 3 at 12 % on the West in the earlier passes (the ring holds 0 of 8); the field AI against a charging player; the defenders' guns unguarded in the field. [paragraph "Balance pass T"]
- West towns' tick cost about 1.5 x a Rome city's per man; the hill port city's set-up is over the 450 ms mark. [paragraph "Pathing pass 2, phase W"]
- Mitred wall strips: no end-cap pieces, palisade and timber wall share the `ps_*` strip, the legacy `_west_fort` still tiles `wall_10_2`. [row "Mitred wall strips"]
- Dated seeds from the siege pass: at walls 2 a defended escalade kills far fewer defenders than before the movement build (find which movement fix changed the walkway fight). [row "Units flow into the space"]

### Sea
- Sea look: other towns' forts / batteries in sea battles; the shore foam to the owner's eye. [row "Sea battle look"]
- Per-faction unit names (built 2026-10-26, `docs/design/ui.md` "Per-faction unit names"): `west.gd UNIT_NAMES` + `CData.unit_name / unit_short`; Itza / Miskito / Brethren rows named per nation (Batab's Guard, King's Guard, Ah Kin, Sukia, Miskito Musketmen, Captain's Crew, Ship's Musketeers). Resolved 2026-10-27: the main-menu unit book (faction picker, per-faction names in small text on shared rows, unit page by faction) and the custom battle (a Names button per side: its army list and the HUD cards); Roles texts name roles, not units; the custom unit picker keeps the row names.
- Launches and boarding (built 2026-10-26, `docs/design/sea.md` "Launches per turn and boarding on arrival"): war canoes launch 4 a turn per port (`"launch"` on the ship row, `sq` is a list), a march with `"fleet"` boards on arrival (`dest_fleet`, `CFleet.boarding_cells` / `pickup_cells` for the view); the view is built (teal boarding / pickup cells, tap a fleet to march and board, grouped Shipyard queue; `docs/design/ui.md` "Boarding indicator and the Shipyard queue").
- Flight rule: gauge / camp layouts; a scripted player who never flees wins 15-19 of 24 against the AI in `order` mode (the AI's flight rule is the suspect); the AI's beat to windward stays slow. [row "Sea battle AI: the flight rule", paragraph "Sea pass 4: the leeward fleet"]
- Sea follow-ons: drop the two `online_ui.gd` gates, head-to-head humans at sea, smoke blocking aim, shore batteries, the formula fitted to fought results, balance of the deck melee. [paragraph "Sea follow-ons built 2026-10-16"]
- N2 / N2b: the AI sacks rarely, pirates seldom hold a haven late, flota interceptions are rare, storms rarely sink AI ships, salvage of wrecks, privateer captains for the nations. [paragraphs "N2 trade, blockades, the flota and the pirate loop", "N2b hurricanes, notorious captains and named treasure galleons"]
- The Rome navy (goal 5): R1 and R2 built (2026-10-23); R3 built (2026-10-24: Mediterranean props, the lane check, galley sprites on the overworld; open: the index-order edge in the sea sim (the lower-index side wins about 2 in 3 with identical fleets, sea_probe `--swap`), the Gades - Tingis lane has no sea cell, a merchantman sprite). Docking (a fleet in a port city: `docs/design/sea.md` "Docking (as built, 2026-10-23)") built (2026-10-23). ["Where we are headed", overview]
- Docking pacing (6 x 60, all Average): Docking took AI sea battles from Rome 29.8 -> 12.7 and the West 53.5 -> 30.5 a campaign (docked fleets cannot be attacked). The sortie rule (docs/AI.md 12.4, 2026-10-23: a docked fleet casts off against a fleet lying off its port with `SORTIE_ODDS_PCT` 110 of its power at Average) barely moves it, before -> after: Rome battles 47.3 -> 47.5, eliminations 10 -> 10 per 6, sea battles 10.8 -> 10.0, landings 8.7 -> 8.5, sorties 0.3 a campaign; West 50.8 -> 50.8, 1 -> 1, 27.5 -> 27.5, 23.7 -> 23.7, sorties 0.8 (hashes unmoved). The fleet off a port almost always outguns the port's fleet (in 3 of 222 Rome cases and 7 of 91 West ones the docked fleet had 110 %), so the missing battles are the enemy's attacks on docked fleets. Open: decide whether a blockader may attack the fleets docked in port (with the port's guns), or the docked side defends when an enemy enters the harbour's zone. [`docs/design/sea.md` "Sorties (as built)"]
- Lane rules: the lanes' sight (a port seeing its lane's cells within `CITY_R` + 1) is not in `csight.gd`, the raided lane and the chronicle row are shown to the owners whatever the fog; the AI raids with lone sloops and a junction raids every lane through it; a Skilled siege blockade is untested; no device look at the raid taps yet. [row "Lane trade, raids and blockades"]

### Campaign rules
- Story: effects other than crew / hull / fame / infamy go to the lead only; a divided ending; the landing sends no ship; the vote dialogs on a phone. [paragraph "Story step 3 built 2026-10-16" and the story steps]
- Raids: the AI raiding beside a garrisoned stack is legal but maybe too bold (an AI odds question). [paragraph "Raids on a player's city"]
- Roads, rivers and hills: a tap on a crossing showing its name; contact across a river edge without a crossing. [row "Roads, rivers and hills on the overworld"]
- N-player: per-army AI for AI allies on a player side; custom battles still two seats; Discord texts still say "ally". [section "Next session (week of 2026-10-13; paused 2026-10-10 midday)"]
- Campaign AI: Skilled vs Average ~47 % (AI-competency pass); Epirus's war with Rome (see Rome start budgets); the tuning backlog. [overview, "Tuning backlog"] The AI's odds thresholds against the refitted curve: done (win chances); left: the West's Skilled margin over Average is within noise and its Average pacing sits at the band's top (60 battles a campaign over 24 seeds). [row "Campaign AI odds as win chances"]
- Smaller: drag-to-exchange on the bar, punitive landing ship, West villages' map coverage, hill-city setup time, the 23 old test saves in this machine's user folder. [section "Where we are headed" (Immediate order paragraph)]
- Diplomacy: trust, alliances and passage (plan agreed 2026-10-26, `docs/design/campaign_rules.md` "Diplomacy: trust, alliances and passage (plan)"): repute and regard that fade, gifts capped, an alliance tier with a voluntary call to arms, AI-AI alliances as a creation setting, passage treaties and trespass, starting treaties carrying the Caribbean asymmetry (Miskito-England, France-Brethren marque) and the Miskito musket line needing a European trade agreement; the team needs an alliance, regard 50 and a battle fought together. State format 10. **Rules built 2026-10-26** (`campaign/cdip.gd`, server StateVersion 10); screen built 2026-10-26 (`docs/design/ui.md` "Diplomacy screen: trust, alliances and passage"). Rome eliminated in 2 of 6 format-10 pin seeds (0 of 6 at formats 6 / 8) looked at 2026-10-27: variance, no rule changed (96 seeds: Rome falls in 18 at format 8, 20 at format 10; neither call to arms nor deterrence played a part in its two deaths; docs/AI.md 41). Watch: Iberia 9 -> 21 of 96 at format 10.
- Team victory (owner, phone campaign 2026-10-23): an AI faction that joins the players' team ("Join our team", accepted after 4 turns at peace when the proposer's team is the weaker or it is losing a war) added its regions to the 20, so a few team-ups ended the game early. **Option landed (2026-10-23):** the creation screen's "Victory counts" (setting `team_regions`, 1 team-mates' regions count, the default and the old rule; 0 only the regions the human players hold, key cities likewise; co-op players always count; stored only when 0, no `VERSION` bump). Later idea, proposed (not agreed): an **alliance** tier below the team (a defensive pact: shared sight, called into each other's wars, no regions counted; the AI leaves after 5 turns of us sitting out its war) and the team kept as one late union per campaign that needs 10 turns of alliance and a battle fought side by side; team-mates' regions count at half toward the goal. [`campaign/cai._why_team`, `crules.victory_progress`]
- Caribbean AI after batch 1 (2026-10-23; done the same day, docs/AI.md 34; England's grenadiers done 2026-10-24, docs/AI.md 40: Barracks 3 in 121 of 144 campaigns, median turn 29, a grenadier in 105). Still open: mortars about 0 a campaign (the Workshop 3 is seldom paid: England 6 of 141 at turn 60; paying it from the whole treasury thinned the lines, measured and not kept); the bands mostly sit in the Miskito capital held by the landing threat (a town taken from the water once in 24 campaigns); the water-field build (~0.3 s once) not measured on the web. [history rows "West AI after batch 1", "West AI after batch 3"]
- West pacing after the Range rule (2026-10-23, 6 x 60): battles 56.2 -> 50.8, eliminations 4 -> 1 per 6 seeds; the Range in recruiting towns: built first since the West AI pass (`RANGE_FIRST_PCT`, docs/AI.md 34; 24 seeds with it off: battles 52.1, with it 54.9). [history row "Campaign: victory-counts option, missile units from the Range"]
- West after batch 3 (2026-10-24, docs/AI.md 40): the Dutch eliminations (6 -> 21 of 144 seeds with batch 3) back to 9: a sea captain only for an army his aura serves (`CHAR_AURA_PCT` 34) and the Barracks 2 goal back for every non-native faction. Open: the coast nations now raise almost no sea captain (their armies are pike and musket; the Brethren 0.19 a campaign); the Itza / Miskito eliminations 24 / 22 -> 14 / 28 (within the earlier 144-seed spread). [history row "West AI after batch 3"]
- Breached walls (2026-10-24, state format 9; docs/design/campaign_rules.md "Breached walls on the campaign (as built)"): a fought battle's breaches stay on the town (`"breach": n`), mended one stretch a turn for 150 (Rome) / 120 (the West), the next battle opens with them down, auto-resolve counts the walls a level lower (never higher than whole). Open: AI-only play never breaches (the formula makes no breaches), so the campaign AI never pays for one unless a player fought there; no device look at the panel note; whether an auto-resolved storm with siege guns should breach too. [history row "Breached walls on the campaign"]
- Rome start budgets (looked at 2026-10-24, no change): Syracuse (income 924, upkeep 996 + fleet 75) recovers by itself, takes a third region by turn 3-4 (24 seeds: treasury 2,200 -> 318 at turn 3, then 1,182 at turn 10 with income 1,549 against upkeep 1,239); Epirus (946 against 1,047 + 45) never does, but not for the money: Rome takes Apulia and the Greek League or Macedon the homeland (Epirus eliminated in 19 of 24 seeds by turn 60, 12 of them by turn 21; finished by the Greeks 8, Rome 6, Macedon 3, Syracuse 2) and both fixes measured (one pike and one horse fewer at Apulia: upkeep 1,092 -> 881; or a treasury of 3,000) left it the same (20 and 19 of 24, no debt early but the same losses). A fix for Epirus is a strategic one (its army split across the strait, at war with Rome from the start and then with its Greek neighbours), not a budget. [history row "Rome start budgets examined"]

### Overworld view
- Beaches and cliffs: frame time re-measure idle (pan median West table 29-60 ms with the beach node, 36-51 ms without, on a loaded machine). [row "Beaches and cliffs on the overworld"]
- Table sea: the owner's eye on `table_depth`. [row "Table map sea on the bathymetry"]
- Mouse scheme and the fleet Deselect fix: the two-finger tap tested with synthetic events only. [row "Overworld mouse scheme and the fleet Deselect fix"]
- Fog of war view: no toggle in the AI-less sandbox but `--all-seeing`. [row "Fog of war, view half"]
- Overworld towns: landmarks placed at `CTown.plan`'s points, ships' baked contact shadow, Rome's Alexandria is not a region; miniatures hand-check on the Tab S7; Rome miniatures have the generic roman look. [paragraphs "Overworld towns modelled into the landscape" (steps 1 and 2), "Map table and miniatures"]
- Zoom / pan hitch and tap latency: AA polylines of the map cost ~7 ms a frame (LOD-simplify or cull); an order still redraws the whole overlay in the tap's frame; not measured on the Tab S7 (`?prof-tap=3`). [the two bullets at the end of "How we work" in the archive]
- Characters wired in: no figure until the Brethren land an army; Hunyuan models: the captain's plume and hat, the licence before release, silhouette fit, the rest of the cast. [rows "Characters wired in", "Hunyuan3D character models"]

### UI
- Options Looks rows (2026-10-25): Map view Terrain / Political and Map style Auto / Table / Relief (was Campaign map); the map's view button is now a Terrain | Political switch. Not yet seen on the owner's phone.
- Menu pass 2: a real-touch long-press and a desktop hover pass; the campaign top bar and command bar tips are boxed but untitled. [row "Menu pass 2"]
- In-game UI theme: the land campaign battle has no name for the top bar; the Options cycles duplicated from `main.gd`; the 800x450 phone top row ~20 px too wide. [rows "In-game UI theme, pass 1", "In-game UI theme, pass 2"]
- Main menu: the owner picks the background and emblem style; the owner's cleaned-up emblems to swap in; title background swipe tested with mouse events only. [rows "Main menu rebuild", "Title screen background selector"]
- Command bar: no morale / supply in the campaign, no "..." fold on phones, Recruit / Build open the full panel, drag onto another army / Exchange is not built. [rows "Overworld command bar", "Command bar round 2"]
- Faction mark on the battle HUD; story panel swatches are gauges, not factions. [paragraph "West faction emblems"]

### Art
- Crests: Dutch / Miskito lose their flag blue and turtle green in the 3-colour flatten; Rome's references are plain shields. [row "Faction crests"]
- West icons: 16 px legibility of the buccaneers (26) and pistoleers (28) on the tablet. [row "West icons"]
- Battle look: the cliff pieces are straight, Caribbean adobe flat roofs, hedges / fences drawn not kit pieces, the roofed round tower unused, no star-fort trace in the generator. [paragraphs "Level 1 phase 1", "Battle look Level 1 phases 2-6"]
- Ambient beds and web sound: the owner listens (swell speed, gull / creak level, the 35 % default, `?audio-debug=1` on devices); pan on the web if wanted. [rows "Ambient beds", "Web sound"]

### Distribution
- The GitHub workflows have never run; the ghcr package must be made public after the first push; the itch.io origin to confirm on the first real upload; no code signing; no game icon on the desktop exes; Windows / macOS builds never run. [paragraph "Distribution (D)"]

### Tests and devices
- Not played on a phone / tablet / real mouse yet: waypoints, the Paths overlay and Occupy flow, ships on Quality Low, crests, beaches, markers and banners, mouse scheme, title swipe, sea flight rule, End battle / Continue, battle touch Undo (co-op Undo untested live), fog view, command bar. [the rows named above]
- The windowed tests abort at exit with a double free (pre-existing, also at HEAD); `campaign_input_test` counts script errors. [rows "Overworld zoom / pan hitch", "Fleets join by tapping"]

## Verification pins

Pinned values to compare after a change (they move only with a stated reason; the row that set each is in the archive).

The default `campaign_sim` plays state format 6 (`var fmt := 6`): the format 6 and format 8 rows are **legacy** (the rules of older formats, kept exact); the format 10 rows are the current rules (since 2026-10-26).

| Pin | Value | Set |
|---|---|---|
| `campaign_sim --format=10` 6 x 60, Rome | `5af35d0f 16aa22f3 97e93bf2 81dc9f4d cc80b514 96159b8e` | 2026-10-26 (diplomacy rules, state format 10: trust, alliances with defensive calls to arms, deterrence by the target's bloc, passage and trespass; eliminations rome 2, cart 1, epir 5, gree 2, syra 2, gaul 1; battles 33 / 45 / 31 / 50 / 40 / 62; in `tools/verify_all.sh` as "sim10", `tools/balance/pins.json` "rome10") |
| `campaign_sim --format=10` 6 x 60, West | `76fd69c2 5007b062 1fb55364 f4f5ad4e 037a3c52 9f9c2246` | 2026-10-26 (the same; eliminations bret 2, itza 2; battles 49 / 50 / 53 / 55 / 43 / 56; "simw10", pins.json "west10") |
| `campaign_sim` 6 x 60, West pack | `599df3aa f3e3b769 b0438965 4184023a ac43d647 2078ca50` | 2026-10-26 (Launches per turn and boarding on arrival: ship_check's batch rule and the AI ordering canoes in batches; ships launched over the 6 seeds 447 -> 500, eliminations 3 -> 3 (Brethren 34, Itza 23, Miskito 28), battles 51.0 -> 50.0; were `24c5f228 c0b2dcf3 14e616ff 6aa4f970 e0b44ba6 9f82d1ab` after West AI after batch 3, 2026-10-24, docs/AI.md 40: `CHAR_AURA_PCT`, the Barracks 2 goal back, grenadiers first, `BU_LINE_TREASURY`; eliminations 2 -> 3 (Brethren 37, Itza 23, Miskito 28), battles 52.3 -> 51.0; were `c349e501 ea8fe0da 30151731 55065b30 c99101a2 8cffead8` after Caribbean roster batch 3, the characters: the AI raises sea captains and shamans (missionaries at Skilled) instead of Rome's six, docs/AI.md 38; were `c48df9ec 8e25f84c 0573d041 51bc1672 402836a2 dcb8e77c` after West AI after batch 2: `MIX_LIVE`, recruiting picks among the mix lines a centre can raise (docs/AI.md 37); were `c6d023bf be562b06 34730bf5 5b1d1039 3edb095d 73ca1976` after Caribbean roster batch 2: seven West rows, rosters, mixes, militia garrisons; were `57e0052e d5f95887 7fff902b 923b1e99 52405c76 341c7614` after poisoned arrows: Miskito bowmen carry poison, fire arrows Itza only; were `57e0052e 287cbf96 737ececb 92a0aa04 24728bb1 341c7614` after the West AI after batch 1, 2026-10-23: build-up lines, a Range first, specialists, amphibious bands and water distances (docs/AI.md 34); were `537c05eb 2ef8cd92 d33e6048 fd83ac83 4eba33d4 5f4fff9d` after Caribbean roster batch 1, 2026-10-23: seven West rows, mixes and recruit lines (docs/design/battle_sim.md "as built"); were `005c4bb9 15e2d8bf fc4fbe9f f0fb21bc 12fa4627 ac502bec` after no trade with the enemy, 2026-10-23: a lane between ports at war pays neither (docs/design/sea.md "Lanes at war and legible raids"); were `69971b5f e323246e ce4d2db4 2fa4bd9d 582c4808 1e9aeaf9` after musket Range rule, 2026-10-23: musketeers and the mounted missile lines need a Range (docs/design/campaign_rules.md); were `9ab4e83f b83cf517 c7e43889 6365cfdf ca6d682b 5c37c9af` after port rule HARBOUR_MAX 1, 2026-10-23: Puerto Principe out; were `0d7d7d3b e766e1c8 01b412d0 db1d3889 0ddb6278 74e13f7f` after Port rule, 2026-10-23: HARBOUR_MAX 2, Rome HARBOUR_FAR Gades 3 (docs/design/sea.md "Port rule"); were `6eb5fcfa 2e5913eb 688124be eff3014a 3ec8e2c5 350adab3` after Docking; Docking, 2026-10-23: the AI docks its free fleets, docked fleets fight nothing, the repair rule splits (docs/design/sea.md "Docking (as built)"); were `8773a8fc abe21851 5c81e3f6 1f2d7243 a80b8229 8b6e4ab5` after garrisons, 2026-10-23: AI garrisons against landings, docs/AI.md 12.2, SEA_AWAY_PCT 120 at Average; were `cd596549 4a22d29b 72e1b16e 86a089a2 a80b8229 7f92babc` with 150; were `fdcde239 666890f5 8c28a056 efc2c701 e8db9300 95dc3802` after 2026-10-22 (row "Campaign AI odds as win chances"; were `7f28336f e4e63bcb fc358ea5 34b7ccb6 3bb99388 87068d07` after the row "Lane trade, raids and blockades", `f35b6a3a 3c4807ee 40ab341c da4ecb04 7896bb0d 5bd06f73` after the row "Auto-resolve refit"))|
| `campaign_sim` 6 x 60, Rome pack | `7df61f83 8e12363b 07354ffa 3656ce6d a27c02da 2640b4c5` | 2026-10-23 (lanes at war, 2026-10-23, confirmed on top of the sortie rule f7c3f14, which alone had moved this row to `b2cb4eab e40de96c a416c9c2 a065aa4c 2bad8df3 c798d183`; no trade with the enemy, 2026-10-23: a lane between ports at war pays neither (docs/design/sea.md "Lanes at war and legible raids"); were `b2cb4eab e40de96c 8aeea476 a065aa4c d94dbb4e c798d183` after the musket Range rule (unchanged by it), 2026-10-23: the Rome AI builds the same; before it (unchanged by the musket Range rule, 2026-10-23: the Rome AI builds the same; port rule HARBOUR_MAX 1, 2026-10-23: Patavium out; were `9119d3f1 554c2db0 7c9c5268 a065aa4c cc94c9e3 c798d183` after Port rule, 2026-10-23: HARBOUR_MAX 2, Rome HARBOUR_FAR Gades 3 (docs/design/sea.md "Port rule"); were `723f6d4b 554c2db0 7c9c5268 a065aa4c cc94c9e3 177b1275` after Docking; Docking, 2026-10-23: the AI docks its free fleets, docked fleets fight nothing, the repair rule splits (docs/design/sea.md "Docking (as built)"); were `5b815997 9f253374 22b3e502 c1a85489 60a756f8 7af8c2b6` after garrisons, 2026-10-23: SEA_AWAY_PCT 120 at Average; were `04f4fa7f aa11b2fa 520177c5 963ed991 0bab2f14 f2188f49` with 150 after the Rome data follow-up, 2026-10-23: Syracuse's start fleet 2 triremes + a lembos, SEA_TRADE_PCT 50; were `20eb4ab1 aafbbee9 6107e914 7fcce6e4 48d6b228 8d3da914` after garrisons, 2026-10-23; were `e8efb372 246d6b30 a3267ff4 a4b91f47 2632d26b 520c5be9` after R2, 2026-10-23: Rome fleets; were `8fbb3ce8 078cda88 fd334207 0d4b974b 52d75989 d5d71a7d` after 2026-10-22 (same row; were `57ebb97a 89043efa 6baf5ad8 ccaf53f8 37693c54 5bc63aab` after the lane rules, `7a4fdddc 2e06d5ab 3054d32e 658ce540 e2295baf 7f4ea2af`) |
| `campaign_sim --format=8`, Rome | `a9a782f2 01adaebc cdc2cbb5 c4ddb744 b71553ad deef9bc2` | 2026-10-23 (lanes at war, 2026-10-23, confirmed on top of the sortie rule, which alone had moved this row to `361f9f99 1159782a 1a03d38a 82d5a8b8 b842aa6e 30cace63`; no trade with the enemy, 2026-10-23: a lane between ports at war pays neither (docs/design/sea.md "Lanes at war and legible raids"); were `361f9f99 1159782a 92ee8631 82d5a8b8 3deb56e6 30cace63` after FLEET_R 5, 2026-10-23: a fleet at sea sees 5 cells (the fog memory is in the state); were `0c08c462 9550157e b7324f23 157c9fac f2838a1a 1c291d2f` after port rule HARBOUR_MAX 1, 2026-10-23; were `6f92927d 80fe567c b05cb6c3 157c9fac ea0ad89e 1c291d2f` after Port rule, 2026-10-23: HARBOUR_MAX 2, Rome HARBOUR_FAR Gades 3 (docs/design/sea.md "Port rule"); were `106bc6e1 80fe567c b05cb6c3 157c9fac ea0ad89e edcf85c9` after Docking; Docking, 2026-10-23: the AI docks its free fleets, docked fleets fight nothing, the repair rule splits (docs/design/sea.md "Docking (as built)"); were `a9cb504b eea14cca 5c6a0ee7 8893db02 fa884115 6d4e1245` after garrisons, 2026-10-23: SEA_AWAY_PCT 120 at Average; were `eee58796 da44296b d27aaa90 9fb2098a a3876f53 e5bc1bb4` with 150 after the Rome data follow-up, 2026-10-23; were `e7b7ee32 c4ae5e8c 3526de20 496bdd81 3fb80a2e cf49c0dc` after garrisons, 2026-10-23; were `f8163ce9 3a55a1a4 3f1486bf 347a7601 66da6047 df12df5d` after R2, 2026-10-23: Rome fleets; were `d5192647 a7994873 5518a9bc 37b78b2c c573da0b f7adc767` after 2026-10-22 (row "Campaign AI odds as win chances"; HEAD before it already read `571a3d03 73d2f32a a7ef6f92 2acfa87d 4f40c97f 6dfeff56`, the 2026-10-17 pin `4d21f126 ...` was stale)|
| `campaign_sim --format=8`, West | `9a3bcb77 2f6445f3 b6a543b5 b45cff4b 96769eea 01c4eb25` | 2026-10-26 (legacy; measured at 450cb28 before the diplomacy rules and unchanged by them; this pin had gone stale, it read `e937b1bf cc52b8e9 c333f481 4933ce81 6f35cb4f aad2ab4b`, set 2026-10-24 (West AI after batch 3, docs/AI.md 40; were `db1bbc9f f0f73e13 7ef9f203 177f36fa 7c2276a9 d12781db` after Caribbean roster batch 3, the characters (docs/AI.md 38); were `2e30db16 679728bb 453a67bc 987f965b f14be6a9 e1757c68` after West AI after batch 2, `MIX_LIVE` (docs/AI.md 37); were `a50006b1 5c160924 1cf9d9e9 fd984d94 abda9de1 e946dcd0` after Caribbean roster batch 2; were `15af9cb1 4870f275 c0f891f4 fa4aadb5 eccb167a 12e36e06` after poisoned arrows, Miskito only; were `15af9cb1 46fd076d 90c9e7d4 60a4a32d 2df7058b 12e36e06` after the West AI after batch 1, 2026-10-23 (docs/AI.md 34); were `4f3f41be 86b089a2 65047c8a 3a91da40 cd3db17e f6156250` after Caribbean roster batch 1, 2026-10-23: seven West rows, mixes and recruit lines (docs/design/battle_sim.md "as built"); were `a8ca33bc 011be1fd 0b5e815a 4070e14d a8433128 e2f08160` after no trade with the enemy, 2026-10-23: a lane between ports at war pays neither (docs/design/sea.md "Lanes at war and legible raids"); were `4224515d 87f1e725 d574ade4 468a10c5 b0da5ebe 8f1accce` after musket Range rule and FLEET_R 5, 2026-10-23; were `537d49ce 0c07a7f8 43ffe1aa d4a52d08 8acd06e7 f2349d16` after port rule HARBOUR_MAX 1, 2026-10-23; were `21dfcb87 14961cf7 9d72e51e bd0b22e8 40783cd9 83778bd0` after Port rule, 2026-10-23: HARBOUR_MAX 2, Rome HARBOUR_FAR Gades 3 (docs/design/sea.md "Port rule"); were `4a2d4590 37ad7c23 30203e8a fe22109d c764fd7e 12f1ccb3` after Docking; Docking, 2026-10-23: the AI docks its free fleets, docked fleets fight nothing, the repair rule splits (docs/design/sea.md "Docking (as built)"); were `618d308a 0a43d53f 1a94498d f843ef51 89455406 46da4f78` after garrisons, 2026-10-23: SEA_AWAY_PCT 120 at Average; were `5539e80a 8f8bac43 7456a9a6 2da94626 89455406 b2197845` with 150; were `d6dc8813 a2dbbf24 0bce8f44 24338e5e a25cfa32 939f4dde` after 2026-10-22 (row "Campaign AI odds as win chances"); HEAD before it `26b1bc4c d628d8bc 774a2f9d d2d39259 0d7593d9 f232fb86`, the 2026-10-17 pin `d8cded2d ...` stale))|
| AI goldens as format 7 (`as_format(st, 7)`) | `9aca1fcc` (rng 2580136663), `f3b40674` (rng 1790012962) (`tests/campaign_test.gd`) | 2026-10-23 (no trade with the enemy, 2026-10-23: a lane between ports at war pays neither (docs/design/sea.md "Lanes at war and legible raids"): were `4c8a4977` (rng 2580136663), `ed0717eb` (rng 2573862638); Port rule, 2026-10-23: Easy golden was `11d7ae9c` (rng 1530193207), Average unchanged; Docking, 2026-10-23: the AI docks its free fleets, docked fleets fight nothing, the repair rule splits (docs/design/sea.md "Docking (as built)"); were `653fa85c` (rng 3934412497), `123fe3e4` (rng 662798570) (`tests/campaign_test.gd`) after garrisons, 2026-10-23: SEA_AWAY_PCT 120 at Average; were `ddb1d8a4`, `af5fa501` with 150 after the Rome data follow-up, 2026-10-23; were `1e444176`, `e8a57e07` after garrisons, 2026-10-23; were `90d0b2cd`, `75f80cd7` after R2, 2026-10-23: Rome fleets; were `519bcec8`, `9f1555b0` after 2026-10-22 (row "Campaign AI odds as win chances"; were `e641d961`, `1508a9cb` after the row "Lane trade, raids and blockades", `3007c1ab`, `bd76985b`) |
| `tests/pack_test.gd` Rome AI-only campaign, seed 4242, 20 turns | `ROME_20` `239212f3` (format 9); as format 8 `ROME_20_V8` `7d094e62`, as format 7 `ROME_20_V7` `de4e8cfd` | 2026-10-24 (breached walls, state format 9: only the version key moved, the format 8 play is the old `7d094e62`; no trade with the enemy, 2026-10-23: a lane between ports at war pays neither (docs/design/sea.md "Lanes at war and legible raids"): ROME_20 was `0f451773`, V7 was `9425a021`; FLEET_R 5, 2026-10-23: ROME_20 was `2cd9a3eb`, V7 unchanged; Docking, 2026-10-23: the AI docks its free fleets, docked fleets fight nothing, the repair rule splits (docs/design/sea.md "Docking (as built)"); were `ROME_20` `e588f4c3` (format 8); as format 7 `ROME_20_V7` `635e25ce` after garrisons, 2026-10-23: SEA_AWAY_PCT 120 at Average; were `e9ea81e2` / `066b42cf` with 150 after the Rome data follow-up, 2026-10-23; were `65b64803` / `5a0bbec3` after garrisons, 2026-10-23; were `a2def14b` / `a0016f69` after R2, 2026-10-23: Rome fleets; were `91b91238` / `4a93a2f1` after 2026-10-22 (row "Campaign AI odds as win chances"; were `244711de` / `6fd1aac2` after the row "Lane trade, raids and blockades": Rome's lanes pay; `70843c45` / `57aa56ba` after the row "Four leftovers", `3c26a0bc` / `57aa56ba` after "Auto-resolve refit", `d60c218a` / `575e23d5` before) |
| `tests/pack_test.gd` "pack" state hash as the server sees it (also in Go `TestStateHashPack`) | `a9a7a1e4`, `a5c588a1` | 2026-10-13 |

The determinism goldens (four flat digests, every `--only=` pin) are in `tests/determinism_test.gd`; rows say "goldens unmoved" when a change keeps them.

## How to run things

```sh
# Campaign tests
godot --headless --script res://tests/campaign_test.gd      # rules, determinism, JSON
godot --headless --script res://tests/campaign_sim.gd -- --seeds=6 --turns=60   # AI pacing (format 6; --format=5 the region-hop rules)
#   campaign_sim: --skill=easy|average|skilled, --skill-f=rome:s (one faction), --knob=s:ID=VALUE (ablation), --twice,
#   --seed0=N (start at seed index N: shard 24 seeds as 4 x --seeds=6), --no-water (amphibious armies plan by land only)
#   --trace-faction=rome (that faction's diplomacy, losses and treasury per turn), --ai-alliances=0 (the creation setting)
godot --headless --script res://tools/campaign_grid.gd [-- --check --png=/tmp/grid.png]  # regenerate / check the nav grid
godot --headless --script res://tests/campaign_solo.gd      # 20 turns of a player policy
godot --headless --script res://tests/story_test.gd         # the story campaign (-- --turns=45 --seeds=8 --quick)
# Story testing aids: -- --story=seed[:turns] (turns autoplayed) --story-path=first|random|republic|pardon|legend
#   --story-show=EVENT|ending --story-seen=N --story-choices --story-log
godot --headless --script res://tests/campaign_battles.gd   # auto-resolve timing, formula calibration; -- --only=fit: the formula against the fought tables
godot --script res://tests/campaign_input_test.gd           # needs a window
godot --headless --script res://tests/battle_screen_test.gd  # battle screen: pre-battle, auto / fought result, field battle
godot --headless --script res://tests/matchups.gd -- --only=tiers   # tier balance
# Campaign testing aids: -- --campaign=rome[,greeks][:seed] --sim-turns=N
#   --camp-attack=N:region --camp-siege=N:region:turns --camp-assault=region --camp-auto --camp-fight --select-army=N --select-region=key
#   --cam-zoom=Z --dialog=battles|summary|diplomacy|realm|goals --new-campaign
#   --controls --ios-tab; battle: --demo-ghost=deg
#   --popup=... (command bar popups, see the Command bar row); --host-start=PORT (desktop: start the hosted game server at launch)

# Tests
godot --headless --script res://tests/determinism_test.gd
godot --headless --script res://tests/benchmark.gd
godot --headless --script res://tests/matchups.gd
godot --headless --script res://tests/matchups.gd -- --fair=100   # mirrored AI battles
godot --headless --script res://tests/matchups.gd -- --only=terrain  # terrain effect sizes
godot --headless --script res://tests/matchups.gd -- --fair=50 --fair-terrain=4  # mirrored, symmetric hill map
godot --headless --script res://tests/matchups.gd -- --only=maps     # woods, streets, gates, settlement battles
godot --headless --script res://tests/matchups.gd -- --only=sieges   # settlement battles only
godot --headless --script res://tests/matchups.gd -- --only=plans --seeds=8 [--plans=0,4]   # each wall plan at walls 1-3
godot --headless --script res://tests/matchups.gd -- --only=fair-sieges [--plans=4 --walls=3 --rows=0 --time-limit=1800 --tune=WALL_COVER=0,25,45,70]
#   equal-force sieges, ladders + ram (row 0) or artillery only (row 1); shard by plan / walls / row
godot --headless --script res://tests/probe_maps.gd -- --scen=siege_town --png=1500 --out=/tmp  # siege debug pictures
godot --headless --script res://tests/ladder_probe.gd [-- --walls=2 --plans=4 --quick]   # every stretch climbable as the preview says (~7 min)
godot --headless --script res://tools/city_dump.gd -- --out=/tmp --seed=1234   # generated settlements to PNG
# Sandbox URL / command line: --siege=seed:level:walls[:ground[:kind[:defend[:plan[:coast[:equip[:time]]]]]]], --ground=N, --no-trees
#   (equip 0 none, 1 three ladder sets, 2 three ladder sets and a ram; time = battle time limit in s)
godot --script res://tests/input_test.gd        # needs a window
tools/check_scripts.sh                           # GDScript warnings as errors (in a scratch copy of the
                                                 # project: safe while other Godot runs use this checkout)

# Live co-op battles (milestone 5)
godot --headless --script res://tests/lockstep_test.gd   # snapshots, two peers, mid-battle join (-- --quick; -- --only=three: three peers)
python3 tests/live_team_e2e.py --port 8073       # three headless clients, a campaign battle with humans on both sides (~2 min)
python3 tests/live_e2e.py --port 8077            # two headless clients, three live battles + two custom battles
python3 tests/live_e2e.py --port 8077 --only-custom   # just the custom head-to-head and co-op battles (~90 s)
godot --headless --script res://tests/custom_battle_test.gd   # custom setups build and run
godot --headless --script res://tests/deploy_view_test.gd     # deployment through the battle view
python3 tests/custom_shots.py --port 8081         # phone screenshots: setup, deployment, head-to-head lobby (needs a window)
# Testing aids: -- --custom (the custom battle screen), --custom-solo, --custom-template=test_cav_archers,
#   --custom-join=CODE; web: ?custom=CODE
python3 tests/live_shots.py                      # phone screenshots of the co-op UI (needs a window)
(cd server && PATH=$HOME/.local/go/bin:$PATH go run ./cmd/webcheck -url http://127.0.0.1:8074 -live)
                                                 # two headless Chromiums, live battle (serve a web export there)

# Server (milestone 4; see docs/SERVER.md)
tools/build_server.sh --test                     # go vet + go test + build build/server/scserver
SC_BUILD_OUT=build/server-test/scserver tools/build_server.sh   # elsewhere (tests do this)
tools/run_server.sh 8070                         # serve build/web + API + telemetry on a port
python3 tests/online_e2e.py                      # two headless clients against a test server (~30 s)
godot --headless --script res://tests/net_test.gd  # client server choice: address normalising, per-server seats, state_version check
tools/export_desktop.sh [windows linux macos]    # build/desktop/<platform>/ + zip, scserver bundled beside the game
tools/itch_push.sh                               # butler push, channels web / windows / linux / mac (not run yet)
(cd server && PATH=$HOME/.local/go/bin:$PATH go run ./cmd/webcheck -url http://127.0.0.1:8070)
                                                 # the web export in two headless Chromiums

# Web build and playtest server
tools/export_web.sh                              # writes build/web
python3 tools/serve_web.py 8060                  # plain HTTP, behind Caddy
python3 tools/serve_web.py 8443 --cert .certs/dev.crt --key .certs/dev.key
                                                 # self-signed, direct on the LAN
python3 tools/playtest_report.py                 # summarise playtest_logs/
```

- Playing online as a player, hosting a server and the HTTPS rule for browsers:
  `docs/PLAYING_ONLINE.md`; self-hosting the server image: `server/README.md`.
- Godot's web build needs a secure context, so phones must use HTTPS. The
  self-signed certificate in `.certs/` (gitignored) is created with
  `openssl req -x509 -newkey rsa:2048 -nodes -days 365 -keyout .certs/dev.key
  -out .certs/dev.crt -subj "/CN=strategic-command-dev"
  -addext "subjectAltName=IP:<lan ip>,IP:127.0.0.1,DNS:localhost"`.
  Each browser shows a warning once; accept it.
- `?scenario=bench_4000` on the URL jumps straight into a scenario;
  `&seed=N&terrain=ridge` fixes the seed and ground of a playable battle
  (flat, rolling, ridge, valley, hill, slope, random). The battle's seed
  and terrain kind are shown in the top-left readout. Benchmark
  scenarios use a fixed seed so hashes can be compared between devices, but
  only between builds with the same `sim:` hash in the build stamp.
- Web export templates for Godot 4.7.2 (no-threads variants only) are in
  `~/.local/share/godot/export_templates/4.7.2.stable/`.
- Playtest telemetry lands in `playtest_logs/` (gitignored).

## Decisions already made (do not reopen without the user)

- Co-op only for now; head-to-head and controlling the enemy army come later.
- Simultaneous turn planning; the turn resolves when both have submitted.
  Turn timeout is a campaign setting (off, or one of several durations).
- Battles never block silently: they become pending and are resolved by
  auto-resolve, solo real-time, or live co-op.
- If the ally's army is in range and they are offline, the present player
  chooses per battle: wait for them, or take command of their army.
- In co-op battles each player commands their own army; units can be gifted
  and gifted back. Pause and speed changes need both players to agree.
- Per-soldier combat (health, blocking, individual hits) is a hard requirement.
- Live battles use deterministic lockstep, so the sim must stay integer-only.
- Game rules run on the clients; the server stores saves and relays traffic.
- No generals, family, politics, agents or naval combat in the first version.
- Web first (Godot export with threads off). Notifications through Discord.

Last of all (moved 2026-10-09): **shared empire** (both humans running one
faction); two empires working together plays well enough that this waits
behind the N-player campaign.

## How we work

- Design, architecture and review happen in the main session with the user.
  Code generation is delegated to the latest Opus model (see `CLAUDE.md`).
- The loop: build, re-export, the user playtests on their phone against the
  dev server, telemetry plus their impressions drive the next change.
- Commit only when the user says so.

## History

- `docs/history/2026-10.md`: every dated row and paragraph of the old STATUS (2026-10-04 to 2026-10-22), newest first: the old "Where we are" table, "In progress right now", the session notes, the West pack slices, the sea passes.
- `docs/history/overview.md`: the undated general sections of the old STATUS (old header paragraph, milestone definitions, the tuning backlog, the old open items, the first-milestone rows).
- Older months: none (the project started in October 2026).
