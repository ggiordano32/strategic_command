extends Control
## New campaign screen: one or two human factions (any two; they are
## permanently allied), name, seed and settings. Emits `start(data, slot)`
## with fresh save data, or `back`.

signal start(data: Dictionary, slot: String)
signal back

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
	head.add_child(_mode_button)
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
	if picks.has(f):
		picks.erase(f)
	elif two:
		if picks.size() >= 2:
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
	if picks.size() < need:
		_info.text = "Choose %s faction%s." % ["your" if not two else "two", "" if need == 1 else "s (any two: the players are allied for good)"]
	else:
		var names: Array[String] = []
		for f in picks:
			names.append(CData.faction_name(f))
		_info.text = "Playing " + " and ".join(names) + (". Both players plan on this device, one after the other." if two else ".")
	_start_button.disabled = picks.size() < need
	var vr: Dictionary = _setting_buttons
	vr["victory_regions"].text = "Win at %d regions" % int(settings["victory_regions"])
	vr["victory_capitals"].text = "with %d great cities" % int(settings["victory_capitals"])
	vr["turn_timeout_h"].text = "Turn timeout: " + ("off" if int(settings["turn_timeout_h"]) == 0 else "%d h" % int(settings["turn_timeout_h"]))
	vr["autoresolve"].text = "Battles: " + ("ask" if str(settings["autoresolve"]) == "ask" else "always auto")
	vr["ai_aggression"].text = "AI: " + {70: "calm", 100: "normal", 130: "aggressive"}[int(settings["ai_aggression"])]


func _start() -> void:
	var sd := int(seed_edit.text) if seed_edit.text.is_valid_int() else 1
	var nm := name_edit.text.strip_edges()
	if nm == "":
		nm = "Campaign"
	var st := CState.new_campaign(nm, sd, picks.duplicate(), settings)
	var slot := Saves.slot_for(nm, sd)
	var data := {"state": st, "session": {"subs": [], "plans": {}, "seen": {}}}
	Saves.save(slot, data)
	start.emit(data, slot)
