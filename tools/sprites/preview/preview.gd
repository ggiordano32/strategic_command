extends Node2D
## Sprite pipeline step 1a preview: loads assets/sprites/manifest.json and
## the sheets (raw PNGs, read with Image.load_from_file: the folder has a
## .gdignore until step 1b), and shows every unit's actions animating,
## recoloured per palette by recolor.gdshader, at 1x, at the game's typical
## zoom (about 12 px per man) and tiny (about 7 px per man), on grass; plus
## the iso unit's walk in 8 directions.
##
##   godot --path . --resolution 2400x1350 res://tools/sprites/preview/preview.tscn
##   ... -- --shot=/path/shot.png   (saves a screenshot after ~1.3 s and quits)
##   ... -- --scroll=520            (moves the page up, for the lower sections)

const DIR := "res://assets/sprites/"
const SHADER := preload("res://tools/sprites/preview/recolor.gdshader")
const GRASS := Color(0.38, 0.52, 0.26)
const ACTIONS: Array[String] = ["idle", "walk", "attack", "death"]
const GAME_SCALE := 0.42   # ~12 px per man (a man is ~29 px across at 1x)
const TINY_SCALE := 0.25   # ~7 px per man

var man: Dictionary = {}
var tex: Dictionary = {}       # file name -> ImageTexture
var anims: Array[Dictionary] = []
var t := 0.0
var shot_path := ""
var shot_done := false


func _ready() -> void:
	RenderingServer.set_default_clear_color(GRASS)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
		elif a.begins_with("--scroll="):
			position.y = -float(a.substr(9))
	var txt := FileAccess.get_file_as_string(DIR + "manifest.json")
	var parsed: Variant = JSON.parse_string(txt)
	if not parsed is Dictionary:
		push_error("no manifest at " + DIR)
		return
	man = parsed
	_layout()


func _texture(file: String) -> ImageTexture:
	if not tex.has(file):
		var img := Image.load_from_file(ProjectSettings.globalize_path(DIR + file))
		img.generate_mipmaps()
		tex[file] = ImageTexture.create_from_image(img)
	return tex[file]


func _material(pal: Dictionary, mask_file: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("mask_tex", _texture(mask_file))
	for k: String in ["primary", "secondary", "accent"]:
		var c: Array = pal[k]
		m.set_shader_parameter(k, Vector3(c[0], c[1], c[2]))
	var p: Array = pal["pattern"]
	m.set_shader_parameter("pattern_col", Vector3(p[0], p[1], p[2]))
	m.set_shader_parameter("pattern_k", float(pal["pattern_k"]))
	return m


## An animated sprite whose anchor (the man's feet) sits at `pos`.
func _sprite(entry: Dictionary, sheet: Dictionary, pal: Dictionary, pos: Vector2,
		scl: float, rot: float = 0.0, phase: float = 0.0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _texture(sheet["shade"])
	s.material = _material(pal, sheet["mask"])
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.centered = false
	s.region_enabled = true
	var anchor: Array = entry["anchor"]
	s.offset = -Vector2(anchor[0], anchor[1])
	s.position = pos
	s.scale = Vector2(scl, scl)
	s.rotation = rot
	add_child(s)
	anims.append({"node": s, "frames": entry["frames"], "fps": float(entry["fps"]),
		"loop": int(entry["loop"]), "phase": phase})
	_set_frame(anims[-1], 0.0)
	return s


func _set_frame(a: Dictionary, time: float) -> void:
	var frames: Array = a["frames"]
	var i := int(floor((time + a["phase"]) * a["fps"]))
	if a["loop"] == 1:
		i = posmod(i, frames.size())
	else:
		i = posmod(i, frames.size() + 6)   # play, hold the corpse, replay
		i = mini(i, frames.size() - 1)
	var r: Array = frames[i]
	(a["node"] as Sprite2D).region_rect = Rect2(r[0], r[1], r[2], r[3])


func _label(text: String, pos: Vector2, size: int = 15) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 0.92))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.12, 0.06))
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)


func _frame_size(entry: Dictionary) -> Vector2:
	var r: Array = (entry["frames"] as Array)[0]
	return Vector2(r[2], r[3])


func _layout() -> void:
	var units: Dictionary = man["units"]
	var pals: Dictionary = man["palettes"]
	# --- 1x: per unit a row: palettes x actions
	var y := 30.0
	_label("1x (24 px per metre): idle, walk, attack, death  |  palettes: " + ", ".join(
		pals.values().map(func(p: Dictionary) -> String: return p["name"])), Vector2(12, 4))
	for uid: String in units:
		var u: Dictionary = units[uid]
		var acts: Dictionary = u["actions"]
		var h := 0.0
		for act in ACTIONS:
			h = maxf(h, _frame_size(acts[act]).y)
		var x := 12.0
		for pk: String in pals:
			if x > 1400.0:   # wrap the wide (cavalry) rows
				x = 12.0
				y += h + 10.0
			for act in ACTIONS:
				var e: Dictionary = acts[act]
				var anchor: Array = e["anchor"]
				var top: float = h * 0.5 - _frame_size(e).y * 0.5
				_sprite(e, u, pals[pk], Vector2(x + anchor[0], y + top + anchor[1]), 1.0)
				x += _frame_size(e).x + 6.0
			x += 22.0
		y += h + 10.0
	# --- game zoom and tiny: per unit a row of blocks (palettes x straight / turned)
	for zi in 2:
		var scl := GAME_SCALE if zi == 0 else TINY_SCALE
		_label("%s zoom (x%.2f, about %d px per man): blocks walking, front rank attacking, one dead; each second block turned 35 deg"
			% ["game" if zi == 0 else "tiny", scl, int(round(29.0 * scl))], Vector2(12, y))
		y += 30.0
		for uid: String in units:
			var u: Dictionary = units[uid]
			var cav := uid.contains("cav")
			var dx: float = (3.4 if cav else 1.6) * 24.0 * scl   # rank spacing (forward)
			var dy: float = (1.7 if cav else 1.2) * 24.0 * scl   # file spacing
			var ranks := 3
			var files := 5
			var x := 30.0
			for pk: String in pals:
				for turned in 2:
					var origin := Vector2(x + dx * 0.8, y + dy * (1.6 if turned == 1 else 0.6))
					var rot := -0.61 if turned == 1 else 0.0
					var basis := Transform2D(rot, Vector2.ZERO)
					for rk in ranks:
						for fl in files:
							var act := "walk"
							if rk == ranks - 1:
								act = "attack"
							if rk == 0 and fl == 3:
								act = "death"
							var local := Vector2(rk * dx, fl * dy)
							_sprite(u["actions"][act], u, pals[pk], origin + basis * local, scl, rot,
								0.13 * (rk * 7 + fl * 3))
					x += dx * ranks + dx * 1.5 + 14.0
				x += 24.0
			y += dy * files + dy * 1.2 + 8.0
		y += 6.0
	# --- iso: 8 directions
	if man.has("iso"):
		var iso: Dictionary = man["iso"]
		var dirs: Dictionary = iso["directions"]
		_label("iso (%d deg elevation): %s walk in 8 directions (d0 east, counter-clockwise), 1x per palette, then x0.5"
			% [int(iso["elevation_deg"]), iso["unit"]], Vector2(12, y))
		y += 24.0
		var fs := _frame_size(dirs["d0"])
		var x := 12.0
		for pk: String in pals:
			if x + fs.x * 8.0 > 2300.0:
				x = 12.0
				y += fs.y + 4.0
			for k in dirs.size():
				var e: Dictionary = dirs["d%d" % k]
				var anchor: Array = e["anchor"]
				_sprite(e, iso, pals[pk], Vector2(x + anchor[0], y + anchor[1]), 1.0)
				x += fs.x + 2.0
			x += 16.0
		y += fs.y + 6.0
		x = 12.0
		for pk: String in pals:
			for k in dirs.size():
				var e: Dictionary = dirs["d%d" % k]
				var anchor: Array = e["anchor"]
				_sprite(e, iso, pals[pk], Vector2(x + anchor[0] * 0.5, y + anchor[1] * 0.5), 0.5)
				x += fs.x * 0.5 + 2.0
			x += 16.0


func _process(delta: float) -> void:
	t += delta
	for a in anims:
		_set_frame(a, t)
	if shot_path != "" and not shot_done and t > 1.3:
		shot_done = true
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot_path)
		print("PREVIEW shot ", shot_path, " ", img.get_size())
		get_tree().quit()
