extends RefCounted
## The weather pass, the look (2026-11-06; docs/design/art_pipeline.md "The weather pass, the look"), and since 2026-11-09 the
## rules told in words (the bottom of this file; the rules themselves: sim/wx.gd, docs/design/battle_sim.md "Weather in battle").
## A battle's weather is a string such as "storm,winter": the scenario's "weather" (the campaign's pending battle, decided by
## campaign/cweather.gd; the sandbox's picks), read by the sim as a rule and by the view as the look (`Battle.weather`).
##
## A weather is a kind (clear, overcast, drizzle / rain / downpour, storm, light snow / snow / blizzard, fog) and a season (spring,
## summer, autumn, winter) which combine: "rain,autumn", "snow,winter", "storm". Tokens in any order, commas or spaces; unknown
## tokens are ignored. `spec(w)` is the numbers every view draws from; `apply_globals` sets the shader globals (game/weather.gdshaderinc)
## the board, the trees and the kit read; the layers are game/weather_layer.gd (grade, veil, rain / snow, lightning in every view) and
## game/weather3d.gd (the 3D view's particle volume, lamp, ambient and fog).

const Quality := preload("res://game/quality.gd")
const TrackLayer := preload("res://game/track_layer.gd")
const CWeather := preload("res://campaign/cweather.gd")
const Wx := preload("res://sim/wx.gd")

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


## The campaign's season mapping with a seed-hash roll (the look's former pick, kept for the view tests). Since 2026-11-09 the
## campaign's battles take their weather from the rules (campaign/cweather.gd, one CState.rand draw when the battle is
## created, stored on the pending battle as "weather"); the mapping itself is CWeather.for_turn.
static func for_campaign(turn: int, pack: String, seed_v: int) -> String:
	return CWeather.for_turn(turn, pack, (absi(seed_v) * 2654435761 + turn * 40503) % 100)


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


# ------------------------------------------------------------ the rules in words ---
# The weather's rules (2026-11-09; sim/wx.gd, docs/design/battle_sim.md "Weather in battle") told to the player: one
# builder from the sim's tiers to sentences, for the battle HUD's weather chip and plate, the deployment line, the
# campaign's battle dialog, the custom battle's Sky and Ground tips and the how-to book's Weather page. The numbers come
# from the sim's table (Wx.WX_*), so the words follow the rules.

## A share in words (35 -> "a third").
static func frac(pct: int) -> String:
	match pct:
		5:
			return "a little"
		10:
			return "a tenth"
		15:
			return "about a sixth"
		20:
			return "a fifth"
		25:
			return "a quarter"
		35:
			return "a third"
		50:
			return "half"
	return "%d %%" % pct


## The weather's name for the chip and the plate's title: "Downpour, muddy ground", "Clear, snow on the ground".
static func rule_title(w: String) -> String:
	var p := parse(w)
	var t := Wx.tiers(w)
	var name: String = KIND_NAMES[KINDS.find(str(p["kind"]))]
	if t[Wx.T_MUD] != 0:
		return name + ", muddy ground"
	if t[Wx.T_COVER] != 0 and t[Wx.T_SNOW] == 0:
		return name + ", snow on the ground"
	return name


## Some rule applies (overcast, the seasons and a clear day: none).
static func has_rules(w: String) -> bool:
	return Wx.any(Wx.tiers(w))


## The HUD chip's words: the name and the ground short ("Downpour, mud", "Clear, snow"); compact (a phone): the ground's
## word only ("mud", "snow"), else none (the icon says the sky).
static func chip_text(w: String, compact: bool) -> String:
	var t := Wx.tiers(w)
	var g := ""
	if t[Wx.T_MUD] != 0:
		g = "mud"
	elif t[Wx.T_COVER] != 0:
		g = "snow"
	if compact:
		return g
	var name: String = KIND_NAMES[KINDS.find(str(parse(w)["kind"]))]
	if g == "" or (g == "snow" and t[Wx.T_SNOW] > 0):
		return name
	return name + ", " + g


## The chip's icon (game/ui_icons.gd): sun, cloud, rain, storm, snowflake, fog bands.
static func icon_of(w: String) -> String:
	match str(parse(w)["kind"]):
		"overcast":
			return "wx_cloud"
		"drizzle", "rain", "downpour":
			return "wx_rain"
		"storm", "tempest":
			return "wx_storm"
		"lightsnow", "snow", "blizzard":
			return "wx_snow"
		"fog":
			return "wx_fog"
	return "wx_cloud" if Wx.tiers(w)[Wx.T_MUD] != 0 else "wx_clear"


## Every active rule as a plain sentence, one per line (sea: a sea battle's: the guns and the lookouts only).
static func effects(w: String, sea := false) -> PackedStringArray:
	var t := Wx.tiers(w)
	var out := PackedStringArray()
	if not Wx.any(t):
		out.append("No effect on the battle: the sky and the season are a look only.")
		return out
	var rl := Wx.reload_pct(t)
	if rl > 0:
		out.append(("Ships' guns reload %s slower." if sea else "Muskets, pistols and guns reload %s slower.") % frac(rl))
	var sm := Wx.sight_m(t)
	if sea:
		if sm > 0:
			out.append("The lookouts see %s as far (%d m): no broadside beyond it." % ["half" if Wx.sight_pct(t) == 50 else "three quarters", sm])
		if out.is_empty():
			out.append("No effect at sea: the ground's mud or snow is the land's.")
		out.append("No effect on the wind, morale or boarding.")
		return out
	if not Wx.fire_ok(t):
		out.append("Fire arrows and fire pots cannot be lit: they shoot plain shot.")
	if Wx.burn_pct(t) < 100:
		out.append("Fires already burning go out twice as fast.")
	var sp := Wx.spread_pct(t)
	if sp > 0:
		out.append("Arrows, bullets and shot scatter %s more." % frac(sp))
	if sm > 0:
		out.append("You see %s as far (%d m); nobody shoots beyond sight." % ["half" if Wx.sight_pct(t) == 50 else "three quarters", sm])
	if t[Wx.T_MUD] != 0:
		out.append("Mud slows foot %s, horse %s, guns, wagons and the ram %s." % [frac(100 - Wx.WX_MUD[Wx.CAT_FOOT]),
			frac(100 - Wx.WX_MUD[Wx.CAT_HORSE]), frac(100 - Wx.WX_MUD[Wx.CAT_GUN])])
		out.append("Charges hit %s softer in the mud." % frac(100 - Wx.WX_MUD_CHARGE))
	if t[Wx.T_COVER] != 0:
		out.append("Snow on the ground slows foot and horse %s, guns, wagons and the ram %s." % [frac(100 - Wx.WX_COVER[Wx.CAT_FOOT]),
			frac(100 - Wx.WX_COVER[Wx.CAT_GUN])])
	out.append("No effect on morale or melee.")
	return out


## One line: the name and the rules in short ("Downpour, muddy ground: guns reload a third slower, no fire arrows, ...").
static func short_line(w: String, sea := false) -> String:
	var t := Wx.tiers(w)
	var parts := PackedStringArray()
	if not Wx.any(t):
		return rule_title(w) + ": no effect on the battle"
	var rl := Wx.reload_pct(t)
	if rl > 0:
		parts.append("guns reload %s slower" % frac(rl))
	var sm := Wx.sight_m(t)
	if not sea:
		if not Wx.fire_ok(t):
			parts.append("no fire arrows")
		var sp := Wx.spread_pct(t)
		if sp > 0:
			parts.append("missiles scatter %s more" % frac(sp))
	if sm > 0:
		parts.append("sight %d m" % sm)
	if not sea:
		if t[Wx.T_MUD] != 0:
			parts.append("mud slows the march")
		elif t[Wx.T_COVER] != 0:
			parts.append("snow slows the march")
	if parts.is_empty():
		return rule_title(w) + ": no effect on the battle"
	return rule_title(w) + ": " + ", ".join(parts)


## The how-to book's Weather page (game/campaign/howto.gd "weather_1" .. "weather_4"): the full table in words.
static func howto_line(k: int) -> String:
	var tiers3 := func(tbl: Array, base: int) -> String:
		return "%s, %s, %s" % [frac(absi(int(tbl[1]) - base)), frac(absi(int(tbl[2]) - base)), frac(absi(int(tbl[3]) - base))]
	var sm := func(pct: int) -> int:
		return Wx.WX_SIGHT_M * pct / 100
	match k:
		1:
			return "The weather is a rule in battle. The chip by the battle's clock shows it: tap it for every rule in force; the deployment bar repeats them, and a campaign battle's card gives the forecast before you choose Fight or Auto-resolve. Weather never touches morale, melee, armour or hit points, and an overcast sky or the season only changes the colours."
		2:
			return "Rain fouls the powder: muskets, pistols and guns reload %s slower in drizzle, rain and a downpour or thunderstorm, and every missile scatters %s more. From rain on, fire arrows and fire pots cannot be lit (they shoot plain shot), fires burn out twice as fast and the ground turns to mud; a downpour or a storm also cuts sight to %d m." % [
				tiers3.call(Wx.WX_RL_RAIN, 0), tiers3.call(Wx.WX_SPR_RAIN, 0), sm.call(Wx.WX_SIGHT_RAIN[3])]
		3:
			return "Snow: powder reloads %s slower in light snow, snow and a blizzard, and missiles scatter %s more. In snow you see %d m, in a blizzard %d m, and in a blizzard nothing burning can be lit. Snow on the ground slows foot and horse %s, guns, wagons and the ram %s." % [
				tiers3.call(Wx.WX_RL_SNOW, 0), tiers3.call(Wx.WX_SPR_SNOW, 0), sm.call(Wx.WX_SIGHT_SNOW[2]), sm.call(Wx.WX_SIGHT_SNOW[3]),
				frac(100 - Wx.WX_COVER[Wx.CAT_FOOT]), frac(100 - Wx.WX_COVER[Wx.CAT_GUN])]
		4:
			return "Fog: you see half as far (%d m) and missiles scatter %s more. Nobody shoots beyond what he can see, so the guns' long reach is lost in fog, snow and a downpour. Mud slows foot %s, horse %s, guns, wagons and the ram %s, and charges hit %s softer. At sea the ships' guns reload slower in rain and snow and fire no further than the lookouts see; the wind blows as it always did." % [
				sm.call(Wx.WX_SIGHT_FOG), frac(Wx.WX_SPR_FOG), frac(100 - Wx.WX_MUD[Wx.CAT_FOOT]), frac(100 - Wx.WX_MUD[Wx.CAT_HORSE]),
				frac(100 - Wx.WX_MUD[Wx.CAT_GUN]), frac(100 - Wx.WX_MUD_CHARGE)]
	return ""
