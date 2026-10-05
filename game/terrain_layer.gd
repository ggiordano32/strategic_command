extends Node2D
## The ground under the battle: one rectangle over the field drawn by
## terrain.gdshader from a height texture built once here from the sim's
## height grid (view only; reads sim.ter_h, never writes the sim).
##
## The sim grid has 4 m nodes; the texture doubles that to 2 m with a
## Catmull-Rom midpoint rule ((-a + 9b + 9c - d) / 16, separable), so the
## contours stay smooth when zoomed in. Hill shade is computed here from the
## same 2 m heights (light from the upper left) and stored in the blue
## channel; the shader interpolates it, so the shading has no facets.

const SHADER := preload("res://game/terrain.gdshader")
const NODE_M := 2.0                       # texture node spacing (metres)
const LIGHT := Vector3(-0.55, -0.7, 0.85) # from the upper left, fairly high
const RELIEF_EXAGGERATE := 2.5            # shading reads on gentle slopes too

var sim
var px_per_m := 10.0
var rect: ColorRect
var material_ref: ShaderMaterial
## Heights at 2 m nodes in metres (view use: tests, overlay hints).
var heights := PackedFloat32Array()
var nx := 2
var ny := 2
var build_ms := 0.0


func setup(p_sim, p_px_per_m: float) -> void:
	sim = p_sim
	px_per_m = p_px_per_m
	rect = ColorRect.new()
	rect.size = Vector2(sim.field_w, sim.field_h) / 1024.0 * px_per_m
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	material_ref = ShaderMaterial.new()
	material_ref.shader = SHADER
	rect.material = material_ref
	add_child(rect)
	var t0 := Time.get_ticks_usec()
	_build()
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _build() -> void:
	var m := material_ref
	m.set_shader_parameter("grid_px", 50.0 * px_per_m)
	if sim.ter_on == 0:
		var img0 := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img0.fill(Color8(0, 0, 128, 255))
		m.set_shader_parameter("hmap", ImageTexture.create_from_image(img0))
		m.set_shader_parameter("hmap_size", Vector2i(2, 2))
		m.set_shader_parameter("terrain_on", false)
		return
	var snx: int = sim.ter_nx
	var sny: int = sim.ter_ny
	var src := PackedFloat32Array()
	src.resize(snx * sny)
	var hmax := 0.0
	for k in snx * sny:
		var v: float = sim.ter_h[k] / 1024.0
		src[k] = v
		hmax = maxf(hmax, v)
	# 2x along x, then along y.
	nx = snx * 2 - 1
	ny = sny * 2 - 1
	var rows := PackedFloat32Array()
	rows.resize(nx * sny)
	for j in sny:
		var o := j * snx
		var r := j * nx
		for i in snx:
			rows[r + 2 * i] = src[o + i]
			if i < snx - 1:
				var a := src[o + maxi(i - 1, 0)]
				var b := src[o + i]
				var c := src[o + i + 1]
				var d := src[o + mini(i + 2, snx - 1)]
				rows[r + 2 * i + 1] = (-a + 9.0 * b + 9.0 * c - d) / 16.0
	heights.resize(nx * ny)
	for i in nx:
		for j in sny:
			heights[(2 * j) * nx + i] = rows[j * nx + i]
			if j < sny - 1:
				var a := rows[maxi(j - 1, 0) * nx + i]
				var b := rows[j * nx + i]
				var c := rows[(j + 1) * nx + i]
				var d := rows[mini(j + 2, sny - 1) * nx + i]
				heights[(2 * j + 1) * nx + i] = (-a + 9.0 * b + 9.0 * c - d) / 16.0
	var lo := heights[0]
	var hi := heights[0]
	var sum := 0.0
	for v in heights:
		lo = minf(lo, v)
		hi = maxf(hi, v)
		sum += v
	var range_m := maxf(hi - lo, 0.01)
	var light := LIGHT.normalized()
	var flat_l := light.z
	var bytes := PackedByteArray()
	bytes.resize(nx * ny * 4)
	var inv := 1.0 / (2.0 * NODE_M)
	for j in ny:
		var jm := maxi(j - 1, 0)
		var jp := mini(j + 1, ny - 1)
		for i in nx:
			var k := j * nx + i
			var h := heights[k]
			var q := int(round((h - lo) / range_m * 65535.0))
			var gx := (heights[j * nx + mini(i + 1, nx - 1)] - heights[j * nx + maxi(i - 1, 0)]) * inv
			var gy := (heights[jp * nx + i] - heights[jm * nx + i]) * inv
			var n := Vector3(-gx * RELIEF_EXAGGERATE, -gy * RELIEF_EXAGGERATE, 1.0).normalized()
			var s := n.dot(light) / flat_l - 1.0
			var o4 := k * 4
			bytes[o4] = q >> 8
			bytes[o4 + 1] = q & 255
			bytes[o4 + 2] = clampi(int(round(128.0 + s * 160.0)), 0, 255)
			bytes[o4 + 3] = 255
	var img := Image.create_from_data(nx, ny, false, Image.FORMAT_RGBA8, bytes)
	m.set_shader_parameter("hmap", ImageTexture.create_from_image(img))
	m.set_shader_parameter("hmap_size", Vector2i(nx, ny))
	m.set_shader_parameter("texel_px", NODE_M * px_per_m)
	m.set_shader_parameter("h_range_m", range_m)
	# Heights in the texture start at lo (0 for sim maps).
	m.set_shader_parameter("h_mid_m", sum / heights.size() - lo)
	m.set_shader_parameter("h_base_m", _commonest(lo) - lo)
	m.set_shader_parameter("terrain_on", true)


## The most common height (to 0.1 m): the plain, if the map has one.
func _commonest(lo: float) -> float:
	var hist := {}
	var best := 0
	var best_n := 0
	for v in heights:
		var b := int(floor((v - lo) * 10.0))
		var c: int = hist.get(b, 0) + 1
		hist[b] = c
		if c > best_n or (c == best_n and b < best):
			best = b
			best_n = c
	return lo + (best + 0.5) / 10.0


## Ground height in metres at a world pixel position (view use).
func height_m_at(p: Vector2) -> float:
	if sim == null or sim.ter_on == 0:
		return 0.0
	var x := int(p.x / px_per_m * 1024.0)
	var y := int(p.y / px_per_m * 1024.0)
	return sim.height_at(x, y) / 1024.0
