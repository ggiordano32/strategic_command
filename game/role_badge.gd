extends RefCounted
## Role badges (docs/design/battle_sim.md "Roles and abilities", step 1): a tiny glyph per
## role on a tinted tile, drawn with canvas primitives like unit_icons.gd so it stays crisp
## at 12 px on a phone. Used by the unit card, the unit book, the deployment and custom
## battle lists and the Keys page. View only.

const UT := preload("res://sim/unit_types.gd")


static func colour(role: String) -> Color:
	return Color.html(str(UT.ROLES.get(role, {}).get("colour", "888888")))


## Tooltip body of a role: its two-line "plays as".
static func plays(role: String) -> String:
	return str(UT.ROLES.get(role, {}).get("plays", ""))


## A tile of the role's colour (rect) with its glyph in white.
static func draw_badge(ci: CanvasItem, role: String, rect: Rect2, dim: bool = false) -> void:
	var info: Dictionary = UT.ROLES.get(role, {})
	if info.is_empty():
		return
	var col := colour(role)
	if dim:
		col = col.darkened(0.5)
	ci.draw_rect(rect, Color(col.darkened(0.45), 0.95))
	ci.draw_rect(rect, col, false, 1.0)
	var s := minf(rect.size.x, rect.size.y) * 0.42
	draw_glyph(ci, str(info["glyph"]), rect.get_center(), s, Color(1, 1, 1, 0.55 if dim else 0.95))


## The glyph alone, in a circle of radius s around c.
static func draw_glyph(ci: CanvasItem, glyph: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(s * 0.2, 1.0)
	match glyph:
		"line":  # a close rank: three bars
			for k in 3:
				ci.draw_line(c + Vector2(-0.9, -0.62 + 0.62 * k) * s, c + Vector2(0.9, -0.62 + 0.62 * k) * s, col, w * 1.1, true)
		"scatter":  # a loose scatter of men
			for p in [Vector2(-0.65, -0.55), Vector2(0.3, -0.7), Vector2(0.75, 0.05), Vector2(-0.2, 0.0), Vector2(-0.7, 0.65), Vector2(0.35, 0.7)]:
				ci.draw_circle(c + p * s, maxf(s * 0.2, 0.9), col)
		"bow":
			ci.draw_arc(c + Vector2(-0.4, 0) * s, 0.95 * s, -1.1, 1.1, 10, col, w, true)
			ci.draw_line(c + Vector2(0.0, -0.8) * s, c + Vector2(0.0, 0.8) * s, col, w * 0.6, true)
			ci.draw_line(c + Vector2(-0.6, 0) * s, c + Vector2(0.9, 0) * s, col, w * 0.8, true)
		"blade":  # a sword, point up, with a cross guard
			ci.draw_line(c + Vector2(0, 0.7) * s, c + Vector2(0, -0.95) * s, col, w * 1.2, true)
			ci.draw_line(c + Vector2(-0.55, 0.3) * s, c + Vector2(0.55, 0.3) * s, col, w, true)
		"horse", "horse_dot":  # a horseshoe; the light horse has a dot in it
			ci.draw_arc(c + Vector2(0, 0.1) * s, 0.7 * s, PI * 0.85, PI * 2.15, 10, col, w * 1.3, true)
			ci.draw_line(c + Vector2(-0.68, 0.25) * s, c + Vector2(-0.62, 0.85) * s, col, w * 1.3, true)
			ci.draw_line(c + Vector2(0.68, 0.25) * s, c + Vector2(0.62, 0.85) * s, col, w * 1.3, true)
			if glyph == "horse_dot":
				ci.draw_circle(c + Vector2(0, 0.15) * s, maxf(s * 0.2, 0.9), col)
		"gun", "gun_big":  # a barrel on a wheel; the siege gun a fatter barrel and a ball
			var th := 0.34 if glyph == "gun" else 0.52
			ci.draw_line(c + Vector2(-0.55, -0.25) * s, c + Vector2(0.95, -0.55) * s, col, w * (th * 4.0), true)
			ci.draw_arc(c + Vector2(-0.3, 0.45) * s, 0.45 * s, 0, TAU, 10, col, w, true)
			if glyph == "gun_big":
				ci.draw_circle(c + Vector2(0.85, 0.5) * s, maxf(s * 0.22, 1.0), col)
		"flag":  # a pole with a pennant
			ci.draw_line(c + Vector2(-0.5, 0.95) * s, c + Vector2(-0.5, -0.95) * s, col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.5, -0.95) * s, c + Vector2(0.85, -0.5) * s,
				c + Vector2(-0.5, -0.05) * s]), col)
		"beast":  # a humped back and a trunk
			ci.draw_arc(c + Vector2(-0.1, 0.35) * s, 0.8 * s, PI, TAU, 10, col, w * 1.2, true)
			ci.draw_line(c + Vector2(-0.9, 0.35) * s, c + Vector2(-0.9, 0.9) * s, col, w, true)
			ci.draw_line(c + Vector2(0.7, 0.35) * s, c + Vector2(0.7, 0.9) * s, col, w, true)
			ci.draw_line(c + Vector2(0.7, 0.35) * s, c + Vector2(1.0, 0.0) * s, col, w, true)
