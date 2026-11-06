shader_type spatial;
// The 3D view's rain and snow (game/weather3d.gd): one MultiMesh of camera-facing quads, no per-drop data: every drop is its
// instance index hashed, falling with `t`, wrapped into a box that follows the camera's target (so the layer is always in view and
// the drops stand still in the world when the camera pans). The quad is cut from the camera's axes (the camera is orthographic),
// a streak along the fall's projection for rain, a soft round flake for snow. Depth-tested (a drop behind a house is hidden), no
// depth write, fogged with the rest of the scene.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, world_vertex_coords;

uniform vec3 centre = vec3(0.0);     // the ground point under the screen's centre (metres)
uniform vec3 box = vec3(120.0, 70.0, 120.0);   // x, height, z of the volume (metres)
uniform float y0 = 0.0;              // the volume's floor
uniform float t = 0.0;
uniform float fall = 40.0;           // m/s
uniform vec2 wind = vec2(5.0, 0.0);  // m/s on the ground (x, z)
uniform float size = 1.0;            // metres of a streak's half length (rain) or a flake's radius (snow)
uniform float snow = 0.0;
uniform float count = 1000.0;        // instances drawn (the rest collapsed)
uniform vec3 cam_r = vec3(1.0, 0.0, 0.0);
uniform vec3 cam_u = vec3(0.0, 1.0, 0.0);
uniform vec4 col : source_color = vec4(0.85, 0.9, 1.0, 0.5);

varying float v_a;

float h11(float n) { return fract(sin(n * 12.9898 + 4.1) * 43758.5453); }

void vertex() {
	float id = float(INSTANCE_ID);
	if (id >= count) {
		VERTEX = vec3(0.0, -9999.0, 0.0);
		v_a = 0.0;
	} else {
		vec3 b = vec3(h11(id), h11(id + 0.37), h11(id + 0.71));
		float sp = snow > 0.5 ? (0.7 + 0.6 * b.x) : (0.85 + 0.3 * b.x);
		vec3 vel = vec3(wind.x, -fall * sp, wind.y);
		float k = snow > 0.5 ? 1.0 : 1.0;
		vec3 w = vec3(b.x * box.x, b.y * box.y, b.z * box.z);
		w.xz += vel.xz * t;
		w.y -= fall * sp * t;
		if (snow > 0.5) {
			w.x += sin(t * (0.8 + b.z) + id) * 1.2;
			w.z += cos(t * (0.7 + b.y) + id * 1.7) * 1.2;
		}
		vec3 p;
		p.xz = centre.xz + mod(w.xz - centre.xz + box.xz * 0.5, box.xz) - box.xz * 0.5;
		p.y = y0 + mod(w.y, box.y);
		// The quad: UV (0..1); a streak is long along the fall's screen direction.
		vec2 c = UV * 2.0 - 1.0;
		vec2 vs = vec2(dot(vel, cam_r), dot(vel, cam_u));
		vec2 dir = normalize(vs + vec2(0.0001));
		vec2 perp = vec2(-dir.y, dir.x);
		float sz = size * (0.8 + 0.4 * b.y);
		vec2 o;
		if (snow > 0.5) {
			o = c * sz;
		} else {
			o = dir * c.y * sz * 3.2 + perp * c.x * sz * 0.09;
		}
		VERTEX = p + cam_r * o.x + cam_u * o.y;
		// (the screen-space fade of drops in the volume's edge: none at the floor, a little at the top)
		v_a = smoothstep(0.0, 4.0, p.y - y0) * (0.55 + 0.45 * b.z);
	}
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float a;
	if (snow > 0.5) {
		a = 1.0 - smoothstep(0.35, 1.0, length(c));
	} else {
		// UV.y 1 = the head (lower end), a tail fading up
		float tail = smoothstep(-1.0, 1.0, c.y);
		a = (1.0 - smoothstep(0.2, 1.0, abs(c.x))) * tail * (1.0 - smoothstep(0.92, 1.0, c.y));
	}
	ALBEDO = col.rgb;
	ALPHA = a * col.a * v_a;
}
