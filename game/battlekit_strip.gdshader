shader_type canvas_item;
// Battle kit wall strips (game/battlekit.gd _wall_ring): the mitred wall mesh of a settlement, one mesh drawn
// over the kit's houses and under its gates and towers. The lighting is game/battlekit.gdshader's (keep the
// two in step): the north-west key with the normal turned by the stretch's angle, the culture's stone tint,
// rim and outline. One texture pair per strip (tools/battlekit/pack_strips.py), repeat_enable along the wall
// (UV.x counts tiles, UV.y runs outer edge 0 to inner edge 1); the vertex colour carries the stretch's turn
// (cos, sin) * 0.5 + 0.5. The normal atlas' R,G = normal x,y in the strip's frame (y up = the outer side),
// B = height / 20 m, A = mask class (1 none).

uniform sampler2D albedo_tex : filter_linear, repeat_enable;
uniform sampler2D nrm_tex : filter_linear, repeat_enable;
uniform float culture_i = 0.0;
uniform vec3 stone_tint[8];
uniform vec3 pal_r[8];
uniform vec3 pal_g[8];
uniform vec3 pal_b[8];
uniform vec3 light_dir = vec3(-0.55, -0.50, 0.67);   // screen space (north is -y), towards the light
uniform float amb = 0.66;
uniform float key = 0.55;
// Look parameters, set from game/battle_look.gd: diorama (default) amb 0.50, key 0.88, rim 0.22,
// outline 0.55, sat 1.22, contrast 1.12; painterly the values below (tools/battlekit/mockup.py STYLE).
uniform float rim = 0.05;        // light on convex edges (dry brush)
uniform float outline = 0.24;    // dark line where a piece ends against the ground
uniform float sat = 0.86;
uniform float contrast = 1.04;

varying vec2 rot_cs;

void vertex() {
	rot_cs = COLOR.rg * 2.0 - 1.0;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV);
	if (a.a < 0.01) {
		discard;
	}
	vec4 n = texture(nrm_tex, UV);
	vec2 nxy = n.rg * 2.0 - 1.0;
	float nz = sqrt(max(1.0 - dot(nxy, nxy), 0.0));
	// Piece space (x right, y up = its outer side) to the screen: right -> (c, s), up -> (s, -c).
	vec2 rc = normalize(rot_cs);
	vec2 ns = nxy.x * vec2(rc.x, rc.y) + nxy.y * vec2(rc.y, -rc.x);
	vec3 nrm = vec3(ns, nz);
	vec3 L = normalize(light_dir);
	float diff = clamp(dot(nrm, L), 0.0, 1.0);
	float hemi = 0.5 + 0.5 * nz;
	float lf = (amb * (0.7 + 0.3 * hemi) + key * diff) / (amb + key * L.z);
	int ci = clamp(int(culture_i + 0.5), 0, 7);
	vec3 col = a.rgb;
	float mc = n.a;
	if (mc > 0.85) {
		col *= stone_tint[ci];
	} else {
		vec3 p = mc > 0.55 ? pal_r[ci] : (mc > 0.25 ? pal_g[ci] : pal_b[ci]);
		col *= p / 0.85;
	}
	col *= lf;
	// Rim: pixels higher than their surroundings catch the light; outline on the silhouette.
	float hgt = n.b;
	float hn = (texture(nrm_tex, UV + vec2(1.5, 0.0) / vec2(textureSize(nrm_tex, 0))).b
		+ texture(nrm_tex, UV - vec2(1.5, 0.0) / vec2(textureSize(nrm_tex, 0))).b
		+ texture(nrm_tex, UV + vec2(0.0, 1.5) / vec2(textureSize(nrm_tex, 0))).b
		+ texture(nrm_tex, UV - vec2(0.0, 1.5) / vec2(textureSize(nrm_tex, 0))).b) * 0.25;
	col += rim * clamp((hgt - hn) * 28.0, 0.0, 1.0) * vec3(1.0, 0.95, 0.8);
	col *= 1.0 - outline * (1.0 - smoothstep(0.55, 0.98, a.a));
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(vec3(lum), col, sat);
	col = (col - 0.5) * contrast + 0.5;
	COLOR = vec4(clamp(col, 0.0, 1.0), a.a);
}
