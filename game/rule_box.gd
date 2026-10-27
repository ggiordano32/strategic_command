extends StyleBox
## The table's chrome as one StyleBox (docs/design/ui.md "HUD chrome in the table's language"): the dark fill the panels,
## bars and plate buttons always had, an inked double rule (the 1 px edge line in `edge`, a second lighter line 2 px
## inside it) and, on panels and bars, small diagonal corner ticks. A bar can be a wood band: a subtle vertical
## wood-grain gradient (drawn rows, no texture) with a thin brass rule along its bottom edge. Quality Low draws the rules
## only (no gradient, no grain). The content margins are the ones given, so swapping a StyleBoxFlat for this changes no
## layout metric: every line is drawn inside the rect. View only.

const Quality := preload("res://game/quality.gd")

const BRASS := Color(0.69, 0.54, 0.25)

var bg := Color(0.1, 0.12, 0.11, 0.96)
var edge := Color(0.69, 0.54, 0.25, 0.6)   # the outer line (a plate's state colour: dim, gold when hot)
var radius := 5
var marks := false        # the four corner ticks
var wood := false         # the wood band
var brass_bottom := false  # the brass rule along the bottom edge
# Mirrors of the StyleBoxFlat fields tests and callers read.
var border_width_left := 1
var border_width_bottom := 0
var _base := StyleBoxFlat.new()


func setup(p_bg: Color, margin: float, p_radius: int, p_edge: Color) -> StyleBox:
	bg = p_bg
	radius = p_radius
	edge = p_edge
	set_content_margin_all(margin)
	return self


func _draw(ci: RID, r: Rect2) -> void:
	if wood:
		_draw_wood(ci, r)
	else:
		_base.bg_color = bg
		_base.set_corner_radius_all(radius)
		_base.draw(ci, r)
	# The outer line, then the lighter line 2 px inside it.
	RenderingServer.canvas_item_add_polyline(ci, _ring(r.grow(-0.5), radius), PackedColorArray([edge]), 1.0)
	var inner := Color(edge.lightened(0.3), minf(edge.a * 0.8, 1.0))
	if r.size.x > 12.0 and r.size.y > 12.0:
		RenderingServer.canvas_item_add_polyline(ci, _ring(r.grow(-2.5), maxi(radius - 2, 0)), PackedColorArray([inner]), 1.0)
	if marks and r.size.x > 24.0 and r.size.y > 24.0:
		var t := Color(edge.lightened(0.4), minf(edge.a + 0.2, 1.0))
		for c in 4:
			var sx := 1.0 if c % 2 == 0 else -1.0
			var sy := 1.0 if c < 2 else -1.0
			var o := Vector2(r.position.x + 2.5 if sx > 0.0 else r.end.x - 2.5, r.position.y + 2.5 if sy > 0.0 else r.end.y - 2.5)
			RenderingServer.canvas_item_add_line(ci, o, o + Vector2(sx, sy) * 4.5, t, 1.0)
	if brass_bottom:
		RenderingServer.canvas_item_add_rect(ci, Rect2(r.position.x, r.end.y - 1.0, r.size.x, 1.0), Color(BRASS.lightened(0.28), 1.0))


func _draw_wood(ci: RID, r: Rect2) -> void:
	RenderingServer.canvas_item_add_rect(ci, r, bg)
	if Quality.is_low():
		return
	# Horizontal grain: rows of 2 to 3 px, each cut into soft streaks along the bar, lighter or darker than the fill by a
	# deterministic hash (no randomness, so the band looks the same on every redraw). The lighter and darker streaks
	# balance, so the band's mean luminance stays the dark fill's and the bar text keeps its contrast.
	var y := r.position.y
	var i := 0
	while y < r.end.y:
		var h := minf(2.0 + float((i * 5 + 1) % 2), r.end.y - y)
		var x := r.position.x - float((i * 37) % 53)
		var j := 0
		while x < r.end.x:
			var hv := (i * 7919 + j * 104729 + 13) % 97
			var seg := 40.0 + float(hv % 9) * 22.0
			var k := float(hv) / 96.0 - 0.5          # -0.5 .. 0.5
			var x0 := maxf(x, r.position.x)
			var x1 := minf(x + seg, r.end.x)
			if x1 > x0 and absf(k) > 0.08:
				var c := Color(0.60, 0.37, 0.18, k * 0.5) if k > 0.0 else Color(0.0, 0.0, 0.0, -k * 0.5)
				RenderingServer.canvas_item_add_rect(ci, Rect2(x0, y, x1 - x0, h), c)
			x += seg
			j += 1
		y += h
		i += 1


## A rounded (or square) rectangle outline as a closed polyline.
static func _ring(o: Rect2, rad: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if rad <= 0:
		pts.append_array([o.position, Vector2(o.end.x, o.position.y), o.end, Vector2(o.position.x, o.end.y), o.position])
		return pts
	var k := float(rad)
	var centres := [Vector2(o.end.x - k, o.position.y + k), Vector2(o.end.x - k, o.end.y - k), Vector2(o.position.x + k, o.end.y - k), Vector2(o.position.x + k, o.position.y + k)]
	for c in 4:
		for s in 4:
			var a := (-90.0 + c * 90.0 + s * 30.0) * PI / 180.0
			pts.append((centres[c] as Vector2) + Vector2(cos(a), sin(a)) * k)
	pts.append(pts[0])
	return pts
