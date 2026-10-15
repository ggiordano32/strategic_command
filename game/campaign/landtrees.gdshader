shader_type canvas_item;
#include "res://game/campaign/map_look.gdshaderinc"
// The landscape's trees and rocks as models (one MultiMesh, landtrees.gd): each instance takes its sprite from
// the minis atlas through INSTANCE_CUSTOM (x y w h in uv); the instance colour is the primary colour (the
// crown or rock body, from the map's palette), the mask atlas gives the highlight and shadow tones like the
// town pieces. Same map look as the terrain and the pieces. View only.
uniform sampler2D mask : filter_linear, repeat_disable;
varying vec4 prim;

void vertex() {
	prim = COLOR;
	UV = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
}

void fragment() {
	vec4 sh = texture(TEXTURE, UV);
	vec3 m = texture(mask, UV).rgb;
	vec3 p = prim.rgb;
	vec3 s = mix(p, vec3(0.97, 0.94, 0.86), 0.28);
	vec3 a = p * 0.5;
	vec3 tint = m.r * p + m.g * s + m.b * a + (1.0 - clamp(m.r + m.g + m.b, 0.0, 1.0));
	vec3 col = sh.rgb * tint;
	vec2 px = 1.6 / vec2(textureSize(TEXTURE, 0));
	float a_nw = texture(TEXTURE, UV - px).a;
	col += clamp(sh.a - a_nw, 0.0, 1.0) * 0.18 * vec3(1.0, 0.95, 0.8);
	col = map_bands(col, 0.75);
	col = map_grade(col);
	col = (col - 0.5) * 1.08 + 0.5;
	col = mix(col, MAP_INK, 0.30 * (1.0 - smoothstep(0.55, 0.98, sh.a)));
	col = map_grain(col, SCREEN_UV, SCREEN_PIXEL_SIZE);
	COLOR = vec4(clamp(col, 0.0, 1.0), sh.a * prim.a);
}
