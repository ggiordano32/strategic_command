shader_type canvas_item;
// Battlefield ground: a calm topographic-map look drawn in one pass from a
// height texture built once per battle (game/terrain_layer.gd).
//
// Texture (RGBA8, one texel per 2 m node, nearest / texelFetch only, no
// float textures and no reliance on filtering precision):
//   R, G  height, 16 bits (R high byte), 0..65535 over 0..h_range_m metres
//   B     hill shade: 128 = flat; (B - 128) / 160 = relative brightness
//   A     reserved (vegetation later)
// The four nodes around a fragment are decoded and interpolated here
// (manual bilinear in highp), so contours are exact and stable when panning
// and zooming. Contour lines keep a constant screen width via fwidth() and
// fade out where they would crowd together when zoomed far out.

uniform sampler2D hmap : filter_nearest, repeat_disable;
uniform ivec2 hmap_size = ivec2(2, 2);
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
		// Subtle elevation tint, then soft hill shading.
		float e = clamp((hm - h_mid_m) / tint_span_m, -1.0, 1.0);
		col = e < 0.0 ? mix(base_col, low_col, -e) : mix(base_col, high_col, e);
		col *= 1.0 + shade_k * shade;
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
			col = mix(col, major_col.rgb, major_col.a * fade * line_a(dist, fw, 0.75));
		} else {
			float fade = 1.0 - smoothstep(0.1, 0.17, fw);
			col = mix(col, line_col.rgb, line_col.a * fade * line_a(dist, fw, 0.5));
		}
	}
	// Faint 50 m grid, about one pixel wide at any zoom.
	highp vec2 g = world / grid_px;
	highp vec2 gd = abs(fract(g - 0.5) - 0.5);
	highp vec2 gw = fwidth(g);
	float ga = max(line_a(gd.x, gw.x, 0.5), line_a(gd.y, gw.y, 0.5));
	col = mix(col, vec3(1.0), grid_alpha * ga);
	COLOR = vec4(col, 1.0);
}
