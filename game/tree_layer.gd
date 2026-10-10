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
const CityDraw := preload("res://game/city_draw.gd")

const KINDS := 8               # atlas cells: 0 broadleaf, 1 pine, 2 olive / scrub, 3 cypress,
							   # 4 grass tuft, 5 reeds, 6 willow, 7 bush
const EXTRA_CAP := 1900        # glyphs of non-gameplay cover in all (reeds, willows, orchards beyond the walls, tufts, bushes)
const REED_CAP := 420
const WILLOW_CAP := 90
const CELL_PX := 64            # atlas cell size
const MAX_TREES := 40000
## Trees per 4 m cell by density (x 100) and canopy radius range (m).
const PER_CELL := [0, 45, 105, 165]
const R_MIN := [0.0, 1.8, 2.1, 2.4]
const R_MAX := [0.0, 2.8, 3.3, 3.8]

static var _atlas_cache: ImageTexture = null

var sim
var px_per_m := 10.0
var count := 0            # trees (drawn over the men)
var cover_count := 0      # ground cover (drawn under them)
var build_ms := 0.0
var update_us := 0
var _mmi: MultiMeshInstance2D
var _cover_mmi: MultiMeshInstance2D
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
	var dry := pal_i == MapGen.PAL_ARID or pal_i == MapGen.PAL_DRY or pal_i == MapGen.PAL_ROCKY
	var orchard_kind := 2 if pal_i == MapGen.PAL_ARID or pal_i == MapGen.PAL_DRY else 0
	_rng = (int(sim.ter_hash) & 0x7FFFFFFF) | 1
	var vw: int = sim.veg_w
	var vh: int = sim.veg_h
	var veg: PackedByteArray = sim.veg
	# Heights for the band (valley floors, high ground) and the grade.
	var tn_x: int = sim.ter_nx
	var tn_y: int = sim.ter_ny
	var tlo := 0.0
	var thi := 1.0
	if sim.ter_on != 0:
		tlo = 1e9
		thi = -1e9
		for hv in sim.ter_h:
			tlo = minf(tlo, hv / 1024.0)
			thi = maxf(thi, hv / 1024.0)
	var relief := thi - tlo
	var plan: Dictionary = CityDraw.plan_surround(sim)
	var mask: PackedByteArray = plan.get("mask", PackedByteArray())
	# Orchard rectangles (metres): the settlement's own and the ones beyond
	# its walls (the view's plan).
	var orchards: Array = []
	if sim.map_info.has("city"):
		for f in sim.map_info["city"]["fields"]:
			if int(f[4]) == 1:
				orchards.append(Rect2(f[0], f[1], int(f[2]) - int(f[0]), int(f[3]) - int(f[1])))
	var outer_orchards: Array = plan.get("orchards", [])
	var data := PackedFloat32Array()
	var cover := PackedFloat32Array()
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
			var hn := 0.5
			if relief > 6.0:
				hn = (float(sim.ter_h[mini(j, tn_y - 1) * tn_x + mini(i, tn_x - 1)]) / 1024.0 - tlo) / relief
			# A stand: groups of 8 x 8 cells lean to one species.
			var stand_kind := _pick_h(kinds, _cell_hash(i >> 3, j >> 3))
			var n := int(PER_CELL[d]) / 100
			if _rand() % 100 < int(PER_CELL[d]) % 100:
				n += 1
			for q in n:
				var x := i * 4.0 + _randf() * 4.0
				var y := j * 4.0 + _randf() * 4.0
				var kd := stand_kind if _rand() % 100 < 60 else _pick(kinds)
				var r := lerpf(R_MIN[d], R_MAX[d], _randf())
				# Sizes vary: saplings, the common run, now and then an old giant.
				var sz := 0.78 + 0.42 * _randf()
				if _rand() % 100 < 7:
					sz *= 1.3
				r *= sz
				# Valley floors grow bigger trees, high ground small and stunted.
				if relief > 6.0:
					r *= lerpf(1.1, 1.0, clampf(hn * 3.0, 0.0, 1.0)) * lerpf(1.0, 0.68, clampf((hn - 0.65) / 0.3, 0.0, 1.0))
					if hn > 0.7 and not dry and _rand() % 100 < 50:
						kd = 1
				# The thin edge of a wood: some bushes among the trees.
				if d == 1 and _rand() % 100 < 22:
					kd = 7
					r *= 0.5
				if kd == 2:
					r *= 0.75  # olives and scrub are smaller
				elif kd == 3:
					r *= 0.6   # cypresses are narrow
				_push(data, x * k, y * k, r * k, kd, _rand() % 3, _rand() % 8)
				if data.size() / 16 >= MAX_TREES:
					break
	var n_inner := data.size() / 16
	for o in orchards + outer_orchards:
		var rc: Rect2 = o
		var yy := rc.position.y + 3.0
		while yy < rc.end.y - 1.0:
			var xx := rc.position.x + 3.0
			while xx < rc.end.x - 1.0:
				_push(data, (xx + _randf() * 0.6) * k, (yy + _randf() * 0.6) * k, (1.5 + _randf() * 0.4) * k,
					orchard_kind, 1, _rand() % 8)
				xx += 6.0
			yy += 6.0
	# Water's edge (crossing maps): reeds, a few willows.
	var reeds := PackedFloat32Array()
	if sim.riv_on != 0 and sim.map_info.has("river"):
		_river_edge(reeds, data, k)
	# Ground cover in the open (non-gameplay): grass tufts, scrub on dry
	# slopes, sparse bushes; clumped, capped.
	var budget := EXTRA_CAP - reeds.size() / 16 - (data.size() / 16 - n_inner)
	_ground_cover(cover, veg, mask, vw, vh, dry, budget)
	cover.append_array(reeds)
	count = data.size() / 16
	cover_count = cover.size() / 16
	if count == 0 and cover_count == 0:
		return
	var fw: float = sim.field_w / 1024.0 * px_per_m
	var fh: float = sim.field_h / 1024.0 * px_per_m
	var shades: Array = pal["trees"]
	var base: Color = pal["base"]
	_occ_bytes.resize(vw * vh)
	_occ_bytes.fill(0)
	_occ_img = Image.create_from_data(vw, vh, false, Image.FORMAT_L8, _occ_bytes)
	_occ_tex = ImageTexture.create_from_image(_occ_img)
	for layer in 2:
		var buf := data if layer == 0 else cover
		if buf.size() == 0:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_custom_data = true
		mm.use_colors = true
		mm.mesh = _make_quad()
		mm.instance_count = buf.size() / 16
		mm.buffer = buf
		mm.custom_aabb = AABB(Vector3(-20, -20, -1), Vector3(fw + 40, fh + 40, 2))
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("atlas", _atlas())
		mat.set_shader_parameter("kinds", float(KINDS))
		for s in 3:
			var c: Color = shades[mini(s, shades.size() - 1)]
			mat.set_shader_parameter("shade%d" % s, Vector3(c.r, c.g, c.b))
		var tuft := base.lerp(Color(0.62, 0.6, 0.3) if dry else Color(0.42, 0.62, 0.27), 0.38)
		mat.set_shader_parameter("col_tuft", Vector3(tuft.r, tuft.g, tuft.b))
		mat.set_shader_parameter("col_reed", Vector3(0.33, 0.44, 0.2) if not dry else Vector3(0.45, 0.5, 0.25))
		var wc: Color = shades[0]
		mat.set_shader_parameter("col_willow", Vector3(wc.r * 1.3 + 0.1, wc.g * 1.25 + 0.1, wc.b * 1.1 + 0.05))
		var bc: Color = shades[mini(1, shades.size() - 1)]
		mat.set_shader_parameter("col_bush", Vector3(bc.r * 1.25, bc.g * 1.2, bc.b * 1.1))
		mat.set_shader_parameter("occ", _occ_tex)
		mat.set_shader_parameter("occ_size_px", Vector2(vw, vh) * 4.0 * px_per_m)
		if layer == 1:
			mat.set_shader_parameter("fade_to", 1.0)  # under the men: no fading
		var inst := MultiMeshInstance2D.new()
		inst.multimesh = mm
		inst.material = mat
		if layer == 1:
			_cover_mmi = inst
			inst.z_index = -1  # over the ground (-2), under the city, the works and the men (0)
			add_child(inst)
		else:
			_mmi = inst
			add_child(inst)
	update_occupancy()


## Reeds along both banks and the ford's edges (into `reeds`, drawn under the
## men), a few willows on the banks (into `top`, drawn with the trees).
func _river_edge(reeds: PackedFloat32Array, top: PackedFloat32Array, k: float) -> void:
	var g: Dictionary = sim.riv
	var rl: Dictionary = sim.map_info["river"]
	var hw := float(int(g["hw"]))
	var fx0 := float(int(rl["x0"]))
	var fx1 := float(int(rl["x1"]))
	var bridge := int(rl["kind"]) == 1
	var fw_m: int = sim.field_w / 1024
	var x := 2.0
	var nw := 0
	while x < fw_m - 2:
		var step := 2.6 + _randf() * 1.6
		var cy := MapGen.river_cy(g, int(x)) / 100.0
		var on_cross := x > fx0 - 0.5 and x < fx1 + 0.5
		var near_bridge := bridge and x > fx0 - 4.0 and x < fx1 + 4.0
		if not on_cross and not near_bridge:
			for side in [-1.0, 1.0]:
				if _randf() < 0.75 and reeds.size() / 16 < REED_CAP:
					_push(reeds, (x + _randf()) * k, (cy + side * (hw + 0.2 + _randf() * 2.4)) * k, (1.0 + _randf() * 0.8) * k, 5, _rand() % 3, _rand() % 8)
				if _randf() < 0.35 and reeds.size() / 16 < REED_CAP:
					_push(reeds, (x + _randf()) * k, (cy + side * (hw - 0.6 - _randf() * 1.3)) * k, (0.8 + _randf() * 0.5) * k, 5, _rand() % 3, _rand() % 8)
		x += step
	# Along the ford's two edges, in the shallows.
	if not bridge:
		for ex in [fx0 - 0.9, fx1 + 0.9]:
			var yy := MapGen.river_cy(g, int(ex)) / 100.0 - hw
			while yy < MapGen.river_cy(g, int(ex)) / 100.0 + hw:
				if _randf() < 0.55 and reeds.size() / 16 < REED_CAP:
					_push(reeds, (ex + _randf() * 0.8 - 0.4) * k, yy * k, (0.8 + _randf() * 0.6) * k, 5, _rand() % 3, _rand() % 8)
				yy += 2.5
	# Willows, now and then, a little way up each bank.
	var wx := 8.0 + _randf() * 12.0
	while wx < fw_m - 6 and nw < WILLOW_CAP:
		if not (wx > fx0 - 16.0 and wx < fx1 + 16.0):
			var side := 1.0 if _rand() % 2 == 0 else -1.0
			var wy := MapGen.river_cy(g, int(wx)) / 100.0 + side * (hw + 4.0 + _randf() * 3.0)
			_push(top, wx * k, wy * k, (3.4 + _randf() * 1.6) * k, 6, _rand() % 3, _rand() % 8)
			nw += 1
		wx += 18.0 + _randf() * 20.0


## Tufts, scrub and bushes on clear ground into `out`: clumped by a hash of
## 16 m blocks, more on slopes (scrub on dry ground), thinned at random to
## `budget` instances. Never on woods, streets, fields, water, the ditch or
## the view's tracks and fields.
func _ground_cover(out: PackedFloat32Array, veg: PackedByteArray, mask: PackedByteArray, vw: int, vh: int,
		dry: bool, budget: int) -> void:
	if budget <= 0:
		return
	var blockers: int = MapGen.V_DENS | MapGen.V_URBAN | MapGen.V_FIELD | MapGen.V_ROAD | MapGen.V_PLAZA | MapGen.V_WATER | MapGen.V_DITCH
	var tn_x: int = sim.ter_nx
	var tn_y: int = sim.ter_ny
	var cand := PackedFloat32Array()
	var k := px_per_m
	var riv_hw := 0.0
	if sim.riv_on != 0:
		riv_hw = float(int(sim.riv["hw"])) + 2.5
	for j in vh:
		for i in vw:
			if riv_hw > 0.0 and absf(j * 4.0 + 2.0 - MapGen.river_cy(sim.riv, i * 4 + 2) / 100.0) < riv_hw:
				continue  # the river and its ford
			var b := veg[j * vw + i]
			if (b & blockers) != 0 or (mask.size() > 0 and mask[j * vw + i] != 0):
				continue
			var gr := 0.0
			if sim.ter_on != 0 and i > 0 and j > 0 and i < tn_x - 1 and j < tn_y - 1:
				var gx := float(sim.ter_h[j * tn_x + i + 1] - sim.ter_h[j * tn_x + i - 1]) / (8.0 * 1024.0)
				var gy := float(sim.ter_h[(j + 1) * tn_x + i] - sim.ter_h[(j - 1) * tn_x + i]) / (8.0 * 1024.0)
				gr = sqrt(gx * gx + gy * gy)
			var clump := float(_cell_hash(i >> 2, j >> 2) % 100) / 100.0
			var steep := clampf(gr / 0.2, 0.0, 1.0)
			var p_tuft := (0.03 + 0.25 * steep) * (1.6 if clump < 0.45 else 0.3)
			var p_bush := 0.008 + (0.05 * clampf((gr - 0.04) / 0.2, 0.0, 1.0) if dry else 0.02 * steep)
			if _randf() < p_tuft:
				var scrub := dry and gr > 0.05 and _rand() % 100 < 40
				_push(cand, (i * 4.0 + _randf() * 4.0) * k, (j * 4.0 + _randf() * 4.0) * k,
					((1.1 + _randf() * 0.6) if scrub else (0.7 + _randf() * 0.6)) * k, 2 if scrub else 4, _rand() % 3, _rand() % 8)
			if _randf() < p_bush:
				_push(cand, (i * 4.0 + _randf() * 4.0) * k, (j * 4.0 + _randf() * 4.0) * k, (1.2 + _randf() * 0.8) * k, 7,
					_rand() % 3, _rand() % 8)
	var n := cand.size() / 16
	var keep := 1.0 if n <= budget else float(budget) / float(n)
	for q in n:
		if keep < 1.0 and _randf() >= keep:
			continue
		out.append_array(cand.slice(q * 16, q * 16 + 16))
	if out.size() / 16 > budget:
		out.resize(budget * 16)


static func _cell_hash(a: int, b: int) -> int:
	var x := (a * 73856093) ^ (b * 19349663)
	x = (x ^ (x >> 13)) * 1274126177
	return (x ^ (x >> 16)) & 0x7FFFFFFF


func _pick(kinds: Array) -> int:
	var r := _rand() % 100
	for kv in kinds:
		r -= int(kv[1])
		if r < 0:
			return int(kv[0])
	return int(kinds[0][0])


## The same pick from a hash instead of the view's random stream.
func _pick_h(kinds: Array, h: int) -> int:
	var r := h % 100
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
		x, y, r, float(kind + shade * 8 + rot * 32)])


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
		4:  # grass tuft: a fan of blades
			edge = 0.38 + 0.5 * pow(absf(cos(a * 5.5 + 0.3 + 0.8 * sin(a * 2.0))), 3.0)
			return clampf((edge - r) / 0.12, 0.0, 1.0) * 0.7
		5:  # reeds: thin blades crossing, a dense core
			edge = 0.3 + 0.62 * pow(absf(sin(a * 3.5 + 1.0 + 0.6 * sin(a * 1.5))), 9.0)
			return clampf((edge - r) / 0.09, 0.0, 1.0) * 0.9
		6:  # willow: a wide, loose crown with drooping lobes
			edge = 0.84 + 0.1 * sin(a * 9.0 + 0.5) + 0.06 * sin(a * 17.0)
		7:  # bush: small lumpy
			edge = 0.78 + 0.13 * sin(a * 5.0 + 0.5) + 0.06 * sin(a * 9.0)
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
		4:
			l = 0.4 + 0.55 * r
		5:
			l = 0.55 + 0.4 * r + 0.1 * sin(atan2(p.y, p.x) * 5.0)
		6:
			l = 0.5 + 0.25 * sin(atan2(p.y, p.x) * 14.0) * r + 0.2 * clampf(1.0 - r, 0.0, 1.0)
		7:
			for c in [Vector2(-0.3, -0.25), Vector2(0.28, 0.12)]:
				var d3 := p.distance_to(c)
				l += 0.25 * clampf(1.0 - d3 / 0.35, 0.0, 1.0)
	return clampf(l, 0.0, 1.0)
