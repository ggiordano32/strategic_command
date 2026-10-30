shader_type canvas_item;
// A multiplied Sprite2D texture on the ground (the kit's baked shadow) in the oblique view: game/board_ground.gdshaderinc.
render_mode skip_vertex_transform, blend_mul;
#include "res://game/board_ground.gdshaderinc"

void vertex() {
	VERTEX = ob_ground_vertex(VERTEX, UV, MODEL_MATRIX);
	v_b = VERTEX;
	v_rect = ob_ground_rect(MODEL_MATRIX, TEXTURE_PIXEL_SIZE);
}

void fragment() {
	vec2 w;
	vec3 g = ob_ground_uv(w);
	COLOR = mix(vec4(1.0), texture(TEXTURE, g.xy), g.z);
}
