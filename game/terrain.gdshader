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
//   A     unused
// Ground features texture (RGBA8, one texel per 4 m cell, linear filter):
//   R woods (tree density / 3), G inside a settlement, B farm field,
//   A 0.5 main street / 1.0 plaza.
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

varying highp vec2 world;

void vertex() {
	world = VERTEX;
}

highp vec3 node(ivec2 p) {
	vec4 t = texelFetch(hmap, clamp(p, ivec2(0), hmap_size - ivec2(1)), 0);
	highp float h = floor(t.r * 255.0 + 0.5) * 256.0 + floor(t.g * 255.0 + 0.5);
	return vec3(h, t.b, 0.0);
}

// Coverage of a line at distance `d` (in line units) given the derivative
// `fw` of those units per pixel; `half_px` is the half width in pixels.
float line_a(highp float d, highp float fw, float half_px) {
	highp float px = d / max(fw, 1e-6);
	return 1.0 - smoothstep(half_px - 0.5, half_px + 0.5, px);
}

void fragment() {
	vec3 col = base_col;
	float contour_k = 1.0;
	float sea = 0.0;
	float ditch = 0.0;
	if (sea_on) {
		vec2 sv = texture(seamap, world / veg_size_px).rg;
		sea = smoothstep(0.35, 0.65, sv.r);
		ditch = smoothstep(0.3, 0.7, sv.g);
	}
	float ford = 0.0;
	if (riv_on) {
		vec2 rw = texture(rivmap, world / riv_size_px).rg;
		sea = max(sea, smoothstep(0.35, 0.65, rw.r));
		ford = smoothstep(0.3, 0.7, rw.g);
	}
	if (veg_on) {
		vec4 v = texture(vegmap, world / veg_size_px);
		// Forest floor: darker and a little greener under the trees.
		col = mix(col, wood_col, v.r * 0.55);
		// Settlement ground, main streets and the plaza: paving.
		col = mix(col, pave_col, v.g * 0.45);
		col = mix(col, pave_col * 1.12, clamp(v.a, 0.0, 1.0) * 0.55);
		// Fields: straw-coloured strips.
		float strip = 0.85 + 0.15 * step(0.5, fract(world.y / 30.0));
		col = mix(col, field_col * strip, v.b * 0.55);
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
		float shade = (v.y * 255.0 - 128.0) / 160.0;
		// Elevation tint (low ground darker and cooler, high ground paler and
		// warmer), then hill shading from the upper left.
		float e = clamp((hm - h_mid_m) / tint_span_m, -1.0, 1.0);
		vec3 tint = e < 0.0 ? mix(base_col, low_col, -e) : mix(base_col, high_col, e);
		col = col + (tint - base_col);
		// Lit slopes brighten less than shaded ones darken (no washed-out crests).
		col *= 1.0 + shade_k * (shade > 0.0 ? shade * 0.7 : shade) * (1.0 - sea);
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
	if ((sea_on || riv_on) && sea > 0.0) {
		// Water: flat colour with a slow ripple and a light band of foam
		// along the shore.
		highp vec2 wv = world / 90.0;
		float rip = 0.5 + 0.5 * sin(wv.x * 1.7 + sin(wv.y * 2.3) * 1.3) * sin(wv.y * 1.1);
		vec3 water = sea_col * (0.94 + 0.1 * rip);
		col = mix(col, water, sea);
		float foam = sea * (1.0 - sea) * 4.0;
		col = mix(col, vec3(0.88, 0.92, 0.9), foam * 0.45);
	}
	if (riv_on && ford > 0.0) {
		// The ford: pale shallows over a gravel bed, ripples across the
		// current and a light edge where it meets the deep water.
		highp vec2 fv = world / 14.0;
		float gravel = 0.5 + 0.5 * sin(fv.x * 2.9 + sin(fv.y * 3.7) * 1.9) * sin(fv.y * 2.3 + fv.x * 0.7);
		vec3 shallow = ford_col * (0.93 + 0.12 * gravel);
		col = mix(col, shallow, ford * 0.92);
		float wv = sin(world.x / 7.0 + sin(world.y / 19.0) * 2.4);
		float rip = smoothstep(0.7, 0.98, wv) * (0.6 + 0.4 * sin(world.y / 5.0));
		col = mix(col, vec3(0.9, 0.95, 0.94), rip * ford * 0.25);
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
