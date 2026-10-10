extends Control
## The campaign map's key (bottom left): a small "Key" button; open, a
## scrollable list of samples, each drawn with the map's own painters and
## colours (map_overlay.gd, map_view.gd static draw_* and COL_*), so the key
## cannot drift from the drawing code, and what each one means. The rows
## follow the campaign's format: version 6 (the continuous overworld: paths
## along cells, reach, zones of control, links, merge glyphs, stances,
## rivers, fords, bridges, roads and hills),
## version 5 (free movement: region destinations, hops solid / dotted) or
## older (arrows).
##
## Open / closed is a view preference in user://settings.cfg ([ui]
## map_key), never in the campaign state. The campaign screen places the
## panel (clear of the hint and End turn) and closes it on a tap on the map
## on phones.

signal toggled(open: bool)

const Overlay := preload("res://game/campaign/map_overlay.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const TouchScroll := preload("res://game/touch_scroll.gd")
const CData := preload("res://campaign/cdata.gd")

const SETTINGS := "user://settings.cfg"
const BUTTON_W := 76.0
const BUTTON_H := 48.0
const PANEL_W := 300.0
const SAMPLE := Vector2(66, 30)
const MARGIN := 8.0
## Icons of the key's section headings (the rows show the map's own marks).
const SECTION_ICONS := {"Planned marches": "move", "Planned moves": "move", "Armies": "men", "Map": "view_map"}

## Format shown: 6 the overworld, 5 free movement, 4 older (arrows).
var format := -1
var expanded := false
var persist := true  # save open / closed (tests and screenshots switch it off)
var own_col := CData.faction_color(0)
var enemy_col := CData.faction_color(1)

var button: Button
var panel: PanelContainer
var header: Button
var scroll: ScrollContainer
var list: VBoxContainer


func _init() -> void:
	name = "map_key"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	button = Kit.icon_button("Key", "key", func(): set_expanded(true), BUTTON_W)
	button.name = "map_key_button"
	button.custom_minimum_size = Vector2(BUTTON_W, BUTTON_H)
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	button.offset_left = MARGIN
	button.offset_right = MARGIN + BUTTON_W
	button.offset_bottom = -MARGIN
	button.offset_top = -MARGIN - BUTTON_H
	add_child(button)
	panel = Kit.panel(Color(Kit.PANEL_BG, 0.94), 6)
	panel.name = "map_key_panel"
	panel.visible = false
	add_child(panel)
	var v := Kit.vbox(4)
	panel.add_child(v)
	header = Kit.button("Map key   ×", func(): set_expanded(false), 0, Kit.FONT)
	header.name = "map_key_header"
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.flat = true
	header.add_theme_color_override("font_color", Kit.COL_GOLD)
	header.add_theme_color_override("font_hover_color", Kit.COL_GOLD.lightened(0.3))
	Kit.set_icon(header, "key", Kit.COL_GOLD)
	v.add_child(header)
	scroll = TouchScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	list = Kit.vbox(3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)


static func load_pref() -> bool:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) != OK:
		return false
	return int(cf.get_value("ui", "map_key", 0)) != 0


static func save_pref(on: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("ui", "map_key", 1 if on else 0)
	cf.save(SETTINGS)


func set_expanded(on: bool) -> void:
	if on == expanded and panel.visible == on:
		return
	expanded = on
	panel.visible = on
	button.visible = not on
	if persist:
		save_pref(on)
	toggled.emit(on)


## The rows for a format (6, 5 or older), rebuilt only when it changes.
func set_format(p_format: int, p_own: Color, p_enemy: Color) -> void:
	if p_format == format and p_own == own_col and p_enemy == enemy_col:
		return
	format = p_format
	own_col = p_own
	enemy_col = p_enemy
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	for r in rows():
		if r.size() == 1:
			var s := Kit.label(str(r[0]), Kit.FONT_SMALL, Kit.COL_DIM)
			if SECTION_ICONS.has(str(r[0])):
				Kit.label_icon(s, str(SECTION_ICONS[str(r[0])]))
			s.set_meta("key_section", true)
			list.add_child(s)
			continue
		var h := Kit.hbox(8)
		h.set_meta("key_row", true)
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		var smp := Sample.new()
		smp.painter = r[1]
		h.add_child(smp)
		var l := Kit.label(str(r[0]), Kit.FONT_SMALL, Color.WHITE, true)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(l)
		list.add_child(h)


## Number of sample rows shown (sections not counted).
func row_count() -> int:
	var n := 0
	for c in list.get_children():
		if c.has_meta("key_row") and not c.is_queued_for_deletion():
			n += 1
	return n


## Place the open panel: its bottom edge at `bottom`, its top no higher than
## `top` (screen px).
func place(top: float, bottom: float, vp_w: float) -> void:
	if not panel.visible:
		return
	var w := minf(PANEL_W, vp_w - 2.0 * MARGIN)
	var room := maxf(bottom - top, 120.0)
	var want := list.get_combined_minimum_size().y
	var hh := header.get_combined_minimum_size().y + 4.0 + 12.0  # header, gap, panel margins
	var sh := minf(want, room - hh)
	if not is_equal_approx(scroll.custom_minimum_size.y, sh) or not is_equal_approx(scroll.custom_minimum_size.x, w - 12.0):
		scroll.custom_minimum_size = Vector2(w - 12.0, sh)
		panel.custom_minimum_size = Vector2(w, 0)
		panel.reset_size()
	var pos := Vector2(MARGIN, bottom - panel.size.y)
	if not panel.position.is_equal_approx(pos):
		panel.position = pos


## [label, painter(ci, size)] per row, [section title] for a heading.
func rows() -> Array:
	var out: Array = []
	var m := 0.8
	var oc := own_col
	var ec := enemy_col
	if format >= 6:
		out.append(["Planned marches"])
		out.append(["March this turn", func(ci: Control, sz: Vector2):
			_land(ci, sz)
			Overlay.draw_path_step(ci, _l(sz), _r(sz), Overlay.COL_MOVE, true, m)])
		out.append(["March in later turns", func(ci: Control, sz: Vector2):
			_land(ci, sz)
			Overlay.draw_path_step(ci, _l(sz), _r(sz), Overlay.COL_MOVE, false, m)])
		out.append(["Where this turn's march ends", func(ci: Control, sz: Vector2):
			_land(ci, sz)
			var mid := (_l(sz) + _r(sz)) * 0.5
			Overlay.draw_path_step(ci, _l(sz), mid, Overlay.COL_MOVE, true, m)
			Overlay.draw_path_step(ci, mid, _r(sz), Overlay.COL_MOVE, false, m)
			Overlay.draw_turn_end(ci, mid, Overlay.COL_MOVE, m)])
		out.append(["Attack an army or assault a city", _path_row("attack", "", m)])
		out.append(["Lay siege to a city", _path_row("siege", "", m)])
		out.append(["Go inside your own walls", _path_row("inside", "", m)])
		out.append(["Merge into your army", _path_row("merge", "", m)])
		out.append(["Too many units to merge (over %d)" % CData.ARMY_MAX, func(ci: Control, sz: Vector2):
			_land(ci, sz)
			Overlay.draw_path_step(ci, _l(sz), _r(sz), Overlay.path_color("merge", "Too many"), true, m)])
		out.append(["Selected army"])
		out.append(["Reach this turn", func(ci: Control, sz: Vector2):
			_land(ci, sz)
			var rc := Rect2(Vector2(6, 4), sz - Vector2(12, 8))
			ci.draw_rect(rc, MapView.COL_REACH)
			MapView.draw_reach_edge(ci, _closed(rc), 1.0)])
		out.append(["Reach next turn", func(ci: Control, sz: Vector2):
			_land(ci, sz)
			MapView.draw_next_edge(ci, _closed(Rect2(Vector2(6, 4), sz - Vector2(12, 8))), 1.0)])
		out.append(["Enemy zone of control", func(ci: Control, sz: Vector2):
			_land(ci, sz)
			Overlay.draw_zone(ci, sz * 0.5, sz.y * 0.42)])
		out.append(["Support: a friendly army close enough to help", func(ci: Control, sz: Vector2):
			_land(ci, sz)
			Overlay.draw_link(ci, _l(sz), _r(sz), 0)])
		out.append(["Enemy it can attack this turn", func(ci: Control, sz: Vector2):
			_land(ci, sz)
			Overlay.draw_link(ci, _l(sz), _r(sz), 1)])
		out.append(["Your army it can merge into (in reach, room for the units)", _glyph_row(0)])
		out.append(["Ally's army next to it: give it units", _glyph_row(1)])
	elif format == 5:
		out.append(["Planned marches"])
		out.append(["March this turn", _hop_row(Overlay.COL_MOVE, true)])
		out.append(["March in later turns", _hop_row(Overlay.COL_MOVE, false)])
		out.append(["Attack or assault", _hop_row(Overlay.COL_ATTACK, true)])
		out.append(["Lay siege", _hop_row(Overlay.COL_SIEGE, true)])
	else:
		out.append(["Planned moves"])
		out.append(["Move", _arrow_row(Overlay.COL_MOVE)])
		out.append(["Attack or assault", _arrow_row(Overlay.COL_ATTACK)])
		out.append(["Lay siege", _arrow_row(Overlay.COL_SIEGE)])
	if format <= 5:
		out.append(["Selected army"])
		out.append(["Can march there this turn", _target_row(false, 0)])
		if format == 5:
			out.append(["Can reach in later turns", _target_row(false, 1)])
		out.append(["Enemy land: attack or siege", _target_row(true, 0)])
		out.append(["Cannot go there (tap for why)", func(ci: Control, sz: Vector2):
			_land(ci, sz)
			var rc := Rect2(Vector2(4, 3), sz - Vector2(8, 6))
			ci.draw_rect(rc, MapView.COL_BLOCKED)
			ci.draw_polyline(_closed(rc), MapView.COL_BLOCKED_EDGE, 2.0, true)
			MapView.draw_blocked_cross(ci, sz * 0.5, 1.0)])
	out.append(["Armies"])
	out.append(["Army: units in it; bar: strength (gold under 60%)", func(ci: Control, sz: Vector2):
		_land(ci, sz)
		Overlay.draw_banner(ci, Vector2(sz.x * 0.3, sz.y * 0.42), oc, 0.75, true, 8, 0.9)
		Overlay.draw_banner(ci, Vector2(sz.x * 0.72, sz.y * 0.42), oc, 0.75, true, 5, 0.4)])
	out.append(["White edge: a player's army; dark: the AI's", func(ci: Control, sz: Vector2):
		_land(ci, sz)
		Overlay.draw_banner(ci, Vector2(sz.x * 0.3, sz.y * 0.42), oc, 0.75, true, 6, 1.0)
		Overlay.draw_banner(ci, Vector2(sz.x * 0.72, sz.y * 0.42), ec, 0.75, false, 6, 1.0)])
	out.append(["Selected army", func(ci: Control, sz: Vector2):
		_land(ci, sz)
		Overlay.draw_banner(ci, Vector2(sz.x * 0.5, sz.y * 0.42), oc, 0.75, true, 6, 1.0, 3.0)])
	out.append(["Inside the walls", func(ci: Control, sz: Vector2):
		_land(ci, sz)
		Overlay.draw_tower(ci, Overlay.draw_banner(ci, Vector2(sz.x * 0.5, sz.y * 0.45), oc, 0.75, true, 6, 1.0), 0.75)])
	if format >= 6:
		out.append(["Stance: F forced march, D fortified, R raiding", func(ci: Control, sz: Vector2):
			_land(ci, sz)
			var k := 0
			for s in [CData.ST_FORCED, CData.ST_FORTIFY, CData.ST_RAID]:
				var p := Vector2(sz.x * (0.22 + 0.28 * k), sz.y * 0.5)
				Overlay.draw_stance(ci, Rect2(p - Vector2(10, 0), Vector2(10, 10)), int(s))
				k += 1])
	if format <= 5:
		out.append(["Grey dot: has moved this turn", func(ci: Control, sz: Vector2):
			_land(ci, sz)
			Overlay.draw_banner(ci, Vector2(sz.x * 0.5, sz.y * 0.45), oc, 0.75, true, 6, 1.0, 0.0, true)])
	if format >= 6:
		out.append(["Replay: the way an army just went", func(ci: Control, sz: Vector2):
			_land(ci, sz)
			Overlay.draw_trail(ci, PackedVector2Array([_l(sz), Vector2(sz.x * 0.5, sz.y * 0.3), _r(sz)]), ec)])
	out.append(["Map"])
	out.append(["Battle to fight", func(ci: Control, sz: Vector2):
		_land(ci, sz)
		Overlay.draw_battle(ci, sz * 0.5, 1.0)])
	out.append(["Siege (tents in the besieger's colour)", func(ci: Control, sz: Vector2):
		_land(ci, sz)
		var p := Vector2(sz.x * 0.5, sz.y * 0.68)
		Overlay.draw_site(ci, p, 4.0, oc, 0, 0.6)
		Overlay.draw_siege_ring(ci, p, 6.0, ec, 0.6)])
	out.append(["Walls: more towers, stronger walls", func(ci: Control, sz: Vector2):
		_land(ci, sz)
		Overlay.draw_site(ci, Vector2(sz.x * 0.3, sz.y * 0.5), 5.0, oc, 1, 0.8)
		Overlay.draw_site(ci, Vector2(sz.x * 0.72, sz.y * 0.5), 5.0, oc, 3, 0.8)])
	out.append(["White star: key city (victory goal)", func(ci: Control, sz: Vector2):
		_land(ci, sz)
		Overlay.draw_site(ci, sz * 0.5, Overlay.SITE_R[2] * 0.9, ec, 0, 0.9)
		Overlay.draw_key_city(ci, sz * 0.5, Overlay.SITE_R[2] * 0.9)])
	out.append(["Land in its owner's colour", func(ci: Control, sz: Vector2):
		var rc := Rect2(Vector2(2, 2), Vector2(sz.x * 0.5 - 3, sz.y - 4))
		var rc2 := Rect2(Vector2(sz.x * 0.5 + 1, 2), Vector2(sz.x * 0.5 - 3, sz.y - 4))
		for pair in [[rc, oc], [rc2, ec]]:
			var c: Color = pair[1]
			ci.draw_rect(pair[0], MapView.LAND.lerp(c, MapView.TINT))
			ci.draw_polyline(_closed((pair[0] as Rect2).grow(-1.5)), Color(c, MapView.OWNER_EDGE_A), MapView.OWNER_EDGE_W, true)])
	if format >= 6:
		# Roads, rivers and hills (2026-10-09): the map's own painters.
		out.append(["River: cross only at a ford or a bridge", func(ci: Control, sz: Vector2):
			_land(ci, sz)
			MapView.draw_river(ci, PackedVector2Array([Vector2(4, sz.y * 0.75), Vector2(sz.x * 0.5, sz.y * 0.4),
				Vector2(sz.x - 4, sz.y * 0.25)]), 1.0)])
		out.append(["Ford: crossing costs %d more" % CData.GRID_FORD, func(ci: Control, sz: Vector2):
			_land(ci, sz)
			MapView.draw_river(ci, PackedVector2Array([Vector2(sz.x * 0.5, 2), Vector2(sz.x * 0.5, sz.y - 2)]), 1.0)
			MapView.draw_ford(ci, sz * 0.5, Vector2(1, 0), 1.3)])
		out.append(["Bridge: crossing at no extra cost", func(ci: Control, sz: Vector2):
			_land(ci, sz)
			MapView.draw_river(ci, PackedVector2Array([Vector2(sz.x * 0.5, 2), Vector2(sz.x * 0.5, sz.y - 2)]), 1.0)
			MapView.draw_bridge(ci, sz * 0.5, Vector2(1, 0), 1.3)])
		out.append(["Road: %d a cell (open ground %d)" % [CData.GRID_ROAD, int(CData.GRID_COST[CData.FLAT])], func(ci: Control, sz: Vector2):
			_land(ci, sz)
			MapView.draw_road(ci, PackedVector2Array([_l(sz), Vector2(sz.x * 0.5, sz.y * 0.35), _r(sz)]), 1.0)])
		out.append(["Hills %d a cell, ridge %d (a battle there is on that ground)" % [int(CData.GRID_COST[CData.HILL]),
				int(CData.GRID_COST[CData.RIDGE])], func(ci: Control, sz: Vector2):
			_land(ci, sz)
			var cpx := sz.y * 0.8
			MapView.draw_hills(ci, MapView.hill_mark(Vector2(sz.x * 0.3, sz.y * 0.55), cpx, 0), 0, 1.6)
			MapView.draw_hills(ci, MapView.hill_mark(Vector2(sz.x * 0.72, sz.y * 0.55), cpx, 1), 1, 1.6)])
	if format <= 5:
		out.append(["Land route", func(ci: Control, sz: Vector2):
			_land(ci, sz)
			MapView.draw_route(ci, _l(sz), _r(sz), 1.0)])
	out.append(["Sea lane between ports", func(ci: Control, sz: Vector2):
		ci.draw_rect(Rect2(Vector2.ZERO, sz), MapView.SEA)
		MapView.draw_sea_lane(ci, _l(sz), _r(sz), 1.0)])
	return out


# Sample helpers.

static func _land(ci: Control, sz: Vector2) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, sz), MapView.LAND.darkened(0.3))


static func _l(sz: Vector2) -> Vector2:
	return Vector2(8, sz.y * 0.5)


static func _r(sz: Vector2) -> Vector2:
	return Vector2(sz.x - 8, sz.y * 0.5)


static func _closed(rc: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rc.position, Vector2(rc.end.x, rc.position.y), rc.end,
		Vector2(rc.position.x, rc.end.y), rc.position])


## A version 6 path of a kind with its end badge (none for a plain march).
static func _path_row(kind: String, caption: String, m: float) -> Callable:
	return func(ci: Control, sz: Vector2):
		_land(ci, sz)
		var col := Overlay.path_color(kind, caption)
		var e := Vector2(sz.x - 14, sz.y * 0.5)
		Overlay.draw_path_step(ci, _l(sz), e, col, true, m)
		Overlay.draw_intent(ci, e, kind, col, m)


static func _glyph_row(kind: int) -> Callable:
	return func(ci: Control, sz: Vector2):
		_land(ci, sz)
		Overlay.draw_merge_glyph(ci, sz * 0.5, kind, 1.0)


static func _hop_row(col: Color, this_turn: bool) -> Callable:
	return func(ci: Control, sz: Vector2):
		_land(ci, sz)
		Overlay.draw_hop(ci, _l(sz), _r(sz), col, this_turn, 0.8)


static func _arrow_row(col: Color) -> Callable:
	return func(ci: Control, sz: Vector2):
		_land(ci, sz)
		Overlay.draw_arrow(ci, Vector2(-6, sz.y * 0.5), Vector2(sz.x + 6, sz.y * 0.5), col)


static func _target_row(attack: bool, turns: int) -> Callable:
	return func(ci: Control, sz: Vector2):
		_land(ci, sz)
		var rc := Rect2(Vector2(4, 3), sz - Vector2(8, 6))
		ci.draw_rect(rc, MapView.target_fill(attack, turns, 0.32))
		var te := MapView.target_edge(attack, turns)
		ci.draw_polyline(_closed(rc), te[0], float(te[1]), true)


## One sample: a box drawn by a painter(ci, size).
class Sample extends Control:
	var painter: Callable

	func _init() -> void:
		custom_minimum_size = SAMPLE
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		clip_contents = true

	func _draw() -> void:
		if painter.is_valid():
			painter.call(self, size)
