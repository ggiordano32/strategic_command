extends SceneTree
## Touch scrolling in lists (needs a window): phone-sized UI (780x360 CSS at
## DPR 2, touch), synthetic ScreenTouch / ScreenDrag events through Godot's
## input pipeline (the engine emulates the mouse events buttons see).
##   godot --resolution 1560x720 --script res://tests/touch_scroll_test.gd
## For the recruitment list (the army card of an army at a city), the army unit list, the save list, the main menu
## test list and the unit book (list and page): (a) a drag that starts on a
## button or row scrolls and presses nothing; (b) a short tap presses exactly
## that button; (c) a fling keeps scrolling after release; (d) a long press
## on a recruit or army row opens the unit page, and a drag cancels it.
## Exits 0 on success, 1 on failure.

const UiScale := preload("res://game/ui_scale.gd")
const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const Saves := preload("res://game/campaign/saves.gd")
const CGrid := preload("res://campaign/cgrid.gd")

var failures := 0


func _initialize() -> void:
	Input.use_accumulated_input = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	UiScale._dpr_override = 2.0
	UiScale._touch_override = 1
	UiScale.apply(root)
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


func _win(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func _touch(p: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = _win(p)
	e.pressed = pressed
	Input.parse_input_event(e)


## Drag from a to b (viewport coords) over `steps` frames, then lift.
func _drag(a: Vector2, b: Vector2, steps: int = 8, lift: bool = true) -> void:
	_touch(a, true)
	await _frames(2)
	var prev := a
	for k in range(1, steps + 1):
		var p := a.lerp(b, float(k) / steps)
		var e := InputEventScreenDrag.new()
		e.index = 0
		e.position = _win(p)
		e.relative = _win(p) - _win(prev)
		Input.parse_input_event(e)
		prev = p
		await process_frame
	if lift:
		_touch(b, false)
		await _frames(2)


func _tap(p: Vector2) -> void:
	_touch(p, true)
	await _frames(2)
	_touch(p, false)
	await _frames(3)


func _centre(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


## Wait for flings to stop, then bring c into view in its scroll area.
func _settle(c: Control) -> void:
	for k in 200:
		var busy := false
		for n in root.find_children("*", "ScrollContainer", true, false):
			if n.has_method("is_flinging") and n.is_flinging():
				busy = true
		if not busy:
			break
		await process_frame
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(c)
			break
		p = p.get_parent()
	await _frames(3)


func _run() -> void:
	await _frames(5)
	UiScale.apply(root)
	await _frames(3)
	print("window ", root.size, " logical size ", root.get_visible_rect().size)
	await _campaign_lists()
	await _menu_lists()
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)


# ------------------------------------------------------------ campaign ---

func _campaign_lists() -> void:
	var rome := CData.faction_index("rome")
	var st := CState.new_campaign("Touch", 5, [rome])
	st["factions"][rome]["treasury"] = 100000
	var cs := CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "touch_test")
	root.add_child(cs)
	await _frames(5)
	cs.close_dialog()
	# The recruit list is in the card of an army at one of our cities
	# (format 6): Rome's first army inside the walls of Roma.
	var a0: Dictionary = CState.armies_of(cs.st, rome)[0]
	CState.place(a0, CGrid.site(CData.region_index("latium")))
	cs._replan()
	cs.select_army(int(a0["id"]))
	await _frames(4)
	var sc = cs.side_scroll
	_check(sc.get_v_scroll_bar().max_value > sc.get_v_scroll_bar().page, "the army card with its recruit list overflows the phone screen (scrollable)")
	# (a) drag starting on a recruit + button.
	var plus: Button = cs.side_box.find_child("recruit_heavy", true, false)
	var y0: int = sc.scroll_vertical
	var start := _centre(plus)
	await _drag(start, start + Vector2(0, -120))
	_check(sc.scroll_vertical > y0 + 60, "recruit list: a drag from a button scrolls (%d -> %d)" % [y0, sc.scroll_vertical])
	_check(cs.orders.is_empty(), "recruit list: the drag pressed nothing")
	_check(not plus.is_pressed() and plus.get_draw_mode() != BaseButton.DRAW_PRESSED, "recruit list: the button's pressed look is cleared")
	# (c) fling: a fast drag keeps going after release.
	sc.scroll_vertical = 0
	await _frames(2)
	plus = cs.side_box.find_child("recruit_heavy", true, false)
	start = _centre(plus)
	await _drag(start, start + Vector2(0, -90), 3)
	var after_release: int = sc.scroll_vertical
	await _frames(8)
	_check(sc.scroll_vertical > after_release and sc.is_flinging() or sc.scroll_vertical > after_release,
		"recruit list: the fling continues after release (%d -> %d)" % [after_release, sc.scroll_vertical])
	await _frames(40)
	# (b) a tap presses exactly that button.
	sc.scroll_vertical = 0
	await _frames(3)
	plus = cs.side_box.find_child("recruit_heavy", true, false)
	await _settle(plus)
	await _tap(_centre(plus))
	_check(cs.orders.size() == 1 and str(cs.orders[0]["unit"]) == "heavy", "recruit list: a tap recruits exactly one heavy (%s)" % str(cs.orders))
	# (d) long press on a recruit row opens the unit page; a drag cancels it.
	var row: Control = cs.side_box.find_child("recruit_row_spear", true, false)
	await _settle(row)
	_touch(_centre(row), true)
	await create_timer(0.7).timeout
	_touch(_centre(row), false)
	await _frames(3)
	_check(cs.dialog.visible and cs.dialog_title.text == "Spearmen", "recruit list: a long press opens the unit page (%s)" % cs.dialog_title.text)
	cs.close_dialog()
	await _frames(2)
	row = cs.side_box.find_child("recruit_row_spear", true, false)
	await _settle(row)
	start = _centre(row)
	await _drag(start, start + Vector2(0, -60), 4, false)
	await create_timer(0.7).timeout
	_touch(start + Vector2(0, -60), false)
	await _frames(3)
	_check(not cs.dialog.visible, "recruit list: a drag cancels the long press")
	_check(cs.orders.size() == 1, "recruit list: still one order")
	# Army unit list (Carthage's first army has 8 units).
	cs.close_side()
	var a: Dictionary = CState.armies_of(cs.ps, rome)[0]
	for k in 5:
		(a["units"] as Array).append({"t": "spear", "n": 100})
	cs.select_army(int(a["id"]))
	await _frames(4)
	sc.scroll_vertical = 0
	await _frames(2)
	var urow: Control = cs.side_box.find_child("unit_2", true, false)
	await _settle(urow)
	start = _centre(urow)
	await _drag(start, start + Vector2(0, -100))
	_check(sc.scroll_vertical > 40, "army list: a drag from a unit row scrolls (%d)" % sc.scroll_vertical)
	urow = cs.side_box.find_child("unit_2", true, false)
	_check(not urow.selected, "army list: the drag selected nothing")
	await _frames(30)
	urow = cs.side_box.find_child("unit_3", true, false)
	await _settle(urow)
	await _tap(_centre(urow))
	urow = cs.side_box.find_child("unit_3", true, false)
	_check(urow.selected, "army list: a tap selects that unit")
	# Panel drags never pan the map.
	var off: Vector2 = cs.offset
	urow = cs.side_box.find_child("unit_1", true, false)
	await _settle(urow)
	await _drag(_centre(urow), _centre(urow) + Vector2(-150, -40))
	_check(cs.offset == off, "a drag in the panel does not pan the map")
	cs.queue_free()
	await _frames(3)


# ---------------------------------------------------------------- menus ---

func _menu_lists() -> void:
	# Fourteen saves for the Continue list.
	for k in 14:
		var st := CState.new_campaign("Save%02d" % k, 100 + k, [k % 8])
		Saves.save("touchtest_%02d" % k, {"state": st, "session": {}})
	var m = (load("res://game/main.gd") as GDScript).new()
	root.add_child(m)
	await _frames(4)
	m.show_page("continue")
	await _frames(4)
	var sc = m._continue_box.get_parent()
	var btns: Array = []
	for b in m._continue_box.find_children("*", "Button", true, false):
		if (b as Button).text != "Delete":
			btns.append(b)
	var b0: Button = btns[1]
	var start := _centre(b0)
	await _drag(start, start + Vector2(0, -100))
	_check(sc.scroll_vertical > 40, "save list: a drag from a save button scrolls (%d)" % sc.scroll_vertical)
	_check(m.campaign == null, "save list: the drag opened nothing")
	await _frames(30)
	sc.scroll_vertical = 0
	await _frames(3)
	await _settle(btns[0])
	await _tap(_centre(btns[0]))
	await _frames(3)
	_check(m.campaign != null, "save list: a tap opens that campaign")
	if m.campaign != null:
		m._close_campaign()
		await _frames(3)
	for k in 14:
		Saves.delete("touchtest_%02d" % k)
	# Sandbox page with the tests open.
	m.show_page("sandbox")
	m._toggle_tests()
	await _frames(4)
	var ssc = m._pages["sandbox"]
	var test_btn: Button = null
	for b in m._tests_box.get_children():
		test_btn = b
		break
	var scrollable: bool = ssc.get_v_scroll_bar().max_value > ssc.get_v_scroll_bar().page
	await _settle(test_btn)
	start = _centre(test_btn)
	await _drag(start, start + Vector2(0, -80))
	if scrollable:
		_check(ssc.scroll_vertical > 20, "test list: a drag from a test button scrolls (%d)" % ssc.scroll_vertical)
	else:
		print("  (test list fits the screen: nothing to scroll)")
	_check(m._battle == null, "test list: the drag started no battle")
	await _frames(30)
	ssc.scroll_vertical = 0
	await _frames(2)
	# Unit book: list and page.
	m.book.open(0)
	await _frames(4)
	var lsc = m.book._list[0].get_parent().get_parent()
	await _settle(m.book._list[2])
	start = _centre(m.book._list[2])
	await _drag(start, start + Vector2(0, -150))
	_check(lsc.scroll_vertical > 60, "book list: a drag from a unit button scrolls (%d)" % lsc.scroll_vertical)
	_check(m.book.current == 0, "book list: the drag changed no page")
	await _frames(30)
	var target: Button = null
	for k in m.book._list.size():
		var r: Rect2 = m.book._list[k].get_global_rect()
		if r.position.y > 60 and r.end.y < root.get_visible_rect().size.y - 20:
			target = m.book._list[k]
			break
	var want: int = m.book._list.find(target)
	await _settle(target)
	await _tap(_centre(target))
	_check(m.book.current == want, "book list: a tap opens that page (%d, want %d)" % [m.book.current, want])
	var page = m.book.entry
	var py0: int = page.scroll_vertical
	start = _centre(page)
	await _drag(start, start + Vector2(0, -120))
	_check(page.scroll_vertical > py0 + 40, "book page: dragging the page scrolls it (%d -> %d)" % [py0, page.scroll_vertical])
	m.book.close()
	await _frames(2)
	m.queue_free()
	await _frames(2)
