extends RefCounted
## Campaign map landscape (view only, 2026-10-10): baked ONCE from the grid
## and the regions' data, drawn by map_view.gd's Terrain view.
##  - ground texture (one pixel per grid cell, drawn bilinear over the land):
##    each region's ground palette (game/ground_palette.gd, lifted like the
##    Political fill), the arid south sandier with latitude, hill and ridge
##    cells towards the palette's high ground, valley regions and cells
##    between hills a lower, greener tone; blurred over the land only so
##    region borders blend into one landscape;
##  - one mesh of glyphs (vertex colours): ridge peaks (two-tone, lit from the
##    north-west), hill domes, trees in the battle map's kinds (tree_layer.gd:
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
const TREES_PER_CELL := 5.0    # at 100 % forest, before clustering
const MAX_TREES := 4500
const MAX_SPECKS := 3500

const COL_ROCK := Color(0.66, 0.63, 0.57)
const COL_ROCK_SHADE := Color(0.18, 0.15, 0.10, 0.45)
const COL_SCRUB := Color(0.40, 0.42, 0.22, 0.85)
const COL_BANK := Color(0.93, 0.95, 0.80, 0.55)
const COL_VALLEY_STRIP := Color(0.32, 0.55, 0.26, 0.26)

static var ground_tex: ImageTexture = null
static var mesh: ArrayMesh = null
static var bake_ms := -1.0
static var tree_count := 0
static var peak_count := 0   # crest stamps
static var dome_count := 0   # hill domes
static var relief_tex: ImageTexture = null
static var _elev := PackedFloat32Array()
const RS := 4                 # relief field pixels per grid cell
const CREST_R := 7            # crest kernel radius, field px
const DOME_R := 9
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
	# Cell-sized blotches.
	var n := _h(CGrid.cx(c), CGrid.cy(c), 1) - 0.5
	return base.lightened(n * 0.07) if n > 0.0 else base.darkened(-n * 0.07)


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


## Raise the field to h * kernel under (cx, cy) (max: crests stay sharp).
static func _stamp(e: PackedFloat32Array, w: int, h: int, cx: int, cy: int, hgt: float, kern: PackedFloat32Array, r: int, touch: PackedByteArray = PackedByteArray()) -> void:
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
			if not touch.is_empty():
				touch[i] = 1


static func _vn(fx: float, fy: float, sd: int) -> float:
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx := fx - x0
	var ty := fy - y0
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	return lerpf(lerpf(_h(x0, y0, sd), _h(x0 + 1, y0, sd), tx), lerpf(_h(x0, y0 + 1, sd), _h(x0 + 1, y0 + 1, sd), tx), ty)


## The elevation field (RS x the grid): crest lines through ridge cells with
## noisy summits, spurs, hill domes at half the height; then the baked relief.
static func _bake_relief() -> void:
	var w := CGrid.width() * RS
	var h := CGrid.height() * RS
	var gw := CGrid.width()
	var gh := CGrid.height()
	_elev = PackedFloat32Array()
	_elev.resize(w * h)
	var touch := PackedByteArray()
	touch.resize(w * h)
	var kc := _kernel(CREST_R)
	var kd := PackedFloat32Array()
	for dy in range(-DOME_R, DOME_R + 1):
		for dx in range(-DOME_R, DOME_R + 1):
			var d := sqrt(float(dx * dx + dy * dy)) / DOME_R
			kd.append(0.5 * (1.0 + cos(PI * d)) if d < 1.0 else 0.0)
	var stamps := 0
	var domes := 0
	for c in gw * gh:
		var ov := CGrid.terrain_override(c)
		if ov < 0:
			continue
		var x := CGrid.cx(c)
		var y := CGrid.cy(c)
		var px := (x + 0.5) * RS
		var py := (y + 0.5) * RS
		if ov != CData.RIDGE:
			_stamp(_elev, w, h, int(px + (_h(x, y, 51) - 0.5) * 2.0), int(py + (_h(x, y, 52) - 0.5) * 2.0),
				0.30 + 0.08 * _h(x, y, 53), kd, DOME_R, touch)
			domes += 1
			continue
		# Crest: the cell centre and the midpoints towards ridge neighbours
		# E, SE, S, SW (each pair once), each a summit of hashed height.
		var pts: Array = [Vector2(px, py)]
		for d in [[1, 0], [1, 1], [0, 1], [-1, 1]]:
			var nx: int = x + d[0]
			var ny: int = y + d[1]
			if nx >= 0 and ny >= 0 and nx < gw and ny < gh and CGrid.terrain_override(ny * gw + nx) == CData.RIDGE:
				var q := Vector2((nx + 0.5) * RS, (ny + 0.5) * RS)
				pts.append((Vector2(px, py) + q) * 0.5)
				pts.append(Vector2(px, py).lerp(q, 0.25))
				pts.append(Vector2(px, py).lerp(q, 0.75))
		for p in pts:
			var jx := (_h(int(p.x * 3), int(p.y * 3), 54) - 0.5) * 1.6
			var jy := (_h(int(p.x * 3), int(p.y * 3), 55) - 0.5) * 1.6
			var n := _vn(p.x / 3.0, p.y / 3.0, 56) * 0.65 + _vn(p.x / 1.3, p.y / 1.3, 57) * 0.35
			var hg := 0.40 + 0.60 * pow(n, 2.0) * 1.5
			hg = minf(hg, 1.0)
			_stamp(_elev, w, h, int(p.x + jx), int(p.y + jy), hg, kc, CREST_R, touch)
			stamps += 1
			if _h(int(p.x * 5), int(p.y * 5), 58) < 0.3:
				# A spur off the crest.
				var a := _h(int(p.x * 5), int(p.y * 5), 59) * TAU
				_stamp(_elev, w, h, int(p.x + cos(a) * 4.0), int(p.y + sin(a) * 4.0), hg * 0.6, kc, CREST_R, touch)
	peak_count = stamps
	dome_count = domes
	relief_tex = ImageTexture.create_from_image(relief_image(_elev, w, h, touch))


const ROCK := Color(0.40, 0.35, 0.30)
const SNOW := Color(0.95, 0.96, 0.97)
const SHADOW := Color(0.14, 0.13, 0.20)

## Hillshade + hypsometric image of an elevation field (touched pixels only):
## light from the NW, bright NW faces, deep SE shadow, a bright crest line,
## snow-pale summits, rock flanks, transparent where low (the ground shows).
static func relief_image(e: PackedFloat32Array, w: int, h: int, touch: PackedByteArray) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	# A light 3x3 blur (touched pixels) takes the pixel stair-steps out.
	var raw := e
	e = raw.duplicate()
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var j := y * w + x
			if touch[j] != 0:
				e[j] = (raw[j] * 4.0 + raw[j - 1] + raw[j + 1] + raw[j - w] + raw[j + w]
					+ (raw[j - w - 1] + raw[j - w + 1] + raw[j + w - 1] + raw[j + w + 1]) * 0.5) / 8.0
	for y in h:
		var row := y * w
		for x in w:
			var i := row + x
			if touch[i] == 0:
				continue
			var v := e[i]
			if v <= 0.004:
				continue
			var l := e[i - 1] if x > 0 else v
			var r := e[i + 1] if x < w - 1 else v
			var u := e[i - w] if y > 0 else v
			var d := e[i + w] if y < h - 1 else v
			# Rough rock: a little noise on the height used for shading.
			var gx := (r - l) * 0.5
			var gy := (d - u) * 0.5
			var nrm := Vector3(-gx * 5.5, -gy * 5.5, 1.0).normalized()
			var lit := nrm.dot(Vector3(-0.6, -0.6, 0.52).normalized())
			var sh := clampf((lit - 0.52 * 0.0 - Vector3(0, 0, 1).dot(Vector3(-0.6, -0.6, 0.52).normalized())) * 2.6, -1.0, 1.0)
			var snow := smoothstep(0.78, 0.95, v)
			var col := ROCK.lerp(SNOW, snow)
			if sh > 0.0:
				col = col.lerp(Color(0.95, 0.88, 0.72), sh * 0.32)
			else:
				col = col.lerp(SHADOW, -sh * 0.9)
			var crest := clampf(-(l + r + u + d - 4.0 * v) * 30.0, 0.0, 1.0) * smoothstep(0.2, 0.4, v)
			col = col.lerp(Color(1.0, 0.98, 0.92), crest * 0.6)
			var a := clampf((v - 0.02) * 3.0, 0.0, 1.0) * (0.2 + 0.78 * smoothstep(0.3, 0.55, v))
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return img


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
		# Trees: forest % of the region, clustered by a hash of the 3x3 block,
		# fewer on hills.
		var dens := float(CData.REGIONS[r]["forest"]) / 100.0
		if ov >= 0:
			dens *= 0.6
		if CGrid.region(c) < 0:
			dens *= 0.4
		var g := _h(x / 3, y / 3, 31) * 0.7 + _h(x / 2, y / 2, 32) * 0.3
		var f := 0.0 if g < 0.3 else 0.6 + (g - 0.3) * 2.2
		var want := dens * TREES_PER_CELL * f
		var nt := int(want)
		if _h(x, y, 33) < want - nt:
			nt += 1
		for q in nt:
			var tx := ox + px * (0.12 + 0.76 * _h(x * 8 + q, y, 34))
			var ty := oy + px * (0.12 + 0.76 * _h(x, y * 8 + q, 35))
			var kd := _tree_kind(pi, _h(x * 8 + q, y * 8 + q, 36))
			var rad := (2.8 + 1.7 * _h(x + q, y, 37)) * (0.75 if kd == 2 else (0.6 if kd == 3 else 1.0))
			if _elev_at(tx, ty) > 0.18:
				continue
			if coastal:
				var p := Vector2(tx, ty)
				if not (_in_land(p + Vector2(rad, rad)) and _in_land(p - Vector2(rad, rad))):
					continue
			trees_at.append([tx, ty, kd, int(_h(x + q, y + q, 38) * 3.0), rad, _h(x, y + q, 39) * TAU, pi])
		# Speckles: rocks on rocky ground and hills, scrub and small rocks on
		# dry and arid ground.
		var ns := 0
		var rocky := pi == MapGen.PAL_ROCKY
		if rocky or ov >= 0:
			ns = 1 + int(_h(x, y, 41) * 2.0)
		elif pi == MapGen.PAL_ARID or pi == MapGen.PAL_DRY:
			ns = 1 if _h(x, y, 42) < (0.7 if pi == MapGen.PAL_ARID else 0.4) else 0
		for q in ns:
			var sx := ox + px * (0.1 + 0.8 * _h(x * 8 + q, y, 43))
			var sy := oy + px * (0.1 + 0.8 * _h(x, y * 8 + q, 44))
			if _elev_at(sx, sy) > 0.5:
				continue
			var rock := rocky or ov >= 0 or _h(x + q, y, 45) < 0.45
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
		for st in [[16, 18, 1.0], [30, 16, 0.8], [46, 19, 0.95], [56, 17, 0.55]]:
			_stamp(e, w, h, int(st[0]), int(st[1]), float(st[2]), kern, 9)
		var touch := PackedByteArray()
		touch.resize(w * h)
		touch.fill(1)
		_peak_sample = ImageTexture.create_from_image(relief_image(e, w, h, touch))
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
