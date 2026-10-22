extends PanelContainer
## The command bar of the overworld (user, 2026-10-15: "just a big list on the
## right ... move the army display to the bottom like Rome"): what is selected
## as cards along the bottom of the screen. View only: every button calls the
## screen / panels functions the side-panel buttons call (the screen's order
## list), nothing here touches the state.
##
##  - army: a leader card (emblem, general or army, men, units, movement,
##    stance, upkeep, supply in a siege, what it is doing), a strip of unit
##    cards (symbol, strength bar, tier pips, trait glyphs; a tap picks it for
##    Split / Disband, a long press opens its page, hovering shows the full
##    row), a grid of icon actions with a label under each;
##  - city: the city card, the garrison cards and a row of building chips,
##    the city's actions (Recruit, Build, City map, siege, Raid, Sally);
##  - fleet: the fleet card, a card per ship, the fleet's actions.
## Details opens the old full panel in the side panel (the side panel only
## opens on demand now). Desktop: between the map key and the End turn row,
## DESK_H high, full width at the bottom; the map key and the End turn row
## rise above its corners while it shows (the screen's _layout_bottom).
## Under PHONE_W (a phone): one horizontally scrollable row (card, unit
## cards, actions), PHONE_H high.
## An action that cannot be done is greyed and says why on hover and on a tap.

const FogView := preload("res://game/campaign/fog_view.gd")
const AudioFx := preload("res://game/audio.gd")
const TouchScroll := preload("res://game/touch_scroll.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const UiIcons := preload("res://game/ui_icons.gd")
const IconRaster := preload("res://game/campaign/icon_raster.gd")
const Icons := preload("res://game/unit_icons.gd")
const Traits := preload("res://game/unit_traits.gd")
const UT := preload("res://sim/unit_types.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CChars := preload("res://campaign/cchars.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CSea := preload("res://campaign/csea.gd")
const Panels := preload("res://game/campaign/campaign_panels.gd")
const DragReorder := preload("res://game/drag_reorder.gd")

const DESK_H := 132.0          # bar height, desktop / tablet
const PHONE_H := 96.0          # bar height under PHONE_W
const PHONE_W := 700.0
const MARGIN := 8.0
const CARD_W := 78.0           # unit card width (desktop, the widest)
const CARD_MIN_W := 56.0       # narrowest when the army is big
const CARD_W_PHONE := 62.0
const LEADER_W := 262.0
const LEADER_W_PHONE := 196.0
const ACT_W := 64.0
const ACT_H := 56.0
const ACT_W_PHONE := 56.0
const ACT_ICON := 26           # icon size, desktop
const ACT_ICON_PHONE := 24
const ACT_FONT := 11
const MAX_TRAITS := 3
const COL_BG := Color(0.07, 0.085, 0.075, 0.95)
const WARM_ACTIONS := ["assault", "build", "cancel", "close", "details", "disband", "embark", "exchange", "merge", "raid",
	"raise", "recruit", "sally", "ship", "shipyard", "siege", "split", "view_map", "walls", "war", "withdraw", "more"]
const WARM_STATS := ["coin", "forage", "income", "men", "move", "units", "walls"]
const STANCE_SHORT := {0: "March", 2: "Forced", 3: "Fortify", 4: "Raid"}

var s  # the campaign screen
var phone := false
var shown := false
var _h := DESK_H
var _key := ""
var _scroll_keep := {}      # selection key -> strip scroll
var _strip: ScrollContainer = null


func _init(screen) -> void:
	s = screen
	name = "command_bar"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	add_theme_stylebox_override("panel", Kit.box(COL_BG, 6.0, 8))
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	_warm_icons()


## The bar's icons go into the raster atlas when the screen opens (icon_raster.gd), so the first selection
## already draws them as textures.
func _warm_icons() -> void:
	var acts: Array = WARM_ACTIONS.duplicate()
	acts.append_array(Panels.STANCE_ICONS.values())
	IconRaster.warm(acts, [ACT_ICON, ACT_ICON_PHONE])
	var small: Array = WARM_STATS.duplicate()
	small.append_array(Panels.STANCE_ICONS.values())
	small.append_array(Panels.CHAR_GLYPH)
	IconRaster.warm(small, [UiIcons.px_for(12)])
	IconRaster.warm(Traits.TRAIT_ICONS.values(), [12, 14])


## Top edge (screen y) of the bar, the screen's height when it is hidden.
func top_y() -> float:
	var vp: Vector2 = s._vp()
	if not shown:
		return vp.y
	return vp.y - MARGIN - _h


## Height of the bar.
func height() -> float:
	return _h


func _place() -> void:
	offset_left = MARGIN
	offset_right = -MARGIN
	offset_bottom = -MARGIN
	offset_top = -MARGIN - _h


## Rebuild for the current selection (true: the bar shows something).
func refresh() -> bool:
	var vp: Vector2 = s._vp()
	phone = vp.x < PHONE_W
	_h = PHONE_H if phone else DESK_H
	var kind := ""
	var id := -1
	if s.sel_army >= 0 and not CState.army(s.ps, s.sel_army).is_empty():
		kind = "a"
		id = s.sel_army
	elif s.sel_fleet >= 0 and CFleet.on(s.ps) and not CFleet.fleet(s.ps, s.sel_fleet).is_empty():
		kind = "f"
		id = s.sel_fleet
	elif s.sel_region >= 0:
		kind = "r"
		id = s.sel_region
	if _strip != null and is_instance_valid(_strip):
		_scroll_keep[_key] = _strip.scroll_horizontal
	_strip = null
	for c in get_children():
		remove_child(c)
		c.queue_free()
	if kind == "":
		shown = false
		visible = false
		_key = ""
		return false
	_key = "%s%d" % [kind, id]
	match kind:
		"a":
			_build_army(id)
		"f":
			_build_fleet(id)
		_:
			_build_region(id)
	_place()
	shown = true
	visible = true
	if _strip != null and int(_scroll_keep.get(_key, 0)) > 0:
		_restore.call_deferred(_key, int(_scroll_keep[_key]))
	return true


func _restore(key: String, v: int) -> void:
	if key == _key and _strip != null and is_instance_valid(_strip):
		_strip.scroll_horizontal = v


# ------------------------------------------------------------ pieces ---

func _sep() -> VSeparator:
	var v := VSeparator.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


func _stat(icon: String, text: String, tip: String, col: Color = Color.WHITE) -> Label:
	var l := Kit.icon_label(text, icon, 12, col)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l


## The card on the left: emblem, title and sub line, glyph + number pairs,
## a status line.
func _leader(fac: int, title: String, sub: String, title_col: Color, stats: Array, status: String, status_col: Color) -> Control:
	var v := Kit.vbox(3)
	v.name = "leader_card"
	v.custom_minimum_size.x = LEADER_W_PHONE if phone else LEADER_W
	var head := Kit.hbox(8)
	head.add_child(Kit.faction_mark(fac, 30.0 if phone else 36.0))
	var tv := Kit.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tl := Kit.label(title, 15, title_col) if phone else Kit.title(title, 18, title_col)   # the display face from 18 px
	tl.name = "leader_title"
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tl.custom_minimum_size.x = 40
	tv.add_child(tl)
	var sl := Kit.label(sub, 12, Kit.COL_DIM)
	sl.name = "leader_sub"
	sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sl.custom_minimum_size.x = 40
	tv.add_child(sl)
	head.add_child(tv)
	v.add_child(head)
	var fl := Kit.flow(10)
	fl.name = "leader_stats"
	for st in stats:
		fl.add_child(st)
	v.add_child(fl)
	if status != "":
		var stl := Kit.label(status, 12, status_col)
		stl.name = "leader_status"
		stl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		stl.custom_minimum_size.x = 40
		stl.tooltip_text = status
		stl.mouse_filter = Control.MOUSE_FILTER_STOP
		v.add_child(stl)
	return v


## An icon action with its label under it. `off` (a reason) greys it: a tap
## then says why (touch has no hover); `lit` marks the current choice.
func _action(icon: String, label: String, tip: String, cb: Callable, off: String = "", nm: String = "", lit: bool = false) -> Button:
	var b := Button.new()
	b.name = "act_" + (nm if nm != "" else icon)
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", ACT_FONT)
	b.icon = IconRaster.tex(icon, ACT_ICON_PHONE if phone else ACT_ICON)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_constant_override("h_separation", 0)
	b.add_theme_constant_override("icon_max_width", ACT_ICON_PHONE if phone else ACT_ICON)
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	b.custom_minimum_size = Vector2(ACT_W_PHONE if phone else ACT_W, PHONE_H - 26.0 if phone else ACT_H)
	Kit.tint_icon(b, Kit.COL_GOLD if lit else Kit.COL_TEXT)
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var sb := Kit.box(_btn_col(st, lit), 2.0, 6)
		sb.content_margin_left = 1.0
		sb.content_margin_right = 1.0
		b.add_theme_stylebox_override(st, sb)
	if lit:
		b.add_theme_color_override("font_color", Kit.COL_GOLD)
		b.toggle_mode = true
		b.button_pressed = true
	b.tooltip_text = tip if off == "" else "%s\n%s" % [tip, off]
	if off != "":
		b.modulate = Color(1, 1, 1, 0.45)
		b.pressed.connect(func():
			AudioFx.play("refused", 0.9, 0.0, "ui")
			s.show_toast(off))
	else:
		b.pressed.connect(AudioFx.click)
		b.pressed.connect(cb)
	return b


func _btn_col(state: String, lit: bool) -> Color:
	var base := Color(0.8, 0.7, 0.3, 0.16) if lit else Color(1, 1, 1, 0.07)
	match state:
		"hover":
			return Color(base, 0.2)
		"pressed", "hover_pressed":
			return Color(base, 0.3)
		"focus":
			return Color(0, 0, 0, 0)
	return base


func _actions(list: Array) -> Control:
	if phone:
		var h := Kit.hbox(4)
		h.name = "actions"
		for b in list:
			h.add_child(b)
		return h
	var g := GridContainer.new()
	g.name = "actions"
	g.columns = maxi(1, ceili(list.size() / 2.0))
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	for b in list:
		g.add_child(b)
	return g


func _details_action() -> Button:
	if s.side.visible:
		return _action("close", "Hide", "Close the full panel (the selection stays)", func(): s.close_details(), "", "details")
	return _action("details", "Details", "The full panel: every order, list and number", func(): s.open_details(), "", "details")


## Put the pieces together: desktop: card, strip (scrolls), actions; phone:
## everything in one scrolling row.
func _assemble(leader: Control, cards: Array, extra: Array, actions: Array) -> void:
	if phone:
		var sc := TouchScroll.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.name = "bar_scroll"
		var row := Kit.hbox(6)
		sc.add_child(row)
		row.add_child(leader)
		row.add_child(_sep())
		for c in cards:
			row.add_child(c)
		for e in extra:
			row.add_child(e)
		row.add_child(_sep())
		row.add_child(_actions(actions))
		add_child(sc)
		_strip = sc
		return
	var root := Kit.hbox(8)
	add_child(root)
	root.add_child(leader)
	root.add_child(_sep())
	var sc2 := TouchScroll.new()
	sc2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc2.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc2.name = "unit_strip"
	var strip := Kit.hbox(6)
	sc2.add_child(strip)
	for c in cards:
		strip.add_child(c)
	for e in extra:
		strip.add_child(e)
	sc2.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and (ev.button_index == MOUSE_BUTTON_WHEEL_DOWN or ev.button_index == MOUSE_BUTTON_WHEEL_UP):
			sc2.scroll_horizontal += (90 if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN else -90)
			sc2.accept_event())
	root.add_child(sc2)
	root.add_child(_sep())
	root.add_child(_actions(actions))
	_strip = sc2


## Card width: the widest that lets n cards fit the strip on a desktop.
func _card_w(n: int, actions_n: int) -> float:
	if phone:
		return CARD_W_PHONE
	var vp: Vector2 = s._vp()
	var act_w := ceili(actions_n / 2.0) * (ACT_W + 4.0)
	var avail := vp.x - 2.0 * MARGIN - LEADER_W - act_w - 60.0
	if n <= 0:
		return CARD_W
	return clampf(floorf((avail - 6.0 * n) / n), CARD_MIN_W, CARD_W)


func _card_h() -> float:
	return (PHONE_H if phone else DESK_H) - 12.0 - (4.0 if phone else 14.0)


func _card(ty: int, men: int, full: int, fac: int) -> UnitCard:
	var c := UnitCard.new(0.0, _card_h())
	c.ty = ty
	c.men = men
	c.full = maxi(full, 1)
	c.faction = fac
	c.col = CData.faction_color(fac) if fac >= 0 else Color(0.5, 0.5, 0.5)
	c.title = str(UT.TYPES[ty].get("short", UT.TYPES[ty]["name"]))   # the card is narrow: the short name
	c.pips = UT.tier_of(ty)
	c.tooltip_text = str(UT.TYPES[ty]["name"])
	return c


# -------------------------------------------------------------- army ---

func _status(a: Dictionary) -> Array:
	var ps: Dictionary = s.ps
	var id := int(a["id"])
	if int(a["busy"]) != 0:
		return ["In a battle", Kit.COL_BAD]
	var role := CRules.siege_role(ps, a)
	if role == 1:
		return ["Besieging %s" % CData.REGIONS[int(a["r"])]["city"], Kit.COL_GOLD]
	if role == 2:
		return ["Besieged inside the walls", Kit.COL_BAD]
	var p6: Dictionary = s.plan6(id)
	if p6.is_empty():
		return ["Holding position", Kit.COL_DIM]
	var kind: String = s.move_kind(id)
	var verb: String = {"inside": "Going inside", "siege": "Laying siege", "join": "Joining the siege", "assault": "Storming",
		"relief": "Relieving", "merge": "Marching to merge", "attack": "Attacking", "sally": "Sallying", "raid": "Raiding"}.get(kind, "Marching")
	var rt: Dictionary = s.route6(id)
	var when := ""
	if rt.has("why"):
		return ["Cannot march: %s" % str(rt["why"]), Kit.COL_BAD]
	if not (rt.get("t", []) as Array).is_empty():
		var last := int(rt["t"][-1])
		when = ", arrives this turn" if last == 0 else (", next turn" if last == 1 else ", in %d turns" % (last + 1))
	return [verb + when, Kit.COL_GOOD if kind in ["move", "inside", "merge"] else Kit.COL_BAD]


func _build_army(id: int) -> void:
	var ps: Dictionary = s.ps
	var a := CState.army(ps, id)
	var af := int(a["f"])
	var mine: bool = af == s.f
	var r := int(a["r"])
	var units: Array = a["units"]
	var busy := int(a["busy"]) != 0
	var role := CRules.siege_role(ps, a)
	var city := str(CData.REGIONS[r]["city"])
	var hero: Dictionary = CChars.in_slot(ps, id, CChars.SLOT_HERO)
	var title := "%s army" % CData.FACTIONS[af]["adj"]
	var sub := "at %s" % city
	if not hero.is_empty():
		title = str(hero.get("name", title))
		sub = "%s army at %s" % [CData.FACTIONS[af]["adj"], city]
	var arriving: Array = s.panels._army_recruits(id) if mine else []
	var up := 0
	for u in units:
		up += CState.upkeep_of(CState.unit_type(u))
	var cur := CState.stance(a)
	var stats: Array = []
	stats.append(_stat("men", "%d" % CState.men(a), "Men in the army"))
	stats.append(_stat("units", "%d/%d%s" % [CState.unit_count(a), CData.ARMY_MAX, " +%d" % arriving.size() if not arriving.is_empty() else ""],
		"Units of %d the army can hold%s" % [CData.ARMY_MAX, " (recruits arriving at the end of the turn)" if not arriving.is_empty() else ""]))
	stats.append(_stat("move", "%d/%d" % [CState.mp(a), CState.full_mp(ps, a)], "Movement points left this turn / in a full turn"))
	stats.append(_stat(str(Panels.STANCE_ICONS.get(cur, "stance_default")), str(STANCE_SHORT.get(cur, "March")),
		"Stance: %s" % str(CData.STANCE_NAMES.get(cur, "Default"))))
	if mine:
		stats.append(_stat("coin", "-%d/turn" % up, "Upkeep: what the army costs a turn (not the treasury)", Kit.COL_GOLD))
	if role != 0:
		var sg := CState.siege_at(ps, r)
		if not sg.is_empty():
			stats.append(_stat("forage", "%d" % int(sg.get("supply", 0)), "Turns of supplies left in the siege"))
	for c in CChars.of_army(ps, id):
		if int(CChars.slot_of(str(c["kind"]))) != CChars.SLOT_HERO:
			stats.append(_stat(str(Panels.CHAR_GLYPH[CChars.slot_of(str(c["kind"]))]), "", "%s: %s" % [CChars.SLOT_NAMES[CChars.slot_of(str(c["kind"]))], str(c.get("name", ""))]))
	var stt := _status(a)
	var leader := _leader(af, title, sub, CData.faction_color(af).lightened(0.45), stats, str(stt[0]), stt[1])
	# Actions.
	var acts: Array = []
	var sel: Array = s.panels._split_sel.get(id, [])
	var p6: Dictionary = s.plan6(id) if mine and not busy else {}
	if mine and not busy:
		if role != 2:
			var i := Panels.STANCE_ORDER.find(cur)
			var nxt: int = Panels.STANCE_ORDER[(i + 1) % Panels.STANCE_ORDER.size()]
			acts.append(_action(str(Panels.STANCE_ICONS[cur]), str(STANCE_SHORT.get(cur, "March")),
				"Stance: %s. %s\nTap for %s." % [CData.STANCE_NAMES[cur], str(Panels.STANCE_HELP.get(cur, "")), CData.STANCE_NAMES[nxt]],
				func(): s.panels._set_stance6(id, nxt), "", "stance"))
		if not p6.is_empty():
			var kind: String = s.move_kind(id)
			if kind in ["siege", "join", "assault"]:
				var assault := int(p6["mode"]) == CData.MODE_ASSAULT
				acts.append(_action("siege", "Siege", "On arrival: lay siege", func(): s.set_move_mode(id, CData.MODE_SIEGE), "", "arrive_siege", not assault))
				acts.append(_action("assault", "Assault", "On arrival: storm the walls", func(): s.set_move_mode(id, CData.MODE_ASSAULT), "", "arrive_assault", assault))
			acts.append(_action("cancel", "Cancel", "Cancel this army's march", func():
				s.set_move6(id, int(p6["cell"]), int(p6["tgt"]))
				s.select_army(id), "", "cancel_move"))
		if role == 1:
			var sr := r
			acts.append(_action("siege", "Siege", "The siege of %s: assault, withdraw" % CData.REGIONS[sr]["city"], func(): s.select_region(sr), "", "siege"))
		elif role == 2:
			acts.append(_action("sally", "Sally", "Sally out: select this army and tap a besieger on the map", func():
				s.show_toast("To sally: with this army selected, tap a besieger on the map."), "", "sally"))
		var nsel := sel.size()
		if role == 0:
			acts.append(_action("split", "Split", "Split the picked units off into a new army (tap unit cards to pick them)", func(): s.panels._split(id),
				"Tap unit cards to pick the units to split off" if nsel == 0 else ("Leave at least one unit behind" if nsel >= units.size() else ""), "split"))
		var parts: Array = s.panels._partners(ps, a)
		var merge_to := -1
		for o in parts:
			if int(o["f"]) == af and CRules.merge_check(ps, af, id, int(o["id"])) == "":
				merge_to = int(o["id"])
				break
		if not parts.is_empty():
			if merge_to >= 0:
				var mt := merge_to
				acts.append(_action("merge", "Merge", "Merge into the army beside it (%d units)" % CState.unit_count(CState.army(ps, mt)), func():
					s.panels._split_sel.erase(id)
					if s.add_order({"t": "merge", "army": id, "into": mt}) == "":
						s.select_army(mt), "", "merge"))
			acts.append(_action("exchange", "Exchange", "Trade units with the army beside it", func(): s.panels.show_exchange(id, -1), "", "exchange"))
		var rr := CRules.recruit_region(ps, a)
		if rr >= 0 and role == 0:
			acts.append(_action("recruit", "Recruit", "Recruit into this army at %s" % CData.REGIONS[rr]["city"],
				func(): s.panels.show_army_recruit(id), "This army is marching: cancel its move to recruit" if not p6.is_empty() else "", "recruit"))
		if role == 0:
			acts.append(_action("disband", "Disband", "Disband the picked units (their men go home)", func(): s.panels._disband(id),
				"Tap unit cards to pick the units to disband" if nsel == 0 else "", "disband"))
		if CFleet.on(ps):
			for fl in CFleet.fleets_of(ps, s.f):
				if CFleet.near_fleet(a, fl):
					var fid := int(fl["id"])
					var why := CFleet.embark_check(ps, s.f, id, fid)
					acts.append(_action("embark", "Board", "Board the fleet beside it (%d of %d places taken)" % [CFleet.carried_units(fl), CFleet.capacity(fl)],
						func(): s.embark(id, fid), why, "board"))
					break
	if not mine and not busy and s.f >= 0 and CState.grid_on(ps) and CState.at_war(ps, s.f, af):
		var ch: Array = s.panels.attacker_for(id)
		var by := int(ch[0])
		acts.append(_action("war", "Attack", "Attack them with your strongest army that reaches them this turn", func(): s.panels.attack_with(by, id),
			str(ch[1]), "attack"))
	acts.append(_details_action())
	# Cards.
	var cw := _card_w(units.size() + arriving.size(), acts.size())
	var cards: Array = []
	# Drag a card (mouse: press and move; touch: hold until it lifts) to change
	# the order the army takes the field in: an "arrange" order, as in Details.
	var reorder: DragReorder = null
	if mine and not busy and units.size() > 1:
		reorder = DragReorder.new()
		reorder.name = "unit_reorder"
		reorder.vertical = false
		reorder.moved.connect(func(from: int, to: int): s.panels._arrange(id, from, to))
		reorder.held.connect(func(i: int): s.open_unit_page(CState.unit_type(units[i]), Callable(), ""))
	for k in units.size():
		var u: Dictionary = units[k]
		var ty := CState.unit_type(u)
		var c := _card(ty, int(u["n"]), UT.size_of(ty), af)
		c.name = "unit_card_%d" % k
		c.custom_minimum_size.x = cw
		c.selected = sel.has(k)
		var kk := k
		c.pressed.connect(func():
			if not mine or busy:
				s.open_unit_page(ty, Callable(), "")
				return
			var cur_sel: Array = s.panels._split_sel.get(id, [])
			if cur_sel.has(kk):
				cur_sel.erase(kk)
			else:
				cur_sel.append(kk)
			s.panels._split_sel[id] = cur_sel
			s.select_army(id))
		if reorder != null:
			reorder.items.append(c)
			c.gui_input.connect(func(e: InputEvent): reorder.feed(e, kk))
		else:
			c.long_pressed.connect(func(): s.open_unit_page(ty, Callable(), ""))
		cards.append(c)
	for k in arriving.size():
		var rty := UT.index_of(str(arriving[k]["unit"]))
		var ac := _card(rty, -1, UT.size_of(rty), af)
		ac.name = "arriving_card_%d" % k
		ac.custom_minimum_size.x = cw
		ac.dim = true
		ac.sub = "joins"
		ac.tooltip_text = "%s: joins at the end of the turn" % str(UT.TYPES[rty]["name"])
		var ro: Dictionary = arriving[k]
		ac.tooltip_text += " (tap to cancel the recruit)"
		ac.pressed.connect(func(): s.remove_orders(func(o): return is_same(o, ro)))
		ac.long_pressed.connect(func(): s.open_unit_page(rty, Callable(), ""))
		cards.append(ac)
	var extra: Array = []
	if reorder != null:
		extra.append(reorder)
	_assemble(leader, cards, extra, acts)
	if reorder != null and _strip != null:
		reorder.scroll = _strip


# -------------------------------------------------------------- city ---

func _build_region(r: int) -> void:
	var ps: Dictionary = s.ps
	var f: int = s.f
	var rd: Dictionary = CData.REGIONS[r]
	var rs: Dictionary = ps["regions"][r]
	if not FogView.region_seen(r):
		# (fog) out of sight: the owner as last seen and when, nothing else
		var fo := FogView.shown_owner(ps, r)
		var ft := FogView.last_seen(ps, r)
		var fl := _leader(fo, str(rd["city"]), "Out of sight", CData.faction_color(fo).lightened(0.45) if fo >= 0 else Kit.COL_DIM, [],
			"Never seen" if ft < 0 else "As of turn %d: %s" % [ft, CData.faction_name(fo) if fo >= 0 else "independent"], Kit.COL_GOLD)
		_assemble(fl, [], [], [_details_action()])
		return
	var o := int(rs["owner"])
	var mine := o == f and f >= 0
	var lvl := int(rs["level"])
	var w := CState.walls(ps, r)
	var gar := CRules.garrison(ps, r)
	var gmen := 0
	for g in gar:
		gmen += int(g["n"])
	var sg := CState.siege_at(ps, r)
	var oname := CData.faction_name(o) if o >= 0 else "Independent"
	var stats: Array = []
	stats.append(_stat("income", "%d" % CRules.region_income(ps, r), "Income a turn"))
	stats.append(_stat("coin", "%d" % int(rd["wealth"]), "Wealth of the land"))
	stats.append(_stat("walls", "%d" % w, "Walls level %d" % w))
	stats.append(_stat("men", "%d" % gmen, "Garrison: %d men at %d%% strength" % [gmen, int(rs["gar"])]))
	var status := "Level %d of %d" % [lvl + 1, CData.LEVEL_NAMES.size()]
	var scol := Kit.COL_DIM
	if not sg.is_empty():
		var tn := int(ps["turn"]) - int(sg["turn"])
		status = "Besieged by %s, turn %d" % [CData.faction_name(int(sg["f"])), tn]
		scol = Kit.COL_BAD
		stats.append(_stat("forage", "%d" % int(sg["supply"]), "Turns of supplies left in the siege"))
	elif not CState.battle_at(ps, r).is_empty():
		status = "A battle is pending here"
		scol = Kit.COL_BAD
	elif CRules.raider(ps, r) >= 0:
		status = "Raided by %s" % CData.faction_name(CRules.raider(ps, r))
		scol = Kit.COL_BAD
	elif o != f and o >= 0 and f >= 0:
		match CState.dip(ps, f, o):
			CState.WAR:
				status = "At war with you"
				scol = Kit.COL_BAD
			CState.ALLIED:
				status = "Your ally"
				scol = Kit.COL_GOOD
			_:
				status = "At peace with you"
	var leader := _leader(o, str(rd["city"]), "%s of %s" % [CData.LEVEL_NAMES[lvl], oname], CData.faction_color(o).lightened(0.45) if o >= 0 else Kit.COL_DIM, stats, status, scol)
	# Actions.
	var acts: Array = []
	var grid := CState.grid_on(ps)
	if mine and grid:
		var why := Panels.raise_why(ps, f, r)
		var yt: Array = s.panels.ship_tab(r)
		if why != "" and bool(yt[0]) and str(yt[1]) == "":
			why = ""  # nothing to raise, but ships to build
		acts.append(_action("raise", "Recruit", "Raise a new army here%s (to add to an army, select it)" % (" or build ships" if bool(yt[0]) else ""),
			func(): s.panels.show_raise(r, s.panels.raise_tab_for(r)), why, "recruit"))
		acts.append(_action("build", "Build", "Buildings of this city: queue one", func(): s.panels.show_build(r), "", "build"))
	acts.append(_action("view_map", "City map", "The battle map of this settlement", func(): s.panels.show_city_map(r), "", "city_map"))
	if not sg.is_empty():
		var bs := CRules.besiegers(ps, r)
		var mine_b: Array = []
		for a in bs:
			if int(a["f"]) == f:
				mine_b.append(a)
		if not mine_b.is_empty():
			var ordered: bool = s.panels._has_order("assault", r)
			var leaving: bool = s.panels._withdrawing(mine_b, r)
			var no_assault := CRules.can_assault(ps, f, r)
			acts.append(_action("assault", "Assault", "Storm the walls at the end of the turn", func():
				s.panels._cancel_withdraw(mine_b, r)
				s.add_order({"t": "assault", "r": r})
				s.select_region(r), "Already ordered" if ordered else no_assault, "siege_assault", ordered))
			if ordered or leaving:
				acts.append(_action("siege", "Continue", "Keep up the siege instead", func():
					s.remove_orders(func(x): return str(x["t"]) == "assault" and int(x.get("r", -1)) == r)
					s.panels._cancel_withdraw(mine_b, r)
					s.select_region(r), "", "siege_continue"))
			acts.append(_action("withdraw", "Withdraw", "Lift the siege: the besiegers withdraw", func():
				s.remove_orders(func(x): return str(x["t"]) == "assault" and int(x.get("r", -1)) == r)
				s.panels._withdraw(mine_b, sg)
				s.select_region(r), "Already withdrawing" if leaving else "", "siege_withdraw", leaving))
		elif mine and not CRules.besieged_armies(ps, r).is_empty():
			acts.append(_action("sally", "Sally", "Sally out: select an army inside and tap a besieger on the map", func():
				s.show_toast("To sally: select an army inside (its banner under the city) and tap a besieger."), "", "sally"))
	elif f >= 0 and o != f and CState.at_war(ps, f, o) and CState.battle_at(ps, r).is_empty():
		var best := -1
		var best_d := 1000000
		var raider := -1
		for a in CState.armies_of(ps, f):
			if int(a["busy"]) != 0:
				continue
			var d := CGrid.cheb(CState.cell(a), CGrid.site(r))
			if d < best_d:
				best_d = d
				best = int(a["id"])
			if int(a["r"]) == r and raider < 0:
				raider = int(a["id"])
		var bid := best
		acts.append(_action("siege", "Besiege", "Select your nearest army, then tap the city to march on it", func():
			s.select_army(bid)
			s.show_toast("Army selected: tap the city again on the map to lay siege to it."),
			"No army of yours is free" if best < 0 else "", "besiege"))
		if raider >= 0:
			var rid := raider
			var ra := CState.army(ps, rid)
			acts.append(_action("raid", "Raid", "Put the army standing here on a raid: it takes part of the income",
				func(): s.panels._set_stance6(rid, 4), "Already raiding" if CState.stance(ra) == 4 else "", "raid", CState.stance(ra) == 4))
	acts.append(_details_action())
	# Cards: the garrison, then the building chips.
	var cw := _card_w(gar.size(), acts.size())
	var cards: Array = []
	for k in gar.size():
		var g: Dictionary = gar[k]
		var ty := UT.index_of(str(g["t"]))
		var c := _card(ty, int(g["n"]), int(g["full"]), o)
		c.name = "garrison_card_%d" % k
		c.custom_minimum_size.x = cw
		c.pressed.connect(func(): s.open_unit_page(ty, Callable(), ""))
		c.long_pressed.connect(func(): s.open_unit_page(ty, Callable(), ""))
		cards.append(c)
	var extra: Array = []
	if mine and grid:
		var chips: Array = []
		var bld: Array = rs["build"]
		for ci in CData.CHAINS.size():
			var ch: Dictionary = CData.CHAINS[ci]
			var cur := CState.building(ps, r, ci)
			var building: bool = not bld.is_empty() and int(bld[0]) == ci
			if cur == 0 and not building:
				continue
			var lab := "%s %d" % [str(ch["name"]), cur]
			var tip := "%s: %s" % [lab, str(ch["desc"])]
			if building:
				tip += "\nBuilding level %d: %d turn%s left." % [int(bld[1]), int(bld[2]), "" if int(bld[2]) == 1 else "s"]
			var chip := _action(str(ch["key"]), ("%s >%d" % [str(ch["name"]), int(bld[1])]) if building else lab, tip,
				func(): s.show_toast(tip), "", "bld_" + str(ch["key"]), building)
			chip.custom_minimum_size = Vector2(ACT_W_PHONE if phone else 52.0, chip.custom_minimum_size.y if phone else ACT_H)
			chips.append(chip)
		if not chips.is_empty():
			var holder: Control
			if phone:
				var hb := Kit.hbox(4)
				hb.name = "building_row"
				for chp in chips:
					hb.add_child(chp)
				holder = hb
			else:
				var gd := GridContainer.new()
				gd.name = "building_row"
				gd.columns = maxi(1, ceili(chips.size() / 2.0))
				gd.add_theme_constant_override("h_separation", 4)
				gd.add_theme_constant_override("v_separation", 4)
				for chp in chips:
					gd.add_child(chp)
				holder = gd
			extra.append(_sep())
			extra.append(holder)
	_assemble(leader, cards, extra, acts)


# ------------------------------------------------------------- fleet ---

func _build_fleet(id: int) -> void:
	var ps: Dictionary = s.ps
	var fl := CFleet.fleet(ps, id)
	var ff := int(fl["f"])
	var mine: bool = ff == s.f
	var ships: Array = fl["ships"]
	var flota := CSea.is_flota(fl)
	var up := 0
	for sh in ships:
		up += int(CData.ship_row(str(sh["t"])).get("upkeep", 0))
	var place: String = s.panels.sea_place(int(fl["x"]), int(fl["y"]))
	var stats: Array = []
	stats.append(_stat("ship", "%d" % ships.size(), "Ships in the fleet"))
	stats.append(_stat("men", "%d/%d" % [CFleet.carried_units(fl), CFleet.capacity(fl)], "Units of troops aboard / places"))
	stats.append(_stat("move", "%d" % (CFleet.speed(fl) / 10), "Cells a turn on a beam reach"))
	if mine and not flota:
		stats.append(_stat("coin", "-%d/turn" % up, "Upkeep: what the army costs a turn (not the treasury)", Kit.COL_GOLD))
	var status := "Has sailed this turn" if int(fl.get("moved", 0)) != 0 else "In port" if CFleet.port_of(ps, fl, ff) >= 0 else "At sea"
	var vy: Array = s.planned_voyage(id) if mine else [-1, -1]
	if mine and (int(vy[0]) >= 0 or int(vy[1]) >= 0):
		status = "Voyage planned"
	var leader := _leader(ff, "The flota" if flota else "%s fleet" % CData.FACTIONS[ff]["adj"], place, CData.faction_color(ff).lightened(0.45), stats, status, Kit.COL_GOOD if status == "Voyage planned" else Kit.COL_DIM)
	var acts: Array = []
	if mine and not flota and int(fl.get("moved", 0)) == 0:
		if int(vy[0]) >= 0 or int(vy[1]) >= 0:
			acts.append(_action("cancel", "Cancel", "Cancel the voyage", func(): s.set_fmove(id, int(vy[0]), int(vy[1])), "", "cancel_voyage"))
		else:
			acts.append(_action("move", "Sail", "Tap the sea on the map to sail there, a coast to land the troops, an enemy fleet to attack it, your own fleet to join it", func():
				s.show_toast("Tap the sea to sail, a coast to land the troops aboard, an enemy fleet to attack, your own fleet to join it."), "", "sail"))
		for a in CState.armies_of(ps, s.f):
			if CFleet.near_fleet(a, fl):
				var aid := int(a["id"])
				acts.append(_action("embark", "Board", "Board an army of %d units" % CState.unit_count(a), func(): s.embark(aid, id),
					CFleet.embark_check(ps, s.f, aid, id), "board"))
				break
		var first_join := -1
		for o in CFleet.fleets_of(ps, s.f):
			if int(o["id"]) != id and not CSea.is_flota(o) and CGrid.cheb(CFleet.cell(o), CFleet.cell(fl)) <= 1:
				var oid := int(o["id"])
				acts.append(_action("merge", "Join", "Join the fleet alongside (%d ships)" % (o["ships"] as Array).size(), func():
					s.join_fleet(id, oid), "", "join" if first_join < 0 else "join_%d" % oid))
				if first_join < 0:
					first_join = oid
	if mine and not flota:
		var port := CFleet.port_of(ps, fl, ff)
		var yt: Array = s.panels.ship_tab(port) if port >= 0 else [false, ""]
		if bool(yt[0]):
			acts.append(_action("shipyard", "Shipyard", "Build ships at %s" % CData.REGIONS[port]["city"],
				func(): s.panels.show_raise(port, "ship"), str(yt[1]), "shipyard"))
	acts.append(_details_action())
	var cw := _card_w(ships.size(), acts.size())
	var cards: Array = []
	for k in ships.size():
		var sh: Dictionary = ships[k]
		var row := CData.ship_row(str(sh["t"]))
		var c := UnitCard.new(cw, _card_h())
		c.name = "ship_card_%d" % k
		c.glyph = "ship"
		c.title = str(row.get("name", sh["t"]))
		c.men = int(sh["h"])
		c.full = 100
		c.bar2 = clampf(float(int(sh["c"])) / 100.0, 0.0, 1.0)
		c.sub = "%d%%  %d guns" % [int(sh["h"]), int(row.get("guns", 0))]
		c.col = CData.faction_color(ff)
		c.tooltip_text = "%s: hull %d%%, crew %d%%, %d guns, carries %d.\n%s" % [c.title, int(sh["h"]), int(sh["c"]), int(row.get("guns", 0)), int(row.get("cap", 0)), str(row.get("desc", ""))]
		c.pressed.connect(func(): s.show_toast(c.tooltip_text))
		cards.append(c)
	_assemble(leader, cards, [], acts)


# ------------------------------------------------------------- cards ---

## A unit (or ship) card: name, symbol in the side colour, tier pips,
## trait glyphs, strength bar with men / full.
class UnitCard extends Control:
	signal pressed
	signal long_pressed
	const LONG_PRESS_SEC := 0.5
	var ty := -1
	var glyph := ""            # a UI icon in place of a unit symbol (ships)
	var title := ""
	var men := 0               # -1: none (a planned recruit)
	var full := 1
	var bar2 := -1.0           # a second bar (crew), -1 none
	var col := Color(0.35, 0.6, 1.0)
	var faction := -1
	var selected := false
	var dim := false
	var sub := ""              # replaces "men/full" under the bar
	var pips := 0              # filled tier pips
	var _press_t := -1.0
	var _long_fired := false
	var _hits: Array = []
	var _tap_hint := ""

	func _init(w: float, h: float) -> void:
		custom_minimum_size = Vector2(w, h)
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_process(false)

	func _make_custom_tooltip(_for_text: String) -> Object:
		if ty < 0 or men < 0:
			return null
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", Kit.box(Kit.PANEL_BG, 6.0, 6))
		var row := Kit.UnitRow.new(ty, men, col)
		row.faction = faction
		p.add_child(row)
		return p

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_t = Time.get_ticks_msec() / 1000.0
				_long_fired = false
				_tap_hint = _hit_at(event.position)
				set_process(true)
			else:
				var inside := Rect2(Vector2.ZERO, size).has_point(event.position)
				var was := _press_t >= 0.0
				_press_t = -1.0
				set_process(false)
				if was and inside and not _long_fired and _tap_hint != "" and _tap_hint == _hit_at(event.position):
					Kit.show_hint(_tap_hint)
				elif was and inside and not _long_fired:
					pressed.emit()
			queue_redraw()
			accept_event()
		elif event is InputEventMouseMotion and _press_t >= 0.0:
			if not Rect2(Vector2.ZERO, size).has_point(event.position):
				_press_t = -1.0
				set_process(false)
				queue_redraw()

	## The drag helper took the press (a lifted card presses nothing).
	func cancel_press() -> void:
		_press_t = -1.0
		set_process(false)
		queue_redraw()

	func _hit_at(pos: Vector2) -> String:
		for h in _hits:
			if (h[0] as Rect2).grow(2).has_point(pos):
				return str(h[1])
		return ""

	func _process(_delta: float) -> void:
		if _press_t >= 0.0 and not _long_fired and Time.get_ticks_msec() / 1000.0 - _press_t >= LONG_PRESS_SEC:
			_long_fired = true
			_press_t = -1.0
			set_process(false)
			queue_redraw()
			long_pressed.emit()

	func _draw() -> void:
		var sz := size
		_hits = []
		var compact := sz.y < 90.0
		var a := 0.55 if dim else 1.0
		var bg := Color(1, 1, 1, 0.14) if selected else Color(1, 1, 1, 0.06)
		if _press_t >= 0.0:
			bg = Color(1, 1, 1, 0.24)
		draw_rect(Rect2(Vector2.ZERO, sz), bg)
		if selected:
			Kit.draw_trim(self, Rect2(Vector2.ZERO, sz), 2.0, 9.0)   # the gold trim: only the selected card has it
		var font := ThemeDB.fallback_font
		var fs := 10 if compact else 11
		draw_string(font, Vector2(3, fs + 2), title, HORIZONTAL_ALIGNMENT_CENTER, sz.x - 6, fs, Color(1, 1, 1, a))
		var r := 13.0 if compact else 17.0
		var cy := fs + 5 + r
		var cx := sz.x * 0.5
		if glyph != "":
			draw_circle(Vector2(cx, cy), r, Color(col, a))
			draw_arc(Vector2(cx, cy), r, 0, TAU, 20, Color(0, 0, 0, 0.75), 1.5, true)
			IconRaster.draw_icon(self, glyph, Rect2(cx - r * 0.75, cy - r * 0.75, r * 1.5, r * 1.5), Color(1, 1, 1, 0.95 * a))
		elif ty >= 0:
			Icons.draw_marker(self, Icons.icon_of(ty), Vector2(cx, cy), r, Color(col, a))
		# Tier pips down the left edge (the campaign has no experience: tier).
		for k in 3:
			var py := cy + (k - 1) * 8.0
			var on := (2 - k) < pips
			draw_circle(Vector2(6, py), 2.4, Color(1.0, 0.85, 0.3, a) if on else Color(1, 1, 1, 0.13))
		# Trait glyphs under the symbol.
		if ty >= 0 and (men >= 0 or sub != ""):
			var tl: Array = Traits.traits(ty, faction)
			var gs := 12.0 if compact else 14.0
			var n := mini(tl.size(), 3)
			var gx := cx - (n * (gs + 3.0) - 3.0) * 0.5
			var gy := cy + r + (3.0 if compact else 4.0)
			for k in n:
				var rc := Rect2(gx + k * (gs + 3.0), gy, gs, gs)
				IconRaster.draw_icon(self, str(Traits.TRAIT_ICONS[tl[k]]), rc, Color(1, 0.9, 0.6, a))
				# (no tap hint on a glyph: the middle of a card is where a finger lands; the hover row has the traits)
		# Strength bar and numbers.
		var bw := sz.x - 12.0
		var by := sz.y - (22.0 if compact else 26.0)
		if men >= 0:
			var frac := clampf(float(men) / full, 0.0, 1.0)
			var bc := Kit.COL_GOOD if frac > 0.66 else (Kit.COL_GOLD if frac > 0.33 else Kit.COL_BAD)
			draw_rect(Rect2(6, by, bw, 7), Color(1, 1, 1, 0.14))
			draw_rect(Rect2(6, by, bw * frac, 7), Color(bc, 0.85 * a))
			if bar2 >= 0.0:
				draw_rect(Rect2(6, by + 9, bw, 4), Color(1, 1, 1, 0.14))
				draw_rect(Rect2(6, by + 9, bw * bar2, 4), Color(0.6, 0.75, 1.0, 0.85 * a))
		var t := "%d/%d" % [men, full] if sub == "" else sub
		if men < 0 and sub == "":
			t = ""
		draw_string(font, Vector2(3, sz.y - 3), t, HORIZONTAL_ALIGNMENT_CENTER, sz.x - 6, fs, Color(Kit.COL_DIM, a))
