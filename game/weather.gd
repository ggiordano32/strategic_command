extends RefCounted
## The weather pass, the look (2026-11-06; docs/design/art_pipeline.md "The weather pass, the look"). View only: a battle's weather
## is a view parameter read from the battle's setup (`Battle.weather`, a string such as "storm,winter"), never from or into the
## sim or the campaign state (the rules half comes later and will make it a sim parameter; `Weather.spec` is what it will read).
##
## A weather is a kind (clear, overcast, drizzle / rain / downpour, storm, light snow / snow / blizzard, fog) and a season (spring,
## summer, autumn, winter) which combine: "rain,autumn", "snow,winter", "storm". Tokens in any order, commas or spaces; unknown
## tokens are ignored. `spec(w)` is the numbers every view draws from; `apply_globals` sets the shader globals (game/weather.gdshaderinc)
## the board, the trees and the kit read; the layers are game/weather_layer.gd (grade, veil, rain / snow, lightning in every view) and
## game/weather3d.gd (the 3D view's particle volume, lamp, ambient and fog).

const Quality := preload("res://game/quality.gd")
const TrackLayer := preload("res://game/track_layer.gd")

const KINDS := ["clear", "overcast", "drizzle", "rain", "downpour", "storm", "tempest", "lightsnow", "snow", "blizzard", "fog"]
const KIND_NAMES := ["Clear", "Overcast", "Drizzle", "Rain", "Downpour", "Thunderstorm", "Heavy thunderstorm", "Light snow", "Snow", "Blizzard", "Fog"]
## The ground token (weather variety, 2026-11-07), separate from the sky: "snowcover" = snow lies (board, hills, crowns, roofs) with
## no flakes falling; "wet" = the board wet and the tracks heavier with no rain falling. The snow kinds imply snowcover, the rain kinds wet.
const GROUNDS := ["", "snowcover", "wet"]
const GROUND_NAMES := ["As it comes", "Snow cover", "Wet"]
const SEASONS := ["", "spring", "summer", "autumn", "winter"]
const SEASON_NAMES := ["No season", "Spring", "Summer", "Autumn", "Winter"]
const ALIASES := {"thunderstorm": "storm", "thunder": "storm", "flurries": "lightsnow", "light_snow": "lightsnow", "heavy_snow": "blizzard",
	"mist": "fog", "cloudy": "overcast", "sun": "clear", "dry": "clear", "fall": "autumn", "heavystorm": "tempest",
	"heavy_storm": "tempest", "snow_cover": "snowcover", "snowy": "snowcover", "wetground": "wet", "wet_ground": "wet"}

## The weather the current battle was set up with ("" = clear, no season): set by Battle before any layer is built.
static var current := ""
static var _web := "?"


## "storm,winter" -> {"kind": "storm", "season": "winter"} (a missing kind is clear, a missing season ""), normalised.
static func parse(s: String) -> Dictionary:
	var kind := "clear"
	var season := ""
	var ground := ""
	for t in s.to_lower().replace(",", " ").replace("+", " ").replace(":", " ").split(" ", false):
		var k: String = ALIASES.get(t, t)
		if k in KINDS:
			kind = k
		elif k in SEASONS:
			season = k
		elif k in GROUNDS:
			ground = k
	return {"kind": kind, "season": season, "ground": ground}


static func join(kind: String, season: String, ground := "") -> String:
	var parts: Array = []
	if kind != "clear" and kind != "":
		parts.append(kind)
	if season != "":
		parts.append(season)
	if ground != "":
		parts.append(ground)
	return ",".join(parts)


## The testing aid: --weather=storm,winter, or on the web ?weather=storm,winter; "" when not given.
static func launch_arg() -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--weather="):
			return str(a).get_slice("=", 1)
	if OS.has_feature("web"):
		if _web == "?":
			_web = ""
			var q = JavaScriptBridge.eval("window.location.search", true)
			if q is String:
				for kv in (q as String).trim_prefix("?").split("&"):
					if kv.begins_with("weather="):
						_web = kv.get_slice("=", 1).uri_decode()
		return _web
	return ""


## A campaign battle's weather, from the turn's season and the content pack (the campaign has two turns a year, the even turns
## summer, the odd winter: campaign/cstorm.gd season). View only, the tint and the look; nothing in the rules reads it; the pick is
## from the turn and a seed in the state the view reads, so both peers see the same.
## Rome: summer clear (some overcast), winter snow, fog, overcast, or snow lying without snowfall (about half of the winter turns).
## The West (Caribbean, no snow): the summer turns are the wet season (rain, drizzle, a storm, now and then the heavy one, a wet
## field under an overcast sky), the winter turns the dry (clear, some overcast).
static func for_campaign(turn: int, pack: String, seed_v: int) -> String:
	var summer := turn % 2 == 0
	var h := (absi(seed_v) * 2654435761 + turn * 40503) % 100
	if pack == "west":
		if summer:
			if h < 12:
				return "tempest,summer" if h < 5 else "storm,summer"
			if h < 40:
				return "rain,summer"
			if h < 58:
				return "overcast,summer,wet"
			return ("drizzle" if h < 80 else "overcast") + ",summer"
		return ("overcast" if h < 25 else "clear") + ",spring"
	if summer:
		return ("overcast" if h < 25 else "clear") + ",summer"
	if h < 25:
		return "snow,winter"
	if h < 33:
		return "fog,winter"
	if h < 50:
		return "overcast,winter"
	return ("overcast" if h < 75 else "clear") + ",winter,snowcover"


## Everything a view draws, for a weather string. mul: the grade multiplied over the screen (rgb); veil: colour and alpha laid over;
## fog_m: the visibility in metres (0: none); rain / snow: density 0..1; wet, cover: the board's wetness and snow cover; mud: the
## tracks' extra strength; lamp_k, amb_k: the 3D lamp's and ambient's energy against the clear day's; storm: lightning;
## wind: the precipitation's slant (x per unit fall); tmul, tadd: the season's grade of the board and the trees.
static func spec(w: String) -> Dictionary:
	var p := parse(w)
	var k: String = p["kind"]
	var s := {"kind": k, "season": p["season"], "mul": Color(1, 1, 1), "veil": Color(0.8, 0.82, 0.86, 0.0), "fog_m": 0.0,
		"rain": 0.0, "snow": 0.0, "wet": 0.0, "cover": 0.0, "mud": 0.0, "lamp_k": 1.0, "amb_k": 1.0, "storm": false, "storm_k": 1.0, "wind": 0.0, "ground": p["ground"],
		"tmul": Color(1, 1, 1, 0), "tadd": Color(0, 0, 0, 0)}
	match k:
		"overcast":
			s.merge({"mul": Color(0.84, 0.87, 0.92), "veil": Color(0.74, 0.77, 0.82, 0.14), "lamp_k": 0.3, "amb_k": 2.2}, true)
		"drizzle":
			s.merge({"mul": Color(0.88, 0.9, 0.94), "veil": Color(0.62, 0.66, 0.73, 0.1), "lamp_k": 0.4, "amb_k": 2.0, "rain": 0.3,
				"wet": 0.5, "mud": 0.35, "wind": 0.1}, true)
		"rain":
			s.merge({"mul": Color(0.88, 0.9, 0.95), "veil": Color(0.55, 0.6, 0.69, 0.12), "lamp_k": 0.3, "amb_k": 2.2, "rain": 0.62,
				"wet": 0.85, "mud": 0.7, "wind": 0.18, "fog_m": 700.0}, true)
		"downpour":
			s.merge({"mul": Color(0.76, 0.8, 0.9), "veil": Color(0.46, 0.51, 0.62, 0.16), "lamp_k": 0.25, "amb_k": 2.3, "rain": 1.0,
				"wet": 1.0, "mud": 1.0, "wind": 0.28, "fog_m": 450.0}, true)
		"storm":
			s.merge({"mul": Color(0.76, 0.8, 0.9), "veil": Color(0.28, 0.31, 0.43, 0.12), "lamp_k": 0.2, "amb_k": 2.3, "rain": 0.8,
				"wet": 1.0, "mud": 1.0, "wind": 0.4, "fog_m": 380.0, "storm": true}, true)
		"tempest":
			s.merge({"mul": Color(0.68, 0.72, 0.84), "veil": Color(0.2, 0.23, 0.35, 0.18), "lamp_k": 0.15, "amb_k": 2.4, "rain": 1.0,
				"wet": 1.0, "mud": 1.0, "wind": 0.6, "fog_m": 300.0, "storm": true, "storm_k": 1.6}, true)
		"lightsnow":
			s.merge({"mul": Color(0.95, 0.97, 1.0), "veil": Color(0.92, 0.94, 0.98, 0.08), "lamp_k": 0.4, "amb_k": 1.7, "snow": 0.4,
				"cover": 0.7, "mud": 0.6, "wind": 0.05}, true)
		"snow":
			s.merge({"mul": Color(0.92, 0.94, 0.99), "veil": Color(0.92, 0.94, 0.98, 0.1), "lamp_k": 0.35, "amb_k": 1.7, "snow": 0.7,
				"cover": 1.0, "mud": 0.8, "wind": 0.1, "fog_m": 900.0}, true)
		"blizzard":
			s.merge({"mul": Color(0.92, 0.95, 1.0), "veil": Color(0.9, 0.92, 0.98, 0.26), "lamp_k": 0.4, "amb_k": 2.0, "snow": 1.0,
				"cover": 1.0, "mud": 0.8, "wind": 0.45, "fog_m": 260.0}, true)
		"fog":
			s.merge({"mul": Color(0.94, 0.95, 0.97), "veil": Color(0.8, 0.82, 0.85, 0.14), "lamp_k": 0.45, "amb_k": 1.9, "fog_m": 190.0}, true)
	# The ground token: snow lying or a wet field under any sky (the snow kinds and the rain kinds already have theirs).
	match str(p["ground"]):
		"snowcover":
			s["cover"] = maxf(float(s["cover"]), 1.0)
			s["mud"] = maxf(float(s["mud"]), 0.8)
		"wet":
			s["wet"] = maxf(float(s["wet"]), 0.85)
			s["mud"] = maxf(float(s["mud"]), 0.7)
	match str(p["season"]):
		"spring":
			s["tmul"] = Color(0.95, 1.12, 0.9, 0.0)
			s["tadd"] = Color(0.0, 0.012, 0.0, 0.0)
		"summer":
			s["tmul"] = Color(1.03, 1.0, 0.86, 0.0)
		"autumn":
			s["tmul"] = Color(1.5, 1.0, 0.8, 0.25)
			s["tadd"] = Color(0.04, 0.015, 0.0, 0.0)
		"winter":
			s["tmul"] = Color(1.28, 1.14, 1.02, 0.45)
			s["tadd"] = Color(0.02, 0.02, 0.03, 0.0)
	return s


## Set the shader globals for a spec (Low: no gloss). neutral() puts them back (a battle's end).
static func apply_globals(s: Dictionary) -> void:
	var low := Quality.is_low()
	var gloss := 0.0 if low else 1.0
	RenderingServer.global_shader_parameter_set("wx_surf", Plane(float(s["wet"]), float(s["cover"]), float(s["mud"]), gloss))
	var tm: Color = s["tmul"]
	var ta: Color = s["tadd"]
	RenderingServer.global_shader_parameter_set("wx_tmul", Plane(tm.r, tm.g, tm.b, tm.a))
	RenderingServer.global_shader_parameter_set("wx_tadd", Plane(ta.r, ta.g, ta.b, 0.0))
	# The tracks layer's hook (game/track_layer.gd weather_mul): mud and snow show the stamps stronger.
	var m := 1.0 + 0.25 * float(s["mud"])
	TrackLayer.weather_mul = Vector3(m, m, m)


## True when nothing is drawn: a clear day with no season (the layers are not built at all).
static func is_clear(s: Dictionary) -> bool:
	return str(s["kind"]) == "clear" and str(s["season"]) == "" and str(s["ground"]) == ""


static func neutral() -> void:
	apply_globals(spec(""))
