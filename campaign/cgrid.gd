extends RefCounted
## The campaign nav grid (state format 6, the continuous overworld): static
## data generated from the map (the active pack's CData.GRID; Rome:
## campaign/data/grid_data.gd, written by
## tools/campaign_grid.gd) plus the searches the rules, the AI and the view
## share. Pure data and integer maths: no state, no Nodes, deterministic
## (fixed neighbour order, ties by cell index).
##
## A cell is an int index y * W + x; cells are square on the map (CELL_PX
## map pixels; the map view draws cell c at (x + 0.5, y + 0.5) * CELL_PX).
## Per cell: the region it belongs to (-1 sea, -2 unclaimed land: both
## impassable), its landmass, its terrain kind (the region's, or the
## grid's hill / ridge override) and its movement cost (CData.GRID_COST by
## that kind, + GRID_WOODS in heavy woods; a road cell GRID_ROAD, never more
## than its terrain; OVERRIDES set a cost directly, last). Steps are
## 8-connected within one landmass; a diagonal costs 14/10 of the cell it
## enters and needs one of its two orthogonal cells passable (no squeezing
## through a corner). Rivers (roads, rivers and hills, 2026-10-09): a step
## across a river edge (the grid's RIVER masks) is impossible, except the
## crossings' steps (CROSS): a ford costs the cell entered + GRID_FORD, a
## bridge just the cell; a diagonal across a river is never a step (the
## grid tool marks it). Sea lanes join the port cells of CData.SEA_LANES
## (embark with full points, using them all); not in a pack with ships
## (CData.ships_on: armies cross on fleets, campaign/cfleet.gd).
##
## Searches use g = turn * full + (full - points left), which orders
## positions by (turn reached, most points left): exactly the movement rule
## (a step that costs more than the points left waits for the next turn).

const CData := preload("res://campaign/cdata.gd")

const INF := 1 << 30
## Neighbour order (fixed): N, NE, E, SE, S, SW, W, NW.
const DX: Array[int] = [0, 1, 1, 1, 0, -1, -1, -1]
const DY: Array[int] = [-1, -1, 0, 1, 1, 1, 0, -1]

static var _n := 0
static var _reg: PackedInt32Array = []
static var _mass: PackedInt32Array = []
static var _cost: PackedInt32Array = []
static var _nb: PackedInt32Array = []    # n * 8: neighbour cell or -1
static var _nbc: PackedInt32Array = []   # n * 8: step cost
static var _links := {}                  # port cell -> Array of [cell, region]
static var _cells: Array = []            # per region: PackedInt32Array of its cells
static var _terr: PackedInt32Array = []  # terrain kind per cell (-1 impassable)
static var _ovr: PackedByteArray = []    # 1: the kind is the grid's hill / ridge override
static var _road: PackedByteArray = []   # 1: a road cell
static var _rmask: PackedInt32Array = [] # bit k: the step in direction k crosses a river
static var _cross := {}                  # a * n + b (both orders) -> crossing id
static var _cross_list: Array = []       # per crossing id: [a, b, kind]
static var _fields := {}                 # memo: static distance fields
static var last_nodes := 0
## The active pack's grid (CData.GRID): size, cell size and the settlement,
## port and camp cells per region, set by pack_reset() (at load and on a
## pack switch); the derived tables above are rebuilt by ensure().
static var _gw := 0
static var _gh := 0
static var _cpx := 0
static var _site: Array[int] = []
static var _port: Array[int] = []
# Water-extended steps for amphibious armies (2026-10-23): _wet marks the
# coastal sea cells (set by CFleet.ensure), _nbw / _nbcw the neighbour tables
# with the steps between land and those cells. Built on first use.
static var _wet := PackedByteArray()
static var _nbw := PackedInt32Array()
static var _nbcw := PackedInt32Array()
const WATER_STEP := 10
static var _camp: Array[int] = []


static func _static_init() -> void:
	pack_reset()


## The pack changed (CData.use_pack_script; also at load): read the active
## grid's sizes and drop every table built from the previous one.
static func pack_reset() -> void:
	var d := CData.GRID.get_script_constant_map()
	_gw = int(d["W"])
	_gh = int(d["H"])
	_cpx = int(d["CELL_PX"])
	_site = d["SITE"]
	_port = d["PORT"]
	_camp = d["CAMP"]
	_n = 0
	_reg = PackedInt32Array()
	_mass = PackedInt32Array()
	_cost = PackedInt32Array()
	_nb = PackedInt32Array()
	_nbc = PackedInt32Array()
	_wet = PackedByteArray()
	_nbw = PackedInt32Array()
	_nbcw = PackedInt32Array()
	_links = {}
	_cells = []
	_terr = PackedInt32Array()
	_ovr = PackedByteArray()
	_road = PackedByteArray()
	_rmask = PackedInt32Array()
	_cross = {}
	_cross_list = []
	_fields = {}


static func ensure() -> void:
	if _n > 0:
		return
	var gd := CData.GRID.get_script_constant_map()
	var w := _gw
	var h := _gh
	var n := w * h
	_reg.resize(n)
	_mass.resize(n)
	_cost.resize(n)
	_terr.resize(n)
	_terr.fill(-1)
	_ovr.resize(n)
	_ovr.fill(0)
	_road.resize(n)
	_road.fill(0)
	_rmask.resize(n)
	_rmask.fill(0)
	var nreg := CData.region_count()
	var per: Array = []
	for r in nreg:
		per.append([])
	for y in h:
		var row: String = gd["ROWS"][y]
		var trow: String = gd["TERRAIN"][y]
		for x in w:
			var i := y * w + x
			var ch := row.unicode_at(x)
			var r := -1
			if ch == 44:  # ","
				r = -2
			elif ch >= 65 and ch <= 90:
				r = ch - 65
			elif ch >= 97 and ch <= 122:
				r = ch - 97 + 26
			_reg[i] = r
			_mass[i] = int(CData.REGIONS[r]["land"]) if r >= 0 else -1
			_cost[i] = _region_cost(r) if r >= 0 else 0
			if r >= 0:
				(per[r] as Array).append(i)
				_terr[i] = int(CData.REGIONS[r]["terrain"])
				# "." own terrain, "h" hill, "r" ridge; upper case also a road.
				var tc := trow.unicode_at(x)
				var kind := -1
				if tc == 104 or tc == 72:  # h H
					kind = CData.HILL
				elif tc == 114 or tc == 82:  # r R
					kind = CData.RIDGE
				if kind >= 0:
					_terr[i] = kind
					_ovr[i] = 1
					_cost[i] = int(CData.GRID_COST[kind]) + (CData.GRID_WOODS if int(CData.REGIONS[r]["forest"]) >= CData.WOODS_HEAVY else 0)
				if tc == 61 or tc == 72 or tc == 82:  # = H R
					_road[i] = 1
					_cost[i] = mini(_cost[i], CData.GRID_ROAD)
	for r in nreg:
		_cells.append(PackedInt32Array(per[r]))
	for k in range(0, gd["OVERRIDES"].size(), 2):
		var c := int(gd["OVERRIDES"][k])
		if _reg[c] >= 0:
			_cost[c] = int(gd["OVERRIDES"][k + 1])
	for k in range(0, gd["RIVER"].size(), 2):
		_rmask[int(gd["RIVER"][k])] = int(gd["RIVER"][k + 1])
	_cross = {}
	_cross_list = []
	for k in range(0, gd["CROSS"].size(), 4):
		var a := int(gd["CROSS"][k])
		var b := int(gd["CROSS"][k + 1])
		var id := int(gd["CROSS"][k + 2])
		_cross[a * n + b] = id
		_cross[b * n + a] = id
		while _cross_list.size() <= id:
			_cross_list.append([])
		_cross_list[id] = [a, b, int(gd["CROSS"][k + 3])]
	_nb.resize(n * 8)
	_nbc.resize(n * 8)
	_nb.fill(-1)
	_nbc.fill(0)
	for i in n:
		if _reg[i] < 0:
			continue
		var x := i % w
		var y := i / w
		for k in 8:
			var nx := x + DX[k]
			var ny := y + DY[k]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var j := ny * w + nx
			if _reg[j] < 0 or _mass[j] != _mass[i]:
				continue
			var extra := 0
			if _rmask[i] & (1 << k) != 0:
				# A river: only at a crossing (never a diagonal).
				var cid := int(_cross.get(i * n + j, -1))
				if cid < 0 or k % 2 == 1:
					continue
				if int(_cross_list[cid][2]) == CData.CROSS_FORD:
					extra = CData.GRID_FORD
			if k % 2 == 1:
				var oa := y * w + nx
				var ob := ny * w + x
				if not ((_reg[oa] >= 0 and _mass[oa] == _mass[i]) or (_reg[ob] >= 0 and _mass[ob] == _mass[i])):
					continue
				_nbc[i * 8 + k] = _cost[j] * 14 / 10
			else:
				_nbc[i * 8 + k] = _cost[j] + extra
			_nb[i * 8 + k] = j
	# A pack with ships (CData.ships_on) has no sea lanes for armies: they
	# cross on fleets (campaign/cfleet.gd).
	# (R2: the Rome pack keeps them, its SHIPS constant LANES_FOR_ARMIES.)
	var lanes_armies := not CData.ships_on() or int(CData.ship_const("LANES_FOR_ARMIES", 0)) != 0
	for pair in (CData.SEA_LANES if lanes_armies else []):
		var a := CData.region_index(pair[0])
		var b := CData.region_index(pair[1])
		_link(port(a), port(b), b)
		_link(port(b), port(a), a)
	_n = n


static func _region_cost(r: int) -> int:
	var c := int(CData.GRID_COST.get(int(CData.REGIONS[r]["terrain"]), 10))
	if int(CData.REGIONS[r]["forest"]) >= CData.WOODS_HEAVY:
		c += CData.GRID_WOODS
	return c


static func _link(a: int, b: int, rb: int) -> void:
	if not _links.has(a):
		_links[a] = []
	(_links[a] as Array).append([b, rb])


# --------------------------------------------------------------- lookups ---

static func width() -> int:
	return _gw


static func height() -> int:
	return _gh


static func count() -> int:
	ensure()
	return _n


static func cell_px() -> int:
	return _cpx


static func cx(c: int) -> int:
	return c % _gw


static func cy(c: int) -> int:
	return c / _gw


## Cell at (x, y), -1 outside the grid.
static func at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= _gw or y >= _gh:
		return -1
	return y * _gw + x


## Region of cell c (-1 sea, -2 unclaimed land).
static func region(c: int) -> int:
	ensure()
	return _reg[c] if c >= 0 and c < _n else -1


static func passable(c: int) -> bool:
	ensure()
	return c >= 0 and c < _n and _reg[c] >= 0


static func cost(c: int) -> int:
	ensure()
	return _cost[c]


## Terrain kind of cell c (a sim/terrain.gd kind: the region's own, or the
## grid's hill / ridge override), -1 for the sea and unclaimed land.
static func cell_terrain(c: int) -> int:
	ensure()
	return _terr[c] if c >= 0 and c < _n else -1


## The grid's hill / ridge override of cell c (a terrain kind), -1 none.
static func terrain_override(c: int) -> int:
	ensure()
	return _terr[c] if c >= 0 and c < _n and _ovr[c] != 0 else -1


static func is_road(c: int) -> bool:
	ensure()
	return c >= 0 and c < _n and _road[c] != 0


## River mask of cell c: bit k set when the step in direction k (N, NE, E,
## SE, S, SW, W, NW) crosses a river (crossing or not).
static func river_mask(c: int) -> int:
	ensure()
	return _rmask[c] if c >= 0 and c < _n else 0


## The crossing whose step joins cells a and b (either way round), -1 none.
static func crossing_at(a: int, b: int) -> int:
	ensure()
	if a < 0 or b < 0 or a >= _n or b >= _n:
		return -1
	return int(_cross.get(a * _n + b, -1))


static func crossing_count() -> int:
	ensure()
	return _cross_list.size()


## Crossing id's [cell a, cell b, kind (CData.CROSS_FORD / CROSS_BRIDGE)].
static func crossing(id: int) -> Array:
	ensure()
	return _cross_list[id]


## Crossings with a step from cell c: [[id, other cell], ...] (id order).
static func crossings_from(c: int) -> Array:
	ensure()
	var out: Array = []
	if c < 0 or c >= _n or _rmask[c] == 0:
		return out
	for id in _cross_list.size():
		var cr: Array = _cross_list[id]
		if int(cr[0]) == c:
			out.append([id, int(cr[1])])
		elif int(cr[1]) == c:
			out.append([id, int(cr[0])])
	return out


static func site(r: int) -> int:
	return _site[r]


static func port(r: int) -> int:
	return _port[r]


static func camp(r: int) -> int:
	return _camp[r]


## Region r's cells (index order).
static func cells_of(r: int) -> PackedInt32Array:
	ensure()
	return _cells[r]


## Sea lane destinations from cell c: [[cell, region], ...] (only port cells).
static func links(c: int) -> Array:
	ensure()
	return _links.get(c, [])


## The settlement region whose cell c is, else -1.
static func site_region(c: int) -> int:
	var r := region(c)
	if r >= 0 and site(r) == c:
		return r
	return -1


## Chebyshev distance (0 the same cell, 1 next to it: "the ring").
static func cheb(a: int, b: int) -> int:
	return maxi(absi(a % _gw - b % _gw), absi(a / _gw - b / _gw))


static func d2(a: int, b: int) -> int:
	var dx := a % _gw - b % _gw
	var dy := a / _gw - b / _gw
	return dx * dx + dy * dy


## Cell b lies within the circle of radius rad around a (dx^2 + dy^2 <=
## rad^2 + rad: radius 2 is the 5 x 5 square without its corners).
static func within(a: int, b: int, rad: int) -> bool:
	return d2(a, b) <= rad * rad + rad


## Cells within radius rad of c (index order, passable or not, on the grid).
static func disc(c: int, rad: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var x0 := c % _gw
	var y0 := c / _gw
	for dy in range(-rad, rad + 1):
		for dx in range(-rad, rad + 1):
			if dx * dx + dy * dy > rad * rad + rad:
				continue
			var j := at(x0 + dx, y0 + dy)
			if j >= 0:
				out.append(j)
	out.sort()
	return out


## Octile distance in tenths of a straight step (10 straight, 14 diagonal).
static func octile(a: int, b: int) -> int:
	var dx := absi(a % _gw - b % _gw)
	var dy := absi(a / _gw - b / _gw)
	return 10 * maxi(dx, dy) + 4 * mini(dx, dy)


## Compass sector (0 N, 1 NE ... 7 NW) of cell `from` seen from cell `at_c`
## (north is up on the map), -1 for the same cell.
static func sector(at_c: int, from: int) -> int:
	var dx := from % _gw - at_c % _gw
	var dy := at_c / _gw - from / _gw  # north positive
	if dx == 0 and dy == 0:
		return -1
	var ax := absi(dx)
	var ay := absi(dy)
	if ay * 1000 >= ax * 2414:
		return 0 if dy > 0 else 4
	if ax * 1000 >= ay * 2414:
		return 2 if dx > 0 else 6
	if dx > 0:
		return 1 if dy > 0 else 3
	return 7 if dy > 0 else 5


## Step cost from cell a to its neighbour b (0 if not a step).
static func step_cost(a: int, b: int) -> int:
	ensure()
	for k in 8:
		if _nb[a * 8 + k] == b:
			return _nbc[a * 8 + k]
	return 0


## CFleet.ensure hands over the coastal sea cells (1 = an open-sea cell within
## one cell of land) the amphibious armies may paddle on.
static func set_wet(mask: PackedByteArray) -> void:
	_wet = mask
	_nbw = PackedInt32Array()
	_nbcw = PackedInt32Array()


## Cell c is coastal water an amphibious army may stand on.
static func is_wet(c: int) -> bool:
	return c >= 0 and c < _wet.size() and _wet[c] != 0


## The neighbour tables with the water steps (the land ones plus every step
## between a land cell and a wet cell, or two wet cells: WATER_STEP a straight
## step, a diagonal x 14 / 10; a landing costs the land cell's own cost).
## Without wet cells (a pack with no ships) the land tables.
static func _water_tables() -> void:
	ensure()
	if not _nbw.is_empty() or _wet.size() != _n:
		return
	var w := _gw
	_nbw = _nb.duplicate()
	_nbcw = _nbc.duplicate()
	for i in _n:
		var iw := _wet[i] != 0
		if not iw and _reg[i] < 0:
			continue
		var x := i % w
		var y := i / w
		for k in 8:
			var nx := x + DX[k]
			var ny := y + DY[k]
			if nx < 0 or ny < 0 or nx >= w or ny >= _gh:
				continue
			var j := ny * w + nx
			var jw := _wet[j] != 0
			if not iw and not jw:
				continue
			if not jw and _reg[j] < 0:
				continue
			if k % 2 == 1:
				var oa := y * w + nx
				var ob := ny * w + x
				if _wet[oa] == 0 and _wet[ob] == 0:
					continue
			var base := WATER_STEP if jw else _cost[j]
			_nbw[i * 8 + k] = j
			_nbcw[i * 8 + k] = base * 14 / 10 if k % 2 == 1 else base


## True when the water tables exist (a pack with ships).
static func has_water() -> bool:
	_water_tables()
	return not _nbw.is_empty()


## Step cost from a to its neighbour b with the water steps (0 if not a step).
static func step_cost_w(a: int, b: int) -> int:
	_water_tables()
	if _nbw.is_empty():
		return step_cost(a, b)
	for k in 8:
		if _nbw[a * 8 + k] == b:
			return _nbcw[a * 8 + k]
	return 0


# --------------------------------------------------------------- searches ---

## Cheapest path for an army with `full` points a turn and `mp` left now
## from `start` to `goal` (adjacent: stop on the first cell next to goal,
## the ring of a settlement or an army). block: PackedByteArray (1 = may not
## enter; the goal itself is never entered when adjacent), or empty; zone:
## PackedInt32Array (> 0 = may not enter either: zones of control), or empty. A* on
## g = turn * full + (full - points left) with the octile heuristic, ties by
## cell index; sea lanes from port cells (full points, all used). Returns
## {"path": [cells after start], "t": [turn each is reached], "m": [points
## left there]} or {} (no path within max_turns or max_nodes expansions).
static func find_path(start: int, goal: int, full: int, mp: int, block: PackedByteArray,
		zone: PackedInt32Array = PackedInt32Array(), adjacent: bool = false, max_turns: int = 12,
		max_nodes: int = 6000, water: bool = false) -> Dictionary:
	var res := _find_cheapest(start, goal, full, mp, block, zone, adjacent, max_turns, max_nodes, water)
	if water or not detour_rule or res.is_empty() or (res["path"] as Array).size() < 3:
		return res
	return _limit_detour(res, start, goal, full, mp, block, zone, adjacent, max_nodes)


## The cheapest path (A* on the g above), whatever its shape.
static func _find_cheapest(start: int, goal: int, full: int, mp: int, block: PackedByteArray,
		zone: PackedInt32Array, adjacent: bool, max_turns: int, max_nodes: int, water: bool = false) -> Dictionary:
	ensure()
	if water:
		_water_tables()
		water = not _nbw.is_empty()
	if start < 0 or goal < 0 or full <= 0:
		return {}
	if (adjacent and cheb(start, goal) <= 1) or (not adjacent and start == goal):
		return {"path": [], "t": [], "m": []}
	var n := _n
	var w := _gw
	var nb := _nbw if water else _nb
	var nbc := _nbcw if water else _nbc
	var g := PackedInt32Array()
	g.resize(n)
	g.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var hv := PackedInt32Array()  # heuristic per cell (-1: not yet)
	hv.resize(n)
	hv.fill(-1)
	var has_block := block.size() == n
	var has_zone := zone.size() == n
	var gx := goal % w
	var gy := goal / w
	var m0 := clampi(mp, 0, full)
	g[start] = full - m0
	var heap: Array[int] = []
	hv[start] = _h(start, gx, gy, w)
	_push(heap, (g[start] + hv[start]) * 65536 + start)
	var found := -1
	var nodes := 0
	var cap := max_turns * full + full
	while not heap.is_empty():
		var top := _pop(heap)
		var u := top & 65535
		var gu := g[u]
		if top >> 16 != gu + hv[u]:
			continue  # stale entry
		var ux := u % w
		var uy := u / w
		if adjacent:
			if absi(ux - gx) <= 1 and absi(uy - gy) <= 1:
				found = u
				break
		elif u == goal:
			found = u
			break
		nodes += 1
		if nodes > max_nodes or gu > cap:
			break
		var t := gu / full
		var left := full - (gu - t * full)
		if gu > 0 and gu % full == 0:
			# Exactly out of points at the end of turn t - 1: same as turn t
			# with nothing left.
			t = gu / full - 1
			left = 0
		var base := u * 8
		for k in 8:
			var v := nb[base + k]
			if v < 0 or (has_block and block[v] != 0) or (has_zone and zone[v] > 0):
				continue
			if adjacent and v == goal:
				continue
			var c := nbc[base + k]
			var ng := gu + c if left >= c else (t + 1) * full + c
			if ng < g[v]:
				g[v] = ng
				prev[v] = u
				if hv[v] < 0:
					hv[v] = _h(v, gx, gy, w)
				_push(heap, (ng + hv[v]) * 65536 + v)
		if _links.has(u):
			for ln in _links[u]:
				var v2 := int(ln[0])
				if (has_block and block[v2] != 0) or (has_zone and zone[v2] > 0):
					continue
				var ng2 := t * full + full if left == full else (t + 1) * full + full
				if ng2 < g[v2]:
					g[v2] = ng2
					prev[v2] = u
					if hv[v2] < 0:
						hv[v2] = _h(v2, gx, gy, w)
					_push(heap, (ng2 + hv[v2]) * 65536 + v2)
	last_nodes = nodes
	if found < 0:
		return {}
	var path: Array = []
	var c2 := found
	while c2 != start:
		path.push_front(c2)
		c2 = prev[c2]
	var ts: Array = []
	var ms: Array = []
	for c3 in path:
		var gv := g[c3]
		var tt := gv / full
		var lf := full - (gv - tt * full)
		if gv > 0 and gv % full == 0:
			tt -= 1
			lf = 0
		ts.append(tt)
		ms.append(lf)
	return {"path": path, "t": ts, "m": ms}


## The detour rule (owner 2026-10-22: an army went east through Veracruz to
## reach Orizaba to its west). The cheapest path is taken only when it is at
## most DETOUR_PCT % longer than the direct path (the fewest cells, as octile
## length: 10 a straight step, 14 a diagonal; ties by the cheaper) or when it
## arrives a whole turn sooner than the direct path; otherwise the army walks
## the direct path. So the turn of arrival never gets later. Paths that use a
## sea link are left alone. (static var: the tests measure with and without.)
const DETOUR_PCT := 25
static var detour_rule := true


static func _path_len(start: int, path: Array) -> int:
	var tot := 0
	var prev := start
	for c in path:
		tot += 10 if (prev % _gw == int(c) % _gw or prev / _gw == int(c) / _gw) else 14
		prev = int(c)
	return tot


static func _limit_detour(res: Dictionary, start: int, goal: int, full: int, mp: int,
		block: PackedByteArray, zone: PackedInt32Array, adjacent: bool, max_nodes: int) -> Dictionary:
	var path: Array = res["path"]
	var prev := start
	for c in path:
		if cheb(prev, int(c)) != 1:
			return res  # a sea link: not a walk
		prev = int(c)
	var plen := _path_len(start, path)
	var lb := octile(start, goal) - (14 if adjacent else 0)
	if plen * 100 <= maxi(lb, 0) * (100 + DETOUR_PCT):
		return res  # within the bound of any direct path
	var direct := _shortest(start, goal, block, zone, adjacent, max_nodes * 2)
	if direct.is_empty():
		return res
	var dlen := _path_len(start, direct)
	if plen * 100 <= dlen * (100 + DETOUR_PCT):
		return res
	var sched := _schedule(direct, start, full, mp)
	var t_det: int = (res["t"] as Array)[(res["t"] as Array).size() - 1]
	var t_dir: int = (sched["t"] as Array)[(sched["t"] as Array).size() - 1]
	if t_det < t_dir:
		return res  # the detour saves a whole turn
	return sched


## The turn and the points left at each cell of a walked path (find_path's
## "t" and "m"), by the same rule as the search.
static func _schedule(path: Array, start: int, full: int, mp: int) -> Dictionary:
	var ts: Array = []
	var ms: Array = []
	var gu := full - clampi(mp, 0, full)
	var prev := start
	for c in path:
		var t := gu / full
		var left := full - (gu - t * full)
		if gu > 0 and gu % full == 0:
			t = gu / full - 1
			left = 0
		var cst := step_cost(prev, int(c))
		gu = gu + cst if left >= cst else (t + 1) * full + cst
		var tt := gu / full
		var lf := full - (gu - tt * full)
		if gu > 0 and gu % full == 0:
			tt -= 1
			lf = 0
		ts.append(tt)
		ms.append(lf)
		prev = int(c)
	return {"path": path, "t": ts, "m": ms}


## The direct path: the fewest octile length, ties by the cheaper step costs
## (A* on length * 4096 + cost). Walking steps only; {} none within max_nodes.
static func _shortest(start: int, goal: int, block: PackedByteArray, zone: PackedInt32Array,
		adjacent: bool, max_nodes: int) -> Array:
	var n := _n
	var w := _gw
	var g := PackedInt32Array()
	g.resize(n)
	g.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var has_block := block.size() == n
	var has_zone := zone.size() == n
	var gx := goal % w
	var gy := goal / w
	g[start] = 0
	var heap: Array[int] = []
	_push(heap, octile(start, goal) * 4096 * 65536 + start)
	var found := -1
	var nodes := 0
	while not heap.is_empty():
		var top := _pop(heap)
		var u := top & 65535
		var gu := g[u]
		var hu := octile(u, goal) * 4096
		if top >> 16 != gu + hu:
			continue
		if adjacent:
			if absi(u % w - gx) <= 1 and absi(u / w - gy) <= 1:
				found = u
				break
		elif u == goal:
			found = u
			break
		nodes += 1
		if nodes > max_nodes:
			break
		var base := u * 8
		for k in 8:
			var v := _nb[base + k]
			if v < 0 or (has_block and block[v] != 0) or (has_zone and zone[v] > 0):
				continue
			if adjacent and v == goal:
				continue
			var ng := gu + (10 if k % 2 == 0 else 14) * 4096 + _nbc[base + k]
			if ng < g[v]:
				g[v] = ng
				prev[v] = u
				_push(heap, (ng + octile(v, goal) * 4096) * 65536 + v)
	if found < 0:
		return []
	var path: Array = []
	var c2 := found
	while c2 != start:
		path.push_front(c2)
		c2 = prev[c2]
	return path


## The search's heuristic: the octile distance at H_PCT % of the cheapest
## step (a little greedy: fewer cells searched for a path within a few
## points of the cheapest; deterministic all the same).
const H_PCT := 150


static func _h(c: int, gx: int, gy: int, w: int) -> int:
	var dx := absi(c % w - gx)
	var dy := absi(c / w - gy)
	return (10 * maxi(dx, dy) + 4 * mini(dx, dy)) * H_PCT / 100


## Every cell an army reaches (Dijkstra on the same g as find_path) up to
## turn max_t: PackedInt32Array per cell, the turn it gets there (-1 never;
## 0 this turn). Cells marked in block are not entered; cells with stop > 0
## (PackedInt32Array, may be empty) are entered but not left (a zone of
## control).
static func reach(start: int, full: int, mp: int, block: PackedByteArray, max_t: int = 0,
		stop: PackedInt32Array = PackedInt32Array(), water: bool = false) -> PackedInt32Array:
	ensure()
	var nbr := _nb
	var nbcr := _nbc
	if water:
		_water_tables()
		if not _nbw.is_empty():
			nbr = _nbw
			nbcr = _nbcw
	var out := PackedInt32Array()
	out.resize(_n)
	out.fill(-1)
	if start < 0 or full <= 0:
		return out
	var g := PackedInt32Array()
	g.resize(_n)
	g.fill(INF)
	var has_block := block.size() == _n
	var has_stop := stop.size() == _n
	g[start] = full - clampi(mp, 0, full)
	var heap: Array[int] = [g[start] * 65536 + start]
	var cap := (max_t + 1) * full
	while not heap.is_empty():
		var top := _pop(heap)
		var u := top & 65535
		var gu := g[u]
		if top >> 16 != gu:
			continue
		var t := gu / full
		var left := full - (gu - t * full)
		if gu > 0 and gu % full == 0:
			t -= 1
			left = 0
		out[u] = t
		if has_stop and stop[u] > 0 and u != start:
			continue
		for k in 8:
			var v := nbr[u * 8 + k]
			if v < 0 or (has_block and block[v] != 0):
				continue
			var c := nbcr[u * 8 + k]
			var ng := gu + c if left >= c else (t + 1) * full + c
			if ng <= cap and ng < g[v]:
				g[v] = ng
				_push(heap, ng * 65536 + v)
		if _links.has(u):
			for ln in _links[u]:
				var v2 := int(ln[0])
				if has_block and block[v2] != 0:
					continue
				var ng2 := t * full + full if left == full else (t + 1) * full + full
				if ng2 <= cap and ng2 < g[v2]:
					g[v2] = ng2
					_push(heap, ng2 * 65536 + v2)
	return out


## Static distance field from cell `src` (points over passable land, a sea
## lane costing `sea` points; no state: peace, armies and battles ignored).
## Memoised per (src, sea): the same on every client.
static func field(src: int, sea: int) -> PackedInt32Array:
	ensure()
	var key := src * 4096 + sea
	if _fields.has(key):
		return _fields[key]
	var nb := _nb
	var nbc := _nbc
	var g := PackedInt32Array()
	g.resize(_n)
	g.fill(INF)
	g[src] = 0
	# A bucket queue (costs are small integers): no heap.
	var buckets := {}
	var cur := 0
	var pending := 1
	buckets[0] = [src]
	var maxg := 0
	while pending > 0:
		if not buckets.has(cur):
			cur += 1
			continue
		var list: Array = buckets[cur]
		buckets.erase(cur)
		for u in list:
			pending -= 1
			if g[u] != cur:
				continue
			var base: int = u * 8
			for k in 8:
				var v := nb[base + k]
				if v < 0:
					continue
				var ng := cur + nbc[base + k]
				if ng < g[v]:
					g[v] = ng
					if not buckets.has(ng):
						buckets[ng] = []
					(buckets[ng] as Array).append(v)
					pending += 1
					maxg = maxi(maxg, ng)
			if _links.has(u):
				for ln in _links[u]:
					var v2 := int(ln[0])
					var ng2 := cur + sea
					if ng2 < g[v2]:
						g[v2] = ng2
						if not buckets.has(ng2):
							buckets[ng2] = []
						(buckets[ng2] as Array).append(v2)
						pending += 1
		cur += 1
	_fields[key] = g
	return g


## Next cell from c down the field (the neighbour, or sea link, with the
## lowest value; ties by neighbour order), -1 at the bottom.
static func downhill(fld: PackedInt32Array, c: int, sea: int) -> int:
	ensure()
	var best := -1
	var bv := fld[c]
	for k in 8:
		var v := _nb[c * 8 + k]
		if v >= 0 and fld[v] < bv:
			bv = fld[v]
			best = v
	if _links.has(c):
		for ln in _links[c]:
			var v2 := int(ln[0])
			if fld[v2] + sea <= fld[c] and fld[v2] < bv:
				bv = fld[v2]
				best = v2
	return best


static func _push(heap: Array[int], v: int) -> void:
	heap.append(v)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if heap[p] <= v:
			break
		heap[i] = heap[p]
		i = p
	heap[i] = v


static func _pop(heap: Array[int]) -> int:
	var top := heap[0]
	var last: int = heap.pop_back()
	var n := heap.size()
	if n == 0:
		return top
	var i := 0
	while true:
		var l := 2 * i + 1
		if l >= n:
			break
		var r := l + 1
		var c := l if r >= n or heap[l] <= heap[r] else r
		if heap[c] >= last:
			break
		heap[i] = heap[c]
		i = c
	heap[i] = last
	return top
