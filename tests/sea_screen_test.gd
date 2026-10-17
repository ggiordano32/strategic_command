extends SceneTree
## Sea battles on the campaign screen (N3a), headless:
##   godot --headless --script res://tests/sea_screen_test.gd
## A West campaign with England a player; an English fleet sails into a
## Spanish one: the turn ends with a pending sea battle. The Battles dialog
## shows the sea battle's card (its title, the water preview, both fleets'
## ships, Auto-resolve / Fight). Fight opens the real-time sea battle
## screen (game/sea_battle.gd: the HUD with the wind, the ship cards, the
## orders bar; a tap on the sea gives a sail order); the battle AI then
## sails both sides to the end, the screen's Continue applies the outcome
## (the campaign's fleets change, the battle is gone, the phase is plan) and
## the result card shows the fates. A second pending sea battle,
## auto-resolved: the formula's result card.

const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const SeaBattle := preload("res://game/sea_battle.gd")
const SeaSim := preload("res://sim/sea_sim.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const PackView := preload("res://game/campaign/pack_view.gd")

var cs: CampaignScreen
var eng := -1
var _ok := true
var _frame := 0
var _step := 0
var _bid := -1
var _sb = null


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		_ok = false


func _state() -> Dictionary:
	PackView.use_pack("west")
	eng = CData.faction_index("england")
	var sp := CData.faction_index("new_spain")
	var st := CState.new_campaign("SeaScreenTest", 11, [eng], {}, [], "west")
	var open := -1
	for c in CGrid.count():
		if CFleet.is_sea(c) and CFleet.coast_dist(c) >= 3 and CGrid.cy(c) > 20 and CGrid.cx(c) > 60 and CGrid.cx(c) < 120:
			open = c
			break
	var e1 := {"id": 900, "f": eng, "x": CGrid.cx(open) + 4, "y": CGrid.cy(open), "ships": [{"t": "frigate", "h": 100, "c": 100},
		{"t": "sloop", "h": 100, "c": 100}], "carry": [], "moved": 0}
	var e2 := {"id": 901, "f": sp, "x": CGrid.cx(open) - 4, "y": CGrid.cy(open), "ships": [{"t": "galleon", "h": 100, "c": 100},
		{"t": "sloop", "h": 90, "c": 90}], "carry": [], "moved": 0}
	var e3 := {"id": 902, "f": eng, "x": CGrid.cx(open) + 4, "y": CGrid.cy(open) + 14, "ships": [{"t": "frigate", "h": 100, "c": 100}],
		"carry": [], "moved": 0}
	var e4 := {"id": 903, "f": sp, "x": CGrid.cx(open) - 4, "y": CGrid.cy(open) + 14, "ships": [{"t": "frigate", "h": 100, "c": 100}],
		"carry": [], "moved": 0}
	st["fleets"] = [e1, e2, e3, e4]
	var orders := [{"t": "fmove", "fleet": 900, "x": int(e2["x"]), "y": int(e2["y"]), "tgt": 901},
		{"t": "fmove", "fleet": 902, "x": int(e4["x"]), "y": int(e4["y"]), "tgt": 903}]
	return CTurn.resolve_turn(st, [CTurn.submission(st, eng, orders)])


func _initialize() -> void:
	var st := _state()
	var sea := 0
	for b in st["battles"]:
		if b.has("sea"):
			sea += 1
	_check(sea == 2 and str(st["phase"]) == "battles", "two sea battles pending after the turn (%d)" % sea)
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "sea_screen_test")
	root.add_child(cs)


func _button(part: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and str(b.name).contains(part):
			return b
	return null


func _text_under(n: Node) -> String:
	var out := ""
	for l in n.find_children("*", "Label", true, false):
		out += (l as Label).text + "\n"
	return out


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 4:
		return false
	match _step:
		0:
			cs.panels.show_battles()
			var card: Node = cs.dialog.find_child("battle_screen", true, false)
			var txt := _text_under(cs.dialog)
			_check(card != null and txt.contains("Sea battle off") and txt.contains("Galleon"), "the Battles dialog shows a sea battle's card")
			var pv: Node = cs.dialog.find_child("battle_preview", true, false)
			_check(pv != null, "the card has the water preview")
			var fb: Button = null
			for b in cs.dialog.find_children("*", "Button", true, false):
				if str(b.name).begins_with("fight_"):
					fb = b
					_bid = int(str(b.name).get_slice("_", 1))
					break
			_check(fb != null and _button("auto_%d" % _bid) != null, "Fight and Auto-resolve on the card")
			if fb == null:
				_finish()
				return true
			fb.pressed.emit()
			_step = 1
			_frame = 0
		1:
			_sb = null
			for c in root.get_children():
				if c is SeaBattle:
					_sb = c
			_check(_sb != null and not cs.world.visible, "Fight opens the sea battle screen")
			if _sb == null:
				_finish()
				return true
			_check(_sb.sim.n_units == 4 and int(_sb.player_side) == 0 and _button("sea_full") != null and _button("sea_board") != null,
				"the sea screen: 4 ships, the player's side 0, the orders bar")
			var tips := true
			for n in ["sea_full", "sea_battle_sail", "sea_stop", "sea_round", "sea_chain", "sea_grape", "sea_fire", "sea_board", "sea_hold", "sea_flee"]:
				var ob := _button(n)
				tips = tips and ob != null and ob.tooltip_text != ""
			_check(tips, "every order button has a tooltip")
			var bk := _button("sea_book_button")
			_check(bk != null, "the sea screen has the book button")
			if bk != null:
				bk.pressed.emit()
				_check(_sb.book.visible, "the Ship book opens (tests/sea_help_test.gd covers its pages)")
				_sb.book.close()
			# A tap on the sea: the selected ship gets a sail order.
			var s0: int = _sb.selection[0]
			var p: Vector2 = _sb._pos(s0) + Vector2(0, -300)
			var scr: Vector2 = _sb.get_canvas_transform() * p
			_sb._tap(scr)
			_sb.sim.step()
			_check(_sb.sim.s_mode[s0] == SeaSim.M_GOTO, "a tap on the sea: sail there (mode %d)" % _sb.sim.s_mode[s0])
			# The battle AI fights both sides to the end.
			_sb.sim.ai_sides[0] = 1
			while _sb.sim.ended == 0 and _sb.sim.tick < 9300:
				_sb.sim.step()
			_check(_sb.sim.ended != 0, "the sea battle ends (%d s, side %d won)" % [_sb.sim.tick / 10, _sb.sim.winner])
			_sb._decided_at = 0.0
			_sb._show_end()
			_step = 2
			_frame = 0
		2:
			var cont := _button("sea_continue")
			_check(cont != null, "the sea battle's end panel has Continue")
			if cont == null:
				_finish()
				return true
			cont.pressed.emit()
			_step = 3
			_frame = 0
		3:
			var st: Dictionary = cs.st
			var still := CState.battle(st, _bid)
			_check(still.is_empty() and (st["battles"] as Array).size() == 1, "the fought battle is applied and gone")
			var txt := _text_under(cs.dialog)
			_check(cs.dialog.visible and (txt.contains("VICTORY") or txt.contains("DEFEAT")) and txt.contains("Fought"),
				"the result card: the banner, Fought")
			var fl := CFleet.fleet(st, 900)
			_check(fl.is_empty() or not fl.has("busy"), "the English fleet is free again")
			cs.close_dialog()
			var b2: Dictionary = st["battles"][0]
			cs.auto_resolve(int(b2["id"]))
			_step = 4
			_frame = 0
		4:
			var st2: Dictionary = cs.st
			var txt2 := _text_under(cs.dialog)
			_check((st2["battles"] as Array).is_empty() and str(st2["phase"]) == "plan" and txt2.contains("Auto-resolved"),
				"auto-resolve: the formula, the result card (phase %s)" % str(st2["phase"]))
			_finish()
			return true
	return false


func _finish() -> void:
	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)
