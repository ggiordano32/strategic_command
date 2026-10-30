// The figure bases (tabletop pass 1, docs/design/art_pipeline.md "Pass 1,
// trays and bases"): a round base about 1 m across (0.7 m is hidden by the top-down figure) under every drawn man,
// a darker ring in the faction's colour with the colour at low saturation
// inside, and a soft contact shadow to the lower right. One quad per
// instance of the soldiers' own MultiMesh (the third layer, drawn first), the
// same two data paths as soldiers.gdshaderinc (texture-fed, and CPU-fed under
// `#define CPU_FED`). A dead man's base stays with his toppled figure and
// fades with it (the state word's heading code, see soldiers.gdshaderinc).
// View only. `low` (Graphics Low): a plain dark ellipse, no ring.
// Flock (tabletop pass 3 leftovers): inside the ring the base is dressed like a painted miniature's: a green-brown
// static-grass speckle (round specks of two greens and straw on a dark earth green, by a hash of the cell and of the man's
// position so no two bases are alike) instead of the plain fill; the faction-coloured rim and the contact shadow stay. The
// speckle fades to its mean colour where a speck would be under about 2 px (far out).
// The oblique view (`#define OBLIQUE`, tabletop pass 3): the base lies on the board under the figure's feet (the circle
// squashed into an ellipse, lifted with the ground and the wall walk), in the soldiers' per-tick order, hidden behind
// a nearer kit piece as the figures are (soldiers.gdshaderinc).
#ifdef OBLIQUE
#include "res://game/board_view.gdshaderinc"
uniform sampler2D ob_occ : filter_nearest, repeat_disable;
uniform float ob_occ_on = 0.0;
uniform vec2 ob_near_r = vec2(0.0, 1.0);
varying float v_near;
#endif

uniform float alpha = 1.0;          // interpolation 0 = prev tick, 1 = current
uniform float px_per_unit = 0.01;   // view pixels per sim unit
uniform float low = 0.0;
uniform sampler2D pal_tex : filter_nearest, repeat_disable;

varying vec4 v_b;   // x palette row, y fade, z 1 = a base here
varying vec2 v_c;   // the corner in base radii
varying float v_seed;   // 0..1 by the man's position (the flock's lattice offset)

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// The flock inside a base at corner coordinates c (base radii): the colour.
vec3 flock_col(vec2 c, float seed) {
	vec2 q = c / 0.2 + vec2(seed * 37.0, seed * 91.0);
	vec2 id = floor(q);
	vec2 f = fract(q) - 0.5;
	float h = hash12(id);
	float h2 = hash12(id + vec2(7.7, 3.1));
	vec2 jit = vec2(hash12(id + vec2(1.3, 9.9)), hash12(id + vec2(5.5, 2.2))) - 0.5;
	float rr = 0.26 + 0.22 * h2;
	float sp = 1.0 - smoothstep(rr - 0.12, rr, length(f - jit * 0.35));
	vec3 g1 = vec3(0.17, 0.34, 0.08);
	vec3 g2 = vec3(0.30, 0.48, 0.12);
	vec3 straw = vec3(0.62, 0.54, 0.28);
	vec3 sc = h < 0.45 ? g1 : (h < 0.8 ? g2 : straw);
	vec3 earth = vec3(0.24, 0.17, 0.09);
	vec3 col = mix(earth, sc, sp);
	vec3 mean = mix(earth, vec3(0.30, 0.43, 0.15), 0.45);
	float fw = fwidth(c.x);
	return mix(col, mean, smoothstep(0.07, 0.14, fw));
}

// The base radius in metres by sprite (soldier_layer.gd SPR_RECT: 5 horse and rider,
// 9 camel, 10 elephant, 11 dog).
float base_radius(int spr) {
	if (spr == 11) { return 0.36; }
	if (spr == 5 || spr == 9) { return 0.65; }   // horse and rider, camel
	if (spr == 10) { return 1.1; }                // war elephant
	return 0.5;
}

#ifndef CPU_FED
uniform sampler2D data_tex : filter_nearest;
uniform int rows_per_block = 1;
uniform int tex_width = 1024;

int fetch_int(int block, int idx) {
	int row = idx / tex_width;
	ivec2 p = ivec2(idx - row * tex_width, block * rows_per_block + row);
	vec4 b = floor(texelFetch(data_tex, p, 0) * 255.0 + 0.5);
	if (b.a >= 128.0) {
		vec4 c = vec4(255.0) - b;
		return -int(c.r + c.g * 256.0 + c.b * 65536.0 + c.a * 16777216.0) - 1;
	}
	return int(b.r + b.g * 256.0 + b.b * 65536.0 + b.a * 16777216.0);
}

int bitfield(int v, int div, int span) {
	int q = v / div;
	return q - (q / span) * span;
}
#endif

void vertex() {
#ifdef CPU_FED
	float sbw = floor(MODEL_MATRIX[1].y + 0.5);
	float hdw = floor(sbw / 16.0);
	int hd = int(hdw);
	int st = int(sbw - hdw * 16.0);
	vec2 cur = MODEL_MATRIX[3].xy;
	vec2 prv = MODEL_MATRIX[0].xy;
#ifdef OBLIQUE
	float spx = floor(INSTANCE_CUSTOM.x + 0.5);
	int spr = clamp(int(mod(spx, 16.0)), 0, 11);
	float ext = floor(spx / 16.0) * 0.1 * px_per_unit * 1024.0;
#else
	int spr = clamp(int(INSTANCE_CUSTOM.x + 0.5), 0, 11);
#endif
	int pal = int(floor(floor(INSTANCE_CUSTOM.z + 0.5) / 64.0));
#else
	int i = int(INSTANCE_CUSTOM.x + 0.5) + int(INSTANCE_CUSTOM.y + 0.5) * 2048;
#ifdef OBLIQUE
	i = fetch_int(9, i);
#endif
	int sb = fetch_int(5, i);
	int hd = sb / 16;
	int st = sb - hd * 16;
	vec2 cur = vec2(float(fetch_int(0, i)), float(fetch_int(1, i)));
	vec2 prv = vec2(float(fetch_int(2, i)), float(fetch_int(3, i)));
	int uidx = fetch_int(6, i);
	int flags = fetch_int(7, uidx);
	int spr = clamp(bitfield(flags, 16, 16), 0, 11);
	int pal = bitfield(flags, 262144, 16);
#ifdef OBLIQUE
	float ext = float(fetch_int(8, uidx) / 64) * 0.1 * px_per_unit * 1024.0;
#endif
#endif
	// 0 formed, 1 fighting, 2 routing, 3 knocked down, 4 dead (hd: its fade), 5 off the field; 6+ engines
	if (st == 5 || st >= 6) {
		VERTEX = vec2(-100000.0);
		v_b = vec4(0.0);
		v_c = vec2(0.0);
		v_seed = 0.0;
#ifdef OBLIQUE
		v_near = 0.0;
#endif
	} else {
		float r = base_radius(spr);
		vec2 c = (UV * 2.0 - 1.0) * 1.7;
		float fade = (st == 4 && hd > 0) ? float(hd) / 32.0 : 1.0;
		v_b = vec4(float(pal), fade * (st == 4 ? 0.9 : 1.0), 1.0, 0.0);
		v_c = c;
		v_seed = hash12(floor(cur * 0.004));
		vec2 p = mix(prv, cur, alpha) * px_per_unit + c * (r * px_per_unit * 1024.0);
#ifdef OBLIQUE
		vec2 g = mix(prv, cur, alpha) * px_per_unit;
		v_near = ob_near(g, ext);
		p = ob_board(g) - vec2(0.0, ext * OB_SIN) + c * (r * px_per_unit * 1024.0) * vec2(1.0, OB_COS);
#endif
#ifdef CPU_FED
		VERTEX = p;
#else
		VERTEX = p - MODEL_MATRIX[3].xy;
#endif
	}
}

void fragment() {
	vec3 prim = texelFetch(pal_tex, ivec2(0, int(v_b.x + 0.5)), 0).rgb;
	float d = length(v_c);
	float aa = clamp(fwidth(d) * 0.9, 0.02, 0.5);
	if (low > 0.5) {
		float e = length(v_c * vec2(1.0, 1.25) - vec2(0.12, 0.18));
		COLOR = vec4(0.05, 0.04, 0.03, (1.0 - smoothstep(1.0 - aa, 1.0, e)) * 0.5 * v_b.y);
	} else {
		float disc = 1.0 - smoothstep(1.0 - aa, 1.0, d);
		float ring = smoothstep(0.74 - aa, 0.74, d);
		float luma = dot(prim, vec3(0.3, 0.59, 0.11));
		vec3 inner = mix(flock_col(v_c, v_seed), mix(vec3(luma), prim, 0.5) * 0.9, 0.1) * 0.85;
		vec3 rim = prim * 0.4;
		vec3 col = mix(inner, rim, ring);
		col += vec3(0.07) * (1.0 - smoothstep(-0.7, 0.1, v_c.y + v_c.x * 0.3)) * (1.0 - ring);   // a lit top
		float sh = (1.0 - smoothstep(0.5, 1.45, length(v_c - vec2(0.3, 0.38)))) * 0.42;
		float a = disc + sh * (1.0 - disc);
		vec3 rgb = (col * disc + vec3(0.04, 0.03, 0.02) * sh * (1.0 - disc)) / max(a, 0.0001);
		COLOR = vec4(rgb, a * v_b.y);
	}
#ifdef OBLIQUE
	if (ob_occ_on > 0.5) {
		vec4 o = texture(ob_occ, SCREEN_UV);
		float on = (floor(o.r * 255.0 + 0.5) * 256.0 + floor(o.g * 255.0 + 0.5)) / 65535.0 * ob_near_r.y + ob_near_r.x;
		if (o.a > 0.5 && on > v_near + 2.0) {
			COLOR.a *= o.b * 0.6;   // (the man is a ghost: no base; behind a fading wall, as its fade)
		}
	}
#endif
}
