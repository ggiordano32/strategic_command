extends SceneTree
## The countermarch walks (docs/design/battle_sim.md "The countermarch (as built, 2026-11-02)"): a probe. A West
## musket line (no AI, side 0) shoots a target 70 m off for two minutes; prints the shots and hits of each minute,
## the men who fired, how many men walked to the rear (stat_cm_files), the closest two men of the line came and the
## line's footprint drift (its box's middle and size at the start and the end). Cases: 100 men in 4 ranks at a
## deep pike block (900 men, so it stands the two minutes); 98 and 90 men (a partial rank); 100 against a musket line that shoots back (men fall, ranks shrink).
## --png=DIR writes top-view dot pictures of the line during its first rolling cycle.
##   godot --headless --script res://tests/cm_probe.gd [-- --png=DIR]
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const FM := preload("res://sim/fixed_math.gd")
const M := 1024
const UP := 768
const DOWN := 256

var png := ""


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--png="):
			png = a.substr(6)
	var mus := UT.index_of("musketeers")
	var pk := UT.index_of("w_pikemen")
	_run("100 at pikes", [Scenarios.unit(0, mus, 100, 150, 200, UP, 25), Scenarios.unit(1, pk, 900, 150, 130, DOWN, 45)], true)
	_run("98 at pikes", [Scenarios.unit(0, mus, 98, 150, 200, UP, 25), Scenarios.unit(1, pk, 900, 150, 130, DOWN, 45)], false)
	_run("90 at pikes", [Scenarios.unit(0, mus, 90, 150, 200, UP, 25), Scenarios.unit(1, pk, 900, 150, 130, DOWN, 45)], false)
	_run("100 duel", [Scenarios.unit(0, mus, 100, 150, 200, UP, 25), Scenarios.unit(1, mus, 100, 150, 130, DOWN, 25)], false)
	quit(0)


func _run(name: String, units: Array, shots: bool) -> void:
	var sim := BattleSim.new()
	sim.setup({"width_m": 300, "height_m": 300, "ai_sides": [], "units": units, "orders": []}, 31)
	var per_min := [0, 0]
	var hits := [0, 0]
	var fired := {}
	var closest := 1 << 30
	var box0 := []
	var b0: int = sim.u_slot_base[0]
	var n0: int = sim.u_count0[0]
	var mk := 0
	for t in 1200:
		var sh0: int = sim.stat_shots
		var k0: int = sim.u_killed[1]
		var am := sim.ammo.slice(b0, b0 + n0)
		sim.step()
		per_min[t / 600] += sim.stat_shots - sh0
		hits[t / 600] += sim.u_killed[1] - k0
		for k in n0:
			if sim.ammo[b0 + k] < am[k]:
				fired[k] = 1
		if t == 5:
			box0 = [sim.u_cx[0], sim.u_cy[0], sim.u_maxx[0] - sim.u_minx[0], sim.u_maxy[0] - sim.u_miny[0]]
		if (t % 5) == 0 and t > 100:
			closest = mini(closest, _closest(sim, 0))
		if shots and png != "" and mk < 8 and sim.stat_cm_rank >= 1 and (t % 6) == 0:
			_shot(sim, "%s/cm_%d_t%04d.png" % [png, mk, t])
			mk += 1
	print("    %s: side 0 lost %d, side 1 lost %d, states %d / %d, shots %d, volleys %d, rank %d, full %d" % [name, sim.u_killed[0], sim.u_killed[1], sim.u_state[0], sim.u_state[1], sim.stat_shots, sim.stat_volleys, sim.stat_cm_rank, sim.stat_cm_full])
	print("%-14s shots/min %d, %d  kills/min %d, %d  men fired %d of %d  walked %d  closest %.2f m  box (%.1f, %.1f) %.1f x %.1f m -> (%.1f, %.1f) %.1f x %.1f m" % [
		name, per_min[0], per_min[1], hits[0], hits[1], fired.size(), n0, sim.stat_cm_files if "stat_cm_files" in sim else -1,
		closest / float(M), box0[0] / float(M), box0[1] / float(M), box0[2] / float(M), box0[3] / float(M),
		sim.u_cx[0] / float(M), sim.u_cy[0] / float(M), (sim.u_maxx[0] - sim.u_minx[0]) / float(M), (sim.u_maxy[0] - sim.u_miny[0]) / float(M)])


func _closest(sim, u: int) -> int:
	var b: int = sim.u_slot_base[u]
	var best := 1 << 30
	var a: int = sim.u_alive[u]
	for s in a:
		var i: int = sim.slot_soldier[b + s]
		for q in range(s + 1, a):
			var j: int = sim.slot_soldier[b + q]
			var dx: int = sim.pos_x[i] - sim.pos_x[j]
			var dy: int = sim.pos_y[i] - sim.pos_y[j]
			if absi(dx) < M and absi(dy) < M:
				best = mini(best, FM.approx_len(dx, dy))
	return best


## Top view of 36 x 14 m round the line, 16 px a metre: the front rank light, the men walking to the rear dark.
func _shot(sim, path: String) -> void:
	var x0 := 132 * M
	var y0 := 195 * M
	var pxm := 16
	var img := Image.create(576, 224, false, Image.FORMAT_RGB8)
	img.fill(Color(0.85, 0.82, 0.7))
	var b: int = sim.u_slot_base[0]
	var files: int = sim.files_of(0)
	for s in sim.u_alive[0]:
		var i: int = sim.slot_soldier[b + s]
		var col := Color(0.15, 0.25, 0.8)
		if s < files:
			col = col.lightened(0.45)
		if "s_rtw" in sim and sim.s_rtw.size() > i and sim.s_rtw[i] != 0:
			col = Color(0.05, 0.05, 0.2)
		var cx: int = (sim.pos_x[i] - x0) * pxm / M
		var cy: int = (sim.pos_y[i] - y0) * pxm / M
		for yy in range(-5, 6):
			for xx in range(-5, 6):
				if xx * xx + yy * yy <= 24 and cx + xx >= 0 and cx + xx < 576 and cy + yy >= 0 and cy + yy < 224:
					img.set_pixel(cx + xx, cy + yy, col)
	img.save_png(path)
