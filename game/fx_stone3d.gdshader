shader_type spatial;
// The 3D view's stones, balls and chips (game/impacts3d.gd; 2026-11-07): little spheres in the 3D scene, one MultiMesh, the
// instance colour (rgb, alpha) their paint and fade, lit as the kit's faces are (half-Lambert along the world lamp, key_dir) so a
// stone reads as part of the scene, depth-tested and depth-written so a house or a man in front hides it.
render_mode unshaded, cull_back, blend_mix, depth_draw_opaque, shadows_disabled;
uniform vec3 key_dir = vec3(-0.40, 0.77, -0.50);   // world, toward the light

varying vec3 w_nrm;

void vertex() {
	w_nrm = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 N = normalize(w_nrm);
	float diff = clamp(dot(N, normalize(key_dir)) * 0.5 + 0.5, 0.0, 1.0);
	float hemi = 0.5 + 0.5 * N.y;
	float lf = 0.35 + 0.65 * (0.55 * diff + 0.45 * hemi) * 1.25;
	vec3 c = COLOR.rgb * lf;
	// (a darker rim, as the sprites' stones were drawn: rim, body, highlight)
	float rim = 1.0 - clamp(abs(dot(N, vec3(0.0, 0.0, 1.0))), 0.0, 1.0);
	ALBEDO = clamp(c, vec3(0.0), vec3(1.0));
	ALPHA = COLOR.a;
}
