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
//     fire, bits 4-7 sprite, bits 8-11 engine sprite)
//
// CPU-fed variant (render_mode skip_vertex_transform): the same sim ints,
// converted to floats natively and interleaved into the MultiMesh buffer by
// soldier_layer.gd, read back through MODEL_MATRIX (layer node at identity):
//   [3].xy current position, [0].xy previous position, [1].x facing,
//   [1].y state; INSTANCE_CUSTOM.x sprite, .y side + 2 selected + 4 under
//   fire. No texture fetch, uniform array, int uniform or bit operator in
//   the vertex stage. Both variants draw the same pixels.
//
// Instances past the soldiers are artillery engines (state 6 working,
// 7 wrecked or abandoned, drawn with the corpses).
//
// Sprites: one atlas, SPRITES cells side by side. Each cell maps the local
// box x (forward) -1.6..4.4 m, y (right) -1.25..1.25 m. The quad drawn per
// soldier covers only its sprite's rect of that box (soldier_layer.gd
// SPR_RECT), so infantry stay small and pikes and horses get long quads,
// all in this one draw call.

const int SPRITES = 11;
const float CELL_X0 = -1.6;
const float CELL_W = 6.0;
const float CELL_Y0 = -1.25;
const float CELL_H = 2.5;

uniform float alpha = 1.0;          // interpolation 0 = prev tick, 1 = current
uniform float px_per_unit = 0.01;   // view pixels per sim unit
uniform vec3 color_side0 = vec3(0.35, 0.6, 1.0);
uniform vec3 color_side1 = vec3(1.0, 0.36, 0.28);

varying vec4 v_color;

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
	return vec4(-1.6, 1.75, -1.0, 1.0);
}
#else
uniform sampler2D data_tex : filter_nearest;
uniform int rows_per_block = 1;
uniform int tex_width = 1024;
uniform int layer_pass = 1;         // 0 = corpses only, 1 = living only
// xmin, xmax, ymin, ymax in metres per sprite (see soldier_layer.gd).
uniform vec4 spr_rect[11];

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
void place(vec2 cur, vec2 prv, float facing, int st, int spr, vec4 r, int side, bool sel, bool fire,
		inout vec2 uv, out vec2 pos, out vec4 col) {
	bool engine = st >= 6;
	bool dead = st == 4 || st == 7;
	vec2 p = mix(prv, cur, alpha) * px_per_unit;
	float ang = facing * (6.2831853 / 1024.0);
	vec3 base = side == 0 ? color_side0 : color_side1;
	vec2 lp = vec2(mix(r.x, r.y, uv.x), mix(r.z, r.w, uv.y));
	uv = vec2((float(spr) + (lp.x - CELL_X0) / CELL_W) / float(SPRITES),
		(lp.y - CELL_Y0) / CELL_H);
	vec2 v = lp * (px_per_unit * 1024.0);
	if (engine) {
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
		col = vec4(mix(base, vec3(0.22, 0.16, 0.12), 0.75), 0.75);
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

void vertex() {
#ifdef CPU_FED
	int st = int(MODEL_MATRIX[1].y + 0.5);
	bool want_dead = layer_pass < 0.5;
#else
	int i = slot_index(INSTANCE_CUSTOM);
	int st = fetch_int(5, i);
	bool want_dead = layer_pass == 0;
#endif
	// 0 formed, 1 fighting, 2 routing, 3 knocked down, 4 dead, 5 off field;
	// engines: 6 working, 7 out of action
	bool dead = st == 4 || st == 7;
	if (st == 5 || dead != want_dead) {
		VERTEX = vec2(-100000.0);
		v_color = vec4(0.0);
	} else {
		vec2 pos;
		vec4 col;
		vec2 uv = UV;
#ifdef CPU_FED
		int spr = clamp(int(INSTANCE_CUSTOM.x + 0.5), 0, SPRITES - 1);
		float fl = floor(INSTANCE_CUSTOM.y + 0.5);  // side + 2 selected + 4 under fire
		int side = int(mod(fl, 2.0));
		bool sel = mod(floor(fl / 2.0), 2.0) > 0.5;
		bool fire = fl >= 4.0;
		place(MODEL_MATRIX[3].xy, MODEL_MATRIX[0].xy, MODEL_MATRIX[1].x, st, spr, sprite_rect(spr),
			side, sel, fire, uv, pos, col);
		// skip_vertex_transform: pos is already in the layer's (= canvas) space.
		VERTEX = pos;
#else
		vec2 cur = vec2(float(fetch_int(0, i)), float(fetch_int(1, i)));
		vec2 prv = vec2(float(fetch_int(2, i)), float(fetch_int(3, i)));
		int flags = fetch_int(7, fetch_int(6, i));
		int spr = clamp(st >= 6 ? bitfield(flags, 256, 16) : bitfield(flags, 16, 16), 0, SPRITES - 1);
		place(cur, prv, float(fetch_int(4, i)), st, spr, spr_rect[spr], bitfield(flags, 1, 2),
			bitfield(flags, 2, 2) != 0, bitfield(flags, 4, 2) != 0, uv, pos, col);
		// Instance transforms are identity; cancel whatever origin this
		// instance has (the engine applies MODEL_MATRIX after this).
		VERTEX = pos - MODEL_MATRIX[3].xy;
#endif
		UV = uv;
		v_color = col;
	}
}

void fragment() {
	COLOR = texture(TEXTURE, UV) * v_color;
}
