extends RefCounted
## The wall rings of the overworld towns (map-table style, view only): a town's curtain is one mitred ring drawn as
## polygons at the kit's camera (52 degrees from the vertical, the light from the north-west), not a row of 6 m
## pieces. The plan (town_plan.gd) walks the trace as a closed loop, cuts it where a gate, a tower or a bastion
## point stands (those stay sprites) and where the harbour is left open, and hands the runs over here:
##   cmds(ring, detail)    the ring as triangle soups, one per stretch, each with the y it sorts by (the foot of
##                         the stretch's centre line), sorted: the town layer merges them with the pieces by y
##   shadow_polys(ring)    the stretches' cast shadows on the ground (south-east), for the town ground's paint
##   foot_polys(ring)      the contact band round the foot, for the same
## Each ring is {"kind": "stone" | "bast" | "star" | "pal", "runs": [PackedVector2Array of world px, travelling clockwise on
## the screen so the outside is on the left of the direction (d.y, -d.x)], "t": thickness in metres (0 the kind's)}.
## Cross-section (the kit's pieces, heights exaggerated by the kit's 1.7): the body to hb, the cap band to hc, the
## walk on top at hc, merlons (stone) to hm on the outer lip at the kit's 2.4 m spacing; bastioned walls (West) have
## a cornice and no merlons; a palisade is a row of stakes. Every vertex of a run is mitred, so adjacent faces share
## their edge exactly. `detail` false (the small atlas, Graphics Low) draws the faces flat: no courses, merlons as
## one band, stakes as one block each.

const K := 1.2                      # world px a metre
const KZ := K * 0.788               # screen px a metre of height at 52 degrees from the vertical (sin 52)
const MITRE_MAX := 3.0              # a mitre longer than this many half thicknesses is bevelled

# Colours sampled from the painted big atlas (the kit sprites the ring joins): a face is the sprite's south face divided by
# the brightness `_lit` gives a south face (0.94), tops are the sprites' lit tops, `ink` the sprites' outline tone.
const SPEC := {
	"stone": {"t": 3.2, "hb": 7.5, "hc": 8.7, "hm": 10.1, "mt": 1.5, "ml": 1.15, "pitch": 2.4, "course": 1.5, "ink": Color(0.30, 0.27, 0.23),
		"face": Color(0.74, 0.71, 0.69), "cap": Color(0.58, 0.56, 0.59), "top": Color(0.60, 0.58, 0.57), "mtop": Color(0.68, 0.65, 0.60)},
	"bast": {"t": 4.4, "hb": 6.1, "hc": 7.1, "hm": 7.1, "mt": 0.0, "ml": 0.0, "pitch": 2.4, "course": 1.7, "ink": Color(0.40, 0.33, 0.20),
		"face": Color(0.76, 0.68, 0.51), "cap": Color(0.76, 0.70, 0.61), "top": Color(0.80, 0.72, 0.56), "mtop": Color(0.80, 0.72, 0.56)},
	"star": {"t": 1.9, "hb": 6.1, "hc": 7.1, "hm": 7.1, "mt": 0.0, "ml": 0.0, "pitch": 2.4, "course": 1.7, "ink": Color(0.30, 0.23, 0.12),
		"face": Color(0.62, 0.55, 0.42), "cap": Color(0.66, 0.62, 0.56), "top": Color(0.74, 0.67, 0.52), "mtop": Color(0.74, 0.67, 0.52)},
	"pal": {"t": 1.4, "hb": 8.2, "hc": 8.2, "hm": 10.6, "mt": 0.0, "ml": 0.95, "pitch": 0.95, "course": 0.0, "ink": Color(0.16, 0.06, 0.01),
		"face": Color(0.52, 0.31, 0.08), "cap": Color(0.14, 0.04, 0.0), "top": Color(0.52, 0.31, 0.08), "mtop": Color(0.60, 0.36, 0.09)},
}
# the kit's light (build.py: the key from the north-west, a fill from the camera's side) as a brightness on a face
# with the screen normal n (y down): the south and south-east faces catch the fill, the west ones the key, the
# south-west ones neither much
const KEY_TO := Vector3(-0.55, 0.45, 0.70)
const FILL_TO := Vector3(0.25, -0.60, 0.76)


class Soup:
	var idx := PackedInt32Array()
	var pts := PackedVector2Array()
	var cols := PackedColorArray()

	func quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
		quad4(a, b, c, d, col, col, col, col)

	## a, b, c, d around the quad with a colour each (a, b the lower edge, c, d the upper: a gradient up the face).
	func quad4(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
		var i := pts.size()
		pts.append(a)
		pts.append(b)
		pts.append(c)
		pts.append(d)
		cols.append(ca)
		cols.append(cb)
		cols.append(cc)
		cols.append(cd)
		idx.append(i)
		idx.append(i + 1)
		idx.append(i + 2)
		idx.append(i)
		idx.append(i + 2)
		idx.append(i + 3)

	func tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
		var i := pts.size()
		pts.append(a)
		pts.append(b)
		pts.append(c)
		cols.append(col)
		cols.append(col)
		cols.append(col)
		idx.append(i)
		idx.append(i + 1)
		idx.append(i + 2)


static func thickness(ring: Dictionary) -> float:
	var t := float(ring.get("t", 0.0))
	return t if t > 0.0 else float((SPEC[ring["kind"]] as Dictionary)["t"])


## The outward unit normal of the edge a to b of a loop travelling clockwise on the screen.
static func out_normal(a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	var l := d.length()
	return Vector2(d.y, -d.x) / l if l > 0.0001 else Vector2.ZERO


## A closed loop offset by d px (positive: outwards), every vertex mitred (bevelled where the corner is too sharp).
static func offset_loop(loop: PackedVector2Array, d: float) -> PackedVector2Array:
	var n := loop.size()
	var out := PackedVector2Array()
	for j in n:
		var na := out_normal(loop[(j + n - 1) % n], loop[j])
		var nb := out_normal(loop[j], loop[(j + 1) % n])
		out.append(loop[j] + _mitre(na, nb) * d)
	return out


## The vector that moves a vertex one unit sideways between edges with normals na and nb.
static func _mitre(na: Vector2, nb: Vector2) -> Vector2:
	var s := na + nb
	var dt := 1.0 + na.dot(nb)
	if dt < 1.0 / (MITRE_MAX * MITRE_MAX) * 2.0 or s.length() < 0.0001:
		return (s.normalized() if s.length() > 0.0001 else na)
	return s / dt


## The parts of a closed loop (or an open polyline) outside every cut circle [centre, radius] and not on an open edge
## (open[e] true: edge e, from vertex e to e + 1, is left out). Returns the runs, each a PackedVector2Array of at
## least 3 px. A run keeps its direction.
static func clip_runs(loop: PackedVector2Array, closed: bool, circles: Array, open: PackedByteArray = PackedByteArray()) -> Array:
	var runs: Array = []
	var cur := PackedVector2Array()
	var ne := loop.size() if closed else loop.size() - 1
	for e in ne:
		var a := loop[e]
		var b := loop[(e + 1) % loop.size()]
		if e < open.size() and open[e] != 0:
			_flush(runs, cur)
			cur = PackedVector2Array()
			continue
		var cutl: Array = []   # intervals [t0, t1] inside a circle
		for cc in circles:
			var iv := _inside(a, b, cc[0] as Vector2, float(cc[1]))
			if not iv.is_empty():
				cutl.append(iv)
		cutl.sort_custom(func(p, q): return float(p[0]) < float(q[0]))
		var t := 0.0
		var kept: Array = []
		for iv in cutl:
			if float(iv[0]) > t:
				kept.append([t, float(iv[0])])
			t = maxf(t, float(iv[1]))
		if t < 1.0:
			kept.append([t, 1.0])
		for kp in kept:
			var k0: float = kp[0]
			var k1: float = kp[1]
			if k1 - k0 < 0.0001:
				continue
			if k0 > 0.0001 or cur.is_empty():
				if not cur.is_empty():
					_flush(runs, cur)
					cur = PackedVector2Array()
				cur.append(a.lerp(b, k0))
			cur.append(a.lerp(b, k1))
			if k1 < 0.9999:
				_flush(runs, cur)
				cur = PackedVector2Array()
		if kept.is_empty():
			_flush(runs, cur)
			cur = PackedVector2Array()
	_flush(runs, cur)
	return runs


static func _flush(runs: Array, cur: PackedVector2Array) -> void:
	if cur.size() < 2:
		return
	var l := 0.0
	for i in cur.size() - 1:
		l += cur[i].distance_to(cur[i + 1])
	if l >= 2.5:
		runs.append(cur)


## The interval of t in 0..1 where a + t (b - a) lies inside the circle, [] when none.
static func _inside(a: Vector2, b: Vector2, c: Vector2, r: float) -> Array:
	var d := b - a
	var f := a - c
	var qa := d.dot(d)
	if qa < 0.000001:
		return []
	var qb := 2.0 * f.dot(d)
	var qc := f.dot(f) - r * r
	var disc := qb * qb - 4.0 * qa * qc
	if disc <= 0.0:
		return []
	var sq := sqrt(disc)
	var t0 := (-qb - sq) / (2.0 * qa)
	var t1 := (-qb + sq) / (2.0 * qa)
	if t1 <= 0.0 or t0 >= 1.0:
		return []
	return [maxf(t0, 0.0), minf(t1, 1.0)]


static func _lift(p: Vector2, h: float) -> Vector2:
	return Vector2(p.x, p.y - h * KZ)


## The brightness of a vertical face with screen normal n under the kit's light (the colours above are the lit
## material, so a south face is about 0.95).
static func _lit(n: Vector2) -> float:
	var w := Vector3(n.x, -n.y, 0.0)
	var lum := 3.4 * maxf(0.0, w.dot(KEY_TO.normalized())) + 1.3 * maxf(0.0, w.dot(FILL_TO.normalized()))
	return clampf(0.28 + 0.85 * lum, 0.45, 1.12)


static func _mul(c: Color, f: float) -> Color:
	return Color(minf(c.r * f, 1.0), minf(c.g * f, 1.0), minf(c.b * f, 1.0), c.a)


static func _hash(a: int, b: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xffff) / 65535.0


## The ring's stretches as triangle soups, sorted by the y of the stretch's foot: [[key_y, idx, pts, cols], ...].
static func cmds(ring: Dictionary, detail: bool) -> Array:
	var kind: String = ring["kind"]
	var S: Dictionary = SPEC[kind]
	var t := thickness(ring) * K
	var out: Array = []
	var rseed := int(ring.get("seed", 0))
	for run in ring["runs"]:
		_run(run as PackedVector2Array, kind, S, t, detail, rseed, out)
	out.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	return out


static func _run(run: PackedVector2Array, kind: String, S: Dictionary, t: float, detail: bool, rseed: int, out: Array) -> void:
	var n := run.size()
	if n < 2:
		return
	var ne := n - 1
	# the outward normals of the edges and the mitre of every vertex
	var nrm: Array = []
	for e in ne:
		nrm.append(out_normal(run[e], run[e + 1]))
	var mit: Array = []
	for j in n:
		if j == 0:
			mit.append(nrm[0])
		elif j == n - 1:
			mit.append(nrm[ne - 1])
		else:
			mit.append(_mitre(nrm[j - 1], nrm[j]))
	var to := t * 0.5
	var ti := -t * 0.5
	var hc: float = S["hc"]
	var hm: float = S["hm"]
	var mt: float = float(S["mt"]) * K
	var face: Color = S["face"]
	var top: Color = S["top"]
	var mtop: Color = S["mtop"]
	for e in ne:
		var p0 := run[e]
		var p1 := run[e + 1]
		var nv: Vector2 = nrm[e]
		var dv := (p1 - p0)
		var elen := dv.length()
		if elen < 0.0001:
			continue
		var dn := dv / elen
		var so := Soup.new()
		var key := (p0.y + p1.y) * 0.5
		if kind == "pal":
			_stakes(so, p0, p1, dn, nv, elen, S, detail, rseed + e * 31)
			out.append([key, so.idx, so.pts, so.cols])
			continue
		var o0: Vector2 = p0 + (mit[e] as Vector2) * to
		var o1: Vector2 = p1 + (mit[e + 1] as Vector2) * to
		var i0: Vector2 = p0 + (mit[e] as Vector2) * ti
		var i1: Vector2 = p1 + (mit[e + 1] as Vector2) * ti
		var vis_out := nv.y > 0.03
		var vis_in := nv.y < -0.03
		# the walk (top of the body, at hc), a lit lip along its inner edge
		var tc := _mul(top, 0.97)
		so.quad(_lift(o0, hc), _lift(o1, hc), _lift(i1, hc), _lift(i0, hc), tc)
		var lipw := 0.45 * K
		var l0 := i0 + (mit[e] as Vector2) * lipw
		var l1 := i1 + (mit[e + 1] as Vector2) * lipw
		so.quad(_lift(l0, hc), _lift(l1, hc), _lift(i1, hc), _lift(i0, hc), _mul(top, 1.1))
		# the crenel bed under the merlons: the outer band of the walk in shade, so the gaps read dark between the teeth
		if hm > hc and mt > 0.0:
			var b0 := o0 - (mit[e] as Vector2) * mt
			var b1 := o1 - (mit[e + 1] as Vector2) * mt
			so.quad(_lift(b0, hc), _lift(b1, hc), _lift(o1, hc), _lift(o0, hc), _mul(top, 0.66))
		# the visible face: the outer one in the south of the ring, the inner one in its north
		if vis_out:
			_face(so, o0, o1, nv, S, detail, 1.0)
		elif vis_in:
			_face(so, i0, i1, -nv, S, detail, 0.92)
		# merlons on the outer lip (stone): blocks on the outer edge, seen from the inside in the ring's north
		if hm > hc and mt > 0.0:
			var ml := float(S["ml"]) * K
			var pitch := float(S["pitch"]) * K
			var lat_f := to if vis_out else to - mt
			var fn := nv if vis_out else -nv
			var fc := _mul(face, _lit(fn) * 1.04)
			if not (vis_out or vis_in):
				fc = _mul(face, 0.85)
			if detail:
				var nm := maxi(1, int(round(elen / pitch)))
				for k in nm:
					var uc := (float(k) + 0.5) / float(nm) * elen
					var u0 := maxf(0.0, uc - ml * 0.5)
					var u1 := minf(elen, uc + ml * 0.5)
					_merlon(so, p0, dn, nv, u0, u1, to, mt, lat_f, hc, hm, fc, mtop, vis_out or vis_in, S["ink"])
			else:
				_merlon(so, p0, dn, nv, 0.0, elen, to, mt, lat_f, hc, hm, _mul(fc, 0.96), _mul(mtop, 0.96), vis_out or vis_in, S["ink"])
		# the ends of a run: the cut section where it is visible
		if e == 0:
			_end_cap(so, o0, i0, -dn, hc, face)
		if e == ne - 1:
			_end_cap(so, o1, i1, dn, hc, face)
		out.append([key, so.idx, so.pts, so.cols])


## A visible face from the ground edge a-b (outward normal fn) up the body, the cap band and its lit lip.
static func _face(so: Soup, a: Vector2, b: Vector2, fn: Vector2, S: Dictionary, detail: bool, dim: float) -> void:
	var hb: float = S["hb"]
	var hc: float = S["hc"]
	var lt := _lit(fn) * dim
	var fcol := _mul(S["face"], lt)
	var ccol := _mul(S["cap"], lt)
	var foot := _mul(fcol, 0.62)
	var hf := minf(1.5, hb * 0.25)
	# the foot: a darker band that fades into the body, a thin ink line on the ground like the pieces' edge
	so.quad4(a, b, _lift(b, hf), _lift(a, hf), foot, foot, fcol, fcol)
	var ink: Color = S["ink"]
	so.quad(a, b, _lift(b, 0.42), _lift(a, 0.42), ink)
	so.quad(_lift(a, hf), _lift(b, hf), _lift(b, hb), _lift(a, hb), fcol)
	if detail:
		var course: float = S["course"]
		if course > 0.0:
			var line := _mul(fcol, 0.74)
			var h := course
			while h < hb - 0.5:
				so.quad(_lift(a, h - 0.16), _lift(b, h - 0.16), _lift(b, h + 0.16), _lift(a, h + 0.16), line)
				h += course
	# the cap band (inked where it meets the body), a lit lip along its top
	so.quad(_lift(a, hb), _lift(b, hb), _lift(b, hc), _lift(a, hc), ccol)
	so.quad(_lift(a, hb - 0.12), _lift(b, hb - 0.12), _lift(b, hb + 0.22), _lift(a, hb + 0.22), ink)
	var lip := _mul(ccol, 1.28)
	so.quad(_lift(a, hc - 0.34), _lift(b, hc - 0.34), _lift(b, hc - 0.1), _lift(a, hc - 0.1), lip)
	so.quad(_lift(a, hc - 0.1), _lift(b, hc - 0.1), _lift(b, hc), _lift(a, hc), _mul(ink, 1.15))


## One merlon from u0 to u1 along the edge (origin p0, direction dn, outward normal nv): its visible face at lateral
## lat_f, its top over the outer band mt deep.
static func _merlon(so: Soup, p0: Vector2, dn: Vector2, nv: Vector2, u0: float, u1: float, to: float, mt: float, lat_f: float, hc: float, hm: float, fc: Color, tc: Color, face_vis: bool, ink: Color) -> void:
	if face_vis:
		var fa := p0 + dn * u0 + nv * lat_f
		var fb := p0 + dn * u1 + nv * lat_f
		so.quad(_lift(fa, hc), _lift(fb, hc), _lift(fb, hm), _lift(fa, hm), fc)
		so.quad(_lift(fa, hc), _lift(fb, hc), _lift(fb, hc + 0.3), _lift(fa, hc + 0.3), _mul(ink, 1.1))   # the merlon's foot edge
		so.quad(_lift(fa, hm - 0.28), _lift(fb, hm - 0.28), _lift(fb, hm), _lift(fa, hm), ink)          # its top edge
	var a := p0 + dn * u0 + nv * (to - mt)
	var b := p0 + dn * u1 + nv * (to - mt)
	var c := p0 + dn * u1 + nv * to
	var d := p0 + dn * u0 + nv * to
	so.quad(_lift(a, hm), _lift(b, hm), _lift(c, hm), _lift(d, hm), tc)


## The cut section at the end of a run (outward normal en along the run's axis) when it faces the camera.
static func _end_cap(so: Soup, o: Vector2, i: Vector2, en: Vector2, hc: float, face: Color) -> void:
	if en.y <= 0.15:
		return
	var col := _mul(face, _lit(en) * 0.88)
	so.quad(o, i, _lift(i, hc), _lift(o, hc), col)


## A palisade stretch: stakes along the line, each a pale and a shaded half and a pointed tip, the nearest drawn last;
## on the ring's north side the rails lashing them show from the inside.
static func _stakes(so: Soup, p0: Vector2, p1: Vector2, dn: Vector2, nv: Vector2, elen: float, S: Dictionary, detail: bool, rseed: int) -> void:
	var w := float(S["ml"]) * K
	var n := maxi(1, int(ceil(elen / w)))
	var hs: float = S["hb"]
	var ht: float = float(S["hm"]) - hs
	var base: Color = S["face"]
	var order: Array = range(n)
	if dn.y < 0.0:
		order.reverse()
	for k in order:
		var u := (float(k) + 0.5) / float(n) * elen
		var b: Vector2 = p0 + dn * u
		var v := 0.86 + 0.28 * _hash(rseed, int(k))
		var hw := w * 0.5
		var hh := hs * (0.94 + 0.12 * _hash(rseed + 7, int(k)))
		var c := _mul(base, v)
		if detail:
			var tipc := _mul(S["mtop"], v)
			so.quad4(b + Vector2(-hw, 0.0), b + Vector2(0.0, 0.0), _lift(b, hh), _lift(b, hh) + Vector2(-hw, 0.0), _mul(c, 0.7), _mul(c, 0.8), _mul(c, 1.12), _mul(c, 1.14))
			so.quad4(b, b + Vector2(hw, 0.0), _lift(b, hh) + Vector2(hw, 0.0), _lift(b, hh), _mul(c, 0.62), _mul(c, 0.68), _mul(c, 0.82), _mul(c, 0.84))
			so.tri(_lift(b, hh) + Vector2(-hw, 0.0), _lift(b, hh) + Vector2(hw, 0.0), _lift(b, hh + ht), _mul(tipc, 1.0))
		else:
			so.quad(b + Vector2(-hw, 0.0), b + Vector2(hw, 0.0), _lift(b, hh) + Vector2(hw, 0.0), _lift(b, hh) + Vector2(-hw, 0.0), _mul(c, 0.9))
			so.tri(_lift(b, hh) + Vector2(-hw, 0.0), _lift(b, hh) + Vector2(hw, 0.0), _lift(b, hh + ht), _mul(S["mtop"], v))
	if detail and nv.y < -0.03:
		var rc: Color = S["cap"]
		for rh in [3.7, 6.1]:
			var a := p0 - nv * 0.55 * K
			var b2 := p1 - nv * 0.55 * K
			so.quad(_lift(a, rh - 0.3), _lift(b2, rh - 0.3), _lift(b2, rh + 0.3), _lift(a, rh + 0.3), rc)


## The stretches' cast shadows on the ground: the footprint of each stretch and the footprint carried along `dir`
## by the height's shadow length (the same rule as the pieces'), as convex hulls merged per run (one outline, so
## translucent paint does not double up where two stretches meet).
static func shadow_polys(ring: Dictionary, dir: Vector2) -> Array:
	var kind: String = ring["kind"]
	var S: Dictionary = SPEC[kind]
	var half := thickness(ring) * K * 0.5
	var slen := minf(float(S["hm"]), 36.0) * K * 0.34
	var out: Array = []
	for run in ring["runs"]:
		var r: PackedVector2Array = run
		var hulls: Array = []
		for e in r.size() - 1:
			var nv := out_normal(r[e], r[e + 1])
			if nv == Vector2.ZERO:
				continue
			var pts := PackedVector2Array()
			for q in [r[e], r[e + 1]]:
				for sgn in [-1.0, 1.0]:
					var g: Vector2 = (q as Vector2) + nv * half * sgn
					pts.append(g)
					pts.append(g + dir * slen)
			hulls.append(Geometry2D.convex_hull(pts))
		out.append_array(_union(hulls))
	return out


## The footprint of each run grown by `grow` px (the contact band round the foot), merged per run.
static func foot_polys(ring: Dictionary, grow: float) -> Array:
	var half := thickness(ring) * K * 0.5 + grow
	var out: Array = []
	for run in ring["runs"]:
		var r: PackedVector2Array = run
		var quads: Array = []
		for e in r.size() - 1:
			var nv := out_normal(r[e], r[e + 1])
			if nv == Vector2.ZERO:
				continue
			var dn := (r[e + 1] - r[e]).normalized() * grow
			quads.append(PackedVector2Array([r[e] - dn + nv * half, r[e + 1] + dn + nv * half, r[e + 1] + dn - nv * half, r[e] - dn - nv * half]))
		out.append_array(_union(quads))
	return out


## The union of convex polygons as outer outlines (holes are filled: they are slivers between neighbours).
static func _union(polys: Array) -> Array:
	var acc: Array = []
	for p in polys:
		var cur: PackedVector2Array = p
		if cur.size() < 3:
			continue
		var rest: Array = []
		for q in acc:
			var m: Array = Geometry2D.merge_polygons(cur, q as PackedVector2Array)
			var outer: Array = []
			for mp in m:
				if not Geometry2D.is_polygon_clockwise(mp as PackedVector2Array):
					outer.append(mp)
			if outer.size() == 1:
				cur = outer[0]
			else:
				rest.append(q)
		rest.append(cur)
		acc = rest
	return acc
