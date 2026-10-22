extends SceneTree
## The title menu (needs a window, for the live background):
##   godot --resolution 1280x720 --script res://tests/menu_test.gd [-- --shots=DIR]
## Every entry opens its page and Back (the button, Esc, the Android back request) returns; Continue is hidden
## with no saves and shown with one (the most recent, with its setting's emblem) and opens it; the Campaign cards
## open the new-campaign page for the right setting; Grand Campaign carries the server line (the title screen
## does not), Host / Join / Game server; Battles opens the sandbox and the custom battle; Options cycles each
## setting (user://settings.cfg is put back afterwards); both backgrounds build (the diorama's build time is
## printed, the content pack is Rome again when the menu hides); both emblem styles draw; the phone layout
## (--ui-dpr 3, touch) stacks the entries centred. Script errors logged during the run are counted.
## --shots=DIR also saves the screenshots (title x background x emblems, the pages, the phone layout).
## Exits 0 on success, 1 on failure.

const UiScale := preload("res://game/ui_scale.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const Saves := preload("res://game/campaign/saves.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const MenuPrefs := preload("res://game/menu/menu_prefs.gd")
const Emblem := preload("res://game/menu/emblem.gd")
const Quality := preload("res://game/quality.gd")

const SETTINGS := "user://settings.cfg"

var failures := 0
var m: Control = null
var _shots := ""
var _settings_bytes := PackedByteArray()
var _had_settings := false


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
	Saves.subdir = "menu_test/"
	_wipe_saves()
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


func _wipe_saves() -> void:
	for e in Saves.list():
		Saves.delete(str(e["slot"]))


func _restore_settings() -> void:
	if _had_settings:
		var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
		f.store_buffer(_settings_bytes)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _shot(name: String) -> void:
	if _shots == "":
		return
	await _frames(3)
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])


func _new_menu() -> void:
	if m != null:
		m.queue_free()
		await _frames(2)
	PackView.use_pack("rome")
	m = (load("res://game/main.gd") as GDScript).new()
	root.add_child(m)
	await _frames(4)


func _btn(nm: String) -> Button:
	return m.find_child(nm, true, false) as Button


func _press(nm: String) -> void:
	var b := _btn(nm)
	_check(b != null, "button %s exists" % nm)
	if b != null:
		b.pressed.emit()
	await _frames(3)


func _visible_in_page(c: Control) -> bool:
	return c != null and c.is_visible_in_tree()


func _run() -> void:
	UiScale._dpr_override = 1.0
	UiScale._touch_override = 0
	MenuPrefs.bg_override = "art"
	await _new_menu()
	await _frames(20)
	await _entries()
	await _continue()
	await _campaign_page()
	await _grand_page()
	await _battles_page()
	await _options_page()
	await _emblems()
	await _backgrounds()
	await _phone()
	_wipe_saves()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://campaigns/menu_test"))
	m.queue_free()
	await _frames(3)
	_restore_settings()
	_check(_errs.n == 0, "no script errors logged during the run (%d: %s)" % [_errs.n, _errs.first])
	print("RESULT ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)


# ------------------------------------------------------------ entries ---

func _entries() -> void:
	_check(m.page == "home", "starts on the title screen")
	for nm in ["home_campaign", "home_grand", "home_battles", "home_options"]:
		_check(_visible_in_page(_btn(nm)), "%s is on the title screen" % nm)
	_check(not _visible_in_page(_btn("home_continue")), "Continue is hidden with no saves")
	_check(m._net_line == null or not m._home.is_ancestor_of(m._net_line), "the title screen has no server line")
	_check(m._back_btn != null and not m._back_btn.visible, "no Back on the title screen")
	await _shot_title("title_start")
	for pair in [["home_campaign", "campaign"], ["home_grand", "grand"], ["home_battles", "battles"], ["home_options", "options"]]:
		await _press(pair[0])
		_check(m.page == pair[1], "%s opens the %s page" % [pair[0], pair[1]])
		_check(m._back_btn.visible and (m._pages[pair[1]] as Control).visible, "the %s page shows a Back button" % pair[1])
		m._back_btn.pressed.emit()
		await _frames(2)
		_check(m.page == "home", "Back returns from %s" % pair[1])
	# Esc and the Android back request
	m.show_page("options")
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	m._unhandled_input(esc)
	_check(m.page == "home", "Esc returns from Options")
	m.show_page("grand")
	m._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(m.page == "home", "the Android back request returns from Grand Campaign")
	m.show_page("home")
	await _frames(2)
	m.go_back()
	_check(m.page == "home", "Back on the title screen stays there")


func _shot_title(name: String) -> void:
	await create_timer(0.9).timeout   # (the entries slide in over about a second of wall time)
	await _shot(name)


# ----------------------------------------------------------- continue ---

func _save(nm: String, sd: int, pack: String, turn: int) -> void:
	var st := CState.new_campaign(nm, sd, [0], {}, [], pack)
	st["turn"] = turn
	Saves.save(Saves.slot_for(nm, sd), {"state": st, "session": {"subs": [], "plans": {}, "seen": {}}})
	PackView.use_pack("rome")


func _continue() -> void:
	_save("Older", 11, "rome", 3)
	await create_timer(1.1).timeout   # (saved_at is in seconds)
	_save("Newest", 12, "west", 6)
	m.show_page("home")
	await _frames(3)
	var holder: Control = _btn("home_continue").get_parent()
	_check(holder.visible, "Continue shows with a save")
	_check(_btn("home_continue").text == "Continue: Newest, turn 7", "Continue names the most recent save (%s)" % _btn("home_continue").text)
	_check((m._continue_emblem as Emblem).pack == "west", "Continue carries the save's setting emblem")
	_check((m._home_emblem as Emblem).pack == "west", "the wordmark's emblem follows the last-played setting")
	await _shot_title("title_continue")
	m.page = "home"
	_btn("home_continue").pressed.emit()
	await _frames(30)
	_check(m.campaign != null and str(m.campaign.st["name"]) == "Newest", "Continue opens that campaign")
	m._close_campaign()
	await _frames(4)
	_check(m.page == "home" and m._menu.visible, "closing the campaign returns to the title screen")


# ----------------------------------------------------------- campaign ---

func _campaign_page() -> void:
	m.show_page("campaign")
	await _frames(3)
	var rows := 0
	for c in m._continue_box.get_children():
		if c is HBoxContainer:
			rows += 1
	_check(rows == 2, "Your campaigns lists both local saves (%d)" % rows)
	_check(_btn("card_west") != null and _btn("card_rome") != null, "two setting cards")
	_check(_btn("home_Import") != null, "Import is on the Campaign page")
	await _shot("campaign_page")
	for pk in ["west", "rome"]:
		await _press("card_" + pk)
		_check(m._new_campaign != null and m._new_campaign.pack_pick == pk, "card %s opens the new-campaign page" % pk)
		_check(CData.pack == pk, "... on the %s setting" % pk)
		var key := "brethren" if pk == "west" else "rome"
		_check(m._new_campaign.find_child("row_" + key, true, false) != null, "... with its faction rows (%s)" % key)
		_check(m._new_campaign.find_child("pack_west", true, false) == null, "... without the Setting row")
		await _shot("newcampaign_" + pk)
		m._new_campaign.back.emit()
		await _frames(3)
		_check(m._new_campaign == null and m._menu.visible and m.page == "campaign", "Back from the faction page returns to Campaign")
	await _press("home_Import")
	_check(m.page == "import", "Import opens the import page")
	m._back_btn.pressed.emit()
	_check(m.page == "campaign", "Back from Import returns to Campaign")


# -------------------------------------------------------------- grand ---

func _grand_page() -> void:
	m.show_page("grand")
	await _frames(3)
	_check(m._pages["grand"].is_ancestor_of(m._net_line), "the server line is on the Grand Campaign page")
	for nm in ["home_Online_co-op", "home_Join", "home_server"]:
		_check(_btn(nm) != null and _btn(nm).is_visible_in_tree(), "%s is on the Grand Campaign page" % nm)
	await _shot("grand_page")
	await _press("home_Join")
	_check(m.page == "join", "Join with a code opens the join page")
	m._back_btn.pressed.emit()
	_check(m.page == "grand", "Back from Join returns to Grand Campaign")
	await _press("home_server")
	_check(m.page == "server", "Game server opens its page")
	m._back_btn.pressed.emit()
	_check(m.page == "grand", "Back from Game server returns to Grand Campaign")
	await _press("home_Online_co-op")
	_check(m._new_campaign != null and m._new_campaign.online, "Host a new grand campaign opens the online new-campaign page")
	m._new_campaign.back.emit()
	await _frames(3)
	_check(m.page == "grand" and m._menu.visible, "... and Back returns to Grand Campaign")


# ------------------------------------------------------------ battles ---

func _battles_page() -> void:
	m.show_page("battles")
	await _frames(3)
	await _press("home_sandbox")
	_check(m.page == "sandbox", "Battle sandbox opens the sandbox page")
	m._back_btn.pressed.emit()
	_check(m.page == "battles", "Back from the sandbox returns to Battles")
	await _press("home_custom")
	_check(m.custom != null and not m._menu.visible, "Custom battle opens the custom screen")
	m.custom.back.emit()
	await _frames(3)
	_check(m.custom == null and m._menu.visible, "... and returns to the menu")


# ------------------------------------------------------------ options ---

func _options_page() -> void:
	m.show_page("options")
	await _frames(3)
	await _shot("options_page")
	_check(_btn("home_tests") == null, "no Tests and benchmarks without --dev")
	_check(not m._tests_button.visible, "the sandbox page hides its Tests button without --dev")
	for nm in ["home_ui_size", "home_quality", "home_soldiers", "home_battle_look", "home_map_style", "home_menu_bg", "home_menu_emblems"]:
		var b := _btn(nm)
		_check(b != null, "Options has %s" % nm)
		if b == null:
			continue
		var seen := {b.text: true}
		for k in 4:
			b.pressed.emit()
			await _frames(1)
			seen[b.text] = true
		_check(seen.size() >= 2, "%s cycles (%s)" % [nm, ", ".join(seen.keys())])
	_check(_btn("audio_mute") != null and _btn("home_controls") != null and _btn("home_unit_book") != null and _btn("home_fullscreen") != null, "Options has Audio, Controls, Unit book and Fullscreen")
	# the two menu settings reach the config file
	MenuPrefs.set_background("diorama")
	MenuPrefs.set_emblems("painted")
	_check(MenuPrefs.stored_background() == "diorama" and MenuPrefs.stored_emblems() == "painted", "the menu settings are kept in [menu]")
	m._update_menu_buttons()
	_check(_btn("home_menu_bg").text.contains("diorama") and _btn("home_menu_emblems").text.contains("painted"), "their buttons show them")
	MenuPrefs.set_background("auto")
	MenuPrefs.set_emblems("drawn")
	MenuPrefs.dev_override = true
	await _new_menu()
	m.show_page("options")
	_check(_btn("home_tests") != null, "Tests and benchmarks appear with --dev")
	_btn("home_tests").pressed.emit()
	await _frames(2)
	_check(m.page == "sandbox" and m._tests_box.visible, "... and open the test list")
	MenuPrefs.dev_override = false
	await _new_menu()


# ----------------------------------------------------------- emblems ---

func _emblems() -> void:
	for pk in ["west", "rome"]:
		var d: Emblem = Emblem.make(pk, 96, "drawn")
		var p: Emblem = Emblem.make(pk, 96, "painted")
		root.add_child(d)
		root.add_child(p)
		await _frames(2)
		_check(d.shown_style() == "drawn", "%s: the drawn style draws vectors" % pk)
		_check(p.shown_style() == ("painted" if Emblem.painted(pk) != null else "drawn"), "%s: the painted style %s" % [pk, "uses the PNG" if Emblem.painted(pk) != null else "falls back to the drawn mark (no file)"])
		d.queue_free()
		p.queue_free()
	if _shots != "":
		var sheet := Control.new()
		sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var bgc := ColorRect.new()
		bgc.color = Color(0.1, 0.12, 0.12)
		bgc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sheet.add_child(bgc)
		var x := 20
		for pk in ["west", "rome"]:
			for st in ["drawn", "painted"]:
				for px in [256, 96, 40, 20]:
					var e: Control = Emblem.make(pk, px, st)
					e.position = Vector2(x, 20 if px == 256 else 300)
					sheet.add_child(e)
					x += px + 12
		root.add_child(sheet)
		await _shot("emblems_sheet")
		sheet.queue_free()


# ------------------------------------------------------- backgrounds ---

func _backgrounds() -> void:
	# art: the placeholder or the painted picture, no world
	MenuPrefs.bg_override = "art"
	PackView.use_pack("rome")
	m.show_page("home")
	m._activate_bg()
	await _frames(5)
	_check(m._bg.mode == "art" and m._bg.diorama == null, "art background: no diorama is built")
	await _shot_title("title_art_drawn")
	MenuPrefs.set_emblems("painted")
	call_group("menu_emblem", "queue_redraw")
	await _shot_title("title_art_painted")
	MenuPrefs.set_emblems("drawn")
	# diorama
	MenuPrefs.bg_override = "diorama"
	var ms := 0.0
	for pk in ["west", "rome"]:
		MenuPrefs.set_background("diorama")
		m._bg.deactivate()
		await _frames(2)
		_check(CData.pack == "rome", "the content pack is Rome with no diorama")
		m._bg.activate(pk)
		var d = null
		for k in 900:
			await process_frame
			d = m._bg.diorama
			if d != null and is_instance_valid(d) and d.ready_flag:
				break
		_check(d != null and d.ready_flag, "the %s diorama builds" % pk)
		if d != null and d.ready_flag:
			ms = d.build_ms
			print("  diorama %s built in %.0f ms: %s" % [pk, ms, str(d.steps_ms)])
			_check(ms < 2500.0, "the %s diorama builds in %.0f ms (target 1500)" % [pk, ms])
			_check(CData.pack == pk, "the diorama holds the %s content pack" % pk)
			await _frames(30)
			if pk == "west":
				await _shot_title("title_diorama_drawn")
				MenuPrefs.set_emblems("painted")
				call_group("menu_emblem", "queue_redraw")
				await _shot_title("title_diorama_painted")
				MenuPrefs.set_emblems("drawn")
				call_group("menu_emblem", "queue_redraw")
			else:
				await _shot("title_diorama_rome")
	# hiding the menu frees the diorama and puts Rome back
	m._menu.visible = false
	await _frames(3)
	_check(m._bg.diorama == null and CData.pack == "rome", "hiding the menu frees the diorama and restores Rome")
	m._menu.visible = true
	await _frames(3)
	for k in 900:
		await process_frame
		if m._bg.diorama != null and is_instance_valid(m._bg.diorama) and m._bg.diorama.ready_flag:
			break
	_check(m._bg.diorama != null and m._bg.diorama.ready_flag, "showing the menu again rebuilds it")
	m._menu.visible = false
	await _frames(2)
	# auto: art on Low graphics
	MenuPrefs.bg_override = "auto"
	Quality.save_pref("low")
	_check(MenuPrefs.background() == "art", "auto picks the picture on Low graphics")
	Quality.save_pref("high")
	_check(MenuPrefs.background() == "diorama", "auto picks the diorama on High graphics")
	Quality.save_pref("auto")
	MenuPrefs.bg_override = "art"
	m._menu.visible = true
	await _frames(3)


# ------------------------------------------------------------- phone ---

func _phone() -> void:
	m.show_page("home")
	await _frames(3)
	var desk_x: float = m._home_stack.get_global_rect().get_center().x
	_check(not m._phone_layout and desk_x < m.get_viewport_rect().size.x * 0.4, "desktop: the entries sit on the left (x %.0f)" % desk_x)
	UiScale._dpr_override = 3.0
	UiScale._touch_override = 1
	var old := DisplayServer.window_get_size()
	DisplayServer.window_set_size(Vector2i(844, 390))
	await _frames(6)
	UiScale.apply(root)
	await _frames(4)
	m._layout_home()
	await _frames(3)
	var vp: Vector2 = m.get_viewport_rect().size
	var cx: float = m._home_stack.get_global_rect().get_center().x
	_check(m._phone_layout, "phone: the phone layout is on (viewport %s)" % str(vp))
	_check(absf(cx - vp.x * 0.5) < 24.0, "phone: the entries are centred (x %.0f of %.0f)" % [cx, vp.x])
	var all_in := true
	for w in m._entries:
		if (w as Control).visible and not Rect2(Vector2.ZERO, vp).encloses((w as Control).get_global_rect()):
			all_in = false
	_check(all_in, "phone: every entry fits on the screen")
	await _shot_title("title_phone")
	m.show_page("campaign")
	await _frames(3)
	await _shot("campaign_phone")
	m.show_page("home")
	UiScale._dpr_override = 1.0
	UiScale._touch_override = 0
	DisplayServer.window_set_size(old)
	await _frames(6)
	UiScale.apply(root)
	await _frames(3)
