extends RefCounted
## The theme of the battle screens (UI theme pass 2; docs/DESIGN.md "UI theme (as built)"): the battle HUD, the
## sea battle's bars and the battle modals dress their buttons here. View only.
##
## The plates are the kit's nav style (Kit.nav_style: dark warm plate, thin gold edge) and a lit variant for a
## toggle that is on (the segmented control's gold). Both are built ONCE and shared by every button (a StyleBox is a
## resource: forty buttons point at the same five), so building or rebuilding a bar (the sea order bar is rebuilt
## on every selection) allocates no styles; nothing here runs per frame.
##
## Touch: a battle button never gets the kit's long-press tip (meta "tip_host_skip"): a press held for half a second
## and released must still give the order, mid-fight. The boxed tip shows on a desktop hover as everywhere.

const Kit := preload("res://game/campaign/ui_kit.gd")

const COL_FONT := Color(0.91, 0.86, 0.69)       # bone
const COL_HOT := Color(1.0, 0.96, 0.82)
const COL_DIS := Color(0.55, 0.52, 0.45)

static var _plate: Dictionary = {}   # state -> StyleBox
static var _lit: Dictionary = {}


static func _build() -> void:
	if not _plate.is_empty():
		return
	var d := Button.new()
	Kit.nav_style(d)
	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		_plate[k] = d.get_theme_stylebox(k)
	d.free()
	var cols := {"normal": Color(0.30, 0.22, 0.08, 1.0), "hover": Color(0.36, 0.27, 0.10, 1.0), "pressed": Color(0.40, 0.30, 0.11, 1.0),
		"disabled": Color(0.2, 0.17, 0.1, 0.8)}
	for k in cols:
		var sb := Kit.box(cols[k], 4.0, 5)
		sb.set_border_width_all(1)
		sb.border_color = Kit.COL_GOLD if k != "disabled" else Color(0.4, 0.34, 0.2, 0.6)
		_lit[k] = sb


## Dress a button: the nav plate, bone label, the kit's hover / press motion (once). toggle: its pressed state is the
## lit plate. lit: shown lit now (a sea order that is on).
static func plate(b: Button, toggle: bool = false, lit: bool = false, motion: bool = true) -> void:
	_build()
	var on: Dictionary = _lit if lit else _plate
	b.add_theme_stylebox_override("normal", on["normal"])
	b.add_theme_stylebox_override("hover", on["hover"])
	b.add_theme_stylebox_override("disabled", _plate["disabled"])
	b.add_theme_stylebox_override("focus", _plate["normal"])
	var pr: Dictionary = _lit if (toggle or lit) else _plate
	b.add_theme_stylebox_override("pressed", pr["pressed"] if not toggle else _lit["normal"])
	b.add_theme_stylebox_override("hover_pressed", pr["pressed"] if not toggle else _lit["hover"])
	var f := Kit.COL_GOLD if lit else COL_FONT
	b.add_theme_color_override("font_color", f)
	b.add_theme_color_override("font_hover_color", COL_HOT)
	b.add_theme_color_override("font_pressed_color", Kit.COL_GOLD)
	b.add_theme_color_override("font_hover_pressed_color", Kit.COL_GOLD)
	b.add_theme_color_override("font_disabled_color", COL_DIS)
	if toggle:
		b.add_theme_color_override("font_pressed_color", Kit.COL_GOLD)
	if motion and not b.has_meta("bt_motion"):
		b.set_meta("bt_motion", true)
		Kit.motion(b)
	b.set_meta("tip_host_skip", true)


## A capsule of momentary buttons (the group buttons): the kit's Segmented with no lit segment, the segments
## (or the one with value `lit` lit) sized for a touch (`h` high, `min_w` wide at least) with trimmed side margins so the row keeps its width.
## items: [label, value] pairs; cb(value) runs on a press. Segments are named "<nm>_<value>".
static func capsule(items: Array, cb: Callable, nm: String, size: int, min_w: float, h: float, lit = null) -> Kit.Segmented:
	var sg := Kit.segmented(items, lit, Callable(), nm, size)
	for b in sg.buttons():
		var v = b.get_meta("seg_value")
		b.pressed.disconnect(sg.pick.bind(v))   # (momentary: nothing stays lit)
		b.pressed.connect(cb.bind(v))
		b.custom_minimum_size = Vector2(min_w, h)
		trim_margins(b, 6.0)
		b.set_meta("tip_host_skip", true)
	return sg


## Narrower side margins on a segment's four styles (they are the segment's own, not shared).
static func trim_margins(b: Button, side: float) -> void:
	for k in ["normal", "hover", "pressed", "disabled"]:
		var sb := b.get_theme_stylebox(k) as StyleBoxFlat
		if sb != null:
			sb.content_margin_left = side
			sb.content_margin_right = side


## The title block of the top bar: [emblem] [title in the title face]. Returned as an HBox; the caller places it.
## Desktop only (the caller decides).
static func title_block(pack: String, text: String) -> HBoxContainer:
	var h := Kit.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var e := Kit.emblem(pack, 32.0)
	e.name = "bar_emblem"
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	e.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(e)
	var t := Kit.title(text, 18)
	t.name = "bar_title"
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.clip_text = true
	t.custom_minimum_size.x = 40
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(t)
	return h


## The gold hairline under a top bar.
static func bar_rule() -> Control:
	var r := Kit.rule(Color(Kit.COL_RULE, 0.5))
	r.name = "bar_rule"
	return r


## Whether the desktop dressing (emblem, title face) shows: a wide window and no touch screen.
static func desktop(vp_w: float) -> bool:
	return vp_w >= 820.0 and not Kit.UiScale.is_touch()
