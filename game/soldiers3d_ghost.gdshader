shader_type spatial;
// The 3D view's ghost pass (game/soldiers3d.gdshaderinc GHOST; docs/design/art_pipeline.md "The ghost and the map camera"): the
// viewer's own men again, as a flat tinted silhouette, where the men's pass left the stencil unset (hidden by a house, a wall, a
// tower or a crest). Transparent, no depth test, no depth write; the stencil test needs the men's shader to write stencil 1.
render_mode unshaded, cull_disabled, world_vertex_coords, blend_mix, depth_test_disabled, depth_draw_never;
stencil_mode read, compare_not_equal, 1;
#define GHOST
#include "res://game/soldiers3d.gdshaderinc"
