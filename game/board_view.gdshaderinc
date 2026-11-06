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
// Pass 6 (the hills): the fine lift field. ob_fine 1: ob_lift_px reads the half-float texture ob_ftex (one bilinear fetch, nodes
// of ob_fgeo.x world px, ob_fgeo.yz of them along x, y; the node i at i x cell) and, when ob_fq.x > 0, snaps it to the terrain's foam
// bands (ob_fq: band in lift px, 1 / band, offset, ramp share): each riser is a short ramp, a vertical face on the board. The
// CPU-fed soldier shaders (CPU_FED) cannot read a texture in the vertex stage and always use the coarse grid (BoardView.use_grid).
uniform float ob_fine = 0.0;
uniform vec4 ob_fgeo = vec4(20.0, 2.0, 2.0, 0.0);
uniform vec4 ob_fq = vec4(0.0, 1.0, 0.0, 0.18);
#ifndef CPU_FED
uniform sampler2D ob_ftex : filter_linear, repeat_disable;
#endif

#ifdef V3D
// The 3D view (game/board_view.gd set_view): the camera's right and toward-the-viewer directions on the ground, (sin, cos) of its
// elevation, and the stored lifts' scale to that elevation. ob_board below is then the 3D camera's projection of the ground.
uniform vec2 ob_r = vec2(1.0, 0.0);
uniform vec2 ob_f = vec2(0.0, 1.0);
uniform vec2 ob_cs = vec2(0.6427876097, 0.7660444431);
uniform float ob_lk = 1.0;
#endif

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

highp float ob_quant(highp float l) {
	if (ob_fq.x <= 0.0) {
		return l;
	}
	highp float lv = l * ob_fq.y + ob_fq.z;
	highp float n = floor(lv + 0.5);
	highp float t = clamp((lv + 0.5 - n) / ob_fq.w, 0.0, 1.0);
	return (n - 1.0 + t * t * (3.0 - 2.0 * t) - ob_fq.z) * ob_fq.x;
}

float ob_lift_px(vec2 w) {
#ifndef CPU_FED
	if (ob_fine > 0.5) {
		vec2 uv = (clamp(w, vec2(0.0), ob_field) / ob_fgeo.x + 0.5) / ob_fgeo.yz;
		return ob_quant(textureLod(ob_ftex, uv, 0.0).r);
	}
#endif
	return ob_lift_dy(w).x;
}

// World point (px, at ground level) -> board point (px).
vec2 ob_board(vec2 w) {
#ifdef V3D
	return vec2(dot(w, ob_r), dot(w, ob_f) * ob_cs.x - ob_lift_px(w) * ob_lk);
#else
	return vec2(w.x, w.y * OB_COS - ob_lift_px(w));
#endif
}

// Board point -> the ground point under it. The coarse grid: Newton steps on y (the lift is linear along y inside a cell).
// The fine field: the nearest root of y x COS - lift(b.x, y) = b.y, marched from the near end of the lift's range in 14 steps
// until the function changes sign, then 5 bisections (the steps' risers are ramps: the function is continuous).
vec2 ob_world(vec2 b) {
#ifndef CPU_FED
	if (ob_fine > 0.5) {
		float y_hi = (b.y + ob_lrange.x) / OB_COS;
		float y_lo = (b.y + ob_lrange.y) / OB_COS;
		if (y_hi - y_lo < 0.05) {
			return vec2(b.x, y_hi);
		}
		float stp = (y_hi - y_lo) / 14.0;
		float ya = y_hi;
		float yb = y_lo;
		for (int it = 1; it <= 14; it++) {
			float y = y_hi - stp * float(it);
			if (y * OB_COS - ob_lift_px(vec2(b.x, y)) - b.y <= 0.0) {
				yb = y;
				break;
			}
			ya = y;
		}
		for (int it = 0; it < 5; it++) {
			float ym = 0.5 * (ya + yb);
			if (ym * OB_COS - ob_lift_px(vec2(b.x, ym)) - b.y > 0.0) {
				ya = ym;
			} else {
				yb = ym;
			}
		}
		return vec2(b.x, 0.5 * (ya + yb));
	}
#endif
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
