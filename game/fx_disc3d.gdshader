shader_type spatial;
// The 3D view's ground discs (game/impacts3d.gd; 2026-11-07): a flat quad on the ground, the instance colour its paint and alpha,
// the custom data's x the shape (0 a soft blob: the shadow under a stone in the air, the dust under a landing; 1 a ring: the dust
// ring where a stone or a ball came down). Depth-tested, not written: a house or a man in front hides it.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

varying float ring;

void vertex() {
	ring = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec2 q = (UV - vec2(0.5)) * 2.0;
	float r = length(q);
	float blob = 1.0 - smoothstep(0.25, 1.0, r);
	float band = 1.0 - smoothstep(0.0, 0.22, abs(r - 0.78));
	float s = ring > 0.5 ? band * (1.0 - smoothstep(0.9, 1.0, r)) : blob;
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * s;
}
