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
war canoes (Miskito, Itza: coastal water only, fast, carry 1). A fleet is
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
