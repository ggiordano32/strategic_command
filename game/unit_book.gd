extends Control
## The unit book: a full-screen overlay listing every unit type, with one
## UnitEntry page shown at a time (list on the left, Previous / Next, Close).
## Used from the start menu and from the battle HUD; it only emits `closed`
## and never touches the sim.

signal closed

const UT := preload("res://sim/unit_types.gd")
const Icons := preload("res://game/unit_icons.gd")
const IconView := preload("res://game/unit_icon_view.gd")
const UnitEntry := preload("res://game/unit_entry.gd")

var entry: UnitEntry
var current := 0
var side_color := Color(0.35, 0.6, 1.0)
var _list: Array[Button] = []
var prev_button: Button
var next_button: Button
var close_button: Button


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.1, 1.0)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 10
	panel.offset_top = 10
	panel.offset_right = -10
	panel.offset_bottom = -10
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	# Unit list.
	var lscroll := ScrollContainer.new()
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lscroll.custom_minimum_size = Vector2(210, 0)
	row.add_child(lscroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	lscroll.add_child(list)
	for ty in UT.count():
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 56)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "            " + str(UT.TYPES[ty]["name"])
		b.add_theme_font_size_override("font_size", 16)
		var ic := IconView.new(Icons.icon_of(ty), side_color, 40.0)
		ic.position = Vector2(8, 8)
		b.add_child(ic)
		b.pressed.connect(show_type.bind(ty))
		list.add_child(b)
		_list.append(b)
	# Page with its header.
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 8)
	row.add_child(page)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	page.add_child(head)
	var title := Label.new()
	title.text = "Unit book"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	prev_button = _button("< Prev")
	prev_button.pressed.connect(func(): show_type((current + UT.count() - 1) % UT.count()))
	head.add_child(prev_button)
	next_button = _button("Next >")
	next_button.pressed.connect(func(): show_type((current + 1) % UT.count()))
	head.add_child(next_button)
	close_button = _button("Close")
	close_button.pressed.connect(close)
	head.add_child(close_button)
	entry = UnitEntry.new()
	page.add_child(entry)


func open(ty: int = -1) -> void:
	visible = true
	show_type(current if ty < 0 else ty)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func show_type(ty: int) -> void:
	current = clampi(ty, 0, UT.count() - 1)
	for k in _list.size():
		_list[k].set_pressed_no_signal(k == current)
	entry.set_unit_type(current, side_color)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				close()
			KEY_LEFT, KEY_UP:
				show_type((current + UT.count() - 1) % UT.count())
			KEY_RIGHT, KEY_DOWN:
				show_type((current + 1) % UT.count())
		get_viewport().set_input_as_handled()


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 54)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	return b
