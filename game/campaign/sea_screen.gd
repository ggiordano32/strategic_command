extends RefCounted
## The battle screen of a sea battle (N3a; game/campaign/battle_screen.gd
## hands a battle with "sea" here). Pre-battle: the title ("Sea battle off
## Havana"), a preview of the water (open sea, an island, the coast on the
## sides the campaign cell has land) with the wind and both fleets' start,
## each side's ships (hull, crew, guns, troops aboard, a treasure galleon's
## name and silver, a pirate captain), the balance of power (the fleet
## formula) and Auto-resolve (the formula) / Fight (real time, the sea
## battle screen game/sea_battle.gd). Result: VICTORY / DEFEAT, fought or
## auto-resolved, each ship's fate (afloat with her hull and crew, sunk,
## taken, escaped; prizes), the reports. View only.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CCaptain := preload("res://campaign/ccaptain.gd")
const CSeaBattle := preload("res://campaign/cseabattle.gd")
const SeaSim := preload("res://sim/sea_sim.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")

const FATE_NAMES := ["afloat", "sunk", "taken", "escaped"]


static func _place(_st: Dictionary, b: Dictionary) -> String:
	return str(CData.REGIONS[int(b["r"])]["city"])


static func _names(list: Array) -> String:
	var out: Array[String] = []
	for f in list:
		out.append(CData.faction_name(int(f)))
	return " and ".join(out)


static func title(st: Dictionary, b: Dictionary) -> String:
	var facs := CRules.battle_factions(st, b)
	return "Sea battle off %s: %s (attacking) against %s" % [_place(st, b), _names(facs[0]), _names(facs[1])]


static func snapshot(st: Dictionary, b: Dictionary, viewer: int) -> Dictionary:
	var facs := CRules.battle_factions(st, b)
	var sides := [[], []]
	var sdz := CSeaBattle.sides(st, b)
	for k in 2:
		for fl in sdz[k]:
			var ships: Array = []
			for i in (fl["ships"] as Array).size():
				var sh: Dictionary = fl["ships"][i]
				ships.append({"k": i, "t": str(sh["t"]), "h": int(sh["h"]), "c": int(sh["c"]), "nm": str(sh.get("nm", "")),
					"g": int(sh.get("g", 0))})
			var cp := CCaptain.of_fleet(st, int(fl["id"]))
			sides[k].append({"fleet": int(fl["id"]), "f": int(fl["f"]), "ships": ships, "men": CSeaBattle._carried_men(fl),
				"capt": str(cp.get("nm", "")), "fame": int(cp.get("fame", 0))})
	var me := -1
	for k in 2:
		if me < 0 and (facs[k] as Array).has(viewer):
			me = k
	if me < 0 and viewer >= 0:
		for k in 2:
			for f in facs[k]:
				if me < 0 and CState.friendly(st, int(f), viewer):
					me = k
	return {"sea": 1, "bid": int(b["id"]), "r": int(b["r"]), "x": int(b["x"]), "y": int(b["y"]), "facs": facs,
		"lead": [int(b["att_f"]), int(b["def_f"])], "sides": sides, "me": me, "title": title(st, b), "kind": "sea",
		"settlement": 0}


static func _dialog_w(s) -> float:
	return minf(900.0, s._vp().x - 24) - 48


## The pre-battle card (the online dialog swaps "battle_buttons" and fills
## "battle_status" as for a land battle).
static func pre(s, st: Dictionary, b: Dictionary) -> Control:
	var snap := snapshot(st, b, int(s.f))
	var w := _dialog_w(s)
	var wide := w >= 640.0
	var p := Kit.panel(Color(1, 1, 1, 0.06), 8)
	p.name = "battle_screen"
	var v := Kit.vbox(8)
	p.add_child(v)
	v.add_child(Kit.label(str(snap["title"]), Kit.FONT, Kit.COL_GOLD, true))
	var top: BoxContainer = Kit.vbox(8)
	if wide:
		top = Kit.hbox(10)
	v.add_child(top)
	var built := CSeaBattle.build(st, b, -1)
	var scn: Dictionary = built["scenario"]
	var pw := minf(w * (0.42 if wide else 1.0), 340.0)
	var ph := minf(pw * 0.62, 110.0 if s._vp().y < 600 else 190.0)
	var prev := SeaPreview.new(scn, int(built["seed"]), [CData.faction_color(int(snap["lead"][0])),
		CData.faction_color(int(snap["lead"][1]))], Vector2(pw, ph))
	prev.name = "battle_preview"
	prev.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(prev)
	var info := Kit.vbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	var land: Dictionary = scn["land"]
	var water := "Open sea"
	if int(land.get("kind", 0)) == 1:
		water = "Open sea with an island"
	elif int(land.get("kind", 0)) == 2:
		water = "Close to the coast (shoals: deep-draught ships run aground, shallow hulls and canoes pass)"
	var wb := int(scn["wind_deg"])
	var compass: String = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"][int(round(wb / 45.0)) % 8]
	var force := "a light" if int(scn["wind_str"]) < 40 else "a moderate" if int(scn["wind_str"]) < 65 else "a fresh" if int(scn["wind_str"]) < 85 else "a strong"
	info.add_child(Kit.label("%s. The wind: %s breeze from the %s. Fought in real time: keep sea room, use the wind (sail) or the stroke (oars), shoot, ram, board." % [
		water, force, compass], Kit.FONT_SMALL, Kit.COL_DIM, true))
	var facs: Array = snap["facs"]
	var hs := CRules.battle_humans(st, b)
	var human_att: bool = not hs.is_empty() and (facs[0] as Array).has(hs[0])
	var lead: Array = snap["lead"]
	info.add_child(Kit.odds_view(CBattle.battle_odds(st, b), 0 if human_att else 1, [_names([lead[0]]), _names([lead[1]])],
		[CData.faction_color(int(lead[0])), CData.faction_color(int(lead[1]))], "Balance of power (the fleets' guns, hulls and crews):"))
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
	v.add_child(_sides_view(snap, {}, wide))
	return p


static func _sides_view(snap: Dictionary, fates: Dictionary, wide: bool) -> Control:
	var box: BoxContainer = Kit.vbox(8)
	if wide:
		box = Kit.hbox(12)
	box.name = "battle_sides"
	for k in 2:
		var col := Kit.vbox(4)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(Kit.section("Attackers" if k == 0 else "Defenders"))
		for g in snap["sides"][k]:
			var f := int(g["f"])
			var head := "%s fleet" % str(CData.FACTIONS[f]["adj"])
			if str(g["capt"]) != "":
				head += " under %s (fame %d)" % [str(g["capt"]), int(g["fame"])]
			if int(g["men"]) > 0:
				head += ", %d men aboard" % int(g["men"])
			var hl := Kit.label(head, Kit.FONT_SMALL, CData.faction_color(f).lightened(0.35), true)
			col.add_child(hl)
			for sh in g["ships"]:
				var row := CData.ship_row(str(sh["t"]))
				var nm := str(row.get("name", sh["t"]))
				if str(sh["nm"]) != "":
					nm = "%s (%s)" % [str(sh["nm"]), nm.to_lower()]
				var line := "%s: %s, hull %d%%, crew %d%%" % [nm, CFleet.arms_text(row), int(sh["h"]), int(sh["c"])]
				if int(sh["g"]) > 0:
					line += ", %d in silver" % int(sh["g"])
				var key := "%d:%d" % [int(g["fleet"]), int(sh["k"])]
				var lc := Color.WHITE
				if fates.has(key):
					var fr: Array = fates[key]
					var fate := int(fr[2])
					line = "%s: %s" % [nm, FATE_NAMES[fate]]
					if fate == 0 or fate == 3:
						line += ", hull %d%%, crew %d%%" % [int(fr[3]), int(fr[4])]
					if int(fr[5]) != 0:
						line += " (her magazine blew up)"
					lc = Kit.COL_BAD if fate == 1 or fate == 2 else Color.WHITE
				col.add_child(Kit.label(line, Kit.FONT_SMALL, lc, true))
		box.add_child(col)
	return box


## The result: VICTORY / DEFEAT for the viewer, how it was decided, each
## ship's fate (a fought battle's outcome; an auto-resolved one: the losses
## in the reports), then the reports.
static func result(s, snap: Dictionary, outcome: Dictionary, st: Dictionary, events: Array) -> Control:
	var w := _dialog_w(s)
	var wide := w >= 640.0
	var v := Kit.vbox(8)
	v.name = "battle_result"
	var me := int(snap["me"])
	var winner := int(outcome.get("winner", -1))
	if winner < 0:
		# Auto-resolved: the formula decided when it was applied.
		for e in st["events"]:
			if str(e["k"]) == "sea_battle" and int(e["x"]) == int(snap["x"]) and int(e["y"]) == int(snap["y"]):
				winner = int(e["won"])
	winner = maxi(winner, 0)
	var word := "VICTORY" if winner == me else "DEFEAT"
	var wcol := Kit.COL_GOOD if winner == me else Kit.COL_BAD
	if me < 0:
		word = "ATTACKERS WIN" if winner == 0 else "DEFENDERS WIN"
		wcol = Color.WHITE
	var banner := Kit.label(word, 40, wcol)
	banner.name = "result_banner"
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_constant_override("outline_size", 6)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	v.add_child(banner)
	var mode := "Fought" if str(outcome.get("mode", "")) in ["fought", "forfeit"] else "Auto-resolved"
	if str(outcome.get("mode", "")) == "forfeit":
		mode = "Fought (you left the battle)"
	var ml := Kit.label("%s. %s" % [mode, str(snap["title"]).get_slice(":", 0)], Kit.FONT_SMALL, Kit.COL_DIM, true)
	ml.name = "result_mode"
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ml)
	var fates := {}
	var n := [0, 0, 0, 0]
	for r in outcome.get("ships", []):
		fates["%d:%d" % [int(r[0]), int(r[1])]] = r
		n[int(r[2])] += 1
	if not fates.is_empty():
		var ol := Kit.label("%s held the sea: %d ship%s sunk, %d taken, %d escaped." % [_names(snap["facs"][winner]), n[1],
			"" if n[1] == 1 else "s", n[2], n[3]], Kit.FONT, Color.WHITE, true)
		ol.name = "result_outcome"
		ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(ol)
	v.add_child(_sides_view(snap, fates, wide))
	if not events.is_empty():
		v.add_child(Kit.section("Reports"))
		for t in events:
			v.add_child(Kit.label(str(t), Kit.FONT_SMALL, Color.WHITE, true))
	return v


## The water of the battle, its wind and where the fleets start.
class SeaPreview extends Control:
	var sim: SeaSim
	var cols: Array = []

	func _init(scn: Dictionary, sd: int, p_cols: Array, p_size: Vector2) -> void:
		sim = SeaSim.new()
		sim.setup(scn, sd)
		cols = p_cols
		custom_minimum_size = p_size
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _draw() -> void:
		var sz := size
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.13, 0.36, 0.5))
		var k := minf(sz.x / sim.field_w, sz.y / sim.field_h)
		var off := (sz - Vector2(sim.field_w, sim.field_h) * k) * 0.5
		var cs := float(SeaSim.CELL_M) * k
		for gy in sim.g_h:
			for gx in sim.g_w:
				var v := sim.g[gy * sim.g_w + gx]
				if v == 0:
					continue
				var c := Color(0.55, 0.82, 0.78, 0.6) if v == 1 else Color(0.62, 0.66, 0.42)
				draw_rect(Rect2(off + Vector2(gx, gy) * cs, Vector2(cs + 0.6, cs + 0.6)), c)
		for s in sim.n_units:
			var p := off + Vector2(sim.s_x[s], sim.s_y[s]) / 1024.0 * k
			var a := sim.heading(s) * TAU / 1024.0
			var f := Vector2(cos(a), sin(a))
			var l := maxf(sim.ST.stat(sim.s_type[s], "len") * k * 2.5, 5.0)
			draw_line(p - f * l * 0.5, p + f * l * 0.5, cols[sim.u_side[s]], 3.5)
			draw_circle(p + f * l * 0.5, 2.0, Color.WHITE)
		# The wind.
		var wa := (sim.w_from + 512) * TAU / 1024.0
		var wt := Vector2(cos(wa), sin(wa))
		var c0 := Vector2(sz.x - 26, 22)
		draw_circle(c0, 17, Color(0, 0, 0, 0.4))
		draw_line(c0 - wt * 12, c0 + wt * 12, Color(0.6, 0.85, 1.0), 2.5)
		var sd := Vector2(-wt.y, wt.x)
		draw_colored_polygon(PackedVector2Array([c0 + wt * 14, c0 + wt * 6 + sd * 5, c0 + wt * 6 - sd * 5]), Color(0.6, 0.85, 1.0))
		draw_string(ThemeDB.fallback_font, c0 + Vector2(-20, 30), "wind", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
