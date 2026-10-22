extends SceneTree
## Painted faction crests (game/faction_crest.gd, assets/ui/crests/<pack>/<key>.png + _64.png): checks that every
## faction of both packs has both files, that Kit.faction_mark returns the painted control under the painted setting
## and the drawn one (West emblem) or the swatch (Rome) under drawn, and that a missing file falls back; renders
## every crest at 128 / 64 / 24 px (and the 24 px faction colour beside it) on dark and light grounds into
## docs/screenshots/crests.png (West row 1 and 2, Rome row 3 and 4). Needs a window:
##   godot --resolution 1300x900 --script res://tests/crest_gallery.gd [-- --out=path.png]

const CData := preload("res://campaign/cdata.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const Crest := preload("res://game/faction_crest.gd")
const FE := preload("res://game/faction_emblem.gd")
const MenuPrefs := preload("res://game/menu/menu_prefs.gd")

var out := "res://docs/screenshots/crests.png"
var fails := 0
var frames := 0
var vp: SubViewport


func _check(c: bool, what: String) -> void:
	if not c:
		fails += 1
		print("FAIL ", what)


func _set_style(v: String) -> void:
	var cf := ConfigFile.new()
	cf.load(MenuPrefs.SETTINGS)
	cf.set_value("menu", "emblems", v)
	cf.save(MenuPrefs.SETTINGS)


class Sheet extends Control:
	var cells: Array = []   # [pack, key, Color]
	const CW := 240.0
	const RH := 150.0
	func _draw() -> void:
		var Crest = load("res://game/faction_crest.gd")
		for i in cells.size():
			var c: Array = cells[i]
			var col := i % 8
			var row := (i / 8) * 2
			for g in 2:
				var r := Rect2(col * CW, (row + g) * RH, CW, RH)
				draw_rect(r, Color(0.12, 0.14, 0.12) if g == 0 else Color(0.85, 0.82, 0.72))
				var x := r.position.x + 8.0
				var y := r.position.y + 10.0
				draw_texture_rect(Crest.texture(c[0], c[1], 256.0), Rect2(x, y, 128, 128), false)
				draw_texture_rect(Crest.texture(c[0], c[1], 64.0), Rect2(x + 136, y, 64, 64), false)
				draw_texture_rect(Crest.texture(c[0], c[1], 64.0), Rect2(x + 136, y + 72, 24, 24), false)
				draw_rect(Rect2(x + 166, y + 72, 24, 24), c[2])


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	var prior := MenuPrefs.stored_emblems()
	var cells: Array = []
	for pack in ["west", "rome"]:
		CData.use_pack(pack)
		for f in CData.faction_count():
			var key := str(CData.FACTIONS[f]["key"])
			cells.append([pack, key, CData.faction_color(f)])
			_check(ResourceLoader.exists(Crest.DIR + pack + "/" + key + ".png") or FileAccess.file_exists(Crest.DIR + pack + "/" + key + ".png"), "%s/%s has the 256 px crest" % [pack, key])
			_check(ResourceLoader.exists(Crest.DIR + pack + "/" + key + "_64.png") or FileAccess.file_exists(Crest.DIR + pack + "/" + key + "_64.png"), "%s/%s has the 64 px crest" % [pack, key])
			var t256 := Crest.texture(pack, key, 256.0)
			var t64 := Crest.texture(pack, key, 64.0)
			_check(t256 != null and t256.get_width() == 256 and t256.get_height() == 256, "%s/%s 256 px texture is 256 x 256" % [pack, key])
			_check(t64 != null and t64.get_width() == 64 and t64.get_height() == 64, "%s/%s 64 px texture is 64 x 64" % [pack, key])
			_set_style("painted")
			var pm := Kit.faction_mark(f, 30.0)
			_check(pm.get_script() == Crest and pm.custom_minimum_size == Vector2(30, 30), "%s/%s: painted setting gives the crest control" % [pack, key])
			_check(pm.get("small") == true and (Crest.mark(pack, key, 100.0).get("small") == false), "%s/%s: the 64 px file at 64 px and below, the 256 px above" % [pack, key])
			_set_style("drawn")
			var dm := Kit.faction_mark(f, 30.0)
			_check(dm.get_script() != Crest, "%s/%s: drawn setting gives the drawn mark" % [pack, key])
			_check((dm is ColorRect) == not FE.has(key), "%s/%s: drawn is the emblem (West) or the swatch (Rome)" % [pack, key])
			pm.free()
			dm.free()
	_check(not Crest.wanted("west", "no_such_faction"), "a faction without a crest file falls back")
	_set_style(prior)
	CData.use_pack("rome")
	var s := Sheet.new()
	s.cells = cells
	s.size = Vector2(1920, 600)
	vp = SubViewport.new()
	vp.size = Vector2i(1920, 600)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	vp.add_child(s)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 6:
		var img := vp.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(out))
		print("saved ", out, " fails=", fails)
		quit(1 if fails > 0 else 0)
	return false
