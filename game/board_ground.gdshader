shader_type canvas_item;
// A Sprite2D texture on the ground (game/board_ground.gdshaderinc): the streets in the oblique view.
render_mode skip_vertex_transform;
#include "res://game/board_ground.gdshaderinc"

void vertex() {
	VERTEX = ob_ground_vertex(VERTEX, UV, MODEL_MATRIX);
	v_b = VERTEX;
	v_rect = ob_ground_rect(MODEL_MATRIX, TEXTURE_PIXEL_SIZE);
}

void fragment() {
	vec2 w;
	vec3 g = ob_ground_uv(w);
	vec4 c = texture(TEXTURE, g.xy);
	COLOR = vec4(c.rgb, c.a * g.z) * COLOR;
}
