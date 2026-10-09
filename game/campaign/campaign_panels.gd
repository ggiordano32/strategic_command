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
const UiIcons := preload("res://game/ui_icons.gd")
const Saves := preload("res://game/campaign/saves.gd")
const CityPreview := preload("res://game/campaign/city_preview.gd")
const MapGen := preload("res://sim/mapgen.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const DragReorder := preload("res://game/drag_reorder.gd")
const BattleScreen := preload("res://game/campaign/battle_screen.gd")

var s  # the campaign screen
var _split_sel: Dictionary = {}  # army id -> Array of selected unit indices
## The exchange panel's pending trade: {a (this army), b (the other), out
## [indices of a's units going to b], back [indices of b's coming to a]}.
var _xc: Dictionary = {}


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
	var b := Kit.icon_button("Close", "close", func(): s.close_side(), 70)
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
	var rd_f := CRules.raider(ps, r)
	if rd_f >= 0:
		var rtxt := "Raided by %s: half income." % CData.faction_name(rd_f)
		if CState.grid_on(ps):
			rtxt = "Raided by %s: it takes %d%% of the income." % [CData.faction_name(rd_f), CData.RAID_PCT]
		var rl := Kit.label(rtxt, Kit.FONT, Kit.COL_BAD if o == f else Kit.COL_GOLD, true)
		rl.name = "raided_note"
		Kit.label_icon(rl, "raid")
		box.add_child(rl)
	if not CState.siege_at(ps, r).is_empty():
		if CState.grid_on(ps):
			_siege_section6(box, r)
		else:
			_siege_section(box, r)
	elif f >= 0 and CState.at_war(ps, f, o) and CState.battle_at(ps, r).is_empty():
		if CState.moves_on(ps) and not CState.grid_on(ps) and not CRules._mine_here(ps, f, r).is_empty():
			_raid_section(box, r)
		_attack_section(box, r)
	var gp := CRules.growth_per_turn(ps, r)
	var grow := "Growth %d/%d to %s (+%d a turn)" % [int(rs["growth"]), int(CData.GROWTH_TO[lvl + 1]), CData.LEVEL_NAMES[lvl + 1].to_lower(), gp] if lvl < CData.CITY else "Full-grown city"
	box.add_child(Kit.label("Income %d a turn.  %s." % [CRules.region_income(ps, r), grow], Kit.FONT_SMALL, Color.WHITE, true))
	var b := CState.battle_at(ps, r)
	if not b.is_empty():
		box.add_child(Kit.label("A battle is pending here.", Kit.FONT, Kit.COL_BAD))
	box.add_child(Kit.label(CBattle.city_caption(ps, r) + ".", Kit.FONT_SMALL, Kit.COL_DIM, true))
	var vb := Kit.icon_button("View battle map", "view_map", show_city_map.bind(r))
	vb.name = "view_battle_map"
	box.add_child(vb)
	# Armies here.
	var here := CState.armies_in(ps, r)
	if CState.grid_on(ps):
		here = []
		for a in ps["armies"]:
			if CGrid.cheb(CState.cell(a), CGrid.site(r)) <= 1:
				here.append(a)
	if not here.is_empty():
		box.add_child(Kit.section("Armies" if not CState.grid_on(ps) else "Armies at %s" % rd["city"]))
		for a in here:
			var bt := Kit.button("%s army: %d units, %d men" % [CData.FACTIONS[int(a["f"])]["adj"], CState.unit_count(a), CState.men(a)],
				s.select_army.bind(int(a["id"])))
			bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
			bt.add_theme_color_override("font_color", _fc(int(a["f"])).lightened(0.5))
			Kit.set_icon(bt, "men", _fc(int(a["f"])).lightened(0.5))
			box.add_child(bt)
	var grid := CState.grid_on(ps)
	if mine:
		if grid:
			_raise_section(box, r)  # version 6: recruiting is in the army card
		else:
			_recruit(box, r)
		_buildings(box, r)
		if grid:
			_trains(box, r)
	_gift_section(box, r)
	# Garrison: what the settlement provides (by level and walls).
	var gar := CRules.garrison(ps, r)
	var gs := Kit.section("Garrison (%d%% strength, walls %d)" % [int(rs["gar"]), CState.walls(ps, r)], "walls")
	gs.name = "garrison_section"
	box.add_child(gs)
	if grid:
		box.add_child(Kit.label("Provided by the %s and its walls; it defends the city and recovers %d%% a turn." % [
			CData.LEVEL_NAMES[lvl].to_lower(), CData.GARRISON_REGEN], Kit.FONT_SMALL, Kit.COL_DIM, true))
	for g in gar:
		var gty := UT.index_of(str(g["t"]))
		var row := Kit.UnitRow.new(gty, int(g["n"]), _fc(o))
		row.full = int(g["full"])
		if grid:
			row.pressed.connect(func(): s.open_unit_page(gty, Callable(), ""))
		box.add_child(row)


# ------------------------------------------------- gifts between players ---

## A number-only field (digits; empty reads as 0).
func _num_field(placeholder: String, nm: String, w: float = 90.0) -> LineEdit:
	var le := Kit.text_field(placeholder, "", w)
	le.name = nm
	le.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	le.text_changed.connect(func(t: String):
		var d := ""
		for ch in t:
			if ch >= "0" and ch <= "9":
				d += ch
		d = d.substr(0, 7)
		if d != t:
			le.text = d
			le.caret_column = d.length())
	return le


func _num(le: LineEdit) -> int:
	return int(le.text) if le.text.is_valid_int() else 0


## Alive allied human players faction f may trade gifts with.
func _gift_partners(ps: Dictionary, f: int) -> Array:
	var out: Array = []
	for g in ps["humans"]:
		if CRules.gift_partner_check(ps, f, int(g)) == "":
			out.append(int(g))
	return out


func _gift_order_text(o: Dictionary) -> String:
	var price := int(o.get("price", 0))
	var city := str(CData.REGIONS[int(o["r"])]["city"])
	if str(o["t"]) == "buy_region":
		return "Planned: offer %d for %s" % [price, city]
	return "Planned: %s to %s%s" % [city, _fname(int(o["to"])), " for %d" % price if price > 0 else " as a gift"]


## A planned gift / offer row with Cancel (the order is taken out; Undo
## brings it back).
func _planned_gift_row(box: Container, o: Dictionary, nm: String, after: Callable) -> void:
	var h := Kit.hbox(6)
	h.add_child(Kit.label(_gift_order_text(o) if str(o["t"]) != "gift_money" else "Planned: %d to %s" % [int(o["amount"]), _fname(int(o["to"]))],
		Kit.FONT_SMALL, Kit.COL_GOOD, true))
	var key := str(o)
	var cb := Kit.icon_button("Cancel", "cancel", func():
		s.remove_orders(func(x): return str(x) == key)
		after.call(), 80, Kit.FONT_SMALL)
	cb.name = nm
	h.add_child(cb)
	box.add_child(h)


## Region panel: give this city to the allied player (free, or for a price:
## an offer they accept next turn); the planned gift with Cancel.
func _gift_section(box: VBoxContainer, r: int) -> void:
	var ps: Dictionary = s.ps
	var f: int = s.f
	if f < 0:
		return
	var planned: Array = []
	for o in s.orders:
		if str(o["t"]) == "gift_region" and int(o.get("r", -1)) == r:
			planned.append(o)
	var partners := _gift_partners(ps, f)
	var mine := CState.owner(ps, r) == f
	if planned.is_empty() and (not mine or partners.is_empty()):
		return
	box.add_child(Kit.section("Gift to an ally", "gift"))
	for o in planned:
		_planned_gift_row(box, o, "gift_cancel", func(): pass)
	if not mine or not planned.is_empty():
		return
	box.add_child(Kit.label("The city passes with its garrison and buildings when the turn is resolved; with a price it is an offer the ally accepts next turn, paying then.",
		Kit.FONT_SMALL, Kit.COL_DIM, true))
	for g in partners:
		var why := CRules.gift_region_check(ps, f, r, g, 0)
		var h := Kit.hbox(6)
		var pf := _num_field("price", "gift_price_%s" % CData.FACTIONS[g]["key"])
		h.add_child(pf)
		var b := Kit.icon_button("Gift to %s" % _fname(g), "gift", func():
			s.add_order({"t": "gift_region", "r": r, "to": g, "price": _num(pf)}), 0)
		b.name = "gift_to_%s" % CData.FACTIONS[g]["key"]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # the row spans the panel
		b.disabled = why != ""
		h.add_child(b)
		box.add_child(h)
		if why != "":
			box.add_child(Kit.label("Cannot give it now: %s." % why, Kit.FONT_SMALL, Kit.COL_BAD, true))


## How faction f planned to answer city offer id: 1 accept, 0 decline, -1 not.
func _offer_answer(id: int) -> int:
	for o in s.orders:
		if int(o.get("id", -1)) == id:
			if str(o["t"]) == "accept_offer":
				return 1
			if str(o["t"]) == "decline_offer":
				return 0
	return -1


## Diplomacy, under the allied player g: their offers to us (Accept /
## Decline), our planned gifts and offers (Cancel), Offer money, Offer to
## buy one of their cities.
func _ally_deals(outer: VBoxContainer, g: int) -> void:
	# Indented under the ally's row (past its colour swatch), so the deals
	# read as that faction's.
	var mc := MarginContainer.new()
	mc.name = "deals_" + str(CData.FACTIONS[g]["key"])
	mc.add_theme_constant_override("margin_left", 24)
	outer.add_child(mc)
	var box := Kit.vbox(6)
	mc.add_child(box)
	var ps: Dictionary = s.ps
	var f: int = s.f
	var gk := str(CData.FACTIONS[g]["key"])
	var redraw := func(): show_diplomacy(g)
	for p in s.st["proposals"]:
		if not p.has("kind") or int(p["to"]) != f or int(p["from"]) != g:
			continue
		var pid := int(p["id"])
		var city := str(CData.REGIONS[int(p["r"])]["city"])
		var txt := "%s offers you %s for %d." % [_fname(g), city, int(p["price"])] if str(p["kind"]) == "offer_city" \
			else "%s offers %d for your %s." % [_fname(g), int(p["price"]), city]
		var h := Kit.hbox(6)
		h.add_child(Kit.label(txt, Kit.FONT, Kit.COL_GOLD, true))
		var ans := _offer_answer(pid)
		if ans < 0:
			var ab := Kit.icon_button("Accept", "accept", func():
				s.add_order({"t": "accept_offer", "id": pid})
				show_diplomacy(g), 80)
			ab.name = "offer_accept_%d" % pid
			h.add_child(ab)
			var db := Kit.icon_button("Decline", "decline", func():
				s.add_order({"t": "decline_offer", "id": pid})
				show_diplomacy(g), 80)
			db.name = "offer_decline_%d" % pid
			h.add_child(db)
		else:
			h.add_child(Kit.label("accepted" if ans == 1 else "declined", Kit.FONT_SMALL, Kit.COL_DIM))
			var cb := Kit.icon_button("Cancel", "cancel", func():
				s.remove_orders(func(o): return int(o.get("id", -1)) == pid and str(o["t"]) in ["accept_offer", "decline_offer"])
				show_diplomacy(g), 80, Kit.FONT_SMALL)
			cb.name = "offer_undo_%d" % pid
			h.add_child(cb)
		box.add_child(h)
	for o in s.orders:
		var t := str(o["t"])
		if ((t == "gift_region" or t == "gift_money") and int(o.get("to", -1)) == g) \
				or (t == "buy_region" and CState.owner(s.st, int(o.get("r", -1))) == g):
			_planned_gift_row(box, o, "deal_cancel", redraw)
	# Offer money.
	var mh := Kit.hbox(6)
	var mf := _num_field("amount", "money_amount_" + gk)
	mh.add_child(mf)
	var mb := Kit.icon_button("Offer money", "coin", func():
		if s.add_order({"t": "gift_money", "to": g, "amount": _num(mf)}) == "":
			show_diplomacy(g), 0)
	mb.name = "offer_money_" + gk
	mh.add_child(mb)
	box.add_child(mh)
	# Offer to buy one of their cities (those that may change hands now:
	# no army of theirs in it, not besieged, not their last).
	var theirs: Array = []
	for r in CState.regions_of(ps, g):
		if CRules.city_deal_check(ps, g, f, r, 0) == "":
			theirs.append(r)
	if theirs.is_empty():
		box.add_child(Kit.label("None of %s's cities can change hands now (an army of theirs in it, a siege or a battle there, or their last city)." % _fname(g),
			Kit.FONT_SMALL, Kit.COL_DIM, true))
		return
	var bh := Kit.flow(6)
	var pick := OptionButton.new()
	pick.name = "buy_city_" + gk
	pick.custom_minimum_size = Vector2(150, Kit.BTN_H)
	for r in theirs:
		pick.add_item(str(CData.REGIONS[r]["city"]), r)
	bh.add_child(pick)
	var pf := _num_field("price", "buy_price_" + gk)
	bh.add_child(pf)
	var bb := Kit.icon_button("Offer to buy", "buy", func():
		if pick.selected < 0:
			return
		if s.add_order({"t": "buy_region", "r": pick.get_item_id(pick.selected), "price": _num(pf)}) == "":
			show_diplomacy(g), 0)
	bb.name = "offer_buy_" + gk
	bh.add_child(bb)
	box.add_child(bh)


func _gift_text(e: Dictionary, f: int) -> String:
	var city := str(CData.REGIONS[int(e["r"])]["city"]) if e.has("r") else ""
	var a := int(e["f"]) if e.has("f") else int(e.get("from", -1))
	var b := int(e["to"])
	if a != f and b != f:
		return ""
	var who := func(x: int) -> String: return "you" if x == f else _fname(x)
	match str(e["k"]):
		"gift_money":
			return "%s gave %s %d." % ["You" if a == f else _fname(a), who.call(b), int(e["amount"])]
		"gift_region":
			var price := int(e["price"])
			return "%s handed %s to %s%s." % ["You" if a == f else _fname(a), city, who.call(b), " for %d" % price if price > 0 else " as a gift"]
		"city_offer":
			var price2 := int(e["price"])
			if str(e["kind"]) == "offer_city":
				return "%s offered %s to %s for %d (answer in Diplomacy next turn)." % ["You" if a == f else _fname(a), city, who.call(b), price2]
			return "%s offered %d for %s (answer in Diplomacy next turn)." % ["You" if a == f else _fname(a), price2, city]
		"city_declined":
			return "%s declined the offer about %s." % ["You" if a == f else _fname(a), city]
		"city_refused":
			return "The deal about %s fell through: %s." % [city, str(e["why"])]
	return ""


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
	if CState.grid_on(s.ps):
		for a in CState.armies_of(s.ps, s.f):
			var p6: Dictionary = s.plan6(int(a["id"]))
			if not p6.is_empty() and int(p6["cell"]) == CGrid.site(r):
				out.append(a)
		return out
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
	var eq_t := CBattle.equipment_text(ps, r)
	if eq_t != "":
		var eql := Kit.label(eq_t, Kit.FONT_SMALL, Color.WHITE, true)
		eql.name = "siege_equipment"
		Kit.label_icon(eql, "ladder")
		v.add_child(eql)
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
		var h := Kit.flow(8)
		var ab := Kit.icon_button("Assault", "assault", func(): s.add_order({"t": "assault", "r": r}), 110)
		ab.name = "siege_assault"
		ab.disabled = ordered or CRules.can_assault(ps, f, r) != ""
		h.add_child(ab)
		var mb := Kit.icon_button("Maintain", "siege", func(): s.remove_orders(func(x): return str(x["t"]) == "assault" and int(x.get("r", -1)) == r), 110)
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
		var sb := Kit.icon_button("Cancel sally" if ordered2 else "Sally", "cancel" if ordered2 else "sally", func():
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


## Version 5: the odds of army `army` (with the armies marching with it to
## r) against the enemy armies in the field in region r, which stop it
## there: {od, by (their faction)}; {} if none stand there.
func field_odds(army: int, r: int) -> Dictionary:
	var ps: Dictionary = s.ps
	var a := CState.army(ps, army)
	if a.is_empty() or not CState.moves_on(ps):
		return {}
	var foes := CRules.hostile_field(ps, r, int(a["f"]))
	if foes.is_empty():
		return {}
	var ours := planned_into(r)
	if not ours.has(a):
		ours.append(a)
	return {"od": CBattle.odds(ps, ours, foes, r, false, -1), "by": int(foes[0]["f"])}


## Region panel of an enemy region where our armies stand without a siege
## (version 5, raiding): lay siege or storm the settlement from here.
func _raid_section(box: VBoxContainer, r: int) -> void:
	var ps: Dictionary = s.ps
	var f: int = s.f
	var o := CState.owner(ps, r)
	var mine := CRules._mine_here(ps, f, r)
	var p := Kit.panel(Color(0.3, 0.2, 0.08, 0.5), 8)
	p.name = "raid_panel"
	var v := Kit.vbox(6)
	p.add_child(v)
	box.add_child(p)
	var sieging := _has_order("siege", r)
	var storming := _has_order("assault", r)
	var what := "Your arm%s here raid%s %s: half its income is lost to %s. %s is not attacked unless you order it." % [
		"y" if mine.size() == 1 else "ies", "s" if mine.size() == 1 else "", CData.REGIONS[r]["name"], CData.faction_name(o), CData.REGIONS[r]["city"]]
	if sieging:
		what = "Orders: lay siege to %s at the end of the turn." % CData.REGIONS[r]["city"]
	elif storming:
		what = "Orders: storm %s at the end of the turn." % CData.REGIONS[r]["city"]
	v.add_child(Kit.label(what, Kit.FONT, Kit.COL_GOLD, true))
	var foes := CRules.hostile_field(ps, r, f)
	if not foes.is_empty():
		var fo := CBattle.odds(ps, mine, foes, r, false, -1)
		v.add_child(Kit.odds_view(fo, 0, [_fname(f), _fname(int(foes[0]["f"]))], [_fc(f), _fc(int(foes[0]["f"]))],
			"Their army stands in the field here: a siege or an assault starts with a field battle:"))
	var h := Kit.hbox(8)
	var sb := Kit.icon_button("Cancel siege" if sieging else "Lay siege", "cancel" if sieging else "siege", func():
		if sieging:
			s.remove_orders(func(x): return str(x["t"]) == "siege" and int(x.get("r", -1)) == r)
		else:
			s.remove_orders(func(x): return str(x["t"]) == "assault" and int(x.get("r", -1)) == r)
			s.add_order({"t": "siege", "r": r}), 130)
	sb.name = "raid_siege"
	sb.disabled = not sieging and CRules.can_siege(ps, f, r) != ""
	h.add_child(sb)
	var ab := Kit.icon_button("Cancel assault" if storming else "Assault", "cancel" if storming else "assault", func():
		if storming:
			s.remove_orders(func(x): return str(x["t"]) == "assault" and int(x.get("r", -1)) == r)
		else:
			s.remove_orders(func(x): return str(x["t"]) == "siege" and int(x.get("r", -1)) == r)
			s.add_order({"t": "assault", "r": r}), 130)
	ab.name = "raid_assault"
	ab.disabled = not storming and CRules.can_assault(ps, f, r) != ""
	h.add_child(ab)
	v.add_child(h)
	var od := CBattle.odds(ps, mine, _defs_of(ps, r), r, true)
	v.add_child(Kit.odds_view(od, 0, [_fname(f), _fname(o)], [_fc(f), _fc(o)], "If you storm it now (garrison, walls and the armies inside):"))


static func _defs_of(ps: Dictionary, r: int) -> Array:
	var o := CState.owner(ps, r)
	var out: Array = []
	if o < 0:
		return out
	for a in CState.armies_in(ps, r):
		if CState.friendly(ps, int(a["f"]), o):
			out.append(a)
	return out


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
	if CState.grid_on(ps):
		assault = 0
		for a in into:
			if int(s.move_mode(int(a["id"]))) == CData.MODE_ASSAULT:
				assault += 1
	var verb := "storm it at once" if assault > 0 or not CState.sieges_on(ps) else "lay siege (no battle this turn)"
	if CState.grid_on(ps):
		verb = "storm it on arrival" if assault > 0 else "lay siege on arrival"
	elif CState.moves_on(ps):
		var marching := 0
		for m in s.moves:
			if int(m[1]) == r and int(m[2]) == CData.MODE_MARCH:
				marching += 1
		verb = "storm it on arrival" if assault > 0 else ("march in and raid it" if marching == into.size() else "lay siege on arrival")
	var what := "Planned: %d arm%s %s." % [into.size(), "y" if into.size() == 1 else "ies", verb]
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
	box.add_child(Kit.section("Buildings (%d of %d slots)" % [(rs["slots"] as Array).size(), CState.slot_count(r, int(rs["level"]))], "build"))
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
		var l := Kit.icon_label(name, str(ch["key"]), Kit.FONT, Color.WHITE if cur > 0 else Kit.COL_DIM)
		l.custom_minimum_size.x = 104 + UiIcons.px_for(Kit.FONT) + Kit.ICON_GAP
		l.tooltip_text = str(ch["desc"])
		h.add_child(l)
		if not bld.is_empty() and int(bld[0]) == c:
			var t := Kit.label("-> %d: %d turn%s left" % [int(bld[1]), int(bld[2]), "" if int(bld[2]) == 1 else "s"], Kit.FONT_SMALL, Kit.COL_GOOD, true)
			h.add_child(t)
			if planned == c:
				var cb := Kit.icon_button("Cancel", "cancel", func(): s.remove_orders(func(o): return str(o["t"]) == "build" and int(o["r"]) == r), 70)
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
				var bb := Kit.icon_button("Build %d" % int(info["level"]) if cur == 0 else "Upgrade", "build" if cur == 0 else "upgrade", func(): s.add_order({"t": "build", "r": r, "chain": c}), 84)
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
	box.add_child(Kit.section("Recruit (%d of %d this turn; ready next turn)" % [q.size(), cap], "recruit"))
	for k in q.size():
		var ty := UT.index_of(str(q[k]))
		var row := Kit.UnitRow.new(ty, -1, _fc(f), "planned")
		row.sub_text = "arrives next turn"
		var h := Kit.hbox(4)
		h.add_child(row)
		var key := str(q[k])
		h.add_child(Kit.icon_button("", "close", func(): _cancel_recruit(r, key), 44))
		box.add_child(h)
	for o in best_options(ps, f, r):
		var ty := UT.index_of(str(o["t"]))
		var why := str(o["why"])
		var row := Kit.UnitRow.new(ty, -1, _fc(f), str(o["price"]))
		row.sub_text = "Tier %d  -  upkeep %d" % [int(o["tier"]), CState.upkeep_of(ty)] if o["ok"] else why
		if o["ok"] and str(o.get("ak", "")) != "":
			row.sub_text += "  -  + " + UT.ammo_text(UT.ammo_index(str(o["ak"])), "name").to_lower()
		var key := str(o["t"])
		row.name = "recruit_row_" + key
		if o["lower"]:
			row.modulate = Color(1, 1, 1, 0.82)
		var open_page := func(): s.open_unit_page(ty,
			(func(): s.add_order({"t": "recruit", "r": r, "unit": key})) if o["ok"] else Callable(),
			"Recruit (%d)" % int(o["price"]))
		row.pressed.connect(open_page)
		row.long_pressed.connect(open_page)
		var h := Kit.hbox(4)
		h.add_child(row)
		var add := Kit.icon_button("", "plus", func(): s.add_order({"t": "recruit", "r": r, "unit": key}), 44)
		add.name = "recruit_" + key
		add.disabled = not o["ok"]
		h.add_child(add)
		box.add_child(h)


## The recruit list's rows: every tier the buildings unlock, per line, best
## tier first (a "lower" key marks the tiers under the best one, shown a
## little dimmer); locked higher tiers are left to the unit book.
static func best_options(ps: Dictionary, f: int, r: int) -> Array:
	var out: Array = []
	var shown := {}
	for o in CRules.recruit_options(ps, f, r):
		var line := str(o["line"])
		if str(o["why"]).begins_with("needs") and int(o["tier"]) > 1:
			continue
		var e: Dictionary = o.duplicate()
		e["lower"] = shown.has(line)
		shown[line] = 1
		out.append(e)
	return out


## Version 6 region panel: this turn's recruit slots, the planned new army
## (with X) and "Raise new army" (the picker).
func _raise_section(box: VBoxContainer, r: int) -> void:
	var ps: Dictionary = s.ps
	var f: int = s.f
	var rs: Dictionary = ps["regions"][r]
	var cap := int(CData.RECRUITS_PER_TURN[int(rs["level"])])
	var used := (rs["queue"] as Array).size()
	var sec := Kit.section("Recruits (%d of %d here this turn)" % [used, cap], "recruit")
	sec.name = "recruit_slots"
	box.add_child(sec)
	var raising := _raise_orders(r)
	if not raising.is_empty():
		var names: Array[String] = []
		for o in raising:
			names.append(str(UT.TYPES[UT.index_of(str(o["unit"]))]["name"]))
		var h := Kit.hbox(6)
		var l := Kit.label("Raising a new army: %d unit%s (%s), inside the walls at the end of the turn." % [raising.size(),
			"" if raising.size() == 1 else "s", ", ".join(names)], Kit.FONT, Kit.COL_GOOD, true)
		l.name = "raise_planned"
		h.add_child(l)
		var x := Kit.icon_button("", "close", func(): s.remove_orders(func(o): return _is_raise(o, r)), 44)
		x.name = "raise_cancel"
		h.add_child(x)
		box.add_child(h)
	# Old-form recruits planned before this panel changed (a saved plan):
	# shown with X so they can still be taken back.
	for o in s.orders:
		if str(o["t"]) == "recruit" and int(o.get("r", -1)) == r and not o.has("army") and int(o.get("new", 0)) == 0:
			var oty := UT.index_of(str(o["unit"]))
			var orow := Kit.UnitRow.new(oty, -1, _fc(f), "planned")
			orow.sub_text = "arrives at the end of the turn"
			var oh := Kit.hbox(4)
			oh.add_child(orow)
			var ox := Kit.icon_button("", "close", func(): s.remove_orders(func(x): return is_same(x, o)), 44)
			oh.add_child(ox)
			box.add_child(oh)
	var why := raise_why(ps, f, r)
	var b := Kit.icon_button("Raise new army" if raising.is_empty() else "Add to the new army", "raise", func(): show_raise(r), 0)
	b.name = "raise_army"
	b.disabled = why != ""
	box.add_child(b)
	var hint := "To recruit into an army, select an army standing at %s: its card has the recruit list. Recruits arrive at the end of the turn; an army taking recruits cannot march this turn." % CData.REGIONS[r]["city"]
	if why != "":
		hint = "Cannot raise an army now: %s. " % why + hint
	box.add_child(Kit.label(hint, Kit.FONT_SMALL, Kit.COL_DIM, true))


func _is_raise(o: Dictionary, r: int) -> bool:
	return str(o["t"]) == "recruit" and int(o.get("r", -1)) == r and int(o.get("new", 0)) != 0


## The planned "new army" recruit orders of region r.
func _raise_orders(r: int) -> Array:
	var out: Array = []
	for o in s.orders:
		if _is_raise(o, r):
			out.append(o)
	return out


## "" if faction f can raise (or add to) a new army in region r now, else
## why not (the region's: besieged, recruitment full, money...).
static func raise_why(ps: Dictionary, f: int, r: int) -> String:
	var first := ""
	for o in CRules.recruit_options(ps, f, r):
		if o["ok"]:
			return ""
		if first == "" or first.begins_with("needs") or first == "not in your roster":
			first = str(o["why"])
	return first if first != "" else "nothing to recruit"


## The units the city trains (what its buildings unlock): the best tier of
## each line with the building it needs; a tap opens the unit book.
func _trains(box: VBoxContainer, r: int) -> void:
	var ps: Dictionary = s.ps
	var f: int = s.f
	var sec := Kit.section("Trains here", "barracks")
	sec.name = "trains_section"
	box.add_child(sec)
	var ro: Dictionary = CData.roster(f)
	var any := false
	for line in CData.LINE_ORDER:
		if not ro.has(line):
			continue
		var tiers: Array = ro[line]
		var best := ""
		var next := ""
		for k in tiers.size():
			var key := str(tiers[k])
			if key == "":
				continue
			var nd := CRules.needs(key)
			if CState.building(ps, r, int(nd[0])) >= int(nd[1]):
				best = key
			elif next == "":
				next = key
		if best == "":
			continue
		any = true
		var ty := UT.index_of(best)
		var nd2 := CRules.needs(best)
		var row := Kit.UnitRow.new(ty, -1, _fc(f), str(UT.price_of(ty)))
		row.name = "trains_" + best
		var sub := "Tier %d (%s %d)" % [UT.tier_of(ty), CData.CHAINS[int(nd2[0])]["name"], int(nd2[1])]
		if next != "":
			var nn := CRules.needs(next)
			sub += "; tier %d needs %s %d" % [UT.tier_of(UT.index_of(next)), CData.CHAINS[int(nn[0])]["name"], int(nn[1])]
		row.sub_text = sub
		row.pressed.connect(func(): s.open_unit_page(ty, Callable(), ""))
		box.add_child(row)
	if not any:
		box.add_child(Kit.label("No military buildings yet: build barracks, a range or stables to train units.", Kit.FONT_SMALL, Kit.COL_DIM, true))


## The "Raise new army" picker: {r, picks {unit key: count}} while open.
var _raise: Dictionary = {}


## Pick the units of a new army raised in region r this turn (up to the
## free slots and the treasury); Confirm adds one recruit order with
## "new": 1 per unit (one Undo step).
func show_raise(r: int) -> void:
	var ps: Dictionary = s.ps
	var f: int = s.f
	if int(_raise.get("r", -1)) != r:
		_raise = {"r": r, "picks": {}}
	var picks: Dictionary = _raise["picks"]
	var rs: Dictionary = ps["regions"][r]
	var cap := int(CData.RECRUITS_PER_TURN[int(rs["level"])])
	var free := cap - (rs["queue"] as Array).size()
	var money := int(ps["factions"][f]["treasury"])
	var n := 0
	var cost := 0
	for o in best_options(ps, f, r):
		var key := str(o["t"])
		n += int(picks.get(key, 0))
		cost += int(picks.get(key, 0)) * int(o["price"])
	var v := Kit.vbox(6)
	v.name = "raise_panel"
	v.add_child(Kit.label("Choose the units of a new army: up to %d this turn (%d of %d recruit slots used at %s). It forms inside the walls at the end of the turn." % [
		free, cap - free, cap, CData.REGIONS[r]["city"]], Kit.FONT_SMALL, Kit.COL_DIM, true))
	for o in best_options(ps, f, r):
		var key := str(o["t"])
		var ty := UT.index_of(key)
		var price := int(o["price"])
		var cnt := int(picks.get(key, 0))
		var ok: bool = o["ok"] or (cnt > 0)
		var row := Kit.UnitRow.new(ty, -1, _fc(f), str(price))
		row.name = "raise_row_" + key
		if o["lower"]:
			row.modulate = Color(1, 1, 1, 0.82)
		row.selected = cnt > 0
		row.sub_text = "Tier %d  -  upkeep %d" % [int(o["tier"]), CState.upkeep_of(ty)] if ok else str(o["why"])
		if ok and str(o.get("ak", "")) != "":
			row.sub_text += "  -  + " + UT.ammo_text(UT.ammo_index(str(o["ak"])), "name").to_lower()
		row.pressed.connect(func(): s.open_unit_page(ty, Callable(), ""))
		var h := Kit.hbox(4)
		h.add_child(row)
		var minus := Kit.icon_button("", "minus", func(): _raise_pick(key, -1), 44)
		minus.name = "raise_minus_" + key
		minus.disabled = cnt == 0
		h.add_child(minus)
		var cl := Kit.label(str(cnt), Kit.FONT, Color.WHITE)
		cl.name = "raise_count_" + key
		cl.custom_minimum_size.x = 22
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_child(cl)
		var plus := Kit.icon_button("", "plus", func(): _raise_pick(key, 1), 44)
		plus.name = "raise_plus_" + key
		plus.disabled = not ok or n >= free or cost + price > money
		h.add_child(plus)
		v.add_child(h)
	var tl := Kit.label("%d unit%s, %s (treasury %s)." % [n, "" if n == 1 else "s", Kit.money(cost), Kit.money(money)],
		Kit.FONT, Kit.COL_GOLD if n > 0 else Kit.COL_DIM, true)
	tl.name = "raise_total"
	v.add_child(tl)
	s.show_dialog("Raise new army at %s" % CData.REGIONS[r]["city"], v,
		[["Cancel", func():
			_raise = {}
			s.close_dialog()], ["Raise army (%d)" % n, func(): _raise_confirm(r)]], 640)
	var btns: Array = s.dialog_buttons.get_children()
	if btns.size() >= 2:
		(btns[0] as Button).name = "raise_cancel_dialog"
		var okb := btns[btns.size() - 1] as Button
		okb.name = "raise_confirm"
		okb.disabled = n == 0


func _raise_pick(key: String, d: int) -> void:
	if _raise.is_empty():
		return
	var picks: Dictionary = _raise["picks"]
	picks[key] = maxi(int(picks.get(key, 0)) + d, 0)
	if int(picks[key]) == 0:
		picks.erase(key)
	show_raise(int(_raise["r"]))


func _raise_confirm(r: int) -> void:
	if _raise.is_empty():
		return
	var picks: Dictionary = _raise["picks"]
	var list: Array = []
	# Lines in display order (a Dictionary's order is the taps').
	for o in best_options(s.ps, s.f, r):
		var key := str(o["t"])
		for i in int(picks.get(key, 0)):
			list.append({"t": "recruit", "r": r, "unit": key, "new": 1})
	_raise = {}
	s.close_dialog()
	if list.is_empty():
		return
	if s.add_orders(list) == "":
		s._t("campaign_input", {"what": "raise_army", "n": list.size()})
	s.select_region(r)


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
	var arriving: Array = _army_recruits(id) if mine else []
	var cnt_l := Kit.label("%d of %d units%s, %d men, upkeep %d" % [CState.unit_count(a), CData.ARMY_MAX,
		" (+%d arriving)" % arriving.size() if not arriving.is_empty() else "", CState.men(a), up], Kit.FONT_SMALL, Kit.COL_DIM, true)
	cnt_l.name = "army_count"
	Kit.label_icon(cnt_l, "men")
	box.add_child(cnt_l)
	if mine and CState.grid_on(ps):
		_together_row(box, a)
		_army_orders6(box, a)
	elif mine:
		var mv: int = s.planned_move(id)
		var role := CRules.siege_role(ps, a)
		if int(a["busy"]) != 0:
			box.add_child(Kit.label("In a battle.", Kit.FONT, Kit.COL_BAD))
		elif mv >= 0:
			var h := Kit.vbox(4)
			var kind: String = s.move_kind(id)
			var verb: String = {"siege": "Lays siege to", "join": "Joins the siege of", "assault": "Assaults", "relief": "Relieves",
				"move": "Moves to", "raid": "Marches into"}.get(kind, "Moves to")
			var when := ""
			if CState.moves_on(ps):
				var rt: Dictionary = s.route(id)
				var turns: Array = rt.get("turns", [])
				if not turns.is_empty():
					var last := int(turns[-1])
					when = " (arrives this turn, %d points left)" % int(rt["left"]) if last == 0 else (" (arrives next turn)" if last == 1 else " (arrives in %d turns)" % (last + 1))
					if s.stored_move(id) == mv and s.planned_move(id) == mv and _no_order(id):
						when += ", marching on from an earlier turn"
			h.add_child(Kit.label("%s %s%s" % [verb, CData.REGIONS[mv]["name"], when], Kit.FONT,
				Kit.COL_GOOD if kind == "move" else Kit.COL_BAD, true))
			var hb := Kit.flow(6)
			if CState.moves_on(ps) and kind in ["raid", "siege", "assault"]:
				var nxt := CData.MODE_SIEGE if kind == "raid" else (CData.MODE_ASSAULT if kind == "siege" else CData.MODE_MARCH)
				var mb0 := Kit.icon_button({CData.MODE_SIEGE: "Lay siege", CData.MODE_ASSAULT: "Assault", CData.MODE_MARCH: "March only"}[nxt],
					{CData.MODE_SIEGE: "siege", CData.MODE_ASSAULT: "assault", CData.MODE_MARCH: "move"}[nxt],
					func(): s.set_move_mode(id, nxt), 96)
				mb0.name = "move_mode"
				hb.add_child(mb0)
			elif kind == "siege" or kind == "join" or (kind == "assault" and CState.sieges_on(ps)):
				var to_mode := CData.MODE_SIEGE if kind == "assault" else CData.MODE_ASSAULT
				var mb := Kit.icon_button("Lay siege" if kind == "assault" else "Assault", "siege" if kind == "assault" else "assault", func(): s.set_move_mode(id, to_mode), 96)
				mb.name = "move_mode"
				hb.add_child(mb)
			var cb := Kit.icon_button("Cancel move", "cancel", func(): s.set_move(id, mv), 110)
			cb.name = "cancel_move"
			hb.add_child(cb)
			h.add_child(hb)
			box.add_child(h)
		elif role == 1:
			var sg := CState.siege_at(ps, r)
			var h2 := Kit.hbox(6)
			h2.add_child(Kit.label("Besieging %s (turn %d). It stays until ordered away." % [CData.REGIONS[r]["city"],
				int(ps["turn"]) - int(sg["turn"])], Kit.FONT, Kit.COL_GOLD, true))
			var sp := Kit.icon_button("Siege", "siege", func(): s.select_region(r), 80)
			sp.name = "army_siege"
			h2.add_child(sp)
			box.add_child(h2)
		elif role == 2:
			var h3 := Kit.hbox(6)
			h3.add_child(Kit.label("Inside the besieged walls of %s: it can only leave by a sally." % CData.REGIONS[r]["city"],
				Kit.FONT, Kit.COL_BAD, true))
			var sp2 := Kit.icon_button("Siege", "siege", func(): s.select_region(r), 80)
			sp2.name = "army_siege"
			h3.add_child(sp2)
			box.add_child(h3)
		elif CState.moves_on(ps) and CState.at_war(ps, af, CState.owner(ps, r)):
			var h4 := Kit.hbox(6)
			h4.add_child(Kit.label("Raiding %s: %s gets half its income." % [CData.REGIONS[r]["name"], _fname(CState.owner(ps, r))],
				Kit.FONT, Kit.COL_GOLD, true))
			var rb := Kit.icon_button("Siege / assault", "siege", func(): s.select_region(r), 120)
			rb.name = "army_raid"
			h4.add_child(rb)
			box.add_child(h4)
		else:
			box.add_child(Kit.label("Tap a highlighted region on the map to move.", Kit.FONT_SMALL, Color.WHITE, true))
		if CState.moves_on(ps):
			_movement_rows(box, a)
	var sel: Array = _split_sel.get(id, [])
	var units: Array = a["units"]
	# Drag a row to reorder the army (an "arrange" order; mouse: drag; touch:
	# long press until it lifts, then drag). Its long press without a drag
	# opens the unit page.
	var reorder: DragReorder = null
	if mine and int(a["busy"]) == 0 and units.size() > 1:
		reorder = DragReorder.new()
		reorder.name = "unit_reorder"
		reorder.vertical = true
		reorder.scroll = s.side_scroll
		box.add_child(reorder)
		reorder.moved.connect(func(from: int, to: int): _arrange(id, from, to))
		reorder.held.connect(func(i: int): s.open_unit_page(CState.unit_type(units[i]), Callable(), ""))
	for k in units.size():
		var u: Dictionary = units[k]
		var ty := CState.unit_type(u)
		var row := Kit.UnitRow.new(ty, int(u["n"]), _fc(af), "", mine)
		row.selected = sel.has(k)
		row.name = "unit_%d" % k
		var kk := k
		if reorder != null:
			reorder.items.append(row)
			row.gui_input.connect(func(e: InputEvent): reorder.feed(e, kk))
		else:
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
	# Planned recruits joining it at the end of the turn (version 6), greyed.
	for k in arriving.size():
		var ro: Dictionary = arriving[k]
		var rty := UT.index_of(str(ro["unit"]))
		var arow := Kit.UnitRow.new(rty, -1, _fc(af).darkened(0.35), "arriving")
		arow.sub_text = "joins at the end of the turn"
		arow.modulate = Color(1, 1, 1, 0.65)
		arow.name = "arriving_%d" % k
		arow.pressed.connect(func(): s.open_unit_page(rty, Callable(), ""))
		var ah := Kit.hbox(4)
		ah.add_child(arow)
		var xb := Kit.icon_button("", "close", func(): s.remove_orders(func(o): return is_same(o, ro)), 44)
		xb.name = "recruit_cancel_%d" % k
		ah.add_child(xb)
		box.add_child(ah)
	if mine and CState.grid_on(ps):
		_army_recruit(box, a)
	if not mine or int(a["busy"]) != 0 or CRules.siege_role(ps, a) != 0:
		return
	var fl := Kit.flow(6)
	var nsel := sel.size()
	var split := Kit.icon_button("Split off %d" % nsel, "split", func(): _split(id), 0)
	split.name = "split"
	split.disabled = nsel == 0 or nsel >= units.size()
	fl.add_child(split)
	var dis := Kit.icon_button("Disband %d" % nsel, "disband", func(): _disband(id), 0)
	dis.disabled = nsel == 0
	fl.add_child(dis)
	fl.add_child(Kit.icon_button("Book", "units", func():
		var ty := CState.unit_type(units[sel[0]] if nsel > 0 else units[0])
		s.open_unit_page(ty, Callable(), ""), 0))
	var near := CState.armies_in(ps, r)
	if CState.grid_on(ps):
		near = []  # version 6: Merge and Exchange are at the top of the card
	for o in near:
		if int(o["id"]) != id and int(o["f"]) == af and int(o["busy"]) == 0 and CRules.siege_role(ps, o) == 0:
			var oid := int(o["id"])
			var mb := Kit.icon_button("Merge into army (%d units)" % CState.unit_count(o), "merge", func():
				_split_sel.erase(id)
				s.add_order({"t": "merge", "army": id, "into": oid})
				s.select_army(oid), 0)
			mb.disabled = CState.unit_count(o) + units.size() > CData.ARMY_MAX
			fl.add_child(mb)
	box.add_child(fl)
	box.add_child(Kit.label("Tap units to choose them for splitting or disbanding. Drag a unit (on a touch screen: hold it until it lifts) to change the order the army takes the field in.",
		Kit.FONT_SMALL, Kit.COL_DIM, true))


## The planned recruit orders into army id (version 6), in order.
func _army_recruits(id: int) -> Array:
	var out: Array = []
	for o in s.orders:
		if str(o["t"]) == "recruit" and int(o.get("army", -1)) == id:
			out.append(o)
	return out


## Version 6 army card: the recruit list when the army stands on or next to
## a settlement of ours: the slots used this turn, every unlocked tier per line
## (tap: the unit book with a Recruit button; "+" recruits at once); off
## while the army has a march planned (an army taking recruits cannot march
## this turn).
func _army_recruit(box: VBoxContainer, a: Dictionary) -> void:
	var ps: Dictionary = s.ps
	var f: int = s.f
	var id := int(a["id"])
	var r := CRules.recruit_region(ps, a)
	if r < 0 or int(a["busy"]) != 0:
		return
	var rs: Dictionary = ps["regions"][r]
	var cap := int(CData.RECRUITS_PER_TURN[int(rs["level"])])
	var used := (rs["queue"] as Array).size()
	var sec := Kit.section("Recruit at %s" % CData.REGIONS[r]["city"], "recruit")
	sec.name = "recruit_section"
	box.add_child(sec)
	var sl := Kit.label("%d of %d recruits here this turn; they join this army at the end of the turn, and it cannot march this turn." % [used, cap],
		Kit.FONT_SMALL, Kit.COL_DIM, true)
	sl.name = "recruit_slots"
	box.add_child(sl)
	if not s.plan6(id).is_empty():
		var ml := Kit.label("This army is marching this turn: cancel its move to recruit into it.", Kit.FONT, Kit.COL_GOLD, true)
		ml.name = "recruit_marching"
		box.add_child(ml)
		return
	var why_a := CRules.army_recruit_check(ps, f, r, id)
	for o in best_options(ps, f, r):
		var ty := UT.index_of(str(o["t"]))
		var ok: bool = o["ok"] and why_a == ""
		var row := Kit.UnitRow.new(ty, -1, _fc(f), str(o["price"]))
		row.sub_text = "Tier %d  -  upkeep %d" % [int(o["tier"]), CState.upkeep_of(ty)] if ok else (why_a if o["ok"] else str(o["why"]))
		var key := str(o["t"])
		row.name = "recruit_row_" + key
		if o["lower"]:
			row.modulate = Color(1, 1, 1, 0.82)
		var order := {"t": "recruit", "r": r, "unit": key, "army": id}
		var add_it := func():
			if s.add_order(order.duplicate()) == "":
				s._t("campaign_input", {"what": "recruit_army"})
		var open_page := func(): s.open_unit_page(ty, add_it if ok else Callable(), "Recruit (%d)" % int(o["price"]))
		row.pressed.connect(open_page)
		row.long_pressed.connect(open_page)
		var h := Kit.hbox(4)
		h.add_child(row)
		var add := Kit.icon_button("", "plus", add_it, 44)
		add.name = "recruit_" + key
		add.disabled = not ok
		h.add_child(add)
		box.add_child(h)


## Version 6, top of the army card: "Merge into army (N units)" for each
## army of ours standing together with this one, and "Exchange units" when
## any friendly army (ours or the allied player's) does.
func _together_row(box: VBoxContainer, a: Dictionary) -> void:
	var ps: Dictionary = s.ps
	var id := int(a["id"])
	if int(a["busy"]) != 0:
		return
	var fl := Kit.flow(6)
	fl.name = "together_row"
	var any := false
	for o in _partners(ps, a):
		any = true
		var oid := int(o["id"])
		if int(o["f"]) != int(a["f"]):
			continue
		var mb := Kit.icon_button("Merge into army (%d units)" % CState.unit_count(o), "merge", func():
			_split_sel.erase(id)
			if s.add_order({"t": "merge", "army": id, "into": oid}) == "":
				s.select_army(oid), 0)
		mb.name = "merge_into_%d" % oid
		mb.disabled = CRules.merge_check(ps, int(a["f"]), id, oid) != ""
		fl.add_child(mb)
	if not any:
		return
	var xb := Kit.icon_button("Exchange units", "exchange", func(): show_exchange(id, -1), 0)
	xb.name = "exchange_units"
	fl.add_child(xb)
	box.add_child(fl)


## Friendly armies army a may trade units with now (ours, or an allied
## player's for a gift), by id.
func _partners(ps: Dictionary, a: Dictionary) -> Array:
	var out: Array = []
	var af := int(a["f"])
	for o in ps["armies"]:
		var of := int(o["f"])
		if int(o["id"]) == int(a["id"]):
			continue
		if of != af and not (CState.is_human(ps, of) and CState.is_human(ps, af) and CState.friendly(ps, af, of)):
			continue
		if CRules.together(ps, a, o) == "":
			out.append(o)
	return out


## The exchange panel (version 6): this army on the left, a nearby friendly
## army on the right (a picker when there are several). Tap a unit row to
## send it across; the counts and the cap show; Confirm adds one exchange
## order (to the allied player's army: a gift, only from this side).
func show_exchange(id: int, other: int) -> void:
	var ps: Dictionary = s.ps
	var a := CState.army(ps, id)
	if a.is_empty():
		return
	var parts := _partners(ps, a)
	if parts.is_empty():
		return
	if int(_xc.get("a", -1)) != id or (other >= 0 and int(_xc.get("b", -1)) != other):
		_xc = {"a": id, "b": other, "out": [], "back": []}
	var cur := -1
	for o in parts:
		if int(o["id"]) == int(_xc["b"]):
			cur = int(o["id"])
	if cur < 0:
		_xc = {"a": id, "b": int(parts[0]["id"]), "out": [], "back": []}
	var b := CState.army(ps, int(_xc["b"]))
	var f := int(a["f"])
	var gift := CRules.is_gift(ps, f, b)
	var out: Array = _xc["out"]
	var back: Array = _xc["back"]
	var v := Kit.vbox(8)
	v.name = "exchange_panel"
	if parts.size() > 1:
		var pick := Kit.flow(6)
		pick.add_child(Kit.label("With:", Kit.FONT_SMALL, Kit.COL_DIM))
		for o in parts:
			var oid := int(o["id"])
			var pb := Kit.button("%s army (%d)" % [CData.FACTIONS[int(o["f"])]["adj"], CState.unit_count(o)], func():
				_xc = {"a": id, "b": oid, "out": [], "back": []}
				show_exchange(id, oid), 0)
			pb.name = "xc_pick_%d" % oid
			pb.disabled = oid == int(b["id"])
			pb.add_theme_color_override("font_color", _fc(int(o["f"])).lightened(0.4))
			pick.add_child(pb)
		v.add_child(pick)
	var na := CState.unit_count(a) - out.size() + back.size()
	var nb := CState.unit_count(b) - back.size() + out.size()
	var cols := Kit.hbox(10)
	var left := Kit.vbox(4)
	var right := Kit.vbox(4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	cols.add_child(right)
	var la := Kit.label("This army: %d / %d" % [na, CData.ARMY_MAX], Kit.FONT, Kit.COL_BAD if na > CData.ARMY_MAX else _fc(f).lightened(0.45))
	la.name = "xc_count_a"
	left.add_child(la)
	var bname := "%s army%s" % [CData.FACTIONS[int(b["f"])]["adj"], " (gift)" if gift else ""]
	var lb := Kit.label("%s: %d / %d" % [bname, nb, CData.ARMY_MAX], Kit.FONT, Kit.COL_BAD if nb > CData.ARMY_MAX else _fc(int(b["f"])).lightened(0.45))
	lb.name = "xc_count_b"
	right.add_child(lb)
	var au: Array = a["units"]
	var bu: Array = b["units"]
	# Units coming across first (framed), then the army's own.
	for k in bu.size():
		if back.has(k):
			left.add_child(_xc_row(bu[k], int(b["f"]), "in", "xb_%d" % k, true, _xc_toggle.bind("back", k)))
	for k in au.size():
		if not out.has(k):
			left.add_child(_xc_row(au[k], f, "", "xa_%d" % k, true, _xc_toggle.bind("out", k)))
	for k in au.size():
		if out.has(k):
			right.add_child(_xc_row(au[k], f, "gift" if gift else "in", "xa_%d" % k, true, _xc_toggle.bind("out", k)))
	for k in bu.size():
		if not back.has(k):
			right.add_child(_xc_row(bu[k], int(b["f"]), "", "xb_%d" % k, not gift, _xc_toggle.bind("back", k)))
	v.add_child(cols)
	var why := CRules.exchange_check(ps, f, id, int(b["id"]), out, back)
	var hint := "Tap a unit to send it across." if not gift else "Tap your units to give them to your ally; their units stay theirs."
	if why != "" and why != "no units chosen":
		hint = "Cannot: %s." % why
	var hl := Kit.label(hint, Kit.FONT_SMALL, Kit.COL_BAD if why != "" and why != "no units chosen" else Kit.COL_DIM, true)
	hl.name = "xc_hint"
	v.add_child(hl)
	var ok_text := ("Gift %d unit%s" % [out.size(), "" if out.size() == 1 else "s"]) if gift else "Confirm"
	# Confirm and Cancel in the dialog's button row: always in view. A
	# re-render after a tap keeps the scroll position (show_dialog).
	s.show_dialog("Exchange units" if not gift else "Give units to %s" % CData.faction_name(int(b["f"])), v,
		[["Cancel", func():
			_xc = {}
			s.close_dialog()], [ok_text, _xc_confirm]], 760)
	var btns: Array = s.dialog_buttons.get_children()
	if btns.size() >= 2:
		(btns[0] as Button).name = "xc_cancel"
		var ok := btns[btns.size() - 1] as Button
		ok.name = "xc_confirm"
		ok.disabled = why != ""
		if gift:
			ok.add_theme_color_override("font_color", _fc(int(b["f"])).lightened(0.5))


func _xc_row(u: Dictionary, uf: int, tag: String, nm: String, active: bool, cb: Callable) -> Control:
	var row := Kit.UnitRow.new(CState.unit_type(u), int(u["n"]), _fc(uf), tag, false)
	row.name = nm
	row.selected = tag != ""
	if active:
		row.pressed.connect(cb)
	else:
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.modulate = Color(1, 1, 1, 0.75)
	return row


func _xc_toggle(side: String, k: int) -> void:
	if _xc.is_empty():
		return
	var list: Array = _xc[side]
	if list.has(k):
		list.erase(k)
	else:
		list.append(k)
	show_exchange(int(_xc["a"]), int(_xc["b"]))


func _xc_confirm() -> void:
	if _xc.is_empty():
		return
	var id := int(_xc["a"])
	var bid := int(_xc["b"])
	var out: Array = (_xc["out"] as Array).duplicate()
	var back: Array = (_xc["back"] as Array).duplicate()
	out.sort()
	back.sort()
	var o := {"t": "exchange", "from": id, "to": bid, "units": out}
	if not back.is_empty():
		o["back"] = back
	var gift := CRules.is_gift(s.ps, s.f, CState.army(s.ps, bid))
	_xc = {}
	s.close_dialog()
	_split_sel.erase(id)
	if s.add_order(o) == "":
		s._t("campaign_input", {"what": "exchange", "gift": 1 if gift else 0})
		if not CState.army(s.ps, id).is_empty():
			s.select_army(id)
		elif int(CState.army(s.ps, bid).get("f", -1)) == s.f:
			s.select_army(bid)
		else:
			s.close_side()


func _no_order(id: int) -> bool:
	for o in s.orders:
		if str(o["t"]) == "move" and int(o["army"]) == id:
			return false
	return true


## Version 5 army card rows: movement points and the stance toggle (Inside
## the walls / In the field) with what it means.
func _movement_rows(box: VBoxContainer, a: Dictionary) -> void:
	var ps: Dictionary = s.ps
	var id := int(a["id"])
	var full := CState.max_mp(a)
	var left := CState.mp(a)
	var rt: Dictionary = s.route(id)
	if not rt.is_empty() and not (rt["turns"] as Array).is_empty() and int(rt["turns"][-1]) == 0:
		left = int(rt["left"])
	var pace := "cavalry only" if full == CData.MP_CAV else ("artillery sets the pace" if full == CData.MP_ART else "on foot")
	var ml := Kit.label("Movement %d of %d points this turn (%s). Open ground costs %d, hills and ridges %d, heavy woods +%d; a sea lane takes a whole turn." % [
		left, full, pace, CData.COST_OPEN, CData.COST_ROUGH, CData.COST_WOODS], Kit.FONT_SMALL, Kit.COL_DIM, true)
	ml.name = "army_points"
	box.add_child(ml)
	var r := int(a["r"])
	if int(a["busy"]) != 0 or CRules.siege_role(ps, a) != 0:
		return
	var own := CState.friendly(ps, int(a["f"]), CState.owner(ps, r))
	var stance := CState.stance(a)
	var h := Kit.hbox(6)
	var inb := Kit.icon_button("Inside the walls" + (" (now)" if stance == CData.STANCE_GARRISON else ""), "inside",
		func(): _set_stance(id, CData.STANCE_GARRISON), 0)
	inb.name = "stance_inside"
	inb.disabled = stance == CData.STANCE_GARRISON or not own
	h.add_child(inb)
	var fb := Kit.icon_button("In the field" + (" (now)" if stance == CData.STANCE_FIELD else ""), "field",
		func(): _set_stance(id, CData.STANCE_FIELD), 0)
	fb.name = "stance_field"
	fb.disabled = stance == CData.STANCE_FIELD
	h.add_child(fb)
	box.add_child(h)
	var txt := ""
	if stance == CData.STANCE_GARRISON:
		txt = "Inside the walls of %s: it defends the settlement with the garrison and cannot be caught in the field, but stops no enemy and supports no battle outside." % CData.REGIONS[r]["city"]
	elif own:
		txt = "In the field: enemy armies marching into %s must fight it, and it joins battles it can reach this turn." % CData.REGIONS[r]["name"]
	else:
		txt = "In the field: enemy armies marching in must fight it, and it joins battles it can reach this turn. Only a settlement of your side can shelter it."
	box.add_child(Kit.label(txt, Kit.FONT_SMALL, Kit.COL_DIM, true))


## Toggle a stance: an order (no points spent); back to the stance it had
## at the start of the turn removes the order.
func _set_stance(id: int, st_v: int) -> void:
	s.remove_orders(func(x): return str(x["t"]) == "stance" and int(x.get("a", -1)) == id)
	var base := CState.army(s.st, id)
	if not base.is_empty() and CState.stance(base) != st_v:
		s.add_order({"t": "stance", "a": id, "s": st_v})
	s.select_army(id)


## A unit row of army id dropped at position `to`: one "arrange" order for
## the army this turn. A later drag rewrites the pending one (composing the
## two) unless an order after it changed the army's units (then a second
## arrange follows them); back to the turn's order drops it. The split
## selection follows its units; the card keeps its scroll position.
func _arrange(id: int, from: int, to: int) -> void:
	var n := CState.unit_count(CState.army(s.ps, id))
	if from < 0 or from >= n or to < 0 or to >= n or from == to:
		return
	var perm: Array = range(n)
	perm.insert(to, perm.pop_at(from))
	var sel: Array = _split_sel.get(id, [])
	if not sel.is_empty():
		var moved_sel: Array = []
		for k in n:
			if sel.has(int(perm[k])):
				moved_sel.append(k)
		_split_sel[id] = moved_sel
	var j := -1
	for k in s.orders.size():
		var o: Dictionary = s.orders[k]
		if str(o["t"]) == "arrange" and int(o.get("army", -1)) == id:
			j = k
	if j >= 0 and not _units_changed_after(id, j):
		var old: Array = s.orders[j]["order"]
		var comp: Array = []
		for k in n:
			comp.append(int(old[int(perm[k])]))
		var list: Array = s.orders.duplicate()
		if comp == range(n):
			list.remove_at(j)
		else:
			list[j] = {"t": "arrange", "army": id, "order": comp}
		s.set_orders(list)
	else:
		s.add_order({"t": "arrange", "army": id, "order": perm})
	s._t("campaign_input", {"what": "arrange"})
	s.select_army(id)  # the same army's card: show_side keeps its place


## An order after index j that changes army id's unit list.
func _units_changed_after(id: int, j: int) -> bool:
	for k in range(j + 1, s.orders.size()):
		var o: Dictionary = s.orders[k]
		var t := str(o["t"])
		if (t in ["split", "disband", "merge", "arrange"] and int(o.get("army", -1)) == id) \
				or (t == "merge" and int(o.get("into", -1)) == id) \
				or (t == "exchange" and (int(o.get("from", -1)) == id or int(o.get("to", -1)) == id)):
			return true
	return false


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
	box.add_child(Kit.label_icon(Kit.label("Treasury %s after this turn's spending." % Kit.money(int(ps["factions"][f]["treasury"])), Kit.FONT, Color.WHITE, true),
		"treasury", Kit.COL_GOLD))
	box.add_child(Kit.icon_label("Income %d (regions %d, trade %d, cost of a large realm -%d), upkeep %d: %+d a turn." % [
		int(inc["total"]), int(inc["regions"]), int(inc["trade"]), int(inc.get("corruption", 0)), up, int(inc["total"]) - up], "income", Kit.FONT, Kit.COL_GOLD, true))
	box.add_child(Kit.label("A turn ending with less than nothing costs every unit a tenth of its men.", Kit.FONT_SMALL, Kit.COL_DIM, true))
	box.add_child(Kit.section("Regions", "realm"))
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
	box.add_child(Kit.icon_label("At war with: " + (", ".join(wars) if not wars.is_empty() else "nobody"), "war", Kit.FONT, Kit.COL_BAD, true))
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
		if int(p["to"]) != f or p.has("kind"):
			continue
		var pid := int(p["id"])
		var answered := -1
		for o in s.orders:
			if str(o["t"]) == "answer" and int(o["id"]) == pid:
				answered = int(o["accept"])
		var h := Kit.hbox(6)
		h.add_child(Kit.label("%s offers %s." % [CData.faction_name(int(p["from"])), _what(str(p["what"]))], Kit.FONT, Kit.COL_GOLD, true))
		if answered < 0:
			h.add_child(Kit.icon_button("Accept", "accept", func():
				s.add_order({"t": "answer", "id": pid, "accept": 1})
				show_diplomacy(), 80))
			h.add_child(Kit.icon_button("Refuse", "decline", func():
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
			if CRules.gift_partner_check(ps, f, g) == "":
				_ally_deals(box, g)
			continue
		var acts := Kit.hbox(6)
		row.add_child(acts)
		var planned := ""
		for o in s.orders:
			if (str(o["t"]) == "propose" or str(o["t"]) == "war") and int(o["to"]) == g:
				planned = str(o.get("what", "war"))
		if planned != "":
			acts.add_child(Kit.label("Planned: " + _what(planned), Kit.FONT_SMALL, Kit.COL_GOOD))
			acts.add_child(Kit.icon_button("Cancel", "cancel", func():
				s.remove_orders(func(o): return (str(o["t"]) == "propose" or str(o["t"]) == "war") and int(o["to"]) == g)
				show_diplomacy(), 80))
		else:
			if d == CState.WAR:
				acts.add_child(_dip_button("Offer peace", "peace", {"t": "propose", "to": g, "what": "peace"}))
			if d == CState.PEACE:
				acts.add_child(_dip_button("Offer trade", "trade", {"t": "propose", "to": g, "what": "trade"}))
			if d == CState.TRADE:
				acts.add_child(_dip_button("End trade", "trade_end", {"t": "propose", "to": g, "what": "cancel_trade"}))
			if d != CState.WAR:
				var wb := Kit.icon_button("Declare war", "war", func(): _confirm_war(g), 0)
				wb.add_theme_color_override("font_color", Kit.COL_BAD)
				Kit.tint_icon(wb, Kit.COL_BAD)
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


func _dip_button(text: String, icon: String, o: Dictionary) -> Button:
	return Kit.icon_button(text, icon, func():
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
	if s._vp().y >= 600:  # a landscape phone: the battle screen needs the room
		box.add_child(Kit.label("Battles must be resolved before the turn can be planned. Auto-resolve lets the battle AI fight both sides (honest, a little worse than good command); Fight to command it yourself.", Kit.FONT_SMALL, Kit.COL_DIM, true))
	for b in list:
		box.add_child(_battle_card(st, b))
	s.show_dialog("Pending battles (%d)" % list.size(), box, [["Close", Callable()]], 900, true)


func _battle_card(st: Dictionary, b: Dictionary) -> Control:
	return BattleScreen.pre(s, st, b)


## The battle screen's result state (game/campaign/battle_screen.gd) for
## the battle just applied: s._battle_snap was taken when it started.
func show_battle_result(events_before: int, outcome: Dictionary) -> void:
	var st: Dictionary = s.st
	var texts: Array = []
	var evs: Array = st["events"]
	for i in range(events_before, evs.size()):
		var t := event_text(evs[i], s.f)
		if t != "":
			texts.append(t)
	var snap: Dictionary = s._battle_snap
	if snap.is_empty():
		var box := Kit.vbox(6)
		for t2 in texts:
			box.add_child(Kit.label(t2, Kit.FONT, Color.WHITE, true))
		if int(outcome.get("forfeit", 0)) != 0:
			box.add_child(Kit.label("You left the field: the army withdrew and the battle counts as lost.", Kit.FONT_SMALL, Kit.COL_DIM, true))
		s.show_dialog("Battle result", box, [["Continue", func(): s._next_step()]], 560)
		return
	s.show_dialog("Battle result", BattleScreen.result(s, snap, outcome, st, texts), [["Continue", func(): s._next_step()]], 900, true)


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
	var how := "Each turn: move your armies (tap an army, then a highlighted region; red regions mean a battle), build and recruit in your regions (tap a region), and End turn. Battles are resolved before the next turn: auto-resolve or fight them yourself."
	if CState.grid_on(s.ps):
		how = "Each turn: march your armies (tap an army, then the map), recruit into an army standing at one of your cities (its card) or raise a new army there (tap the city), build (tap the city), and End turn. Battles are resolved before the next turn: auto-resolve or fight them yourself."
	box.add_child(Kit.label(how, Kit.FONT, Color.WHITE, true))
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
		"peace", "trade", "built", "recruited", "grew", "victory", "gift", "gift_money":
			return Kit.COL_GOOD
		"gift_region":
			return Kit.COL_GOOD if int(e["to"]) == f else Kit.COL_GOLD
		"city_offer":
			return Kit.COL_GOLD
		"city_refused", "city_declined":
			return Kit.COL_BAD
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
				"field":
					return "Field battle in %s: %s attacked %s in the open; %s (%s). %s" % [CData.REGIONS[int(e["r"])]["name"],
						_names(e["att"]), _names(e["def"]), "the defenders fell back" if int(e["winner"]) == 0 else "the attackers fell back", how, loss]
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
		"intercepted":
			if int(e["f"]) != f and int(e["by"]) != f:
				return ""
			if e.has("x"):
				return "A %s army ran into %s's army in %s: a battle." % [CData.FACTIONS[int(e["f"])]["adj"],
					CData.faction_name(int(e["by"])), CData.REGIONS[int(e["r"])]["name"]]
			return "A %s army marching through %s was stopped by %s's army in the field." % [CData.FACTIONS[int(e["f"])]["adj"],
				CData.REGIONS[int(e["r"])]["name"], CData.faction_name(int(e["by"]))]
		"retreat":
			if e.has("x"):
				return "A %s army fell back in %s." % [CData.FACTIONS[int(e["f"])]["adj"], CData.REGIONS[maxi(int(e["to"]), 0)]["name"]]
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
		"gift":
			var n := int(e["n"])
			if int(e["to"]) == f:
				return "%s gave you %d unit%s at %s." % [CData.faction_name(int(e["f"])), n, "" if n == 1 else "s", city.call(e["r"])]
			if int(e["f"]) == f:
				return "You gave %s %d unit%s at %s." % [CData.faction_name(int(e["to"])), n, "" if n == 1 else "s", city.call(e["r"])]
			return ""
		"gift_region", "gift_money", "city_offer", "city_refused", "city_declined":
			return _gift_text(e, f)
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
			if str(e["why"]) == "mustering":
				return "An army taking recruits stayed to muster them this turn; a stored march goes on next turn."
			if int(e["to"]) < 0:
				return "An army could not move: %s." % str(e["why"])
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
			if CState.grid_on(ps) and (CState.stance(a) == CData.ST_FORTIFY or CState.stance(a) == CData.ST_RAID or CRules.inside(ps, a)):
				near_enemy = false  # holding on purpose
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
	for p in s.st["proposals"]:
		if int(p["to"]) == f and p.has("kind") and _offer_answer(int(p["id"])) < 0:
			out.append("%s's offer about %s is unanswered (it lapses): Diplomacy." % [CData.faction_name(int(p["from"])), CData.REGIONS[int(p["r"])]["city"]])
	for p in ps["proposals"]:
		if int(p["to"]) == f and not p.has("kind"):
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
		fl.add_child(Kit.icon_button("Online", "online", func(): s.onl.show_online(), 0))
	else:
		fl.add_child(Kit.icon_button("Export save as text", "export", func(): show_export(), 0))
		var net: Node = s.get_node_or_null("/root/Net")
		if net != null and net.has_server() and str(s.st["phase"]) == "plan" and int(s.st["turn"]) >= 0:
			var ob := Kit.icon_button("Play online", "online", func(): show_go_online(), 0)
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
	var inv := Kit.text_field("Invite key (only if the server asks for one)", str(net.accounts.data.get("invite", "")) if net else "", 300, "Invite key", true)
	inv.name = "invite"
	box.add_child(Kit.field_box(inv))
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
	var copy := Kit.icon_button("Copy to clipboard", "copy", func():
		DisplayServer.clipboard_set(text)
		s._flash("Copied."), 0)
	box.add_child(copy)
	box.add_child(Kit.label("%d characters." % text.length(), Kit.FONT_SMALL, Kit.COL_DIM))
	s.show_dialog("Export", box, [["Close", Callable()]], 620)


# ------------------------------------------- the continuous overworld (v6) ---

const STANCE_HELP := {
	0: "Default: marches at its normal pace, attacks and lays siege; its zone of control stops enemy marches.",
	2: "Forced march: half again as far, but it cannot attack or lay siege, has no zone of control, and fights shaken if caught.",
	3: "Fortify: it stays put; a wider zone of control, supports battles further off and defends better in the field.",
	4: "Raiding: a slower pace; standing in enemy land it takes half that region's income for you.",
}
const STANCE_ORDER: Array[int] = [0, 2, 3, 4]
const STANCE_ICONS := {0: "stance_default", 2: "forced_march", 3: "fortify", 4: "raid"}


## The siege the army stands round (its region), -1 if none.
func _siege_of(ps: Dictionary, a: Dictionary) -> int:
	for sg in ps.get("sieges", []):
		if CGrid.cheb(CState.cell(a), CGrid.site(int(sg["r"]))) <= 1:
			return int(sg["r"])
	return -1


## Army card (version 6): what it does (its march and when it arrives, the
## siege it is in), the on-arrival switch for a hostile settlement, Cancel
## move, the points and the stance selector.
func _army_orders6(box: VBoxContainer, a: Dictionary) -> void:
	var ps: Dictionary = s.ps
	var id := int(a["id"])
	var role := CRules.siege_role(ps, a)
	if int(a["busy"]) != 0:
		box.add_child(Kit.label("In a battle.", Kit.FONT, Kit.COL_BAD))
		return
	var p6: Dictionary = s.plan6(id)
	if role == 1:
		var sr := _siege_of(ps, a)
		var h2 := Kit.hbox(6)
		var sg := CState.siege_at(ps, sr)
		h2.add_child(Kit.label("Besieging %s (turn %d)." % [CData.REGIONS[sr]["city"], int(ps["turn"]) - int(sg.get("turn", ps["turn"]))],
			Kit.FONT, Kit.COL_GOLD, true))
		var sp := Kit.icon_button("Siege", "siege", func(): s.select_region(sr), 80)
		sp.name = "army_siege"
		h2.add_child(sp)
		box.add_child(h2)
	elif role == 2:
		var h3 := Kit.hbox(6)
		h3.add_child(Kit.label("Inside the besieged walls of %s: tap a besieger to sally against it." % CData.REGIONS[int(a["r"])]["city"],
			Kit.FONT, Kit.COL_BAD, true))
		var sp2 := Kit.icon_button("Siege", "siege", func(): s.select_region(int(a["r"])), 80)
		sp2.name = "army_siege"
		h3.add_child(sp2)
		box.add_child(h3)
	elif CRules.inside(ps, a):
		box.add_child(Kit.label("Inside the walls of %s: it defends the city with the garrison; it stops no enemy and supports no battle outside." % CData.REGIONS[int(a["r"])]["city"],
			Kit.FONT_SMALL, Kit.COL_DIM, true))
	if not p6.is_empty():
		var rt: Dictionary = s.route6(id)
		var kind: String = s.move_kind(id)
		var c := int(p6["cell"])
		var r := CGrid.region(c)
		var sr2 := CGrid.site_region(c)
		var place := str(CData.REGIONS[r]["name"]) if r >= 0 else "there"
		var verb := "Marches into %s" % place
		match kind:
			"inside":
				verb = "Goes inside the walls of %s" % CData.REGIONS[sr2]["city"]
			"siege":
				verb = "Lays siege to %s" % CData.REGIONS[sr2]["city"]
			"join":
				verb = "Joins the siege of %s" % CData.REGIONS[sr2]["city"]
			"assault":
				verb = "Storms %s" % CData.REGIONS[sr2]["city"]
			"relief":
				verb = "Relieves %s" % CData.REGIONS[maxi(sr2, r)]["city"]
			"merge":
				var jt := CState.army(ps, int(p6.get("join", -1)))
				verb = "Marches to merge into the army of %d units" % CState.unit_count(jt) if not jt.is_empty() else "Marches to merge"
			"attack", "sally":
				var t := CState.army(ps, int(p6["tgt"]))
				verb = "%s the %s army" % ["Sallies against" if kind == "sally" else "Attacks",
					CData.FACTIONS[int(t["f"])]["adj"] if not t.is_empty() else "enemy"]
		var when := ""
		if rt.has("why"):
			when = " - cannot march there now: %s" % str(rt["why"])
		elif not (rt.get("t", []) as Array).is_empty():
			var last := int(rt["t"][-1])
			when = " (arrives this turn, %d points left)" % int(rt["left"]) if last == 0 else (" (arrives next turn)" if last == 1 else " (arrives in %d turns)" % (last + 1))
		if bool(p6["stored"]):
			when += ", marching on from an earlier turn"
		var ml := Kit.label(verb + when + ".", Kit.FONT, Kit.COL_GOOD if kind in ["move", "inside", "merge"] else Kit.COL_BAD, true)
		ml.name = "army_march"
		box.add_child(ml)
		var h := Kit.flow(6)
		if kind in ["siege", "join", "assault"]:
			h.add_child(Kit.label("On arrival:", Kit.FONT_SMALL, Kit.COL_DIM))
			var assault := int(p6["mode"]) == CData.MODE_ASSAULT
			var b1 := Kit.icon_button("Lay siege" + (" (now)" if not assault else ""), "siege", func(): s.set_move_mode(id, CData.MODE_SIEGE), 0)
			b1.name = "arrive_siege"
			b1.disabled = not assault
			h.add_child(b1)
			var b2 := Kit.icon_button("Assault" + (" (now)" if assault else ""), "assault", func(): s.set_move_mode(id, CData.MODE_ASSAULT), 0)
			b2.name = "arrive_assault"
			b2.disabled = assault
			h.add_child(b2)
		var cb := Kit.icon_button("Cancel move", "cancel", func():
			s.set_move6(id, int(p6["cell"]), int(p6["tgt"]))
			s.select_army(id), 110)
		cb.name = "cancel_move"
		h.add_child(cb)
		box.add_child(h)
	elif role != 2:
		box.add_child(Kit.label("Tap the map (or drag the army) to march: the shaded area is this turn's reach; tap an enemy army to attack it, a city to besiege it.",
			Kit.FONT_SMALL, Color.WHITE, true))
	_movement_rows6(box, a)


func _movement_rows6(box: VBoxContainer, a: Dictionary) -> void:
	var ps: Dictionary = s.ps
	var id := int(a["id"])
	var full := CState.full_mp(ps, a)
	var left := CState.mp(a)
	var base := CState.max_mp(a)
	var pace := "cavalry only" if base == CData.MP_CAV else ("artillery sets the pace" if base == CData.MP_ART else "on foot")
	var ml := Kit.label("Movement %d of %d points this turn (%s). A cell of open ground costs %d, hills %d, ridges %d, heavy woods +%d (diagonals 1.4x); a sea lane takes a whole turn." % [
		left, full, pace, int(CData.GRID_COST[CData.FLAT]), int(CData.GRID_COST[CData.HILL]), int(CData.GRID_COST[CData.RIDGE]),
		CData.GRID_WOODS], Kit.FONT_SMALL, Kit.COL_DIM, true)
	ml.name = "army_points"
	box.add_child(ml)
	if CRules.siege_role(ps, a) == 2:
		return
	var cur := CState.stance(a)
	box.add_child(Kit.label("Stance", Kit.FONT_SMALL, Kit.COL_GOLD))
	var fl := Kit.flow(6)
	for sv in STANCE_ORDER:
		var b := Kit.icon_button(str(CData.STANCE_NAMES[sv]), str(STANCE_ICONS[sv]), func(): _set_stance6(id, sv), 0)
		b.name = "stance_%d" % sv
		b.toggle_mode = true
		b.button_pressed = sv == cur
		b.disabled = sv == cur
		fl.add_child(b)
	box.add_child(fl)
	var sl := Kit.label(str(STANCE_HELP.get(cur, "")), Kit.FONT_SMALL, Kit.COL_DIM, true)
	sl.name = "stance_help"
	box.add_child(sl)


## A stance order (no points spent); back to the stance it had at the start
## of the turn removes the order.
func _set_stance6(id: int, sv: int) -> void:
	var base := CState.army(s.st, id)
	var keep: Array = []
	for o in s.orders:
		if not (str(o["t"]) == "stance" and int(o.get("a", -1)) == id):
			keep.append(o)
	if keep.size() != s.orders.size():
		s._push_undo()
	s.orders = keep
	s._replan()
	if not base.is_empty() and CState.stance(base) != sv:
		s.add_order({"t": "stance", "a": id, "s": sv})
	s.save()
	s.select_army(id)


## The besieged city's panel (version 6): who, how long, supplies; a
## besieger gets the odds and Assault / Continue siege / Withdraw; the
## defender the odds of a sally (made on the map: an army inside taps a
## besieger) and of a relief.
func _siege_section6(box: VBoxContainer, r: int) -> void:
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
		else "out of supplies: the garrison loses %d%% a turn, the besiegers %d%% of their men" % [CData.SIEGE_STARVE_PCT, CData.SIEGE_BESIEGER_PCT]
	var bs := CRules.besiegers(ps, r)
	var men := 0
	var mine: Array = []
	for a in bs:
		men += CState.men(a)
		if int(a["f"]) == f:
			mine.append(a)
	v.add_child(Kit.label("Besieged by %s, turn %d of the siege, %s." % [_fname(int(sg["f"])), turn_n, sup_t],
		Kit.FONT, Kit.COL_GOLD, true))
	var eq_t := CBattle.equipment_text(ps, r)
	if eq_t != "":
		var eql := Kit.label(eq_t, Kit.FONT_SMALL, Color.WHITE, true)
		eql.name = "siege_equipment"
		Kit.label_icon(eql, "ladder")
		v.add_child(eql)
	var note := Kit.label("%d besieging arm%s, %d men. No income, recruits or building while besieged; with no garrison and no army inside it surrenders." % [
		bs.size(), "y" if bs.size() == 1 else "ies", men], Kit.FONT_SMALL, Kit.COL_DIM, true)
	if f < 0:
		v.add_child(note)
		return
	if not mine.is_empty():
		var po := plan_odds(r)
		v.add_child(Kit.odds_view(po["od"], 0, po["names"], po["cols"], "If you storm it this turn (all besiegers):"))
		var ordered := _has_order("assault", r)
		var leaving := _withdrawing(mine, r)
		var txt := "Orders: keep up the siege."
		if ordered:
			txt = "Orders: storm the walls at the end of the turn."
		elif leaving:
			txt = "Orders: withdraw (the siege is lifted when the last besieger leaves)."
		var ol := Kit.label(txt, Kit.FONT, Kit.COL_BAD if ordered or leaving else Color.WHITE, true)
		ol.name = "siege_orders"
		v.add_child(ol)
		var h := Kit.flow(8)
		var ab := Kit.icon_button("Assault", "assault", func():
			_cancel_withdraw(mine, r)
			s.add_order({"t": "assault", "r": r})
			s.select_region(r), 100)
		ab.name = "siege_assault"
		ab.disabled = ordered or CRules.can_assault(ps, f, r) != ""
		h.add_child(ab)
		var cb := Kit.icon_button("Continue siege", "siege", func():
			s.remove_orders(func(x): return str(x["t"]) == "assault" and int(x.get("r", -1)) == r)
			_cancel_withdraw(mine, r)
			s.select_region(r), 130)
		cb.name = "siege_continue"
		cb.disabled = not ordered and not leaving
		h.add_child(cb)
		var wb := Kit.icon_button("Withdraw", "withdraw", func():
			s.remove_orders(func(x): return str(x["t"]) == "assault" and int(x.get("r", -1)) == r)
			_withdraw(mine, sg)
			s.select_region(r), 100)
		wb.name = "siege_withdraw"
		wb.disabled = leaving
		h.add_child(wb)
		v.add_child(h)
		v.add_child(note)
	elif CState.friendly(ps, f, o):
		var inside := CRules.besieged_armies(ps, r)
		if not inside.is_empty():
			var od := CBattle.odds(ps, inside, bs, r, false, 0)
			v.add_child(Kit.odds_view(od, 0, [_fname(f), _fname(int(sg["f"]))], [_fc(f), _fc(int(sg["f"]))],
				"If the armies inside sally with the garrison (a field battle outside the walls):"))
			var hl := Kit.label("To sally: select an army inside (its banner under the city) and tap a besieger.", Kit.FONT_SMALL, Color.WHITE, true)
			hl.name = "sally_hint"
			v.add_child(hl)
		if planned_into(r).size() > 0:
			var po2 := plan_odds(r)
			v.add_child(Kit.odds_view(po2["od"], 0, po2["names"], po2["cols"], "Your relief (with the garrison and the armies inside riding out):"))
		else:
			v.add_child(Kit.label("An army of yours marching onto the city relieves it: a field battle against a besieger, the garrison and the armies inside on its side.",
				Kit.FONT_SMALL, Kit.COL_DIM, true))
		v.add_child(note)
	else:
		v.add_child(note)


## Where a besieger withdraws to: the field cell of the region it came from
## when that is ours, else of our nearest region.
func _withdraw_cell(a: Dictionary, sg: Dictionary) -> int:
	var ps: Dictionary = s.ps
	var f := int(a["f"])
	for pr in sg.get("from", []):
		if int(pr[0]) == int(a["id"]) and int(pr[1]) >= 0 and CState.friendly(ps, f, CState.owner(ps, int(pr[1]))):
			return CState.field_cell(int(pr[1]))
	var best := -1
	var bd := 1 << 30
	for rr in CData.region_count():
		if CState.owner(ps, rr) == f and CState.siege_at(ps, rr).is_empty():
			var d := CGrid.d2(CState.cell(a), CGrid.site(rr))
			if d < bd:
				bd = d
				best = rr
	return CState.field_cell(best) if best >= 0 else -1


func _withdraw(mine: Array, sg: Dictionary) -> void:
	for a in mine:
		var c := _withdraw_cell(a, sg)
		if c < 0:
			continue
		var p6: Dictionary = s.plan6(int(a["id"]))
		if not p6.is_empty() and int(p6["cell"]) == c:
			continue
		s.set_move6(int(a["id"]), c, -1)


func _withdrawing(mine: Array, r: int) -> bool:
	if mine.is_empty():
		return false
	for a in mine:
		var p6: Dictionary = s.plan6(int(a["id"]))
		if p6.is_empty() or CGrid.cheb(int(p6["cell"]), CGrid.site(r)) <= 1:
			return false
	return true


func _cancel_withdraw(mine: Array, r: int) -> void:
	var ids: Array = []
	for a in mine:
		var p6: Dictionary = s.plan6(int(a["id"]))
		if not p6.is_empty() and CGrid.cheb(int(p6["cell"]), CGrid.site(r)) > 1:
			ids.append(int(a["id"]))
	if not ids.is_empty():
		s.remove_orders(func(x): return str(x["t"]) == "move" and ids.has(int(x["army"])))
