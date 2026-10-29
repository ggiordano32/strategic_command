extends RefCounted
## The Chips page (battle menu): every chip with its glyph, name, its states and its tip, grouped by cluster. Built from
## Hud.legend_entries(), which reads the chips' own tips, so the page cannot drift from the bar. View only.

const Kit := preload("res://game/campaign/ui_kit.gd")


## Fill `box` (a VBox) with the legend; `entries` is Hud.legend_entries().
static func fill(box: VBoxContainer, entries: Array) -> void:
	var cl := ""
	for e in entries:
		if str(e["cluster"]) != cl:
			cl = str(e["cluster"])
			var h := Kit.label(cl, 17, Kit.COL_GOLD)
			h.name = "legend_head_" + cl.replace(" ", "_")
			box.add_child(h)
			box.add_child(Kit.rule())
		var row := Kit.hbox(10)
		row.name = "legend_" + str(e["key"])
		var glyph := TextureRect.new()
		glyph.texture = e["icon"]
		glyph.custom_minimum_size = Vector2(30.0, 30.0)
		glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glyph.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.modulate = Kit.COL_TEXT
		row.add_child(glyph)
		var v := Kit.vbox(1)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(v)
		var states := ""
		if not (e["states"] as Array).is_empty():
			states = "  -  " + ", ".join(e["states"])
		v.add_child(Kit.label(str(e["name"]) + states, 15, Color(1, 0.95, 0.7), true))
		var tip := str(e["tip"])
		if tip != "":
			v.add_child(Kit.label(tip, 13, Color(0.9, 0.9, 0.85), true))
		box.add_child(row)
