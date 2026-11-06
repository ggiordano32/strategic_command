shader_type spatial;
// The 3D battle view's kit pieces as meshes (step two, 2026-11-06; game/kit3d.gd, game/view3d.gd _build_meshes): a MultiMesh
// per piece kind, the instance's custom data its culture. The baked painted albedo (tools/battlekit/export3d.py: the kit's own
// materials times a soft ambient occlusion; the masked parts grey) recoloured by the culture's palette through the vertex's
// mask class (UV2.x: 1.0 none / 0.7 roof / 0.4 plaster / 0.1 accent, the kit atlases' classes), lit as battlekit.gdshader
// lights the painted sprites (an ambient with a sky term and one half-Lambert key, normalised so a face looking up reads at its
// painted value) with the key along the 3D lamp (key_dir, the world lamp's direction: the same faces lit from every yaw), then
// the battle look's saturation and contrast; the lamp adds only its shadows (as the kit's cards: lit 1.0, in shadow 0.71). No
// texture read in the vertex stage (the compatible path's rule): the ground's height is in the instance's transform.
render_mode diffuse_lambert, specular_disabled, cull_back;
#include "res://game/weather.gdshaderinc"

uniform sampler2D kit_tex : filter_linear_mipmap, repeat_disable;
uniform vec3 stone_tint[8];
uniform vec3 pal_r[8];
uniform vec3 pal_g[8];
uniform vec3 pal_b[8];
uniform float amb = 0.66;
uniform float key = 0.55;
uniform float sat = 0.86;
uniform float contrast = 1.04;
uniform vec3 key_dir = vec3(-0.40, 0.77, -0.50);   // world, toward the light

varying vec3 w_nrm;
varying float culture;
varying float mclass;

void vertex() {
	culture = INSTANCE_CUSTOM.r;
	mclass = UV2.x;
	w_nrm = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 a = texture(kit_tex, UV).rgb;
	bool palm = culture > 7.5;
	int ci = clamp(int(culture + 0.5) - (palm ? 8 : 0), 0, 7);
	vec3 col = a;
	float mc = mclass;
	if (mc > 0.85) {
		if (palm) {
			float al = dot(a, vec3(0.3, 0.59, 0.11));
			col = mix(col, col * vec3(0.70, 0.76, 0.86), smoothstep(0.43, 0.52, al));
		}
		col *= stone_tint[ci];
	} else {
		vec3 p = mc > 0.55 ? pal_r[ci] : (mc > 0.25 ? pal_g[ci] : pal_b[ci]);
		col *= p / 0.85;
	}
	vec3 N = normalize(w_nrm);
	if (wx_surf.y > 0.001) {
		// Snow on the roofs (the mask class 0.7) and the faces that look up (the weather pass).
		float roof = mclass > 0.55 && mclass < 0.85 ? 1.0 : 0.0;
		col = wx_snow_on(col, roof * (0.5 + 0.5 * smoothstep(0.2, 0.8, N.y)) + (1.0 - roof) * 0.9 * smoothstep(0.7, 0.95, N.y));
	}
	vec3 L = normalize(key_dir);
	// (half-Lambert and a floor: the painted sprites light a wall turned from the key at about 0.6 of its paint, not black)
	float diff = clamp(dot(N, L) * 0.5 + 0.5, 0.0, 1.0);
	float hemi = 0.5 + 0.5 * N.y;
	float lf = (amb * (0.7 + 0.3 * hemi) + key * diff) / (amb + key * (0.5 + 0.5 * L.y));
	lf = 0.25 + 0.75 * lf;
	col *= lf;
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(vec3(lum), col, sat);
	col = (col - 0.5) * contrast + 0.5;
	ALBEDO = clamp(col, 0.0, 1.0);
}

// (A face turned from the lamp is already darkened by the key above: the shadow counts only on faces the lamp reaches, so a
// wall in its own shade is not darkened twice.)
void light() {
	float att = mix(1.0, ATTENUATION, smoothstep(0.0, 0.25, dot(NORMAL, LIGHT)));
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * (0.45 + 0.29 * att);
}
