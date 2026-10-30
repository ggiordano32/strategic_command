extends RefCounted
## The table's motion (tabletop pass 5, docs/design/art_pipeline.md "Pass 5, furniture and motion"; view only): the dive onto
## the table as a battle opens (game/battle.gd) and the die that rolls on an auto-resolve (game/campaign/battle_screen.gd).
## One setting for both, user://settings.cfg [video] battle_dive = on | off (default on; "--no-dive" turns it off for the
## session). Tests and the screenshot / benchmark aids never see the motion: a battle dives only when the screen that opens it
## says so (Battle.dive) and none of the aids below is on the command line.

const SETTINGS := "user://settings.cfg"
## Command-line aids that frame the camera, take shots or measure frames: with any of them there is no dive.
const AIDS := ["--shot", "--frame-stats", "--skip-ticks", "--zoom", "--cam", "--cam-unit", "--select", "--pause", "--no-dive"]


static func enabled() -> bool:
	if "--no-dive" in OS.get_cmdline_user_args():
		return false
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) != OK:
		return true
	return str(cf.get_value("video", "battle_dive", "on")) != "off"


static func save_pref(on: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("video", "battle_dive", "on" if on else "off")
	cf.save(SETTINGS)


## Tests set this to see the motion (they run as scripts, with no current scene, and get none otherwise).
static var force := false


## Whether a screen may play the table's motion now: the setting is on, the game is the running scene (not a test script) and no
## command-line aid is on.
static func allowed() -> bool:
	if not enabled():
		return false
	if force:
		return true
	var tree := Engine.get_main_loop() as SceneTree
	return tree != null and tree.current_scene != null and not aids_present()


## True when a command-line aid is present (they get no motion).
static func aids_present() -> bool:
	for a in OS.get_cmdline_user_args():
		var k := str(a).get_slice("=", 0)
		if k in AIDS:
			return true
	return false


## The ease-out of the dive: 0 at the start, 1 at the end, fast first.
static func ease_out(t: float) -> float:
	var q := 1.0 - clampf(t, 0.0, 1.0)
	return 1.0 - q * q * q
