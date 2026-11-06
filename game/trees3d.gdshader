shader_type spatial;
// The 3D battle view's trees (game/view3d.gd): each wood / orchard tree a card standing at its foot, facing the camera, cut from the
// oblique kit sheet's tree sprites (as trees_kit.gdshader's oblique branch: the same table, tint and lighting from the sheet's normal
// pass; light_dir the key in screen space, turned by view3d.gd with the camera's yaw against the world lamp's, the screen's upper
// left at the opening yaw). Unshaded (the light is the sheet's), alpha-cut so it writes depth and casts a shadow; the card is built
// from the camera's axes (cam_*), in the shadow pass upright facing the lamp (its shadow the same at every yaw). The canopy thins
// over men under it (the tree layer's occupancy texture).
render_mode unshaded, cull_disabled, world_vertex_coords;
#include "res://game/weather.gdshaderinc"

uniform sampler2D albedo_tex : filter_linear, repeat_disable;
uniform sampler2D nrm_tex : filter_linear, repeat_disable;
uniform sampler2D low_tex : filter_linear, repeat_disable;
uniform sampler2D occ : filter_linear, repeat_disable;
uniform bool is_low = false;
uniform vec2 occ_size_px = vec2(1.0);
uniform vec4 rects[64];
uniform vec4 anch[64];          // the sheet's sprites: size px, anchor px
uniform float pidx[32];         // piece by kind * 4 + shade
uniform vec3 shade0 = vec3(0.15, 0.3, 0.13);
uniform vec3 shade1 = vec3(0.19, 0.35, 0.15);
uniform vec3 shade2 = vec3(0.12, 0.25, 0.12);
uniform float fade_to = 0.28;
uniform float tint_k = 0.6;
uniform vec3 light_dir = vec3(-0.55, -0.50, 0.67);
uniform float amb = 0.50;
uniform float key = 0.88;
uniform float rim = 0.22;
uniform float outline = 0.55;
uniform float sat = 1.22;
uniform float contrast = 1.12;
uniform float palm_lo = 100.0;
uniform float palm_hi = -1.0;
uniform float ppm = 10.0;
uniform vec3 cam_r = vec3(1.0, 0.0, 0.0);
uniform vec3 cam_u = vec3(0.0, 0.766, -0.643);
uniform vec3 cam_b = vec3(0.0, 0.643, 0.766);

varying vec2 world;
varying vec2 q;
varying vec3 tint;
varying float piece;
varying float var_l;
varying float tk;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	float w = cd.w;
	float kind = mod(w, 8.0);
	float sh = mod(floor(w / 8.0), 4.0);
	piece = floor(pidx[int(kind) * 4 + int(sh)] + 0.5);
	vec4 an = anch[int(piece)];
	vec3 foot = MODEL_MATRIX[3].xyz;
	vec2 q01 = vec2(UV.x, 1.0 - UV.y);   // (world_vertex_coords: VERTEX comes in already placed, so the corner is the UV)
	float f = cd.z * 2.16 / max(an.x, 1.0);
	vec2 off = (q01 * an.xy - an.zw) * f / ppm;   // metres in the camera's plane (x right, y down)
	if (dot(INV_VIEW_MATRIX[2].xyz, cam_b) < 0.999) {
		// The shadow pass: upright at the foot, facing the lamp.
		VERTEX = foot + normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z)) * off.x - vec3(0.0, off.y, 0.0);
	} else {
		VERTEX = foot + cam_r * off.x - cam_u * off.y + cam_b * 0.6;
	}
	q = q01;
	world = cd.xy;
	tint = sh < 0.5 ? shade0 : (sh < 1.5 ? shade1 : shade2);
	tk = (piece >= palm_lo && piece <= palm_hi) ? 0.15 : tint_k;
	var_l = 0.92 + 0.16 * hash(cd.x * 0.37 + cd.y * 0.011);
}

vec4 samp(vec2 uv) {
	if (is_low) {
		return texture(low_tex, uv);
	}
	return texture(albedo_tex, uv);
}

void fragment() {
	vec4 r = rects[int(piece)];
	vec2 uv = r.xy + clamp(q, vec2(0.0), vec2(1.0)) * r.zw;
	vec4 alb = samp(uv);
	float a = alb.a;
	vec3 base = alb.rgb;
	float lum = dot(base, vec3(0.3, 0.59, 0.11));
	base = mix(base, lum * tint * 3.2, tk) * var_l;
	base = wx_veg(base);
	base = mix(base, vec3(0.9, 0.93, 0.99) * (0.8 + 0.4 * lum), wx_surf.y * 0.62 * (0.35 + 0.65 * (1.0 - q.y)));
	vec3 col = base;
	if (!is_low) {
		vec4 n = texture(nrm_tex, uv);
		vec2 nxy = n.rg * 2.0 - 1.0;
		float nz = sqrt(max(1.0 - dot(nxy, nxy), 0.0));
		vec3 nrm = vec3(nxy.x, -nxy.y, nz);
		vec3 L = normalize(light_dir);
		float diff = clamp(dot(nrm, L), 0.0, 1.0);
		float hemi = 0.5 + 0.5 * nz;
		float lf = (amb * (0.7 + 0.3 * hemi) + key * diff) / (amb + key * L.z);
		col = base * lf;
		col *= 1.0 - outline * 0.7 * (1.0 - smoothstep(0.55, 0.98, a));
		float l2 = dot(col, vec3(0.3, 0.59, 0.11));
		col = mix(vec3(l2), col, sat);
		col = (col - 0.5) * contrast + 0.5;
	}
	float o = texture(occ, world / occ_size_px).r;
	float fade = mix(1.0, fade_to, smoothstep(0.05, 0.5, o));
	col = clamp(col, vec3(0.0), vec3(1.0));
	ALBEDO = col;
	ALPHA = a * (0.35 + 0.65 * fade);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
