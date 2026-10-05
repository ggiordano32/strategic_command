extends CanvasLayer
## Screen-space UI: performance readout, pause/speed/menu buttons, unit cards
## along the bottom, and actions for the selected unit. It only emits signals;
## battle.gd turns them into sim orders or view changes.

signal card_pressed(unit: int)
signal pause_pressed
signal speed_pressed
signal menu_pressed
signal run_pressed
signal halt_pressed
signal orders_toggled(on: bool)

const BattleSim := preload("res://sim/battle_sim.gd")
const UT := preload("res://sim/unit_types.gd")

var stats_label: Label
var banner: Label
var pause_button: Button
var orders_button: Button
var speed_button: Button
var run_button: Button
var halt_button: Button
var cards_bar: PanelContainer
var cards_box: HBoxContainer
var bench_panel: PanelContainer
var bench_label: Label
var actions_box: VBoxContainer
var _cards: Dictionary = {}  # unit -> Button
var _ui_controls: Array[Control] = []


func build(sim, player_side: int, interactive: bool) -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Performance readout, top left.
	var stats_panel := PanelContainer.new()
	stats_panel.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.55)))
	stats_panel.position = Vector2(8, 8)
	stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stats_panel)
	stats_label = Label.new()
	stats_label.add_theme_font_size_override("font_size", 15)
	stats_label.text = "..."
	stats_panel.add_child(stats_label)

	# Buttons, top right.
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top.position = Vector2(-8, 8)
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)
	pause_button = _button("Pause", Vector2(110, 60))
	pause_button.pressed.connect(func(): pause_pressed.emit())
	speed_button = _button("1x", Vector2(80, 60))
	speed_button.pressed.connect(func(): speed_pressed.emit())
	var menu := _button("Menu", Vector2(90, 60))
	menu.pressed.connect(func(): menu_pressed.emit())
	orders_button = _button("Orders", Vector2(140, 60))
	orders_button.toggle_mode = true
	orders_button.tooltip_text = "Show where every unit is headed"
	orders_button.toggled.connect(func(on: bool):
		set_orders_text(on)
		orders_toggled.emit(on))
	top.add_child(orders_button)
	top.add_child(pause_button)
	top.add_child(speed_button)
	top.add_child(menu)
	_ui_controls.append(top)

	# Selected unit actions, right side above the cards.
	var actions := VBoxContainer.new()
	actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	actions.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	actions.grow_vertical = Control.GROW_DIRECTION_BEGIN
	actions.position = Vector2(-8, -112)
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)
	run_button = _button("Run: off", Vector2(130, 56))
	run_button.pressed.connect(func(): run_pressed.emit())
	halt_button = _button("Halt", Vector2(130, 56))
	halt_button.pressed.connect(func(): halt_pressed.emit())
	actions.add_child(run_button)
	actions.add_child(halt_button)
	actions.visible = false
	actions_box = actions
	_ui_controls.append(actions)

	# Unit cards along the bottom edge.
	cards_bar = PanelContainer.new()
	cards_bar.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.45)))
	cards_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	cards_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	cards_bar.custom_minimum_size = Vector2(0, 96)
	root.add_child(cards_bar)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	cards_bar.add_child(scroll)
	cards_box = HBoxContainer.new()
	cards_box.add_theme_constant_override("separation", 6)
	scroll.add_child(cards_box)
	for u in sim.n_units:
		if sim.u_side[u] != player_side:
			continue
		var b := _button("", Vector2(118, 84))
		b.add_theme_font_size_override("font_size", 15)
		b.toggle_mode = true
		b.disabled = not interactive
		b.pressed.connect(func(): card_pressed.emit(u))
		cards_box.add_child(b)
		_cards[u] = b
	_ui_controls.append(cards_bar)

	# Result banner, top centre.
	banner = Label.new()
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.position.y = 80
	banner.add_theme_font_size_override("font_size", 40)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 8)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.visible = false
	root.add_child(banner)

	# Benchmark summary panel, centre.
	bench_panel = PanelContainer.new()
	bench_panel.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.8)))
	bench_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	bench_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bench_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	bench_panel.visible = false
	root.add_child(bench_panel)
	var vb := VBoxContainer.new()
	bench_panel.add_child(vb)
	bench_label = Label.new()
	bench_label.add_theme_font_size_override("font_size", 18)
	vb.add_child(bench_label)
	var back := _button("Back to menu", Vector2(200, 60))
	back.pressed.connect(func(): menu_pressed.emit())
	vb.add_child(back)
	_ui_controls.append(bench_panel)


func set_orders_text(on: bool) -> void:
	orders_button.text = "Orders: on" if on else "Orders"


func is_over_ui(screen_pos: Vector2) -> bool:
	for c in _ui_controls:
		if c.visible and c.get_global_rect().has_point(screen_pos):
			return true
	return false


## run: the selected unit's run flag as the player last ordered it.
func set_selected(u: int, run: int) -> void:
	for k in _cards:
		(_cards[k] as Button).set_pressed_no_signal(k == u)
	actions_box.visible = u >= 0
	if u >= 0:
		run_button.text = "Run: on" if run != 0 else "Run: off"


func update_cards(sim) -> void:
	for u in _cards:
		var b: Button = _cards[u]
		var ty: int = sim.u_type[u]
		var mstate := morale_text(sim, u)
		b.text = "%s %d\n%d / %d\n%s" % [UT.TYPES[ty]["short"], u + 1, sim.u_alive[u],
			sim.u_count0[u], mstate]
		var col := Color(1, 1, 1)
		if sim.u_state[u] == BattleSim.U_DESTROYED:
			col = Color(0.5, 0.5, 0.5)
		elif sim.u_state[u] == BattleSim.U_ROUTING:
			col = Color(1.0, 0.85, 0.3)
		elif sim.u_morale[u] < 250:
			col = Color(1.0, 0.6, 0.4)
		b.add_theme_color_override("font_color", col)
		b.add_theme_color_override("font_pressed_color", col)


static func morale_text(sim, u: int) -> String:
	var s: int = sim.u_state[u]
	if s == BattleSim.U_DESTROYED:
		return "Destroyed"
	if s == BattleSim.U_ROUTING:
		return "Routing"
	var m: int = sim.u_morale[u]
	if m >= 450:
		return "Steady"
	if m >= 250:
		return "Shaken"
	return "Wavering"


func _button(text: String, size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	return b


static func _box(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	return sb
