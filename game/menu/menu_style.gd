extends RefCounted
## Looks of the title menu: the display font (assets/ui/fonts/Cinzel-*.ttf when present, else the UI font),
## flat entry buttons that brighten and grow 3 % on hover / press, and art cards. View only.

const FONT_BOLD := "res://assets/ui/fonts/Cinzel-Bold.ttf"
const FONT_REGULAR := "res://assets/ui/fonts/Cinzel-Regular.ttf"
const COL_ENTRY := Color(0.86, 0.82, 0.70)
const COL_ENTRY_HOT := Color(1.0, 0.95, 0.78)
const COL_GOLD := Color(1.0, 0.85, 0.45)
const SCALE_HOT := 1.03

static var _fonts := {}


## The display face, null until the font files exist.
static func display_font(bold: bool = true) -> Font:
	var path := FONT_BOLD if bold else FONT_REGULAR
	if _fonts.has(path):
		return _fonts[path]
	var f: Font = null
	if ResourceLoader.exists(path):
		f = load(path) as Font
	elif FileAccess.file_exists(path):
		var ff := FontFile.new()
		ff.data = FileAccess.get_file_as_bytes(path)
		f = ff
	_fonts[path] = f
	return f


static func use_display(c: Control, size: int, bold: bool = true) -> void:
	var f := display_font(bold)
	if f != null:
		c.add_theme_font_override("font", f)
	c.add_theme_font_size_override("font_size", size)


static func _flat(col: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, radius: int = 4, pad: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	return sb


## A title entry: flat, left-aligned (centred on phones), the label brightens and the whole grows 3 % on hover.
static func entry_style(b: Button, size: int, centred: bool) -> void:
	use_display(b, size)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER if centred else HORIZONTAL_ALIGNMENT_LEFT
	var n := _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4, 6)
	n.content_margin_left = 6
	var h := _flat(Color(1, 0.9, 0.55, 0.07), Color(1, 0.85, 0.45, 0.5), 0, 4, 6)
	h.border_width_left = 3
	h.content_margin_left = 10
	var pr := _flat(Color(1, 0.9, 0.55, 0.14), Color(1, 0.85, 0.45, 0.8), 0, 4, 6)
	pr.border_width_left = 3
	pr.content_margin_left = 10
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("focus", n)
	b.add_theme_stylebox_override("disabled", n)
	for k in ["font_color", "font_focus_color"]:
		b.add_theme_color_override(k, COL_ENTRY)
	b.add_theme_color_override("font_hover_color", COL_ENTRY_HOT)
	b.add_theme_color_override("font_hover_pressed_color", COL_GOLD)
	b.add_theme_color_override("font_pressed_color", COL_GOLD)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	b.add_theme_constant_override("outline_size", 4)
	b.mouse_entered.connect(func(): _grow(b, SCALE_HOT))
	b.mouse_exited.connect(func(): _grow(b, 1.0))
	b.button_down.connect(func(): _grow(b, SCALE_HOT))
	b.button_up.connect(func(): _grow(b, SCALE_HOT if b.is_hovered() else 1.0))



static func _grow(b: Control, k: float) -> void:
	b.pivot_offset = Vector2(0.0, b.size.y * 0.5)
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(k, k), 0.1)


## A big card button (the setting cards): a panel that lights up on hover.
static func card_style(b: Button) -> void:
	var n := _flat(Color(0.08, 0.1, 0.1, 0.82), Color(0.7, 0.55, 0.25, 0.55), 2, 8, 14)
	var h := _flat(Color(0.12, 0.14, 0.12, 0.92), Color(1.0, 0.85, 0.45, 0.95), 2, 8, 14)
	var pr := _flat(Color(0.16, 0.17, 0.13, 0.95), Color(1.0, 0.9, 0.55, 1.0), 3, 8, 14)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("focus", n)
	b.mouse_entered.connect(func(): _grow_c(b, SCALE_HOT))
	b.mouse_exited.connect(func(): _grow_c(b, 1.0))


static func _grow_c(b: Control, k: float) -> void:
	b.pivot_offset = b.size * 0.5
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(k, k), 0.1)


## The page buttons: an opaque dark plate with a thin gold edge, lighter on hover.
static func button_style(b: Button) -> void:
	var n := _flat(Color(0.11, 0.13, 0.12, 0.94), Color(0.55, 0.43, 0.2, 0.7), 1, 5, 8)
	var h := _flat(Color(0.17, 0.19, 0.16, 0.97), Color(1.0, 0.85, 0.45, 0.95), 1, 5, 8)
	var pr := _flat(Color(0.22, 0.22, 0.16, 1.0), Color(1.0, 0.9, 0.55, 1.0), 1, 5, 8)
	var d := _flat(Color(0.09, 0.1, 0.1, 0.8), Color(0.3, 0.3, 0.3, 0.5), 1, 5, 8)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("focus", n)
	b.add_theme_stylebox_override("disabled", d)
