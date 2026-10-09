extends RefCounted
## The battle screen on the overworld (docs/STATUS.md item 4b): one screen
## in two states, for auto-resolved and fought battles alike.
##
## Pre-battle (the Battles dialog, solo and online): a map preview (the
## settlement drawn from its seed by city_preview.gd, or the field's ground
## and woods with both deployment edges), both sides as rows of unit cards
## (symbol with tier mark, men, a health bar of men against full strength)
## grouped by army and faction, garrison and support armies included, the
## siege equipment line, the odds bar, and the buttons.
##
## Result (after auto-resolve or a fought battle): VICTORY / DEFEAT / DRAW
## for the viewing player, the one-line outcome, "Auto-resolved" / "Fought",
## and the same card rows with survivors against fielded (the lost part
## marked) and each unit's losses; per-side totals with the side's kills
## (the enemy's dead). A fought battle's outcome also carries each unit's
## kills (the sim's u_kills): its cards show "kills N"; an auto-resolved one
## does not, and the note says kills are counted per side.
##
## View only: reads the state, a snapshot taken when the battle starts and
## the outcome dictionary (CBattle.outcome_from_result); never writes state.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const UT := preload("res://sim/unit_types.gd")
const Terrain := preload("res://sim/terrain.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const UiIcons := preload("res://game/ui_icons.gd")
const Icons := preload("res://game/unit_icons.gd")
const CityPreview := preload("res://game/campaign/city_preview.gd")
const GroundPalette := preload("res://game/ground_palette.gd")

const WIDE := 640.0       # logical px: sides side by side from this dialog width
const COL_HEALTH := Color(0.45, 0.8, 0.4)
const COL_LOST := Color(0.9, 0.22, 0.18)
const KILLS_NOTE := "Each card shows that unit's own losses; kills are counted per side (the battle does not record which unit killed whom)."
## A fought battle's outcome carries each unit's kills (CBattle.outcome_from_result).
const KILLS_NOTE_UNITS := "Each card shows that unit's own losses and the enemies its men killed (kills)."


# ------------------------------------------------------------- snapshot ---

## Plain data of battle b as it stands (taken when the battle starts, so the
## result can be drawn after the state has moved on): per side, groups
## {army (-1 garrison), f, name, support, units: [{unit, ty, n, full, on}]}
## in the order CBattle.build fields them (`on` 0: past the side's
## BATTLE_SIDE_MAX, left out of the battle). me: the viewer's side (-1
## neither).
static func snapshot(st: Dictionary, b: Dictionary, viewer: int) -> Dictionary:
	var r := int(b["r"])
	var kind := str(b.get("kind", ""))
	var arm := CRules.battle_armies(st, b)
	var facs := CRules.battle_factions(st, b)
	var reinf: Array = b.get("reinf", [])
	var sides := [[], []]
	for sd in 2:
		var fielded := 0
		for a in arm[sd]:
			var f := int(a["f"])
			var g := {"army": int(a["id"]), "f": f, "name": "%s army" % str(CData.FACTIONS[f]["adj"]),
				"support": 1 if reinf.has(int(a["id"])) else 0, "units": []}
			for k in CState.unit_count(a):
				var u: Dictionary = a["units"][k]
				var n := int(u["n"])
				var ty := UT.index_of(str(u["t"]))
				var on := n > 0 and fielded < CData.BATTLE_SIDE_MAX
				if on:
					fielded += 1
				g["units"].append({"unit": k, "ty": ty, "n": n, "full": maxi(UT.size_of(ty), 1), "on": 1 if on else 0,
					"ak": str(u.get("ak", ""))})
			sides[sd].append(g)
	if kind != "field":
		var gar := CRules.garrison(st, r)
		if not gar.is_empty():
			var g2 := {"army": -1, "f": CState.owner(st, r), "name": "Garrison of %s" % str(CData.REGIONS[r]["city"]),
				"support": 0, "units": []}
			for k in gar.size():
				var ty2 := UT.index_of(str(gar[k]["t"]))
				var n2 := int(gar[k]["n"])
				g2["units"].append({"unit": k, "ty": ty2, "n": n2, "full": maxi(int(gar[k]["full"]), 1), "on": 1 if n2 > 0 else 0})
			sides[1].append(g2)
	var me := -1
	for sd in 2:
		if me < 0 and facs[sd].has(viewer):
			me = sd
	if me < 0 and viewer >= 0:
		for sd in 2:
			for f in facs[sd]:
				if me < 0 and int(f) >= 0 and CState.friendly(st, int(f), viewer):
					me = sd
	return {"bid": int(b["id"]), "r": r, "kind": kind, "settlement": int(b.get("settlement", 1)),
		"facs": facs, "lead": [int(b["att_f"]), int(b["def_f"])], "sides": sides, "me": me,
		"walls": CState.walls(st, r), "equip": CBattle.siege_equipment(st, b), "title": title(st, b),
		"works": CBattle.works_of(st, b) if int(b.get("settlement", 1)) == 0 else {}}


static func _names(list: Array) -> String:
	var out: Array[String] = []
	for f in list:
		out.append(CData.faction_name(int(f)))
	return " and ".join(out)


## "Assault on Roma (Latium): Rome storm the walls held by Greeks".
static func title(st: Dictionary, b: Dictionary) -> String:
	var r := int(b["r"])
	var facs := CRules.battle_factions(st, b)
	var a := _names(facs[0])
	var d := _names(facs[1])
	var city := str(CData.REGIONS[r]["city"])
	var reg := str(CData.REGIONS[r]["name"])
	match str(b.get("kind", "")):
		"assault":
			return "Assault on %s (%s): %s storm the walls held by %s" % [city, reg, a, d]
		"sally":
			return "Sally from %s (%s): %s ride out against the besiegers, %s (a field battle)" % [city, reg, d, a]
		"relief":
			return "Relief of %s (%s): %s and the garrison against the besiegers, %s (a field battle)" % [city, reg, d, a]
		"field":
			return "Field battle in %s: %s ran into %s in the open (no walls, no garrison)" % [reg, a, d]
	return "Battle of %s (%s): %s (attacking) against %s" % [city, reg, a, d]


## The siege equipment line ("" for a field battle or an open town).
static func equipment_line(snap: Dictionary) -> String:
	var w := int(snap["walls"])
	if int(snap["settlement"]) == 0 or w <= 0:
		return ""
	var eq: Dictionary = snap["equip"]
	var parts: Array[String] = []
	if int(eq.get("ladders", 0)) > 0:
		parts.append("%d sets of ladders" % int(eq["ladders"]))
	if int(eq.get("ram", 0)) > 0:
		parts.append("a ram")
	var nt := int(eq.get("towers", 0))
	if nt > 0:
		parts.append("a siege tower" if nt == 1 else "%d siege towers" % nt)
	var lst := ""
	for k in parts.size():
		lst += (", " if k < parts.size() - 1 else " and ") if k > 0 else ""
		lst += parts[k]
	var t := "Siege equipment: " + (lst if not parts.is_empty() else "none (the attackers' own artillery only)")
	if w >= 2:
		t += ". The walls (level %d) carry towers with engines." % w
	else:
		t += ". Walls level 1, no towers."
	return t


## The field works line of a field battle ("" none): each side's stakes
## lines and caltrop fields to place in the deployment, and the defenders'
## camp when they stand fortified.
static func works_line(snap: Dictionary) -> String:
	var wk: Dictionary = snap.get("works", {})
	if wk.is_empty():
		return ""
	var parts: Array[String] = []
	for cs in 2:
		var w: Array = wk["w"][cs]
		var bits: Array[String] = []
		if int(w[0]) > 0:
			bits.append("%d stakes line%s" % [int(w[0]), "" if int(w[0]) == 1 else "s"])
		if int(w[1]) > 0:
			bits.append("%d caltrop field%s" % [int(w[1]), "" if int(w[1]) == 1 else "s"])
		if not bits.is_empty():
			parts.append("%s %s" % ["attackers" if cs == 0 else "defenders", " and ".join(bits)])
	var t := ""
	if bool(wk["fort"]):
		t = "The defenders are fortified: they fight in a camp, a ditch and a wooden palisade with open gaps. "
	if not parts.is_empty():
		t += "Field works (placed in the deployment): " + "; ".join(parts) + "."
	return t.strip_edges()


# ------------------------------------------------------------ pre-battle ---

static func _dialog_w(s) -> float:
	return minf(900.0, s._vp().x - 24) - 48


## The pre-battle screen of pending battle b as a card. The button row
## ("battle_buttons") sits under the odds, near the top, with a box for
## status lines above it ("battle_status"; the online dialog swaps the
## buttons and adds who holds the battle there).
static func pre(s, st: Dictionary, b: Dictionary) -> Control:
	var snap := snapshot(st, b, int(s.f))
	var w := _dialog_w(s)
	var wide := w >= WIDE
	var p := Kit.panel(Color(1, 1, 1, 0.06), 8)
	p.name = "battle_screen"
	var v := Kit.vbox(8)
	p.add_child(v)
	v.add_child(Kit.label(str(snap["title"]), Kit.FONT, Kit.COL_GOLD, true))
	var r := int(b["r"])
	# Map preview and the facts beside it (below it on a narrow screen).
	var top: BoxContainer = Kit.vbox(8)
	if wide:
		top = Kit.hbox(10)
	v.add_child(top)
	var pw := minf(w * (0.42 if wide else 1.0), 360.0)
	var prev: Control
	var cap := ""
	if int(snap["settlement"]) != 0:
		prev = CityPreview.for_region(st, r, pw)
		var sz: Vector2 = prev.custom_minimum_size
		var maxh := 300.0
		if s._vp().y < 600:
			maxh = 140.0  # a landscape phone: the buttons stay in sight
		elif wide:
			maxh = 230.0
		if sz.y > maxh:
			prev.custom_minimum_size = sz * (maxh / sz.y)
		cap = CBattle.city_caption(st, r) + ". Defenders inside, the arrow is the attackers' approach."
	else:
		prev = FieldPreview.new(r, [CData.faction_color(int(snap["lead"][0])), CData.faction_color(int(snap["lead"][1]))],
			Vector2(pw, minf(pw * 0.55, 120.0 if s._vp().y < 600 else 170.0)))
		var rd: Dictionary = CData.REGIONS[r]
		var where := "outside the walls of %s" % rd["city"] if str(snap["kind"]) in ["sally", "relief"] else "in the open"
		cap = "%s ground %s, woods %d%%. Attackers deploy from the south, defenders from the north." % [
			Terrain.KIND_NAMES[int(rd["terrain"])], where, int(rd["forest"])]
	prev.name = "battle_preview"
	prev.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	prev.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(prev)
	var info := Kit.vbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	info.add_child(Kit.label(cap, Kit.FONT_SMALL, Kit.COL_DIM, true))
	var eq := equipment_line(snap)
	if eq != "":
		var el := Kit.label(eq, Kit.FONT_SMALL, Color.WHITE, true)
		el.name = "siege_equipment"
		Kit.label_icon(el, "ladder")
		info.add_child(el)
	var wl := works_line(snap)
	if wl != "":
		var wlab := Kit.label(wl, Kit.FONT_SMALL, Color.WHITE, true)
		wlab.name = "field_works"
		Kit.label_icon(wlab, "palisade" if bool(snap["works"]["fort"]) else "stakes")
		info.add_child(wlab)
	var facs: Array = snap["facs"]
	var hs := CRules.battle_humans(st, b)
	var human_att: bool = not hs.is_empty() and facs[0].has(hs[0])
	var lead: Array = snap["lead"]
	info.add_child(Kit.odds_view(CBattle.battle_odds(st, b), 0 if human_att else 1, [_names([lead[0]]), _names([lead[1]])],
		[CData.faction_color(int(lead[0])), CData.faction_color(int(lead[1]))], "Balance of power (estimate from the battle formula):"))
	if not (b["reinf"] as Array).is_empty():
		if b.has("edge"):
			info.add_child(Kit.label("Reinforcements within a turn's march join%s." % (
				", arriving from the map edge they march from" if int(b.get("settlement", 1)) == 0 else ""), Kit.FONT_SMALL, Kit.COL_DIM, true))
		else:
			info.add_child(Kit.label("Reinforcements from neighbouring regions join the line.", Kit.FONT_SMALL, Kit.COL_DIM, true))
	var status := Kit.vbox(4)
	status.name = "battle_status"
	info.add_child(status)
	var h := Kit.hbox(8)
	h.name = "battle_buttons"
	h.alignment = BoxContainer.ALIGNMENT_END
	var bid := int(b["id"])
	var ab := Kit.icon_button("Auto-resolve", "end_turn", func(): s.auto_resolve(bid), 130)
	ab.name = "auto_%d" % bid
	h.add_child(ab)
	var fb := Kit.icon_button("Fight", "battles", func(): s.fight(bid), 110)
	fb.name = "fight_%d" % bid
	h.add_child(fb)
	info.add_child(h)
	v.add_child(_sides(snap, {}, wide))
	return p


## Both sides' card rows: attackers left, defenders right (stacked when
## narrow). res: outcome units keyed "army:unit" (empty: pre-battle).
static func _sides(snap: Dictionary, res: Dictionary, wide: bool) -> Control:
	var box: BoxContainer = Kit.vbox(10)
	if wide:
		box = Kit.hbox(12)
	box.name = "battle_sides"
	for sd in 2:
		box.add_child(_side(snap, sd, res))
	return box


static func _side(snap: Dictionary, sd: int, res: Dictionary) -> Control:
	var col := Kit.vbox(6)
	col.name = "side_%d" % sd
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.0
	var groups: Array = snap["sides"][sd]
	var men := 0
	var units := 0
	for g in groups:
		for u in g["units"]:
			if int(u["on"]) != 0:
				men += int(u["n"])
				units += 1
	var lead := int(snap["lead"][sd])
	var you := " (you)" if int(snap["me"]) == sd else ""
	var head := "%s%s: %s" % ["Attackers" if sd == 0 else "Defenders", you, _names(snap["facs"][sd])]
	col.add_child(Kit.label(head, Kit.FONT, CData.faction_color(lead).lightened(0.35), true))
	if res.is_empty():
		col.add_child(Kit.label("%d units, %d men" % [units, men], Kit.FONT_SMALL, Kit.COL_DIM))
	var tot := {"fielded": 0, "back": 0, "dead": 0, "fled": 0}
	for g in groups:
		var gh := Kit.hbox(6)
		gh.add_child(Kit.swatch(CData.faction_color(int(g["f"])), 12))
		var gmen := 0
		for u in g["units"]:
			gmen += int(u["n"])
		var gt := str(g["name"]) + (" (support)" if int(g["support"]) != 0 else "")
		gh.add_child(Kit.label("%s, %d men" % [gt, gmen], Kit.FONT_SMALL, Color.WHITE, true))
		col.add_child(gh)
		var fl := Kit.flow(5)
		for u in g["units"]:
			var card := UnitCard.new(int(u["ty"]), int(u["n"]), int(u["full"]), CData.faction_color(int(g["f"])))
			card.fielded = int(u["on"]) != 0
			card.ak = UT.ammo_index(str(u.get("ak", "")))
			var key := "%d:%d" % [int(g["army"]), int(u["unit"])]
			if not res.is_empty() and card.fielded:
				var e: Dictionary = res.get(key, {})
				if not e.is_empty():
					var routed := int(e["routed"])
					var back := mini(int(e["remaining"]) + int(e["withdrawn"]) + routed * CData.ROUT_RETURN / 100, card.men)
					card.back = back
					card.dead = int(e["killed"])
					card.set_kills(int(e.get("kills", -1)))
					tot["fielded"] += card.men
					tot["back"] += back
					tot["dead"] += int(e["killed"])
					tot["fled"] += routed
				else:
					card.back = card.men
					tot["fielded"] += card.men
					tot["back"] += card.men
			card.name = "card_%d_%s" % [sd, key.replace(":", "_").replace("-", "g")]
			card.tooltip_text = card.describe()
			fl.add_child(card)
		col.add_child(fl)
	if not res.is_empty():
		col.set_meta("totals", tot)
	return col


# ---------------------------------------------------------------- result ---

## The result screen of the battle in `snap` (taken at its start) with
## `outcome` applied: st is the state after it, events the texts of the
## events it produced (newest last).
static func result(s, snap: Dictionary, outcome: Dictionary, st: Dictionary, events: Array) -> Control:
	var w := _dialog_w(s)
	var wide := w >= WIDE
	var v := Kit.vbox(8)
	v.name = "battle_result"
	var me := int(snap["me"])
	var winner := 1 if int(outcome.get("winner", 1)) != 0 else 0
	var draw := int(outcome.get("draw", 0)) != 0
	var word := "DRAW"
	var wcol := Kit.COL_GOLD
	var wicon := "draw"
	if not draw:
		if me < 0:
			word = "ATTACKERS WIN" if winner == 0 else "DEFENDERS WIN"
			wcol = Color.WHITE
			wicon = "victory"
		elif winner == me:
			word = "VICTORY"
			wcol = Kit.COL_GOOD
			wicon = "victory"
		else:
			word = "DEFEAT"
			wcol = Kit.COL_BAD
			wicon = "defeat"
	var banner := Kit.label(word, 40, wcol)
	banner.name = "result_banner"
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_constant_override("outline_size", 6)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	# The word between two copies of its icon (laurel, broken sword, scales).
	var bh := Kit.hbox(14)
	bh.name = "result_banner_row"
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	for k in 3:
		if k == 1:
			bh.add_child(banner)
			continue
		var ic := TextureRect.new()
		ic.name = "result_icon_%d" % (k / 2)
		ic.texture = UiIcons.tex(wicon, 38)
		ic.self_modulate = wcol
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bh.add_child(ic)
	v.add_child(bh)
	var mode := "Auto-resolved" if str(outcome.get("mode", "")) == "auto" else "Fought"
	if int(outcome.get("forfeit", 0)) != 0:
		mode = "Fought (left the field)"
	if int(outcome.get("live", 0)) != 0:
		mode = "Fought together"
	var ml := Kit.label("%s. %s" % [mode, str(snap["title"]).get_slice(":", 0)], Kit.FONT_SMALL, Kit.COL_DIM, true)
	ml.name = "result_mode"
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ml)
	var ol := Kit.label(outcome_line(snap, outcome, st), Kit.FONT, Color.WHITE, true)
	ol.name = "result_outcome"
	ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ol)
	if int(outcome.get("scale", 100)) < 100:
		v.add_child(Kit.label("(Big battle: auto-resolved at half unit size, results scaled up.)", Kit.FONT_SMALL, Kit.COL_DIM, true))
	var res := {}
	for e in outcome.get("units", []):
		res["%d:%d" % [int(e["army"]), int(e["unit"])]] = e
	var sides := _sides(snap, res, wide)
	v.add_child(sides)
	# Totals at the foot of each side; a side's kills are the other's dead.
	var tots: Array = []
	for sd in 2:
		tots.append(sides.get_child(sd).get_meta("totals", {"fielded": 0, "back": 0, "dead": 0, "fled": 0}))
	for sd in 2:
		var t: Dictionary = tots[sd]
		var lost := int(t["fielded"]) - int(t["back"])
		var txt := "Fielded %d, back %d, lost %d (%d dead, %d fled). Kills: %d." % [int(t["fielded"]), int(t["back"]), lost,
			int(t["dead"]), int(t["fled"]), int(tots[1 - sd]["dead"])]
		# Shown as a row of icon figures (men fielded / back, dead, fled,
		# kills); the sentence stays as the row's tooltip and in a hidden
		# label (totals_N) for the tests and the record.
		var row := Kit.flow(12)
		row.name = "totals_row_%d" % sd
		row.tooltip_text = txt
		row.add_child(Kit.icon_label("%d fielded, %d back" % [int(t["fielded"]), int(t["back"])], "men", Kit.FONT_SMALL, Kit.COL_GOLD))
		row.add_child(Kit.icon_label("%d dead" % int(t["dead"]), "killed", Kit.FONT_SMALL, Kit.COL_GOLD))
		row.add_child(Kit.icon_label("%d fled" % int(t["fled"]), "routed", Kit.FONT_SMALL, Kit.COL_GOLD))
		row.add_child(Kit.icon_label("%d kills" % int(tots[1 - sd]["dead"]), "battles", Kit.FONT_SMALL, Kit.COL_GOLD))
		(sides.get_child(sd) as Container).add_child(row)
		var tl := Kit.label(txt, Kit.FONT_SMALL, Kit.COL_GOLD, true)
		tl.name = "totals_%d" % sd
		tl.visible = false
		(sides.get_child(sd) as Container).add_child(tl)
	var per_unit := false
	for e2 in outcome.get("units", []):
		if (e2 as Dictionary).has("kills"):
			per_unit = true
	var note := Kit.label((KILLS_NOTE_UNITS if per_unit else KILLS_NOTE) + " Of the men who fled, %d%% return to their units." % CData.ROUT_RETURN,
		Kit.FONT_SMALL, Kit.COL_DIM, true)
	note.name = "kills_note"
	v.add_child(note)
	if not events.is_empty():
		v.add_child(Kit.section("Reports"))
		for t2 in events:
			v.add_child(Kit.label(str(t2), Kit.FONT_SMALL, Color.WHITE, true))
	return v


## One line: what the battle decided (city taken / held, armies destroyed,
## withdrew, the siege continues or is broken, who holds the field).
static func outcome_line(snap: Dictionary, outcome: Dictionary, st: Dictionary) -> String:
	var r := int(snap["r"])
	var city := str(CData.REGIONS[r]["city"])
	var kind := str(snap["kind"])
	var winner := 1 if int(outcome.get("winner", 1)) != 0 else 0
	var draw := int(outcome.get("draw", 0)) != 0
	var loser := 1 - winner
	if kind in ["sally", "relief"] and draw:
		loser = 1  # a drawn sortie leaves the besiegers where they are
	var t := ""
	if int(outcome.get("forfeit", 0)) != 0:
		t = "You left the field: the army withdrew and the battle counts as lost."
	elif kind in ["sally", "relief"]:
		t = "The siege of %s continues." % city if loser == 1 else "The siege of %s is broken; the besiegers fall back." % city
	elif kind == "field":
		t = "%s hold the field; %s fall back." % [_names(snap["facs"][1 - loser]), _names(snap["facs"][loser])]
	elif loser == 1:
		var owner := CState.owner(st, r)
		if owner >= 0 and (snap["facs"][0] as Array).has(owner):
			t = "%s is taken by %s." % [city, CData.faction_name(owner)]
		else:
			t = "The defenders of %s are beaten, but no attacking army is left to take it." % city
	else:
		t = "%s is held; the attackers fall back." % city
	if draw:
		t = "Neither side broke. " + t
	# Armies of either side that no longer exist.
	for sd in 2:
		var gone: Array[String] = []
		for g in snap["sides"][sd]:
			if int(g["army"]) < 0:
				continue
			if CState.army(st, int(g["army"])).is_empty():
				gone.append(str(g["name"]))
		if not gone.is_empty():
			t += " " + ("The %s is destroyed." % gone[0] if gone.size() == 1 else "%d armies are destroyed (%s)." % [gone.size(), ", ".join(gone)])
	return t


# ----------------------------------------------------------------- views ---

## A unit card: symbol (tier mark) in the faction colour, men, tier, short
## name, and a health bar of men against full strength. As a result card
## (back >= 0): survivors in colour, the lost part red, and "-lost".
class UnitCard extends Control:
	const W := 96.0
	const H := 60.0
	var ty := 0
	var men := 0
	var full := 1
	var back := -1
	var dead := 0
	var kills := -1  # enemies its men killed (a fought battle), -1 not known
	var ak := -1  # its special ammunition kind (UT.AMMO row), -1 none
	var fielded := true
	var col := Color.WHITE

	func _init(p_ty: int, p_men: int, p_full: int, p_col: Color) -> void:
		ty = p_ty
		men = p_men
		full = maxi(p_full, 1)
		col = p_col
		custom_minimum_size = Vector2(W, H)
		mouse_filter = Control.MOUSE_FILTER_PASS

	## A fought battle's card: the enemies its men killed, on a row of its
	## own above the name (the card grows by it).
	func set_kills(k: int) -> void:
		kills = k
		custom_minimum_size = Vector2(W, H + (12.0 if k >= 0 else 0.0))

	func describe() -> String:
		var t := "%s (tier %d): %d of %d men" % [UT.TYPES[ty]["name"], UT.tier_of(ty), men, full]
		if not fielded:
			return t + ", not fielded (the side is full)"
		if back >= 0:
			t += "; %d back, %d lost (%d dead)" % [back, men - back, dead]
		if kills >= 0:
			t += "; %d kills" % kills
		if ak >= 0:
			t += "; carries %s" % UT.ammo_text(ak, "name").to_lower()
		if UT.stat(ty, "cmd_r") > 0:
			t += "; the army's general"
		return t

	func _draw() -> void:
		var sz := size
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, 0.07) if fielded else Color(1, 1, 1, 0.03))
		var r := 11.0
		var disc := col if fielded else Color(0.45, 0.45, 0.45)
		Icons.draw_marker(self, Icons.icon_of(ty), Vector2(r + 4, r + 4), r, disc)
		if UT.stat(ty, "cmd_r") > 0:
			# The general: his standard in gold in the top right corner.
			Kit.UiIcons.draw_icon(self, "general", Rect2(sz.x - 16, 3, 13, 13), Kit.COL_GOLD if fielded else Kit.COL_DIM)
		var x0 := r * 2 + 9
		var txt := Color.WHITE if fielded else Color(0.6, 0.6, 0.6)
		var big := str(back) if back >= 0 else str(men)
		draw_string(font, Vector2(x0, 17), big, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, txt)
		var bw := font.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		if back >= 0:
			draw_string(font, Vector2(x0 + bw + 2, 17), "/%d" % men, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Kit.COL_DIM)
			if men - back > 0:
				var lt := "-%d" % (men - back)
				var lw := font.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
				draw_string(font, Vector2(sz.x - lw - 3, 32), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.5, 0.42))
		else:
			var tier := UT.tier_of(ty)
			if tier > 1:
				var tt := "T%d" % tier
				var tw := font.get_string_size(tt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				draw_string(font, Vector2(sz.x - tw - 3, 13), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Kit.COL_GOLD)
		if ak >= 0:
			# Its special ammunition kind (fire, heavy, pots, blast).
			draw_string(font, Vector2(x0, 31), "+" + UT.ammo_text(ak, "short"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				Color(1.0, 0.62, 0.3))
		var nm := str(UT.TYPES[ty].get("short", UT.TYPES[ty]["name"]))
		if not fielded:
			nm = "(reserve)"
		draw_string(font, Vector2(4, sz.y - 15), nm, HORIZONTAL_ALIGNMENT_LEFT, sz.x - 8, 11, txt)
		if kills >= 0 and back >= 0:
			draw_string(font, Vector2(4, sz.y - 28), "kills %d" % kills, HORIZONTAL_ALIGNMENT_LEFT, sz.x - 8, 11, Kit.COL_GOLD)
		# Health bar: men (or survivors) against full strength.
		var bx := 4.0
		var by := sz.y - 10
		var bwid := sz.x - 8
		draw_rect(Rect2(bx, by, bwid, 7), Color(1, 1, 1, 0.12))
		var now := back if back >= 0 else men
		var f0 := clampf(float(now) / full, 0.0, 1.0)
		draw_rect(Rect2(bx, by, bwid * f0, 7), COL_HEALTH if fielded else Color(0.5, 0.5, 0.5))
		if back >= 0 and men > back:
			var f1 := clampf(float(men) / full, 0.0, 1.0)
			draw_rect(Rect2(bx + bwid * f0, by, bwid * (f1 - f0), 7), COL_LOST)
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1, 1, 1, 0.12), false, 1.0)


## A field battle's ground at a glance: the region's ground colour, its
## relief and woods (view-only scatter), the attackers' band at the bottom
## and the defenders' at the top.
class FieldPreview extends Control:
	var r := 0
	var cols: Array = []

	func _init(p_r: int, p_cols: Array, p_size: Vector2) -> void:
		r = p_r
		cols = p_cols
		custom_minimum_size = p_size
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var rd: Dictionary = CData.REGIONS[r]
		var pal := GroundPalette.get_palette(int(rd["ground"]))
		var sz := size
		draw_rect(Rect2(Vector2.ZERO, sz), pal["base"])
		var rng := RandomNumberGenerator.new()
		rng.seed = 7919 * (r + 1)
		var kind := int(rd["terrain"])
		if kind != 0:
			for i in 4:
				var c := Vector2(rng.randf_range(0.15, 0.85) * sz.x, rng.randf_range(0.3, 0.7) * sz.y)
				var rad := rng.randf_range(0.12, 0.25) * sz.x
				for k in 3:
					draw_circle(c, rad * (1.0 - k * 0.3), Color(pal["high"], 0.35))
		var trees: Array = pal["trees"]
		for i in int(rd["forest"]) * 3:
			var p := Vector2(rng.randf() * sz.x, rng.randf_range(0.12, 0.88) * sz.y)
			draw_circle(p, rng.randf_range(2.0, 4.5), trees[i % trees.size()])
		var band := 14.0
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(0, 0, sz.x, band), Color(cols[1], 0.85))
		draw_rect(Rect2(0, sz.y - band, sz.x, band), Color(cols[0], 0.85))
		draw_string(font, Vector2(6, band - 3), "Defenders", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		draw_string(font, Vector2(6, sz.y - 3), "Attackers", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		for k in 3:
			var x := sz.x * (0.3 + 0.2 * k)
			var y0 := sz.y - band - 4
			var y1 := sz.y * 0.55
			draw_line(Vector2(x, y0), Vector2(x, y1 + 8), Color(1.0, 0.85, 0.35, 0.9), 2.5)
			draw_colored_polygon(PackedVector2Array([Vector2(x, y1), Vector2(x - 6, y1 + 10), Vector2(x + 6, y1 + 10)]),
				Color(1.0, 0.85, 0.35, 0.9))
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.6), false, 1.0)
