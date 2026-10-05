extends Control
## Start screen: pick a scenario, then hand over to the battle view.

const Scenarios := preload("res://sim/scenarios.gd")
const Battle := preload("res://game/battle.gd")

var _menu: Control
var _battle: Node = null
var _speed_idx := 1
var _rotate_hint: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu = _build_menu()
	add_child(_menu)
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
	# Shortcuts for testing: command line "-- --scenario=bench_2000 --speed=3",
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
	vb.add_theme_constant_override("separation", 12)
	center.add_child(vb)
	var title := Label.new()
	title.text = "Strategic Command: battle sandbox"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var info := Label.new()
	info.text = "Godot %s, %s renderer" % [Engine.get_version_info()["string"],
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")]
	info.add_theme_font_size_override("font_size", 14)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(info)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)
	for id in Scenarios.IDS:
		grid.add_child(_menu_button(Scenarios.title(id), _start.bind(id)))
	grid.add_child(_menu_button("Toggle fullscreen", _toggle_fullscreen))
	var help := Label.new()
	help.text = "Tap a unit or its card to select. Drag to draw the front line (length = width).\nTap ground to move, tap an enemy to attack, double tap to run.\nTwo fingers (or right drag / wheel) pan and zoom."
	help.add_theme_font_size_override("font_size", 15)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(1, 1, 1, 0.75)
	vb.add_child(help)
	return bg


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 64)
	b.add_theme_font_size_override("font_size", 20)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


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


func _start(id: String) -> void:
	if _battle != null:
		return
	_menu.visible = false
	var b := Battle.new()
	b.scenario_id = id
	# Benchmarks use a fixed seed so runs on different devices are comparable.
	b.seed_value = 42 if id.begins_with("bench") else int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	b.speed_idx = clampi(_speed_idx, 0, Battle.SPEEDS.size() - 1)
	b.exit_requested.connect(_end_battle)
	_battle = b
	get_tree().root.add_child.call_deferred(b)


func _end_battle() -> void:
	if _battle != null:
		_battle.queue_free()
		_battle = null
	_menu.visible = true
