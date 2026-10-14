extends RefCounted
## Battle-map landforms (slice 2d; docs/DESIGN.md "Battle-map landforms"):
## cliffs along the steepest slope breaks (and sea cliffs on a rocky
## coast), rock outcrops on crests and rough ground, and the terrain terms
## that make woods follow the land (valley floors, lower slopes, river
## banks, the lee of ridges) instead of lying about in round blobs.
##
## Built once at map setup by sim/mapgen.gd from the height grid (sim/
## terrain.gd; canonical frame) and the map's exclusions (deployment areas,
## the walls, the approach, water), so both lockstep peers build the same:
## integers only, its own xorshift, fixed order. Cliffs and outcrops are
## obstacle cells (C_CLIFF / C_ROCK in the 2 m grid): nobody walks there;
## missiles pass over them for now (slice 2b reads them for cover and
## sight: each outcrop and cliff point carries a height, `h` in the view
## data). The obstacles keep clear of one another, of the field's edges and
## of the walls and water, so they never close off a piece of ground (and a
## final flood fill from the attackers' ground drops any cliff that would).
##
## Output of place(): "cells" (2 m grid, 0 / C_ROCK / C_CLIFF), "cliffs"
## (view data: points in cm, downhill angle and height per point), "rocks"
## ([seed, height dm, x, y, r, x, y, r, ...] in metres), "nodes" (street-
## graph nodes round them, x, y pairs in metres).

const FM := preload("res://sim/fixed_math.gd")

const M := 1024
# Mirrors of sim/mapgen.gd (MapGen.C_*), which preloads this file.
const C_OPEN := 0
const C_DITCH := 5
const C_WATER := 6
const C_GATE := 8
const C_ROCK := 30
const C_CLIFF := 31
# sim/terrain.gd kinds and sim/mapgen.gd palettes.
const K_FLAT := 0
const K_ROLLING := 1
const K_RIDGE := 2
const K_VALLEY := 3
const K_HILL := 4
const K_SLOPE := 5
const PAL_ROCKY := 4

## Most cliff lines by kind (flat, rolling, ridge, valley, hill, slope) ...
const CLIFFS: Array[int] = [0, 1, 3, 2, 2, 2]
## ... outcrops by kind, and % of that by palette (plain, arid, dry, green, rocky).
const ROCKS: Array[int] = [0, 5, 12, 6, 10, 8]
const ROCK_PAL: Array[int] = [100, 125, 110, 70, 150]
const G_MIN := 410          # Q12 grade (4096 = 100 %): no cliff on ground gentler than 10 % ...
const CLIFF_PCT := 6        # ... and its seeds among the steepest 6 % of the map's nodes
const CLIFF_LEN: Array[int] = [26, 64]   # cliff length (m) drawn from
const CLIFF_MIN := 16       # a shorter trace is dropped
const CLIFF_HW := 220       # band half width (cm): cells within it are cliff
const CLIFF_CLR := 12       # m kept clear round a cliff (other landforms, walls, water, deployment)
const ROCK_CLR := 7         # ... round an outcrop
const EDGE := 18            # m from the field's edges
const STEP := 2             # m: cliff trace step
const TURN_MAX := 36        # angle units a trace may turn a step (13 degrees) ...
const TURN_SUM := 300       # ... and in all (105 degrees): a cliff never curls round
const LD_CAP := 8           # cells: clearance stamped round a new landform (16 m)
const POCKET := 1           # flood check on (drops a cliff that closes off ground)


## Place the landforms. ctx (metres, canonical frame): w_m, h_m, kind, pal,
## seed, hgt (sim/terrain.gd build()), excl (rectangles [x0, y0, x1, y1]
## kept clear, padded by the clearance), avoid (more such rectangles: the
## settlement's fields and orchards), obs (the 2 m grid so far, or empty),
## poly / poly_clr (a settlement's outline and how far outside it to stay),
## open_c / open_r (an open town: stay this far from its centre), shore (a
## coastal city's MapGen.coast_params: the sea above it), sea_cliffs (1:
## cliffs along that shore beyond the city), river (MapGen.river_geom,
## canonical), ref (a point on the attackers' ground, for the flood check).
static func place(ctx: Dictionary) -> Dictionary:
	var w_m: int = ctx["w_m"]
	var h_m: int = ctx["h_m"]
	var ow := w_m / 2
	var oh := h_m / 2
	var cells := PackedByteArray()
	cells.resize(ow * oh)
	cells.fill(0)
	var out := {"cells": cells, "cliffs": [], "rocks": [], "nodes": PackedInt32Array(), "n": 0}
	var hgt: Dictionary = ctx["hgt"]
	if int(hgt.get("on", 0)) == 0:
		return out
	var kind := clampi(int(ctx["kind"]), 0, K_SLOPE)
	var pal := clampi(int(ctx.get("pal", 0)), 0, 4)
	var rng := _rng(int(ctx["seed"]) * 48271 + 911)
	var nx := int(hgt["nx"])
	var ny := int(hgt["ny"])
	var h: PackedInt32Array = hgt["h"]
	var g := _grades(h, nx, ny)
	var gx: PackedInt32Array = g[0]
	var gy: PackedInt32Array = g[1]
	var gm: PackedInt32Array = g[2]
	var ld := PackedByteArray()
	ld.resize(ow * oh)
	ld.fill(255)
	ctx["_ld"] = ld
	ctx["_ow"] = ow
	ctx["_oh"] = oh
	ctx["_cells"] = cells
	var feats: Array = []  # [kind 0 cliff / 1 rock, cell indices, record index]
	# ---- cliffs on the steepest ground, along the contours.
	var n_cl := CLIFFS[kind]
	if n_cl > 0:
		n_cl = n_cl / 2 + _r(rng, n_cl - n_cl / 2 + 1) + (1 if pal == PAL_ROCKY else 0)
	var thr := _steep_threshold(gm)
	var cand := PackedInt32Array()
	if n_cl > 0 and thr > 0:
		for k in gm.size():
			if gm[k] >= thr:
				cand.append(k)
	for c in n_cl:
		if cand.is_empty():
			break
		var best := -1
		var best_g := -1
		for tries in 14:
			var k := cand[_r(rng, cand.size())]
			if gm[k] <= best_g:
				continue
			if not _free(ctx, (k % nx) * 4, (k / nx) * 4, CLIFF_CLR):
				continue
			best = k
			best_g = gm[k]
		var ln := _rr(rng, CLIFF_LEN[0], CLIFF_LEN[1])
		if best < 0:
			continue
		var trc := _trace(ctx, gx, gy, gm, nx, ny, (best % nx) * 400, (best / nx) * 400, ln, thr * 2 / 3)
		var pts: PackedInt32Array = trc[0]
		if pts.size() / 2 < CLIFF_MIN / STEP + 1:
			continue
		var cl := _raster_line(ctx, pts, C_CLIFF)
		if cl.is_empty():
			continue
		_stamp(ctx, cl)
		feats.append([0, cl, (out["cliffs"] as Array).size()])
		(out["cliffs"] as Array).append({"p": pts, "dn": trc[1], "h": trc[2]})
	# ---- sea cliffs along a rocky shore beyond the city.
	if int(ctx.get("sea_cliffs", 0)) != 0 and ctx.get("shore") is PackedInt32Array:
		_sea_cliffs(ctx, rng, out, feats)
	# ---- rock outcrops on crests and rough ground.
	var mean := _box_mean(h, nx, ny, 3)
	var n_rk := ROCKS[kind] * ROCK_PAL[pal] / 100
	if n_rk > 0:
		n_rk = n_rk * 3 / 4 + _r(rng, n_rk / 2 + 1)
	var placed := 0
	var guard := 0
	while placed < n_rk and guard < n_rk * 3:
		guard += 1
		var best_x := -1
		var best_y := -1
		var best_s := -(1 << 30)
		for tries in 8:
			var x := _rr(rng, EDGE, w_m - EDGE)
			var y := _rr(rng, EDGE, h_m - EDGE)
			var k := mini(y / 4, ny - 1) * nx + mini(x / 4, nx - 1)
			var crest := (h[k] - mean[k]) * 10 / M   # decimetres above the ground round it
			var s := gm[k] * 3 / 41 + crest * 2 + _r(rng, 30)
			if s <= best_s or not _free(ctx, x, y, ROCK_CLR + 5):
				continue
			best_s = s
			best_x = x
			best_y = y
		if best_x < 0:
			continue
		var n_made := _rock(ctx, rng, out, feats, best_x, best_y, h, nx, ny)
		if n_made > 0:
			placed += 1
			# Outcrops come in groups: now and then a second one near by.
			if _r(rng, 10) < 4:
				var a := _r(rng, 1024)
				var d := _rr(rng, 10, 16)
				var x2 := best_x + FM.cos_a(a) * d / FM.TRIG_ONE
				var y2 := best_y + FM.sin_a(a) * d / FM.TRIG_ONE
				if _free(ctx, x2, y2, ROCK_CLR + 3):
					if _rock(ctx, rng, out, feats, x2, y2, h, nx, ny) > 0:
						placed += 1
	# ---- no piece of ground closed off (a cliff that does is dropped).
	if POCKET != 0 and not (out["cliffs"] as Array).is_empty() and ctx.has("ref"):
		_pockets(ctx, out, feats)
	# ---- street-graph nodes round every landform left.
	var nodes: PackedInt32Array = out["nodes"]
	for cl2 in out["cliffs"]:
		var c2: Dictionary = cl2
		if c2.has("gone"):
			continue
		_cliff_nodes(nodes, c2["p"])
	for rk in out["rocks"]:
		var a2: Array = rk
		var ext := 0
		var x0 := int(a2[2])
		var y0 := int(a2[3])
		for q in (a2.size() - 2) / 3:
			var b := 2 + q * 3
			ext = maxi(ext, FM.approx_len(int(a2[b]) - x0, int(a2[b + 1]) - y0) + int(a2[b + 2]))
		for s in 4:
			var aa := s * 256 + 128
			nodes.append(x0 + FM.cos_a(aa) * (ext + 5) / FM.TRIG_ONE)
			nodes.append(y0 + FM.sin_a(aa) * (ext + 5) / FM.TRIG_ONE)
	var kept: Array = []
	for cl3 in out["cliffs"]:
		if not (cl3 as Dictionary).has("gone"):
			kept.append(cl3)
	out["cliffs"] = kept
	out["nodes"] = nodes
	var n := 0
	for v in cells:
		if v != 0:
			n += 1
	out["n"] = n
	ctx.erase("_ld")
	ctx.erase("_cells")
	return out


# ----------------------------------------------------------------- rng ---

static func _rng(seed_v: int) -> PackedInt32Array:
	var s := PackedInt32Array([((seed_v & 0x7FFFFFFF) * 69069 + 0x5A17C0DE) & 0x7FFFFFFF])
	if s[0] == 0:
		s[0] = 0x2B7E151
	return s


static func _r(rng: PackedInt32Array, n: int) -> int:
	var x := rng[0]
	x ^= (x << 13) & 0x7FFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0x7FFFFFFF
	x &= 0x7FFFFFFF
	if x == 0:
		x = 0x2B7E151
	rng[0] = x
	return x % maxi(n, 1)


static func _rr(rng: PackedInt32Array, lo: int, hi: int) -> int:
	return lo + _r(rng, hi - lo + 1)


# ------------------------------------------------------------- ground ----

## Node gradients (Q12 grade, central differences as sim/terrain.gd) and
## their size: [gx, gy, grade].
static func _grades(h: PackedInt32Array, nx: int, ny: int) -> Array:
	var gx := PackedInt32Array()
	var gy := PackedInt32Array()
	var gm := PackedInt32Array()
	gx.resize(nx * ny)
	gy.resize(nx * ny)
	gm.resize(nx * ny)
	for j in ny:
		for i in nx:
			var k := j * nx + i
			var a := h[k + 1] - h[k] if i == 0 else (h[k] - h[k - 1] if i == nx - 1 else (h[k + 1] - h[k - 1]) / 2)
			var b := h[k + nx] - h[k] if j == 0 else (h[k] - h[k - nx] if j == ny - 1 else (h[k + nx] - h[k - nx]) / 2)
			gx[k] = a
			gy[k] = b
			gm[k] = FM.approx_len(a, b)
	return [gx, gy, gm]


## Grade above which the steepest CLIFF_PCT % of the nodes lie (at least
## G_MIN); 0 if no node is that steep.
static func _steep_threshold(gm: PackedInt32Array) -> int:
	var hist := PackedInt32Array()
	hist.resize(257)
	hist.fill(0)
	for v in gm:
		hist[mini(v / 16, 256)] += 1
	var want := gm.size() * CLIFF_PCT / 100
	var acc := 0
	var b := 256
	while b > 0 and acc + hist[b] <= want:
		acc += hist[b]
		b -= 1
	var thr := maxi((b + 1) * 16, G_MIN)
	for v in gm:
		if v >= thr:
			return thr
	return 0


## Mean height over the (2r+1)^2 nodes round each node (box blur with
## running sums, integer; fewer nodes at the edges).
static func _box_mean(h: PackedInt32Array, nx: int, ny: int, r: int) -> PackedInt32Array:
	var tmp := PackedInt32Array()
	tmp.resize(nx * ny)
	var cnt := PackedInt32Array()
	cnt.resize(maxi(nx, ny))
	for i in nx:
		cnt[i] = mini(i + r, nx - 1) - maxi(i - r, 0) + 1
	for j in ny:
		var row := j * nx
		var s := 0
		for i in mini(r, nx - 1) + 1:
			s += h[row + i]
		for i in nx:
			tmp[row + i] = s / cnt[i]
			if i + r + 1 < nx:
				s += h[row + i + r + 1]
			if i - r >= 0:
				s -= h[row + i - r]
	for j in ny:
		cnt[j] = mini(j + r, ny - 1) - maxi(j - r, 0) + 1
	var out := PackedInt32Array()
	out.resize(nx * ny)
	for i in nx:
		var s2 := 0
		for j in mini(r, ny - 1) + 1:
			s2 += tmp[j * nx + i]
		for j in ny:
			out[j * nx + i] = s2 / cnt[j]
			if j + r + 1 < ny:
				s2 += tmp[(j + r + 1) * nx + i]
			if j - r >= 0:
				s2 -= tmp[(j - r) * nx + i]
	return out


# ------------------------------------------------------------ clearance --

## (x, y) (m) may take a landform with `clr` metres clear round it: inside
## the field's margins, off the exclusions, outside the settlement (and
## its walls' reach), away from the sea and the river, and clr from the
## landforms already placed.
static func _free(ctx: Dictionary, x: int, y: int, clr: int) -> bool:
	var w_m: int = ctx["w_m"]
	var h_m: int = ctx["h_m"]
	if x < EDGE or y < EDGE or x > w_m - EDGE or y > h_m - EDGE:
		return false
	for e in ctx.get("excl", []):
		var a: Array = e
		if x >= int(a[0]) - clr and x <= int(a[2]) + clr and y >= int(a[1]) - clr and y <= int(a[3]) + clr:
			return false
	for e2 in ctx.get("avoid", []):
		var a2: Array = e2
		if x >= int(a2[0]) - 4 and x <= int(a2[2]) + 4 and y >= int(a2[1]) - 4 and y <= int(a2[3]) + 4:
			return false
	if ctx.has("open_r"):
		var oc: Vector2i = ctx["open_c"]
		var orr: int = ctx["open_r"] + clr
		if (x - oc.x) * (x - oc.x) + (y - oc.y) * (y - oc.y) < orr * orr:
			return false
	if ctx.get("poly_x") is PackedInt32Array:
		var vx: PackedInt32Array = ctx["poly_x"]
		var vy: PackedInt32Array = ctx["poly_y"]
		if _pt_in(vx, vy, x, y) or _poly_dist(vx, vy, x, y) < int(ctx["poly_clr"]) + clr:
			return false
	if ctx.get("shore") is PackedInt32Array:
		if y < _shore_y(ctx["shore"], x) + clr + 4:
			return false
	if ctx.get("river") is Dictionary:
		var g: Dictionary = ctx["river"]
		if absi(y * 100 - _river_y(g, x)) < (int(g["hw"]) + clr + 8) * 100:
			return false
		var xc := (int(g["xa"]) + int(g["xb"])) / 2
		if absi(x - xc) < 60 + clr:
			return false  # the crossing's approaches
	var ow: int = ctx["_ow"]
	var oh: int = ctx["_oh"]
	var i := clampi(x / 2, 0, ow - 1)
	var j := clampi(y / 2, 0, oh - 1)
	var ld: PackedByteArray = ctx["_ld"]
	if ld[j * ow + i] * 2 < clr:
		return false
	var obs: PackedByteArray = ctx.get("obs", PackedByteArray())
	if obs.size() == ow * oh and obs[j * ow + i] != C_OPEN:
		return false
	return true


## Clearance round newly placed cells: each cell within LD_CAP of them
## learns its distance (in cells, Chebyshev) to the nearest landform.
static func _stamp(ctx: Dictionary, cl: PackedInt32Array) -> void:
	var ld: PackedByteArray = ctx["_ld"]
	var ow: int = ctx["_ow"]
	var oh: int = ctx["_oh"]
	for c in cl:
		var ci := c % ow
		var cj := c / ow
		for dj in range(-LD_CAP, LD_CAP + 1):
			var jj := cj + dj
			if jj < 0 or jj >= oh:
				continue
			for di in range(-LD_CAP, LD_CAP + 1):
				var ii := ci + di
				if ii < 0 or ii >= ow:
					continue
				var d := maxi(absi(di), absi(dj))
				var q := jj * ow + ii
				if d < ld[q]:
					ld[q] = d


# --------------------------------------------------------------- cliffs --

## Follow the contour both ways from (sx, sy) (cm) up to ln metres in all,
## while the ground stays steeper than `lo` and the way is free. Returns
## [points (cm, x y pairs), downhill angle per point, height (dm) per point].
static func _trace(ctx: Dictionary, gx: PackedInt32Array, gy: PackedInt32Array, gm: PackedInt32Array,
		nx: int, ny: int, sx: int, sy: int, ln: int, lo: int) -> Array:
	var k0 := _node(sx, sy, nx, ny)
	var d0 := (FM.atan2_a(gy[k0], gx[k0]) + 256) & 1023
	var halves: Array = []
	for side in 2:
		var px := PackedInt32Array()
		var py := PackedInt32Array()
		var d := (d0 + 512 * side) & 1023
		var x := sx
		var y := sy
		var turned := 0
		var gone := 0
		while gone < ln * 100 / 2:
			var nxp := x + FM.cos_a(d) * STEP * 100 / FM.TRIG_ONE
			var nyp := y + FM.sin_a(d) * STEP * 100 / FM.TRIG_ONE
			var k := _node(nxp, nyp, nx, ny)
			if gm[k] < lo or not _free(ctx, nxp / 100, nyp / 100, CLIFF_CLR):
				break
			x = nxp
			y = nyp
			gone += STEP * 100
			px.append(x)
			py.append(y)
			# Turn toward the contour here (whichever way along it is ahead).
			var c := (FM.atan2_a(gy[k], gx[k]) + 256) & 1023
			if absi(FM.angle_diff(c, d)) > 256:
				c = (c + 512) & 1023
			var t := clampi(FM.angle_diff(d, c), -TURN_MAX, TURN_MAX)  # (c - d)
			turned += t
			if absi(turned) > TURN_SUM:
				break
			d = (d + t) & 1023
		halves.append([px, py])
	var pts := PackedInt32Array()
	var dn := PackedInt32Array()
	var hh := PackedInt32Array()
	var back: Array = halves[1]
	var bx: PackedInt32Array = back[0]
	var by: PackedInt32Array = back[1]
	for q in bx.size():
		var r := bx.size() - 1 - q
		pts.append(bx[r])
		pts.append(by[r])
	pts.append(sx)
	pts.append(sy)
	var fwd: Array = halves[0]
	var fx: PackedInt32Array = fwd[0]
	var fy: PackedInt32Array = fwd[1]
	for q in fx.size():
		pts.append(fx[q])
		pts.append(fy[q])
	for q in pts.size() / 2:
		var k2 := _node(pts[q * 2], pts[q * 2 + 1], nx, ny)
		dn.append((FM.atan2_a(-gy[k2], -gx[k2])) & 1023)
		# The face's height (view; cover and sight in 2b): steeper is higher.
		hh.append(clampi(gm[k2] * 60 / 4096 + 12, 14, 45))
	return [pts, dn, hh]


static func _node(x_cm: int, y_cm: int, nx: int, ny: int) -> int:
	return clampi((y_cm + 200) / 400, 0, ny - 1) * nx + clampi((x_cm + 200) / 400, 0, nx - 1)


## Cells within CLIFF_HW of the polyline (cm) become `kind` (open cells
## only). Returns their indices (in index order of the scan).
static func _raster_line(ctx: Dictionary, pts: PackedInt32Array, kind: int) -> PackedInt32Array:
	var cells: PackedByteArray = ctx["_cells"]
	var ow: int = ctx["_ow"]
	var oh: int = ctx["_oh"]
	var obs: PackedByteArray = ctx.get("obs", PackedByteArray())
	var has_obs := obs.size() == ow * oh
	var out := PackedInt32Array()
	var np := pts.size() / 2
	for q in maxi(np - 1, 1):
		var ax := pts[q * 2]
		var ay := pts[q * 2 + 1]
		var bx := pts[mini(q + 1, np - 1) * 2]
		var by := pts[mini(q + 1, np - 1) * 2 + 1]
		var i0 := maxi((mini(ax, bx) - CLIFF_HW) / 200, 0)
		var i1 := mini((maxi(ax, bx) + CLIFF_HW) / 200, ow - 1)
		var j0 := maxi((mini(ay, by) - CLIFF_HW) / 200, 0)
		var j1 := mini((maxi(ay, by) + CLIFF_HW) / 200, oh - 1)
		for j in range(j0, j1 + 1):
			for i in range(i0, i1 + 1):
				var c := j * ow + i
				if cells[c] != 0 or (has_obs and obs[c] != C_OPEN):
					continue
				if _seg_dist_cm(i * 200 + 100, j * 200 + 100, ax, ay, bx, by) <= CLIFF_HW:
					cells[c] = kind
					out.append(c)
	return out


## Sea cliffs: runs of cliff along the shore (just inland of the water)
## beyond the city and its approach, with gaps between them.
static func _sea_cliffs(ctx: Dictionary, rng: PackedInt32Array, out: Dictionary, feats: Array) -> void:
	var cp: PackedInt32Array = ctx["shore"]
	var w_m: int = ctx["w_m"]
	var skip_x0: int = ctx["sea_skip"][0]
	var skip_x1: int = ctx["sea_skip"][1]
	var x := EDGE + _rr(rng, 0, 20)
	while x < w_m - EDGE - CLIFF_MIN:
		var ln := _rr(rng, 30, 70)
		var gap := _rr(rng, 18, 40)
		var pts := PackedInt32Array()
		var dn := PackedInt32Array()
		var hh := PackedInt32Array()
		var xe := mini(x + ln, w_m - EDGE)
		var q := x
		while q <= xe:
			if q >= skip_x0 and q <= skip_x1:
				break
			var y := _shore_y(cp, q) + 2
			if not _sea_free(ctx, q, y):
				break
			pts.append(q * 100)
			pts.append(y * 100)
			dn.append(768)  # down to the sea (canonical: above)
			hh.append(_rr(rng, 30, 60))
			q += STEP
		if pts.size() / 2 >= CLIFF_MIN / STEP:
			var cl := _raster_line(ctx, pts, C_CLIFF)
			if not cl.is_empty():
				_stamp(ctx, cl)
				feats.append([0, cl, (out["cliffs"] as Array).size()])
				(out["cliffs"] as Array).append({"p": pts, "dn": dn, "h": hh, "sea": 1})
		x = maxi(q, x + STEP) + gap
		if q >= skip_x0 and q <= skip_x1:
			x = skip_x1 + gap


## A sea cliff's point: free of everything but the sea it stands over.
static func _sea_free(ctx: Dictionary, x: int, y: int) -> bool:
	var w_m: int = ctx["w_m"]
	var h_m: int = ctx["h_m"]
	if x < EDGE or x > w_m - EDGE or y > h_m - EDGE:
		return false
	for e in ctx.get("excl", []):
		var a: Array = e
		if x >= int(a[0]) - 8 and x <= int(a[2]) + 8 and y >= int(a[1]) - 8 and y <= int(a[3]) + 8:
			return false
	if ctx.get("poly_x") is PackedInt32Array:
		if _poly_dist(ctx["poly_x"], ctx["poly_y"], x, y) < int(ctx["poly_clr"]) + 10:
			return false
	var ow: int = ctx["_ow"]
	var i := clampi(x / 2, 0, ow - 1)
	var j := clampi(y / 2, 0, int(ctx["_oh"]) - 1)
	var ld: PackedByteArray = ctx["_ld"]
	return ld[j * ow + i] * 2 >= 8


## Nodes round a cliff (m): beyond each end and either side of it.
static func _cliff_nodes(nodes: PackedInt32Array, pts: PackedInt32Array) -> void:
	var np := pts.size() / 2
	if np < 2:
		return
	for e in 2:
		var a := 0 if e == 0 else np - 1
		var b := mini(3, np - 1) if e == 0 else maxi(np - 4, 0)
		var dx := pts[a * 2] - pts[b * 2]
		var dy := pts[a * 2 + 1] - pts[b * 2 + 1]
		var l := maxi(FM.isqrt(dx * dx + dy * dy), 1)
		nodes.append((pts[a * 2] + dx * 700 / l) / 100)
		nodes.append((pts[a * 2 + 1] + dy * 700 / l) / 100)
	var parts := 2 if np < 20 else 4
	for s in range(1, parts):
		var q := np * s / parts
		var q2 := mini(q + 1, np - 1)
		var q1 := maxi(q - 1, 0)
		var tx := pts[q2 * 2] - pts[q1 * 2]
		var ty := pts[q2 * 2 + 1] - pts[q1 * 2 + 1]
		var l2 := maxi(FM.isqrt(tx * tx + ty * ty), 1)
		for sg in [-1, 1]:
			nodes.append((pts[q * 2] - ty * 800 * int(sg) / l2) / 100)
			nodes.append((pts[q * 2 + 1] + tx * 800 * int(sg) / l2) / 100)


# ---------------------------------------------------------------- rocks --

## An outcrop at (x, y): a main boulder of radius 1-3 m and up to two
## smaller ones against it. Returns the cells made (0: none).
static func _rock(ctx: Dictionary, rng: PackedInt32Array, out: Dictionary, feats: Array, x: int, y: int,
		h: PackedInt32Array, nx: int, ny: int) -> int:
	var cells: PackedByteArray = ctx["_cells"]
	var ow: int = ctx["_ow"]
	var oh: int = ctx["_oh"]
	var obs: PackedByteArray = ctx.get("obs", PackedByteArray())
	var has_obs := obs.size() == ow * oh
	var r1 := 1 + _r(rng, 2) + (1 if _r(rng, 4) == 0 else 0)
	var discs := PackedInt32Array([x, y, r1])
	var ns := _r(rng, 3)
	for s in ns:
		var a := _r(rng, 1024)
		var d := r1 + _r(rng, 2)
		discs.append(x + FM.cos_a(a) * d / FM.TRIG_ONE)
		discs.append(y + FM.sin_a(a) * d / FM.TRIG_ONE)
		discs.append(1)
	var made := PackedInt32Array()
	for q in discs.size() / 3:
		var cx := discs[q * 3] * 100
		var cy := discs[q * 3 + 1] * 100
		var rr := discs[q * 3 + 2] * 100 + 30
		for j in range(maxi((cy - rr) / 200, 0), mini((cy + rr) / 200, oh - 1) + 1):
			for i in range(maxi((cx - rr) / 200, 0), mini((cx + rr) / 200, ow - 1) + 1):
				var c := j * ow + i
				if cells[c] != 0 or (has_obs and obs[c] != C_OPEN):
					continue
				var dx := i * 200 + 100 - cx
				var dy := j * 200 + 100 - cy
				if dx * dx + dy * dy <= rr * rr:
					cells[c] = C_ROCK
					made.append(c)
	if made.is_empty():
		return 0
	_stamp(ctx, made)
	var k := clampi(y / 4, 0, ny - 1) * nx + clampi(x / 4, 0, nx - 1)
	var rec: Array = [(h[k] ^ (x * 7919 + y * 104729)) & 0x7FFF, 10 + r1 * 6]
	for v in discs:
		rec.append(v)
	feats.append([1, made, (out["rocks"] as Array).size()])
	(out["rocks"] as Array).append(rec)
	return made.size()


# -------------------------------------------------------------- pockets --

## Flood the open ground from the attackers' point (gates open, the
## landforms shut) on 4 m blocks (a block is open when its four 2 m cells
## are: landforms keep 12 m apart, so this closes no real gap); a cliff
## with open ground beside it that the flood did not reach closes something
## off: it is dropped (cells back to open, marked "gone"), and the flood
## runs again.
static func _pockets(ctx: Dictionary, out: Dictionary, feats: Array) -> void:
	var cells: PackedByteArray = ctx["_cells"]
	var ow: int = ctx["_ow"]
	var oh: int = ctx["_oh"]
	var bw := ow / 2
	var bh := oh / 2
	var nb := bw * bh
	var obs: PackedByteArray = ctx.get("obs", PackedByteArray())
	var has_obs := obs.size() == ow * oh
	var ref: Vector2i = ctx["ref"]
	var start := clampi(ref.y / 4, 0, bh - 1) * bw + clampi(ref.x / 4, 0, bw - 1)
	var q := PackedInt32Array()
	q.resize(nb)
	# Blocks shut by something other than a landform (walls, water, houses).
	var base := PackedByteArray()
	base.resize(nb)
	if has_obs:
		for c in ow * oh:
			var k := obs[c]
			if not (k == C_OPEN or k == C_DITCH or (k >= C_GATE and k < C_ROCK)):
				var bi := c % ow / 2
				var bj := c / ow / 2
				if bi < bw and bj < bh:
					base[bj * bw + bi] = 1
	for it in 4:
		# 1: open ground not reached yet; 2: reached.
		var fr := PackedByteArray()
		fr.resize(nb)
		for k2 in nb:
			if base[k2] == 0:
				fr[k2] = 1
		for f in feats:
			var fa0: Array = f
			if int(fa0[0]) == 0 and (out["cliffs"][int(fa0[2])] as Dictionary).has("gone"):
				continue
			for c in (fa0[1] as PackedInt32Array):
				var bi2 := c % ow / 2
				var bj2 := c / ow / 2
				if bi2 < bw and bj2 < bh:
					fr[bj2 * bw + bi2] = 0
		if fr[start] == 0:
			return
		q[0] = start
		fr[start] = 2
		var head := 0
		var tail := 1
		while head < tail:
			var c := q[head]
			head += 1
			var i := c % bw
			if i > 0 and fr[c - 1] == 1:
				fr[c - 1] = 2
				q[tail] = c - 1
				tail += 1
			if i + 1 < bw and fr[c + 1] == 1:
				fr[c + 1] = 2
				q[tail] = c + 1
				tail += 1
			if c >= bw and fr[c - bw] == 1:
				fr[c - bw] = 2
				q[tail] = c - bw
				tail += 1
			if c + bw < nb and fr[c + bw] == 1:
				fr[c + bw] = 2
				q[tail] = c + bw
				tail += 1
		var dropped := false
		for f in feats:
			var fa: Array = f
			if int(fa[0]) != 0:
				continue
			var rec: Dictionary = out["cliffs"][int(fa[2])]
			if rec.has("gone"):
				continue
			var shut := false
			for c in (fa[1] as PackedInt32Array):
				var i2 := c % ow / 2
				var j2 := c / ow / 2
				if i2 >= bw or j2 >= bh:
					continue
				var b := j2 * bw + i2
				if (i2 > 0 and fr[b - 1] == 1) or (i2 + 1 < bw and fr[b + 1] == 1) \
						or (j2 > 0 and fr[b - bw] == 1) or (j2 + 1 < bh and fr[b + bw] == 1):
					shut = true
					break
			if shut:
				for c in (fa[1] as PackedInt32Array):
					cells[c] = 0
				rec["gone"] = 1
				dropped = true
		if not dropped:
			return


# ------------------------------------------------------------- forest ----

## Terrain terms for the woods (sim/mapgen.gd _forest, on maps with
## landforms): added to the blob field `f` (4 m cells, vw x vh) before its
## thresholds. Valley floors and hollows, the lower slopes and the lee of
## the ridges (from a wind drawn from the seed) grow woods; crests, steep
## faces and rock do not; river banks (canonical river geometry `rg`) carry
## a band of trees; a fine hash noise rags the edges.
static func forest_terms(f: PackedInt32Array, vw: int, vh: int, hgt: Dictionary, rg: Dictionary,
		cells: PackedByteArray, ow: int, oh: int, seed_v: int) -> void:
	var on := int(hgt.get("on", 0)) != 0
	var nx := int(hgt.get("nx", 0))
	var ny := int(hgt.get("ny", 0))
	var h: PackedInt32Array = hgt.get("h", PackedInt32Array())
	var mean := PackedInt32Array()
	var g: Array = []
	var gmean := 0
	if on:
		mean = _box_mean(h, nx, ny, 6)
		g = _grades(h, nx, ny)
		for v in h:
			gmean += v
		gmean /= maxi(h.size(), 1)
	var rng := _rng(seed_v * 31 + 5)
	var wind := _r(rng, 1024)
	var wc := FM.cos_a(wind)
	var ws := FM.sin_a(wind)
	var has_cells := cells.size() == ow * oh and ow > 0
	for j in vh:
		for i in vw:
			var t := 0
			if on:
				var k := mini(j, ny - 1) * nx + mini(i, nx - 1)
				var hv := h[k]
				t += clampi((mean[k] - hv) * 70 / M, -450, 450)     # hollows and valley floors
				t += clampi((gmean - hv) * 12 / M, -200, 200)       # lower ground
				var gr: int = (g[2] as PackedInt32Array)[k]
				if gr >= 200 and gr <= 740:
					t += 140                                        # the lower slopes
				elif gr > 900:
					t -= 260                                        # steep faces stay bare
				if gr >= 160:
					# The lee: ground falling away with the wind.
					var along := ((g[0] as PackedInt32Array)[k] * wc + (g[1] as PackedInt32Array)[k] * ws) / FM.TRIG_ONE
					t += clampi(-along * 300 / 410, -220, 220)
			if not rg.is_empty():
				var d := absi((j * 4 + 2) * 100 - _river_y(rg, i * 4 + 2)) / 100 - int(rg["hw"])
				if d >= 4 and d <= 45:
					t += 320 * (45 - d) / 41
			var hsh := ((i * 73856093) ^ (j * 19349663) ^ (seed_v * 83492791)) & 0x7FFFFFFF
			hsh = ((hsh ^ (hsh >> 13)) * 0x5bd1e995) & 0x7FFFFFFF
			t += (hsh >> 9) % 241 - 120
			if has_cells:
				var oc := mini(j * 2 + 1, oh - 1) * ow + mini(i * 2 + 1, ow - 1)
				if cells[oc] >= C_ROCK:
					t -= 2000
			f[j * vw + i] += t


## Contour direction (angle, 0..1023) at (x, y) metres, or -1 on level
## ground (for the woods' long blobs).
static func contour_at(hgt: Dictionary, x: int, y: int) -> int:
	if int(hgt.get("on", 0)) == 0:
		return -1
	var nx := int(hgt["nx"])
	var ny := int(hgt["ny"])
	var h: PackedInt32Array = hgt["h"]
	var i := clampi(x / 4, 1, nx - 2)
	var j := clampi(y / 4, 1, ny - 2)
	var a := (h[j * nx + i + 1] - h[j * nx + i - 1]) / 2
	var b := (h[(j + 1) * nx + i] - h[(j - 1) * nx + i]) / 2
	if FM.approx_len(a, b) < 120:
		return -1
	return (FM.atan2_a(b, a) + 256) & 1023


# ------------------------------------------------------------- geometry --
# (Copies of sim/mapgen.gd's: this file does not preload it.)

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
	return absi(rx * dy - ry * dx) / maxi(FM.isqrt(den), 1)


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


static func _poly_dist(vx: PackedInt32Array, vy: PackedInt32Array, x: int, y: int) -> int:
	var n := vx.size()
	var best := 1 << 30
	for k in n:
		var k2 := (k + 1) % n
		best = mini(best, _seg_dist_cm(x * 100, y * 100, vx[k] * 100, vy[k] * 100, vx[k2] * 100, vy[k2] * 100))
	return best / 100


## MapGen.shore_y (canonical y of the shoreline at x, m).
static func _shore_y(cp: PackedInt32Array, x: int) -> int:
	var y := cp[0] + cp[1] * (x - cp[2]) / 1000
	var ex := maxi(absi(x - cp[2]) - cp[3], 0)
	if ex > 0:
		var ramp := mini(ex, 40)
		var wave := cp[5] * FM.sin_a((cp[6] + ex * 1024 / 150) & 1023) \
			+ cp[7] * FM.sin_a((cp[8] + ex * 1024 / 60) & 1023)
		y += ex * cp[4] / 1000 + wave * ramp / 40 / FM.TRIG_ONE
	return maxi(y, 20)


## MapGen.river_y (canonical centre line y, cm, at x m).
static func _river_y(g: Dictionary, x: int) -> int:
	var d := x - int(g["xc"])
	var a := (d * 1024 / int(g["l1"]) + int(g["ph"])) & 1023
	var b := (d * 1024 / int(g["l2"]) + int(g["p2"])) & 1023
	return int(g["h"]) * 50 - int(g["a1"]) * 100 * FM.cos_a(a) / FM.TRIG_ONE \
		+ int(g["a2"]) * 100 * FM.sin_a(b) / FM.TRIG_ONE
