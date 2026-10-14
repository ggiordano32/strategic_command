extends Node2D
## Cliffs and rock outcrops on the battle map (view only; slice 2d): drawn
## once from the sim's landform data (sim.map_info["land"], built by
## sim/landforms.gd; the cells themselves are in the sim's obstacle grid)
## over the ground and under the cover, trees and soldiers (a child of the
## terrain layer, after its decals). Light from the upper left as the hill
## shade: a cliff is a lit top edge, its face (darker the more it turns
## from the light, strata on Graphics High), a drop shadow down the slope
## and scree at its foot; an outcrop is a few irregular boulders with a
## lit facet, a crack and a shadow. Graphics Low draws the faces, boulders
## and shadows only. Shapes vary by a hash of the map, so every peer sees
## the same rocks.

const GroundPalette := preload("res://game/ground_palette.gd")

const LIGHT := Vector2(-0.62, -0.78)   # toward the light (upper left)

var cliffs: Array = []
var rocks: Array = []
var k := 10.0
var rock_col := Color(0.5, 0.48, 0.42)
var low := false


func setup(sim, px_per_m: float, p_low: bool) -> void:
	k = px_per_m
	low = p_low
	var ld: Dictionary = sim.map_info.get("land", {})
	cliffs = ld.get("cliffs", [])
	rocks = ld.get("rocks", [])
	var pal := GroundPalette.get_palette(int(sim.ter_info.get("palette", 0)))
	var base: Color = pal["base"]
	# Rock a little toward the ground's own colour, so it sits in the land.
	rock_col = (pal["rock"] as Color).lerp(base, 0.18)


func set_low(v: bool) -> void:
	if v != low:
		low = v
		queue_redraw()


func _draw() -> void:
	for c in cliffs:
		_cliff(c)
	for r in rocks:
		_rock(r)


static func _h(a: int, b: int) -> int:
	var x := (a * 73856093) ^ (b * 19349663) ^ 0x5bd1e995
	x = (x ^ (x >> 13)) * 0x5bd1e995
	return (x ^ (x >> 15)) & 0x7FFFFFFF


static func _hf(a: int, b: int) -> float:
	return float(_h(a, b) % 10000) / 10000.0


## One cliff: points (cm), downhill angle and face height (dm) per point.
func _cliff(c: Dictionary) -> void:
	var pts: PackedInt32Array = c["p"]
	var dn: PackedInt32Array = c["dn"]
	var hh: PackedInt32Array = c["h"]
	var n := pts.size() / 2
	if n < 2:
		return
	var p := PackedVector2Array()
	var nrm := PackedVector2Array()
	var face := PackedFloat32Array()
	for q in n:
		p.append(Vector2(pts[q * 2], pts[q * 2 + 1]) / 100.0)
		var a := float(dn[q]) / 1024.0 * TAU
		nrm.append(Vector2(cos(a), sin(a)))
		face.append(float(hh[q]) / 10.0)
	# Smooth the normals a little (the sim's are per 4 m node).
	var sm := PackedVector2Array()
	for q in n:
		var v := nrm[q] * 2.0 + nrm[maxi(q - 1, 0)] + nrm[mini(q + 1, n - 1)]
		sm.append(v.normalized())
	nrm = sm
	var sea := int(c.get("sea", 0)) != 0
	var seed_i := int(pts[0]) ^ int(pts[1])
	# Taper at the ends: the face narrows over the last 6 m.
	var taper := PackedFloat32Array()
	for q in n:
		var e := float(mini(q, n - 1 - q)) * 2.0
		taper.append(clampf(0.35 + e / 6.0, 0.35, 1.0))
	var top := PackedVector2Array()
	var foot := PackedVector2Array()
	var shad := PackedVector2Array()
	for q in n:
		var w := (1.6 + face[q] * 0.7) * taper[q]
		var wob := (_hf(seed_i, q) - 0.5) * 0.6
		top.append((p[q] - nrm[q] * (1.5 + wob * 0.5)) * k)
		foot.append((p[q] + nrm[q] * (w + wob)) * k)
		shad.append((p[q] + nrm[q] * (w + face[q] * 1.3 * taper[q]) + Vector2(0.6, 0.8) * face[q] * 0.35) * k)
	# Drop shadow down the slope (soft: dark at the foot, clear at its end).
	for q in n - 1:
		var quad := PackedVector2Array([foot[q], foot[q + 1], shad[q + 1], shad[q]])
		var a0 := 0.42 if not sea else 0.22
		draw_polygon(quad, PackedColorArray([Color(0, 0, 0, a0), Color(0, 0, 0, a0), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
	# The face: lighter at the brow, darker at the foot, shaded by how it
	# turns to the light.
	var cols := PackedColorArray()
	for q in n:
		var lit := nrm[q].dot(LIGHT.normalized())
		var shade := clampf(0.78 + lit * 0.3, 0.5, 1.05)
		cols.append(Color(rock_col.r * shade, rock_col.g * shade, rock_col.b * shade))
	for q in n - 1:
		var quad2 := PackedVector2Array([top[q], top[q + 1], foot[q + 1], foot[q]])
		draw_polygon(quad2, PackedColorArray([cols[q].lightened(0.06), cols[q + 1].lightened(0.06),
			cols[q + 1].darkened(0.32), cols[q].darkened(0.32)]))
	if not low:
		# Hachures: rock ribs and gullies running down the face.
		var len_m := 0.0
		for q in n - 1:
			var seg := p[q + 1] - p[q]
			var sl := seg.length()
			var t := fmod(1.0 - len_m, 1.0)
			while t < sl:
				var f := t / maxf(sl, 0.01)
				var a := top[q].lerp(top[q + 1], f)
				var b := foot[q].lerp(foot[q + 1], f)
				var hv := _hf(seed_i + 31, int((len_m + t) * 10.0))
				var reach := 0.45 + hv * 0.55
				var dark := 0.18 + hv * 0.22
				draw_line(a.lerp(b, 0.12), a.lerp(b, reach), Color(0, 0, 0, dark), maxf(0.16 * k, 1.0))
				if hv > 0.7:
					draw_line(a.lerp(b, 0.08), a.lerp(b, 0.3 + hv * 0.3), Color(1, 1, 1, 0.12), maxf(0.12 * k, 1.0))
				t += 0.8 + _hf(seed_i + 37, int((len_m + t) * 10.0)) * 0.7
			len_m += sl
		# A few fallen stones at the foot.
		for q in n:
			if _h(seed_i + 17, q) % 3 != 0:
				continue
			var off := (_hf(seed_i + 19, q) * 1.4 + 0.4) * nrm[q] * k
			var side := Vector2(-nrm[q].y, nrm[q].x) * (_hf(seed_i + 23, q) - 0.5) * 2.0 * k
			var ctr := foot[q] + off + side
			var rr := (0.2 + _hf(seed_i + 29, q) * 0.35) * k
			draw_circle(ctr + Vector2(0.3, 0.4) * rr, rr, Color(0, 0, 0, 0.2))
			draw_circle(ctr, rr, rock_col.darkened(0.15))
	# The lit brow along the top, a darker lip just behind it.
	if not low:
		var lip := PackedVector2Array()
		for q in n:
			lip.append(top[q] - nrm[q] * 0.4 * k)
		draw_polyline(lip, Color(0, 0, 0, 0.18), maxf(0.3 * k, 1.0))
	draw_polyline(top, rock_col.lightened(0.42), maxf(0.45 * k, 2.0))


## One outcrop: [seed, height dm, x, y, r, x, y, r, ...] (metres).
func _rock(r: Array) -> void:
	var sd := int(r[0])
	var hgt := float(int(r[1])) / 10.0
	var nd := (r.size() - 2) / 3
	var shapes: Array = []
	for d in nd:
		var cx := float(int(r[2 + d * 3]))
		var cy := float(int(r[3 + d * 3]))
		var rad := float(int(r[4 + d * 3]))
		var poly := PackedVector2Array()
		var nv := 9
		var rot := _hf(sd, d * 31) * TAU
		for v in nv:
			var a := rot + TAU * v / nv
			var rr := rad * (0.82 + _hf(sd + d * 7, v) * 0.38)
			poly.append(Vector2(cx + cos(a) * rr, cy + sin(a) * rr * 0.92) * k)
		shapes.append([poly, Vector2(cx, cy) * k, rad * k])
	# Shadows first (down to the lower right), then the boulders.
	for s in shapes:
		var sh := PackedVector2Array()
		var off := Vector2(0.55, 0.75) * minf(hgt * 0.55, 2.2) * k
		for v in (s[0] as PackedVector2Array):
			sh.append(v + off)
		draw_colored_polygon(sh, Color(0, 0, 0, 0.3))
	for i in shapes.size():
		var s: Array = shapes[i]
		var poly: PackedVector2Array = s[0]
		var ctr: Vector2 = s[1]
		var rad: float = s[2]
		var v := 0.86 + _hf(sd + 41, i) * 0.16
		var body := Color(rock_col.r * v, rock_col.g * v, rock_col.b * v)
		draw_colored_polygon(poly, body.darkened(0.16))
		# The lit upper-left facet.
		var lit := PackedVector2Array()
		for p in poly:
			lit.append(ctr + (p - ctr) * 0.72 + LIGHT * rad * 0.18)
		draw_colored_polygon(lit, body.lightened(0.14))
		if not low:
			var top := PackedVector2Array()
			for p in poly:
				top.append(ctr + (p - ctr) * 0.36 + LIGHT * rad * 0.3)
			draw_colored_polygon(top, body.lightened(0.28))
			if _h(sd, i + 5) % 2 == 0:
				var a := _hf(sd, i + 9) * TAU
				var dir := Vector2(cos(a), sin(a))
				draw_line(ctr - dir * rad * 0.5, ctr + dir * rad * 0.35, Color(0, 0, 0, 0.3), maxf(0.12 * k, 1.0))
			draw_polyline(poly + PackedVector2Array([poly[0]]), Color(0, 0, 0, 0.22), maxf(0.1 * k, 1.0))
