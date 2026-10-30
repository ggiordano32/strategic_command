shader_type canvas_item;
// Soldiers in the oblique view, CPU-fed: see soldiers.gdshaderinc (OBLIQUE).
render_mode skip_vertex_transform;
#define CPU_FED
#define OBLIQUE
#include "res://game/soldiers.gdshaderinc"
