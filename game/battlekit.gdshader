shader_type canvas_item;
// Battle kit pieces (game/battlekit.gd): one MultiMesh, every instance a quad carrying a piece of
// the atlas (walls, towers, gates). The albedo atlas holds the unlit colour (masked parts grey),
// the normal atlas R,G = normal x,y in the piece's frame (y up = the piece's outer side), B =
// height, A = mask class (1 none, 0.7 roof, 0.4 plaster, 0.1 accent). Lit here: the north-west
// key light with the piece's normal turned by the instance's angle, so every wall reads lit from
// the same side; the culture palette tints stone and fills the masked parts.
// Instance custom data: x = piece index, y = rotation (rad), z = culture, w = flash (0..1).
// The oblique view (tabletop pass 3, game/battlekit.gd "the oblique view"): a piece stands upright at its ground point
// (the oblique kit sheet's sprite, assets/battlekit_ob through game/kit_ob.gd: piece code 100 + its index, the row's origin
// the footprint's centre, its x scale the piece's; drawn from its own albedo and world-normal passes and lit here as the
// top-down kit is; else the top-down piece stood up with its lower edge there);
// the wall rows (game/battlekit.gd _ob_walls: custom.x = 400 + kind + 8 x height dm (above the kit sheet's 100 + 288); the custom data is kept in half
// floats, so only small numbers go there) carry world px in the transform: a face its ground edge A, B (MODEL_MATRIX
// columns 0, 1) and its top (column 3's y, metres; its foot the packed height), a top its two lines A, B and A2
// (column 3), B2 (B + custom.yz), at the packed height; custom.w the stretch's fade (faded: 55 % alpha). Placed on the board and
// shaded here: dressed stone in courses (a palisade: stakes), each face lit by its own direction against the key
// light, a darker foot, a lit lip, merlons on the outer edge (gaps discarded), the walk darker than the faces.
// `ob_depth`: the occluder pass (game/kit_occluder.gd) writes each opaque pixel's nearness (16 bits in R, G) and the
// fade (B) instead of the colour.
render_mode skip_vertex_transform;
#include "res://game/board_view.gdshaderinc"
uniform float ob_depth = 0.0;
uniform vec2 ob_near_r = vec2(0.0, 1.0);
uniform float ob_ppm = 10.0;
uniform float ob_timber = 0.0;
uniform float ob_wall_cul = 0.0;   // the walls' culture (the kit's)
uniform float ob_kit = 0.0;
uniform sampler2D ob_kalb : filter_linear, repeat_disable;
uniform sampler2D ob_knrm : filter_linear, repeat_disable;
uniform vec4 ob_krect[288];
uniform vec4 ob_kanch[288];   // size px, anchor px (the footprint's centre on the ground)
uniform float ob_kk = 1.25;   // board px per sheet px

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
varying vec4 v_wall;    // x: 0 a piece, 3 an oblique-kit piece, 10 + kind a wall row; y: metres along; z: metres up (a
                        // face) or 0..1 across (a top); w: the face's top, or the top's height, m

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	int pi = int(cd.x + 0.5);
	vec2 w = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	v_wall = vec4(0.0);
	v_near = 0.0;
	vec4 r = rects[clamp(pi, 0, 63)];
	if (ob_on > 0.5 && pi >= 400 && pi < 2048) {
		// A wall row (world px): a face or a top, placed on the board here.
		float c = floor(cd.x + 0.5) - 400.0;
		float zdm = floor(c / 8.0 + 0.001);
		float kind = c - zdm * 8.0;
		vec2 A = MODEL_MATRIX[0].xy;
		vec2 B = MODEL_MATRIX[1].xy;
		vec2 C = MODEL_MATRIX[3].xy;
		vec2 d = (B - A) / max(length(B - A), 0.0001);
		vec2 g;
		float z;
		if (kind < 4.5) {
			g = mix(A, B, UV.x);
			z = mix(C.y, zdm * 0.1, UV.y);
			v_wall = vec4(10.0 + kind, dot(g, d) / ob_ppm, z, C.y);
			rot_cs = vec2(d.y, -d.x);   // the face's normal on the ground
		} else {
			g = mix(mix(A, B, UV.x), mix(C, B + cd.yz, UV.x), UV.y);
			z = zdm * 0.1;
			v_wall = vec4(10.0 + kind, dot(g, d) / ob_ppm, UV.y, z);
			rot_cs = vec2(0.0);
		}
		VERTEX = ob_board(g) - vec2(0.0, z * ob_ppm * OB_SIN);
		v_near = ob_near(g, z * ob_ppm);
		culture = ob_wall_cul;
		flash = clamp(cd.w, 0.0, 1.0);   // (a wall row: its fade)
		UV = vec2(0.0);
	} else {
		if (ob_on > 0.5) {
			vec2 o = MODEL_MATRIX[3].xy;
			if (ob_kit > 0.5 && pi >= 100) {
				// The oblique kit: the sprite at the footprint's centre, scaled by the row's x scale.
				int q = clamp(pi - 100, 0, 287);
				vec4 ka = ob_kanch[q];
				float sc = MODEL_MATRIX[0].x * ob_kk;
				w = ob_board(o) + (UV * ka.xy - ka.zw) * sc;
				r = ob_krect[q];
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
		rot_cs = v_wall.x > 2.5 ? vec2(1.0, 0.0) : vec2(cos(cd.y), sin(cd.y));   // (the sheet's normals are the world's)
		culture = cd.z;
		flash = cd.w;
	}
}

float ob_hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// The kit's nearness for the occluder pass (16 bits in R, G; B a wall's fade).
vec4 ob_near_col(float a, float fade) {
	float n = clamp((v_near - ob_near_r.x) / ob_near_r.y, 0.0, 1.0) * 65535.0;
	float hi = floor(n / 256.0);
	return vec4(hi / 255.0, (n - hi * 256.0) / 255.0, fade, a);
}

// The wall rows: dressed stone in courses (a palisade: stakes and an earth bank), each face lit by its direction
// against the key light (from the north-west: a face toward the camera is in half shade), a darker foot, a lit lip;
// the merlons on the outer edge (gaps cut out), the walk darker than the faces and the inner rampart darker still, so
// the wall reads thick but walkable. Returns alpha 0 for a cut-out pixel.
const float MERLON_STEP = 2.0;   // tools/battlekit b_wall_strip: 8 merlons a 16 m tile, 1.1 m wide
const float MERLON_W = 1.1;
vec4 ob_wall_col() {
	int kind = int(v_wall.x - 10.0 + 0.5);
	int ci = clamp(int(culture + 0.5), 0, 7);
	vec3 stone = vec3(0.66, 0.62, 0.55) * stone_tint[ci];
	float u = v_wall.y;
	bool timber = ob_timber > 0.5;
	// A merlon (stone) or a stake (timber) at u: symmetric about the step's middle, so a face drawn either way agrees.
	float mph = fract(u / MERLON_STEP);
	bool merlon = abs(mph - 0.5) < MERLON_W / MERLON_STEP * 0.5;
	float sx = fract(u / 0.46);
	float stake = floor(u / 0.46);
	vec3 wood = vec3(0.47, 0.35, 0.23);
	vec3 earth = vec3(0.42, 0.34, 0.23);
	vec3 col;
	if (kind <= 4) {
		float z = v_wall.z;
		float z1 = v_wall.w;
		// The merlon band of the outer face and the merlons' inner faces.
		bool band = (kind == 0 && z > z1 - (timber ? 0.8 : 1.2)) || kind == 1;
		if (band) {
			if (timber) {
				if (z > z1 - 0.8 * abs(sx - 0.5) * 2.0) {
					return vec4(0.0);
				}
			} else if (!merlon) {
				return vec4(0.0);
			}
		}
		vec2 L = normalize(light_dir.xy);
		float hl = 0.5 + 0.5 * dot(rot_cs, L);
		float lf = 0.80 + 0.36 * hl;
		if (timber && (kind <= 1)) {
			col = wood * (0.66 + 0.14 * ob_hash(vec2(stake, 3.0))) * (0.78 + 0.32 * smoothstep(0.0, 0.22, min(sx, 1.0 - sx)));
		} else if (timber) {
			col = earth * (0.85 + 0.1 * ob_hash(floor(vec2(u / 0.7, z * 3.0))));
		} else {
			float course = floor(z / 0.55);
			float gy = fract(z / 0.55);
			float jx = fract(u / 1.1 + course * 0.37);
			float mortar = max(1.0 - smoothstep(0.0, 0.09, gy), 1.0 - smoothstep(0.0, 0.05, min(jx, 1.0 - jx)));
			col = stone * (0.9 + 0.12 * ob_hash(vec2(course, floor(u / 1.1 + course * 0.37))));
			col *= 1.0 - 0.2 * mortar;
			if (kind == 3 || kind == 2) {
				col *= 0.88;   // the inner rampart and the walk's step
			}
		}
		col *= lf;
		// A darker foot (the ground's damp and the shade), a lit lip along the top of the solid part.
		col *= 0.74 + 0.26 * smoothstep(0.0, 1.3, z);
		float lip = (kind == 0 && !timber && !merlon) ? z1 - 1.2 : z1;
		col = mix(col, col * 1.22 + vec3(0.03), smoothstep(lip - 0.22, lip - 0.06, z) * step(z, lip + 0.001));
	} else {
		float ac = v_wall.z;   // 0 the line nearer the outer edge .. 1 the inner
		if (kind == 6) {
			// The merlons' tops.
			if (!merlon) {
				return vec4(0.0);
			}
			col = stone * 1.12;
		} else if (kind == 5) {
			if (timber) {
				col = wood * 0.78 * (0.85 + 0.15 * step(0.12, fract(u / 0.35)));
			} else {
				// The walk: worn flags, darker than the faces; a lit lip on its inner edge (the step down).
				float fl = ob_hash(floor(vec2(u / 1.3, ac * 4.0)));
				col = stone * 0.68 * (0.9 + 0.12 * fl);
				col *= 1.0 - 0.18 * (1.0 - smoothstep(0.0, 0.05, min(fract(u / 1.3), fract(ac * 4.0))));
			}
			col = mix(col, col * 1.3, smoothstep(0.9, 0.97, ac));
		} else {
			// The inner rampart's top: earth and stone, darker still.
			col = (timber ? earth * 0.9 : mix(stone, earth, 0.45) * 0.62) * (0.92 + 0.08 * ob_hash(floor(vec2(u / 1.7, ac * 3.0))));
			col = mix(col, col * 1.2, smoothstep(0.88, 0.97, ac));
		}
	}
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(vec3(lum), col, sat);
	col = (col - 0.5) * contrast + 0.5;
	return vec4(clamp(col, 0.0, 1.0), 1.0);
}

void fragment() {
	if (v_wall.x > 9.5) {
		vec4 wc = ob_wall_col();
		if (wc.a < 0.5) {
			discard;
		}
		// (flash: the stretch's fade)
		COLOR = ob_depth > 0.5 ? ob_near_col(1.0, flash) : vec4(wc.rgb, 1.0 - 0.45 * flash);
	} else {
	// The top-down atlases, or the oblique kit sheet's passes (the same channels).
	vec4 a;
	vec4 n;
	float hn;
	if (v_wall.x > 2.5) {
		a = texture(ob_kalb, UV);
		n = texture(ob_knrm, UV);
		vec2 tx = 1.5 / vec2(textureSize(ob_knrm, 0));
		hn = (texture(ob_knrm, UV + vec2(tx.x, 0.0)).b + texture(ob_knrm, UV - vec2(tx.x, 0.0)).b
			+ texture(ob_knrm, UV + vec2(0.0, tx.y)).b + texture(ob_knrm, UV - vec2(0.0, tx.y)).b) * 0.25;
	} else {
		a = texture(albedo_tex, UV);
		n = texture(nrm_tex, UV);
		vec2 tx = 1.5 / vec2(textureSize(nrm_tex, 0));
		hn = (texture(nrm_tex, UV + vec2(tx.x, 0.0)).b + texture(nrm_tex, UV - vec2(tx.x, 0.0)).b
			+ texture(nrm_tex, UV + vec2(0.0, tx.y)).b + texture(nrm_tex, UV - vec2(0.0, tx.y)).b) * 0.25;
	}
	if (a.a < 0.01) {
		discard;
	}
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
		COLOR = ob_near_col(1.0, 0.0);
	}
	}
}
