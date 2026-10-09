extends "res://game/touch_scroll.gd"
## One unit type's page: symbol, name, role, description, what it beats and
## what counters it, special rules, formation, and every stat that matters as
## a number plus a bar scaled against the best value of that stat among all
## unit types. Self-contained: call set_unit_type(ty); meant to be reused as
## the recruitment card in the campaign.
##
## Everything except the prose is read from the same unit type data the sim
## uses (sim/unit_types.gd) and from the scenario unit sizes, so it follows
## any stat tuning. Fixed-point values are shown in metres, m/s and seconds.

const UT := preload("res://sim/unit_types.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const Icons := preload("res://game/unit_icons.gd")
const IconView := preload("res://game/unit_icon_view.gd")
const CData := preload("res://campaign/cdata.gd")

const M := 1024.0
const TICKS_PER_SEC := 10.0
const BAR_W := 120.0
const COL_GOOD := Color(0.6, 0.95, 0.6)
const COL_BAD := Color(1.0, 0.6, 0.5)
const COL_DIM := Color(0.75, 0.75, 0.75)

## Stat rows: [label, key, kind]. kind: "int", "pct", "m" (distance),
## "mps" (speed), "s_low" (seconds, lower is better), "count", "s" (seconds,
## lower is better), "deg" (angle units, shown as the full arc in degrees),
## "degps" (angle units per tick, as degrees per second). Keys starting with
## "_" are derived values (see value()).
const MELEE_ROWS := [
	["Hit points", "hp", "int"], ["Melee attack", "attack", "int"],
	["Melee defence", "defence", "int"], ["Armour", "armour", "int"],
	["Shield (melee)", "shield", "pct"], ["Shield (missiles)", "mshield", "pct"],
	["Weapon damage", "damage", "int"], ["Reach", "reach", "m"],
	["Ranks that strike", "ranks_reach", "count"],
]
const MOVE_ROWS := [
	["Walk", "walk", "mps"], ["Run", "run", "mps"], ["Mass", "mass", "int"],
	["Morale", "morale", "int"],
]
const MISSILE_ROWS := [
	["Range", "m_range", "m"], ["Missile damage", "m_damage", "int"],
	["Armour piercing", "m_ap", "pct"], ["Ammunition", "m_ammo", "count"],
	["Rate of fire", "m_reload", "s_low"],
]
const ART_ROWS := [
	["Engines", "_engines", "count"], ["Crew each", "crew", "count"],
	["Silent below", "crew_min", "count"],
	["Range", "m_range", "m"], ["Min range", "m_min", "m"],
	["Shot energy", "m_damage", "int"], ["Armour pierce", "m_ap", "pct"],
	["Struck per shot", "m_pierce", "count"],
	["Shots / engine", "m_ammo", "count"], ["Reload", "m_reload", "s_low"],
	["Firing arc", "arc", "deg"], ["Traverse", "traverse", "degps"],
	["Set-up time", "deploy", "s"], ["Engine hp", "e_hp", "int"],
	["Reserve / engine", "m_reserve", "count"], ["Refill", "m_refill", "s_low"],
	["Fright per hit", "m_fear", "int"],
]
const SPECIAL_ROWS := [
	["Charge impact", "charge", "int"], ["Brace vs charges", "brace", "int"],
	["Bonus vs cavalry", "vs_cav", "int"],
]

var unit_type := -1
var side_color := Color(0.35, 0.6, 1.0)

var _box: VBoxContainer
var _icon: IconView
var _name: Label
var _role: Label
var _desc: Label
var _good: Label
var _bad: Label
var _tags: HFlowContainer
var _formation: Label
var _tier: Label
var _grid: GridContainer


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_box.add_child(head)
	_icon = IconView.new(0, side_color, 60.0)
	head.add_child(_icon)
	var names := VBoxContainer.new()
	head.add_child(names)
	_name = _label("", 26, Color.WHITE)
	names.add_child(_name)
	_role = _label("", 16, COL_DIM)
	names.add_child(_role)
	_desc = _label("", 16, Color.WHITE, true)
	_box.add_child(_desc)
	_good = _label("", 15, COL_GOOD, true)
	_box.add_child(_good)
	_bad = _label("", 15, COL_BAD, true)
	_box.add_child(_bad)
	_tags = HFlowContainer.new()
	_tags.add_theme_constant_override("h_separation", 6)
	_tags.add_theme_constant_override("v_separation", 6)
	_box.add_child(_tags)
	_formation = _label("", 15, COL_DIM, true)
	_box.add_child(_formation)
	_tier = _label("", 15, Color(1.0, 0.85, 0.45), true)
	_box.add_child(_tier)
	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 4)
	_box.add_child(_grid)


func set_unit_type(ty: int, p_side_color: Color = Color(0.35, 0.6, 1.0)) -> void:
	unit_type = ty
	side_color = p_side_color
	scroll_vertical = 0
	_icon.set_icon(Icons.icon_of(ty), side_color)
	_name.text = str(UT.TYPES[ty]["name"])
	var role := UT.text(ty, "role")
	var cname := _class_name(UT.cls(ty))
	_role.text = role if role.to_lower() == cname else "%s  -  %s" % [role, cname]
	_desc.text = UT.text(ty, "desc")
	_good.text = "Good against: " + UT.text(ty, "good_vs")
	_bad.text = "Countered by: " + UT.text(ty, "weak_vs")
	for c in _tags.get_children():
		c.queue_free()
	for t in tags(ty):
		_tags.add_child(_chip(t))
	var soldiers: int = UT.size_of(ty)
	var files: int = Scenarios.FILES.get(UT.base_of(ty), 0)
	_formation.text = "%d soldiers per unit in %d files. Spacing %.1f m between files, %.1f m between ranks. Cost %d per soldier." % [
		soldiers, files, UT.stat(ty, "file_sp") / M, UT.stat(ty, "rank_sp") / M, UT.stat(ty, "cost")]
	var tier := UT.tier_of(ty)
	var lines := {"heavy": "Barracks", "light": "Barracks", "spear": "Barracks", "pike": "Barracks",
		"archer": "Range", "javelin": "Range", "cav": "Stables", "bolt": "Workshop", "stone": "Workshop",
		"siege": "Workshop"}
	var bld: String = lines.get(UT.line_of(ty), "")
	var need := tier if UT.cls(ty) != UT.CLS_ART else (2 if UT.base_of(ty) == UT.STONE else 1)
	var need_txt := "%s %d" % [bld, need]
	var tkey := UT.key_of(ty)
	if CData.UNIT_NEEDS.has(tkey):
		var nl: Array[String] = []
		for nd in CData.UNIT_NEEDS[tkey]:
			nl.append("%s %d" % [str(CData.CHAINS[int(nd[0])]["name"]), int(nd[1])])
		need_txt = " and ".join(nl)
	_tier.text = "Tier %d (%s line).  Campaign: %d to recruit, %d upkeep per turn; needs %s." % [
		tier, str(UT.TYPES[UT.base_of(ty)]["name"]).to_lower(), UT.price_of(ty),
		UT.price_of(ty) * CData.UPKEEP_PCT / 100, need_txt]
	var wt := UT.stat(ty, "wagon")
	if wt >= 0:
		_tier.text += "\nWagon: %d horse%s, %s; stock %d%% of a hand cart's (%s); hit points %d. Auto-resolve: the army's missile and artillery strength +%d%%." % [
			UT.wagon_stat(wt, "horses"), "" if UT.wagon_stat(wt, "horses") == 1 else "s",
			"%.1f m/s" % (UT.wagon_pace(wt, UT.wagon_stat(wt, "horses")) / 102.4), UT.wagon_stat(wt, "stock_pct"),
			"%d arrows, %d javelins, %d bolts, %d stones" % [UT.ammo_stat(0, "wagon"), UT.ammo_stat(1, "wagon"),
				UT.ammo_stat(2, "wagon"), UT.ammo_stat(3, "wagon")], UT.wagon_stat(wt, "hp"), UT.wagon_stat(wt, "bonus_pct")]
	var aml := ammo_line(ty)
	if aml != "":
		_tier.text += "\n" + aml
	if UT.cls(ty) == UT.CLS_ART:
		_formation.text = "%d engines with %d crew each (%d soldiers), %d m apart. Cost %d per crew member (%d per battery)." % [
			value(ty, "_engines"), UT.stat(ty, "crew"), soldiers, UT.stat(ty, "file_sp") / 1024,
			UT.stat(ty, "cost"), UT.stat(ty, "cost") * soldiers]
	for c in _grid.get_children():
		c.queue_free()
	var rows: Array = []
	_section(rows, "Melee", MELEE_ROWS, ty)
	_section(rows, "Movement and morale", MOVE_ROWS, ty)
	if UT.cls(ty) == UT.CLS_ART:
		_section(rows, "Artillery", ART_ROWS, ty)
	elif UT.stat(ty, "m_ammo") > 0:
		_section(rows, "Missiles", MISSILE_ROWS, ty)
	var special: Array = []
	for r in SPECIAL_ROWS:
		if UT.stat(ty, r[1]) > 0:
			special.append(r)
	if not special.is_empty():
		_section(rows, "Special", special, ty)
	# Narrow screens (phones): one column of stats, so the page never needs
	# horizontal room it does not have.
	var narrow := is_inside_tree() and get_viewport_rect().size.x < 1150.0
	_grid.columns = 3 if narrow else 6
	if narrow:
		for r in rows:
			_add_row(r)
		return
	# Two columns, split at the section boundary nearest the middle so a
	# section never breaks across columns.
	var split := rows.size()
	for k in rows.size():
		if k > 0 and rows[k].has("title") and absi(2 * k - rows.size()) < absi(2 * split - rows.size()):
			split = k
	var left := rows.slice(0, split)
	var right := rows.slice(split)
	for k in maxi(left.size(), right.size()):
		for col in [left, right]:
			if k < col.size():
				_add_row(col[k])
			else:
				for i in 3:
					_grid.add_child(Control.new())


## Ammunition: the standard kind and the special kinds that ride on the
## weapon, with who carries them (campaign: faction and building), from
## the data (UnitTypes.AMMO, CData.AMMO_AVAIL). "" for a type without
## missiles.
static func ammo_line(ty: int) -> String:
	var std := UT.stat(ty, "m_ak")
	if std < 0:
		return ""
	var parts: Array[String] = []
	for k in UT.ammo_specials(ty):
		var who: Array[String] = []
		var key := str(UT.AMMO[k]["key"])
		for row in CData.AMMO_AVAIL:
			if str(row[0]) != key:
				continue
			var fs: Array[String] = []
			for fk in row[1]:
				fs.append(CData.faction_name(CData.faction_index(str(fk))))
			who.append("%s, %s %d" % [", ".join(fs), str(CData.CHAINS[int(row[2])]["name"]), int(row[3])])
		parts.append("%s (%d%% of the load, %d%% damage, %d%% range%s): %s%s" % [UT.ammo_text(k, "name"),
			UT.ammo_stat(k, "share"), UT.ammo_stat(k, "dmg"), UT.ammo_stat(k, "range"),
			", sets things alight" if UT.ammo_stat(k, "fire") > 0 else "", UT.ammo_text(k, "desc"),
			(" Carried by: " + "; ".join(who) + ".") if not who.is_empty() else ""])
	var head := "Ammunition: %s." % UT.ammo_text(std, "name").to_lower()
	if parts.is_empty():
		return head
	return head + " Special: " + " ".join(parts)


## Special rules as short tags, derived from the data so they follow tuning.
static func tags(ty: int) -> Array[String]:
	var out: Array[String] = []
	var c := UT.cls(ty)
	if UT.stat(ty, "ranks_reach") > 1:
		out.append("Ranks 1-%d strike (pike wall)" % UT.stat(ty, "ranks_reach"))
	if UT.stat(ty, "brace") > 0:
		out.append("Braces vs cavalry" + (" (when formed)" if c == UT.CLS_PIKE else " (standing still)"))
	if UT.stat(ty, "vs_cav") > 0:
		out.append("+%d vs cavalry" % UT.stat(ty, "vs_cav"))
	if UT.stat(ty, "turn") > 0 and UT.stat(ty, "turn") <= 6:
		out.append("Turns slowly (90 deg in %.0f s)" % (256.0 / UT.stat(ty, "turn") / TICKS_PER_SEC))
	if UT.stat(ty, "sec_attack") > 0:
		out.append("Short sword when disordered or flanked (att %d, def %d, dmg %d)" % [
			UT.stat(ty, "sec_attack"), UT.stat(ty, "sec_defence"), UT.stat(ty, "sec_damage")])
	if UT.stat(ty, "charge") > 0:
		out.append("Charge impact: knocks soldiers down")
	if c == UT.CLS_CAV:
		out.append("Charge rolls on until the front rank has struck")
		out.append("Shields and ranks blunt a charge into a steady front")
		var runup := (100 / BattleSim.MOM_GAIN) * (UT.stat(ty, "run") * 7 / 8) / 1024
		out.append("Full charge needs ~%d m of run-up" % runup)
		out.append("Pull out and charge again (turning away costs blows)")
	if UT.stat(ty, "m_vuln") > 100 or UT.stat(ty, "m_down") > 0:
		out.append("Vulnerable to missiles (x%.1f damage, %d%% of hits bring a horse down)" % [
			UT.stat(ty, "m_vuln") / 100.0, UT.stat(ty, "m_down")])
	# Terrain (data-driven: the type's climb rate and missile height gain).
	if c == UT.CLS_ART:
		out.append("Packed up: -%d%% speed per 10%% uphill" % UT.stat(ty, "climb"))
	else:
		out.append("Uphill: -%d%% speed per 10%% of slope" % UT.stat(ty, "climb"))
	if UT.stat(ty, "m_ammo") > 0 and UT.stat(ty, "m_hgain") > 0:
		var gain := UT.stat(ty, "m_hgain") / 10
		out.append("Range +%d m from 10 m higher (-%d m shooting up)" % [gain, gain])
	if UT.stat(ty, "m_ammo") > 0 and UT.stat(ty, "m_arc") == 0:
		out.append("Flat: blocked by a crest in the way")
	if UT.stat(ty, "charge") > 0:
		out.append("Charges downhill hit up to +%d%%, uphill down to -%d%%" % [
			BattleSim.CHG_H_MAX - 100, 100 - BattleSim.CHG_H_MIN])
	if c == UT.CLS_PIKE:
		out.append("Wall breaks %d%% faster on steep ground" % (BattleSim.PIKE_STEEP_DIS - 100))
	if c == UT.CLS_ART and UT.stat(ty, "m_kind") == 2:
		out.append("Stones bounce less far uphill")
	if c == UT.CLS_ART:
		var kind := UT.stat(ty, "m_kind")
		if kind == 1:
			out.append("Flat bolts: friends in the line are hit or stop it")
			out.append("Pierces up to %d men in a row" % UT.stat(ty, "m_pierce"))
			out.append("Big shields and armour soak it up")
		else:
			out.append("Lobbed over friends")
			out.append("Bounces %d m on through the ranks, knocking men down" % (UT.stat(ty, "m_plough") / 1024))
			out.append("Aims at the near face; lands short rather than over")
			out.append("Smashes engines")
		out.append("Minimum range %d m" % (UT.stat(ty, "m_min") / 1024))
		out.append("Turns to shoot outside its %d deg arc" % int(round(UT.stat(ty, "arc") * 720.0 / 1024.0)))
		out.append("Cannot shoot while moving; sets up in %d s, packs up in %d s" % [
			UT.stat(ty, "deploy") / 10, UT.stat(ty, "deploy") / 20])
		out.append("Slow: %.1f m/s, never runs" % (UT.stat(ty, "walk") * TICKS_PER_SEC / M))
		out.append("Crews re-man engines; silent below %d crew" % UT.stat(ty, "crew_min"))
		out.append("Wrecked by enemies next to it")
		out.append("Frightens the unit it hits (a few seconds)")
		out.append("Fire at will / hold fire")
		out.append("Refill: %d more shots per engine in the baggage, ~%d s for a full load; cannot move or shoot meanwhile" % [
			UT.stat(ty, "m_reserve"), UT.stat(ty, "m_ammo") * UT.stat(ty, "m_refill") / 10 + BattleSim.REFILL_FULL / 10])
		out.append("Crews weak in melee, break easily")
		return out
	if UT.stat(ty, "m_ammo") > 0:
		out.append("Shoots over friends" if UT.stat(ty, "m_arc") != 0 else "Thrown flat: needs a clear line")
		out.append("Fire at will / hold fire")
		out.append("Leads moving targets; keeps its chosen target")
		out.append("Skirmish mode" + (" (on by default)" if UT.stat(ty, "skirm") != 0 else ""))
		out.append("Weak in melee")
	return out


static func _class_name(c: int) -> String:
	match c:
		UT.CLS_PIKE:
			return "pike infantry"
		UT.CLS_MISSILE:
			return "missile infantry"
		UT.CLS_CAV:
			return "cavalry"
		UT.CLS_ART:
			return "artillery"
	return "infantry"


func _section(rows: Array, title: String, defs: Array, ty: int) -> void:
	rows.append({"title": title})
	for d in defs:
		rows.append({"label": d[0], "key": d[1], "kind": d[2], "ty": ty})


func _add_row(r: Dictionary) -> void:
	if r.has("title"):
		_grid.add_child(_label(r["title"], 16, Color(1, 0.9, 0.6)))
		_grid.add_child(Control.new())
		_grid.add_child(Control.new())
		return
	var ty: int = r["ty"]
	var key: String = r["key"]
	var kind: String = r["kind"]
	var v := value(ty, key)
	var best := 0
	var lowest := 0
	for t in UT.count():
		var x := value(t, key)
		best = maxi(best, x)
		if x > 0 and (lowest == 0 or x < lowest):
			lowest = x
	var frac := 0.0
	if kind == "s_low" or kind == "s":
		frac = float(lowest) / v if v > 0 else 0.0
	elif best > 0:
		frac = float(v) / best
	_grid.add_child(_label(r["label"], 15, COL_DIM))
	var val := _label(format_value(v, kind), 15, Color.WHITE)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.custom_minimum_size.x = 84
	_grid.add_child(val)
	_grid.add_child(_Bar.new(frac, side_color))


## A stat of type ty, or a derived value ("_engines": engines in a unit of
## the default size).
static func value(ty: int, key: String) -> int:
	if key == "_engines":
		var crew := UT.stat(ty, "crew")
		return UT.size_of(ty) / crew if crew > 0 else 0
	return UT.stat(ty, key)


## Human units for a raw stat value.
static func format_value(v: int, kind: String) -> String:
	match kind:
		"s":
			return "%.0f s" % (v / TICKS_PER_SEC)
		"deg":
			return "%d deg" % int(round(v * 720.0 / 1024.0))
		"degps":
			return "%.0f deg/s" % (v * 360.0 * TICKS_PER_SEC / 1024.0)
		"pct":
			return "%d%%" % v
		"m":
			return ("%.1f m" % (v / M)) if v < 20 * M else ("%d m" % int(round(v / M)))
		"mps":
			return "%.1f m/s" % (v * TICKS_PER_SEC / M)
		"s_low":
			return "1 per %.1f s" % (v / TICKS_PER_SEC)
	return str(v)


func _label(text: String, font_px: int, col: Color, wrapped: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", col)
	if wrapped:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _chip(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.12)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(_label(text, 14, Color.WHITE))
	return p


## Horizontal bar: fraction of the best value among all unit types.
class _Bar extends Control:
	var frac := 0.0
	var col := Color.WHITE

	func _init(p_frac: float, p_col: Color) -> void:
		frac = clampf(p_frac, 0.0, 1.0)
		col = p_col
		custom_minimum_size = Vector2(BAR_W, 20)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var h := 10.0
		var y := (size.y - h) * 0.5
		draw_rect(Rect2(0, y, size.x, h), Color(1, 1, 1, 0.12))
		if frac > 0.0:
			draw_rect(Rect2(0, y, maxf(size.x * frac, 2.0), h), col)
