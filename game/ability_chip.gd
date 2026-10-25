extends Button
## A chip of the battle bar (docs/design/ui.md "The battle HUD pass"): an icon, a short name and a state
## word, 42 px high and at least 56 wide. Two kinds, one widget:
## - a toggle (`ab` -1): the orders the bar has always had (Fire: at will / hold, Skirmish, Stance ...); a tap
##   cycles it, the owner (hud.gd) sets the state word;
## - an ability (`ab` a UT.AB_* id): Auto / Hold / Use now (roles step 2); a tap cycles Auto -> Hold -> Use now
##   -> Auto (Pistols: Auto <-> Hold), Use now arms a target pick on the field and the chip then reads
##   "Use now: tap a target".
## The chip knows nothing of the sim: hud.gd and battle.gd set `state_word`, `armed`, `common`.
## View only.

const Kit := preload("res://game/campaign/ui_kit.gd")
const BTheme := preload("res://game/battle_theme.gd")
const AudioFx := preload("res://game/audio.gd")

const FONT := 15
const MIN_W := 56.0
const H := 42.0

var key := ""            # the chip's name in the bar ("fire", "grenade" ...)
var label_name := ""     # "Fire"
var ab := -1             # UT.AB_* for an ability chip, else -1
var state_word := ""     # "at will", "Hold" ...
var armed := false       # an ability waiting for its target
var common := true       # every selected unit has it (false: dimmed, tip "not all selected units")
var low := false         # goes under More first (Waypoints, Release on any width)
var pinned := false      # never goes under More (the armed ability)
var tip_title := ""
var tip_body := ""
var compact_mode := false


func _make_custom_tooltip(for_text: String) -> Object:
	return Kit.tip_box_or_null(str(get_meta("tip_title", "")), for_text)


## Build the chip: `icon_name` a UiIcons name, `toggle` a lit-when-on toggle button (Occupy, Release, ...).
func setup(p_key: String, p_name: String, icon_name: String, title: String, body: String, p_ab: int = -1, toggle: bool = false) -> void:
	Kit.install_tips()
	key = p_key
	name = "chip_" + p_key
	label_name = p_name
	ab = p_ab
	tip_title = title
	tip_body = body
	custom_minimum_size = Vector2(MIN_W, H)
	focus_mode = Control.FOCUS_NONE
	add_theme_font_size_override("font_size", FONT)
	pressed.connect(AudioFx.click)
	text = label_name   # (before the icon: an icon on an empty button is centred)
	if icon_name != "":
		Kit.set_icon(self, icon_name)
	if toggle:
		toggle_mode = true
		BTheme.plate(self, true)
	else:
		BTheme.plate(self)
	_apply_tip()
	text = full_text()


func full_text() -> String:
	if armed:
		return "Use now: tap a target"
	return label_name if state_word == "" else "%s: %s" % [label_name, state_word]


func compact_text() -> String:
	if armed:
		return "Tap a target"
	return label_name if state_word == "" else state_word


func text_for(compact: bool) -> String:
	return compact_text() if compact else full_text()


func set_mode(compact: bool) -> void:
	compact_mode = compact
	text = text_for(compact)


## The state word (and the armed flag of an ability) changed.
func set_state(word: String, p_armed: bool = false) -> void:
	state_word = word
	armed = p_armed
	pinned = p_armed
	text = text_for(compact_mode)
	if ab >= 0:
		# (an ability lights while its pick is armed)
		BTheme.plate(self, false, p_armed, false)


## Dim the chip when not every selected unit has it.
func set_common(c: bool) -> void:
	if common == c:
		return
	common = c
	modulate = Color(1, 1, 1, 1.0) if c else Color(1, 1, 1, 0.55)
	_apply_tip()


func _apply_tip() -> void:
	var body := tip_body
	if not common:
		body += "\nNot all selected units have it: only some obey."
	Kit.tip(self, tip_title, body)


## The width this chip needs in the given mode (text, icon, plate margins, the minimum).
func width_for(compact: bool) -> float:
	var t := text_for(compact)
	var fs := get_theme_font_size("font_size")
	var w := get_theme_font("font").get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if icon != null:
		w += icon.get_width() + get_theme_constant("h_separation")
	w += get_theme_stylebox("normal").get_minimum_size().x
	return maxf(w, MIN_W)
