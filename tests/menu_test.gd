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
const TableMotion := preload("res://game/table_motion.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const CStory := preload("res://campaign/cstory.gd")
const Accounts := preload("res://game/net/accounts.gd")
const SoldierLayer := preload("res://game/soldier_layer.gd")
const BattleLook := preload("res://game/battle_look.gd")
const ConfirmOrders := preload("res://game/confirm_orders.gd")
const Controls := preload("res://game/controls.gd")
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
	if DisplayServer.get_name() == "headless":
		# headless has no real window and starts at 640x640: size the root to the desktop window the checks assume
		# (the same trick as campaign_input_test's phone steps), so the layout checks measure the intended size
		root.size = Vector2i(1280, 720)
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
	await _options_fit()
	await _howto_fit()
	await _tooltips()
	await _emblems()
	await _backgrounds()
	await _unit_book_names()
	await _phone()
	_wipe_saves()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://campaigns/menu_test"))
	m.queue_free()
	await _frames(3)
	_restore_settings()
	_check(_errs.n == 0, "no script errors logged during the run (%d: %s)" % [_errs.n, _errs.first])
	print("RESULT ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures > 0 else 0)


# The unit book under per-faction unit names (west.gd UNIT_NAMES): a faction's list shows its names.
func _unit_book_names() -> void:
	var UB := preload("res://game/unit_book.gd")
	var UTm := preload("res://sim/unit_types.gd")
	PackView.use_pack("west")
	var bk: Control = UB.new()
	root.add_child(bk)
	bk.open()
	await _frames(2)
	var mis := CData.faction_index("miskito")
	var itz := CData.faction_index("itza")
	_check(bk.faction_pick.visible and bk.faction_pick.item_count >= 4, "unit book (west): a faction picker lists the factions with names")
	var all: Array = bk.names_for(-1)
	_check(all.has("Warriors") and all.has("Musketeers") and all.has("Chieftain's Guard"), "unit book (west): all factions list the row names")
	var wt := UTm.index_of("native_warriors")
	_check(bk.variants_text(wt) == "Itza Warriors, Miskito Warriors" and bk._subs[wt].visible, "unit book (west): a shared row lists each faction's name in small text (%s)" % bk.variants_text(wt))
	bk.open(-1, mis)
	await _frames(2)
	var mn: Array = bk.names_for(mis)
	_check(mn.has("Miskito Musketmen") and mn.has("King's Guard") and mn.has("Miskito Warriors"), "unit book (west): the Miskito list has Miskito Musketmen, King's Guard, Miskito Warriors")
	_check(str(bk._list[UTm.index_of("musketeers")].text).strip_edges() == "Miskito Musketmen", "unit book (west): the Miskito list's button reads Miskito Musketmen")
	bk.show_type(UTm.index_of("chieftain"))
	_check(bk.entry._name.text == "King's Guard", "unit book (west): the Miskito unit page is named King's Guard (%s)" % bk.entry._name.text)
	bk.open(-1, itz)
	_check(bk.names_for(itz).has("Batab's Guard") and not bk.names_for(itz).has("Miskito Musketmen"), "unit book (west): the Itza list has Batab's Guard")
	bk.queue_free()
	PackView.use_pack("rome")
	var rb: Control = UB.new()
	root.add_child(rb)
	rb.open()
	await _frames(2)
	var wr := UTm.index_of("heavy")
	var st := UTm.index_of("stone")
	_check(rb.faction_pick.visible and rb.names_for(-1).has(str(UTm.TYPES[wr]["name"])) and rb.variants_text(wr) == "" and str(rb._list[wr].text).strip_edges() == str(UTm.TYPES[wr]["name"])
		and rb.variants_text(st).contains("Archimedean Engines"),
		"unit book (rome, 2026-11-07): the faction picker shows (the Rome specials' names), a plain row keeps its name, the stone throwers list Archimedean Engines")
	rb.queue_free()
	await _frames(2)


# ------------------------------------------------------------ entries ---

func _entries() -> void:
	_check(m.page == "home", "starts on the title screen")
	for nm in ["home_campaign", "home_grand", "home_battles", "home_howto", "home_options"]:
		_check(_visible_in_page(_btn(nm)), "%s is on the title screen" % nm)
	_check(not _visible_in_page(_btn("home_continue")), "Continue is hidden with no saves")
	_check(m._net_line == null or not m._home.is_ancestor_of(m._net_line), "the title screen has no server line")
	_check(m._back_btn != null and not m._back_btn.visible, "no Back on the title screen")
	await _shot_title("title_start")
	for pair in [["home_campaign", "campaign"], ["home_grand", "grand"], ["home_battles", "battles"], ["home_howto", "howto"], ["home_options", "options"]]:
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
	var sst := CStory.new_story("Tale", 10, {}, "brethren", false)
	Saves.save(Saves.slot_for("Tale", 10), {"state": sst, "session": {"subs": [], "plans": {}, "seen": {}}})
	PackView.use_pack("rome")
	_save("Older", 11, "rome", 3)
	await create_timer(1.1).timeout   # (saved_at is in seconds)
	_save("Newest", 12, "west", 6)
	m.show_page("home")
	await _frames(3)
	var holder: Control = _btn("home_continue").get_parent()
	_check(holder.visible, "Continue shows with a save")
	_check(_btn("home_continue").text == "Continue: Newest, turn 7", "Continue names the most recent save (%s)" % _btn("home_continue").text)
	_check((m._continue_emblem as Emblem).pack == "west", "Continue carries the save's setting emblem")
	_check((m._home_emblem as Emblem).pack == MenuPrefs.pack_of(m._bg_choice) and m._bg_choice == "diorama_rome", "the wordmark's emblem follows the selected background (rome), not the last-played save")
	await _shot_title("title_continue")
	m.page = "home"
	_btn("home_continue").pressed.emit()
	await _frames(30)
	_check(m.campaign != null and str(m.campaign.st["name"]) == "Newest", "Continue opens that campaign")
	m._close_campaign()
	await _frames(4)
	_check(m.page == "home" and m._menu.visible, "closing the campaign returns to the title screen")


# ----------------------------------------------------------- campaign ---

## Every descendant of the three Story Campaign cards lies inside its card's rect (the tutorial card once sprawled out).
func _cards_inside(tag: String) -> void:
	for nm in ["card_tutorial", "card_native", "card_story"]:
		var card := _btn(nm)
		var r := card.get_global_rect().grow(0.5)
		var bad := 0
		for c in card.find_children("*", "Control", true, false):
			if (c as Control).is_visible_in_tree() and not r.encloses((c as Control).get_global_rect()):
				bad += 1
		_check(bad == 0, "%s: everything in %s lies inside its card (%d outside)" % [tag, nm, bad])


func _campaign_page() -> void:
	m.show_page("campaign")
	await _frames(3)
	var rows := 0
	for c in m._continue_box.get_children():
		if c is HBoxContainer:
			rows += 1
	_check(rows == 1, "Your story campaigns lists only the story save (%d)" % rows)
	var story_txt := ""
	for c in m._continue_box.find_children("*", "Button", true, false):
		story_txt += (c as Button).text
	_check(story_txt.contains("Tale") and not story_txt.contains("Older") and not story_txt.contains("Newest"), "... a story save on the Story Campaign page and no Grand Campaign save (%s)" % story_txt)
	_check(m._entries.size() > 0 and str(_btn("home_campaign").text) == "Story Campaign", "the title entry reads Story Campaign (%s)" % _btn("home_campaign").text)
	var ncards := 0
	for c in m._pages["campaign"].find_children("card_*", "Button", true, false):
		ncards += 1
	_check(ncards == 3 and _btn("card_story") != null and _btn("card_tutorial") != null and _btn("card_native") != null, "the Campaign page has three cards, Your first command, The native way and the story (%d)" % ncards)
	_check(_btn("card_west") == null and _btn("card_rome") == null, "... no setting cards (Rome is the Grand Campaign's)")
	_check(_btn("home_Import") != null, "Import is on the Campaign page")
	_cards_inside("story page")
	await _shot("campaign_page")
	await _press("card_story")
	var nc: Control = m._new_campaign
	_check(nc != null and nc.story_only and not nc.online and CData.pack == "west", "the story card opens the story setup on the West setting")
	_check(nc.find_children("row_*", "PanelContainer", true, false).is_empty() and nc.find_children("faction_*", "Button", true, false).is_empty(), "... without faction rows")
	_check(nc.find_child("pack_west", true, false) == null and nc.find_child("pack_rome", true, false) == null, "... without the Setting row")
	_check(nc.find_child("all_one_team", true, false) == null or not (nc.find_child("all_one_team", true, false) as Control).is_visible_in_tree(), "... without the team buttons")
	for nm in ["story_brethren", "story_brethren_coop", "campaign_name", "campaign_seed", "start_campaign", "ai_battle_skill_2", "autoresolve_auto", "deploy_time", "time_limit"]:
		_check(nc.find_child(nm, true, false) != null, "the story setup has %s" % nm)
	_check(nc.find_child("step_victory_regions_plus", true, false) == null, "... and no victory settings (the story has its own ending)")
	_check(not (nc.find_child("start_campaign", true, false) as Button).disabled, "Start is on (it plays the story)")
	await _shot("story_setup")
	nc.back.emit()
	await _frames(3)
	_check(m._new_campaign == null and m._menu.visible and m.page == "campaign", "Back from the story setup returns to Campaign")
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
	for nm in ["home_Online_co-op", "grand_join", "grand_join_code", "grand_join_paste", "home_server", "host_pack_west", "host_pack_rome"]:
		_check(_btn(nm) != null and _btn(nm).is_visible_in_tree() or (nm == "grand_join_code" and m._gj_edit.is_visible_in_tree()), "%s is on the Grand Campaign page" % nm)
	_check(m._grand_cards.get_child_count() == 2 and not m._grand_cards.vertical, "the Host and Join panels sit side by side")
	_check(m.find_child("offline_card", true, false) == null and _btn("offline_pack_west") == null and _btn("home_offline") != null and m.find_child("host_card", true, false).is_ancestor_of(_btn("home_offline")), "Play offline is a button inside the Host panel (one pack row)")
	_check(_btn("home_offline").get_global_rect().position.y > _btn("home_Online_co-op").get_global_rect().end.y - 1.0 and absf(_btn("home_offline").size.x - _btn("home_Online_co-op").size.x) < 2.0, "... under Host, the same width")
	var grand_rows := 0
	var grand_txt := ""
	for c in m._grand_saves_box.get_children():
		if c is HBoxContainer:
			grand_rows += 1
	for c in m._grand_saves_box.find_children("*", "Button", true, false):
		grand_txt += (c as Button).text
	_check(grand_rows == 2 and grand_txt.contains("Older") and grand_txt.contains("Newest") and not grand_txt.contains("Tale"), "Your Grand Campaigns lists the two offline saves and not the story save (%d: %s)" % [grand_rows, grand_txt])
	_check(m.find_child("online_empty", true, false) == null, "offline saves present: no 'none yet' line")
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
		var hn: Control = m._new_campaign
		_check(CData.pack == pk and hn.find_child("row_" + ("brethren" if pk == "west" else "rome"), true, false) != null, "... on the %s setting, with its faction rows" % pk)
		_check(hn.find_child("pack_west", true, false) == null and not hn.story_only, "... without the Setting row, not the story setup")
		_check((hn.find_child("story_brethren_online", true, false) != null) == (pk == "west"), "... the online story card only on the West setting")
		var hfold := hn.find_child("settings_fold", true, false) as Button
		_check(hfold != null and hfold.text.contains("Campaign Settings") and not hn.find_child("settings_body", true, false).visible, "... the Campaign Settings section is folded by default (%s)" % (hfold.text if hfold != null else "none"))
		_check(hfold.text.contains("AI") and hfold.text.contains("min battles") and hfold.text.contains("fog"), "... its header summarises the choices")
		_check((hn.find_child("campaign_name", true, false) as Control).is_visible_in_tree() and (hn.find_child("campaign_seed", true, false) as Control).is_visible_in_tree(), "... Name and Seed stay visible above the fold")
		_check(not (hn.find_child("time_limit", true, false) as Control).is_visible_in_tree(), "... the other settings are hidden")
		hfold.pressed.emit()
		await _frames(2)
		_check((hn.find_child("time_limit", true, false) as Control).is_visible_in_tree() and hfold.text.begins_with("v"), "... the chevron opens it")
		hfold.pressed.emit()
		await _frames(2)
		_check(not hn.find_child("settings_body", true, false).visible, "... and folds it again")
		# Hosting: two humans picked, the state the Host path creates (the server call itself needs a server).
		var f1 := CData.faction_index("rome" if pk == "rome" else "england")
		var f2 := CData.faction_index("carthage" if pk == "rome" else "france")
		hn._pick(f1)
		await _frames(2)
		_check(not (hn.find_child("start_campaign", true, false) as Button).disabled, "... one human enables Start (a solo campaign on the server)")
		hn._pick(f2)
		var hst: Dictionary = hn.build_state("HostTest", 7)
		_check(CData.pack == pk and str(hst.get("pack", "rome")) == pk and (hst["humans"] as Array).size() == 2 and (hst["humans"] as Array).has(f1), "... Host creates a %s campaign (CData.pack %s, state pack %s, humans %s)" % [pk, CData.pack, hst.get("pack", "(none)"), hst["humans"]])
		if pk == "west":
			await _shot("faction_west_online")
			await _scroll_shot(m._new_campaign, "faction_west_online_bottom", 100000)
		m._new_campaign.back.emit()
		await _frames(3)
		_check(m.page == "grand" and m._menu.visible, "... and Back returns to Grand Campaign")
	# Play offline: the faction page, offline, local save; the one pack pick serves it as it does Host.
	for pk in ["rome", "west", "rome"]:
		await _press("host_pack_" + pk)
		_check(m._gh_pack == pk and bool(_btn("host_pack_" + pk).get_meta("on")), "the %s mini-card is lit before Play offline" % pk)
		await _press("home_offline")
		var on_: Control = m._new_campaign
		_check(on_ != null and not on_.online and not on_.story_only and on_.pack_pick == pk, "Play offline opens the offline faction page for %s" % pk)
		_check(on_.find_child("row_" + ("brethren" if pk == "west" else "rome"), true, false) != null and on_.find_child("online_panel", true, false) == null, "... with faction rows (%s's) and no online fields" % pk)
		_check(on_.find_child("row_" + ("rome" if pk == "west" else "brethren"), true, false) == null, "... and none of the other setting's")
		var of1 := CData.faction_index("rome" if pk == "rome" else "england")
		on_._pick(of1)
		await _frames(2)
		_check(not (on_.find_child("start_campaign", true, false) as Button).disabled, "... one human enables Start")
		var ost: Dictionary = on_.build_state("OfflineTest", 7)
		_check(CData.pack == pk and str(ost.get("pack", "rome")) == pk and (ost["humans"] as Array).has(of1), "... build_state gives a %s state (CData.pack %s)" % [pk, CData.pack])
		_check(on_.find_child("settings_fold", true, false) != null and not on_.find_child("settings_body", true, false).visible, "... the Campaign Settings section is folded (%s)" % pk)
		on_.back.emit()
		await _frames(3)
	# The title's background as the live table, then Rome (the owner's report: Rome showed the Western armies).
	MenuPrefs.bg_override = "diorama_west"   # (a test run builds no table unless it asks)
	m._bg.switch_to("diorama_west")
	await _frames(3)
	m.show_page("grand")
	for how in ["host", "offline"]:
		await _press("host_pack_rome")
		await _press("home_Online_co-op" if how == "host" else "home_offline")
		var lt: Control = m._new_campaign
		_check(lt != null and lt.pack_pick == "rome" and CData.pack == "rome" and lt.find_child("row_rome", true, false) != null and lt.find_child("row_brethren", true, false) == null, "live table background, %s: Rome's rows and CData.pack rome" % how)
		lt._pick(CData.faction_index("rome"))
		_check(str(lt.build_state("LiveTest", 5).get("pack", "rome")) == "rome", "... build_state carries the rome pack (%s)" % how)
		lt.back.emit()
		await _frames(3)
	_check(m._bg.diorama == null or CData.pack == "west" or CData.pack == "rome", "the live table leaves a known pack set")
	MenuPrefs.bg_override = ""
	m._bg.deactivate()   # (the live table sets the global pack while it builds; drop it for the steps below)
	await _frames(3)
	PackView.use_pack("rome")
	# Back from a West campaign (the last pack is west), then Rome.
	m.show_page("home")
	_save("WestRun", 21, "west", 2)
	m._recent = m._find_recent()
	_check(m._last_pack() == "west", "after a West save the menu's last pack is west (%s)" % m._last_pack())
	m.show_page("grand")
	for how in ["host", "offline"]:
		await _press("host_pack_rome")
		await _press("home_Online_co-op" if how == "host" else "home_offline")
		var wl: Control = m._new_campaign
		_check(wl != null and CData.pack == "rome" and wl.find_child("row_rome", true, false) != null and wl.find_child("row_brethren", true, false) == null, "after a West campaign, Rome picked, %s: Rome's rows" % how)
		wl._pick(CData.faction_index("rome"))
		_check(str(wl.build_state("WestThenRome", 6).get("pack", "rome")) == "rome", "... build_state carries the rome pack (%s)" % how)
		wl.back.emit()
		await _frames(3)
	_check(CData.pack == "rome", "listing saves (a West one among them) leaves the global pack alone (%s)" % CData.pack)
	await _press("home_server")
	_check(m.page == "server", "Game server opens its page")
	m._back_btn.pressed.emit()
	_check(m.page == "grand", "Back from Game server returns to Grand Campaign")
	_check(_btn("host_server_change") == null, "the Host card has no second Change button (one Game server row, 2026-10-23)")
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


# ------------------------------------------------------------ how to play ---

## The How to play page (game/campaign/howto_page.gd) at phone sizes: the panel fits the width, all ten sections are
## there and the last line can be scrolled into view (the page scrolls; it is long).
func _howto_fit() -> void:
	var size0 := UiScale.size_name()
	var old := DisplayServer.window_get_size()
	for sz in [Vector2i(886, 409), Vector2i(844, 390), Vector2i(1280, 720)]:
		DisplayServer.window_set_size(sz)
		root.size = sz
		await _frames(10)
		await _new_menu()
		m.show_page("howto")
		await _frames(8)
		var tag := "%dx%d" % [sz.x, sz.y]
		var panel: Control = m.find_child("howto_panel", true, false)
		var vp := m.get_viewport_rect().size
		_check(panel != null and panel.is_visible_in_tree() and panel.get_global_rect().position.x >= -0.5 and panel.get_global_rect().end.x <= vp.x + 0.5,
			"How to play fits the width at %s (panel %s of %s)" % [tag, str(panel.get_global_rect()) if panel != null else "-", str(vp)])
		var heads := 0
		for sec in preload("res://game/campaign/howto.gd").SECTIONS:
			if m.find_child("howto_h_" + str(sec["id"]), true, false) != null:
				heads += 1
		_check(heads == 10, "%s: the ten sections are there" % tag)
		var last: Control = m.find_child("howto_ways_3", true, false)
		var scroll: ScrollContainer = null
		var p := panel.get_parent()
		while p != null and scroll == null:
			if p is ScrollContainer:
				scroll = p
			p = p.get_parent()
		_check(scroll != null and last != null, "%s: the page scrolls" % tag)
		if scroll != null and last != null:
			scroll.ensure_control_visible(last)
			await _frames(3)
			var r := last.get_global_rect()
			_check(r.end.y <= scroll.get_global_rect().end.y + 1.0 and r.size.x <= vp.x, "%s: the last line scrolls into view" % tag)
		if sz.x == 886:
			await _shot("howto_886x409")
	DisplayServer.window_set_size(old)
	root.size = old
	await _frames(10)
	UiScale.set_size_name(root, size0)
	await _frames(4)
	await _new_menu()


# ------------------------------------------------------------ options ---

## The Options page needs no scroll at 1024x576 with UI size M (tighter rows, sliders side by side, descriptions
## dropped when short of room); a roomy window keeps the full page; 844x390 and 1280x720 L still work (the page may
## scroll on the phone and at L on a 720p window since L became 1.4, 2026-10-25; every row and button is there).
func _options_fit() -> void:
	var size0 := UiScale.size_name()
	var old := DisplayServer.window_get_size()
	var fits := func() -> bool:
		var box: Control = m._options_box
		var scroll: Control = box.get_parent().get_parent()
		return box.get_combined_minimum_size().y <= scroll.size.y + 0.5
	for case in [[Vector2i(1024, 576), "M", true], [Vector2i(1280, 720), "L", false], [Vector2i(1280, 720), "M", true], [Vector2i(844, 390), "M", false]]:
		DisplayServer.window_set_size(case[0])
		root.size = case[0]
		await _frames(10)
		UiScale.set_size_name(root, str(case[1]))
		await _frames(4)
		await _new_menu()
		m.show_page("options")
		await _frames(8)
		var rows = m._opts
		var tag := "%dx%d %s" % [case[0].x, case[0].y, case[1]]
		if bool(case[2]):
			_check(fits.call(), "Options needs no scroll at %s (viewport %s, fit level %d, need %d have %d)" % [tag, str(m.get_viewport_rect().size), rows.level, int(m._options_box.get_combined_minimum_size().y), int(m._options_box.get_parent().get_parent().size.y)])
		else:
			_check(rows.level >= 0, "Options builds at %s (fit level %d)" % [tag, rows.level])
		_check(rows.seg.size() >= 8 and rows.sliders.size() == 3 and _btn("home_controls") != null and _btn("home_unit_book") != null,
			"%s: every setting, the three sliders and the Help buttons are there" % tag)
		var sl: HSlider = rows.sliders["master"]
		_check(sl.is_visible_in_tree() and sl.get_global_rect().size.x > 40.0, "%s: the Master slider is shown and usable" % tag)
		if str(case[1]) == "M" and case[0].x == 1024:
			_check((rows.descs["quality"] as Label).visible == (rows.level < 3), "1024x576 M: the description lines go only when the page is short of room")
			await _shot("options_1024x576_M")
	DisplayServer.window_set_size(old)
	root.size = old
	await _frames(10)
	UiScale.set_size_name(root, size0)
	await _frames(4)
	await _new_menu()

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
		"battle_dive": func(): return "on" if TableMotion.enabled() else "off",
		"confirm_orders": func(): return ConfirmOrders.pref(),
		"map_view": func(): return "terrain" if MapView.terrain_view else "political",
		"map_style": func(): return MapView.style_pref,
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
	# Stage B (2026-11-09): the 3D view is the only battle view, so Options has no Battle view or Crest ghost row; an old saved
	# [video] battle_view reads as 3d; Table motion stays beside Battle look.
	var BV := preload("res://game/board_view.gd")
	_check(not rows.seg.has("battle_view") and not rows.seg.has("crest_ghost"), "Options: no Battle view and no Crest ghost row")
	_check(rows.seg["battle_dive"].get_parent().get_parent() == rows.seg["battle_look"].get_parent().get_parent(), "Options: Table motion sits beside Battle look")
	var cfv := ConfigFile.new()
	cfv.load("user://settings.cfg")
	var bv0 = cfv.get_value("video", "battle_view", null)
	for old in ["top", "oblique", "3d"]:
		cfv.set_value("video", "battle_view", old)
		cfv.save("user://settings.cfg")
		_check(BV.pref() == "3d", "an old saved battle_view '%s' reads as 3d" % old)
	cfv.set_value("video", "battle_view", bv0)
	cfv.save("user://settings.cfg")
	BV.force = "top"
	_check(BV.pref() == "top", "the developer aid (BoardView.force) still picks a flat view")
	BV.force = ""
	# Confirm orders shares the UI size row (one capsule beside the other, so the page keeps its height); the stored value is
	# [ui] confirm_orders, "auto" with nothing stored; the Controls page lists the placement tool.
	var cs_row = rows.seg.get("confirm_orders")
	_check(cs_row != null and cs_row.get_parent().get_parent() == rows.seg["ui_size"].get_parent().get_parent() and cs_row.values == ["auto", "on", "off"],
		"Options: Confirm orders is Auto / On / Off beside UI size")
	cs_row.button_for("on").pressed.emit()
	await _frames(1)
	var cf := ConfigFile.new()
	_check(cf.load("user://settings.cfg") == OK and str(cf.get_value("ui", "confirm_orders", "")) == "on", "Options: Confirm orders is kept in [ui] confirm_orders")
	cs_row.button_for("auto").pressed.emit()
	var ctl := Controls.new()
	root.add_child(ctl)
	ctl.open()
	await _frames(2)
	var found := false
	var ids := {}
	var dup := false
	for b in Controls.BINDINGS:
		dup = dup or ids.has(b["id"])
		ids[b["id"]] = true
	for l in ctl.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with("Placement tool") or (l as Label).text.contains("Drag the ghost's body handle"):
			found = true
	_check(ids.has("place_tool") and ids.has("stray_taps") and not dup and found, "the Controls page shows the placement tool and the stray-tap guards")
	ctl.queue_free()
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
	MenuPrefs.set_background("diorama_rome")
	MenuPrefs.set_emblems("painted")
	_check(MenuPrefs.stored_background("west") == "diorama_rome" and MenuPrefs.stored_emblems() == "painted", "the menu settings are kept in [menu]")
	rows.refresh()
	_check(rows.seg["menu_emblems"].value == "painted", "refresh shows them")
	_check(not rows.seg.has("menu_bg") and _btn("home_menu_bg_art") == null and m.find_child("home_menu_bg", true, false) == null, "Options has no Menu picture row (the title screen's selector replaced it)")
	MenuPrefs.set_background("diorama_rome")
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

func _wait_diorama() -> Node:
	var d = null
	for k in 900:
		await process_frame
		d = m._bg.diorama
		if d != null and is_instance_valid(d) and d.ready_flag:
			break
	return d


func _bg_state(c: String) -> void:
	var want_kind := MenuPrefs.kind(c)
	_check(m._bg_choice == c and m._bg.choice == c, "selector: the choice is %s" % c)
	_check(m._sel_label.text == str(MenuPrefs.LABELS[c]), "selector: the label reads \"%s\"" % MenuPrefs.LABELS[c])
	_check(MenuPrefs.stored_background("rome") == c, "selector: %s is saved" % c)
	_check(m._bg.mode == want_kind, "selector: the background is a %s" % want_kind)
	_check((m._home_emblem as Emblem).pack == MenuPrefs.pack_of(c) and m._subtitle.text == PackView.subtitle(MenuPrefs.pack_of(c)),
		"selector: the wordmark shows the %s emblem and subtitle" % MenuPrefs.pack_of(c))


func _backgrounds() -> void:
	# migration of the saved values (the retired art_<pack> -> the diorama of its setting; art / auto / junk and the old
	# diorama -> the diorama of the last-played setting)
	for pair in [["art", "diorama_west"], ["auto", "diorama_west"], ["diorama", "diorama_west"], ["art_west", "diorama_west"],
			["art_rome", "diorama_rome"], ["diorama_rome", "diorama_rome"], ["junk", "diorama_west"]]:
		MenuPrefs._cfg_set("background", pair[0])
		_check(MenuPrefs.stored_background("west") == pair[1], "migration: saved %s reads as %s" % [pair[0], pair[1]])
		MenuPrefs.migrate("west")
		_check(MenuPrefs.stored_background("west") == pair[1], "migration: %s is rewritten" % pair[0])
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.erase_section_key("menu", "background")
	cf.save(SETTINGS)
	_check(MenuPrefs.stored_background("west") == "diorama_west" and MenuPrefs.stored_background("rome") == "diorama_rome", "first run: the table of the last-played setting")
	_check(MenuPrefs.normalize("diorama", "rome") == "diorama_rome" and MenuPrefs.normalize("auto", "xyz") == "diorama_rome" and MenuPrefs.normalize("art_west", "rome") == "diorama_west", "old and retired values map onto the two")
	_check(MenuPrefs.BACKGROUNDS == ["diorama_west", "diorama_rome"], "MenuPrefs has the two choices")
	_check(MenuPrefs.PLACEHOLDER.has("west") and MenuPrefs.PLACEHOLDER.has("rome") and not ResourceLoader.exists("res://assets/ui/keyart/west.jpg"), "the placeholder gradients stand in; no key art file")
	# a test run that asked for nothing builds no table (the gradient shows); the selector is on the title page
	MenuPrefs.bg_override = ""
	PackView.use_pack("rome")
	m.show_page("home")
	m._activate_bg()
	await _frames(5)
	_check(m._bg.diorama == null and m._bg.mode == "diorama" and MenuPrefs.skip_live(), "no table is built in a test run that did not ask for one")
	_check(m._sel != null and m._sel.is_visible_in_tree() and m._sel_prev.custom_minimum_size.x == 44.0, "the selector shows on the title screen with 44 px arrows")
	var r: Rect2 = m._sel.get_global_rect()
	var vpw: float = m.get_viewport_rect().size.x
	_check(absf(r.get_center().x - vpw * 0.5) < 2.0 and r.end.y > m.get_viewport_rect().size.y - 90.0 and r.end.y <= m.get_viewport_rect().size.y,
		"the selector sits at the bottom centre (%s)" % str(r))
	m.show_page("campaign")
	await _frames(2)
	_check(not m._sel.is_visible_in_tree(), "the selector is on the title page only")
	m.show_page("home")
	await _frames(3)
	# step through both with the arrows (the setting saved in [menu]); the override is lifted so the saved value rules
	MenuPrefs.bg_override = "diorama_west"
	MenuPrefs.set_background("diorama_west")
	m._activate_bg()
	var d = await _wait_diorama()
	_check(d != null and d.ready_flag, "the Caribbean map-table diorama builds")
	_bg_state("diorama_west")
	_check(CData.pack == "west" and d.map_view.table_on(), "diorama_west: the west pack in the table style")
	print("  diorama_west built in %.0f ms" % d.build_ms)
	await _frames(30)
	await _shot_title("selector_1_diorama_west")
	m._sel_next.pressed.emit()
	d = await _wait_diorama()
	_check(d != null and d.ready_flag, "the Rome relief diorama builds")
	_bg_state("diorama_rome")
	_check(CData.pack == "rome" and not d.map_view.table_on(), "diorama_rome: the relief style, not the table")
	print("  diorama_rome built in %.0f ms" % d.build_ms)
	await _frames(30)
	await _shot_title("selector_2_diorama_rome")
	m._sel_next.pressed.emit()   # wraps to the first
	d = await _wait_diorama()
	_bg_state("diorama_west")
	_check(d != null and d.ready_flag and MapView.style_pref != "" , "the next arrow wraps to the first choice")
	m._sel_prev.pressed.emit()   # wraps back to the last
	d = await _wait_diorama()
	_bg_state("diorama_rome")
	_check(d != null and d.ready_flag, "the previous arrow wraps to the last choice")
	# the keys step it too
	var ev := InputEventAction.new()
	ev.action = "ui_left"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	_check(m._bg_choice == "diorama_west", "the left key steps back (%s)" % m._bg_choice)
	ev = InputEventAction.new()
	ev.action = "ui_right"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	_check(m._bg_choice == "diorama_rome", "the right key steps forward (%s)" % m._bg_choice)
	# a swipe on the row (40 px) steps it; a shorter drag does not
	var z: Control = m._sel_zone
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(100, 10)
	z.gui_input.emit(press)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = Vector2(100 - 20, 10)
	z.gui_input.emit(rel)
	_check(m._bg_choice == "diorama_rome", "a 20 px drag does not step")
	rel = InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = Vector2(100 - 50, 10)
	z.gui_input.emit(rel)
	_check(m._bg_choice == "diorama_west", "a 50 px swipe left steps forward (%s)" % m._bg_choice)
	await _frames(10)
	# a stored art_west (the retired picture) opens as the Caribbean table
	MenuPrefs._cfg_set("background", "art_west")
	MenuPrefs.bg_override = ""
	m._activate_bg()
	_check(m._bg_choice == "diorama_west" and MenuPrefs.stored_background("rome") == "diorama_west", "an art_west pref opens the Caribbean table and is rewritten")
	# emblem styles on the title
	m._set_bg("diorama_west", true)
	await _frames(10)
	await _shot_title("title_diorama_drawn")
	MenuPrefs.set_emblems("painted")
	call_group("menu_emblem", "queue_redraw")
	await _shot_title("title_diorama_painted")
	MenuPrefs.set_emblems("drawn")
	call_group("menu_emblem", "queue_redraw")
	# the saved choice is read when the menu shows again, and hiding frees the diorama
	MenuPrefs.bg_override = "diorama_rome"
	m._set_bg("diorama_rome", true)
	d = await _wait_diorama()
	m._menu.visible = false
	await _frames(3)
	_check(m._bg.diorama == null and CData.pack == "rome", "hiding the menu frees the diorama and restores Rome")
	m._menu.visible = true
	await _frames(3)
	d = await _wait_diorama()
	_check(m._bg_choice == "diorama_rome" and d != null and d.ready_flag, "showing the menu again rebuilds the saved choice")
	m._menu.visible = false
	await _frames(2)
	# Low graphics no longer forces the picture: the diorama builds with the Low layers
	Quality.save_pref("low")
	m._menu.visible = true
	await _frames(3)
	d = await _wait_diorama()
	_check(Quality.is_low() and m._bg.mode == "diorama" and d != null and d.ready_flag, "Low graphics keeps the chosen diorama")
	m._menu.visible = false
	await _frames(2)
	Quality.save_pref("auto")
	MenuPrefs.bg_override = ""
	MenuPrefs.set_background("diorama_rome")
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
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(844, 390)
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
	_cards_inside("phone story page")
	await _shot("campaign_phone")
	m.show_page("grand")
	await _frames(3)
	_check(m._grand_cards.vertical, "phone: the Host and Join panels stack")
	_check(_btn("home_offline").get_global_rect().end.x <= vp.x and (m.find_child("host_card", true, false) as Control).get_global_rect().size.x <= vp.x, "phone: Play offline is in the Host panel and fits the width")
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
	for pk in ["story", "host_west", "host_rome"]:
		if pk == "story":
			await _press("card_story")
		else:
			m.show_page("grand")
			await _frames(2)
			await _press("host_pack_" + pk.get_slice("_", 1))
			await _press("home_Online_co-op")
		var nc: Control = m._new_campaign
		await _frames(4)
		_check(nc.find_child("settings_fold", true, false) != null and not nc.find_child("settings_body", true, false).visible, "phone: the Settings panel is folded under a Campaign Settings header (%s)" % pk)
		_check(Rect2(Vector2.ZERO, vp).encloses((nc.find_child("start_campaign", true, false) as Control).get_global_rect()), "phone: Start is on the screen without scrolling (%s)" % pk)
		var wide := 0
		for r in nc.find_children("row_*", "PanelContainer", true, false):
			if (r as Control).get_global_rect().end.x > vp.x + 0.5:
				wide += 1
		_check(wide == 0, "phone: the faction rows fit the width (%s)" % pk)
		if pk != "story":
			var ppk: String = pk.get_slice("_", 1)
			nc._pick(CData.faction_index("rome" if ppk == "rome" else "england"))
			_check(CData.pack == ppk and nc.find_child("row_" + ("rome" if ppk == "rome" else "brethren"), true, false) != null and nc.find_child("row_" + ("brethren" if ppk == "rome" else "rome"), true, false) == null, "phone: Host on %s gives that setting's rows (CData.pack %s)" % [ppk, CData.pack])
			_check(str(nc.build_state("PhoneHost", 3).get("pack", "rome")) == ppk, "phone: Host's build_state carries the %s pack" % ppk)
			await _shot("faction_%s_phone" % pk)
		nc.find_child("settings_fold", true, false).pressed.emit()
		await _frames(3)
		_check(nc.find_child("settings_body", true, false).visible, "phone: the fold opens")
		nc.find_child("settings_fold", true, false).pressed.emit()   # (the open state is remembered for the session: fold it again)
		nc.back.emit()
		await _frames(3)
	for ppk in ["rome", "west"]:
		m.show_page("grand")
		await _frames(2)
		await _press("host_pack_" + ppk)
		await _press("home_offline")
		var po: Control = m._new_campaign
		_check(po != null and not po.online and CData.pack == ppk and po.find_child("row_" + ("rome" if ppk == "rome" else "brethren"), true, false) != null, "phone: Play offline on %s gives that setting's rows (CData.pack %s)" % [ppk, CData.pack])
		po._pick(CData.faction_index("rome" if ppk == "rome" else "england"))
		_check(str(po.build_state("PhoneOffline", 4).get("pack", "rome")) == ppk, "phone: Play offline's build_state carries the %s pack" % ppk)
		po.back.emit()
		await _frames(3)
	m.show_page("home")
	UiScale._dpr_override = 1.0
	UiScale._touch_override = 0
	DisplayServer.window_set_size(old)
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(1280, 720)
	await _frames(6)
	UiScale.apply(root)
	await _frames(3)
