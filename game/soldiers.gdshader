shader_type canvas_item;
// Draws every soldier as one MultiMesh instance (INSTANCE_ID = soldier index).
// Positions come straight from the sim's int arrays: the view uploads them
// once per tick as raw bytes in an RGBA8 texture (one texel = one int32,
// little endian), and this shader decodes them and interpolates between the
// previous and current tick. No per-soldier GDScript runs in the view.
//
// Texture blocks (each `rows_per_block` rows of `tex_width` texels):
//   0 pos_x, 1 pos_y, 2 prev_x, 3 prev_y, 4 facing, 5 state, 6 unit_of,
//   7 unit flags (indexed by unit: bit0 side, bit1 selected)

uniform sampler2D data_tex : filter_nearest;
uniform int rows_per_block = 1;
uniform int tex_width = 1024;
uniform float alpha = 1.0;          // interpolation 0 = prev tick, 1 = current
uniform float px_per_unit = 0.01;   // view pixels per sim unit
uniform int layer_pass = 1;         // 0 = corpses only, 1 = living only
uniform vec3 color_side0 = vec3(0.35, 0.6, 1.0);
uniform vec3 color_side1 = vec3(1.0, 0.36, 0.28);

varying vec4 v_color;

int fetch_int(int block, int idx) {
	ivec2 p = ivec2(idx % tex_width, block * rows_per_block + idx / tex_width);
	vec4 t = texelFetch(data_tex, p, 0);
	uvec4 b = uvec4(round(t * 255.0));
	uint u = b.r | (b.g << 8u) | (b.b << 16u) | (b.a << 24u);
	return int(u);
}

void vertex() {
	int i = INSTANCE_ID;
	int st = fetch_int(5, i);
	bool dead = st == 3;
	bool want_dead = layer_pass == 0;
	if (dead != want_dead) {
		VERTEX = vec2(-100000.0);
		v_color = vec4(0.0);
	} else {
		vec2 cur = vec2(float(fetch_int(0, i)), float(fetch_int(1, i)));
		vec2 prv = vec2(float(fetch_int(2, i)), float(fetch_int(3, i)));
		vec2 p = mix(prv, cur, alpha) * px_per_unit;
		float ang = float(fetch_int(4, i)) * (6.2831853 / 1024.0);
		int flags = fetch_int(7, fetch_int(6, i));
		vec3 base = (flags & 1) == 0 ? color_side0 : color_side1;
		vec2 v = VERTEX;
		if (dead) {
			v *= vec2(0.8, 0.55);
			v_color = vec4(mix(base, vec3(0.22, 0.16, 0.12), 0.75), 0.75);
		} else {
			vec3 c = base;
			if (st == 1) {
				c = mix(c, vec3(1.0), 0.15);  // fighting
			} else if (st == 2) {
				c = mix(c, vec3(1.0, 0.95, 0.5), 0.55);  // routing
			}
			if ((flags & 2) != 0) {
				c = mix(c, vec3(1.0), 0.45);  // selected unit
			}
			v_color = vec4(c, 1.0);
		}
		float cs = cos(ang);
		float sn = sin(ang);
		// Instance transforms are identity except two corner markers used
		// only for culling bounds; cancel whatever origin this instance has.
		VERTEX = vec2(v.x * cs - v.y * sn, v.x * sn + v.y * cs) + p - MODEL_MATRIX[3].xy;
	}
}

void fragment() {
	COLOR = texture(TEXTURE, UV) * v_color;
}
