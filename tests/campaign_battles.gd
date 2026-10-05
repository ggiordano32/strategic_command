extends SceneTree
## Campaign battles through the battle sim (headless).
##   godot --headless --script res://tests/campaign_battles.gd [-- --only=timing|calib --n=40]
## timing: auto-resolve (AI vs AI) of a 12 v 12 and a 24 v 24 campaign battle
##   from start to the end of pursuit, wall time and ticks.
## calib: random armies (2-12 units a side, random lines and tiers, some
##   garrisoned settlements with walls) fought by the sim AI vs AI and
##   predicted by the formula: how often the formula's favourite wins in the
##   sim, and the loss fractions of both.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const UT := preload("res://sim/unit_types.gd")

var only := ""
var n := 40


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.get_slice("=", 1)
		elif a.begins_with("--n="):
			n = int(a.get_slice("=", 1))
	if only == "" or only == "timing":
		_timing()
	if only == "" or only == "calib":
		_calib()
	quit(0)


## A state with a battle in region r between armies of the given unit keys
## (attacker faction fa from a neighbour, defender fd owning r).
func _setup(fa: int, fd: int, r: int, att: Array, def: Array, gar_pct: int, seed_v: int) -> Dictionary:
	var st := CState.new_campaign("b", seed_v, [])
	st["armies"] = []
	st["regions"][r]["owner"] = fd
	st["regions"][r]["gar"] = gar_pct
	CState.set_dip(st, fa, fd, CState.WAR)
	var ids := [[], []]
	var k := 0
	for side in 2:
		var lists: Array = att if side == 0 else def
		for lst in lists:
			k += 1
			var units: Array = []
			for key in lst:
				units.append({"t": key, "n": UT.size_of(UT.index_of(key))})
			var a := {"id": k, "f": fa if side == 0 else fd, "r": r, "units": units, "from": -1, "moved": 1, "busy": 1}
			(st["armies"] as Array).append(a)
			ids[side].append(k)
	var b := {"id": 1, "r": r, "turn": 0, "att": ids[0], "def": ids[1], "att_f": fa, "def_f": fd,
		"reinf": [], "settlement": 1}
	st["battles"] = [b]
	return st


func _army(keys: Array, count: int, k0: int) -> Array:
	var out: Array = []
	for i in count:
		out.append(keys[(i + k0) % keys.size()])
	return out


func _run(st: Dictionary, scale: int = 100) -> Dictionary:
	var b: Dictionary = st["battles"][0]
	var built := CBattle.build(st, b, -1, scale)
	var sim := BattleSim.new()
	var t0 := Time.get_ticks_msec()
	sim.setup(built["scenario"], int(built["seed"]))
	while sim.ended == 0 and sim.tick < 12000:
		sim.step()
	return {"ms": Time.get_ticks_msec() - t0, "ticks": sim.tick, "soldiers": sim.n, "res": sim.result(), "built": built}


func _timing() -> void:
	print("=== Auto-resolve timing (AI vs AI, to the end of pursuit)")
	var mix := ["heavy", "spear", "heavy", "archer", "cav", "javelin", "heavy2", "spear", "cav", "light", "archer", "heavy"]
	var r := CData.region_index("campania")
	for case in [[12, 1], [24, 2]]:
		var units: int = case[0]
		var armies: int = case[1]
		var att: Array = []
		var def: Array = []
		for a in armies:
			att.append(_army(mix, 12, a))
			def.append(_army(mix, 12, a + 3))
		for rep in 4:
			var st := _setup(0, 1, r, att, def, 0, 77 + rep / 2)
			var scale := 100 if rep % 2 == 0 else 50
			var out := _run(st, scale)
			print("scale %d%%: %d v %d units, %d soldiers: %d ticks (%.1f min battle), %.1f s wall, %.2f ms per tick; winner %d" % [
				scale, units, units, out["soldiers"], out["ticks"], out["ticks"] / 600.0, out["ms"] / 1000.0,
				float(out["ms"]) / maxi(int(out["ticks"]), 1), int(out["res"]["winner"])])


func _calib() -> void:
	print("=== Formula vs sim (%d random battles)" % n)
	var lines := ["heavy", "light", "spear", "archer", "javelin", "cav", "pike"]
	var agree := 0
	var sum_p_att := 0
	var sim_att_wins := 0
	var loss_w := [0.0, 0.0]  # sim: winner, loser kill fraction
	var loss_wf := [0.0, 0.0]  # formula
	var regions := ["campania", "samnium", "etruria", "apulia", "thessalia", "attica"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var buckets := {}
	for i in n:
		var na := rng.randi_range(2, 12)
		var nd := rng.randi_range(2, 12)
		var att: Array = []
		var def: Array = []
		for k in na:
			var line: String = lines[rng.randi_range(0, lines.size() - 1)]
			var tier := rng.randi_range(1, 3)
			att.append(UT.key_of(UT.index_of(line)) if tier == 1 else "%s%d" % [line, tier])
		for k in nd:
			var line: String = lines[rng.randi_range(0, lines.size() - 1)]
			var tier := rng.randi_range(1, 3)
			def.append(UT.key_of(UT.index_of(line)) if tier == 1 else "%s%d" % [line, tier])
		var r := CData.region_index(regions[i % regions.size()])
		var st := _setup(0, 1, r, [att], [def], rng.randi_range(0, 100), 500 + i)
		var b: Dictionary = st["battles"][0]
		var s := CBattle.side_strengths(st, b)
		var p := CBattle.win_chance(s[0], s[1])
		sum_p_att += p
		var out := _run(st)
		var o := CBattle.outcome_from_result(out["built"], out["res"], "auto")
		var w := int(o["winner"])
		if w == 0:
			sim_att_wins += 1
		var fav := 0 if p >= 500 else 1
		if fav == w:
			agree += 1
		var bucket := clampi(p / 200, 0, 4)
		var bk: Array = buckets.get(bucket, [0, 0])
		bk[0] += 1
		bk[1] += 1 if w == 0 else 0
		buckets[bucket] = bk
		# Kill fractions per side in the sim.
		var men := [0, 0]
		var killed := [0, 0]
		for u in out["res"]["units"]:
			var cs: int = 0 if int(u["side"]) == int(out["built"]["sim_side"][0]) else 1
			men[cs] += int(u["started"])
			killed[cs] += int(u["killed"])
		loss_w[0] += float(killed[w]) / maxi(men[w], 1)
		loss_w[1] += float(killed[1 - w]) / maxi(men[1 - w], 1)
		var fo := CBattle.formula(CState.copy(st), b)
		var fw := int(fo["winner"])
		var fm := [0, 0]
		var fk := [0, 0]
		for u in fo["units"]:
			var a := CState.army(st, int(u["army"]))
			var cs := 0 if int(a["f"]) == 0 else 1
			fm[cs] += int(u["killed"]) + int(u["routed"]) + int(u["remaining"])
			fk[cs] += int(u["killed"])
		loss_wf[0] += float(fk[fw]) / maxi(fm[fw], 1)
		loss_wf[1] += float(fk[1 - fw]) / maxi(fm[1 - fw], 1)
	print("formula favourite won in the sim: %d / %d (%.0f%%)" % [agree, n, 100.0 * agree / n])
	print("attacker wins: sim %.0f%%, formula expected %.0f%%" % [100.0 * sim_att_wins / n, sum_p_att / 10.0 / n])
	for k in 5:
		if buckets.has(k):
			print("  formula p(att) %d-%d%%: %d battles, sim attacker won %.0f%%" % [k * 20, k * 20 + 20, buckets[k][0], 100.0 * buckets[k][1] / buckets[k][0]])
	print("killed share, winner / loser: sim %.0f%% / %.0f%%, formula %.0f%% / %.0f%%" % [
		100 * loss_w[0] / n, 100 * loss_w[1] / n, 100 * loss_wf[0] / n, 100 * loss_wf[1] / n])
