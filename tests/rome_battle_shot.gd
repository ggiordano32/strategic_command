extends SceneTree
## Principes against hoplites in the oblique view (windowed, view only; docs/design/art_pipeline.md "Rome and Greek figure
## sets"): two AI lines of 40 men meet on open ground and are shot at 1280x720 after 14 s of play at zoom 3:
##   godot --path . --resolution 1280x720 -s tests/rome_battle_shot.gd -- --out=DIR [--view=top]
## Saves DIR/battle_principes_hoplites.png.

const Battle := preload("res://game/battle.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const BoardView := preload("res://game/board_view.gd")
const SpriteOb := preload("res://game/sprite_ob.gd")
const UT := preload("res://sim/unit_types.gd")

var battle: Battle
var out := "user://"
var frame := 0
var view := "oblique"


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1).trim_suffix("/") + "/"
		elif a.begins_with("--view="):
			view = a.get_slice("=", 1)
	BoardView.force = "oblique" if view == "oblique" else "top"
	SpriteOb.ensure()
	SpriteOb.shade = _file_tex("res://assets/sprites_ob/atlas_shade.png")   # (see _fresh_atlas)
	SpriteOb.mask = _file_tex("res://assets/sprites_ob/atlas_mask.png")
	SpriteOb.sheet = SpriteOb.shade.get_size()
	var units: Array = [
		Scenarios.unit(0, UT.index_of("principes"), 40, 90, 120, Scenarios.FACE_RIGHT, 10),
		Scenarios.unit(1, UT.index_of("hoplites"), 40, 130, 120, Scenarios.FACE_LEFT, 10)]
	var sc := {"width_m": 220, "height_m": 240, "ai_sides": [0, 1], "units": units, "orders": []}
	battle = Battle.new()
	battle.custom_scenario = sc
	battle.seed_value = 3
	root.add_child(battle)


func _process(_d: float) -> bool:
	frame += 1
	if frame == 5:
		_fresh_atlas(root)
	if frame == 10:
		battle.hud.visible = false
		if not battle.paused:
			battle._toggle_pause()
		for _i in 560:   # the sim stepped by hand (14 s): the lines meet
			battle.sim.step()
		battle.soldiers.upload()
	if frame >= 12:
		_frame_cam()
	if frame == 40:
		root.get_texture().get_image().save_png(out + "battle_principes_hoplites%s.png" % ("" if view == "oblique" else "_top"))
		BoardView.force = ""
		quit(0)
	return false


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


## The camera on the lines' meeting point (as tests/oblique_sets_shot.gd: through the canvas transform).
func _frame_cam() -> void:
	battle.camera.zoom = Vector2.ONE * 4.0
	var sim = battle.sim
	var mid := Vector2(sim.u_cx[0] + sim.u_cx[1], sim.u_cy[0] + sim.u_cy[1]) / 2048.0 * Battle.PX_PER_M
	battle._cam_to(mid)
	battle.camera.force_update_scroll()
	var ct: Transform2D = battle.get_canvas_transform()
	var sp: Vector2 = battle.world_to_screen(mid)
	var vp: Vector2 = battle.get_viewport_rect().size
	battle.camera.position += (sp - vp * 0.5) / ct.get_scale().x
	battle.camera.force_update_scroll()
