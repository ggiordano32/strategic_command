extends RefCounted
## Battle map features beyond height (integers only, own RNG): woods on any
## map, and the settlement of a city map (buildings, walls, towers, gates,
## streets, plaza, orchards and fields outside, a navigation graph for unit
## paths). Built once at setup from the scenario's terrain dictionary, so
## both lockstep peers build the identical map; nothing is transmitted.
##
## Terrain dictionary keys read here (all ints / arrays of ints):
##   forest   woods coverage 0-100 (region data; 0 = none): blobs of trees
##            whose edges follow the height, never across the deployment
##            zones' centres
##   woods    hand-placed rectangles of trees [x_m, y_m, half_w_m, half_h_m,
##            density 1-3] (tests, set pieces)
##   ground   ground palette (view only; see PALETTES)
##   blocks   hand-placed buildings [x0, y0, x1, y1] (m) on a map without a
##            city (tests, set pieces: streets); the area round them counts
##            as a settlement's streets (V_URBAN) within `urban` rectangles
##   city     settlement: {seed, level 0 village / 1 town / 2 city, walls 0-3,
##            bld [building chain ids present], def (defending sim side)}
##
## Grids (final frame, row-major, index = row * width + col):
##   veg  4 m cells: bits 0-1 tree density 0-3, V_URBAN inside a settlement,
##        V_FIELD farm field, V_ROAD main street, V_PLAZA (the last three
##        are view only)
##   obs  2 m cells: C_* kind (building, wall body, walkway, tower, gate g)
##
## A city is generated in a canonical frame (defenders at the top, the main
## gate facing the attackers at the bottom), relative to its own centre, so
## a city looks the same whatever the field size; if the defenders are sim
## side 0 (the bottom) everything is turned 180 degrees at the end.

const FM := preload("res://sim/fixed_math.gd")

const M := 1024

# 2 m obstacle cells.
const C_OPEN := 0
const C_BUILDING := 1
const C_WALL := 2      # wall body: outer parapet and inner face
const C_WALK := 3      # wall walkway (only units placed on the wall stand here)
const C_TOWER := 4
const C_GATE := 8      # + gate index (8..11)

# Passability bits (BattleSim.nav).
const NAV_GROUND := 1
const NAV_WALL := 2

# 4 m vegetation cells.
const V_DENS := 3
const V_URBAN := 4
const V_FIELD := 8
const V_ROAD := 16
const V_PLAZA := 32

## Ground palettes (view: battle ground and campaign map tint), by index.
const PAL_PLAIN := 0   # the original green-grey look (sandbox default)
const PAL_ARID := 1    # Africa, south-east Iberia: ochre, olive scrub
const PAL_DRY := 2     # Greece, southern Italy, the islands: straw, olives
const PAL_GREEN := 3   # Gaul, northern Italy, Atlantic Iberia: oak, pine
const PAL_ROCKY := 4   # mountains: grey-brown, pine
const PALETTE_NAMES: Array[String] = ["Plain", "Arid", "Dry", "Green", "Rocky"]
## Typical woods coverage per palette (sandbox ground choice).
const PALETTE_FOREST: Array[int] = [0, 8, 18, 38, 26]

# Settlement geometry (metres).
const R_LEVEL: Array[int] = [60, 85, 115]          # footprint radius by level
const WALL_T: Array[int] = [0, 8, 10, 12]          # wall thickness by wall level
const WALL_P: Array[int] = [0, 2, 2, 4]            # outer parapet thickness
const WALK_W := 4                       # walkway width
const WALL_H: Array[int] = [0, 5, 7, 9]            # walkway height above the ground
const GATE_HW := 4                      # gate opening half width
const PLAZA_HS: Array[int] = [12, 16, 22]          # plaza half size by level
const CAPTURE_EXTRA := 6                # capture zone = plaza half size + this
const CITY_TOP := 70                    # canonical: top edge to the footprint
const APPROACH := 150                   # main gate (outer face) to the attackers' front
const RING_W := 6                       # ring road inside the walls
const BUILT_PCT: Array[int] = [62, 76, 88]         # lots with a building by level
const BUILD_H: Array[int] = [4, 5, 6]              # building height (line of fire)
const GATE_HP: Array[int] = [0, 1800, 2700, 3800]  # gate hit points by wall level
const EXT := 170                        # block grid extent from the centre
const EDGE_MAX := 48                    # nav graph edges at most this long
const NODE_STEP := 30                   # ring nodes every this many metres

# Building kinds (view: roof colours).
const B_HOUSE := 0
const B_TEMPLE := 1
const B_MARKET := 2
const B_BARRACKS := 3
const B_STABLES := 4
const B_WORKSHOP := 5
const B_RANGE := 6

const K_HILL := 4
const K_RIDGE := 2

static var _cache_key := ""
static var _cache: Dictionary = {}


# ------------------------------------------------------------------- rng ---

static func _rng(seed_v: int) -> PackedInt32Array:
	var s := PackedInt32Array([((seed_v & 0x7FFFFFFF) * 69069 + 0x1F2E3D4C) & 0x7FFFFFFF])
	if s[0] == 0:
		s[0] = 0x13579BD
	return s


static func _r(rng: PackedInt32Array, n: int) -> int:
	var x := rng[0]
	x ^= (x << 13) & 0x7FFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0x7FFFFFFF
	x &= 0x7FFFFFFF
	if x == 0:
		x = 0x13579BD
	rng[0] = x
	return x % maxi(n, 1)


static func _rr(rng: PackedInt32Array, lo: int, hi: int) -> int:
	return lo + _r(rng, hi - lo + 1)


# ------------------------------------------------------------ frame -------

## City parameters with defaults filled in.
static func city_params(c: Dictionary) -> Dictionary:
	var bld: Array = []
	for b in c.get("bld", []):
		bld.append(int(b))
	return {"seed": int(c.get("seed", 1)), "level": clampi(int(c.get("level", 1)), 0, 2),
		"walls": clampi(int(c.get("walls", 0)), 0, 3), "bld": bld, "def": int(c.get("def", 1))}


## Canonical centre and radius of a city on a field w_m x h_m metres.
static func city_frame(c: Dictionary, w_m: int, _h_m: int) -> Vector3i:
	var p := city_params(c)
	var r0: int = R_LEVEL[int(p["level"])]
	var cx := (w_m / 2) & ~1
	var cy := (CITY_TOP + r0 * 112 / 100) & ~1
	return Vector3i(cx, cy, r0)


## Field size (metres, multiples of 4) a city needs around it, given the
## attackers' deployment depth and frontage (metres).
static func city_field(c: Dictionary, att_width_m: int, att_depth_m: int) -> Vector2i:
	var p := city_params(c)
	var r0: int = R_LEVEL[int(p["level"])]
	var rmax := r0 * 112 / 100
	var w := maxi(2 * rmax + 2 * 150, att_width_m + 160)
	var cy := CITY_TOP + rmax
	var h := cy + rmax + WALL_T[int(p["walls"])] / 2 + APPROACH + att_depth_m + 40
	w = (w + 3) / 4 * 4
	h = (h + 3) / 4 * 4
	return Vector2i(w, h)


# ------------------------------------------------------------- build ------

## Every feature of a battle map. `hgt` is sim/terrain.gd's build() result
## for the same map (in the canonical frame for a city: this turns its
## heights round with everything else when the defenders are side 0).
static func build(terr: Dictionary, battle_seed: int, w_m: int, h_m: int, hgt: Dictionary) -> Dictionary:
	var vw := (w_m + 3) / 4
	var vh := (h_m + 3) / 4
	var veg := PackedByteArray()
	veg.resize(vw * vh)
	veg.fill(0)
	var out := {"veg_on": 0, "obs_on": 0, "city_on": 0, "vw": vw, "vh": vh, "veg": veg,
		"ow": 0, "oh": 0, "obs": PackedByteArray(), "palette": int(terr.get("ground", PAL_PLAIN)),
		"forest": int(terr.get("forest", 0))}
	var dens := clampi(int(terr.get("forest", 0)), 0, 100)
	var woods: Array = terr.get("woods", [])
	var blocks: Array = terr.get("blocks", [])
	var has_city: bool = terr.has("city") and terr["city"] is Dictionary
	if dens <= 0 and woods.is_empty() and not has_city and blocks.is_empty():
		return out
	var tseed := int(terr.get("seed", -1))
	if tseed < 0:
		tseed = battle_seed
	var key := "%s|%d|%d|%d|%d" % [str(terr), tseed, w_m, h_m, int(hgt.get("on", 0))]
	if key == _cache_key and not _cache.is_empty():
		var hit := _cache.duplicate()
		hit["veg"] = (_cache["veg"] as PackedByteArray).duplicate()
		hit["obs"] = (_cache["obs"] as PackedByteArray).duplicate()
		if _cache.has("h_flipped"):
			hgt["h"] = (_cache["h_flipped"] as PackedInt32Array).duplicate()
		return hit
	var excl: Array = []  # rectangles [x0, y0, x1, y1] (m) kept free of woods
	var city := {}
	if has_city:
		city = _city(city_params(terr["city"]), w_m, h_m, out, excl)
	else:
		# Field battle: the centre of both deployment zones stays clear.
		excl.append([w_m * 15 / 100, h_m / 2 + 72, w_m * 85 / 100, h_m / 2 + 190])
		excl.append([w_m * 15 / 100, h_m / 2 - 190, w_m * 85 / 100, h_m / 2 - 72])
	if dens > 0:
		var ox := 0
		var oy := 0
		var bw := w_m
		var bh := h_m
		if has_city:
			# Woods placed relative to the city, so they do not move with the
			# field size.
			ox = int(city["cx"]) - 300
			oy = int(city["cy"]) - 260
			bw = 600
			bh = 640
		_forest(veg, vw, vh, dens, tseed * 31 + 7, hgt, ox, oy, bw, bh, excl, int(terr.get("sym", 0)))
	for wd in woods:
		var a: Array = wd
		_veg_rect(veg, vw, vh, int(a[0]) - int(a[2]), int(a[1]) - int(a[3]), int(a[0]) + int(a[2]),
			int(a[1]) + int(a[3]), clampi(int(a[4]), 0, 3))
	if not has_city and not blocks.is_empty():
		var ow := w_m / 2
		var oh := h_m / 2
		var obs := PackedByteArray()
		obs.resize(ow * oh)
		obs.fill(C_OPEN)
		for b in blocks:
			var a: Array = b
			_set_rect(obs, ow, oh, a[0], a[1], a[2], a[3], C_BUILDING)
		for ur in terr.get("urban", []):
			var a2: Array = ur
			for j in range(maxi(int(a2[1]) / 4, 0), mini(int(a2[3]) / 4 + 1, vh)):
				for i in range(maxi(int(a2[0]) / 4, 0), mini(int(a2[2]) / 4 + 1, vw)):
					veg[j * vw + i] |= V_URBAN
		out["obs"] = obs
		out["ow"] = ow
		out["oh"] = oh
		out["obs_on"] = 1
	for k in veg.size():
		if (veg[k] & V_DENS) != 0:
			out["veg_on"] = 1
			break
	if has_city and int(city["def"]) == 0:
		_flip_all(out, hgt, w_m, h_m)
	_cache_key = key
	_cache = out.duplicate()
	_cache["veg"] = (out["veg"] as PackedByteArray).duplicate()
	_cache["obs"] = (out["obs"] as PackedByteArray).duplicate()
	if has_city and int(city["def"]) == 0:
		_cache["h_flipped"] = (hgt["h"] as PackedInt32Array).duplicate()
	return out


## Set every 4 m cell whose centre lies in [x0, x1) x [y0, y1) (m) to tree
## density d (keeping the other bits).
static func _veg_rect(veg: PackedByteArray, vw: int, vh: int, x0: int, y0: int, x1: int, y1: int,
		d: int) -> void:
	for j in range(maxi((y0 - 2 + 3) / 4, 0), mini((y1 - 2 + 3) / 4, vh)):
		for i in range(maxi((x0 - 2 + 3) / 4, 0), mini((x1 - 2 + 3) / 4, vw)):
			var k := j * vw + i
			veg[k] = (veg[k] & ~V_DENS) | d


# ------------------------------------------------------------- woods ------

## Woods: smooth integer blobs (big ones for the woods, small ones to break
## up their edges), a height term so the edges follow the contours, then
## thresholds that give `dens`% x 0.55 of the map as trees (a quarter of
## that dense, half medium or denser). Blob positions are drawn in the box
## (ox, oy, bw, bh) metres.
static func _forest(veg: PackedByteArray, vw: int, vh: int, dens: int, seed_v: int, hgt: Dictionary,
		ox: int, oy: int, bw: int, bh: int, excl: Array, sym: int) -> void:
	var rng := _rng(seed_v)
	var f := PackedInt32Array()
	f.resize(vw * vh)
	f.fill(0)
	var nb := 4 + dens / 10 + _r(rng, 3)
	for b in nb:
		var bx := ox + _r(rng, bw)
		var by := oy + _r(rng, bh)
		var rad := (28 + _r(rng, 50)) * (70 + dens) / 100
		_blob(f, vw, vh, bx, by, rad, 1000)
	var ns := 14 + dens / 3
	for b in ns:
		var bx := ox + _r(rng, bw)
		var by := oy + _r(rng, bh)
		var amp := 420 if _r(rng, 2) == 0 else -420
		_blob(f, vw, vh, bx, by, 8 + _r(rng, 14), amp)
	if int(hgt.get("on", 0)) != 0:
		var h: PackedInt32Array = hgt["h"]
		var nx := int(hgt["nx"])
		var mean := 0
		for v in h:
			mean += v
		mean /= maxi(h.size(), 1)
		for j in vh:
			for i in vw:
				var hv := h[mini(j, int(hgt["ny"]) - 1) * nx + mini(i, nx - 1)]
				f[j * vw + i] += clampi((hv - mean) * 40 / M, -500, 500)
	# Thresholds from the histogram: coverage cov% of the cells.
	var cov := dens * 55 / 100
	var hist := PackedInt32Array()
	hist.resize(2048)
	hist.fill(0)
	for v in f:
		hist[clampi(v + 1024, 0, 2047)] += 1
	var t1 := _quantile(hist, f.size() * cov / 100)
	var t2 := _quantile(hist, f.size() * cov * 55 / 10000)
	var t3 := _quantile(hist, f.size() * cov * 25 / 10000)
	for k in f.size():
		var b := clampi(f[k] + 1024, 0, 2047)
		var d := 0
		if b >= t3:
			d = 3
		elif b >= t2:
			d = 2
		elif b >= t1:
			d = 1
		if d > 0:
			veg[k] = (veg[k] & ~V_DENS) | d
	for e in excl:
		var a: Array = e
		_veg_rect(veg, vw, vh, int(a[0]), int(a[1]), int(a[2]), int(a[3]), 0)
	if sym != 0:
		var last := veg.size() - 1
		for k in (veg.size() + 1) / 2:
			var d0 := mini(veg[k] & V_DENS, veg[last - k] & V_DENS)
			veg[k] = (veg[k] & ~V_DENS) | d0
			veg[last - k] = (veg[last - k] & ~V_DENS) | d0


## Lowest histogram bin b such that at most `want` cells lie at or above b
## (2048 = none).
static func _quantile(hist: PackedInt32Array, want: int) -> int:
	if want <= 0:
		return 2048
	var acc := 0
	var b := 2047
	while b >= 0:
		if acc + hist[b] > want:
			return b + 1
		acc += hist[b]
		b -= 1
	return 0


## Add amp x (1 - d^2/r^2)^2 to the 4 m cells within r metres of (x, y).
static func _blob(f: PackedInt32Array, vw: int, vh: int, x: int, y: int, r: int, amp: int) -> void:
	var r2 := r * r * 16  # quarter-metre units: cell centres are at 4i + 2
	for j in range(maxi((y - r) / 4, 0), mini((y + r) / 4 + 1, vh)):
		var dy := (j * 4 + 2 - y) * 4
		if dy * dy >= r2:
			continue
		for i in range(maxi((x - r) / 4, 0), mini((x + r) / 4 + 1, vw)):
			var dx := (i * 4 + 2 - x) * 4
			var d2 := dx * dx + dy * dy
			if d2 >= r2:
				continue
			var u := 1024 - d2 * 1024 / r2
			f[j * vw + i] += amp * (u * u >> 10) / 1024


# -------------------------------------------------------------- city ------

## Generate the city (canonical frame) into `out` and append the areas kept
## free of woods to `excl`. Returns the layout (metres).
static func _city(p: Dictionary, w_m: int, h_m: int, out: Dictionary, excl: Array) -> Dictionary:
	var level: int = p["level"]
	var walls: int = p["walls"]
	var rng := _rng(int(p["seed"]))
	var fr := city_frame(p, w_m, h_m)
	var cx := fr.x
	var cy := fr.y
	var r0 := fr.z
	var ow := w_m / 2
	var oh := h_m / 2
	var obs := PackedByteArray()
	obs.resize(ow * oh)
	obs.fill(C_OPEN)
	# Masks over the obstacle grid: inside the footprint, kept open (streets,
	# plaza, ring road, gate squares), occupied by a landmark.
	var inside := PackedByteArray()
	inside.resize(ow * oh)
	inside.fill(0)
	var keep := PackedByteArray()
	keep.resize(ow * oh)
	keep.fill(0)
	# Footprint polygon: the same angles and radius factors for every level
	# (from the seed), scaled by the level's radius.
	var nv := 7 + _r(rng, 4)
	var vx := PackedInt32Array()
	var vy := PackedInt32Array()
	for k in nv:
		var ang := (k * 1024 / nv + _rr(rng, -22, 22)) & 1023
		var rad := r0 * _rr(rng, 90, 112) / 100
		vx.append(cx + FM.cos_a(ang) * rad / FM.TRIG_ONE)
		vy.append(cy + FM.sin_a(ang) * rad / FM.TRIG_ONE)
	# Random numbers drawn in a fixed order whatever the level and walls.
	var plaza_jx := _rr(rng, -8, 8)
	var plaza_jy := _rr(rng, -6, 6)
	var gate_jit: Array = []
	for k in 4:
		gate_jit.append(_rr(rng, -100, 100))
	_fill_poly(inside, ow, oh, vx, vy)
	var t: int = WALL_T[walls]
	var pp: int = WALL_P[walls]
	var inner := t - pp - WALK_W
	var wall_h: int = WALL_H[walls]
	var tow_r := t / 2 + 2              # vertex tower radius
	var trg := t / 2 + 1             # gate tower radius
	var px := cx + plaza_jx
	var py := cy + plaza_jy
	var hs: int = PLAZA_HS[level]
	# Edge outward normals (Q12) and lengths.
	var en_x := PackedInt32Array()
	var en_y := PackedInt32Array()
	var ee_x := PackedInt32Array()
	var ee_y := PackedInt32Array()
	var elen := PackedInt32Array()
	for k in nv:
		var ax := vx[k]
		var ay := vy[k]
		var bx := vx[(k + 1) % nv]
		var by := vy[(k + 1) % nv]
		var l := maxi(FM.isqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)), 1)
		var ex := (bx - ax) * FM.TRIG_ONE / l
		var ey := (by - ay) * FM.TRIG_ONE / l
		var nx := -ey
		var ny := ex
		if nx * ((ax + bx) / 2 - cx) + ny * ((ay + by) / 2 - cy) < 0:
			nx = -nx
			ny = -ny
		en_x.append(nx)
		en_y.append(ny)
		ee_x.append(ex)
		ee_y.append(ey)
		elen.append(l)
	# Gates: the edge facing the attackers (down) first, then left, right, up.
	var gates: Array = []
	if walls > 0:
		var ngates := clampi(5 - walls, 2, 2 + level)
		var prefs: Array = [256, 768] if ngates == 2 else ([256, 512, 0] if ngates == 3 else [256, 512, 0, 768])
		var used := {}
		for gi in prefs.size():
			var want: int = prefs[gi]
			var best := -1
			var best_d := 0
			for k in nv:
				if used.has(k) or elen[k] < 2 * (GATE_HW + 2 * trg) + 6:
					continue
				var na := FM.atan2_a(en_y[k], en_x[k])
				var d := absi(FM.angle_diff(na, want))
				# Spread the gates: not next to one already chosen if possible.
				if used.has((k + 1) % nv) or used.has((k + nv - 1) % nv):
					d += 200
				if best < 0 or d < best_d:
					best = k
					best_d = d
			if best < 0:
				continue
			used[best] = true
			var l := elen[best]
			var room := l / 2 - GATE_HW - 2 * trg - 3
			var along := l / 2 + clampi(int(gate_jit[gi]) * l / 1600, -maxi(room, 0), maxi(room, 0))
			var gx := vx[best] + ee_x[best] * along / FM.TRIG_ONE
			var gy := vy[best] + ee_y[best] * along / FM.TRIG_ONE
			gates.append({"edge": best, "along": along, "x": gx, "y": gy,
				"dir": FM.atan2_a(en_y[best], en_x[best]),
				"ox": gx + en_x[best] * (t / 2 + 10) / FM.TRIG_ONE, "oy": gy + en_y[best] * (t / 2 + 10) / FM.TRIG_ONE,
				"ix": gx - en_x[best] * (t / 2 + 4) / FM.TRIG_ONE, "iy": gy - en_y[best] * (t / 2 + 4) / FM.TRIG_ONE})
	# Wall band, ring road (distance from the wall line, inside / outside).
	var towers: Array = []
	if walls > 0:
		var margin := t / 2 + RING_W + 2
		var wd := PackedInt32Array()  # min distance (cm) to the wall line, cells near it
		wd.resize(ow * oh)
		wd.fill(1 << 30)
		for k in nv:
			var ax := vx[k]
			var ay := vy[k]
			var bx := vx[(k + 1) % nv]
			var by := vy[(k + 1) % nv]
			for j in range(maxi((mini(ay, by) - margin) / 2, 0), mini((maxi(ay, by) + margin) / 2 + 1, oh)):
				for i in range(maxi((mini(ax, bx) - margin) / 2, 0), mini((maxi(ax, bx) + margin) / 2 + 1, ow)):
					var d := _seg_dist_cm(i * 200 + 100, j * 200 + 100, ax * 100, ay * 100, bx * 100, by * 100)
					var c := j * ow + i
					if d < wd[c]:
						wd[c] = d
		var half := t * 50
		for c in ow * oh:
			var d := wd[c]
			if d > (t / 2 + RING_W) * 100:
				continue
			if d <= half:
				if inside[c] == 0:
					obs[c] = C_WALL if d > (t / 2 - pp) * 100 else C_WALK
				else:
					obs[c] = C_WALL if d > (t / 2 - inner) * 100 else C_WALK
			elif inside[c] != 0:
				keep[c] = 1  # ring road
		for k in nv:
			_disc(obs, ow, oh, vx[k], vy[k], tow_r, C_TOWER)
			towers.append([vx[k], vy[k], tow_r])
		for g in gates.size():
			var gd: Dictionary = gates[g]
			var e: int = gd["edge"]
			for s in [-1, 1]:
				var tx: int = int(gd["x"]) + s * ee_x[e] * (GATE_HW + trg) / FM.TRIG_ONE
				var ty: int = int(gd["y"]) + s * ee_y[e] * (GATE_HW + trg) / FM.TRIG_ONE
				_disc(obs, ow, oh, tx, ty, trg, C_TOWER)
				towers.append([tx, ty, trg])
			# Gate cells: across the whole wall band within the opening.
			var gx: int = gd["x"]
			var gy: int = gd["y"]
			for j in range(maxi((gy - t - GATE_HW) / 2, 0), mini((gy + t + GATE_HW) / 2 + 1, oh)):
				for i in range(maxi((gx - t - GATE_HW) / 2, 0), mini((gx + t + GATE_HW) / 2 + 1, ow)):
					var rx := (i * 200 + 100) - gx * 100
					var ry := (j * 200 + 100) - gy * 100
					var al := (rx * ee_x[e] + ry * ee_y[e]) / FM.TRIG_ONE
					var pe := (rx * en_x[e] + ry * en_y[e]) / FM.TRIG_ONE
					if absi(al) <= GATE_HW * 100 and absi(pe) <= half + 60:
						obs[j * ow + i] = C_GATE + g
			# Squares kept open either side of the gate.
			_keep_disc(keep, ow, oh, int(gd["ix"]), int(gd["iy"]), 7)
	# Plaza and main streets.
	var streets: Array = []
	var msw: int = [3, 4, 4][level]
	if walls > 0:
		for gd in gates:
			streets.append([int(gd["ix"]), int(gd["iy"]), px, py, msw])
	else:
		var dirs: Array = [256, 512, 0, 768]
		for k in (3 if level == 0 else 4):
			var a: int = dirs[k]
			var l := r0 * 135 / 100
			streets.append([px, py, cx + FM.cos_a(a) * l / FM.TRIG_ONE, cy + FM.sin_a(a) * l / FM.TRIG_ONE, msw])
	for s in streets:
		_keep_seg(keep, ow, oh, s[0], s[1], s[2], s[3], s[4])
	_keep_rect(keep, ow, oh, px - hs, py - hs, px + hs, py + hs)
	# Landmarks (bigger buildings) by the plaza and the main gate.
	var occ := PackedByteArray()
	occ.resize(ow * oh)
	occ.fill(0)
	var buildings: Array = []
	var bset := {}
	for b in p["bld"]:
		bset[int(b)] = true
	var lm: Array = []
	if level >= 1:
		var tw := 16 if level == 1 else 20
		lm.append([B_TEMPLE, px - tw / 2, py - hs - 4 - tw * 13 / 10, px + tw / 2, py - hs - 4])
	if bset.has(1) and level >= 1:  # market: a long stoa on the plaza's left side
		lm.append([B_MARKET, px - hs - 12, py - hs, px - hs - 4, py + hs])
	if bset.has(3) and level >= 1:
		lm.append([B_RANGE, px + hs + 4, py - hs, px + hs + 14, py])
	if bset.has(5) and level >= 1:
		lm.append([B_WORKSHOP, px + hs + 4, py + 4, px + hs + 16, py + hs])
	var mg: Dictionary = gates[0] if not gates.is_empty() else {"ix": cx, "iy": cy + r0 * 3 / 4}
	if bset.has(2):
		lm.append([B_BARRACKS, int(mg["ix"]) + msw + 4, int(mg["iy"]) - 34, int(mg["ix"]) + msw + 16, int(mg["iy"]) - 10])
	if bset.has(4):
		lm.append([B_STABLES, int(mg["ix"]) - msw - 18, int(mg["iy"]) - 32, int(mg["ix"]) - msw - 4, int(mg["iy"]) - 12])
	for b in lm:
		var a: Array = b
		if _rect_free(inside, keep, occ, ow, oh, a[1], a[2], a[3], a[4]):
			_mark_rect(occ, ow, oh, a[1], a[2], a[3], a[4])
			buildings.append([a[1], a[2], a[3], a[4], a[0]])
	# Houses on a jittered block grid (fixed by the seed over the largest
	# footprint, so a town grows into the same city).
	var cols := PackedInt32Array()  # block x0, x1 pairs
	var x := cx - EXT
	var street_xs := PackedInt32Array()
	while x < cx + EXT:
		var bwid := 2 * _rr(rng, 8, 14)
		cols.append(x)
		cols.append(x + bwid)
		var sw := 4 if _r(rng, 3) > 0 else 6
		street_xs.append(x + bwid + sw / 2)
		x += bwid + sw
	var rows := PackedInt32Array()
	var y := cy - EXT
	var street_ys := PackedInt32Array()
	while y < cy + EXT:
		var bh2 := 2 * _rr(rng, 8, 13)
		rows.append(y)
		rows.append(y + bh2)
		var sw2 := 4 if _r(rng, 3) > 0 else 6
		street_ys.append(y + bh2 + sw2 / 2)
		y += bh2 + sw2
	var inset := 1
	for rj in rows.size() / 2:
		for ci in cols.size() / 2:
			var bx0 := cols[ci * 2]
			var bx1 := cols[ci * 2 + 1]
			var by0 := rows[rj * 2]
			var by1 := rows[rj * 2 + 1]
			# Lots of about 10 m; a house fills its lot less a metre all
			# round (2 m alleys), villages smaller houses with yards.
			var nxl := maxi((bx1 - bx0 + 3) / 10, 1)
			var nyl := maxi((by1 - by0 + 3) / 10, 1)
			for ly in nyl:
				for lx in nxl:
					var roll := _r(rng, 100)
					var jx := _r(rng, 3)
					var jy := _r(rng, 3)
					var lx0 := bx0 + (bx1 - bx0) * lx / nxl
					var lx1 := bx0 + (bx1 - bx0) * (lx + 1) / nxl
					var ly0 := by0 + (by1 - by0) * ly / nyl
					var ly1 := by0 + (by1 - by0) * (ly + 1) / nyl
					if roll >= int(BUILT_PCT[level]):
						continue
					var hx0 := lx0 + inset + (jx if level == 0 else jx / 2)
					var hy0 := ly0 + inset + (0 if level > 0 else jy / 2)
					var hx1 := lx1 - inset
					var hy1 := ly1 - inset - (jy if level == 0 else jy / 2)
					if hx1 - hx0 < 4 or hy1 - hy0 < 4:
						continue
					if _rect_free(inside, keep, occ, ow, oh, hx0, hy0, hx1, hy1):
						_mark_rect(occ, ow, oh, hx0, hy0, hx1, hy1)
						buildings.append([hx0, hy0, hx1, hy1, B_HOUSE])
	for b in buildings:
		var a: Array = b
		_set_rect(obs, ow, oh, a[0], a[1], a[2], a[3], C_BUILDING)
	# Vegetation bits: urban, roads, plaza (4 m cells sample their centre).
	var veg: PackedByteArray = out["veg"]
	var vw: int = out["vw"]
	var vh: int = out["vh"]
	for j in vh:
		for i in vw:
			var oc := mini(j * 2 + 1, oh - 1) * ow + mini(i * 2 + 1, ow - 1)
			if inside[oc] != 0:
				veg[j * vw + i] |= V_URBAN
	for s in streets:
		_veg_seg(veg, vw, vh, s[0], s[1], s[2], s[3], s[4], V_ROAD)
	for j in range(maxi((py - hs) / 4, 0), mini((py + hs) / 4 + 1, vh)):
		for i in range(maxi((px - hs) / 4, 0), mini((px + hs) / 4 + 1, vw)):
			veg[j * vw + i] |= V_PLAZA
	# Wall walkway segments between towers and gates.
	var segs: Array = []
	if walls > 0:
		var off := (inner - pp) / 2  # walkway centre, outward of the wall line
		for k in nv:
			var cut: Array = [[0, tow_r + 1], [elen[k] - tow_r - 1, elen[k]]]
			for gd in gates:
				if int(gd["edge"]) == k:
					var ga: int = gd["along"]
					cut.append([ga - GATE_HW - 2 * trg - 1, ga + GATE_HW + 2 * trg + 1])
			cut.sort_custom(func(a, b): return a[0] < b[0])
			var s0 := 0
			for c in cut:
				if int(c[0]) - s0 >= 12:
					segs.append([vx[k] + (ee_x[k] * s0 + en_x[k] * off) / FM.TRIG_ONE,
						vy[k] + (ee_y[k] * s0 + en_y[k] * off) / FM.TRIG_ONE,
						vx[k] + (ee_x[k] * int(c[0]) + en_x[k] * off) / FM.TRIG_ONE,
						vy[k] + (ee_y[k] * int(c[0]) + en_y[k] * off) / FM.TRIG_ONE,
						FM.atan2_a(en_y[k], en_x[k])])
				s0 = maxi(s0, int(c[1]))
	# Outside: orchards and fields at low levels, cleared ground near high
	# walls, the approach and the attackers' deployment free of trees.
	var rmax := r0 * 112 / 100
	var gate_y := (int(mg["y"]) + t / 2) if walls > 0 else cy + rmax
	var att_y := gate_y + APPROACH
	var att_x: int = int(mg["x"]) if walls > 0 else cx
	var fields: Array = []
	var nf := 4 + _r(rng, 4)
	for k in 8:
		var a := _r(rng, 1024)
		var dist := rmax + 35 + _r(rng, 90)
		var fw := 2 * _rr(rng, 10, 20)
		var fh := 2 * _rr(rng, 8, 16)
		var kind := 1 + _r(rng, 2)
		if k >= nf or level == 2 or walls >= 2:
			continue
		var fx := cx + FM.cos_a(a) * dist / FM.TRIG_ONE
		var fy := cy + FM.sin_a(a) * dist / FM.TRIG_ONE
		if (absi(fx - att_x) < 50 + fw / 2 and fy > cy) or fy + fh / 2 > att_y - 30:
			continue
		if fx - fw / 2 < 4 or fy - fh / 2 < 4 or fx + fw / 2 > w_m - 4:
			continue
		fields.append([fx - fw / 2, fy - fh / 2, fx + fw / 2, fy + fh / 2, kind])
	excl.append([cx - rmax - 25, cy - rmax - 25, cx + rmax + 25, cy + rmax + 25])
	if walls >= 2:
		excl.append([cx - rmax - 60, cy - rmax - 60, cx + rmax + 60, cy + rmax + 60])
	excl.append([att_x - 40, cy, att_x + 40, att_y + 120])
	excl.append([w_m * 10 / 100, att_y - 20, w_m * 90 / 100, h_m])
	var nav_nodes := _nav_graph(obs, ow, oh, w_m, h_m, vx, vy, en_x, en_y, ee_x, ee_y, elen, gates,
		cx, cy, r0, t, tow_r, px, py, hs, streets, street_xs, street_ys, inside, walls)
	out["obs"] = obs
	out["ow"] = ow
	out["oh"] = oh
	out["obs_on"] = 1
	out["city_on"] = 1
	var poly := PackedInt32Array()
	for k in nv:
		poly.append(vx[k])
		poly.append(vy[k])
	var lay := {"cx": cx, "cy": cy, "r0": r0, "level": level, "walls": walls, "def": int(p["def"]),
		"seed": int(p["seed"]), "t": t, "pp": pp, "inner": inner, "wall_h_m": wall_h,
		"build_h_m": BUILD_H[level], "poly": poly, "gates": gates, "towers": towers,
		"plaza": [px, py, hs, hs + CAPTURE_EXTRA], "streets": streets, "buildings": buildings,
		"fields": fields, "segs": segs, "att_x": att_x, "att_y": att_y, "nav": nav_nodes,
		"gate_hp": GATE_HP[walls]}
	out["city"] = lay
	# Orchards are trees; fields are a view bit.
	for f in fields:
		var a: Array = f
		if int(a[4]) == 1:
			_veg_rect(veg, vw, vh, a[0], a[1], a[2], a[3], 1)
		else:
			for j in range(maxi(int(a[1]) / 4, 0), mini(int(a[3]) / 4 + 1, vh)):
				for i in range(maxi(int(a[0]) / 4, 0), mini(int(a[2]) / 4 + 1, vw)):
					veg[j * vw + i] |= V_FIELD
	return lay


## Distance (cm) from point (px, py) to segment a-b (all cm).
static func _seg_dist_cm(px: int, py: int, ax: int, ay: int, bx: int, by: int) -> int:
	var dx := bx - ax
	var dy := by - ay
	var rx := px - ax
	var ry := py - ay
	var den := dx * dx + dy * dy
	var num := rx * dx + ry * dy
	if den <= 0 or num <= 0:
		return FM.isqrt(rx * rx + ry * ry)
	if num >= den:
		var qx := px - bx
		var qy := py - by
		return FM.isqrt(qx * qx + qy * qy)
	var cr := absi(rx * dy - ry * dx)
	return cr / maxi(FM.isqrt(den), 1)


## Scanline fill: cells whose centre is inside the polygon get 1.
static func _fill_poly(mask: PackedByteArray, ow: int, oh: int, vx: PackedInt32Array, vy: PackedInt32Array) -> void:
	var nv := vx.size()
	for j in oh:
		var yc := j * 200 + 100  # cm
		var xs: Array[int] = []
		for k in nv:
			var ay := vy[k] * 100
			var by := vy[(k + 1) % nv] * 100
			if ay == by:
				continue
			if (yc >= ay and yc < by) or (yc >= by and yc < ay):
				var ax := vx[k] * 100
				var bx := vx[(k + 1) % nv] * 100
				xs.append(ax + (yc - ay) * (bx - ax) / (by - ay))
		if xs.size() < 2:
			continue
		xs.sort()
		var q := 0
		while q + 1 < xs.size():
			var i0 := maxi((xs[q] - 100 + 199) / 200, 0)
			var i1 := mini((xs[q + 1] - 100) / 200, ow - 1)
			for i in range(i0, i1 + 1):
				mask[j * ow + i] = 1
			q += 2


static func _disc(g: PackedByteArray, ow: int, oh: int, x: int, y: int, r: int, v: int) -> void:
	var r2 := r * r * 10000
	for j in range(maxi((y - r) / 2, 0), mini((y + r) / 2 + 1, oh)):
		for i in range(maxi((x - r) / 2, 0), mini((x + r) / 2 + 1, ow)):
			var dx := i * 200 + 100 - x * 100
			var dy := j * 200 + 100 - y * 100
			if dx * dx + dy * dy <= r2:
				g[j * ow + i] = v


static func _keep_disc(g: PackedByteArray, ow: int, oh: int, x: int, y: int, r: int) -> void:
	_disc(g, ow, oh, x, y, r, 1)


static func _keep_rect(g: PackedByteArray, ow: int, oh: int, x0: int, y0: int, x1: int, y1: int) -> void:
	_set_rect(g, ow, oh, x0, y0, x1, y1, 1)


## Cells whose centre lies in [x0, x1) x [y0, y1) (metres) get v.
static func _set_rect(g: PackedByteArray, ow: int, oh: int, x0: int, y0: int, x1: int, y1: int, v: int) -> void:
	for j in range(maxi(y0 / 2, 0), mini((y1 + 1) / 2, oh)):
		for i in range(maxi(x0 / 2, 0), mini((x1 + 1) / 2, ow)):
			var xc := i * 2 + 1
			var yc := j * 2 + 1
			if xc >= x0 and xc < x1 and yc >= y0 and yc < y1:
				g[j * ow + i] = v


static func _mark_rect(g: PackedByteArray, ow: int, oh: int, x0: int, y0: int, x1: int, y1: int) -> void:
	_set_rect(g, ow, oh, x0, y0, x1, y1, 1)


## Every cell of the rectangle is inside the footprint, not kept open and
## not already built on.
static func _rect_free(inside: PackedByteArray, keep: PackedByteArray, occ: PackedByteArray, ow: int,
		oh: int, x0: int, y0: int, x1: int, y1: int) -> bool:
	if x0 < 0 or y0 < 0 or x1 > ow * 2 or y1 > oh * 2:
		return false
	for j in range(y0 / 2, (y1 + 1) / 2):
		for i in range(x0 / 2, (x1 + 1) / 2):
			var c := j * ow + i
			if inside[c] == 0 or keep[c] != 0 or occ[c] != 0:
				return false
	return true


## Cells within hw metres of segment a-b get 1.
static func _keep_seg(g: PackedByteArray, ow: int, oh: int, ax: int, ay: int, bx: int, by: int, hw: int) -> void:
	for j in range(maxi((mini(ay, by) - hw) / 2, 0), mini((maxi(ay, by) + hw) / 2 + 1, oh)):
		for i in range(maxi((mini(ax, bx) - hw) / 2, 0), mini((maxi(ax, bx) + hw) / 2 + 1, ow)):
			if _seg_dist_cm(i * 200 + 100, j * 200 + 100, ax * 100, ay * 100, bx * 100, by * 100) <= hw * 100:
				g[j * ow + i] = 1


static func _veg_seg(veg: PackedByteArray, vw: int, vh: int, ax: int, ay: int, bx: int, by: int, hw: int,
		bit: int) -> void:
	for j in range(maxi((mini(ay, by) - hw) / 4, 0), mini((maxi(ay, by) + hw) / 4 + 1, vh)):
		for i in range(maxi((mini(ax, bx) - hw) / 4, 0), mini((maxi(ax, bx) + hw) / 4 + 1, vw)):
			if _seg_dist_cm(i * 400 + 200, j * 400 + 200, ax * 100, ay * 100, bx * 100, by * 100) <= hw * 100 + 100:
				veg[j * vw + i] |= bit


# ------------------------------------------------------------ nav graph ----

## Waypoint graph for unit paths: gates (outside, gate, inside), a ring of
## points outside the walls, the ring road inside, the plaza, points along
## the main streets and the street grid's crossings. Edges join nodes up to
## EDGE_MAX apart with a clear line 3 m wide (a gate's cells only for edges
## to that gate's own node, so a closed gate cuts exactly its node).
## Returns {"x", "y", "gate", "e0", "to", "w"} (metres, CSR adjacency).
static func _nav_graph(obs: PackedByteArray, ow: int, oh: int, w_m: int, h_m: int,
		vx: PackedInt32Array, vy: PackedInt32Array, en_x: PackedInt32Array, en_y: PackedInt32Array,
		ee_x: PackedInt32Array, ee_y: PackedInt32Array, elen: PackedInt32Array, gates: Array,
		cx: int, cy: int, r0: int, t: int, tow_r: int, px: int, py: int, hs: int, streets: Array,
		sxs: PackedInt32Array, sys: PackedInt32Array, inside: PackedByteArray, walls: int) -> Dictionary:
	var nx := PackedInt32Array()
	var ny := PackedInt32Array()
	var ng := PackedInt32Array()
	var add := func(x: int, y: int, g: int) -> void:
		if x < 4 or y < 4 or x > w_m - 4 or y > h_m - 4:
			return
		var c := mini(y / 2, oh - 1) * ow + mini(x / 2, ow - 1)
		var k := obs[c]
		if g < 0 and k != C_OPEN:
			return
		for q in nx.size():
			if absi(nx[q] - x) < 4 and absi(ny[q] - y) < 4:
				return
		nx.append(x)
		ny.append(y)
		ng.append(g)
	for g in gates.size():
		var gd: Dictionary = gates[g]
		add.call(int(gd["ox"]), int(gd["oy"]), -1)
		add.call(int(gd["x"]), int(gd["y"]), g)
		add.call(int(gd["ix"]), int(gd["iy"]), -1)
	var nv := vx.size()
	if walls > 0:
		for k in nv:
			# Outside: round the tower at the vertex and along the edge (ends
			# included, clear of the towers); inside: the ring road.
			var rx := vx[k] - cx
			var ry := vy[k] - cy
			var rl := maxi(FM.isqrt(rx * rx + ry * ry), 1)
			var out_d := t / 2 + tow_r + 7
			add.call(vx[k] + rx * out_d / rl, vy[k] + ry * out_d / rl, -1)
			var in_d := t / 2 + RING_W / 2 + 3
			add.call(vx[k] - rx * in_d / rl, vy[k] - ry * in_d / rl, -1)
			var steps := maxi((elen[k] + 19) / 20, 1)
			for s in range(0, steps + 1):
				var al := elen[k] * s / steps
				var bx := vx[k] + ee_x[k] * al / FM.TRIG_ONE
				var by := vy[k] + ee_y[k] * al / FM.TRIG_ONE
				add.call(bx + en_x[k] * (t / 2 + tow_r + 5) / FM.TRIG_ONE, by + en_y[k] * (t / 2 + tow_r + 5) / FM.TRIG_ONE, -1)
				if s > 0 and s < steps:
					add.call(bx - en_x[k] * (t / 2 + RING_W / 2) / FM.TRIG_ONE,
						by - en_y[k] * (t / 2 + RING_W / 2) / FM.TRIG_ONE, -1)
	else:
		var rr := r0 * 128 / 100
		var n_out := maxi(rr * 6 / NODE_STEP, 8)
		for s in n_out:
			var a := s * 1024 / n_out
			add.call(cx + FM.cos_a(a) * rr / FM.TRIG_ONE, cy + FM.sin_a(a) * rr / FM.TRIG_ONE, -1)
	add.call(px, py, -1)
	for c in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		add.call(px + c.x * (hs - 3), py + c.y * (hs - 3), -1)
	for s in streets:
		var a: Array = s
		var l := FM.isqrt((int(a[2]) - int(a[0])) * (int(a[2]) - int(a[0])) + (int(a[3]) - int(a[1])) * (int(a[3]) - int(a[1])))
		var steps := maxi(l / 25, 1)
		for q in range(0, steps + 1):
			add.call(int(a[0]) + (int(a[2]) - int(a[0])) * q / steps, int(a[1]) + (int(a[3]) - int(a[1])) * q / steps, -1)
	for sy in sys:
		for sx in sxs:
			var c := mini(sy / 2, oh - 1) * ow + mini(sx / 2, ow - 1)
			if sx < 0 or sy < 0 or sx >= w_m or sy >= h_m:
				continue
			# Street crossings inside the settlement (and just outside it).
			var near_in := inside[c] != 0
			if not near_in:
				var dx := sx - cx
				var dy := sy - cy
				near_in = walls == 0 and dx * dx + dy * dy < r0 * r0 * 3 / 2
			if near_in:
				add.call(sx, sy, -1)
	# Edges.
	var n := nx.size()
	var adj: Array = []
	for a in n:
		adj.append([])
	for a in n:
		for b in range(a + 1, n):
			var dx := nx[b] - nx[a]
			var dy := ny[b] - ny[a]
			if absi(dx) > EDGE_MAX or absi(dy) > EDGE_MAX:
				continue
			var l2 := dx * dx + dy * dy
			if l2 > EDGE_MAX * EDGE_MAX:
				continue
			var allow := ng[a] if ng[a] >= 0 else ng[b]
			if not _clear_fat(obs, ow, oh, nx[a], ny[a], nx[b], ny[b], allow):
				continue
			var w := FM.isqrt(l2 * 64)  # eighths of a metre
			(adj[a] as Array).append([b, w])
			(adj[b] as Array).append([a, w])
	_join_components(obs, ow, oh, nx, ny, ng, adj)
	var e0 := PackedInt32Array()
	var to := PackedInt32Array()
	var ww := PackedInt32Array()
	for a in n:
		e0.append(to.size())
		for e in adj[a]:
			to.append(int(e[0]))
			ww.append(int(e[1]))
	e0.append(to.size())
	return {"x": nx, "y": ny, "gate": ng, "e0": e0, "to": to, "w": ww}


## Join graph pieces: while the graph falls apart, link the piece of node
## 0 to another piece by the shortest clear line between them (of the 24
## shortest candidate pairs), whatever its length.
static func _join_components(obs: PackedByteArray, ow: int, oh: int, nx: PackedInt32Array,
		ny: PackedInt32Array, ng: PackedInt32Array, adj: Array) -> void:
	var n := nx.size()
	for it in 24:
		var comp := PackedInt32Array()
		comp.resize(n)
		comp.fill(-1)
		var stack: Array[int] = [0]
		comp[0] = 0
		var reached := 1
		while not stack.is_empty():
			var v: int = stack.pop_back()
			for e in adj[v]:
				var b: int = e[0]
				if comp[b] < 0:
					comp[b] = 0
					reached += 1
					stack.append(b)
		if reached >= n:
			return
		# Candidate pairs (in, out) by distance.
		var pairs: Array = []
		for a in n:
			if comp[a] != 0:
				continue
			for b in n:
				if comp[b] == 0:
					continue
				var dx := nx[b] - nx[a]
				var dy := ny[b] - ny[a]
				pairs.append([dx * dx + dy * dy, a, b])
		pairs.sort_custom(func(p, q): return p[0] < q[0] or (p[0] == q[0] and (p[1] < q[1] or (p[1] == q[1] and p[2] < q[2]))))
		var joined := false
		for k in mini(pairs.size(), 24):
			var a: int = pairs[k][1]
			var b: int = pairs[k][2]
			var allow := ng[a] if ng[a] >= 0 else ng[b]
			if _clear_fat(obs, ow, oh, nx[a], ny[a], nx[b], ny[b], allow):
				var w := FM.isqrt(int(pairs[k][0]) * 64)
				(adj[a] as Array).append([b, w])
				(adj[b] as Array).append([a, w])
				joined = true
				break
		if not joined:
			return


## A clear line 3 m wide between two points (metres): the centre line and
## lines 1.5 m either side, sampled every metre. Gate cells are blocked
## except those of gate `allow`.
static func _clear_fat(obs: PackedByteArray, ow: int, oh: int, ax: int, ay: int, bx: int, by: int,
		allow: int) -> bool:
	var dx := bx - ax
	var dy := by - ay
	var l := maxi(FM.isqrt(dx * dx + dy * dy), 1)
	var ox := -dy * 150 / l  # 1.5 m across, in cm
	var oy := dx * 150 / l
	for q in l + 1:
		var x := ax * 100 + dx * 100 * q / l
		var y := ay * 100 + dy * 100 * q / l
		for s in 3:
			var sx := x + ox * (s - 1)
			var sy := y + oy * (s - 1)
			if sx < 0 or sy < 0:
				return false
			var i := sx / 200
			var j := sy / 200
			if i >= ow or j >= oh:
				return false
			var k := obs[j * ow + i]
			if k != C_OPEN and k != C_GATE + allow:
				return false
	return true


# --------------------------------------------------------------- flip -----

## Turn the whole map 180 degrees (x -> w - x, y -> h - y): grids reversed,
## coordinates mirrored, directions turned by half a turn.
static func _flip_all(out: Dictionary, hgt: Dictionary, w_m: int, h_m: int) -> void:
	for key in ["veg", "obs"]:
		var g: PackedByteArray = out[key]
		var n := g.size()
		for k in n / 2:
			var a := g[k]
			g[k] = g[n - 1 - k]
			g[n - 1 - k] = a
	if hgt.has("h"):
		var h: PackedInt32Array = hgt["h"]
		var n2 := h.size()
		for k in n2 / 2:
			var a2 := h[k]
			h[k] = h[n2 - 1 - k]
			h[n2 - 1 - k] = a2
	var lay: Dictionary = out["city"]
	var fx := func(x: int) -> int: return w_m - x
	var fy := func(y: int) -> int: return h_m - y
	lay["cx"] = fx.call(int(lay["cx"]))
	lay["cy"] = fy.call(int(lay["cy"]))
	var poly: PackedInt32Array = lay["poly"]
	for k in poly.size() / 2:
		poly[k * 2] = fx.call(poly[k * 2])
		poly[k * 2 + 1] = fy.call(poly[k * 2 + 1])
	for gd in lay["gates"]:
		for kx in ["x", "ox", "ix"]:
			gd[kx] = fx.call(int(gd[kx]))
		for ky in ["y", "oy", "iy"]:
			gd[ky] = fy.call(int(gd[ky]))
		gd["dir"] = (int(gd["dir"]) + 512) & 1023
	for tw in lay["towers"]:
		tw[0] = fx.call(int(tw[0]))
		tw[1] = fy.call(int(tw[1]))
	var pl: Array = lay["plaza"]
	pl[0] = fx.call(int(pl[0]))
	pl[1] = fy.call(int(pl[1]))
	for s in lay["streets"]:
		s[0] = fx.call(int(s[0]))
		s[1] = fy.call(int(s[1]))
		s[2] = fx.call(int(s[2]))
		s[3] = fy.call(int(s[3]))
	for list in [lay["buildings"], lay["fields"]]:
		for b in list:
			var x0: int = b[0]
			var y0: int = b[1]
			b[0] = fx.call(int(b[2]))
			b[1] = fy.call(int(b[3]))
			b[2] = fx.call(x0)
			b[3] = fy.call(y0)
	for s in lay["segs"]:
		s[0] = fx.call(int(s[0]))
		s[1] = fy.call(int(s[1]))
		s[2] = fx.call(int(s[2]))
		s[3] = fy.call(int(s[3]))
		s[4] = (int(s[4]) + 512) & 1023
	lay["att_x"] = fx.call(int(lay["att_x"]))
	lay["att_y"] = fy.call(int(lay["att_y"]))
	var nav: Dictionary = lay["nav"]
	var nxs: PackedInt32Array = nav["x"]
	var nys: PackedInt32Array = nav["y"]
	for k in nxs.size():
		nxs[k] = fx.call(nxs[k])
		nys[k] = fy.call(nys[k])
	nav["x"] = nxs
	nav["y"] = nys
	lay["poly"] = poly
