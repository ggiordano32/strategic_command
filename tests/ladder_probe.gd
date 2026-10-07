extends SceneTree
## Ladder probe (docs/STATUS.md item 4 part 2b, bug B): over every outer
## (and citadel) stretch of every plan x site x coast x wall level, at three
## points along it, the preview's rule (BattleSim.ladder_set_for, as the
## order rule and the overlay use it) is compared with what happens: a unit
## carrying a ladder set, standing out from the wall, is ordered onto the
## point; where the rule says it can, its first man must be on the walkway
## within BOUND ticks. Prints the counts and every failure.
##   godot --headless --script res://tests/ladder_probe.gd [-- --walls=2 --plans=4 --quick]
## Exit 1 if any point the rule allows is not climbed.

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const FM := preload("res://sim/fixed_math.gd")
const MapGen := preload("res://sim/mapgen.gd")
const Terrain := preload("res://sim/terrain.gd")

const M := 1024
const BOUND := 1500        # ticks for the first man up (walk out ~40 m at the carry pace, plant, climb)
const OUT := 40            # the unit stands this many metres out from the foot (or as near as open ground allows)


func _init() -> void:
	var walls_l: Array = [1, 2, 3]
	var plans: Array = [0, 1, 2, 3, 4]
	var kinds: Array = [Terrain.K_FLAT, Terrain.K_HILL, Terrain.K_RIDGE, Terrain.K_ROLLING]
	var quick := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--walls="):
			walls_l = Array(a.get_slice("=", 1).split(",")).map(func(v): return int(v))
		elif a.begins_with("--plans="):
			plans = Array(a.get_slice("=", 1).split(",")).map(func(v): return int(v))
		elif a == "--quick":
			quick = true
	if quick:
		kinds = [Terrain.K_FLAT, Terrain.K_HILL]
	var maps := 0
	var allowed := 0
	var climbed := 0
	var refused := 0
	var fails: Array = []
	var why := {}
	var t0 := Time.get_ticks_msec()
	for walls in walls_l:
		for plan in plans:
			for kind in kinds:
				for coast in 2:
					if plan == MapGen.PLAN_RING and coast == 1:
						continue  # (the ring has no coastal form)
					var r := _map(walls, plan, kind, coast)
					maps += 1
					allowed += int(r["allowed"])
					climbed += int(r["climbed"])
					refused += int(r["refused"])
					fails.append_array(r["fails"])
					for k in (r["why"] as Dictionary):
						why[k] = int(why.get(k, 0)) + int(r["why"][k])
	print("ladder probe: %d maps, %d points the rule allows: %d climbed, %d failed; %d refused %s (%.0f s)" % [
		maps, allowed, climbed, fails.size(), refused, str(why), (Time.get_ticks_msec() - t0) / 1000.0])
	for f in fails:
		print("  FAIL ", f)
	quit(1 if not fails.is_empty() else 0)


## One map: every land stretch at 1/4, 1/2, 3/4 of its length.
func _map(walls: int, plan: int, kind: int, coast: int) -> Dictionary:
	var sd := 900 + plan * 13 + kind + walls * 101
	var city := {"seed": sd, "level": 2, "walls": walls, "bld": [], "plan": plan, "coast": coast}
	var terr := {"kind": kind, "seed": sd * 7 + 3, "forest": 0, "ground": MapGen.PAL_DRY}
	var res := Scenarios.settlement(city, terr, [[UT.HEAVY, 40]], [[UT.SPEAR, 20]], 1, [], {"ladders": 1})
	var sc: Dictionary = res["scenario"]
	var base := BattleSim.new()
	base.setup(sc, 7)
	var snap := base.snapshot()
	var out := {"allowed": 0, "climbed": 0, "refused": 0, "fails": [], "why": {}}
	var u := 0  # the attackers' unit
	var q := 0  # its ladder set
	for sg in base.ws_x0.size():
		if (base.ws_fl[sg] & MapGen.SEG_SEA) != 0:
			continue
		var l := BattleSim.seg_len(base, sg)
		for part in [1, 2, 3]:
			var sim := BattleSim.new()
			sim.setup(sc, 7)
			sim.restore(snap)
			var p := BattleSim.seg_pt(sim, sg, l * part / 4)
			var lf := BattleSim.ladder_foot(sim, sg, p.x, p.y)
			if lf.z == 0:
				out["refused"] += 1
				_why(out, "no foot (tower, gate, sea, citadel)" if (sim.ws_fl[sg] & MapGen.SEG_CIT) == 0 else "citadel")
				continue
			var st := _stand(sim, sg, lf)
			if st.z == 0:
				out["refused"] += 1
				_why(out, "no ground to stand on out there")
				continue
			_place(sim, u, q, st, sg)
			var lq := BattleSim.ladder_set_for(sim, u, sg, p.x, p.y)
			if lq < 0:
				out["refused"] += 1
				_why(out, "foot not on the unit's ground")
				continue
			out["allowed"] += 1
			var tag := "walls %d plan %d kind %d coast %d seg %d (%d/4) at (%d, %d) foot (%d, %d)" % [walls, plan, kind,
				coast, sg, part, p.x / M, p.y / M, lf.x / M, lf.y / M]
			sim.queue_order(BattleSim.make_move_order(sim.tick, u, p.x, p.y, sim.ws_dir[sg], 10 * M, 0))
			var up := -1
			for t in BOUND:
				sim.step()
				if _men_up(sim, u) > 0:
					up = sim.tick
					break
			if up < 0:
				out["fails"].append("%s: stair %d order %d anchor (%d, %d) planted %d" % [tag, sim.u_stair[u], sim.u_order[u],
					sim.u_ax[u] / M, sim.u_ay[u] / M, sim.stat_planted])
			else:
				out["climbed"] += 1
	return out


func _why(out: Dictionary, k: String) -> void:
	out["why"][k] = int(out["why"].get(k, 0)) + 1


## Where the unit stands: OUT m out from the foot along the stretch's
## outward direction, else the open ground nearest that on the foot's own
## ground (5 m steps in, then out to 80 m). z 0: none.
func _stand(sim, sg: int, lf: Vector3i) -> Vector3i:
	var c := FM.cos_a(sim.ws_dir[sg])
	var s := FM.sin_a(sim.ws_dir[sg])
	var rf: int = sim.reach_at(lf.x, lf.y)
	for d in [OUT, 35, 30, 25, 20, 45, 50, 60, 70, 80]:
		var x: int = lf.x + c * d * M / FM.TRIG_ONE
		var y: int = lf.y + s * d * M / FM.TRIG_ONE
		if x < 10 * M or y < 10 * M or x > sim.field_w - 10 * M or y > sim.field_h - 10 * M:
			continue
		if sim.obs_kind(x, y) == MapGen.C_OPEN and (sim.nav_at(x, y) & MapGen.NAV_GROUND) != 0 \
				and sim.reach_at(x, y) == rf:
			return Vector3i(x, y, 1)
	return Vector3i(0, 0, 0)


## The attackers' unit u at (x, y) facing the wall, carrying ladder set q.
func _place(sim, u: int, q: int, st: Vector3i, sg: int) -> void:
	sim.u_ax[u] = st.x
	sim.u_ay[u] = st.y
	sim.u_face[u] = (sim.ws_dir[sg] + 512) & 1023
	sim.u_dface[u] = sim.u_face[u]
	sim.u_files[u] = 10
	sim.u_order[u] = BattleSim.O_NONE
	sim._compute_offsets(u)
	var base: int = sim.u_slot_base[u]
	for k in sim.u_alive[u]:
		var i: int = sim.slot_soldier[base + k]
		sim.pos_x[i] = st.x + sim.off_x[base + k]
		sim.pos_y[i] = st.y + sim.off_y[base + k]
	sim.prev_x = sim.pos_x.duplicate()
	sim.prev_y = sim.pos_y.duplicate()
	sim.u_pn[u] = 0
	sim.u_settled[u] = 0
	sim._update_bounds()
	sim.q_state[q] = BattleSim.Q_CARRIED
	sim.q_unit[q] = u
	sim.q_x[q] = st.x
	sim.q_y[q] = st.y
	sim.u_carry[u] = q


func _men_up(sim, u: int) -> int:
	var n := 0
	var base: int = sim.u_slot_base[u]
	for k in sim.u_alive[u]:
		var i: int = sim.slot_soldier[base + k]
		if sim.state[i] < BattleSim.S_DEAD and sim._on_walk(sim.pos_x[i], sim.pos_y[i]):
			n += 1
	return n
