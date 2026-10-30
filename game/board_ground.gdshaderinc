// A texture lying on the ground (a Sprite2D, centered = false, no region: the streets, the Paths hatch) in the oblique
// view (tabletop pass 3, game/board_view.gd): the quad is stretched over the board area its ground can rise to, and
// each pixel finds its ground point (ob_world) and samples the texture there, so the texture rides the lifted ground
// exactly as the terrain does. The top view: the sprite as before.
#include "res://game/board_view.gdshaderinc"

varying vec2 v_b;       // world px (top) or board px (oblique)
varying vec4 v_rect;    // the texture's world rect: origin, size

// (Varyings are set by the caller: v_b = the returned vertex, v_rect = ob_ground_rect(model, tps).)
vec2 ob_ground_vertex(vec2 vtx, vec2 uv, mat4 model) {
	vec2 w = (model * vec4(vtx, 0.0, 1.0)).xy;
	if (ob_on > 0.5) {
		return vec2(w.x, w.y * OB_COS - (uv.y < 0.5 ? ob_lrange.x : ob_lrange.y));
	}
	return w;
}

vec4 ob_ground_rect(mat4 model, vec2 tps) {
	return vec4(model[3].xy, vec2(model[0].x, model[1].y) / tps);
}

// The world point under this pixel and the texture's uv there (z: 1 inside the texture, else 0).
vec3 ob_ground_uv(out vec2 w) {
	w = ob_on > 0.5 ? ob_world(v_b) : v_b;
	vec2 uv = (w - v_rect.xy) / v_rect.zw;
	float inside = step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
	return vec3(uv, inside);
}
