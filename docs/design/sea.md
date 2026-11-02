# Sea (the Caribbean pack, sea battles)

Moved verbatim from `docs/DESIGN.md` on 2026-10-22 (the docs split; index in `docs/DESIGN.md` and `docs/design/README.md`). Design sections first, then the "as built" sections in date order.

### The Caribbean pack: ships, pirates, cover, asymmetry (agreed 2026-10-14)

The West pack's first setting is the Caribbean and Gulf, 1650 (slice 1 as
built: STATUS "The West pack, slice 1"). The user's decisions on
2026-10-14: sea battles are **real time with the wind**; pirates are
**raiders with havens**; armies cross the sea by **embarking on fleets**.
Battle balance waits until ships, cover and asymmetry are in.

**Fleets (campaign, West pack only; Rome keeps its sea lanes).** Ship
rows are data (pack "west"): sloop (fast, few guns, carries 1 unit),
brigantine, frigate (carries 3), galleon (slow, heavy, a treasure hold,
carries 6), ship of the line (England / Dutch top tier), and piraguas /
war canoes (Miskito, Itza: coastal water only, fast; carry 3, 4 and 6 since
2026-11-02, see "Native vessels carry more"). A fleet is
a campaign piece on sea cells with the overworld's continuous movement.
Its reach per turn depends on the heading against the map's baked wind
(`relief_west` WIND: the trade winds from the east), so running west is
quick and beating east is slow; integers only, from the grid's sea cells.
An army boards a fleet in port or on a coast cell beside it, up to the
fleet's capacity, moves at the fleet's pace and lands on any coast cell
(a landing takes the rest of the turn). Enemy fleets in reach intercept;
transports in a lost sea battle are sunk or captured with the men on
board. Ports build and repair ships (a shipyard chain); a long time at sea
costs a little crew (scurvy).

**Trade and the treasure fleet.** Each port's trade income travels by
sea: an enemy fleet blockading a port (on its approach cells) cuts it and
takes a share as plunder. Every few turns Spain's flota gathers galleons
at Veracruz and Portobelo, meets at Havana and sails off the map east;
whatever arrives pays a large sum, and whatever is intercepted is the
richest prize on the map.

**Pirates (the Brethren of the Coast).** Income is mostly plunder:
intercepted trade, blockade shares, the flota, and **sacking** coastal
towns (a landing and a battle; a won sack takes gold and wrecks buildings
without occupying). They hold a few **havens** (Port-de-Paix for Tortuga)
where crews recruit cheaply. A pirate faction is not eliminated while it
has a ship. **Infamy** rises with every sack and prize: more recruits
flock in, and the nations hunt them harder. **Letters of marque**: a
nation can hire them by treaty (privateering), so they leave that nation
alone and plunder its enemies at a bonus. AI pirates prefer weak, rich
targets.

**Sea battles (real time).** Ships are sim pieces with fixed-point
positions and headings that sail by the battle's wind (from the campaign
wind at the spot), with points of sail, tacking and stays. They fire
broadsides from their sides at range (round shot for the hull, chain for
the rigging, grape for the crew), take hull / rig / crew damage, and
grapple to board; a boarding becomes a deck melee in the existing soldier
sim. Forts and shore batteries fire on ships; ships can bombard shore
units in coastal land battles. Auto-resolve stays available and is fitted
to the real-time results.

**Cover (battle, slice 2b).** A unit trait `cover` (natives, buccaneers,
frontier militia, skirmishers): in woods, rocks, walls, fields and
buildings those men go to ground behind what is there and take far fewer
hits (missiles and guns), and they fire from cover. Line infantry (Spain's
tercios, English and Dutch foot) do not take cover: they stand in
formation, and their strengths are volley discipline, morale and pike
protection. Line of sight: woods, rocks and buildings block sight and
shots, so ambush works.

**Asymmetry (to design per faction).** Spain: rich, forts, tercios, the
flota, slow galleons. England and the Dutch: navies, trade, ships of the
line, strong guns. France: buccaneers, alliances with natives,
privateers. The Brethren: the pirate loop above. Itza: jungle, cover,
ambush, a lake fortress, no need of ships. Miskito: canoe raids, English
muskets by trade, friends of pirates.

### Sea battles (as built, N3a, 2026-10-14)

The "Sea battles (real time)" paragraph above, first playable version
(campaign hand-off: CAMPAIGN.md "Sea battles fought (N3a)"). Rule of cool on
real seamanship: ships sail by the wind, beat to windward in tacks, fight
with broadsides and boarders, strike their colours; speeds are about twice
a real ship's and ranges compressed so a frigate duel decides in a few
minutes.

- **A sibling sim, not a mode of BattleSim** (`sim/sea_sim.gd`, types
  `sim/sea_types.gd`): a sea battle has a handful of ships and no soldiers,
  so it shares none of BattleSim's per-man arrays, maps, engines or AI;
  apart, every land battle stays byte-identical (Rome goldens untouched).
  It keeps the same discipline and the interface the lockstep layer uses
  (`sim/lockstep.gd` picks it for a scenario with `"sea": 1`): integers and
  `FixedMath` (1 m = 1024, angles 0..1023), its own xorshift RNG, ship-index
  order, orders queued by (tick, player, seq), `state_hash()` over every
  state array, `snapshot()` / `restore()` of every script variable (the land
  grid rebuilt by `setup`), `result()`; a tick is 0.1 s.
- **Ships** (rows by the campaign keys: sloop, brigantine, frigate,
  galleon, ship of the line, war canoe): length and beam, top speed (sloop
  9.5 m/s ... galleon 6.0; canoes 9.8 rowed), rate of turn (sloop 9 deg/s
  ... galleon 3.4, slower without way), the no-go angle off the wind (sloop
  42 deg, brigantine 50, frigate 62, ship of the line 66, galleon 70; canoes
  none), the speed % needed to tack, guns a broadside (4 / 7 / 15 / 20 / 35
  / 1), shot weight, range (220-300 m; chain 80 %, grape 40 %), hull, crew,
  rigging, reload (10-17 s with a full gun crew), draught (deep ships run
  aground on shoals), boarding quality. State per ship: position, heading
  (x16), speed, sail (stop / battle 75 % / full), hull, crew, rig, troops
  aboard, gunnery and boarding quality, morale, mode (hold course, sail to a
  point, engage, board, flee, hold a heading), each broadside's loaded shot
  and reload, grapple, fire, captor.
- **Wind** from the scenario's bearing and strength; every 30 s it shifts a
  few degrees (seeded, within 35 deg of the start). **Points of sail**: no
  drive in the no-go zone, 45-80 % close-hauled, best (100 %) from the beam
  to the broad reach, 82 % dead before it; leeway pushes everything
  downwind. **Navigator** (every ship, any mode): straight to the goal when
  it can lie the course, else close-hauled on its tack to the layline then
  the other tack (the view draws exactly these legs); it turns through the
  wind when it has the way (tacking), else wears round; caught in irons
  without way the bow falls off; probes ahead turn it from land, shoals (deep
  ships) and the field's edge.
- **Broadsides**: a side (port / starboard, a 42 deg arc either side of the
  beam) fires all its working guns (fewer as the hull goes) when loaded and
  an enemy bears in range of its shot, the ordered target first, else (fire
  at will) the nearest, never through a friend. Each gun hits at 88 % x
  target size x (1 - 0.7 x range / max range) x gunnery quality. Round shot:
  hull, splinters among the crew, a little rigging, 0.5 % a hit to start a
  fire; chain: rigging (speed); grape: crew. Raking (from within 32 deg of
  her bow or stern) kills 2.5 x. Reload slows with too few men at the guns
  (4 a gun, both sides). A fire burns the hull until the crew puts it out (14
  % a second at full crew); each second 1.5 % (3 % after 30 s) the magazine
  goes: she blows up, her neighbours within 70 m are holed, lose men and
  catch fire. Hull 0: she sinks.
- **Boarding**: ordered (or the AI) to board, a ship sails alongside,
  matching speed; within (lengths x 0.4 + 8) m at under 3.5 m/s relative
  speed she grapples, both stop and drift together; each second the
  boarders (crew x boarding quality + troops x 1.2) and defenders (the same,
  x 125 % on their own deck) lose 5-8 % of the other's strength; the
  defenders are taken under 40 % of the boarders, the boarders thrown back
  under 50 % of the defenders or after 60 s. The prize gets a prize crew
  (an eighth of the captor's, at most 40). A struck ship laid alongside is
  taken at once. **N3b hook**: scenario `"deck": 1` stops the sim resolving
  a grapple; `deck_request()` lists the grappled pairs (ships, sides, crews,
  troops, qualities: the data a deck melee in BattleSim needs) and the
  order `O_DECK` (boarder, target, won, crews left) applies the melee's
  result, through the lockstep like any order.
- **Morale and the end**: hits lower morale by the share of hull and men
  lost (raking more), a ship struck, sunk or taken nearby by 8-12; quiet time
  restores it. A ship strikes at 0, or with under 18 % of her crew (or 12 %
  hull and a wrecked rig) with an enemy within 400 m; struck, she stops and
  is out of the fight. A side with no ship fighting has lost (fled ships
  escaped); at the time limit the fighting power left decides (ties: the
  defenders). The loser's struck ships are taken; the winner's hoist their
  colours again.
- **Battle AI** (each ship every second, staggered): run for the edge away
  from the enemy (preferring a fast point of sail) when beaten (hull < 28 %,
  crew < 32 % or morale < 22 and the enemy stronger); else the nearest
  weakest enemy (kept unless another is much better); board when its
  boarding strength (with friends already boarding her) is 1.6 x hers (1.3
  x since sea pass 4, below) and
  she is close or crippled (not a ship outrunning it); else engage: beyond
  ~600 m beat up to a point 220 m to windward of her (the weather gauge),
  then hold the broadside on at the loaded shot's range, presenting the
  loaded side, opening when too close (raking comes from the geometry);
  grape inside grape range on a manned ship, chain when it means to board
  her and she is in chain range, else round; battle sail inside 320 m.
- **Water**: a land grid of 20 m cells (sea, shoal, land) from the scenario's
  `land`: open sea, an island (a ragged blob with a shoal ring), or a coast
  along the sides given (the campaign cell's land neighbours), ragged by
  integer sine noise, with shoals off it; ships start clear of it.
- **Orders** (types inside the lockstep's sim-order range): `O_SAIL` x, y;
  `O_TARGET` target; `O_HOLD`; `O_SAILS` 0-2; `O_FIRE` on; `O_SHOT` kind;
  `O_FLEE` (what the lockstep's army withdrawal sends); `O_BOARD` target;
  `O_HEAD` facing; `O_DECK` (N3b).
- **View** (`game/sea_battle.gd`, touch first): tap a ship of yours (double
  tap: the fleet; long-press drag: a box), tap the sea to sail (several
  ships spread in a line abreast; the planned course drawn with its tack),
  tap an enemy to engage, Board armed then an enemy to board; one finger
  pans, two pinch, the wheel zooms; the bottom bar: Full sail / Battle sail
  / Heave to, Round / Chain / Grape, Fire at will, Board, Hold course, Flee;
  the left column your ships (hull, crew, rig bars, both broadsides'
  reload); the wind rose; speed II / 1x / 2x / 4x; Leave (a defeat). Drawn:
  waves running before the wind, land and shoals (the grid smoothed),
  top-down hulls 1.5 x their size (to read on a phone) with gunports, a
  rail in the faction colour, masts and square sails braced round with the
  wind and bellied by the drive (a sloop's boom swings to leeward), torn
  and shot away with the rigging, furled when hove to or struck; the
  ensign (white when struck, the captor's when taken); wakes; broadside
  smoke and muzzle flashes along the firing side drifting with this battle's
  wind (the land battle's gun-smoke look), shot streaks, splashes for
  misses and splinters for hits; fires with smoke columns; the magazine
  blast (fireball, shock ring, pall, wreckage); sinking; grapples; the
  selected ship's broadside arcs and reach. Messages: grapples, prizes,
  strikes, sinkings, fires, groundings, escapes.
- **Custom battle**: the West setting's "Sea battle" (solo): ships per side
  (up to 8), wind direction and strength, water (open / island / a coast),
  start (across the wind, your fleet upwind or downwind).
- **Measured** (`determinism_test --only=sea`): STATUS "N3a".
- **Later**: smoke blocking aim, shore batteries and forts firing on
  ships, ships bombarding shore units, the formula fitted to these results,
  sea battle art (the miniatures at headings), sounds of the sea. (Live
  co-op at sea, N3b deck melees and N3c fire ships: built, below.)

### Sea battles: live co-op, deck melee, fire ships (as built, N3b / N3c, 2026-10-16)

The three follow-ons to N3a (campaign hand-off: CAMPAIGN.md "Sea battles
fought", the co-op, deck melee and fire ship bullets).

- **Live co-op at sea** (milestone 5 rules unchanged: everything shared
  lives in the sim or the lockstep, changes only by lockstep inputs): the
  lockstep already ran a SeaSim; what was missing is the room and the view.
  `CSeaBattle.build` gives `controller` / `battle` / `sim_side` as
  `CBattle.build` does, so `CoopSession` takes a sea battle unchanged
  (`live_ai_sides` keeps a sea scenario's per-side AI flags, its telemetry
  no longer reads a soldier count from a SeaSim). `CampaignScreen.fight_live`
  opens a sea battle's room like a land battle's (`_fight_sea_live`), and
  `game/sea_battle.gd` runs in co-op the way `game/battle.gd` does: it
  follows the lockstep's sim (rebinding on start and on a snapshot restore,
  events not replayed), interpolates by the session's frame clock, sends
  orders through `coop.issue()` for the ships this player commands only (a
  tap or a card of a team-mate's ship says whose it is; double tap and box
  take only your own), II and the speeds are votes (II asks to pause or
  resume; a speed while paused also asks to resume; choosing the speed in
  force withdraws your proposal), Gift in the orders bar hands the selected
  ships to a team-mate (the picker with several), the card column carries
  each ship's commander colour once a team-mate takes part, the co-op HUD
  (`game/coop_hud.gd`: roster strip, lobby, waiting / catching up / resync,
  vote chips with Accept / Decline, Continue without a disconnected player)
  sits over it through a small shim of the land HUD's names, Leave says who
  gets your ships, Continue at the end waits for the final frame, and
  `coop_exit_result()` is what the campaign screen uploads (the host once;
  the last player's forfeit of their own side). Testing aids:
  `--coop-start-alone`, `--coop-auto-exit`. Not reachable from the Online
  battles list until `online_ui.gd` stops gating "Fight together" off for
  sea battles (CAMPAIGN.md).
- **Deck melee (N3b): an integer crew-against-crew melee inside the sea
  sim**, not the land sim. Reusing BattleSim for a deck would have meant a
  second simulation nested in every sea battle (its own map, snapshot and
  hash, its result fed back by an O_DECK input that some peer would have to
  issue), for a fight of a few dozen groups on a 2 m grid; inside the sea
  sim it is a few hundred integer operations a deck step, hashed, in
  snapshots and in lockstep by construction. The N3b hook stays: scenario
  `"deck": 1` still parks a grapple for an outside melee (`deck_request()`,
  `O_DECK`, now refused unless a boarding is waiting for one).
  - **The deck**: both ships side by side as a grid of `DECK_CELL_M` 2 m
    cells, each ship her length by her beam (5-28 by 2-7 cells), the
    boarder's rows above the rail, the defender's below, masts in the way.
  - **The men** as figures of a few men each, at most `DECK_FIG` 24 a side:
    the boarding party (`DECK_BOARD_PCT` 75 % of the crew and every soldier
    aboard) against every defender; the soldiers at the rail, the crew
    behind, the captain and two mates at the stern. Arms: the crew kit by
    faction (`ST.DECK_CREWS`: the Brethren cutlass, axe and a brace of
    pistols 34 / 22 and two volleys; Spain sword and buckler 28 / 28;
    France boarding axes 30 / 22; England and the Dutch cutlass, pistol and
    pike 27 / 24; Miskito and Itza clubs and bows with three volleys) times
    the ship's boarding quality; soldiers by their unit rows (attack;
    defence + armour + shield / 2) and their line's volley
    (`ST.DECK_LINE_SHOT`: muskets 26 % at 7 cells, buccaneers 34 % at 8,
    pistols, bows); soldiers without a kit musket and bayonet; the captain
    at `DECK_CAPTAIN_ATK` 250 % (x the campaign captain's `cq`).
  - **A deck step** every `DECK_EVERY` 2 ticks, figures in index order
    (reversed every other step): strike the nearest enemy figure next to
    it (each man kills at `DECK_KILL_PM` 14 per mille x 2 atk / (atk +
    def); a figure on its own deck defends at `DECK_BONUS_PCT` 125 %;
    shaken men strike weaker), else fire a loaded volley in reach (shot %
    x `DECK_SHOT_PM` 5 per mille a man), else step a cell toward it (every
    `DECK_MOVE` 3 steps). Losses come off the ship's crew or troops at once.
  - **Heart**: each side's morale starts from its ship's (boarders +10),
    falls by the share of its men lost (`DECK_MOR_LOSS` 100 for all of
    them; a quarter less while its captain stands), `DECK_CAPT_LOSS` 30
    when he falls, a little each step when outnumbered. **The end**: the
    defenders strike (the deck is lost: the existing capture, a prize crew
    across) when their heart is gone or they are under `DECK_BREAK_DEF` 30
    % of the boarders; the boarders are thrown back (their ship's morale
    -25) when theirs is gone or they are under `DECK_BREAK_ATT` 45 % (after
    2 s); both at once, or `DECK_MAX_TICKS` 45 s: both crews are spent, the
    grapnels are cut and the ships part (-15 each). Ships in a deck fight
    do not strike by the ordinary rule (the deck decides).
  - Measured (probe runs, two ships laid alongside at the start): strong pirates take a
    weakened brigantine in 4-6 s, an even pair fights 15-28 s before the
    boarders are thrown back, a sloop boarding a frigate is thrown back in
    2 s, an English frigate with musketeers boarding a galleon with
    rodeleros is thrown back in 6-9 s.
  - **View**: an inset at the top right (a tap centres the pair) draws both
    decks in the diorama look (planking with seams, a grating, rails in the
    ships' colours, masts, grapnel lines across the gap), each figure as a
    little crowd of up to five men in its ship's colour (soldiers with a
    crossbelt, the captain ringed in gold), easing from cell to cell, cold
    steel sparks where it struck, powder smoke from volleys, each side's
    men and heart and "captain down"; the outcome stays 2.5 s. Sounds:
    `melee` while it lasts, `musket` per volley, `unit_break` / a horn at
    the end. Events `EV_DECK_SHOT`, `EV_CAPTAIN`, `EV_DECK_END`.
- **Fire (N3c)**: a fire has an intensity (`s_burn` 1..`FIRE_MAX` 1000):
  a hit's fire starts at 60, grows 25-45 a second and the crew beat it down
  by `FIRE_FIGHT` 45 x their share of a full crew (a full crew puts a small
  fire out in a few seconds, a thin one cannot); it eats the hull by its
  intensity (`FIRE_HULL`). **Magazines**: past `MAG_LV` 500 each second
  rolls (the sim RNG) (intensity - 500) / 4 per mille: she blows up, holes,
  kills and fires (at 250, half the time) her neighbours within `BLAST_M`
  70 m (N3a rolled 1.5-3 % a second from the first spark).
- **Fire ships (N3c)**: a ship row (`fire_ship`: 22 m, 9.5 m/s, no guns,
  hull 420, a crew of 14, `fire` 1). Ordered at an enemy (a tap with her
  selected; `O_TARGET` / `O_BOARD` become `M_FIRE`) she sails at the mark's
  place a little ahead, is lit inside `FS_LIGHT_M` 200 m when she can lie
  the course, her crew lash the helm and take to the boat inside
  `FS_ABANDON_M` 80 m (or `FS_ABANDON_TICKS` 30 s after); "Light her"
  (`O_LIGHT`) fires her at once; a fire ship that would strike, or that a
  shot sets alight (4 x a ship's chance), fires instead. Lit, she burns at
  `FIRE_MAX` (2 % of her hull a second, no hull penalty to her speed),
  takes no orders, does not count as fighting, is everyone's first target
  within 300 m; whatever she touches (either side) she grapples for
  `FS_STICK_TICKS` 25 s and sets alight at `FS_FIRE` 400, feeding its fire
  `FS_FEED` 80 a second; sparks catch ships within `FS_SPREAD_M` 25 m at 25
  % a second. **Battle AI**: a fire ship goes for the biggest enemy (guns
  and hull) when the wind serves (the mark lies at least `FS_SERVES` ~105
  deg off the wind, within 1.2 km), else waits 420 m up to windward of it.
  Measured (`determinism_test --only=sea`, the fireship set piece over 8
  seeds): lit in 8, reached and fired her mark in 6, magazines blown in 5;
  a Spanish line ahead to leeward: 2 contacts in 6 seeds (the line's
  broadsides sink the rest first). **View**: a tarred hull with brushwood
  and barrels; lit, flame tongues lean downwind along her length (by the
  fire's intensity on any burning ship), embers blow off, a black column;
  her crew's boat pulls away; orders drawn in orange with her lighting
  ring; messages; `burst` on lighting and contact. Custom battle: the fire
  ship is in the ship list.
- **Help on the sea screen**: every order has a one-line tooltip and a
  long-press card, sail and shot changes show a hint, and the Ship book
  (top bar) explains points of sail, sails (speed only), shot kinds,
  boarding, striking, fire and every ship row, all from the sim's own
  numbers (view only, `game/sea_book.gd`).
- **Determinism and cost**: all the new state (fire ship, crew kit, troop
  kit, melee slot and figure arrays) is in `state_hash()` (so in
  `Lockstep.state_hash()`) and in snapshots (script variables); `f_hit`
  (when a figure last struck, for the sparks) is view data, not hashed.
  Desktop: 60-70 us a tick, 160 us during a deck melee (worst 300 us);
  `state_hash` 26-30 us; a snapshot 1.6-1.9 KB.

### Sea battles: the leeward fleet (sea pass 4, as built 2026-10-17)

The owner's tablet report: tacking is fun but too extreme; the downwind
ships keep running aground and never really engage. Measured first
(`tests/sea_probe.gd`, STATUS "Sea pass 4"), then these rules (they
replace the N3a "beyond ~600 m beat up to a point 220 m to windward" and
"probes ahead" above). Points of sail table unchanged (a gentler
close-hauled margin measured no gain).

- **Tacking carries her way**: a ship turning through the wind loses her
  speed slowly (`TACK_WAY`, a 30 s time constant) instead of in about a
  second; head to wind and not turning she still stops fast. A frigate
  tacks in about 30 s and comes out at about 30 % speed (before, every
  frigate or galleon tack ended in irons and a wear).
- **The engagement rule** (`_closing`, any ship sent to engage, beyond her
  range + 220 m): the weather gauge is for the ship that has it (to
  windward of her target: she bears down to her range on its windward
  side) or can fetch the gauge point (220 m to windward of the target) on
  one board. A leeward ship makes for the target's lee bow (her range off
  its lee side, a little ahead of it): on a reach when she can lie it,
  else beating that far, never past the target. The battle AI's leeward
  ship whose target lies to windward beyond its fleet's two boards' reach
  (`BOARD_M` 400 m x 2 close-hauled, for the fleet's worst sailer to
  windward) stops beating and holds its line: hove to, close-hauled
  toward the enemy, broadside to its approach (under sail near a lee
  shore). It holds at most `HOLD_TICKS` (3 min), then beats up after all:
  a player who keeps the gauge and never comes down must not win on the
  clock (ties go to the defender).
- **Sea room** (every ship, any mode): the navigator's probes look down a
  lane her beam wide plus 12 m either side, not a line; a new board is
  the one with `SEA_ROOM_M` 400 m of clear water ahead (the board she is
  on when both or neither have it, else the longer); she tacks `LAYLINE_M`
  200 m short of land or the edge when the other board has more room;
  within `LEE_SHORE_M` 250 m of land to leeward (within 60 deg of dead
  downwind) she never steers in toward it but sails along it, the shore
  abeam, on the side nearer her course and her heading, until clear;
  turning away from land she tries the side she is already turning to
  first (no swinging either side of an island). A ship aground amidships
  works off at a tenth of her speed, without leeway, once her bow points
  at open water within 60 m (before, she could lie there all battle).
- **Deployment**: each fleet's line (no scenario positions) is shifted
  toward the middle and / or along the line, the smallest move first (up
  to 800 m in and 300 m along, the sideways sign by the seed, the fleets
  kept 600 m apart), so that no shoal or land lies within `START_CLEAR_M`
  300 m of a ship and the leeward fleet (200 m or more farther downwind;
  placed first) has `LEE_ROOM_M` 500 m of clear water to leeward and on
  both beams; failing that, the shift with the least land in the way.
  Shoals still within 300 m of a ship are cleared to open water (setup
  rebuilds the grid the same way on every peer; `ter_hash` covers it).
- **Boarding**: the battle AI boards at `BOARD_PCT` 130 % of the target's
  boarding strength (was 160 %); three quarters of its boardings take the
  prize in the probe.
- **Ship book**: the Points of sail page says how a tack carries her way,
  the sea-room rules and the engagement rule; the Engaging paragraph
  points to it (`game/sea_book.gd`).
- **Determinism**: no new state; the rules read the hashed state (tick,
  positions, the wind, `ai_sides`) and the land grid. Cost: see STATUS.

### Sea battles: the flight rule (sea balance, as built 2026-10-21)

The battle AI judges its fleet every 10 s (docs/AI.md 32): below its
skill's share of the enemy's fighting strength (Easy 70, Average 50,
Skilled 40 %) and losing the exchange of the last two minutes, or half
its ships crippled and nearly as weak, the fleet breaks off: every ship
that can still sail runs for the edge by her fastest way out before the
enemy can cut her off (a Skilled fleet with the weather gauge keeps it),
firing at pursuers as she bears; a dismasted ship fights on. Ships off
the edge escape (in the campaign they survive), and the fleet that holds
the sea wins; let go for a minute it rallies and holds, and comes back
only to a fight it is not losing; four minutes out of reach and it has
withdrawn; at the time limit a fleet in flight never wins on the clock.
Measured first, the AI's real losses were its fighting: it now keeps full
sail in the fight (battle sail only close in by land), never loads grape
(a broadside loaded with grape cannot fire beyond its short range;
players still choose it) and boards at 160 % of her strength (sea pass
4's 130 % boarded too eagerly). Against a player who never flees it now
wins 43-47 % of equal fights instead of 31-36 % and loses a fifth fewer
ships.

### Sea battles: Douse (as built 2026-10-22)

A burning ship can douse (the orders row shows Douse only while she
burns): all hands to the buckets, her guns silent (they neither fire nor
reload; a loaded broadside keeps its load) and the fire fought twice as
fast, so a crew thinned to two fifths still wins against a fire that a
full crew only just holds; boarded meanwhile, her men fight at half
strength. It turns off by itself when the fire is out. The battle AI
douses when a fire is outgrowing its crew and nobody is coming to board
her (Easy on any fire; Skilled only with nothing in its arc, unless the
fire nears the magazine). Before, most fires in AI-against-AI battles
ended with the ship lost (47 of 67 in the probe); now about one in five
(12 of 55; docs/AI.md 32.1). The Ship
book's Fire page explains how fires start, the crew's fight, the magazine
and Douse, and warns against lying alongside a burning ship. The fire's
smoke column already scales with its strength, so it thins as she is
doused.

### Sea battles: the look (as built 2026-10-22)

View only (`game/sea_look.gd`, `sea_water.gdshader`, `sea_land.gdshader`,
`sea_shore.gdshaderinc`; nothing in the sim changed). Per battle the sim's
20 m land grid is baked to 10 m fields: the signed distance to the sim's
coast, a depth (the campaign's bathymetry sampled over the battle's cell,
capped by a shelf from the distance to land; custom battles use open-water
depth plus the shelf), the coast's steepness (the relief of the land cells it
faces) and the woods. Water: sandy turquoise shallows to the dark deep, two
wave trains running before the sim's wind (direction eased, strength from
`w_str`) with crests lit from the north-west like the battle kit, whitecaps
in a hard wind, a small sun glitter, breaker lines and a swash band of foam
fading with depth along the shore, and the ships' wakes as foam on the water
(not a line); the diorama's saturation and rim as on the land maps. Land:
the land layer's ground palette, a sand beach band, a cliff bevel and drop
shadow where the coast is steep, sparse kit trees and palms (600, 200 on
Graphics Low) and the harbour forts of the campaign's town (Havana's two)
at the coast. Shoreline: the sim's cell edge is refined for drawing with the
land maps' two-scale shore noise (seeded by the battle seed), always 5 to 14
m INTO the sim's land: the water is drawn over sim land, never land over sim
water, so no ship ever lies over drawn land (`SeaLook.shore_ok`, tested).
Graphics Low: the depth colouring and a still shore wash, no animation, no
time uniform. Tests: `tests/sea_look_test.gd`; frame times in STATUS.

## Rome's navy (plan, 2026-10-23; goal 5)

The Rome pack gets fleets on the Caribbean machinery. Three steps, in order;
the first two can run side by side once the galley rows exist.

**R1, galleys in the sea sim (`sim/sea_types.gd`, `sim/sea_sim.gd`).**
Three oared rows, keyed as the campaign will key them: `lembos` (the light
Illyrian galley: 20 m, fast, a handful of marines, no ram worth the name),
`trireme` (37 m, 200 crew, a bronze ram, 20 marines), `quinquereme` (45 m,
300 crew, the ram, 120 marines; Rome's carry the corvus). No guns: the
exchange before contact is the deck lines' missiles (`DECK_LINE_SHOT`
archers / javelins / slings) at short range, each reload. New row fields:
`ram` (hull damage quality at full dash, 0 none), `corvus` (1: a boarding
bridge), `marines` (built-in deck fighters, added to the unit's troops at
build), `dash` (seconds of ramming speed before the rowers tire). Oars
already exist (`oars` 1, the wind ignored, `drive` 100 on every heading).
Oared pace: the sail-setting order (`O_SAILS`) becomes the stroke for a
rowed ship, 0 rest, 1 cruise (65 % of `vmax`), 2 dash (`vmax`, draining the
dash meter, which refills at cruise at a third of the rate; at an empty
meter she drops to cruise). Ramming, in `_contacts`: when a ram ship's bow
cone (30 degrees either side of her heading) meets another hull closing at
RAM_MIN or more, the struck ship takes `ram` x closing-speed factor hull
damage, doubled on her beam (the strike angle within 45 degrees of
perpendicular to her heading), halved bow to bow (both take it), and the
rammer backs water: speed zero for RAM_BACK seconds, then free; the ram has
a cool-down so a push is not a ram. A ship at hull 0 sinks as now. The
corvus: a `corvus` ship within grapple range of an enemy at any relative
speed drops it and boards at once with `DECK_BONUS_PCT` for her side (the
grapple rule today wants a low relative speed); Rome only. Oared-ship AI:
a ram ship steers for the target's beam at a right angle and dashes for the
last 60 m (the diekplous: when faster than the target, she passes through
and turns for the stern), a corvus ship closes and boards, a lembos keeps
clear of heavier ships and hunts crippled ones, galleys flee straight away
from the enemy rather than downwind, and a tired crew (empty meter) does
not start a ram run. State: the dash meter and the ram cool-down are ints
in the hashed state and in the snapshot. Pins: every existing sea pin is
unchanged (no sail-ship rule moves); new `sea_checks` cases for a ram, a
corvus boarding and a dash; `sea_probe` learns a `--ships=` list so the
galleys can be measured mirrored.

**R2, Rome fleets on the campaign (`campaign/data/rome_ships.gd`, the view).**
`SHIPS` for the Rome pack: the three galleys and a `corbita` (a sailing
merchantman: carry 2, no fight, the transport), costs and upkeep scaled from
the West rows, `yard` levels, `factions` (the corvus quinquereme Rome's; the
Punic and Greek yards build the plain one and better crews via
`SEA_CREWS`), `START_YARDS` at Ostia / Carthage / Syracuse / Pella /
Alexandria, `START_FLEETS` modest (Carthage the largest), Mediterranean
wind constants (a north-westerly, lighter than the trades), no flota, no
pirates, no storms (Illyrian pirates later, as a lane-raid option).
`DECK_CREWS` Rome keys (legionaries / Punic marines / Greek epibatai). The
custom sea setup's ship list per pack, the Ship book's galley page (the
stroke, ramming, the corvus), the rig drawing for oars (banks of oars, one
mast with the sail furled), the sea look's Mediterranean palette (no palms;
the tropic flag is per pack). `CFleet.init` for Rome bumps the Rome pins
(`ROME_20`, the format-8 campaign_sim pins) and `CState.VERSION`; the
West pins stay.

**R3, Rome sea maps.** The coast and island rules are pack-agnostic; R3 is
the look (shore colours, props) and a check of each lane's cells for a
sensible coast mask. Done when a Rome campaign fights a sea battle from a
lane raid with the corvus deciding it.

### Rome's navy R1: galleys in the sea sim (as built 2026-10-23)

Built as planned in `sim/sea_types.gd` and `sim/sea_sim.gd` (header
paragraph "Galleys"), with these differences and fixed numbers. **Rows**:
`lembos` (20 x 4 m, vmax 100, turn 110, hull 120, crew 50, board 100, no
ram, marines 50, dash 45 s), `trireme` (37 x 6, 92, 80, 260, 200, board 100,
ram 100, marines 20, dash 40), `quinquereme` (45 x 7, 84, 60, 420, 300,
board 110, ram 140, corvus 1, marines 120, dash 35, deep draught) and a
second row `quinquereme_p` "Punic quinquereme" (hull 440, board 105, no
corvus, marines 40) so R2 can give the corvus to Rome by row; all reload 8,
no guns, no rigging; the four new fields are 0 on every sail row and the
war canoe (`ST.is_galley`: oars and no guns, so the canoe keeps today's
rules exactly). **Stroke**: as planned (cruise `CRUISE_PCT` 65, the meter
in tenths of a second, refill `DASH_FILL` 3 a second); a galley starts at
cruise. **Speeds** are the sim's (1/1024 m a tick, about 100 = 1 m/s):
`RAM_MIN` 300, `CORVUS_REL` 500. **Ramming** (`_rams`, first in
`_contacts`): the rammer's bow point inside the other hull's box (2 m
margin) with her keel inside the 30 degree bow cone; closing speed = the
rammer's speed less the struck ship's along the rammer's heading; damage
ram x closing / `RAM_DIV` 600, x2 within 45 degrees of her beam; bow to bow
(her heading within 45 degrees of the reverse and the rammer in her bow
cone) one blow, half of the heavier ram's, to both, both back water;
`RAM_BACK` 4 s, `RAM_COOL` 6 s; added: the blow halves the struck ship's
way, and the blows of a tick are found first and struck after (two ships
ramming each other both strike: no edge to the lower index). Only enemies
are rammed. **Corvus**: as planned (any grapple a corvus ship makes is a
corvus boarding, logged as `EV_GRAPPLE` with b 1), firing at will or on her
ordered target; in a corvus melee the deck bonus (`DECK_BONUS_PCT`) is the
boarders' and the defenders lose their home bonus (the plan's "for her
side"); after her boarders are thrown back the bridge is hauled up for
`CORVUS_COOL` 30 s (the AI does not reboard meanwhile; without it a corvus
ship reboarded every second and lost every melee). **Marines** join the
scenario's troops; with no kit given they fight as `ST.DECK_MARINES`
(atk 30, def 30, the javelin line). **Missiles**: a galley's troops (not
the rowers) throw every `reload` seconds at the nearest enemy within
`MSL_M` 60 m, troops x shot % x `DECK_SHOT_PM` / 1000 crew killed, morale
as for grape; events `EV_RAM` 16, `EV_MISSILE` 17. **AI**: a ram ship sets
up `SETUP_M` 120 m off the target's beam (the lead point; her stern
quarter when the galley is faster: the diekplous) and runs in at a right
angle when fresh (meter over a third, the ram ready), dashing the last
`RUN_M` 60 m; a corvus ship with a ram comes in the same way and boards
(the ram stops her alongside, then the bridge drops); a light galley (no
ram, no corvus) passes over ships of more than twice her hull unless
crippled (hull under 40 %) or her side outnumbers theirs two to one, flees
when nothing is left for her, and engages at `MSL_STAND` 40 m, opening
inside 25 m; galleys flee straight away from the nearest enemy. Engage and
board set the stroke for a player's galley too (as the board order already
set the sails). Power and the flight rule count a galley's ram, marines and
boarders in place of guns (`_guns_eq`). **State**: `s_dash`, `s_ram_t`,
`s_msl`, `s_cv_t`, `k_cv` (`GAL_ARRAYS`), in snapshots, hashed only when the
battle has a galley (`gal_on`), so every existing sea hash and pin is
unchanged. **Measured** (`tests/sea_probe.gd --ships0= --ships1= --mirror`,
8 seeds x layouts ns and gauge0, each seed with the fleets both ways, AI
both sides): 4 v 4 triremes decided in 5:39 / 6:28 mean (ns 16-0 to side 0:
the mirrored ns start is one geometry and the first mover wins it; gauge0
8-8); 2 corvus v 3 Punic quinqueremes 14 of 32 to the corvus (6:22 / 5:24);
6 lembos v 2 triremes 6 of 32 to the lembos (6:02 / 8:19); no battle went
to the time limit. Moved from the plan's numbers to get there: lembos
marines 10 -> 50 and board 90 -> 100 (with 10 she never won), the Punic
quinquereme's marines 40 (the plan gave none; at 120 the corvus side won
1 of 32). Not done (R2): the view (rig, oars, the stroke buttons and
help, the Ship book's galley page; the book lists the new rows as text),
the campaign rows.

### Rome's navy R2: Rome fleets on the campaign (as built 2026-10-23)

Built as planned (`campaign/data/rome_ships.gd`, `SHIPS` of `rome.gd`; the view),
with these differences. **Rows**: `lembos` (cost 250, upkeep 15, hull 12, crew 50, speed 370, no
yard, coastal), `trireme` (500 / 30, hull 26, crew 200, speed 340, yard 1, carries 1), `quinquereme`
(900 / 50, hull 42, crew 300, speed 320, yard 2, carries 1, Rome's only), `quinquereme_p` (hull 44,
every faction but Rome), `corbita` (300 / 10, hull 30, crew 30, speed 260, carries 2, any port; a new
sim row `corbita` at the end of `sea_types.gd`: a sail row with no guns, nothing in any hash). Hull is the
sim row / 10 as the West's. A galley has no guns, so her worth in `CFleet.ship_power` is the row's `power`
(110 / 240 / 440 / 420; the corbita has none: hull and crew only). **Start**: yards Rome, Carthage, Macedon
and Syracuse at 2, Epirus, the Greeks (Athens), the Iberians (Saguntum) and the Gauls (Narbo) at 1
in the capital if it has a *harbour* (`CFleet.harbour`, which Athens and Pella have, not only the
regions on a sea lane) else the nearest own harbour; fleets: Carthage 2 Punic quinqueremes and 3
triremes, Rome a corvus quinquereme and 2 triremes (no corbita: a transport at turn 1 made the early
landings), Syracuse (yard 2, the great naval power) 2 triremes and a lembos (a Punic quinquereme too until the
data follow-up of 2026-10-23: it started Syracuse in debt), Macedon
2 triremes, every other faction a trireme and a lembos; Bruttium's start army has one more spear. **Off in this pack** (declared at their off value, the rules read them with
defaults): flota (`FLOTA_PARTS` empty), pirates (`PIRATE_*` 100 %), hurricanes (`STORM_BOX` empty),
captains (`CAPTAIN_NAMES` empty). **Conditional on data, not the pack**: `CData.SHIPS`, `CHAINS` and
`_ship_c` default to Rome's (the static defaults were the West-less ones), `CGrid` keeps the sea lanes
as army links when the ships script says `LANES_FOR_ARMIES` 1 (Rome; the West's islands are crossed on
fleets only), the Realm panel's flota line is shown only with `FLOTA_PARTS`, `CSea.blockader` tolerates a
state of another pack, `CState.as_format(st, v < 6)` strips fleets and Shipyards. **Wind** a
north-westerly 315 degrees, 55, `WIND_PCT` the West's; `SEA_ISLAND_PCT` 20; `SEA_CREWS` Carthage
[112, 100], the Greek cities [110, 105], Macedon / Epirus [100, 100], Rome [92, 105], the hill peoples
[85-88, 112]. `DECK_CREWS` Rome keys (rome legionaries 30 / 29, carthage 27 / 25 with javelins and
slings, macedon / epirus / greeks / syracuse epibatai 28-29 / 30 with shots; the Iberians and Gauls keep
`navy`). **View**: the custom sea battle is offered in every setting (`CS.sea_ships(pack)`,
`sea_default(pack)`: Rome 3 triremes and a quinquereme a side, wind 315 / 55; switching the setting
resets the fleets); `_draw_galley` (banks of oars that sweep with the stroke, a bronze ram, the corvus
bridge, one mast with the sail furled); a galley's sail buttons read Dash / Cruise / Rest, the shot kinds
are hidden for her and Fire at will reads At will / Hold (the corvus); the Ship book has a Galleys page
(stroke and meter, ramming, the corvus, missiles, orders) and the Ships page writes the galley rows and
the merchantman without gun text; the sea look takes `TROPIC` from the pack (0: a deeper blue, a pale
limestone shore, pines and scrub, no palms; the kit has no cypress or olive pieces). **Not done**: the
campaign map draws the galleys with the sprites of the sail ships of about their size (`SHIP_LOOK` in
`minis_layer.gd`: no oared map sprites yet); `CState.VERSION` is not bumped (the state's hash includes
the version, so a bump would have moved the West pins; a Rome save without `fleets` plays as before, a
new one carries them, and the online rules hash separates the builds); Syracuse still falls in 6 of 6
pin seeds (5 before turn 30; turns 11-44; it fell in 5 of 6 at HEAD): its AI sends its armies abroad
and Carthage lands in the empty cities; see the history row. (2026-10-23: the AI's garrisons against landings,
docs/AI.md 12.2: 1 of 6, at turn 27; with the data follow-up, Syracuse's start fleet trimmed and Rome
`SEA_TRADE_PCT` 50, `BLOCKADE_CUT_PCT` 75 as the West: 4 of 6, at turns 16, 33, 47, 56.)

### Rome's navy R3: the Mediterranean maps, galley sprites, lane check (as built 2026-10-24)

View and data only; no sim rule, no hash moved (the Rome pins `7df61f83 8e12363b 07354ffa 3656ce6d a27c02da 2640b4c5`,
`ROME_20`, the West pins and the sea goldens are as before).

**The look.** R2 already took `TROPIC` from the pack (deeper blue water, a pale limestone shore, pines and scrub, no
palms). R3 adds the rest of the plan's props to the non-tropic kit in `SeaLook._props`: rocks (`rock_a`, `rock_b`) among
the scrub, more scrub, and one ruined watch-tower (`tower_round`, at most one a map, inland of the beach) in place of the
palms and the harbour forts. Open water has no props. The Caribbean list and the tropic palette are untouched (Havana's
test and the West looks byte-identical). `tests/sea_look_test.gd` asserts rocks, at most one tower, no palms.

**The lane check** (`tests/sea_lanes_test.gd`, `-- --pack=west` runs the West's). For every sea cell of every lane
(`CLanes.cells_of`, the port cell is land and is skipped) and four seeds with the wind 30 degrees either side of the pack's
north-westerly, the map is built as `cseabattle.build` does (`land_of`, the layout "we" for a coast with a west or north
side, 3 triremes a side) and checked: no ship starts on land or shoal or off the field, the fleets' centres start at least
250 m apart, no map more than 50 % land, and on a coast map there is a line of open water between the two fleets (an
island between them is the map's feature and is only counted: column isleLOS). Result: no lane needed a data change.
One finding: **Gades - Tingis has no sea cell** (the Strait of Gibraltar is land in the grid; the lane is an army link
only, `LANES_FOR_ARMIES`), so it can never be raided or fought on; the test lists it as known (`NO_SEA`). Changing the
grid or dropping the lane would move the Rome pins, so it is left for a map pass. The test also plays the plan's "done
when": a Punic fleet at war raids the Latium - Sardinia lane (`CLanes.raiders`), Rome's corvus quinquereme and a trireme
sail onto it (`fmove` with `tgt`), the pending sea battle builds with `CBattle.build`, the sim fights it AI against AI and
`CTurn.apply_battle` writes it back: 12 campaigns, 12 battles, 30 corvus boardings in the log, Rome won 4 (against two Punic
quinqueremes and a trireme), every Rome win with corvus boardings.

**Oared sprites on the overworld.** The map's ships are atlas sprites (`tools/structures`, Blender, style D), so the
galleys went through that pipeline: `galley_parts` in `gen_spec.py` (a long narrow hull, a bronze ram at the waterline,
banks of oars dipping into the water, one mast with the sail furled on its yard, a raised stern post; the quinquereme
carries a second bank and the corvus on a post by the bow, `quinquereme_p` the same hull without it) gives
`ship_lembos`, `ship_trireme`, `ship_quinquereme`, `ship_quinquereme_p` at the 8 headings in both atlases (big 128 px,
small 64 px; frames rendered with `--structs` of these only into a copy of `_frames`, then `pack.py`: the 1852 older sprite
rectangles compared pixel-identical in the repacked atlases, the atlas grows to 2048 x 1216 / 384). `minis_layer.gd`
`SHIP_LOOK` now only maps the `corbita` to the galleon (open: a merchantman sprite). Faction colour and selection are the
same path as the sail ships (the mask's primary / secondary). Rome's moored ships in a harbour (`TownPlan._moored`) are a
trireme and a lembos instead of the West's brigantine and frigate.

**The ns layout's first-mover edge: not geometry, a sim rule.** `tests/sea_probe.gd --layouts=ns --modes=ai --ships=trireme:4`,
24 seeds: side 0 won 18 of 24; with `--swap` (side 1's ships listed first, same geometry) side 1 won 16 of 24 and side 0 8.
The side whose ships have the lower unit indices wins about two in three whichever end of the map it starts at (the 48-battle
mirrored run: ns 36 / 12 and gauge0 32 / 16 to side 0 with the fleets A and B at 24 / 24). The starting lines are
mirrored (`_layout`, `_place_line`: the same offsets and stagger, facing each other), so there is nothing to fix in the
layout data; the edge is in index-order resolution in the sim (the AI's orders and target picks run in unit order, ties go to
the lower index). Left for a sim pass (it moves every sea hash); open.

## Docking (plan, 2026-10-23)

The owner, 2026-10-23: a fleet should be able to **dock with a city**, not only lie off it; armies keep
boarding and landing from the shore as they do now. Today "in port" means within `PORT_CELLS` (2) of an
own harbour: repairs, storm shelter, boarding from the settlement. Docking makes the port a place a fleet
is *in*, as Rome 2's: sheltered behind the mole, refitted by the yard, lost with the city.

**State.** A fleet lying in port carries `"in": r` (the region; absent otherwise, so old saves and the
West pins read as before: no `CState.VERSION` bump) and sits on `CFleet.dock(r)`. `CFleet.docked(fl)`
is `r` or -1. New fleets (the start fleets of `init`, a ship launched where no fleet of ours lies at the
dock) start docked; a ship launched at a port joins the fleet docked there first, else one beside the
dock as now.

**Orders.** `fdock {fleet, r}`: a station order like `fblockade` (`CSea.station_plan`, kind 3): the
fleet sails to `dock(r)` (a stored voyage, kept till it arrives, carried as `"dk": r` on the fleet) and
docks the turn it gets there; at the dock already, it docks at once. `r` must have a dock and be ours,
an ally's, or (a pirate) a marque patron's; the fleet not `busy`, `sto` or `flota`. `fundock {fleet}`:
casts off (the fleet stays on the dock cell, undocked). Any voyage order (`fmove`, `fraid`,
`fblockade`, a join, a landing anywhere but the city) casts off as it is planned, even for zero steps.
At the end of a turn a docked fleet whose port is no longer ours or friendly (captured by land,
diplomacy) is cast off.

**Docked, a fleet** has no zone and fights nothing: it is left out of `block_mask`, `zone_owner`,
`sea_battle`'s gathering, `execute_moves`' foes and the end-of-turn zone fights (an enemy fleet may lie
on the dock cell: that is a blockade, and the fleet casting off into its zone fights it on the way out,
with `PORT_DEF_PCT` as any defender in its own port). It counts for `CSea._blockade_sides` as now (the
rule's "stronger than its own fleets there" stands for the sortie it would make). Storms skip it
(`cstorm`: `STORM_PORT_PCT` is for fleets lying off the port); no scurvy. **Repair**: docked, `REPAIR` +
`REPAIR_YARD` x the Shipyard level (+ the haven bonus); lying off an own harbour within `PORT_CELLS`
undocked, `REPAIR` alone (the crews put in at the beach; the yard works on ships at its quay). Boarding
is unchanged (`near_fleet`: beside the fleet, or in the settlement whose harbour it lies beside); a
docked fleet's troops may also `land` straight into the settlement cell (`CGrid.site(r)`) whatever its
distance from the dock. Upkeep, sight, trade and the lanes are unchanged.

**The city falls** (`CRules._capture`): the fleets docked there that are not friendly to the captor are
taken as prizes: their ships join (or form) a fleet of the captor's docked at `r` at `TAKEN_PCT` hull and
crew (event `fleet_taken {f, from, r, ships}`), the troops aboard are destroyed (event `destroyed`). A
pack without ships, or a captor whose people build none, still takes them (a prize is a prize). A sack
leaves docked fleets alone (behind the chain).

**AI** (`cai_fleet`): docked is in port for every rule; a free fleet lying at an own dock with no job
docks (an at-once `fdock`), a home voyage (7.) docks on arrival (`dk`), and a fleet given a voyage
casts off by it. No new knob.

**View.** The fleet card reads "In port at Carthage" with **Cast off**; an undocked fleet of ours has
**Dock**: at an own dock it docks there, else tapping one of our (or an ally's) port cities with the
fleet selected orders `fdock` (the voyage drawn to the dock, status "Sailing to dock at ..."), and
tapping the same city again cancels as the station orders do. A docked fleet is drawn at the town
plan's water spot with the sails furled (oars shipped) and no wake ring; the settlement card lists the
fleets in port ("In port: Carthaginian fleet, 5 ships"). The Ship book's campaign page gets a Docking
paragraph. Tests: `campaign_test._docking` (order, arrival, shelter, repair, launches, landing into the
city, the prize, cast off by a voyage and by capture, the storm) and a campaign input case for the
buttons and the city tap.

### Docking (as built, 2026-10-23)

Built as planned; what the build settled or changed:

- **State and API** (`campaign/cfleet.gd`): `"in": r` on the fleet (absent otherwise, no `CState.VERSION` bump), `CFleet.docked(fl)`
  (`r` or -1), `can_dock(st, f, r)` (a dock, and an owner who is `f`, friendly to `f`, or `f`'s marque patron when `f` is a
  pirate), `dock_region(st, f, cell)`, `dock_at`, `docked_in(st, r, f)`, `take_docked` (the prize rule). `"dk": r` rides a
  stored voyage. `fdock` / `fundock` are in `CFleet.apply_order` and `CRules.apply_order`'s dispatch, `CSea.station_plan`
  (kind 3) and the three places of `cturn` that list the station orders (preview, the skip list of the order pass, the fleet
  phase). `fdock` at the dock docks inside `apply_order` (so the planning preview shows it docked at once); from afar it is
  a stored voyage planned with the fleets' moves.
- **Cast off is in `execute_moves`**, not in the orders: any voyage that is planned (a player's `fmove` / `fraid` /
  `fblockade` / `fdock`, a stored one, or any AI move tuple) erases `in` before the fleet sails, even for zero steps; a failed
  plan leaves the fleet docked. A landing anywhere but the city (`_land_order`) casts off. A station order that holds the
  fleet where it lies (`fraid` / `fblockade` at the station) erases `in` in `cturn`.
- **Docked fleets** are left out of `block_mask`, `zone_owner`, `sea_battle`'s gathering (the mover itself excepted),
  `execute_moves`' foe list, the end-of-turn zone fights (as fighter and as foe) and `cstorm.strike`. `plan` refuses a
  chase after a docked enemy fleet ("docked in port"), and the AI's `_prey` skips them. `CSea._blockade_sides` is unchanged.
- **Repair**: docked, `REPAIR` + `REPAIR_YARD` x the Shipyard level of the dock's region (an ally's yard for an ally's
  port) + the pirate haven bonus; undocked within `PORT_CELLS` of an own harbour (or a patron's), `REPAIR` alone; at sea,
  scurvy as before. At the end of a turn a docked fleet whose port is not ours / friendly / a patron's any more is cast
  off before the repair.
- **Launches** join the fleet docked at the dock first, else a fleet within a cell of it as before, else a new fleet that
  starts docked; `init`'s start fleets start docked (story fleets, the flota's galleons and `_new_fleet` itself do not: only
  `init` and the launch dock them). `fmerge` into a docked fleet keeps the berth when the two share the cell.
- **Capture** (`CRules._capture` -> `CFleet.take_docked`): docked fleets of factions not friendly to the captor are prizes
  at `TAKEN_PCT` (names, treasure and the capitana flag kept), joining a fleet of the captor docked there or a new docked
  one; the troops aboard are destroyed (event `destroyed`), the captain meets his fate as for a lost fleet
  (`CCaptain.fleet_lost`, one RNG draw), event `fleet_taken {f, from, r, ships, fleet}` (in `CHRONICLE_KINDS`, the
  chronicle text "took the N ships docked at X"). A docked fleet friendly to the captor stays (cast off if it may not dock
  there any more).
- **AI** (`cai_fleet`, header item 9; docs/AI.md 12.3): a free fleet with no job and nothing aboard lying on a dock it may
  use gets an at-once `fdock` after all other planning; home voyages carry the dock region (sixth tuple element). The
  fleets already moving are not docked that turn.
- **View**: the fleet card ("In port at X", "Docking at X", "Sailing to dock at X", "Casting off"), buttons Dock / Cast off /
  Stay (`act_dock`, `act_cast_off`); `CampaignScreen.start_dock`, `toggle_cast_off`, `dock_order`, `dock_mode` and
  `set_station(id, lane, r, dock)`; with a fleet of ours selected a tap on one of our (or an ally's) port cities orders
  `fdock` when nothing is aboard (before: an error), or after the Dock button for a loaded fleet; the same city again
  cancels. Docked ships are drawn by `MinisLayer` at the quay without wake or bob, with a shadow and a mooring line to the
  town (no furled-sail sprite exists; the cue is the missing wake and the line). The settlement card has an "In port"
  section (our fleets, the enemy's we see) with a button per fleet; the map key has a docked-fleet row. The Ship book has
  no campaign page (it is the sea battle's): the Docking paragraph is on its Ships page.
- **Knobs**: none new. `PORT_CELLS`, `REPAIR`, `REPAIR_YARD`, `TAKEN_PCT` as before.
- **Effect**: the pins moved because the AI docks and the repair rule split (fleets lying off a port get the beach repair only): see docs/STATUS.md for the six hashes per pack and the goldens. The `_chars` hero check (seed 77) raised
  no hero after the move, an emergent change of the sequence; the check uses seed 79 now.
- **Tests**: `campaign_test._docking` (25 checks: start fleets docked, JSON round trip, fdock at the dock, fundock, an
  enemy port refused, the preview of fdock from afar, the stored voyage with `dk` docking on arriving, an enemy fleet
  sailing onto the dock cell fights nothing and the same fleet undocked is fought, the end-of-turn zone fight skipped and
  undocked not, the repair split, a launch joining the docked fleet and a new fleet starting docked, landing into the city,
  `fmove` and a zero-step `fmove` casting off, the prize with its event and the troops destroyed, the prizes joining a docked
  fleet, a port lost without a capture, the storm, the AI docking, determinism) and `campaign_input_test._j_dock` (12
  checks: Dock at sea and the city tap, the same city cancels, Cast off / Stay, Dock at a dock, the settlement card's list).

### Sorties (as built, 2026-10-23)

The fleet AI's answer to a fleet lying off its port (docs/AI.md 12.4; `CAIFleet._sorties`, no rules change): each turn, at
each port where fleets of the AI lie docked, the strongest of them, empty and in repair (`BLOCKADE_HULL`), casts off and
attacks an enemy fleet at war within `BLOCKADE_CELLS` of the harbour (the blockader first) when it has `SORTIE_ODDS_PCT` of
the enemy's power at the spot (the enemy fleets in the battle's zone, times the target's own port guns when it lies in its
own port), and at Skilled one merely passing within `SORTIE_REACH` cells more at `SORTIE_HUNT_PCT`. Knobs Easy / Average /
Skilled: `SORTIE_ODDS_PCT` 0 / 110 / 100, `SORTIE_REACH` 0 / 1 / 2, `SORTIE_HUNT_PCT` 0 / 0 / 130. Next turn the fleet follows
the ordinary rules and docks again when it comes home. Measured (6 x 60, Average): 0.3 sorties a campaign in Rome, 0.8 in the
West; sea battles Rome 10.8 -> 10.0, the West 27.5 unchanged. A fleet lies off a port only when it outguns the port's
fleets (blockade stations need `SAFE_PCT` 130 over the guard, a blockade needs more power than the owner's fleets there), so
a sortie with the odds is rare; the sea battles Docking removed were attacks on the docked fleets, which this rule does not
restore.

### Port rule (2026-10-23)

Owner, phone playtest: "what are the anchor markers? They are on every city now." With `HARBOUR_MAX` 4 (Chebyshev, site to the
nearest coast cell) 29 of Rome's 36 regions and 43 of the West's 49 were ports, inland towns among them (Arretium and
Beneventum at 3; Tayasal, Chickasawhay, Barquisimeto at 4). Now `CFleet.ensure` reads `HARBOUR_MAX` from the pack's ships
script (`CData.ship_const("HARBOUR_MAX", 2)`; default 2, so the West needs no line, `rome_ships.gd` states it) and an
optional Dictionary `HARBOUR_FAR {region key: max distance}` for a real port whose site sits back from the water, read by
key only (`.get(key, HARBOUR_MAX)`, never iterated): Rome's is `{"baetica": 3}` (Gades, Carthage's Atlantic port). A town
plan's own port cell (`CGrid.port`) still wins when it exists. Result: Rome 27 ports (Arretium and Beneventum gone), the West
37 (Tayasal, Chickasawhay, Barquisimeto, Villahermosa, Valladolid, Atakapa Bayou gone); every start yard, start fleet and
lane port of both packs is still a port. Yards, docking, boarding from the settlement, the AI's home ports and blockade
targets follow the rule; sea trade is a share of income at risk under blockade, so no economy change. Pins moved in both
packs (STATUS). A fleet can no longer dock, be built or be boarded at the dropped towns.

### Lanes at war and legible raids (2026-10-23)

Owner, phone playtest: "The raiding looks great on the supply lines, but right now I cannot tell who is raiding what, so there
isn't really a clear distinction on how I can stop the raid. Countries at war should not trade, so their routes should have a
different color for 'At War' state."

Rule: no trade with the enemy. `CLanes.lane_state` pays neither end of a port lane whose two owners are at war
(`CLanes.at_war(st, id)`, false for an exit, an unowned end or one owner holding both); it pays again at peace. Lane exits are
unaffected. A raid on a lane that pays nothing cuts nothing (no `cuta` / `cutb`, no badge, no chronicle row); the AI's
`_lane_gold` already reads `lane_state`, so it never raids a lane that pays nothing (docs/AI.md unchanged). A war now costs
both sides the trade between them: West pacing moved (STATUS pins); Rome has few such lanes.

View (both map styles): a trading lane keeps the pale dashes; a lane at war is redrawn by `MapOverlay._draw_lanes` over them
in a dull dark red-brown (`COL_LANE_WAR`, about twice as wide, the same dash cut so it covers the pale ones; the overlay holds
the state, the cached coast layer does not); a raided lane stays bold red with a badge "raided by <adjective>" in the raider's
colour on a dark plate ("raided" when the raider is out of sight), and the raiding fleet's pennant carries a small red "raider"
tag under its ship count. A tap with nothing selected on a raided lane or its badge says "The <lane> lane is raided by the <adj>
fleet (<n> ships) at <nearest city>: attack it with a stronger fleet, blockade its port, or make peace."; on a lane at war,
"No trade on the <lane> lane: <A> and <B> are at war."; with a fleet selected the raid order tap is as before. Key rows: Sea
lane (a trade route, its gold paid to both ports), Sea lane at war, Raided lane. The Realm panel adds "Stop a raid: attack the
raiding fleet, blockade its home port, or make peace." while a lane paying us is cut. The chronicle row was left as it is
(naming the raider's fleet size would put it in the event, hence in the hashed state).

### Launches per turn and boarding on arrival (as built, 2026-10-26)

Owner, phone playtest of the Miskito: a port could order one ship a turn, too little for war canoes (tiny, one unit each, a war
party needs one per unit), and getting an army beside a fleet took turns of guessing.

Launches: a ship row may carry `"launch"` (ships of this kind one port launches in a turn, default 1); the war canoe has 4.
`regions[r]["sq"]` is now a list that grows: `CFleet.ship_check` refuses an order when the queue already holds as many ships as
the smallest `launch` among the queued keys and the key ordered, with "launching a ship already" (limit 1: a sloop behind canoes
or a canoe behind a sloop) or "the yard launches N of these a turn". So a queue is one ship of any kind, or up to `launch` of a
multi-launch kind. `end_of_turn` already launched every queued key. The AI's `_build` repeats its one ship order for a
multi-launch kind when it wants transport, while the check passes, the cost fits what is left of its budget and fewer than
`launch` were ordered.

Boarding: `CFleet.boarding_cells(st, fl)` (the passable cells beside the fleet plus the site of every region whose harbour is
beside it) and `CFleet.pickup_cells(st, a)` (the open-sea cells beside the army, or beside the harbour of the settlement it
holds) are pure helpers for the view; both agree with `near_fleet` (tested). The version 6 move order takes an optional
`"fleet"` (id of the faction's own fleet; the view sends x, y of a boarding cell and persist 1): refused up front when the fleet
is not ours, the army is in a battle or a siege, or the fleet could never carry it ("not enough room aboard"). The march rows
carry the fleet as an eighth element and a stored march keeps it as the army's `dest_fleet`. Right after the players' moves
`CFleet.board_on_arrival` (in index order) boards every army with `dest_fleet` that passes `embark_check` (event `embarked`);
one whose march has ended without that forgets the plan (event `board_missed {f, army, fleet}`); the rest march on. A fleet
that sails away meanwhile is not chased: the army walks to the old cell and reports the miss. Optional keys only, no
`CState.VERSION` change. Tests: `campaign_test` `_launches`, `_board_march`.

(2026-10-30) A fleet waits for an army marching to board it. The owner: loading the army took one turn more than it allowed, so the ship sailed to Tortuga empty (the fleets sail first, the armies march after, and `board_on_arrival` came last). Rule: in `cturn.resolve_turn`, `_defer_boarding_fleets` drops from the fleets' moves every fleet that is the `dest_fleet` of an army of the same faction marching this turn (a `move` with `fleet` among the submissions, or a stored march with `dest_fleet`); the voyage is written to the fleet as a stored one (`dest_x`, `dest_y`, `tgt`, `dk`; one already stored to the same cell is kept), so the fleet sails the turn after the army went aboard, with it. Event `fleet_waits {f, fleet, army}` (chronicle: "A fleet of ours waits for an army marching to board it, then sails."). The fleet panel says "Waits this turn for the army to board, then sails." in front of the planned voyage. A direct `embark` order is applied before the moves and is unchanged. The AI never uses `dest_fleet` (it boards with `embark` beside the fleet, `cai.gd`), so its fleets are untouched. No new state field, no `CState.VERSION` bump; the rules hash moves (online players reload between turns). Tests: `campaign_test` "boarding wait".

### Native vessels (as built, 2026-11-01)

The natives' heavier dugouts (campaign side, the ally condition and the measure: `docs/design/campaign_rules.md` "Native
vessels (as built, 2026-11-01)"). Sea sim rows, appended to `sim/sea_types.gd` ROWS after the corbita (index 12-14), so every
older row keeps its `s_type` and every older battle hashes as before:

| Row | len / beam | vmax | turn | guns x gun, range | hull | crew | board | other |
|---|---|---|---|---|---|---|---|---|
| piragua | 18 / 3 | 100 | 110 | 1 x 3, 120 m | 180 | 60 | 160 | rowed, rig 1, reload 8 |
| great_canoe | 24 / 3 | 92 | 100 | none | 260 | 80 | 150 | rowed |
| fire_canoe | 13 / 3 | 95 | 70 | none | 60 | 10 | 60 | rowed, `fire` 1, reload 10 |

All three, and the war canoe, carry `"canoe": 1`: `ST.is_galley` (oars and no guns) excludes them, so the great canoe and the
fire canoe are not Rome's war galleys (no stroke meter, no galley AI or orders bar, no galley drawing): they paddle as the war
canoe does. The fire canoe is a fire ship by her flag (`ST.is_fire`): an O_TARGET / O_BOARD sends her at the mark (M_FIRE),
a rowed fire ship is lit inside `FS_LIGHT_OARS_M` (80 m, where a sailing one lights at `FS_LIGHT_M` 200) and her paddlers
leave her inside `FS_ABANDON_OARS_M` (25 m; `FS_ABANDON_M` 80 for sail): abandoned, a rowed hull slows to 30 % (the crew term
of a rowed ship's pace) and cannot outrun a ship under sail for long. With the sailing distances she was lit too far off and
drifted: over 16 seeds of the "canoes" battle 2 enemy contacts and 2 on her own side; with the rowed distances 5 and 0 (the
European fire ship's numbers do not move; only a row with both `fire` and `oars`). Measured against a sloop hove to 400 m
off: lit at tick 356, alongside at 423. The deck melee's mast cells (`_masts`) and the view's rig read the row's optional `"masts"`
(`ST.masts`: the sloop 1, the brigantine and the fire ship 2, default 3, rowed 0) where they compared the keys "sloop",
"brigantine" and "fire_ship": the compare meant the rig, not a class of hull. The view draws the dugouts as the war canoe
(paddles along both sides, by `len` and `beam`); the overworld miniature is the war canoe's (`MinisLayer.SHIP_LOOK`), the
great canoe 1.35 times larger (`SHIP_SCALE`); `SHIP_RANK` puts the great canoe after the sloop, then the piragua, the war
canoe, the fire canoe. The custom battle's West ship list gains the three. Test: `tests/sea_checks.gd` `canoes()` (in the
sea determinism run): the rows, a fire canoe lit and alongside a sloop, a piragua grappling a sloop, the "canoes" battle
(two piraguas, a great canoe and a fire canoe against a sloop and a brigantine, both sides AI) twice identical with
snapshots restored at 300 and 1200, over 8 seeds the fire canoe lit and the canoes boarding; at equal gold the dugouts board
more than once a battle. The test scenarios set the boarding quality as the campaign does (`cseabattle`: the row's `board` x
the crews' boarding %, `SeaChecks._cu`); the first build's scenario gave every ship a flat 115, which undervalued the dugouts.

**The dugouts close and board (2026-11-01, the sea AI).** The battle AI's think for a ship with `canoe`:
- *Target:* the enemy ship with the fewest defenders (distance + 6 x her boarding strength), not the weakest hull.
- *Board:* when her boarding strength is `CANOE_BOARD_PCT` (100) % of the target's with the defenders' deck bonus (the others
  need `BOARD_PCT` 160), at any range (rowed, as before); otherwise she engages as before.
- *Strength:* `_guns_eq` (the fleet's power for the flight rule and the call on the clock) counts a dugout as a galley (her
  boarders), so a canoe fleet is not "outgunned" by one brigantine and does not flee.
A "swarm" count (every free dugout of the side added to her strength) was tried and dropped: a grapple is one ship to one ship
in this sim, so the swarm sent canoes alone against a brigantine.

Equal gold, `SeaChecks` "canoes_eq": two Itza piraguas and a great canoe (940 gold; gunnery 80, the Itza crews' boarding 115 %)
against a Spanish sloop, brigantine and war canoe (920; gunnery 95, boarding 115 %), layout gauge0, both sides AI, canoe wins:

| Step | 8 seeds | 16 seeds | boardings (8) |
|---|---|---|---|
| The first build's AI | 0 | 0 | 6 |
| + the swarm count | 0 | 1 | 20 |
| + the target by defenders | 1 | 3 | 22 |
| the swarm dropped, boarding at 100 % (as built) | 1 | 3 | 33 |
| + piragua board 160 -> 180 | 1 | 3 | 30 |
| + piragua board 200 | 1 | 3 | 31 |
| + piragua hull 180 -> 200 | 1 | 3 | 32 |
| + piragua hull 220 | 1 | 3 | 27 |
| + great canoe board 150 -> 170 | 1 | 2 | 24 |
| + great canoe board 190 | 1 | 2 | 16 |
| (a reading, not kept: a dugout sends 95 % of her crew across, not `DECK_BOARD_PCT` 75) | 2 | 3 | 22 |

No step reaches the 40-50 % band, so the rows keep their numbers (piragua board 160, hull 180; great canoe board 150) and only
the AI change is kept. Why the stats do not move it: the boarding quality is clamped at 200 in the sim (`s_bq`; a piragua's 160
x 115 % is already 184), hull does not enter a deck melee, and a melee is one ship against one: a piragua sends 45 of her 60 men
across against a sloop's 60 fighting at 125 % on their own deck, and the brigantine's 90. The canoes take the war canoe and
often the sloop, then lose their boarders to the brigantine. The levers left are outside the brief: more than one boarder on a
ship, the 200 clamp, a dugout's share across, or crews.

### Joint boarding by dugouts (as built, 2026-11-01)

The owner's levers for the equal-gold canoe fight (the previous section's open item): two or more dugouts boarding one ship
together, and a larger share of a dugout's crew sent across. Code: `sim/sea_sim.gd` `_join_of`, `_join`, `_join_settle`,
`_charge_men`, `_deck_pct`; the gates in `_contacts` and `_steer` (M_BOARD); `_ungrapple`, `_deck_close`, `_hold_alongside`.

- **Who joins.** A dugout (a row with `canoe`) whose board target is already grappled by a boarder of her own side (dugout or
  not), that boarder's deck melee on (`k_on`), grapples her too when she comes within the grapple reach at the same relative
  speed gate as a first grapple. She is a *joiner* of that melee (`s_join` = the first boarder, hashed in `SHIP_ARRAYS`,
  carried by snapshots): `s_grap` the target, `s_boarder` 1, no melee of her own (`k_on` 0); `EV_GRAPPLE` with `d` 1 ("joins
  the boarding" in the view's log), `stats["boardings"]` and `stats["joins"]` + 1. A player's O_BOARD at such a ship joins the
  same way. A non-dugout never joins (it still cannot grapple a grappled ship). The target and the melee stay the first
  boarder's: one melee per first boarder, the prize is hers.
- **Her men.** `crew x CANOE_DECK_PCT / 100 + troops` enter side 0 of the first boarder's melee: new figures at the free cells
  of the first boarder's deck (rail back, amidships out) while side 0 has free figure slots (`DECK_FIG`), her soldiers with her
  first troop kit, her crew with her own kit and boarding quality (`s_ck_*` x `s_bq`; no captain of her own); with no free cell
  or slot her men are spread over side 0's figures in index order (the remainder to the first). Side 0's morale becomes the
  men-weighted mean of its morale and hers + `DECK_RUSH`; `k2_men0` grows by her men. She lies on the target's other side from
  the first boarder; a second joiner on the first boarder's side a third of the target's length forward, and so on.
- **Losses.** From the first join side 0's losses are pooled (`k_jl`) instead of being taken off the first boarder at once; when
  the melee ends in any way (taken, thrown back, both spent, the first boarder sinking, striking, burning, the battle's end)
  `_join_settle` charges them to the first boarder and each joiner by the men each had in it (the first boarder: her men on
  deck at the first join, `s_jw`), integer shares, the remainder to the first boarder, troops first then crew, and casts the
  joiners off (`s_grap`, `s_boarder`, `s_join` cleared, M_FREE). Losses before the first join were already the first
  boarder's. A joiner that sinks or burns mid-melee is dropped (`k_dw` keeps her men's weight): her men already across fight
  on and her share of the losses is charged to nobody.
- **The dugout share.** `CANOE_DECK_PCT` 95: a dugout's boarding party (first boarder or joiner) is 95 % of her crew (no sails
  to work; `DECK_BOARD_PCT` 75 for every other ship). The AI's strength estimate (`my_b`) counts the whole crew and is
  unchanged; the boarding quality clamp at 200 is unchanged.
- **The pack's target.** A dugout of the battle AI scores each enemy ship by her broadside weight (`guns` x `gun`: the
  brigantine 35, the sloop 16, the war canoe 3) and admits her when the side's free dugout pack (every dugout of the side
  sailing, not grappled, not a fire row or lit, plus its dugouts already grappled to her) has a boarding strength of
  `CANOE_PACK_PCT` (100) % of her defenders with the deck bonus; among the admitted ships the heaviest broadside, ties by
  distance; none admitted: the fewest defenders, as before. So every dugout of a side converges on the same gunned ship and
  the later ones join the first's melee.
- **Limits.** With the scenario's `"deck"` 1 (the outside melee, O_DECK) nobody joins: a dugout waits as before. A joiner
  cannot herself be boarded or joined (she is grappled). No morale hit for a joiner when the melee is thrown back (the first
  boarder's `_repelled` only).

Measured (`SeaChecks`, 8 seeds, both sides AI, canoe wins; `docs/AI.md` 53):

| Step | canoes_eq | canoes |
|---|---|---|
| Before (the fewest-defenders target, one boarder a ship, 75 % across) | 1 | 5 |
| Joining alone (share 75) | 1 | 8 |
| Joining + `CANOE_DECK_PCT` 95 | 2 | 8 |
| ... `CANOE_BOARD_PCT` 60 / 80 / 130 | 2 / 2 / 1 | 8 |
| + the pack's target (as built) | 3 | 5 |

Test: `SeaChecks._joint_boarding` (in `canoes()`).

### Native vessels carry more (2026-11-02)

The owner, as the Miskito: "Requiring a full stack of 12 for the canoes to move a stack of 12 seems unreasonable. The Miskito
not being able to jump to the southern island without 36 canoes if I have 3 armies doesn't work." Every native hull carried one
unit and a port launches a few ships a turn, so a 12-unit army needed 12 canoes. Data only (`campaign/data/west_ships.gd`
`cap`): war canoe 1 -> 3, piragua 1 -> 4, great canoe 2 -> 6 (a 12-unit army boards four war canoes, three piraguas or two
great canoes); the fire canoe 0, the sloop 1, frigate 3, galleon 6, ship of the line 4 unchanged; price, upkeep, build time and
launches a turn unchanged. Nothing else read the old numbers: boarding (`CFleet.embark_check`, `csea.gd`), the fleet card
("men 3/12"), the Board chip ("n of m places taken") and the ship rows' "carries n" all read `CFleet.capacity`. Units aboard a
sunk or taken ship: the existing rule (`CFleet._sink_extra`): when the fleet's remaining ships carry fewer places than the units
aboard, the last-boarded armies are lost whole (event `army_sunk`), so a loaded canoe lost in a fight takes its army with it
(the pre-battle share of the men is the same either way).

In a sea battle the carried men fight: `CSeaBattle.build` gives each hull a share of the men aboard by its places (`troops`),
and the troops defend the deck and join a boarding (`sea_sim.gd` `s_troops`; sea.md "Joint boarding by dugouts"). A piragua
with four units aboard carries about 400 men on top of her 60 crew; before, the same four units needed four hulls. Probe
(`canoe_probe.gd` in the session scratchpad, piragua + 2 war canoes vs a TF frigate with no troops, 24 seeds;
natives' deck troops 0 / 100 each / 400 + 300 + 300): AI-ordered natives win 0 / 0 / 10 of 24, ordered to board 0 / 13 / 20 of
24 (median 90 s / 132 s / 108 s). A full-loaded trio is a real threat to a lone frigate, which is the point of a troop
transport; an escort frigate with troops of its own (the AI's) is not in the probe.
