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
## terrain preview instead of the city, no equipment line, the cards; the
## defenders bring 26 units and more (their support), so the card lists
## those past the 24 field slots as "Arriving: n units" (reinforcements).
## The end of a campaign battle: at the decision the End battle / Continue
## modal (no return timer); Continue keeps the timer off, relabels the
## top-right button "End battle" and the pursuit runs past the old 60 s
## end; that button ends it and the screen returns; End battle in the modal
## ends it on the next tick and returns.
## A fleet at the shore (2026-11-05): a port town battle with the player's ships off the quay opens with the ship
## layer under the men (drawn by the board's lift in the oblique view), a hull for each of the three ships in her
## faction's colours, each ship's crew on her deck.
## Then the whole run again in the oblique battle view (tabletop pass 3, BoardView.force = "oblique"; the checks
## marked "[oblique]"): the same assertions, plus the battles open in that view with the upright figures' shaders; and once
## more in the 3D view (BoardView.force = "3d", "[3d]"; docs/design/art_pipeline.md "The 3D battle view, step one"): the same
## assertions plus `_v3d_cases`.

const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const BattleScreen := preload("res://game/campaign/battle_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CChars := preload("res://campaign/cchars.gd")
const UT := preload("res://sim/unit_types.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const CityPreview := preload("res://game/campaign/city_preview.gd")
const Battle := preload("res://game/battle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const SoldierLayer := preload("res://game/soldier_layer.gd")
const BoardView := preload("res://game/board_view.gd")

var cs: CampaignScreen
var rome := CData.faction_index("rome")
var target := CData.region_index("sicilia_or")
var _ok := true
var _frame := 0
var _step := 0
var _wait := 0
var _bid := -1
var _snap: Dictionary = {}
var _hero: Dictionary = {}
var _oblique := false   # the second run: the oblique battle view
var _v3d := false       # the third run: the 3D battle view (game/view3d.gd; oblique true as well: the same board transform)
var _rub: _RubNode = null  # (the top view's rubble mark, drawn on a frame after _cover_cases)
var _roll_b = null           # (the stone rolls and breaks: a battle whose overlay draws its impact ring on the next frames)
var _roll_phase := 0         # 0 not begun in this view, 1 drawing, 2 checked
var _roll_frames := 0


## Cover and line of fire, fourth pass (2026-11-06): draws a breached West stretch's rubble as the top view does (up
## 0) and as the oblique view's kit does (up > 0), counting the top view's heap marks (CityDraw.heap_marks).
class _RubNode extends Node2D:
	const CityDraw := preload("res://game/city_draw.gd")
	var sim
	var cells := PackedInt32Array()
	var marks := -1
	var marks_ob := -1
	func _draw() -> void:
		var m0: int = CityDraw.heap_marks
		CityDraw.draw_rubble(self, sim, cells, 4.0, Vector2.ZERO, false, 0.0)
		marks = CityDraw.heap_marks - m0
		var m1: int = CityDraw.heap_marks
		CityDraw.draw_rubble(self, sim, cells, 4.0, Vector2.ZERO, false, 2.0)
		marks_ob = CityDraw.heap_marks - m1


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + ("[3d] " if _v3d else ("[oblique] " if _oblique else "")) + what)
	if not c:
		_ok = false


func _initialize() -> void:
	BoardView.force = "top"
	_begin()


func _begin() -> void:
	target = CData.region_index("sicilia_or")
	_bid = -1
	_snap = {}
	_hero = {}
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
	var hl = scr.find_child("char_0_%d" % int(_hero["id"]), true, false)
	_check(hl is Label and (hl as Label).text.contains(str(_hero["name"])) and (hl as Label).text.contains("Master of Horse"),
		"the pre-battle card lists the attackers' hero: " + ((hl as Label).text if hl is Label else "-"))


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
	_check(mode.begins_with("Auto-resolved") if auto else mode.begins_with("Fought (you left the battle)"), "labelled: " + mode)
	_check(_label(res, "result_outcome") != "", "the one-line outcome")
	if auto:
		_check(res.find_child("char_0_%d" % int(_hero["id"]), true, false) != null, "the result card still lists the hero")
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
					"withdrawn": 0, "remaining": n - n / 4, "kills": 3 + k,
					"kills_by": [["heavy", 2 + k], ["archer", 1]] if k > 0 else [["heavy", 3]]})
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
	# A tap on a card with kills expands them under its group's cards.
	var tap = null
	for c in _cards(res):
		if c.kills > 3 and tap == null:
			tap = c
	var shown := ""
	if tap != null:
		tap.tapped.emit()
		for l in res.find_children("kills_detail_*", "Label", true, false):
			if (l as Label).visible:
				shown = (l as Label).text
	_check(tap != null and shown.contains("killed %d" % tap.kills) and shown.contains("x Heavy") and shown.contains("per 10 lost"),
		"a tap on a card lists its kills by enemy type: " + shown)
	var kd := Kit.kills_detail("U", 40, 10, [["heavy", 30], [1, 5], ["archer", 1], ["spear", 1], ["javelin", 1], ["cav", 2]])
	_check(kd.contains("(40 per 10 lost)") and kd.contains("30 x Heavy") and kd.ends_with("+2 others")
		and Kit.kills_detail("U", 5, 0, []).contains("lost none") and Kit.effect_short(40, 10) == "40/10" and Kit.effect_short(5, 0) == "",
		"kills_detail names the top 5 and sums the rest; nothing lost reads 'lost none': " + kd)
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
	if _rub != null and _rub.marks >= 0:
		_check(_rub.marks > 0 and _rub.marks_ob == 0 and _rub.cells.size() > 0,
			"rubble (drawn on the frame after the top view's run): the top view draws the heap's mark on a breach (%d of %d cells), the oblique view its heaped stones instead (%d)" % [
				_rub.marks, _rub.cells.size(), _rub.marks_ob])
		_rub.queue_free()
		_rub = null
	if _roll_phase == 1:
		_roll_frame()
	if _wait > 0:
		_wait -= 1
		return false
	_step += 1
	match _step:
		1:
			var a1: Dictionary = CState.armies_of(cs.st, rome)[0]
			# A Master of Horse rides with it (heroes and agents).
			_hero = CChars.make_char(cs.st, rome, "hero_cav", int(a1["r"]), int(a1["id"]))
			_assault(a1, true)
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
				_check(BoardView.oblique == _oblique and cs.battle.soldiers.oblique == _oblique,
					"the battle opens in the %s view" % ("oblique" if _oblique else "top"))
				_check((cs.battle.view3d != null) == _v3d and BoardView.v3d == _v3d,
					"the 3D scene is built only in the 3D view (%s)" % str(cs.battle.view3d != null))
				if _v3d:
					_v3d_cases(cs.battle)
				cs.battle.hud.menu_pressed.emit()
				_check(cs.battle.leave_dialog == null, "a Leave tap while the battle opens does nothing")
				cs.battle.leave_grace = 0.0
				cs.battle.hud.menu_pressed.emit()
			_wait = 5
		8:
			if cs.battle != null:
				var dlg: Control = cs.battle.leave_dialog
				_check(dlg != null and dlg.visible, "then Leave asks in a modal")
				var go: Button = dlg.find_child("leave_go", true, false) if dlg != null else null
				if go != null:
					go.pressed.emit()
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
				var arr := _label(scr, "arriving_1")
				var on2 := 0
				for g in sn["sides"][1]:
					for u in g["units"]:
						if int(u["on"]) == 2:
							on2 += 1
				_check(on2 >= 2 and arr.begins_with("Arriving: %d units" % on2) and _label(scr, "arriving_0") == "",
					"the defenders' reinforcements line: " + arr)
			_end_open()
			_wait = 5
		13:
			_end_decide()
			if _eb != null and _eb.end_dialog != null:
				var cont: Button = _eb.end_dialog.find_child("end_continue", true, false)
				if cont != null:
					cont.pressed.emit()
			_wait = 3
		14:
			_end_pursue()
			_wait = 3
		15:
			if _eb != null and not _eb_exit and _frame < 40000:
				_step -= 1  # (the end banner's short wait, then back)
				return false
			_check(_eb_exit, "after End battle the battle returns to the campaign")
			_end_close()
			_end_open()
			_wait = 5
		16:
			_end_decide()
			if _eb != null and _eb.end_dialog != null:
				var go: Button = _eb.end_dialog.find_child("end_go", true, false)
				if go != null:
					go.pressed.emit()
			if _eb != null:
				_eb._do_tick()
				_check(_eb.sim.ended != 0 and _eb.sim.pursue == 0 and _eb.sim.end_how() == "end" and not _eb.end_dialog.visible,
					"End battle in the modal ends the battle on the next tick")
			_wait = 3
		17:
			if _eb != null and not _eb_exit and _frame < 40000:
				_step -= 1
				return false
			if _roll_phase == 0:
				_check(_eb_exit, "and returns to the campaign")
				_end_close()
				_facing_cases()
				_casualty_cases()
				_ship_cases()
				_flash_cases()
				_cover_cases()
				_supp_cases()
				_roll_cases()
				_track_cases()
			if _roll_phase == 1:
				_step -= 1  # (the stone's roll is drawn on the next frames: _roll_frame)
				return false
			_roll_phase = 0
			if not _oblique or not _v3d:
				# Again, in the oblique battle view, then in the 3D view.
				_v3d = _oblique
				_oblique = true
				BoardView.force = "3d" if _v3d else "oblique"
				if is_instance_valid(cs):
					cs.queue_free()
				_begin()
				_step = 0
				_frame = 0
				_wait = 3
				return false
			BoardView.force = ""
			print("RESULT: ", "PASS" if _ok else "FAIL")
			quit(0 if _ok else 1)
	return false


# End of a campaign battle (docs/DESIGN.md "Battle end: End battle /
# Continue"): a battle screen in campaign mode on test_pike_front (both
# sides human; the player side 0), stepped by hand to the decision.
var _eb = null
var _eb_exit := false


func _end_open() -> void:
	_eb = Battle.new()
	_eb.scenario_id = "test_pike_front"
	_eb.seed_value = 7
	_eb.campaign_mode = true
	_eb_exit = false
	_eb.exit_requested.connect(func(): _eb_exit = true)
	root.add_child(_eb)
	_check(_eb.soldiers.oblique == _oblique and (not _oblique or _eb.soldiers._blocks == SoldierLayer.BLOCKS + 2),
		"the end-of-battle screen's view: %s" % ("oblique (the per-tick order block, the stair heights block)" if _oblique else "top"))


## The 3D view (game/view3d.gd) in a campaign battle: the men come from the CPU-fed buffer into the 3D MultiMesh (every man, no
## probe of the hidden 2D layers), the 2D world layers are not drawn, the board mesh and the camera stand, a turn keeps the
## ground under the screen's centre, and taps come back where the 3D camera shows the ground.
func _v3d_cases(b) -> void:
	var sl = b.soldiers
	_check(sl.cpu_fed and sl.v3d_mm != null and sl.v3d_mm.instance_count == sl._n_inst and not sl.auto_fallback,
		"3D: the men fed from the CPU-fed buffer (%d instances), no 2D probe fallback" % (sl.v3d_mm.instance_count if sl.v3d_mm != null else -1))
	_check(not sl.visible and not b.terrain.visible and not b.trees.visible and b.overlay.visible and b.hud.visible,
		"3D: the 2D world layers hidden, the overlay and the HUD drawn")
	var v = b.view3d
	_check(v.terrain_mi != null and v.terrain_mi.mesh != null and v.cam != null and v.cam.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"3D: the board mesh and the orthographic camera")
	var vp: Vector2 = b.get_viewport_rect().size
	b.camera.force_update_scroll()
	var g0: Vector2 = b._screen_to_world(vp * 0.5)
	b._v3d_turn(deg_to_rad(75.0), 0.0, vp * 0.5)
	b.camera.force_update_scroll()
	var g1: Vector2 = b._screen_to_world(vp * 0.5)
	_check(g0.distance_to(g1) < b.PX_PER_M * 0.2, "3D: a turn keeps the ground under the screen's centre (%.2f m)" % (g0.distance_to(g1) / b.PX_PER_M))
	v.sync_camera()
	var w: Vector2 = g1 + Vector2(30.0, -20.0) * b.PX_PER_M
	var s3: Vector2 = v.cam.unproject_position(Vector3(w.x / b.PX_PER_M, BoardView.ground_m(w), w.y / b.PX_PER_M))
	var back: Vector2 = b._screen_to_world(s3)
	_check(back.distance_to(w) < b.PX_PER_M * 0.3, "3D: a tap where the 3D camera shows a ground point comes back to it (%.2f m)" % (back.distance_to(w) / b.PX_PER_M))
	b._v3d_turn(-deg_to_rad(75.0), 0.0, vp * 0.5)


func _end_close() -> void:
	if _eb != null:
		_eb.queue_free()
		_eb = null


func _end_decide() -> void:
	if _eb == null:
		_check(false, "the end-of-battle screen opened")
		return
	var k := 0
	while _eb.sim.winner < 0 and k < 3000:
		_eb._do_tick()
		k += 1
	var dlg: Control = _eb.end_dialog
	_check(_eb.sim.winner == 0 and _eb.sim.ended == 0 and dlg != null and dlg.visible and _eb._exit_timer <= 0.0
		and dlg.find_child("end_go", true, false) != null and dlg.find_child("end_continue", true, false) != null,
		"at the decision a campaign battle asks End battle / Continue (tick %d), no return timer" % _eb.sim.tick)
	if dlg != null:
		var txt := ""
		for l in dlg.find_children("*", "Label", true, false):
			txt += (l as Label).text + " "
		_check(txt.contains("Victory") and txt.contains("The enemy is broken and running."), "the modal says: " + txt.strip_edges())


func _end_pursue() -> void:
	if _eb == null:
		return
	_check(not _eb.end_dialog.visible and _eb._exit_timer <= 0.0 and _eb.hud.menu_button.text == "End battle"
		and _eb.hud.banner.text.begins_with("Victory: pursuing"),
		"Continue closes the modal, keeps the return timer off, the button reads End battle, the banner: " + _eb.hud.banner.text.replace("\n", " / "))
	var dec: int = _eb.sim.decided_tick
	while _eb.sim.ended == 0 and _eb.sim.tick < dec + BattleSim.END_AFTER + 100:
		_eb._do_tick()
	_check(_eb.sim.pursue == 1 and _eb.sim.ended == 0 and _eb._exit_timer <= 0.0,
		"the pursuit runs on past the old 60 s end (tick %d, decided %d)" % [_eb.sim.tick, dec])
	_eb.hud.menu_pressed.emit()
	_eb._do_tick()
	_check(_eb.sim.ended != 0 and _eb.sim.end_how() == "end" and _eb._exit_timer > 0.0,
		"End battle on the top-right button ends it (%s), the return timer set" % _eb.sim.end_how())


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
	for k in 21:
		(mine["units"] as Array).append({"t": "light", "n": 50})  # (26 units: 2 past the 24 field slots)
	CRules.execute_moves(st, [[id, CData.region_index("samnium"), ep, CData.MODE_MARCH, 0]])
	var b := CState.battle_at(st, CData.region_index("samnium"))
	_check(not b.is_empty() and str(b.get("kind", "")) == "field", "the interception is a pending field battle")
	b.erase("new")
	st["phase"] = "battles"
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "battle_screen_test5")
	root.add_child(cs)


# The men's drawn heading (view only: game/soldier_layer.gd `_update_yaw`,
# docs/DESIGN.md "Men turn to their march"). Headless: the view's arrays.

static func _adiff(a: float, b: float) -> float:
	return fposmod(a - b + 512.0, 1024.0) - 512.0


func _facing_run(move_m: Vector2, ticks: int, probe: Callable, settle := 0) -> Dictionary:
	var sim := BattleSim.new()
	sim.setup(Scenarios.make("skirmish"), 42)
	var lay := SoldierLayer.new()
	root.add_child(lay)
	lay.setup(sim, 24.0)
	var u := 0
	for t in settle:
		sim.step()
		lay.upload()
	var face: int = sim.u_face[u]
	# (From the formation's anchor: the sim snaps a move of at most 12 m from there.)
	sim.queue_order(BattleSim.make_move_order(sim.tick, u, sim.u_ax[u] + int(move_m.x * 1024.0), sim.u_ay[u] + int(move_m.y * 1024.0), face,
			BattleSim.files_to_width(sim.u_files[u], sim.u_type[u]), 0))  # (the width kept: a new width is a big re-form)
	var base: int = sim.u_slot_base[u]
	var men := PackedInt32Array()
	for s in sim.u_alive[u]:
		men.append(sim.slot_soldier[base + s])
	var last := {}
	var st := {"max_step": 0.0, "max_off": 0.0, "moved_max": 0.0, "face": face, "u": u, "men": men}
	var start := PackedVector2Array()
	for i in men:
		start.append(Vector2(sim.pos_x[i], sim.pos_y[i]))
	for t in ticks:
		sim.step()
		lay.upload()
		for k in men.size():
			var i := men[k]
			var y := lay.drawn_yaw(i)
			if last.has(i):
				st["max_step"] = maxf(st["max_step"], absf(_adiff(y, last[i])))
			last[i] = y
			st["max_off"] = maxf(st["max_off"], absf(_adiff(y, float(sim.facing[i]))))
			st["moved_max"] = maxf(st["moved_max"], Vector2(sim.pos_x[i], sim.pos_y[i]).distance_to(start[k]) / 1024.0)
		probe.call(sim, lay, t, st)
	st["sim"] = sim
	st["lay"] = lay
	return st


## Tabletop pass 1: casualties stay on the table (the dead man's last frame and base), fading over 60 s, at most 40 a unit and
## 2000 in all, the oldest first; a routed unit's are lifted off with it.
func _casualty_cases() -> void:
	var sim := BattleSim.new()
	sim.setup(Scenarios.make("bench_2000"), 42)
	var lay := SoldierLayer.new()
	root.add_child(lay)
	lay.setup(sim, 24.0)
	var peak_total := 0
	var peak_unit := 0
	var seen_fade := false
	for t in 1800:
		sim.step()
		lay.upload()
		peak_total = maxi(peak_total, lay._cas_total)
		for u in sim.n_units:
			peak_unit = maxi(peak_unit, lay._cas_kept[u])
	var dead := 0
	var shown := 0
	var gone := 0
	var sts: PackedInt32Array = lay._casualties(sim.state)
	for i in sim.n:
		if sim.state[i] != 4:
			continue
		dead += 1
		if sts[i] == 5:
			gone += 1
		elif sts[i] >= 20 and sts[i] / 16 <= 32:
			shown += 1
			seen_fade = true
	_check(dead > 200, "the battle has casualties to keep (%d dead)" % dead)
	_check(peak_unit <= SoldierLayer.CAS_UNIT and peak_total <= SoldierLayer.CAS_TOTAL,
		"casualties kept: at most %d a unit (peak %d) and %d in all (peak %d)" % [SoldierLayer.CAS_UNIT, peak_unit, SoldierLayer.CAS_TOTAL, peak_total])
	_check(shown + gone == dead and seen_fade and gone > 0, "every dead man is on the table fading (%d) or gone (%d) of %d" % [shown, gone, dead])
	# A unit that routs lifts its casualties off with it.
	var ru := -1
	for u in sim.n_units:
		if lay._cas_kept[u] > 0:
			ru = u
			break
	if ru >= 0:
		sim.u_state[ru] = BattleSim.U_ROUTING
		sts = lay._casualties(sim.state)
		var lifted := true
		for i in range(lay._cas_first[ru], lay._cas_first[ru] + lay._cas_n[ru]):
			if sim.state[i] == 4 and sts[i] != 5:
				lifted = false
		_check(lifted, "a routed unit's casualties are not drawn")
	# Sixty seconds on, a casualty is gone.
	for t in 620:
		sim.step()
		lay.upload()
	var old := 0
	for i in sim.n:
		if lay._cas_dt[i] >= 0 and sim.tick - lay._cas_dt[i] >= SoldierLayer.CAS_LIFE:
			old += 1
	_check(old == 0, "no casualty stays past %d s (%d older ones kept)" % [SoldierLayer.CAS_LIFE / 10, old])
	lay.queue_free()


func _facing_cases() -> void:
	# A long oblique march (58 m): halfway the men face their own march.
	var mid := {"n": 0, "on": 0, "off_final": 0.0}
	var probe_long := func(sm, ly, t: int, st: Dictionary) -> void:
		if t == 120:
			for i in st["men"]:
				var dx: float = sm.pos_x[i] - sm.prev_x[i]
				var dy: float = sm.pos_y[i] - sm.prev_y[i]
				if dx * dx + dy * dy < 400.0:
					continue
				mid["n"] += 1
				var hd := atan2(dy, dx) * 1024.0 / TAU
				if absf(_adiff(ly.drawn_yaw(i), hd)) <= 40.0 and absf(_adiff(ly.drawn_yaw(i), float(st["face"]))) > 40.0:
					mid["on"] += 1
	var r := _facing_run(Vector2(50, 30), 520, probe_long)
	var sim: BattleSim = r["sim"]
	var lay = r["lay"]
	_check(mid["n"] >= 20 and mid["on"] >= mid["n"] * 8 / 10,
		"a long march: halfway %d of %d moving men are drawn along their own movement, not the unit's facing" % [mid["on"], mid["n"]])
	var back := true
	for i in r["men"]:
		if sim.state[i] == 0 and absf(_adiff(lay.drawn_yaw(i), float(sim.u_face[0]))) > 2.0:
			back = false
	_check(sim.u_order[0] == 0 and sim.u_face[0] == r["face"] and back,
		"on arrival every man is drawn at the unit's facing again (%d)" % sim.u_face[0])
	_check(r["max_step"] <= float(lay.yaw_cap) + 0.5,
		"the yaw-rate cap: no man turns more than %d units (%.0f degrees) a tick; the worst %.1f" % [lay.yaw_cap, lay.yaw_cap * 360.0 / 1024.0, r["max_step"]])
	lay.queue_free()
	# A short re-form (8 m to the side, the same facing): the men keep it.
	var rr := _facing_run(Vector2(0, 8), 45, func(_a, _b, _t, _c): pass, 120)
	_check(rr["moved_max"] > 3.0 and rr["max_off"] < 0.5,
		"a short re-form: men moved up to %.1f m and are drawn at the unit's facing throughout (largest difference %.1f units)" % [rr["moved_max"], rr["max_off"]])
	(rr["lay"] as Node).queue_free()


## (2026-11-05) A fleet at the shore in the battle view (docs/design/art_pipeline.md "(2026-11-05) The ship on the board").
## The muzzle flash belongs to the man who fired (docs/design/art_pipeline.md "The muzzle flash is the man's own"): a musket line
## fires at a standing block; on a tick of fire the flashes shown equal the sim's gun shots that tick (the front rank of the
## countermarch, not the whole unit), a second later none; archers loosing arrows make none. tests/muzzle_flash_probe.gd has the
## table for every case and both soldier paths.
func _flash_cases() -> void:
	var was := CData.pack
	CData.use_pack("west")
	for bow in [false, true]:
		var b := Battle.new()
		b.custom_scenario = {"width_m": 300, "height_m": 300, "ai_sides": [], "units": [
			Scenarios.unit(0, UT.index_of("archer" if bow else "musketeers"), 80 if bow else 100, 150, 200, 768),
			Scenarios.unit(1, UT.index_of("heavy"), 100, 150, 130, 256)], "orders": [Scenarios.attack(0, 0, 1, 0)]}
		b.seed_value = 3
		root.add_child(b)
		b.paused = true
		var s: BattleSim = b.sim
		var ov = b.overlay
		var fired_ticks := 0
		var matched := 0
		var partial := 0   # fire ticks on which only some of the men fired (the countermarch's front rank)
		var arrows := 0
		for t in 300:
			s.step()
			b.soldiers.upload()
			ov._process(0.13)   # (a tick is 0.1 s: last tick's flash has faded)
			var shots := 0
			for p in s.pr_t1.size():
				if s.pr_t1[p] >= 0 and s.pr_t0[p] == s.tick - 1:
					if s.t_m_gun[s.pr_ty[p]] != 0:
						shots += 1
					else:
						arrows += 1
			if shots > 0:
				fired_ticks += 1
				if shots < s.u_alive[0]:
					partial += 1
				if ov.flashes_live == shots:
					matched += 1
			elif ov.flashes_live != 0:
				matched -= 1000
		for i in 10:
			ov._process(0.1)
		if bow:
			_check(arrows > 0 and ov.flashes_made == 0, "bows: %d arrows loosed, no muzzle flash made (%d)" % [arrows, ov.flashes_made])
		else:
			_check(fired_ticks >= 3 and matched == fired_ticks and partial >= 3,
				"musket line: the flashes shown equal the sim's shots on each of %d fire ticks (%d of them a front rank of 25 of the 100, not the unit), none on the ticks between" % [fired_ticks, partial])
			_check(ov.flashes_live == 0, "musket line: no flash a second after the last shot")
		b.queue_free()
	CData.use_pack(was)


## Cover and line of fire, second pass (docs/design/ui.md "Cover chips and hittable marks", 2026-11-06): the cover
## chip on the markers reads what the troop type gets (a musket line behind a 1.3 m wall: light; behind a 2.5 m one:
## heavy; in the open: none; riders behind the low wall: none), its tick points at the nearest enemy; while a musket
## line is selected an enemy behind a house is marked blocked and one in the open hittable; the overlay draws them.
## Tracks on the board (docs/design/art_pipeline.md "Tracks on the board", 2026-11-06): the ground-marks layer has stamped
## nothing when the battle opens; after a march of a foot column, a cavalry unit and a gun it has stamped each kind (foot
## wear, hoof churn, two ruts); a unit that stands leaves none; a stone's landing stamps one furrow. Headless the layer keeps
## no texture and counts its stamps; windowed it also owns the texture (tests/ has no windowed run: the shots read it).
func _track_cases() -> void:
	var was := CData.pack
	CData.use_pack("west")
	var b := Battle.new()
	b.custom_scenario = {"width_m": 400, "height_m": 200, "ai_sides": [], "units": [
		Scenarios.unit(0, UT.index_of("heavy"), 60, 40, 50, 0),
		Scenarios.unit(0, UT.index_of("lancers"), 30, 40, 100, 0),
		Scenarios.unit(0, UT.index_of("field_gun"), 4, 40, 150, 0),
		Scenarios.unit(0, UT.index_of("heavy"), 40, 40, 180, 0),
		Scenarios.unit(1, UT.index_of("heavy"), 40, 380, 100, 512)], "orders": []}
	b.seed_value = 3
	root.add_child(b)
	b.paused = true
	var s: BattleSim = b.sim
	var trk = b.tracks
	_check(trk != null and trk.stamps == 0 and trk.passes == 0 and trk.furrows == 0, "tracks: the layer exists and has stamped nothing when the battle opens")
	var start := Vector2(s.u_cx[3], s.u_cy[3]) / 1024.0
	for u in 3:
		s.queue_order(BattleSim.make_move_order(s.tick, u, 300 * 1024, int(s.u_cy[u]), 0, BattleSim.files_to_width(s.u_files[u], s.u_type[u]), 0))
	for t in 400:
		s.step()
		if t % 10 == 9:
			trk.stamp()
	_check(trk.by_channel.x > 0 and trk.by_channel.y > 0 and trk.by_channel.z > 0,
		"tracks: a march stamped foot wear (%d), ruts behind the gun (%d) and hoof churn behind the horse (%d)" % [trk.by_channel.x, trk.by_channel.y, trk.by_channel.z])
	var moved := Vector2(s.u_cx[3], s.u_cy[3]) / 1024.0
	_check(moved.distance_to(start) < 1.0, "tracks: the unit left standing did not move (%.1f m), so it has no stamp to its name" % moved.distance_to(start))
	var f0: int = trk.furrows
	var k: int = s.fx_head
	s.fx_x[k] = 200 * 1024
	s.fx_y[k] = 100 * 1024
	s.fx_dx[k] = 4096
	s.fx_dy[k] = 0
	s.fx_t[k] = s.tick
	s.fx_k[k] = BattleSim.FXK_STONE
	s.fx_r[k] = 8 * 1024
	s.fx_h[k] = 0
	s.fx_head = (k + 1) % s.fx_x.size()
	trk.stamp()
	_check(trk.furrows == f0, "tracks: a stone still rolling has no furrow yet")
	for t in 25:
		s.step()
	trk.stamp()
	trk.stamp()
	_check(trk.furrows == f0 + 1, "tracks: a stone's furrow is stamped once, after its run (the overlay no longer draws the line)")
	b.queue_free()
	CData.use_pack(was)


## Suppression (2026-11-06; docs/design/ui.md "Suppression chips"): a player's musket line under fire is suppressed
## (its meter set, the sim's own state from it), then pinned; its men carry the crouch level in the soldier flags (both
## paths, the 3D view's buffer from the same flags; on the CPU path the buffer's flags column), its card strip and its
## tokens say Suppressed / Pinned; an enemy line's state reads the same (the marker chip is drawn for every side).
func _supp_cases() -> void:
	const Terrain := preload("res://sim/terrain.gd")
	var b := Battle.new()
	b.custom_scenario = {"width_m": 400, "height_m": 300, "ai_sides": [], "orders": [], "los": 1, "time_limit": 600,
		"terrain": {"kind": Terrain.K_FLAT},
		"units": [Scenarios.unit(0, UT.index_of("musketeers"), 40, 170, 160, Scenarios.FACE_DOWN, 10),
			Scenarios.unit(1, UT.index_of("musketeers"), 60, 170, 230, Scenarios.FACE_UP, 15)]}
	b.seed_value = 3
	root.add_child(b)
	b.paused = true
	var s: BattleSim = b.sim
	var sl = b.soldiers
	for lv in [1, 2]:
		s.u_sup[0] = 600 if lv == 1 else 1000
		s.u_sut[0] = s.tick
		s.u_sup[1] = s.u_sup[0]
		s.u_sut[1] = s.tick
		s.step()
		sl.upload()
		var fl: int = sl._flags[0]
		var cpu_ok := true
		if sl.cpu_fed and sl._n_inst > 0:
			var first: int = s.slot_soldier[s.u_slot_base[0]]
			cpu_ok = false
			for r in range(0, sl._runs.size(), 3):
				if sl._runs[r + 2] == 0 and first >= sl._runs[r] and first < sl._runs[r] + sl._runs[r + 1]:
					cpu_ok = int(sl._cbuf.get_pixel(SoldierLayer.C_FLAGS, first).r) == fl
		var cs_: Array = b._card_states(0)
		var word := "Pinned" if lv == 2 else "Suppressed"
		var has_word := false
		for g in cs_:
			if str(g[1]) == word and str(g[0]) == word.to_lower():
				has_word = true
		var toks: Array = b.overlay._tokens(0)
		var tok := false
		for t in toks:
			if str(t[0]) == word.to_lower():
				tok = true
		_check(s.supp_state(0) == lv and s.supp_state(1) == lv and (fl / SoldierLayer.F_CROUCH) & 3 == lv and cpu_ok and has_word and tok,
			"suppression: %s: the sim's state %d (enemy %d), the men's crouch level %d in the flags (CPU buffer %s), the card strip %s, token %s" % [
				word, s.supp_state(0), s.supp_state(1), (fl / SoldierLayer.F_CROUCH) & 3, str(cpu_ok), str(cs_), str(tok)])
		b.overlay._tok_at.fill(-100)
	b.queue_free()


## The stone rolls and breaks (2026-11-06; docs/design/art_pipeline.md "The stone rolls and breaks (as built,
## 2026-11-06)"): a landed stone runs on its sim run (BattleSim.fx_r) from 0 to the full run, slowing, then rests; a
## ball's first 40 % is one bounce off the ground; a stone that struck a wall (FXK_STRIKE) shatters at the face. The
## overlay draws, on the next frames, a running stone, a ball, a breaking stone, a sinking one and a shatter (its draw
## counts), in each view.
func _roll_cases() -> void:
	const Terrain := preload("res://sim/terrain.gd")
	const Ov := preload("res://game/overlay.gd")
	var a0 := Ov.stone_run_at(12.0, 0.0, false)
	var a1 := Ov.stone_run_at(12.0, 6.0, false)
	var a2 := Ov.stone_run_at(12.0, 40.0, false)
	var mid := Ov.stone_run_at(12.0, 6.66, false)
	var b_hop := Ov.stone_run_at(20.0, 2.0, true)
	var b_roll := Ov.stone_run_at(20.0, 8.0, true)
	_check(a0.x == 0.0 and a1.x > 0.0 and a1.x < 12.0 and a1.z < 0.0 and a2.x == 12.0 and a2.z > 0.0 and mid.x > 6.0 \
			and b_hop.y > 0.0 and b_hop.x <= 8.0 and b_roll.y == 0.0 and b_roll.x > 8.0,
		"the stone rolls: a 12 m run from %.1f to %.1f (moving %.1f m at 0.6 s, half time %.1f m: slowing) to rest at 12 m; a ball's bounce %.2f m up at %.1f m, then rolling at %.1f m" % [
			a0.x, a2.x, a1.x, mid.x, b_hop.y, b_hop.x, b_roll.x])
	var b := Battle.new()
	b.custom_scenario = {"width_m": 400, "height_m": 300, "ai_sides": [], "orders": [], "los": 0, "time_limit": 600,
		"terrain": {"kind": Terrain.K_FLAT},
		"units": [Scenarios.unit(0, UT.STONE, 18, 200, 100, Scenarios.FACE_DOWN),
			Scenarios.unit(1, UT.SPEAR, 60, 200, 160, Scenarios.FACE_UP)]}
	b.seed_value = 3
	root.add_child(b)
	b.paused = true
	var s: BattleSim = b.sim
	s.step()
	s.step()
	b.soldiers.upload()
	b.soldiers.set_alpha(1.0)
	var cx: int = s.u_cx[1]
	var cy: int = s.u_cy[1]
	var now := s.tick - 1
	# (kind, x offset m, run m, height dm, age ticks): running, a ball bouncing, three at rest (two break, one sinks: the
	# split is by the point: three points a metre apart, one of each), a shatter at a wall's face 6 m up.
	var rows := [[BattleSim.FXK_STONE, -12, 12, 0, 4], [BattleSim.FXK_BALL, -6, 20, 0, 2],
		[BattleSim.FXK_STONE, 0, 6, 0, 10], [BattleSim.FXK_STONE, 1, 6, 0, 10], [BattleSim.FXK_STONE, 2, 6, 0, 10],
		[BattleSim.FXK_STRIKE, 12, 0, 60, 3]]
	for r in rows:
		var f: int = s._fx_add(cx + int(r[1]) * 1024, cy, 0, 4096, int(r[0]), int(r[2]) * 1024, int(r[3]))
		s.fx_t[f] = now - int(r[4])
	if b.dive_t >= 0.0:
		b.dive_finish()
	b._cam_to(b.overlay.to_px(cx, cy))
	b.camera.force_update_scroll()
	b.overlay.impact_stats = PackedInt32Array([0, 0, 0, 0])
	b.overlay.queue_redraw()
	_roll_b = b
	_roll_frames = 0
	_roll_phase = 1


func _roll_frame() -> void:
	_roll_frames += 1
	var st: PackedInt32Array = _roll_b.overlay.impact_stats
	if (st[0] <= 0 or st[1] <= 0 or st[2] <= 0 or st[3] <= 0) and _roll_frames < 6:
		_roll_b.overlay.queue_redraw()
		return
	_check(st[0] > 0 and st[1] > 0 and st[2] > 0 and st[3] > 0,
		"the stone rolls and breaks: the overlay drew stones running %d, breaking %d, sinking %d, shattering at a wall %d (frames %d)" % [
			st[0], st[1], st[2], st[3], _roll_frames])
	_roll_b.queue_free()
	_roll_b = null
	_roll_phase = 2


func _cover_cases() -> void:
	const Terrain := preload("res://sim/terrain.gd")
	const Probe := preload("res://tests/lof_probe.gd")
	var was := CData.pack
	CData.use_pack("west")
	var rk := []
	for x in range(150, 191, 2):
		rk.append([x, 163, 1, 13])
	for x in range(96, 125, 2):
		rk.append([x, 163, 1, 13])
	for x in range(30, 71, 2):
		rk.append([x, 163, 1, 25])
	var b := Battle.new()
	b.custom_scenario = {"width_m": 400, "height_m": 300, "ai_sides": [], "orders": [], "los": 1, "time_limit": 600,
		"terrain": {"kind": Terrain.K_FLAT, "rocks": rk},
		"units": [Scenarios.unit(0, UT.index_of("musketeers"), 40, 170, 160, Scenarios.FACE_DOWN, 10),
			Scenarios.unit(0, UT.index_of("musketeers"), 40, 50, 160, Scenarios.FACE_DOWN, 10),
			Scenarios.unit(0, UT.index_of("musketeers"), 40, 300, 160, Scenarios.FACE_DOWN, 10),
			Scenarios.unit(0, UT.index_of("lancers"), 30, 110, 160, Scenarios.FACE_DOWN, 10),
			Scenarios.unit(1, UT.index_of("musketeers"), 60, 170, 240, Scenarios.FACE_UP, 15),
			Scenarios.unit(1, UT.index_of("musketeers"), 30, 50, 250, Scenarios.FACE_UP, 10)]}
	b.seed_value = 3
	root.add_child(b)
	b.paused = true
	var s: BattleSim = b.sim
	var ov = b.overlay
	for t in 3:
		s.step()
	var low: Array = ov.chip_state(0)
	var tall: Array = ov.chip_state(1)
	var open: Array = ov.chip_state(2)
	var rider: Array = ov.chip_state(3)
	_check(int(low[1]) == 1 and int(tall[1]) == 2 and int(open[1]) == 0 and int(rider[1]) == 0,
		"cover chips: a musket line behind the yard wall light (%d), behind the tall wall heavy (%d), in the open none (%d), riders by the low wall none (%d)" % [low[1], tall[1], open[1], rider[1]])
	_check(absi(((int(low[2]) - 256 + 512) & 1023) - 512) < 64, "cover chips: the tick points at the enemy (bearing %d, down 256)" % int(low[2]))
	# (Third pass: rated against the units that shot at it in the last 3 s: the line behind the yard wall shot at.)
	s.queue_order(BattleSim.make_fire_order(s.tick, 4, 1))
	var shooters := PackedInt32Array()
	for t in 300:
		s.step()
		shooters = s.cover_shooters(0, ov.CHIP_SHOT_T)
		if not shooters.is_empty():
			break
	ov._chip.clear()
	var shot_at: Array = ov.chip_state(0)
	_check(not shooters.is_empty() and shooters.has(int(shot_at[4])),
		"cover chips: rated against a unit that shot at it (threat %d, shooters %s)" % [int(shot_at[4]), str(shooters)])
	var spike := PackedInt32Array()
	for k in 73:
		spike.append(100 if k == 10 or k == 11 else 20)
	spike[72] = spike[0]
	var opened: PackedInt32Array = ov._ring_open(spike)
	var wide := PackedInt32Array()
	for k in 73:
		wide.append(100 if k >= 10 and k < 30 else 20)
	var wopened: PackedInt32Array = ov._ring_open(wide)
	_check(opened[10] == 20 and opened[11] == 20 and wopened[15] == 100 and wopened[40] == 20,
		"range ring: a two-step spike down a street is pulled in (%d), a wide open sector kept (%d)" % [opened[10], wopened[15]])
	b._select(0)
	ov.queue_redraw()
	b.queue_free()
	# Hittable / blocked marks: the lof_probe's town case (a musket line 40 m off pikes behind a house: blocked) and the
	# same line with pikes in the open beside it (hittable).
	for pos in ["town", "beside"]:
		var hb := Battle.new()
		hb.custom_scenario = Probe.scenario("musket", pos, 40, "faw")
		hb.seed_value = 7
		root.add_child(hb)
		hb.paused = true
		hb.sim.step()
		hb._select(0)
		var hov = hb.overlay
		var hs: int = hov.hit_state(0, 1)
		var src: int = hov._hit_source()
		_check(src == 0 and hs == (0 if pos == "town" else 1), "hittable marks: the selected musket line marks pikes %s %s (%d)" % [
			"behind a house" if pos == "town" else "beside the house", "blocked" if pos == "town" else "hittable", hs])
		hov.queue_redraw()
		hb.queue_free()
	CData.use_pack(was)
	if not _oblique:
		# (Fourth pass: the top view's rubble reads as a heap; checked on the next frame, _process.)
		var bsc: Dictionary = Probe.breach_scenario("inside")
		var rs := BattleSim.new()
		rs.setup(bsc, 1)
		rs._breach(int(bsc["_breach"]), -1)
		_rub = _RubNode.new()
		_rub.sim = rs
		_rub.cells = preload("res://game/city_draw.gd").rubble_cells(rs)
		root.add_child(_rub)


func _ship_cases() -> void:
	var was := CData.pack
	CData.use_pack("west")
	var sb := Battle.new()
	var sc := Scenarios.shore_battle(1, 0, [0])
	var tf := CData.faction_index("tierra_firme")
	for e in sc["ships"]:
		e["f"] = tf
	sb.custom_scenario = sc
	sb.player_side = 1
	sb.seed_value = 8100
	root.add_child(sb)
	var tag := ""  # (_check marks the oblique run itself)
	var lay = sb.ships
	_check(lay != null and (lay.visible or _v3d) and sb.sim.shp_on == 1 and lay.colors.size() == 3 and lay.colors[0] == CData.faction_color(tf),
		tag + "ships: the ship layer holds the three hulls in their faction's colours")
	if _v3d:
		# (the 3D view hides the 2D layer and builds the hulls as solids: game/ship_layer.gd build_mesh3d)
		_check(not lay.visible and sb.view3d != null and sb.view3d.ship_mi.mesh != null and sb.view3d.ship_mi.mesh.get_surface_count() > 0,
			tag + "ships: the 3D view builds the hulls as solids")
	_check(lay != null and lay.get_index() < sb.soldiers.get_index(), tag + "ships: the hulls are drawn under the men")
	_check(lay != null and (lay.material != null) == _oblique, tag + "ships: placed by the board's lift in the oblique view only")
	var on_deck := true
	for s2 in sb.sim.sh_side.size():
		var u: int = sb.sim.sh_unit[s2]
		var base: int = sb.sim.u_slot_base[u]
		for k in sb.sim.u_alive[u]:
			var i: int = sb.sim.slot_soldier[base + k]
			var d := Vector2(sb.sim.pos_x[i] - sb.sim.sh_x[s2], sb.sim.pos_y[i] - sb.sim.sh_y[s2]).length() / 1024.0
			if d > float(sb.sim.sh_len[s2]) * 0.55:
				on_deck = false
	_check(on_deck, tag + "ships: each ship's crew stands on her deck (within her length)")
	sb.queue_free()
	CData.use_pack(was)
