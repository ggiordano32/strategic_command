// Missiles in flight, one MultiMesh instance per projectile slot of the sim:
// the body shared by projectiles.gdshader (data texture, the default) and
// projectiles_cpu.gdshader (CPU-fed, the compatible fallback; see
// soldiers.gdshaderinc). The sim stores only the firing point and tick and
// the landing point and tick; this shader interpolates between them (no
// per-frame flight physics anywhere). Arcing missiles swell toward
// mid-flight to suggest height. Bolts are long and flat; stones are big
// round shapes that swell a lot (lobbed high). Stone impact marks are drawn
// by overlay.gd.
//
// Texture variant, blocks (each `rows_per_block` rows of `tex_width` texels):
//   0 sx, 1 sy, 2 x, 3 y, 4 t0, 5 t1 (-1 = free slot), 6 shooter unit,
//   7 unit flags (indexed by unit: bit0 side, bits 1-2 kind: 0 arrow,
//     1 javelin, 2 bolt, 3 stone)
// CPU-fed variant (skip_vertex_transform), through MODEL_MATRIX: [3].xy
// firing point, [0].xy landing point, [1].x t0, [1].y t1; INSTANCE_CUSTOM.x
// the shooter's flags (side + 2 x kind).

uniform float now = 0.0;            // sim tick of the frame being drawn
uniform float px_per_unit = 0.01;

varying vec4 v_color;
varying vec2 v_uv;
varying float v_kind;

#ifndef CPU_FED
uniform sampler2D data_tex : filter_nearest;
uniform int rows_per_block = 1;
uniform int tex_width = 1024;

// Portability (mobile WebGL drivers), as in soldiers.gdshaderinc.
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
#endif

// One missile in flight from s to e (sim units) at fraction f; side 0 / 1,
// kind 0 arrow, 1 javelin, 2 bolt, 3 stone. Returns the corner's position
// in the layer's space; col: its colour.
vec2 place(vec2 s, vec2 e, float f, int side, int kind, vec2 uv, out vec4 col) {
	vec2 p = mix(s, e, f) * px_per_unit;
	vec2 d = e - s;
	float ang = atan(d.y, d.x);
	float m = px_per_unit * 1024.0;
	// Arrow 0.9 m, javelin 1.6 m, bolt 2 m; width a fixed fraction.
	// Stone 0.9 m across, swelling to ~3x at the top of its arc.
	vec2 size = vec2(0.9, 0.12);
	float lift = 0.8;
	if (kind == 1) {
		size = vec2(1.6, 0.16);
		lift = 0.25;
	} else if (kind == 2) {
		size = vec2(2.0, 0.24);
		lift = 0.12;
	} else if (kind == 3) {
		size = vec2(0.9, 0.9);
		lift = 2.2;
	}
	size *= 1.0 + lift * sin(3.14159 * f);
	vec2 v = (uv - vec2(0.5)) * size * m;
	float cs = cos(ang);
	float sn = sin(ang);
	vec3 tint = side == 0 ? vec3(0.75, 0.85, 1.0) : vec3(1.0, 0.82, 0.75);
	if (kind == 2) {
		tint = mix(tint, vec3(0.35, 0.25, 0.15), 0.55);
	} else if (kind == 3) {
		tint = mix(tint, vec3(0.45, 0.43, 0.4), 0.8);
	}
	col = vec4(tint, 0.95);
	return vec2(v.x * cs - v.y * sn, v.x * sn + v.y * cs) + p;
}

void vertex() {
#ifdef CPU_FED
	float t0 = MODEL_MATRIX[1].x;
	float t1 = MODEL_MATRIX[1].y;
#else
	int i = slot_index(INSTANCE_CUSTOM);
	float t0 = float(fetch_int(4, i));
	float t1 = float(fetch_int(5, i));
#endif
	v_uv = UV;
	v_kind = 0.0;
	if (t1 < 0.0 || now < t0 || now > t1 || t1 <= t0) {
		VERTEX = vec2(-100000.0);
		v_color = vec4(0.0);
	} else {
		float f = (now - t0) / (t1 - t0);
		vec4 col;
		int kind;
#ifdef CPU_FED
		float fl = floor(INSTANCE_CUSTOM.x + 0.5);  // side + 2 x kind
		kind = int(floor(fl / 2.0));
		VERTEX = place(MODEL_MATRIX[3].xy, MODEL_MATRIX[0].xy, f, int(mod(fl, 2.0)), kind, UV, col);
#else
		vec2 s = vec2(float(fetch_int(0, i)), float(fetch_int(1, i)));
		vec2 e = vec2(float(fetch_int(2, i)), float(fetch_int(3, i)));
		int flags = fetch_int(7, fetch_int(6, i));
		int side = flags - (flags / 2) * 2;
		kind = flags / 2 - (flags / 8) * 4;
		VERTEX = place(s, e, f, side, kind, UV, col) - MODEL_MATRIX[3].xy;
#endif
		v_kind = float(kind);
		v_color = col;
	}
}

void fragment() {
	if (v_kind > 2.5) {
		// Stone: a shaded ball with a dark rim.
		vec2 q = (v_uv - vec2(0.5)) * 2.0;
		float r = length(q);
		float a = 1.0 - smoothstep(0.85, 1.0, r);
		vec3 c = v_color.rgb * (1.1 - 0.5 * clamp(dot(q, vec2(0.6, 0.6)), 0.0, 1.0));
		if (r > 0.75) {
			c *= 0.45;
		}
		COLOR = vec4(c, v_color.a * a);
	} else {
		// A shaft with a darker head at the front.
		float across = abs(v_uv.y - 0.5) * 2.0;
		float a = 1.0 - smoothstep(0.35, 1.0, across);
		vec3 c = v_color.rgb;
		if (v_uv.x > 0.82) {
			c *= 0.35;
		}
		COLOR = vec4(c, v_color.a * a);
	}
}
