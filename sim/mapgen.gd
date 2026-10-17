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
##   rocks    [[x, y, r, h_dm], ...] (m; field maps without a river): rock
##            outcrops placed by hand (tests, set pieces: C_ROCK cells, the
##            view's outcrop records and the graph round them, as the
##            generated ones; h_dm their height in decimetres, 0: 10 + 6 r)
##   landforms 1 (default) / 0: cliffs, rock outcrops and woods that follow
##            the land (sim/landforms.gd) on generated hilly ground (rolling,
##            ridge, valley, hill, slope; never on sym maps), and settlements
##            shaped by their ground (shape_of); 0 gives the maps as they
##            were before slice 2d (tests, set pieces)
##
## Grids (final frame, row-major, index = row * width + col):
##   veg  4 m cells: bits 0-1 tree density 0-3, V_URBAN inside a settlement,
##        V_FIELD farm field, V_ROAD street, V_PLAZA, V_WATER sea, V_DITCH
##        (the last five are view only: the rules read obs)
##   obs  2 m cells: C_* kind (building, wall body, walkway, tower, ditch,
##        water, stair, gate g, rock, cliff)
##   land view data of the landforms (cliff lines, outcrops; final frame),
##        copied to BattleSim.map_info["land"] for game/land_layer.gd
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
const Land := preload("res://sim/landforms.gd")

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
const C_GATE := 8      # + gate index (8..12; is_gate())
const C_ROCK := 30     # rock outcrop (landforms, sim/landforms.gd): nobody; missiles pass over (cover in 2b)
const C_CLIFF := 31    # cliff face: nobody; missiles pass over (sight in 2b)

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
const FIELD_STEP := 48                  # field maps with landforms: graph lattice step (m)
const NODE_STEP := 30                   # ring nodes every this many metres
const STAIR_IN := 3                     # a stair this far in from each end of a walkway stretch
const STAIR_HW := 2                     # ... this wide either side
const DITCH_GAP := 10                   # ditch starts this far beyond the towers' reach
const DITCH_W := 6                      # ditch width
const CAUSEWAY_HW := 4                  # causeway half width beyond a gate's opening
const CIT_N := 6                        # citadel wall: corners

## River crossings (scenario "river": {id, kind, seed, bank}; field maps
## only; docs/DESIGN.md "River crossings"). One river across the field
## between the two deployment edges, generated in a canonical frame (the
## far bank, held by sim side `bank`, at the top) from the crossing's own
## seed, then turned 180 degrees when side 0 holds it. Numbers chosen once:
const RIV_HW: Array[int] = [10, 20]     # half width (m): the river 20-40 m wide
const RIV_A1: Array[int] = [8, 18]      # main meander amplitude (m) ...
const RIV_L1: Array[int] = [320, 480]   # ... and wavelength (m); its bend toward the far bank at the crossing
const RIV_A2: Array[int] = [2, 5]       # small wiggle amplitude (m) ...
const RIV_L2: Array[int] = [100, 160]   # ... and wavelength
const RIV_OFF := 40                     # crossing within this of the field's centre line (x, m)
const FORD_W: Array[int] = [12, 20]     # ford width (m, even)
const BRIDGE_W := 6                     # bridge width (m): one unit wide
const RIV_DEPTH := 2                    # river bed / ford below the plain (m) ...
const RIV_BANK := 16                    # ... rising to it over this from the water (max grade ~19 %)
const RISE_H: Array[int] = [3, 6]       # a low rise on each bank (m high) ...
const RISE_R: Array[int] = [45, 70]     # ... radius (m) ...
const RISE_BACK: Array[int] = [45, 80]  # ... its top this far back from the water
const RIV_CLEAR := 6                    # no trees within this of the water
const RIV_ROW := 14                     # nav nodes along each bank this far from the water ...
const RIV_STEP := 30                    # ... this far apart
const RIV_MOUTH := 5                    # crossing mouth nodes this far beyond the water
# River cells (the "rv" grid, 2 m like obs).
const R_LAND := 0
const R_WATER := 1
const R_FORD := 2
const R_BRIDGE := 3

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

## Cell kind k is a gate's (C_GATE + its index).
static func is_gate(k: int) -> bool:
	return k >= C_GATE and k < C_ROCK


## Cell kind k is a landform's (rock or cliff).
static func is_land(k: int) -> bool:
	return k == C_ROCK or k == C_CLIFF


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
	var out := {"seed": int(c.get("seed", 1)), "level": clampi(int(c.get("level", 1)), 0, 2),
		"walls": clampi(int(c.get("walls", 0)), 0, 3), "bld": bld, "def": int(c.get("def", 1)),
		"plan": plan, "coast": 1 if int(c.get("coast", 0)) != 0 else 0, "founder": founder,
		"owner": owner if owner >= 0 else founder, "banner": int(c.get("banner", -2)),
		"bstyle": bstyle, "hstyle": hstyle}
	if c.has("towers"):
		out["towers"] = int(c["towers"])  # (read by the sim: 0 = no tower engines; not the map's)
	if int(c.get("west", 0)) != 0:
		out["west"] = 1  # (the West pack: an open town, phase W; is_west)
	return out


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
	if is_west(p):
		# (A West open town: the band's middle and half its depth.)
		var lv: int = p["level"]
		return Vector3i((w_m / 2) & ~1, W_TOP + W_D[lv] / 2, W_D[lv] / 2)
	var r0: int = R_LEVEL[int(p["level"])]
	var cx := (w_m / 2) & ~1
	var cy := (CITY_TOP + r0 * 112 / 100) & ~1
	return Vector3i(cx, cy, r0)


## Field size (metres, multiples of 4) a city needs around it, given the
## attackers' deployment depth and frontage (metres).
static func city_field(c: Dictionary, att_width_m: int, att_depth_m: int) -> Vector2i:
	var p := city_params(c)
	if is_west(p):
		# A West open town: the band the field's width across (the town is
		# the same whatever the armies), the approach and the attackers below.
		var lv: int = p["level"]
		var ww := (maxi(W_FW[lv], att_width_m + 80) + 3) / 4 * 4
		var hh := (W_TOP + W_D[lv] + W_APPROACH + att_depth_m + 40 + 3) / 4 * 4
		return Vector2i(ww, hh)
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
	var rg := {}
	if not has_city and terr.get("river") is Dictionary:
		rg = river_geom(terr["river"], w_m, h_m)
	# Landforms (slice 2d): cliffs, outcrops and woods that follow the land,
	# on generated hilly ground (not on symmetric test maps; "landforms": 0
	# turns them off and gives the maps as they were before).
	var lkind := int(hgt.get("kind", terr.get("kind", K_FLAT)))
	var land_ok := int(terr.get("landforms", 1)) != 0 and int(hgt.get("on", 0)) != 0 \
		and int(terr.get("sym", 0)) == 0 and lkind >= K_ROLLING and lkind <= 5
	var trocks: Array = terr.get("rocks", [])
	if dens <= 0 and woods.is_empty() and not has_city and blocks.is_empty() and rg.is_empty() and not land_ok \
			and trocks.is_empty():
		return out
	var tseed := int(terr.get("seed", -1))
	if tseed < 0:
		tseed = battle_seed
	if not rg.is_empty():
		tseed = int(rg["seed"])  # a crossing's woods are its own (frozen)
	var key := "%s|%d|%d|%d|%d" % [str(terr), tseed, w_m, h_m, int(hgt.get("on", 0))]
	if key == _cache_key and not _cache.is_empty():
		var hit := _cache.duplicate()
		hit["veg"] = (_cache["veg"] as PackedByteArray).duplicate()
		hit["obs"] = (_cache["obs"] as PackedByteArray).duplicate()
		if _cache.has("rv"):
			hit["rv"] = (_cache["rv"] as PackedByteArray).duplicate()
		if _cache.has("h_flipped"):
			hgt["h"] = (_cache["h_flipped"] as PackedInt32Array).duplicate()
		return hit
	var excl: Array = []  # rectangles [x0, y0, x1, y1] (m) kept free of woods
	var city := {}
	var land := {}
	var pal := int(terr.get("ground", PAL_PLAIN))
	if has_city:
		var cpar := city_params(terr["city"])
		if is_west(cpar):
			city = _city_west(cpar, int(terr.get("kind", K_FLAT)), w_m, h_m, out, excl, hgt, land_ok, pal)
		else:
			city = _city(cpar, int(terr.get("kind", K_FLAT)), w_m, h_m, out, excl,
				hgt if land_ok else {}, pal)
		land = out.get("land_raw", {})
		out.erase("land_raw")
	else:
		# Field battle: the centre of both deployment zones stays clear.
		excl.append([w_m * 15 / 100, h_m / 2 + 72, w_m * 85 / 100, h_m / 2 + 190])
		excl.append([w_m * 15 / 100, h_m / 2 - 190, w_m * 85 / 100, h_m / 2 - 72])
	var rcells: Array = []
	if not rg.is_empty():
		rcells = _river_cells(rg, w_m, h_m)
	if land_ok and not has_city:
		var lctx := {"w_m": w_m, "h_m": h_m, "kind": lkind, "pal": pal, "seed": tseed * 13 + 7, "hgt": hgt,
			"excl": excl, "ref": Vector2i(w_m / 2, h_m / 2 + 130)}
		if not rg.is_empty():
			lctx["river"] = rg
			lctx["obs"] = rcells[0]
		land = Land.place(lctx)
	if not has_city and rg.is_empty() and not trocks.is_empty():
		land = _hand_rocks(land, trocks, w_m, h_m)
	var lcells: PackedByteArray = land.get("cells", PackedByteArray())
	if has_city and not land.is_empty():
		lcells = out["obs"]  # (the landforms are in the settlement's grid already)
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
		elif not rg.is_empty():
			# A crossing: round the field's centre (canonical frame).
			ox = w_m / 2 - 320
			oy = h_m / 2 - 300
			bw = 640
			bh = 600
		_forest(veg, vw, vh, dens, tseed * 31 + 7, hgt, ox, oy, bw, bh, excl, int(terr.get("sym", 0)),
			land_ok, lcells, w_m / 2, h_m / 2, rg)
	for wd in woods:
		var a: Array = wd
		_veg_rect(veg, vw, vh, int(a[0]) - int(a[2]), int(a[1]) - int(a[3]), int(a[0]) + int(a[2]),
			int(a[1]) + int(a[3]), clampi(int(a[4]), 0, 3))
	if has_city:
		_city_post(city, veg, vw, vh)
	if lcells.size() == (w_m / 2) * (h_m / 2) and int(land.get("n", 0)) > 0:
		# No trees on the rocks, nor on a cliff's face (4 m round it).
		var low := w_m / 2
		for c in lcells.size():
			var kc := lcells[c]
			if not is_land(kc):
				continue
			var vi := (c % low) / 2
			var vj := (c / low) / 2
			var rr := 1 if kc == C_CLIFF else 0
			for dj in range(-rr, rr + 1):
				for di in range(-rr, rr + 1):
					var ii := vi + di
					var jj := vj + dj
					if ii >= 0 and jj >= 0 and ii < vw and jj < vh:
						veg[jj * vw + ii] &= ~V_DENS
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
	var lnodes: PackedInt32Array = land.get("nodes", PackedInt32Array())
	if not rg.is_empty():
		_river(out, rg, veg, vw, vh, hgt, w_m, h_m, rcells, lcells if not has_city else PackedByteArray(), lnodes)
	elif not has_city and int(land.get("n", 0)) > 0:
		# Landforms on a field map: the obstacle grid and a graph round them.
		var ow2 := w_m / 2
		var oh2 := h_m / 2
		var obs2: PackedByteArray = out["obs"]
		if obs2.size() != ow2 * oh2:
			obs2 = PackedByteArray()
			obs2.resize(ow2 * oh2)
			obs2.fill(C_OPEN)
		for c in lcells.size():
			if lcells[c] != 0 and obs2[c] == C_OPEN:
				obs2[c] = lcells[c]
		out["obs"] = obs2
		out["ow"] = ow2
		out["oh"] = oh2
		out["obs_on"] = 1
		out["nav"] = _field_nav(obs2, ow2, oh2, w_m, h_m, lnodes)
	if not land.is_empty():
		out["land"] = {"cliffs": land.get("cliffs", []), "rocks": land.get("rocks", [])}
		if not rg.is_empty() and int(rg["flip"]) != 0:
			_flip_land(out["land"], w_m, h_m)
	for k in veg.size():
		if (veg[k] & V_DENS) != 0:
			out["veg_on"] = 1
			break
	if has_city and int(city["def"]) == 0:
		_flip_all(out, hgt, w_m, h_m)
	var flipped := (has_city and int(city["def"]) == 0) or (not rg.is_empty() and int(rg["flip"]) != 0)
	_cache_key = key
	_cache = out.duplicate()
	_cache["veg"] = (out["veg"] as PackedByteArray).duplicate()
	_cache["obs"] = (out["obs"] as PackedByteArray).duplicate()
	if out.has("rv"):
		_cache["rv"] = (out["rv"] as PackedByteArray).duplicate()
	if flipped:
		_cache["h_flipped"] = (hgt["h"] as PackedInt32Array).duplicate()
	return out


## Turn the landforms' view data 180 degrees (x -> w - x, y -> h - y).
## Terrain key "rocks" (tests, set pieces): outcrops by hand, [x, y, r, h_dm]
## in metres (h_dm 0: 10 + 6 r), added to the landforms `land` (or a new
## one): C_ROCK cells (2 m grid), the view's outcrop records and graph
## nodes 5 m round each (as sim/landforms.gd makes them).
static func _hand_rocks(land: Dictionary, rocks: Array, w_m: int, h_m: int) -> Dictionary:
	var ow := w_m / 2
	var oh := h_m / 2
	var out := land.duplicate()
	var cells: PackedByteArray = out.get("cells", PackedByteArray())
	if cells.size() != ow * oh:
		cells = PackedByteArray()
		cells.resize(ow * oh)
		cells.fill(0)
	var recs: Array = (out.get("rocks", []) as Array).duplicate()
	var nodes: PackedInt32Array = (out.get("nodes", PackedInt32Array()) as PackedInt32Array).duplicate()
	var n := int(out.get("n", 0))
	for rk in rocks:
		var a: Array = rk
		var x := int(a[0])
		var y := int(a[1])
		var r := maxi(int(a[2]), 1)
		var hd := int(a[3]) if a.size() > 3 and int(a[3]) > 0 else 10 + 6 * r
		var cx := x * 100
		var cy := y * 100
		var rr := r * 100 + 50  # (a 1 m rock on whole metres still takes the cells round it)
		for j in range(maxi((cy - rr) / 200, 0), mini((cy + rr) / 200, oh - 1) + 1):
			for i in range(maxi((cx - rr) / 200, 0), mini((cx + rr) / 200, ow - 1) + 1):
				var dx := i * 200 + 100 - cx
				var dy := j * 200 + 100 - cy
				if dx * dx + dy * dy <= rr * rr and cells[j * ow + i] == 0:
					cells[j * ow + i] = C_ROCK
					n += 1
		recs.append([(x * 7919 + y * 104729) & 0x7FFF, hd, x, y, r])
		for k in 8:
			var ang := k * 128
			nodes.append(clampi(x + FM.cos_a(ang) * (r + 5) / FM.TRIG_ONE, 2, w_m - 2))
			nodes.append(clampi(y + FM.sin_a(ang) * (r + 5) / FM.TRIG_ONE, 2, h_m - 2))
	out["cells"] = cells
	out["rocks"] = recs
	out["nodes"] = nodes
	out["n"] = n
	if not out.has("cliffs"):
		out["cliffs"] = []
	return out


static func _flip_land(ld: Dictionary, w_m: int, h_m: int) -> void:
	for c in ld["cliffs"]:
		var cl: Dictionary = c
		var pts: PackedInt32Array = cl["p"]
		for q in pts.size() / 2:
			pts[q * 2] = w_m * 100 - pts[q * 2]
			pts[q * 2 + 1] = h_m * 100 - pts[q * 2 + 1]
		cl["p"] = pts
		var dn: PackedInt32Array = cl["dn"]
		for q in dn.size():
			dn[q] = (dn[q] + 512) & 1023
		cl["dn"] = dn
	for r in ld["rocks"]:
		var a: Array = r
		for q in (a.size() - 2) / 3:
			a[2 + q * 3] = w_m - int(a[2 + q * 3])
			a[3 + q * 3] = h_m - int(a[3 + q * 3])


## Street graph on a field map with landforms (final frame): a lattice of
## nodes FIELD_STEP apart on open ground and the nodes round each landform,
## joined by clear 3 m lines up to EDGE_MAX long (pieces joined).
static func _field_nav(obs: PackedByteArray, ow: int, oh: int, w_m: int, h_m: int,
		extra: PackedInt32Array) -> Dictionary:
	var nxs := PackedInt32Array()
	var nys := PackedInt32Array()
	var y := FIELD_STEP / 2
	while y < h_m - 4:
		var x := FIELD_STEP / 2
		while x < w_m - 4:
			_add_node(obs, ow, oh, w_m, h_m, nxs, nys, x, y)
			x += FIELD_STEP
		y += FIELD_STEP
	for q in extra.size() / 2:
		_add_node(obs, ow, oh, w_m, h_m, nxs, nys, extra[q * 2], extra[q * 2 + 1])
	var ng := PackedInt32Array()
	ng.resize(nxs.size())
	ng.fill(-1)
	return _graph(obs, ow, oh, nxs, nys, ng)


## A graph node at (x, y) (m) if that is open ground inside the field and
## no node is within 4 m (else nothing).
static func _add_node(obs: PackedByteArray, ow: int, oh: int, w_m: int, h_m: int, nxs: PackedInt32Array,
		nys: PackedInt32Array, x: int, y: int) -> void:
	if x < 4 or y < 4 or x > w_m - 4 or y > h_m - 4:
		return
	if obs[mini(y / 2, oh - 1) * ow + mini(x / 2, ow - 1)] != C_OPEN:
		return
	for q in nxs.size():
		if absi(nxs[q] - x) < 4 and absi(nys[q] - y) < 4:
			return
	nxs.append(x)
	nys.append(y)


## Edges between the nodes (clear 3 m lines up to EDGE_MAX), pieces joined;
## the graph as the sim loads it.
static func _graph(obs: PackedByteArray, ow: int, oh: int, nxs: PackedInt32Array, nys: PackedInt32Array,
		ng: PackedInt32Array) -> Dictionary:
	var n := nxs.size()
	var adj: Array = []
	for a in n:
		adj.append([])
	for a in n:
		for b in range(a + 1, n):
			var dx := nxs[b] - nxs[a]
			var dy := nys[b] - nys[a]
			if absi(dx) > EDGE_MAX or absi(dy) > EDGE_MAX:
				continue
			var l2 := dx * dx + dy * dy
			if l2 > EDGE_MAX * EDGE_MAX or not _clear_fat(obs, ow, oh, nxs[a], nys[a], nxs[b], nys[b], -1):
				continue
			var wgt := FM.isqrt(l2 * 64)
			(adj[a] as Array).append([b, wgt])
			(adj[b] as Array).append([a, wgt])
	if n > 0:
		_join_components(obs, ow, oh, nxs, nys, ng, adj)
	var e0 := PackedInt32Array()
	var to := PackedInt32Array()
	var ww := PackedInt32Array()
	for a in n:
		e0.append(to.size())
		for e in adj[a]:
			to.append(int(e[0]))
			ww.append(int(e[1]))
	e0.append(to.size())
	return {"x": nxs, "y": nys, "gate": ng, "e0": e0, "to": to, "w": ww}


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
		ox: int, oy: int, bw: int, bh: int, excl: Array, sym: int, land: bool = false,
		lcells: PackedByteArray = PackedByteArray(), ow: int = 0, oh: int = 0, rg: Dictionary = {}) -> void:
	var rng := _rng(seed_v)
	var f := PackedInt32Array()
	f.resize(vw * vh)
	f.fill(0)
	var nb := 4 + dens / 10 + _r(rng, 3)
	for b in nb:
		var bx := ox + _r(rng, bw)
		var by := oy + _r(rng, bh)
		var rad := (28 + _r(rng, 50)) * (70 + dens) / 100
		if land:
			# Long woods lying along the contour where they grow (landforms):
			# 1.7 x as long, 0.6 x as wide.
			var cd := Land.contour_at(hgt, bx, by)
			if cd >= 0:
				_blob_long(f, vw, vh, bx, by, rad * 17 / 10, rad * 6 / 10, cd, 800)
				continue
		_blob(f, vw, vh, bx, by, rad, 1000 if not land else 800)
	var ns := 14 + dens / 3
	for b in ns:
		var bx := ox + _r(rng, bw)
		var by := oy + _r(rng, bh)
		var amp := 420 if _r(rng, 2) == 0 else -420
		_blob(f, vw, vh, bx, by, 8 + _r(rng, 14), amp)
	if land:
		# The land's own terms: valley floors, lower slopes, river banks, the
		# lee of the ridges; no woods on crests, steep faces or rock.
		Land.forest_terms(f, vw, vh, hgt, rg, lcells, ow, oh, seed_v)
	elif int(hgt.get("on", 0)) != 0:
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


## Add amp x (1 - t^2)^2 to the 4 m cells within an ellipse round (x, y):
## half length ra along angle dir, half width rc across (metres); t^2 =
## (along / ra)^2 + (across / rc)^2.
static func _blob_long(f: PackedInt32Array, vw: int, vh: int, x: int, y: int, ra: int, rc: int, dir: int,
		amp: int) -> void:
	ra = maxi(ra, 2)
	rc = maxi(rc, 2)
	var c := FM.cos_a(dir)
	var s := FM.sin_a(dir)
	for j in range(maxi((y - ra) / 4, 0), mini((y + ra) / 4 + 1, vh)):
		var dy := (j * 4 + 2 - y) * 4
		for i in range(maxi((x - ra) / 4, 0), mini((x + ra) / 4 + 1, vw)):
			var dx := (i * 4 + 2 - x) * 4
			var al := (dx * c + dy * s) / FM.TRIG_ONE   # quarter metres
			var ac := (dy * c - dx * s) / FM.TRIG_ONE
			var t2 := al * al * 1024 / (ra * ra * 16) + ac * ac * 1024 / (rc * rc * 16)
			if t2 >= 1024:
				continue
			var u := 1024 - t2
			f[j * vw + i] += amp * (u * u >> 10) / 1024


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

static func _city(p: Dictionary, kind: int, w_m: int, h_m: int, out: Dictionary, excl: Array,
		hgt: Dictionary = {}, pal: int = PAL_PLAIN) -> Dictionary:
	if int(p["plan"]) == PLAN_RING:
		return _city_ring(p, w_m, h_m, out, excl)
	return _city_plan(p, kind, w_m, h_m, out, excl, hgt, pal)


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
static func plan_outline(p: Dictionary, kind: int, w_m: int, land: int = 1) -> Dictionary:
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
	# The town's shape on its ground (landforms, slice 2d): long down a spur,
	# along a hill's contours or the shore, lobed by a few harmonics; the
	# castrum keeps its rectangle and the ring its circle.
	var sh := shape_of(p, kind) if land != 0 and plan != PLAN_CASTRUM and plan != PLAN_RING else PackedInt32Array()
	var high := not sh.is_empty() and (site == SITE_HILL or site == SITE_SPUR)
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
				var rj := _rr(rng, 82, 114)
				var rad := mini(r0 * rj / 100, rmax)
				if not sh.is_empty():
					rad = mini(r0 * (98 + (rj - 98) / 2) / 100 * shape_pm(sh, ang) / 1000, rmax)
				vx.append(cx + FM.cos_a(ang) * rad / FM.TRIG_ONE)
				vy.append(cy + FM.sin_a(ang) * rad / FM.TRIG_ONE)
			var ag_a := (256 + _rr(rng, -200, 200)) & 1023
			var ag_d := r0 * _rr(rng, 15, 28) / 100
			px = cx + FM.cos_a(ag_a) * ag_d / FM.TRIG_ONE
			py = cy + FM.sin_a(ag_a) * ag_d / FM.TRIG_ONE
			cit_ang = (768 + _rr(rng, 90, 210) * (1 if _r(rng, 2) == 0 else -1)) & 1023
			if high:
				# The acropolis on the high point: the hill's top behind the
				# town, the far end of the spur.
				cit_ang = (768 + FM.angle_diff(cit_ang, 768) / 3) & 1023
			if coast != 0:
				cit_ang = (cit_ang + (256 if cit_ang > 768 else -256)) & 1023  # a front corner, off the sea
			cit_dist = r0 * 50 / 100
			if high and site == SITE_HILL:
				cit_dist = r0 * 40 / 100
			cit_r = _rr(rng, 20, 24)
			n_gates = _rr(rng, 2, 4)
			lat_a = _rr(rng, -70, 70)
			lat_b = lat_a + _rr(rng, 70, 130) * (1 if _r(rng, 2) == 0 else -1)
			if high:
				lat_a /= 3  # the main grid's streets along the contours
			seam = _r(rng, 1024)
			blk_w = 2 * _rr(rng, 8, 10)
			blk_l = 2 * _rr(rng, 15, 19)
			blk_s = 4 + _r(rng, 2)
		PLAN_PUNIC:
			var nv2 := 6 + _r(rng, 3)
			for k in nv2:
				var ang2 := (k * 1024 / nv2 + _rr(rng, -15, 15)) & 1023
				var rad2 := r0 * _rr(rng, 94, 106) / 100
				if not sh.is_empty():
					rad2 = mini(rad2 * shape_pm(sh, ang2) / 1000, rmax)
				vx.append(cx + FM.cos_a(ang2) * rad2 / FM.TRIG_ONE)
				vy.append(cy + FM.sin_a(ang2) * rad2 / FM.TRIG_ONE)
			var side_c := _r(rng, 2)
			var jc := _rr(rng, -60, 60)
			var jb := _rr(rng, -120, 120)
			cit_ang = ((512 * side_c + jc) if coast != 0 else (768 + (jb / 3 if high else jb))) & 1023
			cit_dist = r0 * 55 / 100
			cit_r = _rr(rng, 21, 25)
			var away := (cit_ang + 512) & 1023
			px = cx + FM.cos_a(away) * (r0 * 12 / 100) / FM.TRIG_ONE
			py = cy + FM.sin_a(away) * (r0 * 12 / 100) / FM.TRIG_ONE
			tsp = _rr(rng, 18, 24)
			n_gates = 2
			g_want = [256, 512 if _r(rng, 2) == 0 else 0]
			lat_a = _rr(rng, -24, 24)
			if high:
				lat_a /= 3
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
			var dlt := mouth * 163 / maxi(_opp_r(ea, eb, phi, ki, kd, sh, rmax), 1)
			var gw := 2 * (GATE_HW + 2 * trg) + 16
			var done := walls == 0
			for k in 16:
				var a := k * 64
				if walls > 0 and absi(FM.angle_diff(a, phi)) <= dlt + 20:
					continue
				if not done and a > phi:
					done = true
					funnel = _funnel(vx, vy, vt, cx, cy, ea, eb, ki, kd, phi, dlt, depth, skew, gw, tow_r + 2, sh, rmax)
				var r := _opp_r(ea, eb, a, ki, kd, sh, rmax)
				vx.append(cx + FM.cos_a(a) * r / FM.TRIG_ONE)
				vy.append(cy + FM.sin_a(a) * r / FM.TRIG_ONE)
				vt.append(0)
			if not done:
				funnel = _funnel(vx, vy, vt, cx, cy, ea, eb, ki, kd, phi, dlt, depth, skew, gw, tow_r + 2, sh, rmax)
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
		"site": site, "t": t, "tow_r": tow_r, "trg": trg, "rng": rng, "cx": cx, "cy": cy, "r0": r0, "shape": sh}


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


## An oppidum's radius at angle a on its shaped ground (the oval as it
## always was without a shape).
static func _opp_r(ea: int, eb: int, a: int, ki: int, kd: int, sh: PackedInt32Array, rmax: int) -> int:
	var r := _ell_r(ea, eb, a, ki, kd)
	if sh.is_empty():
		return r
	return mini(r * shape_pm(sh, a) / 1000, rmax)


## A settlement's shape on its ground (landforms, slice 2d; its own draws,
## so the plan's draws are as they were): [elongation, three harmonics
## (amplitude, phase), mean offset], all per mille of the radius. A spur
## town runs long down the spur (canonical y) and narrow across it; a hill
## town along the hill's contours (x), as does a town along the shore; the
## harmonics lobe the outline so no two towns are the same oval.
static func shape_of(p: Dictionary, kind: int) -> PackedInt32Array:
	var sd := int(p["seed"])
	var rng := _rng(sd * 31 + 17)
	var site := site_of(kind, sd)
	var e := _rr(rng, -60, 60)
	if site == SITE_SPUR:
		e = _rr(rng, 140, 210)
	elif site == SITE_HILL:
		e = -_rr(rng, 70, 140)
	elif int(p.get("coast", 0)) != 0:
		e = -_rr(rng, 90, 150)
	var sh := PackedInt32Array([e, _rr(rng, 10, 70), _r(rng, 1024), _rr(rng, 40, 100), _r(rng, 1024),
		_rr(rng, 20, 65), _r(rng, 1024), 0])
	var mean := 0
	for k in 32:
		mean += shape_pm(sh, k * 32)
	sh[7] = mean / 32 - 1000
	return sh


## Radius per mille at angle a of shape sh (1000 with no shape).
static func shape_pm(sh: PackedInt32Array, a: int) -> int:
	if sh.is_empty():
		return 1000
	var v := 1000 - sh[0] * FM.cos_a((2 * a) & 1023) / FM.TRIG_ONE
	v += sh[1] * FM.cos_a((a - sh[2]) & 1023) / FM.TRIG_ONE
	v += sh[3] * FM.cos_a((2 * a - sh[4]) & 1023) / FM.TRIG_ONE
	v += sh[5] * FM.cos_a((3 * a - sh[6]) & 1023) / FM.TRIG_ONE
	return clampi(v - sh[7], 700, 1200)


## Append an oppidum's gate funnel to the outline at angle phi: the mouth
## corners (with towers) on the oval and the inner corners, offset to one
## side by `skew` and one arm longer than the other; the gate goes in the
## inner edge. Returns the index of the inner left corner.
static func _funnel(vx: PackedInt32Array, vy: PackedInt32Array, vt: PackedInt32Array, cx: int, cy: int,
		ea: int, eb: int, ki: int, kd: int, phi: int, dlt: int, depth: int, skew: int, gw: int,
		mouth_r: int, sh: PackedInt32Array = PackedInt32Array(), rmax: int = 1 << 20) -> int:
	var ra := _opp_r(ea, eb, (phi - dlt) & 1023, ki, kd, sh, rmax)
	var rb := _opp_r(ea, eb, (phi + dlt) & 1023, ki, kd, sh, rmax)
	var rm := _opp_r(ea, eb, phi, ki, kd, sh, rmax)
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
static func _city_plan(p: Dictionary, kind: int, w_m: int, h_m: int, out: Dictionary, excl: Array,
		hgt: Dictionary = {}, pal: int = PAL_PLAIN) -> Dictionary:
	var level: int = p["level"]
	var walls: int = p["walls"]
	var plan: int = p["plan"]
	var coast: int = p["coast"]
	var o := plan_outline(p, kind, w_m, 0 if hgt.is_empty() else 1)
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
	# ---- landforms round the settlement (slice 2d): cliffs on its hill's
	# or spur's steep flanks, outcrops, sea cliffs along a rocky shore; clear
	# of the walls' reach, the ditch, the approach, the attackers' ground,
	# the fields and orchards.
	if not hgt.is_empty():
		var reach := t / 2 + tow_r + 18 if walls > 0 else 16
		if ditch != 0:
			reach = t / 2 + tow_r + DITCH_GAP + DITCH_W + 14
		var avoid: Array = []
		for f in fields:
			avoid.append(f)
		for r in post:
			avoid.append(r)
		var lctx := {"w_m": w_m, "h_m": h_m, "kind": kind, "pal": pal, "seed": int(p["seed"]) * 7 + 5,
			"hgt": hgt, "obs": obs, "avoid": avoid, "ref": Vector2i(att_x, mini(att_y + 30, h_m - 8)),
			"excl": [[att_x - 45, cy, att_x + 45, att_y + 120], [w_m * 10 / 100, att_y - 20, w_m * 90 / 100, h_m]],
			"poly_x": vx, "poly_y": vy, "poly_clr": reach}
		if walls == 0:
			lctx["open_c"] = Vector2i(cx, cy)
			lctx["open_r"] = r0 * 140 / 100
		if coast != 0:
			lctx["shore"] = cp
			lctx["sea_cliffs"] = 1 if site != SITE_PLAIN or pal == PAL_ROCKY else 0
			lctx["sea_skip"] = [cx - rmax - 40, cx + rmax + 40]
		var ld := Land.place(lctx)
		var lc: PackedByteArray = ld["cells"]
		for c in lc.size():
			if lc[c] != 0 and obs[c] == C_OPEN:
				obs[c] = lc[c]
		extra.append_array(ld["nodes"])
		out["land_raw"] = ld
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
		# Candidate pairs (in, out) by distance (then a, then b), the 24
		# shortest tried in that order. (They are picked one at a time from
		# the list rather than by sorting it all: the same order, far
		# cheaper, as the first or second usually joins.)
		var pd := PackedInt64Array()
		var pa := PackedInt32Array()
		var pb := PackedInt32Array()
		for a in n:
			if comp[a] != 0:
				continue
			for b in n:
				if comp[b] == 0:
					continue
				var dx := nx[b] - nx[a]
				var dy := ny[b] - ny[a]
				pd.append(dx * dx + dy * dy)
				pa.append(a)
				pb.append(b)
		var joined := false
		var np := pd.size()
		var used := PackedByteArray()
		used.resize(np)
		for k in mini(np, 24):
			var bi := -1
			for q in np:
				if used[q] != 0:
					continue
				if bi < 0 or pd[q] < pd[bi] or (pd[q] == pd[bi] and (pa[q] < pa[bi] or (pa[q] == pa[bi] and pb[q] < pb[bi]))):
					bi = q
			used[bi] = 1
			var a: int = pa[bi]
			var b: int = pb[bi]
			var allow := ng[a] if ng[a] >= 0 else ng[b]
			if _clear_fat(obs, ow, oh, nx[a], ny[a], nx[b], ny[b], allow):
				var w := FM.isqrt(int(pd[bi]) * 64)
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


# ------------------------------------------------------------- river ------

## A crossing's geometry from its scenario key {id, kind (0 ford / 1
## bridge), seed, bank (the sim side holding the far bank)} on a field
## w_m x h_m: every number drawn from the seed alone (so the ford and the
## bridge of one seed share their river), the crossing's x range [xa, xb)
## (even metres) about the field's centre line.
static func river_geom(rv: Dictionary, w_m: int, h_m: int) -> Dictionary:
	var sd := int(rv.get("seed", int(rv.get("id", 0)) * 7 + 1)) & 0x7FFFFFFF
	var rng := _rng(sd * 7919 + 4111)
	var hw := _rr(rng, RIV_HW[0], RIV_HW[1])
	var a1 := _rr(rng, RIV_A1[0], RIV_A1[1])
	var l1 := _rr(rng, RIV_L1[0], RIV_L1[1])
	var ph := _rr(rng, -60, 60)
	var a2 := _rr(rng, RIV_A2[0], RIV_A2[1])
	var l2 := _rr(rng, RIV_L2[0], RIV_L2[1])
	var p2 := _r(rng, 1024)
	var off := _rr(rng, -RIV_OFF, RIV_OFF)
	var fw := _rr(rng, FORD_W[0] / 2, FORD_W[1] / 2) * 2
	var rises: Array = []
	for s in 2:
		# [x offset from the crossing, back from the water, radius, height]:
		# s 0 the far bank (canonical top), 1 the near bank.
		rises.append([_rr(rng, -70, 70), _rr(rng, RISE_BACK[0], RISE_BACK[1]), _rr(rng, RISE_R[0], RISE_R[1]),
			_rr(rng, RISE_H[0], RISE_H[1])])
	var kind := clampi(int(rv.get("kind", 0)), 0, 1)
	var cw := BRIDGE_W if kind == 1 else fw
	var xc := w_m / 2 + off
	var xa := (xc - cw / 2) & ~1
	return {"seed": sd, "id": int(rv.get("id", 0)), "kind": kind, "hw": hw, "a1": a1, "l1": l1, "ph": ph,
		"a2": a2, "l2": l2, "p2": p2, "xc": xc, "xa": xa, "xb": xa + cw, "fw": fw, "rises": rises,
		"bank": clampi(int(rv.get("bank", 1)), 0, 1), "flip": 1 if int(rv.get("bank", 1)) == 0 else 0,
		"w": w_m, "h": h_m}


## Canonical centre line's y (cm) at x (m): the main bend's apex (toward
## the far bank, the top) at the crossing, plus a small wiggle.
static func river_y(g: Dictionary, x: int) -> int:
	var d := x - int(g["xc"])
	var a := (d * 1024 / int(g["l1"]) + int(g["ph"])) & 1023
	var b := (d * 1024 / int(g["l2"]) + int(g["p2"])) & 1023
	return int(g["h"]) * 50 - int(g["a1"]) * 100 * FM.cos_a(a) / FM.TRIG_ONE \
		+ int(g["a2"]) * 100 * FM.sin_a(b) / FM.TRIG_ONE


## Final frame (as the battle sees it): the river's centre y (cm) at x (m).
static func river_cy(g: Dictionary, x: int) -> int:
	if int(g["flip"]) != 0:
		return int(g["h"]) * 100 - river_y(g, int(g["w"]) - x)
	return river_y(g, x)


## Final frame: y (cm) of the water's edge facing side `side` (0: the
## bottom bank, 1: the top) at x (m).
static func river_edge(g: Dictionary, x: int, side: int) -> int:
	var c := river_cy(g, x)
	return c + int(g["hw"]) * 100 if side == 0 else c - int(g["hw"]) * 100


## Final frame: the water's edge facing `side` nearest that side's edge of
## the field over [x0, x1] (m; sampled every 2 m), in metres rounded away
## from the water.
static func river_reach(g: Dictionary, x0: int, x1: int, side: int) -> int:
	var best := -(1 << 30) if side == 0 else (1 << 30)
	var x := x0
	while true:
		var e := river_edge(g, clampi(x, 0, int(g["w"])), side)
		best = maxi(best, e) if side == 0 else mini(best, e)
		if x >= x1:
			break
		x = mini(x + 2, x1)
	return (best + 99) / 100 if side == 0 else best / 100


## Final frame: the crossing's mouth on side `side`'s bank (m): the middle
## of the crossing, RIV_MOUTH beyond the water.
static func river_mouth(g: Dictionary, side: int) -> Vector2i:
	var xm := (int(g["xa"]) + int(g["xb"])) / 2
	if int(g["flip"]) != 0:
		xm = int(g["w"]) - xm
	var xa := xm - (int(g["xb"]) - int(g["xa"])) / 2
	var xb := xm + (int(g["xb"]) - int(g["xa"])) / 2
	var y := river_reach(g, xa, xb, side)
	return Vector2i(xm, y + RIV_MOUTH if side == 0 else y - RIV_MOUTH)


## Height features of a crossing (terrain.gd F_BUMP rows, canonical frame):
## a low rise on each bank.
static func river_rises(g: Dictionary) -> Array:
	var out: Array = []
	var xc := int(g["xc"])
	for s in 2:
		var r: Array = g["rises"][s]
		var x := xc + int(r[0])
		var e := river_y(g, x) / 100 + (-int(g["hw"]) if s == 0 else int(g["hw"]))
		var y := e - int(r[1]) if s == 0 else e + int(r[1])
		out.append([1, x, y, int(r[2]), int(r[3])])
	return out


## Carve the river's bed into the canonical height grid (nodes 4 m apart):
## RIV_DEPTH below where it lies, rising to the plain over RIV_BANK.
static func river_carve(h: PackedInt32Array, nx: int, ny: int, g: Dictionary) -> void:
	var hw := int(g["hw"]) * 100
	var band := RIV_BANK * 100
	for i in nx:
		var yc := river_y(g, i * 4)
		for j in ny:
			var d := absi(j * 400 - yc) - hw
			if d >= band:
				continue
			var t := 0
			if d > 0:
				# smoothstep(d / band) in 1/1024
				var u := d * 1024 / band
				t = u * u * (3072 - 2 * u) / (1024 * 1024)
			h[j * nx + i] -= RIV_DEPTH * M * (1024 - t) / 1024


## The river on a field map: rasterise water, ford and bridge (canonical
## frame) into obs (C_WATER where nobody goes; ford and bridge open ground)
## and the rv grid; the sea bit on the water's 4 m cells (the view's water)
## and no trees near it; then turn everything round if side 0 holds the far
## bank, and build the way across (nav graph, final frame) and the layout.
static func _river(out: Dictionary, g: Dictionary, veg: PackedByteArray, vw: int, vh: int, hgt: Dictionary,
		w_m: int, h_m: int, rc: Array = [], lcells: PackedByteArray = PackedByteArray(),
		lnodes: PackedInt32Array = PackedInt32Array()) -> void:
	var ow := w_m / 2
	var oh := h_m / 2
	if rc.is_empty():
		rc = _river_cells(g, w_m, h_m)
	var obs: PackedByteArray = rc[0]
	var rvg: PackedByteArray = rc[1]
	var hw := int(g["hw"]) * 100
	var xa := int(g["xa"])
	var xb := int(g["xb"])
	# Landforms on its banks (canonical frame, clear of the water).
	if lcells.size() == ow * oh:
		for c in lcells.size():
			if lcells[c] != 0 and obs[c] == C_OPEN:
				obs[c] = lcells[c]
	# The view's water (4 m cells whose centre is water or under the bridge)
	# and no trees on or near it.
	var clear := hw + RIV_CLEAR * 100
	for i in vw:
		var x := i * 4 + 2
		var yc := river_y(g, mini(x, w_m))
		for j in range(maxi((yc - clear) / 400 - 1, 0), mini((yc + clear) / 400 + 2, vh)):
			var d := absi((j * 4 + 2) * 100 - yc)
			if d >= clear:
				continue
			var k := j * vw + i
			veg[k] &= ~V_DENS
			var oc := mini(j * 2 + 1, oh - 1) * ow + mini(i * 2 + 1, ow - 1)
			if rvg[oc] == R_WATER or rvg[oc] == R_BRIDGE:
				veg[k] |= V_WATER
	# The crossing's approaches stay clear of trees (40 m either side).
	var ycx := river_y(g, (xa + xb) / 2) / 100
	_veg_rect(veg, vw, vh, xa - 12, ycx - int(g["hw"]) - 40, xb + 12, ycx + int(g["hw"]) + 40, 0)
	out["obs"] = obs
	out["ow"] = ow
	out["oh"] = oh
	out["obs_on"] = 1
	out["rv"] = rvg
	out["riv_on"] = 1
	if int(g["flip"]) != 0:
		for key in ["veg", "obs", "rv"]:
			var gr: PackedByteArray = out[key]
			var gn := gr.size()
			for k in gn / 2:
				var a := gr[k]
				gr[k] = gr[gn - 1 - k]
				gr[gn - 1 - k] = a
		if hgt.has("h"):
			var hh: PackedInt32Array = hgt["h"]
			var n2 := hh.size()
			for k in n2 / 2:
				var a2 := hh[k]
				hh[k] = hh[n2 - 1 - k]
				hh[n2 - 1 - k] = a2
	# The way across (final frame): a row of nodes along each bank, the
	# crossing's two mouths and its middle (and the nodes round the
	# landforms, last).
	var nxs := PackedInt32Array()
	var nys := PackedInt32Array()
	var add := func(x: int, y: int) -> void:
		if x < 4 or y < 4 or x > w_m - 4 or y > h_m - 4:
			return
		if obs[mini(y / 2, oh - 1) * ow + mini(x / 2, ow - 1)] != C_OPEN:
			return
		for q in nxs.size():
			if absi(nxs[q] - x) < 4 and absi(nys[q] - y) < 4:
				return
		nxs.append(x)
		nys.append(y)
	var m0 := river_mouth(g, 0)
	var m1 := river_mouth(g, 1)
	add.call(m0.x, m0.y)
	add.call(m1.x, m1.y)
	add.call(m0.x, river_cy(g, m0.x) / 100)
	for s in 2:
		var k := -(m0.x / RIV_STEP)
		while m0.x + k * RIV_STEP < w_m:
			var x := m0.x + k * RIV_STEP
			k += 1
			if x < 8 or x > w_m - 8:
				continue
			var e := river_reach(g, maxi(x - 16, 0), mini(x + 16, w_m), s)
			add.call(x, e + RIV_ROW if s == 0 else e - RIV_ROW)
	var fl := int(g["flip"]) != 0
	for q in lnodes.size() / 2:
		add.call(w_m - lnodes[q * 2] if fl else lnodes[q * 2], h_m - lnodes[q * 2 + 1] if fl else lnodes[q * 2 + 1])
	var ng := PackedInt32Array()
	ng.resize(nxs.size())
	ng.fill(-1)
	var nav := _graph(obs, ow, oh, nxs, nys, ng)
	var xm := m0.x
	var half := (xb - xa) / 2
	out["river"] = {"kind": int(g["kind"]), "id": int(g["id"]), "seed": int(g["seed"]), "hw": int(g["hw"]),
		"bank": int(g["bank"]), "x0": xm - half, "x1": xm + half, "mouth": [[m0.x, m0.y], [m1.x, m1.y]],
		"geom": g, "nav": nav}


## A crossing's cells (canonical frame): [obs (C_WATER where nobody goes;
## ford and bridge open ground), rv (R_*)].
static func _river_cells(g: Dictionary, w_m: int, h_m: int) -> Array:
	var ow := w_m / 2
	var oh := h_m / 2
	var obs := PackedByteArray()
	obs.resize(ow * oh)
	obs.fill(C_OPEN)
	var rvg := PackedByteArray()
	rvg.resize(ow * oh)
	rvg.fill(R_LAND)
	var hw := int(g["hw"]) * 100
	var xa := int(g["xa"])
	var xb := int(g["xb"])
	var cross := R_BRIDGE if int(g["kind"]) == 1 else R_FORD
	for i in ow:
		var x := i * 2 + 1
		var yc := river_y(g, x)
		var in_x := x >= xa and x < xb
		for j in range(maxi((yc - hw) / 200 - 1, 0), mini((yc + hw) / 200 + 2, oh)):
			if absi((j * 2 + 1) * 100 - yc) >= hw:
				continue
			var c := j * ow + i
			if in_x:
				rvg[c] = cross
			else:
				rvg[c] = R_WATER
				obs[c] = C_WATER
	return [obs, rvg]


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
	if out.has("land"):
		_flip_land(out["land"], w_m, h_m)
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
	if int(lay.get("west", 0)) != 0:
		_w_flip(lay, w_m, h_m)
	var nav: Dictionary = lay["nav"]
	var nxs: PackedInt32Array = nav["x"]
	var nys: PackedInt32Array = nav["y"]
	for k in nxs.size():
		nxs[k] = fx.call(nxs[k])
		nys[k] = fy.call(nys[k])
	nav["x"] = nxs
	nav["y"] = nys


# ------------------------------------------------ West open towns (phase W) --
# docs/DESIGN.md "West open towns (as built, pathing phase W)";
# docs/PATHING_SPEC.md section 7 and addendum 2. A West (Caribbean) European
# settlement with walls 0-2 (city key "west": 1; natives keep the oppidum,
# walls 3 the walled plans) is an open town over 30-55 % of the battle map: a
# band along the shore (or the top of the field inland) the field's width
# across, a waterfront quay, a winding high street through a plaza with the
# church and the governor's house, cross streets down to the landward edge
# (their ends are the street mouths), lanes between them; buildings by kind
# front the roads on irregular lots (uneven setbacks and gaps, small turns,
# wings, lean-tos, yard walls), denser at the quay and the plaza, thinning to
# shacks and plots at the edge; roads bend round rocks, cliffs, big trees and
# the fort, and along the contours; lots step with the slope. Walls 1: a
# harbour fort (a solid bastioned work beside the town on the shore, or on
# the high back corner inland); walls 2: the fort and a stake palisade along
# the landward edge (gaps at the roads). Cover by material: each building
# record carries its height (dm) and material (stone stops balls, timber
# lets some through: sim/battle_sim.gd), props (barrels, crates, carts) and
# low yard walls are small rock cells with their height. Everything from the
# seed with integer maths in a fixed order (the map is sim input).

const B_TAVERN := 7
const B_SHOP := 8
const B_STORE := 9       # food store, bodega
const B_WAREHOUSE := 10
const B_CHANDLER := 11
const B_GOVERNOR := 12
const B_SHACK := 13
const B_LEANTO := 14
const B_FORT := 15       # the harbour fort's core and bastions (solid)
const B_STAKES := 16     # a run of the stake palisade
const MAT_STONE := 0
const MAT_TIMBER := 1
const P_BARRELS := 0     # props (lay "props": [kind, x, y, angle, height dm])
const P_CRATES := 1
const P_CART := 2
const P_WELL := 3
const W_HW: Array[int] = [190, 245, 300]     # town half width by level (m)
const W_D: Array[int] = [150, 205, 255]      # band depth: top (shore) to the landward edge
const W_FW: Array[int] = [440, 560, 680]     # field width at least
const W_TOP := 48                            # canonical y of the town's top (about the shore)
const W_APPROACH := 95                       # landward edge to the attackers' front
const W_MAIN: Array[int] = [8, 10, 12]       # high street width
const W_QUAY: Array[int] = [12, 14, 16]      # quay width
const W_BACK := 7                            # an inland town's back street
const W_LANE := 6
const W_PLAZA: Array[int] = [18, 23, 28]     # plaza half size (a 36-56 m square)
const W_STEP := 10                           # road trace step (m)
const W_EDGE := 34                           # street graph: edges up to this long (the nodes are dense)
const W_PAD := 3                             # m kept between buildings (sides and back): no slivers
const W_SLOPE := 3                           # m of height across a lot at most
const W_STYLE := 4                           # the view's colonial style
# The harbour fort with an inside (slice 2c; docs/DESIGN.md "Forts and
# fighting from buildings"): a bastioned square, low thick walls.
const F_H: Array[int] = [24, 27, 30]         # half side of the trace's square (m) by level
const F_B: Array[int] = [13, 14, 15]         # a bastion's salient this far out from the corner (both axes)
const F_G := 9                               # its gorge (where the flank meets the curtain) this far from the corner ...
const F_F := 6                               # ... and its flank this long, square to the curtain
const F_T := 10                              # wall thickness (an earth-backed rampart faced in stone)
const F_PP := 2                              # outer parapet
const F_WALL_H := 6                          # walkway height above the ground
const F_WALLS := 2                           # the sim's wall level for the fort (gate, ladders, battlements)
const F_DITCH_GAP := 2                       # the ditch this far beyond the wall's outer face ...
const F_DITCH := 6                           # ... and this wide (land side; a causeway at each gate)
const B_MAGAZINE := 17                       # the fort's powder magazine (stone, vaulted)


## A West European open town (phase W) rather than a walled plan.
static func is_west(p: Dictionary) -> bool:
	return int(p.get("west", 0)) != 0 and int(p.get("walls", 0)) < 3 and int(p.get("founder", 0)) != CUL_CELTIC


## A West town's shore (MapGen.coast_params' layout, read by shore_y): along
## the town's top, gently sloping, bending beyond it.
static func west_coast(p: Dictionary, w_m: int) -> PackedInt32Array:
	var lv: int = p["level"]
	var rng := _rng(int(p["seed"]) * 13 + 211)
	var cx := (w_m / 2) & ~1
	return PackedInt32Array([W_TOP - 2, _rr(rng, -25, 25), cx, W_HW[lv] + 30, _rr(rng, -300, 300),
		_rr(rng, 3, 7), _r(rng, 1024), _rr(rng, 2, 4), _r(rng, 1024), W_TOP + W_D[lv] / 2])


## A West town's outline and fixed parameters (canonical frame), from the
## seed alone in a fixed order (shared with sim/terrain.gd: the plaza's and
## the fort's ground). Returns {cx, cy, r0, hw, dep, top, bot, cp (shore,
## coast only), the landward edge's waves, plaza px py hs, the high street's
## rail, fort {x, y, h, b, dir} (walls >= 1), vx vy (the outline), site}.
static func west_outline(p: Dictionary, kind: int, w_m: int) -> Dictionary:
	var level: int = p["level"]
	var walls: int = p["walls"]
	var coast: int = p["coast"]
	var sd: int = p["seed"]
	var rng := _rng(sd * 17 + 9)
	var cx := (w_m / 2) & ~1
	var hw: int = W_HW[level]
	var dep: int = W_D[level]
	var top := W_TOP
	var bot := top + dep
	var cp := west_coast(p, w_m) if coast != 0 else PackedInt32Array()
	var o := {"cx": cx, "cy": top + dep / 2, "r0": dep / 2, "hw": hw, "dep": dep, "top": top, "bot": bot,
		"cp": cp, "coast": coast, "site": site_of(kind, sd), "level": level}
	o["ba1"] = _rr(rng, 6, 14)
	o["bl1"] = _rr(rng, 140, 260)
	o["bp1"] = _r(rng, 1024)
	o["ba2"] = _rr(rng, 3, 7)
	o["bl2"] = _rr(rng, 50, 90)
	o["bp2"] = _r(rng, 1024)
	o["lean"] = _rr(rng, -40, 40)
	var hs: int = W_PLAZA[level]
	o["hs"] = hs
	o["px"] = cx + _rr(rng, -hw / 5, hw / 5)
	o["py"] = top + dep * (36 if coast != 0 else 44) / 100 + _rr(rng, -8, 8)
	o["ra1"] = _rr(rng, 9, 18)
	o["rl1"] = _rr(rng, 200, 320)
	o["rp1"] = _r(rng, 1024)
	o["ra2"] = _rr(rng, 3, 7)
	o["rl2"] = _rr(rng, 70, 120)
	o["rp2"] = _r(rng, 1024)
	var fside := 1 if _r(rng, 2) == 0 else -1
	var fh: int = F_H[level]
	var fb: int = F_B[level]
	var fjit := _rr(rng, -6, 6)
	o["fort"] = {}
	if walls >= 1:
		# (Slice 2c: a fort with an inside; the trace's square half side fh,
		# its bastions' salients fb out from the corners along both axes.)
		var fx := cx + fside * (hw - fh - fb - 10) + fjit
		var fy := top + fh + fb + 4
		var fdir := 0
		if coast != 0:
			fdir = FM.atan2_a(shore_y(cp, fx + 20) - shore_y(cp, fx - 20), 40)
			fy = shore_y(cp, fx) + fh + 1  # (its seaward curtain on the shore, the sea bastions in the water)
		o["fort"] = {"x": fx, "y": fy, "h": fh, "b": fb, "dir": fdir, "side": fside, "level": level,
			"ext": fh + fb + F_T / 2 + F_DITCH_GAP + F_DITCH + 4}
	# The outline: the top (the shore, or the top), the sides, the landward edge.
	var vx := PackedInt32Array()
	var vy := PackedInt32Array()
	var x := cx - hw
	while x < cx + hw:
		vx.append(x)
		vy.append(_w_top(o, x))
		x += 30
	vx.append(cx + hw)
	vy.append(_w_top(o, cx + hw))
	x = cx + hw
	while x > cx - hw:
		vx.append(x)
		vy.append(_w_bot(o, x))
		x -= 24
	vx.append(cx - hw)
	vy.append(_w_bot(o, cx - hw))
	o["vx"] = vx
	o["vy"] = vy
	return o


## The town's top edge at x (the shore, or W_TOP inland).
static func _w_top(o: Dictionary, x: int) -> int:
	if int(o["coast"]) != 0:
		return shore_y(o["cp"], x)
	return int(o["top"])


## The landward edge at x: two waves and a lean, rounded at the ends.
static func _w_bot(o: Dictionary, x: int) -> int:
	var cx: int = o["cx"]
	var d := x - cx
	var y: int = int(o["bot"]) + int(o["ba1"]) * FM.sin_a((d * 1024 / int(o["bl1"]) + int(o["bp1"])) & 1023) / FM.TRIG_ONE \
		+ int(o["ba2"]) * FM.sin_a((d * 1024 / int(o["bl2"]) + int(o["bp2"])) & 1023) / FM.TRIG_ONE \
		+ int(o["lean"]) * d / 1000
	var ex := absi(d) - (int(o["hw"]) - 44)
	if ex > 0:
		y -= ex * ex / 36
	return maxi(y, _w_top(o, x) + 30)


## The high street's line (y at x): through the plaza's middle, winding.
static func _w_rail(o: Dictionary, x: int) -> int:
	var px: int = o["px"]
	var f := func(xx: int) -> int:
		return int(o["ra1"]) * FM.sin_a((xx * 1024 / int(o["rl1"]) + int(o["rp1"])) & 1023) / FM.TRIG_ONE \
			+ int(o["ra2"]) * FM.sin_a((xx * 1024 / int(o["rl2"]) + int(o["rp2"])) & 1023) / FM.TRIG_ONE
	return int(o["py"]) + f.call(x) - f.call(px)


## Ground height (sim units) at (x, y) m: the nearest 4 m node (0 without).
static func _w_h(hgt: Dictionary, x: int, y: int) -> int:
	if hgt.is_empty() or int(hgt.get("on", 0)) == 0:
		return 0
	var nx := int(hgt["nx"])
	var ny := int(hgt["ny"])
	var h: PackedInt32Array = hgt["h"]
	return h[clampi((y + 2) / 4, 0, ny - 1) * nx + clampi((x + 2) / 4, 0, nx - 1)]


## No blocked cell (blk) within r m of (x, y), and well inside the field
## (`sat`: blk summed, (ow + 1) x (oh + 1); a box with none is free at once).
static func _w_free(blk: PackedByteArray, ow: int, oh: int, x: int, y: int, r: int,
		sat: PackedInt32Array = PackedInt32Array()) -> bool:
	if x < 4 or y < 4 or x > ow * 2 - 4 or y > oh * 2 - 4:
		return false
	if not sat.is_empty():
		var i0 := maxi((x - r) / 2, 0)
		var j0 := maxi((y - r) / 2, 0)
		var i1 := mini((x + r) / 2 + 1, ow)
		var j1 := mini((y + r) / 2 + 1, oh)
		var w1 := ow + 1
		if sat[j1 * w1 + i1] - sat[j0 * w1 + i1] - sat[j1 * w1 + i0] + sat[j0 * w1 + i0] == 0:
			return true
	var r2 := r * r * 10000
	for j in range(maxi((y - r) / 2, 0), mini((y + r) / 2 + 1, oh)):
		for i in range(maxi((x - r) / 2, 0), mini((x + r) / 2 + 1, ow)):
			var dx := i * 200 + 100 - x * 100
			var dy := j * 200 + 100 - y * 100
			if dx * dx + dy * dy <= r2 and blk[j * ow + i] != 0:
				return false
	return true


## A road from the last point of `pts` (x, y pairs, m) toward (gx, gy),
## W_STEP a step, bending round what `blk` marks (a free disc of hw + 1 m
## ahead), at most 96 angle units off the goal's bearing in one go and `wig`
## of random bend a step; with heights (`lvl` 1) a step costs its rise too,
## so the road keeps along the contours. Stops when nothing ahead is free.
static func _w_trace(wc: Dictionary, pts: PackedInt32Array, gx: int, gy: int, hw: int, lvl: int, wig: int) -> void:
	var blk: PackedByteArray = wc["blk"]
	var ow: int = wc["ow"]
	var oh: int = wc["oh"]
	var hgt: Dictionary = wc["hgt"]
	var rng: PackedInt32Array = wc["rng"]
	var sat: PackedInt32Array = wc.get("bsat", PackedInt32Array())
	var n := pts.size()
	var px := pts[n - 2]
	var py := pts[n - 1]
	var head := FM.atan2_a(gy - py, gx - px)
	if n >= 4:
		head = FM.atan2_a(py - pts[n - 3], px - pts[n - 4])
	var steps := FM.approx_len(gx - px, gy - py) * 2 / W_STEP + 4
	for it in steps:
		var dx := gx - px
		var dy := gy - py
		if FM.approx_len(dx, dy) <= W_STEP + 2:
			if _w_free(blk, ow, oh, gx, gy, hw + 1, sat):
				pts.append(gx)
				pts.append(gy)
			return
		var want := FM.atan2_a(dy, dx)
		if wig > 0:
			want = (want + _rr(rng, -wig, wig)) & 1023
		want = (head + clampi(FM.angle_diff(head, want), -96, 96)) & 1023
		var best := -1
		var best_s := 1 << 30
		var h0 := _w_h(hgt, px, py) if lvl != 0 else 0
		for q in 7:
			var off: int = [0, 40, -40, 90, -90, 150, -150][q]
			var a := (want + off) & 1023
			var qx := px + FM.cos_a(a) * W_STEP / FM.TRIG_ONE
			var qy := py + FM.sin_a(a) * W_STEP / FM.TRIG_ONE
			if not _w_free(blk, ow, oh, qx, qy, hw + 1, sat):
				continue
			var s := absi(off) * 4
			if lvl != 0:
				s += absi(_w_h(hgt, qx, qy) - h0) * 160 / M
			if s < best_s:
				best_s = s
				best = a
		if best < 0:
			return
		head = best
		px += FM.cos_a(best) * W_STEP / FM.TRIG_ONE
		py += FM.sin_a(best) * W_STEP / FM.TRIG_ONE
		pts.append(px)
		pts.append(py)


## A road through waypoints (x, y pairs): traced leg by leg.
static func _w_road(wc: Dictionary, way: PackedInt32Array, hw: int, lvl: int, wig: int) -> PackedInt32Array:
	var pts := PackedInt32Array([way[0], way[1]])
	for q in range(1, way.size() / 2):
		_w_trace(wc, pts, way[q * 2], way[q * 2 + 1], hw, lvl, wig)
	return pts


## Point at arc length s along polyline pts (cumulative lengths cum):
## [x, y, ex, ey] (m; the direction there, Q12).
static func _w_at(pts: PackedInt32Array, cum: PackedInt32Array, s: int) -> PackedInt32Array:
	var n := pts.size() / 2
	var k := 0
	while k < n - 2 and cum[k + 1] < s:
		k += 1
	var ax := pts[k * 2]
	var ay := pts[k * 2 + 1]
	var dx := pts[k * 2 + 2] - ax
	var dy := pts[k * 2 + 3] - ay
	var l := maxi(cum[k + 1] - cum[k], 1)
	var t := clampi(s - cum[k], 0, l)
	var ll := maxi(FM.isqrt(dx * dx + dy * dy), 1)
	return PackedInt32Array([ax + dx * t / l, ay + dy * t / l, dx * FM.TRIG_ONE / ll, dy * FM.TRIG_ONE / ll])


## Density 8-96 at (x, y): high at the top (the quay) and round the plaza,
## low at the landward edge and the town's ends.
static func _w_dens(wc: Dictionary, x: int, y: int) -> int:
	var o: Dictionary = wc["o"]
	var dep: int = o["dep"]
	var hw: int = o["hw"]
	var bv: PackedInt32Array = wc["botv"]
	var de := clampi((bv[clampi(x, 0, bv.size() - 1)] - y) * 100 / dep, 0, 100)
	var dp := FM.approx_len(x - int(o["px"]), y - int(o["py"]))
	var core := maxi(0, 100 - dp * 100 / maxi(hw * 6 / 10, 1))
	var side := clampi((hw - absi(x - int(o["cx"]))) * 100 / 60, 0, 100)
	var d := 30 + de * 42 / 100 + core * 34 / 100
	d = d * (50 + side * 50 / 100) / 100
	return clampi(d + [-6, 2, 8][int(o["level"])], 8, 96)


## A building kind for a lot on road kind rk (0 quay / back street, 1 high
## street, 2 cross street, 3 lane) at density dens.
static func _w_kind(rng: PackedInt32Array, rk: int, dens: int, coast: int) -> int:
	var r := _r(rng, 100)
	if dens < 34:
		return B_SHACK if r < 55 else B_HOUSE
	if rk == 0 and coast != 0:
		if r < 30:
			return B_WAREHOUSE
		if r < 48:
			return B_CHANDLER
		if r < 70:
			return B_TAVERN
		if r < 86:
			return B_STORE
		return B_HOUSE
	if rk == 1:
		if r < 26:
			return B_SHOP
		if r < 44:
			return B_TAVERN
		if r < 60:
			return B_STORE
		return B_HOUSE
	if rk == 3:
		return B_SHACK if r < 30 else B_HOUSE
	if r < 9:
		return B_SHOP
	if r < 18:
		return B_TAVERN
	if r < 26:
		return B_STORE
	if r < 30 and rk == 0:
		return B_WAREHOUSE
	if dens < 50 and r > 84:
		return B_SHACK
	return B_HOUSE


## Frontage, depth (m) and height (dm) of a building of kind kd.
static func _w_size(rng: PackedInt32Array, kd: int) -> Vector3i:
	match kd:
		B_SHACK:
			return Vector3i(_rr(rng, 5, 7), _rr(rng, 4, 6), _rr(rng, 27, 32))
		B_TAVERN:
			return Vector3i(_rr(rng, 10, 14), _rr(rng, 8, 11), _rr(rng, 55, 65))
		B_SHOP:
			return Vector3i(_rr(rng, 7, 10), _rr(rng, 7, 9), _rr(rng, 42, 50))
		B_STORE:
			return Vector3i(_rr(rng, 8, 12), _rr(rng, 7, 10), _rr(rng, 42, 50))
		B_WAREHOUSE:
			return Vector3i(_rr(rng, 14, 22), _rr(rng, 9, 13), _rr(rng, 60, 70))
		B_CHANDLER:
			return Vector3i(_rr(rng, 9, 13), _rr(rng, 7, 10), _rr(rng, 48, 55))
		B_GOVERNOR:
			return Vector3i(_rr(rng, 18, 22), _rr(rng, 13, 16), _rr(rng, 70, 80))
	return Vector3i(_rr(rng, 7, 11), _rr(rng, 6, 9), _rr(rng, 42, 52))


## Stone or timber for a building of kind kd (Spanish towns build more in
## masonry, the English, French and Dutch more in timber).
static func _w_mat(rng: PackedInt32Array, kd: int, founder: int) -> int:
	var pct := 45
	match kd:
		B_SHACK, B_LEANTO, B_STAKES:
			return MAT_TIMBER
		B_GOVERNOR, B_TEMPLE, B_FORT, B_BARRACKS:
			return MAT_STONE
		B_WAREHOUSE:
			pct = 70
		B_TAVERN:
			pct = 40
		B_CHANDLER:
			pct = 30
		B_HOUSE:
			pct = 60 if founder == CUL_LATIN else 35
	return MAT_STONE if _r(rng, 100) < pct else MAT_TIMBER


## Cells of a quad (corners in cm, 8 ints) as integer-metre corners and
## its cells: [xs (m), ys (m), cells].
static func _w_cells(q: PackedInt32Array, ow: int, oh: int) -> Array:
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	for k in 4:
		xs.append((q[k * 2] + 50) / 100)
		ys.append((q[k * 2 + 1] + 50) / 100)
	return [xs, ys, _poly_cells(xs, ys, ow, oh)]


## A quad (cm) from front-left corner (ax, ay) cm: `fw` m along u, `fd` m
## along n (Q12 unit vectors), grown by `gs` m at the sides, `gb` m at the
## back and `gf` at the front.
static func _w_quad(ax: int, ay: int, ux: int, uy: int, nx: int, ny: int, fw: int, fd: int, gs: int, gb: int,
		gf: int = 0) -> PackedInt32Array:
	var x0 := ax - ux * gs * 100 / FM.TRIG_ONE - nx * gf * 100 / FM.TRIG_ONE
	var y0 := ay - uy * gs * 100 / FM.TRIG_ONE - ny * gf * 100 / FM.TRIG_ONE
	var lx := ux * (fw + 2 * gs) * 100 / FM.TRIG_ONE
	var ly := uy * (fw + 2 * gs) * 100 / FM.TRIG_ONE
	var dx := nx * (fd + gb + gf) * 100 / FM.TRIG_ONE
	var dy := ny * (fd + gb + gf) * 100 / FM.TRIG_ONE
	return PackedInt32Array([x0, y0, x0 + lx, y0 + ly, x0 + lx + dx, y0 + ly + dy, x0 + dx, y0 + dy])


## Quad q (cm; corners front-left, front-right, back-right, back-left
## along axes u, n) grown by g cm all round.
static func _w_grow(q: PackedInt32Array, ux: int, uy: int, nx: int, ny: int, g: int) -> PackedInt32Array:
	var out := q.duplicate()
	var su: Array[int] = [-1, 1, 1, -1]
	var sn: Array[int] = [-1, -1, 1, 1]
	for k in 4:
		out[k * 2] += (ux * su[k] + nx * sn[k]) * g / FM.TRIG_ONE
		out[k * 2 + 1] += (uy * su[k] + ny * sn[k]) * g / FM.TRIG_ONE
	return out


## Try to put a building (quad from front-left corner a, cm; axes u, n)
## where nothing else is: its cells inside the town, off the roads, the
## blocked ground and other buildings (`par`: one it may touch, its own
## parent), W_PAD m clear of other buildings at its sides and back, on
## ground that rises at most W_SLOPE across it. Returns the record (and
## marks it) or [].
static func _w_put(wc: Dictionary, ax: int, ay: int, ux: int, uy: int, nx: int, ny: int, fw: int, fd: int,
		kd: int, hd: int, mat: int, par: int) -> Array:
	var ow: int = wc["ow"]
	var oh: int = wc["oh"]
	var inside: PackedByteArray = wc["inside"]
	var keep: PackedByteArray = wc["keep"]
	var blk: PackedByteArray = wc["blk"]
	var own: PackedInt32Array = wc["own"]
	var obs: PackedByteArray = wc["obs"]
	var body := _w_quad(ax, ay, ux, uy, nx, ny, fw, fd, 0, 0)
	# (A quick look first: its middle and corners.)
	for k in 5:
		var qx := (body[0] + body[2] + body[4] + body[6]) / 400 if k == 4 else body[k * 2] / 100
		var qy := (body[1] + body[3] + body[5] + body[7]) / 400 if k == 4 else body[k * 2 + 1] / 100
		if qx < 0 or qy < 0 or qx >= ow * 2 or qy >= oh * 2:
			return []
		var qc := (qy / 2) * ow + qx / 2
		if inside[qc] == 0 or keep[qc] != 0 or blk[qc] != 0 or (own[qc] != 0 and own[qc] != par + 1):
			return []
	# (Its cells: those within 0.6 m of the drawn outline, so the drawing
	# never overhangs open ground a man can stand on.)
	var cells: PackedInt32Array = (_w_cells(_w_grow(body, ux, uy, nx, ny, 60), ow, oh) as Array)[2]
	if cells.size() < 4:
		return []
	for c in cells:
		if inside[c] == 0 or keep[c] != 0 or blk[c] != 0 or obs[c] != C_OPEN or (own[c] != 0 and own[c] != par + 1):
			return []
	var pad := _w_quad(ax, ay, ux, uy, nx, ny, fw, fd, W_PAD, W_PAD, W_PAD)
	var pc: Array = _w_cells(pad, ow, oh)
	for c in pc[2] as PackedInt32Array:
		if blk[c] != 0 or (own[c] != 0 and own[c] != par + 1):
			return []
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	for k in 4:
		xs.append((body[k * 2] + 50) / 100)
		ys.append((body[k * 2 + 1] + 50) / 100)
	var hgt: Dictionary = wc["hgt"]
	if not hgt.is_empty():
		var lo := 1 << 40
		var hi := -(1 << 40)
		for k in 4:
			var hv := _w_h(hgt, xs[k], ys[k])
			lo = mini(lo, hv)
			hi = maxi(hi, hv)
		if hi - lo > W_SLOPE * M:
			return []
	var blds: Array = wc["buildings"]
	var idx := blds.size()
	for c in cells:
		own[c] = idx + 1
		obs[c] = C_BUILDING
	var rec: Array = [mini(mini(xs[0], xs[1]), mini(xs[2], xs[3])), mini(mini(ys[0], ys[1]), mini(ys[2], ys[3])),
		maxi(maxi(xs[0], xs[1]), maxi(xs[2], xs[3])), maxi(maxi(ys[0], ys[1]), maxi(ys[2], ys[3])),
		kd, W_STYLE, SH_QUAD, xs[0], ys[0], xs[1], ys[1], xs[2], ys[2], xs[3], ys[3], hd, mat]
	blds.append(rec)
	return rec


## A low wall (yard, garden) from (ax, ay) to (bx, by) cm: the 2 m cells
## within 0.8 m of it become rock-like cover 1.2-1.4 m high, where free.
## Returns true if any was laid.
static func _w_lowwall(wc: Dictionary, ax: int, ay: int, bx: int, by: int, par: int) -> bool:
	var ow: int = wc["ow"]
	var oh: int = wc["oh"]
	var inside: PackedByteArray = wc["inside"]
	var keep: PackedByteArray = wc["keep"]
	var blk: PackedByteArray = wc["blk"]
	var own: PackedInt32Array = wc["own"]
	var obs: PackedByteArray = wc["obs"]
	var cells := PackedInt32Array()
	for j in range(maxi((mini(ay, by) - 100) / 200, 0), mini((maxi(ay, by) + 100) / 200 + 1, oh)):
		for i in range(maxi((mini(ax, bx) - 100) / 200, 0), mini((maxi(ax, bx) + 100) / 200 + 1, ow)):
			if _seg_dist_cm(i * 200 + 100, j * 200 + 100, ax, ay, bx, by) <= 80:
				var c := j * ow + i
				if own[c] == par + 1 and obs[c] == C_BUILDING:
					continue  # (its own house: the wall runs on from it)
				if inside[c] == 0 or keep[c] != 0 or blk[c] != 0 or obs[c] != C_OPEN or (own[c] != 0 and own[c] != par + 1):
					return false
				# (Not within two cells of another building: no sliver beside it.)
				for dj in range(-2, 3):
					for di in range(-2, 3):
						var i2 := i + di
						var j2 := j + dj
						if i2 >= 0 and j2 >= 0 and i2 < ow and j2 < oh:
							var o2 := own[j2 * ow + i2]
							if o2 != 0 and o2 != par + 1:
								return false
				cells.append(c)
	if cells.size() < 2:
		return false
	for c in cells:
		obs[c] = C_ROCK
		own[c] = par + 1
	(wc["lowwalls"] as Array).append([(ax + 50) / 100, (ay + 50) / 100, (bx + 50) / 100, (by + 50) / 100, 13])
	return true


## A prop (barrels, crates, a cart) at (x, y) m turned to `ang`: its cell (a
## cart two, along ang) becomes rock-like cover of its height where open.
static func _w_prop(wc: Dictionary, kind: int, x: int, y: int, ang: int) -> void:
	var ow: int = wc["ow"]
	var oh: int = wc["oh"]
	var obs: PackedByteArray = wc["obs"]
	var blk: PackedByteArray = wc["blk"]
	var cells := PackedInt32Array()
	var n := 2 if kind == P_CART else 1
	for q in n:
		var qx := x + FM.cos_a(ang) * (q * 2 - (n - 1)) / FM.TRIG_ONE
		var qy := y + FM.sin_a(ang) * (q * 2 - (n - 1)) / FM.TRIG_ONE
		if qx < 2 or qy < 2 or qx >= ow * 2 - 2 or qy >= oh * 2 - 2:
			return
		var c := (qy / 2) * ow + qx / 2
		if obs[c] != C_OPEN or blk[c] != 0:
			return
		cells.append(c)
	for c in cells:
		obs[c] = C_ROCK
		blk[c] = 1
	var hd: int = [11, 12, 14, 10][kind]
	(wc["props"] as Array).append([kind, x, y, ang, hd])


## Lots along one road (both sides, a fixed order): buildings by kind and
## density, uneven gaps and setbacks, turned a little off the road and
## toward the contour on a slope; now and then a wing, a lean-to, a yard
## wall, barrels or a cart at the door.
static func _w_lots(wc: Dictionary, pts: PackedInt32Array, rw: int, rk: int) -> void:
	var rng: PackedInt32Array = wc["rng"]
	var hgt: Dictionary = wc["hgt"]
	var n := pts.size() / 2
	if n < 2:
		return
	var cum := PackedInt32Array([0])
	for k in range(1, n):
		cum.append(cum[k - 1] + FM.approx_len(pts[k * 2] - pts[k * 2 - 2], pts[k * 2 + 1] - pts[k * 2 - 1]))
	var total := cum[n - 1]
	var coast: int = (wc["o"] as Dictionary)["coast"]
	var founder: int = wc["founder"]
	for si in 2:
		var side := 1 if si == 0 else -1
		var s := _rr(rng, 1, 6)
		while s < total - 6:
			var pm := _w_at(pts, cum, s + 4)
			var dens := _w_dens(wc, pm[0], pm[1])
			if _r(rng, 100) >= dens + 26:
				s += _rr(rng, 4, 9)
				continue
			var kd := _w_kind(rng, rk, dens, coast)
			var sz := _w_size(rng, kd)
			var mat := _w_mat(rng, kd, founder)
			var sb := _r(rng, 2) + (100 - dens) / 35 + _r(rng, 1 + (100 - dens) / 25)
			var rot := _rr(rng, -14, 14) + (_rr(rng, -16, 16) if dens < 40 else 0)
			var gap := _rr(rng, 0, 2) + (100 - dens) / 15 + _r(rng, 1 + (100 - dens) / 12)
			var extra := _r(rng, 100)
			var placed: Array = []
			for tries in 2:
				var fw := sz.x if tries == 0 else sz.x * 3 / 4
				var fd := sz.y if tries == 0 else sz.y * 3 / 4
				if fw < 4 or fd < 4:
					break
				var p := _w_at(pts, cum, s + fw / 2)
				var ex := p[2]
				var ey := p[3]
				var a := FM.atan2_a(ey, ex)
				var r2 := rot
				var cd := Land.contour_at(hgt, p[0], p[1]) if not hgt.is_empty() else -1
				if cd >= 0:
					# Step with the slope: the nearer of the contour's axes.
					var best_d := 1 << 20
					for q in 4:
						var dd := FM.angle_diff(a, (cd + q * 256) & 1023)
						if absi(dd) < absi(best_d):
							best_d = dd
					r2 += clampi(best_d, -24, 24)
				var ua := (a + r2) & 1023
				var ux := FM.cos_a(ua)
				var uy := FM.sin_a(ua)
				var nx := -uy * side
				var ny := ux * side
				var snx := -ey * side
				var sny := ex * side
				# Front edge clear of the road whatever the turn.
				var off := rw * 50 + sb * 100 + 60 + fw * 50 * absi(FM.sin_a(r2 & 1023)) / FM.TRIG_ONE
				var fx := p[0] * 100 + snx * off / FM.TRIG_ONE - ux * fw * 50 / FM.TRIG_ONE
				var fy := p[1] * 100 + sny * off / FM.TRIG_ONE - uy * fw * 50 / FM.TRIG_ONE
				placed = _w_put(wc, fx, fy, ux, uy, nx, ny, fw, fd, kd, sz.z, mat, -1)
				if not placed.is_empty():
					var idx: int = (wc["buildings"] as Array).size() - 1
					_w_extras(wc, placed, idx, fx, fy, ux, uy, nx, ny, fw, fd, kd, extra, rw, sb, side, ex, ey)
					s += fw + gap
					break
			if placed.is_empty():
				s += 3


## The extras of a building just placed (record b, index idx, front-left
## corner f cm, axes u n, size fw x fd): a back wing (taverns, warehouses,
## big houses), a lean-to at a side, a yard wall behind, goods at the door.
static func _w_extras(wc: Dictionary, b: Array, idx: int, fx: int, fy: int, ux: int, uy: int, nx: int, ny: int,
		fw: int, fd: int, kd: int, roll: int, rw: int, sb: int, side: int, ex: int, ey: int) -> void:
	var rng: PackedInt32Array = wc["rng"]
	var founder: int = wc["founder"]
	var hd: int = b[15]
	var mat: int = b[16]
	if (kd == B_TAVERN or kd == B_WAREHOUSE or kd == B_GOVERNOR or (kd == B_HOUSE and fw >= 9)) and roll < 35:
		# An L: a wing at one back corner running back.
		var ww := maxi(fw * 45 / 100, 4)
		var wd := maxi(fd * 7 / 10, 4)
		var right := roll % 2 == 0
		# (A metre into the house: the two share their cells, no sliver.)
		var bx := fx + nx * (fd - 1) * 100 / FM.TRIG_ONE + (ux * (fw - ww) * 100 / FM.TRIG_ONE if right else 0)
		var by := fy + ny * (fd - 1) * 100 / FM.TRIG_ONE + (uy * (fw - ww) * 100 / FM.TRIG_ONE if right else 0)
		_w_put(wc, bx, by, ux, uy, nx, ny, ww, wd + 1, kd, hd - 6, mat, idx)
	elif kd != B_SHACK and roll >= 35 and roll < 55:
		# A lean-to against a side, toward the back.
		var right2 := roll % 2 == 0
		var ld := maxi(fd * 6 / 10, 3)
		var lx := fx + nx * (fd - ld) * 100 / FM.TRIG_ONE + (ux * (fw - 1) * 100 / FM.TRIG_ONE if right2 else -ux * 300 / FM.TRIG_ONE)
		var ly := fy + ny * (fd - ld) * 100 / FM.TRIG_ONE + (uy * (fw - 1) * 100 / FM.TRIG_ONE if right2 else -uy * 300 / FM.TRIG_ONE)
		_w_put(wc, lx, ly, ux, uy, nx, ny, 4, ld, B_LEANTO, 28, MAT_TIMBER, idx)
	if (kd == B_HOUSE or kd == B_GOVERNOR or kd == B_TAVERN) and _r(rng, 100) < (40 if founder == CUL_LATIN else 25):
		# A yard behind: its back wall and one side (the other side open).
		var yd := _rr(rng, 5, 8)
		var b0x := fx + nx * fd * 100 / FM.TRIG_ONE
		var b0y := fy + ny * fd * 100 / FM.TRIG_ONE
		var b1x := b0x + ux * fw * 100 / FM.TRIG_ONE
		var b1y := b0y + uy * fw * 100 / FM.TRIG_ONE
		var dxy := nx * yd * 100 / FM.TRIG_ONE
		var dyy := ny * yd * 100 / FM.TRIG_ONE
		if _w_lowwall(wc, b0x + dxy, b0y + dyy, b1x + dxy, b1y + dyy, idx):
			if _r(rng, 2) == 0:
				_w_lowwall(wc, b1x, b1y, b1x + dxy, b1y + dyy, idx)
			else:
				_w_lowwall(wc, b0x, b0y, b0x + dxy, b0y + dyy, idx)
	if (kd == B_TAVERN or kd == B_WAREHOUSE or kd == B_CHANDLER or kd == B_STORE) and rw >= 10 and _r(rng, 100) < 45:
		# Goods at the street's edge by the door.
		var snx := -ey * side
		var sny := ex * side
		var mx := fx + ux * fw * 50 / FM.TRIG_ONE
		var my := fy + uy * fw * 50 / FM.TRIG_ONE
		var back := sb * 100 + 60 + rw * 50 - 150
		var gx := (mx - snx * back / FM.TRIG_ONE + ux * _rr(rng, -250, 250) / FM.TRIG_ONE) / 100
		var gy := (my - sny * back / FM.TRIG_ONE + uy * _rr(rng, -250, 250) / FM.TRIG_ONE) / 100
		var pk := P_BARRELS if kd == B_TAVERN else (P_CRATES if _r(rng, 2) == 0 else P_CART)
		_w_prop(wc, pk, gx, gy, FM.atan2_a(ey, ex))


## The West open town (canonical frame) into `out`; appends the woods'
## exclusions to `excl`. Returns the layout (metres).
static func _city_west(p: Dictionary, kind: int, w_m: int, h_m: int, out: Dictionary, excl: Array,
		hgt: Dictionary, land_ok: bool, pal: int) -> Dictionary:
	var level: int = p["level"]
	var walls: int = p["walls"]
	var coast: int = p["coast"]
	var o := west_outline(p, kind, w_m)
	var rng := _rng(int(p["seed"]) * 29 + 11)
	var cx: int = o["cx"]
	var hw: int = o["hw"]
	var dep: int = o["dep"]
	var top: int = o["top"]
	var px: int = o["px"]
	var py: int = o["py"]
	var hs: int = o["hs"]
	var cp: PackedInt32Array = o["cp"]
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
	var blk := PackedByteArray()
	blk.resize(nc)
	blk.fill(0)
	var own := PackedInt32Array()
	own.resize(nc)
	own.fill(0)
	var vx: PackedInt32Array = o["vx"]
	var vy: PackedInt32Array = o["vy"]
	_fill_poly(inside, ow, oh, vx, vy)
	var att_x := cx
	var att_y := int(o["bot"]) + W_APPROACH
	var hg: Dictionary = hgt if int(hgt.get("on", 0)) != 0 else {}
	var botv := PackedInt32Array()  # the landward edge's y at each metre
	for x in w_m + 1:
		botv.append(_w_bot(o, x))
	var wc := {"o": o, "rng": rng, "ow": ow, "oh": oh, "obs": obs, "inside": inside, "keep": keep, "blk": blk,
		"own": own, "hgt": hg, "buildings": [], "props": [], "lowwalls": [], "founder": int(p["founder"]), "botv": botv}
	var blds: Array = wc["buildings"]
	# ---- the sea.
	if coast != 0:
		for i in ow:
			var sy := shore_y(cp, i * 2 + 1)
			for j in range(0, mini((sy - 1 + 1) / 2, oh)):
				obs[j * ow + i] = C_WATER
				blk[j * ow + i] = 1
	# ---- the fort (slice 2c): a bastioned trace with an inside: walls,
	# walkways, stairs, a gate toward the town, a sally port, the ditch on
	# the land side, a magazine and barracks on its parade.
	var fort: Dictionary = o["fort"]
	var fw := {}
	if not fort.is_empty():
		fw = _w_fort(wc, fort, coast)
		wc["fort_w"] = fw
	# ---- landforms (rolling or rougher ground): the roads bend round them.
	var land := {}
	if land_ok and not hg.is_empty():
		var avoid: Array = [[px - hs - 10, py - hs - 10, px + hs + 10, py + hs + 10]]
		if not fort.is_empty():
			var fe0 := int(fort["ext"])
			avoid.append([int(fort["x"]) - fe0, int(fort["y"]) - fe0, int(fort["x"]) + fe0, int(fort["y"]) + fe0])
		var lctx := {"w_m": w_m, "h_m": h_m, "kind": kind, "pal": pal, "seed": int(p["seed"]) * 7 + 5,
			"hgt": hg, "obs": obs, "avoid": avoid, "ref": Vector2i(att_x, mini(att_y + 30, h_m - 8)),
			"excl": [[cx - hw - 20, 0, cx + hw + 20, top + W_QUAY[level] + 8], [att_x - 45, int(o["bot"]), att_x + 45, att_y + 120],
				[w_m * 10 / 100, att_y - 20, w_m * 90 / 100, h_m]]}
		if coast != 0:
			lctx["shore"] = cp
			lctx["sea_cliffs"] = 1 if int(o["site"]) != SITE_PLAIN or pal == PAL_ROCKY else 0
			lctx["sea_skip"] = [cx - hw - 30, cx + hw + 30]
		land = Land.place(lctx)
		var lc: PackedByteArray = land["cells"]
		for c in lc.size():
			if lc[c] != 0 and obs[c] == C_OPEN:
				obs[c] = lc[c]
				blk[c] = 1
		out["land_raw"] = land
	# ---- big trees in the town (ceibas, palm clumps): roads and lots go round.
	var post: Array = []
	var n_tr: int = [5, 8, 12][level]
	for k in n_tr * 3:
		if post.size() >= n_tr:
			break
		var tx := cx + _rr(rng, -hw + 20, hw - 20)
		var ty := _rr(rng, top + 24, int(o["bot"]) - 10)
		var c := (ty / 2) * ow + tx / 2
		if inside[c] == 0 or (absi(tx - px) < hs + 14 and absi(ty - py) < hs + 14) or not _w_free(blk, ow, oh, tx, ty, 6):
			continue
		if absi(ty - _w_rail(o, tx)) < 12:
			continue
		post.append([tx - 3, ty - 3, tx + 3, ty + 3, 2])
		_disc(blk, ow, oh, tx, ty, 3, 1)
	# (blk summed, for the roads' quick look: it does not change while they are traced.)
	var bsat := PackedInt32Array()
	bsat.resize((ow + 1) * (oh + 1))
	bsat.fill(0)
	for j in oh:
		var acc := 0
		for i in ow:
			acc += blk[j * ow + i]
			bsat[(j + 1) * (ow + 1) + i + 1] = bsat[j * (ow + 1) + i + 1] + acc
	wc["bsat"] = bsat
	# ---- roads: the quay (or an inland town's back street), the high street
	# through the plaza, cross streets down to the landward edge, lanes.
	var roads: Array = []   # [points, width, kind]
	var qw: int = W_QUAY[level] if coast != 0 else W_BACK
	var x0 := cx - hw - 14
	var x1 := cx + hw + 14
	if not fort.is_empty():
		if int(fort["side"]) < 0:
			x0 = int(fort["x"]) + int(fort["ext"]) + 4
		else:
			x1 = int(fort["x"]) - int(fort["ext"]) - 4
	var qway := PackedInt32Array()
	var xq := x0
	while true:
		qway.append(xq)
		qway.append(_w_top(o, xq) + qw / 2 + (2 if coast != 0 else 6))
		if xq >= x1:
			break
		xq = mini(xq + 40, x1)
	var quay := _w_road(wc, qway, qw / 2, 0, 0)
	roads.append([quay, qw, 0])
	var mw: int = W_MAIN[level]
	var mway := PackedInt32Array()
	var xm := cx - hw - 12
	var plaza_done := false
	while xm <= cx + hw + 12:
		if not plaza_done and xm > px - 30:
			mway.append(px)
			mway.append(py)
			plaza_done = true
			xm = px + 30
			continue
		mway.append(xm)
		mway.append(_w_rail(o, xm))
		xm += 46
	mway.append(cx + hw + 12)
	mway.append(_w_rail(o, cx + hw + 12))
	var mpts := _w_road(wc, mway, mw / 2, 1, 0)
	roads.append([mpts, mw, 1])
	# ---- landmarks on the plaza (before the other roads, which bend round
	# them): the church on its seaward side (else the other), the governor's
	# house opposite, a guardhouse at a corner (each facing the plaza).
	for r in roads:
		var rp0: PackedInt32Array = r[0]
		for q in range(rp0.size() / 2 - 1):
			_keep_seg(keep, ow, oh, rp0[q * 2], rp0[q * 2 + 1], rp0[q * 2 + 2], rp0[q * 2 + 3], int(r[1]) / 2)
	_keep_rect(keep, ow, oh, px - hs, py - hs, px + hs, py + hs)
	var cw2: int = [16, 24, 30][level]
	var cd2: int = [8, 10, 12][level]
	var chd := 90 if level > 0 else 65
	var ch_n := _w_landmark(wc, px + cw2 / 2, py - hs - 2, -1, 0, 0, -1, cw2, cd2, B_TEMPLE, chd, MAT_STONE)
	if not ch_n and not _w_landmark(wc, px - cw2 / 2, py + hs + 2, 1, 0, 0, 1, cw2, cd2, B_TEMPLE, chd, MAT_STONE):
		_w_landmark(wc, px - hs / 2 + cw2 / 2, py - hs - 2, -1, 0, 0, -1, cw2, cd2, B_TEMPLE, chd, MAT_STONE)
	if level >= 1:
		var gs := _w_size(rng, B_GOVERNOR)
		var gy0 := py + hs + 2 if ch_n else py - hs - 2
		var gny := 1 if ch_n else -1
		var placed_g := false
		for off in [0, hs / 2, -hs / 2]:
			if placed_g:
				break
			var gx0: int = px - gs.x / 2 + int(off) if gny > 0 else px + gs.x / 2 + int(off)
			placed_g = _w_landmark(wc, gx0, gy0, gny, 0, 0, gny, gs.x, gs.y, B_GOVERNOR, gs.z, MAT_STONE)
	var bld: Array = p["bld"]
	if bld.has(2):
		for cn in 4:
			var sxn := 1 if cn % 2 == 0 else -1
			var syn := 1 if cn < 2 else -1
			if _w_landmark(wc, px + sxn * (hs + 4) - (14 if sxn < 0 else 0), py + syn * (hs + 4) - (10 if syn < 0 else 0),
					1, 0, 0, 1, 14, 10, B_BARRACKS, 55, MAT_STONE):
				break
	# (Their ground blocked, a cell round, for the roads still to come; the
	# summed table again from the first row that changed.)
	var jmin := oh
	for b in blds:
		var a0: Array = b
		if int(a0[4]) == B_FORT:
			continue
		for cj in range(maxi(int(a0[1]) / 2 - 3, 0), mini(int(a0[3]) / 2 + 4, oh)):
			for ci in range(maxi(int(a0[0]) / 2 - 3, 0), mini(int(a0[2]) / 2 + 4, ow)):
				var hit := false
				for dj in range(-1, 2):
					for di in range(-1, 2):
						var ii := ci + di
						var jj := cj + dj
						if ii >= 0 and jj >= 0 and ii < ow and jj < oh and own[jj * ow + ii] != 0:
							hit = true
				if hit and blk[cj * ow + ci] == 0:
					blk[cj * ow + ci] = 1
					jmin = mini(jmin, cj)
	for j in range(jmin, oh):
		var acc2 := 0
		for i in ow:
			acc2 += blk[j * ow + i]
			bsat[(j + 1) * (ow + 1) + i + 1] = bsat[j * (ow + 1) + i + 1] + acc2
	# A second street along the town's lower half (towns and cities).
	if level >= 1:
		var lway := PackedInt32Array()
		var xl := cx - hw + _rr(rng, 30, 60)
		var xe := cx + hw - _rr(rng, 30, 60)
		var lf := _rr(rng, 58, 70)
		while xl < xe:
			lway.append(xl)
			lway.append(_w_rail(o, xl) + (_w_bot(o, xl) - _w_rail(o, xl)) * lf / 100 + _rr(rng, -10, 10))
			xl += _rr(rng, 40, 64)
		if lway.size() >= 4:
			var bpts := _w_road(wc, lway, 4, 1, 22)
			if bpts.size() >= 6:
				roads.append([bpts, 8, 1])
	# Cross streets.
	var cxs: Array = []
	var xc := cx - hw + _rr(rng, 14, 30)
	while xc < cx + hw - 14:
		cxs.append(xc)
		xc += _rr(rng, 50, 82) if level > 0 else _rr(rng, 58, 92)
	var crosses: Array = []
	var mouths: Array = []
	for k in cxs.size():
		var xk: int = cxs[k]
		if not fort.is_empty() and absi(xk - int(fort["x"])) < int(fort["ext"]) + 6:
			continue
		var cw := 10 if absi(xk - px) < hs + 40 else (8 if k % 2 == 0 else 7)
		var ys := _w_top(o, xk) + qw / 2 + 2
		var yb := _w_bot(o, xk) + 22
		var ym := _w_rail(o, xk)
		# Upper part (quay to the high street) and lower part (on to the edge),
		# often a dog-leg apart where they meet the high street.
		var jog := 0 if _r(rng, 100) < 35 else _rr(rng, 8, 22) * (1 if _r(rng, 2) == 0 else -1)
		var xu := xk + _rr(rng, -14, 14)
		var cpts := PackedInt32Array()
		if _r(rng, 100) >= 22 or level == 0:
			var up := _w_road(wc, PackedInt32Array([xk, ys, xu, (ys + ym) / 2, xk, ym]), cw / 2, 1, 34)
			if up.size() >= 6:
				roads.append([up, cw, 2])
		var low := _w_road(wc, PackedInt32Array([xk + jog, ym, xk + jog + _rr(rng, -18, 18), (ym + yb) / 2,
			xk + jog + _rr(rng, -24, 24), yb]), cw / 2, 1, 34)
		cpts = low
		if cpts.size() < 6:
			continue
		roads.append([cpts, cw, 2])
		crosses.append(cpts)
		var n2 := cpts.size()
		if cpts[n2 - 1] >= _w_bot(o, cpts[n2 - 2]) + 6:
			mouths.append([cpts[n2 - 2], cpts[n2 - 1], FM.atan2_a(cpts[n2 - 1] - cpts[n2 - 3], cpts[n2 - 2] - cpts[n2 - 4])])
	# Lanes between neighbouring cross streets.
	for k in range(crosses.size() - 1):
		var ca: PackedInt32Array = crosses[k]
		var cb: PackedInt32Array = crosses[k + 1]
		var nl := 1 + (1 if absi(cb[0] - ca[0]) > 64 else 0) + (1 if level == 2 else 0)
		for q in nl:
			if _r(rng, 100) < 28:
				continue
			var yl := top + dep * _rr(rng, 22, 88) / 100
			if absi(yl - py) < hs + 6:
				continue
			var a := _w_near_y(ca, yl)
			var b := _w_near_y(cb, yl + _rr(rng, -12, 12))
			if a.x < 0 or b.x < 0:
				continue
			var lpts := _w_road(wc, PackedInt32Array([a.x, a.y, (a.x + b.x) / 2, (a.y + b.y) / 2 + _rr(rng, -6, 6), b.x, b.y]),
				W_LANE / 2, 1, 30)
			if lpts.size() >= 6:
				roads.append([lpts, W_LANE, 3])
	# The high street's ends are mouths too (the town's sides).
	var mn := mpts.size()
	if mn >= 4:
		mouths.append([mpts[mn - 2], mpts[mn - 1], 0])
		mouths.append([mpts[0], mpts[1], 512])
	# Nearest the attackers' line first.
	mouths.sort_custom(func(a, b):
		var da := absi(int(a[0]) - att_x) + (400 if int(a[2]) == 0 or int(a[2]) == 512 else 0)
		var db := absi(int(b[0]) - att_x) + (400 if int(b[2]) == 0 or int(b[2]) == 512 else 0)
		return da < db or (da == db and int(a[0]) < int(b[0])))
	var streets: Array = []
	for r in roads:
		var rp: PackedInt32Array = r[0]
		var rw: int = r[1]
		for q in range(rp.size() / 2 - 1):
			streets.append([rp[q * 2], rp[q * 2 + 1], rp[q * 2 + 2], rp[q * 2 + 3], rw])
			_keep_seg(keep, ow, oh, rp[q * 2], rp[q * 2 + 1], rp[q * 2 + 2], rp[q * 2 + 3], rw / 2)
	_keep_rect(keep, ow, oh, px - hs, py - hs, px + hs, py + hs)
	wc.erase("bsat")
	# ---- buildings on lots along the roads (quay, high street, cross streets, lanes).
	for r in roads:
		_w_lots(wc, r[0], int(r[1]), int(r[2]))
	# ---- goods on the quay's sea side, a few carts on the wide streets.
	if coast != 0:
		var qn := quay.size() / 2
		var qcum := PackedInt32Array([0])
		for k in range(1, qn):
			qcum.append(qcum[k - 1] + FM.approx_len(quay[k * 2] - quay[k * 2 - 2], quay[k * 2 + 1] - quay[k * 2 - 1]))
		var sq := _rr(rng, 6, 16)
		while qn >= 2 and sq < qcum[qn - 1] - 6:
			var at := _w_at(quay, qcum, sq)
			var kx := P_BARRELS if _r(rng, 3) == 0 else (P_CRATES if _r(rng, 2) == 0 else P_CART)
			# (The sea side: toward smaller y.)
			var sgn := -1 if at[2] >= 0 else 1
			var ex2 := at[0] + (-at[3]) * sgn * (qw / 2 - 2) / FM.TRIG_ONE
			var ey2 := at[1] + at[2] * sgn * (qw / 2 - 2) / FM.TRIG_ONE
			_w_prop(wc, kx, ex2, ey2, FM.atan2_a(at[3], at[2]))
			sq += _rr(rng, 14, 30)
	# ---- the stake palisade along the landward edge (walls 2), gaps at the roads.
	if walls >= 2:
		var run: Array = []   # [cell column, cell row] of the run so far
		var prow := -1
		var i0 := (cx - hw + 30) / 2
		var i1 := (cx + hw - 30) / 2
		for ic in range(i0, i1 + 1):
			var row := (_w_bot(o, ic * 2 + 1) + 9) / 2
			if prow >= 0:
				row = clampi(row, prow - 1, prow + 1)  # (no diagonal leak between columns)
			prow = row
			var ok := row >= 0 and row + 1 < oh
			if ok:
				for dj in 2:
					var c2 := (row + dj) * ow + ic
					if keep[c2] != 0 or blk[c2] != 0 or obs[c2] != C_OPEN:
						ok = false
			if ok:
				run.append(Vector2i(ic, row))
			if (not ok or ic == i1) and run.size() >= 2:
				_w_stakes(wc, run)
			if not ok or ic == i1:
				run = []
	# ---- each building cell's height (dm, bits 0-6) and material (bit 7:
	# timber) for the sim's line of fire (cover by material).
	var bmat := PackedByteArray()
	bmat.resize(nc)
	bmat.fill(0)
	for c in nc:
		var k := own[c]
		if k > 0 and obs[c] == C_BUILDING and k <= blds.size():
			var rec: Array = blds[k - 1]
			bmat[c] = clampi(int(rec[15]), 1, 127) | (128 if int(rec[16]) == MAT_TIMBER else 0)
	# ---- the ground: town, roads, plaza, the sea, gardens at the edge.
	var veg: PackedByteArray = out["veg"]
	var vw: int = out["vw"]
	var vh: int = out["vh"]
	var fseed := int(p["seed"]) * 2654435761
	for j in vh:
		for i in vw:
			var oc := mini(j * 2 + 1, oh - 1) * ow + mini(i * 2 + 1, ow - 1)
			if inside[oc] == 0:
				continue
			veg[j * vw + i] |= V_URBAN
			if keep[oc] == 0 and own[oc] == 0 and obs[oc] == C_OPEN and blk[oc] == 0:
				var xm2 := i * 4 + 2
				var ym2 := j * 4 + 2
				if _w_dens(wc, xm2, ym2) < 46:
					var pid := ((xm2 / 12) * 7919 + (ym2 / 10) * 104729 + fseed) & 0x7FFFFFFF
					pid = ((pid ^ (pid >> 13)) * 0x5bd1e995) & 0x7FFFFFFF
					if (pid >> 7) % 10 < 4:
						veg[j * vw + i] |= V_FIELD
	for s in streets:
		_veg_seg(veg, vw, vh, s[0], s[1], s[2], s[3], s[4] / 2, V_ROAD)
	for j in range(maxi((py - hs) / 4, 0), mini((py + hs) / 4 + 1, vh)):
		for i in range(maxi((px - hs) / 4, 0), mini((px + hs) / 4 + 1, vw)):
			veg[j * vw + i] |= V_PLAZA
	if not fw.is_empty():
		# (The fort's ditch, drawn as the walled plans' is.)
		for j in vh:
			for i in vw:
				if obs[mini(j * 2 + 1, oh - 1) * ow + mini(i * 2 + 1, ow - 1)] == C_DITCH:
					veg[j * vw + i] |= V_DITCH
	var sea := {}
	if coast != 0:
		for i in vw:
			var sy2 := shore_y(cp, i * 4 + 2)
			for j in range(0, mini((sy2 - 2 + 3) / 4, vh)):
				veg[j * vw + i] |= V_WATER
		# Piers: timber jetties off the quay (scenery: the rules see the sea).
		var piers: Array = []
		var npi: int = [1, 2, 3][level]
		for k in npi * 3:
			if piers.size() >= npi:
				break
			var pxk := cx + _rr(rng, -hw + 30, hw - 30)
			if not fort.is_empty() and absi(pxk - int(fort["x"])) < int(fort["ext"]) + 10:
				continue
			var clash := false
			for pr in piers:
				if absi(int((pr as PackedInt32Array)[0]) - pxk) < 40:
					clash = true
			if clash:
				continue
			var sy3 := shore_y(cp, pxk)
			var pl := _rr(rng, 16, 30)
			piers.append(PackedInt32Array([pxk - 2, sy3 - pl, pxk + 2, sy3 - pl, pxk + 2, sy3 + 1, pxk - 2, sy3 + 1]))
		var yl := mini(shore_y(cp, 6) + 30, h_m - 8)
		var yr := mini(shore_y(cp, w_m - 6) + 30, h_m - 8)
		sea = {"gate": [], "moles": [], "flee": [[6, yl], [w_m - 6, yr]], "piers": piers}
	# ---- woods kept off the town, its approach and the attackers' ground.
	excl.append([cx - hw - 18, 0 if coast == 0 else top - 10, cx + hw + 18, int(o["bot"]) + 28])
	excl.append([att_x - 40, int(o["bot"]), att_x + 40, att_y + 120])
	excl.append([w_m * 10 / 100, att_y - 20, w_m * 90 / 100, h_m])
	# ---- the street graph.
	var lnodes: PackedInt32Array = land.get("nodes", PackedInt32Array())
	var nav := _w_graph(wc, roads, w_m, h_m, lnodes)
	out["obs"] = obs
	out["ow"] = ow
	out["oh"] = oh
	out["obs_on"] = 1
	out["city_on"] = 1
	var poly := PackedInt32Array()
	for k in vx.size():
		poly.append(vx[k])
		poly.append(vy[k])
	var has_f := not fw.is_empty()
	var lay := {"cx": cx, "cy": int(o["cy"]), "r0": int(o["r0"]), "level": level, "walls": F_WALLS if has_f else 0,
		"def": int(p["def"]),
		"seed": int(p["seed"]), "t": F_T if has_f else 0, "pp": F_PP if has_f else 0,
		"inner": F_T - F_PP - WALK_W if has_f else 0, "wall_h_m": F_WALL_H if has_f else 0,
		"build_h_m": BUILD_H[level], "poly": poly, "gates": fw.get("gates", []), "towers": [],
		"plaza": [px, py, hs, hs + CAPTURE_EXTRA], "agora": [px, py, hs], "cit": fw.get("cit", {}),
		"streets": streets, "mouths": mouths, "buildings": blds,
		"fields": [], "segs": fw.get("segs", []), "att_x": att_x, "att_y": att_y, "nav": nav,
		"gate_hp": GATE_HP[F_WALLS] if has_f else 0, "plan": int(p["plan"]), "site": int(o["site"]), "coast": coast,
		"ditch": 1 if has_f else 0,
		"sea": sea, "palisade": 0, "enclosed": 0,
		"founder": int(p["founder"]), "owner": int(p["owner"]), "banner": int(p["banner"]),
		"post_veg": post, "west": 1, "wwalls": walls, "props": wc["props"], "lowwalls": wc["lowwalls"],
		"fort": fort, "top": top, "bot": int(o["bot"]), "hw": hw, "bmat": bmat}
	out["city"] = lay
	return lay


# ------------------------------------------- the harbour fort (slice 2c) --
# docs/DESIGN.md "Forts and fighting from buildings". A square trace with a
# flanked bastion at each corner (curtain, flank, face, salient, face,
# flank), low thick walls (F_T, walkway F_WALL_H up), stairs up from the
# parade at every stretch's ends, the main gate in the curtain toward the
# town, a sally port in the far curtain, the ditch round the land faces
# (causeways at the gates), the powder magazine and the barracks on the
# parade, gun platforms at the four salients and on the seaward curtain.

## The trace's vertices in the fort's own frame (metres; x along the shore,
## y inland, the sea at -y): the north-east corner's five (gorge, flank,
## salient, flank, gorge) turned through the four corners, clockwise.
static func fort_trace(fh: int, fb: int) -> Array:
	var pat: Array[Vector2i] = [Vector2i(fh - F_G, -fh), Vector2i(fh - F_G, -fh - F_F), Vector2i(fh + fb, -fh - fb),
		Vector2i(fh + F_F, -fh + F_G), Vector2i(fh, -fh + F_G)]
	var out: Array = []
	for r in 4:
		for v in pat:
			var q := v
			for k in r:
				q = Vector2i(-q.y, q.x)
			out.append(q)
	return out


## Fort-frame point (metres, or cm with cm = 100) to the map's.
static func _f_w(fort: Dictionary, lx: int, ly: int, cm: int = 1) -> Vector2i:
	var cs := FM.cos_a(int(fort["dir"]))
	var sn := FM.sin_a(int(fort["dir"]))
	return Vector2i(int(fort["x"]) * cm + (cs * lx - sn * ly) / FM.TRIG_ONE,
		int(fort["y"]) * cm + (sn * lx + cs * ly) / FM.TRIG_ONE)


## Build the fort into the West town's grids (wc, _city_west's context):
## returns {"gates", "segs", "cit", "poly"} for the layout; adds its
## magazine and barracks to the buildings, its gun platforms to fort["guns"]
## ([x, y, facing] metres, the salients first) and its middle and gates to
## fort ("mx", "my").
static func _w_fort(wc: Dictionary, fort: Dictionary, coast: int) -> Dictionary:
	var ow: int = wc["ow"]
	var oh: int = wc["oh"]
	var obs: PackedByteArray = wc["obs"]
	var keep: PackedByteArray = wc["keep"]
	var blk: PackedByteArray = wc["blk"]
	var fh: int = fort["h"]
	var fb: int = fort["b"]
	var fs: int = fort["side"]
	var fd: int = fort["dir"]
	var trc := fort_trace(fh, fb)
	var nv := trc.size()
	var vx := PackedInt32Array()
	var vy := PackedInt32Array()
	for v in trc:
		var w := _f_w(fort, (v as Vector2i).x, (v as Vector2i).y)
		vx.append(w.x)
		vy.append(w.y)
	var nc := ow * oh
	var fin := PackedByteArray()
	fin.resize(nc)
	fin.fill(0)
	_fill_poly(fin, ow, oh, vx, vy)
	var ed := _edges(vx, vy, int(fort["x"]), int(fort["y"]), false)
	var en_x: PackedInt32Array = ed["nx"]
	var en_y: PackedInt32Array = ed["ny"]
	var elen: PackedInt32Array = ed["len"]
	# Seaward edges (no ditch, no wall men set there by the scenario).
	var sea_x := FM.sin_a(fd)
	var sea_y := -FM.cos_a(fd)
	var esea := PackedInt32Array()
	for k in nv:
		var dot := (en_x[k] * sea_x + en_y[k] * sea_y) / FM.TRIG_ONE
		esea.append(1 if coast != 0 and dot > FM.TRIG_ONE * 55 / 100 else 0)
	var inner := F_T - F_PP - WALK_W
	# (The ground under it is open: whatever the shore cells were.)
	for c in nc:
		if fin[c] != 0 and obs[c] == C_WATER:
			obs[c] = C_OPEN
	_wall_band(obs, keep, fin, ow, oh, vx, vy, F_T, F_PP, inner)
	# Gates: the main gate in the curtain toward the town (the corner
	# pattern's fifth edge of each corner is a curtain: 4 east, 9 south, 14
	# west, 19 north), the sally port in the far one.
	var e_town := 14 if fs > 0 else 4
	var e_far := 4 if fs > 0 else 14
	var gates: Array = []
	var g0 := _mk_gate(vx, vy, ed, e_town, elen[e_town] / 2, GATE_HW, 0, F_T, 1, 0, 1)
	g0["fort"] = 1
	gates.append(g0)
	var g1 := _mk_gate(vx, vy, ed, e_far, elen[e_far] / 2, POSTERN_HW, 0, F_T, 0, 1, 1)
	g1["fort"] = 1
	gates.append(g1)
	var dummy: Array = []
	for g in gates.size():
		_gate_raster(obs, keep, ow, oh, gates[g], g, ed, F_T, 0, dummy)
	# Walkway stretches and their stairs down to the parade.
	var cut := PackedInt32Array()
	for k in nv:
		var kk := k % 5
		cut.append(F_T / 2 + 2 if kk == 2 else (4 if kk == 1 or kk == 3 else 2))
	# (Not SEG_CIT: the fort's walls are the only walls a West town has, laddered as any.)
	var segs := _segments(vx, vy, ed, gates, cut, F_T, F_PP, inner, esea, 0, 1)
	_stairs(obs, fin, ow, oh, segs, F_T, inner)
	# The ditch round the land faces, causeways at both gates.
	_ditch(obs, fin, ow, oh, vx, vy, esea, gates, gates.size(), F_T / 2 + F_DITCH_GAP, F_T / 2 + F_DITCH_GAP + F_DITCH)
	# Its ground, the ditch and a margin are kept from the town's roads and lots.
	var rb := (fh + fb) * 142 / 100 + F_T / 2 + F_DITCH_GAP + F_DITCH + 3
	_disc(blk, ow, oh, int(fort["x"]), int(fort["y"]), rb, 1)
	for c in nc:
		if fin[c] != 0 or obs[c] == C_DITCH:
			blk[c] = 1
	# The parade: the barracks along the far curtain, the magazine in its
	# seaward corner (fronts to the parade).
	var ia := fh - F_T / 2 - RING_W - 1
	var bx0 := fs * (ia - 7)
	var by_lo := -ia + 8
	var by_hi := ia
	_w_fort_bld(wc, fort, bx0 * 100, ((by_lo + by_hi) / 2 + fs * (by_hi - by_lo) / 2) * 100, 0, -fs, fs, 0,
		by_hi - by_lo, 7, B_BARRACKS, 55, fin)
	_w_fort_bld(wc, fort, fs * (ia - 6) * 100, (-ia + 3 + fs * 3) * 100, 0, -fs, fs, 0, 6, 5, B_MAGAZINE, 45, fin)
	# Gun platforms: the salients (1 m in from the point, facing out along
	# the bastion's axis), then the seaward curtain (its walkway, facing the
	# sea; ports only).
	var guns: Array = []
	for r in 4:
		var sv: Vector2i = trc[r * 5 + 2]
		if coast != 0 and sv.y < 0:
			continue  # (the seaward bastions' guns look out to sea: the curtain's below stand for them)
		var sgx := 1 if sv.x > 0 else -1
		var sgy := 1 if sv.y > 0 else -1
		var p := _f_w(fort, sv.x - sgx, sv.y - sgy)
		var q := _f_w(fort, sv.x * 2, sv.y * 2)
		guns.append([p.x, p.y, FM.atan2_a(q.y - p.y, q.x - p.x)])
	if coast != 0:
		var nsea: int = 1
		for k in nsea:
			var lx := 0 if nsea == 1 else (-fh / 3 if k == 0 else fh / 3)
			var p2 := _f_w(fort, lx, -fh - 1)
			var q2 := _f_w(fort, lx, -fh - 40)
			guns.append([p2.x, p2.y, FM.atan2_a(q2.y - p2.y, q2.x - p2.x)])
	fort["guns"] = guns
	var poly := PackedInt32Array()
	for k in nv:
		poly.append(vx[k])
		poly.append(vy[k])
	var rc := fh + F_T / 2
	var cit := {"x": int(fort["x"]), "y": int(fort["y"]), "rc": rc, "poly": poly, "gate": 0, "fort": 1}
	return {"gates": gates, "segs": segs, "cit": cit, "poly": poly, "fin": fin}


## A building on the fort's parade: quad from front-left corner (ax, ay)
## cm in the fort's frame, along u (Q12 units given as -1 / 0 / 1), into it
## along n, fw x fd m, kind kd, height hd (dm), stone; its cells within 0.6
## m of the drawing, inside the fort (fin) on open ground only.
static func _w_fort_bld(wc: Dictionary, fort: Dictionary, ax: int, ay: int, ux: int, uy: int, nx: int, ny: int,
		fw: int, fd: int, kd: int, hd: int, fin: PackedByteArray) -> void:
	var ow: int = wc["ow"]
	var oh: int = wc["oh"]
	var obs: PackedByteArray = wc["obs"]
	var own: PackedInt32Array = wc["own"]
	var blds: Array = wc["buildings"]
	var lq := PackedInt32Array([ax, ay, ax + ux * fw * 100, ay + uy * fw * 100,
		ax + ux * fw * 100 + nx * fd * 100, ay + uy * fw * 100 + ny * fd * 100, ax + nx * fd * 100, ay + ny * fd * 100])
	var body := PackedInt32Array()
	for k in 4:
		var w := _f_w(fort, lq[k * 2], lq[k * 2 + 1], 100)
		body.append(w.x)
		body.append(w.y)
	var cs := FM.cos_a(int(fort["dir"]))
	var sn := FM.sin_a(int(fort["dir"]))
	var wux := cs * ux - sn * uy
	var wuy := sn * ux + cs * uy
	var wnx := cs * nx - sn * ny
	var wny := sn * nx + cs * ny
	var cells: PackedInt32Array = (_w_cells(_w_grow(body, wux, wuy, wnx, wny, 60), ow, oh) as Array)[2]
	var idx := blds.size()
	var n_ok := 0
	for c in cells:
		if fin[c] != 0 and obs[c] == C_OPEN:
			obs[c] = C_BUILDING
			own[c] = idx + 1
			n_ok += 1
	if n_ok == 0:
		return
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	for k in 4:
		xs.append((body[k * 2] + 50) / 100)
		ys.append((body[k * 2 + 1] + 50) / 100)
	blds.append([mini(mini(xs[0], xs[1]), mini(xs[2], xs[3])), mini(mini(ys[0], ys[1]), mini(ys[2], ys[3])),
		maxi(maxi(xs[0], xs[1]), maxi(xs[2], xs[3])), maxi(maxi(ys[0], ys[1]), maxi(ys[2], ys[3])),
		kd, W_STYLE, SH_QUAD, xs[0], ys[0], xs[1], ys[1], xs[2], ys[2], xs[3], ys[3], hd, MAT_STONE])


## The point of polyline pts nearest height y (its y within 12 m), or (-1, -1).
static func _w_near_y(pts: PackedInt32Array, y: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := 13
	for q in pts.size() / 2:
		var d := absi(pts[q * 2 + 1] - y)
		if d < bd:
			bd = d
			best = Vector2i(pts[q * 2], pts[q * 2 + 1])
	return best


## A landmark: a building square to the plaza, its front-left corner at
## (x0, y0) m, w along (ux, uy) and d back along (nx, ny) (unit axes), where free.
static func _w_landmark(wc: Dictionary, x0: int, y0: int, ux: int, uy: int, nx: int, ny: int, w: int, d: int,
		kd: int, hd: int, mat: int) -> bool:
	return not _w_put(wc, x0 * 100, y0 * 100, ux * FM.TRIG_ONE, uy * FM.TRIG_ONE, nx * FM.TRIG_ONE, ny * FM.TRIG_ONE,
		w, d, kd, hd, mat, -1).is_empty()


## A run of the stake palisade ([cell column, cell row] each, 2 m cells):
## two cells deep in each column; a building record (2 m thick, inside its
## cells) for each stretch on one row, so the drawn stakes and the blocked
## cells agree (the gaps are the roads).
static func _w_stakes(wc: Dictionary, run: Array) -> void:
	var ow: int = wc["ow"]
	var obs: PackedByteArray = wc["obs"]
	var own: PackedInt32Array = wc["own"]
	var blds: Array = wc["buildings"]
	var q := 0
	while q < run.size():
		var a: Vector2i = run[q]
		var e := q
		while e + 1 < run.size() and (run[e + 1] as Vector2i).y == a.y and e - q < 7:
			e += 1
		var b: Vector2i = run[e]
		var idx := blds.size()
		for k in range(q, e + 1):
			var pt: Vector2i = run[k]
			for dj in 2:
				var c := (pt.y + dj) * ow + pt.x
				obs[c] = C_BUILDING
				own[c] = idx + 1
		var x0 := a.x * 2
		var x1 := b.x * 2 + 2
		var y0 := a.y * 2 + 1
		var y1 := a.y * 2 + 3
		blds.append([x0, y0, x1, y1, B_STAKES, W_STYLE, SH_QUAD, x0, y0, x1, y0, x1, y1, x0, y1, 26, MAT_TIMBER])
		q = e + 1


## The West town's street graph: nodes along every road (about 20 m apart),
## the plaza and its corners, a line outside the landward edge, a 48 m
## lattice over the open ground round the town, round the fort and the
## landforms; edges between nodes up to EDGE_MAX apart with a clear line
## 3 m wide (candidates from 48 m buckets, in index order), then the pieces
## joined. Returns {"x", "y", "gate", "e0", "to", "w"} as _nav_graph.
static func _w_graph(wc: Dictionary, roads: Array, w_m: int, h_m: int, lnodes: PackedInt32Array) -> Dictionary:
	var obs: PackedByteArray = wc["obs"]
	var inside: PackedByteArray = wc["inside"]
	var ow: int = wc["ow"]
	var oh: int = wc["oh"]
	var o: Dictionary = wc["o"]
	var nx := PackedInt32Array()
	var ny := PackedInt32Array()
	var ng := PackedInt32Array()
	var gb := {}   # 8 m buckets of the nodes (merge test)
	var add := func(x: int, y: int) -> int:
		if x < 4 or y < 4 or x > w_m - 4 or y > h_m - 4:
			return -1
		if obs[mini(y / 2, oh - 1) * ow + mini(x / 2, ow - 1)] != C_OPEN:
			return -1
		for bj in range(y / 8 - 1, y / 8 + 2):
			for bi in range(x / 8 - 1, x / 8 + 2):
				for q in gb.get(bj * 4096 + bi, []):
					if absi(nx[q] - x) < 4 and absi(ny[q] - y) < 4:
						return q
		nx.append(x)
		ny.append(y)
		ng.append(-1)
		var key := (y / 8) * 4096 + x / 8
		if not gb.has(key):
			gb[key] = []
		(gb[key] as Array).append(nx.size() - 1)
		return nx.size() - 1
	var px: int = o["px"]
	var py: int = o["py"]
	var hs: int = o["hs"]
	add.call(px, py)
	for c in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
		add.call(px + c.x * (hs - 3), py + c.y * (hs - 3))
	for r in roads:
		var rp: PackedInt32Array = r[0]
		var n := rp.size() / 2
		for q in n:
			if q % 2 == 0 or q == n - 1:
				add.call(rp[q * 2], rp[q * 2 + 1])
	var hw: int = o["hw"]
	var cx: int = o["cx"]
	var xo := cx - hw - 20
	while xo <= cx + hw + 20:
		add.call(xo, _w_bot(o, clampi(xo, cx - hw, cx + hw)) + 16)
		xo += 26
	var fort: Dictionary = o["fort"]
	var gate_links: Array = []  # [gate node, outside node, inside node]
	if not fort.is_empty():
		var rr := (int(fort["h"]) + int(fort["b"])) * 142 / 100 + F_T / 2 + F_DITCH_GAP + F_DITCH + 5
		for k in 8:
			add.call(int(fort["x"]) + FM.cos_a(k * 128) * rr / FM.TRIG_ONE, int(fort["y"]) + FM.sin_a(k * 128) * rr / FM.TRIG_ONE)
		var fw: Dictionary = wc.get("fort_w", {})
		if not fw.is_empty():
			# (Slice 2c.) Each gate: its outside, the gate itself (a node of
			# that gate: a shut gate cuts exactly it) and its inside; the
			# parade every 8 m and the foot of each stair.
			var fgates: Array = fw["gates"]
			for g in fgates.size():
				var gd: Dictionary = fgates[g]
				var n_o: int = add.call(int(gd["ox"]), int(gd["oy"]))
				nx.append(int(gd["x"]))
				ny.append(int(gd["y"]))
				ng.append(g)
				var n_g := nx.size() - 1
				var n_i: int = add.call(int(gd["ix"]), int(gd["iy"]))
				gate_links.append([n_g, n_o, n_i])
			var fin: PackedByteArray = fw["fin"]
			var fr := int(fort["h"])
			var ly := -fr
			while ly <= fr:
				var lx := -fr
				while lx <= fr:
					var w := _f_w(fort, lx, ly)
					if w.x > 0 and w.y > 0 and w.x < w_m and w.y < h_m and fin[mini(w.y / 2, oh - 1) * ow + mini(w.x / 2, ow - 1)] != 0:
						add.call(w.x, w.y)
					lx += 8
				ly += 8
			for sg in fw["segs"]:
				for e2 in 2:
					add.call(int(sg[9 + e2 * 6]), int(sg[10 + e2 * 6]))
	for q in lnodes.size() / 2:
		add.call(lnodes[q * 2], lnodes[q * 2 + 1])
	# Inside the town: the open ground between the lots (yards, gardens, the
	# backs of the blocks) every 16 m where a man stands 2 m clear, so a unit
	# anywhere in the town sees a node.
	var keep: PackedByteArray = wc["keep"]
	var iy := int(o["top"]) + 8
	while iy < int(o["bot"]) + 8:
		var ix := cx - hw + 8
		while ix < cx + hw:
			var c0 := mini(iy / 2, oh - 1) * ow + mini(ix / 2, ow - 1)
			if inside[c0] != 0 and keep[c0] == 0:
				var clear := true
				for dj in range(-1, 2):
					for di in range(-1, 2):
						var ii := ix / 2 + di
						var jj := iy / 2 + dj
						if ii < 0 or jj < 0 or ii >= ow or jj >= oh or obs[jj * ow + ii] != C_OPEN:
							clear = false
				if clear:
					add.call(ix, iy)
			ix += 16
		iy += 16
	var gy := FIELD_STEP / 2
	while gy < h_m:
		var gx := FIELD_STEP / 2
		while gx < w_m:
			if inside[mini(gy / 2, oh - 1) * ow + mini(gx / 2, ow - 1)] == 0:
				add.call(gx, gy)
			gx += FIELD_STEP
		gy += FIELD_STEP
	# Edges.
	var n2 := nx.size()
	var bk := {}
	for a in n2:
		var key := (ny[a] / W_EDGE) * 4096 + nx[a] / W_EDGE
		if not bk.has(key):
			bk[key] = []
		(bk[key] as Array).append(a)
	var adj: Array = []
	for a in n2:
		adj.append([])
	for a in n2:
		var cand: Array[int] = []
		var bi := nx[a] / W_EDGE
		var bj := ny[a] / W_EDGE
		for dj in range(-1, 2):
			for di in range(-1, 2):
				for b in bk.get((bj + dj) * 4096 + bi + di, []):
					if int(b) > a:
						cand.append(int(b))
		cand.sort()
		for b in cand:
			var dx := nx[b] - nx[a]
			var dy := ny[b] - ny[a]
			var l2 := dx * dx + dy * dy
			if l2 > W_EDGE * W_EDGE:
				continue
			if not _clear_fat(obs, ow, oh, nx[a], ny[a], nx[b], ny[b], ng[a] if ng[a] >= 0 else ng[b]):
				continue
			var w := FM.isqrt(l2 * 64)
			(adj[a] as Array).append([b, w])
			(adj[b] as Array).append([a, w])
	# A fort gate always joins its own outside and inside points.
	for gl in gate_links:
		var n_g: int = gl[0]
		for sd in [1, 2]:
			var n_s: int = gl[sd]
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
	_w_join(obs, ow, oh, nx, ny, adj)
	var e0 := PackedInt32Array()
	var to := PackedInt32Array()
	var ww := PackedInt32Array()
	for a in n2:
		e0.append(to.size())
		for e in adj[a]:
			to.append(int(e[0]))
			ww.append(int(e[1]))
	e0.append(to.size())
	return {"x": nx, "y": ny, "gate": ng, "e0": e0, "to": to, "w": ww}


## Join the pieces of a West town's graph to the piece of node 0 (the
## plaza): each other piece, in order of its first node, by the shortest
## clear line (of its 12 shortest pairs within 64 m) to a node already
## joined; a piece that finds none stays apart (a yard no line reaches).
## Up to three rounds (a piece may reach the main one through another).
static func _w_join(obs: PackedByteArray, ow: int, oh: int, nx: PackedInt32Array, ny: PackedInt32Array, adj: Array) -> void:
	var n := nx.size()
	if n == 0:
		return
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var nc := 0
	for s0 in n:
		if comp[s0] >= 0:
			continue
		comp[s0] = nc
		var stack: Array[int] = [s0]
		while not stack.is_empty():
			var v: int = stack.pop_back()
			for e in adj[v]:
				var b: int = e[0]
				if comp[b] < 0:
					comp[b] = nc
					stack.append(b)
		nc += 1
	if nc <= 1:
		return
	var joined := PackedByteArray()
	joined.resize(nc)
	joined.fill(0)
	joined[comp[0]] = 1
	var bk := {}
	for a in n:
		var key := (ny[a] / 64) * 4096 + nx[a] / 64
		if not bk.has(key):
			bk[key] = []
		(bk[key] as Array).append(a)
	for rnd in 3:
		var progress := false
		for c in nc:
			if joined[c] != 0:
				continue
			var pd := PackedInt64Array()
			var pa := PackedInt32Array()
			var pb := PackedInt32Array()
			for a in n:
				if comp[a] != c:
					continue
				var bi := nx[a] / 64
				var bj := ny[a] / 64
				for dj in range(-1, 2):
					for di in range(-1, 2):
						for b in bk.get((bj + dj) * 4096 + bi + di, []):
							if joined[comp[int(b)]] == 0:
								continue
							var dx := nx[int(b)] - nx[a]
							var dy := ny[int(b)] - ny[a]
							var d2 := dx * dx + dy * dy
							if d2 <= 64 * 64:
								pd.append(d2)
								pa.append(a)
								pb.append(int(b))
			var used := PackedByteArray()
			used.resize(pd.size())
			used.fill(0)
			for k in mini(pd.size(), 12):
				var bi2 := -1
				for q in pd.size():
					if used[q] != 0:
						continue
					if bi2 < 0 or pd[q] < pd[bi2] or (pd[q] == pd[bi2] and (pa[q] < pa[bi2] or (pa[q] == pa[bi2] and pb[q] < pb[bi2]))):
						bi2 = q
				used[bi2] = 1
				var a2: int = pa[bi2]
				var b2: int = pb[bi2]
				if _clear_fat(obs, ow, oh, nx[a2], ny[a2], nx[b2], ny[b2], -1):
					var w := FM.isqrt(int(pd[bi2]) * 64)
					(adj[a2] as Array).append([b2, w])
					(adj[b2] as Array).append([a2, w])
					joined[c] = 1
					progress = true
					break
		if not progress:
			break


## Turn a West town's own layout keys 180 degrees (_flip_all does the rest).
static func _w_flip(lay: Dictionary, w_m: int, h_m: int) -> void:
	for pr in lay.get("props", []):
		pr[1] = w_m - int(pr[1])
		pr[2] = h_m - int(pr[2])
		pr[3] = (int(pr[3]) + 512) & 1023
	for lw in lay.get("lowwalls", []):
		for q in 2:
			lw[q * 2] = w_m - int(lw[q * 2])
			lw[q * 2 + 1] = h_m - int(lw[q * 2 + 1])
	var fort: Dictionary = lay.get("fort", {})
	if not fort.is_empty():
		fort["x"] = w_m - int(fort["x"])
		fort["y"] = h_m - int(fort["y"])
		fort["dir"] = (int(fort["dir"]) + 512) & 1023
		for gp in fort.get("guns", []):
			gp[0] = w_m - int(gp[0])
			gp[1] = h_m - int(gp[1])
			gp[2] = (int(gp[2]) + 512) & 1023
	var sea: Dictionary = lay.get("sea", {})
	var piers: Array = sea.get("piers", [])
	for k in piers.size():
		var pq: PackedInt32Array = piers[k]
		for q in 4:
			pq[q * 2] = w_m - pq[q * 2]
			pq[q * 2 + 1] = h_m - pq[q * 2 + 1]
		piers[k] = pq
	lay["top"] = h_m - int(lay["top"])
	lay["bot"] = h_m - int(lay["bot"])
	var bm: PackedByteArray = lay.get("bmat", PackedByteArray())
	var nb := bm.size()
	for k in nb / 2:
		var t := bm[k]
		bm[k] = bm[nb - 1 - k]
		bm[nb - 1 - k] = t
	lay["bmat"] = bm
