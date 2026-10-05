extends CanvasLayer
## Screen-space UI: performance readout, pause/speed/menu buttons, unit cards
## along the bottom, group selection buttons, actions for the selected units,
## and the battle result. It only emits signals; battle.gd turns them into
## sim orders or view changes.

signal card_pressed(unit: int)
signal pause_pressed
signal speed_pressed
signal menu_pressed
signal run_pressed
signal halt_pressed
signal fire_pressed
signal skirmish_pressed
signal deploy_pressed
signal withdraw_pressed
signal withdraw_all_pressed
signal group_pressed(kind: String)
signal add_toggled(on: bool)
signal orders_toggled(on: bool)
signal book_pressed
signal card_long_pressed(unit: int)

const BattleSim := preload("res://sim/battle_sim.gd")
const UT := preload("res://sim/unit_types.gd")
const Icons := preload("res://game/unit_icons.gd")
const IconView := preload("res://game/unit_icon_view.gd")
const UnitBook := preload("res://game/unit_book.gd")
const CONFIRM_SEC := 3.0
const LONG_PRESS_SEC := 0.5
const LONG_PRESS_SLOP := 14.0   # px the finger may wander during a long press

var stats_label: Label
var banner: Label
var pause_button: Button
var orders_button: Button
var speed_button: Button
var run_button: Button
var halt_button: Button
var fire_button: Button
var skirm_button: Button
var deploy_button: Button
var withdraw_button: Button
var withdraw_all_button: Button
var add_button: Button
var group_buttons: Dictionary = {}  # kind -> Button
var cards_bar: PanelContainer
var cards_box: HBoxContainer
var bench_panel: PanelContainer
var bench_label: Label
var result_panel: PanelContainer
var result_grid: GridContainer
var result_title: Label
var actions_box: VBoxContainer
var group_box: HBoxContainer
var _cards: Dictionary = {}  # unit -> Button
var _card_labels: Dictionary = {}  # unit -> Label inside the card
var book: UnitBook
var book_button: Button
# Long press on a card: unit, start time, start position; fired once.
var _lp_unit := -1
var _lp_start := 0.0
var _lp_pos := Vector2.ZERO
var _lp_fired := false
## Unit whose card release must not select (the long press opened the book).
var suppress_card := -1
var _ui_controls: Array[Control] = []
var _confirm_left := 0.0


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
	book_button = _button("Units", Vector2(90, 60))
	book_button.tooltip_text = "Unit book: what every unit type does"
	book_button.pressed.connect(func(): book_pressed.emit())
	orders_button = _button("Orders", Vector2(130, 60))
	orders_button.toggle_mode = true
	orders_button.tooltip_text = "Show where every unit is headed"
	orders_button.toggled.connect(func(on: bool):
		set_orders_text(on)
		orders_toggled.emit(on))
	top.add_child(book_button)
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
	run_button = _button("Run: off", Vector2(136, 54))
	run_button.pressed.connect(func(): run_pressed.emit())
	halt_button = _button("Halt", Vector2(136, 54))
	halt_button.pressed.connect(func(): halt_pressed.emit())
	fire_button = _button("Fire: at will", Vector2(136, 54))
	fire_button.tooltip_text = "Missile troops: fire at will, or hold fire"
	fire_button.pressed.connect(func(): fire_pressed.emit())
	skirm_button = _button("Skirmish: on", Vector2(136, 54))
	skirm_button.tooltip_text = "Missile troops fall back from approaching melee troops"
	skirm_button.pressed.connect(func(): skirmish_pressed.emit())
	deploy_button = _button("Deploy: on", Vector2(136, 54))
	deploy_button.tooltip_text = "Artillery: set up to shoot, or pack up to move (takes time either way)"
	deploy_button.pressed.connect(func(): deploy_pressed.emit())
	withdraw_button = _button("Withdraw", Vector2(136, 54))
	withdraw_button.tooltip_text = "Leave the battle by your own map edge"
	withdraw_button.pressed.connect(func(): withdraw_pressed.emit())
	for b in [run_button, halt_button, fire_button, skirm_button, deploy_button, withdraw_button]:
		(b as Button).add_theme_font_size_override("font_size", 16)
		actions.add_child(b)
	actions.visible = false
	actions_box = actions
	_ui_controls.append(actions)

	# Group selection and army withdrawal, bottom left above the cards.
	var groups := HBoxContainer.new()
	groups.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	groups.grow_vertical = Control.GROW_DIRECTION_BEGIN
	groups.position = Vector2(8, -112)
	groups.add_theme_constant_override("separation", 6)
	root.add_child(groups)
	for kind in ["All", "Inf", "Missile", "Cav"]:
		var gb := _button(kind, Vector2(84, 54))
		gb.tooltip_text = "Select all %s units" % kind.to_lower()
		if kind == "Missile":
			gb.tooltip_text = "Select all missile units and artillery"
		gb.pressed.connect(func(): group_pressed.emit(kind.to_lower()))
		gb.disabled = not interactive
		groups.add_child(gb)
		group_buttons[kind.to_lower()] = gb
	add_button = _button("+ Add", Vector2(84, 54))
	add_button.toggle_mode = true
	add_button.tooltip_text = "Taps on units or cards add to / remove from the selection"
	add_button.toggled.connect(func(on: bool): add_toggled.emit(on))
	add_button.disabled = not interactive
	groups.add_child(add_button)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(18, 1)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	groups.add_child(spacer)
	withdraw_all_button = _button("Withdraw army", Vector2(150, 54))
	withdraw_all_button.add_theme_font_size_override("font_size", 16)
	withdraw_all_button.tooltip_text = "Every unit leaves the battle (tap twice)"
	withdraw_all_button.pressed.connect(_on_withdraw_all)
	withdraw_all_button.disabled = not interactive
	groups.add_child(withdraw_all_button)
	group_box = groups
	_ui_controls.append(groups)

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
		var b := _button("", Vector2(150, 84))
		b.toggle_mode = true
		b.disabled = not interactive
		b.pressed.connect(func(): card_pressed.emit(u))
		b.gui_input.connect(_on_card_input.bind(u))
		# Symbol on the left, text to its right (children ignore the mouse
		# so the whole card stays one button).
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 6
		hb.offset_right = -4
		hb.add_theme_constant_override("separation", 6)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(hb)
		var ic := IconView.new(Icons.icon_of(sim.u_type[u]), Icons.SIDE_COLORS[player_side], 34.0)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(ic)
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(lbl)
		cards_box.add_child(b)
		_cards[u] = b
		_card_labels[u] = lbl
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

	# Battle result panel, centre.
	result_panel = PanelContainer.new()
	result_panel.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.82)))
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	result_panel.visible = false
	root.add_child(result_panel)
	var rvb := VBoxContainer.new()
	rvb.add_theme_constant_override("separation", 8)
	result_panel.add_child(rvb)
	result_title = Label.new()
	result_title.add_theme_font_size_override("font_size", 24)
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rvb.add_child(result_title)
	var rscroll := ScrollContainer.new()
	rscroll.custom_minimum_size = Vector2(620, 300)
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rvb.add_child(rscroll)
	result_grid = GridContainer.new()
	result_grid.columns = 6
	result_grid.add_theme_constant_override("h_separation", 18)
	rscroll.add_child(result_grid)
	var rbuttons := HBoxContainer.new()
	rbuttons.add_theme_constant_override("separation", 12)
	rbuttons.alignment = BoxContainer.ALIGNMENT_CENTER
	rvb.add_child(rbuttons)
	var close := _button("Close", Vector2(160, 56))
	close.pressed.connect(func(): result_panel.visible = false)
	var rmenu := _button("Back to menu", Vector2(200, 56))
	rmenu.pressed.connect(func(): menu_pressed.emit())
	rbuttons.add_child(close)
	rbuttons.add_child(rmenu)
	_ui_controls.append(result_panel)

	# Unit book, above everything else.
	book = UnitBook.new()
	book.side_color = Icons.SIDE_COLORS[player_side]
	root.add_child(book)
	_ui_controls.append(book)


## Long press (touch or left button held) or right click on a card opens
## that unit type's page; it never selects or orders anything.
func _on_card_input(event: InputEvent, u: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			card_long_pressed.emit(u)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_lp_unit = u
				_lp_start = Time.get_ticks_msec() / 1000.0
				_lp_pos = mb.global_position
				_lp_fired = false
			else:
				_lp_unit = -1
				if suppress_card >= 0:
					# The card's own release handling (pressed) runs first.
					set_deferred("suppress_card", -1)
	elif event is InputEventMouseMotion and _lp_unit == u:
		if (event as InputEventMouseMotion).global_position.distance_to(_lp_pos) > LONG_PRESS_SLOP:
			_lp_unit = -1


func _process(delta: float) -> void:
	if _lp_unit >= 0 and not _lp_fired and Time.get_ticks_msec() / 1000.0 - _lp_start >= LONG_PRESS_SEC:
		_lp_fired = true
		suppress_card = _lp_unit  # the release that follows must not select
		card_long_pressed.emit(_lp_unit)
	if _confirm_left > 0.0:
		_confirm_left -= delta
		if _confirm_left <= 0.0:
			withdraw_all_button.text = "Withdraw army"


func _on_withdraw_all() -> void:
	if _confirm_left > 0.0:
		_confirm_left = 0.0
		withdraw_all_button.text = "Withdraw army"
		withdraw_all_pressed.emit()
	else:
		_confirm_left = CONFIRM_SEC
		withdraw_all_button.text = "Tap to confirm"


func set_orders_text(on: bool) -> void:
	orders_button.text = "Orders: on" if on else "Orders"


## Text shown on a unit's card.
func card_text(u: int) -> String:
	return (_card_labels[u] as Label).text


func is_over_ui(screen_pos: Vector2) -> bool:
	for c in _ui_controls:
		if c.visible and c.get_global_rect().has_point(screen_pos):
			return true
	return false


## Selection and the action buttons' states. Toggle values are the
## predicted ones (pending orders included); -1 hides a missile-only (or
## artillery-only) button. run -1 hides Run (only artillery selected).
func set_selection(units: Array[int], run: int, fire: int, skirm: int, deploy: int = -1) -> void:
	for k in _cards:
		(_cards[k] as Button).set_pressed_no_signal(units.has(k))
	actions_box.visible = not units.is_empty()
	run_button.visible = run >= 0
	run_button.text = "Run: on" if run > 0 else "Run: off"
	fire_button.visible = fire >= 0
	skirm_button.visible = skirm >= 0
	deploy_button.visible = deploy >= 0
	fire_button.text = "Fire: at will" if fire > 0 else "Fire: hold"
	skirm_button.text = "Skirmish: on" if skirm > 0 else "Skirmish: off"
	deploy_button.text = "Deploy: on" if deploy > 0 else "Deploy: off"


func update_cards(sim) -> void:
	for u in _cards:
		var ty: int = sim.u_type[u]
		var mstate := morale_text(sim, u)
		var text := "%s %d\n%d/%d" % [UT.TYPES[ty]["short"], u + 1, sim.u_alive[u], sim.u_count0[u]]
		if UT.cls(ty) == UT.CLS_ART:
			text = art_card_text(sim, u) + "  " + mstate
		else:
			if UT.stat(ty, "m_ammo") > 0:
				text += " ammo %d" % ((sim.u_ammo[u] + maxi(sim.u_alive[u], 1) - 1) / maxi(sim.u_alive[u], 1))
			text += "\n" + mstate
		var lbl: Label = _card_labels[u]
		lbl.text = text
		var col := Color(1, 1, 1)
		if sim.u_state[u] >= BattleSim.U_DESTROYED:
			col = Color(0.5, 0.5, 0.5)
		elif sim.u_state[u] == BattleSim.U_ROUTING:
			col = Color(1.0, 0.85, 0.3)
		elif sim.u_order[u] == BattleSim.O_WITHDRAW:
			col = Color(0.75, 0.8, 1.0)
		elif sim.u_morale[u] < 250:
			col = Color(1.0, 0.6, 0.4)
		lbl.add_theme_color_override("font_color", col)


## Battery card: crew, engines still working, shots left, set-up state (the
## caller adds the morale word after it).
static func art_card_text(sim, u: int) -> String:
	var ty: int = sim.u_type[u]
	var ok := 0
	for k in sim.u_neng[u]:
		if sim.e_state[sim.u_eng0[u] + k] == 0:
			ok += 1
	return "%s %d  %d/%d\neng %d/%d  %d shots\n%s" % [UT.TYPES[ty]["short"], u + 1,
		sim.u_alive[u], sim.u_count0[u], ok, sim.u_neng[u], maxi(sim.u_ammo[u], 0), deploy_text(sim, u)]


## Artillery set-up state as a word.
static func deploy_text(sim, u: int) -> String:
	var full := UT.stat(sim.u_type[u], "deploy")
	var d: int = sim.u_depl[u]
	var packing: bool = sim.u_deploy[u] == 0 or sim.u_order[u] == BattleSim.O_MOVE \
		or sim.u_order[u] == BattleSim.O_WITHDRAW
	if d >= full:
		return "Ready"
	if d == 0:
		return "Moving" if sim.u_moved[u] > 0 else "Packed"
	return ("Packing %d%%" if packing else "Set up %d%%") % (d * 100 / maxi(full, 1))


static func morale_text(sim, u: int) -> String:
	var s: int = sim.u_state[u]
	if s == BattleSim.U_DESTROYED:
		return "Destroyed"
	if s == BattleSim.U_LEFT:
		return "Left field"
	if s == BattleSim.U_ROUTING:
		return "Routing"
	if sim.u_order[u] == BattleSim.O_WITHDRAW:
		return "Withdrawing"
	var m: int = sim.u_morale[u] - sim.u_fright[u]
	if m >= 450:
		return "Steady"
	if m >= 250:
		return "Shaken"
	return "Wavering"


## Fill the result panel from BattleSim.result().
func show_result(res: Dictionary, title: String, player_side: int) -> void:
	result_title.text = title
	for c in result_grid.get_children():
		c.queue_free()
	for side in [player_side, 1 - player_side]:
		var s: Dictionary = res["sides"][side]
		_cell("Your army" if side == player_side else "Enemy", Color(0.35, 0.6, 1.0) if side == 0 else Color(1.0, 0.45, 0.35))
		for h in ["Start", "Killed", "Routed off", "Withdrawn", "Remain"]:
			_cell(h, Color(0.8, 0.8, 0.8))
		for r in res["units"]:
			if int(r["side"]) != side:
				continue
			_cell("%s %d" % [UT.TYPES[int(r["type"])]["short"], int(r["unit"]) + 1], Color.WHITE)
			for k in ["started", "killed", "routed_off", "withdrawn", "remaining"]:
				_cell(str(r[k]), Color.WHITE)
		_cell("Total", Color(1, 1, 0.7))
		for k in ["started", "killed", "routed_off", "withdrawn", "remaining"]:
			_cell(str(s[k]), Color(1, 1, 0.7))
	result_panel.visible = true


func _cell(text: String, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", col)
	result_grid.add_child(l)


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
