extends Node2D
## The settlement's walls, towers and gates on the battle map, drawn from the battle kit
## (tools/battlekit, atlases in assets/battlekit, table in game/battlekit_atlas.gd). View only:
## nothing here touches the sim; it reads the layout (sim.map_info["city"], metres) and the gates'
## state each tick.
##
## High: one MultiMesh (one draw call), every wall segment / tower / gate a quad with its piece of the
## atlas; game/battlekit.gdshader lights it (NW key, the piece's normal turned by the instance angle)
## and tints it by the founding culture. A baked cast shadow + AO layer under it
## (game/battlekit_shadow.gd). Low / CPU path (Graphics Low): the same instances drawn with
## draw_texture_rect_region from the 4 px/m pre-lit atlas, tinted by modulate, no shadow layer, no
## shader at all.
##
## Pieces: walls laid along each edge of the wall polygon, tiled to its length (x scale <= ~25 %), the
## variant matching the sim's (thickness, parapet) so the walkway sits where the men stand; round /
## square (or timber) towers at the sim's tower list (the gate towers are in it); a gate piece
## (closed / open / broken) over the wall at each gate, widths from the sim.

const Atlas := preload("res://game/battlekit_atlas.gd")
const Shadow := preload("res://game/battlekit_shadow.gd")
const Quality := preload("res://game/quality.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const SHADER := preload("res://game/battlekit.gdshader")
## Loaded when needed (the script checkers' scratch project has no assets/).
var TEX_ALB: Texture2D
var TEX_NRM: Texture2D
var TEX_LOW: Texture2D

const WALL_LEN := 16.0          # a wall piece's length (stone); a palisade piece is PAL_LEN
const PAL_LEN := 12.0
const WALL_H := [5, 5, 7, 9]    # MapGen.WALL_H by wall level
const WALL_VARIANTS := [[8, 2, "wall_8_2"], [10, 2, "wall_10_2"], [12, 2, "wall_12_2"], [12, 4, "wall_12_4"],
	[14, 4, "wall_14_4"]]
const PAL_VARIANTS := [[8, "pal_8"], [10, "pal_10"], [12, "pal_12"]]
## Stone tint by culture: Latin, Greek, Punic, Celtic, Spanish colonial, native, spare, spare.
const STONE_TINT: Array[Vector3] = [Vector3(1.0, 0.98, 0.95), Vector3(1.06, 1.0, 0.9), Vector3(1.12, 1.05, 0.92),
	Vector3(0.92, 0.95, 0.9), Vector3(1.1, 0.98, 0.84), Vector3(0.98, 0.86, 0.7), Vector3(1, 1, 1), Vector3(1, 1, 1)]
const PAL_R: Array[Vector3] = [Vector3(0.78, 0.34, 0.22), Vector3(0.86, 0.70, 0.54), Vector3(0.90, 0.88, 0.82),
	Vector3(0.70, 0.58, 0.36), Vector3(0.84, 0.48, 0.28), Vector3(0.62, 0.48, 0.36), Vector3(0.7, 0.4, 0.3), Vector3(0.7, 0.4, 0.3)]
const PAL_G: Array[Vector3] = [Vector3(0.90, 0.83, 0.68), Vector3(0.92, 0.9, 0.82), Vector3(0.95, 0.93, 0.86),
	Vector3(0.80, 0.72, 0.58), Vector3(0.95, 0.92, 0.82), Vector3(0.78, 0.60, 0.42), Vector3(0.9, 0.85, 0.7), Vector3(0.9, 0.85, 0.7)]
const PAL_B: Array[Vector3] = [Vector3(0.70, 0.18, 0.16), Vector3(0.25, 0.35, 0.65), Vector3(0.45, 0.30, 0.55),
	Vector3(0.25, 0.35, 0.65), Vector3(0.88, 0.68, 0.20), Vector3(0.20, 0.55, 0.55), Vector3(0.7, 0.2, 0.2), Vector3(0.7, 0.2, 0.2)]

var sim
var lay: Dictionary = {}
var k := 10.0                       # px per metre
var low := false
var shadows_on := true
var culture := 0
var build_ms := 0.0
var shadow_ms := 0.0

# Instances (parallel arrays).
var i_piece := PackedInt32Array()
var i_pos := PackedVector2Array()   # metres
var i_e := PackedVector2Array()     # unit vector of the piece's right (image x) on the screen
var i_sx := PackedFloat32Array()
var i_sy := PackedFloat32Array()
var i_hs := PackedFloat32Array()    # height scale (shadows)
var i_gate := PackedInt32Array()    # gate index, or -1
var i_flash := PackedFloat32Array()
var _gate_inst := PackedInt32Array()
var _gate_state := PackedInt32Array()
var _gate_hit := PackedInt32Array()
var _timber := false
var _mm: MultiMesh
var _mmi: MultiMeshInstance2D
var _low_node: Node2D
var _shadow: Node2D
var _name_idx := {}


func setup(p_sim, p_lay: Dictionary, p_k: float) -> void:
	sim = p_sim
	lay = p_lay
	k = p_k
	var t0 := Time.get_ticks_usec()
	for q in Atlas.NAMES.size():
		_name_idx[Atlas.NAMES[q]] = q
	culture = clampi(int(lay.get("founder", lay.get("plan", 0))), 0, 7)
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--kit-culture="):
			culture = clampi(int(str(a).get_slice("=", 1)), 0, 7)
	_timber = int(lay.get("palisade", 0)) != 0
	_build_instances()
	low = Quality.is_low()
	_make_nodes()
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0


# ------------------------------------------------------------ instances ----

func _add(piece: String, pos: Vector2, e: Vector2, sx: float, sy: float, hs: float, gate := -1) -> int:
	i_piece.append(_name_idx[piece])
	i_pos.append(pos)
	i_e.append(e)
	i_sx.append(sx)
	i_sy.append(sy)
	i_hs.append(hs)
	i_gate.append(gate)
	i_flash.append(0.0)
	return i_piece.size() - 1


func _build_instances() -> void:
	var t: float = lay["t"]
	var pp: int = int(lay["pp"])
	var walls := clampi(int(lay["walls"]), 0, 3)
	var hs := 1.0 if _timber else float(WALL_H[walls]) / 5.0
	if walls <= 0:
		return
	# Wall variant: the sim's (thickness, parapet), else the nearest.
	var wname := ""
	var wt := 10.0
	if _timber:
		var best := 1000.0
		for v in PAL_VARIANTS:
			if absf(float(v[0]) - t) < best:
				best = absf(float(v[0]) - t)
				wname = v[1]
				wt = float(v[0])
	else:
		var best2 := 1000.0
		for v in WALL_VARIANTS:
			var d := absf(float(v[0]) - t) * 10.0 + absf(float(v[1]) - pp)
			if d < best2:
				best2 = d
				wname = v[2]
				wt = float(v[0])
	var rings: Array = [lay["poly"]]
	var cit: Dictionary = lay.get("cit", {})
	if not cit.is_empty():
		rings.append(cit["poly"])
	for poly: PackedInt32Array in rings:
		_wall_ring(poly, wname, t / wt, hs)
	# Gates over the wall, then the towers over everything.
	_gate_inst.resize(0)
	var gates: Array = lay["gates"]
	for g in gates.size():
		var gd: Dictionary = gates[g]
		var ang := float(int(gd["dir"])) * TAU / 1024.0
		var n := Vector2(cos(ang), sin(ang))
		var e := Vector2(-n.y, n.x)
		var hw := float(int(gd.get("hw", 4)))
		var st: int = sim.g_state[g] if g < sim.n_gates else BattleSim.GATE_CLOSED
		_gate_inst.append(_add(_gate_name(st), Vector2(gd["x"], gd["y"]), e, hw / 4.0, (t + 1.0) / 11.0, hs, g))
	_gate_state.resize(gates.size())
	_gate_hit.resize(gates.size())
	for g in gates.size():
		_gate_state[g] = sim.g_state[g] if g < sim.n_gates else BattleSim.GATE_CLOSED
		_gate_hit[g] = 0
	var q := 0
	for tw in lay["towers"]:
		q += 1
		_tower(tw, q, hs)
	var sea: Dictionary = lay.get("sea", {})
	if not sea.is_empty() and not (sea["gate"] as Array).is_empty():
		var g2: Array = sea["gate"]
		var ang2 := float(int(g2[2])) * TAU / 1024.0
		var n2 := Vector2(cos(ang2), sin(ang2))
		var e2 := Vector2(-n2.y, n2.x)
		for s in [-1.0, 1.0]:
			var tc: Vector2 = Vector2(g2[0], g2[1]) + e2 * (3.0 + t * 0.5) * s
			_tower([tc.x, tc.y, t * 0.5, 0, 0], q + 7, hs)


func _gate_name(st: int) -> String:
	var c := "c"
	if st == BattleSim.GATE_OPEN:
		c = "o"
	elif st == BattleSim.GATE_BROKEN:
		c = "b"
	return ("pgate_" if _timber else "gate_") + c


func _tower(tw: Array, q: int, hs: float) -> void:
	var r := float(tw[2])
	var pos := Vector2(float(tw[0]), float(tw[1]))
	if _timber:
		var a := float((q * 37) % 100) * 0.0628
		_add("tower_timber", pos, Vector2(cos(a), sin(a)), r / 6.5, r / 6.5, hs)
	elif tw.size() > 3 and int(tw[3]) != 0:
		var ang := float(int(tw[4])) * TAU / 1024.0 if tw.size() > 4 else 0.0
		_add("tower_sq", pos, Vector2(cos(ang), sin(ang)), r / 6.1, r / 6.1, hs)
	else:
		var a2 := float((q * 37) % 100) * 0.0628
		_add("tower_round", pos, Vector2(cos(a2), sin(a2)), r / 6.4, r / 6.4, hs)


func _wall_ring(poly: PackedInt32Array, piece: String, sy: float, hs: float) -> void:
	var nv := poly.size() / 2
	var area := 0.0
	for e in nv:
		var e2 := (e + 1) % nv
		area += float(poly[e * 2]) * poly[e2 * 2 + 1] - float(poly[e2 * 2]) * poly[e * 2 + 1]
	for e in nv:
		var a := Vector2(poly[e * 2], poly[e * 2 + 1])
		var b := Vector2(poly[((e + 1) % nv) * 2], poly[((e + 1) % nv) * 2 + 1])
		var l := a.distance_to(b)
		if l < 0.5:
			continue
		var d := (b - a) / l
		if area <= 0.0:
			d = -d   # the piece's outer side must be the polygon's outside
		var plen := PAL_LEN if _timber else WALL_LEN
		var cnt := maxi(roundi(l / plen), 1)
		var step := l / cnt
		for q in cnt:
			_add(piece, a + (b - a) / l * step * (q + 0.5), d, step / plen, sy, hs)


## The quad's transform in px for instance i drawn as piece p.
func _xform(i: int, p: int) -> Transform2D:
	var an: Array = Atlas.ANCHOR[p]
	var e: Vector2 = i_e[i]
	var dn := Vector2(-e.y, e.x)    # image down on the screen
	var sx := i_sx[i]
	var sy := i_sy[i]
	var o: Vector2 = (i_pos[i] + e * (float(an[0]) * sx) + dn * (float(an[1]) * sy)) * k
	return Transform2D(e * (float(an[2]) * sx * k), dn * (float(an[3]) * sy * k), o)


# ---------------------------------------------------------------- nodes ----

func _make_nodes() -> void:
	if low:
		if TEX_LOW == null:
			TEX_LOW = load("res://assets/battlekit/atlas_low.png")
	elif TEX_ALB == null:
		TEX_ALB = load("res://assets/battlekit/atlas_albedo.png")
		TEX_NRM = load("res://assets/battlekit/atlas_nrm.png")
	for c in get_children():
		c.queue_free()
	_mmi = null
	_low_node = null
	_shadow = null
	shadow_ms = 0.0
	if i_piece.is_empty():
		return
	if low:
		_low_node = _LowDraw.new()
		_low_node.kit = self
		add_child(_low_node)
		return
	shadows_on = not ("--no-kit-shadow" in OS.get_cmdline_user_args())
	if shadows_on:
		var t0 := Time.get_ticks_usec()
		_shadow = Shadow.new()
		_shadow.build(self)
		add_child(_shadow)
		shadow_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_custom_data = true
	_mm.mesh = _make_quad()
	_mm.instance_count = i_piece.size()
	var buf := PackedFloat32Array()
	buf.resize(i_piece.size() * 12)
	for i in i_piece.size():
		_write(buf, i)
	_mm.buffer = buf
	_mm.custom_aabb = AABB(Vector3(-50, -50, -1), Vector3(sim.field_w / 1024.0 * k + 100, sim.field_h / 1024.0 * k + 100, 2))
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("albedo_tex", TEX_ALB)
	mat.set_shader_parameter("nrm_tex", TEX_NRM)
	var rects := PackedVector4Array()
	rects.resize(24)
	for p in Atlas.RECT.size():
		var r: Array = Atlas.RECT[p]
		rects[p] = Vector4(float(r[0]) / Atlas.ATLAS_W, float(r[1]) / Atlas.ATLAS_H, float(r[2]) / Atlas.ATLAS_W,
			float(r[3]) / Atlas.ATLAS_H)
	mat.set_shader_parameter("rects", rects)
	mat.set_shader_parameter("stone_tint", PackedVector3Array(STONE_TINT))
	mat.set_shader_parameter("pal_r", PackedVector3Array(PAL_R))
	mat.set_shader_parameter("pal_g", PackedVector3Array(PAL_G))
	mat.set_shader_parameter("pal_b", PackedVector3Array(PAL_B))
	_mmi = MultiMeshInstance2D.new()
	_mmi.multimesh = _mm
	_mmi.material = mat
	add_child(_mmi)


func _write(buf: PackedFloat32Array, i: int, o := -1) -> void:
	var p := i_piece[i]
	var xf := _xform(i, p)
	if o < 0:
		o = i * 12
	buf[o] = xf.x.x
	buf[o + 1] = xf.y.x
	buf[o + 2] = 0.0
	buf[o + 3] = xf.origin.x
	buf[o + 4] = xf.x.y
	buf[o + 5] = xf.y.y
	buf[o + 6] = 0.0
	buf[o + 7] = xf.origin.y
	buf[o + 8] = float(p)
	buf[o + 9] = i_e[i].angle()
	buf[o + 10] = float(culture)
	buf[o + 11] = i_flash[i]


static func _make_quad() -> ArrayMesh:
	var verts := PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


# --------------------------------------------------------------- per tick ----

## Gates: the piece follows the state (closed / open / broken), a flash while struck; a gate
## breaking re-bakes its shadow. Also follows a Graphics quality switch.
func refresh() -> void:
	if i_piece.is_empty():
		return
	if Quality.is_low() != low:
		low = not low
		_make_nodes()
		return
	var changed := false
	var gates: Array = lay["gates"]
	for g in mini(gates.size(), sim.n_gates):
		var st: int = sim.g_state[g]
		var hit := 1 if sim.tick - sim.g_hit_t[g] < 4 else 0
		if st == _gate_state[g] and hit == _gate_hit[g]:
			continue
		var i := _gate_inst[g]
		var broke := st != _gate_state[g]
		_gate_state[g] = st
		_gate_hit[g] = hit
		i_piece[i] = _name_idx[_gate_name(st)]
		i_flash[i] = 1.0 if hit != 0 else 0.0
		changed = true
		if _mm != null:
			var buf := PackedFloat32Array()
			buf.resize(12)
			_write(buf, i, 0)
			_mm.set_instance_transform_2d(i, Transform2D(Vector2(buf[0], buf[4]), Vector2(buf[1], buf[5]), Vector2(buf[3], buf[7])))
			_mm.set_instance_custom_data(i, Color(buf[8], buf[9], buf[10], buf[11]))
		if broke and _shadow != null:
			_shadow.rebake_instance(i)
	if changed and _low_node != null:
		_low_node.queue_redraw()


## The Low path: no shader, no shadow layer; pre-lit 4 px/m atlas, culture tint by modulate.
class _LowDraw extends Node2D:
	var kit

	func _draw() -> void:
		var tint: Vector3 = kit.STONE_TINT[kit.culture]
		var col := Color(tint.x, tint.y, tint.z)
		var lowk: float = float(kit.Atlas.LOW_PPM) / float(kit.Atlas.PPM)
		for i in kit.i_piece.size():
			var p: int = kit.i_piece[i]
			var an: Array = kit.Atlas.ANCHOR[p]
			var r: Array = kit.Atlas.RECT[p]
			var e: Vector2 = kit.i_e[i]
			var dn := Vector2(-e.y, e.x)
			var sx: float = kit.i_sx[i]
			var sy: float = kit.i_sy[i]
			var w: float = float(an[2]) * sx * float(kit.k)
			var h: float = float(an[3]) * sy * float(kit.k)
			var o: Vector2 = (kit.i_pos[i] + e * (float(an[0]) * sx) + dn * (float(an[1]) * sy)) * float(kit.k)
			draw_set_transform_matrix(Transform2D(e, dn, o))
			var c := col
			if kit.i_flash[i] > 0.0:
				c = col.lerp(Color(1.0, 0.62, 0.25), 0.45)
			draw_texture_rect_region(kit.TEX_LOW, Rect2(-w * 0.5, -h * 0.5, w, h),
				Rect2(float(r[0]) * lowk, float(r[1]) * lowk, float(r[2]) * lowk, float(r[3]) * lowk), c)
