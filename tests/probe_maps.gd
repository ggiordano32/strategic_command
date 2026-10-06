extends SceneTree
## Dev probe: run woods / settlement scenarios AI vs AI and print what
## happened (paths, clamps, gates, capture, winner) and the time per tick.
##   godot --headless --script res://tests/probe_maps.gd -- --scen=siege_town --ticks=3000

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")


func _init() -> void:
	var scens := ["test_woods", "siege_village", "siege_town", "siege_city", "siege_hill"]
	var ticks := 3000
	var sd := 7
	var shots: Array = []
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--png="):
			for t in a.get_slice("=", 1).split(","):
				shots.append(int(t))
		elif a.begins_with("--out="):
			out = a.get_slice("=", 1)
		if a.begins_with("--scen="):
			scens = a.get_slice("=", 1).split(",")
		elif a.begins_with("--ticks="):
			ticks = int(a.get_slice("=", 1))
		elif a.begins_with("--seed="):
			sd = int(a.get_slice("=", 1))
	for scen in scens:
		var sc := Scenarios.make(scen)
		sc["ai_sides"] = [0, 1]
		var sim := BattleSim.new()
		var t0 := Time.get_ticks_usec()
		sim.setup(sc, sd)
		var setup_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var worst := 0.0
		var total := 0.0
		var n := 0
		var broke := -1
		var cap_start := -1
		for t in ticks:
			var s := Time.get_ticks_usec()
			sim.step()
			var ms := (Time.get_ticks_usec() - s) / 1000.0
			worst = maxf(worst, ms)
			total += ms
			n += 1
			if broke < 0 and sim.stat_gate_broken > 0:
				broke = sim.tick
			if cap_start < 0 and sim.cap_t > 0:
				cap_start = sim.tick
			if sim.tick in shots:
				_png(sim, "%s/%s_%d.png" % [out, scen, sim.tick])
			if sim.ended != 0:
				break
		var gates := []
		for g in sim.n_gates:
			gates.append("%d:%d/%d" % [sim.g_state[g], sim.g_hp[g] / 100, sim.g_hp0[g] / 100])
		print("%s: %d soldiers, field %dx%d, setup %.1f ms, ticks %d, mean %.2f ms, max %.1f ms, winner %d decided %d, alive %d/%d" % [
			scen, sim.n, sim.field_w / 1024, sim.field_h / 1024, setup_ms, n, total / n, worst, sim.winner,
			sim.decided_tick, sim.alive_count(0), sim.alive_count(1)])
		print("  first gate broken at %d, plaza first held at %d" % [broke, cap_start])
		print("  gates %s cap_t %d paths %d clamp %d squeeze %d hack %d art %d closed %d broken %d capture %d" % [
			str(gates), sim.cap_t, sim.stat_paths, sim.stat_clamp, sim.stat_squeeze, sim.stat_gate_hack / 100,
			sim.stat_gate_art, sim.stat_gate_close, sim.stat_gate_broken, sim.stat_capture])
		print("  woods: slow %d dis %d stop %d tree_lof %d obs_lof %d wall_cover %d impact %d; kills %s" % [
			sim.stat_veg_slow, sim.stat_veg_dis, sim.stat_veg_stop, sim.stat_tree_lof, sim.stat_obs_lof,
			sim.stat_wall_cover, sim.stat_veg_impact, str(sim.stat_kills)])
	quit(0)


func _png(sim, path: String) -> void:
	var w: int = sim.field_w / 1024
	var h: int = sim.field_h / 1024
	var img := Image.create(w * 2, h * 2, false, Image.FORMAT_RGB8)
	img.fill(Color(0.55, 0.6, 0.45))
	for y in h * 2:
		for x in w * 2:
			var k: int = sim.obs_kind(x * 512, y * 512)
			var c := Color(0.55, 0.6, 0.45)
			var d: int = sim.veg_d(x * 512, y * 512)
			if d > 0:
				c = c.lerp(Color(0.1, 0.3, 0.1), 0.25 * d)
			if k == 1:
				c = Color(0.7, 0.45, 0.3)
			elif k == 2 or k == 4:
				c = Color(0.3, 0.3, 0.3)
			elif k == 3:
				c = Color(0.5, 0.5, 0.5)
			elif k >= 8:
				var st: int = sim.g_state[k - 8]
				c = Color(0.9, 0.1, 0.1) if st == 1 else (Color(0.9, 0.9, 0.1) if st == 2 else Color(0.2, 0.9, 0.2))
			img.set_pixel(x, y, c)
	for i in sim.n:
		if sim.state[i] >= 4:
			continue
		var x: int = sim.pos_x[i] / 512
		var y: int = sim.pos_y[i] / 512
		if x < 0 or y < 0 or x >= w * 2 or y >= h * 2:
			continue
		var u: int = sim.unit_of[i]
		var col := Color(0.1, 0.2, 1.0) if sim.u_side[u] == 0 else Color(1.0, 0.1, 0.1)
		if sim.state[i] == 2:
			col = Color(1, 1, 0)
		img.set_pixel(x, y, col)
	for u in sim.n_units:
		if sim.u_state[u] >= 2:
			continue
		var ax: int = sim.u_ax[u] / 512
		var ay: int = sim.u_ay[u] / 512
		for d in range(-2, 3):
			if ax + d >= 0 and ax + d < w * 2 and ay >= 0 and ay < h * 2:
				img.set_pixel(ax + d, ay, Color.WHITE)
			if ay + d >= 0 and ay + d < h * 2 and ax >= 0 and ax < w * 2:
				img.set_pixel(ax, ay + d, Color.WHITE)
	img.save_png(path)
	print("  saved ", path, " tick ", sim.tick, " cap_t ", sim.cap_t, " phases ", sim.ai_phase, " gate ", sim.ai_gate)
	for u in sim.n_units:
		if sim.u_state[u] < 2:
			print("    u%d side %d cls %d alive %d state %d order %d ai %d wall %d tgt %d gt %d at (%d,%d) d(%d,%d) pn %d pk %d sq %d" % [u, sim.u_side[u], sim.u_cls[u],
				sim.u_alive[u], sim.u_state[u], sim.u_order[u], sim.u_ai[u], sim.u_wall[u], sim.u_target[u], sim.u_gtarget[u],
				sim.u_ax[u] / 1024, sim.u_ay[u] / 1024, sim.u_dx[u] / 1024, sim.u_dy[u] / 1024, sim.u_pn[u], sim.u_pk[u], sim.u_sq[u]])
			if sim.u_pn[u] > 1:
				var wps := []
				for k in sim.u_pn[u]:
					wps.append("(%d,%d)" % [sim.pth_x[u * 24 + k] / 1024, sim.pth_y[u * 24 + k] / 1024])
				print("       path ", " ".join(wps), " trail %d cx (%d,%d) moved %d" % [sim.u_trn[u], sim.u_cx[u] / 1024, sim.u_cy[u] / 1024, sim.u_moved[u]])
