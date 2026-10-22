extends RefCounted
## The title menu's view settings (user://settings.cfg [menu]) and its testing aids. View only.
##   background = diorama | art | auto   (auto: diorama on High graphics, art on Low)
##   emblems    = drawn | painted         (painted falls back to drawn when the PNG is missing)
## Aids: --menu-bg=diorama|art|auto and --menu-emblems=drawn|painted force one for the session;
## --dev (or ?dev on the web) shows the Tests and benchmarks entries in Options.

const Quality := preload("res://game/quality.gd")
const Saves := preload("res://game/campaign/saves.gd")
const SETTINGS := "user://settings.cfg"
const BACKGROUNDS: Array[String] = ["auto", "diorama", "art"]
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


static func _cfg_get(key: String, def: String, allowed: Array[String]) -> String:
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


## The setting: auto / diorama / art.
static func background_pref() -> String:
	if BACKGROUNDS.has(bg_override):
		return bg_override
	var o := _aid("--menu-bg=")
	if BACKGROUNDS.has(o):
		return o
	if Saves._test_run():
		return "art"   # (a test run never builds the live map behind a menu it did not ask about: it switches the content pack)
	return _cfg_get("background", "auto", BACKGROUNDS)


## The saved choice, whatever an aid or a test forces.
static func stored_background() -> String:
	return _cfg_get("background", "auto", BACKGROUNDS)


static func stored_emblems() -> String:
	return _cfg_get("emblems", "drawn", EMBLEMS)


static func set_background(v: String) -> void:
	_cfg_set("background", v)


## The background in force: diorama or art.
static func background() -> String:
	var p := background_pref()
	if p == "auto":
		return "art" if Quality.is_low() else "diorama"
	return p


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
