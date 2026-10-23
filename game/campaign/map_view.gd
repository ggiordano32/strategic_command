extends Node2D
## Campaign map, world layer (map pixels; the camera pans and zooms it):
## sea, land, territories tinted by owner, borders, land routes and sea lanes,
## and the highlighted destinations of the selected army. Markers and text
## are drawn by map_overlay.gd in screen space so they stay crisp and sized
## for touch at any zoom.
##
## State version 6: the selected army's reach this turn is a filled
## translucent area with a smoothed outline (cells from CRules.reach6; next
## turn's a dashed outline); land routes are gone (armies walk the grid),
## sea lanes join the port cells. Roads, rivers and hills (2026-10-09, from
## the grid the rules read): hill / ridge cells a faint chevron each (two
## for a ridge), rivers blue lines (map_geo.gd's lines: an orthogonal step
## is a river edge exactly when it crosses one), a ford stepping stones
## across the river and a bridge a deck over it, both where the crossing's
## step meets the line, roads thin tan lines through their cells' centres.

const ZProf := preload("res://game/campaign/zprof.gd")
const Quality := preload("res://game/quality.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const FogView := preload("res://game/campaign/fog_view.gd")
const Geo := preload("res://game/campaign/map_geo.gd")
const GroundPalette := preload("res://game/ground_palette.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const Landscape := preload("res://game/campaign/landscape.gd")
const CLanes := preload("res://campaign/clanes.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const GeoFields := preload("res://game/campaign/geo_fields.gd")
const WATER_SHADER := preload("res://game/campaign/water.gdshader")
const SeaWaves := preload("res://game/campaign/sea_waves.gd")

const SEA := Color(0.13, 0.25, 0.34)
const SEA_SHALLOW := Color(0.22, 0.38, 0.47)
const LAND := Color(0.80, 0.76, 0.62)
const COAST := Color(0.09, 0.11, 0.10, 0.92)
const TINT := 0.55         # owner colour over the region's ground
const GROUND_LIFT := 0.36  # the battle palettes are darker than a map should be
## Lines and highlights, shared with the map key (map_key.gd draws its
## samples with the painters below). Widths are screen px (times lw).
const COL_SEA_LANE := Color(0.75, 0.9, 1.0, 0.6)
const SEA_LANE_DASH := 3.0
const COL_ROUTE := Color(0.25, 0.18, 0.1, 0.55)   # versions 1-5: land routes
const ROUTE_DASH := 7.0
const LANE_W := 1.6
const COL_REACH := Color(1.0, 0.98, 0.85, 0.36)    # version 6: reach this turn (fill)
const COL_REACH_EDGE := Color(1, 0.95, 0.6, 0.95)
const COL_REACH_NEXT := Color(1, 1, 0.9, 0.7)     # ... next turn (dashed outline)
const REACH_NEXT_W := 2.0
const REACH_NEXT_DASH := 7.0                       # dash and gap, screen px
const OWNER_EDGE_A := 0.85                         # owner band inside each territory
const OWNER_EDGE_W := 3.5
const COL_BLOCKED := Color(0.1, 0.1, 0.1, 0.32)    # version 5: a neighbour it cannot enter
const COL_BLOCKED_EDGE := Color(0.15, 0.15, 0.15, 0.85)
## Roads, rivers and hills (version 6). Widths are screen px (times lw).
const COL_RIVER := Color(0.22, 0.46, 0.78, 0.95)
const RIVER_W := 2.4
const COL_ROAD := Color(0.55, 0.4, 0.22, 0.85)
const ROAD_W := 1.7
## The table style paints roads as dirt tracks (a soft-edged ochre ribbon, broken by the towns) and the sea
## lanes as pale dashed curves (2026-10-22).
const COL_TRACK := Color(0.50, 0.36, 0.17)
const TRACK_CORE_W := 2.4
const TRACK_EDGE_W := 4.6
const TRACK_GAP_VILLAGE := 8.0     # map px cleared round a settlement's centre
const TRACK_GAP_TOWN := 11.0
const TRACK_GAP_CITY := 14.0
const COL_LANE_TABLE := Color(0.93, 0.97, 1.0, 0.62)
const LANE_TABLE_DASH := 6.0
const LANE_TABLE_GAP := 5.0
const LANE_TABLE_W := 1.9
const LANE_DASH := 4.0
const LANE_GAP := 3.5
const COL_HILL := Color(0.25, 0.18, 0.08, 0.2)
const COL_RIDGE := Color(0.2, 0.13, 0.05, 0.3)
## Relief shading (2026-10-10): an elevation field from the grid (ridge 2,
## hill 1, else 0), blurred, lit from the north-west, baked once into an
## image of the grid's size and drawn bilinear over the land fill.
const SHADE_BLUR := 2          # box blur radius in cells, applied twice
const SHADE_SLOPE := 3.0       # slope gain
const SHADE_ALPHA := 0.5       # opacity of the shade at full slope
const SHADE_HEIGHT_A := 0.10   # opacity of the warm height tint per elevation unit
const SHADE_LIGHT := Color(1.0, 0.96, 0.8)
const SHADE_DARK := Color(0.12, 0.08, 0.1)
const SHADE_TINT := Color(1.0, 0.9, 0.62)
const HILL_W := 1.2
const COL_FORD := Color(0.93, 0.9, 0.8, 1.0)
const COL_BRIDGE := Color(0.45, 0.3, 0.15, 1.0)

## Terrain view (2026-10-10): the land is its ground (landscape.gd: palette
## texture, peaks, domes, trees, speckles) with the owner a translucent tint;
## Political is the older look (region fills in owner colour, hatch marks).
## A view preference in user://settings.cfg [map] terrain (never in the
## state); "--map-view=political|terrain" on the command line overrides it
## for the session without saving.
const SETTINGS := "user://settings.cfg"
const TERRAIN_TINT := 0.30   # owner colour alpha over the ground
const COL_BANK_GREEN := Color(0.30, 0.52, 0.26, 0.30)
const BANK_GREEN_W := 11.0
const BANK_W := 4.8
static var terrain_view := true
## The sea (2026-10-13, water.gdshader): a narrow depth tint, contour lines, waves lit as a normal map, surf
## foam on wind-exposed coasts and an advected current texture; "low" keeps the depth tint and contour
## lines only (sea_waves.gd is the waves' CPU twin). A view preference in user://settings.cfg [map] water = low | high
## ("--map-water=low|high" overrides it for the session).
static var water_high := true
## The map style (2026-10-14): "table" (miniature diorama: posterised hillshade bands with ink contours, a brighter
## palette, clean banded sea, a softer owner wash with a stronger border; table_land.gdshader, table_frame.gd)
## or "relief" (the hillshaded relief of 2026-10-10). A view preference in user://settings.cfg [map] style =
## auto | table | relief (auto: table for the West pack, relief for Rome); "--map-style=table|relief" overrides it.
const TABLE_LAND_SHADER := preload("res://game/campaign/table_land.gdshader")
const MapLook := preload("res://game/campaign/map_look.gd")
const TABLE_TINT := 0.15      # the owner wash over the land in the table style
const TABLE_EDGE_W := 3.6
const TABLE_BORDER := Color(0.12, 0.08, 0.05, 0.5)
static var style_pref := "auto"
static var _elev_tex: ImageTexture = null
static var _elev_gen := -1
var _table: Node2D = null
var _pulse_node: Node2D = null
## Beaches and cliffs along the coast (2026-10-22): a coast cell a fleet may land on (CFleet.land_ok's geometric part:
## land with open sea beside it) gets a sand strip on the land side of the coastline, any other coast cell (water
## beside it that no fleet sails: a lagoon, a lake) a dark rock line with hatch ticks. Widths are screen px (times lw).
const COL_SAND := Color(0.93, 0.84, 0.58)
const COL_FOAM := Color(1.0, 1.0, 1.0)
const COL_ROCK := Color(0.16, 0.14, 0.13)
const COL_ROCK_RELIEF := Color(0.05, 0.05, 0.06)
const BEACH_STEP := 4.0            # map px between the samples along the coastline
const BEACH_BAND := 1.08           # the strip's offset is rebuilt when the zoom changes by this factor
const CLIFF_TICK_GAP := 6.0        # screen px between the hatch ticks
const CLIFF_TICK_LEN := 3.8
var _reach_node: Node2D = null  # the selected army's reach (its own node: a selection does not redraw the map)
var _sel_node: Node2D = null    # the selected region's outline (over the edges, under the coast)
var _reach_rt := PackedInt32Array()      # the reach set_reach last outlined
var _owners_drawn := PackedInt32Array()   # the owners the map was last drawn for (refresh_state)
var _edges: Node2D = null     # children drawn after the map's own drawing, redrawn a frame apart (see _process)
var _coast_node: Node2D = null
var _beach_node: Node2D = null   # the beaches and cliffs (see "beaches and cliffs")
var _beach_band := -9999         # the zoom band (and style, pack) the beach node was drawn for
var _tbl := false
var _stage := 0
var _heavy_frame := -1
static var _land_meshes: Array = []   # triangulated once: the polygons are fine now
static var _land_sz := Vector2.ZERO
static var _cell_meshes: Dictionary = {}   # region -> Array of ArrayMesh
var _water: Node2D = null
static var _pref_loaded := false
static var instance: Node2D = null

## Built once from the grid (view only): hatch segments per kind, road
## polylines, river polylines, crossing glyphs [point, step direction, kind].
static var _hill_segs: Array = []
static var _shade_tex: ImageTexture = null
static var _shade_ms := -1.0   # bake time, ms (for the record)
static var _road_lines: Array = []
static var _track_lines: Array = []   # the road lines cut open at the settlements (table style)
static var _lane_lines: Array = []    # sea lanes: smoothed polylines (map px) through the sea
static var _lane_polys := {}          # lane id -> its polyline (a lane whose curve came out empty is missing)
static var _lane_dashes: Array = []   # ... cut into dashes for this line scale / style
static var _lane_dash_key := ""
static var _river_lines: Array = []
static var _cross_marks: Array = []
## The coast dressing: runs of the coastline [kind (1 beach, 2 cliff), points (map px), inward normals], built once
## from the land polygons and the grid.
static var _coast_runs: Array = []
static var _coast_class := PackedByteArray()   # per cell: 0 not coast, 1 landing coast, 2 other coast, 255 unknown
static var _coast_drawn := PackedByteArray()   # per cell: bit 1 a beach segment was drawn, bit 2 a cliff segment
static var _beach_cell_pts: Dictionary = {}    # cell -> PackedVector2Array of its beach's coast points (map px)
static var _beach_cells := PackedInt32Array()  # the cells with a beach, ascending
static var _coast_unseen := PackedInt32Array()  # coast cells of the grid with no outline of the map within two cells
static var _coast_ms := -1.0                   # build time, ms (for the record)
static var _coast_geo_key := ""
static var _coast_geo: Array = []              # the runs offset for the zoom band: [kind, line, foam line, tick segments]
static var _gen := 0           # map_geo.gd's gen these caches belong to


## A pack switch (Geo.use_pack) invalidates the geometry caches.
static func _sync_gen() -> void:
	if _gen == Geo.gen:
		return
	_gen = Geo.gen
	_land_meshes = []
	_land_sz = Vector2.ZERO
	_cell_meshes = {}
	_hill_segs = []
	_shade_tex = null
	_road_lines = []
	_track_lines = []
	_lane_lines = []
	_lane_polys = {}
	_lane_dashes = []
	_lane_dash_key = ""
	_river_lines = []
	_cross_marks = []
	_coast_runs = []
	_coast_class = PackedByteArray()
	_coast_drawn = PackedByteArray()
	_coast_unseen = PackedInt32Array()
	_beach_cell_pts = {}
	_beach_cells = PackedInt32Array()
	_coast_geo_key = ""
	_coast_geo = []

var state: Dictionary = {}
var zoom := 1.0
## The visible part of the map (world px, set by the screen each frame).
var view_rect := Rect2()
## Regions to highlight as move destinations, and the hovered / selected region.
var targets: Array[int] = []
var attack_targets: Array[int] = []
## Neighbours the selected army cannot enter (muted, crossed out).
var blocked_targets: Array[int] = []
## State version 5: the turn the selected army reaches each target (0 this
## turn: bright; 1 next turn: dimmer; later: outline only).
var target_turns: Dictionary = {}
var selected_region := -1
var pulse := 0.0
## Version 6 reach: cells (map-pixel squares) and smoothed outlines.
var grid := false
var reach_rects: Array = []      # Rect2 per reachable cell this turn (fallback fill)
var reach_fill: Array = []       # outer outlines that triangulate (the fill)
var reach_loops: Array = []      # PackedVector2Array outlines (this turn)
var next_loops: Array = []       # ... within two turns (dashed)
var _next_dashes: Array = []     # next_loops cut into dashes (PackedVector2Array of segment pairs)
var _next_dashes_lw := -1.0      # ... for this line scale


## Set the reach (per cell: 0 this turn, 1 next turn, -1 not), or clear it
## (empty array).
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	load_view_pref()
	instance = self
	_make_water()


## The sea: one quad behind this node's own drawing (the land polygons cover
## it), with water.gdshader reading the coast distance field.
func _make_water() -> void:
	_water = Node2D.new()
	_water.show_behind_parent = true
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	var f := GeoFields.coast()
	var img := Image.create_from_data(GeoFields.fine_width(), GeoFields.fine_height(), false, Image.FORMAT_L8, f)
	m.set_shader_parameter("coast", ImageTexture.create_from_image(img))
	m.set_shader_parameter("field_px", Vector2(GeoFields.fine_width(), GeoFields.fine_height()) * GeoFields.sample_px())
	m.set_shader_parameter("hi", 1.0 if _water_hi() else 0.0)
	m.set_shader_parameter("shore", ImageTexture.create_from_image(GeoFields.shore_image()))
	m.set_shader_parameter("depth", ImageTexture.create_from_image(GeoFields.depth_image()))
	m.set_shader_parameter("wind_dir", GeoFields.wind_dir())
	m.set_shader_parameter("wind_strength", GeoFields.wind_strength())
	for i in SeaWaves.TRAINS.size():
		m.set_shader_parameter("train%d" % i, SeaWaves.TRAINS[i])
	m.set_shader_parameter("table", 1.0 if table_on() else 0.0)
	m.set_shader_parameter("wave_gain", 0.6 if table_on() else 1.0)
	_water.material = m
	_water.draw.connect(func(): _water.draw_rect(Rect2(Vector2(-4000, -4000), Geo.SIZE + Vector2(8000, 8000)), SEA))
	add_child(_water)
	_table = Node2D.new()
	_table.show_behind_parent = true
	_table.visible = false
	_table.draw.connect(_draw_table_land)
	add_child(_table)
	_reach_node = Node2D.new()
	_reach_node.draw.connect(_draw_reach_node)
	add_child(_reach_node)
	_pulse_node = Node2D.new()
	_pulse_node.draw.connect(_draw_pulse)
	add_child(_pulse_node)
	_edges = Node2D.new()
	_edges.draw.connect(_draw_edges)
	add_child(_edges)
	_sel_node = Node2D.new()
	_sel_node.draw.connect(_draw_sel)
	add_child(_sel_node)
	_beach_node = Node2D.new()   # (under the coast node: its own redraw, only when the zoom band changes)
	_beach_node.draw.connect(_draw_beach_node)
	add_child(_beach_node)
	_coast_node = Node2D.new()
	_coast_node.draw.connect(_draw_coast)
	add_child(_coast_node)


## The style changed: the sea's uniforms, the land node, a redraw.
func _sync_style() -> void:
	var m := _water.material as ShaderMaterial
	m.set_shader_parameter("table", 1.0 if table_on() else 0.0)
	m.set_shader_parameter("wave_gain", 0.6 if table_on() else 1.0)
	if (Landscape.clear_towns != table_on() or Landscape.models != (table_on() and not Quality.is_low())) and Landscape.tree_count > 0:
		Landscape.clear_towns = table_on()
		Landscape.models = table_on() and not Quality.is_low()
		Landscape.rebake_glyphs()
	queue_redraw()


## The painted ground of the towns (town_paint.gd, baked once and again when a town changes): the land
## shader mixes it in. `size` is the world size (px) the texture covers.
static var _town_tex: Texture2D = null
static var _town_size := Vector2.ONE


func set_town_paint(tex: Texture2D, size: Vector2) -> void:
	_town_tex = tex
	_town_size = size
	if _table != null and _table.material != null:
		_apply_town_paint(_table.material as ShaderMaterial)


static func _apply_town_paint(m: ShaderMaterial) -> void:
	m.set_shader_parameter("towns", _town_tex)
	m.set_shader_parameter("towns_px", _town_size)
	m.set_shader_parameter("towns_on", 1.0 if _town_tex != null else 0.0)


## The road polylines (world px) the towns' tracks join.
static func road_lines() -> Array:
	_terrain_geometry()
	return _road_lines


## The land polygons with the table shader (behind this node's own drawing).
func _draw_table_land() -> void:
	if _table.material == null:
		var m := ShaderMaterial.new()
		m.shader = TABLE_LAND_SHADER
		m.set_shader_parameter("ground", Landscape.ground_tex)
		m.set_shader_parameter("elev", _elevation_tex())
		m.set_shader_parameter("coast", (_water.material as ShaderMaterial).get_shader_parameter("coast"))
		m.set_shader_parameter("field_px", Vector2(GeoFields.fine_width(), GeoFields.fine_height()) * GeoFields.sample_px())
		m.set_shader_parameter("elev_texel", Vector2(1.0 / GeoFields.fine_width(), 1.0 / GeoFields.fine_height()))
		m.set_shader_parameter("sample_m", GeoFields.sample_m())
		_apply_town_paint(m)
		MapLook.apply(m)
		_table.material = m
	var lsz := Vector2(CGrid.width(), CGrid.height()) * float(CGrid.cell_px())
	for mesh in land_meshes(lsz):
		_table.draw_mesh(mesh, null)


## The real elevation (metres) as a half-float texture, once per pack.
static func _elevation_tex() -> ImageTexture:
	_sync_gen()
	if _elev_tex == null or _elev_gen != Geo.gen:
		var img := Image.create_from_data(GeoFields.fine_width(), GeoFields.fine_height(), false, Image.FORMAT_RF,
			GeoFields.fine().to_byte_array())
		img.convert(Image.FORMAT_RH)
		_elev_tex = ImageTexture.create_from_image(img)
		_elev_gen = Geo.gen
	return _elev_tex


## The wave clock (SeaWaves.t, also the shader's `wave_t`): the sea only moves on "high".
func _process(delta: float) -> void:
	if _stage == 1:
		_stage = 2
		_heavy_frame = Engine.get_process_frames()
		if _edges != null:
			_edges.queue_redraw()
	elif _stage == 2:
		_stage = 0
		_heavy_frame = Engine.get_process_frames()
		if _coast_node != null:
			_coast_node.queue_redraw()
		_refresh_beach()
	if _water != null and _water_hi():
		SeaWaves.t += delta
		(_water.material as ShaderMaterial).set_shader_parameter("wave_t", SeaWaves.t)


## Water quality (saved): high = waves, surf foam and currents, low = depth tint and contour lines.
## Graphics Low (game/quality.gd) forces the still sea; trees and speckles are
## skipped when zoomed out beyond LOW_TREE_ZOOM (the relief texture stays).
const LOW_TREE_ZOOM := 0.9
static func _water_hi() -> bool:
	return water_high and not Quality.is_low()


static func set_water_high(on: bool, save := true) -> void:
	water_high = on
	if save:
		var cf := ConfigFile.new()
		cf.load(SETTINGS)
		cf.set_value("map", "water", "high" if on else "low")
		cf.save(SETTINGS)
	if instance != null and is_instance_valid(instance):
		var w: Node2D = instance.get("_water")
		if w != null:
			(w.material as ShaderMaterial).set_shader_parameter("hi", 1.0 if _water_hi() else 0.0)


static func load_view_pref() -> void:
	if _pref_loaded:
		return
	_pref_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		terrain_view = int(cf.get_value("map", "terrain", 1)) != 0
		water_high = str(cf.get_value("map", "water", "high")) != "low"
		var sp := str(cf.get_value("map", "style", "auto"))
		style_pref = sp if sp == "table" or sp == "relief" else "auto"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map-view="):
			terrain_view = a.substr(11) != "political"
		elif a.begins_with("--map-water="):
			water_high = a.substr(12) != "low"
		elif a.begins_with("--map-style="):
			var sv: String = a.substr(12)
			style_pref = sv if sv == "table" or sv == "relief" else "auto"


## Switch the view (saved) and redraw the map.
## True when the map-table style is in force (the pack's default under "auto").
static func table_on() -> bool:
	load_view_pref()
	if style_pref == "auto":
		return CData.pack == "west"
	return style_pref == "table"


static func set_style(v: String, save := true) -> void:
	style_pref = v if v == "table" or v == "relief" else "auto"
	if save:
		var cf := ConfigFile.new()
		cf.load(SETTINGS)
		cf.set_value("map", "style", style_pref)
		cf.save(SETTINGS)
	if instance != null and is_instance_valid(instance):
		instance.call("_sync_style")


static func set_terrain_view(on: bool, save := true) -> void:
	terrain_view = on
	if save:
		var cf := ConfigFile.new()
		cf.load(SETTINGS)
		cf.set_value("map", "terrain", 1 if on else 0)
		cf.save(SETTINGS)
	if instance != null and is_instance_valid(instance):
		instance.queue_redraw()


func set_reach(rt: PackedInt32Array) -> void:
	if rt == _reach_rt and (not rt.is_empty() or reach_loops.is_empty()):
		return   # (the same reach: its outlines and fill are kept)
	_reach_rt = rt
	reach_rects = []
	reach_loops = []
	next_loops = []
	reach_fill = []
	_next_dashes = []
	_next_dashes_lw = -1.0
	if rt.size() != CGrid.count():
		_redraw_reach()
		return
	var px := float(CGrid.cell_px())
	var now := PackedByteArray()
	var two := PackedByteArray()
	now.resize(rt.size())
	two.resize(rt.size())
	for c in rt.size():
		if rt[c] == 0:
			now[c] = 1
			reach_rects.append(Rect2(CGrid.cx(c) * px, CGrid.cy(c) * px, px, px))
		if rt[c] >= 0:
			two[c] = 1
	reach_loops = outline(now)
	next_loops = outline(two)
	reach_fill = []
	var ok := true
	for lp in reach_loops:
		if _area(lp) > 0.0:
			if Geometry2D.triangulate_polygon(lp).is_empty():
				ok = false
			else:
				reach_fill.append(lp)
	if ok:
		reach_rects = []  # the smooth shapes fill it
	_redraw_reach()


## Only the reach node is drawn again (before the first draw of the map: the whole map).
func _redraw_reach() -> void:
	if _reach_node != null:
		_reach_node.queue_redraw()
	else:
		queue_redraw()


## The selected region (outline and tint) changed: only its two nodes are drawn again.
func set_selected_region(r: int) -> void:
	if r == selected_region:
		return
	selected_region = r
	if _sel_node != null:
		_sel_node.queue_redraw()
	if _pulse_node != null:
		_pulse_node.queue_redraw()


## The state changed (a new preview, a resolved turn): the map is drawn again only when an owner changed, the
## only thing of the state it shows (the rest is the overlay's). The first call always draws.
func refresh_state() -> void:
	var own := PackedInt32Array()
	if not state.is_empty():
		own.resize(CData.region_count())
		for r in own.size():
			own[r] = -2 if FogView.never(r) else FogView.shown_owner(state, r)   # (fog: the owner as last seen)
	if own != _owners_drawn or own.is_empty():
		queue_redraw()


## Outlines of a set of cells (1 in `on`): the boundary edges chained into
## loops (map pixels), corners cut twice (Chaikin) so they read smooth.
static func outline(on: PackedByteArray) -> Array:
	var w := CGrid.width()
	var h := CGrid.height()
	var px := float(CGrid.cell_px())
	var nxt := {}  # start vertex key -> Array of end vertex keys
	var vw := w + 1
	for c in on.size():
		if on[c] == 0:
			continue
		var x := c % w
		var y := c / w
		# Clockwise edges (screen y down); only those facing outside.
		if y == 0 or on[c - w] == 0:
			_edge(nxt, y * vw + x, y * vw + x + 1)
		if x == w - 1 or on[c + 1] == 0:
			_edge(nxt, y * vw + x + 1, (y + 1) * vw + x + 1)
		if y == h - 1 or on[c + w] == 0:
			_edge(nxt, (y + 1) * vw + x + 1, (y + 1) * vw + x)
		if x == 0 or on[c - 1] == 0:
			_edge(nxt, (y + 1) * vw + x, y * vw + x)
	var loops: Array = []
	var starts := nxt.keys()
	starts.sort()
	for s0 in starts:
		while nxt.has(s0) and not (nxt[s0] as Array).is_empty():
			var pts := PackedVector2Array()
			var v: int = s0
			for guard in 100000:
				pts.append(Vector2((v % vw) * px, (v / vw) * px))
				var outs: Array = nxt.get(v, [])
				if outs.is_empty():
					break
				var nv: int = outs.pop_back()
				v = nv
				if v == s0:
					break
			if pts.size() >= 3:
				# Edge midpoints turn the cells' staircases into diagonals;
				# then two rounds of corner cutting.
				var mids := PackedVector2Array()
				for i in pts.size():
					mids.append((pts[i] + pts[(i + 1) % pts.size()]) * 0.5)
				loops.append(_smooth(_smooth(mids)))
	return loops


static func _edge(nxt: Dictionary, a: int, b: int) -> void:
	if not nxt.has(a):
		nxt[a] = []
	(nxt[a] as Array).append(b)


## Shoelace sum (positive: an outer outline, negative: a hole).
static func _area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		a += pts[i].cross(pts[(i + 1) % pts.size()])
	return a


## One Chaikin pass over a closed polygon.
static func _smooth(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	return out


## Land colour of region r owned by o: its ground palette, then the owner.
static func region_color(r: int, o: int) -> Color:
	var g := GroundPalette.land_color(int(CData.REGIONS[r]["ground"])).lightened(GROUND_LIFT)
	if o < 0:
		return g.lerp(Color(0.55, 0.55, 0.52), 0.25)
	return g.lerp(CData.faction_color(o), TINT)


## A polygon as a mesh (triangulated once, with uv = point / sz), or null.
static func _poly_mesh(poly: PackedVector2Array, sz: Vector2) -> ArrayMesh:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return null
	var uv := PackedVector2Array()
	uv.resize(poly.size())
	for i in poly.size():
		uv[i] = poly[i] / sz
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = poly
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## The land and island polygons as meshes, uv over the grid's size sz.
static func land_meshes(sz: Vector2) -> Array:
	_sync_gen()
	if _land_meshes.is_empty() or _land_sz != sz:
		_land_meshes = []
		_land_sz = sz
		for poly in Geo.lands() + Geo.islands():
			var m := _poly_mesh(poly, sz)
			if m != null:
				_land_meshes.append(m)
				continue
			if CData.pack != "west":
				continue   # (Rome's one tiny failing islet stays as it was: that look is frozen)
			# A coastline that crosses itself does not triangulate (the West
			# mainland): clean it first and mesh each outer piece (lakes stay land).
			for part in Geometry2D.merge_polygons(poly, PackedVector2Array()):
				if Geometry2D.is_polygon_clockwise(part):
					continue
				var pm := _poly_mesh(part, sz)
				if pm != null:
					_land_meshes.append(pm)
	return _land_meshes


## Fill region r's territory with col (cached meshes: the territory polygons
## follow the fine coast and are too big to triangulate at every redraw).
func _fill_cell(r: int, col: Color) -> void:
	for m in cell_meshes(r):
		draw_mesh(m, null, Transform2D.IDENTITY, col)


const INDEP_EDGE := Color(0.62, 0.62, 0.58, 0.95)
static var _indep_cache := {}
static var _indep_gen := -1


## Dash segments (point pairs, world units) along the outline of region r.
static func _indep_dashes(r: int) -> Array:
	_sync_gen()
	if _indep_gen != Geo.gen:
		_indep_cache = {}
		_indep_gen = Geo.gen
	if _indep_cache.has(r):
		return _indep_cache[r]
	var out: Array = []
	for piece in Geo.cell(r):
		var segs := PackedVector2Array()
		var on := true
		var left := 9.0
		var n: int = piece.size()
		for i in n:
			var a: Vector2 = piece[i]
			var b: Vector2 = piece[(i + 1) % n]
			var seg_len := a.distance_to(b)
			var t := 0.0
			while t < seg_len:
				var step := minf(left, seg_len - t)
				if on:
					segs.append(a.lerp(b, t / seg_len))
					segs.append(a.lerp(b, (t + step) / seg_len))
				t += step
				left -= step
				if left <= 0.0001:
					on = not on
					left = 9.0 if on else 6.0
		out.append(segs)
	_indep_cache[r] = out
	return out


static func cell_meshes(r: int) -> Array:
	_sync_gen()
	if not _cell_meshes.has(r):
		var ms: Array = []
		for piece in Geo.cell(r):
			var m := _poly_mesh(piece, Vector2.ONE)
			if m != null:
				ms.append(m)
		_cell_meshes[r] = ms
	return _cell_meshes[r]


static var last_draw_ms := 0.0   # the last _draw's cost (ms), for the frame benches


func _draw() -> void:
	var t_draw := Time.get_ticks_usec()
	_draw_all()
	ZProf.add("map_view_draw", t_draw)
	last_draw_ms = float(Time.get_ticks_usec() - t_draw) / 1000.0


func _draw_all() -> void:
	var lw := 1.0 / maxf(zoom, 0.05)
	var land_view := terrain_view and grid and not state.is_empty()
	if land_view:
		_terrain_geometry()
	var tbl := land_view and table_on()
	if _table != null:
		if _table.visible != tbl:
			_table.visible = tbl
			if tbl:
				_table.queue_redraw()
	# (The sea is the water node behind this one.)
	var lsz := Vector2(CGrid.width(), CGrid.height()) * float(CGrid.cell_px())
	var lmeshes := land_meshes(lsz)
	if not tbl:
		for m in lmeshes:
			draw_mesh(m, null, Transform2D.IDENTITY, LAND)
	if state.is_empty():
		return
	# Territories.
	# Each region's land is its ground palette (the colour of its battle
	# maps: arid, dry, green, rocky), tinted by its owner.
	if land_view:
		# Terrain view: the ground texture over the land, the owner a
		# translucent tint over it.
		if not tbl:
			for m in lmeshes:
				draw_mesh(m, Landscape.ground_tex)
		for r in CData.region_count():
			var o := FogView.shown_owner(state, r)
			if o >= 0:
				var tc := CData.faction_color(o)
				tc.a = TABLE_TINT if tbl else TERRAIN_TINT
				_fill_cell(r, tc)
		# Rivers: a faint green and a pale bank under the blue line.
		for ln in _river_lines:
			draw_polyline(ln, COL_BANK_GREEN, BANK_GREEN_W * lw, true)
			draw_polyline(ln, Landscape.COL_BANK, (RIVER_W + BANK_W) * lw, true)
	else:
		for r in CData.region_count():
			var o := FogView.shown_owner(state, r)
			var col := region_color(r, o)
			_fill_cell(r, col)
	if grid:
		_terrain_geometry()
		var rtex: Texture2D = Landscape.relief_tex if land_view else _shade_tex
		if rtex != null and not tbl:
			for m in lmeshes:
				draw_mesh(m, rtex)
		if land_view:
			if zoom >= LOW_TREE_ZOOM or not Quality.is_low():
				draw_mesh(Landscape.mesh, null)
		else:
			draw_hills(self, _hill_segs[0], 0, lw)
			draw_hills(self, _hill_segs[1], 1, lw)
	# (the reach is the first child, the selected region's outline a child after the edges: both drawn with the map)
	_owners_drawn = PackedInt32Array()
	if not state.is_empty():
		_owners_drawn.resize(CData.region_count())
		for r in _owners_drawn.size():
			_owners_drawn[r] = -2 if FogView.never(r) else FogView.shown_owner(state, r)
	if _reach_node != null:
		_reach_node.queue_redraw()
	if _sel_node != null:
		_sel_node.queue_redraw()
	# (the owner edges, borders and target outlines, then the coast, roads and rivers are children drawn after this one:
	# their redraws are staged over the next frames, see _process)
	_tbl = tbl
	_stage = 1
	if _pulse_node != null:
		_pulse_node.queue_redraw()


## The destinations of the selected army, blocked cells and the selected region: tints that pulse, so a child node
## redrawn every frame while there are any (the rest of the map is not).
func _draw_pulse() -> void:
	var a := 0.25 + 0.15 * sin(pulse * 4.0)
	for r in targets:
		var tt := int(target_turns.get(r, 0))
		if tt >= 2:
			continue
		var hc := target_fill(attack_targets.has(r), tt, a)
		for m in cell_meshes(r):
			_pulse_node.draw_mesh(m, null, Transform2D.IDENTITY, hc)
	for r in blocked_targets:
		for m in cell_meshes(r):
			_pulse_node.draw_mesh(m, null, Transform2D.IDENTITY, COL_BLOCKED)
	if selected_region >= 0:
		for m in cell_meshes(selected_region):
			_pulse_node.draw_mesh(m, null, Transform2D.IDENTITY, Color(1, 1, 0.8, 0.22))


## True while the staged redraw of the edges and coast is still to come (the screen then lets the overlay slide).
func heavy_pending() -> bool:
	return _stage != 0 or _heavy_frame == Engine.get_process_frames()


## Redraw only the pulsing tints (the screen calls it every frame while a destination is shown).
func redraw_pulse() -> void:
	if _pulse_node != null:
		_pulse_node.queue_redraw()


## The territory edges and outlines (child node `_edges`): the owner's band, the borders, the targets' outlines.
func _draw_edges() -> void:
	if (state.get("regions", []) as Array).size() != CData.region_count():
		return   # (no campaign loaded, or the state of another pack: nothing to outline)
	var t0 := ZProf.begin()
	var lw := 1.0 / maxf(zoom, 0.05)
	var tbl := _tbl
	# Owner edge: a band of the owner's colour inside each territory, so the
	# owner reads at once whatever the ground.
	for r in CData.region_count():
		if FogView.never(r):
			continue   # (fog: no border round land never seen)
		var o := FogView.shown_owner(state, r)
		if o < 0:
			if tbl:
				# Independent land: no wash, a neutral grey dashed border.
				for dsh in _indep_dashes(r):
					_edges.draw_multiline(dsh, Color(0.12, 0.08, 0.05, 0.5), (TABLE_EDGE_W + 1.0) * lw, true)
					_edges.draw_multiline(dsh, INDEP_EDGE, TABLE_EDGE_W * 0.8 * lw, true)
			continue
		var ec := CData.faction_color(o)
		ec.a = OWNER_EDGE_A
		for piece in Geo.cell(r):
			var closed: PackedVector2Array = piece.duplicate()
			closed.append(piece[0])
			if tbl:
				_edges.draw_polyline(closed, TABLE_BORDER, (TABLE_EDGE_W + 1.6) * lw, true)
			_edges.draw_polyline(closed, ec, (TABLE_EDGE_W if tbl else OWNER_EDGE_W) * lw, true)
	# Borders between territories (darker where owners differ is implied by
	# the tint; one thin line everywhere keeps it light).
	for r in CData.region_count():
		if FogView.never(r):
			continue
		for piece in Geo.cell(r):
			var closed: PackedVector2Array = piece.duplicate()
			closed.append(piece[0])
			_edges.draw_polyline(closed, Color(0.1, 0.1, 0.08, 0.7 if tbl else 0.45), (1.8 if tbl else 1.2) * lw, true)
	for r in targets:
		var te := target_edge(attack_targets.has(r), int(target_turns.get(r, 0)))
		for piece in Geo.cell(r):
			var closed: PackedVector2Array = piece.duplicate()
			closed.append(piece[0])
			_edges.draw_polyline(closed, te[0], float(te[1]) * lw, true)
	for r in blocked_targets:
		for piece in Geo.cell(r):
			var closed: PackedVector2Array = piece.duplicate()
			closed.append(piece[0])
			_edges.draw_polyline(closed, COL_BLOCKED_EDGE, 2.0 * lw, true)
		# A small cross on the settlement: "not this turn".
		draw_blocked_cross(_edges, Geo.site(r), lw)
	ZProf.add("mv_edges", t0)


## The selected region's outline (its own node over the edges: selecting a region does not redraw them).
func _draw_sel() -> void:
	if selected_region < 0 or state.is_empty():
		return
	var lw := 1.0 / maxf(zoom, 0.05)
	for piece in Geo.cell(selected_region):
		var closed: PackedVector2Array = piece.duplicate()
		closed.append(piece[0])
		_sel_node.draw_polyline(closed, Color(1, 1, 0.75, 1.0), 3.0 * lw, true)


func _draw_reach_node() -> void:
	if grid and not state.is_empty():
		_draw_reach(_reach_node, 1.0 / maxf(zoom, 0.05))


## The coastline, roads, rivers, crossings and sea lanes (child node `_coast_node`).
func _draw_coast() -> void:
	var t0 := ZProf.begin()
	_draw_coast_body()
	ZProf.add("mv_coast", t0)


func _draw_coast_body() -> void:
	var lw := 1.0 / maxf(zoom, 0.05)
	# Coastline.
	for poly in Geo.lands() + Geo.islands():
		var closed: PackedVector2Array = poly.duplicate()
		closed.append(poly[0])
		_coast_node.draw_polyline(closed, COAST, 1.6 * lw, true)
	# Land routes (dashed) and sea lanes (dotted, light blue).
	if grid:
		# Roads, rivers and the crossings over them.
		if table_on():
			for ln in _track_lines:
				draw_track(_coast_node, ln, lw)
		else:
			for ln in _road_lines:
				draw_road(_coast_node, ln, lw)
		for ln in _river_lines:
			draw_river(_coast_node, ln, lw)
		for cm in _cross_marks:
			if int(cm[2]) == 0:
				draw_ford(_coast_node, cm[0], cm[1], lw)
			else:
				draw_bridge(_coast_node, cm[0], cm[1], lw)
		# Sea lanes (every pack, both styles): curves through the sea between the ports. They are trade routes
		# in a pack with ships, where armies cross on fleets, and the armies' links in one without.
		_draw_lanes(_coast_node, lw)
		return
	for pair in CData.ROUTES:
		var p0 := Geo.site(CData.region_index(pair[0]))
		var p1 := Geo.site(CData.region_index(pair[1]))
		draw_route(_coast_node, p0, p1, lw)
	for pair in CData.SEA_LANES:
		var p0 := Geo.site(CData.region_index(pair[0]))
		var p1 := Geo.site(CData.region_index(pair[1]))
		draw_sea_lane(_coast_node, p0, p1, lw)


## The sea lanes as dashed curves (dashes cut for this line scale and style, cached).
static func _draw_lanes(ci: CanvasItem, lw: float) -> void:
	var tbl := table_on()
	var key := "%d:%.4f:%s" % [_gen, lw, "t" if tbl else "r"]
	if key != _lane_dash_key:
		_lane_dash_key = key
		_lane_dashes = []
		for ln in _lane_lines:
			_lane_dashes.append(dash_polyline(ln, (LANE_TABLE_DASH if tbl else LANE_DASH) * lw, (LANE_TABLE_GAP if tbl else LANE_GAP) * lw))
	for segs in _lane_dashes:
		if (segs as PackedVector2Array).size() >= 2:
			if tbl:
				ci.draw_multiline(segs, Color(0.05, 0.12, 0.2, 0.22), (LANE_TABLE_W + 1.6) * lw, true)
				ci.draw_multiline(segs, COL_LANE_TABLE, LANE_TABLE_W * lw, true)
			else:
				ci.draw_multiline(segs, COL_SEA_LANE, LANE_W * lw, true)


# ----------------------------------------------------------- beaches and cliffs ---

## True when cell c (land or sea) is open sea: where fleets sail (CFleet.is_sea; a pack without ships: any sea).
static func _open_sea(c: int) -> bool:
	if CData.ships_on():
		return CFleet.is_sea(c)
	return CGrid.region(c) == -1


## What kind of coast land cell c is: 1 a landing coast (a passable cell with open sea in one of its 8 neighbours:
## where CFleet.land_ok can hold, the geometric part of the rule), 2 other coast (water beside it no fleet sails, or
## unclaimed land), 0 not coast.
static func coast_class(c: int) -> int:
	if c < 0 or CGrid.region(c) == -1:
		return 0
	if _coast_class.size() != CGrid.count():
		_coast_class.resize(CGrid.count())
		_coast_class.fill(255)
	if _coast_class[c] != 255:
		return _coast_class[c]
	var k := 0
	for d in 8:
		var j := CGrid.at(CGrid.cx(c) + CGrid.DX[d], CGrid.cy(c) + CGrid.DY[d])
		if j < 0 or CGrid.region(j) != -1:
			continue
		if _open_sea(j) and CGrid.passable(c):
			k = 1
			break
		k = 2
	_coast_class[c] = k
	return k


## The land cell a coastline sample belongs to: the first land cell inland of it, and its coast class (cell, class).
static func _sample_cell(p: Vector2, n: Vector2) -> Array:
	var px := float(CGrid.cell_px())
	var best := -1
	var cls := 0
	for dist in [3.0, 9.0]:
		var q: Vector2 = p + n * dist
		var c := CGrid.at(int(floor(q.x / px)), int(floor(q.y / px)))
		if c < 0 or CGrid.region(c) == -1:
			continue
		var k := coast_class(c)
		if k > 0:
			return [c, k]
		if best < 0:
			best = c
	if best < 0:
		return [-1, 0]
	# (the polygon and the raster differ by a fraction of a cell: take a coast cell beside it)
	for d in 8:
		var j := CGrid.at(CGrid.cx(best) + CGrid.DX[d], CGrid.cy(best) + CGrid.DY[d])
		var k2 := coast_class(j)
		if k2 == 1:
			return [j, 1]
		if k2 == 2:
			cls = 2
			best = j
	return [best, cls] if cls > 0 else [-1, 0]


## Samples every land polygon's outline every BEACH_STEP and groups the runs of one kind (once, with the geometry).
static func _build_coast_dressing() -> void:
	var t0 := Time.get_ticks_usec()
	_coast_runs = []
	_coast_class = PackedByteArray()
	_coast_drawn = PackedByteArray()
	_coast_drawn.resize(CGrid.count())
	_coast_unseen = PackedInt32Array()
	_beach_cell_pts = {}
	for poly in Geo.lands() + Geo.islands():
		var pl: PackedVector2Array = poly
		var m := pl.size()
		if m < 3:
			continue
		var cur_kind := 0
		var pts := PackedVector2Array()
		var nrm := PackedVector2Array()
		var carry := 0.0
		for i in m:
			var a := pl[i]
			var b := pl[(i + 1) % m]
			var seg := b - a
			var ln := seg.length()
			if ln < 0.001:
				continue
			var t := seg / ln
			var n0 := Vector2(-t.y, t.x)
			var pos := carry
			while pos < ln:
				var p := a + t * pos
				# the land side: the normal or its opposite, whichever has land just inland
				var sc := _sample_cell(p, n0)
				var nn := n0
				if int(sc[0]) < 0:
					sc = _sample_cell(p, -n0)
					nn = -n0
				var kind: int = int(sc[1])
				if kind != cur_kind and not pts.is_empty():
					_coast_runs.append([cur_kind, pts, nrm])
					pts = PackedVector2Array()
					nrm = PackedVector2Array()
				cur_kind = kind
				if kind > 0:
					pts.append(p)
					nrm.append(nn)
					var c: int = int(sc[0])
					_coast_drawn[c] = _coast_drawn[c] | kind
					if kind == 1:
						var bp: PackedVector2Array = _beach_cell_pts.get(c, PackedVector2Array())
						bp.append(p)   # (a packed array is a value: put it back)
						_beach_cell_pts[c] = bp
				pos += BEACH_STEP
			carry = pos - ln
		if not pts.is_empty():
			_coast_runs.append([cur_kind, pts, nrm])
	# A coast cell the outline did not cross (a corner, a spit): the three coastline samples of the same kind nearest
	# its centre (any kind when none) are its strip, so the dressing stays on the coastline.
	var px := float(CGrid.cell_px())
	var w := CGrid.width()
	var buckets := {}   # cell -> Array of [run, index] of the samples inside it
	for ri in _coast_runs.size():
		var rp: PackedVector2Array = _coast_runs[ri][1]
		for i in rp.size():
			var bc := CGrid.at(int(floor(rp[i].x / px)), int(floor(rp[i].y / px)))
			if not buckets.has(bc):
				buckets[bc] = []
			(buckets[bc] as Array).append([ri, i])
	for c in CGrid.count():
		var k := coast_class(c)
		if k == 0 or (_coast_drawn[c] & k) != 0:
			continue
		var ctr := Vector2((c % w + 0.5) * px, (c / w + 0.5) * px)
		var best: Array = []
		var bd := INF
		for want_kind in [k, 0]:
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var bc2 := CGrid.at(CGrid.cx(c) + dx, CGrid.cy(c) + dy)
					for e in buckets.get(bc2, []):
						var run: Array = _coast_runs[int(e[0])]
						if want_kind != 0 and int(run[0]) != want_kind:
							continue
						var d := ctr.distance_squared_to((run[1] as PackedVector2Array)[int(e[1])])
						if d < bd:
							bd = d
							best = e
			if not best.is_empty():
				break
		if best.is_empty():
			# (no outline within two cells: cells the grid gives a region but the map draws as sea; nothing to dress)
			_coast_unseen.append(c)
			continue
		var src: Array = _coast_runs[int(best[0])]
		var sp: PackedVector2Array = src[1]
		var sn: PackedVector2Array = src[2]
		var fpts := PackedVector2Array()
		var fn := PackedVector2Array()
		for i in range(maxi(0, int(best[1]) - 1), mini(sp.size(), int(best[1]) + 2)):
			fpts.append(sp[i])
			fn.append(sn[i])
		_coast_runs.append([k, fpts, fn])
		_coast_drawn[c] = _coast_drawn[c] | k
		if k == 1:
			_beach_cell_pts[c] = fpts
	var cells: Array = _beach_cell_pts.keys()
	cells.sort()
	_beach_cells = PackedInt32Array(cells)
	_coast_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Every cell with a beach, ascending (the cells a landing can aim for).
static func beach_cells() -> PackedInt32Array:
	return _beach_cells


## The coast points (map px) of cell c's beach, empty when it has none.
static func beach_points(c: int) -> PackedVector2Array:
	return _beach_cell_pts.get(c, PackedVector2Array())


## Counts for the tests: the cells with a drawn beach segment, with a cliff segment, and the runs.
static func coast_counts() -> Array:
	var nb := 0
	var nc := 0
	for v in _coast_drawn:
		if (v & 1) != 0:
			nb += 1
		if (v & 2) != 0:
			nc += 1
	return [nb, nc, _coast_runs.size(), _coast_ms]


## Coast cells the grid knows and the map does not draw as land (so they carry no dressing).
static func coast_unseen() -> PackedInt32Array:
	return _coast_unseen


## True when a segment of kind (1 beach, 2 cliff) was built for cell c.
static func coast_drawn(c: int, kind: int) -> bool:
	return c >= 0 and c < _coast_drawn.size() and (_coast_drawn[c] & kind) != 0


## The runs offset for this zoom band (the strip sits inland of the coastline by a fixed screen distance).
static func _coast_geometry(lw: float, tbl: bool) -> Array:
	var band := int(round(log(maxf(lw, 0.001)) / log(BEACH_BAND)))
	var key := "%d:%d:%s" % [_gen, band, "t" if tbl else "r"]
	if key == _coast_geo_key:
		return _coast_geo
	_coast_geo_key = key
	_coast_geo = []
	var lq := pow(BEACH_BAND, float(band))
	var stride := maxi(1, int(ceil(CLIFF_TICK_GAP * lq / BEACH_STEP)))
	for run in _coast_runs:
		var pts: PackedVector2Array = run[1]
		var nrm0: PackedVector2Array = run[2]
		var n := pts.size()
		var nrm := PackedVector2Array()   # (the normals averaged over their neighbours: no kinks at the polygon's corners)
		nrm.resize(n)
		for i in n:
			var sum := nrm0[i] * 2.0
			if i > 0:
				sum += nrm0[i - 1]
			if i < n - 1:
				sum += nrm0[i + 1]
			nrm[i] = sum.normalized() if sum.length() > 0.01 else nrm0[i]
		if int(run[0]) == 1:
			var line := PackedVector2Array()
			var foam := PackedVector2Array()
			line.resize(n)
			foam.resize(n)
			var off := (3.0 if tbl else 1.7) * lq
			for i in n:
				line[i] = pts[i] + nrm[i] * off
				foam[i] = pts[i] - nrm[i] * (1.2 * lq)
			_coast_geo.append([1, line, foam, PackedVector2Array()])
		else:
			var line2 := PackedVector2Array()
			line2.resize(n)
			var ticks := PackedVector2Array()
			for i in n:
				line2[i] = pts[i] + nrm[i] * (0.7 * lq)
				if tbl and i % stride == 0:
					ticks.append(pts[i] + nrm[i] * (0.7 * lq))
					ticks.append(pts[i] + nrm[i] * ((0.7 + CLIFF_TICK_LEN) * lq))
			_coast_geo.append([2, line2, PackedVector2Array(), ticks])
	return _coast_geo


## The zoom band of line scale lw (BEACH_BAND steps), with the style and the pack folded in.
static func _beach_band_of(lw: float) -> int:
	return int(round(log(maxf(lw, 0.001)) / log(BEACH_BAND))) * 4 + (1 if table_on() else 0) + _gen * 100000


## Draw the beach node again when the zoom band (or the style, the pack) changed since it was drawn.
func _refresh_beach() -> void:
	if _beach_node == null:
		return
	if not grid:
		return
	var band := _beach_band_of(1.0 / maxf(zoom, 0.05))
	if band != _beach_band:
		_beach_band = band
		_beach_node.queue_redraw()


func _draw_beach_node() -> void:
	if not grid:
		return
	var t0 := ZProf.begin()
	_draw_coast_dressing(_beach_node, 1.0 / maxf(zoom, 0.05))
	ZProf.add("mv_beach", t0)


## Beach and cliff strips along the coastline, in the table or the relief style, widths for the zoom band of lw.
static func _draw_coast_dressing(ci: CanvasItem, lw: float) -> void:
	var tbl := table_on()
	var lq := pow(BEACH_BAND, float(int(round(log(maxf(lw, 0.001)) / log(BEACH_BAND)))))
	for g in _coast_geometry(lw, tbl):
		var line: PackedVector2Array = g[1]
		if line.size() < 2:
			continue
		if int(g[0]) == 1:
			draw_beach(ci, line, g[2], lq, tbl)
		else:
			draw_cliff(ci, line, g[3], lq, tbl)


## A beach: a sand strip (pale ribbon with a soft edge and a faint foam line on the water side in the table style, a
## thin sand band on the relief).
static func draw_beach(ci: CanvasItem, line: PackedVector2Array, foam: PackedVector2Array, lw: float, tbl: bool) -> void:
	if tbl:
		var c := COL_SAND
		if foam.size() >= 2:
			ci.draw_polyline(foam, Color(COL_FOAM.r, COL_FOAM.g, COL_FOAM.b, 0.5), 1.3 * lw, true)
		ci.draw_polyline(line, Color(c.r, c.g, c.b, 0.25), 7.0 * lw, true)
		ci.draw_polyline(line, Color(c.r, c.g, c.b, 0.5), 5.6 * lw, true)
		ci.draw_polyline(line, Color(c.r, c.g, c.b, 0.95), 4.0 * lw, true)
	else:
		ci.draw_polyline(line, Color(COL_SAND.r, COL_SAND.g, COL_SAND.b, 0.95), 2.2 * lw, true)


## A cliff: a dark rock line, with short hatch ticks inland in the table style; a darker coast line on the relief.
static func draw_cliff(ci: CanvasItem, line: PackedVector2Array, ticks: PackedVector2Array, lw: float, tbl: bool) -> void:
	if tbl:
		ci.draw_polyline(line, Color(COL_ROCK.r, COL_ROCK.g, COL_ROCK.b, 0.95), 2.6 * lw, true)
		if ticks.size() >= 2:
			ci.draw_multiline(ticks, Color(COL_ROCK.r, COL_ROCK.g, COL_ROCK.b, 0.8), 1.1 * lw, true)
	else:
		ci.draw_polyline(line, Color(COL_ROCK_RELIEF.r, COL_ROCK_RELIEF.g, COL_ROCK_RELIEF.b, 0.97), 2.8 * lw, true)



## The steps of preparing the campaign map for the loading panel:
## [[label, Callable], ...] (each is cheap once done).
static func prepare_steps() -> Array:
	return [["Building the map", geometry_lines],
		["Shading the relief (first time only)" if not Landscape.relief_cached() else "Loading the relief", Landscape.bake_relief],
		["Painting the landscape", _bake_land]]


## The landscape's glyphs (the forest is cleared round the towns in the table style).
static func _bake_land() -> void:
	Landscape.clear_towns = table_on()
	Landscape.models = table_on() and not Quality.is_low()
	Landscape.bake_land()


## The roads, rivers and hills geometry from the grid (once).
static func _terrain_geometry() -> void:
	_sync_gen()
	if not _hill_segs.is_empty():
		return
	Landscape.clear_towns = table_on()
	Landscape.models = table_on() and not Quality.is_low()
	Landscape.bake()
	geometry_lines()


## The map's own geometry without the landscape bake: the territory and land
## meshes, hills, the shade, roads, rivers and crossings (once). The loading
## panel runs it as its own step.
static func geometry_lines() -> void:
	_sync_gen()
	if not _hill_segs.is_empty():
		return
	var gsz := Vector2(CGrid.width(), CGrid.height()) * float(CGrid.cell_px())
	land_meshes(gsz)
	for r in CData.region_count():
		cell_meshes(r)
	var px := float(CGrid.cell_px())
	var hills := PackedVector2Array()
	var ridges := PackedVector2Array()  # (packed arrays are values: one variable each)
	for c in CGrid.count():
		var ov := CGrid.terrain_override(c)
		if ov < 0:
			continue
		var ctr := Vector2((CGrid.cx(c) + 0.5) * px, (CGrid.cy(c) + 0.5) * px)
		if ov == CData.RIDGE:
			ridges.append_array(hill_mark(ctr, px, 1))
		else:
			hills.append_array(hill_mark(ctr, px, 0))
	_hill_segs = [hills, ridges]
	var t0 := Time.get_ticks_usec()
	var elev := PackedFloat32Array()
	elev.resize(CGrid.count())
	for c in CGrid.count():
		var ov2 := CGrid.terrain_override(c)
		elev[c] = 2.0 if ov2 == CData.RIDGE else (1.0 if ov2 >= 0 else 0.0)
	_shade_tex = ImageTexture.create_from_image(shade_image(elev, CGrid.width(), CGrid.height()))
	_shade_ms = (Time.get_ticks_usec() - t0) / 1000.0
	var w := CGrid.width()
	for ri in Geo.ROADS.size():
		var cells := Geo.line_cells(Geo.road_line(ri), px, w, CGrid.height())
		var pts := PackedVector2Array()
		for k in cells.size():
			var c := cells[k]
			# Leave out the corner cells a diagonal run steps through (the
			# line reads straighter); keep both ends.
			if k > 0 and k < cells.size() - 1:
				var p0 := cells[k - 1]
				var p1 := cells[k + 1]
				if absi(p0 % w - p1 % w) == 1 and absi(p0 / w - p1 / w) == 1:
					continue
			pts.append(Vector2((c % w + 0.5) * px, (c / w + 0.5) * px))
		if pts.size() >= 2:
			_road_lines.append(_smooth_open(_smooth_open(pts)))
	_track_lines = _cut_at_towns(_road_lines)
	_build_lanes()
	_build_coast_dressing()
	for vi in Geo.RIVERS.size():
		_river_lines.append(Geo.river_line(vi))
	var info := Geo.crossings()
	for id in CGrid.crossing_count():
		var cr := CGrid.crossing(id)
		var a := Vector2((CGrid.cx(int(cr[0])) + 0.5) * px, (CGrid.cy(int(cr[0])) + 0.5) * px)
		var b := Vector2((CGrid.cx(int(cr[1])) + 0.5) * px, (CGrid.cy(int(cr[1])) + 0.5) * px)
		var at := (a + b) * 0.5
		if id < info.size():
			var line: PackedVector2Array = _river_lines[int(info[id]["river"])]
			for k in line.size() - 1:
				var hit: Variant = Geometry2D.segment_intersects_segment(a, b, line[k], line[k + 1])
				if hit != null:
					at = hit
					break
		_cross_marks.append([at, (b - a).normalized(), int(cr[2])])


## The road polylines with a gap round every settlement (the town models stand on the track).
static func _cut_at_towns(lines: Array) -> Array:
	var sites: Array = []
	for r in CData.region_count():
		var lvl := int(CData.REGIONS[r]["level"])
		var rad := TRACK_GAP_CITY if lvl >= CData.CITY else (TRACK_GAP_TOWN if lvl >= CData.TOWN else TRACK_GAP_VILLAGE)
		var c := CGrid.site(r)
		var px := float(CGrid.cell_px())
		sites.append([Vector2((CGrid.cx(c) + 0.5) * px, (CGrid.cy(c) + 0.5) * px), rad * rad])
	var out: Array = []
	for ln in lines:
		var run := PackedVector2Array()
		for p in ln:
			var inside := false
			for st in sites:
				if p.distance_squared_to(st[0]) < float(st[1]):
					inside = true
					break
			if inside:
				if run.size() >= 2:
					out.append(run)
				run = PackedVector2Array()
			else:
				run.append(p)
		if run.size() >= 2:
			out.append(run)
	return out


## The sea lanes (CData.SEA_LANES and SEA_LANE_EXITS) as smoothed curves through the sea (campaign/clanes.gd cells).
static func _build_lanes() -> void:
	_lane_lines = []
	_lane_polys = {}
	for i in CData.SEA_LANES.size():
		var ln := _resample(lane_curve(CLanes.lane(i), i), 4.0)
		if ln.size() >= 2:
			_lane_lines.append(ln)
			_lane_polys[i] = ln
	for i in CData.SEA_LANE_EXITS.size():
		var ln := _resample(lane_curve(CLanes.exit_lane(i), CData.SEA_LANES.size() + i), 4.0)
		if ln.size() >= 2:
			_lane_lines.append(ln)
			_lane_polys[CData.SEA_LANES.size() + i] = ln


## Lane id (CLanes: the port lanes, then the exits) as the smoothed curve drawn on the map, in map px ([] none).
static func lane_poly(id: int) -> PackedVector2Array:
	return _lane_polys.get(id, PackedVector2Array())


static func _cell_pt(c: int) -> Vector2:
	var px := float(CGrid.cell_px())
	return Vector2((CGrid.cx(c) + 0.5) * px, (CGrid.cy(c) + 0.5) * px)


## True when map point p lies in open sea.
static func _sea_at(p: Vector2) -> bool:
	var px := float(CGrid.cell_px())
	return CLanes.is_open(CGrid.at(int(floor(p.x / px)), int(floor(p.y / px))))


## The segment a-b runs through open sea with `clear` map px either side (the
## first and last `skip` px, at a port, are not checked).
static func _sea_line(a: Vector2, b: Vector2, clear: float, skip: float) -> bool:
	var d := b - a
	var dl := d.length()
	if dl < 0.001:
		return true
	var nrm := Vector2(-d.y, d.x) / dl
	var n := maxi(int(dl / 5.0), 1)
	for k in n + 1:
		var p := a + d * (float(k) / n)
		if _near_port(p, skip):
			continue
		if not _sea_at(p) or not _sea_at(p + nrm * clear) or not _sea_at(p - nrm * clear):
			return false
	return true


static var _port_pts: Array = []   # the two port points of the lane being smoothed


static func _near_port(p: Vector2, skip: float) -> bool:
	for q in _port_pts:
		if p.distance_to(q) < skip:
			return true
	return false


static func _chaikin(pts: PackedVector2Array, passes: int) -> PackedVector2Array:
	for _k in passes:
		pts = _smooth_open(pts)
	return pts


## A lane's route cells as a gentle curve (map px) that stays in the sea: the
## cells' centres cut down to the corners that are needed (straight sight lines
## over open water), the corners rounded (Chaikin); a lane that comes out
## straight bends a little to one side (a quadratic arc, the side alternating
## by lane `idx`, flipped if it would meet land). Falls back to the cells' own
## line when the curve would touch land.
static func lane_curve(cells: PackedInt32Array, idx: int) -> PackedVector2Array:
	var raw := PackedVector2Array()
	for c in cells:
		raw.append(_cell_pt(c))
	if raw.size() < 2:
		return raw
	var px := float(CGrid.cell_px())
	var skip := px * 3.0
	_port_pts = [raw[0], raw[raw.size() - 1]]
	var clear := px * 0.45
	# Sight-line simplification.
	var pts := PackedVector2Array([raw[0]])
	var i := 0
	while i < raw.size() - 1:
		# as far as the sight line stays in open water
		# (found by doubling and bisecting: the sight lines are nearly monotonic along a route)
		var last := raw.size() - 1
		var lo := i + 1   # visible (adjacent cells always are)
		var hi := last + 1
		var stepj := 2
		while lo + stepj - 1 < last + 1 and lo + stepj - 1 <= last:
			if _sea_line(raw[i], raw[lo + stepj - 1], clear, skip):
				lo = lo + stepj - 1
				stepj *= 2
			else:
				hi = lo + stepj - 1
				break
		while hi - lo > 1:
			var mid := (lo + hi) / 2
			if _sea_line(raw[i], raw[mid], clear, skip):
				lo = mid
			else:
				hi = mid
		pts.append(raw[lo])
		i = lo
	if pts.size() == 2:
		var a := pts[0]
		var b := pts[1]
		var d := b - a
		var dl := d.length()
		var nrm := Vector2(-d.y, d.x) / maxf(dl, 0.001)
		var side := 1.0 if idx % 2 == 0 else -1.0
		for _try in 2:
			var ctl := (a + b) * 0.5 + nrm * (dl * 0.16 * side)   # (a quadratic's mid is half the control offset: 8 %)
			var curve := PackedVector2Array()
			for k in 25:
				var t := float(k) / 24.0
				curve.append(a * ((1.0 - t) * (1.0 - t)) + ctl * (2.0 * t * (1.0 - t)) + b * (t * t))
			if _curve_ok(curve, clear * 0.5):
				return curve
			side = -side
		if _curve_ok(pts, 0.0):
			return pts
		return _chaikin(raw, 2)
	for passes in [3, 2]:
		var sm := _chaikin(pts, passes)
		if _curve_ok(sm, clear * 0.5):
			return sm
	for passes in [3, 2]:
		var sm := _chaikin(raw, passes)
		if _curve_ok(sm, 0.0):
			return sm
	return raw


## Every point of the curve lies in open sea (but near the ports), `clear` px to either side.
static func _curve_ok(curve: PackedVector2Array, clear: float) -> bool:
	var skip := float(CGrid.cell_px()) * 3.0
	var step := maxi(curve.size() / 120, 1)
	var k := 0
	while k < curve.size():
		var p := curve[k]
		if not _near_port(p, skip):
			if not _sea_at(p):
				return false
			if clear > 0.0 and k > 0 and k < curve.size() - 1:
				var nrm := (curve[k + 1] - curve[k - 1]).orthogonal().normalized() * clear
				if not _sea_at(p + nrm) or not _sea_at(p - nrm):
					return false
		k += step
	# (a coarse sample can step over a one-cell spit: the segments between samples are short, a few px)
	return true


## The polyline's points spaced `step` px apart along it (the ends kept).
static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	if pts.size() < 2:
		return pts
	var out := PackedVector2Array([pts[0]])
	var acc := 0.0
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var seg := a.distance_to(b)
		while acc + seg >= step and seg > 0.0001:
			var t := (step - acc) / seg
			a = a.lerp(b, t)
			out.append(a)
			seg = a.distance_to(b)
			acc = 0.0
		acc += seg
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > 0.01:
		out.append(pts[pts.size() - 1])
	return out


## A polyline cut into dashes: segment pairs for draw_multiline.
static func dash_polyline(pts: PackedVector2Array, dash: float, gap: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var on := true
	var left := dash
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var seg := a.distance_to(b)
		if seg < 0.0001:
			continue
		var dir := (b - a) / seg
		var pos := 0.0
		while pos < seg:
			var take := minf(left, seg - pos)
			if on:
				out.append(a + dir * pos)
				out.append(a + dir * (pos + take))
			pos += take
			left -= take
			if left <= 0.0001:
				on = not on
				left = dash if on else gap
	return out


## Crossing id at map point p (within `rad` map px of its glyph), -1 none.
static func crossing_near(p: Vector2, rad: float) -> int:
	_terrain_geometry()
	var best := -1
	var bd := rad
	for id in _cross_marks.size():
		var d := p.distance_to(_cross_marks[id][0])
		if d <= bd:
			bd = d
			best = id
	return best


## One Chaikin pass over an open polyline (ends kept).
static func _smooth_open(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	for i in pts.size() - 1:
		out.append(pts[i].lerp(pts[i + 1], 0.25))
		out.append(pts[i].lerp(pts[i + 1], 0.75))
	out.append(pts[pts.size() - 1])
	return out


## Relief image of an elevation field (w x h floats): blurred, lit from the
## north-west; transparent on flat ground, dark on south-east slopes, light
## on north-west ones, a faint warm tint with height.
static func shade_image(elev: PackedFloat32Array, w: int, h: int) -> Image:
	var e := elev
	for _pass in 2:
		for horiz in 2:
			var o := PackedFloat32Array()
			o.resize(w * h)
			for y in h:
				for x in w:
					var sum := 0.0
					var n := 0
					for d in range(-SHADE_BLUR, SHADE_BLUR + 1):
						var xx := x + d if horiz == 0 else x
						var yy := y if horiz == 0 else y + d
						if xx >= 0 and yy >= 0 and xx < w and yy < h:
							sum += e[yy * w + xx]
							n += 1
					o[y * w + x] = sum / n
			e = o
	var light := Vector3(-1.0, -1.0, 1.1).normalized()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dx := (e[y * w + mini(x + 1, w - 1)] - e[y * w + maxi(x - 1, 0)]) * 0.5
			var dy := (e[mini(y + 1, h - 1) * w + x] - e[maxi(y - 1, 0) * w + x]) * 0.5
			var nrm := Vector3(-dx * SHADE_SLOPE, -dy * SHADE_SLOPE, 1.0).normalized()
			var sh := clampf((nrm.dot(light) - light.z) * 2.2, -1.0, 1.0)
			var ht := clampf(e[y * w + x], 0.0, 2.0)
			var col := SHADE_LIGHT if sh > 0.0 else SHADE_DARK
			var a := absf(sh) * SHADE_ALPHA
			# warm tint with height: composite under the shade
			var ta := ht * SHADE_HEIGHT_A
			var oa := a + ta * (1.0 - a)
			var rgb := Color(col.r * a + SHADE_TINT.r * ta * (1.0 - a), col.g * a + SHADE_TINT.g * ta * (1.0 - a),
				col.b * a + SHADE_TINT.b * ta * (1.0 - a)) / maxf(oa, 0.001)
			img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, oa))
	return img


static var _sample_tex: ImageTexture = null

## The key's hills row: a hill and a ridge shaded as on the map.
static func draw_shade_sample(ci: CanvasItem, rc: Rect2) -> void:
	if _sample_tex == null:
		var w := 16
		var h := 6
		var el := PackedFloat32Array()
		el.resize(w * h)
		for y in h:
			for x in w:
				el[y * w + x] = (1.0 if x >= 3 and x <= 5 and y >= 1 and y <= 4 else 0.0) \
					+ (2.0 if x >= 10 and x <= 12 and y >= 1 and y <= 4 else 0.0)
		_sample_tex = ImageTexture.create_from_image(shade_image(el, w, h))
	ci.draw_texture_rect(_sample_tex, rc, false)


## Hatch of a hill (kind 0: one chevron) or ridge (1: two) cell of size
## `px` centred on ctr: segment pairs for draw_multiline.
static func hill_mark(ctr: Vector2, px: float, kind: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var hw := px * (0.22 if kind == 0 else 0.26)
	var hh := px * (0.16 if kind == 0 else 0.22)
	var offs: Array = [Vector2(0, px * 0.08)] if kind == 0 else [Vector2(-px * 0.18, px * 0.12), Vector2(px * 0.18, px * 0.12)]
	for o in offs:
		var base: Vector2 = ctr + o
		out.append_array(PackedVector2Array([base + Vector2(-hw, 0), base + Vector2(0, -hh),
			base + Vector2(0, -hh), base + Vector2(hw, 0)]))
	return out


static func draw_hills(ci: CanvasItem, segs: PackedVector2Array, kind: int, lw: float) -> void:
	if segs.size() >= 2:
		ci.draw_multiline(segs, COL_HILL if kind == 0 else COL_RIDGE, HILL_W * lw, true)


static func draw_river(ci: CanvasItem, pts: PackedVector2Array, lw: float) -> void:
	ci.draw_polyline(pts, COL_RIVER, RIVER_W * lw, true)


static func draw_road(ci: CanvasItem, pts: PackedVector2Array, lw: float) -> void:
	if table_on():
		draw_track(ci, pts, lw)
		return
	ci.draw_polyline(pts, COL_ROAD, ROAD_W * lw, true)


## The table style's road: a dirt track, an ochre ribbon with a soft edge.
static func draw_track(ci: CanvasItem, pts: PackedVector2Array, lw: float) -> void:
	var c := COL_TRACK
	ci.draw_polyline(pts, Color(c.r, c.g, c.b, 0.14), TRACK_EDGE_W * lw, true)
	ci.draw_polyline(pts, Color(c.r, c.g, c.b, 0.26), (TRACK_EDGE_W - 1.2) * lw, true)
	ci.draw_polyline(pts, Color(c.r, c.g, c.b, 0.8), TRACK_CORE_W * lw, true)


## A ford: the river broken by three pale stepping stones along the step.
static func draw_ford(ci: CanvasItem, p: Vector2, dir: Vector2, lw: float) -> void:
	ci.draw_circle(p, 5.2 * lw, Color(0.2, 0.15, 0.08, 0.6))
	for k in [-1, 0, 1]:
		ci.draw_circle(p + dir * (3.1 * lw * k), 1.4 * lw, COL_FORD)


## A bridge: a short deck over the river along the step, dark edged.
static func draw_bridge(ci: CanvasItem, p: Vector2, dir: Vector2, lw: float) -> void:
	var half := dir * (6.5 * lw)
	ci.draw_line(p - half, p + half, Color(0.1, 0.07, 0.03, 0.9), 5.4 * lw, true)
	ci.draw_line(p - half, p + half, COL_BRIDGE.lightened(0.3), 3.2 * lw, true)


## A sea lane (dashed, pale) as a polyline through the sea.
static func draw_sea_lane_line(ci: CanvasItem, pts: PackedVector2Array, lw: float) -> void:
	var tbl := table_on()
	var segs := dash_polyline(pts, (LANE_TABLE_DASH if tbl else LANE_DASH) * lw, (LANE_TABLE_GAP if tbl else LANE_GAP) * lw)
	if segs.size() >= 2:
		ci.draw_multiline(segs, COL_LANE_TABLE if tbl else COL_SEA_LANE, (LANE_TABLE_W if tbl else LANE_W) * lw, true)


## A sea lane (versions 1-5: straight, dotted, light blue) between two ports.
static func draw_sea_lane(ci: CanvasItem, p0: Vector2, p1: Vector2, lw: float) -> void:
	ci.draw_dashed_line(p0, p1, COL_SEA_LANE, LANE_W * lw, SEA_LANE_DASH * lw, true)


## Versions 1-5: a land route (dashed, brown) between two settlements.
static func draw_route(ci: CanvasItem, p0: Vector2, p1: Vector2, lw: float) -> void:
	ci.draw_dashed_line(p0, p1, COL_ROUTE, LANE_W * lw, ROUTE_DASH * lw, true)


## Version 6: an outline of this turn's reach (closed polyline).
static func draw_reach_edge(ci: CanvasItem, closed: PackedVector2Array, lw: float) -> void:
	ci.draw_polyline(closed, Color(0, 0, 0, 0.5), 4.5 * lw, true)
	ci.draw_polyline(closed, COL_REACH_EDGE, 2.4 * lw, true)


## Version 6: an outline of next turn's reach: dashed, light over a dark
## shadow (clearly visible on light land, unlike this turn's solid bright
## edge).
static func draw_next_edge(ci: CanvasItem, closed: PackedVector2Array, lw: float) -> void:
	draw_next_dashes(ci, next_dashes(closed, lw), lw)


## The dashes of a closed outline (dash and gap REACH_NEXT_DASH screen px,
## running on round the corners): segment pairs for draw_multiline.
static func next_dashes(closed: PackedVector2Array, lw: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var dash := REACH_NEXT_DASH * lw
	var t := 0.0  # position in the dash + gap period
	for i in closed.size() - 1:
		var a := closed[i]
		var b := closed[i + 1]
		var ln := a.distance_to(b)
		var s := 0.0
		while s < ln:
			var left := maxf((dash - t) if t < dash else (2.0 * dash - t), 0.01)
			var e := minf(s + left, ln)
			if t < dash:
				out.append(a.lerp(b, s / ln))
				out.append(a.lerp(b, e / ln))
			t = fmod(t + (e - s), 2.0 * dash)
			s = e
	return out


static func draw_next_dashes(ci: CanvasItem, segs: PackedVector2Array, lw: float) -> void:
	if segs.size() < 2:
		return
	ci.draw_multiline(segs, Color(0, 0, 0, 0.45), (REACH_NEXT_W + 2.0) * lw, true)
	ci.draw_multiline(segs, COL_REACH_NEXT, REACH_NEXT_W * lw, true)


## Version 5: a destination's fill (turns 0 this turn, 1 next; attack: an
## enemy region) at pulse phase a (0.1 - 0.4).
static func target_fill(attack: bool, turns: int, a: float) -> Color:
	var hc := Color(1, 1, 1, a) if not attack else Color(1.0, 0.35, 0.25, a + 0.1)
	if turns == 1:
		hc.a *= 0.4
	return hc


## Version 5: a destination's outline [colour, width (times lw)].
static func target_edge(attack: bool, turns: int) -> Array:
	var oc := Color(1, 1, 1, 0.9) if not attack else Color(1, 0.5, 0.4, 0.95)
	if turns >= 1:
		oc.a = 0.55 if turns == 1 else 0.3
	return [oc, 2.5 if turns == 0 else 1.6]


## Version 5: a neighbour the army cannot enter: a cross on its settlement.
static func draw_blocked_cross(ci: CanvasItem, c: Vector2, lw: float) -> void:
	var k := 9.0 * lw
	ci.draw_line(c + Vector2(-k, -k), c + Vector2(k, k), Color(0.1, 0.1, 0.1, 0.9), 2.5 * lw, true)
	ci.draw_line(c + Vector2(k, -k), c + Vector2(-k, k), Color(0.1, 0.1, 0.1, 0.9), 2.5 * lw, true)


## Version 6: the selected army's reach (this turn filled, next turn a
## dashed outline).
func _draw_reach(ci: CanvasItem, lw: float) -> void:
	if reach_loops.is_empty():
		return
	if reach_rects.is_empty():
		for lp in reach_fill:
			ci.draw_colored_polygon(lp, COL_REACH)
	for rc in reach_rects:
		ci.draw_rect(rc, COL_REACH)
	if not is_equal_approx(_next_dashes_lw, lw):
		# Map redraws every frame while an army is selected: cut the dashes
		# again only when the zoom changes.
		_next_dashes = []
		_next_dashes_lw = lw
		for lp in next_loops:
			var closed: PackedVector2Array = (lp as PackedVector2Array).duplicate()
			closed.append(lp[0])
			_next_dashes.append(next_dashes(closed, lw))
	for segs in _next_dashes:
		draw_next_dashes(ci, segs, lw)
	for lp in reach_loops:
		var closed2: PackedVector2Array = (lp as PackedVector2Array).duplicate()
		closed2.append(lp[0])
		draw_reach_edge(ci, closed2, lw)
