extends RefCounted
## Panels and dialogs of the campaign screen (built on demand from the
## preview state; every action goes back through the screen's order list):
## region, army, realm (faction overview), diplomacy, pending battles, battle
## result, turn summary, objectives, end-turn warnings, menu.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const UT := preload("res://sim/unit_types.gd")
const Terrain := preload("res://sim/terrain.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const Saves := preload("res://game/campaign/saves.gd")
const CityPreview := preload("res://game/campaign/city_preview.gd")
const MapGen := preload("res://sim/mapgen.gd")

var s  # the campaign screen
var _split_sel: Dictionary = {}  # army id -> Array of selected unit indices


func _init(screen) -> void:
	s = screen


func _fc(f: int) -> Color:
	return CData.faction_color(f)


func _close_row(box: Container, title: String, col: Color) -> void:
	var h := Kit.hbox(6)
	var t := Kit.label(title, Kit.FONT_TITLE, col)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(t)
	var b := Kit.button("Close", func(): s.close_side(), 70)
	b.name = "side_close"
	h.add_child(b)
	box.add_child(h)


# --------------------------------------------------------------- region ---

func region_panel(box: VBoxContainer, r: int) -> void:
	var ps: Dictionary = s.ps
	var f: int = s.f
	var rd: Dictionary = CData.REGIONS[r]
	var rs: Dictionary = ps["regions"][r]
	var o := int(rs["owner"])
	var mine := o == f
	_close_row(box, "%s (%s)" % [rd["city"], rd["name"]], _fc(o).lightened(0.4))
	var lvl := int(rs["level"])
	var info := "%s of %s. %s, %s ground." % [CData.LEVEL_NAMES[lvl], CData.faction_name(o),
		"Key city" if CData.KEY_CITIES.has(str(rd["key"])) else ("Capital" if CData.is_capital(r) else "Wealth %d" % int(rd["wealth"])),
		Terrain.KIND_NAMES[int(rd["terrain"])].to_lower()]
	box.add_child(Kit.label(info, Kit.FONT_SMALL, Kit.COL_DIM, true))
	if o != f and f >= 0:
		var rel := ""
		var col := Color.WHITE
		if o < 0:
			rel = "Independent: can always be attacked."
			col = Kit.COL_BAD
		else:
			match CState.dip(ps, f, o):
				CState.WAR:
					rel = "%s is at war with you." % CData.faction_name(o)
					col = Kit.COL_BAD
				CState.PEACE:
					rel = "%s is at peace with you: declare war in Diplomacy to attack." % CData.faction_name(o)
				CState.TRADE:
					rel = "%s is at peace and trading with you." % CData.faction_name(o)
				CState.ALLIED:
					rel = "%s is your ally." % CData.faction_name(o)
					col = Kit.COL_GOOD
		box.add_child(Kit.label(rel, Kit.FONT_SMALL, col, true))
	if not CState.siege_at(ps, r).is_empty():
		_siege_section(box, r)
	elif f >= 0 and CState.at_war(ps, f, o) and CState.battle_at(ps, r).is_empty():
		_attack_section(box, r)
	var gp := CRules.growth_per_turn(ps, r)
	var grow := "Growth %d/%d to %s (+%d a turn)" % [int(rs["growth"]), int(CData.GROWTH_TO[lvl + 1]), CData.LEVEL_NAMES[lvl + 1].to_lower(), gp] if lvl < CData.CITY else "Full-grown city"
	box.add_child(Kit.label("Income %d a turn.  %s." % [CRules.region_income(ps, r), grow], Kit.FONT_SMALL, Color.WHITE, true))
	var b := CState.battle_at(ps, r)
	if not b.is_empty():
		box.add_child(Kit.label("A battle is pending here.", Kit.FONT, Kit.COL_BAD))
	box.add_child(Kit.label(CBattle.city_caption(ps, r) + ".", Kit.FONT_SMALL, Kit.COL_DIM, true))
	var vb := Kit.button("View battle map", show_city_map.bind(r))
	vb.name = "view_battle_map"
	box.add_child(vb)
	# Armies here.
	var here := CState.armies_in(ps, r)
	if not here.is_empty():
		box.add_child(Kit.section("Armies"))
		for a in here:
			var bt := Kit.button("%s army: %d units, %d men" % [CData.FACTIONS[int(a["f"])]["adj"], CState.unit_count(a), CState.men(a)],
				s.select_army.bind(int(a["id"])))
			bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
			bt.add_theme_color_override("font_color", _fc(int(a["f"])).lightened(0.5))
			box.add_child(bt)
	if mine:
		_recruit(box, r)
		_buildings(box, r)
	# Garrison.
	var gar := CRules.garrison(ps, r)
	box.add_child(Kit.section("Garrison (%d%% strength, walls %d)" % [int(rs["gar"]), CState.walls(ps, r)]))
	for g in gar:
		var row := Kit.UnitRow.new(UT.index_of(str(g["t"])), int(g["n"]), _fc(o))
		row.full = int(g["full"])
		box.add_child(row)


# ---------------------------------------------------------------- sieges ---

func _fname(f: int) -> String:
	return CData.faction_name(f)


func _has_order(t: String, r: int) -> bool:
	for o in s.orders:
		if str(o["t"]) == t and int(o.get("r", -1)) == r:
			return true
	return false


## Armies the player planning now has ordered into region r (in the preview
## state, still where they stand).
func planned_into(r: int) -> Array:
	var out: Array = []
	for m in s.moves:
		if int(m[1]) == r:
			var a := CState.army(s.ps, int(m[0]))
			if not a.is_empty():
				out.append(a)
	return out


## The odds of what the player plans against region r: a relief of our
## besieged city (field battle: the relief and the armies inside with the
## garrison against the besiegers), else storming it with the armies ordered
## in and those already besieging it (garrison and armies there defending).
## {od, me, names, cols, kind ("relief" | "assault"), n (armies)}.
func plan_odds(r: int) -> Dictionary:
	var ps: Dictionary = s.ps
	var f: int = s.f
	var o := CState.owner(ps, r)
	var att := planned_into(r)
	var sg := CState.siege_at(ps, r)
	if not sg.is_empty() and CState.friendly(ps, f, o):
		var od := CBattle.odds(ps, att + CRules.besieged_armies(ps, r), CRules.besiegers(ps, r), r, false, 0)
		return {"od": od, "me": 0, "names": [_fname(f), _fname(int(sg["f"]))], "cols": [_fc(f), _fc(int(sg["f"]))],
			"kind": "relief", "n": att.size()}
	for a in CRules.besiegers(ps, r):
		if not att.has(a):
			att.append(a)
	var defs: Array = []
	if o >= 0:
		for a in CState.armies_in(ps, r):
			if CState.friendly(ps, int(a["f"]), o):
				defs.append(a)
	var od2 := CBattle.odds(ps, att, defs, r, true)
	return {"od": od2, "me": 0, "names": [_fname(f), _fname(o)], "cols": [_fc(f), _fc(o)], "kind": "assault", "n": att.size()}


## Region panel of a besieged settlement: who, how long, supplies; for a
## besieger the assault odds with Assault / Maintain, for the defender the
## sally odds with Sally.
func _siege_section(box: VBoxContainer, r: int) -> void:
	var ps: Dictionary = s.ps
	var f: int = s.f
	var sg := CState.siege_at(ps, r)
	var o := CState.owner(ps, r)
	var p := Kit.panel(Color(0.35, 0.18, 0.08, 0.5), 8)
	p.name = "siege_panel"
	var v := Kit.vbox(6)
	p.add_child(v)
	box.add_child(p)
	var turn_n := int(ps["turn"]) - int(sg["turn"])
	var sup := int(sg["supply"])
	var sup_t := ("supplies %d turn%s left" % [sup, "" if sup == 1 else "s"]) if sup > 0 \
		else "out of supplies: the garrison loses %d%% a turn" % CData.SIEGE_STARVE_PCT
	var bs := CRules.besiegers(ps, r)
	var men := 0
	for a in bs:
		men += CState.men(a)
	v.add_child(Kit.label("Besieged by %s, turn %d of the siege, %s." % [_fname(int(sg["f"])), turn_n, sup_t],
		Kit.FONT, Kit.COL_GOLD, true))
	var note := Kit.label("%d besieging arm%s, %d men. No income, recruits or building while besieged; with no garrison and no army inside it surrenders." % [
		bs.size(), "y" if bs.size() == 1 else "ies", men], Kit.FONT_SMALL, Kit.COL_DIM, true)
	if f < 0:
		v.add_child(note)
		return
	var mine := false
	for a in bs:
		if int(a["f"]) == f:
			mine = true
	if mine:
		var po := plan_odds(r)
		v.add_child(Kit.odds_view(po["od"], 0, po["names"], po["cols"], "If you storm it this turn (all besiegers%s):" % (
			" and the armies marching in" if planned_into(r).size() > 0 else "")))
		var ordered := _has_order("assault", r)
		v.add_child(Kit.label("Orders: storm the walls at the end of the turn." if ordered else "Orders: keep up the siege.",
			Kit.FONT, Kit.COL_BAD if ordered else Color.WHITE, true))
		var h := Kit.hbox(8)
		var ab := Kit.button("Assault", func(): s.add_order({"t": "assault", "r": r}), 110)
		ab.name = "siege_assault"
		ab.disabled = ordered or CRules.can_assault(ps, f, r) != ""
		h.add_child(ab)
		var mb := Kit.button("Maintain", func(): s.remove_orders(func(x): return str(x["t"]) == "assault" and int(x.get("r", -1)) == r), 110)
		mb.name = "siege_maintain"
		mb.disabled = not ordered
		h.add_child(mb)
		v.add_child(h)
		v.add_child(note)
	elif CState.friendly(ps, f, o):
		var inside := CRules.besieged_armies(ps, r)
		var od := CBattle.odds(ps, inside, bs, r, false, 0)
		v.add_child(Kit.odds_view(od, 0, [_fname(f), _fname(int(sg["f"]))], [_fc(f), _fc(int(sg["f"]))],
			"If the garrison and the armies inside sally (a field battle outside the walls):" if not inside.is_empty()
			else "If the garrison sallies (a field battle outside the walls):"))
		var ordered2 := _has_order("sally", r)
		var h2 := Kit.hbox(8)
		var sb := Kit.button("Cancel sally" if ordered2 else "Sally", func():
			if ordered2:
				s.remove_orders(func(x): return str(x["t"]) == "sally" and int(x.get("r", -1)) == r)
			else:
				s.add_order({"t": "sally", "r": r}), 130)
		sb.name = "siege_sally"
		sb.disabled = not ordered2 and CRules.can_sally(ps, f, r) != ""
		h2.add_child(sb)
		h2.add_child(Kit.label("Orders: sally at the end of the turn." if ordered2 else "Win to lift the siege; lose and the siege goes on.",
			Kit.FONT_SMALL, Kit.COL_BAD if ordered2 else Kit.COL_DIM, true))
		v.add_child(h2)
		if planned_into(r).size() > 0:
			var po2 := plan_odds(r)
			v.add_child(Kit.odds_view(po2["od"], 0, po2["names"], po2["cols"], "Your relief (with the garrison and the armies inside riding out):"))
		else:
			v.add_child(Kit.label("An army of yours marching in relieves it: a field battle, the garrison and the armies inside fight on its side.",
				Kit.FONT_SMALL, Kit.COL_DIM, true))
		v.add_child(note)
	else:
		v.add_child(note)


## Region panel of an enemy settlement: the odds of the armies ordered into
## it this turn.
func _attack_section(box: VBoxContainer, r: int) -> void:
	var ps: Dictionary = s.ps
	var into := planned_into(r)
	if into.is_empty():
		return
	var po := plan_odds(r)
	var assault := 0
	for m in s.moves:
		if int(m[1]) == r and int(m[2]) == CData.MODE_ASSAULT:
			assault += 1
	var what := "Planned: %d arm%s %s." % [into.size(), "y" if into.size() == 1 else "ies",
		"storm it at once" if assault > 0 or not CState.sieges_on(ps) else "lay siege (no battle this turn)"]
	var p := Kit.panel(Color(0.3, 0.1, 0.08, 0.45), 8)
	p.name = "attack_panel"
	var v := Kit.vbox(6)
	p.add_child(v)
	v.add_child(Kit.label(what, Kit.FONT, Kit.COL_GOLD, true))
	v.add_child(Kit.odds_view(po["od"], 0, po["names"], po["cols"], "Odds of storming it (garrison and walls included):"))
	if CState.sieges_on(ps) and assault == 0:
		v.add_child(Kit.label("A siege starves it: supplies %d turns, then the garrison weakens each turn." % CState.siege_supply(ps, r),
			Kit.FONT_SMALL, Kit.COL_DIM, true))
	box.add_child(p)


## The settlement's battle map as it stands now (CityPreview), with what
## shapes it: level, walls, gates, the main gate facing the approach.
func show_city_map(r: int) -> void:
	var ps: Dictionary = s.ps
	var rd: Dictionary = CData.REGIONS[r]
	var rs: Dictionary = ps["regions"][r]
	var lvl := int(rs["level"])
	var w := CState.walls(ps, r)
	var vp: Vector2 = s._vp()
	# Short landscape screens (phones): picture left, text right.
	var side := vp.y < 600.0
	var pw := minf(560.0, vp.x - 72.0)
	if side:
		pw = minf(vp.x * 0.42, 420.0)
	var prev := CityPreview.for_region(ps, r, pw)
	var maxh := clampf(vp.y * (0.62 if side else 0.5), 190.0, 400.0)
	if prev.custom_minimum_size.y > maxh:
		prev.custom_minimum_size = prev.custom_minimum_size * (maxh / prev.custom_minimum_size.y)
	var box: BoxContainer = Kit.vbox(8)
	if side:
		box = Kit.hbox(12)
	var cc := CenterContainer.new()
	cc.add_child(prev)
	box.add_child(cc)
	var txt := Kit.vbox(8)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.custom_minimum_size = Vector2(280 if side else 0, 0)
	box.add_child(txt)
	var lay: Dictionary = prev.data["lay"]
	var ng := 0
	var cit := false
	for gd in lay["gates"]:
		if int((gd as Dictionary).get("cit", 0)) == 0:
			ng += 1
		else:
			cit = true
	txt.add_child(Kit.label(CBattle.city_caption(ps, r) + ".", Kit.FONT, Kit.COL_GOOD, true))
	var what := "%s, %s ground, %s%s." % [CData.LEVEL_NAMES[lvl], MapGen.PALETTE_NAMES[int(rd["ground"])].to_lower(),
		("walls level %d with %d gates and towers" % [w, ng]) if w > 0 else "no walls: an open town entered by its streets",
		" and a walled citadel (its plaza is the one to hold)" if cit else ""]
	txt.add_child(Kit.label(what, Kit.FONT, Color.WHITE, true))
	var how := "Attackers form up at the bottom (yellow arrow)" + (", before the main gate (red); its garrison's archers stand on the walls nearest the gates, a foot unit holds each gate and the rest the plaza. Break a gate with artillery or by hacking at it with infantry, then hold the plaza for a minute to take the city." if w > 0 else "; the defenders hold the street mouths and the plaza. Hold the plaza for a minute to take the town.")
	txt.add_child(Kit.label(how, Kit.FONT_SMALL, Kit.COL_DIM, true))
	txt.add_child(Kit.label("The map is fixed for this settlement: it changes only as it grows, builds or raises its walls.", Kit.FONT_SMALL, Kit.COL_DIM, true))
	if side:
		pw += 300.0
	s.show_dialog("Battle map: %s" % rd["city"], box, [["Close", Callable()]], pw + 48.0)


func _buildings(box: VBoxContainer, r: int) -> void:
	var ps: Dictionary = s.ps
	var f: int = s.f
	var rs: Dictionary = ps["regions"][r]
	box.add_child(Kit.section("Buildings (%d of %d slots)" % [(rs["slots"] as Array).size(), CState.slot_count(r, int(rs["level"]))]))
	var bld: Array = rs["build"]
	var planned := -1
	for o in s.orders:
		if str(o["t"]) == "build" and int(o["r"]) == r:
			planned = int(o["chain"])
	for c in CData.CHAINS.size():
		var ch: Dictionary = CData.CHAINS[c]
		var cur := CState.building(ps, r, c)
		var h := Kit.hbox(6)
		var name := "%s %d" % [ch["name"], cur] if cur > 0 else str(ch["name"])
		var l := Kit.label(name, Kit.FONT, Color.WHITE if cur > 0 else Kit.COL_DIM)
		l.custom_minimum_size.x = 104
		l.tooltip_text = str(ch["desc"])
		h.add_child(l)
		if not bld.is_empty() and int(bld[0]) == c:
			var t := Kit.label("-> %d: %d turn%s left" % [int(bld[1]), int(bld[2]), "" if int(bld[2]) == 1 else "s"], Kit.FONT_SMALL, Kit.COL_GOOD, true)
			h.add_child(t)
			if planned == c:
				var cb := Kit.button("Cancel", func(): s.remove_orders(func(o): return str(o["t"]) == "build" and int(o["r"]) == r), 70)
				h.add_child(cb)
		else:
			var info := CRules.build_info(ps, f, r, c)
			if info.has("why"):
				if cur == 0 and str(info["why"]) == "no free slot":
					continue
				var why := str(info["why"])
				if why == "fully built" and cur == 0:
					continue
				h.add_child(Kit.label(why, Kit.FONT_SMALL, Kit.COL_DIM, true))
			else:
				var t := Kit.label("%d (%d turn%s)" % [int(info["cost"]), int(info["turns"]), "" if int(info["turns"]) == 1 else "s"], Kit.FONT_SMALL, Kit.COL_GOLD, true)
				h.add_child(t)
				var bb := Kit.button("Build %d" % int(info["level"]) if cur == 0 else "Upgrade", func(): s.add_order({"t": "build", "r": r, "chain": c}), 84)
				bb.name = "build_%s" % ch["key"]
				bb.tooltip_text = str(ch["desc"])
				h.add_child(bb)
		box.add_child(h)


func _recruit(box: VBoxContainer, r: int) -> void:
	var ps: Dictionary = s.ps
	var f: int = s.f
	var rs: Dictionary = ps["regions"][r]
	var q: Array = rs["queue"]
	var cap := int(CData.RECRUITS_PER_TURN[int(rs["level"])])
	box.add_child(Kit.section("Recruit (%d of %d this turn; ready next turn)" % [q.size(), cap]))
	for k in q.size():
		var ty := UT.index_of(str(q[k]))
		var row := Kit.UnitRow.new(ty, -1, _fc(f), "planned")
		row.sub_text = "arrives next turn"
		var h := Kit.hbox(4)
		h.add_child(row)
		var key := str(q[k])
		h.add_child(Kit.button("X", func(): _cancel_recruit(r, key), 44))
		box.add_child(h)
	var shown := {}
	for o in CRules.recruit_options(ps, f, r):
		var line := str(o["line"])
		# Best available tier per line, plus locked higher tiers greyed.
		if shown.has(line) and not o["ok"]:
			continue
		if shown.has(line) and int(shown[line]) == 1:
			continue
		var ty := UT.index_of(str(o["t"]))
		var why := str(o["why"])
		if why.begins_with("needs") and int(o["tier"]) > 1:
			continue  # locked higher tiers: shown in the unit book
		shown[line] = 1 if o["ok"] else 0
		var row := Kit.UnitRow.new(ty, -1, _fc(f), str(o["price"]))
		row.sub_text = "Tier %d  -  upkeep %d" % [int(o["tier"]), CState.upkeep_of(ty)] if o["ok"] else why
		var key := str(o["t"])
		row.name = "recruit_row_" + key
		var open_page := func(): s.open_unit_page(ty,
			(func(): s.add_order({"t": "recruit", "r": r, "unit": key})) if o["ok"] else Callable(),
			"Recruit (%d)" % int(o["price"]))
		row.pressed.connect(open_page)
		row.long_pressed.connect(open_page)
		var h := Kit.hbox(4)
		h.add_child(row)
		var add := Kit.button("+", func(): s.add_order({"t": "recruit", "r": r, "unit": key}), 44)
		add.name = "recruit_" + key
		add.disabled = not o["ok"]
		h.add_child(add)
		box.add_child(h)


func _cancel_recruit(r: int, key: String) -> void:
	# Remove the last planned recruit of this type here.
	var idx := -1
	for i in s.orders.size():
		var o: Dictionary = s.orders[i]
		if str(o["t"]) == "recruit" and int(o["r"]) == r and str(o["unit"]) == key:
			idx = i
	if idx >= 0:
		var target: Dictionary = s.orders[idx]
		s.remove_orders(func(o): return is_same(o, target))


# ----------------------------------------------------------------- army ---

func army_panel(box: VBoxContainer, id: int) -> void:
	var ps: Dictionary = s.ps
	var a := CState.army(ps, id)
	if a.is_empty():
		return
	var af := int(a["f"])
	var mine: bool = af == s.f
	var r := int(a["r"])
	_close_row(box, "%s army at %s" % [CData.FACTIONS[af]["adj"], CData.REGIONS[r]["city"]], _fc(af).lightened(0.4))
	var up := 0
	for u in a["units"]:
		up += CState.upkeep_of(CState.unit_type(u))
	box.add_child(Kit.label("%d of %d units, %d men, upkeep %d" % [CState.unit_count(a), CData.ARMY_MAX, CState.men(a), up],
		Kit.FONT_SMALL, Kit.COL_DIM, true))
	if mine:
		var mv: int = s.planned_move(id)
		var role := CRules.siege_role(ps, a)
		if int(a["busy"]) != 0:
			box.add_child(Kit.label("In a battle.", Kit.FONT, Kit.COL_BAD))
		elif mv >= 0:
			var h := Kit.hbox(6)
			var kind: String = s.move_kind(id)
			var verb: String = {"siege": "Lays siege to", "join": "Joins the siege of", "assault": "Assaults", "relief": "Relieves",
				"move": "Moves to"}.get(kind, "Moves to")
			h.add_child(Kit.label("%s %s" % [verb, CData.REGIONS[mv]["name"]], Kit.FONT,
				Kit.COL_GOOD if kind == "move" else Kit.COL_BAD, true))
			if kind == "siege" or kind == "join" or (kind == "assault" and CState.sieges_on(ps)):
				var to_mode := CData.MODE_SIEGE if kind == "assault" else CData.MODE_ASSAULT
				var mb := Kit.button("Lay siege" if kind == "assault" else "Assault", func(): s.set_move_mode(id, to_mode), 96)
				mb.name = "move_mode"
				h.add_child(mb)
			var cb := Kit.button("Cancel move", func(): s.set_move(id, mv), 110)
			cb.name = "cancel_move"
			h.add_child(cb)
			box.add_child(h)
		elif role == 1:
			var sg := CState.siege_at(ps, r)
			var h2 := Kit.hbox(6)
			h2.add_child(Kit.label("Besieging %s (turn %d). It stays until ordered away." % [CData.REGIONS[r]["city"],
				int(ps["turn"]) - int(sg["turn"])], Kit.FONT, Kit.COL_GOLD, true))
			var sp := Kit.button("Siege", func(): s.select_region(r), 80)
			sp.name = "army_siege"
			h2.add_child(sp)
			box.add_child(h2)
		elif role == 2:
			var h3 := Kit.hbox(6)
			h3.add_child(Kit.label("Inside the besieged walls of %s: it can only leave by a sally." % CData.REGIONS[r]["city"],
				Kit.FONT, Kit.COL_BAD, true))
			var sp2 := Kit.button("Siege", func(): s.select_region(r), 80)
			sp2.name = "army_siege"
			h3.add_child(sp2)
			box.add_child(h3)
		else:
			box.add_child(Kit.label("Tap a highlighted region on the map to move.", Kit.FONT_SMALL, Color.WHITE, true))
	var sel: Array = _split_sel.get(id, [])
	var units: Array = a["units"]
	for k in units.size():
		var u: Dictionary = units[k]
		var ty := CState.unit_type(u)
		var row := Kit.UnitRow.new(ty, int(u["n"]), _fc(af), "", mine)
		row.selected = sel.has(k)
		row.name = "unit_%d" % k
		var kk := k
		row.long_pressed.connect(func(): s.open_unit_page(ty, Callable(), ""))
		row.pressed.connect(func():
			var cur: Array = _split_sel.get(id, [])
			if cur.has(kk):
				cur.erase(kk)
			else:
				cur.append(kk)
			_split_sel[id] = cur
			s.select_army(id))
		box.add_child(row)
	if not mine or int(a["busy"]) != 0 or CRules.siege_role(ps, a) != 0:
		return
	var fl := Kit.flow(6)
	var nsel := sel.size()
	var split := Kit.button("Split off %d" % nsel, func(): _split(id), 0)
	split.name = "split"
	split.disabled = nsel == 0 or nsel >= units.size()
	fl.add_child(split)
	var dis := Kit.button("Disband %d" % nsel, func(): _disband(id), 0)
	dis.disabled = nsel == 0
	fl.add_child(dis)
	fl.add_child(Kit.button("Book", func():
		var ty := CState.unit_type(units[sel[0]] if nsel > 0 else units[0])
		s.open_unit_page(ty, Callable(), ""), 0))
	for o in CState.armies_in(ps, r):
		if int(o["id"]) != id and int(o["f"]) == af and int(o["busy"]) == 0 and CRules.siege_role(ps, o) == 0:
			var oid := int(o["id"])
			var mb := Kit.button("Merge into army (%d units)" % CState.unit_count(o), func():
				_split_sel.erase(id)
				s.add_order({"t": "merge", "army": id, "into": oid})
				s.select_army(oid), 0)
			mb.disabled = CState.unit_count(o) + units.size() > CData.ARMY_MAX
			fl.add_child(mb)
	box.add_child(fl)
	box.add_child(Kit.label("Tap units to choose them for splitting or disbanding.", Kit.FONT_SMALL, Kit.COL_DIM, true))


func _split(id: int) -> void:
	var sel: Array = _split_sel.get(id, [])
	if sel.is_empty():
		return
	var nid := CRules.new_army_id(s.ps, s.f)
	_split_sel.erase(id)
	if s.add_order({"t": "split", "army": id, "units": sel.duplicate(), "new": nid}) == "":
		s.select_army(nid)


func _disband(id: int) -> void:
	var sel: Array = _split_sel.get(id, [])
	if sel.is_empty():
		return
	var box := Kit.label("Disband %d unit%s? Their men go home and their upkeep stops." % [sel.size(), "" if sel.size() == 1 else "s"], Kit.FONT, Color.WHITE, true)
	s.show_dialog("Disband", box, [["Disband", func():
		_split_sel.erase(id)
		s.close_dialog()
		s.add_order({"t": "disband", "army": id, "units": sel.duplicate()})
		s.select_army(id)], ["Back", Callable()]], 420)


# -------------------------------------------------------------- faction ---

func show_faction() -> void:
	var ps: Dictionary = s.ps
	var f: int = s.f if s.f >= 0 else int(ps["humans"][0])
	var box := Kit.vbox(6)
	var inc := CRules.income(ps, f)
	var up := CRules.upkeep(ps, f)
	box.add_child(Kit.label("Treasury %s after this turn's spending." % Kit.money(int(ps["factions"][f]["treasury"])), Kit.FONT, Color.WHITE, true))
	box.add_child(Kit.label("Income %d (regions %d, trade %d, cost of a large realm -%d), upkeep %d: %+d a turn." % [
		int(inc["total"]), int(inc["regions"]), int(inc["trade"]), int(inc.get("corruption", 0)), up, int(inc["total"]) - up],
		Kit.FONT, Kit.COL_GOLD, true))
	box.add_child(Kit.label("A turn ending with less than nothing costs every unit a tenth of its men.", Kit.FONT_SMALL, Kit.COL_DIM, true))
	box.add_child(Kit.section("Regions"))
	var fl := Kit.flow(6)
	for r in CState.regions_of(ps, f):
		var rs: Dictionary = ps["regions"][r]
		var busy := "" if (rs["build"] as Array).is_empty() else " *"
		fl.add_child(Kit.button("%s (%s, %d)%s" % [CData.REGIONS[r]["city"], CData.LEVEL_NAMES[int(rs["level"])].to_lower(),
			CRules.region_income(ps, r), busy], func():
			s.close_dialog()
			s.select_region(r)
			s.focus_region(r), 0, Kit.FONT_SMALL))
	box.add_child(fl)
	box.add_child(Kit.section("Armies"))
	var fl2 := Kit.flow(6)
	for a in CState.armies_of(ps, f):
		var id := int(a["id"])
		var mv: int = s.planned_move(id)
		var t := "%s: %d units%s" % [CData.REGIONS[int(a["r"])]["city"], CState.unit_count(a), " -> " + str(CData.REGIONS[mv]["city"]) if mv >= 0 else ""]
		fl2.add_child(Kit.button(t, func():
			s.close_dialog()
			s.select_army(id)
			s.focus_region(int(a["r"])), 0, Kit.FONT_SMALL))
	box.add_child(fl2)
	var wars: Array[String] = []
	for g in CState.nf():
		if g != f and CState.alive(ps, g) and CState.dip(ps, f, g) == CState.WAR:
			wars.append(CData.faction_name(g))
	box.add_child(Kit.label("At war with: " + (", ".join(wars) if not wars.is_empty() else "nobody"), Kit.FONT, Kit.COL_BAD, true))
	s.show_dialog(CData.faction_name(f), box, [["Close", Callable()]])


# ------------------------------------------------------------ diplomacy ---

func show_diplomacy(focus: int = -1) -> void:
	var ps: Dictionary = s.ps
	var f: int = s.f
	if f < 0:
		return
	var focus_row: Control = null
	var box := Kit.vbox(8)
	box.add_child(Kit.label("Proposals are answered when the turn is resolved; the other side weighs its strength against yours, how long the war has lasted and its losses.", Kit.FONT_SMALL, Kit.COL_DIM, true))
	for p in ps["proposals"]:
		if int(p["to"]) != f:
			continue
		var pid := int(p["id"])
		var answered := -1
		for o in s.orders:
			if str(o["t"]) == "answer" and int(o["id"]) == pid:
				answered = int(o["accept"])
		var h := Kit.hbox(6)
		h.add_child(Kit.label("%s offers %s." % [CData.faction_name(int(p["from"])), _what(str(p["what"]))], Kit.FONT, Kit.COL_GOLD, true))
		if answered < 0:
			h.add_child(Kit.button("Accept", func():
				s.add_order({"t": "answer", "id": pid, "accept": 1})
				show_diplomacy(), 80))
			h.add_child(Kit.button("Refuse", func():
				s.add_order({"t": "answer", "id": pid, "accept": 0})
				show_diplomacy(), 80))
		else:
			h.add_child(Kit.label("accepted" if answered == 1 else "refused", Kit.FONT_SMALL, Kit.COL_DIM))
		box.add_child(h)
	var mine := _fstrength(ps, f)
	for g in CState.nf():
		if g == f or not CState.alive(ps, g):
			continue
		var d := CState.dip(ps, f, g)
		var row := Kit.hbox(6)
		row.name = "dip_%s" % CData.FACTIONS[g]["key"]
		if g == focus:
			focus_row = row
		row.add_child(Kit.swatch(_fc(g), 18))
		var them := _fstrength(ps, g)
		var desc := "%s - %s. %d regions, %s army." % [CData.faction_name(g), CState.DIP_NAMES[d],
			CState.regions_of(ps, g).size(), _compare(mine, them)]
		var l := Kit.label(desc, Kit.FONT, Kit.COL_BAD if d == CState.WAR else Color.WHITE, true)
		row.add_child(l)
		box.add_child(row)
		if d == CState.ALLIED:
			continue
		var acts := Kit.hbox(6)
		row.add_child(acts)
		var planned := ""
		for o in s.orders:
			if (str(o["t"]) == "propose" or str(o["t"]) == "war") and int(o["to"]) == g:
				planned = str(o.get("what", "war"))
		if planned != "":
			acts.add_child(Kit.label("Planned: " + _what(planned), Kit.FONT_SMALL, Kit.COL_GOOD))
			acts.add_child(Kit.button("Cancel", func():
				s.remove_orders(func(o): return (str(o["t"]) == "propose" or str(o["t"]) == "war") and int(o["to"]) == g)
				show_diplomacy(), 80))
		else:
			if d == CState.WAR:
				acts.add_child(_dip_button("Offer peace", {"t": "propose", "to": g, "what": "peace"}))
			if d == CState.PEACE:
				acts.add_child(_dip_button("Offer trade", {"t": "propose", "to": g, "what": "trade"}))
			if d == CState.TRADE:
				acts.add_child(_dip_button("End trade", {"t": "propose", "to": g, "what": "cancel_trade"}))
			if d != CState.WAR:
				var wb := Kit.button("Declare war", func(): _confirm_war(g), 0)
				wb.add_theme_color_override("font_color", Kit.COL_BAD)
				acts.add_child(wb)
	s.show_dialog("Diplomacy", box, [["Close", Callable()]], 700)
	if focus_row != null:
		# Bring the faction asked about into view and mark it.
		var hl := StyleBoxFlat.new()
		hl.bg_color = Color(1, 0.85, 0.4, 0.16)
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", hl)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.show_behind_parent = true
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		focus_row.add_child(p)
		s.dialog_scroll.call_deferred("ensure_control_visible", focus_row)


func _dip_button(text: String, o: Dictionary) -> Button:
	return Kit.button(text, func():
		s.add_order(o)
		show_diplomacy(), 0)


func _confirm_war(g: int) -> void:
	var l := Kit.label("Declare war on %s? It takes effect when the turn is resolved, before armies move, so moves into their land can be planned right away and happen this turn." % CData.faction_name(g), Kit.FONT, Color.WHITE, true)
	s.show_dialog("War", l, [["Declare war", func():
		s.add_order({"t": "war", "to": g})
		show_diplomacy(g)], ["Back", func(): show_diplomacy(g)]], 460)


func _what(w: String) -> String:
	return {"peace": "peace", "trade": "a trade agreement", "cancel_trade": "an end to trade", "war": "war"}.get(w, w)


func _fstrength(ps: Dictionary, f: int) -> int:
	var t := 0
	for a in CState.armies_of(ps, f):
		t += CState.strength(a)
	return t


func _compare(mine: int, them: int) -> String:
	if them * 100 > mine * 150:
		return "much stronger"
	if them * 100 > mine * 110:
		return "stronger"
	if them * 100 * 150 < mine * 100 * 100:
		return "much weaker"
	if them * 110 < mine * 100:
		return "weaker"
	return "about equal"


# -------------------------------------------------------------- battles ---

func show_battles() -> void:
	if s.online != null:
		s.onl.show_battles()
		return
	var st: Dictionary = s.st
	var list := CTurn.pending_for(st)
	var box := Kit.vbox(10)
	if list.is_empty():
		box.add_child(Kit.label("No battles pending.", Kit.FONT, Color.WHITE))
		s.show_dialog("Battles", box, [["Close", Callable()]], 520)
		return
	box.add_child(Kit.label("Battles must be resolved before the turn can be planned. Auto-resolve lets the battle AI fight both sides (honest, a little worse than good command); Fight to command it yourself.", Kit.FONT_SMALL, Kit.COL_DIM, true))
	for b in list:
		box.add_child(_battle_card(st, b))
	s.show_dialog("Pending battles (%d)" % list.size(), box, [["Close", Callable()]], 720)


func _battle_card(st: Dictionary, b: Dictionary) -> Control:
	var p := Kit.panel(Color(1, 1, 1, 0.06), 8)
	var v := Kit.vbox(6)
	p.add_child(v)
	var r := int(b["r"])
	var facs := CRules.battle_factions(st, b)
	var arm := CRules.battle_armies(st, b)
	var sides := ["", ""]
	for k in 2:
		var names: Array[String] = []
		for f in facs[k]:
			names.append(CData.faction_name(int(f)))
		sides[k] = " and ".join(names)
	var kind := str(b.get("kind", ""))
	var title := "Battle of %s (%s): %s (attacking) against %s" % [CData.REGIONS[r]["city"], CData.REGIONS[r]["name"], sides[0], sides[1]]
	match kind:
		"assault":
			title = "Assault on %s (%s): %s storm the walls held by %s" % [CData.REGIONS[r]["city"], CData.REGIONS[r]["name"], sides[0], sides[1]]
		"sally":
			title = "Sally from %s (%s): %s ride out against the besiegers, %s (a field battle)" % [CData.REGIONS[r]["city"], CData.REGIONS[r]["name"], sides[1], sides[0]]
		"relief":
			title = "Relief of %s (%s): %s and the garrison against the besiegers, %s (a field battle)" % [CData.REGIONS[r]["city"], CData.REGIONS[r]["name"], sides[1], sides[0]]
	v.add_child(Kit.label(title, Kit.FONT, Kit.COL_GOLD, true))
	var men := [0, 0]
	var units := [0, 0]
	for k in 2:
		for a in arm[k]:
			men[k] += CState.men(a)
			units[k] += CState.unit_count(a)
	var gar := CRules.garrison(st, r)
	var gmen := 0
	for g in gar:
		gmen += int(g["n"])
	var hs := CRules.battle_humans(st, b)
	var human_att: bool = facs[0].has(hs[0])
	var terr := Terrain.KIND_NAMES[int(CData.REGIONS[r]["terrain"])].to_lower()
	var field := int(b.get("settlement", 1)) == 0
	var where := ("in the field outside the walls, on %s ground" % terr) if field else ("walls %d, %s ground" % [CState.walls(st, r), terr])
	v.add_child(Kit.label("Attackers %d units, %d men. Defenders %d units, %d men, plus a garrison of %d (%s)." % [
		units[0], men[0], units[1], men[1], gmen, where], Kit.FONT_SMALL, Color.WHITE, true))
	var lead := [int(b["att_f"]), int(b["def_f"])]
	v.add_child(Kit.odds_view(CBattle.battle_odds(st, b), 0 if human_att else 1, [_names([lead[0]]), _names([lead[1]])],
		[_fc(lead[0]), _fc(lead[1])], "Balance of power (estimate from the battle formula):"))
	if not (b["reinf"] as Array).is_empty():
		v.add_child(Kit.label("Reinforcements from neighbouring regions join the line.", Kit.FONT_SMALL, Kit.COL_DIM, true))
	var h := Kit.hbox(8)
	h.alignment = BoxContainer.ALIGNMENT_END
	var bid := int(b["id"])
	var ab := Kit.button("Auto-resolve", func(): s.auto_resolve(bid), 130)
	ab.name = "auto_%d" % bid
	h.add_child(ab)
	var fb := Kit.button("Fight", func(): s.fight(bid), 110)
	fb.name = "fight_%d" % bid
	h.add_child(fb)
	v.add_child(h)
	return p


func show_battle_result(events_before: int, outcome: Dictionary) -> void:
	var st: Dictionary = s.st
	var box := Kit.vbox(6)
	var evs: Array = st["events"]
	for i in range(events_before, evs.size()):
		var t := event_text(evs[i], s.f)
		if t != "":
			box.add_child(Kit.label(t, Kit.FONT, Color.WHITE, true))
	if int(outcome.get("forfeit", 0)) != 0:
		box.add_child(Kit.label("You left the field: the army withdrew and the battle counts as lost.", Kit.FONT_SMALL, Kit.COL_DIM, true))
	if int(outcome.get("scale", 100)) < 100:
		box.add_child(Kit.label("(Big battle: auto-resolved at half unit size, results scaled up.)", Kit.FONT_SMALL, Kit.COL_DIM, true))
	s.show_dialog("Battle result", box, [["Continue", func(): s._next_step()]], 560)


# -------------------------------------------------------------- summary ---

## "What happened since you last played": events of the turns after `seen`.
func show_summary(seen: int, then: Callable = Callable()) -> void:
	var st: Dictionary = s.st
	var f: int = s.f
	var mine := Kit.vbox(4)
	var world := Kit.vbox(4)
	for e in st["events"]:
		if int(e["turn"]) <= seen and seen >= 0:
			continue
		var t := event_text(e, f)
		if t == "":
			continue
		var col := Color.WHITE
		if _involves(e, f):
			mine.add_child(Kit.label(t, Kit.FONT, _event_color(e, f), true))
		elif str(e["k"]) in ["captured", "eliminated", "war", "peace"]:
			world.add_child(Kit.label(t, Kit.FONT_SMALL, Kit.COL_DIM, true))
		col = col
	var box := Kit.vbox(8)
	box.add_child(Kit.label("%s. Treasury %s." % [CData.date_text(int(st["turn"])), Kit.money(int(st["factions"][f]["treasury"]))], Kit.FONT, Kit.COL_GOLD))
	if mine.get_child_count() == 0:
		mine.add_child(Kit.label("A quiet season for you.", Kit.FONT, Color.WHITE))
	box.add_child(mine)
	if world.get_child_count() > 0:
		box.add_child(Kit.section("Elsewhere"))
		box.add_child(world)
	var nb := CTurn.pending_for(st, f).size()
	if nb > 0:
		box.add_child(Kit.label("%d battle%s to resolve before planning." % [nb, "" if nb == 1 else "s"], Kit.FONT, Kit.COL_BAD))
	s.show_dialog("Since you last played: %s" % CData.faction_name(f), box, [["Continue", then]], 640)


func show_intro() -> void:
	var f: int = s.f
	var box := Kit.vbox(8)
	box.add_child(Kit.label("%s. You lead %s." % [CData.date_text(int(s.st["turn"])), CData.faction_name(f)], Kit.FONT, Kit.COL_GOLD, true))
	box.add_child(Kit.label("Each turn: move your armies (tap an army, then a highlighted region; red regions mean a battle), build and recruit in your regions (tap a region), and End turn. Battles are resolved before the next turn: auto-resolve or fight them yourself.", Kit.FONT, Color.WHITE, true))
	var p := CRules.victory_progress(s.st)
	box.add_child(Kit.label("Goal: hold %d regions including %d of Roma, Carthago, Pella, Syracusae and Athenae. You lose if %s is destroyed." % [
		int(p["need_regions"]), int(p["need_capitals"]), "either player" if (s.st["humans"] as Array).size() > 1 else "your faction"], Kit.FONT, Color.WHITE, true))
	s.show_dialog("A new campaign", box, [["Start", Callable()]], 600)


func _involves(e: Dictionary, f: int) -> bool:
	for k in ["f", "from", "to", "a", "b", "o", "by"]:
		if e.has(k) and int(e[k]) == f and str(e["k"]) != "move_failed":
			return true
	if str(e["k"]) == "battle":
		return (e["att"] as Array).has(f) or (e["def"] as Array).has(f)
	if str(e["k"]) == "captured":
		return int(e["f"]) == f or int(e["from"]) == f
	if str(e["k"]) in ["order_failed", "move_failed"]:
		return int(e["f"]) == f
	return str(e["k"]) in ["victory", "defeat"]


func _event_color(e: Dictionary, f: int) -> Color:
	match str(e["k"]):
		"battle":
			var won := (int(e["winner"]) == 0 and (e["att"] as Array).has(f)) or (int(e["winner"]) == 1 and (e["def"] as Array).has(f))
			return Kit.COL_GOOD if won else Kit.COL_BAD
		"captured":
			return Kit.COL_GOOD if int(e["f"]) == f else Kit.COL_BAD
		"war", "destroyed", "debt", "eliminated", "defeat", "order_failed", "move_failed", "starving":
			return Kit.COL_BAD
		"siege":
			return Kit.COL_BAD if int(e["o"]) == f else Kit.COL_GOLD
		"siege_lifted":
			return Kit.COL_GOOD if int(e["o"]) == f else Kit.COL_DIM
		"peace", "trade", "built", "recruited", "grew", "victory":
			return Kit.COL_GOOD
	return Color.WHITE


func _names(list: Array) -> String:
	var out: Array[String] = []
	for f in list:
		out.append(CData.faction_name(int(f)))
	return " and ".join(out)


func event_text(e: Dictionary, f: int) -> String:
	var city := func(r): return str(CData.REGIONS[int(r)]["city"])
	match str(e["k"]):
		"battle":
			var w := "the attackers won" if int(e["winner"]) == 0 else "the defenders held"
			var how := str(e["mode"]).replace("formula", "fought out of sight")
			var loss := "Losses %d of %d and %d of %d men." % [int(e["att_lost"]), int(e["att_men"]), int(e["def_lost"]), int(e["def_men"])]
			match str(e.get("kind", "")):
				"assault":
					return "Assault on %s: %s stormed the walls of %s; %s (%s). %s" % [city.call(e["r"]), _names(e["att"]), _names(e["def"]),
						"the city fell" if int(e["winner"]) == 0 else "the walls held", how, loss]
				"sally", "relief":
					return "%s %s: %s against the besiegers, %s; %s (%s). %s" % ["Sally from" if str(e["kind"]) == "sally" else "Relief of",
						city.call(e["r"]), _names(e["def"]), _names(e["att"]),
						"the siege goes on" if int(e["winner"]) == 0 else "the siege is broken", how, loss]
			return "Battle of %s: %s attacked %s; %s (%s). %s" % [city.call(e["r"]),
				_names(e["att"]), _names(e["def"]), w, how, loss]
		"captured":
			if str(e.get("how", "")) == "surrendered":
				return "%s surrendered to %s (%s) after a siege." % [city.call(e["r"]), CData.faction_name(int(e["f"])), CData.faction_name(int(e["from"]))]
			return "%s took %s from %s." % [CData.faction_name(int(e["f"])), city.call(e["r"]), CData.faction_name(int(e["from"]))]
		"siege":
			return "%s laid siege to %s (%s)." % [CData.faction_name(int(e["f"])), city.call(e["r"]), CData.faction_name(int(e["o"]))]
		"siege_lifted":
			return "The siege of %s by %s was lifted%s." % [city.call(e["r"]), CData.faction_name(int(e["f"])),
				": the besiegers marched away" if str(e.get("why", "")) == "left" else ""]
		"starving":
			if int(e["f"]) != f and int(e["by"]) != f:
				return ""
			return "%s is starving under siege: garrison at %d%%." % [city.call(e["r"]), int(e["gar"])]
		"retreat":
			return "A %s army fell back from %s to %s." % [CData.FACTIONS[int(e["f"])]["adj"], city.call(e["r"]), city.call(e["to"])]
		"destroyed":
			return "A %s army of %d men was destroyed at %s with nowhere to retreat." % [CData.FACTIONS[int(e["f"])]["adj"], int(e["men"]), city.call(e["r"])]
		"war":
			return "%s declared war on %s." % [CData.faction_name(int(e["a"])), CData.faction_name(int(e["b"]))]
		"peace":
			return "%s and %s made peace." % [CData.faction_name(int(e["a"])), CData.faction_name(int(e["b"]))]
		"trade":
			return "%s and %s agreed to trade." % [CData.faction_name(int(e["a"])), CData.faction_name(int(e["b"]))]
		"trade_end":
			return "%s and %s stopped trading." % [CData.faction_name(int(e["a"])), CData.faction_name(int(e["b"]))]
		"refused":
			return "%s refused %s from %s." % [CData.faction_name(int(e["from"])), _what(str(e["what"])), CData.faction_name(int(e["to"]))]
		"proposal":
			return "%s offers %s (answer in Diplomacy this turn)." % [CData.faction_name(int(e["from"])), _what(str(e["what"]))]
		"built":
			if int(e["f"]) != f:
				return ""
			return "%s: %s %d completed." % [city.call(e["r"]), CData.CHAINS[int(e["chain"])]["name"], int(e["level"])]
		"recruited":
			if int(e["f"]) != f:
				return ""
			var names: Array[String] = []
			for k in e["units"]:
				names.append(str(UT.TYPES[UT.index_of(str(k))]["name"]))
			return "%s: recruited %s." % [city.call(e["r"]), ", ".join(names)]
		"grew":
			if int(e["f"]) != f:
				return ""
			return "%s grew into a %s." % [city.call(e["r"]), CData.LEVEL_NAMES[int(e["level"])].to_lower()]
		"debt":
			if int(e["f"]) != f:
				return ""
			return "The treasury is empty (%d): men deserted." % int(e["treasury"])
		"eliminated":
			return "%s has been destroyed." % CData.faction_name(int(e["f"]))
		"order_failed":
			if int(e["f"]) != f:
				return ""
			return "An order could not be carried out: %s." % str(e["why"])
		"move_failed":
			if int(e["f"]) != f:
				return ""
			return "An army could not move to %s: %s." % [city.call(e["to"]), str(e["why"])]
		"victory":
			return "Victory!"
		"defeat":
			return "%s has fallen: the campaign is lost." % CData.faction_name(int(e["f"]))
	return ""


# ----------------------------------------------------------- objectives ---

func show_objectives() -> void:
	var st: Dictionary = s.ps
	var p := CRules.victory_progress(st)
	var box := Kit.vbox(8)
	box.add_child(Kit.label("Win together: hold %d regions (you hold %d) including %d of the five great cities (you hold %d)." % [
		int(p["need_regions"]), int(p["regions"]), int(p["need_capitals"]), int(p["capitals"])], Kit.FONT, Color.WHITE, true))
	for key in CData.KEY_CITIES:
		var r := CData.region_index(key)
		var o := CState.owner(st, r)
		var h := Kit.hbox(6)
		h.add_child(Kit.swatch(_fc(o), 16))
		h.add_child(Kit.label("%s - %s" % [CData.REGIONS[r]["city"], CData.faction_name(o)], Kit.FONT,
			Kit.COL_GOOD if CState.is_human(st, o) else Color.WHITE))
		box.add_child(h)
	box.add_child(Kit.label("You lose if %s loses all its regions." % ("either player's faction" if (st["humans"] as Array).size() > 1 else "your faction"), Kit.FONT, Kit.COL_BAD, true))
	var t: Dictionary = st["settings"]
	box.add_child(Kit.label("Settings: turn timeout %s (%s), battles %s, AI aggression %d%%." % [
		"off" if int(t["turn_timeout_h"]) == 0 else "%d h" % int(t["turn_timeout_h"]),
		"online campaigns: the server's setting, see Online" if s.online != null else "used by online campaigns only",
		"always auto-resolved" if str(t["autoresolve"]) == "auto" else "your choice each time", int(t["ai_aggression"])], Kit.FONT_SMALL, Kit.COL_DIM, true))
	s.show_dialog("Objectives", box, [["Close", Callable()]], 560)


func show_game_over() -> void:
	var st: Dictionary = s.st
	var won := int(st["winner"]) == 1
	var box := Kit.vbox(8)
	box.add_child(Kit.label("Victory! The Mediterranean is yours." if won else "Defeat.", 24, Kit.COL_GOOD if won else Kit.COL_BAD))
	box.add_child(Kit.label("%s, turn %d." % [CData.date_text(int(st["turn"])), int(st["turn"])], Kit.FONT, Color.WHITE))
	s.show_dialog("The campaign is over", box, [["Back to menu", func(): s.request_exit()], ["Look at the map", Callable()]], 520)


# ------------------------------------------------------------- warnings ---

## Short list of things left undone this turn.
func warnings() -> Array:
	var ps: Dictionary = s.ps
	var f: int = s.f
	var out: Array = []
	var idle := 0
	for a in CState.armies_of(ps, f):
		if int(a["busy"]) == 0 and s.planned_move(int(a["id"])) < 0 and CRules.siege_role(ps, a) == 0:
			var near_enemy := false
			for e in CData.adjacent(int(a["r"])):
				if CState.at_war(ps, f, CState.owner(ps, int(e[0]))):
					near_enemy = true
			if near_enemy:
				idle += 1
	if idle > 0:
		out.append("%d arm%s next to an enemy without orders." % [idle, "y" if idle == 1 else "ies"])
	var can_build := 0
	var cheapest := 1 << 30
	for r in CState.regions_of(ps, f):
		if not (ps["regions"][r]["build"] as Array).is_empty():
			continue
		for c in CData.CHAINS.size():
			var info := CRules.build_info(ps, f, r, c)
			if not info.has("why"):
				can_build += 1
				cheapest = mini(cheapest, int(info["cost"]))
				break
	if can_build > 0:
		out.append("%d region%s could start a building (from %d)." % [can_build, "" if can_build == 1 else "s", cheapest])
	for p in ps["proposals"]:
		if int(p["to"]) == f:
			var answered := false
			for o in s.orders:
				if str(o["t"]) == "answer" and int(o["id"]) == int(p["id"]):
					answered = true
			if not answered:
				out.append("%s's offer of %s is unanswered (it lapses)." % [CData.faction_name(int(p["from"])), _what(str(p["what"]))])
	return out


func show_warnings(list: Array) -> void:
	var box := Kit.vbox(6)
	for w in list:
		box.add_child(Kit.label("- " + str(w), Kit.FONT, Color.WHITE, true))
	s.show_dialog("Before you end the turn", box, [["End turn", func():
		s.close_dialog()
		s.end_turn(true)], ["Back", Callable()]], 520)


# ------------------------------------------------------------------ menu ---

func show_menu() -> void:
	var box := Kit.vbox(8)
	if s.online != null:
		box.add_child(Kit.label("%s - %s. Online: saved on the server." % [str(s.st["name"]), CData.date_text(int(s.st["turn"]))], Kit.FONT, Color.WHITE, true))
	else:
		box.add_child(Kit.label("%s - %s. Saved automatically." % [str(s.st["name"]), CData.date_text(int(s.st["turn"]))], Kit.FONT, Color.WHITE, true))
	box.add_child(Kit.label("State %s" % CState.hash_text(s.st), Kit.FONT_SMALL, Kit.COL_DIM))
	var fl := Kit.flow(8)
	if s.online != null:
		fl.add_child(Kit.button("Online", func(): s.onl.show_online(), 0))
	else:
		fl.add_child(Kit.button("Export save as text", func(): show_export(), 0))
		var net: Node = s.get_node_or_null("/root/Net")
		if net != null and net.has_server() and str(s.st["phase"]) == "plan" and int(s.st["turn"]) >= 0:
			var ob := Kit.button("Play online", func(): show_go_online(), 0)
			ob.name = "menu_go_online"
			fl.add_child(ob)
	fl.add_child(Kit.button("Controls", func():
		s.close_dialog()
		s.controls_page.open(), 0))
	box.add_child(fl)
	s.show_dialog("Campaign", box, [["Main menu", func():
		s.save()
		s.request_exit()], ["Back", Callable()]], 520)


## Move a local campaign online: the current state becomes an online
## campaign (this device plays the faction planning now; the other human
## seat, if any, joins with the code). The local save stays as it is.
func show_go_online() -> void:
	var net: Node = s.get_node_or_null("/root/Net")
	var box := Kit.vbox(8)
	var hs: Array = s.st["humans"]
	var me: int = s.f if s.f >= 0 else int(hs[0])
	box.add_child(Kit.label("Upload this campaign to the server and play it online. You keep %s%s. Plans not yet ended are not uploaded. The local save stays on this device unchanged." % [
		CData.faction_name(me), (", and your ally joins as %s with a code" % CData.faction_name(int(hs[1] if int(hs[0]) == me else hs[0]))) if hs.size() > 1 else ""], Kit.FONT, Color.WHITE, true))
	var inv := LineEdit.new()
	inv.placeholder_text = "Invite key (only if the server asks for one)"
	inv.text = str(net.accounts.data.get("invite", "")) if net else ""
	inv.custom_minimum_size = Vector2(300, 40)
	box.add_child(inv)
	var info := Kit.label("", Kit.FONT_SMALL, Kit.COL_BAD, true)
	box.add_child(info)
	s.show_dialog("Play online", box, [["Upload", func():
		info.text = "Uploading..."
		info.add_theme_color_override("font_color", Kit.COL_DIM)
		var r: Dictionary = await net.create_campaign(s.st, me, {"invite": inv.text.strip_edges()})
		if not r["ok"]:
			info.add_theme_color_override("font_color", Kit.COL_BAD)
			info.text = "Could not create it: %s" % (str(r["message"]) if str(r["message"]) != "" else str(r["error"]))
			return
		s._t("online_create", {"from": "local", "turn": int(s.st["turn"])})
		s.set_meta("go_online", str(r["data"]["id"]))
		s.request_exit()], ["Back", Callable()]], 560)


func show_export() -> void:
	s.save()
	var text := Saves.export_text(s.data)
	var box := Kit.vbox(8)
	box.add_child(Kit.label("Copy this text and send it to the other player; they paste it under Campaign > Import on the main menu. It holds the whole campaign, including plans not yet ended.", Kit.FONT_SMALL, Color.WHITE, true))
	var te := TextEdit.new()
	te.text = text
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.custom_minimum_size = Vector2(300, 140)
	te.editable = false
	box.add_child(te)
	var copy := Kit.button("Copy to clipboard", func():
		DisplayServer.clipboard_set(text)
		s._flash("Copied."), 0)
	box.add_child(copy)
	box.add_child(Kit.label("%d characters." % text.length(), Kit.FONT_SMALL, Kit.COL_DIM))
	s.show_dialog("Export", box, [["Close", Callable()]], 620)
