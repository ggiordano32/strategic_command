extends SceneTree
## The oblique view's figure sweep (tabletop pass 3, needs a window):
##   godot --path . --resolution 1280x720 -s tests/oblique_sets_shot.gd -- --out=DIR
## Every sprite set (a unit of it, or for the engine sets a battery's engines) on flat ground, its men in a row facing
## the 8 directions S, SW, W, NW, N, NE, E, SE left to right, a set a row, at zoom 2; nine frames of five sets saved as
## DIR/p3b_sets_1..9.png and put together (3 x 3) into DIR/p3b_sets.png. View only: the sim is set up and
## its positions and facings placed by hand for the picture (never stepped). Prints the sets and exits.

const Battle := preload("res://game/battle.gd")
const UT := preload("res://sim/unit_types.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const BoardView := preload("res://game/board_view.gd")
const SpriteOb := preload("res://game/sprite_ob.gd")
const SpriteAtlas := preload("res://game/sprite_atlas.gd")

const DX := 3.8         # metres between the men of a row
const PANELS := 3
const PER := 5          # sets a frame
const ROW_H := 8.0      # metres between rows
const X0 := 20.0
const Y0 := 20.0

var battle: Battle
var out := "user://"
var frame := 0
var shots: Array[Image] = []
var _sets: Array = []        # [set, type, engine] per block


func _initialize() -> void:
	BoardView.force = "top" if OS.get_cmdline_user_args().has("--top") else "oblique"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # (an unfocused window can stall on vsync)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1).trim_suffix("/") + "/"
	SpriteOb.ensure()
	SpriteOb.shade = _file_tex("res://assets/sprites_ob/atlas_shade.png")   # (see _fresh_atlas)
	SpriteOb.mask = _file_tex("res://assets/sprites_ob/atlas_mask.png")
	SpriteOb.sheet = SpriteOb.shade.get_size()
	var units: Array = []
	var keys := ["principes", "triarii", "hoplites", "cav", "cav2", "cav3", "bodyguard", "scorpions", "tower_bolt", "tower_stone"]
	for k in keys:
		var ty := -1
		for t in UT.TYPES.size():
			if UT.key_of(t) == k:
				ty = t
				break
		if ty < 0:
			print("no type ", k)
			continue
		var eng: bool = UT.cls(ty) == UT.CLS_ART
		var s: int = UT.stat(ty, "engine_set") if eng else UT.stat(ty, "sprite_set")
		var b := _sets.size()
		_sets.append([maxi(s, 1), ty, eng])
		var c := _block(b)
		units.append(Scenarios.unit(0, ty, mini(8, maxi(UT.size_of(ty), 1)), int(c.x) + 14, int(c.y), Scenarios.FACE_DOWN))
	var sc := {"width_m": 100, "height_m": int(Y0 * 2.0 + ROW_H * _sets.size()), "ai_sides": [], "units": units, "orders": []}
	battle = Battle.new()
	battle.custom_scenario = sc
	battle.seed_value = 1
	root.add_child(battle)


func _block(b: int) -> Vector2:
	return Vector2(X0, Y0 + b * ROW_H)


func _place() -> void:
	var sim = battle.sim
	for u in sim.n_units:
		var c := _block(u) * 1024.0
		var base: int = sim.u_slot_base[u]
		var eng: bool = _sets[u][2]
		for s in sim.u_alive[u]:
			var i: int = sim.slot_soldier[base + s]
			if eng or s >= 8:
				sim.state[i] = 5   # (an engine set: the crews off; only the engines are shown)
				continue
			sim.pos_x[i] = int(c.x + s * DX * 1024.0)
			sim.pos_y[i] = int(c.y)
			sim.prev_x[i] = sim.pos_x[i]
			sim.prev_y[i] = sim.pos_y[i]
			sim.facing[i] = (256 + 128 * s) & 1023
			sim.state[i] = 0
		var k := 0
		for e in sim.n_eng:
			if sim.e_unit[e] != u:
				continue
			sim.e_x[e] = int(c.x + k * DX * 1024.0)
			sim.e_y[e] = int(c.y)
			sim.e_px[e] = sim.e_x[e]
			sim.e_py[e] = sim.e_y[e]
			sim.e_face[e] = (256 + 128 * k) & 1023
			k += 1
		sim.u_cx[u] = int(c.x)
		sim.u_cy[u] = int(c.y)
	battle.soldiers.upload()
	battle.soldiers.set_alpha(1.0)
	battle.overlay.visible = false
	battle.trays.visible = false
	battle.hud.visible = false
	var lab := _Labels.new()
	lab.sets = _sets
	lab.test = self
	battle.add_child(lab)


func _frame_cam(panel: int) -> void:
	# Rows 8 a panel: the camera on the middle of the panel's rows.
	battle.camera.zoom = Vector2(2.0, 2.0)
	# The panel's first figure 60 px from the left edge, its rows centred (measured through the canvas transform).
	var vp: Vector2 = battle.get_viewport_rect().size
	var first := Vector2(X0, Y0 + (panel * PER + (PER - 1) * 0.5) * ROW_H) * Battle.PX_PER_M
	battle._cam_to(first)
	battle.camera.force_update_scroll()
	var ct: Transform2D = battle.get_canvas_transform()
	var sp: Vector2 = battle.world_to_screen(first)
	battle.camera.position.x += (sp.x - 60.0) / ct.get_scale().x
	battle.camera.position.y += (sp.y - vp.y * 0.5 + 20.0) / ct.get_scale().y
	battle.camera.force_update_scroll()


func _process(_d: float) -> bool:
	frame += 1
	if frame == 5:
		_fresh_atlas(root)
	elif frame == 20:
		if not battle.paused:
			battle._toggle_pause()
		_place()
		_frame_cam(0)
	elif frame >= 30 and frame <= 30 + 10 * (PANELS - 1) and frame % 10 == 0:
		var img := root.get_texture().get_image()
		shots.append(img)
		img.save_png(out + "aud_sets_%d.png" % shots.size())
		if shots.size() < PANELS:
			_frame_cam(shots.size())
	elif frame == 32 + 10 * (PANELS - 1):
		var w := shots[0].get_width()
		var h := shots[0].get_height()
		var all := Image.create(w * 3, h * 3, false, shots[0].get_format())
		for q in PANELS:
			all.blit_rect(shots[q], Rect2i(0, 0, w, h), Vector2i(w * (q % 3), h * (q / 3)))
		all.save_png(out + "aud_sets.png")
		for b in _sets.size():
			print("SET %d %s (block %d, type %s%s)" % [_sets[b][0], SpriteAtlas.SETS[_sets[b][0] - 1], b,
				UT.key_of(_sets[b][1]), ", engines" if _sets[b][2] else ""])
		print("RESULT: saved %sp3b_sets.png" % out)
		BoardView.force = ""
		quit(0)
	return false


## The set's name under each row of figures (on the board, no lift shader: the board point by hand).
class _Labels extends Node2D:
	var sets: Array
	var test

	func _ready() -> void:
		z_index = 50

	func _draw() -> void:
		for b in sets.size():
			var c: Vector2 = test._block(b) + Vector2(-2.0, 1.6)
			var p := BoardView.to_board(c * Battle.PX_PER_M)
			draw_string(ThemeDB.fallback_font, p, "%s" % UT.key_of(sets[b][1]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 0.85))


## The imported copies of the atlases can be older than the files (a re-pack before the project's next import): the shot
## loads both atlases from the files and hands them to every soldier material.
func _fresh_atlas(n: Node) -> void:
	if n is CanvasItem and (n as CanvasItem).material is ShaderMaterial:
		var m := (n as CanvasItem).material as ShaderMaterial
		if m.get_shader_parameter("atlas_shade") != null:
			for p in ["shade", "mask"]:
				m.set_shader_parameter("atlas_" + p, _file_tex("res://assets/sprites/atlas_%s.png" % p))
		if m.get_shader_parameter("ob_shade") != null:
			for p in ["shade", "mask"]:
				m.set_shader_parameter("ob_" + p, _file_tex("res://assets/sprites_ob/atlas_%s.png" % p))
	for c in n.get_children():
		_fresh_atlas(c)


func _file_tex(path: String) -> ImageTexture:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
