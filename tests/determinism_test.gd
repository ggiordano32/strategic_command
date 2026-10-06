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
## Exits 0 on success, 1 on failure.

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const Terrain := preload("res://sim/terrain.gd")

const M := 1024

## scenario -> ticks to run
## (Playable battles have random generated terrain; "@kind" forces a kind.)
const RUNS := {"skirmish@0": 1500, "battle_2000@0": 1800, "bench_2000": 2500, "test_cav_spears": 600,
	"test_cav_art": 700, "battle_2000@2": 1800, "bench_2000@4": 3000, "bench_2000@3": 2500,
	"test_bolts_crest": 500, "test_attack_uphill": 1500, "test_ridge_defend": 1500,
	"ai_hill": 1800, "ai_ridge": 600, "test_woods": 1200, "siege_village@ai": 3500,
	"siege_city@ai": 4200, "siege_hill@ai": 3000, "gate_ops": 1800}

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
			need = ["paths", "clamp", "squeeze", "veg_slow", "capture"]
		"siege_city@ai":
			need = ["paths", "clamp", "squeeze", "gate_art", "gate_broken", "obs_lof", "wall_cover"]
		"siege_hill@ai":
			need = ["paths", "clamp", "gate_art", "gate_broken", "wall_cover", "obs_lof"]
		"gate_ops":
			need = ["gate_close", "gate_open", "gate_hack", "gate_art", "gate_broken", "paths"]
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
	if key.ends_with("@ai"):
		var sa := Scenarios.make(key.get_slice("@", 0))
		sa["ai_sides"] = [0, 1]
		return sa
	if key == "gate_ops":
		var r := Scenarios.settlement({"seed": 202, "level": 1, "walls": 1, "bld": []},
			{"kind": 1, "seed": 9, "forest": 20, "ground": 2}, [[UT.HEAVY, 100], [UT.BOLT, 16]],
			[[UT.ARCHER, 40], [UT.SPEAR, 60]], 1, [])
		return r["scenario"]
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
		"gate_broken": sim.stat_gate_broken, "capture": sim.stat_capture, "ai_shelter": sim.stat_ai[15]}
	print("  %s seed %d: alive %d/%d after %d ticks, winner %d" % [scen, p_seed,
		sim.alive_count(0), sim.alive_count(1), ticks, sim.winner])
	return {"hashes": hashes, "result": sim.result(), "stats": stats}


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


## Snapshot / restore round trips on woods and settlement battles: a copy
## restored at several ticks runs on with exactly the original's hashes.
func _check_snapshots() -> void:
	for key in ["test_woods", "siege_city@ai", "gate_ops"]:
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
