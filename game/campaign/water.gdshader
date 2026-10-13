shader_type canvas_item;
// The sea of the campaign map (third pass, 2026-10-13). Pass 2 kept a narrow calm
// shallow band hugging the coast (tools/geo_fit.py COAST field) falling to the
// open-sea colour and two sharp 1 px offshore contour lines (fwidth), with a faint
// advected current texture. Now, on "high":
//  - waves: three directional trains from the map's wind (uniforms train0..2 and
//    wind_dir, the rows of sea_waves.gd, which holds the same height / normal on
//    the CPU for ships), lit as a normal map from the north-west with a very small
//    glint; damped near the coast and in sheltered water;
//  - surf foam: broken, noisy breaker lines that advance and fade in the surf zone
//    (a few km wide) only on coasts the wind and the sea reach (EXPOSURE baked by
//    tools/geo_fit.py, red channel of `shore`), stronger on steep shores (SHORE,
//    green); a few whitecaps on crests only in strongly exposed open sea.
// The coast line itself is drawn by map_view over the land edge. View only; the
// clock is `wave_t` (map_view advances it, SeaWaves.t on the CPU).
// hi = 0 (settings.cfg [map] water = low): depth tint and contour lines only, static.

uniform sampler2D coast : filter_linear, repeat_disable;  // 128 + signed km, sea positive
uniform sampler2D shore : filter_linear, repeat_disable;  // R exposure 0..1, G shore steepness
uniform vec2 field_px = vec2(2760.0, 1400.0);              // map pixels the field covers
uniform float hi = 1.0;
uniform float wave_t = 0.0;
uniform vec2 wind_dir = vec2(0.7071, 0.7071);              // direction the wind blows towards
uniform float wind_strength = 1.0;
uniform vec4 train0 = vec4(0.0, 46.0, 6.0, 1.0);           // heading deg, wavelength px, speed px/s, amplitude
uniform vec4 train1 = vec4(55.0, 88.0, 4.5, 0.55);
uniform vec4 train2 = vec4(-30.0, 27.0, 5.0, 0.35);
uniform vec2 gyre_c = vec2(1190.0, 800.0);                 // western Mediterranean (map px)
uniform float gyre_r = 420.0;
uniform vec3 c_shore = vec3(0.27, 0.46, 0.52);   // at the coast
uniform vec3 c_shal = vec3(0.18, 0.33, 0.42);    // about 6 km
uniform vec3 c_deep = vec3(0.13, 0.25, 0.34);    // 25 km and more
uniform vec3 c_line = vec3(0.62, 0.80, 0.86);    // contour lines
uniform vec3 c_foam = vec3(0.90, 0.95, 0.96);
uniform float wave_gain = 1.0;                   // strength of the lit waves

const float WARP_K = 0.045;
const float WARP_A = 1.4;
const float ENV_K = 0.012;
const float STEEP = 0.22;
const float SLOPE = 2.2;
const float SP = 3.0;                            // breaker spacing, km

varying vec2 wp;

void vertex() {
	wp = VERTEX;
}

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// A sharp 1 px line at distance k (km) from the coast; fades out when the
// lines would crowd (zoomed far out).
float contour(float d, float fw, float k) {
	float l = 1.0 - smoothstep(0.45 * fw, 1.1 * fw, abs(d - k));
	return l * smoothstep(3.0, 7.0, k / max(fw, 0.0001));
}

// One train: adds its height to z and its gradient to xy (sea_waves.gd, line for line).
void train(vec4 tr, float idx, vec2 p, float wpp, inout vec3 hg) {
	float lod = smoothstep(5.0, 11.0, tr.y / wpp);        // gone when under ~6 screen px
	if (lod <= 0.0) {
		return;
	}
	float a = radians(tr.x);
	vec2 d = vec2(wind_dir.x * cos(a) - wind_dir.y * sin(a), wind_dir.x * sin(a) + wind_dir.y * cos(a));
	vec2 dp = vec2(d.y, -d.x);
	float k = 6.2831853 / tr.y;
	float ph = dot(p, d) * k - wave_t * tr.z * k + WARP_A * sin(dot(p, dp) * WARP_K + wave_t * 0.11 + idx * 2.1);
	float env = 0.65 + 0.35 * sin(dot(p, d) * ENV_K * 0.6 + dot(p, dp) * ENV_K + wave_t * 0.05 + idx * 4.0);
	float am = tr.w * env * lod;
	hg.z += am * (sin(ph) - STEEP * cos(2.0 * ph));
	hg.xy += d * (am * k * (cos(ph) + 2.0 * STEEP * sin(2.0 * ph)));
}

void fragment() {
	float t = wave_t;
	vec2 fuv = wp / field_px;
	float inwin = step(0.0, fuv.x) * step(fuv.x, 1.0) * step(0.0, fuv.y) * step(fuv.y, 1.0);
	float d = texture(coast, fuv).r * 255.0 - 128.0;   // km, sea side positive
	d = mix(80.0, d, inwin);                            // outside the window: open sea
	vec3 col = mix(c_shore, c_shal, smoothstep(0.0, 5.0, d));
	col = mix(col, c_deep, smoothstep(5.0, 25.0, d));
	float fw = fwidth(d);
	float foam_zone = 0.0;
	if (hi > 0.5) {
		vec2 sh = texture(shore, fuv).rg;
		float ex = mix(1.0, sh.r, inwin);
		float e = smoothstep(0.2, 0.75, ex);
		float wpp = max(fwidth(wp.x) + fwidth(wp.y), 0.0001) * 0.7;   // map px per screen px
		float open = smoothstep(6.0, 24.0, d);
		// Waves: summed trains, damped near the coast and where the sea is sheltered.
		vec3 hg = vec3(0.0);
		train(train0, 0.0, wp, wpp, hg);
		train(train1, 1.0, wp, wpp, hg);
		train(train2, 2.0, wp, wpp, hg);
		float damp = mix(0.2, 1.0, smoothstep(1.0, 24.0, d)) * mix(0.5, 1.0, e) * wind_strength;
		vec3 nrm = normalize(vec3(-hg.x * damp * SLOPE, -hg.y * damp * SLOPE, 1.0));
		vec3 ldir = normalize(vec3(-0.55, -0.55, 0.62));   // the map's light, north-west
		float lit = dot(nrm, ldir) - ldir.z;
		col += vec3(0.60, 0.80, 0.90) * lit * 0.17 * wave_gain;
		// A very small glint on the lit slopes.
		vec3 hv = normalize(ldir + vec3(0.0, 0.0, 1.0));
		col += vec3(0.8, 0.9, 0.95) * pow(max(dot(nrm, hv), 0.0), 120.0) * 0.10 * wave_gain;
		// The current: a flow field (anticlockwise gyre in the western
		// Mediterranean, a gentle ambient drift elsewhere).
		vec2 rel = wp - gyre_c;
		float rr = length(rel);
		vec2 gyre = vec2(rel.y, -rel.x) / max(rr, 1.0);
		float gw = exp(-rr * rr / (2.0 * gyre_r * gyre_r));
		float ang = 0.4 * sin(wp.x * 0.0031 + 1.0) + 0.5 * cos(wp.y * 0.0047);
		vec2 amb = vec2(cos(ang), sin(ang));
		vec2 fl = normalize(gyre * gw * 1.7 + amb * (1.0 - gw) + vec2(0.0001));
		float cyc = 14.0;
		float p1 = fract(t / cyc);
		float p2 = fract(t / cyc + 0.5);
		float w1 = 0.5 - 0.5 * cos(6.2831853 * p1);
		float c1 = vnoise((wp - fl * p1 * cyc * 7.0) * vec2(0.016, 0.026));
		float c2 = vnoise((wp - fl * p2 * cyc * 7.0) * vec2(0.016, 0.026) + 31.7);
		float cur = mix(c2, c1, w1) - 0.5;
		col += vec3(0.08, 0.11, 0.12) * cur * 0.7 * open;
		// Whitecaps: only high crests of strongly exposed open sea, very sparse.
		float wcs = smoothstep(0.55, 0.9, ex) * open * wind_strength;
		if (wcs > 0.01) {
			float cap = smoothstep(1.3, 1.8, hg.z * damp) * smoothstep(0.76, 0.9, vnoise(wp * 0.30 + vec2(t * 0.05, 0.0)));
			col = mix(col, c_foam, cap * wcs * 0.3);
		}
		// Surf: breaker lines advancing on the shore, broken up, only where exposed.
		float W = mix(2.5, 7.0, e);
		float strength = e * wind_strength * (0.75 + 0.45 * sh.g);
		foam_zone = (1.0 - smoothstep(0.35 * W, W, d)) * step(-0.9, d) * strength;
		if (foam_zone > 0.01) {
			float ph = d / SP + t * 0.30;
			float f = fract(ph);
			float idx = floor(ph);
			float prof = smoothstep(0.0, 0.08, f) * (1.0 - smoothstep(0.10, 0.62, f)) * smoothstep(0.3, 1.6, d + 0.4);
			float n = vnoise(wp * 0.22 + vec2(idx * 13.7, idx * 5.3));
			float gap = smoothstep(0.40, 0.60, n + 0.12 * (e - 0.5));
			// The swash: a ragged wash right at the waterline, coming and going.
			float sw = (1.0 - smoothstep(0.1, 2.2, d + 0.4)) * smoothstep(0.40, 0.70, vnoise(wp * 0.35 + vec2(t * 0.25, -t * 0.2)))
					* (0.55 + 0.45 * sin(t * 1.3 + n * 9.0));
			float lines = prof * gap * 1.1 + sw * 0.7;
			// Zoomed out the lines are under a pixel: their average, a dim ragged edge.
			float lod = 1.0 - smoothstep(0.3 * SP, 0.8 * SP, fw);
			float avg = (1.0 - smoothstep(0.0, 0.7 * W, d + 0.4)) * 0.3 * smoothstep(0.35, 0.65, vnoise(wp * 0.4));
			float foam = mix(avg, lines, lod) * foam_zone;
			col = mix(col, c_foam, clamp(foam, 0.0, 0.8));
		}
	}
	float ln = max(contour(d, fw, 3.0) * 0.7, contour(d, fw, 8.0) * 0.45) * step(0.5, d);
	col = mix(col, c_line, ln * 0.22 * (1.0 - clamp(foam_zone * 1.5, 0.0, 1.0)));
	COLOR = vec4(col, 1.0);
}
