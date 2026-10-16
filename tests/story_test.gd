extends SceneTree
## Story campaigns (campaign/cstory.gd, the script campaign/data/story_brethren.gd).
##   godot --headless --script res://tests/story_test.gd [-- --turns=45 --seeds=8 --quick]
## The start, the prologue played deterministically for scripted choices
## (twice the same, a JSON round trip on the way), triggers firing at their
## thresholds, a choice's effects, a story battle and its follow-up, the
## turn held while a choice waits, step 2's effects and conditions (letters
## of marque, the treaty, ships, the Armada's growth and rest, walls, a
## story assault, a raid waiting for a battle, a deserter, the free port's
## goal, an ending), and normal campaigns unchanged by any of it. Then the
## whole story (45 turns) on the scripted paths to each ending
## (game/campaign/story_autoplay.gd: twice the same, and the same through a
## JSON round trip every turn), and headless runs with random choices
## (several seeds) that must reach the end of Act 1 and one of the three
## endings without errors. --quick: the paths once, no round trip.

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
const CAI := preload("res://campaign/cai.gd")
const SA := preload("res://game/campaign/story_autoplay.gd")

var fails := 0
var turns := 45
var seeds := 8
var quick := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--turns="):
			turns = int(a.get_slice("=", 1))
		elif a.begins_with("--seeds="):
			seeds = int(a.get_slice("=", 1))
		elif a == "--quick":
			quick = true
	var west0 := _west_hash()
	var rome0 := _rome_hash()
	_start()
	_scripted()
	_triggers()
	_effects()
	_battles()
	_blocked()
	_coop()
	_shield()
	_step2()
	_paths()
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


## The haven shield: the sandbox AI leaves a captain's haven alone unless provoked.
func _shield() -> void:
	var st := _new(5)
	var hr := CData.region_index("port_de_paix")
	var fr := CData.faction_index("france")
	var sp := CData.faction_index("new_spain")
	var en := CData.faction_index("england")
	var ca := CStory.player(st)
	_check(CStory.shielded(st, fr, hr) and CStory.shielded(st, sp, hr) and CStory.shielded(st, en, hr), "shield: unprovoked nations leave the haven alone")
	_check(not CStory.shielded(st, ca, hr) and not CStory.shielded(st, fr, CData.region_index("havana")), "shield: not for the captain's own side, nor for other regions")
	CStory.S(st)["p"]["heat"] = 40
	_check(not CStory.shielded(st, sp, hr) and CStory.shielded(st, fr, hr), "shield: the Armada's attention provokes Spain only")
	CStory.S(st)["p"]["heat"] = 0
	CStory._provoke(st, fr, int(st["turn"]))
	_check(not CStory.shielded(st, fr, hr) and CStory.shielded(st, en, hr), "shield: a sacked port provokes that nation")
	st["turn"] = int(st["turn"]) + 8
	_check(CStory.shielded(st, fr, hr), "shield: eight turns on it is forgiven")
	CStory.set_flag(st, "treaty")
	_check(not CStory.shielded(st, en, hr) and CStory.shielded(st, fr, hr), "shield: England is released at the Treaty")
	var w := CState.new_campaign("w", 3, [], {}, [], "west")
	_check(not CStory.shielded(w, fr, hr) and not CAI._shield(w, fr, hr), "shield: a sandbox campaign has none")
	# The AI plays on: France at war with the captain and a French stack beside the haven does not take it by turn 20.
	var run := SA.play(101, 20, "first", 1)
	_check(CState.owner(run, hr) == CStory.player(run) or CStory.flag(run, "lost_reprisal") or CStory.attention(run) >= 35,
		"shield: the haven stands at turn 20 unless the reprisal or the attention took it")


## Co-op: two captains, the crew votes every choice (cstory.gd answer).
func _coop() -> void:
	var st := CStory.new_story("Co", 5, {}, "brethren", true)
	var caps := CStory.captains(st)
	_check(caps.size() == 2 and (st["humans"] as Array).size() == 2 and CStory.voters(st).size() == 2, "co-op: two human captains")
	var a := int(caps[0])
	var b := int(caps[1])
	_check(not CStory.flagship(st, b).is_empty() and CState.alive(st, b) and not CState.regions_of(st, b).is_empty(),
		"co-op: the partner has a sloop and a haven of his own")
	var pe: Dictionary = CStory.pending_for(st)[0]
	var pid := int(pe["id"])
	_check(CStory.is_vote(pe) and CStory.pending_for(st, a).size() == 1 and CStory.pending_for(st, b).size() == 1,
		"co-op: the first choice is a vote both captains answer")
	_check(CStory.answer_check(st, b + 1, pid, 0) != "", "co-op: a third faction cannot vote")
	var h0 := CState.hash_text(st)
	var s1 := CStory.answer(st, a, pid, 0)
	_check(CState.hash_text(st) == h0, "co-op: answer() is pure")
	_check(CStory.blocked(s1) and CStory.pending_for(s1, a).is_empty() and CStory.pending_for(s1, b).size() == 1 and CStory.vote_of(s1_pe(s1), a) == 0,
		"co-op: after one vote the choice still waits for the other captain")
	_check(CStory.answer_check(s1, a, pid, 1) != "", "co-op: a captain votes once")
	var t1 := CTurn.resolve_turn(s1, [])
	_check(int(t1["turn"]) == int(s1["turn"]), "co-op: the turn does not resolve while a vote is open")
	var rt := CState.from_json(CState.to_json(s1))
	var agree := CStory.answer(rt, b, pid, 0)
	_check(CStory.pending_for(agree).filter(func(x): return int(x["id"]) == pid).is_empty(), "co-op: agreement passes the choice")
	var last: Dictionary = (CStory.S(agree)["log"] as Array).filter(func(x): return str(x["e"]) == str(pe["e"])).back()
	_check(int(last["c"]) == 0 and int(last["w"]) == -1 and (last["v"] as Array).size() == 2, "co-op: the log keeps both votes")
	var solo := CStory.answer(CStory.new_story("Co", 5, {}, "brethren", true), a, pid, 0)
	solo = CStory.answer(solo, b, pid, 0)
	_check(CState.hash_text(solo) == CState.hash_text(agree), "co-op: the same votes through JSON give the same state")
	# A disagreement: the heavier side (fame, crew, men) wins; its loser's crew grumbles.
	var d1 := CStory.answer(st, a, pid, 0)
	var d2 := CStory.answer(d1, b, pid, 1)
	var d3 := CStory.answer(CStory.answer(st, b, pid, 1), a, pid, 0)
	_check(CState.hash_text(d2) == CState.hash_text(d3), "co-op: the order of the votes does not matter")
	var wa := CStory.vote_weight(st, a)
	var wb := CStory.vote_weight(st, b)
	var want := 0 if wa >= wb else 1
	var dl: Dictionary = (CStory.S(d2)["log"] as Array).filter(func(x): return str(x["e"]) == str(pe["e"])).back()
	_check(int(dl["c"]) == want and int(dl["w"]) == (a if wa >= wb else b) and CStory.flag(d2, "crew_split"),
		"co-op: a split vote goes to the heavier side (%d against %d)" % [wa, wb])
	var loser := b if wa >= wb else a
	var crew0 := 0
	var crew1 := 0
	for fl in CFleet.fleets_of(st, loser):
		crew0 += int(fl["ships"][0]["c"])
	for fl in CFleet.fleets_of(d2, loser):
		crew1 += int(fl["ships"][0]["c"])
	_check(crew1 < crew0 or crew0 <= 5, "co-op: the loser's crew grumbles (%d -> %d)" % [crew0, crew1])
	# Famous partner outvotes the lead.
	var sf := CStory.new_story("Co", 5, {}, "brethren", true)
	for c in CCaptain.of_faction(sf, b):
		c["fame"] = 40
	var d4 := CStory.answer(CStory.answer(sf, a, pid, 0), b, pid, 1)
	var d4l: Dictionary = (CStory.S(d4)["log"] as Array).filter(func(x): return str(x["e"]) == str(pe["e"])).back()
	_check(int(d4l["c"]) == 1 and int(d4l["w"]) == b, "co-op: the more famous captain carries a split vote")
	# A tie goes to the lead.
	var stie := CStory.new_story("Co", 5, {}, "brethren", true)
	for c in CCaptain.of_faction(stie, b):
		c["fame"] = 5
	for c in CCaptain.of_faction(stie, a):
		c["fame"] = 5
	for fl in CFleet.fleets_of(stie, a):
		fl["ships"][0]["c"] = CFleet.fleets_of(stie, b)[0]["ships"][0]["c"]
		fl["carry"] = CFleet.fleets_of(stie, b)[0]["carry"].duplicate(true)
	for ar in stie["armies"]:
		if int(ar["f"]) == a or int(ar["f"]) == b:
			ar["units"] = []
	var dt := CStory.answer(CStory.answer(stie, a, pid, 0), b, pid, 1)
	var dtl: Dictionary = (CStory.S(dt)["log"] as Array).filter(func(x): return str(x["e"]) == str(pe["e"])).back()
	_check(CStory.vote_weight(stie, a) == CStory.vote_weight(stie, b) and int(dtl["w"]) == a and int(dtl["c"]) == 0, "co-op: a tie goes to the lead captain")
	# The whole story with two captains voting (a quarter of the second captain's votes differ).
	for sd in 2:
		var cp := SA.play(300 + sd, turns, "random", 2000 + sd, false, true, true, 4)
		var cp2 := SA.play(300 + sd, turns, "random", 2000 + sd, false, true, true, 4)
		_check(CState.hash_text(cp) == CState.hash_text(cp2) and not CStory.blocked(cp) and (int(cp["turn"]) >= turns or str(cp["phase"]) == "over"),
			"co-op seed %d: %d turns of votes, the same twice (turn %d, %s)" % [sd, turns, int(cp["turn"]), CStory.ending(cp)])
		var j := CState.to_json(cp)
		_check(CState.hash_text(CState.from_json(j)) == CState.hash_text(cp), "co-op seed %d: the state round-trips through JSON" % sd)
	var cj := SA.play(300, mini(turns, 20), "random", 2000, true, true, true, 4)
	var cn := SA.play(300, mini(turns, 20), "random", 2000, false, true, true, 4)
	_check(CState.hash_text(cj) == CState.hash_text(cn), "co-op: the same through a JSON round trip every turn")


func s1_pe(st: Dictionary) -> Dictionary:
	return CStory.pending_for(st)[0]


## The whole story with random choices and the autoplay captain (every
## battle by the formula), several seeds: no errors, Act 1 told, and one of
## the three endings by turn 45 (or the campaign over, which is the Legend).
func _random_runs() -> void:
	for sd in seeds:
		var st := SA.play(100 + sd, turns, "random", 1000 + sd)
		var fired: Array = []
		for fr in CStory.S(st)["fired"]:
			fired.append(str(fr[0]))
		print("     seed %d: turn %d, act %d, ending %s (turn %d), purse %d, attention %d, haven %d, favour %d, %d events fired" % [sd,
			int(st["turn"]), int(CStory.S(st)["act"]), CStory.ending(st), int(CStory.S(st).get("end_t", -1)), CStory.p(st, "purse"),
			CStory.attention(st), CStory.p(st, "haven"), CStory.p(st, "favour"), fired.size()])
		_check((int(st["turn"]) >= turns or str(st["phase"]) == "over") and not CStory.blocked(st),
			"seed %d: %d turns with random choices" % [sd, turns])
		_check(fired.has("hanging") and fired.has("chase") and fired.has("hungry") and fired.has("act1"), "seed %d: the prologue's beats and Act 1 fired" % sd)
		if turns >= 15:
			_check(fired.has("act1_end") or str(st["phase"]) == "over", "seed %d: Act 1 ends" % sd)
		if turns >= 45:
			_check(["republic", "pardon", "legend"].has(CStory.ending(st)), "seed %d: the story ends in one of the three endings (%s)" % [sd, CStory.ending(st)])
		var j := CState.to_json(st)
		_check(CState.hash_text(CState.from_json(j)) == CState.hash_text(st), "seed %d: the state round-trips through JSON" % sd)


## The whole story on the scripted paths (story_autoplay.gd: choices by
## event id, the captain winning his battles but the Legend's finale): each
## reaches its ending, the same twice and through a JSON round trip each turn.
func _paths() -> void:
	for path in ["republic", "pardon", "legend"]:
		var a := SA.play(5, 46, path, 7)
		var fired: Array = []
		for fr in CStory.S(a)["fired"]:
			fired.append(str(fr[0]))
		print("     %s: %s, ending turn %d, stats %s" % [path, CState.hash_text(a), int(CStory.S(a).get("end_t", -1)), str(CStory.end_stats(a))])
		_check(CStory.ending(a) == path, "the %s path ends in the %s (%s)" % [path, path, CStory.ending(a)])
		for id in ["act2", "commission", "flota_news", "treaty", "lindo_test", "act2_end", "act3", "vane_pages", "council", "great_raid", "pardon"]:
			if not fired.has(id):
				_check(false, "the %s path: %s fired" % [path, id])
		if path != "pardon":
			_check(fired.has("armada_gathers") and fired.has("eve") and (fired.has("finale_sea") or fired.has("finale_walls")),
				"the %s path: Mendoza comes, the night before, the finale" % path)
		_check(CStory.S(a)["actors"].is_empty() and CStory.S(a)["pending"].is_empty() and CStory.flag(a, "ended"),
			"the %s path: the ending released the story's fleets and ended its choices" % path)
		_check(CStory.fates(a).size() == 7, "the %s path: seven fates in the epilogue" % path)
		if quick:
			continue
		var b := SA.play(5, 46, path, 7)
		var c := SA.play(5, 46, path, 7, true)
		_check(CState.hash_text(a) == CState.hash_text(b), "the %s path plays the same twice" % path)
		_check(CState.hash_text(a) == CState.hash_text(c), "... and the same through a JSON round trip every turn")
		var j := CState.to_json(a)
		var re := RegEx.create_from_string("[:\\[,]\\s*(true|false|[0-9]+\\.[0-9])")
		_check(re.search(j) == null and CState.hash_text(CState.from_json(j)) == CState.hash_text(a),
			"the %s ending's state is plain JSON (no bools, no floats) and round-trips" % path)


## Step 2's effects and conditions, one by one on a fresh story.
func _step2() -> void:
	var st := _new(11)
	var pf := _pf(st)
	st = _answer(st, 0)
	var eng := CData.faction_index("england")
	var spa := CData.faction_index("new_spain")
	var tf := CData.faction_index("tierra_firme")
	CStory._fx(st, pf, [["dip2", "england", "new_spain", "war"], ["marque", "england"]])
	_check(CSea.has_marque(st, eng, pf) and CState.dip(st, eng, pf) == CState.PEACE and CState.at_war(st, eng, spa),
		"the commission: England's letter of marque, peace with England, England at war with Spain")
	_check(CSea.plunder_pct(st, pf, spa) > 100, "Spanish plunder pays more under the letter (%d %%)" % CSea.plunder_pct(st, pf, spa))
	CStory._fx(st, pf, [["dip2", "england", "new_spain", "peace"], ["unmarque", "england"], ["dip", "england", "war"]])
	_check(not CSea.has_marque(st, eng, pf) and CState.at_war(st, eng, pf) and not CState.at_war(st, eng, spa),
		"the treaty: the letter revoked, England at peace with Spain and at war with you")
	var fl := CStory.flagship(st, pf)
	var n0 := (fl["ships"] as Array).size()
	CStory._fx(st, pf, [["ship", "brigantine", "Lindo's Folly"]])
	_check((fl["ships"] as Array).size() == n0 + 1 and str(fl["ships"][-1]["nm"]) == "Lindo's Folly", "a bought ship joins the flagship's fleet")
	var ar := CStory.actor_fleet(st, "armada")
	var na := (ar["ships"] as Array).size()
	CStory._fx(st, pf, [["actor_add", "armada", [{"t": "galleon"}]], ["actor_att", "armada", 20]])
	_check((ar["ships"] as Array).size() == na + 1 and int(CStory.actor(st, "armada")["att"]) == 20, "the Armada grows and hunts from attention 20")
	CStory._fx(st, pf, [["actor_lose", "armada", 1]])
	_check((ar["ships"] as Array).size() == na and str(ar["ships"][-1]["t"]) != "galleon", "recognition: the Armada loses its strongest ship")
	var hr := CData.region_index("port_de_paix")
	CStory._fx(st, pf, [["build", "port_de_paix", "walls", 2]])
	_check(CState.walls(st, hr) == 2, "the crew raises Tortuga's walls to stone (2)")
	# The free port's goal and its parts.
	CStory._fx(st, pf, [["free_port"], ["fp_gold", 1500]])
	_check(CStory.fp_met(st, "chest") and not CStory.fp_met(st, "fort") and CStory.fp_parts(st).size() == 3,
		"the free port: the chest full, the fort not held yet")
	(CStory.S(st)["fp"] as Dictionary)["held"] = 5
	_check(CStory.fp_met(st, "fort") and CStory.fp_count(st) >= 2 and CStory._cond(st, {"fp_ge": 2}), "five turns held: two parts of three")
	# A story assault: everyone lands beside Cartagena and storms it now.
	var s2 := _new(12)
	s2 = _answer(s2, 0)
	var cr := CData.region_index("cartagena")
	CStory._fx(s2, _pf(s2), [["weaken", "cartagena", 40], ["assault", "cartagena", ["cutlass", "cutlass", "buccaneers"], "cartagena"]])
	var lb := CTurn.pending_for(s2)
	_check(lb.size() == 1 and not lb[0].has("sea") and int(lb[0]["r"]) == cr and CStory.flag(s2, "bt_cartagena"),
		"the great raid: a land battle at Cartagena, flagged bt_cartagena")
	s2["phase"] = "battles"
	s2 = CTurn.apply_battle(s2, int(lb[0]["id"]), CBattle.formula(s2, lb[0]))
	_check(CStory.flag(s2, "won_cartagena") or CStory.flag(s2, "lost_cartagena"), "its result is read back")
	# A raid on a settlement with a battle already pending there waits for it.
	var s3 := _new(13)
	s3 = _answer(s3, 0)
	CStory._fx(s3, _pf(s3), [["raid", "new_spain", "port_de_paix", ["musketeers"], "one"], ["raid", "new_spain", "port_de_paix", ["musketeers"], "two"]])
	_check(CTurn.pending_for(s3).size() == 1 and (CStory.S(s3).get("rq", []) as Array).size() == 1, "a second raid waits while the first is pending")
	s3["phase"] = "battles"
	var b1: Dictionary = CTurn.pending_for(s3)[0]
	s3 = CTurn.apply_battle(s3, int(b1["id"]), CBattle.formula(s3, b1))
	if CState.owner(s3, hr) == _pf(s3):
		_check(CStory.flag(s3, "bt_two") and str(s3["phase"]) == "battles", "... and lands when it is over (the turn waits for it)")
	# A deserter: a captain the story made turns his coat.
	var s4 := _new(14)
	var p4 := _pf(s4)
	s4 = _answer(s4, 0)
	CStory._fx(s4, p4, [["spawn", "hesketh", "brethren", "port_de_paix", [{"t": "brigantine", "nm": "Ranger"}], 0, "hold"], ["join", "hesketh", "Tom Hesketh", 15]])
	_check(not CStory.story_captain(s4, "hesketh").is_empty() and CStory.actor(s4, "hesketh").is_empty(), "Hesketh's Ranger sails for you under her own captain")
	CStory._fx(s4, p4, [["desert", "hesketh", "new_spain"]])
	var hf := CStory.actor_fleet(s4, "hesketh")
	_check(CStory.story_captain(s4, "hesketh").is_empty() and not hf.is_empty() and int(hf["f"]) == spa, "... and turns his coat: an actor of Spain's again")
	# An ending: the actors released, the choices gone, no more events.
	var s5 := _new(15)
	CStory._fx(s5, _pf(s5), [["ending", "legend"]])
	CStory.S(s5)["sched"].append([0, "tortuga"])
	CStory.check(s5)
	_check(CStory.ending(s5) == "legend" and CStory.S(s5)["actors"].is_empty() and not CStory.blocked(s5) and not _has_pending(s5, "tortuga"),
		"an ending: the story's fleets released, nothing waits, no event fires after it")
	var s6 := CTurn.resolve_turn(s5, [])
	_check(int(s6["turn"]) == 1 and CStory.ending(s6) == "legend", "the campaign plays on after the ending (the sandbox)")
	_check(tf >= 0, "the factions are there")


