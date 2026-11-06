shader_type canvas_item;
// The muzzle flashes' additive layer (game/overlay.gd _add_redraw, the flash and smoke pass 2026-11-06): the lift of board_lift3d.gdshader with additive blending.
// The 3D battle view's lift for draw-based layers (game/board_view.gd lift_node when BoardView.v3d): as game/board_lift.gdshader,
// with the 3D camera's yaw and elevation in the board transform (board_view.gdshaderinc under V3D), so the ground drawing (order
// lines, range rings, decals) lies on the 3D board's ground and upright items stand at their anchor's screen point.
render_mode skip_vertex_transform, blend_add;
#define V3D
#include "res://game/board_view.gdshaderinc"

void vertex() {
	if (ob_on > 0.5 && ob_up_marked(MODEL_MATRIX)) {
		vec2 a = MODEL_MATRIX[3].xy / (1.0 - OB_UP_K);
		VERTEX = ob_board(a) + (VERTEX - a);
	} else {
		vec2 w = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
		VERTEX = ob_on > 0.5 ? ob_board(w) : w;
	}
}
