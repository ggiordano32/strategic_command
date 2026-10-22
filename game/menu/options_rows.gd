extends RefCounted
## The Options rows, shared by the title screen's Options page (game/main.gd) and the in-game Menu's (game/campaign/
## game_menu.gd): each setting is a row, the label (16, bone) with a one-line description under it (13, dim) on the left
## and a segmented control on the right (the control under the label when `narrow`: phones and the in-game column).
## Sections Display / Looks / Audio / Help with a gold rule between. The values are the ones the cycle buttons kept:
## the same settings files, nothing new is stored. View only.
##
##   var rows := OptionsRows.new()
##   rows.build(parent, {"prefix": "home", "narrow": false, "title": true, "dev": false, "win": get_window(),
##       "on_size": Callable, "on_controls": Callable, "on_book": Callable, "on_tests": Callable})
##   rows.refresh()   # the controls show the stored values again
## Controls are named "<prefix>_<key>": ui_size, quality, soldiers, fullscreen, battle_look, map_style,
## menu_emblems; audio_mute and audio_master / audio_effects / audio_ambient (sliders).

const Kit := preload("res://game/campaign/ui_kit.gd")
const AudioFx := preload("res://game/audio.gd")
const UiScale := preload("res://game/ui_scale.gd")
const Quality := preload("res://game/quality.gd")
const SoldierLayer := preload("res://game/soldier_layer.gd")
const BattleLook := preload("res://game/battle_look.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const MenuPrefs := preload("res://game/menu/menu_prefs.gd")
const Emblem := preload("res://game/menu/emblem.gd")

var seg := {}            # key -> Kit.Segmented
var sliders := {}        # "master" / "effects" / "ambient" -> HSlider
var descs := {}          # key -> the description Label
var buttons := {}        # "controls" / "book" / "tests" -> Button
var _o := {}
var _vals := {}          # audio key -> the value Label
var _building := false


func build(parent: Control, o: Dictionary) -> void:
	_o = o
	_building = true
	var title: bool = bool(o.get("title", false))
	_section(parent, "Display", false)
	_choice(parent, "ui_size", "UI size", "Size of the buttons and text.", [["S", "S"], ["M", "M"], ["L", "L"]], UiScale.size_name(),
		"UI size", "Small, Medium or Large buttons and text. Large is easier on a phone or a tablet.", func(v):
			UiScale.set_size_name(_win(), str(v))
			_call("on_size"))
	_choice(parent, "quality", "Graphics", "How much detail to draw.", [["Auto", "auto"], ["High", "high"], ["Low", "low"]], Quality.load_pref(),
		"Graphics", "Auto picks Low on devices that need the compatible soldiers path or run a battle slowly, else High. Low: a plainer ground, " \
		+ "no grass or scrub, a still sea. Takes effect at the next battle; the map on the next open.", func(v):
			Quality.save_pref(str(v))
			refresh())
	_choice(parent, "soldiers", "Soldiers", "How the soldiers are drawn. Compatible works on every device.", [["Auto", "auto"], ["Compatible", "cpu"]],
		SoldierLayer.load_pref(), "Soldiers", "Auto: the fast way, switching by itself to compatible if this device shows no soldiers. " \
		+ "Compatible: always the way that works everywhere (a little more work per tick).", func(v): SoldierLayer.save_pref(str(v)))
	_toggle(parent, "fullscreen", "Fullscreen", "Fill the whole screen.", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN,
		"Fullscreen", "Works on desktop and Android browsers; iPhone Safari has no fullscreen for pages: use Add to Home Screen.", func(on: bool):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	_section(parent, "Looks", true)
	_choice(parent, "battle_look", "Battle look", "The look of the battle map.", [["Diorama", "diorama"], ["Painterly", "painterly"]], BattleLook.pref(),
		"Battle look", "Diorama: a tabletop miniatures board (splatted ground, rim light and outlines, saturated colour, a bevelled edge). " \
		+ "Painterly: the softer, grounded look. Takes effect at the next battle.", func(v): BattleLook.save_pref(str(v)))
	MapView.load_view_pref()
	_choice(parent, "map_style", "Campaign map", "The style of the campaign map.", [["Auto", "auto"], ["Table", "table"], ["Relief", "relief"]],
		MapView.style_pref, "Campaign map", "Auto: the map table (painted miniatures, banded relief and sea) for the Caribbean, the relief map for Rome. " \
		+ "Table and Relief force one. Takes effect on the next map.", func(v): MapView.set_style(str(v)))
	if title:
		_choice(parent, "menu_emblems", "Emblems", "The marks of the two settings.", [["Drawn", "drawn"], ["Painted", "painted"]],
			MenuPrefs.stored_emblems(), "Emblems", "Drawn in code, or painted pictures (when the files are installed).", func(v):
				MenuPrefs.set_emblems(str(v))
				if Engine.get_main_loop() is SceneTree:
					(Engine.get_main_loop() as SceneTree).call_group("menu_emblem", "queue_redraw")
				refresh())
	_section(parent, "Audio", true)
	var a = AudioFx.inst()
	_toggle(parent, "audio_mute", "Sound", "Everything you hear.", not (a != null and a.muted), "Sound", "Switches all sound on or off; the volumes below stay as set.", func(on: bool):
		var au = AudioFx.inst()
		if au != null:
			au.set_muted(not on))
	for k in ["master", "effects", "ambient"]:
		_slider(parent, k, {"master": "Master volume", "effects": "Effects", "ambient": "Ambient"}[k])
	if bool(o.get("help", title)):
		_section(parent, "Help", true)
		var row := Kit.flow(8)
		parent.add_child(row)
		for d in [["controls", "Controls", "on_controls"], ["book", "Unit book", "on_book"]]:
			var b := Kit.button(d[1], _o.get(d[2], Callable()), 150)
			Kit.nav_style(b)
			b.name = "%s_%s" % [str(o["prefix"]), "controls" if d[0] == "controls" else "unit_book"]
			row.add_child(b)
			buttons[d[0]] = b
		if bool(o.get("dev", false)):
			var tb := Kit.button("Tests and benchmarks", _o.get("on_tests", Callable()), 190)
			Kit.nav_style(tb)
			tb.name = "%s_tests" % str(o["prefix"])
			row.add_child(tb)
			buttons["tests"] = tb
	_building = false
	refresh()


## How many settings the page shows (capsules and sliders).
func find_row_count() -> int:
	return seg.size() + sliders.size()


func _win() -> Window:
	return _o["win"] as Window


func _call(key: String) -> void:
	var c = _o.get(key, Callable())
	if c is Callable and (c as Callable).is_valid():
		(c as Callable).call()


func _section(parent: Control, text: String, rule_before: bool) -> void:
	if rule_before:
		var sp := Control.new()
		sp.custom_minimum_size.y = 4
		parent.add_child(sp)
		parent.add_child(Kit.rule())
	var l := Kit.label(text, 18, Kit.COL_GOLD)
	l.name = "section_" + text.to_lower()
	parent.add_child(l)


## The row's frame: label + description left, the control right (below on a narrow layout).
func _frame(parent: Control, key: String, label: String, desc: String, control: Control) -> void:
	var left := Kit.vbox(1)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := Kit.label(label, 16, Kit.COL_BONE)
	left.add_child(l)
	var d := Kit.label(desc, 13, Kit.COL_DIM, true)
	d.name = "desc_" + key
	descs[key] = d
	if desc != "":
		left.add_child(d)
	var row: Control
	if bool(_o.get("narrow", false)):
		var v := Kit.vbox(4)
		v.add_child(left)
		control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(control)
		row = v
	else:
		var h := Kit.hbox(14)
		h.add_child(left)
		control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(control)
		row = h
	row.name = "row_" + key
	parent.add_child(row)


func _choice(parent: Control, key: String, label: String, desc: String, options: Array, value, tip_title: String, tip_text: String, cb: Callable) -> void:
	var sg := Kit.segmented(options, value, Callable(), "%s_%s" % [str(_o["prefix"]), key])
	sg.changed.connect(func(v):
		if not _building:
			cb.call(v))
	Kit.tip(sg, tip_title, tip_text)
	seg[key] = sg
	_frame(parent, key, label, desc, sg)


func _toggle(parent: Control, key: String, label: String, desc: String, on: bool, tip_title: String, tip_text: String, cb: Callable) -> void:
	var nm := key if key.begins_with("audio_") else "%s_%s" % [str(_o["prefix"]), key]
	var sg := Kit.toggle(on, Callable(), nm)
	sg.changed.connect(func(v):
		if not _building:
			cb.call(int(v) == 1))
	Kit.tip(sg, tip_title, tip_text)
	seg[key] = sg
	_frame(parent, key, label, desc, sg)


func _slider(parent: Control, k: String, label: String) -> void:
	var a = AudioFx.inst()
	var vol: Dictionary = a.vol if a != null else AudioFx.DEFAULTS
	var h := Kit.hbox(8)
	var s := Kit.slider(int(vol[k]), Callable(), 180.0)
	s.name = "audio_" + k
	var vl := Kit.label("", 15, Kit.COL_BONE)
	vl.custom_minimum_size.x = 48
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(s)
	h.add_child(vl)
	s.value_changed.connect(func(v: float):
		vl.text = "%d%%" % int(v)
		if _building:
			return
		var au = AudioFx.inst()
		if au != null:
			au.set_volume(k, int(v)))
	s.drag_ended.connect(func(_c: bool): AudioFx.play("tap", 1.0))
	Kit.tip(s, label, "Drag to set it from 0 to 100 percent.")
	sliders[k] = s
	_vals[k] = vl
	vl.text = "%d%%" % int(s.value)
	_frame(parent, "audio_" + k, label, "", h)


## The controls show the stored values again (a battle may have switched Soldiers, another page the size).
func refresh() -> void:
	_building = true
	var put := func(key: String, v):
		if seg.has(key):
			(seg[key] as Kit.Segmented).set_value(v)
	put.call("ui_size", UiScale.size_name())
	put.call("quality", Quality.load_pref())
	put.call("soldiers", SoldierLayer.load_pref())
	put.call("fullscreen", 1 if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else 0)
	put.call("battle_look", BattleLook.pref())
	MapView.load_view_pref()
	put.call("map_style", MapView.style_pref)
	put.call("menu_emblems", MenuPrefs.stored_emblems())
	var a = AudioFx.inst()
	put.call("audio_mute", 0 if a != null and a.muted else 1)
	var vol: Dictionary = a.vol if a != null else AudioFx.DEFAULTS
	for k in sliders:
		(sliders[k] as HSlider).value = int(vol[k])
		(_vals[k] as Label).text = "%d%%" % int(vol[k])
	if descs.has("quality"):
		var p := Quality.load_pref()
		(descs["quality"] as Label).text = "How much detail to draw%s." % (" (now %s)" % ("Low" if Quality.is_low() else "High") if p == "auto" else "")
	if descs.has("menu_emblems"):
		var e := MenuPrefs.stored_emblems()
		var none := e == "painted" and Emblem.painted("west") == null and Emblem.painted("rome") == null
		(descs["menu_emblems"] as Label).text = "The marks of the two settings." + (" (No painted files installed.)" if none else "")
	_building = false
