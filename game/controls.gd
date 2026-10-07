extends Control
## Controls: ONE table of every input (BINDINGS) and the page that shows it.
## Each row: action id, section, label, the touch gesture, the mouse input
## and the default keys. The page is rendered from the table, and the battle
## and campaign screens read their keyboard shortcuts from it
## (action_for_key / held), so the page cannot drift from what the keys do.
## Gestures and mouse buttons are described here and handled in the views
## (their handlers name the action ids in comments). Rebinding is later:
## it only has to change "keys" here.

signal closed

const TouchScroll := preload("res://game/touch_scroll.gd")
const UiKit := preload("res://game/campaign/ui_kit.gd")
const UiScale := preload("res://game/ui_scale.gd")

const SECTIONS := ["battle", "campaign", "general"]
const SECTION_NAMES := {"battle": "Battle", "campaign": "Campaign map", "general": "General"}

## keys: Array of keycodes; a key may carry modifiers as "ctrl+", "shift+",
## "alt+" through KEY_MASK bits (e.g. KEY_A | KEY_MASK_CTRL).
static var BINDINGS: Array = [
	# ---- battle: selecting
	{"id": "select", "s": "battle", "label": "Select a unit",
		"touch": "Tap the unit, its symbol or its card", "mouse": "Left click the unit, its symbol or its card", "keys": []},
	{"id": "select_add", "s": "battle", "label": "Add / remove a unit from the selection",
		"touch": "+ Add, then tap units or cards", "mouse": "Shift+click or Ctrl+click", "keys": []},
	{"id": "select_all", "s": "battle", "label": "Select all units",
		"touch": "All button", "mouse": "All button", "keys": [KEY_A | KEY_MASK_CTRL, KEY_1]},
	{"id": "select_inf", "s": "battle", "label": "Select infantry",
		"touch": "Inf button", "mouse": "Inf button", "keys": [KEY_2]},
	{"id": "select_missile", "s": "battle", "label": "Select missile troops and artillery",
		"touch": "Missile button", "mouse": "Missile button", "keys": [KEY_3]},
	{"id": "select_cav", "s": "battle", "label": "Select cavalry",
		"touch": "Cav button", "mouse": "Cav button", "keys": [KEY_4]},
	{"id": "deselect", "s": "battle", "label": "Deselect all",
		"touch": "None button (with the group buttons)", "mouse": "None button", "keys": [KEY_ESCAPE]},
	{"id": "box_select", "s": "battle", "label": "Select units in a box",
		"touch": "-", "mouse": "Left drag on empty ground with nothing selected", "keys": []},
	# ---- battle: orders
	{"id": "move", "s": "battle", "label": "Move (keep frontage)",
		"touch": "Tap the ground", "mouse": "Left click the ground", "keys": []},
	{"id": "move_run", "s": "battle", "label": "Move running",
		"touch": "Double tap the ground", "mouse": "Double click the ground", "keys": []},
	{"id": "line", "s": "battle", "label": "Draw the front line (position, width, facing; at most one rank long: the line stops there)",
		"touch": "Drag along the ground with units selected", "mouse": "Left drag with units selected", "keys": []},
	{"id": "attack", "s": "battle", "label": "Attack / shoot a unit",
		"touch": "Tap the enemy (or its symbol)", "mouse": "Left click the enemy", "keys": []},
	{"id": "attack_run", "s": "battle", "label": "Attack running / charge",
		"touch": "Double tap the enemy", "mouse": "Double click the enemy", "keys": []},
	{"id": "group_move", "s": "battle", "label": "Move the selection as it stands, turning it",
		"touch": "Three-finger drag; twist the fingers to turn; lift a finger to place, add a fourth finger to cancel",
		"mouse": "Alt+left drag (or hold G and drag); wheel or Q / E turns; right click or Esc cancels", "keys": [KEY_G]},
	{"id": "group_rotate_left", "s": "battle", "label": "Turn the group left (while moving it)",
		"touch": "Twist three fingers", "mouse": "Wheel up", "keys": [KEY_Q]},
	{"id": "group_rotate_right", "s": "battle", "label": "Turn the group right (while moving it)",
		"touch": "Twist three fingers", "mouse": "Wheel down", "keys": [KEY_E]},
	{"id": "run", "s": "battle", "label": "Run / walk toggle",
		"touch": "Run button", "mouse": "Run button", "keys": [KEY_R]},
	{"id": "halt", "s": "battle", "label": "Halt",
		"touch": "Halt button", "mouse": "Halt button", "keys": [KEY_H]},
	{"id": "fire", "s": "battle", "label": "Fire at will / hold fire",
		"touch": "Fire button", "mouse": "Fire button", "keys": [KEY_F]},
	{"id": "skirmish", "s": "battle", "label": "Skirmish mode",
		"touch": "Skirmish button", "mouse": "Skirmish button", "keys": [KEY_K]},
	{"id": "deploy", "s": "battle", "label": "Artillery: pack up / set up",
		"touch": "Deploy button", "mouse": "Deploy button", "keys": [KEY_D | KEY_MASK_SHIFT]},
	{"id": "refill", "s": "battle", "label": "Artillery: refill from the baggage",
		"touch": "Refill button", "mouse": "Refill button", "keys": [KEY_Y]},
	{"id": "man_wall", "s": "battle", "label": "Walls (defending): up onto the nearest stretch, facing the enemy",
		"touch": "Man the wall button (or tap the wall, a tower or the walkway)", "mouse": "Man the wall button, or click the wall",
		"keys": [KEY_M]},
	{"id": "drop", "s": "battle", "label": "Siege equipment: put down the ladders or the ram (pick up: tap the piece)",
		"touch": "Drop button", "mouse": "Drop button", "keys": [KEY_X]},
	{"id": "come_down", "s": "battle", "label": "Walls: down off the wall into the street inside",
		"touch": "Come down button (or tap the ground)", "mouse": "Come down button, or click the ground", "keys": [KEY_M | KEY_MASK_SHIFT]},
	{"id": "withdraw", "s": "battle", "label": "Withdraw the selected units",
		"touch": "Withdraw button", "mouse": "Withdraw button", "keys": []},
	{"id": "withdraw_all", "s": "battle", "label": "Withdraw the whole army",
		"touch": "Withdraw army, tap twice", "mouse": "Withdraw army, click twice", "keys": []},
	# ---- battle: deployment phase
	{"id": "place", "s": "battle", "label": "Deployment: place units (inside your blue zone; the men stand there at once)",
		"touch": "Tap the ground, drag a line, or three-finger drag a group (as moving)",
		"mouse": "Click, drag or Alt+drag (as moving); a point outside the zone is kept to its edge", "keys": []},
	{"id": "ready", "s": "battle", "label": "Deployment: ready, start the battle (it starts when every player is ready, or when the time runs out)",
		"touch": "Start battle button", "mouse": "Start battle button", "keys": [KEY_ENTER, KEY_KP_ENTER]},
	# ---- battle: view
	{"id": "pan", "s": "battle", "label": "Pan the view",
		"touch": "Drag with one finger (nothing selected) or two fingers",
		"mouse": "Right or middle drag; W A S D or arrow keys", "keys": []},
	{"id": "pan_up", "s": "battle", "label": "Pan up", "touch": "-", "mouse": "-", "keys": [KEY_W, KEY_UP], "hidden": true},
	{"id": "pan_down", "s": "battle", "label": "Pan down", "touch": "-", "mouse": "-", "keys": [KEY_S, KEY_DOWN], "hidden": true},
	{"id": "pan_left", "s": "battle", "label": "Pan left", "touch": "-", "mouse": "-", "keys": [KEY_A, KEY_LEFT], "hidden": true},
	{"id": "pan_right", "s": "battle", "label": "Pan right", "touch": "-", "mouse": "-", "keys": [KEY_D, KEY_RIGHT], "hidden": true},
	{"id": "zoom", "s": "battle", "label": "Zoom",
		"touch": "Pinch", "mouse": "Mouse wheel; Page Up / Page Down", "keys": []},
	{"id": "zoom_in", "s": "battle", "label": "Zoom in", "touch": "-", "mouse": "-", "keys": [KEY_PAGEUP], "hidden": true},
	{"id": "zoom_out", "s": "battle", "label": "Zoom out", "touch": "-", "mouse": "-", "keys": [KEY_PAGEDOWN], "hidden": true},
	{"id": "pause", "s": "battle", "label": "Pause / resume",
		"touch": "Pause button", "mouse": "Pause button", "keys": [KEY_SPACE, KEY_P]},
	{"id": "speed_up", "s": "battle", "label": "Faster",
		"touch": "Speed button (cycles)", "mouse": "Speed button", "keys": [KEY_EQUAL, KEY_KP_ADD]},
	{"id": "speed_down", "s": "battle", "label": "Slower",
		"touch": "Speed button (cycles)", "mouse": "Speed button", "keys": [KEY_MINUS, KEY_KP_SUBTRACT]},
	{"id": "orders_overlay", "s": "battle", "label": "Show every unit's orders",
		"touch": "Orders button", "mouse": "Orders button", "keys": [KEY_O]},
	{"id": "unit_info", "s": "battle", "label": "Unit book page of a unit",
		"touch": "Long press its card (lift your finger without moving)", "mouse": "Right click its card, or hold the button on it", "keys": []},
	{"id": "card_reorder", "s": "battle", "label": "Reorder the unit cards (this battle, on your screen only; All / Inf / Missile / Cav select in this order)",
		"touch": "Long press a card until it lifts, then drag it between two cards", "mouse": "Drag a card between two cards", "keys": []},
	{"id": "readout", "s": "battle", "label": "Performance readout (short / full)",
		"touch": "Tap the readout, top left", "mouse": "Click the readout", "keys": [KEY_F3]},
	# ---- campaign
	{"id": "map_select_army", "s": "campaign", "label": "Select an army",
		"touch": "Tap its banner", "mouse": "Left click its banner", "keys": []},
	{"id": "map_next_army", "s": "campaign", "label": "Next army",
		"touch": "-", "mouse": "-", "keys": [KEY_TAB]},
	{"id": "map_move", "s": "campaign", "label": "Move the selected army",
		"touch": "Tap a highlighted region (red: attack)", "mouse": "Left or right click a highlighted region", "keys": []},
	{"id": "map_cancel_move", "s": "campaign", "label": "Cancel a planned move",
		"touch": "Tap its destination again, or Cancel move", "mouse": "Click its destination again", "keys": []},
	{"id": "map_region", "s": "campaign", "label": "Region panel (buildings, raise a new army, garrison)",
		"touch": "Tap the region or its settlement", "mouse": "Left click the region", "keys": []},
	{"id": "map_army_reorder", "s": "campaign", "label": "Reorder an army's units (an order: the order they take the field in)",
		"touch": "On the army card, long press a unit until it lifts, then drag it", "mouse": "On the army card, drag a unit", "keys": []},
	{"id": "map_recruit_info", "s": "campaign", "label": "Unit page before recruiting",
		"touch": "Tap the unit in the recruit list (the army card of an army at your city)", "mouse": "Click the unit", "keys": []},
	{"id": "map_deselect", "s": "campaign", "label": "Close the panel / deselect",
		"touch": "Deselect button (bottom right), tap the sea, or Close", "mouse": "Deselect button, click the sea, or Close", "keys": [KEY_ESCAPE]},
	{"id": "map_pan", "s": "campaign", "label": "Pan the map",
		"touch": "Drag", "mouse": "Left, right or middle drag; W A S D or arrow keys", "keys": []},
	{"id": "map_pan_up", "s": "campaign", "label": "Pan up", "touch": "-", "mouse": "-", "keys": [KEY_W, KEY_UP], "hidden": true},
	{"id": "map_pan_down", "s": "campaign", "label": "Pan down", "touch": "-", "mouse": "-", "keys": [KEY_S, KEY_DOWN], "hidden": true},
	{"id": "map_pan_left", "s": "campaign", "label": "Pan left", "touch": "-", "mouse": "-", "keys": [KEY_A, KEY_LEFT], "hidden": true},
	{"id": "map_pan_right", "s": "campaign", "label": "Pan right", "touch": "-", "mouse": "-", "keys": [KEY_D, KEY_RIGHT], "hidden": true},
	{"id": "map_zoom", "s": "campaign", "label": "Zoom",
		"touch": "Pinch", "mouse": "Mouse wheel; + / -", "keys": []},
	{"id": "map_zoom_in", "s": "campaign", "label": "Zoom in", "touch": "-", "mouse": "-", "keys": [KEY_EQUAL, KEY_KP_ADD], "hidden": true},
	{"id": "map_zoom_out", "s": "campaign", "label": "Zoom out", "touch": "-", "mouse": "-", "keys": [KEY_MINUS, KEY_KP_SUBTRACT], "hidden": true},
	{"id": "map_end_turn", "s": "campaign", "label": "End turn",
		"touch": "End turn button", "mouse": "End turn button", "keys": [KEY_ENTER | KEY_MASK_CTRL]},
	# ---- general
	{"id": "book", "s": "general", "label": "Unit book",
		"touch": "Units button", "mouse": "Units button", "keys": [KEY_B]},
	{"id": "book_page", "s": "general", "label": "Unit book: previous / next page",
		"touch": "< Prev / Next > buttons", "mouse": "Buttons", "keys": [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]},
	{"id": "close", "s": "general", "label": "Close the book, this page or a dialog",
		"touch": "Close button", "mouse": "Close button", "keys": [KEY_ESCAPE]},
	{"id": "controls", "s": "general", "label": "This page",
		"touch": "Controls button", "mouse": "Controls button", "keys": [KEY_F1]},
	{"id": "fullscreen", "s": "general", "label": "Full screen",
		"touch": "Fullscreen (main menu); on iPhone: Share > Add to Home Screen", "mouse": "Fullscreen (main menu)", "keys": [KEY_F11]},
	{"id": "menu", "s": "general", "label": "Back to the menu",
		"touch": "Menu button", "mouse": "Menu button", "keys": []},
]

static var _by_id := {}


static func binding(id: String) -> Dictionary:
	if _by_id.is_empty():
		for b in BINDINGS:
			_by_id[str(b["id"])] = b
	return _by_id.get(id, {})


## Action of a key press within a section ("" if none). Modifiers must
## match exactly (Ctrl+A is not A).
static func action_for_key(e: InputEventKey, section: String) -> String:
	var code := e.keycode
	if code == KEY_NONE:
		code = e.physical_keycode
	var full := code | (KEY_MASK_CTRL if e.ctrl_pressed else 0) | (KEY_MASK_SHIFT if e.shift_pressed else 0) \
		| (KEY_MASK_ALT if e.alt_pressed else 0)
	for b in BINDINGS:
		if str(b["s"]) != section and str(b["s"]) != "general":
			continue
		for k in b["keys"]:
			if int(k) == full:
				return str(b["id"])
	return ""


## Is a key of this action held (no modifiers)?
static func held(id: String) -> bool:
	var b := binding(id)
	if b.is_empty():
		return false
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT):
		return false
	for k in b["keys"]:
		if Input.is_key_pressed(int(k) & KEY_CODE_MASK):
			return true
	return false


static func key_text(b: Dictionary) -> String:
	var parts: Array[String] = []
	for k in b["keys"]:
		parts.append(OS.get_keycode_string(int(k)))
	return ", ".join(parts)


# ----------------------------------------------------------------- page ---

var _grid_box: VBoxContainer
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
	var panel := UiKit.panel(Color(0.1, 0.12, 0.1, 1.0), 12)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 10
	panel.offset_top = 10
	panel.offset_right = -10
	panel.offset_bottom = -10
	add_child(panel)
	var v := UiKit.vbox(8)
	panel.add_child(v)
	var head := UiKit.hbox(8)
	v.add_child(head)
	var title := UiKit.label("Controls", 20, Color(0.85, 0.85, 0.85))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	close_button = UiKit.button("Close", close, 96, 17)
	close_button.custom_minimum_size.y = 48
	head.add_child(close_button)
	var scroll := TouchScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_grid_box = UiKit.vbox(10)
	_grid_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid_box)


func open() -> void:
	_fill()
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _fill() -> void:
	for c in _grid_box.get_children():
		c.queue_free()
	var touch := UiScale.is_touch()
	var cols := ["touch", "mouse"] if touch else ["mouse", "touch"]
	var names := {"touch": "Touch", "mouse": "Mouse and keyboard"}
	_grid_box.add_child(UiKit.label("Showing %s first (this device). Keys are listed after the mouse input." % names[cols[0]].to_lower(),
		13, UiKit.COL_DIM, true))
	for sec in SECTIONS:
		_grid_box.add_child(UiKit.label(SECTION_NAMES[sec], 18, UiKit.COL_GOLD))
		var g := GridContainer.new()
		g.columns = 3
		g.add_theme_constant_override("h_separation", 14)
		g.add_theme_constant_override("v_separation", 6)
		g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid_box.add_child(g)
		g.add_child(UiKit.label("Action", 14, UiKit.COL_DIM))
		for c in cols:
			g.add_child(UiKit.label(names[c], 14, Color(1, 0.95, 0.7) if c == cols[0] else UiKit.COL_DIM))
		for b in BINDINGS:
			if str(b["s"]) != sec or b.get("hidden", false):
				continue
			g.add_child(_cell(str(b["label"]), Color.WHITE))
			for c in cols:
				var text := str(b[c])
				if c == "mouse" and not (b["keys"] as Array).is_empty():
					text = (text + "; " if text != "-" else "") + "key " + key_text(b)
				g.add_child(_cell(text, Color(1, 0.95, 0.8) if c == cols[0] else Color(0.8, 0.8, 0.78)))


func _cell(text: String, col: Color) -> Label:
	var l := UiKit.label(text, 14, col, true)
	l.custom_minimum_size.x = 120
	return l


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_F1:
			close()
		get_viewport().set_input_as_handled()
