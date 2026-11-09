shader_type spatial;
// The sea battle's water in the 3D view (game/sea_view3d.gd). High: a displaced grid (game/sea_swell3d.gd grid_mesh) carrying a live
// swell, two long trains before the wind whose formula the CPU twin shares (so the ships ride the surface drawn under them), the 2D
// sea screen's fragment (game/sea_water_body.gdshaderinc: depth colours, painted crests, whitecaps, the shore's swash and breakers,
// the board's rim) as the painted colour, then a cast-resin finish: the swell's slope lights and darkens it a little and one glossy
// highlight from the lamp rides the crests (no sky reflection, no Fresnel, no simulated foam). Low: one flat quad, sw_k = 0,
// hi = 0, the still wash. Unshaded (the light is painted); no vertex texture reads (the compatible path).
render_mode unshaded, depth_draw_opaque, cull_disabled;

#include "res://game/sea_water_body.gdshaderinc"

uniform float sw_turn[2];
uniform float sw_lam[2];
uniform float sw_spd[2];
uniform float sw_amp[2];
uniform float sw_k = 0.0;
uniform float sw_lean = 0.12;
uniform float sw_gloss = 0.0;
uniform float sw_shine = 38.0;
uniform float sw_shade = 1.0;

varying vec2 wp;
varying vec3 swn;

void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	wp = p;
	swn = vec3(0.0, 1.0, 0.0);
	if (sw_k > 0.0) {
		float d = (0.35 + 0.65 * COLOR.r) * (0.35 + 0.65 * wstr) * sw_k * COLOR.g;
		vec2 w = normalize(wdir);
		float h = 0.0;
		vec2 g = vec2(0.0);
		for (int i = 0; i < 2; i++) {
			vec2 dir = rot(w, sw_turn[i]);
			float kw = 6.2831853 / sw_lam[i];
			float ph = dot(p, dir) * kw - t * sw_spd[i] * kw + float(i) * 2.1;
			h += sw_amp[i] * (sin(ph) - sw_lean * cos(2.0 * ph));
			g += dir * (sw_amp[i] * kw * (cos(ph) + 2.0 * sw_lean * sin(2.0 * ph)));
		}
		VERTEX.y += h * d;
		swn = normalize(vec3(-g.x * d, 1.0, -g.y * d));
	}
}

void fragment() {
	vec3 col = sea_water_color(wp).rgb;
	if (sw_k > 0.0) {
		vec3 L = normalize(vec3(-0.62 * 0.8, 0.9, -0.78 * 0.8));
		float lit = dot(swn, L) - L.y;
		col *= 1.0 + sw_shade * lit * 1.6;
		vec3 vw = (INV_VIEW_MATRIX * vec4(normalize(VIEW), 0.0)).xyz;
		vec3 hv = normalize(L + vw);
		float spec = pow(max(dot(swn, hv), 0.0), sw_shine);
		col += vec3(1.0, 0.97, 0.88) * spec * sw_gloss * 0.55;
	}
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
}
