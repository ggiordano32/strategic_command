// Sprite pipeline step 1a: recolour a shade sheet by its mask sheet and a
// faction palette (see tools/sprites/pack.py). Both sheets share one layout,
// so the mask is sampled at the same UV.
shader_type canvas_item;

uniform sampler2D mask_tex : filter_linear_mipmap;
uniform vec3 primary = vec3(0.84, 0.13, 0.11);
uniform vec3 secondary = vec3(0.98, 0.8, 0.22);
uniform vec3 accent = vec3(0.86, 0.62, 0.28);
uniform vec3 pattern_col = vec3(0.55, 0.06, 0.05);
uniform float pattern_k = 0.0;

void fragment() {
	vec4 s = texture(TEXTURE, UV);
	vec4 m = texture(mask_tex, UV);
	float pat = clamp((1.0 - m.a) * 2.0, 0.0, 1.0) * pattern_k;
	vec3 team = m.r * mix(primary, pattern_col, pat) + m.g * secondary + m.b * accent;
	float rest = max(0.0, 1.0 - m.r - m.g - m.b);
	COLOR = vec4(s.rgb * (rest + team), s.a);
}
