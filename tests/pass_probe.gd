extends SceneTree
## Filtering through a friendly unit (docs/design/battle_sim.md "Filtering through a friendly unit"): a probe.
## A unit of side 0 ordered through a standing friendly unit 40 m ahead, to a place 40 m beyond it; no AI, no enemy
## (a far enemy only so the battle runs). Prints per case: the pass time against the same move with the field
## clear, the closest two men of the two units came, man-ticks with two men of the two units within 0.5 m (inside
## one another), the standing unit's men off their places (most during, at the end), the moving unit's men off their
## places at the end and whether any slot changed hands. --png=DIR writes top-view dot pictures at a few moments.
##   godot --headless --script res://tests/pass_probe.gd [-- --png=DIR --only=line|column|cav|foot_cav|pikes]
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const FM := preload("res://sim/fixed_math.gd")
const M := 1024
const UP := 768
const DOWN := 256

var png := ""


func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--png="):
			png = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7)
	var cases := [
		["line", "musketeers", 100, 25, "musketeers", 100, 25],
		["column", "musketeers", 100, 5, "musketeers", 100, 25],
		["cav", "lancers", 60, 15, "musketeers", 100, 25],
		["foot_cav", "musketeers", 100, 25, "lancers", 60, 15],
		["rome", "heavy", 120, 30, "heavy", 120, 30],
		["pikes", "musketeers", 100, 25, "w_pikemen", 120, 30],
	]
	for c in cases:
		if only != "" and only != c[0]:
			continue
		var base := _run(c, false)
		var r := _run(c, true)
		print("%-8s pass %5.1f s (clear %5.1f s)  closest %4.2f m  inside %5d man-ticks (%d under 0.25 m, %d at worst)  standing off >0.3 m: most %4.2f m, %d men at end; mover off at end %d; slots swapped %d / %d" % [
			c[0], r["t"] / 10.0, base["t"] / 10.0, r["closest"] / float(M), r["inside"], r["deep"], r["worst"], r["dev"] / float(M), r["st_off"],
			r["mv_off"], r["sw_s"], r["sw_m"]])
	quit(0)


func _sc(c: Array, with_st: bool) -> Dictionary:
	var units := [Scenarios.unit(0, UT.index_of(c[1]), c[2], 150, 240, UP, c[3])]
	if with_st:
		units.append(Scenarios.unit(0, UT.index_of(c[4]), c[5], 150, 200, UP, c[6]))
	units.append(Scenarios.unit(1, UT.index_of("musketeers"), 20, 150, 20, DOWN, 10))
	var w: int = mini(c[3], c[2]) * UT.stat(UT.index_of(c[1]), "file_sp")
	return {"width_m": 300, "height_m": 300, "ai_sides": [], "units": units,
		"orders": [BattleSim.make_move_order(5, 0, 150 * M, 160 * M, UP, w, 0)]}


func _run(c: Array, with_st: bool) -> Dictionary:
	var sim := BattleSim.new()
	sim.setup(_sc(c, with_st), 7)
	var closest := 1 << 30
	var inside := 0
	var deep := 0
	var worst := 0
	var dev := 0
	var done := -1
	var ss0 := sim.slot_soldier.duplicate()
	var marks := [207, 203, 199, 195, 190, 180]
	var mk := 0
	for t in 1500:
		sim.step()
		var ins0 := inside
		if with_st:
			var b0: int = sim.u_slot_base[0]
			var b1: int = sim.u_slot_base[1]
			for s in sim.u_alive[0]:
				var i: int = sim.slot_soldier[b0 + s]
				for q in sim.u_alive[1]:
					var j: int = sim.slot_soldier[b1 + q]
					var dx: int = sim.pos_x[i] - sim.pos_x[j]
					var dy: int = sim.pos_y[i] - sim.pos_y[j]
					if absi(dx) < 2 * M and absi(dy) < 2 * M:
						var d := FM.approx_len(dx, dy)
						closest = mini(closest, d)
						if d < M / 2:
							inside += 1
						if d < M / 4:
							deep += 1
			for q in sim.u_alive[1]:
				dev = maxi(dev, _off(sim, 1, q))
			if png != "" and inside - ins0 > worst:
				worst = inside - ins0
				_shot(sim, "%s/%s_worst.png" % [png, c[0]])
		if png != "" and with_st and mk < marks.size() and sim.u_ay[0] <= marks[mk] * M:
			_shot(sim, "%s/%s_%d_%d.png" % [png, c[0], mk, marks[mk]])
			mk += 1
		if done < 0 and sim.tick > 10 and sim.u_order[0] == BattleSim.O_NONE:
			var ok := true
			for s in sim.u_alive[0]:
				if _off(sim, 0, s) > M / 3:
					ok = false
					break
			if ok:
				done = sim.tick
		if done >= 0 and sim.tick > done + 50:
			break
	var st_off := 0
	var mv_off := 0
	var sw_s := 0
	var sw_m := 0
	for s in sim.u_alive[0]:
		if _off(sim, 0, s) > M * 3 / 10:
			mv_off += 1
		if sim.slot_soldier[sim.u_slot_base[0] + s] != ss0[sim.u_slot_base[0] + s]:
			sw_m += 1
	if with_st:
		for s in sim.u_alive[1]:
			if _off(sim, 1, s) > M * 3 / 10:
				st_off += 1
			if sim.slot_soldier[sim.u_slot_base[1] + s] != ss0[sim.u_slot_base[1] + s]:
				sw_s += 1
	return {"t": done if done >= 0 else 9999, "closest": closest, "inside": inside, "deep": deep, "worst": worst, "dev": dev, "st_off": st_off,
		"mv_off": mv_off, "sw_s": sw_s, "sw_m": sw_m}


func _off(sim, u: int, s: int) -> int:
	var k: int = sim.u_slot_base[u] + s
	var i: int = sim.slot_soldier[k]
	return FM.approx_len(sim.u_ax[u] + sim.off_x[k] - sim.pos_x[i], sim.u_ay[u] + sim.off_y[k] - sim.pos_y[i])


## Top view of the 44 x 32 m round the pass, 14 px a metre: the mover blue (its front rank lighter), the standing
## unit red, each man a disc of 0.35 m.
func _shot(sim, path: String) -> void:
	var x0 := 128 * M
	var y0 := 182 * M
	var pxm := 14
	var img := Image.create(616, 448, false, Image.FORMAT_RGB8)
	img.fill(Color(0.85, 0.82, 0.7))
	for u in 2:
		if u >= sim.n_units or sim.u_side[u] != 0:
			continue
		var b: int = sim.u_slot_base[u]
		var files: int = sim.files_of(u)
		for s in sim.u_alive[u]:
			var i: int = sim.slot_soldier[b + s]
			var col := Color(0.15, 0.25, 0.8) if u == 0 else Color(0.8, 0.15, 0.1)
			if s < files:
				col = col.lightened(0.45)
			var cx: int = (sim.pos_x[i] - x0) * pxm / M
			var cy: int = (sim.pos_y[i] - y0) * pxm / M
			for yy in range(-5, 6):
				for xx in range(-5, 6):
					if xx * xx + yy * yy <= 24 and cx + xx >= 0 and cx + xx < 616 and cy + yy >= 0 and cy + yy < 448:
						img.set_pixel(cx + xx, cy + yy, col)
	img.save_png(path)
