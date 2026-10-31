extends RefCounted
## The title menu's view settings (user://settings.cfg [menu]) and its testing aids. View only.
##   background = diorama_west | diorama_rome   (the title screen's selector: the live table of the Caribbean or of
##                Rome; the retired values art_west / art_rome and the old art / auto / diorama are migrated to the
##                diorama of their setting, or of the last-played one)
##   emblems    = drawn | painted         (painted falls back to drawn when the PNG is missing)
## Aids: --menu-bg=<one of the two> (or an old value) and --menu-emblems=drawn|painted force one for the session;
## --dev (or ?dev on the web) shows the Tests and benchmarks entries in Options.

const Saves := preload("res://game/campaign/saves.gd")
const SETTINGS := "user://settings.cfg"
const BACKGROUNDS: Array[String] = ["diorama_west", "diorama_rome"]
const LEGACY: Array[String] = ["auto", "art", "diorama", "art_west", "art_rome"]
const LABELS := {"diorama_west": "The Caribbean, the map table", "diorama_rome": "Rome, the relief map"}
## What shows while the table builds (and where it cannot: a test run, a device that fails to build it) and behind
## the loading panel: a dark vertical gradient (top, bottom) in the table's colours, a warm wood for the West and a
## cooler stone for Rome. No picture file.
const PLACEHOLDER := {"west": [Color(0.09, 0.055, 0.03), Color(0.21, 0.13, 0.065)], "rome": [Color(0.085, 0.095, 0.11), Color(0.2, 0.21, 0.22)]}
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


## Always "diorama" (the painted pictures are retired).
static func kind(_c: String) -> String:
	return "diorama"


## "west" or "rome".
static func pack_of(c: String) -> String:
	return c.get_slice("_", 1)


## Any stored / aid value as one of the two; the retired art_<pack> takes its own setting, the old values (art, auto,
## diorama) and junk the given one.
static func normalize(v: String, pack: String) -> String:
	if BACKGROUNDS.has(v):
		return v
	if v == "art_west" or v == "art_rome":
		return "diorama_" + v.get_slice("_", 1)
	var p := pack if pack == "west" or pack == "rome" else "rome"
	return "diorama_" + p


## The choice in force: a test's override, a command-line aid, else the saved one (first run: the table of `pack`,
## the last-played setting).
static func background_pref(pack: String) -> String:
	if bg_override != "":
		return normalize(bg_override, pack)
	var o := _aid("--menu-bg=")
	if BACKGROUNDS.has(o) or LEGACY.has(o):
		return normalize(o, pack)
	return stored_background(pack)


## Whether the live table is not built: a test run that did not ask for one (an override or an aid), since building
## it switches the content pack; the placeholder gradient shows instead.
static func skip_live() -> bool:
	return Saves._test_run() and bg_override == "" and _aid("--menu-bg=") == ""


## The saved choice, whatever an aid or a test forces.
static func stored_background(pack: String) -> String:
	return normalize(_cfg_get("background", "", BACKGROUNDS + LEGACY), pack)


## Rewrite an old saved value as one of the two.
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
