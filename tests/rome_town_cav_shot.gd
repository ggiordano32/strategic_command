extends SceneTree
## The Roman cavalry rows on a Rome town (windowed, view only; docs/design/art_pipeline.md "The Roman cavalry on a
## town (2026-11-05)"): a settlement battle (both sides AI) with equites, equites extraordinarii and the shock cavalry
## on both sides; shots of the nearest cavalry unit to the plaza (streets), the gate and the attackers' squadron.
##   godot --path . --resolution 1280x720 -s tests/rome_town_cav_shot.gd -- --out=DIR [--view=top|oblique]
##       [--plan=0..3] [--walls=0..3] [--goals=100,220,400] (ticks of the shots)
## Saves DIR/town_<plan>_w<walls>_<view>_<what>.png.
const Battle := preload("res://game/battle.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const BoardView := preload("res://game/board_view.gd")
const SpriteOb := preload("res://game/sprite_ob.gd")
const UT := preload("res://sim/unit_types.gd")
const MapGen := preload("res://sim/mapgen.gd")
const Terrain := preload("res://sim/terrain.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
var b
var out := "user://"
var view := "oblique"
var plan := 0
var walls := 0
var goals: Array = [100, 220, 400]


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	BoardView.force = "oblique"
	for a in OS.get_cmdline_user_args():
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--out="): out = v.trim_suffix("/") + "/"
		elif a.begins_with("--view="): view = v
		elif a.begins_with("--plan="): plan = int(v)
		elif a.begins_with("--walls="): walls = int(v)
		elif a.begins_with("--goals="):
			goals = []
			for g in v.split(","):
				goals.append(int(g))
	BoardView.force = "oblique" if view == "oblique" else "top"
	_run.call_deferred()


func _file_tex(path: String) -> ImageTexture:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


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


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	print("run start")
	await _frames(4)
	print("frames ok")
	SpriteOb.ensure()
	SpriteOb.shade = _file_tex("res://assets/sprites_ob/atlas_shade.png")
	SpriteOb.mask = _file_tex("res://assets/sprites_ob/atlas_mask.png")
	SpriteOb.sheet = SpriteOb.shade.get_size()
	var att: Array = [[UT.index_of("equites"), 40], [UT.index_of("equites_extra"), 40], [UT.index_of("cav"), 40],
		[UT.index_of("principes"), 100], [UT.index_of("principes"), 100]]
	var dfn: Array = [[UT.index_of("equites"), 40], [UT.index_of("equites_extra"), 40], [UT.index_of("cav"), 40],
		[UT.index_of("principes"), 90], [UT.index_of("triarii"), 60], [UT.index_of("principes"), 90]]
	var terr := {"kind": Terrain.K_ROLLING, "seed": 4243, "forest": 10, "ground": MapGen.PAL_DRY}
	var city := {"seed": 4242, "level": 2, "walls": walls, "bld": [1, 2, 3, 4], "plan": plan, "coast": 0}
	var sc: Dictionary = Scenarios.settlement(city, terr, att, dfn, 1, [0, 1])["scenario"]
	b = Battle.new()
	b.custom_scenario = sc
	b.seed_value = 5
	root.add_child(b)
	await _frames(8)
	_fresh_atlas(root)
	b.hud.visible = false
	b._set_paused(true)
	var s = b.sim
	var tag := "town_%d_w%d_%s" % [plan, walls, view]
	var stepped := 0
	var cavs := ["equites", "equites_extra", "cav"]
	for goal in goals:
		while stepped < goal:
			if stepped % 20 == 0:
				_charge(s)   # the AI keeps the horse back: send every squadron at the nearest enemy foot
			s.step()
			stepped += 1
		b.soldiers.upload()
		for side in [1, 0]:
			for k in cavs:
				var best := -1
				var bd := 1 << 60
				for u in s.n_units:
					if s.u_side[u] != side or s.u_alive[u] <= 0 or UT.key_of(s.u_type[u]) != k:
						continue
					var d: int = absi(s.u_cx[u] - s.cit_x) + absi(s.u_cy[u] - s.cit_y)
					if d < bd:
						bd = d
						best = u
				if best < 0:
					continue
				b.camera.zoom = Vector2.ONE * 3.5
				b._cam_to(Vector2(s.u_cx[best], s.u_cy[best]) / 1024.0 * Battle.PX_PER_M)
				await _frames(6)
				var f := "%s%s_t%d_s%d_%s.png" % [out, tag, goal, side, k]
				root.get_texture().get_image().save_png(f)
				print("saved ", f, " at ", s.u_cx[best] / 1024, ",", s.u_cy[best] / 1024)
	BoardView.force = ""
	quit(0)


func _charge(s) -> void:
	for u in s.n_units:
		if s.u_alive[u] <= 0 or UT.key_of(s.u_type[u]) not in ["equites", "equites_extra", "cav"]:
			continue
		var best := -1
		var bd := 1 << 60
		for t in s.n_units:
			if s.u_side[t] == s.u_side[u] or s.u_alive[t] <= 0 or UT.key_of(s.u_type[t]) in ["equites", "equites_extra", "cav"]:
				continue
			var d: int = absi(s.u_cx[u] - s.u_cx[t]) + absi(s.u_cy[u] - s.u_cy[t])
			if d < bd:
				bd = d
				best = t
		if best >= 0:
			s.u_order[u] = BattleSim.O_ATTACK
			s.u_target[u] = best
