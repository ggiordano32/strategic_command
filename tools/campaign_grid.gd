extends SceneTree
## Builds the campaign nav grid (state format 6, the continuous overworld)
## from the map geometry (game/campaign/map_geo.gd: landmass polygons and
## the regions' territories) and writes it as static data to
## campaign/data/grid_data.gd (a GDScript file of constants, so it is
## exported and loads without parsing or floats).
##   godot --headless --script res://tools/campaign_grid.gd [-- --cell=20 --check]
##
## Cells are square on the map: CELL map pixels (20 = 0.2 deg of latitude,
## 0.26 deg of longitude). Per cell: sea, unclaimed land (the map's phantom
## areas: impassable) or a region (by majority of 3 x 3 samples of the
## territory polygons). A cell is land when at least 2 of its 9 samples are
## on a landmass polygon (islands that are only decoration count as sea).
## Then per region: the settlement cell (the cell holding the settlement, else
## the region's nearest cell), the port cell for ports (the coastal cell of
## the region nearest the settlement, not the settlement cell itself) and a
## camp cell (a field cell away from the settlement, near the territory's
## centre). Land routes whose regions end up in different land components
## (thin isthmuses, phantom areas between them) are joined by a corridor
## along the line between their settlements (the cells taken by the nearer
## of the two regions). Every region must have cells and each landmass must
## be one connected component; the tool prints what it fixed and checks.
## --check: build and compare with the checked-in file (exit 1 if different).

const Geo := preload("res://game/campaign/map_geo.gd")
const CData := preload("res://campaign/cdata.gd")

const OUT := "res://campaign/data/grid_data.gd"
const SEA := "."
const WILD := ","
var cell := 20
var w := 0
var h := 0
var reg: PackedInt32Array = []   # -1 sea, -2 wild, else region
var mass: PackedInt32Array = []  # landmass of land cells, -1 sea


func _init() -> void:
	var check := false
	var png := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cell="):
			cell = int(a.get_slice("=", 1))
		elif a == "--check":
			check = true
		elif a.begins_with("--png="):
			png = a.get_slice("=", 1)
	var text := build()
	if text == "":
		quit(1)
		return
	if check:
		var f := FileAccess.open(OUT, FileAccess.READ)
		var same := f != null and f.get_as_text() == text
		print("grid data %s the checked-in file" % ("matches" if same else "DIFFERS FROM"))
		quit(0 if same else 1)
		return
	var fo := FileAccess.open(OUT, FileAccess.WRITE)
	fo.store_string(text)
	fo.close()
	print("wrote ", OUT)
	if png != "":
		_png(png)
	quit(0)


## --png=path: the grid as a picture (4 px a cell; sea blue, unclaimed grey,
## regions in their palette hue, settlements white, ports cyan, camps red).
func _png(path: String) -> void:
	var s := 4
	var img := Image.create(w * s, h * s, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var v := reg[_idx(x, y)]
			var col := Color(0.15, 0.3, 0.45) if v == -1 else Color(0.5, 0.5, 0.5)
			if v >= 0:
				col = Color.from_hsv(fmod(v * 0.618, 1.0), 0.45, 0.85)
			img.fill_rect(Rect2i(x * s, y * s, s, s), col)
	var data := load(OUT)
	for r in CData.region_count():
		for pair in [[data.SITE[r], Color.WHITE], [data.PORT[r], Color.CYAN], [data.CAMP[r], Color.RED]]:
			var c := int(pair[0])
			if c >= 0:
				img.fill_rect(Rect2i(c % w * s, c / w * s, s, s), pair[1])
	img.save_png(path)
	print("wrote ", path)


func _idx(x: int, y: int) -> int:
	return y * w + x


func build() -> String:
	w = int(ceil(Geo.SIZE.x / cell))
	h = int(ceil(Geo.SIZE.y / cell))
	var n := w * h
	reg.resize(n)
	mass.resize(n)
	reg.fill(-1)
	mass.fill(-1)
	var lands: Array = Geo.lands()
	var nreg := CData.region_count()
	# Region polygons with bounding boxes for quick rejection.
	var polys: Array = []
	for r in nreg:
		for piece in Geo.cell(r):
			var bb := Rect2(piece[0], Vector2.ZERO)
			for p in piece:
				bb = bb.expand(p)
			polys.append([r, piece, bb])
	var land_bb: Array = []
	for l in lands:
		var bb := Rect2(l[0], Vector2.ZERO)
		for p in l:
			bb = bb.expand(p)
		land_bb.append(bb)
	for y in h:
		for x in w:
			var votes := {}
			var mvotes := {}
			var land_n := 0
			for sy in 3:
				for sx in 3:
					var p := Vector2((x + (sx + 0.5) / 3.0) * cell, (y + (sy + 0.5) / 3.0) * cell)
					var lm := -1
					for k in lands.size():
						if (land_bb[k] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, lands[k]):
							lm = k
							break
					if lm < 0:
						continue
					land_n += 1
					mvotes[lm] = int(mvotes.get(lm, 0)) + 1
					var rr := -2
					for pe in polys:
						if (pe[2] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, pe[1]):
							rr = int(pe[0])
							break
					votes[rr] = int(votes.get(rr, 0)) + 1
			if land_n < 2:
				continue
			var i := _idx(x, y)
			mass[i] = _argmax(mvotes)
			# A region needs at least one sample; wild only if no region sample.
			var best := -2
			var best_n := 0
			for rk in votes:
				if int(rk) >= 0 and (int(votes[rk]) > best_n or (int(votes[rk]) == best_n and int(rk) < best)):
					best = int(rk)
					best_n = int(votes[rk])
			if best >= 0 and int(CData.REGIONS[best]["land"]) != mass[i]:
				best = -2
			reg[i] = best
	# Every region has cells; settlements on their nearest cell.
	var sites: Array = []
	for r in nreg:
		var sp := Geo.site(r)
		var sx := clampi(int(sp.x / cell), 0, w - 1)
		var sy := clampi(int(sp.y / cell), 0, h - 1)
		var c := _nearest_of_region(r, sx, sy)
		if c < 0:
			printerr("region %s has no cell" % CData.REGIONS[r]["key"])
			return ""
		sites.append(c)
	# Corridors for land routes split across components.
	for guard in 4:
		var comp := _components()
		var fixed := 0
		for pair in CData.ROUTES:
			var a := CData.region_index(pair[0])
			var b := CData.region_index(pair[1])
			if comp[sites[a]] == comp[sites[b]]:
				continue
			fixed += _corridor(a, b, sites[a], sites[b])
			comp = _components()
		if fixed == 0:
			break
	var comp2 := _components()
	var ok := true
	for k in 5:
		var seen := {}
		for i in n:
			if reg[i] >= 0 and mass[i] == k:
				seen[comp2[i]] = 1
		if seen.size() != 1:
			printerr("landmass %d has %d components" % [k, seen.size()])
			ok = false
	for pair in CData.ROUTES:
		var a := CData.region_index(pair[0])
		var b := CData.region_index(pair[1])
		if comp2[sites[a]] != comp2[sites[b]]:
			printerr("route %s - %s not connected" % [pair[0], pair[1]])
			ok = false
	if not ok:
		return ""
	# Ports and camps.
	var ports: Array = []
	var camps: Array = []
	for r in nreg:
		var s: int = sites[r]
		ports.append(_port(r, s) if CData.is_port(r) else -1)
		camps.append(_camp(r, s))
	var counts: Array = []
	for r in nreg:
		var cnt := 0
		for i in n:
			if reg[i] == r:
				cnt += 1
		counts.append(cnt)
	print("grid %d x %d cells of %d px; land cells per region: %s" % [w, h, cell, str(counts)])
	return _emit(sites, ports, camps)


func _argmax(votes: Dictionary) -> int:
	var best := -1
	var bn := 0
	for k in votes:
		if int(votes[k]) > bn or (int(votes[k]) == bn and int(k) < best):
			best = int(k)
			bn = int(votes[k])
	return best


func _nearest_of_region(r: int, x: int, y: int) -> int:
	var best := -1
	var bd := 1 << 30
	for i in w * h:
		if reg[i] != r:
			continue
		var dx := i % w - x
		var dy := i / w - y
		var d := dx * dx + dy * dy
		if d < bd:
			bd = d
			best = i
	return best


## Same 8-connected step rule as campaign/cgrid.gd: both passable, same
## landmass; a diagonal needs one of its two orthogonal cells passable.
func _step_ok(a: int, b: int) -> bool:
	if reg[a] < 0 or reg[b] < 0 or mass[a] != mass[b]:
		return false
	var ax := a % w
	var ay := a / w
	var bx := b % w
	var by := b / w
	if ax != bx and ay != by:
		return reg[_idx(bx, ay)] >= 0 and mass[_idx(bx, ay)] == mass[a] \
			or reg[_idx(ax, by)] >= 0 and mass[_idx(ax, by)] == mass[a]
	return true


func _components() -> PackedInt32Array:
	var n := w * h
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var next := 0
	for s in n:
		if reg[s] < 0 or comp[s] >= 0:
			continue
		comp[s] = next
		var q: Array[int] = [s]
		var qi := 0
		while qi < q.size():
			var c := q[qi]
			qi += 1
			var cx := c % w
			var cy := c / w
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx := cx + dx
					var ny := cy + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var d := _idx(nx, ny)
					if comp[d] < 0 and _step_ok(c, d):
						comp[d] = next
						q.append(d)
		next += 1
	return comp


## Cells along the line from settlement a to b that are not passable get the
## nearer region (4-connected line, so no diagonal gaps).
func _corridor(a: int, b: int, ca: int, cb: int) -> int:
	var x0 := ca % w
	var y0 := ca / w
	var x1 := cb % w
	var y1 := cb / w
	var steps := maxi(absi(x1 - x0), absi(y1 - y0)) * 2 + 1
	var fixed := 0
	var land := int(CData.REGIONS[a]["land"])
	var py := y0
	for k in steps + 1:
		var x := x0 + (x1 - x0) * k / steps
		var y := y0 + (y1 - y0) * k / steps
		for c in [_idx(x, py), _idx(x, y)]:
			if reg[c] < 0 or mass[c] != land:
				var cx: int = c % w
				var cy: int = c / w
				var da := (cx - x0) * (cx - x0) + (cy - y0) * (cy - y0)
				var db := (cx - x1) * (cx - x1) + (cy - y1) * (cy - y1)
				reg[c] = a if da <= db else b
				mass[c] = land
				fixed += 1
		py = y
	if fixed > 0:
		print("corridor %s - %s: %d cells" % [CData.REGIONS[a]["key"], CData.REGIONS[b]["key"], fixed])
	return fixed


func _coastal(i: int) -> bool:
	var x := i % w
	var y := i / w
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx := x + dx
			var ny := y + dy
			if nx < 0 or ny < 0 or nx >= w or ny >= h or reg[_idx(nx, ny)] == -1:
				return true
	return false


func _port(r: int, s: int) -> int:
	var best := -1
	var bd := 1 << 30
	for i in w * h:
		if reg[i] != r or i == s or not _coastal(i):
			continue
		var dx := i % w - s % w
		var dy := i / w - s / w
		var d := dx * dx + dy * dy
		if d < bd:
			bd = d
			best = i
	if best < 0:
		best = s
	return best


func _camp(r: int, s: int) -> int:
	var sx := 0
	var sy := 0
	var cnt := 0
	for i in w * h:
		if reg[i] == r:
			sx += i % w
			sy += i / w
			cnt += 1
	var cxm := float(sx) / cnt
	var cym := float(sy) / cnt
	for min_d in [3, 2, 1]:
		var best := -1
		var bd := 1e9
		for i in w * h:
			if reg[i] != r:
				continue
			var cheb := maxi(absi(i % w - s % w), absi(i / w - s / w))
			if cheb < min_d:
				continue
			var d := (i % w - cxm) * (i % w - cxm) + (i / w - cym) * (i / w - cym) + cheb * 0.5
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			return best
	return s


func _char(v: int) -> String:
	if v == -1:
		return SEA
	if v == -2:
		return WILD
	return char(65 + v) if v < 26 else char(97 + v - 26)


func _emit(sites: Array, ports: Array, camps: Array) -> String:
	var lines: Array[String] = []
	lines.append("extends RefCounted")
	lines.append("## Campaign nav grid (state format 6). GENERATED by tools/campaign_grid.gd")
	lines.append("## from game/campaign/map_geo.gd: do not edit by hand; regenerate.")
	lines.append("## ROWS: one string per row, one character per cell: \".\" sea, \",\"")
	lines.append("## unclaimed land (impassable), \"A\"-\"Z\" regions 0-25, \"a\"-\"z\" 26-51 (CData")
	lines.append("## REGIONS order). SITE / PORT / CAMP: per region the cell index (y * W + x)")
	lines.append("## of its settlement, its port (-1 none) and a field cell away from the")
	lines.append("## settlement. OVERRIDES: [cell, cost] pairs (roads, fords: later).")
	lines.append("")
	lines.append("const CELL_PX := %d" % cell)
	lines.append("const W := %d" % w)
	lines.append("const H := %d" % h)
	lines.append("const SITE: Array[int] = %s" % str(sites))
	lines.append("const PORT: Array[int] = %s" % str(ports))
	lines.append("const CAMP: Array[int] = %s" % str(camps))
	lines.append("const OVERRIDES: Array[int] = []")
	lines.append("const ROWS: Array[String] = [")
	for y in h:
		var s := ""
		for x in w:
			s += _char(reg[_idx(x, y)])
		lines.append("\t\"%s\"," % s)
	lines.append("]")
	return "\n".join(lines) + "\n"
