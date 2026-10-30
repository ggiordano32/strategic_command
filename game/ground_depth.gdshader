shader_type canvas_item;
// Pass 6, the crest ghost (BoardView.crest_ghost, [video] crest_ghost): the ground's own nearness for the occluder pass
// (game/kit_occluder.gd). Every pixel of the field finds the ground point under it (ob_world, the same field as the ground
// shader) and writes its nearness along the view (ob_near) in the kit's 16 bit encoding, so a man whose nearness is less
// than the ground's at his pixel (he stands behind a crest nearer the camera) draws as the faction ghost.
#include "res://game/board_view.gdshaderinc"

uniform vec2 ob_near_r = vec2(0.0, 1.0);
varying highp vec2 vpos;

void vertex() {
	vpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 w = ob_world(vpos);
	vec2 e = min(w, ob_field - w);
	if (min(e.x, e.y) < 0.0) {
		discard;
	}
	float n = clamp((ob_near(w, 0.0) - ob_near_r.x) / ob_near_r.y, 0.0, 1.0) * 65535.0;
	float hi = floor(n / 256.0);
	COLOR = vec4(hi / 255.0, (n - hi * 256.0) / 255.0, 0.0, 1.0);
}
