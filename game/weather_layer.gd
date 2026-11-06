extends CanvasLayer
## The weather pass, the look: the screen-space half (game/weather.gd; docs/design/art_pipeline.md "The weather pass, the look"). One
## CanvasLayer under the HUD (added before it, as the diorama lens is), over the battle's world in all three views:
## - grade: a multiplying full-screen rect (the kind's dimming and cold or warm cast; no screen read: a multiply blend);
## - veil: a mixing rect with a vertical gradient, the haze and the fog: in the top and oblique views a distance fade from the zoom
##   and the tilt (the far, top of the screen foggier), in 3D only the flat haze (the environment's fog does the distance);
## - the precipitation in the top and oblique views: one full-screen procedural shader, 3 parallax layers of streaks or flakes (1 on
##   Graphics Low, a quarter of the density), nothing per drop; in 3D the particle volume is game/weather3d.gd;
## - the lightning: view-side only (own RNG from the battle's seed, advanced by frame time, never the sim's), a flash value 0..1 a
##   frame (a flicker of 2-3 strokes) drawn here as an additive rect and read by game/weather3d.gd for the lamp and the ambient.
## Cost: 3 full-screen blended rects (the precipitation only while it rains or snows). View only.

const Quality := preload("res://game/quality.gd")
const BoardView := preload("res://game/board_view.gd")

const MUL_CODE := """
shader_type canvas_item;
render_mode blend_mul;
uniform vec4 mul_col : source_color = vec4(1.0);
void fragment() { COLOR = vec4(mul_col.rgb, 1.0); }
"""
const VEIL_CODE := """
shader_type canvas_item;
uniform vec4 veil_col : source_color = vec4(0.8, 0.82, 0.86, 0.1);
uniform float a_top = 0.1;
uniform float a_bot = 0.1;
uniform float vig = 0.0;
void fragment() {
	float a = mix(a_top, a_bot, UV.y);
	vec2 p = (UV - 0.5) * vec2(1.3, 1.0);
	a = clamp(a + vig * smoothstep(0.45, 1.0, length(p) * 1.5), 0.0, 0.96);
	COLOR = vec4(veil_col.rgb, a);
}
"""
const FLASH_CODE := """
shader_type canvas_item;
render_mode blend_add;
uniform float amount = 0.0;
void fragment() {
	float g = 1.0 - 0.35 * UV.y;   // (the sky end of the screen, the far side, brighter)
	COLOR = vec4(vec3(0.62, 0.7, 0.95) * amount * g, 1.0);
}
"""
## Rain streaks or snow flakes, a screen-space layer with parallax: each layer a grid of cells (cell size in px at 390 px of
## height), a drop or flake per cell by hash, falling with TIME, leaning with the wind; the camera's pan moves the nearer layers more.
const PRECIP_CODE := """
shader_type canvas_item;
uniform float is_snow = 0.0;        // 0 rain, 1 snow
uniform float density = 0.5;        // 0..1
uniform float wind = 0.15;
uniform float unit = 1.0;           // screen px per reference px (viewport height / 390)
uniform vec2 pan = vec2(0.0);       // the camera's world position (px)
uniform int layers = 3;
uniform vec4 col : source_color = vec4(0.82, 0.88, 0.97, 0.5);

float h11(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
vec2 h21(float n) { return vec2(h11(n), h11(n + 17.31)); }

float rain_layer(vec2 p, float cs_x, float cs_y, float speed, float seed, float dens, float wpx) {
	vec2 q = vec2(p.x - p.y * wind, p.y);
	vec2 cell = floor(q / vec2(cs_x, cs_y) + vec2(0.0, 0.0));
	float n = cell.x * 7.13 + cell.y * 131.7 + seed * 53.0;
	vec2 r = h21(n);
	if (r.x > dens) { return 0.0; }
	float fy = fract(q.y / cs_y);
	// The head falls: its place in the cell grows with time (screen y is down); the tail trails above it (da: the distance above
	// the head, 0 at the head), nothing below it.
	float hp = fract(TIME * speed * (0.85 + 0.3 * r.y) + r.x * 7.0);
	float da = fract(hp - fy);
	float len = 0.34;
	float tail = 1.0 - smoothstep(0.0, len, da);
	float ty = da;
	float x0 = (0.2 + 0.6 * r.y) * cs_x;
	float dx = abs(fract(q.x / cs_x) * cs_x - x0);
	float side = 1.0 - smoothstep(0.3 * wpx, wpx, dx);
	float head = smoothstep(0.0, 0.03, ty);
	return tail * side * head;
}

float snow_layer(vec2 p, float cs, float speed, float seed, float dens, float rad) {
	vec2 q = vec2(p.x - p.y * wind * 0.6, p.y);
	vec2 cell = floor(q / cs);
	float n = cell.x * 7.13 + cell.y * 131.7 + seed * 53.0;
	vec2 r = h21(n);
	if (r.x > dens) { return 0.0; }
	float fy = fract(r.y * 3.0 + TIME * speed * (0.8 + 0.4 * r.y));
	vec2 fp = vec2((cell.x + 0.2 + 0.6 * h11(n + 3.0)) * cs + sin(TIME * (0.7 + r.x) + n) * 0.22 * cs, (cell.y + fy) * cs);
	float d = length(q - fp);
	float edge = smoothstep(0.0, 0.15, fy) * (1.0 - smoothstep(0.85, 1.0, fy));
	return (1.0 - smoothstep(rad * 0.2, rad, d)) * edge;
}

void fragment() {
	vec2 p = FRAGCOORD.xy / unit;
	float a = 0.0;
	for (int i = 0; i < 3; i++) {
		if (i >= layers) { break; }
		float f = float(i);
		vec2 pp = p + pan * 0.012 * (1.0 + f) / unit;
		float dens = density * (0.55 - 0.1 * f);
		if (is_snow > 0.5) {
			a += snow_layer(pp, 18.0 + 14.0 * f, 0.9 * (0.6 + 0.3 * f), f * 3.7, dens * 1.3, 2.4 + 1.8 * f);
		} else {
			a += rain_layer(pp, 11.0 + 7.0 * f, 90.0 + 40.0 * f, 1.5 + 0.8 * f, f * 3.7, dens * 1.3, 0.8 + 0.4 * f) * (0.55 + 0.25 * f);
		}
	}
	COLOR = vec4(col.rgb, clamp(a, 0.0, 1.0) * col.a);
}
"""

var battle: Node
var spec: Dictionary = {}
var v3d := false
var _grade: ColorRect
var _veil: ColorRect
var _precip: ColorRect
var _flash: ColorRect
var _veil_mat: ShaderMaterial
var _flash_mat: ShaderMaterial
var _precip_mat: ShaderMaterial
var _grade_mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _next_strike := 4.0
var _strike_t := -1.0
var _strike_pat: Array = []
var _t := 0.0
## The lightning's current value 0..1 (read by the 3D view for the lamp and the ambient), and how many strokes have struck.
var flash := 0.0
var strikes := 0
var precip_on := false
var low := false

## A strike is a few strokes [time s, strength]: a flicker, then the long one.
const PATTERNS := [
	[[0.0, 1.0], [0.09, 0.2], [0.16, 0.85], [0.34, 0.35]],
	[[0.0, 0.7], [0.07, 0.15], [0.12, 1.0]],
	[[0.0, 1.0], [0.20, 0.5], [0.27, 0.25], [0.46, 0.7]],
]


func setup(p_battle: Node, p_spec: Dictionary, seed_v: int) -> void:
	battle = p_battle
	spec = p_spec
	v3d = BoardView.v3d
	low = Quality.is_low()
	layer = 1
	_rng.seed = (seed_v ^ 0x57A11) & 0x7FFFFFFF
	_next_strike = _rng.randf_range(1.5, 5.0)
	_grade = _rect(MUL_CODE)
	_grade_mat = _grade.material
	var m: Color = spec["mul"]
	# (Low keeps the dimming: the multiply is the cheap part.)
	_grade_mat.set_shader_parameter("mul_col", m)
	_grade.visible = m != Color(1, 1, 1)
	_veil = _rect(VEIL_CODE)
	_veil_mat = _veil.material
	var vc: Color = spec["veil"]
	_veil_mat.set_shader_parameter("veil_col", Color(vc.r, vc.g, vc.b, 1.0))
	var rain: float = spec["rain"]
	var snow: float = spec["snow"]
	var dens := maxf(rain, snow)
	precip_on = dens > 0.0 and not v3d
	_precip = _rect(PRECIP_CODE)
	_precip_mat = _precip.material
	_precip_mat.set_shader_parameter("is_snow", 1.0 if snow > 0.0 else 0.0)
	_precip_mat.set_shader_parameter("density", dens * (0.5 if low else 1.0))
	_precip_mat.set_shader_parameter("wind", float(spec["wind"]))
	_precip_mat.set_shader_parameter("layers", 1 if low else 3)
	_precip_mat.set_shader_parameter("col", Color(0.84, 0.9, 0.98, 0.55) if rain > 0.0 else Color(1.0, 1.0, 1.0, 0.95))
	_precip.visible = precip_on
	_flash = _rect(FLASH_CODE)
	_flash_mat = _flash.material
	_flash.visible = false
	_update_veil()


func _rect(code: String) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	r.material = mat
	add_child(r)
	return r


## The veil's alpha at the top and the bottom of the screen: the kind's haze, and a distance fade for the fog (top and oblique:
## from the visible height in metres and the tilt; 3D leaves the distance to the environment's fog).
func _update_veil() -> void:
	var vc: Color = spec["veil"]
	var base := vc.a
	var top := base
	var bot := base
	var fog_m: float = spec["fog_m"]
	if fog_m > 0.0 and battle != null and battle.camera != null and not v3d:
		var vp := get_viewport().get_visible_rect().size
		var z := maxf(get_viewport().canvas_transform.x.length(), 0.001)
		var ppm: float = float(battle.PX_PER_M)
		var cam_h := vp.y / (z * ppm)
		var e := deg_to_rad(BoardView.elev_deg) if BoardView.oblique else deg_to_rad(90.0)
		var span := 0.5 * cam_h / maxf(tan(e), 0.2) if BoardView.oblique else 0.0
		var d0 := 60.0
		top = 1.0 - (1.0 - base) * exp(-maxf(span + d0, 0.0) / fog_m)
		bot = 1.0 - (1.0 - base) * exp(-maxf(-span + d0, 0.0) / fog_m)
		if not BoardView.oblique:
			top = 1.0 - (1.0 - base) * exp(-d0 * 0.5 / fog_m)
			bot = top
	_veil_mat.set_shader_parameter("a_top", top)
	_veil_mat.set_shader_parameter("a_bot", bot)
	_veil_mat.set_shader_parameter("vig", 0.12 if spec["kind"] != "clear" else 0.0)
	_veil.visible = top > 0.004 or bot > 0.004


## One strike now (tests: the same pattern the timer picks).
func strike(pattern := -1) -> void:
	_strike_pat = PATTERNS[(pattern if pattern >= 0 else _rng.randi() % PATTERNS.size())]
	_strike_t = 0.0
	strikes += 1


func _process(delta: float) -> void:
	_t += delta
	if spec.is_empty():
		return
	var vp := get_viewport().get_visible_rect().size
	if precip_on:
		_precip_mat.set_shader_parameter("unit", vp.y / 390.0)
		var ct := get_viewport().canvas_transform
		_precip_mat.set_shader_parameter("pan", -ct.origin / maxf(ct.x.length(), 0.001))
	_update_veil()
	step(delta)


## The lightning's clock (also called by tests with a fixed delta): the timer, the strokes' envelope, the additive rect.
func step(delta: float) -> void:
	var f := 0.0
	if bool(spec["storm"]) and not low:
		if _strike_t < 0.0:
			_next_strike -= delta
			if _next_strike <= 0.0:
				strike()
				_next_strike = _rng.randf_range(6.0, 18.0)
		if _strike_t >= 0.0:
			_strike_t += delta
			for s in _strike_pat:
				var dt := _strike_t - float(s[0])
				if dt >= 0.0:
					f = maxf(f, float(s[1]) * exp(-dt * 16.0))
			var last: float = float(_strike_pat[_strike_pat.size() - 1][0])
			if _strike_t > last + 0.5:
				_strike_t = -1.0
	flash = f
	_flash.visible = f > 0.01
	if f > 0.01:
		# (3D: the lamp does most of it, the rect only the sky's glare)
		_flash_mat.set_shader_parameter("amount", f * (0.18 if v3d else 0.34))
