extends Node
## The campaign screen: map, panels, dialogs, and the session flow (solo or
## two players on one device). It reads the campaign state and only changes
## it through campaign/cturn.gd: the player's plan is a list of orders
## (crules.gd) previewed on a copy of the state; End turn turns the plan into
## a submission (cturn.submission: exactly what milestone 4 will upload);
## when every player has submitted, resolve_turn runs. Pending battles are
## resolved first (auto-resolve with the real sim, or fought in the battle
## view) through cturn.apply_battle.
##
## Hot seat: the players plan one after the other with a hand-over screen in
## between; "session" (saved with the state, not part of it) holds the
## submissions made so far this turn, each player's unfinished plan and the
## turn each player last saw (for "since you last played").
##
## Online (milestone 4): `online` is the seat's game/net/online_campaign.gd;
## online_ui.gd runs the turn flow against the server (Submit turn, waiting
## for the ally, claims on battles, results uploaded instead of applied
## locally). Local solo and hot-seat play are unchanged.

signal exit_requested

const TouchScroll := preload("res://game/touch_scroll.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const UT := preload("res://sim/unit_types.gd")
const Geo := preload("res://game/campaign/map_geo.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const MapOverlay := preload("res://game/campaign/map_overlay.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const Saves := preload("res://game/campaign/saves.gd")
const Panels := preload("res://game/campaign/campaign_panels.gd")
const AutoResolve := preload("res://game/campaign/auto_resolve.gd")
const Battle := preload("res://game/battle.gd")
const UnitBook := preload("res://game/unit_book.gd")
const UnitEntry := preload("res://game/unit_entry.gd")
const Controls := preload("res://game/controls.gd")
const OnlineUI := preload("res://game/campaign/online_ui.gd")
const CoopSession := preload("res://game/net/coop_session.gd")

const ZOOM_MIN := 0.2
const ZOOM_MAX := 2.5
const DRAG_THRESHOLD := 14.0
const PANEL_W := 360.0
const TOP_H := 46.0

## Campaign data: {"state", "session", "meta"} (see saves.gd).
var data: Dictionary = {}
var slot := ""
var st: Dictionary = {}        # the shared state
var ps: Dictionary = {}        # preview: st with the current plan applied
var f := -1                    # faction planning now
var orders: Array = []
var moves: Array = []          # planned moves [[army, to]]
var sel_army := -1
var sel_region := -1
var zoom := 0.6
var offset := Vector2.ZERO     # screen = map * zoom + offset

var world: Node2D
var map_view: MapView
var overlay: MapOverlay
var ui: Control
var top_label: Label
var top_box: HBoxContainer
var side: PanelContainer
var side_box: VBoxContainer
var side_scroll: ScrollContainer
var end_button: Button
var battles_button: Button
var hint: Label
var dialog: PanelContainer
var dialog_box: VBoxContainer
var dialog_title: Label
var dialog_buttons: HBoxContainer
var dialog_scroll: ScrollContainer
var cover: ColorRect
var book: UnitBook
var controls_page: Controls
var panels: Panels
var battle: Battle = null
var _battle_built: Dictionary = {}
var _battle_id := -1
var _resolver: AutoResolve = null
var _progress: ProgressBar = null
var _plan_start_ms := 0
var _tele: Node = null
var online = null              # game/net/online_campaign.gd when playing online
var onl: OnlineUI = null
var net_button: Button
var wait_panel: PanelContainer
var dialog_kind := ""          # what the open dialog is (online flow re-renders its own)

# Gestures.
var _touches := {}
var _press_pos := Vector2.ZERO
var _dragging := false
var _multi := false
var _pinch_d := 0.0
var _pinch_mid := Vector2.ZERO
var _mouse_pan := false


func _ready() -> void:
	_tele = get_node_or_null("/root/Telemetry")
	panels = Panels.new(self)
	world = Node2D.new()
	add_child(world)
	map_view = MapView.new()
	world.add_child(map_view)
	var ol := CanvasLayer.new()
	ol.layer = 1
	add_child(ol)
	overlay = MapOverlay.new()
	ol.add_child(overlay)
	var ul := CanvasLayer.new()
	ul.layer = 2
	add_child(ul)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ul.add_child(ui)
	_build_ui()
	book = UnitBook.new()
	ui.add_child(book)
	controls_page = Controls.new()
	ui.add_child(controls_page)
	if online != null:
		_load_online()
	elif not data.is_empty():
		_load_data()


## Open a campaign (data from saves.gd or a new one).
func open(p_data: Dictionary, p_slot: String) -> void:
	data = p_data
	slot = p_slot
	if is_inside_tree():
		_load_data()


## Open an online campaign (its controller has been created by Net; this
## screen opens it).
func open_online(oc) -> void:
	online = oc
	slot = ""
	data = {"state": oc.st, "session": {"subs": [], "plans": {}, "seen": {}}}
	if is_inside_tree():
		_load_online()


func _load_online() -> void:
	onl = OnlineUI.new(self, online)
	net_button.visible = true
	st = online.st
	_t("online_open", {"campaign": online.id, "f": online.f})
	onl.step()
	online.open()
	call_deferred("_apply_debug_args")


func _load_data() -> void:
	st = data["state"]
	if not data.has("session"):
		data["session"] = {}
	var ses: Dictionary = data["session"]
	if not ses.has("subs"):
		ses["subs"] = []
	for k in ["plans", "seen"]:
		if not ses.has(k):
			ses[k] = {}
	_t("campaign_open", {"turn": int(st["turn"]), "humans": st["humans"], "slot": slot})
	_next_step()
	call_deferred("_apply_debug_args")


## Testing aids: --cam-zoom=Z --cam-region=key --close-dialog
## --select-region=key --select-army=N (Nth army of the player)
## --plan-move=N:key --camp-attack=N:key --camp-fight --sim-turns=N --dialog-scroll=PX
## --dialog=battles|summary|diplomacy|realm|goals|warnings|online|citymap
func _apply_debug_args() -> void:
	for a in OS.get_cmdline_user_args():
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--cam-zoom="):
			zoom = float(v)
			focus_region(sel_region if sel_region >= 0 else CData.region_index(str(CData.FACTIONS[maxi(f, 0)]["capital"])))
		elif a.begins_with("--cam-region="):
			focus_region(CData.region_index(v))
		elif a == "--close-dialog":
			close_dialog()
		elif a.begins_with("--dialog-scroll="):
			await get_tree().create_timer(1.5).timeout
			dialog_scroll.scroll_vertical = int(v)  # testing aid
		elif a == "--debug-xform":
			print("world ", world.get_global_transform_with_canvas(), " overlay ", overlay.get_global_transform_with_canvas(), " vp ", _vp(), " zoom ", zoom, " off ", offset, " roma ", Geo.site(0), " -> ", overlay.to_screen(Geo.site(0)))
		elif a.begins_with("--select-region="):
			select_region(CData.region_index(v))
		elif a.begins_with("--select-army="):
			var mine := CState.armies_of(ps, f)
			if int(v) < mine.size():
				select_army(int(mine[int(v)]["id"]))
		elif a.begins_with("--plan-move="):
			var mine2 := CState.armies_of(ps, f)
			var k := int(v.get_slice(":", 0))
			if k < mine2.size():
				set_move(int(mine2[k]["id"]), CData.region_index(v.get_slice(":", 1)))
		elif a.begins_with("--sim-turns="):
			# Advance N turns with the players holding (battles by formula).
			for k in int(v):
				st = CTurn.resolve_turn(st, [])
				while not (st["battles"] as Array).is_empty():
					var b: Dictionary = st["battles"][0]
					st = CTurn.apply_battle(st, int(b["id"]), CBattle.formula(st, b))
			data["session"] = {"subs": [], "plans": {}, "seen": {}}
			_next_step()
		elif a.begins_with("--explain="):
			explain_refusal(sel_army, CData.region_index(v))  # testing aid
		elif a.begins_with("--live-open=") or a.begins_with("--live-join="):
			# Testing aid: open / join the live room of battle N once the
			# online state is here.
			for i in 100:
				if online != null and not online.st.is_empty() and not online.summary.is_empty():
					break
				await get_tree().create_timer(0.1).timeout
			if online != null:
				await online.sync()
				fight_live(int(v), a.begins_with("--live-open="))
		elif a == "--camp-fight":
			var pb := CTurn.pending_for(st)
			if not pb.is_empty():
				fight(int(pb[0]["id"]))
		elif a.begins_with("--camp-attack="):
			# --camp-attack=N:region: the player's Nth army attacks now (war if needed).
			var mine3 := CState.armies_of(st, f)
			var to := CData.region_index(v.get_slice(":", 1))
			var a3: Dictionary = mine3[int(v.get_slice(":", 0))]
			var o := CState.owner(st, to)
			if o >= 0 and not CState.at_war(st, f, o):
				CRules.declare_war(st, f, o)
			a3["r"] = to
			a3["from"] = -1
			a3["moved"] = 1
			CRules.add_reinforcements(st, CRules.start_battle(st, to, a3))
			st["phase"] = "battles"
			_next_step()
		elif a.begins_with("--dialog="):
			match v:
				"battles":
					panels.show_battles()
				"summary":
					panels.show_summary(-1)
				"diplomacy":
					panels.show_diplomacy()
				"realm":
					panels.show_faction()
				"goals":
					panels.show_objectives()
				"citymap":
					panels.show_city_map(sel_region if sel_region >= 0 else 0)
				"warnings":
					panels.show_warnings(panels.warnings())
				"online":
					if onl != null:
						await get_tree().create_timer(1.0).timeout
						onl.show_online()


func _t(kind: String, d: Dictionary) -> void:
	if _tele != null:
		_tele.event(kind, d)


func request_exit() -> void:
	exit_requested.emit()


func save() -> void:
	if online != null:
		if f >= 0 and not st.is_empty() and str(st.get("phase", "")) == "plan" and not online.i_submitted():
			online.set_plan(orders)
		return
	if f >= 0:
		data["session"]["plans"][str(f)] = orders.duplicate(true)
	data["state"] = st
	if not Saves.save(slot, data):
		_t("campaign_error", {"what": "save failed", "slot": slot})


# ----------------------------------------------------------------- flow ---

## Decide what happens next: game over, pending battles, the next player's
## planning (after a hand-over in hot seat), or resolving the turn.
func _next_step() -> void:
	if online != null:
		onl.step()
		return
	close_dialog()
	if str(st["phase"]) == "over":
		f = -1
		_refresh()
		panels.show_game_over()
		return
	var pending := CTurn.pending_for(st)
	if not pending.is_empty():
		f = int(CRules.battle_humans(st, pending[0])[0])
		_set_planner(f, false)
		var seen := int(data["session"]["seen"].get(str(f), -1))
		# Setting "always auto-resolve": no choice dialog.
		var then := func(): panels.show_battles()
		if str(st["settings"].get("autoresolve", "ask")) == "auto":
			var bid := int(pending[0]["id"])
			then = func(): auto_resolve(bid)
		if seen < int(st["turn"]) and int(st["turn"]) > 0:
			data["session"]["seen"][str(f)] = int(st["turn"])
			save()
			panels.show_summary(seen, then)
		else:
			then.call()
		return
	var subs: Array = data["session"]["subs"]
	var next := -1
	for h in st["humans"]:
		var done := false
		for s in subs:
			if int(s["f"]) == int(h) and int(s["turn"]) == int(st["turn"]):
				done = true
		if not done and CState.alive(st, int(h)):
			next = int(h)
			break
	if next < 0:
		_resolve_turn()
		return
	var hot := (st["humans"] as Array).size() > 1
	if hot and f != next:
		f = next
		_show_handover()
		return
	_set_planner(next, true)


func _set_planner(p_f: int, start: bool) -> void:
	f = p_f
	orders = []
	if online != null:
		orders = online.plan_orders()
		var sub = online.session.get("submitted", {})
		if online.i_submitted() and sub is Dictionary and int(sub.get("turn", -1)) == int(st["turn"]):
			orders = (sub["orders"] as Array).duplicate(true)
		start = false
	elif data["session"]["plans"].has(str(f)):
		orders = (data["session"]["plans"][str(f)] as Array).duplicate(true)
	sel_army = -1
	sel_region = -1
	_replan()
	if start:
		_plan_start_ms = Time.get_ticks_msec()
		var seen := int(data["session"]["seen"].get(str(f), -1))
		if seen < int(st["turn"]):
			if int(st["turn"]) > 0 or not (st["events"] as Array).is_empty():
				panels.show_summary(seen)
			else:
				panels.show_intro()
			data["session"]["seen"][str(f)] = int(st["turn"])
			save()
		_focus_faction()


func _show_handover() -> void:
	cover.visible = true
	close_side()
	var box := Kit.vbox(12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var sw := Kit.hbox(10)
	sw.alignment = BoxContainer.ALIGNMENT_CENTER
	sw.add_child(Kit.swatch(CData.faction_color(f), 26))
	sw.add_child(Kit.label("%s's turn" % CData.faction_name(f), 26))
	box.add_child(sw)
	box.add_child(Kit.label("Pass the device to the %s player. %s." % [CData.FACTIONS[f]["adj"], CData.date_text(int(st["turn"]))], 16, Kit.COL_DIM))
	show_dialog("", box, [["Start my turn", func():
		cover.visible = false
		_set_planner(f, true)]])


func end_turn(skip_warnings: bool = false) -> void:
	if f < 0 or not CTurn.pending_for(st).is_empty():
		return
	if online != null and online.i_submitted():
		return
	if not skip_warnings:
		var warn := panels.warnings()
		if not warn.is_empty():
			panels.show_warnings(warn)
			return
	if online != null:
		online.set_plan(orders)
		onl.submit(orders.duplicate(true))
		return
	var sub := CTurn.submission(st, f, orders)
	(data["session"]["subs"] as Array).append(sub)
	data["session"]["plans"].erase(str(f))
	_t("campaign_turn_submitted", {"turn": int(st["turn"]), "f": f, "orders": orders.size(),
		"planning_s": (Time.get_ticks_msec() - _plan_start_ms) / 1000.0, "base": sub["base"]})
	orders = []
	save()
	_next_step()


func _resolve_turn() -> void:
	var subs: Array = data["session"]["subs"]
	var t0 := Time.get_ticks_msec()
	st = CTurn.resolve_turn(st, subs)
	data["session"]["subs"] = []
	data["session"]["plans"] = {}
	_t("campaign_turn_resolved", {"turn": int(st["turn"]), "ms": Time.get_ticks_msec() - t0,
		"hash": CState.hash_text(st), "battles": (st["battles"] as Array).size()})
	f = -1
	save()
	_next_step()


# ------------------------------------------------------------- planning ---

## Re-run the preview of the plan; drop orders that no longer apply.
func _replan() -> void:
	if f < 0:
		ps = st
		moves = []
		_refresh()
		return
	for guard in 8:
		var pv := CTurn.preview(st, f, orders)
		var errs: Array = pv["errors"]
		if errs.is_empty():
			ps = pv["state"]
			moves = pv["moves"]
			break
		var bad: Array = []
		for e in errs:
			bad.append(int(e[0]))
		var keep: Array = []
		for i in orders.size():
			if not bad.has(i):
				keep.append(orders[i])
		orders = keep
	_refresh()


func add_order(o: Dictionary) -> String:
	var pv := CTurn.preview(st, f, orders + [o])
	for e in pv["errors"]:
		if int(e[0]) == orders.size():
			_flash(str(e[1]))
			return str(e[1])
	orders.append(o)
	_replan()
	save()
	return ""


func remove_orders(pred: Callable) -> void:
	var keep: Array = []
	for o in orders:
		if not pred.call(o):
			keep.append(o)
	orders = keep
	_replan()
	save()


func planned_move(army: int) -> int:
	for m in moves:
		if int(m[0]) == army:
			return int(m[1])
	return -1


func set_move(army: int, to: int) -> void:
	var cur := planned_move(army)
	remove_orders(func(o): return str(o["t"]) == "move" and int(o["army"]) == army)
	if cur == to:
		_t("campaign_input", {"what": "move_cancel"})
		return
	add_order({"t": "move", "army": army, "to": to})
	_t("campaign_input", {"what": "move"})


## Why the selected army cannot move to region r, and what to do about it,
## as a toast (with a Diplomacy shortcut when peace is the reason).
func explain_refusal(army: int, r: int) -> void:
	var a := CState.army(ps, army)
	var why := CRules.can_move(ps, a, r)
	var o := CState.owner(ps, r)
	var reg := str(CData.REGIONS[r]["name"])
	var text := ""
	var action := []
	if why.begins_with("at peace"):
		var d := CState.dip(ps, f, o)
		text = "%s belongs to %s. You are at %s with them: declare war in Diplomacy to attack. War is declared before armies move, so you can attack this same turn." % [
			reg, CData.faction_name(o), "peace" if d == CState.PEACE else "peace and trade"]
		action = ["Diplomacy", func(): panels.show_diplomacy(o)]
	elif why == "already moved":
		text = "This army has already moved this turn."
	elif why == "in a battle":
		text = "This army is in a battle: resolve it first (Battles)."
		action = ["Battles", func(): panels.show_battles()]
	elif why == "battle pending there":
		text = "A battle is pending in %s: no other army can enter until it is resolved." % reg
	elif why == "not adjacent":
		text = "%s is not next to this army: one region or one sea lane a turn." % reg
	else:
		text = "Cannot move to %s: %s." % [reg, why]
	_t("campaign_input", {"what": "move_refused", "why": why})
	show_toast(text, action)


var _toast: PanelContainer = null


## A short message above the bottom edge (stays 6 s or until tapped away),
## with an optional [label, callable] button.
func show_toast(text: String, action: Array = []) -> void:
	if _toast != null:
		_toast.queue_free()
	_toast = Kit.panel(Color(0.12, 0.1, 0.08, 0.96), 10)
	_toast.name = "toast"
	var h := Kit.hbox(8)
	_toast.add_child(h)
	var l := Kit.label(text, Kit.FONT, Color(1, 0.92, 0.8), true)
	# Fits left of the side panel when it is open.
	var room := _vp().x - (side.size.x + 16.0 if side.visible else 0.0) - 16.0
	l.custom_minimum_size.x = clampf(room - 200.0, 180.0, 520.0)
	h.add_child(l)
	if not action.is_empty():
		var cb: Callable = action[1]
		var b := Kit.button(str(action[0]), func():
			if _toast != null:
				_toast.queue_free()
				_toast = null
			cb.call(), 110)
		b.name = "toast_action"
		h.add_child(b)
	var x := Kit.button("OK", func():
		if _toast != null:
			_toast.queue_free()
			_toast = null, 56)
	h.add_child(x)
	ui.add_child(_toast)
	ui.move_child(_toast, end_button.get_index())
	_toast.reset_size()
	var vp := _vp()
	_toast.position = Vector2(8, vp.y - _toast.size.y - 64)
	var me := _toast
	get_tree().create_timer(6.0).timeout.connect(func():
		if is_instance_valid(me) and me == _toast:
			me.queue_free()
			_toast = null)


func _flash(text: String) -> void:
	hint.text = text
	hint.modulate = Color(1, 0.7, 0.6)
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_callback(func(): hint.modulate = Color(1, 1, 1); _update_hint())


# ------------------------------------------------------------------- UI ---

func _build_ui() -> void:
	# Top bar.
	var top := Kit.panel(Color(0.08, 0.09, 0.08, 0.92), 4)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = TOP_H
	ui.add_child(top)
	top_box = Kit.hbox(5)
	top.add_child(top_box)
	top_label = Kit.label("", Kit.FONT)
	top_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_label.clip_text = true
	top_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_label.mouse_filter = Control.MOUSE_FILTER_STOP
	top_label.gui_input.connect(func(e):
		if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			panels.show_faction())
	top_box.add_child(top_label)
	net_button = Kit.button("Online", func():
		if onl != null:
			onl.show_online(), 0)
	net_button.name = "net_status"
	net_button.visible = false
	net_button.clip_text = true
	net_button.custom_minimum_size.x = 96
	top_box.add_child(net_button)
	battles_button = Kit.button("Battles", func(): panels.show_battles(), 0)
	top_box.add_child(battles_button)
	top_box.add_child(Kit.button("Realm", func(): panels.show_faction(), 0))
	top_box.add_child(Kit.button("Diplomacy", func(): panels.show_diplomacy(), 0))
	top_box.add_child(Kit.button("Goals", func(): panels.show_objectives(), 0))
	top_box.add_child(Kit.button("Units", func(): book.open(), 0))
	top_box.add_child(Kit.button("Menu", func(): panels.show_menu(), 0))
	# Side panel (right).
	side = Kit.panel(Kit.PANEL_BG, 8)
	side.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -PANEL_W
	side.offset_top = TOP_H + 4
	side.offset_bottom = -62  # clear of End turn
	side.offset_right = -4
	side.visible = false
	ui.add_child(side)
	side_scroll = TouchScroll.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(side_scroll)
	side_box = Kit.vbox(6)
	side_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(side_box)
	# Bottom: hint (left), End turn (right).
	hint = Kit.label("", Kit.FONT_SMALL, Color(1, 1, 1), true)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position = Vector2(8, 0)
	hint.offset_bottom = -8
	hint.offset_right = 420
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 5)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hint)
	end_button = Kit.button("End turn", func(): end_turn(), 130, 17)
	end_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	end_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	end_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	end_button.offset_right = -8
	end_button.offset_bottom = -8
	end_button.custom_minimum_size = Vector2(130, 48)
	ui.add_child(end_button)
	wait_panel = Kit.panel(Color(0.1, 0.12, 0.1, 0.95), 8)
	wait_panel.name = "wait_panel"
	wait_panel.visible = false
	ui.add_child(wait_panel)
	# Cover (hand-over) and dialog.
	cover = ColorRect.new()
	cover.color = Color(0.06, 0.07, 0.06, 1.0)
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.visible = false
	ui.add_child(cover)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.visible = false
	ui.add_child(dim)
	dialog = Kit.panel(Color(0.1, 0.12, 0.11, 0.98), 12)
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	dialog.visible = false
	dialog.set_meta("dim", dim)
	ui.add_child(dialog)
	var dv := Kit.vbox(8)
	dialog.add_child(dv)
	dialog_title = Kit.label("", Kit.FONT_TITLE, Kit.COL_GOLD)
	dv.add_child(dialog_title)
	dialog_scroll = TouchScroll.new()
	dialog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(dialog_scroll)
	dialog_box = Kit.vbox(6)
	dialog_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_scroll.add_child(dialog_box)
	dialog_buttons = Kit.hbox(8)
	dialog_buttons.alignment = BoxContainer.ALIGNMENT_END
	dv.add_child(dialog_buttons)


func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


## Show a modal dialog. buttons: [[text, callable], ...]; an empty callable
## just closes. The dialog fills most of a phone screen and is capped on a
## desktop.
func show_dialog(title: String, content: Control, buttons: Array, width: float = 620.0) -> void:
	for c in dialog_box.get_children():
		dialog_box.remove_child(c)
		c.queue_free()
	for c in dialog_buttons.get_children():
		dialog_buttons.remove_child(c)
		c.queue_free()
	dialog_title.text = title
	dialog_title.visible = title != ""
	dialog_box.add_child(content)
	for bdef in buttons:
		var cb: Callable = bdef[1]
		var b := Kit.button(str(bdef[0]), func():
			if cb.is_valid():
				cb.call()
			else:
				close_dialog(), 110)
		b.name = "dlg_" + str(bdef[0]).replace(" ", "_")
		dialog_buttons.add_child(b)
	var vp := _vp()
	var w := minf(width, vp.x - 24)
	var h := minf(vp.y - 24, maxf(260.0, vp.y * 0.86))
	dialog.custom_minimum_size = Vector2(w, 0)
	dialog_scroll.custom_minimum_size = Vector2(w - 24, 0)
	dialog_scroll.set_meta("max_h", minf(h - 110, 560))
	dialog.size = Vector2(w, 0)
	dialog.reset_size()
	dialog.position = (vp - dialog.size) * 0.5
	dialog.visible = true
	dialog_kind = ""
	(dialog.get_meta("dim") as Control).visible = true
	dialog_scroll.scroll_vertical = 0
	call_deferred("_center_dialog")


func _center_dialog() -> void:
	# The scroll area takes the content's height, up to the screen.
	var want := dialog_box.get_combined_minimum_size().y
	dialog_scroll.custom_minimum_size.y = minf(want, float(dialog_scroll.get_meta("max_h", 400.0)))
	dialog.reset_size()
	dialog.position = (_vp() - dialog.size) * 0.5


func close_dialog() -> void:
	dialog.visible = false
	(dialog.get_meta("dim") as Control).visible = false


func dialog_open() -> bool:
	return dialog.visible


func show_side(content_builder: Callable) -> void:
	for c in side_box.get_children():
		side_box.remove_child(c)
		c.queue_free()
	content_builder.call(side_box)
	var pad := Control.new()  # room after the last row
	pad.custom_minimum_size.y = 24
	side_box.add_child(pad)
	var vp := _vp()
	var w := minf(PANEL_W, vp.x * 0.48)
	side.offset_left = -w - 4
	side.visible = true
	side_scroll.scroll_vertical = 0


func close_side() -> void:
	side.visible = false
	sel_army = -1
	sel_region = -1
	_refresh_map()


## Unit book page as a recruitment card: the UnitEntry view with a Recruit
## button.
func open_unit_page(ty: int, recruit_cb: Callable, recruit_text: String) -> void:
	var entry := UnitEntry.new()
	entry.custom_minimum_size = Vector2(0, minf(_vp().y * 0.62, 520))
	entry.set_unit_type(ty, CData.faction_color(f))
	var btns: Array = [["Close", Callable()]]
	if recruit_cb.is_valid():
		btns.push_front([recruit_text, func():
			recruit_cb.call()
			close_dialog()])
	show_dialog(str(UT.TYPES[ty]["name"]), entry, btns, 900)


func _refresh() -> void:
	_refresh_top()
	_refresh_map()
	_update_hint()
	if side.visible:
		if sel_army >= 0 and not CState.army(ps, sel_army).is_empty():
			show_side(func(box): panels.army_panel(box, sel_army))
		elif sel_region >= 0:
			show_side(func(box): panels.region_panel(box, sel_region))
		else:
			side.visible = false


func _refresh_top() -> void:
	if st.is_empty():
		return
	var fs := f if f >= 0 else (int(st["humans"][0]) if not (st["humans"] as Array).is_empty() else 0)
	var inc := CRules.income(ps, fs)
	var up := CRules.upkeep(ps, fs)
	top_label.text = "  %s   %s   Treasury %s (%+d)" % [CData.faction_name(fs), CData.date_text(int(st["turn"])),
		Kit.money(int(ps["factions"][fs]["treasury"])), int(inc["total"]) - up]
	top_label.add_theme_color_override("font_color", CData.faction_color(fs).lightened(0.45))
	var nb := CTurn.pending_for(st).size()
	battles_button.text = "Battles (%d)" % nb if nb > 0 else "Battles"
	battles_button.modulate = Color(1, 0.6, 0.5) if nb > 0 else Color(1, 1, 1)
	end_button.disabled = nb > 0 or f < 0 or str(st["phase"]) == "over"
	if onl != null:
		var eb := onl.end_button_state()
		end_button.text = str(eb[0])
		end_button.disabled = bool(eb[1]) or nb > 0


func _update_hint() -> void:
	if st.is_empty() or f < 0:
		hint.text = ""
		return
	if not CTurn.pending_for(st).is_empty():
		hint.text = "Resolve the pending battles first (Battles)."
	elif online != null and online.i_submitted():
		hint.text = "Turn submitted. You can look around; Unsubmit to change your orders."
	elif sel_army >= 0:
		hint.text = "Tap a highlighted region to move there (red: attack; dark: not allowed, tap for why). Tap it again to cancel."
	else:
		hint.text = "Tap an army to move it, a region for buildings and recruits."


func _refresh_map() -> void:
	map_view.state = ps
	overlay.state = ps
	overlay.player = f
	overlay.selected_army = sel_army
	overlay.moves = moves
	var att: Array[int] = []
	for m in moves:
		var o := CState.owner(ps, int(m[1]))
		if CState.at_war(ps, f, o):
			att.append(int(m[0]))
	overlay.attack_moves = att
	map_view.targets = []
	map_view.attack_targets = []
	map_view.blocked_targets = []
	if sel_army >= 0:
		var a := CState.army(ps, sel_army)
		if not a.is_empty() and int(a["f"]) == f:
			var tg := CRules.move_targets(ps, a) if int(a["busy"]) == 0 else ([] as Array[int])
			var bl: Array[int] = []
			for e in CData.adjacent(int(a["r"])):
				if not tg.has(int(e[0])) and planned_move(sel_army) != int(e[0]):
					bl.append(int(e[0]))
			map_view.blocked_targets = bl
			map_view.targets = tg
			var at: Array[int] = []
			for r in tg:
				if CState.at_war(ps, f, CState.owner(ps, r)):
					at.append(r)
			map_view.attack_targets = at
	map_view.selected_region = sel_region
	map_view.queue_redraw()
	overlay.queue_redraw()


func select_army(id: int) -> void:
	sel_army = id
	var a := CState.army(ps, id)
	sel_region = -1
	if not a.is_empty():
		show_side(func(box): panels.army_panel(box, id))
	_refresh_map()
	_update_hint()


func select_region(r: int) -> void:
	sel_region = r
	sel_army = -1
	show_side(func(box): panels.region_panel(box, r))
	_refresh_map()
	_update_hint()


func focus_region(r: int, z: float = -1.0) -> void:
	if z > 0.0:
		zoom = z
	var vp := _vp()
	var clear_w := vp.x - (PANEL_W if side.visible else 0.0)
	offset = Vector2(clear_w * 0.5, (vp.y + TOP_H) * 0.5) - Geo.site(r) * zoom
	_clamp_view()


func _focus_faction() -> void:
	var cap := CData.region_index(str(CData.FACTIONS[f]["capital"]))
	if CState.owner(st, cap) != f:
		var mine := CState.regions_of(st, f)
		if not mine.is_empty():
			cap = mine[0]
	focus_region(cap, 0.7 if _vp().x < 1200 else 0.9)


# ------------------------------------------------------------ battles ---

func auto_resolve(bid: int) -> void:
	var b := CState.battle(st, bid)
	if b.is_empty() or _resolver != null:
		return
	if online != null and not await onl.claim(bid, "auto"):
		return
	b = CState.battle(st, bid)
	if b.is_empty() or _resolver != null:
		return
	_resolver = AutoResolve.new()
	add_child(_resolver)
	_resolver.start(st, b)
	_battle_id = bid
	var box := Kit.vbox(10)
	box.add_child(Kit.label("Auto-resolving the battle at %s: both armies under the battle AI%s." % [
		CData.REGIONS[int(b["r"])]["city"], " (big battle: fast mode, half-size units)" if _resolver.scale < 100 else ""], Kit.FONT, Color.WHITE, true))
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(300, 26)
	_progress.max_value = 1.0
	_progress.step = 0.001
	_progress.show_percentage = false
	box.add_child(_progress)
	show_dialog("Battle of %s" % CData.REGIONS[int(b["r"])]["city"], box, [])
	_resolver.finished.connect(_on_auto_done)


func _process(delta: float) -> void:
	map_view.pulse += delta
	overlay.pulse += delta
	if _resolver != null and _progress != null:
		_progress.value = _resolver.progress
	world.position = offset
	world.scale = Vector2(zoom, zoom)
	map_view.zoom = zoom
	overlay.zoom = zoom
	var xf := Transform2D(0.0, Vector2(zoom, zoom), 0.0, offset)
	if xf != overlay.xform:
		overlay.xform = xf
		overlay.queue_redraw()
		map_view.queue_redraw()  # line widths follow the zoom
	if sel_army >= 0 or not moves.is_empty() or not map_view.targets.is_empty():
		map_view.queue_redraw()
		overlay.queue_redraw()
	_keys(delta)


func _on_auto_done(outcome: Dictionary) -> void:
	var b := CState.battle(st, _battle_id)
	_t("campaign_battle", {"mode": "auto", "turn": int(st["turn"]), "region": int(b.get("r", -1)),
		"ms": int(outcome.get("wall_ms", 0)), "scale": int(outcome.get("scale", 100)),
		"ticks": int(outcome.get("ticks", 0)), "winner": int(outcome["winner"])})
	_resolver.queue_free()
	_resolver = null
	_progress = null
	_apply_battle(_battle_id, outcome)


func _apply_battle(bid: int, outcome: Dictionary) -> void:
	if online != null:
		onl.upload(bid, outcome)
		_after_battle_refresh()
		return
	var before := (st["events"] as Array).size()
	st = CTurn.apply_battle(st, bid, outcome)
	save()
	_replan()
	panels.show_battle_result(before, outcome)


func fight(bid: int) -> void:
	var b := CState.battle(st, bid)
	if b.is_empty() or battle != null:
		return
	if online != null and not await onl.claim(bid, "fight"):
		return
	b = CState.battle(st, bid)
	if b.is_empty() or battle != null:
		return
	var hs := CRules.battle_humans(st, b)
	var hf: int = f if hs.has(f) else int(hs[0])
	_battle_built = CBattle.build(st, b, hf)
	_battle_id = bid
	battle = Battle.new()
	battle.custom_scenario = _battle_built["scenario"]
	battle.seed_value = int(_battle_built["seed"])
	battle.scenario_id = "campaign"
	battle.campaign_mode = true
	battle.exit_requested.connect(_on_battle_exit)
	close_dialog()
	_set_visible(false)
	_t("campaign_battle_start", {"turn": int(st["turn"]), "region": int(b["r"]), "units": (_battle_built["map"] as Array).size()})
	get_tree().root.add_child.call_deferred(battle)


## Server changes that arrived during a battle are shown afterwards.
func _after_battle_refresh() -> void:
	if online != null and has_meta("refresh_after_battle"):
		remove_meta("refresh_after_battle")
		st = online.st
		_replan()


func _set_visible(on: bool) -> void:
	world.visible = on
	overlay.visible = on
	ui.visible = on
	set_process_unhandled_input(on)


## A live co-op battle (milestone 5): open its room (create, the host) or
## join the open one, built from the campaign version the room was opened
## at. keep: let the host keep command of this player's units.
func fight_live(bid: int, create: bool, keep: bool = false) -> void:
	var b := CState.battle(st, bid)
	if b.is_empty() or battle != null or online == null:
		return
	var v: int = online.version
	var bst: Dictionary = st
	var live = online.battle_info(bid).get("live")
	if not create and live is Dictionary and int(live.get("version", v)) != v:
		v = int(live["version"])
		bst = await online.state_at(v)
		if bst.is_empty():
			show_toast("Could not load the campaign as it was when this battle started. Try again.")
			return
		b = CState.battle(bst, bid)
		if b.is_empty():
			return
	if battle != null:
		return
	var hs: Array = CRules.battle_humans(bst, b)
	var hmin := int(hs.min()) if not hs.is_empty() else f
	_battle_built = CBattle.build(bst, b, hmin)
	_battle_id = bid
	var net := get_node_or_null("/root/Net")
	var coop = CoopSession.new()
	add_child(coop)
	coop.setup(net.api.base_url if net != null else "", online.id, online.token, online.f, _battle_built, hs, v, create, keep)
	coop.failed.connect(func(code: String, text: String): _coop_failed(code, text))
	battle = Battle.new()
	battle.custom_scenario = _battle_built["scenario"]
	battle.seed_value = int(_battle_built["seed"])
	battle.scenario_id = "campaign_live"
	battle.campaign_mode = true
	battle.coop = coop
	battle.coop_region = str(CData.REGIONS[int(b["r"])]["city"])
	battle.exit_requested.connect(_on_battle_exit)
	close_dialog()
	_set_visible(false)
	_t("campaign_battle_start", {"turn": int(st["turn"]), "region": int(b["r"]), "units": (_battle_built["map"] as Array).size(),
		"live": true, "create": create})
	get_tree().root.add_child.call_deferred(battle)


func _coop_failed(code: String, text: String) -> void:
	var msg := text
	match code:
		"no_room":
			msg = "Nobody is fighting this battle live any more."
		"claimed":
			msg = "Your ally is resolving this battle right now."
		"stale":
			msg = "The campaign moved on; try again."
		"not_pending":
			msg = "This battle has been resolved."
	if battle != null and battle.coop != null:
		battle.coop.leave()
		var c = battle.coop
		get_tree().create_timer(2.0).timeout.connect(func(): if is_instance_valid(c): c.queue_free())
		battle.queue_free()
		battle = null
		_set_visible(true)
	show_toast(msg)
	if online != null:
		await online.sync()
		_after_battle_refresh()
		if onl != null:
			onl.show_battles()


func _on_battle_exit() -> void:
	if battle.coop != null:
		_on_coop_exit()
		return
	var res: Dictionary = battle.sim.result()
	var decided := battle.is_decided()
	var outcome: Dictionary
	if decided:
		outcome = CBattle.outcome_from_result(_battle_built, res, "fought")
	else:
		outcome = CBattle.outcome_forfeit(_battle_built, res)
	_t("campaign_battle", {"mode": "fought" if decided else "forfeit", "turn": int(st["turn"]),
		"ticks": int(res["tick"]), "winner": int(outcome["winner"])})
	battle.queue_free()
	battle = null
	_set_visible(true)
	_apply_battle(_battle_id, outcome)


func _on_coop_exit() -> void:
	var c = battle.coop
	var r: Dictionary = battle.coop_exit_result()
	var res: Dictionary = battle.sim.result()
	_t("campaign_battle", {"mode": "live", "turn": int(st["turn"]), "ticks": int(res["tick"]), "winner": int(res["winner"]),
		"upload": not r.is_empty(), "host": c.is_host(), "stats": c.stats})
	battle.queue_free()
	battle = null
	_set_visible(true)
	get_tree().create_timer(2.0).timeout.connect(func(): if is_instance_valid(c): c.queue_free())
	if r.is_empty():
		_after_battle_refresh()
		if online != null:
			online.sync()
		return
	var outcome: Dictionary
	if bool(r["decided"]):
		outcome = CBattle.outcome_from_result(_battle_built, r["res"], "fought")
	else:
		outcome = CBattle.outcome_forfeit(_battle_built, r["res"])
	outcome["live"] = 1
	_apply_battle(_battle_id, outcome)


# ---------------------------------------------------------------- input ---

func _map_point(screen: Vector2) -> Vector2:
	return (screen - offset) / zoom


func _clamp_view() -> void:
	var vp := _vp()
	var avail := vp - Vector2(0, TOP_H)
	var fit := minf(avail.x / Geo.SIZE.x, avail.y / Geo.SIZE.y)
	zoom = clampf(zoom, fit, ZOOM_MAX)  # never smaller than the whole map
	var mapsz := Geo.SIZE * zoom
	var margin := 60.0
	# Along each axis: centred if the map fits, else kept on screen with a margin.
	if mapsz.x <= avail.x:
		offset.x = (vp.x - mapsz.x) * 0.5
	else:
		# The right edge may come in past the side panel.
		offset.x = clampf(offset.x, vp.x - mapsz.x - minf(PANEL_W, vp.x * 0.48) - margin, margin)
	if mapsz.y <= avail.y:
		offset.y = TOP_H + (avail.y - mapsz.y) * 0.5
	else:
		offset.y = clampf(offset.y, vp.y - mapsz.y - margin, TOP_H + margin)


func _zoom_at(p: Vector2, factor: float) -> void:
	var m := _map_point(p)
	zoom = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	offset = p - m * zoom
	_clamp_view()


func _blocked() -> bool:
	return dialog.visible or book.visible or controls_page.visible or cover.visible or battle != null


func _unhandled_input(event: InputEvent) -> void:
	if _blocked():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and dialog.visible and not cover.visible:
			close_dialog()
		return
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.15)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mouse_pan = mb.pressed
			if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and sel_army >= 0:
				# Right click on a region with an army selected: move there.
				var r := _region_at(mb.position)
				if r >= 0 and map_view.targets.has(r):
					set_move(sel_army, r)
					_mouse_pan = false
	elif event is InputEventMouseMotion and _mouse_pan:
		offset += (event as InputEventMouseMotion).relative
		_clamp_view()
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		offset -= event.delta * 8.0
		_clamp_view()
	elif event is InputEventKey and event.pressed and not event.echo:
		match Controls.action_for_key(event as InputEventKey, "campaign"):
			"map_deselect":
				if side.visible:
					close_side()
			"map_end_turn":
				if not end_button.disabled:
					end_turn()
			"map_zoom_in":
				_zoom_at(_vp() * 0.5, 1.25)
			"map_zoom_out":
				_zoom_at(_vp() * 0.5, 0.8)
			"map_next_army":
				_cycle_army()


## Keyboard panning (held keys).
func _keys(delta: float) -> void:
	if _blocked() or get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var v := Vector2.ZERO
	if Controls.held("map_pan_left"):
		v.x += 1
	if Controls.held("map_pan_right"):
		v.x -= 1
	if Controls.held("map_pan_up"):
		v.y += 1
	if Controls.held("map_pan_down"):
		v.y -= 1
	if v != Vector2.ZERO:
		offset += v * 700.0 * delta
		_clamp_view()


func _cycle_army() -> void:
	var mine := CState.armies_of(ps, f)
	if mine.is_empty():
		return
	var idx := 0
	for i in mine.size():
		if int(mine[i]["id"]) == sel_army:
			idx = (i + 1) % mine.size()
	var a: Dictionary = mine[idx]
	select_army(int(a["id"]))
	focus_region(int(a["r"]))


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_press_pos = e.position
			_dragging = false
			_multi = false
		else:
			_multi = true
			_start_pinch()
		return
	if not _touches.has(e.index):
		return
	_touches.erase(e.index)
	if _multi:
		if _touches.is_empty():
			_multi = false
		elif _touches.size() >= 2:
			_start_pinch()
		return
	if not _dragging:
		_tap(e.position)
	_dragging = false


func _on_drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index):
		return
	_touches[e.index] = e.position
	if _multi:
		if _touches.size() >= 2:
			var ks := _touches.keys()
			ks.sort()
			var a: Vector2 = _touches[ks[0]]
			var b: Vector2 = _touches[ks[1]]
			var d := a.distance_to(b)
			var mid := (a + b) * 0.5
			offset += mid - _pinch_mid
			if _pinch_d > 1.0 and d > 1.0:
				_zoom_at(mid, d / _pinch_d)
			_pinch_d = d
			_pinch_mid = mid
			_clamp_view()
		return
	if not _dragging and e.position.distance_to(_press_pos) > DRAG_THRESHOLD:
		_dragging = true
	if _dragging:
		offset += e.relative
		_clamp_view()


func _start_pinch() -> void:
	var ks := _touches.keys()
	ks.sort()
	var a: Vector2 = _touches[ks[0]]
	var b: Vector2 = _touches[ks[1]]
	_pinch_d = a.distance_to(b)
	_pinch_mid = (a + b) * 0.5


func _region_at(p: Vector2) -> int:
	var s := overlay.settlement_at(p)
	if s >= 0:
		return s
	return Geo.region_at(_map_point(p))


## Tap: an army marker selects it; with an army selected, a highlighted
## region is a move order (again: cancel); otherwise a region opens its panel;
## the sea clears the selection.
func tap(p: Vector2) -> void:
	_tap(p)


func _tap(p: Vector2) -> void:
	if f < 0:
		return
	var id := overlay.army_at(p)
	var r := _region_at(p)
	if sel_army >= 0 and r >= 0 and map_view.blocked_targets.has(r) and \
			(id < 0 or int(CState.army(ps, id).get("f", -1)) != f):
		explain_refusal(sel_army, r)
		return
	if sel_army >= 0 and r >= 0 and (map_view.targets.has(r) or planned_move(sel_army) == r):
		# A tap on one of our own banners selects it; anywhere else in a
		# highlighted region (an enemy banner included) is the move.
		if id < 0 or int(CState.army(ps, id).get("f", -1)) != f:
			set_move(sel_army, r)
			return
	if id >= 0:
		select_army(id)
		_t("campaign_input", {"what": "select_army"})
		return
	if r >= 0:
		select_region(r)
		return
	close_side()
