extends Control
## Start screen: pick a scenario, then hand over to the battle view.

const TouchScroll := preload("res://game/touch_scroll.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const Battle := preload("res://game/battle.gd")
const UnitBook := preload("res://game/unit_book.gd")
const Terrain := preload("res://sim/terrain.gd")
const UiScale := preload("res://game/ui_scale.gd")
const Controls := preload("res://game/controls.gd")
const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const NewCampaign := preload("res://game/campaign/new_campaign.gd")
const Saves := preload("res://game/campaign/saves.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const CState := preload("res://campaign/cstate.gd")
const CData := preload("res://campaign/cdata.gd")
const NetScript := preload("res://game/net/net.gd")
const NetSelftest := preload("res://game/net/net_selftest.gd")
const MapGen := preload("res://sim/mapgen.gd")
## Menu terrain choices for the playable battles: -1 = random from the seed.
const TERRAIN_CHOICES := [-1, Terrain.K_FLAT, Terrain.K_ROLLING, Terrain.K_RIDGE,
	Terrain.K_VALLEY, Terrain.K_HILL, Terrain.K_SLOPE]

var _menu: Control
var _battle: Node = null
var _speed_idx := 1
var _seed := -1
var _terrain_idx := 0
var _terrain_button: Button
var _replay_button: Button
## Ground palette for the playable battles (MapGen.PAL_*; Plain = no woods).
var _ground_idx := 0
var _ground_button: Button
## Settlement battle controls: seed, level 0-2, walls 0-3, terrain kind,
## the player attacks (def side 1) or defends (0).
var _siege_seed: LineEdit
var _siege_level := 1
var _siege_walls := 1
var _siege_kind_idx := 0
var _siege_def := 1
var _siege_buttons := {}
const SIEGE_KINDS := [Terrain.K_ROLLING, Terrain.K_FLAT, Terrain.K_HILL, Terrain.K_RIDGE]
## Last settlement battle (replayed by Replay), empty if the last was not one.
var _last_siege: Array = []
## Last battle started from the menu: replayed with the same seed and terrain.
var _last_id := ""
var _last_seed := -1
var _last_terrain := -1
var _rotate_hint: Label
var book: UnitBook
var controls: Controls
var campaign: CampaignScreen = null
var _new_campaign: NewCampaign = null
## Menu pages: "home", "sandbox", "continue", "import", "join", "share".
var _pages := {}
var page := "home"
var _continue_box: VBoxContainer
var _import_edit: TextEdit
var _import_info: Label
var _ios_tab := false
var _join_edit: LineEdit
var _join_info: Label
var _join_box: VBoxContainer
var _share_box: VBoxContainer
var _net_line: Label
var _online_box: VBoxContainer


var _shot_path := ""
var _shot_frames := 0
var _tests_box: Control
var _tests_button: Button
var _help: Label
var _size_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# UI size from the device (and the player's S / M / L choice).
	UiScale.apply(get_window())
	get_tree().root.size_changed.connect(func(): UiScale.apply(get_window()))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			# Testing aid: save the window as a PNG after --shot-frames frames
			# (default 30), then quit.
			_shot_path = a.get_slice("=", 1)
			if _shot_frames == 0:
				_shot_frames = 30
		elif a.begins_with("--shot-frames="):
			_shot_frames = int(a.get_slice("=", 1))
	_menu = _build_menu()
	add_child(_menu)
	show_page("home")
	book = UnitBook.new()
	add_child(book)
	controls = Controls.new()
	add_child(controls)
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_rotate_hint = Label.new()
	_rotate_hint.text = "Rotate your phone to landscape"
	_rotate_hint.add_theme_font_size_override("font_size", 28)
	_rotate_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_rotate_hint.add_theme_constant_override("outline_size", 8)
	_rotate_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_rotate_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_rotate_hint.grow_vertical = Control.GROW_DIRECTION_BOTH
	_rotate_hint.visible = false
	_rotate_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rotate_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rotate_hint.custom_minimum_size = Vector2(300, 0)
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color(0.06, 0.07, 0.06, 0.97)
	hb.set_corner_radius_all(8)
	hb.set_content_margin_all(18)
	_rotate_hint.add_theme_stylebox_override("normal", hb)
	layer.add_child(_rotate_hint)
	if OS.has_feature("web"):
		# iPhone / iPad Safari in a browser tab cannot rotate a page to
		# landscape; only the home-screen app can.
		var ios = JavaScriptBridge.eval("(/iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)) && !(window.navigator.standalone === true || window.matchMedia('(display-mode: standalone)').matches)", true)
		# JavaScriptBridge returns a JS boolean as a bool or an int depending on
		# the engine version; `int == bool` is a runtime error that used to
		# abort this _ready on every non-iOS browser.
		_ios_tab = str(ios) in ["true", "1"]
	for a in OS.get_cmdline_user_args():
		if a == "--ios-tab":
			_ios_tab = true  # testing aid
	if _ios_tab:
		_rotate_hint.text = "Turn your phone sideways. In Safari: tap Share, then Add to Home Screen, and open the game from there to play in landscape."
	# Shortcuts for testing: command line "-- --scenario=bench_2000 --speed=3"
	# (--seed=N fixes the seed),
	# or on the web a URL query "?scenario=bench_2000&speed=3".
	var args := Array(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if q is String and q.length() > 1:
			for kv in (q as String).substr(1).split("&"):
				args.append("--" + kv)
	for a in args:
		if a.begins_with("--speed="):
			_speed_idx = int(a.get_slice("=", 1))
		elif a.begins_with("--seed="):
			_seed = int(a.get_slice("=", 1))  # testing aid: fixed seed
		elif a.begins_with("--terrain="):
			# Terrain for the playable battles: a kind name or number
			# (flat, rolling, ridge, valley, hill, slope; random).
			var v: String = str(a).get_slice("=", 1).to_lower()
			for k in TERRAIN_CHOICES.size():
				var kind: int = TERRAIN_CHOICES[k]
				var nm := "random" if kind < 0 else Terrain.KIND_NAMES[kind].to_lower()
				if v == nm or v == str(kind):
					_terrain_idx = k
			_update_terrain_button()
		elif a.begins_with("--ground="):
			_ground_idx = clampi(int(a.get_slice("=", 1)), 0, MapGen.PALETTE_NAMES.size() - 1)
			_update_ground_button()
	for a in args:
		if a == "--menu-tests":
			_toggle_tests()  # testing aid: open the Tests section
		if a.begins_with("--book="):
			book.open(int(a.get_slice("=", 1)))  # testing aid: open a page
		elif a.begins_with("--book-scroll="):
			book.entry.set_deferred("scroll_vertical", int(a.get_slice("=", 1)))
	for a in args:
		if a.begins_with("--scenario="):
			_start(a.get_slice("=", 1))
		elif a.begins_with("--siege="):
			# Testing aid: --siege=seed:level:walls[:ground[:kind[:defend]]]
			var sp: PackedStringArray = a.get_slice("=", 1).split(":")
			_start_siege([int(sp[0]), int(sp[1]) if sp.size() > 1 else 1, int(sp[2]) if sp.size() > 2 else 1,
				int(sp[3]) if sp.size() > 3 else MapGen.PAL_DRY, int(sp[4]) if sp.size() > 4 else Terrain.K_ROLLING,
				0 if sp.size() > 5 and int(sp[5]) != 0 else 1])
		elif a.begins_with("--menu-page="):
			show_page(a.get_slice("=", 1))  # testing aid
		elif a == "--new-campaign":
			_new_campaign_page()  # testing aid
		elif a == "--new-online":
			_new_campaign_page(true)  # testing aid
		elif a.begins_with("--open-online="):
			_open_online(a.get_slice("=", 1))  # testing aid
		elif a.begins_with("--share="):
			_show_share(a.get_slice("=", 1).get_slice(":", 0), a.get_slice(":", 1))  # testing aid
		elif a == "--controls":
			controls.open()  # testing aid
		elif a.begins_with("--campaign="):
			# Testing aid: --campaign=rome[,greeks][:seed] starts a new campaign.
			var spec: String = a.get_slice("=", 1)
			var picks: Array = []
			for k in spec.get_slice(":", 0).split(","):
				picks.append(CData.faction_index(k))
			var sd := int(spec.get_slice(":", 1)) if spec.contains(":") else 7
			var st := CState.new_campaign("Test", sd, picks)
			var data := {"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}
			var sl := Saves.slot_for("test", sd)
			Saves.save(sl, data)
			_open_campaign(data, sl)
		elif a.begins_with("--campaign-slot="):
			var sl2: String = a.get_slice("=", 1)
			var d2 := Saves.load_slot(sl2)
			if not d2.is_empty():
				_open_campaign(d2, sl2)
	_check_server.call_deferred()
	var net := _net()
	if net != null and net.launch.has("nettest"):
		var t := NetSelftest.new()
		t.role = str(net.launch["nettest"])
		t.params = net.launch.duplicate()
		t.params["join"] = str(net.launch.get("join", ""))
		add_child(t)
	elif net != null and campaign == null:
		if net.launch.has("link"):
			_claim_device_code.call_deferred(str(net.launch["link"]))
		elif net.launch.has("join"):
			show_page("join")
			_join_edit.text = NetScript.show_code(str(net.launch["join"]))
			_join_find.call_deferred()


func _net() -> Node:
	return get_node_or_null("/root/Net")


## Is the campaign server there? (A line on the home page says.)
func _check_server() -> void:
	var net := _net()
	if net == null or _net_line == null:
		return
	if not net.has_server():
		_net_line.text = "Online play needs the game server (open the game from its web address)."
		return
	_net_line.text = "Checking the game server..."
	var ok: bool = await net.check_server()
	if ok:
		_net_line.text = "Online co-op ready." + (" A newer version of the game is on the server: reload the page." if net.new_build_available else "")
		_net_line.add_theme_color_override("font_color", Kit.COL_GOOD if not net.new_build_available else Kit.COL_GOLD)
	else:
		_net_line.text = "The game server is not available: online play is off; local play works as usual."
		_net_line.add_theme_color_override("font_color", Kit.COL_DIM)


func _build_menu() -> Control:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.15, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pages["home"] = _build_home(bg)
	_pages["continue"] = _build_continue(bg)
	_pages["import"] = _build_import(bg)
	_pages["join"] = _build_join(bg)
	_pages["share"] = _build_share(bg)
	var center := _scroll_page(bg)
	_pages["sandbox"] = center.get_parent()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	center.add_child(vb)
	var title := Label.new()
	title.text = "Battle sandbox"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var info := Label.new()
	info.text = "Godot %s, %s renderer" % [Engine.get_version_info()["string"],
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")]
	info.add_theme_font_size_override("font_size", 12)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(info)
	# Battles.
	var battles := HBoxContainer.new()
	battles.add_theme_constant_override("separation", 8)
	battles.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(battles)
	for id in Scenarios.PLAYABLE:
		var b := _menu_button(Scenarios.title(id), _start.bind(id))
		b.custom_minimum_size = Vector2(250, 48)
		b.add_theme_font_size_override("font_size", 16)
		battles.add_child(b)
	# Options.
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	_terrain_button = _menu_button("", _cycle_terrain)
	_terrain_button.tooltip_text = "Ground for the three battles (tests have their own)"
	row.add_child(_terrain_button)
	_ground_button = _menu_button("", _cycle_ground)
	_ground_button.tooltip_text = "Region look and woods: plain (no woods), arid, dry, green, rocky"
	row.add_child(_ground_button)
	_replay_button = _menu_button("Replay last battle", _replay)
	_replay_button.tooltip_text = "Same battle, same seed, same ground"
	_replay_button.disabled = true
	row.add_child(_replay_button)
	row.add_child(_menu_button("Unit book", _open_book))
	_tests_button = _menu_button("Tests and benchmarks  +", _toggle_tests)
	row.add_child(_tests_button)
	row.add_child(_menu_button("< Back", show_page.bind("home")))
	_update_terrain_button()
	_update_ground_button()
	vb.add_child(_build_siege_row())
	# Tests and benchmarks, folded away by default.
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	grid.visible = false
	vb.add_child(grid)
	for id in Scenarios.IDS:
		if id in Scenarios.PLAYABLE:
			continue
		var tb := _menu_button(Scenarios.title(id).trim_prefix("Test: ").replace("AI vs AI benchmark", "AI benchmark"), _start.bind(id))
		tb.custom_minimum_size = Vector2(205, 36)
		tb.add_theme_font_size_override("font_size", 13)
		tb.clip_text = true
		tb.tooltip_text = Scenarios.title(id)
		grid.add_child(tb)
	_tests_box = grid
	var help := Label.new()
	help.text = "Tap a unit or its card to select; All / Inf / Missile / Cav select groups, + Add adds by tapping cards.\nDrag to draw the front line. Tap ground to move, tap an enemy to attack (missile troops and artillery\nshoot it), double tap to run. Contour lines are 2 m apart: high ground helps. Long press a card: unit book.\nSettlements: select engines or foot and tap a gate to break it; defending, tap a gate (nothing selected) to open or shut it."
	help.add_theme_font_size_override("font_size", 13)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(1, 1, 1, 0.75)
	vb.add_child(help)
	_help = help
	return bg


## A menu page: a touch-scrollable full-screen area with its content centred
## (scrolls when the content is taller than a phone screen).
func _scroll_page(bg: Control) -> CenterContainer:
	var scroll := TouchScroll.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.visible = false
	bg.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	return center


func _page_box(bg: Control) -> VBoxContainer:
	var center := _scroll_page(bg)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	center.add_child(vb)
	return vb


func _build_home(bg: Control) -> Control:
	var vb := _page_box(bg)
	var title := Kit.label("Strategic Command", 30, Color(1, 0.92, 0.7))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := Kit.label("The western Mediterranean, 280 BC", 15, Kit.COL_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var camp := HFlowContainer.new()
	camp.add_theme_constant_override("h_separation", 8)
	camp.add_theme_constant_override("v_separation", 8)
	camp.alignment = FlowContainer.ALIGNMENT_CENTER
	camp.custom_minimum_size.x = 640
	vb.add_child(camp)
	for d in [["New campaign", _new_campaign_page.bind(false)], ["Online co-op", _new_campaign_page.bind(true)],
			["Join", show_page.bind("join")], ["Continue", show_page.bind("continue")],
			["Import", show_page.bind("import")]]:
		var b := _menu_button(d[0], d[1])
		b.custom_minimum_size = Vector2(150 if d[0] in ["Join", "Import"] else 190, 52)
		b.add_theme_font_size_override("font_size", 17)
		b.name = "home_" + str(d[0]).replace(" ", "_")
		camp.add_child(b)
	_net_line = Kit.label("", 13, Kit.COL_DIM)
	_net_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_net_line)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	var sb := _menu_button("Battle sandbox", show_page.bind("sandbox"))
	sb.name = "home_sandbox"
	row.add_child(sb)
	row.add_child(_menu_button("Unit book", _open_book))
	var cb := _menu_button("Controls", _open_controls)
	cb.name = "home_controls"
	row.add_child(cb)
	_size_button = _menu_button("", _cycle_ui_size)
	_size_button.tooltip_text = "Size of buttons and text (S / M / L)"
	row.add_child(_size_button)
	row.add_child(_menu_button("Fullscreen", _toggle_fullscreen))
	_update_size_button()
	var info := Kit.label("Godot %s, %s renderer" % [Engine.get_version_info()["string"],
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")], 12, Color(1, 1, 1, 0.5))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(info)
	return vb.get_parent().get_parent()


func _build_continue(bg: Control) -> Control:
	var vb := _page_box(bg)
	vb.add_child(Kit.label("Continue a campaign", 22, Kit.COL_GOLD))
	var scroll := TouchScroll.new()
	scroll.custom_minimum_size = Vector2(560, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var both := Kit.vbox(8)
	both.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(both)
	_online_box = Kit.vbox(6)
	_online_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	both.add_child(_online_box)
	_continue_box = Kit.vbox(6)
	_continue_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	both.add_child(_continue_box)
	vb.add_child(_menu_button("< Back", show_page.bind("home")))
	return vb.get_parent().get_parent()


func _fill_continue() -> void:
	for c in _continue_box.get_children():
		c.queue_free()
	_fill_online()
	var list := Saves.list()
	if not list.is_empty() and _online_box.get_child_count() > 0:
		_continue_box.add_child(Kit.label("On this device", 15, Kit.COL_GOLD))
	if list.is_empty() and _online_box.get_child_count() == 0:
		_continue_box.add_child(Kit.label("No saved campaigns yet.", 15, Kit.COL_DIM))
	for m in list:
		var h := Kit.hbox(6)
		var sl := str(m["slot"])
		var b := _menu_button("%s - %s - %s" % [m.get("name", sl), " & ".join(m.get("factions", [])), m.get("date", "")],
			func():
				var d := Saves.load_slot(sl)
				if not d.is_empty():
					_open_campaign(d, sl))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		h.add_child(b)
		var del := Kit.button("Delete", Callable(), 80)
		del.pressed.connect(func():
			if del.text == "Sure?":
				Saves.delete(sl)
				_fill_continue()
			else:
				del.text = "Sure?")
		h.add_child(del)
		_continue_box.add_child(h)


## Online campaigns this device has a seat in, with live status badges.
func _fill_online() -> void:
	for c in _online_box.get_children():
		c.queue_free()
	var net := _net()
	if net == null:
		return
	var list: Array = net.accounts.list()
	if list.is_empty():
		return
	_online_box.add_child(Kit.label("Online", 15, Kit.COL_GOLD))
	var badges := {}
	for e in list:
		var cid := str(e["id"])
		var h := Kit.hbox(6)
		var b := _menu_button("%s - %s" % [e.get("name", cid), CData.faction_name(int(e["f"]))], _open_online.bind(cid))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.name = "online_" + cid
		h.add_child(b)
		var badge := Kit.label("..." if net.has_server() else "Offline", 14, Kit.COL_DIM)
		badge.custom_minimum_size.x = 150
		badge.name = "badge"
		badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(badge)
		badges[cid] = badge
		var del := Kit.button("Forget", Callable(), 80)
		del.tooltip_text = "Remove this campaign from this device (it stays on the server; your ally keeps playing)."
		del.pressed.connect(func():
			if del.text == "Sure?":
				net.accounts.remove(cid)
				_fill_continue()
			else:
				del.text = "Sure?")
		h.add_child(del)
		_online_box.add_child(h)
	if net.has_server():
		_update_badges(badges)


func _update_badges(labels: Dictionary) -> void:
	var net := _net()
	var got: Dictionary = await net.refresh_badges()
	for cid in labels:
		var l: Label = labels[cid]
		if is_instance_valid(l) and got.has(cid):
			l.text = str(got[cid]["text"])
			l.add_theme_color_override("font_color", got[cid]["color"])


func _build_import(bg: Control) -> Control:
	var vb := _page_box(bg)
	vb.add_child(Kit.label("Import a campaign", 22, Kit.COL_GOLD))
	vb.add_child(Kit.label("Paste the text from Export (campaign Menu) on the other device.", 14, Kit.COL_DIM))
	_import_edit = TextEdit.new()
	_import_edit.custom_minimum_size = Vector2(560, 150)
	_import_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	vb.add_child(_import_edit)
	_import_info = Kit.label("", 14, Kit.COL_BAD)
	vb.add_child(_import_info)
	var h := Kit.hbox(8)
	h.add_child(_menu_button("Paste", func(): _import_edit.text = DisplayServer.clipboard_get()))
	h.add_child(_menu_button("Import and play", _do_import))
	h.add_child(_menu_button("< Back", show_page.bind("home")))
	vb.add_child(h)
	return vb.get_parent().get_parent()


func _do_import() -> void:
	var d := Saves.import_text(_import_edit.text)
	if d.is_empty():
		_import_info.text = "That text is not a campaign save (or is cut short)."
		return
	var st: Dictionary = d["state"]
	var sl := Saves.slot_for(str(st["name"]), int(st["seed"]))
	Saves.save(sl, d)
	_import_info.text = ""
	_open_campaign(d, sl)


# ------------------------------------------------------------------ join ---

func _build_join(bg: Control) -> Control:
	var vb := _page_box(bg)
	vb.add_child(Kit.label("Join a campaign", 22, Kit.COL_GOLD))
	vb.add_child(Kit.label("Enter the join code from your ally, or a device code to continue your own campaign here.", 14, Kit.COL_DIM))
	var h := Kit.hbox(8)
	_join_edit = LineEdit.new()
	_join_edit.name = "join_code"
	_join_edit.placeholder_text = "ABC-DEF"
	_join_edit.custom_minimum_size = Vector2(240, 52)
	_join_edit.add_theme_font_size_override("font_size", 26)
	_join_edit.max_length = 11
	_join_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_join_edit.text_changed.connect(func(t: String):
		var up: String = t.to_upper()
		if up != t:
			var c := _join_edit.caret_column
			_join_edit.text = up
			_join_edit.caret_column = c)
	_join_edit.text_submitted.connect(func(_t): _join_find())
	h.add_child(_join_edit)
	var fb := _menu_button("Find", _join_find)
	fb.name = "join_find"
	fb.custom_minimum_size = Vector2(110, 52)
	h.add_child(fb)
	h.add_child(_menu_button("Paste", func():
		_join_edit.text = DisplayServer.clipboard_get().strip_edges().to_upper().substr(0, 40)))
	vb.add_child(h)
	_join_info = Kit.label("", 14, Kit.COL_BAD, true)
	_join_info.custom_minimum_size.x = 520
	vb.add_child(_join_info)
	_join_box = Kit.vbox(8)
	vb.add_child(_join_box)
	vb.add_child(_menu_button("< Back", show_page.bind("home")))
	return vb.get_parent().get_parent()


func _join_find() -> void:
	var net := _net()
	for c in _join_box.get_children():
		c.queue_free()
	var raw := _join_edit.text
	# A whole link pasted: take its code.
	for key in ["join=", "link="]:
		if raw.to_lower().contains(key):
			raw = raw.substr(raw.to_lower().find(key) + key.length()).get_slice("&", 0)
	var code: String = NetScript.norm_code(raw)
	if net == null or not net.has_server():
		_join_info.text = "Online play needs the game server: open the game from its web address."
		return
	if not net.available and not await net.check_server():
		_join_info.text = "The game server is not available right now, so online play is off. Local play works as usual."
		return
	if code.length() == 8:
		_claim_device_code(code)
		return
	if code.length() != 6:
		_join_info.text = "A join code has 6 characters, a device code 8 (letters and digits; no 0, 1, I, L, O, U or V)."
		return
	_join_info.add_theme_color_override("font_color", Kit.COL_DIM)
	_join_info.text = "Looking..."
	var r: Dictionary = await net.join_preview(code)
	_join_info.add_theme_color_override("font_color", Kit.COL_BAD)
	if not r["ok"]:
		_join_info.text = _net_error(r, "No open campaign has that code. Check it with your ally (it stops working once both seats are taken).")
		return
	_join_info.text = ""
	var d: Dictionary = CState.normalise(r["data"])
	if int(d.get("format_version", 0)) > CState.VERSION or int(d.get("format_version", 0)) < CState.MIN_VERSION:
		_join_info.text = "That campaign was made by a different version of the game: reload the page to update."
		return
	_join_box.add_child(Kit.label("%s, turn %d." % [d.get("name", ""), int(d.get("turn", 0)) + 1], 17, Color.WHITE))
	var free: Array = []
	var taken: Array[String] = []
	for seat in d["seats"]:
		if bool(seat["claimed"]):
			taken.append(str(seat["name"]))
		else:
			free.append(seat)
	if not taken.is_empty():
		_join_box.add_child(Kit.label("Playing already: " + ", ".join(taken) + ".", 14, Kit.COL_DIM))
	if free.is_empty():
		_join_box.add_child(Kit.label("Every seat is taken.", 15, Kit.COL_BAD))
		return
	var du := LineEdit.new()
	du.placeholder_text = "Your Discord user id (optional, for @mentions)"
	du.custom_minimum_size = Vector2(380, 40)
	du.text = str(net.accounts.data.get("discord_user", ""))
	_join_box.add_child(du)
	var row := Kit.flow(8)
	for seat in free:
		var f := int(seat["f"])
		var b := _menu_button("Play as %s" % seat["name"], func(): _join_seat(code, f, du.text.strip_edges()))
		b.name = "join_seat_%d" % f
		b.custom_minimum_size = Vector2(220, 52)
		var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
		img.fill(CData.faction_color(f))
		b.icon = ImageTexture.create_from_image(img)
		row.add_child(b)
	_join_box.add_child(row)


func _join_seat(code: String, f: int, discord_user: String) -> void:
	var net := _net()
	if discord_user != "":
		net.accounts.set_value("discord_user", discord_user)
	_join_info.add_theme_color_override("font_color", Kit.COL_DIM)
	_join_info.text = "Joining..."
	var r: Dictionary = await net.join(code, f, discord_user)
	_join_info.add_theme_color_override("font_color", Kit.COL_BAD)
	if not r["ok"]:
		_join_info.text = _net_error(r, "Could not join.")
		return
	_join_info.text = ""
	_tele_event("online_join", {"f": f})
	_open_online(str(r["data"]["id"]))


func _claim_device_code(code: String) -> void:
	var net := _net()
	if net == null:
		return
	show_page("join")
	_join_edit.text = NetScript.show_code(code)
	if not net.available and not await net.check_server():
		_join_info.add_theme_color_override("font_color", Kit.COL_BAD)
		_join_info.text = "The game server is not available right now, so online play is off. Local play works as usual."
		return
	_join_info.add_theme_color_override("font_color", Kit.COL_DIM)
	_join_info.text = "Moving your campaign to this device..."
	var r: Dictionary = await net.claim_link(code)
	_join_info.add_theme_color_override("font_color", Kit.COL_BAD)
	if not r["ok"]:
		_join_info.text = _net_error(r, "That device code is unknown or has expired (codes last 30 minutes). Get a new one on the other device: Online > Get a device code.")
		return
	_join_info.text = ""
	_tele_event("online_device_linked", {})
	_open_online(str(r["data"]["id"]))


func _net_error(r: Dictionary, fallback: String) -> String:
	if r["network"]:
		return "The game server cannot be reached. Check the connection and try again."
	if int(r["status"]) == 429:
		return "Too many tries: wait a few minutes."
	if int(r["status"]) == 404 or str(r["error"]) == "bad_code":
		return fallback
	return str(r["message"]) if str(r["message"]) != "" else fallback


func _tele_event(kind: String, d: Dictionary) -> void:
	var tele := get_node_or_null("/root/Telemetry")
	if tele != null:
		tele.event(kind, d)


# ------------------------------------------------------- share (created) ---

func _build_share(bg: Control) -> Control:
	var vb := _page_box(bg)
	_share_box = vb
	return vb.get_parent().get_parent()


## After creating an online campaign: the join code and link for the ally.
func _show_share(cid: String, code: String) -> void:
	for c in _share_box.get_children():
		c.queue_free()
	var net := _net()
	_share_box.add_child(Kit.label("Online campaign created", 22, Kit.COL_GOLD))
	if code != "":
		var link: String = net.join_link(code) if net else code
		_share_box.add_child(Kit.label("Send your ally this join code, or the link:", 15, Color.WHITE))
		var cl := Kit.label(NetScript.show_code(code), 40, Kit.COL_GOLD)
		cl.name = "share_code"
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_share_box.add_child(cl)
		var ll := Kit.label(link, 14, Kit.COL_DIM, true)
		ll.custom_minimum_size.x = 520
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_share_box.add_child(ll)
		var row := Kit.flow(8)
		row.alignment = FlowContainer.ALIGNMENT_CENTER
		row.add_child(_menu_button("Copy link", func():
			DisplayServer.clipboard_set(link)
			_share_info("Link copied.")))
		row.add_child(_menu_button("Copy code", func():
			DisplayServer.clipboard_set(NetScript.show_code(code))
			_share_info("Code copied.")))
		_share_box.add_child(row)
		_share_box.add_child(Kit.label("They open the link (or Join on the main menu and type the code). You can start planning now; the turn resolves when you have both submitted.", 13, Kit.COL_DIM, true))
	_share_box.add_child(Kit.label("To continue on another of your devices later: in the campaign, Online > Get a device code.", 13, Kit.COL_DIM, true))
	var info := Kit.label("", 13, Kit.COL_GOOD)
	info.name = "share_info"
	_share_box.add_child(info)
	var ob := _menu_button("Open the campaign", _open_online.bind(cid))
	ob.name = "share_open"
	ob.custom_minimum_size = Vector2(240, 52)
	_share_box.add_child(ob)
	_menu.visible = true
	show_page("share")


func _share_info(t: String) -> void:
	var l := _share_box.get_node_or_null("share_info")
	if l != null:
		l.text = t


func _open_online(cid: String) -> void:
	var net := _net()
	if net == null or campaign != null:
		return
	var oc = net.open_campaign(cid)
	if oc == null:
		return
	_menu.visible = false
	campaign = CampaignScreen.new()
	campaign.open_online(oc)
	campaign.exit_requested.connect(_close_campaign)
	get_tree().root.add_child.call_deferred(campaign)


func show_page(p: String) -> void:
	page = p
	for k in _pages:
		(_pages[k] as Control).visible = k == p
	if p == "continue":
		_fill_continue()


func _new_campaign_page(online: bool = false) -> void:
	_menu.visible = false
	_new_campaign = NewCampaign.new()
	_new_campaign.online = online
	_new_campaign.created_online.connect(func(cid, code):
		_new_campaign.queue_free()
		_new_campaign = null
		_show_share(cid, code))
	_new_campaign.start.connect(func(d, sl):
		_new_campaign.queue_free()
		_new_campaign = null
		_open_campaign(d, sl))
	_new_campaign.back.connect(func():
		_new_campaign.queue_free()
		_new_campaign = null
		_menu.visible = true)
	add_child(_new_campaign)
	move_child(_new_campaign, _menu.get_index() + 1)


func _open_campaign(d: Dictionary, sl: String) -> void:
	if campaign != null:
		return
	_menu.visible = false
	campaign = CampaignScreen.new()
	campaign.open(d, sl)
	campaign.exit_requested.connect(_close_campaign)
	get_tree().root.add_child.call_deferred(campaign)


func _close_campaign() -> void:
	var went_online := ""
	if campaign != null:
		if campaign.has_meta("go_online"):
			went_online = str(campaign.get_meta("go_online"))
		if campaign.online != null:
			campaign.online.flush_session()
			var net := _net()
			if net != null:
				net.close_campaign()
		campaign.queue_free()
		campaign = null
	_menu.visible = true
	show_page("home")
	if went_online != "":
		var net2 := _net()
		var sm := {}
		var code := ""
		if net2 != null:
			var e: Dictionary = net2.accounts.get_entry(went_online)
			var r: Dictionary = await net2.api.call_api("GET", "/api/c/" + went_online, null, str(e.get("token", "")))
			if r["ok"]:
				sm = r["data"]
				code = str(sm.get("join_code", ""))
		_show_share(went_online, code)


func _open_controls() -> void:
	controls.open()


func _toggle_tests() -> void:
	_tests_box.visible = not _tests_box.visible
	_help.visible = not _tests_box.visible
	_tests_button.text = "Tests and benchmarks  " + ("-" if _tests_box.visible else "+")


func _cycle_ui_size() -> void:
	UiScale.cycle_size(get_window())
	_update_size_button()


func _update_size_button() -> void:
	if _size_button != null:
		_size_button.text = "UI size: " + UiScale.size_name()


## Settlement battles: a seed, the level and walls, the ground kind, attack
## or defend; Start opens the settlement's battle map (the ground palette is
## the Ground button's; Plain uses the dry one).
func _build_siege_row() -> Control:
	var box := HFlowContainer.new()
	box.add_theme_constant_override("h_separation", 8)
	box.add_theme_constant_override("v_separation", 8)
	box.alignment = FlowContainer.ALIGNMENT_CENTER
	var l := Label.new()
	l.text = "Settlement battle:"
	l.add_theme_font_size_override("font_size", 15)
	l.custom_minimum_size = Vector2(0, 42)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(l)
	_siege_seed = LineEdit.new()
	_siege_seed.text = "1"
	_siege_seed.placeholder_text = "seed"
	_siege_seed.custom_minimum_size = Vector2(96, 42)
	_siege_seed.tooltip_text = "Settlement seed: the same seed, level and walls always give the same map"
	box.add_child(_siege_seed)
	for key in ["level", "walls", "kind", "side"]:
		var b := _menu_button("", _cycle_siege.bind(key))
		b.custom_minimum_size = Vector2(110, 42)
		_siege_buttons[key] = b
		box.add_child(b)
	var go := _menu_button("Start", func(): _start_siege(_siege_params()))
	go.custom_minimum_size = Vector2(100, 42)
	box.add_child(go)
	_update_siege_buttons()
	return box


func _cycle_siege(key: String) -> void:
	match key:
		"level":
			_siege_level = (_siege_level + 1) % 3
		"walls":
			_siege_walls = (_siege_walls + 1) % 4
		"kind":
			_siege_kind_idx = (_siege_kind_idx + 1) % SIEGE_KINDS.size()
		"side":
			_siege_def = 1 - _siege_def
	_update_siege_buttons()


func _update_siege_buttons() -> void:
	if _siege_buttons.is_empty():
		return
	(_siege_buttons["level"] as Button).text = ["Village", "Town", "City"][_siege_level]
	(_siege_buttons["walls"] as Button).text = "Walls %d" % _siege_walls
	(_siege_buttons["kind"] as Button).text = Terrain.KIND_NAMES[SIEGE_KINDS[_siege_kind_idx]]
	(_siege_buttons["side"] as Button).text = "You attack" if _siege_def == 1 else "You defend"


func _siege_params() -> Array:
	var sd := absi(int(_siege_seed.text)) if _siege_seed.text.is_valid_int() else absi(_siege_seed.text.hash())
	var ground := _ground_idx if _ground_idx > 0 else MapGen.PAL_DRY
	return [sd, _siege_level, _siege_walls, ground, SIEGE_KINDS[_siege_kind_idx], _siege_def]


## params: [seed, level, walls, ground, kind, def side].
func _start_siege(params: Array) -> void:
	if _battle != null:
		return
	_menu.visible = false
	var b := Battle.new()
	b.scenario_id = "settlement"
	b.custom_scenario = Scenarios.siege_test(params[0], params[1], params[2], params[3], params[4], params[5])
	b.seed_value = _seed if _seed >= 0 else int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	_last_siege = params
	_last_id = "settlement"
	_last_seed = b.seed_value
	_replay_button.disabled = false
	_replay_button.text = "Replay (seed %d)" % b.seed_value
	b.speed_idx = clampi(_speed_idx, 0, Battle.SPEEDS.size() - 1)
	b.exit_requested.connect(_end_battle)
	_battle = b
	get_tree().root.add_child.call_deferred(b)


func _cycle_ground() -> void:
	_ground_idx = (_ground_idx + 1) % MapGen.PALETTE_NAMES.size()
	_update_ground_button()


func _update_ground_button() -> void:
	if _ground_button != null:
		_ground_button.text = "Ground: " + MapGen.PALETTE_NAMES[_ground_idx].to_lower()


func _cycle_terrain() -> void:
	_terrain_idx = (_terrain_idx + 1) % TERRAIN_CHOICES.size()
	_update_terrain_button()


func _update_terrain_button() -> void:
	if _terrain_button == null:
		return
	var kind: int = TERRAIN_CHOICES[_terrain_idx]
	_terrain_button.text = "Terrain: " + ("random" if kind < 0 else Terrain.KIND_NAMES[kind].to_lower())


func _replay() -> void:
	if _last_id == "":
		return
	if _last_id == "settlement" and not _last_siege.is_empty():
		var keep := _seed
		_seed = _last_seed
		_start_siege(_last_siege)
		_seed = keep
		return
	_start_with(_last_id, _last_seed, _last_terrain)


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 42)
	b.add_theme_font_size_override("font_size", 15)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _open_book() -> void:
	var tele := get_node_or_null("/root/Telemetry")
	if tele != null:
		tele.event("book_open", {"from": "menu"})
	book.open()


func _toggle_fullscreen() -> void:
	# Works on desktop and Android browsers; iPhone Safari has no fullscreen
	# API for pages (use "Add to Home Screen" there instead).
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _process(_delta: float) -> void:
	var sz := get_viewport().get_visible_rect().size
	_rotate_hint.visible = sz.y > sz.x
	if _shot_path != "":
		_shot_frames -= 1
		if _shot_frames <= 0:
			var img := get_viewport().get_texture().get_image()
			img.save_png(_shot_path)
			print("saved ", _shot_path, " ", img.get_size(), " logical ", get_viewport().get_visible_rect().size)
			_shot_path = ""
			get_tree().quit()


func _start(id: String) -> void:
	# Benchmarks use a fixed seed so runs on different devices are comparable.
	var sd := 42 if id.begins_with("bench") else int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	if _seed >= 0:
		sd = _seed
	_start_with(id, sd, TERRAIN_CHOICES[_terrain_idx])


func _start_with(id: String, sd: int, terrain_kind: int) -> void:
	if _battle != null:
		return
	_menu.visible = false
	var b := Battle.new()
	b.scenario_id = id
	b.seed_value = sd
	b.terrain_kind = terrain_kind
	if id in Scenarios.PLAYABLE and _ground_idx > 0:
		b.ground = _ground_idx
	_last_siege = []
	_last_id = id
	_last_seed = sd
	_last_terrain = terrain_kind
	_replay_button.disabled = false
	_replay_button.text = "Replay (seed %d)" % sd
	b.speed_idx = clampi(_speed_idx, 0, Battle.SPEEDS.size() - 1)
	b.exit_requested.connect(_end_battle)
	_battle = b
	get_tree().root.add_child.call_deferred(b)


func _end_battle() -> void:
	if _battle != null:
		_battle.queue_free()
		_battle = null
	_menu.visible = true
