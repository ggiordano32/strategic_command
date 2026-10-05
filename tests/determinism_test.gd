extends SceneTree
## Headless determinism test.
##   godot --headless --script res://tests/determinism_test.gd
## Runs the same scenario + seed + scripted orders twice and asserts the state
## hash matches at every tick, then checks a different seed diverges. The
## scripted orders use every order type (move, attack/shoot, halt, run, fire
## at will, skirmish, withdraw, army withdrawal) and the runs are checked to
## have exercised missiles, cavalry impacts, braced reflections, knockdowns,
## pike walls, withdrawals and routs off the field; and artillery: bolts and
## stones fired and striking, batteries packing up, moving and setting up
## again (deploy order), engines wrecked in melee and engines abandoned.
## Exits 0 on success, 1 on failure.

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")

const M := 1024

## scenario -> ticks to run
const RUNS := {"skirmish": 1500, "battle_2000": 1800, "bench_2000": 2500, "test_cav_spears": 600,
	"test_cav_art": 700}

var _ok := true


func _init() -> void:
	for scen in RUNS:
		var ticks: int = RUNS[scen]
		var a := _run(scen, 12345, ticks)
		var b := _run(scen, 12345, ticks)
		var ha: PackedInt64Array = a["hashes"]
		var hb: PackedInt64Array = b["hashes"]
		var first_bad := -1
		for t in ha.size():
			if t >= hb.size() or ha[t] != hb[t]:
				first_bad = t
				break
		if first_bad >= 0 or ha.size() != hb.size():
			_fail("%s: same seed diverged at tick %d" % [scen, first_bad])
		else:
			print("PASS %s: %d ticks identical, final hash %08x" % [scen, ha.size(), ha[ha.size() - 1]])
		if str(a["result"]) != str(b["result"]):
			_fail("%s: result() differs between identical runs" % scen)
		var c := _run(scen, 999, ticks)
		var hc: PackedInt64Array = c["hashes"]
		var diverge := -1
		for t in mini(ha.size(), hc.size()):
			if ha[t] != hc[t]:
				diverge = t
				break
		if diverge < 0:
			_fail("%s: different seed did not diverge" % scen)
		else:
			print("PASS %s: different seed diverges from tick %d" % [scen, diverge])
		_check_coverage(scen, a["stats"])
	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


func _fail(msg: String) -> void:
	printerr("FAIL ", msg)
	_ok = false


## Every mechanic must actually have happened somewhere in the run.
func _check_coverage(scen: String, st: Dictionary) -> void:
	var need: Array = []
	match scen:
		"skirmish":
			need = ["shots", "missile_hits", "impacts", "withdrawn", "attacks"]
		"battle_2000":
			need = ["shots", "missile_hits", "impacts", "knockdowns", "withdrawn",
				"pike_wall", "attacks", "bolts", "stones", "art_hits", "art_kills",
				"packs", "deploys", "parting", "engines_out"]
		"bench_2000":
			need = ["shots", "impacts", "routed_off", "ai_flank", "ai_pull", "attacks",
				"bolts", "stones", "art_hits", "ai_art", "ai_guard"]
		"test_cav_spears":
			need = ["reflects"]
		"test_cav_art":
			need = ["wrecked", "engines_out", "impacts", "bolts", "stones"]
	for k in need:
		if int(st.get(k, 0)) <= 0:
			_fail("%s: run never exercised %s (%s)" % [scen, k, str(st)])
	print("  %s coverage: %s" % [scen, str(st)])


## Scripted player orders for side 0 (side 1 is AI or scripted).
func _script_orders(sim, scen: String) -> void:
	var player_units: Array = []
	var enemy_units: Array = []
	for u in sim.n_units:
		if sim.u_side[u] == 0:
			player_units.append(u)
		else:
			enemy_units.append(u)
	if scen == "test_cav_art":
		# One cavalry unit rides down the stone throwers, the other pins the
		# spearmen, the light infantry runs in on the bolt throwers.
		sim.queue_order(BattleSim.make_attack_order(5, 0, 4, 1))
		sim.queue_order(BattleSim.make_attack_order(5, 1, 5, 1))
		sim.queue_order(BattleSim.make_attack_order(5, 2, 3, 1))
		return
	if scen == "test_cav_spears" or sim.is_ai_side(0):
		return
	var missiles: Array = []
	var cav: Array = []
	var foot: Array = []
	var arts: Array = []
	for u in player_units:
		var c := UT.cls(sim.u_type[u])
		if c == UT.CLS_MISSILE:
			missiles.append(u)
		elif c == UT.CLS_CAV:
			cav.append(u)
		elif c == UT.CLS_ART:
			arts.append(u)
		else:
			foot.append(u)
	# Artillery: pack up, move, set up again, shoot a chosen unit, hold fire
	# and fire at will again (the stones keep firing at will throughout).
	for k in arts.size():
		var a: int = arts[k]
		if k == 0:
			sim.queue_order(BattleSim.make_deploy_order(10, a, 0))
			sim.queue_order(BattleSim.make_move_order(60, a, sim.u_ax[a], sim.u_ay[a] - 15 * M, 768, 28 * M, 1))
			sim.queue_order(BattleSim.make_deploy_order(300, a, 1))
			sim.queue_order(BattleSim.make_attack_order(450, a, enemy_units[3], 0))
			sim.queue_order(BattleSim.make_fire_order(700, a, 0))
			sim.queue_order(BattleSim.make_halt_order(701, a))
			sim.queue_order(BattleSim.make_fire_order(800, a, 1))
	var u0: int = foot[0]
	var u1: int = foot[1] if foot.size() > 1 else foot[0]
	# Move / reform / halt / run.
	sim.queue_order(BattleSim.make_move_order(5, u0, sim.u_ax[u0], sim.u_ay[u0] - 30 * M, 768, 34 * M, 0))
	sim.queue_order(BattleSim.make_halt_order(60, u0))
	sim.queue_order(BattleSim.make_run_order(61, u0, 1))
	sim.queue_order(BattleSim.make_move_order(80, u0, sim.u_ax[u0] + 20 * M, sim.u_ay[u0] - 40 * M, 700, 20 * M, 1))
	# Missiles: hold fire, then shoot an explicit target, then fire at will,
	# skirmish toggled off and on.
	for m in missiles:
		sim.queue_order(BattleSim.make_fire_order(2, m, 0))
		sim.queue_order(BattleSim.make_skirmish_order(3, m, 0))
		sim.queue_order(BattleSim.make_attack_order(40, m, enemy_units[0], 0))
		sim.queue_order(BattleSim.make_fire_order(300, m, 1))
		sim.queue_order(BattleSim.make_skirmish_order(301, m, 1))
	# Cavalry: charge, pull out, charge again.
	for k in cav.size():
		var c: int = cav[k]
		var tgt: int = enemy_units[(k * 3 + 1) % enemy_units.size()]
		sim.queue_order(BattleSim.make_attack_order(150, c, tgt, 1))
		sim.queue_order(BattleSim.make_move_order(420, c, sim.u_ax[c], sim.u_ay[c], 768, 30 * M, 1))
		sim.queue_order(BattleSim.make_attack_order(520, c, tgt, 1))
	# Everyone else attacks, one unit withdraws, then the whole army.
	for k in foot.size():
		var tgt2: int = enemy_units[k % enemy_units.size()]
		sim.queue_order(BattleSim.make_attack_order(120 + k, foot[k], tgt2, 0))
	# A unit withdraws before contact (reaches the edge), later the army.
	var w: int = missiles[missiles.size() - 1] if not missiles.is_empty() else u1
	sim.queue_order(BattleSim.make_withdraw_order(200, w))
	sim.queue_order(BattleSim.make_withdraw_all_order(1000, 0))


func _run(scen: String, p_seed: int, ticks: int) -> Dictionary:
	var sim := BattleSim.new()
	sim.setup(Scenarios.make(scen), p_seed)
	_script_orders(sim, scen)
	var hashes := PackedInt64Array()
	hashes.append(sim.state_hash())
	var pike_wall := 0
	for t in ticks:
		sim.step()
		hashes.append(sim.state_hash())
		for u in sim.n_units:
			if sim.u_nwalls[u] > 0 and sim.u_contact[u] != 0:
				pike_wall += 1
	var withdrawn := 0
	var routed_off := 0
	for u in sim.n_units:
		withdrawn += sim.u_withdrawn[u]
		routed_off += sim.u_routed_off[u]
	var stats := {"shots": sim.stat_shots, "missile_hits": sim.stat_missile_hits,
		"impacts": sim.stat_impacts, "reflects": sim.stat_reflects,
		"knockdowns": sim.stat_knockdowns, "attacks": sim.stat_attacks,
		"withdrawn": withdrawn, "routed_off": routed_off, "pike_wall": pike_wall,
		"ai_flank": sim.stat_ai[2], "ai_pull": sim.stat_ai[6], "ai_art": sim.stat_ai[9],
		"ai_guard": sim.stat_ai[10], "bolts": sim.stat_bolts, "stones": sim.stat_stones,
		"art_hits": sim.stat_art_victims, "art_kills": sim.stat_art_kills,
		"packs": sim.stat_packs, "deploys": sim.stat_deploys, "wrecked": sim.stat_wrecked,
		"engines_out": sim.stat_wrecked + sim.stat_abandoned, "parting": sim.stat_parting}
	print("  %s seed %d: alive %d/%d after %d ticks, winner %d" % [scen, p_seed,
		sim.alive_count(0), sim.alive_count(1), ticks, sim.winner])
	return {"hashes": hashes, "result": sim.result(), "stats": stats}
