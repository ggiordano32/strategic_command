extends SceneTree
## Headless check of the sea's CPU wave twin (game/campaign/sea_waves.gd): finite,
## inside the documented bound, gust patches really vary, hash/vnoise sane.
## Run: godot --headless --script res://tests/sea_waves_test.gd
const SW := preload("res://game/campaign/sea_waves.gd")

var _fails := 0


func _check(ok: bool, msg: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL ", msg)


func _init() -> void:
	var wind := Vector2(0.7071, 0.7071)
	var mx := 0.0
	var gmin := 9.0
	var gmax := -9.0
	var vmin := 9.0
	var vmax := -9.0
	var finite := true
	for ix in 60:
		for iy in 30:
			var p := Vector2(ix * 47.3, iy * 51.7)
			var tm := float(ix * 7 + iy) * 1.3
			var h := SW.height(p, tm, wind)
			var n := SW.normal(p, tm, wind)
			if is_nan(h) or is_inf(h) or is_nan(n.x) or absf(n.length() - 1.0) > 0.001:
				finite = false
			mx = maxf(mx, absf(h))
			var f := SW.field(p, tm, wind)
			gmin = minf(gmin, f[0])
			gmax = maxf(gmax, f[0])
			vmin = minf(vmin, f[1])
			vmax = maxf(vmax, f[1])
	_check(finite, "height / normal finite, normal unit")
	_check(mx <= 2.0, "|h| <= 2.0 (got %f)" % mx)
	_check(mx > 0.5, "open sea has waves (got %f)" % mx)
	_check(gmin < 0.45 and gmax > 0.95, "gust has calm and rough patches (%f .. %f)" % [gmin, gmax])
	_check(vmin < -0.1 and vmax > 0.1 and absf(vmin) <= 0.4 and vmax <= 0.4, "veer within +-0.4 rad (%f .. %f)" % [vmin, vmax])
	# hash(1, 2) by hand: p3 = fract(vec3(1, 2, 1) * 0.1031) = (0.1031, 0.2062, 0.1031);
	# d = 0.1031 * 33.5362 + 0.2062 * 33.4331 + 0.1031 * 33.5362 + ... see below
	var a := 0.1031
	var b := 0.2062
	var d := a * (b + 33.33) + b * (a + 33.33) + a * (a + 33.33)
	var want := fmod((a + d + b + d) * (a + d), 1.0)
	_check(absf(SW._hash(Vector2(1, 2)) - want) < 1e-6, "hash(1,2) = %f, got %f" % [want, SW._hash(Vector2(1, 2))])
	_check(absf(SW.vnoise(Vector2(3, 4)) - SW._hash(Vector2(3, 4))) < 1e-9, "vnoise at a lattice point is the hash")
	print("max |h| ", mx, " gust ", gmin, "..", gmax, " veer ", vmin, "..", vmax)
	print("RESULT: ", "PASS" if _fails == 0 else "FAIL")
	quit(1 if _fails > 0 else 0)
