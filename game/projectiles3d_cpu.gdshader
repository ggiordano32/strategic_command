shader_type spatial;
// The 3D view's missiles on the compatible path (the coarse lift grid: no texture read in the vertex stage).
render_mode unshaded, cull_disabled, world_vertex_coords, blend_mix, depth_draw_never, shadows_disabled;
#define CPU_FED
#include "res://game/projectiles3d.gdshaderinc"
