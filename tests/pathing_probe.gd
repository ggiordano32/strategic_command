extends SceneTree
## Pathing probe (docs/PATHING_SPEC.md, phase 0): AI vs AI battles on the
## settlement and landform maps, measuring how men move.
##   godot --headless --script res://tests/pathing_probe.gd [-- --ids=siege_town,siege_city]
##       [--ticks=6000] [--seed=7] [--phase=A] [--quick] [--west (the West towns only)]
##   an id "plan:<pack>:<region>:<level>:<walls>" is a campaign town's battle on its plan (plan:west:havana:2:1).
## Metrics:
## - Jitter: for each man, in each 2 s window, path = the sum of his steps
##   and net = his displacement; a man-window jitters when path >= 3 m and
##   net < path / 3. rev/step: the share of his steps that reverse the
##   previous one. walk/net: path over net summed. Grouped by unit state
##   (rout / move / fight / idle) and place (wall, stair1-3, town, nearobs,
##   field).
## - Routers that stay put: share of routing unit-seconds whose centroid
##   moved < 3 m in the last 10 s (huddled routers, u_hud, not counted).
## - Stuck time, routers included: the longest no-progress run of a ready
##   unit (stat_stuck_u: while none of its men is fighting, since the fight
##   jitter pass 2026-10-16) and of a router (centroid < 3 m in 10 s, counted
##   on from there, not huddled); runs over 30 s.
## - Men inside the drawn footprint of a building (the view's polygons,
##   map_info.city.buildings; ready ground units every 5 ticks, men within
##   6 m of a building) and within 0.3 m of a face.
## - Tick mean (ms).
## Thresholds (spec section 8) are checked at the end; --phase=A gates the
## exit code on the ones phase A must meet (rout jitter, stationary routers,
## stuck), the others are reported only.
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const MapGen := preload("res://sim/mapgen.gd")
const UT := preload("res://sim/unit_types.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const M := 1024
const W := 20  # jitter window (ticks)
const SCENS := ["siege_village", "siege_town", "siege_city", "siege_hill", "siege_castrum", "siege_polis",
	"siege_punic", "siege_oppidum", "battle_2000", "bench_4000_hills",
	# West open towns (phase W): villages, towns and cities, coasts and inland, flat to ridge country.
	"west_village", "west_town", "west_city", "west_inland", "west_port", "west_hill_village"]

var cats := {}      # category -> [man_windows, jitter, path_m, net_m, reversals, steps] (all runs)
var rout_s := 0     # routing unit-seconds (all runs)
var still_s := 0    # ... of them stationary (not huddled)
var stuck_max := 0  # ticks: longest ready-unit stuck run (all runs)
var rstuck_max := 0 # seconds: longest router stationary run
var stuck30 := 0    # runs over 30 s (ready units and routers)
var fp_n := 0
var fp_in := 0
var fp_c3 := 0
var tick_ms := []   # per run [id, mean ms]
var polys: Array = []
var buck := {}


func _init() -> void:
	var ids: Array = SCENS.duplicate()
	var ticks := 6000
	var sd := 7
	var phase := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ids="):
			ids = Array(a.get_slice("=", 1).split(","))
		elif a.begins_with("--ticks="):
			ticks = int(a.get_slice("=", 1))
		elif a.begins_with("--seed="):
			sd = int(a.get_slice("=", 1))
		elif a.begins_with("--phase="):
			phase = a.get_slice("=", 1)
		elif a == "--quick":
			ids = ["siege_town", "siege_city", "siege_castrum"]
		elif a == "--west":
			ids = ["west_village", "west_town", "west_city", "west_inland", "west_port", "west_hill_village"]
	for id in ids:
		_run(id, ticks, sd)
	var ok := _summary(phase)
	quit(0 if ok or phase == "" else 1)


func _cat(sim, u: int) -> String:
	var where := "field"
	if sim.obs_on != 0:
		if sim.u_wall[u] > 0:
			where = "wall"
		elif sim.u_stair[u] != 0:
			where = "stair%d" % sim.u_stair[u]
		elif (sim.veg_bits(sim.u_cx[u], sim.u_cy[u]) & MapGen.V_URBAN) != 0:
			where = "town"
		elif sim._u_obs[u] != 0:
			where = "nearobs"
	var what := "rout"
	if sim.u_state[u] == BattleSim.U_READY:
		what = "fight" if sim.u_contact[u] != 0 else ("move" if sim.u_order[u] != 0 else "idle")
	return what + "/" + where


func _add(dst: Dictionary, c: String, v: Array) -> void:
	if not dst.has(c):
		dst[c] = [0, 0, 0.0, 0.0, 0, 0]
	var a: Array = dst[c]
	for k in 6:
		a[k] += v[k]


func _huddled(sim, u: int) -> bool:
	return "u_hud" in sim and sim.u_hud.size() > u and sim.u_hud[u] != 0


func _setup_polys(sim) -> void:
	polys = []
	buck = {}
	var lay: Dictionary = sim.map_info.get("city", {}) if sim.map_info is Dictionary else {}
	for b in lay.get("buildings", []):
		var pts := PackedVector2Array()
		var sh: int = b[6] if b.size() > 6 else 0
		if sh == MapGen.SH_QUAD:
			for k in 4:
				pts.append(Vector2(b[7 + 2 * k], b[8 + 2 * k]))
		elif sh == MapGen.SH_ROUND:
			for k in 8:
				var an := TAU * k / 8.0
				pts.append(Vector2(b[7] + b[9] * cos(an), b[8] + b[9] * sin(an)))
		else:
			pts = PackedVector2Array([Vector2(b[0], b[1]), Vector2(b[2], b[1]), Vector2(b[2], b[3]), Vector2(b[0], b[3])])
		var idx := polys.size()
		polys.append(pts)
		for gy in range(int(b[1]) / 8 - 1, int(b[3]) / 8 + 2):
			for gx in range(int(b[0]) / 8 - 1, int(b[2]) / 8 + 2):
				var key := gy * 4096 + gx
				if not buck.has(key):
					buck[key] = []
				buck[key].append(idx)


func _footprints(sim) -> Vector3i:
	var n := 0
	var inside := 0
	var c3 := 0
	for u in sim.n_units:
		if sim.u_state[u] != BattleSim.U_READY or sim.u_alive[u] <= 0 or sim.u_wall[u] > 0 or sim.u_stair[u] != 0:
			continue
		if sim.occ_on != 0 and sim.u_occ[u] > 0:
			continue  # (slice 2c: a unit holding a building stands in it on purpose)
		var b: int = sim.u_slot_base[u]
		for s in sim.u_alive[u]:
			var i: int = sim.slot_soldier[b + s]
			var p := Vector2(sim.pos_x[i] / float(M), sim.pos_y[i] / float(M))
			var key := int(p.y) / 8 * 4096 + int(p.x) / 8
			if not buck.has(key):
				continue
			var best := 99.0
			var ins := false
			for k in buck[key]:
				var pts: PackedVector2Array = polys[k]
				if Geometry2D.is_point_in_polygon(p, pts):
					ins = true
				for e in pts.size():
					var q := Geometry2D.get_closest_point_to_segment(p, pts[e], pts[(e + 1) % pts.size()])
					best = minf(best, p.distance_to(q))
			if best > 6.0 and not ins:
				continue
			n += 1
			if ins:
				inside += 1
			elif best < 0.3:
				c3 += 1
	return Vector3i(n, inside, c3)


## A campaign town's settlement battle on its plan (docs/DESIGN.md "The town plan (shared)"): id
## "plan:<pack>:<region>:<level>:<walls>", the armies of tests/determinism_test.gd _town_scenario.
func _plan_scenario(id: String) -> Dictionary:
	var sp := id.split(":")
	var pack := sp[1]
	CData.use_pack(pack)
	var st := CState.new_campaign("town", 5, [], {}, [], pack)
	var r := CData.region_index(sp[2])
	st["regions"][r]["level"] = int(sp[3])
	var got := false
	for sl in st["regions"][r]["slots"]:
		if int(sl[0]) == CData.WALLS:
			sl[1] = int(sp[4])
			got = true
	if not got:
		st["regions"][r]["slots"].append([CData.WALLS, int(sp[4])])
	var city := CBattle.city_dict(st, r)
	var rd: Dictionary = CData.REGIONS[r]
	var terr := {"kind": int(rd["terrain"]), "seed": (CState.city_seed(st, r) ^ 0x2545F491) & 0x7FFFFFFF,
		"forest": int(rd["forest"]), "ground": int(rd["ground"])}
	var att: Array = []
	var dfn: Array = []
	if pack == "west":
		for e in Scenarios.WEST_ATT:
			att.append([UT.index_of(str(e[0])), int(e[1])])
		for e in Scenarios.WEST_DEF:
			dfn.append([UT.index_of(str(e[0])), int(e[1])])
	else:
		att = Scenarios.SIEGE_ARMY.duplicate(true)
		for k in 5:
			dfn.append([Scenarios.SIEGE_GARRISON[k], 60])
	return Scenarios.settlement(city, terr, att, dfn, 1, [0, 1], {"ladders": 3, "ram": 1})["scenario"]


func _run(id: String, ticks: int, sd: int) -> void:
	var sc: Dictionary = _plan_scenario(id) if id.begins_with("plan:") else Scenarios.make(id)
	sc["ai_sides"] = [0, 1]
	var sim = BattleSim.new()
	sim.setup(sc, sd)
	_setup_polys(sim)
	var mine := {}
	var n: int = sim.pos_x.size()
	var sx := PackedInt32Array(); sx.resize(n)
	var sy := PackedInt32Array(); sy.resize(n)
	var path := PackedInt32Array(); path.resize(n)
	var lx := PackedInt32Array(); lx.resize(n)
	var ly := PackedInt32Array(); ly.resize(n)
	var ldx := PackedInt32Array(); ldx.resize(n)
	var ldy := PackedInt32Array(); ldy.resize(n)
	var rev := PackedInt32Array(); rev.resize(n)
	var stp := PackedInt32Array(); stp.resize(n)
	for i in n:
		sx[i] = sim.pos_x[i]; sy[i] = sim.pos_y[i]; lx[i] = sx[i]; ly[i] = sy[i]
	var ucat := []
	var hist := {}    # router -> ring of 10 centroids (one a second)
	var streak := {}  # router -> seconds stationary in a row
	var r_s := 0
	var r_still := 0
	var r_max := 0
	var r30 := 0
	var fp := Vector3i.ZERO
	var us := 0
	var tn := 0
	while sim.tick < ticks and sim.ended == 0:
		if sim.tick % W == 0:
			ucat = []
			for u in sim.n_units:
				ucat.append(_cat(sim, u) if sim.u_state[u] <= BattleSim.U_ROUTING and sim.u_alive[u] > 0 else "")
		var t0 := Time.get_ticks_usec()
		sim.step()
		us += Time.get_ticks_usec() - t0
		tn += 1
		for u in sim.n_units:
			if sim.u_alive[u] <= 0 or sim.u_state[u] > BattleSim.U_ROUTING:
				continue
			var b: int = sim.u_slot_base[u]
			for s in sim.u_alive[u]:
				var i: int = sim.slot_soldier[b + s]
				var dx: int = sim.pos_x[i] - lx[i]
				var dy: int = sim.pos_y[i] - ly[i]
				var d := int(sqrt(float(dx) * dx + float(dy) * dy))
				path[i] += d
				if d > M / 20:
					stp[i] += 1
					if ldx[i] * dx + ldy[i] * dy < 0 and (absi(ldx[i]) + absi(ldy[i])) > M / 20:
						rev[i] += 1
					ldx[i] = dx; ldy[i] = dy
				lx[i] = sim.pos_x[i]; ly[i] = sim.pos_y[i]
		if sim.tick % W == 0:
			for u in sim.n_units:
				if u >= ucat.size() or ucat[u] == "" or sim.u_alive[u] <= 0:
					continue
				var b: int = sim.u_slot_base[u]
				var v := [0, 0, 0.0, 0.0, 0, 0]
				for s in sim.u_alive[u]:
					var i: int = sim.slot_soldier[b + s]
					if sim.state[i] >= BattleSim.S_DEAD:
						continue
					var nx: int = sim.pos_x[i] - sx[i]
					var ny: int = sim.pos_y[i] - sy[i]
					var net := sqrt(float(nx) * nx + float(ny) * ny) / M
					var p := float(path[i]) / M
					v[0] += 1
					if p >= 3.0 and net < p / 3.0:
						v[1] += 1
					v[2] += p
					v[3] += net
					v[4] += rev[i]
					v[5] += stp[i]
				_add(mine, ucat[u], v)
				_add(cats, ucat[u], v)
			for i in n:
				sx[i] = sim.pos_x[i]; sy[i] = sim.pos_y[i]; path[i] = 0; rev[i] = 0; stp[i] = 0
		if sim.tick % 5 == 0 and not polys.is_empty():
			fp += _footprints(sim)
		if sim.tick % BattleSim.TICKS_PER_SECOND == 0:
			for u in sim.n_units:
				if sim.u_state[u] != BattleSim.U_ROUTING or sim.u_alive[u] <= 0:
					hist.erase(u)
					streak.erase(u)
					continue
				r_s += 1
				var h: Array = hist.get(u, [])
				h.append(Vector2i(sim.u_cx[u], sim.u_cy[u]))
				if h.size() > 11:
					h.pop_front()
				hist[u] = h
				var still := false
				if h.size() == 11 and not _huddled(sim, u):
					var o: Vector2i = h[0]
					still = sqrt(float(sim.u_cx[u] - o.x) ** 2 + float(sim.u_cy[u] - o.y) ** 2) < 3.0 * M
				if still:
					r_still += 1
					var k: int = streak.get(u, 10) + 1
					streak[u] = k
					r_max = maxi(r_max, k)
					if k == 31:
						r30 += 1
				else:
					streak.erase(u)
	var su: int = 0
	var s30 := 0
	for u in sim.n_units:
		su = maxi(su, sim.stat_stuck_u[u])
		if sim.stat_stuck_u[u] > 30 * BattleSim.TICKS_PER_SECOND:
			s30 += 1
	rout_s += r_s
	still_s += r_still
	stuck_max = maxi(stuck_max, su)
	rstuck_max = maxi(rstuck_max, r_max)
	stuck30 += s30 + r30
	fp_n += fp.x
	fp_in += fp.y
	fp_c3 += fp.z
	var ms := us / 1000.0 / maxi(tn, 1)
	tick_ms.append([id, ms])
	print("== %s seed %d: %d ticks, winner %d, tick mean %.2f ms" % [id, sd, sim.tick, sim.winner, ms])
	var keys := mine.keys()
	keys.sort()
	for c in keys:
		_line(c, mine[c])
	print("  routers: %d unit-s, stationary %.1f %% | stuck max: ready %d s, router %d s, >30 s %d | footprint: %d samples, inside %.2f %%, <0.3 m %.2f %%" % [
		r_s, 100.0 * r_still / maxi(r_s, 1), su / BattleSim.TICKS_PER_SECOND, r_max, s30 + r30,
		fp.x, 100.0 * fp.y / maxi(fp.x, 1), 100.0 * fp.z / maxi(fp.x, 1)])


func _line(c: String, a: Array) -> void:
	if a[0] == 0:
		return
	print("  %-14s man-win %7d  jitter %5.1f %%  walk/net %5.2f  rev/step %5.1f %%" % [c, a[0],
		100.0 * a[1] / a[0], a[2] / maxf(a[3], 0.001), 100.0 * a[4] / maxf(a[5], 1)])


func _jit(a: Array) -> float:
	return 100.0 * a[1] / maxi(a[0], 1)


func _summary(phase: String) -> bool:
	print("== ALL RUNS")
	var keys := cats.keys()
	keys.sort()
	for c in keys:
		_line(c, cats[c])
	# Thresholds (docs/PATHING_SPEC.md section 8). Small categories (< 200
	# man-windows) are reported but not judged.
	var ok_a := true
	var worst_rout := 0.0
	var worst_rc := ""
	var worst_fight := 0.0
	var worst_fc := ""
	for c in keys:
		var a: Array = cats[c]
		if a[0] < 200:
			continue
		if c.begins_with("rout/") and _jit(a) > worst_rout:
			worst_rout = _jit(a)
			worst_rc = c
		if (c == "fight/town" or c == "fight/nearobs") and _jit(a) > worst_fight:
			worst_fight = _jit(a)
			worst_fc = c
	var still_pct := 100.0 * still_s / maxi(rout_s, 1)
	var fp_pct := 100.0 * fp_in / maxi(fp_n, 1)
	var rows := [
		["A", "rout jitter <= 5 % in every category", worst_rout <= 5.0, "%.1f %% (%s)" % [worst_rout, worst_rc]],
		["A", "stationary routing time <= 5 % (not huddled)", still_pct <= 5.0, "%.1f %%" % still_pct],
		["A", "stuck > 30 s: 0 (ready units and routers)", stuck30 == 0,
			"%d (longest ready %d s, router %d s)" % [stuck30, stuck_max / BattleSim.TICKS_PER_SECOND, rstuck_max]],
		["C", "fight / town and fight / near-obstacle jitter <= 3 %", worst_fight <= 3.0, "%.1f %% (%s)" % [worst_fight, worst_fc]],
		["B", "inside the drawn footprint <= 0.2 %", fp_pct <= 0.2, "%.2f %% (<0.3 m %.2f %%)" % [fp_pct, 100.0 * fp_c3 / maxi(fp_n, 1)]],
	]
	print("== THRESHOLDS")
	for r in rows:
		print("  [%s] %-6s %-52s %s" % [r[0], "PASS" if r[2] else "FAIL", r[1], r[3]])
		if r[0] == "A" and not r[2]:
			ok_a = false
	var tm := ""
	for t in tick_ms:
		tm += "%s %.2f  " % [t[0], t[1]]
	print("  tick mean ms: %s" % tm)
	if phase != "":
		print("RESULT: ", "PASS" if ok_a else "FAIL", " (phase A thresholds)")
	return ok_a
