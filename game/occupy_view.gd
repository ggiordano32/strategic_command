extends RefCounted
## The Occupy flow's read-only queries (view only; nothing here writes the sim):
## which buildings the selected men may be sent into (the sim's own rule,
## BattleSim.occupy_refusal), and a building's sight fans: per face a fan of
## 16 rays from its firing places out to the weapon range, each cut at the
## first obstacle cell (another house, a wall, a tower, a gate, a rock; the
## building's own cells and open ground, ditch and water let it through).
## Metres, the map's frame.

const BattleSim := preload("res://sim/battle_sim.gd")
const MapGen := preload("res://sim/mapgen.gd")
const UT := preload("res://sim/unit_types.gd")

const RAYS := 16            # directions per face (17 edge points of a fan)
const HALF_ARC := 0.87      # a face's fan: +-50 degrees about its outward facing
const MAX_RANGE_M := 80.0  # the longest fan drawn
const MIN_RANGE_M := 25.0   # for men with no missile weapon: what the windows still command
const STEP := 1024          # ray march step: 1 m (an obstacle cell is 2 m)

const KIND_NAME := {MapGen.B_HOUSE: "House", MapGen.B_TEMPLE: "Shrine", MapGen.B_BARRACKS: "Barracks", MapGen.B_TAVERN: "Tavern",
	MapGen.B_SHOP: "Shop", MapGen.B_STORE: "Store", MapGen.B_WAREHOUSE: "Warehouse", MapGen.B_CHANDLER: "Chandlery",
	MapGen.B_GOVERNOR: "Governor's house"}


## The foot units of `units` that may take a building at all (ready, not on a wall, carrying nothing).
static func eligible(sim, units: Array) -> Array[int]:
	var out: Array[int] = []
	if sim.occ_on == 0:
		return out
	for u in units:
		if BattleSim.stance_ok(sim.u_type[u]) and sim.u_state[u] == BattleSim.U_READY and sim.u_occ[u] == 0:
			out.append(u)
	return out


## Buildings (indices of the layout / sim.ob_*) some unit of `units` may be sent into, in index order.
static func lit(sim, units: Array) -> Array[int]:
	var out: Array[int] = []
	var us := eligible(sim, units)
	if us.is_empty():
		return out
	for b in sim.ob_ok.size():
		if sim.ob_ok[b] == 0:
			continue
		for u in us:
			if BattleSim.occupy_refusal(sim, u, b) == "":
				out.append(b)
				break
	return out


## The weapon range (m) its fans reach, from unit u's type (capped, floored).
static func range_m(sim, u: int) -> float:
	var r := float(UT.stat(sim.u_type[u], "m_range")) / 1024.0 if u >= 0 else 0.0
	return clampf(r, MIN_RANGE_M, MAX_RANGE_M)


## The footprint of building b, 4 corners, metres (empty: none).
static func quad(sim, b: int) -> PackedVector2Array:
	var lay: Dictionary = sim.map_info.get("city", {})
	var blds: Array = lay.get("buildings", [])
	var pts := PackedVector2Array()
	if b < 0 or b >= blds.size():
		return pts
	var a: Array = blds[b]
	if a.size() < 15:
		return pts
	for q in 4:
		pts.append(Vector2(float(int(a[7 + q * 2])), float(int(a[8 + q * 2]))))
	return pts


static func kind_name(sim, b: int) -> String:
	var blds: Array = (sim.map_info.get("city", {}) as Dictionary).get("buildings", [])
	if b < 0 or b >= blds.size():
		return "Building"
	return str(KIND_NAME.get(int((blds[b] as Array)[4]), "Building"))


## Places of building b (the firing places the sim gives its men) and how many men it holds at once
## (the windows, plus the two at the door).
static func places(sim, b: int) -> int:
	return int(sim.ob_sn[b])


static func holds(sim, b: int) -> int:
	return int(sim.ob_sn[b]) + BattleSim.OCC_DOOR_N


## The sight fans of building b to `range_m` metres: one per face, each
## {"face": sim angle, "origin": Vector2 (the face's places' middle), "n": places on the face,
## "pts": PackedVector2Array (origin first, then the RAYS + 1 ray ends)}.
static func fans(sim, b: int, rng_m: float) -> Array:
	var out: Array = []
	if b < 0 or b >= sim.ob_ok.size() or sim.ob_ok[b] == 0:
		return out
	var s0: int = sim.ob_s0[b]
	var sn: int = sim.ob_sn[b]
	var i := 0
	while i < sn:
		var f: int = sim.sp_f[s0 + i]
		var j := i
		var mx := 0
		var my := 0
		while j < sn and sim.sp_f[s0 + j] == f:
			mx += sim.sp_x[s0 + j]
			my += sim.sp_y[s0 + j]
			j += 1
		var n := j - i
		var ox := mx / n
		var oy := my / n
		var base := f * TAU / 1024.0
		var pts := PackedVector2Array([Vector2(ox, oy) / 1024.0])
		for k in RAYS + 1:
			var ang := base - HALF_ARC + 2.0 * HALF_ARC * k / RAYS
			pts.append(_ray(sim, b, ox, oy, cos(ang), sin(ang), rng_m))
		out.append({"face": f, "origin": Vector2(ox, oy) / 1024.0, "n": n, "pts": pts})
		i = j
	return out


## How far (m, to `rng_m`) a ray from (ox, oy) (sim units) clears; its end point in metres.
static func _ray(sim, b: int, ox: int, oy: int, dx: float, dy: float, rng_m: float) -> Vector2:
	var steps := int(rng_m)
	var w: int = sim.ob_w
	var h: int = sim.ob_h
	var last := Vector2(ox, oy) / 1024.0
	var left_own := false
	for s in range(1, steps + 1):
		var x := ox + int(dx * s * STEP)
		var y := oy + int(dy * s * STEP)
		if x < 0 or y < 0:
			break
		var i := x >> 11
		var j := y >> 11
		if i >= w or j >= h:
			break
		var c: int = j * w + i
		var k: int = sim.obs[c]
		if k == MapGen.C_BUILDING and sim.occ_bg[c] == b + 1 and not left_own:
			last = Vector2(x, y) / 1024.0
			continue  # (still inside the building's own walls)
		left_own = true
		if k == MapGen.C_OPEN or k == MapGen.C_DITCH or k == MapGen.C_WATER or k == MapGen.C_WALK:
			last = Vector2(x, y) / 1024.0
			continue
		break
	return last
