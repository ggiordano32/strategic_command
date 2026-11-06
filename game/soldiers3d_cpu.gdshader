shader_type spatial;
// The 3D view's men on the compatible path: game/soldiers3d.gdshaderinc with the coarse lift grid (no texture read in the vertex
// stage at all; the frame table as constants).
render_mode unshaded, cull_disabled, world_vertex_coords;
#define CPU_FED
#include "res://game/soldiers3d.gdshaderinc"
