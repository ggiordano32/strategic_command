extends RefCounted
## The sea battle's bob, foam rings and wakes in 3D (stage D2 part 2; docs/design/sea.md "The sea battle in 3D, stage D2"). View only.
##  - the ride (lift, pitch and roll) of a hull comes from game/sea_swell3d.gd, the CPU twin of the displaced water's vertex stage, so
##    hull and water agree; this file keeps the foam ring, the wakes and their texture. Graphics Low draws none of it.
##  - ring_mesh(): the foam ring a hull wears at the waterline (the outline widened, white to nothing outward) as a flat decal on the water,
##    since the compatibility renderer has no depth texture to find the waterline from.
##  - Wakes: fading ribbon strips on the water from the host's wake points (SeaBattle._wake, the 2D screen's own: a point every 0.4 s,
##    14 kept), widening and fading with age, plus the bow wave's two short moustaches, one ImmediateMesh for all ships.

const SeaShip := preload("res://game/sea_ship3d.gd")

const WAKE_Y := 0.06
const RING_Y := 0.08


## The hull's foam ring in the ship's frame (x forward, z starboard): a strip from just inside the waterline outline out `w` metres,
## vertex alpha 0.85 to 0; uv x along the ring (a repeat every 9 m), uv y across.
static func ring_mesh(ty: int, vis: float, w: float) -> ArrayMesh:
	var d := SeaShip.dims(ty, vis)
	var ln: float = d["ln"]
	var bm: float = d["bm"]
	var pts := SeaShip.outline(ln, bm, is_oared(ty))
	var n := pts.size()
	var pv := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var acc := 0.0
	for i in n + 1:
		var a: Vector2 = pts[i % n] * 0.9
		var prev: Vector2 = pts[(i + n - 1) % n]
		var next: Vector2 = pts[(i + 1) % n]
		var tang := (next - prev).normalized()
		var out := Vector2(tang.y, -tang.x)   # (the outline runs clockwise in x, z)
		if out.dot(a) < 0.0:
			out = -out
		if i > 0:
			acc += a.distance_to(pts[(i - 1) % n] * 0.9)
		var o := a + out * w * (1.0 + (0.9 if (i % n) == 0 else 0.0))
		pv.append(Vector3(a.x, 0.0, a.y))
		pv.append(Vector3(o.x, 0.0, o.y))
		uv.append(Vector2(acc / 9.0, 0.0))
		uv.append(Vector2(acc / 9.0, 1.0))
		col.append(Color(1, 1, 1, 0.85))
		col.append(Color(1, 1, 1, 0.0))
		if i > 0:
			var b := (i - 1) * 2
			idx.append_array(PackedInt32Array([b, b + 1, b + 3, b, b + 3, b + 2]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pv
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


static func is_oared(ty: int) -> bool:
	return SeaShip.ST.stat(ty, "oars") != 0


## The foam material (flat, unshaded, alpha by the vertex colour times the bubbly texture).
static func foam_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.texture_repeat = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.render_priority = 1
	return m


## A tileable bubbly foam strip: u along (wraps), v across (soft edges), white with the alpha broken into bubbles.
static func foam_strip_texture() -> ImageTexture:
	var w := 64
	var hh := 32
	var tab := PackedFloat32Array()
	for q in 1024:
		tab.append(float((q * 73856093 ^ (q >> 3) * 19349663 ^ 0x5bd1e995) & 0xFFFF) / 65535.0)
	var img := Image.create(w, hh, false, Image.FORMAT_RGBA8)
	for y in hh:
		for x in w:
			var v := (y + 0.5) / hh * 2.0 - 1.0
			var edge := 1.0 - absf(v)
			var n1 := tab[((x >> 2) % 16) * 16 + ((y >> 2) % 16)]
			var n2 := tab[(((x * 5) >> 1) % 32) * 16 + ((y * 3) % 16)] * 0.6 + tab[(x * 7 + y * 13 + 5) % 1024] * 0.4
			var a := smoothstep(0.30, 0.62, n1 * 0.55 + n2 * 0.45 + edge * 0.55 - 0.18)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## One frame of every ship's wake into `mesh` (cleared first): `ships` a list of {pts: PackedVector2Array oldest first (the last the
## ship's place), beam, speed 0..1, heading}. Ribbons widen with age and fade; the bow wave is two moustaches at speed.
static func build_wakes(mesh: ImmediateMesh, ships: Array, lift: Callable) -> int:
	mesh.clear_surfaces()
	var count := 0
	var started := false
	for sh in ships:
		var pts: PackedVector2Array = sh["pts"]
		var n := pts.size()
		if n < 2:
			continue
		var beam: float = sh["beam"]
		var speed: float = sh["speed"]
		var acc := 0.0
		# The ribbon: a cross-section at every point, the width and the alpha by age.
		var left: Array = []
		var right: Array = []
		var lifts: Array = []   # the swell's height at each cross-section (one sample a point, not a vertex)
		var us: Array = []
		var als: Array = []
		for i in n:
			var f := float(i) / float(n - 1)
			var a: Vector2 = pts[maxi(i - 1, 0)]
			var b: Vector2 = pts[mini(i + 1, n - 1)]
			var tang := (b - a)
			if tang.length() < 0.001:
				tang = Vector2(1, 0)
			tang = tang.normalized()
			var nrm := Vector2(-tang.y, tang.x)
			var wd := beam * (0.5 + (1.0 - f) * 1.7)
			if i > 0:
				acc += pts[i].distance_to(pts[i - 1])
			lifts.append(float(lift.call(pts[i])))
			left.append(pts[i] + nrm * wd)
			right.append(pts[i] - nrm * wd)
			us.append(acc / (beam * 3.0))
			als.append(0.55 * pow(f, 0.9) * clampf(0.35 + speed, 0.0, 1.0))
		for i in n - 1:
			if (pts[i + 1] - pts[i]).length() < 0.3:
				continue
			if not started:
				mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				started = true
			var quad := [[left[i], us[i], 0.0, als[i], lifts[i]], [right[i], us[i], 1.0, als[i], lifts[i]], [right[i + 1], us[i + 1], 1.0, als[i + 1], lifts[i + 1]],
				[left[i], us[i], 0.0, als[i], lifts[i]], [right[i + 1], us[i + 1], 1.0, als[i + 1], lifts[i + 1]], [left[i + 1], us[i + 1], 0.0, als[i + 1], lifts[i + 1]]]
			for q in quad:
				mesh.surface_set_color(Color(1, 1, 1, float(q[3])))
				mesh.surface_set_uv(Vector2(float(q[1]), float(q[2])))
				mesh.surface_add_vertex(Vector3((q[0] as Vector2).x, WAKE_Y + float(q[4]), (q[0] as Vector2).y))
			count += 1
		# The bow wave.
		if speed > 0.08:
			var head := pts[n - 1]
			var bow_lift := float(lifts[n - 1])
			var fw := Vector2(cos(float(sh["heading"])), sin(float(sh["heading"])))
			var sd := Vector2(-fw.y, fw.x)
			for sg in [-1.0, 1.0]:
				var a0 := head + fw * beam * 1.9 + sd * float(sg) * beam * 0.1
				var a1 := head + fw * beam * 0.1 + sd * float(sg) * beam * (0.9 + 1.2 * speed)
				var nn := (a1 - a0).normalized()
				var pr := Vector2(-nn.y, nn.x) * beam * 0.4
				if not started:
					mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
					started = true
				var al := 0.7 * speed
				var corners := [[a0 + pr, 0.0, 0.0, al], [a0 - pr, 0.0, 1.0, al], [a1 - pr, 1.0, 1.0, 0.0],
					[a0 + pr, 0.0, 0.0, al], [a1 - pr, 1.0, 1.0, 0.0], [a1 + pr, 1.0, 0.0, 0.0]]
				for q in corners:
					mesh.surface_set_color(Color(1, 1, 1, float(q[3])))
					mesh.surface_set_uv(Vector2(float(q[1]), float(q[2])))
					mesh.surface_add_vertex(Vector3((q[0] as Vector2).x, WAKE_Y + bow_lift, (q[0] as Vector2).y))
				count += 1
	if started:
		mesh.surface_end()
	return count
