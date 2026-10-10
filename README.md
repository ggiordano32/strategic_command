# Strategic Command

A co-op grand strategy game in the spirit of *Rome II: Total War*, built for
phones and browsers. Run an empire in the western Mediterranean of 280 BC on
your own time, then meet up for the battles.

![Campaign map: the Alps and the Po valley on the terrain view, real relief from elevation data](docs/screenshots/overworld_terrain_alps.png)

## What it is

- **A campaign you play in 15-minute sittings.** Each of you commands a
  faction; turns are asynchronous, so you move your armies, build and
  recruit whenever you like and the turn resolves when you've both
  submitted. Pick any two factions: Rome, Carthage, Syracuse, Epirus,
  Macedon, the Greeks, the Iberians, the Gauls.
- **A real map.** The overworld is fitted to real elevation, coastlines and
  rivers: mountains cost movement, rivers block it except at the historic
  fords and bridges, Roman roads speed it up, and a battle at a crossing is
  fought on that crossing's own map, where a fortified defender holds the
  far bank from a camp at the ford.
- **Real battles, not dice rolls.** Every soldier is simulated: health,
  shield, blocks, hits, fatigue and nerve. Pikes hold, cavalry charges
  wrap round a flank, archers lead their targets, bolt and stone throwers
  need a line of fire, and units break and run when they have had enough.
  Four thousand men on a phone at 60 fps.
- **A full roster.** Heavy and light foot, spears and pikes, archers,
  javelins and slingers, shock and missile cavalry, camels that spook
  horses, elephants that break lines or run amok, war dogs loosed on
  skirmishers, and a general whose presence steadies his men. Fire arrows,
  lead bullets and explosive stones as special ammunition; forage in the
  woods or bring a wagon when the quivers run dry.
- **Sieges that feel like sieges.** Settlements grow from villages to
  walled cities in the style of their founders: Roman grids, Greek towns
  with an acropolis, Punic citadels, Celtic hill forts. Bolt and stone
  throwers on the towers, ladders, rams, siege towers and mantlets earned
  by besieging for turns, stakes and caltrops in the field, a palisaded
  camp when you fortify. Break a gate, burn it, climb the wall, take the
  plaza. Or starve them out.
- **Fight together, live.** When a battle has both your armies in it you
  can jump in at the same time: each commands their own units, you can
  gift units to each other mid-fight, and pause and speed are by vote.
  Or auto-resolve and get on with the turn.
- **An AI that plays by your rules.** Easy, Average and Skilled on the
  field and on the map, with no cheats: skill is reaction, perception and
  planning. The diplomacy screen tells you whether an AI would accept
  your offer before you send it, and a chronicle keeps the world's news
  turn by turn.

| | |
|---|---|
| ![A river crossing: the attacker wades the ford into a fortified camp](docs/screenshots/river_crossing_fortified.png) | ![Fire arrows and an explosive stone landing on a gate](docs/screenshots/siege_fire_and_blast.png) |
| A ford battle: the defenders fortified at the crossing | Fire arrows on the gate and a blast in the ranks |
| ![A Greek coastal city](docs/screenshots/settlements_polis_hill_coast.png) | ![Raising an army: unit cards with traits, counters and stat pips](docs/screenshots/recruit_cards_tablet.png) |
| A Greek city on a coastal hill with its acropolis | Raising an army: what each unit is good and bad against |

## The units

Every unit is a row of data: its men, weapons, armour, nerve and quirks. Three
tiers per line as the buildings grow, and each faction's own named troops on top.

**Infantry**

| Unit | Role | |
|---|---|---|
| Heavy Swords | Line infantry | Armoured swordsmen with large shields, the backbone of the line. |
| Light Infantry | Fast infantry | Fast, lightly armoured fighters. |
| Spearmen | Anti-cavalry infantry | Steady spearmen whose second rank can also reach. |
| Pikemen | Phalanx | A dense block whose first four ranks all strike with 5.5 m pikes. |

**Missile troops**

| Unit | Role | |
|---|---|---|
| Archers | Missile infantry | Long-range bowmen who shoot over friendly units and hills and lead moving targets. |
| Javelinmen | Skirmishers | Loose-order skirmishers throwing armour-piercing javelins at short range. |
| Slingers | Missile infantry | Light troops with slings who outrange the bow and shoot faster. |
| Gastraphetes | Missile infantry (belly-bows) | Greek belly-bowmen: a composite bow on a stock, spanned by leaning on it with the belly, shot like a small bolt engine. |

**Cavalry and beasts**

| Unit | Role | |
|---|---|---|
| Shock Cavalry | Shock cavalry | Heavy horsemen. |
| Light Horse | Missile cavalry | Javelin riders on small, quick horses. |
| Camel Riders | Anti-cavalry riders | Riders on camels. |
| Camel Archers | Mounted archers on camels | Archers on camels: they shoot from the saddle at a fair range, ride away from what comes for them, and scare horses like any camels (enemy horsemen within 30 m lose much of their charge and turn rate and lose heart). |
| War Elephants | Shock beasts | Twelve war elephants, each a driver and two javelin men on its back. |

**Artillery and the train**

| Unit | Role | |
|---|---|---|
| Bolt Throwers | Light artillery (scorpions) | Four torsion bolt throwers with their crews. |
| Stone Throwers | Heavy artillery (onagers) | Three onagers lobbing heavy stones over friendly troops and hills at very long range. |
| Scorpions | Light artillery (carried scorpions) | Six small bolt engines, two men to each, light enough for the crews to carry: they march at a man's walking pace and set up or pack up in a moment, so they keep up with an assault and shoot the men on the wall above the ladders and the ram. |
| Hand Cart | Ammunition wagon | A hand cart of arrows, javelins and shot pulled by its eight men at walking pace or slower. |

**Commanders and dogs**

| Unit | Role | |
|---|---|---|
| General's Bodyguard | The general and his guard | The army's commander and his picked riders. |
| War Dogs | Handlers and a pack of war dogs | Sixteen handlers with a pack of two dogs each. |

**Named troops by faction**

- **Rome:** Principes, Extraordinarii, Triarii, Legate's Guard.
- **Carthage:** Sacred Band, Balearic Slingers, Numidian Horse, Sufet's Guard.
- **Macedon:** Phalangites, Silver Shields, Companion Cavalry, Royal Hetairoi.
- **The Greek League:** Hoplites, Picked Hoplites, Cretan Archers, Rhodian Slingers, Tarentine Horse, Strategos' Guard.
- **Syracuse:** Hoplites, Picked Hoplites, Cretan Archers, Gastraphetes, Strategos' Guard.
- **Epirus:** Chaonian Guard, Agema, Tarentine Horse, War Elephants, Royal Hetairoi.
- **The Gauls:** Gallic Warband, Gallic Nobles, Noble Cavalry, Gallic Light Horse, Chieftain's Guard.
- **The Iberians:** Scutarii, Caetrati, Iberian Slingers, Iberian Light Horse, Chieftain's Guard.

Special ammunition comes with the buildings and the faction: fire arrows and
javelins that burn gates, wagons and palisades, lead sling bullets, heavy
bolts, and explosive stones that burst in a 4 m blast and throw men down.

## Co-op play

1. One of you creates a campaign and sends the other a join code.
2. Each turn: move armies across the map (roads, rivers, hills, zones of
   control, sieges by marching onto a city), build, recruit, trade, make
   and break treaties. Armies within range support each other in battle.
   Submit.
3. When a battle involves one of you, you get a ping. Fight it yourself,
   auto-resolve it, or open the lobby and fight it together in real time;
   the other player can join any fought battle and be given units.
4. Gift units, armies, cities or money to each other on the map, and pass
   units across during a live battle.

![Live co-op: a pause vote during a battle](docs/screenshots/live_phone_vote.png)

## Tech, briefly

Godot 4 (GDScript), exported to the web as a progressive web app; a
deterministic integer-only battle simulation with lockstep networking for
live co-op; a small Go server with SQLite for campaigns, turns and battle
coordination; the overworld baked from public-domain elevation (ETOPO 2022)
and Natural Earth coastlines and rivers by a tool that takes any window of
the globe, so the same engine can carry other settings. Design notes live
in [`docs/`](docs/).

Playable in any modern browser on Android, iPhone or desktop. Ask Garrett
for the link and the invite key.
