shader_type spatial;
// The 3D view's missiles: game/projectiles3d.gdshaderinc, the ground heights from the fine lift field.
render_mode unshaded, cull_disabled, world_vertex_coords, blend_mix, depth_draw_never, shadows_disabled;
#include "res://game/projectiles3d.gdshaderinc"
