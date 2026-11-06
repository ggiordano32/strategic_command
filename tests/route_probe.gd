extends SceneTree
## Paths clear of the enemy (docs/design/battle_sim.md "Paths clear of the enemy (as built, 2026-11-06)"): the route
## probe. A unit (no AI) ordered on a move with an enemy unit (no AI, fire at will) across its plain way. Prints per case: the anchor's way (metres walked), the time to arrive, the men it lost
## on the way (the shots that struck it), the closest its box came to the enemy's and whether it joined a melee.
##   thru    the open field: 60 rodeleros from 140 m out of an enemy musket line facing them to 70 m behind it
##   front   the open field: 60 rodeleros past the front of an enemy musket line facing across their way (70 m off)
##   house   west_village: the defenders' musket company (holding its fire) into a house (ORDER_OCCUPY) 90-170 m off,
##           the attackers' musket company (24 men) standing halfway along the plain way to its door, facing it
##   godot --headless --script res://tests/route_probe.gd [-- --only=thru|front|house --png=DIR]
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const MapGen := preload("res://sim/mapgen.gd")
const Terrain := preload("res://sim/terrain.gd")
const FM := preload("res://sim/fixed_math.gd")
const M := 1024
const UP := 768
const DOWN := 256

var png := ""


func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
		elif a.begins_with("--png="):
			png = a.substr(6)
	for c in ["thru", "front", "house"]:
		if only != "" and only != c:
			continue
		var r := run_case(c, png)
		print("%-6s way %6.1f m (plain %6.1f m)  arrived %6.1f s  men lost %3d  closest to the enemy's box %5.1f m  melee %d  detours %d" % [
			c, r["walked"] / float(M), r["plain"] / float(M), r["arr"] / 10.0, r["lost"], r["closest"] / float(M), r["melee"], r["detours"]])
	quit(0)


## The case's sim, mover, enemy and goal.
static func setup_case(c: String) -> Array:
	var a := scenario_case(c)
	var sim := BattleSim.new()
	sim.setup(a[0], 7)
	return [sim, a[1], a[2], a[3]]


## The case's scenario (seed 7), mover, enemy and goal.
static func scenario_case(c: String) -> Array:
	var rod := UT.index_of("rodeleros")
	var mus := UT.index_of("musketeers")
	if c == "thru" or c == "front":
		var units := [Scenarios.unit(0, rod, 60, 200 if c == "thru" else 180, 330, UP, 15)]
		if c == "thru":
			units.append(Scenarios.unit(1, mus, 100, 200, 190, DOWN, 25))
		else:
			units.append(Scenarios.unit(1, mus, 100, 110, 190, 0, 25))
		var sc := {"width_m": 400, "height_m": 400, "ai_sides": [], "units": units}
		var gx := (200 if c == "thru" else 180) * M
		var gy := (120 if c == "thru" else 50) * M
		sc["orders"] = [BattleSim.make_move_order(5, 0, gx, gy, UP, 15 * UT.stat(rod, "file_sp"), 0)]
		return [sc, 0, 1, Vector2i(gx, gy)]
	# house: west_village, the attackers' rodeleros and the defenders' musketeers.
	var sc2 := Scenarios.west_town(11, 0, 0, 1, Terrain.K_FLAT, MapGen.PAL_DRY, MapGen.CUL_LATIN)
	var keep: Array = []
	var got := {}
	for ud in sc2["units"]:
		var key := "%d:%s" % [int(ud["side"]), UT.key_of(int(ud["type"]))]
		if (key == "1:musketeers" or key == "0:musketeers") and not got.has(key):
			got[key] = true
			keep.append(ud)
	sc2["units"] = keep
	sc2["deploy_zones"] = []
	sc2["ai_sides"] = []
	var probe := BattleSim.new()
	probe.setup(sc2, 7)
	var mv := 0 if probe.u_side[0] == 1 else 1
	var en := 1 - mv
	# The house: the nearest holdable building whose door is 90-170 m from the mover and whose plain way's middle
	# lies on open ground (24 m clear either side across the way: room to go round the company standing there).
	var bb := -1
	var at := Vector2i.ZERO
	var fc := 0
	var door := Vector2i.ZERO
	var cands: Array = []
	for k in probe.ob_ok.size():
		if probe.ob_ok[k] == 0:
			continue
		var dd := FM.approx_len(probe.ob_dx[k] - probe.u_ax[mv], probe.ob_dy[k] - probe.u_ay[mv])
		if dd >= 90 * M and dd <= 170 * M:
			cands.append([dd, k])
	cands.sort()
	for cd in cands:
		var k: int = cd[1]
		var dr := Vector2i(probe.ob_dx[k], probe.ob_dy[k])
		var mid := _mid_of(probe, mv, dr)
		var ok := true
		var mc := FM.cos_a(mid.z)
		var sn := FM.sin_a(mid.z)
		for off in [-24, -18, -12, -6, 6, 12, 18, 24]:
			var px: int = mid.x - sn * off * M / FM.TRIG_ONE
			var py: int = mid.y + mc * off * M / FM.TRIG_ONE
			if (probe.nav_at(px, py) & probe._ground_mask(mv)) == 0:
				ok = false
				break
		if ok:
			bb = k
			door = dr
			at = Vector2i(mid.x, mid.y)
			fc = (mid.z + 512) & FM.ANGLE_MASK
			break
	for ud in sc2["units"]:
		if int(ud["side"]) == probe.u_side[en]:
			ud["x_m"] = at.x / M
			ud["y_m"] = at.y / M
			ud["facing"] = fc
			ud["files"] = 8
			ud["count"] = 24
	sc2["orders"] = [{"tick": 0, "type": BattleSim.ORDER_FIRE, "unit": mv, "on": 0},
		{"tick": 5, "type": BattleSim.ORDER_OCCUPY, "unit": mv, "building": bb, "run": 0}]
	return [sc2, mv, en, door]


## The middle (by length) of unit mv's plain way to `dr`, and the way's heading there (z).
static func _mid_of(probe, mv: int, dr: Vector2i) -> Vector3i:
	var way: PackedInt32Array = probe.route_to(probe.u_ax[mv], probe.u_ay[mv], dr.x, dr.y, probe._ground_mask(mv))
	var pts := PackedInt32Array([probe.u_ax[mv], probe.u_ay[mv]])
	pts.append_array(way)
	var total := 0
	for k in range(1, pts.size() / 2):
		total += FM.approx_len(pts[k * 2] - pts[k * 2 - 2], pts[k * 2 + 1] - pts[k * 2 - 1])
	var half := total / 2
	for k in range(1, pts.size() / 2):
		var l := FM.approx_len(pts[k * 2] - pts[k * 2 - 2], pts[k * 2 + 1] - pts[k * 2 - 1])
		if half <= l and l > 0:
			return Vector3i(pts[k * 2 - 2] + (pts[k * 2] - pts[k * 2 - 2]) * half / l, pts[k * 2 - 1] + (pts[k * 2 + 1] - pts[k * 2 - 1]) * half / l,
				FM.atan2_a(pts[k * 2 + 1] - pts[k * 2 - 1], pts[k * 2] - pts[k * 2 - 2]))
		half -= l
	return Vector3i(dr.x, dr.y, 0)


static func run_case(c: String, pdir: String = "") -> Dictionary:
	var a := setup_case(c)
	var sim = a[0]
	var mv: int = a[1]
	var en: int = a[2]
	var goal: Vector2i = a[3]
	var plain: PackedInt32Array = sim.route_to(sim.u_ax[mv], sim.u_ay[mv], goal.x, goal.y, sim._ground_mask(mv))
	var pl := 0
	var lx: int = sim.u_ax[mv]
	var ly: int = sim.u_ay[mv]
	for k in plain.size() / 2:
		pl += FM.approx_len(plain[k * 2] - lx, plain[k * 2 + 1] - ly)
		lx = plain[k * 2]
		ly = plain[k * 2 + 1]
	var alive0: int = sim.u_alive[mv]
	var walked := 0
	var arr := -1
	var closest := 1 << 30
	var melee := 0
	var trail := PackedInt32Array()
	var px: int = sim.u_ax[mv]
	var py: int = sim.u_ay[mv]
	for t in 3000:
		sim.step()
		walked += FM.approx_len(sim.u_ax[mv] - px, sim.u_ay[mv] - py)
		px = sim.u_ax[mv]
		py = sim.u_ay[mv]
		if t % 5 == 0:
			trail.append(px)
			trail.append(py)
		if sim.u_contact[mv] != 0:
			melee = 1
		var gx := maxi(maxi(sim.u_minx[en] - sim.u_maxx[mv], sim.u_minx[mv] - sim.u_maxx[en]), 0)
		var gy := maxi(maxi(sim.u_miny[en] - sim.u_maxy[mv], sim.u_miny[mv] - sim.u_maxy[en]), 0)
		closest = mini(closest, FM.approx_len(gx, gy))
		if t > 10 and sim.u_order[mv] == BattleSim.O_NONE:
			arr = sim.tick
			break
	if pdir != "":
		_shot(sim, mv, en, trail, plain, goal, "%s/route_%s.png" % [pdir, c])
	var det := 0
	if "stat_rt_detours" in sim:
		det = sim.stat_rt_detours
	return {"walked": walked, "plain": pl, "arr": arr, "lost": alive0 - sim.u_alive[mv], "closest": closest, "melee": melee,
		"detours": det, "trail": trail}


## Top view, 3 px a metre round the mover's start, the goal and the enemy: blocked ground grey, the plain way
## (route_to) thin black, the anchor's trail blue, the enemy's men red, the mover's men blue, the goal a green dot.
static func _shot(sim, mv: int, en: int, trail: PackedInt32Array, plain: PackedInt32Array, goal: Vector2i, path: String) -> void:
	var x0 := mini(mini(trail[0], goal.x), sim.u_minx[en]) - 40 * M
	var y0 := mini(mini(trail[1], goal.y), sim.u_miny[en]) - 40 * M
	var x1 := maxi(maxi(trail[0], goal.x), sim.u_maxx[en]) + 40 * M
	var y1 := maxi(maxi(trail[1], goal.y), sim.u_maxy[en]) + 40 * M
	for k in trail.size() / 2:
		x0 = mini(x0, trail[k * 2] - 10 * M)
		x1 = maxi(x1, trail[k * 2] + 10 * M)
		y0 = mini(y0, trail[k * 2 + 1] - 10 * M)
		y1 = maxi(y1, trail[k * 2 + 1] + 10 * M)
	var s := 3
	var w := (x1 - x0) / M * s
	var h := (y1 - y0) / M * s
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.86, 0.83, 0.72))
	if sim.obs_on != 0:
		for yy in h:
			for xx in w:
				var wx: int = x0 + xx * M / s
				var wy: int = y0 + yy * M / s
				if (sim.nav_at(wx, wy) & sim._ground_mask(mv)) == 0:
					img.set_pixel(xx, yy, Color(0.45, 0.42, 0.4))
	var lx: int = trail[0]
	var ly: int = trail[1]
	for k in plain.size() / 2:
		_line(img, x0, y0, s, lx, ly, plain[k * 2], plain[k * 2 + 1], Color(0.1, 0.1, 0.1))
		lx = plain[k * 2]
		ly = plain[k * 2 + 1]
	for k in range(1, trail.size() / 2):
		_line(img, x0, y0, s, trail[k * 2 - 2], trail[k * 2 - 1], trail[k * 2], trail[k * 2 + 1], Color(0.1, 0.3, 0.9))
	for u in [en, mv]:
		var b: int = sim.u_slot_base[u]
		for q in sim.u_alive[u]:
			var i: int = sim.slot_soldier[b + q]
			_dot(img, (sim.pos_x[i] - x0) * s / M, (sim.pos_y[i] - y0) * s / M, 1, Color(0.8, 0.1, 0.1) if u == en else Color(0.1, 0.2, 0.7))
	_dot(img, (goal.x - x0) * s / M, (goal.y - y0) * s / M, 3, Color(0.1, 0.6, 0.2))
	img.save_png(path)


static func _line(img: Image, x0: int, y0: int, s: int, ax: int, ay: int, bx: int, by: int, col: Color) -> void:
	var n: int = maxi(FM.approx_len(bx - ax, by - ay) * s / M, 1)
	for k in n + 1:
		_dot(img, (ax + (bx - ax) * k / n - x0) * s / M, (ay + (by - ay) * k / n - y0) * s / M, 0, col)


static func _dot(img: Image, cx: int, cy: int, r: int, col: Color) -> void:
	for yy in range(-r, r + 1):
		for xx in range(-r, r + 1):
			if cx + xx >= 0 and cy + yy >= 0 and cx + xx < img.get_width() and cy + yy < img.get_height():
				img.set_pixel(cx + xx, cy + yy, col)
