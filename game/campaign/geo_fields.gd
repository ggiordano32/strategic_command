extends RefCounted
## Real-terrain fields of the campaign map for the view (floats allowed; the
## rules never read this). Decodes what tools/geo_fit.py baked:
##  - game/campaign/relief_data.gd: the FINE elevation field (FS samples per
##    grid cell side, 8: 0.025 degrees of latitude, 2.5 map px), SLOPE and
##    RELIEF_F at the same resolution, and COAST: the signed distance to the
##    coast (km, sea side positive, land side negative, about 80 km at most);
##  - campaign/data/elev_data.gd: per grid cell mean / max elevation, relief,
##    distance to the nearest river and the terrain class.
## Everything is decoded once on first use (about 0.1 s) and cached.
##
## Map points are in map pixels (map_geo.gd projection). Typical use:
##   GeoFields.elev_m(p)            metres at a map point (bilinear)
##   GeoFields.slope_pct(p)         gradient in percent
##   GeoFields.relief_m(p)          highest minus lowest metres in 5 x 5 samples
##   GeoFields.coast_km(p)          signed km to the coast (sea side positive)
##   GeoFields.exposure(p)         0..1 how open the sea is to the wind at a map point
##   GeoFields.shore_steep(p)      0..1 steepness of the land beside a sea point
##   GeoFields.wind_dir()          unit vector the wind blows TOWARDS (map axes, y south)
##   GeoFields.wind_strength()     0..1
##   GeoFields.cell_class(c)        CLASS_* of grid cell c
##   GeoFields.river_dist(c)        cells to the nearest river (float)
##   GeoFields.fine() / slope() / relief_field()  the raw fields (FW x FH, row 0 north)

# The baked fields of the active pack (use_pack). Rome: relief_data.gd and
# campaign/data/elev_data.gd (preloaded, so the export always carries them);
# other packs load relief_<key>.gd and campaign/data/<key>_elev_data.gd on
# demand, so a Rome session never touches the West files. (map_geo.gd preloads
# this script, so it is reached lazily here, not preloaded: no cycle.)
const RomeRelief := preload("res://game/campaign/relief_data.gd")
const RomeElev := preload("res://campaign/data/elev_data.gd")
const MAP_GEO := "res://game/campaign/map_geo.gd"
static var Relief = RomeRelief
static var Elev = RomeElev
static var pack_key := "rome"

const CLASS_SEA := -1
const CLASS_PLAIN := 0
const CLASS_ROLLING := 1
const CLASS_VALLEY := 2
const CLASS_HILL := 3
const CLASS_RIDGE := 4

static var _fine := PackedFloat32Array()     # metres
static var _slope := PackedByteArray()       # percent
static var _relief := PackedByteArray()      # units of 8 m
static var _coast := PackedByteArray()       # 128 + km, sea side positive
static var _expo := PackedByteArray()        # 0..255 (steps of 8)
static var _shore := PackedByteArray()       # 0..252 (steps of 36)
static var _px := 2.5                        # map pixels per fine sample


## Switch the baked fields to pack `key` and drop every cache (fails loudly if
## a data file is missing). Usually reached through map_geo.gd's use_pack.
static func use_pack(key: String) -> void:
	if key == pack_key:
		return
	if key == "rome":
		Relief = RomeRelief
		Elev = RomeElev
	else:
		var rp := "res://game/campaign/relief_%s.gd" % key
		var ep := "res://campaign/data/%s_elev_data.gd" % key
		assert(ResourceLoader.exists(rp), "geo_fields.use_pack: no relief file " + rp)
		assert(ResourceLoader.exists(ep), "geo_fields.use_pack: no elev file " + ep)
		var r = load(rp)
		var e = load(ep)
		if r == null or e == null:
			push_error("geo_fields.use_pack: cannot load the %s fields" % key)
			return
		Relief = r
		Elev = e
	pack_key = key
	_fine = PackedFloat32Array()
	_slope = PackedByteArray()
	_relief = PackedByteArray()
	_coast = PackedByteArray()
	_expo = PackedByteArray()
	_shore = PackedByteArray()
	_px = 2.5


static func _decode(text: String, n: int) -> PackedByteArray:
	return Marshalls.base64_to_raw(text).decompress(n, FileAccess.COMPRESSION_DEFLATE)


static func ensure() -> void:
	if _fine.size() > 0:
		return
	var n: int = Relief.FW * Relief.FH
	var raw := _decode(Relief.FINE, n)
	var lut := PackedFloat32Array()
	lut.resize(256)
	for v in 256:
		lut[v] = (v / float(Relief.FINE_K)) * (v / float(Relief.FINE_K))
	_fine.resize(n)
	for i in n:
		_fine[i] = lut[raw[i]]
	_slope = _decode(Relief.SLOPE, n)
	_relief = _decode(Relief.RELIEF_F, n)
	_coast = _decode(Relief.COAST, n)
	_expo = _decode(Relief.EXPOSURE, n)
	_shore = _decode(Relief.SHORE, n)
	_px = 20.0 / float(Relief.FS)


static func fine_width() -> int:
	return Relief.FW


static func fine_height() -> int:
	return Relief.FH


## Metres on the ground per fine sample (latitude: 111,320 m a degree).
static func sample_m() -> float:
	return sample_px() / float(load(MAP_GEO).PX_LAT) * 111320.0


## Map pixels per fine sample (the cell size / FS).
static func sample_px() -> float:
	return 20.0 / float(Relief.FS)


static func fine() -> PackedFloat32Array:
	ensure()
	return _fine


static func slope() -> PackedByteArray:
	ensure()
	return _slope


static func relief_field() -> PackedByteArray:
	ensure()
	return _relief


## The coast field as baked: byte = 128 + signed km (sea side positive).
static func coast() -> PackedByteArray:
	ensure()
	return _coast


## Signed distance in km from map point p to the coast: positive on the sea,
## negative on the land (bilinear between sample centres; capped near 80).
static func coast_km(p: Vector2) -> float:
	ensure()
	var fx := p.x / _px - 0.5
	var fy := p.y / _px - 0.5
	var x0 := clampi(int(floor(fx)), 0, Relief.FW - 2)
	var y0 := clampi(int(floor(fy)), 0, Relief.FH - 2)
	var tx := clampf(fx - x0, 0.0, 1.0)
	var ty := clampf(fy - y0, 0.0, 1.0)
	var i: int = y0 * Relief.FW + x0
	var a := lerpf(_coast[i], _coast[i + 1], tx)
	var b := lerpf(_coast[i + Relief.FW], _coast[i + Relief.FW + 1], tx)
	return lerpf(a, b, ty) - 128.0


## Wind exposure of the sea at map point p, 0 (sheltered: bay, lee of land)
## to 1 (open to the wind and the sea); bilinear. Baked by
## tools/geo_fit.py bake_exposure (the config's "wind").
static func exposure(p: Vector2) -> float:
	ensure()
	return _bilinear8(_expo, p) / 255.0


## Steepness of the land within two samples of map point p, 0 .. 1.
static func shore_steep(p: Vector2) -> float:
	ensure()
	return _bilinear8(_shore, p) / 255.0


## The direction the wind blows towards (unit, map axes: x east, y south), from
## the baked compass bearing it blows FROM (315 = north-west gives (0.71, 0.71)).
static func wind_dir() -> Vector2:
	var b := deg_to_rad(float(Relief.WIND_FROM_DEG))
	return Vector2(-sin(b), cos(b))


static func wind_strength() -> float:
	return float(Relief.WIND_STRENGTH) / 100.0


static func _bilinear8(f: PackedByteArray, p: Vector2) -> float:
	var fx := p.x / _px - 0.5
	var fy := p.y / _px - 0.5
	var x0 := clampi(int(floor(fx)), 0, Relief.FW - 2)
	var y0 := clampi(int(floor(fy)), 0, Relief.FH - 2)
	var tx := clampf(fx - x0, 0.0, 1.0)
	var ty := clampf(fy - y0, 0.0, 1.0)
	var i: int = y0 * Relief.FW + x0
	return lerpf(lerpf(f[i], f[i + 1], tx), lerpf(f[i + Relief.FW], f[i + Relief.FW + 1], tx), ty)


## The exposure (R) and shore steepness (G) as an RG8 image for the water shader.
static func shore_image() -> Image:
	ensure()
	var n: int = Relief.FW * Relief.FH
	var d := PackedByteArray()
	d.resize(n * 2)
	for i in n:
		d[2 * i] = _expo[i]
		d[2 * i + 1] = _shore[i]
	return Image.create_from_data(Relief.FW, Relief.FH, false, Image.FORMAT_RG8, d)


## Elevation in metres at map point p (bilinear between sample centres).
static func elev_m(p: Vector2) -> float:
	ensure()
	var fx := p.x / _px - 0.5
	var fy := p.y / _px - 0.5
	var x0 := clampi(int(floor(fx)), 0, Relief.FW - 2)
	var y0 := clampi(int(floor(fy)), 0, Relief.FH - 2)
	var tx := clampf(fx - x0, 0.0, 1.0)
	var ty := clampf(fy - y0, 0.0, 1.0)
	var i: int = y0 * Relief.FW + x0
	return lerpf(lerpf(_fine[i], _fine[i + 1], tx), lerpf(_fine[i + Relief.FW], _fine[i + Relief.FW + 1], tx), ty)


static func _at(field: PackedByteArray, p: Vector2) -> int:
	ensure()
	var x := clampi(int(p.x / _px), 0, Relief.FW - 1)
	var y := clampi(int(p.y / _px), 0, Relief.FH - 1)
	return field[y * Relief.FW + x]


static func slope_pct(p: Vector2) -> float:
	return float(_at(_slope, p))


static func relief_m(p: Vector2) -> float:
	return float(_at(_relief, p)) * 8.0


# Per grid cell (index y * W + x).

static func cell_mean(c: int) -> int:
	return Elev.MEAN[c]


static func cell_max(c: int) -> int:
	return Elev.MAXH[c]


static func cell_relief(c: int) -> int:
	return Elev.RELIEF[c]


## Cells from the cell's centre to the nearest river line (float, 9.9 max).
static func river_dist(c: int) -> float:
	return float(Elev.RIVER_DIST[c]) / 10.0


## CLASS_SEA .. CLASS_RIDGE of cell c (the classes of tools/geo_fit.py).
static func cell_class(c: int) -> int:
	var ch: int = (Elev.CLASS[c / Elev.W] as String).unicode_at(c % Elev.W)
	return CLASS_SEA if ch == 46 else ch - 48
