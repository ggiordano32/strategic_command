extends Node2D
## A static cast shadow + ambient occlusion layer for the battle kit's walls, towers and gates (view only,
## High quality). Baked once at battle load from the pieces' heights (the height channel of the kit
## atlas, scaled by each instance's wall height) on a 0.5 m grid: a height raster, the shadow cast to
## the south-east by the north-west light (40 degrees up, long and soft), a short dark rim where a wall
## meets the ground. One multiplied Sprite2D (under the pieces, over the ground and the houses): colours
## are cool dark values on white, alpha 1, so MUL darkens the ground and whatever lies there. A gate
## that breaks re-bakes only the window round it. Nothing here touches the sim.

const Atlas := preload("res://game/battlekit_atlas.gd")
const BattleLook := preload("res://game/battle_look.gd")
const MapGen := preload("res://sim/mapgen.gd")

var cell := 0.5                    # metres (the kit's shadow_cell)
const TAN_ELEV := 0.62             # tan(32 degrees): a shadow is 1.6 x its piece's height long
const MAX_LEN := 36.0              # metres of shadow at most (a church or a tall tower)
const SH_STR := 0.72               # darkness under a wall's foot (diorama; painterly x PAINT_K)
const AO_STR := 0.55
const H_SHADOW := 1.4              # the kit's heights read low at game scale: shadows are cast from 1.4 x
const H_CAP := 15.0                # ... capped (a shadow at most about 24 m long)
const PAINT_K := 0.82
const AO_M := 2.5                  # metres of contact band
const AO_DX := [1, -1, 0, 0]
const AO_DY := [0, 0, 1, -1]
const MIN_CELL := 1.0              # the bake grid is never finer than this (the linear filter softens it)
const TINT := Vector3(0.58, 0.54, 0.42)    # 1 - (0.42, 0.46, 0.58): the shadow's cool cast

var kit
var _w := 0
var _h := 0
var _org := Vector2.ZERO           # metres, top-left of the grid
var _ht := PackedFloat32Array()    # metres
var _sh := PackedByteArray()
var _ao := PackedByteArray()
var _px := PackedByteArray()       # RGBA8
var _img: Image
var _tex: ImageTexture
var _spr: Sprite2D
var _nrm := PackedByteArray()      # atlas_nrm raw RGBA8 (B = height / 20 m)
var _alb := PackedByteArray()      # atlas_albedo raw RGBA8 (A = coverage)
var _aw := 0
var _snrm := PackedByteArray()     # the wall strip's normal / albedo (the strip is one repeating texture)
var _salb := PackedByteArray()
var _sw := 0
var _sh_px := 0
var _touch := PackedInt32Array()
var _ao_n := 3
var _k := 1.0                      # look strength (diorama 1, painterly PAINT_K)


func build(p_kit) -> void:
	kit = p_kit
	cell = maxf(kit.shadow_cell, MIN_CELL)
	_ao_n = ceili(AO_M / cell)
	_k = 1.0 if BattleLook.is_diorama() else PAINT_K
	_nrm = _raw(kit.TEX_NRM)
	_alb = _raw(kit.TEX_ALB)
	_aw = int(Atlas.ATLAS_W)
	if not kit.s_vx.is_empty():
		_snrm = _raw(kit.TEX_S_NRM)
		_salb = _raw(kit.TEX_S_ALB)
		_sw = kit.TEX_S_NRM.get_width()
		_sh_px = kit.TEX_S_NRM.get_height()
	# Bounds of everything, a margin on the north-west, the shadow's reach on the south-east.
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for i in kit.i_piece.size():
		var fp := _footprint(i)
		lo = lo.min(fp.position)
		hi = hi.max(fp.end)
	for pt in kit.s_vx:
		lo = lo.min(pt)
		hi = hi.max(pt)
	_org = (lo - Vector2(4, 4)).floor()
	var end := (hi + Vector2(MAX_LEN * 0.75, MAX_LEN * 0.75)).ceil()
	_w = int((end.x - _org.x) / cell)
	_h = int((end.y - _org.y) / cell)
	_ht.resize(_w * _h)
	_sh.resize(_w * _h)
	_ao.resize(_w * _h)
	_px.resize(_w * _h * 4)
	_px.fill(255)
	for i in kit.i_piece.size() + 1:
		if i == kit.strip_at:
			_raster_strip(0, 0, _w, _h)   # (the walls stand over the houses before them, under the gates and towers after)
		if i < kit.i_piece.size():
			_raster(i, 0, 0, _w, _h)
	_cast(0, 0, _w, _h, 0, 0, _w, _h)
	_blur(0, 0, _w, _h)
	_touch.resize(0)
	_collect_touched()
	for c in _touch:
		_set_px(c)
	_img = Image.create_from_data(_w, _h, false, Image.FORMAT_RGBA8, _px)
	_tex = ImageTexture.create_from_image(_img)
	_spr = Sprite2D.new()
	_spr.texture = _tex
	_spr.centered = false
	_spr.position = _org * kit.k
	_spr.scale = Vector2.ONE * cell * kit.k
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_spr.material = mat
	add_child(_spr)
	_nrm = PackedByteArray()   # only needed while baking; re-read on a rebake


static func _raw(tex: Texture2D) -> PackedByteArray:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img.get_data()


## The instance's footprint in metres (axis-aligned).
func _footprint(i: int) -> Rect2:
	var p: int = kit.i_piece[i]
	var an: Array = Atlas.ANCHOR[p]
	var e: Vector2 = kit.i_e[i]
	var dn := Vector2(-e.y, e.x)
	var sx: float = kit.i_sx[i]
	var sy: float = kit.i_sy[i]
	var c: Vector2 = kit.i_pos[i] + e * (float(an[0]) * sx) + dn * (float(an[1]) * sy)
	var hw := float(an[2]) * sx * 0.5
	var hh := float(an[3]) * sy * 0.5
	var ex := absf(e.x) * hw + absf(dn.x) * hh
	var ey := absf(e.y) * hw + absf(dn.y) * hh
	return Rect2(c - Vector2(ex, ey), Vector2(ex, ey) * 2.0)


## Rasterise instance i's heights into cells inside [x0, x1) x [y0, y1) (later instances replace
## earlier ones where the piece covers the cell).
func _raster(i: int, x0: int, y0: int, x1: int, y1: int) -> void:
	if kit.fallen(i):
		return  # (a fallen building casts nothing)
	var p: int = kit.i_piece[i]
	var an: Array = Atlas.ANCHOR[p]
	var rc: Array = Atlas.RECT[p]
	var e: Vector2 = kit.i_e[i]
	var dn := Vector2(-e.y, e.x)
	var sx: float = kit.i_sx[i]
	var sy: float = kit.i_sy[i]
	var hs: float = kit.i_hs[i]
	var c: Vector2 = kit.i_pos[i] + e * (float(an[0]) * sx) + dn * (float(an[1]) * sy)
	var fp := _footprint(i)
	var cx0 := maxi(int(floor((fp.position.x - _org.x) / cell)), x0)
	var cy0 := maxi(int(floor((fp.position.y - _org.y) / cell)), y0)
	var cx1 := mini(int(ceil((fp.end.x - _org.x) / cell)), x1)
	var cy1 := mini(int(ceil((fp.end.y - _org.y) / cell)), y1)
	var ppm: float = Atlas.PPM
	var rx := float(rc[0]) + float(rc[2]) * 0.5
	var ry := float(rc[1]) + float(rc[3]) * 0.5
	var rw := int(rc[0]) + int(rc[2])
	var rh := int(rc[1]) + int(rc[3])
	for cy in range(cy0, cy1):
		var qy := _org.y + (cy + 0.5) * cell
		for cx in range(cx0, cx1):
			var d := Vector2(_org.x + (cx + 0.5) * cell, qy) - c
			var u := d.dot(e) / sx
			var v := d.dot(dn) / sy
			var ax := int(rx + u * ppm)
			var ay := int(ry + v * ppm)
			if ax < int(rc[0]) or ay < int(rc[1]) or ax >= rw or ay >= rh:
				continue
			var o := (ay * _aw + ax) * 4
			if _alb[o + 3] < 128:
				continue
			_ht[cy * _w + cx] = float(_nrm[o + 2]) / 255.0 * 20.0 * hs


## The wall strip's triangles' heights inside [x0, x1) x [y0, y1): the texel the UV names (the UV is affine in
## the position: u tiles along the stretch from its origin, v across).
func _raster_strip(x0: int, y0: int, x1: int, y1: int) -> void:
	if _snrm.is_empty():
		return
	var vx: PackedVector2Array = kit.s_vx
	var hs: float = kit.strip_hs
	var vo: float = kit.strip_vo
	var vspan: float = kit.strip_vi - kit.strip_vo
	var rub: bool = kit.sim.rub_n > 0
	for t in vx.size() / 3:
		var a := vx[t * 3]
		var b := vx[t * 3 + 1]
		var c := vx[t * 3 + 2]
		var lo := a.min(b).min(c)
		var hi := a.max(b).max(c)
		var cx0 := maxi(int(floor((lo.x - _org.x) / cell)), x0)
		var cy0 := maxi(int(floor((lo.y - _org.y) / cell)), y0)
		var cx1 := mini(int(ceil((hi.x - _org.x) / cell)), x1)
		var cy1 := mini(int(ceil((hi.y - _org.y) / cell)), y1)
		var d: Vector2 = kit.s_d[t]
		var nn := Vector2(-d.y, d.x)
		var org: Vector2 = kit.s_a[t]
		var step: float = kit.s_step[t]
		var den := (b - a).cross(c - a)
		if absf(den) < 0.0001:
			continue
		for cy in range(cy0, cy1):
			var qy := _org.y + (cy + 0.5) * cell
			for cx in range(cx0, cx1):
				var q := Vector2(_org.x + (cx + 0.5) * cell, qy)
				var w0 := (b - q).cross(c - q) / den
				var w1 := (c - q).cross(a - q) / den
				var w2 := 1.0 - w0 - w1
				if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
					continue
				if rub and kit.sim.obs_kind(int(q.x * 1024.0), int(q.y * 1024.0)) == MapGen.C_RUBBLE:
					continue  # (a breach: no wall there)
				var u := (q - org).dot(d) / step
				var v := ((q - org).dot(nn) - vo) / vspan
				if v < 0.0 or v >= 1.0:
					continue
				var ax := clampi(int((u - floor(u)) * float(_sw)), 0, _sw - 1)
				var ay := clampi(int(v * float(_sh_px)), 0, _sh_px - 1)
				var o := (ay * _sw + ax) * 4
				if _salb[o + 3] < 128:
					continue
				_ht[cy * _w + cx] = float(_snrm[o + 2]) / 255.0 * 20.0 * hs


## Shadow and AO from the sources in [sx0, sx1) x [sy0, sy1) into the targets in [tx0, tx1) x [ty0, ty1).
## The shadow is a height-field sweep along the light's diagonal (north-west to south-east): each cell's
## "ray" height is the higher of its own height and the ray before it minus the drop over one diagonal
## step; a cell below its ray is in shadow by the gap. Every roof ridge and wall top casts, not only edges.
func _cast(sx0: int, sy0: int, sx1: int, sy1: int, tx0: int, ty0: int, tx1: int, ty1: int) -> void:
	var w := _w
	var drop := cell * 1.4142 * TAN_ELEV
	var ray := PackedFloat32Array()
	ray.resize(w * _h)
	for y in range(sy0, sy1):
		for x in range(sx0, sx1):
			var i := y * w + x
			var hh := minf(_ht[i] * H_SHADOW, H_CAP)
			var r := hh
			if x > sx0 and y > sy0:
				r = maxf(hh, ray[i - w - 1] - drop)
			ray[i] = r
			var gap := r - hh
			if gap > 0.05 and x >= tx0 and x < tx1 and y >= ty0 and y < ty1:
				var sv := minf(gap / 1.4, 1.0) * (0.6 + 0.4 * minf(gap / 6.0, 1.0))
				var bv := int(sv * 255.0)
				if bv > _sh[i]:
					_sh[i] = bv
	for y in range(sy0, sy1):
		for x in range(sx0, sx1):
			var h := _ht[y * w + x]
			if h < 0.5:
				continue
			# Occlusion: a short rim on the ground beside a wall's foot.
			if h < 0.9:
				continue
			for dd in 4:
				var ddx: int = AO_DX[dd]
				var ddy: int = AO_DY[dd]
				var ax: int = x + ddx
				var ay: int = y + ddy
				if ax < 0 or ay < 0 or ax >= w or ay >= _h or _ht[ay * w + ax] > h - 0.3:
					continue
				for s2 in _ao_n:
					var ox: int = ax + ddx * s2
					var oy: int = ay + ddy * s2
					if ox < tx0 or oy < ty0 or ox >= tx1 or oy >= ty1 or ox >= w or oy >= _h or ox < 0 or oy < 0:
						break
					if _ht[oy * w + ox] > h - 0.3:
						break
					var t := float(s2) / float(_ao_n)
					var ab := int((1.0 - t) * (1.0 - t) * 255.0)
					if ab > _ao[oy * w + ox]:
						_ao[oy * w + ox] = ab


## Soft edge: two 3-tap box blurs (separable) of the cast shadow inside the window.
func _blur(x0: int, y0: int, x1: int, y1: int) -> void:
	var w := _w
	var xa := maxi(x0, 1)
	var xb := mini(x1, w - 1)
	var ya := maxi(y0, 1)
	var yb := mini(y1, _h - 1)
	var tmp := PackedByteArray()
	tmp.resize(w * _h)
	for pass_i in 2:
		for y in range(y0, y1):
			var o := y * w
			for x in range(xa, xb):
				tmp[o + x] = (_sh[o + x - 1] + _sh[o + x] + _sh[o + x + 1]) / 3
		for y in range(ya, yb):
			var o2 := y * w
			for x in range(xa, xb):
				_sh[o2 + x] = (tmp[o2 + x - w] + tmp[o2 + x] + tmp[o2 + x + w]) / 3


func _collect_touched() -> void:
	for i in _w * _h:
		if _sh[i] != 0 or _ao[i] != 0:
			_touch.append(i)


func _set_px(i: int) -> void:
	var dark := minf(float(_sh[i]) / 255.0 * SH_STR + float(_ao[i]) / 255.0 * AO_STR, 0.8) * _k
	var o := i * 4
	_px[o] = int((1.0 - dark * TINT.x) * 255.0)
	_px[o + 1] = int((1.0 - dark * TINT.y) * 255.0)
	_px[o + 2] = int((1.0 - dark * TINT.z) * 255.0)
	_px[o + 3] = 255


## Instance i changed piece (a gate broke): re-raster and re-cast the window round it.
func rebake_instance(i: int) -> void:
	rebake_rect(_footprint(i))


## Bake the shadow again round a box (metres): a gate broken, a stretch breached, a building fallen.
func rebake_rect(fp: Rect2) -> void:
	if _spr == null:
		return
	var x0 := maxi(int(floor((fp.position.x - 4.0 - _org.x) / cell)), 0)
	var y0 := maxi(int(floor((fp.position.y - 4.0 - _org.y) / cell)), 0)
	var x1 := mini(int(ceil((fp.end.x + MAX_LEN * 0.75 + 2.0 - _org.x) / cell)), _w)
	var y1 := mini(int(ceil((fp.end.y + MAX_LEN * 0.75 + 2.0 - _org.y) / cell)), _h)
	_nrm = _raw(kit.TEX_NRM)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c := y * _w + x
			_ht[c] = 0.0
			_sh[c] = 0
			_ao[c] = 0
	for j in kit.i_piece.size() + 1:
		if j == kit.strip_at:
			_raster_strip(x0, y0, x1, y1)
		if j == kit.i_piece.size():
			break
		var f2 := _footprint(j)
		if f2.end.x < _org.x + x0 * cell or f2.position.x > _org.x + x1 * cell \
				or f2.end.y < _org.y + y0 * cell or f2.position.y > _org.y + y1 * cell:
			continue
		_raster(j, x0, y0, x1, y1)
	var m := int(MAX_LEN / cell)
	_cast(maxi(x0 - m, 0), maxi(y0 - m, 0), x1, y1, x0, y0, x1, y1)
	_nrm = PackedByteArray()
	_blur(x0, y0, x1, y1)
	for y in range(y0, y1):
		for x in range(x0, x1):
			_set_px(y * _w + x)
	_img.set_data(_w, _h, false, Image.FORMAT_RGBA8, _px)
	_tex.update(_img)
