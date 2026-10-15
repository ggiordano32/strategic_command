extends Node2D
## Painted miniatures of the fleets on the overworld (view only; tools/structures builds the sprites,
## game/minis_atlas.gd lists them): ships at 8 headings bobbing on SeaWaves, a contact shadow and a wake. Sits
## under map_overlay.gd (same canvas layer, added before it) so the names, army banners and fleet pennants draw
## over the models. The towns are not drawn here any more: town_layer.gd assembles them from kit pieces on the
## map itself; this layer only answers the overlay's questions about them (`on_sites`, half width, label lift,
## where fleets in port stand) from the town plans. Quality Low: the small atlas only, no bobbing redraws.
## The overlay asks `on_sites` / `on_ships` (set here each frame) whether to skip its icon or ship hull.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CSea := preload("res://campaign/csea.gd")
const MapGen := preload("res://sim/mapgen.gd")
const Quality := preload("res://game/quality.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const SeaWaves := preload("res://game/campaign/sea_waves.gd")
const Atlas := preload("res://game/minis_atlas.gd")
const SHADER := preload("res://game/campaign/minis.gdshader")
const MapLook := preload("res://game/campaign/map_look.gd")

static var on_sites := false
static var on_ships := false
static var towns: Node = null   # the town layer (town_layer.gd), set by the campaign screen
static var _label_lift := 0.0
static var _headings := {}   # fleet id -> last heading 0..7

const SITE_MIN_ZOOM := 0.55
const SHIP_MIN_ZOOM := 0.35
const TILE_M := 58.0           # a base tile's width in metres (the sprites' scale)
const SHIP_RANK := ["ship_of_the_line", "galleon", "frigate", "brigantine", "sloop", "war_canoe"]
const SHIP_K := 1.0

var overlay: Node2D
var _tex := {}   # set name -> [shade, mask material]
var _t_acc := 0.0
var _under: Node2D       # drawn behind the sprites: ship wakes and contact shadows
var _wakes: Array = []   # [position, scale, heading]
static var texture_bytes := 0


func _ready() -> void:
	z_index = 0
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_under = Node2D.new()
	_under.show_behind_parent = true
	_under.draw.connect(_draw_under)
	add_child(_under)


func _atlas(name_set: String) -> Array:
	if _tex.has(name_set):
		return _tex[name_set]
	var sh: Texture2D = load("res://assets/minis/atlas_%s_shade.png" % name_set)
	var mk: Texture2D = load("res://assets/minis/atlas_%s_mask.png" % name_set)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("mask", mk)
	MapLook.apply(m)
	_tex[name_set] = [sh, m]
	if sh != null:
		texture_bytes += sh.get_width() * sh.get_height() * 4 + mk.get_width() * mk.get_height() * 3
	return _tex[name_set]


## Pixels the label of a settlement is lifted above its anchor (0: icons).
## Pixels armies inside a settlement's walls are dropped below its anchor.
static func army_drop() -> float:
	return _label_lift * 0.5 if on_sites else 0.0


## Half the width of settlement r's model on screen (walls included).
static func half_w(zoom: float, r: int) -> float:
	var i := _info(r)
	if i.is_empty():
		return tile_px(zoom) * 0.55
	return float(i["half_w"]) * zoom


## Where fleets in port wait: in the water off the harbour (the town plan's water spot, on the real sea),
## else beside the model on the harbour side (side -1 / +1), a little below its anchor.
static func fleet_spot(r: int, site: Vector2, side: float, zoom: float, to_screen: Callable) -> Vector2:
	var i := _info(r)
	if not i.is_empty() and (i["water"] as Vector2) != Vector2.ZERO:
		return to_screen.call(i["water"])
	return site + Vector2(side * (half_w(zoom, r) + 24.0), tile_px(zoom) * 0.3)


## -1 / +1 the side the harbour of r lies on (from the plan), 0 when the plan has none.
static func harbour_side(r: int) -> float:
	var i := _info(r)
	return 0.0 if i.is_empty() else float(i["side"])


## The screen rectangle of the model of r relative to its site point (the model sits on the point).
static func model_rect(zoom: float, r: int) -> Rect2:
	var i := _info(r)
	if i.is_empty():
		var tp := tile_px(zoom)
		return Rect2(-tp * 0.55, -tp * 0.9, tp * 1.1, tp * 1.4)
	var off: Vector2 = ((i["c"] as Vector2) - (i["p0"] as Vector2)) * zoom
	var hw := float(i["half_w"]) * zoom
	var t := float(i["top"]) * zoom
	var b := float(i["bottom"]) * zoom
	return Rect2(off.x - hw, off.y - t, hw * 2.0, t + b)


## Pixels the label of r is lifted above its anchor (0: icons).
static func label_lift_of(zoom: float, r: int) -> float:
	if not on_sites:
		return 0.0
	var i := _info(r)
	if i.is_empty():
		return _label_lift
	return minf(float(i["top"]) * zoom * 0.8, 60.0 + 80.0 * zoom)


static func _info(r: int) -> Dictionary:
	if towns == null or not is_instance_valid(towns) or not on_sites:
		return {}
	return towns.call("info", r)


## Ship scale factor: smaller at mid zoom so a fleet is no taller than a town.
static func ship_k(zoom: float) -> float:
	return clampf(0.62 + (zoom - 1.0) * 0.25, 0.55, 1.0)


static func label_lift() -> float:
	return _label_lift if on_sites else 0.0


## Diameter of a base tile on screen at this zoom.
static func tile_px(zoom: float) -> float:
	return 88.0 * sqrt(maxf(zoom, 0.05))


func _process(delta: float) -> void:
	if overlay == null:
		return
	var z: float = overlay.zoom
	var st: Dictionary = overlay.state
	var tbl := MapView.table_on() and MapView.terrain_view   # the miniatures are the map-table style's
	var s_on := tbl and not st.is_empty() and z >= SITE_MIN_ZOOM and towns != null and bool(towns.get("on")) and bool(towns.call("planned"))
	var sh_on := tbl and not st.is_empty() and z >= SHIP_MIN_ZOOM and CData.ships_on()
	on_sites = s_on
	on_ships = sh_on
	_label_lift = tile_px(z) * 0.5
	if not (s_on or sh_on):
		if visible:
			visible = false
		return
	visible = true
	_t_acc += delta
	if Quality.is_low() and _t_acc < 0.1:
		return
	_t_acc = 0.0
	queue_redraw()


func _draw() -> void:
	if overlay == null:
		return
	var st: Dictionary = overlay.state
	if st.is_empty():
		return
	var z: float = overlay.zoom
	var vp := get_viewport_rect().grow(120.0)
	_wakes.clear()
	var items: Array = []   # [screen y, kind, payload...]
	if on_ships and st.has("fleets"):
		var fpos: Dictionary = overlay.fleet_positions()
		for fl in st["fleets"]:
			var id := int(fl["id"])
			if fpos.has(id):
				var q: Vector2 = fpos[id]
				if vp.has_point(q):
					items.append([q.y, 1, fl, q])
	items.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var tile := tile_px(z)
	var small := Quality.is_low() or tile < 92.0
	var aname := "small" if small else "big"
	var sd := _atlas(aname)
	var table: Dictionary = Atlas.SETS[aname]
	var shade: Texture2D = sd[0]
	if shade == null:
		return
	material = sd[1]
	for it in items:
		_ship(it[2], it[3], tile / TILE_M * ship_k(z), table, shade)
	_under.queue_redraw()


func _blit(table: Dictionary, shade: Texture2D, nm: String, at: Vector2, pxm: float, col: Color, alpha := 1.0) -> void:
	if not table.has(nm):
		return
	var e: Array = table[nm]
	var k := pxm / float(e[6])
	var dst := Rect2(at - Vector2(float(e[4]), float(e[5])) * k, Vector2(float(e[2]), float(e[3])) * k)
	draw_texture_rect_region(shade, dst, Rect2(float(e[0]), float(e[1]), float(e[2]), float(e[3])), Color(col.r, col.g, col.b, alpha))


## The heading (0..7, 45 deg steps anticlockwise from east on the north-up
## map) of fleet fl: along its planned voyage, else the last one, else a
## stable one from its id.
func _heading(fl: Dictionary) -> int:
	var id := int(fl["id"])
	for fp in overlay.fleet_paths:
		if int(fp["fleet"]) == id and (fp["path"] as Array).size() >= 2:
			var a: Vector2 = overlay.cell_point(int(fp["path"][0]))
			var b: Vector2 = overlay.cell_point(int(fp["path"][1]))
			var d := b - a
			if d.length() > 0.1:
				var h := int(round(atan2(-d.y, d.x) / (PI / 4.0))) & 7
				_headings[id] = h
				return h
	if not _headings.has(id):
		_headings[id] = (id * 3 + 1) & 7
	return int(_headings[id])


func _ship(fl: Dictionary, c: Vector2, pxm: float, table: Dictionary, shade: Texture2D) -> void:
	var f := int(fl["f"])
	var col := CData.faction_color(f)
	var types: Array = []
	for s in fl["ships"]:
		types.append(str(s["t"]))
	if types.is_empty():
		return
	types.sort_custom(func(a, b): return SHIP_RANK.find(a) < SHIP_RANK.find(b))
	var mp: Vector2 = overlay.cell_point(CFleet.cell(fl))
	var tt: float = SeaWaves.t if SeaWaves.t > 0.0 else float(overlay.pulse)
	var amp := clampf(SeaWaves.amp(mp), 0.25, 1.0)
	var bob := 0.0 if Quality.is_low() else SeaWaves.height(mp, tt) * amp * 1.6 * pxm * 3.0
	var h := _heading(fl)
	var pos := c + Vector2(0, bob)
	var sc := pxm
	_wakes.append([c, pxm, h])
	if types.size() >= 2:
		var t2: String = types[1]
		_blit(table, shade, "ship_%s__h%d" % [t2, h], pos + Vector2(-9.0, -5.0) * (pxm / 1.3), sc * 0.82, col)
	_blit(table, shade, "ship_%s__h%d" % [types[0], h], pos, sc, col)


## A soft contact shadow (south-east, the light is north-west) and a small wake behind each ship.
func _draw_under() -> void:
	var low := Quality.is_low()
	for w in _wakes:
		var c: Vector2 = w[0]
		var k: float = w[1]
		var a: float = float(int(w[2])) * PI / 4.0
		var dir := Vector2(cos(a), -sin(a))
		var back := -dir
		for i in (1 if low else 3):
			var f := float(3 - i) / 3.0
			var pts := PackedVector2Array()
			for j in 16:
				var t := TAU * float(j) / 16.0
				pts.append(c + Vector2(4.0, 3.0) * k + Vector2(cos(t) * 15.0, sin(t) * 7.5) * k * (0.6 + 0.4 * f))
			_under.draw_colored_polygon(pts, Color(0.03, 0.10, 0.20, 0.13))
		if low:
			continue
		var foam := Color(1, 1, 1, 0.5)
		for side in [-1.0, 1.0]:
			var pl := PackedVector2Array()
			for s in 6:
				var d := float(s) * 4.5 * k
				var sp: float = (3.0 + float(s) * 2.2 * k) * side
				pl.append(c + Vector2(0.0, 2.0 * k) + (back * d + Vector2(-back.y, back.x) * sp) * Vector2(1.0, 0.62))
			foam.a = 0.5
			_under.draw_polyline(pl, foam, maxf(1.0, 1.5 * k), true)
		_under.draw_arc(c + dir * 4.0 * k + Vector2(0.0, 2.0 * k), 9.0 * k, 0.0, TAU, 20, Color(1, 1, 1, 0.28), maxf(1.0, 1.2 * k), true)
