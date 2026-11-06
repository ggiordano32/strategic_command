shader_type spatial;
// The 3D view's figure bases: game/soldiers3d.gdshaderinc under BASES (a flocked disc with the faction's rim, flat on the board,
// lit by the lamp; shadows fall on it).
render_mode diffuse_lambert, specular_disabled, world_vertex_coords, cull_disabled;
#define BASES
#include "res://game/soldiers3d.gdshaderinc"
