extends RefCounted
## Graphics quality (2026-10-13), a view preference in user://settings.cfg
## [video] quality = auto | high | low ("--quality=high|low|auto" overrides it
## for the session). Auto is Low when the soldier probe chose the CPU path (the
## Chrome-on-tablet case: soldiers = cpu) or when the first seconds of a battle
## averaged under AUTO_FPS (terrain_layer.gd measures; the downgrade lasts for
## the session only). View only: nothing here touches the sim.

const SoldierLayer := preload("res://game/soldier_layer.gd")
const SETTINGS := "user://settings.cfg"
const AUTO_FPS := 40.0
const MEASURE_S := 3.0
static var session_low := false   # the auto downgrade, for this run only


static func _launch_override() -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--quality="):
			var v := str(a).get_slice("=", 1).to_lower()
			if v == "high" or v == "low" or v == "auto":
				return v
	return ""


## The setting: auto / high / low.
static func load_pref() -> String:
	var o := _launch_override()
	if o != "":
		return o
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) != OK:
		return "auto"
	var v := str(cf.get_value("video", "quality", "auto"))
	return v if v == "high" or v == "low" else "auto"


static func save_pref(v: String) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("video", "quality", v)
	cf.save(SETTINGS)
	session_low = false


## True when the cheap view is in force.
static func is_low() -> bool:
	var p := load_pref()
	if p == "low":
		return true
	if p == "high":
		return false
	if session_low:
		return true
	var f := SoldierLayer.forced_path()
	return f == "cpu" or (f == "" and SoldierLayer.load_pref() == "cpu")
