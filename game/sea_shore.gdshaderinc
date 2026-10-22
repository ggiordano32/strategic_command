// Shared by sea_water.gdshader and sea_land.gdshader (the sea battle's look, game/sea_look.gd):
// value noise and the shore's refinement. The sim's land is a grid of 20 m cells; the baked
// signed distance to its edge (`sdf`, metres, sea positive) is smooth, and the drawn shore
// lies shore_e() metres INSIDE the sim's land (5 to 14 m), ragged by two noise scales: the
// water shows where the sim has land, never the other way round, so no ship can lie over
// drawn land. Both shaders compute the drawn distance dd = sdf + shore_e(p) (sea positive).

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

uniform float shore_lo = 5.0;      // metres of land the water always takes
uniform float shore_amp = 9.0;     // ... and up to this much more, by noise

float shore_e(vec2 p) {
	return shore_lo + shore_amp * (0.62 * vnoise(p / 37.0 + vec2(3.7, 1.2)) + 0.38 * vnoise(p / 11.0 + vec2(8.1, 5.5)));
}

// BattleLook values (game/battle_look.gd, set by BattleLook.apply).
uniform float amb = 0.5;
uniform float key = 0.88;
uniform float rim = 0.22;
uniform float outline = 0.55;
uniform float sat = 1.22;
uniform float contrast = 1.12;

// The board's edge (the field's rectangle): beyond it the sea and the land go on, a little dimmed
// and desaturated, and a thin rim of light marks the edge (the diorama's board).
vec3 board_edge(vec3 col, vec2 p, vec2 field_m, float wpp) {
	vec2 q = max(vec2(-p.x, p.x - field_m.x), vec2(-p.y, p.y - field_m.y));
	float out_d = max(q.x, q.y);                       // metres outside the field (negative inside)
	float outside = smoothstep(-1.0, max(1.0, wpp), out_d);
	float l = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, mix(vec3(l), col, 0.8) * 0.78, outside);
	float rimline = 1.0 - smoothstep(0.0, max(2.5, wpp * 1.6), abs(out_d));
	return mix(col, vec3(0.80, 0.92, 0.96), rimline * (0.10 + rim * 0.5));
}

vec3 grade(vec3 c, float sat_k, float pivot) {
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(vec3(l), c, sat_k);
	return clamp((c - pivot) * contrast + pivot, 0.0, 1.0);
}
