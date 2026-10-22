extends Node
## The live overworld behind the title menu: a non-interactive copy of the campaign map's layers (MapView, the
## landscape trees, the town pieces, the minis and the overlay) on a fresh default state of one setting
## (CState.new_campaign, never saved, fog off), seen from a fixed spot (Port Royal from the sea; the Bay of
## Naples) that drifts a few pixels a minute. It lives inside its own SubViewport (the layers use canvas layers),
## is built a step at a time with a frame between so the menu never stalls, and is freed when the menu hides
## (it switches the global content pack; free() puts Rome back). View only.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const Geo := preload("res://game/campaign/map_geo.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const MapOverlay := preload("res://game/campaign/map_overlay.gd")
const MinisLayer := preload("res://game/campaign/minis_layer.gd")
const TownLayer := preload("res://game/campaign/town_layer.gd")
const LandTrees := preload("res://game/campaign/landtrees.gd")
const FogView := preload("res://game/campaign/fog_view.gd")
const Landscape := preload("res://game/campaign/landscape.gd")

signal built(ms: float)

## Per setting: the region the camera looks at, its zoom, and where that spot sits in the window (fractions).
const SCENES := {
	"west": {"region": "port_royal", "zoom": 2.6, "at": Vector2(0.62, 0.40), "shift": Vector2(-10, 10)},
	"rome": {"region": "campania", "zoom": 2.0, "at": Vector2(0.64, 0.44), "shift": Vector2(-70, -25)},
}
const DRIFT_PX := 13.0       # amplitude: with a 4 minute period about 20 px a minute at the fastest
const DRIFT_PERIOD := 240.0

var pack := "west"
var ready_flag := false
var build_ms := 0.0
var steps_ms: Array = []
var map_view: Node2D
var overlay: Node2D
var minis: Node2D
var town_layer: Node2D
var land_trees: Node2D
var world: Node2D
var st: Dictionary = {}
var _vp: Vector2 = Vector2(1280, 720)
var _base := Vector2.ZERO
var _t := 0.0
var _zoom := 1.5
var _canceled := false
var _forced := false
var _steps: Array = []
var _t0 := 0
var _tl := 0


## Build for `p_pack` into this node's tree; vp is the size of the viewport it is in. The work is queued as steps
## that _process runs one a frame (no coroutine: freeing the node in between is then harmless).
func build(p_pack: String, vp: Vector2) -> void:
	pack = p_pack if SCENES.has(p_pack) else "rome"
	_vp = vp
	_t0 = Time.get_ticks_usec()
	_tl = _t0
	_steps.append(["pack", _use_pack])
	for s in MapView.prepare_steps():
		_steps.append([str(s[0]), s[1]])
	_steps.append(["state", _make_state])
	_steps.append(["layers", _make_layers])
	_steps.append(["refresh", _first_refresh])
	for i in 3:
		_steps.append(["frame %d" % i, func(): pass])
	_steps.append(["done", _finish])


func _use_pack() -> void:
	PackView.use_pack(pack)
	# Rome's own map style is the plain relief; the diorama wants the miniatures table (put back in release()).
	if MapView.style_pref == "auto" and pack == "rome":
		_forced = true
		MapView.style_pref = "table"


func _make_state() -> void:
	st = CState.new_campaign("Menu", 7, [0], {"fog": 0}, [], pack)
	FogView.update(st, -1)


func _make_layers() -> void:
	world = Node2D.new()
	add_child(world)
	map_view = MapView.new()
	world.add_child(map_view)
	var ol := CanvasLayer.new()
	ol.layer = 1
	add_child(ol)
	minis = MinisLayer.new()
	ol.add_child(minis)
	overlay = MapOverlay.new()
	minis.overlay = overlay
	land_trees = LandTrees.new()
	world.add_child(land_trees)
	land_trees.overlay = overlay
	town_layer = TownLayer.new()
	world.add_child(town_layer)
	town_layer.overlay = overlay
	MinisLayer.towns = town_layer
	ol.add_child(overlay)
	var sc: Dictionary = SCENES[pack]
	_zoom = float(sc["zoom"])
	_aim()
	_apply_view()
	map_view.state = st
	overlay.state = st
	map_view.grid = true
	overlay.grid = true
	overlay.player = -1


func _first_refresh() -> void:
	map_view.refresh_state()
	map_view.queue_redraw()
	overlay.queue_redraw()


func _finish() -> void:
	build_ms = float(Time.get_ticks_usec() - _t0) / 1000.0
	ready_flag = true
	built.emit(build_ms)


func _aim() -> void:
	var sc: Dictionary = SCENES[pack]
	var site := Geo.site(CData.region_index(str(sc["region"]))) + (sc["shift"] as Vector2)
	_base = _vp * (sc["at"] as Vector2) - site * _zoom


func resize(vp: Vector2) -> void:
	_vp = vp
	if ready_flag:
		_aim()
		_apply_view()


func _apply_view() -> void:
	var drift := Vector2(sin(_t * TAU / DRIFT_PERIOD), 0.35 * sin(_t * TAU / DRIFT_PERIOD * 0.7)) * DRIFT_PX
	var offset := _base - drift
	world.position = offset
	world.scale = Vector2(_zoom, _zoom)
	map_view.zoom = _zoom
	map_view.view_rect = Rect2(-offset / _zoom, _vp / _zoom)
	overlay.zoom = _zoom
	overlay.set_view(Transform2D(0.0, Vector2(_zoom, _zoom), 0.0, offset), map_view.heavy_pending())


func _process(delta: float) -> void:
	if _canceled:
		return
	if not ready_flag:
		if not _steps.is_empty():
			var stp: Array = _steps.pop_front()
			(stp[1] as Callable).call()
			var now := Time.get_ticks_usec()
			steps_ms.append([stp[0], float(now - _tl) / 1000.0])
			_tl = now
		return
	_t += delta
	map_view.pulse += delta
	overlay.pulse += delta
	_apply_view()


## Stop, drop the static references and put Rome back.
func release() -> void:
	_canceled = true
	ready_flag = false
	if MinisLayer.towns == town_layer:
		MinisLayer.towns = null
	if MapView.instance == map_view:
		MapView.instance = null
	if _forced:
		_forced = false
		MapView.style_pref = "auto"
		Landscape._baked = false   # (baked for the table: the campaign bakes it again for its own style)
	PackView.use_pack("rome")
	queue_free()
