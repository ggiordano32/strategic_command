extends RefCounted
## The wave field of the overworld sea (2026-10-13, view only): the CPU twin of
## water.gdshader's height and normal, so a sprite on the sea (a ship) can bob,
## pitch and leave a wake that agree with the water drawn under it.
##
## Three directional trains of one dominant wind (GeoFields.wind_dir(): from the
## NW for the Mediterranean's mistral, from the E for a Caribbean map): the wind
## sea (along the wind), a weaker cross swell and a short chop. Each is a Stokes-
## like sine (sharper crest, flatter trough) with its phase bent by a slow warp
## and its height grouped by a slow envelope, so there are no straight parallel
## rulings. Heights are in arbitrary units, about +-1.9 at most in open sea;
## `amp()` damps them near the coast and in sheltered water.
##
## TRAINS rows: x = heading in degrees from the wind (+ clockwise on the map),
## y = wavelength in map px, z = phase speed in map px per second, w = amplitude.
## water.gdshader gets the same rows as uniforms (map_view.gd), so this file is
## the one place that defines the waves; the warp and envelope constants below
## are repeated in the shader (keep them equal; the normal here ignores the
## warp's and the envelope's own gradients, the shader too).
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
	Vector4(0.0, 46.0, 6.0, 1.0),
	Vector4(55.0, 88.0, 4.5, 0.55),
	Vector4(-30.0, 27.0, 5.0, 0.35),
]
const WARP_K := 0.045          # the phase warp's spatial frequency (rad per map px)
const WARP_A := 1.4            # ... and its size in radians
const ENV_K := 0.012           # the group envelope's spatial frequency
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


static func _phase(i: int, p: Vector2, time: float, wind: Vector2) -> float:
	var trn := TRAINS[i]
	var d := dir(i, wind)
	var k := TAU / trn.y
	var warp := WARP_A * sin(p.dot(Vector2(d.y, -d.x)) * WARP_K + time * 0.11 + float(i) * 2.1)
	return p.dot(d) * k - time * trn.z * k + warp


static func _env(i: int, p: Vector2, time: float, wind: Vector2) -> float:
	var d := dir(i, wind)
	return 0.65 + 0.35 * sin(p.dot(d) * ENV_K * 0.6 + p.dot(Vector2(d.y, -d.x)) * ENV_K + time * 0.05 + float(i) * 4.0)


## Unscaled height at map point p and time (sum of the trains).
static func height(p: Vector2, time: float = t, wind: Vector2 = Vector2.ZERO) -> float:
	if wind == Vector2.ZERO:
		wind = GeoFields.wind_dir()
	var h := 0.0
	for i in TRAINS.size():
		var ph := _phase(i, p, time, wind)
		h += TRAINS[i].w * _env(i, p, time, wind) * (sin(ph) - STEEP * cos(2.0 * ph))
	return h


## Unit surface normal (x east, y south, z up) of the unscaled field; `slope`
## sets how steep the water looks (1 = the shader's value).
static func normal(p: Vector2, time: float = t, wind: Vector2 = Vector2.ZERO, slope: float = 2.2) -> Vector3:
	if wind == Vector2.ZERO:
		wind = GeoFields.wind_dir()
	var g := Vector2.ZERO
	for i in TRAINS.size():
		var ph := _phase(i, p, time, wind)
		var k := TAU / TRAINS[i].y
		g += dir(i, wind) * (TRAINS[i].w * _env(i, p, time, wind) * k * (cos(ph) + 2.0 * STEEP * sin(2.0 * ph)))
	return Vector3(-g.x * slope, -g.y * slope, 1.0).normalized()
