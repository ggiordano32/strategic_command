shader_type canvas_item;
// The sea of the campaign map (reworked 2026-10-13): a narrow calm shallow
// band hugging the coast (tools/geo_fit.py COAST field) falling smoothly to
// the open-sea colour, two faint sharp offshore contour lines (water-lining,
// 1 px wide in screen space via fwidth) and, on "high", a low-contrast
// advected noise that slides along the current (flow-map technique: two
// layers a half cycle apart, crossfaded) plus a faint large shimmer. No foam,
// no streaks. The coast line itself is drawn by map_view over the land edge.
// View only; TIME is the engine's render clock.
// hi = 0 (settings.cfg [map] water = low): depth tint and contour lines only.

uniform sampler2D coast : filter_linear, repeat_disable;  // 128 + signed km, sea positive
uniform vec2 field_px = vec2(2760.0, 1400.0);              // map pixels the field covers
uniform float hi = 1.0;
uniform vec2 gyre_c = vec2(1190.0, 800.0);                 // western Mediterranean (map px)
uniform float gyre_r = 420.0;
uniform vec3 c_shore = vec3(0.27, 0.46, 0.52);   // at the coast
uniform vec3 c_shal = vec3(0.18, 0.33, 0.42);    // about 6 km
uniform vec3 c_deep = vec3(0.13, 0.25, 0.34);    // 25 km and more
uniform vec3 c_line = vec3(0.62, 0.80, 0.86);    // contour lines

varying vec2 wp;

void vertex() {
	wp = VERTEX;
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// A sharp 1 px line at distance k (km) from the coast; fades out when the
// lines would crowd (zoomed far out).
float contour(float d, float fw, float k) {
	float l = 1.0 - smoothstep(0.45 * fw, 1.1 * fw, abs(d - k));
	return l * smoothstep(3.0, 7.0, k / max(fw, 0.0001));
}

void fragment() {
	float t = TIME;
	vec2 fuv = wp / field_px;
	float d = texture(coast, fuv).r * 255.0 - 128.0;   // km, sea side positive
	d = mix(80.0, d, step(0.0, fuv.x) * step(fuv.x, 1.0) * step(0.0, fuv.y) * step(fuv.y, 1.0));   // outside the window: open sea
	vec3 col = mix(c_shore, c_shal, smoothstep(0.0, 5.0, d));
	col = mix(col, c_deep, smoothstep(5.0, 25.0, d));
	if (hi > 0.5) {
		float open = smoothstep(6.0, 24.0, d);
		// Faint large shimmer.
		float n1 = vnoise(wp * 0.022 + vec2(t * 0.020, t * 0.012));
		col += vec3((n1 - 0.5) * 0.035);
		// The current: a flow field (anticlockwise gyre in the western
		// Mediterranean, a gentle ambient drift elsewhere).
		vec2 rel = wp - gyre_c;
		float rr = length(rel);
		vec2 gyre = vec2(rel.y, -rel.x) / max(rr, 1.0);
		float gw = exp(-rr * rr / (2.0 * gyre_r * gyre_r));
		float ang = 0.4 * sin(wp.x * 0.0031 + 1.0) + 0.5 * cos(wp.y * 0.0047);
		vec2 amb = vec2(cos(ang), sin(ang));
		vec2 fl = normalize(gyre * gw * 1.7 + amb * (1.0 - gw) + vec2(0.0001));
		// Two layers of noise, each carried along the flow over a cycle and
		// crossfaded so the texture slides without stretching.
		float cyc = 14.0;
		float p1 = fract(t / cyc);
		float p2 = fract(t / cyc + 0.5);
		float w1 = 0.5 - 0.5 * cos(6.2831853 * p1);
		float c1 = vnoise((wp - fl * p1 * cyc * 7.0) * vec2(0.016, 0.026));
		float c2 = vnoise((wp - fl * p2 * cyc * 7.0) * vec2(0.016, 0.026) + 31.7);
		float cur = mix(c2, c1, w1) - 0.5;
		col += vec3(0.08, 0.11, 0.12) * cur * 0.9 * open;
	}
	float fw = fwidth(d);
	float ln = max(contour(d, fw, 3.0) * 0.7, contour(d, fw, 8.0) * 0.45) * step(0.5, d);
	col = mix(col, c_line, ln * 0.22);
	COLOR = vec4(col, 1.0);
}
