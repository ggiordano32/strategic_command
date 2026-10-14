extends Node2D
## A static cast shadow + ambient occlusion layer for the battle kit's walls, towers and gates (view only,
## High quality). Baked once at battle load from the pieces' heights (the height channel of the kit
## atlas, scaled by each instance's wall height) on a 0.5 m grid: a height raster, the shadow cast to
## the south-east by the north-west light (40 degrees up, long and soft), a short dark rim where a wall
## meets the ground. One multiplied Sprite2D (under the pieces, over the ground and the houses): colours
## are cool dark values on white, alpha 1, so MUL darkens the ground and whatever lies there. A gate
## that breaks re-bakes only the window round it. Nothing here touches the sim.

const Atlas := preload("res://game/battlekit_atlas.gd")

var cell := 0.5                    # metres (the kit's shadow_cell)
const TAN_ELEV := 1.0              # tan(45 degrees)
const MAX_LEN := 12.0              # metres of shadow at most
const SH_DIR := Vector2(0.74, 0.67)
const SH_STR := 0.34
const AO_STR := 0.30
const TINT := Vector3(0.38, 0.34, 0.24)    # 1 - (0.62, 0.66, 0.76): the shadow's cool cast

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
var _touch := PackedInt32Array()
var _dir := SH_DIR.normalized()


func build(p_kit) -> void:
	kit = p_kit
	cell = kit.shadow_cell
	_nrm = _raw(kit.TEX_NRM)
	_alb = _raw(kit.TEX_ALB)
	_aw = int(Atlas.ATLAS_W)
	# Bounds of everything, a margin on the north-west, the shadow's reach on the south-east.
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for i in kit.i_piece.size():
		var fp := _footprint(i)
		lo = lo.min(fp.position)
		hi = hi.max(fp.end)
	_org = (lo - Vector2(4, 4)).floor()
	var end := (hi + Vector2(MAX_LEN * 0.5, MAX_LEN * 0.5)).ceil()
	_w = int((end.x - _org.x) / cell)
	_h = int((end.y - _org.y) / cell)
	_ht.resize(_w * _h)
	_sh.resize(_w * _h)
	_ao.resize(_w * _h)
	_px.resize(_w * _h * 4)
	_px.fill(255)
	for i in kit.i_piece.size():
		_raster(i, 0, 0, _w, _h)
	_cast(0, 0, _w, _h, 0, 0, _w, _h)
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


## Shadow and AO from the sources in [sx0, sx1) x [sy0, sy1) into the targets in [tx0, tx1) x [ty0, ty1).
func _cast(sx0: int, sy0: int, sx1: int, sy1: int, tx0: int, ty0: int, tx1: int, ty1: int) -> void:
	var step2 := Vector2i(roundi(_dir.x * 2.0), roundi(_dir.y * 2.0))
	var w := _w
	for y in range(sy0, sy1):
		for x in range(sx0, sx1):
			var h := _ht[y * w + x]
			if h < 0.5:
				continue
			# Shadow: only from cells whose south-east neighbour is lower (the lit-side edge).
			var nx := x + step2.x
			var ny := y + step2.y
			if nx >= 0 and ny >= 0 and nx < w and ny < _h and _ht[ny * w + nx] < h - 0.05:
				var reach := minf(h / TAN_ELEV, MAX_LEN) / cell
				var d := 1.0
				while d <= reach:
					var tx := x + int(round(_dir.x * d))
					var ty := y + int(round(_dir.y * d))
					d += 1.0
					if tx < tx0 or ty < ty0 or tx >= tx1 or ty >= ty1:
						continue
					var ray := h - d * cell * TAN_ELEV
					var ti := ty * w + tx
					var gap := ray - _ht[ti]
					if gap <= 0.0:
						continue
					var s := (1.0 - 0.55 * d / reach) * minf(gap / 0.7, 1.0)
					var b := int(s * 255.0)
					if b > _sh[ti]:
						_sh[ti] = b
			# Occlusion: a short rim on the ground beside a wall's foot.
			if h < 0.9:
				continue
			for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ax: int = x + dv.x
				var ay: int = y + dv.y
				if ax < 0 or ay < 0 or ax >= w or ay >= _h or _ht[ay * w + ax] > h - 0.3:
					continue
				for s2 in 3:
					var ox: int = ax + dv.x * s2
					var oy: int = ay + dv.y * s2
					if ox < tx0 or oy < ty0 or ox >= tx1 or oy >= ty1 or ox >= w or oy >= _h or ox < 0 or oy < 0:
						break
					if _ht[oy * w + ox] > h - 0.3:
						break
					var ab := int((0.6 - 0.22 * s2) * 255.0)
					if ab > _ao[oy * w + ox]:
						_ao[oy * w + ox] = ab


func _collect_touched() -> void:
	for i in _w * _h:
		if _sh[i] != 0 or _ao[i] != 0:
			_touch.append(i)


func _set_px(i: int) -> void:
	var dark := minf(float(_sh[i]) / 255.0 * SH_STR + float(_ao[i]) / 255.0 * AO_STR, 0.62)
	var o := i * 4
	_px[o] = int((1.0 - dark * TINT.x) * 255.0)
	_px[o + 1] = int((1.0 - dark * TINT.y) * 255.0)
	_px[o + 2] = int((1.0 - dark * TINT.z) * 255.0)
	_px[o + 3] = 255


## Instance i changed piece (a gate broke): re-raster and re-cast the window round it.
func rebake_instance(i: int) -> void:
	if _spr == null:
		return
	var fp := _footprint(i)
	var x0 := maxi(int(floor((fp.position.x - 4.0 - _org.x) / cell)), 0)
	var y0 := maxi(int(floor((fp.position.y - 4.0 - _org.y) / cell)), 0)
	var x1 := mini(int(ceil((fp.end.x + 20.0 - _org.x) / cell)), _w)
	var y1 := mini(int(ceil((fp.end.y + 20.0 - _org.y) / cell)), _h)
	_nrm = _raw(kit.TEX_NRM)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c := y * _w + x
			_ht[c] = 0.0
			_sh[c] = 0
			_ao[c] = 0
	for j in kit.i_piece.size():
		var f2 := _footprint(j)
		if f2.end.x < _org.x + x0 * cell or f2.position.x > _org.x + x1 * cell \
				or f2.end.y < _org.y + y0 * cell or f2.position.y > _org.y + y1 * cell:
			continue
		_raster(j, x0, y0, x1, y1)
	var m := int(MAX_LEN / cell)
	_cast(maxi(x0 - m, 0), maxi(y0 - m, 0), x1, y1, x0, y0, x1, y1)
	_nrm = PackedByteArray()
	for y in range(y0, y1):
		for x in range(x0, x1):
			_set_px(y * _w + x)
	_img.set_data(_w, _h, false, Image.FORMAT_RGBA8, _px)
	_tex.update(_img)
