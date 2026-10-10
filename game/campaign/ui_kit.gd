extends RefCounted
## Small helpers for the campaign screens: labels, buttons, boxes and a drawn
## unit row. Sizes are logical pixels (game/ui_scale.gd makes them touch-sized
## on phones and compact on desktops), matching the battle HUD: 42 px
## buttons, 15 px text.

const UT := preload("res://sim/unit_types.gd")
const Icons := preload("res://game/unit_icons.gd")
const UiScale := preload("res://game/ui_scale.gd")
const TouchScroll := preload("res://game/touch_scroll.gd")
const UiIcons := preload("res://game/ui_icons.gd")
const Traits := preload("res://game/unit_traits.gd")

const BTN_H := 40.0
const FONT := 15
const FONT_SMALL := 13
const FONT_TITLE := 18
const COL_DIM := Color(0.75, 0.75, 0.72)
const COL_GOOD := Color(0.6, 0.95, 0.6)
const COL_BAD := Color(1.0, 0.6, 0.5)
const COL_GOLD := Color(1.0, 0.85, 0.45)
const PANEL_BG := Color(0.1, 0.12, 0.11, 0.96)
const COL_TEXT := Color(0.875, 0.875, 0.875)  # the default theme's button text
const ICON_GAP := 6


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


## A button with an icon left of its text (game/ui_icons.gd); text "" makes
## a bare icon button (only where the icon is plain: Undo, Deselect, Menu),
## which gets the icon's name as its tooltip.
static func icon_button(text: String, icon: String, cb: Callable, min_w: float = 0.0, size: int = FONT) -> Button:
	var b := button(text, cb, min_w, size)
	set_icon(b, icon)
	return b


## Put an icon on a button, sized to its text and coloured like it in every
## state (col: the text colour when the button overrides it). Disabled is an
## opaque grey so overlapping strokes do not show.
static func set_icon(b: Button, icon: String, col: Color = Color(0, 0, 0, 0)) -> void:
	b.icon = UiIcons.tex(icon, UiIcons.px_for(b.get_theme_font_size("font_size")))
	b.add_theme_constant_override("h_separation", ICON_GAP)
	if b.text == "":
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if b.tooltip_text == "":
			b.tooltip_text = icon.capitalize()
	tint_icon(b, col if col.a > 0.0 else COL_TEXT)


static func tint_icon(b: Button, col: Color) -> void:
	b.add_theme_color_override("icon_normal_color", col)
	b.add_theme_color_override("icon_focus_color", col)
	b.add_theme_color_override("icon_hover_color", col.lightened(0.3))
	b.add_theme_color_override("icon_pressed_color", col.lightened(0.3))
	b.add_theme_color_override("icon_hover_pressed_color", col.lightened(0.3))
	b.add_theme_color_override("icon_disabled_color", Color(col.darkened(0.45), 1.0))


## A label with an icon left of its first line.
static func icon_label(text: String, icon: String, size: int = FONT, col: Color = Color.WHITE, p_wrap: bool = false) -> Label:
	return label_icon(label(text, size, col, p_wrap), icon)


## Give a label an icon left of its first line (again to change it; ""
## removes it). The text moves right by the icon's width (a content margin),
## so wrapping, names and .text are those of the plain label. icon_col: the
## icon's colour if not the text's.
static func label_icon(l: Label, icon: String, icon_col: Color = Color(0, 0, 0, 0)) -> Label:
	var px := UiIcons.px_for(l.get_theme_font_size("font_size"))
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = float(px + ICON_GAP) if icon != "" else 0.0
	l.add_theme_stylebox_override("normal", sb)
	l.set_meta("icon", icon)
	l.set_meta("icon_col", icon_col)
	if not l.has_meta("icon_hooked"):
		l.set_meta("icon_hooked", true)
		l.draw.connect(_draw_label_icon.bind(l))
	l.queue_redraw()
	return l


static func _draw_label_icon(l: Label) -> void:
	var icon := str(l.get_meta("icon", ""))
	if icon == "":
		return
	var fs := l.get_theme_font_size("font_size")
	var px := float(UiIcons.px_for(fs))
	var fh := l.get_theme_font("font").get_height(fs)
	var ls := float(l.get_theme_constant("line_spacing"))
	var n := maxi(l.get_visible_line_count(), 1)
	var block := n * (fh + ls) - ls
	var y0 := 0.0
	if l.vertical_alignment == VERTICAL_ALIGNMENT_CENTER:
		y0 = floorf((l.size.y - block) * 0.5)
	elif l.vertical_alignment == VERTICAL_ALIGNMENT_BOTTOM:
		y0 = l.size.y - block
	var col: Color = l.get_meta("icon_col", Color(0, 0, 0, 0))
	if col.a <= 0.0:
		col = l.get_theme_color("font_color")
	UiIcons.draw_icon(l, icon, Rect2(0.0, y0 + (fh - px) * 0.5, px, px), col)


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


static func section(text: String, icon: String = "") -> Label:
	var l := label(text, FONT, COL_GOLD)
	if icon != "":
		label_icon(l, icon)
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


## Where a tap on a card glyph shows its one-line meaning (the campaign screen
## sets it to its toast); a Callable taking the text.
static var hint_cb := Callable()


static func show_hint(text: String) -> void:
	if hint_cb.is_valid():
		hint_cb.call(text)


## A unit as one drawn row: symbol (with tier mark) in the side colour, name,
## strength bar with men / full, and optional right-hand text. Toggleable
## (selected rows are framed). Emits `pressed`.
class UnitRow extends Control:
	const KitSelf := preload("res://game/campaign/ui_kit.gd")
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
	var sub_text := "":
		set(v):
			sub_text = v
			update_minimum_size()
	var selected := false
	var toggle := false
	## Compact card: trait glyphs after the name, good / weak against class
	## rows, the five pips (game/unit_traits.gd). faction: for the fire trait.
	var detail := true
	var faction := -1
	var _hits: Array = []  # [Rect2, hint text] of the glyphs drawn last
	var _tap_hint := ""

	func _init(p_ty: int, p_men: int, p_col: Color, p_right: String = "", p_toggle: bool = false) -> void:
		ty = p_ty
		men = p_men
		full = maxi(UT.size_of(p_ty), 1)
		col = p_col
		right_text = p_right
		toggle = p_toggle
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _get_minimum_size() -> Vector2:
		if not detail:
			return Vector2(200, 40)
		var h := 56.0
		if men >= 0 or sub_text != "":
			h += 16.0
		return Vector2(200, h)

	## Press on release, only if the pointer is still on the row (a touch
	## that became a scroll is moved far away by TouchScroll, which cancels
	## the press and any long press). Holding LONG_PRESS_SEC emits
	## long_pressed instead. Touches arrive as emulated mouse events.
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_t = Time.get_ticks_msec() / 1000.0
				_long_fired = false
				_tap_hint = _hit_at(event.position)
				queue_redraw()
			else:
				var inside := Rect2(Vector2.ZERO, size).has_point(event.position)
				var was := _press_t >= 0.0
				_press_t = -1.0
				queue_redraw()
				if was and inside and not _long_fired and _tap_hint != "" and _tap_hint == _hit_at(event.position):
					KitSelf.show_hint(_tap_hint)
				elif was and inside and not _long_fired:
					if toggle:
						selected = not selected
						queue_redraw()
					pressed.emit()
			accept_event()
		elif event is InputEventMouseMotion and _press_t >= 0.0:
			if not Rect2(Vector2.ZERO, size).has_point(event.position):
				_press_t = -1.0
				queue_redraw()

	func _hit_at(pos: Vector2) -> String:
		for h in _hits:
			if (h[0] as Rect2).grow_individual(3, 5, 3, 5).has_point(pos):
				return str(h[1])
		return ""

	## Forget the press in progress (a drag to reorder took it over: no
	## press, no long press on release).
	func cancel_press() -> void:
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
		_hits = []
		var bg := Color(1, 1, 1, 0.13) if selected else Color(1, 1, 1, 0.05)
		if _press_t >= 0.0:
			bg = Color(1, 1, 1, 0.22)  # pressed feedback while the finger is down
		draw_rect(Rect2(Vector2.ZERO, sz), bg)
		if selected:
			draw_rect(Rect2(Vector2(1, 1), sz - Vector2(2, 2)), Color(1, 0.95, 0.5), false, 2.0)
		var r := minf(sz.y * 0.36, 15.0) if not detail else 15.0
		var cy := sz.y * 0.5 if not detail else 24.0
		Icons.draw_marker(self, Icons.icon_of(ty), Vector2(r + 5, cy), r, col)
		var font := ThemeDB.fallback_font
		var x0 := r * 2 + 12
		var rw := 0.0
		if right_text != "":
			rw = font.get_string_size(right_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 8
			draw_string(font, Vector2(sz.x - rw, 18.0 if detail else sz.y * 0.5 + 5.0), right_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.88, 0.55))
		var nm := str(UT.TYPES[ty]["name"])
		var nw := minf(font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x, sz.x - x0 - rw - 4)
		draw_string(font, Vector2(x0, 16), nm, HORIZONTAL_ALIGNMENT_LEFT, sz.x - x0 - rw - 4, 14, Color.WHITE)
		if detail:
			# Line 1: up to three trait glyphs after the name.
			var gx := x0 + nw + 8
			for t in Traits.traits(ty, faction):
				if gx + 16 > sz.x - rw:
					break
				var rc := Rect2(gx, 3, 16, 16)
				UiIcons.draw_icon(self, str(Traits.TRAIT_ICONS[t]), rc, Color(1, 0.9, 0.6))
				_hits.append([rc, Traits.trait_text(t)])
				gx += 20
			# Line 2: green row (good against), red row (weak against).
			var cx := x0
			var y2 := 24.0
			for pair in [[true, COL_GOOD], [false, COL_BAD]]:
				var list: Array = Traits.classes_good(ty) if pair[0] else Traits.classes_bad(ty)
				if list.is_empty():
					continue
				var c: Color = pair[1]
				var x1 := cx
				var tri := PackedVector2Array([Vector2(cx, y2 + 11), Vector2(cx + 5, y2 + 11), Vector2(cx + 2.5, y2 + 4)]) if pair[0] \
					else PackedVector2Array([Vector2(cx, y2 + 4), Vector2(cx + 5, y2 + 4), Vector2(cx + 2.5, y2 + 11)])
				draw_colored_polygon(tri, c)
				cx += 8
				for k in list:
					UiIcons.draw_icon(self, str(Traits.CLASS_ICONS[k]), Rect2(cx, y2, 15, 15), c)
					cx += 17
				_hits.append([Rect2(x1, y2, cx - x1, 15), Traits.classes_text(ty, pair[0])])
				cx += 8
			# Line 3: the five pips.
			var p := Traits.pips(ty)
			var px := x0
			var y3 := 43.0
			var letters := ["A", "D", "R", "M", "S"]
			for k in 5:
				var v := int(p[Traits.PIP_NAMES[k]])
				draw_string(font, Vector2(px, y3 + 8), letters[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_DIM)
				for sg in 4:
					draw_rect(Rect2(px + 9 + sg * 6, y3, 5, 8), Color(col.lightened(0.25), 0.95) if sg < v else Color(1, 1, 1, 0.14))
				px += 38
			_hits.append([Rect2(x0, y3, px - x0, 10), Traits.pips_text(ty)])
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


# ------------------------------------------------------------ text entry ---
# Every text field in the game is a Kit.text_field, so typing and pasting
# work on the web build too:
#  - a finger tap on a field on the web build opens the browser's own
#    prompt() with the field's title and text: Godot's web export has no
#    usable on-screen keyboard (the experimental one needs a hidden DOM input
#    focused inside the touch handler, which Godot's main loop cannot do, so
#    iOS Safari never raises it), while prompt() always brings up the
#    keyboard and allows paste, on Android Chrome and iOS Safari alike. The
#    answer goes into the LineEdit, then text_changed and text_submitted are
#    emitted as if typed. A mouse click (desktop) edits in place as usual.
#  - Ctrl+V / Cmd+V on the web reads the clipboard through the browser
#    (navigator.clipboard.readText, started inside the real keydown handler):
#    Godot's own web paste returns the clipboard of the previous paste.
#  - field_box() adds a Paste button beside a field on the web build; its
#    read starts in the browser's own pointerup handler (Safari wants the
#    gesture), and a refusal shows a short hint under the field.

const PASTE_HINT := "Paste not allowed by the browser: use Ctrl+V with the field focused."
const PASTE_HINT_TOUCH := "Paste not allowed by the browser: tap the field and paste into the box that opens."
const _JS := """
if (!window.scText) {
  window.scText = {
    n: 0, res: {}, armed: 0, last: 0, lastT: 0, taken: 0, cb: null,
    read: function () {
      const n = ++this.n;
      this.last = n;
      this.lastT = Date.now();
      const done = (ok, t) => { this.res[n] = JSON.stringify([ok, t]); if (this.cb) this.cb(n, ok, t); };
      try {
        navigator.clipboard.readText().then((t) => done(1, String(t)), (e) => done(0, String(e)));
      } catch (e) { done(0, String(e)); }
      return n;
    },
    arm: function () { this.armed = Date.now(); },
    take: function () {
      if (this.last > this.taken && Date.now() - this.lastT < 2000) { this.taken = this.last; return this.last; }
      const n = this.read();
      this.taken = n;
      return n;
    },
    result: function (n) { const r = this.res[n]; delete this.res[n]; return r === undefined ? "" : r; },
  };
  window.addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && !e.altKey && (e.key === "v" || e.key === "V")) scText.read();
  }, true);
  window.addEventListener("pointerup", () => {
    if (scText.armed && Date.now() - scText.armed < 3000) { scText.armed = 0; scText.read(); }
  }, true);
}
"""

static var _js_cb: JavaScriptObject = null
static var _clip_wait := {}   # clipboard read number -> Callable(ok: bool, text: String)


## A one-line text field (see the section header). title: what the browser
## prompt asks (default: the placeholder). trim: drop surrounding spaces from
## prompted and pasted text (keys and codes).
static func text_field(placeholder: String, text: String = "", min_w: float = 200.0, title: String = "", trim: bool = false) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.text = text
	le.custom_minimum_size = Vector2(min_w, BTN_H)
	le.set_meta("title", title if title != "" else placeholder)
	if trim:
		le.set_meta("trim", 1)
	if OS.has_feature("web"):
		_web_init()
		le.gui_input.connect(func(e: InputEvent): _field_input(e, le))
	return le


## A multi-line text box (pasted saves): Ctrl+V works on the web too.
static func text_area(min_size: Vector2) -> TextEdit:
	var te := TextEdit.new()
	te.custom_minimum_size = min_size
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	if OS.has_feature("web"):
		_web_init()
		te.gui_input.connect(func(e: InputEvent): _paste_key(e, te))
	return te


## The field with a Paste button beside it (web build only; elsewhere the
## field itself is returned) and a hint line under it for a refused paste.
## Add the returned control (and show / hide it) instead of the field.
static func field_box(c: Control) -> Control:
	if not OS.has_feature("web"):
		return c
	var v := vbox(2)
	v.size_flags_horizontal = c.size_flags_horizontal
	var h := hbox(6)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(c)
	var b := button("Paste", Callable(), 0, FONT_SMALL)
	b.name = str(c.name) + "_paste"
	b.pressed.connect(func(): paste_into(c))
	arm_paste(b)
	h.add_child(b)
	v.add_child(h)
	var hint := label("", FONT_SMALL, COL_BAD, true)
	hint.visible = false
	v.add_child(hint)
	c.set_meta("hint", hint)
	c.set_meta("own_hint", 1)
	return v


## A Paste button (it calls paste_into on pressed): on the web, start the
## clipboard read in the browser's own release handler.
static func arm_paste(b: BaseButton) -> void:
	if OS.has_feature("web"):
		b.button_down.connect(func(): JavaScriptBridge.eval("window.scText && scText.arm()"))


## Paste the clipboard into a LineEdit or TextEdit: replace its text, or
## insert at the caret. On the web this waits for the browser's read.
static func paste_into(c: Control, insert: bool = false) -> void:
	if not OS.has_feature("web"):
		_put(c, DisplayServer.clipboard_get(), insert, "paste")
		return
	_web_init()
	var n := int(JavaScriptBridge.eval("scText.take()", true))
	_clip_wait[n] = func(ok: bool, s: String):
		if not is_instance_valid(c):
			return
		if ok:
			_put(c, s, insert, "paste")
		else:
			push_warning("paste refused: " + s)
			var hint = c.get_meta("hint", null)
			if hint is Label and is_instance_valid(hint):
				hint.text = PASTE_HINT_TOUCH if UiScale.is_touch() else PASTE_HINT
				hint.visible = true
	var r = JavaScriptBridge.eval("scText.result(%d)" % n, true)
	if r is String and r != "":
		var a = JSON.parse_string(r)
		if a is Array and a.size() == 2:
			_clip_done([n, a[0], a[1]])


static func _web_init() -> void:
	if _js_cb != null:
		return
	JavaScriptBridge.eval(_JS, true)
	_js_cb = JavaScriptBridge.create_callback(func(args: Array): _clip_done(args))
	var st: JavaScriptObject = JavaScriptBridge.get_interface("scText")
	if st != null:
		st.cb = _js_cb


static func _clip_done(args: Array) -> void:
	var n := int(args[0])
	if not _clip_wait.has(n):
		return
	var f: Callable = _clip_wait[n]
	_clip_wait.erase(n)
	JavaScriptBridge.eval("delete scText.res[%d]" % n)
	f.call(int(args[1]) != 0, str(args[2]))


static func _field_input(e: InputEvent, le: LineEdit) -> void:
	if not le.editable:
		return
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and TouchScroll.is_touch_event(e):
		# A finger: the browser's prompt instead of Godot's (missing) keyboard.
		le.accept_event()
		var mb := e as InputEventMouseButton
		if not mb.pressed and Rect2(Vector2.ZERO, le.size).has_point(mb.position):
			_ask.call_deferred(le)
		return
	_paste_key(e, le)


## Ctrl+V / Cmd+V on the web: paste through the browser (see the header).
static func _paste_key(e: InputEvent, c: Control) -> void:
	if e is InputEventKey:
		var k := e as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_V and (k.ctrl_pressed or k.meta_pressed) and not k.alt_pressed:
			c.accept_event()
			paste_into(c, true)


static func _ask(le: LineEdit) -> void:
	if not is_instance_valid(le) or not le.is_visible_in_tree():
		return
	var r = JavaScriptBridge.eval("prompt(%s, %s)" % [JSON.stringify(str(le.get_meta("title", ""))), JSON.stringify(le.text)], true)
	le.release_focus()
	if r == null:
		return  # cancelled
	_put(le, str(r), false, "prompt")
	le.text_submitted.emit(le.text)


## Put text into a field as if typed (one line for a LineEdit), and tell its
## listeners.
static func _put(c: Control, s: String, insert: bool, how: String) -> void:
	if c is LineEdit:
		var le := c as LineEdit
		s = s.replace("\r", "").replace("\n", " ")
		if le.has_meta("trim"):
			s = s.strip_edges()
		if insert:
			le.insert_text_at_caret(s)
		else:
			le.text = s
		if le.has_meta("trim"):
			le.text = le.text.strip_edges()
		le.caret_column = le.text.length()
		le.text_changed.emit(le.text)
		print("text field %s: %d chars by %s" % [le.name, le.text.length(), how])
	elif c is TextEdit:
		var te := c as TextEdit
		if insert:
			te.insert_text_at_caret(s)
		else:
			te.text = s
		te.text_changed.emit()
		print("text field %s: %d chars by %s" % [te.name, te.text.length(), how])
	var hint = c.get_meta("hint", null)
	if hint is Label and is_instance_valid(hint) and hint.text in [PASTE_HINT, PASTE_HINT_TOUCH]:
		hint.text = ""
		if c.has_meta("own_hint"):
			hint.visible = false
