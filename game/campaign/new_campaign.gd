extends Control
## New campaign screen: one or two human factions (any two; they are
## permanently allied), name, seed and settings. Emits `start(data, slot)`
## with fresh save data, or `back`. Online mode (`online` = true): two
## factions, the first one tapped is yours; plus the Discord webhook, your
## Discord user id and (if the server wants one) an invite key; Start
## creates the campaign on the server and emits `created_online(id, code)`.

signal start(data: Dictionary, slot: String)
signal back
signal created_online(id: String, join_code: String)

const TouchScroll := preload("res://game/touch_scroll.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const Saves := preload("res://game/campaign/saves.gd")

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

var picks: Array[int] = []
var two := false
var name_edit: LineEdit
var seed_edit: LineEdit
var settings := CState.DEFAULT_SETTINGS.duplicate()
var _fbuttons: Array[Button] = []
var _mode_button: Button
var _info: Label
var _start_button: Button
var _setting_buttons := {}
var online := false
var _online_box: VBoxContainer
var _hook_edit: LineEdit
var _user_edit: LineEdit
var _invite_edit: LineEdit
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
	_mode_button = Kit.button("", _toggle_mode, 190)
	_mode_button.visible = not online
	head.add_child(_mode_button)
	if online:
		two = true
		t.text = "New online co-op campaign"
	head.add_child(Kit.button("Back", func(): back.emit(), 80))
	_start_button = Kit.button("Start", _start, 120, 17)
	_start_button.name = "start_campaign"
	head.add_child(_start_button)
	v.add_child(head)
	_info = Kit.label("", Kit.FONT, Color.WHITE, true)
	v.add_child(_info)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(grid)
	for f in CData.faction_count():
		var fd: Dictionary = CData.FACTIONS[f]
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(200, 54)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 13)
		b.text = "%s - %s" % [fd["name"], BLURB[fd["key"]]]
		b.name = "faction_" + str(fd["key"])
		var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
		img.fill(CData.faction_color(f))
		b.icon = ImageTexture.create_from_image(img)
		b.pressed.connect(_pick.bind(f))
		grid.add_child(b)
		_fbuttons.append(b)
	var row := Kit.flow(8)
	row.add_child(Kit.label("Name", Kit.FONT, Kit.COL_DIM))
	name_edit = LineEdit.new()
	name_edit.text = "Campaign"
	name_edit.custom_minimum_size = Vector2(180, 40)
	row.add_child(name_edit)
	row.add_child(Kit.label("Seed", Kit.FONT, Kit.COL_DIM))
	seed_edit = LineEdit.new()
	seed_edit.text = str(int(Time.get_unix_time_from_system()) % 100000)
	seed_edit.custom_minimum_size = Vector2(110, 40)
	row.add_child(seed_edit)
	v.add_child(row)
	var sr := Kit.flow(8)
	for k in ["victory_regions", "victory_capitals", "turn_timeout_h", "autoresolve", "ai_aggression"]:
		var b := Kit.button("", _cycle.bind(k), 0, 14)
		_setting_buttons[k] = b
		sr.add_child(b)
	v.add_child(sr)
	_online_box = Kit.vbox(6)
	_online_box.visible = online
	v.add_child(_online_box)
	var net := get_node_or_null("/root/Net")
	_online_box.add_child(Kit.label("Discord notifications (optional): a channel's webhook URL (Channel settings > Integrations > Webhooks), and your Discord user id for @mentions (Discord settings > Advanced > Developer mode, then right-click your name > Copy User ID).", 13, Kit.COL_DIM, true))
	_hook_edit = LineEdit.new()
	_hook_edit.placeholder_text = "https://discord.com/api/webhooks/..."
	_hook_edit.custom_minimum_size = Vector2(300, 40)
	_hook_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_online_box.add_child(_hook_edit)
	var r2 := Kit.flow(8)
	_user_edit = LineEdit.new()
	_user_edit.placeholder_text = "Your Discord user id"
	_user_edit.custom_minimum_size = Vector2(240, 40)
	_user_edit.text = str(net.accounts.data.get("discord_user", "")) if net else ""
	r2.add_child(_user_edit)
	_invite_edit = LineEdit.new()
	_invite_edit.placeholder_text = "Invite key (if the server asks)"
	_invite_edit.custom_minimum_size = Vector2(240, 40)
	_invite_edit.text = str(net.accounts.data.get("invite", "")) if net else ""
	r2.add_child(_invite_edit)
	_online_box.add_child(r2)
	if online and net != null and not bool(net.info.get("invite_required", true)):
		_invite_edit.visible = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--picks="):
			# Testing aid: --picks=rome,carthage
			for k in a.get_slice("=", 1).split(","):
				_pick(CData.faction_index(k))
	_update()


const CHOICES := {"victory_regions": [15, 20, 25, 30], "victory_capitals": [2, 3, 4, 5],
	"turn_timeout_h": [0, 12, 24, 48, 72], "autoresolve": ["ask", "auto"], "ai_aggression": [70, 100, 130]}


func _cycle(k: String) -> void:
	var ch: Array = CHOICES[k]
	var i := ch.find(settings[k])
	settings[k] = ch[(i + 1) % ch.size()]
	_update()


func _toggle_mode() -> void:
	two = not two
	if not two and picks.size() > 1:
		picks = [picks[0]]
	_update()


func _pick(f: int) -> void:
	if _creating:
		return
	if picks.has(f):
		picks.erase(f)
	elif two:
		if picks.size() >= 2:
			if online:
				picks[1] = f  # keep "you", change the ally
				_update()
				return
			picks.remove_at(0)
		picks.append(f)
	else:
		picks = [f]
	_update()


func _update() -> void:
	_mode_button.text = "Players: 2 (hot seat)" if two else "Players: 1 (solo)"
	for f in _fbuttons.size():
		_fbuttons[f].set_pressed_no_signal(picks.has(f))
	var need := 2 if two else 1
	if online and picks.size() < need:
		_info.text = "Tap your faction first, then your ally's (any two: you are allied for good)." if picks.is_empty() else "You play %s. Now tap your ally's faction." % CData.faction_name(picks[0])
	elif picks.size() < need:
		_info.text = "Choose %s faction%s." % ["your" if not two else "two", "" if need == 1 else "s (any two: the players are allied for good)"]
	elif online:
		_info.text = "You play %s, your ally %s. Each plans on their own device; the turn resolves when both have submitted." % [
			CData.faction_name(picks[0]), CData.faction_name(picks[1])]
	else:
		var names: Array[String] = []
		for f in picks:
			names.append(CData.faction_name(f))
		_info.text = "Playing " + " and ".join(names) + (". Both players plan on this device, one after the other." if two else ".")
	_start_button.disabled = picks.size() < need or _creating
	if online:
		for i in _fbuttons.size():
			_fbuttons[i].text = "%s%s - %s" % [CData.FACTIONS[i]["name"], " (you)" if not picks.is_empty() and picks[0] == i else (" (ally)" if picks.size() > 1 and picks[1] == i else ""), BLURB[CData.FACTIONS[i]["key"]]]
	var vr: Dictionary = _setting_buttons
	vr["victory_regions"].text = "Win at %d regions" % int(settings["victory_regions"])
	vr["victory_capitals"].text = "with %d great cities" % int(settings["victory_capitals"])
	vr["turn_timeout_h"].text = "Turn timeout: " + ("off" if int(settings["turn_timeout_h"]) == 0 else "%d h" % int(settings["turn_timeout_h"]))
	vr["autoresolve"].text = "Battles: " + ("ask" if str(settings["autoresolve"]) == "ask" else "always auto")
	vr["ai_aggression"].text = "AI: " + {70: "calm", 100: "normal", 130: "aggressive"}[int(settings["ai_aggression"])]


func _start() -> void:
	if online:
		_start_online()
		return
	var sd := int(seed_edit.text) if seed_edit.text.is_valid_int() else 1
	var nm := name_edit.text.strip_edges()
	if nm == "":
		nm = "Campaign"
	var st := CState.new_campaign(nm, sd, picks.duplicate(), settings)
	var slot := Saves.slot_for(nm, sd)
	var data := {"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}
	Saves.save(slot, data)
	start.emit(data, slot)


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
	var st := CState.new_campaign(nm, sd, picks.duplicate(), settings)
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
			_invite_edit.visible = true
			_info.text = "This server needs an invite key to create campaigns: ask the server's owner."
		else:
			_info.text = "Could not create it: " + (str(r["message"]) if str(r["message"]) != "" else str(r["error"]))
		return
	var tele := get_node_or_null("/root/Telemetry")
	if tele != null:
		tele.event("online_create", {"from": "new", "humans": picks, "timeout_h": int(settings["turn_timeout_h"]),
			"webhook": _hook_edit.text.strip_edges() != ""})
	created_online.emit(str(r["data"]["id"]), str(r["data"].get("join_code", "")))
