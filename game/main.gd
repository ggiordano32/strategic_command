extends Control
## Start screen: pick a scenario, then hand over to the battle view.

const Scenarios := preload("res://sim/scenarios.gd")
const Battle := preload("res://game/battle.gd")
const UnitBook := preload("res://game/unit_book.gd")
const Terrain := preload("res://sim/terrain.gd")
const UiScale := preload("res://game/ui_scale.gd")
## Menu terrain choices for the playable battles: -1 = random from the seed.
const TERRAIN_CHOICES := [-1, Terrain.K_FLAT, Terrain.K_ROLLING, Terrain.K_RIDGE,
	Terrain.K_VALLEY, Terrain.K_HILL, Terrain.K_SLOPE]

var _menu: Control
var _battle: Node = null
var _speed_idx := 1
var _seed := -1
var _terrain_idx := 0
var _terrain_button: Button
var _replay_button: Button
## Last battle started from the menu: replayed with the same seed and terrain.
var _last_id := ""
var _last_seed := -1
var _last_terrain := -1
var _rotate_hint: Label
var book: UnitBook


var _shot_path := ""
var _shot_frames := 0
var _tests_box: Control
var _tests_button: Button
var _help: Label
var _size_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# UI size from the device (and the player's S / M / L choice).
	UiScale.apply(get_window())
	get_tree().root.size_changed.connect(func(): UiScale.apply(get_window()))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			# Testing aid: save the window as a PNG after --shot-frames frames
			# (default 30), then quit.
			_shot_path = a.get_slice("=", 1)
			if _shot_frames == 0:
				_shot_frames = 30
		elif a.begins_with("--shot-frames="):
			_shot_frames = int(a.get_slice("=", 1))
	_menu = _build_menu()
	add_child(_menu)
	book = UnitBook.new()
	add_child(book)
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_rotate_hint = Label.new()
	_rotate_hint.text = "Rotate your phone to landscape"
	_rotate_hint.add_theme_font_size_override("font_size", 28)
	_rotate_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_rotate_hint.add_theme_constant_override("outline_size", 8)
	_rotate_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_rotate_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_rotate_hint.grow_vertical = Control.GROW_DIRECTION_BOTH
	_rotate_hint.visible = false
	layer.add_child(_rotate_hint)
	# Shortcuts for testing: command line "-- --scenario=bench_2000 --speed=3"
	# (--seed=N fixes the seed),
	# or on the web a URL query "?scenario=bench_2000&speed=3".
	var args := Array(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String and q.length() > 1:
			for kv in (q as String).substr(1).split("&"):
				args.append("--" + kv)
	for a in args:
		if a.begins_with("--speed="):
			_speed_idx = int(a.get_slice("=", 1))
		elif a.begins_with("--seed="):
			_seed = int(a.get_slice("=", 1))  # testing aid: fixed seed
		elif a.begins_with("--terrain="):
			# Terrain for the playable battles: a kind name or number
			# (flat, rolling, ridge, valley, hill, slope; random).
			var v: String = str(a).get_slice("=", 1).to_lower()
			for k in TERRAIN_CHOICES.size():
				var kind: int = TERRAIN_CHOICES[k]
				var nm := "random" if kind < 0 else Terrain.KIND_NAMES[kind].to_lower()
				if v == nm or v == str(kind):
					_terrain_idx = k
			_update_terrain_button()
	for a in args:
		if a == "--menu-tests":
			_toggle_tests()  # testing aid: open the Tests section
		if a.begins_with("--book="):
			book.open(int(a.get_slice("=", 1)))  # testing aid: open a page
		elif a.begins_with("--book-scroll="):
			book.entry.set_deferred("scroll_vertical", int(a.get_slice("=", 1)))
	for a in args:
		if a.begins_with("--scenario="):
			_start(a.get_slice("=", 1))


func _build_menu() -> Control:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.15, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(center)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	center.add_child(vb)
	var title := Label.new()
	title.text = "Strategic Command: battle sandbox"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var info := Label.new()
	info.text = "Godot %s, %s renderer" % [Engine.get_version_info()["string"],
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")]
	info.add_theme_font_size_override("font_size", 12)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(info)
	# Battles.
	var battles := HBoxContainer.new()
	battles.add_theme_constant_override("separation", 8)
	battles.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(battles)
	for id in Scenarios.PLAYABLE:
		var b := _menu_button(Scenarios.title(id), _start.bind(id))
		b.custom_minimum_size = Vector2(250, 48)
		b.add_theme_font_size_override("font_size", 16)
		battles.add_child(b)
	# Options.
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	_terrain_button = _menu_button("", _cycle_terrain)
	_terrain_button.tooltip_text = "Ground for the three battles (tests have their own)"
	row.add_child(_terrain_button)
	_replay_button = _menu_button("Replay last battle", _replay)
	_replay_button.tooltip_text = "Same battle, same seed, same ground"
	_replay_button.disabled = true
	row.add_child(_replay_button)
	row.add_child(_menu_button("Unit book", _open_book))
	_size_button = _menu_button("", _cycle_ui_size)
	_size_button.tooltip_text = "Size of buttons and text (S / M / L)"
	row.add_child(_size_button)
	row.add_child(_menu_button("Fullscreen", _toggle_fullscreen))
	_tests_button = _menu_button("Tests and benchmarks  +", _toggle_tests)
	row.add_child(_tests_button)
	_update_terrain_button()
	_update_size_button()
	# Tests and benchmarks, folded away by default.
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	grid.visible = false
	vb.add_child(grid)
	for id in Scenarios.IDS:
		if id in Scenarios.PLAYABLE:
			continue
		var tb := _menu_button(Scenarios.title(id).trim_prefix("Test: ").replace("AI vs AI benchmark", "AI benchmark"), _start.bind(id))
		tb.custom_minimum_size = Vector2(205, 36)
		tb.add_theme_font_size_override("font_size", 13)
		tb.clip_text = true
		tb.tooltip_text = Scenarios.title(id)
		grid.add_child(tb)
	_tests_box = grid
	var help := Label.new()
	help.text = "Tap a unit or its card to select; All / Inf / Missile / Cav select groups, + Add adds by tapping cards.\nDrag to draw the front line. Tap ground to move, tap an enemy to attack (missile troops and artillery\nshoot it), double tap to run. Contour lines are 2 m apart: high ground helps. Long press a card: unit book."
	help.add_theme_font_size_override("font_size", 13)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(1, 1, 1, 0.75)
	vb.add_child(help)
	_help = help
	return bg


func _toggle_tests() -> void:
	_tests_box.visible = not _tests_box.visible
	_help.visible = not _tests_box.visible
	_tests_button.text = "Tests and benchmarks  " + ("-" if _tests_box.visible else "+")


func _cycle_ui_size() -> void:
	UiScale.cycle_size(get_window())
	_update_size_button()


func _update_size_button() -> void:
	if _size_button != null:
		_size_button.text = "UI size: " + UiScale.size_name()


func _cycle_terrain() -> void:
	_terrain_idx = (_terrain_idx + 1) % TERRAIN_CHOICES.size()
	_update_terrain_button()


func _update_terrain_button() -> void:
	if _terrain_button == null:
		return
	var kind: int = TERRAIN_CHOICES[_terrain_idx]
	_terrain_button.text = "Terrain: " + ("random" if kind < 0 else Terrain.KIND_NAMES[kind].to_lower())


func _replay() -> void:
	if _last_id == "":
		return
	_start_with(_last_id, _last_seed, _last_terrain)


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 42)
	b.add_theme_font_size_override("font_size", 15)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _open_book() -> void:
	var tele := get_node_or_null("/root/Telemetry")
	if tele != null:
		tele.event("book_open", {"from": "menu"})
	book.open()


func _toggle_fullscreen() -> void:
	# Works on desktop and Android browsers; iPhone Safari has no fullscreen
	# API for pages (use "Add to Home Screen" there instead).
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _process(_delta: float) -> void:
	var sz := get_viewport().get_visible_rect().size
	_rotate_hint.visible = sz.y > sz.x
	if _shot_path != "":
		_shot_frames -= 1
		if _shot_frames <= 0:
			var img := get_viewport().get_texture().get_image()
			img.save_png(_shot_path)
			print("saved ", _shot_path, " ", img.get_size(), " logical ", get_viewport().get_visible_rect().size)
			_shot_path = ""
			get_tree().quit()


func _start(id: String) -> void:
	# Benchmarks use a fixed seed so runs on different devices are comparable.
	var sd := 42 if id.begins_with("bench") else int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	if _seed >= 0:
		sd = _seed
	_start_with(id, sd, TERRAIN_CHOICES[_terrain_idx])


func _start_with(id: String, sd: int, terrain_kind: int) -> void:
	if _battle != null:
		return
	_menu.visible = false
	var b := Battle.new()
	b.scenario_id = id
	b.seed_value = sd
	b.terrain_kind = terrain_kind
	_last_id = id
	_last_seed = sd
	_last_terrain = terrain_kind
	_replay_button.disabled = false
	_replay_button.text = "Replay (seed %d)" % sd
	b.speed_idx = clampi(_speed_idx, 0, Battle.SPEEDS.size() - 1)
	b.exit_requested.connect(_end_battle)
	_battle = b
	get_tree().root.add_child.call_deferred(b)


func _end_battle() -> void:
	if _battle != null:
		_battle.queue_free()
		_battle = null
	_menu.visible = true
