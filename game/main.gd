extends Control
## Start screen: pick a scenario, then hand over to the battle view.

const AudioFx := preload("res://game/audio.gd")
const Quality := preload("res://game/quality.gd")
const BattleLook := preload("res://game/battle_look.gd")
const TouchScroll := preload("res://game/touch_scroll.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const Battle := preload("res://game/battle.gd")
const UnitBook := preload("res://game/unit_book.gd")
const Terrain := preload("res://sim/terrain.gd")
const UiScale := preload("res://game/ui_scale.gd")
const SoldierLayer := preload("res://game/soldier_layer.gd")
const Controls := preload("res://game/controls.gd")
const CampaignScreen := preload("res://game/campaign/campaign_screen.gd")
const NewCampaign := preload("res://game/campaign/new_campaign.gd")
const LoadingPanel := preload("res://game/campaign/loading_panel.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const Saves := preload("res://game/campaign/saves.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const ServerPage := preload("res://game/net/server_page.gd")
const CState := preload("res://campaign/cstate.gd")
const CData := preload("res://campaign/cdata.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const NetScript := preload("res://game/net/net.gd")
const NetSelftest := preload("res://game/net/net_selftest.gd")
const MapGen := preload("res://sim/mapgen.gd")
const CustomBattle := preload("res://game/custom/custom_battle.gd")
const CustomSetup := preload("res://game/custom/custom_setup.gd")
const SeaBattle := preload("res://game/sea_battle.gd")
const MenuPrefs := preload("res://game/menu/menu_prefs.gd")
const MenuBg := preload("res://game/menu/menu_bg.gd")
const Emblem := preload("res://game/menu/emblem.gd")
const MenuStyle := preload("res://game/menu/menu_style.gd")
const OptionsRows := preload("res://game/menu/options_rows.gd")
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
## Battle AI skill for the sandbox (sim/ai_profile.gd EASY / AVERAGE /
## SKILLED).
var _ai_skill := 1
var _ai_button: Button
const AI_SKILL_LABELS: Array[String] = ["easy", "average", "skilled"]
## Settlement battle controls: seed, level 0-2, walls 0-3, terrain kind,
## the player attacks (def side 1) or defends (0).
var _siege_seed: LineEdit
var _siege_level := 1
var _siege_walls := 1
var _siege_kind_idx := 0
var _siege_def := 1
var _siege_plan := MapGen.PLAN_RING
var _siege_coast := 0
var _siege_equip := 0  # attackers' siege equipment: 0 none, 1 ladders, 2 ladders and a ram
var _siege_time := 900  # battle time limit (s)
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
var _preparing := false  # a campaign is opening behind the loading panel
var _new_campaign: NewCampaign = null
var _subtitle: Label = null
## Menu pages: "home" (the title screen), "campaign", "grand", "battles", "options", and below them "sandbox",
## "import", "join", "share", "server". BACK says where a page's Back goes.
var _pages := {}
var page := "home"
const BACK := {"campaign": "home", "grand": "home", "battles": "home", "options": "home", "sandbox": "battles",
	"import": "campaign", "join": "grand", "server": "grand", "share": "grand"}
var _bg: Control = null          # the title menu's background (game/menu/menu_bg.gd)
var _back_btn: Button = null
var _home: Control = null
var _home_stack: VBoxContainer = null
var _home_mark: HBoxContainer = null
var _home_emblem: Control = null
var _entries: Array = []         # the title screen's entry wrappers, in order
var _continue_entry: Button = null
var _continue_emblem: Control = null
var _recent: Dictionary = {}     # the most recent save: {kind, slot / id, name, turn, pack}
var _phone_layout := false
var _bg_choice := ""              # the title screen's background (one of MenuPrefs.BACKGROUNDS; "" before the first resolve)
var _sel: VBoxContainer = null    # the background selector at the bottom of the title screen
var _sel_label: Label = null
var _sel_prev: Button = null
var _sel_next: Button = null
var _sel_zone: Control = null
var _sel_press := Vector2.ZERO
var _home_info: Label = null
var _continue_box: VBoxContainer
var _import_edit: TextEdit
var _import_info: Label
var _ios_tab := false
var _join_edit: LineEdit
var _join_info: Label
var _join_box: VBoxContainer
var _share_box: VBoxContainer
var _net_line: Label             # the Host card's server line ("Server: <host> - ready")
var _net_dot: Kit.Dot
var _srv_label: Label            # the Game server row at the bottom of the Grand Campaign page
var _srv_dot: Kit.Dot
var _server_page  # game/net/server_page.gd
var _online_box: VBoxContainer
var _grand_cards: BoxContainer   # the Host and Join cards (side by side, stacked on a phone)
var _grand_col: VBoxContainer
var _gh_pack := "west"           # the Host card's picked setting
var _gh_cards := {}              # pack key -> its mini-card
var _gj_edit: LineEdit           # the Join card's code field
var _gj_info: Label
var _gj_box: VBoxContainer
var _opts: OptionsRows = null    # the Options page's rows


var custom: CustomBattle = null
var _shot_path := ""
var _shot_frames := 0
var _tests_box: Control
var _tests_button: Button
var _help: Label


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
	_menu.visibility_changed.connect(_menu_visibility)
	get_tree().root.size_changed.connect(_layout_home)
	get_tree().root.size_changed.connect(_fit_options_later)
	get_tree().root.size_changed.connect(_layout_grand)
	show_page("home")
	_activate_bg.call_deferred()
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
			# Testing aid: --siege=seed:level:walls[:ground[:kind[:defend[:plan[:coast[:equip[:time]]]]]]]
			# (plan: MapGen.PLAN_* 0 castrum, 1 polis, 2 punic, 3 oppidum, 4 ring;
			# equip 0 none, 1 ladders, 2 ladders and a ram; time limit in s)
			var sp: PackedStringArray = a.get_slice("=", 1).split(":")
			_start_siege([int(sp[0]), int(sp[1]) if sp.size() > 1 else 1, int(sp[2]) if sp.size() > 2 else 1,
				int(sp[3]) if sp.size() > 3 else MapGen.PAL_DRY, int(sp[4]) if sp.size() > 4 else Terrain.K_ROLLING,
				0 if sp.size() > 5 and int(sp[5]) != 0 else 1,
				clampi(int(sp[6]), 0, MapGen.PLAN_RING) if sp.size() > 6 else MapGen.PLAN_RING,
				1 if sp.size() > 7 and int(sp[7]) != 0 else 0, int(sp[8]) if sp.size() > 8 else 0,
				int(sp[9]) if sp.size() > 9 else 900])
		elif a.begins_with("--menu-page="):
			show_page(a.get_slice("=", 1))  # testing aid
		elif a.begins_with("--host-start="):
			# Testing aid: open the Game server page and press Host > Start on that port.
			show_page("server")
			_server_page.autostart.call_deferred(int(a.get_slice("=", 1)))
		elif a == "--new-campaign":
			_new_campaign_page()  # testing aid
		elif a == "--custom" or a.begins_with("--custom-template=") or a.begins_with("--custom-join="):
			if custom == null:
				_open_custom()  # testing aid (the screen reads the rest)
		elif a == "--custom-solo":
			_open_custom()
			custom._play_solo.call_deferred()  # testing aid: straight into the battle
		elif a == "--new-online":
			_new_campaign_page(true)  # testing aid
		elif a.begins_with("--open-online="):
			_open_online.call_deferred(a.get_slice("=", 1))  # testing aid
		elif a.begins_with("--share="):
			_show_share(a.get_slice("=", 1).get_slice(":", 0), a.get_slice(":", 1))  # testing aid
		elif a == "--controls":
			controls.open()  # testing aid
		elif a.begins_with("--campaign="):
			# Testing aid: --campaign=rome[,greeks][:seed] starts a new campaign.
			var spec: String = a.get_slice("=", 1)
			for a2 in OS.get_cmdline_user_args():
				if a2.begins_with("--pack="):
					PackView.use_pack(a2.get_slice("=", 1))  # --pack=west with --campaign=new_spain
			var picks: Array = []
			for k in spec.get_slice(":", 0).split(","):
				picks.append(CData.faction_index(k))
			var sd := int(spec.get_slice(":", 1)) if spec.contains(":") else 7
			var st := CState.new_campaign("Test", sd, picks, {}, [], CData.pack)
			var data := {"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}
			var sl := Saves.slot_for("test", sd)
			Saves.save(sl, data)
			_open_campaign.call_deferred(data, sl)
		elif a.begins_with("--story="):
			# Testing aid: --story=seed[:turns] starts the story campaign (game/campaign/story_view.gd
			# autoplay: turns played with the first allowed choice); --story-seen=N: the first N log entries read.
			var sspec: String = a.get_slice("=", 1)
			var sdata: Dictionary = (load("res://game/campaign/story_view.gd") as GDScript).call("autoplay",
				int(sspec.get_slice(":", 0)), int(sspec.get_slice(":", 1)) if sspec.contains(":") else 0)  # (--story-coop: two captains)
			for a3 in OS.get_cmdline_user_args():
				if a3.begins_with("--story-seen="):
					sdata["session"]["story_seen"] = int(a3.get_slice("=", 1))
			var ssl := Saves.slot_for("story test", int(sspec.get_slice(":", 0)))
			Saves.save(ssl, sdata)
			_open_campaign.call_deferred(sdata, ssl)
		elif a.begins_with("--campaign-slot="):
			var sl2: String = a.get_slice("=", 1)
			var d2 := Saves.load_slot(sl2)
			if not d2.is_empty():
				_open_campaign.call_deferred(d2, sl2)
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
		elif net.launch.has("custom"):
			_open_custom()
			custom._code_edit.text = str(net.launch["custom"])
			custom._join.call_deferred()
		elif net.launch.has("join"):
			show_page("join")
			_join_edit.text = NetScript.show_code(str(net.launch["join"]))
			_join_find.call_deferred()


func _net() -> Node:
	return get_node_or_null("/root/Net")


## The server's state for the Grand Campaign page: kind is "ready", "invite", "down" or "checking" (the dot's colour),
## word what follows "Server: <host> - ".
func _server_state(kind: String, word: String) -> void:
	var col: Color = {"ready": Kit.COL_GOOD, "invite": Kit.COL_GOLD, "down": Kit.COL_BAD}.get(kind, Kit.COL_DIM)
	var net := _net()
	var host := "no server"
	if net != null and net.has_server():
		host = net.server_url().trim_prefix("https://").trim_prefix("http://").trim_suffix("/")
	if _net_line != null:
		_net_line.text = "Server: %s - %s" % [host, word]
		_net_line.set_meta("kind", kind)
		_net_dot.set_col(col)
	if _srv_label != null:
		_srv_label.text = "Game server: %s%s" % [host, " (default)" if net != null and net.has_server() and net.is_default() else ""]
		_srv_dot.set_col(col)


## Is the campaign server there? (The Grand Campaign page says.)
func _check_server() -> void:
	var net := _net()
	if net == null or _net_line == null:
		return
	if not net.has_server():
		_server_state("down", "none chosen (see Change)")
		return
	_server_state("checking", "checking...")
	var ok: bool = await net.check_server()
	if ok:
		var d: Dictionary = net.describe_info(net.info)
		if bool(d["mismatch"]):
			_server_state("down", "another version of the game")
		elif not bool(d["ok"]):
			_server_state("down", "not a game server")
		else:
			_server_state("invite" if bool(d["invite_required"]) else "ready", "invite key needed" if bool(d["invite_required"]) else "ready")
		if net.new_build_available:
			_net_line.text += " - newer version, reload the page"
	else:
		var t = net.launch.get("server_result", null)
		_server_state("down", "not reachable")
		Kit.tip(_net_line, "Game server", str(t["text"]) if t is Dictionary and not bool(t["ok"]) else "The game server is not available: online play is off; local play works as usual.")
	if _server_page != null:
		_server_page.refresh()


func _build_menu() -> Control:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg = MenuBg.new()
	bg.add_child(_bg)
	_pages["home"] = _build_home(bg)
	_pages["campaign"] = _build_campaign(bg)
	_pages["grand"] = _build_grand(bg)
	_pages["battles"] = _build_battles(bg)
	_pages["options"] = _build_options(bg)
	_pages["import"] = _build_import(bg)
	_pages["join"] = _build_join(bg)
	_pages["share"] = _build_share(bg)
	_pages["server"] = _build_server(bg)
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
	Kit.tip(_terrain_button, "Terrain", "The ground for the three playable battles; the tests have their own.")
	row.add_child(_terrain_button)
	_ground_button = _menu_button("", _cycle_ground)
	Kit.tip(_ground_button, "Ground", "The region look and the woods: plain (no woods), arid, dry, green or rocky.")
	row.add_child(_ground_button)
	_ai_button = _menu_button("", _cycle_ai_skill)
	Kit.tip(_ai_button, "Battle AI", "How well the enemy plays. Easy and Skilled play like Average for now.")
	row.add_child(_ai_button)
	_update_ai_button()
	row.add_child(_menu_button("Custom battle", _open_custom))
	_replay_button = _menu_button("Replay last battle", _replay)
	Kit.tip(_replay_button, "Replay", "The same battle with the same seed and the same ground.")
	_replay_button.disabled = true
	row.add_child(_replay_button)
	row.add_child(_menu_button("Unit book", _open_book))
	_tests_button = _menu_button("Tests and benchmarks  +", _toggle_tests)
	_tests_button.visible = MenuPrefs.dev() or "--menu-tests" in OS.get_cmdline_user_args()
	row.add_child(_tests_button)
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
		Kit.tip(tb, "Test scenario", Scenarios.title(id))
		grid.add_child(tb)
	_tests_box = grid
	var help := Label.new()
	help.text = "Tap a unit or its card to select; All / Inf / Missile / Cav select groups, + Add adds by tapping cards.\nDrag to draw the front line. Tap ground to move, tap an enemy to attack (missile troops and artillery\nshoot it), double tap to run. Contour lines are 2 m apart: high ground helps. Long press a card: unit book.\nSettlements: select engines or foot and tap a gate to break it; defending, tap a gate (nothing selected) to open or shut it."
	help.add_theme_font_size_override("font_size", 13)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(1, 1, 1, 0.75)
	vb.add_child(help)
	_help = help
	_back_btn = Kit.button("< Back", go_back, 110, 16)
	_back_btn.name = "menu_back"
	_back_btn.position = Vector2(14, 10)
	_back_btn.visible = false
	bg.add_child(_back_btn)
	return bg


## A menu page: a touch-scrollable full-screen area with its content centred
## (scrolls when the content is taller than a phone screen).
func _scroll_page(bg: Control) -> CenterContainer:
	var scroll := TouchScroll.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 56
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


# ------------------------------------------------------------ title menu ---

func _heading(text: String, fsize: int = 28) -> Label:
	var l := Kit.label(text, fsize, Kit.COL_GOLD)
	MenuStyle.use_display(l, fsize)
	return l


func _is_phone() -> bool:
	return UiScale.is_touch() and get_viewport_rect().size.y < 520.0


## The title screen: the wordmark top-left, a stack of entries over the background (centred on phones).
func _build_home(bg: Control) -> Control:
	var home := Control.new()
	home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	home.visible = false
	home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(home)
	_home = home
	# Wordmark: the last-played setting's emblem and the title in the display face.
	_home_mark = HBoxContainer.new()
	_home_mark.add_theme_constant_override("separation", 14)
	_home_mark.position = Vector2(30, 22)
	home.add_child(_home_mark)
	_home_emblem = Emblem.make("rome", 64)
	_home_emblem.name = "home_emblem"
	_home_mark.add_child(_home_emblem)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	_home_mark.add_child(tv)
	var title := Kit.label("STRATEGIC COMMAND", 34, Color(1, 0.92, 0.7))
	MenuStyle.use_display(title, 34)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.04))
	title.add_theme_constant_override("outline_size", 6)
	title.name = "home_title"
	tv.add_child(title)
	_subtitle = Kit.label(PackView.subtitle("rome"), 14, Kit.COL_DIM)
	tv.add_child(_subtitle)
	# The entries.
	_home_stack = VBoxContainer.new()
	_home_stack.add_theme_constant_override("separation", 6)
	home.add_child(_home_stack)
	_continue_entry = _entry("Continue", "home_continue", _continue_recent)
	_continue_emblem = Emblem.make("rome", 34)
	_continue_emblem.position = Vector2(6, 10)
	_continue_entry.add_child(_continue_emblem)
	_entry("Campaign", "home_campaign", show_page.bind("campaign"))
	_entry("Grand Campaign", "home_grand", show_page.bind("grand"))
	_entry("Battles", "home_battles", show_page.bind("battles"))
	_entry("Options", "home_options", show_page.bind("options"))
	var info := Kit.label("Godot %s, %s renderer" % [Engine.get_version_info()["string"],
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")], 12, Color(1, 1, 1, 0.45))
	_home_info = info
	info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	info.offset_left = 30
	info.offset_top = -30
	home.add_child(info)
	_build_selector(home)
	_layout_home()
	return home


## A chevron drawn in code (the kit has no chevron icon): dir -1 points left, +1 right.
class Chevron extends Control:
	var dir := 1
	func _draw() -> void:
		var c := size * 0.5
		var h := minf(size.x, size.y) * 0.2
		var a := Vector2(-dir * h * 0.6, 0.0) + c
		var pts := PackedVector2Array([a + Vector2(dir * h, -h * 1.5), a + Vector2(dir * h * 2.0, 0.0), a + Vector2(dir * h, h * 1.5)])
		draw_polyline(pts, Color(Kit.COL_BONE, 0.95), 2.5, true)


## The background selector, bottom centre of the title screen: a gold rule, then [<] name [>].
func _build_selector(home: Control) -> void:
	_sel = VBoxContainer.new()
	_sel.name = "bg_selector"
	_sel.add_theme_constant_override("separation", 8)
	_sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home.add_child(_sel)
	var rl := Kit.rule(Color(Kit.COL_GOLD, 0.55))
	rl.custom_minimum_size = Vector2(0, 1)
	_sel.add_child(rl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_sel.add_child(row)
	_sel_prev = _sel_arrow(-1)
	row.add_child(_sel_prev)
	# the middle is the swipe zone (a drag along it steps the choice)
	_sel_zone = Control.new()
	_sel_zone.name = "bg_zone"
	_sel_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	_sel_zone.gui_input.connect(_on_sel_input)
	row.add_child(_sel_zone)
	_sel_label = Kit.label("", 18, Kit.COL_BONE)
	_sel_label.name = "bg_label"
	_sel_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sel_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sel_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuStyle.use_display(_sel_label, 18)
	_sel_label.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.04, 0.9))
	_sel_label.add_theme_constant_override("outline_size", 5)
	_sel_zone.add_child(_sel_label)
	_sel_next = _sel_arrow(1)
	row.add_child(_sel_next)
	_layout_selector()


func _sel_arrow(dir: int) -> Button:
	var b := Button.new()
	b.name = "bg_prev" if dir < 0 else "bg_next"
	b.focus_mode = Control.FOCUS_NONE
	Kit.nav_style(b)
	b.pressed.connect(AudioFx.click)
	b.pressed.connect(_step_bg.bind(dir))
	var ch := Chevron.new()
	ch.dir = dir
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(ch)
	Kit.tip(b, "Menu picture", "Step to the %s background." % ("previous" if dir < 0 else "next"))
	return b


func _layout_selector() -> void:
	if _sel == null:
		return
	var ph := _is_phone()
	var bs := 36.0 if ph else 44.0
	for b in [_sel_prev, _sel_next]:
		(b as Control).custom_minimum_size = Vector2(bs, bs)
	_sel_zone.custom_minimum_size = Vector2(clampf(get_viewport_rect().size.x - 2.0 * bs - 44.0, 200.0, 340.0), bs)
	MenuStyle.use_display(_sel_label, 16 if ph else 18)
	_sel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_sel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_sel.offset_bottom = -(10.0 if ph else 24.0)
	_sel.offset_top = _sel.offset_bottom - (bs + 9.0)


func _on_sel_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_sel_press = (ev as InputEventMouseButton).position
		else:
			var dx: float = (ev as InputEventMouseButton).position.x - _sel_press.x
			if absf(dx) >= 40.0:
				_step_bg(-1 if dx > 0.0 else 1)   # (dragging right pulls the previous picture in)
	elif ev is InputEventScreenTouch:
		if ev.pressed:
			_sel_press = (ev as InputEventScreenTouch).position
		else:
			var dx2: float = (ev as InputEventScreenTouch).position.x - _sel_press.x
			if absf(dx2) >= 40.0:
				_step_bg(-1 if dx2 > 0.0 else 1)


## Step the background selector (wraps) and keep the choice.
func _step_bg(dir: int) -> void:
	if _bg == null:
		return
	var n := MenuPrefs.BACKGROUNDS.size()
	var i := MenuPrefs.BACKGROUNDS.find(_current_bg())
	_set_bg(MenuPrefs.BACKGROUNDS[(i + dir + n) % n], true)


func _current_bg() -> String:
	return _bg_choice if _bg_choice != "" else MenuPrefs.stored_background(_last_pack())


func _set_bg(c: String, switch: bool) -> void:
	_bg_choice = c
	MenuPrefs.set_background(c)
	if switch and _bg != null:
		_bg.switch_to(c)
	_apply_wordmark()


## The wordmark's emblem and subtitle and the selector's name follow the selected background's setting.
func _apply_wordmark() -> void:
	var c := _current_bg()
	var pk := MenuPrefs.pack_of(c)
	if _sel_label != null:
		_sel_label.text = str(MenuPrefs.LABELS[c])
	if _home_emblem != null:
		(_home_emblem as Emblem).pack = pk
		_home_emblem.queue_redraw()
	if _subtitle != null:
		_subtitle.text = PackView.subtitle(pk)


## One entry of the stack: a wrapper (so the slide-in can move the button) holding a flat button.
func _entry(text: String, nm: String, cb: Callable) -> Button:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(380, 54)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var b := Button.new()
	b.text = text
	b.name = nm
	b.focus_mode = Control.FOCUS_NONE
	b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.pressed.connect(AudioFx.click)
	b.pressed.connect(cb)
	MenuStyle.entry_style(b, 26, false)
	holder.add_child(b)
	_home_stack.add_child(holder)
	_entries.append(holder)
	return b


## Place the wordmark and the stack: left side on a desktop, centred on a phone.
func _layout_home() -> void:
	if _home == null or _home_stack == null:
		return
	var sz := get_viewport_rect().size
	_phone_layout = _is_phone()
	var fs := 22 if _phone_layout else 26
	for w in _entries:
		var b: Button = w.get_child(0)
		b.add_theme_font_size_override("font_size", fs)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER if _phone_layout else HORIZONTAL_ALIGNMENT_LEFT
		var cont := b == _continue_entry
		(w as Control).custom_minimum_size = Vector2(320 if _phone_layout else 380, 42 if _phone_layout else 54)
		b.get_theme_stylebox("normal").content_margin_left = (60.0 if cont else 6.0)
		b.get_theme_stylebox("hover").content_margin_left = (64.0 if cont else 10.0)
		b.get_theme_stylebox("pressed").content_margin_left = (64.0 if cont else 10.0)
	if _continue_emblem != null:
		var h := 42.0 if _phone_layout else 54.0
		_continue_emblem.custom_minimum_size = Vector2(h - 14.0, h - 14.0)
		_continue_emblem.size = Vector2(h - 14.0, h - 14.0)
		_continue_emblem.position = Vector2(8, 7)
	_home_stack.add_theme_constant_override("separation", 2 if _phone_layout else 6)
	if _phone_layout:
		_home_stack.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
		_home_stack.offset_top += 24
		_home_stack.offset_bottom += 24
		_home_mark.position = Vector2(14, 8)
		_home_emblem.custom_minimum_size = Vector2(40, 40)
	else:
		_home_stack.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE)
		var ml := maxf(40.0, sz.x * 0.07)
		_home_stack.offset_left = ml
		_home_stack.offset_right = ml + 380
		_home_mark.position = Vector2(30, 22)
		_home_emblem.custom_minimum_size = Vector2(64, 64)
	_layout_selector()
	_home_info.visible = not _phone_layout   # (the engine line would sit under the selector on a phone)
	_home_stack.grow_horizontal = Control.GROW_DIRECTION_BOTH if _phone_layout else Control.GROW_DIRECTION_END
	_home_stack.grow_vertical = Control.GROW_DIRECTION_BOTH


## The most recent save, local or online (online ones are ordered by when they were added: no play time is kept).
func _find_recent() -> Dictionary:
	var best := {}
	var list := Saves.list()
	if not list.is_empty():
		var m: Dictionary = list[0]
		best = {"kind": "local", "slot": str(m["slot"]), "name": str(m.get("name", m["slot"])), "turn": int(m.get("turn", 0)) + 1,
			"pack": str(m.get("pack", "rome")), "at": int(m.get("saved_at", 0))}
	var net := _net()
	if net != null:
		for e in net.local_campaigns():
			var at := int(e.get("added_at", 0))
			if best.is_empty() or at > int(best["at"]):
				best = {"kind": "online", "id": str(e["id"]), "name": str(e.get("name", e["id"])), "turn": 0,
					"pack": str(e.get("pack", "rome")), "at": at}
			break
	return best


## The setting of the last-played campaign (else the last chosen on the new-campaign screen).
func _last_pack() -> String:
	var aid := MenuPrefs.pack_aid()
	if aid != "" and CData.has_pack(aid):
		return aid
	var r := _find_recent() if _recent.is_empty() else _recent
	var p := str(r.get("pack", "")) if not r.is_empty() else ""
	return p if p != "" and CData.has_pack(p) else PackView.load_pref()


func _update_home() -> void:
	_recent = _find_recent()
	var has := not _recent.is_empty()
	(_continue_entry.get_parent() as Control).visible = has
	if has:
		var t := "Continue: %s" % _recent["name"]
		if str(_recent["kind"]) == "local":
			t += ", turn %d" % int(_recent["turn"])
		else:
			t += ", online"
		_continue_entry.text = t
		Kit.tip(_continue_entry, "Continue", t)
		(_continue_emblem as Emblem).pack = str(_recent["pack"])
		_continue_emblem.queue_redraw()
	_apply_wordmark()
	_layout_home()


func _continue_recent() -> void:
	if _recent.is_empty():
		return
	if str(_recent["kind"]) == "online":
		_open_online(str(_recent["id"]))
		return
	var sl := str(_recent["slot"])
	var d := Saves.load_slot(sl)
	if not d.is_empty():
		_open_campaign(d, sl)


## The entries slide in from the left, 0.25 s each, staggered.
func _slide_in(nodes: Array) -> void:
	var i := 0
	for w in nodes:
		var holder: Control = w
		if not holder.visible:
			continue
		var b: Control = holder.get_child(0)
		b.modulate.a = 0.0
		b.position.x = -40.0
		var tw := b.create_tween()
		tw.tween_interval(0.07 * i)
		tw.tween_property(b, "position:x", 0.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(b, "modulate:a", 1.0, 0.25)
		i += 1


func _pack_card(pack: String, label: String) -> Button:
	var b := Button.new()
	b.name = "card_" + pack
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(250, 220)
	MenuStyle.card_style(b)
	b.pressed.connect(AudioFx.click)
	b.pressed.connect(_new_campaign_page.bind(false, pack))
	b.mouse_entered.connect(func(): _bg.show_pack(pack))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_right = -12
	v.offset_top = 12
	v.offset_bottom = -12
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(v)
	var em := Emblem.make(pack, 96)
	em.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(em)
	var t := Kit.label(label, 22, Color(1, 0.92, 0.7))
	MenuStyle.use_display(t, 22)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var sub := Kit.label(PackView.subtitle(pack), 13, Kit.COL_DIM, true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sub)
	return b


## Campaign (single player): the two settings as cards, then this device's saved campaigns and Import.
func _build_campaign(bg: Control) -> Control:
	var vb := _page_box(bg)
	vb.add_child(_heading("Campaign"))
	vb.add_child(Kit.label("One player, or several taking turns on this device. Pick a setting to begin.", 14, Kit.COL_DIM))
	var cards := HFlowContainer.new()
	cards.add_theme_constant_override("h_separation", 16)
	cards.add_theme_constant_override("v_separation", 12)
	cards.alignment = FlowContainer.ALIGNMENT_CENTER
	for key in ["west", "rome"]:
		if CData.has_pack(key):
			cards.add_child(_pack_card(key, CARD_TITLES[key]))
	vb.add_child(cards)
	var yh := Kit.hbox(8)
	yh.add_child(Kit.label("Your campaigns", 20, Kit.COL_GOLD))
	vb.add_child(yh)
	_continue_box = Kit.vbox(6)
	_continue_box.custom_minimum_size.x = 560
	_continue_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_continue_box)
	var imp := _menu_button("Import a campaign", show_page.bind("import"))
	imp.name = "home_Import"
	vb.add_child(imp)
	return vb.get_parent().get_parent()


const CARD_TITLES := {"west": "The Caribbean, 1650", "rome": "Rome, 280 BC"}


## The page's content width: the two cards side by side, or the screen's width on a phone.
func _grand_width() -> float:
	return minf(740.0, get_viewport_rect().size.x - 32.0)


## Grand Campaign (online co-op): the Host card and the Join card, this device's online campaigns, the game server.
func _build_grand(bg: Control) -> Control:
	var vb := _page_box(bg)
	_grand_col = vb
	vb.add_theme_constant_override("separation", 12)
	vb.add_child(_heading("Grand Campaign"))
	var intro := Kit.label("Online co-op: each player on their own device; the turn resolves when everyone has submitted.", 14, Kit.COL_DIM, true)
	intro.name = "grand_intro"
	vb.add_child(intro)
	_grand_cards = BoxContainer.new()
	_grand_cards.name = "grand_cards"
	_grand_cards.add_theme_constant_override("separation", 14)
	vb.add_child(_grand_cards)
	_grand_cards.add_child(_build_host_card())
	_grand_cards.add_child(_build_join_card())
	vb.add_child(Kit.title("Your grand campaigns", 20))
	_online_box = Kit.vbox(6)
	_online_box.name = "online_box"
	_online_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_online_box)
	# The server row.
	var sp := Kit.panel(Color(0.07, 0.06, 0.05, 0.9), 8)
	sp.name = "server_row"
	var sh := Kit.hbox(8)
	sp.add_child(sh)
	_srv_dot = Kit.dot(Kit.COL_DIM)
	sh.add_child(_srv_dot)
	_srv_label = Kit.label("Game server", 14, Kit.COL_BONE)
	_srv_label.name = "server_row_label"
	_srv_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_srv_label.clip_text = true
	sh.add_child(_srv_label)
	var chg := Kit.button("Change", show_page.bind("server"), 100, 14)
	chg.name = "home_server"
	Kit.nav_style(chg)
	Kit.tip(chg, "Game server", "Which server online play uses: the default one, a friend's or your own, and hosting one from this PC.")
	sh.add_child(chg)
	vb.add_child(sp)
	_layout_grand()
	return vb.get_parent().get_parent()


## Cards side by side on a roomy screen, stacked on a phone; the column as wide as the cards.
func _layout_grand() -> void:
	if _grand_cards == null:
		return
	var w := _grand_width()
	_phone_layout = _is_phone()
	_grand_cards.vertical = w < 640.0 or _phone_layout
	for c in _grand_cards.get_children():
		(c as Control).custom_minimum_size.x = w if _grand_cards.vertical else (w - 14.0) * 0.5
		(c as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grand_col.custom_minimum_size.x = w


func _card_panel(nm: String) -> PanelContainer:
	var card := Kit.trim_panel(Color(0.06, 0.055, 0.045, 0.93), 14)
	card.name = nm
	return card


## Host a grand campaign: the setting (two mini-cards), Host, and the server's state under it.
func _build_host_card() -> Control:
	var card := _card_panel("host_card")
	var v := Kit.vbox(8)
	card.add_child(v)
	v.add_child(Kit.title("Host a grand campaign", 20))
	v.add_child(Kit.label("Pick a setting, then choose who plays each faction. The others join with a code.", 13, Kit.COL_DIM, true))
	var pr := Kit.hbox(8)
	var first := ""
	for key in ["west", "rome"]:
		if not CData.has_pack(key):
			continue
		if first == "":
			first = key
		var b := Kit.button("", _gh_select.bind(key), 0, 14)
		b.name = "host_pack_" + key
		b.custom_minimum_size = Vector2(0, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var inner := Kit.hbox(8)
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 8
		inner.offset_right = -6
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		var em := Kit.emblem(key, 36)
		em.mouse_filter = Control.MOUSE_FILTER_IGNORE
		em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		inner.add_child(em)
		var tv := Kit.vbox(0)
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tl := Kit.label(str(CARD_TITLES[key]).get_slice(", ", 0), 15, Kit.COL_BONE)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(tl)
		var yl := Kit.label(str(CARD_TITLES[key]).get_slice(", ", 1), 12, Kit.COL_DIM)
		yl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(yl)
		inner.add_child(tv)
		b.add_child(inner)
		Kit.tip(b, CARD_TITLES[key], PackView.subtitle(key))
		pr.add_child(b)
		_gh_cards[key] = b
	v.add_child(pr)
	if not _gh_cards.has(_gh_pack):
		_gh_pack = first
	var hb := Kit.hero_button("Host", "", func(): _new_campaign_page(true, _gh_pack), 0, 20)
	hb.name = "home_Online_co-op"
	Kit.tip(hb, "Host a grand campaign", "Opens the faction page for the chosen setting: pick the humans (two at least) and the rules, then send the join code.")
	v.add_child(hb)
	var st := Kit.hbox(8)
	_net_dot = Kit.dot(Kit.COL_DIM)
	st.add_child(_net_dot)
	_net_line = Kit.label("", 13, Kit.COL_DIM, true)
	_net_line.name = "net_line"
	_net_line.mouse_filter = Control.MOUSE_FILTER_STOP
	_net_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.add_child(_net_line)  # (the Change button is the Game server row's at the foot of the page, 2026-10-23: one, not two)
	v.add_child(st)
	_gh_select(_gh_pack)
	return card


## The Host card's setting: the picked mini-card is lit.
func _gh_select(key: String) -> void:
	_gh_pack = key
	for k in _gh_cards:
		var b: Button = _gh_cards[k]
		var on: bool = k == key
		var cols := {"normal": [Color(0.30, 0.22, 0.08, 1.0) if on else Color(0.11, 0.13, 0.12, 0.94), Kit.COL_GOLD if on else Color(Kit.COL_RULE, 0.6)],
			"hover": [Color(0.36, 0.27, 0.10, 1.0) if on else Color(0.17, 0.19, 0.16, 0.97), Kit.COL_GOLD],
			"pressed": [Color(0.40, 0.30, 0.11, 1.0), Color(1.0, 0.9, 0.55)]}
		for st in cols:
			var sb := Kit.box(cols[st][0], 6.0, 5)
			sb.set_border_width_all(2 if on else 1)
			sb.border_color = cols[st][1]
			b.add_theme_stylebox_override(st, sb)
		b.add_theme_stylebox_override("focus", b.get_theme_stylebox("normal"))
		b.set_meta("on", on)


## Join a grand campaign: a code field (uppercase as typed), Paste, Join, and the result under it.
func _build_join_card() -> Control:
	var card := _card_panel("join_card")
	var v := Kit.vbox(8)
	card.add_child(v)
	v.add_child(Kit.title("Join a grand campaign", 20))
	v.add_child(Kit.label("Enter the code from the player who hosts, or a device code to carry your own campaign here.", 13, Kit.COL_DIM, true))
	var h := Kit.hbox(6)
	_gj_edit = Kit.text_field("Join code", "", 120, "Join code or device code", true)
	_gj_edit.name = "grand_join_code"
	_gj_edit.custom_minimum_size = Vector2(120, 48)
	_gj_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gj_edit.add_theme_font_size_override("font_size", 20)
	_gj_edit.max_length = 300  # a whole link can be pasted
	_gj_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_gj_edit.text_changed.connect(func(t: String):
		var up: String = t.to_upper()
		if up != t:
			var c := _gj_edit.caret_column
			_gj_edit.text = up
			_gj_edit.caret_column = c)
	_gj_edit.text_submitted.connect(func(_t): _join_find_in(_gj_edit, _gj_info, _gj_box))
	Kit.tip(_gj_edit, "Codes", "A join code has 6 characters, a device code 8 (letters and digits; no 0, 1, I, L, O, U or V). A whole invite link works too.")
	h.add_child(_gj_edit)
	var pb := Kit.button("Paste", func(): Kit.paste_into(_gj_edit), 70, 14)
	pb.name = "grand_join_paste"
	pb.custom_minimum_size.y = 48
	Kit.nav_style(pb)
	Kit.arm_paste(pb)
	h.add_child(pb)
	var jb := Kit.hero_button("Join", "", func(): _join_find_in(_gj_edit, _gj_info, _gj_box), 80, 18)
	jb.name = "grand_join"
	h.add_child(jb)
	v.add_child(h)
	_gj_info = Kit.label("", 13, Kit.COL_BAD, true)
	_gj_info.name = "grand_join_info"
	_gj_edit.set_meta("hint", _gj_info)
	v.add_child(_gj_info)
	_gj_box = Kit.vbox(8)
	_gj_box.name = "grand_join_box"
	v.add_child(_gj_box)
	return card


## Battles: a custom battle, or the sandbox with its fixed scenarios.
func _build_battles(bg: Control) -> Control:
	var vb := _page_box(bg)
	vb.add_child(_heading("Battles"))
	vb.add_child(Kit.label("Real-time battles without a campaign.", 14, Kit.COL_DIM))
	for d in [["Custom battle", "home_custom", _open_custom, "Pick the armies, the ground and the sides; play alone or with a friend online."],
			["Battle sandbox", "home_sandbox", show_page.bind("sandbox"), "The ready-made battles and settlement sieges, with ground and AI choices."]]:
		var b := _menu_button(d[0], d[2])
		b.name = d[1]
		b.custom_minimum_size = Vector2(420, 56)
		b.add_theme_font_size_override("font_size", 19)
		vb.add_child(b)
		var l := Kit.label(d[3], 13, Kit.COL_DIM, true)
		l.custom_minimum_size.x = 420
		vb.add_child(l)
	return vb.get_parent().get_parent()


## Options: display, looks, audio and help as rows (game/menu/options_rows.gd, shared with the in-game Menu), in a
## panel so they read over any picture. Tests and benchmarks only with --dev.
func _build_options(bg: Control) -> Control:
	var vb := _page_box(bg)
	vb.add_child(_heading("Options"))
	var panel := Kit.trim_panel(Color(0.06, 0.055, 0.045, 0.93), 16)
	panel.name = "options_panel"
	vb.add_child(panel)
	var inner := Kit.vbox(8)
	inner.name = "options_rows"
	var narrow := _is_phone() or get_viewport_rect().size.x < 720.0
	inner.custom_minimum_size.x = minf(660.0, get_viewport_rect().size.x - 72.0)
	panel.add_child(inner)
	_opts = OptionsRows.new()
	_opts.build(inner, {"prefix": "home", "narrow": narrow, "title": true, "dev": MenuPrefs.dev(), "win": get_window(),
		"on_controls": _open_controls, "on_book": _open_book, "on_tests": _open_tests, "on_size": _fit_options_later})
	_options_box = vb
	return vb.get_parent().get_parent()


var _options_box: Control = null


func _fit_options_later() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_fit_options()


## The Options page needs no scroll on a short wide window (1024x576 at UI size M): tighter rows, the audio sliders
## side by side, then no description lines (OptionsRows.fit). Phones keep the narrow layout and scroll.
func _fit_options() -> void:
	if _opts == null or _options_box == null or not is_instance_valid(_options_box) or not _options_box.is_visible_in_tree():
		return
	var scroll: Control = _options_box.get_parent().get_parent()
	_opts.fit(func(): return _options_box.get_combined_minimum_size().y <= scroll.size.y)


func _open_tests() -> void:
	show_page("sandbox")
	if not _tests_box.visible:
		_toggle_tests()


## Start (or refresh) the background for the current setting; the diorama is built a frame later.
func _activate_bg() -> void:
	if _bg == null or not _menu.visible:
		return
	var lp := _last_pack()
	MenuPrefs.migrate(lp)
	_bg_choice = MenuPrefs.background_pref(lp)
	_bg.activate(_bg_choice)
	_apply_wordmark()


func _menu_visibility() -> void:
	if _menu.visible:
		_activate_bg.call_deferred()
		_update_home()
	elif _bg != null:
		_bg.deactivate()


func _fill_continue() -> void:
	for c in _continue_box.get_children():
		c.queue_free()
	var list := Saves.list()
	if list.is_empty():
		_continue_box.add_child(Kit.label("No saved campaigns yet.", 15, Kit.COL_DIM))
	for m in list:
		var h := Kit.hbox(6)
		var sl := str(m["slot"])
		h.add_child(Emblem.make(str(m.get("pack", "rome")), 32))
		var b := _menu_button("%s - %s - %s" % [m.get("name", sl), " & ".join(m.get("factions", [])), m.get("date", "")], Callable())
		b.pressed.connect(func():
			# (off at once: a second tap cannot open it twice; the panel follows in the same frame)
			b.disabled = true
			var d := Saves.load_slot(sl)
			if not d.is_empty():
				_open_campaign(d, sl)
			else:
				b.disabled = false)
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


## An online seat's faction, read under its campaign's pack (restored after): {name, mark}.
func _seat_info(e: Dictionary) -> Dictionary:
	var keep := CData.pack
	PackView.use_pack(str(e.get("pack", "rome")))
	var f := int(e["f"])
	var out := {"name": CData.faction_name(f), "mark": Kit.faction_mark(f, 22)}
	PackView.use_pack(keep)
	return out


## Online campaigns this device has a seat in, with live status badges: one row each (the setting's emblem, the
## campaign's name, your faction and the turn, the badge, Resume and a small x to forget it).
func _fill_online() -> void:
	for c in _online_box.get_children():
		c.queue_free()
	var net := _net()
	if net == null:
		_online_box.add_child(Kit.label("Online play needs the game server.", 14, Kit.COL_DIM))
		return
	var list: Array = net.local_campaigns()
	if list.is_empty():
		var el := Kit.label("No grand campaigns on this device yet. Host one above, or join with a code.", 14, Kit.COL_DIM, true)
		el.name = "online_empty"
		_online_box.add_child(el)
		return
	var badges := {}
	for e in list:
		var cid := str(e["id"])
		var row := Kit.panel(Color(0.06, 0.055, 0.045, 0.92), 8)
		row.name = "grow_" + cid
		var h := Kit.hbox(10)
		row.add_child(h)
		var em := Emblem.make(str(e.get("pack", "rome")), 40)
		em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(em)
		var info := _seat_info(e)
		var mid := Kit.vbox(2)
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nl := Kit.label(str(e.get("name", cid)), 16, Kit.COL_BONE)
		nl.clip_text = true
		nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nl.custom_minimum_size.x = 40
		mid.add_child(nl)
		var fr := Kit.hbox(6)
		fr.add_child(info["mark"])
		var fl := Kit.label(str(info["name"]), 13, Kit.COL_DIM)
		fl.name = "faction"
		fr.add_child(fl)
		var tl := Kit.label("", 13, Kit.COL_DIM)
		tl.name = "turn"
		fr.add_child(tl)
		mid.add_child(fr)
		h.add_child(mid)
		var badge := Kit.label("..." if net.has_server() else "Offline", 13, Kit.COL_DIM, true)
		badge.custom_minimum_size.x = 110
		badge.size_flags_horizontal = Control.SIZE_SHRINK_END
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.name = "badge"
		h.add_child(badge)
		badges[cid] = {"badge": badge, "turn": tl}
		var rb := Kit.button("Resume", _open_online.bind(cid), 90, 14)
		rb.name = "online_" + cid
		Kit.nav_style(rb)
		h.add_child(rb)
		var del := Kit.button("x", Callable(), 36, 14)
		del.name = "forget_" + cid
		Kit.nav_style(del)
		Kit.tip(del, "Forget this campaign", "Removes it from this device (it stays on the server; the other players keep playing). Press twice to confirm.")
		del.pressed.connect(func():
			if del.text == "Sure?":
				net.accounts.remove(cid)
				_fill_online()
			else:
				del.text = "Sure?"
				del.custom_minimum_size.x = 64
				del.add_theme_color_override("font_color", Kit.COL_BAD))
		h.add_child(del)
		_online_box.add_child(row)
	if net.has_server():
		_update_badges(badges)


func _update_badges(labels: Dictionary) -> void:
	var net := _net()
	var got: Dictionary = await net.refresh_badges()
	for cid in labels:
		var l: Label = labels[cid]["badge"]
		if is_instance_valid(l) and got.has(cid):
			l.text = str(got[cid]["text"])
			l.add_theme_color_override("font_color", got[cid]["color"])
			var sm: Dictionary = got[cid].get("summary", {})
			var tl: Label = labels[cid]["turn"]
			if is_instance_valid(tl) and sm.has("turn"):
				tl.text = " - turn %d" % (int(sm["turn"]) + 1)


func _build_server(bg: Control) -> Control:
	var vb := _page_box(bg)
	var net := _net()
	var pg := ServerPage.new()
	_server_page = pg
	vb.add_child(pg)
	if net != null:
		pg.setup(net)
	pg.back_requested.connect(show_page.bind("grand"))
	return vb.get_parent().get_parent()


func _build_import(bg: Control) -> Control:
	var vb := _page_box(bg)
	vb.add_child(Kit.label("Import a campaign", 22, Kit.COL_GOLD))
	vb.add_child(Kit.label("Paste the text from Export (campaign Menu) on the other device.", 14, Kit.COL_DIM))
	_import_edit = Kit.text_area(Vector2(560, 150))
	_import_edit.name = "import_text"
	vb.add_child(_import_edit)
	_import_info = Kit.label("", 14, Kit.COL_BAD)
	vb.add_child(_import_info)
	_import_edit.set_meta("hint", _import_info)
	var h := Kit.hbox(8)
	h.add_child(_menu_button("Paste", func(): Kit.paste_into(_import_edit)))
	Kit.arm_paste(h.get_child(-1))
	h.add_child(_menu_button("Import and play", _do_import))
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
	vb.add_child(Kit.label("Enter the join code from the campaign's creator, or a device code to continue your own campaign here.", 14, Kit.COL_DIM))
	var h := Kit.hbox(8)
	_join_edit = Kit.text_field("ABC-DEF", "", 240, "Join code or device code", true)
	_join_edit.name = "join_code"
	_join_edit.custom_minimum_size = Vector2(240, 52)
	_join_edit.add_theme_font_size_override("font_size", 26)
	_join_edit.max_length = 300  # a whole link can be pasted
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
	h.add_child(_menu_button("Paste", func(): Kit.paste_into(_join_edit)))
	Kit.arm_paste(h.get_child(-1))
	vb.add_child(h)
	_join_info = Kit.label("", 14, Kit.COL_BAD, true)
	_join_edit.set_meta("hint", _join_info)
	_join_info.custom_minimum_size.x = 520
	vb.add_child(_join_info)
	_join_box = Kit.vbox(8)
	vb.add_child(_join_box)
	return vb.get_parent().get_parent()


func _join_find() -> void:
	_join_find_in(_join_edit, _join_info, _join_box)


## Look up the code in `edit` and show the result in `info` (errors) and `box` (the seats to take): the join page and the
## Grand Campaign page's Join card share this.
func _join_find_in(edit: LineEdit, info: Label, box: VBoxContainer) -> void:
	var net := _net()
	for c in box.get_children():
		c.queue_free()
	info.add_theme_color_override("font_color", Kit.COL_BAD)
	var raw := edit.text
	var full := raw
	# A whole link pasted: take its code.
	for key in ["join=", "link="]:
		if raw.to_lower().contains(key):
			raw = raw.substr(raw.to_lower().find(key) + key.length()).get_slice("&", 0)
	var code: String = NetScript.norm_code(raw)
	if net != null and full.to_lower().contains("server="):
		# A link from a friend's own server: switch to it (an http one is refused in a browser).
		var sv: String = full.substr(full.to_lower().find("server=") + 7).get_slice("&", 0).uri_decode()
		var sr: Dictionary = await net.set_server(sv)
		if not bool(sr["ok"]):
			info.text = str(sr["text"])
			return
	if code.length() != 6 and code.length() != 8:
		info.text = JOIN_HINT
		return
	if net == null or not net.has_server():
		info.text = "Online play needs the game server: open the game from its web address."
		return
	if not net.available and not await net.check_server():
		info.text = "The game server is not available right now, so online play is off. Local play works as usual."
		return
	if code.length() == 8:
		_claim_device_code(code)
		return
	info.add_theme_color_override("font_color", Kit.COL_DIM)
	info.text = "Looking..."
	var r: Dictionary = await net.join_preview(code)
	info.add_theme_color_override("font_color", Kit.COL_BAD)
	if not r["ok"]:
		info.text = _net_error(r, "No open campaign has that code. Check it with the player who sent it (it stops working once every seat is taken).")
		return
	info.text = ""
	var d: Dictionary = CState.normalise(r["data"])
	if int(d.get("format_version", 0)) > CState.VERSION or int(d.get("format_version", 0)) < CState.MIN_VERSION:
		info.text = "That campaign was made by a different version of the game: reload the page to update."
		return
	box.add_child(Kit.label("%s, turn %d." % [d.get("name", ""), int(d.get("turn", 0)) + 1], 17, Color.WHITE))
	var free: Array = []
	var taken: Array[String] = []
	for seat in d["seats"]:
		if bool(seat["claimed"]):
			taken.append(str(seat["name"]))
		else:
			free.append(seat)
	if not taken.is_empty():
		box.add_child(Kit.label("Playing already: " + ", ".join(taken) + ".", 14, Kit.COL_DIM, true))
	if free.is_empty():
		box.add_child(Kit.label("Every seat is taken.", 15, Kit.COL_BAD))
		return
	var du := Kit.text_field("Your Discord user id (optional, for @mentions)", str(net.accounts.data.get("discord_user", "")), 200, "Your Discord user id", true)
	du.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(Kit.field_box(du))
	var row := Kit.flow(8)
	for seat in free:
		var f := int(seat["f"])
		var b := _menu_button("Play as %s" % seat["name"], func(): _join_seat(code, f, du.text.strip_edges(), info))
		b.name = "join_seat_%d" % f
		b.custom_minimum_size = Vector2(200, 48)
		var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
		img.fill(CData.faction_color(f))
		b.icon = ImageTexture.create_from_image(img)
		row.add_child(b)
	box.add_child(row)


const JOIN_HINT := "A join code has 6 characters, a device code 8 (letters and digits; no 0, 1, I, L, O, U or V)."


func _join_seat(code: String, f: int, discord_user: String, info: Label) -> void:
	var net := _net()
	if discord_user != "":
		net.accounts.set_value("discord_user", discord_user)
	info.add_theme_color_override("font_color", Kit.COL_DIM)
	info.text = "Joining..."
	var r: Dictionary = await net.join(code, f, discord_user)
	info.add_theme_color_override("font_color", Kit.COL_BAD)
	if not r["ok"]:
		info.text = _net_error(r, "Could not join.")
		return
	info.text = ""
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
		_share_box.add_child(Kit.label("Send the other players this join code, or the link:", 15, Color.WHITE))
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
	if oc == null or _preparing:
		return
	_preparing = true
	var lp = LoadingPanel.open(get_tree().root, "Preparing the campaign", 5)
	_menu.visible = false
	await lp.step("Contacting the server")
	await oc.prefetch()
	PackView.use_state(oc.st)  # the geometry before the map's bakes
	var ent: Dictionary = _net().accounts.get_entry(oc.id) if _net() != null else {}
	if not ent.is_empty() and str(ent.get("pack", "rome")) != CData.pack:
		ent["pack"] = CData.pack  # (so the menu names the seat's faction right)
		_net().accounts.save()
	await _prepare_map(lp)
	await lp.step("Building the screen")
	campaign = CampaignScreen.new()
	campaign.open_online(oc)
	campaign.exit_requested.connect(_close_campaign)
	get_tree().root.add_child(campaign)
	await _finish_loading(lp)


func show_page(p: String) -> void:
	if p == "continue":
		p = "campaign"   # (the old Continue page: its list is Your campaigns now)
	if not _pages.has(p):
		p = "home"
	page = p
	for k in _pages:
		(_pages[k] as Control).visible = k == p
	if _back_btn != null:
		_back_btn.visible = p != "home"
	if _bg != null:
		_bg.set_dim((0.45 if _phone_layout else 0.0) if p == "home" else 0.66, p == "home")
		if p == "home" and _bg_choice != "":
			_bg.show_pack(MenuPrefs.pack_of(_bg_choice))   # (a setting card may have shown the other picture)
	if p == "campaign":
		_fill_continue()
	if p == "grand":
		_fill_online()
		_check_server()
	if p == "server" and _server_page != null:
		_server_page.refresh()
	if p == "options" and _opts != null:
		_opts.refresh()
		_fit_options_later()
	if p == "home":
		_update_home()
		if _opts != null:
			_opts.refresh()  # a battle may have switched Soldiers (soldier self-check)
		_slide_in(_entries)


## Back from a sub-page (the button at the top left, Esc, the Android back key).
func go_back() -> void:
	if page != "home":
		show_page(BACK.get(page, "home"))


func _unhandled_input(event: InputEvent) -> void:
	if _menu.visible and page == "home" and not book.visible and not controls.visible and custom == null and _new_campaign == null:
		if event.is_action_pressed("ui_left"):
			_step_bg(-1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_right"):
			_step_bg(1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel") and _menu.visible and page != "home" and not book.visible \
			and not controls.visible and custom == null and _new_campaign == null:
		go_back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _menu != null and _menu.visible and page != "home" \
			and not book.visible and not controls.visible:
		go_back()


func _new_campaign_page(online: bool = false, pack: String = "") -> void:
	_menu.visible = false
	_new_campaign = NewCampaign.new()
	_new_campaign.online = online
	_new_campaign.pack_pick = pack
	_new_campaign.created_online.connect(func(cid, code):
		_new_campaign.queue_free()
		_new_campaign = null
		_show_share(cid, code))
	_new_campaign.start.connect(func(d, sl, lp):
		_new_campaign.queue_free()
		_new_campaign = null
		_open_campaign(d, sl, lp))
	_new_campaign.server_requested.connect(func():
		_new_campaign.queue_free()
		_new_campaign = null
		_menu.visible = true
		show_page("server"))
	_new_campaign.back.connect(func():
		_new_campaign.queue_free()
		_new_campaign = null
		PackView.use_pack("rome")  # the menu's own screens (custom battle) use Rome
		_menu.visible = true)
	add_child(_new_campaign)
	move_child(_new_campaign, _menu.get_index() + 1)


## Open a campaign behind the "Preparing the campaign" panel: lp is the panel
## a new campaign's tap already opened (its first step done), else it opens
## here (a saved game: 4 steps). The map's bakes run a step at a time with a
## frame between, then the screen is built.
func _open_campaign(d: Dictionary, sl: String, lp = null) -> void:
	if campaign != null or _preparing:
		if lp != null:
			lp.close()
		return
	_preparing = true
	if lp == null:
		lp = LoadingPanel.open(get_tree().root, "Preparing the campaign", 4)
	_menu.visible = false
	PackView.use_state(d["state"])  # the geometry before the map's bakes
	await _prepare_map(lp)
	await lp.step("Building the screen")
	campaign = CampaignScreen.new()
	campaign.open(d, sl)
	campaign.exit_requested.connect(_close_campaign)
	get_tree().root.add_child(campaign)
	await _finish_loading(lp)


## The map's bake steps (MapView.prepare_steps) on the panel.
func _prepare_map(lp) -> void:
	for s in MapView.prepare_steps():
		await lp.step(s[0])
		(s[1] as Callable).call()


## The screen is built: let its first frame draw, then drop the panel.
func _finish_loading(lp) -> void:
	await lp.done()
	await get_tree().process_frame
	lp.close()
	_preparing = false


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
	PackView.use_pack("rome")
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
	_siege_seed = Kit.text_field("seed", "1", 96, "Settlement seed", true)
	_siege_seed.custom_minimum_size = Vector2(96, 42)
	Kit.tip(_siege_seed, "Settlement seed", "The same seed, level and walls always give the same map.")
	box.add_child(_siege_seed)
	for key in ["plan", "level", "walls", "kind", "coast", "side", "equip"]:
		var b := _menu_button("", _cycle_siege.bind(key))
		b.custom_minimum_size = Vector2(110, 42)
		_siege_buttons[key] = b
		box.add_child(b)
	var tdd := Kit.dropdown(Kit.TIME_OPTIONS, _siege_time, func(v): _siege_time = int(v), 110, 15)
	tdd.name = "siege_time"
	tdd.custom_minimum_size.y = 42
	box.add_child(tdd)
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
		"plan":
			_siege_plan = (_siege_plan + 1) % (MapGen.PLAN_RING + 1)
		"coast":
			_siege_coast = 1 - _siege_coast
		"equip":
			_siege_equip = (_siege_equip + 1) % 3
	_update_siege_buttons()


func _update_siege_buttons() -> void:
	if _siege_buttons.is_empty():
		return
	(_siege_buttons["level"] as Button).text = ["Village", "Town", "City"][_siege_level]
	(_siege_buttons["walls"] as Button).text = "Walls %d" % _siege_walls
	(_siege_buttons["kind"] as Button).text = Terrain.KIND_NAMES[SIEGE_KINDS[_siege_kind_idx]]
	(_siege_buttons["side"] as Button).text = "You attack" if _siege_def == 1 else "You defend"
	(_siege_buttons["plan"] as Button).text = MapGen.PLAN_NAMES[_siege_plan]
	(_siege_buttons["coast"] as Button).text = "Coast" if _siege_coast != 0 else "Inland"
	(_siege_buttons["equip"] as Button).text = ["No ladders", "Ladders", "Ladders, ram"][_siege_equip]


func _siege_params() -> Array:
	var sd := absi(int(_siege_seed.text)) if _siege_seed.text.is_valid_int() else absi(_siege_seed.text.hash())
	var ground := _ground_idx if _ground_idx > 0 else MapGen.PAL_DRY
	return [sd, _siege_level, _siege_walls, ground, SIEGE_KINDS[_siege_kind_idx], _siege_def, _siege_plan,
		_siege_coast, _siege_equip, _siege_time]


## params: [seed, level, walls, ground, kind, def side, plan, coast,
## siege equipment (0 none, 1 ladders, 2 ladders and a ram), time limit (s)].
func _start_siege(params: Array) -> void:
	if _battle != null:
		return
	_menu.visible = false
	var b := Battle.new()
	b.scenario_id = "settlement"
	var eq := int(params[8]) if params.size() > 8 else 0
	var equip := {}
	if eq >= 1:
		equip["ladders"] = 3
	if eq >= 2:
		equip["ram"] = 1
	b.custom_scenario = Scenarios.siege_test(params[0], params[1], params[2], params[3], params[4], params[5],
		-1, int(params[6]) if params.size() > 6 else MapGen.PLAN_RING, int(params[7]) if params.size() > 7 else 0,
		equip)
	if params.size() > 9 and int(params[9]) >= 60 and int(params[9]) != 900:
		b.custom_scenario["time_limit"] = int(params[9])
	b.ai_skill = _ai_skill
	b.seed_value = _seed if _seed >= 0 else int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	_last_siege = params
	_last_id = "settlement"
	_last_seed = b.seed_value
	_replay_button.disabled = false
	_replay_button.text = "Replay (seed %d)" % b.seed_value
	b.speed_q = Battle.SPEED_PRESETS[clampi(_speed_idx, 0, Battle.SPEED_PRESETS.size() - 1)]
	b.exit_requested.connect(_end_battle)
	_battle = b
	get_tree().root.add_child.call_deferred(b)


func _cycle_ground() -> void:
	_ground_idx = (_ground_idx + 1) % MapGen.PALETTE_NAMES.size()
	_update_ground_button()


func _update_ground_button() -> void:
	if _ground_button != null:
		_ground_button.text = "Ground: " + MapGen.PALETTE_NAMES[_ground_idx].to_lower()


func _cycle_ai_skill() -> void:
	_ai_skill = (_ai_skill + 1) % AI_SKILL_LABELS.size()
	_update_ai_button()


func _update_ai_button() -> void:
	if _ai_button != null:
		_ai_button.text = "AI: " + AI_SKILL_LABELS[_ai_skill]


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
	Kit.install_tips()
	var b := Kit.TipButton.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 42)
	b.add_theme_font_size_override("font_size", 15)
	b.focus_mode = Control.FOCUS_NONE
	MenuStyle.button_style(b)
	b.pressed.connect(AudioFx.click)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


func _open_book() -> void:
	var tele := get_node_or_null("/root/Telemetry")
	if tele != null:
		tele.event("book_open", {"from": "menu"})
	book.open()


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
	b.ai_skill = _ai_skill
	if id in Scenarios.PLAYABLE and _ground_idx > 0:
		b.ground = _ground_idx
	_last_siege = []
	_last_id = id
	_last_seed = sd
	_last_terrain = terrain_kind
	_replay_button.disabled = false
	_replay_button.text = "Replay (seed %d)" % sd
	b.speed_q = Battle.SPEED_PRESETS[clampi(_speed_idx, 0, Battle.SPEED_PRESETS.size() - 1)]
	b.exit_requested.connect(_end_battle)
	_battle = b
	get_tree().root.add_child.call_deferred(b)


func _end_battle() -> void:
	if _battle != null:
		if _battle.coop != null and _battle.has_meta("custom"):
			_battle.coop.leave()
		_battle.queue_free()
		_battle = null
	if custom != null:
		custom.visible = true
		return
	_menu.visible = true
	if _opts != null:
		_opts.refresh()


# --------------------------------------------------------- custom battles ---

func _open_custom() -> void:
	if _bg != null:
		_bg.deactivate()   # (the diorama may have switched the content pack: Rome back before the screen builds)
	if custom == null:
		custom = CustomBattle.new()
		custom.back.connect(func():
			custom.queue_free()
			custom = null
			_menu.visible = true)
		custom.play_solo.connect(_custom_solo)
		custom.play_online.connect(_custom_online)
		add_child(custom)
	_menu.visible = false
	custom.visible = true


func _custom_battle(built: Dictionary, st: Dictionary, me: int) -> Battle:
	var b := Battle.new()
	b.scenario_id = "custom"
	b.custom_scenario = built["scenario"]
	b.seed_value = int(built["seed"])
	b.player_side = maxi(CustomSetup.side_of_player(st, me), 0)
	b.custom_summary = CustomSetup.summary(st)
	b.set_meta("custom", true)
	b.speed_q = Battle.SPEED_PRESETS[clampi(_speed_idx, 0, Battle.SPEED_PRESETS.size() - 1)]
	b.exit_requested.connect(_end_battle)
	return b


func _custom_solo(built: Dictionary, st: Dictionary) -> void:
	if _battle != null:
		return
	custom.visible = false
	if built.has("sea"):
		# (N3a) A sea battle (game/sea_battle.gd).
		var sb := SeaBattle.new()
		sb.scenario = built["scenario"]
		sb.seed_value = int(built["seed"])
		sb.title_text = "Sea battle"
		sb.exit_requested.connect(_end_battle)
		_battle = sb
		get_tree().root.add_child.call_deferred(sb)
		return
	var b := _custom_battle(built, st, 0)
	_battle = b
	get_tree().root.add_child.call_deferred(b)


func _custom_online(session: Node, st: Dictionary) -> void:
	if _battle != null:
		session.leave()
		return
	custom.visible = false
	var b := _custom_battle({"scenario": session.scenario, "seed": session.seed_value}, st, session.me)
	b.coop = session
	b.coop_region = "custom"
	b.add_child(session)
	_battle = b
	get_tree().root.add_child.call_deferred(b)
