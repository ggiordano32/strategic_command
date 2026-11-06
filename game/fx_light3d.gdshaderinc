// The muzzle flashes' light for the 3D view's unshaded sprites (the men, the smoke: a real OmniLight3D does not reach an unshaded
// shader; game/fx3d.gd sets these each frame from its pooled lights, at most 8). flash_pts: xyz the light's place in metres, w its
// strength; the warm light falls off to nothing at FLASH_R metres.
uniform vec4 flash_pts[8];
uniform int flash_n = 0;
const float FLASH_R = 8.0;

vec3 fx_flash_light(vec3 wp) {
	vec3 acc = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		if (i >= flash_n) {
			break;
		}
		vec3 d = wp - flash_pts[i].xyz;
		float q = clamp(1.0 - dot(d, d) / (FLASH_R * FLASH_R), 0.0, 1.0);
		acc += flash_pts[i].w * q * q;
	}
	return acc * vec3(1.0, 0.62, 0.30);
}
