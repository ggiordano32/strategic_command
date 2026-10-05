# Campaign (milestone 3) — as built

Design agreed with the user on 2026-10-05; built 2026-10-05. This file is the
campaign's design intent plus the rules and numbers as they are in the code.
`docs/DESIGN.md` section 2 has the original outline. Code: rules in
`campaign/` (pure data, no Nodes), screens in `game/campaign/`.

## Intent (unchanged)

The western and central Mediterranean from 280 BC. Two friends, permanently
allied, each pick any faction and play an asynchronous campaign in 15-minute
sessions (40-60 turns, two turns a year); solo works too. Simultaneous
planning, deterministic resolution, battles never block silently, auto-resolve
a little worse than good play. No fleets, generals, politics or agents.

## Architecture

- `campaign/cdata.gd` static tables (regions, routes, sea lanes, factions,
  rosters, buildings, economy numbers). `campaign/cstate.gd` the state: new
  campaign, JSON, hash, RNG, queries. `campaign/crules.gd` orders, moves,
  battles bookkeeping, outcome, economy, end conditions. `campaign/cbattle.gd`
  campaign battle <-> battle sim, and the formula for AI-only battles.
  `campaign/cai.gd` AI factions and diplomacy. `campaign/cturn.gd` the turn
  pipeline (resolve_turn, apply_battle, preview).
- **Determinism:** integers only; the state's own xorshift RNG (`rng`);
  arrays iterated in index order; dictionaries only looked up by key, never
  iterated by the rules (JSON load does not keep key order); no Node, no
  engine time. `resolve_turn(state, submissions)` and
  `apply_battle(state, battle, outcome)` are pure functions of their inputs
  (they deep-copy the state). Tested: same inputs give the same hash, also
  across a save/load in the middle (`tests/campaign_test.gd`).
- **State** is one JSON-serialisable Dictionary (string keys; ints, strings,
  arrays, dictionaries; no floats or bools). `CState.to_json` writes it with
  sorted keys; `from_json` turns JSON's floats back into ints (`normalise`).
  `state_hash` = first 32 bits of the MD5 of that canonical JSON.

### State format (version 1)

```
format "strategic_command_campaign", version 1, name, seed, turn (0 = 280 BC
summer), phase "plan" | "battles" | "over", rng, winner (-1, 1 won, 0 lost),
settings {victory_regions 20, victory_capitals 3, turn_timeout_h 0|12|24|48|72
  (stored, not enforced), autoresolve "ask"|"auto", ai_aggression 70|100|130},
humans [faction...]   (sorted; permanently allied: dip ALLIED)
factions [{alive, treasury, next_army, income, upkeep, war_turns}]  (CData order)
dip [8*8] 0 war / 1 peace / 2 trade / 3 allied;  dip_turn [8*8] turn of change
regions [{owner (-1 independent), level 0 village|1 town|2 city, growth,
  slots [[chain, level]...], build [chain, level, turns_left] | [],
  queue [unit keys recruited this turn], gar (garrison strength %)}]
armies [{id, f, r, units [{t: unit key, n: men}], from, moved, busy}] by id;
  id = faction * 100000 + factions[f].next_army
battles [{id, r, turn, att [army ids], def [army ids], att_f, def_f, reinf
  [army ids], settlement 1}], next_battle
proposals [{id, from (AI), to (player), what, turn}], next_proposal
events [{turn, k, ...}] (the last two turns: battle, captured, retreat,
  destroyed, war, peace, trade, trade_end, refused, proposal, built,
  recruited, grew, debt, eliminated, order_failed, move_failed, victory, defeat)
stats {battles, battles_formula, battles_auto, battles_fought, last_war_on_players}
```

Unit types are stored by key (`"principes"`), regions and factions by index
into the `cdata.gd` tables; changing those indices needs a version bump.

### Orders and submissions (what milestone 4 sends)

A submission is what one player sends for one turn:
`{"turn": t, "f": faction, "base": hash planned on, "orders": [...]}` with
orders (plain data):

| order | fields | when applied |
|---|---|---|
| move | army, to | step 3, all players' moves by army id |
| recruit | r, unit (type key) | step 2; paid now, arrives at end of turn |
| build | r, chain | step 2; paid now, done after the chain's turns |
| merge | army, into | step 2 (same region, at most 12 units) |
| split | army, units [indices], new (the faction's next army id) | step 2 |
| disband | army, units [indices] | step 2 |
| propose | to, what peace / trade / cancel_trade | step 4, AI answers |
| war | to | step 1 |
| answer | id (AI proposal), accept 0/1 | step 1 |

Invalid orders are skipped and logged (`order_failed` / `move_failed`), never
fatal. The client previews its plan with `CTurn.preview` (the same rule code
on a copy) and drops orders that became invalid.

A battle result is the other input: `{winner 0 attackers / 1 defenders,
mode, units [{army (-1 garrison), unit, killed, routed, withdrawn,
remaining}], garrison_pct}`, built from `BattleSim.result()` by
`CBattle.outcome_from_result` (or `outcome_forfeit`, or `formula`).

### Turn pipeline (`cturn.gd` resolve_turn)

1. Players' war declarations and answers to AI proposals.
2. Players' other orders, faction by faction, in the order given.
3. Players' moves, by army id. Entering a region of a faction at war (or an
   independent) starts a battle there (or joins it).
4. Players' proposals; the AI answers at once.
5. AI factions act in faction order (merge, cut debt, build, recruit, move).
6. Neighbouring armies reinforce the new battles.
7. Battles without a player: resolved now by the formula. Battles with a
   player: pending (phase "battles").
8. AI diplomacy; end of turn (constructions, recruits, money, debt,
   replenishment, garrisons, growth); eliminations; victory; turn + 1.

Pending battles must be resolved (`apply_battle`) before the next turn can be
planned; `resolve_turn` refuses while any is pending. A faction that submits
nothing holds (the turn timeout will use this).

## Map

36 regions, 45 land routes, 14 sea lanes. Crossing a sea lane takes the
turn like a land move; no fleets. Settlements at real coordinates.

| Region (settlement) | Terrain | Wealth | Start | Land routes | Sea lanes |
|---|---|---|---|---|---|
| Latium (Roma) | rolling | 6 | city, walls 1 | Etruria, Campania, Samnium | Sardinia |
| Etruria (Arretium) | hill | 4 | town | Latium, Cisalpina | Corsica |
| Campania (Capua) | flat | 6 | town | Latium, Samnium, Bruttium | |
| Samnium (Beneventum) | ridge | 3 | village | Latium, Campania, Apulia | |
| Apulia (Tarentum) | flat | 5 | city, walls 1 | Samnium, Bruttium | Epirus, Illyria |
| Bruttium (Rhegium) | hill | 3 | village | Campania, Apulia | Sicilia Or. |
| Gallia Cisalpina (Mediolanum) | flat | 4 | village | Etruria, Venetia, Allobroges, Massalia | |
| Venetia (Patavium) | flat | 3 | village | Cisalpina, Illyria | |
| Sicilia Occ. (Lilybaeum) | hill | 4 | town, walls 1 | Sicilia Or. | Zeugitana |
| Sicilia Or. (Syracusae) | rolling | 6 | city, walls 2 | Sicilia Occ. | Bruttium, Achaea |
| Sardinia (Caralis) | hill | 3 | village | | Zeugitana, Corsica, Latium |
| Corsica (Aleria) | ridge | 2 | village | | Sardinia, Etruria, Massalia |
| Baetica (Gades) | rolling | 5 | town | Contestania, Carpetania, Lusitania | Mauretania |
| Contestania (Mastia) | hill | 4 | village | Baetica, Edetania, Carpetania | Numidia |
| Edetania (Saguntum) | rolling | 4 | town | Contestania, Ilergetia, Celtiberia | |
| Ilergetia (Emporion) | rolling | 3 | village | Edetania, Celtiberia, Volcae | Massalia |
| Celtiberia (Numantia) | ridge | 3 | town, walls 1 | Edetania, Ilergetia, Carpetania, Gallaecia | |
| Carpetania (Toletum) | flat | 3 | village | Baetica, Contestania, Celtiberia, Lusitania | |
| Lusitania (Olisipo) | rolling | 3 | village | Baetica, Carpetania, Gallaecia | |
| Gallaecia (Brigantium) | hill | 2 | village | Lusitania, Celtiberia | |
| Massalia (Massalia) | hill | 5 | city, walls 1 | Cisalpina, Volcae, Allobroges | Corsica, Ilergetia |
| Volcae (Narbo) | flat | 3 | village | Ilergetia, Massalia, Arverni | |
| Arverni (Gergovia) | ridge | 4 | town, walls 1 | Volcae, Allobroges | |
| Allobroges (Vienna) | valley | 3 | village | Cisalpina, Massalia, Arverni | |
| Macedonia (Pella) | rolling | 5 | city, walls 1 | Thessalia, Illyria, Epirus | |
| Thessalia (Larissa) | flat | 4 | town | Macedonia, Epirus, Aetolia, Attica | |
| Epirus (Ambracia) | ridge | 3 | town, walls 1 | Macedonia, Thessalia, Illyria, Aetolia | Apulia |
| Illyria (Scodra) | hill | 3 | village | Venetia, Macedonia, Epirus | Apulia |
| Aetolia (Thermon) | ridge | 3 | village | Thessalia, Epirus, Attica | Achaea |
| Attica (Athenae) | rolling | 6 | city, walls 2 | Thessalia, Aetolia, Achaea | |
| Achaea (Corinthus) | hill | 5 | town, walls 1 | Attica, Laconia | Aetolia, Sicilia Or. |
| Laconia (Sparta) | valley | 3 | town | Achaea | |
| Zeugitana (Carthago) | flat | 7 | city, walls 2 | Byzacena, Numidia | Sicilia Occ., Sardinia |
| Byzacena (Hadrumetum) | flat | 4 | town | Zeugitana, Numidia | |
| Numidia (Cirta) | rolling | 3 | village | Zeugitana, Byzacena, Mauretania | Contestania |
| Mauretania (Tingis) | hill | 2 | village | Numidia | Baetica |

The map screen draws hand-authored low-polygon coastlines (Europe as one
polygon closed by the map edges, North Africa, Sicily, Sardinia, Corsica;
Balearics, Crete, Euboea, Ionian islands, Elba, Malta as decoration),
projected equirectangularly (lon x 76.6, lat x 100 px per degree). A region's
territory is the Voronoi cell of its settlement among the settlements of the
same landmass, clipped to the land; 19 unclaimed "phantom" sites (Dalmatia,
Pannonia, Thrace, Aquitania, the Alps, the Saharan interior...) keep cells
from spilling over the Adriatic or across the desert.

## Factions and start

| Faction | Regions | Treasury | Armies |
|---|---|---|---|
| Rome | Latium (capital), Etruria, Campania, Samnium | 1,500 | 7 + 5 units |
| Carthage | Zeugitana (capital), Byzacena, Sicilia Occ., Sardinia, Baetica | 2,200 | 8 + 5 + 5 |
| Macedon | Macedonia (capital), Thessalia | 1,600 | 8 |
| Epirus | Epirus (capital), Apulia | 1,800 | 10 (in Tarentum) + 4 |
| Greek League | Attica (capital), Achaea, Aetolia | 1,600 | 5 + 4 |
| Syracuse | Sicilia Or. (capital), Bruttium | 2,200 | 10 + 3 |
| Iberian Tribes | Celtiberia (capital), Edetania, Carpetania | 1,200 | 7 + 4 |
| Gallic Tribes | Arverni (capital), Cisalpina, Volcae | 1,200 | 7 + 5 |

The other 12 regions are independent: they never move; their garrisons are
two units larger than a faction's and nearly full-size units. Starting wars:
Rome-Epirus, Carthage-Syracuse; everyone else at peace without trade.
Starting buildings: capitals farm, barracks, range, stables (and market in a
city); other cities farm, market, barracks; towns farm, barracks; villages a
farm; walls as in the table.

## Unit tiers

Tier 1 is each base type (the sandbox's nine types, unchanged). Tiers 2 and 3
are derived rows appended to `sim/unit_types.gd` (indices 9-39): base stats
plus attack/defence +5/+10 (pikes half), armour +3/+6, hp +6/+12, morale
+70/+140 (max 1000), damage +2/+4, missile damage +3/+6 for missile lines,
charge +5/+10 for cavalry, and a row's own touches. Price per line set so a
higher tier is roughly even with tier 1 at equal price. Upkeep is 15% of the
price per turn. Symbols carry one (tier 2) or two (tier 3) gold chevrons.

| Unit | Line | Tier | Price | Att/Def/Arm/HP | Morale | Upkeep |
|---|---|---|---|---|---|---|
| Heavy Swords | heavy | 1 | 600 | 40/35/14/100 | 900 | 90 |
| Veteran Swordsmen, Principes (Rome), Scutarii (Iberia) | heavy | 2 | 810 | 45/40/17/106 | 970 | 121 |
| Guard Swordsmen, Extraordinarii (Rome), Gallic Nobles | heavy | 3 | 1140 | 50/45/20/112 | 1000 | 171 |
| Light Infantry | light | 1 | 400 | 36/26/4/85 | 600 | 60 |
| Veteran Light Infantry, Caetrati (+2 att), Gallic Warband (+4 dmg, -2 def) | light | 2 | 560 | 41/31/7/91 | 670 | 84 |
| Elite Light Infantry | light | 3 | 720 | 46/36/10/97 | 740 | 108 |
| Spearmen | spear | 1 | 500 | 15/30/9/90 | 780 | 75 |
| Veteran Spearmen, Hoplites (+5 missile shield) | spear | 2 | 765 | 20/35/12/96 | 850 | 114 |
| Guard Spearmen, Picked Hoplites, Triarii (+2 def, morale 980) | spear | 3 | 1310 | 25/40/15/102 | 920 | 196 |
| Sacred Band (Carthage: +2 armour, morale 980) | spear | 3 | 1385 | 25/40/17/102 | 980 | 207 |
| Pikemen | pike | 1 | 600 | 34/40/8/90 | 820 | 90 |
| Veteran Pikemen, Phalangites (Macedon) | pike | 2 | 966 | 36/42/11/96 | 890 | 144 |
| Guard Pikemen, Silver Shields (+2 armour, morale 1000), Chaonian Guard (+2 att) | pike | 3 | 1650 | 39/45/14/102 | 960 | 247 |
| Archers | archer | 1 | 400 | 18/16/3/75 | 640 | 60 |
| Veteran Archers | archer | 2 | 488 | 23/21/6/81 | 710 | 73 |
| Elite Archers, Cretan Archers (+2 more missile damage) | archer | 3 | 512 | 28/26/9/87 | 780 | 76 |
| Javelinmen | javelin | 1 | 240 | 28/22/3/80 | 500 | 36 |
| Veteran / Elite Javelinmen | javelin | 2 / 3 | 288 / 384 | 33/27/6/86, 38/32/9/92 | 570 / 640 | 43 / 57 |
| Shock Cavalry | cav | 1 | 600 | 36/28/10/150 | 760 | 90 |
| Veteran Cavalry | cav | 2 | 882 | 41/33/13/156 | 830 | 132 |
| Guard Cavalry, Companions (+6 charge), Agema (+2 def), Noble Cavalry | cav | 3 | 1260 | 46/38/16/162 | 900 | 189 |
| Bolt / Stone Throwers | bolt / stone | 1 | 400 / 540 | | | 60 / 81 |

Rosters (line: tier 1 / 2 / 3, "-" missing): Rome heavy Heavy / Principes /
Extraordinarii, light 1-2, spear Spear / Veteran / Triarii, javelin 1-3, cav
1-2, bolt, stone. Carthage heavy 1-2, light 1-3, spear Spear / Veteran /
Sacred Band, archer 1-2, javelin 1-3, cav 1-3, bolt, stone. Macedon pike Pike /
Phalangites / Silver Shields, light 1-2, archer 1-3, javelin 1-2, cav Cav /
Veteran / Companions, bolt, stone. Epirus pike Pike / Veteran / Chaonian
Guard, spear 1-2, light 1-2, archer 1-2, javelin 1-2, cav Cav / Veteran /
Agema, bolt. Greek League and Syracuse spear Spear / Hoplites / Picked
Hoplites, archer Archer / Veteran / Cretans, plus pikes 1-2 (Greeks) or heavy
1-2 (Syracuse), light, javelins, cav 1-2, engines. Iberians light Light /
Caetrati / Elite, heavy Heavy / Scutarii / Guard, javelin 1-3, spear 1-2, cav
1-2. Gauls light Light / Warband / Elite, heavy Heavy / Veteran / Gallic
Nobles, spear 1-2, javelin 1-2, archer 1, cav Cav / Veteran / Noble Cavalry.
Independents: spear, archer, heavy, light 1-3 (garrisons only).

Tier balance (`tests/matchups.gd -- --only=tiers --seeds=12`, both units
advancing into each other; equal price = the tier-1 side gets proportionally
more men in one wider unit):

| Line | T3 v T1 equal numbers | T3 v T1 equal price | T2 v T1 equal numbers | T2 v T1 equal price |
|---|---|---|---|---|
| heavy | 100% (killed 15 v 85) | 25% | 100% | 41% |
| light | 100% | 50% | 100% | 50% |
| spear | 100% | 75% | 100% | 33% |
| pike | 100% | 0-100% (cliff, see below) | 100% | 16-81% |
| archer | 100% | 66% | 100% | 33% |
| javelin | 100% | 33% | 100% | 50% |
| cav | 100% | 58% | 100% | 66% |

The pike duel at equal price flips from 100% to 0% between 2.5 and 3.1 times
the price (one 300-man pike block either envelops the elite block or is held
on its points); 2.75 is the midpoint. A wider, single-unit "equal price"
test exaggerates numbers; in an army line the gap is smaller.

## Economy and growth

- Income per region per turn: wealth x 60 + settlement (village 0, town 80,
  city 200) + farm 40 per level + market 90 per level.
- Trade per partner (trade agreement or the allied player): 80 + 15 per
  region of the smaller realm, at most 260, then +15% per market level of
  ours (at most 3).
- A large realm costs income: 4% per region beyond 6, at most 40%.
- Upkeep per unit per turn: 15% of its price, whatever its strength.
- Ending a turn below zero: every unit loses a tenth of its men (at least one)
  and nothing replenishes. The AI disbands its most depleted units when in
  debt.
- Growth per turn: 1 + farm level (+1 for wealth 5 or more); town at 18,
  city at 45 points.
- Slots: village 2, town 3, city 4; capitals +2. Highest building level =
  settlement level + 1. One construction at a time per region.
- Recruits per turn: village 1, town 2, city 3; a recruit needs the line's
  building at its tier's level (workshop 1 bolts, 2 stones), is paid at once
  and joins the first army in the region with room at the end of the turn (or
  forms a new army).
- Replenishment in own or allied land, not in a battle, not in debt: 8% of
  full strength plus 6% per level of the line's building in that region.

| Chain | Levels | Cost | Turns | Effect |
|---|---|---|---|---|
| Farms | 3 | 400 / 900 / 1600 | 1 / 2 / 3 | +1 growth, +40 income per level |
| Market | 3 | 500 / 1000 / 1800 | 1 / 2 / 3 | +90 income, +15% trade per level |
| Barracks | 3 | 400 / 900 / 1600 | 1 / 2 / 3 | swords, light, spears, pikes of tier = level |
| Range | 3 | 350 / 800 / 1400 | 1 / 2 / 3 | archers, javelins of tier = level |
| Stables | 3 | 500 / 1000 / 1800 | 1 / 2 / 3 | cavalry of tier = level |
| Workshop | 2 | 600 / 1200 | 2 / 3 | bolt throwers / stone throwers |
| Walls | 3 | 400 / 900 / 1600 | 2 / 2 / 3 | garrison and defenders' high ground |

## Armies, movement, garrisons and battles

- An army is at most 12 units; moves one region or one sea lane per turn.
  Entry into a faction's region at peace is refused; declare war first
  (declarations apply before moves). Regions with a pending battle cannot be
  entered.
- Every owned settlement has a free garrison that only defends:
  2 / 3 / 4 units (village / town / city) + 1 per wall level, each 60% of a
  full unit (independents +2 units at 90%); tier 1, +1 in a city, +1 with
  walls 2 or more; types from the owner's roster (spear, missile, melee in
  turn). Garrison strength recovers 25 points a turn (to 100%). A captured
  settlement's garrison starts at 30%.
- **Walls in battle (chosen mechanism):** extra garrison units (above), better
  garrison tiers, and the defenders' front stands on a ridge across the field
  3 m + 3 m per wall level high (a terrain feature added to the region's
  terrain; the battle AI holds high ground 4 m or more above the enemy). In the
  formula the garrison counts +15% per wall level. Real walls are later.
- Reinforcements: armies of either side in regions joined by a land route that
  did not move this turn and are not committed elsewhere join the battle,
  until a side has 24 field units.
- A battle in the sim: attackers and defenders (armies at their current
  headcounts and tiers, the garrison on the defending side, reinforcements
  simply more units in the line: they do not yet arrive from the map edge they
  come from), at most 24 field units a side plus the garrison; the player's
  side at the bottom (sim side 0); terrain kind from the region, terrain seed
  and battle seed from campaign seed + region + turn. Layout: cavalry on the
  wings, bolt throwers at the line ends, pikes centre, missiles 15 m ahead,
  stone throwers behind, past 12 units a second infantry line 45 m back.
  Field 560-960 m wide.
- Command seam: `CBattle.build` returns `unit_faction` and `controller` for
  every sim unit; today the present player commands every unit on the player
  side (allied armies included). Co-op battles (milestone 5) split it there.
- Applying a result: every unit keeps remaining + withdrawn + 70% of its
  routed-off men; empty units and armies go. The loser's armies in the region
  retreat (attackers to where they came from if still friendly, else any
  friendly neighbour, land first) or are destroyed if there is none;
  reinforcements stay where they are. If the attackers win, the lead attacker
  (or the first attacking faction still there) takes the region; a draw counts
  as the defenders holding.
- **Leaving a battle midway** (Leave, tapped twice) is a forfeit: losses so far
  stand, the player's men still on the field withdraw (they all rejoin), the
  other side wins. If the page dies mid-battle nothing was saved, so the
  battle is still pending on reload.
- **Auto-resolve** (battles with a player): the real battle sim, AI against
  AI, from the same inputs as a fought battle, run in 24 ms slices per frame
  with a progress bar. Above 2,600 soldiers it runs every unit at half its men
  (artillery unscaled) and scales the losses back up.
- **AI-only battles:** formula. Side strength = men x (unit price / unit
  size), defenders + garrison (+15% per wall level), defenders x (100 +
  ground)% (hill / ridge 15, rolling / valley 10, flat 5). Attacker wins with
  chance Sa^3 / (Sa^3 + Sd^3) (state RNG). Winner loses 3.2% per 100% of the
  loser/winner strength ratio (4-45%) killed; loser 66% - 12% x ratio +-5 (35-80%)
  killed and 20% routed.

Timings (native Linux desktop, AMD Ryzen 7 5800X, one thread):

| Battle | Soldiers | Ticks (battle time) | Wall time |
|---|---|---|---|
| 12 v 12, full size | 2,080 | 3,000-3,550 (5-6 min) | 4.1-4.4 s |
| 12 v 12, half size | 1,040 | 2,700-3,050 | 2.0-2.1 s |
| 24 v 24, full size | 4,160 | 4,450-4,600 (7.5 min) | 10.5-10.8 s |
| 24 v 24, half size (used) | 2,080 | 4,100-4,300 | 5.9-6.5 s |

A phone browser is roughly 3-4x slower and the slices leave ~60% of each
frame to the sim, so: 12 v 12 about 20-30 s, 24 v 24 (fast mode) about 35-50 s
worst case; untested on a phone.

Formula vs sim (`tests/campaign_battles.gd --only=calib --n=60`, random
armies of 2-12 units, random lines and tiers, random garrisons): the
formula's favourite won the sim battle 53 / 60 (88%); by predicted chance:
0-20% -> sim attacker won 4%, 20-40% -> 0%, 40-60% -> 38%, 60-80% -> 75%,
80-100% -> 100%. Killed share winner / loser: sim 23% / 60%, formula
19% / 58%.

## Diplomacy and AI

- Per pair: war, peace, trade; the players are allied for good.
- Player proposals are answered at resolution. AI accepts **peace** after 3+
  turns of war if its strength < the proposer's, after 18 turns, or when down
  to 2 regions; **trade** after 2+ turns of peace unless it is 2.5x stronger;
  ending trade always.
- AI factions each turn: merge armies together; disband the most depleted
  units while in debt; build (budget 60% of treasury above one turn of
  upkeep): walls where threatened, farms and markets, the military buildings
  of their preferred lines in towns and capitals, workshops; recruit by their
  preferred mix (e.g. Rome 45% heavy, 20% javelins, 15% spears, 15% cavalry)
  at the best tier available, while upkeep stays under 70% of income (x
  aggression, +10 points at war, +1 point per 10% of income in the bank, up to
  +40); attack an adjacent hostile region (land or sea) when the armies that
  can reach it bring 1.5x its defence (garrison with walls and ground, armies
  there, half the hostile armies next to it), most valuable per defence first;
  armies whose region is threatened stay; the rest march towards the frontier.
- AI diplomacy: peace offers after 6+ turns of war when weaker than 70%, or
  after 20 turns; 15% chance a turn of a trade offer to a neighbour at peace;
  war on a neighbour at peace 6+ turns that is weaker (needs 1.2x strength, or
  0.9x if that neighbour is already at war), 12% a turn (8% on the players)
  x aggression, halved with trade, reduced for realms over 8 regions; no AI
  war before turn 6, none on the players before turn 10 or within 8 turns of
  the last, and no new war while at war with 2.
- AI-only campaigns, 60 turns, 6 seeds (`tests/campaign_sim.gd -- --seeds=6`),
  regions held by the largest faction at turn 15 / 30 / 60 per seed: 10/14/18
  (Carthage), 10/10/21 (Carthage), 9/11/10, 10/10/10, 10/9/16 (Rome), 10/12/15.
  Eliminations by turn 60: 4, 1, 1, 2, 3, 4 factions (Epirus, Syracuse and the
  Iberians go most often). Battles 30-58 per campaign; armies 18-31, units
  180-300; treasuries between -2,300 and +7,300 (debt is brief). Full AI turn
  (all 8 factions, resolution included) 10.7-12.2 ms mean, 16.5 ms worst,
  native desktop. Carthage, rich and spread out, is the faction most likely
  to snowball in the second half.

## Victory and defeat

Players win together holding 20 regions including 3 of Roma, Carthago, Pella,
Syracusae, Athenae (settings 15-30 regions, 2-5 cities); they lose if either
player's faction has no region left. A faction with no regions is eliminated
and its armies disband.

## Screens

- **Main menu:** New campaign / Continue (save list, delete) / Import; Battle
  sandbox (the battles, terrain, replay, tests); Unit book; Controls; UI size;
  Fullscreen.
- **New campaign:** 1 or 2 players (any two factions), name, seed, win
  target, great cities, turn timeout (stored only), battles ask / always
  auto, AI calm / normal / aggressive.
- **Map:** pan (drag, right / middle drag, W A S D / arrows), zoom (pinch,
  wheel, + / -) from the whole map to close up; territories tinted by owner;
  settlements sized by level, rings for walls, gold dot for great cities;
  dashed land routes, dotted light-blue sea lanes; army banners in faction
  colour with unit count and strength bar (players' outlined in white),
  scaled down and overlapped when zoomed out; pending battles as red crosses.
  Tap an army: its panel, its destinations highlighted (red = attack); tap a
  destination to plan the move (arrow), again to cancel; right click works too.
  Tap a region: its panel. Tab cycles armies; Ctrl+Enter ends the turn.
- **Region panel:** income, growth, armies, recruit list (best tier per line,
  price and upkeep; tap a unit for its unit book page with a Recruit button;
  "+" recruits at once; planned recruits with X), buildings (build / upgrade
  with cost and turns, or why not), garrison.
- **Army panel:** units with strength bars; tap units to choose them; Split
  off, Disband (confirm), Merge into another army there, Book; planned move
  with Cancel.
- **Realm, Diplomacy, Goals, Battles, Menu** dialogs; turn summary ("since you
  last played": your battles, gains and losses, diplomacy, buildings,
  recruits, growth, failed orders; captures and wars elsewhere); battle result;
  End turn with a short warning list (armies next to an enemy without orders,
  regions that could build, unanswered offers) that can be skipped.
- **Hot seat:** each player plans in turn behind a hand-over screen; the
  submissions are exactly the milestone-4 payload. **Saves:** one file per
  campaign in `user://campaigns/` (IndexedDB on the web), written on every
  order change, submission, resolution and battle; Continue lists them;
  Export gives one line of text (gzip + base64) to paste into Import on the
  other device.

## Tests

- `tests/campaign_test.gd` rules, JSON round trip, determinism (also across a
  save/load), movement, sea lanes, economy sums, building and recruitment
  gating by level and tier, replenishment, armies, battle scenario and
  outcome, conquest, retreat, elimination, victory.
- `tests/campaign_sim.gd` AI-only campaigns (pacing, economy, time per turn).
- `tests/campaign_solo.gd` a player faction with a simple policy for 20
  turns, pending battles auto-resolved with the sim, consistency checks.
- `tests/campaign_battles.gd` auto-resolve timing and formula calibration.
- `tests/campaign_input_test.gd` (windowed) the screens with synthetic
  touches.

## Later

Vegetation and region-driven map generation; reinforcements arriving from
the map edge; real walls and sieges; elephants, camels, chariots; both players
sharing one empire; turn timeout enforcement (server); live co-op battles.
