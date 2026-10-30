extends Control
## The die on an auto-resolve (tabletop pass 5, docs/design/art_pipeline.md "Pass 5, furniture and motion"; view only): a wooden die
## tumbles across the card for ROLL_SEC and settles showing the face the RULES gave (a laurel for a victory, a broken shield for
## a defeat, two crossed swords for a draw: the game's own icons, game/ui_icons.gd), holds a moment, then `settled` fires and the
## screen shows the result cards. The tumble is only a roll: its faces are a fixed order that ends on the result, nothing in it
## is random and nothing decides anything. A tap or a key skips to the settled face.
## Drawn flat in 2D: each flip the front face squashes down while the next one comes into view above it, the die travelling
## across the lane with a decaying bounce and a soft shadow on the card.

signal settled

const UIIcons := preload("res://game/ui_icons.gd")
const ROLL_SEC := 0.9
const HOLD_SEC := 0.45
const FLIPS := 5                 # faces shown on the way, the last one the result
const SIZE := 64.0
const WOOD := Color(0.74, 0.52, 0.28)
const WOOD_DARK := Color(0.42, 0.26, 0.12)
const WOOD_LIGHT := Color(0.9, 0.72, 0.46)
const ENGRAVE := Color(0.26, 0.14, 0.06)

var face := "battles"            # the result's icon: victory, broken_shield or battles
var t := 0.0
var done := false
const CYCLE := ["victory", "broken_shield", "battles"]


## `result`: "win", "loss" or "draw" (the rules' outcome for the player).
static func face_of(result: String) -> String:
	return {"win": "victory", "loss": "broken_shield"}.get(result, "battles")


func setup(result: String) -> void:
	face = face_of(result)
	custom_minimum_size = Vector2(0, SIZE + 28.0)
	mouse_filter = Control.MOUSE_FILTER_STOP


## The face shown on flip k (0 = the first): the three faces in their fixed order, counted back from the result at FLIPS.
func face_at(k: int) -> String:
	var ri: int = CYCLE.find(face)
	return CYCLE[(((ri - (FLIPS - mini(k, FLIPS))) % 3) + 3) % 3]


func skip() -> void:
	if not done:
		t = ROLL_SEC + HOLD_SEC
		_finish()
		queue_redraw()


func _finish() -> void:
	if done:
		return
	done = true
	settled.emit()


func _process(delta: float) -> void:
	if done:
		return
	t += delta
	if t >= ROLL_SEC + HOLD_SEC:
		_finish()
	queue_redraw()


func _input(e: InputEvent) -> void:
	if done or not is_visible_in_tree():
		return
	if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed) \
			or (e is InputEventKey and e.pressed and not e.echo):
		get_viewport().set_input_as_handled()
		skip()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < SIZE:
		return
	# The progress through the roll: ease-out, fast first.
	var q := clampf(t / ROLL_SEC, 0.0, 1.0)
	var p := 1.0 - pow(1.0 - q, 3.0)
	var base_y := h - SIZE - 8.0
	var x0 := SIZE * 0.7
	var x1 := w * 0.5 - SIZE * 0.5
	var x := lerpf(x0, x1, p)
	var bounce := absf(sin(q * PI * 3.0)) * (1.0 - q) * 26.0
	var y := base_y - bounce
	# The shadow on the card: wider and fainter the higher the die.
	var sh_w := SIZE * (0.62 + 0.16 * bounce / 26.0)
	draw_set_transform(Vector2(x + SIZE * 0.5 + 5.0, h - 6.0), 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, sh_w, Color(0, 0, 0, 0.30 - 0.12 * bounce / 26.0))
	draw_circle(Vector2.ZERO, sh_w * 0.65, Color(0, 0, 0, 0.18))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# The flips: the front face squashes down, the next one grows in above it.
	var f := p * float(FLIPS)
	var k := mini(int(floor(f)), FLIPS)
	var fr := 0.0 if k >= FLIPS else f - float(k)
	fr = fr * fr * (3.0 - 2.0 * fr)
	var tilt := (1.0 - q) * sin(q * 17.0) * 0.12
	draw_set_transform(Vector2(x + SIZE * 0.5, y + SIZE * 0.5), tilt, Vector2.ONE)
	var top := -SIZE * 0.5
	var h1 := SIZE * (1.0 - fr)       # the face in front, squashed from the top as it turns away
	var h2 := SIZE * fr               # the next face, coming over the top edge
	if h2 > 1.0:
		_face(Rect2(-SIZE * 0.5, top, SIZE, h2), face_at(k + 1), 0.82)
	_face(Rect2(-SIZE * 0.5, top + h2, SIZE, h1), face_at(k), 1.0 - 0.18 * fr)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## One face of the die in `r` (its height squashed by the flip): wood with a grain, a bevel, the icon engraved.
func _face(r: Rect2, icon: String, light: float) -> void:
	if r.size.y < 1.0:
		return
	var rad := minf(9.0, r.size.y * 0.5)
	var body := Color(WOOD.r * light, WOOD.g * light, WOOD.b * light)
	draw_style_box(_box(body, WOOD_DARK, rad), r)
	# Grain: a few long darker strokes.
	for g in 4:
		var gy := r.position.y + r.size.y * (0.2 + 0.2 * g)
		draw_line(Vector2(r.position.x + 7.0, gy), Vector2(r.end.x - 7.0, gy + sin(float(g) * 2.1) * 1.5 * (r.size.y / SIZE)),
			Color(WOOD_DARK, 0.18), 1.0)
	# The bevel's lamp: a light edge along the top-left, a dark one along the bottom-right.
	draw_line(r.position + Vector2(rad, 1.5), Vector2(r.end.x - rad, r.position.y + 1.5), Color(WOOD_LIGHT, 0.7 * light), 1.5)
	draw_line(Vector2(r.position.x + 1.5, r.position.y + rad), Vector2(r.position.x + 1.5, r.end.y - rad), Color(WOOD_LIGHT, 0.45 * light), 1.5)
	draw_line(Vector2(r.position.x + rad, r.end.y - 1.5), Vector2(r.end.x - rad, r.end.y - 1.5), Color(WOOD_DARK, 0.6), 1.5)
	# The engraving, squashed with the face.
	var gs := SIZE * 0.62
	var gh := gs * (r.size.y / SIZE)
	if gh > 3.0:
		UIIcons.draw_icon(self, icon, Rect2(r.get_center() - Vector2(gs, gh) * 0.5, Vector2(gs, gh)), Color(ENGRAVE, 0.95))


static func _box(fill: Color, edge: Color, rad: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing = true
	return sb
