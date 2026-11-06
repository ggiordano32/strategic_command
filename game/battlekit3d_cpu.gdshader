shader_type spatial;
// The 3D view's kit on the compatible path (the coarse lift grid: no texture read in the vertex stage).
render_mode diffuse_lambert, specular_disabled, cull_disabled, world_vertex_coords;
#define CPU_FED
#include "res://game/battlekit3d.gdshaderinc"
