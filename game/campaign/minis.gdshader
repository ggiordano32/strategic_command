shader_type canvas_item;
// Painted miniatures (tools/structures, style D): the shade atlas is the
// texture, `mask` the same layout (R primary, G secondary, B accent). The
// primary colour is the draw call's modulate (the owner's faction colour);
// trim and shadow tones are derived from it. View only.
uniform sampler2D mask : filter_linear, repeat_disable;
varying vec4 prim;

void vertex() {
	prim = COLOR;
}

void fragment() {
	vec4 sh = texture(TEXTURE, UV);
	vec3 m = texture(mask, UV).rgb;
	vec3 p = prim.rgb;
	vec3 s = mix(p, vec3(0.97, 0.94, 0.86), 0.72);
	vec3 a = p * 0.42;
	vec3 tint = m.r * p + m.g * s + m.b * a + (1.0 - clamp(m.r + m.g + m.b, 0.0, 1.0));
	vec3 col = sh.rgb * tint;
	// The battle's diorama finish (battlekit.gdshader): rim light on edges facing the north-west light,
	// a dark line on the silhouette, saturation and contrast.
	vec2 px = 1.6 / vec2(textureSize(TEXTURE, 0));
	float a_nw = texture(TEXTURE, UV - px).a;
	float a_se = texture(TEXTURE, UV + px).a;
	float rim = clamp(sh.a - a_nw, 0.0, 1.0) * 0.22 + clamp(sh.a - a_se, 0.0, 1.0) * 0.0;
	col += rim * vec3(1.0, 0.95, 0.8);
	col *= 1.0 - 0.22 * (1.0 - smoothstep(0.55, 0.98, sh.a));
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(vec3(lum), col, 1.18);
	col = (col - 0.5) * 1.08 + 0.5;
	COLOR = vec4(clamp(col, 0.0, 1.0), sh.a * prim.a);
}
