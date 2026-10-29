extends RefCounted
## First-time tips (docs/design/campaign_rules.md "The tutorial", part 2): the first time the player selects an army,
## opens a town, lays a siege, enters a deployment, meets a chip, boards a fleet, gets a proposal or wins a battle, one
## sentence (howto.gd) in a toast with a "Got it". Remembered per device in user://tips.cfg, reset from Options ("Show
## the tips again"). No gate, no pointer. The screen showing tips registers a presenter (Callable(text, key)); with
## none (a headless run, a menu) a tip is not shown and not used up. Test runs (tests/*.gd, Saves' test folder rule)
## keep their file in the tests folder, never in the real user folder. View only.

const Howto := preload("res://game/campaign/howto.gd")
const Saves := preload("res://game/campaign/saves.gd")

const FILE := "user://tips.cfg"

## Set by the screen that can show a toast: func(text: String, key: String). Cleared by it on leaving.
static var presenter := Callable()
## The guided first campaign's cards say the same things: its tips wait.
static var suppress := false
static var shown_log: Array[String] = []   # the keys shown this run (tests read it)
## Scripted test runs (tests/*.gd, tools/*.gd) show no tips, so a toast that came late never covers a toast a test waits
## for and the result does not depend on what an earlier run remembered; tests/tutorial_test.gd turns them on.
static var in_tests := false
static var _test_run := -1


static func path() -> String:
	Saves.dir()   # (decides the test folder)
	if Saves.subdir != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Saves.DIR + Saves.subdir))
		return Saves.DIR + Saves.subdir + "tips.cfg"
	return FILE


static func seen(key: String) -> bool:
	var cf := ConfigFile.new()
	if cf.load(path()) != OK:
		return false
	return int(cf.get_value("seen", key, 0)) != 0


static func mark(key: String) -> void:
	var cf := ConfigFile.new()
	cf.load(path())
	cf.set_value("seen", key, 1)
	cf.save(path())


## Forget every tip (Options: Show the tips again).
static func reset() -> void:
	var p := path()
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	shown_log.clear()


static func count_seen() -> int:
	var n := 0
	for k in Howto.TIP_KEYS:
		if seen(k):
			n += 1
	return n


## Show the tip `key` if it was never shown on this device and a screen can show it. True when shown.
static func show(key: String) -> bool:
	if _test_run < 0:
		_test_run = 1 if Saves._test_run() else 0
	if suppress or not presenter.is_valid() or (_test_run == 1 and not in_tests) or seen(key):
		return false
	var text := Howto.tip(key)
	if text == "":
		return false
	mark(key)
	shown_log.append(key)
	presenter.call(text, key)
	return true
