extends SceneTree
## Pursuit as a unit (docs/AI.md 46): a unit chasing an enemy that runs or
## walks away, on flat open ground, scripted orders only (no AI). Set pieces:
##   brk    100 heavy attack 100 heavy face to face; the target routs at 15 s
##          (an anchor runs at 7/8 of its men's run, routers too: equal types
##          never gain, the chase is the men in contact when it broke)
##   rout   100 light attack 100 heavy that rout at the start, 15 m ahead
##   walk   100 heavy (at the run) attack 100 light walking away (a move order)
##   cav    a cavalry unit attacks 100 light that rout, 40 m ahead
##   skirm  (West) 100 native warriors (at the run) attack 80 native bowmen
##          in skirmish mode that fall back
## Each runs PHASE1 s (60) from the order; then the attacker is moved 40 m to
## its flank (same facing, at the run) and runs PHASE2 s (30): the reposition.
## Per second (--verbose, first seed): the attacker's spread along its facing
## (bounding box, m), mean distance of its men from their places (m), men
## within reach of their man (u_inreach), strikes that second (swings),
## kills so far, the anchor's distance to the target's centre (m).
## Summary per case over the seeds: means over phase 1 of the spread, the
## distance from places and men in reach; strikes a second; kills in phase 1;
## the reposition: seconds until the move is done and 90 % of the men are
## within 2 m of their places, the largest anchor step in one tick (m: a
## jump if above the run's 0.45 m) and the share within 2 m at its end.
## Rules can be switched off by their static flags (builds that have them):
##   --off=back,push,pace,run,reform   (CHASE_BACK_ON, CHASE_PUSH_ON,
##   CHASE_PACE_ON, CHASE_RUN_ON, CHASE_REFORM_ON; "all"); --cases=rout,walk
##   --seeds=4 --verbose
##   godot --headless --script res://tests/chase_probe.gd [-- ...]

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const Terrain := preload("res://sim/terrain.gd")
const FM := preload("res://sim/fixed_math.gd")
const M := 1024
const PHASE1 := 600
const PHASE2 := 300
const BRK_T := 150

const FLAGS := {"back": "CHASE_BACK_ON", "push": "CHASE_PUSH_ON", "pace": "CHASE_PACE_ON", "run": "CHASE_RUN_ON",
	"reform": "CHASE_REFORM_ON"}


static func _sc(kind: String) -> Dictionary:
	# Side 1 (the target) runs toward y = 0; side 0 behind it, facing up.
	var a: Dictionary
	var t: Dictionary
	if kind == "brk":
		# Face to face 6 m apart; the target routs at BRK_T.
		t = Scenarios.unit(1, UT.index_of("heavy"), 100, 200, 700, Scenarios.FACE_DOWN)
		a = Scenarios.unit(0, UT.index_of("heavy"), 100, 200, 706, Scenarios.FACE_UP)
	elif kind == "rout":
		# (Routers run at 7/8 of their run, an anchor at 7/8 of its: heavy
		# routers 3.2 m/s, light after them 3.9; heavy after heavy never gain.)
		t = Scenarios.unit(1, UT.index_of("heavy"), 100, 200, 700, Scenarios.FACE_UP)
		a = Scenarios.unit(0, UT.index_of("light"), 100, 200, 715 + 6, Scenarios.FACE_UP)
	elif kind == "walk":
		t = Scenarios.unit(1, UT.index_of("light"), 100, 200, 700, Scenarios.FACE_UP)
		a = Scenarios.unit(0, UT.index_of("heavy"), 100, 200, 715 + 6, Scenarios.FACE_UP)
	elif kind == "cav":
		t = Scenarios.unit(1, UT.index_of("light"), 100, 200, 700, Scenarios.FACE_UP)
		a = Scenarios.unit(0, UT.index_of("cav"), UT.size_of(UT.index_of("cav")), 200, 740 + 6, Scenarios.FACE_UP)
	else:
		# (Bowmen fall back at 4.1 m/s; warriors run 4.8.)
		t = Scenarios.unit(1, UT.index_of("native_bowmen"), 80, 200, 700, Scenarios.FACE_DOWN)
		a = Scenarios.unit(0, UT.index_of("native_warriors"), 100, 200, 760, Scenarios.FACE_UP)
	return {"width_m": 400, "height_m": 1000, "ai_sides": [], "orders": [], "units": [a, t],
		"terrain": {"kind": Terrain.K_FLAT}}


static func _place(sim, u: int, s: int) -> Vector2i:
	var b: int = sim.u_slot_base[u]
	return Vector2i(sim.u_ax[u] + sim.off_x[b + s], sim.u_ay[u] + sim.off_y[b + s])


## [spread along facing, mean distance from places, share within 2 m (per mille)]
static func _shape(sim, u: int) -> Array:
	var b: int = sim.u_slot_base[u]
	var n: int = sim.u_alive[u]
	if n <= 0:
		return [0, 0, 1000]
	var c := FM.cos_a(sim.u_face[u])
	var s := FM.sin_a(sim.u_face[u])
	var lo := 1 << 40
	var hi := -(1 << 40)
	var dsum := 0
	var near := 0
	for k in n:
		var i: int = sim.slot_soldier[b + k]
		var x: int = sim.pos_x[i]
		var y: int = sim.pos_y[i]
		var f := (x * c + y * s) / FM.TRIG_ONE
		lo = mini(lo, f)
		hi = maxi(hi, f)
		var p := _place(sim, u, k)
		var d := int(sqrt(float(x - p.x) ** 2 + float(y - p.y) ** 2))
		dsum += d
		if d <= 2 * M:
			near += 1
	return [hi - lo, dsum / n, near * 1000 / n]


func _run(kind: String, sd: int, verbose: bool) -> Dictionary:
	var sim := BattleSim.new()
	sim.setup(_sc(kind), sd)
	var ta := 0
	var tt := 1
	if kind == "brk":
		pass
	elif kind == "rout" or kind == "cav":
		sim._start_rout(tt)
		sim.u_routs[tt] = BattleSim.MAX_ROUTS + 1  # (no rally)
	elif kind == "walk":
		sim.queue_order(BattleSim.make_move_order(0, tt, sim.u_ax[tt], sim.u_ay[tt] - 400 * M, sim.u_face[tt],
			BattleSim.files_to_width(sim.u_files[tt], sim.u_type[tt]), 0))
	else:
		sim.queue_order(BattleSim.make_skirmish_order(0, tt, 1))
	sim.queue_order(BattleSim.make_attack_order(0, ta, tt, 0 if kind == "rout" or kind == "cav" or kind == "brk" else 1))
	var men_t: Array = []
	var bt: int = sim.u_slot_base[tt]
	for k in sim.u_alive[tt]:
		men_t.append(sim.slot_soldier[bt + k])
	var cool: int = UT.stat(sim.u_type[ta], "cooldown")
	var cd0 := PackedInt32Array()
	cd0.resize(sim.n_soldiers if sim.get("n_soldiers") != null else sim.cooldown.size())
	var r := {"spread": 0, "pdist": 0, "inreach": 0, "strikes": 0, "kills": 0, "rep_t": -1, "jump": 0,
		"near_end": 0, "samples": 0}
	if verbose:
		print("--- %s seed %d: t  spread m  from place m  in reach  strikes  kills  anchor-target m" % [kind, sd])
	var sec_strikes := 0
	var ax0: int = sim.u_ax[ta]
	var ay0: int = sim.u_ay[ta]
	for tk in PHASE1 + PHASE2:
		if kind == "brk" and tk == BRK_T:
			sim._start_rout(tt)
			sim.u_routs[tt] = BattleSim.MAX_ROUTS + 1
		if tk == PHASE1:
			# The reposition: 40 m to its left flank, the same facing.
			var f: int = sim.u_face[ta]
			var c := FM.cos_a(f)
			var s := FM.sin_a(f)
			var lx: int = sim.u_ax[ta] + s * 40 * M / FM.TRIG_ONE
			var ly: int = sim.u_ay[ta] - c * 40 * M / FM.TRIG_ONE
			sim.queue_order(BattleSim.make_move_order(sim.tick, ta, lx, ly, f,
				BattleSim.files_to_width(sim.u_files[ta], sim.u_type[ta]), 1))
			if verbose:
				print("  reposition: move 40 m to the flank")
		var ba: int = sim.u_slot_base[ta]
		for k in sim.u_alive[ta]:
			var i: int = sim.slot_soldier[ba + k]
			cd0[i] = sim.cooldown[i]
		ax0 = sim.u_ax[ta]
		ay0 = sim.u_ay[ta]
		sim.step()
		ba = sim.u_slot_base[ta]
		for k in sim.u_alive[ta]:
			var i: int = sim.slot_soldier[ba + k]
			if sim.cooldown[i] >= cool and sim.cooldown[i] > cd0[i] and sim.target[i] >= 0:
				sec_strikes += 1
		if tk >= PHASE1:
			var j := int(sqrt(float(sim.u_ax[ta] - ax0) ** 2 + float(sim.u_ay[ta] - ay0) ** 2))
			r["jump"] = maxi(r["jump"], j)
		if (tk + 1) % 10 == 0:
			var sh := _shape(sim, ta)
			var kills := 0
			for i in men_t:
				if sim.state[i] == BattleSim.S_DEAD:
					kills += 1
			var dt := int(sqrt(float(sim.u_cx[tt] - sim.u_ax[ta]) ** 2 + float(sim.u_cy[tt] - sim.u_ay[ta]) ** 2))
			if tk < PHASE1:
				r["spread"] += sh[0]
				r["pdist"] += sh[1]
				r["inreach"] += sim.u_inreach[ta]
				r["strikes"] += sec_strikes
				r["kills"] = kills
				r["samples"] += 1
			elif r["rep_t"] < 0 and sim.u_order[ta] == BattleSim.O_NONE and sh[2] >= 900:
				r["rep_t"] = tk + 1 - PHASE1
			if tk == PHASE1 + PHASE2 - 1:
				r["near_end"] = sh[2]
			if verbose:
				print("  %3d  %6.1f  %6.1f  %4d  %4d  %4d  %6.1f%s" % [(tk + 1) / 10, sh[0] / 1024.0, sh[1] / 1024.0,
					sim.u_inreach[ta], sec_strikes, kills, dt / 1024.0,
					"  (order done)" if tk >= PHASE1 and sim.u_order[ta] == BattleSim.O_NONE else ""])
			sec_strikes = 0
	return r


func _init() -> void:
	var seeds := 4
	var verbose := false
	var cases := ["brk", "rout", "walk", "cav", "skirm"]
	var off: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.get_slice("=", 1))
		elif a == "--verbose":
			verbose = true
		elif a.begins_with("--cases="):
			cases = a.get_slice("=", 1).split(",")
		elif a.begins_with("--off="):
			off = Array(a.get_slice("=", 1).split(","))
	var probe := BattleSim.new()
	for k in FLAGS:
		if probe.get(FLAGS[k]) != null:
			probe.set(FLAGS[k], 0 if k in off or "all" in off else 1)
	print("rules off: %s" % (",".join(off) if not off.is_empty() else "none"))
	print("case    spread m  from place m  in reach  strikes/s  kills 60s  reform s  max anchor step m  within 2 m at 30 s")
	for kind in cases:
		var tot := {"spread": 0.0, "pdist": 0.0, "inreach": 0.0, "strikes": 0.0, "kills": 0.0, "rep": 0.0,
			"rep_n": 0, "jump": 0, "near": 0.0}
		for k in seeds:
			var r := _run(kind, 11 * (k + 1), verbose and k == 0)
			var n := maxf(float(r["samples"]), 1.0)
			tot["spread"] += r["spread"] / n / 1024.0
			tot["pdist"] += r["pdist"] / n / 1024.0
			tot["inreach"] += r["inreach"] / n
			tot["strikes"] += r["strikes"] / n
			tot["kills"] += r["kills"]
			if r["rep_t"] >= 0:
				tot["rep"] += r["rep_t"] / 10.0
				tot["rep_n"] += 1
			tot["jump"] = maxi(tot["jump"], r["jump"])
			tot["near"] += r["near_end"] / 10.0
		var sn := float(seeds)
		print("%-6s  %7.1f  %9.1f  %9.1f  %9.1f  %9.1f  %8s  %8.2f  %8.1f %%" % [kind, tot["spread"] / sn,
			tot["pdist"] / sn, tot["inreach"] / sn, tot["strikes"] / sn, tot["kills"] / sn,
			("%.1f" % (tot["rep"] / tot["rep_n"])) + ("" if tot["rep_n"] == seeds else " (%d/%d)" % [tot["rep_n"], seeds])
				if tot["rep_n"] > 0 else "never", tot["jump"] / 1024.0, tot["near"] / sn])
	quit()
