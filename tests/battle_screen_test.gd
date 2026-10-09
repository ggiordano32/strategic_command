extends SceneTree
## The battle screen on the overworld (game/campaign/battle_screen.gd),
## headless:
##   godot --headless --script res://tests/battle_screen_test.gd
## A pending assault on a walled city: the Battles dialog shows the
## pre-battle screen (the settlement preview, the siege equipment line, the
## odds bar, a card per unit with its health bar, the garrison as a group,
## Auto-resolve / Fight); Auto-resolve runs and the result state shows the
## right banner for the player, "Auto-resolved", the outcome line, survivors
## on the cards and the totals (a side's kills are the other side's dead);
## Continue goes on. A second assault fought and left: "Fought (left the
## field)" and DEFEAT. Per-unit kills: a fought battle's cards show "kills
## N" (its outcome rows carry them), an auto-resolved one's do not and say
## kills are counted per side; a fought outcome with kills drawn on the
## first assault's cards. A field battle (an interception, format 5): the
## terrain preview instead of the city, no equipment line, the cards.

const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const BattleScreen := preload("res://game/campaign/battle_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CTurn := preload("res://campaign/cturn.gd")
const UT := preload("res://sim/unit_types.gd")
const CityPreview := preload("res://game/campaign/city_preview.gd")

var cs: CampaignScreen
var rome := CData.faction_index("rome")
var target := CData.region_index("sicilia_or")
var _ok := true
var _frame := 0
var _step := 0
var _wait := 0
var _bid := -1
var _snap: Dictionary = {}


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		_ok = false


func _initialize() -> void:
	var st := CState.new_campaign("BattleScreenTest", 11, [rome])
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "battle_screen_test")
	root.add_child(cs)


## The player's first army has besieged `target` for two turns and storms it.
func _assault(a: Dictionary, damage: bool) -> void:
	var st: Dictionary = cs.st
	if damage:
		a["units"][0]["n"] = 60  # a mauled unit: its health bar shows it
	var o := CState.owner(st, target)
	if o >= 0 and not CState.at_war(st, rome, o):
		CRules.declare_war(st, rome, o)
	var left := int(a["r"])
	a["r"] = target
	if CState.grid_on(st):
		CState.place(a, CState.ring_cell(target, 0))
	var sg := CRules.start_siege(st, target, a, left)
	sg["turn"] = int(st["turn"]) - 2
	var b := CRules.start_siege_battle(st, target, "assault")
	b.erase("new")
	_bid = int(b["id"])
	st["phase"] = "battles"
	cs._next_step()


func _button(part: String) -> Button:
	for b in cs.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and str(b.name).contains(part):
			return b
	return null


func _cards(under: Node) -> Array:
	var out: Array = []
	for c in under.find_children("card_*", "", true, false):
		if c is BattleScreen.UnitCard:
			out.append(c)
	return out


func _label(under: Node, nm: String) -> String:
	var l = under.find_child(nm, true, false)
	return (l as Label).text if l is Label else ""


func _check_pre() -> void:
	var scr := cs.dialog_box.find_child("battle_screen", true, false)
	_check(cs.dialog.visible and scr != null, "the Battles dialog shows the pre-battle screen")
	if scr == null:
		return
	_check(scr.find_child("battle_preview", true, false) is CityPreview, "with the settlement's map preview")
	var eq := _label(scr, "siege_equipment")
	_check(eq.contains("3 sets of ladders") and eq.contains("ram"), "the siege equipment line: " + eq)
	var ml := _label(scr, "mantlets")
	_check(ml.contains("Mantlets: 2"), "the mantlets line: " + ml)
	_check(scr.find_child("odds_bar", true, false) != null and scr.find_child("odds_text", true, false) != null, "the odds bar")
	var b := CState.battle(cs.st, _bid)
	_snap = BattleScreen.snapshot(cs.st, b, rome)
	var want := 0
	for sd in 2:
		for g in _snap["sides"][sd]:
			want += (g["units"] as Array).size()
	var cards := _cards(scr)
	_check(want > 0 and cards.size() == want, "a card per unit (%d of %d)" % [cards.size(), want])
	var gar := false
	for g in _snap["sides"][1]:
		gar = gar or int(g["army"]) == -1
	_check(gar and scr.find_child("card_1_g1_0", true, false) != null, "the garrison is a group on the defenders' side")
	var c0 = scr.find_child("card_0_%d_0" % int(_snap["sides"][0][0]["army"]), true, false)
	_check(c0 != null and c0.men == 60 and c0.full == UT.size_of(int(c0.ty)) and c0.back == -1,
		"the mauled unit's card: 60 of %d men (health bar)" % (c0.full if c0 != null else 0))
	_check(_button("auto_%d" % _bid) != null and _button("fight_%d" % _bid) != null, "Auto-resolve and Fight")


func _check_result(auto: bool) -> void:
	var res := cs.dialog_box.find_child("battle_result", true, false)
	_check(cs.dialog.visible and res != null, "the result state is shown")
	if res == null:
		return
	var ev: Dictionary = {}
	for e in cs.st["events"]:
		if str(e["k"]) == "battle" and int(e.get("battle", -1)) == _bid:
			ev = e
	var banner := _label(res, "result_banner")
	var want := "VICTORY" if int(ev.get("winner", -1)) == 0 else "DEFEAT"
	var mode := _label(res, "result_mode")
	print("  banner %s, %s, %s" % [banner, mode, _label(res, "result_outcome")])
	_check(banner == want or banner == "DRAW", "the banner from Rome's side: %s (winner %d)" % [banner, int(ev.get("winner", -1))])
	_check(mode.begins_with("Auto-resolved") if auto else mode.begins_with("Fought (left the field)"), "labelled: " + mode)
	_check(_label(res, "result_outcome") != "", "the one-line outcome")
	var cards := _cards(res)
	var fielded := [0, 0]
	var back := [0, 0]
	for c in cards:
		if c.fielded:
			var sd := 0 if str(c.name).begins_with("card_0") else 1
			fielded[sd] += c.men
			back[sd] += c.back
			if c.back < 0 or c.back > c.men:
				_check(false, "a result card with survivors in 0..fielded")
	_check(not cards.is_empty(), "result cards (%d)" % cards.size())
	# The event's own men counts agree with the cards' (armies only there).
	var t0 := _label(res, "totals_0")
	var t1 := _label(res, "totals_1")
	_check(t0.begins_with("Fielded %d, back %d" % [fielded[0], back[0]]), "the attackers' totals: " + t0)
	_check(t1.begins_with("Fielded %d, back %d" % [fielded[1], back[1]]), "the defenders' totals: " + t1)
	var dead1 := int(t1.get_slice("(", 1).get_slice(" ", 0))
	_check(t0.ends_with("Kills: %d." % dead1), "the attackers' kills are the defenders' dead (%d)" % dead1)
	_check(int(ev.get("att_men", -1)) == fielded[0] and int(ev.get("att_lost", -1)) == fielded[0] - back[0],
		"the attackers' fielded and lost men match the battle event (%d, %d)" % [int(ev.get("att_men", -1)), int(ev.get("att_lost", -1))])
	# Per-unit kills: only a fought battle's outcome carries them.
	var with_k := 0
	var n_f := 0
	for c in cards:
		if c.fielded:
			n_f += 1
			if c.kills >= 0:
				with_k += 1
	var note := _label(res, "kills_note")
	if auto:
		_check(with_k == 0 and note.begins_with(BattleScreen.KILLS_NOTE), "auto-resolved: no per-unit kills, kills counted per side")
	else:
		_check(n_f > 0 and with_k == n_f and note.begins_with(BattleScreen.KILLS_NOTE_UNITS),
			"fought: every fielded card shows its kills (%d of %d)" % [with_k, n_f])
	_check(_button("dlg_Continue") != null, "Continue")


## A fought outcome for the first assault's snapshot with made-up losses
## and kills: each fielded card shows its own kills, the footer still sums
## the enemy's dead.
func _check_kills_cards() -> void:
	var rows: Array = []
	var want := {}
	var k := 0
	for sd in 2:
		for g in _snap["sides"][sd]:
			for u in g["units"]:
				if int(u["on"]) == 0:
					continue
				var n := int(u["n"])
				var key := "card_%d_%s" % [sd, ("%d:%d" % [int(g["army"]), int(u["unit"])]).replace(":", "_").replace("-", "g")]
				rows.append({"army": int(g["army"]), "unit": int(u["unit"]), "killed": n / 4, "routed": 0,
					"withdrawn": 0, "remaining": n - n / 4, "kills": 3 + k})
				want[key] = 3 + k
				k += 1
	var out := {"winner": 0, "mode": "fought", "units": rows, "garrison_pct": 50}
	var res: Control = BattleScreen.result(cs, _snap, out, cs.st, [])
	var ok := not want.is_empty()
	for c in _cards(res):
		if want.has(str(c.name)):
			ok = ok and c.kills == int(want[str(c.name)]) and c.describe().contains("%d kills" % int(want[str(c.name)]))
			want.erase(str(c.name))
	_check(ok and want.is_empty(), "a fought outcome's kills on each card ('kills N')")
	var t0 := ""
	var t1 := ""
	for l in res.find_children("totals_*", "Label", true, false):
		if str(l.name) == "totals_0":
			t0 = (l as Label).text
		else:
			t1 = (l as Label).text
	var dead1 := int(t1.get_slice("(", 1).get_slice(" ", 0))
	_check(dead1 > 0 and t0.ends_with("Kills: %d." % dead1), "the per-side kills footer stays (the enemy's dead): " + t0)
	res.free()


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 5:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	_step += 1
	match _step:
		1:
			_assault(CState.armies_of(cs.st, rome)[0], true)
			_wait = 3
		2:
			_check_pre()
			_button("auto_%d" % _bid).pressed.emit()
		3:
			if cs._resolver != null and _frame < 20000:
				_step -= 1
				return false
			_wait = 3
		4:
			_check(CState.battle(cs.st, _bid).is_empty(), "auto-resolve applied the battle")
			_check_result(true)
			_button("dlg_Continue").pressed.emit()
			_wait = 3
		5:
			_check(not cs.dialog.visible or cs.dialog_box.find_child("battle_result", true, false) == null, "Continue leaves the result")
			# A second assault by a fresh army on another city, fought and left at once.
			var st: Dictionary = cs.st
			target = CData.region_index("attica")
			var a2 := {"id": CRules.new_army_id(st, rome), "f": rome, "r": CData.region_index("latium"),
				"units": [{"t": "heavy", "n": 100}, {"t": "spear", "n": 100}], "from": -1, "moved": 0, "busy": 0}
			st["factions"][rome]["next_army"] = int(st["factions"][rome]["next_army"]) + 1
			CRules._insert_army(st, a2)
			_assault(CState.army(st, int(a2["id"])), false)
			_wait = 3
		6:
			var fb := _button("fight_%d" % _bid)
			_check(fb != null, "Fight on the second assault")
			if fb != null:
				fb.pressed.emit()
			_wait = 10
		7:
			_check(cs.battle != null and cs.battle.campaign_mode, "Fight opens the battle")
			if cs.battle != null:
				cs.battle.hud.menu_pressed.emit()
			_wait = 5
		8:
			if cs.battle != null:
				cs.battle.hud.menu_pressed.emit()
			_wait = 8
		9:
			_check(cs.battle == null and CState.battle(cs.st, _bid).is_empty(), "leaving the battle applies it (forfeit)")
			_check_result(false)
			_check(_label(cs.dialog_box, "result_banner") == "DEFEAT", "a forfeit is a DEFEAT")
			_check_kills_cards()
			_button("dlg_Continue").pressed.emit()
			_wait = 3
		10:
			_field()
			_wait = 5
		11:
			cs._next_step()
			_wait = 3
		12:
			var scr := cs.dialog_box.find_child("battle_screen", true, false)
			_check(scr != null, "a field battle's pre-battle screen")
			if scr != null:
				_check(scr.find_child("battle_preview", true, false) is BattleScreen.FieldPreview, "with the terrain preview")
				_check(scr.find_child("siege_equipment", true, false) == null and scr.find_child("mantlets", true, false) == null,
					"and no siege equipment or mantlets line")
				var b: Dictionary = CTurn.pending_for(cs.st)[0]
				var sn := BattleScreen.snapshot(cs.st, b, rome)
				var want := 0
				var gar := false
				for sd in 2:
					for g in sn["sides"][sd]:
						want += (g["units"] as Array).size()
						gar = gar or int(g["army"]) < 0
				_check(scr.find_child("odds_bar", true, false) != null and _cards(scr).size() == want and want >= 7 and not gar,
					"the odds bar and a card per unit, no garrison (%d of %d)" % [_cards(scr).size(), want])
				var txt := ""
				for l in scr.find_children("*", "Label", true, false):
					txt += (l as Label).text + " "
				_check(txt.contains("Field battle in Samnium") and txt.contains("woods"), "the title and the ground with its woods")
			print("RESULT: ", "PASS" if _ok else "FAIL")
			quit(0 if _ok else 1)
	return false


## Format 5: an Epirote army marching into Samnium runs into Rome's army
## standing there (a field battle, no garrison).
func _field() -> void:
	cs.queue_free()
	var st := CState.as_format(CState.new_campaign("BattleScreenField", 3, [rome]), 5)
	var ep := CData.faction_index("epirus")
	CRules.declare_war(st, rome, ep)
	var id := CRules.new_army_id(st, ep)
	st["factions"][ep]["next_army"] = int(st["factions"][ep]["next_army"]) + 1
	CRules._insert_army(st, {"id": id, "f": ep, "r": CData.region_index("apulia"), "units": [{"t": "pike", "n": 120}, {"t": "cav", "n": 60}],
		"from": -1, "moved": 0, "busy": 0})
	var mine: Dictionary = CState.armies_of(st, rome)[0]
	mine["r"] = CData.region_index("samnium")
	mine["stance"] = CData.STANCE_FIELD
	mine["units"] = [{"t": "heavy", "n": 100}, {"t": "heavy", "n": 80}, {"t": "spear", "n": 100}, {"t": "light", "n": 120}, {"t": "cav", "n": 60}]
	CRules.execute_moves(st, [[id, CData.region_index("samnium"), ep, CData.MODE_MARCH, 0]])
	var b := CState.battle_at(st, CData.region_index("samnium"))
	_check(not b.is_empty() and str(b.get("kind", "")) == "field", "the interception is a pending field battle")
	b.erase("new")
	st["phase"] = "battles"
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "battle_screen_test5")
	root.add_child(cs)
