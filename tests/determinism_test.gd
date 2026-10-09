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
## Deployment phase (October 2026): a field battle and a settlement battle
## with "deploy_time": nothing moves during it, placements are kept to the
## side's zone (clamped on the field, refused outside the walls, onto a
## walkway for wall units), move orders are refused, the AI's line is
## placed at the start, the battle starts when the player is ready or when
## the countdown runs out; identical on repeat and across snapshot / restore
## mid-deployment and mid-battle.
## Siege equipment and wall towers (2026-10-07): the equal-force walls-3
## siege with ladders, a ram, the city's tower engines and a 20 minute time
## limit ("siege_eq_ring3"), and a walls-2 polis with ladders, a Workshop's
## extra tower shots and a Skilled attacker ("siege_eq_polis2~sa"):
## identical on repeat and across snapshot / restore; men climbed ladders,
## the ram struck, towers were hit. Field battles and walls-0/1 cities hash
## as before; walls-2/3 cities changed (towers, harder gates, cover).
## Units do not pass through each other (2026-10-07; "--only=blocking"): a
## street fight (two columns meeting in a 10 m street: one unit a side
## fights, the rest wait), a unit passing through a standing friend (slower
## than round it), four units through one open gate (none freezes), and the
## "gate rush" (foot and riders at the run ordered to the plaza past a spear
## unit holding the gateway, or standing 14 m inside: never through it,
## never behind it in the gateway, the plaza clock never starts); each
## identical on repeat and across snapshot / restore. The flat-map golden
## digests of skirmish and bench_2000 were re-recorded for it.
## The defenders' layout at the attacked gate (2026-10-08, part 2c;
## "--only=layout"): an equal-force walls-1 ring town, both sides Average:
## the stack's front at the attacked gate's inner mouth before the gate
## falls, the quiet gates' guards at their places in the stack, the plaza
## reserve counter-attacking; identical on repeat and across snapshot /
## restore. Settlement battles hash differently (the layout, defenders'
## routers running to a shut gate inside instead of out by the breach);
## field battles and the golden digests are unchanged. "siege_city@ai~ea"
## runs 5,000 ticks (the Easy attackers get into the town later).
## Exits 0 on success, 1 on failure.

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const Terrain := preload("res://sim/terrain.gd")
const SiegeAI := preload("res://sim/siege_ai.gd")
const BattleAI := preload("res://sim/battle_ai.gd")
const FM := preload("res://sim/fixed_math.gd")
const AIP := preload("res://sim/ai_profile.gd")

const M := 1024

## scenario -> ticks to run
## (Playable battles have random generated terrain; "@kind" forces a kind.)
const RUNS := {"skirmish@0": 1500, "battle_2000@0": 1800, "bench_2000": 2500, "test_cav_spears": 600,
	"test_cav_art": 700, "battle_2000@2": 1800, "bench_2000@4": 3000, "bench_2000@3": 2500,
	"test_bolts_crest": 500, "test_attack_uphill": 1500, "test_ridge_defend": 1500,
	"ai_hill": 1800, "ai_ridge": 600, "test_woods": 1200, "siege_village@ai": 3500,
	"siege_city@ai": 4200, "siege_hill@ai": 3000, "gate_ops": 1800,
	"siege_castrum@ai": 3600, "siege_polis@ai": 4500, "siege_punic@ai": 6500, "siege_oppidum@ai": 3600,
	"cit_ops": 3200, "bench_2000~ee": 2500, "bench_2000@4~ea": 3000, "siege_city@ai~ea": 5000,
	"siege_city@ai~ae": 4200, "bench_2000~ss": 2500, "bench_2000@4~sa": 3000, "ai_woods~as": 2500,
	"siege_city@ai~sa": 4200, "siege_city@ai~as": 4200, "siege_eq_ring3": 4500, "siege_eq_polis2~sa": 4500}

## Trajectory digests of flat battles (soldier and unit arrays every 50
## ticks over 2,500 ticks, seed 4242): flat maps must keep playing exactly
## like this. Update only for an intended change of flat-map rules. History:
## terrain height left the digests of commit 49c1022 unchanged; they were
## re-recorded for more ammunition, stones aimed at the near face and the
## artillery Refill order (October 2026), and for units that do not pass
## through each other (2026-10-07: skirmish and bench_2000 changed, the two
## artillery set pieces did not).
const GOLDEN := {"skirmish": "65e6f576f5248be9", "bench_2000": "45a3d1affeff41e8",
	"test_cav_art": "2614adc80bd29eb4", "test_stone_line": "62b07015506232ff"}

var _ok := true


func _init() -> void:
	if "--only=engines" in OS.get_cmdline_user_args():
		_check_engines()
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	_check_deploy()
	if "--only=deploy" in OS.get_cmdline_user_args():
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	_check_layout()
	if "--only=layout" in OS.get_cmdline_user_args():
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	_check_equipment()
	_check_shut_inner_gate()
	_check_engines()
	if "--only=equipment" in OS.get_cmdline_user_args():
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	_check_blocking()
	if "--only=blocking" in OS.get_cmdline_user_args():
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
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
			need = ["paths", "clamp", "squeeze", "gate_art", "gate_broken", "obs_lof", "wall_cover", "layout"]
		"siege_hill@ai":
			# (Walls 3 since the tower engines: the batteries batter the towers
			# by the gate first, so the gate stands past the run, and the
			# archers keep out of the walls' longer reach.)
			# (No gate_hack: walls-3 gates do not yield to swords.)
			need = ["paths", "clamp", "obs_lof", "tower_hits"]
		"gate_ops":
			need = ["gate_close", "gate_open", "gate_hack", "gate_art", "gate_broken", "paths"]
		"siege_castrum@ai":
			need = ["paths", "clamp", "gate_broken", "wall_cover", "obs_lof"]
		"siege_polis@ai":
			# (Part 2c: the defenders hold the gate's mouth and their wall
			# units stay up, nobody falls back to the acropolis within the
			# run: stair moves and the shut gate are cit_ops' and punic's.)
			need = ["paths", "gate_broken", "obs_lof", "layout"]
		"siege_punic@ai":
			need = ["paths", "gate_broken", "stair_down", "gate_art", "gate_close"]
		"siege_oppidum@ai":
			# (Part 2c: no wall unit routs off its stretch within the run.)
			need = ["paths", "gate_broken", "gate_art", "layout"]
		"cit_ops":
			need = ["stair_down", "stair_up", "gate_close", "gate_open", "gate_hack", "gate_broken", "capture"]
		"bench_2000~ee", "bench_2000@4~ea", "siege_city@ai~ea", "siege_city@ai~ae":
			need = ["mistakes", "attacks"]
		"bench_2000~ss", "bench_2000@4~sa", "ai_woods~as", "siege_city@ai~sa":
			need = ["skilled", "attacks"]
		"siege_city@ai~as":
			# (Average attackers at an iron-bound gate: no foot go in within
			# the run since walls-2/3 gates do not yield to swords.)
			need = ["skilled"]
		"siege_eq_ring3":
			# (The AI's ladders come late at the carry pace: the scripted
			# "equipment" case covers planting and climbing.)
			need = ["pickups", "tower_hits", "bolts", "stones", "wall_cover", "gate_broken"]
		"siege_eq_polis2~sa":
			need = ["pickups", "tower_hits", "bolts", "skilled", "gate_broken"]
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
	if key == "siege_eq_ring3":
		# The equal-force walls-3 siege with ladders, a ram, the city's tower
		# engines and a 20 minute time limit (docs/DESIGN.md "Siege
		# equipment and wall towers"), both sides AI.
		var se := Scenarios.fair_siege(741, 3, 4, {"ladders": 3, "ram": 1})
		se["time_limit"] = 1200
		return se
	if key == "siege_eq_polis2":
		# A walls-2 polis (its acropolis), ladders only, a workshop's extra shots.
		var sp := Scenarios.fair_siege(782, 2, 1, {"ladders": 2})
		(sp["terrain"]["city"]["bld"] as Array).append(5)
		return sp
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
		"ditch": sim.stat_ditch, "sea_exit": sim.stat_sea_exit, "mistakes": _mistakes(sim),
		"ladder_up": sim.stat_ladder_up, "ram_blows": sim.stat_ram_blows, "tower_hits": sim.stat_tower_hits,
		"unbar": sim.stat_unbar, "pickups": sim.stat_pickups, "planted": sim.stat_planted, "drops": sim.stat_drops,
		"layout": sim.stat_ai[SiegeAI.A_MOUTH] + sim.stat_ai[SiegeAI.A_PLAZA]}
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
			"siege_city@ai~ae", "bench_2000~ss", "ai_woods~as", "siege_city@ai~sa", "siege_city@ai~as",
			"siege_eq_ring3", "siege_eq_polis2~sa"]:
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


# ------------------------------------------------------ siege equipment ---
# Siege equipment as objects (docs/DESIGN.md "Siege equipment and wall
# towers", part 2b): pick up, carry, drop, plant, climb, ram; and the shut
# inner gate (nobody fights a wall).

## The equipment set piece: a walls-2 ring, three attacking units with two
## ladder sets and a ram, scripted (no AI): the heavy picks up set 0 and
## plants it on the nearest stretch it can (and climbs), the light picks up
## set 1 and puts it down again, the pikes carry the ram to gate 0 and
## batter it (putting it down once it breaks). Hashes every tick; a second
## run equal; a copy restored mid-carry runs on equal.
func _equip_run(snap_check: bool) -> Dictionary:
	var city := {"seed": 4242, "level": 2, "walls": 2, "bld": []}
	var terr := {"kind": Terrain.K_FLAT, "seed": 11, "forest": 0, "ground": 2}
	var r := Scenarios.settlement(city, terr, [[UT.HEAVY, 60], [UT.LIGHT, 60], [UT.PIKE, 60]], [[UT.SPEAR, 20]], 1, [],
		{"ladders": 2, "ram": 1})
	var sc: Dictionary = r["scenario"]
	var sim := BattleSim.new()
	sim.setup(sc, 77)
	var hashes := PackedInt64Array()
	var ram_q := sim.n_eq - 1
	var dropped := -1
	var snap_bad := -1
	var snap_t := -1
	for t in 3000:
		if t % 10 == 0:
			if sim.u_carry[0] < 0 and sim.q_state[0] == BattleSim.Q_GROUND and sim.u_pick[0] != 0:
				sim.queue_order({"tick": sim.tick, "type": BattleSim.ORDER_PICKUP, "unit": 0, "equip": 0, "run": 1})
			elif sim.u_carry[0] == 0 and sim.u_stair[0] == 0 and sim.u_order[0] != BattleSim.O_MOVE:
				var best := -1
				var bd := 0
				for sg in sim.ws_x0.size():
					var mp: Vector2i = BattleSim.seg_pt(sim, sg, BattleSim.seg_len(sim, sg) / 2)
					if BattleSim.ladder_set_for(sim, 0, sg, mp.x, mp.y) < 0:
						continue
					var d := absi(mp.x - sim.u_cx[0]) + absi(mp.y - sim.u_cy[0])
					if best < 0 or d < bd:
						best = sg
						bd = d
				if best >= 0:
					var lp: Vector2i = BattleSim.seg_pt(sim, best, BattleSim.seg_len(sim, best) / 2)
					sim.queue_order(BattleSim.make_move_order(sim.tick, 0, lp.x, lp.y, 768, 20 * 1024, 0))
			if dropped < 0 and sim.u_carry[1] < 0 and sim.u_pick[1] != 1:
				sim.queue_order({"tick": sim.tick, "type": BattleSim.ORDER_PICKUP, "unit": 1, "equip": 1, "run": 1})
			elif dropped < 0 and sim.u_carry[1] == 1:
				dropped = sim.tick
				sim.queue_order({"tick": sim.tick, "type": BattleSim.ORDER_DROP, "unit": 1})
			if sim.u_carry[2] < 0 and sim.q_state[ram_q] == BattleSim.Q_GROUND and sim.g_state[0] == BattleSim.GATE_CLOSED \
					and sim.u_pick[2] != ram_q:
				sim.queue_order({"tick": sim.tick, "type": BattleSim.ORDER_PICKUP, "unit": 2, "equip": ram_q, "run": 0})
			elif sim.u_carry[2] == ram_q and sim.u_gtarget[2] != 0 and sim.g_state[0] == BattleSim.GATE_CLOSED:
				sim.queue_order({"tick": sim.tick, "type": BattleSim.ORDER_ATTACK, "unit": 2, "target": -1, "gate": 0, "run": 0})
		sim.step()
		hashes.append(sim.state_hash())
		if snap_check and snap_t < 0 and sim.u_carry[2] == ram_q and sim.u_carry[0] == 0:
			snap_t = sim.tick
			var b := BattleSim.new()
			b.setup(sc, 77)
			b.restore(sim.snapshot())
			var c := sim.snapshot()
			var a2 := BattleSim.new()
			a2.setup(sc, 77)
			a2.restore(c)
			for k in 300:
				a2.step()
				b.step()
				if a2.state_hash() != b.state_hash():
					snap_bad = k
					break
	return {"hashes": hashes, "pickups": sim.stat_pickups, "drops": sim.stat_drops, "planted": sim.stat_planted,
		"up": sim.stat_ladder_up, "blows": sim.stat_ram_blows, "broken": sim.g_state[0] == BattleSim.GATE_BROKEN,
		"ram_state": sim.q_state[ram_q], "snap_t": snap_t, "snap_bad": snap_bad, "dropped": dropped}


func _check_equipment() -> void:
	var a := _equip_run(true)
	var b := _equip_run(false)
	if a["hashes"] != b["hashes"]:
		_fail("equipment: the repeat diverged")
		return
	if int(a["snap_t"]) < 0 or int(a["snap_bad"]) >= 0:
		_fail("equipment: no snapshot mid-carry, or the restored copy diverged (%s)" % str(a.erase("hashes")))
		return
	if int(a["pickups"]) < 3 or int(a["drops"]) < 2 or int(a["planted"]) < 1 or int(a["up"]) <= 0 \
			or int(a["blows"]) <= 0 or not a["broken"] or int(a["ram_state"]) != BattleSim.Q_GROUND:
		a.erase("hashes")
		_fail("equipment: %s" % str(a))
		return
	print("PASS equipment: picked up %d, put down %d (the light's set at tick %d, the ram as the gate broke), planted %d, men up %d, ram blows %d; identical on repeat and across snapshot / restore mid-carry (tick %d)" % [
		a["pickups"], a["drops"], a["dropped"], a["planted"], a["up"], a["blows"], a["snap_t"]])


# ------------------------------------------------- engines as equipment ---
# Engines are equipment, crews are men (docs/DESIGN.md "Artillery").

## A bolt battery leaves its engines (tick 10) and walks off as plain men; an
## archer unit (2 arrows a man, holding fire) takes them up, shoots the heavy
## foot with them, leaves them once it has 3 kills and has its 80 arrows
## back; an enemy light unit then takes them (a capture) and shoots with
## them. Scripted, no AI. Returns the tick of each step, what was seen at
## it, the hashes of every tick and the kill tallies.
func _engine_run(snap_check: bool) -> Dictionary:
	var sc := {"width_m": 300, "height_m": 300, "ai_sides": [], "orders": [], "units": [
		Scenarios.unit(0, UT.BOLT, 16, 150, 200, Scenarios.FACE_UP),
		Scenarios.unit(0, UT.ARCHER, 40, 110, 215, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.HEAVY, 60, 150, 60, Scenarios.FACE_DOWN),
		Scenarios.unit(1, UT.LIGHT, 40, 250, 120, Scenarios.FACE_DOWN)]}
	var sim := BattleSim.new()
	sim.setup(sc, 4242)
	var base: int = sim.u_slot_base[1]
	for s in sim.u_alive[1]:
		sim.ammo[sim.slot_soldier[base + s]] = 2
	sim.u_ammo[1] = 2 * sim.u_alive[1]
	sim.u_fire[1] = 0
	sim.u_fire[0] = 0
	var ev := {}
	var bad: Array[String] = []
	var hashes := PackedInt64Array()
	var snap_t := -1
	var snap_bad := -1
	for t in 1500:
		var tk: int = sim.tick
		if tk == 10:
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_DROP, "unit": 0})
		if tk == 11:
			ev["drop0"] = tk
			var all_left := true
			for k in 4:
				all_left = all_left and sim.e_state[k] == BattleSim.E_ABANDONED
			if sim.u_eg[0] != -1 or sim.u_type[0] != UT.LIGHT or sim.u_cls[0] != UT.CLS_INF or sim.u_neng[0] != 0 \
					or not all_left or not sim.engines_free(0) or sim.u_ammo[0] != 0:
				bad.append("the battery did not leave its engines as plain men")
			sim.queue_order(BattleSim.make_move_order(tk, 0, 50 * M, 260 * M, Scenarios.FACE_UP, 10 * M, 0))
		if tk == 20:
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_PICKUP, "unit": 1, "engines": 0, "run": 0})
		if not ev.has("pick1") and sim.u_eg[1] == 0:
			ev["pick1"] = tk
			if sim.u_type[1] != UT.BOLT or sim.u_cls[1] != UT.CLS_ART or sim.u_ammo[1] != 44 or sim.u_oammo[1] != 80 \
					or sim.u_depl[1] != UT.stat(UT.BOLT, "deploy") or sim.e_unit[0] != 1 or sim.e_state[0] != BattleSim.E_OK:
				bad.append("the archers did not take the engines up as a set-up battery with their own arrows put aside")
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_ATTACK, "unit": 1, "target": 2, "run": 0})
		if ev.has("pick1") and not ev.has("drop1") and sim.u_kills[1] >= 3:
			ev["drop1"] = tk
			ev["bolts1"] = sim.stat_bolts
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_DROP, "unit": 1})
		if ev.has("drop1") and not ev.has("plain1") and sim.u_eg[1] < 0:
			ev["plain1"] = tk
			if sim.u_type[1] != UT.ARCHER or sim.u_cls[1] != UT.CLS_MISSILE or sim.u_ammo[1] != 2 * sim.u_alive[1] \
					or sim.u_alive[1] != 40 or sim.e_state[0] != BattleSim.E_ABANDONED:
				bad.append("the archers did not get their arrows back (ammo %d)" % sim.u_ammo[1])
			sim.queue_order(BattleSim.make_move_order(tk, 1, 110 * M, 260 * M, Scenarios.FACE_UP, 20 * M, 0))
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_PICKUP, "unit": 3, "engines": 0, "run": 1})
		if ev.has("plain1") and not ev.has("cap3") and sim.u_eg[3] == 0:
			ev["cap3"] = tk
			ev["ammo3"] = sim.u_ammo[3]
			if sim.u_type[3] != UT.BOLT or sim.e_unit[0] != 3 or sim.eg_side[0] != 1:
				bad.append("the enemy did not capture the engines")
		sim.step()
		hashes.append(sim.state_hash())
		if snap_check and snap_t < 0 and ev.has("plain1") and sim.u_pick[3] >= BattleSim.PICK_ENG:
			# Mid-flow: the engines on the ground, the enemy on its way to them.
			snap_t = sim.tick
			var a2 := BattleSim.new()
			a2.setup(sc, 4242)
			a2.restore(sim.snapshot())
			var b2 := BattleSim.new()
			b2.setup(sc, 4242)
			b2.restore(sim.snapshot())
			for k in 400:
				a2.step()
				b2.step()
				if a2.state_hash() != b2.state_hash():
					snap_bad = k
					break
			if snap_bad < 0 and a2.u_eg[3] != 0:
				snap_bad = 999  # the restored copy never captured them
	var ks := [0, 0]
	for u in sim.n_units:
		ks[sim.u_side[u]] += sim.u_kills[u]
	var dead := [0, 0]
	for s in 2:
		for c in 5:
			dead[s] += sim.stat_kside[s * 5 + c]
		dead[s] -= sim.stat_ff[s]
	return {"ev": ev, "bad": bad, "hashes": hashes, "kills": sim.u_kills.duplicate(), "side_kills": ks,
		"enemy_dead": [dead[1], dead[0]], "bolts": sim.stat_bolts, "epick": sim.stat_epick, "edrop": sim.stat_edrop,
		"snap_t": snap_t, "snap_bad": snap_bad}


func _check_engines() -> void:
	var a := _engine_run(true)
	var b := _engine_run(false)
	var ev: Dictionary = a["ev"]
	if a["hashes"] != b["hashes"] or str(ev) != str(b["ev"]):
		_fail("engines: the repeat diverged")
		return
	if not (a["bad"] as Array).is_empty():
		_fail("engines: %s" % str(a["bad"]))
		return
	for k in ["drop0", "pick1", "drop1", "plain1", "cap3"]:
		if not ev.has(k):
			_fail("engines: step %s never happened (%s)" % [k, str(ev)])
			return
	var kills: PackedInt32Array = a["kills"]
	if int(a["bolts"]) <= int(ev["bolts1"]) or kills[3] <= 0 or kills[1] < 3:
		_fail("engines: the captors never shot with them (kills %s)" % str(kills))
		return
	if str(a["side_kills"]) != str(a["enemy_dead"]):
		_fail("engines: per-unit kills %s do not sum to each side's kills %s" % [str(a["side_kills"]), str(a["enemy_dead"])])
		return
	if int(a["snap_t"]) < 0 or int(a["snap_bad"]) >= 0:
		_fail("engines: no snapshot mid-flow, or the restored copy diverged (%d at %d)" % [int(a["snap_bad"]), int(a["snap_t"])])
		return
	print("PASS engines: the battery left them at %d; the archers took them up at %d, shot %d bolts (%d kills), left them at %d with their arrows back; the enemy took them at %d (%d shots left in them) and shot (%d kills); per-unit kills %s sum to the sides' kills %s; identical on repeat and across snapshot / restore (tick %d)" % [
		int(ev["drop0"]), int(ev["pick1"]), int(ev["bolts1"]), kills[1], int(ev["drop1"]), int(ev["cap3"]), int(ev["ammo3"]),
		kills[3], str(kills), str(a["side_kills"]), int(a["snap_t"])])


## The shut inner gate: an equal-force walls-2 polis with a ram, both
## sides AI, its outer gates broken at the start and the defenders falling
## back into the acropolis, which they shut (an iron-bound gate). Nobody
## hacks at it; no attacker stands fighting a man he cannot reach (behind
## a wall or a gate) for more than a tick or two; the AI brings the ram to
## it (or waits); identical on repeat and across snapshot / restore.
func _shut_run(snap_check: bool) -> Dictionary:
	var sc := Scenarios.fair_siege(700, 2, 1, {"ram": 1})
	var sim := BattleSim.new()
	sim.setup(sc, 53000)
	for g in sim.n_gates:
		if sim.g_cit[g] == 0:
			sim._break_gate(g)
	sim.step()
	sim.ai_cit[1] = 1
	for u in sim.n_units:
		if sim.u_side[u] != 1 or sim.u_state[u] != 0 or sim.is_tower(u) or sim.u_cls[u] == UT.CLS_CAV \
				or sim.u_cls[u] == UT.CLS_ART:
			continue
		BattleAI._set_mode(sim, u, SiegeAI.A_CIT)
		var post: Vector3i = SiegeAI._fallback_post(sim, u)
		sim.u_ai_x[u] = post.x
		sim.u_ai_y[u] = post.y
		BattleAI._order(sim, u, {"type": 1, "x": post.x, "y": post.y, "facing": post.z, "width": 12 * 1024, "run": 1}, 2)
	var hack0: int = sim.stat_gate_hack
	var hashes := PackedInt64Array()
	var across := 0
	var shut := -1
	var ram_at := -1
	var snap_bad := -1
	while sim.tick < 5000 and sim.winner < 0:
		sim.step()
		hashes.append(sim.state_hash())
		if shut < 0 and sim.g_state[sim.cit_gate] == BattleSim.GATE_CLOSED:
			shut = sim.tick
		for u in sim.n_units:
			if ram_at < 0 and sim.u_side[u] == 0 and sim.u_carry[u] >= 0 and sim.u_gtarget[u] == sim.cit_gate:
				ram_at = sim.tick
		for i in sim.n:
			var t: int = sim.target[i]
			if t < 0 or sim.state[i] != BattleSim.S_FIGHTING or sim.u_side[sim.unit_of[i]] != 0:
				continue
			var dx: int = sim.pos_x[t] - sim.pos_x[i]
			var dy: int = sim.pos_y[t] - sim.pos_y[i]
			var rr: int = sim.u_reach[sim.unit_of[i]] + 1024
			if dx * dx + dy * dy <= rr * rr and not sim._reach_ok(sim.pos_x[i], sim.pos_y[i], sim.pos_x[t], sim.pos_y[t]):
				across += 1
		if snap_check and sim.tick == 2000:
			var b := BattleSim.new()
			b.setup(sc, 53000)
			b.restore(sim.snapshot())
			var a2 := BattleSim.new()
			a2.setup(sc, 53000)
			a2.restore(sim.snapshot())
			for k in 300:
				a2.step()
				b.step()
				if a2.state_hash() != b.state_hash():
					snap_bad = k
					break
	return {"hashes": hashes, "shut": shut, "hack": (sim.stat_gate_hack - hack0) / 100, "across": across,
		"ram_at": ram_at, "blows": sim.stat_ram_blows, "snap_bad": snap_bad, "winner": sim.winner, "tick": sim.tick}


func _check_shut_inner_gate() -> void:
	var a := _shut_run(true)
	var b := _shut_run(false)
	if a["hashes"] != b["hashes"] or int(a["snap_bad"]) >= 0:
		_fail("shut inner gate: the repeat or the restored copy diverged (%d)" % int(a["snap_bad"]))
		return
	a.erase("hashes")
	if int(a["shut"]) < 0 or int(a["hack"]) > 0 or int(a["across"]) > 40 or int(a["ram_at"]) < 0:
		_fail("shut inner gate: %s" % str(a))
		return
	print("PASS shut inner gate: the acropolis shut at tick %d; hacked 0; man-ticks within reach of a man behind a wall %d; the ram sent at it at tick %d (%d blows); winner %d at %d; identical on repeat and across snapshot / restore" % [
		a["shut"], a["across"], a["ram_at"], a["blows"], a["winner"], a["tick"]])


# ------------------------------------------------------ defender layout ---
# The defenders' layout at the attacked gate (docs/AI.md 16, part 2c).

## An equal-force walls-1 ring town (fair siege seed 1, artillery only),
## both sides Average: the attacked gate is read and a unit of the stack
## stands at its inner mouth before the gate falls, the guards of the quiet
## gates join the stack (at their places in it), the plaza reserve
## counter-attacks an attacker; hashes every tick, the repeat equal, copies
## restored at three points run on equal.
func _layout_run(snap_check: bool) -> Dictionary:
	var sc := Scenarios.fair_siege(741, 1, 4, {})
	var sim := BattleSim.new()
	sim.setup(sc, 53197)
	var hashes := PackedInt64Array()
	var guards := {}
	var ag := -1
	var mouth_t := -1
	var fall_t := -1
	var arrived := {}
	var plaza_t := -1
	var snap_bad := 0
	while sim.tick < 4500 and sim.winner < 0:
		sim.step()
		hashes.append(sim.state_hash())
		if snap_check and (sim.tick == 600 or sim.tick == 2000 or sim.tick == 4000):
			snap_bad += _snap_diverges(sim, sc, 53197, 120)
		if sim.tick == 20:
			for u in sim.n_units:
				if sim.u_side[u] == 1 and sim.u_ai[u] == SiegeAI.A_GATE:
					guards[u] = sim.u_ai_y[u]
		if ag < 0:
			ag = sim.ai_gate[1]
			if ag < 0:
				continue
		var kn: PackedInt32Array = AIP.of(sim, 1)
		if fall_t < 0 and sim.g_state[ag] != BattleSim.GATE_CLOSED:
			fall_t = sim.tick
		if fall_t < 0 and mouth_t < 0:
			var fp: Vector3i = SiegeAI._mouth_front(sim, ag, kn, 0)
			for u in sim.n_units:
				if sim.u_side[u] == 1 and sim.u_state[u] == 0 and sim.u_ai[u] == SiegeAI.A_MOUTH \
						and sim.u_ai_y[u] == 0 and FM.approx_len(sim.u_ax[u] - fp.x, sim.u_ay[u] - fp.y) < 6 * M:
					mouth_t = sim.tick
		for u in guards:
			if int(guards[u]) == ag or arrived.has(u) or sim.u_state[u] != 0 or sim.u_ai[u] != SiegeAI.A_MOUTH:
				continue
			var pp: Vector3i = SiegeAI._mouth_post(sim, u, ag, kn)
			if FM.approx_len(sim.u_ax[u] - pp.x, sim.u_ay[u] - pp.y) < 12 * M:
				arrived[u] = sim.tick
		if plaza_t < 0:
			for u in sim.n_units:
				if sim.u_side[u] == 1 and sim.u_state[u] == 0 and sim.u_ai[u] == SiegeAI.A_PLAZA \
						and sim.u_order[u] == BattleSim.O_ATTACK and sim.u_target[u] >= 0 and sim.u_side[sim.u_target[u]] == 0:
					plaza_t = sim.tick
	return {"hashes": hashes, "ag": ag, "mouth": mouth_t, "fall": fall_t, "arrived": arrived.size(),
		"arrived_t": str(arrived.values()), "plaza": plaza_t, "snap_bad": snap_bad, "winner": sim.winner, "tick": sim.tick,
		"rot": sim.stat_aic[AIP.N_COUNTERS + AIP.C_ROTATION]}


func _check_layout() -> void:
	var a := _layout_run(true)
	var b := _layout_run(false)
	if a["hashes"] != b["hashes"]:
		_fail("layout: the repeat diverged")
		return
	if int(a["snap_bad"]) > 0:
		_fail("layout: restored copies diverged (%d ticks)" % int(a["snap_bad"]))
		return
	a.erase("hashes")
	if int(a["ag"]) < 0 or int(a["mouth"]) < 0 or int(a["fall"]) < 0 or int(a["mouth"]) >= int(a["fall"]) \
			or int(a["arrived"]) < 2 or int(a["plaza"]) < 0:
		_fail("layout: %s" % str(a))
		return
	print("PASS layout: gate %d read, the stack's front at its inner mouth at tick %d (the gate fell at %d); %d quiet-gate guards at their places in the stack (ticks %s); the plaza reserve attacked at tick %d; %d reliefs; winner %d at %d; identical on repeat and across snapshot / restore at 600, 2000, 4000" % [
		a["ag"], a["mouth"], a["fall"], a["arrived"], a["arrived_t"], a["plaza"], a["rot"], a["winner"], a["tick"]])


# ------------------------------------------------------------- blocking ---
# Units do not pass through each other (docs/DESIGN.md "Unit blocking and
# street fights"): a street fight (two columns meeting in a 10 m street: no
# more than two units a side fighting at once, the rest wait behind), a
# unit passing through a standing friend (slower than over open ground, it
# gets there), four attacking units through one open gate together (none
# freezes in the gateway); each identical on repeat and across snapshot /
# restore (mid street fight, mid pass-through, mid jam).

## A 10 m street between two blocks of houses; side 0's three heavy units
## come up it from the south, side 1's three from the north, each column's
## units attacking the other column's head.
static func _street_fight_scenario() -> Dictionary:
	var units: Array = []
	for k in 3:
		units.append(Scenarios.unit(0, UT.HEAVY, 60, 150, 252 + k * 16, Scenarios.FACE_UP))
	for k in 3:
		units.append(Scenarios.unit(1, UT.HEAVY, 60, 150, 48 - k * 16, Scenarios.FACE_DOWN))
	for u in units:
		u["files"] = 8
	var orders: Array = []
	for k in 3:
		orders.append({"tick": 2 + k, "type": BattleSim.ORDER_ATTACK, "unit": k, "target": 3, "run": 0, "player": 50})
		orders.append({"tick": 2 + k, "type": BattleSim.ORDER_ATTACK, "unit": 3 + k, "target": 0, "run": 0, "player": 50})
	return {"width_m": 300, "height_m": 300, "units": units, "orders": orders,
		"terrain": {"kind": 0, "blocks": [[40, 60, 145, 240], [155, 60, 260, 240]], "urban": [[40, 60, 260, 240]]}}


## A light unit marching through a heavy one standing in its way (or, with
## `clear`, with the heavy unit off to the side); a lone enemy far off.
static func _pass_scenario(clear: bool) -> Dictionary:
	var units: Array = [Scenarios.unit(0, UT.HEAVY, 80, 260 if clear else 150, 150, Scenarios.FACE_UP),
		Scenarios.unit(0, UT.LIGHT, 60, 150, 195, Scenarios.FACE_UP), Scenarios.unit(1, UT.SPEAR, 40, 30, 20, Scenarios.FACE_DOWN)]
	units[0]["files"] = 16
	units[1]["files"] = 10
	return {"width_m": 300, "height_m": 300, "units": units,
		"orders": [{"tick": 2, "type": BattleSim.ORDER_MOVE, "unit": 1, "x": 150 * M, "y": 115 * M, "facing": Scenarios.FACE_UP,
			"width": 11 * M, "run": 0, "player": 50}]}


## A walled town (walls 1) whose garrison (javelins on the wall, told to
## hold fire) opens its main gate; four attacking units go through it to
## the plaza together.
static func _gate_jam_scenario() -> Dictionary:
	var r := Scenarios.settlement({"seed": 202, "level": 1, "walls": 1, "bld": []},
		{"kind": 1, "seed": 9, "forest": 0, "ground": 2},
		[[UT.HEAVY, 60], [UT.LIGHT, 60], [UT.SPEAR, 60], [UT.HEAVY, 60]], [[UT.JAVELIN, 40]], 1, [])
	return r["scenario"]


func _gate_jam_orders(sim) -> void:
	var dfn := -1
	for u in sim.n_units:
		if sim.u_side[u] == 1:
			dfn = u
	sim.queue_order({"tick": 1, "type": BattleSim.ORDER_FIRE, "unit": dfn, "on": 0, "player": 51})
	sim.queue_order({"tick": 1, "type": BattleSim.ORDER_GATE, "unit": dfn, "gate": 0, "on": 0, "player": 51})
	for u in sim.n_units:
		if sim.u_side[u] == 0:
			sim.queue_order({"tick": 20, "type": BattleSim.ORDER_MOVE, "unit": u, "x": sim.plaza[0] + (u % 2) * 8 * M - 4 * M,
				"y": sim.plaza[1], "facing": FM.atan2_a(sim.plaza[1] - sim.g_y[0], sim.plaza[0] - sim.g_x[0]),
				"width": 9 * M, "run": 0, "player": 50})


## Run a blocking set piece: hashes every tick, and the per-tick probe.
func _block_run(kind: String, snap_at: int, ticks: int) -> Dictionary:
	var sc: Dictionary
	match kind:
		"street":
			sc = _street_fight_scenario()
		"pass":
			sc = _pass_scenario(false)
		"pass_clear":
			sc = _pass_scenario(true)
		_:
			sc = _gate_jam_scenario()
	var sim := BattleSim.new()
	sim.setup(sc, 777)
	if kind == "jam":
		_gate_jam_orders(sim)
	var hashes := PackedInt64Array()
	var max_fight := [0, 0]
	var arrived := -1
	var snap_bad := -1
	for t in ticks:
		sim.step()
		hashes.append(sim.state_hash())
		if t == snap_at:
			snap_bad = _snap_diverges(sim, sc, 777, 120)
		if kind == "street":
			var nf := [0, 0]
			for u in sim.n_units:
				if sim.u_state[u] == BattleSim.U_READY and sim.u_fighting[u] > 0:
					nf[sim.u_side[u]] += 1
			for sd in 2:
				max_fight[sd] = maxi(max_fight[sd], nf[sd])
		elif kind == "pass" or kind == "pass_clear":
			if arrived < 0 and sim.u_order[1] == BattleSim.O_NONE and t > 5:
				arrived = t
		elif arrived < 0 and t > 25:
			var all_in := true
			for u in sim.n_units:
				if sim.u_side[u] == 0 and sim.u_state[u] == BattleSim.U_READY and sim.u_order[u] != BattleSim.O_NONE:
					all_in = false
			if all_in:
				arrived = t
	return {"hashes": hashes, "max_fight": max_fight, "arrived": arrived, "snap_bad": snap_bad,
		"queued": sim.stat_queued, "blocked": sim.stat_blocked, "pass": sim.stat_pass, "dodge": sim.stat_dodge,
		"killed": [sim.u_killed[0] + sim.u_killed[1] + sim.u_killed[2], sim.u_killed[3] + sim.u_killed[4] + sim.u_killed[5]] if kind == "street" else [],
		"winner": sim.winner}


## The "gate rush": a walled town (walls 1) with its main gate opened at
## the start, a defending spear unit standing just inside the gateway
## (`inside` m in from the gate's inner point), an attacking heavy unit
## (or `cav`: riders at the run) outside ordered to the plaza. Returns
## {sc, gate}.
static func _rush_scenario(inside: int, cav: bool) -> Dictionary:
	var r := Scenarios.settlement({"seed": 202, "level": 1, "walls": 1, "bld": []},
		{"kind": 1, "seed": 9, "forest": 0, "ground": 2},
		[[UT.CAVALRY, 40] if cav else [UT.HEAVY, 60]], [[UT.SPEAR, 60]], 1, [])
	var sc: Dictionary = r["scenario"]
	var probe := BattleSim.new()
	probe.setup(sc, 777)
	var g := 0
	var dc := FM.cos_a(probe.g_dir[g])
	var ds := FM.sin_a(probe.g_dir[g])
	for ud in sc["units"]:
		if int(ud["side"]) == 1:
			ud["x_m"] = (probe.g_ix[g] - dc * inside * M / FM.TRIG_ONE) / M
			ud["y_m"] = (probe.g_iy[g] - ds * inside * M / FM.TRIG_ONE) / M
			ud["facing"] = probe.g_dir[g]
			ud["files"] = 6
		else:
			ud["x_m"] = (probe.g_ox[g] + dc * 30 * M / FM.TRIG_ONE) / M
			ud["y_m"] = (probe.g_oy[g] + ds * 30 * M / FM.TRIG_ONE) / M
			ud["facing"] = (probe.g_dir[g] + 512) & 1023
			ud["files"] = 6
	sc["orders"] = [{"tick": 1, "type": BattleSim.ORDER_GATE, "unit": 1, "gate": g, "on": 0, "player": 51},
		{"tick": 10, "type": BattleSim.ORDER_MOVE, "unit": 0, "x": probe.plaza[0], "y": probe.plaza[1],
			"facing": (probe.g_dir[g] + 512) & 1023, "width": 7 * M, "run": 1 if cav else 0, "player": 50}]
	return {"sc": sc, "gate": g}


## Run a gate rush: where the attacker gets to relative to the defender
## (metres in from the gate along its axis), whether its anchor was ever
## inside the defender's formation or behind its rear rank, the plaza clock.
func _rush_run(inside: int, cav: bool, ticks: int, snap: bool) -> Dictionary:
	var rs := _rush_scenario(inside, cav)
	var sc: Dictionary = rs["sc"]
	var g: int = rs["gate"]
	var sim := BattleSim.new()
	sim.setup(sc, 777)
	var hashes := PackedInt64Array()
	var dc := FM.cos_a(sim.g_dir[g])
	var ds := FM.sin_a(sim.g_dir[g])
	var contact := -1
	var behind := 0
	var inside_n := 0
	var cap := 0
	var snap_bad := 0
	for t in ticks:
		sim.step()
		hashes.append(sim.state_hash())
		if snap and t == 300:
			snap_bad = _snap_diverges(sim, sc, 777, 120)
		if contact < 0 and (sim.u_fighting[0] > 0 or sim.u_blk[0] == BattleSim.BLK_ENEMY):
			contact = t
		cap = maxi(cap, sim.cap_t)
		if sim.u_state[1] == BattleSim.U_READY and sim.u_state[0] == BattleSim.U_READY:
			# In from the gate's inner point along its axis (m x 1024).
			var a_in: int = -((sim.u_ax[0] - sim.g_ix[g]) * dc + (sim.u_ay[0] - sim.g_iy[g]) * ds) / FM.TRIG_ONE
			var d_in: int = -((sim.u_ax[1] - sim.g_ix[g]) * dc + (sim.u_ay[1] - sim.g_iy[g]) * ds) / FM.TRIG_ONE
			if a_in > d_in + sim.unit_depth(1) + 2 * M:
				behind += 1
			# Inside its formation rectangle (1 m in from its edges)?
			var fdx: int = sim.u_ax[0] - sim.u_ax[1]
			var fdy: int = sim.u_ay[0] - sim.u_ay[1]
			var fc := FM.cos_a(sim.u_face[1])
			var fs := FM.sin_a(sim.u_face[1])
			var fw := (fdx * fc + fdy * fs) / FM.TRIG_ONE
			var lt := (-fdx * fs + fdy * fc) / FM.TRIG_ONE
			if fw < -M and fw > -sim.unit_depth(1) + M and absi(lt) < sim.unit_half_width(1) - M:
				inside_n += 1
	var a_end: int = -((sim.u_ax[0] - sim.g_ix[g]) * dc + (sim.u_ay[0] - sim.g_iy[g]) * ds) / FM.TRIG_ONE / M
	return {"hashes": hashes, "contact": contact, "behind": behind, "inside": inside_n, "cap": cap, "snap_bad": snap_bad,
		"a_end": a_end, "def_in": inside, "killed": [sim.u_killed[0], sim.u_killed[1]], "states": [sim.u_state[0], sim.u_state[1]], "routs": [sim.u_routs[0], sim.u_routs[1]],
		"plaza_d": FM.approx_len(sim.u_ax[0] - sim.plaza[0], sim.u_ay[0] - sim.plaza[1]) / M, "dodge": sim.stat_dodge}


func _check_gate_rush() -> void:
	for spec in [[2, false, "foot, defender in the gateway"], [2, true, "riders at the run, defender in the gateway"],
			[14, false, "foot, defender 14 m inside (side streets open)"], [14, true, "riders, defender 14 m inside"]]:
		var a := _rush_run(int(spec[0]), bool(spec[1]), 900, true)
		var b := _rush_run(int(spec[0]), bool(spec[1]), 900, false)
		if a["hashes"] != b["hashes"]:
			_fail("gate rush (%s): same seed diverged" % spec[2])
		if int(a["snap_bad"]) != 0:
			_fail("gate rush (%s): snapshot / restore diverged" % spec[2])
		var why := "contact at tick %d, attacker ended %d m in from the gate (defender %d m in), %d m from the plaza; anchor inside the defender %d ticks, behind it %d ticks; plaza clock max %d; killed att %d / def %d; states %s, routs %s; steered %d" % [
			a["contact"], a["a_end"], a["def_in"], a["plaza_d"], a["inside"], a["behind"], a["cap"],
			a["killed"][0], a["killed"][1], str(a["states"]), str(a["routs"]), a["dodge"]]
		if int(a["inside"]) > 0 or int(a["contact"]) < 0 or (int(spec[0]) < 5 and (int(a["behind"]) > 0 or int(a["cap"]) > 0)):
			_fail("gate rush (%s): %s" % [spec[2], why])
		else:
			print("PASS gate rush (%s): %s; identical on repeat and across snapshot / restore" % [spec[2], why])


func _check_blocking() -> void:
	_check_gate_rush()
	for kind in ["street", "pass", "pass_clear", "jam"]:
		var ticks := 1500 if kind == "street" else (1200 if kind != "jam" else 3000)
		var snap_at := 400 if kind == "street" else (200 if kind != "jam" else 500)
		var a := _block_run(kind, snap_at, ticks)
		var b := _block_run(kind, -1, ticks)
		var ha: PackedInt64Array = a["hashes"]
		var hb: PackedInt64Array = b["hashes"]
		if ha != hb:
			_fail("blocking %s: same seed diverged" % kind)
		if int(a["snap_bad"]) != 0:
			_fail("blocking %s: snapshot / restore diverged (%d ticks)" % [kind, int(a["snap_bad"])])
		var info := "queued %d, blocked %d, through friends %d, steered %d" % [a["queued"], a["blocked"], a["pass"], a["dodge"]]
		match kind:
			"street":
				var mf: Array = a["max_fight"]
				if int(mf[0]) > 2 or int(mf[1]) > 2:
					_fail("blocking street: more than two units a side fought at once (%s)" % str(mf))
				if int(a["queued"]) <= 0:
					_fail("blocking street: nobody waited behind the fighting friends (%s)" % info)
				print("PASS blocking street fight: at most %s units a side fighting at once, killed %s, winner %d; %s; identical on repeat and across snapshot / restore at tick 400" % [
					str(mf), str(a["killed"]), a["winner"], info])
			"pass":
				var clear := _block_run("pass_clear", -1, 1200)
				if int(a["pass"]) <= 0 or int(a["arrived"]) < 0 or int(a["arrived"]) <= int(clear["arrived"]):
					_fail("blocking pass-through: arrived at %d (open ground %d), %s" % [a["arrived"], clear["arrived"], info])
				else:
					print("PASS blocking pass-through: through a standing friend in %d ticks (open ground %d); %s; identical across snapshot / restore mid-pass" % [
						a["arrived"], clear["arrived"], info])
			"jam":
				if int(a["arrived"]) < 0:
					_fail("blocking gate jam: the four units did not all get through the gate (%s)" % info)
				else:
					print("PASS blocking gate jam: four units through one open gate to the plaza by tick %d; %s; identical across snapshot / restore mid-jam" % [
						a["arrived"], info])


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


# ------------------------------------------------------------ deployment ---

static func _deploy_scenario(kind: String) -> Dictionary:
	var sc: Dictionary
	if kind == "field":
		sc = Scenarios.make("battle_2000")
		sc["terrain"] = {"kind": Terrain.K_ROLLING, "seed": 77}
		sc["deploy_zones"] = Scenarios.field_zones(sc)
	else:
		# The player (side 0) defends a walled town; the AI attacks.
		sc = Scenarios.siege_test(202, 1, 1, 2, Terrain.K_ROLLING, 0)
	sc["deploy_time"] = 60
	return sc


## Scripted deployment: returns {hashes, rlog, steps}. ready_at < 0: wait
## for the countdown. snap: check snapshot / restore at a deployment step
## and in the battle.
func _deploy_run(kind: String, ready_at: int, snap: bool) -> Dictionary:
	var sc := _deploy_scenario(kind)
	var sim := BattleSim.new()
	sim.setup(sc, 4711)
	var rlog: Array = []
	var hashes := PackedInt64Array([sim.state_hash()])
	var mine: Array[int] = []
	for u in sim.n_units:
		if sim.u_side[u] == 0:
			mine.append(u)
	var steps := 0
	var bad_snap := 0
	while sim.phase == BattleSim.PHASE_DEPLOY and steps < 2000:
		if steps == 3:
			if kind == "field":
				var u0: int = mine[0]
				# Inside the zone: placed where ordered.
				sim.queue_order({"tick": 0, "type": BattleSim.ORDER_PLACE, "unit": u0, "x": sim.u_ax[u0] - 30 * M,
					"y": sim.u_ay[u0] + 20 * M, "facing": 700, "files": 12})
				# Into the enemy's half: clamped to the edge of our zone.
				var u1: int = mine[1]
				sim.queue_order({"tick": 0, "type": BattleSim.ORDER_PLACE, "unit": u1, "x": sim.u_ax[u1], "y": 50 * M,
					"facing": 768, "files": 10})
				# A move during the deployment: refused.
				var u2: int = mine[2]
				sim.queue_order(BattleSim.make_move_order(0, u2, sim.u_ax[u2], sim.u_ay[u2] - 60 * M, 768, 20 * M, 1))
			else:
				for u in mine:
					if sim.u_wall[u] > 0 and sim.u_cls[u] == UT.CLS_MISSILE:
						# Off the wall: into the street by the plaza.
						sim.queue_order({"tick": 0, "type": BattleSim.ORDER_PLACE, "unit": u, "x": sim.plaza[0],
							"y": sim.plaza[1], "facing": 256, "files": 10})
						rlog.append("down %d" % u)
						break
				for u in mine:
					if sim.u_wall[u] == 0 and sim.u_cls[u] == UT.CLS_INF:
						# Onto the stretch of wall farthest from it.
						var best := -1
						var far := -1
						for sg in sim.ws_x0.size():
							var d: int = absi(sim.ws_x0[sg] - sim.u_ax[u]) + absi(sim.ws_y0[sg] - sim.u_ay[u])
							if d > far:
								far = d
								best = sg
						var mid := BattleSim.seg_pt(sim, best, BattleSim.seg_len(sim, best) / 2)
						sim.queue_order({"tick": 0, "type": BattleSim.ORDER_PLACE, "unit": u, "x": mid.x, "y": mid.y,
							"facing": 0, "files": 10})
						rlog.append("up %d seg %d" % [u, best])
						break
				# Outside the walls: refused.
				var uo: int = mine[mine.size() - 1]
				sim.queue_order({"tick": 0, "type": BattleSim.ORDER_PLACE, "unit": uo, "x": sim.field_w / 2,
					"y": sim.field_h - 20 * M, "facing": 768, "files": 10})
				rlog.append("outside %d at %d,%d" % [uo, sim.u_ax[uo] / M, sim.u_ay[uo] / M])
		if steps == ready_at:
			sim.queue_order({"tick": 0, "type": BattleSim.ORDER_READY, "who": 0})
		if snap and steps == 10:
			bad_snap += _snap_diverges(sim, sc, 4711, 60)
		sim.step()
		steps += 1
		if sim.tick != 0:
			_fail("%s: the clock ran during the deployment" % kind)
			break
		hashes.append(sim.state_hash())
		if steps == 5:
			rlog.append(_deploy_report(sim, mine, kind))
	rlog.append("started after %d steps" % steps)
	for t in 400:
		sim.step()
		hashes.append(sim.state_hash())
		if snap and t == 200:
			bad_snap += _snap_diverges(sim, sc, 4711, 60)
	if bad_snap > 0:
		_fail("%s deployment: restored copies diverged (%d)" % [kind, bad_snap])
	return {"hashes": hashes, "rlog": rlog, "steps": steps}


## What the first placements did (checked here).
func _deploy_report(sim, mine: Array[int], kind: String) -> String:
	if kind == "field":
		var u0: int = mine[0]
		var u1: int = mine[1]
		var u2: int = mine[2]
		var z: Vector3i = BattleSim.deploy_clamp(sim, 0, sim.u_ax[u1], 0)
		if sim.u_ay[u1] != z.y:
			_fail("field deployment: a placement into the enemy half was not clamped to the zone (%d vs %d)" % [sim.u_ay[u1], z.y])
		if sim.u_order[u2] != BattleSim.O_NONE:
			_fail("field deployment: a move order was obeyed during the deployment")
		if sim.u_face[u0] != 700 or sim.u_files[u0] != 12:
			_fail("field deployment: placement did not take its facing / files")
		var far := 0
		for s in sim.u_alive[u0]:
			var i: int = sim.slot_soldier[sim.u_slot_base[u0] + s]
			far = maxi(far, absi(sim.pos_x[i] - sim.u_ax[u0] - sim.off_x[sim.u_slot_base[u0] + s]))
		if far != 0:
			_fail("field deployment: the placed unit's men are not in their places")
		return "placed u%d at %d,%d; u%d clamped to y %d" % [u0, sim.u_ax[u0] / M, sim.u_ay[u0] / M, u1, sim.u_ay[u1] / M]
	var out := ""
	for u in mine:
		if sim.u_wall[u] > 0:
			out += "u%d on wall %d; " % [u, sim.u_wall[u] - 1]
		if u == mine[mine.size() - 1]:
			out += "u%d at %d,%d" % [u, sim.u_ax[u] / M, sim.u_ay[u] / M]
	return out


## Snapshot sim now into two copies and run both `n` steps: diverging steps.
func _snap_diverges(sim, sc: Dictionary, p_seed: int, n: int) -> int:
	var blob: PackedByteArray = sim.snapshot()
	var a := BattleSim.new()
	a.setup(sc, p_seed)
	var b := BattleSim.new()
	b.setup(sc, p_seed)
	if not a.restore(blob) or not b.restore(blob):
		_fail("restore refused")
		return 1
	if a.state_hash() != sim.state_hash():
		_fail("restored copy hashes differently")
		return 1
	var bad := 0
	for t in n:
		a.step()
		b.step()
		if a.state_hash() != b.state_hash():
			bad += 1
	return bad


func _check_deploy() -> void:
	for kind in ["field", "town"]:
		var sc := _deploy_scenario(kind)
		var probe := BattleSim.new()
		probe.setup(sc, 4711)
		var plain := BattleSim.new()
		var sc0 := sc.duplicate(true)
		sc0.erase("deploy_time")
		plain.setup(sc0, 4711)
		if probe.phase != BattleSim.PHASE_DEPLOY or plain.phase != BattleSim.PHASE_BATTLE:
			_fail("%s: deployment phase not set from deploy_time" % kind)
		if kind == "field":
			# The AI's line is placed at the start (its units moved, ours not).
			var moved := [0, 0]
			for u in probe.n_units:
				if probe.u_ax[u] != plain.u_ax[u] or probe.u_ay[u] != plain.u_ay[u]:
					moved[probe.u_side[u]] += 1
			if moved[1] == 0 or moved[0] != 0:
				_fail("field: the AI did not deploy at the start (moved %s)" % str(moved))
			else:
				print("PASS field deployment: the AI placed %d units at the start" % moved[1])
		var a := _deploy_run(kind, 30, true)
		var b := _deploy_run(kind, 30, false)
		if a["hashes"] != b["hashes"]:
			_fail("%s deployment: repeat runs differ" % kind)
		else:
			print("PASS %s deployment: %s; identical on repeat and across snapshot / restore" % [kind, str(a["rlog"])])
		if int(a["steps"]) != 31:
			_fail("%s deployment: ready did not start the battle (%d steps)" % [kind, int(a["steps"])])
		if kind == "town" and not str(a["rlog"]).contains("on wall"):
			_fail("town deployment: no unit placed up on a wall")
		var c := _deploy_run(kind, -1, false)
		if int(c["steps"]) != 600:
			_fail("%s deployment: the countdown did not start the battle (%d steps)" % [kind, int(c["steps"])])
		else:
			print("PASS %s deployment: the countdown starts the battle after 600 steps" % kind)
