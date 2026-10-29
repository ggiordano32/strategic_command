extends Control
## The tutorial's pointer: a pulsing gold ring (and a short arrow) over the thing to tap. It is a full-screen control that
## ignores the mouse, drawn every frame at the screen point its `target` Callable answers (a Vector2 in this control's
## space, or null for "nothing to show"). Used on the campaign screen (a map cell, a button of the interface) and on the
## battle HUD (a chip, a card, a spot on the map). View only.

const COL := Color(1.0, 0.85, 0.35)

var target := Callable()     # -> Vector2 (screen point) or null
var radius := 30.0
var point := Vector2.ZERO    # the point last drawn (tests read it)
var showing := false


func _init() -> void:
	name = "tutor_pointer"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200


## A Control's centre on the screen (null while it is not visible).
static func center_of(c: Control) -> Variant:
	if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
		return null
	return c.get_global_rect().get_center()


func _process(_d: float) -> void:
	var p: Variant = target.call() if target.is_valid() else null
	showing = p is Vector2
	visible = showing
	if showing:
		point = p
		queue_redraw()


func _draw() -> void:
	if not showing:
		return
	var t := Time.get_ticks_msec() / 1000.0
	var k := fmod(t * 1.4, 1.0)
	var r0 := radius * (0.7 + 0.5 * k)
	draw_circle(point, radius * 0.55, Color(COL, 0.10))
	draw_arc(point, r0, 0.0, TAU, 40, Color(COL, 0.9 * (1.0 - k)), 3.0, true)
	draw_arc(point, radius * 0.7, 0.0, TAU, 40, Color(0, 0, 0, 0.6), 5.0, true)
	draw_arc(point, radius * 0.7, 0.0, TAU, 40, COL, 2.4, true)
