extends SceneTree
## Multi-select on the campaign map (view only; ui.md "Multi-select on the campaign map"). Needs a window:
##   godot --script res://tests/multiselect_test.gd [-- --shots=DIR]
## The same cases run inside tests/campaign_input_test.gd (step _ms_run); this file runs them alone, fast, and with
## --shots=DIR writes the set shots (844 x 390 and 1280 x 720).
## Shift-add, the touch add mode (the capsule), the drag box, the double tap, a group move (one move per army), Embark all
## (room for two of three reports the third; two fleets fill in turn), Disembark all, Merge all within the cap, Hold /
## Stance for all, the bar's summary line and member cards, the layout at the two phone sizes.

const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const MapOverlay := preload("res://game/campaign/map_overlay.gd")

var cs: CampaignScreen
var frame := 0
var started := false
var failures := 0
var shots_dir := ""


func _initialize() -> void:
	Input.use_accumulated_input = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.substr(8)
			DirAccess.make_dir_recursive_absolute(shots_dir)


func _process(_d: float) -> bool:
	frame += 1
	if frame >= 8 and not started:
		started = true
		_main()
	return false


func _main() -> void:
	await _ms_run()
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)


func _check(c: bool, what: String) -> void:
	if c:
		print("PASS ", what)
	else:
		printerr("FAIL ", what)
		failures += 1


func _key_off() -> void:
	if not cs.is_node_ready():
		cs.ready.connect(_key_off, CONNECT_ONE_SHOT)
		return
	cs.map_key.persist = false
	cs.map_key.set_expanded(false)


func _win(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


# ---------------------------------------------------------------- the cases ---

var _ms_a := -1
var _ms_b := -1
var _ms_c := -1
var _ms_d := -1
var _ms_f1 := -1
var _ms_f2 := -1
var _ms_r := -1
var _ms_mk := -1


func _ms_pos(id: int) -> Vector2:
	return cs.overlay.army_positions()[id]


func _ms_fpos(id: int) -> Vector2:
	return cs.overlay.fleet_positions()[id]


func _ms_cellpt(c: int) -> Vector2:
	return cs.overlay.to_screen(MapOverlay.cell_point(c))


func _ms_orders(kind: String) -> Array:
	var out: Array = []
	for o in cs.orders:
		if str(o["t"]) == kind:
			out.append(o)
	return out


func _ms_reset() -> void:
	cs.orders = []
	cs._undo = []
	cs.close_side()
	if cs._toast != null:
		cs._toast.queue_free()
		cs._toast = null
	cs._last_tap = {}
	cs._replan()


func _ms_ids(a: Array) -> String:
	var b := a.duplicate()
	b.sort()
	return str(b)


func _ms_empty_point(near: Vector2) -> Vector2:
	for k in 60:
		var p := near + Vector2((k % 6) * -14.0, (k / 6) * -14.0)
		if cs.overlay.army_at(p) < 0 and cs.overlay.settlement_at(p) < 0 and cs.overlay.fleet_at(p) < 0:
			return p
	return near


## A touch / emulated mouse press, a held wait (seconds, real time), drags and a release, handed to the screen's own touch
## handlers (`_on_touch`, `_on_drag`: what `_unhandled_input` calls; the engine's delivery is not the thing under test, and
## the first real events after other steps can be swallowed by a control that kept the mouse focus).
func _ms_gesture(from: Vector2, to: Vector2, emulated: bool, hold_s: float) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = from
	e.pressed = true
	if emulated:
		e.device = InputEvent.DEVICE_ID_EMULATION
	cs._on_touch(e)
	if hold_s > 0.0:
		var t0 := Time.get_ticks_msec()   # (real time, frame by frame: an earlier step may have changed the timers' scale)
		while Time.get_ticks_msec() - t0 < int(hold_s * 1000.0):
			await process_frame
		await process_frame
	if from != to:
		for k in range(1, 9):
			var d := InputEventScreenDrag.new()
			d.index = 0
			d.position = from.lerp(to, k / 8.0)
			d.relative = (to - from) / 8.0
			if emulated:
				d.device = InputEvent.DEVICE_ID_EMULATION
			cs._on_drag(d)
			await process_frame
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.position = to
	u.pressed = false
	if emulated:
		u.device = InputEvent.DEVICE_ID_EMULATION
	cs._on_touch(u)
	await process_frame


func _ms_clone(src: Dictionary, c: int) -> int:
	var na := src.duplicate(true)
	var f := int(src["f"])
	na["id"] = CRules.new_army_id(cs.st, f)
	cs.st["factions"][f]["next_army"] = int(cs.st["factions"][f]["next_army"]) + 1
	na["moved"] = 0
	na["busy"] = 0
	na["dest_x"] = -1
	na["dest_y"] = -1
	na["tgt"] = -1
	na["dest_army"] = -1
	CState.place(na, c)
	CRules._insert_army(cs.st, na)
	return int(na["id"])


func _ms_fleet(id: int, c: int, cap_units: int) -> Dictionary:
	var ships: Array = []
	var fl := {"id": id, "f": _ms_mk, "x": CGrid.cx(c), "y": CGrid.cy(c), "ships": ships, "carry": [], "moved": 0}
	while CFleet.capacity(fl) < cap_units and ships.size() < 12:
		ships.append({"t": "sloop", "h": 100, "c": 100})
	return fl


func _ms_setup() -> bool:
	for n in root.get_children():
		if n is CampaignScreen:
			n.queue_free()   # (an earlier step's screen would take the real touches too)
	await process_frame
	await process_frame
	CData.use_pack("west")
	_ms_mk = CData.faction_index("miskito")
	var st := CState.new_campaign("Msel", 3, [_ms_mk], {}, [], "west")
	var mine: Array = CState.armies_of(st, _ms_mk)
	var src: Dictionary = (mine[0] as Dictionary).duplicate(true)
	# a port: the Miskito's own region with a harbour, else any
	var port := -1
	for r in CData.region_count():
		if CFleet.harbour(r) >= 0 and CState.owner(st, r) == _ms_mk:
			port = r
			break
	if port < 0:
		for r in CData.region_count():
			if CFleet.harbour(r) >= 0:
				port = r
				break
	_ms_r = port
	var keep: Array = []
	for a in st["armies"]:
		if int(a["f"]) != _ms_mk:
			keep.append(a)
	st["armies"] = keep
	var units: Array = src["units"]
	while units.size() > 3:
		units.pop_back()
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "multiselect_test")
	root.add_child(cs)
	_key_off()
	await process_frame
	await process_frame
	if cs.dialog.visible:
		cs.close_dialog()
	cs.cover.visible = false
	var site := CGrid.site(port)
	_ms_a = _ms_clone(src, site)
	_ms_b = _ms_clone(src, site)
	_ms_c = _ms_clone(src, site)
	# a fourth, in another region
	var far := -1
	for r in CData.region_count():
		if r != port and CGrid.cheb(CGrid.site(r), site) >= 6 and CGrid.cheb(CGrid.site(r), site) <= 14 and CFleet.harbour(r) < 0:
			far = CGrid.site(r)
			break
	_ms_d = _ms_clone(src, far if far >= 0 else CGrid.at(CGrid.cx(site) + 8, CGrid.cy(site)))
	cs.st["fleets"] = [_ms_fleet(7001, CFleet.harbour(port), 6), _ms_fleet(7002, CFleet.harbour(port), 3)]
	cs.st["next_fleet"] = 7003
	_ms_f1 = 7001
	_ms_f2 = 7002
	cs._replan()
	cs.focus_region(port, 1.8)
	await process_frame
	await process_frame
	cs._refresh_map()
	await process_frame
	await process_frame
	return CFleet.capacity(CFleet.fleet(cs.ps, _ms_f1)) >= 6 and CFleet.capacity(CFleet.fleet(cs.ps, _ms_f1)) < 9


func _ms_run() -> void:
	var ok := await _ms_setup()
	_check(ok, "multiselect: the scene has a port with a fleet that holds two of three armies (cap %d)" % CFleet.capacity(CFleet.fleet(cs.ps, _ms_f1)))
	var mine := CState.armies_of(cs.ps, cs.f)
	_check(mine.size() == 4 and cs._g(), "multiselect: four armies of ours on the grid")
	# 1. Shift-click adds and removes (desktop)
	cs.select_army(_ms_a)
	await process_frame
	cs._left_click(_ms_pos(_ms_b), true)
	_check(_ms_ids(cs.set_armies()) == _ms_ids([_ms_a, _ms_b]) and cs.sel_army == _ms_a and cs.set_size() == 2, "shift-click adds an army: %s" % str(cs.set_armies()))
	cs._left_click(_ms_pos(_ms_c), true)
	_check(cs.set_size() == 3, "a third")
	cs._left_click(_ms_pos(_ms_b), true)
	_check(_ms_ids(cs.set_armies()) == _ms_ids([_ms_a, _ms_c]), "shift-click on a member takes it out")
	cs._left_click(_ms_pos(_ms_a), true)
	_check(cs.sel_army == _ms_c and cs.set_size() == 1, "taking the focus out passes it on (sel_army %d)" % cs.sel_army)
	cs._left_click(_ms_pos(_ms_a), true)
	cs._left_click(_ms_pos(_ms_b), true)
	for k in 3:
		await process_frame
	_check(cs.set_size() == 3 and cs.overlay.extra_armies.size() == 2 and cs.cmd_bar.find_child("member_army_%d" % _ms_a, true, false) != null,
		"every selected army is in the overlay's set and on the bar")
	cs._left_click(_ms_pos(_ms_b), false)
	_check(cs.set_size() == 1 and cs.sel_army == _ms_b, "a plain click selects just that army")
	# 2. touch add mode
	_ms_reset()
	cs.select_army(_ms_a)
	cs.long_press_at(_ms_pos(_ms_a))
	await process_frame
	_check(cs.add_mode and cs._sel_capsule.visible, "a long press on a marker enters add mode and shows the capsule")
	cs.tap(_ms_pos(_ms_b))
	cs.tap(_ms_pos(_ms_c))
	await process_frame
	_check(cs.set_size() == 3 and cs.add_mode, "taps add in add mode")
	var cap_text: String = cs._capsule_label.text
	_check(cap_text == "Selecting: 3 armies.", "the capsule reads '%s'" % cap_text)
	cs.tap(_ms_fpos(_ms_f1))
	await process_frame
	_check(cs.set_fleets() == [_ms_f1] and cs._capsule_label.text == "Selecting: 3 armies, 1 fleet.", "a fleet joins the set: '%s'" % cs._capsule_label.text)
	cs.tap(_ms_pos(_ms_b))
	_check(cs.set_armies().size() == 2, "a tap on a member removes it")
	var done: Button = cs._sel_capsule.find_child("select_done", true, false)
	done.pressed.emit()
	await process_frame
	_check(not cs.add_mode and not cs._sel_capsule.visible and cs.set_size() == 3, "Done ends add mode and keeps the set")
	cs.enter_add_mode()
	cs.tap(_ms_empty_point(_ms_pos(_ms_a) + Vector2(-60, -60)))
	_check(not cs.add_mode, "a tap on empty map ends add mode")
	# a held touch
	_ms_reset()
	cs.select_army(_ms_a)
	await process_frame
	await _ms_gesture(_ms_pos(_ms_b), _ms_pos(_ms_b), false, 0.7)
	_check(cs.add_mode and cs.in_set("a", _ms_b) and cs.set_size() == 2, "a held touch on a marker adds it and enters add mode")
	cs.end_add_mode()
	# 3. the box
	_ms_reset()
	var lo := _ms_pos(_ms_a)
	var hi := _ms_pos(_ms_a)
	for p in [_ms_pos(_ms_b), _ms_pos(_ms_c), _ms_fpos(_ms_f1), _ms_fpos(_ms_f2)]:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var n: int = cs.select_in_rect(Rect2(lo - Vector2(26, 26), hi - lo + Vector2(52, 52)))
	_check(n >= 4 and _ms_ids(cs.set_armies()) == _ms_ids([_ms_a, _ms_b, _ms_c]) and cs.set_fleets().size() == 2, "a box takes every own army and fleet inside (%d)" % n)
	_check(not cs.set_armies().has(_ms_d), "... and not the army outside")
	_ms_reset()
	var from := _ms_empty_point(lo - Vector2(40, 40))
	var off0: Vector2 = cs.offset
	await _ms_gesture(from, hi + Vector2(40, 40), true, 0.0)
	_check(cs.set_size() == 0 and cs.offset != off0, "a plain left drag from empty ground pans and selects nothing")
	cs.offset = off0   # (back where the markers were)
	cs.close_side()
	await process_frame
	cs.test_shift = true
	await _ms_gesture(from, hi + Vector2(40, 40), true, 0.0)
	cs.test_shift = false
	_check(cs.set_size() >= 4 and cs.set_armies().size() == 3 and not cs._box_panel.visible, "a Shift + left drag from empty ground draws the box and selects (%d)" % cs.set_size())
	_ms_reset()
	await _ms_gesture(from, hi + Vector2(40, 40), false, 0.7)
	_check(cs.set_armies().size() == 3, "a touch: long press on empty ground, then drag, is the box (%d)" % cs.set_size())
	# 4. double tap
	_ms_reset()
	cs.tap(_ms_pos(_ms_a))
	cs.tap(_ms_pos(_ms_a))
	await process_frame
	_check(_ms_ids(cs.set_armies()) == _ms_ids([_ms_a, _ms_b, _ms_c]) and cs.sel_army == _ms_a, "a double tap on an army selects every army of ours in its region (not the far one)")
	_ms_reset()
	cs.tap(_ms_fpos(_ms_f1))
	cs.tap(_ms_fpos(_ms_f1))
	await process_frame
	_check(_ms_ids(cs.set_fleets()) == _ms_ids([_ms_f1, _ms_f2]), "a double tap on a fleet selects every fleet of ours at its port")
	_ms_reset()
	cs.tap(_ms_pos(_ms_d))
	cs.tap(_ms_pos(_ms_d))
	await process_frame
	_check(cs.set_size() <= 1, "a double tap on a lone army is the ordinary tap (selects, then deselects)")
	# 5. group move: one move order per army
	_ms_reset()
	cs.select_set([_ms_a, _ms_b, _ms_c], [])
	await process_frame
	var site := CGrid.site(_ms_r)
	var dest := -1
	for k in 8:
		var c := CGrid.at(CGrid.cx(site) + CGrid.DX[k] * 2, CGrid.cy(site) + CGrid.DY[k] * 2)
		if c >= 0 and CGrid.passable(c) and CGrid.site_region(c) < 0:
			dest = c
			break
	_check(dest >= 0, "a land cell two steps out")
	cs.tap(_ms_cellpt(dest))
	await process_frame
	var mv := _ms_orders("move")
	var ids: Array = []
	for o in mv:
		ids.append(int(o["army"]))
	_check(mv.size() == 3 and _ms_ids(ids) == _ms_ids([_ms_a, _ms_b, _ms_c]) and int(mv[0]["x"]) == CGrid.cx(dest) and int(mv[2]["y"]) == CGrid.cy(dest),
		"a tap with three armies selected emits one move each to the same cell (%d orders)" % mv.size())
	_check("3 armies ordered" in cs._toast_text() and "this turn" in cs._toast_text() or "next turn" in cs._toast_text() or "turns" in cs._toast_text(),
		"the toast says who arrives when: '%s'" % cs._toast_text())
	_check(cs.set_size() == 3, "the set stays selected after the order")
	cs.tap(_ms_cellpt(dest))
	await process_frame
	_check(_ms_orders("move").is_empty(), "the same spot again takes all three marches back")
	cs.tap(_ms_cellpt(dest))
	cs.undo()
	_check(_ms_orders("move").size() == 2, "Undo takes back one order at a time (the group's last one first)")
	# far: an army that cannot reach this turn still marches
	_ms_reset()
	cs.select_set([_ms_a, _ms_b], [])
	var farc := CGrid.at(CGrid.cx(site) + 9, CGrid.cy(site))
	var fc := -1
	for dx in range(7, 12):
		for dy in range(-4, 5):
			var c2 := CGrid.at(CGrid.cx(site) + dx, CGrid.cy(site) + dy)
			if c2 >= 0 and CGrid.passable(c2) and CGrid.site_region(c2) < 0 and fc < 0:
				var pr := CRules.plan_path(cs.ps, CState.army(cs.ps, _ms_a), c2, -1, CData.MODE_SIEGE)
				if not pr.has("why") and (pr["t"] as Array).size() > 0 and int(pr["t"][-1]) >= 1:
					fc = c2
	farc = fc
	if farc >= 0:
		cs.tap(_ms_cellpt(farc))
		await process_frame
		_check(_ms_orders("move").size() == 2 and "turns" in cs._toast_text() or "next turn" in cs._toast_text(),
			"a march past this turn's reach is still ordered, the toast says when: '%s'" % cs._toast_text())
	# Hold and Stance for all
	cs.hold_group()
	_check(_ms_orders("move").is_empty(), "Hold takes every planned march back")
	var s0 := CState.stance(CState.army(cs.ps, _ms_a))
	cs.stance_group(CData.ST_RAID if s0 != CData.ST_RAID else 0)
	await process_frame
	_check(_ms_orders("stance").size() == 2 and cs.set_size() == 2, "Stance for all: one stance order each, the set kept")
	# 6. Embark all: room for two of three
	_ms_reset()
	cs.select_set([_ms_a, _ms_b, _ms_c], [_ms_f1])
	await process_frame
	cs.tap(_ms_fpos(_ms_f1))
	await process_frame
	var emb := _ms_orders("embark")
	_check(emb.size() == 2 and int(emb[0]["army"]) == _ms_a and int(emb[1]["army"]) == _ms_b, "Embark all: the first two armies board in selection order (%d orders)" % emb.size())
	var tt: String = cs._toast_text()
	_check("2 armies of 3 boarded" in tt and "Did not fit" in tt and "not enough room aboard" in tt, "the toast names who did not fit and why: '%s'" % tt)
	_check(CFleet.carried_units(CFleet.fleet(cs.ps, _ms_f1)) == 6 and cs.set_armies() == [_ms_c] and cs.set_fleets() == [_ms_f1], "the boarded armies leave the set, the third and the fleet stay")
	# two fleets fill in turn
	_ms_reset()
	cs.select_set([_ms_a, _ms_b, _ms_c], [_ms_f1, _ms_f2])
	await process_frame
	cs.board_set()
	await process_frame
	var emb2 := _ms_orders("embark")
	var in1 := 0
	var in2 := 0
	for o in emb2:
		if int(o["fleet"]) == _ms_f1:
			in1 += 1
		else:
			in2 += 1
	_check(in1 == 2 and in2 == 1, "the Board button fills the first fleet then the next (%d, %d)" % [in1, in2])
	# 7. Disembark all: the loaded fleets to a shore cell
	var lc := -1
	for k in 8:
		var c3 := CGrid.at(CGrid.cx(site) + CGrid.DX[k], CGrid.cy(site) + CGrid.DY[k])
		if c3 >= 0 and CGrid.passable(c3):
			lc = c3
			break
	cs.select_set([], [_ms_f1, _ms_f2])
	await process_frame
	cs.tap(_ms_cellpt(site) if lc < 0 else _ms_cellpt(site))
	await process_frame
	var fm := _ms_orders("fmove")
	var land_ok := 0
	for o in fm:
		if CGrid.at(int(o["x"]), int(o["y"])) == site:
			land_ok += 1
	_check(fm.size() == 2 and land_ok == 2, "Disembark all: a tap on the shore orders every loaded fleet to land (%d fmove orders)" % fm.size())
	_check("land" in cs._toast_text() and "9 units" in cs._toast_text(), "the toast says the landing: '%s'" % cs._toast_text())
	# a sea cell: fleets sail
	_ms_reset()
	cs.select_set([], [_ms_f1, _ms_f2])
	var sc := -1
	var hc := CFleet.harbour(_ms_r)
	for dx in range(2, 5):
		for dy in range(-3, 4):
			var c4 := CGrid.at(CGrid.cx(hc) + dx, CGrid.cy(hc) + dy)
			if c4 >= 0 and CFleet.is_sea(c4) and sc < 0 and not CFleet.plan(cs.ps, cs.f, _ms_f1, c4).has("why"):
				sc = c4
	if sc >= 0:
		cs.tap(_ms_cellpt(sc))
		await process_frame
		_check(_ms_orders("fmove").size() == 2, "a tap on the sea sends both fleets (%d)" % _ms_orders("fmove").size())
	# 8. Merge all, within the cap
	_ms_reset()
	cs.select_set([_ms_a, _ms_b], [])
	await process_frame
	cs.tap(_ms_pos(_ms_c))
	await process_frame
	_check(cs.merge_tap == _ms_c and "Merge 2 armies" in cs._toast_text(), "the first tap previews the group merge: '%s'" % cs._toast_text())
	cs.tap(_ms_pos(_ms_c))
	await process_frame
	var mg := _ms_orders("merge")
	_check(mg.size() == 2 and int(mg[0]["into"]) == _ms_c, "the second tap merges both into the tapped army (%d orders)" % mg.size())
	_ms_reset()
	var cu: Array = CState.army(cs.st, _ms_c)["units"]
	var base_u: Dictionary = (cu[0] as Dictionary).duplicate(true)
	var cu0 := cu.size()
	while cu.size() < 8:
		cu.append(base_u.duplicate(true))
	cs._replan()
	cs.select_set([_ms_a, _ms_b], [])
	cs.merge_group(cs.set_armies(), _ms_c)
	await process_frame
	var mg2 := _ms_orders("merge")
	_check(mg2.size() == 1 and "Not merged" in cs._toast_text() and "more than 12" in cs._toast_text(), "Merge all stops at the cap and reports the rest: '%s'" % cs._toast_text())
	while cu.size() > cu0:
		cu.pop_back()
	cs._replan()
	# 9. the bar
	_ms_reset()
	cs.select_set([_ms_a, _ms_b, _ms_c], [_ms_f1])
	for k in 4:
		await process_frame
	var sm: Label = cs.cmd_bar.find_child("set_summary", true, false)
	var want_men := 0
	for id in [_ms_a, _ms_b, _ms_c]:
		want_men += CState.men(CState.army(cs.ps, id))
	_check(sm != null and sm.text.begins_with("3 armies, 9 units, ") and "; 1 fleet, %d ships, room for 6 units" % CFleet.fleet(cs.ps, _ms_f1)["ships"].size() in sm.text, "the bar's summary line: '%s'" % (sm.text if sm != null else "none"))
	_check(sm != null and (str(want_men) in sm.text.replace(",", "")), "... with the men")
	_check(cs.cmd_bar.find_children("member_*", "Control", true, false).size() == 4 and cs.cmd_bar.find_child("unit_card_0", true, false) == null, "one leader card per member, no unit strip for a set")
	var card: Control = cs.cmd_bar.find_child("member_army_%d" % _ms_b, true, false)
	card.pressed.emit()
	for k in 3:
		await process_frame
	_check(cs.sel_army == _ms_b and cs.set_size() == 4 and cs.cmd_bar.find_child("unit_card_0", true, false) != null, "a tapped card makes that army the focus, shows its units, keeps the set")
	var back: Button = cs.cmd_bar.find_child("act_set_back", true, false)
	_check(back != null, "the focus bar has a Set button")
	if back != null:
		back.pressed.emit()
		for k in 3:
			await process_frame
		_check(cs.cmd_bar.find_child("set_summary", true, false) != null, "Set returns to the set bar")
	# 10. layout at the two sizes (and the shots)
	var win := root.content_scale_size
	for sz in [Vector2i(844, 390), Vector2i(1280, 720)]:
		root.content_scale_size = sz
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		if DisplayServer.get_name() == "headless":
			root.size = sz
		cs.select_set([_ms_a, _ms_b, _ms_d], [_ms_f1])
		cs.enter_add_mode()
		cs.zoom = 0.9
		cs.focus_region(_ms_r)
		for k in 6:
			await process_frame
		var tag := "set bar %dx%d: " % [sz.x, sz.y]
		var bar = cs.cmd_bar
		var vr := Rect2(Vector2.ZERO, Vector2(sz))
		var br: Rect2 = bar.get_global_rect()
		_check(bar.shown and vr.encloses(br.grow(-1.0)), tag + "the bar is on screen (%s)" % str(br))
		_check(bar.height() >= bar.get_combined_minimum_size().y - 0.5, tag + "the reported height is the real one")
		var capr: Rect2 = cs._sel_capsule.get_global_rect()
		_check(cs._sel_capsule.visible and vr.encloses(capr) and not capr.intersects(br), tag + "the capsule is on screen and clear of the bar (%s)" % str(capr))
		var cards := bar.find_children("member_*", "Control", true, false)
		var all_in := true
		for c in cards:
			if (c as Control).get_global_rect().size.x < 40.0:
				all_in = false
		_check(cards.size() == 4 and all_in, tag + "three army cards and a fleet card, none squeezed")
		_check(not cs.bottom_bar.get_global_rect().intersects(br), tag + "the End turn row clears the bar")
		if shots_dir != "" and DisplayServer.get_name() != "headless":
			await create_timer(0.4).timeout
			var img := root.get_texture().get_image()
			img.save_png("%s/set_%dx%d.png" % [shots_dir, sz.x, sz.y])
		cs.end_add_mode()
	root.content_scale_size = win
	CData.use_pack("rome")
	cs.queue_free()
