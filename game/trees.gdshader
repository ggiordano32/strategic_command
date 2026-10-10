shader_type canvas_item;
// Trees (game/tree_layer.gd): a MultiMesh, every instance a quad placed
// here from its custom data (x, y, radius in world px; w = kind + 8 x shade
// + 32 x rotation step; kinds 0-3 trees, 4 grass tuft, 5 reeds, 6 willow,
// 7 bush). A second MultiMesh with this shader draws the low ground cover
// under the men (fade_to = 1). The atlas holds greyscale canopies: R luminance,
// G canopy coverage, B shadow coverage (offset down-right, from the light
// at the upper left). Canopies fade where soldiers stand under them (the
// occupancy texture, 4 m cells, rebuilt each sim tick).

uniform sampler2D atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D occ : filter_linear, repeat_disable;
uniform vec2 occ_size_px = vec2(1.0);
uniform float kinds = 4.0;
uniform vec3 shade0 = vec3(0.15, 0.3, 0.13);
uniform vec3 shade1 = vec3(0.19, 0.35, 0.15);
uniform vec3 shade2 = vec3(0.12, 0.25, 0.12);
uniform float fade_to = 0.28;
uniform vec3 col_tuft = vec3(0.4, 0.55, 0.25);
uniform vec3 col_reed = vec3(0.33, 0.44, 0.2);
uniform vec3 col_willow = vec3(0.3, 0.45, 0.25);
uniform vec3 col_bush = vec3(0.2, 0.33, 0.16);

varying vec2 world;
varying vec3 tint;
varying float kind;
varying float var_l;
varying float rot;
varying float shadow_k;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	float w = cd.w;
	kind = mod(w, 8.0);
	float sh = mod(floor(w / 8.0), 4.0);
	rot = floor(w / 32.0) * 0.7854;
	VERTEX = cd.xy + VERTEX * cd.z * 1.18;
	world = VERTEX;
	tint = sh < 0.5 ? shade0 : (sh < 1.5 ? shade1 : shade2);
	shadow_k = 0.4;
	if (kind > 3.5 && kind < 4.5) {
		tint = col_tuft * (sh < 0.5 ? 0.92 : (sh < 1.5 ? 1.0 : 1.1));
		shadow_k = 0.12;
	} else if (kind > 4.5 && kind < 5.5) {
		tint = col_reed * (sh < 0.5 ? 0.9 : (sh < 1.5 ? 1.0 : 1.12));
		shadow_k = 0.15;
	} else if (kind > 5.5 && kind < 6.5) {
		tint = col_willow * (sh < 0.5 ? 0.92 : (sh < 1.5 ? 1.0 : 1.08));
	} else if (kind > 6.5) {
		tint = col_bush * (sh < 0.5 ? 0.9 : (sh < 1.5 ? 1.0 : 1.1));
		shadow_k = 0.3;
	}
	var_l = 0.9 + 0.2 * hash(float(INSTANCE_ID) * 0.37 + cd.x * 0.011);
}

void fragment() {
	// The canopy is turned (variety); its shadow and the light stay fixed at
	// the upper left.
	vec2 d = UV - 0.5;
	float c = cos(rot);
	float s = sin(rot);
	vec2 ur = vec2(d.x * c - d.y * s, d.x * s + d.y * c) + 0.5;
	vec4 t = texture(atlas, vec2((kind + clamp(ur.x, 0.0, 1.0)) / kinds, clamp(ur.y, 0.0, 1.0)));
	float shadow = texture(atlas, vec2((kind + UV.x) / kinds, UV.y)).b;
	float o = texture(occ, world / occ_size_px).r;
	float fade = mix(1.0, fade_to, smoothstep(0.05, 0.5, o));
	float light = 1.0 + 0.45 * ((0.5 - UV.x) + (0.5 - UV.y));
	vec3 canopy = tint * (0.6 + 0.7 * t.r) * var_l * light;
	float ca = t.g * fade;
	float sa = shadow * shadow_k * fade;
	float a = ca + sa * (1.0 - ca);
	vec3 col = a > 0.0 ? canopy * ca / a : vec3(0.0);
	COLOR = vec4(col, a);
}
