extends Node3D
## The 3D battle view, step one (2026-11-06; docs/design/art_pipeline.md "The 3D battle view, step one"; the owner: "go with the
## 3D view with painted sprites"). Chosen by the Battle view setting "3D" (`[video] battle_view = 3d`, BoardView.v3d). View only:
## it reads the sim and the 2D layers' built data and writes nothing back; lockstep and the hashes never see it.
##
## A Node3D scene in the battle's own viewport, under the HUD and the overlay (both stay 2D, on top):
## - the board: a mesh of the sim's heightfield at the fine lift field's 2 m nodes (the foam steps quantised as BoardView does),
##   shaded by the terrain shader's own body (game/terrain_body.gdshaderinc through game/terrain3d.gdshader: the painted board of
##   pass 2, the hills of pass 6, the resin water), lit by one lamp; the board a cut slab with foam layers on its four edges
##   (game/board_slab3d.gdshader) on a wooden table plane (game/table3d.gdshader);
## - one orthographic Camera3D placed every frame from the battle's Camera2D (its canvas transform: the point at the screen's centre
##   and the zoom) and BoardView's yaw and elevation, so the 2D overlay drawn through the board transform lies exactly on the 3D
##   ground (BoardView.to_board is this camera's projection of the ground);
## - one DirectionalLight3D standing in the room (the world lamp, 2026-11-06: fixed to the board, not the camera; at the battle's
##   opening yaw it is where the painted sprites' key is, the screen's upper left and the far side), its shadows on at Graphics
##   High (the camera's near and far fitted to the visible ground, which is the shadow's range for an orthographic camera);
##   ambient and tone mapping as the 3D spike set them (linear, lamp 1.0, ambient 0.42);
## - the trees as cards (the oblique kit sheet's tree sprites standing at their feet, game/trees3d.gdshader);
## - the kit (game/battlekit3d.gdshaderinc): the oblique view's wall rows (walls, gates, drums, stairs, the stockade, square towers
##   off the axes) as real geometry on the ground, its sheet pieces (houses, towers, gates, rocks, landmarks) as cards re-picked
##   from the sheet's renders for the camera's yaw (in 90 degree steps: they swap as the table turns); the siege gear and the ships
##   off the shore as solids (game/siege_gear_ob.gd's emitter), rebuilt when they change;
## - step two (2026-11-06): the houses, huts, the West town's buildings, the towers, the bastion, the props, the rocks and the
##   landmarks as meshes (game/kit3d.gd: the kit's own Blender models, low poly, their painted look baked), a MultiMesh per piece
##   kind at the pieces' places, turned with the table and casting shadows (_build_meshes); every gate and square tower as rows;
##   their cards are hidden; without assets/battlekit_ob/kit3d.res (or with --no-kit3d) the cards as step one;
## - the men as painted cards (game/soldiers3d.gdshaderinc) from the soldier layer's CPU-fed buffer as it is, their round bases flat
##   on the board under them, the missiles in flight in real height (game/projectiles3d.gdshaderinc).

const BoardView := preload("res://game/board_view.gd")
const Quality := preload("res://game/quality.gd")
const KitOb := preload("res://game/kit_ob.gd")
const TERRAIN_SHADER := preload("res://game/terrain3d.gdshader")
const TABLE_SHADER := preload("res://game/table3d.gdshader")
const SLAB_SHADER := preload("res://game/board_slab3d.gdshader")
const TREE_SHADER := preload("res://game/trees3d.gdshader")
const MEN_SHADER := preload("res://game/soldiers3d.gdshader")
const MEN_SHADER_CPU := preload("res://game/soldiers3d_cpu.gdshader")
const BASE_SHADER := preload("res://game/soldier_bases3d.gdshader")
const BASE_SHADER_CPU := preload("res://game/soldier_bases3d_cpu.gdshader")
const PR_SHADER := preload("res://game/projectiles3d.gdshader")
const PR_SHADER_CPU := preload("res://game/projectiles3d_cpu.gdshader")
const SpriteOb := preload("res://game/sprite_ob.gd")
const KIT_SHADER := preload("res://game/battlekit3d.gdshader")
const KIT_SHADER_CPU := preload("res://game/battlekit3d_cpu.gdshader")
const SOLID_SHADER := preload("res://game/solid3d.gdshader")
const CityDraw := preload("res://game/city_draw.gd")
const GroundPalette := preload("res://game/ground_palette.gd")
const BattleLook := preload("res://game/battle_look.gd")
const SoldierLayer := preload("res://game/soldier_layer.gd")
const Kit3D := preload("res://game/kit3d.gd")
const Fx3D := preload("res://game/fx3d.gd")
const KIT_MESH_SHADER := preload("res://game/kit_mesh3d.gdshader")
const KitAtlas := preload("res://game/battlekit_atlas.gd")
const MapGen := preload("res://sim/mapgen.gd")
## Rome's houses (the kit's own frame has no street side): their door turned to the open side (_street_flip).
const DOOR_PIECES := ["house_gable_s", "house_gable_m", "house_gable_l", "house_hip_s", "house_hip_m", "longhouse",
	"house_L", "hut_thatch", "house_flat_s", "house_flat_m"]

const AMBIENT := 0.42
const LAMP := 1.0
## The lamp at yaw 0 (the direction its light travels): from the screen's upper left and the far side, so shadows fall to the
## lower right as the 2D views' baked shadows do (the sprites' key light is the camera's upper left). The world lamp is this turned
## by the battle's opening yaw (lamp_yaw) and then stays: 50.3 degrees up, 38.7 degrees left of the opening camera's forward.
const LAMP_DIR := Vector3(0.40, -0.77, 0.50)
## The painted sprites' and the trees' screen-space key (x right, y down, z toward the viewer): the 2D kit's light_dir.
const PAINT_KEY := Vector3(-0.55, -0.50, 0.67)
## How much a figure's card is darkened on the side away from the lamp and lightened toward it when the table is turned
## (the paint's highlight is on the camera's left; at the opening yaw the term is 0): a gradient over a man's width.
const SIDE_K := 0.3
## The lamp's first shadow split, a share of the camera's near-far range (the ground in view, sync_camera).
const SHADOW_SPLIT := 0.5
var side_amt := SIDE_K           # (--v3d-side=K: a testing aid, 0 the paint as it is)
const SLAB_BELOW := 3.0          # metres of board under its lowest ground
const TABLE_BELOW := 0.05        # the table just under the slab's foot
const MESH_MAX_VERTS := 200000   # the board mesh's budget (a coarser stride past it)

var battle: Node
var sim
var ppm := 10.0
var cam: Camera3D
var lamp: DirectionalLight3D
var env: Environment
var terrain_mi: MeshInstance3D
var terrain_mat: ShaderMaterial
var table_mi: MeshInstance3D
var slab_mi: MeshInstance3D
var tree_mmi: MultiMeshInstance3D
var tree_mat: ShaderMaterial
var shadows := true
## The world lamp's yaw (BoardView.yaw at the first frame: the battle's opening yaw), latched once; -1000 until then.
var lamp_yaw := -1000.0
## The kit materials' and the trees' own light_dir as built (the kit's walls are lit by it in world space, the trees' sheet
## normals in screen space): turned with the lamp.
var _kit_ld: Array = []          # [ShaderMaterial, its light_dir]
var _tree_ld := PAINT_KEY
var ground_lo := 0.0             # the board's lowest / highest ground (3D y, metres)
var ground_hi := 0.0
var field_m := Vector2(100.0, 100.0)
var build_ms := 0.0
## Card materials whose camera terms follow the camera (the cards are built from the camera's axes in the vertex stage, also in the
## shadow pass, where the view is the lamp's).
var card_mats: Array[ShaderMaterial] = []
var cam_size := 100.0
var men_mmi: MultiMeshInstance3D
var men_mat: ShaderMaterial
var base_mmi: MultiMeshInstance3D
var base_mat: ShaderMaterial
var pr_mmi: MultiMeshInstance3D
var pr_mat: ShaderMaterial
## Materials whose interpolation (alpha, now) follows the soldier layer's every frame.
var tick_mats: Array[ShaderMaterial] = []
var kits: Array = []             # [kit node, MultiMeshInstance3D, its rev, its yaw sector] per kit with rows
var fx: Node3D                   # the flashes and the smoke (game/fx3d.gd)
var gear_mi: MeshInstance3D
var ship_mi: MeshInstance3D
var _gear_tick := -1
var _gear_sig := 0
var _ship_sig := -2
var _solid_mat: ShaderMaterial
## Step two: per kit with meshes {"kit", "mat", "mmis": piece -> MultiMeshInstance3D, "rev", "inst": instance indices drawn as
## meshes, "lm": landmark rows drawn as meshes}; the instances drawn as meshes in all (tests and the build line).
var kit_meshes: Array = []
var mesh_instances := 0
var mesh_mats: Array[ShaderMaterial] = []
## The drawn ground decals of the 2D views (the terrain layer's tracks and flock-square fields, the sea gate's channel, the
## breach and fallen-house rubble) painted once into an offscreen canvas over the whole field and laid on the board by its
## shader; painted again when the rubble changes.
var _gc_vp: SubViewport
var _gc_node: Node2D
var _gc_rub := -1
## The self-check (as the soldier layer's probe): PROBE_FRAMES frames in, only the men are drawn into a small offscreen viewport
## round the biggest unit and the drawn pixels counted; none with men alive on the fine path (a texture read in the vertex
## stage, which some devices' WebGL does not do: Chrome on the Tab S7) switches the men, the bases, the missiles and the kit to
## the compatible shaders (the coarse grid) and remembers it for later battles (the soldier layer's pref "cpu").
const PROBE_LAYER := 1 << 19
const PROBE_PX := 128
const PROBE_FRAMES := 30
var _probe_frames := 0
var probe_drawn := -1


func setup(p_battle: Node, p_sim, p_ppm: float) -> void:
	var t0 := Time.get_ticks_usec()
	battle = p_battle
	sim = p_sim
	ppm = p_ppm
	process_priority = 1000   # after the battle's _process has moved the Camera2D
	field_m = Vector2(sim.field_w, sim.field_h) / 1024.0
	shadows = not Quality.is_low() and not ("--v3d-shadows=0" in OS.get_cmdline_user_args())
	if "--v3d-shadows=1" in OS.get_cmdline_user_args():
		shadows = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--v3d-side="):
			side_amt = float(a.get_slice("=", 1))
	_build_env()
	_build_board()
	_build_table()
	_build_trees()
	_build_men()
	_build_fx()
	_build_kits()
	_build_ground_canvas()
	if "--v3d-no-men" in OS.get_cmdline_user_args():
		for n in [men_mmi, base_mmi, pr_mmi]:
			if n != null:
				n.visible = false   # (testing aid: the board's own frame cost)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	add_child(cam)
	cam.make_current()
	sync_camera()
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	print("view3d: built in %.1f ms (board %d verts, %d trees, %d kit meshes, shadows %s)" % [build_ms,
		(terrain_mi.mesh as ArrayMesh).surface_get_array_len(0) if terrain_mi != null and terrain_mi.mesh != null else 0,
		tree_mmi.multimesh.instance_count if tree_mmi != null else 0, mesh_instances, "on" if shadows else "off"])


func _build_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.09, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.6, 0.66)
	env.ambient_light_energy = AMBIENT
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	lamp = DirectionalLight3D.new()
	lamp.light_energy = LAMP
	lamp.light_color = Color(1.0, 0.95, 0.86)
	lamp.shadow_enabled = shadows
	# Two splits over the camera's near-far range (sync_camera fits it to the ground in view): the near half of the ground (the
	# screen's lower half) gets its own map. At the phone's fit this drew the houses' shadows where one orthogonal map blurred
	# them away, for about the same GPU time (art_pipeline.md "The 3D battle view: the world lamp").
	lamp.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	lamp.directional_shadow_split_1 = SHADOW_SPLIT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--v3d-splits="):   # (testing aids: 1 one orthogonal map, 2 or 4 parallel splits; the first split)
			var n := int(a.get_slice("=", 1))
			lamp.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if n <= 1 else (DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if n == 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
		elif a.begins_with("--v3d-split1="):
			lamp.directional_shadow_split_1 = float(a.get_slice("=", 1))
	lamp.shadow_bias = 0.05
	lamp.shadow_normal_bias = 1.0
	lamp.shadow_blur = 1.0
	lamp.transform = Transform3D(_lamp_basis(), Vector3.ZERO)
	add_child(lamp)


# --------------------------------------------------------------------------------------------- the board

## The ground's height (3D y, metres above the base) at a fine node / a world point.
func _node_h(i: int, j: int, st: int) -> float:
	var nx := BoardView.fine_nx
	var ii := mini(i * st, nx - 1)
	var jj := mini(j * st, BoardView.fine_ny - 1)
	return BoardView.quant(BoardView.fine_l[jj * nx + ii]) / (ppm * BoardView.OBLIQUE_SIN)


func _build_board() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var gx := 0
	var gy := 0
	var cell := 2.0
	var hs := PackedFloat32Array()
	if BoardView.fine:
		var st := 1
		var cap := MESH_MAX_VERTS / 4 if Quality.is_low() else MESH_MAX_VERTS
		while (BoardView.fine_nx / st + 1) * (BoardView.fine_ny / st + 1) > cap:
			st += 1
		gx = (BoardView.fine_nx - 1) / st + 1
		gy = (BoardView.fine_ny - 1) / st + 1
		cell = BoardView.fine_cell_px / ppm * st
		hs.resize(gx * gy)
		for j in gy:
			for i in gx:
				hs[j * gx + i] = _node_h(i, j, st)
	else:
		# The coarse grid (the compatible soldiers path, Graphics Low, a flat map): its bilinear lift sampled every 4 m.
		cell = 4.0
		gx = int(ceilf(field_m.x / cell)) + 1
		gy = int(ceilf(field_m.y / cell)) + 1
		hs.resize(gx * gy)
		for j in gy:
			for i in gx:
				var w := Vector2(minf(i * cell, field_m.x), minf(j * cell, field_m.y)) * ppm
				hs[j * gx + i] = BoardView.ground_m(w) if BoardView.oblique else 0.0
	verts.resize(gx * gy)
	norms.resize(gx * gy)
	ground_lo = 1e9
	ground_hi = -1e9
	for j in gy:
		for i in gx:
			var k := j * gx + i
			var h := hs[k]
			ground_lo = minf(ground_lo, h)
			ground_hi = maxf(ground_hi, h)
			verts[k] = Vector3(minf(i * cell, field_m.x), h, minf(j * cell, field_m.y))
			var hl := hs[j * gx + maxi(i - 1, 0)]
			var hr := hs[j * gx + mini(i + 1, gx - 1)]
			var hu := hs[maxi(j - 1, 0) * gx + i]
			var hd := hs[mini(j + 1, gy - 1) * gx + i]
			norms[k] = Vector3(hl - hr, 2.0 * cell, hu - hd).normalized()
	idx.resize((gx - 1) * (gy - 1) * 6)
	var q := 0
	for j in gy - 1:
		for i in gx - 1:
			var a := j * gx + i
			idx[q] = a
			idx[q + 1] = a + 1
			idx[q + 2] = a + gx
			idx[q + 3] = a + 1
			idx[q + 4] = a + gx + 1
			idx[q + 5] = a + gx
			q += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = TERRAIN_SHADER
	var tl = battle.terrain
	if tl != null and tl.material_ref != null:
		copy_params(tl.material_ref, terrain_mat)
	BoardView.apply(terrain_mat)
	terrain_mat.set_shader_parameter("fake_lamp", 0.0 if shadows else 1.0)
	terrain_mat.set_shader_parameter("shade_k", 0.0)
	terrain_mat.set_shader_parameter("tufts_on", false)
	var cl = battle.city
	if cl != null:
		for ch in cl.get_children():
			if ch is Sprite2D and ch != cl.paths_node and (ch as Sprite2D).texture != null:
				var sp := ch as Sprite2D
				var tsz := sp.texture.get_size() * sp.scale
				terrain_mat.set_shader_parameter("street_tex", sp.texture)
				terrain_mat.set_shader_parameter("street_rect", Vector4(sp.position.x, sp.position.y, tsz.x, tsz.y))
				break
	terrain_mi = MeshInstance3D.new()
	terrain_mi.mesh = am
	terrain_mi.material_override = terrain_mat
	terrain_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(terrain_mi)
	_build_slab(hs, gx, gy, cell)


## The board's four cut edges: a strip from the ground at the edge down to the slab's foot (game/board_slab3d.gdshader paints the
## foam layers, the MDF base and the flock lip by height).
func _build_slab(hs: PackedFloat32Array, gx: int, gy: int, cell: float) -> void:
	var foot := ground_lo - SLAB_BELOW
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	# (each edge: a run of ground points, its outward normal)
	var edges: Array = []
	var north: Array = []
	var south: Array = []
	for i in gx:
		north.append(Vector3(minf(i * cell, field_m.x), hs[i], 0.0))
		south.append(Vector3(minf(i * cell, field_m.x), hs[(gy - 1) * gx + i], field_m.y))
	var west: Array = []
	var east: Array = []
	for j in gy:
		west.append(Vector3(0.0, hs[j * gx], minf(j * cell, field_m.y)))
		east.append(Vector3(field_m.x, hs[j * gx + gx - 1], minf(j * cell, field_m.y)))
	edges.append([north, Vector3(0, 0, -1)])
	edges.append([south, Vector3(0, 0, 1)])
	edges.append([west, Vector3(-1, 0, 0)])
	edges.append([east, Vector3(1, 0, 0)])
	for e in edges:
		var pts: Array = e[0]
		var n: Vector3 = e[1]
		var base := verts.size()
		for p in pts:
			var v: Vector3 = p
			verts.append(v)
			verts.append(Vector3(v.x, foot, v.z))
			norms.append(n)
			norms.append(n)
			uvs.append(Vector2(v.x + v.z, v.y))
			uvs.append(Vector2(v.x + v.z, v.y))
		for s in pts.size() - 1:
			var a := base + s * 2
			idx.append_array(PackedInt32Array([a, a + 2, a + 1, a + 2, a + 3, a + 1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = SLAB_SHADER
	mat.set_shader_parameter("band_m", BoardView.BAND_M * BoardView.exag)
	mat.set_shader_parameter("foot_y", foot)
	var tl = battle.terrain
	if tl != null and tl.material_ref != null:
		var bc = tl.material_ref.get_shader_parameter("base_col")
		if bc is Vector3:
			mat.set_shader_parameter("flock_col", bc)
	slab_mi = MeshInstance3D.new()
	slab_mi.mesh = am
	slab_mi.material_override = mat
	add_child(slab_mi)


func _build_table() -> void:
	table_mi = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000.0, 6000.0)
	table_mi.mesh = pm
	table_mi.position = Vector3(field_m.x * 0.5, ground_lo - SLAB_BELOW - TABLE_BELOW, field_m.y * 0.5)
	var mat := ShaderMaterial.new()
	mat.shader = TABLE_SHADER
	mat.set_shader_parameter("board_rect", Vector4(0.0, 0.0, field_m.x, field_m.y))
	table_mi.material_override = mat
	table_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(table_mi)


# --------------------------------------------------------------------------------------------- the men

## The men, their bases and the missiles: MultiMeshes the soldier layer fills from its CPU-fed buffers every tick
## (SoldierLayer.v3d_mm / v3d_pr_mm); the shaders read the fine lift field for the ground's height, or the coarse grid when the
## board is the grid (the compatible soldiers path: no texture read in the vertex stage).
func _build_men() -> void:
	var sl = battle.soldiers
	if sl == null:
		return
	var grid := not BoardView.fine
	var aabb := AABB(Vector3(-60.0, ground_lo - 20.0, -60.0), Vector3(field_m.x + 120.0, ground_hi - ground_lo + 80.0, field_m.y + 120.0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = card_quad()
	mm.instance_count = sl._n_inst
	mm.custom_aabb = aabb
	men_mat = ShaderMaterial.new()
	men_mat.shader = MEN_SHADER_CPU if grid else MEN_SHADER
	_men_params(men_mat, sl)
	men_mmi = MultiMeshInstance3D.new()
	men_mmi.multimesh = mm
	men_mmi.material_override = men_mat
	men_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(men_mmi)
	base_mat = ShaderMaterial.new()
	base_mat.shader = BASE_SHADER_CPU if grid else BASE_SHADER
	_men_params(base_mat, sl)
	base_mat.set_shader_parameter("low", 1.0 if Quality.is_low() else 0.0)
	base_mmi = MultiMeshInstance3D.new()
	base_mmi.multimesh = mm
	base_mmi.material_override = base_mat
	base_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(base_mmi)
	sl.v3d_mm = mm
	var pm := MultiMesh.new()
	pm.transform_format = MultiMesh.TRANSFORM_3D
	pm.mesh = card_quad()
	pm.instance_count = 0
	pm.custom_aabb = aabb
	pr_mat = ShaderMaterial.new()
	pr_mat.shader = PR_SHADER_CPU if grid else PR_SHADER
	BoardView.apply(pr_mat)
	pr_mat.set_shader_parameter("ppm", ppm)
	pr_mat.set_shader_parameter("px_per_unit", ppm / 1024.0)
	card_mats.append(pr_mat)
	tick_mats.append(pr_mat)
	pr_mmi = MultiMeshInstance3D.new()
	pr_mmi.multimesh = pm
	pr_mmi.material_override = pr_mat
	pr_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pr_mmi)
	sl.v3d_pr_mm = pm
	sl._pr_t0_seen = PackedInt32Array()   # (upload the missiles again into the new MultiMesh)
	sl.upload()


func _men_params(mat: ShaderMaterial, sl) -> void:
	BoardView.apply(mat)
	mat.set_shader_parameter("ppm", ppm)
	mat.set_shader_parameter("px_per_unit", ppm / 1024.0)
	mat.set_shader_parameter("pal_tex", SoldierLayer.palette_texture())
	mat.set_shader_parameter("atlas_shade", load(SoldierLayer.ATLAS_SHADE_PATH) as Texture2D)
	mat.set_shader_parameter("atlas_mask", load(SoldierLayer.ATLAS_MASK_PATH) as Texture2D)
	mat.set_shader_parameter("proc_tex", sl._atlas)
	mat.set_shader_parameter("anim_on", 1.0 if sl.animate else 0.0)
	if SpriteOb.source != "":
		mat.set_shader_parameter("ob_shade", SpriteOb.shade)
		mat.set_shader_parameter("ob_mask", SpriteOb.mask)
		mat.set_shader_parameter("ob_tab", SpriteOb.tab)
		mat.set_shader_parameter("ob_cell", SpriteOb.cells)
		mat.set_shader_parameter("ob_sheet", SpriteOb.sheet)
		mat.set_shader_parameter("ob_maxf", float(SpriteOb.max_frames))
		mat.set_shader_parameter("sheet_ppm", SpriteOb.ppm)
	else:
		var none := PackedVector4Array()
		none.resize(64)
		mat.set_shader_parameter("ob_cell", none)
	card_mats.append(mat)
	tick_mats.append(mat)


# --------------------------------------------------------------------------------------------- the kit

func _build_kits() -> void:
	var list: Array = []
	if battle.city != null and battle.city.kit != null:
		list.append(battle.city.kit)
	var tl = battle.terrain
	if tl != null and tl._land != null and tl._land.get("kit") != null:
		list.append(tl._land.kit)
	for k in list:
		if k.ob_mm == null or k.ob_mat == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = card_quad()
		mm.instance_count = k.ob_mm.instance_count
		mm.custom_aabb = AABB(Vector3(-60.0, ground_lo - 20.0, -60.0), Vector3(field_m.x + 120.0, ground_hi - ground_lo + 120.0, field_m.y + 120.0))
		var mat := ShaderMaterial.new()
		mat.shader = KIT_SHADER if BoardView.fine else KIT_SHADER_CPU
		copy_params(k.ob_mat, mat)
		BoardView.apply(mat)
		mat.set_shader_parameter("ppm", ppm)
		mat.set_shader_parameter("kit_ppm", KitOb.ppm)
		card_mats.append(mat)
		var ld0 = mat.get_shader_parameter("light_dir")
		_kit_ld.append([mat, ld0 if ld0 is Vector3 else PAINT_KEY])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mi)
		kits.append([k, mi, -1, -99])
		if Kit3D.ok():
			_build_meshes(k, mat)
	_solid_mat = ShaderMaterial.new()
	_solid_mat.shader = SOLID_SHADER
	gear_mi = MeshInstance3D.new()
	gear_mi.material_override = _solid_mat
	add_child(gear_mi)
	ship_mi = MeshInstance3D.new()
	ship_mi.material_override = _solid_mat
	add_child(ship_mi)
	refresh_kit(true)


## The kit's rows again when they changed (a gate's state, a fallen house, a breach) or when the camera's yaw crossed into another
## quarter (the sheet pieces' renders); the siege gear each tick it may have moved; the ships when their state changed.
func refresh_kit(force := false) -> void:
	var sector := int(floor((rad_to_deg(BoardView.yaw) + 45.0) / 90.0))
	for e in kits:
		var k = e[0]
		if force or int(e[2]) != int(k.ob_rev) or int(e[3]) != sector or (e[1] as MultiMeshInstance3D).multimesh.instance_count != k.ob_mm.instance_count:
			e[2] = k.ob_rev
			e[3] = sector
			var mm: MultiMesh = (e[1] as MultiMeshInstance3D).multimesh
			mm.instance_count = k.ob_mm.instance_count
			var buf: PackedFloat32Array = k.ob_buffer_3d(float(sector) * 90.0)
			_hide_cards(k, buf)
			if buf.size() == mm.instance_count * 12 and buf.size() > 0:
				mm.buffer = buf
	for km in kit_meshes:
		if force or int(km["rev"]) != int((km["kit"]).ob_rev):
			_fill_meshes(km)
	if sim.n_eq > 0 and (force or sim.tick != _gear_tick) and battle.overlay != null:
		_gear_tick = sim.tick
		# (rebuilt only when a piece moved, turned or changed state: a native hash of the sim's gear arrays)
		var gsig := hash([sim.q_x, sim.q_y, sim.q_state, sim.q_face, sim.q_unit, sim.u_face, sim.u_alive])
		if force or gsig != _gear_sig:
			_gear_sig = gsig
			gear_mi.mesh = battle.overlay.gear_mesh()
	if battle.ships != null and battle.ships.has_method("sig") and (force or battle.ships.sig() != _ship_sig):
		_ship_sig = battle.ships.sig()
		ship_mi.mesh = battle.ships.build_mesh3d()


# --------------------------------------------------------------------------------------------- the kit's meshes (step two)

## The kit's card pieces that have a mesh (game/kit3d.gd) as meshes: a MultiMeshInstance3D per piece kind (TRANSFORM_3D, the
## culture in the custom data), one material for the kit (its palette and look copied from the oblique rows' material).
func _build_meshes(k, kmat: ShaderMaterial) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = KIT_MESH_SHADER
	copy_params(kmat, mat)
	mat.set_shader_parameter("kit_tex", Kit3D.tex)
	var inst := PackedInt32Array()
	var lms: Array = []
	for i in k.i_piece.size():
		var nm: String = KitAtlas.NAMES[k.i_piece[i]]
		if i < k._ob_slot.size() and k._ob_slot[i] >= 0 and Kit3D.has(nm):
			inst.append(i)
	for lm in k._ob_lm:
		if (lm as Array).size() >= 6 and Kit3D.has(str(lm[1])):
			lms.append(lm)
	if inst.is_empty() and lms.is_empty():
		return
	var km := {"kit": k, "mat": mat, "mmis": {}, "rev": -1, "inst": inst, "lm": lms}
	mesh_mats.append(mat)
	kit_meshes.append(km)


## The pieces' rows in the MultiMeshes again (built once, then when the kit's rows change: a fallen house is left out).
func _fill_meshes(km: Dictionary) -> void:
	var k = km["kit"]
	km["rev"] = k.ob_rev
	var rows := {}    # piece -> PackedFloat32Array (16 floats an instance)
	for i in km["inst"]:
		if k.fallen(i):
			continue
		var nm: String = KitAtlas.NAMES[k.i_piece[i]]
		var e: Vector2 = k.i_e[i]
		if nm in DOOR_PIECES and _street_flip(k, i):
			e = -e
		var c := Kit3D.centre(nm)
		var sx: float = k.i_sx[i]
		var sy: float = k.i_sy[i]
		# (the footprint's centre on the instance's place, as the oblique sheet anchors the card)
		var o: Vector2 = k.i_pos[i] - e * (c.x * sx) - Vector2(e.y, -e.x) * (c.y * sy)
		_mesh_row(rows, nm, o, e, sx, sy, sy, float(k.i_cul[i]))
	for lm in km["lm"]:
		var yaw: float = lm[4]
		var sc: float = lm[5]
		_mesh_row(rows, str(lm[1]), lm[3], Vector2(cos(yaw), sin(yaw)), sc, sc, sc, float(k.culture))
	var mmis: Dictionary = km["mmis"]
	for nm in rows:
		var buf: PackedFloat32Array = rows[nm]
		var mi: MultiMeshInstance3D = mmis.get(nm)
		if mi == null:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = Kit3D.mesh(nm)
			mm.custom_aabb = AABB(Vector3(-60.0, ground_lo - 20.0, -60.0), Vector3(field_m.x + 120.0, ground_hi - ground_lo + 140.0, field_m.y + 120.0))
			mi = MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = km["mat"]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			mi.name = "kit3d_" + nm
			add_child(mi)
			mmis[nm] = mi
		mi.multimesh.instance_count = buf.size() / 16
		mi.multimesh.buffer = buf
	for nm in mmis:
		if not rows.has(nm):
			(mmis[nm] as MultiMeshInstance3D).multimesh.instance_count = 0
	mesh_instances = 0
	for e2 in kit_meshes:
		for nm2 in e2["mmis"]:
			mesh_instances += (e2["mmis"][nm2] as MultiMeshInstance3D).multimesh.instance_count


## One instance: the piece's origin `o` (m, the map), its right `e` (a unit vector on the map, y down), scales along its right,
## its depth (toward its outer side) and up; standing on the board's ground under the origin.
func _mesh_row(rows: Dictionary, nm: String, o: Vector2, e: Vector2, sx: float, sy: float, sz: float, cul: float) -> void:
	var g := BoardView.ground_m(o * ppm)
	var bx := Vector3(e.x * sx, 0.0, e.y * sx)
	var by := Vector3(0.0, sz, 0.0)
	var bz := Vector3(-e.y * sy, 0.0, e.x * sy)
	var buf: PackedFloat32Array = rows.get(nm, PackedFloat32Array())
	buf.append_array(PackedFloat32Array([bx.x, by.x, bz.x, o.x, bx.y, by.y, bz.y, g, bx.z, by.z, bz.z, o.y, cul, 0.0, 0.0, 0.0]))
	rows[nm] = buf


## Whether a Rome house's door (its outer side, +y in the kit's frame) should turn round: its own side faces a building, a wall
## or the water a few metres out and the other side the street (the sim's obstacle cells, read only).
func _street_flip(k, i: int) -> bool:
	if sim.obs_on == 0 or MapGen.west_kit(k.lay):
		return false
	var e: Vector2 = k.i_e[i]
	var f := Vector2(e.y, -e.x)
	var o: Vector2 = k.i_pos[i]
	var d := maxf(k.i_sy[i] * 4.0, 3.0) + 2.5
	var a := o + f * d
	var b := o - f * d
	var ka: int = sim.obs_kind(int(a.x * 1024.0), int(a.y * 1024.0))
	var kb: int = sim.obs_kind(int(b.x * 1024.0), int(b.y * 1024.0))
	return ka != MapGen.C_OPEN and ka != MapGen.C_RUBBLE and (kb == MapGen.C_OPEN or kb == MapGen.C_RUBBLE)


## The cards of the pieces drawn as meshes left out of the kit's rows (the row's code 0: no vertex lands on the board).
func _hide_cards(k, buf: PackedFloat32Array) -> void:
	for km in kit_meshes:
		if km["kit"] != k:
			continue
		for i in km["inst"]:
			var sl: int = k._ob_slot[i] if i < k._ob_slot.size() else -1
			if sl >= 0 and sl * 12 + 8 < buf.size():
				buf[sl * 12 + 8] = 0.0
		for lm in km["lm"]:
			var w: int = lm[0]
			var sl2: int = k._ob_wslot[w] if w < k._ob_wslot.size() else -1
			if sl2 >= 0 and sl2 * 12 + 8 < buf.size():
				buf[sl2 * 12 + 8] = 0.0


# --------------------------------------------------------------------------------------------- trees

## The woods and orchards as cards: the tree layer's instances (x, y, radius in world px, the kind code) at their ground height,
## drawn from the oblique kit sheet's tree sprites (its 40 degree renders face the camera at any yaw: a tree reads alike round).
func _build_trees() -> void:
	var tl = battle.trees
	if tl == null or tl.data3d.is_empty() or tl._kit_mat == null or not KitOb.ok():
		return
	var src: PackedFloat32Array = tl.data3d
	var n := src.size() / 16
	var buf := PackedFloat32Array()
	buf.resize(n * 16)
	for i in n:
		var o := i * 16
		var x := src[o + 12]
		var y := src[o + 13]
		var h := BoardView.ground_m(Vector2(x, y))
		buf[o] = 1.0
		buf[o + 3] = x / ppm
		buf[o + 5] = 1.0
		buf[o + 7] = h
		buf[o + 10] = 1.0
		buf[o + 11] = y / ppm
		buf[o + 12] = x
		buf[o + 13] = y
		buf[o + 14] = src[o + 14]
		buf[o + 15] = src[o + 15]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = card_quad()
	mm.instance_count = n
	mm.buffer = buf
	mm.custom_aabb = AABB(Vector3(-40.0, ground_lo - 10.0, -40.0), Vector3(field_m.x + 80.0, ground_hi - ground_lo + 60.0, field_m.y + 80.0))
	tree_mat = ShaderMaterial.new()
	tree_mat.shader = TREE_SHADER
	copy_params(tl._kit_mat, tree_mat)
	if "--v3d-debug" in OS.get_cmdline_user_args():
		print("TREES pidx ", tree_mat.get_shader_parameter("pidx"), " rects0 ", (tree_mat.get_shader_parameter("rects") as PackedVector4Array).slice(0, 4), " anch0 ", (tree_mat.get_shader_parameter("anch") as PackedVector4Array).slice(0, 4), " alb ", tree_mat.get_shader_parameter("albedo_tex"), " code0 ", buf.slice(12, 16))
	tree_mat.set_shader_parameter("ppm", ppm)
	var tld = tree_mat.get_shader_parameter("light_dir")
	_tree_ld = tld if tld is Vector3 else PAINT_KEY
	card_mats.append(tree_mat)
	tree_mmi = MultiMeshInstance3D.new()
	tree_mmi.multimesh = mm
	tree_mmi.material_override = tree_mat
	tree_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(tree_mmi)


## A card: a quad whose corners (its UV, 0..1, v up) the card shaders place in the camera's plane.
static func card_quad() -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.custom_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	return am


## Every uniform of dst's shader that src holds (the 2D layer's built textures and looks).
static func copy_params(src: ShaderMaterial, dst: ShaderMaterial) -> void:
	for u in dst.shader.get_shader_uniform_list():
		var nm := str(u["name"])
		var v = src.get_shader_parameter(nm)
		if v != null:
			dst.set_shader_parameter(nm, v)


## The muzzle flashes and the gun smoke as billboards with depth, the flash's pooled light (game/fx3d.gd).
func _build_fx() -> void:
	fx = Fx3D.new()
	add_child(fx)
	fx.setup(self)


# --------------------------------------------------------------------------------------------- the camera

## Place the Camera3D (and the lamp, the shadow range, the cards' camera terms) from the battle's Camera2D: its canvas transform
## gives the board point at the screen's centre and the zoom; BoardView gives the yaw and the elevation.
func sync_camera() -> void:
	if battle == null or battle.camera == null:
		return
	var c2: Camera2D = battle.camera
	c2.force_update_scroll()
	var ct := get_viewport().canvas_transform
	var vp := get_viewport().get_visible_rect().size
	var z := ct.x.length()
	if z <= 0.0:
		return
	var bc := ct.affine_inverse() * (vp * 0.5)
	var w := BoardView.dir_r * bc.x + BoardView.dir_f * (bc.y / BoardView.ob_c)
	var t3 := Vector3(w.x / ppm, 0.0, w.y / ppm)
	var b := Basis(Vector3.UP, BoardView.yaw) * Basis(Vector3.RIGHT, -deg_to_rad(BoardView.elev_deg))
	cam_size = vp.y / (z * ppm)
	var span := maxf(cam_size * vp.x / maxf(vp.y, 1.0), cam_size)
	var dist := span + (ground_hi - ground_lo) + 60.0
	cam.transform = Transform3D(b, t3 + b.z * dist)
	cam.size = cam_size
	# Near and far hug the ground the camera sees (the screen's half height along the ground's slope in the view, the relief and
	# the tallest pieces either way, the table under the slab): an orthographic camera's directional shadow covers its whole
	# near-far range (Godot ignores directional_shadow_max_distance there), so a loose far spread the shadow map over empty air.
	var e := deg_to_rad(BoardView.elev_deg)
	var hmax := maxf(absf(ground_lo), absf(ground_hi)) + SLAB_BELOW + 30.0
	var reach := cam_size * 0.5 * cos(e) / maxf(sin(e), 0.1) + hmax / maxf(sin(e), 0.1) + 10.0
	cam.near = maxf(1.0, dist - reach)
	cam.far = dist + reach
	lamp.directional_shadow_max_distance = cam.far
	var kd := lamp.transform.basis.z   # (toward the lamp: it shines along its -z)
	# The lamp in the camera's frame: the painted key turned by the camera's yaw against the lamp's (0 at the opening yaw).
	var rel := lamp_yaw - BoardView.yaw if lamp_yaw > -999.0 else 0.0
	var sk := _turn2(Vector2(PAINT_KEY.x, PAINT_KEY.y), rel)
	var side := side_amt * (sk.x - PAINT_KEY.x) / Vector2(PAINT_KEY.x, PAINT_KEY.y).length() * 0.5
	if tree_mat != null:
		var t2 := _turn2(Vector2(_tree_ld.x, _tree_ld.y), rel)
		tree_mat.set_shader_parameter("light_dir", Vector3(t2.x, t2.y, _tree_ld.z))
	for m in mesh_mats:
		m.set_shader_parameter("key_dir", kd)
	for m in card_mats:
		m.set_shader_parameter("cam_r", b.x)
		m.set_shader_parameter("cam_u", b.y)
		m.set_shader_parameter("cam_b", b.z)
		m.set_shader_parameter("cam_yaw", BoardView.yaw)
		m.set_shader_parameter("side_k", side)


## Stand the lamp in the room at yaw y (the battle's opening yaw: called once, at the first camera sync after the battle set its
## view; tests may call it again): its light, the kit's wall faces' key and the Low board's painted hill shade follow it.
func set_lamp(y: float) -> void:
	lamp_yaw = y
	print("view3d: the lamp stands at yaw %.0f (from %.0f degrees, %.1f up)" % [rad_to_deg(y), fposmod(-38.7 - rad_to_deg(y), 360.0), 50.3])
	lamp.transform = Transform3D(Basis(Vector3.UP, y) * _lamp_basis(), Vector3.ZERO)
	for e in _kit_ld:
		var ld: Vector3 = e[1]
		var w := _turn2(Vector2(ld.x, ld.y), y)
		(e[0] as ShaderMaterial).set_shader_parameter("light_dir", Vector3(w.x, w.y, ld.z))
	if terrain_mat != null:
		terrain_mat.set_shader_parameter("fake_ld", _turn2(Vector2(0.6154, 0.7882), y))


## A ground direction (x, y: the 2D world's or the screen's, y toward the viewer at yaw 0) turned as Basis(UP, a) turns (x, z).
static func _turn2(v: Vector2, a: float) -> Vector2:
	return Vector2(v.x * cos(a) + v.y * sin(a), -v.x * sin(a) + v.y * cos(a))


static func _lamp_basis() -> Basis:
	var d := LAMP_DIR.normalized()
	return Basis.looking_at(d, Vector3.UP)


## The Paths overlay (game/city_layer.gd set_paths_alpha builds and fades it) drawn by the board's shader.
var _paths_tex: Texture2D = null


func _build_ground_canvas() -> void:
	var tl = battle.terrain
	var city_on: bool = sim.city_on != 0 and sim.map_info is Dictionary and sim.map_info.has("city")
	if not city_on or terrain_mat == null:
		return
	var fpx: Vector2 = BoardView.field_px
	var sc := minf(0.5, 4096.0 / maxf(fpx.x, fpx.y))
	_gc_vp = SubViewport.new()
	_gc_vp.size = Vector2i(maxi(int(fpx.x * sc), 1), maxi(int(fpx.y * sc), 1))
	_gc_vp.transparent_bg = true
	_gc_vp.disable_3d = true
	_gc_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_gc_node = _GroundDraw.new()
	_gc_node.sim = sim
	_gc_node.k = ppm
	_gc_node.plan = CityDraw.plan_surround(sim)
	var pal_i := int(sim.ter_info.get("palette", 0))
	_gc_node.base = GroundPalette.get_palette(pal_i)["base"]
	_gc_node.pal_i = pal_i
	_gc_node.low = Quality.is_low()
	_gc_node.board = BattleLook.is_diorama() and not ("--no-splat" in OS.get_cmdline_user_args())
	_gc_node.decals = tl != null and tl._decals != null
	_gc_vp.add_child(_gc_node)
	add_child(_gc_vp)
	_gc_vp.canvas_transform = Transform2D.IDENTITY.scaled(Vector2(sc, sc))   # (once in the tree: its canvas exists)
	_gc_rub = sim.rub_n
	_gc_node.cells = CityDraw.rubble_cells(sim)
	terrain_mat.set_shader_parameter("gc_tex", _gc_vp.get_texture())
	terrain_mat.set_shader_parameter("gc_rect", Vector4(0.0, 0.0, fpx.x, fpx.y))


func _ground_canvas_refresh() -> void:
	if _gc_vp == null or sim.rub_n == _gc_rub:
		return
	_gc_rub = sim.rub_n
	_gc_node.cells = CityDraw.rubble_cells(sim)
	_gc_node.queue_redraw()
	_gc_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


class _GroundDraw extends Node2D:
	var sim
	var k := 10.0
	var plan: Dictionary = {}
	var base := Color(0.3, 0.4, 0.2)
	var pal_i := 0
	var low := false
	var board := false
	var decals := true
	var cells := PackedInt32Array()

	func _draw() -> void:
		if decals:
			CityDraw.draw_surround(self, plan, k, Vector2.ZERO, base, pal_i, low, board)
		CityDraw.draw_sea_passage(self, sim, k, Vector2.ZERO)
		if not cells.is_empty():
			CityDraw.draw_rubble(self, sim, cells, k, Vector2.ZERO, false)


func _paths() -> void:
	var cl = battle.city
	if cl == null or terrain_mat == null:
		return
	var pn: Sprite2D = cl.paths_node
	var a: float = cl.paths_alpha if pn != null and pn.visible else 0.0
	if pn != null and pn.texture != _paths_tex:
		_paths_tex = pn.texture
		terrain_mat.set_shader_parameter("paths_tex", _paths_tex)
		var tsz := _paths_tex.get_size() * pn.scale
		terrain_mat.set_shader_parameter("paths_rect", Vector4(pn.position.x, pn.position.y, tsz.x, tsz.y))
		terrain_mat.set_shader_parameter("paths_period", ppm * 0.9)
	terrain_mat.set_shader_parameter("paths_alpha", a)


func _probe() -> void:
	var best := -1
	for u in sim.n_units:
		if sim.u_alive[u] > 0 and (best < 0 or sim.u_alive[u] > sim.u_alive[best]):
			best = u
	if best < 0:
		return
	men_mmi.layers |= PROBE_LAYER
	var vp := SubViewport.new()
	vp.size = Vector2i(PROBE_PX, PROBE_PX)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var pc := Camera3D.new()
	pc.projection = Camera3D.PROJECTION_ORTHOGONAL
	pc.size = 64.0
	pc.cull_mask = PROBE_LAYER
	pc.near = 1.0
	pc.far = 2000.0
	var w := Vector2(sim.u_cx[best], sim.u_cy[best]) / 1024.0
	var c := Vector3(w.x, BoardView.ground_m(w * ppm), w.y)
	pc.transform = Transform3D(cam.transform.basis, c + cam.transform.basis.z * 300.0)
	vp.add_child(pc)
	add_child(vp)
	pc.make_current()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var drawn := 0
	var img := vp.get_texture().get_image()
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
		var px := img.get_data()
		for i in range(3, px.size(), 4):
			if px[i] > 64:
				drawn += 1
	vp.queue_free()
	men_mmi.layers &= ~PROBE_LAYER
	if "--v3d-probe-fail" in OS.get_cmdline_user_args() and men_mat.shader == MEN_SHADER:
		drawn = 0
	probe_drawn = drawn
	var men := int(sim.u_alive[best])
	var path := "v3d-cpu" if men_mat.shader == MEN_SHADER_CPU else "v3d-gpu"
	print("V3D_PROBE drawn=%d men=%d path=%s" % [drawn, men, path])
	var sl = battle.soldiers
	if sl != null:
		sl.probed.emit(drawn, men, path)
	if drawn == 0 and men > 0 and men_mat.shader == MEN_SHADER:
		_use_compatible()
		if SoldierLayer.forced_path() == "":
			SoldierLayer.save_pref("cpu")
		_probe_frames = 0


## The compatible shaders from now on (the coarse lift grid in every vertex stage; the board keeps its mesh this battle).
func _use_compatible() -> void:
	BoardView.use_grid()
	men_mat.shader = MEN_SHADER_CPU
	base_mat.shader = BASE_SHADER_CPU
	pr_mat.shader = PR_SHADER_CPU
	for e in kits:
		((e[1] as MultiMeshInstance3D).material_override as ShaderMaterial).shader = KIT_SHADER_CPU
	for m in [men_mat, base_mat, pr_mat]:
		BoardView.apply(m)
	for km in kit_meshes:
		km["rev"] = -1   # (the meshes on the coarse grid's ground)


func set_shadows(on: bool) -> void:
	shadows = on
	lamp.shadow_enabled = on
	if terrain_mat != null:
		terrain_mat.set_shader_parameter("fake_lamp", 0.0 if on else 1.0)


func _process(_delta: float) -> void:
	if _probe_frames >= 0:
		_probe_frames += 1
		if _probe_frames >= PROBE_FRAMES:
			_probe_frames = -1
			if DisplayServer.get_name() != "headless" and men_mmi != null:
				_probe()
	if lamp_yaw < -999.0:
		set_lamp(BoardView.yaw)   # (the first frame: the battle has set its opening view)
	sync_camera()
	if fx != null:
		fx.update()
	refresh_kit()
	_paths()
	_ground_canvas_refresh()
	var sl = battle.soldiers if battle != null else null
	if sl != null and sim != null:
		var a: float = sl.alpha
		var now := float(sim.tick) - 1.0 + a
		for m in tick_mats:
			m.set_shader_parameter("alpha", a)
			m.set_shader_parameter("now", now)
