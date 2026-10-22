shader_type canvas_item;
// The sea battle's land (game/sea_look.gd; 2026-10-22, owner: the land in the ocean battles was low
// quality and its shoreline poor beside the rest of the game). The land maps' ground, drawn in one
// pass over the field from the same baked fields as sea_water.gdshader:
//  - the ground palette of the campaign region (game/ground_palette.gd: base, lush / dry patches,
//    the grass tile), darker under the woods the tree sprites stand in;
//  - a sand beach band (wet and dark at the water, the sand tile), ragged by noise, in place of a
//    cliff where the coast is steep: rock (the rock tile, strata) with a lit brow on the side the
//    light reaches and a dark foot, the diorama's bevel along every shore, the outline;
//  - the shore itself is the sim's cell edge refined with noise (sea_shore.gdshaderinc), always
//    inside the sim's land cells (and guarded by the nearest-sampled cell mask).
// low = true (Graphics Low): plain palette, the beach and cliff bands, the bevel; no noise, no tiles.

#include "res://game/sea_shore.gdshaderinc"

uniform sampler2D fld : filter_linear, repeat_disable;
uniform sampler2D fld2 : filter_linear, repeat_disable;
uniform sampler2D cells : filter_nearest, repeat_disable;
uniform vec2 grid_m = vec2(2400.0, 1600.0);
uniform vec2 field_m = vec2(2400.0, 1600.0);
uniform bool low = false;
uniform vec3 base_col = vec3(0.30, 0.45, 0.22);
uniform vec3 patch_a = vec3(-0.03, 0.05, -0.02);
uniform vec3 patch_b = vec3(0.06, 0.03, -0.04);
uniform vec3 rock_col = vec3(0.46, 0.45, 0.40);
uniform vec3 sand_col = vec3(0.58, 0.52, 0.38);
uniform vec3 wood_col = vec3(0.14, 0.26, 0.12);
uniform sampler2D tile_grass : filter_linear_mipmap, repeat_enable;
uniform sampler2D tile_sand : filter_linear_mipmap, repeat_enable;
uniform sampler2D tile_rock : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_mean = vec3(0.39, 0.49, 0.235);
uniform vec3 sand_mean = vec3(0.76, 0.685, 0.49);

const vec2 LIGHT_XY = vec2(-0.62, -0.78);

varying vec2 wp;

void vertex() {
	wp = VERTEX;
}

void fragment() {
	vec2 p = wp;
	vec2 fuv = p / grid_m;
	vec2 cuv = clamp(fuv, vec2(0.0), vec2(1.0));      // beyond the field the edge texel goes on
	vec4 f = texture(fld, cuv);
	vec4 f2 = texture(fld2, cuv);
	vec2 nrm = normalize(f.gb * 2.0 - 1.0 + vec2(0.0001));      // toward the sea
	float sdf = f.r * 320.0 - 80.0;
	float dd = sdf + shore_e(p);
	float inl = -dd;                                  // metres inland of the drawn shore
	float wpp = max(fwidth(p.x) + fwidth(p.y), 0.0001) * 0.7;
	float guard = step(0.5, texture(cells, cuv).r);
	float a = smoothstep(-0.6 * wpp, 0.6 * wpp, inl) * guard;
	if (a <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		float steep = f2.g;
		// The woods (the formula of SeaLook.wood_formula, which places the trees).
		float im = -sdf - (shore_lo + shore_amp * 0.5);
		float wood = 0.0;
		if (im > 0.0) {
			float w1 = smoothstep(0.42, 0.66, f2.b) * smoothstep(8.0, 38.0, im);
			float strip = smoothstep(14.0, 24.0, im) * (1.0 - smoothstep(48.0, 80.0, im)) * smoothstep(0.35, 0.6, f2.a) * 0.55;
			wood = max(w1, strip) * (1.0 - 0.8 * smoothstep(0.35, 0.7, steep));
		}
		float n1 = 0.5;
		float n2 = 0.5;
		float n3 = 0.5;
		if (!low) {
			n1 = vnoise(p / 58.0 + vec2(3.1, 7.7));
			n2 = vnoise(p / 21.0 + vec2(11.7, 2.3));
			n3 = vnoise(p / 3.4 + vec2(5.3, 9.1));
		}
		float patchv = (n1 - 0.5) * 1.5 + (n2 - 0.5) * 0.7;
		vec3 ground = base_col + (patchv > 0.0 ? patch_a : patch_b) * abs(patchv) * 1.6;
		vec3 sand = sand_col;
		vec3 rock = rock_col;
		if (!low) {
			ground *= 1.0 + (n3 - 0.5) * 0.07;
			vec3 gt = texture(tile_grass, p / 64.0).rgb;
			ground *= mix(vec3(1.0), clamp(gt / grass_mean, vec3(0.55), vec3(1.55)), 0.85);
			vec3 st = texture(tile_sand, p / 20.0).rgb;
			sand = st * (sand_col / sand_mean);
			vec3 rt = texture(tile_rock, p / 9.0).rgb;
			rock = rock_col * mix(vec3(1.0), clamp(rt / vec3(0.5), vec3(0.5), vec3(1.5)), 0.8);
		}
		ground = mix(ground, wood_col, wood * 0.5);
		// The beach: wet and dark at the water, then dry sand, ragged.
		float bw = 7.0 + 8.0 * (low ? 0.5 : n1) + 3.0 * (n3 - 0.5);
		float beach = 1.0 - smoothstep(bw - 3.5, bw, inl);
		vec3 col = mix(ground, sand * 1.22, beach * (1.0 - 0.85 * smoothstep(0.35, 0.6, steep)));
		float wet = 1.0 - smoothstep(0.0, 2.6, inl);
		col = mix(col, col * vec3(0.80, 0.78, 0.74), wet * (1.0 - 0.6 * steep));
		// Steep coast: a cliff band along the water instead of the beach.
		float cw = 5.0 + 9.0 * steep;
		float cmask = smoothstep(0.32, 0.55, steep) * (1.0 - smoothstep(cw - 1.0, cw + 2.5, inl));
		float lit = clamp(dot(nrm, LIGHT_XY) * 1.4, -1.0, 1.0);        // +1: the face the light reaches
		float strata = 0.5 + 0.5 * sin(inl * 1.6 + 3.0 * vnoise(p / 7.0));
		vec3 face = rock * 1.4 * (0.78 + 0.22 * strata) * (1.0 + 0.30 * lit);
		face *= mix(0.62, 1.0, smoothstep(0.0, cw, inl));              // dark at the foot (talus)
		float brow = (1.0 - smoothstep(0.0, 1.8, abs(inl - cw))) * cmask;
		face = mix(face, rock * 1.28, brow * (0.35 + 0.35 * max(lit, 0.0)));
		col = mix(col, face, cmask);
		// The diorama bevel along every shore: a lit edge facing the light, a darker one away from it,
		// then the outline.
		float bev = exp(-inl / 3.6);
		col *= 1.0 + 0.42 * key * lit * bev * (1.0 - 0.5 * cmask);
		col += vec3(0.5, 0.5, 0.42) * rim * max(lit, 0.0) * (1.0 - smoothstep(0.0, 1.4, inl)) * 0.35;
		col *= 1.0 - outline * 0.5 * (1.0 - 0.5 * cmask) * (1.0 - smoothstep(0.0, max(1.1, wpp * 0.9), inl));
		col = board_edge(col, p, field_m, wpp);
		vec3 g = grade(col, 1.0 + (sat - 1.0) * 0.55, 0.40);
		COLOR = vec4(g, a);
	}
}
