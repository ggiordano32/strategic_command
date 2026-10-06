extends SceneTree
## Dev tool: render generated settlements to PNG.
##   godot --script res://tools/city_dump.gd -- --out=docs/screenshots
##     one picture per plan x site (and some coasts), drawn exactly like the
##     campaign's "View battle map" (game/campaign/city_preview.gd +
##     game/city_draw.gd), as settlements_<plan>_<site>[_coast].png. Needs a
##     window (rendering).
##   godot --headless --script res://tools/city_dump.gd -- --grid --out=/tmp --seed=N
##     the obstacle grid, vegetation and street graph of the original maps
##     as city_<level>_<walls>_<seed>.png (2 px per metre), with times.

const MapGen := preload("res://sim/mapgen.gd")
const Terrain := preload("res://sim/terrain.gd")
const CityPreview := preload("res://game/campaign/city_preview.gd")

const COL := {0: Color(0.62, 0.66, 0.48), 1: Color(0.72, 0.45, 0.32), 2: Color(0.35, 0.33, 0.30),
	3: Color(0.55, 0.53, 0.50), 4: Color(0.25, 0.24, 0.22), 5: Color(0.3, 0.22, 0.14),
	6: Color(0.2, 0.38, 0.55), 7: Color(0.9, 0.85, 0.3)}

## [plan, terrain kind, coast, level, walls, ground, seed, owner culture, banner faction,
##  house styles by level, name]
const CASES := [
	[MapGen.PLAN_CASTRUM, Terrain.K_FLAT, 0, 2, 3, MapGen.PAL_DRY, 4101, 0, 0, [0, 0, 0], "castrum_plain"],
	[MapGen.PLAN_CASTRUM, Terrain.K_HILL, 1, 1, 2, MapGen.PAL_GREEN, 4102, 0, 0, [0, 0, 0], "castrum_hill_coast"],
	[MapGen.PLAN_POLIS, Terrain.K_HILL, 1, 2, 2, MapGen.PAL_DRY, 4103, 0, 0, [1, 1, 0], "polis_hill_coast"],
	[MapGen.PLAN_POLIS, Terrain.K_RIDGE, 0, 2, 2, MapGen.PAL_ROCKY, 4104, 1, 4, [1, 1, 1], "polis_spur"],
	[MapGen.PLAN_PUNIC, Terrain.K_FLAT, 1, 2, 2, MapGen.PAL_ARID, 4105, 2, 1, [2, 2, 2], "punic_plain_coast"],
	[MapGen.PLAN_PUNIC, Terrain.K_HILL, 0, 1, 1, MapGen.PAL_ARID, 4106, 0, 0, [2, 2, 0], "punic_hill"],
	[MapGen.PLAN_OPPIDUM, Terrain.K_RIDGE, 0, 1, 1, MapGen.PAL_GREEN, 4107, 3, 7, [3, 3, 3], "oppidum_spur"],
	[MapGen.PLAN_OPPIDUM, Terrain.K_FLAT, 0, 2, 3, MapGen.PAL_GREEN, 4108, 0, 0, [3, 3, 0], "oppidum_plain"],
	[MapGen.PLAN_OPPIDUM, Terrain.K_ROLLING, 0, 0, 1, MapGen.PAL_GREEN, 4109, 3, -1, [3, 3, 3], "oppidum_village"],
	[MapGen.PLAN_RING, Terrain.K_HILL, 0, 2, 3, MapGen.PAL_ROCKY, 4110, 0, -2, [0, 0, 0], "ring_hill"],
]

var _out := "/tmp"
var _queue: Array = []
var _vp: SubViewport
var _wait := 0
var _cur := ""


func _init() -> void:
	var seeds := [1234]
	var kinds := [1]
	var grid := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.get_slice("=", 1)
		elif a.begins_with("--seed="):
			seeds = []
			for s in a.get_slice("=", 1).split(","):
				seeds.append(int(s))
		elif a.begins_with("--kind="):
			kinds = [int(a.get_slice("=", 1))]
		elif a == "--grid":
			grid = true
	if grid:
		_dump_grids(seeds, kinds)
		quit(0)
		return
	_queue = CASES.duplicate(true)


func _process(_delta: float) -> bool:
	if _queue.is_empty() and _vp == null:
		return true
	if _vp != null:
		_wait -= 1
		if _wait > 0:
			return false
		var img := _vp.get_texture().get_image()
		var path := "%s/settlements_%s.png" % [_out, _cur]
		img.save_png(path)
		print("saved ", path, " ", img.get_size())
		_vp.queue_free()
		_vp = null
		return false
	var cs: Array = _queue.pop_front()
	var c := {"seed": cs[6], "level": cs[3], "walls": cs[4], "bld": [1, 2, 3, 4, 5], "def": 1, "plan": cs[0],
		"coast": cs[2], "owner": cs[7], "banner": cs[8], "hstyle": cs[9], "bstyle": [cs[7], cs[7], cs[7], cs[7], cs[7]]}
	if int(cs[0]) < MapGen.PLAN_RING:
		c["founder"] = cs[0]
	var terr := {"kind": cs[1], "seed": int(cs[6]) * 7 + 3, "forest": MapGen.PALETTE_FOREST[int(cs[5])],
		"ground": cs[5], "city": c}
	var t0 := Time.get_ticks_usec()
	var data := CityPreview.make(terr)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var crop: Rect2 = data["crop"]
	var w := 1100
	var h := int(w * crop.size.y / crop.size.x)
	_vp = SubViewport.new()
	_vp.size = Vector2i(w, h)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var prev := CityPreview.new()
	prev.data = data
	prev.size = Vector2(w, h)
	_vp.add_child(prev)
	root.add_child(_vp)
	_cur = cs[10]
	_wait = 3
	print("%s: %s, built in %.0f ms" % [cs[10], MapGen.describe(cs[0], cs[3], cs[1], cs[6], cs[2]), ms])
	return false


func _dump_grids(seeds: Array, kinds: Array) -> void:
	for sd in seeds:
		for lv in [[0, 0], [0, 1], [1, 0], [1, 1], [2, 2], [2, 3]]:
			var c := {"seed": sd, "level": lv[0], "walls": lv[1], "bld": [1, 2, 4], "def": 1}
			var fs := MapGen.city_field(c, 300, 110)
			var terr := {"kind": kinds[0], "seed": sd, "forest": 30, "city": c}
			var t0 := Time.get_ticks_usec()
			var t := Terrain.build(terr, sd, fs.x * 1024, fs.y * 1024)
			var t1 := Time.get_ticks_usec()
			var f := MapGen.build(terr, sd, fs.x, fs.y, t)
			var t2 := Time.get_ticks_usec()
			_render(f, t, fs, "%s/city_%d_%d_%d.png" % [_out, lv[0], lv[1], sd])
			var lay: Dictionary = f["city"]
			print("  graph components: ", _components(lay["nav"]))
			print("level %d walls %d seed %d: field %dx%d m, heights %.1f ms, map %.1f ms, %d buildings, %d gates, %d segs, %d nav nodes, %d edges" % [
				lv[0], lv[1], sd, fs.x, fs.y, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0,
				(lay["buildings"] as Array).size(), (lay["gates"] as Array).size(), (lay["segs"] as Array).size(),
				(lay["nav"]["x"] as PackedInt32Array).size(), (lay["nav"]["to"] as PackedInt32Array).size() / 2])


func _components(nav: Dictionary) -> String:
	var n: int = (nav["x"] as PackedInt32Array).size()
	var e0: PackedInt32Array = nav["e0"]
	var to: PackedInt32Array = nav["to"]
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var nc := 0
	for s in n:
		if comp[s] >= 0:
			continue
		var stack := [s]
		comp[s] = nc
		while not stack.is_empty():
			var v: int = stack.pop_back()
			for e in range(e0[v], e0[v + 1]):
				if comp[to[e]] < 0:
					comp[to[e]] = nc
					stack.append(to[e])
		nc += 1
	var sizes := []
	for c in nc:
		sizes.append(comp.count(c))
	return str(sizes)


func _render(f: Dictionary, t: Dictionary, fs: Vector2i, path: String) -> void:
	var img := Image.create(fs.x, fs.y, false, Image.FORMAT_RGB8)
	var vw: int = f["vw"]
	var veg: PackedByteArray = f["veg"]
	var ow: int = f["ow"]
	var obs: PackedByteArray = f["obs"]
	var h: PackedInt32Array = t["h"]
	var nx: int = t["nx"]
	var hmax := 1
	for v in h:
		hmax = maxi(hmax, v)
	for y in fs.y:
		for x in fs.x:
			var hv: int = h[mini(y / 4, int(t["ny"]) - 1) * nx + mini(x / 4, nx - 1)]
			var c: Color = COL[0].darkened(0.25 - 0.4 * hv / float(hmax))
			var vb: int = veg[(y / 4) * vw + x / 4]
			var d := vb & 3
			if (vb & MapGen.V_FIELD) != 0:
				c = Color(0.75, 0.7, 0.4)
			if (vb & MapGen.V_URBAN) != 0:
				c = c.lerp(Color(0.7, 0.65, 0.55), 0.5)
			if (vb & MapGen.V_PLAZA) != 0:
				c = Color(0.85, 0.8, 0.7)
			if d > 0:
				c = c.lerp(Color(0.1, 0.3, 0.1), 0.25 * d)
			if ow > 0:
				var k: int = obs[(y / 2) * ow + x / 2]
				if k >= 8:
					c = Color(0.9, 0.2, 0.1)
				elif k > 0:
					c = COL[k]
			img.set_pixel(x, y, c)
	if f.has("city"):
		var nav: Dictionary = f["city"]["nav"]
		var xs: PackedInt32Array = nav["x"]
		var ys: PackedInt32Array = nav["y"]
		var e0: PackedInt32Array = nav["e0"]
		var to: PackedInt32Array = nav["to"]
		for a in xs.size():
			for e in range(e0[a], e0[a + 1]):
				var b := to[e]
				for q in 20:
					var px := xs[a] + (xs[b] - xs[a]) * q / 20
					var py := ys[a] + (ys[b] - ys[a]) * q / 20
					if px >= 0 and py >= 0 and px < fs.x and py < fs.y:
						img.set_pixel(px, py, Color(0.2, 0.4, 1.0))
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var qx := xs[a] + dx
					var qy := ys[a] + dy
					if qx >= 0 and qy >= 0 and qx < fs.x and qy < fs.y:
						img.set_pixel(qx, qy, Color(1, 1, 0))
	img.resize(fs.x * 2, fs.y * 2, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
