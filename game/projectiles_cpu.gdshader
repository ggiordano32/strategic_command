shader_type canvas_item;
// Missiles, CPU-fed (the compatible fallback): see projectiles.gdshaderinc.
render_mode skip_vertex_transform;
#define CPU_FED
#include "res://game/projectiles.gdshaderinc"
