extends Control
## The unit book: a full-screen overlay listing every unit type, with one
## UnitEntry page shown at a time (list on the left, Previous / Next, Close),
## and a last page, "Terrain", explaining the ground rules with the sim's
## own numbers. Used from the start menu and from the battle HUD; it only
## emits `closed` and never touches the sim.

signal closed

const TouchScroll := preload("res://game/touch_scroll.gd")
const UT := preload("res://sim/unit_types.gd")
const Icons := preload("res://game/unit_icons.gd")
const IconView := preload("res://game/unit_icon_view.gd")
const UnitEntry := preload("res://game/unit_entry.gd")
const BattleSim := preload("res://sim/battle_sim.gd")

var entry: UnitEntry
## Page shown: a unit type, or UT.count() for the Terrain page.
var current := 0
var terrain_page: ScrollContainer
var terrain_text: Label
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
	var lscroll := TouchScroll.new()
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
	var tb := Button.new()
	tb.custom_minimum_size = Vector2(200, 56)
	tb.toggle_mode = true
	tb.focus_mode = Control.FOCUS_NONE
	tb.text = "Terrain"
	tb.add_theme_font_size_override("font_size", 16)
	tb.pressed.connect(show_type.bind(UT.count()))
	list.add_child(tb)
	_list.append(tb)
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
	prev_button.pressed.connect(func(): show_type((current + _pages() - 1) % _pages()))
	head.add_child(prev_button)
	next_button = _button("Next >")
	next_button.pressed.connect(func(): show_type((current + 1) % _pages()))
	head.add_child(next_button)
	close_button = _button("Close")
	close_button.pressed.connect(close)
	head.add_child(close_button)
	entry = UnitEntry.new()
	page.add_child(entry)
	terrain_page = TouchScroll.new()
	terrain_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	terrain_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terrain_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	terrain_page.visible = false
	page.add_child(terrain_page)
	terrain_text = Label.new()
	terrain_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	terrain_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terrain_text.add_theme_font_size_override("font_size", 16)
	terrain_text.text = terrain_help()
	terrain_page.add_child(terrain_text)


func _pages() -> int:
	return UT.count() + 1


## The Terrain page, in plain words, with the numbers the sim uses.
static func terrain_help() -> String:
	var climb := "%d%% (light infantry, javelins) to %d%% (pikes), cavalry %d%%" % [
		UT.stat(UT.LIGHT, "climb"), UT.stat(UT.PIKE, "climb"), UT.stat(UT.CAVALRY, "climb")]
	var lines: Array[String] = [
		"TERRAIN",
		"",
		"Reading the ground. The field is drawn like a contour map: each thin line is 2 m higher or lower than the next, every fifth line is a little darker, slopes facing the light (upper left) are lighter and slopes facing away darker, and higher ground is slightly paler. Lines close together mean a steep slope. The faint grid squares are 50 m.",
		"",
		"Moving. Each 10%% of uphill slope costs a unit some of its speed: %s, packed artillery %d-%d%%. A slope of 10%% rises 1 m in 10 m. Never slower than %d%% of normal (artillery %d%%). A gentle downhill (up to 10%%) is up to %d%% faster; downhill steeper than %d%% slows again (cavalry twice as much). Moving across ground steeper than %d%% loosens a formation: a pike block's wall comes down and spearmen cannot brace until they stand again." % [
			climb, UT.stat(UT.BOLT, "climb"), UT.stat(UT.STONE, "climb"), BattleSim.TER_MIN_FAC / 10,
			BattleSim.TER_MIN_FAC_ART / 10, BattleSim.TER_DOWN_BONUS / 10,
			(BattleSim.TER_STEEP * 100 + 2048) / 4096, (BattleSim.TER_STEEP * 100 + 2048) / 4096],
		"",
		"Fighting. A man striking down at his opponent hits a little more often: +%.1f%% for each 10%% of slope between them, at most +%.0f%%, and the man below hits that much less. Small per blow, but a long fight adds it up: between two equal units a moderate slope (10-15%%) is worth roughly a 60-70%% chance of winning to the side above, a steep one (25%%) about 85%%. Never a sure thing." % [
			BattleSim.MELEE_H_K / 100.0, BattleSim.MELEE_H_CAP / 10.0],
		"",
		"Charging. Cavalry riding down onto a man hits harder (+%d%% per 10%% of slope, at most +%d%%); riding up into him, weaker (down to -%d%%). Uphill the horses cannot build a full charge at all: on a 20%% climb only a weak one. A good downhill run builds momentum faster." % [
			BattleSim.CHG_H_K / 10, BattleSim.CHG_H_MAX - 100, 100 - BattleSim.CHG_H_MIN],
		"",
		"Shooting. From higher ground missiles reach further, and shooting uphill they fall short by as much: arrows and stones %.1f m for each metre of height, javelins %.1f m, bolts %.1f m (at most %d%% of the range). The range ring of a selected unit bends to show this. Arrows and stones arc over hills; javelins and bolts fly flat and cannot shoot through a crest. A target hidden by the ground is shown with a broken red line and a cross where the ground gets in the way; javelin units ordered to shoot it walk closer until they can. A bolt is stopped by rising ground and flies over the heads of men below its line." % [
			UT.stat(UT.ARCHER, "m_hgain") / 100.0, UT.stat(UT.JAVELIN, "m_hgain") / 100.0,
			UT.stat(UT.BOLT, "m_hgain") / 100.0, BattleSim.RANGE_H_CAP],
		"",
		"Stones bounce on %d%% less far for each 10%% they land uphill, and %d%% further downhill." % [
			BattleSim.STONE_UP_K / 10, BattleSim.STONE_DOWN_K / 10],
		"",
		"Pikes. A pike block standing on ground steeper than %d%% loses its order %d%% faster when struck in the flank, the rear or by a charge." % [
			(BattleSim.TER_STEEP * 100 + 2048) / 4096, BattleSim.PIKE_STEEP_DIS - 100],
		"",
		"The enemy. The AI deploys on nearby higher ground, stops on a crest while its archers shoot, holds a hill it stands on (up to 4 minutes, unless outshot) and lets you climb to it, goes round to a gentler side rather than straight up a steep slope, avoids charging uphill, and puts its archers and engines on rises with a clear line of fire.",
		"",
		"Ordered moves and attacks show 'uphill' or 'downhill' with the average slope when it is 4% or more.",
	]
	return "\n".join(lines)


func open(ty: int = -1) -> void:
	visible = true
	show_type(current if ty < 0 else ty)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func show_type(ty: int) -> void:
	current = clampi(ty, 0, UT.count())
	for k in _list.size():
		_list[k].set_pressed_no_signal(k == current)
	var terr := current == UT.count()
	terrain_page.visible = terr
	entry.visible = not terr
	if terr:
		terrain_page.scroll_vertical = 0
	else:
		entry.set_unit_type(current, side_color)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				close()
			KEY_LEFT, KEY_UP:
				show_type((current + _pages() - 1) % _pages())
			KEY_RIGHT, KEY_DOWN:
				show_type((current + 1) % _pages())
		get_viewport().set_input_as_handled()


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 54)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 17)
	return b
