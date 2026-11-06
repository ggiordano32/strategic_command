shader_type spatial;
// The 3D battle view's board (game/view3d.gd): the heightfield mesh, coloured by the terrain shader's own body
// (game/terrain_body.gdshaderinc, the same uniforms the 2D terrain layer built) at the fragment's world point, lit by the lamp.
// The 2D shading's display values go to ALBEDO as they are: the Compatibility renderer's 3D output matches the 2D layers that way
// (measured against the oblique view; linearising first made the board far too dark).
render_mode diffuse_lambert, specular_disabled;
#define V3D
#include "res://game/board_view.gdshaderinc"
#include "res://game/terrain_body.gdshaderinc"

// Ground decals the 2D views draw as their own layers: the settlement's streets (game/city_streets.gd's texture over its rect, world
// px) and the Paths overlay's hatch (game/city_layer.gd: the sim's 2 m cells, faded by its alpha; the same hatch shader's maths).
uniform sampler2D gc_tex : filter_linear, repeat_disable;   // the drawn decals and the rubble (game/view3d.gd _GroundDraw)
uniform vec4 gc_rect = vec4(0.0, 0.0, 0.0, 0.0);
uniform sampler2D street_tex : filter_linear, repeat_disable;
uniform vec4 street_rect = vec4(0.0, 0.0, 0.0, 0.0);
uniform sampler2D paths_tex : filter_nearest, repeat_disable;
uniform vec4 paths_rect = vec4(0.0, 0.0, 0.0, 0.0);
uniform float paths_alpha = 0.0;
uniform float paths_period = 9.0;
varying highp vec2 vworld;   // world px

void vertex() {
	vworld = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz * ppm;
}

void fragment() {
	vec3 c = clamp(terrain_col(vworld, 1.0), vec3(0.0), vec3(1.0));
	if (gc_rect.z > 0.0) {
		vec4 gc = texture(gc_tex, (vworld - gc_rect.xy) / gc_rect.zw);
		c = mix(c, gc.rgb / max(gc.a, 0.001), clamp(gc.a, 0.0, 1.0));
	}
	if (street_rect.z > 0.0) {
		vec2 su = (vworld - street_rect.xy) / street_rect.zw;
		if (su.x >= 0.0 && su.y >= 0.0 && su.x <= 1.0 && su.y <= 1.0) {
			vec4 sc = texture(street_tex, su);
			c = mix(c, sc.rgb, sc.a);
		}
	}
	if (paths_alpha > 0.001 && paths_rect.z > 0.0) {
		vec2 pu = (vworld - paths_rect.xy) / paths_rect.zw;
		float m = (pu.x >= 0.0 && pu.y >= 0.0 && pu.x <= 1.0 && pu.y <= 1.0) ? texture(paths_tex, pu).r : 0.0;
		float h = fract((vworld.x + vworld.y) / paths_period);
		float d = abs(h - 0.5) * 2.0;
		float w = max(fwidth(d), 0.02);
		float line = smoothstep(0.62 - w, 0.62 + w, d);
		if (m > 0.75) {
			c = mix(c, vec3(0.95, 0.30, 0.22), (0.10 + 0.55 * line) * paths_alpha);
		} else {
			float h2 = fract((vworld.x - vworld.y) / (paths_period * 1.6));
			float d2 = abs(h2 - 0.5) * 2.0;
			float w2 = max(fwidth(d2), 0.02);
			float l2 = smoothstep(0.75 - w2, 0.75 + w2, d2);
			c = mix(c, vec3(0.98, 0.72, 0.25), step(0.25, m) * (0.06 + 0.5 * l2) * paths_alpha);
		}
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
