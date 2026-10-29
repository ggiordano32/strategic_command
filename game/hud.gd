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
## The top-right Menu / Leave / End battle button (battle.gd: the Menu overlay, the Leave ask or End battle); menu_pressed is
## "back to the menu" (the result panels' Back to menu buttons).
signal menu_button_pressed
signal run_pressed
signal halt_pressed
signal fire_pressed
signal skirmish_pressed
signal occupy_pressed
signal waypoints_pressed
signal bounds_pressed
signal deploy_pressed
signal refill_pressed
signal ammo_pressed
signal forage_pressed
signal drop_pressed
signal kill_pressed
signal release_pressed
signal char_pressed(act: String)  # a character's act button: "sabotage", "attempt", "parley"
signal withdraw_pressed
signal withdraw_all_pressed
signal group_pressed(kind: String)
signal ability_pressed(ab: int)   # an armed ability chip tapped again (UT.AB_*): battle.gd cancels the pick
signal ability_set(ab: int, state: int)   # a row of an ability chip's options: UT.AB_AUTO / AB_HOLD / AB_NOW
signal stance_set(stance: int)    # a row of the Stance options: 0 Line, 1 Cover, 2 Hold street
signal add_toggled(on: bool)
signal orders_toggled(on: bool)
signal paths_toggled(on: bool)
signal book_pressed
signal card_long_pressed(unit: int)
signal chip_book_pressed   # the 'Unit book' row of a chip's long-press explanation: battle.gd opens the selected unit's page
signal deselect_pressed
signal undo_pressed
signal controls_pressed
signal gift_pressed
signal cards_reordered
signal ready_pressed
signal works_pressed(mode: String)  # deployment: field works palette ("stakes", "caltrops", "rotate", "remove")

## The only battle speeds offered, in quarter steps: 0.5x, 1x, 2x, 4x.
const SPEED_QS := [2, 4, 8, 16]
const AudioFx := preload("res://game/audio.gd")
const TouchScroll := preload("res://game/touch_scroll.gd")
const DragReorder := preload("res://game/drag_reorder.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Lockstep := preload("res://sim/lockstep.gd")
const UT := preload("res://sim/unit_types.gd")
const CData := preload("res://campaign/cdata.gd")
const Icons := preload("res://game/unit_icons.gd")
const UnitBook := preload("res://game/unit_book.gd")
const Controls := preload("res://game/controls.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const RoleBadge := preload("res://game/role_badge.gd")
const Traits := preload("res://game/unit_traits.gd")
const BTheme := preload("res://game/battle_theme.gd")
const AbilityChip := preload("res://game/ability_chip.gd")
const RoleTile := preload("res://game/role_tile.gd")
const BANNER_SIZE := 30   # the end banner (Cinzel); the pursuit line is 20
const LONG_PRESS_SEC := 0.5
# Layout in logical pixels (game/ui_scale.gd turns them into device sizes).
const BTN_H := 42.0
## The phone capsule's glyph for each role group (the group's lead role).
const ROLE_OF_GROUP := {"line": "line", "skirmish": "skirmish", "shock": "shock", "horse": "horse_shock", "guns": "guns_field"}
const MARGIN := 6.0
const GAP := 5.0
const FONT := 15
const FONT_SMALL := 13
const CARD_H := 34.0
const CARD_MIN_W := 84.0
const CARD_NARROW_W := 58.0  # below CARD_MIN_W: symbol and number only
const CARD_MAX_W := 136.0
const CARD_GAP := 2.0
# Chip clusters (docs/design/ui.md "Chip clusters and the long-press explanation"): a hairline divider between the groups
# of the bar, and a 9 px caption under each group's chips.
const CAP_H := 10.0       # the caption row under the chips
const CAP_FONT := 9
const DIV_W := 3.0        # a divider's slot (the line is 1 px in its middle)
const MORE_HEAD_H := 13.0 # a cluster heading in the More grid
const CLUSTERS := ["Move", "Shoot", "Fight", "Kit"]
## Chip key -> cluster. A chip whose key is not here lands in Fight; a new chip (a new ability) is one line here.
const CLUSTER_OF := {"bounds": "Move", "deploy": "Move", "waypoints": "Move", "release": "Move",
	"batter": "Shoot", "caracole": "Shoot", "fire": "Shoot", "skirmish": "Shoot", "ammo": "Shoot", "refill": "Shoot", "forage": "Shoot",
	"countermarch": "Shoot",
	"stance": "Fight", "occupy": "Fight", "grenades": "Fight", "pistols": "Fight",
	"drop": "Kit", "gift": "Kit", "char_sabotage": "Kit", "char_attempt": "Kit", "char_parley": "Kit"}
const CHIP2_H := 36.0     # a chip's height while the bar is double stacked (the double stack, docs/design/ui.md)
const UP_FIRST := ["Move", "Kit", "Fight", "Shoot"]   # the order the clusters move to the upper row
const CHIP_LONG_SEC := 0.45   # a held chip explains itself
const CHIP_LONG_SLOP := 8.0   # px it may move meanwhile
const EXPLAIN_W := 270.0

var stats_label: Label
var chips_box: HBoxContainer      # the chips that fit the bar (after Halt / Run / Withdraw)
var more_button: AbilityChip           # More: opens the popover with the chips that did not fit
var more_panel: PanelContainer
var more_scroll: ScrollContainer
var more_box: MoreBox       # (one column; more columns when the list is taller than the room above the bar)
var opt_panel: PanelContainer     # the options popover of a multi-state chip (docs/design/ui.md "Chip options")
var opt_box: VBoxContainer
var chips_up: HBoxContainer       # the upper row of the double stack (above the bar's row; clusters whole, right-aligned)
var cap_up: Control               # the captions under the upper row
var two_rows := false             # the double stack is on (chips 36 px high, two rows)
var cap_layer: Control            # draws the clusters' captions under the bar's chips (a top-level child of chips_box)
var explain_panel: PanelContainer # the long-press explanation of a chip
var explain_box: VBoxContainer
var _exp_chip: AbilityChip = null
var _dividers: Array = []         # the bar's hairline dividers (pooled; the first n are visible)
var _more_extras: Array = []      # the headings and padding cells in the More grid (only while it is open)
var _lp_chip: AbilityChip = null  # the chip a press is held on
var _lp_ms := 0
var _lp_pos := Vector2.ZERO
var _lp_fired := false
var ammo_kinds: Array = []        # [standard, special] ammunition words of the selection (set by battle.gd)
var _opt_chip: AbilityChip = null # the chip whose options are open
var _opt_cur := -1                # that chip's current state value when it opened
var _cur_val := {}                # chip key -> current state value (1 on / 0 off, stance 0..2), set by set_selection
var _toggle_emit := {}            # multi-state toggle chip -> Callable that emits its old signal (one press = one flip)
var ab_chips := {}                # UT.AB_* -> its chip
var _chip_order: Array = []       # every chip, in the bar's fixed order
var _sel: Array[int] = []         # the selection as last set
var _refit_pending := false
## Set by battle.gd: unit -> Array of [glyph, word] for the card's state strip and tip (the chips not at their default).
var card_states := Callable()
var _card_key := {}               # unit -> the strip's last key (redraw and re-tip only on change)
var _cap_tiles := {}              # group key -> the role glyph shown in the phone capsule
var _cap_words := {}              # group key -> the segment's word
var stats_button: Button
var stats_panel: PanelContainer
var stats_expanded := false
var card_rows := 1
var banner: Label
## Reinforcements (docs/DESIGN.md "Reinforcements"): "Arriving: n units"
## while a side has reserves to come, and a short "Reinforcements: <army>"
## note when one arrives (unit_labels: sim unit -> its army's name, set by
## the battle view from the scenario).
var arriving_label: Label
var arrival_note: Label
var unit_labels := {}
## Campaign faction index per sim unit (battle.gd copies its unit_faction; view
## only, [] outside a campaign battle): the units' display names (CData.unit_name).
var unit_faction: Array = []
var _note_left := 0.0
var _arr_seen := 0
var pause_button: Button
var orders_button: Button
var paths_button: Button      # town maps: the Paths overlay (impassable ground hatched)
var speed_button: Button
## Speed popover under the speed button: value label, slider (quarter
## steps), tick labels.
var speed_panel: PanelContainer
var speed_slider: HSlider
var speed_value: Label
var _speed_dragging := false
var _speed_last_emit := -1


## The nearest offered speed (SPEED_QS) to a q.
static func snap_speed(q: int) -> int:
	var best: int = SPEED_QS[0]
	for c in SPEED_QS:
		if absi(int(c) - q) < absi(best - q):
			best = int(c)
	return best
var run_button: AbilityChip
var halt_button: Button
var fire_button: AbilityChip
var skirm_button: AbilityChip
var stance_button: AbilityChip
var bounds_button: AbilityChip
var occupy_button: AbilityChip
var waypoints_button: AbilityChip  # Waypoints: taps and line drags add stops (battle.gd waypoint_mode; lit while on)
var deploy_button: AbilityChip
var refill_button: AbilityChip
var ammo_button: AbilityChip
var forage_button: AbilityChip
var drop_button: AbilityChip
## "Kill elephant": shown while a beast unit of the player's runs amok.
var kill_button: Button
## "Release": handlers with dogs in the kennel selected; then a tap on an enemy.
var release_button: AbilityChip
## Heroes and agents: the selected character's acts ("sabotage", "attempt",
## "parley" -> Button; battle.gd shows them and arms the next tap).
var char_buttons := {}   # act -> its chip
var withdraw_button: Button
var gift_button: AbilityChip
var withdraw_all_button: Button
var add_button: Button
var deselect_button: Button
var undo_button: Button  # the command bar's Undo (battle.gd shows it for a few seconds after each order batch)
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
## The top bar's dressing: a gold rule, and (desktop) the setting's emblem and the battle's name (set_title).
var bar_rule: Control
var title_block: HBoxContainer = null
var _left: HBoxContainer
var _title_pack := ""
var _title_text := ""
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
var confirm_panel: PanelContainer   # the Withdraw / Withdraw army confirmation popover
var confirm_label: Label
var confirm_ok: Button
var confirm_cancel: Button
var _confirm_anchor: Control
var _confirm_sig := ""
var _sel_n := 0


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
	Kit.tip(stats_button, "Performance", "Frame rate and tick time. Tap for the full readout.")
	stats_button.pressed.connect(func(): set_stats_expanded(not stats_expanded))
	_left = HBoxContainer.new()   # (the readout, then on a desktop the battle's emblem and name)
	_left.name = "top_left"
	_left.position = Vector2(MARGIN, MARGIN)
	_left.add_theme_constant_override("separation", 14)
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_left)
	_left.add_child(stats_button)
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
	Kit.tip(book_button, "Unit book", "What every unit type does.")
	book_button.pressed.connect(func(): book_pressed.emit())
	orders_button = _button("Orders", Vector2(78, BTN_H), "move")
	orders_button.toggle_mode = true
	BTheme.plate(orders_button, true)
	Kit.tip(orders_button, "Orders", "Show where every unit is headed.")
	orders_button.toggled.connect(func(on: bool):
		set_orders_text(on)
		orders_toggled.emit(on))
	paths_button = _button("Paths", Vector2(66, BTN_H))
	paths_button.name = "paths"
	paths_button.toggle_mode = true
	BTheme.plate(paths_button, true)
	Kit.tip(paths_button, "Paths", "Hatch what men cannot walk on (houses, walls, rocks) when a unit is selected or a route is drawn; streets and alleys stay clear.\nRed: cannot be crossed.\nAmber: rubble: slow going, low cover (a breached wall, a fallen house).")
	paths_button.toggled.connect(func(on: bool): paths_toggled.emit(on))
	paths_button.visible = false   # (shown on town maps)
	pause_button = _button("Pause", Vector2(74, BTN_H))
	pause_button.pressed.connect(func(): pause_pressed.emit())
	speed_button = _button("1x", Vector2(50, BTN_H))
	Kit.tip(speed_button, "Battle speed", "Opens the slider. The + and - keys step it.")
	speed_button.pressed.connect(func():
		set_speed_panel_open(not speed_panel.visible)
		speed_pressed.emit())
	withdraw_all_button = _button("Withdraw army", Vector2(0, BTN_H), "withdraw")
	Kit.tip(withdraw_all_button, "Withdraw army", "Every unit leaves the battle; asks to confirm.")
	withdraw_all_button.pressed.connect(func(): _open_confirm(withdraw_all_button, "Withdraw the whole army? Every unit leaves the battle.", "Withdraw army", "all"))
	withdraw_all_button.disabled = not interactive
	var menu := _button("", Vector2(50, BTN_H), "menu")
	menu.name = "menu"
	Kit.tip(menu, "Menu", "Resume, options, controls, or leave the battle.")
	menu.pressed.connect(func(): menu_button_pressed.emit())
	menu_button = menu
	controls_button = _button("Keys", Vector2(54, BTN_H), "key")
	Kit.tip(controls_button, "Controls", "Every touch, mouse and key input (F1).")
	controls_button.pressed.connect(func(): controls_pressed.emit())
	for b in [withdraw_all_button, book_button, controls_button, orders_button, paths_button, pause_button, speed_button, menu]:
		top.add_child(b)
	_top = top
	_ui_controls.append(top)
	# A gold rule under the top bar; on a desktop the setting's emblem and the battle's name in the title face.
	bar_rule = BTheme.bar_rule()
	bar_rule.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar_rule.offset_top = MARGIN + BTN_H + 3.0
	bar_rule.offset_bottom = bar_rule.offset_top + 1.0
	root.add_child(bar_rule)
	var bar_band := BTheme.bar_band()   # the wood band behind the buttons, under everything else
	bar_band.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar_band.offset_bottom = bar_rule.offset_top + 1.0
	root.add_child(bar_band)
	root.move_child(bar_band, 0)
	get_viewport().size_changed.connect(_layout_title)

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
	# All / Line / Skirm / Shock / Horse / Guns / None: one capsule (momentary segments, nothing stays lit).
	# The groups are the roles' filter groups (UT.FILTER_GROUPS, UT.filter_group).
	# On a phone width the role segments show the role badge glyphs, 34 px each (`_apply_capsule`; the row has no spare room at 844 px).
	var gsel := BTheme.capsule([["All", "all"], ["Line", "line"], ["Skirm", "skirmish"], ["Shock", "shock"], ["Horse", "horse"],
		["Guns", "guns"], ["None", "none"]],
		func(kind: String):
			if kind == "none":
				deselect_pressed.emit()
			else:
				group_pressed.emit(kind), "group", FONT, 50.0, BTN_H)
	gsel.name = "group_capsule"
	var gtips := {"all": ["Select all", "Every unit you command."],
		"line": ["Line", "Select the line troops: swords, spears, pikes and musketeers. Generals on foot too."],
		"skirmish": ["Skirmishers", "Select the skirmishers (loose order) and the missile troops (archers)."],
		"shock": ["Shock", "Select the shock foot: cutlass men, rodeleros, holcan, grenadiers, war dogs."],
		"horse": ["Horse", "Select all mounted units: shock and light horse, generals' guards, camels and elephants."],
		"guns": ["Guns", "Select the field and siege artillery."],
		"none": ["Deselect", "Clear the selection (Esc)."]}
	for gb in gsel.buttons():
		var gk: String = str(gb.get_meta("seg_value"))
		Kit.tip(gb, gtips[gk][0], gtips[gk][1])
		gb.disabled = not interactive
		_cap_words[gk] = gb.text
		if ROLE_OF_GROUP.has(gk):
			var tile := RoleTile.new(str(ROLE_OF_GROUP[gk]), 24.0)
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			tile.grow_horizontal = Control.GROW_DIRECTION_BOTH
			tile.grow_vertical = Control.GROW_DIRECTION_BOTH
			tile.tooltip_text = ""
			tile.visible = false
			gb.add_child(tile)
			_cap_tiles[gk] = tile
		if gk == "none":
			deselect_button = gb
			gb.name = "deselect"
		else:
			group_buttons[gk] = gb
	groups.add_child(gsel)
	_apply_capsule()
	get_viewport().size_changed.connect(_apply_capsule)
	add_button = _button("Add", Vector2(58, BTN_H), "plus")
	add_button.toggle_mode = true
	BTheme.plate(add_button, true)
	Kit.tip(add_button, "Add", "Taps on units or cards add to, or remove from, the selection.")
	add_button.toggled.connect(func(on: bool): add_toggled.emit(on))
	add_button.disabled = not interactive
	groups.add_child(add_button)
	undo_button = _button("Undo", Vector2(58, BTN_H))
	undo_button.name = "undo"
	Kit.tip(undo_button, "Undo", "Take back the last order (Ctrl+Z).")
	undo_button.pressed.connect(func(): undo_pressed.emit())
	undo_button.disabled = not interactive
	undo_button.visible = false
	groups.add_child(undo_button)
	kill_button = _button("Kill elephant", Vector2(0, BTN_H), "kill_beast")
	kill_button.name = "kill_beast"
	Kit.tip(kill_button, "Kill elephants", "Their drivers kill the rampaging elephants in 5 s, before more of your men are trampled.")
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
	# The fixed three, always on the bar with a selection: Halt, Run (its state word), Withdraw.
	halt_button = _button("Halt", Vector2(54, BTN_H), "cancel")
	Kit.tip(halt_button, "Halt", "Stop where they stand and drop their orders.")
	halt_button.pressed.connect(func(): halt_pressed.emit())
	run_button = _chip("run", "Run", "run", "Run", "Run or walk: the selection's pace.", "off")
	_multi(run_button, func(): run_pressed.emit())
	withdraw_button = _button("Withdraw", Vector2(0, BTN_H), "withdraw")
	Kit.tip(withdraw_button, "Withdraw", "Leave the battle by your own map edge; asks to confirm.")
	withdraw_button.pressed.connect(func():
		var n := maxi(_sel_n, 1)
		_open_confirm(withdraw_button, "Withdraw %d unit%s by your map edge?" % [n, "" if n == 1 else "s"], "Withdraw", "unit"))
	# The chips, in the bar's fixed order (see _fit_actions: what does not fit goes under More).
	var ab_tips := {
		UT.AB_BATTER: ["Target", "Guns that batter. Auto: they shoot men, or what they were ordered at. Hold: stop a battering under way. Use now: tap a wall stretch, a gate (the stretch beside it) or a building to batter it. Torch raiders batter with axes: Use now at a gate or a stretch of palisade, and they go to it and hack until it gives (a stone wall they cannot hurt)."],
		UT.AB_CARACOLE: ["Caracole", "Horse with firearms. Auto: ride up, fire, wheel back and reload, again. Hold: an attack is a charge. Use now: tap an enemy unit and they caracole at it."],
		UT.AB_GRENADE: ["Grenades", "Auto: thrown at formed blocks, held houses and shut gates in reach (fire pots: held houses and shut gates only, setting them alight). Hold: never thrown, the unit fights as shock foot. Use now: tap an enemy unit or a shut gate and it is thrown at at once."],
		UT.AB_PISTOL: ["Pistols", "Auto: a point-blank shot in each man's first rounds of a melee, the spent men changing places to reload. Hold: blades only."],
		UT.AB_ROLL: ["Countermarch", "Musket lines: rolling fire by ranks. Auto: an opening volley, then one rank fires after another, keeping the enemy shaken; the last volley of every loaded man when an enemy comes within 40 m. Hold: volleys only. Use now: rolling fire at any range."]}
	var ab_icons := {UT.AB_BATTER: "target", UT.AB_CARACOLE: "caracole", UT.AB_GRENADE: "grenade", UT.AB_PISTOL: "pistol",
		UT.AB_ROLL: "countermarch"}
	for ab in [UT.AB_BATTER, UT.AB_CARACOLE, UT.AB_GRENADE, UT.AB_PISTOL, UT.AB_ROLL]:
		var abk: int = ab
		var ac := _chip(UT.AB_NAMES[abk].to_lower(), "Target" if abk == UT.AB_BATTER else UT.AB_NAMES[abk],
			str(ab_icons[abk]), str(ab_tips[abk][0]), str(ab_tips[abk][1]), "Auto", false, abk)
		ac.pressed.connect(func():
			if ac.armed:
				ability_pressed.emit(abk)   # (the armed chip again cancels the pick)
			else:
				_open_options(ac))
		ac.visible = false
		ab_chips[abk] = ac
	fire_button = _chip("fire", "Fire", "fire", "Fire", "Missile troops fire at will, or hold fire.", "at will")
	_multi(fire_button, func(): fire_pressed.emit())
	skirm_button = _chip("skirmish", "Skirmish", "skirmish", "Skirmish", "Missile troops fall back from approaching melee troops.", "on")
	_multi(skirm_button, func(): skirmish_pressed.emit())
	stance_button = _chip("stance", "Stance", "stance_line", "Stance", "Line keeps the formation. Cover takes cover spots. Hold street fills the street.", "Line")
	_multi(stance_button, Callable())
	stance_button.visible = false
	occupy_button = _chip("occupy", "Occupy", "inside", "Occupy", "Lights the buildings these men can hold: point at one to see what its windows and roof cover, then click it (tap twice on a touch screen) to send them in (I). Leave goes out by the door.", "", true)
	occupy_button.name = "occupy"
	occupy_button.pressed.connect(func(): occupy_pressed.emit())
	occupy_button.visible = false
	bounds_button = _chip("bounds", "Bounds", "bound", "Bounds", "Half the men run to the next cover while the others shoot, then they swap.", "off")
	_multi(bounds_button, func(): bounds_pressed.emit())
	bounds_button.visible = false
	deploy_button = _chip("deploy", "Deploy", "deploy", "Deploy", "Artillery sets up to shoot or packs up to move. Both take time.", "on")
	_multi(deploy_button, func(): deploy_pressed.emit())
	ammo_button = _chip("ammo", "Ammo", "ammo", "Ammunition", "Shoot the second kind (fire arrows, heavy bolts) or the standard one (V).", "arrows")
	ammo_button.name = "ammo"
	_multi(ammo_button, func(): ammo_pressed.emit())
	refill_button = _chip("refill", "Refill", "pick_up", "Refill", "Artillery brings up shots from the baggage; missile troops refill at an ammunition wagon. No moving or shooting meanwhile.", "off")
	_multi(refill_button, func(): refill_pressed.emit())
	forage_button = _chip("forage", "Forage", "forage", "Forage", "Missile troops in woods make arrows or javelins, slowly. No moving or shooting meanwhile (J).", "off")
	forage_button.name = "forage"
	_multi(forage_button, func(): forage_pressed.emit())
	drop_button = _chip("drop", "Drop", "drop", "Drop", "Put down the ladders, ram, wagon or engines where the unit stands (X). Any foot unit takes them up again.", "")
	drop_button.pressed.connect(func(): drop_pressed.emit())
	drop_button.visible = false
	release_button = _chip("release", "Release", "release", "Release", "Let the war dogs loose, then tap an enemy unit within 80 m (U).", "0 dogs", true)
	release_button.name = "release"
	release_button.low = true
	_multi(release_button, func(): release_pressed.emit())
	release_button.visible = false
	for a in [["sabotage", "Sabotage", "fire", "Assassin: tap an enemy battery to wreck its engines, or a shut gate to unbar it from inside (Shift+B)."],
			["attempt", "Attempt", "dagger", "Assassin: tap an enemy hero or general. One strike: 40 % kills, 30 % wounds (T)."],
			["parley", "Parley", "scroll", "Diplomat: tap a routing or wavering enemy unit. It may surrender (Shift+P)."]]:
		var act: String = a[0]
		var cb := _chip("char_" + act, str(a[1]), str(a[2]), str(a[1]), str(a[3]), "", true)
		cb.name = "char_" + act
		cb.pressed.connect(func(): char_pressed.emit(act))
		cb.visible = false
		char_buttons[act] = cb
	# Live co-op: give the selected units to the ally (hidden otherwise).
	gift_button = _chip("gift", "Gift", "gift", "Gift", "Give the selected units to your ally. They can give them back.", "")
	gift_button.pressed.connect(func(): gift_pressed.emit())
	gift_button.visible = false
	waypoints_button = _chip("waypoints", "Waypoints", "move", "Waypoints", "While lit, each tap on the ground or line you drag adds a stop after the unit's current move: they march from one to the next (up to 8), the last one's facing kept. Tap a numbered dot to take that stop out. It goes off when the selection changes (or a two-finger tap). With a mouse: Shift + right click, Shift + right drag; Shift + left click a dot takes it out.", "", true)
	waypoints_button.name = "waypoints"
	waypoints_button.low = true
	waypoints_button.pressed.connect(func(): waypoints_pressed.emit())
	_chip_order = [ab_chips[UT.AB_BATTER], ab_chips[UT.AB_CARACOLE], fire_button, ab_chips[UT.AB_ROLL], skirm_button, stance_button, occupy_button,
		ab_chips[UT.AB_GRENADE], ab_chips[UT.AB_PISTOL], bounds_button, deploy_button, ammo_button, refill_button, forage_button,
		drop_button, release_button, char_buttons["sabotage"], char_buttons["attempt"], char_buttons["parley"], gift_button, waypoints_button]
	for b in [halt_button, run_button]:
		actions.add_child(b)
	chips_box = HBoxContainer.new()
	chips_box.name = "chips"
	chips_box.add_theme_constant_override("separation", int(GAP))
	chips_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips_box.custom_minimum_size.y = BTN_H + CAP_H   # (the caption row under the chips)
	actions.add_child(chips_box)
	chips_up = HBoxContainer.new()
	chips_up.name = "chips_up"
	chips_up.add_theme_constant_override("separation", int(GAP))
	chips_up.alignment = BoxContainer.ALIGNMENT_END
	chips_up.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips_up.custom_minimum_size.y = CHIP2_H + CAP_H
	chips_up.visible = false
	bottom.add_child(chips_up)
	bottom.move_child(chips_up, 0)
	_ui_controls.append(chips_up)
	for c in _chip_order:
		c.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		chips_box.add_child(c)
	cap_layer = ClusterCaptions.new()
	chips_box.add_child(cap_layer)
	chips_box.sort_children.connect(_place_clusters)
	cap_up = ClusterCaptions.new()
	chips_up.add_child(cap_up)
	chips_up.sort_children.connect(_place_clusters)
	for b in [halt_button, run_button, withdraw_button, group_box]:
		(b as Control).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	group_box.custom_minimum_size.y = BTN_H
	for n in [engine_note, carry_note]:
		(n as Label).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		(n as Label).custom_minimum_size.y = BTN_H
		(n as Label).vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	more_button = _chip("more", "More", "more", "More", "The orders that did not fit the bar.", "", true)
	more_button.name = "more"
	more_button.visible = false
	more_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	more_button.pressed.connect(func(): _set_more_open(more_button.button_pressed))
	actions.add_child(more_button)
	actions.add_child(withdraw_button)   # the row's last element: at the bar's right edge
	# The popover above More: every chip that did not fit, one under another (nothing is ever clipped).
	more_panel = PanelContainer.new()
	more_panel.name = "more_panel"
	more_panel.add_theme_stylebox_override("panel", Kit.trim_box(Color(Kit.PANEL_BG, 0.96), 8.0))
	more_panel.visible = false
	root.add_child(more_panel)
	more_box = MoreBox.new()
	more_box.sep = GAP
	more_scroll = ScrollContainer.new()   # (only scrolls when no column count fits the viewport: the worst case)
	more_scroll.name = "more_scroll"
	more_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	more_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	more_panel.add_child(more_scroll)
	more_scroll.add_child(more_box)
	_ui_controls.append(more_panel)
	opt_panel = PanelContainer.new()
	opt_panel.name = "opt_panel"
	opt_panel.add_theme_stylebox_override("panel", Kit.trim_box(Color(Kit.PANEL_BG, 0.97), 6.0))
	opt_panel.visible = false
	root.add_child(opt_panel)
	opt_box = VBoxContainer.new()
	opt_box.add_theme_constant_override("separation", 2)
	opt_panel.add_child(opt_box)
	_ui_controls.append(opt_panel)
	explain_panel = PanelContainer.new()
	explain_panel.name = "explain_panel"
	explain_panel.add_theme_stylebox_override("panel", Kit.trim_box(Color(Kit.PANEL_BG, 0.97), 8.0))
	explain_panel.visible = false
	root.add_child(explain_panel)
	explain_box = VBoxContainer.new()
	explain_box.add_theme_constant_override("separation", 4)
	explain_panel.add_child(explain_box)
	_ui_controls.append(explain_panel)
	confirm_panel = PanelContainer.new()
	confirm_panel.name = "confirm_panel"
	confirm_panel.add_theme_stylebox_override("panel", Kit.trim_box(Color(Kit.PANEL_BG, 0.97), 6.0))
	confirm_panel.visible = false
	root.add_child(confirm_panel)
	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 4)
	confirm_panel.add_child(cbox)
	confirm_label = Label.new()
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_label.custom_minimum_size.x = 220.0
	confirm_label.add_theme_font_size_override("font_size", FONT)
	cbox.add_child(confirm_label)
	confirm_ok = _button("Withdraw", Vector2(0, 42), "withdraw")
	confirm_ok.name = "confirm_ok"
	confirm_ok.pressed.connect(_confirm_yes)
	cbox.add_child(confirm_ok)
	confirm_cancel = _button("Cancel", Vector2(0, 42), "cancel")
	confirm_cancel.name = "confirm_cancel"
	confirm_cancel.pressed.connect(close_confirm)
	cbox.add_child(confirm_cancel)
	_ui_controls.append(confirm_panel)
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
		b.visible = sim.u_state[u] != BattleSim.U_KENNEL and sim.u_state[u] != BattleSim.U_RESERVE  # (a war dog pack: shown once let loose; a reinforcement once it arrives)
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
		face.role = UT.role(sim.u_otype[u])   # the role badge and its colour band
		if face.role != "":
			Kit.tip(b, str(UT.ROLES[face.role]["name"]), RoleBadge.plays(face.role))
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
	banner.name = "banner"
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.position.y = BTN_H + 3 * MARGIN
	banner.add_theme_font_size_override("font_size", BANNER_SIZE)
	var bf := Kit.title_font()
	if bf != null:
		banner.add_theme_font_override("font", bf)   # Victory / Defeat / Draw in the title face over a trim plate
	banner.add_theme_color_override("font_color", Kit.COL_GOLD)
	banner.add_theme_stylebox_override("normal", Kit.trim_box(Color(Kit.PANEL_BG, 0.88), 16.0))
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.visible = false
	root.add_child(banner)
	arriving_label = Label.new()
	arriving_label.name = "arriving"
	arriving_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	arriving_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	arriving_label.position.y = BTN_H + 2 * MARGIN
	arriving_label.add_theme_font_size_override("font_size", FONT_SMALL)
	arriving_label.add_theme_color_override("font_outline_color", Color.BLACK)
	arriving_label.add_theme_constant_override("outline_size", 4)
	arriving_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arriving_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arriving_label.visible = false
	root.add_child(arriving_label)
	arrival_note = Label.new()
	arrival_note.name = "arrival_note"
	arrival_note.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	arrival_note.grow_horizontal = Control.GROW_DIRECTION_BOTH
	arrival_note.position.y = BTN_H + 2 * MARGIN + 20
	arrival_note.add_theme_font_size_override("font_size", FONT + 3)
	arrival_note.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	arrival_note.add_theme_color_override("font_outline_color", Color.BLACK)
	arrival_note.add_theme_constant_override("outline_size", 6)
	arrival_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrival_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrival_note.visible = false
	root.add_child(arrival_note)

	# Benchmark summary panel, centre.
	bench_panel = PanelContainer.new()
	bench_panel.add_theme_stylebox_override("panel", Kit.trim_box(Kit.PANEL_BG, 14.0))
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
	result_panel.add_theme_stylebox_override("panel", Kit.trim_box(Color(Kit.PANEL_BG, 0.97), 16.0))
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	result_panel.visible = false
	root.add_child(result_panel)
	var rvb := VBoxContainer.new()
	rvb.add_theme_constant_override("separation", 8)
	result_panel.add_child(rvb)
	result_title = Kit.title("", 22)
	result_title.name = "result_title"
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rvb.add_child(result_title)
	rvb.add_child(Kit.rule())
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
	deploy_panel.add_theme_stylebox_override("panel", Kit.trim_box(Kit.PANEL_BG, 10.0))
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
	Kit.tip(ready_button, "Start battle", "The battle starts when every player is ready, or when the time runs out (Enter).")
	ready_button.pressed.connect(func(): ready_pressed.emit())
	dh.add_child(ready_button)
	_ui_controls.append(deploy_panel)

	# Field works palette, under the deployment bar: a button per kind with
	# the count left to place, then Rotate and Remove (toggles: the mode the
	# next tap or drag on the field uses).
	works_panel = PanelContainer.new()
	works_panel.add_theme_stylebox_override("panel", Kit.trim_box(Kit.PANEL_BG, 10.0))
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
		BTheme.plate(b, true)
		b.name = "works_" + mode
		Kit.tip(b, m[1], m[2])
		b.pressed.connect(func(): works_pressed.emit(mode))
		wh.add_child(b)
		works_buttons[mode] = b
	_ui_controls.append(works_panel)

	_build_speed_panel(root)

	# Unit book, above everything else.
	book = UnitBook.new()
	book.side_color = Icons.SIDE_COLORS[player_side]
	for u in sim.n_units:
		if UT.pack_of(sim.u_otype[u]) != "rome":
			book.pack = UT.pack_of(sim.u_otype[u])  # (a battle of the West's rows: their book)
	root.add_child(book)
	_ui_controls.append(book)
	controls = Controls.new()
	root.add_child(controls)
	_ui_controls.append(controls)


## The battle's name for the top bar (desktop only: the setting's emblem and the name in the title face).
func set_title(text: String, pack: String) -> void:
	_title_text = text
	_title_pack = pack
	if title_block != null:
		title_block.queue_free()
		title_block = null
	_layout_title()


func _layout_title() -> void:
	if _root == null or _top == null:
		return
	var want := BTheme.desktop(get_viewport().get_visible_rect().size.x) and _title_text != ""
	if not want:
		if title_block != null:
			title_block.visible = false
		return
	if title_block == null:
		title_block = BTheme.title_block(_title_pack, _title_text)
		title_block.name = "title_block"
		_left.add_child(title_block)
	title_block.visible = true
	# (as wide as the room between the readout and the buttons on the right; the readout is about 170 px)
	var room := get_viewport().get_visible_rect().size.x - _top.get_combined_minimum_size().x - 2.0 * MARGIN - 190.0 - 40.0 - 28.0
	var tf: Font = Kit.title_font() if Kit.title_font() != null else ThemeDB.fallback_font
	var tw := tf.get_string_size(_title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 4.0
	(title_block.get_node("bar_title") as Control).custom_minimum_size.x = clampf(minf(tw, room), 40.0, 520.0)


## The end banner's colour: green for a win, red for a loss, gold otherwise.
func tint_banner(text: String) -> void:
	var col := Kit.COL_GOLD
	if text.begins_with("Victory") or text == "Blue wins":
		col = Kit.COL_GOOD
	elif text.begins_with("Defeat") or text == "Red wins":
		col = Kit.COL_BAD
	banner.add_theme_color_override("font_color", col)


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
	var row_h := BTN_H
	if chips_box != null and chips_box.visible:
		row_h = maxf(BTN_H, chips_box.custom_minimum_size.y)
	var up_h := 0.0
	if chips_up != null and chips_up.visible:
		up_h = chips_up.custom_minimum_size.y + GAP   # (the double stack's upper row)
	return MARGIN * 3 + row_h + up_h + GAP + card_rows * (CARD_H + CARD_GAP) + 6.0


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
	if _lp_chip != null and not _lp_fired and Time.get_ticks_msec() - _lp_ms >= int(CHIP_LONG_SEC * 1000.0):
		_lp_fired = true
		var lc := _lp_chip
		if lc.is_visible_in_tree():
			# (off and on again cancels the press: the release then gives no tap)
			lc.disabled = true
			lc.disabled = false
			_open_explain(lc)
	if _note_left > 0.0:
		_note_left -= delta
		if _note_left <= 0.0:
			arrival_note.visible = false


## The Withdraw / Withdraw army confirmation: a small popover above its button (docs/design/ui.md "Withdraw at the right").
func _open_confirm(anchor: Control, text: String, ok_text: String, sig: String) -> void:
	if confirm_panel.visible and _confirm_anchor == anchor:
		close_confirm()
		return
	set_speed_panel_open(false)
	_set_more_open(false)
	_close_options()
	_confirm_anchor = anchor
	_confirm_sig = sig
	confirm_label.text = text
	confirm_ok.text = ok_text
	confirm_panel.visible = true
	_place_confirm()


func _confirm_yes() -> void:
	var sig := _confirm_sig
	close_confirm()
	if sig == "all":
		withdraw_all_pressed.emit()
	elif sig == "unit":
		withdraw_pressed.emit()


func close_confirm() -> void:
	if confirm_panel == null:
		return
	confirm_panel.visible = false
	_confirm_anchor = null
	_confirm_sig = ""


func _place_confirm() -> void:
	if confirm_panel == null or not confirm_panel.visible:
		return
	if _confirm_anchor == null or not _confirm_anchor.is_visible_in_tree():
		close_confirm()
		return
	var vp := get_viewport().get_visible_rect().size
	confirm_panel.reset_size()
	var sz := confirm_panel.get_combined_minimum_size()
	var r := _confirm_anchor.get_global_rect()
	var x := clampf(r.end.x - sz.x, MARGIN, maxf(vp.x - sz.x - MARGIN, MARGIN))
	var y := r.position.y - sz.y - GAP
	if y < MARGIN:
		y = clampf(r.end.y + GAP, MARGIN, maxf(vp.y - sz.y - MARGIN, MARGIN))
	confirm_panel.position = Vector2(x, y)
	confirm_panel.size = sz


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


## Live co-op: mark unit u's card as commanded by another player (not
## orderable here) in their colour, or as this player's own; band: a strip
## in the commander's colour along the card's top (several players on a
## side: whose unit is whose at a glance).
func set_card_owner(u: int, foreign: bool, col: Color, band: bool = false) -> void:
	if not _faces.has(u):
		return
	var f: CardFace = _faces[u]
	if f.foreign != foreign or f.owner_col != col or f.owner_band != band:
		f.foreign = foreign
		f.owner_col = col
		f.owner_band = band
		f.queue_redraw()


func _build_speed_panel(root: Control) -> void:
	speed_panel = PanelContainer.new()
	speed_panel.name = "speed_panel"
	speed_panel.add_theme_stylebox_override("panel", Kit.trim_box(Kit.PANEL_BG, 10.0))
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
	speed_slider.min_value = SPEED_QS[0]
	speed_slider.max_value = Lockstep.SPEED_Q_MAX
	speed_slider.step = 1
	speed_slider.value = 4
	speed_slider.focus_mode = Control.FOCUS_NONE
	speed_slider.scrollable = false  # the wheel zooms the map, never the speed
	speed_slider.custom_minimum_size = Vector2(270, 40)
	# Touch-sized handle and a visible track.
	var grab := _disc(30, Kit.COL_BONE)
	speed_slider.add_theme_icon_override("grabber", grab)
	speed_slider.add_theme_icon_override("grabber_highlight", _disc(30, Kit.COL_GOLD))
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.28, 0.26, 0.2)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	speed_slider.add_theme_stylebox_override("slider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Kit.COL_RULE
	speed_slider.add_theme_stylebox_override("grabber_area", fill)
	speed_slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	speed_slider.value_changed.connect(func(x: float):
		var sq := snap_speed(int(round(x)))
		if float(sq) != x:
			speed_slider.set_value_no_signal(sq)  # snaps to 0.5 / 1 / 2 / 4
		speed_value.text = Lockstep.speed_text(sq)
		if sq != _speed_last_emit:
			_speed_last_emit = sq
			speed_chosen.emit(sq, false))
	speed_slider.drag_started.connect(func(): _speed_dragging = true)
	# A tap on the track moves the handle without a drag in between; the
	# value at release is what counts either way.
	speed_slider.drag_ended.connect(func(_changed: bool):
		_speed_dragging = false
		_speed_last_emit = -1
		speed_chosen.emit(snap_speed(int(round(speed_slider.value))), true))
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
		close_confirm()
		_close_options()
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
	# The confirmation popover: Esc or a press outside it (and its button) closes it with no action.
	if confirm_panel != null and confirm_panel.visible:
		if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
			close_confirm()
			get_viewport().set_input_as_handled()
		else:
			var cp := Vector2(-1, -1)
			if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
				cp = (event as InputEventScreenTouch).position
			elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
				cp = (event as InputEventMouseButton).position
			if cp.x >= 0.0 and not confirm_panel.get_global_rect().has_point(cp) and not _confirm_anchor.get_global_rect().has_point(cp):
				close_confirm()
	# The chip explanation: Esc or a press anywhere outside it closes it.
	if explain_panel != null and explain_panel.visible:
		if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
			_close_explain()
			get_viewport().set_input_as_handled()
		else:
			var xp := Vector2(-1, -1)
			if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
				xp = (event as InputEventScreenTouch).position
			elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
				xp = (event as InputEventMouseButton).position
			if xp.x >= 0.0 and not explain_panel.get_global_rect().has_point(xp):
				_close_explain()
	# Esc closes the options popover without a change; a press outside it (and its chip) closes it too.
	if opt_panel != null and opt_panel.visible:
		if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
			_close_options()
			get_viewport().set_input_as_handled()
		else:
			var op := Vector2(-1, -1)
			if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
				op = (event as InputEventScreenTouch).position
			elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
				op = (event as InputEventMouseButton).position
			if op.x >= 0.0 and not opt_panel.get_global_rect().has_point(op) and not _opt_chip.get_global_rect().has_point(op):
				_close_options()
	# A press outside the open More popover (and its button) closes it.
	if more_panel != null and more_panel.visible:
		var mp := Vector2(-1, -1)
		if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
			mp = (event as InputEventScreenTouch).position
		elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			mp = (event as InputEventMouseButton).position
		if mp.x >= 0.0 and not more_panel.get_global_rect().has_point(mp) and not more_button.get_global_rect().has_point(mp) \
				and not (opt_panel != null and opt_panel.visible and opt_panel.get_global_rect().has_point(mp)) \
				and not (explain_panel != null and explain_panel.visible and explain_panel.get_global_rect().has_point(mp)):
			_set_more_open(false)
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
		release_armed: bool = false, stance: int = -1, bounds: int = -1, occupy: int = -1) -> void:
	_sel_n = units.size()
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
	if chips_up != null and not actions_box.visible:
		chips_up.visible = false
	engine_note.visible = not units.is_empty() and engine_only
	run_button.visible = run >= 0
	fire_button.visible = fire >= 0
	skirm_button.visible = skirm >= 0
	stance_button.visible = stance >= 0
	bounds_button.visible = bounds >= 0
	occupy_button.visible = occupy >= 0
	occupy_button.label_name = "Leave" if occupy > 0 else "Occupy"
	occupy_button.text = occupy_button.text_for(occupy_button.compact_mode)
	var stance_word: String = ["Line", "Cover", "Hold"][clampi(stance, 0, 2)]
	Kit.set_icon(stance_button, ["stance_line", "stance_cover", "stance_hold"][clampi(stance, 0, 2)])
	deploy_button.visible = deploy >= 0
	refill_button.visible = refill >= 0
	ammo_button.visible = ammo >= 0
	forage_button.visible = forage >= 0
	release_button.visible = dogs >= 0
	release_button.set_pressed_no_signal(release_armed)
	Kit.set_icon(fire_button, "fire" if fire > 0 else "hold_fire")
	run_button.set_state("on" if run > 0 else "off")
	fire_button.set_state("at will" if fire > 0 else "hold")
	skirm_button.set_state("on" if skirm > 0 else "off")
	stance_button.set_state(stance_word)
	bounds_button.set_state("on" if bounds > 0 else "off")
	deploy_button.set_state("on" if deploy > 0 else "off")
	refill_button.set_state("on" if refill > 0 else "off")
	ammo_button.set_state(ammo_word)
	forage_button.set_state("on" if forage > 0 else "off")
	release_button.set_state("tap an enemy" if release_armed else "%d dogs" % maxi(dogs, 0))
	_cur_val = {"run": 1 if run > 0 else 0, "fire": 1 if fire > 0 else 0, "skirmish": 1 if skirm > 0 else 0,
		"stance": clampi(stance, 0, 2), "bounds": 1 if bounds > 0 else 0, "deploy": 1 if deploy > 0 else 0,
		"refill": 1 if refill > 0 else 0, "forage": 1 if forage > 0 else 0, "ammo": 1 if ammo > 0 else 0,
		"release": 1 if release_armed else 0}
	if _sel != units:
		_set_more_open(false)
		_close_options()
		_close_explain()
	_sel = units.duplicate()
	_update_common()
	_fit_actions()


## Whether unit u is one the chip `c` is about (a chip that not every selected unit has is dimmed).
## The situational chips (refill, forage, drop, release, the acts, gift, waypoints) are always common.
func _chip_applies(c: Button, u: int) -> bool:
	if _sim == null or u < 0 or u >= _sim.n_units:
		return true
	var ty: int = _sim.u_type[u]
	var art := UT.cls(ty) == UT.CLS_ART
	var ac := c as AbilityChip
	if ac.ab >= 0:
		return (_sim.t_abil[ty] & (1 << ac.ab)) != 0
	match ac.key:
		"fire":
			return UT.stat(ty, "m_ammo") > 0
		"skirmish":
			return UT.stat(ty, "m_ammo") > 0 and not art
		"run":
			return not art
		"stance", "bounds", "occupy":
			return BattleSim.stance_ok(ty)
		"deploy":
			return art and UT.stat(ty, "fixed") == 0
		"ammo":
			return _sim.spec_kind(u) >= 0
	return true


## Dim the chips some of the selected units do not have (tip: not all selected units).
func _update_common() -> void:
	for c in _chip_order:
		var ch := c as AbilityChip
		var all := true
		for u in _sel:
			if not _chip_applies(ch, u):
				all = false
				break
		ch.set_common(all)


## The ability chips of the selection: info is UT.AB_* -> {"word": state word, "armed": bool}; an ability not in
## it has no chip. Call before set_selection (which fits the bar).
func set_abilities(info: Dictionary) -> void:
	for ab in ab_chips:
		var c: AbilityChip = ab_chips[ab]
		c.visible = info.has(ab)
		if c.visible:
			c.set_state(str(info[ab]["word"]), bool(info[ab]["armed"]))
	for c in _chip_order:
		(c as AbilityChip).pinned = (c as AbilityChip).armed


## The bottom bar's width the fit works with, logical px.
func _bar_width() -> float:
	return get_viewport().get_visible_rect().size.x - 2.0 * MARGIN


## Fit the action row to the screen: Halt / Run / Withdraw are fixed; the chips follow in their fixed order (an armed
## ability first, then the chips every selected unit has, then the rest); when the full texts do not fit they drop
## their name and keep the state (the icon says which); what still does not fit goes under More. Nothing is clipped.
## Measured from the texts' metrics at once and again one frame later (after the layout), and on a resize.
func _fit_actions() -> void:
	if actions_box == null:
		return
	_fit_now()
	if not _refit_pending and is_inside_tree():
		_refit_pending = true
		get_tree().process_frame.connect(_refit_later, CONNECT_ONE_SHOT)


func _refit_later() -> void:
	_refit_pending = false
	if actions_box == null:
		return
	_fit_now()
	_place_more()


func _fit_now() -> void:
	var vw := get_viewport().get_visible_rect().size.x
	var phone := not BTheme.desktop(vw)
	# Room for the row: the bar less the selection capsule and the notes.
	var avail := _bar_width() - group_box.get_combined_minimum_size().x - 2.0 * GAP - 4.0
	for n in [engine_note, carry_note]:
		if (n as Label).visible:
			avail -= (n as Label).get_combined_minimum_size().x + GAP
	var fixed: Array = []
	for b in [halt_button, run_button, withdraw_button]:
		if (b as Control).visible:
			fixed.append(b)
	# The chips that apply, in order: armed first, then common, then the rest (each group in the fixed order).
	var vis: Array = []
	for pass_k in 3:
		for c in _chip_order:
			var ch := c as AbilityChip
			if not ch.visible:
				continue
			var k := 0 if ch.pinned else (1 if ch.common else 2)
			if k == pass_k:
				vis.append(ch)
	# Where each chip stands now: a chip that is not visible goes home to the bar's box.
	var in_bar: Array = []
	var in_more: Array = []
	var forced: Array = []
	var rest: Array = []
	for ch in vis:
		if (ch as AbilityChip).low and phone and not (ch as AbilityChip).pinned:
			forced.append(ch)
		else:
			rest.append(ch)
	var mode_compact := false
	var in_up: Array = []
	var fixed_w := _row_w(fixed, false)
	var all_w := fixed_w + _row_w(rest, false) + (GAP if not fixed.is_empty() and not rest.is_empty() else 0.0) \
		+ _divider_w(rest)
	if forced.is_empty() and all_w <= avail:
		in_bar = rest
	else:
		mode_compact = true
		fixed_w = _row_w(fixed, true)
		var more_w := more_button.width_for(false) + GAP
		var used := fixed_w + more_w
		var stop := false
		var seen := {}
		for ch in rest:
			var cl := cluster_of(ch)
			var w := (ch as AbilityChip).width_for(true) + GAP + (DIV_W + GAP if not seen.is_empty() and not seen.has(cl) else 0.0)
			if not stop and (ch as AbilityChip).pinned and used + w <= avail:
				in_bar.append(ch)
				seen[cl] = true
				used += w
			elif not stop and used + w <= avail and not (ch as AbilityChip).pinned:
				in_bar.append(ch)
				seen[cl] = true
				used += w
			else:
				stop = true
				in_more.append(ch)
		in_more.append_array(forced)
		# The double stack: when the clusters still do not fit one row, a second row above; only what does not fit
		# two rows goes under More.
		if in_more.size() > forced.size():
			var two := _two_rows(rest, forced, fixed_w, avail)
			if (two[2] as Array).size() < in_more.size():
				in_bar = two[0]
				in_up = two[1]
				in_more = two[2]
	two_rows = not in_up.is_empty()
	in_bar = _cluster_sorted(in_bar)
	in_more = _cluster_sorted(in_more)
	_strip_more_extras()
	for b in fixed:
		if b is AbilityChip:
			(b as AbilityChip).set_mode(mode_compact)
	for c in _chip_order:
		(c as AbilityChip).set_mode(mode_compact)
	# Put the chips where they go, in order.
	var chip_h := CHIP2_H if two_rows else AbilityChip.H
	for c in _chip_order:
		var ch := c as Control
		if in_bar.has(ch) or not (vis.has(ch)):
			_home(ch, chips_box)
		elif in_up.has(ch):
			_home(ch, chips_up)
		(ch as AbilityChip).set_h(chip_h if (in_bar.has(ch) or in_up.has(ch)) else AbilityChip.H)
	chips_box.custom_minimum_size.y = chip_h + CAP_H
	chips_up.custom_minimum_size.y = CHIP2_H + CAP_H
	var nd := _put_row(chips_box, in_bar, 0, chip_h)
	nd = _put_row(chips_up, in_up, nd, chip_h)
	for i in range(nd, _dividers.size()):
		(_dividers[i] as Control).visible = false
	chips_box.move_child(cap_layer, chips_box.get_child_count() - 1)
	chips_up.move_child(cap_up, chips_up.get_child_count() - 1)
	chips_up.visible = not in_up.is_empty() and actions_box.visible
	for ch in in_more:
		_home(ch, more_box)
		(ch as AbilityChip).set_mode(false)
		more_box.move_child(ch, more_box.get_child_count() - 1)
	chips_box.visible = not in_bar.is_empty()   # (an empty box would still cost a gap)
	more_button.visible = not in_more.is_empty()
	if not more_button.visible:
		_set_more_open(false)
	_place_more()
	_place_options()
	_place_explain()
	_place_confirm()
	_place_clusters()


## Lay `items` (in cluster order) into `box` with a divider between neighbouring clusters; returns the next divider index.
func _put_row(box: Container, items: Array, nd: int, chip_h: float) -> int:
	var prev := ""
	for ch in items:
		var cl := cluster_of(ch)
		if prev != "" and cl != prev:
			var d := _divider(nd)
			_home(d, box)
			d.custom_minimum_size.y = chip_h + CAP_H
			d.visible = true
			box.move_child(d, box.get_child_count() - 1)
			nd += 1
		prev = cl
		box.move_child(ch, box.get_child_count() - 1)
	return nd


## The double stack (docs/design/ui.md "The double stack and the Chips page"): `rest` split over two rows, clusters
## whole. The lower row keeps Halt / Run / More / Withdraw (`fixed_w` with the compact texts) and the clusters that
## fit beside them; the others go to the upper row, which has the whole bar width. Every split of the present clusters
## is tried (at most 16): the one with the fewest chips left for More wins, then the cheapest clusters upstairs
## (UP_FIRST: Move, Kit, Fight, Shoot). Chips that fit neither row (an armed ability always stays) go under More with
## `forced`. Returns [lower, upper, more].
func _two_rows(rest: Array, forced: Array, fixed_w: float, avail: float) -> Array:
	var present: Array = []
	for cl in CLUSTERS:
		for ch in rest:
			if cluster_of(ch) == cl:
				present.append(cl)
				break
	var best: Array = []
	var best_key := INF
	for mask in 1 << present.size():
		var low_cl: Array = []
		var cost := 0.0
		for k in present.size():
			if (mask >> k) & 1:
				cost += float(1 << UP_FIRST.find(present[k]))
			else:
				low_cl.append(present[k])
		var res := _split_rows(rest, forced, fixed_w, avail, low_cl)
		if res.is_empty():
			continue
		var key: float = float((res[2] as Array).size()) * 1000.0 + cost
		if key < best_key:
			best_key = key
			best = res
	return best


## One split for _two_rows: [lower, upper, more], or [] when the lower row's clusters do not fit beside the fixed buttons.
func _split_rows(rest: Array, forced: Array, fixed_w: float, avail: float, low_cl: Array) -> Array:
	var low: Array = []
	var up_all: Array = []
	for ch in rest:
		if low_cl.has(cluster_of(ch)):
			low.append(ch)
		else:
			up_all.append(ch)
	up_all = _cluster_sorted(up_all)
	var avail_up := _bar_width() - 4.0
	var up: Array = []
	var more: Array = []
	var used := 0.0
	var seen := {}
	var stop := false
	for ch in up_all:
		var cl := cluster_of(ch)
		var w := (ch as AbilityChip).width_for(true) + GAP + (DIV_W + GAP if not seen.is_empty() and not seen.has(cl) else 0.0)
		if (ch as AbilityChip).pinned or (not stop and used + w <= avail_up):
			up.append(ch)
			seen[cl] = true
			used += w
		else:
			stop = true
			more.append(ch)
	var more_w := (more_button.width_for(false) + GAP) if (not more.is_empty() or not forced.is_empty()) else 0.0
	if fixed_w + more_w + _clusters_w(rest, low_cl) > avail and not low.is_empty():
		return []
	more.append_array(forced)
	return [low, up, more]


## Width of the chips of these clusters in a row (compact texts, gaps, dividers).
func _clusters_w(items: Array, clusters: Array) -> float:
	var w := 0.0
	for ch in items:
		if clusters.has(cluster_of(ch)):
			w += (ch as AbilityChip).width_for(true) + GAP
	return w + (DIV_W + GAP) * maxi(clusters.size() - 1, 0)


## The cluster of a chip (CLUSTER_OF by its key; Fight when it is not listed).
static func cluster_of(c: AbilityChip) -> String:
	return str(CLUSTER_OF.get(c.key, "Fight"))


## Chips in cluster order, each cluster in the bar's fixed order.
func _cluster_sorted(items: Array) -> Array:
	var out := items.duplicate()
	out.sort_custom(func(a, b) -> bool:
		var ca := CLUSTERS.find(cluster_of(a))
		var cb := CLUSTERS.find(cluster_of(b))
		if ca != cb:
			return ca < cb
		return _chip_order.find(a) < _chip_order.find(b))
	return out


## Extra width the dividers of these chips cost.
func _divider_w(items: Array) -> float:
	var seen := {}
	for ch in items:
		seen[cluster_of(ch)] = true
	return (DIV_W + GAP) * maxi(seen.size() - 1, 0)


func _divider(i: int) -> Control:
	while _dividers.size() <= i:
		var d := ClusterDivider.new()
		d.name = "divider_%d" % _dividers.size()
		d.visible = false
		chips_box.add_child(d)
		_dividers.append(d)
	return _dividers[i]


## The captions: one per cluster that has a chip on the bar, centred under its chips, in the row under them.
func _place_clusters() -> void:
	if cap_layer == null or chips_box == null:
		return
	var chip_h := CHIP2_H if two_rows else AbilityChip.H
	for pair in [[chips_box, cap_layer], [chips_up, cap_up]]:
		var box: Control = pair[0]
		var caps: Array = []
		for cl in CLUSTERS:
			var x0 := INF
			var x1 := -INF
			for c in _chip_order:
				var ch := c as AbilityChip
				if ch.get_parent() == box and ch.visible and cluster_of(ch) == cl:
					x0 = minf(x0, ch.position.x)
					x1 = maxf(x1, ch.position.x + ch.size.x)
			if x0 < INF:
				caps.append([cl, Rect2(x0, chip_h, x1 - x0, CAP_H)])
		var cap_node := pair[1] as ClusterCaptions
		cap_node.global_position = box.global_position
		cap_node.size = box.size
		cap_node.caps = caps
		cap_node.visible = not caps.is_empty()
		cap_node.queue_redraw()


## The caption rectangles in viewport space: cluster word -> Rect2 (for the tests).
func cluster_caption_rects() -> Dictionary:
	var out := {}
	if cap_layer == null:
		return out
	for pair in [[chips_box, cap_layer], [chips_up, cap_up]]:
		var o: Vector2 = (pair[0] as Control).get_global_rect().position
		for c in (pair[1] as ClusterCaptions).caps:
			out[str(c[0])] = Rect2(o + (c[1] as Rect2).position, (c[1] as Rect2).size)
	return out


## The visible dividers' rectangles in viewport space.
func divider_rects() -> Array:
	var out: Array = []
	for d in _dividers:
		if (d as Control).visible:
			out.append((d as Control).get_global_rect())
	return out


func _strip_more_extras() -> void:
	for e in _more_extras:
		if is_instance_valid(e):
			if e.get_parent() != null:
				e.get_parent().remove_child(e)
			e.queue_free()
	_more_extras.clear()


func _row_w(items: Array, compact: bool) -> float:
	var w := 0.0
	for b in items:
		w += (_chip_w(b, compact))
	w += GAP * maxi(items.size() - 1, 0)
	return w


func _chip_w(b: Control, compact: bool) -> float:
	if b is AbilityChip:
		return (b as AbilityChip).width_for(compact)
	return _button_w(b as Button, (b as Button).text)


func _home(c: Control, box: Container) -> void:
	if c.get_parent() == box:
		return
	if c.get_parent() != null:
		c.get_parent().remove_child(c)
	box.add_child(c)


func _set_more_open(on: bool) -> void:
	if more_panel == null:
		return
	on = on and more_button.visible and more_box.get_child_count() > 0
	more_panel.visible = on
	more_button.set_pressed_no_signal(on)
	if on:
		close_confirm()
	else:
		_strip_more_extras()
	if on or (_opt_chip != null and _opt_chip.get_parent() == more_box):
		_close_options()
	if on or (_exp_chip != null and _exp_chip.get_parent() == more_box):
		_close_explain()
	if on:
		_place_more()


## The grid's height with `cols` columns: per cluster a heading row and its chips in rows of `cols`.
func _more_height(chips: Array, cols: int) -> float:
	var h := 0.0
	for cl in CLUSTERS:
		var k := 0
		for c in chips:
			if cluster_of(c) == cl:
				k += 1
		if k > 0:
			h += MORE_HEAD_H + GAP + ceili(float(k) / cols) * (AbilityChip.H + GAP)
	return h


## A heading cell of the More grid (text "": an empty padding cell).
func _more_cell(text: String) -> Control:
	var n: Control
	if text == "":
		n = Control.new()
		n.name = "pad"
	else:
		var l := Label.new()
		l.text = text
		l.name = "head_" + text
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", Color(Kit.COL_BONE, 0.65))
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		n = l
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	n.custom_minimum_size = Vector2(0.0, MORE_HEAD_H)
	_more_extras.append(n)
	return n


## The popover sits above the More chip, right-aligned to it and kept on screen.
func _place_more() -> void:
	if more_panel == null or not more_panel.visible:
		return
	var vp := get_viewport().get_visible_rect().size
	var r := more_button.get_global_rect()
	# Columns: as few as let the clusters (a heading row, then their chips) fit between the top bar and the More chip.
	_strip_more_extras()
	var chips: Array = []
	for c in more_box.get_children():
		if (c as Control).visible:
			chips.append(c)
	chips = _cluster_sorted(chips)
	var pad := more_panel.get_theme_stylebox("panel").get_minimum_size()
	var below_bar := r.position.y - GAP - (BTN_H + 3.0 * MARGIN) - pad.y   # between the top bar and the More chip
	var to_edge := r.position.y - GAP - MARGIN - pad.y                      # worst case: over the top bar
	var max_w := vp.x - 2.0 * MARGIN - pad.x
	var cw := 0.0
	for c in chips:
		cw = maxf(cw, (c as Control).get_combined_minimum_size().x)
	var max_cols := mini(maxi(1, int((max_w + GAP) / (cw + GAP))), maxi(chips.size(), 1))
	# 1. A grid: as few columns as let the clusters (a heading row, then their chips) fit between the bar and the chip.
	var cols := 1
	while cols < max_cols and _more_height(chips, cols) > below_bar:
		cols += 1
	var grid_ok := _more_height(chips, cols) <= below_bar
	more_box.flow_w = 0.0
	more_box.columns = cols
	var seq: Array = []
	for cl in CLUSTERS:
		var grp: Array = []
		for c in chips:
			if cluster_of(c) == cl:
				grp.append(c)
		if grp.is_empty():
			continue
		seq.append(_more_cell(cl))
		if grid_ok:
			for i in cols - 1:
				seq.append(_more_cell(""))
		seq.append_array(grp)
		if grid_ok:
			for i in (cols - grp.size() % cols) % cols:
				seq.append(_more_cell(""))
	for i in seq.size():
		var node: Node = seq[i]
		if node.get_parent() == null:
			more_box.add_child(node)
		more_box.move_child(node, i)
	# 2. No grid fits: the clusters flow (a heading, then its chips, wrapping like text), widening until it fits, first
	# under the bar, then over it; and only if even the widest flow is too tall does the popover scroll.
	if not grid_ok:
		var fit := false
		for lim in [below_bar, to_edge]:
			var w := cw + 40.0
			while w <= max_w + 0.5 and not fit:
				more_box.flow_w = w
				if more_box.get_combined_minimum_size().y <= lim:
					fit = true
				else:
					w += 12.0
			if fit:
				break
		if not fit:
			more_box.flow_w = max_w
	more_scroll.custom_minimum_size = Vector2.ZERO
	more_panel.reset_size()
	var content := more_box.get_combined_minimum_size()
	more_scroll.custom_minimum_size = Vector2(minf(content.x, max_w), minf(content.y, maxf(to_edge, AbilityChip.H)))
	more_panel.reset_size()
	var sz := more_panel.get_combined_minimum_size()
	var x := clampf(r.end.x - sz.x, MARGIN, maxf(vp.x - sz.x - MARGIN, MARGIN))
	var y := maxf(r.position.y - sz.y - GAP, MARGIN)
	more_panel.position = Vector2(x, y)
	more_panel.size = sz


# ------------------------------------------------------ chip options ---
# docs/design/ui.md "Chip options": a tap on a chip with more than one state opens a small popover above it with one
# 42 px row per state (the current one pressed, with a check); a row sets that state and closes the popover. A tap
# outside, on the chip again, Esc or a selection change closes it with no change. Keys still cycle (battle.gd).

## A hairline between two clusters of the bar.
## The More popover's content: a grid of `columns` columns (column widths and row heights from the cells), or, when
## `flow_w` > 0, the cells flowing left to right like text in that width (a heading cell stays with the cell after it).
class MoreBox extends Container:
	var columns := 1:
		set(v):
			columns = maxi(v, 1)
			update_minimum_size()
			queue_sort()
	var flow_w := 0.0:
		set(v):
			flow_w = v
			update_minimum_size()
			queue_sort()
	var sep := 5.0

	func _cells() -> Array:
		var a: Array = []
		for k in get_children():
			if k is Control and (k as Control).visible:
				a.append(k)
		return a

	## [rects per cell, total size]
	func _plan() -> Array:
		var cells := _cells()
		var rects: Array = []
		var total := Vector2.ZERO
		if flow_w <= 0.0:
			var colw: Array = []
			colw.resize(columns)
			colw.fill(0.0)
			var rows := ceili(float(cells.size()) / columns)
			var rowh: Array = []
			rowh.resize(maxi(rows, 0))
			rowh.fill(0.0)
			for i in cells.size():
				var m: Vector2 = (cells[i] as Control).get_combined_minimum_size()
				colw[i % columns] = maxf(colw[i % columns], m.x)
				rowh[i / columns] = maxf(rowh[i / columns], m.y)
			var ys: Array = []
			var y := 0.0
			for r in rows:
				ys.append(y)
				y += rowh[r] + sep
			var xs: Array = []
			var x := 0.0
			for c in columns:
				xs.append(x)
				x += colw[c] + sep
			for i in cells.size():
				rects.append(Rect2(xs[i % columns], ys[i / columns], colw[i % columns], rowh[i / columns]))
			total = Vector2(maxf(x - sep, 0.0), maxf(y - sep, 0.0))
		else:
			var x := 0.0
			var y := 0.0
			var rh := 0.0
			var rowstart := 0
			var i := 0
			while i < cells.size():
				var m: Vector2 = (cells[i] as Control).get_combined_minimum_size()
				var unit := m.x
				var n := 1
				if str(cells[i].name).begins_with("head_") and i + 1 < cells.size():
					unit += sep + (cells[i + 1] as Control).get_combined_minimum_size().x
					n = 2
				if x > 0.0 and x + unit > flow_w:
					for j in range(rowstart, rects.size()):
						rects[j].size.y = rh
					y += rh + sep
					x = 0.0
					rh = 0.0
					rowstart = rects.size()
				for k in n:
					var mk: Vector2 = (cells[i + k] as Control).get_combined_minimum_size()
					rects.append(Rect2(x, y, mk.x, mk.y))
					x += mk.x + sep
					rh = maxf(rh, mk.y)
					total.x = maxf(total.x, x - sep)
				i += n
			for j in range(rowstart, rects.size()):
				rects[j].size.y = rh
			total.y = y + rh
		return [cells, rects, total]

	func _get_minimum_size() -> Vector2:
		return _plan()[2]

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			var p := _plan()
			for i in p[0].size():
				fit_child_in_rect(p[0][i], p[1][i])


class ClusterDivider extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(3.0, 52.0)
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	func _draw() -> void:
		draw_rect(Rect2(floorf(size.x * 0.5), 2.0, 1.0, maxf(size.y - 4.0, 1.0)), Color(0.69, 0.54, 0.25, 0.5))


## The clusters' captions, drawn (a Label would not fit the 10 px row): `caps` is [word, Rect2 in this node's space].
class ClusterCaptions extends Control:
	var caps: Array = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_level = true
		name = "captions"

	func _draw() -> void:
		var f := ThemeDB.fallback_font
		for c in caps:
			var r: Rect2 = c[1]
			var w := f.get_string_size(str(c[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			draw_string(f, Vector2(r.position.x + maxf((r.size.x - w) * 0.5, 0.0), r.end.y - 2.0), str(c[0]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.91, 0.86, 0.69, 0.6))


## An option row: a toggle-look button that draws a check at its right end when it is the current state.
class OptRow extends Button:
	var current := false

	func _draw() -> void:
		if not current:
			return
		var c := Color(1.0, 0.85, 0.4)
		var x := size.x - 22.0
		var y := size.y * 0.5
		draw_polyline(PackedVector2Array([Vector2(x, y), Vector2(x + 5, y + 5), Vector2(x + 14, y - 6)]), c, 2.5, true)


func _is_multi(c: AbilityChip) -> bool:
	return c.ab >= 0 or _toggle_emit.has(c)


## Register a multi-state toggle chip: a press opens its options; `act` emits its old (flip) signal.
func _multi(c: AbilityChip, act: Callable) -> void:
	_toggle_emit[c] = act
	c.pressed.connect(func(): _open_options(c))


## The legend of the Chips page (battle menu): the fixed three, then every chip by cluster, each as
## {cluster, key, name, icon (Texture2D or null), title, tip, states (Array of words)}; all read from the chips' own tips.
func legend_entries() -> Array:
	var out: Array = []
	for b in [halt_button, run_button, withdraw_button]:
		var t: Array = Kit.tip_of(b)
		var states: Array = []
		if b == run_button:
			t = [run_button.tip_title, run_button.tip_body]
			states = ["On", "Off"]
		out.append({"cluster": "Always on the bar", "key": "run" if b == run_button else ("halt" if b == halt_button else "withdraw"),
			"name": "Run" if b == run_button else str((b as Button).text),
			"icon": (b as Button).icon, "title": str(t[0]) if t.size() > 0 else "", "tip": str(t[1]) if t.size() > 1 else "", "states": states})
	for cl in CLUSTERS:
		for c in _cluster_sorted(_chip_order):
			var ch := c as AbilityChip
			if cluster_of(ch) != cl:
				continue
			var states: Array = []
			for r in _chip_rows(ch):
				states.append(str(r[0]))
			out.append({"cluster": cl, "key": ch.key, "name": ch.label_name, "icon": ch.icon, "title": ch.tip_title,
				"tip": ch.tip_body, "states": states})
	return out


## The rows of a chip: [word, icon, state value] in display order ([] for a single-action chip).
func _chip_rows(c: AbilityChip) -> Array:
	if c.ab >= 0:
		var rows := [["Auto", "", UT.AB_AUTO], ["Hold", "", UT.AB_HOLD]]
		if c.ab != UT.AB_PISTOL:
			rows.append(["Use now", "", UT.AB_NOW])
		return rows
	match c.key:
		"run":
			return [["On", "", 1], ["Off", "", 0]]
		"fire":
			return [["At will", "fire", 1], ["Hold", "hold_fire", 0]]
		"skirmish", "bounds", "deploy", "refill", "forage":
			return [["On", "", 1], ["Off", "", 0]]
		"stance":
			return [["Line", "stance_line", 0], ["Cover", "stance_cover", 1], ["Hold street", "stance_hold", 2]]
		"ammo":
			var std := str(ammo_kinds[0]) if ammo_kinds.size() > 0 else "Standard"
			var spc := str(ammo_kinds[1]) if ammo_kinds.size() > 1 else "Special"
			return [[std, "ammo", 0], [spc, "ammo", 1]]
		"release":
			return [["Ready", "", 0], ["Tap an enemy", "", 1]]
	return []


func _ability_cur(c: AbilityChip) -> int:
	if c.armed:
		return UT.AB_NOW
	match c.state_word:
		"Auto":
			return UT.AB_AUTO
		"Hold":
			return UT.AB_HOLD
		"Use now":
			return UT.AB_NOW
	return -1   # Mixed


func _open_options(c: AbilityChip) -> void:
	if c.toggle_mode:
		c.set_pressed_no_signal(int(_cur_val.get(c.key, 0)) == 1)   # (the press must not flip the lit look: only a row does)
	if opt_panel.visible and _opt_chip == c:
		_close_options()
		return
	var rows := _chip_rows(c)
	if rows.is_empty():
		return
	set_speed_panel_open(false)
	close_confirm()
	_close_explain()
	if c.get_parent() != more_box:
		_set_more_open(false)
	_close_options()
	_opt_cur = _ability_cur(c) if c.ab >= 0 else int(_cur_val.get(c.key, 0))
	var wmax := 0.0
	var made: Array[OptRow] = []
	for r in rows:
		var row := OptRow.new()
		row.name = "opt_%d" % int(r[2])
		row.set_meta("value", int(r[2]))
		row.text = str(r[0])
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.focus_mode = Control.FOCUS_NONE
		row.toggle_mode = true
		row.add_theme_font_size_override("font_size", FONT)
		BTheme.plate(row, true, false, false)
		if str(r[1]) != "":
			Kit.set_icon(row, str(r[1]))
		row.current = int(r[2]) == _opt_cur
		row.set_pressed_no_signal(row.current)
		row.custom_minimum_size = Vector2(0.0, AbilityChip.H)
		row.pressed.connect(AudioFx.click)
		var val := int(r[2])
		row.pressed.connect(func(): _choose_option(c, val))
		opt_box.add_child(row)
		made.append(row)
		wmax = maxf(wmax, _button_w(row, row.text) + 28.0)
	for row in made:
		row.custom_minimum_size.x = wmax
	_opt_chip = c
	opt_panel.visible = true
	_place_options()


func _close_options() -> void:
	if opt_panel == null:
		return
	opt_panel.visible = false
	_opt_chip = null
	for k in opt_box.get_children():
		opt_box.remove_child(k)
		k.queue_free()


## A row was tapped: close the popover, then set that state through the old order path.
func _choose_option(c: AbilityChip, value: int) -> void:
	var cur := _opt_cur
	_close_options()
	if value == cur:
		return
	if c.ab >= 0:
		ability_set.emit(c.ab, value)
	elif c.key == "stance":
		stance_set.emit(value)
	elif _toggle_emit.has(c):
		(_toggle_emit[c] as Callable).call()
	if c.toggle_mode and c.key == "release":
		c.set_pressed_no_signal(int(_cur_val.get(c.key, 0)) == 1)


## The popover sits above its chip (centred, kept inside the viewport); for a chip under More it goes beside the More
## popover (left, else right), else above it, else clamped inside the viewport.
func _place_options() -> void:
	if opt_panel == null or not opt_panel.visible:
		return
	if _opt_chip == null or not _opt_chip.is_visible_in_tree():
		_close_options()
		return
	opt_panel.reset_size()
	var sz := opt_panel.get_combined_minimum_size()
	opt_panel.position = _popover_pos(_opt_chip, sz)
	opt_panel.size = sz


## Where a popover of size `sz` goes for `chip`: above it (centred, kept inside the viewport); for a chip under More
## beside the More popover (left, else right), else above it, else clamped inside the viewport.
func _popover_pos(chip: Control, sz: Vector2) -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var r := chip.get_global_rect()
	var pos: Vector2
	if chip.get_parent() == more_box and more_panel.visible:
		var mr := more_panel.get_global_rect()
		var y := clampf(r.get_center().y - sz.y * 0.5, MARGIN, maxf(vp.y - sz.y - MARGIN, MARGIN))
		if mr.position.x - GAP - sz.x >= MARGIN:
			pos = Vector2(mr.position.x - GAP - sz.x, y)
		elif mr.end.x + GAP + sz.x <= vp.x - MARGIN:
			pos = Vector2(mr.end.x + GAP, y)
		elif mr.position.y - GAP - sz.y >= MARGIN:
			pos = Vector2(clampf(r.get_center().x - sz.x * 0.5, MARGIN, maxf(vp.x - sz.x - MARGIN, MARGIN)), mr.position.y - GAP - sz.y)
		else:
			pos = Vector2(clampf(r.get_center().x - sz.x * 0.5, MARGIN, maxf(vp.x - sz.x - MARGIN, MARGIN)), y)
	else:
		pos = Vector2(clampf(r.get_center().x - sz.x * 0.5, MARGIN, maxf(vp.x - sz.x - MARGIN, MARGIN)),
			maxf(r.position.y - sz.y - GAP, MARGIN))
		if r.position.y - sz.y - GAP < MARGIN:
			# No room above (a chip of the upper row on a short screen): beside the chip, clear of it.
			var y2 := clampf(r.get_center().y - sz.y * 0.5, MARGIN, maxf(vp.y - sz.y - MARGIN, MARGIN))
			if r.position.x - GAP - sz.x >= MARGIN:
				pos = Vector2(r.position.x - GAP - sz.x, y2)
			elif r.end.x + GAP + sz.x <= vp.x - MARGIN:
				pos = Vector2(r.end.x + GAP, y2)
	return pos


# ------------------------------------------- the long-press explanation ---
# A chip held 0.45 s (a finger or the mouse button, not moving more than 8 px) opens a popover above it: the chip's
# title, its state, the tip, one line per state, and a link to the unit book. The release gives no tap. Taps outside,
# Esc, a selection change, or opening the options close it.

## Mouse / touch input on a chip: starts and ends the hold (the timer runs in _process).
func _chip_input(ev: InputEvent, c: AbilityChip) -> void:
	if c == more_button:
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		if mb.pressed:
			_lp_chip = c
			_lp_ms = Time.get_ticks_msec()
			_lp_pos = mb.global_position
			_lp_fired = false
		else:
			_lp_chip = null
	elif ev is InputEventMouseMotion and _lp_chip == c:
		if (ev as InputEventMouseMotion).global_position.distance_to(_lp_pos) > CHIP_LONG_SLOP:
			_lp_chip = null


func _open_explain(c: AbilityChip) -> void:
	set_speed_panel_open(false)
	close_confirm()
	if c.get_parent() != more_box:
		_set_more_open(false)
	_close_options()
	_close_explain()
	var title := Kit.label(c.tip_title, 16, Kit.COL_GOLD)
	title.name = "ex_title"
	explain_box.add_child(title)
	var cur_word := "Use now" if c.armed else c.state_word
	if cur_word != "":
		var st := Kit.label("Now: " + cur_word, 14, Kit.COL_DIM)
		st.name = "ex_state"
		explain_box.add_child(st)
	var body := c.tip_body
	if not c.common:
		body += "\nNot all selected units have it: only some obey."
	var bl := Kit.label(body, 14, Kit.COL_BONE, true)
	bl.name = "ex_body"
	bl.custom_minimum_size.x = EXPLAIN_W
	explain_box.add_child(bl)
	var rows := _chip_rows(c)
	if rows.size() > 1:
		var cur := _ability_cur(c) if c.ab >= 0 else int(_cur_val.get(c.key, 0))
		for r in rows:
			var now := int(r[2]) == cur
			var l := Kit.label(str(r[0]) + ("  (now)" if now else ""), 14, Kit.COL_GOLD if now else Kit.COL_BONE)
			l.name = "ex_row_%d" % int(r[2])
			if str(r[1]) != "":
				Kit.label_icon(l, str(r[1]))
			explain_box.add_child(l)
	var xbook := Button.new()
	xbook.name = "ex_book"
	xbook.text = "Unit book"
	xbook.focus_mode = Control.FOCUS_NONE
	xbook.alignment = HORIZONTAL_ALIGNMENT_LEFT
	xbook.add_theme_font_size_override("font_size", FONT)
	xbook.custom_minimum_size = Vector2(0.0, 36.0)
	BTheme.plate(xbook)
	Kit.set_icon(xbook, "units")
	xbook.pressed.connect(AudioFx.click)
	xbook.pressed.connect(func():
		_close_explain()
		chip_book_pressed.emit())
	explain_box.add_child(xbook)
	_exp_chip = c
	explain_panel.visible = true
	_place_explain()


func _close_explain() -> void:
	if explain_panel == null:
		return
	explain_panel.visible = false
	_exp_chip = null
	for k in explain_box.get_children():
		explain_box.remove_child(k)
		k.queue_free()


func _place_explain() -> void:
	if explain_panel == null or not explain_panel.visible:
		return
	if _exp_chip == null or not _exp_chip.is_visible_in_tree():
		_close_explain()
		return
	explain_panel.reset_size()
	var sz := explain_panel.get_combined_minimum_size()
	explain_panel.position = _popover_pos(_exp_chip, sz)
	explain_panel.size = sz


func _button_w(b: Button, t: String) -> float:
	var fs := b.get_theme_font_size("font_size")
	var w := b.get_theme_font("font").get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if b.icon != null:
		w += b.icon.get_width() + b.get_theme_constant("h_separation")
	w += b.get_theme_stylebox("normal").get_minimum_size().x
	return maxf(w, b.custom_minimum_size.x)


## The selection capsule: on a phone width the role segments show their badge glyph (34 px, the tip names the group),
## on a desktop the words (50 px). All and None keep their words.
func _apply_capsule() -> void:
	var compact := not BTheme.desktop(get_viewport().get_visible_rect().size.x)
	for k in _cap_words:
		var gb: Button = deselect_button if k == "none" else group_buttons.get(k)
		if gb == null:
			continue
		var glyph := compact and _cap_tiles.has(k)
		gb.text = "" if glyph else str(_cap_words[k])
		if _cap_tiles.has(k):
			(_cap_tiles[k] as Control).visible = glyph
		if compact:
			gb.custom_minimum_size.x = 34.0
			gb.add_theme_font_size_override("font_size", FONT - 3)
			BTheme.trim_margins(gb, 2.0)
		else:
			gb.custom_minimum_size.x = 50.0
			gb.add_theme_font_size_override("font_size", FONT)
			BTheme.trim_margins(gb, 6.0)


## Heroes and agents: show the act buttons in `acts` (act names), the
## `armed` one pressed and reading "<Act>: tap".
func set_char_buttons(acts: Dictionary, armed: String) -> void:
	for act in char_buttons:
		var b: Button = char_buttons[act]
		b.visible = acts.has(act)
		b.set_pressed_no_signal(armed == act)
		(b as AbilityChip).label_name = str(act).capitalize()
		(b as AbilityChip).set_state("tap" if armed == act else "")


## Siege equipment: "Drop" while a selected unit carries a piece (battle.gd
## decides when; men go up and down walls by a click / tap, M / Shift+M).
## The selected unit's carry pattern line ("" hides it).
func set_carry_note(text: String) -> void:
	if carry_note.text != text:
		carry_note.text = text
	carry_note.visible = text != ""


## Gift's label ("Gift to Anna", "Gift to ...").
func set_gift_text(t: String) -> void:
	gift_button.label_name = t
	gift_button.text = gift_button.text_for(gift_button.compact_mode)
	_fit_actions()


func set_drop_button(drop: bool) -> void:
	drop_button.visible = drop


func update_cards(sim) -> void:
	var tick: int = sim.tick
	_update_arriving(sim)
	for u in _cards:
		var ty: int = sim.u_type[u]
		var f: CardFace = _faces[u]
		var mstate := morale_text(sim, u)
		var art := UT.cls(ty) == UT.CLS_ART
		f.name_text = "%s %d" % [CData.unit_short(UT.key_of(sim.u_otype[u]), _uf(u)), u + 1]
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
		if sim.rsv_on != 0 and sim.u_hand[u] < 0:
			(_cards[u] as Button).visible = sim.u_state[u] != BattleSim.U_RESERVE  # (a reinforcement: once it arrives)
		if sim.u_hand[u] >= 0:
			(_cards[u] as Button).visible = sim.u_state[u] != BattleSim.U_KENNEL  # (the pack: only while loose)
			if sim.u_ret[u] != 0:
				summary += " returning"
		if art:
			f.ammo_text = "%d+%d" % [maxi(sim.u_ammo[u], 0), maxi(sim.u_reserve[u], 0)]
			summary = art_card_text(sim, u, _uf(u)).replace("\n", " | ")
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
		f.poisoned = sim.poi_on != 0 and sim.u_poisoned[u] > 0
		if f.poisoned:
			f.summary += " | %d poisoned" % sim.u_poisoned[u]
		# Holding a building under fire (destruction): its hit points as a small bar.
		f.bld_pm = -1
		f.bld_fire = false
		var bpm: int = sim.occ_hp_pm(u)
		if bpm >= 0:
			var ob: int = sim.u_occ[u] - 1
			f.bld_fire = ob < sim.ob_fire.size() and sim.ob_fire[ob] != 0
			if bpm < 1000 and tick - sim.ob_hit_t[ob] < 300:
				f.bld_pm = bpm
			if f.bld_fire:
				f.summary += " | building on fire %d%%" % (bpm / 10)
			elif bpm < 1000:
				f.summary += " | building %d%%" % (bpm / 10)
		f.fighting = sim.u_fighting[u] > 0
		_card_state_strip(u, f)
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


## The card's state strip and tip: a glyph for each chip not at its default (battle.gd's card_states), the tip in words.
func _card_state_strip(u: int, f: CardFace) -> void:
	if not card_states.is_valid() or f.role == "":
		return
	var st: Array = card_states.call(u)
	var key := str(st)
	if _card_key.get(u, "") == key:
		return
	_card_key[u] = key
	var glyphs: Array[String] = []
	var words: Array[String] = []
	for g in st:
		glyphs.append(str(g[0]))
		words.append(str(g[1]))
	f.glyphs = glyphs
	var body := RoleBadge.plays(f.role)
	if not words.is_empty():
		body += "\n" + ", ".join(words)
	Kit.tip(_cards[u] as Button, str(UT.ROLES[f.role]["name"]), body)


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
static func art_card_text(sim, u: int, fac: int = -1) -> String:
	var ok := 0
	for k in sim.u_neng[u]:
		if sim.e_state[sim.u_eng0[u] + k] == 0:
			ok += 1
	return "%s %d  %d/%d\neng %d/%d  %d shots +%d\n%s" % [CData.unit_short(UT.key_of(sim.u_otype[u]), fac), u + 1,
		sim.u_alive[u], sim.u_count0[u], ok, sim.u_neng[u], maxi(sim.u_ammo[u], 0),
		maxi(sim.u_reserve[u], 0), deploy_text(sim, u)]


## The campaign faction of sim unit u (-1 unknown).
func _uf(u: int) -> int:
	return int(unit_faction[u]) if u >= 0 and u < unit_faction.size() else -1


## Siege equipment a unit carries: "carrying ladders" / "carrying ram" /
## "pushing a tower", else "".
static func carry_text(sim, u: int) -> String:
	var k := BattleSim.carrying(sim, u)
	if k == BattleSim.EQ_LADDERS:
		return "carrying ladders"
	if k == BattleSim.EQ_POLES:
		return "carrying poles"
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
	if k == BattleSim.EQ_POLES:
		return "a file a pole (%d)" % files
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
	elif k == BattleSim.EQ_POLES:
		what = "Carrying scaling poles"
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


## The "Arriving" line and the arrival note (reinforcements).
func _update_arriving(sim) -> void:
	if arriving_label == null or sim.rsv_on == 0:
		return
	var me := clampi(_player_side, 0, 1)
	var txt := arriving_text(sim.reserves_left(me), sim.reserves_left(1 - me))
	arriving_label.text = txt
	arriving_label.visible = txt != ""
	if sim.stat_arrived != _arr_seen:
		_arr_seen = sim.stat_arrived
		var last := -1
		for u in sim.n_units:
			if sim.u_arr[u] >= 0 and (last < 0 or sim.u_arr[u] >= sim.u_arr[last]):
				last = u
		if last >= 0:
			var who := str(unit_labels.get(last, ""))
			arrival_note.text = "Reinforcements: %s" % (who if who != "" else CData.unit_name(UT.key_of(sim.u_otype[last]), _uf(last)))
			if sim.u_side[last] != me:
				arrival_note.text = "Enemy reinforcements: %s" % (who if who != "" else CData.unit_name(UT.key_of(sim.u_otype[last]), _uf(last)))
			arrival_note.visible = true
			_note_left = 3.0


## "Arriving: n units" (own reserves still to come) and the enemy's.
static func arriving_text(mine: int, theirs: int) -> String:
	var bits: Array[String] = []
	if mine > 0:
		bits.append("Arriving: %d unit%s" % [mine, "" if mine == 1 else "s"])
	if theirs > 0:
		bits.append("Enemy arriving: %d unit%s" % [theirs, "" if theirs == 1 else "s"])
	return "   ".join(bits)


static func morale_text(sim, u: int) -> String:
	var s: int = sim.u_state[u]
	if s == BattleSim.U_RESERVE:
		return "Arriving"
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
			_cell("%s %d" % [CData.unit_short(UT.key_of(int(r["type"])), _uf(int(r["unit"]))), int(r["unit"]) + 1], Color.WHITE)
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
	result_detail.text = Kit.kills_detail("%s %d" % [CData.unit_short(UT.key_of(int(r["type"])), _uf(int(r["unit"]))), int(r["unit"]) + 1],
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
	Kit.install_tips()
	var b := Kit.TipButton.new()
	b.text = text
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", FONT)
	b.pressed.connect(AudioFx.click)
	if icon != "":
		Kit.set_icon(b, icon)
	BTheme.plate(b)   # the nav plate and the hover / press motion; toggle buttons call plate(b, true) again
	return b


## A bar chip (game/ability_chip.gd): `state` its first state word; `toggle` a lit-when-on button; `ab` a UT.AB_* ability.
func _chip(key: String, label: String, icon: String, title: String, tip_text: String, state: String,
		toggle: bool = false, ab: int = -1) -> AbilityChip:
	var c := AbilityChip.new()
	c.setup(key, label, icon, title, tip_text, ab, toggle)
	c.state_word = state
	c.text = c.full_text()
	c.gui_input.connect(_chip_input.bind(c))
	c.pressed.connect(func():
		if more_panel != null and c.get_parent() == more_box and c != more_button and not _is_multi(c):
			_set_more_open(false))
	return c


static func _box(col: Color, margin: float = 8.0) -> StyleBox:
	return Kit.rule_box(col, margin, 5, Color(Kit.COL_RULE, 0.45), true)


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
	## The unit's role key (UT.ROLES; "" none): a badge beside the count and a colour band along the card's foot.
	var role := ""
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
	var owner_band := false
	## The general (a command aura): a gold standard in the top right corner.
	var general := false
	## A hero or agent (campaign characters): "crown", "dagger" or "scroll" in the same corner.
	var char_icon := ""
	## Holding a building under fire: its hit points per mille (-1: no bar).
	var bld_pm := -1
	## ... and the building is burning (the bar red at any level).
	var bld_fire := false
	## Poisoned men in it (poisoned arrows): a green strip down the right edge.
	var poisoned := false
	## The state strip (top right): a glyph per chip not at its default, "icon" (a state), "icon!" (on Hold: struck
	## through) or "icon*" (a Use now waiting for its target, gold).
	var glyphs: Array[String] = []

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
		if owner_band:
			draw_rect(Rect2(0, 0, sz.x, 3), owner_col)
		if under_fire and state != ST_GONE:
			draw_rect(Rect2(0, 0, 3, sz.y), Color(1.0, 0.55, 0.1))
		if poisoned and state != ST_GONE:
			draw_rect(Rect2(sz.x - 3, 0, 3, sz.y), Color(0.45, 0.85, 0.25))
		var r := minf(sz.y * 0.3, 10.0)
		var glyph := Color(0.12, 0.1, 0.05) if state == ST_ROUT else Color.WHITE
		var disc := Color(1.0, 0.9, 0.3) if state == ST_ROUT else (Color(0.45, 0.45, 0.45) if state == ST_GONE else side_col)
		var font := ThemeDB.fallback_font
		var x0 := r * 2 + 6
		# The state strip: up to three 11 px glyphs at the top right (one on a narrow card), left of the general's mark.
		var nglyph := mini(glyphs.size(), 1 if narrow else 3) if state != ST_GONE else 0
		var strip_w := nglyph * 11.0
		var strip_r := sz.x - 3.0 - (14.0 if (general or char_icon != "") else 0.0) - (11.0 if foreign else 0.0)
		for gi in nglyph:
			var gname := glyphs[gi]
			var gcol := Color(0.95, 0.95, 0.9)
			var gcross := false
			if gname.ends_with("!"):
				gname = gname.trim_suffix("!")
				gcross = true
				gcol = Color(0.95, 0.55, 0.45)
			elif gname.ends_with("*"):
				gname = gname.trim_suffix("*")
				gcol = Kit.COL_GOLD
			var grect := Rect2(strip_r - 11.0 * (gi + 1), 3, 11, 11)
			Kit.UiIcons.draw_icon(self, gname, grect, gcol)
			if gcross:
				draw_line(grect.position + Vector2(1, 10), grect.position + Vector2(10, 1), Color(0.95, 0.35, 0.3), 1.4)
		# Line 1: name and number (narrow cards: the number beside the symbol).
		if narrow:
			Icons.draw_marker(self, icon, Vector2(r + 3, r + 3), r, disc, glyph)
			draw_string(font, Vector2(x0, 14), number_text, HORIZONTAL_ALIGNMENT_LEFT, sz.x - x0 - 2 - strip_w, 13, txt)
		else:
			Icons.draw_marker(self, icon, Vector2(r + 3, sz.y * 0.5), r, disc, glyph)
			draw_string(font, Vector2(x0, 14), name_text, HORIZONTAL_ALIGNMENT_LEFT, sz.x - x0 - 2 - strip_w, 13, txt)
		# Line 2: headcount bar with the count and state word; ammunition
		# (artillery: shots + reserve) at its right end.
		var bx := 3.0 if narrow else x0
		var bw := sz.x - bx - 3
		var by := sz.y - 14
		if role != "":
			# The role badge beside the count (the bar and the count move over), and the colour band along the foot.
			RoleBadge.draw_badge(self, role, Rect2(bx, by - 1, 14, 14), state == ST_GONE)
			draw_rect(Rect2(0, sz.y - 2, sz.x, 2), Color(RoleBadge.colour(role), 0.5 if state == ST_GONE else 0.9))
			bx += 16.0
			bw -= 16.0
		var frac := clampf(float(alive) / maxf(count0, 1), 0.0, 1.0)
		draw_rect(Rect2(bx, by, bw, 12), Color(1, 1, 1, 0.1))
		draw_rect(Rect2(bx, by, bw * frac, 12), Color(bar, 0.55))
		if bld_pm >= 0:
			# The building it holds: a thin stone bar over the headcount, red below a third.
			var bf := clampf(bld_pm / 1000.0, 0.0, 1.0)
			draw_rect(Rect2(bx, by - 4, bw, 3), Color(0, 0, 0, 0.45))
			draw_rect(Rect2(bx, by - 4, bw * bf, 3), Color(0.92, 0.32, 0.22) if bld_pm < 333 or bld_fire else Color(0.78, 0.72, 0.6))
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
			Kit.draw_trim(self, Rect2(Vector2.ZERO, sz), 2.0, 9.0, Kit.COL_GOLD)   # only the selected card is trimmed
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
		for q in SPEED_QS:
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
