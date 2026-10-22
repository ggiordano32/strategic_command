extends RefCounted
## The title menu's view settings (user://settings.cfg [menu]) and its testing aids. View only.
##   background = art_west | art_rome | diorama_west | diorama_rome   (the title screen's selector; the old values
##                art / auto / diorama are migrated to the picture / the diorama of the last-played setting)
##   emblems    = drawn | painted         (painted falls back to drawn when the PNG is missing)
## Aids: --menu-bg=<one of the four> (or an old value) and --menu-emblems=drawn|painted force one for the session;
## --dev (or ?dev on the web) shows the Tests and benchmarks entries in Options.

const Saves := preload("res://game/campaign/saves.gd")
const SETTINGS := "user://settings.cfg"
const BACKGROUNDS: Array[String] = ["art_west", "art_rome", "diorama_west", "diorama_rome"]
const LEGACY: Array[String] = ["auto", "art", "diorama"]
const LABELS := {"art_west": "The Caribbean, painted", "art_rome": "Rome, painted",
	"diorama_west": "The Caribbean, the map table", "diorama_rome": "Rome, the relief map"}
const EMBLEMS: Array[String] = ["drawn", "painted"]

## Set by tests to show the developer entries without a command line.
static var dev_override := false
## Set by tests: the background pref to use ("" = none).
static var bg_override := ""


static func _args() -> Array:
	var a := Array(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String and q.length() > 1:
			for kv in (q as String).substr(1).split("&"):
				a.append("--" + kv)
	return a


static func _aid(prefix: String) -> String:
	for a in _args():
		if str(a).begins_with(prefix):
			return str(a).get_slice("=", 1).to_lower()
	return ""


static func _cfg_get(key: String, def: String, allowed: Array) -> String:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) != OK:
		return def
	var v := str(cf.get_value("menu", key, def))
	return v if allowed.has(v) else def


static func _cfg_set(key: String, v: String) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("menu", key, v)
	cf.save(SETTINGS)


## "art" or "diorama".
static func kind(c: String) -> String:
	return c.get_slice("_", 0)


## "west" or "rome".
static func pack_of(c: String) -> String:
	return c.get_slice("_", 1)


## Any stored / aid value as one of the four; old values (art, auto, diorama) take the given setting.
static func normalize(v: String, pack: String) -> String:
	if BACKGROUNDS.has(v):
		return v
	var p := pack if pack == "west" or pack == "rome" else "rome"
	return ("diorama_" if v == "diorama" else "art_") + p


## The choice in force: a test's override, a command-line aid, else the saved one (first run: the picture of `pack`,
## the last-played setting).
static func background_pref(pack: String) -> String:
	if bg_override != "":
		return normalize(bg_override, pack)
	var o := _aid("--menu-bg=")
	if BACKGROUNDS.has(o) or LEGACY.has(o):
		return normalize(o, pack)
	if Saves._test_run():
		return normalize("art", pack)   # (a test run never builds the live map behind a menu it did not ask about: it switches the content pack)
	return stored_background(pack)


## The saved choice, whatever an aid or a test forces.
static func stored_background(pack: String) -> String:
	return normalize(_cfg_get("background", "", BACKGROUNDS + LEGACY), pack)


## Rewrite an old saved value as one of the four.
static func migrate(pack: String) -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK and cf.has_section_key("menu", "background") and not BACKGROUNDS.has(str(cf.get_value("menu", "background"))):
		set_background(normalize(str(cf.get_value("menu", "background")), pack))


static func stored_emblems() -> String:
	return _cfg_get("emblems", "drawn", EMBLEMS)


static func set_background(v: String) -> void:
	_cfg_set("background", v)


static func emblems_pref() -> String:
	var o := _aid("--menu-emblems=")
	if EMBLEMS.has(o):
		return o
	return _cfg_get("emblems", "drawn", EMBLEMS)


static func set_emblems(v: String) -> void:
	_cfg_set("emblems", v)


## --menu-pack=west|rome: the setting the menu treats as last played (a testing aid).
static func pack_aid() -> String:
	return _aid("--menu-pack=")


static func dev() -> bool:
	if dev_override:
		return true
	for a in _args():
		if a == "--dev":
			return true
	return false
