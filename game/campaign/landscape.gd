extends RefCounted
## Campaign map landscape (view only, 2026-10-10): baked ONCE from the grid
## and the regions' data, drawn by map_view.gd's Terrain view.
##  - ground texture (one pixel per grid cell, drawn bilinear over the land):
##    each region's ground palette (game/ground_palette.gd, lifted like the
##    Political fill), the arid south sandier with latitude, hill and ridge
##    cells towards the palette's high ground, valley regions and cells
##    between hills a lower, greener tone; blurred over the land only so
##    region borders blend into one landscape;
##  - the relief texture (2026-10-10): the REAL elevation (geo_fields.gd, 0.025
##    degree samples, ETOPO 2022) hillshaded from the north-west with a
##    subtle hypsometric tint and a thin dark line along the crests; no
##    glyphs for mountains;
##  - one mesh of glyphs (vertex colours): trees in the battle map's kinds (tree_layer.gd:
##    broadleaf, pine, scrub, cypress; canopy shades from the palette) with
##    density from the region's forest % and clustered by a hash of the cell
##    block, rocks and scrub speckles on rocky and dry ground.
## Trees and speckles keep off the sea, road and river cells, the cities
## (settlement, port, camp cells and their neighbours) and the ridge peaks.
## Everything is a pure function of the grid and CData: nothing is stored.

const CData := preload("res://campaign/cdata.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const Geo := preload("res://game/campaign/map_geo.gd")
const GroundPalette := preload("res://game/ground_palette.gd")
const MapGen := preload("res://sim/mapgen.gd")

const LIFT := 0.30             # the battle palettes are darker than a map should be
const BLUR := 2                # cells, box blur applied twice (land only)
const SAND := Color(0.86, 0.76, 0.52)
const TREES_PER_CELL := 7.0    # at 100 % forest, before clustering
const MAX_TREES := 4500
const MAX_SPECKS := 3500

const COL_ROCK := Color(0.66, 0.63, 0.57)
const COL_ROCK_SHADE := Color(0.18, 0.15, 0.10, 0.45)
const COL_SCRUB := Color(0.40, 0.42, 0.22, 0.85)
const COL_BANK := Color(0.93, 0.95, 0.80, 0.55)
const VALLEY_GREEN := Color(0.40, 0.58, 0.30)
const COL_VALLEY_STRIP := Color(0.32, 0.55, 0.26, 0.26)

static var ground_tex: ImageTexture = null
static var mesh: ArrayMesh = null
static var bake_ms := -1.0
static var tree_count := 0
static var relief_tex: ImageTexture = null
static var _elev := PackedFloat32Array()   # metres, GeoFields.fine()
const GeoFields := preload("res://game/campaign/geo_fields.gd")
const RS := 8                 # relief field samples per grid cell side
const TREELINE := 1800.0      # no trees above (m)
const SCRUB_LINE := 2600.0    # no rocks and scrub speckles above (m)
static var speck_count := 0
static var _land_polys: Array = []
static var _land_boxes: Array = []
## Region a cell takes its ground from: its own, or for unclaimed land the
## nearest region's (flood fill), -1 for the sea.
static var _near := PackedInt32Array()

# Mesh builder state.
static var _v := PackedVector2Array()
static var _c := PackedColorArray()
static var _i := PackedInt32Array()
static var _rings: Array = []   # unit rings: broadleaf x3, pine x3, scrub x3, cypress, small disc


static func bake() -> void:
	if ground_tex != null:
		return
	var t0 := Time.get_ticks_usec()
	_land_polys = Geo.lands() + Geo.islands()
	_land_boxes = []
	for poly in _land_polys:
		var bx := Rect2(poly[0], Vector2.ZERO)
		for pt in poly:
			bx = bx.expand(pt)
		_land_boxes.append(bx.grow(1.0))
	_flood()
	_bake_ground()
	_bake_relief()
	_bake_glyphs()
	bake_ms = (Time.get_ticks_usec() - t0) / 1000.0


static func _flood() -> void:
	var w := CGrid.width()
	var h := CGrid.height()
	_near = PackedInt32Array()
	_near.resize(w * h)
	var queue: Array[int] = []
	for c in w * h:
		var r := CGrid.region(c)
		_near[c] = r if r >= 0 else (-2 if r == -2 else -1)
		if r >= 0:
			queue.append(c)
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var x := c % w
		var y := c / w
		var v := _near[c]
		if x < w - 1 and _near[c + 1] == -2:
			_near[c + 1] = v
			queue.append(c + 1)
		if x > 0 and _near[c - 1] == -2:
			_near[c - 1] = v
			queue.append(c - 1)
		if y < h - 1 and _near[c + w] == -2:
			_near[c + w] = v
			queue.append(c + w)
		if y > 0 and _near[c - w] == -2:
			_near[c - w] = v
			queue.append(c - w)
	for c in w * h:
		if _near[c] == -2:
			_near[c] = -1


static func _h(a: int, b: int, s: int) -> float:
	var x := (a * 73856093) ^ (b * 19349663) ^ (s * 83492791)
	x = ((x ^ (x >> 13)) * 1274126177) & 0x7FFFFFFF
	x = (x ^ (x >> 16)) & 0xFFFFFF
	return float(x & 0xFFFF) / 65536.0


static func _lat(r: int) -> float:
	return float(CData.REGIONS[r]["lat"]) / 100.0


## Ground colour of cell c (before the blur).
static func _region_tones(r: int) -> Array:
	var pi := int(CData.REGIONS[r]["ground"])
	var pal := GroundPalette.get_palette(pi)
	var base: Color = (pal["base"] as Color).lightened(LIFT)
	var lat := _lat(r)
	if pi == MapGen.PAL_ARID:
		base = base.lerp(SAND, 0.25 + 0.55 * clampf((38.5 - lat) / 3.0, 0.0, 1.0))
	elif pi == MapGen.PAL_DRY and lat < 37.5:
		base = base.lerp(SAND, 0.2)
	var low: Color = (GroundPalette.get_palette(MapGen.PAL_GREEN)["low"] as Color).lightened(LIFT)
	var valley := base.lerp(low, 0.55)
	return [base,
		base.lerp((GroundPalette.get_palette(MapGen.PAL_ROCKY)["high"] as Color).lightened(LIFT), 0.6),
		base.lerp((pal["high"] as Color).lightened(LIFT), 0.5),
		valley if int(CData.REGIONS[r]["terrain"]) == CData.VALLEY else base, valley]


## Ground colour of cell c (before the blur); tones: [flat, ridge, hill,
## region's own, valley].
static func _cell_ground(c: int, hilly: PackedByteArray, tones: Array) -> Color:
	var ov := CGrid.terrain_override(c)
	var base: Color
	if ov == CData.RIDGE:
		base = tones[1]
	elif ov >= 0:
		base = tones[2]
	elif hilly[c] >= 7:
		base = tones[4]
	else:
		base = tones[3]
	# Real terrain class: plains quiet, rolling land dappled, valley floors
	# greener along the rivers (wider where the ground is flat).
	var cls := GeoFields.cell_class(c)
	var amp := 0.07
	var n := _h(CGrid.cx(c), CGrid.cy(c), 1) - 0.5
	if cls == GeoFields.CLASS_PLAIN:
		amp = 0.025
	elif cls == GeoFields.CLASS_ROLLING:
		amp = 0.07 + 0.05 * (_h(CGrid.cx(c) / 2, CGrid.cy(c) / 2, 2) - 0.5)
		n += 0.8 * (_h(CGrid.cx(c) / 3, CGrid.cy(c) / 3, 3) - 0.5)
	if cls != GeoFields.CLASS_SEA and cls < GeoFields.CLASS_HILL:
		var d := GeoFields.river_dist(c)
		var flat := 1.0 - clampf(float(GeoFields.cell_relief(c)) / 400.0, 0.0, 1.0)
		var reach := 1.2 + 2.2 * flat
		var gv := clampf(1.0 - d / reach, 0.0, 1.0) * (0.4 + 0.3 * flat)
		if cls == GeoFields.CLASS_VALLEY:
			gv = maxf(gv, 0.3)
		if gv > 0.0:
			base = base.lerp(tones[4], gv * 1.2).lerp(VALLEY_GREEN, gv * 0.35)
	return base.lightened(n * amp) if n > 0.0 else base.darkened(-n * amp)


static func _bake_ground() -> void:
	var w := CGrid.width()
	var h := CGrid.height()
	var n := w * h
	# Hill / ridge cells within 2 cells (valley detection).
	var hilly := PackedByteArray()
	hilly.resize(n)
	for c in n:
		if CGrid.terrain_override(c) < 0:
			continue
		var x := CGrid.cx(c)
		var y := CGrid.cy(c)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var xx := x + dx
				var yy := y + dy
				if xx >= 0 and yy >= 0 and xx < w and yy < h:
					hilly[yy * w + xx] += 1
	var rr := PackedFloat32Array()
	var gg := PackedFloat32Array()
	var bb := PackedFloat32Array()
	var wt := PackedFloat32Array()
	for a in [rr, gg, bb, wt]:
		a.resize(n)
	var region_tones: Array = []
	for r in CData.region_count():
		region_tones.append(_region_tones(r))
	var fallback := GroundPalette.land_color(MapGen.PAL_DRY).lightened(LIFT)
	for c in n:
		if _near[c] >= 0:
			var col := _cell_ground(c, hilly, region_tones[_near[c]])
			rr[c] = col.r
			gg[c] = col.g
			bb[c] = col.b
			wt[c] = 1.0
	# Normalised box blur: land cells only, so coasts do not darken.
	var chans := [rr, gg, bb, wt]
	for _pass in 2:
		for horiz in 2:
			for k in 4:
				chans[k] = _blur(chans[k], w, h, horiz == 0)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for c in n:
		var ww: float = chans[3][c]
		var col2 := fallback
		if ww > 0.001:
			col2 = Color(chans[0][c] / ww, chans[1][c] / ww, chans[2][c] / ww)
		img.set_pixel(c % w, c / w, col2)
	ground_tex = ImageTexture.create_from_image(img)


static func _blur(src: PackedFloat32Array, w: int, h: int, horiz: bool) -> PackedFloat32Array:
	var o := PackedFloat32Array()
	o.resize(w * h)
	var outer := h if horiz else w
	var inner := w if horiz else h
	var stride := 1 if horiz else w       # step along the blurred axis
	var ostride := w if horiz else 1      # step between lines
	for line in outer:
		var base := line * ostride
		var sum := 0.0
		for k in mini(BLUR, inner):
			sum += src[base + k * stride]
		for k in inner:
			var add := k + BLUR
			if add < inner:
				sum += src[base + add * stride]
			var sub := k - BLUR - 1
			if sub >= 0:
				sum -= src[base + sub * stride]
			o[base + k * stride] = sum
	return o


# Mesh builder.

static func _tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
	var k := _v.size()
	_v.append(a)
	_v.append(b)
	_v.append(c)
	for q in 3:
		_c.append(col)
	_i.append_array(PackedInt32Array([k, k + 1, k + 2]))


## A fan around ctr of unit-ring points scaled by (sx, sy).
static func _fan(ctr: Vector2, pts: PackedVector2Array, sx: float, sy: float, col: Color) -> void:
	var k := _v.size()
	var n := pts.size()
	_v.resize(k + n + 1)
	_c.resize(k + n + 1)
	_v[k] = ctr
	_c[k] = col
	for j in n:
		var q := pts[j]
		_v[k + 1 + j] = Vector2(ctr.x + q.x * sx, ctr.y + q.y * sy)
		_c[k + 1 + j] = col
	var ki := _i.size()
	_i.resize(ki + n * 3)
	for j in n:
		_i[ki + j * 3] = k
		_i[ki + j * 3 + 1] = k + 1 + j
		_i[ki + j * 3 + 2] = k + 1 + (j + 1) % n


static func _ring(seg: int, wob: float, phase: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for j in seg:
		var a := TAU * j / seg
		var f := 1.0 + wob * sin(a * 3.0 + phase) * (1.0 if j % 2 == 0 else 0.6)
		out.append(Vector2(cos(a) * f, sin(a) * f))
	return out


static func _star(seg: int, rot: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for j in seg * 2:
		var a := TAU * j / (seg * 2) + rot
		var f := 1.0 if j % 2 == 0 else 0.62
		out.append(Vector2(cos(a) * f, sin(a) * f))
	return out


static func _elev_at(x: float, y: float) -> float:
	var w := CGrid.width() * RS
	var k := float(CGrid.cell_px()) / RS
	var ix := clampi(int(x / k), 0, w - 1)
	var iy := clampi(int(y / k), 0, CGrid.height() * RS - 1)
	return _elev[iy * w + ix]


## Cone kernel of radius r (1 at the centre, 0 at the rim), (2r+1)^2.
static func _kernel(r: int) -> PackedFloat32Array:
	var k := PackedFloat32Array()
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			k.append(maxf(0.0, 1.0 - sqrt(float(dx * dx + dy * dy)) / r))
	return k


## Raise the field to hgt * kernel under (cx, cy) (max).
static func _stamp(e: PackedFloat32Array, w: int, h: int, cx: int, cy: int, hgt: float, kern: PackedFloat32Array, r: int) -> void:
	var side := 2 * r + 1
	for dy in side:
		var y := cy + dy - r
		if y < 0 or y >= h:
			continue
		for dx in side:
			var kv := kern[dy * side + dx]
			if kv <= 0.0:
				continue
			var x := cx + dx - r
			if x < 0 or x >= w:
				continue
			var v := hgt * kv
			var i := y * w + x
			if v > e[i]:
				e[i] = v


static func _bake_relief() -> void:
	_elev = GeoFields.fine()
	var w := CGrid.width() * RS
	var h := CGrid.height() * RS
	# The shading is the slow part of the bake (about 1.5 s, several times
	# that in the web build): cached as a PNG in user://, keyed by the data
	# and the look parameters.
	var key := str([GeoFields.Relief.FINE.hash(), GeoFields.Relief.COAST.hash(), RELIEF_CODE, BEACH_KM, COL_BEACH, COL_CLIFF, TINT_STOPS, SUN, EXAG, SHADE_GAIN, LIGHT_TINT,
		SHADOW_TINT, CREST_COL, UPSAMPLE]).hash()
	var path := "user://relief_%d.png" % key
	var img: Image = null
	if FileAccess.file_exists(path):
		img = Image.load_from_file(path)
		if img != null and (img.get_width() != w * UPSAMPLE or img.get_height() != h * UPSAMPLE):
			img = null
	if img == null:
		img = relief_image(_elev, w, h, GeoFields.sample_m(), UPSAMPLE, GeoFields.coast())
		var tmp := "user://relief_tmp_%d.png" % Time.get_ticks_usec()
		if img.save_png(tmp) == OK:
			DirAccess.rename_absolute(tmp, path)
		# (Old caches of other looks stay; a few MB each.)
	relief_tex = ImageTexture.create_from_image(img)


# Hillshade and tint of the elevation field (metres; one pixel per sample).
const RELIEF_CODE := 3                    # bump when relief_image changes
## Beaches and cliffs (2026-10-10): within BEACH_KM of the coast (the signed
## distance field of tools/geo_fit.py, geo_fields.gd coast()), low ground
## takes a band of sand, a steep rise from the coast a dark cliff line.
const BEACH_KM := 3.0
const COL_BEACH := Color(0.90, 0.83, 0.62)
const COL_CLIFF := Color(0.22, 0.17, 0.12)
const UPSAMPLE := 2                       # relief image pixels per elevation sample
const SUN := Vector3(-0.55, -0.55, 0.63)   # towards the light: north-west, 39 deg up
const EXAG := 2.0                          # vertical exaggeration of the slopes
const SHADE_GAIN := 2.0
const LIGHT_TINT := Color(1.0, 0.95, 0.82)
const SHADOW_TINT := Color(0.13, 0.12, 0.22)
const CREST_COL := Color(0.16, 0.12, 0.10)
## Hypsometric stops: [metres, colour, tint alpha]. Greens to tans to
## grey-brown; pale only above 2,000 m.
const TINT_STOPS := [
	[0.0, Color(0.50, 0.62, 0.34), 0.0],
	[150.0, Color(0.52, 0.62, 0.34), 0.10],
	[500.0, Color(0.60, 0.60, 0.36), 0.34],
	[900.0, Color(0.68, 0.58, 0.38), 0.50],
	[1400.0, Color(0.62, 0.50, 0.37), 0.58],
	[1900.0, Color(0.58, 0.49, 0.41), 0.62],
	[2400.0, Color(0.66, 0.62, 0.58), 0.58],
	[3000.0, Color(0.80, 0.79, 0.77), 0.62],
	[4600.0, Color(0.88, 0.88, 0.89), 0.66],
]
const LUT_STEP := 10.0


static func _tint_lut() -> Array:
	var n := int(4700.0 / LUT_STEP) + 1
	var cr := PackedFloat32Array()
	var cg := PackedFloat32Array()
	var cb := PackedFloat32Array()
	var ca := PackedFloat32Array()
	for k in n:
		var m := k * LUT_STEP
		var col := Color.WHITE
		var al := 0.0
		for j in TINT_STOPS.size() - 1:
			var s0: Array = TINT_STOPS[j]
			var s1: Array = TINT_STOPS[j + 1]
			if m >= float(s0[0]) and m <= float(s1[0]):
				var t := (m - float(s0[0])) / (float(s1[0]) - float(s0[0]))
				col = (s0[1] as Color).lerp(s1[1], t)
				al = lerpf(float(s0[2]), float(s1[2]), t)
				break
		cr.append(col.r)
		cg.append(col.g)
		cb.append(col.b)
		ca.append(al)
	return [cr, cg, cb, ca]


## Hillshade + hypsometric image of an elevation field e (metres, w x h,
## pix_m metres a sample): Lambert shading from the north-west, a subtle
## tint by height, a thin dark line where the ground is a local crest.
## Transparent on the flat and low ground, so the ground texture shows.
static func relief_image(e0: PackedFloat32Array, w0: int, h0: int, pix_m0: float, up: int = UPSAMPLE,
		coast0: PackedByteArray = PackedByteArray()) -> Image:
	var e := e0
	var w := w0
	var h := h0
	var pix_m := pix_m0
	if up > 1:
		# Smooth (cubic) upsampling of the elevation, so the shading has no
		# per-sample stair-steps; not a blur: the field keeps its detail.
		var src := Image.create_from_data(w0, h0, false, Image.FORMAT_RF, e0.to_byte_array())
		src.resize(w0 * up, h0 * up, Image.INTERPOLATE_CUBIC)
		e = src.get_data().to_float32_array()
		w = w0 * up
		h = h0 * up
		pix_m = pix_m0 / up
	# Signed distance to the coast (km, land negative), upsampled like the elevation.
	var cst := PackedFloat32Array()
	if coast0.size() == w0 * h0:
		var ci := Image.create_from_data(w0, h0, false, Image.FORMAT_L8, coast0)
		ci.convert(Image.FORMAT_RF)
		if up > 1:
			ci.resize(w0 * up, h0 * up, Image.INTERPOLATE_BILINEAR)
		cst = ci.get_data().to_float32_array()
	var has_coast := cst.size() == w * h
	var data := PackedByteArray()
	data.resize(w * h * 4)
	var lut := _tint_lut()
	var lr: PackedFloat32Array = lut[0]
	var lg: PackedFloat32Array = lut[1]
	var lb: PackedFloat32Array = lut[2]
	var la: PackedFloat32Array = lut[3]
	var nl := lr.size() - 1
	var inv2 := EXAG / (2.0 * pix_m)
	var sun := SUN.normalized()
	var sx := sun.x
	var sy := sun.y
	var sz := sun.z
	var m2 := 2 * up
	var m4 := 4 * up
	var lit_c := LIGHT_TINT
	var sh_c := SHADOW_TINT
	for y in range(1, h - 1):
		var row := y * w
		for x in range(1, w - 1):
			var i := row + x
			var v := e[i]
			var l := e[i - 1]
			var r := e[i + 1]
			var u := e[i - w]
			var d := e[i + w]
			var dx := r - l
			var dy := d - u
			# Beach and cliff (the land side of the coast, within BEACH_KM).
			var sand_a := 0.0
			var cliff_a := 0.0
			if has_coast:
				var lk := 128.0 - cst[i] * 255.0   # km inland (negative: sea side)
				if lk > 0.0 and lk < BEACH_KM:
					sand_a = (1.0 - smoothstep(1.0, BEACH_KM, lk)) * (1.0 - smoothstep(30.0, 120.0, v)) * 0.8
					var rise := sqrt(dx * dx + dy * dy) * 0.5 / pix_m
					cliff_a = smoothstep(0.10, 0.30, rise) * (1.0 - smoothstep(1.0, 2.4, lk)) * smoothstep(20.0, 80.0, v) * 0.6
					sand_a *= 1.0 - cliff_a
			if v < 140.0 and absf(dx) < 25.0 and absf(dy) < 25.0:
				if sand_a > 0.02:
					var o2 := i * 4   # sea, plain and low flat ground: the ground shows, but the beach
					data[o2] = int(COL_BEACH.r * 255.0)
					data[o2 + 1] = int(COL_BEACH.g * 255.0)
					data[o2 + 2] = int(COL_BEACH.b * 255.0)
					data[o2 + 3] = clampi(int(sand_a * 255.0), 0, 255)
				continue
			var gx := dx * inv2
			var gy := dy * inv2
			var lit := (-gx * sx - gy * sy + sz) / sqrt(gx * gx + gy * gy + 1.0)
			var sh := clampf((lit - sz) * SHADE_GAIN, -1.0, 1.0)
			var ash := absf(sh)
			sh = signf(sh) * 0.5 * (sqrt(ash) + ash)   # gentle slopes show too
			var k := clampi(int(v / LUT_STEP), 0, nl)
			var hy_r := lr[k]
			var hy_g := lg[k]
			var hy_b := lb[k]
			var hy_a := la[k]
			# Shade layer: light faces warm, shadow faces cool; strength by slope.
			var sa := 0.0
			var shr := 0.0
			var shg := 0.0
			var shb := 0.0
			if sh > 0.0:
				sa = minf(sh * 0.5, 0.4)
				shr = lit_c.r
				shg = lit_c.g
				shb = lit_c.b
			else:
				sa = minf(-sh * 0.7, 0.55)
				shr = sh_c.r
				shg = sh_c.g
				shb = sh_c.b
			# Crest: the highest of a line of 5 samples across (either axis or
			# diagonal) that also stands well above the ground 4 samples (11 km)
			# either side: the main crests, not every spur.
			var cr_a := 0.0
			if v > 800.0 and x > m4 and y > m4 and x < w - m4 - 1 and y < h - m4 - 1:
				var s := 0.0
				if v >= l and v >= r and v >= e[i - m2] and v >= e[i + m2]:
					s = maxf(s, v - 0.5 * (e[i - m4] + e[i + m4]))
				if v >= u and v >= d and v >= e[i - m2 * w] and v >= e[i + m2 * w]:
					s = maxf(s, v - 0.5 * (e[i - m4 * w] + e[i + m4 * w]))
				if v >= e[i - w - 1] and v >= e[i + w + 1] and v >= e[i - m2 * w - m2] and v >= e[i + m2 * w + m2]:
					s = maxf(s, v - 0.5 * (e[i - m4 * w - m4] + e[i + m4 * w + m4]))
				if v >= e[i - w + 1] and v >= e[i + w - 1] and v >= e[i - m2 * w + m2] and v >= e[i + m2 * w - m2]:
					s = maxf(s, v - 0.5 * (e[i - m4 * w + m4] + e[i + m4 * w - m4]))
				if s > 250.0:
					cr_a = smoothstep(250.0, 650.0, s) * 0.5
			# over(shade, tint), then the crest line over that.
			var a := sa + hy_a * (1.0 - sa)
			var cr_ := 0.0
			var cg_ := 0.0
			var cb_ := 0.0
			if a > 0.0001:
				cr_ = (shr * sa + hy_r * hy_a * (1.0 - sa)) / a
				cg_ = (shg * sa + hy_g * hy_a * (1.0 - sa)) / a
				cb_ = (shb * sa + hy_b * hy_a * (1.0 - sa)) / a
			if cr_a > 0.0:
				var a2 := cr_a + a * (1.0 - cr_a)
				cr_ = (CREST_COL.r * cr_a + cr_ * a * (1.0 - cr_a)) / a2
				cg_ = (CREST_COL.g * cr_a + cg_ * a * (1.0 - cr_a)) / a2
				cb_ = (CREST_COL.b * cr_a + cb_ * a * (1.0 - cr_a)) / a2
				a = a2
			if sand_a > 0.02:
				# The beach under what is there.
				var a3 := a + sand_a * (1.0 - a)
				cr_ = (cr_ * a + COL_BEACH.r * sand_a * (1.0 - a)) / a3
				cg_ = (cg_ * a + COL_BEACH.g * sand_a * (1.0 - a)) / a3
				cb_ = (cb_ * a + COL_BEACH.b * sand_a * (1.0 - a)) / a3
				a = a3
			if cliff_a > 0.02:
				var a4 := cliff_a + a * (1.0 - cliff_a)
				cr_ = (COL_CLIFF.r * cliff_a + cr_ * a * (1.0 - cliff_a)) / a4
				cg_ = (COL_CLIFF.g * cliff_a + cg_ * a * (1.0 - cliff_a)) / a4
				cb_ = (COL_CLIFF.b * cliff_a + cb_ * a * (1.0 - cliff_a)) / a4
				a = a4
			if a < 0.01:
				continue
			var o := i * 4
			data[o] = clampi(int(cr_ * 255.0), 0, 255)
			data[o + 1] = clampi(int(cg_ * 255.0), 0, 255)
			data[o + 2] = clampi(int(cb_ * 255.0), 0, 255)
			data[o + 3] = clampi(int(a * 255.0), 0, 255)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)


static func _in_land(p: Vector2) -> bool:
	for k in _land_polys.size():
		if (_land_boxes[k] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, _land_polys[k]):
			return true
	return false


static func _bake_glyphs() -> void:
	_v = PackedVector2Array()
	_c = PackedColorArray()
	_i = PackedInt32Array()
	tree_count = 0
	speck_count = 0
	var w := CGrid.width()
	var h := CGrid.height()
	var px := float(CGrid.cell_px())
	# Cells to keep clear: roads, rivers, cities and their neighbours.
	var clear := PackedByteArray()
	clear.resize(w * h)
	for c in w * h:
		if CGrid.is_road(c):
			clear[c] = 1
	for ri in Geo.RIVERS.size():
		for c in Geo.line_cells(Geo.river_line(ri), px, w, h):
			clear[c] = 1
	for r in CData.region_count():
		for c0 in [CGrid.site(r), CGrid.port(r), CGrid.camp(r)]:
			if c0 < 0:
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var xx: int = CGrid.cx(c0) + dx
					var yy: int = CGrid.cy(c0) + dy
					if xx >= 0 and yy >= 0 and xx < w and yy < h:
						clear[yy * w + xx] = 1
	var trees_at: Array = []   # [x, y, kind, shade, radius, rot] collected, drawn by y
	var specks: Array = []
	for c in w * h:
		var r := _near[c]
		if r < 0:
			continue
		var x := CGrid.cx(c)
		var y := CGrid.cy(c)
		var ox := x * px
		var oy := y * px
		var pi := int(CData.REGIONS[r]["ground"])
		var ov := CGrid.terrain_override(c)
		var coastal := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var xx := x + dx
				var yy := y + dy
				if xx < 0 or yy < 0 or xx >= w or yy >= h or _near[yy * w + xx] < 0:
					coastal = true
		if ov == CData.RIDGE:
			continue   # crests: the relief texture, no trees
		if clear[c] == 1:
			continue
		# Trees by the real terrain: dense on valley floors and lowlands near
		# rivers, moderate on hill flanks up to the tree line, sparse on dry
		# plains far from water, none on ridges and summits. Clustered by a
		# hash of the fine cell.
		var cls := GeoFields.cell_class(c)
		if cls == GeoFields.CLASS_RIDGE:
			continue
		var rd := GeoFields.river_dist(c)
		var wet := clampf(1.0 - (rd - 1.0) / 5.0, 0.0, 1.0)     # 1 within a cell of a river
		var dens := float(CData.REGIONS[r]["forest"]) / 100.0
		if CGrid.region(c) < 0:
			dens *= 0.4
		var low := cls == GeoFields.CLASS_VALLEY or cls == GeoFields.CLASS_PLAIN
		var tf := (0.45 + 1.15 * wet) if low else (0.8 + 0.4 * wet)
		if cls == GeoFields.CLASS_PLAIN and wet < 0.2:
			tf *= 0.6          # dry plain far from water
		var g := _h(x / 3, y / 3, 31) * 0.7 + _h(x / 2, y / 2, 32) * 0.3
		var f := 0.0 if g < 0.3 else 0.6 + (g - 0.3) * 2.2
		var want := dens * TREES_PER_CELL * f * tf
		var nt := int(want)
		if _h(x, y, 33) < want - nt:
			nt += 1
		for q in nt:
			var tx := ox + px * (0.12 + 0.76 * _h(x * 8 + q, y, 34))
			var ty := oy + px * (0.12 + 0.76 * _h(x, y * 8 + q, 35))
			var kd := _tree_kind(pi, _h(x * 8 + q, y * 8 + q, 36))
			var rad := (2.8 + 1.7 * _h(x + q, y, 37)) * (0.75 if kd == 2 else (0.6 if kd == 3 else 1.0))
			var fx := int(tx / FPX)
			var fy := int(ty / FPX)
			var em := _elev_at(tx, ty)
			if em > TREELINE:
				continue
			# Fade out towards the tree line and on steep rock; fine-cell clumps.
			var keep := 1.0 - smoothstep(1100.0, TREELINE, em)
			keep *= 1.0 - smoothstep(45.0, 90.0, GeoFields.slope_pct(Vector2(tx, ty)))
			keep *= 0.35 + 0.65 * _h(fx / 2, fy / 2, 51)
			if _h(x * 8 + q, y * 8 + q, 52) > keep:
				continue
			if coastal:
				var p := Vector2(tx, ty)
				if not (_in_land(p + Vector2(rad, rad)) and _in_land(p - Vector2(rad, rad))):
					continue
			trees_at.append([tx, ty, kd, int(_h(x + q, y + q, 38) * 3.0), rad, _h(x, y + q, 39) * TAU, pi])
		# Speckles: rock on steep and rocky ground, scrub and small rocks on
		# dry ground; the plains stay quiet.
		var ns := 0
		var rocky := pi == MapGen.PAL_ROCKY
		var sl := GeoFields.slope_pct(Vector2(ox + px * 0.5, oy + px * 0.5))
		var steep := cls == GeoFields.CLASS_HILL or sl > 25.0
		if steep or (rocky and cls != GeoFields.CLASS_PLAIN):
			ns = 1 + int(_h(x, y, 41) * 2.0 * clampf(sl / 30.0, 0.4, 1.5))
		elif cls != GeoFields.CLASS_VALLEY and (pi == MapGen.PAL_ARID or pi == MapGen.PAL_DRY):
			var pr := 0.7 if pi == MapGen.PAL_ARID else 0.4
			if cls == GeoFields.CLASS_PLAIN:
				pr *= 0.5
			ns = 1 if _h(x, y, 42) < pr else 0
		for q in ns:
			var sx := ox + px * (0.1 + 0.8 * _h(x * 8 + q, y, 43))
			var sy := oy + px * (0.1 + 0.8 * _h(x, y * 8 + q, 44))
			if _elev_at(sx, sy) > SCRUB_LINE:
				continue
			var rock := rocky or steep or _h(x + q, y, 45) < 0.45
			if coastal and not _in_land(Vector2(sx, sy)):
				continue
			specks.append([sx, sy, rock, 1.1 + 1.1 * _h(x + q, y, 46)])
	# Specks first (under), then trees by y.
	var ns2 := 0
	for s in specks:
		if ns2 >= MAX_SPECKS:
			break
		ns2 += 1
		_speck(Vector2(s[0], s[1]), bool(s[2]), float(s[3]))
	speck_count = ns2
	trees_at.sort_custom(func(a, b): return a[1] < b[1])
	for t in trees_at:
		if tree_count >= MAX_TREES:
			break
		_tree(Vector2(t[0], t[1]), int(t[2]), int(t[3]), float(t[4]), float(t[5]), int(t[6]))
		tree_count += 1
	_bake_peaks()
	mesh = ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_COLOR] = _c
	arr[Mesh.ARRAY_INDEX] = _i
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_v = PackedVector2Array()
	_c = PackedColorArray()
	_i = PackedInt32Array()


## Summit marks: only at strict local maxima of the fine field above
## PEAK_MIN (the highest within PEAK_R samples), a small sharp peak whose
## lit and shaded faces and snow cap come from the field's own gradient.
const PEAK_MIN := 2000.0
const PEAK_R := 9
const FPX := 2.5
static var peak_count := 0

static func _bake_peaks() -> void:
	peak_count = 0
	var w := CGrid.width() * RS
	var h := CGrid.height() * RS
	var pk: Array = []
	for y in range(PEAK_R, h - PEAK_R):
		for x in range(PEAK_R, w - PEAK_R):
			var v := _elev[y * w + x]
			if v < PEAK_MIN:
				continue
			var ok := true
			for dy in range(-PEAK_R, PEAK_R + 1):
				for dx in range(-PEAK_R, PEAK_R + 1):
					if (dx != 0 or dy != 0) and dx * dx + dy * dy <= PEAK_R * PEAK_R:
						var o := _elev[(y + dy) * w + x + dx]
						if o > v or (o == v and (dy < 0 or (dy == 0 and dx < 0))):
							ok = false
							break
				if not ok:
					break
			if ok:
				pk.append([x, y, v])
	pk.sort_custom(func(a, b): return a[1] < b[1])
	for p in pk:
		var x: int = p[0]
		var y: int = p[1]
		var v: float = p[2]
		var ctr := Vector2((x + 0.5) * FPX, (y + 0.5) * FPX)
		var gx := _elev[y * w + x + 3] - _elev[y * w + x - 3]
		var gy := _elev[(y + 3) * w + x] - _elev[(y - 3) * w + x]
		var sk := clampf((gx + gy) / 1200.0, -0.25, 0.25)
		var hgt := 5.5 + 4.5 * clampf((v - PEAK_MIN) / 2200.0, 0.0, 1.0)
		var wd := hgt * 0.75
		var base_y := ctr.y + hgt * 0.35
		var apex := Vector2(ctr.x + sk * wd * 0.4, ctr.y - hgt * 0.65)
		var bl := Vector2(ctr.x - wd, base_y)
		var br := Vector2(ctr.x + wd, base_y)
		var bm := Vector2(ctr.x + sk * wd * 0.2 + wd * 0.1, base_y + hgt * 0.05)
		_tri(bl + Vector2(1.0, 0.8), apex + Vector2(1.0, 0.8), br + Vector2(1.0, 0.8), Color(0.1, 0.08, 0.05, 0.3))
		_tri(bl, apex, bm, Color(0.74, 0.70, 0.64))
		_tri(bm, apex, br, Color(0.32, 0.28, 0.26))
		if v > 2600.0:
			var t := clampf((v - 2600.0) / 1600.0, 0.0, 1.0) * 0.25 + 0.35
			var a1 := apex.lerp(bl, t)
			var a2 := apex.lerp(bm, t)
			var a3 := apex.lerp(br, t)
			_tri(a1, apex, a2, Color(0.97, 0.97, 0.98))
			_tri(a2, apex, a3, Color(0.78, 0.80, 0.88))
		peak_count += 1


## tree_layer.gd's kinds per palette: 0 broadleaf, 1 pine, 2 scrub / olive,
## 3 cypress.
static func _tree_kind(pi: int, u: float) -> int:
	match pi:
		MapGen.PAL_ARID:
			return 2 if u < 0.75 else (3 if u < 0.85 else 0)
		MapGen.PAL_DRY:
			return 2 if u < 0.5 else (0 if u < 0.8 else 3)
		MapGen.PAL_ROCKY:
			return 1 if u < 0.65 else 0
		MapGen.PAL_GREEN:
			return 0 if u < 0.7 else 1
	return 0


static func tree_color(pi: int, shade: int) -> Color:
	var cols: Array = GroundPalette.get_palette(pi)["trees"]
	return (cols[shade % cols.size()] as Color).lightened(0.06)


## A tree as the battle map draws it, small: shadow down-right, canopy,
## highlight up-left.
static func _init_rings() -> void:
	if not _rings.is_empty():
		return
	for q in 3:
		_rings.append(_ring(8, 0.12, q * 2.1))
	for q in 3:
		_rings.append(_star(5, q * 0.7))
	for q in 3:
		_rings.append(_ring(6, 0.22, q * 2.1))
	_rings.append(_ring(6, 0.05, 0.0))
	_rings.append(_ring(5, 0.0, 0.0))


static func _tree(p: Vector2, kind: int, shade: int, rad: float, rot: float, pi: int) -> void:
	_init_rings()
	var col := tree_color(pi, shade)
	var v := int(rot * 10.0) % 3
	var ring: PackedVector2Array
	var sx := rad
	var sy := rad
	match kind:
		1:
			ring = _rings[3 + v]
		2:
			ring = _rings[6 + v]
		3:
			ring = _rings[9]
			sx = rad * 0.85
		_:
			ring = _rings[v]
	_fan(p + Vector2(rad * 0.3, rad * 0.35), ring, sx, sy, Color(0.05, 0.08, 0.03, 0.34))
	_fan(p, ring, sx, sy, col)
	if kind != 1:
		_fan(p + Vector2(-rad * 0.3, -rad * 0.3), _rings[10], rad * 0.42, rad * 0.42, col.lightened(0.28))
	else:
		_fan(p, _rings[10], rad * 0.3, rad * 0.3, col.lightened(0.2))


static func _speck(p: Vector2, rock: bool, r: float) -> void:
	if rock:
		_init_rings()
		_fan(p + Vector2(0.9, 0.9), _rings[10], r, r * 0.8, COL_ROCK_SHADE)
		_fan(p, _rings[10], r, r * 0.8, COL_ROCK if int(p.x) % 2 == 0 else COL_ROCK.lightened(0.12))
	else:
		_fan(p, _rings[9], r * 1.2, r * 0.9, COL_SCRUB)


# Key samples.

## Sample painters for the key (a canvas item and its size).
static var _peak_sample: ImageTexture = null

static func draw_sample_peaks(ci: CanvasItem, sz: Vector2) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.45, 0.58, 0.34))
	if _peak_sample == null:
		var w := 66
		var h := 30
		var e := PackedFloat32Array()
		e.resize(w * h)
		var kern := _kernel(9)
		for st in [[16, 18, 2600.0], [30, 16, 1900.0], [46, 19, 2300.0], [56, 17, 1200.0]]:
			_stamp(e, w, h, int(st[0]), int(st[1]), float(st[2]), kern, 9)
		_peak_sample = ImageTexture.create_from_image(relief_image(e, w, h, GeoFields.sample_m()))
	ci.draw_texture_rect(_peak_sample, Rect2(Vector2.ZERO, sz), false)


static func draw_sample_trees(ci: CanvasItem, sz: Vector2) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.45, 0.58, 0.34))
	_sample(ci, sz, func():
		var k := 0
		for q in [Vector2(0.2, 0.4), Vector2(0.4, 0.62), Vector2(0.55, 0.35), Vector2(0.75, 0.6), Vector2(0.88, 0.35)]:
			_tree(Vector2(sz.x * q.x, sz.y * q.y), [0, 1, 0, 1, 2][k], k, 3.8, float(k), MapGen.PAL_GREEN)
			k += 1)


static func draw_sample_desert(ci: CanvasItem, sz: Vector2) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.78, 0.68, 0.46))
	_sample(ci, sz, func():
		_speck(Vector2(sz.x * 0.2, sz.y * 0.4), true, 1.9)
		_speck(Vector2(sz.x * 0.45, sz.y * 0.65), false, 1.7)
		_speck(Vector2(sz.x * 0.65, sz.y * 0.35), true, 1.5)
		_speck(Vector2(sz.x * 0.85, sz.y * 0.7), false, 1.9)
		_tree(Vector2(sz.x * 0.5, sz.y * 0.3), 2, 0, 3.0, 0.5, MapGen.PAL_ARID))


static func _sample(ci: CanvasItem, _sz: Vector2, build: Callable) -> void:
	_v = PackedVector2Array()
	_c = PackedColorArray()
	_i = PackedInt32Array()
	build.call()
	var m := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_COLOR] = _c
	arr[Mesh.ARRAY_INDEX] = _i
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_v = PackedVector2Array()
	_c = PackedColorArray()
	_i = PackedInt32Array()
	ci.draw_mesh(m, null)
