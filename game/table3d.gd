extends RefCounted
## The 3D battle room's builders (view only; docs/design/art_pipeline.md "The room: table3d.gd"): the environment, the world lamp,
## the wooden table and the board's cut slab, as static functions so the land battle's view (game/view3d.gd) and the sea battle's
## (game/sea_view3d.gd) stand their boards in the same room. Nothing here reads a sim or BoardView: a caller passes the sizes.

const TABLE_SHADER := preload("res://game/table3d.gdshader")
const SLAB_SHADER := preload("res://game/board_slab3d.gdshader")

const AMBIENT := 0.42
const LAMP := 1.0
## The lamp at yaw 0 (the direction its light travels): see View3D.LAMP_DIR.
const LAMP_DIR := Vector3(0.40, -0.77, 0.50)
## The lamp's first shadow split, a share of the camera's near-far range.
const SHADOW_SPLIT := 0.5
const SLAB_BELOW := 3.0          # metres of board under its lowest ground
const TABLE_BELOW := 0.05        # the table just under the slab's foot


static func lamp_basis() -> Basis:
	var d := LAMP_DIR.normalized()
	return Basis.looking_at(d, Vector3.UP)


## The environment and the lamp, added to `host`: {"env": Environment, "lamp": DirectionalLight3D}.
static func build_env(host: Node, shadows: bool) -> Dictionary:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.09, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.6, 0.66)
	env.ambient_light_energy = AMBIENT
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	host.add_child(we)
	var lamp := DirectionalLight3D.new()
	lamp.light_energy = LAMP
	lamp.light_color = Color(1.0, 0.95, 0.86)
	lamp.shadow_enabled = shadows
	# Two splits over the camera's near-far range (the view's sync_camera fits it to the ground in view): the near half of the ground
	# (the screen's lower half) gets its own map (art_pipeline.md "The 3D battle view: the world lamp").
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
	lamp.transform = Transform3D(lamp_basis(), Vector3.ZERO)
	host.add_child(lamp)
	return {"env": env, "lamp": lamp}


## The board's cut sides as one mesh: `edges` are [run of Vector3 points along the top, outward normal] (the land's four edges),
## each dropped to `foot`.
static func slab_mesh(edges: Array, foot: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
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
	return am


## The slab's material. `flock` (a Vector3 or null): the lip's colour; `resin` (a Vector3 or null): a cast-resin board (the sea's):
## the layers above the base strip read as the resin over its painted bed in this colour.
static func slab_material(band_m: float, foot: float, flock = null, resin = null) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SLAB_SHADER
	mat.set_shader_parameter("band_m", band_m)
	mat.set_shader_parameter("foot_y", foot)
	if flock is Vector3:
		mat.set_shader_parameter("flock_col", flock)
	if resin is Vector3:
		mat.set_shader_parameter("resin_k", 1.0)
		mat.set_shader_parameter("resin_col", resin)
	return mat


## The wooden table: a plane `size` metres square centred at `centre` (its y is the table's top), the board's rectangle
## (x0, z0, x1, z1) lit by the lamp's pool.
static func table(centre: Vector3, board_rect: Vector4, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	mi.mesh = pm
	mi.position = centre
	var mat := ShaderMaterial.new()
	mat.shader = TABLE_SHADER
	mat.set_shader_parameter("board_rect", board_rect)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
