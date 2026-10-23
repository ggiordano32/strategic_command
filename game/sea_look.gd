extends RefCounted
## The sea battle's look (view only; docs/DESIGN.md "Sea battles", the look paragraph; 2026-10-22).
## game/sea_battle.gd draws the water, the land and the wakes through this: nothing here is read
## by the sim and nothing writes it, so a co-op battle looks the same on every peer without being
## synchronised (the fields below come from the sim's land grid and the battle seed).
##
## Baked once per battle from the sim's 20 m land grid (`g`: 0 sea, 1 shoal, 2 land), at 10 m texels:
##  - `fld` (RGBA8): R the signed distance to the sim's land edge (m, sea positive, -80 .. +240),
##    G the sea depth (sqrt of 0 .. 1500 m), B how steep the coast is, A the woods;
##  - `aux` (RG8): the unit direction seaward (the distance field's gradient);
##  - `cells` (L8, nearest): the sim's land cells themselves.
## Depth: the campaign's bathymetry (GeoFields.depth_at over the battle's cell, 3 x 3 samples,
## bilinear) capped by a shelf from the distance to land (steeper where the neighbouring land is
## rugged: CData relief of the land cells the coast faces), a shoal 1.5 m deep; a battle without a
## campaign cell (custom battles) has an open-water depth and the same shelf.
## The drawn shore is the sim's cell edge refined: sea_shore.gdshaderinc moves it 5 to 14 m INTO
## the sim's land by two noise scales (the land maps' ragged coast), so the water is drawn over
## sim land, never the land over sim water: no ship can lie over drawn land. `shore_ok()` checks it.
## Props (trees, a harbour fort) are placed on the baked woods and drawn once with the battle kit.

const SeaSim := preload("res://sim/sea_sim.gd")
const Quality := preload("res://game/quality.gd")
const BattleLook := preload("res://game/battle_look.gd")
const GroundPalette := preload("res://game/ground_palette.gd")
const Atlas := preload("res://game/battlekit_atlas.gd")
const Atlas2 := preload("res://game/battlekit_atlas2.gd")
const CData := preload("res://campaign/cdata.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CTown := preload("res://campaign/ctown.gd")
const GeoFields := preload("res://game/campaign/geo_fields.gd")
const WATER_SHADER := preload("res://game/sea_water.gdshader")
const LAND_SHADER := preload("res://game/sea_land.gdshader")

const T := 10.0                  # metres a texel of the baked fields
const SDF_LO := -80.0            # R = 0
const SDF_SPAN := 320.0          # R = 255
const DEPTH_MAX := 1500.0
const SHORE_MIN := 5.0           # the drawn shore lies at least this far inside the sim's land (metres)
const SHORE_AMP := 9.0
const FORT_SCALE := 2.3          # a landmark fort's size (ships are drawn 1.5 x their length too)
const TREE_CAP := 600
const TREE_CAP_LOW := 200
const LIGHT := Vector2(-0.62, -0.78)

static var _atlas1: Texture2D          # trees: the pre-lit atlas (4 px / m, plenty at 10 m a tree)
static var _atlas2: Texture2D          # forts: the albedo atlas (8 px / m), the pre-lit one on Graphics Low
static var _atlas2_low := false
static var _tiles := {}

var gw := 0
var gh := 0
var tw := 0
var th := 0
var field := Vector2.ZERO
var low := false
var kind := 0                    # the scenario's land kind: 0 open, 1 island, 2 coast
var dirs := 0
var mseed := 1
var palette := 3
var tropic := false
var has_cell := false
var sdf := PackedFloat32Array()        # metres per texel (10 m), + sea
var cst := PackedFloat32Array()        # per cell (20 m): steepness 0 .. 1
var cdp := PackedFloat32Array()        # ... the campaign's depth (m)
var cwn := PackedFloat32Array()        # ... the woods noise 0 .. 1
var cpn := PackedFloat32Array()        # ... the shore palms' noise
var csh := PackedFloat32Array()        # ... shoal or land 0 / 1
var ccs := PackedFloat32Array()        # ... the signed distance at the cell centre
var cgx := PackedFloat32Array()        # ... the seaward unit vector
var cgy := PackedFloat32Array()
var cland := PackedByteArray()         # ... 1: land in the sim
var gxt := PackedFloat32Array()        # per texel: the seaward unit vector, smooth
var gyt := PackedFloat32Array()
var sht := PackedFloat32Array()        # per texel: shoal or land, smooth
var fld_tex: ImageTexture
var fld2_tex: ImageTexture
var cell_tex: ImageTexture
var water_mat: ShaderMaterial
var land_mat: ShaderMaterial
var foam_tex: ImageTexture
var soft_tex: ImageTexture
var trees: Array = []                  # [x, y, piece index, scale, tint]
var forts: Array = []                  # [x, y, piece index (Atlas2), yaw, scale]
var build_ms := 0.0
var wind_base := 0.0                   # the wind's angle when the battle began (the pattern's reference)
var _wind_vis := 0.0
var _seed := 1
var _clock := 0.0
var _cell := Vector2i(-1, -1)
var _region := -1


## Bakes the fields, builds the materials and places the props. `scn` is the scenario (its "land"),
## `cell` the campaign cell of the battle ((-1, -1): none), `region` the nearest region (-1: none).
func setup(sim, seed_v: int, scn: Dictionary, cell: Vector2i, region: int) -> void:
	var t0 := Time.get_ticks_usec()
	low = Quality.is_low()
	_seed = seed_v & 0xFFFF
	gw = sim.g_w
	gh = sim.g_h
	tw = gw * 2
	th = gh * 2
	field = Vector2(sim.field_w, sim.field_h)
	_cell = cell
	_region = region
	has_cell = cell.x >= 0 and CData.REGIONS.size() > 0
	var land: Dictionary = scn.get("land", {})
	kind = int(land.get("kind", 0))
	dirs = int(land.get("dirs", 0))
	mseed = int(land.get("mseed", 1))
	tropic = int(CData.ship_const("TROPIC", 1 if CData.pack == "west" else 0)) != 0   # (R2: the pack's SHIPS says)
	palette = 3 if tropic else 0
	if has_cell and region >= 0 and region < CData.REGIONS.size():
		palette = int(CData.REGIONS[region].get("ground", palette))
	var t1 := Time.get_ticks_usec()
	_bake(sim)
	var t2 := Time.get_ticks_usec()
	_materials()
	var t3 := Time.get_ticks_usec()
	_props()
	var t4 := Time.get_ticks_usec()
	_textures()
	if "--look-prof" in OS.get_cmdline_user_args():
		print("sea look: bake %.0f ms, materials %.0f, props %.0f, textures %.0f" % [(t2 - t1) / 1000.0, (t3 - t2) / 1000.0, (t4 - t3) / 1000.0, (Time.get_ticks_usec() - t4) / 1000.0])
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_wind_vis = _wind_angle(sim)
	wind_base = _wind_vis


static func _wind_angle(sim) -> float:
	return (sim.w_from + 512) * TAU / 1024.0


# ----------------------------------------------------------------- baking ---

static func _hi(a: int, b: int, c: int) -> int:
	var x := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791) ^ 0x5bd1e995
	x = (x ^ (x >> 13)) * 0x5bd1e995
	return (x ^ (x >> 15)) & 0x7FFFFFFF


static func _hf(a: int, b: int, c: int) -> float:
	return float(_hi(a, b, c) % 10000) / 10000.0


## Squared distance (in cells) to the nearest seed (Felzenszwalb), rows then columns.
static func _edt(seeds: PackedByteArray, w: int, h: int) -> PackedFloat32Array:
	var inf := 1.0e9
	var out := PackedFloat32Array()
	out.resize(w * h)
	var f := PackedFloat32Array()
	f.resize(maxi(w, h))
	var tmp := PackedFloat32Array()
	tmp.resize(maxi(w, h))
	for x in w:
		for y in h:
			f[y] = 0.0 if seeds[y * w + x] != 0 else inf
		_dt1(f, h, tmp)
		for y in h:
			out[y * w + x] = tmp[y]
	for y in h:
		for x in w:
			f[x] = out[y * w + x]
		_dt1(f, w, tmp)
		for x in w:
			out[y * w + x] = tmp[x]
	return out


static func _dt1(f: PackedFloat32Array, n: int, d: PackedFloat32Array) -> void:
	var inf := 1.0e12
	var v := PackedInt32Array()
	v.resize(n)
	var z := PackedFloat32Array()
	z.resize(n + 1)
	var k := 0
	v[0] = 0
	z[0] = -inf
	z[1] = inf
	for q in range(1, n):
		var p := v[k]
		var s := ((f[q] + q * q) - (f[p] + p * p)) / float(2 * q - 2 * p)
		while s <= z[k]:
			k -= 1
			p = v[k]
			s = ((f[q] + q * q) - (f[p] + p * p)) / float(2 * q - 2 * p)
		k += 1
		v[k] = q
		z[k] = s
		z[k + 1] = inf
	k = 0
	for q in n:
		while z[k + 1] < q:
			k += 1
		var p2 := v[k]
		d[q] = (q - p2) * (q - p2) + f[p2]


func _bake(sim) -> void:
	var ncell := gw * gh
	var any := false
	cland.resize(ncell)
	var seeds_s := PackedByteArray()
	seeds_s.resize(ncell)
	for c in ncell:
		var land := 1 if sim.g[c] == 2 else 0
		cland[c] = land
		seeds_s[c] = 1 - land
		any = any or land != 0
	# The signed distance at the cells' centres (m, to the cell edge), cubic up to 10 m texels.
	var cs := ccs
	cs.resize(ncell)
	var cm := float(SeaSim.CELL_M)
	if any:
		var dl := _edt(cland, gw, gh)
		var ds := _edt(seeds_s, gw, gh)
		for c in ncell:
			if cland[c] != 0:
				cs[c] = -(sqrt(ds[c]) - 0.5) * cm
			else:
				cs[c] = (sqrt(dl[c]) - 0.5) * cm
	else:
		cs.fill(240.0)
	# The seaward direction (the distance's gradient) per cell.
	cgx.resize(ncell)
	cgy.resize(ncell)
	for cy in gh:
		for cx in gw:
			var c := cy * gw + cx
			var ax := cs[cy * gw + mini(cx + 1, gw - 1)] - cs[cy * gw + maxi(cx - 1, 0)]
			var ay := cs[mini(cy + 1, gh - 1) * gw + cx] - cs[maxi(cy - 1, 0) * gw + cx]
			var l := sqrt(ax * ax + ay * ay)
			if l > 2.0:
				cgx[c] = ax / l
				cgy[c] = ay / l
			else:
				cgx[c] = 0.0
				cgy[c] = 0.0
	_cell_fields(sim)
	_blur_cells(csh)
	_blur_cells(csh)
	sdf = _up(cs)
	gxt = _up(cgx)
	gyt = _up(cgy)
	sht = _up(csh)


## One [1 2 1] pass each way over a per-cell field (rounds the shoals' staircase).
func _blur_cells(a: PackedFloat32Array) -> void:
	var tmp := PackedFloat32Array()
	tmp.resize(a.size())
	for y in gh:
		for x in gw:
			tmp[y * gw + x] = (a[y * gw + maxi(x - 1, 0)] + 2.0 * a[y * gw + x] + a[y * gw + mini(x + 1, gw - 1)]) * 0.25
	for y in gh:
		for x in gw:
			a[y * gw + x] = (tmp[maxi(y - 1, 0) * gw + x] + 2.0 * tmp[y * gw + x] + tmp[mini(y + 1, gh - 1) * gw + x]) * 0.25


## A per-cell field (gw x gh) as per-texel (tw x th), smooth (the engine's cubic resize, in C++).
func _up(cell: PackedFloat32Array) -> PackedFloat32Array:
	var img := Image.create_from_data(gw, gh, false, Image.FORMAT_RF, cell.to_byte_array())
	img.resize(tw, th, Image.INTERPOLATE_CUBIC)
	return img.get_data().to_float32_array()


## How steep the coast is toward each of the 8 land directions (0 .. 1): the campaign cell's land
## neighbours' relief (flat plain 0, hills 0.4, mountains 1), else a seeded value.
func _dir_steep() -> Array:
	var out := []
	var base := 0.08 + 0.5 * _hf(mseed, 3, 77)
	for i in 8:
		var s := base
		if has_cell and kind == 2:
			var a := float(i) * PI / 4.0
			var x := _cell.x + int(round(cos(a)))
			var y := _cell.y + int(round(sin(a)))
			if x >= 0 and y >= 0 and x < CGrid.width() and y < CGrid.height():
				var c := CGrid.at(x, y)
				if not CFleet.is_sea(c):
					s = clampf((float(GeoFields.cell_relief(c)) - 60.0) / 400.0, 0.0, 1.0)
		out.append(s)
	return out


## The per-cell fields: the coast's steepness (toward the land directions of the scenario), the
## campaign's bathymetry (3 x 3 samples over the cell, bilinear), the shoals, and two noises for the
## woods (the shaders and the tree placement share the formula, `wood_at`).
func _cell_fields(sim) -> void:
	var ncell := gw * gh
	cst.resize(ncell)
	cdp.resize(ncell)
	csh.resize(ncell)
	cwn.resize(ncell)
	cpn.resize(ncell)
	var ds := _dir_steep()
	var samples := PackedFloat32Array()
	samples.resize(9)
	if has_cell:
		var px := float(CGrid.cell_px())
		var cc := Vector2((_cell.x + 0.5) * px, (_cell.y + 0.5) * px)
		for j in 3:
			for i in 3:
				samples[j * 3 + i] = maxf(GeoFields.depth_at(cc + Vector2(i - 1, j - 1) * px * 0.5), 8.0)
	else:
		samples.fill(300.0)
	var ctr := field * 0.5
	var base_s := 0.0
	for i in 8:
		base_s += float(ds[i])
	base_s /= 8.0
	var ux := PackedFloat32Array()
	var uy := PackedFloat32Array()
	for i in 8:
		ux.append(cos(float(i) * PI / 4.0))
		uy.append(sin(float(i) * PI / 4.0))
	var cm := float(SeaSim.CELL_M)
	for cy in gh:
		var v := (cy + 0.5) / float(gh) * 2.0 - 0.5
		var j0 := clampi(int(floor(v)), 0, 1)
		var fv := clampf(v - j0, 0.0, 1.0)
		for cx in gw:
			var c := cy * gw + cx
			var u := (cx + 0.5) / float(gw) * 2.0 - 0.5
			var i0 := clampi(int(floor(u)), 0, 1)
			var fu := clampf(u - i0, 0.0, 1.0)
			cdp[c] = lerpf(lerpf(samples[j0 * 3 + i0], samples[j0 * 3 + i0 + 1], fu),
				lerpf(samples[(j0 + 1) * 3 + i0], samples[(j0 + 1) * 3 + i0 + 1], fu), fv)
			csh[c] = 1.0 if sim.g[c] != 0 else 0.0
			var st := base_s
			if kind == 2 and dirs != 0:
				var vx := (cx + 0.5) * cm - ctr.x
				var vy := (cy + 0.5) * cm - ctr.y
				var vl := maxf(sqrt(vx * vx + vy * vy), 0.001)
				var wsum := 0.0
				var ssum := 0.0
				for i in 8:
					if (dirs >> i) & 1 == 0:
						continue
					var w := maxf((vx * ux[i] + vy * uy[i]) / vl, 0.0)
					w = w * w + 0.02
					wsum += w
					ssum += w * float(ds[i])
				if wsum > 0.0:
					st = ssum / wsum
			cst[c] = clampf(st, 0.0, 1.0)
	var n1 := _noise_cells(70.0, 11)
	var n2 := _noise_cells(24.0, 23)
	var n3 := _noise_cells(30.0, 31)
	for c in ncell:
		cwn[c] = n1[c] * 0.62 + n2[c] * 0.38
		cpn[c] = n3[c]


## Smooth noise per cell (0 .. 1, feature size `feature_m` metres) from the engine's noise (C++).
func _noise_cells(feature_m: float, salt: int) -> PackedFloat32Array:
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_PERLIN
	nz.seed = _seed * 31 + salt
	nz.frequency = float(SeaSim.CELL_M) / feature_m
	var d := nz.get_image(gw, gh, false, false, true).get_data()
	var out := PackedFloat32Array()
	out.resize(gw * gh)
	for i in gw * gh:
		out[i] = float(d[i]) / 255.0
	return out


## The woods' density 0 .. 1 at inland distance `im` (metres from the middle of the drawn shore band),
## noise n, palm noise pn, steepness st: the formula of sea_land.gdshader.
static func wood_formula(im: float, n: float, pn: float, st: float) -> float:
	if im <= 0.0:
		return 0.0
	var w := smoothstep(0.42, 0.66, n) * smoothstep(8.0, 38.0, im)
	var strip := smoothstep(14.0, 24.0, im) * (1.0 - smoothstep(48.0, 80.0, im)) * smoothstep(0.35, 0.6, pn) * 0.55
	return maxf(w, strip) * (1.0 - 0.8 * smoothstep(0.35, 0.7, st))


## The drawn land at every texel centre lies inside the sim's land cells, with SHORE_MIN to spare
## (the drawn shore is the sim's edge moved at least that far inland): false names a bug in the
## bake (tests/sea_screen_test.gd).
func shore_ok() -> bool:
	for ty in th:
		for tx in tw:
			if sdf[ty * tw + tx] + SHORE_MIN < 0.0 and cland[(ty / 2) * gw + tx / 2] == 0:
				return false
	return true


## sdf at a world point (bilinear), metres, sea positive.
func sdf_at(p: Vector2) -> float:
	return _sample(sdf, p, tw, th, T)


func _sample(a: PackedFloat32Array, p: Vector2, w: int, h: int, step: float) -> float:
	var fx := clampf(p.x / step - 0.5, 0.0, float(w - 1))
	var fy := clampf(p.y / step - 0.5, 0.0, float(h - 1))
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var x1 := mini(x0 + 1, w - 1)
	var y1 := mini(y0 + 1, h - 1)
	var wx := fx - x0
	var wy := fy - y0
	return lerpf(lerpf(a[y0 * w + x0], a[y0 * w + x1], wx), lerpf(a[y1 * w + x0], a[y1 * w + x1], wx), wy)


## Cell-resolution fields (20 m) sampled at a world point.
func _csample(a: PackedFloat32Array, p: Vector2) -> float:
	return _sample(a, p, gw, gh, float(SeaSim.CELL_M))


## The woods' density at a world point (the shaders' formula on the same baked fields).
func wood_at(p: Vector2) -> float:
	var im := -sdf_at(p) - (SHORE_MIN + SHORE_AMP * 0.5)
	if im <= 0.0:
		return 0.0
	return wood_formula(im, _csample(cwn, p), _csample(cpn, p), _csample(cst, p))


# -------------------------------------------------------- textures, materials ---

func _textures() -> void:
	var n := tw * th
	var b := PackedByteArray()
	b.resize(n * 4)
	for k in n:
		var o := k * 4
		b[o] = clampi(int((sdf[k] - SDF_LO) * (255.0 / SDF_SPAN) + 0.5), 0, 255)
		b[o + 1] = clampi(int((gxt[k] * 0.5 + 0.5) * 255.0 + 0.5), 0, 255)
		b[o + 2] = clampi(int((gyt[k] * 0.5 + 0.5) * 255.0 + 0.5), 0, 255)
		b[o + 3] = clampi(int(sht[k] * 255.0 + 0.5), 0, 255)
	fld_tex = ImageTexture.create_from_image(Image.create_from_data(tw, th, false, Image.FORMAT_RGBA8, b))
	var nc := gw * gh
	var b2 := PackedByteArray()
	b2.resize(nc * 4)
	var cb := PackedByteArray()
	cb.resize(nc)
	for c in nc:
		var o2 := c * 4
		b2[o2] = clampi(int(sqrt(clampf(cdp[c] / DEPTH_MAX, 0.0, 1.0)) * 255.0 + 0.5), 0, 255)
		b2[o2 + 1] = clampi(int(cst[c] * 255.0 + 0.5), 0, 255)
		b2[o2 + 2] = clampi(int(cwn[c] * 255.0 + 0.5), 0, 255)
		b2[o2 + 3] = clampi(int(cpn[c] * 255.0 + 0.5), 0, 255)
		cb[c] = 255 if cland[c] != 0 else 0
	fld2_tex = ImageTexture.create_from_image(Image.create_from_data(gw, gh, false, Image.FORMAT_RGBA8, b2))
	cell_tex = ImageTexture.create_from_image(Image.create_from_data(gw, gh, false, Image.FORMAT_L8, cb))
	water_mat.set_shader_parameter("fld", fld_tex)
	water_mat.set_shader_parameter("fld2", fld2_tex)
	land_mat.set_shader_parameter("fld", fld_tex)
	land_mat.set_shader_parameter("fld2", fld2_tex)
	land_mat.set_shader_parameter("cells", cell_tex)
	foam_tex = _foam_blob()
	soft_tex = _soft_blob()


func _materials() -> void:
	var gm := Vector2(gw, gh) * float(SeaSim.CELL_M)
	water_mat = ShaderMaterial.new()
	water_mat.shader = WATER_SHADER
	land_mat = ShaderMaterial.new()
	land_mat.shader = LAND_SHADER
	for m in [water_mat, land_mat]:
		m.set_shader_parameter("grid_m", gm)
		m.set_shader_parameter("field_m", field)
		m.set_shader_parameter("shore_lo", SHORE_MIN)
		m.set_shader_parameter("shore_amp", SHORE_AMP)
		BattleLook.apply(m)
	water_mat.set_shader_parameter("hi", 0.0 if low else 1.0)
	if not tropic:
		# The Mediterranean: a deeper blue, the shallows less turquoise (R2).
		water_mat.set_shader_parameter("c_sand", Vector3(0.74, 0.80, 0.70))
		water_mat.set_shader_parameter("c_shal", Vector3(0.30, 0.62, 0.70))
		water_mat.set_shader_parameter("c_tq", Vector3(0.14, 0.46, 0.64))
		water_mat.set_shader_parameter("c_mid", Vector3(0.08, 0.32, 0.55))
		water_mat.set_shader_parameter("c_blue", Vector3(0.06, 0.25, 0.47))
		water_mat.set_shader_parameter("c_deep", Vector3(0.04, 0.18, 0.37))
	var pal := GroundPalette.get_palette(palette)
	land_mat.set_shader_parameter("low", low)
	land_mat.set_shader_parameter("base_col", _v3(pal["base"]))
	var lush: Vector3 = pal["lush"]
	var dry: Vector3 = pal["dry"]
	land_mat.set_shader_parameter("patch_a", lush)
	land_mat.set_shader_parameter("patch_b", dry)
	land_mat.set_shader_parameter("rock_col", _v3((pal["rock"] as Color).lerp(pal["base"], 0.18)))
	land_mat.set_shader_parameter("sand_col", _v3(pal["sand"]) if tropic else Vector3(0.84, 0.80, 0.68))   # (pale limestone shore, R2)
	var wc := (pal["trees"][2] as Color)
	land_mat.set_shader_parameter("wood_col", Vector3(wc.r, wc.g, wc.b) * 0.9)
	var dryg := palette == 1 or palette == 2
	land_mat.set_shader_parameter("grass_mean", Vector3(0.62, 0.565, 0.335) if dryg else Vector3(0.39, 0.49, 0.235))
	if not low:
		land_mat.set_shader_parameter("tile_grass", _tile("dry" if dryg else "grass"))
		land_mat.set_shader_parameter("tile_sand", _tile("sand"))
		land_mat.set_shader_parameter("tile_rock", _tile("rock"))


static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


static func _tile(nm: String) -> Texture2D:
	if _tiles.has(nm):
		return _tiles[nm]
	var img := (load("res://assets/battlekit/ground/%s.png" % nm) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tiles[nm] = t
	return t


## Water per frame (High): time, the wind's pattern direction (eased: it follows 35 % of the wind's
## drift from where it began, so a slow shift does not slide the whole pattern) and strength.
func tick(clock: float, sim) -> void:
	if low:
		return
	_clock = clock
	var cur := _wind_angle(sim)
	var d := angle_difference(wind_base, cur)
	_wind_vis = wind_base + d * 0.35
	water_mat.set_shader_parameter("t", clock)
	water_mat.set_shader_parameter("wdir", Vector2(cos(_wind_vis), sin(_wind_vis)))
	water_mat.set_shader_parameter("wstr", clampf(float(sim.w_str) / 100.0, 0.1, 1.0))


func wind_to(sim) -> Vector2:
	var a := _wind_angle(sim)
	return Vector2(cos(a), sin(a))


# ------------------------------------------------------------------ props ---

func _props() -> void:
	trees.clear()
	forts.clear()
	if kind == 0 and not _has_land():
		return
	_place_forts()
	var pieces: Array = []
	var names: Array = ["tree_palm_a", "tree_palm_b", "tree_palm_a", "tree_broad_a", "bush_a"] if tropic else \
		["tree_pine_a", "tree_pine_b", "tree_pine_a", "tree_broad_b", "bush_a", "bush_b"]   # (the Mediterranean: pines and scrub; no cypress or olive pieces in the kit)
	for nm in names:
		pieces.append(Atlas.NAMES.find(nm))
	var cap := TREE_CAP_LOW if low else TREE_CAP
	var step := 13.0
	var cx := int(field.x / step)
	var cy := int(field.y / step)
	for j in cy:
		for i in cx:
			if trees.size() >= cap:
				break
			var jx := _hf(i, j, 5 + _seed)
			var jy := _hf(i, j, 6 + _seed)
			var p := Vector2((i + jx) * step, (j + jy) * step)
			if ccs[int(p.y / 20.0) * gw + int(p.x / 20.0)] > 6.0 or sdf_at(p) > -(SHORE_MIN + SHORE_AMP + 4.0):
				continue
			var w := wood_at(p)
			if w < 0.08 or _hf(i, j, 7 + _seed) > w * 0.55:
				continue
			if _near_fort(p, 34.0):
				continue
			var pc: int = pieces[_hi(i, j, 8 + _seed) % pieces.size()]
			var sc := 0.85 + 0.55 * _hf(i, j, 9 + _seed)
			if Atlas.NAMES[pc] == "bush_a" or Atlas.NAMES[pc] == "bush_b":
				sc *= 1.5
			var tint := 0.88 + 0.2 * _hf(i, j, 10 + _seed)
			trees.append([p.x, p.y, pc, sc, tint])
	trees.sort_custom(func(a, b): return float(a[1]) < float(b[1]))


func _has_land() -> bool:
	for k in range(0, tw * th, 7):
		if sdf[k] < 0.0:
			return true
	return false


func _near_fort(p: Vector2, r: float) -> bool:
	for f in forts:
		if Vector2(f[0], f[1]).distance_to(p) < r * float(f[4]) / 1.6:
			return true
	return false


## A fort piece of the battle kit where the campaign cell's nearest region has one (CTown.LM,
## the harbour's landmark: Havana's Morro and Fuerza, Portobelo's two harbour forts ...) on the
## coast the battle is fought off.
func _place_forts() -> void:
	if not has_cell or kind != 2 or dirs == 0 or _region < 0 or _region >= CData.REGIONS.size():
		return
	if CFleet.coast_dist(CGrid.at(_cell.x, _cell.y)) > 1:
		return
	var key := str(CData.REGIONS[_region]["key"])
	var lms: Array = CTown.LM.get(key, [])
	var pcs: Array = []
	for lm in lms:
		if bool(lm.get("fort", false)) and Atlas2.NAMES.has("lm_" + str(lm["p"])):
			pcs.append("lm_" + str(lm["p"]))
	if pcs.is_empty():
		return
	# The coast's direction (toward the land) and along it.
	var ld := Vector2.ZERO
	for i in 8:
		if (dirs >> i) & 1 != 0:
			ld += Vector2(cos(float(i) * PI / 4.0), sin(float(i) * PI / 4.0))
	if ld.length() < 0.1:
		return
	ld = ld.normalized()
	var tg := Vector2(-ld.y, ld.x)
	var ext := absf(tg.x) * field.x + absf(tg.y) * field.y
	var offs: Array = [-0.22, 0.22] if pcs.size() > 1 else [0.16 if _hf(mseed, 1, 2) > 0.5 else -0.16]
	for q in mini(pcs.size(), 2):
		var c0 := field * 0.5 + tg * ext * float(offs[q])
		var far := (absf(ld.x) * field.x + absf(ld.y) * field.y) * 0.5
		var p := c0 - ld * far
		var hit := Vector2(-1, -1)
		var s := 0.0
		while s < far * 2.0:
			var pp := p + ld * s
			if pp.x > 20.0 and pp.y > 20.0 and pp.x < field.x - 20.0 and pp.y < field.y - 20.0 and sdf_at(pp) < -(SHORE_MIN + SHORE_AMP + 22.0):
				hit = pp
				break
			s += 6.0
		if hit.x < 0.0:
			continue
		# Face the sea along the local coast direction.
		var sea := Vector2(_csample(cgx, hit), _csample(cgy, hit))
		if sea.length() < 0.2:
			sea = -ld
		sea = sea.normalized()
		var yaw := atan2(sea.x, -sea.y)
		forts.append([hit.x, hit.y, Atlas2.NAMES.find(str(pcs[q])), yaw, FORT_SCALE])


## Draws the props once (trees' shadows, the trees, the forts) on `c` in world metres.
func draw_props(c: CanvasItem) -> void:
	if _atlas1 == null:
		_atlas1 = load("res://assets/battlekit/atlas_low.png")
	if not forts.is_empty() and (_atlas2 == null or _atlas2_low != low):
		_atlas2_low = low
		_atlas2 = load("res://assets/battlekit/atlas2_low.png" if low else "res://assets/battlekit/atlas2_albedo.png")
	var lowk: float = Atlas.LOW_PPM / Atlas.PPM
	var lowk2: float = lowk if low else 1.0
	for f in forts:
		var an: Array = Atlas2.ANCHOR[int(f[2])]
		var sw := float(an[2]) * float(f[4])
		var sh := float(an[3]) * float(f[4])
		c.draw_texture_rect(soft_tex, Rect2(f[0] - sw * 0.62 + 7.0, f[1] - sh * 0.5 + 10.0, sw * 1.25, sh * 1.2), false, Color(0, 0, 0, 0.32))
	for t in trees:
		var an: Array = Atlas.ANCHOR[int(t[2])]
		var s := float(t[3])
		var w := float(an[2]) * s
		var h := float(an[3]) * s
		c.draw_texture_rect(soft_tex, Rect2(t[0] - w * 0.4 + 2.0 * s, t[1] - h * 0.3 + 3.0 * s, w * 0.9, h * 0.7), false, Color(0, 0, 0, 0.30))
	for t in trees:
		var pc := int(t[2])
		var an: Array = Atlas.ANCHOR[pc]
		var r: Array = Atlas.RECT[pc]
		var s := float(t[3])
		var w := float(an[2]) * s
		var h := float(an[3]) * s
		var tint := float(t[4])
		c.draw_texture_rect_region(_atlas1, Rect2(float(t[0]) + float(an[0]) * s - w * 0.5, float(t[1]) + float(an[1]) * s - h * 0.5, w, h),
			Rect2(float(r[0]) * lowk, float(r[1]) * lowk, float(r[2]) * lowk, float(r[3]) * lowk), Color(tint, tint, tint, 1.0))
	for f in forts:
		var p2 := int(f[2])
		var an2: Array = Atlas2.ANCHOR[p2]
		var r2: Array = Atlas2.RECT[p2]
		var yaw := float(f[3])
		var sc := float(f[4])
		var e := Vector2(cos(yaw), sin(yaw))
		var dn := Vector2(-e.y, e.x)
		var lk: float = lowk2
		var w2 := float(an2[2]) * sc
		var h2 := float(an2[3]) * sc
		var o := Vector2(f[0], f[1]) + (e * float(an2[0]) + dn * float(an2[1])) * sc
		c.draw_set_transform_matrix(Transform2D(e, dn, o))
		c.draw_texture_rect_region(_atlas2, Rect2(-w2 * 0.5, -h2 * 0.5, w2, h2),
			Rect2(float(r2[0]) * lk, float(r2[1]) * lk, float(r2[2]) * lk, float(r2[3]) * lk))
		c.draw_set_transform_matrix(Transform2D.IDENTITY)


# ----------------------------------------------------------------- wakes ---

## A soft round foam blob with a broken, bubbly edge (the wake's and the bow wave's puff).
static func _foam_blob() -> ImageTexture:
	var n := 64
	var tab := PackedFloat32Array()
	for q in 256:
		tab.append(_hf(q, q * 7, 3))
	var bytes := PackedByteArray()
	bytes.resize(n * n * 4)
	for y in n:
		for x in n:
			var dx := (x + 0.5) / n * 2.0 - 1.0
			var dy := (y + 0.5) / n * 2.0 - 1.0
			var r := sqrt(dx * dx + dy * dy)
			var nz := tab[((x >> 2) & 15) * 16 + ((y >> 2) & 15)] * 0.5 + tab[(((x >> 1) + 5) & 15) * 16 + (((y >> 1) + 9) & 15)] * 0.3 \
				+ tab[((x * 7 + 3) & 15) * 16 + ((y * 5 + 1) & 15)] * 0.2
			var a := smoothstep(0.22, 0.8, nz + (1.0 - r) * 0.95 - 0.5)
			var o := (y * n + x) * 4
			bytes[o] = 255
			bytes[o + 1] = 255
			bytes[o + 2] = 255
			bytes[o + 3] = int(a * 255.0 + 0.5)
	return ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, bytes))


static func _soft_blob() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var dx := (x + 0.5) / n * 2.0 - 1.0
			var dy := (y + 0.5) / n * 2.0 - 1.0
			var a := clampf(1.0 - sqrt(dx * dx + dy * dy), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * (3.0 - 2.0 * a)))
	return ImageTexture.create_from_image(img)


## The wakes as foam on the water (replaces the old lines): `pts` are the ship's recent positions
## oldest first (the last one the ship's), `beam` her beam in metres, `speed` 0 .. 1 of her top
## speed. Puffs grow and fade with age; a bow wave at the head. One texture, so it batches.
func draw_wake(c: CanvasItem, pts: PackedVector2Array, beam: float, speed: float, heading: float) -> void:
	var n := pts.size()
	if n < 2:
		return
	for i in range(1, n):
		var f := float(i) / float(n - 1)            # 0 old .. 1 new
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		if seg < 0.3:
			continue
		var age := 1.0 - f
		var r := beam * (0.55 + age * 1.5)
		var al := 0.40 * pow(f, 0.8) * clampf(0.35 + speed, 0.0, 1.0)
		var steps := clampi(int(ceil(seg / maxf(r * 0.38, 1.0))), 1, 10)
		for k in steps:
			var p := a.lerp(b, (k + 0.5) / float(steps))
			var qx := int(floor(p.x / 3.0))
			var qy := int(floor(p.y / 3.0))
			var jit := Vector2(_hf(qx, qy, 1) - 0.5, _hf(qx, qy, 2) - 0.5) * beam * (0.5 + age * 1.6)
			var rr := r * (0.7 + 0.5 * _hf(qx, qy, 3))
			c.draw_texture_rect(foam_tex, Rect2(p + jit - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(1, 1, 1, al * (0.7 + 0.5 * _hf(qx, qy, 4))))
	# The bow wave: a short white moustache either side of the stem, strongest at speed.
	var head := pts[n - 1]
	var fw := Vector2(cos(heading), sin(heading))
	var sd := Vector2(-fw.y, fw.x)
	var bs := clampf(speed, 0.0, 1.0)
	if bs > 0.08:
		for sgn in [-1.0, 1.0]:
			for q in 3:
				var pos: Vector2 = head + fw * beam * (1.6 - 0.45 * q) + sd * float(sgn) * beam * (0.25 + 0.3 * q)
				var rr: float = beam * (0.45 + 0.12 * q)
				c.draw_texture_rect(foam_tex, Rect2(pos - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(1, 1, 1, 0.4 * bs))
