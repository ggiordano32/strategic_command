shader_type canvas_item;
// The map-table frame over the map (under the interface): parchment outside
// the map's edge with an ink border and a soft inner shadow, a vignette, and
// an optional cheap tilt-shift (the screen blurred more towards the top and
// bottom edges, from the screen texture's mipmaps).
uniform sampler2D screen : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec4 map_rect = vec4(0.0, 0.0, 1000.0, 600.0);   // screen px: x0 y0 x1 y1
uniform vec2 view_px = vec2(1280.0, 720.0);
uniform float tilt = 1.0;
uniform float scale_px = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 px = SCREEN_UV * view_px;
	vec3 col = textureLod(screen, SCREEN_UV, 0.0).rgb;
	if (tilt > 0.5) {
		float y = abs(SCREEN_UV.y - 0.5) * 2.0;
		float b = smoothstep(0.7, 1.0, y) * 1.7;
		if (b > 0.05) {
			col = textureLod(screen, SCREEN_UV, b).rgb;
		}
	}
	// vignette
	float v = smoothstep(0.55, 1.25, length((SCREEN_UV - 0.5) * vec2(1.25, 1.0) * 1.6));
	col *= 1.0 - v * 0.27;
	// inside / outside of the map's edge
	vec2 lo = px - map_rect.xy;
	vec2 hi = map_rect.zw - px;
	float din = min(min(lo.x, hi.x), min(lo.y, hi.y));       // + inside, - outside
	float sh = (1.0 - smoothstep(0.0, 26.0 * scale_px, din)) * step(0.0, din);
	col *= 1.0 - sh * 0.30;
	if (din < 0.0) {
		float n = hash(floor(px / 2.0)) * 0.05 + hash(floor(px / 7.0)) * 0.03;
		vec3 paper = vec3(0.88, 0.80, 0.62) - n;
		float out_d = -din;
		paper *= 1.0 - 0.18 * smoothstep(0.0, 160.0, out_d);
		col = paper;
	}
	float ink = 1.0 - smoothstep(0.0, 2.0 * scale_px, abs(din) - 1.5 * scale_px);
	col = mix(col, vec3(0.20, 0.13, 0.07), ink * 0.9);
	COLOR = vec4(col, 1.0);
}
