extends RefCounted
## The weather rules (2026-11-09; docs/design/battle_sim.md "Weather in battle (as built, 2026-11-09)"). One table for the
## battle sim (sim/battle_sim.gd), the sea sim (sim/sea_sim.gd) and the view's sentences (game/weather.gd effects()).
##
## A scenario's optional "weather" string (game/weather.gd's token form: "downpour,wet", "snow,winter", "fog") is parsed
## once at setup into integer tiers: rain 0-3 (drizzle 1, rain 2, downpour / storm / tempest 3), snowfall 0-3 (light snow 1,
## snow 2, blizzard 3), fog 0/1, mud 0/1 (the ground token "wet", or rain 2+), snow cover 0/1 ("snowcover", or any snow kind).
## Overcast and the seasons are a look only (all tiers 0). The tiers enter the sims' state_hash() only when some tier is
## set (the veterancy precedent), so a battle without weather hashes as before. Integers only; no Nodes; no floats.

const T_RAIN := 0
const T_SNOW := 1
const T_FOG := 2
const T_MUD := 3
const T_COVER := 4
const T_N := 5

const RAIN_KINDS := {"drizzle": 1, "rain": 2, "downpour": 3, "storm": 3, "tempest": 3}
const SNOW_KINDS := {"lightsnow": 1, "snow": 2, "blizzard": 3}
const ALIASES := {"thunderstorm": "storm", "thunder": "storm", "flurries": "lightsnow", "light_snow": "lightsnow",
	"heavy_snow": "blizzard", "mist": "fog", "heavystorm": "tempest", "heavy_storm": "tempest", "snow_cover": "snowcover",
	"snowy": "snowcover", "wetground": "wet", "wet_ground": "wet"}
const OTHER_KINDS := ["clear", "overcast", "fog", "cloudy", "sun", "dry"]

## The effects, by tier (index 0: none). Percent of the clear day's value.
const WX_RL_RAIN: Array[int] = [0, 10, 20, 35]     # gunpowder reload time, % longer (muskets, pistols, all guns, ships' guns)
const WX_RL_SNOW: Array[int] = [0, 5, 10, 15]      # ... in falling snow
const WX_SPR_RAIN: Array[int] = [0, 5, 10, 20]     # missile scatter, % more (every shooter)
const WX_SPR_SNOW: Array[int] = [0, 10, 20, 35]
const WX_SPR_FOG := 20
const WX_SIGHT_M := 200                            # the weather's sight at x1.0 (m): a clear day has no limit
const WX_SIGHT_FOG := 50                           # sight, % of WX_SIGHT_M: fog ...
const WX_SIGHT_SNOW: Array[int] = [100, 100, 75, 50]   # ... snowfall (tier 2 x 0.75, the blizzard x 0.5)
const WX_SIGHT_RAIN: Array[int] = [100, 100, 100, 75]  # ... rain (the downpour and the storms x 0.75)
const WX_MUD: Array[int] = [90, 85, 75]            # mud: speed % of foot, horse, guns / wagons / the ram
const WX_MUD_CHARGE := 90                          # ... and a charge's impact %
const WX_COVER: Array[int] = [90, 90, 75]          # snow cover: speed % of foot, horse, guns / wagons / the ram
const WX_FIRE_RAIN := 2                            # no fire shot at this rain tier or more ...
const WX_FIRE_SNOW := 3                            # ... nor in this snowfall (the blizzard)
const WX_BURN_PCT := 50                            # fires already burning last this % as long at rain tier WX_FIRE_RAIN+
const CAT_FOOT := 0
const CAT_HORSE := 1
const CAT_GUN := 2


## "downpour,wet" -> [rain, snow, fog, mud, cover]. Unknown tokens and the seasons are ignored.
static func tiers(w: String) -> PackedInt32Array:
	var t := PackedInt32Array([0, 0, 0, 0, 0])
	var wet := false
	var cover := false
	for tok in w.to_lower().replace(",", " ").replace("+", " ").replace(":", " ").split(" ", false):
		var k: String = ALIASES.get(tok, tok)
		if RAIN_KINDS.has(k):
			t[T_RAIN] = int(RAIN_KINDS[k])
			t[T_SNOW] = 0
			t[T_FOG] = 0
		elif SNOW_KINDS.has(k):
			t[T_SNOW] = int(SNOW_KINDS[k])
			t[T_RAIN] = 0
			t[T_FOG] = 0
		elif k in OTHER_KINDS:
			t[T_RAIN] = 0
			t[T_SNOW] = 0
			t[T_FOG] = 1 if k == "fog" else 0
		elif k == "wet":
			wet = true
		elif k == "snowcover":
			cover = true
	t[T_MUD] = 1 if wet or t[T_RAIN] >= 2 else 0
	t[T_COVER] = 1 if cover or t[T_SNOW] > 0 else 0
	return t


## Some rule applies (the tiers are hashed).
static func any(t: PackedInt32Array) -> bool:
	for i in T_N:
		if t[i] != 0:
			return true
	return false


## Gunpowder reload time, % longer.
static func reload_pct(t: PackedInt32Array) -> int:
	return WX_RL_RAIN[t[T_RAIN]] + WX_RL_SNOW[t[T_SNOW]]


## Missile scatter, % more.
static func spread_pct(t: PackedInt32Array) -> int:
	return WX_SPR_RAIN[t[T_RAIN]] + WX_SPR_SNOW[t[T_SNOW]] + (WX_SPR_FOG if t[T_FOG] != 0 else 0)


## Sight, % of WX_SIGHT_M (100: no limit).
static func sight_pct(t: PackedInt32Array) -> int:
	var p := mini(WX_SIGHT_SNOW[t[T_SNOW]], WX_SIGHT_RAIN[t[T_RAIN]])
	if t[T_FOG] != 0:
		p = mini(p, WX_SIGHT_FOG)
	return p


## Sight in metres (0: no limit).
static func sight_m(t: PackedInt32Array) -> int:
	var p := sight_pct(t)
	return 0 if p >= 100 else WX_SIGHT_M * p / 100


## Fire shot can be lit.
static func fire_ok(t: PackedInt32Array) -> bool:
	return t[T_RAIN] < WX_FIRE_RAIN and t[T_SNOW] < WX_FIRE_SNOW


## Fires already burning last this % as long.
static func burn_pct(t: PackedInt32Array) -> int:
	return WX_BURN_PCT if t[T_RAIN] >= WX_FIRE_RAIN else 100


## Speed % of category cat (CAT_FOOT, CAT_HORSE, CAT_GUN): mud and snow cover, the worse of the two.
static func speed_pct(t: PackedInt32Array, cat: int) -> int:
	var p := 100
	if t[T_MUD] != 0:
		p = mini(p, WX_MUD[cat])
	if t[T_COVER] != 0:
		p = mini(p, WX_COVER[cat])
	return p


## A charge's impact %.
static func charge_pct(t: PackedInt32Array) -> int:
	return WX_MUD_CHARGE if t[T_MUD] != 0 else 100
