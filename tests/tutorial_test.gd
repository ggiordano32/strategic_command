extends SceneTree
## The tutorial (docs/design/campaign_rules.md "The tutorial"), headless:
##   godot --headless --script res://tests/tutorial_test.gd
## One text source (howto.gd: the eight sections, ten lessons, six battle steps, eight tips); the first-time tips (shown
## once, remembered in the tests folder's tips.cfg, reset, never in the real user folder); the guided first campaign
## (its state: England at Port Royal, Sevilla la Nueva Spanish, `tutorial` 1; the campaign AI declares no war on the
## player for the first ten turns; the ten lessons driven by the scripted order of each objective with End turn held
## until it is met, a lesson card and a pointer each turn; the skip path; the leave path); the battle tutorial's six steps
## on the battle screen; the How to play page in the title menu and the two in-game menus. Exits 0 on success, 1 on failure.

const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CAI := preload("res://campaign/cai.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const Saves := preload("res://game/campaign/saves.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const Howto := preload("res://game/campaign/howto.gd")
const Tips := preload("res://game/campaign/tips.gd")
const Tutorial := preload("res://game/campaign/tutorial.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const UT := preload("res://sim/unit_types.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const OptionsRows := preload("res://game/menu/options_rows.gd")

class ErrCount extends Logger:
	var n := 0
	var first := ""

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_SCRIPT:
			n += 1
			if first == "":
				first = "%s:%d %s %s" % [file, line, code, rationale]


var _errs := ErrCount.new()
var failures := 0
var cs: CampaignScreen = null
var eng := -1
var pr := -1
var sv := -1
var _real_tips := false


func _initialize() -> void:
	OS.add_logger(_errs)
	Saves.subdir = "tutorial_test/"
	Tips.in_tests = true
	_real_tips = FileAccess.file_exists("user://tips.cfg")
	_run.call_deferred()


func _check(c: bool, what: String) -> void:
	if c:
		print("PASS ", what)
	else:
		printerr("FAIL ", what)
		failures += 1


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _run() -> void:
	_texts()
	_tips()
	_rules()
	await _run_lessons()
	await _run_skip_leave()
	await _howto_menus()
	if cs != null and is_instance_valid(cs):
		cs.queue_free()
	await _frames(2)
	_check(_errs.n == 0, "no script errors logged (%d) %s" % [_errs.n, _errs.first])
	print("%s tutorial_test: %d failure(s)" % ["RESULT: PASS" if failures == 0 else "RESULT: FAIL", failures])
	quit(0 if failures == 0 else 1)


# ------------------------------------------------------------------ texts ---

func _texts() -> void:
	_check(Howto.SECTIONS.size() == 8, "How to play has eight sections")
	var all_lines := true
	for s in Howto.SECTIONS:
		if (s["lines"] as Array).size() < 1 or (s["lines"] as Array).size() > 3:
			all_lines = false
		for k in s["lines"]:
			if Howto.text(str(k)) == "":
				all_lines = false
	_check(all_lines, "every section has one to three lines, all with text")
	var lessons_ok := true
	for n in range(1, Howto.LESSONS + 1):
		var L := Howto.lesson(n)
		if str(L["title"]) == "" or str(L["text"]) == "" or str(L["obj"]) == "":
			lessons_ok = false
	_check(lessons_ok, "the ten lessons each have a title, a text and an objective")
	var steps_ok := true
	for n in range(1, Howto.STEPS + 1):
		if Howto.step(n) == "":
			steps_ok = false
	_check(steps_ok and Howto.text("step_1b") != "" and Howto.text("step_win") != "", "the battle tutorial's six steps have text")
	var tips_ok := Howto.TIP_KEYS.size() == 8
	for k in Howto.TIP_KEYS:
		var t := Howto.tip(k)
		if t == "" or t.count(". ") > 0:
			tips_ok = false   # (one sentence)
	_check(tips_ok, "the eight tips are one sentence each")


# ------------------------------------------------------------------- tips ---

func _tips() -> void:
	Tips.reset()
	Tips.presenter = Callable()
	Tips.suppress = false
	var path := Tips.path()
	_check(path.begins_with("user://campaigns/tutorial_test/"), "tests keep the tips file in the tests folder (%s)" % path)
	_check(not Tips.show("army_selected") and not Tips.seen("army_selected"), "with no screen to show it, a tip is not shown and not used up")
	var got: Array = []
	Tips.presenter = func(text: String, key: String): got.append([key, text])
	_check(Tips.show("army_selected") and got.size() == 1 and str(got[0][1]) == Howto.tip("army_selected"), "the first time a tip is shown with the howto.gd sentence")
	_check(not Tips.show("army_selected") and got.size() == 1, "... and not again")
	_check(FileAccess.file_exists(path) and Tips.seen("army_selected") and not Tips.seen("town_opened"), "... remembered in the file")
	Tips.suppress = true
	_check(not Tips.show("town_opened"), "tips wait while the tutorial runs")
	Tips.suppress = false
	_check(Tips.show("town_opened") and Tips.count_seen() == 2, "two tips seen")
	_check(FileAccess.file_exists("user://tips.cfg") == _real_tips, "the real user folder's tips.cfg is untouched")
	# Options: "Show the tips again"
	var host := VBoxContainer.new()
	root.add_child(host)
	var rows := OptionsRows.new()
	rows.build(host, {"prefix": "tt", "narrow": true, "title": false, "help": false, "win": root})
	var btn: Button = rows.buttons.get("tips")
	_check(btn != null and btn.name == "tt_tips_reset", "Options has the Show the tips again button")
	btn.pressed.emit()
	_check(not FileAccess.file_exists(path) and not Tips.seen("army_selected"), "... it resets the tips file")
	_check(Tips.show("army_selected"), "... and the tips show again")
	Tips.reset()
	host.queue_free()
	Tips.presenter = Callable()


# ------------------------------------------------------------------ rules ---

func _rules() -> void:
	var st := Tutorial.make_state("T", Tutorial.SEED, 0)
	eng = CData.faction_index("england")
	pr = CData.region_index("port_royal")
	sv = CData.region_index("sevilla_jamaica")
	var spa := CData.faction_index("new_spain")
	_check(CData.pack == "west" and st["humans"] == [eng], "the tutorial is a West campaign for England")
	_check(int(st["settings"]["tutorial"]) == 1 and int(st["settings"]["tutorial_turns"]) == 10, "settings: tutorial 1, tutorial_turns 10")
	_check(CState.owner(st, pr) == eng and CState.owner(st, sv) == spa, "Port Royal is English and Sevilla la Nueva Spanish")
	_check(CState.at_war(st, eng, spa), "England is at war with Spain from the start")
	var armies := CState.armies_of(st, eng)
	var a: Dictionary = armies[0] if armies.size() == 1 else {}
	var counts := {}
	for u in a.get("units", []):
		counts[str(u["t"])] = int(counts.get(str(u["t"]), 0)) + 1
	_check(armies.size() == 1 and int(a["r"]) == pr and int(counts.get("musketeers", 0)) == 2 and int(counts.get("w_pikemen", 0)) == 1 and int(counts.get("pistoleers", 0)) == 1,
		"one English army at Port Royal: two musketeers, a pike, a horse")
	var pp := CRules.plan_path(st, a, CGrid.camp(sv), -1, CData.MODE_SIEGE, {}, 12, -1)
	_check(not pp.has("why") and (pp["t"] as Array).size() > 0, "the camp outside Sevilla la Nueva is reachable overland from Port Royal")
	var pp2 := CRules.plan_path(st, a, CGrid.site(sv), -1, CData.MODE_SIEGE, {}, 12, -1)
	_check(not pp2.has("why"), "... and so is the town itself")
	_check(CAI.tutorial_shield(st, eng), "the AI shield is on at turn 0")
	var plain := CState.new_campaign("P", 5, [eng], {}, [], "west")
	_check(not CAI.tutorial_shield(plain, eng), "... and off in a campaign without the setting")
	# Ten turns of the player doing nothing: the AI declares no new war on England.
	var wars0 := _wars_on(st, eng)
	for t in 9:
		st = CTurn.resolve_turn(st, [CTurn.submission(st, eng, [])])
		while not CTurn.pending_for(st).is_empty():
			var b: Dictionary = CTurn.pending_for(st)[0]
			var out := {"winner": 1, "mode": "auto", "units": [], "garrison_pct": 100}
			st = CTurn.apply_battle(st, int(b["id"]), out)
	_check(_wars_on(st, eng) == wars0, "nine turns on, no new war on England (%s wars on it)" % str(_wars_on(st, eng)))
	_check(int(st["turn"]) >= 9 and CAI.tutorial_shield(st, eng) == (int(st["turn"]) < 10), "the shield ends with tutorial_turns")


func _wars_on(st: Dictionary, f: int) -> Array:
	var out: Array = []
	for g in CState.nf():
		if g != f and CState.at_war(st, f, g):
			out.append(g)
	return out


# ---------------------------------------------------------------- screens ---

func _new_screen(st: Dictionary, slot: String) -> void:
	if cs != null and is_instance_valid(cs):
		cs.queue_free()
		await _frames(3)
	PackView.use_pack("west")
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, slot)
	root.add_child(cs)
	await _frames(10)
	await _close_dialogs()


func _close_dialogs() -> void:
	for k in 6:
		if cs.dialog_open():
			cs.close_dialog()
		await _frames(2)
		if not cs.dialog_open():
			break


## End the turn (through the warnings) and wait for the next planning phase (or the pending battle).
func _end_turn() -> void:
	var t0 := int(cs.st["turn"])
	cs.end_turn(true)
	for k in 120:
		await process_frame
		if int(cs.st["turn"]) > t0 and cs.dialog_kind != "resolving":
			break
	await _frames(3)


func _army_id() -> int:
	var a := CState.armies_of(cs.ps, eng)
	var best := -1
	var n := -1
	for x in a:
		if CState.unit_count(x) > n:
			n = CState.unit_count(x)
			best = int(x["id"])
	return best


func _card_text() -> String:
	return str(cs.tutorial.card.text_label.text) if cs.tutorial.card.visible else ""


## Lesson n: the card shows its words, End turn is held, and `act` (the objective's order) opens the gate.
func _lesson(n: int, act: Callable) -> void:
	var tu = cs.tutorial
	_check(tu.lesson_n() == n, "lesson %d is current (turn %d)" % [n, int(cs.st["turn"])])
	if not tu.card.visible or _card_text() != Howto.lesson(n)["text"]:
		print("   card visible=%s dialog=%s kind=%s phase=%s pending=%d f=%d text=%s" % [tu.card.visible, cs.dialog_open(), cs.dialog_kind, cs.st["phase"], CTurn.pending_for(cs.st).size(), cs.f, _card_text()])
	_check(tu.card.visible and _card_text() == Howto.lesson(n)["text"], "lesson %d: the card shows its words" % n)
	_check(str(tu.card.title_label.text).contains(str(Howto.lesson(n)["title"])), "lesson %d: the card has its title" % n)
	_check(tu.card.buttons.has("skip") and tu.card.buttons.has("leave"), "lesson %d: Skip the lesson and Leave the tutorial are there" % n)
	_check(tu.holds_end() and cs.end_button.disabled, "lesson %d: End turn is held" % n)
	var t0 := int(cs.st["turn"])
	cs.end_turn(true)
	await _frames(4)
	_check(int(cs.st["turn"]) == t0 and not cs._resolving, "lesson %d: End turn does nothing before the objective" % n)
	_check(Kit.tip_of(cs.end_button).size() > 0 and str(Kit.tip_of(cs.end_button)[0]) == Howto.text("ui_gate"), "lesson %d: the held button says Finish the lesson first" % n)
	await act.call()
	await _frames(3)
	_check(tu.met(n) and not tu.holds_end() and not cs.end_button.disabled, "lesson %d: the objective opens the gate" % n)
	_check(tu.pointer.visible and tu.pointer.showing, "lesson %d: the pointer points at End turn" % n)


func _run_lessons() -> void:
	var st := Tutorial.make_state("Tutorial run", Tutorial.SEED, 0)
	await _new_screen(st, "tutorial_test_a")
	var tu = cs.tutorial
	_check(tu != null and tu.on() and cs.f == eng, "the tutorial runs on the campaign screen")
	_check(tu.pointer.visible and tu.pointer.showing, "lesson 1: the pointer is on Port Royal")
	# 1 the map
	await _lesson(1, func(): cs.select_region(pr))
	await _end_turn()
	await _close_dialogs()
	# 2 recruiting
	await _lesson(2, func():
		var aid := _army_id()
		cs.add_order({"t": "recruit", "r": pr, "unit": "musketeers", "army": aid})
		_check(not tu.met(2), "lesson 2: one musketeer company is not enough")
		cs.add_order({"t": "recruit", "r": pr, "unit": "musketeers", "army": aid}))
	await _end_turn()
	await _close_dialogs()
	# 3 building
	await _lesson(3, func(): cs.add_order({"t": "build", "r": pr, "chain": Tutorial._chain("range")}))
	await _end_turn()
	await _close_dialogs()
	# 4 moving
	_check(CState.unit_count(CState.army(cs.st, _army_id())) == 7, "the two recruits joined the army (seven units, four musketeers)")
	await _lesson(4, func(): cs.set_move6(_army_id(), CGrid.camp(sv), -1))
	await _end_turn()
	await _close_dialogs()
	_check(CState.cell(CState.army(cs.st, _army_id())) == CGrid.camp(sv), "the army marched to the camp outside Sevilla la Nueva")
	# 5 the siege
	await _lesson(5, func(): cs.set_move6(_army_id(), CGrid.site(sv), -1))
	await _end_turn()
	await _close_dialogs()
	_check(not CState.siege_at(cs.st, sv).is_empty() and int(CState.siege_at(cs.st, sv)["f"]) == eng, "the siege of Sevilla la Nueva is laid")
	# 6 the battle: the assault order, then the battle tutorial
	await _lesson(6, func(): cs.add_order({"t": "assault", "r": sv}))
	await _end_turn()
	await _close_dialogs()
	_check(not CTurn.pending_for(cs.st).is_empty(), "the assault leaves a battle to fight")
	await _battle_tutorial()
	await _close_dialogs()
	_check(CState.owner(cs.st, sv) == eng, "Sevilla la Nueva is English after the battle")
	_check(tu.lesson_n() == 7, "the battle won, lesson 7 follows")
	# 7 after
	await _lesson(7, func():
		cs.panels.show_faction()
		await _frames(2)
		cs.close_dialog())
	await _end_turn()
	await _close_dialogs()
	# 8 diplomacy
	await _lesson(8, func(): cs.add_order({"t": "propose", "to": CData.faction_index("dutch"), "what": "trade"}))
	await _end_turn()
	await _close_dialogs()
	# 9 the sea
	await _lesson(9, func():
		var fl: Dictionary = CFleet.fleets_of(cs.ps, eng)[0]
		_check(not tu.met(9), "lesson 9: boarding alone is not enough")
		cs.set_board(_army_id(), int(fl["id"]))
		cs.set_fmove(int(fl["id"]), Tutorial.sail_cell()))
	await _end_turn()
	await _close_dialogs()
	# 10 goals
	await _lesson(10, func():
		cs.panels.show_objectives()
		await _frames(2)
		cs.close_dialog())
	await _end_turn()
	await _close_dialogs()
	await _frames(3)
	_check(tu.lesson_n() == Tutorial.DONE_STAGE and tu.card.visible and tu.card.buttons.has("over"), "after lesson 10 the card says the lessons are over")
	_check(_card_text() == Howto.text("lesson_over") and not tu.holds_end(), "... and End turn is free")
	tu.card.buttons["over"].pressed.emit()
	await _frames(2)
	_check(not tu.on() and not tu.card.visible, "Got it ends the tutorial: the campaign is a sandbox")
	_check(int(cs.data["session"]["tutorial"]["off"]) == 1, "the lesson state is in the save's session, not in the state")
	_check(not (cs.st.has("tutorial")) and Tutorial.is_tutorial(cs.st), "the state only carries the setting")


# --------------------------------------------------------- battle tutorial ---

func _battle_tutorial() -> void:
	var b: Dictionary = CTurn.pending_for(cs.st)[0]
	cs.fight(int(b["id"]))
	await _frames(30)
	var bt = cs.battle
	_check(bt != null and bt.tutorial != null, "the battle gets the tutorial script")
	if bt == null or bt.tutorial == null:
		return
	var tb = bt.tutorial
	var sim = bt.sim
	_check(sim.phase == BattleSim.PHASE_DEPLOY and tb.step == 1 and tb.card.visible, "step 1: the deployment, the card shows")
	_check(tb.card.text_label.text == Howto.step(1) and tb.pointer.visible, "step 1: the card has the words and the pointer shows")
	var horse: Array = tb.mine(UT.CLS_CAV)
	var musk: Array = tb.mine(UT.CLS_MISSILE)
	var pikes: Array = tb.mine(UT.CLS_PIKE)
	print("   army: horse %d musk %d pike %d inf %d, units %d, phase %d" % [horse.size(), musk.size(), pikes.size(), tb.mine(UT.CLS_INF).size(), sim.n_units, sim.phase])
	_check(horse.size() == 1 and musk.size() == 4 and pikes.size() == 1, "the army: four musketeers, one pike, one horse")
	# 1 place the line
	var u0: int = musk[0]
	bt._select(u0)
	var o := BattleSim.make_move_order(0, u0, int(sim.u_cx[u0]) + 4 * 1024, int(sim.u_cy[u0]), int(sim.u_face[u0]) if "u_face" in sim else 0, 0, 0)
	bt._queue(o)
	await _frames(4)
	_check(tb.seen_log.has(BattleSim.ORDER_PLACE) and tb._sub == "ready", "step 1: a placement was seen, the card asks for Start battle")
	_check(tb.card.text_label.text == Howto.text("step_1b"), "step 1: the second card says Start battle")
	bt._deploy_ready()
	for k in 200:
		await process_frame
		if sim.phase == BattleSim.PHASE_BATTLE:
			break
	await _frames(20)   # (the battle's card timer moves the step on)
	_check(sim.phase == BattleSim.PHASE_BATTLE and tb.step == 2, "the battle starts: step 2 (move it forward)")
	_check(tb.card.text_label.text == Howto.step(2), "step 2: the card shows its words")
	# 2 move forward
	bt._select_group("all")
	var tx: int = int(sim.u_cx[u0]) + 10 * 1024
	bt._queue(BattleSim.make_move_order(0, u0, tx, int(sim.u_cy[u0]), 0, 0, 0))
	await _frames(2)
	_check(tb.step == 3, "step 2 done by a move order: step 3 (fire at will)")
	tb.update()
	await _frames(2)
	print("   fire chip visible=%s in_tree=%s parent=%s sel=%d explained=%s step=%d more_vis=%s" % [bt.hud.fire_button.visible, bt.hud.fire_button.is_visible_in_tree(), bt.hud.fire_button.get_parent().name, bt.selection.size(), tb.explained, tb.step, bt.hud.more_button.visible])
	_check(tb.explained and bt.hud.explain_panel.visible, "step 3: the Fire chip's long-press explanation was opened once for the player")
	_check(bt.selection.size() == 4 and tb.card.text_label.text == Howto.step(3), "step 3: the musketeers are selected, the card has its words")
	_check(tb.step == 3 and not tb._fire_all_on() and not tb.seen_log.has(BattleSim.ORDER_FIRE), "step 3: the musketeers were told to hold fire, and that does not finish the step")
	bt.hud.fire_button.pressed.emit()   # (the Fire chip opens its options)
	await _frames(2)
	_check(bt.hud.opt_panel.visible and tb._target() != null, "step 3: the options are open, the pointer is on a row")
	bt.hud._choose_option(bt.hud.fire_button, 1)   # (At will)
	await _frames(2)
	print("   after At will: step %d fire_all_on %s log %s opt_visible %s sel %d fire_vals %s" % [tb.step, tb._fire_all_on(), str(tb.seen_log), bt.hud.opt_panel.visible, bt.selection.size(), str(tb.mine(UT.CLS_MISSILE).map(func(u): return bt.orders.value(u, "fire")))])
	_check(tb.step == 4 and tb._fire_all_on(), "step 3 done once Fire is at will: step 4 (charge with the horse)")
	tb.update()
	# 4 charge with the horse
	var foe := -1
	for u in sim.n_units:
		if sim.u_side[u] != bt.player_side and sim.u_alive[u] > 0:
			foe = u
			break
	bt._queue(BattleSim.make_attack_order(0, musk[1], foe, 0))
	await _frames(1)
	_check(tb.step == 4, "step 4: an attack by a musketeer is not the horse's charge")
	bt._queue(BattleSim.make_attack_order(0, horse[0], foe, 0))
	await _frames(2)
	_check(tb.step == 5, "step 4 done by the horse's attack: step 5 (hold)")
	# 5 hold
	bt._select(pikes[0])
	bt._halt()
	await _frames(2)
	_check(tb.step == 6, "step 5 done by Halt: step 6 (withdraw)")
	tb.update()
	# 6 withdraw
	bt._select(musk[3])
	bt._withdraw()
	await _frames(2)
	_check(tb.step == 7, "step 6 done by Withdraw: the closing card")
	tb.update()
	_check(tb.card.text_label.text == Howto.text("step_win") and tb.card.buttons.has("done"), "the closing card says to beat the garrison")
	_check(tb.seen_log.has(BattleSim.ORDER_HALT) and tb.seen_log.has(BattleSim.ORDER_WITHDRAW) and tb.seen_log.has(BattleSim.ORDER_ATTACK), "the order queue was seen")
	# fight it out: everyone attacks the nearest enemy until it is decided
	var guard := 0
	while sim.winner < 0 and sim.ended == 0 and guard < 6000:
		guard += 1
		if guard % 100 == 1:
			for u in tb.mine(UT.CLS_INF) + tb.mine(UT.CLS_PIKE) + tb.mine(UT.CLS_CAV) + tb.mine(UT.CLS_MISSILE):
				var best := -1
				var bd := 1e18
				for e in sim.n_units:
					if sim.u_side[e] != bt.player_side and sim.u_alive[e] > 0:
						var d := Vector2(sim.u_cx[e] - sim.u_cx[u], sim.u_cy[e] - sim.u_cy[u]).length_squared()
						if d < bd:
							bd = d
							best = e
				if best >= 0:
					bt._queue(BattleSim.make_attack_order(0, u, best, 1))
		bt._do_tick()
	_check(bt.is_decided() and sim.winner == bt.player_side, "the battle is won (%d ticks)" % sim.tick)
	tb.update()
	_check(not tb.card.visible, "the battle cards go when the battle is decided")
	bt._end_battle()   # (the End battle / Continue modal's End battle)
	for k in 300:
		await process_frame
		if cs.battle == null:
			break
	_check(cs.battle == null, "the battle returns to the campaign")


# ---------------------------------------------------- skip and leave paths ---

func _run_skip_leave() -> void:
	var st := Tutorial.make_state("Skip run", Tutorial.SEED, 0)
	await _new_screen(st, "tutorial_test_b")
	var tu = cs.tutorial
	for n in range(1, 6):
		_check(tu.lesson_n() == n and tu.holds_end(), "skip path: lesson %d is held" % n)
		(tu.card.buttons["skip"] as Button).pressed.emit()
		await _frames(3)
		_check(tu.met(n) and not tu.holds_end(), "skip path: Skip the lesson completes lesson %d" % n)
		await _end_turn()
		await _close_dialogs()
	_check(tu.lesson_n() == 6, "skip path: five skips, then lesson 6")
	_check(not CState.siege_at(cs.st, sv).is_empty(), "skip path: the skipped orders did the work (the siege is laid)")
	(tu.card.buttons["leave"] as Button).pressed.emit()
	await _frames(3)
	_check(not tu.on() and not tu.card.visible and not tu.pointer.visible, "leave path: Leave the tutorial stops the cards and the pointer")
	_check(not tu.holds_end() and not cs.end_button.disabled, "leave path: End turn is free")
	_check(int(cs.data["session"]["tutorial"]["left"]) == 1 and Tutorial.is_tutorial(cs.st), "leave path: remembered in the session; the state's setting stays (the rules have no settings order)")
	_check(not Tips.suppress, "leave path: the tips are back")
	await _end_turn()
	await _close_dialogs()
	_check(int(cs.st["turn"]) == 6 or not CTurn.pending_for(cs.st).is_empty() or int(cs.st["turn"]) > 5, "leave path: the turn resolves")


# ------------------------------------------------------------ How to play ---

func _howto_menus() -> void:
	var m: Control = (load("res://game/main.gd") as GDScript).new()
	root.add_child(m)
	await _frames(6)
	var b: Button = m.find_child("home_howto", true, false) as Button
	_check(b != null and b.is_visible_in_tree(), "the title menu has a How to play entry")
	b.pressed.emit()
	await _frames(4)
	_check(m.page == "howto", "... it opens the How to play page")
	var panel: Control = m.find_child("howto_panel", true, false)
	_check(panel != null and panel.is_visible_in_tree(), "the page is a trim panel")
	var heads := 0
	for s in Howto.SECTIONS:
		if m.find_child("howto_h_" + str(s["id"]), true, false) != null:
			heads += 1
	_check(heads == 8, "... with the eight sections (%d)" % heads)
	var l: Label = m.find_child("howto_map_1", true, false) as Label
	_check(l != null and l.text == Howto.text("map_1"), "... in the words of howto.gd")
	var vp := m.get_viewport_rect().size
	_check(panel.get_global_rect().size.x <= vp.x + 0.5, "... within the width of the window (%s)" % str(vp))
	m._back_btn.pressed.emit()
	await _frames(2)
	_check(m.page == "home", "Back returns to the title screen")
	m.queue_free()
	await _frames(2)
	# the in-game menus
	await _new_screen(Tutorial.make_state("Menu", Tutorial.SEED, 0), "tutorial_test_c")
	cs.game_menu.open()
	await _frames(2)
	var hb: Button = cs.game_menu.find_child("menu_howto", true, false) as Button
	_check(hb != null, "the campaign Menu has How to play")
	hb.pressed.emit()
	await _frames(3)
	_check(cs.game_menu.page == "howto" and cs.game_menu.find_child("howto_h_sea", true, false) != null, "... it shows the sections")
	cs.game_menu.back()
	await _frames(2)
	_check(cs.game_menu.page == "main", "... Back returns to the Menu's entries")
	cs.game_menu.close()
