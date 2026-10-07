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
## again (deploy order), engines wrecked in melee and engines abandoned,
## refilling from the baggage (and a refill broken off by melee).
## Terrain: maps are identical for the same seed and parameters and differ
## across seeds; the hilly runs ("scenario@kind" forces generated terrain of
## that kind) exercise every terrain rule (melee height bonus, slowing
## uphill, steep-ground disorder, charges downhill and uphill, range from
## height, flat shots refused for want of a line of fire, bolts stopped by
## the ground, stones ploughing less uphill, and the AI holding high ground,
## moving missiles onto rises and shifting its deployment); on a mirror-
## symmetric map every terrain function is exactly symmetric; and on flat
## maps the battles are bit-for-bit the recorded ones (golden trajectory
## digests; update them only for an intended change of flat-map rules).
## Woods and settlements: a woods set piece (slowing, disorder, arrows and
## stones stopped by trees, flat throws blocked, charges blunted) and AI
## settlement battles (an open village, a walled city, a hill city:
## paths through the streets, men kept out of walls and buildings,
## squeezing, gates broken by artillery, shots blocked by walls, the
## battlements' cover, plaza capture), a scripted gate set piece (closing,
## opening, refusing to close on men, hacking by infantry, bolts at a
## gate); the same hashes on repeat and across snapshot / restore at
## several points; the same map for the same parameters.
## Settlement plans (October 2026): AI battles on a castrum on a plain
## (ditch), a coastal polis on a hill (acropolis), a Punic city on the
## coast (citadel) and an oppidum on a spur (enclosed fields); a scripted
## citadel set piece on a coastal polis (a wall unit sent down a stair and
## up onto another stretch, the citadel's gate shut, hacked down, the
## citadel's plaza held: capture); the sea gate is scenery (no gate, wall
## cells), nobody walks on water and missiles fly over it; ditch cells
## with causeways at the gates; the view-only owner style keys change no
## hash.
## Wall orders (October 2026 playtest): garrison javelins on a wall are
## ordered down to the street just inside it, then back up by a tap on the
## walkway, on the wall's body (parapet), on a tower and by "Man the wall",
## climbing each time into their wall line (two ranks on the walkway); a
## unit longer than its stretch spills through a tower onto the next; the
## same hashes on repeat and across snapshot / restore. A drag longer than
## a unit's single rank forms exactly one rank.
## Reachability (October 2026 playtest, "the formation goes past the
## walls"): attackers outside a shut town ordered inside hold at the gate
## (no men strung along the wall); ordered to attack a unit inside, foot go
## to the gate and hack it, then go in once it breaks; archers shoot from
## outside the wall; no man's place on a wall or in a house.
## AI skill (docs/AI.md step 2): "key~xy" runs a RUNS key with the AI of
## side 0 at level x and side 1 at y (e Easy, a Average): Easy on a flat
## and a hilly field battle, an Easy attacker and an Easy defender of a
## walled city; identical on repeat and across snapshot / restore, and the
## Easy sides make deliberate mistakes (the mistake roller draws from the
## sim's RNG). The Average runs and golden digests above are unchanged.
## Skilled (docs/AI.md step 3; "s" in the key): both sides on a flat field,
## Skilled against Average on a hill, Average against Skilled on a
## mirror-symmetric woods map ("ai_woods"), a Skilled attacker and a
## Skilled defender of a walled city: identical on repeat and across
## snapshot / restore, and the Skilled sides use their behaviours
## ("skilled" coverage: rotations, reserve commits, Skilled-only counters).
## Exits 0 on success, 1 on failure.

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const Terrain := preload("res://sim/terrain.gd")
const FM := preload("res://sim/fixed_math.gd")

const M := 1024

## scenario -> ticks to run
## (Playable battles have random generated terrain; "@kind" forces a kind.)
const RUNS := {"skirmish@0": 1500, "battle_2000@0": 1800, "bench_2000": 2500, "test_cav_spears": 600,
	"test_cav_art": 700, "battle_2000@2": 1800, "bench_2000@4": 3000, "bench_2000@3": 2500,
	"test_bolts_crest": 500, "test_attack_uphill": 1500, "test_ridge_defend": 1500,
	"ai_hill": 1800, "ai_ridge": 600, "test_woods": 1200, "siege_village@ai": 3500,
	"siege_city@ai": 4200, "siege_hill@ai": 3000, "gate_ops": 1800,
	"siege_castrum@ai": 3600, "siege_polis@ai": 4500, "siege_punic@ai": 6500, "siege_oppidum@ai": 3600,
	"cit_ops": 3200, "bench_2000~ee": 2500, "bench_2000@4~ea": 3000, "siege_city@ai~ea": 4200,
	"siege_city@ai~ae": 4200, "bench_2000~ss": 2500, "bench_2000@4~sa": 3000, "ai_woods~as": 2500,
	"siege_city@ai~sa": 4200, "siege_city@ai~as": 4200}

## Trajectory digests of flat battles (soldier and unit arrays every 50
## ticks over 2,500 ticks, seed 4242): flat maps must keep playing exactly
## like this. Update only for an intended change of flat-map rules. History:
## terrain height left the digests of commit 49c1022 unchanged; they were
## re-recorded for more ammunition, stones aimed at the near face and the
## artillery Refill order (October 2026).
const GOLDEN := {"skirmish": "55283f52005038df", "bench_2000": "698d8a1a4d09955d",
	"test_cav_art": "2614adc80bd29eb4", "test_stone_line": "62b07015506232ff"}

var _ok := true


func _init() -> void:
	_check_wall_orders()
	_check_line_clamp()
	_check_reach()
	_check_plans()
	_check_city_maps()
	_check_snapshots()
	_check_maps()
	_check_symmetry()
	_check_golden()
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
		"skirmish@0":
			need = ["shots", "missile_hits", "impacts", "withdrawn", "attacks"]
		"battle_2000@0":
			need = ["shots", "missile_hits", "impacts", "knockdowns", "withdrawn",
				"pike_wall", "attacks", "bolts", "stones", "art_hits", "art_kills", "refills", "refilled",
				"packs", "deploys", "parting", "engines_out"]
		"bench_2000":
			need = ["shots", "impacts", "routed_off", "ai_flank", "ai_pull", "attacks",
				"bolts", "stones", "art_hits", "ai_art", "ai_guard"]
		"test_cav_spears":
			need = ["reflects"]
		"test_cav_art":
			need = ["wrecked", "engines_out", "impacts", "bolts", "stones", "refill_broken"]
		"battle_2000@2":
			need = ["h_melee", "slow_up", "charge_down", "charge_up", "steep_dis",
				"bolts", "stones", "bolt_ground", "plough_short"]
		"bench_2000@4":
			need = ["h_melee", "slow_up", "range_up", "charge_down", "charge_up", "ai_hold",
				"ai_rise", "steep_dis"]
		"ai_hill":
			need = ["ai_detour", "ai_hold", "h_melee", "charge_up"]
		"ai_ridge":
			need = ["ai_deploy"]
		"bench_2000@3":
			need = ["h_melee", "plough_short", "bolt_ground", "ai_rise"]
		"test_bolts_crest":
			need = ["lof_blocked", "bolts"]
		"test_attack_uphill":
			need = ["h_melee", "slow_up", "charge_up", "range_up"]
		"test_ridge_defend":
			need = ["h_melee", "charge_up", "range_up", "steep_dis"]
		"test_woods":
			need = ["veg_slow", "veg_dis", "veg_stop", "veg_impact", "tree_lof"]
		"siege_village@ai":
			need = ["paths", "clamp", "squeeze", "veg_slow"]
		"siege_city@ai":
			need = ["paths", "clamp", "squeeze", "gate_art", "gate_broken", "obs_lof", "wall_cover"]
		"siege_hill@ai":
			need = ["paths", "clamp", "gate_art", "gate_broken", "wall_cover", "obs_lof"]
		"gate_ops":
			need = ["gate_close", "gate_open", "gate_hack", "gate_art", "gate_broken", "paths"]
		"siege_castrum@ai":
			need = ["paths", "clamp", "gate_broken", "wall_cover", "obs_lof"]
		"siege_polis@ai":
			need = ["paths", "gate_broken", "stair_down", "gate_close", "obs_lof"]
		"siege_punic@ai":
			need = ["paths", "gate_broken", "stair_down", "gate_art", "gate_close"]
		"siege_oppidum@ai":
			need = ["paths", "gate_broken", "gate_art", "stair_rout"]
		"cit_ops":
			need = ["stair_down", "stair_up", "gate_close", "gate_open", "gate_hack", "gate_broken", "capture"]
		"bench_2000~ee", "bench_2000@4~ea", "siege_city@ai~ea", "siege_city@ai~ae":
			need = ["mistakes", "attacks"]
		"bench_2000~ss", "bench_2000@4~sa", "ai_woods~as", "siege_city@ai~sa", "siege_city@ai~as":
			need = ["skilled", "attacks"]
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
		# The enemy batteries keep trying to refill as the riders come in:
		# melee breaks the refill off.
		for t in range(150, 700, 20):
			for b in [3, 4]:
				var o := BattleSim.make_refill_order(t, b, 1)
				o["player"] = 50
				sim.queue_order(o)
		return
	scen = scen.get_slice("@", 0) if scen.ends_with("@0") else scen
	if scen == "test_bolts_crest":
		# Shoot the pikes behind the crest (refused), then the light infantry.
		sim.queue_order(BattleSim.make_attack_order(5, 0, 2, 0))
		sim.queue_order(BattleSim.make_attack_order(250, 0, 3, 0))
		return
	if scen == "test_attack_uphill":
		# Everything goes straight up the hill at the enemy; the cavalry
		# charges the spearmen's flank uphill.
		sim.queue_order(BattleSim.make_attack_order(5, 0, 4, 0))
		sim.queue_order(BattleSim.make_attack_order(5, 1, 4, 0))
		sim.queue_order(BattleSim.make_attack_order(5, 2, 5, 0))
		sim.queue_order(BattleSim.make_attack_order(200, 3, 6, 1))
		return
	if scen == "test_ridge_defend":
		return  # the enemy climbs the ridge by its own scripted orders
	if scen.ends_with("@ai"):
		return
	if scen == "test_woods":
		# Cavalry charges the archers standing in dense woods; the pikes
		# advance through woods on the heavy; the javelins go for theirs
		# across the dense thicket between them.
		sim.queue_order(BattleSim.make_attack_order(5, 0, 3, 1))
		sim.queue_order(BattleSim.make_attack_order(5, 1, 4, 0))
		sim.queue_order(BattleSim.make_attack_order(5, 2, 5, 0))
		return
	if scen == "gate_ops":
		# Defenders (side 1, player 51) shut gate 0 while a man is in it
		# (refused), open gate 1 and close it again; the attackers' heavy
		# infantry go into gate 0 (it cannot be shut on them), come out, it
		# is shut, and they hack at it while their bolts shoot it.
		for o in [{"tick": 5, "gate": 1, "on": 0}, {"tick": 300, "gate": 1, "on": 1},
				{"tick": 320, "gate": 0, "on": 0}, {"tick": 400, "gate": 0, "on": 1},
				{"tick": 650, "gate": 0, "on": 1}]:
			var go: Dictionary = o.duplicate()
			go["type"] = BattleSim.ORDER_GATE
			go["unit"] = sim.n_units - 1
			go["player"] = 51
			sim.queue_order(go)
		var gfoot := -1
		var bat := -1
		for u in sim.n_units:
			if sim.u_side[u] == 0 and UT.cls(sim.u_type[u]) == UT.CLS_ART:
				bat = u
			elif sim.u_side[u] == 0:
				gfoot = u
		sim.queue_order({"tick": 330, "type": BattleSim.ORDER_MOVE, "unit": gfoot, "x": sim.g_ox[0], "y": sim.g_oy[0],
			"facing": (sim.g_dir[0] + 512) & 1023, "width": 10 * M, "run": 1})
		sim.queue_order({"tick": 380, "type": BattleSim.ORDER_MOVE, "unit": gfoot, "x": sim.g_x[0], "y": sim.g_y[0],
			"facing": (sim.g_dir[0] + 512) & 1023, "width": 6 * M, "run": 0})
		# Out of the gate again; it is shut behind him; then he hacks at it
		# and the bolts shoot it.
		sim.queue_order({"tick": 500, "type": BattleSim.ORDER_MOVE, "unit": gfoot, "x": sim.g_ox[0] + (sim.g_ox[0] - sim.g_x[0]),
			"y": sim.g_oy[0] + (sim.g_oy[0] - sim.g_y[0]), "facing": (sim.g_dir[0] + 512) & 1023, "width": 10 * M, "run": 1})
		sim.queue_order({"tick": 700, "type": BattleSim.ORDER_ATTACK, "unit": gfoot, "target": -1, "gate": 0, "run": 0})
		sim.queue_order({"tick": 700, "type": BattleSim.ORDER_ATTACK, "unit": bat, "target": -1, "gate": 0, "run": 0})
		return
	if scen == "cit_ops":
		_cit_orders(sim)
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
		elif k == 1:
			# The stone throwers refill after their first stones, then are
			# told to shoot (which ends a refill still running).
			sim.queue_order(BattleSim.make_refill_order(320, a, 1))
			sim.queue_order(BattleSim.make_attack_order(1200, a, enemy_units[2], 0))
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


## Scenario for a RUNS key: "id" or "id@kind" (forced generated terrain);
## "ai_hill": both AIs on the hill test (the attacker goes round the steep
## side, the holder holds); "ai_ridge": the skirmish, AI against AI, with a
## low ridge just behind the top army (it shifts its deployment onto it).
static func _scenario(key: String) -> Dictionary:
	if key.find("~") >= 0:
		# AI skill per side: "~ea" side 0 Easy, side 1 Average.
		var sk := key.get_slice("~", 1)
		var sc0 := _scenario(key.get_slice("~", 0))
		var lv := {"e": 0, "a": 1, "s": 2}
		sc0["ai_skill"] = [lv[sk.substr(0, 1)], lv[sk.substr(1, 1)]]
		return sc0
	if key == "ai_woods":
		# Mirrored armies, AI against AI, on a mirror-symmetric field with woods.
		var sw := Scenarios.make("bench_2000")
		sw["terrain"] = {"kind": Terrain.K_FLAT, "sym": 1, "forest": 40, "seed": 901}
		return sw
	if key.ends_with("@ai"):
		var sa := Scenarios.make(key.get_slice("@", 0))
		sa["ai_sides"] = [0, 1]
		return sa
	if key == "gate_ops":
		var r := Scenarios.settlement({"seed": 202, "level": 1, "walls": 1, "bld": []},
			{"kind": 1, "seed": 9, "forest": 20, "ground": 2}, [[UT.HEAVY, 100], [UT.BOLT, 16]],
			[[UT.ARCHER, 40], [UT.SPEAR, 60]], 1, [])
		return r["scenario"]
	if key == "cit_ops":
		var rc := Scenarios.settlement({"seed": 606, "level": 1, "walls": 1, "bld": [], "plan": 1, "coast": 1},
			{"kind": 4, "seed": 11, "forest": 10, "ground": 2}, [[UT.HEAVY, 100], [UT.HEAVY, 100]],
			[[UT.ARCHER, 40], [UT.SPEAR, 40]], 1, [])
		return rc["scenario"]
	if key == "ai_hill":
		var sh := Scenarios.make("test_attack_uphill")
		sh["ai_sides"] = [0, 1]
		return sh
	if key == "ai_ridge":
		var sr := Scenarios.make("skirmish")
		sr["ai_sides"] = [0, 1]
		sr["terrain"] = {"kind": Terrain.K_CUSTOM, "features": [Scenarios.ridge(220, 108, 22, 7, 0, 160)]}
		return sr
	var id := key.get_slice("@", 0)
	var sc := Scenarios.make(id)
	if key.find("@") >= 0:
		var kind := int(key.get_slice("@", 1))
		sc["terrain"] = {"kind": kind}
	return sc


func _run(scen: String, p_seed: int, ticks: int) -> Dictionary:
	var sim := BattleSim.new()
	sim.setup(_scenario(scen), p_seed)
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
		"engines_out": sim.stat_wrecked + sim.stat_abandoned, "parting": sim.stat_parting,
		"h_melee": sim.stat_h_melee, "charge_down": sim.stat_charge_down,
		"charge_up": sim.stat_charge_up, "lof_blocked": sim.stat_lof_blocked,
		"slow_up": sim.stat_slow_up, "range_up": sim.stat_range_up,
		"plough_short": sim.stat_plough_short, "bolt_ground": sim.stat_bolt_ground,
		"steep_dis": sim.stat_steep_dis, "ai_hold": sim.stat_ai[12], "ai_rise": sim.stat_ai[13],
		"ai_deploy": sim.stat_ai[14], "ai_detour": sim.stat_ai[11],
		"refills": sim.stat_refills, "refilled": sim.stat_refilled,
		"refill_broken": sim.stat_refill_broken, "veg_slow": sim.stat_veg_slow, "veg_dis": sim.stat_veg_dis,
		"veg_stop": sim.stat_veg_stop, "veg_impact": sim.stat_veg_impact, "tree_lof": sim.stat_tree_lof,
		"obs_lof": sim.stat_obs_lof, "wall_cover": sim.stat_wall_cover, "paths": sim.stat_paths,
		"clamp": sim.stat_clamp, "squeeze": sim.stat_squeeze, "gate_hack": sim.stat_gate_hack,
		"gate_art": sim.stat_gate_art, "gate_close": sim.stat_gate_close, "gate_open": sim.stat_gate_open,
		"gate_broken": sim.stat_gate_broken, "capture": sim.stat_capture, "ai_shelter": sim.stat_ai[15],
		"stair_down": sim.stat_stair_down, "stair_up": sim.stat_stair_up, "stair_rout": sim.stat_stair_rout,
		"ditch": sim.stat_ditch, "sea_exit": sim.stat_sea_exit, "mistakes": _mistakes(sim)}
	if not sim.ai_mem.is_empty():
		stats["skilled"] = _skilled(sim)
	print("  %s seed %d: alive %d/%d after %d ticks, winner %d" % [scen, p_seed,
		sim.alive_count(0), sim.alive_count(1), ticks, sim.winner])
	return {"hashes": hashes, "result": sim.result(), "stats": stats}


## Deliberate AI mistakes made in the battle (both sides).
static func _mistakes(sim) -> int:
	var AP := preload("res://sim/ai_profile.gd")
	var n := 0
	for side in 2:
		for m in AP.N_MISTAKES:
			n += sim.stat_aic[side * AP.N_COUNTERS + AP.C_MISTAKE + m]
	return n


## Skilled behaviours carried out (rotations, reserve commits and the
## Skilled-only counters), both sides.
static func _skilled(sim) -> int:
	var AP := preload("res://sim/ai_profile.gd")
	var n := 0
	for side in 2:
		for c in [AP.C_ROTATION, AP.C_RESERVE_COMMIT, AP.C_CAV_STAY, AP.C_DOUBLE, AP.C_FOCUS, AP.C_GUARD_FREE,
				AP.C_WAVER_PULL, AP.C_SIEGE, AP.C_ART_PULL]:
			n += sim.stat_aic[side * AP.N_COUNTERS + c]
	return n


# --------------------------------------------------------------- terrain ---

## Same seed and parameters: the same map (and hash); another seed or kind:
## a different one; flat: no terrain; and the hash is in state_hash().
func _check_maps() -> void:
	var w := 560 * 1024
	var h := 560 * 1024
	for kind in [Terrain.K_ROLLING, Terrain.K_RIDGE, Terrain.K_VALLEY, Terrain.K_HILL, Terrain.K_SLOPE]:
		var a := Terrain.build({"kind": kind}, 777, w, h)
		var b := Terrain.build({"kind": kind}, 777, w, h)
		var c := Terrain.build({"kind": kind}, 778, w, h)
		var d := Terrain.build({"kind": kind, "seed": 777}, 5, w, h)
		if a["h"] != b["h"] or a["h"] != d["h"]:
			_fail("terrain kind %d: same seed built different maps" % kind)
		elif a["h"] == c["h"]:
			_fail("terrain kind %d: different seeds built the same map" % kind)
		elif int(a["on"]) != 1:
			_fail("terrain kind %d: no relief" % kind)
		else:
			print("PASS terrain kind %d: same seed same map, other seed differs" % kind)
	var sc := Scenarios.make("battle_2000")
	var s1 := BattleSim.new()
	s1.setup(sc, 4242)
	var s2 := BattleSim.new()
	s2.setup(sc.duplicate(true), 4242)
	var sc3: Dictionary = sc.duplicate(true)
	sc3["terrain"]["relief_m"] = 13
	var s3 := BattleSim.new()
	s3.setup(sc3, 4242)
	if s1.state_hash() != s2.state_hash() or s1.ter_hash != s2.ter_hash:
		_fail("battle_2000: same seed, different tick-0 hash")
	elif s1.state_hash() == s3.state_hash():
		_fail("battle_2000: a different terrain parameter left the tick-0 hash unchanged")
	else:
		print("PASS terrain parameters are covered by state_hash() at tick 0")
	var flat := BattleSim.new()
	flat.setup(Scenarios.make("bench_2000"), 4242)
	if flat.ter_on != 0 or flat.height_at(100000, 100000) != 0:
		_fail("bench_2000 is not flat")


## On a mirror-symmetric map, every terrain function gives exactly the
## mirrored answer for the mirrored question (no top / bottom bias).
func _check_symmetry() -> void:
	var bad := 0
	var checks := 0
	for kind in [Terrain.K_ROLLING, Terrain.K_RIDGE, Terrain.K_HILL, Terrain.K_SLOPE]:
		var sc := Scenarios.make("bench_2000")
		sc["terrain"] = {"kind": kind, "sym": 1, "seed": 99 + kind}
		var sim := BattleSim.new()
		sim.setup(sc, 1)
		var W: int = sim.field_w
		var H: int = sim.field_h
		var rng := 12345
		for k in 4000:
			rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
			var x := rng % (W + 1)
			rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
			var y := rng % (H + 1)
			if k < 40:
				# Grid lines and edges, where rounding would show first.
				x = (k % 10) * 4096 * 7
				y = (k / 10) * 4096 * 13
			checks += 1
			if sim.height_at(x, y) != sim.height_at(W - x, H - y):
				bad += 1
			var g := sim.slope_at(x, y)
			var gm := sim.slope_at(W - x, H - y)
			if g.x != -gm.x or g.y != -gm.y:
				bad += 1
			rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
			var dx := rng % 8001 - 4000
			rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
			var dy := rng % 8001 - 4000
			if sim.grade_along(x, y, dx, dy) != sim.grade_along(W - x, H - y, -dx, -dy):
				bad += 1
			if k % 8 == 0:
				rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
				var x1 := rng % (W + 1)
				rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
				var y1 := rng % (H + 1)
				var z0 := sim.height_at(x, y) + BattleSim.LOF_EYE
				var z1 := sim.height_at(x1, y1) + BattleSim.LOF_BODY
				var b1 := sim.lof_block(x, y, z0, x1, y1, z1, 3000, 20000)
				var b2 := sim.lof_block(W - x, H - y, z0, W - x1, H - y1, z1, 3000, 20000)
				if b1 != b2:
					bad += 1
	if bad > 0:
		_fail("terrain functions not mirror-symmetric on a symmetric map (%d of %d checks)" % [bad, checks])
	else:
		print("PASS terrain functions exactly mirror-symmetric (%d points x 4 symmetric maps)" % (checks / 4))


## Flat maps play exactly as recorded (golden digests).
func _check_golden() -> void:
	for scen in GOLDEN:
		var sim := BattleSim.new()
		var sc := Scenarios.make(scen)
		if sc.has("terrain"):
			sc["terrain"] = {"kind": Terrain.K_FLAT}
		sim.setup(sc, 4242)
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_MD5)
		for t in 2500:
			sim.step()
			if t % 50 == 0:
				for arr in [sim.pos_x, sim.pos_y, sim.hp, sim.state, sim.u_morale, sim.u_ax, sim.u_ay,
						sim.pr_x, sim.e_hp]:
					var bytes := (arr as PackedInt32Array).to_byte_array()
					if bytes.size() > 0:
						ctx.update(bytes)
		var dig := ctx.finish().hex_encode().substr(0, 16)
		if dig != GOLDEN[scen]:
			_fail("%s on a flat map no longer plays as recorded (digest %s, want %s)" % [scen, dig, GOLDEN[scen]])
		else:
			print("PASS %s on a flat map plays exactly as recorded" % scen)



# ---------------------------------------------------- woods and settlements ---

## City maps: the same parameters build the same map (and ter_hash); the
## defenders at the bottom get the same city turned round; every wall
## stretch and gate node is in the street graph's main piece.
func _check_city_maps() -> void:
	var a := Scenarios.make("siege_city")
	var s1 := BattleSim.new()
	s1.setup(a, 77)
	var s2 := BattleSim.new()
	s2.setup(Scenarios.make("siege_city"), 77)
	if s1.ter_hash != s2.ter_hash or s1.state_hash() != s2.state_hash():
		_fail("siege_city: same parameters built different maps")
	var b := Scenarios.siege_test(303, 2, 2, 1, Terrain.K_FLAT, 0)
	var s3 := BattleSim.new()
	s3.setup(b, 77)
	var bad := 0
	if s3.ob_w != s1.ob_w or s3.ob_h != s1.ob_h:
		bad += 1
	else:
		var n: int = s1.obs.size()
		for k in n:
			if s1.obs[k] != s3.obs[n - 1 - k]:
				bad += 1
	if bad > 0:
		_fail("siege_city defended from the bottom is not the same city turned round (%d cells)" % bad)
	else:
		print("PASS settlement maps: same parameters same map; turned round for the other side")
	var other := Scenarios.siege_test(304, 2, 2, 1, Terrain.K_FLAT, 1)
	var s4 := BattleSim.new()
	s4.setup(other, 77)
	if s4.ter_hash == s1.ter_hash:
		_fail("another city seed built the same map")


## The citadel set piece on a coastal polis town (attackers 0, 1: heavy
## infantry; defenders 2: archers on a wall, 3: spearmen at the gate). The
## defenders open the outer gate, the spearmen go into the citadel, the
## archers come down a stair to the agora; the attackers march to the
## citadel; its gate is shut; they hack it down while the archers climb
## onto another stretch of wall; they kill the spearmen and hold the
## citadel's plaza.
func _cit_orders(sim) -> void:
	var cg: int = sim.cit_gate
	var arch := 2
	var spear := 3
	var own_seg: int = sim.u_wall[arch] - 1
	var other := -1
	for sg in sim.ws_x0.size():
		if sg != own_seg and sim.ws_fl[sg] == 0:
			other = sg
			break
	var gate_o := func(t: int, g: int, on: int) -> void:
		sim.queue_order({"tick": t, "type": BattleSim.ORDER_GATE, "unit": spear, "gate": g, "on": on, "player": 51})
	var mv := func(t: int, u: int, x: int, y: int, run: int, pl: int) -> void:
		var o := BattleSim.make_move_order(t, u, x, y, 768, 8 * M, run)
		o["player"] = pl
		sim.queue_order(o)
	gate_o.call(5, 0, 0)
	mv.call(5, spear, sim.cit_x, sim.cit_y, 1, 51)
	mv.call(5, arch, sim.agora[0], sim.agora[1], 0, 51)
	for u in [0, 1]:
		mv.call(10, u, sim.g_ox[cg] + (u * 2 - 1) * 6 * M, sim.g_oy[cg], 1, 0)
	gate_o.call(700, cg, 1)
	for u in [0, 1]:
		sim.queue_order({"tick": 760, "type": BattleSim.ORDER_ATTACK, "unit": u, "target": -1, "gate": cg,
			"run": 0, "player": 0})
	if other >= 0:
		var o2 := BattleSim.make_move_order(800, arch, (sim.ws_x0[other] + sim.ws_x1[other]) / 2,
			(sim.ws_y0[other] + sim.ws_y1[other]) / 2, 768, 8 * M, 0)
		o2["player"] = 51
		sim.queue_order(o2)
	for u in [0, 1]:
		sim.queue_order(BattleSim.make_attack_order(1500, u, spear, 0))
	mv.call(2100, 0, sim.cit_x, sim.cit_y, 0, 0)
	mv.call(2100, 1, sim.cit_x + 4 * M, sim.cit_y + 4 * M, 0, 0)


## Settlement plans: every plan x site builds; coast (the sea gate is wall,
## not a gate; nobody walks on the sea; shots fly over it); the ditch (and
## its causeways); the citadel is the capture zone; the view-only style
## keys (owner, founder, banner, bstyle, hstyle) change no map or hash.
func _check_plans() -> void:
	var MapGen := preload("res://sim/mapgen.gd")
	var pol := BattleSim.new()
	pol.setup(Scenarios.make("siege_polis"), 77)
	var lay: Dictionary = pol.map_info["city"]
	var sea: Dictionary = lay["sea"]
	var bad := []
	if pol.sea_on == 0 or sea.is_empty() or (sea["gate"] as Array).is_empty():
		bad.append("no sea gate on the coastal polis")
	else:
		var sgx: int = int(sea["gate"][0]) * M
		var sgy: int = int(sea["gate"][1]) * M
		# Across the wall at the sea gate some cell is closed to men on the
		# ground (the gate is scenery: wall and walkway).
		var sdir: int = int(sea["gate"][2])
		var shut := false
		for q in range(-8, 9):
			var qx := sgx + FM.cos_a(sdir) * q * M / 4096
			var qy := sgy + FM.sin_a(sdir) * q * M / 4096
			if (pol.nav_at(qx, qy) & MapGen.NAV_GROUND) == 0 and pol.obs_kind(qx, qy) != MapGen.C_WATER:
				shut = true
		if not shut:
			bad.append("the sea gate can be walked through")
		for g in pol.n_gates:
			if FM.approx_len(pol.g_x[g] - sgx, pol.g_y[g] - sgy) < 14 * M:
				bad.append("a sim gate at the sea gate")
	var water := 0
	for c in pol.obs.size():
		if pol.obs[c] == MapGen.C_WATER:
			water += 1
			if pol.nav[c] != 0:
				bad.append("water is passable")
				break
	if water < 1000:
		bad.append("no sea (%d cells)" % water)
	if pol._obs_top(int(sea["flee"][0][0]) * M, 2 * M if pol.city_def == 1 else pol.field_h - 2 * M) != 0:
		bad.append("the sea blocks shots")
	if pol.cit_r <= 0 or pol.plaza[0] != pol.cit_x or pol.plaza[1] != pol.cit_y:
		bad.append("the polis's capture zone is not its acropolis")
	if pol.g_state[pol.cit_gate] != BattleSim.GATE_OPEN:
		bad.append("the citadel's gate does not start open")
	var cas := BattleSim.new()
	cas.setup(Scenarios.make("siege_castrum"), 77)
	var ditch := 0
	for c in cas.obs.size():
		if cas.obs[c] == MapGen.C_DITCH:
			ditch += 1
	if ditch < 500 or cas.city_ditch == 0:
		bad.append("no ditch round the castrum (%d cells)" % ditch)
	for g in cas.n_gates:
		var dx := FM.cos_a(cas.g_dir[g])
		var dy := FM.sin_a(cas.g_dir[g])
		for d in range(16, 40, 2):
			if cas.obs_kind(cas.g_x[g] + dx * d * M / 4096, cas.g_y[g] + dy * d * M / 4096) == MapGen.C_DITCH:
				bad.append("gate %d has no causeway" % g)
				break
	# View-only style keys.
	var plain := Scenarios.siege_test(707, 2, 2, 1, Terrain.K_FLAT, 1, -1, MapGen.PLAN_PUNIC, 1)
	var styled: Dictionary = plain.duplicate(true)
	var cty: Dictionary = styled["terrain"]["city"]
	cty["owner"] = 0
	cty["founder"] = 2
	cty["banner"] = 0
	cty["bstyle"] = [0, 0, 1]
	cty["hstyle"] = [2, 0, 0]
	var s1 := BattleSim.new()
	s1.setup(plain, 4242)
	var s2 := BattleSim.new()
	s2.setup(styled, 4242)
	for t in 300:
		s1.step()
		s2.step()
	if s1.ter_hash != s2.ter_hash or s1.state_hash() != s2.state_hash():
		bad.append("owner style keys changed the map or the hash")
	var st_view := 0
	for b in (s2.map_info["city"]["buildings"] as Array):
		if int(b[5]) == 0:
			st_view += 1
	if st_view == 0:
		bad.append("owner style keys did not reach the view's layout")
	# Every plan x site x coast builds, with gates and a street graph.
	var built := 0
	for plan in 4:
		for kind in [Terrain.K_FLAT, Terrain.K_HILL, Terrain.K_RIDGE, Terrain.K_ROLLING]:
			for coast in 2:
				var sc := Scenarios.siege_test(900 + plan * 13 + kind, 2, 2, 2, kind, 1, -1, plan, coast)
				var sp := BattleSim.new()
				sp.setup(sc, 1)
				var outer := 0
				for g in sp.n_gates:
					if sp.g_cit[g] == 0:
						outer += 1
				if outer < 1 or sp.ng_x.size() < 20 or sp.ws_x0.size() < 2:
					bad.append("plan %d kind %d coast %d: %d gates, %d nodes" % [plan, kind, coast, outer, sp.ng_x.size()])
				built += 1
	# The ditch: foot ordered straight across it wade through (slowly);
	# horses sent to the same spot go round by a causeway, never into it.
	var rd := Scenarios.settlement({"seed": 505, "level": 2, "walls": 3, "bld": [], "plan": 0, "coast": 0},
		{"kind": 0, "seed": 3, "forest": 0, "ground": 2}, [[UT.HEAVY, 60], [UT.CAVALRY, 40]],
		[[UT.SPEAR, 20]], 1, [])
	var sd := BattleSim.new()
	sd.setup(rd["scenario"], 5)
	var gdir: int = sd.g_dir[0]
	var lx: int = sd.g_x[0] - FM.sin_a(gdir) * 40 * M / 4096 + FM.cos_a(gdir) * 18 * M / 4096
	var ly: int = sd.g_y[0] + FM.cos_a(gdir) * 40 * M / 4096 + FM.sin_a(gdir) * 18 * M / 4096
	for u in [0, 1]:
		sd.queue_order(BattleSim.make_move_order(2, u, lx, ly, 768, 12 * M, 0))
	var cav_in := 0
	var t_cross := -1
	var cav_u := 0 if UT.cls(sd.u_type[0]) == UT.CLS_CAV else 1
	for t in 1500:
		sd.step()
		var base: int = sd.u_slot_base[cav_u]
		for q in sd.u_alive[cav_u]:
			var i: int = sd.slot_soldier[base + q]
			if sd.obs_kind(sd.pos_x[i], sd.pos_y[i]) == MapGen.C_DITCH:
				cav_in += 1
		if t_cross < 0 and sd.stat_ditch > 0:
			t_cross = sd.tick
	if sd.stat_ditch <= 0:
		bad.append("foot did not cross the ditch")
	if cav_in > 0:
		bad.append("horses stood in the ditch (%d man-ticks)" % cav_in)
	if bad.is_empty():
		print("PASS settlement plans: %d plan x site x coast maps build; sea gate is wall, water impassable, shots cross it; ditch with causeways, foot wade it (%d unit-ticks in it), horses never; citadel is the capture zone; style keys change no hash" % [built, sd.stat_ditch])
	else:
		for b in bad:
			_fail("plans: " + str(b))


## Snapshot / restore round trips on woods and settlement battles: a copy
## restored at several ticks runs on with exactly the original's hashes.
func _check_snapshots() -> void:
	for key in ["test_woods", "siege_city@ai", "gate_ops", "cit_ops", "siege_polis@ai", "bench_2000~ee",
			"siege_city@ai~ae", "bench_2000~ss", "ai_woods~as", "siege_city@ai~sa", "siege_city@ai~as"]:
		var sim := BattleSim.new()
		sim.setup(_scenario(key), 4242)
		_script_orders(sim, key)
		var bad := 0
		var checks := 0
		for stop in [300, 900, 1500]:
			while sim.tick < stop:
				sim.step()
			var blob := sim.snapshot()
			var copy := BattleSim.new()
			copy.setup(_scenario(key), 4242)
			if not copy.restore(blob):
				_fail("%s: restore refused at tick %d" % [key, stop])
				break
			for t in 120:
				sim.step()
				copy.step()
				checks += 1
				if sim.state_hash() != copy.state_hash():
					bad += 1
		if bad > 0:
			_fail("%s: restored copies diverged (%d of %d ticks)" % [key, bad, checks])
		else:
			print("PASS %s: snapshot / restore at 300, 900, 1500 runs on identically (%d ticks checked)" % [key, checks])


# ---------------------------------------------------------------- walls ---

## Garrison javelins (unit 1) on a wall of a walled town, spearmen (unit 2)
## in it; the attackers (unit 0) stand outside. No AI.
static func _wall_scenario() -> Dictionary:
	var r := Scenarios.settlement({"seed": 202, "level": 1, "walls": 1, "bld": []},
		{"kind": 1, "seed": 9, "forest": 0, "ground": 2}, [[UT.HEAVY, 60]],
		[[UT.JAVELIN, 40], [UT.SPEAR, 60]], 1, [])
	return r["scenario"]


## The wall orders run: returns {hashes, log, bad}.
func _wall_run(snap_check: bool) -> Dictionary:
	var MapGen := preload("res://sim/mapgen.gd")
	var sim := BattleSim.new()
	sim.setup(_wall_scenario(), 31)
	var hashes := PackedInt64Array()
	var bad: Array = []
	var notes: Array = []
	var jav := -1
	var spear := -1
	for u in sim.n_units:
		if sim.u_wall[u] > 0:
			jav = u
		elif sim.u_side[u] == sim.city_def:
			spear = u
	if jav < 0 or spear < 0:
		return {"hashes": hashes, "log": notes, "bad": ["no wall unit in the wall scenario"]}
	var sg0: int = sim.u_wall[jav] - 1
	# Starts in its wall line.
	if _off_line(sim, jav) > 0:
		bad.append("garrison javelins do not start in their wall line (%d men off it)" % _off_line(sim, jav))
	var mid := BattleSim.seg_pt(sim, sg0, BattleSim.seg_len(sim, sg0) / 2)
	var dir: int = sim.ws_dir[sg0]
	# Taps: the walkway; the wall's body (outward from the walkway to the
	# parapet); a tower (along the centre line past an end); "Man the wall".
	var parapet := Vector2i(-1, -1)
	for q in 24:
		var px: int = mid.x + FM.cos_a(dir) * q * 256 / 4096
		var py: int = mid.y + FM.sin_a(dir) * q * 256 / 4096
		if sim.obs_kind(px, py) == MapGen.C_WALL:
			parapet = Vector2i(px, py)
			break
	var tower := Vector2i(-1, -1)
	for e in 2:
		var a := BattleSim.seg_pt(sim, sg0, 0 if e == 0 else BattleSim.seg_len(sim, sg0))
		var b := BattleSim.seg_pt(sim, sg0, BattleSim.seg_len(sim, sg0) if e == 0 else 0)
		var l := maxi(FM.approx_len(a.x - b.x, a.y - b.y), 1)
		for q in 40:
			var tx: int = a.x + (a.x - b.x) * q * 512 / l
			var ty: int = a.y + (a.y - b.y) * q * 512 / l
			if sim.obs_kind(tx, ty) == MapGen.C_TOWER:
				tower = Vector2i(tx, ty)
				break
		if tower.x >= 0:
			break
	if parapet.x < 0 or tower.x < 0:
		bad.append("wall scenario: no parapet / tower cell found by the stretch")
		return {"hashes": hashes, "log": notes, "bad": bad}
	var ways := ["walkway", "parapet", "tower", "man the wall"]
	for w in ways.size():
		# Down to the street just inside the wall (toward the attackers).
		var inside: Vector2i = sim.wall_inside(sim.u_wall[jav] - 1, sim.u_ax[jav], sim.u_ay[jav])
		var downs: int = sim.stat_stair_down
		_wall_order(sim, jav, inside.x, inside.y)
		if not _wall_wait(sim, hashes, 700, func() -> bool: return sim.u_wall[jav] == 0 and sim.u_stair[jav] == 0):
			bad.append("%s: the javelins did not come down" % ways[w])
			break
		if sim.stat_stair_down != downs + 1:
			bad.append("%s: %d stair descents, want 1" % [ways[w], sim.stat_stair_down - downs])
		_wall_wait(sim, hashes, 150, func() -> bool: return sim.u_order[jav] == BattleSim.O_NONE)
		var dest := mid
		if w == 1:
			dest = parapet
		elif w == 2:
			dest = tower
		elif w == 3:
			var mt := BattleSim.man_wall_target(sim, jav)
			if mt.z < 0:
				bad.append("man the wall: no stretch found")
				break
			dest = Vector2i(mt.x, mt.y)
		var want := BattleSim.wall_snap(sim, dest.x, dest.y)
		if want.z < 0:
			bad.append("%s: the tap does not snap to a stretch" % ways[w])
			break
		var ups: int = sim.stat_stair_up
		_wall_order(sim, jav, dest.x, dest.y)
		var ok := _wall_wait(sim, hashes, 900, func() -> bool:
			return sim.u_wall[jav] > 0 and sim.u_stair[jav] == 0 and _off_line(sim, jav) == 0)
		if sim.stat_stair_up != ups + 1 or sim.u_wall[jav] - 1 != want.z:
			bad.append("%s: %d climbs, on stretch %d (want 1 climb onto %d)" % [ways[w], sim.stat_stair_up - ups,
				sim.u_wall[jav] - 1, want.z])
		elif not ok:
			bad.append("%s: on the wall but %d men are off their wall line" % [ways[w], _off_line(sim, jav)])
		notes.append("%s up by tick %d" % [ways[w], sim.tick])
		if snap_check and w == 1:
			# Snapshot / restore on the wall: runs on identically.
			var blob := sim.snapshot()
			var copy := BattleSim.new()
			copy.setup(_wall_scenario(), 31)
			if not copy.restore(blob):
				bad.append("wall orders: restore refused")
			else:
				for t in 120:
					sim.step()
					copy.step()
					hashes.append(sim.state_hash())
					if sim.state_hash() != copy.state_hash():
						bad.append("wall orders: restored copy diverged at tick %d" % sim.tick)
						break
	# A unit longer than its stretch: the spearmen onto a short stretch with
	# a joined neighbour spill through the tower onto it.
	var fsp := UT.stat(sim.u_type[spear], "file_sp")
	var need := BattleSim.wall_nf(sim.u_alive[spear]) * fsp
	var short := -1
	for sg in sim.ws_x0.size():
		if sg != sim.u_wall[jav] - 1 and BattleSim.seg_len(sim, sg) < need \
				and (sim.ws_nb[sg * 2] >= 0 or sim.ws_nb[sg * 2 + 1] >= 0):
			short = sg
			break
	if short < 0:
		bad.append("spill: no short joined stretch on the map")
	else:
		var sp := BattleSim.seg_pt(sim, short, BattleSim.seg_len(sim, short) / 2)
		_wall_order(sim, spear, sp.x, sp.y)
		var ok2 := _wall_wait(sim, hashes, 1500, func() -> bool:
			return sim.u_wall[spear] > 0 and sim.u_stair[spear] == 0 and _off_line(sim, spear) <= 1)
		var on_nb := 0
		var base: int = sim.u_slot_base[spear]
		for q in sim.u_alive[spear]:
			var i: int = sim.slot_soldier[base + q]
			var best := -1
			var best_o := 1 << 40
			for sg in sim.ws_x0.size():
				var o: int = sim._seg_off(sg, sim.pos_x[i], sim.pos_y[i])
				if o < best_o:
					best_o = o
					best = sg
			if best != short:
				on_nb += 1
		if not ok2 or sim.u_wall[spear] - 1 != short:
			bad.append("spill: the spearmen did not take their line on stretch %d (on %d, %d off the line)" % [short,
				sim.u_wall[spear] - 1, _off_line(sim, spear)])
		elif on_nb == 0:
			bad.append("spill: no man on the joined stretch")
		notes.append("spill: %d of %d spearmen on the joined stretch, by tick %d" % [on_nb, sim.u_alive[spear], sim.tick])
	return {"hashes": hashes, "log": notes, "bad": bad}


## Men of wall unit u more than 1.5 m from their place in its wall line or
## off the walkway (towers count as walkway: a spilled line passes them).
static func _off_line(sim, u: int) -> int:
	var MapGen := preload("res://sim/mapgen.gd")
	var sl := BattleSim.wall_slots(sim, sim.u_wall[u] - 1, sim.u_ax[u], sim.u_ay[u], sim.u_alive[u], sim.u_type[u])
	var base: int = sim.u_slot_base[u]
	var off := 0
	for q in sim.u_alive[u]:
		var i: int = sim.slot_soldier[base + q]
		# His place: the sim's (anchor + offset) is the wall line's.
		if sim.u_ax[u] + sim.off_x[base + q] != sl[q * 2] or sim.u_ay[u] + sim.off_y[base + q] != sl[q * 2 + 1]:
			off += 1
			continue
		var dx: int = sl[q * 2] - sim.pos_x[i]
		var dy: int = sl[q * 2 + 1] - sim.pos_y[i]
		var k: int = sim.obs_kind(sim.pos_x[i], sim.pos_y[i])
		if dx * dx + dy * dy > 1536 * 1536 or (k != MapGen.C_WALK and k != MapGen.C_TOWER):
			off += 1
	return off


## A tap-like move order for unit u to (x, y) (the defenders' player).
static func _wall_order(sim, u: int, x: int, y: int) -> void:
	var o := BattleSim.make_move_order(sim.tick, u, x, y, sim.u_face[u],
		BattleSim.files_to_width(sim.u_files[u], sim.u_type[u]), 0)
	o["player"] = 51
	sim.queue_order(o)


## Step until cond holds (true) or `most` ticks pass (false).
static func _wall_wait(sim, hashes: PackedInt64Array, most: int, cond: Callable) -> bool:
	for t in most:
		sim.step()
		hashes.append(sim.state_hash())
		if cond.call():
			return true
	return false


func _check_wall_orders() -> void:
	var a := _wall_run(true)
	var b := _wall_run(false)
	var bad: Array = a["bad"]
	var ha: PackedInt64Array = a["hashes"]
	var hb: PackedInt64Array = b["hashes"]
	# Run b has no snapshot detour: compare up to it.
	var n := 0
	for t in mini(ha.size(), hb.size()):
		if ha[t] != hb[t]:
			break
		n += 1
	if n < 200:
		bad.append("wall orders: repeat runs diverged at step %d" % n)
	if bad.is_empty():
		print("PASS wall orders: down and back up by walkway, parapet, tower and Man the wall, in the wall line each time; spill onto the joined stretch; repeatable, snapshot / restore (%s)" % "; ".join(a["log"]))
	else:
		for x in bad:
			_fail("walls: " + str(x))


## A drag longer than a unit's single rank: exactly one rank.
func _check_line_clamp() -> void:
	var sim := BattleSim.new()
	sim.setup(Scenarios.make("skirmish"), 5)
	var u := 0
	var alive: int = sim.u_alive[u]
	sim.queue_order(BattleSim.make_move_order(1, u, sim.u_ax[u], sim.u_ay[u] - 20 * M, 768, 900 * M, 0))
	for t in 5:
		sim.step()
	if sim.u_files[u] != alive or sim.unit_depth(u) != 0:
		_fail("an over-long drag gave %d files of %d men (depth %d), want one rank" % [sim.u_files[u], alive, sim.unit_depth(u)])
	else:
		print("PASS drag clamp: a 900 m line forms one rank of %d" % alive)


# ---------------------------------------------------------- reachability ---

## Attackers (side 0): heavy foot 0, archers 1; defenders (side 1): spears
## 2 inside the shut town. No AI.
static func _reach_scenario() -> Dictionary:
	var r := Scenarios.settlement({"seed": 202, "level": 1, "walls": 1, "bld": []},
		{"kind": 1, "seed": 9, "forest": 0, "ground": 2}, [[UT.HEAVY, 60], [UT.ARCHER, 40]],
		[[UT.SPEAR, 60]], 1, [])
	return r["scenario"]


func _reach_run() -> Dictionary:
	var sim := BattleSim.new()
	sim.setup(_reach_scenario(), 21)
	var bad: Array = []
	var notes: Array = []
	var hashes := PackedInt64Array()
	var heavy := -1
	var arch := -1
	var spear := -1
	for u in sim.n_units:
		var c := UT.cls(sim.u_type[u])
		if sim.u_side[u] == sim.city_def:
			spear = u
		elif c == UT.CLS_MISSILE:
			arch = u
		else:
			heavy = u
	var outside: int = sim.reach_at(sim.u_ax[heavy], sim.u_ay[heavy])
	var inside: int = sim.reach_at(sim.u_ax[spear], sim.u_ay[spear])
	if outside < 0 or inside < 0 or outside == inside:
		return {"bad": ["reach: the shut town is not two pieces (%d, %d)" % [outside, inside]], "notes": notes, "hashes": hashes}
	# (a) A tap on the plaza from outside: to the gate, and it holds there.
	sim.queue_order(BattleSim.make_move_order(1, heavy, sim.plaza[0], sim.plaza[1], 768, 20 * M, 1))
	var off_slot := 0
	for t in 1200:
		sim.step()
		hashes.append(sim.state_hash())
		if t % 10 == 0:
			off_slot += _bad_slots(sim)
		if t > 20 and sim.u_order[heavy] == BattleSim.O_NONE:
			break
	for t in 60:
		sim.step()  # (its men take their places)
		hashes.append(sim.state_hash())
	var at_gate := _at_gate(sim, heavy)
	if sim.reach_at(sim.u_ax[heavy], sim.u_ay[heavy]) != outside:
		bad.append("reach (a): the heavy foot's anchor left its ground")
	if at_gate < 0 or sim.u_order[heavy] != BattleSim.O_NONE:
		bad.append("reach (a): ordered into the shut town, the heavy foot did not stop at a gate")
	var strung := _strung(sim, heavy)
	if strung > 0:
		bad.append("reach (a): %d men strung out from their unit at the gate" % strung)
	notes.append("(a) holds at gate %d from tick %d, %d men strung out" % [at_gate, sim.tick, strung])
	# (b) A fresh battle: the heavy foot and the archers ordered to attack
	# the spearmen inside. The foot go to the gate and hack it, (c) go in
	# once it breaks; (e) the archers shoot from outside.
	sim = BattleSim.new()
	sim.setup(_reach_scenario(), 21)
	sim.queue_order(BattleSim.make_attack_order(1, heavy, spear, 1))
	sim.queue_order(BattleSim.make_attack_order(1, arch, spear, 0))
	var broke := -1
	var arch_in := 0
	var gate_t := -1
	var went_in := -1
	for t in 3000:
		sim.step()
		hashes.append(sim.state_hash())
		if t % 10 == 0:
			off_slot += _bad_slots(sim)
			if broke < 0 and sim.reach_at(sim.u_ax[arch], sim.u_ay[arch]) != outside:
				arch_in += 1
		if gate_t < 0 and _at_gate(sim, heavy) >= 0:
			gate_t = sim.tick
		if broke < 0:
			for g in sim.n_gates:
				if sim.g_state[g] == BattleSim.GATE_BROKEN:
					broke = sim.tick
		elif went_in < 0 and (sim.reach_at(sim.u_ax[heavy], sim.u_ay[heavy]) != outside or sim.u_fighting[heavy] != 0 \
				or sim.u_state[spear] != BattleSim.U_READY):
			went_in = sim.tick
		if went_in >= 0:
			break
	if gate_t < 0:
		bad.append("reach (b): attacking a unit inside, the heavy foot never came to a gate")
	if sim.stat_gate_hack <= 0:
		bad.append("reach (b): nobody hacked at the gate")
	if broke < 0:
		bad.append("reach (c): the gate never broke")
	elif went_in < 0:
		bad.append("reach (c): the gate is broken but the heavy foot did not go in")
	if sim.stat_shots <= 0:
		bad.append("reach (e): the archers did not shoot at the spearmen inside")
	if arch_in > 0:
		bad.append("reach (e): the archers' anchor left the outside before the gate broke")
	if off_slot > 0:
		bad.append("reach (d): %d places of standing units on a wall, a house or other ground" % off_slot)
	notes.append("(b) at the gate at tick %d, hacked %d hp, (c) broken at tick %d, in at %d, (e) archers shot %d, (d) no place off its ground" % [
		gate_t, sim.stat_gate_hack / 100, broke, went_in, sim.stat_shots])
	return {"bad": bad, "notes": notes, "hashes": hashes}


## The gate whose front (attackers' side) unit u's anchor stands at, or -1.
static func _at_gate(sim, u: int) -> int:
	for g in sim.n_gates:
		var f: Vector3i = sim.gate_front(g, sim.u_side[u])
		if FM.approx_len(f.x - sim.u_ax[u], f.y - sim.u_ay[u]) <= 3 * M:
			return g
	return -1


## Men of unit u farther from the anchor than its depth + 8 m.
static func _strung(sim, u: int) -> int:
	var lim: int = sim.unit_depth(u) + BattleSim.files_to_width(sim.u_files[u], sim.u_type[u]) / 2 + 8 * M
	var n := 0
	var base: int = sim.u_slot_base[u]
	for q in sim.u_alive[u]:
		var i: int = sim.slot_soldier[base + q]
		if FM.approx_len(sim.pos_x[i] - sim.u_ax[u], sim.pos_y[i] - sim.u_ay[u]) > lim:
			n += 1
	return n


## Places (anchor + offset) of standing ground units near obstacles that are
## not on their anchor's ground.
static func _bad_slots(sim) -> int:
	var n := 0
	for u in sim.n_units:
		if sim.u_state[u] != BattleSim.U_READY or sim.u_wall[u] > 0 or sim.u_stair[u] != 0 \
				or sim.u_order[u] != BattleSim.O_NONE or sim.u_dirty[u] != 0 or sim._u_obs[u] == 0:
			continue
		var ra: int = sim.reach_at(sim.u_ax[u], sim.u_ay[u])
		if ra < 0:
			continue
		var base: int = sim.u_slot_base[u]
		for q in sim.u_alive[u]:
			if sim.reach_at(sim.u_ax[u] + sim.off_x[base + q], sim.u_ay[u] + sim.off_y[base + q]) != ra:
				n += 1
	return n


func _check_reach() -> void:
	var a := _reach_run()
	var b := _reach_run()
	var bad: Array = a["bad"]
	if a["hashes"] != b["hashes"]:
		bad.append("reach: repeat runs differ")
	if bad.is_empty():
		print("PASS reachability: %s; repeatable" % "; ".join(a["notes"]))
	else:
		for x in bad:
			_fail(str(x))
