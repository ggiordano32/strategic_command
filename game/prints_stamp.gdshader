shader_type canvas_item;
// The detail window's stamp (game/print_layer.gd): one instance per print, placed from the ring texture (four floats a print:
// x m, y m, a code = heading + 8 * (type + 4 * ground kind), the sim second). The canvas transform of the window's SubViewport
// maps metres to texels. Draws R = the print's second (mod 256 s, in 255ths), G = 1 (the coverage: alpha blending makes it the shape), B = its darkness; blended over
// the older prints (mix), so an overlapping edge averages. Types: 0 left boot, 1 right boot, 2 hoof.
uniform sampler2D ring : filter_nearest, repeat_disable;
uniform int first = 0;
uniform int cap = 49152;
uniform float now = 0.0;
uniform float grow = 1.0;   // sprite size factor: more than 1 when the window has fewer texels a metre (Low)
uniform vec2 rows[5];   // per ground kind: boot, hoof darkness

varying flat vec4 pv;   // type, darkness, second code, 0

void vertex() {
	int idx = (first + INSTANCE_ID) % cap;
	vec4 e = texelFetch(ring, ivec2(idx % 256, idx / 256), 0);
	float ty = floor((e.b + 4.0) / 8.0);
	float ang = e.b - ty * 8.0;
	float kind = floor(ty / 4.0);
	ty -= kind * 4.0;
	float age = now - e.a;
	vec2 r = rows[int(kind)];
	float dark = ty > 1.5 ? r.y : r.x;
	pv = vec4(ty, dark, fract(e.a / 256.0), 0.0);
	vec2 sz = ty > 1.5 ? vec2(0.42, 0.38) : vec2(0.58, 0.26);   // metres (long, wide); a little bigger than a real boot
	vec2 l = VERTEX * sz * grow;
	float c = cos(ang);
	float s = sin(ang);
	vec2 p = vec2(l.x * c - l.y * s, l.x * s + l.y * c) + e.xy;
	VERTEX = (age > 90.0 || dark <= 0.0) ? vec2(-1.0e6) : p;
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;   // -1..1, x along the print's heading
	float a = 0.0;
	if (pv.x < 1.5) {
		// a boot: the sole (front) and the heel (back), a narrow waist between; the right foot mirrored
		float m = pv.x < 0.5 ? 1.0 : -1.0;
		vec2 f = vec2(q.x - 0.38, q.y * m * 1.05 + 0.04 * (q.x - 0.38));
		float sole = 1.0 - smoothstep(0.62, 1.0, length(f / vec2(0.58, 0.95)));
		vec2 h = vec2(q.x + 0.62, q.y * m);
		float heel = 1.0 - smoothstep(0.6, 1.0, length(h / vec2(0.36, 0.72)));
		a = max(sole, heel * 0.95);
	} else {
		// a hoof: a filled round print with a small notch at the back (too few texels to draw a horseshoe)
		float d = length(q * vec2(1.0, 0.95));
		a = (1.0 - smoothstep(0.7, 1.0, d)) * (1.0 - 0.5 * smoothstep(-0.2, -0.8, q.x) * (1.0 - smoothstep(0.1, 0.35, abs(q.y))));
	}
	COLOR = vec4(pv.z, 1.0, pv.y, clamp(a, 0.0, 1.0));
}
