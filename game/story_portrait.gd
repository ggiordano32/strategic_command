extends RefCounted
## Code-drawn portraits for the story campaign "The Brethren's Due" (no
## textures, no fonts): a bust in a framed roundel in the speaker's badge
## colour, one per CHARS key of campaign/data/story_brethren.gd. View only.
## Readable at 48 and 96 px. draw(ci, key, rect) draws on any CanvasItem,
## make_control(key, px) makes a Control; has(key) is false for unknown keys
## and the narrator "" (the caller draws the faction mark instead).
## tests/portrait_gallery.gd renders the contact sheet.

const KEYS: Array[String] = ["mercy", "lindo", "vane", "mendoza", "ashby", "boucher", "jeremy", "hesketh", "crew", "captain", "partner"]
const COLS := {
	"mercy": "b8432f", "lindo": "7b5ea7", "vane": "8a6a3a", "mendoza": "d9a31f", "ashby": "c8402f",
	"boucher": "5a1a1a", "crew": "5a6b5a", "jeremy": "8a4fc4", "hesketh": "3f6f8f", "captain": "4a4a52", "partner": "2f7f6f",
}
const INK := Color(0.07, 0.06, 0.06)
const WHITE := Color(0.95, 0.93, 0.88)

static var _ci: CanvasItem
static var _c := Vector2.ZERO
static var _s := 1.0
static var _ink_w := 1.0


static func has(key: String) -> bool:
	return KEYS.has(key)


static func make_control(key: String, size: float) -> Control:
	var m := Pic.new()
	m.key = key
	m.custom_minimum_size = Vector2(size, size)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


class Pic extends Control:
	var key := ""
	func _draw() -> void:
		var side := minf(size.x, size.y)
		var r := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
		(load("res://game/story_portrait.gd") as Script).call("draw", self, key, r)


## Draw the portrait filling the square centred in rect.
static func draw(ci: CanvasItem, key: String, rect: Rect2) -> void:
	if not has(key):
		return
	var side := minf(rect.size.x, rect.size.y)
	_ci = ci
	_c = rect.get_center()
	_s = side * 0.5
	_ink_w = maxf(1.0, side / 48.0)
	var col := Color(String(COLS[key]))
	_frame(col)
	match key:
		"mercy": _mercy()
		"lindo": _lindo()
		"vane": _vane()
		"mendoza": _mendoza()
		"ashby": _ashby()
		"boucher": _boucher()
		"jeremy": _jeremy()
		"hesketh": _hesketh()
		"crew": _crew()
		"captain": _captain()
		"partner": _partner()
	_ci = null


# ---------------------------------------------------------------- pen ---

static func _p(x: float, y: float) -> Vector2:
	return _c + Vector2(x, y) * _s


static func _pts(xy: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, xy.size(), 2):
		out.append(_p(float(xy[i]), float(xy[i + 1])))
	return out


## Filled polygon with a thin dark edge.
static func _poly(xy: Array, fill: Color, edge := true) -> void:
	var pts := _pts(xy)
	_ci.draw_colored_polygon(pts, fill)
	if edge:
		var closed := pts.duplicate()
		closed.append(pts[0])
		_ci.draw_polyline(closed, INK, _ink_w)


static func _ell(cx: float, cy: float, rx: float, ry: float, fill: Color, edge := true) -> void:
	var xy: Array = []
	for i in 28:
		var a := TAU * i / 28.0
		xy.append(cx + cos(a) * rx)
		xy.append(cy + sin(a) * ry)
	_poly(xy, fill, edge)


static func _ln(x1: float, y1: float, x2: float, y2: float, w: float, col: Color) -> void:
	_ci.draw_line(_p(x1, y1), _p(x2, y2), col, maxf(1.0, w * _s))


static func _arc(cx: float, cy: float, r: float, a0: float, a1: float, w: float, col: Color) -> void:
	_ci.draw_arc(_p(cx, cy), r * _s, deg_to_rad(a0), deg_to_rad(a1), 16, col, maxf(1.0, w * _s))


static func _dot(cx: float, cy: float, r: float, col: Color) -> void:
	_ci.draw_circle(_p(cx, cy), maxf(0.8, r * _s), col)


## Panel + roundel + ring in the badge colour.
static func _frame(col: Color) -> void:
	var r := Rect2(_c - Vector2(_s, _s), Vector2(_s, _s) * 2.0)
	_ci.draw_rect(r, col.darkened(0.55))
	_ci.draw_circle(_c, _s * 0.93, col.lightened(0.05))
	_ci.draw_circle(_c + Vector2(0, -_s * 0.25), _s * 0.62, col.lightened(0.22))
	_ci.draw_arc(_c, _s * 0.93, 0, TAU, 40, INK, _ink_w)
	_ci.draw_rect(r, INK, false, _ink_w * 1.5)


## Shoulders: a coat shape at the bottom, with a neck. Clipped by shape to fit.
static func _shoulders(coat: Color, skin: Color) -> void:
	_poly([-0.30, 0.46, -0.20, 0.34, 0.20, 0.34, 0.30, 0.46, 0.62, 0.62, 0.66, 0.92, -0.66, 0.92, -0.62, 0.62], coat)
	_poly([-0.13, 0.20, 0.13, 0.20, 0.15, 0.40, 0.0, 0.52, -0.15, 0.40], skin)


static func _head(skin: Color, rx := 0.30, ry := 0.36) -> void:
	_ell(0, -0.12, rx, ry, skin)


## Eyes at a given height, brows, nose.
static func _face(brow := 0.0, eye := Color(0.1, 0.08, 0.07), gap := 0.12) -> void:
	_dot(-gap, -0.14, 0.035, WHITE)
	_dot(gap, -0.14, 0.035, WHITE)
	_dot(-gap, -0.14, 0.022, eye)
	_dot(gap, -0.14, 0.022, eye)
	_ln(-gap - 0.07, -0.22 + brow, -gap + 0.06, -0.22 - brow, 0.03, INK)
	_ln(gap + 0.07, -0.22 + brow, gap - 0.06, -0.22 - brow, 0.03, INK)
	_ln(0.0, -0.12, 0.03, -0.01, 0.025, INK.lightened(0.15))


static func _mouth(smile := 0.0, y := 0.1, w := 0.1) -> void:
	if smile == 0.0:
		_ln(-w, y, w, y, 0.03, INK)
	else:
		_ci.draw_polyline(_pts([-w, y - smile * 0.4, 0, y + smile, w, y - smile * 0.4]), INK, maxf(1.0, 0.03 * _s))


# --------------------------------------------------------------- cast ---

static func _mercy() -> void:
	var skin := Color("c98f60")
	var coat := Color("a82a24")
	# braid behind
	_ell(0.30, 0.18, 0.08, 0.22, Color("2a1a14"))
	_shoulders(coat, skin)
	_ln(-0.30, 0.46, -0.05, 0.92, 0.05, Color("e2b84a"))  # baldric
	_ln(0.0, 0.40, 0.0, 0.92, 0.03, Color("6e1612"))
	_head(skin)
	# dark hair under the wrap
	_poly([-0.30, -0.14, -0.24, 0.02, -0.30, 0.2, -0.36, 0.0], Color("2a1a14"))
	_face(0.03)
	_mouth(-0.02, 0.12, 0.09)
	# scar over the left cheek
	_ln(-0.22, -0.06, -0.10, 0.12, 0.025, Color("e8c8b0"))
	_ln(-0.20, 0.0, -0.14, 0.0, 0.02, Color("e8c8b0"))
	# tricorn
	_poly([-0.52, -0.22, -0.32, -0.34, -0.30, -0.56, 0.0, -0.66, 0.30, -0.56, 0.32, -0.34, 0.52, -0.22, 0.0, -0.40], Color("2c2a38"))
	_ln(-0.50, -0.23, 0.0, -0.40, 0.04, Color("e2b84a"))
	_ln(0.50, -0.23, 0.0, -0.40, 0.04, Color("e2b84a"))
	_dot(0.0, -0.50, 0.05, Color("e2b84a"))


static func _lindo() -> void:
	var skin := Color("e0b48e")
	var coat := Color("5c3e8a")
	_shoulders(coat, skin)
	_poly([-0.14, 0.38, 0.0, 0.62, 0.14, 0.38, 0.1, 0.5, 0.0, 0.76, -0.1, 0.5], WHITE)  # cravat
	for sx in [-0.5, 0.5]:
		_ln(sx * 0.55, 0.7, sx * 0.55, 0.92, 0.03, Color("e2b84a"))
	# wig: side curls
	for i in 4:
		_ell(-0.34, -0.3 + i * 0.16, 0.12, 0.09, Color("e6e2da"))
		_ell(0.34, -0.3 + i * 0.16, 0.12, 0.09, Color("e6e2da"))
	_head(skin, 0.28, 0.34)
	_poly([-0.30, -0.2, -0.24, -0.52, 0.0, -0.6, 0.24, -0.52, 0.30, -0.2, 0.12, -0.34, -0.12, -0.34], Color("e6e2da"))
	# spectacles
	var gold := Color("e2b84a")
	_ci.draw_arc(_p(-0.12, -0.14), 0.09 * _s, 0, TAU, 16, gold, maxf(1.0, 0.03 * _s))
	_ci.draw_arc(_p(0.12, -0.14), 0.09 * _s, 0, TAU, 16, gold, maxf(1.0, 0.03 * _s))
	_ln(-0.03, -0.15, 0.03, -0.15, 0.025, gold)
	_dot(-0.12, -0.14, 0.022, INK)
	_dot(0.12, -0.14, 0.022, INK)
	_ln(-0.2, -0.24, -0.06, -0.26, 0.03, Color("a8a49c"))
	_ln(0.2, -0.24, 0.06, -0.26, 0.03, Color("a8a49c"))
	_ln(0.0, -0.1, 0.03, 0.0, 0.025, INK.lightened(0.15))
	# smug grin with a gold tooth
	_mouth(0.05, 0.1, 0.1)
	_poly([0.02, 0.1, 0.07, 0.1, 0.07, 0.16, 0.02, 0.16], gold, false)
	# ringed hand at the chest
	_ell(0.42, 0.66, 0.12, 0.1, skin)
	_dot(0.42, 0.62, 0.05, Color("66e0ff"))
	_ci.draw_arc(_p(0.42, 0.66), 0.06 * _s, 0, TAU, 10, gold, maxf(1.0, 0.03 * _s))


static func _vane() -> void:
	# sepia logbook page: ink figure on aged paper
	var paper := Color("d9c79a")
	var ink := Color("4a3a24")
	var faded := Color("8c7752")
	# ruled lines on the page behind
	for i in 6:
		_ln(-0.8, -0.7 + i * 0.28, 0.8, -0.7 + i * 0.28, 0.012, Color("b8a37a"))
	_poly([-0.30, 0.46, -0.20, 0.34, 0.20, 0.34, 0.30, 0.46, 0.62, 0.62, 0.66, 0.92, -0.66, 0.92, -0.62, 0.62], faded)
	_poly([-0.13, 0.20, 0.13, 0.20, 0.15, 0.40, 0.0, 0.52, -0.15, 0.40], paper.darkened(0.12))
	_head(paper.darkened(0.08))
	# long hair and a captain's hat
	_poly([-0.32, -0.2, -0.34, 0.24, -0.22, 0.12, -0.26, -0.06], ink)
	_poly([0.32, -0.2, 0.34, 0.24, 0.22, 0.12, 0.26, -0.06], ink)
	_poly([-0.46, -0.24, -0.30, -0.56, 0.0, -0.64, 0.30, -0.56, 0.46, -0.24, 0.0, -0.36], ink)
	# hollow eyes, grim mouth
	_dot(-0.12, -0.14, 0.04, ink)
	_dot(0.12, -0.14, 0.04, ink)
	_ln(-0.2, -0.22, -0.06, -0.2, 0.03, ink)
	_ln(0.2, -0.22, 0.06, -0.2, 0.03, ink)
	_ln(0.0, -0.1, 0.03, 0.0, 0.025, ink)
	_ln(-0.09, 0.12, 0.09, 0.12, 0.03, ink)
	# noose-frayed rope collar
	var rope := Color("a07a3c")
	var zig: Array = []
	for i in 9:
		zig.append(-0.34 + i * 0.085)
		zig.append(0.34 + (0.09 if i % 2 == 0 else 0.0) + 0.14 * (1.0 - absf(i - 4.0) / 4.0) * 0.0 + absf(i - 4.0) * -0.015)
	_ci.draw_polyline(_pts(zig), rope, maxf(1.5, 0.07 * _s))
	_ci.draw_polyline(_pts(zig), INK, maxf(1.0, 0.012 * _s))
	_ln(0.0, 0.4, -0.1, 0.62, 0.05, rope)
	_ln(0.0, 0.4, 0.1, 0.64, 0.05, rope)
	_ln(-0.1, 0.62, -0.14, 0.72, 0.02, rope)
	_ln(-0.1, 0.62, -0.06, 0.74, 0.02, rope)
	_ln(0.1, 0.64, 0.14, 0.74, 0.02, rope)
	# ink blot and quill
	_dot(-0.58, 0.58, 0.06, ink)
	_ln(0.5, 0.2, 0.74, -0.2, 0.025, ink)
	_poly([0.74, -0.2, 0.84, -0.5, 0.66, -0.3], paper.lightened(0.2))
	# faded wash
	_ci.draw_rect(Rect2(_c - Vector2(_s, _s), Vector2(_s, _s) * 2.0), Color(0.85, 0.78, 0.6, 0.18))


static func _mendoza() -> void:
	var skin := Color("c89a70")
	var steel := Color("b9c0c8")
	_shoulders(Color("2e2a34"), skin)
	_poly([-0.5, 0.62, -0.3, 0.46, 0.3, 0.46, 0.5, 0.62, 0.0, 0.7], Color("2e2a34").lightened(0.1), false)
	# ruff
	for i in 7:
		_ell(-0.3 + i * 0.1, 0.42, 0.075, 0.07, WHITE)
	_head(skin, 0.28, 0.33)
	_face(0.03)
	# moustache and pointed beard
	_poly([-0.14, 0.02, 0.0, 0.0, 0.14, 0.02, 0.06, 0.08, 0.0, 0.05, -0.06, 0.08], Color("1c1412"))
	_poly([-0.14, 0.08, 0.14, 0.08, 0.1, 0.24, 0.0, 0.5, -0.1, 0.24], Color("1c1412"))
	# morion helmet with comb and plume
	_poly([-0.36, -0.24, -0.30, -0.5, -0.1, -0.62, 0.1, -0.62, 0.30, -0.5, 0.36, -0.24, 0.5, -0.18, 0.0, -0.32, -0.5, -0.18], steel)
	_poly([-0.08, -0.62, 0.0, -0.84, 0.08, -0.62], steel.darkened(0.15))
	_ln(-0.3, -0.4, 0.3, -0.4, 0.02, Color("e8c040"))
	_poly([0.06, -0.62, 0.34, -0.9, 0.5, -0.76, 0.3, -0.7, 0.4, -0.6, 0.2, -0.6], Color("c8302a"))
	# medal of the order
	_ln(-0.08, 0.5, 0.0, 0.7, 0.03, Color("c8302a"))
	_ln(0.08, 0.5, 0.0, 0.7, 0.03, Color("c8302a"))
	_dot(0.0, 0.74, 0.08, Color("f0c030"))
	_dot(0.0, 0.74, 0.035, Color("c8302a"))


static func _ashby() -> void:
	var skin := Color("ecc6a8")
	var wig := Color("f0ece6")
	var coat := Color("a8261f")
	# big wig behind, falling to the shoulders
	_poly([0.0, -0.78, -0.3, -0.7, -0.5, -0.4, -0.56, 0.0, -0.58, 0.5, -0.4, 0.6, -0.2, 0.2, 0.2, 0.2, 0.4, 0.6, 0.58, 0.5, 0.56, 0.0, 0.5, -0.4, 0.3, -0.7], wig)
	for i in 3:
		_ell(-0.5, 0.0 + i * 0.2, 0.1, 0.1, wig.darkened(0.06))
		_ell(0.5, 0.0 + i * 0.2, 0.1, 0.1, wig.darkened(0.06))
	_poly([-0.30, 0.46, -0.20, 0.34, 0.20, 0.34, 0.30, 0.46, 0.62, 0.62, 0.66, 0.92, -0.66, 0.92, -0.62, 0.62], coat)
	_poly([-0.13, 0.20, 0.13, 0.20, 0.15, 0.40, 0.0, 0.52, -0.15, 0.40], skin)
	# lace cravat
	_poly([-0.16, 0.34, 0.16, 0.34, 0.2, 0.56, 0.1, 0.5, 0.0, 0.72, -0.1, 0.5, -0.2, 0.56], WHITE)
	_head(skin, 0.26, 0.32)
	# wig fringe over the brow
	_poly([-0.28, -0.14, -0.24, -0.5, 0.0, -0.58, 0.24, -0.5, 0.28, -0.14, 0.14, -0.34, 0.0, -0.28, -0.14, -0.34], wig)
	_face(-0.02, Color("2a4a6a"), 0.11)
	_dot(-0.16, -0.02, 0.05, Color("f0a0a0"))
	_dot(0.16, -0.02, 0.05, Color("f0a0a0"))
	_mouth(-0.015, 0.11, 0.07)
	_ln(-0.04, 0.0, -0.02, 0.04, 0.02, INK.lightened(0.2))
	# gold star of office
	_dot(0.4, 0.7, 0.07, Color("f0c030"))


static func _boucher() -> void:
	var skin := Color("c8a888")
	var coat := Color("2a1014")
	_shoulders(coat, skin)
	_ln(-0.62, 0.62, -0.4, 0.5, 0.04, Color("8a1a1a"))
	_head(skin, 0.31, 0.37)
	# stubble
	_poly([-0.26, 0.02, 0.26, 0.02, 0.2, 0.2, 0.0, 0.26, -0.2, 0.2], Color("5a4a40"), false)
	# bandana + knot
	_poly([-0.33, -0.2, -0.28, -0.42, 0.0, -0.5, 0.28, -0.42, 0.33, -0.2, 0.0, -0.3], Color("8a1414"))
	_poly([0.28, -0.3, 0.55, -0.18, 0.46, -0.36, 0.56, -0.5, 0.3, -0.38], Color("8a1414"))
	for i in 4:
		_dot(-0.2 + i * 0.13, -0.38, 0.018, WHITE)
	# eyes: one scarred shut
	_ln(-0.19, -0.14, -0.05, -0.14, 0.04, INK)
	_dot(0.12, -0.14, 0.04, WHITE)
	_dot(0.12, -0.14, 0.025, Color("a01010"))
	_ln(-0.2, -0.22, -0.05, -0.26, 0.03, INK)
	_ln(0.2, -0.28, 0.05, -0.2, 0.03, INK)
	_ln(0.0, -0.1, 0.03, 0.0, 0.025, INK.lightened(0.15))
	# long scar across the eye and cheek
	_ln(-0.26, -0.3, -0.06, 0.1, 0.03, Color("e8d0c0"))
	# cruel grin with teeth
	_poly([-0.15, 0.08, 0.0, 0.14, 0.15, 0.08, 0.1, 0.18, 0.0, 0.2, -0.1, 0.18], Color("2a0a0a"))
	for i in 5:
		_poly([-0.12 + i * 0.06, 0.1, -0.07 + i * 0.06, 0.1, -0.095 + i * 0.06, 0.15], WHITE, false)
	# bloody cutlass
	_ln(0.5, 0.95, 0.74, 0.1, 0.05, Color("cfd6dc"))
	_ln(0.74, 0.1, 0.78, -0.1, 0.04, Color("cfd6dc"))
	_ln(0.44, 0.72, 0.64, 0.82, 0.045, Color("d9a31f"))
	_ln(0.7, 0.3, 0.74, 0.12, 0.04, Color("b01818"))
	_dot(0.66, 0.46, 0.025, Color("b01818"))
	_dot(0.78, 0.0, 0.02, Color("b01818"))
	_dot(0.6, 0.6, 0.02, Color("b01818"))


static func _jeremy() -> void:
	var skin := Color("8a5a3a")
	var coat := Color("b3262b")
	_shoulders(coat, skin)
	# gold-laced lapels and buttons
	_ln(-0.3, 0.46, -0.3, 0.92, 0.04, Color("e8c040"))
	_ln(0.3, 0.46, 0.3, 0.92, 0.04, Color("e8c040"))
	for i in 3:
		_dot(0.0, 0.62 + i * 0.12, 0.03, Color("e8c040"))
	_poly([-0.13, 0.3, 0.0, 0.5, 0.13, 0.3], WHITE)
	# long black hair behind
	_poly([-0.3, -0.2, -0.38, 0.2, -0.3, 0.5, -0.2, 0.2], Color("1a1210"))
	_poly([0.3, -0.2, 0.38, 0.2, 0.3, 0.5, 0.2, 0.2], Color("1a1210"))
	_head(skin, 0.29, 0.35)
	_poly([-0.29, -0.16, -0.24, -0.42, 0.0, -0.46, 0.24, -0.42, 0.29, -0.16, 0.14, -0.3, -0.14, -0.3], Color("1a1210"))
	_face(0.0)
	_mouth(0.03, 0.11, 0.09)
	_ln(-0.2, -0.04, -0.12, -0.02, 0.02, Color("c04030"))  # face paint
	_ln(0.2, -0.04, 0.12, -0.02, 0.02, Color("c04030"))
	# feather crown on a gold band
	var fe: Array = [Color("2f9e5a"), Color("d9302a"), Color("f0c030"), Color("2f7ec8"), Color("d9302a"), Color("2f9e5a"), Color("f0c030")]
	for i in 7:
		var a := deg_to_rad(-150.0 + i * 20.0)
		var tip := Vector2(cos(a), sin(a))
		var base := Vector2(0, -0.28)
		var p1 := base + tip * 0.34
		var p2 := base + tip * 0.74
		var n := Vector2(-tip.y, tip.x) * 0.07
		_poly([p1.x - n.x, p1.y - n.y, p2.x, p2.y, p1.x + n.x, p1.y + n.y], fe[i] as Color)
	_poly([-0.3, -0.26, 0.3, -0.26, 0.3, -0.38, 0.22, -0.34, 0.1, -0.44, 0.0, -0.34, -0.1, -0.44, -0.22, -0.34, -0.3, -0.38], Color("f0c030"))


static func _hesketh() -> void:
	var skin := Color("d9a67a")
	var coat := Color("3f5a72")
	_shoulders(coat, skin)
	_poly([-0.14, 0.36, 0.0, 0.56, 0.14, 0.36], WHITE)
	for i in 3:
		_dot(0.2, 0.62 + i * 0.1, 0.025, Color("e8c040"))
	_head(skin, 0.30, 0.35)
	# grey-flecked beard
	_poly([-0.29, 0.0, 0.29, 0.0, 0.22, 0.2, 0.0, 0.34, -0.22, 0.2], Color("5a5048"))
	_poly([-0.12, 0.0, 0.12, 0.0, 0.08, 0.08, 0.0, 0.06, -0.08, 0.08], Color("5a5048").lightened(0.3), false)
	_face(0.0)
	_mouth(0.03, 0.1, 0.07)
	_ln(-0.3, -0.12, -0.34, 0.0, 0.05, Color("2c2420"))  # hair
	_ln(0.3, -0.12, 0.34, 0.0, 0.05, Color("2c2420"))
	# hat with a feather
	_poly([-0.5, -0.22, -0.34, -0.34, -0.3, -0.62, 0.0, -0.7, 0.3, -0.62, 0.34, -0.34, 0.5, -0.22, 0.0, -0.38], Color("3a2a22"))
	_ln(-0.32, -0.36, 0.32, -0.36, 0.05, Color("e8c040"))
	_poly([0.2, -0.5, 0.7, -0.84, 0.6, -0.5, 0.5, -0.36, 0.3, -0.4], WHITE)
	_ln(0.22, -0.46, 0.64, -0.78, 0.015, Color("a8a49c"))
	# parrot on the shoulder
	_ell(-0.52, 0.34, 0.13, 0.17, Color("d9302a"))
	_ell(-0.5, 0.42, 0.07, 0.12, Color("2f7ec8"))
	_ell(-0.5, 0.16, 0.1, 0.1, Color("d9302a"))
	_dot(-0.47, 0.14, 0.03, WHITE)
	_dot(-0.46, 0.14, 0.015, INK)
	_poly([-0.4, 0.12, -0.3, 0.18, -0.4, 0.22], Color("f0c030"))
	_poly([-0.56, 0.5, -0.5, 0.72, -0.44, 0.5], Color("2f9e5a"))


static func _crew() -> void:
	# crossed cutlasses behind three faces in a huddle, a skull above
	var steel := Color("cfd6dc")
	_ln(-0.7, -0.6, 0.7, 0.8, 0.07, steel)
	_ln(0.7, -0.6, -0.7, 0.8, 0.07, steel)
	_ln(-0.7, -0.6, -0.56, -0.46, 0.09, Color("d9a31f"))
	_ln(0.7, -0.6, 0.56, -0.46, 0.09, Color("d9a31f"))
	# bodies
	_poly([-0.74, 0.92, -0.7, 0.46, -0.5, 0.36, -0.28, 0.46, -0.24, 0.92], Color("7a3a2a"))
	_poly([0.74, 0.92, 0.7, 0.46, 0.5, 0.36, 0.28, 0.46, 0.24, 0.92], Color("2f4a6a"))
	_poly([-0.26, 0.92, -0.22, 0.36, 0.0, 0.26, 0.22, 0.36, 0.26, 0.92], Color("c8b890"))
	# side heads
	_ell(-0.5, 0.12, 0.2, 0.24, Color("b8845a"))
	_poly([-0.72, 0.04, -0.66, -0.2, -0.5, -0.24, -0.32, -0.2, -0.28, 0.04, -0.5, -0.06], Color("c8302a"))
	_ln(-0.62, 0.1, -0.56, 0.1, 0.03, INK)
	_ln(-0.44, 0.1, -0.38, 0.1, 0.03, INK)
	_ln(-0.56, 0.24, -0.44, 0.24, 0.03, INK)
	_ell(0.5, 0.12, 0.2, 0.24, Color("e0b48e"))
	_poly([0.72, 0.0, 0.64, -0.24, 0.5, -0.3, 0.36, -0.24, 0.28, 0.0, 0.5, -0.1], Color("2c2a38"))
	_dot(0.44, 0.1, 0.025, INK)
	_dot(0.58, 0.1, 0.025, INK)
	_ln(0.42, 0.24, 0.58, 0.22, 0.03, INK)
	_poly([0.3, 0.2, 0.7, 0.2, 0.62, 0.34, 0.5, 0.4, 0.38, 0.34], Color("6a5a48"), false)
	# centre head, taller
	_ell(0.0, -0.06, 0.24, 0.3, Color("d9a67a"))
	_poly([-0.26, -0.1, -0.22, -0.34, 0.0, -0.4, 0.22, -0.34, 0.26, -0.1, 0.0, -0.2], Color("1c1c1c"))
	_ln(-0.1, 0.0, -0.05, 0.0, 0.04, INK)
	_dot(0.1, 0.0, 0.03, INK)
	_ln(-0.1, 0.14, 0.1, 0.14, 0.03, INK)
	_ln(-0.16, 0.0, 0.16, -0.12, 0.0, INK)
	# skull on the cap
	_ell(0.0, -0.3, 0.07, 0.065, WHITE)
	_dot(-0.025, -0.31, 0.016, INK)
	_dot(0.025, -0.31, 0.016, INK)


static func _captain() -> void:
	var skin := Color("d9a67a")
	var coat := Color("34343c")
	_shoulders(coat, skin)
	_poly([-0.14, 0.36, 0.0, 0.56, 0.14, 0.36], WHITE)
	for i in 3:
		_dot(0.2, 0.62 + i * 0.1, 0.025, Color("b8b8c0"))
	# cutlass hilt over the right shoulder, strap across the chest
	_ln(-0.3, 0.4, 0.4, 0.92, 0.04, Color("6a4a2a"))
	_ln(0.5, 0.5, 0.66, 0.12, 0.05, Color("cfd6dc"))
	_ln(0.42, 0.42, 0.62, 0.56, 0.05, Color("d9a31f"))
	_dot(0.5, 0.5, 0.05, Color("d9a31f"))
	_head(skin, 0.29, 0.35)
	# dark stubble and tied-back hair
	_poly([-0.28, 0.02, 0.28, 0.02, 0.2, 0.2, 0.0, 0.24, -0.2, 0.2], Color("4a3c34"), false)
	_ln(-0.3, -0.12, -0.34, 0.06, 0.05, Color("2c2420"))
	_ln(0.3, -0.12, 0.34, 0.06, 0.05, Color("2c2420"))
	# eyes: left covered by a patch, scar across it
	_dot(0.12, -0.14, 0.035, WHITE)
	_dot(0.12, -0.14, 0.022, INK)
	_ln(0.2, -0.22, 0.06, -0.25, 0.03, INK)
	_ln(-0.2, -0.26, -0.06, -0.2, 0.03, INK)
	_ell(-0.12, -0.14, 0.075, 0.065, INK)
	_ln(-0.3, -0.24, 0.0, -0.3, 0.015, INK)
	_ln(-0.26, -0.3, -0.04, -0.02, 0.03, Color("ecd0bc"))
	_ln(0.0, -0.1, 0.03, 0.0, 0.025, INK.lightened(0.15))
	_ln(-0.08, 0.12, 0.1, 0.1, 0.03, INK)
	_ln(0.1, 0.1, 0.14, 0.06, 0.03, INK)
	# black tricorn, red feather
	_poly([-0.52, -0.22, -0.32, -0.34, -0.30, -0.56, 0.0, -0.66, 0.30, -0.56, 0.32, -0.34, 0.52, -0.22, 0.0, -0.40], Color("16161a"))
	_ln(-0.50, -0.23, 0.0, -0.40, 0.03, Color("8a8a94"))
	_ln(0.50, -0.23, 0.0, -0.40, 0.03, Color("8a8a94"))
	_poly([0.2, -0.5, 0.62, -0.88, 0.7, -0.62, 0.52, -0.42, 0.32, -0.4], Color("d9302a"))
	_ln(0.24, -0.48, 0.64, -0.8, 0.015, Color("8a1410"))


static func _partner() -> void:
	var skin := Color("a8704a")
	var coat := Color("2f7f6f")
	var teal := Color("1f5f52")
	# long braid behind, over the left shoulder
	_poly([-0.26, 0.0, -0.4, 0.3, -0.46, 0.7, -0.52, 0.94, -0.36, 0.94, -0.3, 0.7, -0.22, 0.3], Color("1c1412"))
	for i in 4:
		_ln(-0.44, 0.34 + i * 0.15, -0.3, 0.4 + i * 0.15, 0.025, Color("4a3a30"))
	_ln(-0.52, 0.92, -0.36, 0.92, 0.04, Color("d9302a"))
	_shoulders(coat, skin)
	_poly([-0.3, 0.46, -0.13, 0.34, 0.0, 0.5, 0.13, 0.34, 0.3, 0.46, 0.0, 0.7], Color("c8b890"))
	# harpoon over the right shoulder
	_ln(0.62, 0.9, 0.36, 0.0, 0.04, Color("7a5a34"))
	_ln(0.36, 0.0, 0.3, -0.18, 0.04, Color("7a5a34"))
	_poly([0.3, -0.52, 0.38, -0.2, 0.22, -0.2], Color("cfd6dc"))
	_poly([0.3, -0.52, 0.42, -0.34, 0.3, -0.28, 0.18, -0.34], Color("cfd6dc"))
	_head(skin, 0.29, 0.35)
	# bandana with a knot and tails
	_poly([-0.31, -0.16, -0.26, -0.44, 0.0, -0.52, 0.26, -0.44, 0.31, -0.16, 0.0, -0.3], Color("e8dcb8"))
	_poly([0.26, -0.3, 0.5, -0.2, 0.4, -0.36, 0.5, -0.46, 0.28, -0.4], Color("e8dcb8"))
	for i in 4:
		_dot(-0.2 + i * 0.13, -0.4, 0.02, teal)
	_ln(-0.31, -0.2, 0.31, -0.2, 0.03, teal)
	_face(0.0)
	# wide grin with teeth
	_poly([-0.15, 0.06, 0.0, 0.12, 0.15, 0.06, 0.1, 0.16, 0.0, 0.18, -0.1, 0.16], Color("2a0a0a"))
	_poly([-0.11, 0.08, 0.11, 0.08, 0.0, 0.12], WHITE, false)
	_ln(0.18, -0.02, 0.2, 0.08, 0.02, INK)
	# hooped gold earring
	_ci.draw_arc(_p(-0.3, 0.02), 0.07 * _s, 0, TAU, 14, Color("f0c030"), maxf(1.2, 0.03 * _s))
