shader_type spatial;
// The 3D battle view's table (game/view3d.gd): wide wooden planks running along x (seams, grain strokes, a tone per plank), the
// board_layer.gd wood, falling off into a dark room away from the board (the lamp's pool).
render_mode diffuse_lambert, specular_disabled;
uniform vec4 board_rect = vec4(0.0, 0.0, 100.0, 100.0);   // the board on the table (metres: x0, z0, x1, z1)
uniform vec3 wood = vec3(0.40, 0.26, 0.16);
varying vec2 vw;

void vertex() {
	vw = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float h1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h1(i.x + i.y * 57.0);
	float b = h1(i.x + 1.0 + i.y * 57.0);
	float c = h1(i.x + (i.y + 1.0) * 57.0);
	float d = h1(i.x + 1.0 + (i.y + 1.0) * 57.0);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float pw = 26.0;
	float row = floor(vw.y / pw);
	float v = fract(vw.y / pw);
	float tone = h1(row * 7.31);
	vec3 c = wood * (0.82 + 0.3 * tone);
	float g = vn(vec2(vw.x / 40.0 + row * 13.0, v * 18.0)) * 0.6 + vn(vec2(vw.x / 9.0, v * 70.0 + row)) * 0.4;
	c *= 0.86 + 0.24 * g;
	float fw = fwidth(v);
	c *= 1.0 - 0.55 * (1.0 - smoothstep(0.0, max(fw * 1.5, 0.004), min(v, 1.0 - v)));
	vec2 ctr = (board_rect.xy + board_rect.zw) * 0.5;
	vec2 hs = (board_rect.zw - board_rect.xy) * 0.5;
	vec2 d = max(abs(vw - ctr) - hs, vec2(0.0));
	float fall = 1.0 - smoothstep(0.0, max(hs.x, hs.y) * 2.2, length(d));
	c *= 0.35 + 0.65 * fall;
	ALBEDO = c;
	ROUGHNESS = 0.7;
}
