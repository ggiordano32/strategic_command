extends RefCounted
## The How to play page's content (docs/design/campaign_rules.md "The tutorial", part 3): the eight sections of
## howto.gd as headings over short paragraphs, built into any VBoxContainer (the title menu's page, the in-game
## Menu's column). View only; the words live in howto.gd.

const Kit := preload("res://game/campaign/ui_kit.gd")
const Howto := preload("res://game/campaign/howto.gd")


## Fill `box` with the sections; `width` is the text's wrap width (labels need one inside a scroll).
static func fill(box: VBoxContainer, width: float) -> void:
	box.name = "howto_rows"
	for s in Howto.SECTIONS:
		var h := Kit.title(str(s["title"]), 18)
		h.name = "howto_h_" + str(s["id"])
		box.add_child(h)
		for k in s["lines"]:
			var l := Kit.label(Howto.text(str(k)), Kit.FONT, Kit.COL_BONE, true)
			l.name = "howto_" + str(k)
			l.custom_minimum_size.x = width
			box.add_child(l)
		box.add_child(Kit.rule())
