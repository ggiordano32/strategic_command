extends Control
## The battle's Menu (the top-right button of a battle that is not a campaign battle): the campaign Menu's overlay
## (game/campaign/game_menu.gd) for the field. The field is dimmed, a dark column on the left holds the setting's
## emblem, the battle's name and the entries in Cinzel: Resume, Options, Controls, Leave the battle (with its
## confirm). Options shows the title screen's settings (game/menu/options_rows.gd). The battle stays paused while it
## is open (solo play; a co-op battle cannot pause and runs on, as with the unit book); Esc, the Android back request,
## Resume and a tap on the dimmed field close it (one step back from Options / the confirm). View only: leaving
## goes through the battle's own exit.

const Kit := preload("res://game/campaign/ui_kit.gd")
const AudioFx := preload("res://game/audio.gd")
const UiScale := preload("res://game/ui_scale.gd")
const MenuStyle := preload("res://game/menu/menu_style.gd")
const OptionsRows := preload("res://game/menu/options_rows.gd")
const TouchScroll := preload("res://game/touch_scroll.gd")

const COL_W := 440.0

signal closed
var battle   # the battle node (battle.gd): _open_controls(), _leave_now(), _count()
var title_text := "Battle"
var pack := "rome"
var page := "main"      # main | options | confirm
var column: PanelContainer
var body: VBoxContainer
var _fade: Tween = null
var _rows: OptionsRows = null


func _init(p_battle, p_title: String, p_pack: String) -> void:
	battle = p_battle
	title_text = p_title
	pack = p_pack
	name = "battle_menu"
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent):
		# a tap on the dimmed field (outside the column) closes the menu like Resume
		if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(dim)
	column = PanelContainer.new()
	column.name = "menu_column"
	column.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	column.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.04, 0.035, 0.92)
	sb.border_color = Color(Kit.COL_RULE, 0.7)
	sb.border_width_right = 1
	sb.set_content_margin_all(0)
	column.add_theme_stylebox_override("panel", sb)
	add_child(column)


func is_open() -> bool:
	return visible


func open() -> void:
	page = "main"
	_layout()
	_build()
	visible = true
	if _fade != null and _fade.is_valid():
		_fade.kill()
	modulate.a = 1.0
	if Kit.anim_on():
		modulate.a = 0.0
		_fade = create_tween()
		_fade.tween_property(self, "modulate:a", 1.0, 0.15)


func close() -> void:
	if not visible:
		return
	visible = false
	if _fade != null and _fade.is_valid():
		_fade.kill()
	modulate.a = 1.0
	closed.emit()


## One step back: Options / the confirm to the entries, the entries to the field.
func back() -> void:
	if page != "main":
		page = "main"
		_build()
	else:
		close()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		back()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:
		back()


func _phone() -> bool:
	return UiScale.is_touch() or get_viewport_rect().size.x < 700.0


func _layout() -> void:
	column.offset_left = 0.0
	column.offset_right = minf(COL_W, get_viewport_rect().size.x)
	column.offset_top = 0.0
	column.offset_bottom = 0.0


func _build() -> void:
	for c in column.get_children():
		column.remove_child(c)
		c.queue_free()
	var sc := TouchScroll.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(sc)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for k in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + k, 18 if k != "top" else 22)
	sc.add_child(m)
	body = Kit.vbox(8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(body)
	match page:
		"options":
			_build_options()
		"confirm":
			_build_confirm()
		_:
			_build_main()


func _header(sub: String) -> void:
	var h := Kit.hbox(12)
	h.add_child(Kit.emblem(pack, 48.0))
	var v := Kit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := Kit.title(title_text, 22)
	t.name = "menu_title"
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.custom_minimum_size.x = 40
	v.add_child(t)
	var l := Kit.label(sub, Kit.FONT_SMALL, Kit.COL_DIM)
	l.name = "menu_sub"
	v.add_child(l)
	h.add_child(v)
	body.add_child(h)
	body.add_child(Kit.rule())


func _entry(text: String, nm: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.name = nm
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 52 if _phone() else 46)
	b.pressed.connect(AudioFx.click)
	b.pressed.connect(cb)
	MenuStyle.entry_style(b, 24 if _phone() else 26, false)
	body.add_child(b)
	return b


func _build_main() -> void:
	_header("The battle goes on." if battle.coop != null else "The battle is paused.")
	_entry("Resume", "menu_resume", close)
	_entry("Options", "menu_options", func():
		page = "options"
		_build())
	_entry("Controls", "menu_controls", func():
		close()   # (the battle's pause is put back first; the controls page pauses on its own)
		battle._open_controls())
	_entry("Leave the battle", "menu_leave", func():
		page = "confirm"
		_build())


func _build_confirm() -> void:
	_header("Leave the battle?")
	var txt := "Back to the main menu. The battle is not saved."
	if battle.coop != null and battle._coop_others_in():
		txt = "Your units go to %s." % battle._coop_heir_name()
	var l := Kit.label(txt, Kit.FONT, Kit.COL_BONE, true)
	l.name = "menu_confirm_text"
	body.add_child(l)
	var row := Kit.hbox(8)
	var leave := Kit.button("Leave", func():
		visible = false
		battle._leave_now(), 140)
	leave.name = "menu_confirm_leave"
	leave.add_theme_color_override("font_color", Kit.COL_BAD)
	row.add_child(leave)
	var stay := Kit.button("Stay", func(): back(), 110)
	stay.name = "menu_stay"
	row.add_child(stay)
	body.add_child(row)


func _build_options() -> void:
	body.add_child(Kit.title("Options", 24))
	body.add_child(Kit.rule())
	_rows = OptionsRows.new()
	_rows.build(body, {"prefix": "bmenu", "narrow": true, "title": false, "help": false, "win": get_window(), "on_size": _layout})
	body.add_child(Kit.rule())
	var bb := Kit.button("Back", func(): back(), 120)
	bb.name = "menu_options_back"
	Kit.nav_style(bb)
	var brow := Kit.hbox(8)
	brow.add_child(bb)
	body.add_child(brow)
