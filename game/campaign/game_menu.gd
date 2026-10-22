extends Control
## The in-game Menu (the top-right button of the campaign screen): an overlay dressed like the title screen. The map is
## dimmed, a dark column on the left holds the setting's emblem, the campaign's name and the entries in Cinzel:
## Resume, Save, Options, Controls, Main menu (with its confirm). Options shows the title screen's settings with the same
## controls and the same saved values (UI size, graphics, soldiers, fullscreen, battle look, map style, audio); a
## local campaign also gets Export save as text and Play online under the entries, an online one its Online page.
## Esc, the Android back request and Resume close it (one step back from Options / the confirm). View only.

const Kit := preload("res://game/campaign/ui_kit.gd")
const AudioFx := preload("res://game/audio.gd")
const UiScale := preload("res://game/ui_scale.gd")
const MenuStyle := preload("res://game/menu/menu_style.gd")
const OptionsRows := preload("res://game/menu/options_rows.gd")
const TouchScroll := preload("res://game/touch_scroll.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")

const COL_W := 440.0

var s  # the campaign screen
var page := "main"      # main | options | confirm
var column: PanelContainer
var body: VBoxContainer   # the page in the column
var _fade: Tween = null


func _init(screen) -> void:
	s = screen
	name = "game_menu"
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(e: InputEvent):
		# a tap on the dimmed map (outside the column) closes the menu like Resume
		if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(dim)
	column = PanelContainer.new()
	column.name = "menu_column"
	column.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	column.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.04, 0.035, 0.9)
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


## One step back: Options / the confirm to the entries, the entries to the map.
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
	var vp: Vector2 = s._vp()
	return UiScale.is_touch() or vp.x < 700.0


func _layout() -> void:
	var vp: Vector2 = s._vp()
	var w := minf(COL_W, vp.x)
	column.offset_left = 0.0
	column.offset_right = w
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
	h.add_child(Kit.emblem(str(s.st.get("pack", "rome")), 48.0))
	var v := Kit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := Kit.title(str(s.st.get("name", "Campaign")), 22)
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
	var online: bool = s.online != null
	_header("%s. %s" % [CData.date_text(int(s.st["turn"])), "Online: saved on the server." if online else "Saved automatically."])
	_entry("Resume", "menu_resume", close)
	_entry("Save", "menu_save", func():
		s.save()
		s.show_toast("Online: saved on the server." if online else "Saved.")
		close())
	_entry("Options", "menu_options", func():
		page = "options"
		_build())
	_entry("Controls", "menu_controls", func():
		close()
		s.controls_page.open())
	_entry("Main menu", "menu_leave", func():
		page = "confirm"
		_build())
	body.add_child(Kit.rule())
	var fl := Kit.flow(8)
	if online:
		fl.add_child(Kit.icon_button("Online", "online", func():
			close()
			s.onl.show_online(), 0))
	else:
		fl.add_child(Kit.icon_button("Export save as text", "export", func():
			close()
			s.panels.show_export(), 0))
		var net: Node = s.get_node_or_null("/root/Net")
		if net != null and net.has_server() and str(s.st["phase"]) == "plan" and int(s.st["turn"]) >= 0:
			var ob := Kit.icon_button("Play online", "online", func():
				close()
				s.panels.show_go_online(), 0)
			ob.name = "menu_go_online"
			fl.add_child(ob)
	body.add_child(fl)
	body.add_child(Kit.label("State %s" % CState.hash_text(s.st), Kit.FONT_SMALL, Kit.COL_DIM))


func _build_confirm() -> void:
	_header("Leave to the main menu?")
	body.add_child(Kit.label("The campaign is saved first; Continue on the title screen brings it back.", Kit.FONT, Color.WHITE, true))
	var row := Kit.hbox(8)
	var leave := Kit.button("Main menu", func():
		close()
		s.save()
		s.request_exit(), 140)
	leave.name = "menu_confirm_leave"
	row.add_child(leave)
	var stay := Kit.button("Stay", func(): back(), 110)
	stay.name = "menu_stay"
	row.add_child(stay)
	body.add_child(row)


# ----------------------------------------------------------------- options ---
# The same rows, settings and saved values as the title screen's Options page (game/menu/options_rows.gd).

var _rows: OptionsRows = null


func _build_options() -> void:
	body.add_child(Kit.title("Options", 24))
	body.add_child(Kit.rule())
	_rows = OptionsRows.new()
	_rows.build(body, {"prefix": "menu", "narrow": true, "title": false, "help": false, "win": get_window(), "on_size": _layout})
	body.add_child(Kit.rule())
	var bb := Kit.button("Back", func(): back(), 120)
	bb.name = "menu_options_back"
	Kit.nav_style(bb)
	var brow := Kit.hbox(8)
	brow.add_child(bb)
	body.add_child(brow)
