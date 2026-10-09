extends RefCounted
## Unit type symbols, drawn with a handful of canvas primitives (no textures)
## so they stay crisp at any size: a disc in the side colour with a white
## glyph. Used by the field markers (overlay.gd), the unit cards and the unit
## book. Icon ids come from the "icon" field of the unit type data.
##   0 heavy swords: tall shield and sword    1 light infantry: dagger, buckler
##   2 spear: shaft with leaf tip             3 pike: three long levelled pikes
##   4 bow: bow, string, arrow                5 javelin: two short shafts
##   6 cavalry: horseshoe                 7 bolt thrower: bow on a stock, bolt
##   8 stone thrower: frame, arm and stone 9 ammunition wagon: covered cart
##   10 camel: humped back, long neck       11 elephant: head, ears, trunk, tusks
##   12 camel archers: the camel and an arrow
##   13 light horse: horseshoe and a javelin  14 slingers: the sling's cords, a stone
##   15 general: his standard (pole, crossbar, banner, a wreath on top)
##   16 war dogs (handlers): a dog's head and a leash   17 the released pack: a running dog
## Symbol ids above 99 carry a tier mark (see icon_of).

const UT := preload("res://sim/unit_types.gd")

const SIDE_COLORS := [Color(0.35, 0.6, 1.0), Color(1.0, 0.36, 0.28)]
const ROUT_COLOR := Color(1.0, 0.9, 0.3)


## Symbol id of a unit type: the glyph ("icon" field) plus 100 per tier above
## the first, so every marker drawn from it carries the tier mark.
static func icon_of(ty: int) -> int:
	return UT.stat(ty, "icon") + 100 * (UT.tier_of(ty) - 1)


## Disc of radius r in `fill` with a dark rim and the glyph for `icon`;
## tiers 2 and 3 get one or two gold chevrons at the bottom of the disc.
static func draw_marker(ci: CanvasItem, icon: int, c: Vector2, r: float, fill: Color,
		glyph: Color = Color(1, 1, 1, 0.97)) -> void:
	ci.draw_circle(c, r, fill)
	ci.draw_arc(c, r, 0, TAU, 20, Color(0, 0, 0, 0.75), maxf(r * 0.11, 1.0), true)
	draw_glyph(ci, icon % 100, c, r * 0.72, glyph)
	var tier := icon / 100 + 1
	if tier > 1:
		draw_tier(ci, tier, c, r)


## Tier mark: gold chevrons below the disc's centre (one for tier 2, two for
## tier 3), with a dark edge so they read on any side colour.
static func draw_tier(ci: CanvasItem, tier: int, c: Vector2, r: float) -> void:
	var gold := Color(1.0, 0.82, 0.25)
	var w := maxf(r * 0.2, 1.4)
	for k in tier - 1:
		var y := c.y + r * (0.98 - 0.36 * k)
		var pts := PackedVector2Array([Vector2(c.x - r * 0.5, y - r * 0.3), Vector2(c.x, y),
			Vector2(c.x + r * 0.5, y - r * 0.3)])
		ci.draw_polyline(pts, Color(0, 0, 0, 0.85), w + 2.0, true)
		ci.draw_polyline(pts, gold, w, true)


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
		9:  # ammunition wagon: covered cart on two wheels, a shaft in front
			ci.draw_arc(c + Vector2(-0.12, 0.05) * s, 0.62 * s, PI, TAU, 12, col, w, true)
			ci.draw_line(c + Vector2(-0.74, 0.05) * s, c + Vector2(0.5, 0.05) * s, col, w, true)
			ci.draw_line(c + Vector2(-0.74, 0.4) * s, c + Vector2(0.5, 0.4) * s, col, w, true)
			ci.draw_arc(c + Vector2(-0.42, 0.68) * s, 0.22 * s, 0, TAU, 10, col, w * 0.8, true)
			ci.draw_arc(c + Vector2(0.22, 0.68) * s, 0.22 * s, 0, TAU, 10, col, w * 0.8, true)
			ci.draw_line(c + Vector2(0.5, 0.3) * s, c + Vector2(0.95, 0.45) * s, col, w * 0.8, true)
		10, 12:  # camel from the side: legs, a humped back, a long neck up to the head
			ci.draw_arc(c + Vector2(-0.2, 0.1) * s, 0.45 * s, PI * 1.05, PI * 1.95, 10, col, w * 1.2, true)
			ci.draw_line(c + Vector2(-0.62, 0.15) * s, c + Vector2(0.25, 0.15) * s, col, w, true)
			ci.draw_line(c + Vector2(-0.5, 0.15) * s, c + Vector2(-0.55, 0.85) * s, col, w * 0.8, true)
			ci.draw_line(c + Vector2(0.15, 0.15) * s, c + Vector2(0.2, 0.85) * s, col, w * 0.8, true)
			ci.draw_line(c + Vector2(0.25, 0.15) * s, c + Vector2(0.55, -0.55) * s, col, w, true)
			ci.draw_line(c + Vector2(0.55, -0.55) * s, c + Vector2(0.85, -0.5) * s, col, w * 1.2, true)
			if icon == 12:
				ci.draw_line(c + Vector2(-0.9, -0.75) * s, c + Vector2(0.1, -0.75) * s, col, w * 0.7, true)
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.3, -0.75) * s,
					c + Vector2(0.05, -0.92) * s, c + Vector2(0.05, -0.58) * s]), col)
		13:  # light horse: a smaller horseshoe and a javelin over it
			ci.draw_arc(c + Vector2(-0.1, 0.3) * s, 0.5 * s, PI * 0.85, PI * 2.15, 12, col, w * 1.2, true)
			ci.draw_line(c + Vector2(-0.58, 0.42) * s, c + Vector2(-0.54, 0.9) * s, col, w * 1.2, true)
			ci.draw_line(c + Vector2(0.38, 0.42) * s, c + Vector2(0.34, 0.9) * s, col, w * 1.2, true)
			ci.draw_line(c + Vector2(-0.85, -0.1) * s, c + Vector2(0.55, -0.75) * s, col, w * 0.8, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.92, -0.92) * s,
				c + Vector2(0.48, -0.88) * s, c + Vector2(0.64, -0.6) * s]), col)
		14:  # sling: two cords from the hand down to the pouch, a stone flying off
			ci.draw_line(c + Vector2(-0.55, -0.8) * s, c + Vector2(-0.35, 0.55) * s, col, w * 0.8, true)
			ci.draw_line(c + Vector2(-0.45, -0.8) * s, c + Vector2(0.15, 0.55) * s, col, w * 0.8, true)
			ci.draw_arc(c + Vector2(-0.1, 0.6) * s, 0.28 * s, 0, PI, 8, col, w * 1.1, true)
			ci.draw_circle(c + Vector2(0.6, -0.35) * s, 0.22 * s, col)
		15:  # the general's standard: pole, crossbar, a banner hanging from it, a wreath on top
			ci.draw_line(c + Vector2(0, -0.6) * s, c + Vector2(0, 0.95) * s, col, w, true)
			ci.draw_line(c + Vector2(-0.62, -0.42) * s, c + Vector2(0.62, -0.42) * s, col, w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.52, -0.42) * s, c + Vector2(-0.52, 0.28) * s,
				c + Vector2(0, 0.1) * s, c + Vector2(0.52, 0.28) * s, c + Vector2(0.52, -0.42) * s]), col, w * 0.9, true)
			ci.draw_arc(c + Vector2(0, -0.78) * s, 0.17 * s, 0, TAU, 10, col, w * 0.8, true)
		16, 17:  # a dog's head in profile: skull, muzzle, a pricked ear, the jaw
			ci.draw_arc(c + Vector2(-0.15, -0.1) * s, 0.42 * s, PI * 0.6, PI * 2.1, 12, col, w, true)
			ci.draw_line(c + Vector2(0.22, -0.3) * s, c + Vector2(0.88, -0.05) * s, col, w, true)
			ci.draw_line(c + Vector2(0.88, -0.05) * s, c + Vector2(0.75, 0.18) * s, col, w, true)
			ci.draw_line(c + Vector2(0.75, 0.18) * s, c + Vector2(0.2, 0.2) * s, col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.35, -0.45) * s,
				c + Vector2(-0.05, -0.98) * s, c + Vector2(0.05, -0.42) * s]), col)
			if icon == 16:  # the handlers: a leash from the collar
				ci.draw_polyline(PackedVector2Array([c + Vector2(-0.3, 0.3) * s, c + Vector2(-0.55, 0.65) * s,
					c + Vector2(-0.95, 0.75) * s]), col, w * 0.7, true)
				ci.draw_line(c + Vector2(-0.5, 0.25) * s, c + Vector2(-0.1, 0.38) * s, col, w * 1.2, true)
			else:  # the pack loose: speed lines
				for k in 2:
					ci.draw_line(c + Vector2(-0.95, 0.35 + 0.25 * k) * s, c + Vector2(-0.45, 0.35 + 0.25 * k) * s,
						col, w * 0.7, true)
		11:  # elephant's head from the front: ears, trunk curling down, tusks
			ci.draw_arc(c + Vector2(0, -0.2) * s, 0.38 * s, 0, TAU, 14, col, w, true)
			ci.draw_arc(c + Vector2(-0.6, -0.2) * s, 0.3 * s, PI * 0.5, PI * 1.5, 10, col, w, true)
			ci.draw_arc(c + Vector2(0.6, -0.2) * s, 0.3 * s, -PI * 0.5, PI * 0.5, 10, col, w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, 0.15) * s, c + Vector2(0, 0.65) * s,
				c + Vector2(0.2, 0.9) * s]), col, w * 1.1, true)
			ci.draw_line(c + Vector2(-0.22, 0.1) * s, c + Vector2(-0.45, 0.55) * s, col, w * 0.7, true)
			ci.draw_line(c + Vector2(0.22, 0.1) * s, c + Vector2(0.45, 0.55) * s, col, w * 0.7, true)
		_:
			ci.draw_circle(c, s * 0.3, col)

