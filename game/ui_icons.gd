extends RefCounted
## UI icons drawn in code, one line style for every screen: round-capped
## strokes of one weight (0.16 of the icon's half-size, as the unit glyphs
## in unit_icons.gd), the glyph filling 90% of a square cell, single colour.
## No textures: an icon is a VecIcon (a Texture2D that draws its strokes
## through the RenderingServer), so it is crisp at any UI scale, goes into a
## Button's `icon` like any texture and takes the button's icon colour for
## each state (normal / hover / pressed / disabled). Labels get one through
## Kit.label_icon (drawn left of the text). draw_icon() draws one onto any
## CanvasItem (the battle HUD, the gallery).
##
## Sizes follow the text: px_for(font size) (13 px text: 18 px icon, 15:
## 20, 17: 22). tests/icon_gallery.gd renders every icon into
## docs/screenshots/icons.png.

## Every icon, in gallery order. Groups: economy and time, overworld
## buttons, orders and stances, diplomacy, buildings, battle HUD, battle
## result, siege equipment, generic.
const NAMES: Array[String] = [
	"treasury", "coin", "income", "turn", "summer", "winter",
	"battles", "realm", "chronicle", "diplomacy", "goals", "units", "menu", "undo", "deselect", "end_turn", "online", "key",
	"move", "siege", "assault", "sally", "raid", "inside", "field", "stance_default", "forced_march", "fortify",
	"merge", "exchange", "recruit", "raise", "disband", "split", "gift", "withdraw", "view_map",
	"war", "peace", "trade", "trade_end", "alliance", "accept", "decline", "cancel", "close", "buy",
	"farm", "market", "barracks", "range", "stables", "workshop", "walls", "build", "upgrade",
	"fire", "hold_fire", "skirmish", "run", "deploy", "wall_up", "wall_down", "pick_up", "drop",
	"victory", "defeat", "draw", "men", "killed", "routed", "captured",
	"ladder", "ram", "tower", "siege_tower", "mantlet", "gate", "ammo", "forage", "wagon", "kill_beast", "general", "release", "crown", "dagger", "scroll",
	"stakes", "caltrops", "palisade", "rotate",
	"copy", "export", "plus", "minus",
	"tr_siege", "tr_shock", "tr_anti_cav", "tr_fearsome", "tr_ap", "tr_long_range", "tr_skirmish", "tr_fire", "tr_beast", "tr_fast",
	"cl_foot", "cl_spear", "cl_horse", "cl_missile", "cl_beast", "cl_engine",
]
const STROKE := 0.16  # line weight, in half-sizes (unit_icons: 0.17 of its glyph radius)
const FILL := 0.9     # glyph extent in the cell (5% padding each side)

static var _cache := {}
# Pen state while one icon is drawn.
static var _rid := RID()
static var _c := Vector2.ZERO
static var _s := 1.0
static var _col := Color.WHITE
static var _w := 1.0


## Icon size in logical px for text of this size.
static func px_for(font_size: int) -> int:
	return roundi(font_size * 1.3) + (1 if font_size <= 13 else 0)


## The icon as a texture of px x px logical pixels (cached).
static func tex(icon: String, px: int = 19) -> Texture2D:
	var k := "%s@%d" % [icon, px]
	if not _cache.has(k):
		var t := VecIcon.new()
		t.drawer = load("res://game/ui_icons.gd")
		t.icon = icon
		t.px = px
		_cache[k] = t
	return _cache[k]


static func has(icon: String) -> bool:
	return NAMES.has(icon)


## Draw `icon` filling the square centred in `rect` on a CanvasItem (call
## from its _draw or draw signal).
static func draw_icon(ci: CanvasItem, icon: String, rect: Rect2, col: Color) -> void:
	draw_rid(ci.get_canvas_item(), icon, rect, col)


static func draw_rid(rid: RID, icon: String, rect: Rect2, col: Color) -> void:
	var side := minf(rect.size.x, rect.size.y)
	_rid = rid
	_col = col
	_s = side * 0.5 * FILL
	_w = maxf(_s * STROKE, 0.9)
	_glyph(icon, rect.get_center(), _s)


## A Texture2D that draws an icon as vector strokes (see the header).
class VecIcon extends Texture2D:
	var icon := ""
	var px := 19
	var drawer: Script  # this file (an inner class cannot call its outer class)

	func _get_width() -> int:
		return px

	func _get_height() -> int:
		return px

	func _has_alpha() -> bool:
		return true

	func _is_pixel_opaque(_x: int, _y: int) -> bool:
		return false

	func _draw(to_canvas_item: RID, pos: Vector2, modulate: Color, _transpose: bool) -> void:
		drawer.call("draw_rid", to_canvas_item, icon, Rect2(pos, Vector2(px, px)), modulate)

	func _draw_rect(to_canvas_item: RID, rect: Rect2, _tile: bool, modulate: Color, _transpose: bool) -> void:
		drawer.call("draw_rid", to_canvas_item, icon, rect, modulate)

	func _draw_rect_region(to_canvas_item: RID, rect: Rect2, _src_rect: Rect2, modulate: Color, _transpose: bool, _clip_uv: bool) -> void:
		drawer.call("draw_rid", to_canvas_item, icon, rect, modulate)


# ------------------------------------------------------------------ pen ---

static func _p(x: float, y: float) -> Vector2:
	return _c + Vector2(x, y) * _s


## A stroke from a to b (unit coordinates), round caps.
static func _l(ax: float, ay: float, bx: float, by: float, wk: float = 1.0) -> void:
	var a := _p(ax, ay)
	var b := _p(bx, by)
	var w := _w * wk
	RenderingServer.canvas_item_add_line(_rid, a, b, _col, w, true)
	RenderingServer.canvas_item_add_circle(_rid, a, w * 0.5, _col, true)
	RenderingServer.canvas_item_add_circle(_rid, b, w * 0.5, _col, true)


## A stroked path through flat [x0, y0, x1, y1, ...], round joins.
static func _pl(xy: Array, closed: bool = false, wk: float = 1.0) -> void:
	var pts := PackedVector2Array()
	for i in range(0, xy.size(), 2):
		pts.append(_p(float(xy[i]), float(xy[i + 1])))
	if closed:
		pts.append(pts[0])
	_stroke(pts, wk)


static func _stroke(pts: PackedVector2Array, wk: float = 1.0) -> void:
	var w := _w * wk
	RenderingServer.canvas_item_add_polyline(_rid, pts, PackedColorArray([_col]), w, true)
	for q in pts:
		RenderingServer.canvas_item_add_circle(_rid, q, w * 0.5, _col, true)


## Arc around (cx, cy), radius r, angles a0 to a1 (radians, y down).
static func _arc(cx: float, cy: float, r: float, a0: float, a1: float, wk: float = 1.0) -> void:
	var n := maxi(int(absf(a1 - a0) / 0.25), 4)
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(_p(cx + cos(a) * r, cy + sin(a) * r))
	_stroke(pts, wk)


## Ellipse arc (rx, ry radii).
static func _earc(cx: float, cy: float, rx: float, ry: float, a0: float, a1: float, wk: float = 1.0) -> void:
	var n := maxi(int(absf(a1 - a0) / 0.25), 4)
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(_p(cx + cos(a) * rx, cy + sin(a) * ry))
	_stroke(pts, wk)


static func _ring(cx: float, cy: float, r: float, wk: float = 1.0) -> void:
	_arc(cx, cy, r, 0.0, TAU, wk)


static func _dot(cx: float, cy: float, r: float) -> void:
	RenderingServer.canvas_item_add_circle(_rid, _p(cx, cy), r * _s, _col, true)


## A filled polygon (flat xy), its edge smoothed by a thin stroke.
static func _fill(xy: Array) -> void:
	var pts := PackedVector2Array()
	for i in range(0, xy.size(), 2):
		pts.append(_p(float(xy[i]), float(xy[i + 1])))
	RenderingServer.canvas_item_add_polygon(_rid, pts, PackedColorArray([_col]))
	pts.append(pts[0])
	RenderingServer.canvas_item_add_polyline(_rid, pts, PackedColorArray([_col]), maxf(_w * 0.35, 0.6), true)


## Arrow head (filled) at (x, y) pointing along (dx, dy).
static func _head(x: float, y: float, dx: float, dy: float, size: float = 0.36) -> void:
	var d := Vector2(dx, dy).normalized()
	var n := Vector2(-d.y, d.x)
	var tip := Vector2(x, y) + d * size * 0.35
	var b := tip - d * size
	_fill([tip.x, tip.y, b.x + n.x * size * 0.62, b.y + n.y * size * 0.62, b.x - n.x * size * 0.62, b.y - n.y * size * 0.62])


## A straight arrow from a to b with a head at b.
static func _arrow(ax: float, ay: float, bx: float, by: float, size: float = 0.36) -> void:
	var d := Vector2(bx - ax, by - ay).normalized()
	_l(ax, ay, bx - d.x * size * 0.4, by - d.y * size * 0.4)
	_head(bx, by, d.x, d.y, size)


## A leaf (filled lens) centred at (x, y), pointing at angle a.
static func _leaf(x: float, y: float, a: float, ln: float, wd: float) -> void:
	var d := Vector2(cos(a), sin(a))
	var n := Vector2(-d.y, d.x)
	var pts: Array = []
	for i in 9:
		var t := float(i) / 8.0
		var q := Vector2(x, y) + d * ln * (t - 0.5) + n * wd * sin(t * PI)
		pts.append_array([q.x, q.y])
	for i in range(7, 0, -1):
		var t := float(i) / 8.0
		var q := Vector2(x, y) + d * ln * (t - 0.5) - n * wd * sin(t * PI)
		pts.append_array([q.x, q.y])
	_fill(pts)


## Draw another glyph scaled k around offset (ox, oy) (composites).
static func _sub(icon: String, ox: float, oy: float, k: float) -> void:
	var c0 := _c
	var s0 := _s
	_glyph(icon, _c + Vector2(ox, oy) * _s, _s * k)
	_c = c0
	_s = s0


static func _slash() -> void:
	_l(-0.8, 0.8, 0.8, -0.8, 1.1)


# --------------------------------------------------------------- glyphs ---

static func _glyph(icon: String, c: Vector2, s: float) -> void:
	_c = c
	_s = s
	match icon:
		"treasury":  # a stack of three coins
			_earc(0, -0.45, 0.75, 0.28, 0, TAU)
			for k in 2:
				var y := -0.45 + 0.42 * (k + 1)
				_earc(0, y, 0.75, 0.28, 0, PI)
				_l(-0.75, y - 0.42, -0.75, y)
				_l(0.75, y - 0.42, 0.75, y)
		"coin":  # one coin with a struck mark
			_ring(0, 0, 0.8)
			_ring(0, 0, 0.45, 0.8)
		"income":  # a rising line with an arrow
			_pl([-0.85, 0.55, -0.3, 0.0, 0.1, 0.32, 0.62, -0.25])
			_head(0.8, -0.45, 1.0, -1.1)
			_l(-0.85, 0.85, 0.85, 0.85, 0.8)
		"turn":  # hourglass
			_l(-0.62, -0.85, 0.62, -0.85)
			_l(-0.62, 0.85, 0.62, 0.85)
			_pl([-0.48, -0.85, -0.48, -0.55, -0.08, 0.0, -0.48, 0.55, -0.48, 0.85])
			_pl([0.48, -0.85, 0.48, -0.55, 0.08, 0.0, 0.48, 0.55, 0.48, 0.85])
			_fill([-0.32, 0.8, 0.32, 0.8, 0.0, 0.42])
		"summer":  # sun
			_ring(0, 0, 0.36)
			for k in 8:
				var a := TAU * k / 8.0
				_l(cos(a) * 0.62, sin(a) * 0.62, cos(a) * 0.88, sin(a) * 0.88)
		"winter":  # snowflake
			for k in 3:
				var a := PI * k / 3.0 + PI / 2.0
				var dx := cos(a) * 0.88
				var dy := sin(a) * 0.88
				_l(-dx, -dy, dx, dy)
				for sg in [-1.0, 1.0]:
					var ex: float = dx * sg
					var ey: float = dy * sg
					var b := Vector2(ex, ey) * 0.62
					var d := Vector2(ex, ey).normalized()
					var n := Vector2(-d.y, d.x) * 0.24
					_l(b.x + n.x, b.y + n.y, b.x + d.x * 0.22, b.y + d.y * 0.22, 0.8)
					_l(b.x - n.x, b.y - n.y, b.x + d.x * 0.22, b.y + d.y * 0.22, 0.8)
		"battles", "war":  # crossed swords, guards near the hilts
			for sg in [-1.0, 1.0]:
				_l(-0.78 * sg, 0.78, 0.72 * sg, -0.72)
				var hx: float = -0.5 * sg
				_l(hx - 0.22, 0.5 - 0.22 * sg, hx + 0.22, 0.5 + 0.22 * sg, 0.9)
		"realm":  # temple front
			_pl([-0.9, -0.38, 0.0, -0.88, 0.9, -0.38], true)
			_l(-0.85, 0.82, 0.85, 0.82)
			for x in [-0.6, -0.2, 0.2, 0.6]:
				_l(x, -0.18, x, 0.62, 0.9)
		"chronicle":  # an open book
			_pl([0.0, -0.55, -0.9, -0.7, -0.9, 0.6, 0.0, 0.75, 0.9, 0.6, 0.9, -0.7, 0.0, -0.55], false)
			_l(0.0, -0.55, 0.0, 0.75)
			for y in [-0.25, 0.05, 0.35]:
				_l(-0.68, y - 0.03, -0.22, y + 0.06, 0.75)
				_l(0.22, y + 0.06, 0.68, y - 0.03, 0.75)
		"diplomacy":  # a scroll
			_pl([-0.5, -0.72, 0.62, -0.72, 0.62, 0.62])
			_pl([0.5, 0.82, -0.62, 0.82, -0.62, -0.58])
			_arc(-0.5, -0.58, 0.14, PI * 0.5, PI * 2.5)
			_arc(0.5, 0.68, 0.14, -PI * 0.5, PI * 1.5)
			for y in [-0.35, -0.05, 0.25]:
				_l(-0.32, y, 0.34, y, 0.75)
		"goals":  # star (the key cities' mark on the map)
			var pts: Array = []
			for k in 10:
				var a := -PI / 2.0 + PI * k / 5.0
				var r := 0.9 if k % 2 == 0 else 0.38
				pts.append_array([cos(a) * r, sin(a) * r + 0.08])
			_pl(pts, true)
		"units":  # open book
			_pl([0.0, -0.55, -0.88, -0.75, -0.88, 0.62, 0.0, 0.82])
			_pl([0.0, -0.55, 0.88, -0.75, 0.88, 0.62, 0.0, 0.82])
			_l(0.0, -0.55, 0.0, 0.82)
		"menu":  # three bars
			for y in [-0.58, 0.0, 0.58]:
				_l(-0.75, y, 0.75, y, 1.1)
		"undo":  # arrow curving back
			_arc(0.08, 0.12, 0.62, PI * 1.12, PI * 2.5)
			_l(0.08, 0.74, -0.45, 0.74)
			_head(-0.53, -0.12, -0.25, 1.0, 0.5)
		"deselect":  # selection corners with a cross
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					_pl([0.85 * sx, 0.4 * sy, 0.85 * sx, 0.85 * sy, 0.4 * sx, 0.85 * sy])
			_l(-0.3, -0.3, 0.3, 0.3)
			_l(-0.3, 0.3, 0.3, -0.3)
		"end_turn":  # arrow to a bar
			_arrow(-0.85, 0.0, 0.42, 0.0, 0.5)
			_l(0.78, -0.75, 0.78, 0.75, 1.1)
		"online":  # signal arcs
			_dot(0.0, 0.62, 0.15)
			for r in [0.42, 0.78]:
				_arc(0.0, 0.62, r, -PI * 0.78, -PI * 0.22)
			_arc(0.0, 0.62, 1.12, -PI * 0.72, -PI * 0.28)
		"key":  # a legend: three sample rows
			for k in 3:
				var y := -0.6 + 0.6 * k
				_dot(-0.62, y, 0.17)
				_l(-0.2, y, 0.8, y)
		"move":  # dashed path into an arrow
			_l(-0.88, 0.0, -0.68, 0.0)
			_l(-0.42, 0.0, -0.22, 0.0)
			_arrow(0.04, 0.0, 0.86, 0.0, 0.5)
		"siege":  # tent (the map's siege mark)
			_pl([-0.85, 0.78, 0.0, -0.72, 0.85, 0.78], true)
			_pl([-0.24, 0.78, 0.0, 0.22, 0.24, 0.78])
			_l(0.0, -0.72, 0.12, -0.92, 0.8)
		"assault":  # ladder against a wall
			_pl([0.42, 0.85, 0.42, -0.55, 0.42, -0.85, 0.62, -0.85, 0.62, -0.68, 0.82, -0.68, 0.82, 0.85])
			_l(-0.82, 0.85, -0.12, -0.78)
			_l(-0.42, 0.85, 0.28, -0.62)
			for t in [0.2, 0.45, 0.7]:
				var ax := lerpf(-0.82, -0.12, t)
				var ay := lerpf(0.85, -0.78, t)
				var bx := lerpf(-0.42, 0.28, t * 0.92)
				var by := lerpf(0.85, -0.62, t * 0.92)
				_l(ax, ay, bx, by, 0.75)
		"sally":  # out of a gate
			_pl([-0.88, 0.85, -0.88, -0.2])
			_arc(-0.45, -0.2, 0.43, PI, TAU)
			_pl([-0.02, -0.2, -0.02, 0.05])
			_l(-0.88, 0.85, -0.6, 0.85)
			_arrow(-0.45, 0.45, 0.88, 0.45, 0.5)
		"raid":  # flame
			_pl([0.0, 0.88, -0.42, 0.72, -0.62, 0.3, -0.5, -0.1, -0.22, -0.42, -0.05, -0.9, 0.2, -0.45,
				0.45, -0.25, 0.62, 0.22, 0.45, 0.7], true)
			_pl([0.0, 0.62, -0.2, 0.42, -0.12, 0.08, 0.05, -0.12, 0.2, 0.25, 0.15, 0.55], true, 0.8)
		"inside", "walls":  # wall with crenels and a gate
			_pl([-0.88, 0.82, -0.88, -0.65, -0.55, -0.65, -0.55, -0.4, -0.18, -0.4, -0.18, -0.65, 0.18, -0.65, 0.18, -0.4,
				0.55, -0.4, 0.55, -0.65, 0.88, -0.65, 0.88, 0.82], true)
			_pl([-0.28, 0.82, -0.28, 0.32])
			_arc(0.0, 0.32, 0.28, PI, TAU)
			_l(0.28, 0.32, 0.28, 0.82)
		"field":  # pennant on a pole in the open
			_l(-0.45, -0.88, -0.45, 0.82)
			_pl([-0.45, -0.85, 0.7, -0.55, -0.45, -0.25])
			_l(-0.88, 0.82, 0.88, 0.82, 0.8)
		"stance_default":  # oblong shield with a boss
			_pl([-0.5, -0.85, 0.5, -0.85, 0.58, 0.0, 0.5, 0.85, -0.5, 0.85, -0.58, 0.0], true)
			_ring(0.0, 0.0, 0.2, 0.8)
			_l(0.0, -0.68, 0.0, -0.3, 0.8)
			_l(0.0, 0.3, 0.0, 0.68, 0.8)
		"forced_march", "run":  # double chevron
			for x in [-0.42, 0.2]:
				_pl([x - 0.25, -0.7, x + 0.4, 0.0, x - 0.25, 0.7], false, 1.15)
		"fortify":  # palisade of stakes
			for x in [-0.66, -0.22, 0.22, 0.66]:
				_pl([x - 0.16, 0.85, x - 0.16, -0.5, x, -0.82, x + 0.16, -0.5, x + 0.16, 0.85], false, 0.85)
			_l(-0.88, 0.2, 0.88, 0.2, 0.85)
		"merge":  # two arrows joining
			_pl([-0.85, -0.65, -0.1, 0.0, -0.85, 0.65])
			_arrow(-0.1, 0.0, 0.86, 0.0, 0.5)
		"exchange":  # arrows both ways
			_arrow(-0.82, -0.38, 0.82, -0.38, 0.48)
			_arrow(0.82, 0.38, -0.82, 0.38, 0.48)
		"recruit", "disband", "men":  # a soldier (with + or -)
			var ox := -0.22 if icon != "men" else 0.0
			_ring(ox, -0.42, 0.3)
			_arc(ox, 0.86, 0.66, PI, TAU)
			if icon == "recruit":
				_l(0.68, -0.6, 0.68, 0.0)
				_l(0.38, -0.3, 0.98, -0.3)
			elif icon == "disband":
				_l(0.38, -0.3, 0.98, -0.3)
		"raise":  # a standard with +
			_l(-0.35, -0.88, -0.35, 0.88)
			_l(-0.82, -0.68, 0.12, -0.68)
			_pl([-0.72, -0.68, -0.72, 0.15, -0.35, 0.0, 0.02, 0.15, 0.02, -0.68])
			_l(0.62, 0.2, 0.62, 0.86)
			_l(0.29, 0.53, 0.95, 0.53)
		"split":  # one path forking in two
			_l(-0.88, 0.0, -0.2, 0.0)
			_pl([-0.2, 0.0, 0.2, -0.5])
			_pl([-0.2, 0.0, 0.2, 0.5])
			_arrow(0.2, -0.5, 0.86, -0.5, 0.45)
			_arrow(0.2, 0.5, 0.86, 0.5, 0.45)
		"gift":  # a wrapped box
			_pl([-0.72, -0.2, 0.72, -0.2, 0.72, 0.85, -0.72, 0.85], true)
			_pl([-0.85, -0.45, 0.85, -0.45, 0.85, -0.2, -0.85, -0.2], true)
			_l(0.0, -0.45, 0.0, 0.85)
			_pl([0.0, -0.45, -0.45, -0.88, -0.6, -0.6, 0.0, -0.45])
			_pl([0.0, -0.45, 0.45, -0.88, 0.6, -0.6, 0.0, -0.45])
		"withdraw":  # out of a door, back
			_pl([0.05, -0.55, 0.05, -0.85, 0.85, -0.85, 0.85, 0.85, 0.05, 0.85, 0.05, 0.55])
			_arrow(0.5, 0.0, -0.88, 0.0, 0.5)
		"view_map":  # folded map
			_pl([-0.88, -0.6, -0.3, -0.82, 0.3, -0.6, 0.88, -0.82, 0.88, 0.6, 0.3, 0.82, -0.3, 0.6, -0.88, 0.82], true)
			_l(-0.3, -0.82, -0.3, 0.6, 0.8)
			_l(0.3, -0.6, 0.3, 0.82, 0.8)
		"peace":  # olive branch
			_pl([-0.82, 0.85, -0.2, 0.2, 0.55, -0.6])
			for k in 4:
				var t := 0.22 + 0.2 * k
				var sd := 1.0 if k % 2 == 0 else -1.0
				var q := Vector2(-0.82, 0.85).lerp(Vector2(0.55, -0.6), t)
				var q2 := q + Vector2(0.707, 0.707) * 0.22 * sd + Vector2(0.707, -0.707) * 0.08
				_leaf(q2.x, q2.y, -PI / 4.0 + sd * 0.75, 0.42, 0.14)
			_leaf(0.66, -0.71, -PI / 4.0, 0.42, 0.14)
		"trade", "trade_end", "draw":  # scales
			_l(0.0, -0.8, 0.0, 0.72)
			_l(-0.45, 0.82, 0.45, 0.82)
			_l(-0.72, -0.55, 0.72, -0.55)
			for sx in [-0.62, 0.62]:
				_pl([sx - 0.26, 0.12, sx, -0.55, sx + 0.26, 0.12], false, 0.75)
				_arc(sx, 0.12, 0.3, 0.0, PI, 0.9)
			if icon == "trade_end":
				_slash()
		"alliance":  # two linked rings
			_ring(-0.32, 0.0, 0.52)
			_ring(0.32, 0.0, 0.52)
		"accept":  # tick
			_pl([-0.78, 0.05, -0.25, 0.6, 0.8, -0.6], false, 1.2)
		"decline", "close":  # cross
			_l(-0.62, -0.62, 0.62, 0.62, 1.15)
			_l(-0.62, 0.62, 0.62, -0.62, 1.15)
		"cancel":  # circle with a stroke
			_ring(0.0, 0.0, 0.8)
			_l(-0.56, 0.56, 0.56, -0.56)
		"buy":  # coin going into a hand-held purse: a coin and an arrow in
			_ring(0.32, 0.0, 0.55)
			_ring(0.32, 0.0, 0.25, 0.75)
			_arrow(-0.92, 0.0, -0.32, 0.0, 0.45)
		"farm":  # ear of wheat
			_l(0.0, 0.9, 0.0, -0.45)
			for k in 3:
				var y := 0.35 - 0.38 * k
				_leaf(-0.2, y - 0.1, -PI * 0.72, 0.42, 0.13)
				_leaf(0.2, y - 0.1, -PI * 0.28, 0.42, 0.13)
			_leaf(0.0, -0.68, -PI * 0.5, 0.42, 0.13)
		"market":  # stall with an awning
			_pl([-0.62, -0.85, 0.62, -0.85, 0.88, -0.38, -0.88, -0.38], true)
			for k in 4:
				_arc(-0.66 + 0.44 * k, -0.38, 0.22, 0.0, PI, 0.8)
			_l(-0.72, -0.16, -0.72, 0.85)
			_l(0.72, -0.16, 0.72, 0.85)
			_l(-0.88, 0.32, 0.88, 0.32)
		"barracks":  # crested helmet
			_arc(0.0, 0.18, 0.62, PI, TAU)
			_l(-0.82, 0.18, 0.82, 0.18)
			_pl([-0.55, 0.18, -0.55, 0.78, -0.22, 0.62])
			_pl([0.55, 0.18, 0.55, 0.78, 0.22, 0.62])
			_arc(0.0, -0.1, 0.75, PI * 1.2, PI * 1.8, 1.4)
		"range":  # bow and arrow
			_arc(-0.4, 0.0, 0.9, -1.12, 1.12)
			_l(0.0, -0.81, 0.0, 0.81, 0.6)
			_arrow(-0.62, 0.0, 0.9, 0.0, 0.42)
		"stables":  # horseshoe
			_arc(0.0, 0.0, 0.62, PI * 0.82, PI * 2.18, 1.35)
			_l(-0.6, 0.15, -0.55, 0.85, 1.35)
			_l(0.6, 0.15, 0.55, 0.85, 1.35)
		"workshop":  # gear
			_ring(0.0, 0.0, 0.52)
			_ring(0.0, 0.0, 0.18, 0.8)
			for k in 8:
				var a := TAU * k / 8.0
				_l(cos(a) * 0.55, sin(a) * 0.55, cos(a) * 0.86, sin(a) * 0.86, 1.4)
		"build":  # hammer
			_l(-0.72, 0.78, 0.22, -0.18, 1.1)
			_l(-0.05, -0.65, 0.68, 0.08, 2.0)
		"upgrade":  # up chevrons
			for y in [0.05, -0.5]:
				_pl([-0.62, y + 0.42, 0.0, y - 0.2, 0.62, y + 0.42], false, 1.15)
			_l(-0.62, 0.8, 0.62, 0.8)
		"fire":  # arrow in flight
			_l(-0.72, 0.72, 0.62, -0.62)
			_head(0.7, -0.7, 1.0, -1.0, 0.5)
			for k in 2:
				var bx := -0.68 + 0.2 * k
				var by := 0.68 - 0.2 * k
				_l(bx, by, bx - 0.24, by, 0.8)
				_l(bx, by, bx, by + 0.24, 0.8)
		"hold_fire":  # arrow struck through
			_sub("fire", 0.0, 0.0, 0.82)
			_ring(0.0, 0.0, 0.9, 0.85)
			_l(-0.62, -0.62, 0.62, 0.62, 0.85)
		"skirmish":  # keep the distance: arrows apart
			_l(0.0, -0.7, 0.0, 0.7, 0.85)
			_arrow(-0.22, 0.0, -0.9, 0.0, 0.45)
			_arrow(0.22, 0.0, 0.9, 0.0, 0.45)
		"deploy":  # map pin
			_arc(0.0, -0.3, 0.5, PI * 0.82, PI * 2.18)
			_pl([-0.47, -0.08, 0.0, 0.62, 0.47, -0.08])
			_ring(0.0, -0.3, 0.16, 0.8)
			_l(-0.62, 0.85, 0.62, 0.85, 0.8)
		"wall_up", "wall_down":  # tower and an arrow up / down
			_sub("tower", -0.38, 0.0, 0.9)
			if icon == "wall_up":
				_arrow(0.62, 0.62, 0.62, -0.82, 0.48)
			else:
				_arrow(0.62, -0.62, 0.62, 0.82, 0.48)
		"pick_up", "drop":  # an arrow from / to the ground
			_l(-0.82, 0.85, 0.82, 0.85)
			if icon == "pick_up":
				_arrow(0.0, 0.5, 0.0, -0.88, 0.55)
			else:
				_arrow(0.0, -0.88, 0.0, 0.5, 0.55)
		"victory":  # laurel wreath, open at the top
			for sg in [-1.0, 1.0]:
				_arc(0.0, 0.05, 0.72, PI * (0.5 - 0.08 * sg), PI * (0.5 - 0.86 * sg))
				for k in 4:
					var a: float = PI * (0.5 - sg * (0.16 + 0.2 * k))
					var tg: float = a - sg * PI / 2.0
					for io in [1.0, -1.0]:
						var rr: float = 0.72 + 0.17 * io
						_leaf(cos(a) * rr, 0.05 + sin(a) * rr, tg + sg * 0.5 * io, 0.32, 0.11)
		"defeat":  # broken sword
			_l(-0.78, 0.78, -0.1, 0.1)
			_l(-0.62, 0.22, -0.2, 0.64, 0.9)
			_l(0.1, -0.02, 0.72, -0.64)
			_pl([-0.1, 0.1, -0.02, -0.05, 0.1, -0.02], false, 0.7)
		"killed":  # skull
			_pl([-0.35, 0.55, -0.62, 0.25, -0.65, -0.2, -0.45, -0.6, 0.0, -0.78, 0.45, -0.6, 0.65, -0.2, 0.62, 0.25, 0.35, 0.55], false)
			_pl([-0.35, 0.55, -0.35, 0.85, 0.35, 0.85, 0.35, 0.55])
			_dot(-0.27, -0.08, 0.17)
			_dot(0.27, -0.08, 0.17)
			_l(-0.12, 0.62, -0.12, 0.85, 0.7)
			_l(0.12, 0.62, 0.12, 0.85, 0.7)
		"routed":  # fleeing: chevrons back
			for x in [0.42, -0.2]:
				_pl([x + 0.25, -0.7, x - 0.4, 0.0, x + 0.25, 0.7], false, 1.15)
		"captured":  # chain links
			for k in 2:
				var cx := -0.36 + 0.72 * k
				var cy := 0.3 - 0.6 * k
				var pts: Array = []
				for i in 21:
					var a := TAU * i / 20.0 + PI * 0.25
					var q := Vector2(cos(a) * 0.5, sin(a) * 0.26).rotated(-PI * 0.25)
					pts.append_array([cx + q.x, cy + q.y])
				_pl(pts)
		"ladder":
			_l(-0.42, 0.88, -0.42, -0.88)
			_l(0.42, 0.88, 0.42, -0.88)
			for y in [-0.55, -0.15, 0.25, 0.62]:
				_l(-0.42, y, 0.42, y, 0.8)
		"ram":  # covered ram on wheels
			_pl([-0.75, 0.3, -0.45, -0.45, 0.55, -0.45, 0.85, 0.3], true)
			_l(-0.92, -0.05, 0.62, -0.05, 1.3)
			_fill([0.6, -0.22, 0.92, -0.05, 0.6, 0.12])
			_ring(-0.45, 0.62, 0.22, 0.85)
			_ring(0.5, 0.62, 0.22, 0.85)
		"tower":  # wall tower
			_pl([-0.45, 0.85, -0.45, -0.85, -0.25, -0.85, -0.25, -0.65, -0.08, -0.65, -0.08, -0.85, 0.08, -0.85, 0.08, -0.65,
				0.25, -0.65, 0.25, -0.85, 0.45, -0.85, 0.45, 0.85], true)
			_l(0.0, -0.3, 0.0, -0.05, 0.85)
		"stakes":  # three sharpened stakes leaning toward the enemy, the ground line
			_l(-0.92, 0.82, 0.92, 0.82, 0.8)
			for x in [-0.55, 0.05, 0.65]:
				_l(x - 0.3, 0.82, x + 0.22, -0.72)
				_head(x + 0.22, -0.72, 0.52, -1.54, 0.28)
		"caltrops":  # a caltrop (four points) and two more scattered
			_l(-0.1, 0.05, -0.62, 0.42)
			_l(-0.1, 0.05, 0.42, 0.42)
			_l(-0.1, 0.05, -0.1, -0.6)
			_dot(-0.1, 0.05, 0.14)
			_dot(0.62, -0.62, 0.14)
			_dot(0.7, 0.72, 0.14)
			_dot(-0.75, -0.55, 0.12)
		"palisade":  # pointed wooden posts, a plank across, on a bank
			for x in [-0.6, -0.2, 0.2, 0.6]:
				_pl([x - 0.15, 0.62, x - 0.15, -0.5, x, -0.85, x + 0.15, -0.5, x + 0.15, 0.62], false, 0.8)
			_l(-0.85, 0.05, 0.85, 0.05, 0.8)
			_earc(0.0, 0.9, 0.95, 0.28, PI, TAU, 0.8)
		"rotate":  # a turn arrow round a short line
			_arc(0.0, 0.0, 0.62, PI * 0.2, PI * 1.7)
			_head(0.5, -0.36, 0.9, 1.0, 0.42)
			_l(-0.35, 0.35, 0.35, -0.35, 0.8)
		"siege_tower":  # tall tower on wheels, its bridge up
			_pl([-0.5, 0.6, -0.42, -0.85, 0.42, -0.85, 0.5, 0.6], true)
			_l(-0.46, -0.12, 0.46, -0.12, 0.8)
			_l(0.42, -0.85, 0.85, -0.45, 0.9)
			_ring(-0.32, 0.75, 0.15, 0.8)
			_ring(0.32, 0.75, 0.15, 0.8)
		"mantlet":  # a plank screen on two legs, propped from behind, an arrow stuck in its face
			_pl([-0.55, 0.5, -0.55, -0.85, 0.35, -0.85, 0.35, 0.5], true)
			_l(-0.25, -0.85, -0.25, 0.5, 0.75)
			_l(0.05, -0.85, 0.05, 0.5, 0.75)
			_l(-0.42, 0.5, -0.42, 0.9, 0.85)
			_l(0.22, 0.5, 0.22, 0.9, 0.85)
			_l(0.35, -0.45, 0.88, 0.9, 0.8)
			_l(-0.98, -0.2, -0.55, -0.2, 0.75)
			_l(-0.84, -0.2, -0.98, -0.36, 0.6)
			_l(-0.84, -0.2, -0.98, -0.04, 0.6)
		"gate":  # arch with a portcullis
			_pl([-0.7, 0.85, -0.7, -0.15])
			_arc(0.0, -0.15, 0.7, PI, TAU)
			_l(0.7, -0.15, 0.7, 0.85)
			for x in [-0.35, 0.0, 0.35]:
				_l(x, -0.65 if x == 0.0 else -0.55, x, 0.85, 0.75)
			_l(-0.7, 0.2, 0.7, 0.2, 0.75)
		"ammo":  # quiver, two shafts out of it, one tipped with a flame
			_pl([-0.55, -0.15, -0.3, 0.88, 0.3, 0.88, 0.55, -0.15], true)
			_l(-0.2, -0.15, -0.45, -0.88, 0.85)
			_l(0.2, -0.15, 0.45, -0.88, 0.85)
			_head(-0.48, -0.92, -0.33, -1.0, 0.3)
			_leaf(0.48, -0.78, -PI * 0.5, 0.32, 0.16)
		"forage":  # a tree and a shaft cut from it
			_ring(-0.25, -0.35, 0.5)
			_l(-0.25, 0.15, -0.25, 0.88)
			_l(-0.7, 0.88, 0.2, 0.88, 0.8)
			_arrow(0.35, 0.85, 0.85, -0.2, 0.36)
		"wagon":  # covered wagon on two wheels, a shaft in front
			_arc(-0.1, 0.05, 0.62, PI, TAU)
			_l(-0.72, 0.05, 0.52, 0.05)
			_l(-0.72, 0.05, -0.72, 0.38, 0.8)
			_l(0.52, 0.05, 0.52, 0.38, 0.8)
			_l(-0.72, 0.38, 0.52, 0.38, 0.8)
			_ring(-0.42, 0.66, 0.2, 0.8)
			_ring(0.25, 0.66, 0.2, 0.8)
			_l(0.52, 0.3, 0.92, 0.45, 0.8)
		"general":  # the general's standard: pole, crossbar, a banner hanging from it, a wreath on top
			_l(0.0, -0.6, 0.0, 0.95)
			_l(-0.62, -0.42, 0.62, -0.42)
			_pl([-0.52, -0.42, -0.52, 0.28, 0.0, 0.1, 0.52, 0.28, 0.52, -0.42], false, 0.9)
			_ring(0.0, -0.78, 0.17, 0.8)
		"crown":  # a hero: a crown, three points on a band
			_pl([-0.8, 0.55, -0.8, -0.35, -0.4, 0.05, 0.0, -0.7, 0.4, 0.05, 0.8, -0.35, 0.8, 0.55], true)
			_l(-0.8, 0.85, 0.8, 0.85)
		"dagger":  # an assassin: a blade pointing up, guard and grip
			_pl([0.0, -0.92, 0.2, -0.2, 0.2, 0.28, -0.2, 0.28, -0.2, -0.2], true)
			_l(-0.5, 0.28, 0.5, 0.28)
			_l(0.0, 0.28, 0.0, 0.88, 1.2)
		"scroll":  # a diplomat: a rolled letter with lines of writing and a seal
			_pl([-0.62, -0.78, 0.62, -0.78, 0.62, 0.55, -0.62, 0.55], true)
			_arc(-0.62, -0.5, 0.28, PI * 0.5, PI * 1.5, 0.9)
			_arc(0.62, 0.55, 0.28, -PI * 0.5, PI * 0.5, 0.9)
			_l(-0.3, -0.35, 0.3, -0.35, 0.8)
			_l(-0.3, -0.05, 0.3, -0.05, 0.8)
			_ring(0.0, 0.3, 0.14, 0.8)
		"kill_beast":  # an elephant's head, the driver's chisel driven in at the top
			_ring(-0.12, 0.0, 0.42)
			_arc(-0.72, 0.0, 0.3, PI * 0.5, PI * 1.5, 0.85)
			_arc(0.48, 0.0, 0.3, -PI * 0.5, PI * 0.5, 0.85)
			_pl([-0.12, 0.4, -0.12, 0.72, 0.1, 0.92], false, 0.9)
			_l(0.55, -0.92, 0.12, -0.38, 0.9)
			_l(0.42, -0.95, 0.72, -0.72, 1.2)
		"release":  # a dog's head, the leash cut loose and an arrow off to the right
			_arc(-0.45, -0.1, 0.36, PI * 0.6, PI * 2.1, 0.9)
			_l(-0.13, -0.28, 0.35, -0.08, 0.9)
			_l(0.35, -0.08, 0.25, 0.12, 0.9)
			_l(0.25, 0.12, -0.15, 0.15, 0.9)
			_fill([-0.62, -0.4, -0.38, -0.85, -0.3, -0.38])
			_l(-0.6, 0.3, -0.9, 0.75, 0.75)
			_arrow(0.1, 0.62, 0.92, 0.62, 0.35)
		"copy":
			_pl([-0.82, -0.45, -0.82, 0.85, 0.35, 0.85, 0.35, -0.45], true)
			_pl([-0.4, -0.45, -0.4, -0.85, 0.82, -0.85, 0.82, 0.45, 0.35, 0.45])
		"export":
			_pl([-0.3, -0.35, -0.75, -0.35, -0.75, 0.85, 0.75, 0.85, 0.75, -0.35, 0.3, -0.35])
			_arrow(0.0, 0.4, 0.0, -0.9, 0.5)
		"plus":
			_l(0.0, -0.7, 0.0, 0.7, 1.15)
			_l(-0.7, 0.0, 0.7, 0.0, 1.15)
		"minus":
			_l(-0.7, 0.0, 0.7, 0.0, 1.15)
		"tr_siege":  # trait: siege engines (the covered ram)
			_sub("ram", 0.0, 0.0, 1.0)
		"tr_shock":  # trait: the charge (a lightning bolt)
			_fill([0.25, -0.95, -0.6, 0.15, -0.08, 0.15, -0.3, 0.95, 0.6, -0.2, 0.08, -0.2])
		"tr_anti_cav":  # trait: braced spears against a charge
			_l(-0.95, 0.85, 0.95, 0.85, 0.8)
			_arrow(-0.85, 0.7, 0.75, -0.25, 0.45)
			_arrow(-0.85, 0.15, 0.75, -0.8, 0.45)
		"tr_fearsome":  # trait: fear (a warning triangle)
			_pl([0.0, -0.85, 0.9, 0.7, -0.9, 0.7], true)
			_l(0.0, -0.25, 0.0, 0.25, 1.1)
			_dot(0.0, 0.5, 0.09)
		"tr_ap":  # trait: armour piercing (an arrow through a plate)
			_l(0.15, -0.85, 0.15, 0.85, 1.7)
			_arrow(-0.95, 0.0, 0.95, 0.0, 0.5)
		"tr_long_range":  # trait: long range (a dashed flight to a target)
			_ring(0.52, 0.0, 0.38)
			_dot(0.52, 0.0, 0.1)
			_l(-0.92, 0.0, -0.62, 0.0)
			_l(-0.4, 0.0, -0.1, 0.0)
			_head(0.0, 0.0, 1.0, 0.0, 0.36)
		"tr_skirmish":  # trait: skirmisher (keeps its distance)
			_sub("skirmish", 0.0, 0.0, 1.0)
		"tr_fire":  # trait: fire ammunition (a flame)
			_pl([0.05, -0.95, 0.5, -0.25, 0.6, 0.3, 0.3, 0.8, -0.1, 0.9, -0.5, 0.65, -0.6, 0.15, -0.3, -0.2, -0.15, -0.5], true)
			_pl([0.05, 0.25, 0.22, 0.52, 0.0, 0.72, -0.2, 0.55], true, 0.8)
		"tr_fast":  # trait: fast (double chevron)
			_pl([-0.7, -0.7, 0.0, 0.0, -0.7, 0.7], false, 1.1)
			_pl([0.05, -0.7, 0.75, 0.0, 0.05, 0.7], false, 1.1)
		"tr_beast", "cl_beast":  # a paw
			_dot(0.0, 0.38, 0.4)
			for q in [[-0.68, -0.05], [-0.25, -0.55], [0.25, -0.55], [0.68, -0.05]]:
				_dot(q[0], q[1], 0.19)
		"cl_foot":  # a soldier on foot
			_ring(0.0, -0.62, 0.24)
			_l(0.0, -0.32, 0.0, 0.22)
			_l(-0.5, -0.1, 0.5, -0.1)
			_l(0.0, 0.22, -0.4, 0.88)
			_l(0.0, 0.22, 0.4, 0.88)
		"cl_spear":  # a spear
			_l(-0.7, 0.9, 0.45, -0.5, 1.0)
			_head(0.75, -0.85, 0.8, -1.0, 0.55)
			_l(-0.2, 0.15, 0.2, 0.45, 0.8)
		"cl_horse":  # a horse's head
			_pl([-0.7, 0.9, -0.5, 0.0, -0.2, -0.65, 0.3, -0.9, 0.65, -0.2, 0.9, 0.25, 0.55, 0.45, 0.25, 0.15, 0.0, 0.3, 0.0, 0.9])
			_l(-0.2, -0.65, -0.35, -0.95, 0.9)
			_dot(0.38, -0.2, 0.07)
		"cl_missile":  # a bow with an arrow
			_arc(-0.35, 0.0, 0.9, -1.15, 1.15)
			_l(-0.35 + cos(1.15) * 0.9, sin(1.15) * 0.9, -0.35 + cos(1.15) * 0.9, -sin(1.15) * 0.9, 0.6)
			_arrow(-0.45, 0.0, 0.95, 0.0, 0.45)
		"cl_engine":  # a cog
			_ring(0.0, 0.0, 0.48)
			for k in 8:
				var a := TAU * k / 8.0
				_l(cos(a) * 0.62, sin(a) * 0.62, cos(a) * 0.9, sin(a) * 0.9, 1.5)
			_dot(0.0, 0.0, 0.12)
		_:
			_ring(0.0, 0.0, 0.5)
