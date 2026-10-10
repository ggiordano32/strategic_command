extends CanvasLayer
## Screen-space UI: performance readout, pause/speed/menu buttons, unit cards
## along the bottom, group selection buttons, actions for the selected units,
## and the battle result. It only emits signals; battle.gd turns them into
## sim orders or view changes.

signal card_pressed(unit: int)
signal pause_pressed
signal speed_pressed
## The speed slider: q in quarter steps (Lockstep.SPEED_Q_MIN..MAX, 4 = 1x).
## final: the finger / button was released (co-op votes only then).
signal speed_chosen(q: int, final: bool)
signal menu_pressed
signal run_pressed
signal halt_pressed
signal fire_pressed
signal skirmish_pressed
signal deploy_pressed
signal refill_pressed
signal ammo_pressed
signal forage_pressed
signal man_wall_pressed
signal come_down_pressed
signal drop_pressed
signal kill_pressed
signal release_pressed
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
signal cards_reordered
signal ready_pressed
signal works_pressed(mode: String)  # deployment: field works palette ("stakes", "caltrops", "rotate", "remove")

const AudioFx := preload("res://game/audio.gd")
const TouchScroll := preload("res://game/touch_scroll.gd")
const DragReorder := preload("res://game/drag_reorder.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Lockstep := preload("res://sim/lockstep.gd")
const UT := preload("res://sim/unit_types.gd")
const Icons := preload("res://game/unit_icons.gd")
const UnitBook := preload("res://game/unit_book.gd")
const Controls := preload("res://game/controls.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const Traits := preload("res://game/unit_traits.gd")
const CONFIRM_SEC := 3.0
const LONG_PRESS_SEC := 0.5
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
var _toggles := {}  # order toggle button -> [order word, state word]
var stats_button: Button
var stats_panel: PanelContainer
var stats_expanded := false
var card_rows := 1
var banner: Label
var pause_button: Button
var orders_button: Button
var speed_button: Button
## Speed popover under the speed button: value label, slider (quarter
## steps), tick labels.
var speed_panel: PanelContainer
var speed_slider: HSlider
var speed_value: Label
var _speed_dragging := false
var run_button: Button
var halt_button: Button
var fire_button: Button
var skirm_button: Button
var deploy_button: Button
var refill_button: Button
var ammo_button: Button
var forage_button: Button
var man_wall_button: Button
var come_down_button: Button
var drop_button: Button
## "Kill elephant": shown while a beast unit of the player's runs amok.
var kill_button: Button
## "Release": handlers with dogs in the kennel selected; then a tap on an enemy.
var release_button: Button
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
var result_detail: Label
var result_title: Label
var actions_box: HBoxContainer
var group_box: HBoxContainer
var _cards: Dictionary = {}  # unit -> Button
var _faces: Dictionary = {}  # unit -> CardFace inside the card
## Wall engines (fixed units on the towers): one card per engine kind, held by
## the first of the group. leader unit -> the group's units.
var _tgroups: Dictionary = {}
var engine_note: Label
## The selected unit's carry pattern ("Carrying a ram: column of 4").
var carry_note: Label
## Set by the battle before set_selection: only wall engines are selected
## (they take no orders).
var engine_only := false
var _sim
var _player_side := 0
var _root: Control
var _top: HBoxContainer
var _bottom: VBoxContainer
var book: UnitBook
var book_button: Button
var controls_button: Button
var controls: Controls
## Unit whose card release must not select (unused since drag_reorder.gd
## swallows the release after a long press; battle.gd still checks it).
var suppress_card := -1
## The cards' display order (unit indices), changed by dragging a card. A
## view-only mapping for this player and this battle: the sim's unit
## indices never change and nothing of it reaches the sim or lockstep.
var _order: Array[int] = []
var _reorder: DragReorder
## Deployment phase: a bar under the top buttons (countdown, who is ready)
## with "Start battle".
var deploy_panel: PanelContainer
var deploy_label: Label
var ready_button: Button
## Deployment: the field works palette (under the deployment bar) and its buttons by mode.
var works_panel: PanelContainer
var works_buttons := {}
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
	book_button = _button("Units", Vector2(64, BTN_H), "units")
	book_button.tooltip_text = "Unit book: what every unit type does"
	book_button.pressed.connect(func(): book_pressed.emit())
	orders_button = _button("Orders", Vector2(78, BTN_H), "move")
	orders_button.toggle_mode = true
	orders_button.tooltip_text = "Show where every unit is headed"
	orders_button.toggled.connect(func(on: bool):
		set_orders_text(on)
		orders_toggled.emit(on))
	pause_button = _button("Pause", Vector2(74, BTN_H))
	pause_button.pressed.connect(func(): pause_pressed.emit())
	speed_button = _button("1x", Vector2(50, BTN_H))
	speed_button.tooltip_text = "Battle speed: tap for the slider (+ / - keys)"
	speed_button.pressed.connect(func():
		set_speed_panel_open(not speed_panel.visible)
		speed_pressed.emit())
	withdraw_all_button = _button("Withdraw army", Vector2(0, BTN_H), "withdraw")
	withdraw_all_button.tooltip_text = "Every unit leaves the battle (tap twice)"
	withdraw_all_button.pressed.connect(_on_withdraw_all)
	withdraw_all_button.disabled = not interactive
	var menu := _button("", Vector2(50, BTN_H), "menu")
	menu.name = "menu"
	menu.tooltip_text = "Menu"
	menu.pressed.connect(func(): menu_pressed.emit())
	menu_button = menu
	controls_button = _button("Keys", Vector2(54, BTN_H), "key")
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
	add_button = _button("Add", Vector2(58, BTN_H), "plus")
	add_button.toggle_mode = true
	add_button.tooltip_text = "Taps on units or cards add to / remove from the selection"
	add_button.toggled.connect(func(on: bool): add_toggled.emit(on))
	add_button.disabled = not interactive
	groups.add_child(add_button)
	deselect_button = _button("", Vector2(54, BTN_H), "deselect")
	deselect_button.name = "deselect"
	deselect_button.tooltip_text = "Deselect all (Esc)"
	deselect_button.pressed.connect(func(): deselect_pressed.emit())
	deselect_button.disabled = not interactive
	groups.add_child(deselect_button)
	kill_button = _button("Kill elephant", Vector2(0, BTN_H), "kill_beast")
	kill_button.name = "kill_beast"
	kill_button.tooltip_text = "Your elephants are running amok: their drivers kill them (5 s) before they trample more of your men"
	kill_button.pressed.connect(func(): kill_pressed.emit())
	kill_button.visible = false
	kill_button.disabled = not interactive
	groups.add_child(kill_button)
	group_box = groups
	_ui_controls.append(groups)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", int(GAP))
	row.add_child(actions)
	engine_note = Label.new()
	engine_note.text = "Wall engine: fixed, shoots on its own"
	engine_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	engine_note.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	engine_note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	engine_note.add_theme_constant_override("outline_size", 4)
	engine_note.size_flags_vertical = Control.SIZE_SHRINK_END
	engine_note.visible = false
	row.add_child(engine_note)
	carry_note = Label.new()
	carry_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carry_note.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0))
	carry_note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	carry_note.add_theme_constant_override("outline_size", 4)
	carry_note.size_flags_vertical = Control.SIZE_SHRINK_END
	carry_note.visible = false
	row.add_child(carry_note)
	row.move_child(carry_note, actions.get_index())  # (left of the order buttons)
	run_button = _button("Run: off", Vector2(0, BTN_H), "run")
	run_button.pressed.connect(func(): run_pressed.emit())
	halt_button = _button("Halt", Vector2(54, BTN_H), "cancel")
	halt_button.pressed.connect(func(): halt_pressed.emit())
	fire_button = _button("Fire: at will", Vector2(0, BTN_H), "fire")
	fire_button.tooltip_text = "Missile troops: fire at will, or hold fire"
	fire_button.pressed.connect(func(): fire_pressed.emit())
	skirm_button = _button("Skirmish: on", Vector2(0, BTN_H), "skirmish")
	skirm_button.tooltip_text = "Missile troops fall back from approaching melee troops"
	skirm_button.pressed.connect(func(): skirmish_pressed.emit())
	deploy_button = _button("Deploy: on", Vector2(0, BTN_H), "deploy")
	deploy_button.tooltip_text = "Artillery: set up to shoot, or pack up to move (takes time either way)"
	deploy_button.pressed.connect(func(): deploy_pressed.emit())
	refill_button = _button("Refill: off", Vector2(0, BTN_H), "pick_up")
	refill_button.tooltip_text = "Artillery: bring up shots from the baggage; missile troops and batteries near an ammunition wagon: refill from it (cannot move or shoot meanwhile)"
	refill_button.pressed.connect(func(): refill_pressed.emit())
	ammo_button = _button("Ammo: arrows", Vector2(0, BTN_H), "ammo")
	ammo_button.name = "ammo"
	ammo_button.tooltip_text = "Units with a second ammunition kind (fire arrows, heavy bolts ...): shoot it, or the standard kind (V)"
	ammo_button.pressed.connect(func(): ammo_pressed.emit())
	forage_button = _button("Forage: off", Vector2(0, BTN_H), "forage")
	forage_button.name = "forage"
	forage_button.tooltip_text = "Missile troops in woods: make arrows / javelins for their quivers, slowly; they cannot move or shoot meanwhile (J)"
	forage_button.pressed.connect(func(): forage_pressed.emit())
	man_wall_button = _button("Man the wall", Vector2(0, BTN_H), "wall_up")
	man_wall_button.tooltip_text = "Up onto the nearest stretch of wall (facing the enemy) by its stair (M)"
	man_wall_button.pressed.connect(func(): man_wall_pressed.emit())
	man_wall_button.visible = false
	come_down_button = _button("Come down", Vector2(0, BTN_H), "wall_down")
	come_down_button.tooltip_text = "Down off the wall by a stair, into the street just inside it (Shift+M)"
	come_down_button.pressed.connect(func(): come_down_pressed.emit())
	come_down_button.visible = false
	drop_button = _button("Drop", Vector2(0, BTN_H), "drop")
	drop_button.tooltip_text = "Put down the ladders, the ram, a wagon or engines where the unit stands, free to fight (X); any foot unit takes it up again (tap it)"
	drop_button.pressed.connect(func(): drop_pressed.emit())
	drop_button.visible = false
	release_button = _button("Release: 0", Vector2(0, BTN_H), "release")
	release_button.name = "release"
	release_button.toggle_mode = true
	release_button.tooltip_text = "War dogs: let the pack loose, then tap an enemy unit within 80 m (U); they come back when no enemy is near"
	release_button.pressed.connect(func(): release_pressed.emit())
	release_button.visible = false
	withdraw_button = _button("Withdraw", Vector2(0, BTN_H), "withdraw")
	withdraw_button.tooltip_text = "Leave the battle by your own map edge"
	withdraw_button.pressed.connect(func(): withdraw_pressed.emit())
	# Live co-op: give the selected units to the ally (hidden otherwise).
	gift_button = _button("Gift", Vector2(0, BTN_H), "gift")
	gift_button.tooltip_text = "Give the selected units to your ally (they can give them back)"
	gift_button.pressed.connect(func(): gift_pressed.emit())
	gift_button.visible = false
	for b in [run_button, halt_button, fire_button, skirm_button, ammo_button, deploy_button, refill_button,
			forage_button, man_wall_button, come_down_button, drop_button, release_button, withdraw_button, gift_button]:
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
	var tleader := {}  # engine type -> the unit holding its card
	for u in sim.n_units:
		if sim.u_side[u] != player_side:
			continue
		if UT.stat(sim.u_type[u], "fixed") != 0:
			var tk: int = sim.u_type[u]
			if tleader.has(tk):
				(_tgroups[tleader[tk]] as Array).append(u)
				continue
			tleader[tk] = u
			_tgroups[u] = [u]
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not interactive
		b.flat = true
		b.visible = sim.u_state[u] != BattleSim.U_KENNEL  # (a war dog pack: shown once let loose)
		b.custom_minimum_size = Vector2(CARD_MIN_W, CARD_H)
		b.pressed.connect(func(): card_pressed.emit(u))
		b.gui_input.connect(_on_card_input.bind(u))
		var face := CardFace.new()
		face.set_anchors_preset(Control.PRESET_FULL_RECT)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.icon = Icons.icon_of(sim.u_otype[u])
		face.general = UT.stat(sim.u_type[u], "cmd_r") > 0
		face.char_icon = Traits.char_icon(sim.u_otype[u])  # a hero or agent: crown / dagger / scroll
		face.side_col = Icons.SIDE_COLORS[player_side]
		b.add_child(face)
		cards_box.add_child(b)
		_cards[u] = b
		_faces[u] = face
		_order.append(u)
	# Drag a card to reorder the strip (mouse: drag; touch: long press, then
	# drag); its long press without a drag opens the unit book.
	_reorder = DragReorder.new()
	root.add_child(_reorder)
	_reorder.held.connect(func(i: int): card_long_pressed.emit(_order[i]))
	_reorder.moved.connect(_on_card_moved)
	_reorder_items()
	_ui_controls.append(cards_bar)
	get_viewport().size_changed.connect(_layout_cards)
	get_viewport().size_changed.connect(_fit_actions.call_deferred)
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
	result_detail = Label.new()
	result_detail.name = "result_kills_detail"
	result_detail.add_theme_font_size_override("font_size", 14)
	result_detail.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	result_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_detail.custom_minimum_size = Vector2(560, 0)
	result_detail.text = "Tap a unit's kills for the enemy types it killed."
	rvb.add_child(result_detail)
	result_grid = GridContainer.new()
	result_grid.columns = 7
	result_grid.add_theme_constant_override("h_separation", 18)
	rscroll.add_child(result_grid)
	var rbuttons := HBoxContainer.new()
	rbuttons.add_theme_constant_override("separation", 12)
	rbuttons.alignment = BoxContainer.ALIGNMENT_CENTER
	rvb.add_child(rbuttons)
	var close := _button("Close", Vector2(120, BTN_H), "close")
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
	ready_button = _button("Start battle", Vector2(130, BTN_H), "battles")
	ready_button.tooltip_text = "Ready: the battle starts when every player is ready, or when the time runs out (Enter)"
	ready_button.pressed.connect(func(): ready_pressed.emit())
	dh.add_child(ready_button)
	_ui_controls.append(deploy_panel)

	# Field works palette, under the deployment bar: a button per kind with
	# the count left to place, then Rotate and Remove (toggles: the mode the
	# next tap or drag on the field uses).
	works_panel = PanelContainer.new()
	works_panel.add_theme_stylebox_override("panel", _box(Color(0.10, 0.07, 0.03, 0.85)))
	works_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	works_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	works_panel.position.y = 2 * BTN_H + 5 * MARGIN
	works_panel.visible = false
	root.add_child(works_panel)
	var wh := HBoxContainer.new()
	wh.add_theme_constant_override("separation", int(GAP))
	works_panel.add_child(wh)
	for m in [["stakes", "Stakes", "Stakes line: tap your zone to place one (drag to lay it along a line); tap a placed one to turn it"],
			["caltrops", "Caltrops", "Caltrop field (hidden from the enemy until crossed): tap your zone to place one"],
			["rotate", "Rotate", "Tap a placed stakes line to turn it an eighth"],
			["remove", "Remove", "Tap a placed piece to take it back"]]:
		var mode: String = m[0]
		var b := _button(m[1], Vector2(0, BTN_H), mode)
		b.toggle_mode = true
		b.name = "works_" + mode
		b.tooltip_text = m[2]
		b.pressed.connect(func(): works_pressed.emit(mode))
		wh.add_child(b)
		works_buttons[mode] = b
	_ui_controls.append(works_panel)

	_build_speed_panel(root)

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
	if _sim != null and _sim.phase != 0:
		return MARGIN * 4 + BTN_H * 2  # (the deployment bar under the buttons)
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


## Right click on a card, or a long press (left button held still; on a
## touch: held until the card lifts, released without moving) opens that
## unit type's page; it never selects or orders anything. Dragging a card
## (touch: after the lift) moves it in the strip (drag_reorder.gd).
func _on_card_input(event: InputEvent, u: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			card_long_pressed.emit(u)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# Shift / Ctrl held at the click: add to the selection.
			card_mod_add = mb.shift_pressed or mb.ctrl_pressed or mb.meta_pressed
	_reorder.feed(event, _order.find(u))


## A card dropped at display position `to`.
func _on_card_moved(from: int, to: int) -> void:
	var u := _order[from]
	_order.remove_at(from)
	_order.insert(to, u)
	cards_box.move_child(_cards[u], to)
	_reorder_items()
	cards_reordered.emit()


func _reorder_items() -> void:
	var list: Array = []
	for u in _order:
		list.append(_cards[u])
	_reorder.items = list


## The player's units in the card strip's display order (the order group
## selection follows).
func display_order() -> Array[int]:
	return _order.duplicate()


func _process(delta: float) -> void:
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


## The field works palette: counts left to place per kind (Vector2i(left,
## placed)), the armed mode ("" none); hidden when `on` is false.
func set_works(on: bool, stakes: Vector2i, caltrops: Vector2i, mode: String) -> void:
	if works_panel == null:
		return
	works_panel.visible = on
	if not on:
		return
	(works_buttons["stakes"] as Button).text = "Stakes %d" % stakes.x
	(works_buttons["stakes"] as Button).visible = stakes.x + stakes.y > 0
	(works_buttons["caltrops"] as Button).text = "Caltrops %d" % caltrops.x
	(works_buttons["caltrops"] as Button).visible = caltrops.x + caltrops.y > 0
	(works_buttons["rotate"] as Button).visible = stakes.y > 0
	(works_buttons["remove"] as Button).visible = stakes.y + caltrops.y > 0
	for k in works_buttons:
		(works_buttons[k] as Button).set_pressed_no_signal(k == mode)


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


func _build_speed_panel(root: Control) -> void:
	speed_panel = PanelContainer.new()
	speed_panel.name = "speed_panel"
	speed_panel.add_theme_stylebox_override("panel", _box(Color(0.05, 0.06, 0.09, 0.92), 10.0))
	speed_panel.visible = false
	root.add_child(speed_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	speed_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := Label.new()
	t.text = "Speed"
	t.add_theme_font_size_override("font_size", FONT_SMALL)
	t.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	speed_value = Label.new()
	speed_value.name = "speed_value"
	speed_value.text = "1x"
	speed_value.add_theme_font_size_override("font_size", 18)
	head.add_child(speed_value)
	speed_slider = HSlider.new()
	speed_slider.name = "speed_slider"
	speed_slider.min_value = Lockstep.SPEED_Q_MIN
	speed_slider.max_value = Lockstep.SPEED_Q_MAX
	speed_slider.step = 1
	speed_slider.value = 4
	speed_slider.focus_mode = Control.FOCUS_NONE
	speed_slider.scrollable = false  # the wheel zooms the map, never the speed
	speed_slider.custom_minimum_size = Vector2(270, 40)
	# Touch-sized handle and a visible track.
	var grab := _disc(30, Color(0.92, 0.93, 0.97))
	speed_slider.add_theme_icon_override("grabber", grab)
	speed_slider.add_theme_icon_override("grabber_highlight", _disc(30, Color(1, 1, 1)))
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.3, 0.32, 0.38)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	speed_slider.add_theme_stylebox_override("slider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color(0.45, 0.62, 0.9)
	speed_slider.add_theme_stylebox_override("grabber_area", fill)
	speed_slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	speed_slider.value_changed.connect(func(x: float):
		speed_value.text = Lockstep.speed_text(int(x))
		speed_chosen.emit(int(x), false))
	speed_slider.drag_started.connect(func(): _speed_dragging = true)
	# A tap on the track moves the handle without a drag in between; the
	# value at release is what counts either way.
	speed_slider.drag_ended.connect(func(_changed: bool):
		_speed_dragging = false
		speed_chosen.emit(int(speed_slider.value), true))
	v.add_child(speed_slider)
	var ticks := SpeedTicks.new()
	ticks.slider = speed_slider
	ticks.custom_minimum_size = Vector2(270, 16)
	ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ticks)
	_ui_controls.append(speed_panel)


static func _disc(d: int, col: Color) -> ImageTexture:
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var r := d / 2.0
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var c := col if dist < r - 2.0 else Color(0.1, 0.12, 0.16)
			c.a = clampf(r - dist, 0.0, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func set_speed_panel_open(on: bool) -> void:
	speed_panel.visible = on
	if on:
		speed_panel.reset_size()
		var r := speed_button.get_global_rect()
		var w := speed_panel.size.x
		speed_panel.position = Vector2(
			clampf(r.end.x - w, MARGIN, _root.size.x - w - MARGIN), r.end.y + GAP)


## The speed shown: the button has the speed in force, the slider (unless
## the finger is on it) `slider_q`: the same, or this player's open co-op
## proposal.
func set_speed(q: int, slider_q: int) -> void:
	speed_button.text = Lockstep.speed_text(q)
	if not _speed_dragging and int(speed_slider.value) != slider_q:
		speed_slider.set_value_no_signal(slider_q)
		speed_value.text = Lockstep.speed_text(slider_q)


func _input(event: InputEvent) -> void:
	# A press anywhere outside the open speed popover (and its button) closes it.
	if speed_panel != null and speed_panel.visible and event is InputEventScreenTouch \
			and (event as InputEventScreenTouch).pressed:
		var p := (event as InputEventScreenTouch).position
		if not speed_panel.get_global_rect().has_point(p) \
				and not speed_button.get_global_rect().has_point(p):
			speed_panel.visible = false


func is_over_ui(screen_pos: Vector2) -> bool:
	for c in _ui_controls:
		if c.visible and c.get_global_rect().has_point(screen_pos):
			return true
	return false


## Selection and the action buttons' states. Toggle values are the
## predicted ones (pending orders included); -1 hides a missile-only (or
## artillery-only) button. run -1 hides Run (only artillery selected).
func set_selection(units: Array[int], run: int, fire: int, skirm: int, deploy: int = -1,
		refill: int = -1, ammo: int = -1, ammo_word: String = "", forage: int = -1, dogs: int = -1,
		release_armed: bool = false) -> void:
	for k in _cards:
		var on := units.has(k)
		if _tgroups.has(k):
			for t in _tgroups[k]:
				on = on or units.has(t)
		(_cards[k] as Button).set_pressed_no_signal(on)
		var f: CardFace = _faces[k]
		if f.selected != on:
			f.selected = on
			f.queue_redraw()
	actions_box.visible = not units.is_empty() and not engine_only
	engine_note.visible = not units.is_empty() and engine_only
	run_button.visible = run >= 0
	fire_button.visible = fire >= 0
	skirm_button.visible = skirm >= 0
	deploy_button.visible = deploy >= 0
	refill_button.visible = refill >= 0
	ammo_button.visible = ammo >= 0
	forage_button.visible = forage >= 0
	release_button.visible = dogs >= 0
	release_button.set_pressed_no_signal(release_armed)
	Kit.set_icon(fire_button, "fire" if fire > 0 else "hold_fire")
	_toggles = {run_button: ["Run", "on" if run > 0 else "off"], fire_button: ["Fire", "at will" if fire > 0 else "hold"],
		skirm_button: ["Skirmish", "on" if skirm > 0 else "off"], deploy_button: ["Deploy", "on" if deploy > 0 else "off"],
		refill_button: ["Refill", "on" if refill > 0 else "off"], ammo_button: ["Ammo", ammo_word],
		forage_button: ["Forage", "on" if forage > 0 else "off"],
		release_button: ["Release", "tap an enemy" if release_armed else "%d dogs" % maxi(dogs, 0)]}
	_fit_actions()


## The order toggles read "Fire: hold" etc.; when the bottom row would not
## fit the screen (phones with several orders showing) they drop the order
## word and keep the icon and the state ("hold").
func _fit_actions() -> void:
	if actions_box == null or _toggles.is_empty():
		return
	var need := group_box.get_combined_minimum_size().x + GAP
	for b in actions_box.get_children():
		var btn := b as Button
		if not btn.visible:
			continue
		var t: String = btn.text
		if _toggles.has(btn):
			t = "%s: %s" % _toggles[btn]
		need += _button_w(btn, t) + GAP
	var compact := need > _bottom.size.x if _bottom.size.x > 0.0 else false
	for b in _toggles:
		var btn := b as Button
		var tg: Array = _toggles[b]
		btn.text = str(tg[1]) if compact else "%s: %s" % tg


func _button_w(b: Button, t: String) -> float:
	var fs := b.get_theme_font_size("font_size")
	var w := b.get_theme_font("font").get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if b.icon != null:
		w += b.icon.get_width() + b.get_theme_constant("h_separation")
	w += b.get_theme_stylebox("normal").get_minimum_size().x
	return maxf(w, b.custom_minimum_size.x)


## Walls: show "Man the wall" / "Come down" (battle.gd decides when);
## siege equipment: "Drop" while a selected unit carries a piece.
## The selected unit's carry pattern line ("" hides it).
func set_carry_note(text: String) -> void:
	if carry_note.text != text:
		carry_note.text = text
	carry_note.visible = text != ""


func set_wall_buttons(man: bool, down: bool, drop: bool = false) -> void:
	man_wall_button.visible = man
	come_down_button.visible = down
	drop_button.visible = drop


func update_cards(sim) -> void:
	var tick: int = sim.tick
	for u in _cards:
		var ty: int = sim.u_type[u]
		var f: CardFace = _faces[u]
		var mstate := morale_text(sim, u)
		var art := UT.cls(ty) == UT.CLS_ART
		f.name_text = "%s %d" % [UT.TYPES[sim.u_otype[u]]["short"], u + 1]
		f.number_text = str(u + 1)
		f.alive = sim.u_alive[u]
		f.count0 = sim.u_count0[u]
		f.ammo_text = ""
		var summary := "%s %d/%d" % [f.name_text, f.alive, f.count0]
		var pk: int = sim.u_pack[u]
		if pk >= 0:
			# War dog handlers: the dogs with them (or the pack is out).
			var out: bool = sim.u_state[pk] == BattleSim.U_READY
			f.ammo_text = "out" if out else "%d" % sim.u_kept[pk]
			summary += " dogs %s" % ("out (%d)" % sim.u_alive[pk] if out else str(sim.u_kept[pk]))
		if sim.u_hand[u] >= 0:
			(_cards[u] as Button).visible = sim.u_state[u] != BattleSim.U_KENNEL  # (the pack: only while loose)
			if sim.u_ret[u] != 0:
				summary += " returning"
		if art:
			f.ammo_text = "%d+%d" % [maxi(sim.u_ammo[u], 0), maxi(sim.u_reserve[u], 0)]
			summary = art_card_text(sim, u).replace("\n", " | ")
		elif UT.stat(ty, "m_ammo") > 0:
			var per: int = (sim.u_ammo[u] + maxi(sim.u_alive[u], 1) - 1) / maxi(sim.u_alive[u], 1)
			f.ammo_text = "%d" % per
			summary += " ammo %d" % per
		var sk: int = sim.spec_kind(u)
		if sk >= 0:
			# A special ammunition kind: how much of it is left, and which
			# kind the unit shoots now.
			var spl: int = sim.special_left(u)
			if not art:
				var al := maxi(sim.u_alive[u], 1)
				spl = (spl + al - 1) / al
			summary += " %s %d%s" % [UT.ammo_text(sk, "short"), spl, " (shooting)" if sim.u_akind[u] != 0 else ""]
		# Short state word: art set-up / refill state, else the morale word
		# unless steady.
		var word := mstate if mstate != "Steady" else ""
		if art and sim.u_state[u] == BattleSim.U_READY and sim.u_order[u] != BattleSim.O_WITHDRAW:
			var dt := deploy_text(sim, u)
			word = dt if dt != "Ready" else word
		var carry := carry_text(sim, u)
		if carry == "":
			carry = work_text(sim, u)
		if carry != "":
			summary += " " + carry
			if word == "":
				word = carry
		f.state_text = word
		f.summary = summary + " " + mstate
		if f.char_icon != "":
			f.summary += " | " + Traits.char_text(sim.u_otype[u])
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
		f.refilling = sim.u_refill[u] != 0 or sim.u_rprog[u] > 0 or sim.u_forage[u] != 0
		if not art and (sim.u_refill[u] != 0 or sim.u_rprog[u] > 0):
			f.state_text = "REFILLING" if sim.u_rprog[u] >= BattleSim.REFILL_FULL else "To refill"
		elif sim.u_forage[u] != 0:
			f.state_text = "FORAGING"
		var wq: int = sim.u_carry[u] if sim.sg_on != 0 else -1
		if wq >= 0 and sim.q_kind[wq] == BattleSim.EQ_WAGON:
			# The wagon's stock (standard kinds; special ones it carries).
			var parts: Array[String] = []
			for k in UT.AMMO.size():
				var n_s: int = sim.wagon_stock(wq, k)
				if n_s > 0:
					parts.append("%s %d" % [UT.ammo_text(k, "short"), n_s])
			f.summary += " | stock " + (", ".join(parts) if not parts.is_empty() else "empty") \
				+ (" | horses %d" % sim.q_hn[wq] if UT.wagon_stat(sim.q_tier[wq], "horses") > 0 else "")
		if _tgroups.has(u):
			_group_card(sim, u, f)
		f.queue_redraw()


## The units of the wall-engine card held by u ([u] alone for any other).
func tower_group(u: int) -> Array:
	return _tgroups.get(u, [u])


## Fill the card of a wall-engine kind from its whole group: engines still
## manned, shots left, crew alive.
func _group_card(sim, u: int, f: CardFace) -> void:
	var g: Array = _tgroups[u]
	var shots := 0
	var crew := 0
	var crew0 := 0
	var up := 0
	var hit := false
	for t in g:
		if sim.u_state[t] < BattleSim.U_DESTROYED:
			up += 1
		shots += maxi(sim.u_ammo[t], 0)
		crew += sim.u_alive[t]
		crew0 += sim.u_count0[t]
		hit = hit or sim.tick - sim.u_hit_t[t] < 10
	var word := "Stone" if sim.u_otype[u] == UT.TOWER_STONE else "Bolt"
	f.name_text = "%s towers x%d" % [word, g.size()]
	f.number_text = "x%d" % g.size()
	f.alive = crew
	f.count0 = maxi(crew0, 1)
	f.ammo_text = str(shots)
	f.state_text = "" if up == g.size() else "%d manned" % up
	f.summary = "%s: %d of %d manned, %d shots left, crew %d/%d. Tap to cycle through them." % [f.name_text, up, g.size(), shots, crew, crew0]
	f.state = CardFace.ST_OK if up > 0 else CardFace.ST_GONE
	f.under_fire = hit
	f.fighting = false


## Battery card: crew, engines still working, shots left, set-up state (the
## caller adds the morale word after it).
static func art_card_text(sim, u: int) -> String:
	var ok := 0
	for k in sim.u_neng[u]:
		if sim.e_state[sim.u_eng0[u] + k] == 0:
			ok += 1
	return "%s %d  %d/%d\neng %d/%d  %d shots +%d\n%s" % [UT.TYPES[sim.u_otype[u]]["short"], u + 1,
		sim.u_alive[u], sim.u_count0[u], ok, sim.u_neng[u], maxi(sim.u_ammo[u], 0),
		maxi(sim.u_reserve[u], 0), deploy_text(sim, u)]


## Siege equipment a unit carries: "carrying ladders" / "carrying ram" /
## "pushing a tower", else "".
static func carry_text(sim, u: int) -> String:
	var k := BattleSim.carrying(sim, u)
	if k == BattleSim.EQ_LADDERS:
		return "carrying ladders"
	if k == BattleSim.EQ_RAM:
		return "carrying ram"
	if k == BattleSim.EQ_WAGON:
		return "with the wagon"
	if k != 0 and BattleSim.EQ_SCREEN[k] != 0:
		return "carrying a mantlet"
	if k != 0 and BattleSim.EQ_EXPOSED[k] != 0:
		return "pushing a tower"
	return ""


## The carry pattern of `files` files for a piece of kind k: "column of 4",
## "a file a ladder (5)", "20 files behind the panels".
static func carry_pattern_text(k: int, files: int) -> String:
	if k == BattleSim.EQ_LADDERS:
		return "a file a ladder (%d)" % files
	if k != 0 and BattleSim.EQ_SCREEN[k] != 0:
		return "%d files behind the panels" % files
	return "column of %d" % files


## Unit u's carry line for the unit panel ("Carrying a ram: column of 4"),
## else "".
static func carry_note_text(sim, u: int) -> String:
	var q: int = sim.u_carry[u] if u >= 0 and u < sim.u_carry.size() else -1
	if q < 0:
		return ""
	var k: int = sim.q_kind[q]
	var what := "Carrying ladders"
	if k == BattleSim.EQ_RAM:
		what = "Carrying a ram"
	elif k == BattleSim.EQ_WAGON:
		what = "With the wagon"
	elif BattleSim.EQ_SCREEN[k] != 0:
		what = "Carrying a mantlet"
	elif BattleSim.EQ_EXPOSED[k] != 0:
		what = "Pushing a siege tower"
	return "%s: %s" % [what, carry_pattern_text(k, BattleSim.carry_files(sim, u, q))]


## Men working engines not their own (taken up on the field): "on bolts" /
## "on stones", else "".
static func work_text(sim, u: int) -> String:
	if sim.n_eg == 0 or sim.u_eg[u] < 0 or sim.u_otype[u] == sim.u_type[u]:
		return ""
	return "on " + str(UT.TYPES[sim.u_type[u]]["short"]).to_lower()


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
	if s == BattleSim.U_KENNEL:
		return "With handlers"
	if s == BattleSim.U_ROUTING:
		return "Amok" if sim.u_amok[u] != 0 else "Routing"
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
		for h in ["Start", "Killed", "Routed off", "Withdrawn", "Remain", "Kills"]:
			_cell(h, Color(0.8, 0.8, 0.8))
		for r in res["units"]:
			if int(r["side"]) != side:
				continue
			_cell("%s %d" % [UT.TYPES[int(r["type"])]["short"], int(r["unit"]) + 1], Color.WHITE)
			for k in ["started", "killed", "routed_off", "withdrawn", "remaining"]:
				_cell(str(r[k]), Color.WHITE)
			var ef := Kit.effect_short(int(r.get("kills", 0)), int(r["killed"]))
			var kc := _cell("%d%s" % [int(r.get("kills", 0)), " (" + ef + ")" if ef != "" else ""], Color(1, 0.85, 0.45))
			kc.name = "kills_%d" % int(r["unit"])
			kc.mouse_filter = Control.MOUSE_FILTER_STOP
			kc.gui_input.connect(_kills_tap.bind(r, kc))
		_cell("Total", Color(1, 1, 0.7))
		for k in ["started", "killed", "routed_off", "withdrawn", "remaining"]:
			_cell(str(s[k]), Color(1, 1, 0.7))
		var tk := 0
		for r in res["units"]:
			if int(r["side"]) == side:
				tk += int(r.get("kills", 0))
		_cell(str(tk), Color(1, 1, 0.7))
	result_panel.visible = true


func _kills_tap(e: InputEvent, r: Dictionary, cell: Label) -> void:
	if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		show_kills(r)
		cell.accept_event()


## Under the table: unit r's kills by enemy type (top 5) and effectiveness.
func show_kills(r: Dictionary) -> void:
	result_detail.text = Kit.kills_detail("%s %d" % [UT.TYPES[int(r["type"])]["short"], int(r["unit"]) + 1],
		int(r.get("kills", 0)), int(r["killed"]), r.get("kills_by", []))


func _cell(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", col)
	result_grid.add_child(l)
	return l


## A HUD button; with an icon (game/ui_icons.gd) left of the text, or bare
## when the text is "" (Menu, Deselect).
func _button(text: String, size: Vector2, icon: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", FONT)
	b.pressed.connect(AudioFx.click)
	if icon != "":
		Kit.set_icon(b, icon)
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
	## The general (a command aura): a gold standard in the top right corner.
	var general := false
	## A hero or agent (campaign characters): "crown", "dagger" or "scroll" in the same corner.
	var char_icon := ""

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
		if char_icon != "":
			var cxg := sz.x - (26.0 if foreign else 15.0)
			Kit.UiIcons.draw_icon(self, char_icon, Rect2(cxg, 2, 12, 12),
				Color(0.5, 0.5, 0.5) if state == ST_GONE else Color(1.0, 0.82, 0.25))
		if general:
			var gx := sz.x - (26.0 if foreign else 15.0)
			Kit.UiIcons.draw_icon(self, "general", Rect2(gx, 2, 12, 12),
				Color(0.5, 0.5, 0.5) if state == ST_GONE else Color(1.0, 0.82, 0.25))
		if selected:
			draw_rect(Rect2(Vector2(1, 1), sz - Vector2(2, 2)), Color(1, 1, 1, 0.95), false, 2.0)
		elif fighting and state == ST_OK:
			draw_rect(Rect2(Vector2(0.5, 0.5), sz - Vector2(1, 1)), Color(1, 1, 1, 0.25), false, 1.0)


## Tick marks and labels under the speed slider, lined up with the handle's
## centre at those values.
class SpeedTicks extends Control:
	var slider: HSlider

	func _draw() -> void:
		var font := get_theme_default_font()
		var g := float(slider.get_theme_icon("grabber").get_width())
		var lo := slider.min_value
		var span := slider.max_value - lo
		var prev_end := -100.0
		for q in Lockstep.SPEED_QS:
			var x: float = g / 2.0 + (float(q) - lo) / span * (size.x - g)
			draw_line(Vector2(x, 0), Vector2(x, 3), Color(0.6, 0.62, 0.7), 1.0)
			var t := Lockstep.speed_text(q).trim_suffix("x")
			var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			var tx := maxf(clampf(x - w / 2.0, 0.0, size.x - w), prev_end + 4.0)  # 0.25 / 0.5 sit close
			prev_end = tx + w
			draw_string(font, Vector2(tx, 14), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.78, 0.85))

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
