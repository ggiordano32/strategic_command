shader_type canvas_item;
// Many antialiased polylines and lines in ONE mesh (ink_lines.gd; overworld frame time, 2026-10-27, view only).
// The vertex shader rebuilds, per vertex, exactly the geometry Godot's canvas_item_add_polyline / add_line make
// for `antialiased = true` (servers/rendering/renderer_canvas_cull.cpp, 4.7: the middle strip, the left and right
// feather strips, the caps; a line's quad and its eight feather quads), so the picture is the one of the
// draw_polyline / draw_multiline calls it replaces, with one draw call instead of three per polyline.
// Widths follow the uniform `lw` (map px per screen px): a zoom changes a uniform, not the mesh.
// A vertex is (code, -1e6 - polyline id): code = point index in its polyline * 16 + side bits (polyline) or
// segment * 64 + corner (line). Anything else drawn on the node (y above -5e5) passes through unchanged.
uniform sampler2D ink_p : filter_nearest, repeat_disable;    // RGF: the points (map px)
uniform sampler2D ink_o : filter_nearest, repeat_disable;    // RGF: each point's offset, times `ls`
uniform sampler2D ink_par : filter_nearest, repeat_disable;  // RGBAF, 2 texels a polyline: colour; (k, first, n, flags)
uniform int tex_w = 1024;
uniform float lw = 1.0;   // width scale: a polyline is k * lw map px wide
uniform float ls = 1.0;   // offset scale

const float FEATHER = 1.25;
const float EPS = 0.00001;

vec2 fetch_p(int q, bool off) {
	ivec2 c = ivec2(q % tex_w, q / tex_w);
	vec2 p = texelFetch(ink_p, c, 0).rg;
	if (off) {
		p += texelFetch(ink_o, c, 0).rg * ls;
	}
	return p;
}

vec2 gnorm(vec2 v) {
	float l = v.x * v.x + v.y * v.y;
	if (l != 0.0) {
		l = sqrt(l);
		return v / l;
	}
	return v;
}

vec2 orth(vec2 v) {
	return vec2(v.y, -v.x);
}

bool feq(float a, float b) {
	if (a == b) {
		return true;
	}
	float tol = EPS * abs(a);
	if (tol < EPS) {
		tol = EPS;
	}
	return abs(a - b) < tol;
}

vec2 clamped(vec2 sd, vec2 pd) {
	float len = 1.0;
	vec2 bis = gnorm(pd * length(sd) - sd * length(pd));
	float ang = atan(bis.x * pd.y - bis.y * pd.x, dot(bis, pd));
	float sa = sin(ang);
	if (!(abs(sa) < EPS) && !(feq(sd.x, pd.x) && feq(sd.y, pd.y))) {
		len = clamp(1.0 / sa, -3.0, 3.0);
	} else {
		bis = orth(sd);
	}
	if (abs(bis.x) < EPS && abs(bis.y) < EPS) {
		bis = orth(sd);
	}
	return bis * len;
}

float comp(float w) {
	if (w > 0.0) {
		if (w <= FEATHER * 2.0 + EPS) {
			return w * 0.5;
		} else if (w <= FEATHER * 4.0 + EPS) {
			float a = w * 0.5;
			float b = w - FEATHER * 0.5;
			return a + (b - a) * (w - FEATHER * 2.0) / (FEATHER * 2.0);
		}
		return w - FEATHER * 0.5;
	}
	return w;
}

void vertex() {
	if (VERTEX.y < -500000.0) {
		int id = int(round(-VERTEX.y - 1000000.0));
		int code = int(round(VERTEX.x));
		ivec2 pc = ivec2((id * 2) % tex_w, (id * 2) / tex_w);
		vec4 col = texelFetch(ink_par, pc, 0);
		vec4 par = texelFetch(ink_par, pc + ivec2(1, 0), 0);
		float k = par.x;
		int first = int(round(par.y));
		int n = int(round(par.z));
		int flags = int(round(par.w));
		bool off = (flags & 2) != 0;
		float w = comp(k * lw);
		bool clear = false;
		vec2 v;
		if ((flags & 4) != 0) {
			// a line (canvas_item_add_line): code = segment * 64 + E + 2 * U + 4 * (sv + 1) + 12 * (sw + 1)
			int sg = code / 64;
			int c = code % 64;
			int e = c & 1;
			float su = (c & 2) != 0 ? 1.0 : -1.0;
			float sv = float((c / 4) % 3) - 1.0;
			float sw = float(c / 12) - 1.0;
			vec2 from = fetch_p(first + sg * 2, off);
			vec2 to = fetch_p(first + sg * 2 + 1, off);
			vec2 diff = from - to;
			vec2 dir = gnorm(orth(diff));
			float bs = FEATHER;
			if (0.0 <= w && w < 1.0) {
				bs *= w;
			}
			vec2 t = dir * w * 0.5;
			v = (e == 1 ? to : from) + su * t + sv * (dir * bs) + sw * (gnorm(diff) * bs);
			clear = sv != 0.0 || sw != 0.0;
		} else {
			// a polyline (canvas_item_add_polyline): code = i * 16 + S + 2 * B + 4 * CB + 8 * CE
			int i = code / 16;
			int c = code % 16;
			float s = (c & 1) != 0 ? 1.0 : -1.0;
			float b = (c & 2) != 0 ? 1.0 : 0.0;
			float cb = (c & 4) != 0 ? 1.0 : 0.0;
			float ce = (c & 8) != 0 ? 1.0 : 0.0;
			bool loop = (flags & 1) != 0;
			vec2 p = fetch_p(first + i, off);
			vec2 seg;
			vec2 prv;
			vec2 beo;
			if (i == 0) {
				seg = gnorm(fetch_p(first + 1, off) - p);
				if (loop) {
					prv = gnorm(fetch_p(first + n - 1, off) - fetch_p(first + n - 2, off));
					beo = clamped(seg, prv);
				} else {
					prv = vec2(0.0);
					beo = orth(seg);
				}
			} else if (i == n - 1) {
				seg = gnorm(p - fetch_p(first + i - 1, off));
				if (loop) {
					prv = gnorm(fetch_p(first + 1, off) - fetch_p(first, off));
					beo = clamped(seg, prv);
				} else {
					prv = seg;
					beo = orth(seg);
				}
			} else {
				seg = gnorm(fetch_p(first + i + 1, off) - p);
				prv = gnorm(p - fetch_p(first + i - 1, off));
				beo = clamped(seg, prv);
			}
			float bs = FEATHER;
			if (w < 1.0) {
				bs *= w;
			}
			v = p + beo * (s * w * 0.5) + beo * (s * b * bs) - seg * (cb * bs) + prv * (ce * bs);
			clear = b + cb + ce > 0.0;
		}
		VERTEX = v;
		COLOR *= clear ? vec4(col.rgb, 0.0) : col;
	}
}
