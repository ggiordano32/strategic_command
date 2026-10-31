extends PanelContainer
## A teaching card in the story cards' frame (the kit's trim panel): a title line, one to three sentences, an optional
## objective line and a row of small buttons. The guided first campaign's lesson cards (tutorial.gd), the battle
## tutorial's step cards (tutorial_battle.gd) and the battle's first-time tips (a "Got it") all use it. View only.

const Kit := preload("res://game/campaign/ui_kit.gd")

signal pressed(key: String)   # a button's key

var title_label: Label
var text_label: Label
var obj_label: Label
var buttons := {}             # key -> Button
var _row: HBoxContainer
var _vbox: VBoxContainer


func _init() -> void:
	name = "tutor_card"
	add_theme_stylebox_override("panel", Kit.trim_box(Color(0.08, 0.09, 0.08, 0.93), 10.0))
	mouse_filter = Control.MOUSE_FILTER_STOP
	_vbox = Kit.vbox(4)
	add_child(_vbox)
	title_label = Kit.label("", 15, Kit.COL_GOLD)
	title_label.name = "tutor_title"
	_vbox.add_child(title_label)
	text_label = Kit.label("", 14, Kit.COL_BONE, true)
	text_label.name = "tutor_text"
	_vbox.add_child(text_label)
	obj_label = Kit.label("", 13, Kit.COL_GOOD, true)
	obj_label.name = "tutor_obj"
	obj_label.visible = false
	_vbox.add_child(obj_label)
	_row = Kit.hbox(6)
	_row.name = "tutor_buttons"
	_vbox.add_child(_row)


## Set the card's words. `obj` "" hides the objective line; `width` is the text's wrap width.
func setup(title: String, text: String, obj: String, width: float) -> void:
	title_label.text = title
	title_label.visible = title != ""
	text_label.text = text
	text_label.custom_minimum_size.x = width
	obj_label.text = obj
	obj_label.visible = obj != ""
	custom_minimum_size.x = 0.0
	reset_size()
	reset_size.call_deferred()   # (again once the label has wrapped: a card set before its first layout stood screen-tall)


## Add a small button (key names it "tutor_<key>").
func add_button(key: String, label: String) -> Button:
	var b := Kit.button(label, func(): pressed.emit(key), 0, 13)
	b.name = "tutor_" + key
	b.custom_minimum_size.y = 34.0
	Kit.nav_style(b)
	_row.add_child(b)
	buttons[key] = b
	return b


## The compact strip (a lesson kept over its popup): only the title and the objective line, the objective wrapped at `width`.
func set_strip(on: bool, width: float = 0.0) -> void:
	text_label.visible = not on
	_row.visible = not on
	obj_label.custom_minimum_size.x = width if on else 0.0
	z_index = 150 if on else 0   # above the dialog's dim, below the pointer
	reset_size()


func clear_buttons() -> void:
	for k in buttons:
		(buttons[k] as Button).queue_free()
	buttons.clear()


func set_met(met: bool, obj_text: String) -> void:
	obj_label.text = ("[done] " if met else "") + obj_text
	obj_label.add_theme_color_override("font_color", Kit.COL_GOOD if met else Kit.COL_GOLD)
	obj_label.visible = obj_text != ""
