shader_type canvas_item;
// Battle kit pieces (game/battlekit.gd): one MultiMesh, every instance a quad carrying a piece of
// the atlas (walls, towers, gates). The albedo atlas holds the unlit colour (masked parts grey),
// the normal atlas R,G = normal x,y in the piece's frame (y up = the piece's outer side), B =
// height, A = mask class (1 none, 0.7 roof, 0.4 plaster, 0.1 accent). Lit here: the north-west
// key light with the piece's normal turned by the instance's angle, so every wall reads lit from
// the same side; the culture palette tints stone and fills the masked parts.
// Instance custom data: x = piece index, y = rotation (rad), z = culture, w = flash (0..1).
// The oblique view (tabletop pass 3, game/battlekit.gd "the oblique view"): a piece stands upright at its ground point
// (the oblique kit sheet's frame with its anchor there, else the top-down piece stood up with its lower edge there);
// the wall rows (pieces 62 front face, 63 top) arrive already on the board, custom (piece, nearness at the stretch's
// two ends, culture + 8 x height dm) and are shaded here. `ob_depth`: the occluder pass (game/kit_occluder.gd) writes
// each opaque pixel's nearness (16 bits in R, G) instead of the colour.
render_mode skip_vertex_transform;
#include "res://game/board_view.gdshaderinc"
uniform float ob_depth = 0.0;
uniform vec2 ob_near_r = vec2(0.0, 1.0);
uniform float ob_ppm = 10.0;
uniform float ob_timber = 0.0;
uniform float ob_kit = 0.0;
uniform sampler2D ob_ktex : filter_linear_mipmap, repeat_disable;
uniform vec4 ob_krect[64];
uniform vec4 ob_kanch[64];
uniform float ob_kk = 0.4166667;

uniform sampler2D albedo_tex : filter_linear, repeat_disable;
uniform sampler2D nrm_tex : filter_linear, repeat_disable;
uniform vec4 rects[64];
uniform vec3 stone_tint[8];
uniform vec3 pal_r[8];
uniform vec3 pal_g[8];
uniform vec3 pal_b[8];
uniform vec3 light_dir = vec3(-0.55, -0.50, 0.67);   // screen space (north is -y), towards the light
uniform float amb = 0.66;
uniform float key = 0.55;
// Look parameters, set from game/battle_look.gd: diorama (default) amb 0.50, key 0.88, rim 0.22,
// outline 0.55, sat 1.22, contrast 1.12; painterly the values below (tools/battlekit/mockup.py STYLE).
uniform float rim = 0.05;        // light on convex edges (dry brush)
uniform float outline = 0.24;    // dark line where a piece ends against the ground
uniform float sat = 0.86;
uniform float contrast = 1.04;

varying vec2 rot_cs;
varying float culture;
varying float flash;
varying float v_near;   // the oblique view: nearness (world px)
varying vec4 v_wall;    // x: 0 a piece, 1 a wall face, 2 a wall top, 3 an oblique-kit piece; y, z: metres along, up
                        // (a face) or across (a top); w: the wall's height, m

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	int pi = int(cd.x + 0.5);
	vec2 w = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	v_wall = vec4(0.0);
	v_near = 0.0;
	vec4 r = rects[clamp(pi, 0, 63)];
	if (ob_on > 0.5 && pi >= 62) {
		// A wall row: already on the board.
		float hdm = floor(cd.w / 8.0);
		float hm = hdm * 0.1;
		bool face = pi == 62;
		float len_m = length(MODEL_MATRIX[0].xy) / ob_ppm;
		v_wall = vec4(face ? 1.0 : 2.0, UV.x * len_m, face ? (1.0 - UV.y) * hm : UV.y, hm);
		v_near = mix(cd.y, cd.z, UV.x) + (face ? (1.0 - UV.y) * hm * ob_ppm * OB_COS : 0.0);
		culture = cd.w - hdm * 8.0;
		flash = 0.0;
		rot_cs = vec2(1.0, 0.0);
		VERTEX = w;
		UV = vec2(0.0);
	} else {
		if (ob_on > 0.5) {
			vec2 o = MODEL_MATRIX[3].xy;
			vec4 ka = ob_kanch[clamp(pi, 0, 63)];
			if (ob_kit > 0.5 && ka.x > 0.0) {
				// The oblique kit: the frame at the footprint's centre, scaled by the instance (its row's x scale).
				float sc = MODEL_MATRIX[0].x * ob_kk;
				w = ob_board(o) + (UV * ka.xy - ka.zw) * sc;
				r = ob_krect[clamp(pi, 0, 63)];
				v_wall.x = 3.0;
			} else {
				// The stand-in: the top-down piece stood up, its lower edge at the ground point.
				float hb = 0.5 * (abs(MODEL_MATRIX[0].y) + abs(MODEL_MATRIX[1].y));
				w = ob_board(o) + vec2(w.x - o.x, w.y - o.y - hb);
			}
			v_near = ob_near(o, 0.0);
		}
		VERTEX = w;
		UV = r.xy + UV * r.zw;
		rot_cs = vec2(cos(cd.y), sin(cd.y));
		culture = cd.z;
		flash = cd.w;
	}
}

float ob_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// The kit's nearness for the occluder pass (16 bits in R, G).
vec4 ob_near_col(float a) {
	float n = clamp((v_near - ob_near_r.x) / ob_near_r.y, 0.0, 1.0) * 65535.0;
	float hi = floor(n / 256.0);
	return vec4(hi / 255.0, (n - hi * 256.0) / 255.0, 0.0, a);
}

// The extruded wall: dressed stone in courses (a palisade: stakes), the face in the shade (the key light is from
// the north-west), a darker foot, a lit lip; the top lit, a parapet along its front edge.
vec4 ob_wall_col() {
	int ci = clamp(int(culture + 0.5), 0, 7);
	vec3 stone = vec3(0.66, 0.62, 0.55) * stone_tint[ci];
	vec3 col;
	if (ob_timber > 0.5) {
		vec3 wood = vec3(0.47, 0.35, 0.23);
		if (v_wall.x < 1.5) {
			float sx = fract(v_wall.y / 0.32);
			float st = floor(v_wall.y / 0.32);
			float tip = v_wall.w - 0.35 * abs(sx - 0.5) * 2.0;
			if (v_wall.z > tip) {
				discard;
			}
			col = wood * (0.62 + 0.12 * ob_hash(vec2(st, 3.0))) * (0.8 + 0.4 * smoothstep(0.0, 0.25, min(sx, 1.0 - sx)));
		} else {
			col = wood * 0.95;
		}
	} else if (v_wall.x < 1.5) {
		float course = floor(v_wall.z / 0.55);
		float gy = fract(v_wall.z / 0.55);
		float jx = fract(v_wall.y / 1.1 + course * 0.37);
		float mortar = max(1.0 - smoothstep(0.0, 0.09, gy), 1.0 - smoothstep(0.0, 0.05, min(jx, 1.0 - jx)));
		col = stone * 0.74 * (0.9 + 0.12 * ob_hash(vec2(course, floor(v_wall.y / 1.1 + course * 0.37))));
		col *= 1.0 - 0.22 * mortar;
		col *= 0.78 + 0.22 * smoothstep(0.0, 1.2, v_wall.z);
		col = mix(col, stone * 1.08, smoothstep(v_wall.w - 0.2, v_wall.w - 0.05, v_wall.z));
	} else {
		col = stone * 1.06 * (0.94 + 0.06 * ob_hash(floor(vec2(v_wall.y / 0.9, v_wall.z * 4.0))));
		float merlon = step(0.5, fract(v_wall.y / 1.6));
		col = mix(col, stone * 0.86, smoothstep(0.72, 0.8, v_wall.z) * (0.6 + 0.4 * merlon));
		col *= 1.0 - 0.25 * (1.0 - smoothstep(0.0, 0.08, v_wall.z));
	}
	return vec4(clamp(col, 0.0, 1.0), 1.0);
}

void fragment() {
	if (v_wall.x > 0.5 && v_wall.x < 2.5) {
		COLOR = ob_depth > 0.5 ? ob_near_col(1.0) : ob_wall_col();
	} else if (v_wall.x > 2.5) {
		// The oblique kit piece: its own lighting baked in; the culture tint on the stone.
		vec4 ka = texture(ob_ktex, UV);
		if (ka.a < (ob_depth > 0.5 ? 0.5 : 0.01)) {
			discard;
		}
		int ci = clamp(int(culture + 0.5), 0, 7);
		vec3 col = ka.rgb * stone_tint[ci];
		col = mix(col, vec3(1.0, 0.62, 0.25), flash * 0.45);
		COLOR = ob_depth > 0.5 ? ob_near_col(1.0) : vec4(clamp(col, 0.0, 1.0), ka.a);
	} else {
	vec4 a = texture(albedo_tex, UV);
	if (a.a < 0.01) {
		discard;
	}
	vec4 n = texture(nrm_tex, UV);
	vec2 nxy = n.rg * 2.0 - 1.0;
	float nz = sqrt(max(1.0 - dot(nxy, nxy), 0.0));
	// Piece space (x right, y up = its outer side) to the screen: right -> (c, s), up -> (s, -c).
	vec2 ns = nxy.x * vec2(rot_cs.x, rot_cs.y) + nxy.y * vec2(rot_cs.y, -rot_cs.x);
	vec3 nrm = vec3(ns, nz);
	vec3 L = normalize(light_dir);
	float diff = clamp(dot(nrm, L), 0.0, 1.0);
	float hemi = 0.5 + 0.5 * nz;
	float lf = (amb * (0.7 + 0.3 * hemi) + key * diff) / (amb + key * L.z);
	int ci = clamp(int(culture + 0.5), 0, 7);
	vec3 col = a.rgb;
	float mc = n.a;
	if (mc > 0.85) {
		col *= stone_tint[ci];
	} else {
		vec3 p = mc > 0.55 ? pal_r[ci] : (mc > 0.25 ? pal_g[ci] : pal_b[ci]);
		col *= p / 0.85;
	}
	col *= lf;
	// Rim: pixels higher than their surroundings catch the light; outline on the silhouette.
	float hgt = n.b;
	float hn = (texture(nrm_tex, UV + vec2(1.5, 0.0) / vec2(textureSize(nrm_tex, 0))).b
		+ texture(nrm_tex, UV - vec2(1.5, 0.0) / vec2(textureSize(nrm_tex, 0))).b
		+ texture(nrm_tex, UV + vec2(0.0, 1.5) / vec2(textureSize(nrm_tex, 0))).b
		+ texture(nrm_tex, UV - vec2(0.0, 1.5) / vec2(textureSize(nrm_tex, 0))).b) * 0.25;
	col += rim * clamp((hgt - hn) * 28.0, 0.0, 1.0) * vec3(1.0, 0.95, 0.8);
	col *= 1.0 - outline * (1.0 - smoothstep(0.55, 0.98, a.a));
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(vec3(lum), col, sat);
	col = (col - 0.5) * contrast + 0.5;
	col = mix(col, vec3(1.0, 0.62, 0.25), flash * 0.45);
	COLOR = vec4(clamp(col, 0.0, 1.0), a.a);
	if (ob_depth > 0.5) {
		if (a.a < 0.5) {
			discard;
		}
		COLOR = ob_near_col(1.0);
	}
	}
}
