extends Node2D
## Static-grass tufts standing up in the oblique view (tabletop pass 3 leftovers; view only, High + diorama only). Pass 2's tufts
## are strokes in terrain.gdshader and would lie flat on the board here, so in the oblique view the shader's are off and these
## stand instead: one MultiMesh of small upright quads (game/tuft.gdshader draws three blades in each: 0.2 to 0.32 m tall, darker
## at the foot, lighter at the tip and on the left), placed by the SAME hash as the shader's `tuft_at` (0.9 m cells, one in four
## holds a tuft, the blades' offsets, lengths and lean from the same hash12 inputs) so the two views agree in position, on open
## ground only (not streets or plazas, water and the wet shore, rock, felt under the woods, fields, buildings, ditches).
## Only inside the camera's view and only at zoom >= MIN_ZOOM, at most CAP instances. The ground is cut into CHUNK cells square
## chunks whose tufts are worked out once (at most BUILD_PER_FRAME a frame) and kept; the MultiMesh buffer is put together from the
## chunks in view when that set changes (not on every move of a cell: a pan crossing a chunk costs one buffer copy).

const MapGen := preload("res://sim/mapgen.gd")
const BoardView := preload("res://game/board_view.gd")
const SHADER := preload("res://game/tuft.gdshader")

const CS := 0.9                  # the shader's cell (metres)
const CHUNK := 30                # cells a side
const MIN_ZOOM := 1.2
const CAP := 6000
const BUILD_PER_FRAME := 2
const MAX_CACHED := 80
const W_M := 0.5                 # the quad's size (metres) and where its foot is (fraction down)
const H_M := 0.4
const FOOT := 0.92
const FLOATS := 12               # per instance: a 2D transform (8) and the custom data (4)

var sim
var px_per_m := 10.0
var instances := 0               # drawn now (tests, the cost line)
var build_us := 0
var _mm: MultiMesh
var _mmi: MultiMeshInstance2D
var _chunks := {}                # Vector2i -> PackedFloat32Array of instances (empty: none)
var _shown: Array = []           # the chunk keys now in the MultiMesh
var _veg: PackedByteArray
var _vw := 0
var _vh := 0
var _riv := {}
var _rocks := PackedVector3Array()   # every boulder (x, y metres, radius): two or three tufts stand against its foot


func setup(p_sim, p_px_per_m: float) -> void:
	sim = p_sim
	px_per_m = p_px_per_m
	_veg = sim.veg if sim.veg.size() >= sim.veg_w * sim.veg_h else PackedByteArray()
	_vw = sim.veg_w
	_vh = sim.veg_h
	if sim.riv_on != 0:
		_riv = {"g": sim.riv, "l": sim.map_info["river"]}
	for rk in sim.map_info.get("land", {}).get("rocks", []):
		for d in (rk.size() - 2) / 3:
			_rocks.append(Vector3(float(int(rk[2 + d * 3])), float(int(rk[3 + d * 3])), float(int(rk[4 + d * 3]))))
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_custom_data = true
	var w := W_M * px_per_m
	var h := H_M * px_per_m
	var x0 := -w * 0.5
	var y0 := -h * FOOT
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(x0, y0), Vector2(x0 + w, y0), Vector2(x0 + w, y0 + h), Vector2(x0, y0 + h)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mm.mesh = mesh
	_mm.instance_count = CAP
	_mm.visible_instance_count = 0
	_mm.custom_aabb = AABB(Vector3(-1000.0, -1000.0, -1.0), Vector3(px_per_m * sim.field_w / 1024.0 + 2000.0, px_per_m * sim.field_h / 1024.0 + 2000.0, 2.0))
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	BoardView.apply(mat)
	_mmi = MultiMeshInstance2D.new()
	_mmi.multimesh = _mm
	_mmi.material = mat
	add_child(_mmi)
	visible = false


func _process(_d: float) -> void:
	if sim == null or not visible:
		return
	var ct := get_canvas_transform()
	var zoom := ct.get_scale().x
	if zoom < MIN_ZOOM:
		if instances != 0:
			_mm.visible_instance_count = 0
			instances = 0
			_shown = []
		return
	var t0 := Time.get_ticks_usec()
	var br := Rect2(ct.affine_inverse() * Vector2.ZERO, get_viewport_rect().size / ct.get_scale())
	var wr := BoardView.world_rect(br).grow(px_per_m * CS)
	var f := 1.0 / (px_per_m * CS * float(CHUNK))
	var c0 := Vector2i(floori(wr.position.x * f), floori(wr.position.y * f))
	var c1 := Vector2i(floori(wr.end.x * f), floori(wr.end.y * f))
	var centre := wr.get_center() * f
	var want: Array = []
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			want.append(Vector2i(cx, cy))
	want.sort_custom(func(a, b): return (Vector2(a) + Vector2(0.5, 0.5)).distance_squared_to(centre) < (Vector2(b) + Vector2(0.5, 0.5)).distance_squared_to(centre))
	var built := 0
	var use: Array = []
	var total := 0
	for k in want:
		if not _chunks.has(k):
			if built >= BUILD_PER_FRAME:
				continue
			_chunks[k] = _build_chunk(k)
			built += 1
		var n: int = (_chunks[k] as PackedFloat32Array).size() / FLOATS
		if total + n > CAP:
			break
		total += n
		use.append(k)
	if use != _shown or built > 0:
		_shown = use
		var buf := PackedFloat32Array()
		for k in use:
			buf.append_array(_chunks[k])
		buf.resize(CAP * FLOATS)
		_mm.buffer = buf
		_mm.visible_instance_count = total
		instances = total
	if _chunks.size() > MAX_CACHED:
		var drop := []
		for k in _chunks:
			if not (k in want):
				drop.append(k)
		for k in drop:
			_chunks.erase(k)
			if _chunks.size() <= MAX_CACHED:
				break
	build_us = Time.get_ticks_usec() - t0


static func hash12(x: float, y: float) -> float:
	var a := fposmod(x * 0.1031, 1.0)
	var b := fposmod(y * 0.1031, 1.0)
	var c := fposmod(x * 0.1031, 1.0)
	var d := a * (b + 33.33) + b * (c + 33.33) + c * (a + 33.33)
	a += d
	b += d
	c += d
	return fposmod((a + b) * c, 1.0)


## The tufts of chunk k as instance floats (see FLOATS): the shader's own cell hash, then the open-ground test.
func _build_chunk(k: Vector2i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var fw_m: float = sim.field_w / 1024.0
	var fh_m: float = sim.field_h / 1024.0
	for j in CHUNK:
		var iy := k.y * CHUNK + j
		for i in CHUNK:
			var ix := k.x * CHUNK + i
			var fx := float(ix)
			var fy := float(iy)
			if hash12(fx + 61.3, fy + 9.1) > 0.24:
				continue
			var bx := (0.28 + 0.44 * hash12(fx + 2.2, fy + 71.7)) * CS
			var by := (0.5 + 0.3 * hash12(fx + 8.8, fy + 5.5)) * CS
			var mx := fx * CS + bx
			var my := fy * CS + by
			if mx < 1.0 or my < 1.0 or mx > fw_m - 1.0 or my > fh_m - 1.0 or not _open(mx, my):
				continue
			var l0 := 0.2 + 0.12 * hash12(fx + 0.0, fy + 19.9)
			var l1 := 0.2 + 0.12 * hash12(fx + 3.3, fy + 19.9)
			var l2 := 0.2 + 0.12 * hash12(fx + 6.6, fy + 19.9)
			var jit := hash12(fx + 0.0, fy + 55.5)
			out.append_array(PackedFloat32Array([1.0, 0.0, 0.0, mx * px_per_m, 0.0, 1.0, 0.0, my * px_per_m,
				l0 / H_M, l1 / H_M, l2 / H_M, jit]))
	# Pass 6: tufts against a boulder's foot (its south half, where an upright tuft shows against the rock).
	var cm := float(CHUNK) * CS
	for rk in _rocks:
		if rk.x < k.x * cm or rk.x >= (k.x + 1) * cm or rk.y < k.y * cm or rk.y >= (k.y + 1) * cm:
			continue
		var sd := int(rk.x * 7.0 + rk.y * 13.0)
		for t in 3:
			var h1 := hash12(float(sd) + t * 5.3, 91.1)
			var h2 := hash12(float(sd) + t * 2.9, 17.7)
			var ang := PI * (0.12 + 0.76 * (float(t) + h1) / 3.0)   # 0 east .. PI west, through south (y down)
			var dist := rk.z * (1.02 + 0.2 * h2)
			var mx := rk.x + cos(ang) * dist
			var my := rk.y + sin(ang) * dist * 0.9
			if mx < 1.0 or my < 1.0 or mx > fw_m - 1.0 or my > fh_m - 1.0:
				continue
			var l0 := 0.24 + 0.14 * hash12(mx, my + 3.0)
			var l1 := 0.22 + 0.14 * hash12(mx + 3.0, my)
			var l2 := 0.24 + 0.14 * hash12(mx + 6.0, my + 6.0)
			out.append_array(PackedFloat32Array([1.0, 0.0, 0.0, mx * px_per_m, 0.0, 1.0, 0.0, my * px_per_m,
				l0 / H_M, l1 / H_M, l2 / H_M, h1]))
	return out


## Bilinear sample of the 4 m vegetation grid's flag test at (x, y) metres (the shader reads the same cells with a linear filter).
func _veg_at(x: float, y: float, mask: int) -> float:
	var gx := clampf(x / 4.0 - 0.5, 0.0, float(_vw - 1))
	var gy := clampf(y / 4.0 - 0.5, 0.0, float(_vh - 1))
	var x0 := mini(int(gx), _vw - 2) if _vw > 1 else 0
	var y0 := mini(int(gy), _vh - 2) if _vh > 1 else 0
	var fx := gx - x0
	var fy := gy - y0
	var x1 := mini(x0 + 1, _vw - 1)
	var y1 := mini(y0 + 1, _vh - 1)
	var a := 1.0 if (_veg[y0 * _vw + x0] & mask) != 0 else 0.0
	var b := 1.0 if (_veg[y0 * _vw + x1] & mask) != 0 else 0.0
	var c := 1.0 if (_veg[y1 * _vw + x0] & mask) != 0 else 0.0
	var d := 1.0 if (_veg[y1 * _vw + x1] & mask) != 0 else 0.0
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


func _open(x: float, y: float) -> bool:
	if not _veg.is_empty():
		if _veg_at(x, y, MapGen.V_DENS) > 0.06:   # felt under the woods (the shader's contour is density 0.075 of 0.33 a step)
			return false
		if _veg_at(x, y, MapGen.V_ROAD | MapGen.V_PLAZA) > 0.25:
			return false
		if _veg_at(x, y, MapGen.V_FIELD) > 0.2:
			return false
		if _veg_at(x, y, MapGen.V_WATER) > 0.0 or _veg_at(x, y, MapGen.V_DITCH) > 0.0:
			return false
		if _veg_at(x, y, MapGen.V_URBAN) > 0.5:
			return false
	if sim.obs_kind(int(x * 1024.0), int(y * 1024.0)) != MapGen.C_OPEN:
		return false
	if not _riv.is_empty():
		var g: Dictionary = _riv["g"]
		var rl: Dictionary = _riv["l"]
		var cy := MapGen.river_cy(g, int(x)) / 100.0
		if absf(y - cy) < float(int(g["hw"])) + 5.0 and x > float(int(rl["x0"])) - 5.0 and x < float(int(rl["x1"])) + 5.0:
			return false
	if sim.ter_on != 0:
		# Steep ground is rock: the height's slope over 2 m either side.
		var h0 := float(sim.height_at(int((x - 2.0) * 1024.0), int(y * 1024.0)))
		var h1 := float(sim.height_at(int((x + 2.0) * 1024.0), int(y * 1024.0)))
		var h2 := float(sim.height_at(int(x * 1024.0), int((y - 2.0) * 1024.0)))
		var h3 := float(sim.height_at(int(x * 1024.0), int((y + 2.0) * 1024.0)))
		var g2 := Vector2(h1 - h0, h3 - h2) / 4096.0
		if g2.length() > 0.45:
			return false
	return true
