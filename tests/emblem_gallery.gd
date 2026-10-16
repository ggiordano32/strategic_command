extends SceneTree
## Contact sheet of the West faction emblems (game/faction_emblem.gd) at 16,
## 24, 32 and 96 px on a dark and a light ground. Needs a window:
##   godot --resolution 1000x420 --script res://tests/emblem_gallery.gd [-- --out=path.png]

const FE := preload("res://game/faction_emblem.gd")
var frames := 0
var out := "user://emblems.png"


class Sheet extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.14, 0.12))
		draw_rect(Rect2(0, 210, size.x, 210), Color(0.85, 0.82, 0.72))
		for i in FE.KEYS.size():
			var x := 20.0 + i * 120.0
			for row in 2:
				var y0 := row * 210.0
				FE.draw(self, FE.KEYS[i], Rect2(x, y0 + 10, 96, 96))
				FE.draw(self, FE.KEYS[i], Rect2(x, y0 + 120, 16, 16))
				FE.draw(self, FE.KEYS[i], Rect2(x + 24, y0 + 120, 24, 24))
				FE.draw(self, FE.KEYS[i], Rect2(x + 56, y0 + 120, 32, 32))


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var s := Sheet.new()
	s.size = Vector2(1000, 420)
	root.add_child(s)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 5:
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		quit(0)
	return false
