shader_type canvas_item;
// Battlefield ground: a calm topographic-map look drawn in one pass from a
// height texture built once per battle (game/terrain_layer.gd), in the
// region's ground palette (game/ground_palette.gd).
//
// Height texture (RGBA8, one texel per 2 m node, nearest / texelFetch only,
// no float textures and no reliance on filtering precision):
//   R, G  height, 16 bits (R high byte), 0..65535 over 0..h_range_m metres
//   B     shade: 128 = flat; (B - 128) / 160 = relative brightness (hill
//         shading from the upper left plus a soft darkening of valley floors)
//   A     slope: ground grade (rise / run) 0..0.8 over 0..255 (rock tint and
//         slope darkening; interpolated like the height)
// Ground features texture (RGBA8, one texel per 4 m cell, linear filter):
//   R woods (tree density / 3), G inside a settlement, B farm field,
//   A 0.5 main street / 1.0 plaza.
// The ground also carries low-frequency colour variation (patches of lusher
// and of drier or stonier ground from hash noise), rock on steep slopes and
// above a notional tree line on hill maps, wet sand along water and a
// moving ripple on the river and the sea (the built-in TIME, nothing from
// the sim).
// The four height nodes around a fragment are decoded and interpolated here
// (manual bilinear in highp), so contours are exact and stable when panning
// and zooming. Contour lines keep a constant screen width via fwidth() and
// fade out where they would crowd together when zoomed far out.
// The oblique view (tabletop pass 3, game/board_view.gd): the rectangle covers the field's board area and each pixel
// finds the ground point under it (ob_world: the board transform inverted, the hills lifted toward the camera); the
// rest of the shading is the same, in that point's world coordinates. Outside the field: transparent.
#include "res://game/board_view.gdshaderinc"
#include "res://game/terrain_body.gdshaderinc"

varying highp vec2 vpos;   // world px (the top view) or board px (the oblique view)

void vertex() {
	vpos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	highp vec2 world = vpos;
	float ob_in = 1.0;
	if (ob_on > 0.5) {
		world = ob_world(vpos);
		vec2 ob_e = min(world, ob_field - world);
		ob_in = step(0.0, min(ob_e.x, ob_e.y));
	}
	COLOR = vec4(terrain_col(world, ob_in), ob_in);
}
