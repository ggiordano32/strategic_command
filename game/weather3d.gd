extends Node3D
## The weather pass, the look: the 3D view's half (game/weather.gd, game/weather_layer.gd; docs/design/art_pipeline.md "The weather
## pass, the look"). A child of the 3D view; view only:
## - the precipitation: one MultiMesh of billboard streaks or flakes (game/weather_precip3d.gdshader), a volume that follows the
##   camera's target, density by kind (drizzle .3, rain .62, downpour and storm 1; snow .4, .7, 1), 3,000 rain streaks / 2,200 flakes
##   at most on High and a quarter of that on Graphics Low; one draw, no node per drop;
## - the lamp and the ambient: the kind's energy against the clear day's (the shadows fade as the lamp dims and the ambient rises,
##   the total about the same: the screen's multiply layer does the dimming and the cast), the lamp's colour toward grey;
## - the fog: the environment's depth fog from the kind's visibility (which also reaches the cards, unshaded), refitted every frame
##   to the camera's distance;
## - the lightning: the weather layer's flash value (a few strokes, view-side clock) lifts the lamp's energy and the ambient for a
##   frame or two and cools the lamp's colour, back to the base values when it ends (not on Graphics Low).

const PRECIP_SHADER := preload("res://game/weather_precip3d.gdshader")
const Quality := preload("res://game/quality.gd")
const BoardView := preload("res://game/board_view.gd")

const RAIN_MAX := 5000
const SNOW_MAX := 6000

var view
var spec: Dictionary = {}
var mmi: MultiMeshInstance3D
var mat: ShaderMaterial
var lamp_base := 1.0
var amb_base := 0.42
var lamp_col := Color(1.0, 0.95, 0.86)
var amb_col := Color(0.62, 0.6, 0.66)
var drawn := 0
var flash_seen := 0.0
var lamp_now := 1.0
var _t := 0.0


func setup(p_view, p_spec: Dictionary) -> void:
	view = p_view
	spec = p_spec
	var low := Quality.is_low()
	lamp_base = float(view.LAMP) * float(spec["lamp_k"])
	amb_base = float(view.AMBIENT) * float(spec["amb_k"])
	var kind: String = spec["kind"]
	var grey := 0.0 if kind == "clear" else (0.55 if float(spec["snow"]) > 0.0 or kind == "fog" else 0.7)
	lamp_col = Color(1.0, 0.95, 0.86).lerp(Color(0.8, 0.85, 0.95), grey)
	amb_col = Color(0.62, 0.6, 0.66).lerp(Color(0.66, 0.68, 0.72) if float(spec["snow"]) > 0.0 else Color(0.62, 0.66, 0.74), grey)
	if bool(spec["storm"]):
		lamp_col = Color(0.64, 0.7, 0.92) if float(spec["storm_k"]) > 1.0 else Color(0.72, 0.78, 0.95)
	var rain: float = spec["rain"]
	var snow: float = spec["snow"]
	if rain > 0.0 or snow > 0.0:
		var n := int((RAIN_MAX if rain > 0.0 else SNOW_MAX) * maxf(rain, snow) * (0.25 if low else 1.0))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = view.card_quad()
		mm.instance_count = n
		var buf := PackedFloat32Array()
		buf.resize(n * 12)
		for i in n:
			buf[i * 12] = 1.0
			buf[i * 12 + 5] = 1.0
			buf[i * 12 + 10] = 1.0
		mm.buffer = buf
		mm.custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(3000, 3000, 3000))
		mat = ShaderMaterial.new()
		mat.shader = PRECIP_SHADER
		var is_snow := snow > 0.0
		mat.set_shader_parameter("snow", 1.0 if is_snow else 0.0)
		mat.set_shader_parameter("count", float(n))
		mat.set_shader_parameter("fall", 7.0 if is_snow else 38.0)
		var w := float(spec["wind"])
		mat.set_shader_parameter("wind", Vector2((14.0 if not is_snow else 6.0) * w * (1.25 if float(spec["storm_k"]) > 1.0 else 1.0), 0.3 * w * 10.0))
		mat.set_shader_parameter("col", Color(1.0, 1.0, 1.0, 0.9) if is_snow else Color(0.82, 0.88, 0.98, 0.5))
		mmi = MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.extra_cull_margin = 16384.0
		add_child(mmi)
		drawn = n
	var fog_m: float = spec["fog_m"]
	if fog_m > 0.0:
		var env: Environment = view.env
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		var fc: Color = (spec["veil"] as Color)
		env.fog_light_color = Color(fc.r, fc.g, fc.b)
		env.fog_density = 1.0
		env.fog_depth_curve = 1.0
	_apply_lamp(0.0)


func _apply_lamp(f: float) -> void:
	var lamp: DirectionalLight3D = view.lamp
	var env: Environment = view.env
	lamp_now = lamp_base + f * 2.2 * float(spec["storm_k"])
	lamp.light_energy = lamp_now
	lamp.light_color = lamp_col.lerp(Color(0.85, 0.9, 1.0), f)
	env.ambient_light_energy = amb_base + f * 1.2 * float(spec["storm_k"])
	env.ambient_light_color = amb_col.lerp(Color(0.8, 0.85, 1.0), f)


## Every frame (the 3D view's _process, after the camera is placed).
func update(delta: float) -> void:
	_t += delta
	var layer = view.battle.get("wx_layer") if view.battle != null else null
	flash_seen = layer.flash if layer != null else 0.0
	_apply_lamp(flash_seen)
	var cam: Camera3D = view.cam
	if cam == null:
		return
	# The camera stands `dist` back from its target along its z: recover the ground point under the screen's centre.
	var b := cam.transform.basis
	var cp := cam.transform.origin
	var tdist := (cp.y - 0.0) / maxf(b.z.y, 0.05)
	var tgt := cp - b.z * tdist
	if mat != null:
		var e := deg_to_rad(BoardView.elev_deg)
		var cs: float = view.cam_size
		var span := cs * 1.78
		var depth_m: float = cs / maxf(sin(e), 0.3) * 1.0
		var hh: float = view.ground_hi - view.ground_lo + 46.0
		var bx: float = span * 1.2 + 20.0
		var bz: float = depth_m * 1.2 + 20.0
		mat.set_shader_parameter("centre", tgt)
		mat.set_shader_parameter("box", Vector3(bx, hh, bz))
		mat.set_shader_parameter("y0", view.ground_lo - 2.0)
		mat.set_shader_parameter("t", _t)
		mat.set_shader_parameter("size", cs * ((0.0032 if spec["kind"] == "blizzard" else 0.0025) if float(spec["snow"]) > 0.0 else 0.02))
		mat.set_shader_parameter("cam_r", b.x)
		mat.set_shader_parameter("cam_u", b.y)
	var fog_m: float = spec["fog_m"]
	if fog_m > 0.0:
		var env: Environment = view.env
		var d := cam.transform.origin.distance_to(tgt)
		env.fog_depth_begin = maxf(d - 60.0, 0.0)
		env.fog_depth_end = env.fog_depth_begin + fog_m * 2.0
