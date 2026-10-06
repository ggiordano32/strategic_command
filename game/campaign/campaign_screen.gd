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
##
## State version 6 (the continuous overworld, CState.grid_on): a move is a
## cell (or an enemy army, tgt): select an army (its reach this turn is
## shaded, enemy zones and support / attack lines drawn), then tap a
## destination or drag from the army; tapping the same destination again
## cancels; Undo takes back the last change to the plan. A resolved turn is
## replayed from the step logs (armies slide cell to cell; a tap skips).

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
const CGrid := preload("res://campaign/cgrid.gd")
const MapKey := preload("res://game/campaign/map_key.gd")
const UiScale := preload("res://game/ui_scale.gd")

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
var map_key: MapKey            # the map key (bottom left)
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

# Version 6.
var undo_button: Button
var _undo: Array = []          # earlier order lists (Undo)
var _routes := {}              # army id -> plan_path result for its plan (per preview)
var _drag_army := -1           # an army being dragged to a destination
var _drag_cell := -1
var _drag_tgt := -1
var merge_tap := -1            # own army tapped once with an army selected: the merge previewed
var _shown_turn := -1          # the turn whose army positions are _shown_cells
var _shown_cells := {}         # army id -> cell, as last shown
var _replay_q: Dictionary = {} # a replay waiting for the dialogs to close
var replay: Dictionary = {}    # the replay running: {rounds, k, t, cur {id: map pt}, from {id: map pt}}
var _replay_freeze := -1
var _skip_release := false       # testing aid: hold the replay half way through this round
const REPLAY_ROUND := 0.13     # seconds per round of steps


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
## --plan-move=N:key --camp-attack=N:key --camp-siege=N:key[:turns] --camp-besieged=key:faction --camp-fight --sim-turns=N --dialog-scroll=PX --side-scroll=PX
## --camp-exchange=N:M:k (version 6: the exchange panel)
## --plan-stance=N:0|1 --camp-raid=N:key (version 5: the player's Nth army raids region key) --camp-intercept=N:key:faction (an army
## of faction marching into key runs into the player's Nth army standing there in the field)
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
		elif a.begins_with("--map-key="):
			map_key.persist = false  # testing aid: open (1) or close (0) the map key
			map_key.set_expanded(v == "1")
		elif a.begins_with("--dialog-scroll="):
			await get_tree().create_timer(1.5).timeout
			dialog_scroll.scroll_vertical = int(v)  # testing aid
		elif a.begins_with("--side-scroll="):
			await get_tree().create_timer(1.0).timeout
			side_scroll.scroll_vertical = int(v)  # testing aid
		elif a == "--debug-xform":
			print("world ", world.get_global_transform_with_canvas(), " overlay ", overlay.get_global_transform_with_canvas(), " vp ", _vp(), " zoom ", zoom, " off ", offset, " roma ", Geo.site(0), " -> ", overlay.to_screen(Geo.site(0)))
		elif a.begins_with("--select-region="):
			select_region(CData.region_index(v))
		elif a.begins_with("--select-army="):
			var mine := CState.armies_of(ps, f)
			if int(v) < mine.size():
				select_army(int(mine[int(v)]["id"]))
		elif a.begins_with("--plan-cell="):
			# --plan-cell=N:x:y (version 6): the player's Nth army marches to cell (x, y).
			var mine10 := CState.armies_of(ps, f)
			var k10 := int(v.get_slice(":", 0))
			if k10 < mine10.size():
				set_move6(int(mine10[k10]["id"]), CGrid.at(int(v.get_slice(":", 1)), int(v.get_slice(":", 2))), -1)
		elif a.begins_with("--plan-site="):
			# --plan-site=N:key (version 6): the player's Nth army marches onto a settlement.
			var mine11 := CState.armies_of(ps, f)
			var k11 := int(v.get_slice(":", 0))
			if k11 < mine11.size():
				set_move6(int(mine11[k11]["id"]), CGrid.site(CData.region_index(v.get_slice(":", 1))), -1)
		elif a.begins_with("--camp-place="):
			# --camp-place=N:x:y (version 6): put the player's Nth army on cell (x, y).
			var mine12 := CState.armies_of(st, f)
			var k12 := int(v.get_slice(":", 0))
			if k12 < mine12.size():
				CState.place(mine12[k12], CGrid.at(int(v.get_slice(":", 1)), int(v.get_slice(":", 2))))
				_replan()
		elif a.begins_with("--camp-exchange="):
			# --camp-exchange=N:M:k (version 6): put the player's Mth army next
			# to its Nth and open the exchange panel, the Nth's first k units
			# sent across.
			var mine13 := CState.armies_of(st, f)
			var n13 := int(v.get_slice(":", 0))
			var m13 := int(v.get_slice(":", 1))
			if n13 < mine13.size() and m13 < mine13.size() and n13 != m13:
				var c13 := CState.cell(mine13[n13])
				for d13 in 8:
					var nc := CGrid.at(CGrid.cx(c13) + CGrid.DX[d13], CGrid.cy(c13) + CGrid.DY[d13])
					if nc >= 0 and CGrid.passable(nc) and CGrid.step_cost(c13, nc) > 0 and CGrid.site_region(nc) < 0:
						CState.place(mine13[m13], nc)
						break
				_replan()
				var id13 := int(mine13[n13]["id"])
				focus_region(int(mine13[n13]["r"]), 1.4)
				select_army(id13)
				panels.show_exchange(id13, int(mine13[m13]["id"]))
				for k13 in int(v.get_slice(":", 2)):
					panels._xc_toggle("out", k13)
		elif a.begins_with("--replay-freeze="):
			_replay_freeze = int(v)  # testing aid
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
		elif a.begins_with("--camp-siege="):
			# --camp-siege=N:region[:turns]: the player's Nth army has been
			# besieging region for `turns` turns (war if needed).
			var mine4 := CState.armies_of(st, f)
			var to4 := CData.region_index(v.get_slice(":", 1))
			var a4: Dictionary = mine4[int(v.get_slice(":", 0))]
			var o4 := CState.owner(st, to4)
			if o4 >= 0 and not CState.at_war(st, f, o4):
				CRules.declare_war(st, f, o4)
			var left := int(a4["r"])
			a4["r"] = to4
			if CState.grid_on(st):
				CState.place(a4, CState.ring_cell(to4, 0))  # version 6: on the ring
			var sg4 := CRules.start_siege(st, to4, a4, left)
			var n4 := int(v.get_slice(":", 2)) if v.get_slice_count(":") > 2 else 1
			sg4["turn"] = int(st["turn"]) - n4
			sg4["supply"] = maxi(int(sg4["supply"]) - n4, 0)
			_replan()
		elif a.begins_with("--camp-besieged="):
			# --camp-besieged=region:faction: a fresh army of faction (at war
			# with the player) has besieged the player's region for a turn.
			var r6 := CData.region_index(v.get_slice(":", 0))
			var e6 := CData.faction_index(v.get_slice(":", 1))
			if not CState.at_war(st, f, e6):
				CRules.declare_war(st, f, e6)
			var id6 := CRules.new_army_id(st, e6)
			st["factions"][e6]["next_army"] = int(st["factions"][e6]["next_army"]) + 1
			CRules._insert_army(st, {"id": id6, "f": e6, "r": r6, "units": [{"t": "heavy", "n": 100}, {"t": "heavy", "n": 100},
				{"t": "spear", "n": 100}, {"t": "light", "n": 120}], "from": -1, "moved": 0, "busy": 0})
			var sg6 := CRules.start_siege(st, r6, CState.army(st, id6), -1)
			sg6["turn"] = int(st["turn"]) - 1
			_replan()
		elif a.begins_with("--plan-stance="):
			var mine9 := CState.armies_of(ps, f)
			add_order({"t": "stance", "a": int(mine9[int(v.get_slice(":", 0))]["id"]), "s": int(v.get_slice(":", 1))})
		elif a.begins_with("--camp-raid="):
			var mine7 := CState.armies_of(st, f)
			var to7 := CData.region_index(v.get_slice(":", 1))
			var a7: Dictionary = mine7[int(v.get_slice(":", 0))]
			var o7 := CState.owner(st, to7)
			if o7 >= 0 and not CState.at_war(st, f, o7):
				CRules.declare_war(st, f, o7)
			a7["r"] = to7
			for d7 in CState.armies_in(st, to7):
				if int(d7["f"]) == o7:
					d7["stance"] = CData.STANCE_GARRISON
			_replan()
		elif a.begins_with("--camp-intercept="):
			var mine8 := CState.armies_of(st, f)
			var r8 := CData.region_index(v.get_slice(":", 1))
			var e8 := CData.faction_index(v.get_slice(":", 2))
			var a8: Dictionary = mine8[int(v.get_slice(":", 0))]
			if not CState.at_war(st, f, e8):
				CRules.declare_war(st, f, e8)
			a8["r"] = r8
			a8["stance"] = CData.STANCE_FIELD
			var from8 := -1
			for e in CData.adjacent(r8):
				if int(e[1]) == 0 and from8 < 0 and CState.owner(st, int(e[0])) != f:
					from8 = int(e[0])
			var id8 := CRules.new_army_id(st, e8)
			st["factions"][e8]["next_army"] = int(st["factions"][e8]["next_army"]) + 1
			CRules._insert_army(st, {"id": id8, "f": e8, "r": from8, "units": [{"t": "heavy", "n": 100}, {"t": "heavy", "n": 100},
				{"t": "spear", "n": 100}, {"t": "light", "n": 100}, {"t": "cav", "n": 60}], "from": -1, "moved": 0, "busy": 0})
			CRules.execute_moves(st, [[id8, r8, e8, CData.MODE_MARCH, 0]])
			for b8 in st["battles"]:
				CRules.add_reinforcements(st, b8)
				b8.erase("new")
			st["phase"] = "battles"
			_next_step()
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
	_undo = []
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
	_routes = {}
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
	_push_undo()
	orders.append(o)
	_replan()
	save()
	return ""


func remove_orders(pred: Callable) -> void:
	var keep: Array = []
	for o in orders:
		if not pred.call(o):
			keep.append(o)
	if keep.size() != orders.size():
		_push_undo()
	orders = keep
	_replan()
	save()


func _push_undo() -> void:
	_undo.append(orders.duplicate(true))
	if _undo.size() > 40:
		_undo.pop_front()


## Take back the last change to the plan.
func undo() -> void:
	if _undo.is_empty() or f < 0:
		return
	orders = _undo.pop_back()
	_replan()
	save()
	_t("campaign_input", {"what": "undo"})


## Where army is ordered this turn: its move order, else (state version 5)
## the destination it is still marching to; -1 if none.
func planned_move(army: int) -> int:
	if _g():
		var p6 := plan6(army)
		return CGrid.region(int(p6["cell"])) if not p6.is_empty() and int(p6["cell"]) >= 0 else -1
	for m in moves:
		if int(m[0]) == army:
			return int(m[1])
	return stored_move(army)


## Version 5: the destination army keeps marching to from an earlier turn
## (and was not stopped this turn), else -1.
func stored_move(army: int) -> int:
	if not CState.moves_on(ps):
		return -1
	var a := CState.army(ps, army)
	if a.is_empty() or int(a["busy"]) != 0 or int(a.get("dest", -1)) == int(a["r"]):
		return -1
	return int(a.get("dest", -1))


func set_move(army: int, to: int) -> void:
	if _g():
		# A region (tests, the v5 callers): its settlement.
		set_move6(army, CGrid.site(to) if to >= 0 else -1, -1)
		return
	var cur := planned_move(army)
	var had_order := false
	for o in orders:
		if str(o["t"]) == "move" and int(o["army"]) == army:
			had_order = true
	remove_orders(func(o): return str(o["t"]) == "move" and int(o["army"]) == army)
	if cur == to:
		if not had_order and stored_move(army) == to:
			add_order({"t": "cancel_move", "army": army})  # stop a march from an earlier turn
		_t("campaign_input", {"what": "move_cancel"})
		return
	var mo := {"t": "move", "army": army, "to": to}
	if CState.moves_on(st):
		# March there over as many turns as it takes; entering enemy land
		# raids it (laying siege or assaulting is one tap away in the toast).
		mo["mode"] = CData.MODE_MARCH
		mo["persist"] = 1
	elif CState.sieges_on(st):
		mo["mode"] = CData.MODE_SIEGE  # the default: lay siege (Assault is one tap away)
	if add_order(mo) == "":
		_t("campaign_input", {"what": "move"})
		if move_kind(army) != "move":
			move_toast(army)


## Mode of army's planned move (CData.MODE_*; -1 if none).
func move_mode(army: int) -> int:
	if _g():
		var p6 := plan6(army)
		return int(p6["mode"]) if not p6.is_empty() else -1
	for m in moves:
		if int(m[0]) == army:
			return int(m[2]) if (m as Array).size() > 2 else CData.MODE_SIEGE
	if stored_move(army) >= 0:
		return int(CState.army(ps, army)["mode"])
	return -1


## Version 5: the planned (or stored) march of army: {path [regions],
## turns [turn each hop is reached: 0 this turn], to, mode}; {} if none.
func route(army: int) -> Dictionary:
	if _g():
		return route6(army)
	var to := planned_move(army)
	var a := CState.army(ps, army)
	if to < 0 or a.is_empty() or not CState.moves_on(ps):
		return {}
	var rc := CRules.reach(ps, a)
	var path := CRules.path_of(rc, to)
	var turns: Array = []
	for r in path:
		turns.append(int(rc["t"][r]))
	return {"path": path, "turns": turns, "to": to, "mode": move_mode(army), "left": int(rc["m"][to]) if not path.is_empty() else 0}


## What army's planned move does: "move" (friendly land), "siege" (lays
## siege), "join" (joins our siege), "assault" (storms it now), "relief"
## (relieves our besieged city), "raid" (version 5: marches into enemy land
## without attacking its settlement), "" (no move).
func move_kind(army: int) -> String:
	if _g():
		var p6 := plan6(army)
		var a6 := CState.army(ps, army)
		if p6.is_empty() or a6.is_empty():
			return ""
		return str(CRules.move_aim(ps, a6, int(p6["cell"]), int(p6["tgt"]), int(p6["mode"]), int(p6.get("join", -1)))["kind"])
	var to := planned_move(army)
	var a := CState.army(ps, army)
	if to < 0 or a.is_empty():
		return ""
	var af := int(a["f"])
	var o := CState.owner(ps, to)
	if not CState.sieges_on(ps):
		return "assault" if CState.at_war(ps, af, o) else "move"
	var sg := CState.siege_at(ps, to)
	if not sg.is_empty():
		if CState.friendly(ps, af, o):
			return "relief"
		return "assault" if move_mode(army) == CData.MODE_ASSAULT else "join"
	if CState.at_war(ps, af, o):
		match move_mode(army):
			CData.MODE_ASSAULT:
				return "assault"
			CData.MODE_MARCH:
				return "raid"
		return "siege"
	return "move"


## Switch army's planned move between laying siege and assaulting (and,
## version 5, marching in without attacking).
func set_move_mode(army: int, mode: int) -> void:
	if _g():
		var p6 := plan6(army)
		if p6.is_empty():
			return
		_push_undo()
		var found6 := false
		for o in orders:
			if str(o["t"]) == "move" and int(o["army"]) == army:
				o["mode"] = mode
				found6 = true
		if not found6:
			var mo := {"t": "move", "army": army, "x": CGrid.cx(int(p6["cell"])), "y": CGrid.cy(int(p6["cell"])), "mode": mode, "persist": 1}
			if int(p6["tgt"]) >= 0:
				mo["tgt"] = int(p6["tgt"])
			orders.append(mo)
		_replan()
		save()
		_t("campaign_input", {"what": "move_mode", "mode": mode})
		return
	var found := false
	for o in orders:
		if str(o["t"]) == "move" and int(o["army"]) == army:
			o["mode"] = mode
			found = true
	if not found and stored_move(army) >= 0:
		# A march from an earlier turn: re-issue it with the new mode.
		orders.append({"t": "move", "army": army, "to": stored_move(army), "mode": mode, "persist": 1})
	_replan()
	save()
	_t("campaign_input", {"what": "move_mode", "mode": mode})
	move_toast(army)


## The toast after planning a move into hostile land: what it does, the
## odds of storming the city now, and the other choice one tap away.
func move_toast(army: int) -> void:
	if _g():
		return  # version 6: the intent is drawn at the path's end
	var kind := move_kind(army)
	var to := planned_move(army)
	if to < 0 or kind == "move" or kind == "":
		return
	var po: Dictionary = panels.plan_odds(to)
	var od: Dictionary = po["od"]
	var odds := "%d%% (%s)" % [int(od["win"]), Kit.BAND_WORDS[int(od["band"])]]
	var city := str(CData.REGIONS[to]["city"])
	if CState.moves_on(ps):
		_march_toast(army, kind, to, odds)
		return
	match kind:
		"siege":
			show_toast("Lays siege to %s: no battle this turn; its supplies last %d turns, then it starves. Storming it now: %s." % [
				city, CState.siege_supply(ps, to), odds], ["Assault now", func(): set_move_mode(army, CData.MODE_ASSAULT)])
		"join":
			show_toast("Joins the siege of %s. Storming it now with every besieger: %s." % [city, odds],
				["Assault now", func(): set_move_mode(army, CData.MODE_ASSAULT)])
		"assault":
			if CState.sieges_on(ps):
				show_toast("Storms %s at once: %s." % [city, odds], ["Lay siege", func(): set_move_mode(army, CData.MODE_SIEGE)])
		"relief":
			show_toast("Relieves %s: a field battle outside the walls, the garrison and the armies inside on your side: %s." % [city, odds])


## Version 5 toast: when the march arrives, what it does there (raid, lay
## siege, storm), a field battle first if enemy armies stand in the field
## there, and the other two choices one tap away.
func _march_toast(army: int, kind: String, to: int, odds: String) -> void:
	var rt := route(army)
	var city := str(CData.REGIONS[to]["city"])
	var reg := str(CData.REGIONS[to]["name"])
	var o := CState.owner(ps, to)
	var turns: Array = rt.get("turns", [])
	var last := int(turns[-1]) if not turns.is_empty() else 0
	var when := "this turn" if last == 0 else ("next turn" if last == 1 else "in %d turns" % (last + 1))
	var text := ""
	var acts: Array = []
	var raid := ["March only", func(): set_move_mode(army, CData.MODE_MARCH)]
	var siege := ["Lay siege", func(): set_move_mode(army, CData.MODE_SIEGE)]
	var storm := ["Assault", func(): set_move_mode(army, CData.MODE_ASSAULT)]
	match kind:
		"raid":
			text = "Marches into %s (%s) and raids it: %s loses half its income. Storming %s instead: %s." % [
				reg, when, CData.faction_name(o), city, odds]
			acts = [siege, storm]
		"siege":
			text = "Lays siege to %s on arrival (%s): no battle; supplies for %d turns. Storming it instead: %s." % [
				city, when, CState.siege_supply(ps, to), odds]
			acts = [storm, raid]
		"join":
			text = "Joins the siege of %s (%s). Storming it with every besieger: %s." % [city, when, odds]
			acts = [storm]
		"assault":
			text = "Storms %s on arrival (%s): %s." % [city, when, odds]
			acts = [siege, raid]
		"relief":
			text = "Relieves %s (%s): a field battle, the garrison and the armies inside with you: %s." % [city, when, odds]
	var fo: Dictionary = panels.field_odds(army, to)
	if not fo.is_empty():
		text += " %s's army in the field there must be beaten first: %d%% (%s)." % [
			CData.faction_name(int(fo["by"])), int(fo["od"]["win"]), Kit.BAND_WORDS[int(fo["od"]["band"])]]
	show_toast(text, acts)


## Why the selected army cannot move to region r, and what to do about it,
## as a toast (with a Diplomacy shortcut when peace is the reason).
func explain_refusal(army: int, r: int, why_in: String = "") -> void:
	var a := CState.army(ps, army)
	var why := why_in if why_in != "" else CRules.can_move(ps, a, r)
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
	elif why == "besieged":
		text = "This army is inside a besieged city: it can only leave by a sally (tap the city)."
	elif why.begins_with("besieged by"):
		text = "%s is %s: only their side or the city's own can march in." % [reg, why]
	elif why == "not adjacent":
		text = "%s is not next to this army: one region or one sea lane a turn." % reg
	elif why == "no route":
		text = "No way to %s: lands at peace or besieged by others block every path." % reg
	elif why == "already there":
		text = "The army is in %s already. To lay siege or storm it, open the region." % reg
	elif why == "in an enemy's zone of control":
		text = "That ground lies in an enemy army's zone of control (red circle): tap the army itself to attack it, or pick a spot outside its zone."
	elif why == "zone of control":
		text = "An enemy army's zone of control stops the march: attack it or go round."
	elif why == "fortified":
		text = "This army is fortified and cannot move: set its stance back to Default first (the army card)."
	elif why == "too many units to merge" or why.begins_with("more than"):
		text = "Too many units to merge: an army holds at most %d. Exchange units instead when the two stand together (the army card)." % CData.ARMY_MAX
	elif why == "not together":
		text = "The two armies must stand on the same or neighbouring cells."
	elif why.begins_with("on a forced march"):
		text = "On a forced march an army cannot attack or lay siege: set its stance to Default first (the army card)."
	else:
		text = "Cannot move to %s: %s." % [reg, why]
	_t("campaign_input", {"what": "move_refused", "why": why})
	show_toast(text, action)


var _toast: PanelContainer = null


## A short message above the bottom edge (stays 6 s or until tapped away),
## with an optional [label, callable] button (or several: [[label,
## callable], ...]; the first is named toast_action, the next toast_action2).
func show_toast(text: String, action: Array = []) -> void:
	if _toast != null:
		_toast.queue_free()
	_toast = Kit.panel(Color(0.12, 0.1, 0.08, 0.96), 10)
	_toast.name = "toast"
	var l := Kit.label(text, Kit.FONT, Color(1, 0.92, 0.8), true)
	# Fits left of the side panel when it is open; on a narrow screen (a
	# phone with the panel open) it spans the width, over the panel.
	var room := _vp().x - (side.size.x + 16.0 if side.visible else 0.0) - 16.0
	var acts: Array = []
	if not action.is_empty():
		acts = action if action[0] is Array else [action]
	var h := Kit.hbox(8)
	if acts.size() > 1:
		# Several choices: the text on top, the buttons in a row below it.
		if room < 320.0:
			room = _vp().x - 16.0
		var v := Kit.vbox(6)
		_toast.add_child(v)
		l.custom_minimum_size.x = clampf(room - 24.0, 240.0, 640.0)
		v.add_child(l)
		h.alignment = BoxContainer.ALIGNMENT_END
		v.add_child(h)
	else:
		if room < 460.0:
			room = _vp().x - 16.0
		_toast.add_child(h)
		l.custom_minimum_size.x = clampf(room - 200.0, 180.0, 520.0)
		h.add_child(l)
	for k in acts.size():
		var cb: Callable = acts[k][1]
		var b := Kit.button(str(acts[k][0]), func():
			if _toast != null:
				_toast.queue_free()
				_toast = null
			cb.call(), 110)
		b.name = "toast_action" if k == 0 else "toast_action%d" % (k + 1)
		h.add_child(b)
	var x := Kit.button("OK", func():
		if _toast != null:
			_toast.queue_free()
			_toast = null, 56)
	h.add_child(x)
	ui.add_child(_toast)
	ui.move_child(_toast, end_button.get_index())
	_place_toast()
	_place_toast.call_deferred()  # again once the wrapped label has its height
	ui.move_child(_toast, -1)
	var me := _toast
	get_tree().create_timer(6.0).timeout.connect(func():
		if is_instance_valid(me) and me == _toast:
			me.queue_free()
			_toast = null)


func _place_toast() -> void:
	if _toast == null or not is_instance_valid(_toast):
		return
	_toast.reset_size()
	_toast.position = Vector2(8, _vp().y - _toast.size.y - 64)


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
	# Right of the map key's button.
	hint.offset_left = MapKey.MARGIN * 2.0 + MapKey.BUTTON_W
	hint.offset_right = hint.offset_left + 412
	ui.add_child(hint)
	map_key = MapKey.new()
	ui.add_child(map_key)
	map_key.set_expanded(MapKey.load_pref())
	end_button = Kit.button("End turn", func(): end_turn(), 130, 17)
	end_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	end_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	end_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	end_button.offset_right = -8
	end_button.offset_bottom = -8
	end_button.custom_minimum_size = Vector2(130, 48)
	ui.add_child(end_button)
	undo_button = Kit.button("Undo", func(): undo(), 80, 15)
	undo_button.name = "undo"
	undo_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	undo_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	undo_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	undo_button.offset_right = -146
	undo_button.offset_bottom = -8
	undo_button.custom_minimum_size = Vector2(80, 48)
	undo_button.visible = false
	ui.add_child(undo_button)
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
	merge_tap = -1
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


## The map key's rows follow the campaign's format; its samples use the
## planning faction's colour and an enemy's.
func _refresh_key() -> void:
	if ps.is_empty():
		return
	var fs := f if f >= 0 else (int(ps["humans"][0]) if not (ps["humans"] as Array).is_empty() else 0)
	var en := (fs + 1) % CData.FACTIONS.size()
	for k in CData.FACTIONS.size():
		if k != fs and not CState.friendly(ps, fs, k):
			en = k
			break
	var fmt := 6 if _g() else (5 if CState.moves_on(ps) else 4)
	map_key.set_format(fmt, CData.faction_color(fs), CData.faction_color(en))


## Phones (and narrow windows): the open map key covers the map, so a tap on
## the map closes it.
func _key_modal() -> bool:
	return UiScale.is_touch() or _vp().x < 1000.0


func _place_key() -> void:
	if not map_key.expanded:
		return
	var vp := _vp()
	var bottom := vp.y - MapKey.MARGIN - MapKey.BUTTON_H
	if hint.text != "" and hint.visible:
		bottom = minf(bottom, hint.get_global_rect().position.y)
	map_key.place(TOP_H + 6.0, bottom - 6.0, vp.x)


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
	undo_button.visible = _g() and f >= 0 and not _undo.is_empty()
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
	elif not replay.is_empty():
		hint.text = "Replaying the turn: tap to skip."
	elif sel_army >= 0 and _g():
		hint.text = "Tap (or drag the army to) a spot inside the shaded area to march there this turn, further on for later turns; tap an enemy army to attack it, a city to besiege it. Same spot again: cancel."
	elif _g():
		hint.text = "Tap an army to move it, a city for buildings and recruits."
	elif sel_army >= 0 and CState.moves_on(ps):
		hint.text = "Tap a region to march there (bright: this turn, dim: later turns; red: enemy land). Tap it again to cancel."
	elif sel_army >= 0:
		hint.text = "Tap a highlighted region to move there (red: siege or attack; dark: not allowed, tap for why). Tap it again to cancel."
	else:
		hint.text = "Tap an army to move it, a region for buildings and recruits."


func _refresh_map() -> void:
	map_view.state = ps
	overlay.state = ps
	_refresh_key()
	if _g():
		_refresh_map6()
		return
	map_view.grid = false
	overlay.grid = false
	overlay.player = f
	overlay.selected_army = sel_army
	overlay.moves = moves
	var att: Array[int] = []
	var sgm: Array[int] = []
	var shown: Array = moves.duplicate()
	var free_moves := not ps.is_empty() and CState.moves_on(ps)
	if free_moves:
		for a in CState.armies_of(ps, f):
			if stored_move(int(a["id"])) >= 0 and planned_move(int(a["id"])) == stored_move(int(a["id"])) and _first(moves, int(a["id"])):
				shown.append([int(a["id"]), stored_move(int(a["id"])), int(a["mode"])])
	for m in shown:
		var o := CState.owner(ps, int(m[1]))
		var kind := move_kind(int(m[0]))
		if (CState.at_war(ps, f, o) and kind != "raid") or kind == "relief":
			att.append(int(m[0]))
		if kind == "siege" or kind == "join":
			sgm.append(int(m[0]))
	overlay.attack_moves = att
	overlay.siege_moves = sgm
	var paths: Array = []
	if free_moves:
		overlay.moves = []
		for m in shown:
			var rt := route(int(m[0]))
			if rt.is_empty() or (rt["path"] as Array).is_empty():
				continue
			var a0 := CState.army(ps, int(m[0]))
			var pts: Array = [Geo.site(int(a0["r"]))]
			var now := 0
			for k in (rt["path"] as Array).size():
				pts.append(Geo.site(int(rt["path"][k])))
				if int(rt["turns"][k]) == 0:
					now = k + 1
			paths.append({"army": int(m[0]), "pts": pts, "now": now})
	overlay.paths = paths
	map_view.targets = []
	map_view.attack_targets = []
	map_view.blocked_targets = []
	map_view.target_turns = {}
	if sel_army >= 0 and free_moves:
		var a := CState.army(ps, sel_army)
		if not a.is_empty() and int(a["f"]) == f and int(a["busy"]) == 0:
			_free_targets(a)
	elif sel_army >= 0:
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


static func _first(list: Array, id: int) -> bool:
	for m in list:
		if int(m[0]) == id:
			return false
	return true


## Version 5 destinations of the selected army: every region it can reach,
## by the turn it gets there (map_view shades this turn bright, the next
## dimmer); unreachable neighbours of this turn's reach are blocked.
func _free_targets(a: Dictionary) -> void:
	var tg := CRules.move_targets(ps, a)
	var rc := CRules.reach(ps, a)
	var turns := {}
	var at: Array[int] = []
	for r in tg:
		turns[r] = int(rc["t"][r])
		if CState.at_war(ps, f, CState.owner(ps, r)):
			at.append(r)
	var near := {int(a["r"]): 1}
	for r in tg:
		if int(rc["t"][r]) == 0:
			near[r] = 1
	var bl: Array[int] = []
	for r in near:
		for e in CData.adjacent(int(r)):
			var n := int(e[0])
			if n != int(a["r"]) and not tg.has(n) and not bl.has(n) and planned_move(sel_army) != n:
				bl.append(n)
	bl.sort()
	map_view.targets = tg
	map_view.attack_targets = at
	map_view.blocked_targets = bl
	map_view.target_turns = turns


## Version 6: the state is on the grid.
func _g() -> bool:
	return not ps.is_empty() and CState.grid_on(ps)


## Version 6: army's planned or stored march: {cell, tgt, mode, stored,
## join (an army of ours it marches to merge into, -1)} ({} none).
func plan6(army: int) -> Dictionary:
	for m in moves:
		if int(m[0]) == army:
			return {"cell": int(m[1]), "tgt": int(m[4]) if (m as Array).size() > 4 else -1, "mode": int(m[2]), "stored": false,
				"join": int(m[5]) if (m as Array).size() > 5 else -1}
	var a := CState.army(ps, army)
	if a.is_empty() or int(a["busy"]) != 0:
		return {}
	for o in orders:
		if str(o["t"]) == "cancel_move" and int(o["army"]) == army:
			return {}
	var join := int(a.get("dest_army", -1))
	if join >= 0:
		var j := CState.army(ps, join)
		if j.is_empty():
			return {}
		return {"cell": CState.cell(j), "tgt": -1, "mode": int(a.get("mode", CData.MODE_SIEGE)), "stored": true, "join": join}
	var tgt := int(a.get("tgt", -1))
	if tgt >= 0:
		var t := CState.army(ps, tgt)
		if t.is_empty():
			return {}
		return {"cell": CState.cell(t), "tgt": tgt, "mode": int(a.get("mode", CData.MODE_SIEGE)), "stored": true, "join": -1}
	if int(a.get("dest_x", -1)) >= 0:
		return {"cell": CGrid.at(int(a["dest_x"]), int(a["dest_y"])), "tgt": -1, "mode": int(a.get("mode", CData.MODE_SIEGE)), "stored": true,
			"join": -1}
	return {}


## Version 6: the path of army's plan now (CRules.plan_path: path, t, m,
## aim; plus turns, left; "why" if it cannot go), {} without a plan. Cached
## per preview.
func route6(army: int) -> Dictionary:
	if _routes.has(army):
		return _routes[army]
	var p6 := plan6(army)
	var a := CState.army(ps, army)
	var out := {}
	if not p6.is_empty() and not a.is_empty():
		out = CRules.plan_path(ps, a, int(p6["cell"]), int(p6["tgt"]), int(p6["mode"]), {}, 12, int(p6.get("join", -1)))
		if not out.has("why"):
			out["turns"] = out["t"]
			out["left"] = int(out["m"][-1]) if not (out["m"] as Array).is_empty() else CState.mp(a)
	_routes[army] = out
	return out


## Version 6: plan army's march to cell c (or after enemy army tgt); the
## same destination again cancels it (a stored march: a cancel_move order).
func set_move6(army: int, c: int, tgt: int) -> void:
	var a := CState.army(ps, army)
	if a.is_empty() or c < 0:
		return
	var cur := plan6(army)
	var same := not cur.is_empty() and ((tgt >= 0 and int(cur["tgt"]) == tgt) or (tgt < 0 and int(cur["tgt"]) < 0 and int(cur["cell"]) == c))
	var had_order := false
	for o in orders:
		if str(o["t"]) == "move" and int(o["army"]) == army:
			had_order = true
	var before := orders.duplicate(true)
	var keep: Array = []
	for o in orders:
		if not ((str(o["t"]) == "move" or str(o["t"]) == "cancel_move") and int(o["army"]) == army):
			keep.append(o)
	orders = keep
	if same:
		if not had_order and bool(cur["stored"]):
			orders.append({"t": "cancel_move", "army": army})
		_undo.append(before)
		_replan()
		save()
		_t("campaign_input", {"what": "move_cancel"})
		return
	var mo := {"t": "move", "army": army, "x": CGrid.cx(c), "y": CGrid.cy(c), "mode": CData.MODE_SIEGE, "persist": 1}
	if tgt >= 0:
		mo["tgt"] = tgt
	var pv := CTurn.preview(st, f, orders + [mo])
	for e in pv["errors"]:
		if int(e[0]) == orders.size():
			orders = before
			_replan()
			explain_refusal(army, maxi(CGrid.region(c), 0), str(e[1]))
			return
	orders.append(mo)
	_undo.append(before)
	_replan()
	save()
	_t("campaign_input", {"what": "move", "tgt": tgt})


## Version 6: army marches to our army `target` and merges into it on
## arrival (a move with "join"; it keeps following it over the turns). Next
## to it already: a merge order now (the plan preview shows the merged
## army). The same target again cancels the march.
func set_join(army: int, target: int) -> void:
	var a := CState.army(ps, army)
	var t := CState.army(ps, target)
	if a.is_empty() or t.is_empty():
		return
	merge_tap = -1
	if CGrid.cheb(CState.cell(a), CState.cell(t)) <= 1 and CRules.merge_check(ps, f, army, target) == "":
		if add_order({"t": "merge", "army": army, "into": target}) == "":
			_t("campaign_input", {"what": "merge"})
			select_army(target)
		return
	var cur := plan6(army)
	var same := not cur.is_empty() and int(cur.get("join", -1)) == target
	var had_order := false
	for o in orders:
		if str(o["t"]) == "move" and int(o["army"]) == army:
			had_order = true
	var before := orders.duplicate(true)
	var keep: Array = []
	for o in orders:
		if not ((str(o["t"]) == "move" or str(o["t"]) == "cancel_move") and int(o["army"]) == army):
			keep.append(o)
	orders = keep
	if same:
		if not had_order and bool(cur["stored"]):
			orders.append({"t": "cancel_move", "army": army})
		_undo.append(before)
		_replan()
		save()
		_t("campaign_input", {"what": "move_cancel"})
		return
	var mo := {"t": "move", "army": army, "join": target, "mode": CData.MODE_SIEGE, "persist": 1}
	var pv := CTurn.preview(st, f, orders + [mo])
	for e in pv["errors"]:
		if int(e[0]) == orders.size():
			orders = before
			_replan()
			explain_refusal(army, maxi(CGrid.region(CState.cell(t)), 0), str(e[1]))
			return
	orders.append(mo)
	_undo.append(before)
	_replan()
	save()
	_t("campaign_input", {"what": "move", "join": target})


## First tap on another of our armies with one selected: preview the merge
## (its path, the caption, a toast with Merge / Select it); a second tap on
## it plans the merge.
func _merge_tap_at(id: int) -> void:
	if merge_tap == id:
		set_join(sel_army, id)
		if sel_army >= 0 and not CState.army(ps, sel_army).is_empty():
			show_side(func(box): panels.army_panel(box, sel_army))
		return
	var sa := CState.army(ps, sel_army)
	var t := CState.army(ps, id)
	if int(plan6(sel_army).get("join", -1)) == id:
		set_join(sel_army, id)  # the planned merge tapped again: cancel it
		show_side(func(box): panels.army_panel(box, sel_army))
		return
	merge_tap = id
	var why := CRules.join_check(ps, sa, id)
	if why == "" and CGrid.cheb(CState.cell(sa), CState.cell(t)) <= 1:
		why = CRules.merge_check(ps, f, sel_army, id)
	elif why == "":
		why = CRules._can_move6(ps, sa, CState.cell(t), -1, CData.MODE_SIEGE, true, id)
	_refresh_map()
	var other := id
	var sel_it := ["Select it", func(): select_army(other)]
	if why == "too many units to merge" or why.begins_with("more than"):
		show_toast("Too many units to merge: %d + %d is more than %d. Exchange units instead when they stand together." % [
			CState.unit_count(sa), CState.unit_count(t), CData.ARMY_MAX], [sel_it])
	elif why != "":
		show_toast("Cannot merge into that army now: %s." % why, [sel_it])
	else:
		var near := CGrid.cheb(CState.cell(sa), CState.cell(t)) <= 1
		show_toast("Merge into army (%d units)%s. Tap it again, or Merge." % [CState.unit_count(t),
			": they stand together, at once" if near else ": the army marches to it and merges on arrival"],
			[["Merge", func(): _merge_tap_at(other)], sel_it])
	_t("campaign_input", {"what": "merge_preview"})


## Version 6 map: armies on their cells, the selected army's reach, enemy
## zones and links, every planned path.
func _refresh_map6() -> void:
	map_view.grid = true
	overlay.grid = true
	overlay.player = f
	overlay.selected_army = sel_army
	overlay.moves = []
	overlay.paths = []
	overlay.attack_moves = []
	overlay.siege_moves = []
	map_view.targets = []
	map_view.attack_targets = []
	map_view.blocked_targets = []
	map_view.target_turns = {}
	map_view.selected_region = sel_region
	var paths: Array = []
	if f >= 0:
		for a in CState.armies_of(ps, f):
			var rt := route6(int(a["id"]))
			if rt.is_empty() or rt.has("why"):
				continue
			paths.append(path_entry(a, rt))
		for h in ps["humans"]:
			if int(h) == f:
				continue
			for a in CState.armies_of(ps, int(h)):
				# The ally's stored marches (their plan is theirs).
				if int(a.get("dest_x", -1)) >= 0 or int(a.get("tgt", -1)) >= 0:
					var c := CGrid.at(int(a["dest_x"]), int(a["dest_y"])) if int(a.get("dest_x", -1)) >= 0 else -1
					var rt2 := CRules.plan_path(ps, a, c, int(a.get("tgt", -1)), int(a["mode"]))
					if not rt2.has("why"):
						paths.append(path_entry(a, rt2))
	var zones: Array = []
	var links: Array = []
	var marks: Array = []
	var sa := CState.army(ps, sel_army) if sel_army >= 0 else {}
	if not sa.is_empty():
		var rt6 := PackedInt32Array()
		if int(sa["f"]) == f:
			rt6 = CRules.reach6(ps, sa, 1)
			if int(sa["busy"]) == 0:
				marks = _merge_marks(sa, rt6)
				var mt := CState.army(ps, merge_tap) if merge_tap >= 0 else {}
				if not mt.is_empty():
					var pr := CRules.plan_path(ps, sa, CState.cell(mt), -1, CData.MODE_SIEGE, {}, 12, merge_tap)
					if not pr.has("why"):
						var pe := path_entry(sa, pr)
						pe["preview"] = 1
						paths.append(pe)
		map_view.reach_hostile = false
		map_view.set_reach(rt6)
		var px := float(CGrid.cell_px())
		for e in CRules.zone_armies(ps, int(sa["f"])):
			var zr := CRules.zone_r(ps, e)
			zones.append([MapOverlay.cell_point(CState.cell(e)), (sqrt(float(zr * zr + zr)) + 0.5) * px])
		var lk := CRules.links_of(ps, sa, rt6)
		for id in lk["support"]:
			links.append([sel_army, int(id), 0])
		for id in lk["attack"]:
			links.append([sel_army, int(id), 1])
	else:
		map_view.set_reach(PackedInt32Array())
	overlay.paths6 = paths
	overlay.zones = zones
	overlay.links = links
	overlay.merge_marks = marks
	overlay.merge_tap = merge_tap
	map_view.queue_redraw()
	overlay.queue_redraw()
	_note_positions()


## Version 6: the armies the selected one (sa, its reach rt6) can merge
## into or give units to: [[id, 0 merge (an army of ours it reaches this
## turn), 1 gift (an allied player's army next to it), 2 too big to merge]].
func _merge_marks(sa: Dictionary, rt6: PackedInt32Array) -> Array:
	var out: Array = []
	var c0 := CState.cell(sa)
	for e in ps["armies"]:
		var id := int(e["id"])
		if id == int(sa["id"]) or int(e["busy"]) != 0:
			continue
		var ef := int(e["f"])
		var ec := CState.cell(e)
		if ef == f:
			var near := CGrid.cheb(c0, ec) <= 1
			if not near and rt6.size() == CGrid.count():
				for k in CGrid.disc(ec, 1):
					if rt6[k] == 0:
						near = true
						break
			if near:
				out.append([id, 2 if CState.unit_count(sa) + CState.unit_count(e) > CData.ARMY_MAX else 0])
		elif CState.is_human(ps, ef) and CState.friendly(ps, f, ef) and CRules.together(ps, sa, e) == "":
			out.append([id, 1])
	return out


## A path for the overlay: {army, pts (map points from the army's cell),
## now (last point reached this turn), kind}; an attack or a siege ends on
## its target.
func path_entry(a: Dictionary, rt: Dictionary) -> Dictionary:
	var pts: Array = [MapOverlay.cell_point(CState.cell(a))]
	var now := 0
	var cells: Array = rt["path"]
	for k in cells.size():
		pts.append(MapOverlay.cell_point(int(cells[k])))
		if int(rt["t"][k]) == 0:
			now = k + 1
	var aim: Dictionary = rt.get("aim", {})
	var kind := str(aim.get("kind", "move"))
	if int(aim.get("adjacent", 0)) != 0 and aim.has("cell"):
		pts.append(MapOverlay.cell_point(int(aim["cell"])))
		if now == cells.size():
			now += 1  # reached this turn: the strike is this turn too
	var out := {"army": int(a["id"]), "pts": pts, "now": now, "kind": kind}
	if kind == "merge":
		var t := CState.army(ps, int(aim.get("join", -1)))
		if not t.is_empty():
			out["caption"] = "Too many units to merge" if CState.unit_count(a) + CState.unit_count(t) > CData.ARMY_MAX \
				else "Merge into army (%d units)" % CState.unit_count(t)
	return out


# --------------------------------------------------------------- replay ---

## Version 6: remember the positions shown; a newer turn with step logs
## queues a replay from the positions last shown.
func _note_positions() -> void:
	if st.is_empty() or not CState.grid_on(st):
		return
	var turn := int(st["turn"])
	if _shown_turn >= 0 and turn == _shown_turn + 1 and not _shown_cells.is_empty():
		var steps: Array = []
		for e in st["events"]:
			if str(e["k"]) == "moves" and int(e["turn"]) == turn - 1:
				steps.append_array(e["steps"])
		var marks: Array = []
		for e in st["events"]:
			if int(e["turn"]) != turn - 1 or str(e["k"]) != "battle":
				continue
			var at := MapOverlay.cell_point(CGrid.site(int(e["r"])))
			for e2 in st["events"]:
				if str(e2["k"]) == "intercepted" and int(e2["turn"]) == turn - 1 and int(e2["r"]) == int(e["r"]) and e2.has("x"):
					at = MapOverlay.cell_point(CGrid.at(int(e2["x"]), int(e2["y"])))
			marks.append(at)
		if not steps.is_empty() or not marks.is_empty():
			_replay_q = {"steps": steps, "from": _shown_cells.duplicate(), "marks": marks}
	if turn != _shown_turn or replay.is_empty():
		_shown_turn = turn
		var cells := {}
		for a in st["armies"]:
			cells[int(a["id"])] = CState.cell(a)
		_shown_cells = cells


## Start a queued replay: the steps grouped in rounds (a round ends where
## the army ids stop rising: the rules move armies by id within a round).
func _start_replay() -> void:
	var q := _replay_q
	_replay_q = {}
	var rounds: Array = []
	var cur: Array = []
	var last := -1
	for stp in q["steps"]:
		var id := int(stp[0])
		if id <= last and not cur.is_empty():
			rounds.append(cur)
			cur = []
		cur.append([id, MapOverlay.cell_point(CGrid.at(int(stp[1]), int(stp[2])))])
		last = id
	if not cur.is_empty():
		rounds.append(cur)
	var pos := {}
	var from: Dictionary = q["from"]
	for rd in rounds:
		for e in rd:
			var id := int(e[0])
			if not pos.has(id):
				pos[id] = MapOverlay.cell_point(int(from[id])) if from.has(id) else e[1]
	replay = {"rounds": rounds, "k": 0, "t": 0.0, "pos": pos, "marks": q["marks"]}
	overlay.replay_pos = pos.duplicate()
	var trails := {}
	for id in pos:
		trails[id] = [pos[id]]
	overlay.replay_trail = trails
	_update_hint()
	_t("campaign_replay", {"rounds": rounds.size()})


func _end_replay() -> void:
	if replay.is_empty():
		return
	for m in replay["marks"]:
		overlay.markers.append([m, 3.0])
	replay = {}
	overlay.replay_pos = {}
	overlay.replay_trail = {}
	overlay.queue_redraw()
	_update_hint()


func _step_replay(delta: float) -> void:
	var rounds: Array = replay["rounds"]
	var k := int(replay["k"])
	if k >= rounds.size():
		_end_replay()
		return
	var t := float(replay["t"]) + delta / REPLAY_ROUND
	if _replay_freeze >= 0 and k >= _replay_freeze:
		t = 0.5
	var pos: Dictionary = replay["pos"]
	var shown := pos.duplicate()
	for e in rounds[k]:
		var id := int(e[0])
		shown[id] = (pos[id] as Vector2).lerp(e[1], clampf(t, 0.0, 1.0))
	if t >= 1.0:
		for e in rounds[k]:
			pos[int(e[0])] = e[1]
			if overlay.replay_trail.has(int(e[0])):
				(overlay.replay_trail[int(e[0])] as Array).append(e[1])
		replay["k"] = k + 1
		t = 0.0
	replay["t"] = t
	overlay.replay_pos = shown
	overlay.queue_redraw()


func select_army(id: int) -> void:
	sel_army = id
	merge_tap = -1
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
	if not _replay_q.is_empty() and replay.is_empty() and not _blocked():
		_start_replay()
	if not replay.is_empty():
		_step_replay(delta)
	if not overlay.markers.is_empty():
		var keep: Array = []
		for m in overlay.markers:
			m[1] = float(m[1]) - delta
			if float(m[1]) > 0.0:
				keep.append(m)
		overlay.markers = keep
		overlay.queue_redraw()
	_keys(delta)
	_place_key()


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
			if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and sel_army >= 0 and _g():
				_mouse_pan = false
				_plan_at(mb.position)
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and sel_army >= 0:
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
	if e.pressed and map_key.expanded and _key_modal() and _touches.is_empty():
		map_key.set_expanded(false)  # a tap on the map closes the key on a phone
		_skip_release = true
		return
	if e.pressed and not replay.is_empty():
		_end_replay()  # a tap skips the replay
		_touches.clear()
		_skip_release = true
		return
	if not e.pressed and _skip_release:
		_skip_release = false
		_touches.erase(e.index)
		return
	if e.pressed:
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_press_pos = e.position
			_dragging = false
			_multi = false
			_drag_army = -1
			if _g() and f >= 0:
				# A drag that starts on one of our free armies plans its march.
				var id := overlay.army_at(e.position)
				var a := CState.army(ps, id) if id >= 0 else {}
				if not a.is_empty() and int(a["f"]) == f and int(a["busy"]) == 0:
					_drag_army = id
		else:
			_multi = true
			_drag_army = -1
			_drag_preview(-1, -1)
			_start_pinch()
		return
	if _drag_army >= 0 and _dragging and not _multi and _touches.has(e.index):
		_touches.erase(e.index)
		var id2 := _drag_army
		_drag_army = -1
		_dragging = false
		_drag_preview(-1, -1)
		if sel_army != id2:
			select_army(id2)
		_plan_at(e.position)
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
	if _dragging and _drag_army >= 0:
		var tg := _target_at(e.position)
		if int(tg[0]) != _drag_cell or int(tg[1]) != _drag_tgt:
			_drag_preview(int(tg[0]), int(tg[1]))
		return
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
	if _g():
		_tap6(p)
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


## Version 6 tap: one of our armies selects it (again: deselects); with one
## of ours selected, an enemy army is an attack, a settlement a march onto
## it (siege, or inside our walls), any land a march there; otherwise a
## settlement or region opens its panel, the sea clears the selection.
func _tap6(p: Vector2) -> void:
	var id := overlay.army_at(p)
	var sa := CState.army(ps, sel_army) if sel_army >= 0 else {}
	var mine_sel := not sa.is_empty() and int(sa["f"]) == f and int(sa["busy"]) == 0
	if id >= 0:
		var e := CState.army(ps, id)
		if id == sel_army:
			close_side()
			return
		var ef := int(e["f"])
		if mine_sel and ef == f:
			_merge_tap_at(id)  # merge (first tap previews)
			return
		if mine_sel and ef != f and CState.is_human(ps, ef) and CState.friendly(ps, f, ef) and CRules.together(ps, sa, e) == "":
			merge_tap = -1
			panels.show_exchange(sel_army, id)  # the ally's army next to ours: a gift
			_t("campaign_input", {"what": "exchange_gift"})
			return
		if not mine_sel or CState.friendly(ps, f, ef):
			select_army(id)
			_t("campaign_input", {"what": "select_army"})
			return
	if mine_sel:
		merge_tap = -1
		_plan_at(p)
		return
	var sr := overlay.settlement_at(p)
	if sr >= 0:
		select_region(sr)
		return
	var r := Geo.region_at(_map_point(p))
	if r >= 0:
		select_region(r)
		return
	close_side()


## What screen point p targets for the selected army: [cell, tgt] (an enemy
## army, a settlement's cell, else the land cell under it; -1 none).
func _target_at(p: Vector2) -> Array:
	var id := overlay.army_at(p)
	if id >= 0 and id != sel_army and id != _drag_army:
		var e := CState.army(ps, id)
		if not e.is_empty() and CState.at_war(ps, f, int(e["f"])):
			return [CState.cell(e), id]
	var sr := overlay.settlement_at(p)
	if sr >= 0:
		return [CGrid.site(sr), -1]
	var c := MapOverlay.cell_of_point(_map_point(p))
	if c >= 0 and CGrid.passable(c):
		return [c, -1]
	return [-1, -1]


## Plan the selected army's march to what screen point p targets.
func _plan_at(p: Vector2) -> void:
	var tg := _target_at(p)
	if int(tg[0]) < 0:
		_flash("Not on land.")
		return
	set_move6(sel_army, int(tg[0]), int(tg[1]))
	if sel_army >= 0 and not CState.army(ps, sel_army).is_empty():
		show_side(func(box): panels.army_panel(box, sel_army))


## The path preview while dragging an army (cell -1: none).
func _drag_preview(c: int, tgt: int) -> void:
	_drag_cell = c
	_drag_tgt = tgt
	overlay.drag = {}
	var a := CState.army(ps, _drag_army)
	if c >= 0 and not a.is_empty():
		var rt := CRules.plan_path(ps, a, c, tgt, CData.MODE_SIEGE)
		if not rt.has("why"):
			var pe := path_entry(a, rt)
			pe["drag"] = 1
			overlay.drag = pe
	overlay.queue_redraw()
