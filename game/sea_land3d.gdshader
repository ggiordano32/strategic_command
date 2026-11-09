shader_type spatial;
// The sea battle's land in the 3D view (D1: a flat quad a hair over the water; the coast mesh is D2): the 2D screen's fragment
// (game/sea_land_body.gdshaderinc) unshaded with its alpha, so the water shows wherever the sim has no land and the drawn shore
// keeps its 5-14 m margin inside the sim's land cells (shore_ok).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

#include "res://game/sea_land_body.gdshaderinc"

varying vec2 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec4 c = sea_land_color(wp);
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
