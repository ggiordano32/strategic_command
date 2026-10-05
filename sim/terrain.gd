extends RefCounted
## Deterministic terrain height generation for the battle sim (integers only).
##
## A battle map's ground is a grid of integer heights (sim units, 1 m = 1024)
## at nodes CELL (4 m) apart covering the field; BattleSim samples it with
## fixed-point bilinear interpolation. The grid is never transmitted: it is
## built from a small parameter set, so both lockstep peers (and, later, the
## campaign passing "region terrain kind + seed") build the identical field.
##
## Scenario data ("terrain" key of a scenario, all ints):
##   kind      K_* below (K_RANDOM picks one of the hilly kinds from the seed)
##   seed      generation seed; -1 (default) = the battle seed
##   relief_m  feature height in metres (0 = the kind's default)
##   scale_m   feature size in metres (0 = the kind's default)
##   sym       1 = make the map exactly symmetric under the 180-degree
##             rotation that maps one army's half onto the other's (fairness
##             tests; needs the field size to be a multiple of 4 m)
##   features  extra hand-placed features (for any kind; the only ones for
##             K_CUSTOM): [type, x_m, y_m, r_m, h_m, dir, len_m] with type
##             F_BUMP (round hill, radius r, height h; negative = hollow),
##             F_RIDGE (ridge or, with h < 0, a valley: a segment through x, y
##             along angle dir (0..1023, 0 = +x), half-length len, half-width
##             r), F_RAMP (one-sided slope rising by h toward angle dir over a
##             band of half-width r centred on x, y).
## Profiles are smooth integer bells (1 - t^2)^2 and smoothsteps computed
## from squared distances, so no square root and no float is involved.
## The generator has its own xorshift RNG and never touches the sim's.
##
## Hooks for later work: vegetation can be added as further feature types
## rasterised into a second grid; the campaign's map generation only needs to
## fill this dictionary (kind + seed from the region, or explicit features).

const FM := preload("res://sim/fixed_math.gd")

const M := 1024
const SHIFT := 12            # node spacing 4 m = 4096 sim units
const CELL := 4096

const K_FLAT := 0
const K_ROLLING := 1
const K_RIDGE := 2
const K_VALLEY := 3
const K_HILL := 4
const K_SLOPE := 5
const K_RANDOM := 6
const K_CUSTOM := 7
const KIND_NAMES: Array[String] = ["Flat", "Rolling", "Ridge", "Valley", "Hill", "Slope",
	"Random", "Custom"]

const F_BUMP := 1
const F_RIDGE := 2
const F_RAMP := 3

## Defaults per kind: relief (m), scale (m). Chosen so the steepest ground of
## a playable map is roughly 15-25% (a 1.5 * relief / scale bell maximum).
const RELIEF := [0, 9, 12, 10, 16, 18, 0, 0]
const SCALE := [0, 95, 85, 110, 105, 0, 0, 0]


## Build the height grid for a field of field_w x field_h sim units.
## Returns {"on", "nx", "ny", "h", "kind", "seed", "relief_m", "scale_m",
## "sym", "features"} (h: PackedInt32Array of nx * ny node heights, min 0).
static func build(terrain: Dictionary, battle_seed: int, field_w: int, field_h: int) -> Dictionary:
	var kind := int(terrain.get("kind", K_FLAT))
	var tseed := int(terrain.get("seed", -1))
	if tseed < 0:
		tseed = battle_seed
	var rng := PackedInt32Array([((tseed & 0x7FFFFFFF) * 69069 + 0x3C6EF35F) & 0x7FFFFFFF])
	if rng[0] == 0:
		rng[0] = 0x2468ACE
	if kind == K_RANDOM:
		kind = K_ROLLING + _r(rng, 5)
	var relief := int(terrain.get("relief_m", 0))
	if relief <= 0:
		relief = RELIEF[kind]
	var scale := int(terrain.get("scale_m", 0))
	if scale <= 0:
		scale = SCALE[kind]
	var sym := int(terrain.get("sym", 0))
	var nx := (field_w + CELL - 1) / CELL + 1
	var ny := (field_h + CELL - 1) / CELL + 1
	var h := PackedInt32Array()
	h.resize(nx * ny)
	h.fill(0)
	var feats: Array = []
	if kind != K_FLAT and kind != K_CUSTOM:
		feats = _features(kind, rng, field_w / M, field_h / M, relief, scale)
	for f in terrain.get("features", []):
		feats.append(f)
	var out := {"on": 0, "nx": nx, "ny": ny, "h": h, "kind": kind, "seed": tseed,
		"relief_m": relief, "scale_m": scale, "sym": sym, "features": feats}
	if feats.is_empty():
		return out
	for f in feats:
		var a: Array = f
		var ty := int(a[0])
		var x := int(a[1]) * M
		var y := int(a[2]) * M
		var r := maxi(int(a[3]), 1) * M
		var amp := int(a[4]) * M
		var dir := int(a[5]) if a.size() > 5 else 0
		var ln := (int(a[6]) if a.size() > 6 else 0) * M
		match ty:
			F_BUMP:
				_bump(h, nx, ny, x, y, r, amp)
			F_RIDGE:
				_ridge(h, nx, ny, x, y, r, amp, dir, ln)
			F_RAMP:
				_ramp(h, nx, ny, x, y, r, amp, dir)
	if sym != 0:
		# Exact 180-degree symmetry: node k and node (last - k) take the same
		# height (the integer mean is commutative, so both get one value).
		var last := nx * ny - 1
		for k in (nx * ny + 1) / 2:
			var v := (h[k] + h[last - k]) / 2
			h[k] = v
			h[last - k] = v
	var lo := h[0]
	var hi := h[0]
	for v in h:
		lo = mini(lo, v)
		hi = maxi(hi, v)
	if hi == lo:
		return out
	for k in h.size():
		h[k] -= lo
	out["h"] = h
	out["on"] = 1
	return out


## Node gradients (Q12 grade: 4096 = 1 m rise per m) by central differences
## (one-sided at the edges); antisymmetric under the field's 180-degree
## rotation, like the heights are symmetric.
static func gradients(h: PackedInt32Array, nx: int, ny: int) -> Array:
	var gx := PackedInt32Array()
	var gy := PackedInt32Array()
	gx.resize(nx * ny)
	gy.resize(nx * ny)
	for j in ny:
		for i in nx:
			var k := j * nx + i
			# Heights are sim units, nodes 4096 apart: grade Q12 = dh * 4096 /
			# spacing, i.e. dh for one cell and dh / 2 across two.
			if i == 0:
				gx[k] = h[k + 1] - h[k]
			elif i == nx - 1:
				gx[k] = h[k] - h[k - 1]
			else:
				gx[k] = (h[k + 1] - h[k - 1]) / 2
			if j == 0:
				gy[k] = h[k + nx] - h[k]
			elif j == ny - 1:
				gy[k] = h[k] - h[k - nx]
			else:
				gy[k] = (h[k + nx] - h[k - nx]) / 2
	return [gx, gy]


## 32-bit hash of the height grid (part of the sim's state hash).
static func grid_hash(h: PackedInt32Array, nx: int, ny: int, on: int) -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(PackedInt32Array([nx, ny, on]).to_byte_array())
	ctx.update(h.to_byte_array())
	return ctx.finish().decode_u32(0)


# ------------------------------------------------------------- features ---

static func _r(rng: PackedInt32Array, n: int) -> int:
	var x := rng[0]
	x ^= (x << 13) & 0x7FFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0x7FFFFFFF
	x &= 0x7FFFFFFF
	if x == 0:
		x = 0x2468ACE
	rng[0] = x
	return x % maxi(n, 1)


## Random integer in [lo, hi].
static func _rr(rng: PackedInt32Array, lo: int, hi: int) -> int:
	return lo + _r(rng, hi - lo + 1)


## Feature list for a generated kind. Armies stand at the top and bottom of
## the field, so ridges and valleys run roughly across it and slopes rise
## toward one army.
static func _features(kind: int, rng: PackedInt32Array, w: int, hgt: int, relief: int,
		scale: int) -> Array:
	var out: Array = []
	match kind:
		K_ROLLING:
			var n := 6 + _r(rng, 4)
			for k in n:
				var amp := relief * _rr(rng, 40, 100) / 100
				if _r(rng, 10) < 3:
					amp = -amp * 2 / 3
				out.append([F_BUMP, _rr(rng, w / 10, w * 9 / 10), _rr(rng, hgt / 10, hgt * 9 / 10),
					scale * _rr(rng, 75, 130) / 100, amp])
		K_RIDGE:
			out.append([F_RIDGE, w / 2 + _rr(rng, -w / 6, w / 6), hgt / 2 + _rr(rng, -hgt / 5, hgt / 5),
				scale * _rr(rng, 85, 115) / 100, relief, _rr(rng, -70, 70) & 1023,
				w * _rr(rng, 30, 45) / 100])
			out.append([F_BUMP, _rr(rng, w / 5, w * 4 / 5), _rr(rng, hgt / 5, hgt * 4 / 5),
				scale * 3 / 4, relief / 3])
		K_VALLEY:
			out.append([F_RIDGE, w / 2 + _rr(rng, -w / 8, w / 8), hgt / 2 + _rr(rng, -hgt / 10, hgt / 10),
				scale * _rr(rng, 90, 120) / 100, -relief, _rr(rng, -60, 60) & 1023, w * 2 / 3])
		K_HILL:
			out.append([F_BUMP, w / 2 + _rr(rng, -w / 5, w / 5), hgt / 2 + _rr(rng, -hgt / 5, hgt / 5),
				scale * _rr(rng, 90, 115) / 100, relief])
			out.append([F_BUMP, _rr(rng, w / 6, w * 5 / 6), _rr(rng, hgt / 6, hgt * 5 / 6),
				scale * 2 / 3, relief / 3])
		K_SLOPE:
			# Rising toward one army (up or down the screen), a little skewed.
			var dir := (256 if _r(rng, 2) == 0 else 768) + _rr(rng, -40, 40)
			out.append([F_RAMP, w / 2, hgt / 2, hgt * 32 / 100, relief, dir & 1023])
	# Gentle undulations so no ground is perfectly flat: low (under a
	# metre, so they rarely make a contour ring of their own) and broad.
	var small := 6 + (w * hgt) / 40000
	for k in small:
		var amp2 := 1
		if _r(rng, 2) == 0:
			amp2 = -amp2
		out.append([F_BUMP, _rr(rng, 0, w), _rr(rng, 0, hgt), _rr(rng, 35, 60), amp2])
	return out


## Node index range [lo, hi] covering coordinate range [a, b] (sim units).
static func _span(a: int, b: int, n: int) -> Vector2i:
	var lo := clampi((a + CELL - 1) / CELL if a > 0 else 0, 0, n - 1)
	var hi := clampi(b / CELL if b >= 0 else -1, -1, n - 1)
	return Vector2i(lo, hi)


## Round hill (amp > 0) or hollow: amp * (1 - d^2 / r^2)^2 within r.
static func _bump(h: PackedInt32Array, nx: int, ny: int, cx: int, cy: int, r: int, amp: int) -> void:
	var r2 := r * r
	var sx := _span(cx - r, cx + r, nx)
	var sy := _span(cy - r, cy + r, ny)
	for j in range(sy.x, sy.y + 1):
		var dy := j * CELL - cy
		var dy2 := dy * dy
		if dy2 >= r2:
			continue
		var row := j * nx
		for i in range(sx.x, sx.y + 1):
			var dx := i * CELL - cx
			var d2 := dx * dx + dy2
			if d2 >= r2:
				continue
			h[row + i] += amp * _bell(d2, r2) / 1024


## Bell profile (1 - t^2)^2 in Q10 (0..1024) for t^2 = d2 / r2 < 1.
static func _bell(d2: int, r2: int) -> int:
	var u := 1048576 - d2 * 1048576 / r2  # Q20
	return (u * u) >> 30


## Ridge (amp > 0) or valley along a segment: centre (cx, cy), direction
## dir, half-length ln, half-width r; bell profile of the distance to it.
static func _ridge(h: PackedInt32Array, nx: int, ny: int, cx: int, cy: int, r: int, amp: int,
		dir: int, ln: int) -> void:
	var c := FM.cos_a(dir)
	var s := FM.sin_a(dir)
	var r2 := r * r
	var ex := (absi(c) * ln) / FM.TRIG_ONE + r
	var ey := (absi(s) * ln) / FM.TRIG_ONE + r
	var sx := _span(cx - ex, cx + ex, nx)
	var sy := _span(cy - ey, cy + ey, ny)
	for j in range(sy.x, sy.y + 1):
		var ry := j * CELL - cy
		var row := j * nx
		for i in range(sx.x, sx.y + 1):
			var rx := i * CELL - cx
			var along := (rx * c + ry * s) / FM.TRIG_ONE
			var lat := (ry * c - rx * s) / FM.TRIG_ONE
			var past := maxi(absi(along) - ln, 0)
			var d2 := lat * lat + past * past
			if d2 >= r2:
				continue
			h[row + i] += amp * _bell(d2, r2) / 1024


## One-sided slope: rises by amp toward direction dir across a band of
## half-width r centred on (cx, cy) (smoothstep), flat beyond.
static func _ramp(h: PackedInt32Array, nx: int, ny: int, cx: int, cy: int, r: int, amp: int,
		dir: int) -> void:
	var c := FM.cos_a(dir)
	var s := FM.sin_a(dir)
	for j in ny:
		var ry := j * CELL - cy
		var row := j * nx
		for i in nx:
			var rx := i * CELL - cx
			var along := (rx * c + ry * s) / FM.TRIG_ONE
			var t := clampi((along + r) * 1024 / (2 * r), 0, 1024)  # Q10
			var f := (3 * t * t * 1024 - 2 * t * t * t) / 1048576  # smoothstep, Q10
			h[row + i] += amp * f / 1024
