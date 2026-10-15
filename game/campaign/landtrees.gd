extends Node2D
## The landscape's trees and rocks as models (map-table style, not Graphics Low; view only): the map's tree
## kinds (broadleaf, pine, scrub, cypress, palm in the tropics) and its rocks, at a few variants each, drawn from
## the minis atlas by ONE MultiMesh at the same positions and sizes as the old dots (landscape.gd's lists),
## sorted by y. Both atlas sizes are prepared as instance buffers when the landscape is baked, so crossing a
## zoom threshold swaps one buffer (no hitch). The trees right round a town are drawn by town_layer.gd with its
## pieces (one y order); their cast shadows, and these, are baked into the ground texture (town_paint.gd).
## Graphics Low keeps the mesh dots.

const CData := preload("res://campaign/cdata.gd")
const Landscape := preload("res://game/campaign/landscape.gd")
const MapGen := preload("res://sim/mapgen.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const Atlas := preload("res://game/minis_atlas.gd")
const Quality := preload("res://game/quality.gd")
const MapLook := preload("res://game/campaign/map_look.gd")
const TownPlan := preload("res://game/campaign/town_plan.gd")
const SHADER := preload("res://game/campaign/landtrees.gdshader")

const NOMINAL_TREE := 3.4     # px: the crown radius of a model at scale 1 (K * 3 m)
const NOMINAL_ROCK := 1.9
const BIG_PX_M := 2.0

var overlay: Node2D
var _inst: MultiMeshInstance2D = null
var _mm: MultiMesh = null
var _mats := {}
var _tex := {}
var _bufs := {}               # atlas name -> PackedFloat32Array
var _gen := -1
var _variant := ""
var count := 0
var build_ms := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	for nm in ["small", "big"]:
		_tex[nm] = load("res://assets/minis/atlas_%s_shade.png" % nm)
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("mask", load("res://assets/minis/atlas_%s_mask.png" % nm))
		MapLook.apply(m)
		_mats[nm] = m


## The model of a map tree t ([x, y, kind, shade, radius, rot, palette]): [piece, scale, colour].
static func pick_tree(t: Array) -> Array:
	var kind := int(t[2])
	var rad := float(t[4])
	var rot := float(t[5])
	var pi := int(t[6])
	var v := int(rot * 10.0) % 3
	var h := fposmod(float(t[0]) * 0.1371 + float(t[1]) * 0.0937, 1.0)
	var col := Landscape.tree_color(pi, int(t[3]))
	col = Color(minf(col.r * 1.3 + 0.03, 1.0), minf(col.g * 1.3 + 0.03, 1.0), minf(col.b * 1.3 + 0.02, 1.0))
	var nm := "lt_b%d" % (v + 1)
	var k := rad / NOMINAL_TREE
	match kind:
		1:
			nm = "lt_pine%d" % (v + 1)
		2:
			nm = "lt_scrub%d" % (v % 2 + 1)
			k = rad * 1.2 / 2.8
		3:
			nm = "lt_cypress"
			k = rad / 2.4
		_:
			if CData.pack == "west" and (pi == MapGen.PAL_GREEN or pi == MapGen.PAL_DRY) and h < 0.2:
				nm = "lt_palm%d" % (v % 2 + 1)
				col = Color(0.42, 0.66, 0.30)
				k = rad / NOMINAL_TREE * 0.95
	return [nm, k, col]


## The model of a speck [x, y, rock, radius].
static func pick_speck(sp: Array) -> Array:
	var r := float(sp[3])
	var h := fposmod(float(sp[0]) * 0.1137 + float(sp[1]) * 0.0731, 1.0)
	if bool(sp[2]):
		var shade := 0.82 + 0.3 * h
		if r > 1.9 and h > 0.55:
			return ["lt_crag", r / 2.6, Color(0.70 * shade, 0.67 * shade, 0.60 * shade)]
		return ["lt_rock%d" % (int(h * 3.0) % 3 + 1), r / NOMINAL_ROCK * 1.2, Color(0.70 * shade, 0.67 * shade, 0.60 * shade)]
	return ["lt_scrub2", r * 1.2 / 2.8, Color(0.52, 0.55, 0.30)]


func _build() -> void:
	var t0 := Time.get_ticks_usec()
	var items: Array = []
	for sp in Landscape.speck_list:
		var pk := pick_speck(sp)
		items.append([float(sp[0]), float(sp[1]), pk])
	for t in Landscape.tree_list:
		var pk := pick_tree(t)
		items.append([float(t[0]), float(t[1]), pk])
	count = items.size()
	for nm in ["small", "big"]:
		var table: Dictionary = Atlas.SETS[nm]
		var tex: Texture2D = _tex[nm]
		var w := float(tex.get_width())
		var h := float(tex.get_height())
		var buf := PackedFloat32Array()
		buf.resize(count * 16)
		var i := 0
		for it in items:
			var pk: Array = it[2]
			var key := "p_%s__y0" % str(pk[0])
			var e: Array = table[key]
			var k := TownPlan.K / float(e[6]) * float(pk[1])
			var o := i * 16
			var sw := float(e[2]) * k
			var sh := float(e[3]) * k
			var ox := float(it[0]) - float(e[4]) * k
			var oy := float(it[1]) - float(e[5]) * k
			buf[o] = sw
			buf[o + 1] = 0.0
			buf[o + 2] = 0.0
			buf[o + 3] = ox
			buf[o + 4] = 0.0
			buf[o + 5] = sh
			buf[o + 6] = 0.0
			buf[o + 7] = oy
			var c: Color = pk[2]
			buf[o + 8] = c.r
			buf[o + 9] = c.g
			buf[o + 10] = c.b
			buf[o + 11] = 1.0
			buf[o + 12] = float(e[0]) / w
			buf[o + 13] = float(e[1]) / h
			buf[o + 14] = float(e[2]) / w
			buf[o + 15] = float(e[3]) / h
			i += 1
		_bufs[nm] = buf
	if _inst == null:
		_mm = MultiMesh.new()
		_mm.transform_format = MultiMesh.TRANSFORM_2D
		_mm.use_colors = true
		_mm.use_custom_data = true
		var am := ArrayMesh.new()
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		_mm.mesh = am
		_inst = MultiMeshInstance2D.new()
		_inst.multimesh = _mm
		add_child(_inst)
	_mm.instance_count = count
	_variant = ""
	_gen = Landscape.glyph_gen
	build_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _process(_d: float) -> void:
	if overlay == null:
		return
	var on := MapView.table_on() and MapView.terrain_view and Landscape.models and not (overlay.state as Dictionary).is_empty() and Landscape.tree_count > 0
	if visible != on:
		visible = on
	if not on:
		return
	if _gen != Landscape.glyph_gen:
		_build()
	var v := "small" if TownPlan.K * float(overlay.zoom) < BIG_PX_M else "big"
	if v != _variant:
		_variant = v
		_mm.buffer = _bufs[v]
		_inst.texture = _tex[v]
		_inst.material = _mats[v]
