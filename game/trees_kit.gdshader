shader_type canvas_item;
// Kit trees (game/tree_layer.gd, the woods and orchards; ground cover keeps trees.gdshader): one MultiMesh,
// every instance a quad carrying a battle kit tree / bush / palm (assets/battlekit atlas) turned by the
// instance's angle. Per instance custom data (x, y, radius in world px; w = kind + 8 x shade + 32 x
// rotation step), as the old shader. High: albedo + normal atlas, lit by the NW key (game/battle_look.gd
// values) with rim and outline, tinted toward the ground palette's tree colours, the cast shadow sampled
// from the piece's own silhouette displaced to the south-east. Low: the pre-lit atlas, no normals.
// Canopies fade where soldiers stand under them (occupancy texture, 4 m cells).
// The oblique view (tabletop pass 3, game/board_view.gd): the tree stands up at its foot's board point, the crown
// unturned above a trunk drawn here (the stand-in until the oblique kit sheet's trees), no cast shadow of its own
// (the ground's crown shadows lie under it), each part faded by the men on the ground it hides. The instances are sorted by y (farther
// first) in game/tree_layer.gd.
#include "res://game/board_view.gdshaderinc"
#include "res://game/weather.gdshaderinc"

uniform sampler2D albedo_tex : filter_linear, repeat_disable;
uniform sampler2D nrm_tex : filter_linear, repeat_disable;
uniform sampler2D low_tex : filter_linear, repeat_disable;
uniform sampler2D occ : filter_linear, repeat_disable;
uniform bool is_low = false;
uniform vec2 occ_size_px = vec2(1.0);
uniform vec4 rects[64];
uniform vec4 anch[64];          // piece centre offset and size (metres)
uniform float pidx[32];         // piece by kind * 4 + shade
uniform vec3 shade0 = vec3(0.15, 0.3, 0.13);
uniform vec3 shade1 = vec3(0.19, 0.35, 0.15);
uniform vec3 shade2 = vec3(0.12, 0.25, 0.12);
uniform float fade_to = 0.28;
uniform float tint_k = 0.6;
uniform float shadow_str = 0.42;
uniform vec3 light_dir = vec3(-0.55, -0.50, 0.67);
uniform float amb = 0.50;
uniform float key = 0.88;
uniform float rim = 0.22;
uniform float outline = 0.55;
uniform float sat = 1.22;
uniform float contrast = 1.12;
uniform float palm_lo = 100.0;
uniform float palm_hi = -1.0;
uniform float ob_tree = 0.0;   // the oblique view with the kit sheet: rects / anch are its sprites (anch: size px, anchor px)

varying vec2 world;
varying vec2 q;
varying vec2 qoff;
varying vec3 tint;
varying float piece;
varying float var_l;
varying vec2 rcs;
varying float tk;
varying vec3 v_trunk;   // the oblique view: trunk x, top y, foot y in q (0 none)

const float M = 1.55;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	float w = cd.w;
	float kind = mod(w, 8.0);
	float sh = mod(floor(w / 8.0), 4.0);
	float rot = floor(w / 32.0) * 0.7854 + hash(cd.x * 0.173 + cd.y * 0.291) * 0.5;
	piece = floor(pidx[int(kind) * 4 + int(sh)] + 0.5);
	vec4 an = anch[int(piece)];
	float s = cd.z * 2.16 / an.z;
	vec2 size = vec2(an.z, an.w) * s;
	vec2 off = an.xy * s;
	rcs = vec2(cos(rot), sin(rot));
	vec2 loc = off + VERTEX * 0.5 * M * size;
	vec2 R = vec2(loc.x * rcs.x - loc.y * rcs.y, loc.x * rcs.y + loc.y * rcs.x);
	q = VERTEX * 0.5 * M + 0.5;
	VERTEX = cd.xy + R;
	world = VERTEX;
	vec2 so = vec2(0.8, 1.0) * cd.z * 0.6;
	qoff = vec2(so.x * rcs.x + so.y * rcs.y, -so.x * rcs.y + so.y * rcs.x) / size;
	v_trunk = vec3(0.0);
	if (ob_on > 0.5 && ob_tree > 0.5) {
		// The kit sheet's tree at its foot: the sprite scaled so its width is the crown's (as the top-down piece's).
		vec2 q01 = (q - 0.5) / M + 0.5;   // (VERTEX is already placed here: the quad's corner from q)
		float f = cd.z * 2.16 / max(an.x, 1.0);
		vec2 off2 = (q01 * an.xy - an.zw) * f;
		VERTEX = ob_board(cd.xy) + off2;
		q = q01;
		rcs = vec2(1.0, 0.0);
		qoff = vec2(0.0);
		world = cd.xy + vec2(off2.x, min(off2.y, 0.0) / OB_COS);
	} else if (ob_on > 0.5) {
		// Upright: the crown's centre 1.15 radii above the foot, unturned; the trunk from it down to the foot.
		float rise = cd.z * 1.15;
		rcs = vec2(1.0, 0.0);
		VERTEX = ob_board(cd.xy) + vec2(loc.x, loc.y - rise);
		// The fade samples the ground this part of the tree hides (behind it, north of its foot), so men behind
		// a tree show through as men under a canopy do in the top view.
		world = cd.xy + vec2(loc.x, min(loc.y - rise, 0.0) / OB_COS);
		qoff = vec2(0.0);
		vec2 qc = vec2(0.5) - off / size;
		v_trunk = vec3(qc.x, qc.y, qc.y + rise / size.y);
	}
	tint = sh < 0.5 ? shade0 : (sh < 1.5 ? shade1 : shade2);
	tk = (piece >= palm_lo && piece <= palm_hi) ? 0.15 : tint_k;
	var_l = 0.92 + 0.16 * hash(float(INSTANCE_ID) * 0.37 + cd.x * 0.011);
}

vec4 samp(vec2 uv) {
	if (is_low) {
		return texture(low_tex, uv);
	}
	return texture(albedo_tex, uv);
}

vec2 atlas_uv(vec4 r, vec2 qq) {
	return r.xy + clamp(qq, vec2(0.0), vec2(1.0)) * r.zw;
}

float cov(vec2 qq, vec4 r) {
	if (qq.x < 0.0 || qq.y < 0.0 || qq.x > 1.0 || qq.y > 1.0) {
		return 0.0;
	}
	return samp(atlas_uv(r, qq)).a;
}

void fragment() {
	vec4 r = rects[int(piece)];
	float o = texture(occ, world / occ_size_px).r;
	float fade = mix(1.0, fade_to, smoothstep(0.05, 0.5, o));
	float a = cov(q, r);
	float sa = (cov(q - qoff, r) + cov(q - qoff * 0.55, r)) * 0.5 * shadow_str;
	vec3 col = vec3(0.0);
	if (a > 0.01) {
		vec2 uv = atlas_uv(r, q);
		vec4 alb = samp(uv);
		vec3 base = alb.rgb;
		float lum = dot(base, vec3(0.3, 0.59, 0.11));
		vec3 tinted = lum * tint * 3.2;
		base = mix(base, tinted, tk) * var_l;
		base = wx_veg(base);
		base = mix(base, vec3(0.9, 0.93, 0.99) * (0.8 + 0.4 * lum), wx_surf.y * 0.62 * (0.35 + 0.65 * (1.0 - q.y)));
		if (is_low) {
			col = base;
		} else {
			vec4 n = texture(nrm_tex, uv);
			vec2 nxy = n.rg * 2.0 - 1.0;
			float nz = sqrt(max(1.0 - dot(nxy, nxy), 0.0));
			vec2 ns = nxy.x * vec2(rcs.x, rcs.y) + nxy.y * vec2(rcs.y, -rcs.x);
			vec3 nrm = vec3(ns, nz);
			vec3 L = normalize(light_dir);
			float diff = clamp(dot(nrm, L), 0.0, 1.0);
			float hemi = 0.5 + 0.5 * nz;
			float lf = (amb * (0.7 + 0.3 * hemi) + key * diff) / (amb + key * L.z);
			col = base * lf;
			vec2 px = 1.5 / vec2(textureSize(nrm_tex, 0));
			float hn = (texture(nrm_tex, uv + vec2(px.x, 0.0)).b + texture(nrm_tex, uv - vec2(px.x, 0.0)).b
				+ texture(nrm_tex, uv + vec2(0.0, px.y)).b + texture(nrm_tex, uv - vec2(0.0, px.y)).b) * 0.25;
			col += rim * clamp((n.b - hn) * 28.0, 0.0, 1.0) * vec3(1.0, 0.95, 0.8);
			col *= 1.0 - outline * 0.7 * (1.0 - smoothstep(0.55, 0.98, a));
			float l2 = dot(col, vec3(0.3, 0.59, 0.11));
			col = mix(vec3(l2), col, sat);
			col = (col - 0.5) * contrast + 0.5;
		}
	}
	float ca = a * fade;
	float sf = sa * fade * (1.0 - a);
	float al = ca + sf * (1.0 - ca);
	vec3 outc = al > 0.0 ? clamp(col, 0.0, 1.0) * ca / al : vec3(0.0);
	if (v_trunk.z > 0.0) {
		// The oblique view's trunk, under the crown: bark lit on its left.
		float tw = 0.035 * (1.0 + 0.6 * (q.y - v_trunk.y) / max(v_trunk.z - v_trunk.y, 0.01));
		float dx = q.x - v_trunk.x;
		float ta = (1.0 - smoothstep(tw * 0.8, tw, abs(dx))) * step(v_trunk.y, q.y) * (1.0 - smoothstep(v_trunk.z - 0.01, v_trunk.z, q.y));
		vec3 bark = vec3(0.30, 0.22, 0.15) * (dx < 0.0 ? 1.2 : 0.8);
		float ab = ta * fade;
		float al2 = ca + ab * (1.0 - ca);
		outc = al2 > 0.0 ? (clamp(col, 0.0, 1.0) * ca + bark * ab * (1.0 - ca)) / al2 : vec3(0.0);
		al = al2;
	}
	COLOR = vec4(outc, al);
}
