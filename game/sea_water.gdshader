shader_type canvas_item;
// The sea battle's water (game/sea_look.gd; 2026-10-22, owner: "make the naval battle shader look more
// like water"). One full-field pass in world metres (1 px = 1 m at zoom 1).
//  - depth colouring: a baked field (`fld`: R signed distance to the coast, G depth, B steepness,
//    A woods; `aux`: the coast's seaward direction) from the campaign cell's bathymetry (else a
//    shelf from the distance to land): sandy turquoise shallows, the shelf blue, deep and abyss;
//  - waves: two trains running before the wind (swell and chop, their phase warped and grouped by
//    noise so nothing tiles), lit from the north-west as the battle kit is, crests catching the
//    light, whitecaps in a hard wind, a small sun glitter; flat in the shallows and near the shore;
//  - shoreline foam: swash and broken breaker lines on the DRAWN shore (the sim's cell edge refined
//    by sea_shore.gdshaderinc), a band fading with depth, and foam on shoals; a drop shadow under
//    steep coasts;
//  - the diorama look's saturation / contrast (BattleLook), a rim round the board's edge.
// hi = 0 (Graphics Low): the depth colouring, a still shore wash, no waves, no time.

#include "res://game/sea_water_body.gdshaderinc"

varying vec2 wp;

void vertex() {
	wp = VERTEX;
}

void fragment() {
	COLOR = sea_water_color(wp);
}
