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

## panel: the loading panel opened by the tap (it carries on to the map).
signal start(data: Dictionary, slot: String, panel: Node)
signal back
signal created_online(id: String, join_code: String)

const TouchScroll := preload("res://game/touch_scroll.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const LoadingPanel := preload("res://game/campaign/loading_panel.gd")
const Saves := preload("res://game/campaign/saves.gd")
const PackView := preload("res://game/campaign/pack_view.gd")

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
var _human_buttons: Array[Button] = []
var _team_dds: Array[OptionButton] = []
var _name_labels: Array[Label] = []
var _info: Label
var _list: VBoxContainer
var _pack_buttons := {}  # pack key -> its Setting button
var _start_button: Button
var _setting_buttons := {}
var online := false
var _online_box: VBoxContainer
var _hook_edit: LineEdit
var _user_edit: LineEdit
var _invite_edit: LineEdit
var _invite_row: Control  # the invite field (with its Paste button on the web)
var _creating := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.15, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := TouchScroll.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 12
	scroll.offset_right = -12
	scroll.offset_top = 8
	scroll.offset_bottom = -8
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var v := Kit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var head := Kit.hbox(8)
	var t := Kit.label("New campaign", 22, Kit.COL_GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	if online:
		t.text = "New online co-op campaign"
	head.add_child(Kit.button("Back", func(): back.emit(), 80))
	_start_button = Kit.button("Start", _start, 120, 17)
	_start_button.name = "start_campaign"
	head.add_child(_start_button)
	v.add_child(head)
	_info = Kit.label("", Kit.FONT, Color.WHITE, true)
	v.add_child(_info)
	var pk := PackView.load_pref()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack="):
			pk = a.get_slice("=", 1)  # testing aid
	if not CData.has_pack(pk):
		pk = "rome"
	PackView.use_pack(pk)
	var avail := PackView.available()
	if avail.size() > 1:
		var sr0 := Kit.flow(8)
		sr0.add_child(Kit.label("Setting", Kit.FONT, Kit.COL_DIM))
		for c in avail:
			var sb := Button.new()
			sb.toggle_mode = true
			sb.focus_mode = Control.FOCUS_NONE
			sb.text = str(c[1])
			sb.name = "pack_" + str(c[0])
			sb.custom_minimum_size = Vector2(0, Kit.BTN_H)
			sb.add_theme_font_size_override("font_size", 14)
			sb.pressed.connect(_set_pack.bind(str(c[0])))
			sr0.add_child(sb)
			_pack_buttons[str(c[0])] = sb
		v.add_child(sr0)
	var team_row := Kit.flow(8)
	var b_one := Kit.button("All humans one team", _all_humans_one_team, 0, 14)
	b_one.name = "all_one_team"
	team_row.add_child(b_one)
	var b_own := Kit.button("Everyone on their own", _everyone_alone, 0, 14)
	b_own.name = "everyone_alone"
	team_row.add_child(b_own)
	v.add_child(team_row)
	_list = Kit.vbox(4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_list)
	_build_rows()
	var row := Kit.flow(8)
	row.add_child(Kit.label("Name", Kit.FONT, Kit.COL_DIM))
	name_edit = Kit.text_field("Campaign name", "Campaign", 180)
	name_edit.name = "campaign_name"
	row.add_child(name_edit)
	row.add_child(Kit.label("Seed", Kit.FONT, Kit.COL_DIM))
	seed_edit = Kit.text_field("Seed", str(int(Time.get_unix_time_from_system()) % 100000), 110, "Seed (a number: the same seed gives the same map)", true)
	seed_edit.name = "campaign_seed"
	seed_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	row.add_child(seed_edit)
	v.add_child(row)
	var sr := Kit.flow(8)
	for k in ["victory_regions", "victory_capitals", "turn_timeout_h", "autoresolve", "ai_aggression"]:
		var b := Kit.button("", _cycle.bind(k), 0, 14)
		_setting_buttons[k] = b
		sr.add_child(b)
	v.add_child(sr)
	settings["ai_battle_skill"] = AI_AVERAGE
	settings["ai_campaign_skill"] = AI_AVERAGE
	var dr := Kit.flow(8)
	dr.add_child(Kit.label("Difficulty", Kit.FONT, Kit.COL_DIM))
	for k in ["ai_battle_skill", "ai_campaign_skill"]:
		var b := Kit.button("", _cycle.bind(k), 0, 14)
		b.name = k
		_setting_buttons[k] = b
		dr.add_child(b)
	settings["deploy_time"] = 60
	dr.add_child(Kit.label("Deployment", Kit.FONT, Kit.COL_DIM))
	var db := Kit.dropdown(Kit.DEPLOY_OPTIONS, 60, func(x): settings["deploy_time"] = int(x), 0, 14)
	db.name = "deploy_time"
	db.tooltip_text = "Before a battle you fight yourself: time to place your units in your zone (Total War style); Unlimited waits until every player is ready; auto-resolve ignores it"
	_deploy_dd = db
	dr.add_child(db)
	settings["time_limit"] = 900
	dr.add_child(Kit.label("Battle time", Kit.FONT, Kit.COL_DIM))
	var tb := Kit.dropdown(Kit.TIME_OPTIONS, 900, func(x): settings["time_limit"] = int(x), 0, 14)
	tb.name = "time_limit"
	tb.tooltip_text = "How long a battle lasts before it is a draw (a long siege may need more than 15 minutes)"
	_time_dd = tb
	dr.add_child(tb)
	v.add_child(dr)
	_online_box = Kit.vbox(6)
	_online_box.visible = online
	v.add_child(_online_box)
	var net := get_node_or_null("/root/Net")
	_online_box.add_child(Kit.label("Discord notifications (optional): a channel's webhook URL (Channel settings > Integrations > Webhooks), and your Discord user id for @mentions (Discord settings > Advanced > Developer mode, then right-click your name > Copy User ID).", 13, Kit.COL_DIM, true))
	_hook_edit = Kit.text_field("https://discord.com/api/webhooks/...", "", 300, "Discord webhook URL", true)
	_hook_edit.name = "webhook"
	_hook_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_online_box.add_child(Kit.field_box(_hook_edit))
	var r2 := Kit.flow(8)
	_user_edit = Kit.text_field("Your Discord user id", str(net.accounts.data.get("discord_user", "")) if net else "", 240, "", true)
	_user_edit.name = "discord_user"
	r2.add_child(Kit.field_box(_user_edit))
	# The invite key last used is remembered on this device (Net accounts).
	_invite_edit = Kit.text_field("Invite key (if the server asks)", str(net.accounts.data.get("invite", "")) if net else "", 240, "Invite key", true)
	_invite_edit.name = "invite"
	_invite_row = Kit.field_box(_invite_edit)
	r2.add_child(_invite_row)
	_online_box.add_child(r2)
	if online and net != null and not bool(net.info.get("invite_required", true)):
		_invite_row.visible = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--picks="):
			# Testing aid: --picks=rome,carthage (humans, in that order)
			for k in a.get_slice("=", 1).split(","):
				_pick(CData.faction_index(k))
		elif a == "--one-team":
			_all_humans_one_team()
	_update()


## The active pack's factions as rows (picks and teams start afresh).
func _build_rows() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	picks.clear()
	team_of.clear()
	_human_buttons.clear()
	_team_dds.clear()
	_name_labels.clear()
	for f in CData.faction_count():
		team_of.append(f)
	var topts: Array = []
	for ti in CData.faction_count():
		topts.append(["Team %d" % (ti + 1), ti])
	for f in CData.faction_count():
		var fd: Dictionary = CData.FACTIONS[f]
		var rowp := Kit.panel(Color(0.16, 0.2, 0.16, 0.9), 6)
		rowp.name = "row_" + str(fd["key"])
		var h := Kit.hbox(8)
		rowp.add_child(h)
		h.add_child(Kit.swatch(CData.faction_color(f), 20))
		var nv := Kit.vbox(0)
		nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nl := Kit.label(str(fd["name"]), 15, Color.WHITE)
		nv.add_child(nl)
		var bl := Kit.label(str(fd.get("blurb", BLURB.get(fd["key"], ""))), 12, Kit.COL_DIM, true)
		bl.custom_minimum_size.x = 120
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nv.add_child(bl)
		h.add_child(nv)
		_name_labels.append(nl)
		var hb := Button.new()
		hb.toggle_mode = true
		hb.focus_mode = Control.FOCUS_NONE
		hb.custom_minimum_size = Vector2(84, Kit.BTN_H)
		hb.add_theme_font_size_override("font_size", 14)
		hb.name = "faction_" + str(fd["key"])
		hb.pressed.connect(_pick.bind(f))
		h.add_child(hb)
		_human_buttons.append(hb)
		var dd := Kit.dropdown(topts, team_of[f], func(x): _set_team(f, int(x)), 92, 14)
		dd.name = "team_" + str(fd["key"])
		dd.tooltip_text = "Factions on one team are allied for good, never at war, and win together"
		h.add_child(dd)
		_team_dds.append(dd)
		_list.add_child(rowp)


## Switch the setting: CData and the map geometry, then the faction list.
func _set_pack(key: String) -> void:
	if _creating or not CData.has_pack(key):
		return
	if key != CData.pack:
		PackView.use_pack(key)
		_build_rows()
	PackView.save_pref(key)
	_update()


var _deploy_dd: OptionButton
var _time_dd: OptionButton

const CHOICES := {"victory_regions": [15, 20, 25, 30], "victory_capitals": [2, 3, 4, 5],
	"turn_timeout_h": [0, 12, 24, 48, 72], "autoresolve": ["ask", "auto"], "ai_aggression": [70, 100, 130],
	"ai_battle_skill": [0, 1, 2], "ai_campaign_skill": [0, 1, 2]}
## AI skill levels (campaign/cai_profile.gd EASY / AVERAGE / SKILLED).
const AI_AVERAGE := 1
const SKILL_LABELS: Array[String] = ["Easy", "Average", "Skilled"]


func _cycle(k: String) -> void:
	var ch: Array = CHOICES[k]
	var i := ch.find(settings[k])
	settings[k] = ch[(i + 1) % ch.size()]
	_update()


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
	for f in _human_buttons.size():
		var is_h := picks.has(f)
		_human_buttons[f].set_pressed_no_signal(is_h)
		_human_buttons[f].text = ("You" if picks.find(f) == 0 else "Human") if is_h else "AI"
		_human_buttons[f].disabled = _creating
		_team_dds[f].select(team_of[f])
		_team_dds[f].disabled = _creating
		_name_labels[f].text = CData.faction_name(f) + (" (you)" if picks.find(f) == 0 else "")
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
	var vr: Dictionary = _setting_buttons
	vr["victory_regions"].text = "Win at %d regions" % int(settings["victory_regions"])
	vr["victory_capitals"].text = "with %d great cities" % int(settings["victory_capitals"])
	vr["turn_timeout_h"].text = "Turn timeout: " + ("off" if int(settings["turn_timeout_h"]) == 0 else "%d h" % int(settings["turn_timeout_h"]))
	vr["autoresolve"].text = "Battles: " + ("ask" if str(settings["autoresolve"]) == "ask" else "always auto")
	vr["ai_aggression"].text = "AI: " + {70: "calm", 100: "normal", 130: "aggressive"}[int(settings["ai_aggression"])]
	vr["ai_battle_skill"].text = "Battle AI: " + SKILL_LABELS[int(settings["ai_battle_skill"])]
	vr["ai_campaign_skill"].text = "Campaign AI: " + SKILL_LABELS[int(settings["ai_campaign_skill"])]
	vr["ai_battle_skill"].tooltip_text = "Easy makes a new player's mistakes; Skilled reads the battle and punishes yours."
	vr["ai_campaign_skill"].tooltip_text = "Easy makes a new player's mistakes; Skilled concentrates its armies, picks its wars and fights one front at a time."


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


func _start_online() -> void:
	var net := get_node_or_null("/root/Net")
	if net == null or not net.has_server():
		_info.text = "Online play needs the game server: open the game from its web address."
		_info.add_theme_color_override("font_color", Kit.COL_BAD)
		return
	if not net.available and not await net.check_server():
		_info.text = "The game server is not available right now, so online play is off. Local play works as usual."
		_info.add_theme_color_override("font_color", Kit.COL_BAD)
		return
	var sd := int(seed_edit.text) if seed_edit.text.is_valid_int() else 1
	var nm := name_edit.text.strip_edges()
	if nm == "":
		nm = "Campaign"
	var st := CState.new_campaign(nm, sd, picks.duplicate(), settings, teams_array(), CData.pack)
	_creating = true
	_update()
	_info.text = "Creating the campaign on the server..."
	_info.add_theme_color_override("font_color", Color.WHITE)
	var user := _user_edit.text.strip_edges()
	if user != "":
		net.accounts.set_value("discord_user", user)
	var r: Dictionary = await net.create_campaign(st, picks[0], {"webhook_url": _hook_edit.text.strip_edges(),
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
		tele.event("online_create", {"from": "new", "humans": picks, "teams": teams_array(), "timeout_h": int(settings["turn_timeout_h"]),
			"webhook": _hook_edit.text.strip_edges() != ""})
	created_online.emit(str(r["data"]["id"]), str(r["data"].get("join_code", "")))
