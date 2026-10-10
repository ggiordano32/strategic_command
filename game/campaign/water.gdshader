shader_type canvas_item;
// The sea of the campaign map (2026-10-10), one quad behind the land: depth
// tint from the distance to the coast (tools/geo_fit.py COAST field), two
// octaves of drifting value noise for waves, slow current streaks along a
// flow field (a gentle anticlockwise gyre in the western Mediterranean), a
// foam line along the coast. View only; TIME is the engine's render clock.
// hi = 0 (settings.cfg [map] water = low): depth tint and a simple foam only.

uniform sampler2D coast : filter_linear, repeat_disable;  // 128 + signed km, sea positive
uniform vec2 field_px = vec2(2760.0, 1400.0);              // map pixels the field covers
uniform float hi = 1.0;
uniform vec2 gyre_c = vec2(1190.0, 800.0);                 // western Mediterranean (map px)
uniform float gyre_r = 420.0;
uniform vec3 c_shore = vec3(0.44, 0.72, 0.70);   // pale turquoise
uniform vec3 c_shal = vec3(0.26, 0.50, 0.56);    // about 15 km
uniform vec3 c_mid = vec3(0.19, 0.37, 0.46);     // about 35 km
uniform vec3 c_deep = vec3(0.13, 0.25, 0.34);    // 60 km and more
uniform vec3 c_foam = vec3(0.92, 0.97, 0.97);

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

void fragment() {
	float t = TIME;
	vec2 fuv = wp / field_px;
	float d = texture(coast, fuv).r * 255.0 - 128.0;   // km, sea side positive
	d = mix(80.0, d, step(0.0, fuv.x) * step(fuv.x, 1.0) * step(0.0, fuv.y) * step(fuv.y, 1.0));   // outside the window: open sea
	vec3 col = mix(c_shore, c_shal, smoothstep(2.0, 15.0, d));
	col = mix(col, c_mid, smoothstep(15.0, 35.0, d));
	col = mix(col, c_deep, smoothstep(35.0, 60.0, d));
	float foam = 0.0;
	if (hi > 0.5) {
		// Waves: two octaves, drifting different ways.
		float n1 = vnoise(wp * 0.045 + vec2(t * 0.030, t * 0.018));
		float n2 = vnoise(wp * 0.120 + vec2(-t * 0.045, t * 0.027) + 17.3);
		float wave = (n1 * 0.62 + n2 * 0.38 - 0.5) * 0.085;
		col += vec3(wave);
		// Currents: slow streaks drifting along the flow.
		vec2 rel = wp - gyre_c;
		float rr = length(rel);
		vec2 gyre = vec2(rel.y, -rel.x) / max(rr, 1.0);   // anticlockwise on the screen
		float gw = exp(-rr * rr / (2.0 * gyre_r * gyre_r));
		float ang = 0.4 * sin(wp.x * 0.0031 + 1.0) + 0.5 * cos(wp.y * 0.0047);
		vec2 amb = vec2(cos(ang), sin(ang));
		vec2 fl = normalize(gyre * gw * 1.7 + amb * (1.0 - gw) + vec2(0.0001));
		float along = dot(wp, fl);
		float across = dot(wp, vec2(-fl.y, fl.x));
		float sn = vnoise(vec2(along * 0.010 - t * 0.55, across * 0.20));
		float streak = smoothstep(0.62, 0.90, sn) * smoothstep(8.0, 30.0, d);
		col += vec3(0.05, 0.075, 0.08) * 0.45 * streak;
		// Foam: a breathing swash line and a thin outer line.
		float breathe = 0.5 + 0.5 * sin(t * 0.8 + n2 * 6.2832);
		float dd = d + (n1 - 0.5) * 1.1;
		foam = (1.0 - smoothstep(0.0, 0.9 + 1.7 * breathe, dd)) * 0.9;
		foam += (1.0 - smoothstep(0.0, 0.3, abs(dd - (1.5 + 1.4 * breathe)))) * 0.35 * (1.0 - breathe);
	} else {
		float breathe = 0.5 + 0.5 * sin(t * 0.8);
		foam = (1.0 - smoothstep(0.0, 0.9 + 1.7 * breathe, d)) * 0.9;
	}
	col = mix(col, c_foam, clamp(foam, 0.0, 1.0) * step(-1.0, d));
	COLOR = vec4(col, 1.0);
}
