shader_type spatial;
// The 3D view's gun smoke (game/fx3d.gd; the flash and smoke pass, 2026-11-06): cotton puffs as billboards in the 3D scene, drawn from
// the gun smoke atlas (game/gun_smoke.gd: the lit side to the upper left, the lamp's side, the shaded underside baked), depth-tested so a
// puff behind a house or a man is hidden, not written to depth. The warm light of a muzzle flash that is going off lifts the puff.
render_mode unshaded, cull_disabled, world_vertex_coords, blend_mix, depth_draw_never, shadows_disabled;
#include "res://game/fx_light3d.gdshaderinc"

uniform sampler2D tex : filter_linear_mipmap, repeat_disable;
uniform vec3 cam_r = vec3(1.0, 0.0, 0.0);
uniform vec3 cam_u = vec3(0.0, 0.766, -0.643);
uniform vec3 cam_b = vec3(0.0, 0.643, 0.766);
uniform float cam_yaw = 0.0;
uniform vec3 tint = vec3(1.0, 1.0, 0.99);
uniform vec3 dust = vec3(0.78, 0.66, 0.48);
const float TILES = 6.0;

varying vec2 q;
varying vec4 cd;
varying vec3 wpos;

void vertex() {
	cd = INSTANCE_CUSTOM;   // radius m, alpha, code (0..3 smoke tile, 4..7 dust, 8 haze glow), 0
	vec3 c = MODEL_MATRIX[3].xyz;
	vec2 k = UV * 2.0 - 1.0;
	VERTEX = c + cam_r * (k.x * cd.x) + cam_u * (k.y * cd.x) + cam_b * (cd.x * 0.6);
	wpos = c;
	q = vec2(UV.x, 1.0 - UV.y);
}

void fragment() {
	float code = cd.z;
	float tile = code > 7.5 ? 4.0 : mod(code, 4.0);
	vec4 t = texture(tex, vec2((tile + q.x) / TILES, q.y));
	vec3 base = code > 7.5 ? tint : t.rgb * (code > 3.5 ? dust : tint);
	vec3 fl = fx_flash_light(wpos);
	ALBEDO = clamp(base * (1.0 + fl * 0.3) + fl * 0.04 * t.a, vec3(0.0), vec3(1.0));
	ALPHA = t.a * cd.y;
}
