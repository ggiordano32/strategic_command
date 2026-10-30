shader_type canvas_item;
// Static-grass tufts standing up in the oblique view (game/tuft_layer.gd): one small quad per tuft, upright at its ground point
// (the instance's translation, world px; the quad's own offsets stay screen-aligned), three blades drawn here: darker at the
// foot, lighter towards the tip and on the left (the lamp is at the upper left), leaning a little. INSTANCE_CUSTOM = the
// blades' lengths as a fraction of the quad's height, and a 0..1 jitter (lean, tone).
render_mode skip_vertex_transform;
#include "res://game/board_view.gdshaderinc"

varying vec4 v_c;
const float W_M = 0.5;
const float H_M = 0.4;
const float FOOT = 0.92;

void vertex() {
	vec2 a = MODEL_MATRIX[3].xy;
	VERTEX = (ob_on > 0.5 ? ob_board(a) : a) + VERTEX;
	v_c = INSTANCE_CUSTOM;
}

void fragment() {
	float cov = 0.0;
	float br = 1.0;
	float aa = max(fwidth(UV.x), 1e-4);
	for (int i = 0; i < 3; i++) {
		float fi = float(i) - 1.0;
		float len = i == 0 ? v_c.x : (i == 1 ? v_c.y : v_c.z);
		float t = (FOOT - UV.y) / len;
		float lean = (fi * 0.07 + (v_c.w - 0.5) * 0.05 + fi * (v_c.w - 0.5) * 0.04) / W_M;
		float cx = 0.5 + fi * 0.045 / W_M + lean * clamp(t, 0.0, 1.0);
		float w = 0.028 / W_M * (1.0 - 0.7 * clamp(t, 0.0, 1.0));
		float c = (1.0 - smoothstep(w - aa, w + aa, abs(UV.x - cx))) * step(0.0, t) * step(t, 1.0);
		if (c > cov) {
			cov = c;
			br = 0.55 + 0.75 * clamp(t, 0.0, 1.0) + (fi < 0.0 ? 0.16 : 0.0) + (UV.x < cx ? 0.12 : 0.0);
		}
	}
	vec3 col = mix(vec3(0.17, 0.32, 0.09), vec3(0.50, 0.70, 0.24), clamp(br - 0.45, 0.0, 1.0));
	col = mix(col, col * vec3(1.18, 1.0, 0.72), v_c.w * 0.5);
	COLOR = vec4(col * (0.8 + 0.4 * br), cov * 0.95);
}
