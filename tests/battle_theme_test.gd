extends SceneTree
## UI theme pass 2: the battle HUD, the battle modals and Menu overlay, the sea screen's bars (needs a window):
##   godot --resolution 1280x720 --script res://tests/battle_theme_test.gd [-- --shots=DIR]
## Battle HUD: the gold rule and (desktop) the emblem + name in the title face, the nav plates on the command bar,
## All / Inf / Missile / Cav / None as one capsule (momentary: nothing stays lit; group_buttons / deselect_button
## are its segments), a boxed tip on every button, the banner in the title face over a trim plate, the end card and the
## Leave confirm in the dialog frame. The Menu (custom battles): opens paused, Resume / Esc restore the pause, Options
## shows the settings, Controls closes it, Leave asks and then exits. Sea: the speed capsule, the sail / shot capsules,
## Kit tips on the order buttons, the Douse button styled like the others. Phone width (--phone): the title block
## is hidden. --shots=DIR saves screenshots. Exits 0 / 1.

const Battle := preload("res://game/battle.gd")
const Hud := preload("res://game/hud.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const SeaBattle := preload("res://game/sea_battle.gd")
const SeaSim := preload("res://sim/sea_sim.gd")
const Checks := preload("res://tests/sea_checks.gd")
const UiScale := preload("res://game/ui_scale.gd")

var failures := 0
var _shots := ""
var _phone := false
var _exits := 0
var b


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	if _shots == "":
		return
	await _frames(4)
	root.get_texture().get_image().save_png("%s/%s%s.png" % [_shots, name, "_phone" if _phone else ""])


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.get_slice("=", 1)
		elif a == "--phone":
			_phone = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Kit.anim_override = 0
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	UiScale._dpr_override = 3.0 if _phone else 1.0   # (--phone: a phone's pixel density and touch, 844x390 window)
	UiScale._touch_override = 1 if _phone else 0
	_run.call_deferred()


func _tap(c: Control) -> void:
	var p := root.get_final_transform() * c.get_global_rect().get_center()
	b._last_tap_time = -10.0
	for pressed in [true, false]:
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.position = p
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame


func _run() -> void:
	if _phone:
		DisplayServer.window_set_size(Vector2i(844, 390))
		await _frames(6)
		UiScale.apply(root)
		await _frames(4)
	await _battle_hud()
	await _menu()
	await _modals()
	await _sea()
	UiScale._dpr_override = -1.0
	UiScale._touch_override = -1
	print("RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)


func _new_battle(campaign: bool) -> void:
	if is_instance_valid(b):
		b.free()
	b = Battle.new()
	b.scenario_id = "battle_2000"
	b.seed_value = 5
	b.campaign_mode = campaign
	b.speed_q = 4
	b.exit_requested.connect(func(): _exits += 1)
	root.add_child(b)
	await _frames(6)


func _battle_hud() -> void:
	await _new_battle(false)
	var h = b.hud
	_check(h.bar_rule != null and h.bar_rule.is_inside_tree(), "the top bar has a gold rule")
	if _phone:
		_check(h.title_block == null or not h.title_block.visible, "phone width: no emblem / title block (the row is as before)")
	else:
		_check(h.title_block != null and h.title_block.visible, "desktop: the emblem and the battle's name show")
		var t: Label = h.title_block.get_node("bar_title")
		_check(t.get_theme_font_size("font_size") == 18 and t.has_theme_font_override("font") == (Kit.title_font() != null), "the name is in the title face at 18")
	# The group capsule.
	var cap: Node = h.find_child("group_capsule", true, false)
	_check(cap is Kit.Segmented and (cap as Kit.Segmented).buttons().size() == 5, "All / Inf / Missile / Cav / None are one capsule")
	_check(h.group_buttons.keys() == ["all", "inf", "missile", "cav"] and h.deselect_button.text == "None" and h.deselect_button.name == "deselect", "group_buttons keep their keys; None is the deselect button")
	var fired: Array = []
	h.group_pressed.connect(func(k): fired.append(k))
	await _tap(h.group_buttons["inf"])
	await _frames(2)
	_check(fired == ["inf"], "a segment gives its group order (%s)" % [fired])
	var lit := 0
	for sb in (cap as Kit.Segmented).buttons():
		if (sb.get_theme_color("font_color") as Color).is_equal_approx(Kit.COL_GOLD):
			lit += 1
	_check(lit == 0, "momentary: nothing stays lit")
	for sb in (cap as Kit.Segmented).buttons():
		_check(sb.custom_minimum_size.y >= Hud.BTN_H and sb.tooltip_text != "", "segment %s keeps its touch height and has a tip" % sb.name)
	# Every HUD button has a tip and the plate.
	var no_tip: Array = []
	var no_plate: Array = []
	for n in [h.book_button, h.orders_button, h.pause_button, h.speed_button, h.menu_button, h.controls_button, h.add_button, h.undo_button, h.run_button, h.halt_button, h.fire_button, h.withdraw_button, h.stats_button]:
		if (n as Button).tooltip_text.strip_edges() == "" and n != h.pause_button:
			no_tip.append(n.name)
		if not (n as Button).has_theme_stylebox_override("normal"):
			no_plate.append(n.name)
	_check(no_tip.is_empty(), "command buttons have tips (missing %s)" % [no_tip])
	_check(no_plate.is_empty(), "command buttons wear the nav plate (missing %s)" % [no_plate])
	var tb: Control = h.book_button._make_custom_tooltip(h.book_button.tooltip_text)
	_check(tb != null and tb.find_child("tip_title", true, false) != null, "a HUD tip is the kit's boxed tip with a title")
	if tb != null:
		tb.free()
	# Selection: one card trimmed (selected flag), a few units.
	b._select_group("all")
	await _frames(3)
	var sel := 0
	for u in h._faces:
		if h._faces[u].selected:
			sel += 1
	_check(sel > 0, "cards select (%d)" % sel)
	await _shot("hud_selection")
	# Banner.
	h.banner.text = "Victory"
	h.tint_banner("Victory")
	h.banner.visible = true
	_check(h.banner.get_theme_font_size("font_size") == 30 and h.banner.has_theme_stylebox_override("normal"), "the banner is Cinzel 30 on a plate")
	await _shot("hud_banner")
	h.banner.visible = false


func _menu() -> void:
	await _new_battle(false)
	var h = b.hud
	await _tap(h.menu_button)
	await _frames(3)
	_check(b.menu != null and b.menu.visible, "the top-right Menu opens the overlay")
	_check(b.paused, "the battle is paused while it is open")
	var names: Array = []
	for n in b.menu.find_children("menu_*", "Button", true, false):
		names.append(str(n.name))
	_check(names == ["menu_resume", "menu_options", "menu_controls", "menu_leave"], "entries: Resume, Options, Controls, Leave the battle (%s)" % [names])
	await _shot("battle_menu")
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	b.menu._unhandled_input(ev)
	await _frames(2)
	_check(not b.menu.visible and not b.paused and _exits == 0, "Esc closes it and the pause is put back")
	b.paused = true
	await _tap(h.menu_button)
	await _frames(2)
	b.menu.close()
	_check(b.paused, "a battle that was paused stays paused after Resume")
	b._set_paused(false)
	await _tap(h.menu_button)
	await _frames(2)
	b.menu.find_child("menu_options", true, false).emit_signal("pressed")
	await _frames(2)
	_check(b.menu.page == "options" and b.menu.find_child("bmenu_quality", true, false) != null, "Options shows the settings")
	await _shot("battle_menu_options")
	b.menu.back()
	await _frames(1)
	b.menu.find_child("menu_leave", true, false).emit_signal("pressed")
	await _frames(2)
	_check(b.menu.page == "confirm" and _exits == 0, "Leave the battle asks first")
	await _shot("battle_menu_leave")
	b.menu.find_child("menu_stay", true, false).emit_signal("pressed")
	await _frames(1)
	_check(b.menu.page == "main", "Stay goes back")
	b.menu.find_child("menu_leave", true, false).emit_signal("pressed")
	await _frames(1)
	b.menu.find_child("menu_confirm_leave", true, false).emit_signal("pressed")
	await _frames(1)
	_check(_exits == 1, "then Leave exits (%d)" % _exits)


func _modals() -> void:
	await _new_battle(true)
	b.leave_grace = 0.0
	b._show_leave_dialog()
	await _frames(2)
	var lp: Control = b.leave_dialog.find_child("leave_panel", true, false)
	_check(lp != null and b.leave_dialog.find_child("leave_title", true, false) != null and b.leave_dialog.find_child("rule", true, false) != null, "the Leave confirm is a framed dialog with a title and a rule")
	_check((b.leave_dialog.find_child("leave_title", true, false) as Label).has_theme_font_override("font") == (Kit.title_font() != null), "its title is in the title face")
	await _shot("leave_confirm")
	b.leave_dialog.visible = false
	b.sim.winner = 0
	b._show_end_dialog("Victory")
	await _frames(2)
	_check(b.end_dialog.find_child("end_panel", true, false) != null and b.end_dialog.find_child("end_go", true, false).has_theme_stylebox_override("normal"), "the End battle card is framed with kit buttons")
	b.hud.banner.text = "Victory"
	b.hud.tint_banner("Victory")
	b.hud.banner.visible = true
	await _shot("end_battle_card")
	b.sim.winner = -1
	b.end_dialog.visible = false
	b.hud.banner.visible = false


func _sea() -> void:
	if is_instance_valid(b):
		b.free()
	var scn := Checks.scenario("boarding")
	scn["ai_sides"] = [0, 1]
	(scn["units"] as Array).append({"side": 0, "t": "fire_ship"})
	var sb = SeaBattle.new()
	sb.scenario = scn
	sb.seed_value = 3
	sb.title_text = "Sea battle off Havana"
	root.add_child(sb)
	await _frames(8)
	var seg: Node = sb.find_child("sea_speed", true, false)
	_check(seg is Kit.Segmented and sb.find_child("sea_speed_1", true, false) != null, "the speeds are one capsule (sea_speed_0..3)")
	sb._refresh_bar()
	await _frames(2)
	var full: Button = sb.find_child("sea_full", true, false)
	_check(full != null and full.get_parent() is Kit.Segmented and sb.find_child("sea_chain", true, false).get_parent() is Kit.Segmented, "sail settings and shot kinds are capsules with the same labels")
	_check(full.text == "Full sail" and sb.find_child("sea_grape", true, false).text == "Grape", "labels unchanged")
	var hold: Button = sb.find_child("sea_hold", true, false)
	_check(hold != null and hold.has_theme_stylebox_override("normal") and hold.tooltip_text != "", "the other orders wear the plate and keep their tip")
	var tb: Control = hold._make_custom_tooltip(hold.tooltip_text)
	_check(tb != null and tb.find_child("tip_title", true, false) != null, "the tip is the kit's box with the order's title")
	if tb != null:
		tb.free()
	sb.sim.s_burn[sb.selection[0]] = 400
	sb._refresh_bar()
	await _frames(2)
	var dz: Button = sb.find_child("sea_douse", true, false)
	_check(dz != null and dz.has_theme_stylebox_override("normal"), "Douse is styled like the others")
	sb._set_key(true)
	await _shot("sea_burning")
	sb._set_key(false)
	sb._open_book()
	await _frames(2)
	_check(sb.book._title.has_theme_font_override("font") == (Kit.title_font() != null), "the Ship book's title is in the title face")
	await _shot("sea_book")
	sb.book.close()
