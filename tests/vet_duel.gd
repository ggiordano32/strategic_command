extends SceneTree
## Veterancy duels (docs/design/battle_sim.md "Veterancy in battle"), headless:
##   godot --headless --script res://tests/vet_duel.gd [-- --seeds=8 --only=musket]
## One unit against one, each attacking the other, over the seeds; the
## levelled unit stands on side 0 in even seeds and side 1 in odd ones (the
## top / bottom bias cancels). Prints the levelled unit's wins, draws and
## both sides' men lost. The plan's gates: a Hardened (level 3) tier-1 unit
## wins about 65-80 % against a fresh one, never 100 %, and at most 55 %
## against a fresh tier-2 of its line.

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")

var seeds := 8
var only := ""
var max_ticks := 9000


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.get_slice("=", 1))
		elif a.begins_with("--only="):
			only = a.get_slice("=", 1)
		elif a.begins_with("--tune="):
			# A veterancy table for the run: --tune=VET_SUP=0,0,0,0 (an ablation).
			var kv := a.get_slice("=", 1)
			var vals: Array[int] = []
			for x in a.get_slice("=", 2).split(","):
				vals.append(int(x))
			match kv:
				"VET_ATT": BattleSim.VET_ATT = vals
				"VET_DEF": BattleSim.VET_DEF = vals
				"VET_SH": BattleSim.VET_SH = vals
				"VET_RL": BattleSim.VET_RL = vals
				"VET_SPR": BattleSim.VET_SPR = vals
				"VET_MOR": BattleSim.VET_MOR = vals
				"VET_SUP": BattleSim.VET_SUP = vals
				"VET_RALLY": BattleSim.VET_RALLY = vals
				_: push_error("unknown table " + kv)
			print("TUNE %s = %s" % [kv, str(vals)])
	# [name, levelled key, its level, opponent key, opponent level, men, gap m]
	var cases := [
		["musket L3 v L0", "musketeers", 3, "musketeers", 0, 100, 60],
		["musket L3 v musketeers2", "musketeers", 3, "musketeers2", 0, 100, 60],
		["musket L0 v L0 (mirror)", "musketeers", 0, "musketeers", 0, 100, 60],
		["musket L0 v musketeers2 (base)", "musketeers", 0, "musketeers2", 0, 100, 60],
		["pike L3 v L0", "w_pikemen", 3, "w_pikemen", 0, 120, 40],
		["pike L3 v w_pikemen2", "w_pikemen", 3, "w_pikemen2", 0, 120, 40],
		["pike L0 v w_pikemen2 (base)", "w_pikemen", 0, "w_pikemen2", 0, 120, 40],
		["bowmen L3 v L0", "native_bowmen", 3, "native_bowmen", 0, 80, 90],
		["bowmen L3 v archer2", "native_bowmen", 3, "archer2", 0, 80, 90],
		["bowmen L0 v archer2 (base)", "native_bowmen", 0, "archer2", 0, 80, 90],
		["warriors L3 v L0", "native_warriors", 3, "native_warriors", 0, 100, 40],
		["warriors L3 v native_warriors2", "native_warriors", 3, "native_warriors2", 0, 100, 40],
		["warriors L0 v native_warriors2 (base)", "native_warriors", 0, "native_warriors2", 0, 100, 40],
		["musket L1 v L0", "musketeers", 1, "musketeers", 0, 100, 60],
		["warriors L1 v L0", "native_warriors", 1, "native_warriors", 0, 100, 40],
	]
	for c in cases:
		if only != "" and str(c[0]).find(only) < 0:
			continue
		_case(c)
	quit(0)


func _case(c: Array) -> void:
	var ta := UT.index_of(str(c[1]))
	var tb := UT.index_of(str(c[3]))
	if ta < 0 or tb < 0:
		print("%-34s missing type" % c[0])
		return
	var men := int(c[5])
	var gap := int(c[6])
	var win := 0
	var draw := 0
	var lost := [0, 0]
	var t_sum := 0
	for k in seeds:
		var vs := k & 1  # the levelled unit's side
		var units := []
		for s in 2:
			var ty := ta if s == vs else tb
			var y := 150 + gap / 2 if s == 0 else 150 - gap / 2
			var u := Scenarios.unit(s, ty, men, 150, y, Scenarios.FACE_UP if s == 0 else Scenarios.FACE_DOWN)
			var lv := int(c[2]) if s == vs else int(c[4])
			if lv > 0:
				u["vet"] = lv
			units.append(u)
		var sc := {"width_m": 300, "height_m": 300, "ai_sides": [], "units": units,
			"orders": [Scenarios.attack(0, 0, 1, 0), Scenarios.attack(0, 1, 0, 0)]}
		var sim := BattleSim.new()
		sim.setup(sc, 4242 + k * 7919)
		while sim.tick < max_ticks and sim.ended == 0:
			sim.step()
		if sim.winner == vs:
			win += 1
		elif sim.winner < 0:
			draw += 1
		lost[0] += sim.u_count0[vs] - sim.u_alive[vs]
		lost[1] += sim.u_count0[1 - vs] - sim.u_alive[1 - vs]
		t_sum += (sim.decided_tick if sim.decided_tick >= 0 else sim.tick) / 10
	print("%-34s levelled wins %3d%%  draws %3d%%  | men lost %5.1f v %5.1f of %d | %4d s" % [c[0],
		win * 100 / seeds, draw * 100 / seeds, float(lost[0]) / seeds, float(lost[1]) / seeds, men, t_sum / seeds])
