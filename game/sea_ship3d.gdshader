shader_type spatial;
// The sea battle's ships in the 3D view (game/sea_ship3d.gd, game/sea_view3d.gd): procedural solids with their colours per vertex,
// lit softly by the world lamp (a half-Lambert so no side goes black; in shadow 0.25 + the room's ambient), double sided for the
// sails and the flags. `tint` darkens a ship (a struck prize, a fire ship alight).
render_mode diffuse_lambert, specular_disabled, cull_disabled;
uniform vec3 tint = vec3(1.0);

void fragment() {
	ALBEDO = COLOR.rgb * tint;
}

void light() {
	float nl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * (0.25 + 0.55 * nl * ATTENUATION);
}
