extends CanvasLayer
## The table's lamp and lens for the diorama look (High only; tabletop pass 2): one full-screen pass that blurs
## the outer part of the screen a little (never the middle third) and, tilt-shift, the top and bottom bands, tints
## the whole board warm from the upper left and adds a soft vignette; under the HUD (added before it, same
## layer). Off on Graphics Low and in the painterly look. View only.

const SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength = 1.6;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 base = texture(screen_tex, uv).rgb;
	vec2 p = (uv - 0.5) * vec2(1.0, 0.9);
	// Depth of field at the screen edges, and the tilt-shift of the overworld frame on the top and bottom bands.
	float ty = smoothstep(0.30, 0.5, abs(uv.y - 0.5));
	float a = max(smoothstep(0.34, 0.62, length(p)), ty * 0.9);
	vec3 col = base;
	if (a >= 0.01) {
		vec2 px = SCREEN_PIXEL_SIZE * strength * a * 2.2 * (1.0 + ty * 0.8);
		vec3 c = base * 2.0;
		float wsum = 2.0;
		for (int i = 0; i < 8; i++) {
			float ang = float(i) * 0.7854 + 0.3;
			vec2 o = vec2(cos(ang), sin(ang)) * px;
			c += texture(screen_tex, uv + o).rgb;
			c += texture(screen_tex, uv + o * 0.5).rgb;
			wsum += 2.0;
		}
		col = mix(base, c / wsum, a);
	}
	// The table lamp: a warm key from the upper left (about 6 % warmer and brighter there, cooler at the lower
	// right), and a soft vignette.
	float k = dot(uv - 0.5, vec2(-0.7071, -0.7071)) / 0.7071;
	col *= vec3(1.0 + 0.06 * k, 1.0 + 0.035 * k, 1.0 - 0.03 * k);
	float v = smoothstep(0.55, 1.25, length((uv - 0.5) * vec2(1.25, 1.0) * 1.6));
	col *= 1.0 - 0.2 * v;
	COLOR = vec4(col, 1.0);
}
"""


func _ready() -> void:
	layer = 1
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = sh
	r.material = mat
	add_child(r)
