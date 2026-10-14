extends CanvasLayer
## Light depth of field at the screen edges for the diorama look (High only): a full-screen pass that blurs
## the outer part of the screen a little (never the middle third), under the HUD (added before it, same
## layer). Off on Graphics Low and in the painterly look. View only.

const SHADER_CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength = 1.6;
void fragment() {
	vec2 p = (SCREEN_UV - 0.5) * vec2(1.0, 0.9);
	float a = smoothstep(0.34, 0.62, length(p));
	if (a < 0.01) {
		COLOR = vec4(0.0);
	} else {
		vec2 px = SCREEN_PIXEL_SIZE * strength * a * 2.2;
		vec3 c = texture(screen_tex, SCREEN_UV).rgb * 2.0;
		float wsum = 2.0;
		for (int i = 0; i < 8; i++) {
			float ang = float(i) * 0.7854 + 0.3;
			vec2 o = vec2(cos(ang), sin(ang)) * px;
			c += texture(screen_tex, SCREEN_UV + o).rgb;
			wsum += 1.0;
		}
		COLOR = vec4(c / wsum, a);
	}
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
