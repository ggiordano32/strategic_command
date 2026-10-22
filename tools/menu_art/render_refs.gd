extends SceneTree
## Renders every faction's drawn mark (Kit.faction_mark at 512 px) on white into OUT/<pack>/<key>.png: the reference
## images for the painted crests (tools/menu_art/crests.py). The West marks are game/faction_emblem.gd with the faction
## colour as the frame; Rome's pack has no drawn emblem (Kit.faction_mark is a colour swatch), so its reference is a
## heater shield in the faction colour with a gold rim, the composition the model then paints. Needs a window:
##   godot --resolution 512x512 --script res://tools/menu_art/render_refs.gd -- --out=/abs/dir
const CData := preload("res://campaign/cdata.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")

var out := "/tmp/crest_ref"
var queue: Array = []   # [pack, faction index]
var frames := 0
var holder: Control
var vp: SubViewport


class Shield extends Control:
	var col := Color.RED
	func _draw() -> void:
		var sh := PackedVector2Array([Vector2(56, 70), Vector2(456, 70), Vector2(456, 250), Vector2(420, 360), Vector2(256, 470), Vector2(92, 360), Vector2(56, 250)])
		draw_colored_polygon(sh, Color(0.69, 0.54, 0.25))
		var inner := PackedVector2Array()
		for p in sh:
			inner.append(Vector2(256, 240) + (p - Vector2(256, 240)) * 0.92)
		draw_colored_polygon(inner, col)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1)
	for pack in ["west", "rome"]:
		DirAccess.make_dir_recursive_absolute(out + "/" + pack)
		CData.use_pack(pack)
		for f in CData.faction_count():
			queue.append([pack, f])
	vp = SubViewport.new()
	vp.size = Vector2i(512, 512)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color.WHITE
	bg.size = Vector2(512, 512)
	vp.add_child(bg)
	holder = Control.new()
	holder.size = Vector2(512, 512)
	vp.add_child(holder)


func _process(_d: float) -> bool:
	frames += 1
	if frames % 4 == 1 and frames > 1:
		var q: Array = queue.pop_front()
		CData.use_pack(q[0])
		vp.get_texture().get_image().save_png("%s/%s/%s.png" % [out, q[0], CData.FACTIONS[q[1]]["key"]])
		if queue.is_empty():
			quit(0)
			return true
	if frames % 4 == 1 or frames == 1:
		for c in holder.get_children():
			c.queue_free()
		var q: Array = queue[0]
		CData.use_pack(q[0])
		var f: int = q[1]
		var key := str(CData.FACTIONS[f]["key"])
		var m: Control
		if load("res://game/faction_emblem.gd").has(key) and q[0] == "west":
			m = Kit.faction_mark(f, 512.0)
		else:
			m = Shield.new()
			m.col = CData.faction_color(f)
		m.size = Vector2(512, 512)
		holder.add_child(m)
	return false
