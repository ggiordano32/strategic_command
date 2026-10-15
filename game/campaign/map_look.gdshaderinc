// The shared "map look" of the map-table style: the terrain (table_land.gdshader), the town pieces and ships
// (minis.gdshader) and the landscape trees and rocks (landtrees.gdshader) all include this, so a roof, a wall, a
// palm and a hillside are graded, lit in the same bands and printed with the same grain. map_look.gd makes the
// textures and sets the uniforms (the same two textures in every material). View only.
const vec3 MAP_LIGHT = vec3(-0.55, -0.55, 0.63);   // the light: north-west (the cast shadows fall south-east)
const vec3 MAP_INK = vec3(0.28, 0.19, 0.10);       // the ink of the coast and contour lines
const float MAP_BANDS = 4.0;                       // posterised light levels

uniform sampler2D look_lut : filter_linear, repeat_disable;     // gradient map: tint by lightness (1.0 = no change)
uniform sampler2D look_grain : filter_linear, repeat_enable;    // tiling paper / print grain
uniform float look_bands = 1.0;       // 0 on Graphics Low
uniform float look_grain_on = 1.0;    // 0 on Graphics Low
uniform float look_sat = 1.16;        // saturation: the palette may go high
uniform float look_grain_px = 128.0;  // the grain texture's size in screen px

float map_luma(vec3 c) {
	return dot(c, vec3(0.30, 0.59, 0.11));
}

// Snap the light level of a lit colour to the terrain's bands (hue and chroma kept).
vec3 map_bands(vec3 c, float amt) {
	float l = map_luma(c);
	float lq = max(floor(clamp(l, 0.0, 1.0) * MAP_BANDS + 0.5) / MAP_BANDS, 0.2);
	return mix(c, c * (lq / max(l, 0.04)), amt * look_bands);
}

// The shared colour grade: the gradient map tints by lightness, then saturation.
vec3 map_grade(vec3 c) {
	float l = map_luma(c);
	vec3 tone = texture(look_lut, vec2(clamp(l, 0.0, 1.0), 0.5)).rgb * 2.0;
	vec3 g = c * tone;
	float l2 = map_luma(g);
	return clamp(mix(vec3(l2), g, look_sat), 0.0, 1.0);
}

// The shared paper grain, multiplied on in screen space.
vec3 map_grain(vec3 c, vec2 screen_uv, vec2 pixel_size) {
	float n = texture(look_grain, screen_uv / (pixel_size * look_grain_px)).r;
	return c * (1.0 + (n - 0.5) * 0.16 * look_grain_on);
}
