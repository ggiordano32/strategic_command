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
#include "res://game/weather.gdshaderinc"
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
uniform vec4 ob_rockq[2];     // pass 6: the oblique kit sheet's rock sprites (indices, -1 unused): sunk into the ground
uniform float ob_sink = 0.14; // how far the rock sits below its footprint, a share of its height
const float TREAD_RISE = 0.3; // a stone stair's step, about (game/city_draw.gd TREAD_RISE; ob_stair_col)

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
varying float v_gate;   // a gate piece's or a square tower's row: 1 its stone (the wall's), 2 a door's planks / the passage floor
varying float v_near;   // the oblique view: nearness (world px)
varying float v_rock;   // a rock sprite: 0 its top .. 1 its foot (the foot fades into the ground); else 2
varying vec4 v_wall;    // x: 0 a piece, 3 an oblique-kit piece, 10 + kind a wall row; y: metres along; z: metres up (a
                        // face) or 0..1 across (a top); w: the face's top, or the top's height, m

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	int pi = int(cd.x + 0.5);
	vec2 w = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	v_wall = vec4(0.0);
	v_gate = 0.0;
	v_near = 0.0;
	v_rock = 2.0;
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
		bool tim = ob_timber > 0.5;
		bool stair = cd.w > 1.5 && cd.w < 2.5;   // (a stone stair's row: game/battlekit.gd STAIR_ROW, where a stretch's fade goes)
		bool gate = cd.w > 2.5;   // (a gate piece's row: GATE_ROW / DOOR_ROW + the flash)
		if (kind < 4.5 || (tim && kind > 6.5)) {   // (a stockade's kind 7: a fence, a face)
			g = mix(A, B, UV.x);
			z = mix(C.y, zdm * 0.1, UV.y);
			v_wall = vec4(10.0 + kind, dot(g, d) / ob_ppm, z, C.y);
			if (stair) {
				// A stone stair's side: its top rising from the ground at the foot to C.y at the top end (custom.y +1:
				// toward B), a step's rise above the slope so the stepped edge (ob_stair_col) fits inside.
				float fr = cd.y > 0.0 ? UV.x : 1.0 - UV.x;
				float rise = C.y / max(floor(C.y / TREAD_RISE + 0.5), 1.0);
				z = mix(min(C.y, C.y * fr + rise), 0.0, UV.y);
				v_wall = vec4(30.0 + kind, fr, z, C.y);
			}
			rot_cs = vec2(d.y, -d.x);   // the face's normal on the ground
		} else {
			g = mix(mix(A, B, UV.x), mix(C, B + cd.yz, UV.x), UV.y);
			z = zdm * 0.1;
			v_wall = vec4(10.0 + kind, dot(g, d) / ob_ppm, UV.y, z);
			rot_cs = vec2(0.0);
			if (tim && kind > 5.5) {
				// A stockade's stair: from the ground at the A end up to the platform at B; along it in metres from A.
				z *= UV.x;
				v_wall.y = UV.x * length(B - A) / ob_ppm;
			} else if (stair) {
				// A stone stair's treads: from the ground at the A end up to the landing at B (y: 0 .. 1 along it).
				z *= UV.x;
				v_wall = vec4(30.0 + kind, UV.x, UV.y, zdm * 0.1);
				rot_cs = d;   // (the way it climbs)
			}
		}
		VERTEX = ob_board(g) - vec2(0.0, z * ob_ppm * OB_SIN);
		v_near = ob_near(g, z * ob_ppm);
		culture = ob_wall_cul;
		flash = stair ? 0.0 : clamp(cd.w, 0.0, 1.0);   // (a wall row: its fade)
		if (gate) {
			v_gate = cd.w > 4.5 ? 2.0 : 1.0;
			flash = clamp(cd.w - (cd.w > 4.5 ? 5.0 : 3.0), 0.0, 1.0);   // (a gate: the struck flash)
		}
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
				float fq = float(q);
				if (abs(ob_rockq[0].x - fq) < 0.5 || abs(ob_rockq[0].y - fq) < 0.5 || abs(ob_rockq[0].z - fq) < 0.5
						|| abs(ob_rockq[0].w - fq) < 0.5 || abs(ob_rockq[1].x - fq) < 0.5 || abs(ob_rockq[1].y - fq) < 0.5) {
					v_rock = UV.y;
					w.y += ob_sink * ka.y * sc;
				}
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
// The timber stockade (game/battlekit.gd "the timber stockade"; ob_timber): upright logs with pointed tops, lashed,
// on an earth footing; posts with knee braces under a plank platform; a rail on its inner edge; plank stairs; the
// garden fences. Returns alpha 0 where the ground (or what is behind) shows through.
const float LOG_W = 0.46;
const float POST_STEP = 2.5;
vec4 ob_timber_col() {
	int kind = int(v_wall.x - 10.0 + 0.5);
	float u = v_wall.y;
	vec3 wood = vec3(0.50, 0.37, 0.24);
	vec3 wood_d = vec3(0.34, 0.25, 0.17);
	vec3 plank = vec3(0.62, 0.49, 0.33);
	vec3 earth = vec3(0.45, 0.36, 0.24);
	vec3 col;
	vec2 L = normalize(light_dir.xy);
	if (kind <= 4 || kind == 7) {
		float z = v_wall.z;
		float z1 = v_wall.w;
		float lf = 0.80 + 0.36 * (0.5 + 0.5 * dot(rot_cs, L));
		if (kind <= 1) {
			// The logs (the same on both faces: |u| along the wall), each its own height and shade, a point on top.
			float au = abs(u);
			float sx = fract(au / LOG_W);
			float lg = floor(au / LOG_W);
			float tip = z1 - 0.32 * ob_hash(vec2(lg, 7.0));
			if (z > tip - 0.8 * abs(sx - 0.5) * 2.0) {
				return vec4(0.0);
			}
			float round_k = 0.62 + 0.42 * sin(sx * 3.14159);
			col = wood * (0.72 + 0.26 * ob_hash(vec2(lg, 3.0))) * round_k;
			col *= 0.9 + 0.1 * ob_hash(vec2(lg, floor(z * 2.5)));
			col = mix(col, vec3(0.70, 0.58, 0.40) * round_k, step(tip - 0.8, z) * 0.55);   // the fresh-cut point
			float hm = z1 - 0.8;
			// Lashing (the outer face: rope bands) or the rails behind (the inner face: a pole, lit on top).
			float b1 = step(abs(z - 1.1), 0.08) + step(abs(z - (hm - 0.7)), 0.08);
			if (kind == 0) {
				col = mix(col, vec3(0.66, 0.58, 0.42) * round_k, clamp(b1, 0.0, 1.0) * 0.8);
				col = mix(col, earth * 0.8, 1.0 - smoothstep(0.15, 0.45, z));   // the earth footing
			} else {
				float r1 = step(abs(z - 1.1), 0.11) + step(abs(z - (hm - 0.7)), 0.11);
				col = mix(col, wood_d * 1.15, clamp(r1, 0.0, 1.0));
			}
		} else if (kind == 2) {
			// A post row under the platform: posts every POST_STEP, knee braces up to the joist at the top.
			float pc = abs(fract(u / POST_STEP + 0.5) - 0.5) * POST_STEP;
			float dz = z1 - 0.3 - z;
			bool post = pc < 0.15;
			bool beam = dz < 0.0;
			bool brace = abs(pc - 0.15 - dz) < 0.09 && dz < 1.0 && dz > 0.0;
			if (!post && !beam && !brace) {
				return vec4(0.0);
			}
			col = beam ? wood * 0.92 : (post ? wood_d * (0.75 + 0.4 * (1.0 - pc / 0.15)) : wood_d * 0.95);
			col = mix(col, col * 1.25, beam ? smoothstep(z1 - 0.1, z1 - 0.02, z) : 0.0);
		} else if (kind == 3) {
			// The rail on the platform's inner edge: posts over the ones below, a top rail and a middle one.
			float pc = abs(fract(u / POST_STEP + 0.5) - 0.5) * POST_STEP;
			bool post = pc < 0.09;
			bool top = z > z1 - 0.13;
			bool midr = abs(z - (z1 - 0.55)) < 0.05;
			if (!post && !top && !midr) {
				return vec4(0.0);
			}
			col = wood_d * (top ? 1.25 : 1.0);
		} else if (kind == 7) {
			// A garden fence: weathered posts every 2 m and two rails.
			float pc = abs(fract(u / 2.0 + 0.5) - 0.5) * 2.0;
			float pt = z1 - 0.15 * ob_hash(vec2(floor(u / 2.0 + 0.5), 5.0));
			bool post = pc < 0.08 && z < pt;
			bool rail = abs(z - 0.45) < 0.05 || abs(z - (z1 - 0.3)) < 0.05;
			if (!post && !rail) {
				return vec4(0.0);
			}
			col = vec3(0.50, 0.43, 0.34) * (post ? 0.85 : 1.05);
		} else {
			col = wood_d * 1.05;   // an end
		}
		col *= lf;
		col *= 0.74 + 0.26 * smoothstep(0.0, 1.3, z);
	} else {
		float ac = v_wall.z;
		if (kind == 6) {
			// A stair: stringers either side, treads with their shadowed risers.
			if (ac < 0.12 || ac > 0.88) {
				col = wood_d;
			} else {
				float tr = fract(u / 0.32);
				col = plank * (0.88 + 0.1 * ob_hash(vec2(floor(u / 0.32), 2.0))) * (tr < 0.72 ? 1.0 : 0.62);
			}
		} else {
			// The platform: planks across it (0.3 m), edge beams, a lit lip on the inner edge.
			float au = abs(u);
			float pl = floor(au / 0.3);
			col = plank * (0.80 + 0.16 * ob_hash(vec2(pl, 9.0)));
			col *= 1.0 - 0.3 * (1.0 - smoothstep(0.0, 0.06, min(fract(au / 0.3), 1.0 - fract(au / 0.3))));
			col = mix(col, wood_d, step(ac, 0.05));
			col = mix(col, col * 1.25, smoothstep(0.9, 0.97, ac));
		}
	}
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(vec3(lum), col, sat);
	col = (col - 0.5) * contrast + 0.5;
	return vec4(clamp(col, 0.0, 1.0), 1.0);
}

// A stone wall's stair (game/battlekit.gd _ob_stone_flight, docs/design/art_pipeline.md "Stone stairs"): dressed stone
// in the wall's culture tint. The treads (kind 5): n steps of about TREAD_RISE from the foot to the landing, each its
// riser then its tread, the riser's share of a step as the camera sees it (most when the flight climbs away from it,
// in the light by its own direction; a shadow line when it climbs toward it), a lit nosing, each tread its own wear,
// a coping along both edges. The sides (kind 4): coursed masonry, the top cut into the steps' profile (the rest
// discarded), a lit lip on each step, a darker foot.
vec4 ob_stair_col() {
	int kind = int(v_wall.x - 30.0 + 0.5);
	int ci = clamp(int(culture + 0.5), 0, 7);
	vec3 stone = vec3(0.66, 0.62, 0.55) * stone_tint[ci];
	float hm = v_wall.w;
	float n = max(floor(hm / TREAD_RISE + 0.5), 1.0);
	float rise = hm / n;
	vec2 L = normalize(light_dir.xy);
	vec3 col;
	if (kind == 5) {
		float fs = v_wall.y * n;
		float st = floor(fs);
		float ph = fs - st;
		float ac = v_wall.z;
		float away = clamp(-rot_cs.y, 0.0, 1.0);   // (climbing north: the risers face the camera)
		float rs = mix(0.10, 0.55, away);
		float wear = 0.92 + 0.12 * ob_hash(vec2(st, 4.0));
		if (ph < rs) {
			// The riser: lit by its own direction (it faces back down the flight); a shadow line when it faces away,
			// a faint one seen from the side (strong lines there read as a fence).
			float rl = 0.5 + 0.5 * dot(-rot_cs, L);
			col = stone * wear * (away > 0.3 ? 0.66 + 0.3 * rl : mix(0.82, 0.55, clamp(rot_cs.y * 2.0, 0.0, 1.0)));
		} else {
			col = stone * 1.04 * wear * (1.0 + (0.04 + 0.12 * away) * (1.0 - smoothstep(0.0, 0.14, ph - rs)));   // the nosing lit
			col *= 1.0 - 0.06 * smoothstep(0.25, 0.0, abs(ac - 0.5));   // (worn in the middle)
		}
		col = mix(col, stone * 1.1, step(0.93, ac) + step(ac, 0.07));   // the coping
		col *= 0.88 + 0.12 * v_wall.y;   // (the foot in the street's shade)
	} else {
		float fr = v_wall.y;
		float z = v_wall.z;
		float ztop = min((floor(fr * n) + 1.0) * rise, hm);
		if (z > ztop) {
			return vec4(0.0);
		}
		float u = fr * hm;
		float course = floor(z / 0.55);
		float gy = fract(z / 0.55);
		float jx = fract(u / 1.1 + course * 0.37);
		float mortar = max(1.0 - smoothstep(0.0, 0.09, gy), 1.0 - smoothstep(0.0, 0.05, min(jx, 1.0 - jx)));
		col = stone * 0.94 * (0.9 + 0.12 * ob_hash(vec2(course, floor(u / 1.1 + course * 0.37))));
		col *= 1.0 - 0.2 * mortar;
		col *= 0.80 + 0.36 * (0.5 + 0.5 * dot(rot_cs, L));
		col *= 0.74 + 0.26 * smoothstep(0.0, 1.3, z);
		col = mix(col, col * 1.25 + vec3(0.03), smoothstep(ztop - 0.09, ztop - 0.02, z));
	}
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(vec3(lum), col, sat);
	col = (col - 0.5) * contrast + 0.5;
	return vec4(clamp(col, 0.0, 1.0), 1.0);
}

// A gate's door leaves and passage floor (game/battlekit.gd _ob_gate_door): vertical planks with iron straps (a face, the
// timber ring's the same in its wood), planks across the leaf's top, cobbles (earth in a timber ring) on the floor.
vec4 ob_door_col() {
	int kind = int(v_wall.x - 10.0 + 0.5);
	float u = v_wall.y;
	bool timber = ob_timber > 0.5;
	vec3 wood = timber ? vec3(0.50, 0.37, 0.24) : vec3(0.40, 0.27, 0.15);
	vec3 col;
	if (kind <= 4) {
		float z = v_wall.z;
		float z1 = v_wall.w;
		float pl = floor(abs(u) / 0.28);
		float sx = fract(abs(u) / 0.28);
		col = wood * (0.78 + 0.24 * ob_hash(vec2(pl, 5.0)));
		col *= 1.0 - 0.28 * (1.0 - smoothstep(0.0, 0.1, min(sx, 1.0 - sx)));
		float strap = max(step(abs(z - 0.9), 0.14), step(abs(z - (z1 - 0.9)), 0.14));
		col = mix(col, vec3(0.20, 0.20, 0.22), strap * 0.85);
		vec2 L = normalize(light_dir.xy);
		col *= 0.80 + 0.36 * (0.5 + 0.5 * dot(rot_cs, L));
		col *= 0.74 + 0.26 * smoothstep(0.0, 1.0, z);
	} else if (kind == 5) {
		col = wood * 0.85 * (0.85 + 0.15 * step(0.12, fract(abs(u) / 0.3)));
	} else {
		float ac = v_wall.z;
		vec3 floor_c = timber ? vec3(0.42, 0.33, 0.22) : vec3(0.47, 0.43, 0.37);
		col = floor_c * (0.86 + 0.2 * ob_hash(floor(vec2(u / 0.55, ac * 12.0))));
	}
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(vec3(lum), col, sat);
	col = (col - 0.5) * contrast + 0.5;
	return vec4(clamp(col, 0.0, 1.0), 1.0);
}

const float MERLON_STEP = 2.0;   // tools/battlekit b_wall_strip: 8 merlons a 16 m tile, 1.1 m wide
const float MERLON_W = 1.1;
vec4 ob_wall_col() {
	if (v_wall.x > 29.5) {
		return ob_stair_col();
	}
	if (ob_timber > 0.5) {
		return ob_timber_col();
	}
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
		vec4 wc = v_gate > 1.5 ? ob_door_col() : ob_wall_col();
		if (wc.a < 0.5) {
			discard;
		}
		if (v_gate > 0.5) {
			// A gate piece: never faded; struck, it flashes as the kit's pieces do.
			COLOR = ob_depth > 0.5 ? ob_near_col(1.0, 0.0) : vec4(mix(wc.rgb, vec3(1.0, 0.62, 0.25), flash * 0.45), 1.0);
		} else {
		// (flash: the stretch's fade)
		COLOR = ob_depth > 0.5 ? ob_near_col(1.0, flash) : vec4(wc.rgb, 1.0 - 0.45 * flash);
		}
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
	if (v_rock < 1.5) {
		// A rock sits in the ground: its foot fades out over the flock the ground draws, and darkens a little above it.
		a.a *= 1.0 - smoothstep(0.64, 0.96, v_rock);
		a.rgb *= 1.0 - 0.22 * smoothstep(0.45, 0.85, v_rock);
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
	// (culture + 8: palm thatch, the native lesson's shacks and lean-tos: their light straw turned grey-brown.)
	bool palm = culture > 7.5;
	int ci = clamp(int(culture + 0.5) - (palm ? 8 : 0), 0, 7);
	vec3 col = a.rgb;
	float mc = n.a;
	if (mc > 0.85) {
		if (palm) {
			float al = dot(a.rgb, vec3(0.3, 0.59, 0.11));
			col = mix(col, col * vec3(0.70, 0.76, 0.86), smoothstep(0.43, 0.52, al));
		}
		col *= stone_tint[ci];
	} else {
		vec3 p = mc > 0.55 ? pal_r[ci] : (mc > 0.25 ? pal_g[ci] : pal_b[ci]);
		col *= p / 0.85;
	}
	if (wx_surf.y > 0.001) {
		// Snow on the roofs (the mask class 0.7: the palette's roof) and every surface that shows a top (the sprite's normal looking up: wall walks, tower decks, parapet tops, drums, palisade tops; the weather pass).
		float roof = mc > 0.55 && mc < 0.85 ? 1.0 : 0.0;
		col = wx_snow_on(col, max(roof * (0.55 + 0.45 * smoothstep(0.3, 0.9, nz)), 0.9 * smoothstep(0.78, 0.97, nz + (dot(a.rgb, vec3(0.3, 0.59, 0.11)) - 0.5) * 0.1)));
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
