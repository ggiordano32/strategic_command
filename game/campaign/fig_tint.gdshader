shader_type canvas_item;
render_mode blend_mul;
// The coat of a character figure toward its faction's colour (view only). Drawn over the figure with the figure's
// mask texture (R = coat, G = sash) as the texture and the faction colour as the draw's modulate: a multiply of
// mix(white, faction, 40 % of the coat), so the painted shading of the coat stays and the rest of the rect is
// multiplied by one (unchanged).
uniform float strength = 0.4;

void fragment() {
	vec4 m = texture(TEXTURE, UV);
	float k = strength * m.r * m.a;
	COLOR = vec4(mix(vec3(1.0), COLOR.rgb, k), 1.0);
}
