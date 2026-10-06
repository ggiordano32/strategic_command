extends SceneTree
## Dev tool: render generated battle maps (woods, settlements) to PNG.
##   godot --headless --script res://tools/city_dump.gd -- --out=/tmp/x --seed=N
## Writes city_<level>_<walls>_<seed>.png (2 px per metre) and prints
## generation times.

const MapGen := preload("res://sim/mapgen.gd")
const Terrain := preload("res://sim/terrain.gd")

const COL := {0: Color(0.62, 0.66, 0.48), 1: Color(0.72, 0.45, 0.32), 2: Color(0.35, 0.33, 0.30),
	3: Color(0.55, 0.53, 0.50), 4: Color(0.25, 0.24, 0.22)}


func _init() -> void:
	var out := "/tmp"
	var seeds := [1234]
	var kinds := [1]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
		elif a.begins_with("--seed="):
			seeds = []
			for s in a.get_slice("=", 1).split(","):
				seeds.append(int(s))
		elif a.begins_with("--kind="):
			kinds = [int(a.get_slice("=", 1))]
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
			_render(f, t, fs, "%s/city_%d_%d_%d.png" % [out, lv[0], lv[1], sd])
			var lay: Dictionary = f["city"]
			print("  graph components: ", _components(lay["nav"]))
			print("level %d walls %d seed %d: field %dx%d m, heights %.1f ms, map %.1f ms, %d buildings, %d gates, %d segs, %d nav nodes, %d edges" % [
				lv[0], lv[1], sd, fs.x, fs.y, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0,
				(lay["buildings"] as Array).size(), (lay["gates"] as Array).size(), (lay["segs"] as Array).size(),
				(lay["nav"]["x"] as PackedInt32Array).size(), (lay["nav"]["to"] as PackedInt32Array).size() / 2])
	quit(0)


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
