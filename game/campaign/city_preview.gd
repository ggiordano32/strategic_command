extends Control
## Static top-down picture of a settlement's battle map as it stands (the
## region panel's "View battle map"): the same generator as the battle
## (sim/terrain.gd + sim/mapgen.gd from CBattle.city_preview_terrain), drawn
## once: the ground (palette, height shading, woods, fields, streets) as a
## small image at 2 m a pixel, then buildings, walls, towers, gates, the
## plaza and the attackers' approach as shapes on top. View only; cached per
## map (seed, level, walls, buildings, ground).

const Terrain := preload("res://sim/terrain.gd")
const MapGen := preload("res://sim/mapgen.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const GroundPalette := preload("res://game/ground_palette.gd")

const ROOF := [Color(0.69, 0.40, 0.28), Color(0.80, 0.76, 0.66), Color(0.74, 0.55, 0.35),
	Color(0.58, 0.36, 0.27), Color(0.62, 0.47, 0.33), Color(0.55, 0.42, 0.36), Color(0.64, 0.44, 0.30)]
const STONE := Color(0.66, 0.63, 0.56)
const STONE_DARK := Color(0.33, 0.31, 0.28)

static var _cache := {}

var data: Dictionary = {}   # {"tex", "crop": Rect2 (m), "lay", "pal"}


## Build (or fetch) the preview data for terrain dictionary `terr` (with
## "city", defenders at the top).
static func make(terr: Dictionary) -> Dictionary:
	var key := str(terr)
	if _cache.has(key):
		return _cache[key]
	var c: Dictionary = terr["city"]
	var fs := MapGen.city_field(c, 300, 110)
	var t := Terrain.build(terr, 0, fs.x * 1024, fs.y * 1024)
	var f := MapGen.build(terr, 0, fs.x, fs.y, t)
	var lay: Dictionary = f["city"]
	var pal := GroundPalette.get_palette(int(terr.get("ground", 0)))
	var rmax: int = int(lay["r0"]) * 112 / 100
	var cx: int = lay["cx"]
	var cy: int = lay["cy"]
	var half := rmax + 55
	var x0 := clampi(cx - half, 0, fs.x)
	var x1 := clampi(cx + half, 0, fs.x)
	var y0 := clampi(cy - rmax - 35, 0, fs.y)
	var y1 := clampi(int(lay["att_y"]) + 25, 0, fs.y)
	var crop := Rect2(x0, y0, x1 - x0, y1 - y0)
	# Ground at 2 m a pixel.
	var iw := (x1 - x0) / 2
	var ih := (y1 - y0) / 2
	var img := Image.create(maxi(iw, 1), maxi(ih, 1), false, Image.FORMAT_RGB8)
	var h: PackedInt32Array = t["h"]
	var nx: int = t["nx"]
	var ny: int = t["ny"]
	var on := int(t["on"]) != 0
	var hmax := 1
	var hmin := 1 << 30
	for v in h:
		hmax = maxi(hmax, v)
		hmin = mini(hmin, v)
	var veg: PackedByteArray = f["veg"]
	var vw: int = f["vw"]
	var obs: PackedByteArray = f["obs"]
	var ow: int = f["ow"]
	var base: Color = pal["base"]
	var lo: Color = pal["low"]
	var hi: Color = pal["high"]
	var tree: Color = (pal["trees"] as Array)[0]
	var street := base.lerp(Color(0.86, 0.80, 0.68), 0.55)
	var field_c := base.lerp(Color(0.85, 0.74, 0.40), 0.55)
	for j in ih:
		var my := y0 + j * 2 + 1
		for i in iw:
			var mx := x0 + i * 2 + 1
			var col := base
			if on:
				var ni := mini(mx / 4, nx - 2)
				var nj := mini(my / 4, ny - 2)
				var hv := h[nj * nx + ni]
				var gx := h[nj * nx + ni + 1] - hv
				var gy := h[(nj + 1) * nx + ni] - hv
				var e := clampf(float(hv - hmin) / float(maxi(hmax - hmin, 2048)) * 2.0 - 1.0, -1.0, 1.0)
				col = base.lerp(lo, -e) if e < 0.0 else base.lerp(hi, e)
				# Light from the upper left (grade of 4 m cells, metres x 1024).
				var sh := clampf(-(gx + gy) / 1024.0 * 0.11, -0.22, 0.22)
				col = col * (1.0 + sh)
			var vb: int = veg[mini(my / 4, (veg.size() / vw) - 1) * vw + mini(mx / 4, vw - 1)]
			if (vb & MapGen.V_FIELD) != 0:
				col = field_c
			if (vb & MapGen.V_URBAN) != 0:
				col = col.lerp(street, 0.6)
			if (vb & MapGen.V_PLAZA) != 0:
				col = street.lightened(0.12)
			var d := vb & MapGen.V_DENS
			if d > 0:
				col = col.lerp(tree, 0.3 + 0.17 * d)
			if ow > 0:
				var k: int = obs[(my / 2) * ow + mx / 2]
				if k == MapGen.C_BUILDING:
					col = col.darkened(0.25)  # under the roofs (shapes drawn on top)
			img.set_pixel(i, j, Color(col.r, col.g, col.b))
	var out := {"tex": ImageTexture.create_from_image(img), "crop": crop, "lay": lay, "pal": pal,
		"houses": (lay["buildings"] as Array).size()}
	_cache[key] = out
	return out


## A preview control for settlement r of state st, `width` logical px wide.
static func for_region(st: Dictionary, r: int, width: float) -> Control:
	var c := new()
	c.data = make(CBattle.city_preview_terrain(st, r))
	var crop: Rect2 = c.data["crop"]
	c.custom_minimum_size = Vector2(width, width * crop.size.y / maxf(crop.size.x, 1.0))
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	return c


func _draw() -> void:
	if data.is_empty():
		return
	var crop: Rect2 = data["crop"]
	var sc := size.x / crop.size.x
	var o := -crop.position * sc
	draw_texture_rect(data["tex"], Rect2(Vector2.ZERO, size), false)
	var lay: Dictionary = data["lay"]
	var m := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * sc
	# Buildings: flat roofs with a shadow toward the lower right.
	for b in lay["buildings"]:
		var a: Array = b
		var rc := Rect2(m.call(a[0], a[1]), Vector2(int(a[2]) - int(a[0]), int(a[3]) - int(a[1])) * sc)
		draw_rect(Rect2(rc.position + Vector2(1.2, 1.2) * maxf(sc, 0.6), rc.size), Color(0, 0, 0, 0.3))
		var roof: Color = ROOF[clampi(int(a[4]), 0, ROOF.size() - 1)]
		draw_rect(rc, roof)
		draw_rect(rc, roof.darkened(0.35), false, 1.0)
	# Plaza outline.
	var pl: Array = lay["plaza"]
	var ph: float = pl[2]
	draw_rect(Rect2(m.call(int(pl[0]) - ph, int(pl[1]) - ph), Vector2(ph, ph) * 2.0 * sc), Color(1, 0.95, 0.7, 0.8), false, 1.5)
	# Walls: the circuit as a thick stone band, towers, gates.
	var walls: int = lay["walls"]
	if walls > 0:
		var poly: PackedInt32Array = lay["poly"]
		var pts := PackedVector2Array()
		for k in poly.size() / 2:
			pts.append(m.call(poly[k * 2], poly[k * 2 + 1]))
		pts.append(pts[0])
		var tw: float = maxf(float(lay["t"]) * sc, 3.0)
		draw_polyline(pts, STONE_DARK, tw + 2.0, true)
		draw_polyline(pts, STONE, tw, true)
		for tow in lay["towers"]:
			var a: Array = tow
			draw_circle(m.call(a[0], a[1]), maxf(float(a[2]) * sc, 2.5) + 1.0, STONE_DARK)
			draw_circle(m.call(a[0], a[1]), maxf(float(a[2]) * sc, 2.5), STONE.lightened(0.08))
		var gi := 0
		for gd in lay["gates"]:
			var c: Vector2 = m.call(gd["x"], gd["y"])
			var ang := float(int(gd["dir"])) / 1024.0 * TAU
			var along := Vector2(-sin(ang), cos(ang)) * float(MapGen.GATE_HW) * sc
			var out := Vector2(cos(ang), sin(ang)) * (float(lay["t"]) * 0.5 * sc + 1.0)
			var q := PackedVector2Array([c - along - out, c + along - out, c + along + out, c - along + out])
			draw_colored_polygon(q, Color(0.42, 0.27, 0.14) if gi > 0 else Color(0.85, 0.30, 0.15))
			gi += 1
	# The attackers' approach: an arrow from their deployment to the main gate.
	var ax: Vector2 = m.call(lay["att_x"], lay["att_y"])
	var tgt: Vector2 = m.call(lay["att_x"], int(lay["cy"]) + int(lay["r0"]) * 112 / 100 + 6)
	if not (lay["gates"] as Array).is_empty():
		var g0: Dictionary = lay["gates"][0]
		tgt = m.call(g0["ox"], g0["oy"])
	var dv := tgt - ax
	if dv.length() > 20.0:
		var u := dv.normalized()
		var tip := tgt - u * 6.0
		draw_line(ax, tip - u * 10.0, Color(0, 0, 0, 0.5), 6.0, true)
		draw_line(ax, tip - u * 10.0, Color(1.0, 0.85, 0.35, 0.95), 3.5, true)
		var nrm := Vector2(-u.y, u.x)
		draw_colored_polygon(PackedVector2Array([tip, tip - u * 13.0 + nrm * 7.0, tip - u * 13.0 - nrm * 7.0]),
			Color(1.0, 0.85, 0.35, 0.95))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6), false, 1.0)
