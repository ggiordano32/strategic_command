shader_type spatial;
// The 3D view's small solids (game/view3d.gd): the siege gear and the ships off the shore, built by game/siege_gear_ob.gd's
// emitter in world metres with their colours (already shaded by the key light) per vertex; lit softly by the lamp so its shadows
// fall on them (no N.L, as the kit: lit 1.0, in shadow 0.71 with the ambient).
render_mode diffuse_lambert, specular_disabled, cull_disabled;

void fragment() {
	ALBEDO = COLOR.rgb;
}

void light() {
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * (0.45 + 0.29 * ATTENUATION);   // (LIGHT_COLOR carries PI, as the built-in Lambert divides it out)
}
