extends RefCounted
## The wave field of the overworld sea (2026-10-13, view only): the CPU twin of
## water.gdshader's height and normal, so a sprite on the sea (a ship) can bob,
## pitch and leave a wake that agree with the water drawn under it.
##
## Five directional trains of one dominant wind (GeoFields.wind_dir(): from the
## NW for the Mediterranean's mistral, from the E for a Caribbean map), headings
## spread -40..+45 degrees around it and wavelengths 12..56 px with no integer
## ratios, so no one train dominates. Each is a Stokes-like sine (sharper crest,
## flatter trough) with its phase bent by a value-noise warp and its height grouped
## by a value-noise envelope (both non-periodic). Three large slow fields shape
## the sea: the gust (wind patches: rough and glassy stretches, x0.25..1.15 on all
## trains), the veer (the wind direction turns by up to +-0.4 rad across the basin,
## so crests curve) and the drifting noise itself. Heights are in arbitrary units,
## about +-2.0 at most in open sea (typically under 1); `amp()` damps them near
## the coast and in sheltered water.
##
## TRAINS rows: x = heading in degrees from the wind (+ clockwise on the map),
## y = wavelength in map px, z = phase speed in map px per second (about
## sqrt(wavelength), deep water), w = amplitude.
## water.gdshader gets the same rows as uniforms (map_view.gd), so this file is
## the one place that defines the waves; the noise constants below are repeated in
## the shader (keep them equal; the normal here ignores the warp's and the
## envelope's own gradients, the shader too). hash/vnoise are the shader's.
##
## Typical use (a ship at map point p, heading h):
##   var t := SeaWaves.t                       # the view's clock (map_view advances it)
##   var a := SeaWaves.amp(p)                  # 0..1 sheltered .. open
##   var bob := SeaWaves.height(p, t) * a      # lift (scale to taste)
##   var n := SeaWaves.normal(p, t)            # unit (x, y, z); tilt = (n.x, n.y) * a
##   pitch / roll = n projected on the hull's forward / side axes
##   wake: stern positions as Line2D points that keep their world position and fade;
##         the sea's own motion is the phase speed above, not a drift of the points.

const GeoFields := preload("res://game/campaign/geo_fields.gd")

const TRAINS: Array[Vector4] = [
	Vector4(0.0, 56.0, 6.6, 0.52),
	Vector4(30.0, 39.0, 5.5, 0.44),
	Vector4(-28.0, 27.0, 4.6, 0.36),
	Vector4(45.0, 18.0, 3.75, 0.27),
	Vector4(-40.0, 12.0, 3.06, 0.20),
]
const WARP_A := 3.0
const WARP_S1 := 1.0 / 90.0
const WARP_S2 := 1.0 / 28.0
const ENV_S1 := 1.0 / 220.0
const ENV_S2 := 1.0 / 130.0
const GUST_S1 := 1.0 / 650.0
const GUST_S2 := 1.0 / 300.0
const VEER_S := 1.0 / 800.0
const VEER_A := 0.8
const STEEP := 0.22            # the Stokes crest term

## The view's wave clock in seconds (map_view.gd advances it and sends the same
## value to the shader).
static var t := 0.0


## Train i's unit direction of travel for a wind blowing towards `wind`.
static func dir(i: int, wind: Vector2) -> Vector2:
	return wind.rotated(deg_to_rad(TRAINS[i].x))


## Damping of the waves at map point p (0.2 at the shore .. 1 open sea).
static func amp(p: Vector2) -> float:
	return amp_at(GeoFields.coast_km(p), GeoFields.exposure(p)) * GeoFields.wind_strength()


## The same from the coast distance (km) and the exposure (0..1): the shader's rule.
static func amp_at(coast_km: float, expo: float) -> float:
	var near := smoothstep(1.0, 24.0, coast_km)
	var open := smoothstep(0.2, 0.8, expo)
	return lerpf(0.2, 1.0, near) * lerpf(0.5, 1.0, open)


static func _fract(x: float) -> float:
	return x - floorf(x)


## The shader's hash (Dave Hoskins) and value noise, 0..1.
static func _hash(p: Vector2) -> float:
	var a := _fract(p.x * 0.1031)
	var b := _fract(p.y * 0.1031)
	var c := _fract(p.x * 0.1031)
	var d := a * (b + 33.33) + b * (c + 33.33) + c * (a + 33.33)   # dot(p3, p3.yzx + 33.33)
	a += d
	b += d
	c += d
	return _fract((a + b) * c)


static func vnoise(p: Vector2) -> float:
	var i := p.floor()
	var f := Vector2(_fract(p.x), _fract(p.y))
	f = Vector2(f.x * f.x * f.x * (f.x * (f.x * 6.0 - 15.0) + 10.0), f.y * f.y * f.y * (f.y * (f.y * 6.0 - 15.0) + 10.0))
	return lerpf(lerpf(_hash(i), _hash(i + Vector2(1, 0)), f.x), lerpf(_hash(i + Vector2(0, 1)), _hash(i + Vector2(1, 1)), f.x), f.y)


## The shared slow fields at p: [gust 0.25..1.15, veer (rad), warp noise 1, warp
## noise 2 (both -1..1), envelope noise 1, 2 (0..1)] (the shader's wave_field).
static func field(p: Vector2, time: float, wind: Vector2) -> PackedFloat64Array:
	var w := wind * time
	var g := 0.65 * vnoise((p - w * 4.0) * GUST_S1 + Vector2(11.3, 5.7)) + 0.35 * vnoise((p - w * 6.0) * GUST_S2 + Vector2(3.1, 17.9))
	return PackedFloat64Array([
		lerpf(0.25, 1.15, smoothstep(0.34, 0.66, g)),
		(vnoise((p - w * 2.0) * VEER_S + Vector2(23.1, 41.7)) - 0.5) * VEER_A,
		(vnoise((p - w * 3.0) * WARP_S1 + Vector2(7.7, 1.3)) - 0.5) * 2.0,
		(vnoise((p - w * 4.5) * WARP_S2 + Vector2(29.9, 13.1)) - 0.5) * 2.0,
		vnoise((p - w * 2.0) * ENV_S1 + Vector2(37.3, 9.1)),
		vnoise((p - w * 3.0) * ENV_S2 + Vector2(19.7, 31.9)),
	])


## Train i's phase and amplitude (gust and envelope included) from the fields.
static func _phase(i: int, p: Vector2, time: float, d: Vector2, f: PackedFloat64Array) -> float:
	var trn := TRAINS[i]
	var k := TAU / trn.y
	var th := float(i) * 2.4
	var warp := WARP_A * (56.0 / trn.y) * (cos(th) * f[2] * 0.65 + sin(th) * f[3] * 0.35 + sin(th + 1.0) * f[2] * 0.35)
	return p.dot(d) * k - time * trn.z * k + warp


static func _am(i: int, f: PackedFloat64Array) -> float:
	var th := float(i) * 2.4
	var env := 0.35 + 0.65 * smoothstep(0.2, 0.8, lerpf(f[4], f[5], 0.5 + 0.5 * cos(th + 1.0)))
	return TRAINS[i].w * env * f[0]


## Unscaled height at map point p and time (sum of the trains).
static func height(p: Vector2, time: float = t, wind: Vector2 = Vector2.ZERO) -> float:
	if wind == Vector2.ZERO:
		wind = GeoFields.wind_dir()
	var f := field(p, time, wind)
	var wv := wind.rotated(f[1])
	var h := 0.0
	for i in TRAINS.size():
		var ph := _phase(i, p, time, dir(i, wv), f)
		h += _am(i, f) * (sin(ph) - STEEP * cos(2.0 * ph))
	return h


## Unit surface normal (x east, y south, z up) of the unscaled field; `slope`
## sets how steep the water looks (1 = the shader's value).
static func normal(p: Vector2, time: float = t, wind: Vector2 = Vector2.ZERO, slope: float = 2.2) -> Vector3:
	if wind == Vector2.ZERO:
		wind = GeoFields.wind_dir()
	var f := field(p, time, wind)
	var wv := wind.rotated(f[1])
	var g := Vector2.ZERO
	for i in TRAINS.size():
		var d := dir(i, wv)
		var ph := _phase(i, p, time, d, f)
		var k := TAU / TRAINS[i].y
		g += d * (_am(i, f) * k * (cos(ph) + 2.0 * STEEP * sin(2.0 * ph)))
	return Vector3(-g.x * slope, -g.y * slope, 1.0).normalized()
