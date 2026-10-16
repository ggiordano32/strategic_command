extends Sprite2D
## The settlement's streets on the battle map (view only): the sim's own street segments (gate to plaza, the
## main streets, the lanes) as wide strips and the lanes between house blocks as the free ground within a few
## metres of the footprints, painted into one texture (0.5 m cells) under the kit. Paving for Latin, Greek and
## Punic towns and colonial plazas (cobbles, a curb), packed dirt for Celtic and native ones. Nothing here
## touches the sim.

const MapGen := preload("res://sim/mapgen.gd")

const CELL := 0.5
const LANE_GROW := 3.0      # metres: a lane runs this far from the houses' footprints
const MARGIN := 6.0


func build(lay: Dictionary, k: float, style: int) -> void:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	var rects: Array = []
	for b in lay["buildings"]:
		var a: Array = b
		var shape := int(a[6]) if a.size() > 6 else MapGen.SH_RECT
		var r: Rect2
		if shape == MapGen.SH_ROUND:
			var rr := float(int(a[9]))
			r = Rect2(float(int(a[7])) - rr, float(int(a[8])) - rr, rr * 2.0, rr * 2.0)
		elif shape == MapGen.SH_QUAD:
			var mn := Vector2(1e9, 1e9)
			var mx := Vector2(-1e9, -1e9)
			for q in 4:
				var pt := Vector2(float(int(a[7 + q * 2])), float(int(a[8 + q * 2])))
				mn = mn.min(pt)
				mx = mx.max(pt)
			r = Rect2(mn, mx - mn)
		else:
			r = Rect2(float(int(a[0])), float(int(a[1])), float(int(a[2]) - int(a[0])), float(int(a[3]) - int(a[1])))
		rects.append(r)
		lo = lo.min(r.position)
		hi = hi.max(r.end)
	var segs: Array = lay.get("streets", [])
	for s in segs:
		var sw := float(int(s[4])) * 0.5
		lo = lo.min(Vector2(minf(float(int(s[0])), float(int(s[2]))) - sw, minf(float(int(s[1])), float(int(s[3]))) - sw))
		hi = hi.max(Vector2(maxf(float(int(s[0])), float(int(s[2]))) + sw, maxf(float(int(s[1])), float(int(s[3]))) + sw))
	if lo.x > hi.x:
		return
	var ag: Array = lay.get("agora", lay["plaza"])
	var ahs := float(int(ag[2]))
	lo = lo.min(Vector2(float(int(ag[0])) - ahs, float(int(ag[1])) - ahs))
	hi = hi.max(Vector2(float(int(ag[0])) + ahs, float(int(ag[1])) + ahs))
	var org := (lo - Vector2(MARGIN, MARGIN)).floor()
	var w := int((hi.x + MARGIN - org.x) / CELL) + 1
	var h := int((hi.y + MARGIN - org.y) / CELL) + 1
	var zone := PackedByteArray()
	zone.resize(w * h)
	var marked := PackedInt32Array()
	# Lanes: the free ground round every footprint.
	for r in rects:
		var rc := (r as Rect2).grow(LANE_GROW)
		_fill(zone, marked, w, h, org, rc, 1)
	# Main streets: the sim's segments, and the agora's square.
	for s in segs:
		var a0 := Vector2(float(int(s[0])), float(int(s[1])))
		var a1 := Vector2(float(int(s[2])), float(int(s[3])))
		var hw := float(int(s[4])) * 0.5 + 0.5
		var bb := Rect2(a0.min(a1), (a0.max(a1) - a0.min(a1))).grow(hw)
		var x0 := maxi(int((bb.position.x - org.x) / CELL), 0)
		var x1 := mini(int((bb.end.x - org.x) / CELL) + 1, w - 1)
		var y0 := maxi(int((bb.position.y - org.y) / CELL), 0)
		var y1 := mini(int((bb.end.y - org.y) / CELL) + 1, h - 1)
		var d := a1 - a0
		var l2 := maxf(d.length_squared(), 0.01)
		for cy in range(y0, y1 + 1):
			for cx in range(x0, x1 + 1):
				var p := org + Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL)
				var t := clampf((p - a0).dot(d) / l2, 0.0, 1.0)
				if p.distance_to(a0 + d * t) <= hw:
					var i := cy * w + cx
					if zone[i] == 0:
						marked.append(i)
					zone[i] = 2
	# (A West town, phase W: sandy earth streets, the plaza paved, zone 3.)
	var west := int(lay.get("west", 0)) != 0
	_fill(zone, marked, w, h, org, Rect2(float(int(ag[0])) - ahs, float(int(ag[1])) - ahs, ahs * 2.0, ahs * 2.0), 3 if west else 2)
	# Paint.
	var paved := style != 3 and style != 5 and not west
	var px := PackedByteArray()
	px.resize(w * h * 4)
	for i in marked:
		var cx := i % w
		var cy := i / w
		var z := zone[i]
		var edge := false
		if cx == 0 or cy == 0 or cx == w - 1 or cy == h - 1:
			edge = true
		else:
			edge = zone[i - 1] == 0 or zone[i + 1] == 0 or zone[i - w] == 0 or zone[i + w] == 0
		var hv := 0.0
		var n := float((((cx * 374761393) ^ (cy * 668265263)) * 1274126177 >> 8) & 255) / 255.0
		var col: Vector3
		if z == 3:
			col = Vector3(0.70, 0.66, 0.58)
			var cob2 := (cx / 2 + (cy / 2 % 2)) % 3
			col *= 0.9 + 0.12 * n - (0.06 if (cx % 2 == 0 or cy % 2 == 0) else 0.0) - 0.02 * float(cob2)
			if edge:
				col *= 0.75
		elif west:
			col = Vector3(0.66, 0.57, 0.42) if z == 2 else Vector3(0.60, 0.52, 0.39)
			col *= 0.9 + 0.16 * n
		elif paved:
			col = Vector3(0.66, 0.62, 0.55) if z == 2 else Vector3(0.60, 0.56, 0.49)
			var cob := (cx / 2 + (cy / 2 % 2) * 1) % 3   # cobbles 1 m, offset rows
			col *= 0.9 + 0.14 * n - (0.07 if (cx % 2 == 0 or cy % 2 == 0) else 0.0) + hv
			col *= 1.0 - 0.025 * float(cob)
			if edge:
				col *= 0.72
		else:
			col = Vector3(0.53, 0.42, 0.30) if z == 2 else Vector3(0.48, 0.38, 0.27)
			col *= 0.88 + 0.2 * n
			if edge:
				col *= 0.9
		var al := 1.0 if z >= 2 else 0.9
		if edge and not paved and z != 3:
			al *= 0.6
		var o := i * 4
		px[o] = clampi(int(col.x * 255.0), 0, 255)
		px[o + 1] = clampi(int(col.y * 255.0), 0, 255)
		px[o + 2] = clampi(int(col.z * 255.0), 0, 255)
		px[o + 3] = int(al * 255.0)
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, px)
	texture = ImageTexture.create_from_image(img)
	centered = false
	position = org * k
	scale = Vector2.ONE * CELL * k
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if paved else CanvasItem.TEXTURE_FILTER_LINEAR


static func _fill(zone: PackedByteArray, marked: PackedInt32Array, w: int, h: int, org: Vector2, rc: Rect2, val: int) -> void:
	var x0 := maxi(int((rc.position.x - org.x) / CELL), 0)
	var x1 := mini(int((rc.end.x - org.x) / CELL), w - 1)
	var y0 := maxi(int((rc.position.y - org.y) / CELL), 0)
	var y1 := mini(int((rc.end.y - org.y) / CELL), h - 1)
	for cy in range(y0, y1 + 1):
		var row := cy * w
		for cx in range(x0, x1 + 1):
			var i := row + cx
			if zone[i] == 0:
				marked.append(i)
			if zone[i] < val:
				zone[i] = val
