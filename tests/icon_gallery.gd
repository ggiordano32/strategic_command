extends SceneTree
## Every UI icon (game/ui_icons.gd) at two sizes the screens use (18 px
## beside small text, 22 px beside End turn's) on the dark panel colour, at
## 22 px dark on a light surface, and a row of Kit buttons and labels with
## icons (normal, disabled, bare), rendered at 2x into
## docs/screenshots/icons.png. Checks that every icon draws something and
## that an unknown name falls back to a ring. Needs a window:
##   godot --script res://tests/icon_gallery.gd [-- --out=path.png]

const UiIcons := preload("res://game/ui_icons.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")

const COLS := 9
const CELL := Vector2(118, 58)
const TOP := 34.0
const K := 2.0

var out := "res://docs/screenshots/icons.png"
var frames := 0
var fails := 0
var sheet: Control
var rows := 0
var vp: SubViewport


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	rows = ceili(float(UiIcons.NAMES.size()) / COLS)
	var logical := Vector2(COLS * CELL.x + 16, TOP + rows * CELL.y + 70)
	# Drawn offscreen at 2x (the window size does not matter).
	vp = SubViewport.new()
	vp.size = Vector2i(logical * K)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.06)
	bg.size = logical * K
	vp.add_child(bg)
	sheet = Control.new()
	sheet.scale = Vector2(K, K)
	sheet.size = logical
	sheet.draw.connect(_draw_sheet)
	vp.add_child(sheet)
	# Kit samples along the bottom.
	var h := Kit.hbox(8)
	h.position = Vector2(8, TOP + rows * CELL.y + 14)
	sheet.add_child(h)
	h.add_child(Kit.icon_button("Assault", "assault", Callable(), 0))
	var d := Kit.icon_button("Lay siege", "siege", Callable(), 0)
	d.disabled = true
	h.add_child(d)
	var w := Kit.icon_button("Declare war", "war", Callable(), 0)
	w.add_theme_color_override("font_color", Kit.COL_BAD)
	Kit.tint_icon(w, Kit.COL_BAD)
	h.add_child(w)
	h.add_child(Kit.icon_button("", "undo", Callable(), 48))
	h.add_child(Kit.icon_button("", "deselect", Callable(), 48))
	h.add_child(Kit.icon_button("", "menu", Callable(), 48))
	h.add_child(Kit.icon_label("1,500 (+862)", "treasury", Kit.FONT, Kit.COL_GOLD))
	h.add_child(Kit.icon_label("Buildings", "build", Kit.FONT_SMALL, Kit.COL_DIM))


func _draw_sheet() -> void:
	var font := ThemeDB.fallback_font
	sheet.draw_string(font, Vector2(8, 22), "UI icons (game/ui_icons.gd): 18 px and 22 px on the panel colour, 22 px on a light surface",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Kit.COL_GOLD)
	for i in UiIcons.NAMES.size():
		var nm: String = UiIcons.NAMES[i]
		var o := Vector2(8 + (i % COLS) * CELL.x, TOP + (i / COLS) * CELL.y)
		sheet.draw_rect(Rect2(o, CELL - Vector2(4, 4)), Kit.PANEL_BG)
		sheet.draw_rect(Rect2(o + Vector2(70, 4), Vector2(36, 30)), Color(0.9, 0.88, 0.82))
		UiIcons.draw_icon(sheet, nm, Rect2(o + Vector2(6, 9), Vector2(18, 18)), Kit.COL_TEXT)
		UiIcons.draw_icon(sheet, nm, Rect2(o + Vector2(32, 7), Vector2(22, 22)), Kit.COL_TEXT)
		UiIcons.draw_icon(sheet, nm, Rect2(o + Vector2(77, 8), Vector2(22, 22)), Color(0.12, 0.12, 0.1))
		sheet.draw_string(font, o + Vector2(6, CELL.y - 12), nm, HORIZONTAL_ALIGNMENT_LEFT, CELL.x - 10, 11, Kit.COL_DIM)


func _process(_d: float) -> bool:
	frames += 1
	if frames < 6:
		return false
	var img := vp.get_texture().get_image()
	for i in UiIcons.NAMES.size():
		var o := (Vector2(8 + (i % COLS) * CELL.x, TOP + (i / COLS) * CELL.y) + Vector2(32, 7)) * K
		var lit := 0
		for y in int(22 * K):
			for x in int(22 * K):
				if img.get_pixel(int(o.x) + x, int(o.y) + y).r > 0.5:
					lit += 1
		var share := float(lit) / (22.0 * 22.0 * K * K)
		if share < 0.04 or share > 0.6:
			print("FAIL icon %s covers %.0f%% of its cell" % [UiIcons.NAMES[i], share * 100])
			fails += 1
	var path := ProjectSettings.globalize_path(out) if out.begins_with("res://") else out
	img.save_png(path)
	print("saved ", path, " ", img.get_size(), " ", UiIcons.NAMES.size(), " icons")
	print("ICON GALLERY %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
	return true
