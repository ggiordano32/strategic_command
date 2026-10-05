extends Control
## A Control that draws one unit symbol (see unit_icons.gd), sized by
## custom_minimum_size. Used on unit cards and in the unit book.

const Icons := preload("res://game/unit_icons.gd")

var icon := 0
var fill := Color(0.35, 0.6, 1.0)


func _init(p_icon: int = 0, p_fill: Color = Color(0.35, 0.6, 1.0), size_px: float = 40.0) -> void:
	icon = p_icon
	fill = p_fill
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_icon(p_icon: int, p_fill: Color) -> void:
	icon = p_icon
	fill = p_fill
	queue_redraw()


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5 - 1.0
	Icons.draw_marker(self, icon, size * 0.5, r, fill)
