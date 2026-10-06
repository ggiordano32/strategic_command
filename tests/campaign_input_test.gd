extends SceneTree
## Scripted input test of the campaign screens (needs a window):
##   godot --script res://tests/campaign_input_test.gd
## Synthetic touches through Godot's input pipeline: hand-over, select an
## army, plan a move and cancel it (tap again), plan an attack, recruit and
## build from the region panel, the unit page from the recruit list, end turn
## through the warnings, the second player's hand-over, the pending battle
## dialog, launching a battle and leaving it (forfeit applied to the state),
## and an auto-resolved battle with the progress dialog applied to the state.
## Sieges: a move into enemy land lays siege by default, the toast's
## "Assault now" switches it; the siege panel's Assault / Maintain and Sally
## buttons with the odds bar.
## Exits 0 on success, 1 on failure.

const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CTurn := preload("res://campaign/cturn.gd")
const Geo := preload("res://game/campaign/map_geo.gd")

var cs: CampaignScreen
var frame := 0
var wait := 0
var failures := 0
var steps: Array[Callable] = []
var rome := CData.faction_index("rome")
var greeks := CData.faction_index("greeks")
var army0 := -1
var army1 := -1
var _poll := 0


func _initialize() -> void:
	Input.use_accumulated_input = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var st := CState.new_campaign("InputTest", 3, [rome, greeks])
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "input_test")
	root.add_child(cs)
	steps = [
		_s_handover, _s_intro, _s_tap_army, _s_check_army, _s_tap_etruria, _s_check_move,
		_s_tap_etruria, _s_check_cancel, _s_tap_army1, _s_tap_apulia, _s_check_siege_default, _s_check_attack,
		_s_tap_roma, _s_check_region, _s_recruit, _s_check_recruit, _s_unit_page, _s_check_unit_page,
		_s_build, _s_check_build, _s_end_turn, _s_warnings, _s_check_handover2, _s_start2, _s_intro,
		_s_end_turn2, _s_summary, _s_check_battles, _s_fight, _s_check_battle_on, _s_leave, _s_leave2,
		_s_check_forfeit, _s_auto_setup, _s_auto_tap, _s_auto_wait, _s_auto_check, _s_refuse_select, _s_refuse_tap, _s_refuse_check, _s_refuse_dip, _s_refuse_war, _s_siege_setup, _s_siege_check, _s_siege_assault_check,
		_s_siege_maintain_check, _s_sally_setup, _s_sally_check, _s_siege_cleanup, _s_controls, _s_controls_check, _s_done,
	]


func _process(_d: float) -> bool:
	frame += 1
	if frame < 8:
		return false
	if wait > 0:
		wait -= 1
		return false
	if steps.is_empty():
		return false
	var s: Callable = steps.pop_front()
	s.call()
	wait = 3
	return false


func _check(c: bool, what: String) -> void:
	if c:
		print("PASS ", what)
	else:
		printerr("FAIL ", what)
		failures += 1


func _win(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func _tap(p: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.position = _win(p)
		e.pressed = pressed
		Input.parse_input_event(e)


func _tap_control(c: Control) -> void:
	# Scroll it into view first (panels and dialogs scroll).
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(c)
			await process_frame
			await process_frame
			break
		p = p.get_parent()
	_tap(c.get_global_rect().get_center())


func _button(name_part: String) -> Button:
	for b in cs.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and (str(b.name).contains(name_part) or (b as Button).text.begins_with(name_part)):
			return b
	return null


func _tap_button(name_part: String, what: String) -> bool:
	var b := _button(name_part)
	_check(b != null, what + " (button %s)" % name_part)
	if b != null:
		_tap_control(b)
	return b != null


func _site(key: String) -> Vector2:
	return cs.overlay.to_screen(Geo.site(CData.region_index(key)))


# ------------------------------------------------------------------ steps ---

func _s_handover() -> void:
	_check(cs.cover.visible and cs.dialog.visible, "hot seat starts with the hand-over screen")
	_tap_button("Start_my_turn", "hand-over: start my turn")


func _s_intro() -> void:
	_check(not cs.cover.visible and cs.dialog.visible, "intro dialog after the hand-over")
	_tap_button("dlg_Start", "intro: start")


func _s_tap_army() -> void:
	var mine := CState.armies_of(cs.ps, rome)
	army0 = int(mine[0]["id"])
	army1 = int(mine[1]["id"])
	cs.focus_region(int(mine[0]["r"]), 0.9)
	await process_frame
	await process_frame
	_tap(cs.overlay.army_positions()[army0])


func _s_check_army() -> void:
	_check(cs.sel_army == army0 and cs.side.visible, "tapping the army banner selects it and opens its panel")
	_check(cs.map_view.targets.has(CData.region_index("etruria")), "Etruria is a highlighted destination")


func _s_tap_etruria() -> void:
	_tap(_site("etruria") + Vector2(0, -30))


func _s_check_move() -> void:
	_check(cs.planned_move(army0) == CData.region_index("etruria"), "tapping a highlighted region plans a move")
	_check(cs.overlay.moves.size() == 1, "the planned move is drawn")


func _s_check_cancel() -> void:
	_check(cs.planned_move(army0) == -1, "tapping the destination again cancels the move")


func _s_tap_army1() -> void:
	var a := CState.army(cs.ps, army1)
	cs.focus_region(int(a["r"]), 0.9)
	await process_frame
	await process_frame
	_tap(cs.overlay.army_positions()[army1])


func _s_tap_apulia() -> void:
	_check(cs.sel_army == army1, "second army selected")
	_check(cs.map_view.attack_targets.has(CData.region_index("apulia")), "Apulia (Epirus, at war) is an attack target")
	_tap(_site("apulia") + Vector2(-20, -25))


func _s_check_siege_default() -> void:
	_check(cs.planned_move(army1) == CData.region_index("apulia") and cs.move_kind(army1) == "siege",
		"a move into enemy land lays siege by default")
	_check(cs.overlay.siege_moves.has(army1), "drawn as a siege")
	var t = cs.find_child("toast", true, false)
	_check(t != null and _button("toast_action") != null and _button("toast_action").text == "Assault now",
		"the toast offers Assault now, one tap away")
	_tap_button("toast_action", "Assault now")


func _s_check_attack() -> void:
	_check(cs.planned_move(army1) == CData.region_index("apulia"), "attack on Apulia planned")
	_check(cs.move_kind(army1) == "assault" and cs.move_mode(army1) == CData.MODE_ASSAULT, "the move now assaults")
	_check(cs.overlay.attack_moves.has(army1) and not cs.overlay.siege_moves.has(army1), "drawn as an attack")


func _s_tap_roma() -> void:
	cs.close_side()
	cs.focus_region(CData.region_index("latium"), 0.9)
	await process_frame
	_tap(_site("latium"))


func _s_check_region() -> void:
	_check(cs.sel_region == CData.region_index("latium") and cs.side.visible, "tapping Roma opens the region panel")


func _s_recruit() -> void:
	_tap_button("recruit_heavy", "recruit heavy swords from the panel")


func _s_check_recruit() -> void:
	var n := 0
	for o in cs.orders:
		if str(o["t"]) == "recruit":
			n += 1
	_check(n == 1 and (cs.ps["regions"][CData.region_index("latium")]["queue"] as Array).size() == 1, "recruit order planned and shown in the queue")
	_check(int(cs.ps["factions"][rome]["treasury"]) == int(cs.st["factions"][rome]["treasury"]) - 600, "the price comes off the previewed treasury")


func _s_unit_page() -> void:
	# Tap the first unit row of the recruit list: the unit book page opens.
	for c in cs.side_box.find_children("*", "Control", true, false):
		if c.get_class() == "Control" and c.has_signal("pressed") and c.get("toggle") == false and c.get("right_text") != "planned" and str(c.get("right_text")) != "":
			_tap_control(c)
			return
	_check(false, "a recruit row to tap")


func _s_check_unit_page() -> void:
	_check(cs.dialog.visible and _button("Recruit (") != null, "the recruit row opens the unit page with a Recruit button")
	_tap_button("dlg_Close", "close the unit page")


func _s_build() -> void:
	for b in cs.side_box.find_children("build_*", "Button", true, false):
		if not (b as Button).disabled:
			_tap_control(b)
			return
	_check(false, "a build button")


func _s_check_build() -> void:
	var n := 0
	for o in cs.orders:
		if str(o["t"]) == "build":
			n += 1
	_check(n == 1 and not (cs.ps["regions"][CData.region_index("latium")]["build"] as Array).is_empty(), "building planned")


func _s_end_turn() -> void:
	cs.close_side()
	_tap_control(cs.end_button)


func _s_warnings() -> void:
	if cs.dialog.visible and _button("dlg_End_turn") != null:
		_check(true, "end-turn warnings shown")
		_tap_button("dlg_End_turn", "end turn anyway")


func _s_check_handover2() -> void:
	_check((cs.data["session"]["subs"] as Array).size() == 1, "Rome's orders are submitted")
	var sub: Dictionary = cs.data["session"]["subs"][0]
	_check(int(sub["f"]) == rome and (sub["orders"] as Array).size() == 3, "the submission holds the plan (%d orders)" % (sub["orders"] as Array).size())
	_check(cs.cover.visible and cs.f == greeks, "hand-over to the Greek player")


func _s_start2() -> void:
	_tap_button("Start_my_turn", "Greek player starts")


func _s_end_turn2() -> void:
	_tap_control(cs.end_button)
	await process_frame
	await process_frame
	if _button("dlg_End_turn") != null:
		_tap_button("dlg_End_turn", "Greek end turn anyway")


func _s_summary() -> void:
	_check(int(cs.st["turn"]) == 1, "both submitted: the turn resolved")
	_check(cs.dialog.visible, "summary dialog for Rome")
	_tap_button("dlg_Continue", "summary continue")


func _s_check_battles() -> void:
	var b := CState.battle_at(cs.st, CData.region_index("apulia"))
	_check(not b.is_empty(), "the attack on Apulia is a pending battle")
	_check(cs.end_button.disabled, "End turn is blocked while a battle is pending")
	_check(_button("fight_") != null and _button("auto_") != null, "pending battle dialog offers Fight and Auto-resolve")


func _s_fight() -> void:
	_tap_button("fight_", "fight the battle")


func _s_check_battle_on() -> void:
	_check(cs.battle != null and cs.battle.is_inside_tree() and cs.battle.campaign_mode, "the battle view opens")
	if cs.battle != null:
		_check(cs.battle.sim.n_units == (cs._battle_built["map"] as Array).size(), "with the campaign's units")


func _s_leave() -> void:
	cs.battle.hud.menu_pressed.emit()


func _s_leave2() -> void:
	_check(cs.battle != null, "first Leave only asks")
	cs.battle.hud.menu_pressed.emit()
	wait = 6


func _s_check_forfeit() -> void:
	_check(cs.battle == null and CState.battle_at(cs.st, CData.region_index("apulia")).is_empty(), "leaving applies the battle (forfeit)")
	var last: Dictionary = {}
	for e in cs.st["events"]:
		if str(e["k"]) == "battle":
			last = e
	_check(not last.is_empty() and int(last["winner"]) == 1, "the forfeit counts as a defeat for the attacker")
	_check(cs.dialog.visible, "battle result shown")
	_tap_button("dlg_Continue", "result continue")


func _s_auto_setup() -> void:
	# A fresh pending battle: a small Roman army attacks Venetia.
	var st: Dictionary = cs.st
	if not (st["battles"] as Array).is_empty() or str(st["phase"]) != "plan":
		_check(false, "no battles left before the auto-resolve setup")
	var id := CRules.new_army_id(st, rome)
	st["factions"][rome]["next_army"] = int(st["factions"][rome]["next_army"]) + 1
	var a := {"id": id, "f": rome, "r": CData.region_index("venetia"), "units": [{"t": "heavy", "n": 100}, {"t": "heavy", "n": 100}, {"t": "cav", "n": 60}],
		"from": CData.region_index("cisalpina"), "moved": 1, "busy": 0}
	CRules._insert_army(st, a)
	CRules.start_battle(st, CData.region_index("venetia"), a)
	st["phase"] = "battles"
	cs._next_step()


func _s_auto_tap() -> void:
	if _button("dlg_Continue") != null:
		_tap_button("dlg_Continue", "summary before battles")
		steps.push_front(_s_auto_tap)
		return
	_tap_button("auto_", "auto-resolve")


func _s_auto_wait() -> void:
	if cs._resolver != null and _poll < 2000:
		_poll += 1
		if _poll == 2:
			_check(cs._progress != null and cs.dialog.visible, "progress dialog during auto-resolve")
		steps.push_front(_s_auto_wait)
		wait = 1


func _s_auto_check() -> void:
	_check(CState.battle_at(cs.st, CData.region_index("venetia")).is_empty(), "auto-resolve result applied")
	var ok := false
	for e in cs.st["events"]:
		if str(e["k"]) == "battle" and str(e["mode"]) == "auto":
			ok = true
	_check(ok, "battle event recorded as auto")
	_tap_button("dlg_Continue", "auto result continue")


func _s_refuse_select() -> void:
	cs.close_dialog()
	var a: Dictionary = CState.army(cs.ps, army0)
	cs.select_army(army0)
	cs.focus_region(CData.region_index("sardinia"), 0.9)
	_check(int(a["r"]) == CData.region_index("latium"), "army still in Latium")


func _s_refuse_tap() -> void:
	var sar := CData.region_index("sardinia")
	_check(cs.map_view.blocked_targets.has(sar) and not cs.map_view.targets.has(sar),
		"Sardinia (Carthage, at peace) is shown as blocked")
	_tap(_site("sardinia") + Vector2(0, -20))


func _s_refuse_check() -> void:
	var t = cs.find_child("toast", true, false)
	_check(t != null and t.visible, "tapping a blocked region explains why")
	if t != null:
		var txt := ""
		for l in t.find_children("*", "Label", true, false):
			txt += (l as Label).text
		_check(txt.contains("Carthage") and txt.contains("Diplomacy"), "the reason names Carthage and the way forward: " + txt.substr(0, 80))
	_check(cs.planned_move(army0) < 0, "and plans no move")
	_tap_button("toast_action", "the toast's Diplomacy shortcut")


func _s_refuse_dip() -> void:
	_check(cs.dialog.visible and cs.dialog_title.text == "Diplomacy", "the shortcut opens Diplomacy")
	_check(cs.dialog_box.find_child("dip_carthage", true, false) != null, "with Carthage's row")
	cs.close_dialog()
	cs.add_order({"t": "war", "to": CData.faction_index("carthage")})


func _s_refuse_war() -> void:
	cs.select_army(army0)
	_check(cs.map_view.targets.has(CData.region_index("sardinia")),
		"with war planned this turn, Sardinia becomes a move target at once")
	cs.remove_orders(func(o): return str(o["t"]) == "war")
	cs.close_side()


var _siege_r := -1


func _s_siege_setup() -> void:
	# Rome's first army has laid siege to Corsica (independent).
	_siege_r = CData.region_index("corsica")
	var a := CState.army(cs.st, army0)
	var left := int(a["r"])
	a["r"] = _siege_r
	CRules.start_siege(cs.st, _siege_r, a, left)
	cs._replan()
	cs.focus_region(_siege_r, 0.9)
	cs.select_region(_siege_r)
	await process_frame
	await process_frame
	var p = cs.side_box.find_child("siege_panel", true, false)
	_check(p != null and cs.side_box.find_child("odds_bar", true, false) != null, "the besieged city's panel shows the siege and the odds bar")
	var ab := _button("siege_assault")
	_check(ab != null and not ab.disabled and _button("siege_maintain").disabled, "Assault is offered, Maintain is the current order")
	_tap_button("siege_assault", "order the assault")


func _s_siege_check() -> void:
	var n := 0
	for o in cs.orders:
		if str(o["t"]) == "assault" and int(o["r"]) == _siege_r:
			n += 1
	_check(n == 1, "the assault order is planned")
	var mb := _button("siege_maintain")
	_check(mb != null and not mb.disabled and _button("siege_assault").disabled, "Maintain is now offered")
	_tap_button("siege_maintain", "keep up the siege instead")


func _s_siege_assault_check() -> void:
	var n := 0
	for o in cs.orders:
		if str(o["t"]) == "assault":
			n += 1
	_check(n == 0, "Maintain removes the assault order")


func _s_siege_maintain_check() -> void:
	# The besieging army's panel says what it does.
	cs.select_army(army0)
	await process_frame
	_check(_button("army_siege") != null, "the besieging army's panel links to its siege")


func _s_sally_setup() -> void:
	# An Epirote army lays siege to Samnium (Rome's); Rome may sally.
	var st: Dictionary = cs.st
	var ep := CData.faction_index("epirus")
	var sa := CData.region_index("samnium")
	var id := CRules.new_army_id(st, ep)
	st["factions"][ep]["next_army"] = int(st["factions"][ep]["next_army"]) + 1
	CRules._insert_army(st, {"id": id, "f": ep, "r": sa, "units": [{"t": "heavy", "n": 100}], "from": -1, "moved": 0, "busy": 0})
	CRules.start_siege(st, sa, CState.army(st, id), CData.region_index("apulia"))
	cs._replan()
	cs.select_region(sa)
	await process_frame
	await process_frame
	var sb := _button("siege_sally")
	_check(sb != null and not sb.disabled and cs.side_box.find_child("odds_bar", true, false) != null, "the defender's panel offers Sally with the odds")
	_tap_button("siege_sally", "order a sally")


func _s_sally_check() -> void:
	var n := 0
	for o in cs.orders:
		if str(o["t"]) == "sally":
			n += 1
	_check(n == 1 and _button("siege_sally") != null and _button("siege_sally").text == "Cancel sally", "the sally is planned (Cancel sally)")


func _s_siege_cleanup() -> void:
	cs.remove_orders(func(o): return str(o["t"]) == "sally" or str(o["t"]) == "assault")
	var st: Dictionary = cs.st
	st["sieges"] = []
	var keep: Array = []
	for a in st["armies"]:
		if int(a["f"]) != CData.faction_index("epirus") or int(a["r"]) != CData.region_index("samnium"):
			keep.append(a)
	st["armies"] = keep
	CState.army(st, army0)["r"] = CData.region_index("latium")
	cs._replan()
	cs.close_side()


func _s_controls() -> void:
	cs.panels.show_menu()
	await process_frame
	_tap_button("Controls", "campaign menu has Controls")


func _s_controls_check() -> void:
	_check(cs.controls_page.visible, "Controls opens from the campaign map")
	_tap_control(cs.controls_page.close_button)


func _s_done() -> void:
	_check(not cs.controls_page.visible, "Controls closes")
	_check(str(cs.st["phase"]) == "plan" and not cs.end_button.disabled, "planning resumes")
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
