extends SceneTree
## The battle's loading bar (docs/design/ui.md "The battle's loading bar"), view only:
##   godot --headless --script res://tests/battle_loading_test.gd
## A Battle built with `staged` runs its setup a step a frame under the loading plate (game/battle_loading.gd): not playable
## and not taking input until the last step, the plate (title, bar, phase) over it, the bar rising with the steps, the plate
## never shown for a load under its delay, then gone; the sim it builds is the one the unstaged setup builds (same state hash
## from the same seed: the setup's order and determinism are unchanged); an unstaged Battle (every other test) is ready
## synchronously as before; the plate fits the phone sizes (393 x 851 and 844 x 390 windows at the project's logical size).

const Battle := preload("res://game/battle.gd")
const BattleLoading := preload("res://game/battle_loading.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")

var _ok := true


func _check(c: bool, msg: String) -> void:
	if not c:
		_ok = false
		printerr("FAIL " + msg)
	else:
		print("ok   " + msg)


func _scn() -> Dictionary:
	return {"width_m": 300, "height_m": 300, "ai_sides": [], "units": [
		Scenarios.unit(0, UT.index_of("heavy"), 60, 150, 200, 768),
		Scenarios.unit(1, UT.index_of("heavy"), 60, 150, 130, 256)]}


func _init() -> void:
	await process_frame   # (the tree runs)
	# unstaged: ready at once, no plate
	var a := Battle.new()
	a.custom_scenario = _scn()
	a.seed_value = 7
	root.add_child(a)
	_check(a.loaded and a.sim != null and a.loading == null, "an unstaged battle is ready synchronously, with no plate")
	var h_a: int = a.sim.state_hash()
	var steps_a: int = a.load_timings.size()
	a.queue_free()
	await process_frame

	# staged: not ready until the steps have run, the plate up meanwhile
	var b := Battle.new()
	b.custom_scenario = _scn()
	b.seed_value = 7
	b.staged = true
	b.tap_msec = Time.get_ticks_msec()
	root.add_child(b)
	await process_frame
	_check(not b.loaded, "a staged battle is not ready on its first frame")
	_check(b.loading != null and b.loading.plate != null, "the loading plate is up")
	var plate: PanelContainer = b.loading.plate
	_check(b.loading.cover.mouse_filter == Control.MOUSE_FILTER_STOP, "the cover takes taps (nothing under it is touchable)")
	_check(plate.modulate.a < 0.05, "the plate has not shown yet (a fast load never flashes it)")
	var fr0: float = b.loading.bar.value
	var phases := {}
	var rose := true
	var last := -1.0
	var n := 0
	while not b.loaded and n < 600:
		phases[b.loading.phase_label.text] = true
		if b.loading.bar.value < last - 0.0001:
			rose = false
		last = b.loading.bar.value
		await process_frame
		n += 1
	_check(b.loaded and n < 600, "the staged setup finishes (%d frames)" % n)
	_check(rose and last > fr0, "the bar only rises (0 -> %.2f before the last step)" % last)
	_check(phases.size() >= 2, "the plate names the phases (%d seen)" % phases.size())
	_check(b.sim.state_hash() == h_a, "the staged battle's sim is the unstaged one (hash %08x)" % h_a)
	await process_frame
	await process_frame
	for i in 40:
		await process_frame
	_check(b.loading == null, "the plate is released at the first playable frame")
	_check(b.load_timings.size() >= steps_a and b.load_total_ms > 0.0, "its setup recorded its steps and the tap-to-frame time")
	b.queue_free()
	await process_frame

	# a slow load shows the plate; the hold aid (--load-hold) is a testing aid, here the plate's own clock
	var lp := BattleLoading.new()
	root.add_child(lp)
	lp.setup("Test battle", "west")
	lp.set_phase("Painting the board", 0.4)
	for i in 6:
		await process_frame
	_check(lp.plate.modulate.a < 0.2, "the plate stays clear before %.1f s" % BattleLoading.SHOW_SEC)
	lp.shown_for_test = true
	await process_frame
	await process_frame
	_check(is_equal_approx(lp.plate.modulate.a, 1.0), "the plate is at full alpha once shown")
	_check(lp.phase_label.text == "Painting the board...", "the phase line reads as given")
	_check(is_equal_approx(lp.bar.value, 0.4), "the bar shows the fraction given")
	# fit: the plate inside the viewport at the project's logical sizes of the two phone windows
	for sz in [Vector2i(800, 1732), Vector2i(1029, 475), Vector2i(800, 400)]:
		_check(lp.plate.size.x <= float(sz.x) and lp.plate.get_combined_minimum_size().y <= float(sz.y) * 0.5,
			"the plate (%d x %d) fits a %d x %d screen" % [lp.plate.size.x, lp.plate.size.y, sz.x, sz.y])
	lp.finish()
	for i in 30:
		await process_frame
	_check(not is_instance_valid(lp), "finish() lifts the plate")
	quit(0 if _ok else 1)
