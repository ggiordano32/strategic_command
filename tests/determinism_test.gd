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
## Mantlets (2026-10-09; "--only=mantlets"): a field battle (archers and a
## bolt thrower against archers, mantlets on both sides, light foot carrying
## one forward and setting it down) and a walls-1 assault with mantlets on
## both sides (the attackers' AI carries its own to the screen line): the
## screens stop missiles, the dropped one faces its unit's way; identical on
## repeat and across snapshot / restore. Battles without the key hash as
## before (the golden digests are unchanged).
## Explosive stones: blast and knockback (2026-10-09; "--only=blast", also
## in the full run): a stone battery shoots its explosive stones into a
## standing pike block 150 m off (every man within 4 m struck, survivors
## thrown and down), against the same battery with ordinary stones: men
## struck, knocked, mean down time, the hole (men over 1.5 m off their
## places right after a burst); identical on repeat and across snapshot /
## restore.
## Units flow into the space (2026-10-09; "--only=flow", also in the full
## run): a 90-man unit up a 5-ladder set at walls 1 and 2 with and without
## 60 defenders on the walkway (all up with every ladder in use, a move
## taken after, nobody left below), four units through one gate, a street
## fight, a unit ordered across a house's corner; the no-progress counter
## and the probe numbers printed; identical on repeat and across snapshot /
## restore.
## River crossings (2026-10-10; "--only=crossing", also in the full run):
## the ford and the bridge maps of one crossing id are the same on every
## build and differ for another id, and side 0 holding the far bank gets
## the same crossing turned round; AI battles over a ford, a bridge and a
## ford held by a fortified army (the camp at the crossing's mouth: rampart
## within 20 m of the exit, no gap facing the water, nothing in the water):
## the attacker crosses (men on the far bank by tick 2400), nobody (formed,
## fighting, routing or down) ever stands in the water; a cavalry charge
## through the ford at foot holding its far exit arrives with no momentum
## (no impact; the same charge on the plain strikes home); identical on
## repeat and across snapshot / restore.
## Exits 0 on success, 1 on failure.

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const Terrain := preload("res://sim/terrain.gd")
const SiegeAI := preload("res://sim/siege_ai.gd")
const BattleAI := preload("res://sim/battle_ai.gd")
const FM := preload("res://sim/fixed_math.gd")
const AIP := preload("res://sim/ai_profile.gd")
const MapGen := preload("res://sim/mapgen.gd")

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
## artillery set pieces did not), and for ranks that hold together in melee
## (2026-10-09: men within 1.5 m of their places, the anchor closes to
## reach, flank / rear by the unit; skirmish and bench_2000 changed), and
## for the field rebalance (2026-10-09: to-hit, flank / rear bonus, the
## wrap at the anchor level, bolts pin, javelins through shields, AI
## missile units out of ammunition leave; skirmish, bench_2000 and
## test_stone_line changed, test_cav_art did not).
const GOLDEN := {"skirmish": "d618e20340501cfa", "bench_2000": "5a0aadfb296bd646",
	"test_cav_art": "2614adc80bd29eb4", "test_stone_line": "b9d3025690cd28ba"}

var _ok := true


func _init() -> void:
	if "--only=flow" in OS.get_cmdline_user_args():
		_check_flow()
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	if "--only=stakes" in OS.get_cmdline_user_args():
		_check_stakes()
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	if "--only=fortified" in OS.get_cmdline_user_args():
		_check_fortified()
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	if "--only=general" in OS.get_cmdline_user_args():
		_check_general()
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	if "--only=chars" in OS.get_cmdline_user_args():
		_check_chars()
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	if "--only=dogs" in OS.get_cmdline_user_args():
		_check_dogs()
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	if "--only=camels" in OS.get_cmdline_user_args():
		_check_camels()
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	if "--only=elephants" in OS.get_cmdline_user_args():
		_check_elephants()
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	if "--only=blast" in OS.get_cmdline_user_args():
		_check_blast()
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	if "--only=ammo" in OS.get_cmdline_user_args():
		_check_ammo()
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	if "--only=wagon" in OS.get_cmdline_user_args():
		_check_wagon()
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	if "--only=siege_tower" in OS.get_cmdline_user_args():
		_check_siege_tower()
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	if "--only=light_art" in OS.get_cmdline_user_args():
		_check_light_art()
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	if "--only=carry" in OS.get_cmdline_user_args():
		_check_carry()
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	if "--only=mantlets" in OS.get_cmdline_user_args():
		_check_mantlets()
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	if "--only=crossing" in OS.get_cmdline_user_args():
		_check_crossing()
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
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
	_check_siege_tower()
	_check_shut_inner_gate()
	_check_engines()
	_check_ammo()
	_check_blast()
	_check_wagon()
	_check_camels()
	_check_elephants()
	_check_general()
	_check_dogs()
	_check_chars()
	_check_stakes()
	_check_fortified()
	_check_light_art()
	_check_mantlets()
	_check_carry()
	_check_crossing()
	if "--only=equipment" in OS.get_cmdline_user_args():
		print("RESULT: ", "PASS" if _ok else "FAIL")
		quit(0 if _ok else 1)
		return
	_check_blocking()
	_check_flow()
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
			# (ai_flank: since 2026-10-09 - men keep to their places - the
			# AI's flank march happens on the hill run below, not here.)
			need = ["shots", "impacts", "routed_off", "ai_pull", "attacks",
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
				"ai_rise", "steep_dis", "ai_flank"]
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
			# (No gate_broken since the 2026-10-09 siege rebalance: with fewer
			# tower engines the batteries spend the run on them and the walls-3
			# gate stands past 5,000 ticks; gate_broken is covered by siege_city,
			# gate_ops, the polis, Punic and oppidum runs.)
			need = ["paths", "clamp", "wall_cover", "obs_lof"]
		"siege_polis@ai":
			# (Part 2c: the defenders hold the gate's mouth and their wall
			# units stay up, nobody falls back to the acropolis within the
			# run: stair moves and the shut gate are cit_ops' and punic's.)
			need = ["paths", "gate_broken", "obs_lof", "layout"]
		"siege_punic@ai":
			# (No gate_close since 2026-10-09, ranks holding together: the
			# defenders are not yet back in the citadel within the run; the
			# shut gate is gate_ops', cit_ops' and the shut inner gate's.)
			need = ["paths", "gate_broken", "stair_down", "gate_art"]
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
		# spearmen, the light infantry runs round the spearmen's flank and in
		# on the bolt throwers. (Until 2026-10-09 it attacked straight away:
		# its anchor stuck on the spearmen's flank, its men ran on 30 m to
		# the engines; men now keep to within 1.5 m of their places.)
		sim.queue_order(BattleSim.make_attack_order(5, 0, 4, 1))
		sim.queue_order(BattleSim.make_attack_order(5, 1, 5, 1))
		sim.queue_order(BattleSim.make_move_order(5, 2, 95 * M, 115 * M, Scenarios.FACE_UP, 25 * M, 1))
		sim.queue_order(BattleSim.make_attack_order(300, 2, 3, 1))
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


# ------------------------------------------------------- siege towers ---
# docs/DESIGN.md "Siege equipment as objects" (the siege tower, 4f.1).

## A walls-2 ring (no tower engines), scripted (no AI), two siege towers:
## the attackers' heavy (unit 0) pushes tower 0 to the nearest stretch it
## can, plants it and crosses onto the walkway; the second heavy (unit 1)
## picks up tower 1 and puts it down again; a defending light unit outside
## the walls takes it up (the other side's now), pushes it 15 m and puts it
## down by it; the attackers' archers (fire arrows) shoot at that unit and
## set tower 1 alight: it burns down (a test shortcut: tower 1 is left with
## 300 hit points when the defenders put it down, so one fire does it).
## Hashes every tick; a second run equal; snapshots while pushing, while
## crossing the planted tower and while tower 1 burns: a restored copy has
## the same hash and two restored copies run on equal.
func _tower_run(snap_check: bool) -> Dictionary:
	var city := {"seed": 4242, "level": 2, "walls": 2, "bld": []}
	var terr := {"kind": Terrain.K_FLAT, "seed": 11, "forest": 0, "ground": 2}
	var r := Scenarios.settlement(city, terr, [[UT.HEAVY, 60], [UT.HEAVY, 60], [UT.ARCHER, 40]], [[UT.SPEAR, 20]], 1, [],
		{"towers": 2})
	var sc: Dictionary = r["scenario"]
	sc["terrain"]["city"]["towers"] = 0  # (no tower engines: the fire is the archers')
	var order: Array = r["order"]
	var arch := -1
	for k in order.size():
		if int(order[k][0]) == 0 and int(order[k][1]) == 2:
			arch = k
	sc["units"][arch]["ak"] = UT.ammo_index("fire_arrows")
	var eq: Array = sc["equip"]
	var t1: Array = eq[1]
	var dl := Scenarios.unit(1, UT.LIGHT, 60, int(t1[1]) + 35, int(t1[2]), Scenarios.FACE_LEFT)
	(sc["units"] as Array).append(dl)
	var dn: int = (sc["units"] as Array).size() - 1
	var h0 := -1
	var h1 := -1
	for k in order.size():
		if int(order[k][0]) == 0 and int(order[k][1]) == 0:
			h0 = k
		if int(order[k][0]) == 0 and int(order[k][1]) == 1:
			h1 = k
	var sim := BattleSim.new()
	sim.setup(sc, 91)
	var hashes := PackedInt64Array()
	var ev := {}
	var snaps: Array = []  # [tick, what, restored hash equal, steps to divergence (-1: none)]
	for t in 6000:
		var tk: int = sim.tick
		if t % 10 == 0:
			# Unit h0: tower 0 to the wall.
			if sim.u_carry[h0] < 0 and sim.q_state[0] == BattleSim.Q_GROUND and sim.u_pick[h0] != 0:
				sim.queue_order({"tick": tk, "type": BattleSim.ORDER_PICKUP, "unit": h0, "equip": 0, "run": 1})
			elif sim.u_carry[h0] == 0 and sim.u_stair[h0] == 0 and sim.u_order[h0] != BattleSim.O_MOVE:
				if not ev.has("pushing"):
					ev["pushing"] = tk
					ev["pace"] = BattleSim.carry_pace(UT.stat(sim.u_type[h0], "walk"), BattleSim.EQ_TOWER, sim.u_alive[h0])
				var best := -1
				var bd := 0
				for sg in sim.ws_x0.size():
					var mp: Vector2i = BattleSim.seg_pt(sim, sg, BattleSim.seg_len(sim, sg) / 2)
					if BattleSim.ladder_set_for(sim, h0, sg, mp.x, mp.y) < 0:
						continue
					var d := absi(mp.x - sim.u_cx[h0]) + absi(mp.y - sim.u_cy[h0])
					if best < 0 or d < bd:
						best = sg
						bd = d
				if best >= 0:
					var lp: Vector2i = BattleSim.seg_pt(sim, best, BattleSim.seg_len(sim, best) / 2)
					sim.queue_order(BattleSim.make_move_order(tk, h0, lp.x, lp.y, 768, 20 * 1024, 0))
			# Unit h1: tower 1 up and down again, then away.
			if not ev.has("drop1"):
				if sim.u_carry[h1] < 0 and sim.u_pick[h1] != 1:
					sim.queue_order({"tick": tk, "type": BattleSim.ORDER_PICKUP, "unit": h1, "equip": 1, "run": 1})
				elif sim.u_carry[h1] == 1:
					ev["drop1"] = tk
					sim.queue_order({"tick": tk, "type": BattleSim.ORDER_DROP, "unit": h1})
					sim.queue_order(BattleSim.make_move_order(tk + 1, h1, sim.u_ax[h1] - 40 * M, sim.u_ay[h1],
						Scenarios.FACE_LEFT, 20 * M, 0))
			# The defenders' light unit outside: takes tower 1, pushes it 15 m, puts it down.
			elif not ev.has("taken"):
				if sim.q_state[1] == BattleSim.Q_GROUND and sim.u_pick[dn] != 1 and tk >= int(ev["drop1"]) + 30:
					sim.queue_order({"tick": tk, "type": BattleSim.ORDER_PICKUP, "unit": dn, "equip": 1, "run": 1})
				elif sim.u_carry[dn] == 1:
					ev["taken"] = tk
					ev["side1"] = sim.q_side[1]
					sim.queue_order(BattleSim.make_move_order(tk, dn, sim.u_ax[dn] + 15 * M, sim.u_ay[dn],
						Scenarios.FACE_LEFT, 20 * M, 0))
			elif not ev.has("drop_d") and sim.u_carry[dn] == 1 and sim.u_order[dn] != BattleSim.O_MOVE:
				ev["drop_d"] = tk
				sim.queue_order({"tick": tk, "type": BattleSim.ORDER_DROP, "unit": dn})
			elif ev.has("drop_d") and not ev.has("shoot"):
				if sim.q_state[1] == BattleSim.Q_GROUND:
					ev["shoot"] = tk
					sim.q_hp[1] = 300  # (the shortcut: one fire burns it down)
					sim.queue_order({"tick": tk, "type": BattleSim.ORDER_AMMO, "unit": arch, "on": 1})
					sim.queue_order({"tick": tk, "type": BattleSim.ORDER_ATTACK, "unit": arch, "target": dn, "run": 0})
		sim.step()
		hashes.append(sim.state_hash())
		if not ev.has("planted") and sim.q_state[0] == BattleSim.Q_PLANTED:
			ev["planted"] = sim.tick
		if not ev.has("lit") and sim.q_burn[1] > 0:
			ev["lit"] = sim.tick
		if not ev.has("burnt") and sim.q_state[1] == BattleSim.Q_WRECKED:
			ev["burnt"] = sim.tick
		if not ev.has("over") and ev.has("planted") and sim.u_wall[h0] > 0 and sim.u_stair[h0] == 0:
			ev["over"] = sim.tick
		var what := ""
		if snap_check:
			if not ev.has("s_push") and ev.has("pushing") and sim.tick >= int(ev["pushing"]) + 200:
				what = "pushing"
			elif not ev.has("s_cross") and sim.u_stair[h0] == BattleSim.ST_LADDER and sim.stat_stw_up >= 10:
				what = "crossing"
			elif not ev.has("s_burn") and ev.has("lit") and sim.q_burn[1] > 0 and sim.tick >= int(ev["lit"]) + 30:
				what = "burning"
			if what != "":
				ev[{"pushing": "s_push", "crossing": "s_cross", "burning": "s_burn"}[what]] = sim.tick
		if what != "":
			var blob := sim.snapshot()
			var a2 := BattleSim.new()
			a2.setup(sc, 91)
			a2.restore(blob)
			var b2 := BattleSim.new()
			b2.setup(sc, 91)
			b2.restore(blob)
			var same: bool = a2.state_hash() == sim.state_hash()
			var bad := -1
			for k in 300:
				a2.step()
				b2.step()
				if a2.state_hash() != b2.state_hash():
					bad = k
					break
			snaps.append([sim.tick, what, same, bad])
		if ev.has("over") and ev.has("burnt") and (not snap_check or snaps.size() >= 3):
			break
	return {"hashes": hashes, "ev": ev, "snaps": snaps, "up": sim.stat_stw_up, "planted": sim.stat_stw_planted,
		"taken": sim.stat_stw_taken, "wrecked": sim.stat_stw_wrecked, "q0": sim.q_state[0], "q1": sim.q_state[1],
		"wall0": sim.u_wall[h0], "alive0": sim.u_alive[h0], "tick": sim.tick}


func _check_siege_tower() -> void:
	var a := _tower_run(true)
	var b := _tower_run(false)
	var n := mini((a["hashes"] as PackedInt64Array).size(), (b["hashes"] as PackedInt64Array).size())
	for t in n:
		if a["hashes"][t] != b["hashes"][t]:
			_fail("siege_tower: the repeat diverged at tick %d" % t)
			return
	var ev: Dictionary = a["ev"]
	a.erase("hashes")
	for k in ["pushing", "planted", "over", "drop1", "taken", "drop_d", "shoot", "lit", "burnt"]:
		if not ev.has(k):
			_fail("siege_tower: step %s never happened (%s)" % [k, str(a)])
			return
	if int(a["planted"]) != 1 or int(a["up"]) <= 0 or int(a["taken"]) != 1 or int(a["wrecked"]) != 1 \
			or int(a["q0"]) != BattleSim.Q_PLANTED or int(a["q1"]) != BattleSim.Q_WRECKED or int(a["wall0"]) <= 0 \
			or int(ev["side1"]) != 1:
		_fail("siege_tower: %s" % str(a))
		return
	var snaps: Array = a["snaps"]
	if snaps.size() < 3:
		_fail("siege_tower: snapshots %s" % str(snaps))
		return
	for sn in snaps:
		if not bool(sn[2]) or int(sn[3]) >= 0:
			_fail("siege_tower: snapshot / restore %s: restored hash equal %s, copies diverged at %d" % [sn[1], str(sn[2]), int(sn[3])])
			return
	var cross: int = int(ev["over"]) - int(ev["planted"])
	print("PASS siege_tower: pushed from tick %d at %d.%02d m/s (tick pace %d), planted at %d, %d men across in %d ticks (%d alive), the second tower put down at %d, taken by the defenders at %d (side %d), put down at %d, lit at %d, burnt down at %d; identical on repeat and across snapshot / restore while %s (ticks %s)" % [
		ev["pushing"], int(ev["pace"]) * 10 / 1024, int(ev["pace"]) * 1000 / 1024 % 100, ev["pace"], ev["planted"],
		a["up"], cross, a["alive0"], ev["drop1"], ev["taken"], ev["side1"], ev["drop_d"], ev["lit"], ev["burnt"],
		", ".join(snaps.map(func(x): return str(x[1]))), ", ".join(snaps.map(func(x): return str(x[0])))])


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


# ------------------------------------------------------- light artillery ---
# docs/DESIGN.md "Light artillery" (STATUS 4f.3).

## A flat 300 x 300 m field, scripted, no AI: a scorpion battery (carrying
## heavy bolts) packs up, marches 40 m and sets up again, then shoots a pike
## block 105 m off along its depth with heavy bolts (75 % range); its crews
## leave the engines (tick 700) and an archer unit takes them up and shoots
## on with them. Gastraphetes meanwhile close on a heavy unit 150 m off and
## shoot it from beyond where archers would stand (85 % of 140 m). Returns what was seen and the hashes of every tick.
func _light_art_run(snap_check: bool) -> Dictionary:
	var sco := UT.index_of("scorpions")
	var gas := UT.index_of("gastraphetes")
	var sc := {"width_m": 300, "height_m": 300, "ai_sides": [], "orders": [], "units": [
		Scenarios.unit(0, sco, 12, 120, 270, Scenarios.FACE_UP),
		Scenarios.unit(0, UT.ARCHER, 40, 60, 235, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.PIKE, 120, 120, 125, Scenarios.FACE_DOWN),
		Scenarios.unit(0, gas, 80, 235, 235, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.HEAVY, 60, 235, 85, Scenarios.FACE_DOWN)]}
	sc["units"][0]["ak"] = UT.ammo_index("heavy_bolts")
	var sim := BattleSim.new()
	sim.setup(sc, 4242)
	sim.u_fire[1] = 0
	sim.u_fire[0] = 0
	sim.u_fire[3] = 0
	var ev := {}
	var bad: Array[String] = []
	var hashes := PackedInt64Array()
	var snap_t := -1
	var snap_bad := -1
	var full := UT.stat(sco, "deploy")
	var y0 := 0
	var moving := 0
	var gas_ammo0: int = sim.u_ammo[3]
	var gas_win := [-1, -1]   # its ammo at ticks 300 and 600
	var max_vic := 0          # most men struck by one scorpion bolt (ticks with one landing)
	var over := 0             # ticks with more men struck than 2 a bolt landing
	for t in 1300:
		var tk: int = sim.tick
		if tk == 1:
			sim.queue_order(BattleSim.make_move_order(tk, 0, 120 * M, 230 * M, Scenarios.FACE_UP, 25 * M, 0))
			sim.queue_order(BattleSim.make_attack_order(tk, 3, 4, 0))
		if not ev.has("packed") and tk > 1 and sim.u_depl[0] == 0:
			ev["packed"] = tk
			y0 = sim.u_ay[0]
		if ev.has("packed") and not ev.has("stopped") and sim.u_depl[0] == 0 and sim.u_moved[0] > 0:
			moving += 1
		if ev.has("packed") and not ev.has("stopped") and sim.u_order[0] == BattleSim.O_NONE:
			ev["stopped"] = tk
			ev["pace"] = (y0 - sim.u_ay[0]) / maxi(moving, 1)  # sim units a tick while moving
		if ev.has("stopped") and not ev.has("set_up") and sim.u_depl[0] >= full:
			ev["set_up"] = tk
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_AMMO, "unit": 0, "on": 1})
			sim.queue_order(BattleSim.make_attack_order(tk, 0, 2, 0))
		if not ev.has("gas_first") and sim.u_ammo[3] < gas_ammo0:
			ev["gas_first"] = tk
			ev["gas_d"] = sim._unit_dist(3, 4) / M
		if tk == 300:
			gas_win[0] = sim.u_ammo[3]
		if tk == 600:
			gas_win[1] = sim.u_ammo[3]
		if tk == 700:
			ev["bolts0"] = sim.stat_bolts
			ev["vic0"] = sim.stat_art_victims
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_DROP, "unit": 0})
		if tk == 702:
			if sim.u_eg[0] != -1 or sim.u_cls[0] == UT.CLS_ART or not sim.engines_free(0):
				bad.append("the crews did not leave the scorpions")
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_PICKUP, "unit": 1, "engines": 0, "run": 0})
		if not ev.has("pick1") and sim.u_eg[1] == 0:
			ev["pick1"] = tk
			ev["bolts_pick"] = sim.stat_bolts
			if sim.u_type[1] != sco or sim.u_otype[1] != UT.ARCHER:
				bad.append("the archers did not take the scorpions up")
			sim.queue_order(BattleSim.make_attack_order(tk, 1, 2, 0))
		var b0: int = sim.stat_bolts
		var v0: int = sim.stat_art_victims
		var f0 := _bolts_flying(sim, sco)
		sim.step()
		hashes.append(sim.state_hash())
		# Bolts landed this tick (in flight before + fired - in flight after)
		# and the men they struck.
		var landed: int = f0 + sim.stat_bolts - b0 - _bolts_flying(sim, sco)
		var vic: int = sim.stat_art_victims - v0
		if vic > 2 * landed:
			over += 1
		if landed == 1:
			max_vic = maxi(max_vic, vic)
		if snap_check and snap_t < 0 and ev.has("pick1") and sim.tick >= int(ev["pick1"]) + 30:
			snap_t = sim.tick
			var a2 := BattleSim.new()
			a2.setup(sc, 4242)
			a2.restore(sim.snapshot())
			var b2 := BattleSim.new()
			b2.setup(sc, 4242)
			b2.restore(sim.snapshot())
			for k in 300:
				a2.step()
				b2.step()
				if a2.state_hash() != b2.state_hash():
					snap_bad = k
					break
	var ak: int = UT.ammo_index("heavy_bolts")
	return {"ev": ev, "bad": bad, "hashes": hashes, "bolts": sim.stat_bolts, "victims": sim.stat_art_victims,
		"max_vic": max_vic, "over": over, "pierce_heavy": UT.stat(sco, "m_pierce") * UT.ammo_stat(ak, "pierce") / 100,
		"kills1": sim.u_kills[1], "kills0": sim.u_kills[0], "gas_win": gas_win, "gas_kills": sim.u_kills[3],
		"gas_ammo0": gas_ammo0, "gas_ammo": sim.u_ammo[3], "gas_alive": sim.u_alive[3],
		"snap_t": snap_t, "snap_bad": snap_bad}


## Scorpion bolts (type sco) in flight.
func _bolts_flying(sim: BattleSim, sco: int) -> int:
	var n := 0
	for p in sim.pr_t1.size():
		if sim.pr_t1[p] >= 0 and sim.pr_ty[p] == sco:
			n += 1
	return n


func _check_light_art() -> void:
	var a := _light_art_run(true)
	var b := _light_art_run(false)
	var ev: Dictionary = a["ev"]
	if a["hashes"] != b["hashes"] or str(ev) != str(b["ev"]):
		_fail("light_art: the repeat diverged")
		return
	if not (a["bad"] as Array).is_empty():
		_fail("light_art: %s" % str(a["bad"]))
		return
	for k in ["packed", "stopped", "set_up", "pick1", "gas_first"]:
		if not ev.has(k):
			_fail("light_art: step %s never happened (%s)" % [k, str(ev)])
			return
	var sco := UT.index_of("scorpions")
	var bolt_pace := UT.stat(UT.BOLT, "walk") * 7 / 8
	var pace: int = ev["pace"]
	var setup_t: int = int(ev["set_up"]) - int(ev["stopped"])
	var pack_t: int = int(ev["packed"]) - 1
	if pace * 100 < UT.stat(sco, "walk") * 7 / 8 * 90 or pace <= bolt_pace * 3 / 2:
		_fail("light_art: packed pace %d a tick (want ~%d; Bolt Throwers %d)" % [pace, UT.stat(sco, "walk") * 7 / 8, bolt_pace])
		return
	if setup_t > 40 or pack_t > 20:
		_fail("light_art: set up in %d ticks, packed in %d" % [setup_t, pack_t])
		return
	var bolts0: int = ev["bolts0"]
	if bolts0 <= 0 or int(a["max_vic"]) != 2 or int(a["over"]) > 0 or int(a["pierce_heavy"]) != 2 or int(a["victims"]) > 2 * int(a["bolts"]) \
			or int(a["victims"]) <= int(a["bolts"]) / 2:
		a.erase("hashes")
		_fail("light_art: bolts / pierce: %s" % str(a))
		return
	if int(a["bolts"]) <= int(ev["bolts_pick"]) or int(a["kills1"]) <= 0:
		_fail("light_art: the archers never shot with the scorpions (%d bolts, %d kills)" % [int(a["bolts"]) - int(ev["bolts_pick"]), int(a["kills1"])])
		return
	var gw: Array = a["gas_win"]
	var per_man := (int(gw[0]) - int(gw[1])) * 100 / maxi(int(a["gas_alive"]), 1)  # shots a man in 300 ticks, x100
	var bow_stand := UT.stat(UT.ARCHER, "m_range") * 17 / 20 / M  # where archers stand to shoot (85 % of 140 m)
	if int(ev["gas_d"]) <= bow_stand or per_man < 200 or per_man > 360 or int(a["gas_kills"]) <= 0:
		_fail("light_art: gastraphetes first shot at %d m, %d.%02d shots a man in 30 s, %d kills" % [int(ev["gas_d"]), per_man / 100, per_man % 100, int(a["gas_kills"])])
		return
	if int(a["snap_t"]) < 0 or int(a["snap_bad"]) >= 0:
		_fail("light_art: no snapshot, or the restored copy diverged (%d at %d)" % [int(a["snap_bad"]), int(a["snap_t"])])
		return
	print("PASS light_art: scorpions packed by tick %d, marched packed at %d.%02d m/s (Bolt Throwers %d.%02d), set up %d ticks after stopping; %d bolts by tick 700 (heavy bolts pierce %d), %d bolts in all striking %d men, at most %d men by one bolt, %d kills; the crews left them at 700, the archers took them up at %d and shot on (%d kills); gastraphetes first shot at tick %d from %d m (archers stand at %d m), flat (m_arc %d), %d.%02d shots a man in 30 s (archers ~7.5), %d kills; identical on repeat and across snapshot / restore (tick %d)" % [
		int(ev["packed"]), pace * 10 / M, pace * 1000 / M % 100, bolt_pace * 10 / M, bolt_pace * 1000 / M % 100, setup_t, bolts0,
		int(a["pierce_heavy"]), int(a["bolts"]), int(a["victims"]), int(a["max_vic"]), int(a["kills0"]), int(ev["pick1"]),
		int(a["kills1"]), int(ev["gas_first"]), int(ev["gas_d"]), bow_stand, UT.stat(UT.index_of("gastraphetes"), "m_arc"),
		per_man / 100, per_man % 100, int(a["gas_kills"]), int(a["snap_t"])])


# ------------------------------------------------------ ammunition kinds ---
# docs/DESIGN.md "Ammunition kinds", "Fire".

## A walls-1 town: archers carrying fire arrows switch to them (tick 1),
## march to 70 m off the main gate and are told to shoot at it: the gate
## catches fire and burns (chip damage); snapshot / restore while it burns.
func _fire_gate_run(snap_check: bool) -> Dictionary:
	var city := {"seed": 4242, "level": 1, "walls": 1, "bld": []}
	var terr := {"kind": Terrain.K_FLAT, "seed": 11, "forest": 0, "ground": 2}
	var r := Scenarios.settlement(city, terr, [[UT.ARCHER, 60]], [[UT.SPEAR, 40]], 1, [])
	var sc: Dictionary = r["scenario"]
	sc["units"][0]["ak"] = UT.ammo_index("fire_arrows")
	var sim := BattleSim.new()
	sim.setup(sc, 31)
	var hashes := PackedInt64Array()
	var ev := {}
	var snap_t := -1
	var snap_bad := -1
	var hp0: int = sim.g_hp[0]
	for t in 2400:
		var tk: int = sim.tick
		if tk == 1:
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_AMMO, "unit": 0, "on": 1})
		if tk == 2:
			ev["akind"] = sim.u_akind[0]
			var gp := SiegeAI._gate_point(sim, 0, 70 * M, 0)
			sim.queue_order(BattleSim.make_move_order(tk, 0, gp.x, gp.y,
				FM.atan2_a(sim.g_y[0] - gp.y, sim.g_x[0] - gp.x), 20 * M, 0))
		if tk > 10 and not ev.has("ordered") and sim.u_order[0] == BattleSim.O_NONE:
			ev["ordered"] = tk
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_ATTACK, "unit": 0, "target": -1, "gate": 0, "run": 0})
		sim.step()
		hashes.append(sim.state_hash())
		if not ev.has("lit") and sim.g_burn[0] > 0:
			ev["lit"] = sim.tick
		if snap_check and snap_t < 0 and ev.has("lit") and sim.tick >= int(ev["lit"]) + 20:
			snap_t = sim.tick
			var a2 := BattleSim.new()
			a2.setup(sc, 31)
			a2.restore(sim.snapshot())
			var b2 := BattleSim.new()
			b2.setup(sc, 31)
			b2.restore(sim.snapshot())
			for k in 300:
				a2.step()
				b2.step()
				if a2.state_hash() != b2.state_hash():
					snap_bad = k
					break
	return {"hashes": hashes, "ev": ev, "ak_shots": sim.stat_ak_shots, "ignite": sim.stat_ignite,
		"fire_dmg": sim.stat_fire_dmg, "hp0": hp0, "hp": sim.g_hp[0], "state": sim.g_state[0],
		"special_left": sim.special_left(0), "snap_t": snap_t, "snap_bad": snap_bad}


## A field: a stone battery carrying explosive stones switches to them and
## shoots a big heavy unit 130 m off: the stones burst (men struck inside
## the wider blast).
func _blast_run(snap_check: bool) -> Dictionary:
	var sc := {"width_m": 300, "height_m": 300, "ai_sides": [], "orders": [], "units": [
		Scenarios.unit(0, UT.STONE, 18, 150, 250, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.HEAVY, 120, 150, 120, Scenarios.FACE_DOWN)]}
	sc["units"][0]["ak"] = UT.ammo_index("explosive")
	var sim := BattleSim.new()
	sim.setup(sc, 4242)
	var hashes := PackedInt64Array()
	var snap_bad := -1
	for t in 1200:
		var tk: int = sim.tick
		if tk == 1:
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_AMMO, "unit": 0, "on": 1})
			sim.queue_order(BattleSim.make_attack_order(tk, 0, 1, 0))
		sim.step()
		hashes.append(sim.state_hash())
		if snap_check and sim.tick == 600:
			var a2 := BattleSim.new()
			a2.setup(sc, 4242)
			a2.restore(sim.snapshot())
			for k in 200:
				a2.step()
				sim.step()
				hashes.append(sim.state_hash())
				if a2.state_hash() != sim.state_hash() and snap_bad < 0:
					snap_bad = k
	return {"hashes": hashes, "blast": sim.stat_blast, "ak_shots": sim.stat_ak_shots, "stones": sim.stat_stones,
		"killed": sim.u_killed[1], "snap_bad": snap_bad}


func _check_ammo() -> void:
	var a := _fire_gate_run(true)
	var b := _fire_gate_run(false)
	var ev: Dictionary = a["ev"]
	if a["hashes"] != b["hashes"]:
		_fail("ammo: the fire-arrow run diverged on repeat")
		return
	if int(ev.get("akind", 0)) != 1 or not ev.has("ordered") or not ev.has("lit") or int(a["ak_shots"]) <= 0 \
			or int(a["ignite"]) <= 0 or int(a["fire_dmg"]) <= 0 or int(a["hp"]) >= int(a["hp0"]):
		a.erase("hashes")
		_fail("ammo: fire arrows at the gate: %s" % str(a))
		return
	if int(a["snap_t"]) < 0 or int(a["snap_bad"]) >= 0:
		_fail("ammo: no snapshot while the gate burned, or the restored copy diverged (%d)" % int(a["snap_bad"]))
		return
	var c := _blast_run(true)
	var d := _blast_run(true)
	if c["hashes"] != d["hashes"] or int(c["snap_bad"]) >= 0:
		_fail("ammo: the explosive run diverged (repeat or snapshot %d)" % int(c["snap_bad"]))
		return
	if int(c["blast"]) <= 0 or int(c["ak_shots"]) <= 0:
		c.erase("hashes")
		_fail("ammo: the explosive stones never burst: %s" % str(c))
		return
	print("PASS ammo: archers switched to fire arrows, shot %d of them at the gate from tick %d, set it alight at %d (%d fires), %d hp burnt off (gate %d -> %d centi-hp, state %d, %d fire arrows left); explosive stones: %d shots, %d men struck in the blast, %d killed; identical on repeat and across snapshot / restore (tick %d; tick 600)" % [
		int(a["ak_shots"]), int(ev["ordered"]), int(ev["lit"]), int(a["ignite"]), int(a["fire_dmg"]), int(a["hp0"]),
		int(a["hp"]), int(a["state"]), int(a["special_left"]), int(c["ak_shots"]), int(c["blast"]), int(c["killed"]),
		int(a["snap_t"])])


## A stone battery (explosive stones or ordinary ones) shooting a standing
## pike block 150 m off for 120 s. Per burst: the men of the block more
## than 1.5 m off their places just after it, less just before (the hole).
func _blast_pike_run(explosive: bool, snap_check: bool) -> Dictionary:
	var sc := {"width_m": 300, "height_m": 300, "ai_sides": [], "orders": [], "units": [
		Scenarios.unit(0, UT.STONE, 18, 150, 250, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.PIKE, 160, 150, 100, Scenarios.FACE_DOWN)]}
	if explosive:
		sc["units"][0]["ak"] = UT.ammo_index("explosive")
	var sim := BattleSim.new()
	sim.setup(sc, 4243)
	var hashes := PackedInt64Array()
	var snap_bad := -1
	var bursts := 0
	var hole := 0
	var hole_max := 0
	var downed_max := 0
	for t in 1200:
		var tk: int = sim.tick
		if tk == 1:
			if explosive:
				sim.queue_order({"tick": tk, "type": BattleSim.ORDER_AMMO, "unit": 0, "on": 1})
			sim.queue_order(BattleSim.make_attack_order(tk, 0, 1, 0))
		var kn0: int = sim.stat_blast_knock
		var off0 := _off_place(sim, 1)
		sim.step()
		hashes.append(sim.state_hash())
		if sim.stat_blast_knock > kn0:
			bursts += 1
			var h := _off_place(sim, 1) - off0
			hole += h
			hole_max = maxi(hole_max, h)
		downed_max = maxi(downed_max, sim.u_down[1])
		if snap_check and sim.tick == 600:
			var a2 := BattleSim.new()
			a2.setup(sc, 4243)
			a2.restore(sim.snapshot())
			for k in 200:
				a2.step()
				sim.step()
				hashes.append(sim.state_hash())
				if a2.state_hash() != sim.state_hash() and snap_bad < 0:
					snap_bad = k
	return {"hashes": hashes, "struck": sim.stat_blast, "knocked": sim.stat_blast_knock,
		"down_ticks": sim.stat_blast_down, "held": sim.stat_blast_held, "bursts": bursts, "hole": hole,
		"hole_max": hole_max, "downed_max": downed_max, "killed": sim.u_killed[1], "victims": sim.stat_art_victims,
		"stones": sim.stat_stones, "ak_shots": sim.stat_ak_shots, "snap_bad": snap_bad}


## Men of unit u more than 1.5 m off their formation places.
func _off_place(sim: BattleSim, u: int) -> int:
	var base: int = sim.u_slot_base[u]
	var cnt := 0
	for s in sim.u_alive[u]:
		var i: int = sim.slot_soldier[base + s]
		if sim.state[i] >= BattleSim.S_DEAD:
			continue
		var k: int = base + sim.slot_of[i]
		var dx: int = sim.pos_x[i] - (sim.u_ax[u] + sim.off_x[k])
		var dy: int = sim.pos_y[i] - (sim.u_ay[u] + sim.off_y[k])
		if dx * dx + dy * dy > 1536 * 1536:
			cnt += 1
	return cnt


func _check_blast() -> void:
	var a := _blast_pike_run(true, true)
	var b := _blast_pike_run(true, false)
	var c := _blast_pike_run(false, true)
	var d := _blast_pike_run(false, false)
	if a["hashes"].slice(0, 1200) != b["hashes"] or int(a["snap_bad"]) >= 0:
		_fail("blast: the explosive run diverged (repeat or snapshot %d)" % int(a["snap_bad"]))
		return
	if c["hashes"].slice(0, 1200) != d["hashes"] or int(c["snap_bad"]) >= 0:
		_fail("blast: the ordinary-stone run diverged (repeat or snapshot %d)" % int(c["snap_bad"]))
		return
	a.erase("hashes")
	c.erase("hashes")
	var nb := maxi(int(a["bursts"]), 1)
	var nk := maxi(int(a["knocked"]), 1)
	if int(a["bursts"]) <= 0 or int(a["knocked"]) <= 0 or int(a["struck"]) <= 0 or int(a["hole"]) <= 0 \
			or int(a["knocked"]) > 30 * int(a["bursts"]) or int(c["knocked"]) != 0:
		_fail("blast: explosive %s / ordinary %s" % [str(a), str(c)])
		return
	print("PASS blast: explosive stones into a pike block at 150 m: %d bursts (%d special shots, %d stones), %d men struck (%d per burst), %d killed, %d knocked (%d per burst, %d throws blocked), mean down %d ticks, hole %d men per burst (most %d), most down at once %d; ordinary stones: %d stones, %d victims, %d killed, none knocked; identical on repeat and across snapshot / restore (tick 600)" % [
		int(a["bursts"]), int(a["ak_shots"]), int(a["stones"]), int(a["struck"]), int(a["struck"]) / nb,
		int(a["killed"]), int(a["knocked"]), int(a["knocked"]) / nb, int(a["held"]), int(a["down_ticks"]) / nk,
		int(a["hole"]) / nb, int(a["hole_max"]), int(a["downed_max"]), int(c["stones"]), int(c["victims"]),
		int(c["killed"])])


# ---------------------------------------------------------------- resupply ---
# docs/DESIGN.md "Resupply: foraging and the ammunition wagon".

## A field with a wood: archers with empty quivers standing in it forage
## (tick 1, for 400 ticks), then march off (the order ends it); javelinmen
## with one javelin a man beside a one-horse wagon refill from it (tick 1);
## the enemy's light infantry (tick 450) attack the wagon's crew until it
## is gone, take the wagon (a capture) and put it down again. Scripted, no
## AI.
func _wagon_run(snap_check: bool) -> Dictionary:
	var sc := {"width_m": 300, "height_m": 300, "ai_sides": [], "orders": [], "units": [
		Scenarios.unit(0, UT.ARCHER, 40, 80, 250, Scenarios.FACE_UP),
		Scenarios.unit(0, UT.index_of("wagon2"), 8, 160, 240, Scenarios.FACE_UP),
		Scenarios.unit(0, UT.JAVELIN, 40, 160, 226, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.LIGHT, 60, 160, 120, Scenarios.FACE_DOWN)],
		"terrain": {"kind": Terrain.K_FLAT, "woods": [[80, 250, 30, 22, 2]]}}
	var sim := BattleSim.new()
	sim.setup(sc, 909)
	for u in [0, 2]:
		var base: int = sim.u_slot_base[u]
		for s2 in sim.u_alive[u]:
			sim.ammo[sim.slot_soldier[base + s2]] = 0 if u == 0 else 1
		sim.u_ammo[u] = 0 if u == 0 else sim.u_alive[u]
		sim.u_fire[u] = 0
	var q: int = sim.u_carry[1]
	var nak := UT.AMMO.size()
	var ev := {"q": q, "jav0": sim.q_stock[q * nak + 1] if q >= 0 else -1}
	var hashes := PackedInt64Array()
	var snap_t := -1
	var snap_bad := -1
	for t in 2600:
		var tk: int = sim.tick
		if tk == 1:
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_FORAGE, "unit": 0, "on": 1})
			sim.queue_order(BattleSim.make_refill_order(tk, 2, 1))
		if tk == 3:
			ev["foraging"] = sim.u_forage[0]
		if tk == 400:
			ev["forage_ammo"] = sim.u_ammo[0]
			sim.queue_order(BattleSim.make_move_order(tk, 0, 60 * M, 280 * M, Scenarios.FACE_UP, 15 * M, 0))
		if tk == 402:
			ev["forage_after_move"] = sim.u_forage[0]
		if not ev.has("refilled") and tk > 1 and sim.u_refill[2] == 0 and sim.u_ammo[2] > sim.u_alive[2]:
			ev["refilled"] = tk
			ev["jav_ammo"] = sim.u_ammo[2]
			ev["jav_left"] = sim.q_stock[q * nak + 1]
		if tk == 450:
			sim.queue_order(BattleSim.make_attack_order(tk, 3, 1, 1))
		if not ev.has("crew_gone") and tk > 450 and (sim.u_state[1] >= BattleSim.U_ROUTING) \
				and sim.q_state[q] == BattleSim.Q_GROUND:
			ev["crew_gone"] = tk
			ev["crew_alive"] = sim.u_alive[1]
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_PICKUP, "unit": 3, "equip": q, "run": 0})
		if ev.has("crew_gone") and not ev.has("taken") and sim.u_carry[3] == q:
			ev["taken"] = tk
			ev["side"] = sim.q_side[q]
		if ev.has("taken") and not ev.has("dropped") and tk >= int(ev["taken"]) + 150:
			ev["dropped"] = tk
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_DROP, "unit": 3})
		sim.step()
		hashes.append(sim.state_hash())
		if snap_check and snap_t < 0 and ev.has("taken") and sim.tick >= int(ev["taken"]) + 40:
			snap_t = sim.tick
			var a2 := BattleSim.new()
			a2.setup(sc, 909)
			a2.restore(sim.snapshot())
			var b2 := BattleSim.new()
			b2.setup(sc, 909)
			b2.restore(sim.snapshot())
			for k in 300:
				a2.step()
				b2.step()
				if a2.state_hash() != b2.state_hash():
					snap_bad = k
					break
		if ev.has("dropped") and sim.tick > int(ev["dropped"]) + 5:
			break
	ev["q_state"] = sim.q_state[q]
	return {"hashes": hashes, "ev": ev, "forage": sim.stat_forage, "refill_shots": sim.stat_refill_shots,
		"taken": sim.stat_wagon_taken, "snap_t": snap_t, "snap_bad": snap_bad}


func _check_wagon() -> void:
	var a := _wagon_run(true)
	var b := _wagon_run(false)
	var ev: Dictionary = a["ev"]
	if a["hashes"] != b["hashes"] or str(ev) != str(b["ev"]):
		_fail("wagon: the repeat diverged")
		return
	for k in ["refilled", "crew_gone", "taken", "dropped"]:
		if not ev.has(k):
			_fail("wagon: step %s never happened (%s)" % [k, str(ev)])
			return
	if int(ev["foraging"]) != 1 or int(ev["forage_ammo"]) <= 0 or int(ev["forage_after_move"]) != 0 or int(a["forage"]) <= 0:
		_fail("wagon: foraging did not fill quivers or did not stop when ordered away (%s)" % str(ev))
		return
	if int(ev["jav_ammo"]) != 6 * 40 or int(ev["jav_left"]) >= int(ev["jav0"]) or int(ev["side"]) != 1 \
			or int(ev["q_state"]) != BattleSim.Q_GROUND or int(a["taken"]) != 1:
		_fail("wagon: %s" % str(ev))
		return
	if int(a["snap_t"]) < 0 or int(a["snap_bad"]) >= 0:
		_fail("wagon: no snapshot with the wagon taken, or the restored copy diverged (%d)" % int(a["snap_bad"]))
		return
	print("PASS wagon: archers foraged %d arrows in 400 ticks in the wood and stopped when moved off; javelinmen refilled from the wagon by tick %d (%d javelins, the wagon's %d -> %d); the crew was gone at %d (%d alive), the enemy took the wagon at %d (side %d) and put it down at %d; identical on repeat and across snapshot / restore (tick %d)" % [
		int(ev["forage_ammo"]), int(ev["refilled"]), int(ev["jav_ammo"]), int(ev["jav0"]), int(ev["jav_left"]),
		int(ev["crew_gone"]), int(ev["crew_alive"]), int(ev["taken"]), int(ev["side"]), int(ev["dropped"]), int(a["snap_t"])])


## Camels (docs/DESIGN.md "Camels and elephants"; "--only=camels"): camels
## standing within 30 m of a horse unit: the horses keep 70 % of their turn
## rate (a wheel in place against an unscared horse unit's), lose heart
## while they stay (no recovery), and charging the camels they shy (scare
## hits); camels charging braced spears lose like any riders. Identical on
## repeat and across snapshot / restore.
func _camel_run(snap_check: bool) -> Dictionary:
	var camel := UT.index_of("camel")
	var sc := {"width_m": 300, "height_m": 300, "ai_sides": [], "orders": [], "units": [
		Scenarios.unit(0, camel, 60, 150, 200, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.CAVALRY, 60, 150, 172, Scenarios.FACE_DOWN),
		Scenarios.unit(1, UT.CAVALRY, 60, 40, 60, Scenarios.FACE_DOWN)],
		"terrain": {"kind": Terrain.K_FLAT}}
	var sim := BattleSim.new()
	sim.setup(sc, 515)
	var ev := {}
	var hashes := PackedInt64Array()
	var snap_t := -1
	var snap_bad := -1
	for t in 900:
		var tk: int = sim.tick
		if tk == 12:
			ev["scare1"] = sim.u_scare[1]
			ev["scare2"] = sim.u_scare[2]
			# Wheel 90 degrees in place: the scared unit turns slower.
			for u in [1, 2]:
				sim.queue_order(BattleSim.make_move_order(tk, u, sim.u_ax[u], sim.u_ay[u],
					(Scenarios.FACE_DOWN + 256) & 1023, 30 * M, 0))
		if tk == 20:
			ev["turn1"] = absi(FM.angle_diff(sim.u_face[1], Scenarios.FACE_DOWN))
			ev["turn2"] = absi(FM.angle_diff(sim.u_face[2], Scenarios.FACE_DOWN))
		if tk == 120:
			ev["mor1"] = sim.u_morale[1]
			ev["mor2"] = sim.u_morale[2]
			# Back off and charge the camels.
			sim.queue_order(BattleSim.make_move_order(tk, 1, 150 * M, 120 * M, Scenarios.FACE_DOWN, 30 * M, 1))
		if tk == 260:
			sim.queue_order(BattleSim.make_attack_order(tk, 1, 0, 1))
		sim.step()
		hashes.append(sim.state_hash())
		if snap_check and snap_t < 0 and sim.tick == 300:
			snap_t = sim.tick
			snap_bad = _snap_diverges(sim, sc, 515, 300)
	ev["scare_hits"] = sim.stat_scare_hits
	ev["scared"] = sim.stat_scared
	# Camels against braced spears (the spears stand: braced).
	var sc2 := {"width_m": 300, "height_m": 300, "ai_sides": [], "orders": [], "units": [
		Scenarios.unit(0, camel, 60, 150, 230, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.SPEAR, 100, 150, 140, Scenarios.FACE_DOWN)],
		"terrain": {"kind": Terrain.K_FLAT}}
	var s2 := BattleSim.new()
	s2.setup(sc2, 516)
	s2.queue_order(BattleSim.make_attack_order(1, 0, 1, 1))
	for t in 1200:
		s2.step()
		hashes.append(s2.state_hash())
	ev["camels_lost"] = s2.u_killed[0]
	ev["spears_lost"] = s2.u_killed[1]
	ev["camel_state"] = s2.u_state[0]
	ev["reflects"] = s2.stat_reflects
	return {"hashes": hashes, "ev": ev, "snap_t": snap_t, "snap_bad": snap_bad}


func _check_camels() -> void:
	var a := _camel_run(true)
	var b := _camel_run(false)
	var ev: Dictionary = a["ev"]
	print("  camels: %s" % str(ev))
	if a["hashes"] != b["hashes"] or str(ev) != str(b["ev"]):
		_fail("camels: the repeat diverged")
		return
	if int(ev["scare1"]) != 70 or int(ev["scare2"]) != 0:
		_fail("camels: the horse unit near the camels is not scared (or the far one is)")
		return
	if int(ev["turn1"]) >= int(ev["turn2"]) or int(ev["turn1"]) <= 0:
		_fail("camels: the scared horses did not turn slower (%d against %d)" % [int(ev["turn1"]), int(ev["turn2"])])
		return
	if int(ev["mor1"]) >= int(ev["mor2"]):
		_fail("camels: the scared horses kept their heart (%d against %d)" % [int(ev["mor1"]), int(ev["mor2"])])
		return
	if int(ev["scare_hits"]) <= 0:
		_fail("camels: the horses charging the camels did not shy")
		return
	if int(ev["camels_lost"]) <= int(ev["spears_lost"]) or int(ev["reflects"]) <= 0:
		_fail("camels: camels charging braced spears did not lose (%s)" % str(ev))
		return
	if int(a["snap_t"]) < 0 or int(a["snap_bad"]) != 0:
		_fail("camels: the restored copy diverged (%d)" % int(a["snap_bad"]))
		return
	print("PASS camels: horses within 30 m keep %d %% (far ones %d), wheel %d against %d angle units in 8 ticks, morale %d against %d after 11 s near the camels; %d horse impacts on the camels shied; camels into braced spears lost %d, killed %d (%d reflected, state %d); identical on repeat and across snapshot / restore (tick %d)" % [
		int(ev["scare1"]), int(ev["scare2"]), int(ev["turn1"]), int(ev["turn2"]), int(ev["mor1"]), int(ev["mor2"]),
		int(ev["scare_hits"]), int(ev["camels_lost"]), int(ev["spears_lost"]), int(ev["reflects"]),
		int(ev["camel_state"]), int(a["snap_t"])])


## The general (docs/DESIGN.md "The general"; "--only=general"): two
## mirrored light infantry units of ours under the same archers' fire, one
## within the general's command aura, keep their heart longer inside it; the
## general's unit (six men) is charged and routs or falls: every friendly
## unit loses cmd_loss at once, the one within his cmd_r cmd_loss_r; light
## horse out of javelins charge with momentum like cavalry. Identical on
## repeat and across snapshot / restore.
func _general_run(snap_check: bool) -> Dictionary:
	var gen := UT.index_of("general")
	var lh := UT.index_of("cav_jav")
	var ev := {}
	var hashes := PackedInt64Array()
	var snap_t := -1
	var snap_bad := -1
	# A: under fire, inside and outside the aura (mirrored, 160 m apart).
	var sc := {"width_m": 400, "height_m": 300, "ai_sides": [], "orders": [], "units": [
		Scenarios.unit(0, gen, 30, 100, 225, Scenarios.FACE_UP),
		Scenarios.unit(0, UT.LIGHT, 100, 100, 190, Scenarios.FACE_UP),
		Scenarios.unit(0, UT.LIGHT, 100, 260, 190, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.ARCHER, 80, 100, 90, Scenarios.FACE_DOWN),
		Scenarios.unit(1, UT.ARCHER, 80, 260, 90, Scenarios.FACE_DOWN)],
		"terrain": {"kind": Terrain.K_FLAT}}
	var sim := BattleSim.new()
	sim.setup(sc, 717)
	sim.queue_order(BattleSim.make_attack_order(1, 3, 1, 0))
	sim.queue_order(BattleSim.make_attack_order(1, 4, 2, 0))
	ev["waver_in"] = -1
	ev["waver_out"] = -1
	for t in 1500:
		sim.step()
		hashes.append(sim.state_hash())
		if sim.tick == 30:
			ev["cmd_in"] = sim.u_led[1]
			ev["cmd_out"] = sim.u_led[2]
		for k in 2:
			var key: String = ["waver_in", "waver_out"][k]
			if int(ev[key]) < 0 and (sim.u_morale[1 + k] < BattleSim.WAVER or sim.u_state[1 + k] != BattleSim.U_READY):
				ev[key] = sim.tick
		if sim.tick == 600:
			ev["mor_in"] = sim.u_morale[1]
			ev["mor_out"] = sim.u_morale[2]
			ev["lost_in"] = sim.u_killed[1]
			ev["lost_out"] = sim.u_killed[2]
		if snap_check and snap_t < 0 and sim.tick == 400:
			snap_t = sim.tick
			snap_bad = _snap_diverges(sim, sc, 717, 300)
	ev["cmd_s"] = sim.stat_cmd
	# B: the general's six men charged by cavalry: the loss strikes the army.
	var sc2 := {"width_m": 400, "height_m": 300, "ai_sides": [], "orders": [], "units": [
		Scenarios.unit(0, gen, 6, 150, 150, Scenarios.FACE_UP),
		Scenarios.unit(0, UT.HEAVY, 100, 150, 185, Scenarios.FACE_UP),
		Scenarios.unit(0, UT.HEAVY, 100, 330, 185, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.CAVALRY, 60, 150, 60, Scenarios.FACE_DOWN)],
		"terrain": {"kind": Terrain.K_FLAT}}
	var s2 := BattleSim.new()
	s2.setup(sc2, 718)
	s2.queue_order(BattleSim.make_attack_order(1, 3, 0, 1))
	ev["fall_t"] = -1
	var pm1: int = s2.u_morale[1]
	var pm2: int = s2.u_morale[2]
	for t in 900:
		s2.step()
		hashes.append(s2.state_hash())
		if int(ev["fall_t"]) < 0 and s2.stat_cmd_falls > 0:
			ev["fall_t"] = s2.tick
			ev["gen_state"] = s2.u_state[0]
			ev["drop_near"] = pm1 - s2.u_morale[1]
			ev["drop_far"] = pm2 - s2.u_morale[2]
		pm1 = s2.u_morale[1]
		pm2 = s2.u_morale[2]
		if snap_check and int(ev["fall_t"]) < 0 and s2.tick == 40:
			# Across a snapshot taken before the fall (the loss happens in the copies).
			var bad := _snap_diverges(s2, sc2, 718, 400)
			snap_bad = maxi(snap_bad, bad)
	ev["falls"] = s2.stat_cmd_falls
	# C: light horse out of javelins charge light infantry.
	var sc3 := {"width_m": 300, "height_m": 300, "ai_sides": [], "orders": [], "units": [
		Scenarios.unit(0, lh, 60, 150, 230, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.LIGHT, 100, 150, 120, Scenarios.FACE_DOWN)],
		"terrain": {"kind": Terrain.K_FLAT}}
	sc3["units"][0]["ammo_pct"] = 0
	var s3 := BattleSim.new()
	s3.setup(sc3, 719)
	s3.queue_order({"tick": 1, "type": BattleSim.ORDER_SKIRMISH, "unit": 0, "on": 0})
	s3.queue_order(BattleSim.make_attack_order(2, 0, 1, 1))
	var mom := 0
	for t in 400:
		s3.step()
		hashes.append(s3.state_hash())
		mom = maxi(mom, s3.u_mom[0])
	ev["lh_mom"] = mom
	ev["lh_impacts"] = s3.stat_impacts
	ev["lh_kills"] = s3.u_killed[1]
	# D: the AI's general (docs/AI.md 20), battle_2000 with a general a side,
	# both Average, then both Easy (he fights as any rider: GEN_THINK 0).
	for lvl in [AIP.AVERAGE, AIP.EASY]:
		var sc4: Dictionary = Scenarios.make("battle_2000")
		sc4["ai_sides"] = [0, 1]
		sc4["ai_skill"] = [lvl, lvl]
		sc4["terrain"] = {"kind": Terrain.K_FLAT}
		var gs: Array = []
		for sd in 2:
			gs.append((sc4["units"] as Array).size())
			sc4["units"].append(Scenarios.unit(sd, gen, 30, 280, 420 if sd == 0 else 140,
				Scenarios.FACE_UP if sd == 0 else Scenarios.FACE_DOWN))
		var s4 := BattleSim.new()
		s4.setup(sc4, 720)
		var tag := "avg" if lvl == AIP.AVERAGE else "easy"
		ev[tag + "_charge_t"] = -1
		ev[tag + "_behind"] = 0
		var engage_t := -1
		for t in (2400 if lvl == AIP.AVERAGE else 1500):
			s4.step()
			hashes.append(s4.state_hash())
			if engage_t < 0 and s4.ai_phase[0] == BattleAI.P_ENGAGE:
				engage_t = s4.tick
			for sd in 2:
				var g: int = gs[sd]
				if int(ev[tag + "_charge_t"]) < 0 and s4.u_ai[g] == BattleAI.A_CHARGE:
					ev[tag + "_charge_t"] = s4.tick
				if s4.tick % 100 == 0 and s4.u_state[g] == BattleSim.U_READY and engage_t < 0:
					# Behind his own foot line (its mean depth) before the lines meet.
					var ly := 0
					var ln := 0
					for o in s4.n_units:
						if s4.u_side[o] == sd and s4.u_state[o] == BattleSim.U_READY and (s4.u_cls[o] == UT.CLS_INF or s4.u_cls[o] == UT.CLS_PIKE):
							ly += s4.u_cy[o]
							ln += 1
					if ln > 0 and (s4.u_cy[g] - ly / ln) * (1 if sd == 0 else -1) > 10 * M:
						ev[tag + "_behind"] = int(ev[tag + "_behind"]) + 1
		ev[tag + "_engage_t"] = engage_t
		var n_r := 0
		var n_c := 0
		for sd in 2:
			n_r += s4.stat_aic[sd * AIP.N_COUNTERS + AIP.C_GEN_RALLY]
			n_c += s4.stat_aic[sd * AIP.N_COUNTERS + AIP.C_GEN_CHARGE]
		ev[tag + "_rallies"] = n_r
		ev[tag + "_charges"] = n_c
		ev[tag + "_falls"] = s4.stat_cmd_falls
	return {"hashes": hashes, "ev": ev, "snap_t": snap_t, "snap_bad": snap_bad}


func _check_general() -> void:
	var a := _general_run(true)
	var b := _general_run(false)
	var ev: Dictionary = a["ev"]
	print("  general: %s" % str(ev))
	var gen := UT.index_of("general")
	if a["hashes"] != b["hashes"] or str(ev) != str(b["ev"]):
		_fail("general: the repeat diverged")
		return
	if int(ev["cmd_in"]) != 1 or int(ev["cmd_out"]) != 0 or int(ev["cmd_s"]) <= 0:
		_fail("general: the aura is not where it should be (%s)" % str(ev))
		return
	var wi := int(ev["waver_in"])
	var wo := int(ev["waver_out"])
	if wo < 0 or (wi >= 0 and wi <= wo) or int(ev["mor_in"]) <= int(ev["mor_out"]):
		_fail("general: the unit inside the aura did not hold longer (wavered at %d, outside %d)" % [wi, wo])
		return
	if int(ev["falls"]) != 1 or int(ev["fall_t"]) < 0:
		_fail("general: the general's fall did not strike the army once (%d)" % int(ev["falls"]))
		return
	var near := UT.stat(gen, "cmd_loss_r")
	var far := UT.stat(gen, "cmd_loss")
	if int(ev["drop_near"]) < near - 10 or int(ev["drop_far"]) < far - 10 or int(ev["drop_far"]) > far + 10:
		_fail("general: the loss hit is wrong (near %d, want %d; far %d, want %d)" % [int(ev["drop_near"]), near,
			int(ev["drop_far"]), far])
		return
	if int(ev["lh_mom"]) < BattleSim.CHARGE_MIN or int(ev["lh_impacts"]) <= 0:
		_fail("general: the light horse built no charge (momentum %d, impacts %d)" % [int(ev["lh_mom"]), int(ev["lh_impacts"])])
		return
	if int(ev["avg_behind"]) <= 0 or int(ev["avg_rallies"]) + int(ev["avg_charges"]) <= 0:
		_fail("general: the Average AI's general did not keep behind the line or never rode to rally or charge (%s)" % str(ev))
		return
	if int(ev["easy_charge_t"]) < 0 or (int(ev["avg_charge_t"]) >= 0 and int(ev["avg_charge_t"]) <= int(ev["easy_charge_t"])):
		_fail("general: the Easy AI did not throw its general in first (Easy %d, Average %d)" % [int(ev["easy_charge_t"]),
			int(ev["avg_charge_t"])])
		return
	if int(a["snap_t"]) < 0 or int(a["snap_bad"]) != 0:
		_fail("general: the restored copy diverged (%d)" % int(a["snap_bad"]))
		return
	print("PASS general (AI): Average keeps him behind the line (%d samples before the lines met at %d), rides to rally %d times, charges %d (first at %d), generals fallen %d; Easy sends him in at tick %d (lines met at %d)" % [
		int(ev["avg_behind"]), int(ev["avg_engage_t"]), int(ev["avg_rallies"]), int(ev["avg_charges"]), int(ev["avg_charge_t"]),
		int(ev["avg_falls"]), int(ev["easy_charge_t"]), int(ev["easy_engage_t"])])
	print("PASS general: under the same fire the unit inside the aura wavered at tick %s, the one outside at %d (morale %d against %d at 600, %d and %d men lost); the general's unit %s at tick %d: the unit near him lost %d morale at once, the far one %d; light horse charged with momentum %d (%d impacts, %d killed); identical on repeat and across snapshot / restore" % [
		str(wi) if wi >= 0 else "never", wo, int(ev["mor_in"]), int(ev["mor_out"]), int(ev["lost_in"]), int(ev["lost_out"]),
		"routed" if int(ev["gen_state"]) == BattleSim.U_ROUTING else "fell", int(ev["fall_t"]),
		int(ev["drop_near"]), int(ev["drop_far"]), int(ev["lh_mom"]), int(ev["lh_impacts"]), int(ev["lh_kills"])])


## War dogs (docs/DESIGN.md "War dogs"; "--only=dogs"), three groups far
## apart on a flat field, no AI: (A) handlers release their pack at archers
## 60 m off (the pack arrives and kills), with nothing left within 30 m for
## 5 s it runs back and is absorbed (dogs back in the kennel); light
## infantry near the handlers is then broken (morale 0) and the pack
## released at it again runs it down; (B) a pack released at braced
## spearmen dies; (C) a pack released at javelinmen while heavy swords
## break its handlers fights on, then stands. Identical on repeat and
## across snapshot / restore before the release, when the pack turns for
## home and while it is back in the kennel (each restored copy run on to
## the end with the same script, hash for hash).
const DOG_SEED := 4242


func _dog_scenario() -> Dictionary:
	var dh := UT.index_of("dog_handlers")
	return {"width_m": 1000, "height_m": 1000, "ai_sides": [], "orders": [], "units": [
		Scenarios.unit(0, dh, 16, 200, 260, Scenarios.FACE_UP),          # 0 handlers A
		Scenarios.unit(1, UT.ARCHER, 80, 200, 200, Scenarios.FACE_DOWN),  # 1 archers
		Scenarios.unit(1, UT.LIGHT, 60, 270, 305, Scenarios.FACE_LEFT),   # 2 light infantry (broken later)
		Scenarios.unit(0, dh, 16, 600, 700, Scenarios.FACE_UP),          # 3 handlers B
		Scenarios.unit(1, UT.SPEAR, 100, 600, 635, Scenarios.FACE_DOWN),  # 4 spearmen (braced)
		Scenarios.unit(0, dh, 16, 880, 500, Scenarios.FACE_UP),          # 5 handlers C
		Scenarios.unit(1, UT.JAVELIN, 60, 880, 435, Scenarios.FACE_DOWN), # 6 javelinmen
		Scenarios.unit(1, UT.HEAVY, 100, 880, 600, Scenarios.FACE_UP)],   # 7 heavy swords (go for C)
		"terrain": {"kind": Terrain.K_FLAT}}


## The scripted orders of the dog run at tick tk (the pursuit release once
## pack A has been back for 2 s); pack units: 8 (A), 9 (B), 10 (C).
func _dog_script(sim, tk: int, ev: Dictionary) -> void:
	if tk == 1:
		for u in [1, 6]:
			sim.queue_order(BattleSim.make_fire_order(tk, u, 0))
		sim.queue_order(BattleSim.make_release_order(tk, 0, 1))
		sim.queue_order(BattleSim.make_release_order(tk, 3, 4))
		sim.queue_order(BattleSim.make_release_order(tk, 5, 6))
		sim.queue_order(BattleSim.make_attack_order(tk, 7, 5, 1))
	if int(ev.get("absorbed", -1)) >= 0 and tk == int(ev["absorbed"]) + 20:
		sim.u_morale[2] = 0  # (the light infantry breaks)
	if int(ev.get("absorbed", -1)) >= 0 and tk == int(ev["absorbed"]) + 25:
		ev["refusal2"] = BattleSim.release_refusal(sim, 0, 2)
		sim.queue_order(BattleSim.make_release_order(tk, 0, 2))


func _dog_run(snap_at: Dictionary, restored: Dictionary = {}) -> Dictionary:
	var sc := _dog_scenario()
	var sim := BattleSim.new()
	sim.setup(sc, DOG_SEED)
	var ev := {}
	var t0 := 0
	var ref: PackedInt64Array = restored.get("hashes", PackedInt64Array())
	var bad := -1
	if restored.has("blob"):
		if not sim.restore(restored["blob"]):
			_fail("dogs: restore refused")
			return {}
		ev = (restored["ev"] as Dictionary).duplicate()
		t0 = sim.tick
	var hashes := PackedInt64Array()
	var snaps := {}
	for t in range(t0, 4000):
		var tk: int = sim.tick
		_dog_script(sim, tk, ev)
		sim.step()
		var h: int = sim.state_hash()
		hashes.append(h)
		# Events the script reads (every run).
		if not ev.has("a_ret") and sim.u_ret[8] != 0:
			ev["a_ret"] = tk
			ev["a_kills_then"] = sim.u_kills[8]
			ev["archers_then"] = "%d/%d st %d" % [sim.u_alive[1], sim.u_count0[1], sim.u_state[1]]
		if ev.has("a_ret") and not ev.has("absorbed") and sim.u_state[8] == BattleSim.U_KENNEL:
			ev["absorbed"] = tk
			ev["kept"] = sim.u_kept[8]
		if restored.has("blob"):
			if tk < ref.size() and ref[tk] != h and bad < 0:
				bad = tk
			if tk >= ref.size() - 1:
				break
			continue
		# Events (the first run only).
		if not ev.has("a_first_kill") and sim.u_kills[8] > 0:
			ev["a_first_kill"] = tk
			ev["a_alive_then"] = sim.u_alive[8]
		if ev.has("absorbed") and not ev.has("released2") and sim.u_state[8] == BattleSim.U_READY:
			ev["released2"] = tk
			ev["li_state"] = sim.u_state[2]
			ev["li_killed0"] = sim.u_killed[2]
		if ev.has("released2"):
			ev["li_killed"] = sim.u_killed[2] - int(ev["li_killed0"])
			ev["li_final"] = sim.u_state[2]
		if not ev.has("b_dead") and sim.u_state[9] == BattleSim.U_DESTROYED:
			ev["b_dead"] = tk
			ev["spears_lost"] = sim.u_killed[4]
			ev["b_kills"] = sim.u_kills[9]
		if not ev.has("c_lost") and sim.u_state[5] != BattleSim.U_READY:
			ev["c_lost"] = tk
		ev["c_state"] = "%d order %d ret %d alive %d kills %d" % [sim.u_state[10], sim.u_order[10], sim.u_ret[10],
			sim.u_alive[10], sim.u_kills[10]]
		if ev.has("c_lost") and sim.u_state[10] == BattleSim.U_READY and sim.u_order[10] == BattleSim.O_NONE \
				and sim.u_fighting[10] == 0:
			if not ev.has("c_stands"):
				ev["c_stands"] = tk
		elif ev.has("c_stands") and sim.u_state[10] < BattleSim.U_DESTROYED:
			ev.erase("c_stands")  # (not standing yet: it went on fighting)
		for k in snap_at:
			if not snaps.has(k) and bool(snap_at[k].call(sim, ev)):
				snaps[k] = {"blob": sim.snapshot(), "ev": ev.duplicate(), "tick": sim.tick}
		if ev.has("released2") and tk > int(ev["released2"]) + 300 and ev.has("b_dead") and ev.has("c_stands") \
				and tk > int(ev["c_stands"]) + 100:
			break
	ev["released"] = sim.stat_released
	ev["absorbed_n"] = sim.stat_absorbed
	ev["hunts"] = sim.stat_dog_hunt
	return {"hashes": hashes, "ev": ev, "snaps": snaps, "bad": bad, "ticks": sim.tick}


func _check_dogs() -> void:
	var snap_at := {
		"before_release": func(sim, _ev): return sim.tick == 1,
		"turning_home": func(sim, _ev): return sim.u_ret[8] != 0,
		"in_kennel": func(sim, e): return e.has("absorbed") and sim.tick == int(e["absorbed"]) + 10,
	}
	var a := _dog_run(snap_at)
	var b := _dog_run({})
	var ev: Dictionary = a["ev"]
	print("  dogs: %s" % str(ev))
	if a["hashes"] != b["hashes"]:
		_fail("dogs: the repeat diverged")
	if not ev.has("a_first_kill"):
		_fail("dogs: the pack released at the archers never killed")
	if not ev.has("absorbed") or int(ev.get("kept", 0)) <= 0:
		_fail("dogs: the pack did not come back to its handlers (%s)" % str(ev))
	if not ev.has("released2") or int(ev.get("li_killed", 0)) <= 0 or int(ev.get("li_state", -1)) != BattleSim.U_ROUTING:
		_fail("dogs: the second release did not run the routers down (%s)" % str(ev))
	if not ev.has("b_dead") or int(ev.get("spears_lost", 99)) > 20:
		_fail("dogs: the pack against braced spears did not die cheaply (%s)" % str(ev))
	if not ev.has("c_lost") or not ev.has("c_stands"):
		_fail("dogs: the pack without its handlers did not fight on and stand (%s)" % str(ev))
	var snaps: Dictionary = a["snaps"]
	for k in ["before_release", "turning_home", "in_kennel"]:
		if not snaps.has(k):
			_fail("dogs: no snapshot %s" % k)
			continue
		var r := _dog_run({}, {"blob": snaps[k]["blob"], "ev": snaps[k]["ev"], "hashes": a["hashes"]})
		if r.is_empty() or int(r["bad"]) >= 0:
			_fail("dogs: restored at %s (tick %d) diverged at tick %d" % [k, int(snaps[k]["tick"]),
				int(r.get("bad", -2))])
		else:
			print("  dogs: restored at %s (tick %d) runs on equal to tick %d" % [k, int(snaps[k]["tick"]),
				int(snaps[k]["tick"]) + (r["hashes"] as PackedInt64Array).size()])
	print("PASS dogs: pack A first kill at tick %d, turned home at %d (%d kills; archers %s), absorbed at %d with %d dogs; released at the broken light infantry at %d, killed %d of them (final state %d); pack B at braced spears dead at tick %d (spears lost %d, dogs killed %d); handlers C lost at %d, pack C stands from %d (%s); %d releases, %d absorbs, %d hunts; identical on repeat and across snapshot / restore" % [
		int(ev.get("a_first_kill", -1)), int(ev.get("a_ret", -1)), int(ev.get("a_kills_then", -1)), str(ev.get("archers_then", "")),
		int(ev.get("absorbed", -1)), int(ev.get("kept", -1)), int(ev.get("released2", -1)), int(ev.get("li_killed", -1)),
		int(ev.get("li_final", -1)), int(ev.get("b_dead", -1)), int(ev.get("spears_lost", -1)), int(ev.get("b_kills", -1)),
		int(ev.get("c_lost", -1)), int(ev.get("c_stands", -1)), str(ev.get("c_state", "")), int(ev["released"]),
		int(ev["absorbed_n"]), int(ev["hunts"])])


## Elephants ("--only=elephants"): a unit of elephants charges a heavy line
## (knock-downs; fire arrows chip it and set it burning on the way in); a
## second unit standing among its own light infantry breaks (its morale
## put to nothing at tick 20) and runs amok, trampling them, then, alone,
## calms after its cooling time; a third breaks at tick 30 and its drivers
## are told to kill it at 35 (dead after the delay). Identical on repeat
## and across snapshot / restore mid-amok.
func _elephant_run(snap_check: bool) -> Dictionary:
	var el := UT.index_of("elephant")
	var fire := UT.ammo_index("fire_arrows")
	var arch := Scenarios.unit(1, UT.ARCHER, 80, 560, 300, Scenarios.FACE_LEFT)
	arch["ak"] = fire
	var sc := {"width_m": 700, "height_m": 700, "ai_sides": [], "orders": [], "units": [
		Scenarios.unit(0, el, 12, 480, 330, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.HEAVY, 100, 480, 220, Scenarios.FACE_DOWN),
		arch,
		Scenarios.unit(0, UT.LIGHT, 40, 150, 470, Scenarios.FACE_UP),
		Scenarios.unit(0, el, 12, 150, 462, Scenarios.FACE_UP),
		Scenarios.unit(0, el, 12, 560, 640, Scenarios.FACE_UP)],
		"terrain": {"kind": Terrain.K_FLAT}}
	var sim := BattleSim.new()
	sim.setup(sc, 717)
	var full := 12 * UT.stat(el, "hp")
	var ev := {"down_max": 0, "burned": 0}
	var hashes := PackedInt64Array()
	var snap_t := -1
	var snap_bad := -1
	for t in 2400:
		var tk: int = sim.tick
		if tk == 1:
			sim.queue_order(BattleSim.make_attack_order(tk, 0, 1, 1))
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_AMMO, "unit": 2, "on": 1})
			sim.queue_order(BattleSim.make_fire_order(tk, 2, 0))
		if tk == 100:
			sim.queue_order(BattleSim.make_attack_order(tk, 2, 0, 0))
		if tk == 20:
			sim.u_morale[4] = 0  # (the second unit breaks)
		if tk == 30:
			sim.u_morale[5] = 0  # (the third)
		if tk == 35:
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_KILL, "unit": 5})
			ev["refused_ready"] = BattleSim.kill_refusal(sim, 0)
		if tk == 22:
			ev["amok"] = sim.u_amok[4]
		ev["down_max"] = maxi(int(ev["down_max"]), sim.u_down[1])
		if sim.u_burn[0] > 0:
			ev["burned"] = 1
		if not ev.has("contact") and sim.u_charge[0] != 0:
			ev["contact"] = tk
			var hp0 := 0
			var base: int = sim.u_slot_base[0]
			for s2 in sim.u_alive[0]:
				hp0 += sim.hp[sim.slot_soldier[base + s2]]
			ev["hp_lost_approach"] = full - hp0
			ev["alive_at_contact"] = sim.u_alive[0]
		if not ev.has("killed_at") and sim.u_state[5] == BattleSim.U_DESTROYED:
			ev["killed_at"] = tk
		if not ev.has("calmed") and tk > 22 and sim.u_amok[4] == 0 and sim.u_state[4] == BattleSim.U_READY:
			ev["calmed"] = tk
		sim.step()
		hashes.append(sim.state_hash())
		if snap_check and snap_t < 0 and sim.tick == 60:
			snap_t = sim.tick
			snap_bad = _snap_diverges(sim, sc, 717, 300)
		if ev.has("calmed") and ev.has("killed_at") and sim.tick > 900:
			break
	ev["impacts"] = sim.stat_impacts
	ev["knockdowns"] = sim.stat_knockdowns
	ev["trample_ff"] = sim.stat_trample_ff
	ev["friends_lost"] = sim.u_killed[3]
	ev["driver_killed"] = sim.stat_beast_killed
	ev["missile_hits"] = sim.stat_missile_hits
	ev["feared"] = sim.stat_feared
	ev["heavy_lost"] = sim.u_killed[1]
	ev["el_lost"] = sim.u_killed[0]
	return {"hashes": hashes, "ev": ev, "snap_t": snap_t, "snap_bad": snap_bad}


func _check_elephants() -> void:
	var a := _elephant_run(true)
	var b := _elephant_run(false)
	var ev: Dictionary = a["ev"]
	print("  elephants: %s" % str(ev))
	if a["hashes"] != b["hashes"] or str(ev) != str(b["ev"]):
		_fail("elephants: the repeat diverged")
		return
	if not ev.has("contact") or int(ev["down_max"]) < 5 or int(ev["impacts"]) <= 0:
		_fail("elephants: the charge did not knock the line down (%s)" % str(ev))
		return
	if int(ev["hp_lost_approach"]) <= 0 or int(ev["burned"]) == 0:
		_fail("elephants: missiles and fire did not chip them on the way in (%s)" % str(ev))
		return
	if int(ev.get("amok", 0)) != 1 or int(ev["trample_ff"]) <= 0:
		_fail("elephants: the broken unit did not run amok through its friends (%s)" % str(ev))
		return
	if not ev.has("calmed"):
		_fail("elephants: the amok unit never calmed (%s)" % str(ev))
		return
	if not ev.has("killed_at") or int(ev["driver_killed"]) != 12 or str(ev["refused_ready"]) == "":
		_fail("elephants: the drivers' Kill order (%s)" % str(ev))
		return
	if int(a["snap_t"]) < 0 or int(a["snap_bad"]) != 0:
		_fail("elephants: the restored copy diverged (%d)" % int(a["snap_bad"]))
		return
	print("PASS elephants: the charge met the line at tick %d (%d of 12 alive; missiles took %d hp on the way in, fire set them burning) and knocked down up to %d men at once (%d impacts, %d knock-downs); the broken unit ran amok and trampled %d friends (%d killed), then calmed at tick %d; the third unit's drivers killed it at tick %d (%d beasts); identical on repeat and across snapshot / restore (tick %d)" % [
		int(ev["contact"]), int(ev["alive_at_contact"]), int(ev["hp_lost_approach"]), int(ev["down_max"]),
		int(ev["impacts"]), int(ev["knockdowns"]), int(ev["trample_ff"]), int(ev["friends_lost"]), int(ev["calmed"]),
		int(ev["killed_at"]), int(ev["driver_killed"]), int(a["snap_t"])])


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
	# (across: 0 until 2026-10-09; since men keep to their places the
	# attackers' anchors press up to the citadel and about 40 single-tick
	# cases remain - a man who picked his man this tick, then one of them
	# stepped so the wall lies between; he drops him the next tick, before
	# any blow. Field rebalance 2026-10-09: 184, instrumented: 177 distinct
	# pairs of at most 2 ticks each, no defender on the walk, 0 blows struck
	# through a wall; it counts brief target picks, not blows, so the bound
	# is 250.)
	if int(a["shut"]) < 0 or int(a["hack"]) > 0 or int(a["across"]) > 250 or int(a["ram_at"]) < 0:
		_fail("shut inner gate: %s" % str(a))
		return
	print("PASS shut inner gate: the acropolis shut at tick %d; hacked 0; man-ticks within reach of a man behind a wall %d; the ram sent at it at tick %d (%d blows); winner %d at %d; identical on repeat and across snapshot / restore" % [
		a["shut"], a["across"], a["ram_at"], a["blows"], a["winner"], a["tick"]])


# ------------------------------------------------------ defender layout ---
# The defenders' layout at the attacked gate (docs/AI.md 16, part 2c).

## An equal-force walls-1 ring town (fair siege seed 2, artillery only;
## seed 1 until units flowed into the space, 2026-10-09: there the attack
## now stalls at the gate and nobody reaches the plaza reserve in 4,500
## ticks), both sides Average: the attacked gate is read and a unit of the
## stack stands at its inner mouth before the gate falls, the guards of the
## quiet gates join the stack (at their places in it), the plaza reserve
## counter-attacks an attacker; hashes every tick, the repeat equal, copies
## restored at three points run on equal.
func _layout_run(snap_check: bool) -> Dictionary:
	var sc := Scenarios.fair_siege(782, 1, 4, {})
	var sim := BattleSim.new()
	sim.setup(sc, 53394)
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
			snap_bad += _snap_diverges(sim, sc, 53394, 120)
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


# ------------------------------------------------------------------ flow ---
# docs/DESIGN.md "Units flow into the space" ("--only=flow"): set pieces
# that measure how units get through places that pinch them (ladder feet,
# gateways, streets, a building's corner): the hashed no-progress counter
# u_stuck, men up, ladders in use, men left behind; identical on repeat and
# across snapshot / restore.

## A walls-`walls` ring (no tower engines), no AI: a 90-man heavy unit 12 m
## out from the stretch nearest it with a ladder set at its feet; it picks
## the set up and is ordered onto the stretch's middle. `dfn`: a 60-man
## heavy unit holds that stretch's walkway (else 10 javelinmen at the
## plaza, told to hold fire). Returns {sc, sg, wx, wy}.
static func _flow_ladder_sc(walls: int, dfn: bool) -> Dictionary:
	var city := {"seed": 4242, "level": 2, "walls": walls, "bld": [], "towers": 0}
	var terr := {"kind": Terrain.K_FLAT, "seed": 11, "forest": 0, "ground": 2}
	var d_arm: Array = [[UT.HEAVY, 60]] if dfn else [[UT.JAVELIN, 10]]
	var r := Scenarios.settlement(city, terr, [[UT.HEAVY, 90]], d_arm, 1, [], {"ladders": 1})
	var sc: Dictionary = r["scenario"]
	var probe := BattleSim.new()
	probe.setup(sc, 77)
	var best := -1
	var bd := 0
	var bap := Vector2i.ZERO
	var bmp := Vector2i.ZERO
	for sg in probe.ws_x0.size():
		var mp: Vector2i = BattleSim.seg_pt(probe, sg, BattleSim.seg_len(probe, sg) / 2)
		var lf: Vector3i = BattleSim.ladder_foot(probe, sg, mp.x, mp.y)
		if lf.z == 0 or not BattleSim.ladder_ok(probe, 0, sg, mp.x, mp.y):
			continue
		var d := absi(mp.x - probe.u_cx[0]) + absi(mp.y - probe.u_cy[0])
		if best < 0 or d < bd:
			best = sg
			bd = d
			bap = BattleSim.ladder_approach(probe, sg, lf.x, lf.y)
			bmp = mp
	var c := FM.cos_a(probe.ws_dir[best])
	var s := FM.sin_a(probe.ws_dir[best])
	var ux: int = (bap.x + c * 12 * M / FM.TRIG_ONE) / M
	var uy: int = (bap.y + s * 12 * M / FM.TRIG_ONE) / M
	for ud in sc["units"]:
		if int(ud["side"]) == 0:
			ud["x_m"] = ux
			ud["y_m"] = uy
			ud["facing"] = (probe.ws_dir[best] + 512) & 1023
			ud["files"] = 15
		elif dfn:
			ud["x_m"] = bmp.x / M
			ud["y_m"] = bmp.y / M
			ud["wall"] = best + 1
	sc["equip"] = [[BattleSim.EQ_LADDERS, ux, uy]]
	return {"sc": sc, "sg": best, "wx": bmp.x, "wy": bmp.y}


## Run a ladder set piece: hashes every tick and the climb's measures.
func _flow_ladder_run(walls: int, dfn: bool, snap: bool) -> Dictionary:
	var ls := _flow_ladder_sc(walls, dfn)
	var sc: Dictionary = ls["sc"]
	var sim := BattleSim.new()
	sim.setup(sc, 77)
	var hashes := PackedInt64Array()
	if not dfn:
		sim.queue_order({"tick": 0, "type": BattleSim.ORDER_FIRE, "unit": 1, "on": 0, "player": 51})
	sim.queue_order({"tick": 1, "type": BattleSim.ORDER_PICKUP, "unit": 0, "equip": 0, "run": 0, "player": 50})
	var ordered := false
	var t_start := -1
	var t_all := -1
	var lanes := PackedInt32Array([-1000, -1000, -1000, -1000, -1000, -1000, -1000, -1000])
	var max_use := 0
	var use_sum := 0
	var use_n := 0
	var px := PackedInt32Array()
	var py := PackedInt32Array()
	var mv_t := -1
	var mv_ok := -1
	var snap_bad := 0
	var end_t := 3000
	for t in 3000:
		if not ordered and sim.u_carry[0] == 0:
			ordered = true
			sim.queue_order(BattleSim.make_move_order(sim.tick, 0, int(ls["wx"]), int(ls["wy"]), 768, 20 * M, 0))
		px = sim.pos_x.duplicate()
		py = sim.pos_y.duplicate()
		sim.step()
		hashes.append(sim.state_hash())
		if snap and t == 700:
			snap_bad = _snap_diverges(sim, sc, 77, 120)
		if t_start < 0 and sim.u_stair[0] == BattleSim.ST_LADDER:
			t_start = sim.tick
		if t_start >= 0 and t_all < 0:
			var per: int = BattleSim.climb_per(sim, 0)
			var base: int = sim.u_slot_base[0]
			var up := 0
			for sl in sim.u_alive[0]:
				var i: int = sim.slot_soldier[base + sl]
				if not sim._on_walk(sim.pos_x[i], sim.pos_y[i]):
					continue
				up += 1
				if sim._on_walk(px[i], py[i]):
					continue
				var bk := 0
				var bkd := 1 << 40
				for k in BattleSim.LADDER_SET:
					var f: Vector2i = sim.set_ladder_foot(0, k)
					var dd := FM.approx_len(px[i] - f.x, py[i] - f.y)
					if dd < bkd:
						bkd = dd
						bk = k
				lanes[bk] = sim.tick
			var use := 0
			for k in BattleSim.LADDER_SET:
				if lanes[k] > sim.tick - per:
					use += 1
			max_use = maxi(max_use, use)
			use_sum += use
			use_n += 1
			if sim.u_alive[0] > 0 and up == sim.u_alive[0]:
				t_all = sim.tick
		if mv_t < 0 and t_start >= 0 and sim.u_state[0] == BattleSim.U_READY \
				and (t_all >= 0 or sim.tick - t_start >= 1200 or (sim.u_stair[0] != BattleSim.ST_LADDER and sim.u_wall[0] == 0)):
			mv_t = sim.tick
			var gx: int = sim.u_cx[0] + FM.cos_a(sim.ws_dir[int(ls["sg"])]) * 40 * M / FM.TRIG_ONE
			var gy: int = sim.u_cy[0] + FM.sin_a(sim.ws_dir[int(ls["sg"])]) * 40 * M / FM.TRIG_ONE
			sim.queue_order(BattleSim.make_move_order(sim.tick, 0, gx, gy, 768, 20 * M, 0))
		if mv_t >= 0 and sim.tick == mv_t + 3:
			mv_ok = 1 if sim.u_order[0] == BattleSim.O_MOVE or sim.u_stair[0] == 1 else 0
		if mv_t >= 0 and sim.tick >= mv_t + 300:
			end_t = sim.tick
			break
	var below := 0
	var up_end := 0
	var base2: int = sim.u_slot_base[0]
	for sl in sim.u_alive[0]:
		var i: int = sim.slot_soldier[base2 + sl]
		if sim._on_walk(sim.pos_x[i], sim.pos_y[i]):
			up_end += 1
		else:
			below += 1
	return {"hashes": hashes, "t_start": t_start, "t_all": t_all, "climb": t_all - t_start if t_all >= 0 else -1,
		"max_use": max_use, "mean_use10": use_sum * 10 / maxi(use_n, 1), "up": sim.stat_ladder_up, "alive": sim.u_alive[0],
		"state": sim.u_state[0], "below": below, "up_end": up_end, "mv_ok": mv_ok, "stuck": sim.stat_stuck_u[0],
		"killed": sim.u_killed[0], "snap_bad": snap_bad, "end": end_t, "def_alive": sim.u_alive[1],
		"whole": "on the wall" if up_end == sim.u_alive[0] and sim.u_wall[0] > 0 else ("on the ground" if below == sim.u_alive[0] \
			and sim.u_wall[0] == 0 and sim.u_stair[0] != BattleSim.ST_LADDER else "split")}


## A unit ordered to a point where its formation would stand across the
## corner of a building (a 30 x 30 m block on a plain field); a lone enemy
## far off. Returns the scenario.
static func _corner_sc() -> Dictionary:
	var units: Array = [Scenarios.unit(0, UT.HEAVY, 90, 150, 250, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.SPEAR, 20, 30, 20, Scenarios.FACE_DOWN)]
	units[0]["files"] = 15
	return {"width_m": 300, "height_m": 300, "units": units,
		"orders": [{"tick": 2, "type": BattleSim.ORDER_MOVE, "unit": 0, "x": 145 * M, "y": 132 * M, "facing": Scenarios.FACE_UP,
			"width": 16 * M, "run": 0, "player": 50}],
		"terrain": {"kind": 0, "blocks": [[145, 120, 175, 150]], "urban": [[100, 100, 200, 200]]}}


## Run a pinch set piece ("gate": four units through one open gate to the
## plaza; "street": three a side meeting in a 10 m street; "corner"):
## hashes, arrival, the longest no-progress count, men far from their
## places and men within reach at the end.
func _flow_pinch_run(kind: String, snap: bool) -> Dictionary:
	var sc: Dictionary
	var ticks := 1500
	match kind:
		"gate":
			sc = _gate_jam_scenario()
			ticks = 3000
		"street":
			sc = _street_fight_scenario()
		_:
			sc = _corner_sc()
			ticks = 1500
	var sim := BattleSim.new()
	sim.setup(sc, 777)
	if kind == "gate":
		_gate_jam_orders(sim)
	var hashes := PackedInt64Array()
	var arrived := -1
	var snap_bad := 0
	var inreach_max := 0
	for t in ticks:
		sim.step()
		hashes.append(sim.state_hash())
		if snap and t == ticks / 3:
			snap_bad = _snap_diverges(sim, sc, 777, 120)
		if kind == "street":
			var ir := 0
			for u in 3:
				ir += sim.u_inreach[u]
			inreach_max = maxi(inreach_max, ir)
		elif arrived < 0 and t > 25:
			var all_in := true
			for u in sim.n_units:
				if sim.u_side[u] == 0 and sim.u_state[u] == BattleSim.U_READY and (sim.u_order[u] != BattleSim.O_NONE \
						or _off_places(sim, u) > sim.u_alive[u] / 10):
					all_in = false
			if all_in:
				arrived = t
	var stuck := 0
	var off := 0
	for u in sim.n_units:
		if sim.u_side[u] == 0:
			stuck = maxi(stuck, sim.stat_stuck_u[u])
			if sim.u_state[u] == BattleSim.U_READY:
				off += _off_places(sim, u)
	return {"hashes": hashes, "arrived": arrived, "stuck": stuck, "off": off, "inreach": inreach_max,
		"killed": [sim.u_killed[0] + sim.u_killed[1] + sim.u_killed[2], sim.u_killed[3] + sim.u_killed[4] + sim.u_killed[5]] if kind == "street" else [],
		"snap_bad": snap_bad, "flow": sim.stat_flow, "unstick": sim.stat_unstick}


## Men of unit u more than 3 m from their places.
static func _off_places(sim, u: int) -> int:
	var n := 0
	var base: int = sim.u_slot_base[u]
	for sl in sim.u_alive[u]:
		var i: int = sim.slot_soldier[base + sl]
		if FM.approx_len(sim.pos_x[i] - sim.u_ax[u] - sim.off_x[base + sl], sim.pos_y[i] - sim.u_ay[u] - sim.off_y[base + sl]) > 3 * M:
			n += 1
	return n


func _check_flow() -> void:
	for walls in [1, 2]:
		for dfn in [false, true]:
			var a := _flow_ladder_run(walls, dfn, true)
			var b := _flow_ladder_run(walls, dfn, false)
			var nm := "flow ladders walls %d %s" % [walls, "60 defenders above" if dfn else "no defenders"]
			if a["hashes"] != b["hashes"]:
				_fail("%s: the repeat diverged" % nm)
			if int(a["snap_bad"]) != 0:
				_fail("%s: snapshot / restore diverged" % nm)
			print("PROBE %s: climb from tick %d, all up after %d ticks, ladders in use at most %d (mean x10 %d), men up %d, alive %d (state %d), up at the end %d, below %d (%s), killed %d, defenders left %d, move order taken after %d, longest no-progress %d" % [
				nm, a["t_start"], a["climb"], a["max_use"], a["mean_use10"], a["up"], a["alive"], a["state"], a["up_end"],
				a["below"], a["whole"], a["killed"], a["def_alive"], a["mv_ok"], a["stuck"]])
			if str(a["whole"]) == "split" or (not dfn and (int(a["climb"]) < 0 or int(a["mv_ok"]) != 1)):
				_fail("%s: men left below, or the climb unfinished, or the unit refused a move after it" % nm)
	for kind in ["gate", "street", "corner"]:
		var a := _flow_pinch_run(kind, true)
		var b := _flow_pinch_run(kind, false)
		if a["hashes"] != b["hashes"]:
			_fail("flow %s: the repeat diverged" % kind)
		if int(a["snap_bad"]) != 0:
			_fail("flow %s: snapshot / restore diverged" % kind)
		print("PROBE flow %s: arrived and formed at %d, longest no-progress %d, men > 3 m off their places at the end %d, most men in reach %d, killed %s; flowed layouts %d, releases %s" % [
			kind, a["arrived"], a["stuck"], a["off"], a["inreach"], str(a["killed"]), a["flow"], str(a["unstick"])])


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


# ------------------------------------------------------------ field works ---
# docs/DESIGN.md "Field works and the fortified camp".

## Field works ("--only=stakes"), side 1's pieces placed by the scenario:
## a cavalry charge (u0) into the stakes before a heavy line (u1) loses its
## momentum and takes losses where the same charge without stakes lands;
## heavy foot (u2) crossing a stakes line arrive later than the same foot
## (u3) on open ground, unhurt, then go back and stand in the stakes and
## hack them down; riders (u4) through a caltrop field lose men's hit points
## and the field's stock and find it (q_seen), slower than riders (u5) on
## open ground; a stakes line set alight (test shortcut: 60 hp left) burns
## down. Identical on repeat and across snapshot / restore.
func _stakes_sc(works: bool) -> Dictionary:
	var units := [Scenarios.unit(0, UT.CAVALRY, 60, 100, 220, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.HEAVY, 100, 100, 100, Scenarios.FACE_DOWN),
		Scenarios.unit(0, UT.HEAVY, 100, 220, 200, Scenarios.FACE_UP),
		Scenarios.unit(0, UT.HEAVY, 100, 270, 200, Scenarios.FACE_UP),
		Scenarios.unit(0, UT.CAVALRY, 40, 25, 220, Scenarios.FACE_UP),
		Scenarios.unit(0, UT.CAVALRY, 40, 165, 220, Scenarios.FACE_UP)]
	var orders := [Scenarios.attack(0, 0, 1, 1),
		BattleSim.make_move_order(0, 2, 220 * M, 140 * M, Scenarios.FACE_UP, 28 * M, 0),
		BattleSim.make_move_order(0, 3, 270 * M, 140 * M, Scenarios.FACE_UP, 28 * M, 0),
		BattleSim.make_move_order(0, 4, 25 * M, 110 * M, Scenarios.FACE_UP, 18 * M, 0),
		BattleSim.make_move_order(0, 5, 165 * M, 110 * M, Scenarios.FACE_UP, 18 * M, 0),
		BattleSim.make_move_order(800, 2, 220 * M, 170 * M, Scenarios.FACE_UP, 28 * M, 0)]
	var sc := {"width_m": 300, "height_m": 300, "ai_sides": [], "units": units, "orders": orders}
	if works:
		sc["field_works"] = [[BattleSim.EQ_STAKES, 1, 100, 106, Scenarios.FACE_DOWN, 34],
			[BattleSim.EQ_STAKES, 1, 220, 170, Scenarios.FACE_DOWN, 34],
			[BattleSim.EQ_CALTROPS, 1, 25, 160, Scenarios.FACE_DOWN, 0],
			[BattleSim.EQ_STAKES, 1, 270, 40, Scenarios.FACE_DOWN, 20]]
	return sc


func _stakes_run(works: bool, snaps: Array) -> Dictionary:
	var sc := _stakes_sc(works)
	var sim := BattleSim.new()
	sim.setup(sc, 4242)
	var hashes := PackedInt64Array()
	var ev := {"snaps": []}
	var hp0 := UT.stat(UT.HEAVY, "hp")
	var q_st := sim.n_eq - 4  # (no wagons: the scenario's pieces are the last)
	for t in 1300:
		if works and t == 5:
			sim.q_burn[q_st + 3] = BattleSim.FIRE_TICKS  # test shortcut: set alight, 60 hp left
			sim.q_hp[q_st + 3] = 60
			sim.fire_on = 1
		if t in snaps:
			ev["snaps"].append([t, _snap_follow(sim, sc, 4242, 60)])
		sim.step()
		hashes.append(sim.state_hash())
		if not ev.has("u0_in") and works:
			var b := sim.u_slot_base[0]
			for s in sim.u_alive[0]:
				var i: int = sim.slot_soldier[b + s]
				if sim.fw_inside(q_st, sim.pos_x[i], sim.pos_y[i]):
					ev["u0_in"] = sim.tick
					ev["mom_in"] = sim.u_mom[0]
					break
		# How far the units through the works lag behind those in the open.
		if t < 800:
			ev["lag2"] = maxi(int(ev.get("lag2", 0)), (sim.u_cy[2] - sim.u_cy[3]) / M)
		# Riders inside the caltrop field (10 x 10 m round 25, 160) vs the
		# same box on open ground in the path of the others (165, 160).
		for u in [4, 5]:
			var bx := 25 * M if u == 4 else 165 * M
			var bu := sim.u_slot_base[u]
			for s2 in sim.u_alive[u]:
				var j: int = sim.slot_soldier[bu + s2]
				if absi(sim.pos_x[j] - bx) <= 5 * M and absi(sim.pos_y[j] - 160 * M) <= 5 * M:
					ev["in%d" % u] = int(ev.get("in%d" % u, 0)) + 1
		for u in [2, 3, 4, 5]:
			var key := "arr%d" % u
			var line := 150 if u <= 3 else 125
			if not ev.has(key) and sim.u_maxy[u] < line * M:
				ev[key] = sim.tick  # (its last man past the line)
		if t == 780:
			var hs := 0
			var b2 := sim.u_slot_base[2]
			for s in sim.u_alive[2]:
				hs += sim.hp[sim.slot_soldier[b2 + s]]
			ev["u2_hp"] = hs
			ev["u2_full"] = sim.u_alive[2] * hp0
			ev["impacts"] = sim.stat_impacts
			ev["u0_alive"] = sim.u_alive[0]
		if works and not ev.has("hacked") and sim.q_state[q_st + 1] == BattleSim.Q_WRECKED:
			ev["hacked"] = sim.tick
		if works and not ev.has("burnt") and sim.q_state[q_st + 3] == BattleSim.Q_WRECKED:
			ev["burnt"] = sim.tick
	var hc := 0
	var bc := sim.u_slot_base[4]
	for s in sim.u_alive[4]:
		hc += sim.hp[sim.slot_soldier[bc + s]]
	ev["u4_hp"] = hc
	ev["u4_full"] = 40 * UT.stat(UT.CAVALRY, "hp")
	if works:
		ev["cal_hp"] = sim.q_hp[q_st + 2]
		ev["cal_seen"] = sim.q_seen[q_st + 2]
		ev["fw"] = "cross %d stop %d dmg %d kills %d knock %d hack %d" % [sim.stat_fw_cross, sim.stat_fw_stop,
			sim.stat_fw_dmg, sim.stat_fw_kills, sim.stat_fw_knock, sim.stat_fw_hack]
	return {"hashes": hashes, "ev": ev}


## Snapshot sim now, restore into a fresh copy and step both n ticks: the
## first diverging tick (-1 none, -2 restore refused / hash differs).
func _snap_follow(sim, sc: Dictionary, p_seed: int, n: int) -> int:
	var blob: PackedByteArray = sim.snapshot()
	var c := BattleSim.new()
	c.setup(sc, p_seed)
	var o := BattleSim.new()
	o.setup(sc, p_seed)
	if not c.restore(blob) or not o.restore(blob) or c.state_hash() != sim.state_hash():
		return -2
	for t in n:
		c.step()
		o.step()
		if c.state_hash() != o.state_hash():
			return t
	return -1


func _check_stakes() -> void:
	var snaps := [100, 130, 160, 820]
	var a := _stakes_run(true, snaps)
	var b := _stakes_run(true, [])
	var w := _stakes_run(false, [])
	var ha: PackedInt64Array = a["hashes"]
	var hb: PackedInt64Array = b["hashes"]
	for t in ha.size():
		if ha[t] != hb[t]:
			_fail("stakes: the repeat diverged at tick %d" % t)
			return
	var ev: Dictionary = a["ev"]
	var ew: Dictionary = w["ev"]
	for sn in ev["snaps"]:
		if int(sn[1]) != -1:
			_fail("stakes: snapshot / restore at tick %d: %d" % [int(sn[0]), int(sn[1])])
			return
	for k in ["u0_in", "arr2", "arr3", "arr4", "arr5", "hacked", "burnt"]:
		if not ev.has(k):
			_fail("stakes: %s never happened %s" % [k, str(ev)])
			return
	var bad := ""
	if int(ev["impacts"]) * 3 >= int(ew["impacts"]):
		bad += "charge impacts %d with stakes vs %d without; " % [int(ev["impacts"]), int(ew["impacts"])]
	if int(ev["mom_in"]) >= BattleSim.CHARGE_MIN and int(ev["impacts"]) > 0:
		bad += "momentum %d in the stakes; " % int(ev["mom_in"])
	if int(ev["lag2"]) < 2 or int(ev["u2_hp"]) != int(ev["u2_full"]) or int(ew["lag2"]) != 0:
		bad += "foot through stakes lag %d m (without %d), hp %d / %d; " % [int(ev["lag2"]), int(ew["lag2"]), int(ev["u2_hp"]), int(ev["u2_full"])]
	if int(ev["in4"]) <= int(ev["in5"]) or int(ev["u4_hp"]) >= int(ew["u4_hp"]) \
			or int(ev["cal_hp"]) >= BattleSim.EQ_HP[BattleSim.EQ_CALTROPS] or (int(ev["cal_seen"]) & 1) == 0:
		bad += "caltrops: rider-ticks in the field %d vs %d, at %d vs %d, hp %d vs %d, stock %d, seen %d; " % [int(ev["in4"]), int(ev["in5"]), int(ev["arr4"]), int(ev["arr5"]),
			int(ev["u4_hp"]), int(ew["u4_hp"]), int(ev["cal_hp"]), int(ev["cal_seen"])]
	if bad != "":
		_fail("stakes: " + bad + str(ev))
		return
	print("PASS stakes: the charge met the stakes at tick %d (momentum %d there), %d impacts (without stakes %d), riders %d left at tick 780 (without %d); foot through stakes up to %d m behind the same foot in the open (all past the line at %d vs %d), unhurt; riders through caltrops %d rider-ticks in the field vs %d in the same box in the open (all past at %d vs %d), hit points %d vs %d of %d, stock %d of %d, found by side 0 (seen %d); stakes hacked down at %d, burnt down at %d; %s; identical on repeat and across snapshot / restore at ticks %s" % [
		int(ev["u0_in"]), int(ev["mom_in"]), int(ev["impacts"]), int(ew["impacts"]), int(ev["u0_alive"]), int(ew["u0_alive"]),
		int(ev["lag2"]), int(ev["arr2"]), int(ev["arr3"]), int(ev["in4"]), int(ev["in5"]), int(ev["arr4"]), int(ev["arr5"]),
		int(ev["u4_hp"]), int(ew["u4_hp"]),
		int(ev["u4_full"]), int(ev["cal_hp"]), BattleSim.EQ_HP[BattleSim.EQ_CALTROPS], int(ev["cal_seen"]),
		int(ev["hacked"]), int(ev["burnt"]), str(ev["fw"]), str(snaps)])


## The fortified camp ("--only=fortified"): side 1 (Average AI) stands
## fortified ("fortified": 1): its ditch and palisade are built round its
## units from the scenario key; its archers go up on the front rampart and
## get the range bonus and the cover against side 0's archers; side 0's
## heavy foot attack and climb slowly (stat_fw_climb), fighting from below
## (height melee); side 0's elephants charge and stop at the ditch (no
## impact; without the camp the same charge lands). Identical on repeat and
## across snapshot / restore.
func _fort_sc(fort: bool) -> Dictionary:
	var eleph := UT.index_of("elephant")
	var units := [Scenarios.unit(1, UT.HEAVY, 100, 200, 125, Scenarios.FACE_DOWN),
		Scenarios.unit(1, UT.ARCHER, 80, 200, 140, Scenarios.FACE_DOWN),
		Scenarios.unit(1, UT.HEAVY, 100, 150, 125, Scenarios.FACE_DOWN),
		Scenarios.unit(0, UT.HEAVY, 100, 205, 300, Scenarios.FACE_UP),
		Scenarios.unit(0, eleph, UT.size_of(eleph), 140, 300, Scenarios.FACE_UP),
		Scenarios.unit(0, UT.ARCHER, 80, 270, 260, Scenarios.FACE_UP)]
	var orders := [Scenarios.attack(250, 3, 0, 0), Scenarios.attack(250, 4, 2, 1),
		Scenarios.attack(60, 5, 1, 0)]
	var sc := {"width_m": 400, "height_m": 400, "ai_sides": [1], "units": units, "orders": orders}
	if fort:
		sc["fortified"] = 1
	return sc


func _fort_run(fort: bool, snaps: Array) -> Dictionary:
	var sc := _fort_sc(fort)
	var sim := BattleSim.new()
	sim.setup(sc, 4242)
	var ev := {"snaps": []}
	var hashes := PackedInt64Array()
	var nr := 0
	var nd := 0
	for q in sim.n_eq:
		if sim.q_kind[q] == BattleSim.EQ_RAMPART and sim.q_state[q] == BattleSim.Q_FIXED:
			nr += 1
		elif sim.q_kind[q] == BattleSim.EQ_DITCH:
			nd += 1
	ev["rampart"] = nr
	ev["ditch"] = nd
	var base_rng := UT.stat(UT.ARCHER, "m_range")
	for t in 1500:
		if t in snaps:
			ev["snaps"].append([t, _snap_follow(sim, sc, 4242, 60)])
		sim.step()
		hashes.append(sim.state_hash())
		if not ev.has("on_rampart") and sim.works_at(sim.u_cx[1], sim.u_cy[1], BattleSim.EQ_COVER, 1) >= 0:
			ev["on_rampart"] = sim.tick
			ev["rng"] = sim.range_vs(1, 5)
		if not ev.has("el_ditch"):
			var b := sim.u_slot_base[4]
			for s in sim.u_alive[4]:
				var i: int = sim.slot_soldier[b + s]
				if sim.works_at(sim.pos_x[i], sim.pos_y[i], BattleSim.EQ_STOP) >= 0:
					ev["el_ditch"] = sim.tick
					break
		elif not ev.has("el_mom"):
			ev["el_mom"] = sim.u_mom[4]
	var imp := 0
	var b4 := sim.u_slot_base[4]
	for s in sim.u_count0[4]:
		imp += sim.dbg_impacted[b4 + s] if b4 + s < sim.n else 0
	ev["el_impacts"] = imp
	ev["climb"] = sim.stat_fw_climb
	ev["h_melee"] = sim.stat_h_melee
	ev["cover"] = sim.stat_fw_cover
	ev["charge_up"] = sim.stat_charge_up
	ev["base_rng"] = base_rng
	ev["alive"] = "%d/%d winner %d" % [sim.alive_count(0), sim.alive_count(1), sim.winner]
	return {"hashes": hashes, "ev": ev}


func _check_fortified() -> void:
	var snaps := [200, 400, 700]
	var a := _fort_run(true, snaps)
	var b := _fort_run(true, [])
	var w := _fort_run(false, [])
	var ha: PackedInt64Array = a["hashes"]
	var hb: PackedInt64Array = b["hashes"]
	for t in ha.size():
		if ha[t] != hb[t]:
			_fail("fortified: the repeat diverged at tick %d" % t)
			return
	var ev: Dictionary = a["ev"]
	var ew: Dictionary = w["ev"]
	for sn in ev["snaps"]:
		if int(sn[1]) != -1:
			_fail("fortified: snapshot / restore at tick %d: %d" % [int(sn[0]), int(sn[1])])
			return
	for k in ["on_rampart", "el_ditch", "el_mom"]:
		if not ev.has(k):
			_fail("fortified: %s never happened %s" % [k, str(ev)])
			return
	if int(ev["rampart"]) < 4 or int(ev["ditch"]) < 4 or int(ew["rampart"]) != 0 or int(ev["climb"]) <= 0 \
			or int(ev["h_melee"]) <= 0 or int(ev["rng"]) <= int(ev["base_rng"]) or int(ev["cover"]) <= 0 \
			or int(ev["el_mom"]) >= BattleSim.CHARGE_MIN or int(ev["el_impacts"]) * 3 > int(ew["el_impacts"]):
		_fail("fortified: %s / without the camp %s" % [str(ev), str(ew)])
		return
	print("PASS fortified: %d palisade sections and %d ditch runs built from the scenario key (none without); the AI's archers on the rampart at tick %d, range %d vs %d on the ground, %d missiles stopped by the palisade; attackers climbing %d man-ticks, %d melee rolls with height; the elephants at the ditch at tick %d, momentum %d after, %d impacts (without the camp %d); alive %s (without the camp %s); identical on repeat and across snapshot / restore at ticks %s" % [
		int(ev["rampart"]), int(ev["ditch"]), int(ev["on_rampart"]), int(ev["rng"]), int(ev["base_rng"]), int(ev["cover"]),
		int(ev["climb"]), int(ev["h_melee"]), int(ev["el_ditch"]), int(ev["el_mom"]), int(ev["el_impacts"]),
		int(ew["el_impacts"]), str(ev["alive"]), str(ew["alive"]), str(snaps)])


# --------------------------------------------------------------- mantlets ---

## The field case: side 0 archers (u0) and light foot (u1), side 1 archers
## (u2) and a bolt thrower (u3) shooting at u0, the archers standing and
## shooting at will; mantlets [3, 2] stand before the archers (side 1's
## second before the bolt thrower); at tick 5 the light
## foot (behind the archers) picks up side 0's third mantlet, carries it
## forward and aside and drops it there facing up.
func _mantlet_field_sc(with: bool) -> Dictionary:
	var sc := {"width_m": 300, "height_m": 300, "ai_sides": [], "units": [
		Scenarios.unit(0, UT.ARCHER, 80, 150, 230, Scenarios.FACE_UP),
		Scenarios.unit(0, UT.LIGHT, 60, 130, 250, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.ARCHER, 80, 150, 100, Scenarios.FACE_DOWN),
		Scenarios.unit(1, UT.BOLT, 16, 150, 40, Scenarios.FACE_DOWN)],
		"orders": [{"tick": 1, "type": BattleSim.ORDER_FIRE, "unit": 0, "on": 1},
			{"tick": 1, "type": BattleSim.ORDER_FIRE, "unit": 2, "on": 1}, BattleSim.make_attack_order(1, 3, 0, 0)]}
	if with:
		sc["mantlets"] = [3, 2]
	return sc


func _mantlet_field_run(with: bool, snap_check: bool) -> Dictionary:
	var sc := _mantlet_field_sc(with)
	var sim := BattleSim.new()
	sim.setup(sc, 4242)
	var hashes := PackedInt64Array()
	var ev := {}
	var snap_bad := 0
	var q3 := sim.n_eq - 3  # side 0's third mantlet (the scenario's are the last: 3 then 2)
	for t in 1200:
		var tk: int = sim.tick
		if with and tk == 5:
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_PICKUP, "unit": 1, "equip": q3, "run": 0})
		if with and not ev.has("picked") and sim.q_state[q3] == BattleSim.Q_CARRIED:
			ev["picked"] = tk
			sim.queue_order(BattleSim.make_move_order(tk, 1, 100 * M, 200 * M, Scenarios.FACE_UP, 20 * M, 0))
		if with and ev.has("picked") and not ev.has("dropped") and tk >= int(ev["picked"]) + 20 \
				and sim.u_order[1] == BattleSim.O_NONE:
			ev["dropped"] = tk
			sim.queue_order({"tick": tk, "type": BattleSim.ORDER_DROP, "unit": 1})
		sim.step()
		hashes.append(sim.state_hash())
		if snap_check and (sim.tick == 200 or sim.tick == 700):
			snap_bad += _snap_diverges(sim, sc, 4242, 120)
	ev["cover"] = sim.stat_mantlet_cover
	ev["lost0"] = 80 - sim.u_alive[0]
	ev["lost2"] = 80 - sim.u_alive[2]
	if with:
		ev["face"] = sim.q_face[q3]
		ev["state"] = sim.q_state[q3]
		ev["q_y"] = sim.q_y[q3] / M
	return {"hashes": hashes, "ev": ev, "snap_bad": snap_bad}


## The assault: a walls-1 fair siege with ladders, a ram and four mantlets
## for the attackers (side 0) and two for the defenders, both sides AI.
func _mantlet_siege_sc() -> Dictionary:
	var sc := Scenarios.fair_siege(741, 1, 4, {"ladders": 2, "ram": 1, "mantlets": 4})
	sc["mantlets"] = [4, 2]
	return sc


func _mantlet_siege_run(snap_check: bool) -> Dictionary:
	var sc := _mantlet_siege_sc()
	var sim := BattleSim.new()
	sim.setup(sc, 53197)
	var hashes := PackedInt64Array()
	var snap_bad := 0
	var carried := {}
	var set_t := -1
	while sim.tick < 3000 and sim.winner < 0:
		sim.step()
		hashes.append(sim.state_hash())
		if snap_check and (sim.tick == 300 or sim.tick == 1500):
			snap_bad += _snap_diverges(sim, sc, 53197, 120)
		for q in sim.n_eq:
			if sim.q_kind[q] == BattleSim.EQ_MANTLET and sim.q_state[q] == BattleSim.Q_CARRIED:
				carried[q] = sim.q_unit[q]
		if set_t < 0 and not carried.is_empty() and sim.ai_gate[0] >= 0:
			# Every attacker mantlet carried so far now stands on its place.
			var all_set := true
			for q in carried:
				var rk: Vector2i = SiegeAI._mantlet_rank(sim, 0, q)
				var sp: Vector2i = SiegeAI._mantlet_spot(sim, 0, rk.x, rk.y, sim.ai_gate[0])
				if sim.q_state[q] != BattleSim.Q_GROUND or not SiegeAI._mantlet_set(sim, q, sp, sim.ai_gate[0]):
					all_set = false
			if all_set and carried.size() >= 4:
				set_t = sim.tick
	return {"hashes": hashes, "snap_bad": snap_bad, "carried": carried.size(), "set_t": set_t,
		"cover": sim.stat_mantlet_cover, "ticks": sim.tick, "winner": sim.winner}


# ------------------------------------------ siege equipment usability ---
# docs/DESIGN.md "Siege equipment usability" ("--only=carry", also in the
# full run): pieces taken up and put down in the deployment phase, the carry
# patterns, a mantlet line at the carrying unit's frontage.

## The walls-2 siege with ladders, a ram, a siege tower, two mantlets and a
## wagon for the attackers (side 0), in a deployment phase, no AI.
func _carry_siege_sc() -> Dictionary:
	var sc := Scenarios.fair_siege(741, 2, 4, {"ladders": 2, "ram": 1, "towers": 1, "mantlets": 2,
		"extra": [[UT.index_of("wagon2"), 8]]})
	sc["ai_sides"] = []
	sc["deploy_time"] = 60
	sc["deploy_need"] = 1
	return sc


## Deployment pick-up run: returns {hashes, ev, snap_bad}.
func _carry_siege_run(snap_check: bool) -> Dictionary:
	var sc := _carry_siege_sc()
	var sim := BattleSim.new()
	sim.setup(sc, 9090)
	var att := 1 - sim.city_def
	var ev := {}
	var pq := {}  # kind -> first piece of the attackers on the ground
	for q in sim.n_eq:
		var k: int = sim.q_kind[q]
		if sim.q_side[q] == att and not pq.has(k):
			pq[k] = q
	var by := {}  # what each unit takes: "lad", "ram", "tower", "mant", "wagon"
	var heavy: Array[int] = []
	for u in sim.n_units:
		if sim.u_side[u] != att:
			continue
		var ty: int = sim.u_type[u]
		if UT.stat(ty, "wagon") >= 0:
			by["wagon"] = u
		elif ty == UT.HEAVY:
			heavy.append(u)
		elif ty == UT.LIGHT and not by.has("ram"):
			by["ram"] = u
		elif ty == UT.ARCHER and not by.has("mant"):
			by["mant"] = u
	if heavy.size() < 2 or not by.has("ram") or not by.has("mant") or not by.has("wagon") \
			or not pq.has(BattleSim.EQ_LADDERS) or not pq.has(BattleSim.EQ_RAM) or not pq.has(BattleSim.EQ_TOWER) \
			or not pq.has(BattleSim.EQ_MANTLET):
		_fail("carry: the scenario lacks a piece or a unit (%s, %s)" % [str(pq), str(by)])
		return {"hashes": PackedInt64Array(), "ev": ev, "snap_bad": 1}
	by["lad"] = heavy[0]
	by["tower"] = heavy[1]
	var ql: int = pq[BattleSim.EQ_LADDERS]
	# The mantlet set up before the archers (the first stands before the bolt battery).
	var qm := -1
	var um0: int = by["mant"]
	for q in sim.n_eq:
		if sim.q_kind[q] == BattleSim.EQ_MANTLET and (qm < 0 or absi(sim.q_x[q] - sim.u_ax[um0]) < absi(sim.q_x[qm] - sim.u_ax[um0])):
			qm = q
	var hashes := PackedInt64Array([sim.state_hash()])
	var snap_bad := 0
	var dstep := func(o: Array) -> void:
		for od in o:
			var d: Dictionary = (od as Dictionary).duplicate()
			d["tick"] = 0
			sim.queue_order(d)
		sim.step()
		hashes.append(sim.state_hash())
	# 1. Ladders, ram, mantlet, then (the ram's pair moved off the tower's
	# column: it stood behind the ram) the tower: each assigned in the
	# deployment.
	var ur: int = by["ram"]
	var ut: int = by["tower"]
	dstep.call([{"type": BattleSim.ORDER_PICKUP, "unit": by["lad"], "equip": ql},
		{"type": BattleSim.ORDER_PICKUP, "unit": ur, "equip": pq[BattleSim.EQ_RAM]},
		{"type": BattleSim.ORDER_PICKUP, "unit": ut, "equip": pq[BattleSim.EQ_TOWER]},
		{"type": BattleSim.ORDER_PICKUP, "unit": by["mant"], "equip": qm}])
	ev["tower_first"] = sim.u_carry[ut]  # (refused: inside the ram's column)
	dstep.call([{"type": BattleSim.ORDER_PLACE, "unit": ur, "x": sim.u_ax[ur] - 40 * M, "y": sim.u_ay[ur],
		"facing": sim.u_face[ur], "files": sim.u_files[ur]}])
	dstep.call([{"type": BattleSim.ORDER_PICKUP, "unit": ut, "equip": pq[BattleSim.EQ_TOWER]}])
	var files := {}
	for key in ["lad", "ram", "tower", "mant", "wagon"]:
		var u: int = by[key]
		var q: int = sim.u_carry[u]
		files[key] = sim.files_of(u) if q >= 0 else -1
		if q >= 0 and (sim.q_x[q] != sim.u_ax[u] or sim.q_y[q] != sim.u_ay[u]):
			files[key] = -2  # (the piece not at its carriers' anchor)
	ev["files"] = files
	ev["mlen0"] = sim.q_len[qm]
	ev["phase1"] = sim.phase
	if snap_check:
		snap_bad += _snap_diverges(sim, sc, 9090, 30)
	# 2. The pair placed: the ladder carriers 20 m to the side, the set with them.
	var ul: int = by["lad"]
	var x0: int = sim.q_x[ql]
	dstep.call([{"type": BattleSim.ORDER_PLACE, "unit": ul, "x": sim.u_ax[ul] + 20 * M, "y": sim.u_ay[ul],
		"facing": sim.u_face[ul], "files": sim.u_files[ul]}])
	ev["moved"] = (sim.q_x[ql] - x0) / M
	ev["with"] = 1 if sim.q_state[ql] == BattleSim.Q_CARRIED and sim.q_x[ql] == sim.u_ax[ul] else 0
	# 3. Dropped: on the ground where they stand, the men in their ordered files.
	var um: int = by["mant"]
	dstep.call([{"type": BattleSim.ORDER_DROP, "unit": ul}, {"type": BattleSim.ORDER_DROP, "unit": um}])
	ev["drop_l"] = [sim.q_state[ql], sim.q_x[ql] == sim.u_ax[ul], sim.files_of(ul) == sim.u_files[ul]]
	ev["drop_m"] = [sim.q_state[qm], sim.q_len[qm], BattleSim.mantlet_len(sim, um), sim.files_of(um) == sim.u_files[um]]
	# 4. Picked up again.
	dstep.call([{"type": BattleSim.ORDER_PICKUP, "unit": ul, "equip": ql},
		{"type": BattleSim.ORDER_PICKUP, "unit": um, "equip": qm}])
	ev["again"] = [sim.q_unit[ql] == ul, sim.q_unit[qm] == um, sim.files_of(ul), sim.files_of(um)]
	# 5. The other side's piece (a mantlet: either side's in the battle) in
	# the deployment: refused.
	var du := -1
	for u in sim.n_units:
		if du < 0 and sim.u_side[u] == sim.city_def and sim.u_cls[u] == UT.CLS_INF:
			du = u
	ev["refused"] = du >= 0 and BattleSim.pickup_refusal(sim, du, pq[BattleSim.EQ_MANTLET]) != ""
	dstep.call([{"type": BattleSim.ORDER_READY, "who": 0}])
	ev["battle"] = sim.phase
	while sim.tick < 400:
		sim.step()
		hashes.append(sim.state_hash())
		if snap_check and sim.tick == 200:
			snap_bad += _snap_diverges(sim, sc, 9090, 60)
	return {"hashes": hashes, "ev": ev, "snap_bad": snap_bad}


## The mantlet line wide and narrow: 80 archers (side 0) carry their mantlet
## from the deployment and put it down at their frontage (wide) or with 4
## files (a 6 m line; then placed again at their frontage); the enemy's
## archers shoot at them for 60 s. Returns {cover, len, lost, hashes}.
func _carry_width_run(wide: bool, snap_check: bool) -> Dictionary:
	var sc := {"width_m": 300, "height_m": 300, "ai_sides": [], "deploy_time": 30, "deploy_need": 1, "units": [
		Scenarios.unit(0, UT.ARCHER, 80, 150, 200, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.ARCHER, 80, 150, 100, Scenarios.FACE_DOWN)],
		"orders": [{"tick": 1, "type": BattleSim.ORDER_FIRE, "unit": 1, "on": 1},
			BattleSim.make_attack_order(1, 1, 0, 0), {"tick": 1, "type": BattleSim.ORDER_FIRE, "unit": 0, "on": 0}],
		"mantlets": [1, 0]}
	var sim := BattleSim.new()
	sim.setup(sc, 4242)
	var q := sim.n_eq - 1
	var hashes := PackedInt64Array()
	var snap_bad := 0
	var f0: int = sim.u_files[0]
	var ax: int = sim.u_ax[0]
	var ay: int = sim.u_ay[0]
	var plan: Array = [[{"type": BattleSim.ORDER_PICKUP, "unit": 0, "equip": q}]]
	if not wide:
		plan.append([{"type": BattleSim.ORDER_PLACE, "unit": 0, "x": ax, "y": ay - 2 * M, "facing": Scenarios.FACE_UP, "files": 4}])
	plan.append([{"type": BattleSim.ORDER_DROP, "unit": 0}])
	if not wide:
		plan.append([{"type": BattleSim.ORDER_PLACE, "unit": 0, "x": ax, "y": ay - 2 * M, "facing": Scenarios.FACE_UP, "files": f0}])
	plan.append([{"type": BattleSim.ORDER_READY, "who": 0}])
	for os in plan:
		for o in os:
			var d: Dictionary = (o as Dictionary).duplicate()
			d["tick"] = 0
			sim.queue_order(d)
		sim.step()
		hashes.append(sim.state_hash())
	var ln: int = sim.q_len[q]
	var placed := [sim.q_state[q], sim.u_files[0], sim.u_ax[0] == sim.q_x[q]]
	while sim.tick < 600:
		sim.step()
		hashes.append(sim.state_hash())
		if snap_check and sim.tick == 300:
			snap_bad += _snap_diverges(sim, sc, 4242, 60)
	return {"cover": sim.stat_mantlet_cover, "len": ln, "lost": 80 - sim.u_alive[0], "hashes": hashes,
		"snap_bad": snap_bad, "placed": placed, "hp": sim.q_hp[q]}


func _check_carry() -> void:
	var a := _carry_siege_run(true)
	var b := _carry_siege_run(false)
	if a["hashes"].is_empty():
		return
	if a["hashes"] != b["hashes"]:
		_fail("carry: the deployment pick-up run diverged on repeat")
		return
	var ev: Dictionary = a["ev"]
	var bad := ""
	if int(a["snap_bad"]) != 0:
		bad += "snapshot / restore diverged (%d); " % int(a["snap_bad"])
	var fl: Dictionary = ev["files"]
	var mfiles: int = int(ev["mlen0"]) / UT.stat(UT.ARCHER, "file_sp")
	if int(fl["lad"]) != BattleSim.LADDER_SET or int(fl["ram"]) != BattleSim.RAM_FILES or int(fl["tower"]) != 8 \
			or int(fl["wagon"]) != BattleSim.WAGON_FILES or int(fl["mant"]) != mfiles or int(ev["phase1"]) != BattleSim.PHASE_DEPLOY:
		bad += "carry files %s (mantlet want %d); " % [str(fl), mfiles]
	if int(ev["moved"]) != 20 or int(ev["with"]) != 1:
		bad += "the pair placed: piece moved %d m, with its carriers %d; " % [int(ev["moved"]), int(ev["with"])]
	var dl: Array = ev["drop_l"]
	var dm: Array = ev["drop_m"]
	if int(dl[0]) != BattleSim.Q_GROUND or not bool(dl[1]) or not bool(dl[2]) or int(dm[0]) != BattleSim.Q_GROUND \
			or int(dm[1]) != int(dm[2]) or not bool(dm[3]):
		bad += "dropped: ladders %s, mantlet %s; " % [str(dl), str(dm)]
	var ag: Array = ev["again"]
	if not bool(ag[0]) or not bool(ag[1]) or int(ag[2]) != BattleSim.LADDER_SET:
		bad += "picked up again: %s; " % str(ag)
	if not bool(ev["refused"]) or int(ev["battle"]) != BattleSim.PHASE_BATTLE or int(ev["tower_first"]) >= 0:
		bad += "refusal %s (tower first %d), phase after ready %d; " % [str(ev["refused"]), int(ev["tower_first"]), int(ev["battle"])]
	var w := _carry_width_run(true, true)
	var w2 := _carry_width_run(true, false)
	var n := _carry_width_run(false, false)
	if w["hashes"] != w2["hashes"]:
		bad += "the mantlet width run diverged on repeat; "
	if int(w["snap_bad"]) != 0:
		bad += "mantlet width snapshot / restore diverged; "
	if int(w["len"]) < 20 * M or int(w["len"]) > 28 * M or int(n["len"]) != BattleSim.MANTLET_W \
			or int(w["cover"]) <= int(n["cover"]):
		bad += "mantlet line %d mm stopped %d, narrow %d mm stopped %d (placed %s / %s); " % [int(w["len"]), int(w["cover"]),
			int(n["len"]), int(n["cover"]), str(w["placed"]), str(n["placed"])]
	if bad != "":
		_fail("carry: " + bad)
		return
	print("PASS carry: deployment pick-up of ladders / ram / siege tower / mantlet, carry files %s; the ladder pair placed 20 m over, dropped, picked up again; a mantlet put down by 80 archers (%d files) is a %.1f m line (%d hp): %d missiles stopped in 60 s, %d archers lost; a 6 m line before the same unit: %d stopped, %d lost; identical on repeat and across snapshot / restore" % [
		str(fl), int(w["placed"][1]), int(w["len"]) / 1024.0, int(w["hp"]), int(w["cover"]), int(w["lost"]), int(n["cover"]), int(n["lost"])])


func _check_mantlets() -> void:
	var a := _mantlet_field_run(true, true)
	var b := _mantlet_field_run(true, false)
	var w := _mantlet_field_run(false, false)
	if a["hashes"] != b["hashes"]:
		_fail("mantlets field: the repeat diverged")
		return
	var ev: Dictionary = a["ev"]
	var ew: Dictionary = w["ev"]
	var bad := ""
	if int(a["snap_bad"]) != 0:
		bad += "snapshot / restore diverged (%d); " % int(a["snap_bad"])
	if int(ev["cover"]) <= 0 or int(ew["cover"]) != 0 or int(ev["lost0"]) >= int(ew["lost0"]):
		bad += "missiles stopped %d (without %d), side 0 archers lost %d (without %d); " % [int(ev["cover"]),
			int(ew["cover"]), int(ev["lost0"]), int(ew["lost0"])]
	if not ev.has("picked") or not ev.has("dropped") or int(ev["state"]) != BattleSim.Q_GROUND \
			or int(ev["face"]) != Scenarios.FACE_UP or int(ev["q_y"]) > 215:
		bad += "carried mantlet: %s; " % str(ev)
	if bad != "":
		_fail("mantlets field: " + bad)
		return
	var sa := _mantlet_siege_run(true)
	var sb := _mantlet_siege_run(false)
	if sa["hashes"] != sb["hashes"]:
		_fail("mantlets siege: the repeat diverged")
		return
	if int(sa["snap_bad"]) != 0 or int(sa["carried"]) < 4 or int(sa["set_t"]) < 0:
		_fail("mantlets siege: %s" % str({"snap_bad": sa["snap_bad"], "carried": sa["carried"], "set_t": sa["set_t"],
			"cover": sa["cover"]}))
		return
	print("PASS mantlets: field: %d missiles stopped by mantlets, side 0 archers lost %d (without mantlets %d), side 1 archers %d (%d); light foot picked one up at tick %d, dropped it at %d, standing at y %d m facing up; assault: the attackers' AI carried %d mantlets, all set on the screen line by tick %d, %d missiles stopped by tick %d (winner %d); identical on repeat and across snapshot / restore" % [
		int(ev["cover"]), int(ev["lost0"]), int(ew["lost0"]), int(ev["lost2"]), int(ew["lost2"]), int(ev["picked"]),
		int(ev["dropped"]), int(ev["q_y"]), int(sa["carried"]), int(sa["set_t"]), int(sa["cover"]), int(sa["ticks"]), int(sa["winner"])])



# ---------------------------------------------------------- river crossings ---

const CROSS_SEED := 7
const CROSS_TICKS := 3000
const CROSS_BY := 2400


## An AI battle over the crossing CROSS_SEED (kind 0 ford / 1 bridge, side 1
## holding the far bank, fortified or not): hashes, the first tick 50 of
## side 0's men stand on the far bank, men-ticks in the water (by state),
## snapshot / restore follow-ups at `snaps`.
func _cross_run(kind: int, fort: bool, snaps: Array) -> Dictionary:
	var sc := Scenarios.crossing(kind, CROSS_SEED, fort)
	var sim := BattleSim.new()
	sim.setup(sc, 4242)
	var g: Dictionary = sim.riv
	var hashes := PackedInt64Array()
	var ev := {"far_at": -1, "wet": 0, "wet_rout": 0, "snaps": [], "map": sim.map_hash, "ter": sim.ter_hash}
	for t in CROSS_TICKS:
		if t in snaps:
			ev["snaps"].append([t, _snap_follow(sim, sc, 4242, 60)])
		sim.step()
		hashes.append(sim.state_hash())
		var far := 0
		for i in sim.n:
			var st: int = sim.state[i]
			if st >= BattleSim.S_DEAD:
				continue
			if sim.river_at(sim.pos_x[i], sim.pos_y[i]) == MapGen.R_WATER:
				ev["wet"] = int(ev["wet"]) + 1
				if st == BattleSim.S_ROUTING:
					ev["wet_rout"] = int(ev["wet_rout"]) + 1
			if int(ev["far_at"]) < 0 and sim.u_side[sim.unit_of[i]] == 0 \
					and sim.pos_y[i] * 100 / M < MapGen.river_edge(g, sim.pos_x[i] / M, 1):
				far += 1
		if int(ev["far_at"]) < 0 and far >= 50:
			ev["far_at"] = sim.tick
		if sim.ended != 0:
			break
	ev["ford"] = sim.stat_ford
	ev["routed"] = sim.stat_ai[8] if sim.stat_ai.size() > 8 else 0
	var rout_men := 0
	for u in sim.n_units:
		rout_men += sim.u_routs[u]
	ev["routs"] = rout_men
	ev["alive"] = "%d/%d winner %d at %d" % [sim.alive_count(0), sim.alive_count(1), sim.winner, sim.tick]
	return {"hashes": hashes, "ev": ev, "sim": sim}


## Cavalry (side 0) charging heavy foot (side 1) that stands at the far
## exit of the ford of crossing CROSS_SEED (river: false, the same set
## piece on the same ground without the river): u0's momentum when it
## reaches them, its charge impacts, its highest momentum while wading.
func _ford_charge(river: bool) -> Dictionary:
	var rk := {"id": CROSS_SEED, "kind": 0, "seed": CROSS_SEED, "bank": 1}
	var g := MapGen.river_geom(rk, 560, 560)
	var m0 := MapGen.river_mouth(g, 0)
	var m1 := MapGen.river_mouth(g, 1)
	var units := [Scenarios.unit(0, UT.CAVALRY, 60, m0.x, m0.y + 45, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.HEAVY, 60, m1.x, m1.y - 20, Scenarios.FACE_DOWN, 12)]
	var sc := {"width_m": 560, "height_m": 560, "ai_sides": [], "units": units,
		"terrain": {"kind": Terrain.K_ROLLING, "seed": CROSS_SEED},
		"orders": [{"tick": 2, "type": BattleSim.ORDER_MOVE, "unit": 1, "x": m1.x * M, "y": (m1.y + 3) * M,
			"facing": Scenarios.FACE_DOWN, "width": 12 * M, "run": 0, "player": 50},
			Scenarios.attack(260, 0, 1, 1)]}
	if river:
		sc["river"] = rk
	var sim := BattleSim.new()
	sim.setup(sc, 4242)
	var ev := {"contact": -1, "mom": -1, "wade_mom": 0, "impacts": 0}
	for t in 700:
		sim.step()
		if sim.u_frd.size() > 0 and sim.u_frd[0] != 0:
			ev["wade_mom"] = maxi(int(ev["wade_mom"]), sim.u_mom[0])
		if int(ev["contact"]) < 0 and (sim.u_contact[0] > 0 or sim.u_fighting[0] > 0):
			ev["contact"] = sim.tick
			ev["mom"] = sim.u_mom[0]
	var imp := 0
	var b := sim.u_slot_base[0]
	for s2 in sim.u_count0[0]:
		imp += sim.dbg_impacted[b + s2] if b + s2 < sim.n else 0
	for i in sim.n:
		if sim.unit_of[i] == 1:
			imp += sim.dbg_impacted[i]
	ev["impacts"] = imp
	ev["stop"] = sim.stat_ford_stop
	return ev


func _check_crossing() -> void:
	# Maps: the same id the same map, another id another, side 0 holding
	# the far bank the same crossing turned round.
	var maps := {}
	for k in [[0, CROSS_SEED, 1], [0, CROSS_SEED, 1], [1, CROSS_SEED, 1], [0, CROSS_SEED + 1, 1], [0, CROSS_SEED, 0]]:
		var sc := Scenarios.crossing(int(k[0]), int(k[1]), false)
		sc["river"]["bank"] = int(k[2])
		var sim := BattleSim.new()
		sim.setup(sc, 4242 + maps.size())  # (the battle seed plays no part in the map)
		maps[maps.size()] = sim
	var m0: BattleSim = maps[0]
	var flipped := true
	var o2: PackedByteArray = (maps[4] as BattleSim).obs
	for c in m0.obs.size():
		if m0.obs[c] != o2[o2.size() - 1 - c]:
			flipped = false
			break
	var h0: PackedInt32Array = m0.ter_h
	var h4: PackedInt32Array = (maps[4] as BattleSim).ter_h
	for c in h0.size():
		if h0[c] != h4[h4.size() - 1 - c]:
			flipped = false
			break
	if m0.riv_on == 0 or m0.ter_hash != (maps[1] as BattleSim).ter_hash or m0.ter_hash == (maps[2] as BattleSim).ter_hash \
			or m0.ter_hash == (maps[3] as BattleSim).ter_hash or not flipped or m0.ng_x.size() < 10:
		_fail("crossing maps: riv_on %d, hashes %08x %08x (bridge %08x, other id %08x), turned round %s, nodes %d" % [
			m0.riv_on, m0.ter_hash, (maps[1] as BattleSim).ter_hash, (maps[2] as BattleSim).ter_hash,
			(maps[3] as BattleSim).ter_hash, str(flipped), m0.ng_x.size()])
		return
	var nw := 0
	var nf := 0
	for c in m0.rv.size():
		if m0.rv[c] == MapGen.R_WATER:
			nw += 1
		elif m0.rv[c] == MapGen.R_FORD:
			nf += 1
	print("PASS crossing maps: the ford of id %d is the same map on every build (%08x), its bridge (%08x) and id %d (%08x) differ, side 0 holding the far bank gets it turned round; river %d m wide, %d water cells, %d ford cells, %d nodes on the way across" % [
		CROSS_SEED, m0.ter_hash, (maps[2] as BattleSim).ter_hash, CROSS_SEED + 1, (maps[3] as BattleSim).ter_hash,
		int(m0.riv["hw"]) * 2, nw, nf, m0.ng_x.size()])
	# The charge through the ford.
	var ch := _ford_charge(true)
	var cp := _ford_charge(false)
	if int(ch["contact"]) < 0 or int(ch["mom"]) >= BattleSim.CHARGE_MIN or int(ch["impacts"]) != 0 \
			or int(ch["wade_mom"]) != 0 or int(ch["stop"]) <= 0 or int(cp["impacts"]) <= 0:
		_fail("crossing charge: through the ford %s, on the plain %s" % [str(ch), str(cp)])
	else:
		print("PASS crossing charge: cavalry charging through the ford reaches the foot at its exit at tick %d with momentum %d (0 all the way through the water, %d rider-ticks stopped), %d impacts; the same charge without the river: momentum %d, %d impacts" % [
			int(ch["contact"]), int(ch["mom"]), int(ch["stop"]), int(ch["impacts"]), int(cp["mom"]), int(cp["impacts"])])
	# AI battles.
	var snaps := [300, 1200, 2100]
	for kf in [[0, false], [1, false], [0, true]]:
		var kind: int = kf[0]
		var fort: bool = kf[1]
		var name := "%s%s" % ["ford" if kind == 0 else "bridge", ", fortified" if fort else ""]
		var a := _cross_run(kind, fort, snaps)
		var ev: Dictionary = a["ev"]
		var b := _cross_run(kind, fort, [])
		var ha: PackedInt64Array = a["hashes"]
		var hb: PackedInt64Array = b["hashes"]
		for t in mini(ha.size(), hb.size()):
			if ha[t] != hb[t] or ha.size() != hb.size():
				_fail("crossing %s: the repeat diverged at tick %d" % [name, t])
				return
		for sn in ev["snaps"]:
			if int(sn[1]) != -1:
				_fail("crossing %s: snapshot / restore at tick %d: %d" % [name, int(sn[0]), int(sn[1])])
				return
		var sim: BattleSim = a["sim"]
		var camp := ""
		if fort:
			var g: Dictionary = sim.riv
			var mo := MapGen.river_mouth(g, 1)
			var ex := mo.x * M
			var ey := (mo.y + MapGen.RIV_MOUTH) * M
			var near := 0
			var wet := 0
			var nr := 0
			for q in sim.n_eq:
				var kq: int = sim.q_kind[q]
				if kq != BattleSim.EQ_RAMPART and kq != BattleSim.EQ_DITCH:
					continue
				var ext := sim.fw_extent(q)
				for cx in [-1, 0, 1]:
					for cy in [-1, 0, 1]:
						if sim.river_at(sim.q_x[q] + cx * ext.x, sim.q_y[q] + cy * ext.y) == MapGen.R_WATER:
							wet += 1
				if kq != BattleSim.EQ_RAMPART:
					continue
				nr += 1
				var dx := maxi(absi(ex - sim.q_x[q]) - ext.x, 0)
				var dy := maxi(absi(ey - sim.q_y[q]) - ext.y, 0)
				if FM.approx_len(dx, dy) <= 20 * M:
					near += 1
			var gaps: Array = BattleAI.camp_gaps(sim, 1)
			if near <= 0 or wet != 0 or not gaps.is_empty() or nr < 6:
				_fail("crossing %s: camp %d sections, %d within 20 m of the exit, %d corners in the water, front gaps %s" % [
					name, nr, near, wet, str(gaps)])
				return
			camp = "; the camp: %d palisade sections, %d within 20 m of the exit, no gap facing the water, nothing in it" % [nr, near]
		if int(ev["far_at"]) < 0 or int(ev["far_at"]) > CROSS_BY or int(ev["wet"]) != 0 or (kind == 0 and int(ev["ford"]) <= 0):
			_fail("crossing %s: %s" % [name, str(ev)])
			return
		print("PASS crossing %s: the AI attacker has 50 men on the far bank at tick %d (by %d), %d unit-ticks wading, nobody in the water (%d unit routs), alive %s%s; identical on repeat and across snapshot / restore at ticks %s" % [
			name, int(ev["far_at"]), CROSS_BY, int(ev["ford"]), int(ev["routs"]), str(ev["alive"]), camp, str(snaps)])


# ------------------------------------------------------ heroes and agents ---
# docs/DESIGN.md "Heroes and agents" ("--only=chars", also in the full run):
# flat set pieces, no AI unless said: (A) each aura measured against the same
# units out of it (to-hit and kills, range and shots, charge impacts, the
# siege hero's climb / reload / batter for the side); (B) a champion cut
# down: his side near him shaken by fall_loss, the far one not, the enemy
# near him heartened; (C) the assassin hidden (the enemy's target lists
# skip him) until he comes near; (D) sabotage of an enemy battery; (E) a shut
# gate unbarred from inside (gate_ops); (F) attempts on a general by seed
# (outcomes); (G) parleys with routers, one that ends in a surrender
# (prisoners, the result rows) and one that does not; (H) the AI's
# characters in battle_2000. Identical on repeat and across snapshot /
# restore.

func _chars_sc(units: Array, chars: Array, w: int = 400, h: int = 400) -> Dictionary:
	return {"width_m": w, "height_m": h, "ai_sides": [], "orders": [], "units": units, "chars": chars,
		"terrain": {"kind": Terrain.K_FLAT}}


func _ch(key: String) -> Dictionary:
	return {"key": key, "name": key.capitalize()}


## The first unit of character kind k on side s (-1 none).
func _ch_unit(sim, s: int, k: int) -> int:
	for u in sim.n_units:
		if sim.u_side[u] == s and sim.u_char[u] == k:
			return u
	return -1


## Place unit u's anchor and men at (x, y) metres (set pieces).
func _ch_put(sim, u: int, x: int, y: int) -> void:
	sim.u_ax[u] = x * M
	sim.u_ay[u] = y * M
	sim.u_dx[u] = x * M
	sim.u_dy[u] = y * M
	var base: int = sim.u_slot_base[u]
	for s in sim.u_alive[u]:
		var i: int = sim.slot_soldier[base + s]
		sim.pos_x[i] = x * M + sim.off_x[base + s]
		sim.pos_y[i] = y * M + sim.off_y[base + s]
	sim.u_dirty[u] = 1
	sim.u_settled[u] = 0
	sim._update_bounds()


func _chars_run(snap_check: bool) -> Dictionary:
	var ev := {}
	var hashes := PackedInt64Array()
	var snap_bad := 0
	var snaps := 0
	# A1: to-hit and morale. Two mirrored light infantry fights 200 m apart,
	# the champion behind ours on the left (within his 40 m), none on the right.
	var sc := _chars_sc([
		Scenarios.unit(0, UT.LIGHT, 60, 100, 230, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.LIGHT, 60, 100, 200, Scenarios.FACE_DOWN),
		Scenarios.unit(0, UT.LIGHT, 60, 300, 230, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.LIGHT, 60, 300, 200, Scenarios.FACE_DOWN)], [[_ch("hero_foot")], []])
	var sim := BattleSim.new()
	sim.setup(sc, 901)
	var hf := _ch_unit(sim, 0, UT.CK_FOOT)
	_ch_put(sim, hf, 100, 255)
	sim.queue_order(BattleSim.make_attack_order(1, 0, 1, 0))
	sim.queue_order(BattleSim.make_attack_order(1, 2, 3, 0))
	sim.queue_order(BattleSim.make_attack_order(1, 1, 0, 0))
	sim.queue_order(BattleSim.make_attack_order(1, 3, 2, 0))
	for t in 400:
		sim.step()
		hashes.append(sim.state_hash())
		if sim.tick == 20:
			ev["foot_aura_in"] = sim.u_aura[0]
			ev["foot_aura_out"] = sim.u_aura[2]
		if snap_check and sim.tick == 150:
			snap_bad += _snap_diverges(sim, sc, 901, 200)
			snaps += 1
	ev["foot_kills_in"] = sim.u_kills[0]
	ev["foot_kills_out"] = sim.u_kills[2]
	ev["foot_mor_in"] = sim.u_morale[0]
	ev["foot_mor_out"] = sim.u_morale[2]
	ev["foot_hits"] = sim.stat_ch_hit
	ev["foot_hit_pct_in"] = sim.stat_ch_rolls[3] * 100 / maxi(sim.stat_ch_rolls[2], 1)
	ev["foot_hit_pct_out"] = sim.stat_ch_rolls[1] * 100 / maxi(sim.stat_ch_rolls[0], 1)
	# A2: range and accuracy. Archers 148 m from light infantry: the ones by
	# the missile hero (154 m) shoot, the others (140 m) cannot.
	sc = _chars_sc([
		Scenarios.unit(0, UT.ARCHER, 80, 100, 300, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.LIGHT, 60, 100, 150, Scenarios.FACE_DOWN),
		Scenarios.unit(0, UT.ARCHER, 80, 300, 300, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.LIGHT, 60, 300, 150, Scenarios.FACE_DOWN)], [[_ch("hero_missile")], []])
	sim = BattleSim.new()
	sim.setup(sc, 902)
	var hm := _ch_unit(sim, 0, UT.CK_MISSILE)
	_ch_put(sim, hm, 100, 325)
	sim.queue_order(BattleSim.make_fire_order(1, hm, 0))
	sim.queue_order(BattleSim.make_fire_order(1, 1, 0))
	sim.queue_order(BattleSim.make_fire_order(1, 3, 0))
	for t in 300:
		sim.step()
		hashes.append(sim.state_hash())
		if sim.tick == 20:
			ev["mis_range_in"] = sim.mrange(0) / M
			ev["mis_range_out"] = sim.mrange(2) / M
	ev["mis_shots"] = sim.stat_ch_rng
	ev["mis_kills_in"] = sim.u_kills[0]
	ev["mis_kills_out"] = sim.u_kills[2]
	# A3: charge. Two cavalry units charge two light infantry units; the
	# horse hero rides in with the left ones.
	sc = _chars_sc([
		Scenarios.unit(0, UT.CAVALRY, 40, 100, 300, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.LIGHT, 60, 100, 200, Scenarios.FACE_DOWN),
		Scenarios.unit(0, UT.CAVALRY, 40, 300, 300, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.LIGHT, 60, 300, 200, Scenarios.FACE_DOWN)], [[_ch("hero_cav")], []])
	sim = BattleSim.new()
	sim.setup(sc, 903)
	var hc := _ch_unit(sim, 0, UT.CK_CAV)
	_ch_put(sim, hc, 100, 318)
	sim.queue_order(BattleSim.make_attack_order(1, 0, 1, 1))
	sim.queue_order(BattleSim.make_attack_order(1, 2, 3, 1))
	sim.queue_order(BattleSim.make_attack_order(1, hc, 1, 1))
	for t in 250:
		sim.step()
		hashes.append(sim.state_hash())
		if sim.tick == 10:
			ev["cav_aura_in"] = sim.u_aura[0]
			ev["cav_aura_out"] = sim.u_aura[2]
	ev["cav_bonus_impacts"] = sim.stat_ch_mom
	ev["cav_impacts"] = sim.stat_impacts
	ev["cav_kills_in"] = sim.u_kills[0]
	ev["cav_kills_out"] = sim.u_kills[2]
	# A4: the siege hero (the whole side): a battery of ours and one of
	# theirs shoot heavy infantry for 60 s; ours with the engineer reloads
	# faster (and the climb / batter factors for the side).
	sc = _chars_sc([
		Scenarios.unit(0, UT.BOLT, 16, 100, 330, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.HEAVY, 100, 100, 150, Scenarios.FACE_DOWN),
		Scenarios.unit(1, UT.BOLT, 16, 300, 70, Scenarios.FACE_DOWN),
		Scenarios.unit(0, UT.HEAVY, 100, 300, 250, Scenarios.FACE_UP)], [[_ch("hero_siege")], []])
	sim = BattleSim.new()
	sim.setup(sc, 904)
	for u in [1, 3]:
		sim.queue_order(BattleSim.make_halt_order(1, u))
	for t in 600:
		sim.step()
		hashes.append(sim.state_hash())
		if sim.tick == 20:
			ev["sg_side"] = "%d/%d" % [sim.ch_sg[0], sim.ch_sg[1]]
	ev["sg_fired_in"] = 4 * UT.stat(UT.BOLT, "m_ammo") - sim.u_ammo[0]
	ev["sg_fired_out"] = 4 * UT.stat(UT.BOLT, "m_ammo") - sim.u_ammo[2]
	ev["sg_climb"] = "%d/%d" % [sim.climb_pct(0), sim.climb_pct(1)]
	ev["sg_reload"] = "%d/%d" % [sim.reload_pct(0), sim.reload_pct(1)]
	ev["sg_batter"] = "%d/%d" % [sim.batter_pct(0), sim.batter_pct(1)]
	# B: a champion cut down by heavy infantry: his side near him (within
	# 60 m) and far, the enemy near and far.
	sc = _chars_sc([
		Scenarios.unit(0, UT.HEAVY, 100, 120, 260, Scenarios.FACE_UP),
		Scenarios.unit(0, UT.HEAVY, 100, 360, 330, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.HEAVY, 100, 150, 180, Scenarios.FACE_DOWN),
		Scenarios.unit(1, UT.HEAVY, 100, 360, 60, Scenarios.FACE_DOWN)], [[_ch("hero_foot")], []])
	sim = BattleSim.new()
	sim.setup(sc, 905)
	hf = _ch_unit(sim, 0, UT.CK_FOOT)
	_ch_put(sim, hf, 150, 215)
	sim.queue_order(BattleSim.make_attack_order(1, 2, hf, 0))
	var pm := PackedInt32Array([0, 0, 0, 0])
	ev["fall_t"] = -1
	for t in 1500:
		for k in 4:
			pm[k] = sim.u_morale[k]
		sim.step()
		hashes.append(sim.state_hash())
		if int(ev["fall_t"]) < 0 and sim.stat_ch_fall > 0:
			ev["fall_t"] = sim.tick
			ev["fall_near"] = pm[0] - sim.u_morale[0]
			ev["fall_far"] = pm[1] - sim.u_morale[1]
			ev["fall_enemy_near"] = sim.u_morale[2] - pm[2]
			ev["fall_enemy_far"] = sim.u_morale[3] - pm[3]
			var rr: Dictionary = sim.result()
			ev["fall_row"] = "char %d alive %d" % [int(rr["units"][hf].get("char", 0)), int(rr["units"][hf].get("alive", -1))]
			break
		if snap_check and sim.tick == 60:
			snap_bad += _snap_diverges(sim, sc, 905, 300)
			snaps += 1
	# C: the assassin hidden: archers firing at will 100 m off do not see him
	# (no target in the sim's or the AI's lists) until he walks within 10 m.
	sc = _chars_sc([
		Scenarios.unit(0, UT.HEAVY, 60, 380, 380, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.ARCHER, 80, 150, 150, Scenarios.FACE_DOWN)], [[_ch("assassin")], []])
	sim = BattleSim.new()
	sim.setup(sc, 906)
	var asn := _ch_unit(sim, 0, UT.CK_ASSASSIN)
	_ch_put(sim, asn, 150, 250)
	sim.queue_order(BattleSim.make_move_order(100, asn, 150 * M, 159 * M, Scenarios.FACE_UP, 1 * M, 1))
	ev["seen_t"] = -1
	for t in 500:
		sim.step()
		hashes.append(sim.state_hash())
		if sim.tick == 50:
			ev["hid_hidden"] = sim.u_hidden[asn]
			ev["hid_ai_nearest"] = BattleAI._nearest_enemy(sim, 1, false)
			ev["hid_fire"] = sim.u_ftarget[1]
		if int(ev["seen_t"]) < 0 and sim.u_hidden[asn] == 0:
			ev["seen_t"] = sim.tick
		if int(ev["seen_t"]) >= 0 and sim.tick == int(ev["seen_t"]) + 10:
			ev["seen_ai_nearest"] = BattleAI._nearest_enemy(sim, 1, false)
			ev["seen_fire"] = sim.u_ftarget[1]
	# D: sabotage: the assassin walks to their battery (its crews shooting at
	# our heavy infantry far off) and wrecks its engines.
	sc = _chars_sc([
		Scenarios.unit(0, UT.HEAVY, 60, 300, 350, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.BOLT, 16, 120, 120, Scenarios.FACE_DOWN)], [[_ch("assassin")], []])
	sim = BattleSim.new()
	sim.setup(sc, 907)
	asn = _ch_unit(sim, 0, UT.CK_ASSASSIN)
	_ch_put(sim, asn, 60, 160)
	sim.queue_order(BattleSim.make_sabotage_order(1, asn, 0))
	ev["sab_refusal_own"] = BattleSim.char_refusal(sim, {"type": BattleSim.ORDER_SABOTAGE, "unit": 1, "eg": 0})
	for t in 900:
		sim.step()
		hashes.append(sim.state_hash())
		if snap_check and sim.tick == 100:
			snap_bad += _snap_diverges(sim, sc, 907, 400)
			snaps += 1
	ev["sab_wrecked"] = sim.stat_sabotage
	ev["sab_engines"] = sim.eg_ne[0]
	ev["sab_alive"] = sim.u_alive[asn]
	ev["sab_captured"] = sim.stat_captured
	# E: a shut gate unbarred from inside: the attackers' assassin walks to
	# its outer face, over the wall beside it, and unbars it.
	sc = _scenario("gate_ops")
	sc["chars"] = [[_ch("assassin")], []]
	sim = BattleSim.new()
	sim.setup(sc, 908)
	asn = _ch_unit(sim, 0, UT.CK_ASSASSIN)
	var gq := 1  # (the north-west gate: away from the defenders' spearmen)
	for u in sim.n_units:
		if sim.u_side[u] == 1 and UT.cls(sim.u_type[u]) == UT.CLS_MISSILE:
			var fo := BattleSim.make_fire_order(1, u, 0)  # (their archers hold their fire)
			fo["player"] = 51
			sim.queue_order(fo)
	ev["gate"] = gq
	ev["gate_open_t"] = -1
	if gq >= 0:
		sim.queue_order(BattleSim.make_sabotage_order(1, asn, -1, gq))
		for t in 1500:
			sim.step()
			hashes.append(sim.state_hash())
			if snap_check and sim.tick == 200:
				snap_bad += _snap_diverges(sim, sc, 908, 300)
				snaps += 1
			if int(ev["gate_open_t"]) < 0 and sim.g_state[gq] == BattleSim.GATE_OPEN:
				ev["gate_open_t"] = sim.tick
				break
	ev["gate_over"] = sim.stat_ch_over
	ev["gate_unbar"] = sim.stat_ch_unbar
	ev["gate_alive"] = sim.u_alive[asn]
	# F: attempts on a general's unit standing behind its line (a seed each).
	var outs := []
	for sd in 8:
		sc = _chars_sc([
			Scenarios.unit(1, UT.index_of("general"), 30, 200, 120, Scenarios.FACE_DOWN),
			Scenarios.unit(1, UT.HEAVY, 100, 200, 160, Scenarios.FACE_DOWN),
			Scenarios.unit(0, UT.HEAVY, 100, 200, 300, Scenarios.FACE_UP)], [[_ch("assassin")], []])
		sim = BattleSim.new()
		sim.setup(sc, 910 + sd)
		asn = _ch_unit(sim, 0, UT.CK_ASSASSIN)
		_ch_put(sim, asn, 150, 112)
		sim.queue_order(BattleSim.make_attempt_order(1, asn, 0))
		for t in 300:
			sim.step()
			hashes.append(sim.state_hash())
			if sim.u_chk[asn] != 0 and (sim.u_chf[asn] & BattleSim.CHF_TRIED) != 0:
				break
		outs.append("%d:%s" % [sim.u_chk[asn], "gone" if sim.u_cmdgone[0] != 0 else "led"])
	ev["attempts"] = " ".join(outs)
	# G: parleys: their light infantry breaks (morale 0) beside our
	# diplomat; he walks up, it stands for 5 s, then it surrenders or not
	# (the first seed of each).
	ev["parley_ok_seed"] = -1
	ev["parley_fail_seed"] = -1
	for sd in 12:
		sc = _chars_sc([
			Scenarios.unit(0, UT.HEAVY, 100, 200, 330, Scenarios.FACE_UP),
			Scenarios.unit(1, UT.LIGHT, 60, 200, 200, Scenarios.FACE_DOWN)], [[_ch("diplomat")], []])
		sim = BattleSim.new()
		sim.setup(sc, 930 + sd)
		var dip := _ch_unit(sim, 0, UT.CK_DIPLOMAT)
		_ch_put(sim, dip, 235, 190)
		sim.u_morale[1] = 0
		sim.step()
		var ref := BattleSim.char_refusal(sim, BattleSim.make_parley_order(sim.tick, dip, 1))
		sim.queue_order(BattleSim.make_parley_order(sim.tick, dip, 1))
		var held := 0
		for t in 400:
			sim.step()
			hashes.append(sim.state_hash())
			if sim.u_hold[1] >= sim.tick:
				held += 1
			if sim.stat_parley_ok + sim.stat_parley_fail > 0:
				break
		if sim.stat_parley_ok > 0 and int(ev["parley_ok_seed"]) < 0:
			var rr: Dictionary = sim.result()
			ev["parley_ok_seed"] = 930 + sd
			ev["parley_ok"] = "refusal '%s' held %d prisoners %d row surrendered %d state %d sides %s" % [ref, held,
				sim.ch_pris[0], int(rr["units"][1].get("surrendered", -1)), int(rr["units"][1]["state"]),
				str([int(rr["sides"][0].get("prisoners", -1)), int(rr["sides"][1].get("surrendered", -1))])]
			ev["parley_men"] = int(rr["units"][1]["started"]) - int(rr["units"][1]["killed"])
		elif sim.stat_parley_fail > 0 and int(ev["parley_fail_seed"]) < 0:
			ev["parley_fail_seed"] = 930 + sd
			ev["parley_fail"] = "held %d prisoners %d wait %d state %d" % [held, sim.ch_pris[0],
				sim.u_chcd[dip] - sim.tick, sim.u_state[1]]
		if int(ev["parley_ok_seed"]) >= 0 and int(ev["parley_fail_seed"]) >= 0:
			break
	# H: the AI's characters (docs/AI.md 26): battle_2000, a general and the
	# six characters a side, both Average, then both Skilled.
	var all6 := []
	for key in ["hero_foot", "hero_missile", "hero_cav", "hero_siege", "assassin", "diplomat"]:
		all6.append(_ch(key))
	for lvl in [AIP.AVERAGE, AIP.SKILLED]:
		var sc4: Dictionary = Scenarios.make("battle_2000")
		sc4["ai_sides"] = [0, 1]
		sc4["ai_skill"] = [lvl, lvl]
		sc4["terrain"] = {"kind": Terrain.K_FLAT}
		for sd in 2:
			sc4["units"].append(Scenarios.unit(sd, UT.index_of("general"), 30, 280, 420 if sd == 0 else 140,
				Scenarios.FACE_UP if sd == 0 else Scenarios.FACE_DOWN))
		sc4["chars"] = [all6, all6]
		var s4 := BattleSim.new()
		s4.setup(sc4, 940)
		var tag := "avg" if lvl == AIP.AVERAGE else "sk"
		var behind := 0
		var ahead := 0
		var attack := 0
		for t in 1800:
			s4.step()
			hashes.append(s4.state_hash())
			if snap_check and lvl == AIP.AVERAGE and s4.tick == 900:
				snap_bad += _snap_diverges(s4, sc4, 940, 200)
				snaps += 1
			if s4.tick % 100 != 0:
				continue
			for u in s4.n_units:
				if s4.u_char[u] < UT.CK_FOOT or s4.u_char[u] > UT.CK_SIEGE or s4.u_state[u] != BattleSim.U_READY:
					continue
				if s4.u_order[u] == BattleSim.O_ATTACK:
					attack += 1
				# Behind or ahead of his own foot line's mean depth.
				var sd: int = s4.u_side[u]
				var ly := 0
				var ln := 0
				for o in s4.n_units:
					if s4.u_side[o] == sd and s4.u_state[o] == BattleSim.U_READY and s4.u_char[o] == 0 \
							and (s4.u_cls[o] == UT.CLS_INF or s4.u_cls[o] == UT.CLS_PIKE):
						ly += s4.u_cy[o]
						ln += 1
				if ln > 0:
					var dep: int = (s4.u_cy[u] - ly / ln) * (1 if sd == 0 else -1)
					if dep > 0:
						behind += 1
					elif dep < -10 * M:
						ahead += 1
		var heroes_alive := 0
		for u in s4.n_units:
			if s4.u_char[u] >= UT.CK_FOOT and s4.u_char[u] <= UT.CK_SIEGE and s4.u_alive[u] > 0:
				heroes_alive += 1
		ev[tag + "_ai"] = "behind %d ahead %d attack-orders %d heroes alive %d/8 attempts %d parleys %d ok %d fail %d prisoners %d/%d falls %d winner %d" % [
			behind, ahead, attack, heroes_alive,
			s4.stat_aic[AIP.C_CH_ATTEMPT] + s4.stat_aic[AIP.N_COUNTERS + AIP.C_CH_ATTEMPT],
			s4.stat_aic[AIP.C_CH_PARLEY] + s4.stat_aic[AIP.N_COUNTERS + AIP.C_CH_PARLEY],
			s4.stat_parley_ok, s4.stat_parley_fail, s4.ch_pris[0], s4.ch_pris[1], s4.stat_ch_fall, s4.winner]
		ev[tag + "_attempts"] = s4.stat_aic[AIP.C_CH_ATTEMPT] + s4.stat_aic[AIP.N_COUNTERS + AIP.C_CH_ATTEMPT]
		ev[tag + "_parleys"] = s4.stat_aic[AIP.C_CH_PARLEY] + s4.stat_aic[AIP.N_COUNTERS + AIP.C_CH_PARLEY]
		ev[tag + "_behind"] = behind
		ev[tag + "_ahead"] = ahead
		ev[tag + "_attack"] = attack
	return {"hashes": hashes, "ev": ev, "snap_bad": snap_bad, "snaps": snaps}


func _check_chars() -> void:
	var a := _chars_run(true)
	var b := _chars_run(false)
	var ev: Dictionary = a["ev"]
	print("  chars: %s" % str(ev))
	if a["hashes"] != b["hashes"] or str(ev) != str(b["ev"]):
		_fail("chars: the repeat diverged")
	if int(a["snap_bad"]) != 0:
		_fail("chars: a restored copy diverged (%d)" % int(a["snap_bad"]))
	if int(a["snaps"]) < 5:
		_fail("chars: only %d snapshot checks ran" % int(a["snaps"]))
	if int(ev["foot_aura_in"]) != BattleSim.AU_FOOT or int(ev["foot_aura_out"]) != 0 \
			or int(ev["foot_hit_pct_in"]) <= int(ev["foot_hit_pct_out"]) or int(ev["foot_mor_in"]) <= int(ev["foot_mor_out"]):
		_fail("chars: the champion's aura (to-hit, morale) did not tell (%s)" % str(ev))
	if int(ev["mis_range_in"]) != 154 or int(ev["mis_range_out"]) != 140 or int(ev["mis_kills_in"]) <= 0 \
			or int(ev["mis_kills_out"]) != 0 or int(ev["mis_shots"]) <= 0:
		_fail("chars: the missile hero's range / accuracy did not tell (%s)" % str(ev))
	if int(ev["cav_aura_in"]) != BattleSim.AU_CAV or int(ev["cav_aura_out"]) != 0 or int(ev["cav_bonus_impacts"]) <= 0:
		_fail("chars: the horse hero's charge bonus did not tell (%s)" % str(ev))
	if str(ev["sg_side"]) != "1/0" or int(ev["sg_fired_in"]) <= int(ev["sg_fired_out"]) or str(ev["sg_climb"]) != "80/100" \
			or str(ev["sg_reload"]) != "83/100" or str(ev["sg_batter"]) != "75/100":
		_fail("chars: the siege hero's side effects did not tell (%s)" % str(ev))
	if int(ev["fall_t"]) < 0 or absi(int(ev["fall_near"]) - 120) > 10 or absi(int(ev["fall_far"])) > 5 \
			or absi(int(ev["fall_enemy_near"]) - 60) > 10 or absi(int(ev["fall_enemy_far"])) > 5 \
			or str(ev["fall_row"]) != "char 1 alive 0":
		_fail("chars: the champion's fall did not strike as it should (%s)" % str(ev))
	if int(ev["hid_hidden"]) != 1 or int(ev["hid_ai_nearest"]) == 2 or int(ev["hid_fire"]) != -1 \
			or int(ev["seen_t"]) < 0 or int(ev.get("seen_ai_nearest", -1)) != 2 or int(ev.get("seen_fire", -1)) != 2:
		_fail("chars: the hidden assassin was seen, or never (%s)" % str(ev))
	if int(ev["sab_wrecked"]) <= 0:
		_fail("chars: the assassin wrecked no engine (%s)" % str(ev))
	if int(ev["gate_open_t"]) < 0 or int(ev["gate_unbar"]) != 1 or int(ev["gate_over"]) != 1:
		_fail("chars: the gate was not unbarred from inside (%s)" % str(ev))
	var att_s := str(ev["attempts"])
	var kinds := 0
	for c in ["1:", "2:", "3:"]:
		if att_s.find(c) >= 0:
			kinds += 1
	if kinds < 2 or att_s.find("1:led") >= 0 or att_s.find("2:gone") >= 0 or att_s.find("3:gone") >= 0:
		_fail("chars: the attempts' outcomes are wrong (%s)" % att_s)
	if int(ev["parley_ok_seed"]) < 0 or int(ev["parley_fail_seed"]) < 0 or int(ev.get("parley_men", 0)) != 60 \
			or str(ev.get("parley_ok", "")).find("prisoners 60 row surrendered 60 state 3 sides [60, 60]") < 0:
		_fail("chars: the parleys did not end as they should (%s)" % str(ev))
	if int(ev["avg_attack"]) != 0 or int(ev["sk_attack"]) != 0 or int(ev["avg_behind"]) <= int(ev["avg_ahead"]) \
			or int(ev["avg_attempts"]) != 0 or int(ev["avg_parleys"]) <= 0:
		_fail("chars: the AI's characters misbehaved (%s / %s)" % [str(ev["avg_ai"]), str(ev["sk_ai"])])
	if not _ok:
		return
	print("PASS chars (auras): champion: to-hit %d %% in his aura against %d %% out, morale %d against %d after 40 s, kills %d / %d; missile hero: range %d m against %d, %d shots aimed by him, kills at 148 m %d / %d; horse hero: %d of %d impacts with his bonus, kills %d / %d; engineer (the side): bolts fired in 60 s %d against %d, ladder ticks %s %%, reload work %s %%, ram / tower battering %s %%" % [
		int(ev["foot_hit_pct_in"]), int(ev["foot_hit_pct_out"]), int(ev["foot_mor_in"]), int(ev["foot_mor_out"]),
		int(ev["foot_kills_in"]), int(ev["foot_kills_out"]), int(ev["mis_range_in"]), int(ev["mis_range_out"]),
		int(ev["mis_shots"]), int(ev["mis_kills_in"]), int(ev["mis_kills_out"]), int(ev["cav_bonus_impacts"]),
		int(ev["cav_impacts"]), int(ev["cav_kills_in"]), int(ev["cav_kills_out"]), int(ev["sg_fired_in"]),
		int(ev["sg_fired_out"]), str(ev["sg_climb"]), str(ev["sg_reload"]), str(ev["sg_batter"])])
	print("PASS chars (fall, agents): the champion fell at tick %d: his side near -%d, far -%d, the enemy near +%d, far +%d (%s); the assassin hidden (AI nearest %d, fire target %d) until seen at tick %d (AI nearest %d, fire target %d); sabotage wrecked %d of %d engines; gate %d unbarred from inside at tick %d; attempts by seed %s; parley seed %d: %s; seed %d: %s" % [
		int(ev["fall_t"]), int(ev["fall_near"]), int(ev["fall_far"]), int(ev["fall_enemy_near"]), int(ev["fall_enemy_far"]),
		str(ev["fall_row"]), int(ev["hid_ai_nearest"]), int(ev["hid_fire"]), int(ev["seen_t"]), int(ev["seen_ai_nearest"]),
		int(ev["seen_fire"]), int(ev["sab_wrecked"]), int(ev["sab_engines"]), int(ev["gate"]), int(ev["gate_open_t"]),
		att_s, int(ev["parley_ok_seed"]), str(ev["parley_ok"]), int(ev["parley_fail_seed"]), str(ev["parley_fail"])])
	print("PASS chars (AI): Average %s; Skilled %s; identical on repeat and across %d snapshot / restore checks" % [
		str(ev["avg_ai"]), str(ev["sk_ai"]), int(a["snaps"])])
