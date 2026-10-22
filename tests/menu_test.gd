extends SceneTree
## The title menu (needs a window, for the live background):
##   godot --resolution 1280x720 --script res://tests/menu_test.gd [-- --shots=DIR]
## Every entry opens its page and Back (the button, Esc, the Android back request) returns; Continue is hidden
## with no saves and shown with one (the most recent, with its setting's emblem) and opens it; the Campaign cards
## open the new-campaign page for the right setting (its blurbs are not clipped, Start waits for a human with a tip);
## Grand Campaign carries the server line (the title screen does not), the Host card (it opens the faction page in
## online mode for the picked setting), the Join card (validates a code, shows the error), Your grand campaigns (rows
## from a stub seat store), the Game server row; Battles opens the sandbox and the custom battle; Options' capsules
## set the stored values and its sliders the volumes (user://settings.cfg is put back afterwards); boxed tooltips (the
## box on a tipped button, the touch long press); both backgrounds build (the diorama's build time is
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
const Kit := preload("res://game/campaign/ui_kit.gd")
const Accounts := preload("res://game/net/accounts.gd")
const SoldierLayer := preload("res://game/soldier_layer.gd")
const BattleLook := preload("res://game/battle_look.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const AudioFx := preload("res://game/audio.gd")

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
	await _tooltips()
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
		await _shot("faction_" + pk)
		await _faction_checks(m._new_campaign, key)
		if pk == "west":
			await _scroll_shot(m._new_campaign, "faction_west_settings", 100000)
		m._new_campaign.back.emit()
		await _frames(3)
		_check(m._new_campaign == null and m._menu.visible and m.page == "campaign", "Back from the faction page returns to Campaign")
	await _press("home_Import")
	_check(m.page == "import", "Import opens the import page")
	m._back_btn.pressed.emit()
	_check(m.page == "campaign", "Back from Import returns to Campaign")


# -------------------------------------------------------------- grand ---

func _grand_page() -> void:
	var net: Node = m._net()
	var keep_accounts = null
	var keep_base := ""
	if net != null:
		# A scratch seat store and a server nobody listens on: the rows come from the stub, nothing leaves the machine.
		keep_accounts = net.accounts
		keep_base = net.api.base_url
		net.api.base_url = "http://127.0.0.1:8074"
		net.accounts = Accounts.new("user://menu_test/accounts.json")
		net.accounts.data["campaigns"] = {}
		net.accounts.save()
	m.show_page("grand")
	await _frames(3)
	_check(m._pages["grand"].is_ancestor_of(m._net_line), "the server line is on the Grand Campaign page")
	for nm in ["home_Online_co-op", "grand_join", "grand_join_code", "grand_join_paste", "home_server", "host_pack_west", "host_pack_rome", "host_server_change"]:
		_check(_btn(nm) != null and _btn(nm).is_visible_in_tree() or (nm == "grand_join_code" and m._gj_edit.is_visible_in_tree()), "%s is on the Grand Campaign page" % nm)
	_check(m._grand_cards.get_child_count() == 2 and not m._grand_cards.vertical, "the Host and Join cards sit side by side")
	_check(m.find_child("online_empty", true, false) != null or net == null, "no campaigns: the empty line shows (the Host card is the call to action)")
	_check(m._net_line.text.begins_with("Server: "), "the server line reads 'Server: <host> - state' (%s)" % m._net_line.text)
	for k in 60:
		if net == null or m._net_line.text.contains("not reachable"):
			break
		await create_timer(0.25).timeout
	_check(net == null or m._net_line.text.contains("not reachable"), "an unreachable server shows '- not reachable' (%s)" % m._net_line.text)
	_check(net == null or m._srv_label.text.begins_with("Game server: 127.0.0.1:8074"), "the Game server row names the address (%s)" % m._srv_label.text)
	await _shot("grand_empty")
	# The Join card validates the code locally and says what is wrong.
	m._gj_edit.text = "ab"
	m._gj_edit.text_changed.emit("ab")
	_check(m._gj_edit.text == "AB", "the code is uppercase as typed")
	await _press("grand_join")
	_check(m._gj_info.text.contains("6 characters") and m._gj_info.text.contains("8"), "a short code shows the hint under the field (%s)" % m._gj_info.text)
	_check(Kit.tip_of(m._gj_edit)[1].contains("6 characters"), "and the field's tip carries it")
	await _shot("grand_join_error")
	# Host card: the setting then Host opens the faction page online for it.
	for pk in ["rome", "west"]:
		await _press("host_pack_" + pk)
		_check(m._gh_pack == pk and bool(_btn("host_pack_" + pk).get_meta("on")), "the %s mini-card is lit" % pk)
		await _press("home_Online_co-op")
		_check(m._new_campaign != null and m._new_campaign.online and m._new_campaign.pack_pick == pk, "Host opens the online faction page for %s" % pk)
		_check(m._new_campaign.find_child("nc_title", true, false).text == "New grand campaign", "... titled New grand campaign")
		if pk == "west":
			await _shot("faction_west_online")
			await _scroll_shot(m._new_campaign, "faction_west_online_bottom", 100000)
		m._new_campaign.back.emit()
		await _frames(3)
		_check(m.page == "grand" and m._menu.visible, "... and Back returns to Grand Campaign")
	await _press("home_server")
	_check(m.page == "server", "Game server opens its page")
	m._back_btn.pressed.emit()
	_check(m.page == "grand", "Back from Game server returns to Grand Campaign")
	await _press("host_server_change")
	_check(m.page == "server", "the Host card's Change opens the server page too")
	m._back_btn.pressed.emit()
	m.show_page("join")
	_check(m.page == "join" and m._join_edit != null, "the separate join page is still reachable")
	m._back_btn.pressed.emit()
	# Your grand campaigns: rows from a stub seat store.
	if net != null:
		net.accounts.add("stubw", 2, "tok", "Port Royal run", "west", "http://127.0.0.1:8074")
		net.accounts.add("stubr", 0, "tok", "Senate game", "rome", "http://127.0.0.1:8074")
		m.show_page("grand")
		await _frames(4)
		for cid in ["stubw", "stubr"]:
			var row := m.find_child("grow_" + cid, true, false) as Control
			_check(row != null, "a row for the %s seat" % cid)
			_check(m.find_child("online_" + cid, true, false) != null and m.find_child("forget_" + cid, true, false) != null, "... with Resume and a forget x")
			_check(row != null and row.find_child("badge", true, false) != null and row.find_child("turn", true, false) != null, "... a badge and the turn")
			_check(row != null and (row.find_child("faction", true, false) as Label).text != "", "... and the faction (%s)" % ((row.find_child("faction", true, false) as Label).text if row != null else ""))
		_check((m.find_child("grow_stubw", true, false).find_child("faction", true, false) as Label).text == "England", "the West seat names England")
		_check(CData.pack == "rome", "reading the seats puts the content pack back")
		_check(m.find_child("online_empty", true, false) == null, "the empty line is gone")
		var fg := m.find_child("forget_stubr", true, false) as Button
		fg.pressed.emit()
		_check(fg.text == "Sure?" and net.accounts.get_entry("stubr").size() > 0, "x asks first")
		fg.pressed.emit()
		await _frames(2)
		_check(net.accounts.get_entry("stubr").is_empty(), "the second press forgets it")
		await _shot("grand_campaigns")
		net.accounts.data["campaigns"] = {}
		net.accounts.save()
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://menu_test/accounts.json"))
		net.accounts = keep_accounts
		net.api.base_url = keep_base


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
	var size0 := UiScale.size_name()
	m.show_page("options")
	await _frames(3)
	await _shot("options")
	_check(_btn("home_tests") == null, "no Tests and benchmarks without --dev")
	_check(not m._tests_button.visible, "the sandbox page hides its Tests button without --dev")
	var rows = m._opts
	_check(rows != null and rows.find_row_count() >= 11, "Options is rows (%d settings)" % (rows.find_row_count() if rows != null else 0))
	# Every capsule sets its stored value.
	var stored := {
		"ui_size": func(): return UiScale.size_name(),
		"quality": func(): return Quality.load_pref(),
		"soldiers": func(): return SoldierLayer.load_pref(),
		"battle_look": func(): return BattleLook.pref(),
		"map_style": func(): return MapView.style_pref,
		"menu_bg": func(): return MenuPrefs.stored_background(),
		"menu_emblems": func(): return MenuPrefs.stored_emblems(),
	}
	for key in stored:
		var sg = rows.seg.get(key)
		_check(sg != null and sg.name == "home_" + key, "Options has the %s capsule" % key)
		if sg == null:
			continue
		var all_ok := true
		for v in sg.values:
			sg.button_for(v).pressed.emit()
			await _frames(1)
			if str((stored[key] as Callable).call()) != str(v) or sg.value != v:
				all_ok = false
				printerr("   %s: picked %s, stored %s" % [key, str(v), str((stored[key] as Callable).call())])
		_check(all_ok, "%s: each choice sets the stored value (%s)" % [key, ", ".join(sg.values.map(func(x): return str(x)))])
	UiScale.set_size_name(root, size0)
	# Fullscreen is a toggle (the window mode is not touched here), Sound and the sliders reach the audio settings.
	_check(rows.seg.has("fullscreen") and rows.seg.has("audio_mute") and _btn("home_controls") != null and _btn("home_unit_book") != null, "Options has Fullscreen, Sound, Controls and Unit book")
	var a = AudioFx.inst()
	if a != null:
		var vol0: Dictionary = a.vol.duplicate()
		var muted0: bool = a.muted
		for k in ["master", "effects", "ambient"]:
			var sl: HSlider = rows.sliders[k]
			_check(sl != null and sl.name == "audio_" + k and sl.max_value == 100, "a 0-100 slider for %s" % k)
			sl.value = 35
			_check(int(a.vol[k]) == 35, "the %s slider sets the volume (%d)" % [k, int(a.vol[k])])
		rows.seg["audio_mute"].button_for(0).pressed.emit()
		_check(a.muted, "Sound off mutes")
		rows.seg["audio_mute"].button_for(1).pressed.emit()
		_check(not a.muted, "Sound on unmutes")
		for k in vol0:
			a.set_volume(k, int(vol0[k]))
		a.set_muted(muted0)
	# every capsule has a boxed tip
	var untipped := 0
	for key in rows.seg:
		for b in (rows.seg[key] as Kit.Segmented).buttons():
			if Kit.tip_of(b).is_empty() or str(Kit.tip_of(b)[0]) == "":
				untipped += 1
	_check(untipped == 0, "every Options control has a titled tip (%d without)" % untipped)
	# the two menu settings reach the config file
	MenuPrefs.set_background("diorama")
	MenuPrefs.set_emblems("painted")
	_check(MenuPrefs.stored_background() == "diorama" and MenuPrefs.stored_emblems() == "painted", "the menu settings are kept in [menu]")
	rows.refresh()
	_check(rows.seg["menu_bg"].value == "diorama" and rows.seg["menu_emblems"].value == "painted", "refresh shows them")
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


# --------------------------------------------------------- tooltips ---

func _tooltips() -> void:
	# The box: title in the display face over a wrapped body, 320 px at most.
	var b := Kit.button("Tipped", Callable())
	Kit.tip(b, "Fog of war", "On: you see your regions and their neighbours, and what your armies, fleets and cities can see; the rest shows as last known. Off: everything is visible.")
	var box := b._make_custom_tooltip(b.tooltip_text) as Control
	root.add_child(box)
	await _frames(2)
	var title := box.find_child("tip_title", true, false) as Label
	var body := box.find_child("tip_body", true, false) as Label
	_check(title != null and title.text == "Fog of war" and body != null and body.text.begins_with("On:"), "a tipped kit button builds a title and a body")
	_check(title.has_theme_font_override("font") == (Kit.title_font() != null) and title.get_theme_font_size("font_size") == 16 and body.get_theme_font_size("font_size") == 14, "title 16 (display face), body 14")
	_check(box.size.x <= 320.5 and box.size.x >= 200.0 and body.get_line_count() >= 3, "wrapped within 320 px (%.0f wide, %d lines)" % [box.size.x, body.get_line_count()])
	_check(box.get_theme_stylebox("panel") is Kit.TrimBox, "the plate is the trim box")
	await _shot_node("tooltip_box", box, Vector2(40, 40))
	box.queue_free()
	var plain := Kit.button("Plain", Callable())
	plain.tooltip_text = "Just a body"
	var pb := plain._make_custom_tooltip(plain.tooltip_text) as Control
	_check(pb.find_child("tip_title", true, false) == null and (pb.find_child("tip_body", true, false) as Label).text == "Just a body", "a plain tooltip_text on a kit button is boxed without a title")
	pb.free()
	_check(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5) <= 0.41, "the desktop delay is 0.4 s")
	# Touch: a long press shows the box above the finger until release; a short tap shows none.
	UiScale._touch_override = 1
	var host := root.get_node_or_null("KitTipHost")
	_check(host != null, "the touch tip host is installed")
	if host == null:
		UiScale._touch_override = 0
		return
	var pressed := [0]
	var tb := Kit.button("Hold me", func(): pressed[0] += 1)
	Kit.tip(tb, "Hold", "Long press to read this.")
	tb.position = Vector2(300, 300)
	tb.size = Vector2(160, 44)
	root.add_child(tb)
	await _frames(2)
	var finger := Vector2(380, 320)
	host.press(finger)
	await create_timer(0.2).timeout
	_check(host.box == null, "no box before the long press time")
	host.release()
	host.press(finger)
	await create_timer(0.65).timeout
	_check(host.box != null and host.target == tb, "a long press on a tipped control shows the box")
	if host.box != null:
		var r: Rect2 = (host.box as Control).get_global_rect()
		_check(r.end.y <= finger.y and r.position.x >= 0.0 and r.end.x <= root.get_visible_rect().size.x, "... above the finger and inside the screen")
		await _shot("tooltip_long_press")
	host.release()
	await _frames(1)
	_check(host.box == null or host.box.is_queued_for_deletion(), "lifting the finger removes it")
	_check(tb.disabled, "... and that release is swallowed (the button is off for it)")
	await _frames(4)
	_check(not tb.disabled and pressed[0] == 0, "then it is back on, and nothing was pressed")
	host.press(Vector2(50, 600))
	await create_timer(0.6).timeout
	_check(host.box == null, "a long press on nothing shows no box")
	host.release()
	tb.queue_free()
	UiScale._touch_override = 0


func _scroll_shot(nc: Control, name: String, y: int) -> void:
	for sc in nc.find_children("*", "ScrollContainer", true, false):
		(sc as ScrollContainer).scroll_vertical = y
	await _frames(3)
	await _shot(name)
	for sc in nc.find_children("*", "ScrollContainer", true, false):
		(sc as ScrollContainer).scroll_vertical = 0


func _shot_node(name: String, n: Control, at: Vector2) -> void:
	if _shots == "":
		return
	var bgc := ColorRect.new()
	bgc.color = Color(0.2, 0.25, 0.22)
	bgc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bgc)
	root.move_child(bgc, n.get_index())
	n.position = at
	await _frames(3)
	var img := root.get_viewport().get_texture().get_image()
	var r := Rect2i(Vector2i(at) - Vector2i(20, 20), Vector2i(n.size) + Vector2i(40, 40))
	img.get_region(r).save_png("%s/%s.png" % [_shots, name])
	bgc.queue_free()


# ----------------------------------------------------------- faction page ---

## The faction page: blurbs wrapped inside their rows (never clipped), Start off with a tip until a human is picked.
func _faction_checks(nc: Control, key: String) -> void:
	await _frames(3)
	var clipped := 0
	var rows := 0
	for r in nc.find_children("row_*", "PanelContainer", true, false):
		rows += 1
		var bl := r.find_child("blurb_*", true, false) as Label
		if bl == null:
			continue
		var font := bl.get_theme_font("font")
		var fh := font.get_height(bl.get_theme_font_size("font_size"))
		if bl.get_line_count() < 1 or bl.size.y + 0.5 < bl.get_line_count() * fh or not (r as Control).get_global_rect().grow(0.5).encloses(bl.get_global_rect()):
			clipped += 1
	_check(rows == CData.faction_count() and clipped == 0, "the faction rows hold their whole blurbs (%d rows, %d clipped)" % [rows, clipped])
	var st := nc.find_child("start_campaign", true, false) as Button
	_check(st != null and st.disabled and str(Kit.tip_of(st)[1]).contains("Switch at least one faction"), "Start is off with the reason as its tip until a human is picked")
	var who := nc.find_child("faction_" + key, true, false) as Button
	who.pressed.emit()
	await _frames(2)
	_check(not st.disabled and who.text == "You", "picking a human turns Start on (and marks you)")
	var row := nc.find_child("row_" + key, true, false) as PanelContainer
	var sb := row.get_theme_stylebox("panel") as StyleBoxFlat
	_check(sb != null and sb.border_width_left == 3 and sb.border_color == Kit.COL_GOLD, "a human row has the gold left edge")
	nc.find_child("ai_" + key, true, false).pressed.emit()
	await _frames(2)
	_check(st.disabled, "back to AI: Start is off again")
	for nm in ["campaign_name", "campaign_seed", "seed_dice", "turn_timeout_h_24", "autoresolve_auto", "ai_aggression_130", "ai_battle_skill_2", "ai_campaign_skill_0", "fog_0", "step_victory_regions_plus", "step_victory_capitals_minus"]:
		_check(nc.find_child(nm, true, false) != null, "the Settings panel has %s" % nm)
	var s0: int = int(nc.settings["victory_regions"])
	nc.find_child("step_victory_regions_plus", true, false).pressed.emit()
	nc.find_child("turn_timeout_h_24", true, false).pressed.emit()
	nc.find_child("fog_0", true, false).pressed.emit()
	await _frames(1)
	_check(int(nc.settings["victory_regions"]) > s0 and int(nc.settings["turn_timeout_h"]) == 24 and int(nc.settings["fog"]) == 0, "the steppers and capsules set the settings")
	var seed0: String = nc.seed_edit.text
	nc.find_child("seed_dice", true, false).pressed.emit()
	_check(nc.seed_edit.text != "" and nc.seed_edit.text.is_valid_int(), "the dice rolls a seed (%s -> %s)" % [seed0, nc.seed_edit.text])


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
	m.show_page("grand")
	await _frames(3)
	_check(m._grand_cards.vertical, "phone: the Host and Join cards stack")
	await _shot("grand_phone")
	m.show_page("options")
	await _frames(3)
	await _shot("options_phone")
	# a long press on an Options capsule on the phone
	var host := root.get_node_or_null("KitTipHost")
	var qb: Button = m._opts.seg["quality"].button_for("low")
	if host != null and qb != null:
		var c := qb.get_global_rect().get_center()
		host.press(c)
		await create_timer(0.65).timeout
		_check(host.box != null and host.target == qb, "phone: a long press on a capsule shows its tip")
		await _shot("tooltip_long_press_phone")
		host.release()
		await _frames(4)
	m.show_page("campaign")
	await _frames(2)
	for pk in ["west", "rome"]:
		await _press("card_" + pk)
		var nc: Control = m._new_campaign
		await _frames(4)
		_check(nc.find_child("settings_fold", true, false) != null and not nc.find_child("settings_body", true, false).visible, "phone: the Settings panel is folded under a Settings header (%s)" % pk)
		var wide := 0
		for r in nc.find_children("row_*", "PanelContainer", true, false):
			if (r as Control).get_global_rect().end.x > vp.x + 0.5:
				wide += 1
		_check(wide == 0, "phone: the faction rows fit the width (%s)" % pk)
		await _faction_checks(nc, "england" if pk == "west" else "rome")
		await _shot("faction_%s_phone" % pk)
		nc.find_child("settings_fold", true, false).pressed.emit()
		await _frames(3)
		_check(nc.find_child("settings_body", true, false).visible, "phone: the fold opens")
		if pk == "west":
			await _scroll_shot(nc, "faction_west_phone_settings", 100000)
			await _scroll_shot(nc, "faction_west_phone_rows", 560)
		nc.back.emit()
		await _frames(3)
	m.show_page("home")
	UiScale._dpr_override = 1.0
	UiScale._touch_override = 0
	DisplayServer.window_set_size(old)
	await _frames(6)
	UiScale.apply(root)
	await _frames(3)
