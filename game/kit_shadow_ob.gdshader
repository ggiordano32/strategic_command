shader_type canvas_item;
// The ground shadow of an upright kit piece in the oblique view (game/battlekit_shadow.gd, tabletop pass 3 leftovers):
// one quad per piece (a MultiMesh, centred on the footprint's centre), multiplied over the ground and under the pieces.
// The footprint's soft contact shadow (60 % at the foot, gone 1.5 m out) and a cast shadow to the lower right (the lamp is
// a warm key from the upper left), the footprint swept along the cast direction by `cast` metres, soft-edged.
// INSTANCE_CUSTOM = (half width m, half depth m, cast length m, angle of the piece's right, radians).
render_mode skip_vertex_transform, blend_mul;
#include "res://game/board_view.gdshaderinc"
uniform float ppm = 10.0;
varying vec2 v_w;       // the ground point, world px
varying vec2 v_c;       // the footprint's centre, world px
varying vec4 v_s;

float sd_box(vec2 p, vec2 h) {
	vec2 d = abs(p) - h;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

void vertex() {
	vec2 wp = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	v_w = wp;
	v_c = MODEL_MATRIX[3].xy;
	v_s = INSTANCE_CUSTOM;
	VERTEX = ob_on > 0.5 ? ob_board(wp) : wp;
}

void fragment() {
	vec2 q = (v_w - v_c) / ppm;
	float ca = cos(v_s.w);
	float sa = sin(v_s.w);
	vec2 lq = vec2(dot(q, vec2(ca, sa)), dot(q, vec2(-sa, ca)));
	vec2 h = v_s.xy;
	float d0 = sd_box(lq, h);
	float contact = 0.6 * (1.0 - smoothstep(0.0, 1.5, d0));
	// The cast: the footprint swept 0..cast metres along (0.707, 0.707) (to the lower right), in the piece's own axes.
	vec2 dir = vec2(0.7071, 0.7071) * v_s.z;
	vec2 ldir = vec2(dot(dir, vec2(ca, sa)), dot(dir, vec2(-sa, ca)));
	float d1 = 1e3;
	for (int i = 0; i < 6; i++) {
		d1 = min(d1, sd_box(lq - ldir * (float(i) * 0.2), h));
	}
	float along = clamp(dot(q, vec2(0.7071)) / max(h.x + h.y + v_s.z, 1.0), 0.0, 1.0);
	float cast = 0.45 * (1.0 - smoothstep(-0.2, 1.1, d1)) * (1.0 - 0.3 * along) * step(0.05, v_s.z);
	float a = max(contact, cast);
	COLOR = vec4(vec3(1.0) - a * vec3(0.62, 0.66, 0.74), 1.0);
}
