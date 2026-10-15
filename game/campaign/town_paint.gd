extends Node
## The ground of the overworld towns, painted once into a texture the land shader mixes in (table_land.gdshader,
## uniform `towns`): feathered clearing, packed earth, streets and plaza, ploughed fields and orchards, tracks
## to the roads, quays, and soft contact shadows of the pieces. No patch outlines: every edge is feathered and
## the texture is shaded by the land's own light afterwards. Drawn on a transparent SubViewport (world scale
## `px_per_texel` world px a texel) when the map loads and again only when a town changes (growth, a conquest);
## never on zoom. View only.

const CData := preload("res://campaign/cdata.gd")
const TownPlan := preload("res://game/campaign/town_plan.gd")
const GroundPalette := preload("res://game/ground_palette.gd")
const Quality := preload("res://game/quality.gd")

const DIRT := Color(0.74, 0.62, 0.40)
const COBBLE := Color(0.83, 0.77, 0.63)
const PLAZA := Color(0.88, 0.83, 0.70)
const STONE := Color(0.80, 0.75, 0.62)
const SHADOW := Color(0.14, 0.09, 0.04)
const CROPS := [Color(0.86, 0.75, 0.38), Color(0.62, 0.76, 0.33), Color(0.69, 0.52, 0.31), Color(0.80, 0.70, 0.36)]

var world := Vector2(3760.0, 2350.0)
var px_per_texel := 2.0
var _vp: SubViewport = null
var _drawer: Node2D = null
var _entries: Array = []     # [plan, site, region]
var _roads: Array = []
var _trees: Array = []
var _specks: Array = []
var _ring: Dictionary = {}
var low := false
var bake_count := 0
var last_ms := 0.0


func setup(world_size: Vector2) -> void:
	world = world_size
	low = Quality.is_low()
	px_per_texel = 3.0 if low else 2.0
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(ceil(world.x / px_per_texel)), int(ceil(world.y / px_per_texel)))
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(_vp)
	_drawer = Node2D.new()
	_drawer.scale = Vector2.ONE / px_per_texel
	_drawer.draw.connect(_paint)
	_vp.add_child(_drawer)


func texture() -> Texture2D:
	return _vp.get_texture() if _vp != null else null


## The landscape's models (trees, rocks; landtrees.gd): their cast shadows are painted with the towns'.
func set_landscape(trees: Array, specks: Array, ring: Dictionary) -> void:
	_trees = trees
	_specks = specks
	_ring = ring


## Paint these towns ([[plan, site, region], ...]) with the roads (world px polylines) the tracks join.
func bake(entries: Array, roads: Array) -> void:
	if _vp == null:
		return
	_entries = entries
	_roads = roads
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_drawer.queue_redraw()
	bake_count += 1


# ------------------------------------------------------------------ drawing

func _poly(pts: PackedVector2Array, col: Color) -> void:
	if pts.size() >= 3 and not Geometry2D.triangulate_polygon(pts).is_empty():
		_drawer.draw_colored_polygon(pts, col)


func _scaled(pts: PackedVector2Array, c: Vector2, k: float) -> PackedVector2Array:
	var o := PackedVector2Array()
	for p in pts:
		o.append(c + (p - c) * k)
	return o


## A feathered blob: rings from a wide faint one to the core, each a scaled copy of the outline.
func _soft(pts: PackedVector2Array, c: Vector2, col: Color, rings: int, spread: float, inner: float = 0.0) -> void:
	for i in rings:
		var f := float(i) / float(maxi(rings - 1, 1))
		var k := lerpf(1.0 + spread, 1.0 - inner, f)
		var cc := col
		cc.a = col.a / float(rings) * (1.6 if i > 0 else 1.0)
		_poly(_scaled(pts, c, k), cc)


func _outline(s: Dictionary, sc: float) -> PackedVector2Array:
	var c: Vector2 = s["c"]
	var rad: PackedFloat32Array = s["rad"]
	var pts := PackedVector2Array()
	for i in TownPlan.NA:
		var a := TAU * float(i) / float(TownPlan.NA)
		var u := Vector2(cos(a), sin(a))
		pts.append(c + u * rad[i] * sc * TownPlan._lvl_dir(s, u, sc))
	return pts


func _lawn(r: int) -> Color:
	var pi := int(CData.REGIONS[r]["ground"])
	var base: Color = GroundPalette.get_palette(pi)["base"]
	return base.lightened(0.18).lerp(Color(0.55, 0.72, 0.31), 0.62)


func _line(pts: PackedVector2Array, w: float, col: Color, edge: float = 0.35) -> void:
	if pts.size() < 2:
		return
	var e := col.darkened(0.28)
	e.a = col.a * edge
	_drawer.draw_polyline(pts, e, w * 1.7, true)
	_drawer.draw_polyline(pts, col, w, true)


func _rect(c: Vector2, yaw: int, hw: float, hd: float, wall: bool) -> PackedVector2Array:
	var a := float(yaw) * PI * 0.25
	var ex := Vector2(cos(a), -sin(a))
	var ey := Vector2(-sin(a), -cos(a))
	var h := hw if not wall else 3.0 * TownPlan.K
	return PackedVector2Array([c - ex * h - ey * hd, c + ex * h - ey * hd, c + ex * h + ey * hd, c - ex * h + ey * hd])


func _paint() -> void:
	var t0 := Time.get_ticks_usec()
	var rings := 2 if low else 4
	var shadows: Array = []
	for e in _entries:
		var plan: Dictionary = e[0]
		var s: Dictionary = e[1]
		var r: int = e[2]
		var style: String = plan["style"]
		var c: Vector2 = s["c"]
		var sc: float = plan["sc"]
		var lawn := _lawn(r)
		# 1 the cleared ground: lawn, wide and soft (the ring the forest keeps off)
		var clear_ring := _outline(s, 1.14)
		var lc := lawn
		lc.a = 0.62
		_soft(clear_ring, c, lc, rings, 0.16, 0.0)
		# unused field sites: fallow meadow
		var used: Array = plan["fields"]
		for fd in s["fields"]:
			var f: Dictionary = fd
			var mc := lawn.lightened(0.05)
			mc.a = 0.55
			_soft(f["quad"], f["ctr"], mc, 2, 0.12, 0.0)
		# 2 packed earth under the town (a village is mostly earth)
		var earth := _outline(s, sc * 0.9)
		var ec := DIRT if style != "maya" else STONE
		ec.a = 0.9 if style != "town" and style != "roman" else 0.82
		_soft(earth, c, ec, rings, 0.14, 0.12)
		# 3 fields and orchards
		for fd in used:
			var f2: Dictionary = fd
			var quad: PackedVector2Array = f2["quad"]
			var fctr: Vector2 = f2["ctr"]
			var row: Vector2 = f2["row"]
			var sh := SHADOW
			sh.a = 0.12
			var qs := PackedVector2Array()
			for q in quad:
				qs.append(q + Vector2(1.6, 1.8))
			_poly(qs, sh)
			if bool(f2["orchard"]):
				var oc := lawn.lightened(0.06)
				oc.a = 0.95
				_poly(quad, oc)
			else:
				var col: Color = CROPS[int(absf(fctr.x * 0.37 + fctr.y * 0.11)) & 3]
				col.a = 0.96
				_poly(quad, col)
				if not low:
					var fur := col.darkened(0.2)
					fur.a = 0.5
					var nrm := Vector2(-row.y, row.x)
					var hl: float = f2["hl"]
					var hw: float = f2["hw"]
					var nl := int(hw * 2.0 / 3.6)
					for k in nl:
						var off := (float(k) + 0.5) / float(nl) * 2.0 - 1.0
						_drawer.draw_line(fctr + nrm * off * hw * 0.92 - row * hl * 0.94, fctr + nrm * off * hw * 0.92 + row * hl * 0.94, fur, 1.7)
			var hedge := Color(0.27, 0.40, 0.18, 0.5)
			var closed := quad.duplicate()
			closed.append(quad[0])
			_drawer.draw_polyline(closed, hedge, 1.5, true)
		# 4 tracks to the roads and the fields
		var track := Color(0.70, 0.58, 0.38, 0.85)
		for trk in _tracks(s):
			_line(trk, 2.6, track, 0.3)
		for fd in used:
			var f3: Dictionary = fd
			var fc: Vector2 = f3["ctr"]
			var dd := (fc - c)
			_line(PackedVector2Array([c + dd.normalized() * (TownPlan.rad_at(s["rad"], atan2(dd.y, dd.x)) * sc * 0.8), c + dd * 0.82, fc]), 2.0, track, 0.3)
		# 5 streets and the plaza
		var cob := COBBLE if style != "native" else DIRT.lightened(0.1)
		cob.a = 0.95
		for st in plan["streets"]:
			_line(st, 4.4 if style != "native" else 3.4, cob, 0.4)
		var pr := 6.5 * TownPlan.K if style != "maya" else 20.0 * TownPlan.K
		var plz := PLAZA if style != "maya" else STONE
		plz.a = 0.96
		if style == "native":
			plz = DIRT.darkened(0.06)
		var ring := PackedVector2Array()
		for j in 18:
			var a := TAU * float(j) / 18.0
			ring.append(c + Vector2(cos(a), sin(a)) * pr * (1.0 + 0.06 * sin(a * 3.0)))
		_soft(ring, c, plz, 3, 0.10, 0.0)
		# 6 the harbour: a stone quay strip and a sand apron
		var ql: PackedVector2Array = plan["quay"]
		if ql.size() >= 2:
			var apron := STONE
			apron.a = 0.9
			_line(ql, 8.5, apron, 0.35)
		# 7 contact shadows of the pieces (south-east, the light is north-west)
		for sd in plan["shadows"]:
			shadows.append(sd)
	var sh2 := SHADOW
	sh2.a = 0.30
	var ao := SHADOW
	ao.a = 0.2
	for sd in shadows:
		var nm: String = sd[1]
		var pd: Array = TownPlan.pd_of(nm)
		var pos: Vector2 = sd[0]
		var yaw: int = sd[2]
		var wall: bool = float(pd[0]) == 0.0 and float(pd[1]) >= 2.0 and (nm.ends_with("_wall") or nm.ends_with("_gate"))
		var round_p: bool = nm.begins_with("tree") or nm.begins_with("palm") or nm == "orange" or nm.ends_with("tower") or nm.ends_with("post") or nm == "lighthouse" or nm == "bast_point"
		var hw := float(pd[1]) * TownPlan.K
		var hd := float(pd[2]) * TownPlan.K
		var slen := minf(float(pd[3]), 36.0) * TownPlan.K * 0.34
		if round_p:
			var pts := PackedVector2Array()
			var tip := pos + TownPlan.SHADOW_DIR * slen
			for j in 12:
				var a := TAU * float(j) / 12.0
				pts.append(pos + Vector2(cos(a), sin(a)) * hd * 0.8)
				pts.append(tip + Vector2(cos(a), sin(a)) * hd * 0.55)
			var hull := Geometry2D.convex_hull(pts)
			_poly(hull, sh2)
			continue
		var base := _rect(pos, yaw, hw, hd, wall)
		var all := PackedVector2Array()
		for q in base:
			all.append(q)
			all.append(q + TownPlan.SHADOW_DIR * slen)
		var hl2 := Geometry2D.convex_hull(all)
		_poly(hl2, sh2)
		# the contact darkening right under it
		_poly(_scaled(base, pos, 1.15), ao)
	# the landscape's trees and rocks: the same north-west cast shadow (soft ellipse towards the south-east)
	var ts := SHADOW
	ts.a = 0.30
	for t in _trees:
		_tree_shadow(t, ts)
	for lst in _ring.values():
		for t in lst:
			_tree_shadow(t, ts)
	var rs := SHADOW
	rs.a = 0.26
	for sp in _specks:
		var rr := float(sp[3]) * (1.0 if bool(sp[2]) else 0.8)
		var c0 := Vector2(float(sp[0]), float(sp[1])) + TownPlan.SHADOW_DIR * rr * 0.8
		_ellipse(c0, rr * 1.2, rr * 0.8, rs)
	last_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _tree_shadow(t: Array, col: Color) -> void:
	var rad := float(t[4])
	var kind := int(t[2])
	var slen := rad * (1.5 if kind == 1 or kind == 3 else 1.1)
	var c0 := Vector2(float(t[0]), float(t[1])) + TownPlan.SHADOW_DIR * slen * 0.8
	_ellipse(c0, rad * (0.8 if kind != 3 else 0.55), rad * 0.7, col)


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for j in 8:
		var a := TAU * float(j) / 8.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	_drawer.draw_colored_polygon(pts, col)


## Tracks from the town to the nearest road points (two, apart), computed once per site.
func _tracks(s: Dictionary) -> Array:
	if s.has("tracks"):
		return s["tracks"]
	var out: Array = []
	var c: Vector2 = s["c"]
	var rm := TownPlan._max_rad(s["rad"])
	var best: Array = []
	for ln in _roads:
		var pl: PackedVector2Array = ln
		var bd := 1e9
		var bp := Vector2.ZERO
		for p in pl:
			var dd := p.distance_to(c)
			if dd > rm * 0.6 and dd < bd:
				bd = dd
				bp = p
		if bd < rm * 3.2:
			best.append([bd, bp])
	best.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var picked: Array = []
	for b in best:
		var dv: Vector2 = ((b[1] as Vector2) - c).normalized()
		var fine := true
		for q in picked:
			if dv.dot(q as Vector2) > 0.6:
				fine = false
		if fine:
			picked.append(dv)
			var mid := c + ((b[1] as Vector2) - c) * 0.5 + Vector2(-dv.y, dv.x) * (float(int(c.x) % 7) - 3.0)
			out.append(PackedVector2Array([c + dv * rm * 0.3, mid, b[1]]))
		if picked.size() >= 2:
			break
	s["tracks"] = out
	return out
