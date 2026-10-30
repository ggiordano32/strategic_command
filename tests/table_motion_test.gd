extends SceneTree
## The table's motion (tabletop pass 5; needs a window):
##   godot --path . --resolution 1280x720 -s tests/table_motion_test.gd [-- --shots=DIR]
## The die on an auto-resolve (game/campaign/die_roll.gd): each result maps to its face (a laurel, a broken shield, crossed
## swords), the faces shown on the way end on the result for every result and no two in a row are alike, the die settles
## once, a skip settles it at once, and it draws without script errors; --shots saves a strip of the roll. The dive onto the
## table (game/battle.gd): a battle opened with `dive` and the motion forced starts at 0.35 of the fit, ends at the fit
## (zoom and position) with its HUD whole, a key skips it, the sim does not step during it, and with `dive` off or the
## setting off there is none. The setting reads and writes [video] battle_dive (user://settings.cfg put back afterwards).

const Battle := preload("res://game/battle.gd")
const DieRoll := preload("res://game/campaign/die_roll.gd")
const TableMotion := preload("res://game/table_motion.gd")
const UIIcons := preload("res://game/ui_icons.gd")
const SETTINGS := "user://settings.cfg"

var _ok := true
var _shots := ""
var _settings_bytes := PackedByteArray()
var _had_settings := false


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		_ok = false


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.get_slice("=", 1)
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	_had_settings = FileAccess.file_exists(SETTINGS)
	if _had_settings:
		_settings_bytes = FileAccess.get_file_as_bytes(SETTINGS)
	_run.call_deferred()


func _restore_settings() -> void:
	if _had_settings:
		var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
		f.store_buffer(_settings_bytes)
	elif FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _die_checks() -> void:
	_check(DieRoll.face_of("win") == "victory" and DieRoll.face_of("loss") == "broken_shield" and DieRoll.face_of("draw") == "battles",
		"a win is a laurel, a loss a broken shield, a draw crossed swords")
	_check(UIIcons.has("victory") and UIIcons.has("broken_shield") and UIIcons.has("battles"), "the three faces are game icons")
	for r in ["win", "loss", "draw"]:
		var d := DieRoll.new()
		d.setup(r)
		_check(d.face_at(DieRoll.FLIPS) == DieRoll.face_of(r) and d.face_at(DieRoll.FLIPS + 3) == DieRoll.face_of(r), "%s: the roll ends on its face" % r)
		var alike := false
		for k in DieRoll.FLIPS:
			if d.face_at(k) == d.face_at(k + 1):
				alike = true
		_check(not alike, "%s: no two faces alike in a row" % r)
		d.free()
	# One die in a card: settles once, after the roll and the hold; a skip settles at once.
	var host := Control.new()
	host.size = Vector2(420, 120)
	root.add_child(host)
	var d1 := DieRoll.new()
	d1.setup("loss")
	host.add_child(d1)
	d1.size = Vector2(420, 92)
	var n := [0]
	d1.settled.connect(func(): n[0] += 1)
	var shot_at := [0.05, 0.15, 0.3, 0.45, 0.6, 0.75, 1.0]
	var si := 0
	var t0 := Time.get_ticks_msec()
	while not d1.done and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
		if _shots != "" and si < shot_at.size() and d1.t >= shot_at[si]:
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png("%s/die_%d.png" % [_shots, si])
			si += 1
	_check(d1.done and n[0] == 1, "the die settles once")
	d1.skip()
	_check(n[0] == 1, "a skip after settling does nothing more")
	var d2 := DieRoll.new()
	d2.setup("win")
	host.add_child(d2)
	d2.size = Vector2(420, 92)
	var n2 := [0]
	d2.settled.connect(func(): n2[0] += 1)
	d2.skip()
	_check(d2.done and n2[0] == 1, "a skip settles it at once")
	host.queue_free()


func _dive_checks() -> void:
	TableMotion.force = true
	var b := Battle.new()
	b.scenario_id = "skirmish"
	b.seed_value = 7
	b.dive = true
	root.add_child(b)
	await _frames(3)
	_check(b.dive_t >= 0.0 and b.dive_t < Battle.DIVE_SEC, "the battle opens diving (t %.2f)" % b.dive_t)
	var z1: float = b._dive_z1
	var p1: Vector2 = b._dive_p1
	_check(absf(b._dive_z0 - z1 * Battle.DIVE_START) < 1e-6, "it starts at %.2f of the fit" % Battle.DIVE_START)
	var tick0: int = b.sim.tick
	await _frames(6)
	_check(b.sim.tick == tick0, "the sim does not step during the dive")
	_check(b.camera.zoom.x < z1 and b.camera.zoom.x > b._dive_z0 * 0.999, "the camera zoom is between the start and the fit (%.3f)" % b.camera.zoom.x)
	var mod: CanvasModulate = b._dive_mod
	_check(mod != null and mod.color.a < 1.0, "the HUD is not yet whole")
	var t1 := Time.get_ticks_msec()
	while b.dive_t >= 0.0 and Time.get_ticks_msec() - t1 < 8000:
		await process_frame
	_check(b.dive_t < 0.0, "the dive ends by itself")
	_check(absf(b.camera.zoom.x - z1) < 1e-6 and b.camera.position.is_equal_approx(p1), "it ends at the fit (zoom %.3f)" % z1)
	_check(b._dive_mod == null, "the HUD's fade is gone")
	b.queue_free()
	await _frames(2)
	# A key skips it.
	var c := Battle.new()
	c.scenario_id = "skirmish"
	c.seed_value = 7
	c.dive = true
	root.add_child(c)
	await _frames(3)
	var zz: float = c._dive_z1
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	_check(c.dive_t < 0.0 and absf(c.camera.zoom.x - zz) < 1e-6, "a key skips the dive to the fit")
	c.queue_free()
	await _frames(2)
	# No dive with `dive` off, or with the setting off, or with a command-line aid (those are not testable here).
	var d := Battle.new()
	d.scenario_id = "skirmish"
	d.seed_value = 7
	root.add_child(d)
	await _frames(3)
	_check(d.dive_t < 0.0, "no dive unless the screen asked for it")
	d.queue_free()
	await _frames(2)
	TableMotion.save_pref(false)
	_check(not TableMotion.enabled(), "the setting off reads off")
	var e := Battle.new()
	e.scenario_id = "skirmish"
	e.seed_value = 7
	e.dive = true
	root.add_child(e)
	await _frames(3)
	_check(e.dive_t < 0.0, "no dive with the setting off")
	e.queue_free()
	TableMotion.save_pref(true)
	_check(TableMotion.enabled(), "the setting on reads on")
	TableMotion.force = false
	_check(not TableMotion.allowed(), "a test script gets no motion unless it forces it")


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await _die_checks()
	await _dive_checks()
	_restore_settings()
	print("RESULT table_motion_test ", "OK" if _ok else "FAILED")
	quit(0 if _ok else 1)
