extends RefCounted
## Unit type symbols, drawn with a handful of canvas primitives (no textures)
## so they stay crisp at any size: a disc in the side colour with a white
## glyph. Used by the field markers (overlay.gd), the unit cards and the unit
## book. Icon ids come from the "icon" field of the unit type data.
##   0 heavy swords: tall shield and sword    1 light infantry: dagger, buckler
##   2 spear: shaft with leaf tip             3 pike: three long levelled pikes
##   4 bow: bow, string, arrow                5 javelin: two short shafts
##   6 cavalry: horseshoe                 7 bolt thrower: bow on a stock, bolt
##   8 stone thrower: frame, arm and stone

const UT := preload("res://sim/unit_types.gd")

const SIDE_COLORS := [Color(0.35, 0.6, 1.0), Color(1.0, 0.36, 0.28)]
const ROUT_COLOR := Color(1.0, 0.9, 0.3)


static func icon_of(ty: int) -> int:
	return UT.stat(ty, "icon")


## Disc of radius r in `fill` with a dark rim and the glyph for `icon`.
static func draw_marker(ci: CanvasItem, icon: int, c: Vector2, r: float, fill: Color,
		glyph: Color = Color(1, 1, 1, 0.97)) -> void:
	ci.draw_circle(c, r, fill)
	ci.draw_arc(c, r, 0, TAU, 20, Color(0, 0, 0, 0.75), maxf(r * 0.11, 1.0), true)
	draw_glyph(ci, icon, c, r * 0.72, glyph)


## The glyph alone, fitting in a circle of radius s around c.
static func draw_glyph(ci: CanvasItem, icon: int, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(s * 0.17, 1.0)
	match icon:
		0:  # tall shield, sword across it
			var sh := PackedVector2Array([c + Vector2(-0.55, -0.75) * s, c + Vector2(0.15, -0.75) * s,
				c + Vector2(0.15, 0.75) * s, c + Vector2(-0.55, 0.75) * s, c + Vector2(-0.55, -0.75) * s])
			ci.draw_polyline(sh, col, w, true)
			ci.draw_line(c + Vector2(0.55, -0.9) * s, c + Vector2(0.55, 0.65) * s, col, w, true)
			ci.draw_line(c + Vector2(0.3, 0.42) * s, c + Vector2(0.8, 0.42) * s, col, w, true)
		1:  # small round buckler and a short blade
			ci.draw_arc(c + Vector2(-0.38, 0.25) * s, 0.42 * s, 0, TAU, 14, col, w, true)
			ci.draw_line(c + Vector2(-0.1, -0.1) * s, c + Vector2(0.75, -0.85) * s, col, w, true)
			ci.draw_line(c + Vector2(0.05, -0.45) * s, c + Vector2(0.35, -0.15) * s, col, w, true)
		2:  # one spear with a leaf-shaped tip
			ci.draw_line(c + Vector2(0, 0.95) * s, c + Vector2(0, -0.35) * s, col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.98) * s,
				c + Vector2(0.28, -0.4) * s, c + Vector2(0, -0.25) * s, c + Vector2(-0.28, -0.4) * s]), col)
		3:  # three long pikes, levelled diagonally
			for k in 3:
				var o := Vector2(-0.4 + 0.4 * k, 0.0) * s
				ci.draw_line(c + o + Vector2(-0.35, 0.95) * s, c + o + Vector2(0.35, -0.75) * s, col, w * 0.85, true)
				ci.draw_colored_polygon(PackedVector2Array([c + o + Vector2(0.45, -0.98) * s,
					c + o + Vector2(0.48, -0.66) * s, c + o + Vector2(0.24, -0.72) * s]), col)
		4:  # bow, string and an arrow
			ci.draw_arc(c + Vector2(-0.35, 0) * s, 0.95 * s, -1.15, 1.15, 12, col, w, true)
			ci.draw_line(c + Vector2(0.03, -0.87) * s, c + Vector2(0.03, 0.87) * s, col, w * 0.6, true)
			ci.draw_line(c + Vector2(-0.6, 0) * s, c + Vector2(0.85, 0) * s, col, w * 0.8, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.98, 0) * s,
				c + Vector2(0.68, -0.2) * s, c + Vector2(0.68, 0.2) * s]), col)
		5:  # two short javelins, crossed
			for sg in [-1.0, 1.0]:
				var a := c + Vector2(-0.7 * sg, 0.75) * s
				var b := c + Vector2(0.55 * sg, -0.6) * s
				ci.draw_line(a, b, col, w * 0.85, true)
				var d := (b - a).normalized()
				var n := Vector2(-d.y, d.x)
				ci.draw_colored_polygon(PackedVector2Array([b + d * 0.35 * s,
					b + n * 0.17 * s, b - n * 0.17 * s]), col)
		6:  # horseshoe with nail holes
			ci.draw_arc(c + Vector2(0, 0.1) * s, 0.68 * s, PI * 0.85, PI * 2.15, 14, col, w * 1.35, true)
			ci.draw_line(c + Vector2(-0.66, 0.25) * s, c + Vector2(-0.6, 0.85) * s, col, w * 1.35, true)
			ci.draw_line(c + Vector2(0.66, 0.25) * s, c + Vector2(0.6, 0.85) * s, col, w * 1.35, true)
		7:  # bolt thrower: a wide bow on a stock, the bolt laid on it
			ci.draw_arc(c + Vector2(0, 0.55) * s, 0.95 * s, -PI * 0.86, -PI * 0.14, 12, col, w, true)
			ci.draw_line(c + Vector2(0, -0.05) * s, c + Vector2(0, 0.95) * s, col, w * 1.3, true)
			ci.draw_line(c + Vector2(-0.82, 0.08) * s, c + Vector2(0, 0.45) * s, col, w * 0.55, true)
			ci.draw_line(c + Vector2(0.82, 0.08) * s, c + Vector2(0, 0.45) * s, col, w * 0.55, true)
			ci.draw_line(c + Vector2(0, 0.6) * s, c + Vector2(0, -0.7) * s, col, w * 0.8, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.98) * s,
				c + Vector2(0.2, -0.66) * s, c + Vector2(-0.2, -0.66) * s]), col)
		8:  # stone thrower: low frame, arm raised, stone in the sling
			ci.draw_line(c + Vector2(-0.85, 0.7) * s, c + Vector2(0.85, 0.7) * s, col, w * 1.2, true)
			ci.draw_line(c + Vector2(0.45, 0.7) * s, c + Vector2(0.3, 0.15) * s, col, w, true)
			ci.draw_line(c + Vector2(-0.5, 0.7) * s, c + Vector2(0.3, 0.15) * s, col, w * 0.8, true)
			ci.draw_line(c + Vector2(-0.25, 0.62) * s, c + Vector2(0.45, -0.55) * s, col, w * 1.1, true)
			ci.draw_circle(c + Vector2(0.55, -0.72) * s, 0.24 * s, col)
		_:
			ci.draw_circle(c, s * 0.3, col)

