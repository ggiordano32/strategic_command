shader_type spatial;
// The 3D battle view's board edge (game/view3d.gd): the board cut like a cake on its four sides, foam layers a band high (the
// terrain's 2 m contour band, exaggerated as the hills are) in two creams with a thin glue line, a painted MDF base strip under
// the lowest ground, and the flock's lip along the top.
render_mode diffuse_lambert, specular_disabled, cull_disabled;
uniform float band_m = 2.8;
uniform float foot_y = -3.0;
uniform vec3 flock_col = vec3(0.27, 0.38, 0.2);
varying float vy;
varying float vtop;

void vertex() {
	vy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	vtop = UV.y;
}

void fragment() {
	float base_top = foot_y + 1.6;
	vec3 c;
	if (vy < base_top) {
		c = vec3(0.30, 0.22, 0.15) * (0.9 + 0.1 * step(foot_y + 0.25, vy));   // MDF, a dark foot line
	} else {
		float lv = (vy - base_top) / band_m;
		float k = mod(floor(lv), 2.0);
		c = mix(vec3(0.86, 0.82, 0.70), vec3(0.80, 0.76, 0.66), k);
		float u = fract(lv);
		float fw = fwidth(lv);
		c *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, max(fw * 1.2, 0.01), min(u, 1.0 - u)));
	}
	// The flock's lip: the ground's green over the top 0.4 m of the cut.
	float lip = smoothstep(-0.45, -0.25, vy - vtop);
	c = mix(c, flock_col * 0.9, lip);
	ALBEDO = c;
	ROUGHNESS = 0.95;
}
