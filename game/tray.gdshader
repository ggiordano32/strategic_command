shader_type canvas_item;
// The movement trays (game/tray_layer.gd): one quad per tray in one MultiMesh, the card drawn here from the pixel distance
// to the nearest edge: a dark edge 1.5 screen px wide, a lighter bevel line just inside it, a translucent dark fill.
// `w` is the world pixels per screen pixel (1 / the camera zoom); the instance's custom data is its size in world pixels.
// The oblique view (tabletop pass 3): the corners go to their board points (squashed, lifted with the ground); the custom
// data's z is the wall walk's height in board px for a unit standing on a wall (tabletop pass 3 leftovers).
render_mode skip_vertex_transform;
#include "res://game/board_view.gdshaderinc"
uniform float w = 1.0;
varying vec2 v_size;

void vertex() {
	v_size = INSTANCE_CUSTOM.xy;
	vec2 wp = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	VERTEX = ob_on > 0.5 ? ob_board(wp) - vec2(0.0, INSTANCE_CUSTOM.z) : wp;
}

void fragment() {
	vec2 lp = (UV - 0.5) * v_size;
	vec2 h = v_size * 0.5 - abs(lp);
	float d = min(h.x, h.y);
	float aa = 0.5 * w;
	float edge = 1.0 - smoothstep(1.5 * w - aa, 1.5 * w + aa, d);
	float bev = smoothstep(2.0 * w, 2.0 * w + aa, d) * (1.0 - smoothstep(2.9 * w - aa, 2.9 * w + aa, d));
	vec4 c = vec4(0.05, 0.04, 0.03, 0.12);
	c = mix(c, vec4(0.9, 0.84, 0.66, 0.32), bev);
	c = mix(c, vec4(0.07, 0.06, 0.05, 0.9), edge);
	COLOR = c;
}
