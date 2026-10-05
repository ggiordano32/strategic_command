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
## Last battle started from the menu: replayed with the same seed and terrain.
var _last_id := ""
var _last_seed := -1
var _last_terrain := -1
var _rotate_hint: Label
var book: UnitBook
var controls: Controls
var campaign: CampaignScreen = null
var _new_campaign: NewCampaign = null
## Menu pages: "home", "sandbox", "continue", "import".
var _pages := {}
var page := "home"
var _continue_box: VBoxContainer
var _import_edit: TextEdit
var _import_info: Label
var _ios_tab := false


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
		_ios_tab = ios == true
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
		elif a.begins_with("--menu-page="):
			show_page(a.get_slice("=", 1))  # testing aid
		elif a == "--new-campaign":
			_new_campaign_page()  # testing aid
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


func _build_menu() -> Control:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.15, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pages["home"] = _build_home(bg)
	_pages["continue"] = _build_continue(bg)
	_pages["import"] = _build_import(bg)
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
	_replay_button = _menu_button("Replay last battle", _replay)
	_replay_button.tooltip_text = "Same battle, same seed, same ground"
	_replay_button.disabled = true
	row.add_child(_replay_button)
	row.add_child(_menu_button("Unit book", _open_book))
	_tests_button = _menu_button("Tests and benchmarks  +", _toggle_tests)
	row.add_child(_tests_button)
	row.add_child(_menu_button("< Back", show_page.bind("home")))
	_update_terrain_button()
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
	help.text = "Tap a unit or its card to select; All / Inf / Missile / Cav select groups, + Add adds by tapping cards.\nDrag to draw the front line. Tap ground to move, tap an enemy to attack (missile troops and artillery\nshoot it), double tap to run. Contour lines are 2 m apart: high ground helps. Long press a card: unit book."
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
	var camp := HBoxContainer.new()
	camp.add_theme_constant_override("separation", 8)
	camp.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(camp)
	for d in [["New campaign", _new_campaign_page], ["Continue", show_page.bind("continue")],
			["Import", show_page.bind("import")]]:
		var b := _menu_button(d[0], d[1])
		b.custom_minimum_size = Vector2(190, 52)
		b.add_theme_font_size_override("font_size", 17)
		b.name = "home_" + str(d[0]).replace(" ", "_")
		camp.add_child(b)
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
	_continue_box = Kit.vbox(6)
	_continue_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_continue_box)
	vb.add_child(_menu_button("< Back", show_page.bind("home")))
	return vb.get_parent().get_parent()


func _fill_continue() -> void:
	for c in _continue_box.get_children():
		c.queue_free()
	var list := Saves.list()
	if list.is_empty():
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


func show_page(p: String) -> void:
	page = p
	for k in _pages:
		(_pages[k] as Control).visible = k == p
	if p == "continue":
		_fill_continue()


func _new_campaign_page() -> void:
	_menu.visible = false
	_new_campaign = NewCampaign.new()
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
	if campaign != null:
		campaign.queue_free()
		campaign = null
	_menu.visible = true
	show_page("home")


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
