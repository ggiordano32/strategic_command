extends Node2D
## The fog over the map (world coordinates, over the terrain, trees and towns, under the overlay): one texture of
## the grid, a dark desaturating blue-grey where the planner's team has no sight, the edge one cell soft
## (bilinear). Rebuilt only when FogView.gen changes.
const FogView := preload("res://game/campaign/fog_view.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const FOG_COL := Color(0.06, 0.08, 0.11)
const FOG_A := 0.66

var _tex: ImageTexture = null
var _gen := -1


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _process(_d: float) -> void:
	if _gen != FogView.gen:
		_gen = FogView.gen
		visible = FogView.on
		if FogView.on:
			_rebuild()
		queue_redraw()


func _rebuild() -> void:
	var w := CGrid.width()
	var h := CGrid.height()
	var vis := FogView.vis
	if vis.size() != w * h:
		_tex = null
		return
	# alpha per cell: 1 unseen; blurred once over the 3x3 neighbourhood so the edge reads soft, but a cell that is
	# itself in sight stays at most half fogged (its own pixel is the centre of the sample)
	var a := PackedFloat32Array()
	a.resize(w * h)
	for i in w * h:
		a[i] = 0.0 if vis[i] != 0 else 1.0
	var data := PackedByteArray()
	data.resize(w * h * 4)
	for y in h:
		for x in w:
			var s := 0.0
			var n := 0.0
			for dy in range(-1, 2):
				var yy := clampi(y + dy, 0, h - 1)
				for dx in range(-1, 2):
					var xx := clampi(x + dx, 0, w - 1)
					var k := 2.0 if dx == 0 and dy == 0 else 1.0
					s += a[yy * w + xx] * k
					n += k
			var al := s / n
			var o := (y * w + x) * 4
			data[o] = int(FOG_COL.r * 255.0)
			data[o + 1] = int(FOG_COL.g * 255.0)
			data[o + 2] = int(FOG_COL.b * 255.0)
			data[o + 3] = int(clampf(al * FOG_A, 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	_tex = ImageTexture.create_from_image(img)


func _draw() -> void:
	if _tex == null or not FogView.on:
		return
	var px := float(CGrid.cell_px())
	var sz := Vector2(CGrid.width(), CGrid.height()) * px
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, sz), false)
	# the sea beyond the map's edge (the water node reaches 4000 px further) is as unseen as its border
	var c := Color(FOG_COL, FOG_A)
	var e := 4000.0
	draw_rect(Rect2(-e, -e, sz.x + 2.0 * e, e), c)
	draw_rect(Rect2(-e, sz.y, sz.x + 2.0 * e, e), c)
	draw_rect(Rect2(-e, 0.0, e, sz.y), c)
	draw_rect(Rect2(sz.x, 0.0, e, sz.y), c)
