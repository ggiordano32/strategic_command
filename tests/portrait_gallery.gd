extends SceneTree
## Contact sheet of the story portraits (game/story_portrait.gd) at 96 and
## 48 px, name under each, on a dark and a light ground. Needs a window:
##   godot --resolution 1180x520 --script res://tests/portrait_gallery.gd [-- --out=path.png]

const SP := preload("res://game/story_portrait.gd")
const BR := preload("res://campaign/data/story_brethren.gd")
var frames := 0
var out := "user://portraits.png"


class Sheet extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.14, 0.12))
		draw_rect(Rect2(0, 260, size.x, 260), Color(0.85, 0.82, 0.72))
		var font := ThemeDB.fallback_font
		for i in SP.KEYS.size():
			var k: String = SP.KEYS[i]
			var x := 12.0 + i * 106.0
			for row in 2:
				var y0 := row * 260.0
				var ink := Color(0.9, 0.9, 0.85) if row == 0 else Color(0.1, 0.1, 0.1)
				SP.draw(self, k, Rect2(x, y0 + 10, 96, 96))
				SP.draw(self, k, Rect2(x + 24, y0 + 116, 48, 48))
				var nm: String = String((BR.CHARS[k] as Dictionary)["name"])
				draw_string(font, Vector2(x, y0 + 190), nm, HORIZONTAL_ALIGNMENT_LEFT, 104, 8, ink)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var s := Sheet.new()
	s.size = Vector2(1180, 520)
	root.add_child(s)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 5:
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		quit(0)
	return false
