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
## Roads, rivers and hills (2026-10-09, map_geo.gd ROADS / RIVERS / HILLS):
## per cell a terrain override (hill / ridge where a hill area is rougher
## than the region's own terrain) and a road flag (every cell a road line
## runs through, 4-connected); rivers as edges: a step between two passable
## cells whose centres a river line separates is a river edge (a diagonal
## also when any orthogonal step of its 2 x 2 block is one), except at the
## crossings: each authored crossing takes its river's orthogonal step
## nearest its point (a road's step there first). Checks (the build fails):
## a river mouth reaches a sea cell (a tributary its river), every crossing
## joins two passable cells of one landmass, river edges only between
## passable cells, every road cell on land, a road crossing a river only at
## a crossing, each landmass still one component and every land route
## joined with the rivers in place.
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
var terr: PackedByteArray = []   # terrain override: 0 none, 1 hill, 2 ridge
var road: PackedByteArray = []   # 1 road cell
var rmask: PackedInt32Array = [] # per cell: bit k = the step in direction k crosses a river
var cross: Array = []            # [a, b, id, kind] (a < b, orthogonal neighbours)
var _cross_key := {}             # a * n + b -> crossing id (both orders)
const DX: Array[int] = [0, 1, 1, 1, 0, -1, -1, -1]
const DY: Array[int] = [-1, -1, 0, 1, 1, 1, 0, -1]


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
		if png != "" and rmask.size() == w * h:
			_png(png)  # what was built so far, to see what failed
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
	var s := 8
	var img := Image.create(w * s, h * s, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var v := reg[_idx(x, y)]
			var col := Color(0.15, 0.3, 0.45) if v == -1 else Color(0.5, 0.5, 0.5)
			if v >= 0:
				col = Color.from_hsv(fmod(v * 0.618, 1.0), 0.45, 0.85)
			img.fill_rect(Rect2i(x * s, y * s, s, s), col)
	for i in w * h:
		var px0 := Vector2i(i % w * s, i / w * s)
		if terr[i] > 0:
			for k in s:
				if (k % 2) == 0:
					img.set_pixel(px0.x + k, px0.y + k, Color(0.25, 0.2, 0.1) if terr[i] == 1 else Color(0, 0, 0))
		if road[i] != 0:
			img.fill_rect(Rect2i(px0 + Vector2i(s / 2 - 1, s / 2 - 1), Vector2i(2, 2)), Color(0.95, 0.85, 0.3))
		if rmask[i] & 4 != 0:
			img.fill_rect(Rect2i(px0.x + s - 1, px0.y, 1, s), Color(0.1, 0.3, 1.0))
		if rmask[i] & 16 != 0:
			img.fill_rect(Rect2i(px0.x, px0.y + s - 1, s, 1), Color(0.1, 0.3, 1.0))
	for cr in cross:
		var a: int = cr[0]
		var b: int = cr[1]
		var col := Color(1, 0.2, 0.2) if int(cr[3]) == 0 else Color(0.2, 1, 0.2)
		var mid := (Vector2(a % w, a / w) + Vector2(b % w, b / w) + Vector2.ONE) * 0.5 * s
		img.fill_rect(Rect2i(Vector2i(mid) - Vector2i(1, 1), Vector2i(3, 3)), col)
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
	if not _terrain():
		return ""
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
	lines.append("## settlement. OVERRIDES: [cell, cost] pairs (a cost set directly; applied last).")
	lines.append("## TERRAIN: one string per row: \".\" the region's own terrain, \"h\" hill,")
	lines.append("## \"r\" ridge; upper case (\"=\" on the region's terrain, \"H\", \"R\"): also a")
	lines.append("## road cell. RIVER: [cell, mask] pairs, bit k of mask (directions N, NE,")
	lines.append("## E, SE, S, SW, W, NW) set when that step crosses a river. CROSS: [cell a,")
	lines.append("## cell b, crossing id (map_geo.gd crossings()), kind (0 ford, 1 bridge)]")
	lines.append("## per crossing: the river step a <-> b that may be taken.")
	lines.append("")
	lines.append("const CELL_PX := %d" % cell)
	lines.append("const W := %d" % w)
	lines.append("const H := %d" % h)
	lines.append("const SITE: Array[int] = %s" % str(sites))
	lines.append("const PORT: Array[int] = %s" % str(ports))
	lines.append("const CAMP: Array[int] = %s" % str(camps))
	lines.append("const OVERRIDES: Array[int] = []")
	var rv: Array[String] = []
	for i in w * h:
		if rmask[i] != 0:
			rv.append("%d, %d" % [i, rmask[i]])
	lines.append("const RIVER: Array[int] = [%s]" % ", ".join(rv))
	var cv: Array[String] = []
	for cr in cross:
		cv.append("%d, %d, %d, %d" % cr)
	lines.append("const CROSS: Array[int] = [%s]" % ", ".join(cv))
	lines.append("const TERRAIN: Array[String] = [")
	for y in h:
		var t := ""
		for x in w:
			var i := _idx(x, y)
			t += (".hr" if road[i] == 0 else "=HR")[terr[i]]
		lines.append("\t\"%s\"," % t)
	lines.append("]")
	lines.append("const ROWS: Array[String] = [")
	for y in h:
		var s := ""
		for x in w:
			s += _char(reg[_idx(x, y)])
		lines.append("\t\"%s\"," % s)
	lines.append("]")
	return "\n".join(lines) + "\n"


# ------------------------------------------------- roads, rivers, hills ---

func _centre(i: int) -> Vector2:
	return Vector2((i % w + 0.5) * cell, (i / w + 0.5) * cell)


func _pass(i: int) -> bool:
	return i >= 0 and reg[i] >= 0


## Terrain overrides, roads, river edges and crossings, with their checks.
func _terrain() -> bool:
	var n := w * h
	var ok := true
	terr.resize(n)
	terr.fill(0)
	road.resize(n)
	road.fill(0)
	rmask.resize(n)
	rmask.fill(0)
	cross = []
	_cross_key = {}
	# Hills.
	var areas: Array = []  # [kind 1 / 2, poly or line, half width px]
	for hl in Geo.HILLS:
		var kind := 1 + int(hl["kind"])
		if hl.has("poly"):
			areas.append([kind, Geo._poly(hl["poly"]), -1.0])
		else:
			areas.append([kind, Geo._poly(hl["pts"]), float(hl["w"]) * Geo.PX_LAT])
	var nh := [0, 0, 0]
	for i in n:
		if reg[i] < 0:
			continue
		var p := _centre(i)
		var best := 0
		for ar in areas:
			var k: int = ar[0]
			if k <= best:
				continue
			var line: PackedVector2Array = ar[1]
			var hit := false
			if float(ar[2]) < 0.0:
				hit = Geometry2D.is_point_in_polygon(p, line)
			else:
				for s2 in line.size() - 1:
					if p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[s2], line[s2 + 1])) <= float(ar[2]):
						hit = true
						break
			if hit:
				best = k
		if best == 0:
			continue
		var kind_t: int = CData.HILL if best == 1 else CData.RIDGE
		var own := int(CData.REGIONS[reg[i]]["terrain"])
		if int(CData.GRID_COST[kind_t]) > int(CData.GRID_COST.get(own, 10)):
			terr[i] = best
			nh[best] += 1
	# Roads.
	var chains: Array = []
	var nroad := 0
	for ri in Geo.ROADS.size():
		var cs := Geo.line_cells(Geo.road_line(ri), float(cell), w, h)
		chains.append(cs)
		for c in cs:
			if reg[c] == -1:
				printerr("road %s: cell (%d, %d) is sea" % [Geo.ROADS[ri][0], c % w, c / w])
				ok = false
			elif reg[c] >= 0 and road[c] == 0:
				road[c] = 1
				nroad += 1
	# Rivers: lines run on to the sea (or across the river they join).
	var lines: Array = []
	for vi in Geo.RIVERS.size():
		var line := Geo.river_line(vi)
		var into := int(Geo.RIVERS[vi]["into"])
		var d := (line[line.size() - 1] - line[line.size() - 2]).normalized()
		var p := line[line.size() - 1]
		var done := false
		for k in 60:
			if into < 0:
				var x := int(p.x / cell)
				var y := int(p.y / cell)
				if x < 0 or y < 0 or x >= w or y >= h or reg[_idx(x, y)] == -1:
					done = true
			else:
				var other: PackedVector2Array = lines[into] if into < lines.size() else Geo.river_line(into)
				for s3 in other.size() - 1:
					if Geometry2D.segment_intersects_segment(line[line.size() - 1], p, other[s3], other[s3 + 1]) != null:
						done = true
						break
			if done:
				line.append(p + d * cell * 0.5)
				break
			p += d * 5.0
		if not done:
			printerr("river %s: its mouth reaches no sea cell" % Geo.RIVERS[vi]["name"])
			ok = false
		lines.append(line)
	var bbs: Array = []
	for line in lines:
		var bb := Rect2(line[0], Vector2.ZERO)
		for q in line:
			bb = bb.expand(q)
		bbs.append(bb.grow(2.0))
	# Orthogonal edges (every pair on the grid): river index or -1.
	var e_east := PackedInt32Array()
	var e_south := PackedInt32Array()
	e_east.resize(n)
	e_south.resize(n)
	e_east.fill(-1)
	e_south.fill(-1)
	for i in n:
		var x := i % w
		var y := i / w
		if x + 1 < w:
			e_east[i] = _river_between(_centre(i), _centre(i + 1), lines, bbs)
		if y + 1 < h:
			e_south[i] = _river_between(_centre(i), _centre(i + w), lines, bbs)
	# Crossings.
	var road_step := {}  # a * n + b (a < b) -> 1: a step of a road chain
	for cs in chains:
		for k in range(1, cs.size()):
			var a := mini(cs[k - 1], cs[k])
			var b := maxi(cs[k - 1], cs[k])
			road_step[a * n + b] = 1
	var cid := 0
	for vi in Geo.RIVERS.size():
		for cr in Geo.RIVERS[vi]["cross"]:
			var p := Geo.project(float(cr[2]), float(cr[3]))
			var best := -1
			var bd := INF
			for pass_road in [true, false]:
				for i in n:
					for dk in 2:
						var j := i + 1 if dk == 0 else i + w
						var rv := e_east[i] if dk == 0 else e_south[i]
						if rv != vi or not _pass(i) or not _pass(j) or mass[i] != mass[j]:
							continue
						if pass_road and not road_step.has(i * n + j):
							continue
						if _cross_key.has(i * n + j):
							continue
						var dd := (_centre(i) + _centre(j)) * 0.5 - p
						var dist := dd.length()
						if dist > (2.0 if pass_road else 2.5) * cell:
							continue
						if dist < bd - 0.001:
							bd = dist
							best = i * n + j
				if best >= 0:
					break
			if best < 0:
				printerr("crossing %s (%s): no river step near it" % [cr[0], Geo.RIVERS[vi]["name"]])
				ok = false
			else:
				var a2 := best / n
				var b2 := best % n
				cross.append([a2, b2, cid, int(cr[1])])
				_cross_key[a2 * n + b2] = cid
				_cross_key[b2 * n + a2] = cid
			cid += 1
	# The mask (passable pairs of one landmass only).
	var nedge := 0
	for i in n:
		if reg[i] < 0:
			continue
		var x := i % w
		var y := i / w
		for k in 8:
			var nx := x + DX[k]
			var ny := y + DY[k]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var j := _idx(nx, ny)
			if reg[j] < 0 or mass[j] != mass[i]:
				continue
			var hit := false
			if k % 2 == 0:
				hit = _orth(i, j, e_east, e_south) >= 0
			else:
				# Diagonal: its own line, or any orthogonal step of the 2 x 2.
				var o1 := _idx(nx, y)
				var o2 := _idx(x, ny)
				hit = _river_between(_centre(i), _centre(j), lines, bbs) >= 0 \
					or _orth(i, o1, e_east, e_south) >= 0 or _orth(o1, j, e_east, e_south) >= 0 \
					or _orth(i, o2, e_east, e_south) >= 0 or _orth(o2, j, e_east, e_south) >= 0
			if hit:
				rmask[i] |= 1 << k
				nedge += 1
	# Checks.
	for cr in cross:
		var a3: int = cr[0]
		var b3: int = cr[1]
		if not _pass(a3) or not _pass(b3) or mass[a3] != mass[b3] or absi(a3 - b3) != 1 and absi(a3 - b3) != w:
			printerr("crossing %d does not join two passable cells of one landmass" % int(cr[2]))
			ok = false
	for ri in chains.size():
		var cs: PackedInt32Array = chains[ri]
		for k in range(1, cs.size()):
			var a4 := cs[k - 1]
			var b4 := cs[k]
			if _pass(a4) and _pass(b4) and mass[a4] == mass[b4] and _orth(a4, b4, e_east, e_south) >= 0 \
					and not _cross_key.has(a4 * n + b4):
				printerr("road %s crosses the %s at (%d, %d) - (%d, %d) without a crossing" % [Geo.ROADS[ri][0],
					Geo.RIVERS[_orth(a4, b4, e_east, e_south)]["name"], a4 % w, a4 / w, b4 % w, b4 / w])
				ok = false
	var comp := _components_rivers()
	for k in 5:
		var seen := {}
		for i in n:
			if reg[i] >= 0 and mass[i] == k:
				seen[comp[i]] = 1
		if seen.size() != 1:
			var sizes := {}
			for i in n:
				if reg[i] >= 0 and mass[i] == k:
					if not sizes.has(comp[i]):
						sizes[comp[i]] = [0, i % w, i / w]
					sizes[comp[i]][0] += 1
			printerr("landmass %d has %d components with the rivers: [cells, x, y] %s" % [k, seen.size(), str(sizes.values())])
			ok = false
	print("terrain: %d hill, %d ridge override cells; %d road cells on %d roads; %d river steps (%d mask bits), %d crossings" % [
		nh[1], nh[2], nroad, chains.size(), nedge / 2, nedge, cross.size()])
	return ok


## River index whose line separates points a and b (the first by index), -1.
func _river_between(a: Vector2, b: Vector2, lines: Array, bbs: Array) -> int:
	var sb := Rect2(a, Vector2.ZERO).expand(b)
	for vi in lines.size():
		if not (bbs[vi] as Rect2).intersects(sb):
			continue
		var line: PackedVector2Array = lines[vi]
		for k in line.size() - 1:
			if Geometry2D.segment_intersects_segment(a, b, line[k], line[k + 1]) != null:
				return vi
	return -1


## River on the orthogonal step a <-> b (-1 none).
func _orth(a: int, b: int, e_east: PackedInt32Array, e_south: PackedInt32Array) -> int:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	return e_east[lo] if hi - lo == 1 else e_south[lo]


## Components over passable cells with the river edges (crossings open).
func _components_rivers() -> PackedInt32Array:
	var n := w * h
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var next := 0
	for s0 in n:
		if reg[s0] < 0 or comp[s0] >= 0:
			continue
		comp[s0] = next
		var q: Array[int] = [s0]
		var qi := 0
		while qi < q.size():
			var c := q[qi]
			qi += 1
			for k in 8:
				var nx := c % w + DX[k]
				var ny := c / w + DY[k]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var d := _idx(nx, ny)
				if comp[d] >= 0 or not _step_ok(c, d):
					continue
				if rmask[c] & (1 << k) != 0 and not _cross_key.has(c * n + d):
					continue
				comp[d] = next
				q.append(d)
		next += 1
	return comp
