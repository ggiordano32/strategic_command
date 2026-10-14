extends RefCounted
## Shared campaign enums (every content pack and campaign/cdata.gd use these;
## cdata re-exports them under the same names, so the rules read CData.CITY,
## CData.RANGE ... as before). Values are stored in the state: never renumber.

const Terrain := preload("res://sim/terrain.gd")
const MapGen := preload("res://sim/mapgen.gd")

## Terrain kinds (sim/terrain.gd).
const FLAT := Terrain.K_FLAT
const ROLLING := Terrain.K_ROLLING
const RIDGE := Terrain.K_RIDGE
const VALLEY := Terrain.K_VALLEY
const HILL := Terrain.K_HILL
## Ground palettes (battle map and campaign map colour; sim/mapgen.gd).
const ARID := MapGen.PAL_ARID
const DRY := MapGen.PAL_DRY
const GREEN := MapGen.PAL_GREEN
const ROCKY := MapGen.PAL_ROCKY
## Founding cultures (sim/mapgen.gd): a settlement's wall plan is its
## founder's (region "culture", static); factions have a culture for the
## style of what they build and of their shrine (view only).
const LATIN := MapGen.CUL_LATIN
const GREEK := MapGen.CUL_GREEK
const PUNIC := MapGen.CUL_PUNIC
const CELTIC := MapGen.CUL_CELTIC

## Settlement levels.
const VILLAGE := 0
const TOWN := 1
const CITY := 2

## AI personalities (campaign/cai_profile.gd CAUTIOUS / BALANCED / AGGRESSIVE).
const AI_CAUTIOUS := 0
const AI_BALANCED := 1
const AI_AGGRESSIVE := 2

## Building chains (index into CData.CHAINS).
const FARM := 0
const MARKET := 1
const BARRACKS := 2
const RANGE := 3
const STABLES := 4
const WORKSHOP := 5
const WALLS := 6
