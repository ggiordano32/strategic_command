extends Node2D
## The diorama look's board (view only): the battlefield is a sculpted tabletop board, a bevelled edge round
## the field with a soft shadow on a wooden table that fills the screen beyond it. Under the ground
## (z -3). Off in the painterly look and with --no-board.

const MARGIN := 900.0      # metres of table beyond the field
const BEVEL := 4.0         # metres, the board edge's width
const LIGHT_EDGE := Color(0.80, 0.70, 0.52)
const DARK_EDGE := Color(0.34, 0.25, 0.16)
const TABLE := Color(0.20, 0.145, 0.10)

var fw := 0.0
var fh := 0.0
var k := 10.0


func setup(sim, px_per_m: float) -> void:
	k = px_per_m
	fw = sim.field_w / 1024.0 * k
	fh = sim.field_h / 1024.0 * k
	z_index = -3
	queue_redraw()


func _draw() -> void:
	var m := MARGIN * k
	draw_rect(Rect2(-m, -m, fw + 2.0 * m, fh + 2.0 * m), TABLE)
	# Wood grain: long faint strokes along x.
	var y := -m
	var i := 0
	while y < fh + m:
		var h := float((i * 7919) % 97) / 97.0
		draw_line(Vector2(-m, y), Vector2(fw + m, y + (h - 0.5) * 6.0), Color(0, 0, 0, 0.06 + 0.06 * h), 1.0 + h * 2.0)
		y += (14.0 + h * 40.0)
		i += 1
	var b := BEVEL * k
	# Soft shadow on the table, to the south-east.
	for s in 6:
		var d := b * (0.3 + 0.35 * s)
		draw_rect(Rect2(b * 0.5, b * 0.5, fw + d, fh + d), Color(0, 0, 0, 0.07))
	# The bevel: four trapezoids lit from the north-west.
	var o := Rect2(-b, -b, fw + 2.0 * b, fh + 2.0 * b)
	var tl := o.position
	var ntr := Vector2(o.end.x, o.position.y)
	var br := o.end
	var bl := Vector2(o.position.x, o.end.y)
	var itl := Vector2.ZERO
	var itr := Vector2(fw, 0)
	var ibr := Vector2(fw, fh)
	var ibl := Vector2(0, fh)
	draw_colored_polygon(PackedVector2Array([tl, ntr, itr, itl]), LIGHT_EDGE.lerp(DARK_EDGE, 0.2))   # north
	draw_colored_polygon(PackedVector2Array([tl, itl, ibl, bl]), LIGHT_EDGE)                           # west
	draw_colored_polygon(PackedVector2Array([bl, ibl, ibr, br]), DARK_EDGE.lerp(LIGHT_EDGE, 0.25))     # south
	draw_colored_polygon(PackedVector2Array([ntr, br, ibr, itr]), DARK_EDGE)                            # east
	draw_rect(o, Color(0.05, 0.03, 0.02, 0.6), false, maxf(k * 0.2, 1.0))
	draw_rect(Rect2(Vector2.ZERO, Vector2(fw, fh)), Color(0.05, 0.03, 0.02, 0.5), false, maxf(k * 0.25, 1.0))
