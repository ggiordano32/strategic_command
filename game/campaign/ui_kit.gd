extends RefCounted
## Small helpers for the campaign screens: labels, buttons, boxes and a drawn
## unit row. Sizes are logical pixels (game/ui_scale.gd makes them touch-sized
## on phones and compact on desktops), matching the battle HUD: 42 px
## buttons, 15 px text.

const UT := preload("res://sim/unit_types.gd")
const Icons := preload("res://game/unit_icons.gd")

const BTN_H := 40.0
const FONT := 15
const FONT_SMALL := 13
const FONT_TITLE := 18
const COL_DIM := Color(0.75, 0.75, 0.72)
const COL_GOOD := Color(0.6, 0.95, 0.6)
const COL_BAD := Color(1.0, 0.6, 0.5)
const COL_GOLD := Color(1.0, 0.85, 0.45)
const PANEL_BG := Color(0.1, 0.12, 0.11, 0.96)


static func label(text: String, size: int = FONT, col: Color = Color.WHITE, p_wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if p_wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = 40
	return l


static func button(text: String, cb: Callable, min_w: float = 0.0, size: int = FONT) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, BTN_H)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func box(col: Color = PANEL_BG, margin: float = 10.0, radius: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


static func panel(col: Color = PANEL_BG, margin: float = 10.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(col, margin))
	return p


static func hbox(sep: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func flow(sep: int = 6) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", sep)
	return f


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func section(text: String) -> Label:
	var l := label(text, FONT, COL_GOLD)
	return l


static func swatch(col: Color, size: float = 16.0) -> ColorRect:
	var c := ColorRect.new()
	c.color = col
	c.custom_minimum_size = Vector2(size, size)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Money as text: "1,250".
static func money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out


## A unit as one drawn row: symbol (with tier mark) in the side colour, name,
## strength bar with men / full, and optional right-hand text. Toggleable
## (selected rows are framed). Emits `pressed`.
class UnitRow extends Control:
	signal pressed
	signal long_pressed
	const LONG_PRESS_SEC := 0.5
	var _press_t := -1.0
	var _long_fired := false
	var ty := 0
	var men := 0
	var full := 1
	var col := Color(0.35, 0.6, 1.0)
	var right_text := ""
	var sub_text := ""
	var selected := false
	var toggle := false

	func _init(p_ty: int, p_men: int, p_col: Color, p_right: String = "", p_toggle: bool = false) -> void:
		ty = p_ty
		men = p_men
		full = maxi(UT.size_of(p_ty), 1)
		col = p_col
		right_text = p_right
		toggle = p_toggle
		custom_minimum_size = Vector2(200, 40)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP

	## Press on release, only if the pointer is still on the row (a touch
	## that became a scroll is moved far away by TouchScroll, which cancels
	## the press and any long press). Holding LONG_PRESS_SEC emits
	## long_pressed instead. Touches arrive as emulated mouse events.
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_t = Time.get_ticks_msec() / 1000.0
				_long_fired = false
				queue_redraw()
			else:
				var inside := Rect2(Vector2.ZERO, size).has_point(event.position)
				var was := _press_t >= 0.0
				_press_t = -1.0
				queue_redraw()
				if was and inside and not _long_fired:
					if toggle:
						selected = not selected
						queue_redraw()
					pressed.emit()
			accept_event()
		elif event is InputEventMouseMotion and _press_t >= 0.0:
			if not Rect2(Vector2.ZERO, size).has_point(event.position):
				_press_t = -1.0
				queue_redraw()

	func _process(_delta: float) -> void:
		if _press_t >= 0.0 and not _long_fired and Time.get_ticks_msec() / 1000.0 - _press_t >= LONG_PRESS_SEC:
			_long_fired = true
			_press_t = -1.0
			queue_redraw()
			long_pressed.emit()

	func _draw() -> void:
		var sz := size
		var bg := Color(1, 1, 1, 0.13) if selected else Color(1, 1, 1, 0.05)
		if _press_t >= 0.0:
			bg = Color(1, 1, 1, 0.22)  # pressed feedback while the finger is down
		draw_rect(Rect2(Vector2.ZERO, sz), bg)
		if selected:
			draw_rect(Rect2(Vector2(1, 1), sz - Vector2(2, 2)), Color(1, 0.95, 0.5), false, 2.0)
		var r := minf(sz.y * 0.36, 15.0)
		Icons.draw_marker(self, Icons.icon_of(ty), Vector2(r + 5, sz.y * 0.5), r, col)
		var font := ThemeDB.fallback_font
		var x0 := r * 2 + 12
		var rw := 0.0
		if right_text != "":
			rw = font.get_string_size(right_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 8
			draw_string(font, Vector2(sz.x - rw, sz.y * 0.5 + 5), right_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.88, 0.55))
		var nm := str(UT.TYPES[ty]["name"])
		draw_string(font, Vector2(x0, 16), nm, HORIZONTAL_ALIGNMENT_LEFT, sz.x - x0 - rw - 4, 14, Color.WHITE)
		var bw := minf(sz.x - x0 - rw - 8, 150.0)
		var by := sz.y - 14
		var frac := clampf(float(men) / full, 0.0, 1.0)
		if men >= 0:
			draw_rect(Rect2(x0, by, bw, 9), Color(1, 1, 1, 0.12))
			draw_rect(Rect2(x0, by, bw * frac, 9), Color(col, 0.75))
			var t := "%d/%d" % [men, full] if sub_text == "" else sub_text
			draw_string(font, Vector2(x0 + bw + 6, by + 9), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_DIM)
		elif sub_text != "":
			draw_string(font, Vector2(x0, by + 9), sub_text, HORIZONTAL_ALIGNMENT_LEFT, sz.x - x0 - rw, 12, COL_DIM)


## Balance of power: a two-colour bar split at the attackers' share of the
## combined strength (campaign/cbattle.gd odds()), a mark at the middle.
class OddsBar extends Control:
	var share := 50
	var cols: Array = [Color(0.8, 0.3, 0.25), Color(0.3, 0.5, 0.9)]
	var texts: Array = ["", ""]

	func _init(p_share: int, p_cols: Array, p_texts: Array) -> void:
		share = clampi(p_share, 0, 100)
		cols = p_cols
		texts = p_texts
		custom_minimum_size = Vector2(180, 24)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var sz := size
		var x := roundf(sz.x * share / 100.0)
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(1, 1, maxf(x - 1, 0), sz.y - 2), cols[0])
		draw_rect(Rect2(x, 1, maxf(sz.x - x - 1, 0), sz.y - 2), cols[1])
		draw_line(Vector2(x, 0), Vector2(x, sz.y), Color.WHITE, 2.0)
		draw_line(Vector2(sz.x * 0.5, sz.y - 5), Vector2(sz.x * 0.5, sz.y), Color(1, 1, 1, 0.8), 1.5)
		var font := ThemeDB.fallback_font
		var fs := 13
		var y := sz.y * 0.5 + fs * 0.35
		for k in 2:
			var t := str(texts[k])
			if t == "":
				continue
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var p := Vector2(6, y) if k == 0 else Vector2(sz.x - tw - 6, y)
			draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
			draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


const BAND_WORDS: Array[String] = ["decisive defeat", "likely defeat", "even", "likely victory", "decisive victory"]
const BAND_COLS: Array[Color] = [Color(1.0, 0.45, 0.4), Color(1.0, 0.65, 0.5), Color(1.0, 0.9, 0.6), Color(0.65, 0.95, 0.6),
	Color(0.5, 1.0, 0.55)]


## The odds of a battle as a box: title, the bar (attackers left in their
## colour, defenders right), and "Your chance 62%: likely victory. Expected
## losses: yours 18%, theirs 41%." me: 0 the viewer attacks, 1 defends, -1
## neither (the attackers' view). names / cols: [attackers, defenders].
static func odds_view(od: Dictionary, me: int, names: Array, cols: Array, title: String) -> Control:
	var v := vbox(3)
	v.name = "odds"
	if title != "":
		v.add_child(label(title, FONT_SMALL, COL_GOLD, true))
	var share := int(od["share"])
	var bar := OddsBar.new(share, cols, ["%s %d%%" % [names[0], share], "%d%% %s" % [100 - share, names[1]]])
	bar.name = "odds_bar"
	v.add_child(bar)
	var win := int(od["win"]) if me != 1 else 100 - int(od["win"])
	var band := int(od["band"]) if me != 1 else 4 - int(od["band"])
	var mine := int(od["att_loss"]) if me != 1 else int(od["def_loss"])
	var theirs := int(od["def_loss"]) if me != 1 else int(od["att_loss"])
	var who := "Your" if me >= 0 else "%s's" % names[0]
	var t := "%s chance %d%%: %s. Expected losses: %s %d%%, %s %d%%." % [who, win, BAND_WORDS[band],
		"yours" if me >= 0 else str(names[0]), mine, "theirs" if me >= 0 else str(names[1]), theirs]
	var l := label(t, FONT_SMALL, BAND_COLS[band], true)
	l.name = "odds_text"
	v.add_child(l)
	return v
