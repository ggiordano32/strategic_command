shader_type spatial;
// The 3D view's figure bases on the compatible path (the coarse lift grid).
render_mode diffuse_lambert, specular_disabled, world_vertex_coords, cull_disabled;
#define CPU_FED
#define BASES
#include "res://game/soldiers3d.gdshaderinc"
