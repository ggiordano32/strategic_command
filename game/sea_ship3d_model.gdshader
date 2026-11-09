shader_type spatial;
// The sea battle's ship models (assets/battlekit_ob/ships3d.res, tools/battlekit/export_ships.py; game/sea_ship3d.gd `model`): the
// painted swatch atlas times the baked occlusion (UV2.y), the mask class (UV2.x) recolouring the parts the faction owns (0.7: the rail's
// strake, the wale, the castle's band; the swatch's grey takes `faction`) and the castle the treasure galleon gilds (0.4: `treasure`
// turns the pale wood to gold). Lit softly by the world lamp as the procedural hulls are (a half-Lambert so no side goes black).
// `tint` darkens a struck prize or a fire ship alight.
render_mode diffuse_lambert, specular_disabled, cull_disabled;

uniform sampler2D albedo_tex : filter_linear_mipmap, repeat_disable;
uniform vec3 faction = vec3(0.8, 0.2, 0.2);
uniform float treasure = 0.0;
uniform vec3 tint = vec3(1.0);

varying float mclass;
varying float occ;

void vertex() {
	mclass = UV2.x;
	occ = UV2.y;
}

void fragment() {
	vec3 a = texture(albedo_tex, UV).rgb;
	float l = dot(a, vec3(0.3, 0.59, 0.11));
	vec3 c = a;
	if (mclass > 0.55 && mclass < 0.85) {
		c = faction * (l / 0.6);
	} else if (mclass > 0.25 && mclass <= 0.55) {
		c = mix(a, vec3(0.92, 0.72, 0.22) * (l / 0.5), treasure);
	}
	ALBEDO = clamp(c * occ * tint, vec3(0.0), vec3(1.0));
}

void light() {
	float nl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * (0.25 + 0.55 * nl * ATTENUATION);
}
