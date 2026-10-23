# Status archive: overview (undated general sections)

Moved verbatim from `docs/STATUS.md` on 2026-10-22 (the docs split). The old header paragraph, the undated rows of the old "Where we are" table, "What exists", "What has been proven", the old "Open items", the superseded Thursday list, the tuning backlog and the milestone definitions. Dated rows and paragraphs are in `docs/history/2026-10.md`.

## Old header (the "Last updated" paragraph, moved verbatim 2026-10-22)

Last updated: 2026-10-17 (distribution milestone D: standalone game server image, Server field, Host a server, desktop exports, built, not committed; slice 2c: harbour forts with an inside, fighting from buildings, the musket line's reserve, built, not committed; balance pass T: firearm AI, per-man fire in cover, street posts, siege rally rule, built, not committed; pathing phase J, fight jitter and stuck units, built, not committed; pathing phase W, West open towns, built, not committed; 2026-10-15 pathing phases C1-C7, street fighting, built, not committed; earlier 2026-10-09: siege towers built, not committed; the general and his bodyguard built, not committed; camels and elephants built, not committed; ammunition kinds and fire, foraging and the ammunition wagon built, not committed; earlier 2026-10-08: a CPU-fed soldier rendering fallback, picked by the battle's self-check, for Chrome on an Adreno 650 tablet that drew no soldiers; earlier 2026-10-07: any ally can join a fought co-op battle and be given units; the battle screen on the overworld; cities worth defending, part 2b: siege equipment as objects, the ladder shuffle and wall-punching bugs; part 2a: units do not pass through each other, street fights; part 1: tower engines, ladders, a ram, hard gates, the battle time limit; earlier 2026-10-06: deployment phase and custom battles built; the continuous campaign overworld built, state format 6; free campaign movement built; sieges and battle odds built on the campaign map; settlement variety built 2026-10-05). Read this first, then `docs/DESIGN.md` for the full
design and `CLAUDE.md` for working rules. Update this file whenever a
milestone lands or the plan changes.

## Where we are

| Milestone | State |
|---|---|
| 1. Battle sandbox | Done, committed (`6b3a1cf`), playtested on an Android phone |
| 2. Full battle mechanics | Done, committed (`49c1022`), playtested; tuning pass included |
| Unit symbols and unit book | Done, committed (`49c1022`) |
| Artillery (bolt and stone throwers) | Committed (`49c1022`), not yet playtested |
| Terrain height | Built, committed, playtested ("feels good so far") |
| Playtest round (HUD scale, stones, ammo, refill) | Built, committed, not yet playtested |
| 4. Async backend (Go + SQLite) | Committed (`fad7399`); port 8060 runs it; first phone playtest done (live battles were missing) |
| Battle maps with character (woods, city maps, palettes, shading) | Committed (`3522fd2`); not yet played on phones |
| 6. Depth (siege towers, tech, more factions) | Not started |

### What exists

- **Battle sim** (`sim/`): deterministic, integer-only, per-soldier, 10 Hz.
  Nine unit types (heavy swords, light infantry, spearmen, pikemen, archers,
  javelinmen, shock cavalry, bolt throwers, stone throwers); melee with
  shields, armour and flank/rear bonuses; multi-rank pikes; projectiles with
  friendly fire; cavalry charges with knockdown and brace reflection;
  artillery engines with crews, set-up / pack-up, piercing bolts and
  ploughing stones; morale, routing, withdrawal; a battle
  AI that only issues orders; a plain-data battle result for the campaign.
- **Terrain height** (`sim/terrain.gd`, built 2026-10-05): an integer
  height grid (4 m nodes) generated from kind + seed + a few parameters
  (flat, rolling, ridge, valley, hill, slope, or hand-placed features),
  hashed into `state_hash()`; slopes slow units (cavalry and artillery most),
  higher ground helps in melee, charges hit harder downhill, missiles reach
  further from above, javelins and bolts are blocked by crests, stones
  plough less uphill; the AI uses high ground. Drawn as a contour map with
  hill shading in one shader. Details in DESIGN.md "Terrain height: as built".
- **View and controls** (`game/`): one-draw-call soldier rendering from a data
  texture, touch and mouse controls, multi-select, show-all-orders overlay,
  instant order preview while paused, unit symbols, unit book, HUD, telemetry.
- **Tests** (`tests/`): determinism, benchmark, scripted input (needs a
  window), balance matchups across seeds.
- **Tools** (`tools/`): web export, HTTPS dev server with telemetry logging,
  playtest report, script warning check, server build / run scripts.
- **Server** (`server/`, milestone 4): one Go binary with SQLite that serves
  the web build (brotli), the telemetry endpoint and the online co-op
  campaign API; Discord notifications; Dockerfile and deployment files.
  Reference: `docs/SERVER.md`. Client side: `game/net/`,
  `game/campaign/online_ui.gd`.

### What has been proven

- GDScript is fast enough: 4,000 soldiers cost about 9 ms mean, 30 ms worst
  per 100 ms tick on a Snapdragon 865 phone browser (milestone 1 build).
- The sim is deterministic across devices: an Android phone, a Linux desktop
  browser and the native Linux build produced identical hashes for the
  fixed-seed benchmark (milestone 1 build).
- The touch control scheme works; the user likes it.

### Open items

- Campaign bug fixed (2026-10-05, from play): two armies ordered into the
  same enemy region in one turn (Lilybaeum -> Carthago by sea) fought
  separately: the second was bounced by "battle pending there". Now an
  army entering a region whose battle started this turn joins it (attackers
  or defenders, 24 field units a side, else "battle side full"); AI attacks
  that commit several armies now arrive together too. Sea-lane neighbours
  still do not reinforce passively (open: whether they should).
- iPhone Safari (iOS 18.7) ran the 4,000 benchmark on the terrain build at a
  steady 60 fps (sim 3.1 ms mean, 7 ms worst per tick) and the terrain shader
  works there. It only rotates to landscape when opened from the home screen
  ("Add to Home Screen"); a Safari tab cannot force orientation.
- **iPhone determinism is not yet cross-checked** against another device on
  the same build. Run the same fixed-seed benchmark on the iPhone and one
  other device and compare with `tools/playtest_report.py`.
- The user reports performance is good on every device tried so far.
- Occasional frame hitches at 4,000 soldiers (a whole sim tick runs inside one
  frame). Fix by spreading tick work across frames if it becomes annoying.
- "A unit with a move order does not fight" was chosen so cavalry can pull out
  and units can retreat. Unconfirmed that it feels right in play.
- The game is reachable at `https://strategiccommand.ggior32.dev` through the
  user's Caddy reverse proxy, which holds a real certificate and forwards
  plain HTTP to the dev server on port 8060. The dev server is not hardened
  and only lives as long as the session that started it.
- Install support (2026-10-05): the export writes `manifest.json` and
  192 / 512 px icons (tools/make_web_icons.gd), standalone, landscape. No
  service worker: Godot's PWA worker answers from its cache first, which
  could serve a stale build, so there is no offline play. Android Chrome
  offers install without a worker (unverified on the user's phone).
- A mild top/bottom bias may remain in mirrored AI battles (53-55% on some
  seed ranges, 50.6% on another). Settle before head-to-head play.
- Deferred battle features: fatigue, horse archers, a manual brace
  toggle, siege equipment (ladders, towers) and climbing walls, sallies,
  spreading tick work across frames; terrain visibility (hiding behind
  hills or in woods).
- Terrain: phone GPU behaviour of `game/terrain.gdshader` is unverified
  (desktop GL only); the AI's high-ground behaviour (hold, detour, rises)
  is unplaytested; menu buttons are 44 px tall to fit the new entries.
- Artillery is unplaytested: look and readability of engines, bolts, stones
  and impact marks on a phone; whether the Deploy button and set-up times
  feel right; whether AI batteries and guards behave sensibly in play.
- bench_4000 (two armies a side) now runs ~10 min to a decision (2,000:
  ~5 min); the AI's second line and batteries could be looked at.
- Forts leftovers (slice 2c), built 2026-10-16 (see "Forts leftovers" under
  the Slice 2c entry): walls 1 59 -> 41 % (the sally, the attackers' guns
  sparing the fort), walls 3 12 -> 25 % (one stone tower), the field AI draws
  all 4 against the charger. Left: walls 1 and 2 both 41 % (45 / 35 wanted:
  walls 2 is now no harder than walls 1); the field AI's draws against the
  charger are 30-minute draws (its empty shooters stay on the field) and its
  musket lines still run dry before the charger's; the second landward
  bastion's gun never bears on the town (measured, not changed).
- Distribution D open items: see "Distribution (D)" below.

## Where we are headed

**Thursday's list (2026-10-22, agreed; starts after 2 pm with a full budget):**
the relief map's Caribbean city markers (floating names are hard to tap) +
less fog over the sea off our own coast (csight: own coastal regions see 2
cells out, ports / forts 3) -> roads for the West (the Camino Real, the
Portobelo trail, the island roads; baked like Rome's; drawn in both styles)
+ the pathing detour (the Veracruz -> Orizaba repro: the road / terrain
costs; a direct line unless the road saves a turn) + ocean trade lanes drawn
on both maps -> the sea battle look (water with the bathymetry's depth
colouring, wind-driven crests, foam at the shore and in wakes; the land /
shoreline with the land maps' beach and cliff edges) -> faction crests
through Klein 4B from the drawn marks -> UI theme pass 2 (battle HUD, sea
screen) -> Rome walls 1-2 (Thursday). Lane rules (raiding / blockading) and
the Rome navy follow.

**Tuning backlog for the rebalance block** (numbers chosen once, never
tuned; collected 2026-10-09):
- **Moved by balance pass T (2026-10-16, see "Balance pass T, as built" above):** the walls 1-3 rows,
  the open-field firearm AI, the street mouth and the West sieges; the
  levers archers' pull-back and escalade lanes tried (neither kept;
  see there); what is left: equal-force
  walls 3 at 12 % (target 25) and the AI follow-ups listed there.
- Walls 2-3 equal-force sieges after the 2026-10-10 siege pass: full kit
  ring / polis walls 2 20 / 10 %, walls 3 0 / 50 % (targets 35 / 25):
  the attackers lose 290-350 men outside the walls (their archers die to
  the last man in the duel with the walls; the kit's carriers under fire)
  and the walls-2 gate falls at about 200 s against 125 s at walls 1
  (the batteries' set-up and counter-battery, not the gate's hit points).
  Levers not tried: archers pulling back from a lost duel, the
  carriers' pace, more escalade lanes at once. Easy defenders weaker than
  Average only in the ring at walls 1. A fortified holder at a crossing
  does worse than an open one (stays in its camp at the mouth).
- Ammunition kinds: fear values (fire against gates: `GATE_FIRE_CHIP`
  15 / 8 / 6 per mille a second by walls since 2026-10-10, not measured on
  its own); the explosive's price (late and
  rare only by building / faction). Explosive blast (2026-10-09): 4 m
  round, damage to a third at the edge, 30 men knocked at most, thrown
  1-2 m, down 2-3 s (riders half, elephants 1 s); its load kills 58 of
  120 pikes against 8 by as many ordinary stones.
- Resupply: forage rate (~37 ticks per arrow per man), wagon refill
  30 s a load, the 30 % horse-hit chance, wagon stocks (100 / 150 /
  220 %), the 20 % strength and +6-12 % auto-resolve bonus.
- AI knobs: `WG_EMPTY_PCT` (15 % Average), `AK_WAVER_PCT` (35 %),
  engine take-up radius 60 m (kept by the field rebalance, not measured).
- Left by the field rebalance (2026-10-09, STATUS row): Skilled vs Average
  40 % (target 65; Skilled's reserves / rotation after the faster melee);
  the missile yardsticks' bands (arrows 71 / 86 % on light / cav, javelins
  55 % on cav, bolts 36 % on a pike block: far above the bands asked for,
  owner's call whether to cut).
- Mantlets (2026-10-09): standing cover 60 % of arrows / slings /
  javelins, 30 % of bolts, 0 % of stones for men in the 6 x 6 m behind
  it; carried cover 40 % within 6 m (roof rule); 600 hp (two stones);
  campaign grants 2 after 2 siege turns, 4 after 3 (any walls); custom 0
  / 2 / 4 a side; the siege AI's screens before the cover archers stop
  11-14 missiles a walls-1 battle with no clear gain in losses; field /
  defender AI use.
- Known AI gaps (not tuning): no AI recaptures enemy engines (the
  settlement AI takes up its own since 2026-10-10); the wagon AI has no dedicated guard
  unit; ammunition kinds go only on units raised at the building's centre
  (no refit of older units; AI.md 24); the defenders and the field AI
  ignore mantlets.

Agreed with the user on 2026-10-06, in this order (milestones 1-5, battle
maps, settlement variety, sieges, free movement and the wall/reachability
fixes are all landed; see "Where we are"):

1. **Continuous overworld** (in progress): Rome 2-style positions on a
   campaign grid, paths and range shapes, zones of control, siege by moving
   onto a city, support by radius with lines, stances (forced march,
   fortify, raiding), turn animation; campaign layer kept data-driven so it
   can be reused for a different setting (the user has an American West
   game in mind on the same engine).
2. **Phone round on the overworld**, then a tuning pass from what it shows.
3. **Roads, rivers, hills and crossings** as grid-cell overrides (historic
   roads, rivers as barriers with fords and bridges; ford battles on the
   battle map; **hills** (user, 2026-10-09): hill cells that cost movement
   and give the battle map its ground, so holding high ground on the
   overworld is a real position). **Design (user, 2026-10-09):** a river crossing gets its **own
   dedicated battle map**, generated from a **frozen seed per crossing**
   (rivers do not change within the period: the same crossing is the same
   map every time, so it can be learnt and planned for, as settlements
   are from their seed). A **fortified army at a crossing sets up its
   camp at the crossing** (the fortified camp placed against the ford /
   bridge mouth, its ditch and palisade covering the exit), so attacking
   a fortified army at a river is clearly more dangerous than meeting an
   unfortified one there: the defender holds the bank, the attacker
   crosses under fire into works. Ties into the formula (fortified at a
   crossing) as the camp does.
   **Pontoon bridges** (user idea, 2026-10-09; agreed in principle): a
   field work the attacker (or defender) lays during the battle, never a
   prerequisite: a foot unit ordered to a bank stretch builds it a section
   at a time (seconds per section, as foraging), the allowance by Workshop
   level like stakes / caltrops; finished, a narrow one-unit lane, slow to
   cross as a ladder lane, wooden (fire arrows and artillery take it).
   The ford is free but defended, the bridge undefended but costs time, a
   unit and an allowance. Balance by a crossing row in the equal-force
   harness (fortified defender vs attacker with / without spans); must
   never be faster than marching to the ford.
4. **Cities must be worth defending** (agreed 2026-10-07, moved ahead of
   everything else after the Skilled campaign AI found that an army is
   better off fortified outside a city than inside it: in the formula
   only the garrison gets the wall bonus (+15 % a level) while a fortified
   field army gets +25 %, 88 % of attacked cities fall, no AI siege has
   ever ended in surrender; in the sim walls-3 attackers win 87-100 % of
   the 1.5-2:1 `siege_test` battles). Principles: **no stat bonus for
   standing inside walls**; defence is attrition at the wall and a slow,
   narrow street fight. In three parts, all sim-first, the formula fitted
   to the sim afterwards, none a save-format change:
   1. **Done 2026-10-07: attrition at the wall** (see "In progress right
      now" for the table: walls 3 about 30 % with ladders and a ram, none
      on arrival; walls 1 missed, 100 %). As agreed: wall archers hit
      harder from the battlements (cover / height levers), **arrow towers
      at walls 2** shooting siege bolts and **two stone throwers mounted
      on walls 3**, immobile garrison engines with a fixed ammunition
      load (+ammo from a building inside), crews that can be shot and
      towers that batteries can duel; walls-2/3 gates nearly immune to
      hand weapons and somewhat tougher; **attacker siege equipment:
      ladders** (foot units climb the wall from outside, slower the higher
      the wall level) **and a ram** (a slow engine unit the gate yields
      to), earned by siege turns in the campaign (optional key on the
      siege entry, no format bump) and chosen in custom battles, so
      without artillery you bring ladders and a ram or starve them (added
      2026-10-07); a **battle time limit setting** (today a fixed 15 min
      `BattleSim.TIME_LIMIT`) in the campaign settings, custom battles
      and the sandbox so long sieges can run. Calibration target: an
      **equal-force siege matchup set**, walls 3 equal strength ->
      attacker about 25 %, walls 1 about 45 %.
   2. **Units do not pass through each other** (part 2a done 2026-10-07:
      blocking, queueing, street frontage, gate rush; walls 1 still 100 %,
      see "In progress right now"; open: the defenders' disposition at
      walls 1, the rest of this item): unit-level blocking first (an enemy unit's footprint is impassable
      in the 4 m pathing grid, frontage clamps to the corridor a unit is
      in, friendly units pass through each other at half speed so streets
      never deadlock), soldier-level separation only at the contact seam
      if it still reads wrong; walls thicker and walls-2/3 cities 15-20 %
      larger inside, measured against the city tick budget; stone
      throwers over the walls at the army inside. Then siege equipment
      over turns (ladders / towers after 2-3 turns), suburbs and river
      sites, sallies from inside.
      **Part 2c done 2026-10-08: the defender layout** (AI.md 16,
      DESIGN.md "Unit blocking and street fights"): the attacked gate read
      from the field, the foot stacked in its inner mouth (front across
      the gateway, the rest behind and falling on whatever comes out),
      quiet gates' guards to the stack (tokens left, re-garrison on a
      second attack), plaza reserve, relief (Average while fighting under
      40 %, Skilled between waves; Easy keeps the old reserves), gates
      shut with nobody in their mouth; sim rule: defending routers inside
      the walls run to the shut gate farthest from the enemy
      (`ROUT_INWARD`), not out through the breach. Fair sieges (both
      Average, 10 seeds, attacker wins ladders + ram / artillery only;
      HEAD -> now): ring walls 1 100 / 100 -> 40 / 30 %, walls 2 50 / 20
      -> 20 / 20 %, walls 3 20 / 40 -> 0 / 0 %; polis walls 1 80 / 100 ->
      50 / 60 % (20 % draws each), walls 2 50 / 40 -> 20 / 0 %, walls 3
      20 / 0 -> 10 / 0 % (30 seeds walls 1: ring 46 / 46, polis 53 / 60 %).
      **Open:** walls 2-3 now far below their targets (50 % / 25 %): the
      attackers lose 200-300 men at the wall and can no longer win the
      street; wall levers alone do not restore it (AI.md 16). Easy
      defenders do about as well as Average in the polis.
   3. **Fit the formula** to the measured siege results across force
      ratios (a walls term for the armies inside is a prediction of the
      sim, not a bonus), turn the campaign AI's shelter knob back on and
      re-run the AI tables. **Done 2026-10-10** (parts 1-3; "Siege pass
      (2026-10-10)" in "Where we are"): equal-force full kit ring / polis
      walls 1 40 / 40 %, walls 2 20 / 10 %, walls 3 0 / 50 % (targets 45 /
      35 / 25: walls 2 and ring walls 3 still low, the attackers lose the
      approach); `WALLS_PCT` walls 1 115 / 115 / 114, walls 2 162 / 162 /
      158, walls 3 262 / 178 / 158 %, `FORTIFY_DEF_PCT` 119; calibration
      78 -> 87 % favourite agreement; Skilled `SHELTER_PCT` 70.
4b. **Battle screen on the overworld** (**done 2026-10-07**, see "In progress right now"; agreed 2026-10-07, next build
   after part 2b, before part 2c): one screen in two states, used for
   auto-resolve and fought battles alike. *Pre-battle* (replaces the
   auto / fight choice): a map preview at the top (the settlement drawn
   from its seed via `city_preview.gd`, or the field's terrain kind and
   woods, with both deployment edges marked); both sides' compositions
   as rows of unit cards (icon, men, tier) with a **health bar under
   each card** (current men vs full strength), attackers left, defenders
   right, grouped by army and faction, garrison and support armies
   included; a siege equipment line (ladder sets, ram, towers); the odds
   bar and the existing buttons (Auto-resolve / Fight / siege choices).
   *Result* (after auto-resolve, and after a fought battle): a big
   VICTORY / DEFEAT / DRAW with the one-line outcome (city taken / held,
   army destroyed, withdrew), labelled "Auto-resolved" or "Fought"; below
   it, per side, the same card rows with survivors vs fielded as the
   health bar (lost part marked) and kills beside each unit, totals at
   the foot; Continue. Fought battles take the sim's tallies, auto-resolve
   the formula's per-unit losses.
4c. **Done 2026-10-08** (see "Where we are" and CAMPAIGN.md "Gifts between
   players"; the receiver's offer to buy is its own order, `buy_region`).
   **Gifting cities and money between co-op players** (asked
   2026-10-07). A player may gift a region they own to the other human
   when **no army of theirs stands in the city** (garrison stays with the
   city); the offer carries an optional price either way (the giver may
   ask for payment, or the receiver may offer it), so money can also be
   gifted on its own. Orders like the existing treaty / exchange orders:
   `gift_region` (r, to, price) and `gift_money` (to, amount), resolved in
   `cturn` as rules (both humans alive, owner check, army check at
   resolution, treasury check, refused otherwise), visible on the region
   dialog and the Diplomacy screen for the ally, with an accept step for a
   priced offer (two-turn handshake like a treaty) and immediate for a
   free gift. No format bump if the pending offer lives in the existing
   diplomacy / proposal structures; else an optional key.
4d. **Done 2026-10-09 (not committed; see "Where we are").** **Ammunition types** (asked 2026-10-08): a second missile kind per
   shooter, chosen per unit in battle (a toggle on the card like Fire /
   Skirmish, with a fixed share of the load, e.g. a third fire arrows),
   available by faction / building and balanced against the standard
   kind, never strictly better:
   - **Fire arrows** (archers; Greeks, Syracuse, Carthage first): less
     damage, more morale shock, −range; ignite wooden things they land
     on (towers, gates, ladders, rams, engines) for chip damage over
     time; a burning unit's morale drains until the fire is out.
   - **Heavy bolts** (bolt throwers and arrow towers; Rome, Syracuse):
     more damage and pierce, shorter range, slower rate.
   - **Fire javelins** (javelin and light foot of Iberia, Gaul): as fire
     arrows for the thrown kind.
   - **Stones**: standard; **fire pots** (more damage to buildings and
     towers, set them alight, less to men); **explosive** (bursts: a
     blast radius against men and engines, less against walls; late,
     expensive, rare by building).
   Sim: ammunition kind per unit (hashed), a per-kind row in
   sim/unit_types.gd's missile fields (damage, pierce, range, rate,
   fear, blast, incendiary), fire as a per-object state on gates / towers
   / equipment with a burn timer and chip damage; AI uses the kinds
   (fire at wooden targets and wavering units, heavy bolts at engines
   and armour) through profile knobs. Campaign: which kinds a faction's
   units carry comes from the faction roster and a building (Fletcher /
   Workshop chain), no state format change if stored on the unit entry
   as an optional key. Battle screen and unit book show the kinds.
4e. **Done 2026-10-09 (not committed; see "Where we are").** **Resupply: foraging in woods and an ammunition wagon** (asked
   2026-10-08). Builds on the artillery refill that exists (ORDER_REFILL:
   a battery settles for REFILL_FULL ticks and draws shots from its finite
   reserve, shown "44+44" on the card).
   - **Foraging:** an archer (and javelin) unit standing in woods can be
     told to make arrows: it cannot move or shoot while doing it, takes
     real time (slower than the wagon, e.g. a quiver in 2-3 minutes),
     stops when attacked or ordered away, and fills only the unit's own
     quiver (not its reserve). Card button "Forage" shown only in woods;
     AI uses it when idle and empty behind the line (knob).
   - **Ammunition wagon:** a unit type recruited from the standard siege
     building (Workshop chain) that takes an army slot; a slow, unarmed
     crew with a wagon (sprite/marker like an engine), roofed like the
     ram, capturable / destroyable (fire). In battle, missile units and
     batteries within a short radius refill their quiver and reserve
     from the wagon's finite stock when told to refill (the artillery
     refill order generalised: a unit near the wagon, not moving, takes
     REFILL_FULL ticks to settle, then draws from the wagon until full or
     the wagon is empty). One wagon carries a fixed stock per missile kind
     (ties into 4d ammunition types: the wagon can carry the special
     kinds). AI brings it behind the line, guards it, and sends empty
     missile units to it (knobs). Campaign: it is a unit (`unit_types`
     row, roster line "siege"), so it costs upkeep, can be gifted and
     exchanged, and auto-resolve counts it as a small strength plus a
     missile bonus for the army; no format change.
     **Tiers and handling (decided 2026-10-08):** level 1 a hand cart the
     crew pulls at walking pace or slower; level 2 one horse (marching
     pace; the horse is a shootable hit box, dead -> crew pace); level 3
     two horses (trot; one dead -> level-2 pace). Crew dead: the wagon
     stands, anyone may harvest it, nobody moves it. **Any foot unit may
     take the wagon** like the ram: it becomes the crew, moves at the
     wagon's current pace (horses alive -> horse pace), cannot attack or
     shoot, fights at the carrier penalty and is badly exposed to flank
     and rear hits; Drop at any time. The enemy may take an abandoned
     wagon too: refill from it or burn it (4d fire). Guarding it matters.
5. **Elephants and camels done 2026-10-09 (not committed; see "Where we
   are" and DESIGN.md "Camels and elephants")**; chariots and war dogs to
   come. **Elephants**, then camels, chariots, war dogs. Roles agreed
   2026-10-08 (shock cavalry as the yardstick: mass 400, charge 70, run
   ~8 m/s, 90 degrees in 1.6 s):
   - **Camels**: slower (run ~6.5 m/s, 90 degrees in ~2.2 s), weaker
     charge (~45), better rider defence against foot, tire slower; their
     job is the **horse scare**: enemy cavalry within ~30 m takes a
     control penalty (lower charge, slower turns, a morale tick) and
     horses charging camels suffer for it; camels vs spears lose like any
     rider; unaffected by arid ground penalties, slow in woods. Carthage
     and Numidian / eastern rosters; a camel-archer missile variant.
   - **Elephants**: mass 2,000+, wide knock-down charge that breaks
     formations (spears still hurt them), slow to accelerate and turn
     (~4 s), run ~6 m/s; a **fear aura** (~25 m, horses more than men);
     one big body with hit points and a crew (driver + 2-3 shooters from
     height); missiles chip, fire (4d) is the counter; batter walls-0/1
     gates only, kept out of narrow streets. On breaking they **run
     amok**: erratic, trample anyone including their own side; the
     driver can be ordered to kill it (delay). **Calming (user,
     2026-10-08): a panicked elephant that ends up on its own, with no
     enemy and no friendly units nearby, cools down and the rider takes
     control again; while any units are near it stays amok.** Carthage,
     Epirus (Pyrrhus).
   - **Horses** stay speed and shock; camels the anti-cavalry screen;
     elephants the slow terror that breaks lines or breaks you.
4f. **Siege towers, field works, light artillery, mantlets** (agreed
   2026-10-09; field works also asked for by the co-op partner). In this
   order, the first two before the walls 2-3 rebalance because they bear
   on it:
   1. **Siege towers** (built 2026-10-09, not committed; see "Where we
      are") (the helepolis): a rolling tower given to the
      attacker by siege turns like ladders / the ram (walls 2+, e.g. 3+
      siege turns), moved into place by a unit like the ram, planted
      against a stretch; then whole units cross onto the wall through it
      (a wide, fast "ladder"), the escalade the walls 2-3 attacker is
      missing. Wooden: it burns (fire kinds are its counter); towers and
      stones wreck it. Icon exists (siege_tower).
   2. **Field works** (built 2026-10-09, not committed; see "Where we
      are"): in the deployment phase a stakes line and caltrops
      as placeable pieces (limited by the army's siege building / an
      engineer count), stopping or wrecking a cavalry / elephant charge
      across them and slowing foot; the **fortify stance** puts a ditch
      and rampart on the battle map for the fortified army (a low wall
      with no gate: attackers climb it slowly, defenders on it get the
      wall missile bonus), giving fortify teeth against horse and
      elephants. Ties into the formula (fortified field army bonus).
   3. **Light artillery** (built 2026-10-09, not committed; see "Where we
      are") (scorpions, the gastraphetes): a small bolt
      engine row between archers and bolt throwers that a unit carries
      and sets up fast, for the ladder-and-ram army.
   4. **Mantlets** (built 2026-10-09, committed; see "Where we
      are"): a moveable missile shelter piece (the ram's roof
      generalised) a unit stands behind. Sheds (a roofed mantlet against
      stones) not built.
   **Later / campaign:** mining (undermining a wall over several siege
   turns as a campaign action), a Syracusan tower upgrade (Archimedes'
   engines: range and reload). Not of the period: onagers, cart
   ballistae, scythed chariots.
5b. **More units before the rebalance** (agreed 2026-10-09, in this
   order, so the field is tuned once with the whole roster present):
   1. **Missile cavalry** (built 2026-10-09 with point 2, see "Where we
      are") (javelins from the saddle, skirmish mode, fast,
      weak in melee): Numidian horse for Carthage, Tarentines for the
      Greeks, Epirus and Syracuse, light horse for Gauls and Iberians.
      Data rows on the existing cavalry / missile / mount fields (camel
      archers with mount 1).
   2. **Slingers** (built 2026-10-09) (long range, low damage, good against unarmoured men;
      lead bullets as an ammunition kind): Balearic for Carthage, Rhodian
      for the Greeks, native for Iberia. A "sling" base missile row.
   3. **A general and his bodyguard** (built 2026-10-09, not committed; see
      "Where we are"): a command aura (the fear aura
      inverted: morale held up within a radius, a rally bonus, a big hit
      when he falls); campaign armies get a leader.
   4. **War dogs** (built 2026-10-09, not committed; see "Where we are"): a handler unit (weak light foot) that releases its
      pack as an order; the pack is a fast, fragile unit strong against
      skirmishers, missile troops, routers and crews, useless against
      formed heavy foot and spears; it fights until dead or until no enemy
      is near, then returns to the handlers (the elephant calming rule
      reused); never routs; a small scare on light troops only. Epirus,
      the Greeks, Rome, Gauls. Dogs are the pursuit tool now that ranks
      hold together and men no longer chase routers on their own.
   Not for these factions: chariots (Britons, Pontus, Seleucids), naval.
   Mercenaries are a campaign recruitment feature for later.
6. **AI competency** (`docs/AI.md`): Easy / Average / Skilled on two
   independent axes (battle, campaign) plus personality, no cheats ever;
   skill is reaction, perception, planning, execution and deliberate
   plausible mistakes. Decided 2026-10-06: AI obeys fog of war (superseded 2026-10-17: the AI sees everything; fog is the player's) if it ever
   exists; difficulty global with per-faction Advanced overrides;
   personalities and army composition styles per faction by default.
   **Step 1 done (2026-10-06): profiles as data, no behaviour change.**
   `sim/ai_profile.gd` (148 battle / settlement knobs) and
   `campaign/cai_profile.gd` (60 campaign knobs), Average / Balanced = the
   old values exactly (Easy and Skilled rows are copies for now); scenario
   `ai_skill` / `ai_style` per side (hashed only when not default, kept by
   snapshots), campaign `settings.ai_battle_skill` / `ai_campaign_skill`
   and `factions[i].ai_skill` / `ai_battle_skill` / `ai_style` (written
   only when not default: no `CState.VERSION` bump); new-campaign
   "Difficulty" row and sandbox "AI:" button (Easy / Skilled marked
   "soon"); per-competency counters (`BattleSim.stat_aic`, campaign
   `CP.count`, printed by `campaign_sim`); `cdata` FACTIONS `ai_style`
   (all Balanced) and `composition` placeholders. Verified: determinism
   golden digests and all final hashes, campaign_sim 6x60 per-seed
   hashes, sieges, campaign_test / solo / battles equal to HEAD.
   **Step 2 done (2026-10-06): Easy, battle and campaign** (`docs/AI.md`
   section 10). Battle: slower thinking, narrower perception, no terrain
   sense, marches straight in, archers never in skirmish mode, no
   fall-back of mauled units, chases routers, plus a deliberate-mistake
   roller on the sim RNG (9 mistakes, per-side cooldowns in hashed
   `BattleSim.ai_mist`; lockstep and snapshot tested). Average beats Easy
   74 % (flat) / 71 % (hill) of mirrored battles; Easy vs Easy 50 / 50,
   no draws. Campaign: cheapest builds, one recruit a turn, nearest
   targets, no gathering / screens / relief / stances, storms on arrival,
   no peace, 5 mistakes on `CState.rand`; an Easy faction ends about as
   big as at Average (target not met: Average's caution costs it as much,
   see AI.md). Several "Easy" behaviours (no pull-outs, unguarded
   batteries, nearest targets, early charge) beat Average and were kept
   at Average: a lead for step 3. Average / Balanced byte-identical
   (determinism, sieges, campaign_sim hashes). UI: Easy without "(soon)".
   **Step 3 done (2026-10-06): Skilled battle and settlement AI** (`docs/AI.md` section 11; reserves, rotation, matchups, focus fire, siege wall shift / breach / sally; beats Average 72 % flat, 67 % hill, Easy 89-95 %; Easy / Average byte-identical).
   **Step 4 done (2026-10-07): Skilled campaign AI** (`docs/AI.md` section 12; `SK_*` knobs in `campaign/cai_profile.gd`, 0 at Easy / Average): never shelters inside the walls (fortifies outside), support-aware hunting at two to one, spare armies merge into / stand by the main army, staging and falling back out of the enemy's reach next turn, storming before a relief, counter-composition, war when the neighbour's armies are away from the border, peace offers to close a second front; no mistakes. One faction Skilled ends turn 60 with +47 % regions over 24 seeds (6.58 against 4.48; +44 % on 6) and 41 eliminations against 70; Macedon not better (3.7 against 4.0, noise). ~0.8 ms per Skilled faction-turn. Average / Easy byte-identical (campaign_sim hashes; golden hash and RNG in campaign_test); no state change, VERSION 6. UI: Campaign AI Skilled without "(soon)". `campaign_sim --knob=` for ablations. Next: step 5 (personalities and composition styles per faction, the Advanced per-faction UI, the split setting).
7. **Mid-battle reinforcements** from the map edge: **built 2026-10-13**
   (no bounce past 24 field units; reserves arrive as slots free or after
   2 minutes; see the row above and DESIGN.md "Reinforcements"). Still
   open: the ambush stance once hidden information in an async game is
   designed.
8. **N-player campaign** (asked 2026-10-09; moved ahead of the shared
   empire: two empires working together already plays well): three or
   more players in one campaign, with the end goal that **every faction
   can be an AI or a real player**. The state already keeps `humans` as a
   sorted list (permanently allied today). **Design (user, 2026-10-09):**
   **teams** as a campaign setting rather than a fixed human alliance:
   every faction starts as a team of its own and may join or be joined by
   others; the new-campaign screen shows a dropdown per faction with the
   team it is on, plus two buttons, "all humans one team" and "everyone
   on their own"; the permanent-alliance rule becomes "factions on one
   team". Once the campaign runs, **the diplomacy screen offers a team
   (alliance) proposal** to any faction, human or AI; accepted, it grants
   movement through the ally's territory and repair / resupply of armies
   standing in allied zones (today's co-op perks generalised). Open
   points: humans on different teams at war with each other (hidden
   information, diplomacy between humans), the turn deadline with N
   submitters, battles with several humans on one or both sides (the
   co-op join flow generalised), seats and invites per faction on the
   server, AI / human per faction on the new-campaign screen, leaving a
   team (notice turns, as the AI's war declarations work).
8a. **Heroes and agents** (**built 2026-10-10**, both halves: see the "Heroes and agents" rows; not exported until the N-player UI; asked 2026-10-09, after the N-player campaign; **campaign and UI side built 2026-10-10**, see the row;
   Warhammer 3 style). **Heroes**: characters attached to an army without
   taking a unit slot (a character list on the army, not a unit: a
   `CState.VERSION` bump), one hero per army; a single man with a large
   health pool and an **area buff by kind**: foot (steadiness, to-hit),
   missile (range, accuracy), cavalry (charge, rally), siege (ladders,
   reloads, ram / tower toughness); each fights well in his own field and
   is a prime target for wall bolts. The general is the first hero
   (command aura) and the model to generalise. Fallen: wounded for N
   turns rather than dead (to decide). The AI must use them (an aura knob
   per kind). **Agents** (the co-op partner's ask): an **assassin** and a
   **diplomat**, one each per army, playable on the field as support
   pieces when attached. Assassin: a single hidden man; orders Sabotage
   (wreck an engine; in a siege open a gate from inside) and Attempt
   (adjacent to the enemy hero / general: roll to wound or kill, the
   general-falls morale hit). Diplomat: Parley on a broken or nearly
   broken enemy unit so it surrenders instead of dying (prisoners:
   ransom / recruits), a steadying aura on wavering friends, a beaten
   garrison surrendering to him for the city intact. Hidden characters
   and parley need hidden information: design with the N-player campaign
   and the ambush stance (item 7).
8b. **Audio** (asked 2026-10-07; **built 2026-10-10**, see the "Audio" row; levels untuned).
   Audit 2026-10-13 ("no audio" report): desktop and the web export (headless Chromium, context suspended until the first click) both pass every gate and play; if it is silent on a device, suspect a stale build/web or the device volume.
   Battle: melee clash, charge impact, volleys and artillery release /
   impact, gate blows and the gate breaking, ladders and towers, unit
   breaking / rallying, a battle horn at start and at the result; mixed by
   distance to the camera and capped per category so 4,000 men do not
   stack 4,000 sounds (one emitter per event bucket per tick). Overworld:
   taps and button clicks, order placed / refused, end of turn, a turn
   resolved and a battle pending (also the notification sound), treaty and
   trade. A light ambient bed per screen (march drums / wind for battles,
   a quiet loop for the map). Music optional and last. Web constraints:
   audio starts only after a user gesture (unlock on the first tap),
   Compatibility renderer and threads off mean the sample player, not the
   worklet; keep total asset size small (OGG, short clips). Sources:
   generated or CC0 packs; settings row for volumes (master / effects /
   ambient) in `user://settings.cfg [audio]`. Nothing in the sim: sounds
   are driven from the view reading sim events, as the animation pipeline
   will be.
8c. **UI icon pass** (asked 2026-10-07): icons where a word stands alone
   today — the top bar (treasury, income, turn / season), the map key
   entries, order kinds on the army card (move, siege, assault, sally,
   stances, merge, exchange, recruit, gift), the overworld buttons
   (Battles, Realm, Diplomacy, Goals, Units, Menu, Undo, Deselect, End
   turn), region dialog buildings and the recruit list, battle HUD
   buttons (fire / hold, skirmish, run, deploy, wall orders, pick up /
   drop, withdraw), the battle screen's outcome banner and totals,
   siege equipment and towers. One consistent line style and size at the
   touch scale, drawn in code or a small SVG set under `assets/icons/`,
   reused by `unit_icons.gd`'s approach; text labels kept beside icons on
   buttons where a bare icon would be unclear. Includes a pass on
   spacing / alignment of the rows that gained buttons this week.
   Phase 1 built 2026-10-09, committed (9d7ddf3): `game/ui_icons.gd`, Kit
   helpers, icons on the overworld (top bar, buttons, army card, region
   panel, recruit lists, diplomacy / gifts, map key, dialogs), online UI and
   custom battle setup; bottom-right row and diplomacy deal rows aligned
   (DESIGN section 8 "Icons"). Tested: check_scripts, icon_gallery,
   windowed campaign_input_test, touch_scroll_test (only its known
   failures), custom_battle_test. Phase 2 built 2026-10-09 (not
   committed): battle HUD buttons with icons (Menu and Deselect bare; fire /
   hold fire swap; on a narrow screen the order toggles drop the order word
   and keep icon + state, e.g. "hold"), battle screen Auto-resolve / Fight,
   equipment line, result banner between two icons, totals as an icon row
   (men, dead, fled, kills). Tested: check_scripts, windowed input_test,
   battle_screen_test, custom_battle_test, windowed campaign_input_test.
   Screenshots `docs/screenshots/icons_{before,after}_phone_battle_*.png`.
9. **Server to Proxmox** via `server/deploy/docker-compose.yml` (Podman),
   plus delete-campaign and revoke-device admin. Independent; whenever the
   user wants the server off the dev machine.
10. **Sprite animation pipeline**: parts + procedural motion workflow and
    tooling, written up in `docs/ART_PIPELINE.md`. Last on purpose: the
    symbolic soldiers stay until the game is in a good state.

Further out: the American West game as a data set and roster on the same
campaign engine; a 3D client remains possible without sim or campaign
changes (view-only), but art cost, not code, is the deciding factor.
