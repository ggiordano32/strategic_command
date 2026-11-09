shader_type spatial;
// The sea battle's water in the 3D view (game/sea_view3d.gd): one flat quad over the field and its margin, the 2D sea screen's
// fragment (game/sea_water_body.gdshaderinc: depth colours from the baked fields, the two wave trains, the whitecaps, the shore's
// swash and breakers, the diorama grade and the board's rim) unshaded, its display values straight to ALBEDO as the land board's
// shader does (the painted light is in the colours). Graphics Low: hi = 0, the depth colour and a still wash, no time.
render_mode unshaded, depth_draw_opaque, cull_disabled;

#include "res://game/sea_water_body.gdshaderinc"

varying vec2 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	ALBEDO = sea_water_color(wp).rgb;
}
