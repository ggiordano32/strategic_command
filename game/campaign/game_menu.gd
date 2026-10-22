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
const Quality := preload("res://game/quality.gd")
const SoldierLayer := preload("res://game/soldier_layer.gd")
const BattleLook := preload("res://game/battle_look.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const MenuStyle := preload("res://game/menu/menu_style.gd")
const TouchScroll := preload("res://game/touch_scroll.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")

const COL_W := 440.0

var s  # the campaign screen
var page := "main"      # main | options | confirm
var column: PanelContainer
var body: VBoxContainer   # the page in the column
var _size_b: Button
var _quality_b: Button
var _soldiers_b: Button
var _look_b: Button
var _style_b: Button
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
# The same settings, saved values and cycles as the title screen's Options page (game/main.gd).

func _build_options() -> void:
	body.add_child(Kit.title("Options", 24))
	body.add_child(Kit.rule())
	body.add_child(Kit.label("Display", Kit.FONT, Kit.COL_GOLD))
	var r1 := Kit.flow(8)
	_size_b = _opt("menu_ui_size", _cycle_ui_size, "Size of buttons and text (S / M / L)")
	_quality_b = _opt("menu_quality", _cycle_quality, "Graphics. Auto: Low on devices that need the compatible soldiers path or that run a battle slowly, else High. Takes effect at the next battle; the map on the next open.")
	_soldiers_b = _opt("menu_soldiers", _cycle_soldiers, "How soldiers are drawn. Auto: the fast way, switching by itself to compatible if this device shows no soldiers.")
	for b in [_size_b, _quality_b, _soldiers_b]:
		r1.add_child(b)
	var fs := Kit.button("Fullscreen", _toggle_fullscreen, 150)
	Kit.nav_style(fs)
	fs.name = "menu_fullscreen"
	r1.add_child(fs)
	body.add_child(r1)
	body.add_child(Kit.label("Looks", Kit.FONT, Kit.COL_GOLD))
	var r2 := Kit.flow(8)
	_look_b = _opt("menu_battle_look", _cycle_look, "Battle map look: Diorama or Painterly. Takes effect at the next battle.")
	_style_b = _opt("menu_map_style", _cycle_style, "Campaign map style: Auto, Table or Relief. Takes effect on the next map.")
	r2.add_child(_look_b)
	r2.add_child(_style_b)
	body.add_child(r2)
	body.add_child(Kit.label("Audio", Kit.FONT, Kit.COL_GOLD))
	body.add_child(_audio_row())
	body.add_child(Kit.rule())
	var bb := Kit.button("Back", func(): back(), 120)
	bb.name = "menu_options_back"
	Kit.nav_style(bb)
	var brow := Kit.hbox(8)
	brow.add_child(bb)
	body.add_child(brow)
	_update()


func _opt(nm: String, cb: Callable, tip: String) -> Button:
	var b := Kit.button("", cb, 150)
	b.name = nm
	b.tooltip_text = tip
	Kit.nav_style(b)
	return b


func _update() -> void:
	if _size_b == null or not is_instance_valid(_size_b):
		return
	_size_b.text = "UI size: " + UiScale.size_name()
	var p := Quality.load_pref()
	_quality_b.text = "Graphics: " + (p if p != "auto" else "auto (%s)" % ("low" if Quality.is_low() else "high"))
	_soldiers_b.text = "Soldiers: " + ("compatible" if SoldierLayer.load_pref() == "cpu" else "auto")
	_look_b.text = "Battle look: " + BattleLook.pref()
	MapView.load_view_pref()
	_style_b.text = "Map: " + MapView.style_pref


func _cycle_ui_size() -> void:
	UiScale.cycle_size(get_window())
	_update()
	_layout()


func _cycle_quality() -> void:
	var p := Quality.load_pref()
	Quality.save_pref("high" if p == "auto" else ("low" if p == "high" else "auto"))
	_update()


func _cycle_soldiers() -> void:
	SoldierLayer.save_pref("auto" if SoldierLayer.load_pref() == "cpu" else "cpu")
	_update()


func _cycle_look() -> void:
	BattleLook.save_pref("painterly" if BattleLook.pref() == "diorama" else "diorama")
	_update()


func _cycle_style() -> void:
	var p := MapView.style_pref
	MapView.set_style("table" if p == "auto" else ("relief" if p == "table" else "auto"))
	_update()


func _toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _audio_row() -> Control:
	var box := Kit.vbox(8)
	box.name = "audio_row"
	var mute := Kit.button("", Callable(), 150)
	mute.name = "audio_mute"
	Kit.nav_style(mute)
	var mrow := Kit.hbox(8)
	mrow.add_child(mute)
	box.add_child(mrow)
	var labels := {}
	for k in ["master", "effects", "ambient"]:
		var h := Kit.hbox(4)
		var minus := Kit.button("-", Callable(), 42)
		Kit.nav_style(minus)
		var l := Kit.label("", Kit.FONT)
		l.custom_minimum_size = Vector2(150, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var plus := Kit.button("+", Callable(), 42)
		Kit.nav_style(plus)
		h.add_child(minus)
		h.add_child(l)
		h.add_child(plus)
		box.add_child(h)
		labels[k] = l
		minus.name = "audio_%s_minus" % k
		plus.name = "audio_%s_plus" % k
		var step := func(d: int):
			var a = AudioFx.inst()
			if a != null:
				a.set_volume(k, int(a.vol[k]) + d)
				AudioFx.play("tap", 1.0)
			_update_audio(mute, labels)
		minus.pressed.connect(step.bind(-10))
		plus.pressed.connect(step.bind(10))
	mute.pressed.connect(func():
		var a = AudioFx.inst()
		if a != null:
			a.set_muted(not a.muted)
		_update_audio(mute, labels))
	_update_audio(mute, labels)
	return box


func _update_audio(mute: Button, labels: Dictionary) -> void:
	var a = AudioFx.inst()
	var vol: Dictionary = a.vol if a != null else AudioFx.DEFAULTS
	mute.text = "Sound: " + ("off" if a != null and a.muted else "on")
	for k in labels:
		labels[k].text = "%s %d%%" % [str(k).capitalize(), int(vol[k])]
