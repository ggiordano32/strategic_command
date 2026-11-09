shader_type canvas_item;
// The sea battle's land (game/sea_look.gd; 2026-10-22, owner: the land in the ocean battles was low
// quality and its shoreline poor beside the rest of the game). The land maps' ground, drawn in one
// pass over the field from the same baked fields as sea_water.gdshader:
//  - the ground palette of the campaign region (game/ground_palette.gd: base, lush / dry patches,
//    the grass tile), darker under the woods the tree sprites stand in;
//  - a sand beach band (wet and dark at the water, the sand tile), ragged by noise, in place of a
//    cliff where the coast is steep: rock (the rock tile, strata) with a lit brow on the side the
//    light reaches and a dark foot, the diorama's bevel along every shore, the outline;
//  - the shore itself is the sim's cell edge refined with noise (sea_shore.gdshaderinc), always
//    inside the sim's land cells (and guarded by the nearest-sampled cell mask).
// low = true (Graphics Low): plain palette, the beach and cliff bands, the bevel; no noise, no tiles.

#include "res://game/sea_land_body.gdshaderinc"

varying vec2 wp;

void vertex() {
	wp = VERTEX;
}

void fragment() {
	COLOR = sea_land_color(wp);
}
