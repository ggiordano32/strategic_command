extends ColorRect
## The map-table frame over the map, under the interface (view only): the
## shader (table_frame.gdshader) paints parchment beyond the map's edge, an
## ink border, a vignette and the optional tilt-shift. campaign_screen.gd
## calls update_view each frame with the map's screen transform.

const MapView := preload("res://game/campaign/map_view.gd")
const Geo := preload("res://game/campaign/map_geo.gd")
const Quality := preload("res://game/quality.gd")
const SHADER := preload("res://game/campaign/table_frame.gdshader")
## Tilt-shift: "--map-tilt=0|1" overrides; the default is on, off on Low.
static var tilt_default := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	material = m
	color = Color.WHITE
	visible = false


func update_view(xf: Transform2D, vp: Vector2) -> void:
	var on := MapView.table_on() and MapView.terrain_view
	if visible != on:
		visible = on
	if not on:
		return
	var a: Vector2 = xf * Vector2.ZERO
	var b: Vector2 = xf * Geo.SIZE
	var m := material as ShaderMaterial
	m.set_shader_parameter("map_rect", Vector4(a.x, a.y, b.x, b.y))
	m.set_shader_parameter("view_px", vp)
	var tilt := tilt_default and not Quality.is_low()
	for arg in OS.get_cmdline_user_args():
		if str(arg) == "--map-tilt=0":
			tilt = false
		elif str(arg) == "--map-tilt=1":
			tilt = true
	m.set_shader_parameter("tilt", 1.0 if tilt else 0.0)
	m.set_shader_parameter("scale_px", clampf(vp.y / 720.0, 0.6, 2.0))
