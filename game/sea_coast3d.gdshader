shader_type spatial;
// The sea battle's land as a modelled terrain piece (stage D2 part 1; game/sea_coast3d.gd builds the mesh): the 2D screen's own
// fragment (game/sea_land_body.gdshaderinc: the ground palette, beach, cliff rock, woods, the diorama's bevel) painted on a relief
// mesh from the baked signed distance (the beach rising from the drawn shore, a cliff where steep), lit by the painted key only
// (a face turned from the key reads darker, a face to it lighter, flat ground at its painted value), alpha-cut at the drawn shore so
// the water shows wherever the sim has no land (shore_ok: the water is never drawn over sim land, the land never over sim sea) and
// the mesh writes depth for the trees, forts and ships. The board's cut edge: a skirt (vertex colour r = 1) down to the slab's foot
// with strata. No vertex texture reads (the compatible path).
render_mode unshaded, cull_disabled;

#include "res://game/sea_land_body.gdshaderinc"

varying vec3 wpos;
varying vec3 wnrm;
varying float skirt;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = NORMAL;
	skirt = COLOR.r;
}

void fragment() {
	if (skirt > 0.5) {
		float band = 0.5 + 0.5 * sin(wpos.y * 2.7 + sin(wpos.x * 0.21 + wpos.z * 0.17) * 1.4);
		vec3 rc = mix(rock_col * 0.62, rock_col * 0.92, band);
		ALBEDO = rc;
		ALPHA = 1.0;
	} else {
		vec4 c = sea_land_color(wpos.xz);
		vec3 n = normalize(wnrm);
		vec3 L = normalize(vec3(-0.62, 1.10, -0.78));
		float lit = clamp(1.0 + 1.7 * (dot(n, L) - L.y), 0.5, 1.4);
		ALBEDO = c.rgb * lit;
		ALPHA = c.a;
	}
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
