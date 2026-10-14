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
	COLOR = vec4(sh.rgb * tint, sh.a * prim.a);
}
