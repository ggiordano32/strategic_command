extends Node2D
## The ground under the battle: one rectangle over the field drawn by
## terrain.gdshader from a height texture built once here from the sim's
## height grid (view only; reads sim.ter_h, never writes the sim).
##
## The sim grid has 4 m nodes; the texture doubles that to 2 m with a
## Catmull-Rom midpoint rule ((-a + 9b + 9c - d) / 16, separable), so the
## contours stay smooth when zoomed in. Hill shade is computed here from the
## same 2 m heights (light from the upper left) and stored in the blue
## channel; the shader interpolates it, so the shading has no facets. Valley
## floors (ground lower than the 24 m around it) are darkened a little in the
## same channel. Colours come from the map's ground palette
## (game/ground_palette.gd, sim.ter_info["palette"]); woods, settlement
## ground, streets, plaza and fields from the sim's vegetation grid go into a
## second, 4 m texture.

const SHADER := preload("res://game/terrain.gdshader")
const GroundPalette := preload("res://game/ground_palette.gd")
const MapGen := preload("res://sim/mapgen.gd")
const NODE_M := 2.0                       # texture node spacing (metres)
const LIGHT := Vector3(-0.55, -0.7, 0.85) # from the upper left, fairly high
const RELIEF_EXAGGERATE := 3.4            # shading reads on gentle slopes too
const SHADE_K := 0.6                      # brightness range of the hill shading
const VALLEY_R := 12                      # nodes (24 m): valley = lower than the mean round it
const VALLEY_K := 0.09                    # shade per metre below that mean ...
const VALLEY_MAX := 0.28                  # ... at most

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
	var pal := GroundPalette.get_palette(int(sim.ter_info.get("palette", 0)))
	var base: Color = pal["base"]
	var line: Color = pal["line"]
	m.set_shader_parameter("base_col", Vector3(base.r, base.g, base.b))
	m.set_shader_parameter("low_col", _v3(pal["low"]))
	m.set_shader_parameter("high_col", _v3(pal["high"]))
	m.set_shader_parameter("line_col", Vector4(line.r, line.g, line.b, line.a))
	m.set_shader_parameter("major_col", Vector4(line.r * 0.8, line.g * 0.8, line.b * 0.8, minf(line.a * 1.55, 0.6)))
	m.set_shader_parameter("wood_col", Vector3(base.r * 0.55, base.g * 0.68, base.b * 0.5))
	m.set_shader_parameter("pave_col", Vector3(base.r * 0.4 + 0.33, base.g * 0.35 + 0.33, base.b * 0.3 + 0.3))
	m.set_shader_parameter("field_col", Vector3(minf(base.r * 0.6 + 0.38, 1.0), minf(base.g * 0.55 + 0.36, 1.0), base.b * 0.5 + 0.18))
	_build_veg()
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
	var valley := _valley_depth()
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
			s -= minf(valley[k] * VALLEY_K, VALLEY_MAX)
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
	m.set_shader_parameter("shade_k", SHADE_K)
	# The tint spans the map's own relief, so low and high ground read
	# apart on gentle maps too.
	m.set_shader_parameter("tint_span_m", clampf(range_m * 0.55, 5.0, 22.0))
	# Heights in the texture start at lo (0 for sim maps).
	m.set_shader_parameter("h_mid_m", sum / heights.size() - lo)
	m.set_shader_parameter("h_base_m", _commonest(lo) - lo)
	m.set_shader_parameter("terrain_on", true)


static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


## How far each 2 m node lies below the mean height within VALLEY_R nodes
## round it (metres, 0 if above): two separable box blurs with running sums.
func _valley_depth() -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(nx * ny)
	var r := VALLEY_R
	for j in ny:
		var row := j * nx
		var acc := 0.0
		var cnt := 0
		for i in mini(r, nx):
			acc += heights[row + i]
			cnt += 1
		for i in nx:
			if i + r < nx:
				acc += heights[row + i + r]
				cnt += 1
			if i - r - 1 >= 0:
				acc -= heights[row + i - r - 1]
				cnt -= 1
			tmp[row + i] = acc / cnt
	var out := PackedFloat32Array()
	out.resize(nx * ny)
	for i in nx:
		var acc2 := 0.0
		var cnt2 := 0
		for j in mini(r, ny):
			acc2 += tmp[j * nx + i]
			cnt2 += 1
		for j in ny:
			if j + r < ny:
				acc2 += tmp[(j + r) * nx + i]
				cnt2 += 1
			if j - r - 1 >= 0:
				acc2 -= tmp[(j - r - 1) * nx + i]
				cnt2 -= 1
			out[j * nx + i] = maxf(acc2 / cnt2 - heights[j * nx + i], 0.0)
	return out


## Ground features texture from the sim's 4 m vegetation grid.
func _build_veg() -> void:
	var m := material_ref
	var vw: int = sim.veg_w
	var vh: int = sim.veg_h
	if sim.map_on == 0 or vw <= 0 or vh <= 0 or sim.veg.size() < vw * vh:
		m.set_shader_parameter("veg_on", false)
		return
	var bytes := PackedByteArray()
	bytes.resize(vw * vh * 4)
	var veg: PackedByteArray = sim.veg
	for k in vw * vh:
		var b := veg[k]
		var o := k * 4
		bytes[o] = (b & MapGen.V_DENS) * 85
		bytes[o + 1] = 255 if (b & MapGen.V_URBAN) != 0 else 0
		bytes[o + 2] = 255 if (b & MapGen.V_FIELD) != 0 else 0
		bytes[o + 3] = 255 if (b & MapGen.V_PLAZA) != 0 else (130 if (b & MapGen.V_ROAD) != 0 else 0)
	var img := Image.create_from_data(vw, vh, false, Image.FORMAT_RGBA8, bytes)
	m.set_shader_parameter("vegmap", ImageTexture.create_from_image(img))
	m.set_shader_parameter("veg_size_px", Vector2(vw, vh) * 4.0 * px_per_m)
	m.set_shader_parameter("veg_on", true)
	# The sea and a ditch (settlement maps only): a second small texture,
	# R sea, G ditch; nothing is bound on other maps.
	var any := false
	var sb := PackedByteArray()
	sb.resize(vw * vh * 2)
	for k in vw * vh:
		var b2 := veg[k]
		if (b2 & MapGen.V_WATER) != 0:
			sb[k * 2] = 255
			any = true
		if (b2 & MapGen.V_DITCH) != 0:
			sb[k * 2 + 1] = 255
			any = true
	m.set_shader_parameter("sea_on", any)
	if any:
		var simg := Image.create_from_data(vw, vh, false, Image.FORMAT_RG8, sb)
		m.set_shader_parameter("seamap", ImageTexture.create_from_image(simg))
		var base: Color = GroundPalette.get_palette(int(sim.ter_info.get("palette", 0)))["base"]
		m.set_shader_parameter("sea_col", Vector3(0.16 + base.r * 0.1, 0.33 + base.g * 0.1, 0.46 + base.b * 0.05))


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
