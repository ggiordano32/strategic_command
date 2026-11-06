shader_type canvas_item;
// The muzzle flashes' additive layer (game/overlay.gd _add_redraw, the flash and smoke pass 2026-11-06): the lift of board_lift.gdshader with additive blending.
// The oblique battle view for draw-based layers (game/board_view.gd lift_node): every vertex the node draws (world px,
// through its draw transform) goes to its board point, so the ground drawing (decals, footprints, order lines, range
// rings, the board edge) lies squashed on the ground and rises with it. Items drawn under BoardView.up_xf(anchor) stand
// upright instead: their offsets from the anchor stay screen-aligned at the anchor's board point (markers, standards,
// tokens, labels). The fragment stage is the default (texture x colour).
render_mode skip_vertex_transform, blend_add;
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
