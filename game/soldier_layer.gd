extends Node2D
## Renders all soldiers with two MultiMeshInstance2D nodes (corpses below,
## living above) that share one MultiMesh and one data texture. Per tick the
## sim's packed int arrays are copied into the texture with native calls only;
## the shader decodes and interpolates them (see soldiers.gdshader).

const SHADER := preload("res://game/soldiers.gdshader")
const TEX_W := 1024
const BLOCKS := 8
const QUAD_M := 1.6  # sprite quad size in metres

var px_per_m: float = 10.0
var sim  # BattleSim (untyped to keep the view decoupled)
var selected_unit: int = -1

var _mm: MultiMesh
var _layers: Array[MultiMeshInstance2D] = []
var _materials: Array[ShaderMaterial] = []
var _image: Image
var _tex: ImageTexture
var _rows: int = 1
var _bytes := PackedByteArray()
var _flags := PackedInt32Array()


func setup(p_sim, p_px_per_m: float) -> void:
	sim = p_sim
	px_per_m = p_px_per_m
	var n: int = sim.n
	_rows = maxi(1, (maxi(n, sim.n_units) + TEX_W - 1) / TEX_W)
	_bytes.resize(BLOCKS * _rows * TEX_W * 4)
	_image = Image.create_from_data(TEX_W, BLOCKS * _rows, false, Image.FORMAT_RGBA8, _bytes)
	_tex = ImageTexture.create_from_image(_image)
	_flags.resize(sim.n_units)

	var quad := px_per_m * QUAD_M
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.mesh = _make_quad(quad)
	_mm.instance_count = n
	for i in n:
		_mm.set_instance_transform_2d(i, Transform2D.IDENTITY)
	# All instance transforms are identity (the shader places soldiers), so
	# give the MultiMesh bounds covering the whole field to avoid culling.
	var fw: float = sim.field_w / 1024.0 * px_per_m
	var fh: float = sim.field_h / 1024.0 * px_per_m
	_mm.custom_aabb = AABB(Vector3(-quad, -quad, -1.0), Vector3(fw + 2.0 * quad, fh + 2.0 * quad, 2.0))

	var sprite := _make_sprite_texture()
	for pass_id in 2:
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("data_tex", _tex)
		mat.set_shader_parameter("rows_per_block", _rows)
		mat.set_shader_parameter("tex_width", TEX_W)
		mat.set_shader_parameter("px_per_unit", px_per_m / 1024.0)
		mat.set_shader_parameter("layer_pass", pass_id)
		var mmi := MultiMeshInstance2D.new()
		mmi.multimesh = _mm
		mmi.texture = sprite
		mmi.material = mat
		add_child(mmi)
		_layers.append(mmi)
		_materials.append(mat)
	upload()


## Copy the sim arrays into the data texture. Call once after each tick.
func upload() -> void:
	var block := _rows * TEX_W * 4
	var nu: int = sim.n_units
	for u in nu:
		_flags[u] = (sim.u_side[u] & 1) | (2 if u == selected_unit else 0)
	var arrays: Array = [sim.pos_x, sim.pos_y, sim.prev_x, sim.prev_y, sim.facing,
		sim.state, sim.unit_of, _flags]
	var out := PackedByteArray()
	for k in BLOCKS:
		var b: PackedByteArray = (arrays[k] as PackedInt32Array).to_byte_array()
		out.append_array(b)
		if b.size() < block:
			var pad := PackedByteArray()
			pad.resize(block - b.size())
			out.append_array(pad)
	_image.set_data(TEX_W, BLOCKS * _rows, false, Image.FORMAT_RGBA8, out)
	_tex.update(_image)


func set_alpha(a: float) -> void:
	for m in _materials:
		m.set_shader_parameter("alpha", a)


func _make_quad(size: float) -> ArrayMesh:
	var h := size * 0.5
	var verts := PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Top-down placeholder soldier facing +x (right): shoulders seen from
## above, a head, a shield bar across the front and a weapon on the right
## hand side (+y). Greyscale so the shader can tint it per side and state.
static func _make_sprite_texture() -> ImageTexture:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			var col := Color(0, 0, 0, 0)
			# Shoulders: ellipse, narrow front-to-back, wide side-to-side.
			var e := Vector2((p.x - 14.0) / 6.5, (p.y - 16.0) / 10.5)
			var el := e.length()
			if el <= 1.0:
				col = Color(0.72, 0.72, 0.72) if el < 0.82 else Color(0.18, 0.18, 0.18)
			# Head.
			var hd := p.distance_to(Vector2(15.0, 16.0))
			if hd <= 4.2:
				col = Color(0.95, 0.95, 0.95) if hd < 3.3 else Color(0.2, 0.2, 0.2)
			# Shield bar across the front.
			if x >= 21 and x <= 24 and y >= 5 and y <= 26:
				var edge := x == 21 or x == 24 or y == 5 or y == 26
				col = Color(0.15, 0.15, 0.15) if edge else Color(1, 1, 1)
			# Weapon held forward on the right hand side.
			if x >= 16 and x <= 31 and y >= 25 and y <= 26:
				col = Color(0.9, 0.9, 0.9)
			if col.a > 0.0:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)
