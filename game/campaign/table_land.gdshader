shader_type canvas_item;
#include "res://game/campaign/map_look.gdshaderinc"
// The map-table land (settings [map] style = table): the ground colours of
// landscape.gd's ground texture, brighter and warmer, with posterised
// hillshade bands (4 levels, north-west light) from the real elevation, thin
// ink contour lines (every `interval` metres, a stronger one every fifth), and
// a sand band along the coast. map_view.gd draws the land polygons with it
// behind its own drawing (trees, rivers, borders, the owner's wash).
uniform sampler2D ground : filter_linear, repeat_disable;
uniform sampler2D elev : filter_linear, repeat_disable;   // metres, R16F
uniform sampler2D coast : filter_linear, repeat_disable;  // 128 + signed km, sea positive
uniform vec2 field_px = vec2(2760.0, 1400.0);
uniform vec2 elev_texel = vec2(0.001, 0.001);
uniform float sample_m = 2500.0;                          // metres a sample
uniform float interval = 400.0;
uniform float exag = 5.0;
uniform sampler2D towns : filter_linear, repeat_disable;  // the towns' painted ground (town_paint.gd), premultiplied
uniform vec2 towns_px = vec2(3760.0, 2350.0);              // world px it covers
uniform float towns_on = 0.0;

varying vec2 wp;

void vertex() {
	wp = VERTEX;
}

float hgt(vec2 uv) {
	return max(texture(elev, uv).r, 0.0);
}

void fragment() {
	vec2 fuv = wp / field_px;
	vec3 g = texture(ground, UV).rgb;
	// brighter, warmer, a little more saturated
	float l = dot(g, vec3(0.30, 0.59, 0.11));
	g = mix(vec3(l), g, 1.22) * vec3(1.12, 1.07, 0.93) + vec3(0.05, 0.04, 0.0);
	// the towns' ground: clearing, packed earth, streets, fields, quays (before the light, so it is shaded like the land)
	vec4 tp = texture(towns, wp / towns_px) * towns_on;
	g = g * (1.0 - tp.a) + tp.rgb;
	float h = hgt(fuv);
	float hx = hgt(fuv + vec2(elev_texel.x * 1.5, 0.0)) - hgt(fuv - vec2(elev_texel.x * 1.5, 0.0));
	float hy = hgt(fuv + vec2(0.0, elev_texel.y * 1.5)) - hgt(fuv - vec2(0.0, elev_texel.y * 1.5));
	vec3 n = normalize(vec3(-hx / (3.0 * sample_m) * exag, -hy / (3.0 * sample_m) * exag, 1.0));
	vec3 ld = normalize(MAP_LIGHT);
	float lit = dot(n, ld) - ld.z;                   // 0 on flat ground
	float q = floor(clamp(lit * 5.0, -1.0, 1.0) * 2.0 + 0.5) / 2.0;   // -1 .. 1 in halves
	g *= 1.0 + q * 0.26;
	// higher ground: a drier, tanner tone in steps
	float lvl = floor(h / (interval * 3.0));
	g = mix(g, vec3(0.80, 0.68, 0.46), clamp(lvl * 0.09, 0.0, 0.5));
	// the coast: a sand band
	float d = texture(coast, fuv).r * 255.0 - 128.0;
	float sand = 1.0 - smoothstep(-1.6, -0.5, d);
	sand *= 1.0 - smoothstep(30.0, 90.0, h);
	g = mix(g, vec3(0.93, 0.85, 0.62), sand * 0.75);
	// ink contours: fade out when they crowd
	float fw = max(fwidth(h), 0.0001);
	float c1 = abs(fract(h / interval + 0.5) - 0.5) * interval;
	float line1 = (1.0 - smoothstep(0.45 * fw, 1.1 * fw, c1)) * smoothstep(3.0, 7.0, interval / fw) * step(interval * 0.5, h);
	float c5 = abs(fract(h / (interval * 5.0) + 0.5) - 0.5) * interval * 5.0;
	float line5 = (1.0 - smoothstep(0.6 * fw, 1.5 * fw, c5)) * smoothstep(3.0, 7.0, interval * 5.0 / fw) * step(interval * 2.0, h);
	g = mix(g, MAP_INK, clamp(line1 * 0.20 + line5 * 0.30, 0.0, 0.6));
	g = map_grade(g);
	g = map_grain(g, SCREEN_UV, SCREEN_PIXEL_SIZE);
	COLOR = vec4(g, 1.0);
}
