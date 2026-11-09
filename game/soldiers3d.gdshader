shader_type spatial;
// The 3D view's men: game/soldiers3d.gdshaderinc, the ground height from the fine lift field.
render_mode unshaded, cull_disabled, world_vertex_coords;
stencil_mode write, compare_always, 1;   // (the ghost pass reads it: game/soldiers3d_ghost.gdshader)
#include "res://game/soldiers3d.gdshaderinc"
