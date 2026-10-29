extends RefCounted
## The guided first campaign, "Your first command" (docs/design/campaign_rules.md "The tutorial"): a West campaign for
## England at Port Royal with a fixed seed, Sevilla la Nueva as the target, and ten lessons, one a turn. Each lesson is a
## card at the top of the screen (howto.gd words, the story cards' frame), a pointer on the thing to tap and a gate:
## End turn is held until the lesson's objective holds. "Skip the lesson" does the lesson's order for the player and
## "Leave the tutorial" stops the cards. The objectives are view-side checks of the state and the plan being made; this
## file never writes the campaign state (the starting state is made once, by `make_state`, before the campaign exists).
## Where the player is (the lesson, the pages opened) lives in the local save's session ("tutorial"), not in the
## hashed state. The rules' only part is the setting `tutorial` 1 that the campaign AI reads (cai.gd tutorial_shield).
## Leave: the rules have no settings order, so `tutorial` stays set in the state (the AI keeps its peace until
## `tutorial_turns`, 10 turns) and the cards stop. Offline campaigns only.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CTurn := preload("res://campaign/cturn.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const Howto := preload("res://game/campaign/howto.gd")
const Tips := preload("res://game/campaign/tips.gd")
const MapOverlay := preload("res://game/campaign/map_overlay.gd")
const TutorCard := preload("res://game/campaign/tutor_card.gd")
const TutorPointer := preload("res://game/campaign/tutor_pointer.gd")
const TutorialBattle := preload("res://game/campaign/tutorial_battle.gd")

const SEED := 1670
const TURNS := 10          # settings.tutorial_turns: the AI declares no war on the player for this many turns
const START_TREASURY := 3000
const DONE_STAGE := 11     # the lessons are over (the closing card)
const BATTLE_LESSON := 6

var s  # the campaign screen
var card: TutorCard
var pointer: TutorPointer
var _shown_n := -1
var _shown_met := false
var _gate_on := false     # the End turn button is held by a lesson


func _init(screen) -> void:
	s = screen


# --------------------------------------------------------------- the start ---

## The tutorial campaign's starting state: the West for England, Sevilla la Nueva (Santiago de la Vega, a village on
## Jamaica) Spanish with its garrison, Belize too (so no Spanish raid on it interrupts the lessons), England's second army folded into the one at Port Royal (a pike, two musketeers, a
## horse and the general: two recruits later make four musketeers), more gold, the AIs on Easy for the battle and the
## chosen skill for the campaign, deployment waiting for the player. `ai_skill`: 0 Easy, 1 Average, 2 Skilled.
static func make_state(nm: String, sd: int, ai_skill: int = 0) -> Dictionary:
	CData.use_pack("west")
	var eng := CData.faction_index("england")
	var stt := {"tutorial": 1, "tutorial_turns": TURNS, "ai_battle_skill": 0, "ai_campaign_skill": ai_skill, "deploy_time": -1}
	var st := CState.new_campaign(nm, sd, [eng], stt, [], "west")
	var spa := CData.faction_index("new_spain")
	var sv := CData.region_index("sevilla_jamaica")
	st["regions"][sv]["owner"] = spa
	st["regions"][CData.region_index("belize")]["owner"] = spa   # (England's far logging camp: a Spanish raid on it would interrupt the lessons)
	var armies: Array = st["armies"]
	for i in range(armies.size() - 1, -1, -1):
		if int(armies[i]["f"]) == eng and int(armies[i]["r"]) == sv:
			armies.remove_at(i)
	var pr := CData.region_index("port_royal")
	for a in armies:
		if int(a["f"]) == eng and int(a["r"]) == pr:
			var keep: Array = []
			var want := {"w_pikemen": 1, "musketeers": 2, "pistoleers": 1, "general": 1}
			for u in a["units"]:
				var k := str(u["t"])
				if int(want.get(k, 0)) > 0:
					want[k] = int(want[k]) - 1
					keep.append(u)
			a["units"] = keep
	st["factions"][eng]["treasury"] = START_TREASURY
	return st


static func is_tutorial(st: Dictionary) -> bool:
	return not st.is_empty() and st.has("settings") and int((st["settings"] as Dictionary).get("tutorial", 0)) != 0


# ------------------------------------------------------------ the screen ---

func setup() -> void:
	card = TutorCard.new()
	card.visible = false
	card.pressed.connect(_on_button)
	s.ui.add_child(card)
	pointer = TutorPointer.new()
	pointer.target = _target
	pointer.visible = false
	s.ui.add_child(pointer)


## The tutorial is running for this screen (a tutorial campaign, offline, not left or finished).
func on() -> bool:
	if s.st.is_empty() or s.online != null or not is_tutorial(s.st):
		return false
	var vd := _vd()
	return int(vd["off"]) == 0 and int(vd["left"]) == 0


## The view data (the save's session); created with its defaults.
func _vd() -> Dictionary:
	var ses: Dictionary = s.data["session"]
	if not ses.has("tutorial"):
		ses["tutorial"] = {"n": 1, "turn": int(s.st.get("turn", 0)), "done": 0, "region": 0, "realm": 0, "goals": 0, "left": 0, "off": 0}
	return ses["tutorial"]


func lesson_n() -> int:
	return int(_vd()["n"])


## A page or panel was opened ("region" with the region, "realm", "goals").
func note(kind: String, arg: int = -1) -> void:
	if not on():
		return
	var vd := _vd()
	var changed := false
	match kind:
		"region":
			if arg == _pr() and int(vd["region"]) == 0:
				vd["region"] = 1
				changed = true
		"realm":
			if int(vd["realm"]) == 0:
				vd["realm"] = 1
				changed = true
		"goals":
			if int(vd["goals"]) == 0:
				vd["goals"] = 1
				changed = true
	if changed:
		s.save_plan()
		s._refresh_top()
		refresh()


func _pr() -> int:
	return CData.region_index("port_royal")


func _sv() -> int:
	return CData.region_index("sevilla_jamaica")


func _army() -> Dictionary:
	var best := {}
	for a in CState.armies_of(s.ps, s.f):
		if best.is_empty() or CState.unit_count(a) > CState.unit_count(best):
			best = a
	return best


func _fleet() -> Dictionary:
	if not s.ps.has("fleets"):
		return {}
	var l := CFleet.fleets_of(s.ps, s.f)
	return {} if l.is_empty() else l[0]


## The sea cell off the Tortuga coast the voyage of lesson 9 aims at (the first sea cell beside Port de Paix's harbour).
static func sail_cell() -> int:
	var h := CFleet.harbour(CData.region_index("port_de_paix"))
	for c in CFleet._ring1(h):
		if CFleet.is_sea(c):
			return c
	return h


# ------------------------------------------------------------- objectives ---

## Has the plan being made reached the lesson's objective? (Reads the orders; never writes.)
func met(n: int) -> bool:
	if s.f < 0:
		return false
	var vd := _vd()
	var pr := _pr()
	var sv := _sv()
	match n:
		1:
			return int(vd["region"]) != 0
		2:
			var c := 0
			for o in s.orders:
				if str(o.get("t", "")) == "recruit" and int(o.get("r", -1)) == pr and str(o.get("unit", "")).begins_with("musketeers"):
					c += 1
			return c >= 2
		3:
			for o in s.orders:
				if str(o.get("t", "")) == "build" and int(o.get("r", -1)) == pr and str(CData.CHAINS[int(o.get("chain", -1))]["key"]) == "range":
					return true
			return false
		4:
			var camp := CGrid.camp(sv)
			for o in s.orders:
				if str(o.get("t", "")) == "move" and CGrid.at(int(o.get("x", -1)), int(o.get("y", -1))) == camp:
					return true
			var a := _army()
			return not a.is_empty() and CState.cell(a) == camp
		5:
			if not CState.siege_at(s.ps, sv).is_empty() and int(CState.siege_at(s.ps, sv)["f"]) == s.f:
				return true
			var site := CGrid.site(sv)
			for o in s.orders:
				var t := str(o.get("t", ""))
				if t == "siege" and int(o.get("r", -1)) == sv:
					return true
				if t == "move" and CGrid.at(int(o.get("x", -1)), int(o.get("y", -1))) == site and int(o.get("mode", CData.MODE_SIEGE)) != CData.MODE_ASSAULT:
					return true
			return false
		6:
			if CState.owner(s.ps, sv) == s.f:
				return true
			for o in s.orders:
				if str(o.get("t", "")) == "assault" and int(o.get("r", -1)) == sv:
					return true
			return false
		7:
			return int(vd["realm"]) != 0
		8:
			var dutch := CData.faction_index("dutch")
			for o in s.orders:
				if str(o.get("t", "")) == "propose" and int(o.get("to", -1)) == dutch and str(o.get("what", "")) == "trade":
					return true
			return false
		9:
			var fl := _fleet()
			if fl.is_empty():
				return false
			var fid := int(fl["id"])
			var boarded: bool = CFleet.carried_units(fl) > 0
			var sail := false
			var h := CFleet.harbour(CData.region_index("port_de_paix"))
			for o in s.orders:
				var t := str(o.get("t", ""))
				if (t == "embark" and int(o.get("fleet", -1)) == fid) or (t == "move" and int(o.get("fleet", -1)) == fid):
					boarded = true
				if t == "fmove" and int(o.get("fleet", -1)) == fid and CGrid.cheb(CGrid.at(int(o.get("x", -1)), int(o.get("y", -1))), h) <= 6:
					sail = true
			return boarded and sail
		10:
			return int(vd["goals"]) != 0
	return false


## End turn is held: a lesson is running and its objective is not reached.
func holds_end() -> bool:
	if not on() or s.f < 0:
		return false
	var n := lesson_n()
	return n <= Howto.LESSONS and not met(n)


## The End turn button follows the gate (called by the screen after it sets the button).
func gate_end_button() -> void:
	if s.end_button == null:
		return
	var h := holds_end()
	if h:
		s.end_button.disabled = true
		Kit.tip(s.end_button, Howto.text("ui_gate"), Howto.text("ui_objective") + Howto.text("lesson_%d_obj" % lesson_n()) + ".")
	elif _gate_on:
		s.end_button.disabled = not CTurn.pending_for(s.st).is_empty() or s.f < 0 or str(s.st["phase"]) == "over"
		Kit.tip(s.end_button, "", "")
	_gate_on = h


## End turn pressed while held: say why. True when it was held.
func guard_end() -> bool:
	if not holds_end():
		return false
	s.show_toast("%s: %s." % [Howto.text("ui_gate"), Howto.text("lesson_%d_obj" % lesson_n())])
	return true


## The turn is being sent: the lesson's objective holds, so the next turn brings the next lesson.
func on_end() -> void:
	if not on():
		return
	var vd := _vd()
	var n := lesson_n()
	if n <= Howto.LESSONS and met(n):
		vd["done"] = 1


## The battle tutorial's script for the pending battle `b`, or null (the tutorial is off, another lesson, another battle).
func battle_script(b: Dictionary):
	if not on() or lesson_n() != BATTLE_LESSON or int(b.get("r", -1)) != _sv():
		return null
	return TutorialBattle.new()


# ---------------------------------------------------------------- the card ---

## Follow the state: advance the lesson on a new turn, refresh the card, the pointer and the End turn gate.
func refresh() -> void:
	if card == null:
		return
	Tips.suppress = on()
	if not on():
		card.visible = false
		pointer.visible = false
		gate_end_button()
		return
	var vd := _vd()
	var turn := int(s.st["turn"])
	var n := lesson_n()
	if n == BATTLE_LESSON and CState.owner(s.st, _sv()) == s.st["humans"][0]:
		_advance(n + 1)
	elif int(vd["turn"]) != turn:
		var ready_ := int(vd["done"]) != 0 and n != BATTLE_LESSON
		vd["turn"] = turn
		if ready_ and n <= Howto.LESSONS:
			_advance(n + 1)
		vd["done"] = 0 if n != BATTLE_LESSON else int(vd["done"])
	n = lesson_n()
	var show: bool = s.f >= 0 and str(s.st["phase"]) == "plan" and not s.dialog_open() and not s.cover.visible \
			and CTurn.pending_for(s.st).is_empty() and s.battle == null
	card.visible = show
	if not show:
		gate_end_button()
		return
	var m := n <= Howto.LESSONS and met(n)
	if n != _shown_n:
		_shown_n = n
		_shown_met = false
		card.clear_buttons()
		var w := clampf(s._vp().x - (s.PANEL_W + 24.0 if s.side.visible else 16.0), 240.0, 520.0)
		if n > Howto.LESSONS:
			card.setup(Howto.text("lesson_over_title"), Howto.text("lesson_over"), "", w - 24.0)
			card.add_button("over", Howto.text("ui_done"))
		else:
			var L := Howto.lesson(n)
			card.setup(Howto.text("ui_lesson_of") % n + ": " + str(L["title"]), str(L["text"]), Howto.text("ui_objective") + str(L["obj"]), w - 24.0)
			card.add_button("skip", Howto.text("ui_skip"))
			card.add_button("leave", Howto.text("ui_leave"))
		card.position = Vector2(8.0, s.TOP_H + 6.0)
	if n <= Howto.LESSONS:
		if m != _shown_met:
			_shown_met = m
			card.set_met(m, Howto.text("ui_objective") + Howto.text("lesson_%d_obj" % n) if not m else "Done. " + Howto.text("lesson_%d_obj" % n) + ". Now end the turn.")
		if card.buttons.has("skip"):
			(card.buttons["skip"] as Button).visible = not m
	card.position = Vector2(8.0, s.TOP_H + 6.0)
	pointer.visible = true
	gate_end_button()


func _advance(n: int) -> void:
	var vd := _vd()
	vd["n"] = n
	vd["done"] = 0
	vd["turn"] = int(s.st["turn"])
	_shown_n = -1
	s.save_plan()


func _on_button(key: String) -> void:
	match key:
		"skip":
			skip()
		"leave":
			leave()
		"over":
			_vd()["off"] = 1
			Tips.suppress = false
			s.save_plan()
			refresh()


func leave() -> void:
	_vd()["left"] = 1
	Tips.suppress = false
	_shown_n = -1
	s.save_plan()
	refresh()
	s.show_toast(Howto.text("ui_left_note"))


## "Skip the lesson": do what the lesson asks (its order, or open nothing: the page flags are set), so the gate opens.
func skip() -> void:
	if not on() or s.f < 0:
		return
	var n := lesson_n()
	var vd := _vd()
	var pr := _pr()
	var sv := _sv()
	var a := _army()
	match n:
		1:
			vd["region"] = 1
		2:
			var have := 0
			for o in s.orders:
				if str(o.get("t", "")) == "recruit" and str(o.get("unit", "")).begins_with("musketeers"):
					have += 1
			for k in maxi(2 - have, 0):
				var o := {"t": "recruit", "r": pr, "unit": "musketeers"}
				if not a.is_empty() and CRules.army_recruit_check(s.ps, s.f, pr, int(a["id"])) == "":
					o["army"] = int(a["id"])
				var why: String = s.add_order(o)
				if why != "":
					s.show_toast("Could not recruit: %s." % why)
					return
		3:
			var why: String = s.add_order({"t": "build", "r": pr, "chain": _chain("range")})
			if why != "":
				s.show_toast("Could not build: %s." % why)
				return
		4:
			if not a.is_empty():
				s.set_move6(int(a["id"]), CGrid.camp(sv), -1)
		5:
			if not a.is_empty():
				s.set_move6(int(a["id"]), CGrid.site(sv), -1)
		6:
			var why6: String = s.add_order({"t": "assault", "r": sv})
			if why6 != "":
				s.show_toast("Could not order the assault: %s." % why6)
				return
		7:
			vd["realm"] = 1
		8:
			var why8: String = s.add_order({"t": "propose", "to": CData.faction_index("dutch"), "what": "trade"})
			if why8 != "":
				s.show_toast("Could not propose: %s." % why8)
				return
		9:
			var fl := _fleet()
			if not a.is_empty() and not fl.is_empty():
				s.set_board(int(a["id"]), int(fl["id"]))
				s.set_fmove(int(fl["id"]), sail_cell())
		10:
			vd["goals"] = 1
	_shown_met = false
	s.save_plan()
	s._refresh_top()
	refresh()


static func _chain(key: String) -> int:
	for c in CData.CHAINS.size():
		if str(CData.CHAINS[c]["key"]) == key:
			return c
	return -1


# ------------------------------------------------------------- the pointer ---

func _map_pt(cell: int) -> Variant:
	if cell < 0 or s.overlay == null:
		return null
	return s.overlay.to_screen(MapOverlay.cell_point(cell))


func _top_button(text: String) -> Variant:
	for b in s.top_box.get_children():
		if b is Button and (b as Button).text == text:
			return TutorPointer.center_of(b)
	return null


func _cmd_button(nm: String) -> Variant:
	if s.cmd_bar == null:
		return null
	return TutorPointer.center_of(s.cmd_bar.find_child(nm, true, false) as Control)


func _dialog_button(nm: String) -> Variant:
	if not s.dialog_open():
		return null
	return TutorPointer.center_of(s.dialog.find_child(nm, true, false) as Control)


func _army_pt() -> Variant:
	var a := _army()
	if a.is_empty():
		return null
	var pos: Dictionary = s.overlay.army_positions()
	return pos.get(int(a["id"]), null)


func _fleet_pt() -> Variant:
	var fl := _fleet()
	if fl.is_empty():
		return null
	var pos: Dictionary = s.overlay.fleet_positions()
	return pos.get(int(fl["id"]), null)


## Where the pointer is now (a screen point) or null.
func _target() -> Variant:
	if not on() or card == null or not card.visible or s.dialog_open():
		return null
	var n := lesson_n()
	if n > Howto.LESSONS:
		return null
	if met(n):
		return TutorPointer.center_of(s.end_button)
	var a := _army()
	var army_sel: bool = not a.is_empty() and s.sel_army == int(a["id"])
	match n:
		1:
			return _map_pt(CGrid.site(_pr()))
		2:
			var p: Variant = _dialog_button("recruit_musketeers")
			if p != null:
				return p
			if army_sel:
				return _cmd_button("act_recruit")
			return _army_pt()
		3:
			if s.sel_region == _pr():
				return _cmd_button("act_build")
			return _map_pt(CGrid.site(_pr()))
		4:
			if army_sel:
				return _map_pt(CGrid.camp(_sv()))
			return _army_pt()
		5:
			if army_sel:
				return _map_pt(CGrid.site(_sv()))
			return _army_pt()
		6:
			if s.sel_region == _sv():
				var b: Variant = _cmd_button("act_siege_assault")
				if b != null:
					return b
			return _map_pt(CGrid.site(_sv()))
		7:
			return _top_button("Realm")
		8:
			return _top_button("Diplomacy")
		9:
			var fl := _fleet()
			if fl.is_empty():
				return null
			var fid := int(fl["id"])
			var boarded := false
			for o in s.orders:
				if (str(o.get("t", "")) == "move" or str(o.get("t", "")) == "embark") and int(o.get("fleet", -1)) == fid:
					boarded = true
			if CFleet.carried_units(fl) > 0:
				boarded = true
			if not boarded:
				if army_sel:
					return _fleet_pt()
				return _army_pt()
			if s.sel_fleet == fid:
				return _map_pt(sail_cell())
			return _fleet_pt()
		10:
			return _top_button("Goals")
	return null
