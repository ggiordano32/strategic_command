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
##
## Lane trade, raids (2026-10-22, the second step; the state functions at the
## foot of this file). Lane ids: 0 .. n - 1 are CData.SEA_LANES, n .. n + m - 1
## the SEA_LANE_EXITS. A port-to-port lane pays (level_a + level_b) x
## LANE_BASE gold a turn (a SEA_LANE_TRADE row overrides), half to each end
## port's owner (the whole value to one owner holding both); a besieged or
## blockaded port's half is not paid. A fleet at war with an end port's owner
## lying on one of the lane's cells at the end of the turn RAIDS it: each half
## still paid is cut by LANE_RAID_PCT %, and the raider's owner takes
## LANE_RAID_TAKE % of what it cut from owners it is at war with. Everything is
## read from the state (fleet cells, ports, the blockade marks), nothing is
## stored: two clients with the same state agree.

const CData := preload("res://campaign/cdata.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CState := preload("res://campaign/cstate.gd")
const CFleet := preload("res://campaign/cfleet.gd")

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


# ------------------------------------------------------------ lane trade ---

static var _map_stamp := -1
static var _on_lane := {}   # cell -> [lane ids] (ascending)


static func count() -> int:
	return CData.SEA_LANES.size()


## Lane ids: the port lanes, then the exits.
static func total() -> int:
	return CData.SEA_LANES.size() + CData.SEA_LANE_EXITS.size()


static func is_exit(id: int) -> bool:
	return id >= CData.SEA_LANES.size()


## The lane's cells (route(), port cell first).
static func cells_of(id: int) -> PackedInt32Array:
	return lane(id) if id < CData.SEA_LANES.size() else exit_lane(id - CData.SEA_LANES.size())


static var _tab_stamp := -1
static var _ea := PackedInt32Array()   # lane id -> end region a / b (an exit's b is -1)
static var _eb := PackedInt32Array()
static var _ov := PackedInt32Array()   # lane id -> its SEA_LANE_TRADE value, -1 none


static func _ensure_tab() -> void:
	if _tab_stamp == CData.gen and _ea.size() == total():
		return
	_tab_stamp = CData.gen
	_ea = PackedInt32Array()
	_eb = PackedInt32Array()
	_ov = PackedInt32Array()
	for id in total():
		if id < CData.SEA_LANES.size():
			var pair: Array = CData.SEA_LANES[id]
			_ea.append(CData.region_index(pair[0]))
			_eb.append(CData.region_index(pair[1]))
			var v := -1
			for row in CData.SEA_LANE_TRADE:
				if (row[0] == pair[0] and row[1] == pair[1]) or (row[0] == pair[1] and row[1] == pair[0]):
					v = int(row[2])
					break
			_ov.append(v)
		else:
			_ea.append(CData.region_index(str(CData.SEA_LANE_EXITS[id - CData.SEA_LANES.size()][0])))
			_eb.append(-1)
			_ov.append(-1)


## The lane's end regions [a, b]; an exit's b is -1.
static func ends(id: int) -> Array:
	_ensure_tab()
	return [_ea[id], _eb[id]]


## "Havana - Veracruz" (an exit: "Havana - the sea").
static func lane_name(id: int) -> String:
	var e := ends(id)
	return "%s - %s" % [str(CData.REGIONS[int(e[0])]["city"]),
		str(CData.REGIONS[int(e[1])]["city"]) if int(e[1]) >= 0 else "the open sea"]


## The lane's sea cells that fleets can sail (CFleet.is_sea), in route order.
static func sea_cells(id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for c in cells_of(id):
		if CFleet.is_sea(c):
			out.append(c)
	return out


static func _ensure_map() -> void:
	if _map_stamp == CData.gen and not _on_lane.is_empty():
		return
	_map_stamp = CData.gen
	_on_lane = {}
	for id in total():
		for c in cells_of(id):
			if not _on_lane.has(c):
				_on_lane[c] = []
			if not (_on_lane[c] as Array).has(id):
				(_on_lane[c] as Array).append(id)


## The lane ids that have cell c on their route (ascending).
static func lanes_at(c: int) -> Array:
	_ensure_map()
	return _on_lane.get(c, [])


static func on_lane(id: int, c: int) -> bool:
	return lanes_at(c).has(id)


## The trade a turn lane id (a port lane) is worth: its SEA_LANE_TRADE row, else
## (level_a + level_b) x LANE_BASE at the ports' levels now. 0 for an exit.
static func base_value(st: Dictionary, id: int) -> int:
	if is_exit(id):
		return 0
	_ensure_tab()
	if _ov[id] >= 0:
		return _ov[id]
	return (int(st["regions"][_ea[id]]["level"]) + int(st["regions"][_eb[id]]["level"])) * CData.LANE_BASE


## Fleet fl may raid at all: ships, not the flota, not in a pending sea battle.
static func _can_raid(fl: Dictionary) -> bool:
	return not (fl["ships"] as Array).is_empty() and not fl.has("flota") and not fl.has("busy")


## Faction f is hostile to lane id: at war with an end port's owner (an exit:
## or with the flota's owner, so the flota's way home can be watched).
static func hostile(st: Dictionary, f: int, id: int) -> bool:
	_ensure_tab()
	for x in [_ea[id], _eb[id]]:
		if x >= 0:
			var o := CState.owner(st, x)
			if o >= 0 and CState.at_war(st, f, o):
				return true
	if is_exit(id) and st.has("fleets"):
		for fl in CFleet.fleets(st):
			if fl.has("flota") and CState.at_war(st, f, int(fl["f"])):
				return true
	return false


## Lane id -> the fleet raiding it now (the lowest fleet id lying on one of its
## cells and hostile to it); only lanes with a raider are keys.
static func raiders(st: Dictionary) -> Dictionary:
	var out := {}
	if not st.has("fleets"):
		return out
	for fl in CFleet.fleets(st):
		if not _can_raid(fl):
			continue
		for id in lanes_at(CFleet.cell(fl)):
			if not out.has(id) and hostile(st, int(fl["f"]), int(id)):
				out[id] = fl
	return out


## What lane id pays now: {v (its value), oa, ob (the end owners), pa, pb (what
## each end's owner receives), cuta, cutb (cut by a raid), la, lb (lost to a
## blockade or siege of that port), rid (the raider's fleet id, -1), rf (its
## faction), take (what the raider's owner takes)}. `rt`: raiders(st).
static func lane_state(st: Dictionary, id: int, rt: Dictionary) -> Dictionary:
	_ensure_tab()
	var a := _ea[id]
	var b := _eb[id]
	var v := base_value(st, id)
	var oa := CState.owner(st, a)
	var ob := CState.owner(st, b) if b >= 0 else -1
	var pa := v / 2 if oa >= 0 else 0
	var pb := (v - v / 2) if ob >= 0 else 0
	var la := 0
	var lb := 0
	if pa > 0 and (int(st["regions"][a].get("bk", -1)) >= 0 or not CState.siege_at(st, a).is_empty()):
		la = pa
		pa = 0
	if pb > 0 and (int(st["regions"][b].get("bk", -1)) >= 0 or not CState.siege_at(st, b).is_empty()):
		lb = pb
		pb = 0
	var out := {"v": v, "oa": oa, "ob": ob, "pa": pa, "pb": pb, "cuta": 0, "cutb": 0, "la": la, "lb": lb,
		"rid": -1, "rf": -1, "take": 0}
	if rt.has(id) and v > 0:
		var fl: Dictionary = rt[id]
		var rf := int(fl["f"])
		var ca := pa * CData.LANE_RAID_PCT / 100
		var cb := pb * CData.LANE_RAID_PCT / 100
		out["cuta"] = ca
		out["cutb"] = cb
		out["pa"] = pa - ca
		out["pb"] = pb - cb
		out["rid"] = int(fl["id"])
		out["rf"] = rf
		var tk := 0
		if oa >= 0 and CState.at_war(st, rf, oa):
			tk += ca
		if ob >= 0 and CState.at_war(st, rf, ob):
			tk += cb
		out["take"] = tk * CData.LANE_RAID_TAKE / 100
	return out


## Faction f's lane terms for income(): {in (what its ports' lanes pay it),
## lost (cut by raids, or unpaid for a blockaded or besieged port), take (what
## its raiders take), raided (lanes it raids now), lanes (lanes paying it)}.
static func income_parts(st: Dictionary, f: int) -> Dictionary:
	var out := {"in": 0, "lost": 0, "take": 0, "raided": 0, "lanes": 0}
	if CData.SEA_LANES.is_empty():
		return out
	var rt := raiders(st)
	_ensure_tab()
	for id in count():
		# (only the lanes that pay f or that f raids need working out)
		var raider_f: int = int((rt[id] as Dictionary)["f"]) if rt.has(id) else -1
		if raider_f != f and CState.owner(st, _ea[id]) != f and CState.owner(st, _eb[id]) != f:
			continue
		var ls := lane_state(st, id, rt)
		var mine := 0
		if int(ls["oa"]) == f:
			mine += int(ls["pa"])
			out["lost"] = int(out["lost"]) + int(ls["cuta"]) + int(ls["la"])
		if int(ls["ob"]) == f:
			mine += int(ls["pb"])
			out["lost"] = int(out["lost"]) + int(ls["cutb"]) + int(ls["lb"])
		if mine > 0:
			out["lanes"] = int(out["lanes"]) + 1
		out["in"] = int(out["in"]) + mine
		if int(ls["rf"]) == f:
			out["take"] = int(out["take"]) + int(ls["take"])
			out["raided"] = int(out["raided"]) + 1
	return out


# ------------------------------------------------------------- stations ---

## The lane cell fleet fl of faction f should lie on to hold lane id: its own
## cell when it is on the lane already, else the lane's sea cell nearest it
## (octile, ties by cell index) outside the zones of fleets at war (a coastal
## fleet only where it can keep to the coast); when every cell lies in an
## enemy zone the nearest of those (the voyage is then an attack). -1 none.
static func raid_station(st: Dictionary, f: int, fl: Dictionary, id: int) -> int:
	var here := CFleet.cell(fl)
	if on_lane(id, here):
		return here
	var lim := int(CData.ship_const("COASTAL_CELLS", 2))
	var best := -1
	var bd := 1 << 30
	var fb := -1
	var fbd := 1 << 30
	for c in sea_cells(id):
		if CFleet.coastal(fl) and (CFleet.coast_dist(c) > lim or not CFleet.coastal_link(here, c)):
			continue
		var d := CGrid.octile(here, c)
		if CFleet.zone_owner(st, f, c) >= 0:
			if d < fbd or (d == fbd and c < fb):
				fbd = d
				fb = c
		elif d < bd or (d == bd and c < best):
			bd = d
			best = c
	return best if best >= 0 else fb


## The lane cell `steps` cells on from the cell of `cells` nearest `from` (the
## route's end when it runs out); sea cells only. -1 when the route has none.
## A flota following its lane steers for this.
static func cell_ahead(cells: PackedInt32Array, from: int, steps: int) -> int:
	var seas: Array = []
	for c in cells:
		if CFleet.is_sea(c):
			seas.append(c)
	if seas.is_empty():
		return -1
	var bi := 0
	var bd := 1 << 30
	for i in seas.size():
		var d := CGrid.d2(int(seas[i]), from)
		if d < bd:
			bd = d
			bi = i
	return int(seas[mini(bi + maxi(steps, 1), seas.size() - 1)])


## The cells of lane id ordered to end at region r (reversed when r is the lane's
## first end); the exit lanes are ordered out from their port.
static func cells_to(id: int, r: int) -> PackedInt32Array:
	var cells := cells_of(id)
	if not is_exit(id) and int(ends(id)[0]) == r:
		var rev := PackedInt32Array()
		for i in range(cells.size() - 1, -1, -1):
			rev.append(cells[i])
		return rev
	return cells


## The port lane joining regions a and b (-1 none; the lowest id).
static func lane_between(a: int, b: int) -> int:
	for id in count():
		var e := ends(id)
		if (int(e[0]) == a and int(e[1]) == b) or (int(e[0]) == b and int(e[1]) == a):
			return id
	return -1


## The exit lane leaving region r's port (the SEA_LANE_EXITS index + count, -1 none).
static func exit_of(r: int) -> int:
	for j in CData.SEA_LANE_EXITS.size():
		if CData.region_index(str(CData.SEA_LANE_EXITS[j][0])) == r:
			return count() + j
	return -1
