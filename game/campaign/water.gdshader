shader_type canvas_item;
// The sea of the campaign map (third pass, 2026-10-13). Pass 2 kept a narrow calm
// shallow band hugging the coast (tools/geo_fit.py COAST field) falling to the
// open-sea colour and two sharp 1 px offshore contour lines (fwidth), with a faint
// advected current texture. Now, on "high":
//  - waves: five directional trains from the map's wind (uniforms train0..4 and
//    wind_dir, the rows of sea_waves.gd, which holds the same height / normal on
//    the CPU for ships), lit as a normal map from the north-west with a very small
//    glint; damped near the coast and in sheltered water; the open sea is patchy (slow
//    wind gusts: rough and glassy stretches), the wind veers across the basin and
//    the phase warp and group envelope are value noise, so nothing tiles;
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
uniform vec4 train0 = vec4(0.0, 56.0, 6.6, 0.52);          // heading deg, wavelength px, speed px/s, amplitude
uniform vec4 train1 = vec4(30.0, 39.0, 5.5, 0.44);
uniform vec4 train2 = vec4(-28.0, 27.0, 4.6, 0.36);
uniform vec4 train3 = vec4(45.0, 18.0, 3.75, 0.27);
uniform vec4 train4 = vec4(-40.0, 12.0, 3.06, 0.20);
uniform vec2 gyre_c = vec2(1190.0, 800.0);                 // western Mediterranean (map px)
uniform float gyre_r = 420.0;
uniform vec3 c_shore = vec3(0.27, 0.46, 0.52);   // at the coast
uniform vec3 c_shal = vec3(0.18, 0.33, 0.42);    // about 6 km
uniform vec3 c_deep = vec3(0.13, 0.25, 0.34);    // 25 km and more
uniform vec3 c_line = vec3(0.62, 0.80, 0.86);    // contour lines
uniform vec3 c_foam = vec3(0.90, 0.95, 0.96);
uniform float wave_gain = 1.0;                   // strength of the lit waves

const float WARP_A = 3.0;      // phase warp size in rad for the 56 px train (x 56 / wavelength for shorter ones; x the noise, +-1.2 typical)
const float WARP_S1 = 1.0 / 90.0;
const float WARP_S2 = 1.0 / 28.0;
const float ENV_S1 = 1.0 / 220.0;
const float ENV_S2 = 1.0 / 130.0;
const float GUST_S1 = 1.0 / 650.0;
const float GUST_S2 = 1.0 / 300.0;
const float VEER_S = 1.0 / 800.0;
const float VEER_A = 0.8;      // wind veer in rad per unit of (noise - 0.5): +-0.4 rad at most
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

// The shared wave fields at map point p (sea_waves.gd _field, line for line):
// x gust 0.25..1.15 (wind patches), y veer angle (rad), zw warp noises, env noises.
struct Field {
	float gust;
	float veer;
	vec2 wn;
	vec2 en;
};

Field wave_field(vec2 p) {
	Field f;
	vec2 w = wind_dir * wave_t;
	float g = 0.65 * vnoise((p - w * 4.0) * GUST_S1 + vec2(11.3, 5.7)) + 0.35 * vnoise((p - w * 6.0) * GUST_S2 + vec2(3.1, 17.9));
	f.gust = mix(0.25, 1.15, smoothstep(0.34, 0.66, g));
	f.veer = (vnoise((p - w * 2.0) * VEER_S + vec2(23.1, 41.7)) - 0.5) * VEER_A;
	f.wn = (vec2(vnoise((p - w * 3.0) * WARP_S1 + vec2(7.7, 1.3)), vnoise((p - w * 4.5) * WARP_S2 + vec2(29.9, 13.1))) - 0.5) * 2.0;
	f.en = vec2(vnoise((p - w * 2.0) * ENV_S1 + vec2(37.3, 9.1)), vnoise((p - w * 3.0) * ENV_S2 + vec2(19.7, 31.9)));
	return f;
}

// One train: adds its height to z and its gradient to xy (sea_waves.gd, line for line).
void train(vec4 tr, float idx, vec2 p, float wpp, Field f, vec2 wv, inout vec3 hg) {
	float lod = smoothstep(5.0, 11.0, tr.y / wpp);        // gone when under ~6 screen px
	if (lod <= 0.0) {
		return;
	}
	float a = radians(tr.x);
	vec2 d = vec2(wv.x * cos(a) - wv.y * sin(a), wv.x * sin(a) + wv.y * cos(a));
	float k = 6.2831853 / tr.y;
	float th = idx * 2.4;
	float warp = WARP_A * (56.0 / tr.y) * (cos(th) * f.wn.x * 0.65 + sin(th) * f.wn.y * 0.35 + sin(th + 1.0) * f.wn.x * 0.35);
	float ph = dot(p, d) * k - wave_t * tr.z * k + warp;
	float env = 0.35 + 0.65 * smoothstep(0.2, 0.8, mix(f.en.x, f.en.y, 0.5 + 0.5 * cos(th + 1.0)));
	float am = tr.w * env * f.gust * lod;
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
		Field wf = wave_field(wp);
		float va = wf.veer;
		vec2 wv = vec2(wind_dir.x * cos(va) - wind_dir.y * sin(va), wind_dir.x * sin(va) + wind_dir.y * cos(va));
		train(train0, 0.0, wp, wpp, wf, wv, hg);
		train(train1, 1.0, wp, wpp, wf, wv, hg);
		train(train2, 2.0, wp, wpp, wf, wv, hg);
		train(train3, 3.0, wp, wpp, wf, wv, hg);
		train(train4, 4.0, wp, wpp, wf, wv, hg);
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
