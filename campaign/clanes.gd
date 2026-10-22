extends RefCounted
## Sea lanes as routes through the sea (2026-10-22): the data is
## CData.SEA_LANES (port to port) and CData.SEA_LANE_EXITS (a port out to the
## open sea at the map's edge); this turns a lane into the sea cells it
## sails. Pure integer maths on the nav grid (no state, no Nodes): the map
## view smooths and draws them, and the rules for raiding and blockading a
## lane (a later step) and a navy read the same cells. Pack-agnostic: Rome's
## lanes and the West's use the same code.
##
## A lane never crosses land: A* over sea cells (8-connected, a diagonal needs
## both orthogonal cells to be sea), the cost 10 / 14 a step plus a penalty
## next to land (a ship keeps off the coast: round the islands, not along
## their beaches). Ties by cell index, so the route is the same everywhere.

const CData := preload("res://campaign/cdata.gd")
const CGrid := preload("res://campaign/cgrid.gd")

const COAST_PEN_1 := 20   # a sea cell next to land
const COAST_PEN_2 := 10   # ... two cells off the land
const COAST_PEN_3 := 4    # ... three cells off

static var _stamp := -1   # CData.gen the tables below belong to (a pack switch bumps it)
static var _pen := PackedInt32Array()
static var _routes := {}   # a * 65536 + b -> PackedInt32Array
static var _open := PackedByteArray()   # 1: a sea cell of a sea of OPEN_SEA cells or more (not a lake or a lagoon)
const OPEN_SEA := 300


static func _ensure() -> void:
	if _stamp == CData.gen and not _pen.is_empty():
		return
	_stamp = CData.gen
	_routes = {}
	var w := CGrid.width()
	var h := CGrid.height()
	_pen = PackedInt32Array()
	_pen.resize(w * h)
	# Distance to land in cells (to 3) by a breadth-first flood from the land cells.
	var dist := PackedByteArray()
	dist.resize(w * h)
	dist.fill(255)
	var front: Array = []
	for c in w * h:
		if CGrid.region(c) != -1:
			dist[c] = 0
			front.append(c)
	var fi := 0
	while fi < front.size():
		var u: int = front[fi]
		fi += 1
		if dist[u] >= 3:
			continue
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var q := CGrid.at(u % w + dx, u / w + dy)
				if q >= 0 and dist[q] == 255:
					dist[q] = dist[u] + 1
					front.append(q)
	for c in w * h:
		if dist[c] == 0:
			_pen[c] = -1
		elif dist[c] == 1:
			_pen[c] = COAST_PEN_1
		elif dist[c] == 2:
			_pen[c] = COAST_PEN_2
		elif dist[c] == 3:
			_pen[c] = COAST_PEN_3
		else:
			_pen[c] = 0
	_open = PackedByteArray()
	_open.resize(w * h)
	var seen := PackedByteArray()
	seen.resize(w * h)
	for c0 in w * h:
		if _pen[c0] < 0 or seen[c0] != 0:
			continue
		var comp: Array = [c0]
		seen[c0] = 1
		var i := 0
		while i < comp.size():
			var u: int = comp[i]
			i += 1
			for k in 4:
				var q := CGrid.at(u % w + CGrid.DX[k * 2], u / w + CGrid.DY[k * 2])
				if q >= 0 and _pen[q] >= 0 and seen[q] == 0:
					seen[q] = 1
					comp.append(q)
		if comp.size() >= OPEN_SEA:
			for u in comp:
				_open[u] = 1


## The cells of the route from cell a to cell b (port cells, land: some touch
## the sea only at a corner or lie a cell or two inland, a river port): a, the
## sea cells from the sea cell nearest a to the one nearest b, b. Empty when
## the sea does not join them.
static func route(a: int, b: int) -> PackedInt32Array:
	_ensure()
	var key := a * 65536 + b
	if _routes.has(key):
		return _routes[key]
	var out := PackedInt32Array()
	if a >= 0 and b >= 0:
		var sa := sea_cell_near(CGrid.cx(a), CGrid.cy(a))
		var sb := sea_cell_near(CGrid.cx(b), CGrid.cy(b))
		var mid := _search(sa, sb) if sa >= 0 and sb >= 0 else PackedInt32Array()
		if not mid.is_empty():
			if a != sa:
				out.append(a)
			out.append_array(mid)
			if b != sb:
				out.append(b)
	_routes[key] = out
	return out


## Lane i of CData.SEA_LANES.
static func lane(i: int) -> PackedInt32Array:
	var pair: Array = CData.SEA_LANES[i]
	return route(CGrid.port(CData.region_index(pair[0])), CGrid.port(CData.region_index(pair[1])))


## Exit i of CData.SEA_LANE_EXITS ([port region key, grid x, grid y]): the
## port out to the sea cell nearest that grid cell.
static func exit_lane(i: int) -> PackedInt32Array:
	var ex: Array = CData.SEA_LANE_EXITS[i]
	return route(CGrid.port(CData.region_index(str(ex[0]))), sea_cell_near(int(ex[1]), int(ex[2])))


static func _h(c: int, g: int, w: int) -> int:
	var dx := absi(c % w - g % w)
	var dy := absi(c / w - g / w)
	return (10 * maxi(dx, dy) + 4 * mini(dx, dy)) * 3 / 2   # a little greedy: a lane need not be the exact optimum


static func _search(a: int, b: int) -> PackedInt32Array:
	var w := CGrid.width()
	var n := w * CGrid.height()
	if a < 0 or b < 0 or a >= n or b >= n:
		return PackedInt32Array()
	var g := PackedInt32Array()
	g.resize(n)
	g.fill(1 << 30)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var heap: Array[int] = []
	g[a] = 0
	_push(heap, _h(a, b, w) * 65536 + a)
	var found := false
	var nodes := 0
	while not heap.is_empty():
		var top := _pop(heap)
		var u := top & 65535
		if top >> 16 != g[u] + _h(u, b, w):
			continue
		if u == b:
			found = true
			break
		nodes += 1
		if nodes > 40000:
			break
		var ux := u % w
		var uy := u / w
		for k in 8:
			var vx := ux + CGrid.DX[k]
			var vy := uy + CGrid.DY[k]
			if vx < 0 or vy < 0 or vx >= w or vy >= CGrid.height():
				continue
			var v := vy * w + vx
			if _pen[v] < 0:
				continue
			if k % 2 == 1 and (_pen[uy * w + vx] < 0 or _pen[vy * w + ux] < 0):
				continue  # a diagonal needs both orthogonal cells open
			var step := (10 if k % 2 == 0 else 14) + maxi(_pen[v], 0)
			var ng := g[u] + step
			if ng < g[v]:
				g[v] = ng
				prev[v] = u
				_push(heap, (ng + _h(v, b, w)) * 65536 + v)
	if not found:
		return PackedInt32Array()
	var cells: Array = []
	var c := b
	while c != a:
		cells.push_front(c)
		c = prev[c]
	cells.push_front(a)
	return PackedInt32Array(cells)


## Cell c is open sea (not land, a lake or a lagoon).
static func is_open(c: int) -> bool:
	_ensure()
	return c >= 0 and c < _open.size() and _open[c] != 0


## The sea cell nearest to (x, y) in cells (ring search), -1 none.
static func sea_cell_near(x: int, y: int) -> int:
	_ensure()
	x = clampi(x, 0, CGrid.width() - 1)
	y = clampi(y, 0, CGrid.height() - 1)
	for r in 40:
		var best := -1
		var bd := 1 << 30
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := CGrid.at(x + dx, y + dy)
				if c >= 0 and _open[c] != 0 and dx * dx + dy * dy < bd:
					bd = dx * dx + dy * dy
					best = c
		if best >= 0:
			return best
	return -1


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
