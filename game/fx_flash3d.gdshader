shader_type spatial;
// The 3D view's muzzle flash (game/fx3d.gd; the flash and smoke pass, 2026-11-06): additive billboards (a soft halo, a glow and the
// white core, from the flash tile of game/gun_smoke.gd), depth-tested so a flash behind a house does not show, pushed toward the camera
// so the glow is not cut by the ground it lies over. The light on the ground and the houses is the pooled OmniLight3Ds'; on the men
// and the smoke, fx_light3d.gdshaderinc.
render_mode unshaded, cull_disabled, world_vertex_coords, blend_add, depth_draw_never, shadows_disabled;

uniform sampler2D tex : filter_linear_mipmap, repeat_disable;
uniform vec3 cam_r = vec3(1.0, 0.0, 0.0);
uniform vec3 cam_u = vec3(0.0, 0.766, -0.643);
uniform vec3 cam_b = vec3(0.0, 0.643, 0.766);
uniform float cam_yaw = 0.0;
const float TILES = 6.0;

varying vec2 q;
varying vec4 cd;

void vertex() {
	cd = INSTANCE_CUSTOM;   // radius m, strength, 0, layer (0 halo, 1 glow, 2 core)
	vec3 c = MODEL_MATRIX[3].xyz;
	vec2 k = UV * 2.0 - 1.0;
	VERTEX = c + cam_r * (k.x * cd.x) + cam_u * (k.y * cd.x) + cam_b * (cd.x * 1.1);
	q = vec2(UV.x, 1.0 - UV.y);
}

void fragment() {
	vec4 t = texture(tex, vec2((5.0 + q.x) / TILES, q.y));
	vec3 col = cd.w < 0.5 ? vec3(1.0, 0.6, 0.25) : (cd.w < 1.5 ? vec3(1.0, 0.85, 0.55) : vec3(1.0, 1.0, 0.95));
	ALBEDO = t.rgb * col;
	ALPHA = t.a * cd.y;
}
