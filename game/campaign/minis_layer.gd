extends Node2D
## Painted miniatures of the fleets on the overworld (view only; tools/structures builds the sprites,
## game/minis_atlas.gd lists them): ships at 8 headings bobbing on SeaWaves, a contact shadow and a wake. Sits
## under map_overlay.gd (same canvas layer, added before it) so the names, army banners and fleet pennants draw
## over the models. The towns are not drawn here any more: town_layer.gd assembles them from kit pieces on the
## map itself; this layer only answers the overlay's questions about them (`on_sites`, half width, label lift,
## where fleets in port stand) from the town plans. Quality Low: the small atlas only, no bobbing redraws.
## The overlay asks `on_sites` / `on_ships` (set here each frame) whether to skip its icon or ship hull.

const ZProf := preload("res://game/campaign/zprof.gd")
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
const CStory := preload("res://campaign/cstory.gd")
const CChars := preload("res://campaign/cchars.gd")

static var on_sites := false
static var on_ships := false
static var towns: Node = null   # the town layer (town_layer.gd), set by the campaign screen
static var _label_lift := 0.0
static var _headings := {}   # fleet id -> last heading 0..7

const SITE_MIN_ZOOM := 0.55
const SHIP_MIN_ZOOM := 0.35
const TILE_M := 58.0           # a base tile's width in metres (the sprites' scale)
const SHIP_RANK := ["ship_of_the_line", "galleon", "quinquereme", "quinquereme_p", "frigate", "corbita", "trireme", "brigantine", "sloop", "lembos", "war_canoe"]
## (R2, Rome's navy) The map sprites of the galleys: until they have their own art they stand in as the sail ships of
## about their size (open: oared sprites).
const SHIP_LOOK := {"lembos": "sloop", "trireme": "brigantine", "quinquereme": "frigate", "quinquereme_p": "frigate", "corbita": "galleon"}
const SHIP_K := 1.0

var overlay: Node2D
var _tex := {}   # set name -> [shade, mask material]
var _t_acc := 0.0
var _draw_key: Array = []   # [xform, zoom] the ships were last drawn for (Low's 10 Hz bobbing redraw never skips a frame where this moved)
## Test probe (tests/zoom_sweep.gd --lag): what the last draws put where, and in which frame.
static var probe := false
static var probe_legacy := false   # test only: the old throttle (no redraw for a moved view on Low), to measure the lag it caused
static var probe_rec := {}
var _under: Node2D       # drawn behind the sprites: ship wakes and contact shadows
var _wakes: Array = []   # [position, scale, heading]
var _moored: Array = []  # (Docking) [position, scale, the town's site on screen]: ships lying docked (no wake, no bob, a mooring line)
static var texture_bytes := 0

## The story's characters standing beside their army's banner (tools/hunyuan renders, assets/minis/characters;
## origin_px of each sprite is the ground point, from NAME.json). Drawn by `_figs`, a child without the ships'
## material, redrawn only when the overlay's army positions change.
const FIG_H := 58.0            # the figure's height on screen at marker scale 1 (the banner is 26 px tall)
const FIG_SMALL_MK := 0.6      # below this marker scale (and on Quality Low) the 48 px sprite is used
const FIG_ORIGIN := {   # name -> [big origin, small origin, big height px, small height px] (the sprite's ground point and standing height)
	"captain": [Vector2(46.0, 98.02), Vector2(23.0, 49.01), 96.0, 48.0],
	"rook": [Vector2(47.0, 97.80), Vector2(23.5, 48.90), 96.0, 48.0],
	"mercy": [Vector2(48.5, 97.31), Vector2(24.5, 48.90), 96.0, 48.0],
}
static var _fig_tex := {}      # "name" / "name_small" -> Texture2D
const FIG_TINT := preload("res://game/campaign/fig_tint.gdshader")
const FIG_TINTED := ["captain", "rook"]   # Mercy's red coat is her identity: no faction tint
const FIG_STEP := 0.96         # a further figure of the same banner stands this many figure widths further left ...
const FIG_BACK := 0.25         # ... and this much of its height further up the screen (drawn first, the front one overlaps it)
var _figs: Node2D
var _figs_tint: Node2D         # the coats' faction tint, a multiply pass over the figures (skipped on Quality Low)
var _fig_list: Array = []      # [[army id, sprite name, slot], ...] for the current state
var _fig_epoch := -1
var _fig_key: Array = []
var fig_on := false
var _fig_only := false


func _ready() -> void:
	z_index = 0
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_under = Node2D.new()
	_under.show_behind_parent = true
	_under.draw.connect(_draw_under)
	add_child(_under)
	_figs = Node2D.new()
	_figs.draw.connect(_draw_figs)
	_figs.visible = false
	add_child(_figs)
	_figs_tint = Node2D.new()
	_figs_tint.draw.connect(_draw_figs_tint)
	_figs_tint.visible = false
	var tm := ShaderMaterial.new()
	tm.shader = FIG_TINT
	_figs_tint.material = tm
	add_child(_figs_tint)


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


## True when settlement r's model is too small or too sparse to be a sure tap target at this zoom (under 96 px wide
## or 20 pieces or fewer): the overlay then draws its code marker (owner colour, walls, harbour) over the model too.
static func weak(zoom: float, r: int) -> bool:
	var i := _info(r)
	if i.is_empty():
		return true
	return float(i["half_w"]) * 2.0 * zoom < 96.0 or int(i.get("n", 0)) <= 20


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
	fig_on = tbl and not st.is_empty() and z >= SHIP_MIN_ZOOM and CStory.on(st)
	_figs.visible = fig_on
	_figs_tint.visible = fig_on and not Quality.is_low()
	if fig_on:
		var k := [overlay._epoch, overlay.xform, z, Quality.is_low()]
		if k != _fig_key:
			_fig_key = k
			_figs.queue_redraw()
			_figs_tint.queue_redraw()
	if fig_on and not (s_on or sh_on):
		if not visible or not _fig_only:
			visible = true   # (the figures alone: one redraw clears the ship pass, then nothing more)
			_fig_only = true
			queue_redraw()
		return
	_fig_only = false
	if not (s_on or sh_on):
		if visible:
			visible = false
		return
	visible = true
	_t_acc += delta
	# Low redraws the bobbing at 10 Hz only; a frame where the view moved (pan or zoom) always redraws, so the
	# ships stay put under the finger like the overlay's armies (the screen sets the overlay's view in its own
	# _process, a parent of this layer's canvas layer, so it runs first in the same frame: no one-frame lag)
	var dk := [overlay.xform, z]
	var moved := dk != _draw_key
	_draw_key = dk
	if Quality.is_low() and _t_acc < 0.1 and not (moved and not probe_legacy):
		return
	_t_acc = 0.0
	queue_redraw()


func _draw() -> void:
	var t0 := ZProf.begin()
	_draw_body()
	ZProf.add("minis_draw", t0)


func _draw_body() -> void:
	if overlay == null:
		return
	var st: Dictionary = overlay.state
	if st.is_empty():
		return
	var z: float = overlay.zoom
	var vp := get_viewport_rect().grow(120.0)
	_wakes.clear()
	_moored.clear()
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
	if probe:
		var pp := {}
		for it in items:
			pp[int((it[2] as Dictionary)["id"])] = it[3]
		probe_rec["ships"] = pp
		probe_rec["ships_f"] = Engine.get_process_frames()
		probe_rec["ships_xf"] = overlay.xform
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
	for i in types.size():
		types[i] = SHIP_LOOK.get(str(types[i]), str(types[i]))
	var mp: Vector2 = overlay.cell_point(CFleet.cell(fl))
	var tt: float = SeaWaves.t if SeaWaves.t > 0.0 else float(overlay.pulse)
	var amp := clampf(SeaWaves.amp(mp), 0.25, 1.0)
	var bob := 0.0 if Quality.is_low() else SeaWaves.height(mp, tt) * amp * 1.6 * pxm * 3.0
	var h := _heading(fl)
	var pos := c + Vector2(0, bob)
	var sc := pxm
	var dkr := CFleet.docked(fl)
	if dkr >= 0:
		# (Docking) a ship at the quay: sails furled (nothing in the wind), no wake, no bob, a line to the town.
		pos = c
		_moored.append([c, pxm, overlay.to_screen(overlay.site_point(dkr))])
	else:
		_wakes.append([c, pxm, h])
	if types.size() >= 2:
		var t2: String = types[1]
		_blit(table, shade, "ship_%s__h%d" % [t2, h], pos + Vector2(-9.0, -5.0) * (pxm / 1.3), sc * 0.82, col)
	_blit(table, shade, "ship_%s__h%d" % [types[0], h], pos, sc, col)


## A soft contact shadow (south-east, the light is north-west) and a small wake behind each ship.
func _draw_under() -> void:
	if probe:
		probe_rec["wakes"] = _wakes.duplicate()
		probe_rec["wakes_f"] = Engine.get_process_frames()
	var low := Quality.is_low()
	for mo in _moored:
		var mc: Vector2 = mo[0]
		var mk_: float = mo[1]
		var pts2 := PackedVector2Array()
		for j in 16:
			var t2 := TAU * float(j) / 16.0
			pts2.append(mc + Vector2(4.0, 3.0) * mk_ + Vector2(cos(t2) * 15.0, sin(t2) * 7.5) * mk_)
		_under.draw_colored_polygon(pts2, Color(0.03, 0.10, 0.20, 0.18))
		if not low:
			var to_town: Vector2 = (mo[2] as Vector2) - mc
			if to_town.length() > 1.0:
				var rope := mc + to_town.normalized() * minf(to_town.length(), 16.0 * mk_)
				_under.draw_line(mc + Vector2(0.0, 2.0 * mk_), rope, Color(0.35, 0.26, 0.15, 0.85), maxf(1.0, 1.1 * mk_), true)
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


# ----------------------------------------------------------- characters ---

static func _fig_texture(nm: String, small: bool, suffix := "") -> Texture2D:
	var k := nm + ("_small" if small else "") + suffix
	if not _fig_tex.has(k):
		_fig_tex[k] = load("res://assets/minis/characters/%s.png" % k) as Texture2D
	return _fig_tex[k]


## Which army carries which figure: for the story's lead human's faction the captain, the second human's Rook, the
## faction CHARS["mercy"] marks Mercy (a second slot, further left, when it is the same faction as a captain). The
## army: the one a hero character rides with, else the faction's largest. [[army id, sprite, slot], ...]
static func figure_armies(st: Dictionary) -> Array:
	var out: Array = []
	if not CStory.on(st):
		return out
	var wants: Array = []   # [faction, sprite]
	var caps: Array = CStory.captains(st)
	if caps.size() >= 1:
		wants.append([int(caps[0]), "captain"])
	if caps.size() >= 2:
		wants.append([int(caps[1]), "rook"])
	var sc := CStory.script_of(st)
	var chars: Dictionary = sc.get_script_constant_map().get("CHARS", {}) if sc != null else {}
	if chars.has("mercy") and (chars["mercy"] as Dictionary).has("mark"):
		var mf := CData.faction_index(str(chars["mercy"]["mark"]))
		if mf >= 0:
			wants.append([mf, "mercy"])
	var used := {}
	for w in wants:
		var f: int = w[0]
		var aid := _figure_army(st, f)
		if aid < 0:
			continue
		var slot := int(used.get(f, 0))
		used[f] = slot + 1
		out.append([aid, w[1], slot])
	return out


static func _figure_army(st: Dictionary, f: int) -> int:
	for c in CChars.all(st):
		if int(c["f"]) == f and int(c["army"]) >= 0 and str(c["kind"]).begins_with("hero") and not CState.army(st, int(c["army"])).is_empty():
			return int(c["army"])
	var best := -1
	var bn := 0
	for a in st["armies"]:
		if int(a["f"]) == f and CState.unit_count(a) > bn:
			bn = CState.unit_count(a)
			best = int(a["id"])
	return best


## Where a figure stands: [feet point, scale, sprite origin, small?] or an empty array (out of sight, off screen).
func _fig_place(e: Array, pos: Dictionary, m: float, small: bool, vp: Rect2) -> Array:
	var id: int = e[0]
	if not pos.has(id):
		return []
	var c: Vector2 = pos[id]
	var o: Array = FIG_ORIGIN[e[1]]
	var k := FIG_H * m / float(o[3] if small else o[2])
	var org: Vector2 = o[1] if small else o[0]
	var slot := float(e[2])
	var feet := Vector2(c.x - overlay.ARMY_W * 0.5 * m - FIG_H * m * (0.30 + FIG_STEP * slot), c.y + overlay.ARMY_H * 0.5 * m - FIG_H * m * FIG_BACK * slot)
	if not vp.has_point(feet):
		return []
	return [feet, k, org]


## The figures, the further slots first so the front one overlaps them.
func _fig_order() -> Array:
	var l: Array = _fig_list.duplicate()
	l.sort_custom(func(a, b): return int(a[2]) > int(b[2]))
	return l


func _draw_figs() -> void:
	if overlay == null or not fig_on:
		return
	var st: Dictionary = overlay.state
	if _fig_epoch != overlay._epoch:
		_fig_epoch = overlay._epoch
		_fig_list = figure_armies(st)
	if _fig_list.is_empty():
		return
	var pos: Dictionary = overlay._positions()   # (the fog-filtered banner positions: an army out of sight has none)
	var m: float = overlay.mk()
	var small := Quality.is_low() or m < FIG_SMALL_MK
	var vp := get_viewport_rect().grow(80.0)
	for e in _fig_order():
		var pl := _fig_place(e, pos, m, small, vp)
		var tex := _fig_texture(e[1], small)
		if pl.is_empty() or tex == null:
			continue
		_figs.draw_texture_rect(tex, Rect2((pl[0] as Vector2) - (pl[2] as Vector2) * float(pl[1]), tex.get_size() * float(pl[1])), false)


## The coat toward the faction's colour (fig_tint.gdshader), over the figures of the captain and the partner.
func _draw_figs_tint() -> void:
	if overlay == null or not fig_on or Quality.is_low() or _fig_list.is_empty():
		return
	var st: Dictionary = overlay.state
	var pos: Dictionary = overlay._positions()
	var m: float = overlay.mk()
	var small := m < FIG_SMALL_MK
	var vp := get_viewport_rect().grow(80.0)
	for e in _fig_order():
		if not FIG_TINTED.has(e[1]):
			continue
		var pl := _fig_place(e, pos, m, small, vp)
		var tex := _fig_texture(str(e[1]), small, "_mask")
		if pl.is_empty() or tex == null:
			continue
		var f := int(CState.army(st, int(e[0])).get("f", -1))
		if f < 0:
			continue
		_figs_tint.draw_texture_rect(tex, Rect2((pl[0] as Vector2) - (pl[2] as Vector2) * float(pl[1]), tex.get_size() * float(pl[1])), false, CData.faction_color(f))
