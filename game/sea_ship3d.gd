extends RefCounted
## The sea battle's ships in 3D (view only; docs/design/sea.md "The sea battle in 3D, stage D1"): procedural meshes in the ship's own
## frame (x forward, y up, z to starboard, metres; the view stands the node at the ship's place and turns it by -heading). The hull
## is built once per ship (a prism of the 2D screen's seven-point outline: waterline, rail in the faction colour, deck, gunports, a stern
## castle, the bowsprit, a galley's ram); the rig is rebuilt as the ship's state changes (masts, yards, square sails braced with the
## relative wind and bellied by the drive, fewer and holed as the rigging goes, furled hove to or struck, the sloop's fore-and-aft sail
## with its boom to leeward) and the flags every frame (the ensign and a masthead pennant, downwind). It reads the sim only.

const ST := preload("res://sim/sea_types.gd")
const FM := preload("res://sim/fixed_math.gd")

const COL_SAIL := Color(0.96, 0.94, 0.86)
const COL_HULL := Color(0.42, 0.27, 0.16)
const COL_DECK := Color(0.68, 0.55, 0.37)
const COL_MAST := Color(0.25, 0.17, 0.10)
const COL_PORT := Color(0.08, 0.06, 0.05)
const BELOW := -1.2             # the hull's keel below the water (the water plane cuts it)


const MODELS_PATH := "res://assets/battlekit_ob/ships3d.res"
const MODELS_TEX := "res://assets/battlekit_ob/ships3d_albedo.png"
const MODEL_VIS := 2.0            # the VIS the models were built at (tools/battlekit/export_ships.py)

static var _m_done := false
static var _m_src: ArrayMesh
static var _m_tex: Texture2D
static var _m_info := {}          # row key -> [surface, triangles, length m, beam m, freeboard m]
static var _m_cache := {}         # row key -> its own one-surface ArrayMesh
static var _m_flat := {}          # row key -> {"p": PackedVector3Array per corner, "c": base colour per triangle, "m": mask per triangle, "n": ...}


## Loads the ship models once; false when assets/battlekit_ob/ships3d.res is missing (or `--no-ship-models`, a testing aid): every
## row then keeps the procedural solid.
static func models_ok() -> bool:
	if not _m_done:
		_m_done = true
		if "--no-ship-models" in OS.get_cmdline_user_args():
			return false
		if ResourceLoader.exists(MODELS_PATH) and ResourceLoader.exists(MODELS_TEX):
			_m_src = load(MODELS_PATH) as ArrayMesh
			_m_tex = load(MODELS_TEX) as Texture2D
			if _m_src != null and _m_tex != null and _m_src.has_meta("models"):
				_m_info = _m_src.get_meta("models")
	return not _m_info.is_empty()


static func model_key(ty: int) -> String:
	return str(ST.ROWS[ty]["key"])


static func has_model(key: String) -> bool:
	return models_ok() and _m_info.has(key)


static func model_tris(key: String) -> int:
	return int((_m_info[key] as Array)[1]) if has_model(key) else 0


## The model's own one-surface mesh (cut out of the source once), or null.
static func model(key: String) -> ArrayMesh:
	if not has_model(key):
		return null
	if _m_cache.has(key):
		return _m_cache[key]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _m_src.surface_get_arrays(int((_m_info[key] as Array)[0])))
	am.surface_set_name(0, key)
	_m_cache[key] = am
	return am


## The model's freeboard (the deck's height amidships, metres, at MODEL_VIS).
static func model_len(key: String) -> float:
	return float((_m_info[key] as Array)[2]) if has_model(key) else 1.0


static func model_beam(key: String) -> float:
	return float((_m_info[key] as Array)[3]) if has_model(key) else 1.0


static func model_fb(key: String) -> float:
	return float((_m_info[key] as Array)[4]) if has_model(key) else 0.0


## The ship model's material: the swatch atlas and the faction's colour (`treasure` gilds a galleon's castle).
static func model_material(rail: Color, treasure: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://game/sea_ship3d_model.gdshader")
	m.set_shader_parameter("albedo_tex", _m_tex)
	m.set_shader_parameter("faction", Vector3(rail.r, rail.g, rail.b))
	m.set_shader_parameter("treasure", 1.0 if treasure else 0.0)
	return m


## The model as flat triangles for a one-colour-a-triangle consumer (the land battle's shore ships, game/ship_layer.gd): {"p": corner
## positions in the model's frame (x forward, y up, z starboard; 3 a triangle), "c": the swatch's colour at the triangle's centre
## times its occlusion, "m": the mask class}. Cached.
static func model_flat(key: String) -> Dictionary:
	if not has_model(key):
		return {}
	if _m_flat.has(key):
		return _m_flat[key]
	var arr: Array = _m_src.surface_get_arrays(int((_m_info[key] as Array)[0]))
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var img := _m_tex.get_image()
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var p := PackedVector3Array()
	var c := PackedColorArray()
	var mk := PackedFloat32Array()
	for t in ix.size() / 3:
		var a := ix[t * 3]
		var b := ix[t * 3 + 1]
		var d := ix[t * 3 + 2]
		p.append(v[a])
		p.append(v[b])
		p.append(v[d])
		var cuv := (uv[a] + uv[b] + uv[d]) / 3.0
		var col := img.get_pixel(clampi(int(cuv.x * w), 0, w - 1), clampi(int(cuv.y * h), 0, h - 1))
		var ao := (uv2[a].y + uv2[b].y + uv2[d].y) / 3.0
		c.append(Color(col.r * ao, col.g * ao, col.b * ao))
		mk.append((uv2[a].x + uv2[b].x + uv2[d].x) / 3.0)
	var out := {"p": p, "c": c, "m": mk}
	_m_flat[key] = out
	return out


## A mesh builder: flat-normal triangles with a colour each.
class Buf:
	extends RefCounted
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()

	func tri(a: Vector3, b: Vector3, d: Vector3, col: Color) -> void:
		var nn := (b - a).cross(d - a)
		nn = nn.normalized() if nn.length_squared() > 1e-12 else Vector3.UP
		v.append(a)
		v.append(b)
		v.append(d)
		n.append(nn)
		n.append(nn)
		n.append(nn)
		c.append(col)
		c.append(col)
		c.append(col)

	func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, col: Color) -> void:
		tri(a, b, d, col)
		tri(a, d, e, col)

	## A thin four-sided bar from p0 to p1, `w` wide.
	func bar(p0: Vector3, p1: Vector3, w: float, col: Color) -> void:
		var d := p1 - p0
		if d.length_squared() < 1e-9:
			return
		d = d.normalized()
		var u := d.cross(Vector3.UP)
		if u.length_squared() < 1e-4:
			u = d.cross(Vector3.RIGHT)
		u = u.normalized() * w * 0.5
		var s := d.cross(u).normalized() * w * 0.5
		var a0 := p0 + u + s
		var a1 := p0 - u + s
		var a2 := p0 - u - s
		var a3 := p0 + u - s
		var b0 := p1 + u + s
		var b1 := p1 - u + s
		var b2 := p1 - u - s
		var b3 := p1 + u - s
		quad(a0, a1, b1, b0, col)
		quad(a1, a2, b2, b1, col)
		quad(a2, a3, b3, b2, col)
		quad(a3, a0, b0, b3, col)

	## An axis-aligned box (the ship's frame): centre, full sizes.
	func box(ctr: Vector3, sx: float, sy: float, sz: float, col: Color) -> void:
		var h := Vector3(sx, sy, sz) * 0.5
		var p := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
			Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
		for i in 8:
			p[i] = (p[i] as Vector3) + ctr
		quad(p[4], p[5], p[6], p[7], col)   # top
		quad(p[0], p[3], p[2], p[1], col.darkened(0.3))
		quad(p[0], p[1], p[5], p[4], col.darkened(0.12))
		quad(p[2], p[3], p[7], p[6], col.darkened(0.12))
		quad(p[3], p[0], p[4], p[7], col.darkened(0.2))
		quad(p[1], p[2], p[6], p[5], col.darkened(0.2))

	func mesh(into: ArrayMesh = null) -> ArrayMesh:
		var am := into if into != null else ArrayMesh.new()
		am.clear_surfaces()
		if v.is_empty():
			return am
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return am


## The masts' places along the keel (fractions of the length), as the 2D screen's rig: a sloop's one, a brigantine's two, three.
static func masts_at(ty: int) -> Array:
	if ST.stat(ty, "oars") != 0 and not ST.is_galley(ty):
		return []   # a dugout: paddlers, no mast
	if ST.is_galley(ty):
		return [0.05]
	var m := ST.masts(ty)
	if m == 1:
		return [0.12]
	if m == 2:
		return [0.22, -0.12]
	return [0.3, 0.02, -0.25]


## Sizes of a ship drawn `vis` times her length: {ln, bm, fb (freeboard), mh (the mainmast's height)}.
static func dims(ty: int, vis: float) -> Dictionary:
	var ln := float(ST.stat(ty, "len")) * vis
	var bm := float(ST.stat(ty, "beam")) * vis
	return {"ln": ln, "bm": bm, "fb": clampf(bm * 0.28, 0.9, 3.6), "mh": clampf(ln * 0.46, 8.0, 27.0)}


static func outline(ln: float, bm: float, oars: bool) -> PackedVector2Array:
	if oars:
		return PackedVector2Array([Vector2(ln * 0.5, 0), Vector2(ln * 0.25, bm * 0.5), Vector2(-ln * 0.3, bm * 0.5),
			Vector2(-ln * 0.5, 0), Vector2(-ln * 0.3, -bm * 0.5), Vector2(ln * 0.25, -bm * 0.5)])
	return PackedVector2Array([Vector2(ln * 0.5, 0), Vector2(ln * 0.3, bm * 0.5), Vector2(-ln * 0.38, bm * 0.5),
		Vector2(-ln * 0.5, bm * 0.36), Vector2(-ln * 0.5, -bm * 0.36), Vector2(-ln * 0.38, -bm * 0.5), Vector2(ln * 0.3, -bm * 0.5)])


static func _p(v: Vector2, y: float, k: float = 1.0) -> Vector3:
	return Vector3(v.x * k, y, v.y * k)


## The hull, once: `rail` the faction's colour, `gold` a treasure galleon's castle.
static func hull(ty: int, vis: float, rail: Color, gold: bool) -> ArrayMesh:
	var d := dims(ty, vis)
	var ln: float = d["ln"]
	var bm: float = d["bm"]
	var fb: float = d["fb"]
	var oars := ST.stat(ty, "oars") != 0
	var fire := ST.is_fire(ty)
	var b := Buf.new()
	var pts := outline(ln, bm, oars)
	var hc := COL_HULL.darkened(0.55) if fire else COL_HULL
	var dc := Color(0.36, 0.3, 0.22) if fire else COL_DECK
	var n := pts.size()
	for i in n:
		var p0 := pts[i]
		var p1 := pts[(i + 1) % n]
		# Keel to waterline to rim: the hull tucks in under the water.
		b.quad(_p(p0, BELOW, 0.7), _p(p1, BELOW, 0.7), _p(p1, 0.0, 0.96), _p(p0, 0.0, 0.96), hc.darkened(0.25))
		b.quad(_p(p0, 0.0, 0.96), _p(p1, 0.0, 0.96), _p(p1, fb - 0.55, 1.0), _p(p0, fb - 0.55, 1.0), hc)
		# The rail's stripe in the faction colour, then the inner wall down to the deck.
		b.quad(_p(p0, fb - 0.55, 1.0), _p(p1, fb - 0.55, 1.0), _p(p1, fb, 1.0), _p(p0, fb, 1.0), rail)
		b.quad(_p(p0, fb, 1.0), _p(p1, fb, 1.0), _p(p1, fb - 0.3, 0.92), _p(p0, fb - 0.3, 0.92), hc.lightened(0.1))
	# The deck, a fan.
	for i in n:
		b.tri(Vector3(0, fb - 0.3, 0), _p(pts[(i + 1) % n], fb - 0.3, 0.92), _p(pts[i], fb - 0.3, 0.92), dc)
	# Gunports along both sides.
	var guns := clampi(ST.stat(ty, "guns"), 0, 18)
	var gp := clampi(guns / 2 + 1, 1, 9) if guns > 0 else 0
	for i in gp:
		var f := (float(i) + 0.5) / gp - 0.5
		for sg in [-1.0, 1.0]:
			var x := f * ln * 0.66
			var z: float = sg * bm * 0.5 * 0.985
			var pw := maxf(bm * 0.07, 0.5)
			var y0 := fb * 0.18
			var y1 := fb * 0.18 + pw * 1.2
			b.quad(Vector3(x - pw, y0, z), Vector3(x + pw, y0, z), Vector3(x + pw, y1, z), Vector3(x - pw, y1, z), COL_PORT)
	# The stern castle of the bigger sailing ships (a treasure galleon's gilded).
	if not oars and not fire and ln >= 40.0 * vis * 0.9:
		var cx := -ln * 0.375
		var ch := bm * 0.3
		b.box(Vector3(cx, fb + ch * 0.5 - 0.3, 0), ln * 0.19, ch, bm * 0.74, Color(0.85, 0.7, 0.3) if gold else COL_HULL.lightened(0.15))
		b.box(Vector3(cx - ln * 0.02, fb + ch + 0.1, 0), ln * 0.14, 0.4, bm * 0.7, rail)
	# The bowsprit; a galley's bronze ram at the waterline.
	if not oars:
		b.bar(Vector3(ln * 0.46, fb * 0.8, 0), Vector3(ln * 0.46 + ln * 0.2, fb + ln * 0.05, 0), maxf(0.5, bm * 0.05), COL_MAST)
	elif ST.stat(ty, "ram") > 0:
		var tip := Vector3(ln * 0.5 + bm * 0.9, -0.1, 0)
		var br := Color(0.72, 0.5, 0.22)
		b.tri(Vector3(ln * 0.5, 0.5, bm * 0.2), Vector3(ln * 0.5, 0.5, -bm * 0.2), tip, br)
		b.tri(Vector3(ln * 0.5, -0.6, bm * 0.2), tip, Vector3(ln * 0.5, -0.6, -bm * 0.2), br.darkened(0.3))
		b.tri(Vector3(ln * 0.5, 0.5, bm * 0.2), tip, Vector3(ln * 0.5, -0.6, bm * 0.2), br.darkened(0.15))
		b.tri(Vector3(ln * 0.5, 0.5, -bm * 0.2), Vector3(ln * 0.5, -0.6, -bm * 0.2), tip, br.darkened(0.15))
	if fire:
		# Brushwood, tar barrels and brimstone stacked on deck.
		for k in 6:
			var bp := Vector3((float(k) / 5.0 - 0.5) * ln * 0.6, fb + 0.2, (0.18 if k % 2 == 0 else -0.18) * bm)
			b.box(bp, bm * 0.26, bm * 0.26, bm * 0.26, Color(0.55, 0.42, 0.2) if k % 3 != 0 else Color(0.25, 0.2, 0.15))
	# A dugout: the paddlers' strokes along both sides are the oars' D2; a thwart or two for the eye.
	return b.mesh()


## The rig, as the ship stands: the sail sheets braced with the relative wind. `st` the ship's facts (see SeaView3D._rig_args):
## ty, vis, rig (0..1), furled, rel (1024ths: 0 running), drv (0..1+), wtl (the wind's way in the ship's frame, x forward, y to
## starboard), seed (holes). Returns nothing: the Buf is filled.
static func rig(b: Buf, ty: int, vis: float, rigf: float, furled: bool, rel: float, drv: float, wtl: Vector2, seed_i: int,
		lee_dir: float, boom_swing: float) -> void:
	var d := dims(ty, vis)
	var ln: float = d["ln"]
	var bm: float = d["bm"]
	var fb: float = d["fb"]
	var mh: float = d["mh"]
	var masts := masts_at(ty)
	if masts.is_empty():
		return
	var galley := ST.is_galley(ty)
	var one := masts.size() == 1 and not galley
	var brace := clampf(rel * 0.55, -150.0, 150.0) * TAU / 1024.0
	var yard := Vector2(-sin(brace), cos(brace))
	var mw := maxf(0.6, bm * 0.07)
	var holes := (1.0 - rigf) * 0.5 if rigf < 0.9 else 0.0
	var belly_dir := (Vector2(1, 0) * 0.75 + wtl * 0.25).normalized()
	var amp := bm * (0.12 + 0.28 * clampf(drv, 0.0, 1.2)) * (0.6 + 0.4 * rigf)
	for i in masts.size():
		var mx := float(masts[i]) * ln
		var top := mh * (1.0 if i == 0 or masts.size() == 1 else (0.92 if i == 1 else 0.8))
		if galley:
			top = mh * 0.8
		if rigf < 0.3 and i > 0:
			# Shot away: a stump leaning over the side.
			b.bar(Vector3(mx, fb, 0), Vector3(mx, fb + top * 0.22, bm * 0.12), mw * 1.2, COL_MAST)
			continue
		b.bar(Vector3(mx, fb - 0.2, 0), Vector3(mx, fb + top, 0), mw, COL_MAST)
		if one:
			# The boom swings to leeward; the fore-and-aft sail between mast and boom.
			var aft := Vector2(-1, 0).rotated(lee_dir * boom_swing)
			var y0 := fb + top * 0.28
			var tip := Vector3(mx + aft.x * ln * 0.55, y0, aft.y * ln * 0.55)
			b.bar(Vector3(mx, y0, 0), tip, mw * 0.8, COL_MAST)
			if furled:
				b.bar(Vector3(mx, y0 + 0.4, 0), tip + Vector3(0, 0.4, 0), mw * 1.3, COL_SAIL.darkened(0.1))
			else:
				var bl := Vector2(-aft.y, aft.x) * lee_dir * -1.0 * ln * 0.12 * clampf(drv, 0.0, 1.2)
				var seg := 5
				for k in seg:
					var t0 := float(k) / seg
					var t1 := float(k + 1) / seg
					var h0 := y0 + (top * 0.95 - top * 0.28) * (1.0 - t0)
					var h1 := y0 + (top * 0.95 - top * 0.28) * (1.0 - t1)
					var o0 := bl * sin(t0 * PI)
					var o1 := bl * sin(t1 * PI)
					if holes > 0.0 and fposmod(float(seed_i * 31 + k * 17) * 0.6180339, 1.0) < holes:
						continue
					var a0 := Vector3(mx + aft.x * ln * 0.55 * t0 + o0.x, y0, aft.y * ln * 0.55 * t0 + o0.y)
					var a1 := Vector3(mx + aft.x * ln * 0.55 * t1 + o1.x, y0, aft.y * ln * 0.55 * t1 + o1.y)
					b.quad(a0, a1, Vector3(a1.x, h1, a1.z), Vector3(a0.x, h0, a0.z), COL_SAIL)
			continue
		var span_lo := bm * (1.8 if not galley else 1.2)
		var span_hi := bm * 1.25
		var rows := [[0.5, 0.4, span_lo], [0.88, 0.3, span_hi]]
		if galley:
			rows = [[0.7, 0.4, span_lo]]
		for ri in rows.size():
			var yv: float = fb + top * float(rows[ri][0])
			var sh: float = top * float(rows[ri][1])
			var span: float = rows[ri][2]
			if ri == 1 and rigf < 0.55 and not galley:
				continue   # the topsail goes first
			var a := Vector2(mx, 0) - yard * span * 0.5
			var e := Vector2(mx, 0) + yard * span * 0.5
			b.bar(Vector3(a.x, yv, a.y), Vector3(e.x, yv, e.y), mw * 0.7, COL_MAST)
			if furled or galley:
				b.bar(Vector3(a.x, yv - 0.35, a.y), Vector3(e.x, yv - 0.35, e.y), maxf(0.9, bm * 0.12), COL_SAIL.darkened(0.1))
				continue
			var cols := 6
			var nr := 3
			for r in nr:
				var s0 := float(r) / nr
				var s1 := float(r + 1) / nr
				var y_0 := yv - sh * s0
				var y_1 := yv - sh * s1
				var f0 := 0.45 + 0.55 * s0
				var f1 := 0.45 + 0.55 * s1
				for c in cols:
					var t0 := float(c) / cols
					var t1 := float(c + 1) / cols
					if holes > 0.0 and fposmod(float(seed_i * 31 + i * 7 + ri * 13 + r * 5 + c) * 0.6180339, 1.0) < holes:
						continue
					var q00 := a.lerp(e, t0) + belly_dir * amp * sin(t0 * PI) * f0
					var q10 := a.lerp(e, t1) + belly_dir * amp * sin(t1 * PI) * f0
					var q01 := a.lerp(e, t0) + belly_dir * amp * sin(t0 * PI) * f1
					var q11 := a.lerp(e, t1) + belly_dir * amp * sin(t1 * PI) * f1
					b.quad(Vector3(q00.x, y_0, q00.y), Vector3(q10.x, y_0, q10.y), Vector3(q11.x, y_1, q11.y), Vector3(q01.x, y_1, q01.y), COL_SAIL)


## The ensign (at the stern) and a pennant at the masthead, flying downwind (`wtl`), in `ens` / `pen` colours; `t` the clock.
static func flags(b: Buf, ty: int, vis: float, wtl: Vector2, ens: Color, pen: Color, t: float, seed_i: int, show_pennant: bool) -> void:
	var d := dims(ty, vis)
	var ln: float = d["ln"]
	var fb: float = d["fb"]
	var mh: float = d["mh"]
	var fl := maxf(ln * 0.22, 5.0)
	var fh := fl * 0.55
	var sx := -ln * 0.5 + 0.6
	var yt := fb + ln * 0.2 + fh
	b.bar(Vector3(sx, fb, 0), Vector3(sx, yt + 0.4, 0), 0.4, COL_MAST)
	var perp := Vector2(-wtl.y, wtl.x)
	var seg := 4
	for k in seg:
		var t0 := float(k) / seg
		var t1 := float(k + 1) / seg
		var w0 := sin(t0 * 5.0 - t * 9.0 + seed_i) * fl * 0.07 * t0
		var w1 := sin(t1 * 5.0 - t * 9.0 + seed_i) * fl * 0.07 * t1
		var p0 := wtl * fl * t0 + perp * w0
		var p1 := wtl * fl * t1 + perp * w1
		b.quad(Vector3(sx + p0.x, yt, p0.y), Vector3(sx + p1.x, yt, p1.y), Vector3(sx + p1.x, yt - fh, p1.y), Vector3(sx + p0.x, yt - fh, p0.y), ens)
	if show_pennant:
		var masts := masts_at(ty)
		if not masts.is_empty():
			var mx := float(masts[0]) * ln
			var top := mh if not ST.is_galley(ty) else mh * 0.8
			var pl := maxf(ln * 0.18, 4.0)
			var ph := pl * 0.14
			var tip := wtl * pl + perp * sin(t * 11.0 + seed_i * 2.0) * pl * 0.1
			b.tri(Vector3(mx, fb + top + ph, 0), Vector3(mx, fb + top - ph, 0), Vector3(mx + tip.x, fb + top, tip.y), pen)
