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
const UT := preload("res://sim/unit_types.gd")
const RoleTile := preload("res://game/role_tile.gd")
const RoleBadge := preload("res://game/role_badge.gd")

const SECTIONS := ["battle", "campaign", "general"]
const SECTION_NAMES := {"battle": "Battle", "campaign": "Campaign map", "general": "General"}

## keys: Array of keycodes; a key may carry modifiers as "ctrl+", "shift+",
## "alt+" through KEY_MASK bits (e.g. KEY_A | KEY_MASK_CTRL).
static var BINDINGS: Array = [
	# ---- battle: selecting
	{"id": "select", "s": "battle", "label": "Select a unit",
		"touch": "Tap the unit's symbol (a near miss counts) or its card, also with units selected; double tap its body selects too", "mouse": "Left click the unit, its symbol or its card (left click the empty ground: deselect)", "keys": []},
	{"id": "select_add", "s": "battle", "label": "Add / remove a unit from the selection",
		"touch": "+ Add, then tap units or cards", "mouse": "Shift+click or Ctrl+click", "keys": []},
	{"id": "select_all", "s": "battle", "label": "Select all units",
		"touch": "All button", "mouse": "All button", "keys": [KEY_A | KEY_MASK_CTRL, KEY_1 | KEY_MASK_ALT]},
	{"id": "select_line", "s": "battle", "label": "Select the line (swords, spears, pikes, musketeers)",
		"touch": "Line button", "mouse": "Line button", "keys": [KEY_2 | KEY_MASK_ALT]},
	{"id": "select_skirmish", "s": "battle", "label": "Select skirmishers and missile troops",
		"touch": "Skirm button", "mouse": "Skirm button", "keys": [KEY_3 | KEY_MASK_ALT]},
	{"id": "select_shock", "s": "battle", "label": "Select shock foot",
		"touch": "Shock button", "mouse": "Shock button", "keys": [KEY_4 | KEY_MASK_ALT]},
	{"id": "select_horse", "s": "battle", "label": "Select horse (and camels, elephants)",
		"touch": "Horse button", "mouse": "Horse button", "keys": [KEY_5 | KEY_MASK_ALT]},
	{"id": "select_guns", "s": "battle", "label": "Select artillery",
		"touch": "Guns button", "mouse": "Guns button", "keys": [KEY_6 | KEY_MASK_ALT]},
	{"id": "group_select", "s": "battle", "label": "Control groups: select group 1 to 9 (the same digit again within 0.4 s centres the camera on it)",
		"touch": "The Groups chips on the bar: tap a group's chip to select it, tap again within 0.4 s to centre on it", "mouse": "Press the digit (the group's units replace the selection)",
		"keys": [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9], "key_label": "1 to 9"},
	{"id": "group_set", "s": "battle", "label": "Control groups: the selection becomes group 1 to 9 (replacing it)",
		"touch": "The + chip makes the next free group from the selection; hold a group chip, Set to selection", "mouse": "Ctrl + digit",
		"keys": [KEY_1 | KEY_MASK_CTRL, KEY_2 | KEY_MASK_CTRL, KEY_3 | KEY_MASK_CTRL, KEY_4 | KEY_MASK_CTRL, KEY_5 | KEY_MASK_CTRL, KEY_6 | KEY_MASK_CTRL,
			KEY_7 | KEY_MASK_CTRL, KEY_8 | KEY_MASK_CTRL, KEY_9 | KEY_MASK_CTRL], "key_label": "Ctrl+1 to Ctrl+9"},
	{"id": "group_add", "s": "battle", "label": "Control groups: add the selection to group 1 to 9",
		"touch": "Hold a group chip, Add selection (Clear empties it)", "mouse": "Shift + digit",
		"keys": [KEY_1 | KEY_MASK_SHIFT, KEY_2 | KEY_MASK_SHIFT, KEY_3 | KEY_MASK_SHIFT, KEY_4 | KEY_MASK_SHIFT, KEY_5 | KEY_MASK_SHIFT, KEY_6 | KEY_MASK_SHIFT,
			KEY_7 | KEY_MASK_SHIFT, KEY_8 | KEY_MASK_SHIFT, KEY_9 | KEY_MASK_SHIFT], "key_label": "Shift+1 to Shift+9"},
	{"id": "deselect", "s": "battle", "label": "Deselect all",
		"touch": "Two-finger tap, or the None button (with the group buttons)", "mouse": "None button", "keys": [KEY_ESCAPE]},
	{"id": "undo", "s": "battle", "label": "Undo the last order (up to 5 batches)",
		"touch": "The Undo toast above the cards, naming the order (shown for 6 s after each order)", "mouse": "Undo button, or the key", "keys": [KEY_Z | KEY_MASK_CTRL]},
	{"id": "box_select", "s": "battle", "label": "Select units in a box",
		"touch": "-", "mouse": "Left drag: a box (Shift adds)", "keys": []},
	# ---- battle: orders
	{"id": "move", "s": "battle", "label": "Move (keep frontage)",
		"touch": "Tap the ground (or the body of one of your units, away from its symbol). With Confirm orders on, the tap places a ghost and Go sends it (see Placement tool); a unit that is fighting needs a held tap (0.25 s) when it is off", "mouse": "Right click the ground (the whole selection moves, keeping its shape)", "keys": []},
	{"id": "move_run", "s": "battle", "label": "Move running",
		"touch": "Double tap the ground (with Confirm orders on: the ghost's Run is lit; Go sends it)", "mouse": "Double right click the ground", "keys": []},
	{"id": "line", "s": "battle", "label": "Draw the front line (position, width, facing; at most one rank long: the line stops there)",
		"touch": "Drag along the ground with units selected (with Confirm orders on: the line is a ghost until Go)", "mouse": "Right drag with units selected (the units spread along the line)", "keys": []},
	{"id": "waypoints", "s": "battle", "label": "Waypoints: add a stop after the current move (up to 8 a unit; they march from one to the next and keep the last one's facing; any other order drops them)",
		"touch": "Waypoints button (lit), then tap the ground or drag a line for each stop (double tap: run to it); tap an enemy unit (or its symbol) to add the attack as the last point (a crossed-swords dot on the enemy, a dashed link from the last stop; nothing can follow it); tap a numbered dot or the swords dot to take that stop out; it goes off when the selection changes, or a two-finger tap",
		"mouse": "Shift + right click the ground (Shift + right drag: a line); Shift + right click an enemy adds the attack as the last point; Shift + left click a numbered dot takes that stop out", "keys": []},
	{"id": "place_tool", "s": "battle", "label": "Placement tool (Options > Confirm orders: On, or Auto while you play by touch): a tap on the ground, a line drag or a double tap does not order, it places a ghost of the selection",
		"touch": "Drag the ghost's body handle to move it; its front handle (ahead of the line) to turn it, in 15 degree steps with a soft stop on its facing and on facing the nearest enemy; an end handle to widen or narrow it (one rank long at most). The toolbar: Go sends the order (once; the selection then clears, Undo names it), Run lights the run, Waypoint adds the ghost as the next stop and keeps the tool open, X drops the ghost. Tap the ground elsewhere to place it again; a two-finger tap drops it and deselects. Attacks, the chips and Withdraw order at once",
		"mouse": "The same with the right button (right click or right drag places the ghost) when Confirm orders is On; Auto leaves it off with the mouse", "keys": []},
	{"id": "stray_taps", "s": "battle", "label": "Stray touches are ignored",
		"touch": "A tap within 0.3 s after a pinch or a two-finger pan, or a finger that moved past the pan distance, orders nothing; with Confirm orders off a tap that orders a unit that is fighting needs a held tap (0.25 s)", "mouse": "-", "keys": []},
	{"id": "attack", "s": "battle", "label": "Attack / shoot a unit",
		"touch": "Tap the enemy (or its symbol)", "mouse": "Right click the enemy", "keys": []},
	{"id": "attack_run", "s": "battle", "label": "Attack running / charge",
		"touch": "Double tap the enemy", "mouse": "Double right click the enemy", "keys": []},
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
	{"id": "stance", "s": "battle", "label": "Cycle stance",
		"touch": "Stance button", "mouse": "Stance button", "keys": [KEY_C]},
	{"id": "bounds", "s": "battle", "label": "Advance by bounds",
		"touch": "Bounds button", "mouse": "Bounds button", "keys": [KEY_B]},
	{"id": "occupy", "s": "battle", "label": "West towns: light the buildings the men can hold, look at one's sight lines, send them in (men at its windows, on its roof, at its door) / leave it",
		"touch": "Occupy button, tap a lit building to see its sight lines, tap it again to send them in, tap elsewhere to cancel", "mouse": "Occupy button, point at a lit building, click to send them in, Esc cancels", "keys": [KEY_I]},
	{"id": "deploy", "s": "battle", "label": "Artillery: pack up / set up",
		"touch": "Deploy button", "mouse": "Deploy button", "keys": [KEY_D | KEY_MASK_SHIFT]},
	{"id": "refill", "s": "battle", "label": "Artillery: refill from the baggage; missile troops: refill at the ammunition wagon",
		"touch": "Refill button", "mouse": "Refill button", "keys": [KEY_Y]},
	{"id": "ammo", "s": "battle", "label": "Second ammunition kind (fire arrows, heavy bolts ...) / the standard kind",
		"touch": "Ammo button", "mouse": "Ammo button", "keys": [KEY_V]},
	{"id": "forage", "s": "battle", "label": "Missile troops in woods: make arrows / javelins (cannot move or shoot meanwhile)",
		"touch": "Forage button (in woods)", "mouse": "Forage button (in woods)", "keys": [KEY_J]},
	{"id": "man_wall", "s": "battle", "label": "Walls (defending): up onto the stretch you click, facing out (M: the nearest stretch, facing the enemy)",
		"touch": "Tap the wall stretch you want (the wall, a tower or the walkway); it lights up", "mouse": "Click the wall stretch you want (it lights under the mouse)",
		"keys": [KEY_M]},
	{"id": "drop", "s": "battle", "label": "Equipment: put down the ladders, the ram, a wagon or engines (take up: tap the piece)",
		"touch": "Drop button", "mouse": "Drop button", "keys": [KEY_X]},
	{"id": "land", "s": "battle", "label": "A ship off the shore: her landing party goes ashore in the boats",
		"touch": "Land button", "mouse": "Land button", "keys": [KEY_L]},
	{"id": "release", "s": "battle", "label": "War dogs: release the pack, then tap an enemy unit within 80 m",
		"touch": "Release button, then tap the enemy", "mouse": "Release button, then click the enemy", "keys": [KEY_U]},
	{"id": "sabotage", "s": "battle", "label": "Assassin: sabotage, then tap an enemy battery (wrecks its engines) or a shut gate (unbars it)",
		"touch": "Sabotage button, then tap the target", "mouse": "Sabotage button, then click the target", "keys": [KEY_B | KEY_MASK_SHIFT]},
	{"id": "attempt", "s": "battle", "label": "Assassin: an attempt, then tap an enemy hero or general (once a battle)",
		"touch": "Attempt button, then tap the target", "mouse": "Attempt button, then click the target", "keys": [KEY_T]},
	{"id": "parley", "s": "battle", "label": "Diplomat: parley, then tap a routing or wavering enemy unit",
		"touch": "Parley button, then tap the unit", "mouse": "Parley button, then click the unit", "keys": [KEY_P | KEY_MASK_SHIFT]},
	{"id": "come_down", "s": "battle", "label": "Walls: down off the wall into the street inside (Shift+M: by the nearer stair)",
		"touch": "Tap the street or ground inside the wall", "mouse": "Click the street or ground inside the wall", "keys": [KEY_M | KEY_MASK_SHIFT]},
	{"id": "withdraw", "s": "battle", "label": "Withdraw the selected units",
		"touch": "Withdraw button", "mouse": "Withdraw button", "keys": []},
	{"id": "withdraw_all", "s": "battle", "label": "Withdraw the whole army",
		"touch": "Withdraw army, tap twice", "mouse": "Withdraw army, click twice", "keys": []},
	# ---- battle: deployment phase
	{"id": "place", "s": "battle", "label": "Deployment: place units (inside your blue zone; the men stand there at once)",
		"touch": "Tap the ground, drag a line, or three-finger drag a group (as moving)",
		"mouse": "Right click, right drag or Alt+left drag (as moving); a point outside the zone is kept to its edge", "keys": []},
	{"id": "ready", "s": "battle", "label": "Deployment: ready, start the battle (it starts when every player is ready, or when the time runs out)",
		"touch": "Start battle button", "mouse": "Start battle button", "keys": [KEY_ENTER, KEY_KP_ENTER]},
	# ---- battle: view
	{"id": "pan", "s": "battle", "label": "Pan the view",
		"touch": "Drag with one finger (nothing selected) or two fingers",
		"mouse": "Middle drag (right drag with nothing selected); W A S D or arrow keys", "keys": []},
	{"id": "pan_up", "s": "battle", "label": "Pan up", "touch": "-", "mouse": "-", "keys": [KEY_W, KEY_UP], "hidden": true},
	{"id": "pan_down", "s": "battle", "label": "Pan down", "touch": "-", "mouse": "-", "keys": [KEY_S, KEY_DOWN], "hidden": true},
	{"id": "pan_left", "s": "battle", "label": "Pan left", "touch": "-", "mouse": "-", "keys": [KEY_A, KEY_LEFT], "hidden": true},
	{"id": "pan_right", "s": "battle", "label": "Pan right", "touch": "-", "mouse": "-", "keys": [KEY_D, KEY_RIGHT], "hidden": true},
	{"id": "camera_turn", "s": "battle", "label": "Turn the table (the camera turns about the middle of the screen; a twist keeps turning a little when let go)",
		"touch": "Twist two fingers (or drag three fingers across, with nothing selected)", "mouse": "Right drag with nothing selected (Alt+right drag with a selection); Q / E held", "keys": []},
	{"id": "camera_tilt", "s": "battle", "label": "Tilt the camera (from 25 to 60 degrees above the table)",
		"touch": "Three fingers with nothing selected, drag up or down", "mouse": "Right drag up or down (as turning); Home / End held", "keys": []},
	{"id": "camera_tilt_up", "s": "battle", "label": "Tilt up", "touch": "-", "mouse": "-", "keys": [KEY_HOME], "hidden": true},
	{"id": "camera_tilt_down", "s": "battle", "label": "Tilt down", "touch": "-", "mouse": "-", "keys": [KEY_END], "hidden": true},
	{"id": "camera_map", "s": "battle", "label": "The map camera (nearly straight down, north up, the whole deployment or battle in view; pan and zoom work; again goes back to the camera you had; turning or tilting leaves it)",
		"touch": "The Map chip (a compass) in the top bar", "mouse": "The Map chip, or the key", "keys": [KEY_N]},
	{"id": "zoom", "s": "battle", "label": "Zoom",
		"touch": "Pinch", "mouse": "Mouse wheel; Page Up / Page Down", "keys": []},
	{"id": "zoom_in", "s": "battle", "label": "Zoom in", "touch": "-", "mouse": "-", "keys": [KEY_PAGEUP], "hidden": true},
	{"id": "zoom_out", "s": "battle", "label": "Zoom out", "touch": "-", "mouse": "-", "keys": [KEY_PAGEDOWN], "hidden": true},
	{"id": "pause", "s": "battle", "label": "Pause / resume",
		"touch": "Pause button", "mouse": "Pause button", "keys": [KEY_SPACE, KEY_P]},
	{"id": "speed_up", "s": "battle", "label": "Faster",
		"touch": "Speed button, then the slider", "mouse": "Speed button, then the slider", "keys": [KEY_EQUAL, KEY_KP_ADD]},
	{"id": "speed_down", "s": "battle", "label": "Slower",
		"touch": "Speed button, then the slider", "mouse": "Speed button, then the slider", "keys": [KEY_MINUS, KEY_KP_SUBTRACT]},
	{"id": "orders_overlay", "s": "battle", "label": "Show every unit's orders",
		"touch": "Orders button", "mouse": "Orders button", "keys": [KEY_O]},
	{"id": "unit_info", "s": "battle", "label": "Unit book page of a unit",
		"touch": "Long press its card (lift your finger without moving)", "mouse": "Right click its card, or hold the button on it", "keys": []},
	{"id": "card_reorder", "s": "battle", "label": "Reorder the unit cards (this battle, on your screen only; All / Line / Skirm / Shock / Horse / Guns select in this order)",
		"touch": "Long press a card until it lifts, then drag it between two cards", "mouse": "Drag a card between two cards", "keys": []},
	{"id": "readout", "s": "battle", "label": "Performance readout (short / full)",
		"touch": "Tap the readout, top left", "mouse": "Click the readout", "keys": [KEY_F3]},
	# ---- campaign
	{"id": "map_select_army", "s": "campaign", "label": "Select an army",
		"touch": "Tap its banner", "mouse": "Left click its banner (another faction's army or fleet: the same, to look at it)", "keys": []},
	{"id": "map_next_army", "s": "campaign", "label": "Next army",
		"touch": "-", "mouse": "-", "keys": [KEY_TAB]},
	{"id": "map_move", "s": "campaign", "label": "Move the selected army",
		"touch": "Tap a highlighted region (red: attack)", "mouse": "Right click the spot (or a highlighted region; red: attack). A left click only selects; right click your other army to merge it", "keys": []},
	{"id": "map_cancel_move", "s": "campaign", "label": "Cancel a planned move",
		"touch": "Tap its destination again, or Cancel move", "mouse": "Right click its destination again", "keys": []},
	{"id": "map_fleet", "s": "campaign", "label": "Fleets: select, sail, land, attack, join",
		"touch": "Tap a fleet, then the sea (sail), a coast (land), an enemy fleet (attack) or your own fleet (join it: beside it at once, else sail and merge on arriving)", "mouse": "Left click a fleet, then right click the sea (sail), a coast (land), an enemy fleet (attack) or your own fleet (join it)", "keys": []},
	{"id": "map_region", "s": "campaign", "label": "Region panel (buildings, raise a new army, garrison)",
		"touch": "Tap the region or its settlement", "mouse": "Left click the region or its settlement", "keys": []},
	{"id": "map_army_reorder", "s": "campaign", "label": "Reorder an army's units (an order: the order they take the field in)",
		"touch": "On the army card, long press a unit until it lifts, then drag it", "mouse": "On the army card, drag a unit", "keys": []},
	{"id": "map_recruit_info", "s": "campaign", "label": "Unit page before recruiting",
		"touch": "Tap the unit in the recruit list (the army card of an army at your city)", "mouse": "Click the unit", "keys": []},
	{"id": "map_deselect", "s": "campaign", "label": "Close the panel / deselect",
		"touch": "Deselect button (bottom right), two-finger tap, tap the sea, or Close", "mouse": "Left click empty map or sea, the Deselect button, or Close", "keys": [KEY_ESCAPE]},
	{"id": "map_pan", "s": "campaign", "label": "Pan the map",
		"touch": "Drag", "mouse": "Left, right or middle drag (a right click without a drag orders); W A S D or arrow keys", "keys": []},
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
	if b.has("key_label"):
		return str(b["key_label"])
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
	_fill_chips()
	_fill_roles()


## The Chips section (battle HUD pass): what the bottom bar's chips and fixed buttons mean.
func _fill_chips() -> void:
	var head := UiKit.label("Chips", 18, UiKit.COL_GOLD)
	head.name = "chips_head"
	_grid_box.add_child(head)
	for line in [
		["Halt, Run, Withdraw", "Always on the bar with a selection (Run is hidden when only guns are selected): stop and drop orders, walk or run, leave the battle."],
		["Chips", "The bar's other buttons are chips, one per order the selected units can take, in a fixed order. A tap cycles a toggle (Fire: at will / hold). A chip dimmed with 'not all selected units' only works for some of the selection."],
		["Auto / Hold / Use now", "Abilities (Grenades, Pistols, Caracole, Target, Countermarch) have three states. Auto: the unit decides. Hold: it never uses it. Use now: tap a target on the field (lit when armed); Esc or the chip again cancels back to Auto. Pistols have Auto and Hold only."],
		["Countermarch", "Musket lines fire by ranks: an opening volley, then one rank after another, so the fire never stops and the enemy stays shaken; the same shots as volleys. Auto: the last volley of every loaded man when an enemy comes within 40 m. Hold: volleys. Use now: no target to tap, rolling fire at any range. Not in buildings, on walls or in cover (every man shoots on his own there)."],
		["Clusters", "The chips sit in four groups with a small caption under each: Move (Bounds, Deploy, Waypoints, Release), Shoot (Target, Caracole, Fire, Countermarch, Skirmish, Ammo, Refill, Forage), Fight (Stance, Occupy, Grenades, Pistols) and Kit (Drop, Gift, the character acts). Under More the same captions head the list."],
		["Long press", "Hold a chip (touch or mouse, about half a second, without moving) for what it does, its state, each of its states, and a link to the unit book. A tap anywhere else closes it; a short tap still gives the order."],
		["Two rows", "When the groups do not fit one row, the bar grows a second row above itself (chips a little lower); a group is never split between the rows. What still does not fit is under More. The battle menu's Chips page lists every chip with its states."],
		["More", "A chip that does not fit the bar is under More, which opens a list above it. Nothing is ever cut off."],
		["Phone capsule", "On a phone the selection capsule shows the role badges: Line (bars), Skirm (scatter), Shock (sword), Horse (horseshoe), Guns (a gun on a wheel). The role keys are Alt+1 to Alt+6 (the digits alone select control groups)."],
		["Groups", "Control groups: a chip per group you have made (1 to 9) and a + chip that makes the next one from the selection. Tap a chip to select the group, tap it again within 0.4 s to centre the camera on it, hold it for Set to selection, Add selection and Clear. A number on a unit's card says which groups it is in. Keys: Ctrl+digit sets, Shift+digit adds, the digit selects, the digit twice centres."],
		["Card strip", "A card shows a small glyph for each chip that is not at its default: hold fire, an ability on Hold or armed, the Cover stance. Its tip lists them in words."]]:
		var row := UiKit.hbox(10)
		var v := UiKit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		v.add_child(UiKit.label(str(line[0]), 15, Color(1, 0.95, 0.7)))
		v.add_child(UiKit.label(str(line[1]), 14, Color(0.9, 0.9, 0.85), true))
		_grid_box.add_child(row)


## The Roles page: the ten roles, each with its badge and the two lines of how it plays.
func _fill_roles() -> void:
	var head := UiKit.label("Roles", 18, UiKit.COL_GOLD)
	head.name = "roles_head"
	_grid_box.add_child(head)
	_grid_box.add_child(UiKit.label("Every unit has one role: its badge sits on the unit's card, and the bar's filters select by it (Line, Skirm = skirmishers and missile troops, Shock, Horse, Guns).",
		13, UiKit.COL_DIM, true))
	for rk in UT.ROLE_ORDER:
		var row := UiKit.hbox(10)
		row.name = "role_" + rk
		var tile := RoleTile.new(rk, 30.0)
		tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(tile)
		var v := UiKit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		var nm := UiKit.label(str(UT.ROLES[rk]["name"]), 16, RoleBadge.colour(rk).lightened(0.35))
		v.add_child(nm)
		v.add_child(UiKit.label(RoleBadge.plays(rk), 14, Color(0.9, 0.9, 0.85), true))
		_grid_box.add_child(row)


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
