extends RefCounted
## Unit type stats as plain integer data. The sim copies these into packed
## arrays at setup, so adding a type is a matter of adding a row here.
##
## Units of measure (all ints):
##   distances in sim units (1 m = 1024), speeds in sim units per tick (10 Hz),
##   chances in percent, hp/damage in hit points, cooldown in ticks,
##   morale on a 0..1000 scale.
##
## Milestone 2 hooks: `reach` already drives melee range and `mass` is carried
## for cavalry impact, `ranks_reach` (how many ranks can strike) is 1 for every
## type now and will be used by pikes. Missile fields are not defined yet.

const HEAVY := 0
const LIGHT := 1
const SPEAR := 2

const TYPES: Array[Dictionary] = [
	{
		"name": "Heavy Swords",
		"short": "Heavy",
		"attack": 40,        # melee attack skill
		"defence": 35,       # melee defence skill
		"armour": 14,        # subtracted from weapon damage
		"shield": 40,        # % chance to block a frontal hit
		"damage": 42,        # weapon damage per hit
		"reach": 1331,       # 1.3 m
		"ranks_reach": 1,
		"mass": 90,
		"walk": 133,         # 1.3 m/s
		"run": 369,          # 3.6 m/s
		"hp": 100,
		"cooldown": 11,      # ticks between swings
		"morale": 720,
	},
	{
		"name": "Light Infantry",
		"short": "Light",
		"attack": 36,
		"defence": 26,
		"armour": 4,
		"shield": 15,
		"damage": 36,
		"reach": 1229,       # 1.2 m
		"ranks_reach": 1,
		"mass": 70,
		"walk": 164,         # 1.6 m/s
		"run": 451,          # 4.4 m/s
		"hp": 85,
		"cooldown": 9,
		"morale": 520,
	},
	{
		"name": "Spearmen",
		"short": "Spear",
		"attack": 30,
		"defence": 40,
		"armour": 9,
		"shield": 35,
		"damage": 36,
		"reach": 2253,       # 2.2 m
		"ranks_reach": 1,
		"mass": 80,
		"walk": 133,
		"run": 369,
		"hp": 90,
		"cooldown": 11,
		"morale": 620,
	},
]


static func count() -> int:
	return TYPES.size()
