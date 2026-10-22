extends Control
## New campaign screen: every faction is a row with a Human / AI toggle and
## a team dropdown (Team 1 .. Team 8; each faction starts on a team of its
## own), plus "All humans one team" and "Everyone on their own". Any number
## of humans 1..8; the first one switched on is "you" (online: the seat this
## device takes). Name, seed and settings. Emits `start(data, slot)` with
## fresh save data, or `back`. Local play with several humans is hot seat
## (the campaign screen cycles through every human seat). Online mode
## (`online` = true): at least two humans, one join code lets the others each
## claim a free seat; plus the Discord webhook, your Discord user id and (if
## the server wants one) an invite key; Start creates the campaign on the
## server and emits `created_online(id, code)`.
## Difficulty: the battle AI and the campaign AI skill (Easy / Average /
## Skilled, campaign/cai_profile.gd) for every AI faction, stored in the
## campaign's settings (only when not Average); docs/AI.md sections 10-12.
## The look is the menu's (ui_kit.gd): a fixed top bar (Back, the setting's emblem and the title in Cinzel, Start as the
## hero button, off with the reason as its tip until the page is valid), then a column of panels: the Story cards (West),
## the faction rows (flag, name, a wrapped blurb, a Human / AI capsule, the team), the Settings panel of rows (label, one
## line, a capsule or a field; a fold on a phone) and, online, the Online panel. Boxed tips on every control.

## panel: the loading panel opened by the tap (it carries on to the map).
signal start(data: Dictionary, slot: String, panel: Node)
signal back
signal server_requested  ## the Change button of the Server row: the menu opens its Game server page
signal created_online(id: String, join_code: String)

const TouchScroll := preload("res://game/touch_scroll.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const LoadingPanel := preload("res://game/campaign/loading_panel.gd")
const Saves := preload("res://game/campaign/saves.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const CStory := preload("res://campaign/cstory.gd")
const UiScale := preload("res://game/ui_scale.gd")

const PANEL_WARM := Color(0.075, 0.066, 0.052, 0.97)

## Fallback blurbs by faction key (a FACTIONS row's own "blurb" wins).
const BLURB := {
	"rome": "Four Italian regions; heavy swordsmen. At war with Epirus.",
	"carthage": "Rich, spread over Africa, Sicily, Sardinia and Spain; strong cavalry. At war with Syracuse.",
	"macedon": "Two strong regions; pikes and companion cavalry.",
	"epirus": "Pyrrhus in Tarentum and Epirus; pikes and cavalry. At war with Rome.",
	"greeks": "Athens, Corinth and Aetolia; hoplites and archers.",
	"syracuse": "Eastern Sicily and Rhegium; hoplites and engines. At war with Carthage.",
	"iberians": "The Spanish interior; light infantry and javelins.",
	"gauls": "Southern Gaul and the Po valley; warbands and cavalry.",
}

## The human factions in the order they were switched on (picks[0] is "you").
var picks: Array[int] = []
## Team number 0..7 per faction (CState `teams`); default: each on its own.
var team_of: Array[int] = []
var name_edit: LineEdit
var seed_edit: LineEdit
var settings := CState.DEFAULT_SETTINGS.duplicate()
var _human_segs: Array = []        # Kit.Segmented per faction (AI / Human)
var _team_dds: Array[OptionButton] = []
var _name_labels: Array[Label] = []
var _row_panels: Array[PanelContainer] = []
var _info: Label
var _list: VBoxContainer
var _pack_buttons := {}  # pack key -> its Setting button
var _start_button: Button
var _seg := {}           # settings key -> its Kit.Segmented
var _steppers := {}      # settings key -> [value Label, format]
var online := false
## Open on this setting and hide the Setting row (the title menu's cards).
var pack_pick := ""
var _online_box: Control
var _hook_edit: LineEdit
var _user_edit: LineEdit
var _server_label: Label
var _invite_edit: LineEdit
var _invite_row: Control  # the invite field (with its Paste button on the web)
var _creating := false
var _narrow := false      # a phone: rows stack, the settings fold
var _title_label: Label
var _title_emblem: Control
var _settings_body: Control
var _fold_button: Button
var _bold: Font = null
var _deploy_dd: OptionButton
var _time_dd: OptionButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vp := get_viewport_rect().size
	_narrow = vp.x < 700.0 or (UiScale.is_touch() and vp.y < 520.0)  # a phone (a landscape phone is 800 x 450 logical)
	var bg := ColorRect.new()
	bg.color = Color(0.055, 0.05, 0.043)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	fv.variation_embolden = 0.5
	_bold = fv
	# The setting first (the title's emblem and the rows need it).
	var pk := PackView.load_pref()
	if pack_pick != "" and CData.has_pack(pack_pick):
		pk = pack_pick
		PackView.save_pref(pk)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack="):
			pk = a.get_slice("=", 1)  # testing aid
	if not CData.has_pack(pk):
		pk = "rome"
	PackView.use_pack(pk)
	# The top bar stays put: Back, the title, Start.
	var top := PanelContainer.new()
	top.name = "top_bar"
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.04, 0.036, 0.03, 0.97)
	tsb.border_color = Color(Kit.COL_RULE, 0.7)
	tsb.border_width_bottom = 1
	tsb.set_content_margin_all(8)
	top.add_theme_stylebox_override("panel", tsb)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var head := Kit.hbox(10)
	top.add_child(head)
	var back_b := Kit.button("< Back", func(): back.emit(), 90 if not _narrow else 70, 15)
	back_b.name = "back_button"
	Kit.nav_style(back_b)
	Kit.tip(back_b, "Back", "Return to the menu without starting anything.")
	head.add_child(back_b)
	_title_emblem = Kit.emblem(pk, 36)
	_title_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_title_emblem)
	_title_label = Kit.title("New grand campaign" if online else "New campaign", 24 if not _narrow else 18)
	_title_label.name = "nc_title"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.custom_minimum_size.x = 40
	head.add_child(_title_label)
	_start_button = Kit.hero_button("Start", "", _start, 110 if not _narrow else 84, 18)
	_start_button.name = "start_campaign"
	head.add_child(_start_button)
	add_child(top)
	var scroll := TouchScroll.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 64
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 16)
	scroll.add_child(margin)
	var fit := func():
		var m := maxf(12.0, (size.x - 900.0) * 0.5)
		margin.add_theme_constant_override("margin_left", int(m))
		margin.add_theme_constant_override("margin_right", int(m))
	resized.connect(fit)
	fit.call()
	var v := Kit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(v)
	_info = Kit.label("", Kit.FONT, Color.WHITE, true)
	_info.name = "nc_info"
	v.add_child(_info)
	var avail := PackView.available()
	if avail.size() > 1 and pack_pick == "":
		var sr0 := Kit.flow(8)
		sr0.add_child(Kit.label("Setting", Kit.FONT, Kit.COL_DIM))
		for c in avail:
			var sb := Kit.button(str(c[1]), _set_pack.bind(str(c[0])), 0, 14)
			sb.toggle_mode = true
			sb.name = "pack_" + str(c[0])
			sr0.add_child(sb)
			_pack_buttons[str(c[0])] = sb
		v.add_child(sr0)
	if CData.has_pack("west"):
		v.add_child(_build_story())
	var team_row := Kit.flow(8)
	var b_one := Kit.button("All humans one team", _all_humans_one_team, 0, 14)
	b_one.name = "all_one_team"
	Kit.nav_style(b_one)
	Kit.tip(b_one, "One team", "Puts every human faction on the first human's team: allied for good, never at war, winning together.")
	team_row.add_child(b_one)
	var b_own := Kit.button("Everyone on their own", _everyone_alone, 0, 14)
	b_own.name = "everyone_alone"
	Kit.nav_style(b_own)
	Kit.tip(b_own, "Own teams", "Every faction on a team of its own again.")
	team_row.add_child(b_own)
	v.add_child(team_row)
	_list = Kit.vbox(6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_list)
	_build_rows()
	v.add_child(_build_settings())
	if online:
		v.add_child(_build_online())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--picks="):
			# Testing aid: --picks=rome,carthage (humans, in that order)
			for k in a.get_slice("=", 1).split(","):
				_pick(CData.faction_index(k))
		elif a == "--one-team":
			_all_humans_one_team()
	_update()


## One labelled row of a panel: label (16, bone) and one dim line on the left, the control on the right (under them on
## a phone).
func _srow(parent: Control, nm: String, label: String, desc: String, control: Control) -> Control:
	var left := Kit.vbox(1)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(Kit.label(label, 16, Kit.COL_BONE))
	if desc != "":
		left.add_child(Kit.label(desc, 13, Kit.COL_DIM, true))
	var row: Control
	if _narrow:
		var vv := Kit.vbox(4)
		vv.add_child(left)
		control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		vv.add_child(control)
		row = vv
	else:
		var h := Kit.hbox(14)
		h.add_child(left)
		control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(control)
		row = h
	row.name = "srow_" + nm
	parent.add_child(row)
	return row


## A capsule bound to settings[key] (values from CHOICES; labels given).
func _setting_seg(parent: Control, key: String, label: String, desc: String, labels: Array, tip_title: String, tip_text: String) -> void:
	var ch: Array = CHOICES[key]
	var opts: Array = []
	for i in ch.size():
		opts.append([labels[i], ch[i]])
	var sg := Kit.segmented(opts, settings.get(key, ch[0]), Callable(), key)
	sg.changed.connect(func(val):
		settings[key] = val
		_update())
	Kit.tip(sg, tip_title, tip_text)
	_seg[key] = sg
	_srow(parent, key, label, desc, sg)


func _stepper(key: String, fmt: String, tip_title: String, tip_text: String) -> Control:
	var h := Kit.hbox(4)
	var minus := Kit.button("-", _step.bind(key, -1), 38, 16)
	minus.name = "step_%s_minus" % key
	Kit.nav_style(minus)
	var l := Kit.label("", 15, Kit.COL_BONE)
	l.custom_minimum_size.x = 100
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var plus := Kit.button("+", _step.bind(key, 1), 38, 16)
	plus.name = "step_%s_plus" % key
	Kit.nav_style(plus)
	h.add_child(minus)
	h.add_child(l)
	h.add_child(plus)
	for c in [minus, plus]:
		Kit.tip(c, tip_title, tip_text)
	_steppers[key] = [l, fmt]
	return h


func _step(key: String, d: int) -> void:
	var ch: Array = CHOICES[key]
	var i := clampi(ch.find(settings[key]) + d, 0, ch.size() - 1)
	settings[key] = ch[i]
	_update()


## The Story cards (West): the story campaign "The Brethren's Due", one captain or two (hot seat here, online from the
## online screen) who vote on every choice.
func _build_story() -> Control:
	var panel := Kit.trim_panel(PANEL_WARM, 12)
	panel.name = "story_panel"
	var v := Kit.vbox(8)
	panel.add_child(v)
	v.add_child(Kit.title("Story", 20))
	var cards := BoxContainer.new()
	cards.vertical = _narrow
	cards.add_theme_constant_override("separation", 10)
	v.add_child(cards)
	var defs: Array = []
	if not online:
		defs.append(["story_brethren", "The Brethren's Due", "One captain. Your captain hanged, one leaky sloop, and the whole Spanish Main against you.", "Play the story",
			"A pirate story in the Caribbean, 1665: your captain hanged, one leaky sloop, and the whole Spanish Main against you. One player; uses the name, seed and difficulty below.", func(): _start_story(false)])
		defs.append(["story_brethren_coop", "Two captains", "The same story for two on one device (hot seat): every choice is the crew's vote.", "Play with two",
			"The same story for two captains on one device: every choice is the crew's vote between them; when they disagree, Mercy calls it by fame and crew.", func(): _start_story(true)])
	else:
		defs.append(["story_brethren_online", "The Brethren's Due, online", "Two captains, each on their own device; you vote on every choice and Mercy breaks a tie.",
			"Host the story", "The pirate story of 1665 for two captains online: each answers every choice from their own device; when you disagree, Mercy calls it by fame and crew. Uses the name, seed and difficulty below.",
			func(): _start_online(true)])
	for d in defs:
		var c := Kit.panel(Color(0.10, 0.09, 0.07, 0.95), 10)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := Kit.vbox(4)
		c.add_child(cv)
		cv.add_child(Kit.label(d[1], 16, Kit.COL_GOLD))
		cv.add_child(Kit.label(d[2], 13, Kit.COL_DIM, true))
		var bt := Kit.button(d[3], d[5], 0, 14)
		bt.name = d[0]
		Kit.nav_style(bt)
		Kit.tip(bt, d[1], d[4])
		cv.add_child(bt)
		cards.add_child(c)
	v.add_child(Kit.label("Caribbean, 1665: a pirate story for two captains." if online else "Caribbean, 1665: a pirate story for one player, or two.", 13, Kit.COL_DIM, true))
	return panel


## The active pack's factions as rows (picks and teams start afresh).
func _build_rows() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	picks.clear()
	team_of.clear()
	_human_segs.clear()
	_team_dds.clear()
	_name_labels.clear()
	_row_panels.clear()
	for f in CData.faction_count():
		team_of.append(f)
	var topts: Array = []
	for ti in CData.faction_count():
		topts.append(["Team %d" % (ti + 1), ti])
	for f in CData.faction_count():
		var fd: Dictionary = CData.FACTIONS[f]
		var key := str(fd["key"])
		var rowp := PanelContainer.new()
		rowp.name = "row_" + key
		_row_panels.append(rowp)
		var rv := Kit.vbox(6)
		rowp.add_child(rv)
		var h := Kit.hbox(10)
		rv.add_child(h)
		var mk := Kit.faction_mark(f, 36)
		mk.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(mk)
		var nv := Kit.vbox(1)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nl := Kit.label(str(fd["name"]), 16, Kit.COL_BONE)
		nl.add_theme_font_override("font", _bold)
		nv.add_child(nl)
		var bl := Kit.label(str(fd.get("blurb", BLURB.get(key, ""))), 13, Kit.COL_DIM, true)
		bl.name = "blurb_" + key
		nv.add_child(bl)
		h.add_child(nv)
		_name_labels.append(nl)
		var ctl := Kit.hbox(8)
		var sg := Kit.segmented([["AI", 0], ["Human", 1]], 0, Callable(), "who_" + key)
		sg.button_for(0).name = "ai_" + key
		sg.button_for(1).name = "faction_" + key
		sg.changed.connect(func(val):
			if (int(val) == 1) != picks.has(f):
				_pick(f))
		Kit.tip(sg, "Human or AI", "Humans plan their own moves; the first one you switch on is you. Online, each human takes a seat and joins with the code.")
		ctl.add_child(sg)
		_human_segs.append(sg)
		var dd := Kit.dropdown(topts, team_of[f], func(x): _set_team(f, int(x)), 92, 14)
		dd.name = "team_" + key
		Kit.tip(dd, "Team", "Factions on one team are allied for good, never at war, and win together.")
		ctl.add_child(dd)
		_team_dds.append(dd)
		if _narrow:
			ctl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			rv.add_child(ctl)
		else:
			ctl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(ctl)
		_style_row(f, false)
		_list.add_child(rowp)


## A faction row's plate: dark, with a gold edge on the left while a human plays it.
func _style_row(f: int, human: bool) -> void:
	var sb := Kit.box(Color(0.09, 0.085, 0.07, 0.95) if not human else Color(0.13, 0.11, 0.07, 0.97), 8.0, 4)
	sb.border_width_left = 3
	sb.border_color = Kit.COL_GOLD if human else Color(Kit.COL_RULE, 0.25)
	sb.content_margin_left = 10.0
	_row_panels[f].add_theme_stylebox_override("panel", sb)


## The Settings panel: rows of a label, one line and a control (a fold on a phone).
func _build_settings() -> Control:
	var panel := Kit.trim_panel(PANEL_WARM, 12)
	panel.name = "settings_panel"
	var v := Kit.vbox(8)
	panel.add_child(v)
	if _narrow:
		_fold_button = Kit.button("Settings  -", _toggle_fold, 0, 16)
		_fold_button.name = "settings_fold"
		_fold_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		Kit.nav_style(_fold_button)
		v.add_child(_fold_button)
	else:
		v.add_child(Kit.title("Settings", 20))
	var body := Kit.vbox(8)
	body.name = "settings_body"
	_settings_body = body
	v.add_child(body)
	name_edit = Kit.text_field("Campaign name", "Campaign", 200)
	name_edit.name = "campaign_name"
	Kit.tip(name_edit, "Name", "What the save is called.")
	_srow(body, "name", "Name", "What the save is called.", name_edit)
	body.add_child(Kit.rule())
	var sh := Kit.hbox(6)
	seed_edit = Kit.text_field("Seed", str(int(Time.get_unix_time_from_system()) % 100000), 110, "Seed (a number: the same seed gives the same map)", true)
	seed_edit.name = "campaign_seed"
	seed_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	Kit.tip(seed_edit, "Seed", "A number: the same seed gives the same map and the same start.")
	sh.add_child(seed_edit)
	var dice := Kit.button("", _new_seed, 42, 14)
	dice.name = "seed_dice"
	Kit.nav_style(dice)
	Kit.tip(dice, "New seed", "Rolls a new random seed.")
	dice.draw.connect(func():
		var c := dice.size * 0.5
		var r := minf(dice.size.x, dice.size.y) * 0.5 - 9.0
		dice.draw_rect(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), Kit.COL_BONE, false, 1.6)
		for pp in [Vector2(-0.5, -0.5), Vector2(0.5, 0.5), Vector2.ZERO, Vector2(0.5, -0.5), Vector2(-0.5, 0.5)]:
			dice.draw_circle(c + pp * r * 1.1, 1.6, Kit.COL_BONE))
	sh.add_child(dice)
	_srow(body, "seed", "Seed", "The same seed gives the same map.", sh)
	body.add_child(Kit.rule())
	var vh := Kit.hbox(14)
	vh.add_child(_stepper("victory_regions", "%d regions", "Regions to win", "Hold this many regions to win outright."))
	vh.add_child(_stepper("victory_capitals", "%d cities", "Great cities to win", "...and hold this many of the great cities."))
	_srow(body, "victory", "Victory", "Win by holding this many regions, with this many great cities.", vh)
	_setting_seg(body, "turn_timeout_h", "Turn timeout", "When the time is up the turn resolves without the slow players.", ["Off", "12 h", "24 h", "48 h", "72 h"],
		"Turn timeout", "Online: how long the others wait for a player before the turn resolves without them. Off: only when everyone has submitted.")
	_setting_seg(body, "autoresolve", "Battles", "Fight the battles yourself, or let them resolve.", ["Ask", "Always auto"],
		"Battles", "Ask: you choose between fighting and auto-resolving each battle you are in. Always auto: every battle is resolved at once.")
	_setting_seg(body, "ai_aggression", "AI aggression", "How eagerly the AI factions go to war.", ["Calm", "Normal", "Aggressive"],
		"AI aggression", "Calm AIs keep the peace longer; aggressive ones pick wars early and often.")
	settings["ai_battle_skill"] = AI_AVERAGE
	settings["ai_campaign_skill"] = AI_AVERAGE
	_setting_seg(body, "ai_battle_skill", "Battle AI", "How well the AI fights the battles you play.", SKILL_LABELS,
		"Battle AI", "Easy makes a new player's mistakes; Skilled reads the battle and punishes yours.")
	_setting_seg(body, "ai_campaign_skill", "Campaign AI", "How well the AI runs its empire.", SKILL_LABELS,
		"Campaign AI", "Easy makes a new player's mistakes; Skilled concentrates its armies, picks its wars and fights one front at a time.")
	settings["fog"] = 1
	_setting_seg(body, "fog", "Fog of war", "Hide what your armies cannot see.", ["On", "Off"],
		"Fog of war", "On: you see your regions and their neighbours, and what your armies, fleets and cities can see; the rest shows as last known. Off: everything is visible. Fixed when the campaign is created.")
	settings["deploy_time"] = 60
	var db := Kit.dropdown(Kit.DEPLOY_OPTIONS, 60, func(x): settings["deploy_time"] = int(x), 0, 14)
	db.name = "deploy_time"
	Kit.tip(db, "Deployment", "Before a battle you fight yourself: time to place your units in your zone (Total War style); Unlimited waits until every player is ready; auto-resolve ignores it.")
	_deploy_dd = db
	_srow(body, "deploy", "Deployment", "Time to place your units before a battle.", db)
	settings["time_limit"] = 900
	var tb := Kit.dropdown(Kit.TIME_OPTIONS, 900, func(x): settings["time_limit"] = int(x), 0, 14)
	tb.name = "time_limit"
	Kit.tip(tb, "Battle time", "How long a battle lasts before it is a draw (a long siege may need more than 15 minutes).")
	_time_dd = tb
	_srow(body, "time", "Battle time", "How long a battle lasts before it is a draw.", tb)
	if _narrow:
		body.visible = false
		_fold_button.text = "Settings  +"
	return panel


func _toggle_fold() -> void:
	_settings_body.visible = not _settings_body.visible
	_fold_button.text = "Settings  " + ("-" if _settings_body.visible else "+")


func _new_seed() -> void:
	seed_edit.text = str(randi() % 100000)


## The Online panel (online mode): the server, the Discord webhook and user id, the invite key.
func _build_online() -> Control:
	var panel := Kit.trim_panel(PANEL_WARM, 12)
	panel.name = "online_panel"
	_online_box = panel
	var v := Kit.vbox(8)
	panel.add_child(v)
	v.add_child(Kit.title("Online", 20))
	var net := get_node_or_null("/root/Net")
	if net != null:
		var svrow := Kit.hbox(8)
		_server_label = Kit.label("Server: %s%s" % [net.server_url(), " (default)" if net.is_default() else ""], 14, Kit.COL_BONE)
		_server_label.name = "server_label"
		_server_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_server_label.clip_text = true
		svrow.add_child(_server_label)
		var sb := Kit.button("Change", func(): server_requested.emit(), 100, 14)
		sb.name = "server_change"
		Kit.nav_style(sb)
		Kit.tip(sb, "Game server", "Pick another server for this campaign, or host one from this PC.")
		svrow.add_child(sb)
		v.add_child(svrow)
	_hook_edit = Kit.text_field("https://discord.com/api/webhooks/...", "", 220, "Discord webhook URL", true)
	_hook_edit.name = "webhook"
	_hook_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Kit.tip(_hook_edit, "Discord webhook", "Optional. A channel's webhook URL (Channel settings > Integrations > Webhooks): the server posts there when it is someone's turn.")
	_srow(v, "webhook", "Discord webhook", "Optional: turn notices in a channel.", Kit.field_box(_hook_edit))
	_user_edit = Kit.text_field("Your Discord user id", str(net.accounts.data.get("discord_user", "")) if net else "", 220, "", true)
	_user_edit.name = "discord_user"
	Kit.tip(_user_edit, "Discord user id", "Optional, for @mentions. Discord settings > Advanced > Developer mode, then right-click your name > Copy User ID.")
	_srow(v, "discord_user", "Your Discord id", "Optional: so the notices can @mention you.", Kit.field_box(_user_edit))
	# The invite key last used is remembered on this device (Net accounts).
	_invite_edit = Kit.text_field("Invite key", str(net.accounts.data.get("invite", "")) if net else "", 220, "Invite key", true)
	_invite_edit.name = "invite"
	Kit.tip(_invite_edit, "Invite key", "Some servers only let invited players create campaigns: ask the server's owner for a key. Joining needs none.")
	_invite_row = _srow(v, "invite", "Invite key", "Only if the server asks for one.", Kit.field_box(_invite_edit))
	if net != null and not bool(net.info.get("invite_required", true)):
		_invite_row.visible = false
	return panel


## Switch the setting: CData and the map geometry, then the faction list.
func _set_pack(key: String) -> void:
	if _creating or not CData.has_pack(key):
		return
	if key != CData.pack:
		PackView.use_pack(key)
		_build_rows()
	PackView.save_pref(key)
	_update()


const CHOICES := {"victory_regions": [15, 20, 25, 30], "victory_capitals": [2, 3, 4, 5],
	"turn_timeout_h": [0, 12, 24, 48, 72], "autoresolve": ["ask", "auto"], "ai_aggression": [70, 100, 130],
	"ai_battle_skill": [0, 1, 2], "ai_campaign_skill": [0, 1, 2], "fog": [1, 0]}
## AI skill levels (campaign/cai_profile.gd EASY / AVERAGE / SKILLED).
const AI_AVERAGE := 1
const SKILL_LABELS: Array[String] = ["Easy", "Average", "Skilled"]


func _pick(f: int) -> void:
	if _creating:
		return
	if picks.has(f):
		picks.erase(f)
	else:
		picks.append(f)
	_update()


func _set_team(f: int, t: int) -> void:
	if _creating:
		return
	team_of[f] = t
	_update()


## Every human on the team of the first one (AI factions stay as they are).
func _all_humans_one_team() -> void:
	if _creating or picks.is_empty():
		return
	for f in picks:
		team_of[f] = team_of[picks[0]]
	_update()


func _everyone_alone() -> void:
	if _creating:
		return
	for f in team_of.size():
		team_of[f] = f
	_update()


## The `teams` array handed to CState.new_campaign.
func teams_array() -> Array:
	var out: Array = []
	for t in team_of:
		out.append(int(t))
	return out


func _team_text() -> String:
	var parts: Array[String] = []
	var seen: Array[int] = []
	for f in team_of.size():
		var t := team_of[f]
		if seen.has(t):
			continue
		seen.append(t)
		var names: Array[String] = []
		for g in team_of.size():
			if team_of[g] == t:
				names.append(CData.faction_name(g))
		if names.size() > 1:
			parts.append("Team %d: %s" % [t + 1, ", ".join(names)])
	return "; ".join(parts)


func _update() -> void:
	for k in _pack_buttons:
		(_pack_buttons[k] as Button).set_pressed_no_signal(str(k) == CData.pack)
		(_pack_buttons[k] as Button).disabled = _creating
	var need := 2 if online else 1
	if _title_emblem != null and _title_emblem.get("pack") != null:
		_title_emblem.set("pack", CData.pack)
		_title_emblem.queue_redraw()
	for f in _human_segs.size():
		var is_h := picks.has(f)
		var sg: Kit.Segmented = _human_segs[f]
		sg.set_value(1 if is_h else 0)
		sg.button_for(1).text = "You" if picks.find(f) == 0 else "Human"
		sg.set_disabled(_creating)
		_team_dds[f].select(team_of[f])
		_team_dds[f].disabled = _creating
		_name_labels[f].text = CData.faction_name(f) + (" (you)" if picks.find(f) == 0 else "")
		_style_row(f, is_h)
	var teams_txt := _team_text()
	if picks.is_empty():
		_info.text = "Switch at least one faction to Human (the first one is you)."
	elif picks.size() < need:
		_info.text = "You play %s. Online co-op needs at least one more human: switch another faction to Human." % CData.faction_name(picks[0])
	else:
		var names: Array[String] = []
		for f in picks:
			names.append(CData.faction_name(f))
		if online:
			_info.text = "You play %s; humans: %s. Each joins with the code and plans on their own device; the turn resolves when everyone has submitted." % [
				CData.faction_name(picks[0]), ", ".join(names)]
		elif picks.size() == 1:
			_info.text = "Playing %s." % names[0]
		else:
			_info.text = "Humans: %s. They plan on this device one after the other (hot seat)." % ", ".join(names)
		if teams_txt != "":
			_info.text += " " + teams_txt + "."
	_start_button.disabled = picks.size() < need or _creating
	if _creating:
		Kit.tip(_start_button, "Starting", "The campaign is being created.")
	elif picks.is_empty():
		Kit.tip(_start_button, "Pick a human", "Switch at least one faction to Human first: the first one you switch on is you.")
	elif picks.size() < need:
		Kit.tip(_start_button, "Pick another human", "An online campaign needs at least two humans: switch one more faction to Human.")
	else:
		Kit.tip(_start_button, "Start", "Create the campaign and open the map." if not online else "Create the campaign on the server and get the join code.")
	for k in _seg:
		(_seg[k] as Kit.Segmented).set_value(settings[k])
		(_seg[k] as Kit.Segmented).set_disabled(_creating)
	for k in _steppers:
		(_steppers[k][0] as Label).text = str(_steppers[k][1]) % int(settings[k])


func _start() -> void:
	if online:
		_start_online()
		return
	var sd := int(seed_edit.text) if seed_edit.text.is_valid_int() else 1
	var nm := name_edit.text.strip_edges()
	if nm == "":
		nm = "Campaign"
	if _creating:
		return
	# The tap answers at once: the button is off and the panel is up before
	# any work starts (a second tap cannot start a second campaign).
	_creating = true
	_update()
	var lp := LoadingPanel.open(get_tree().root, "Preparing the campaign", 5)
	await lp.step("Creating the campaign")
	var st := CState.new_campaign(nm, sd, picks.duplicate(), settings, teams_array(), CData.pack)
	var slot := Saves.slot_for(nm, sd)
	var data := {"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}
	Saves.save(slot, data)
	start.emit(data, slot, lp)


## Start the story campaign "The Brethren's Due" (the West pack, the
## Brethren, its own start; the name, seed and difficulty from this screen).
func _start_story(coop: bool = false) -> void:
	if _creating:
		return
	var sd := int(seed_edit.text) if seed_edit.text.is_valid_int() else 1
	var nm := name_edit.text.strip_edges()
	if nm == "" or nm == "Campaign":
		nm = "The Brethren's Due"
	_creating = true
	_update()
	var lp := LoadingPanel.open(get_tree().root, "Preparing the story", 5)
	await lp.step("Hanging Captain Vane")
	PackView.use_pack("west")
	var stt := {}
	for k in ["ai_battle_skill", "ai_campaign_skill", "deploy_time", "time_limit", "autoresolve"]:
		if settings.has(k):
			stt[k] = settings[k]
	var st := CStory.new_story(nm, sd, stt, "brethren", coop)
	var slot := Saves.slot_for(nm, sd)
	var data := {"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}
	Saves.save(slot, data)
	start.emit(data, slot, lp)


func _start_online(story: bool = false) -> void:
	var net := get_node_or_null("/root/Net")
	if net == null or not net.has_server():
		_info.text = "Online play needs a game server: use Change to pick one."
		_info.add_theme_color_override("font_color", Kit.COL_BAD)
		return
	if not net.available and not await net.check_server():
		_info.text = "The game server %s is not available right now, so online play is off. Local play works as usual, or use Change to pick another server." % net.server_url()
		_info.add_theme_color_override("font_color", Kit.COL_BAD)
		return
	var sinfo: Dictionary = net.describe_info(net.info)
	if bool(sinfo["mismatch"]):
		_info.text = str(sinfo["text"])
		_info.add_theme_color_override("font_color", Kit.COL_BAD)
		return
	var sd := int(seed_edit.text) if seed_edit.text.is_valid_int() else 1
	var nm := name_edit.text.strip_edges()
	if nm == "":
		nm = "Campaign"
	var seat_f: int = picks[0] if not picks.is_empty() else 0
	var st: Dictionary
	if story:
		PackView.use_pack("west")
		var stt := {}
		for k in ["ai_battle_skill", "ai_campaign_skill", "deploy_time", "time_limit", "autoresolve", "turn_timeout_h"]:
			if settings.has(k):
				stt[k] = settings[k]
		if nm == "Campaign":
			nm = "The Brethren's Due"
		st = CStory.new_story(nm, sd, stt, "brethren", true)
		seat_f = CStory.player(st)
	else:
		st = CState.new_campaign(nm, sd, picks.duplicate(), settings, teams_array(), CData.pack)
		_creating = true
	_update()
	_info.text = "Creating the campaign on the server..."
	_info.add_theme_color_override("font_color", Color.WHITE)
	var user := _user_edit.text.strip_edges()
	if user != "":
		net.accounts.set_value("discord_user", user)
	var r: Dictionary = await net.create_campaign(st, seat_f, {"webhook_url": _hook_edit.text.strip_edges(),
		"discord_user": user, "invite": _invite_edit.text.strip_edges(), "name": nm})
	_creating = false
	_update()
	if not r["ok"]:
		_info.add_theme_color_override("font_color", Kit.COL_BAD)
		if r["network"]:
			_info.text = "The game server cannot be reached. Try again later."
		elif str(r["error"]) == "invite_required":
			_invite_row.visible = true
			_info.text = "This server needs an invite key to create campaigns: ask the server's owner."
		else:
			_info.text = "Could not create it: " + (str(r["message"]) if str(r["message"]) != "" else str(r["error"]))
		return
	var tele := get_node_or_null("/root/Telemetry")
	if tele != null:
		tele.event("online_create", {"from": "new", "story": story, "humans": st["humans"], "teams": teams_array(), "timeout_h": int(settings["turn_timeout_h"]),
			"webhook": _hook_edit.text.strip_edges() != ""})
	created_online.emit(str(r["data"]["id"]), str(r["data"].get("join_code", "")))
