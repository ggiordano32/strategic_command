// The oblique battle view's board transform (tabletop pass 3; game/board_view.gd holds the same maths and sets these
// uniforms with BoardView.apply). A ground point w (world px) goes to the board point
//     (w.x, w.y * OB_COS - lift(w))
// lift: bilinear over the coarse lift grid (board px per node, `ob_lift` packed four to a vec4), clamped to the field.
// ob_on 0: the top view (callers keep their old placement). No texture reads, no bit operators: usable in the vertex
// stage of the CPU-fed soldier shaders too (uniform arrays are read in the vertex stage, as the kit trees do).
uniform float ob_on = 0.0;
uniform vec4 ob_geo = vec4(200.0, 2.0, 2.0, 0.0);   // cell px, nodes along x, nodes along y, -
uniform vec2 ob_field = vec2(4000.0, 4000.0);       // the field, world px
uniform vec2 ob_lrange = vec2(0.0, 0.0);           // the grid's highest and lowest lift, board px
uniform vec4 ob_lift[211];

const float OB_COS = 0.6427876097;   // cos(50 deg): ground y on the board
const float OB_SIN = 0.7660444431;   // sin(50 deg): heights on the board
const float OB_UP_K = 0.999;         // BoardView.UP_K: the upright draw mark

float ob_node(int i) {
	int q = i / 4;
	vec4 v = ob_lift[q];
	int c = i - q * 4;
	if (c == 0) { return v.x; }
	if (c == 1) { return v.y; }
	if (c == 2) { return v.z; }
	return v.w;
}

// (lift, d lift / d y) at world point w (board px; per world px).
vec2 ob_lift_dy(vec2 w) {
	vec2 g = clamp(w, vec2(0.0), ob_field) / ob_geo.x;
	int nx = int(ob_geo.y + 0.5);
	int ny = int(ob_geo.z + 0.5);
	int i0 = clamp(int(floor(g.x)), 0, nx - 2);
	int j0 = clamp(int(floor(g.y)), 0, ny - 2);
	vec2 f = clamp(g - vec2(float(i0), float(j0)), vec2(0.0), vec2(1.0));
	int k = j0 * nx + i0;
	float top = mix(ob_node(k), ob_node(k + 1), f.x);
	float bot = mix(ob_node(k + nx), ob_node(k + nx + 1), f.x);
	float d = (w.y > 0.0 && w.y < ob_field.y) ? (bot - top) / ob_geo.x : 0.0;
	return vec2(mix(top, bot, f.y), d);
}

float ob_lift_px(vec2 w) {
	return ob_lift_dy(w).x;
}

// World point (px, at ground level) -> board point (px).
vec2 ob_board(vec2 w) {
	return vec2(w.x, w.y * OB_COS - ob_lift_px(w));
}

// Board point -> the ground point under it (Newton steps on y; the lift is linear along y inside a cell).
vec2 ob_world(vec2 b) {
	float y = b.y / OB_COS;
	for (int it = 0; it < 4; it++) {
		vec2 l = ob_lift_dy(vec2(b.x, y));
		float f = y * OB_COS - l.x - b.y;
		y -= f / max(OB_COS - l.y, 0.2 * OB_COS);
	}
	return vec2(b.x, y);
}

// Nearness along the view (world px; larger = nearer the camera) of ground point w, h_px world px above the ground.
float ob_near(vec2 w, float h_px) {
	return w.y * OB_SIN + (ob_lift_px(w) / OB_SIN + h_px) * OB_COS;
}

// True when the draw transform carries BoardView.up_xf's mark (the next items are drawn upright at its anchor).
bool ob_up_marked(mat4 m) {
	return abs(m[1].y - OB_UP_K) < 0.00002 && abs(m[0].x - 1.0) < 0.00002 && abs(m[1].x) < 0.00002 && abs(m[0].y) < 0.00002;
}
