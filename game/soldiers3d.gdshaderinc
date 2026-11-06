// The 3D battle view's men (game/view3d.gd, docs/design/art_pipeline.md "The 3D battle view, step one"): every man a painted
// card standing on the board at his feet, facing the camera, cut from the oblique sheets (game/sprite_ob.gd), his sheet direction
// picked against the camera's yaw (the sheets' contract: 8 directions relative to the camera, the key light in camera space, so a
// figure seen from a turned camera is the same figure turned the other way: `cam_yaw` added on soldiers.gdshaderinc's one line).
// The action, frame, tints and palette are soldiers.gdshaderinc's oblique branch (place_ob, atlas_frame, place: copied here, the
// same numbers); an action the set has no upright frames for (the stand-in's death) lies on the board as the top-down sprite.
//
// Data: one MultiMesh (TRANSFORM_3D, no custom data) whose buffer is the soldier layer's CPU-fed buffer as it is (12 floats a man,
// game/soldier_layer.gd STRIDE): the 2D layout's first 8 floats land where the 3D transform's do (MODEL_MATRIX [3].xy current
// position, [0].xy previous, [1].x facing, [1].y state + 16 x heading code) and its custom data (sprite + 16 x height dm, flags,
// sprite set + 64 x palette, index) in the transform's third row ([0..3].z), read back here; no texture is read in the vertex stage
// for the data. The ground height: the fine lift field (one texture read in the vertex stage, soldiers3d.gdshader) or the coarse
// grid's uniforms (`#define CPU_FED`, soldiers3d_cpu.gdshader: the compatible path, the board mesh then the same grid).
// Depth sorts men, houses, walls and trees (no per-tick order, no occluder, no ghosts behind walls): the card is moved toward the
// camera along the view (its screen place unchanged) just enough that the sheet's part below the feet clears the ground in front.
// Unshaded (the light is painted in), alpha-cut so it writes depth and casts a shadow. The world lamp (2026-11-06): in the shadow
// pass (the view is not the camera's) the card stands upright at the feet facing the lamp, so a man's shadow is the same at every
// yaw (a card in the camera's plane leans back and its shadow grew and shrank as the table turned); and the paint's highlight is
// on the camera's left, so with the table turned the card is shaded across (side_k: the side toward the lamp lighter, the side
// away darker, 0 at the opening yaw). `BASES` (soldier_bases3d.gdshader): the round flocked base with the faction's rim, flat on the board.
#define V3D
#include "res://game/board_view.gdshaderinc"
#include "res://game/fx_light3d.gdshaderinc"
#ifndef CPU_FED
#define CPU_FED   // (after board_view: the fine variant keeps its texture; the frame table is always the constants)
#endif
#include "res://game/sprite_frames.gdshaderinc"

uniform sampler2D ob_shade : filter_linear_mipmap, repeat_disable;
uniform sampler2D ob_mask : filter_linear_mipmap, repeat_disable;
uniform sampler2D ob_tab : filter_nearest, repeat_disable;
uniform vec4 ob_cell[64];
uniform vec2 ob_sheet = vec2(1024.0, 1024.0);
uniform float ob_maxf = 8.0;
uniform float sheet_ppm = 24.0;       // sheet px per metre (SpriteOb.ppm)
uniform float ppm = 10.0;             // world px per metre
uniform float alpha = 1.0;
uniform float px_per_unit = 0.01;
uniform float now = 0.0;
uniform float anim_on = 1.0;
uniform vec3 color_side0 = vec3(0.35, 0.6, 1.0);
uniform vec3 color_side1 = vec3(1.0, 0.36, 0.28);
uniform sampler2D atlas_shade : filter_linear_mipmap, repeat_disable;
uniform sampler2D atlas_mask : filter_linear_mipmap, repeat_disable;
uniform sampler2D pal_tex : filter_nearest, repeat_disable;
uniform sampler2D proc_tex : filter_linear, repeat_disable;   // the procedural sprites (soldier_layer.gd _make_atlas)
uniform vec3 cam_r = vec3(1.0, 0.0, 0.0);
uniform vec3 cam_u = vec3(0.0, 0.766, -0.643);
uniform vec3 cam_b = vec3(0.0, 0.643, 0.766);
uniform float cam_yaw = 0.0;
uniform float side_k = 0.0;           // view3d.gd SIDE_K turned by the camera's yaw against the lamp's
uniform float low = 0.0;

const int SPRITES = 12;
const float CELL_X0 = -1.6;
const float CELL_W = 6.0;
const float CELL_Y0 = -1.25;
const float CELL_H = 2.5;
const float OB_SIN_REF = 0.7660444431;   // the stored lifts' 40 degrees (BoardView.OBLIQUE_SIN)

varying vec4 v_color;
varying vec4 v_look;
varying vec4 v_ob;
varying vec4 v_b;
varying vec2 v_c;
varying float v_seed;
varying float v_side;

vec4 sprite_rect(int spr) {
	if (spr == 0) { return vec4(-0.6, 0.85, -0.6, 0.6); }
	if (spr == 1) { return vec4(-0.6, 2.35, -0.6, 0.6); }
	if (spr == 2) { return vec4(-0.75, 4.45, -0.6, 0.6); }
	if (spr == 3) { return vec4(-0.6, 0.75, -0.62, 0.62); }
	if (spr == 4) { return vec4(-0.6, 1.5, -0.62, 0.62); }
	if (spr == 5) { return vec4(-1.45, 1.7, -0.62, 0.62); }
	if (spr == 6) { return vec4(-0.55, 0.6, -0.55, 0.55); }
	if (spr == 7) { return vec4(-1.2, 1.45, -1.05, 1.05); }
	if (spr == 9) { return vec4(-1.55, 1.95, -0.62, 0.62); }
	if (spr == 10) { return vec4(-1.6, 2.55, -1.25, 1.25); }
	if (spr == 11) { return vec4(-0.6, 0.65, -0.3, 0.3); }
	return vec4(-1.6, 1.75, -1.0, 1.0);
}

void tint(inout vec3 add, inout float k, vec3 target, float amt) {
	add = add * (1.0 - amt) + target * amt;
	k *= 1.0 - amt;
}

float ob_count(float packed, int a) {
	float d = 1.0;
	if (a == 1) { d = 16.0; }
	if (a == 2) { d = 256.0; }
	if (a == 3) { d = 4096.0; }
	if (a == 4) { d = 65536.0; }
	if (a == 5) { d = 1048576.0; }
	return mod(floor(packed / d), 16.0);
}

// The top-down atlas frame (soldiers.gdshaderinc atlas_frame): uv in -> atlas uv out, lp = the quad corner in metres.
void atlas_frame(int set, int st, vec2 vel, float ang, bool shoot, bool fired, bool gun, float idx, inout vec2 uv, out vec2 lp) {
	float moved = length(vel);
	int act = 0;
	float pick = 0.0;
	float fix = -1.0;
	if (st >= 6) {
		if (st == 7) {
			act = 3;
			pick = -1.0;
		} else if (st >= 9) {
			act = 2;
			fix = float(st - 9);
		} else if (st == 6 && moved >= 20.0) {
			act = 1;
		}
	} else if (st == 4) {
		act = 3;
		pick = -1.0;
	} else if (st == 3) {
		act = 3;
		pick = 1.0;
	} else if (st == 1 || (shoot && moved < 20.0)) {
		act = 2;
	} else if (st == 2 || moved >= 20.0) {
		act = 1;
	}
	int k = ((set - 1) * ACTIONS + act) * 2;
	vec4 a = frame_entry(k);
	vec4 b = frame_entry(k + 1);
	float n = b.w;
	float fr = 0.0;
	if (fix >= 0.0) {
		fr = min(fix, n - 1.0);
	} else if (pick < 0.0) {
		fr = n - 1.0;
	} else if (act == 3) {
		fr = min(pick, n - 1.0);
	} else if (anim_on > 0.5) {
		float phase = fract(idx * 0.6180339);
		float cyc = floor(now * 0.1 * action_fps(act) + phase * n);
		fr = mod(cyc, n);
	}
	vec2 px = vec2(uv.x * a.z, uv.y * a.w);
	lp = (px - b.xy) / 24.0;
	uv = (vec2(a.x + fr * b.z, a.y) + px) / ATLAS_SIZE;
}

// The flat stand-in (soldiers.gdshaderinc place): the top-down sprite lying on the ground, world px.
vec2 place_flat(vec2 p, float ang, int st, int spr, int set, int side, bool sel, bool fire, bool shoot, bool fired, bool gun,
		float idx, vec2 vel, int pal, float deadfade, inout vec2 uv, out vec4 col, out vec4 look) {
	vec4 r = sprite_rect(spr);
	bool engine = st >= 6;
	bool dead = st == 4 || st == 7 || st == 8;
	vec3 base = side == 0 ? color_side0 : color_side1;
	look = vec4(0.0);
	vec2 lp;
	if (set > 0) {
		atlas_frame(set, st, vel, ang, shoot, fired, gun, idx, uv, lp);
	} else {
		lp = vec2(mix(r.x, r.y, uv.x), mix(r.z, r.w, uv.y));
		uv = vec2((float(spr) + (lp.x - CELL_X0) / CELL_W) / float(SPRITES), (lp.y - CELL_Y0) / CELL_H);
	}
	vec2 v = lp * ppm;
	if (set > 0) {
		vec3 add = vec3(0.0);
		float k = 1.0;
		float a = 1.0;
		if (st == 8) {
			tint(add, k, vec3(0.24, 0.2, 0.16), 0.25);
		} else if (dead) {
			tint(add, k, vec3(0.22, 0.19, 0.16), 0.4);
			a = 0.9 * deadfade;
		} else {
			if (st == 2) { tint(add, k, vec3(1.0, 0.95, 0.5), 0.3); }
			else if (st == 3) { tint(add, k, vec3(0.1), 0.3); }
			if (fire) { tint(add, k, vec3(1.0, 0.7, 0.3), 0.15); }
			if (sel) { tint(add, k, vec3(1.0), 0.35); }
		}
		col = vec4(add, a);
		look = vec4(1.0, float(pal), k, 0.0);
	} else if (engine) {
		vec3 c = mix(vec3(0.85, 0.72, 0.52), base, 0.3);
		if (dead) { c = mix(c, vec3(0.15, 0.12, 0.1), 0.7); } else if (sel) { c = mix(c, vec3(1.0), 0.35); }
		col = vec4(c, 1.0);
	} else if (dead) {
		v *= vec2(0.8, 0.55);
		col = vec4(mix(base, vec3(0.22, 0.16, 0.12), 0.75), 0.75 * deadfade);
	} else {
		vec3 c = base;
		if (st == 1) { c = mix(c, vec3(1.0), 0.15); }
		else if (st == 2) { c = mix(c, vec3(1.0, 0.95, 0.5), 0.55); }
		else if (st == 3) { c = mix(c, vec3(0.1), 0.45); ang += 1.5708; v *= 0.85; }
		if (fire) { c = mix(c, vec3(1.0, 0.7, 0.3), 0.2); }
		if (sel) { c = mix(c, vec3(1.0), 0.45); }
		col = vec4(c, 1.0);
	}
	float cs = cos(ang);
	float sn = sin(ang);
	return vec2(v.x * cs - v.y * sn, v.x * sn + v.y * cs) + p;
}

// The base radius in metres by sprite (soldier_bases.gdshaderinc).
float base_radius(int spr) {
	if (spr == 11) { return 0.36; }
	if (spr == 5 || spr == 9) { return 0.65; }
	if (spr == 10) { return 1.1; }
	return 0.5;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	float sbw = floor(MODEL_MATRIX[1].y + 0.5);   // state + 16 x hd
	float hdw = floor(sbw / 16.0);
	int hd = int(hdw);
	int st = int(sbw - hdw * 16.0);
	vec2 cur = MODEL_MATRIX[3].xy;
	vec2 prv = MODEL_MATRIX[0].xy;
	float facing = MODEL_MATRIX[1].x;
	float spx = floor(MODEL_MATRIX[0].z + 0.5);   // sprite + 16 x his height (dm)
	int spr = clamp(int(mod(spx, 16.0)), 0, SPRITES - 1);
	float ext_m = floor(spx / 16.0) * 0.1;
	float fl = floor(MODEL_MATRIX[1].z + 0.5);    // side + 2 selected + 4 under fire + 8 shooting + 16 fired + 32 gun
	int side = int(mod(fl, 2.0));
	bool sel = mod(floor(fl / 2.0), 2.0) > 0.5;
	bool fire = mod(floor(fl / 4.0), 2.0) > 0.5;
	bool shoot = mod(floor(fl / 8.0), 2.0) > 0.5;
	bool fired = mod(floor(fl / 16.0), 2.0) > 0.5;
	bool gun = mod(floor(fl / 32.0), 2.0) > 0.5;
	// Suppression's stand-in crouch (+ 64 x level: 1 suppressed, 2 pinned; soldiers.gdshaderinc crouch_ob): the card squashed
	// toward the feet, a little darker.
	float crc = st == 0 ? mod(floor(fl / 64.0), 4.0) : 0.0;
	vec2 crk = crc > 1.5 ? vec2(0.9, 0.6) : (crc > 0.5 ? vec2(0.94, 0.76) : vec2(1.0));
	float lk = floor(MODEL_MATRIX[2].z + 0.5);    // sprite set + 64 x palette
	int set = int(mod(lk, 64.0));
	int pal = int(floor(lk / 64.0));
	float idx = MODEL_MATRIX[3].z;
	v_color = vec4(0.0);
	v_look = vec4(0.0);
	v_ob = vec4(0.0, 0.0, -1.0, 0.0);
	v_b = vec4(0.0);
	v_c = vec2(0.0);
	v_seed = 0.0;
	v_side = 0.0;
	vec2 uv = vec2(UV.x, 1.0 - UV.y);   // (the card's corner: world_vertex_coords hands VERTEX in already placed)
	vec2 pw = mix(prv, cur, alpha) * px_per_unit;   // world px
	float gy = ob_lift_px(pw) / (ppm * OB_SIN_REF) + ext_m;
	vec3 feet = vec3(pw.x / ppm, gy, pw.y / ppm);
	float deadfade = (st == 4 && hd > 0) ? float(hd) / 32.0 : 1.0;
#ifdef BASES
	if (st == 5 || st >= 6) {
		VERTEX = vec3(0.0, -10000.0, 0.0);
	} else {
		float r = base_radius(spr);
		vec2 c = (uv * 2.0 - 1.0) * 1.15;
		v_b = vec4(float(pal), deadfade * (st == 4 ? 0.9 : 1.0), 1.0, 0.0);
		v_c = c;
		v_seed = hash12(floor(cur * 0.004));
		VERTEX = feet + vec3(c.x * r, 0.03, c.y * r);
	}
#else
	if (st == 5) {
		VERTEX = vec3(0.0, -10000.0, 0.0);
	} else {
		vec2 vel = cur - prv;
		float moved = length(vel);
		int act = 0;
		float pick = 0.0;
		float fix = -1.0;
		if (st >= 6) {
			if (st == 7) { act = 3; pick = -1.0; }
			else if (st >= 9) { act = 2; fix = float(st - 9); }
			else if (st == 6 && moved >= 20.0) { act = 1; }
		} else if (st == 4) {
			act = 3;
			pick = -1.0;
		} else if (st == 3) {
			act = 3;
			pick = 1.0;
		} else if (st == 1 || (shoot && moved < 20.0)) {
			act = 2;
		} else if (st == 2 || moved >= 20.0) {
			act = 1;
		}
		float yaw = facing;
		if (hd > 0 && st == 0) {
			int hh = hd - 1;
			int stp = hh / 1024;
			yaw = float(hh - stp * 1024) - float(stp - 64) * (1.0 - alpha);
		}
		float ang = yaw * (6.2831853 / 1024.0);
		float rate = st == 2 ? 1.6 : 1.0;
		float rev = 1.0;
		if (act == 1 && st == 0) {
			vec2 fwd = vec2(cos(ang), sin(ang));
			float along = dot(vel, fwd);
			if (along < -0.5 * moved) {
				rate = 0.5;
				rev = -1.0;
			} else if (along < 0.5 * moved) {
				rate = 0.7;
			}
		}
		vec4 cell = set > 0 ? ob_cell[set] : vec4(0.0);
		float n = ob_count(cell.w, act);
		if (set <= 0 || n < 0.5) {
			vec4 col;
			vec4 look;
			vec2 pos = place_flat(pw, ang, st, spr, set, side, sel, fire, shoot, fired, gun, idx, vel, pal, deadfade, uv, col, look);
			VERTEX = vec3(pos.x / ppm, gy + 0.05, pos.y / ppm);
			UV = uv;
			v_color = col;
			v_look = look;
		} else {
			float fr = 0.0;
			if (fix >= 0.0) {
				fr = min(fix, n - 1.0);
			} else if (pick < 0.0) {
				fr = n - 1.0;
			} else if (act == 3) {
				fr = min(pick, n - 1.0);
			} else if (anim_on > 0.5) {
				float phase = fract(idx * 0.6180339);
				if (act == 2 && gun && n > 3.0) {
					float cg = floor(now * 0.1 * action_fps(act) * 0.35 + phase * 3.0);
					float q = mod(cg, 3.0);
					fr = fired ? 1.0 : (q < 0.5 ? 0.0 : q + 1.0);
				} else {
					float cyc = floor(now * 0.1 * action_fps(act) * rate + phase * n);
					fr = mod(rev < 0.0 ? n - 1.0 - cyc : cyc, n);
				}
			}
			// The direction against the camera (0 facing it, clockwise in 45 degree steps): the oblique view's line with the yaw.
			float dir = mod(floor((ang + cam_yaw - 1.5707963) / 0.7853982 + 0.5), 8.0);
			vec2 lp = vec2(mix(-cell.x, cell.x, uv.x), mix(-cell.y, cell.z, uv.y));   // sheet px from the feet
			// Toward the camera along the view: the sheet's lowest point (cell.z below the feet) clears the ground in front.
			float cot_e = length(cam_b.xz) / max(cam_b.y, 0.2);
			float dz = cell.z / sheet_ppm * cot_e + 0.12;
			vec3 cr = cam_r;
			vec3 cu = cam_u;
			if (dot(INV_VIEW_MATRIX[2].xyz, cam_b) < 0.999) {
				// The shadow pass: upright at the feet, facing the lamp (its view's x is level).
				cr = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
				cu = vec3(0.0, 1.0, 0.0);
				dz = 0.0;
			}
			VERTEX = feet + (cr * lp.x * crk.x - cu * lp.y * crk.y) / sheet_ppm + cam_b * dz;
			v_side = side_k * clamp(lp.x * crk.x / (0.32 * sheet_ppm), -1.0, 1.0);
			v_ob = vec4(lp, ((float(act) * 8.0 + dir) * ob_maxf + fr) * 2.0, float(set));
			vec3 add = vec3(0.0);
			float k = 1.0;
			float a = 1.0;
			bool dead = st == 4 || st == 7 || st == 8;
			if (st == 8) {
				tint(add, k, vec3(0.24, 0.2, 0.16), 0.25);
			} else if (dead) {
				tint(add, k, vec3(0.22, 0.19, 0.16), 0.4);
				a = 0.9 * deadfade;
			} else {
				if (st == 2) { tint(add, k, vec3(1.0, 0.95, 0.5), 0.3); }
				else if (st == 3) { tint(add, k, vec3(0.1), 0.3); }
				if (fire) { tint(add, k, vec3(1.0, 0.7, 0.3), 0.15); }
				if (sel) { tint(add, k, vec3(1.0), 0.35); }
				if (crc > 0.5) { k *= crc > 1.5 ? 0.8 : 0.9; }
			}
			v_color = vec4(add, a);
			v_look = vec4(1.0, float(pal), k, 0.0);
		}
	}
#endif
}

vec3 recolour(vec4 s, vec4 m, int row, float k, vec3 add) {
	vec4 c3 = texelFetch(pal_tex, ivec2(3, row), 0);
	float pat = clamp((1.0 - m.a) * 2.0, 0.0, 1.0) * c3.a;
	vec3 team = m.r * mix(texelFetch(pal_tex, ivec2(0, row), 0).rgb, c3.rgb, pat)
		+ m.g * texelFetch(pal_tex, ivec2(1, row), 0).rgb + m.b * texelFetch(pal_tex, ivec2(2, row), 0).rgb;
	float rest = max(0.0, 1.0 - m.r - m.g - m.b);
	return s.rgb * (rest + team) * k + add;
}

#ifdef BASES
vec3 flock_col(vec2 c, float seed) {
	vec2 q = c / 0.2 + vec2(seed * 37.0, seed * 91.0);
	vec2 id = floor(q);
	vec2 f = fract(q) - 0.5;
	float h = hash12(id);
	float h2 = hash12(id + vec2(7.7, 3.1));
	vec2 jit = vec2(hash12(id + vec2(1.3, 9.9)), hash12(id + vec2(5.5, 2.2))) - 0.5;
	float rr = 0.26 + 0.22 * h2;
	float sp = 1.0 - smoothstep(rr - 0.12, rr, length(f - jit * 0.35));
	vec3 g1 = vec3(0.17, 0.34, 0.08);
	vec3 g2 = vec3(0.30, 0.48, 0.12);
	vec3 straw = vec3(0.62, 0.54, 0.28);
	vec3 sc = h < 0.45 ? g1 : (h < 0.8 ? g2 : straw);
	vec3 earth = vec3(0.24, 0.17, 0.09);
	vec3 col = mix(earth, sc, sp);
	vec3 mean = mix(earth, vec3(0.30, 0.43, 0.15), 0.45);
	return mix(col, mean, smoothstep(0.07, 0.14, fwidth(c.x)));
}

void fragment() {
	vec3 prim = texelFetch(pal_tex, ivec2(0, int(v_b.x + 0.5)), 0).rgb;
	float d = length(v_c);
	if (d > 1.0 || v_b.y < 0.5) {
		discard;
	}
	vec3 col;
	if (low > 0.5) {
		col = vec3(0.12, 0.1, 0.07);
	} else {
		float ring = step(0.74, d);
		float luma = dot(prim, vec3(0.3, 0.59, 0.11));
		vec3 inner = mix(flock_col(v_c, v_seed), mix(vec3(luma), prim, 0.5) * 0.9, 0.1) * 0.85;
		col = mix(inner, prim * 0.4, ring);
	}
	ALBEDO = col;
}
#else
void fragment() {
	vec4 outc;
	if (v_ob.z >= 0.0) {
		ivec2 tc = ivec2(int(v_ob.z + 0.5), int(v_ob.w + 0.5));
		vec4 fr = texelFetch(ob_tab, tc, 0);                  // x0, y0, w, h
		vec4 an = texelFetch(ob_tab, tc + ivec2(1, 0), 0);    // anchor x, anchor y, mirrored
		vec2 lp = v_ob.xy;
		if (an.z > 0.5) {
			lp.x = -lp.x;
		}
		vec2 fp = an.xy + lp;
		float inside = step(0.0, fp.x) * step(0.0, fp.y) * step(fp.x, fr.z) * step(fp.y, fr.w);
		vec2 uvo = (fr.xy + clamp(fp, vec2(0.0), fr.zw)) / ob_sheet;
		vec4 so = texture(ob_shade, uvo);
		vec4 mo = texture(ob_mask, uvo);
		outc = vec4(recolour(so, mo, int(v_look.y + 0.5), v_look.z, v_color.rgb) * (1.0 + v_side), so.a * v_color.a * inside);
	} else {
		vec4 s = texture(atlas_shade, UV);
		vec4 m = texture(atlas_mask, UV);
		if (v_look.x > 0.5) {
			outc = vec4(recolour(s, m, int(v_look.y + 0.5), v_look.z, v_color.rgb), s.a * v_color.a);
		} else {
			outc = texture(proc_tex, UV) * v_color;
		}
	}
	vec3 fcol = outc.rgb;
	if (flash_n > 0) {
		// a muzzle flash going off near him lights him warm (game/fx3d.gd)
		vec3 fl = fx_flash_light((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
		fcol = fcol * (1.0 + fl * 0.6) + fl * 0.05;
	}
	ALBEDO = clamp(fcol, vec3(0.0), vec3(1.0));
	ALPHA = outc.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
#endif
