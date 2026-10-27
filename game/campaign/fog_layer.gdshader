shader_type canvas_item;
// The fog over the map (fog_layer.gd). Over the chart sea (far from every coast, past the shelf: the same rule as
// water.gdshader's `cf`) the fog is lighter, `chart_fog` of its strength, so unseen far sea reads as a dimmer
// parchment, not dark grey; full over land and the shelf. Uniforms are the water's own textures.
uniform sampler2D chart_d : filter_linear, repeat_disable;
uniform sampler2D depth : filter_linear, repeat_disable;
uniform vec2 field_px = vec2(2760.0, 1400.0);
uniform vec2 chart_range = vec2(40.0, 260.0);
uniform vec2 depth_range = vec2(80.0, 400.0);
uniform float chart_fog = 0.6;
uniform float chart_on = 0.0;
varying vec2 wp;

void vertex() {
	wp = VERTEX;
}

float depth_m(float v) {
	return v <= 31.0 ? max(v - 1.0, 0.0) : 30.0 * exp((v - 31.0) / 48.64);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	vec2 fuv = wp / field_px;
	float inwin = step(0.0, fuv.x) * step(fuv.x, 1.0) * step(0.0, fuv.y) * step(fuv.y, 1.0);
	float cdist = mix(400.0, texture(chart_d, fuv).r * 255.0 * 1.5, inwin);
	float dm = depth_m(mix(255.0, texture(depth, fuv).r * 255.0, inwin));
	float cf = smoothstep(chart_range.x, chart_range.y, cdist) * mix(0.65, 1.0, smoothstep(depth_range.x, depth_range.y, dm)) * chart_on;
	c.a *= mix(1.0, chart_fog, cf);
	COLOR = c;
}
