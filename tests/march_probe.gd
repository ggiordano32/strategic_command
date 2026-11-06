extends SceneTree
## Filtering always on (docs/design/battle_sim.md "Filtering always on (as built, 2026-11-06)"): the march probe.
## Friendly units marching close by, no AI (a far enemy only so the battle runs). Prints per case: the closest two
## men of two different units came over the march, man-ticks with two such men within 0.4 m and within 0.25 m,
## the tick every unit's anchor arrived and the tick every man stood within 0.3 m of his place.
##   beside   two musket lines marching 80 m side by side, their flank files 0.4 m apart (centre to centre)
##   squeeze  the same with their flank files on the same line (the places overlap by a file)
##   column   a line marching 80 m with a column of 5 files 0.3 m behind its rear rank, both stopping at once
##   street   four units of 60 musketeers ordered from outside a walls-0 oppidum to its plaza (no enemy near)
##   godot --headless --script res://tests/march_probe.gd [-- --only=beside|squeeze|column|street]
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const MapGen := preload("res://sim/mapgen.gd")
const Terrain := preload("res://sim/terrain.gd")
const FM := preload("res://sim/fixed_math.gd")
const M := 1024
const UP := 768
const DOWN := 256


func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	for c in ["beside", "squeeze", "column", "street"]:
		if only != "" and only != c:
			continue
		var r := run_case(c)
		print("%-8s closest %4.2f m  under 0.4 m %5d man-ticks  under 0.25 m %5d  anchors in %5.1f s  formed in %5.1f s  sep man-steps %d" % [
			c, r["closest"] / float(M), r["in40"], r["in25"], r["arr"] / 10.0, r["formed"] / 10.0, r["sep"]])
	quit(0)


static func scenario(c: String) -> Dictionary:
	var mus := UT.index_of("musketeers")
	var fsp: int = UT.stat(mus, "file_sp")
	var rsp: int = UT.stat(mus, "rank_sp")
	var hw: int = 24 * fsp / 2
	var units := []
	var orders := []
	if c == "beside" or c == "squeeze":
		var gap: int = 2 * hw + (M * 4 / 10 if c == "beside" else 0)
		var x0: int = 150 * M - gap / 2
		var x1: int = x0 + gap
		units = [Scenarios.unit(0, mus, 100, 0, 240, UP, 25), Scenarios.unit(0, mus, 100, 0, 240, UP, 25),
			Scenarios.unit(1, mus, 20, 150, 20, DOWN, 10)]
		units[0]["x_m"] = 0
		units[1]["x_m"] = 0
		var sc := {"width_m": 300, "height_m": 300, "ai_sides": [], "units": units}
		sc["units"][0]["x_mm"] = x0
		sc["units"][1]["x_mm"] = x1
		orders = [BattleSim.make_move_order(5, 0, x0, 160 * M, UP, 25 * fsp, 0),
			BattleSim.make_move_order(5, 1, x1, 160 * M, UP, 25 * fsp, 0)]
		sc["orders"] = orders
		sc["place_mm"] = [[0, x0, 240 * M], [1, x1, 240 * M]]
		return sc
	if c == "column":
		var cfsp: int = fsp
		var back: int = 3 * rsp + M * 3 / 10  # (the line 4 ranks deep: the column's front 0.3 m behind its rear rank)
		units = [Scenarios.unit(0, mus, 100, 150, 240, UP, 25), Scenarios.unit(0, mus, 100, 150, 240, UP, 5),
			Scenarios.unit(1, mus, 20, 150, 20, DOWN, 10)]
		var sc2 := {"width_m": 300, "height_m": 300, "ai_sides": [], "units": units}
		sc2["place_mm"] = [[0, 150 * M, 240 * M], [1, 150 * M, 240 * M + back]]
		sc2["orders"] = [BattleSim.make_move_order(5, 0, 150 * M, 160 * M, UP, 25 * fsp, 0),
			BattleSim.make_move_order(5, 1, 150 * M, 160 * M + back, UP, 5 * cfsp, 0)]
		return sc2
	# street
	var city := {"seed": 21, "level": 1, "walls": 0, "bld": [1, 2], "plan": MapGen.PLAN_OPPIDUM, "founder": MapGen.CUL_CELTIC}
	var terr := {"kind": Terrain.K_FLAT, "seed": 11, "forest": 0, "ground": MapGen.PAL_GREEN}
	var att := [[mus, 60], [mus, 60], [mus, 60], [mus, 60]]
	var sc3: Dictionary = Scenarios.settlement(city, terr, att, [[UT.JAVELIN, 10]], 1, [], {})["scenario"]
	sc3["deploy_zones"] = []
	sc3["street"] = 1
	return sc3


static func make_sim(c: String) -> Object:
	var sc := scenario(c)
	var sim := BattleSim.new()
	sim.setup(sc, 7)
	for pm in sc.get("place_mm", []):
		_place(sim, int(pm[0]), int(pm[1]), int(pm[2]))
	if c == "street":
		# The defenders' javelinmen (there so the battle runs) off to the far corner, out of everyone's way; every
		# side-0 unit to the plaza (side by side across it, 8 m apart).
		for u in sim.n_units:
			if sim.u_side[u] == 1:
				_place(sim, u, 12 * M, 12 * M)
		var k := 0
		for u in sim.n_units:
			if sim.u_side[u] == 0:
				var fsp: int = sim.t_fsp[sim.u_type[u]]
				var gx: int = sim.plaza[0] + (k - 1) * 8 * M - 4 * M
				sim.queue_order(BattleSim.make_move_order(5, u, gx, sim.plaza[1], DOWN if sim.u_ay[u] > sim.plaza[1] else UP, 10 * fsp, 0))
				k += 1
	return sim


## Unit u's anchor and men to (x, y) exactly (the scenario's metres are too coarse for 0.4 m).
static func _place(sim, u: int, x: int, y: int) -> void:
	var dx: int = x - sim.u_ax[u]
	var dy: int = y - sim.u_ay[u]
	sim.u_ax[u] += dx
	sim.u_ay[u] += dy
	sim.u_cx[u] += dx
	sim.u_cy[u] += dy
	sim.u_minx[u] += dx
	sim.u_maxx[u] += dx
	sim.u_miny[u] += dy
	sim.u_maxy[u] += dy
	var b: int = sim.u_slot_base[u]
	for s in sim.u_alive[u]:
		var i: int = sim.slot_soldier[b + s]
		sim.pos_x[i] += dx
		sim.pos_y[i] += dy


static func run_case(c: String) -> Dictionary:
	var sim = make_sim(c)
	var side0 := []
	for u in sim.n_units:
		if sim.u_side[u] == 0:
			side0.append(u)
	var closest := 1 << 30
	var in40 := 0
	var in25 := 0
	var arr := -1
	var formed := -1
	for t in 4000:
		sim.step()
		if t < 6:
			continue
		for a in side0.size():
			for b in range(a + 1, side0.size()):
				var u: int = side0[a]
				var v: int = side0[b]
				if sim.u_minx[u] > sim.u_maxx[v] + M or sim.u_minx[v] > sim.u_maxx[u] + M \
						or sim.u_miny[u] > sim.u_maxy[v] + M or sim.u_miny[v] > sim.u_maxy[u] + M:
					continue
				var bu: int = sim.u_slot_base[u]
				var bv: int = sim.u_slot_base[v]
				for s in sim.u_alive[u]:
					var i: int = sim.slot_soldier[bu + s]
					for q in sim.u_alive[v]:
						var j: int = sim.slot_soldier[bv + q]
						var dx: int = sim.pos_x[i] - sim.pos_x[j]
						var dy: int = sim.pos_y[i] - sim.pos_y[j]
						if absi(dx) < M and absi(dy) < M:
							var d := FM.approx_len(dx, dy)
							closest = mini(closest, d)
							if d < M * 4 / 10:
								in40 += 1
							if d < M / 4:
								in25 += 1
		if arr < 0:
			var all_in := true
			for u in side0:
				if sim.u_order[u] != BattleSim.O_NONE:
					all_in = false
			if all_in:
				arr = sim.tick
		if arr >= 0 and formed < 0:
			var ok := true
			for u in side0:
				for s in sim.u_alive[u]:
					var k: int = sim.u_slot_base[u] + s
					var i: int = sim.slot_soldier[k]
					if FM.approx_len(sim.u_ax[u] + sim.off_x[k] - sim.pos_x[i], sim.u_ay[u] + sim.off_y[k] - sim.pos_y[i]) > M * 3 / 10:
						ok = false
						break
				if not ok:
					break
			if ok:
				formed = sim.tick
		if formed >= 0 and sim.tick > formed + 30:
			break
	var sep := 0
	if "stat_sep_men" in sim:
		sep = sim.stat_sep_men
	return {"closest": closest, "in40": in40, "in25": in25, "arr": arr, "formed": formed, "sep": sep}
