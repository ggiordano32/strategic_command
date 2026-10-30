extends Node2D
## The overworld towns as the map-table style draws them (view only): each town is assembled from kit
## pieces (town_plan.gd) placed on the terrain, drawn in world coordinates under the map's own transform
## (a child of the campaign screen's `world`, over the map and under the overlay), so pan and zoom cost
## nothing: a town's canvas item is drawn again only when its plan changes (growth, walls, a conquest) or the
## atlas size flips at a zoom threshold. Pieces and the map trees just outside the cleared ground share one
## y order per town. The ground under them is painted into the land by town_paint.gd.
## Graphics Low: the small atlas and a coarser ground texture.

const FogView := preload("res://game/campaign/fog_view.gd")
const ZProf := preload("res://game/campaign/zprof.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const TownPlan := preload("res://game/campaign/town_plan.gd")
const TownPaint := preload("res://game/campaign/town_paint.gd")
const TownRing := preload("res://game/campaign/town_ring.gd")
const Landscape := preload("res://game/campaign/landscape.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const Atlas := preload("res://game/minis_atlas.gd")
const Quality := preload("res://game/quality.gd")
const Geo := preload("res://game/campaign/map_geo.gd")
const SHADER := preload("res://game/campaign/minis.gdshader")
const MapLook := preload("res://game/campaign/map_look.gd")
const LandTrees := preload("res://game/campaign/landtrees.gd")

const MIN_ZOOM := 0.55
const LOW_SKIP := ["barrels", "cannon", "stela", "flagpole", "well", "rowboat", "canoe", "crane", "skull_rock", "totem"]
const BIG_PX_M := 2.0           # screen px a metre from which the big atlas is used

var overlay: Node2D
var _paint: Node = null
var _kids := {}                 # region -> Node2D
var _plans := {}                # region -> plan
var _sigs := {}                 # region -> signature
var _variant := ""
var _land_gen := -1
var _dirty := {}                # regions whose canvas item must be drawn again (done when on screen)
var _keycache := {}             # "piece|yaw|atlas" -> sprite key
var _acc := 10.0
var _mats := {}
var _shades := {}
var _tsorted := {}              # region -> ring trees sorted by y
var _grid := true
var on := false                 # the pieces are showing (the overlay hides its icons then)
var plan_ms := 0.0              # last plan + paint build (ms)
static var texture_bytes := 0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	z_index = 0
	# (loaded here, not inside a draw callback: a texture first loaded while drawing draws as a white placeholder)
	for nm in (["small"] if Quality.is_low() else ["small", "big"]):
		_shades[nm] = load("res://assets/minis/atlas_%s_shade.png" % nm)
		_mat(nm)


func _mat(name_set: String) -> ShaderMaterial:
	if _mats.has(name_set):
		return _mats[name_set]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("mask", load("res://assets/minis/atlas_%s_mask.png" % name_set))
	MapLook.apply(m)
	_mats[name_set] = m
	return m


func _process(delta: float) -> void:
	var t0 := ZProf.begin()
	_tick(delta)
	ZProf.add("towns_process", t0)


func _tick(delta: float) -> void:
	if overlay == null:
		return
	var st: Dictionary = overlay.state
	var tbl := MapView.table_on() and MapView.terrain_view and not st.is_empty() and CData.region_count() > 0 \
		and (st.get("regions", []) as Array).size() == CData.region_count()   # (a state of another pack, e.g. a screen about to be freed after a pack switch: no plans)
	var z: float = overlay.zoom
	on = tbl and z >= MIN_ZOOM
	if visible != on:
		visible = on
	if not tbl:
		return
	_acc += delta
	var v := "small" if (Quality.is_low() or TownPlan.K * z < BIG_PX_M) else "big"
	if v != _variant:
		_variant = v
		for r in _kids:
			_dirty[r] = true
	_redraw_visible()
	if _acc >= 0.25:
		_acc = 0.0
		refresh(st, bool(overlay.grid))


## Draw again the dirty towns that are on screen (a few a frame): a zoom threshold or a repaint never redraws all 49.
func _redraw_visible() -> void:
	if _dirty.is_empty():
		return
	var mv: Node = MapView.instance
	var rect := Rect2()
	if mv != null and is_instance_valid(mv):
		rect = (mv.get("view_rect") as Rect2).grow(160.0)
	var done := 0
	for r in _dirty.keys():
		var pl: Dictionary = _plans.get(r, {})
		if pl.is_empty():
			_dirty.erase(r)
			if _kids.has(r):
				(_kids[r] as Node2D).queue_redraw()   # (a town that went unknown: clear its drawing)
			continue
		if rect.size.x > 0.0 and not rect.has_point(pl["c"] as Vector2):
			continue
		(_kids[r] as Node2D).queue_redraw()
		_dirty.erase(r)
		done += 1
		if done >= 8:
			break


## Re-plan the towns whose state changed (level, walls, owner culture, shipyard, haven) and repaint the ground.
func refresh(st: Dictionary, grid: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if grid != _grid:
		_grid = grid
		_sigs = {}
		_plans = {}
		_cmds.clear()
		_info.clear()
	var changed := false
	var t0 := Time.get_ticks_usec()
	for r in CData.region_count():
		var tf := FogView.town_facts(st, r)   # (fog: out of sight, the last-seen owner's culture, level and walls; {} never seen)
		var sig := "%d_%s" % [FogView.shown_owner(st, r), "never" if tf.is_empty() else TownPlan.sig(st, r, tf)]
		if _sigs.get(r, "") == sig:
			continue
		_sigs[r] = sig
		var prev: Dictionary = _plans.get(r, {})
		var pl := {} if tf.is_empty() else TownPlan.plan(st, r, grid, tf)
		if pl.is_empty():
			_plans.erase(r)   # (never seen: no model, the overlay draws its bare marker)
			changed = true
		else:
			_plans[r] = pl
		_cmds.erase(r)
		_info.erase(r)
		var kid: Node2D = _kids.get(r)
		if pl.is_empty() and kid == null:
			continue
		if kid == null:
			kid = Node2D.new()
			kid.draw.connect(_draw_town.bind(kid, r))
			add_child(kid)
			_kids[r] = kid
		# the owner changed only: the pieces keep their layout (a redraw); anything else repaints the ground
		if prev.is_empty() or not is_same(prev, pl):
			changed = true
		_dirty[r] = true
	if _paint == null:
		_paint = TownPaint.new()
		add_child(_paint)
		_paint.setup(Geo.SIZE)
		changed = true
	if _land_gen != Landscape.glyph_gen:
		_land_gen = Landscape.glyph_gen
		_tsorted = {}
		_cmds.clear()
		changed = true
		for r in _kids:
			_dirty[r] = true
	if changed:
		var entries: Array = []
		for r in CData.region_count():
			if _plans.has(r):
				entries.append([_plans[r], TownPlan.site(r, _grid), r])
		_paint.set_landscape(Landscape.tree_list if Landscape.models else [], Landscape.speck_list if Landscape.models else [], Landscape.town_trees if Landscape.models else {})
		_paint.bake(entries, MapView.road_lines())
		var mv: Node = MapView.instance
		if mv != null and is_instance_valid(mv):
			mv.set_town_paint(_paint.texture(), Geo.SIZE)
	plan_ms = float(Time.get_ticks_usec() - t0) / 1000.0


## A summary of town r for the overlay (labels, banners, fleets): half width and the heights above / below the
## anchor in world px, the water spot of a harbour (Vector2.ZERO none), the harbour side (-1 / +1, 0 none).
func info(r: int) -> Dictionary:
	if not _plans.has(r):
		return {}
	if _info.has(r):
		return _info[r]
	var pl: Dictionary = _plans[r]
	var w: Vector2 = pl["water"]
	var c: Vector2 = pl["c"]
	_info[r] = {"c": c, "p0": (TownPlan.site(r, _grid))["p0"], "half_w": pl["half_w"], "n": (pl["items"] as Array).size(), "top": pl["top"], "bottom": pl["bottom"], "water": w,
		"side": 0.0 if w == Vector2.ZERO else (-1.0 if w.x < c.x else 1.0)}
	return _info[r]


func planned() -> bool:
	return not _plans.is_empty()


func _trees(r: int) -> Array:
	if not _tsorted.has(r):
		var a: Array = (Landscape.town_trees.get(r, []) as Array).duplicate()
		a.sort_custom(func(p, q): return float(p[1]) < float(q[1]))
		_tsorted[r] = a
	return _tsorted[r]


## One ring tree: its model (the same pick as the landscape's trees) or, on Low, the old dot.
func _ring_tree(kid: Node2D, t: Array, table: Dictionary, shade: Texture2D, wuv: Vector2) -> void:
	if Quality.is_low() or not Landscape.models:
		Landscape.draw_tree(kid, t, shade, wuv)
		return
	var pk := LandTrees.pick_tree(t)
	var key := "p_%s__y0" % str(pk[0])
	if not table.has(key):
		return
	var e: Array = table[key]
	var k := TownPlan.K / float(e[6]) * float(pk[1])
	var dst := Rect2(Vector2(float(t[0]), float(t[1])) - Vector2(float(e[4]), float(e[5])) * k, Vector2(float(e[2]), float(e[3])) * k)
	kid.draw_texture_rect_region(shade, dst, Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3])), pk[2])


## The draw list of town r for atlas aname (every piece's rect resolved once, in the y-sorted order with the ring trees):
## a redraw after a zoom threshold replays it instead of resolving 300 sprite keys again. Entries: [0, dst, src, colour or
## null for the owner's] a sprite, [1, centre, radius] a moored ship's shadow.
var _cmds := {}
var _info := {}   # info(r), built once per plan
static var _DBG: bool = OS.get_cmdline_user_args().has("townsdbg")


func _draw_cmds(kid: Node2D, r: int, aname: String, table: Dictionary, shade: Texture2D, col: Color) -> void:
	var per: Dictionary = _cmds.get(r, {})
	if not per.has(aname):
		per[aname] = _build_cmds(r, aname, table, shade)
		_cmds[r] = per
	for c in per[aname]:
		if int(c[0]) == 0:
			kid.draw_texture_rect_region(shade, c[1], c[2], col if c[3] == null else c[3])
		elif int(c[0]) == 2:
			_soup(kid, c, shade)
		else:
			kid.draw_set_transform((c[1] as Vector2) + Vector2(2.5, 3.0), 0.0, Vector2(1.0, 0.42))
			kid.draw_circle(Vector2.ZERO, float(c[2]), Color(0.04, 0.10, 0.18, 0.28))
			kid.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The ring walls of town r for atlas aname as sorted soups [2, idx, pts, cols, uvs, key_y] (every vertex's uv in the atlas'
## white block, the colour in the vertex): the small atlas and Graphics Low draw them flat.
func _ring_cmds(r: int, aname: String, table: Dictionary, shade: Texture2D) -> Array:
	var per: Dictionary = _cmds.get(r, {})
	var ck := "ring|" + aname
	if per.has(ck):
		return per[ck]
	var out: Array = []
	var pl: Dictionary = _plans[r]
	var wh: Array = table["white"]
	var wuv := Vector2((float(wh[0]) + 4.0) / float(shade.get_width()), (float(wh[1]) + 4.0) / float(shade.get_height()))
	var detail := aname == "big" and not Quality.is_low()
	for ring in pl.get("wrings", []):
		for sp in TownRing.cmds(ring as Dictionary, detail):
			var pts: PackedVector2Array = sp[2]
			var uvs := PackedVector2Array()
			uvs.resize(pts.size())
			uvs.fill(wuv)
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for q in pts:
				lo = lo.min(q)
				hi = hi.max(q)
			out.append([2, sp[1], pts, sp[3], uvs, float(sp[0]), false, Rect2(lo, hi - lo)])
	out.sort_custom(func(a, b): return float(a[5]) < float(b[5]))
	per[ck] = out
	_cmds[r] = per
	return out


## Append a ring soup to a draw list. A stretch joins the last soup of the list when none of the pieces drawn since
## overlaps it (their order would not show): one draw call for a run of stretches instead of one each, the
## draw-call count being the cost of the ring, not its triangles. Entries: [2, indices, points, colours, uvs, key y,
## joined (the arrays are the list's own), bounds of the stretch].
func _push_soup(out: Array, c: Array) -> void:
	var bb: Rect2 = c[7]
	var gb := bb.grow(2.0)
	var j := out.size() - 1
	var steps := 0
	while j >= 0 and steps < 48:
		var e: Array = out[j]
		var kind := int(e[0])
		if kind == 2:
			break
		var er: Rect2
		if kind == 0:
			er = e[1]
		else:
			var rr := float(e[2]) * 1.2
			er = Rect2((e[1] as Vector2) - Vector2(rr, rr), Vector2(rr, rr) * 2.0 + Vector2(3.0, 3.0))
		if er.intersects(gb):
			j = -1
			break
		j -= 1
		steps += 1
	if j >= 0 and int((out[j] as Array)[0]) == 2:
		var p: Array = out[j]
		var pts: PackedVector2Array = p[2]
		var base := pts.size()
		var idx: PackedInt32Array = p[1]
		for i in c[1] as PackedInt32Array:
			idx.append(int(i) + base)
		var cols: PackedColorArray = p[3]
		var uvs: PackedVector2Array = p[4]
		pts.append_array(c[2])
		cols.append_array(c[3])
		uvs.append_array(c[4])
		p[1] = idx
		p[2] = pts
		p[3] = cols
		p[4] = uvs
		return
	# (a copy: the cached list of ring soups keeps the single stretches, the draw list owns the joined arrays)
	out.append([2, (c[1] as PackedInt32Array).duplicate(), (c[2] as PackedVector2Array).duplicate(), (c[3] as PackedColorArray).duplicate(), (c[4] as PackedVector2Array).duplicate(), c[5], true, bb])


func _flush_pend(kid: Node2D, pend: Array, shade: Texture2D) -> void:
	if not pend.is_empty():
		_soup(kid, pend[0], shade)
		pend.clear()


## One ring soup: a single triangle array with the colours in the vertices.
func _soup(kid: Node2D, c: Array, shade: Texture2D) -> void:
	RenderingServer.canvas_item_add_triangle_array(kid.get_canvas_item(), c[1], c[2], c[3], c[4], PackedInt32Array(), PackedFloat32Array(), shade.get_rid())


func _build_cmds(r: int, aname: String, table: Dictionary, shade: Texture2D) -> Array:
	var out: Array = []
	var pl0: Dictionary = _plans[r]
	var items: Array = pl0["items"]
	var stars: Array = pl0.get("hidden", [])
	var trees := _trees(r)
	var rc := _ring_cmds(r, aname, table, shade)
	var ri := 0
	var nr := rc.size()
	var ti := 0
	var nt := trees.size()
	for it in items:
		var ii: Array = it
		var pos: Vector2 = ii[0]
		while ti < nt and float((trees[ti] as Array)[1]) <= pos.y:
			_tree_cmd(out, trees[ti], table)
			ti += 1
		while ri < nr and float((rc[ri] as Array)[5]) <= pos.y:
			_push_soup(out, rc[ri])
			ri += 1
		if stars.has(pos) and (str(ii[1]) == "fort" or str(ii[1]) == "harbour_fort"):
			continue
		var pn := str(ii[1])
		var ck := "%s|%d|%s" % [pn, int(ii[2]), aname]
		var key: String
		if _keycache.has(ck):
			key = _keycache[ck]
		else:
			key = TownPlan.sprite(table, pn, int(ii[2]))
			_keycache[ck] = key
		if key == "":
			continue
		var e: Array = table[key]
		var k := TownPlan.K / float(e[6])
		var dst := Rect2(pos - Vector2(float(e[4]), float(e[5])) * k, Vector2(float(e[2]), float(e[3])) * k)
		if pn.begins_with("ship_"):
			out.append([1, pos, float(e[2]) / float(e[6]) * TownPlan.K * 0.5 * 0.8])
		var own = null   # (null: the town owner's colour at draw time)
		if ii.size() > 3:
			own = CData.faction_color(int(ii[3]))
		out.append([0, dst, Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3])), own])
	while ti < nt:
		_tree_cmd(out, trees[ti], table)
		ti += 1
	while ri < nr:
		_push_soup(out, rc[ri])
		ri += 1
	return out


func _tree_cmd(out: Array, t: Array, table: Dictionary) -> void:
	var pk := LandTrees.pick_tree(t)
	var key := "p_%s__y0" % str(pk[0])
	if not table.has(key):
		return
	var e: Array = table[key]
	var k := TownPlan.K / float(e[6]) * float(pk[1])
	out.append([0, Rect2(Vector2(float(t[0]), float(t[1])) - Vector2(float(e[4]), float(e[5])) * k, Vector2(float(e[2]), float(e[3])) * k),
		Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3])), pk[2]])


func _draw_town(kid: Node2D, r: int) -> void:
	var t0 := ZProf.begin()
	_draw_town_body(kid, r)
	ZProf.add("town_draw", t0)


func _draw_town_body(kid: Node2D, r: int) -> void:
	if not _plans.has(r) or overlay == null:
		return
	var st: Dictionary = overlay.state
	if st.is_empty():
		return
	var pl: Dictionary = _plans[r]
	if not pl.has("items"):
		return
	var items: Array = pl["items"]
	var aname := _variant if _variant != "" else "small"
	var table: Dictionary = Atlas.SETS[aname]
	if not _shades.has(aname):
		aname = "small"
	var shade: Texture2D = _shades[aname]
	table = Atlas.SETS[aname]
	kid.material = _mat(aname)
	var col := CData.faction_color(FogView.shown_owner(st, r))
	if not _DBG and not Quality.is_low() and Landscape.models:
		_draw_cmds(kid, r, aname, table, shade, col)
		return
	var trees := _trees(r)
	var wh: Array = table["white"]
	var wuv := Vector2((float(wh[0]) + 4.0) / float(shade.get_width()), (float(wh[1]) + 4.0) / float(shade.get_height()))
	var ti := 0
	var low := Quality.is_low()
	var nt := trees.size()
	var rc := _ring_cmds(r, aname, table, shade)
	var ri := 0
	var nr := rc.size()
	var stars: Array = pl.get("hidden", [])
	var pend: Array = []   # ring stretches waiting for the next piece to be drawn (they join into one draw call)
	for it in items:
		var ii: Array = it
		var pos: Vector2 = ii[0]
		while ti < nt and float((trees[ti] as Array)[1]) <= pos.y:
			_flush_pend(kid, pend, shade)
			_ring_tree(kid, trees[ti], table, shade, wuv)
			ti += 1
		while ri < nr and float((rc[ri] as Array)[5]) <= pos.y:
			_push_soup(pend, rc[ri])
			ri += 1
		var pn := str(ii[1])
		if stars.has(pos) and (pn == "fort" or pn == "harbour_fort"):
			continue
		if low and (pn.begins_with("tree") or pn.begins_with("palm") or pn == "orange" or LOW_SKIP.has(pn) or ((pn.begins_with("house") or pn.begins_with("adobe") or pn == "hut") and (int(pos.x) + int(pos.y)) % 2 == 0)):
			continue
		var ck := "%s|%d|%s" % [pn, int(ii[2]), aname]
		var key: String
		if _keycache.has(ck):
			key = _keycache[ck]
		else:
			key = TownPlan.sprite(table, pn, int(ii[2]))
			_keycache[ck] = key
		if key == "":
			continue
		var e: Array = table[key]
		var k := TownPlan.K / float(e[6])
		var dst := Rect2(pos - Vector2(float(e[4]), float(e[5])) * k, Vector2(float(e[2]), float(e[3])) * k)
		_flush_pend(kid, pend, shade)
		var icol := col
		if ii.size() > 3:   # a besieger's camp is in its own colour
			icol = CData.faction_color(int(ii[3]))
		if pn.begins_with("ship_"):   # a moored ship: a soft shadow on the water first
			var hl := float(e[2]) / float(e[6]) * TownPlan.K * 0.5
			kid.draw_set_transform(pos + Vector2(2.5, 3.0), 0.0, Vector2(1.0, 0.42))
			kid.draw_circle(Vector2.ZERO, hl * 0.8, Color(0.04, 0.10, 0.18, 0.28))
			kid.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		kid.draw_texture_rect_region(shade, dst, Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3])), icol)
	while ti < nt:
		_flush_pend(kid, pend, shade)
		_ring_tree(kid, trees[ti], table, shade, wuv)
		ti += 1
	while ri < nr:
		_push_soup(pend, rc[ri])
		ri += 1
	_flush_pend(kid, pend, shade)
	if _DBG:
		var sd := TownPlan.site(r, _grid)
		var rad: PackedFloat32Array = sd["rad"]
		var c: Vector2 = sd["c"]
		var pts := PackedVector2Array()
		for i in TownPlan.NA + 1:
			var a := TAU * float(i % TownPlan.NA) / float(TownPlan.NA)
			pts.append(c + Vector2(cos(a), sin(a)) * rad[i % TownPlan.NA])
		kid.draw_polyline(pts, Color(1, 0, 1), 1.0)
		for ln in sd["streets"]:
			kid.draw_polyline(ln, Color(1, 1, 0), 1.0)
		for sl in sd["slots"]:
			kid.draw_circle(sl[0], 1.5, Color(0, 1, 1))
		for sh in sd["shore"]:
			kid.draw_circle(sh[0], 1.2, Color(1, 0, 0))
		for f in sd["fields"]:
			kid.draw_polyline(f["quad"], Color(0, 0, 0), 1.0)
		kid.draw_circle(sd["p0"], 2.0, Color(1, 1, 1))
