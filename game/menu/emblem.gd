extends Control
## A setting's emblem on the title menu and its pages: the Caribbean's black flag (a compass rose over crossed
## cutlasses) and Rome's eagle over a laurel wreath. Two styles (MenuPrefs.emblems_pref): "drawn" is vector art
## made in code, crisp at any size; "painted" is assets/ui/emblems/<pack>.png (512 px, alpha) and falls back to the
## drawn mark when the file is missing. View only. tests/menu_test.gd renders both into a sheet.

const MenuPrefs := preload("res://game/menu/menu_prefs.gd")

const GOLD := Color(0.69, 0.54, 0.25)      # b08a40
const GOLD_LIGHT := Color(0.93, 0.8, 0.45)
const INK := Color(0.10, 0.08, 0.06)       # 1a1410
const BONE := Color(0.9, 0.86, 0.74)
const PACKS: Array[String] = ["west", "rome"]
const DIR := "res://assets/ui/emblems/"

static var _tex := {}   # pack -> Texture2D or null (missing)

var pack := "west"
## "" = the setting's style, else "drawn" / "painted".
var style := ""


static func make(p_pack: String, px: float, p_style: String = "") -> Control:
	var e = (load("res://game/menu/emblem.gd") as GDScript).new()
	e.pack = p_pack
	e.style = p_style
	e.custom_minimum_size = Vector2(px, px)
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return e


## The painted emblem of a pack, null when its file is missing.
static func painted(p_pack: String) -> Texture2D:
	if _tex.has(p_pack):
		return _tex[p_pack]
	var t: Texture2D = null
	var path := DIR + p_pack + ".png"
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)   # (not imported yet: still readable from the project folder)
		if img != null and not img.is_empty():
			t = ImageTexture.create_from_image(img)
	_tex[p_pack] = t
	return t


## Which style is really shown for this emblem.
func shown_style() -> String:
	var s := style if style != "" else MenuPrefs.emblems_pref()
	return "painted" if s == "painted" and painted(pack) != null else "drawn"


func _ready() -> void:
	add_to_group("menu_emblem")   # (Options redraws them all when the style changes)


func _draw() -> void:
	var side := minf(size.x, size.y)
	var r := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	if shown_style() == "painted":
		draw_texture_rect(painted(pack), r, false)
	else:
		draw_mark(self, pack, r)


# ------------------------------------------------------------------ vector marks ---

## Draw the drawn emblem of `p_pack` in rect r (square) on any CanvasItem.
static func draw_mark(ci: CanvasItem, p_pack: String, r: Rect2) -> void:
	if p_pack == "rome":
		_rome(ci, r)
	else:
		_west(ci, r)


static func _pt(r: Rect2, x: float, y: float) -> Vector2:
	return r.position + Vector2(x, y) * (r.size.x / 100.0)


static func _pts(r: Rect2, a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, a.size(), 2):
		out.append(_pt(r, a[i], a[i + 1]))
	return out


static func _mirror(a: Array) -> Array:
	var out: Array = []
	for i in range(a.size() - 2, -1, -2):
		out.append(100.0 - float(a[i]))
		out.append(float(a[i + 1]))
	return out


static func _poly(ci: CanvasItem, r: Rect2, a: Array, col: Color) -> void:
	var p := _pts(r, a)
	if Geometry2D.triangulate_polygon(p).size() >= 3:
		ci.draw_colored_polygon(p, col)


static func _line(ci: CanvasItem, r: Rect2, a: Array, w: float, col: Color) -> void:
	ci.draw_polyline(_pts(r, a), col, maxf(w * r.size.x / 100.0, 1.0), true)


## A curved cutlass from the hilt to the tip (both in 0..100), bulging to `bend` (a side, in units).
static func _cutlass(ci: CanvasItem, r: Rect2, hilt: Vector2, tip: Vector2, bend: float) -> void:
	var d := (tip - hilt)
	var n := Vector2(-d.y, d.x).normalized()
	var blade := PackedVector2Array()
	var back := PackedVector2Array()
	var edge := PackedVector2Array()
	var steps := 10
	for i in range(steps + 1):
		var t := float(i) / steps
		var base := hilt + d * (0.2 + 0.8 * t)
		var bow := n * bend * sin(t * PI * 0.5 + 0.05)
		var width := lerpf(5.0, 0.6, t * t)
		back.append(base + bow + n * width * 0.5)
		edge.append(base + bow - n * width * 0.5)
	for p in back:
		blade.append(_pt(r, p.x, p.y))
	for i in range(edge.size() - 1, -1, -1):
		blade.append(_pt(r, edge[i].x, edge[i].y))
	if Geometry2D.triangulate_polygon(blade).size() >= 3:
		ci.draw_colored_polygon(blade, GOLD_LIGHT)
	ci.draw_polyline(blade, INK, maxf(0.9 * r.size.x / 100.0, 0.8), true)
	# guard (a bar across) and grip
	var g := hilt + d * 0.2
	var gp := d.normalized()
	var gn := Vector2(-gp.y, gp.x)
	ci.draw_line(_pt(r, g.x - gn.x * 5.0, g.y - gn.y * 5.0), _pt(r, g.x + gn.x * 5.0, g.y + gn.y * 5.0), GOLD, maxf(2.2 * r.size.x / 100.0, 1.2), true)
	ci.draw_line(_pt(r, hilt.x, hilt.y), _pt(r, g.x, g.y), GOLD, maxf(2.4 * r.size.x / 100.0, 1.2), true)
	ci.draw_circle(_pt(r, hilt.x - gp.x * 1.2, hilt.y - gp.y * 1.2), maxf(1.8 * r.size.x / 100.0, 1.0), GOLD)


static func _west(ci: CanvasItem, r: Rect2) -> void:
	var s := r.size.x / 100.0
	# The black flag on its staff, rippling, with the compass rose on it.
	ci.draw_line(_pt(r, 15, 6), _pt(r, 15, 66), GOLD, maxf(2.6 * s, 1.2), true)
	var flag: Array = [15, 10, 28, 6, 42, 11, 56, 6, 70, 11, 86, 8, 86, 50, 70, 54, 56, 49, 42, 54, 28, 49, 15, 53]
	_poly(ci, r, flag, INK)
	var fl := _pts(r, flag)
	fl.append(fl[0])
	ci.draw_polyline(fl, GOLD, maxf(1.8 * s, 1.0), true)
	# Compass rose: eight points, the four cardinal ones long.
	var c := Vector2(50, 30)
	for k in range(8):
		var ang := TAU * k / 8.0 - PI / 2.0
		var long := 19.0 if k % 2 == 0 else 11.0
		var half := 4.4 if k % 2 == 0 else 3.0
		var dir := Vector2(cos(ang), sin(ang))
		var nrm := Vector2(-dir.y, dir.x)
		var tip := c + dir * long
		var base := c + dir * 2.0
		ci.draw_colored_polygon(PackedVector2Array([_pt(r, tip.x, tip.y), _pt(r, base.x + nrm.x * half, base.y + nrm.y * half), _pt(r, c.x, c.y)]), BONE if k % 2 == 0 else GOLD_LIGHT)
		ci.draw_colored_polygon(PackedVector2Array([_pt(r, tip.x, tip.y), _pt(r, base.x - nrm.x * half, base.y - nrm.y * half), _pt(r, c.x, c.y)]), GOLD if k % 2 == 0 else Color(GOLD.r * 0.7, GOLD.g * 0.7, GOLD.b * 0.7))
	ci.draw_circle(_pt(r, c.x, c.y), 3.0 * s, INK)
	ci.draw_circle(_pt(r, c.x, c.y), 1.7 * s, BONE)
	# Two crossed cutlasses below, hilts at the bottom corners, in front.
	_cutlass(ci, r, Vector2(12, 95), Vector2(88, 56), 7.0)
	_cutlass(ci, r, Vector2(88, 95), Vector2(12, 56), -7.0)


static func _rome(ci: CanvasItem, r: Rect2) -> void:
	var s := r.size.x / 100.0
	# Laurel wreath: two branches rising from the bottom, leaves along a ring, open at the top.
	var cen := Vector2(50, 54)
	var rad := 38.0
	for side in [-1, 1]:
		for i in range(11):
			var t := float(i) / 10.0
			var ang: float = PI / 2.0 + float(side) * (0.22 + t * 2.35)   # from the bottom round the side
			var p := cen + Vector2(cos(ang), sin(ang)) * rad
			var tang := Vector2(-sin(ang), cos(ang)) * float(side) * -1.0
			var leaf_len := lerpf(10.0, 6.5, t)
			for out in [-1, 1]:
				var dir := (tang * 0.8 + Vector2(cos(ang), sin(ang)) * float(out) * 0.6).normalized()
				var a := p
				var b := p + dir * leaf_len
				var nrm := Vector2(-dir.y, dir.x)
				var poly := PackedVector2Array([_pt(r, a.x, a.y), _pt(r, (a + b).x * 0.5 + nrm.x * 2.6, (a + b).y * 0.5 + nrm.y * 2.6), _pt(r, b.x, b.y), _pt(r, (a + b).x * 0.5 - nrm.x * 2.6, (a + b).y * 0.5 - nrm.y * 2.6)])
				if Geometry2D.triangulate_polygon(poly).size() >= 3:
					ci.draw_colored_polygon(poly, GOLD if (i + out) % 2 == 0 else GOLD_LIGHT)
	ci.draw_arc(_pt(r, cen.x, cen.y), rad * s, PI / 2.0 + 0.22, PI / 2.0 + 0.22 + 2.35, 16, GOLD, maxf(1.2 * s, 0.8), true)
	ci.draw_arc(_pt(r, cen.x, cen.y), rad * s, PI / 2.0 - 0.22 - 2.35, PI / 2.0 - 0.22, 16, GOLD, maxf(1.2 * s, 0.8), true)
	# Ribbon tying the stems.
	_poly(ci, r, [44, 91, 50, 87, 56, 91, 60, 97, 54, 94, 50, 98, 46, 94, 40, 97], Color(0.75, 0.2, 0.18))
	# The eagle, wings raised: tail, body, the two wings in feathered steps, the head turned to the right.
	var wing_r: Array = [55, 44, 62, 34, 72, 26, 84, 20, 92, 24, 88, 30, 94, 33, 88, 38, 93, 43, 86, 46, 89, 52, 80, 52, 78, 58, 68, 54, 62, 58, 56, 60]
	_poly(ci, r, wing_r, GOLD_LIGHT)
	_poly(ci, r, _mirror(wing_r), GOLD_LIGHT)
	_poly(ci, r, [43, 60, 50, 56, 57, 60, 61, 72, 56, 78, 60, 84, 50, 80, 40, 84, 44, 78, 39, 72], GOLD)   # body and tail
	_poly(ci, r, [46, 46, 54, 46, 56, 62, 50, 70, 44, 62], GOLD_LIGHT)   # chest
	ci.draw_circle(_pt(r, 50, 38), 6.2 * s, GOLD_LIGHT)   # head
	_poly(ci, r, [54, 35, 63, 38, 55, 42], GOLD)   # beak
	ci.draw_circle(_pt(r, 52, 36.5), 1.1 * s, INK)   # eye
	# wing feather lines
	for fy in [[58, 38, 86, 28], [58, 44, 88, 38], [58, 50, 84, 47]]:
		_line(ci, r, fy, 0.9, INK)
		_line(ci, r, [100.0 - fy[0], fy[1], 100.0 - fy[2], fy[3]], 0.9, INK)
