shader_type canvas_item;
// Figure bases in the oblique view, CPU-fed: see soldier_bases.gdshaderinc (OBLIQUE).
render_mode skip_vertex_transform;
#define CPU_FED
#define OBLIQUE
#include "res://game/soldier_bases.gdshaderinc"
