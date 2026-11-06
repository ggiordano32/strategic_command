// The 3D battle view's missiles (game/view3d.gd): projectiles.gdshaderinc's oblique branch in 3D. The soldier layer's CPU-fed
// missile buffer as it is (12 floats a slot: MODEL_MATRIX [3].xy the firing point, [0].xy the landing point, [1].x / [1].y the
// firing / landing tick, and its custom data in the transform's third row: [0].z the shooter's flags (side + 2 x kind, + 16 a fire
// missile), [1].z / [2].z the firing / landing height in dm). The shot flies a straight line through the air from the ground under
// the shooter (plus his height on a wall) to the ground under the target, plus its own arc (a fifth of the range for the lobbed
// kinds), now in real height; the streak is a card in the camera's plane turned along its path on the screen. Alpha-blended.
#define V3D
#include "res://game/board_view.gdshaderinc"
uniform float now = 0.0;
uniform float px_per_unit = 0.01;
uniform float ppm = 10.0;
uniform vec3 cam_r = vec3(1.0, 0.0, 0.0);
uniform vec3 cam_u = vec3(0.0, 0.766, -0.643);
uniform vec3 cam_b = vec3(0.0, 0.643, 0.766);
const float OB_SIN_REF = 0.7660444431;

varying vec4 v_color;
varying vec2 v_uv;
varying float v_kind;
varying float v_fire;
varying float v_aspect;

vec3 at3(vec2 sp, vec2 ep, float ls, float le, float hs, float he, float hk, float span, float f) {
	vec2 g = mix(sp, ep, f);
	return vec3(g.x / ppm, mix(ls, le, f) + mix(hs, he, f) + hk * span * 4.0 * f * (1.0 - f), g.y / ppm);
}

void vertex() {
	float t0 = MODEL_MATRIX[1].x;
	float t1 = MODEL_MATRIX[1].y;
	v_uv = vec2(UV.x, 1.0 - UV.y);
	v_kind = 0.0;
	v_fire = 0.0;
	v_aspect = 1.0;
	v_color = vec4(0.0);
	if (t1 < 0.0 || now < t0 || now > t1 || t1 <= t0) {
		VERTEX = vec3(0.0, -10000.0, 0.0);
	} else {
		float f = (now - t0) / (t1 - t0);
		float fl = floor(MODEL_MATRIX[0].z + 0.5);
		bool fire = false;
		if (fl >= 16.0) {
			fire = true;
			fl -= 16.0;
		}
		int kind = int(floor(fl / 2.0));
		int side = int(mod(fl, 2.0));
		vec2 sp = MODEL_MATRIX[3].xy * px_per_unit;
		vec2 ep = MODEL_MATRIX[0].xy * px_per_unit;
		float ls = ob_lift_px(sp) / (ppm * OB_SIN_REF);
		float le = ob_lift_px(ep) / (ppm * OB_SIN_REF);
		float hs = MODEL_MATRIX[1].z * 0.1;
		float he = MODEL_MATRIX[2].z * 0.1;
		float span = length(ep - sp) / ppm;
		float hk = kind == 2 ? 0.03 : (kind == 1 ? 0.08 : (kind == 3 ? 0.28 : (kind == 5 ? 0.01 : 0.18)));
		vec2 size = vec2(0.9, 0.12);
		if (kind == 1) { size = vec2(1.6, 0.16); }
		else if (kind == 2) { size = vec2(2.0, 0.24); }
		else if (kind == 3) { size = vec2(0.9, 0.9); }
		else if (kind == 4) { size = vec2(0.45, 0.3); }
		else if (kind == 5) { size = vec2(3.0, 0.3); }
		float f1 = min(f + 0.02, 1.0);
		float f0 = f1 - 0.02;
		vec3 p = at3(sp, ep, ls, le, hs, he, hk, span, f);
		vec3 d3 = at3(sp, ep, ls, le, hs, he, hk, span, f1) - at3(sp, ep, ls, le, hs, he, hk, span, f0);
		vec2 ds = vec2(dot(d3, cam_r), dot(d3, cam_u));
		vec2 dir = length(ds) > 1e-5 ? normalize(ds) : vec2(1.0, 0.0);
		vec2 v = (v_uv - vec2(0.5)) * size;
		if (fire && kind < 3) {
			float q = size.x * 3.2;
			v = vec2((v_uv.x - 0.8) * q, (v_uv.y - 0.5) * 0.6);
		}
		vec2 rv = vec2(v.x * dir.x - v.y * dir.y, v.x * dir.y + v.y * dir.x);
		// (a man's chest height: the shots fly at the figures, not along the ground)
		VERTEX = p + vec3(0.0, 1.1, 0.0) + cam_r * rv.x + cam_u * rv.y + cam_b * 0.3;
		vec3 tint = side == 0 ? vec3(0.75, 0.85, 1.0) : vec3(1.0, 0.82, 0.75);
		if (kind == 2) { tint = mix(tint, vec3(0.35, 0.25, 0.15), 0.55); }
		else if (kind == 5) { tint = vec3(0.92, 0.9, 0.84); }
		else if (kind >= 3) { tint = mix(tint, vec3(0.45, 0.43, 0.4), 0.8); }
		if (fire && kind >= 3) { tint = mix(tint, vec3(1.0, 0.55, 0.15), 0.55); }
		v_color = vec4(tint, 0.95);
		v_kind = float(kind);
		if (fire) {
			v_fire = 1.0;
			v_aspect = (kind == 1 ? 1.6 : (kind == 2 ? 2.0 : 0.9)) * 3.2 / 0.6;
		}
	}
}

void fragment() {
	vec4 c4;
	if (v_kind > 4.5) {
		float dx = (0.9 - v_uv.x) * 10.0;
		float dy = (v_uv.y - 0.5) * 2.0;
		float ball = 1.0 - smoothstep(0.6, 1.0, length(vec2(dx, dy)));
		float t = clamp((0.9 - v_uv.x) / 0.9, 0.0, 1.0);
		float streak = (1.0 - smoothstep(0.0, 0.7, abs(dy))) * (1.0 - t) * step(v_uv.x, 0.9) * 0.55;
		c4 = vec4(mix(v_color.rgb, vec3(0.12, 0.1, 0.09), ball), max(streak, ball) * v_color.a);
	} else if (v_kind > 2.5) {
		vec2 q = (v_uv - vec2(0.5)) * 2.0;
		float r = length(q);
		vec3 c = v_color.rgb * (1.1 - 0.5 * clamp(dot(q, vec2(0.6, 0.6)), 0.0, 1.0));
		if (r > 0.75) {
			c *= 0.45;
		}
		c4 = vec4(c, v_color.a * (1.0 - smoothstep(0.85, 1.0, r)));
	} else if (v_fire > 0.5) {
		float dx = (v_uv.x - 0.8) * v_aspect;
		float dy = (v_uv.y - 0.5) * 2.0;
		float r = length(vec2(dx, dy));
		float glow = 1.0 - smoothstep(0.2, 1.0, r);
		float core = 1.0 - smoothstep(0.0, 0.5, r);
		float t = clamp((0.8 - v_uv.x) / 0.8, 0.0, 1.0);
		float tail = (1.0 - smoothstep(0.0, 0.55 * (1.0 - t) + 0.05, abs(dy))) * (1.0 - t) * step(v_uv.x, 0.8);
		vec3 flame = mix(vec3(1.0, 0.55, 0.12), vec3(0.3, 0.27, 0.25), smoothstep(0.35, 0.9, t));
		c4 = vec4(mix(flame, vec3(1.0, 0.92, 0.55), core), max(max(glow * 0.9, tail * 0.85), core));
	} else {
		float across = abs(v_uv.y - 0.5) * 2.0;
		vec3 c = v_color.rgb;
		if (v_uv.x > 0.82) {
			c *= 0.35;
		}
		c4 = vec4(c, v_color.a * (1.0 - smoothstep(0.35, 1.0, across)));
	}
	ALBEDO = c4.rgb;
	ALPHA = c4.a;
}
