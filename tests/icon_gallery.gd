extends SceneTree
## Every UI icon (game/ui_icons.gd) at two sizes the screens use (18 px
## beside small text, 22 px beside End turn's) on the dark panel colour, at
## 22 px dark on a light surface, and a row of Kit buttons and labels with
## icons (normal, disabled, bare), rendered at 2x into
## docs/screenshots/icons.png. Checks that every icon draws something and
## that an unknown name falls back to a ring. Needs a window:
##   godot --script res://tests/icon_gallery.gd [-- --out=path.png]

const UiIcons := preload("res://game/ui_icons.gd")
const UnitIcons := preload("res://game/unit_icons.gd")
const UT := preload("res://sim/unit_types.gd")
const CData := preload("res://campaign/cdata.gd")
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
var out_west := "res://docs/screenshots/icons_west.png"
var stage := 0  # 0 the Rome sheet, 1 the West sheet
var wsheet: Control
var wvp: SubViewport
var wframes := 0
const WGLYPHS := [3, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34]
const WLOGICAL := Vector2(1010, 590)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--out-west="):
			out_west = a.get_slice("=", 1)
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
	if stage == 1:
		return _process_west()
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
	_start_west()
	stage = 1
	return false


func _start_west() -> void:
	# The _w icons resolve only while the West pack is active.
	if UiIcons.resolve("range") != "range" or UiIcons.resolve("range_w") != "range_w":
		print("FAIL resolve in the Rome pack")
		fails += 1
	CData.use_pack("west")
	for nm in UiIcons.WEST_NAMES:
		var base: String = nm.trim_suffix("_w")
		if not UiIcons.NAMES.has(base) or UiIcons.resolve(base) != nm or UiIcons.resolve(nm) != nm:
			print("FAIL resolve of %s in the West pack" % nm)
			fails += 1
	if UiIcons.resolve("move") != "move":
		print("FAIL a name without a twin changed")
		fails += 1
	# The West rows carry the West glyph ids (the Rome rows keep theirs).
	var want := {"musketeers": 23, "rodeleros": 24, "cutlass": 25, "buccaneers": 26, "lancers": 27, "pistoleers": 28,
		"field_gun": 29, "fort_gun": 30, "light_gun": 31, "native_warriors": 32, "native_bowmen": 33, "w_pikemen": 3}
	for k in want:
		var ty := UT.index_of(k)
		if UT.stat(ty, "icon") != int(want[k]):
			print("FAIL row %s icon %d, wanted %d" % [k, UT.stat(ty, "icon"), want[k]])
			fails += 1
	if UnitIcons.icon_of(UT.index_of("general")) != 34:
		print("FAIL the West general's glyph")
		fails += 1
	CData.use_pack("rome")
	if UnitIcons.icon_of(UT.index_of("general")) != 15:
		print("FAIL the Rome general's glyph")
		fails += 1
	wvp = SubViewport.new()
	wvp.size = Vector2i(WLOGICAL * K)
	wvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(wvp)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.06)
	bg.size = WLOGICAL * K
	wvp.add_child(bg)
	wsheet = Control.new()
	wsheet.scale = Vector2(K, K)
	wsheet.size = WLOGICAL
	wsheet.draw.connect(_draw_west)
	wvp.add_child(wsheet)


const WCELL := Vector2(160, 126)


func _glyph_origin(i: int) -> Vector2:
	return Vector2(8 + (i % 6) * WCELL.x, 34 + (i / 6) * WCELL.y)


func _draw_west() -> void:
	var font := ThemeDB.fallback_font
	wsheet.draw_string(font, Vector2(8, 22), "West unit glyphs (game/unit_icons.gd 23-34, pikes 3): 16 / 24 / 48 px on both sides, tier 2 and 3 at 32 px",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Kit.COL_GOLD)
	for i in WGLYPHS.size():
		var o := _glyph_origin(i)
		wsheet.draw_rect(Rect2(o, WCELL - Vector2(4, 4)), Kit.PANEL_BG)
		for side in 2:
			var y := o.y + 4 + side * 52
			var col: Color = UnitIcons.SIDE_COLORS[side]
			UnitIcons.draw_marker(wsheet, WGLYPHS[i], Vector2(o.x + 12, y + 12), 8.0, col)
			UnitIcons.draw_marker(wsheet, WGLYPHS[i], Vector2(o.x + 44, y + 16), 12.0, col)
			UnitIcons.draw_marker(wsheet, WGLYPHS[i], Vector2(o.x + 94, y + 24), 24.0, col)
		UnitIcons.draw_marker(wsheet, WGLYPHS[i] + 100, Vector2(o.x + 140, o.y + 22), 14.0, UnitIcons.SIDE_COLORS[0])
		UnitIcons.draw_marker(wsheet, WGLYPHS[i] + 200, Vector2(o.x + 140, o.y + 62), 14.0, UnitIcons.SIDE_COLORS[0])
		wsheet.draw_string(font, o + Vector2(6, WCELL.y - 12), "glyph %d" % WGLYPHS[i], HORIZONTAL_ALIGNMENT_LEFT, WCELL.x - 10, 11, Kit.COL_DIM)
	# The UI twins: the Rome icon, then the West one, at 18 and 22 px, dark on light as well.
	var y0 := 34.0 + 3 * WCELL.y + 14.0
	wsheet.draw_string(font, Vector2(8, y0), "UI icons with a West twin (game/ui_icons.gd, _w): Rome left, West right",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Kit.COL_GOLD)
	for i in UiIcons.WEST_NAMES.size():
		var nm: String = UiIcons.WEST_NAMES[i]
		var base := nm.trim_suffix("_w")
		var o := Vector2(8 + (i % 7) * 142, y0 + 10 + (i / 7) * 68)
		wsheet.draw_rect(Rect2(o, Vector2(138, 64)), Kit.PANEL_BG)
		UiIcons.draw_icon(wsheet, base, Rect2(o + Vector2(4, 6), Vector2(18, 18)), Kit.COL_DIM)
		UiIcons.draw_icon(wsheet, base, Rect2(o + Vector2(4, 28), Vector2(18, 18)), Kit.COL_DIM)
		UiIcons.draw_icon(wsheet, nm, Rect2(o + Vector2(30, 6), Vector2(18, 18)), Kit.COL_TEXT)
		UiIcons.draw_icon(wsheet, nm, Rect2(o + Vector2(54, 4), Vector2(22, 22)), Kit.COL_TEXT)
		UiIcons.draw_icon(wsheet, nm, Rect2(o + Vector2(84, 4), Vector2(44, 44)), Kit.COL_TEXT)
		wsheet.draw_string(font, o + Vector2(6, 58), nm, HORIZONTAL_ALIGNMENT_LEFT, 100, 10, Kit.COL_DIM)


func _process_west() -> bool:
	wframes += 1
	if wframes < 6:
		return false
	var img := wvp.get_texture().get_image()
	for i in WGLYPHS.size():
		var o := (_glyph_origin(i) + Vector2(94 - 22, 4 + 24 - 22)) * K  # the 48 px blue marker's box
		var lit := 0
		for y in int(44 * K):
			for x in int(44 * K):
				if img.get_pixel(int(o.x) + x, int(o.y) + y).r > 0.9:
					lit += 1
		if lit < 30:
			print("FAIL West glyph %d draws nothing (%d white pixels)" % [WGLYPHS[i], lit])
			fails += 1
	var path := ProjectSettings.globalize_path(out_west) if out_west.begins_with("res://") else out_west
	img.save_png(path)
	print("saved ", path, " ", img.get_size(), " ", WGLYPHS.size(), " West glyphs, ", UiIcons.WEST_NAMES.size(), " UI twins")
	print("ICON GALLERY %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
	return true
