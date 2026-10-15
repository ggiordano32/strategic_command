extends Node2D
## The overworld towns as the map-table style draws them (view only): each town is assembled from kit
## pieces (town_plan.gd) placed on the terrain, drawn in world coordinates under the map's own transform
## (a child of the campaign screen's `world`, over the map and under the overlay), so pan and zoom cost
## nothing: a town's canvas item is drawn again only when its plan changes (growth, walls, a conquest) or the
## atlas size flips at a zoom threshold. Pieces and the map trees just outside the cleared ground share one
## y order per town. The ground under them is painted into the land by town_paint.gd.
## Graphics Low: the small atlas and a coarser ground texture.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const TownPlan := preload("res://game/campaign/town_plan.gd")
const TownPaint := preload("res://game/campaign/town_paint.gd")
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
	if overlay == null:
		return
	var st: Dictionary = overlay.state
	var tbl := MapView.table_on() and MapView.terrain_view and not st.is_empty() and CData.region_count() > 0
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
	var changed := false
	var t0 := Time.get_ticks_usec()
	for r in CData.region_count():
		var rg: Dictionary = st["regions"][r]
		var sig := "%d_%d_%d_%d_%s" % [int(rg["level"]), CState.walls(st, r), int(rg["owner"]), CState.building(st, r, CData.SHIPYARD), TownPlan.style_of(st, r)]
		if _sigs.get(r, "") == sig:
			continue
		_sigs[r] = sig
		var prev: Dictionary = _plans.get(r, {})
		var pl := TownPlan.plan(st, r, grid)
		_plans[r] = pl
		var kid: Node2D = _kids.get(r)
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
	var pl: Dictionary = _plans[r]
	var w: Vector2 = pl["water"]
	var c: Vector2 = pl["c"]
	return {"c": c, "p0": (TownPlan.site(r, _grid))["p0"], "half_w": pl["half_w"], "top": pl["top"], "bottom": pl["bottom"], "water": w,
		"side": 0.0 if w == Vector2.ZERO else (-1.0 if w.x < c.x else 1.0)}


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


func _draw_town(kid: Node2D, r: int) -> void:
	if not _plans.has(r) or overlay == null:
		return
	var st: Dictionary = overlay.state
	if st.is_empty():
		return
	var pl: Dictionary = _plans[r]
	var items: Array = pl["items"]
	var aname := _variant if _variant != "" else "small"
	var table: Dictionary = Atlas.SETS[aname]
	if not _shades.has(aname):
		aname = "small"
	var shade: Texture2D = _shades[aname]
	table = Atlas.SETS[aname]
	kid.material = _mat(aname)
	var col := CData.faction_color(int(st["regions"][r]["owner"]))
	var trees := _trees(r)
	var wh: Array = table["white"]
	var wuv := Vector2((float(wh[0]) + 4.0) / float(shade.get_width()), (float(wh[1]) + 4.0) / float(shade.get_height()))
	var ti := 0
	var low := Quality.is_low()
	var nt := trees.size()
	for it in items:
		var ii: Array = it
		var pos: Vector2 = ii[0]
		while ti < nt and float((trees[ti] as Array)[1]) <= pos.y:
			_ring_tree(kid, trees[ti], table, shade, wuv)
			ti += 1
		var pn := str(ii[1])
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
		kid.draw_texture_rect_region(shade, dst, Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3])), col)
	while ti < nt:
		_ring_tree(kid, trees[ti], table, shade, wuv)
		ti += 1
	if OS.get_cmdline_user_args().has("townsdbg"):
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
