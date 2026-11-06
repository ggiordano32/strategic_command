// Soldiers (and artillery engines): the body shared by the two variants,
// soldiers.gdshader (the per-man data texture, the default) and
// soldiers_cpu.gdshader (CPU-fed: per-instance data in the MultiMesh, for
// devices whose WebGL draws nothing from a texture read in the vertex
// stage, e.g. Chrome on an Adreno 650 tablet, 2026-10-08). One MultiMesh
// instance per soldier; artillery engines follow the soldiers.
//
// Texture variant: positions come straight from the sim's int arrays: the
// view uploads them once per tick as raw bytes in an RGBA8 texture (one
// texel = one int32, little endian), and the shader decodes them and
// interpolates between the previous and current tick. Texture blocks (each
// `rows_per_block` rows of `tex_width` texels):
//   0 pos_x, 1 pos_y, 2 prev_x, 3 prev_y, 4 facing, 5 state, 6 unit_of,
//   7 unit flags (indexed by unit: bit0 side, bit1 selected, bit2 under
//     fire, bit3 shooting, bits 4-7 sprite, bits 8-11 engine sprite,
//     bits 12-17 sprite set (6 bits: 63 sets), bits 18-21 palette, bit 22 fired a gun shot
//     in the last 0.3 s, bit 23 a powder-weapon unit),
//   8 unit engine set (indexed by unit, 6 bits; its own block: the bits above
//     24 do not survive the float decode); the oblique view + 64 x the wall walk's height (dm); both + 2^20 x the
//     suppression crouch (1 suppressed, 2 pinned; crouch_ob)
//   the oblique view: 9 the per-tick draw order, 10 a man's height on a stone
//     stair's flight (dm, 0 else; soldier_layer.gd _stair_lift)
//
// CPU-fed variant (render_mode skip_vertex_transform): the same sim ints,
// converted to floats natively and interleaved into the MultiMesh buffer by
// soldier_layer.gd, read back through MODEL_MATRIX (layer node at identity):
//   [3].xy current position, [0].xy previous position, [1].x facing,
//   [1].y state; INSTANCE_CUSTOM.x sprite, .y side + 2 selected + 4 under
//   fire + 8 shooting + 16 fired + 32 gun + 64 x the crouch (suppression: 1 suppressed, 2 pinned), .z sprite set (engines: engine set) + 64 x palette, .w the instance's
//   index. No texture fetch, uniform array, int uniform or bit operator in
//   the vertex stage. Both variants draw the same pixels.
//
// Instances past the soldiers are artillery engines (state 6 working,
// 9-12 working and shooting with attack frame 0-3 from the reload, 7
// wrecked, 8 abandoned; 7 and 8 drawn with the corpses). An engine whose
// unit has an engine set draws from the atlas (step 1d): idle, walk while
// it moves (packed, or carried), attack frame by its state, wrecked = the
// death's last frame, abandoned = idle darkened.
//
// Drawn heading (view only, soldier_layer.gd `_update_yaw`): the state word
// (texture block 5, CPU [1].y) is state + 16 x hd. hd 0: the man is drawn at
// the sim's facing. hd > 0: a formed man whose own movement is large (or whose
// unit turns) is drawn at his view-side heading, h = hd - 1 = yaw + 1024 x
// (step + 64): yaw 0..1023 is this tick's heading (1024 a turn, the sim's
// angle), step the change since the last tick (a yaw-rate capped turn); the
// shader interpolates yaw - step x (1 - alpha). A formed man who walks
// sideways or backwards against his heading (re-forming, dressing the line)
// plays the atlas's "sidestep" (6 frames, a shuffle to his left, mirrored in
// the shader for a step to the right) or "backstep" action where his set has
// them (heavy swords, spearmen, pikemen: sets whose table rows repeat the
// walk have none), else the walk cycle slower (sideways 0.7 x, backwards 0.5 x)
// and, for steps to the left and backwards, reversed.
//
// Sprites: one atlas, SPRITES cells side by side. Each cell maps the local
// box x (forward) -1.6..4.4 m, y (right) -1.25..1.25 m. The quad drawn per
// soldier covers only its sprite's rect of that box (soldier_layer.gd
// SPR_RECT), so infantry stay small and pikes and horses get long quads,
// all in this one draw call.
//
// Sprite sets (step 1b of the sprite pipeline, tools/sprites): units whose
// type has a sprite_set > 0 are drawn from the Blender-rendered atlas
// (atlas_shade / atlas_mask, game/sprite_frames.gdshaderinc for the frame
// table) and recoloured in the fragment stage by their faction's palette
// (pal_tex: one row per palette, primary, secondary, accent, pattern + k),
// as tools/sprites/preview/recolor.gdshader. Per man an action from his
// state (dead: the death's last frame; knocked down: its middle frame;
// fighting, or shooting while standing: attack; moving or routing: walk;
// else idle) and a frame from the view clock `now` (ticks, interpolated)
// plus a phase from his index, so a block does not step in lockstep. The
// side is not painted on the man: his unit's marker and the selection tint
// show it. View only: nothing here feeds back to the sim.
//
// The oblique view (tabletop pass 3, `#define OBLIQUE`: soldiers_ob.gdshader, soldiers_ob_cpu.gdshader; game/
// board_view.gd): each man an upright quad standing at his feet's board point (the ground squashed and lifted, plus his
// wall walk's height), his frame from the oblique sheets (game/sprite_ob.gd: the set's quad from `ob_cell` here, the
// frame's rect looked up in `ob_tab` in the fragment stage, so the CPU-fed path needs no texture read in the vertex
// stage) by his drawn heading against the camera (8 directions, S facing it), mirrored where the sheet says; an
// action without upright frames (the stand-in's death) is the top-down sprite lying on the board. The texture path
// draws its instances through a per-tick order (block 9: the men sorted by ground y, nearer over farther); the CPU-fed
// buffer is reordered by soldier_layer.gd. A man behind a nearer kit piece (the kit's nearness, `ob_occ`, a screen
// texture: game/kit_occluder.gd) is drawn as a ghost: flat in his faction's colour at 40 % with a 1 px lighter
// outline (his base is not drawn); behind a wall stretch that is fading he shows through it.
#include "res://game/sprite_frames.gdshaderinc"
#ifdef OBLIQUE
#include "res://game/board_view.gdshaderinc"
uniform sampler2D ob_shade : filter_linear_mipmap, repeat_disable;
uniform sampler2D ob_mask : filter_linear_mipmap, repeat_disable;
uniform sampler2D ob_tab : filter_nearest, repeat_disable;
uniform vec4 ob_cell[64];
uniform vec2 ob_sheet = vec2(1024.0, 1024.0);
uniform float ob_k = 0.4166667;      // board px per sheet px
uniform float ob_maxf = 8.0;         // frames per (action, direction) in the table
uniform sampler2D ob_occ : filter_nearest, repeat_disable;
uniform float ob_occ_on = 0.0;
uniform vec2 ob_near_r = vec2(0.0, 1.0);   // the kit nearness encoding: origin, span (world px)
varying vec4 v_ob;     // upright: sheet px from the feet (x right, y down), the table column, the set; z < 0: flat
varying float v_near;  // the man's nearness (world px)
#endif

const int SPRITES = 12;
const float CELL_X0 = -1.6;
const float CELL_W = 6.0;
const float CELL_Y0 = -1.25;
const float CELL_H = 2.5;

uniform float alpha = 1.0;          // interpolation 0 = prev tick, 1 = current
uniform float px_per_unit = 0.01;   // view pixels per sim unit
uniform vec3 color_side0 = vec3(0.35, 0.6, 1.0);
uniform vec3 color_side1 = vec3(1.0, 0.36, 0.28);
uniform float now = 0.0;            // view clock in ticks (tick - 1 + alpha)
uniform float anim_on = 1.0;        // 0: atlas men hold their first frame
uniform sampler2D atlas_shade : filter_linear_mipmap, repeat_disable;
uniform sampler2D atlas_mask : filter_linear_mipmap, repeat_disable;
uniform sampler2D pal_tex : filter_nearest, repeat_disable;

varying vec4 v_color;
// Atlas men: x 1 (else procedural), y palette row, z: colour = recoloured
// x z + v_color.rgb (the state tints folded into one multiply-add).
varying vec4 v_look;

#ifdef CPU_FED
uniform float layer_pass = 1.0;     // 0 = corpses only, 1 = living only

// soldier_layer.gd SPR_RECT (xmin, xmax, ymin, ymax in metres per sprite).
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
#else
uniform sampler2D data_tex : filter_nearest;
uniform int rows_per_block = 1;
uniform int tex_width = 1024;
uniform int layer_pass = 1;         // 0 = corpses only, 1 = living only
// xmin, xmax, ymin, ymax in metres per sprite (see soldier_layer.gd).
uniform vec4 spr_rect[12];

// Portability (mobile WebGL drivers): the instance's index comes from
// INSTANCE_CUSTOM (x + 2048 * y, written once by soldier_layer.gd), not
// INSTANCE_ID, and the int32s are decoded with float maths (exact below
// 2^24 in magnitude), with no uint, bitwise or % operators.
int slot_index(vec4 cd) {
	return int(cd.x + 0.5) + int(cd.y + 0.5) * 2048;
}

int fetch_int(int block, int idx) {
	int row = idx / tex_width;
	ivec2 p = ivec2(idx - row * tex_width, block * rows_per_block + row);
	vec4 b = floor(texelFetch(data_tex, p, 0) * 255.0 + 0.5);
	if (b.a >= 128.0) {
		vec4 c = vec4(255.0) - b;  // negative: two's complement
		return -int(c.r + c.g * 256.0 + c.b * 65536.0 + c.a * 16777216.0) - 1;
	}
	return int(b.r + b.g * 256.0 + b.b * 65536.0 + b.a * 16777216.0);
}

// A bit field of a non-negative int: (v / div) mod span (div, span powers of 2).
int bitfield(int v, int div, int span) {
	int q = v / div;
	return q - (q / span) * span;
}

#endif

// One visible soldier or engine: its quad corner (from UV) placed in the
// layer's space (pos), its atlas UV and its colour (col). st: state; r: the
// sprite's rect; side 0 / 1; sel: unit selected; fire: under missile fire.
// A state tint folded into (add, k): colour' = colour x k + add.
void tint(inout vec3 add, inout float k, vec3 target, float amt) {
	add = add * (1.0 - amt) + target * amt;
	k *= 1.0 - amt;
}

// Atlas men: the action from the state, the frame from the clock and the
// man's phase; uv in -> atlas uv out, lp = the quad corner in metres.
void atlas_frame(int set, int st, vec2 vel, float ang, bool shoot, bool fired, bool gun, float idx, inout vec2 uv, out vec2 lp) {
	float moved = length(vel);
	int act = 0;
	float pick = 0.0;  // < 0: the death's last frame; 1: its middle frame
	float fix = -1.0;  // >= 0: this frame (engines shooting)
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
	// A formed man walking against his heading (re-forming, dressing the
	// line): a set with its own frames (heavy swords, spearmen, pikemen)
	// plays "sidestep" (rendered to his left; mirrored for a step to the
	// right) or "backstep"; the others keep the walk, slower, and a left or
	// backward step reversed.
	bool mirror = false;
	float rate = st == 2 ? 1.6 : 1.0;  // routing: running
	float rev = 1.0;
	if (act == 1 && st == 0 && anim_on > 0.5) {
		vec2 fwd = vec2(cos(ang), sin(ang));
		float along = dot(vel, fwd);
		bool back = along < -0.5 * moved;
		if (back || along < 0.5 * moved) {
			bool left = dot(vel, vec2(-fwd.y, fwd.x)) < 0.0;
			int own = ((set - 1) * ACTIONS + (back ? 5 : 4)) * 2;
			if (frame_entry(own).x != frame_entry(((set - 1) * ACTIONS + 1) * 2).x) {
				act = back ? 5 : 4;
				mirror = !back && !left;
			} else if (back) {
				rate = 0.5;
				rev = -1.0;
			} else {
				rate = 0.7;
				rev = left ? -1.0 : 1.0;
			}
		}
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
		if (act == 2 && gun && n > 3.0) {
			// Powder weapons: attack frame 1 is the muzzle flash, shown only
			// for a fresh shot; aiming and reloading cycle 0, 2, 3 slowly.
			float cg = floor(now * 0.1 * action_fps(act) * 0.35 + phase * 3.0);
			float q = mod(cg, 3.0);
			fr = fired ? 1.0 : (q < 0.5 ? 0.0 : q + 1.0);
		} else {
			float cyc = floor(now * 0.1 * action_fps(act) * rate + phase * n);
			fr = mod(rev < 0.0 ? n - 1.0 - cyc : cyc, n);
		}
	}
	vec2 px = vec2(uv.x * a.z, uv.y * a.w);  // corner in the frame, px
	lp = (px - b.xy) / 24.0;                 // metres (ATLAS_PX_PER_M)
	if (mirror) {
		lp.y = -lp.y;
	}
	uv = (vec2(a.x + fr * b.z, a.y) + px) / ATLAS_SIZE;
}

void place(vec2 cur, vec2 prv, float facing, int hd, int st, int spr, vec4 r, int side, bool sel, bool fire,
		int set, int pal, bool shoot, bool fired, bool gun, float idx, inout vec2 uv, out vec2 pos, out vec4 col, out vec4 look) {
	if (st == 4) { prv = cur; }   // (a body lies where he fell: the sim never moves a dead man, his stale previous place is not drawn)
	bool engine = st >= 6;
	bool dead = st == 4 || st == 7 || st == 8;
	// A dead man's heading code is his sink (1..32 over the 10 s the oldest body of a full table goes into the ground, 0: not sinking).
	float deadfade = (st == 4 && hd > 0) ? float(hd) / 32.0 : 1.0;
	vec2 p = mix(prv, cur, alpha) * px_per_unit;
	float yaw = facing;
	if (hd > 0 && st == 0) {
		int hh = hd - 1;
		int stp = hh / 1024;
		yaw = float(hh - stp * 1024) - float(stp - 64) * (1.0 - alpha);
	}
	float ang = yaw * (6.2831853 / 1024.0);
	vec3 base = side == 0 ? color_side0 : color_side1;
	look = vec4(0.0);
	vec2 lp;
	if (set > 0) {
		atlas_frame(set, st, cur - prv, ang, shoot, fired, gun, idx, uv, lp);
	} else {
		lp = vec2(mix(r.x, r.y, uv.x), mix(r.z, r.w, uv.y));
		uv = vec2((float(spr) + (lp.x - CELL_X0) / CELL_W) / float(SPRITES),
			(lp.y - CELL_Y0) / CELL_H);
	}
	vec2 v = lp * (px_per_unit * 1024.0);
	if (set > 0) {
		vec3 add = vec3(0.0);
		float k = 1.0;
		float a = 1.0;
		if (st == 8) {
			tint(add, k, vec3(0.24, 0.2, 0.16), 0.25);  // an abandoned engine
		} else if (dead) {
			tint(add, k, vec3(0.22, 0.19, 0.16), 0.4);   // greyed a little
			a = 0.9 * deadfade;
		} else {
			if (st == 2) {
				tint(add, k, vec3(1.0, 0.95, 0.5), 0.3);   // routing
			} else if (st == 3) {
				tint(add, k, vec3(0.1), 0.3);              // knocked down
			}
			if (fire) {
				tint(add, k, vec3(1.0, 0.7, 0.3), 0.15);   // under missile fire
			}
			if (sel) {
				tint(add, k, vec3(1.0), 0.35);             // selected unit
			}
		}
		col = vec4(add, a);
		look = vec4(1.0, float(pal), k, 0.0);
	} else if (engine) {
		// Timber in a light tint of the side colour; wrecks dark.
		vec3 c = mix(vec3(0.85, 0.72, 0.52), base, 0.3);
		if (dead) {
			c = mix(c, vec3(0.15, 0.12, 0.1), 0.7);
		} else if (sel) {
			c = mix(c, vec3(1.0), 0.35);
		}
		col = vec4(c, 1.0);
	} else if (dead) {
		v *= vec2(0.8, 0.55);
		col = vec4(mix(base, vec3(0.22, 0.16, 0.12), 0.75), 0.75 * deadfade);
	} else {
		vec3 c = base;
		if (st == 1) {
			c = mix(c, vec3(1.0), 0.15);  // fighting
		} else if (st == 2) {
			c = mix(c, vec3(1.0, 0.95, 0.5), 0.55);  // routing
		} else if (st == 3) {
			c = mix(c, vec3(0.1), 0.45);  // knocked down: dark, on its side
			ang += 1.5708;
			v *= 0.85;
		}
		if (fire) {
			c = mix(c, vec3(1.0, 0.7, 0.3), 0.2);  // under missile fire
		}
		if (sel) {
			c = mix(c, vec3(1.0), 0.45);  // selected unit
		}
		col = vec4(c, 1.0);
	}
	float cs = cos(ang);
	float sn = sin(ang);
	pos = vec2(v.x * cs - v.y * sn, v.x * sn + v.y * cs) + p;
}

#ifdef OBLIQUE
// Frames of action a in a set's packed counts (4 bits each).
float ob_count(float packed, int a) {
	float d = 1.0;
	if (a == 1) { d = 16.0; }
	if (a == 2) { d = 256.0; }
	if (a == 3) { d = 4096.0; }
	if (a == 4) { d = 65536.0; }
	if (a == 5) { d = 1048576.0; }
	return mod(floor(packed / d), 16.0);
}

// The oblique view: an upright figure where the set has frames for his action, else the top-down sprite lying on the
// board (place(), squashed and lifted). ext: height above the ground (a wall walk), world px.
void place_ob(vec2 cur, vec2 prv, float facing, int hd, int st, int spr, vec4 r, int side, bool sel, bool fire,
		int set, int pal, bool shoot, bool fired, bool gun, float idx, float ext, inout vec2 uv, out vec2 pos, out vec4 col, out vec4 look,
		out vec4 ob, out float near) {
	if (st == 4) { prv = cur; }   // (a body lies where he fell: the sim never moves a dead man, his stale previous place is not drawn)
	vec2 p = mix(prv, cur, alpha) * px_per_unit;
	vec2 anchor = ob_board(p) - vec2(0.0, ext * OB_SIN);
	near = ob_near(p, ext);
	vec2 vel = cur - prv;
	float moved = length(vel);
	// The action and its frame (as atlas_frame; the re-form steps keep the walk, slower, a back step reversed).
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
		place(cur, prv, facing, hd, st, spr, r, side, sel, fire, set, pal, shoot, fired, gun, idx, uv, pos, col, look);
		pos = vec2(pos.x, anchor.y + (pos.y - p.y) * OB_COS);
		ob = vec4(0.0, 0.0, -1.0, 0.0);
		return;
	}
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
	// The direction against the camera (it looks north): 0 S (facing it), clockwise in 45 degree steps.
	float dir = mod(floor((ang - 1.5707963) / 0.7853982 + 0.5), 8.0);
	vec2 lp = vec2(mix(-cell.x, cell.x, uv.x), mix(-cell.y, cell.z, uv.y));   // sheet px from the feet
	pos = anchor + lp * ob_k;
	ob = vec4(lp, ((float(act) * 8.0 + dir) * ob_maxf + fr) * 2.0, float(set));
	// The state tints (as the atlas men's).
	vec3 add = vec3(0.0);
	float k = 1.0;
	float a = 1.0;
	bool dead = st == 4 || st == 7 || st == 8;
	float deadfade = (st == 4 && hd > 0) ? float(hd) / 32.0 : 1.0;
	if (st == 8) {
		tint(add, k, vec3(0.24, 0.2, 0.16), 0.25);
	} else if (dead) {
		tint(add, k, vec3(0.22, 0.19, 0.16), 0.4);
		a = 0.9 * deadfade;
	} else {
		if (st == 2) {
			tint(add, k, vec3(1.0, 0.95, 0.5), 0.3);
		} else if (st == 3) {
			tint(add, k, vec3(0.1), 0.3);
		}
		if (fire) {
			tint(add, k, vec3(1.0, 0.7, 0.3), 0.15);
		}
		if (sel) {
			tint(add, k, vec3(1.0), 0.35);
		}
	}
	col = vec4(add, a);
	look = vec4(1.0, float(pal), k, 0.0);
}
#endif

// Suppression's stand-in crouch (2026-11-06; the sheets have no crouch pose). Second pass (the fourth evaluation: the
// squash read as pale mushrooms): the oblique figure keeps its width and is lowered (a suppressed man to 90 % of his
// height, a pinned one to 80 %) and leaned toward the way he faces (the top of the card sheared 14 % / 28 % of its
// height: a man hunched forward over his piece), and darker (both the shade and the state tint's colour, so it does
// not wash pale); the top view's figure smaller round his place (88 % / 78 %) and darker still. Applied to the placed
// quad, so the frame and its texels are the sheet's own. View only (soldier_layer.gd: CPU flags + 64 x level; the
// texture path's block 8 + 2^20 x level).
vec2 crouch_ob(vec2 pos, vec2 an, float c, float facing) {
	float hk = c > 1.5 ? 0.8 : 0.9;
	float lean = c > 1.5 ? 0.28 : 0.14;
	float h = (an.y - pos.y) * hk;   // (above the feet, screen px, lowered)
	return vec2(pos.x + h * lean * cos(facing * (6.2831853 / 1024.0)), an.y - h);
}
float crouch_top(float c) {
	return c > 1.5 ? 0.78 : 0.88;
}
void crouch_tint(float c, inout vec4 col, inout vec4 look) {
	float d = c > 1.5 ? 0.72 : 0.86;
	if (look.x > 0.5) {
		look.z *= d;
	}
	col.rgb *= d;
}

void vertex() {
#ifdef CPU_FED
	float sbw = floor(MODEL_MATRIX[1].y + 0.5);  // state + 16 x hd
	float hdw = floor(sbw / 16.0);
	int hd = int(hdw);
	int st = int(sbw - hdw * 16.0);
	bool want_dead = layer_pass < 0.5;
#else
	int i = slot_index(INSTANCE_CUSTOM);
#ifdef OBLIQUE
	i = fetch_int(9, i);       // the instance's man in the per-tick order (nearer over farther)
#endif
	int sb = fetch_int(5, i);  // state + 16 x hd
	int hd = sb / 16;
	int st = sb - hd * 16;
	bool want_dead = layer_pass == 0;
#endif
	// 0 formed, 1 fighting, 2 routing, 3 knocked down, 4 dead, 5 off field;
	// engines: 6 working, 7 wrecked, 8 abandoned, 9-12 shooting
	bool dead = st == 4 || st == 7 || st == 8;
	if (st == 5 || dead != want_dead) {
		VERTEX = vec2(-100000.0);
		v_color = vec4(0.0);
		v_look = vec4(0.0);
#ifdef OBLIQUE
		v_ob = vec4(0.0, 0.0, -1.0, 0.0);
		v_near = 0.0;
#endif
	} else {
		vec2 pos;
		vec4 col;
		vec4 look;
		vec2 uv = UV;
#ifdef CPU_FED
#ifdef OBLIQUE
		float spx = floor(INSTANCE_CUSTOM.x + 0.5);   // sprite + 16 x his wall walk's height (dm)
		int spr = clamp(int(mod(spx, 16.0)), 0, SPRITES - 1);
		float ext = floor(spx / 16.0) * 0.1 * px_per_unit * 1024.0;
#else
		int spr = clamp(int(INSTANCE_CUSTOM.x + 0.5), 0, SPRITES - 1);
#endif
		float fl = floor(INSTANCE_CUSTOM.y + 0.5);  // side + 2 selected + 4 under fire + 8 shooting
		int side = int(mod(fl, 2.0));
		bool sel = mod(floor(fl / 2.0), 2.0) > 0.5;
		bool fire = mod(floor(fl / 4.0), 2.0) > 0.5;
		bool shoot = mod(floor(fl / 8.0), 2.0) > 0.5;
		bool fired = mod(floor(fl / 16.0), 2.0) > 0.5;
		bool gun = mod(floor(fl / 32.0), 2.0) > 0.5;
		float crc = st == 0 ? mod(floor(fl / 64.0), 4.0) : 0.0;  // the crouch: 1 suppressed, 2 pinned
		float lk = floor(INSTANCE_CUSTOM.z + 0.5);  // sprite set + 64 x palette
		int set = int(mod(lk, 64.0));
		int pal = int(floor(lk / 64.0));
#ifdef OBLIQUE
		vec4 ob;
		float near;
		place_ob(MODEL_MATRIX[3].xy, MODEL_MATRIX[0].xy, MODEL_MATRIX[1].x, hd, st, spr, sprite_rect(spr),
			side, sel, fire, set, pal, shoot, fired, gun, INSTANCE_CUSTOM.w, ext, uv, pos, col, look, ob, near);
		if (crc > 0.5) {
			vec2 an = ob_board(mix(MODEL_MATRIX[0].xy, MODEL_MATRIX[3].xy, alpha) * px_per_unit) - vec2(0.0, ext * OB_SIN);
			pos = crouch_ob(pos, an, crc, MODEL_MATRIX[1].x);
			crouch_tint(crc, col, look);
		}
		v_ob = ob;
		v_near = near;
#else
		place(MODEL_MATRIX[3].xy, MODEL_MATRIX[0].xy, MODEL_MATRIX[1].x, hd, st, spr, sprite_rect(spr),
			side, sel, fire, set, pal, shoot, fired, gun, INSTANCE_CUSTOM.w, uv, pos, col, look);
		if (crc > 0.5) {
			vec2 pc = mix(MODEL_MATRIX[0].xy, MODEL_MATRIX[3].xy, alpha) * px_per_unit;
			pos = pc + (pos - pc) * crouch_top(crc);
			crouch_tint(crc, col, look);
		}
#endif
		// skip_vertex_transform: pos is already in the layer's (= canvas) space.
		VERTEX = pos;
#else
		vec2 cur = vec2(float(fetch_int(0, i)), float(fetch_int(1, i)));
		vec2 prv = vec2(float(fetch_int(2, i)), float(fetch_int(3, i)));
		int uidx = fetch_int(6, i);
		int flags = fetch_int(7, uidx);
		int spr = clamp(st >= 6 ? bitfield(flags, 256, 16) : bitfield(flags, 16, 16), 0, SPRITES - 1);
#ifdef OBLIQUE
		vec4 ob;
		float near;
		int u8 = fetch_int(8, uidx);   // engine set + 64 x the wall walk's height (dm) + 2^20 x the crouch
		int cri = u8 / 1048576;
		u8 -= cri * 1048576;
		float ext = float(u8 / 64 + fetch_int(10, i)) * 0.1 * px_per_unit * 1024.0;
		place_ob(cur, prv, float(fetch_int(4, i)), hd, st, spr, spr_rect[spr], bitfield(flags, 1, 2),
			bitfield(flags, 2, 2) != 0, bitfield(flags, 4, 2) != 0,
			st >= 6 ? bitfield(u8, 1, 64) : bitfield(flags, 4096, 64),
			bitfield(flags, 262144, 16), bitfield(flags, 8, 2) != 0,
			bitfield(flags, 4194304, 2) != 0, bitfield(flags, 8388608, 2) != 0, float(i),
			ext, uv, pos, col, look, ob, near);
		if (cri > 0 && st == 0) {
			vec2 an = ob_board(mix(prv, cur, alpha) * px_per_unit) - vec2(0.0, ext * OB_SIN);
			pos = crouch_ob(pos, an, float(cri), float(fetch_int(4, i)));
			crouch_tint(float(cri), col, look);
		}
		v_ob = ob;
		v_near = near;
#else
		int u8t = fetch_int(8, uidx);   // engine set (+ 2^20 x the crouch)
		int crt = u8t / 1048576;
		u8t -= crt * 1048576;
		place(cur, prv, float(fetch_int(4, i)), hd, st, spr, spr_rect[spr], bitfield(flags, 1, 2),
			bitfield(flags, 2, 2) != 0, bitfield(flags, 4, 2) != 0,
			st >= 6 ? bitfield(u8t, 1, 64) : bitfield(flags, 4096, 64),
			bitfield(flags, 262144, 16), bitfield(flags, 8, 2) != 0,
			bitfield(flags, 4194304, 2) != 0, bitfield(flags, 8388608, 2) != 0, float(i), uv, pos, col, look);
		if (crt > 0 && st == 0) {
			vec2 pc = mix(prv, cur, alpha) * px_per_unit;
			pos = pc + (pos - pc) * crouch_top(float(crt));
			crouch_tint(float(crt), col, look);
		}
#endif
		// Instance transforms are identity; cancel whatever origin this
		// instance has (the engine applies MODEL_MATRIX after this).
		VERTEX = pos - MODEL_MATRIX[3].xy;
#endif
		UV = uv;
		v_color = col;
		v_look = look;
	}
}

// The faction recolour of an atlas texel (shade s, mask m) in palette row `row`, times k, plus the tint add.
vec3 recolour(vec4 s, vec4 m, int row, float k, vec3 add) {
	vec4 c3 = texelFetch(pal_tex, ivec2(3, row), 0);  // pattern colour, a = pattern_k
	float pat = clamp((1.0 - m.a) * 2.0, 0.0, 1.0) * c3.a;
	vec3 team = m.r * mix(texelFetch(pal_tex, ivec2(0, row), 0).rgb, c3.rgb, pat)
		+ m.g * texelFetch(pal_tex, ivec2(1, row), 0).rgb + m.b * texelFetch(pal_tex, ivec2(2, row), 0).rgb;
	float rest = max(0.0, 1.0 - m.r - m.g - m.b);
	return s.rgb * (rest + team) * k + add;
}

#ifdef OBLIQUE
// The ghost of a man behind a nearer kit piece: his figure flat in his faction's colour (the palette's primary) at 40 %,
// a 1 px lighter outline where a neighbour pixel is outside the figure (`edge`); `a` the figure's coverage.
vec4 ob_ghost(float a, float edge) {
	vec3 fc = mix(texelFetch(pal_tex, ivec2(0, int(v_look.y + 0.5)), 0).rgb, vec3(0.85), 0.15);
	return vec4(mix(fc, mix(fc, vec3(1.0), 0.6), edge), step(0.35, a) * mix(0.4, 0.8, edge) * v_color.a);
}
#endif

void fragment() {
#ifdef OBLIQUE
	// Behind a nearer kit piece (a house, a wall, a tower, a rock): a ghost (his corpse: not drawn); behind a wall
	// stretch that is fading (the camera close, game/battlekit.gd ob_fade_update) he shows through it, as its fade.
	float occ = 0.0;
	float ofade = 0.0;
	if (ob_occ_on > 0.5) {
		vec4 o = texture(ob_occ, SCREEN_UV);
		float on = (floor(o.r * 255.0 + 0.5) * 256.0 + floor(o.g * 255.0 + 0.5)) / 65535.0 * ob_near_r.y + ob_near_r.x;
		if (o.a > 0.5 && on > v_near + 2.0) {
			occ = 1.0;
			ofade = o.b;
		}
	}
#ifdef CPU_FED
	bool corpses = layer_pass < 0.5;
#else
	bool corpses = layer_pass == 0;
#endif
	float spx = max(length(dFdx(v_ob.xy)), length(dFdy(v_ob.xy)));   // sheet px per screen px
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
		COLOR = vec4(recolour(so, mo, int(v_look.y + 0.5), v_look.z, v_color.rgb), so.a * v_color.a * inside);
		if (occ > 0.5) {
			if (corpses) {
				COLOR.a *= ofade * 0.6;
			} else {
				float edge = 0.0;
				for (int q = 0; q < 4; q++) {
					vec2 off = (q == 0 ? vec2(1.0, 0.0) : (q == 1 ? vec2(-1.0, 0.0) : (q == 2 ? vec2(0.0, 1.0) : vec2(0.0, -1.0)))) * spx;
					vec2 fq = fp + off;
					float iq = step(0.0, fq.x) * step(0.0, fq.y) * step(fq.x, fr.z) * step(fq.y, fr.w);
					float aq = iq * textureLod(ob_shade, (fr.xy + clamp(fq, vec2(0.0), fr.zw)) / ob_sheet, 0.0).a;
					edge = max(edge, 1.0 - step(0.35, aq));
				}
				vec4 g = ob_ghost(so.a * inside, edge);
				COLOR = mix(g, vec4(COLOR.rgb, COLOR.a * 0.6), ofade);
			}
		}
	} else {
#endif
	// Every sampler is read unconditionally (implicit derivatives stay
	// defined); the branch only picks the result.
	vec4 proc = texture(TEXTURE, UV) * v_color;
	vec4 s = texture(atlas_shade, UV);
	vec4 m = texture(atlas_mask, UV);
	if (v_look.x > 0.5) {
		int row = int(v_look.y + 0.5);
		vec4 c3 = texelFetch(pal_tex, ivec2(3, row), 0);  // pattern colour, a = pattern_k
		float pat = clamp((1.0 - m.a) * 2.0, 0.0, 1.0) * c3.a;
		vec3 team = m.r * mix(texelFetch(pal_tex, ivec2(0, row), 0).rgb, c3.rgb, pat)
			+ m.g * texelFetch(pal_tex, ivec2(1, row), 0).rgb + m.b * texelFetch(pal_tex, ivec2(2, row), 0).rgb;
		float rest = max(0.0, 1.0 - m.r - m.g - m.b);
		COLOR = vec4(s.rgb * (rest + team) * v_look.z + v_color.rgb, s.a * v_color.a);
	} else {
		COLOR = proc;
	}
#ifdef OBLIQUE
	if (occ > 0.5) {
		// (a flat figure: the ghost without its outline)
		COLOR = corpses ? vec4(COLOR.rgb, COLOR.a * ofade * 0.6) : mix(v_look.x > 0.5 ? ob_ghost(COLOR.a, 0.0)
			: vec4(COLOR.rgb, step(0.35, COLOR.a) * 0.4), vec4(COLOR.rgb, COLOR.a * 0.6), ofade);
	}
	}
#endif
}
