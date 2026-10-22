extends SceneTree
## The in-game UI theme (pass 1: the kit and the campaign screen; needs a window):
##   godot --resolution 1280x720 --script res://tests/theme_test.gd [-- --shots=DIR]
## Kit: the title face and its 18 px floor, the trim box, the rule, the hero button, the button motion (and that it
## is off with Quality Low / the override), the emblem. Campaign screen: the top bar (emblem, faction name in the
## display face, gold rule), End turn as the hero button, the Menu overlay (entries in order, Esc / back one step,
## Options with the title screen's settings, the Main menu confirm, Save), the dialog frame and title, the side panel
## trim, the command bar (the selected card only has the trim, the leader title in the display face), the loading panel
## (key art, tip, bar) and the slow turn resolve behind it, the city names in the display face at the diorama zoom,
## the phone layout (--ui-dpr 3, touch: nothing leaves the screen). Script errors are counted.
## --shots=DIR saves the screenshots (campaign bar, Menu overlay pages, dialog, loading panel, phone). Exits 0 / 1.

const UiScale := preload("res://game/ui_scale.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTurn := preload("res://campaign/cturn.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const LoadingPanel := preload("res://game/campaign/loading_panel.gd")
const MapOverlay := preload("res://game/campaign/map_overlay.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const Quality := preload("res://game/quality.gd")

const SETTINGS := "user://settings.cfg"

var failures := 0
var cs
var _shots := ""
var _settings_bytes := PackedByteArray()
var _had_settings := false
var _exit_seen := false


class ErrCount extends Logger:
	var n := 0
	var first := ""

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_SCRIPT:
			n += 1
			if first == "":
				first = "%s:%d %s %s" % [file, line, code, rationale]


var _errs := ErrCount.new()


func _initialize() -> void:
	OS.add_logger(_errs)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.get_slice("=", 1)
	_had_settings = FileAccess.file_exists(SETTINGS)
	if _had_settings:
		_settings_bytes = FileAccess.get_file_as_bytes(SETTINGS)
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
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


func _shot(name: String) -> void:
	if _shots == "":
		return
	await _frames(4)
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])


func _restore_settings() -> void:
	if _had_settings:
		var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
		f.store_buffer(_settings_bytes)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _open_screen(pack: String, tag: String) -> void:
	PackView.use_pack(pack)
	var humans: Array = [CData.faction_index("england" if pack == "west" else "rome")]
	var st := CState.new_campaign("Theme", 3, humans, {}, [], pack)
	cs = CampaignScreen.new()
	cs.open({"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}, "theme_test_" + tag)
	cs.exit_requested.connect(func(): _exit_seen = true)
	root.add_child(cs)
	await _frames(8)
	for k in 3:   # (an introduction card or the like: close what opened)
		if cs.dialog_open():
			cs.close_dialog()
			await _frames(2)


func _close_screen() -> void:
	if cs != null:
		cs.queue_free()
		cs = null
	await _frames(3)


func _button_in(parent: Node, nm: String) -> Button:
	return parent.find_child(nm, true, false) as Button


func _empty_tips() -> void:
	# An empty tooltip shows nothing: no box for a button with no tip, "", whitespace or a blank tip().
	for tv in [null, "", "\n", " \n  "]:
		var eb := Kit.button("Continue", Callable())
		if tv != null:
			eb.tooltip_text = str(tv)
		_check(eb._make_custom_tooltip(eb.tooltip_text) == null, "a kit button with tip %s makes no tooltip control" % [var_to_str(tv)])
		_check(Kit.tip_of(eb).is_empty(), "... and the touch host finds no tip on it")
		eb.free()
	var eb2 := Kit.button("Continue", Callable())
	Kit.tip(eb2, "", "")
	_check(eb2.tooltip_text == "" and eb2._make_custom_tooltip("") == null, "Kit.tip with an empty title and text clears the tip")
	eb2.free()
	var eo := Kit.dropdown([["a", 1]], 1, Callable())
	var ee := Kit.text_field("x")
	_check(eo._make_custom_tooltip("\n") == null and ee._make_custom_tooltip("") == null, "dropdowns and fields too")
	eo.free()
	ee.free()


func _run() -> void:
	UiScale._dpr_override = 1.0
	UiScale._touch_override = 0
	Kit.anim_override = 0
	_empty_tips()
	await _kit()
	await _screen("west")
	await _loading()
	await _phone()
	await _screen_rome()
	_restore_settings()
	_check(_errs.n == 0, "no script errors logged (%d) %s" % [_errs.n, _errs.first])
	print("RESULT ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------- the kit ---

func _kit() -> void:
	var t := Kit.title("Small", 10)
	_check(t.get_theme_font_size("font_size") == Kit.TITLE_MIN, "a title is never under %d px (asked 10)" % Kit.TITLE_MIN)
	_check(Kit.title_font() != null and t.has_theme_font_override("font"), "the title uses the display face (Cinzel)")
	var lbl := Kit.label("body", 15)
	_check(not lbl.has_theme_font_override("font"), "body text keeps the UI face")
	var sb := Kit.trim_box()
	_check(sb is Kit.TrimBox and sb.get_minimum_size().x >= 20.0, "trim_box is the trim style with content margins")
	var ls := Kit.trim_lines(Rect2(0, 0, 200, 100), 4.0, 12.0)
	_check(ls.size() == 5 and (ls[0] as PackedVector2Array).size() == 5, "the trim is a rule and four corner brackets")
	_check((ls[0] as PackedVector2Array)[0] == Vector2(4, 4), "the rule is inset 4 px")
	var rl := Kit.rule()
	_check(rl.custom_minimum_size.y == 1.0, "rule() is a 1 px hairline")
	var hb := Kit.hero_button("End turn", "end_turn", Callable())
	_check(hb.custom_minimum_size.y >= 48.0 and hb.get_theme_font_size("font_size") >= 18, "hero_button is larger (48 px, 18 pt)")
	_check(hb.get_theme_stylebox("normal").border_width_left == 2, "hero_button has the gold trim")
	var plain := Kit.icon_button("Diplomacy", "diplomacy", Callable(), 0)
	var plated := Kit.icon_button("Diplomacy", "diplomacy", Callable(), 0)
	Kit.nav_style(plated)
	_check(plain.get_combined_minimum_size() == plated.get_combined_minimum_size(), "the plate style keeps a top bar button's size (%s)" % str(plated.get_combined_minimum_size()))
	var em := Kit.emblem("west", 40.0)
	_check(em.custom_minimum_size == Vector2(40, 40), "Kit.emblem returns a 40 px emblem control")
	# The motion.
	var host := Control.new()
	root.add_child(host)
	var b := Kit.button("Motion", Callable(), 100)
	host.add_child(b)
	await _frames(2)
	Kit.anim_override = 1
	b.mouse_entered.emit()
	await create_timer(0.25).timeout
	_check(absf(b.scale.x - Kit.HOT_SCALE) < 0.002, "a button grows 3 %% under the pointer (%.3f)" % b.scale.x)
	b.mouse_exited.emit()
	await create_timer(0.25).timeout
	_check(absf(b.scale.x - 1.0) < 0.002, "and goes back when it leaves")
	Kit.anim_override = 0
	b.mouse_entered.emit()
	await _frames(3)
	_check(b.scale == Vector2.ONE, "no motion when animation is off (Quality Low / --no-anim / override)")
	Kit.anim_override = 1
	var dis := Kit.button("Off", Callable(), 100)
	dis.disabled = true
	host.add_child(dis)
	await _frames(2)
	dis.mouse_entered.emit()
	await create_timer(0.2).timeout
	_check(dis.scale == Vector2.ONE, "a disabled button stays put")
	Kit.anim_override = 0
	host.queue_free()
	await _frames(2)


# --------------------------------------------------------- campaign screen ---

func _screen(pack: String) -> void:
	await _open_screen(pack, pack)
	var vp: Vector2 = cs._vp()
	# Top bar.
	var tb: Control = cs.find_child("top_bar", true, false)
	var sbx := tb.get_theme_stylebox("panel") as StyleBoxFlat
	_check(sbx.border_width_bottom == 1, "the top bar has a gold rule under it")
	_check(cs.top_emblem != null and cs.top_emblem.visible and str(cs.top_emblem.get("pack")) == pack, "the top bar shows the %s emblem" % pack)
	_check(cs.top_label.has_theme_font_override("font") and cs.top_label.get_theme_font_size("font_size") >= 18, "the faction name is in the display face at 18+ px")
	_check(cs.end_button.name == "hero_button" and cs.end_button.get_theme_stylebox("normal").border_width_left == 2, "End turn is the hero button")
	_check(cs.end_button.get_global_rect().end.x <= vp.x and cs.end_button.get_global_rect().end.y <= vp.y, "End turn is on screen")
	var nav: Button = cs.battles_button
	_check(nav.get_theme_stylebox("normal").border_width_left == 1, "the top bar buttons are in the menu's plate style")
	# Select an army: the bar.
	var mine: Array = []
	for a in cs.st["armies"]:
		if int(a["f"]) == cs.f:
			mine.append(int(a["id"]))
	_check(not mine.is_empty(), "the player has an army")
	cs.select_army(mine[0])
	await _frames(6)
	cs._refresh_bar()
	await _frames(4)
	_check(cs.cmd_bar.visible, "the command bar shows the selection")
	var lt: Label = cs.cmd_bar.find_child("leader_title", true, false)
	_check(lt != null and (lt.has_theme_font_override("font") == (not cs.cmd_bar.phone)), "the leader title is in the display face (desktop) at %d px" % (lt.get_theme_font_size("font_size") if lt else 0))
	if lt != null and not cs.cmd_bar.phone:
		_check(lt.get_theme_font_size("font_size") >= 18, "... and at 18 px or more")
	await _shot("campaign_%s_bar" % pack)
	cs.open_details()
	await _frames(5)
	_check(cs.side.visible and cs.side.get_theme_stylebox("panel") is Kit.TrimBox, "the side panel has the trim")
	await _shot("campaign_%s_side" % pack)
	cs.close_details()
	cs.deselect_all()
	await _frames(3)
	# A dialog.
	var box := Kit.vbox(6)
	box.add_child(Kit.label("The armies march, the AI moves, battles are joined...", Kit.FONT, Color.WHITE, true))
	cs.show_dialog("Resolving the turn", box, [["Close", Callable()]], 460)
	await _frames(4)
	_check(cs.dialog.get_theme_stylebox("panel") is Kit.TrimBox, "the dialog has the trim")
	_check(cs.dialog_title.has_theme_font_override("font") and cs.dialog_title.get_theme_font_size("font_size") >= 18, "the dialog title is in the display face")
	_check(cs.dialog_rule.visible, "a titled dialog has the gold rule under its title")
	await _shot("dialog_%s" % pack)
	cs.show_dialog("", Kit.label("no title", Kit.FONT), [["Close", Callable()]], 300)
	await _frames(2)
	_check(not cs.dialog_rule.visible, "an untitled dialog has no rule")
	cs.close_dialog()
	await _frames(2)
	# The Menu overlay.
	await _menu(pack)
	# City names at the diorama zoom.
	var r := 0
	for k in CData.region_count():
		if str(CData.REGIONS[k]["key"]) in ["port_royal", "roma"]:
			r = k
	cs.focus_region(r, 2.0)
	await _frames(8)
	var disp := false
	for k in MapOverlay._lines.keys():
		if str(k).ends_with("|1"):
			disp = true
	_check(disp, "city names are drawn in the display face at the diorama zoom (%.1f)" % cs.zoom)
	await _shot("map_labels_%s" % pack)
	cs.focus_region(r, 0.8)
	cs.zoom = 0.8
	await _frames(4)
	_check(cs.zoom < MapOverlay.DIORAMA_ZOOM, "below the diorama zoom the names keep the UI face")
	# The slow turn resolve behind the loading panel.
	LoadingPanel.last_resolve_ms = 900.0
	var turn0 := int(cs.st["turn"])
	cs.data["session"]["subs"] = [CTurn.submission(cs.st, cs.f, [])]
	cs._resolve_soon()
	await _frames(1)
	var lp := root.find_child("loading_panel", true, false)
	_check(lp != null and not cs.dialog.visible, "a slow resolve shows the loading panel, not the dialog")
	await _frames(8)
	_check(root.find_child("loading_panel", true, false) == null, "the panel is gone when the turn is resolved")
	_check(int(cs.st["turn"]) > turn0, "and the turn advanced (%d -> %d)" % [turn0, int(cs.st["turn"])])
	LoadingPanel.last_resolve_ms = 100.0
	cs.close_dialog()
	await _frames(2)
	cs.data["session"]["subs"] = [CTurn.submission(cs.st, cs.f, [])]
	cs._resolve_soon()
	await _frames(1)
	_check(cs.dialog.visible and root.find_child("loading_panel", true, false) == null, "a quick resolve keeps the small dialog")
	await _frames(8)
	cs.close_dialog()
	await _close_screen()


func _menu(pack: String) -> void:
	var gm = cs.game_menu
	_check(not gm.visible, "the Menu overlay starts closed")
	var mb := _button_in(cs, "menu")
	_check(mb != null, "the Menu button exists")
	mb.pressed.emit()
	await _frames(3)
	_check(gm.visible and cs._blocked(), "the Menu overlay opens and blocks the map")
	var names: Array = []
	for c in gm.body.get_children():
		if c is Button and str(c.name).begins_with("menu_") and c.get_parent() == gm.body:
			names.append(str(c.name))
	_check(names == ["menu_resume", "menu_save", "menu_options", "menu_controls", "menu_leave"], "entries in order: %s" % str(names))
	_check(gm.find_child("menu_title", true, false).has_theme_font_override("font"), "the campaign name is in the display face")
	_check(gm.column.get_global_rect().size.x <= 440.5 and gm.column.get_global_rect().position.x == 0.0, "the entries stack on the left")
	await _shot("menu_%s_main" % pack)
	# Options.
	_button_in(gm, "menu_options").pressed.emit()
	await _frames(3)
	var rows = gm._rows
	_check(gm.page == "options" and rows != null and rows.seg.has("quality") and rows.seg.has("map_style") and rows.seg.has("battle_look") \
		and rows.seg.has("soldiers") and rows.seg.has("ui_size") and rows.seg.has("fullscreen") and rows.seg.has("audio_mute") and rows.sliders.size() == 3,
		"Options has the title screen's rows (UI size, graphics, soldiers, fullscreen, battle look, map style, audio)")
	_check(not rows.seg.has("menu_bg") and gm.find_child("menu_quality_low", true, false) != null, "the in-game rows leave out the menu picture and emblems")
	var q0 := Quality.load_pref()
	var qother := "low" if q0 != "low" else "high"
	rows.seg["quality"].button_for(qother).pressed.emit()
	await _frames(2)
	_check(Quality.load_pref() == qother and rows.seg["quality"].value == qother, "the graphics capsule sets the saved setting")
	Quality.save_pref(q0)
	await _shot("menu_%s_options" % pack)
	gm.back()
	await _frames(2)
	_check(gm.visible and gm.page == "main", "back from Options returns to the entries")
	# The leave confirm.
	_button_in(gm, "menu_leave").pressed.emit()
	await _frames(3)
	_check(gm.page == "confirm" and _button_in(gm, "menu_confirm_leave") != null, "Main menu asks for a confirm")
	await _shot("menu_%s_confirm" % pack)
	_button_in(gm, "menu_stay").pressed.emit()
	await _frames(2)
	_check(gm.page == "main" and not _exit_seen, "Stay returns to the entries without leaving")
	# Save.
	_button_in(gm, "menu_save").pressed.emit()
	await _frames(3)
	_check(not gm.visible, "Save saves and closes the overlay")
	# Esc and the back request.
	cs.panels.show_menu()
	await _frames(3)
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(3)
	_check(not gm.visible, "Esc closes the overlay")
	cs.panels.show_menu()
	await _frames(2)
	_button_in(gm, "menu_options").pressed.emit()
	await _frames(2)
	gm.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(2)
	_check(gm.visible and gm.page == "main", "the back request goes one step back")
	gm.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _frames(2)
	_check(not gm.visible, "... and then closes")
	# Resume, Controls.
	cs.panels.show_menu()
	await _frames(2)
	_button_in(gm, "menu_resume").pressed.emit()
	await _frames(2)
	_check(not gm.visible, "Resume closes the overlay")
	cs.panels.show_menu()
	await _frames(2)
	_button_in(gm, "menu_controls").pressed.emit()
	await _frames(3)
	_check(not gm.visible and cs.controls_page.visible, "Controls closes the overlay and opens the controls page")
	cs.controls_page.close()
	await _frames(3)
	# Leave.
	cs.panels.show_menu()
	await _frames(2)
	_button_in(gm, "menu_leave").pressed.emit()
	await _frames(2)
	_button_in(gm, "menu_confirm_leave").pressed.emit()
	await _frames(3)
	_check(_exit_seen and not gm.visible, "the confirm leaves to the main menu (saved)")
	_exit_seen = false


# ------------------------------------------------------------ loading panel ---

func _loading() -> void:
	for pack in ["west", "rome"]:
		PackView.use_pack(pack)
		var lp = LoadingPanel.open(root, "Preparing the battlefield", 3, pack)
		await lp.step("Building the battlefield")
		await _frames(3)
		var art := lp.find_child("loading_art", true, false) as TextureRect
		_check(art != null and art.texture != null and art.modulate.r < 0.7, "%s: the loading panel shows the key art, darkened" % pack)
		var tip := lp.find_child("loading_tip", true, false) as Label
		_check(tip != null and tip.text != "" and LoadingPanel.TIPS.has(tip.text), "%s: it shows a tip from the list" % pack)
		_check(lp.find_child("loading_title", true, false).has_theme_font_override("font"), "%s: the title is in the display face" % pack)
		_check(lp.bar.max_value == 3.0 and lp.step_label.text.begins_with("Building"), "%s: the bar and the step are there" % pack)
		await _shot("loading_%s" % pack)
		await lp.done()
		lp.close()
		await _frames(2)
	_check(LoadingPanel.TIPS.size() >= 8 and LoadingPanel.TIPS.all(func(t): return t.length() < 120 and not t.contains("\n")), "the tips are one line each")
	LoadingPanel.last_resolve_ms = -1.0
	_check(not LoadingPanel.slow_resolve(), "an unknown resolve time is not slow")
	LoadingPanel.last_resolve_ms = 600.0
	_check(LoadingPanel.slow_resolve(), "a resolve over 0.5 s is slow")
	LoadingPanel.last_resolve_ms = -1.0


# -------------------------------------------------------------------- phone ---

func _phone() -> void:
	UiScale._dpr_override = 3.0
	UiScale._touch_override = 1
	var old := DisplayServer.window_get_size()
	DisplayServer.window_set_size(Vector2i(844, 390))
	await _frames(6)
	UiScale.apply(root)
	await _frames(4)
	await _open_screen("west", "phone")
	await _frames(4)
	var vp: Vector2 = cs._vp()
	var tb: Control = cs.find_child("top_bar", true, false)
	_check(tb.get_global_rect().size.y <= 60.0, "phone: the top bar is one row (%s of %s)" % [str(tb.get_global_rect().size), str(vp)])
	_check(not cs.top_emblem.visible and not cs.top_label.has_theme_font_override("font"), "phone: the plain face and no emblem, as before")
	_check(cs.end_button.get_global_rect().end.x <= vp.x and cs.end_button.size.y >= 48.0, "phone: End turn keeps its 48 px height and fits")
	cs.panels.show_menu()
	await _frames(4)
	var gm = cs.game_menu
	_check(gm.column.get_global_rect().end.x <= vp.x + 1.0, "phone: the Menu column fits the screen")
	var fit := true
	for c in gm.body.get_children():
		if c is Button and (c as Button).get_global_rect().size.y < 44.0:
			fit = false
	_check(fit, "phone: the entries are touch-sized")
	await _shot("phone_menu")
	gm.close()
	cs.select_army(int(cs.st["armies"][0]["id"]) if int(cs.st["armies"][0]["f"]) == cs.f else _first_army())
	await _frames(6)
	cs._refresh_bar()
	await _frames(3)
	await _shot("phone_bar")
	cs.deselect_all()
	var lp = LoadingPanel.open(root, "Resolving the turn", 1, "west")
	await lp.step("The armies march, the AI moves")
	await _frames(3)
	var box := lp.find_child("loading_box", true, false) as Control
	_check(box != null and box.get_global_rect().end.x <= vp.x + 1.0, "phone: the loading panel fits (%s)" % str(box.get_global_rect()) if box else "phone: loading_box")
	await _shot("phone_loading")
	lp.close()
	await _close_screen()
	UiScale._dpr_override = 1.0
	UiScale._touch_override = 0
	DisplayServer.window_set_size(old)
	await _frames(6)
	UiScale.apply(root)
	await _frames(3)


func _first_army() -> int:
	for a in cs.st["armies"]:
		if int(a["f"]) == cs.f:
			return int(a["id"])
	return -1


func _screen_rome() -> void:
	await _screen("rome")
