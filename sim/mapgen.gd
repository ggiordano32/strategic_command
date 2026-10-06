extends RefCounted
## Battle map features beyond height (integers only, own RNG): woods on any
## map, and the settlement of a city map (buildings, walls, towers, gates,
## stairs, streets, plaza, a citadel, a ditch, the sea, orchards and fields,
## a navigation graph for unit paths). Built once at setup from the
## scenario's terrain dictionary, so both lockstep peers build the identical
## map; nothing is transmitted.
##
## Terrain dictionary keys read here (all ints / arrays of ints):
##   kind     terrain kind (sim/terrain.gd K_*): with the city seed it gives
##            the settlement's site (plain, hill, spur)
##   forest   woods coverage 0-100 (region data; 0 = none): blobs of trees
##            whose edges follow the height, never across the deployment
##            zones' centres
##   woods    hand-placed rectangles of trees [x_m, y_m, half_w_m, half_h_m,
##            density 1-3] (tests, set pieces)
##   ground   ground palette (view only; see PALETTES)
##   blocks   hand-placed buildings [x0, y0, x1, y1] (m) on a map without a
##            city (tests, set pieces: streets); the area round them counts
##            as a settlement's streets (V_URBAN) within `urban` rectangles
##   city     settlement: see city_params() (seed, level 0 village / 1 town /
##            2 city, walls 0-3, bld, def, plan, coast and view-only style)
##
## Grids (final frame, row-major, index = row * width + col):
##   veg  4 m cells: bits 0-1 tree density 0-3, V_URBAN inside a settlement,
##        V_FIELD farm field, V_ROAD street, V_PLAZA, V_WATER sea, V_DITCH
##        (the last five are view only: the rules read obs)
##   obs  2 m cells: C_* kind (building, wall body, walkway, tower, ditch,
##        water, stair, gate g)
##
## A city is generated in a canonical frame (defenders at the top, the main
## gate facing the attackers at the bottom, the sea, if any, behind the
## city at the top), relative to its own centre, so a city looks the same
## whatever the field size; if the defenders are sim side 0 (the bottom)
## everything is turned 180 degrees at the end.
##
## Plans (by the founder's culture; geometry fixed per settlement):
##   castrum  rectangle, square corners or rounded, square corner and
##            interval towers, gates at the ends of two main streets that
##            cross at the forum, a regular grid of square blocks
##   polis    irregular outline, agora off the centre, two street grids at
##            an angle (wedge-shaped blocks where they meet), a walled
##            acropolis on a knoll at a back corner
##   punic    thick wall, close square towers on the land side, two land
##            gates, dense small blocks, a walled citadel (Byrsa) inland
##   oppidum  oval / kidney outline on a rise, the main gate at the end of an
##            offset funnel in the wall, round houses in clusters on lanes,
##            villages and towns with gardens, pens and orchards inside
##   ring     the original round ring (default without a plan)
## Sites: plain (level, open; ditch at walls 3; a straight approach road
## with orchards), hill (a rise, gentle on the gate side), spur (a tongue of
## high ground, steep on three sides, a neck to the main gate; other gates
## are posterns), each optionally on the coast (sea behind, a sea wall with
## a sea gate and a mole that are scenery only).

const FM := preload("res://sim/fixed_math.gd")

const M := 1024

# 2 m obstacle cells.
const C_OPEN := 0
const C_BUILDING := 1
const C_WALL := 2      # wall body: outer parapet and inner face
const C_WALK := 3      # wall walkway (only units on the wall stand here)
const C_TOWER := 4
const C_DITCH := 5     # ditch: foot cross it slowly; horses and engines cannot
const C_WATER := 6     # the sea: nobody
const C_STAIR := 7     # stair in the wall's inner face by a tower: walkway <-> street
const C_GATE := 8      # + gate index (8..12)

# Passability bits (BattleSim.nav).
const NAV_GROUND := 1
const NAV_WALL := 2
const NAV_DITCH := 4

# 4 m vegetation cells.
const V_DENS := 3
const V_URBAN := 4
const V_FIELD := 8
const V_ROAD := 16
const V_PLAZA := 32
const V_WATER := 64
const V_DITCH := 128

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
const WALL_T: Array[int] = [0, 8, 10, 12]          # wall thickness by wall level (punic +2)
const WALL_P: Array[int] = [0, 2, 2, 4]            # outer parapet thickness
const WALK_W := 4                       # walkway width
const WALL_H: Array[int] = [0, 5, 7, 9]            # walkway height above the ground
const GATE_HW := 4                      # gate opening half width
const POSTERN_HW := 2                   # postern (spur sites' side gates) half width
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
const STAIR_IN := 3                     # a stair this far in from each end of a walkway stretch
const STAIR_HW := 2                     # ... this wide either side
const DITCH_GAP := 10                   # ditch starts this far beyond the towers' reach
const DITCH_W := 6                      # ditch width
const CAUSEWAY_HW := 4                  # causeway half width beyond a gate's opening
const CIT_N := 6                        # citadel wall: corners

## Walkway segment entries ("segs"): SEG_LEN ints: x0, y0, x1, y1 (walkway
## centre line), outward direction, then for each end (start, end) the
## walkway point E, the stair point S (in the wall's inner face) and its
## foot D (the street inside), and flags.
const SEG_LEN := 18
const SEG_SEA := 1     # faces the sea
const SEG_CIT := 2     # on the citadel's wall

# Building kinds (view: roofs) and shapes.
const B_HOUSE := 0
const B_TEMPLE := 1    # the owner's shrine on the plaza
const B_MARKET := 2
const B_BARRACKS := 3
const B_STABLES := 4
const B_WORKSHOP := 5
const B_RANGE := 6
const SH_RECT := 0     # [x0, y0, x1, y1, kind, style, 0]
const SH_QUAD := 1     # ... + 4 corners x, y
const SH_ROUND := 2    # ... + centre x, y, radius

const K_FLAT := 0
const K_ROLLING := 1
const K_HILL := 4
const K_RIDGE := 2

## Founding cultures (campaign region data; a settlement's wall plan is its
## founder's) and the cultures whose style the view uses for buildings and
## shrines (the current owner's, or whoever built a building).
const CUL_LATIN := 0
const CUL_GREEK := 1
const CUL_PUNIC := 2
const CUL_CELTIC := 3
const CULTURE_NAMES: Array[String] = ["Latin", "Greek", "Punic", "Celtic"]
const CULTURE_ADJ: Array[String] = ["Roman", "Greek", "Punic", "Celtic"]
## Wall plans (city key "plan"): one per founding culture, plus the original
## round ring (the default when a scenario gives none: sandbox tests and
## older scenarios keep their maps).
const PLAN_CASTRUM := 0   # latin: rectangle, four gates, forum, grid
const PLAN_POLIS := 1     # greek: irregular, off-centre agora, wedge blocks, acropolis
const PLAN_PUNIC := 2     # punic: thick wall, close square towers, two land gates, citadel
const PLAN_OPPIDUM := 3   # celtic: oval on a rise, re-entrant main gate, round houses
const PLAN_RING := 4      # the original ring (no culture)
const PLAN_NAMES: Array[String] = ["Castrum", "Polis", "Punic", "Oppidum", "Ring"]
## Sites (derived from the region's terrain kind and the city seed).
const SITE_PLAIN := 0
const SITE_HILL := 1
const SITE_SPUR := 2
const SITE_NAMES: Array[String] = ["plain", "hill", "spur"]

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

## City parameters with defaults filled in. Geometry: seed, level, walls,
## bld (building chains present), def (defending sim side), plan (PLAN_*;
## default the original ring), coast (1: the sea behind the city). View
## only (copied into the layout, never read by the rules): owner (culture
## of the current owner, -1 = the founder's), founder (culture), banner
## (campaign faction index for banner colours; -1 independent, -2 none:
## the view uses the side colours), bstyle (culture that built each entry
## of bld), hstyle (culture of the houses that appeared at settlement
## level 0, 1, 2).
static func city_params(c: Dictionary) -> Dictionary:
	var bld: Array = []
	for b in c.get("bld", []):
		bld.append(int(b))
	var plan := clampi(int(c.get("plan", PLAN_RING)), 0, PLAN_RING)
	var founder := int(c.get("founder", plan if plan < PLAN_RING else CUL_LATIN))
	var bstyle: Array = []
	var bs: Array = c.get("bstyle", [])
	for k in bld.size():
		bstyle.append(int(bs[k]) if k < bs.size() else founder)
	var hstyle: Array = []
	var hs: Array = c.get("hstyle", [])
	for k in 3:
		hstyle.append(int(hs[k]) if k < hs.size() else founder)
	var owner := int(c.get("owner", -1))
	return {"seed": int(c.get("seed", 1)), "level": clampi(int(c.get("level", 1)), 0, 2),
		"walls": clampi(int(c.get("walls", 0)), 0, 3), "bld": bld, "def": int(c.get("def", 1)),
		"plan": plan, "coast": 1 if int(c.get("coast", 0)) != 0 else 0, "founder": founder,
		"owner": owner if owner >= 0 else founder, "banner": int(c.get("banner", -2)),
		"bstyle": bstyle, "hstyle": hstyle}


## Site of a settlement: SITE_* from the region's terrain kind (rolling
## country: a plain or a gentle hill by the seed; valleys: a plain).
static func site_of(kind: int, seed_v: int) -> int:
	if kind == K_HILL:
		return SITE_HILL
	if kind == K_RIDGE:
		return SITE_SPUR
	if kind == K_ROLLING:
		return SITE_HILL if ((seed_v >> 4) & 1) != 0 else SITE_PLAIN
	return SITE_PLAIN


## "Greek city on a coastal hill" (the campaign preview's caption).
static func describe(plan: int, level: int, kind: int, seed_v: int, coast: int) -> String:
	var who: String = CULTURE_NAMES[plan] if plan < PLAN_RING else "Walled"
	var what: String = ["village", "town", "city"][clampi(level, 0, 2)]
	var site := site_of(kind, seed_v) if plan < PLAN_RING else SITE_PLAIN
	var where := ""
	if site == SITE_PLAIN:
		where = "by the sea" if coast != 0 else "on open ground"
	elif site == SITE_HILL:
		where = "on a coastal hill" if coast != 0 else "on a hill"
	else:
		where = "on a spur over the sea" if coast != 0 else "on a spur"
	if plan == PLAN_RING:
		return "%s %s" % [who, what]
	return "%s %s %s" % [who, what, where]


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


## The coast behind a coastal city (canonical frame): [y0 at the centre,
## slope per mille, centre x, half width of the straight shore along the
## city, bend per mille beyond it, two waves (amplitude, phase), centre y].
static func coast_params(c: Dictionary, w_m: int) -> PackedInt32Array:
	var p := city_params(c)
	var fr := city_frame(p, w_m, 0)
	var rng := _rng(int(p["seed"]) * 13 + 101)
	var r0 := fr.z
	var y0 := fr.y - r0 * _rr(rng, 42, 56) / 100
	var slope := _rr(rng, -50, 50)
	var flat := r0 * 112 / 100 + 30
	var bend := _rr(rng, -300, 300)
	var a1 := _rr(rng, 3, 8)
	var p1 := _r(rng, 1024)
	var a2 := _rr(rng, 2, 4)
	var p2 := _r(rng, 1024)
	return PackedInt32Array([y0, slope, fr.x, flat, bend, a1, p1, a2, p2, fr.y])


## Canonical y (metres) of the shoreline at x: the sea lies above it.
static func shore_y(cp: PackedInt32Array, x: int) -> int:
	var y := cp[0] + cp[1] * (x - cp[2]) / 1000
	var ex := maxi(absi(x - cp[2]) - cp[3], 0)
	if ex > 0:
		var ramp := mini(ex, 40)
		var wave := cp[5] * FM.sin_a((cp[6] + ex * 1024 / 150) & 1023) \
			+ cp[7] * FM.sin_a((cp[8] + ex * 1024 / 60) & 1023)
		y += ex * cp[4] / 1000 + wave * ramp / 40 / FM.TRIG_ONE
	return maxi(y, 20)


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
		city = _city(city_params(terr["city"]), int(terr.get("kind", K_FLAT)), w_m, h_m, out, excl)
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
	if has_city:
		_city_post(city, veg, vw, vh)
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


## After the woods: orchards and gardens planted by the settlement (inside
## enclosed fields, along a plain's approach road), and no trees on the sea
## or in the ditch.
static func _city_post(lay: Dictionary, veg: PackedByteArray, vw: int, vh: int) -> void:
	if not lay.has("post_veg"):
		return
	for r in lay["post_veg"]:
		var a: Array = r
		_veg_rect(veg, vw, vh, int(a[0]), int(a[1]), int(a[2]), int(a[3]), int(a[4]))
	lay.erase("post_veg")
	for k in veg.size():
		if (veg[k] & (V_WATER | V_DITCH)) != 0:
			veg[k] &= ~V_DENS


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

static func _city(p: Dictionary, kind: int, w_m: int, h_m: int, out: Dictionary, excl: Array) -> Dictionary:
	if int(p["plan"]) == PLAN_RING:
		return _city_ring(p, w_m, h_m, out, excl)
	return _city_plan(p, kind, w_m, h_m, out, excl)


## The original ring (PLAN_RING): generate the city (canonical frame) into
## `out` and append the areas kept free of woods to `excl`. Returns the
## layout (metres). Random numbers are drawn as they always were, so these
## maps are the same as before (plus stairs at the towers).
static func _city_ring(p: Dictionary, w_m: int, h_m: int, out: Dictionary, excl: Array) -> Dictionary:
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
	var ed := _edges(vx, vy, cx, cy, true)
	var en_x: PackedInt32Array = ed["nx"]
	var en_y: PackedInt32Array = ed["ny"]
	var ee_x: PackedInt32Array = ed["ex"]
	var ee_y: PackedInt32Array = ed["ey"]
	var elen: PackedInt32Array = ed["len"]
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
			gates.append(_mk_gate(vx, vy, ed, best, along, GATE_HW, trg, t, 1 if gates.is_empty() else 0, 0, 0))
	# Wall band, ring road (distance from the wall line, inside / outside).
	var towers: Array = []
	if walls > 0:
		_wall_band(obs, keep, inside, ow, oh, vx, vy, t, pp, inner)
		for k in nv:
			_disc(obs, ow, oh, vx[k], vy[k], tow_r, C_TOWER)
			towers.append([vx[k], vy[k], tow_r, 0, 0])
		for g in gates.size():
			_gate_raster(obs, keep, ow, oh, gates[g], g, ed, t, 0, towers)
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
	var lm := _landmarks(p, px, py, hs, msw, gates, cx, cy, r0, false)
	for b in lm:
		var a: Array = b
		if _rect_free(inside, keep, occ, ow, oh, a[1], a[2], a[3], a[4]):
			_mark_rect(occ, ow, oh, a[1], a[2], a[3], a[4])
			buildings.append([a[1], a[2], a[3], a[4], a[0], a[5], SH_RECT])
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
						var hst := _house_style(p, inside, ow, oh, cx, cy, (hx0 + hx1) / 2, (hy0 + hy1) / 2)
						buildings.append([hx0, hy0, hx1, hy1, B_HOUSE, hst, SH_RECT])
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
	# Wall walkway segments between towers and gates, stairs at their ends.
	var segs: Array = []
	if walls > 0:
		var cut := PackedInt32Array()
		cut.resize(nv)
		cut.fill(tow_r + 1)
		var nosea := PackedInt32Array()
		nosea.resize(nv)
		nosea.fill(0)
		segs = _segments(vx, vy, ed, gates, cut, t, pp, inner, nosea, 0, 0)
		_stairs(obs, inside, ow, oh, segs, t, inner)
	# Outside: orchards and fields at low levels, cleared ground near high
	# walls, the approach and the attackers' deployment free of trees.
	var mg: Dictionary = gates[0] if not gates.is_empty() else {"ix": cx, "iy": cy + r0 * 3 / 4}
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
		cx, cy, r0, t, tow_r, px, py, hs, streets, street_xs, street_ys, inside, walls, PackedInt32Array())
	out["obs"] = obs
	out["ow"] = ow
	out["oh"] = oh
	out["obs_on"] = 1
	out["city_on"] = 1
	var poly := PackedInt32Array()
	for k in nv:
		poly.append(vx[k])
		poly.append(vy[k])
	var mouths: Array = []
	if walls == 0:
		for s in streets:
			var a: Array = s
			mouths.append([int(a[2]), int(a[3]), FM.atan2_a(int(a[3]) - int(a[1]), int(a[2]) - int(a[0]))])
	var lay := {"cx": cx, "cy": cy, "r0": r0, "level": level, "walls": walls, "def": int(p["def"]),
		"seed": int(p["seed"]), "t": t, "pp": pp, "inner": inner, "wall_h_m": wall_h,
		"build_h_m": BUILD_H[level], "poly": poly, "gates": gates, "towers": towers,
		"plaza": [px, py, hs, hs + CAPTURE_EXTRA], "agora": [px, py, hs], "cit": {},
		"streets": streets, "mouths": mouths, "buildings": buildings,
		"fields": fields, "segs": segs, "att_x": att_x, "att_y": att_y, "nav": nav_nodes,
		"gate_hp": GATE_HP[walls], "plan": PLAN_RING, "site": SITE_PLAIN, "coast": 0, "ditch": 0,
		"sea": {}, "palisade": 1 if level == 0 and walls > 0 else 0, "enclosed": 0,
		"founder": int(p["founder"]), "owner": int(p["owner"]), "banner": int(p["banner"])}
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


## Landmarks by the plaza and the main gate from the buildings present:
## [kind, x0, y0, x1, y1, style]. The temple (the owner's shrine) is in the
## owner's style, the others in the style of whoever built them.
static func _landmarks(p: Dictionary, px: int, py: int, hs: int, msw: int, gates: Array, cx: int,
		cy: int, r0: int, shrine_village: bool) -> Array:
	var level: int = p["level"]
	var bld: Array = p["bld"]
	var bstyle: Array = p["bstyle"]
	var st_of := func(chain: int) -> int:
		var k := bld.find(chain)
		return int(bstyle[k]) if k >= 0 else int(p["founder"])
	var lm: Array = []
	if level >= 1:
		var tw := 16 if level == 1 else 20
		lm.append([B_TEMPLE, px - tw / 2, py - hs - 4 - tw * 13 / 10, px + tw / 2, py - hs - 4, int(p["owner"])])
	elif shrine_village:
		lm.append([B_TEMPLE, px - 5, py - hs - 14, px + 5, py - hs - 4, int(p["owner"])])
	if bld.has(1) and level >= 1:  # market: a long stoa on the plaza's left side
		lm.append([B_MARKET, px - hs - 12, py - hs, px - hs - 4, py + hs, st_of.call(1)])
	if bld.has(3) and level >= 1:
		lm.append([B_RANGE, px + hs + 4, py - hs, px + hs + 14, py, st_of.call(3)])
	if bld.has(5) and level >= 1:
		lm.append([B_WORKSHOP, px + hs + 4, py + 4, px + hs + 16, py + hs, st_of.call(5)])
	var mg: Dictionary = gates[0] if not gates.is_empty() else {"ix": cx, "iy": cy + r0 * 3 / 4}
	if bld.has(2):
		lm.append([B_BARRACKS, int(mg["ix"]) + msw + 4, int(mg["iy"]) - 34, int(mg["ix"]) + msw + 16, int(mg["iy"]) - 10, st_of.call(2)])
	if bld.has(4):
		lm.append([B_STABLES, int(mg["ix"]) - msw - 18, int(mg["iy"]) - 32, int(mg["ix"]) - msw - 4, int(mg["iy"]) - 12, st_of.call(4)])
	return lm


## Style (culture) of a house at (x, y): that of the settlement level at
## which its spot first lay inside the footprint (the footprint of a
## smaller level is this one shrunk about the centre).
static func _house_style(p: Dictionary, inside: PackedByteArray, ow: int, oh: int, cx: int, cy: int,
		x: int, y: int) -> int:
	var level: int = p["level"]
	var hst: Array = p["hstyle"]
	var r_now: int = R_LEVEL[level]
	for lv in level:
		var r_l: int = R_LEVEL[lv]
		var qx := cx + (x - cx) * r_now / r_l
		var qy := cy + (y - cy) * r_now / r_l
		if qx >= 0 and qy >= 0 and qx / 2 < ow and qy / 2 < oh and inside[(qy / 2) * ow + qx / 2] != 0:
			return int(hst[lv])
	return int(hst[level])


# --------------------------------------------------------- city plans ----

## Plan outline and parameters (canonical frame), drawn from the seed in a
## fixed order whatever the level and walls (so a town grows into the same
## city): the wall polygon (after the coast is cut off), towers per vertex,
## the agora, the citadel (fitted inside), lattice and block parameters.
## Shared with sim/terrain.gd (the citadel's knoll). Returns a Dictionary;
## its "rng" continues the draws for the houses.
static func plan_outline(p: Dictionary, kind: int, w_m: int) -> Dictionary:
	var level: int = p["level"]
	var walls: int = p["walls"]
	var plan: int = p["plan"]
	var seed_v: int = p["seed"]
	var coast: int = p["coast"]
	var rng := _rng(seed_v * 7 + 3 + plan)
	var fr := city_frame(p, w_m, 0)
	var cx := fr.x
	var cy := fr.y
	var r0 := fr.z
	var rmax := r0 * 112 / 100
	var site := site_of(kind, seed_v)
	var t := 0
	if walls > 0:
		t = WALL_T[walls] + (2 if plan == PLAN_PUNIC else 0)
	var tow_r := t / 2 + 2
	var trg := t / 2 + 1
	var hs: int = PLAZA_HS[level]
	var vx := PackedInt32Array()
	var vy := PackedInt32Array()
	var vt := PackedInt32Array()    # tower radius at each vertex (0 none, -1 default)
	var px := cx
	var py := cy
	var tsp := 0
	var g_want: Array = []
	var funnel := -1
	var cit_ang := 0
	var cit_dist := 0
	var cit_r := 0
	var lat_a := 0
	var lat_b := 0
	var seam := 0
	var blk_w := 20
	var blk_l := 20
	var blk_s := 4
	var built_extra := 0
	var n_gates := 2
	match plan:
		PLAN_CASTRUM:
			var hwf := _rr(rng, 76, 84)
			var hhf := _rr(rng, 70, 80)
			var rounded := _r(rng, 2)
			var chf := _rr(rng, 10, 16)
			var hw := r0 * hwf / 100
			var hh := r0 * hhf / 100
			var ch := r0 * chf / 100 if rounded != 0 else 0
			if ch > 0:
				vx = PackedInt32Array([cx + hw, cx + hw, cx + hw - ch, cx - hw + ch, cx - hw, cx - hw, cx - hw + ch, cx + hw - ch])
				vy = PackedInt32Array([cy - hh + ch, cy + hh - ch, cy + hh, cy + hh, cy + hh - ch, cy - hh + ch, cy - hh, cy - hh])
			else:
				vx = PackedInt32Array([cx + hw, cx + hw, cx - hw, cx - hw])
				vy = PackedInt32Array([cy - hh, cy + hh, cy + hh, cy - hh])
			px = cx + _rr(rng, -6, 6)
			py = cy + _rr(rng, -6, 6)
			tsp = _rr(rng, 28, 40)
			n_gates = _rr(rng, 3, 4)
			blk_w = 2 * _rr(rng, 10, 13)
			blk_l = blk_w
			blk_s = 4 + _r(rng, 2)
			built_extra = 6
		PLAN_POLIS:
			var nv := 8 + _r(rng, 4)
			for k in nv:
				var ang := (k * 1024 / nv + _rr(rng, -30, 30)) & 1023
				var rad := mini(r0 * _rr(rng, 82, 114) / 100, rmax)
				vx.append(cx + FM.cos_a(ang) * rad / FM.TRIG_ONE)
				vy.append(cy + FM.sin_a(ang) * rad / FM.TRIG_ONE)
			var ag_a := (256 + _rr(rng, -200, 200)) & 1023
			var ag_d := r0 * _rr(rng, 15, 28) / 100
			px = cx + FM.cos_a(ag_a) * ag_d / FM.TRIG_ONE
			py = cy + FM.sin_a(ag_a) * ag_d / FM.TRIG_ONE
			cit_ang = (768 + _rr(rng, 90, 210) * (1 if _r(rng, 2) == 0 else -1)) & 1023
			if coast != 0:
				cit_ang = (cit_ang + (256 if cit_ang > 768 else -256)) & 1023  # a front corner, off the sea
			cit_dist = r0 * 50 / 100
			cit_r = _rr(rng, 20, 24)
			n_gates = _rr(rng, 2, 4)
			lat_a = _rr(rng, -70, 70)
			lat_b = lat_a + _rr(rng, 70, 130) * (1 if _r(rng, 2) == 0 else -1)
			seam = _r(rng, 1024)
			blk_w = 2 * _rr(rng, 8, 10)
			blk_l = 2 * _rr(rng, 15, 19)
			blk_s = 4 + _r(rng, 2)
		PLAN_PUNIC:
			var nv2 := 6 + _r(rng, 3)
			for k in nv2:
				var ang2 := (k * 1024 / nv2 + _rr(rng, -15, 15)) & 1023
				var rad2 := r0 * _rr(rng, 94, 106) / 100
				vx.append(cx + FM.cos_a(ang2) * rad2 / FM.TRIG_ONE)
				vy.append(cy + FM.sin_a(ang2) * rad2 / FM.TRIG_ONE)
			var side_c := _r(rng, 2)
			var jc := _rr(rng, -60, 60)
			var jb := _rr(rng, -120, 120)
			cit_ang = ((512 * side_c + jc) if coast != 0 else (768 + jb)) & 1023
			cit_dist = r0 * 55 / 100
			cit_r = _rr(rng, 21, 25)
			var away := (cit_ang + 512) & 1023
			px = cx + FM.cos_a(away) * (r0 * 12 / 100) / FM.TRIG_ONE
			py = cy + FM.sin_a(away) * (r0 * 12 / 100) / FM.TRIG_ONE
			tsp = _rr(rng, 18, 24)
			n_gates = 2
			g_want = [256, 512 if _r(rng, 2) == 0 else 0]
			lat_a = _rr(rng, -24, 24)
			lat_b = lat_a
			blk_w = 2 * _rr(rng, 7, 10)
			blk_l = 2 * _rr(rng, 10, 14)
			blk_s = 3 + _r(rng, 2)
			built_extra = 10
		_:  # PLAN_OPPIDUM
			var ea := r0 * _rr(rng, 98, 108) / 100
			var eb := r0 * _rr(rng, 78, 90) / 100
			var ki := (768 + _rr(rng, -150, 150)) & 1023
			var kd := _rr(rng, 12, 18)
			var phi := (256 + _rr(rng, -80, 80)) & 1023
			var depth := _rr(rng, 20, 26)
			var skew := _rr(rng, -8, 8)
			n_gates = 1 + _r(rng, 2)
			px = cx + _rr(rng, -8, 8)
			py = cy + _rr(rng, -8, 8)
			var mouth := 26
			var dlt := mouth * 163 / maxi(_ell_r(ea, eb, phi, ki, kd), 1)
			var gw := 2 * (GATE_HW + 2 * trg) + 16
			var done := walls == 0
			for k in 16:
				var a := k * 64
				if walls > 0 and absi(FM.angle_diff(a, phi)) <= dlt + 20:
					continue
				if not done and a > phi:
					done = true
					funnel = _funnel(vx, vy, vt, cx, cy, ea, eb, ki, kd, phi, dlt, depth, skew, gw, tow_r + 2)
				var r := _ell_r(ea, eb, a, ki, kd)
				vx.append(cx + FM.cos_a(a) * r / FM.TRIG_ONE)
				vy.append(cy + FM.sin_a(a) * r / FM.TRIG_ONE)
				vt.append(0)
			if not done:
				funnel = _funnel(vx, vy, vt, cx, cy, ea, eb, ki, kd, phi, dlt, depth, skew, gw, tow_r + 2)
	# Draws shared by every plan (fixed order).
	var gate_jit: Array = []
	for k in 4:
		gate_jit.append(_rr(rng, -100, 100))
	var field_depth := _rr(rng, 25, 35)
	var cit_jit: Array = []
	for k in CIT_N:
		cit_jit.append(_rr(rng, -2, 2))
	var sea_jit := _rr(rng, -100, 100)
	var mole_l := _rr(rng, 30, 45)
	var mole_e := _rr(rng, 15, 25) * (1 if _r(rng, 2) == 0 else -1)
	if vt.size() < vx.size():
		for k in range(vt.size(), vx.size()):
			vt.append(-1)
	# The sea cuts off the back of a coastal city along the shore.
	var onl := PackedInt32Array()
	onl.resize(vx.size())
	onl.fill(0)
	var cp := PackedInt32Array()
	if coast != 0:
		cp = coast_params(p, w_m)
		var yoff := t / 2 if walls > 0 else 3
		var cl := _clip(vx, vy, vt, cp[2], cp[0] + yoff, cp[1], funnel)
		vx = cl[0]
		vy = cl[1]
		vt = cl[2]
		onl = cl[3]
		funnel = cl[4]
	var nv3 := vx.size()
	var esea := PackedInt32Array()
	esea.resize(nv3)
	for k in nv3:
		esea[k] = 1 if onl[k] != 0 and onl[(k + 1) % nv3] != 0 else 0
	for k in nv3:
		if vt[k] < 0:
			vt[k] = (tow_r if walls > 0 and plan != PLAN_OPPIDUM else 0)
			if onl[k] != 0 and walls > 0:
				vt[k] = tow_r
	# Citadel: walls and at least a town, fitted inside the outer wall and
	# clear of the agora (else none).
	var cit := Vector3i(0, 0, 0)
	if cit_r > 0 and walls > 0 and level >= 1:
		# Its spot, else the nearest that fits: turned up to 120 degrees
		# either way and pulled in toward the centre.
		if level == 1:
			cit_r -= 2
			cit_dist = cit_dist * 85 / 100
		var need := cit_r + t + RING_W + 4
		var sep := hs + cit_r + t / 2 + 10
		var found := false
		for pass_n in 2:
			# Second pass (small or coastal towns): the agora gives way.
			for da in [0, 50, -50, 100, -100, 150, -150]:
				var ca := (cit_ang + int(da)) & 1023
				var sx := cx + FM.cos_a(ca) * cit_dist / FM.TRIG_ONE
				var sy := cy + FM.sin_a(ca) * cit_dist / FM.TRIG_ONE
				for st in 7:
					var qx := sx + (cx - sx) * st / 8
					var qy := sy + (cy - sy) * st / 8
					if not _pt_in(vx, vy, qx, qy) or _poly_dist(vx, vy, qx, qy) < need:
						continue
					var dag := FM.approx_len(qx - px, qy - py)
					if dag < sep:
						if pass_n == 0:
							continue
						# Move the agora straight away from the citadel.
						var ux := (px - qx) * 1000 / maxi(dag, 1) if dag > 0 else 0
						var uy := (py - qy) * 1000 / maxi(dag, 1) if dag > 0 else 1000
						var ax := qx + ux * sep / 1000
						var ay := qy + uy * sep / 1000
						if not _pt_in(vx, vy, ax, ay) or _poly_dist(vx, vy, ax, ay) < hs + t / 2 + RING_W:
							continue
						px = ax
						py = ay
					cit = Vector3i(qx, qy, cit_r)
					found = true
					break
				if found:
					break
			if found:
				break
	if plan == PLAN_CASTRUM:
		n_gates = mini(n_gates, 2 + level)
		g_want = [256, 768] if n_gates == 2 else ([256, 512, 0] if n_gates == 3 else [256, 512, 0, 768])
	elif plan == PLAN_POLIS:
		n_gates = mini(n_gates, 2 + level)
		g_want = [256, 768] if n_gates == 2 else ([256, 512, 0] if n_gates == 3 else [256, 512, 0, 768])
	elif plan == PLAN_OPPIDUM:
		g_want = [768] if n_gates == 2 and level >= 1 else []
	return {"vx": vx, "vy": vy, "vt": vt, "esea": esea, "px": px, "py": py, "tsp": tsp, "g_want": g_want,
		"funnel": funnel, "cit": cit, "cit_jit": cit_jit, "lat_a": lat_a, "lat_b": lat_b, "seam": seam,
		"blk_w": blk_w, "blk_l": blk_l, "blk_s": blk_s, "built_extra": built_extra, "gate_jit": gate_jit,
		"field_depth": field_depth, "sea_jit": sea_jit, "mole_l": mole_l, "mole_e": mole_e, "cp": cp,
		"site": site, "t": t, "tow_r": tow_r, "trg": trg, "rng": rng, "cx": cx, "cy": cy, "r0": r0}


## Radius (m) of an oppidum's oval at angle a, with the kidney's dent.
static func _ell_r(ea: int, eb: int, a: int, ki: int, kd: int) -> int:
	var c := FM.cos_a(a)
	var s := FM.sin_a(a)
	var den := maxi(FM.isqrt(eb * c * eb * c + ea * s * ea * s), 1)
	var r := ea * eb * FM.TRIG_ONE / den
	var d := absi(FM.angle_diff(a, ki))
	if d < 200:
		var w := 200 - d
		r -= r * kd * (w * w / 200) / 20000
	return r


## Append an oppidum's gate funnel to the outline at angle phi: the mouth
## corners (with towers) on the oval and the inner corners, offset to one
## side by `skew` and one arm longer than the other; the gate goes in the
## inner edge. Returns the index of the inner left corner.
static func _funnel(vx: PackedInt32Array, vy: PackedInt32Array, vt: PackedInt32Array, cx: int, cy: int,
		ea: int, eb: int, ki: int, kd: int, phi: int, dlt: int, depth: int, skew: int, gw: int,
		mouth_r: int) -> int:
	var ra := _ell_r(ea, eb, (phi - dlt) & 1023, ki, kd)
	var rb := _ell_r(ea, eb, (phi + dlt) & 1023, ki, kd)
	var rm := _ell_r(ea, eb, phi, ki, kd)
	var mx := cx + FM.cos_a(phi) * rm / FM.TRIG_ONE
	var my := cy + FM.sin_a(phi) * rm / FM.TRIG_ONE
	var ux := -FM.cos_a(phi)
	var uy := -FM.sin_a(phi)
	var lx := -FM.sin_a(phi)
	var ly := FM.cos_a(phi)
	vx.append(cx + FM.cos_a((phi - dlt) & 1023) * ra / FM.TRIG_ONE)
	vy.append(cy + FM.sin_a((phi - dlt) & 1023) * ra / FM.TRIG_ONE)
	vt.append(mouth_r)
	var da := depth + skew / 2
	var db := depth - skew / 2
	var idx := vx.size()
	vx.append(mx + (ux * da - lx * (gw / 2 - skew)) / FM.TRIG_ONE)
	vy.append(my + (uy * da - ly * (gw / 2 - skew)) / FM.TRIG_ONE)
	vt.append(0)
	vx.append(mx + (ux * db + lx * (gw / 2 + skew)) / FM.TRIG_ONE)
	vy.append(my + (uy * db + ly * (gw / 2 + skew)) / FM.TRIG_ONE)
	vt.append(0)
	vx.append(cx + FM.cos_a((phi + dlt) & 1023) * rb / FM.TRIG_ONE)
	vy.append(cy + FM.sin_a((phi + dlt) & 1023) * rb / FM.TRIG_ONE)
	vt.append(mouth_r)
	return idx


## Cut a polygon by the line y >= y0 + slope (x - cx) / 1000 (Sutherland-
## Hodgman, integers). Returns [vx, vy, vt, on the line (per vertex),
## funnel index moved]. Vertices closer than 6 m are merged.
static func _clip(vx: PackedInt32Array, vy: PackedInt32Array, vt: PackedInt32Array, cx: int, y0: int,
		slope: int, funnel: int) -> Array:
	var n := vx.size()
	var ox := PackedInt32Array()
	var oy := PackedInt32Array()
	var ot := PackedInt32Array()
	var ol := PackedInt32Array()
	var nf := -1
	for k in n:
		var k2 := (k + 1) % n
		var fp := (vy[k] - y0) * 1000 - slope * (vx[k] - cx)
		var fq := (vy[k2] - y0) * 1000 - slope * (vx[k2] - cx)
		if fp >= 0:
			if k == funnel:
				nf = ox.size()
			ox.append(vx[k])
			oy.append(vy[k])
			ot.append(vt[k])
			ol.append(1 if fp < 1000 else 0)
		if (fp >= 0) != (fq >= 0):
			ox.append(vx[k] + (vx[k2] - vx[k]) * fp / (fp - fq))
			oy.append(vy[k] + (vy[k2] - vy[k]) * fp / (fp - fq))
			ot.append(-1)
			ol.append(1)
	# Merge near neighbours (keep the first; "on the line" if either was).
	var mx := PackedInt32Array()
	var my := PackedInt32Array()
	var mt := PackedInt32Array()
	var ml := PackedInt32Array()
	var mf := -1
	for k in ox.size():
		var last := mx.size() - 1
		if last >= 0 and FM.approx_len(ox[k] - mx[last], oy[k] - my[last]) < 6 and k != nf and k != nf + 1:
			ml[last] = ml[last] | ol[k]
			continue
		if k == nf:
			mf = mx.size()
		mx.append(ox[k])
		my.append(oy[k])
		mt.append(ot[k])
		ml.append(ol[k])
	if mx.size() >= 3 and FM.approx_len(mx[0] - mx[mx.size() - 1], my[0] - my[my.size() - 1]) < 6 \
			and mf != mx.size() - 1:
		ml[0] = ml[0] | ml[ml.size() - 1]
		mx.resize(mx.size() - 1)
		my.resize(my.size() - 1)
		mt.resize(mt.size() - 1)
		ml.resize(ml.size() - 1)
	return [mx, my, mt, ml, mf]


## A settlement of one of the cultures' plans (see the header).
static func _city_plan(p: Dictionary, kind: int, w_m: int, h_m: int, out: Dictionary, excl: Array) -> Dictionary:
	var level: int = p["level"]
	var walls: int = p["walls"]
	var plan: int = p["plan"]
	var coast: int = p["coast"]
	var o := plan_outline(p, kind, w_m)
	var rng: PackedInt32Array = o["rng"]
	var cx: int = o["cx"]
	var cy: int = o["cy"]
	var r0: int = o["r0"]
	var rmax := r0 * 112 / 100
	var site: int = o["site"]
	var ow := w_m / 2
	var oh := h_m / 2
	var nc := ow * oh
	var obs := PackedByteArray()
	obs.resize(nc)
	obs.fill(C_OPEN)
	var inside := PackedByteArray()
	inside.resize(nc)
	inside.fill(0)
	var keep := PackedByteArray()
	keep.resize(nc)
	keep.fill(0)
	var occ := PackedByteArray()
	occ.resize(nc)
	occ.fill(0)
	var t: int = o["t"]
	var pp: int = WALL_P[walls]
	var inner := maxi(t - pp - WALK_W, 0)
	var wall_h: int = WALL_H[walls]
	var tow_r: int = o["tow_r"]
	var trg: int = o["trg"]
	var sq := 1 if plan == PLAN_CASTRUM or plan == PLAN_PUNIC else 0
	var hs: int = PLAZA_HS[level]
	var msw: int = [3, 4, 4][level]
	var vx: PackedInt32Array = o["vx"]
	var vy: PackedInt32Array = o["vy"]
	var vt: PackedInt32Array = o["vt"]
	var esea: PackedInt32Array = o["esea"]
	var nv := vx.size()
	var px: int = o["px"]
	var py: int = o["py"]
	var cp: PackedInt32Array = o["cp"]
	var gate_jit: Array = o["gate_jit"]
	_fill_poly(inside, ow, oh, vx, vy)
	var ed := _edges(vx, vy, cx, cy, false)
	var en_x: PackedInt32Array = ed["nx"]
	var en_y: PackedInt32Array = ed["ny"]
	var ee_x: PackedInt32Array = ed["ex"]
	var ee_y: PackedInt32Array = ed["ey"]
	var elen: PackedInt32Array = ed["len"]
	# ---- gates: the main gate facing the attackers, then the others.
	var gates: Array = []
	if walls > 0:
		var used := {}
		var funnel: int = o["funnel"]
		if plan == PLAN_OPPIDUM and funnel >= 0:
			gates.append(_mk_gate(vx, vy, ed, funnel, elen[funnel] / 2, GATE_HW, trg, t, 1, 0, 0))
			used[funnel] = true
		var wants: Array = o["g_want"]
		for gi in wants.size():
			var want: int = wants[gi]
			var main := gates.is_empty()
			var postern := site == SITE_SPUR and not main
			var hw := POSTERN_HW if postern else GATE_HW
			var gtr := 0 if postern else trg
			var best := -1
			# Facing its way with towers; else further round; else without
			# towers; the main gate anywhere on the land side.
			for attempt in 4:
				var maxd: int = [200, 330, 330, 512][attempt]
				if attempt >= 2:
					gtr = 0
				if attempt == 3 and not main:
					break
				var best_d := 0
				for k in nv:
					if used.has(k) or esea[k] != 0 or elen[k] < 2 * (hw + 2 * gtr) + 6:
						continue
					var na := FM.atan2_a(en_y[k], en_x[k])
					var d := absi(FM.angle_diff(na, want))
					if d > maxd:
						continue
					if plan != PLAN_CASTRUM and (used.has((k + 1) % nv) or used.has((k + nv - 1) % nv)):
						d += 200
					if best < 0 or d < best_d:
						best = k
						best_d = d
				if best >= 0:
					break
			if best < 0:
				continue
			used[best] = true
			var l := elen[best]
			var room := maxi(l / 2 - hw - 2 * gtr - 3, 0)
			var along := l / 2 + clampi(int(gate_jit[gi]) * l / 1600, -room, room)
			if plan == PLAN_CASTRUM:
				# On the line of the forum's main streets.
				along = clampi(((px - vx[best]) * ee_x[best] + (py - vy[best]) * ee_y[best]) / FM.TRIG_ONE,
					l / 2 - room, l / 2 + room)
			gates.append(_mk_gate(vx, vy, ed, best, along, hw, gtr, t, 1 if main else 0, 1 if postern else 0, 0))
	var n_outer := gates.size()
	# ---- walls, towers, gates.
	var towers: Array = []
	var cit := {}
	var cit_in := PackedByteArray()
	if walls > 0:
		_wall_band(obs, keep, inside, ow, oh, vx, vy, t, pp, inner)
		for k in nv:
			if vt[k] > 0:
				var dir_k := FM.atan2_a(ee_y[k], ee_x[k])
				if sq != 0:
					_square(obs, ow, oh, vx[k], vy[k], vt[k], dir_k, C_TOWER)
				else:
					_disc(obs, ow, oh, vx[k], vy[k], vt[k], C_TOWER)
				towers.append([vx[k], vy[k], vt[k], sq, dir_k])
		# Interval towers on the land side (bastions: the walkway runs past).
		var tsp: int = o["tsp"]
		if tsp > 0:
			for k in nv:
				if esea[k] != 0:
					continue
				var a0 := maxi(vt[k], t / 2) + tow_r + 3
				var a1 := elen[k] - maxi(vt[(k + 1) % nv], t / 2) - tow_r - 3
				var nseg := (a1 - a0) / tsp
				if nseg < 1:
					continue
				for q in range(1, nseg + 1):
					var al := a0 + (a1 - a0) * q / (nseg + 1)
					var clear := true
					for gd in gates:
						if int(gd["edge"]) == k and absi(al - int(gd["along"])) < int(gd["hw"]) + 2 * int(gd["tr"]) + tow_r + 3:
							clear = false
					if not clear:
						continue
					var bx := vx[k] + (ee_x[k] * al + en_x[k] * (t / 2)) / FM.TRIG_ONE
					var by := vy[k] + (ee_y[k] * al + en_y[k] * (t / 2)) / FM.TRIG_ONE
					var dir_e := FM.atan2_a(ee_y[k], ee_x[k])
					_bastion(obs, inside, ow, oh, bx, by, tow_r - 1, dir_e, sq)
					towers.append([bx, by, tow_r - 1, sq, dir_e])
		for g in gates.size():
			_gate_raster(obs, keep, ow, oh, gates[g], g, ed, t, sq, towers)
		# The citadel (acropolis / Byrsa): its own wall ring with one gate.
		var cv: Vector3i = o["cit"]
		if cv.z > 0:
			var cjit: Array = o["cit_jit"]
			var cvx := PackedInt32Array()
			var cvy := PackedInt32Array()
			for k in CIT_N:
				var ca := (k * 1024 / CIT_N + 40) & 1023
				var cr := cv.z + int(cjit[k])
				cvx.append(cv.x + FM.cos_a(ca) * cr / FM.TRIG_ONE)
				cvy.append(cv.y + FM.sin_a(ca) * cr / FM.TRIG_ONE)
			cit_in.resize(nc)
			cit_in.fill(0)
			_fill_poly(cit_in, ow, oh, cvx, cvy)
			var ced := _edges(cvx, cvy, cv.x, cv.y, false)
			_wall_band(obs, keep, cit_in, ow, oh, cvx, cvy, t, pp, inner)
			_keep_disc(keep, ow, oh, cv.x, cv.y, cv.z + t / 2 + RING_W)
			for c in nc:
				if cit_in[c] != 0 and obs[c] == C_OPEN:
					keep[c] = 1
			# Its gate faces the agora; towers at the other corners.
			var want_c := FM.atan2_a(py - cv.y, px - cv.x)
			var cbest := 0
			var cbd := 1 << 20
			var cnx: PackedInt32Array = ced["nx"]
			var cny: PackedInt32Array = ced["ny"]
			var clen: PackedInt32Array = ced["len"]
			for k in CIT_N:
				var dd := absi(FM.angle_diff(FM.atan2_a(cny[k], cnx[k]), want_c))
				if dd < cbd:
					cbd = dd
					cbest = k
			var ctr := t / 2 + 1
			for k in CIT_N:
				if k == cbest or k == (cbest + 1) % CIT_N:
					continue
				var dk := FM.atan2_a((ced["ey"] as PackedInt32Array)[k], (ced["ex"] as PackedInt32Array)[k])
				if sq != 0:
					_square(obs, ow, oh, cvx[k], cvy[k], ctr, dk, C_TOWER)
				else:
					_disc(obs, ow, oh, cvx[k], cvy[k], ctr, C_TOWER)
				towers.append([cvx[k], cvy[k], ctr, sq, dk])
			var cg := _mk_gate(cvx, cvy, ced, cbest, clen[cbest] / 2, GATE_HW, 0, t, 0, 0, 1)
			gates.append(cg)
			_gate_raster(obs, keep, ow, oh, cg, gates.size() - 1, ced, t, sq, towers)
			_keep_disc(keep, ow, oh, int(cg["ox"]), int(cg["oy"]), 8)
			var cpoly := PackedInt32Array()
			for k in CIT_N:
				cpoly.append(cvx[k])
				cpoly.append(cvy[k])
			cit = {"x": cv.x, "y": cv.y, "rc": cv.z, "poly": cpoly, "gate": gates.size() - 1,
				"ced": ced, "cvx": cvx, "cvy": cvy}
	# ---- streets and the agora.
	var streets: Array = []
	var mouths: Array = []
	var extra := PackedInt32Array()   # more street-graph nodes (x, y pairs)
	var lane_j: Array = []
	for k in 12:
		lane_j.append(_rr(rng, -14, 14))
	if walls > 0:
		for g in n_outer:
			var gd: Dictionary = gates[g]
			if plan == PLAN_OPPIDUM:
				_lane(streets, extra, int(gd["ix"]), int(gd["iy"]), px, py, msw, int(lane_j[g * 2]), int(lane_j[g * 2 + 1]))
			else:
				streets.append([int(gd["ix"]), int(gd["iy"]), px, py, msw])
		if not cit.is_empty():
			var cgd: Dictionary = gates[int(cit["gate"])]
			streets.append([int(cgd["ox"]), int(cgd["oy"]), px, py, msw])
	else:
		var dirs: Array = [256, 512, 0, 768]
		for k in (3 if level == 0 else 4):
			var a: int = dirs[k]
			var l := r0 * 135 / 100
			var ex := cx + FM.cos_a(a) * l / FM.TRIG_ONE
			var ey := cy + FM.sin_a(a) * l / FM.TRIG_ONE
			if coast != 0 and ey < shore_y(cp, ex) + 12:
				continue
			if plan == PLAN_OPPIDUM:
				_lane(streets, extra, px, py, ex, ey, msw, int(lane_j[k * 2]), int(lane_j[k * 2 + 1]))
			else:
				streets.append([px, py, ex, ey, msw])
			mouths.append([ex, ey, a])
	if plan == PLAN_OPPIDUM:
		# A few more lanes out from the open middle.
		for k in 2:
			var a2 := (int(lane_j[8 + k]) * 30 + k * 512 + 128) & 1023
			var l2 := r0 * 70 / 100
			_lane(streets, extra, px, py, cx + FM.cos_a(a2) * l2 / FM.TRIG_ONE, cy + FM.sin_a(a2) * l2 / FM.TRIG_ONE,
				2, int(lane_j[10 + k]), -int(lane_j[10 + k]))
	for s in streets:
		_keep_seg(keep, ow, oh, s[0], s[1], s[2], s[3], s[4])
	var ahs := hs * 13 / 10 if plan == PLAN_OPPIDUM else hs
	_keep_rect(keep, ow, oh, px - ahs, py - ahs, px + ahs, py + ahs)
	# ---- landmarks, then houses.
	var buildings: Array = []
	var lm := _landmarks(p, px, py, ahs, msw, gates, cx, cy, r0, true)
	for b in lm:
		var a: Array = b
		if _rect_free(inside, keep, occ, ow, oh, a[1], a[2], a[3], a[4]):
			_mark_rect(occ, ow, oh, a[1], a[2], a[3], a[4])
			buildings.append([a[1], a[2], a[3], a[4], a[0], a[5], SH_RECT])
	var enclosed := (plan == PLAN_OPPIDUM and level <= 1) or level == 0
	var fdepth: int = o["field_depth"]
	var built_sc := r0 * 1000 / maxi(r0 - fdepth, 20) if enclosed else 1000
	var hb := {"p": p, "inside": inside, "keep": keep, "occ": occ, "obs": obs, "ow": ow, "oh": oh,
		"cx": cx, "cy": cy, "sc": built_sc, "pct": mini(BUILT_PCT[level] + int(o["built_extra"]), 96),
		"buildings": buildings, "extra": extra, "level": level}
	if plan == PLAN_CASTRUM:
		_houses_grid(hb, rng, px, py, int(o["blk_w"]), int(o["blk_s"]), msw)
	elif plan == PLAN_OPPIDUM:
		_houses_round(hb, rng, cx, cy, r0)
	else:
		var two := plan == PLAN_POLIS
		_houses_lattice(hb, rng, px, py, int(o["lat_a"]), int(o["blk_w"]), int(o["blk_l"]), int(o["blk_s"]),
			int(o["seam"]), 1 if two else 0)
		if two:
			_houses_lattice(hb, rng, px, py, int(o["lat_b"]), int(o["blk_w"]), int(o["blk_l"]), int(o["blk_s"]),
				int(o["seam"]), -1)
	for b in buildings:
		var a: Array = b
		if int(a[6]) == SH_RECT:
			_set_rect(obs, ow, oh, a[0], a[1], a[2], a[3], C_BUILDING)
	# ---- vegetation bits.
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
	for j in range(maxi((py - ahs) / 4, 0), mini((py + ahs) / 4 + 1, vh)):
		for i in range(maxi((px - ahs) / 4, 0), mini((px + ahs) / 4 + 1, vw)):
			veg[j * vw + i] |= V_PLAZA
	var post: Array = []
	# Enclosed fields: gardens, pens and a few orchards between the wall and
	# the houses (12 m patches, from the seed).
	if enclosed:
		var fseed := int(p["seed"]) * 2654435761
		for j in vh:
			for i in vw:
				var xm := i * 4 + 2
				var ym := j * 4 + 2
				var oc := mini(ym / 2, oh - 1) * ow + mini(xm / 2, ow - 1)
				if inside[oc] == 0 or keep[oc] != 0 or occ[oc] != 0 or obs[oc] != C_OPEN:
					continue
				if _built_ok(hb, xm, ym):
					continue
				var pid := ((xm / 12) * 7919 + (ym / 12) * 104729 + fseed) & 0x7FFFFFFF
				pid = ((pid ^ (pid >> 13)) * 0x5bd1e995) & 0x7FFFFFFF
				var kind_f := (pid >> 7) % 10
				if kind_f <= 6:
					veg[j * vw + i] |= V_FIELD
				elif kind_f <= 8:
					post.append([xm - 2, ym - 2, xm + 2, ym + 2, 1])
	# ---- wall walkways and stairs.
	var segs: Array = []
	if walls > 0:
		var cut := PackedInt32Array()
		cut.resize(nv)
		for k in nv:
			cut[k] = vt[k] + 1 if vt[k] > 0 else t / 2 + 2
		segs = _segments(vx, vy, ed, gates, cut, t, pp, inner, esea, 0, 0)
		_stairs(obs, inside, ow, oh, segs, t, inner)
		if not cit.is_empty():
			var ccut := PackedInt32Array()
			ccut.resize(CIT_N)
			ccut.fill(t / 2 + 2)
			var cnos := PackedInt32Array()
			cnos.resize(CIT_N)
			cnos.fill(0)
			var csegs := _segments(cit["cvx"], cit["cvy"], cit["ced"], gates, ccut, t, pp, inner, cnos, SEG_CIT, 1)
			_stairs(obs, cit_in, ow, oh, csegs, t, inner)
			segs.append_array(csegs)
	# ---- outside: fields, the approach, ditch, sea.
	var mg: Dictionary = gates[0] if n_outer > 0 else {"x": cx, "y": cy + rmax, "ix": cx, "iy": cy + r0 * 3 / 4}
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
		var kind_v := 1 + _r(rng, 2)
		if k >= nf or level == 2 or walls >= 2:
			continue
		var fx := cx + FM.cos_a(a) * dist / FM.TRIG_ONE
		var fy := cy + FM.sin_a(a) * dist / FM.TRIG_ONE
		if (absi(fx - att_x) < 50 + fw / 2 and fy > cy) or fy + fh / 2 > att_y - 30:
			continue
		if fx - fw / 2 < 4 or fy - fh / 2 < 4 or fx + fw / 2 > w_m - 4:
			continue
		if coast != 0 and fy - fh / 2 < shore_y(cp, fx) + 8:
			continue
		fields.append([fx - fw / 2, fy - fh / 2, fx + fw / 2, fy + fh / 2, kind_v])
	for f in fields:
		var a: Array = f
		if int(a[4]) == 1:
			post.append([a[0], a[1], a[2], a[3], 1])
		else:
			for j in range(maxi(int(a[1]) / 4, 0), mini(int(a[3]) / 4 + 1, vh)):
				for i in range(maxi(int(a[0]) / 4, 0), mini(int(a[2]) / 4 + 1, vw)):
					veg[j * vw + i] |= V_FIELD
	if site == SITE_PLAIN:
		# A straight road out of the main gate, orchards either side of it.
		_veg_seg(veg, vw, vh, att_x, gate_y, att_x, mini(att_y + 60, h_m - 4), 2, V_ROAD)
		var oy0 := gate_y + (60 if walls >= 2 else 35)
		var oy1 := att_y - 40
		if oy1 - oy0 >= 16:
			post.append([att_x - 40, oy0, att_x - 14, oy1, 1])
			post.append([att_x + 14, oy0, att_x + 40, oy1, 1])
	var ditch := 0
	# (Not round an oppidum: the ditch would run into its funnel and leave
	# the attackers one causeway under fire from both arms.)
	if site == SITE_PLAIN and walls == 3 and plan != PLAN_OPPIDUM:
		ditch = 1
		_ditch(obs, inside, ow, oh, vx, vy, esea, gates, n_outer, t / 2 + tow_r + DITCH_GAP, t / 2 + tow_r + DITCH_GAP + DITCH_W)
		var d_out := t / 2 + tow_r + DITCH_GAP + DITCH_W + 8
		for k in nv:
			if esea[k] != 0:
				continue
			var steps := maxi((elen[k] + 19) / 20, 1)
			for s in range(0, steps + 1):
				var al := elen[k] * s / steps
				extra.append(vx[k] + (ee_x[k] * al + en_x[k] * d_out) / FM.TRIG_ONE)
				extra.append(vy[k] + (ee_y[k] * al + en_y[k] * d_out) / FM.TRIG_ONE)
		for g in n_outer:
			var gd: Dictionary = gates[g]
			var gdir: int = gd["dir"]
			extra.append(int(gd["x"]) + FM.cos_a(gdir) * (d_out + 4) / FM.TRIG_ONE)
			extra.append(int(gd["y"]) + FM.sin_a(gdir) * (d_out + 4) / FM.TRIG_ONE)
	var sea := {}
	if coast != 0:
		for i in ow:
			var sy := shore_y(cp, i * 2 + 1)
			for j in range(0, mini((sy - 1 + 1) / 2, oh)):
				var c := j * ow + i
				if obs[c] == C_OPEN:
					obs[c] = C_WATER
		for i in vw:
			var sy2 := shore_y(cp, i * 4 + 2)
			for j in range(0, mini((sy2 - 2 + 3) / 4, vh)):
				veg[j * vw + i] |= V_WATER
		sea = _harbour(o, vx, vy, ed, esea, t, w_m, h_m)
	if ditch != 0:
		for j in vh:
			for i in vw:
				var oc2 := mini(j * 2 + 1, oh - 1) * ow + mini(i * 2 + 1, ow - 1)
				if obs[oc2] == C_DITCH:
					veg[j * vw + i] |= V_DITCH
	excl.append([cx - rmax - 25, cy - rmax - 25, cx + rmax + 25, cy + rmax + 25])
	if walls >= 2:
		excl.append([cx - rmax - 60, cy - rmax - 60, cx + rmax + 60, cy + rmax + 60])
	excl.append([att_x - 40, cy, att_x + 40, att_y + 120])
	excl.append([w_m * 10 / 100, att_y - 20, w_m * 90 / 100, h_m])
	# ---- street graph.
	if not cit.is_empty():
		var ccx: int = cit["x"]
		var ccy: int = cit["y"]
		extra.append(ccx)
		extra.append(ccy)
		var rr := int(cit["rc"]) + t / 2 + 4
		for k in 8:
			var a := k * 128
			extra.append(ccx + FM.cos_a(a) * rr / FM.TRIG_ONE)
			extra.append(ccy + FM.sin_a(a) * rr / FM.TRIG_ONE)
	var nav_nodes := _nav_graph(obs, ow, oh, w_m, h_m, vx, vy, en_x, en_y, ee_x, ee_y, elen, gates,
		cx, cy, r0, t, tow_r, px, py, ahs, streets, PackedInt32Array(), PackedInt32Array(), inside, walls, extra)
	out["obs"] = obs
	out["ow"] = ow
	out["oh"] = oh
	out["obs_on"] = 1
	out["city_on"] = 1
	var poly := PackedInt32Array()
	for k in nv:
		poly.append(vx[k])
		poly.append(vy[k])
	var plaza: Array = [px, py, hs, hs + CAPTURE_EXTRA]
	if not cit.is_empty():
		var chs := maxi(int(cit["rc"]) - t / 2 - 3, 6)
		plaza = [int(cit["x"]), int(cit["y"]), chs, chs + CAPTURE_EXTRA]
		cit.erase("ced")
		cit.erase("cvx")
		cit.erase("cvy")
	var lay := {"cx": cx, "cy": cy, "r0": r0, "level": level, "walls": walls, "def": int(p["def"]),
		"seed": int(p["seed"]), "t": t, "pp": pp, "inner": inner, "wall_h_m": wall_h,
		"build_h_m": BUILD_H[level], "poly": poly, "gates": gates, "towers": towers,
		"plaza": plaza, "agora": [px, py, ahs], "cit": cit,
		"streets": streets, "mouths": mouths, "buildings": buildings,
		"fields": fields, "segs": segs, "att_x": att_x, "att_y": att_y, "nav": nav_nodes,
		"gate_hp": GATE_HP[walls], "plan": plan, "site": site, "coast": coast, "ditch": ditch,
		"sea": sea, "palisade": 1 if level == 0 and walls > 0 else 0, "enclosed": 1 if enclosed else 0,
		"founder": int(p["founder"]), "owner": int(p["owner"]), "banner": int(p["banner"]),
		"post_veg": post}
	out["city"] = lay
	return lay


## A lane from a to b bent twice sideways (j1, j2 metres): three street
## pieces, its bends added to the street graph.
static func _lane(streets: Array, extra: PackedInt32Array, ax: int, ay: int, bx: int, by: int, w: int,
		j1: int, j2: int) -> void:
	var dx := bx - ax
	var dy := by - ay
	var l := maxi(FM.isqrt(dx * dx + dy * dy), 1)
	var nx := -dy * 1000 / l
	var ny := dx * 1000 / l
	var x1 := ax + dx / 3 + nx * j1 / 1000
	var y1 := ay + dy / 3 + ny * j1 / 1000
	var x2 := ax + dx * 2 / 3 + nx * j2 / 1000
	var y2 := ay + dy * 2 / 3 + ny * j2 / 1000
	streets.append([ax, ay, x1, y1, w])
	streets.append([x1, y1, x2, y2, w])
	streets.append([x2, y2, bx, by, w])
	extra.append(x1)
	extra.append(y1)
	extra.append(x2)
	extra.append(y2)


## A house spot lies in the built-up part (not in an enclosure's fields).
static func _built_ok(hb: Dictionary, x: int, y: int) -> bool:
	var sc: int = hb["sc"]
	if sc == 1000:
		return true
	var cx: int = hb["cx"]
	var cy: int = hb["cy"]
	var qx := cx + (x - cx) * sc / 1000
	var qy := cy + (y - cy) * sc / 1000
	var ow: int = hb["ow"]
	var oh: int = hb["oh"]
	if qx < 0 or qy < 0 or qx / 2 >= ow or qy / 2 >= oh:
		return false
	return (hb["inside"] as PackedByteArray)[(qy / 2) * ow + qx / 2] != 0


## Castrum: square insulae on a grid whose main streets cross at the forum.
static func _houses_grid(hb: Dictionary, rng: PackedInt32Array, px: int, py: int, bw: int, sw: int, msw: int) -> void:
	var per := bw + sw
	var kk := EXT / per + 1
	var inside: PackedByteArray = hb["inside"]
	var keep: PackedByteArray = hb["keep"]
	var occ: PackedByteArray = hb["occ"]
	var ow: int = hb["ow"]
	var oh: int = hb["oh"]
	var pct: int = hb["pct"]
	var extra: PackedInt32Array = hb["extra"]
	var blds: Array = hb["buildings"]
	for jj in range(-kk, kk):
		var y0 := py + jj * per + (msw if jj == 0 else sw / 2)
		var y1 := py + (jj + 1) * per - (msw if jj == -1 else sw / 2)
		for ii in range(-kk, kk):
			var x0 := px + ii * per + (msw if ii == 0 else sw / 2)
			var x1 := px + (ii + 1) * per - (msw if ii == -1 else sw / 2)
			var cxs := px + ii * per
			var cys := py + jj * per
			if cxs >= 0 and cys >= 0 and cxs / 2 < ow and cys / 2 < oh and inside[(cys / 2) * ow + cxs / 2] != 0:
				extra.append(cxs)
				extra.append(cys)
			var nxl := maxi((x1 - x0 + 3) / 10, 1)
			var nyl := maxi((y1 - y0 + 3) / 10, 1)
			for ly in nyl:
				for lx in nxl:
					var roll := _r(rng, 100)
					var lx0 := x0 + (x1 - x0) * lx / nxl + 1
					var lx1 := x0 + (x1 - x0) * (lx + 1) / nxl - 1
					var ly0 := y0 + (y1 - y0) * ly / nyl + 1
					var ly1 := y0 + (y1 - y0) * (ly + 1) / nyl - 1
					if roll >= pct or lx1 - lx0 < 4 or ly1 - ly0 < 4:
						continue
					if not _built_ok(hb, (lx0 + lx1) / 2, (ly0 + ly1) / 2):
						continue
					if _rect_free(inside, keep, occ, ow, oh, lx0, ly0, lx1, ly1):
						_mark_rect(occ, ow, oh, lx0, ly0, lx1, ly1)
						var hst := _house_style(hb["p"], inside, ow, oh, hb["cx"], hb["cy"], (lx0 + lx1) / 2, (ly0 + ly1) / 2)
						blds.append([lx0, ly0, lx1, ly1, B_HOUSE, hst, SH_RECT])


## Polis / punic: a grid of blocks turned by `ang` round the agora (lots of
## about 10 m, two rows to a block); `side` +1 / -1 keeps only the lots on
## that side of the seam through the agora (a polis's two grids), 0 all.
static func _houses_lattice(hb: Dictionary, rng: PackedInt32Array, px: int, py: int, ang: int, bw: int, bl: int,
		sw: int, seam: int, side: int) -> void:
	var c := FM.cos_a(ang & 1023)
	var s := FM.sin_a(ang & 1023)
	var pw := bw + sw
	var pl := bl + sw
	var ki := EXT / pw + 2
	var kj := EXT / pl + 2
	var inside: PackedByteArray = hb["inside"]
	var keep: PackedByteArray = hb["keep"]
	var occ: PackedByteArray = hb["occ"]
	var obs: PackedByteArray = hb["obs"]
	var ow: int = hb["ow"]
	var oh: int = hb["oh"]
	var pct: int = hb["pct"]
	var extra: PackedInt32Array = hb["extra"]
	var blds: Array = hb["buildings"]
	var snx := FM.cos_a(seam & 1023)
	var sny := FM.sin_a(seam & 1023)
	var w2 := func(lx: int, ly: int) -> Vector2i:
		return Vector2i(px + (lx * c - ly * s) / FM.TRIG_ONE, py + (lx * s + ly * c) / FM.TRIG_ONE)
	for jj in range(-kj, kj):
		for ii in range(-ki, ki):
			var cr: Vector2i = w2.call(ii * pw, jj * pl)
			if cr.x >= 0 and cr.y >= 0 and cr.x / 2 < ow and cr.y / 2 < oh and inside[(cr.y / 2) * ow + cr.x / 2] != 0:
				if side == 0 or ((cr.x - px) * snx + (cr.y - py) * sny) * side >= 0:
					extra.append(cr.x)
					extra.append(cr.y)
			var bx0 := ii * pw + sw / 2
			var by0 := jj * pl + sw / 2
			var nxl := 2
			var nyl := maxi(bl / 10, 1)
			for ly in nyl:
				for lx in nxl:
					var roll := _r(rng, 100)
					var jx := _r(rng, 3)
					var a0 := bx0 + bw * lx / nxl + 1
					var a1 := bx0 + bw * (lx + 1) / nxl - 1 - (jx if lx == 0 else 0)
					var b0 := by0 + bl * ly / nyl + 1
					var b1 := by0 + bl * (ly + 1) / nyl - 1
					if roll >= pct or a1 - a0 < 4 or b1 - b0 < 4:
						continue
					var mid: Vector2i = w2.call((a0 + a1) / 2, (b0 + b1) / 2)
					if side != 0 and ((mid.x - px) * snx + (mid.y - py) * sny) * side < 0:
						continue
					if not _built_ok(hb, mid.x, mid.y):
						continue
					var q0: Vector2i = w2.call(a0, b0)
					var q1: Vector2i = w2.call(a1, b0)
					var q2: Vector2i = w2.call(a1, b1)
					var q3: Vector2i = w2.call(a0, b1)
					var xs := PackedInt32Array([q0.x, q1.x, q2.x, q3.x])
					var ys := PackedInt32Array([q0.y, q1.y, q2.y, q3.y])
					var cells := _poly_cells(xs, ys, ow, oh)
					if cells.is_empty() or not _cells_free(cells, inside, keep, occ):
						continue
					for cc in cells:
						occ[cc] = 1
						obs[cc] = C_BUILDING
					var hst := _house_style(hb["p"], inside, ow, oh, hb["cx"], hb["cy"], mid.x, mid.y)
					blds.append([mini(mini(q0.x, q1.x), mini(q2.x, q3.x)), mini(mini(q0.y, q1.y), mini(q2.y, q3.y)),
						maxi(maxi(q0.x, q1.x), maxi(q2.x, q3.x)), maxi(maxi(q0.y, q1.y), maxi(q2.y, q3.y)),
						B_HOUSE, hst, SH_QUAD, q0.x, q0.y, q1.x, q1.y, q2.x, q2.y, q3.x, q3.y])


## Oppidum: round houses in clusters (fixed draws per cluster).
static func _houses_round(hb: Dictionary, rng: PackedInt32Array, cx: int, cy: int, r0: int) -> void:
	var inside: PackedByteArray = hb["inside"]
	var keep: PackedByteArray = hb["keep"]
	var occ: PackedByteArray = hb["occ"]
	var obs: PackedByteArray = hb["obs"]
	var ow: int = hb["ow"]
	var oh: int = hb["oh"]
	var pct: int = hb["pct"]
	var blds: Array = hb["buildings"]
	for k in 90:
		var ca := _r(rng, 1024)
		var cd := _rr(rng, 12, 104)
		var nh := _rr(rng, 4, 7)
		var ccx := cx + FM.cos_a(ca) * (R_LEVEL[2] * cd / 100) / FM.TRIG_ONE
		var ccy := cy + FM.sin_a(ca) * (R_LEVEL[2] * cd / 100) / FM.TRIG_ONE
		# Clusters are laid out for a city and pulled in for smaller levels.
		ccx = cx + (ccx - cx) * r0 / R_LEVEL[2]
		ccy = cy + (ccy - cy) * r0 / R_LEVEL[2]
		for h in 7:
			var hx := ccx + _rr(rng, -13, 13)
			var hy := ccy + _rr(rng, -13, 13)
			var hr := _rr(rng, 3, 5)
			var roll := _r(rng, 100)
			if h >= nh or roll >= pct + 4:
				continue
			if not _built_ok(hb, hx, hy):
				continue
			var pad := _octagon(hx, hy, hr + 1)
			var cells_pad := _poly_cells(pad[0], pad[1], ow, oh)
			if cells_pad.is_empty() or not _cells_free(cells_pad, inside, keep, occ):
				continue
			var body := _octagon(hx, hy, hr)
			for cc in _poly_cells(body[0], body[1], ow, oh):
				occ[cc] = 1
				obs[cc] = C_BUILDING
			var hst := _house_style(hb["p"], inside, ow, oh, cx, cy, hx, hy)
			blds.append([hx - hr, hy - hr, hx + hr, hy + hr, B_HOUSE, hst, SH_ROUND, hx, hy, hr])


static func _octagon(x: int, y: int, r: int) -> Array:
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	for k in 8:
		var a := k * 128 + 64
		xs.append(x + FM.cos_a(a) * r / FM.TRIG_ONE)
		ys.append(y + FM.sin_a(a) * r / FM.TRIG_ONE)
	return [xs, ys]


## A coastal city's harbour (scenery: the rules see only the sea and the
## wall): a sea gate in the longest stretch of sea wall and a mole running
## out from it with an elbow; and where routed defenders leave the field
## (along the shore to either side edge).
static func _harbour(o: Dictionary, vx: PackedInt32Array, vy: PackedInt32Array, ed: Dictionary,
		esea: PackedInt32Array, t: int, w_m: int, h_m: int) -> Dictionary:
	var cp: PackedInt32Array = o["cp"]
	var en_x: PackedInt32Array = ed["nx"]
	var en_y: PackedInt32Array = ed["ny"]
	var ee_x: PackedInt32Array = ed["ex"]
	var ee_y: PackedInt32Array = ed["ey"]
	var elen: PackedInt32Array = ed["len"]
	var best := -1
	for k in vx.size():
		if esea[k] != 0 and elen[k] >= 24 and (best < 0 or elen[k] > elen[best]):
			best = k
	var yl := mini(shore_y(cp, 6) + 30, h_m - 8)
	var yr := mini(shore_y(cp, w_m - 6) + 30, h_m - 8)
	var sea := {"gate": [], "moles": [], "flee": [[6, yl], [w_m - 6, yr]]}
	if best < 0:
		return sea
	var l := elen[best]
	var al := l / 2 + clampi(int(o["sea_jit"]) * l / 600, -l / 4, l / 4)
	var gx := vx[best] + ee_x[best] * al / FM.TRIG_ONE
	var gy := vy[best] + ee_y[best] * al / FM.TRIG_ONE
	sea["gate"] = [gx, gy, FM.atan2_a(en_y[best], en_x[best])]
	var ml: int = o["mole_l"]
	var me: int = o["mole_e"]
	var nx := en_x[best]
	var ny := en_y[best]
	var ex := ee_x[best]
	var ey := ee_y[best]
	var b0x := gx + nx * (t / 2) / FM.TRIG_ONE
	var b0y := gy + ny * (t / 2) / FM.TRIG_ONE
	var m1 := _quad_along(b0x, b0y, nx, ny, ex, ey, ml, 4)
	var b1x := b0x + nx * (ml - 4) / FM.TRIG_ONE
	var b1y := b0y + ny * (ml - 4) / FM.TRIG_ONE
	var sgn := 1 if me > 0 else -1
	var m2 := _quad_along(b1x, b1y, ex * sgn, ey * sgn, nx, ny, absi(me), 4)
	sea["moles"] = [m1, m2]
	return sea


## A strip from (x, y) `len` metres along unit (ux, uy) (Q12), `hw` metres
## either side (across (vx2, vy2)): 4 corners as 8 ints.
static func _quad_along(x: int, y: int, ux: int, uy: int, vx2: int, vy2: int, ln: int, hw: int) -> PackedInt32Array:
	var ax := x - vx2 * hw / FM.TRIG_ONE
	var ay := y - vy2 * hw / FM.TRIG_ONE
	var bx := x + vx2 * hw / FM.TRIG_ONE
	var by := y + vy2 * hw / FM.TRIG_ONE
	var dx := ux * ln / FM.TRIG_ONE
	var dy := uy * ln / FM.TRIG_ONE
	return PackedInt32Array([ax, ay, bx, by, bx + dx, by + dy, ax + dx, ay + dy])


# ------------------------------------------------------ wall helpers -----

## Edge outward normals and directions (Q12) and lengths of a polygon; the
## outward side from the polygon's turning sense, or (the original ring)
## away from (cx, cy).
static func _edges(vx: PackedInt32Array, vy: PackedInt32Array, cx: int, cy: int, by_centre: bool) -> Dictionary:
	var nv := vx.size()
	var area := 0
	for k in nv:
		area += vx[k] * vy[(k + 1) % nv] - vx[(k + 1) % nv] * vy[k]
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
		if by_centre:
			if nx * ((ax + bx) / 2 - cx) + ny * ((ay + by) / 2 - cy) < 0:
				nx = -nx
				ny = -ny
		elif area > 0:
			nx = ey
			ny = -ex
		en_x.append(nx)
		en_y.append(ny)
		ee_x.append(ex)
		ee_y.append(ey)
		elen.append(l)
	return {"nx": en_x, "ny": en_y, "ex": ee_x, "ey": ee_y, "len": elen}


## Wall band along a polygon: wall body (outer parapet, inner face) and
## walkway by the distance from the wall line, and the ring road inside
## (kept open) within RING_W of the wall's inner side.
static func _wall_band(obs: PackedByteArray, keep: PackedByteArray, inside: PackedByteArray, ow: int, oh: int,
		vx: PackedInt32Array, vy: PackedInt32Array, t: int, pp: int, inner: int) -> void:
	var nv := vx.size()
	var margin := t / 2 + RING_W + 2
	var wd := PackedInt32Array()  # min distance (cm) to the wall line, cells near it
	wd.resize(ow * oh)
	wd.fill(1 << 30)
	var touched := PackedByteArray()
	touched.resize(ow * oh)
	touched.fill(0)
	for k in nv:
		var ax := vx[k]
		var ay := vy[k]
		var bx := vx[(k + 1) % nv]
		var by := vy[(k + 1) % nv]
		for j in range(maxi((mini(ay, by) - margin) / 2, 0), mini((maxi(ay, by) + margin) / 2 + 1, oh)):
			for i in range(maxi((mini(ax, bx) - margin) / 2, 0), mini((maxi(ax, bx) + margin) / 2 + 1, ow)):
				var d := _seg_dist_cm(i * 200 + 100, j * 200 + 100, ax * 100, ay * 100, bx * 100, by * 100)
				var c := j * ow + i
				touched[c] = 1
				if d < wd[c]:
					wd[c] = d
	var half := t * 50
	for c in ow * oh:
		if touched[c] == 0:
			continue
		var d := wd[c]
		if d > (t / 2 + RING_W) * 100:
			continue
		if d <= half:
			if inside[c] == 0:
				obs[c] = C_WALL if d > (t / 2 - pp) * 100 else C_WALK
			else:
				obs[c] = C_WALL if d > (t / 2 - inner) * 100 else C_WALK
				keep[c] = 1  # no house on the wall
		elif inside[c] != 0:
			keep[c] = 1  # ring road


## A gate on edge e of a polygon at `along` metres: centre, outward
## direction, the points outside / inside it (paths, AI), opening half
## width hw, tower radius gtr (0: none), flags.
static func _mk_gate(vx: PackedInt32Array, vy: PackedInt32Array, ed: Dictionary, e: int, along: int, hw: int,
		gtr: int, t: int, main: int, postern: int, cit: int) -> Dictionary:
	var en_x: int = (ed["nx"] as PackedInt32Array)[e]
	var en_y: int = (ed["ny"] as PackedInt32Array)[e]
	var ee_x: int = (ed["ex"] as PackedInt32Array)[e]
	var ee_y: int = (ed["ey"] as PackedInt32Array)[e]
	var gx := vx[e] + ee_x * along / FM.TRIG_ONE
	var gy := vy[e] + ee_y * along / FM.TRIG_ONE
	return {"edge": e, "along": along, "x": gx, "y": gy, "dir": FM.atan2_a(en_y, en_x),
		"ox": gx + en_x * (t / 2 + 10) / FM.TRIG_ONE, "oy": gy + en_y * (t / 2 + 10) / FM.TRIG_ONE,
		"ix": gx - en_x * (t / 2 + 4) / FM.TRIG_ONE, "iy": gy - en_y * (t / 2 + 4) / FM.TRIG_ONE,
		"hw": hw, "tr": gtr, "main": main, "postern": postern, "cit": cit}


## A gate's towers (either side of the opening), its cells across the wall
## band, and the square kept open inside it.
static func _gate_raster(obs: PackedByteArray, keep: PackedByteArray, ow: int, oh: int, gd: Dictionary, g: int,
		ed: Dictionary, t: int, sq: int, towers: Array) -> void:
	var e: int = gd["edge"]
	var en_x: int = (ed["nx"] as PackedInt32Array)[e]
	var en_y: int = (ed["ny"] as PackedInt32Array)[e]
	var ee_x: int = (ed["ex"] as PackedInt32Array)[e]
	var ee_y: int = (ed["ey"] as PackedInt32Array)[e]
	var hw: int = gd["hw"]
	var gtr: int = gd["tr"]
	if gtr > 0:
		var dir_e := FM.atan2_a(ee_y, ee_x)
		for s in [-1, 1]:
			var tx: int = int(gd["x"]) + s * ee_x * (hw + gtr) / FM.TRIG_ONE
			var ty: int = int(gd["y"]) + s * ee_y * (hw + gtr) / FM.TRIG_ONE
			if sq != 0:
				_square(obs, ow, oh, tx, ty, gtr, dir_e, C_TOWER)
			else:
				_disc(obs, ow, oh, tx, ty, gtr, C_TOWER)
			towers.append([tx, ty, gtr, sq, dir_e])
	# Gate cells: across the whole wall band within the opening.
	var gx: int = gd["x"]
	var gy: int = gd["y"]
	var half := t * 50
	for j in range(maxi((gy - t - hw) / 2, 0), mini((gy + t + hw) / 2 + 1, oh)):
		for i in range(maxi((gx - t - hw) / 2, 0), mini((gx + t + hw) / 2 + 1, ow)):
			var rx := (i * 200 + 100) - gx * 100
			var ry := (j * 200 + 100) - gy * 100
			var al := (rx * ee_x + ry * ee_y) / FM.TRIG_ONE
			var pe := (rx * en_x + ry * en_y) / FM.TRIG_ONE
			if absi(al) <= hw * 100 and absi(pe) <= half + 60:
				obs[j * ow + i] = C_GATE + g
	# Squares kept open either side of the gate.
	_keep_disc(keep, ow, oh, int(gd["ix"]), int(gd["iy"]), 7)


## Walkway segments of a wall polygon between the towers / corners at its
## vertices (cut[k] metres kept clear at vertex k) and the gates (of the
## same wall: cit 0 outer, 1 citadel) on its edges, at least 12 m long;
## SEG_LEN ints each (see SEG_LEN), with a stair STAIR_IN in from each end.
static func _segments(vx: PackedInt32Array, vy: PackedInt32Array, ed: Dictionary, gates: Array,
		cut: PackedInt32Array, t: int, pp: int, inner: int, esea: PackedInt32Array, flags: int,
		cit: int) -> Array:
	var en_x: PackedInt32Array = ed["nx"]
	var en_y: PackedInt32Array = ed["ny"]
	var ee_x: PackedInt32Array = ed["ex"]
	var ee_y: PackedInt32Array = ed["ey"]
	var elen: PackedInt32Array = ed["len"]
	var nv := vx.size()
	var off := (inner - pp) / 2  # walkway centre, outward of the wall line
	var segs: Array = []
	for k in nv:
		var cuts: Array = [[0, cut[k]], [elen[k] - cut[(k + 1) % nv], elen[k]]]
		for gd in gates:
			if int(gd["edge"]) == k and int(gd["cit"]) == cit:
				var ga: int = gd["along"]
				var gw: int = int(gd["hw"]) + 2 * int(gd["tr"]) + 1
				cuts.append([ga - gw, ga + gw])
		cuts.sort_custom(func(a, b): return a[0] < b[0])
		var s0 := 0
		for c in cuts:
			if int(c[0]) - s0 >= 12:
				var s1: int = c[0]
				var e: Array = [vx[k] + (ee_x[k] * s0 + en_x[k] * off) / FM.TRIG_ONE,
					vy[k] + (ee_y[k] * s0 + en_y[k] * off) / FM.TRIG_ONE,
					vx[k] + (ee_x[k] * s1 + en_x[k] * off) / FM.TRIG_ONE,
					vy[k] + (ee_y[k] * s1 + en_y[k] * off) / FM.TRIG_ONE,
					FM.atan2_a(en_y[k], en_x[k])]
				for a in [s0 + STAIR_IN, s1 - STAIR_IN]:
					var wx: int = vx[k] + ee_x[k] * int(a) / FM.TRIG_ONE
					var wy: int = vy[k] + ee_y[k] * int(a) / FM.TRIG_ONE
					e.append(wx + en_x[k] * off / FM.TRIG_ONE)
					e.append(wy + en_y[k] * off / FM.TRIG_ONE)
					e.append(wx - en_x[k] * (t / 2 - inner / 2) / FM.TRIG_ONE)
					e.append(wy - en_y[k] * (t / 2 - inner / 2) / FM.TRIG_ONE)
					e.append(wx - en_x[k] * (t / 2 + RING_W / 2) / FM.TRIG_ONE)
					e.append(wy - en_y[k] * (t / 2 + RING_W / 2) / FM.TRIG_ONE)
				e.append(flags | (SEG_SEA if esea[k] != 0 else 0))
				segs.append(e)
			s0 = maxi(s0, int(c[1]))
	return segs


## Stairs: the wall's inner face (C_WALL cells inside the polygon `mask`)
## within STAIR_HW of each segment end's stair point becomes C_STAIR.
static func _stairs(obs: PackedByteArray, mask: PackedByteArray, ow: int, oh: int, segs: Array, _t: int,
		inner: int) -> void:
	for sg in segs:
		var a: Array = sg
		var dx := int(a[2]) - int(a[0])
		var dy := int(a[3]) - int(a[1])
		var l := maxi(FM.isqrt(dx * dx + dy * dy), 1)
		var ex := dx * FM.TRIG_ONE / l
		var ey := dy * FM.TRIG_ONE / l
		var nx := FM.cos_a(int(a[4]))
		var ny := FM.sin_a(int(a[4]))
		var reach := (inner / 2 + 1) * 100
		for end in 2:
			var sx: int = a[7 + end * 6]
			var sy: int = a[8 + end * 6]
			var r := STAIR_HW + inner / 2 + 2
			for j in range(maxi((sy - r) / 2, 0), mini((sy + r) / 2 + 1, oh)):
				for i in range(maxi((sx - r) / 2, 0), mini((sx + r) / 2 + 1, ow)):
					var c := j * ow + i
					if obs[c] != C_WALL or mask[c] == 0:
						continue
					var rx := i * 200 + 100 - sx * 100
					var ry := j * 200 + 100 - sy * 100
					var al := (rx * ex + ry * ey) / FM.TRIG_ONE
					var pe := (rx * nx + ry * ny) / FM.TRIG_ONE
					if absi(al) <= STAIR_HW * 100 and absi(pe) <= reach:
						obs[c] = C_STAIR


## Ditch outside the land walls: open cells between d0 and d1 metres from
## the wall line, except the causeways in front of the outer gates.
static func _ditch(obs: PackedByteArray, inside: PackedByteArray, ow: int, oh: int, vx: PackedInt32Array,
		vy: PackedInt32Array, esea: PackedInt32Array, gates: Array, n_outer: int, d0: int, d1: int) -> void:
	var nv := vx.size()
	var margin := d1 + 2
	var wd := PackedInt32Array()
	wd.resize(ow * oh)
	wd.fill(1 << 30)
	for k in nv:
		var ax := vx[k]
		var ay := vy[k]
		var bx := vx[(k + 1) % nv]
		var by := vy[(k + 1) % nv]
		for j in range(maxi((mini(ay, by) - margin) / 2, 0), mini((maxi(ay, by) + margin) / 2 + 1, oh)):
			for i in range(maxi((mini(ax, bx) - margin) / 2, 0), mini((maxi(ax, bx) + margin) / 2 + 1, ow)):
				var c := j * ow + i
				if inside[c] != 0:
					continue
				var d := _seg_dist_cm(i * 200 + 100, j * 200 + 100, ax * 100, ay * 100, bx * 100, by * 100)
				if esea[k] != 0:
					d = -1  # by the sea wall: no ditch
				if d < wd[c]:
					wd[c] = d
	for c in ow * oh:
		var d := wd[c]
		if d < d0 * 100 or d > d1 * 100 or obs[c] != C_OPEN:
			continue
		var i := c % ow
		var j := c / ow
		var on_way := false
		for g in n_outer:
			var gd: Dictionary = gates[g]
			var gdir: int = gd["dir"]
			var rx := i * 2 + 1 - int(gd["x"])
			var ry := j * 2 + 1 - int(gd["y"])
			var al := (ry * FM.cos_a(gdir) - rx * FM.sin_a(gdir)) / FM.TRIG_ONE
			var outw := (rx * FM.cos_a(gdir) + ry * FM.sin_a(gdir)) / FM.TRIG_ONE
			if absi(al) <= int(gd["hw"]) + CAUSEWAY_HW and outw > 0:
				on_way = true
				break
		if not on_way:
			obs[c] = C_DITCH


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


## Point (x, y) (m) inside the polygon (crossing count).
static func _pt_in(vx: PackedInt32Array, vy: PackedInt32Array, x: int, y: int) -> bool:
	var n := vx.size()
	var c := false
	for k in n:
		var k2 := (k + 1) % n
		if (vy[k] > y) != (vy[k2] > y):
			var xi := vx[k] + (vx[k2] - vx[k]) * (y - vy[k]) / (vy[k2] - vy[k])
			if x < xi:
				c = not c
	return c


## Distance (m) from (x, y) to the polygon's outline.
static func _poly_dist(vx: PackedInt32Array, vy: PackedInt32Array, x: int, y: int) -> int:
	var n := vx.size()
	var best := 1 << 30
	for k in n:
		var k2 := (k + 1) % n
		best = mini(best, _seg_dist_cm(x * 100, y * 100, vx[k] * 100, vy[k] * 100, vx[k2] * 100, vy[k2] * 100))
	return best / 100


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


## Cells (indices) whose centre lies inside a small polygon (scanline over
## its bounding box).
static func _poly_cells(xs: PackedInt32Array, ys: PackedInt32Array, ow: int, oh: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var nv := xs.size()
	var y0 := ys[0]
	var y1 := ys[0]
	for k in nv:
		y0 = mini(y0, ys[k])
		y1 = maxi(y1, ys[k])
	for j in range(maxi(y0 / 2 - 1, 0), mini(y1 / 2 + 2, oh)):
		var yc := j * 200 + 100
		var cr: Array[int] = []
		for k in nv:
			var ay := ys[k] * 100
			var by := ys[(k + 1) % nv] * 100
			if ay == by:
				continue
			if (yc >= ay and yc < by) or (yc >= by and yc < ay):
				var ax := xs[k] * 100
				var bx := xs[(k + 1) % nv] * 100
				cr.append(ax + (yc - ay) * (bx - ax) / (by - ay))
		if cr.size() < 2:
			continue
		cr.sort()
		var q := 0
		while q + 1 < cr.size():
			var i0 := maxi((cr[q] - 100 + 199) / 200, 0)
			var i1 := mini((cr[q + 1] - 100) / 200, ow - 1)
			for i in range(i0, i1 + 1):
				out.append(j * ow + i)
			q += 2
	return out


static func _cells_free(cells: PackedInt32Array, inside: PackedByteArray, keep: PackedByteArray,
		occ: PackedByteArray) -> bool:
	for c in cells:
		if inside[c] == 0 or keep[c] != 0 or occ[c] != 0:
			return false
	return true


static func _disc(g: PackedByteArray, ow: int, oh: int, x: int, y: int, r: int, v: int) -> void:
	var r2 := r * r * 10000
	for j in range(maxi((y - r) / 2, 0), mini((y + r) / 2 + 1, oh)):
		for i in range(maxi((x - r) / 2, 0), mini((x + r) / 2 + 1, ow)):
			var dx := i * 200 + 100 - x * 100
			var dy := j * 200 + 100 - y * 100
			if dx * dx + dy * dy <= r2:
				g[j * ow + i] = v


## Square of half side r turned to dir.
static func _square(g: PackedByteArray, ow: int, oh: int, x: int, y: int, r: int, dir: int, v: int) -> void:
	var c := FM.cos_a(dir)
	var s := FM.sin_a(dir)
	var rr := r * 142 / 100 + 1
	for j in range(maxi((y - rr) / 2, 0), mini((y + rr) / 2 + 1, oh)):
		for i in range(maxi((x - rr) / 2, 0), mini((x + rr) / 2 + 1, ow)):
			var dx := i * 200 + 100 - x * 100
			var dy := j * 200 + 100 - y * 100
			if absi((dx * c + dy * s) / FM.TRIG_ONE) <= r * 100 and absi((dy * c - dx * s) / FM.TRIG_ONE) <= r * 100:
				g[j * ow + i] = v


## An interval tower: only the part outside the walkway and the town (the
## walkway runs past it).
static func _bastion(obs: PackedByteArray, inside: PackedByteArray, ow: int, oh: int, x: int, y: int, r: int,
		dir: int, sq: int) -> void:
	var c := FM.cos_a(dir)
	var s := FM.sin_a(dir)
	var rr := r * 142 / 100 + 1
	for j in range(maxi((y - rr) / 2, 0), mini((y + rr) / 2 + 1, oh)):
		for i in range(maxi((x - rr) / 2, 0), mini((x + rr) / 2 + 1, ow)):
			var k := j * ow + i
			if inside[k] != 0 or (obs[k] != C_OPEN and obs[k] != C_WALL):
				continue
			var dx := i * 200 + 100 - x * 100
			var dy := j * 200 + 100 - y * 100
			var hit := false
			if sq != 0:
				hit = absi((dx * c + dy * s) / FM.TRIG_ONE) <= r * 100 and absi((dy * c - dx * s) / FM.TRIG_ONE) <= r * 100
			else:
				hit = dx * dx + dy * dy <= r * r * 10000
			if hit:
				obs[k] = C_TOWER


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
## the main streets and the street grid's crossings, and `extra` points
## (x, y pairs: other grids' crossings, lane bends, the citadel, beyond a
## ditch). Edges join nodes up to EDGE_MAX apart with a clear line 3 m wide
## (a gate's cells only for edges to that gate's own node, so a closed gate
## cuts exactly its node). Returns {"x", "y", "gate", "e0", "to", "w"}
## (metres, CSR adjacency).
static func _nav_graph(obs: PackedByteArray, ow: int, oh: int, w_m: int, h_m: int,
		vx: PackedInt32Array, vy: PackedInt32Array, en_x: PackedInt32Array, en_y: PackedInt32Array,
		ee_x: PackedInt32Array, ee_y: PackedInt32Array, elen: PackedInt32Array, gates: Array,
		cx: int, cy: int, r0: int, t: int, tow_r: int, px: int, py: int, hs: int, streets: Array,
		sxs: PackedInt32Array, sys: PackedInt32Array, inside: PackedByteArray, walls: int,
		extra: PackedInt32Array) -> Dictionary:
	var nx := PackedInt32Array()
	var ny := PackedInt32Array()
	var ng := PackedInt32Array()
	# (Returns the node's index, an existing one within 4 m, or -1.)
	var add := func(x: int, y: int, g: int) -> int:
		if x < 4 or y < 4 or x > w_m - 4 or y > h_m - 4:
			return -1
		var c := mini(y / 2, oh - 1) * ow + mini(x / 2, ow - 1)
		var k := obs[c]
		if g < 0 and k != C_OPEN:
			return -1
		for q in nx.size():
			if absi(nx[q] - x) < 4 and absi(ny[q] - y) < 4:
				return q
		nx.append(x)
		ny.append(y)
		ng.append(g)
		return nx.size() - 1
	var gate_links: Array = []  # [gate node, outside node, inside node]
	for g in gates.size():
		var gd: Dictionary = gates[g]
		var n_o: int = add.call(int(gd["ox"]), int(gd["oy"]), -1)
		var n_g: int = add.call(int(gd["x"]), int(gd["y"]), g)
		var n_i: int = add.call(int(gd["ix"]), int(gd["iy"]), -1)
		gate_links.append([n_g, n_o, n_i])
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
	for q in extra.size() / 2:
		add.call(extra[q * 2], extra[q * 2 + 1], -1)
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
	# A gate always joins its own outside and inside points (the 3 m line
	# can clip a wall corner beside a short gate edge, as at a citadel).
	for gl in gate_links:
		var n_g: int = gl[0]
		if n_g < 0 or ng[n_g] < 0:
			continue
		for side in [1, 2]:
			var n_s: int = gl[side]
			if n_s < 0 or n_s == n_g:
				continue
			var linked := false
			for e in adj[n_g]:
				if int(e[0]) == n_s:
					linked = true
			if not linked:
				var dx2 := nx[n_s] - nx[n_g]
				var dy2 := ny[n_s] - ny[n_g]
				var w2 := FM.isqrt((dx2 * dx2 + dy2 * dy2) * 64)
				(adj[n_g] as Array).append([n_s, w2])
				(adj[n_s] as Array).append([n_g, w2])
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
	var fpts := func(arr, start: int, count: int) -> void:
		for q in count:
			arr[start + q * 2] = w_m - int(arr[start + q * 2])
			arr[start + q * 2 + 1] = h_m - int(arr[start + q * 2 + 1])
	lay["cx"] = fx.call(int(lay["cx"]))
	lay["cy"] = fy.call(int(lay["cy"]))
	var poly: PackedInt32Array = lay["poly"]
	fpts.call(poly, 0, poly.size() / 2)
	lay["poly"] = poly
	for gd in lay["gates"]:
		for kx in ["x", "ox", "ix"]:
			gd[kx] = fx.call(int(gd[kx]))
		for ky in ["y", "oy", "iy"]:
			gd[ky] = fy.call(int(gd[ky]))
		gd["dir"] = (int(gd["dir"]) + 512) & 1023
	for tw in lay["towers"]:
		tw[0] = fx.call(int(tw[0]))
		tw[1] = fy.call(int(tw[1]))
		tw[4] = (int(tw[4]) + 512) & 1023
	for key in ["plaza", "agora"]:
		var pl: Array = lay[key]
		pl[0] = fx.call(int(pl[0]))
		pl[1] = fy.call(int(pl[1]))
	var cit: Dictionary = lay["cit"]
	if not cit.is_empty():
		cit["x"] = fx.call(int(cit["x"]))
		cit["y"] = fy.call(int(cit["y"]))
		var cpl: PackedInt32Array = cit["poly"]
		fpts.call(cpl, 0, cpl.size() / 2)
		cit["poly"] = cpl
	for s in lay["streets"]:
		fpts.call(s, 0, 2)
	for m in lay["mouths"]:
		m[0] = fx.call(int(m[0]))
		m[1] = fy.call(int(m[1]))
		m[2] = (int(m[2]) + 512) & 1023
	for list in [lay["buildings"], lay["fields"]]:
		for b in list:
			var x0: int = b[0]
			var y0: int = b[1]
			b[0] = fx.call(int(b[2]))
			b[1] = fy.call(int(b[3]))
			b[2] = fx.call(x0)
			b[3] = fy.call(y0)
	for b in lay["buildings"]:
		if int(b[6]) == SH_QUAD:
			fpts.call(b, 7, 4)
		elif int(b[6]) == SH_ROUND:
			fpts.call(b, 7, 1)
	for s in lay["segs"]:
		fpts.call(s, 0, 2)
		s[4] = (int(s[4]) + 512) & 1023
		fpts.call(s, 5, 6)
	if lay.has("post_veg"):
		for r in lay["post_veg"]:
			var x0: int = r[0]
			var y0: int = r[1]
			r[0] = fx.call(int(r[2]))
			r[1] = fy.call(int(r[3]))
			r[2] = fx.call(x0)
			r[3] = fy.call(y0)
	var sea: Dictionary = lay["sea"]
	if not sea.is_empty():
		var sg: Array = sea["gate"]
		if not sg.is_empty():
			fpts.call(sg, 0, 1)
			sg[2] = (int(sg[2]) + 512) & 1023
		for mo in sea["moles"]:
			fpts.call(mo, 0, 4)
		for fl in sea["flee"]:
			fpts.call(fl, 0, 1)
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
