extends SceneTree
## Story campaigns (campaign/cstory.gd, the script campaign/data/story_brethren.gd).
##   godot --headless --script res://tests/story_test.gd [-- --turns=15 --seeds=4]
## The start, the prologue played deterministically for scripted choices
## (twice the same, a JSON round trip on the way), triggers firing at their
## thresholds, a choice's effects, a story battle and its follow-up, the
## turn held while a choice waits, and normal campaigns unchanged by any of
## it. Then a headless run of the prologue and Act 1 with random choices
## (several seeds) that must reach the end of Act 1 without errors.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CRules := preload("res://campaign/crules.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CSea := preload("res://campaign/csea.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CStory := preload("res://campaign/cstory.gd")
const CCaptain := preload("res://campaign/ccaptain.gd")

var fails := 0
var turns := 15
var seeds := 4


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--turns="):
			turns = int(a.get_slice("=", 1))
		elif a.begins_with("--seeds="):
			seeds = int(a.get_slice("=", 1))
	var west0 := _west_hash()
	var rome0 := _rome_hash()
	_start()
	_scripted()
	_triggers()
	_effects()
	_battles()
	_blocked()
	_random_runs()
	_check(_west_hash() == west0 and _rome_hash() == rome0, "normal West and Rome campaigns unchanged after stories ran (%s, %s)" % [west0, rome0])
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok   ", what)
	else:
		fails += 1
		print("FAIL ", what)


## A West campaign, AI only, 8 turns: its hash (no story keys anywhere).
func _west_hash() -> String:
	var st := CState.new_campaign("w", 77, [], {}, [], "west")
	for t in 8:
		st = CTurn.resolve_turn(st, [])
	_check(not st.has("story") and CData.year_shift == 0, "a West campaign has no story and the pack's calendar")
	return CState.hash_text(st)


func _rome_hash() -> String:
	var st := CState.new_campaign("r", 4242, [])
	for t in 6:
		st = CTurn.resolve_turn(st, [])
	return CState.hash_text(st)


func _new(sd: int = 5) -> Dictionary:
	return CStory.new_story("Story", sd)


func _pf(st: Dictionary) -> int:
	return CStory.player(st)


## Answer the first pending choice of the captain with choice k (-1: the
## first one allowed). Returns the new state.
func _answer(st: Dictionary, k: int = -1) -> Dictionary:
	var pe: Array = CStory.pending_for(st, _pf(st))
	if pe.is_empty():
		return st
	var pid := int(pe[0]["id"])
	if k < 0:
		var n := (CStory.event_def(st, str(pe[0]["e"]))["choices"] as Array).size()
		for i in n:
			if CStory.answer_check(st, _pf(st), pid, i) == "":
				k = i
				break
	return CStory.answer(st, _pf(st), pid, k)


## Every pending battle by the formula.
func _battles_formula(st: Dictionary) -> Dictionary:
	for guard in 10:
		var pb := CTurn.pending_for(st)
		if pb.is_empty():
			break
		st = CTurn.apply_battle(st, int(pb[0]["id"]), CBattle.formula(st, pb[0]))
	return st


func _log_ids(st: Dictionary) -> Array:
	var out: Array = []
	for e in CStory.S(st)["log"]:
		out.append(str(e["e"]))
	return out


func _start() -> void:
	var st := _new()
	var pf := _pf(st)
	_check(st.has("story") and str(st.get("pack", "")) == "west" and pf == CData.faction_index("brethren")
		and (st["humans"] as Array) == [pf], "a story campaign: the West pack, the Brethren played")
	_check(CState.regions_of(st, pf).size() == 1 and CState.owner(st, CData.region_index("port_de_paix")) == pf
		and CState.owner(st, CData.region_index("trujillo")) == -1, "the Brethren hold only Tortuga (Port-de-Paix)")
	var fl := CStory.flagship(st, pf)
	_check(CFleet.fleets_of(st, pf).size() == 1 and (fl["ships"] as Array).size() == 1 and str(fl["ships"][0]["t"]) == "sloop"
		and (fl["carry"] as Array).size() == 1 and CState.armies_of(st, pf).is_empty(), "one battered sloop with a company aboard, no army ashore")
	var pr := CGrid.site(CData.region_index("port_royal"))
	_check(CGrid.cheb(CFleet.cell(fl), pr) <= 6, "the sloop starts off Port Royal (%d cells)" % CGrid.cheb(CFleet.cell(fl), pr))
	var g := CStory.actor_fleet(st, "guarda")
	var ar := CStory.actor_fleet(st, "armada")
	_check(not g.is_empty() and str(g["sto"]) == "guarda" and int(g["f"]) == CData.faction_index("new_spain")
		and CGrid.cheb(CFleet.cell(g), CFleet.cell(fl)) <= 10 and CFleet.cell(g) % CGrid.width() > CFleet.cell(fl) % CGrid.width(),
		"the guardacosta waits to windward (east)")
	_check(not ar.is_empty() and (ar["ships"] as Array).size() == 3, "Mendoza's Armada lies at Havana")
	_check(_log_ids(st) == ["hanging"] and CStory.pending_for(st).size() == 1 and str(CStory.pending_for(st)[0]["e"]) == "chase",
		"turn 0: the hanging (news) and the chase (a choice)")
	_check(CData.date_text(0) == "1665 AD, summer", "the story's calendar starts in 1665 (%s)" % CData.date_text(0))
	_check(CStory.p(st, "purse") == 20 and CStory.attention(st) == 5, "the pressures start where the script says")
	var cap := CCaptain.of_fleet(st, int(fl["id"]))
	_check(not cap.is_empty() and str(cap["nm"]) == "The Captain", "the sloop sails under the player's captain")
	var j := CState.to_json(st)
	_check(not j.contains("true") and not j.contains("false") and CState.hash_text(CState.from_json(j)) == CState.hash_text(st),
		"the story state is plain JSON and round-trips")


## The prologue with fixed choices: run, raid the village, sail to Tortuga.
func _prologue(sd: int, round_trip: bool) -> Dictionary:
	var st := _new(sd)
	var pf := _pf(st)
	st = _answer(st, 0)  # run west
	for t in 4:
		if round_trip:
			st = CState.from_json(CState.to_json(st))
		st = _battles_formula(st)
		while CStory.blocked(st):
			var e := str(CStory.pending_for(st)[0]["e"])
			st = _answer(st, 1 if e == "hungry" else -1)
			st = _battles_formula(st)
		var orders: Array = []
		var fl := CStory.flagship(st, pf)
		if not fl.is_empty() and not fl.has("busy"):
			var dk := CFleet.dock(CData.region_index("port_de_paix"))
			orders.append({"t": "fmove", "fleet": int(fl["id"]), "x": CGrid.cx(dk), "y": CGrid.cy(dk), "persist": 1})
		st = CTurn.resolve_turn(st, [CTurn.submission(st, pf, orders)])
	return st


func _scripted() -> void:
	var a := _prologue(9, false)
	var b := _prologue(9, false)
	var c := _prologue(9, true)
	print("     prologue: %s, turn %d, log %s" % [CState.hash_text(a), int(a["turn"]), str(_log_ids(a))])
	_check(CState.hash_text(a) == CState.hash_text(b), "the prologue plays the same twice for the same choices")
	_check(CState.hash_text(a) == CState.hash_text(c), "... and the same through a JSON round trip each turn")
	_check(CStory.flag(a, "ran") and CStory.flag(a, "raided_village") and _log_ids(a).has("log_wind"),
		"the choices' flags and the wind's logbook page")
	_check(CStory.flag(a, "tortuga") and (_log_ids(a).has("tortuga") or not CStory.pending_for(a).is_empty()),
		"Tortuga reached in the prologue")
	_check(CSea.infamy(a, _pf(a)) > 5 and int(a["factions"][_pf(a)].get("plunder", 0)) >= 120, "the raid's infamy and plunder (%d, %d)" % [
		CSea.infamy(a, _pf(a)), int(a["factions"][_pf(a)].get("plunder", 0))])
	_check(CStory.actor(a, "guarda").is_empty(), "the guardacosta gave up the chase (back to Spain's AI)")


func _triggers() -> void:
	var st := _new()
	st = _answer(st, 0)
	var s := CStory.S(st)
	st["turn"] = 5
	s["fired"].append(["hungry", 1])
	(s["p"] as Dictionary)["purse"] = 39
	CStory.check(st)
	_check(not _has_pending(st, "grumble"), "no grumbling at purse 39")
	(s["p"] as Dictionary)["purse"] = 40
	CStory.check(st)
	_check(_has_pending(st, "grumble"), "grumbling at purse 40")
	(s["p"] as Dictionary)["purse"] = 90
	CStory.check(st)
	_check(_has_pending(st, "desertion") and _has_pending(st, "mutiny"), "desertion and the mutiny vote at purse 90")
	var n := (s["pending"] as Array).size()
	CStory.check(st)
	_check((s["pending"] as Array).size() == n, "a waiting event does not fire twice")
	# Purse rises a turn without plunder, falls with it.
	var st2 := _new()
	st2 = _answer(st2, 0)
	var p0 := CStory.p(st2, "purse")
	CStory.end_turn(st2)
	_check(CStory.p(st2, "purse") == p0 + 6, "the purse rises 6 a turn without plunder (%d -> %d)" % [p0, CStory.p(st2, "purse")])
	CSea.gain(st2, _pf(st2), 300)
	CStory.end_turn(st2)
	_check(CStory.p(st2, "purse") == p0 + 6 - 50 or CStory.p(st2, "purse") == 0, "plunder brings it down (300 / 6)")
	_check(CStory.p(st2, "owed") == 150, "half the plunder is owed in shares")
	# The attention threshold: Mendoza writes.
	var st3 := _new()
	st3 = _answer(st3, 0)
	CSea.add_infamy(st3, _pf(st3), 30)
	CStory.check(st3)
	_check(_has_pending(st3, "mendoza"), "Mendoza's letter at attention 30+")


func _has_pending(st: Dictionary, id: String) -> bool:
	for pe in CStory.pending_for(st):
		if str(pe["e"]) == id:
			return true
	return false


func _effects() -> void:
	var st := _new()
	var pf := _pf(st)
	st = _answer(st, 0)
	var s := CStory.S(st)
	s["sched"].append([0, "tortuga"])
	st["factions"][pf]["treasury"] = 500
	CStory.check(st)
	_check(_has_pending(st, "tortuga") and CStory.flag(st, "tortuga"), "a scheduled event fires (Tortuga)")
	var r := CData.region_index("port_de_paix")
	var pid := -1
	for pe in CStory.pending_for(st):
		if str(pe["e"]) == "tortuga":
			pid = int(pe["id"])
	var st2 := CStory.answer(st, pf, pid, 0)
	var n := 0
	for a in CState.armies_of(st2, pf):
		for u in a["units"]:
			if str(u["t"]) == "buccaneers" and CGrid.cheb(CState.cell(a), CGrid.site(r)) <= 1:
				n += 1
	_check(int(st2["factions"][pf]["treasury"]) == 400 and n == 2, "standing a round: -100 gold, two buccaneer companies at Tortuga")
	_check(int(st["factions"][pf]["treasury"]) == 500 and CState.armies_of(st, pf).is_empty(), "answer() is pure (the old state unchanged)")
	st["factions"][pf]["treasury"] = 50
	_check(CStory.answer_check(st, pf, pid, 0) != "" and CStory.answer_check(st, pf, pid, 2) == "", "a choice that needs gold is refused without it")
	_check(CStory.answer_check(st, pf + 1, pid, 2) != "", "another faction cannot answer")


func _battles() -> void:
	# Fight the guardacosta: a pending sea battle at once, then its follow-up.
	var st := _new(3)
	st = _answer(st, 1)
	var pb := CTurn.pending_for(st)
	_check(str(st["phase"]) == "battles" and pb.size() == 1 and pb[0].has("sea"), "come about and fight: a sea battle, now")
	st = CTurn.apply_battle(st, int(pb[0]["id"]), CBattle.formula(st, pb[0]))
	_check(CStory.flag(st, "won_guarda") or CStory.flag(st, "lost_guarda"), "the battle's result flags the story (%s)" % str(CStory.S(st)["flags"]))
	_check(_log_ids(st).has("won_guarda") or _log_ids(st).has("lost_guarda"), "and its follow-up is told at once")
	_check(str(st["phase"]) == "plan" or not CTurn.pending_for(st).is_empty(), "the phase goes back to planning")
	# The reprisal: Spain lands at Tortuga and storms it: a land battle.
	var s2 := _new(4)
	s2 = _answer(s2, 0)
	CStory.S(s2)["sched"].append([0, "reprisal"])
	CStory.check(s2)
	var lb := CTurn.pending_for(s2)
	_check(lb.size() == 1 and not lb[0].has("sea") and int(lb[0]["r"]) == CData.region_index("port_de_paix"), "the Spanish reprisal is a land battle at Tortuga")
	var info_before := (CStory.S(s2)["bt"] as Array).duplicate()
	s2["phase"] = "battles"
	s2 = CTurn.apply_battle(s2, int(lb[0]["id"]), CBattle.formula(s2, lb[0]))
	_check(not info_before.is_empty() and (CStory.flag(s2, "won_reprisal") or CStory.flag(s2, "lost_reprisal")), "its result is read back")


func _blocked() -> void:
	var st := _new()
	var t0 := CState.hash_text(st)
	var st2 := CTurn.resolve_turn(st, [])
	_check(int(st2["turn"]) == 0 and CState.hash_text(st2) == t0, "the turn does not resolve while a story choice waits")


## Prologue + Act 1 with random choices and a simple captain (sail for
## Tortuga, then the lair once hunting), every battle by the formula.
func _random_runs() -> void:
	for sd in seeds:
		var st := _new(100 + sd)
		var pf := _pf(st)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + sd
		var ok := true
		for t in turns:
			for guard in 20:
				st = _battles_formula(st)
				if not CStory.blocked(st):
					break
				var pe: Dictionary = CStory.pending_for(st)[0]
				var ch: Array = CStory.event_def(st, str(pe["e"]))["choices"]
				var allowed: Array = []
				for i in ch.size():
					if CStory.answer_check(st, pf, int(pe["id"]), i) == "":
						allowed.append(i)
				if allowed.is_empty():
					ok = false
					break
				st = CStory.answer(st, pf, int(pe["id"]), int(allowed[rng.randi() % allowed.size()]))
			st = _battles_formula(st)
			if str(st["phase"]) == "over":
				break
			var orders: Array = []
			var fl := CStory.flagship(st, pf)
			if not fl.is_empty() and not fl.has("busy") and not fl.has("dest_x"):
				var dk := CFleet.dock(CData.region_index("port_de_paix"))
				var bf := CStory.actor_fleet(st, "boucher")
				if CStory.flag(st, "hunt_boucher") and not bf.is_empty():
					dk = CFleet.cell(bf)
				orders.append({"t": "fmove", "fleet": int(fl["id"]), "x": CGrid.cx(dk), "y": CGrid.cy(dk), "persist": 1})
			st = CTurn.resolve_turn(st, [CTurn.submission(st, pf, orders)])
		var fired: Array = []
		for fr in CStory.S(st)["fired"]:
			fired.append(str(fr[0]))
		print("     seed %d: turn %d, act %d, purse %d, attention %d, haven %d, favour %d, fired %s" % [sd, int(st["turn"]),
			int(CStory.S(st)["act"]), CStory.p(st, "purse"), CStory.attention(st), CStory.p(st, "haven"), CStory.p(st, "favour"), str(fired)])
		_check(ok and (int(st["turn"]) >= turns or str(st["phase"]) == "over"), "seed %d: %d turns with random choices" % [sd, turns])
		_check(fired.has("hanging") and fired.has("chase") and fired.has("hungry") and fired.has("act1"), "seed %d: the prologue's beats and Act 1 fired" % sd)
		if turns >= 15:
			_check(fired.has("act1_end") or str(st["phase"]) == "over", "seed %d: Act 1 ends" % sd)
		var j := CState.to_json(st)
		_check(CState.hash_text(CState.from_json(j)) == CState.hash_text(st), "seed %d: the state round-trips through JSON" % sd)
