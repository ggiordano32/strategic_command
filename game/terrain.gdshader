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
// The oblique view (tabletop pass 3, game/board_view.gd): the rectangle covers the field's board area and each pixel
// finds the ground point under it (ob_world: the board transform inverted, the hills lifted toward the camera); the
// rest of the shading is the same, in that point's world coordinates. Outside the field: transparent.
#include "res://game/board_view.gdshaderinc"

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
uniform float terrace = 0.0;          // diorama: stepped height bands (sculpted foam), lit / shaded risers, slope tone
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
// Splatted ground (battle look, game/battle_look.gd; tools/battlekit/pack_ground.py tiles, 64 m a tile):
// a tile (grass, or dry grass on arid palettes) modulates the palette colour, dirt for settlement ground,
// streets and plazas, plough for fields, rock on slopes and above the tree line, sand along water. At most
// four tiles are read per pixel in practice (ground + one or two of the others). Off on Graphics Low.
uniform bool splat_on = false;
uniform sampler2D tile_grass : filter_linear_mipmap, repeat_enable;
uniform sampler2D tile_dirt : filter_linear_mipmap, repeat_enable;
uniform sampler2D tile_rock : filter_linear_mipmap, repeat_enable;
uniform sampler2D tile_sand : filter_linear_mipmap, repeat_enable;
uniform sampler2D tile_plough : filter_linear_mipmap, repeat_enable;
uniform vec3 grass_mean = vec3(0.39, 0.49, 0.235);
uniform float splat_sat = 1.0;
// The painterly ground (2026-10-27): grass and earth patches in two octaves (one on Low), a brushed grain
// along the hill shade's light, and the woods' canopy drawn as clumped crowns (rounded clusters whose size
// follows the vegetation density, each with a soft shadow to the lower right and a darker scalloped rim).
// View only: the crowns read the same density the sim's cover reads and write nothing back.
uniform vec3 crown_a = vec3(0.15, 0.30, 0.13);
uniform vec3 crown_b = vec3(0.19, 0.35, 0.15);
uniform vec3 earth_col = vec3(0.40, 0.36, 0.22);
uniform float crown_cell = 5.5;       // metres: one crown per cell (jittered), radius ~45 % of it
// The terrain board (tabletop pass 2, 2026-10-29; diorama look only, game/terrain_layer.gd sets `board`): flock and static-grass
// tufts on open ground, felt under the woods, sand-strip streets, resin water. View only.
uniform bool board = false;
uniform bool tufts_on = false;        // static-grass tufts (High only)
uniform bool resin_on = false;        // glossy resin water edge and sheen (High only)
uniform vec3 felt_col = vec3(0.15, 0.27, 0.11);
// Graphics Low (game/quality.gd): no noise patches / grain / rock mottling, still water, plain ford.
uniform bool low = false;

varying highp vec2 vpos;   // world px (the top view) or board px (the oblique view)

void vertex() {
	vpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
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

// Flock: short specks of coloured fibre on the board, a colour multiplier. The cell is snapped to an octave of
// the pixel size (about 1.6 px), so a grain never drops under a pixel; it fades away when far out.
vec3 flock_mul(vec2 wm, float mpp) {
	float amp = 1.0 - smoothstep(1.3, 2.6, mpp);
	if (amp < 0.01) {
		return vec3(1.0);
	}
	float cell = 0.16 * exp2(ceil(log2(max(mpp / 0.1, 1.0))));
	vec3 acc = vec3(1.0);
	for (int l = 0; l < 2; l++) {
		// two grids of different size and turn, so the specks do not read as a lattice
		vec2 w = l == 0 ? wm : vec2(wm.x * 0.8 - wm.y * 0.6, wm.x * 0.6 + wm.y * 0.8) + 13.7;
		float cl = l == 0 ? cell : cell * 1.43;
		vec2 q = w / cl;
		vec2 id = floor(q);
		vec2 f = fract(q) - 0.5;
		float h = hash12(id + vec2(7.7 + float(l) * 20.0, 1.9));
		float h2 = hash12(id + vec2(31.1, 12.3 + float(l) * 9.0));
		float h3 = hash12(id + vec2(3.9, 44.4));
		float rad = 0.2 + 0.2 * hash12(id + vec2(70.1, 3.3));
		float d = length(f - (vec2(h2, h3) - 0.5) * 0.5);
		float spk = (1.0 - smoothstep(rad - 0.07, rad + 0.05, d)) * step(0.45, h);
		vec3 m = h2 < 0.45 ? vec3(0.68, 0.9, 0.62) : (h2 < 0.86 ? vec3(0.98, 1.28, 0.7) : vec3(1.4, 1.2, 0.66));
		acc = mix(acc, acc * m, spk * 0.95 * amp);
	}
	return acc;
}

// Static-grass tufts: a few thin vertical blades (a stroke each, lighter towards the tip and on the lit left
// side) in sparse jittered 0.9 m cells. x = coverage, y = brightness. Only close up (fades 0.3..0.5 m a pixel).
vec2 tuft_at(vec2 wm, float mpp) {
	float amp = 1.0 - smoothstep(0.3, 0.5, mpp);
	if (amp < 0.01) {
		return vec2(0.0);
	}
	float cs = 0.9;
	vec2 id = floor(wm / cs);
	vec2 p = (wm / cs - id) * cs;
	float h = hash12(id + vec2(61.3, 9.1));
	if (h > 0.24) {
		return vec2(0.0);
	}
	float bx = (0.28 + 0.44 * hash12(id + vec2(2.2, 71.7))) * cs;
	float by = (0.5 + 0.3 * hash12(id + vec2(8.8, 5.5))) * cs;
	float hw = max(0.02, mpp * 0.5);
	float cov = 0.0;
	float br = 1.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i) - 1.0;
		float len = (0.2 + 0.12 * hash12(id + vec2(float(i) * 3.3, 19.9))) ;
		float lean = fi * 0.07 + (hash12(id + vec2(float(i), 55.5)) - 0.5) * 0.05;
		float ty = (by - p.y) / len;
		float cx = bx + fi * 0.045 + lean * clamp(ty, 0.0, 1.0);
		float w = hw * (1.0 - 0.55 * clamp(ty, 0.0, 1.0));
		float c = (1.0 - smoothstep(w * 0.6, w * 1.2, abs(p.x - cx))) * step(0.0, ty) * step(ty, 1.0);
		if (c > cov) {
			cov = c;
			br = 0.95 + 0.4 * clamp(ty, 0.0, 1.0) + (fi < 0.0 ? 0.18 : 0.0) + (p.x < cx ? 0.12 : 0.0);
		}
	}
	return vec2(cov * amp, br);
}

// Nearest crown at p (metres) for a wood of density vr (0..1): x = how far inside the crown (metres, 0 at
// its rim), y = a per-crown random number, zw = the offset from the crown's centre over its radius.
// 3 x 3 jittered cells; the same hash in game/tree_layer.gd (crown_at) keeps the tree sprites on the crowns.
vec4 crown_at(vec2 p, float vr) {
	vec2 cell = floor(p / crown_cell);
	float best = -9.0;
	vec4 out_v = vec4(-9.0, 0.0, 0.0, 0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = cell + vec2(float(i), float(j));
			float hx = hash12(c + vec2(17.3, 3.1));
			float hy = hash12(c + vec2(5.7, 29.9));
			float hr = hash12(c + vec2(41.1, 13.7));
			vec2 ctr = (c + 0.5 + (vec2(hx, hy) - 0.5) * 0.7) * crown_cell;
			float r = crown_cell * (0.46 + 0.14 * hr) * (0.55 + 0.6 * vr);
			vec2 dv = p - ctr;
			float ins = r - length(dv);
			if (ins > best) {
				best = ins;
				out_v = vec4(ins, hr, dv / r);
			}
		}
	}
	return out_v;
}

void fragment() {
	highp vec2 world = vpos;
	float ob_in = 1.0;
	if (ob_on > 0.5) {
		world = ob_world(vpos);
		vec2 ob_e = min(world, ob_field - world);
		ob_in = step(0.0, min(ob_e.x, ob_e.y));
	}
	highp vec2 wm = world / ppm;  // metres
	float n1 = 0.5;
	float n2 = 0.5;
	float n3 = 0.5;
	if (!low) {
		n1 = vnoise(wm / 58.0 + vec2(3.1, 7.7));
		n2 = vnoise(wm / 21.0 + vec2(11.7, 2.3));
		n3 = vnoise(wm / 3.4 + vec2(5.3, 9.1));
	}
	// Patches of lusher / drier ground, then a fine grain.
	float patchv = (n1 - 0.5) * 1.5 + (n2 - 0.5) * 0.7;
	vec3 col = base_col + (patchv > 0.0 ? patch_a : patch_b) * abs(patchv) * 1.6 * patch_k;
	float mpp = fwidth(wm.x);
	// Painted patches: lush grass and bare earth, two octaves (one on Low), tinted from the palette.
	vec2 wq = wm + vec2(n3 - 0.5, n2 - 0.5) * 6.0;
	float pm = vnoise(wm / 17.0 + vec2(2.3, 8.1));
	if (!low) {
		pm = pm * 0.62 + vnoise(wq / 6.5 + vec2(13.1, 4.7)) * 0.38;
	}
	float earthm = smoothstep(0.56, 0.68, pm);
	float lushm = 1.0 - smoothstep(0.30, 0.42, pm);
	col = mix(col, earth_col * (0.92 + 0.16 * n2), earthm * 0.34 * patch_k);
	col *= 1.0 + 0.07 * lushm * patch_k;
	float grain = 0.0;
	if (!low) {
		// Brush strokes, long along the hill shade's light (upper left to lower right).
		vec2 bu = vec2(dot(wm, vec2(0.7071, 0.7071)), dot(wm, vec2(-0.7071, 0.7071)));
		float bs = vnoise(vec2(bu.x / 9.0, bu.y / 0.8) + vec2(7.7, 1.3)) * 0.65 + vnoise(vec2(bu.x / 4.0, bu.y / 0.45) + vec2(2.9, 6.1)) * 0.35;
		grain += (bs - 0.5) * 0.085 * (1.0 - smoothstep(0.2, 0.55, mpp));
	}
	if (!low) {
		grain += (n3 - 0.5) * 0.07 + (vnoise(wm / 1.15 + vec2(1.7, 4.1)) - 0.5) * 0.05 * (1.0 - smoothstep(0.25, 0.7, mpp));
	}
	col *= 1.0 + grain;
	bool splat = splat_on && !low;
	if (splat) {
		vec3 gt = texture(tile_grass, wm / 64.0).rgb;
		col *= mix(vec3(1.0), clamp(gt / grass_mean, vec3(0.55), vec3(1.55)), 0.85);
	}
	float contour_k = 1.0;
	highp float hm_w = 0.0;
	float sea = 0.0;
	float ditch = 0.0;
	float wr = 0.0;   // the raw water mask (0.5 = the shore line), for the resin edge
	if (sea_on) {
		vec2 sv = texture(seamap, world / veg_size_px).rg;
		wr = sv.r;
		sea = smoothstep(0.35, 0.65, sv.r);
		ditch = smoothstep(0.3, 0.7, sv.g);
	}
	float ford = 0.0;
	float wet = 0.0;
	float pave_m = 0.0;     // streets, plaza and paved settlement ground (no flock)
	float felt_m = 0.0;     // under the woods
	float rock_o = 0.0;
	if (sea_on) {
		wet = texture(seamap, world / veg_size_px).b;
	}
	if (riv_on) {
		vec3 rw = texture(rivmap, world / riv_size_px).rgb;
		wr = max(wr, rw.r);
		sea = max(sea, smoothstep(0.35, 0.65, rw.r));
		ford = smoothstep(0.3, 0.7, rw.g);
		wet = max(wet, rw.b);
	}
	float wfw = fwidth(wr);   // (derivatives taken here, in uniform flow, for the resin edge below)
	vec2 wgr = vec2(dFdx(wr), dFdy(wr));
	if (veg_on) {
		vec4 v = texture(vegmap, world / veg_size_px);
		// Forest floor: darker and a little greener under the trees.
		col = mix(col, wood_col, v.r * 0.55);
		if (board) {
			// Model trees on felt: a darker green sheet cut to the wood's outline (a hand-cut wobble), with fibre
			// grain, a thin lighter rim and a dark line outside it.
			float thr = 0.075 + (vnoise(wm / 2.3 + vec2(4.4, 1.1)) - 0.5) * 0.035;
			float dpx = (v.r - thr) / max(fwidth(v.r), 1e-4);
			felt_m = smoothstep(-0.7, 0.7, dpx);
			if (felt_m > 0.0 || dpx > -3.0) {
				float fib = hash12(floor(wm / max(0.12, mpp * 1.2)) + vec2(9.1, 2.7));
				vec3 fc = felt_col * (0.9 + 0.2 * fib) * (0.85 + 0.3 * n2) * (1.0 + 0.5 * clamp(v.r - 0.2, 0.0, 0.3));
				col = mix(col, fc, felt_m * 0.9);
				float rim = (1.0 - smoothstep(0.8, 2.2, dpx)) * felt_m;
				col = mix(col, fc * 1.9 + vec3(0.03), rim * 0.55);
				col *= 1.0 - 0.28 * (1.0 - felt_m) * (1.0 - smoothstep(0.0, 3.0, -dpx)) * step(-3.0, dpx);
			}
		}
		float vgate = smoothstep(0.04, 0.14, v.r);
		vec2 sh_off = vec2(1.5, 1.7);  // metres, the shadow falls to the lower right
		float vr_s = low ? 0.0 : texture(vegmap, (world - sh_off * ppm) / veg_size_px).r;
		if (v.r > 0.03 || vr_s > 0.03) {
			// Crowns: rounded clusters sized by the density, shadow to the lower right, a darker scalloped rim.
			vec4 cw = crown_at(wm, v.r);
			float cm = smoothstep(-0.12, 0.3, cw.x) * smoothstep(0.18, 0.30, v.r);  // discs only where the sim's density is real wood
			if (!low) {
				vec4 cs = crown_at(wm - sh_off, vr_s);
				float sm = smoothstep(-0.2, 0.5, cs.x) * smoothstep(0.04, 0.14, vr_s);
				col *= 1.0 - 0.36 * sm * (1.0 - cm);
			}
			float lit = clamp(-(cw.z + cw.w) * 0.6, -1.0, 1.0);
			vec3 cc = mix(crown_a, crown_b, cw.y) * (0.82 + 0.4 * cw.y);
			cc *= 1.0 + 0.26 * lit + 0.1 * clamp(cw.x * 0.5, 0.0, 1.0);
			float rim = (1.0 - smoothstep(0.0, 0.55, cw.x)) * (0.22 + 0.3 * (1.0 - v.r));
			cc *= 1.0 - rim;
			col = mix(col * (1.0 - 0.2 * vgate), cc, cm * 0.92);
		}
		// Settlement ground, main streets and the plaza: paving.
		// worn: packed earth mottled, the plaza lighter and scuffed
		float worn = 0.88 + 0.24 * n2 + (n3 - 0.5) * 0.12;
		vec3 pv = pave_col * worn;
		vec3 pl = pave_col * 1.12 * (0.92 + 0.16 * n3);
		if (splat && (v.g > 0.02 || v.a > 0.02)) {
			vec3 dt = texture(tile_dirt, wm / 24.0).rgb * 2.0;
			pv = dt * pave_col * 0.95 * worn;
			pl = dt * pave_col * 1.0 * (0.92 + 0.16 * n3);
		}
		if (board) {
			// Streets and plazas as strips of sand: lighter and warmer, with a faint raised edge from the paved mask.
			vec3 sandy = vec3(0.80, 0.69, 0.48) * (0.93 + 0.12 * n3);
			pv = mix(pv, sandy * 0.9, 0.35);
			pl = mix(pl, sandy, 0.45);
			float sa = clamp(v.a, 0.0, 1.0);
			float ed = abs(sa - 0.5) / max(fwidth(sa), 1e-4);
			col = mix(col, col * (1.0 + 0.22 * (0.5 - 0.5 * clamp(dot(normalize(vec2(dFdx(sa), dFdy(sa)) + 1e-6), vec2(-0.7, -0.7)), -1.0, 1.0))), (1.0 - smoothstep(0.6, 2.2, ed)) * step(0.05, sa) * 0.8);
			pave_m = clamp(v.g * 0.7 + sa, 0.0, 1.0);
		}
		col = mix(col, pv, v.g * (splat ? 0.7 : 0.45));
		col = mix(col, pl, clamp(v.a, 0.0, 1.0) * (splat ? 0.75 : 0.55));
		// Fields: straw-coloured strips (ploughed earth with the splatted ground).
		float strip = 0.85 + 0.15 * step(0.5, fract(world.y / 30.0));
		if (splat && v.b > 0.02) {
			vec3 pt = texture(tile_plough, wm / 32.0).rgb * 1.25;
			col = mix(col, pt * strip, v.b * 0.8);
		} else {
			col = mix(col, field_col * strip * (0.92 + 0.16 * n2), v.b * 0.55);
		}
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
		highp float lv0 = (hm - h_base_m) / minor_m;
		highp float hq = h_base_m + floor(lv0 + 0.5) * minor_m;   // the band's own height
		float e = clamp((mix(hm, hq, terrace * 0.8) - h_mid_m) / tint_span_m, -1.0, 1.0);
		vec3 tint = e < 0.0 ? mix(base_col, low_col, -e) : mix(base_col, high_col, e);
		col = col + (tint - base_col);
		// Lit slopes brighten less than shaded ones darken (no washed-out crests).
		// Foam steps: the step tops are flat, so the hill shade fades there and the risers carry the light.
		highp float fw0 = fwidth(lv0);
		float tf0 = 1.0 - smoothstep(0.1, 0.2, fw0);
		float tshade = shade * (1.0 - 0.6 * terrace * tf0);
		col *= 1.0 + shade_k * (tshade > 0.0 ? tshade * 0.7 : tshade * (terrace > 0.0 ? 0.62 : 1.0)) * (1.0 - sea);
		// Slopes darken a little; steep ground and, on hill maps, ground
		// above the tree line turns to bare rock (less in the woods).
		float wood = veg_on ? texture(vegmap, world / veg_size_px).r : 0.0;
		col *= 1.0 - 0.2 * smoothstep(0.08, 0.45, grade) * (1.0 - sea);
		if (terrace > 0.0) {
			// Slope tone: steep grass turns to bare earth before it turns to rock.
			vec3 earth = mix(rock_col, base_col, 0.45) * 0.95;
			col = mix(col, earth * (1.0 + 0.5 * shade), terrace * 0.42 * smoothstep(0.12, 0.34, grade) * (1.0 - sea));
		}
		float hf = hm / h_range_m;
		float above = smoothstep(tree_line, tree_line + 0.12, hf + (n2 - 0.5) * 0.18);
		float rock = max(smoothstep(0.2, 0.5, grade + (n2 - 0.5) * 0.12), above * 0.7);
		rock *= (1.0 - wood * 0.7) * (1.0 - sea) * (1.0 - ford);
		rock_o = rock;
		vec3 rc = rock_col * (0.88 + 0.24 * n3);
		if (splat && rock > 0.02) {
			rc = texture(tile_rock, wm / 24.0).rgb * (rock_col / vec3(0.5)) * 0.95;
		}
		col = mix(col, rc * (1.0 + shade_k * shade * 0.8), rock * 0.78);
		// Contours at h_base + (k + 0.5) * minor_m: the plain (the commonest
		// height) lies midway between two lines, never on one.
		highp float lv = (hm - h_base_m) / minor_m;
		highp float fw = fwidth(lv);
		highp float dist = abs(fract(lv) - 0.5);
		float k = floor(lv);
		if (terrace > 0.0) {
			// Layered-foam steps (tabletop pass 2): flat step tops, a crisp bevelled riser above each step edge, lit
			// on the upper-left faces and shaded on the lower-right ones (the NW hill shade), a pale lip along its
			// top edge and a thin dark shadow line at its foot; fades out where bands crowd.
			float tf = 1.0 - smoothstep(0.1, 0.2, fw);
			float u = fract(lv + 0.5);
			float gate = max(smoothstep(0.02, 0.2, grade), 0.45) * tf * (1.0 - sea);
			highp float fwc = max(fw, 1e-4);
			float rpx = u / fwc;
			float rwpx = clamp(0.2 / fwc, 2.0, 8.0);
			float riser = (1.0 - smoothstep(rwpx - 0.8, rwpx + 0.8, rpx)) * gate;
			float lip = riser * smoothstep(rwpx - 2.4, rwpx - 1.2, rpx);
			float foot = (1.0 - smoothstep(0.7, 2.3, (1.0 - u) / fwc)) * gate * (1.0 - riser);
			// which way the face looks: lit where the ground falls away to the upper left (height rises to the lower right)
			highp vec2 gdir = vec2((b.x - a.x) + (d.x - c.x), (c.x - a.x) + (d.x - b.x));
			float rl = clamp(dot(gdir / (length(gdir) + 1e-3), vec2(0.7071)) * 1.5, -1.0, 1.0);
			col *= 1.0 + terrace * riser * (rl > 0.0 ? 0.26 * rl : 0.42 * rl);
			col = mix(col, vec3(0.86, 0.83, 0.68), terrace * riser * 0.07 * (0.5 + 0.5 * (rl * 0.5 + 0.5)));
			col *= 1.0 + terrace * lip * 0.15;
			col *= 1.0 - terrace * foot * 0.3;
		}
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
	if (board) {
		// Flock on open ground (not on streets, plazas, the felt under woods, water, bare rock or wet sand) and
		// static-grass tufts close up; fields take the flock too, so a field decal's flock square shows it.
		float open_m = (1.0 - pave_m) * (1.0 - sea) * (1.0 - ford) * (1.0 - rock_o * 0.85) * (1.0 - wet * 0.7) * (1.0 - felt_m * 0.8);
		if (open_m > 0.02) {
			col *= mix(vec3(1.0), flock_mul(wm, mpp), open_m);
			if (tufts_on) {
				vec2 tt = tuft_at(wm, mpp);
				if (tt.x > 0.0) {
					col = mix(col, col * vec3(0.94, 1.3, 0.78) * tt.y, tt.x * open_m * 0.85);
				}
			}
		}
	}
	// Wet sand along the banks and the shore: darker, sandy, ragged edge.
	if (wet > 0.0) {
		float w2 = clamp(wet * (0.75 + 0.6 * n3), 0.0, 1.0) * (1.0 - sea) * (1.0 - ford);
		vec3 sc = sand_col * (0.9 + 0.2 * n2);
		if (splat) {
			sc = texture(tile_sand, wm / 20.0).rgb * (sand_col / vec3(0.76, 0.685, 0.49));
		}
		col = mix(col, sc, w2 * 0.8);
		col *= 1.0 - 0.18 * w2;
	}
	if ((sea_on || riv_on) && sea > 0.0) {
		// Water: depth tint (the river bed lies below the plain), two
		// scrolling ripple layers, glints, and a light animated band of
		// foam along the shore.
		float t = TIME;
		float depth = terrain_on && riv_on ? clamp((h_base_m - hm_w) / 2.2, 0.0, 1.0) : 0.5;
		vec3 water = mix(sea_col * 1.1, sea_col * 0.74, depth);
		float foam = sea * (1.0 - sea) * 4.0;
		if (!low) {
			float r1 = vnoise(wm / 7.0 + vec2(t * 0.30, t * 0.10));
			float r2 = vnoise(wm / 2.9 + vec2(-t * 0.21, t * 0.33) + 17.0);
			float rip = r1 * 0.6 + r2 * 0.4;
			water *= 0.9 + 0.2 * rip;
			float glint = smoothstep(0.74, 0.9, rip) * (0.5 + 0.5 * sin(t * 1.7 + wm.x * 0.9 + wm.y * 0.6));
			water += vec3(0.5, 0.58, 0.6) * glint * 0.2;
			foam *= 0.75 + 0.25 * sin(t * 1.3 + wm.x * 0.5 + wm.y * 0.35);
		}
		float wdpx = (wr - 0.5) / max(wfw, 1e-4);   // pixels inside the shore line
		if (board) {
			// Poured resin over a painted bed: the bed shows sandy-teal in the shallows at the rim.
			vec3 bed = mix(sea_col * 1.3 + vec3(0.10, 0.09, 0.02), sand_col * 0.9, 0.3);
			water = mix(water, bed, (1.0 - smoothstep(0.55, 0.98, wr)) * 0.65);
			foam *= 0.25;
		}
		col = mix(col, water, sea);
		col = mix(col, vec3(0.88, 0.92, 0.9), foam * 0.45);
		if (board) {
			// The cut edge where the resin meets the board: a crisp dark meniscus line.
			col *= 1.0 - 0.42 * (1.0 - smoothstep(0.5, 1.5, abs(wdpx)));
			if (resin_on) {
				// Glossy specular band just inside the edge (brighter on the banks facing the lamp, upper left) and
				// a broad stretched sheen over the surface.
				vec2 wn = normalize(wgr + 1e-6);
				float band = smoothstep(1.4, 2.8, wdpx) * (1.0 - smoothstep(5.0, 12.0, wdpx));
				col += vec3(0.8, 0.9, 0.95) * band * (0.22 + 0.4 * clamp(dot(wn, vec2(0.7071, 0.7071)), 0.0, 1.0)) * sea;
				float sh = vnoise(vec2(dot(wm, vec2(0.8, 0.6)) / 46.0, dot(wm, vec2(-0.6, 0.8)) / 6.5) + vec2(3.3, 8.8));
				col += vec3(0.9, 0.95, 1.0) * smoothstep(0.58, 0.78, sh) * 0.16 * sea;
			}
		}
	}
	if (riv_on && ford > 0.0) {
		// The ford: pale shallows over a pale gravel bed, ripples running
		// with the current, and a light edge where it meets the deep water.
		float t = TIME;
		float gravel = 0.5 + 0.5 * sin(wm.x * 2.0 + sin(wm.y * 2.4) * 1.9) * sin(wm.y * 1.7 + wm.x * 0.5);
		vec3 bed = mix(vec3(0.46, 0.64, 0.6), sand_col * 1.05, 0.3);
		vec3 shallow = bed * (0.94 + 0.1 * gravel);
		col = mix(col, shallow, ford * 0.94);
		if (!low) {
			float cur = vnoise(vec2(wm.x * 0.55 - t * 0.6, wm.y * 1.7) + 3.0);
			float cur2 = vnoise(vec2(wm.x * 1.3 - t * 0.9, wm.y * 3.1) + 9.0);
			float rp = smoothstep(0.62, 0.86, cur * 0.6 + cur2 * 0.4);
			col = mix(col, vec3(0.92, 0.97, 0.96), rp * ford * 0.26);
		}
		float lip = ford * (1.0 - ford) * 4.0;
		col = mix(col, vec3(0.85, 0.9, 0.88), lip * 0.35);
	}
	// Faint 50 m grid, about one pixel wide at any zoom.
	highp vec2 g = world / grid_px;
	highp vec2 gd = abs(fract(g - 0.5) - 0.5);
	highp vec2 gw = fwidth(g);
	float ga = max(line_a(gd.x, gw.x, 0.5), line_a(gd.y, gw.y, 0.5));
	col = mix(col, vec3(1.0), grid_alpha * ga);
	if (splat) {
		float lm = dot(col, vec3(0.3, 0.59, 0.11));
		col = clamp(mix(vec3(lm), col, splat_sat), 0.0, 1.0);
	}
	COLOR = vec4(col, ob_in);
}
