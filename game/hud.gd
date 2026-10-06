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
signal refill_pressed
signal man_wall_pressed
signal come_down_pressed
signal withdraw_pressed
signal withdraw_all_pressed
signal group_pressed(kind: String)
signal add_toggled(on: bool)
signal orders_toggled(on: bool)
signal book_pressed
signal card_long_pressed(unit: int)
signal deselect_pressed
signal controls_pressed
signal gift_pressed
signal ready_pressed

const TouchScroll := preload("res://game/touch_scroll.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const UT := preload("res://sim/unit_types.gd")
const Icons := preload("res://game/unit_icons.gd")
const UnitBook := preload("res://game/unit_book.gd")
const Controls := preload("res://game/controls.gd")
const CONFIRM_SEC := 3.0
const LONG_PRESS_SEC := 0.5
const LONG_PRESS_SLOP := 14.0   # px the finger may wander during a long press
# Layout in logical pixels (game/ui_scale.gd turns them into device sizes).
const BTN_H := 42.0
const MARGIN := 6.0
const GAP := 5.0
const FONT := 15
const FONT_SMALL := 13
const CARD_H := 34.0
const CARD_MIN_W := 84.0
const CARD_NARROW_W := 58.0  # below CARD_MIN_W: symbol and number only
const CARD_MAX_W := 136.0
const CARD_GAP := 2.0

var stats_label: Label
var stats_button: Button
var stats_panel: PanelContainer
var stats_expanded := false
var card_rows := 1
var banner: Label
var pause_button: Button
var orders_button: Button
var speed_button: Button
var run_button: Button
var halt_button: Button
var fire_button: Button
var skirm_button: Button
var deploy_button: Button
var refill_button: Button
var man_wall_button: Button
var come_down_button: Button
var withdraw_button: Button
var gift_button: Button
var withdraw_all_button: Button
var add_button: Button
var deselect_button: Button
## Shift / Ctrl / Cmd was held when the last card was clicked.
var card_mod_add := false
var group_buttons: Dictionary = {}  # kind -> Button
var cards_bar: PanelContainer
var cards_box: HFlowContainer
var bench_panel: PanelContainer
var bench_label: Label
var result_panel: PanelContainer
var menu_button: Button
var result_menu_button: Button
var result_grid: GridContainer
var result_title: Label
var actions_box: HBoxContainer
var group_box: HBoxContainer
var _cards: Dictionary = {}  # unit -> Button
var _faces: Dictionary = {}  # unit -> CardFace inside the card
var _sim
var _player_side := 0
var _root: Control
var _top: HBoxContainer
var _bottom: VBoxContainer
var book: UnitBook
var book_button: Button
var controls_button: Button
var controls: Controls
# Long press on a card: unit, start time, start position; fired once.
var _lp_unit := -1
var _lp_start := 0.0
var _lp_pos := Vector2.ZERO
var _lp_fired := false
## Unit whose card release must not select (the long press opened the book).
var suppress_card := -1
## Deployment phase: a bar under the top buttons (countdown, who is ready)
## with "Start battle".
var deploy_panel: PanelContainer
var deploy_label: Label
var ready_button: Button
var _ui_controls: Array[Control] = []
var _confirm_left := 0.0


func build(sim, player_side: int, interactive: bool) -> void:
	_sim = sim
	_player_side = player_side
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_root = root

	# Performance readout, top left: one short line (fps, tick); tap for the
	# full readout, shown below the top bar so it never sits under a button.
	stats_button = _button("...", Vector2(0, BTN_H))
	stats_button.add_theme_font_size_override("font_size", FONT_SMALL)
	stats_button.position = Vector2(MARGIN, MARGIN)
	stats_button.tooltip_text = "Performance: tap for details"
	stats_button.pressed.connect(func(): set_stats_expanded(not stats_expanded))
	root.add_child(stats_button)
	_ui_controls.append(stats_button)
	stats_panel = PanelContainer.new()
	stats_panel.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.6)))
	stats_panel.position = Vector2(MARGIN, MARGIN * 2 + BTN_H)
	stats_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_panel.visible = false
	root.add_child(stats_panel)
	stats_label = Label.new()
	stats_label.add_theme_font_size_override("font_size", FONT_SMALL)
	stats_label.text = "..."
	stats_panel.add_child(stats_label)

	# Buttons, top right.
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top.position = Vector2(-MARGIN, MARGIN)
	top.add_theme_constant_override("separation", int(GAP))
	root.add_child(top)
	book_button = _button("Units", Vector2(64, BTN_H))
	book_button.tooltip_text = "Unit book: what every unit type does"
	book_button.pressed.connect(func(): book_pressed.emit())
	orders_button = _button("Orders", Vector2(78, BTN_H))
	orders_button.toggle_mode = true
	orders_button.tooltip_text = "Show where every unit is headed"
	orders_button.toggled.connect(func(on: bool):
		set_orders_text(on)
		orders_toggled.emit(on))
	pause_button = _button("Pause", Vector2(74, BTN_H))
	pause_button.pressed.connect(func(): pause_pressed.emit())
	speed_button = _button("1x", Vector2(50, BTN_H))
	speed_button.pressed.connect(func(): speed_pressed.emit())
	withdraw_all_button = _button("Withdraw army", Vector2(0, BTN_H))
	withdraw_all_button.tooltip_text = "Every unit leaves the battle (tap twice)"
	withdraw_all_button.pressed.connect(_on_withdraw_all)
	withdraw_all_button.disabled = not interactive
	var menu := _button("Menu", Vector2(62, BTN_H))
	menu.pressed.connect(func(): menu_pressed.emit())
	menu_button = menu
	controls_button = _button("Keys", Vector2(54, BTN_H))
	controls_button.tooltip_text = "Controls: every touch, mouse and key input (F1)"
	controls_button.pressed.connect(func(): controls_pressed.emit())
	for b in [withdraw_all_button, book_button, controls_button, orders_button, pause_button, speed_button, menu]:
		top.add_child(b)
	_top = top
	_ui_controls.append(top)

	# Bottom: a row with the group buttons (left) and the selection's
	# actions (right), then the unit cards in as many rows as they need.
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_left = MARGIN
	bottom.offset_right = -MARGIN
	bottom.offset_bottom = -MARGIN
	bottom.add_theme_constant_override("separation", int(GAP))
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom)
	_bottom = bottom
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(row)
	var groups := HBoxContainer.new()
	groups.add_theme_constant_override("separation", int(GAP))
	row.add_child(groups)
	for kind in ["All", "Inf", "Missile", "Cav"]:
		var gb := _button(kind, Vector2(54, BTN_H))
		gb.tooltip_text = "Select all %s units" % kind.to_lower()
		if kind == "Missile":
			gb.tooltip_text = "Select all missile units and artillery"
		gb.pressed.connect(func(): group_pressed.emit(kind.to_lower()))
		gb.disabled = not interactive
		groups.add_child(gb)
		group_buttons[kind.to_lower()] = gb
	add_button = _button("+ Add", Vector2(58, BTN_H))
	add_button.toggle_mode = true
	add_button.tooltip_text = "Taps on units or cards add to / remove from the selection"
	add_button.toggled.connect(func(on: bool): add_toggled.emit(on))
	add_button.disabled = not interactive
	groups.add_child(add_button)
	deselect_button = _button("None", Vector2(54, BTN_H))
	deselect_button.tooltip_text = "Deselect all (Esc)"
	deselect_button.pressed.connect(func(): deselect_pressed.emit())
	deselect_button.disabled = not interactive
	groups.add_child(deselect_button)
	group_box = groups
	_ui_controls.append(groups)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", int(GAP))
	row.add_child(actions)
	run_button = _button("Run: off", Vector2(0, BTN_H))
	run_button.pressed.connect(func(): run_pressed.emit())
	halt_button = _button("Halt", Vector2(54, BTN_H))
	halt_button.pressed.connect(func(): halt_pressed.emit())
	fire_button = _button("Fire: at will", Vector2(0, BTN_H))
	fire_button.tooltip_text = "Missile troops: fire at will, or hold fire"
	fire_button.pressed.connect(func(): fire_pressed.emit())
	skirm_button = _button("Skirmish: on", Vector2(0, BTN_H))
	skirm_button.tooltip_text = "Missile troops fall back from approaching melee troops"
	skirm_button.pressed.connect(func(): skirmish_pressed.emit())
	deploy_button = _button("Deploy: on", Vector2(0, BTN_H))
	deploy_button.tooltip_text = "Artillery: set up to shoot, or pack up to move (takes time either way)"
	deploy_button.pressed.connect(func(): deploy_pressed.emit())
	refill_button = _button("Refill: off", Vector2(0, BTN_H))
	refill_button.tooltip_text = "Artillery: bring up shots from the baggage (cannot move or shoot meanwhile)"
	refill_button.pressed.connect(func(): refill_pressed.emit())
	man_wall_button = _button("Man the wall", Vector2(0, BTN_H))
	man_wall_button.tooltip_text = "Up onto the nearest stretch of wall (facing the enemy) by its stair (M)"
	man_wall_button.pressed.connect(func(): man_wall_pressed.emit())
	man_wall_button.visible = false
	come_down_button = _button("Come down", Vector2(0, BTN_H))
	come_down_button.tooltip_text = "Down off the wall by a stair, into the street just inside it (Shift+M)"
	come_down_button.pressed.connect(func(): come_down_pressed.emit())
	come_down_button.visible = false
	withdraw_button = _button("Withdraw", Vector2(0, BTN_H))
	withdraw_button.tooltip_text = "Leave the battle by your own map edge"
	withdraw_button.pressed.connect(func(): withdraw_pressed.emit())
	# Live co-op: give the selected units to the ally (hidden otherwise).
	gift_button = _button("Gift", Vector2(0, BTN_H))
	gift_button.tooltip_text = "Give the selected units to your ally (they can give them back)"
	gift_button.pressed.connect(func(): gift_pressed.emit())
	gift_button.visible = false
	for b in [run_button, halt_button, fire_button, skirm_button, deploy_button, refill_button, man_wall_button,
			come_down_button, withdraw_button, gift_button]:
		actions.add_child(b)
	actions.visible = false
	actions_box = actions
	_ui_controls.append(actions)

	# Unit cards: compact, wrapping into rows (no scrolling).
	cards_bar = PanelContainer.new()
	cards_bar.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.4), 3))
	bottom.add_child(cards_bar)
	cards_box = HFlowContainer.new()
	cards_box.add_theme_constant_override("h_separation", int(CARD_GAP))
	cards_box.add_theme_constant_override("v_separation", int(CARD_GAP))
	cards_bar.add_child(cards_box)
	for u in sim.n_units:
		if sim.u_side[u] != player_side:
			continue
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not interactive
		b.flat = true
		b.custom_minimum_size = Vector2(CARD_MIN_W, CARD_H)
		b.pressed.connect(func(): card_pressed.emit(u))
		b.gui_input.connect(_on_card_input.bind(u))
		var face := CardFace.new()
		face.set_anchors_preset(Control.PRESET_FULL_RECT)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.icon = Icons.icon_of(sim.u_type[u])
		face.side_col = Icons.SIDE_COLORS[player_side]
		b.add_child(face)
		cards_box.add_child(b)
		_cards[u] = b
		_faces[u] = face
	_ui_controls.append(cards_bar)
	get_viewport().size_changed.connect(_layout_cards)
	_layout_cards()

	# Result banner, top centre.
	banner = Label.new()
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.position.y = BTN_H + 3 * MARGIN
	banner.add_theme_font_size_override("font_size", 32)
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
	bench_label.add_theme_font_size_override("font_size", FONT)
	vb.add_child(bench_label)
	var back := _button("Back to menu", Vector2(160, BTN_H))
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
	result_title.add_theme_font_size_override("font_size", 20)
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rvb.add_child(result_title)
	var rscroll := TouchScroll.new()
	rscroll.custom_minimum_size = Vector2(560, 240)
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
	var close := _button("Close", Vector2(120, BTN_H))
	close.pressed.connect(func(): result_panel.visible = false)
	var rmenu := _button("Back to menu", Vector2(160, BTN_H))
	rmenu.pressed.connect(func(): menu_pressed.emit())
	result_menu_button = rmenu
	rbuttons.add_child(close)
	rbuttons.add_child(rmenu)
	_ui_controls.append(result_panel)

	# Deployment bar, top centre under the buttons.
	deploy_panel = PanelContainer.new()
	deploy_panel.add_theme_stylebox_override("panel", _box(Color(0.03, 0.08, 0.16, 0.85)))
	deploy_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	deploy_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	deploy_panel.position.y = BTN_H + 2 * MARGIN
	deploy_panel.visible = false
	root.add_child(deploy_panel)
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", int(GAP) * 2)
	deploy_panel.add_child(dh)
	deploy_label = Label.new()
	deploy_label.add_theme_font_size_override("font_size", FONT)
	deploy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dh.add_child(deploy_label)
	ready_button = _button("Start battle", Vector2(130, BTN_H))
	ready_button.tooltip_text = "Ready: the battle starts when every player is ready, or when the time runs out (Enter)"
	ready_button.pressed.connect(func(): ready_pressed.emit())
	dh.add_child(ready_button)
	_ui_controls.append(deploy_panel)

	# Unit book, above everything else.
	book = UnitBook.new()
	book.side_color = Icons.SIDE_COLORS[player_side]
	root.add_child(book)
	_ui_controls.append(book)
	controls = Controls.new()
	root.add_child(controls)
	_ui_controls.append(controls)


## Cards wrap into rows: as wide as fits up to CARD_MAX_W, at least
## CARD_MIN_W, the fewest rows that hold them all.
func _layout_cards() -> void:
	if cards_box == null:
		return
	var n := _cards.size()
	if n == 0:
		cards_bar.visible = false
		return
	var avail := get_viewport().get_visible_rect().size.x - 2 * MARGIN - 6
	# Fewest rows at full width; from two rows on, narrow cards (symbol and
	# number) are allowed if that saves a row.
	var rows := 1
	var w := 0.0
	while true:
		var per := (n + rows - 1) / rows
		w = floorf((avail + CARD_GAP) / per - CARD_GAP)
		if w >= CARD_MIN_W or (rows >= 2 and w >= CARD_NARROW_W) or rows >= n:
			break
		rows += 1
	w = minf(w, CARD_MAX_W)
	for u in _cards:
		(_cards[u] as Control).custom_minimum_size = Vector2(w, CARD_H)
		(_faces[u] as CardFace).narrow = w < CARD_MIN_W
	card_rows = rows


## Height of the top bar and of the bottom HUD (cards, groups, actions) in
## logical pixels, for framing the battle between them.
func top_height() -> float:
	return MARGIN * 2 + BTN_H


func bottom_height() -> float:
	return MARGIN * 3 + BTN_H + GAP + card_rows * (CARD_H + CARD_GAP) + 6.0


## Readout: short line always, details when expanded.
func set_stats(short: String, long: String) -> void:
	stats_button.text = short
	stats_label.text = long


func set_stats_expanded(on: bool) -> void:
	stats_expanded = on
	stats_panel.visible = on


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
				# Shift / Ctrl held at the click: add to the selection.
				card_mod_add = mb.shift_pressed or mb.ctrl_pressed or mb.meta_pressed
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
	return (_faces[u] as CardFace).summary


## A control of another layer (the co-op panels) that touches must not
## pass through to the battlefield.
## Deployment bar: text "" hides it; the button shows btn (disabled if
## not btn_on).
func set_deploy(text: String, btn: String, btn_on: bool) -> void:
	if deploy_panel == null:
		return
	deploy_panel.visible = text != ""
	deploy_label.text = text
	ready_button.text = btn
	ready_button.disabled = not btn_on
	ready_button.visible = btn != ""


func add_ui_control(c: Control) -> void:
	_ui_controls.append(c)


## Live co-op: mark unit u's card as commanded by the ally (not orderable
## here) in the ally's colour, or as this player's own.
func set_card_owner(u: int, foreign: bool, col: Color) -> void:
	if not _faces.has(u):
		return
	var f: CardFace = _faces[u]
	if f.foreign != foreign or f.owner_col != col:
		f.foreign = foreign
		f.owner_col = col
		f.queue_redraw()


func is_over_ui(screen_pos: Vector2) -> bool:
	for c in _ui_controls:
		if c.visible and c.get_global_rect().has_point(screen_pos):
			return true
	return false


## Selection and the action buttons' states. Toggle values are the
## predicted ones (pending orders included); -1 hides a missile-only (or
## artillery-only) button. run -1 hides Run (only artillery selected).
func set_selection(units: Array[int], run: int, fire: int, skirm: int, deploy: int = -1,
		refill: int = -1) -> void:
	for k in _cards:
		(_cards[k] as Button).set_pressed_no_signal(units.has(k))
		var f: CardFace = _faces[k]
		if f.selected != units.has(k):
			f.selected = units.has(k)
			f.queue_redraw()
	actions_box.visible = not units.is_empty()
	run_button.visible = run >= 0
	run_button.text = "Run: on" if run > 0 else "Run: off"
	fire_button.visible = fire >= 0
	skirm_button.visible = skirm >= 0
	deploy_button.visible = deploy >= 0
	fire_button.text = "Fire: at will" if fire > 0 else "Fire: hold"
	skirm_button.text = "Skirmish: on" if skirm > 0 else "Skirmish: off"
	deploy_button.text = "Deploy: on" if deploy > 0 else "Deploy: off"
	refill_button.visible = refill >= 0
	refill_button.text = "Refill: on" if refill > 0 else "Refill: off"


## Walls: show "Man the wall" / "Come down" (battle.gd decides when).
func set_wall_buttons(man: bool, down: bool) -> void:
	man_wall_button.visible = man
	come_down_button.visible = down


func update_cards(sim) -> void:
	var tick: int = sim.tick
	for u in _cards:
		var ty: int = sim.u_type[u]
		var f: CardFace = _faces[u]
		var mstate := morale_text(sim, u)
		var art := UT.cls(ty) == UT.CLS_ART
		f.name_text = "%s %d" % [UT.TYPES[ty]["short"], u + 1]
		f.number_text = str(u + 1)
		f.alive = sim.u_alive[u]
		f.count0 = sim.u_count0[u]
		f.ammo_text = ""
		var summary := "%s %d/%d" % [f.name_text, f.alive, f.count0]
		if art:
			f.ammo_text = "%d+%d" % [maxi(sim.u_ammo[u], 0), maxi(sim.u_reserve[u], 0)]
			summary = art_card_text(sim, u).replace("\n", " | ")
		elif UT.stat(ty, "m_ammo") > 0:
			var per: int = (sim.u_ammo[u] + maxi(sim.u_alive[u], 1) - 1) / maxi(sim.u_alive[u], 1)
			f.ammo_text = "%d" % per
			summary += " ammo %d" % per
		# Short state word: art set-up / refill state, else the morale word
		# unless steady.
		var word := mstate if mstate != "Steady" else ""
		if art and sim.u_state[u] == BattleSim.U_READY and sim.u_order[u] != BattleSim.O_WITHDRAW:
			var dt := deploy_text(sim, u)
			word = dt if dt != "Ready" else word
		f.state_text = word
		f.summary = summary + " " + mstate
		var st := 0
		if sim.u_state[u] >= BattleSim.U_DESTROYED:
			st = CardFace.ST_GONE
		elif sim.u_state[u] == BattleSim.U_ROUTING:
			st = CardFace.ST_ROUT
		elif sim.u_order[u] == BattleSim.O_WITHDRAW:
			st = CardFace.ST_WITHDRAW
		elif sim.u_morale[u] - sim.u_fright[u] < 250:
			st = CardFace.ST_WAVER
		f.state = st
		f.under_fire = tick - sim.u_hit_t[u] < 10 or tick - sim.u_charged_t[u] < 15
		f.fighting = sim.u_fighting[u] > 0
		f.refilling = art and (sim.u_refill[u] != 0 or sim.u_rprog[u] > 0)
		f.queue_redraw()


## Battery card: crew, engines still working, shots left, set-up state (the
## caller adds the morale word after it).
static func art_card_text(sim, u: int) -> String:
	var ty: int = sim.u_type[u]
	var ok := 0
	for k in sim.u_neng[u]:
		if sim.e_state[sim.u_eng0[u] + k] == 0:
			ok += 1
	return "%s %d  %d/%d\neng %d/%d  %d shots +%d\n%s" % [UT.TYPES[ty]["short"], u + 1,
		sim.u_alive[u], sim.u_count0[u], ok, sim.u_neng[u], maxi(sim.u_ammo[u], 0),
		maxi(sim.u_reserve[u], 0), deploy_text(sim, u)]


## Artillery set-up / refill state as a word.
static func deploy_text(sim, u: int) -> String:
	var rp: int = sim.u_rprog[u]
	if rp > 0 or sim.u_refill[u] != 0:
		if rp >= BattleSim.REFILL_FULL:
			return "REFILLING"
		if sim.u_refill[u] != 0:
			return "To refill %d%%" % (rp * 100 / BattleSim.REFILL_FULL)
		return "Leaving refill"
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
	b.add_theme_font_size_override("font_size", FONT)
	return b


static func _box(col: Color, margin: float = 8.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(margin)
	return sb


## A compact unit card, drawn rather than laid out: side-coloured symbol,
## short name and number, ammunition (artillery: shots + reserve) at the
## right, a thin headcount bar with the count, and a short state word.
## Selected: bright frame; routing: yellow; wavering: orange; withdrawing:
## pale blue; gone: grey; under fire or charged: an orange edge.
class CardFace extends Control:
	const ST_OK := 0
	const ST_WAVER := 1
	const ST_ROUT := 2
	const ST_WITHDRAW := 3
	const ST_GONE := 4
	var icon := 0
	var side_col := Color(0.35, 0.6, 1.0)
	var name_text := ""
	var number_text := ""
	var narrow := false
	var ammo_text := ""
	var state_text := ""
	var summary := ""
	var alive := 0
	var count0 := 1
	var state := ST_OK
	var selected := false
	var under_fire := false
	var fighting := false
	var refilling := false
	## Live co-op: commanded by the ally (drawn with their colour, dimmer).
	var foreign := false
	var owner_col := Color.WHITE

	func _draw() -> void:
		var sz := size
		var bg := Color(0.13, 0.15, 0.13, 0.92)
		var txt := Color(1, 1, 1)
		var bar := side_col
		match state:
			ST_WAVER:
				txt = Color(1.0, 0.7, 0.45)
			ST_ROUT:
				bg = Color(0.35, 0.3, 0.08, 0.95)
				txt = Color(1.0, 0.9, 0.35)
				bar = Color(1.0, 0.85, 0.3)
			ST_WITHDRAW:
				txt = Color(0.75, 0.82, 1.0)
			ST_GONE:
				bg = Color(0.1, 0.1, 0.1, 0.7)
				txt = Color(0.5, 0.5, 0.5)
				bar = Color(0.4, 0.4, 0.4)
		if selected:
			bg = bg.lightened(0.22)
		if foreign:
			bg = bg.darkened(0.35)
			txt = txt.darkened(0.25)
		draw_rect(Rect2(Vector2.ZERO, sz), bg)
		if foreign:
			# The ally's unit: a frame and a corner tab in their colour.
			draw_rect(Rect2(Vector2(1, 1), sz - Vector2(2, 2)), Color(owner_col, 0.85), false, 1.5)
			draw_rect(Rect2(sz.x - 9, 0, 9, 6), owner_col)
		if under_fire and state != ST_GONE:
			draw_rect(Rect2(0, 0, 3, sz.y), Color(1.0, 0.55, 0.1))
		var r := minf(sz.y * 0.3, 10.0)
		var glyph := Color(0.12, 0.1, 0.05) if state == ST_ROUT else Color.WHITE
		var disc := Color(1.0, 0.9, 0.3) if state == ST_ROUT else (Color(0.45, 0.45, 0.45) if state == ST_GONE else side_col)
		var font := ThemeDB.fallback_font
		var x0 := r * 2 + 6
		# Line 1: name and number (narrow cards: the number beside the symbol).
		if narrow:
			Icons.draw_marker(self, icon, Vector2(r + 3, r + 3), r, disc, glyph)
			draw_string(font, Vector2(x0, 14), number_text, HORIZONTAL_ALIGNMENT_LEFT, sz.x - x0 - 2, 13, txt)
		else:
			Icons.draw_marker(self, icon, Vector2(r + 3, sz.y * 0.5), r, disc, glyph)
			draw_string(font, Vector2(x0, 14), name_text, HORIZONTAL_ALIGNMENT_LEFT, sz.x - x0 - 2, 13, txt)
		# Line 2: headcount bar with the count and state word; ammunition
		# (artillery: shots + reserve) at its right end.
		var bx := 3.0 if narrow else x0
		var bw := sz.x - bx - 3
		var by := sz.y - 14
		var frac := clampf(float(alive) / maxf(count0, 1), 0.0, 1.0)
		draw_rect(Rect2(bx, by, bw, 12), Color(1, 1, 1, 0.1))
		draw_rect(Rect2(bx, by, bw * frac, 12), Color(bar, 0.55))
		var aw := 0.0
		if ammo_text != "":
			aw = font.get_string_size(ammo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 3
			draw_string(font, Vector2(bx + bw - aw, by + 10), ammo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
				Color(0.55, 0.85, 1.0) if refilling else Color(1.0, 0.88, 0.55))
		var line := str(alive)
		if state_text != "" and not narrow:
			line += " " + state_text
		draw_string(font, Vector2(bx + 2, by + 10), line, HORIZONTAL_ALIGNMENT_LEFT, maxf(bw - aw - 4, 8), 11, txt)
		if narrow and state_text != "" and state != ST_OK:
			draw_rect(Rect2(sz.x - 6, 3, 3, 8), txt)
		if selected:
			draw_rect(Rect2(Vector2(1, 1), sz - Vector2(2, 2)), Color(1, 1, 1, 0.95), false, 2.0)
		elif fighting and state == ST_OK:
			draw_rect(Rect2(Vector2(0.5, 0.5), sz - Vector2(1, 1)), Color(1, 1, 1, 0.25), false, 1.0)
