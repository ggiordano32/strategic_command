extends SceneTree
## Two units meeting at a hill line (docs/AI.md 48), scripted orders only.
## Grounds (custom terrain, 400 x 400 m; A at y = ya facing up, B at yb
## facing down, the line at y = 200):
##   flat   no relief
##   ramp   rising 6 m towards B over 16 m        steep  6 m over 8 m
##   crest  a 5 m ridge along x at y = 200          step   a 2 m terrace over 4 m
##   cliff  a generated ridge map (560 x 600 m, landforms on; terrain seeds
##          from 1 up with a cliff 70 m clear of the edges): the cliff cell
##          nearest the middle, A 50 m below it on its fall line, B 50 m above
## Modes: one (A attacks B, B has no order), both (each attacks the other),
## ai (A attacks, side 1 the AI's). Per run: the first tick a man of either
## fights (melee), men alive A / B at the end (T s), the centres' distance.
##   --ta=musketeers --tb=musketeers --ya=262 --yb=192 --grounds=crest,cliff
##   --modes=one --t=180 --cliffs=4 --verbose --off (HIDDEN_CLOSE_ON 0: before)
##   --check: the regression (crest and cliff, musketeers, mode one: B must
##   lose men; prints PASS / FAIL)
##   godot --headless --script res://tests/hill_probe.gd [-- ...]

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const Terrain := preload("res://sim/terrain.gd")
const MapGen := preload("res://sim/mapgen.gd")
const FM := preload("res://sim/fixed_math.gd")
const M := 1024

var ta := "heavy"
var tb := "heavy"
var ya := 240
var yb := 160
var t_end := 1800
var verbose := false


static func _feat(g: String) -> Array:
	match g:
		"ramp": return [[Terrain.F_RAMP, 200, 200, 8, 6, 768]]
		"steep": return [[Terrain.F_RAMP, 200, 200, 4, 6, 768]]
		"crest": return [[Terrain.F_RIDGE, 200, 200, 12, 5, 0, 300]]
		"step": return [[Terrain.F_RAMP, 200, 200, 2, 2, 768]]
	return []


static func _cliff_sc(tseed: int, units: Array, ai: Array) -> Dictionary:
	return {"width_m": 560, "height_m": 600, "ai_sides": ai, "orders": [], "units": units,
		"terrain": {"kind": Terrain.K_RIDGE, "seed": tseed}}


## The cliff case's scenario for terrain seed tseed, or {} (no cliff clear of the edges).
func _cliff_case(tseed: int, mode: String) -> Dictionary:
	var p := BattleSim.new()
	p.setup(_cliff_sc(tseed, [Scenarios.unit(0, UT.index_of("heavy"), 20, 50, 590, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.index_of("heavy"), 20, 50, 10, Scenarios.FACE_DOWN)], []), 7)
	var bi := -1
	var bdd := 1 << 40
	for j in p.ob_h:
		for i in p.ob_w:
			if p.obs[j * p.ob_w + i] != MapGen.C_CLIFF:
				continue
			var xm := i * 2 + 1
			var ym := j * 2 + 1
			if xm < 70 or xm > 490 or ym < 70 or ym > 530:
				continue
			var dd := (xm - 280) * (xm - 280) + (ym - 300) * (ym - 300)
			if dd < bdd:
				bdd = dd
				bi = j * p.ob_w + i
	if bi < 0:
		return {}
	var cx := (bi % p.ob_w) * 2 + 1
	var cy := (bi / p.ob_w) * 2 + 1
	var g: Vector2i = p.slope_at(cx * M, cy * M)
	var dn := FM.atan2_a(-g.y, -g.x)  # downhill
	var c := FM.cos_a(dn)
	var s := FM.sin_a(dn)
	var units := [Scenarios.unit(0, UT.index_of(ta), 100, cx + c * 50 / FM.TRIG_ONE, cy + s * 50 / FM.TRIG_ONE,
			(dn + 512) & FM.ANGLE_MASK),
		Scenarios.unit(1, UT.index_of(tb), 100, cx - c * 50 / FM.TRIG_ONE, cy - s * 50 / FM.TRIG_ONE, dn)]
	var hl := p.height_at((cx + c * 8 / FM.TRIG_ONE) * M, (cy + s * 8 / FM.TRIG_ONE) * M)
	var hh := p.height_at((cx - c * 8 / FM.TRIG_ONE) * M, (cy - s * 8 / FM.TRIG_ONE) * M)
	return {"sc": _cliff_sc(tseed, units, [1] if mode == "ai" else []),
		"info": "terrain seed %d, cliff at (%d, %d), ground 8 m below / above it %.1f / %.1f m" % [tseed, cx, cy,
			hl / 1024.0, hh / 1024.0]}


func _run(sc: Dictionary, mode: String) -> Dictionary:
	var sim := BattleSim.new()
	sim.setup(sc, 7)
	sim.queue_order(BattleSim.make_attack_order(0, 0, 1, 0))
	if mode == "both":
		sim.queue_order(BattleSim.make_attack_order(0, 1, 0, 0))
	var first := -1
	for tk in t_end:
		sim.step()
		if first < 0 and (sim.u_fighting[0] > 0 or sim.u_fighting[1] > 0):
			first = tk
		if verbose and (tk + 1) % 50 == 0:
			var d := FM.approx_len(sim.u_cx[1] - sim.u_cx[0], sim.u_cy[1] - sim.u_cy[0])
			print("  %3ds d %5.1f  A (%.0f, %.0f) h %4.1f order %d moved %3d fight %2d stuck %3d  B (%.0f, %.0f) h %4.1f order %d fight %2d seen %d  alive %d / %d" % [
				(tk + 1) / 10, d / 1024.0, sim.u_ax[0] / 1024.0, sim.u_ay[0] / 1024.0, sim.u_h[0] / 1024.0, sim.u_order[0],
				sim.u_moved[0], sim.u_fighting[0], sim.u_stuck[0], sim.u_cx[1] / 1024.0, sim.u_cy[1] / 1024.0,
				sim.u_h[1] / 1024.0, sim.u_order[1], sim.u_fighting[1], sim.u_seen[1] if sim.u_seen.size() > 1 else -1,
				sim.u_alive[0], sim.u_alive[1]])
	return {"first": first, "alive0": sim.u_alive[0], "alive1": sim.u_alive[1],
		"d": FM.approx_len(sim.u_cx[1] - sim.u_cx[0], sim.u_cy[1] - sim.u_cy[0])}


func _line(g: String, m: String, r: Dictionary) -> String:
	return "%-6s %-5s first melee %s  alive %3d / %3d  d end %5.1f m" % [g, m,
		"   -   " if r["first"] < 0 else "%5.1f s" % (r["first"] / 10.0), r["alive0"], r["alive1"], r["d"] / 1024.0]


func _init() -> void:
	var grounds := ["flat", "ramp", "steep", "crest", "step", "cliff"]
	var modes := ["one", "both", "ai"]
	var n_cliffs := 4
	var check := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--grounds="):
			grounds = arg.substr(10).split(",")
		elif arg.begins_with("--modes="):
			modes = arg.substr(8).split(",")
		elif arg.begins_with("--ta="):
			ta = arg.substr(5)
		elif arg.begins_with("--tb="):
			tb = arg.substr(5)
		elif arg.begins_with("--ya="):
			ya = int(arg.substr(5))
		elif arg.begins_with("--yb="):
			yb = int(arg.substr(5))
		elif arg.begins_with("--t="):
			t_end = int(arg.substr(4)) * 10
		elif arg.begins_with("--cliffs="):
			n_cliffs = int(arg.substr(9))
		elif arg == "--off":
			BattleSim.HIDDEN_CLOSE_ON = 0
		elif arg == "--verbose":
			verbose = true
		elif arg == "--check":
			check = true
	if check:
		ta = "musketeers"
		tb = "musketeers"
		ya = 262
		yb = 192
		grounds = ["crest", "cliff"]
		modes = ["one"]
		n_cliffs = 8
	var fails := 0
	for g in grounds:
		for m in modes:
			if g == "cliff":
				var done := 0
				var tseed := 1
				while done < n_cliffs and tseed < 60:
					var cc := _cliff_case(tseed, m)
					tseed += 1
					if cc.is_empty():
						continue
					done += 1
					if verbose:
						print("--- %s %s: %s" % [g, m, cc["info"]])
					var r := _run(cc["sc"], m)
					print("%s  (%s)" % [_line(g, m, r), cc["info"]])
					if check and r["alive1"] >= 100:
						fails += 1
						print("FAIL hill_probe: %s %s B lost no men (%s)" % [g, m, cc["info"]])
			else:
				var a := Scenarios.unit(0, UT.index_of(ta), 100, 200, ya, Scenarios.FACE_UP)
				var b := Scenarios.unit(1, UT.index_of(tb), 100, 200, yb, Scenarios.FACE_DOWN)
				var sc := {"width_m": 400, "height_m": 400, "ai_sides": [1] if m == "ai" else [], "orders": [],
					"units": [a, b], "terrain": {"kind": Terrain.K_FLAT if g == "flat" else Terrain.K_CUSTOM,
					"features": _feat(g)}}
				if verbose:
					print("--- %s %s" % [g, m])
				var r := _run(sc, m)
				print(_line(g, m, r))
				if check and r["alive1"] >= 100:
					fails += 1
					print("FAIL hill_probe: %s %s B lost no men" % [g, m])
	if check:
		print("RESULT hill_probe %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit()
