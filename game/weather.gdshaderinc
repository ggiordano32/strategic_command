// The weather pass, the look (2026-11-06; game/weather.gd): the shader globals every board, tree and kit shader reads, so no
// material needs plumbing. Registered in project.godot [shader_globals], set once a battle by Weather.apply_globals().
//   wx_surf = (wet, snow cover, mud, gloss): rain wets the board (darker, glossy in 3D), snow covers it, mud strengthens the
//             tracks' stamps; gloss is 0 on Graphics Low.
//   wx_tmul = (r, g, b, desaturation) and wx_tadd = (r, g, b, 0): the season's grade of the board and the trees.
#ifndef WX_INC
#define WX_INC
global uniform vec4 wx_surf;
global uniform vec4 wx_tmul;
global uniform vec4 wx_tadd;

vec3 wx_veg(vec3 c) {
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, vec3(l), wx_tmul.a);
	return c * wx_tmul.rgb + wx_tadd.rgb;
}

// Snow on a roof or a wall top: up = how much the face looks up (0..1).
vec3 wx_snow_on(vec3 c, float up) {
	vec3 snow = vec3(0.92, 0.94, 0.99);
	return mix(c, snow * (0.82 + 0.18 * dot(c, vec3(0.3, 0.59, 0.11))), clamp(wx_surf.y * up, 0.0, 1.0));
}
#endif
