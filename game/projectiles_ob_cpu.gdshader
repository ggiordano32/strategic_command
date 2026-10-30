shader_type canvas_item;
// Missiles in the oblique view, CPU-fed: see projectiles.gdshaderinc (OBLIQUE).
render_mode skip_vertex_transform;
#define CPU_FED
#define OBLIQUE
#include "res://game/projectiles.gdshaderinc"
