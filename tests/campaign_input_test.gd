extends SceneTree
## Scripted input test of the campaign screens (needs a window):
##   godot --script res://tests/campaign_input_test.gd
## Synthetic touches through Godot's input pipeline: hand-over, select an
## army, plan a move and cancel it (tap again), plan an attack, recruit and
## build from the region panel, the unit page from the recruit list, end turn
## through the warnings, the second player's hand-over, the pending battle
## dialog, launching a battle and leaving it (forfeit applied to the state),
## and an auto-resolved battle with the progress dialog applied to the state.
## Sieges: the siege panel's Assault / Maintain and Sally buttons with the
## odds bar. Free movement (format 5): a move into enemy land marches in
## (raids) by default and the toast's Lay siege / Assault switch it; a
## two-turn march drawn solid then dotted with its arrival in the army card;
## the stance toggle; Cancel move; a march stored from an earlier turn and
## stopping it; the raided region's note and its Lay siege button; a field
## battle (interception) in the Battles list with the odds bar.
## (All of the above on a format 5 copy of the new campaign: the screens of
## an unmigrated online campaign of that format.)
## Format 6 (the continuous overworld), a solo campaign: selecting an army
## shades its reach and draws the enemies' zones and its links; a tap on
## land plans a march to that cell (x, y) drawn along the cells; the same
## spot again cancels it; Undo brings it back; a tap on an enemy army plans
## an attack (tgt); a tap on a hostile city a siege, with the army card's
## on-arrival Assault switch; a tap on our own city goes inside; the stance
## selector; a drag from an army plans a march, a drag elsewhere pans; the
## siege panel's Assault / Continue siege / Withdraw; a resolved turn
## replays the step log and a tap skips it. Merging and exchanging: the
## army card's Merge into / Exchange units at the top, the exchange panel
## (tap a unit across, the counts, Confirm adds the order, Undo takes it
## back), a tap on our other army previews the merge (caption, glyphs) and
## a second tap merges (next to it: a merge order; further: a march with
## "join"), a tap on the allied player's army next to ours opens the panel
## in gift mode. Recruiting (format 6): the army card of an army at our
## city has the recruit list (slots, "+", the planned recruit greyed in the
## unit list with X); a march planned for it asks in a toast (Keep
## recruiting / Cancel recruits and march); with a march planned the list
## is off; the region panel has no recruit list but the garrison, what the
## city trains and Raise new army (the picker: +, the count, Raise army;
## the planned army with X). The map key: format 5 rows on the format 5 copy; on the
## overworld the Key button opens it (its version 6 rows, clear of End turn
## and the hint), a tap on the map closes it on a phone, its header closes it.
## Exits 0 on success, 1 on failure.

const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CTurn := preload("res://campaign/cturn.gd")
const Geo := preload("res://game/campaign/map_geo.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const MapOverlay := preload("res://game/campaign/map_overlay.gd")
const UiScale := preload("res://game/ui_scale.gd")

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
	var st := CState.as_format(CState.new_campaign("InputTest", 3, [rome, greeks]), 5)
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "input_test")
	root.add_child(cs)
	_key_off()
	steps = [
		_s_handover, _s_intro, _s_tap_army, _s_check_army, _s_tap_etruria, _s_check_move,
		_s_tap_etruria, _s_check_cancel, _s_tap_army1, _s_tap_apulia, _s_check_siege_default, _s_check_attack,
		_s_tap_roma, _s_check_region, _s_recruit, _s_check_recruit, _s_unit_page, _s_check_unit_page,
		_s_build, _s_check_build, _s_end_turn, _s_warnings, _s_check_handover2, _s_start2, _s_intro,
		_s_end_turn2, _s_summary, _s_check_battles, _s_fight, _s_check_battle_on, _s_leave, _s_leave2,
		_s_check_forfeit, _s_auto_setup, _s_auto_tap, _s_auto_wait, _s_auto_check, _s_refuse_select, _s_refuse_tap, _s_refuse_check, _s_refuse_dip, _s_refuse_war, _s_siege_setup, _s_siege_check, _s_siege_assault_check,
		_s_siege_maintain_check, _s_sally_setup, _s_sally_check, _s_siege_cleanup,
		_s_march_tap, _s_march_check, _s_stance_inside, _s_stance_check, _s_stance_field, _s_cancel_tap, _s_cancel_check,
		_s_stored_setup, _s_stored_stop, _s_stored_check, _s_raid_setup, _s_raid_siege, _s_raid_check, _s_field_battle, _s_field_check,
		_s_controls, _s_controls_check, _k5_check, _s_done5,
		_g_setup, _g_intro, _k_open, _k_check, _k_tap_map, _k_reopen, _k_closed, _g_select, _g_tap_land, _g_check_land, _g_cancel, _g_undo, _g_attack, _g_attack_check,
		_g_city, _g_city_check, _g_arrive_assault, _g_inside, _g_inside_check, _g_stance, _g_stance_check,
		_g_drag_army, _g_drag_check, _g_pan, _g_pan_check, _g_siege, _g_siege_assault, _g_siege_continue, _g_siege_withdraw,
		_g_siege_done, _g_end_turn, _g_summary, _g_replay, _g_replay_check,
		_m_setup, _m_card, _m_xc_open, _m_xc_move, _m_xc_confirm, _m_xc_check, _m_undo, _m_tap1, _m_tap2, _m_merged,
		_m_far, _m_far1, _m_far2, _m_far_check, _m_gift_setup, _m_gift_tap, _m_gift_row, _m_gift_confirm, _m_gift_check,
		_r_setup, _r_card, _r_check, _r_march, _r_keep, _r_march2, _r_cancel_march, _r_marching, _r_again, _r_x, _r_x_check,
		_r_region, _r_picker, _r_picker2, _r_picker3, _r_raise_check, _r_raise_x, _s_done,
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
	_check(cs.overlay.paths.size() == 1 and int(cs.overlay.paths[0]["now"]) == 1, "the planned march is drawn (one hop, this turn)")


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
	_check(cs.planned_move(army1) == CData.region_index("apulia") and cs.move_kind(army1) == "raid",
		"a move into enemy land marches in (raids) by default")
	_check(not cs.overlay.siege_moves.has(army1) and not cs.overlay.attack_moves.has(army1), "drawn as a march")
	var t = cs.find_child("toast", true, false)
	_check(t != null and _button("toast_action") != null and _button("toast_action").text == "Lay siege"
		and _button("toast_action2") != null and _button("toast_action2").text == "Assault",
		"the toast offers Lay siege and Assault, one tap away")
	var txt := ""
	if t != null:
		for l in t.find_children("*", "Label", true, false):
			txt += (l as Label).text
	_check(txt.contains("half its income") and txt.contains("must be beaten first"), "it says raiding costs them half the income, and that their field army must be fought first: " + txt.substr(0, 120))
	_tap_button("toast_action2", "Assault")


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


# --------------------------------------------------------- free movement ---

func _s_march_tap() -> void:
	# Rome's first army (Latium) marches to Corsica: Etruria this turn, the
	# sea lane next turn.
	cs.close_side()
	cs.select_army(army0)
	cs.focus_region(CData.region_index("etruria"), 0.7)
	await process_frame
	await process_frame
	_check(cs.map_view.targets.has(CData.region_index("corsica")) and int(cs.map_view.target_turns.get(CData.region_index("corsica"), -1)) == 1,
		"Corsica is a destination for next turn (dim)")
	_tap(_site("corsica"))


func _s_march_check() -> void:
	var co := CData.region_index("corsica")
	_check(cs.planned_move(army0) == co, "tapping a region two hops away plans the march")
	var mo := {}
	for o in cs.orders:
		if str(o["t"]) == "move" and int(o["army"]) == army0:
			mo = o
	_check(int(mo.get("persist", 0)) == 1 and int(mo.get("mode", -1)) == CData.MODE_MARCH, "the order marches on over the turns (persist)")
	var pth: Dictionary = {}
	for p in cs.overlay.paths:
		if int(p["army"]) == army0:
			pth = p
	_check(not pth.is_empty() and (pth["pts"] as Array).size() == 3 and int(pth["now"]) == 1,
		"drawn solid to Etruria (this turn), dotted on to Corsica")
	var txt := ""
	for l in cs.side_box.find_children("*", "Label", true, false):
		txt += (l as Label).text + " "
	_check(txt.contains("arrives next turn") and cs.side_box.find_child("army_points", true, false) != null,
		"the army card says when it arrives and shows its points")


func _s_stance_inside() -> void:
	cs.set_move(army0, cs.planned_move(army0))  # cancel the march first
	cs.select_army(army0)
	await process_frame
	_tap_button("stance_inside", "Inside the walls")


func _s_stance_check() -> void:
	var n := 0
	for o in cs.orders:
		if str(o["t"]) == "stance" and int(o["a"]) == army0 and int(o["s"]) == CData.STANCE_GARRISON:
			n += 1
	_check(n == 1 and CState.stance(CState.army(cs.ps, army0)) == CData.STANCE_GARRISON, "the stance order shelters the army inside Roma's walls")
	_check(_button("stance_field") != null and not _button("stance_field").disabled and _button("stance_inside").text.ends_with("(now)"), "In the field is offered back")


func _s_stance_field() -> void:
	_tap_button("stance_field", "In the field")


func _s_cancel_tap() -> void:
	var n := 0
	for o in cs.orders:
		if str(o["t"]) == "stance":
			n += 1
	_check(n == 0 and CState.stance(CState.army(cs.ps, army0)) == CData.STANCE_FIELD, "back in the field: the stance order is gone")
	cs.set_move(army0, CData.region_index("campania"))
	cs.select_army(army0)
	await process_frame
	_tap_button("cancel_move", "Cancel move")


func _s_cancel_check() -> void:
	_check(cs.planned_move(army0) == -1, "Cancel move in the army card drops the march")


func _s_stored_setup() -> void:
	# A march stored from an earlier turn.
	var a := CState.army(cs.st, army0)
	a["dest"] = CData.region_index("corsica")
	a["mode"] = CData.MODE_MARCH
	cs._replan()
	cs.select_army(army0)
	await process_frame
	var txt := ""
	for l in cs.side_box.find_children("*", "Label", true, false):
		txt += (l as Label).text + " "
	_check(cs.planned_move(army0) == CData.region_index("corsica") and txt.contains("from an earlier turn"),
		"a march from an earlier turn shows in the army card")
	_check(cs.overlay.paths.size() >= 1, "and on the map")


func _s_stored_stop() -> void:
	_tap_button("cancel_move", "Cancel move (stored march)")


func _s_stored_check() -> void:
	var n := 0
	for o in cs.orders:
		if str(o["t"]) == "cancel_move" and int(o["army"]) == army0:
			n += 1
	_check(n == 1 and cs.planned_move(army0) == -1, "stopping it is a cancel_move order")
	cs.remove_orders(func(o): return str(o["t"]) == "cancel_move")
	CState.army(cs.st, army0)["dest"] = -1
	cs._replan()


var _raid_r := -1


func _s_raid_setup() -> void:
	# Rome's second army stands in Apulia (Epirus) without a siege; the
	# Epirote army there is inside the walls.
	_raid_r = CData.region_index("apulia")
	var a := CState.army(cs.st, army1)
	if a.is_empty():
		var mine := CState.armies_of(cs.st, rome)
		a = mine[mine.size() - 1]
		army1 = int(a["id"])
	a["r"] = _raid_r
	for e in CState.armies_in(cs.st, _raid_r):
		if int(e["f"]) == CData.faction_index("epirus"):
			e["stance"] = CData.STANCE_GARRISON
	cs._replan()
	cs.select_region(_raid_r)
	await process_frame
	await process_frame
	var note = cs.side_box.find_child("raided_note", true, false)
	_check(note != null and (note as Label).text.begins_with("Raided by Rome"), "the region panel says it is raided (half income)")
	_check(cs.side_box.find_child("raid_panel", true, false) != null and _button("raid_siege") != null and not _button("raid_siege").disabled,
		"the raiding armies may lay siege from here")
	_tap_button("raid_siege", "Lay siege from inside")


func _s_raid_siege() -> void:
	var n := 0
	for o in cs.orders:
		if str(o["t"]) == "siege" and int(o["r"]) == _raid_r:
			n += 1
	_check(n == 1 and _button("raid_siege") != null and _button("raid_siege").text == "Cancel siege", "the siege order is planned (Cancel siege)")
	_tap_button("raid_siege", "cancel the siege order")


func _s_raid_check() -> void:
	var n := 0
	for o in cs.orders:
		if str(o["t"]) == "siege":
			n += 1
	_check(n == 0, "Cancel siege removes it")
	var a := CState.army(cs.st, army1)
	a["r"] = CData.region_index("samnium")
	cs._replan()
	cs.close_side()


func _s_field_battle() -> void:
	# An Epirote army marching into Samnium ran into Rome's field army there.
	var st: Dictionary = cs.st
	var ep := CData.faction_index("epirus")
	var id := CRules.new_army_id(st, ep)
	st["factions"][ep]["next_army"] = int(st["factions"][ep]["next_army"]) + 1
	CRules._insert_army(st, {"id": id, "f": ep, "r": CData.region_index("apulia"), "units": [{"t": "pike", "n": 120}, {"t": "cav", "n": 60}],
		"from": -1, "moved": 0, "busy": 0})
	var defn := CState.army(st, army1)
	defn["r"] = CData.region_index("samnium")
	defn["stance"] = CData.STANCE_FIELD
	CRules.execute_moves(st, [[id, CData.region_index("samnium"), ep, CData.MODE_MARCH, 0]])
	var b := CState.battle_at(st, CData.region_index("samnium"))
	_check(not b.is_empty() and str(b.get("kind", "")) == "field", "the interception is a pending field battle")
	b.erase("new")
	st["phase"] = "battles"
	cs._next_step()


func _s_field_check() -> void:
	if _button("dlg_Continue") != null:
		_tap_button("dlg_Continue", "summary before battles")
		steps.push_front(_s_field_check)
		return
	var txt := ""
	for l in cs.dialog_box.find_children("*", "Label", true, false):
		txt += (l as Label).text + " "
	_check(cs.dialog.visible and txt.contains("Field battle in Samnium") and cs.dialog_box.find_child("odds_bar", true, false) != null,
		"the Battles list shows the field battle with the odds bar")
	# Clean up: drop the battle.
	var st: Dictionary = cs.st
	for a in st["armies"]:
		a["busy"] = 0
	st["battles"] = []
	st["phase"] = "plan"
	cs.close_dialog()
	cs._next_step()


func _s_controls() -> void:
	cs.panels.show_menu()
	await process_frame
	_tap_button("Controls", "campaign menu has Controls")


func _s_controls_check() -> void:
	_check(cs.controls_page.visible, "Controls opens from the campaign map")
	_tap_control(cs.controls_page.close_button)


func _s_done5() -> void:
	_check(not cs.controls_page.visible, "Controls closes")
	_check(str(cs.st["phase"]) == "plan" and not cs.end_button.disabled, "planning resumes")


func _s_done() -> void:
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)

# ------------------------------------------------- the overworld (format 6) ---

var g0 := -1   # Rome's army in Latium
var g1 := -1   # Rome's army in Samnium
var _off := Vector2.ZERO
var _corsica := -1


func _cell_screen(c: int) -> Vector2:
	return cs.overlay.to_screen(MapOverlay.cell_point(c))


func _move_order(id: int) -> Dictionary:
	for o in cs.orders:
		if str(o["t"]) == "move" and int(o["army"]) == id:
			return o
	return {}


# ------------------------------------------------------------- map key ---

## The test never saves the key's open / closed preference and starts closed.
func _key_off() -> void:
	if not cs.is_node_ready():
		cs.ready.connect(_key_off, CONNECT_ONE_SHOT)
		return
	cs.map_key.persist = false
	cs.map_key.set_expanded(false)


func _k5_check() -> void:
	var k := cs.map_key
	_check(k.format == 5 and k.row_count() >= 15, "format 5: the map key has the free-movement rows (%d)" % k.row_count())
	var has_route := false
	for r in k.rows():
		has_route = has_route or str(r[0]) == "Land route"
	_check(has_route, "format 5: the key explains the land routes")


func _k_open() -> void:
	_check(cs.map_key.button.is_visible_in_tree() and not cs.map_key.panel.visible, "the map key starts closed: a Key button")
	_tap_button("map_key_button", "open the map key")


func _k_check() -> void:
	var k := cs.map_key
	_check(k.expanded and k.panel.is_visible_in_tree(), "the Key button opens the map key")
	_check(k.format == 6 and k.row_count() >= 25, "format 6: the key has the overworld rows (%d)" % k.row_count())
	var pr := k.panel.get_global_rect()
	_check(not pr.intersects(cs.end_button.get_global_rect()), "the key does not cover End turn")
	_check(cs.hint.text == "" or not pr.intersects(cs.hint.get_global_rect()), "the key does not cover the hint")
	_check(pr.position.y >= cs.TOP_H, "the key stays under the top bar")
	UiScale._touch_override = 1  # a phone: a tap on the map closes the key
	_tap(cs._vp() * Vector2(0.6, 0.5))


func _k_tap_map() -> void:
	UiScale._touch_override = -1
	_check(not cs.map_key.expanded and cs.map_key.button.is_visible_in_tree(), "on a phone a tap on the map closes the key")
	_check(cs.sel_army == -1, "that tap only closed the key")
	_tap_button("map_key_button", "open the map key again")


func _k_reopen() -> void:
	_check(cs.map_key.expanded, "the key opens again")
	_tap_button("map_key_header", "close the key by its header")


func _k_closed() -> void:
	_check(not cs.map_key.expanded and not cs.map_key.panel.visible, "its header closes the key")


func _g_setup() -> void:
	cs.queue_free()
	var st := CState.new_campaign("Overworld", 3, [rome])
	_check(CState.grid_on(st), "a new campaign is on the overworld grid (format %d)" % int(st["version"]))
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "input_test6")
	root.add_child(cs)
	_key_off()
	wait = 6


func _g_intro() -> void:
	if cs.dialog.visible:
		_tap_button("dlg_Start", "intro: start")
	var mine := CState.armies_of(cs.ps, rome)
	g0 = int(mine[0]["id"])
	g1 = int(mine[1]["id"])


func _g_select() -> void:
	cs.focus_region(CData.region_index("latium"), 1.1)
	await process_frame
	await process_frame
	_tap(cs.overlay.army_positions()[g0])
	await process_frame
	await process_frame
	_check(cs.sel_army == g0 and cs.side.visible, "tapping the banner selects the army")
	_check(not cs.map_view.reach_loops.is_empty(), "its reach this turn is drawn (%d outline(s))" % cs.map_view.reach_loops.size())
	_check(not cs.overlay.zones.is_empty(), "the zones of the enemy armies are drawn (%d)" % cs.overlay.zones.size())


func _g_tap_land() -> void:
	_tap(_cell_screen(CState.field_cell(CData.region_index("etruria"))))


func _g_check_land() -> void:
	var c := CState.field_cell(CData.region_index("etruria"))
	var o := _move_order(g0)
	_check(not o.is_empty() and int(o.get("x", -1)) == CGrid.cx(c) and int(o.get("y", -1)) == CGrid.cy(c) and int(o.get("persist", 0)) == 1,
		"a tap on land plans a march to that cell: %s" % str(o))
	_check(cs.overlay.paths6.size() == 1 and int(cs.overlay.paths6[0]["now"]) == (cs.overlay.paths6[0]["pts"] as Array).size() - 1,
		"the path is drawn along the cells, all of it this turn")
	_check(cs.undo_button.visible, "Undo is offered")
	_tap(_cell_screen(c))


func _g_cancel() -> void:
	_check(_move_order(g0).is_empty() and cs.overlay.paths6.is_empty(), "the same spot again cancels the march")
	_tap_control(cs.undo_button)


func _g_undo() -> void:
	_check(not _move_order(g0).is_empty(), "Undo brings the march back")
	cs.remove_orders(func(o): return str(o["t"]) == "move")
	cs.close_side()
	cs.focus_region(CData.region_index("apulia"), 1.1)
	await process_frame
	await process_frame
	_tap(cs.overlay.army_positions()[g1])


func _g_attack() -> void:
	_check(cs.sel_army == g1, "the Samnite army selected")
	var att := 0
	for ln in cs.overlay.links:
		if int(ln[2]) == 1:
			att += 1
	_check(att > 0, "a red line to the enemy army it can attack this turn (%d links)" % cs.overlay.links.size())
	var ep := -1
	for a in cs.ps["armies"]:
		if int(a["f"]) == CData.faction_index("epirus") and int(a["r"]) == CData.region_index("apulia"):
			ep = int(a["id"])
	_check(ep >= 0, "an Epirote army stands in Apulia")
	if ep >= 0:
		_tap(cs.overlay.army_positions()[ep])


func _g_attack_check() -> void:
	var o := _move_order(g1)
	_check(int(o.get("tgt", -1)) >= 0 and cs.move_kind(g1) == "attack", "a tap on an enemy army plans an attack on it: %s" % str(o))
	_check(not cs.overlay.paths6.is_empty() and str(cs.overlay.paths6[0]["kind"]) == "attack", "drawn as an attack")
	_tap(cs.overlay.to_screen(cs.overlay.site_point(CData.region_index("apulia"))))


func _g_city() -> void:
	pass


func _g_city_check() -> void:
	var o := _move_order(g1)
	var s := CGrid.site(CData.region_index("apulia"))
	_check(int(o.get("x", -1)) == CGrid.cx(s) and int(o.get("y", -1)) == CGrid.cy(s) and int(o.get("tgt", -1)) < 0
		and cs.move_kind(g1) == "siege", "a tap on Tarentum plans a siege on arrival: %s (%s)" % [str(o), cs.move_kind(g1)])
	_check(_button("arrive_assault") != null and _button("cancel_move") != null, "the army card offers Assault on arrival and Cancel move")
	_check(cs.find_child("toast", true, false) == null, "no move-mode toast")
	_tap_button("arrive_assault", "Assault on arrival")


func _g_arrive_assault() -> void:
	_check(cs.move_mode(g1) == CData.MODE_ASSAULT and cs.move_kind(g1) == "assault", "the march now storms the city on arrival")
	cs.remove_orders(func(o): return str(o["t"]) == "move")
	cs.close_side()
	cs.focus_region(CData.region_index("latium"), 1.1)
	await process_frame
	await process_frame
	cs.select_army(g0)
	await process_frame
	_tap(cs.overlay.to_screen(cs.overlay.site_point(CData.region_index("latium"))))


func _g_inside() -> void:
	pass


func _g_inside_check() -> void:
	_check(cs.move_kind(g0) == "inside", "a tap on our own city goes inside the walls (%s)" % cs.move_kind(g0))
	cs.remove_orders(func(o): return str(o["t"]) == "move")
	cs.select_army(g0)


func _g_stance() -> void:
	_check(_button("stance_0") != null and _button("stance_2") != null and _button("stance_3") != null and _button("stance_4") != null,
		"the army card has the stance selector")
	_check(_button("stance_inside") == null and _button("stance_field") == null, "no inside / field toggle")
	_tap_button("stance_2", "Forced march")


func _g_stance_check() -> void:
	var n := 0
	for o in cs.orders:
		if str(o["t"]) == "stance" and int(o["a"]) == g0 and int(o["s"]) == CData.ST_FORCED:
			n += 1
	var a := CState.army(cs.ps, g0)
	_check(n == 1 and CState.stance(a) == CData.ST_FORCED and CState.mp(a) > CData.MP6_FOOT, "forced march: the order, more points (%d)" % CState.mp(a))
	_tap_button("stance_0", "back to Default")
	await process_frame
	await process_frame
	var n2 := 0
	for o in cs.orders:
		if str(o["t"]) == "stance":
			n2 += 1
	_check(n2 == 0, "back to Default drops the stance order")


func _drag(from: Vector2, to: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = _win(from)
	e.pressed = true
	Input.parse_input_event(e)
	for k in range(1, 9):
		var d := InputEventScreenDrag.new()
		d.index = 0
		var p := from.lerp(to, k / 8.0)
		d.position = _win(p)
		d.relative = (to - from) / 8.0
		Input.parse_input_event(d)
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.position = _win(to)
	u.pressed = false
	Input.parse_input_event(u)


func _g_drag_army() -> void:
	cs.close_side()
	await process_frame
	var c := CState.field_cell(CData.region_index("campania"))
	_drag(cs.overlay.army_positions()[g0], _cell_screen(c))


func _g_drag_check() -> void:
	var c := CState.field_cell(CData.region_index("campania"))
	var o := _move_order(g0)
	_check(int(o.get("x", -1)) == CGrid.cx(c) and int(o.get("y", -1)) == CGrid.cy(c), "dragging the army to a spot plans its march there: %s" % str(o))
	_check(cs.overlay.drag.is_empty(), "the drag preview is gone after the release")
	cs.remove_orders(func(o2): return str(o2["t"]) == "move")
	cs.close_side()
	_off = cs.offset


func _g_pan() -> void:
	var p := _cell_screen(CState.field_cell(CData.region_index("latium"))) + Vector2(0, 120)
	_drag(p, p + Vector2(-90, 10))


func _g_pan_check() -> void:
	_check(cs.offset != _off and _move_order(g0).is_empty() and _move_order(g1).is_empty(), "a drag elsewhere pans the map and plans nothing")


func _g_siege() -> void:
	# Rome's first army lays siege to Aleria (Corsica, independent).
	_corsica = CData.region_index("corsica")
	var a := CState.army(cs.st, g0)
	CState.place(a, CState.ring_cell(_corsica, 0))
	CRules.start_siege(cs.st, _corsica, a, CData.region_index("latium"))
	cs._replan()
	cs.focus_region(_corsica, 1.1)
	cs.select_region(_corsica)
	await process_frame
	await process_frame
	_check(cs.side_box.find_child("siege_panel", true, false) != null and cs.side_box.find_child("odds_bar", true, false) != null,
		"the besieged city's panel shows the siege with the odds")
	_check(_button("siege_assault") != null and _button("siege_continue") != null and _button("siege_withdraw") != null
		and _button("siege_maintain") == null and _button("siege_sally") == null, "Assault / Continue siege / Withdraw (no Maintain, no Sally)")
	_tap_button("siege_assault", "Assault")


func _g_siege_assault() -> void:
	var n := 0
	for o in cs.orders:
		if str(o["t"]) == "assault" and int(o["r"]) == _corsica:
			n += 1
	_check(n == 1 and not _button("siege_continue").disabled, "the assault is ordered; Continue siege is offered")
	_tap_button("siege_continue", "Continue siege")


func _g_siege_continue() -> void:
	var n := 0
	for o in cs.orders:
		if str(o["t"]) == "assault":
			n += 1
	_check(n == 0, "Continue siege drops the assault")
	_tap_button("siege_withdraw", "Withdraw")


func _g_siege_withdraw() -> void:
	var o := _move_order(g0)
	var l = cs.side_box.find_child("siege_orders", true, false)
	_check(not o.is_empty() and l != null and (l as Label).text.contains("withdraw"), "Withdraw orders the besiegers away: %s" % str(o))


func _g_siege_done() -> void:
	cs.remove_orders(func(o): return str(o["t"]) == "move")
	cs.st["sieges"] = []
	CState.place(CState.army(cs.st, g0), CState.field_cell(CData.region_index("latium")))
	cs._replan()
	cs.close_side()
	# Plan a march for the replay.
	cs.set_move6(g0, CState.field_cell(CData.region_index("etruria")), -1)


func _g_end_turn() -> void:
	_tap_control(cs.end_button)
	await process_frame
	await process_frame
	if _button("dlg_End_turn") != null:
		_tap_button("dlg_End_turn", "end turn anyway")


func _g_summary() -> void:
	_check(int(cs.st["turn"]) == 1, "the turn resolved")
	if cs.dialog.visible and _button("dlg_Continue") != null:
		_tap_button("dlg_Continue", "summary continue")
	elif cs.dialog.visible:
		cs.close_dialog()


func _g_replay() -> void:
	_check(not cs.replay.is_empty(), "the turn replays from the step log (%d rounds)" % (cs.replay.get("rounds", []) as Array).size())
	_check(not cs.overlay.replay_pos.is_empty(), "armies are drawn on their way")
	_tap(Vector2(300, 400))


func _g_replay_check() -> void:
	_check(cs.replay.is_empty() and cs.overlay.replay_pos.is_empty(), "a tap skips the replay")
	_check(int(CState.army(cs.st, g0).get("r", -1)) == CData.region_index("etruria"), "the army marched to Etruria")


# ----------------------------------------- merge, exchange, gift (format 6) ---

var _ally := -1
var _ally_army := -1


func _neighbour(c0: int) -> int:
	for k in 8:
		var c := CGrid.at(CGrid.cx(c0) + CGrid.DX[k], CGrid.cy(c0) + CGrid.DY[k])
		if c >= 0 and CGrid.passable(c) and CGrid.step_cost(c0, c) > 0 and CGrid.site_region(c) < 0:
			return c
	return -1


func _m_setup() -> void:
	if cs.dialog.visible:
		cs.close_dialog()
	cs.orders = []
	var c0 := CState.field_cell(CData.region_index("latium"))
	CState.place(CState.army(cs.st, g0), c0)
	CState.place(CState.army(cs.st, g1), _neighbour(c0))
	CState.army(cs.st, g0)["dest_x"] = -1
	CState.army(cs.st, g0)["dest_y"] = -1
	cs._replan()
	cs.close_side()
	cs.focus_region(CData.region_index("latium"), 1.6)
	await process_frame
	await process_frame
	cs.select_army(g0)


func _m_card() -> void:
	var mb := _button("merge_into_%d" % g1)
	_check(mb != null and not mb.disabled and mb.text.begins_with("Merge into army"), "the army card offers Merge into the army next to it")
	var row = cs.side_box.find_child("together_row", true, false)
	var orders_lbl = cs.side_box.find_child("army_points", true, false)
	_check(row != null and (orders_lbl == null or (row as Control).get_index() < 3), "near the top of the card")
	_tap_button("exchange_units", "Exchange units")


func _m_xc_open() -> void:
	var pnl = cs.dialog.find_child("exchange_panel", true, false)
	_check(cs.dialog.visible and pnl != null, "the exchange panel opens")
	var row = cs.dialog.find_child("xa_0", true, false)
	_check(row != null, "this army's units are listed")
	if row != null:
		_tap_control(row)


func _m_xc_move() -> void:
	var a := CState.army(cs.ps, g0)
	var b := CState.army(cs.ps, g1)
	var la = cs.dialog.find_child("xc_count_a", true, false)
	var lb = cs.dialog.find_child("xc_count_b", true, false)
	_check(la != null and (la as Label).text.begins_with("This army: %d / %d" % [CState.unit_count(a) - 1, CData.ARMY_MAX])
		and lb != null and (lb as Label).text.contains("%d / %d" % [CState.unit_count(b) + 1, CData.ARMY_MAX]),
		"a tapped unit moves across; the counts and the cap show (%s | %s)" % [(la as Label).text if la else "", (lb as Label).text if lb else ""])
	var btn = cs.dialog.find_child("xc_confirm", true, false)
	_check(btn != null and not (btn as Button).disabled, "Confirm is enabled")
	if btn != null:
		_tap_control(btn)


func _m_xc_confirm() -> void:
	pass


func _m_xc_check() -> void:
	var n := 0
	for o in cs.orders:
		if str(o["t"]) == "exchange" and int(o["from"]) == g0 and int(o["to"]) == g1 and str(o["units"]) == str([0]):
			n += 1
	_check(n == 1 and not cs.dialog.visible, "Confirm adds the exchange order")
	_check(CState.unit_count(CState.army(cs.ps, g1)) == CState.unit_count(CState.army(cs.st, g1)) + 1, "the plan preview shows the counts after it")
	_tap_control(cs.undo_button)


func _m_undo() -> void:
	var n := 0
	for o in cs.orders:
		if str(o["t"]) == "exchange":
			n += 1
	_check(n == 0, "Undo takes the exchange back")
	cs.select_army(g0)
	await process_frame
	_tap(cs.overlay.army_positions()[g1])


func _m_tap1() -> void:
	_check(cs.sel_army == g0 and cs.merge_tap == g1, "a first tap on our other army previews the merge (still %d selected)" % cs.sel_army)
	var marks := 0
	for mm in cs.overlay.merge_marks:
		if int(mm[0]) == g1:
			marks += 1
	var cap := ""
	for pth in cs.overlay.paths6:
		cap += str(pth.get("caption", ""))
	_check(marks == 1 and cap.begins_with("Merge into army"), "a merge glyph on it and the caption: %s" % cap)
	_check(cs.find_child("toast", true, false) != null, "a toast offers Merge / Select it")
	_tap(cs.overlay.army_positions()[g1])


func _m_tap2() -> void:
	pass


func _m_merged() -> void:
	var n := 0
	for o in cs.orders:
		if str(o["t"]) == "merge" and int(o["army"]) == g0 and int(o["into"]) == g1:
			n += 1
	_check(n == 1 and CState.army(cs.ps, g0).is_empty() and cs.sel_army == g1, "the second tap merges (next to it: a merge order now)")
	cs.orders = []
	cs._replan()


func _m_far() -> void:
	CState.place(CState.army(cs.st, g1), CState.field_cell(CData.region_index("campania")))
	cs._replan()
	cs.close_side()
	cs.focus_region(CData.region_index("latium"), 0.9)
	await process_frame
	await process_frame
	cs.select_army(g0)


func _m_far1() -> void:
	_tap(cs.overlay.army_positions()[g1])


func _m_far2() -> void:
	_tap(cs.overlay.army_positions()[g1])


func _m_far_check() -> void:
	var o := _move_order(g0)
	_check(int(o.get("join", -1)) == g1 and cs.move_kind(g0) == "merge", "further away: a march that merges on arrival: %s" % str(o))
	var cap := ""
	for pth in cs.overlay.paths6:
		cap += str(pth.get("caption", ""))
	_check(cap.begins_with("Merge into army"), "its path reads %s" % cap)
	cs.orders = []
	cs._replan()


func _m_gift_setup() -> void:
	# An allied player (Carthage) with an army next to ours.
	_ally = CData.faction_index("carthage")
	(cs.st["humans"] as Array).append(_ally)
	(cs.st["humans"] as Array).sort()
	CState.set_dip(cs.st, rome, _ally, CState.ALLIED)
	var c0 := CState.field_cell(CData.region_index("latium"))
	var id := CRules.new_army_id(cs.st, _ally)
	cs.st["factions"][_ally]["next_army"] = int(cs.st["factions"][_ally]["next_army"]) + 1
	var na := {"id": id, "f": _ally, "r": CGrid.region(c0), "units": [{"t": "spear", "n": 100}], "from": -1, "moved": 0, "busy": 0}
	CState.place(na, _neighbour(c0))
	CRules._insert_army(cs.st, na)
	_ally_army = id
	CState.place(CState.army(cs.st, g1), CState.field_cell(CData.region_index("campania")))
	cs._replan()
	cs.close_side()
	cs.focus_region(CData.region_index("latium"), 1.6)
	await process_frame
	await process_frame
	cs.select_army(g0)


func _m_gift_tap() -> void:
	var gl := 0
	for mm in cs.overlay.merge_marks:
		if int(mm[0]) == _ally_army and int(mm[1]) == 1:
			gl += 1
	_check(gl == 1, "the ally's army next to ours shows the gift glyph")
	_tap(cs.overlay.army_positions()[_ally_army])


func _m_gift_row() -> void:
	var btn = cs.dialog.find_child("xc_confirm", true, false)
	_check(cs.dialog.visible and btn != null and (btn as Button).text.begins_with("Gift"), "a tap on the ally's army opens the panel in gift mode")
	var theirs = cs.dialog.find_child("xb_0", true, false)
	_check(theirs != null and (theirs as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE, "the ally's units cannot be taken")
	var row = cs.dialog.find_child("xa_0", true, false)
	if row != null:
		_tap_control(row)


func _m_gift_confirm() -> void:
	var btn = cs.dialog.find_child("xc_confirm", true, false)
	_check(btn != null and (btn as Button).text == "Gift 1 unit" and not (btn as Button).disabled, "Gift 1 unit")
	if btn != null:
		_tap_control(btn)


func _m_gift_check() -> void:
	var n := 0
	for o in cs.orders:
		if str(o["t"]) == "exchange" and int(o["to"]) == _ally_army and not o.has("back"):
			n += 1
	_check(n == 1 and CState.unit_count(CState.army(cs.ps, _ally_army)) == 2, "the gift is planned; the ally's army shows it in the preview")


# ------------------------------------------------------------ recruiting ---

var _lat := CData.region_index("latium")


func _recruit_orders() -> Array:
	var out: Array = []
	for o in cs.orders:
		if str(o["t"]) == "recruit":
			out.append(o)
	return out


func _r_setup() -> void:
	if cs.dialog.visible:
		cs.close_dialog()
	# Back to Rome alone; its first army inside the walls of Roma.
	if _ally_army >= 0:
		cs.st["armies"].erase(CState.army(cs.st, _ally_army))
	cs.st["humans"] = [rome]
	cs.st["factions"][rome]["treasury"] = 20000
	cs.orders = []
	var a := CState.army(cs.st, g0)
	CState.place(a, CGrid.site(_lat))
	a["dest_x"] = -1
	a["dest_y"] = -1
	a["tgt"] = -1
	CState.place(CState.army(cs.st, g1), CState.field_cell(CData.region_index("campania")))
	cs._replan()
	cs.close_side()
	cs.focus_region(_lat, 1.4)
	await process_frame
	await process_frame
	cs.select_army(g0)


func _r_card() -> void:
	var sec = cs.side_box.find_child("recruit_section", true, false)
	var sl = cs.side_box.find_child("recruit_slots", true, false)
	_check(sec != null and sl != null and (sl as Label).text.begins_with("0 of 3 recruits here this turn"),
		"the card of an army at Roma has the recruit list (%s)" % ((sl as Label).text if sl else "none"))
	var plus: Button = null
	for b in cs.side_box.find_children("recruit_*", "Button", true, false):
		if not (b as Button).disabled and not str(b.name).begins_with("recruit_cancel"):
			plus = b
			break
	_check(plus != null, "a recruit + button is enabled")
	if plus != null:
		_tap_control(plus)


func _r_check() -> void:
	var rec := _recruit_orders()
	_check(rec.size() == 1 and int(rec[0].get("army", -1)) == g0 and int(rec[0]["r"]) == _lat, "+ plans a recruit into this army: %s" % str(rec))
	var cnt = cs.side_box.find_child("army_count", true, false)
	_check(cnt != null and (cnt as Label).text.contains("(+1 arriving)"), "the card counts it as arriving (%s)" % ((cnt as Label).text if cnt else ""))
	_check(cs.side_box.find_child("arriving_0", true, false) != null and cs.side_box.find_child("recruit_cancel_0", true, false) != null,
		"the planned recruit shows greyed in the unit list with an X")
	var sl = cs.side_box.find_child("recruit_slots", true, false)
	_check(sl != null and (sl as Label).text.begins_with("1 of 3"), "the slot counter: %s" % ((sl as Label).text if sl else ""))
	_check(int(cs.ps["factions"][rome]["treasury"]) < int(cs.st["factions"][rome]["treasury"]), "the price comes off the previewed treasury")
	# Plan a march for it: a toast asks first.
	_tap(_cell_screen(CState.field_cell(_lat)))


func _r_march() -> void:
	var t = cs.find_child("toast", true, false)
	var b1 := _button("toast_action")
	var b2 := _button("toast_action2")
	_check(t != null and b1 != null and b1.text == "Cancel recruits and march" and b2 != null and b2.text == "Keep recruiting",
		"a march for an army taking recruits asks: Cancel recruits and march / Keep recruiting")
	_check(_move_order(g0).is_empty() and _recruit_orders().size() == 1, "nothing changed yet")
	if b2 != null:
		_tap_control(b2)


func _r_keep() -> void:
	_check(_move_order(g0).is_empty() and _recruit_orders().size() == 1, "Keep recruiting: no march, the recruit stays")
	_tap(_cell_screen(CState.field_cell(_lat)))


func _r_march2() -> void:
	var b1 := _button("toast_action")
	_check(b1 != null and b1.text == "Cancel recruits and march", "the toast again")
	if b1 != null:
		_tap_control(b1)


func _r_cancel_march() -> void:
	_check(not _move_order(g0).is_empty() and _recruit_orders().is_empty(), "Cancel recruits and march: the recruit is gone, the march planned")


func _r_marching() -> void:
	cs.select_army(g0)
	await process_frame
	var ml = cs.side_box.find_child("recruit_marching", true, false)
	_check(ml != null and cs.side_box.find_child("recruit_heavy", true, false) == null and cs.side_box.find_child("recruit_row_heavy", true, false) == null,
		"with a march planned the recruit list is off: This army is marching this turn")
	cs.orders = []
	cs._replan()
	cs.select_army(g0)


func _r_again() -> void:
	var plus: Button = null
	for b in cs.side_box.find_children("recruit_*", "Button", true, false):
		if not (b as Button).disabled and not str(b.name).begins_with("recruit_cancel"):
			plus = b
			break
	if plus != null:
		_tap_control(plus)


func _r_x() -> void:
	_check(_recruit_orders().size() == 1, "recruit planned again")
	var x = cs.side_box.find_child("recruit_cancel_0", true, false)
	if x != null:
		_tap_control(x)


func _r_x_check() -> void:
	_check(_recruit_orders().is_empty() and cs.side_box.find_child("arriving_0", true, false) == null, "its X takes the planned recruit back")


func _r_region() -> void:
	cs.close_side()
	cs.select_region(_lat)
	await process_frame
	await process_frame
	_check(cs.side_box.find_child("recruit_heavy", true, false) == null and cs.side_box.find_child("recruit_row_heavy", true, false) == null,
		"the region panel has no recruit list")
	_check(cs.side_box.find_child("garrison_section", true, false) != null and cs.side_box.find_child("trains_section", true, false) != null,
		"it shows the garrison and what the city trains")
	var rb := _button("raise_army")
	_check(rb != null and not rb.disabled, "Raise new army")
	if rb != null:
		_tap_control(rb)


var _raise_key := ""


func _r_picker() -> void:
	_check(cs.dialog.visible and cs.dialog.find_child("raise_panel", true, false) != null, "the picker opens")
	var ok = cs.dialog.find_child("raise_confirm", true, false)
	_check(ok != null and (ok as Button).disabled, "Raise army is off with nothing picked")
	for b in cs.dialog.find_children("raise_plus_*", "Button", true, false):
		if not (b as Button).disabled:
			_raise_key = str(b.name).substr("raise_plus_".length())
			_tap_control(b)
			return
	_check(false, "a + in the picker")


func _r_picker2() -> void:
	var b = cs.dialog.find_child("raise_plus_" + _raise_key, true, false)
	if b != null:
		_tap_control(b)


func _r_picker3() -> void:
	var cl = cs.dialog.find_child("raise_count_" + _raise_key, true, false)
	var ok = cs.dialog.find_child("raise_confirm", true, false)
	_check(cl != null and (cl as Label).text == "2" and ok != null and not (ok as Button).disabled and (ok as Button).text == "Raise army (2)",
		"two picked: Raise army (2)")
	if ok != null:
		_tap_control(ok)


func _r_raise_check() -> void:
	var rec := _recruit_orders()
	_check(rec.size() == 2 and int(rec[0].get("new", 0)) == 1 and int(rec[1].get("new", 0)) == 1 and not cs.dialog.visible,
		"Raise army adds two new-army recruit orders: %s" % str(rec))
	var pl = cs.side_box.find_child("raise_planned", true, false)
	_check(pl != null and (pl as Label).text.begins_with("Raising a new army: 2 units"), "the region panel shows it: %s" % ((pl as Label).text if pl else ""))
	var x = cs.side_box.find_child("raise_cancel", true, false)
	if x != null:
		_tap_control(x)


func _r_raise_x() -> void:
	_check(_recruit_orders().is_empty() and cs.side_box.find_child("raise_planned", true, false) == null, "its X cancels the new army")
