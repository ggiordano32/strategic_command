extends Node2D
## Trees over the battlefield (view only): one MultiMesh of top-down tree
## sprites placed once per battle from the sim's vegetation grid (sim.veg, 4 m
## cells, density 1-3), with a view-side RNG seeded from the map's hash so
## every peer sees the same trees (the sim does not care). Orchards (the
## settlement's "fields" of kind 1) are planted in rows. Kinds and shades
## follow the ground palette: olive and scrub on arid / dry ground, oak and
## pine on green / rocky ground.
##
## Canopies fade (to ~35%) over soldiers: after each sim tick the units'
## boxes are marked in a small occupancy texture (4 m cells) that the tree
## shader samples. No per-frame work on the CPU.

const SHADER := preload("res://game/trees.gdshader")
const GroundPalette := preload("res://game/ground_palette.gd")
const MapGen := preload("res://sim/mapgen.gd")

const KINDS := 4               # atlas cells: 0 broadleaf, 1 pine, 2 olive / scrub, 3 cypress
const CELL_PX := 64            # atlas cell size
const MAX_TREES := 40000
## Trees per 4 m cell by density (x 100) and canopy radius range (m).
const PER_CELL := [0, 45, 105, 165]
const R_MIN := [0.0, 1.8, 2.1, 2.4]
const R_MAX := [0.0, 2.8, 3.3, 3.8]

static var _atlas_cache: ImageTexture = null

var sim
var px_per_m := 10.0
var count := 0
var build_ms := 0.0
var update_us := 0
var _mmi: MultiMeshInstance2D
var _mat: ShaderMaterial
var _occ_bytes := PackedByteArray()
var _occ_img: Image
var _occ_tex: ImageTexture
var _rng := 1


func setup(p_sim, p_px_per_m: float) -> void:
	sim = p_sim
	px_per_m = p_px_per_m
	if sim.veg_on == 0:
		return
	var t0 := Time.get_ticks_usec()
	_build()
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0


func _rand() -> int:
	_rng = (_rng * 1103515245 + 12345) & 0x7FFFFFFF
	return _rng >> 8


func _randf() -> float:
	return float(_rand() % 10000) / 10000.0


func _build() -> void:
	var pal_i: int = int(sim.ter_info.get("palette", 0))
	var pal := GroundPalette.get_palette(pal_i)
	# Kinds for this ground: [kind, weight %] pairs.
	var kinds: Array = [[0, 100]]
	match pal_i:
		MapGen.PAL_ARID:
			kinds = [[2, 75], [3, 10], [0, 15]]
		MapGen.PAL_DRY:
			kinds = [[2, 50], [0, 30], [3, 20]]
		MapGen.PAL_GREEN:
			kinds = [[0, 70], [1, 30]]
		MapGen.PAL_ROCKY:
			kinds = [[1, 65], [0, 35]]
	var orchard_kind := 2 if pal_i == MapGen.PAL_ARID or pal_i == MapGen.PAL_DRY else 0
	_rng = (int(sim.ter_hash) & 0x7FFFFFFF) | 1
	var vw: int = sim.veg_w
	var vh: int = sim.veg_h
	var veg: PackedByteArray = sim.veg
	# Orchard rectangles (metres).
	var orchards: Array = []
	if sim.map_info.has("city"):
		for f in sim.map_info["city"]["fields"]:
			if int(f[4]) == 1:
				orchards.append(Rect2(f[0], f[1], int(f[2]) - int(f[0]), int(f[3]) - int(f[1])))
	var data := PackedFloat32Array()
	var k := px_per_m
	for j in vh:
		for i in vw:
			var d: int = veg[j * vw + i] & MapGen.V_DENS
			if d == 0:
				continue
			var cx := i * 4.0 + 2.0
			var cy := j * 4.0 + 2.0
			var in_orchard := false
			for o in orchards:
				if (o as Rect2).has_point(Vector2(cx, cy)):
					in_orchard = true
					break
			if in_orchard:
				continue
			var n := int(PER_CELL[d]) / 100
			if _rand() % 100 < int(PER_CELL[d]) % 100:
				n += 1
			for q in n:
				var x := i * 4.0 + _randf() * 4.0
				var y := j * 4.0 + _randf() * 4.0
				var kd := _pick(kinds)
				var r := lerpf(R_MIN[d], R_MAX[d], _randf())
				if kd == 2:
					r *= 0.75  # olives and scrub are smaller
				elif kd == 3:
					r *= 0.6   # cypresses are narrow
				_push(data, x * k, y * k, r * k, kd, _rand() % 3, _rand() % 8)
				if data.size() / 16 >= MAX_TREES:
					break
	for o in orchards:
		var rc: Rect2 = o
		var yy := rc.position.y + 3.0
		while yy < rc.end.y - 1.0:
			var xx := rc.position.x + 3.0
			while xx < rc.end.x - 1.0:
				_push(data, (xx + _randf() * 0.6) * k, (yy + _randf() * 0.6) * k, (1.5 + _randf() * 0.4) * k,
					orchard_kind, 1, _rand() % 8)
				xx += 6.0
			yy += 6.0
	count = data.size() / 16
	if count == 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = _make_quad()
	mm.instance_count = count
	mm.buffer = data
	var fw: float = sim.field_w / 1024.0 * px_per_m
	var fh: float = sim.field_h / 1024.0 * px_per_m
	mm.custom_aabb = AABB(Vector3(-20, -20, -1), Vector3(fw + 40, fh + 40, 2))
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("atlas", _atlas())
	_mat.set_shader_parameter("kinds", float(KINDS))
	var shades: Array = pal["trees"]
	for s in 3:
		var c: Color = shades[mini(s, shades.size() - 1)]
		_mat.set_shader_parameter("shade%d" % s, Vector3(c.r, c.g, c.b))
	_occ_bytes.resize(vw * vh)
	_occ_bytes.fill(0)
	_occ_img = Image.create_from_data(vw, vh, false, Image.FORMAT_L8, _occ_bytes)
	_occ_tex = ImageTexture.create_from_image(_occ_img)
	_mat.set_shader_parameter("occ", _occ_tex)
	_mat.set_shader_parameter("occ_size_px", Vector2(vw, vh) * 4.0 * px_per_m)
	_mmi = MultiMeshInstance2D.new()
	_mmi.multimesh = mm
	_mmi.material = _mat
	add_child(_mmi)
	update_occupancy()


func _pick(kinds: Array) -> int:
	var r := _rand() % 100
	for kv in kinds:
		r -= int(kv[1])
		if r < 0:
			return int(kv[0])
	return int(kinds[0][0])


## One instance in the MultiMesh buffer: transform (identity, unused: the
## shader places the quad), colour (unused), custom (x, y, radius, packed
## kind / shade / rotation step).
static func _push(data: PackedFloat32Array, x: float, y: float, r: float, kind: int, shade: int, rot: int) -> void:
	data.append_array([1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0,
		x, y, r, float(kind + shade * 4 + rot * 16)])


## Mark the cells under every unit on the field (its box, a cell of margin;
## scattered routers soldier by soldier). Call after each sim tick.
func update_occupancy() -> void:
	if _occ_tex == null:
		return
	var t0 := Time.get_ticks_usec()
	_occ_bytes.fill(0)
	var vw: int = sim.veg_w
	var vh: int = sim.veg_h
	for u in sim.n_units:
		if sim.u_alive[u] <= 0 or sim.u_state[u] >= 2:
			continue
		var i0: int = maxi((sim.u_minx[u] >> 12) - 1, 0)
		var i1: int = mini((sim.u_maxx[u] >> 12) + 1, vw - 1)
		var j0: int = maxi((sim.u_miny[u] >> 12) - 1, 0)
		var j1: int = mini((sim.u_maxy[u] >> 12) + 1, vh - 1)
		if (i1 - i0) * (j1 - j0) > 400:
			var base: int = sim.u_slot_base[u]
			for s in sim.u_alive[u]:
				var p: int = sim.slot_soldier[base + s]
				var ci: int = clampi(sim.pos_x[p] >> 12, 0, vw - 1)
				var cj: int = clampi(sim.pos_y[p] >> 12, 0, vh - 1)
				_occ_bytes[cj * vw + ci] = 255
			continue
		for j in range(j0, j1 + 1):
			var row := j * vw
			for i in range(i0, i1 + 1):
				_occ_bytes[row + i] = 255
	_occ_img.set_data(vw, vh, false, Image.FORMAT_L8, _occ_bytes)
	_occ_tex.update(_occ_img)
	update_us = Time.get_ticks_usec() - t0


func _make_quad() -> ArrayMesh:
	var verts := PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## Procedural canopies, greyscale: R luminance (lumps and shading), G canopy
## coverage, B its shadow (down-right). Cell space -1.18..1.18 (the quad's
## margin for the shadow); the canopy fills radius 1.
static func _atlas() -> ImageTexture:
	if _atlas_cache != null:
		return _atlas_cache
	var img := Image.create(CELL_PX * KINDS, CELL_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for kind in KINDS:
		for py in CELL_PX:
			for px in CELL_PX:
				var p := (Vector2(px + 0.5, py + 0.5) / CELL_PX * 2.0 - Vector2.ONE) * 1.18
				var cov := _canopy(kind, p)
				var sh := _canopy(kind, p - Vector2(0.17, 0.2)) * 0.9
				var lum := _lum(kind, p)
				img.set_pixel(kind * CELL_PX + px, py, Color(lum, cov, sh, 1.0))
	img.generate_mipmaps()
	_atlas_cache = ImageTexture.create_from_image(img)
	return _atlas_cache


## Canopy coverage 0..1 (soft edge) of a tree kind at p.
static func _canopy(kind: int, p: Vector2) -> float:
	var r := p.length()
	var a := atan2(p.y, p.x)
	var edge := 0.92
	match kind:
		0:  # broadleaf: lumpy round crown
			edge = 0.86 + 0.07 * sin(a * 6.0 + 0.7) + 0.04 * sin(a * 11.0)
		1:  # pine: star of needles
			edge = 0.78 + 0.16 * absf(sin(a * 4.5))
		2:  # olive / scrub: irregular clumps
			edge = 0.8 + 0.1 * sin(a * 3.0 + 1.3) + 0.08 * sin(a * 7.0 + 0.4)
		3:  # cypress: tight round
			edge = 0.9 + 0.03 * sin(a * 9.0)
	return clampf((edge - r) / 0.08, 0.0, 1.0)


static func _lum(kind: int, p: Vector2) -> float:
	var r := p.length()
	var l := 0.55 - 0.25 * r
	match kind:
		0:
			# Highlights on a few sub-crowns.
			for c in [Vector2(-0.35, -0.3), Vector2(0.3, -0.15), Vector2(-0.05, 0.35), Vector2(0.0, 0.0)]:
				var d := p.distance_to(c)
				l += 0.22 * clampf(1.0 - d / 0.38, 0.0, 1.0)
		1:
			l = 0.3 + 0.35 * clampf(1.0 - r, 0.0, 1.0) + 0.1 * absf(sin(atan2(p.y, p.x) * 9.0))
		2:
			for c in [Vector2(-0.3, -0.25), Vector2(0.3, 0.1), Vector2(-0.1, 0.35)]:
				var d2 := p.distance_to(c)
				l += 0.25 * clampf(1.0 - d2 / 0.32, 0.0, 1.0)
		3:
			l = 0.35 + 0.4 * clampf(1.0 - r, 0.0, 1.0)
	return clampf(l, 0.0, 1.0)
