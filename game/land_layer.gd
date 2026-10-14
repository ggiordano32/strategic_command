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
const BattleKit := preload("res://game/battlekit.gd")

const LIGHT := Vector2(-0.62, -0.78)   # toward the light (upper left)

var cliffs: Array = []
var rocks: Array = []
var k := 10.0
var rock_col := Color(0.5, 0.48, 0.42)
var low := false
var kit: Node2D                 # rocks and cliffs from the battle kit (null: the drawn ones)


func setup(sim, px_per_m: float, p_low: bool) -> void:
	k = px_per_m
	low = p_low
	var ld: Dictionary = sim.map_info.get("land", {})
	cliffs = ld.get("cliffs", [])
	rocks = ld.get("rocks", [])
	if "--land-info" in OS.get_cmdline_user_args():
		for c in cliffs:
			print("CLIFF x=%d y=%d n=%d" % [int(c["p"][0]) / 100, int(c["p"][1]) / 100, c["p"].size() / 2])
	var pal := GroundPalette.get_palette(int(sim.ter_info.get("palette", 0)))
	var base: Color = pal["base"]
	# Rock a little toward the ground's own colour, so it sits in the land.
	rock_col = (pal["rock"] as Color).lerp(base, 0.18)
	if not ("--no-kit" in OS.get_cmdline_user_args()) and not rocks.is_empty():
		kit = BattleKit.new()
		add_child(kit)
		kit.setup_land(sim, px_per_m)


func set_low(v: bool) -> void:
	if v != low:
		low = v
		if kit != null:
			kit.refresh()
		queue_redraw()


func _draw() -> void:
	# Cliffs are a continuous face along the polyline (also with the kit); rocks are kit pieces.
	if tex == null and not low:
		tex = _rock_tex()
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	for c in cliffs:
		_cliff(c)
	if kit != null:
		return
	for r in rocks:
		_rock(r)


var tex: Texture2D


static func _rock_tex() -> Texture2D:
	var img := (load("res://assets/battlekit/ground/rock.png") as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Chaikin corner cutting of an open polyline (ends kept), twice: curved cliffs get no straight facets.
static func _chaikin(pts: PackedVector2Array) -> PackedVector2Array:
	var cur := pts
	for _it in 2:
		if cur.size() < 3:
			break
		var out := PackedVector2Array()
		out.append(cur[0])
		for i in cur.size() - 1:
			out.append(cur[i].lerp(cur[i + 1], 0.25))
			out.append(cur[i].lerp(cur[i + 1], 0.75))
		out.append(cur[cur.size() - 1])
		cur = out
	return cur


static func _h(a: int, b: int) -> int:
	var x := (a * 73856093) ^ (b * 19349663) ^ 0x5bd1e995
	x = (x ^ (x >> 13)) * 0x5bd1e995
	return (x ^ (x >> 15)) & 0x7FFFFFFF


static func _hf(a: int, b: int) -> float:
	return float(_h(a, b) % 10000) / 10000.0


## A quad by draw_primitive (no triangulation, so degenerate ones are harmless).
func _quad(p: PackedVector2Array, c: PackedColorArray, uv := PackedVector2Array(), t: Texture2D = null) -> void:
	draw_primitive(p, c, uv, t)


## One cliff: points (cm), downhill angle and face height (dm) per point, drawn as one continuous face along
## the polyline (corner-cut so curves stay curved): a lit brow, the face (rock tile mapped along its length,
## strata, ribs, darker toward the foot), talus at the foot and a soft drop shadow down the slope.
func _cliff(c: Dictionary) -> void:
	var pts: PackedInt32Array = c["p"]
	var dn: PackedInt32Array = c["dn"]
	var hh: PackedInt32Array = c["h"]
	var n0 := pts.size() / 2
	if n0 < 2:
		return
	var p0 := PackedVector2Array()
	var nx0 := PackedFloat32Array()   # normal as cos / sin kept apart for the corner cutting
	var ny0 := PackedFloat32Array()
	var fc0 := PackedFloat32Array()
	for q in n0:
		p0.append(Vector2(pts[q * 2], pts[q * 2 + 1]) / 100.0)
		var a := float(dn[q]) / 1024.0 * TAU
		nx0.append(cos(a))
		ny0.append(sin(a))
		fc0.append(float(hh[q]) / 10.0)
	# Smooth normals and face heights along the line, then cut the corners of all of them alike.
	var nrm0 := PackedVector2Array()
	for q in n0:
		var v := Vector2(nx0[q], ny0[q]) * 2.0 + Vector2(nx0[maxi(q - 1, 0)], ny0[maxi(q - 1, 0)]) \
			+ Vector2(nx0[mini(q + 1, n0 - 1)], ny0[mini(q + 1, n0 - 1)])
		nrm0.append(v.normalized())
	var pp := _chaikin(p0)
	var nrm := _chaikin(nrm0)
	var fcv := _chaikin(PackedVector2Array(Array(fc0).map(func(f): return Vector2(f, 0.0))))
	var n := pp.size()
	if nrm.size() != n or fcv.size() != n:
		return
	var sea := int(c.get("sea", 0)) != 0
	var seed_i := int(pts[0]) ^ int(pts[1])
	var lt := LIGHT.normalized()
	# Arc length (m) per point, for the texture and the end taper.
	var s_m := PackedFloat32Array()
	s_m.append(0.0)
	for q in range(1, n):
		s_m.append(s_m[q - 1] + pp[q].distance_to(pp[q - 1]))
	var total := s_m[n - 1]
	var brow := PackedVector2Array()
	var top := PackedVector2Array()
	var foot := PackedVector2Array()
	var talus := PackedVector2Array()
	var shad := PackedVector2Array()
	var nr := PackedVector2Array()
	for q in n:
		var nn := nrm[q].normalized()
		nr.append(nn)
		var face: float = fcv[q].x
		var tp := clampf(0.3 + minf(s_m[q], total - s_m[q]) / 5.0, 0.3, 1.0)
		var w := (1.5 + face * 0.62) * tp
		var wob := (_hf(seed_i, int(s_m[q] * 0.8)) - 0.5) * 0.5
		brow.append((pp[q] - nn * (0.55 + wob * 0.3)) * k)
		top.append((pp[q] - nn * 0.1) * k)
		foot.append((pp[q] + nn * (w + wob)) * k)
		talus.append((pp[q] + nn * (w + wob + 1.3 * tp + face * 0.18)) * k)
		shad.append((pp[q] + nn * (w + face * 1.2 * tp + 0.8) + Vector2(0.6, 0.8) * face * 0.35) * k)
	var tinted := Color(rock_col.r / 0.5, rock_col.g / 0.48, rock_col.b / 0.42) * 0.95
	# Drop shadow and talus, as gradients.
	for q in n - 1:
		var a0 := 0.40 if not sea else 0.2
		_quad(PackedVector2Array([foot[q], foot[q + 1], shad[q + 1], shad[q]]),
			PackedColorArray([Color(0, 0, 0, a0), Color(0, 0, 0, a0), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
		var tc := rock_col.darkened(0.12)
		tc.a = 0.78
		var tc0 := Color(tc.r, tc.g, tc.b, 0.0)
		_quad(PackedVector2Array([foot[q], foot[q + 1], talus[q + 1], talus[q]]),
			PackedColorArray([tc, tc, tc0, tc0]))
	# The face.
	for q in n - 1:
		var l0 := nr[q].dot(lt)
		var l1 := nr[q + 1].dot(lt)
		var sh0 := clampf(0.8 + l0 * 0.34, 0.5, 1.08)
		var sh1 := clampf(0.8 + l1 * 0.34, 0.5, 1.08)
		var u0 := s_m[q] / 12.0
		var u1 := s_m[q + 1] / 12.0
		var vf := maxf(((foot[q] - top[q]).length() / k), 0.5) / 12.0
		var cb0 := Color(tinted.r * sh0, tinted.g * sh0, tinted.b * sh0)
		var cb1 := Color(tinted.r * sh1, tinted.g * sh1, tinted.b * sh1)
		var cf0 := Color(cb0.r * 0.5, cb0.g * 0.46, cb0.b * 0.44)
		var cf1 := Color(cb1.r * 0.5, cb1.g * 0.46, cb1.b * 0.44)
		if tex != null:
			_quad(PackedVector2Array([top[q], top[q + 1], foot[q + 1], foot[q]]),
				PackedColorArray([cb0.lightened(0.08), cb1.lightened(0.08), cf1, cf0]),
				PackedVector2Array([Vector2(u0, 0.0), Vector2(u1, 0.0), Vector2(u1, vf), Vector2(u0, vf)]), tex)
		else:
			_quad(PackedVector2Array([top[q], top[q + 1], foot[q + 1], foot[q]]),
				PackedColorArray([rock_col * sh0, rock_col * sh1, rock_col * sh1 * 0.62, rock_col * sh0 * 0.62]))
	if not low:
		# Strata: faint dark and light courses along the face at fixed fractions, and ribs down it.
		for f in [0.34, 0.66]:
			var line := PackedVector2Array()
			for q in n:
				line.append(top[q].lerp(foot[q], f))
			draw_polyline(line, Color(0, 0, 0, 0.2), maxf(0.16 * k, 1.0))
			var line2 := PackedVector2Array()
			for q in n:
				line2.append(top[q].lerp(foot[q], f + 0.045))
			draw_polyline(line2, Color(1, 1, 1, 0.08), maxf(0.12 * k, 1.0))
		var q2 := 0
		var t := 0.6
		while t < total and q2 < n - 1:
			while q2 < n - 2 and s_m[q2 + 1] < t:
				q2 += 1
			var f := (t - s_m[q2]) / maxf(s_m[q2 + 1] - s_m[q2], 0.01)
			var a := top[q2].lerp(top[q2 + 1], f)
			var b := foot[q2].lerp(foot[q2 + 1], f)
			var hv := _hf(seed_i + 31, int(t * 10.0))
			draw_line(a.lerp(b, 0.1), a.lerp(b, 0.25 + hv * 0.4), Color(0, 0, 0, 0.08 + hv * 0.14), maxf(0.15 * k, 1.0))
			t += 0.7 + _hf(seed_i + 37, int(t * 10.0)) * 1.8
		# Fallen stones in the talus.
		for q in range(0, n, 2):
			if int(_h(seed_i + 17, q)) % 2 != 0:
				continue
			var ctr := foot[q].lerp(talus[q], 0.35 + _hf(seed_i + 19, q) * 0.5) \
				+ Vector2(-nr[q].y, nr[q].x) * (_hf(seed_i + 23, q) - 0.5) * 1.2 * k
			var rr := (0.16 + _hf(seed_i + 29, q) * 0.28) * k
			draw_circle(ctr + Vector2(0.3, 0.4) * rr, rr, Color(0, 0, 0, 0.2))
			draw_circle(ctr, rr, rock_col.darkened(0.1))
		# A darker lip just behind the brow.
		var lip := PackedVector2Array()
		for q in n:
			lip.append(brow[q] - nr[q] * 0.45 * k)
		draw_polyline(lip, Color(0, 0, 0, 0.16), maxf(0.35 * k, 1.0))
	# The lit brow: a pale grass-edged crest line, brighter where the face turns to the light.
	for q in n - 1:
		var lb := clampf(0.5 + nr[q].dot(lt) * 0.5, 0.0, 1.0)
		draw_line(brow[q], brow[q + 1], rock_col.lightened(0.28 + 0.2 * lb), maxf(0.42 * k, 2.0))


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
