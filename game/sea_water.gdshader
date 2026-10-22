shader_type canvas_item;
// The sea battle's water (game/sea_look.gd; 2026-10-22, owner: "make the naval battle shader look more
// like water"). One full-field pass in world metres (1 px = 1 m at zoom 1).
//  - depth colouring: a baked field (`fld`: R signed distance to the coast, G depth, B steepness,
//    A woods; `aux`: the coast's seaward direction) from the campaign cell's bathymetry (else a
//    shelf from the distance to land): sandy turquoise shallows, the shelf blue, deep and abyss;
//  - waves: two trains running before the wind (swell and chop, their phase warped and grouped by
//    noise so nothing tiles), lit from the north-west as the battle kit is, crests catching the
//    light, whitecaps in a hard wind, a small sun glitter; flat in the shallows and near the shore;
//  - shoreline foam: swash and broken breaker lines on the DRAWN shore (the sim's cell edge refined
//    by sea_shore.gdshaderinc), a band fading with depth, and foam on shoals; a drop shadow under
//    steep coasts;
//  - the diorama look's saturation / contrast (BattleLook), a rim round the board's edge.
// hi = 0 (Graphics Low): the depth colouring, a still shore wash, no waves, no time.

#include "res://game/sea_shore.gdshaderinc"

uniform sampler2D fld : filter_linear, repeat_disable;
uniform sampler2D fld2 : filter_linear, repeat_disable;
uniform vec2 grid_m = vec2(2400.0, 1600.0);
uniform vec2 field_m = vec2(2400.0, 1600.0);
uniform float hi = 1.0;
uniform float t = 0.0;
uniform vec2 wdir = vec2(1.0, 0.0);      // where the wind blows towards (the waves' pattern, eased)
uniform float wstr = 0.8;                // wind strength 0.1 .. 1

uniform vec3 c_sand = vec3(0.62, 0.80, 0.68);   // under half a metre: the sand showing through
uniform vec3 c_shal = vec3(0.40, 0.78, 0.74);   // about 2 m
uniform vec3 c_tq = vec3(0.24, 0.68, 0.72);     // about 7 m
uniform vec3 c_mid = vec3(0.14, 0.47, 0.64);    // about 22 m
uniform vec3 c_blue = vec3(0.11, 0.38, 0.57);   // the shelf, 60 to 150 m
uniform vec3 c_deep = vec3(0.09, 0.30, 0.49);   // 400 m and more
uniform vec3 c_foam = vec3(0.93, 0.97, 0.97);

const vec2 LIGHT_XY = vec2(-0.62, -0.78);       // toward the light (the land layer's)

varying vec2 wp;

void vertex() {
	wp = VERTEX;
}

vec3 water_colour(float d) {
	vec3 c = mix(c_sand, c_shal, smoothstep(0.15, 2.0, d));
	c = mix(c, c_tq, smoothstep(2.0, 7.0, d));
	c = mix(c, c_mid, smoothstep(7.0, 24.0, d));
	c = mix(c, c_blue, smoothstep(24.0, 100.0, d));
	return mix(c, c_deep, smoothstep(100.0, 450.0, d));
}

vec2 rot(vec2 v, float a) {
	float s = sin(a);
	float c = cos(a);
	return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// One wave train at point p: adds its height to h and the gradient to g. dir: where it runs,
// lambda metres, speed m/s, amp. The phase is warped and the amplitude grouped by noise.
void train(vec2 p, vec2 dir, float lambda, float speed, float amp, float idx, float wpp, inout float h, inout vec2 g) {
	float lod = smoothstep(2.0, 6.0, lambda / wpp);
	if (lod <= 0.0) {
		return;
	}
	float k = 6.2831853 / lambda;
	vec2 pp = vec2(-dir.y, dir.x);
	float along = dot(p, dir);
	float across = dot(p, pp);
	float warp = 2.6 * (vnoise(vec2(along, across) / (lambda * 1.7) + vec2(idx * 7.3, 2.1)) - 0.5);
	float ph = along * k - t * speed * k + warp;
	float grp = smoothstep(0.15, 0.85, vnoise(vec2(across / (lambda * 1.5), (along - t * speed * 0.6) / (lambda * 3.2)) + vec2(idx * 3.9, 9.4)));
	float a = amp * (0.30 + 0.70 * grp) * lod;
	h += a * (sin(ph) - 0.12 * cos(2.0 * ph));
	g += dir * (a * k * (cos(ph) + 0.24 * sin(2.0 * ph)));
}

void fragment() {
	vec2 p = wp;
	vec2 fuv = p / grid_m;
	vec2 cuv = clamp(fuv, vec2(0.0), vec2(1.0));
	vec4 f = texture(fld, cuv);
	vec4 f2 = texture(fld2, cuv);
	vec2 gr = f.gb * 2.0 - 1.0;
	float sdf = f.r * 320.0 - 80.0;      // (beyond the field the edge texel goes on: the coast continues)
	float steep = f2.g;
	float dd = sdf + shore_e(p);                     // metres from the drawn shore, water positive
	// Depth: the campaign's bathymetry (fld2.r) capped by a shelf from the distance to the sim's coast
	// (steeper where the land is rugged), a shoal 1.5 m deep (fld.a), nothing on the land itself.
	float ds = max(sdf, 0.0);
	float shelf = 0.4 + ds * (0.05 + 0.30 * steep) + 0.00035 * ds * ds;
	float depth = min(f2.r * f2.r * 1500.0, shelf);
	depth = mix(depth, min(depth, 1.5 + 0.3 * steep), smoothstep(0.30, 0.75, f.a));
	depth *= smoothstep(-8.0, 0.0, sdf);
	float wpp = max(fwidth(p.x) + fwidth(p.y), 0.0001) * 0.7;   // metres per screen pixel
	float dsw = depth;   // (baked 0 on the sim's land, so the strip the drawn shore takes is a few cm of swash)
	vec3 col = water_colour(dsw);
	float foam = 0.0;
	if (hi > 0.5) {
		// Shallows: caustic-like ripples on the bottom.
		float shal = 1.0 - smoothstep(1.5, 9.0, dsw);
		if (shal > 0.01) {
			float cs = vnoise(p / 3.1 + vec2(t * 0.35, -t * 0.22)) * 0.6 + vnoise(p / 1.7 - vec2(t * 0.27, t * 0.31)) * 0.4;
			col += vec3(0.08, 0.11, 0.08) * (cs - 0.5) * shal;
		}
		// Waves before the wind, flat in the shallows and near the shore.
		float damp = smoothstep(2.0, 16.0, dsw) * (0.35 + 0.65 * smoothstep(8.0, 120.0, dd)) * (0.35 + 0.65 * wstr);
		float h = 0.0;
		vec2 g = vec2(0.0);
		vec2 w = normalize(wdir);
		train(p, w, 58.0, 5.8, 0.34, 0.0, wpp, h, g);
		train(p, rot(w, 0.28), 31.0, 4.2, 0.20, 1.0, wpp, h, g);
		train(p, rot(w, -0.34), 8.5, 2.6, 0.085 * (0.5 + 0.5 * wstr), 2.0, wpp, h, g);
		h *= damp;
		g *= damp;
		vec3 n = normalize(vec3(-g * 1.9, 1.0));
		vec3 L = normalize(vec3(LIGHT_XY * 0.8, 0.62));
		float lit = dot(n, L) - L.z;
		col += vec3(0.55, 0.78, 0.88) * lit * 0.24;
		// Crests catch the light: a bright rim on the lit side of the high ridges.
		float crest = smoothstep(0.30, 1.05, h) * (0.55 + 0.45 * clamp(lit * 5.0 + 0.5, 0.0, 1.0));
		col = mix(col, vec3(0.80, 0.94, 0.97), crest * 0.12);
		// Slow patches: gusts darken and roughen stretches of the sea, calms lighten them.
		float gust = vnoise((p - w * t * 3.0) / 210.0 + vec2(5.1, 2.9)) * 0.65 + vnoise((p - w * t * 5.0) / 90.0 + vec2(1.7, 8.3)) * 0.35;
		col *= 1.0 + (gust - 0.5) * 0.16 * smoothstep(10.0, 60.0, dsw);
		// Whitecaps in a hard wind.
		float thr = mix(1.35, 0.78, smoothstep(0.55, 1.0, wstr));
		float cap = smoothstep(thr, thr + 0.22, h + 0.28 * (vnoise(p / 2.3 + vec2(t * 0.4, 0.0)) - 0.5)) * smoothstep(0.45, 0.8, wstr);
		foam = max(foam, cap * 0.55);
		// Sun glitter: sparks on the slopes that face the light.
		vec3 hv = normalize(L + vec3(0.0, 0.0, 1.0));
		float spec = pow(max(dot(n, hv), 0.0), 60.0);
		float spk = smoothstep(0.62, 0.9, vnoise(p / 1.3 + vec2(t * 0.8, t * 0.5)));
		col += vec3(1.0, 0.97, 0.85) * (spec * 0.35 + spec * spk * 0.5) * smoothstep(8.0, 40.0, dsw);
		// Steep coast: its drop shadow lies on the water away from the light.
		float sh = steep * max(dot(gr, -LIGHT_XY), 0.0);
		col *= 1.0 - 0.38 * sh * (1.0 - smoothstep(0.0, 14.0, dd)) * step(0.0, dd);
	} else {
		col *= 1.0 - 0.18 * steep * (1.0 - smoothstep(0.0, 14.0, dd)) * step(0.0, dd);
	}
	// Shore foam on the drawn shore: the swash, and breaker lines fading with depth.
	float band = (1.0 - smoothstep(0.2, 7.0, depth)) * (1.0 - smoothstep(14.0, 34.0, dd));
	if (dd > -1.0 && band > 0.01) {
		float swash;
		float lines = 0.0;
		float lod = 1.0 - smoothstep(2.0, 6.0, wpp);
		if (hi > 0.5) {
			float nn = vnoise(p / 4.5 + vec2(t * 0.25, -t * 0.2));
			swash = (1.0 - smoothstep(0.2, 4.2, dd + 0.5 * sin(t * 1.1 + p.x * 0.07))) * (0.45 + 0.65 * smoothstep(0.25, 0.7, nn));
			float ph = dd / 9.0 + t * 0.22;
			float fr = fract(ph);
			float idx = floor(ph);
			float prof = smoothstep(0.0, 0.1, fr) * (1.0 - smoothstep(0.12, 0.6, fr)) * smoothstep(1.5, 5.0, dd);
			float gap = smoothstep(0.30, 0.62, vnoise(p / 15.0 + vec2(idx * 13.7, idx * 5.3)));
			lines = prof * gap * 0.75 * lod;
		} else {
			swash = (1.0 - smoothstep(0.2, 4.8, dd)) * 0.6;
		}
		foam = max(foam, (swash * 0.85 + lines) * band * (1.0 - 0.35 * steep));
		foam += (1.0 - smoothstep(0.0, 1.4, abs(dd - 0.4))) * 0.5 * band;
	}
	// Foam on a shoal even away from the beach (the sim's shoals, where deep ships ground).
	if (hi > 0.5) {
		float shoal = (1.0 - smoothstep(1.3, 2.3, depth)) * step(1.0, dd);
		float sn = smoothstep(0.62, 0.8, vnoise(p / 7.0 + vec2(t * 0.15, 3.3)));
		foam = max(foam, shoal * sn * 0.22);
	}
	col = mix(col, c_foam, clamp(foam, 0.0, 0.92));
	col = board_edge(col, p, field_m, wpp);
	COLOR = vec4(grade(col, 1.0 + (sat - 1.0) * 0.5, 0.42), 1.0);
}
