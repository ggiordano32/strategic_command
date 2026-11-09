shader_type spatial;
// The sea battle's trees as cards (stage D2 part 1; game/sea_coast3d.gd): the oblique kit sheet's palm, pine, broadleaf and scrub
// sprites standing upright at their foot facing the camera's yaw (as trees3d.gdshader's cards, but upright: the sea camera tilts
// 25-60 degrees). Unshaded (the sheet's painted light), tinted by the shade the way the land battle's trees are, alpha-cut.
render_mode unshaded, cull_disabled, world_vertex_coords;

uniform sampler2D albedo_tex : filter_linear_mipmap, repeat_disable;
uniform vec4 rects[16];
uniform vec4 anch[16];          // size px, anchor px
uniform float mpp = 0.125;      // metres a sprite pixel (the sheet is 8 px a metre)
uniform float up_k = 1.3;       // the sprites are drawn at 40 degrees: a metre of height is cos(40) of a metre of sprite
uniform vec3 shade0 = vec3(0.15, 0.3, 0.13);
uniform vec3 shade1 = vec3(0.19, 0.35, 0.15);
uniform vec3 shade2 = vec3(0.12, 0.25, 0.12);

varying vec2 q;
varying float piece;
varying float tn;
varying float shade;

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	tn = cd.x;
	piece = floor(cd.y + 0.5);
	shade = cd.w;
	vec4 an = anch[int(piece)];
	vec3 foot = MODEL_MATRIX[3].xyz;
	vec2 q01 = vec2(UV.x, 1.0 - UV.y);
	vec2 off = (q01 * an.xy - an.zw) * mpp * cd.z;
	vec3 r = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	VERTEX = foot + r * off.x - vec3(0.0, off.y * up_k, 0.0) + INV_VIEW_MATRIX[2].xyz * 0.6;
	q = q01;
}

void fragment() {
	vec4 r = rects[int(piece)];
	vec4 a = texture(albedo_tex, r.xy + clamp(q, vec2(0.0), vec2(1.0)) * r.zw);
	vec3 base = a.rgb;
	float lum = dot(base, vec3(0.3, 0.59, 0.11));
	bool palm = shade > 2.5;
	vec3 tint = shade < 0.5 ? shade0 : (shade < 1.5 ? shade1 : shade2);
	base = mix(base, lum * tint * 3.2, palm ? 0.15 : 0.6) * tn;
	ALBEDO = clamp(base, vec3(0.0), vec3(1.0));
	ALPHA = a.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
