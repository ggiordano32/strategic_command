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
## `tutorial_turns`, 10 turns) and the cards stop.
## Seats (2026-10-29, the follow-ups): each human seat has its own lesson state (`PROFILES`: England at Port Royal against
## Sevilla la Nueva, France at Leogane (the region Saint-Domingue) against Cibao on Hispaniola), kept
## in the save's session (hot seat) or in the online seat's session blob (a one-human online campaign); the cards, the
## pointer and the gate follow the seat whose turn it is. Online the tutorial runs only while the campaign has one human.

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
## The seats a guided campaign can have, in the order they are added (one human: England; a second on the same device: France).
## `home` the town the lessons start from, `target` the Spanish town they take, `partner` the nation proposed a trade,
## `cede` a far region of the seat handed to Spain (a Spanish raid on it would interrupt the lessons), `sail` the town whose coast the voyage aims at, `sail_name` how the lesson text says it, `names` the text replaced for
## this seat (the words are written for England).
const PROFILES := [
	{"faction": "england", "home": "port_royal", "target": "sevilla_jamaica", "partner": "dutch", "sail": "port_de_paix", "sail_name": "Tortuga coast",
		"cede": ["belize"], "names": {}},
	{"faction": "france", "home": "leogane", "target": "santiago_caballeros", "partner": "dutch", "sail": "port_royal", "sail_name": "Jamaica coast",
		"cede": ["new_orleans"],
		"names": {"Port Royal": "Saint-Domingue", "Sevilla la Nueva": "Cibao", "just west of you": "close by", "Sevilla": "Cibao", "Tortuga coast": "Jamaica coast"}},
]

var s  # the campaign screen
var card: TutorCard
var pointer: TutorPointer
var _shown_n := -1
var _shown_met := false
var _gate_on := false     # the End turn button is held by a lesson
var _shown_f := -2        # the seat the card was built for
var _as := -2             # a seat to read instead of the screen's (the battle script of a seat that is not the planner)


func _init(screen) -> void:
	s = screen


# --------------------------------------------------------------- the start ---

## The tutorial campaign's starting state: the West for England, Sevilla la Nueva (Santiago de la Vega, a village on
## Jamaica) Spanish with its garrison, Belize too (so no Spanish raid on it interrupts the lessons), England's second army folded into the one at Port Royal (a pike, two musketeers, a
## horse and the general: two recruits later make four musketeers), more gold, the AIs on Easy for the battle and the
## chosen skill for the campaign, deployment waiting for the player. `ai_skill`: 0 Easy, 1 Average, 2 Skilled.
## `players` 1 or 2: the second human (hot seat, one device) is France on Hispaniola with its own lessons. `extra`: settings
## to add (the Host screen's turn timeout for an online tutorial).
static func make_state(nm: String, sd: int, ai_skill: int = 0, players: int = 1, extra: Dictionary = {}) -> Dictionary:
	CData.use_pack("west")
	var humans: Array = []
	for i in clampi(players, 1, PROFILES.size()):
		humans.append(CData.faction_index(str(PROFILES[i]["faction"])))
	var stt := {"tutorial": 1, "tutorial_turns": TURNS, "ai_battle_skill": 0, "ai_campaign_skill": ai_skill, "deploy_time": -1}
	for k in extra:
		stt[k] = extra[k]
	var st := CState.new_campaign(nm, sd, humans, stt, [], "west")
	var spa := CData.faction_index("new_spain")
	var armies: Array = st["armies"]
	for i in humans.size():
		var P: Dictionary = PROFILES[i]
		var hf: int = humans[i]
		var sv := CData.region_index(str(P["target"]))
		st["regions"][sv]["owner"] = spa
		for c in P["cede"]:
			st["regions"][CData.region_index(str(c))]["owner"] = spa
		if CState.dip(st, hf, spa) != CState.WAR:
			CState.set_dip(st, hf, spa, CState.WAR)
		var home := CData.region_index(str(P["home"]))
		for j in range(armies.size() - 1, -1, -1):
			if int(armies[j]["f"]) == hf and (int(armies[j]["r"]) == sv or (i > 0 and int(armies[j]["r"]) != home)):
				armies.remove_at(j)
		for a in armies:
			if int(a["f"]) == hf and int(a["r"]) == home:
				var keep: Array = []
				var want := {"w_pikemen": 1, "musketeers": 2, "pistoleers": 1, "general": 1}
				for u in a["units"]:
					var k := str(u["t"])
					if int(want.get(k, 0)) > 0:
						want[k] = int(want[k]) - 1
						keep.append(u)
				a["units"] = keep
		st["factions"][hf]["treasury"] = START_TREASURY
	return st


## The seat's profile (see PROFILES), or {} for a faction with no lessons.
static func profile(st: Dictionary, f: int) -> Dictionary:
	if f < 0 or not st.has("humans"):
		return {}
	for P in PROFILES:
		if CData.faction_index(str(P["faction"])) == f:
			return P
	return {}


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


## The seat the lessons are read for: the planner (the first human between turns).
func seat() -> int:
	if _as != -2:
		return _as
	if s.f >= 0:
		return s.f
	return int(s.st["humans"][0]) if not s.st.is_empty() and not (s.st["humans"] as Array).is_empty() else -1


## The tutorial is running for this seat of this screen (a tutorial campaign, a seat with a profile, not left or finished;
## online only while the campaign has one human: a second human joining ends it for both, the flag stays).
func on() -> bool:
	if s.st.is_empty() or not is_tutorial(s.st) or profile(s.st, seat()).is_empty():
		return false
	if s.online != null and (s.st["humans"] as Array).size() != 1:
		return false
	var vd := _vd()
	return int(vd["off"]) == 0 and int(vd["left"]) == 0


## The view data of the seat: the save's session (key `tutorial` for the first human, `tutorial<seat>` for the others) or
## the online seat's session blob; created with its defaults.
func _vd() -> Dictionary:
	var f := seat()
	var key := "tutorial" if f == int(s.st["humans"][0]) else "tutorial%d" % f
	var ses: Dictionary = s.online.session if s.online != null else s.data["session"]
	if not ses.has(key) or not (ses[key] is Dictionary):
		ses[key] = {"n": 1, "turn": int(s.st.get("turn", 0)), "done": 0, "region": 0, "realm": 0, "goals": 0, "left": 0, "off": 0}
	return ses[key]


## Keep the lesson state: the save (a hot seat), the online session.
func _persist() -> void:
	if s.online != null:
		s.online._touch_session()
	else:
		s.save_plan()


## The lesson's words for this seat (the text is written for England).
func tx(key: String) -> String:
	return localize(Howto.text(key))


func localize(t: String) -> String:
	var names: Dictionary = profile(s.st, seat()).get("names", {})
	for k in names:
		t = t.replace(str(k), str(names[k]))
	return t


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
		_persist()
		s._refresh_top()
		refresh()


func _pr() -> int:
	return CData.region_index(str(profile(s.st, seat()).get("home", "port_royal")))


func _sail_town() -> String:
	return str(profile(s.st, seat()).get("sail", "port_de_paix"))


func _sv() -> int:
	return CData.region_index(str(profile(s.st, seat()).get("target", "sevilla_jamaica")))


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
static func sail_cell(town: String = "port_de_paix") -> int:
	var h := CFleet.harbour(CData.region_index(town))
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
			var dutch := CData.faction_index(str(profile(s.st, seat()).get("partner", "dutch")))
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
			var h := CFleet.harbour(CData.region_index(_sail_town()))
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
		Kit.tip(s.end_button, Howto.text("ui_gate"), Howto.text("ui_objective") + tx("lesson_%d_obj" % lesson_n()) + ".")
	elif _gate_on:
		s.end_button.disabled = not CTurn.pending_for(s.st).is_empty() or s.f < 0 or str(s.st["phase"]) == "over"
		Kit.tip(s.end_button, "", "")
	_gate_on = h


## End turn pressed while held: say why. True when it was held.
func guard_end() -> bool:
	if not holds_end():
		return false
	s.show_toast("%s: %s." % [Howto.text("ui_gate"), tx("lesson_%d_obj" % lesson_n())])
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
	if s.st.is_empty() or not is_tutorial(s.st):
		return null
	var hs: Array = CRules.battle_humans(s.st, b)
	var script = null
	for h in hs:
		_as = int(h)
		if on() and lesson_n() == BATTLE_LESSON and int(b.get("r", -1)) == _sv():
			script = TutorialBattle.new()
		_as = -2
		if script != null:
			break
	return script


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
	if _shown_f != seat():
		_shown_f = seat()
		_shown_n = -1
	if n == BATTLE_LESSON and CState.owner(s.st, _sv()) == seat():
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
			card.setup(Howto.text("ui_lesson_of") % n + ": " + localize(str(L["title"])), localize(str(L["text"])), Howto.text("ui_objective") + localize(str(L["obj"])), w - 24.0)
			card.add_button("skip", Howto.text("ui_skip"))
			card.add_button("leave", Howto.text("ui_leave"))
		card.position = Vector2(8.0, s.TOP_H + 6.0)
	if n <= Howto.LESSONS:
		if m != _shown_met:
			_shown_met = m
			card.set_met(m, Howto.text("ui_objective") + tx("lesson_%d_obj" % n) if not m else "Done. " + tx("lesson_%d_obj" % n) + ". Now end the turn.")
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
	_persist()


func _on_button(key: String) -> void:
	match key:
		"skip":
			skip()
		"leave":
			leave()
		"over":
			_vd()["off"] = 1
			Tips.suppress = false
			_persist()
			refresh()


func leave() -> void:
	_vd()["left"] = 1
	Tips.suppress = false
	_shown_n = -1
	_persist()
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
			var why8: String = s.add_order({"t": "propose", "to": CData.faction_index(str(profile(s.st, seat()).get("partner", "dutch"))), "what": "trade"})
			if why8 != "":
				s.show_toast("Could not propose: %s." % why8)
				return
		9:
			var fl := _fleet()
			if not a.is_empty() and not fl.is_empty():
				s.set_board(int(a["id"]), int(fl["id"]))
				s.set_fmove(int(fl["id"]), sail_cell(_sail_town()))
		10:
			vd["goals"] = 1
	_shown_met = false
	_persist()
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
				return _map_pt(sail_cell(_sail_town()))
			return _fleet_pt()
		10:
			return _top_button("Goals")
	return null
