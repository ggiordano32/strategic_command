// Footprints on the board (game/print_layer.gd): the detail window's texture (R = the print's second mod 256 in 255ths, G =
// the coverage, B its darkness, stamped at 8 texels a metre round the camera's look-at point) and `prints_dark`, the darkness at a world
// point: the print, faded by its age (FADE_S 90 s), and gone with the zoom (the coarse wear of the marks layer carries the far
// look). prints_win = (the window's top-left in metres, its width in metres; 0: no window).
uniform sampler2D prints_tex : filter_linear, repeat_disable;
uniform vec3 prints_win = vec3(0.0);
uniform float prints_now = 0.0;   // the sim's seconds

float prints_dark(vec2 wm, float mpp) {
	if (prints_win.z <= 0.0 || mpp > 0.9) {
		return 0.0;
	}
	vec2 uv = (wm - prints_win.xy) / prints_win.z;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	vec3 p = texture(prints_tex, uv).rgb;
	if (p.g < 0.05) {
		return 0.0;
	}
	float cov = smoothstep(0.32, 0.62, p.g);   // (the bilinear blur sharpened back to an edge)
	float dark = p.b / p.g;
	float age = fract(prints_now / 256.0 - p.r) * 256.0;
	float fade = clamp(1.0 - age / 90.0, 0.0, 1.0);
	float far_k = 1.0 - smoothstep(0.4, 0.9, mpp);
	return clamp(dark * 1.3, 0.0, 1.0) * cov * fade * (0.35 + 0.65 * fade) * far_k;
}
