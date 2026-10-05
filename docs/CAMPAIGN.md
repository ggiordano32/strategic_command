# Campaign Design (milestone 3) — draft 1

Agreed with the user on 2026-10-05 unless marked **DEFAULT** (my proposal,
not yet confirmed) or **LATER**. `docs/DESIGN.md` section 2 has the original
outline; this file supersedes it for the campaign layer.

## Setting

The western and central Mediterranean from 280 BC: Pyrrhus in Italy, then the
Punic Wars. About 36 regions and 8 factions. A campaign should run 40-60
turns, which is one to two months at one or two turns a day.

## Players

- Two human players, permanently allied, each picking any faction.
- **LATER:** both players sharing one empire (e.g. two Roman consuls).
- The campaign must also be playable solo (one human, the rest AI) for
  testing and for playing alone.

## Map

Regions are nodes joined by land routes and sea lanes. Each has one
settlement, a terrain kind used to generate its battle map, and an owner.

| Area | Region (settlement) | Terrain |
|---|---|---|
| Italy | Latium (Roma) | rolling |
| | Etruria (Arretium) | hill |
| | Campania (Capua) | flat |
| | Samnium (Beneventum) | ridge |
| | Apulia (Tarentum) | flat |
| | Bruttium (Rhegium) | hill |
| | Gallia Cisalpina (Mediolanum) | flat |
| | Venetia (Patavium) | flat |
| Islands | Sicilia Occidentalis (Lilybaeum) | hill |
| | Sicilia Orientalis (Syracusae) | rolling |
| | Sardinia (Caralis) | hill |
| | Corsica (Aleria) | ridge |
| Iberia | Baetica (Gades) | rolling |
| | Contestania (Mastia) | hill |
| | Edetania (Saguntum) | rolling |
| | Ilergetia (Emporion) | rolling |
| | Celtiberia (Numantia) | ridge |
| | Carpetania (Toletum) | flat |
| | Lusitania (Olisipo) | rolling |
| | Gallaecia (Brigantium) | hill |
| Southern Gaul | Massalia (Massalia) | hill |
| | Volcae (Narbo) | flat |
| | Arverni (Gergovia) | ridge |
| | Allobroges (Vienna) | valley |
| Greece | Macedonia (Pella) | rolling |
| | Thessalia (Larissa) | flat |
| | Epirus (Ambracia) | ridge |
| | Illyria (Scodra) | hill |
| | Aetolia (Thermon) | ridge |
| | Attica (Athenae) | rolling |
| | Achaea (Corinthus) | hill |
| | Laconia (Sparta) | valley |
| Africa | Zeugitana (Carthago) | flat |
| | Byzacena (Hadrumetum) | flat |
| | Numidia (Cirta) | rolling |
| | Mauretania (Tingis) | hill |

Sea lanes join ports (for example Rhegium-Syracusae, Lilybaeum-Carthago,
Tarentum-Ambracia, Gades-Tingis, Massalia-Aleria, Caralis-Carthago). Crossing
a sea lane takes a full turn. There are no fleets and no naval battles.

## Factions and starting positions (DEFAULT)

| Faction | Starts with | Army style |
|---|---|---|
| Rome | Latium, Etruria, Campania, Samnium | Heavy swords, javelins, some cavalry |
| Carthage | Zeugitana, Byzacena, Sicilia Occ., Sardinia, Baetica | Mixed mercenaries, strong cavalry |
| Macedon | Macedonia, Thessalia | Pikes, shock cavalry, artillery |
| Epirus | Epirus, Apulia | Pikes, cavalry (elephants later) |
| Greek League | Attica, Achaea, Aetolia | Spearmen, archers, artillery |
| Syracuse | Sicilia Orientalis, Bruttium | Spearmen, artillery, mercenaries |
| Iberian tribes | Edetania, Celtiberia, Carpetania | Light infantry, javelins, light cavalry |
| Gallic tribes | Gallia Cisalpina, Arverni, Volcae | Warbands (light and heavy), cavalry |

All other regions start independent, each with a garrison, and do not expand.

Faction rosters are selections from the shared unit types, with small stat
variations where it adds character. **LATER:** elephants, then camels,
chariots and war dogs.

## Turn structure

- Two turns per year (summer, winter).
- Simultaneous planning; the turn resolves when both players have submitted,
  then AI factions act. Turn timeout is a campaign setting (off, or one of
  several durations).
- The campaign rules are deterministic and integer-only, and the whole state
  serialises to one JSON blob, so whichever client submits last can resolve
  the turn and upload the result (milestone 4).

## Armies and movement

- An army is a stack of up to 12 units (**DEFAULT**; battles of two allied
  armies against two enemy armies then stay near the 4,000-soldier target).
- An army moves one region per turn along a route, or crosses one sea lane.
- Entering a region holding an enemy army or settlement creates a battle.
- Armies in adjacent regions can reinforce a battle (**DEFAULT**: adjacent
  and not already committed elsewhere this turn).
- Units keep their losses after a battle and replenish slowly in friendly
  territory, faster in a region with the right military building.
- Each owned settlement has a small free garrison that only defends.

## Economy and building

- One currency. Income per region from its base wealth, buildings and trade
  agreements; upkeep per unit.
- Each settlement has 4 building slots (capitals 6). Chains, three levels each:
  farm (growth and income), market (income, trade), barracks (infantry),
  stables (cavalry), range (missiles), workshop (artillery), walls
  (garrison strength now, real sieges later).
- Recruitment happens in a settlement with the required building, takes one
  turn, and uses the unit book page as its screen.

### Unit tiers and city growth (requested by the user)

- Every unit line has tiers, unlocked by the level of its military building:
  level 1 gives the basic unit (levy spearmen, militia), level 2 the trained
  version, level 3 the elite (royal guards, veteran legionaries, companion
  cavalry): heavier armour, better training and morale, higher cost and
  upkeep. Starting cities can only raise tier 1; a built-up city is what
  makes elite armies possible.
- Tiers are data: a tier is a unit type entry derived from its base type with
  stat changes, its own name, symbol mark and unit book page.
- First version: three tiers for the core lines (melee infantry, spear or
  pike, missile, cavalry); artillery has one tier. Faction-flavoured elites
  where history offers them (triarii, silver shields, sacred band).
- Settlements grow: a settlement level (village, town, city) rises with
  population from farms and time, and unlocks building slots and higher
  building levels.
- Garrisons grow with the settlement and its walls: more and better garrison
  units at each settlement level, more again per wall level.
- Walls: until real sieges exist, each wall level adds garrison units and a
  defender's bonus in the settlement battle. **LATER:** walls and gates on
  the battle map.

## Diplomacy

- Per pair of factions: war, peace, or peace with a trade agreement.
- The two players are permanently allied with each other.
- AI accepts or refuses by a simple score: relative strength, how long the
  war has run, shared enemies, shared borders.
- Starting wars follow history where it is clear (Rome and Epirus at war;
  Carthage and Syracuse at war).

## Battles from the campaign

- A battle becomes pending rather than blocking silently; the turn cannot
  advance past it. It is resolved by auto-resolve, a solo real-time battle,
  or (milestone 5) a live co-op battle.
- If the ally's army is involved and they are offline, the present player
  chooses per battle: wait for them, or take command of their army.
- The battle map is generated from the region's terrain kind and a seed
  derived from the campaign seed, region and turn.
- The battle sim's result (killed, routed, withdrawn, remaining per unit)
  feeds straight back into the armies.
- Attacking a settlement is a field battle with the garrison on the
  defender's side. **LATER:** walls and gates.
- Auto-resolve is deliberately a little worse than competent play.

## Vegetation (built alongside)

Forest zones on battle maps that slow and disorder formations (cavalry
most), blunt missile fire, and are drawn as tree sprites that fade over
units. Regions gain a forest density that feeds map generation.

## Winning (DEFAULT)

The players win together when they jointly hold 20 regions including three
of Roma, Carthago, Pella, Syracusae and Athenae. They lose if either player
is eliminated. Campaign settings can adjust the target.

## Screens (phone first)

- Map: pan and zoom, tap a region for its panel, tap an army then a
  neighbouring region to move, clear ownership colours and army markers.
- Region panel: buildings, recruitment queue, garrison.
- Army panel: unit list with strength, merge and split.
- Diplomacy, turn summary (what happened since you last played), pending
  battles list, end-turn button.

## Build order

1. Data and rules: map, factions, economy, movement, turn resolution, save
   and load, all headless-testable.
2. Map screen and panels, solo play against passive neighbours.
3. Battles from the map: pending battles, auto-resolve, launch the real-time
   battle with generated terrain, results applied.
4. Campaign AI and diplomacy.
5. Vegetation and region-driven map generation.
6. Two players on one device (hot seat) as the stand-in until the async
   backend of milestone 4.
