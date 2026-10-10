shader_type canvas_item;
// Battlefield ground: a calm topographic-map look drawn in one pass from a
// height texture built once per battle (game/terrain_layer.gd), in the
// region's ground palette (game/ground_palette.gd).
//
// Height texture (RGBA8, one texel per 2 m node, nearest / texelFetch only,
// no float textures and no reliance on filtering precision):
//   R, G  height, 16 bits (R high byte), 0..65535 over 0..h_range_m metres
//   B     shade: 128 = flat; (B - 128) / 160 = relative brightness (hill
//         shading from the upper left plus a soft darkening of valley floors)
//   A     slope: ground grade (rise / run) 0..0.8 over 0..255 (rock tint and
//         slope darkening; interpolated like the height)
// Ground features texture (RGBA8, one texel per 4 m cell, linear filter):
//   R woods (tree density / 3), G inside a settlement, B farm field,
//   A 0.5 main street / 1.0 plaza.
// The ground also carries low-frequency colour variation (patches of lusher
// and of drier or stonier ground from hash noise), rock on steep slopes and
// above a notional tree line on hill maps, wet sand along water and a
// moving ripple on the river and the sea (the built-in TIME, nothing from
// the sim).
// The four height nodes around a fragment are decoded and interpolated here
// (manual bilinear in highp), so contours are exact and stable when panning
// and zooming. Contour lines keep a constant screen width via fwidth() and
// fade out where they would crowd together when zoomed far out.

uniform sampler2D hmap : filter_nearest, repeat_disable;
uniform ivec2 hmap_size = ivec2(2, 2);
uniform sampler2D vegmap : filter_linear, repeat_disable;
uniform bool veg_on = false;
uniform vec2 veg_size_px = vec2(1.0);  // world pixels covered by the features texture
uniform float texel_px = 20.0;        // world pixels between texels (nodes)
uniform float h_range_m = 1.0;        // metres represented by 65535
uniform float h_mid_m = 0.0;          // tint is neutral at this height
uniform float h_base_m = 0.0;         // the commonest height: midway between two contours
uniform bool terrain_on = false;
uniform vec3 base_col = vec3(0.27, 0.38, 0.2);
uniform vec3 low_col = vec3(0.2, 0.33, 0.21);
uniform vec3 high_col = vec3(0.37, 0.42, 0.23);
uniform float tint_span_m = 22.0;     // full tint this far above / below h_mid
uniform float shade_k = 0.38;
uniform float minor_m = 2.0;          // contour interval
uniform float major_every = 5.0;      // every 5th line (10 m) a little stronger
uniform vec4 line_col = vec4(0.09, 0.12, 0.05, 0.34);
uniform vec4 major_col = vec4(0.07, 0.09, 0.03, 0.52);
uniform float grid_px = 500.0;        // faint 50 m grid
uniform float grid_alpha = 0.045;
uniform vec3 wood_col = vec3(0.16, 0.24, 0.12);
uniform vec3 pave_col = vec3(0.56, 0.52, 0.45);
uniform vec3 field_col = vec3(0.70, 0.64, 0.38);
// The sea and a ditch (settlement maps): R sea, G ditch, one texel per 4 m.
uniform sampler2D seamap : filter_linear, repeat_disable;
uniform bool sea_on = false;
uniform vec3 sea_col = vec3(0.18, 0.36, 0.5);
uniform vec3 ditch_col = vec3(0.27, 0.21, 0.15);
// A river crossing (field maps): R water (under a bridge too), G the ford's
// shallows, one texel per 2 m.
uniform sampler2D rivmap : filter_linear, repeat_disable;
uniform bool riv_on = false;
uniform vec2 riv_size_px = vec2(1.0);
uniform vec3 ford_col = vec3(0.50, 0.58, 0.54);

// Ground variation, rock and wet sand (set by terrain_layer.gd).
uniform float ppm = 10.0;             // world pixels per metre
uniform vec3 patch_a = vec3(-0.02, 0.04, -0.02); // colour added in lusher patches
uniform vec3 patch_b = vec3(0.05, 0.02, -0.03);  // ... and in drier / stonier ones
uniform float patch_k = 1.0;
uniform vec3 rock_col = vec3(0.5, 0.48, 0.42);
uniform float tree_line = 2.0;        // fraction of the height range above which rock shows (> 1: none)
uniform vec3 sand_col = vec3(0.55, 0.49, 0.36);

varying highp vec2 world;

void vertex() {
	world = VERTEX;
}

highp vec3 node(ivec2 p) {
	vec4 t = texelFetch(hmap, clamp(p, ivec2(0), hmap_size - ivec2(1)), 0);
	highp float h = floor(t.r * 255.0 + 0.5) * 256.0 + floor(t.g * 255.0 + 0.5);
	return vec3(h, t.b, t.a);
}

// Coverage of a line at distance `d` (in line units) given the derivative
// `fw` of those units per pixel; `half_px` is the half width in pixels.
float line_a(highp float d, highp float fw, float half_px) {
	highp float px = d / max(fw, 1e-6);
	return 1.0 - smoothstep(half_px - 0.5, half_px + 0.5, px);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	highp vec2 wm = world / ppm;  // metres
	float n1 = vnoise(wm / 58.0 + vec2(3.1, 7.7));
	float n2 = vnoise(wm / 21.0 + vec2(11.7, 2.3));
	float n3 = vnoise(wm / 3.4 + vec2(5.3, 9.1));
	// Patches of lusher / drier ground, then a fine grain.
	float patchv = (n1 - 0.5) * 1.5 + (n2 - 0.5) * 0.7;
	vec3 col = base_col + (patchv > 0.0 ? patch_a : patch_b) * abs(patchv) * 1.6 * patch_k;
	float mpp = fwidth(wm.x);
	float grain = (n3 - 0.5) * 0.07 + (vnoise(wm / 1.15 + vec2(1.7, 4.1)) - 0.5) * 0.05 * (1.0 - smoothstep(0.25, 0.7, mpp));
	col *= 1.0 + grain;
	float contour_k = 1.0;
	highp float hm_w = 0.0;
	float sea = 0.0;
	float ditch = 0.0;
	if (sea_on) {
		vec2 sv = texture(seamap, world / veg_size_px).rg;
		sea = smoothstep(0.35, 0.65, sv.r);
		ditch = smoothstep(0.3, 0.7, sv.g);
	}
	float ford = 0.0;
	float wet = 0.0;
	if (sea_on) {
		wet = texture(seamap, world / veg_size_px).b;
	}
	if (riv_on) {
		vec3 rw = texture(rivmap, world / riv_size_px).rgb;
		sea = max(sea, smoothstep(0.35, 0.65, rw.r));
		ford = smoothstep(0.3, 0.7, rw.g);
		wet = max(wet, rw.b);
	}
	if (veg_on) {
		vec4 v = texture(vegmap, world / veg_size_px);
		// Forest floor: darker and a little greener under the trees.
		col = mix(col, wood_col, v.r * 0.55);
		// Settlement ground, main streets and the plaza: paving.
		// worn: packed earth mottled, the plaza lighter and scuffed
		float worn = 0.88 + 0.24 * n2 + (n3 - 0.5) * 0.12;
		col = mix(col, pave_col * worn, v.g * 0.45);
		col = mix(col, pave_col * 1.12 * (0.92 + 0.16 * n3), clamp(v.a, 0.0, 1.0) * 0.55);
		// Fields: straw-coloured strips.
		float strip = 0.85 + 0.15 * step(0.5, fract(world.y / 30.0));
		col = mix(col, field_col * strip * (0.92 + 0.16 * n2), v.b * 0.55);
		contour_k = 1.0 - v.g * 0.5;
	}
	// A ditch: dark earth, its floor in shadow.
	col = mix(col, ditch_col, ditch * 0.85);
	contour_k *= 1.0 - max(max(sea, ditch), ford);
	if (terrain_on) {
		highp vec2 tp = world / texel_px;
		highp vec2 f0 = floor(tp);
		highp vec2 fr = tp - f0;
		ivec2 i = ivec2(f0);
		highp vec3 a = node(i);
		highp vec3 b = node(i + ivec2(1, 0));
		highp vec3 c = node(i + ivec2(0, 1));
		highp vec3 d = node(i + ivec2(1, 1));
		highp vec3 v = mix(mix(a, b, fr.x), mix(c, d, fr.x), fr.y);
		highp float hm = v.x * (h_range_m / 65535.0);
		hm_w = hm;
		float shade = (v.y * 255.0 - 128.0) / 160.0;
		float grade = v.z * (255.0 / 255.0) * 0.8;
		// Elevation tint (low ground darker and cooler, high ground paler and
		// warmer), then hill shading from the upper left.
		float e = clamp((hm - h_mid_m) / tint_span_m, -1.0, 1.0);
		vec3 tint = e < 0.0 ? mix(base_col, low_col, -e) : mix(base_col, high_col, e);
		col = col + (tint - base_col);
		// Lit slopes brighten less than shaded ones darken (no washed-out crests).
		col *= 1.0 + shade_k * (shade > 0.0 ? shade * 0.7 : shade) * (1.0 - sea);
		// Slopes darken a little; steep ground and, on hill maps, ground
		// above the tree line turns to bare rock (less in the woods).
		float wood = veg_on ? texture(vegmap, world / veg_size_px).r : 0.0;
		col *= 1.0 - 0.2 * smoothstep(0.08, 0.45, grade) * (1.0 - sea);
		float hf = hm / h_range_m;
		float above = smoothstep(tree_line, tree_line + 0.12, hf + (n2 - 0.5) * 0.18);
		float rock = max(smoothstep(0.2, 0.5, grade + (n2 - 0.5) * 0.12), above * 0.7);
		rock *= (1.0 - wood * 0.7) * (1.0 - sea) * (1.0 - ford);
		col = mix(col, rock_col * (0.88 + 0.24 * n3) * (1.0 + shade_k * shade * 0.8), rock * 0.78);
		// Contours at h_base + (k + 0.5) * minor_m: the plain (the commonest
		// height) lies midway between two lines, never on one.
		highp float lv = (hm - h_base_m) / minor_m;
		highp float fw = fwidth(lv);
		highp float dist = abs(fract(lv) - 0.5);
		float k = floor(lv);
		bool major = abs(mod(k, major_every) - floor(major_every * 0.5)) < 0.5;
		// Fade where lines would be packed tighter than ~6 px (minor) or
		// ~8 px apart (major), so a zoomed-out hill is shaded, not hatched.
		if (major) {
			float fade = 1.0 - smoothstep(0.35, 0.6, fw);
			col = mix(col, major_col.rgb, major_col.a * contour_k * fade * line_a(dist, fw, 0.75));
		} else {
			float fade = 1.0 - smoothstep(0.1, 0.17, fw);
			col = mix(col, line_col.rgb, line_col.a * contour_k * fade * line_a(dist, fw, 0.5));
		}
	}
	// Wet sand along the banks and the shore: darker, sandy, ragged edge.
	if (wet > 0.0) {
		float w2 = clamp(wet * (0.75 + 0.6 * n3), 0.0, 1.0) * (1.0 - sea) * (1.0 - ford);
		col = mix(col, sand_col * (0.9 + 0.2 * n2), w2 * 0.8);
		col *= 1.0 - 0.18 * w2;
	}
	if ((sea_on || riv_on) && sea > 0.0) {
		// Water: depth tint (the river bed lies below the plain), two
		// scrolling ripple layers, glints, and a light animated band of
		// foam along the shore.
		float t = TIME;
		float depth = terrain_on && riv_on ? clamp((h_base_m - hm_w) / 2.2, 0.0, 1.0) : 0.5;
		float r1 = vnoise(wm / 7.0 + vec2(t * 0.30, t * 0.10));
		float r2 = vnoise(wm / 2.9 + vec2(-t * 0.21, t * 0.33) + 17.0);
		float rip = r1 * 0.6 + r2 * 0.4;
		vec3 water = mix(sea_col * 1.1, sea_col * 0.74, depth) * (0.9 + 0.2 * rip);
		float glint = smoothstep(0.74, 0.9, rip) * (0.5 + 0.5 * sin(t * 1.7 + wm.x * 0.9 + wm.y * 0.6));
		water += vec3(0.5, 0.58, 0.6) * glint * 0.2;
		col = mix(col, water, sea);
		float foam = sea * (1.0 - sea) * 4.0;
		foam *= 0.75 + 0.25 * sin(t * 1.3 + wm.x * 0.5 + wm.y * 0.35);
		col = mix(col, vec3(0.88, 0.92, 0.9), foam * 0.45);
	}
	if (riv_on && ford > 0.0) {
		// The ford: pale shallows over a pale gravel bed, ripples running
		// with the current, and a light edge where it meets the deep water.
		float t = TIME;
		float gravel = 0.5 + 0.5 * sin(wm.x * 2.0 + sin(wm.y * 2.4) * 1.9) * sin(wm.y * 1.7 + wm.x * 0.5);
		vec3 bed = mix(vec3(0.46, 0.64, 0.6), sand_col * 1.05, 0.3);
		vec3 shallow = bed * (0.94 + 0.1 * gravel);
		col = mix(col, shallow, ford * 0.94);
		float cur = vnoise(vec2(wm.x * 0.55 - t * 0.6, wm.y * 1.7) + 3.0);
		float cur2 = vnoise(vec2(wm.x * 1.3 - t * 0.9, wm.y * 3.1) + 9.0);
		float rp = smoothstep(0.62, 0.86, cur * 0.6 + cur2 * 0.4);
		col = mix(col, vec3(0.92, 0.97, 0.96), rp * ford * 0.26);
		float lip = ford * (1.0 - ford) * 4.0;
		col = mix(col, vec3(0.85, 0.9, 0.88), lip * 0.35);
	}
	// Faint 50 m grid, about one pixel wide at any zoom.
	highp vec2 g = world / grid_px;
	highp vec2 gd = abs(fract(g - 0.5) - 0.5);
	highp vec2 gw = fwidth(g);
	float ga = max(line_a(gd.x, gw.x, 0.5), line_a(gd.y, gw.y, 0.5));
	col = mix(col, vec3(1.0), grid_alpha * ga);
	COLOR = vec4(col, 1.0);
}
