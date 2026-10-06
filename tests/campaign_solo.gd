extends SceneTree
## Scripted solo campaign: a human faction played by a simple policy for N
## turns, every pending battle auto-resolved with the real battle sim (AI vs
## AI, as the game's Auto-resolve does), checking the state stays consistent
## (sieges included: the policy lays siege when weaker and storms when the
## odds turn).
##   godot --headless --script res://tests/campaign_solo.gd [-- --turns=20 --faction=rome --seed=5]

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const CAI := preload("res://campaign/cai.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const UT := preload("res://sim/unit_types.gd")

var turns := 20
var faction := "rome"
var seed_v := 5
var fails := 0


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--turns="):
			turns = int(a.get_slice("=", 1))
		elif a.begins_with("--faction="):
			faction = a.get_slice("=", 1)
		elif a.begins_with("--seed="):
			seed_v = int(a.get_slice("=", 1))
	var f := CData.faction_index(faction)
	var st := CState.new_campaign("solo", seed_v, [f])
	var battles := 0
	var won := 0
	var sim_ms := 0
	for t in turns:
		st = CTurn.resolve_turn(st, [CTurn.submission(st, f, _plan(st, f))])
		while str(st["phase"]) == "battles":
			var b: Dictionary = CTurn.pending_for(st)[0]
			var t0 := Time.get_ticks_msec()
			var built := CBattle.build(st, b, -1, 50)
			var sim := BattleSim.new()
			sim.setup(built["scenario"], int(built["seed"]))
			while sim.ended == 0 and sim.tick < 12000:
				sim.step()
			sim_ms += Time.get_ticks_msec() - t0
			var out := CBattle.outcome_from_result(built, sim.result(), "auto")
			var facs := CRules.battle_factions(st, b)
			var mine := 0 if facs[0].has(f) else 1
			battles += 1
			if int(out["winner"]) == mine:
				won += 1
			st = CTurn.apply_battle(st, int(b["id"]), out)
		_consistency(st, t)
		if str(st["phase"]) == "over":
			break
		print("turn %2d  %s: %d regions, %d armies, %d units, treasury %d | battles so far %d (won %d)" % [
			int(st["turn"]), CData.faction_name(f), CState.regions_of(st, f).size(), CState.armies_of(st, f).size(),
			_units(st, f), int(st["factions"][f]["treasury"]), battles, won])
	var nsg := 0
	var nsur := 0
	for e in st["events"]:
		nsg += 1 if str(e["k"]) == "siege" else 0
		nsur += 1 if str(e.get("how", "")) == "surrendered" else 0
	print("sieges in the last two turns' events: %d started, %d surrendered; open now: %d" % [nsg, nsur, (st.get("sieges", []) as Array).size()])
	var back := CState.from_json(CState.to_json(st))
	_check(CState.state_hash(back) == CState.state_hash(st), "final state survives a JSON round trip")
	print("auto-resolved %d battles (half-size units) in %.1f s of sim" % [battles, sim_ms / 1000.0])
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


func _units(st: Dictionary, f: int) -> int:
	var n := 0
	for a in CState.armies_of(st, f):
		n += CState.unit_count(a)
	return n


## Policy: build the cheapest thing in each region, recruit the best melee
## unit available while upkeep stays below 70% of income, attack the most
## valuable neighbour (independents first) when 1.4 times its defence (lay
## siege at 0.7 times), storm a siege when the odds reach 55%. Format 5:
## targets it reaches this turn; the checks allow raiding armies and check
## points and stances.
func _plan(st: Dictionary, f: int) -> Array:
	var orders: Array = []
	var ps := CState.copy(st)
	for r in CState.regions_of(ps, f):
		for c in [CData.BARRACKS, CData.FARM, CData.MARKET, CData.WALLS]:
			var o := {"t": "build", "r": r, "chain": c}
			if CRules.apply_order(ps, f, o) == "":
				orders.append(o)
				break
	var inc := int(CRules.income(ps, f)["total"])
	for r in CState.regions_of(ps, f):
		for line in ["heavy", "spear", "pike", "light", "cav", "javelin"]:
			for tier in [3, 2, 1]:
				var key := CState.roster_type(f, line, tier)
				if key == "" or CRules.recruit_check(ps, f, r, key) != "":
					continue
				if CRules.upkeep(ps, f) + CState.upkeep_of(UT.index_of(key)) > inc * 70 / 100:
					continue
				var o := {"t": "recruit", "r": r, "unit": key}
				if CRules.apply_order(ps, f, o) == "":
					orders.append(o)
				break
	for sg in ps.get("sieges", []):
		var r := int(sg["r"])
		if CRules.can_assault(ps, f, r) == "" and int(CBattle.odds(ps, CRules.besiegers(ps, r), CRules.besieged_armies(ps, r), r, true)["win"]) >= 55:
			orders.append({"t": "assault", "r": r})
	for a in CState.armies_of(ps, f):
		if int(a["busy"]) != 0 or CRules.siege_role(ps, a) != 0:
			continue
		var best := -1
		var best_v := 0
		var best_mode := CData.MODE_ASSAULT
		for t in CRules.move_targets(ps, a, true):
			if not CState.at_war(ps, f, CState.owner(ps, t)):
				continue
			var d := CAI.target_defence(ps, f, t)
			if CState.strength(a) * 100 < d * 70:
				continue
			var v := CAI.region_value(ps, t) * 1000 / maxi(d, 1)
			if v > best_v:
				best_v = v
				best = t
				best_mode = CData.MODE_ASSAULT if CState.strength(a) * 100 >= d * 140 else CData.MODE_SIEGE
		if best >= 0:
			orders.append({"t": "move", "army": int(a["id"]), "to": best, "mode": best_mode})
	return orders


func _consistency(st: Dictionary, t: int) -> void:
	var ok := true
	var ids := {}
	for a in st["armies"]:
		var id := int(a["id"])
		if ids.has(id):
			ok = false
			printerr("  duplicate army id %d" % id)
		ids[id] = 1
		if CState.unit_count(a) == 0 or CState.unit_count(a) > CData.ARMY_MAX:
			ok = false
			printerr("  army %d has %d units" % [id, CState.unit_count(a)])
		for u in a["units"]:
			if int(u["n"]) <= 0 or int(u["n"]) > UT.size_of(CState.unit_type(u)):
				ok = false
				printerr("  army %d unit with %d men" % [id, int(u["n"])])
		if CState.moves_on(st):
			if int(a.get("mp", -1)) != CState.max_mp(a) and str(st["phase"]) == "plan" and int(a["moved"]) == 0:
				ok = false
				printerr("  army %d starts the turn with %d of %d points" % [id, int(a.get("mp", -1)), CState.max_mp(a)])
			if CState.stance(a) == CData.STANCE_GARRISON and not CState.friendly(st, int(a["f"]), CState.owner(st, int(a["r"]))):
				ok = false
				printerr("  army %d inside the walls of a hostile settlement" % id)
		var o := CState.owner(st, int(a["r"]))
		var raiding := CState.moves_on(st) and CState.at_war(st, int(a["f"]), o)
		if not CState.friendly(st, int(a["f"]), o) and CState.battle_at(st, int(a["r"])).is_empty() and CRules.siege_role(st, a) != 1 \
				and not raiding:
			ok = false
			printerr("  army %d of %s stands in %s's region %d without a battle" % [id, a["f"], o, int(a["r"])])
		if not CState.alive(st, int(a["f"])):
			ok = false
	for sg in st.get("sieges", []):
		if CRules.besiegers(st, int(sg["r"])).is_empty() or CState.friendly(st, int(sg["f"]), CState.owner(st, int(sg["r"]))):
			ok = false
			printerr("  siege of region %d without besiegers or of a friendly city" % int(sg["r"]))
	if not (st["battles"] as Array).is_empty() and str(st["phase"]) == "plan":
		ok = false
		printerr("  battles left in phase plan")
	for r in CData.region_count():
		var rs: Dictionary = st["regions"][r]
		if (rs["slots"] as Array).size() > CState.slot_count(r, int(rs["level"])) + 1:
			ok = false
			printerr("  region %d has too many buildings" % r)
	_check(ok, "state consistent after turn %d" % t)


func _check(cond: bool, what: String) -> void:
	if not cond:
		printerr("FAIL ", what)
		fails += 1
