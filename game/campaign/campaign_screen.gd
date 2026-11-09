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

const ZProf := preload("res://game/campaign/zprof.gd")
const TapProf := preload("res://game/campaign/tap_prof.gd")
const AudioFx := preload("res://game/audio.gd")
const TouchScroll := preload("res://game/touch_scroll.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CDip := preload("res://campaign/cdip.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const UT := preload("res://sim/unit_types.gd")
const Geo := preload("res://game/campaign/map_geo.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
const LoadingPanel := preload("res://game/campaign/loading_panel.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const MapOverlay := preload("res://game/campaign/map_overlay.gd")
const MinisLayer := preload("res://game/campaign/minis_layer.gd")
const TownLayer := preload("res://game/campaign/town_layer.gd")
const LandTrees := preload("res://game/campaign/landtrees.gd")
const TableFrame := preload("res://game/campaign/table_frame.gd")
const Weather := preload("res://game/weather.gd")
const CWeather := preload("res://campaign/cweather.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const Traits := preload("res://game/unit_traits.gd")
const Saves := preload("res://game/campaign/saves.gd")
const Panels := preload("res://game/campaign/campaign_panels.gd")
const AutoResolve := preload("res://game/campaign/auto_resolve.gd")
const BattleScreen := preload("res://game/campaign/battle_screen.gd")
const Battle := preload("res://game/battle.gd")
const SeaBattle := preload("res://game/sea_battle.gd")
const CSeaBattle := preload("res://campaign/cseabattle.gd")
const UnitBook := preload("res://game/unit_book.gd")
const UnitEntry := preload("res://game/unit_entry.gd")
const Controls := preload("res://game/controls.gd")
const OnlineUI := preload("res://game/campaign/online_ui.gd")
const CoopSession := preload("res://game/net/coop_session.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CLanes := preload("res://campaign/clanes.gd")
const CSea := preload("res://campaign/csea.gd")
const CChars := preload("res://campaign/cchars.gd")
const MapKey := preload("res://game/campaign/map_key.gd")
const UiScale := preload("res://game/ui_scale.gd")
const StoryView := preload("res://game/campaign/story_view.gd")
const DieRoll := preload("res://game/campaign/die_roll.gd")
const TableMotion := preload("res://game/table_motion.gd")
const Tutorial := preload("res://game/campaign/tutorial.gd")
const Tips := preload("res://game/campaign/tips.gd")
const CommandBar := preload("res://game/campaign/command_bar.gd")
const GameMenu := preload("res://game/campaign/game_menu.gd")
const FogView := preload("res://game/campaign/fog_view.gd")
const FogLayer := preload("res://game/campaign/fog_layer.gd")

const ZOOM_MIN := 0.2
const ZOOM_MAX := 2.5
const DRAG_THRESHOLD := 14.0
const TWO_TAP_DOWN_MS := 120    # two-finger tap: both fingers down within, up within TWO_TAP_TOTAL_MS of the first
const TWO_TAP_TOTAL_MS := 250
const TWO_TAP_MOVE := 12.0
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
var sel_fleet := -1            # a fleet (a pack with ships, campaign/cfleet.gd)
var dock_mode := -1            # (Docking) the fleet whose next tap on one of our port cities orders fdock, -1 none
var _wave_redraw := 0.0        # fleets bob on the waves: the overlay redraws a few times a second
var zoom := 0.6
var offset := Vector2.ZERO     # screen = map * zoom + offset

var world: Node2D
var map_view: MapView
var overlay: MapOverlay
var minis: MinisLayer
var town_layer: TownLayer
var fog_layer: Node2D
var land_trees: LandTrees
var _mv_zoom := -1.0   # the zoom the map view was last drawn at
var _mv_settle := 0.0
var table_frame: TableFrame
var ui: Control
var top_label: Label
var top_box: HBoxContainer
var side: PanelContainer
var side_box: VBoxContainer
var side_scroll: ScrollContainer
var cmd_bar: CommandBar        # the selection as cards along the bottom (command_bar.gd)
## Testing aid (--details; the input tests): a selection opens the full side
## panel as it did before the command bar.
var details_on_select := false
const SAVE_DELAY_MS := 1500     # save_plan: a plan edit is saved this long after the last one
var _save_due := 0              # ticks (ms) when the pending plan save is written, 0 none
var _bar_sig: Array = []        # _refresh_bar: what the command bar was last built for (this frame)
var _bar_ps: Dictionary = {}
var _bar_st: Dictionary = {}
var _drawn_ps: Dictionary = {}  # the state the map / overlay were last drawn for (_refresh_map6)
var _drawn_st: Dictionary = {}
var _drawn_f := -2
var _drawn_sig: Array = []
var _resolving := false        # _resolve_soon: the turn resolves in two frames
var _defer_sel := false         # select_army: the selection's reach etc. in the next frame (_refresh_map6)
var _map6_next := false         # ... asked for
var _map6_frame := 0            # ... in the first _tick of a later process frame (a frame count, not a draw
                                # callback: headless runs get it too; a frame is drawn in between)
var no_bar := false            # testing aid --no-bar: the old layout (side panel only)
var _force_side := false       # open_details is building the side panel
var end_button: Button
var battles_button: Button
var hint: Label
var _hint_plate: Panel = null
var _hint_key := ""
var map_key: MapKey            # the map key (bottom left)
var dialog: PanelContainer
var dialog_box: VBoxContainer
var dialog_title: Label
var dialog_rule: Control
var game_menu: GameMenu        # the in-game Menu overlay (game_menu.gd)
var top_emblem: Control        # the setting's emblem, left of the top bar
var _top_title := -1           # the faction name's face: 1 the display face, 0 the UI face
var dialog_buttons: HBoxContainer
var dialog_scroll: ScrollContainer
var cover: ColorRect
var book: UnitBook
var controls_page: Controls
var panels: Panels
var tutorial: Tutorial  # the guided first campaign (game/campaign/tutorial.gd): its cards, pointer and End turn gate
var story: StoryView  # a story campaign's dialogue, pressures and log (game/campaign/story_view.gd)
var battle = null  # Battle, or SeaBattle for a sea battle (N3a)
var _battle_built: Dictionary = {}
## The battle screen's snapshot of the battle in progress (taken at its start).
var _battle_snap: Dictionary = {}
var _battle_id := -1
var _resolver: AutoResolve = null
var _progress: ProgressBar = null
var _auto_box: Control = null   # the auto-resolve dialog's content (the die rolls in it)
var _die: Control = null        # the die rolling on an auto-resolve (tabletop pass 5), null otherwise
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
var _rmb_down := false           # real mouse: right button held (a click orders, a drag pans)
var _rmb_start := Vector2.ZERO
var _rmb_dragged := false
var _press_mouse := false        # the press now down is the real mouse's left button (emulated touch)
var last_mouse := false          # the last map input came from a real mouse (the hint's words)
var _tt_t0 := 0                  # two-finger tap: first finger down (ms)
var _tt_ok := false
var _tt_start := {}

# Version 6.
var undo_button: Button
var deselect_button: Button    # bottom right, while something is selected
var bottom_bar: HBoxContainer  # Deselect, Undo, End turn
var top_date: Label
var top_money: Label
var top_income: Label
var _side_key := ""            # what the side panel shows ("a<army>" / "r<region>")
var _side_gen := 0             # side panel builds (a stale scroll restore is dropped)
var _dlg_gen := 0              # dialog builds (likewise)
var _undo: Array = []          # earlier order lists (Undo)
var _routes := {}              # army id -> plan_path result for its plan (per preview)
var _drag_army := -1           # an army being dragged to a destination
var _drag_cell := -1
var _drag_tgt := -1
var merge_tap := -1            # own army tapped once with an army selected: the merge previewed
var _marks_for := -1           # the army _marks were computed for (until the plan changes)
var _marks: Array = []         # _merge_marks of _marks_for (per preview)
var _shown_turn := -1          # the turn whose army positions are _shown_cells
var _shown_cells := {}         # army id -> cell, as last shown
var _replay_q: Dictionary = {} # a replay waiting for the dialogs to close
var replay: Dictionary = {}    # the replay running: {rounds, k, t, cur {id: map pt}, from {id: map pt}}
var _replay_freeze := -1
var _skip_release := false       # testing aid: hold the replay half way through this round
const REPLAY_ROUND := 0.13     # seconds per round of steps


var _hint_cb := Callable()  # the lambda given to Kit.hint_cb, cleared in _exit_tree


func _ready() -> void:
	if "--all-seeing" in OS.get_cmdline_user_args():
		FogView.all_seeing = true   # testing aid: no fog of war (fog_view.gd)
	_tele = get_node_or_null("/root/Telemetry")
	panels = Panels.new(self)
	_hint_cb = func(t: String): show_toast(t)
	Kit.hint_cb = _hint_cb
	world = Node2D.new()
	add_child(world)
	map_view = MapView.new()
	world.add_child(map_view)
	var ol := CanvasLayer.new()
	ol.layer = 1
	add_child(ol)
	minis = MinisLayer.new()
	ol.add_child(minis)
	overlay = MapOverlay.new()
	minis.overlay = overlay
	land_trees = LandTrees.new()   # the landscape's trees and rocks as models: under the towns, over the map
	world.add_child(land_trees)
	land_trees.overlay = overlay
	town_layer = TownLayer.new()   # the towns assembled from kit pieces, on the map itself (under the overlay)
	world.add_child(town_layer)
	town_layer.overlay = overlay
	MinisLayer.towns = town_layer
	fog_layer = FogLayer.new()   # the fog of war over the map, towns and trees (fog_layer.gd), under the overlay
	world.add_child(fog_layer)
	ol.add_child(overlay)
	var frame_layer := CanvasLayer.new()   # the map-table frame: over the map and its markers, under the interface
	frame_layer.layer = 1
	add_child(frame_layer)
	table_frame = TableFrame.new()
	frame_layer.add_child(table_frame)
	var ul := CanvasLayer.new()
	ul.layer = 2
	add_child(ul)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ul.add_child(ui)
	_build_ui()
	story = StoryView.new(self)
	story.setup()
	tutorial = Tutorial.new(self)
	tutorial.setup()
	Tips.presenter = _show_tip
	book = UnitBook.new()
	ui.add_child(book)
	controls_page = Controls.new()
	ui.add_child(controls_page)
	if online != null:
		_load_online()
	elif not data.is_empty():
		_load_data()
	var tp := TapProf.wanted()   # testing aid --prof-tap (tap_prof.gd)
	if tp != "":
		add_child(TapProf.new(self, tp))


## Open a campaign (data from saves.gd or a new one).
func open(p_data: Dictionary, p_slot: String) -> void:
	PackView.use_state(p_data.get("state", {}))
	data = p_data
	slot = p_slot
	if is_inside_tree():
		_load_data()


## Open an online campaign (its controller has been created by Net; this
## screen opens it).
func open_online(oc) -> void:
	PackView.use_state(oc.st)
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


## Testing aids: --cam-zoom=Z --cam-region=key --close-dialog --handover-start
## --select-region=key --select-army=N (Nth army of the player)
## --plan-move=N:key --camp-attack=N:key --camp-siege=N:key[:turns] --camp-assault=key --camp-besieged=key:faction --camp-fight --camp-auto --sim-turns=N --dialog-scroll=PX --side-scroll=PX
## --camp-exchange=N:M:k (version 6: the exchange panel)
## --camp-recruit=N:key:k --camp-raise=key:k (version 6: recruits into an army, the raise picker)
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
		elif a.begins_with("--tap-crossing="):
			# testing aid: centre on crossing N and tap it (its name in the hint bar)
			await get_tree().create_timer(0.3).timeout
			var cp: Vector2 = Geo.crossings()[int(v)]["p"]
			zoom = 1.2
			offset = _vp() * 0.5 - cp * zoom
			_clamp_view()
			_refresh_map()
			await get_tree().process_frame
			_tap(cp * zoom + offset)
		elif a == "--handover-start":
			if cover.visible:  # testing aid: press "Start my turn" on the hand-over
				cover.visible = false
				_set_planner(f, true)
				close_dialog()
		elif a.begins_with("--map-key="):
			map_key.persist = false  # testing aid: open (1) or close (0) the map key
			map_key.set_expanded(v == "1")
		elif a.begins_with("--dialog-scroll="):
			await get_tree().create_timer(1.5).timeout
			dialog_scroll.scroll_vertical = int(v)  # testing aid
		elif a == "--no-bar":
			no_bar = true
			details_on_select = true
		elif a.begins_with("--popup="):
			# testing aid --popup=build:key | raise:key | ship:key | recruit:N (the command bar's popups; recruit: the player's Nth army)
			var kind: String = v.get_slice(":", 0)
			var arg: String = v.get_slice(":", 1)
			if kind == "recruit":
				var mine_p := CState.armies_of(ps, f)
				if int(arg) < mine_p.size():
					select_army(int(mine_p[int(arg)]["id"]))
					panels.show_army_recruit(int(mine_p[int(arg)]["id"]))
			else:
				var rp := CData.region_index(arg)
				select_region(rp)
				match kind:
					"build":
						panels.show_build(rp)
					"ship":
						panels.show_raise(rp, "ship")
					_:
						panels.show_raise(rp)
		elif a == "--details":
			details_on_select = true  # testing aid: selections open the full side panel as before
			open_details()
		elif a.begins_with("--side-scroll="):
			await get_tree().create_timer(1.0).timeout
			if not side.visible:
				open_details()
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
		elif a.begins_with("--camp-recruit="):
			# --camp-recruit=N:key:k (version 6): put the player's Nth army
			# inside the walls of region key, select it and plan k recruits
			# into it (the first recruitable lines of its card).
			var mine14 := CState.armies_of(st, f)
			var n14 := int(v.get_slice(":", 0))
			var r14 := CData.region_index(v.get_slice(":", 1))
			if n14 < mine14.size() and r14 >= 0:
				var id14 := int(mine14[n14]["id"])
				CState.place(mine14[n14], CGrid.site(r14))
				_replan()
				focus_region(r14, 1.4)
				for k14 in int(v.get_slice(":", 2)):
					for o14 in Panels.best_options(ps, f, r14):
						if o14["ok"]:
							add_order({"t": "recruit", "r": r14, "unit": str(o14["t"]), "army": id14})
							break
				select_army(id14)
		elif a.begins_with("--camp-raise="):
			# --camp-raise=key:k (version 6): the region panel of key and the
			# Raise new army picker with k units picked.
			var r15 := CData.region_index(v.get_slice(":", 0))
			if r15 >= 0:
				focus_region(r15, 1.4)
				select_region(r15)
				panels.show_raise(r15)
				var opts15 := Panels.best_options(ps, f, r15)
				for k15 in int(v.get_slice(":", 1)):
					if k15 < opts15.size():
						panels._raise_pick(str(opts15[k15]["t"]), 1)
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
		elif a.begins_with("--camp-assault="):
			# --camp-assault=region (after --camp-siege): the besiegers storm it now.
			var b16 := CRules.start_siege_battle(st, CData.region_index(v), "assault")
			if not b16.is_empty():
				b16.erase("new")
				st["phase"] = "battles"
				_next_step()
		elif a == "--camp-auto":
			var pb2 := CTurn.pending_for(st)
			if not pb2.is_empty():
				auto_resolve(int(pb2[0]["id"]))
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
				"chronicle":
					panels.show_chronicle()
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
	if _save_due > 0:
		save()
	exit_requested.emit()


## A plan edit (an order added, changed, undone): the save is written a moment later, once for a burst of taps,
## not in the tap's frame (a save serialises the whole campaign: 4-6 ms here at turn 10, several times that on a
## tablet's browser). Flushed by save(), leaving the screen, the window losing focus or closing (_notification).
func save_plan() -> void:
	_save_due = Time.get_ticks_msec() + SAVE_DELAY_MS


## First-time tips (game/campaign/tips.gd): a toast with a Got it.
func _show_tip(text: String, _key: String) -> void:
	show_toast(text, ["Got it", func(): pass])


func _exit_tree() -> void:
	# a static holding a lambda that captures this screen outlives it: at quit the engine freed it twice (heap abort)
	if Kit.hint_cb == _hint_cb:
		Kit.hint_cb = Callable()
	if Tips.presenter == Callable(self, "_show_tip"):
		Tips.presenter = Callable()
	Tips.suppress = false


## The tips that follow the state (not a tap): a siege of ours, a fleet carrying an army, a proposal made to us.
func tip_scan() -> void:
	if f < 0 or ps.is_empty():
		return
	for sg in ps.get("sieges", []):
		if int(sg["f"]) == f:
			Tips.show("siege_laid")
			break
	for fl in ps.get("fleets", []):
		if int(fl["f"]) == f and not (fl["carry"] as Array).is_empty():
			Tips.show("fleet_boarded")
			break
	for p in st.get("proposals", []):
		if int(p["to"]) == f and CState.is_human(st, f):
			Tips.show("proposal_received")
			break


func _save_tick() -> void:
	if _save_due > 0 and Time.get_ticks_msec() >= _save_due:
		save()


func _notification(what: int) -> void:
	if _save_due > 0 and what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT,
			NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_EXIT_TREE]:
		save()


func save() -> void:
	_save_due = 0
	if online != null:
		if f >= 0 and not st.is_empty() and str(st.get("phase", "")) == "plan" and not online.i_submitted():
			online.set_plan(orders)
		return
	var t_sv := ZProf.begin()
	if f >= 0:
		data["session"]["plans"][str(f)] = orders.duplicate(true)
	data["state"] = st
	if not Saves.save(slot, data):
		_t("campaign_error", {"what": "save failed", "slot": slot})
	ZProf.add("h_save", t_sv)


# ----------------------------------------------------------------- flow ---

## Decide what happens next: game over, pending battles, the next player's
## planning (after a hand-over in hot seat), or resolving the turn.
func _next_step() -> void:
	if online != null:
		onl.step()
		return
	close_dialog()
	if str(st["phase"]) == "over":
		if story.step():
			return  # (a story campaign) its last news and its ending first
		f = -1
		_refresh()
		panels.show_game_over()
		return
	var pending := CTurn.pending_for(st)
	if not pending.is_empty() and story.step(true):
		return  # (a story campaign) the news that set off the battle first
	if not pending.is_empty():
		AudioFx.play("battle_pending", 0.9, 0.0, "horn")
		f = int(CRules.battle_humans(st, pending[0])[0])
		_set_planner(f, false)
		var seen := int(data["session"]["seen"].get(str(f), -1))
		# Setting "always auto-resolve": no choice dialog.
		var then := func(): panels.show_battles()
		if str(st["settings"].get("autoresolve", "ask")) == "auto" and not tutorial.is_lesson_battle(pending[0]):
			var bid := int(pending[0]["id"])
			then = func(): auto_resolve(bid)
		if seen < int(st["turn"]) and int(st["turn"]) > 0:
			data["session"]["seen"][str(f)] = int(st["turn"])
			save()
			panels.show_summary(seen, then)
		else:
			then.call()
		return
	if story.step():
		return  # (a story campaign) news to read or a choice to make first
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
		_resolve_soon()
		return
	var hot := (st["humans"] as Array).size() > 1
	if hot and f != next:
		f = next
		_show_handover()
		return
	_set_planner(next, true)


func _set_planner(p_f: int, start: bool) -> void:
	if _save_due > 0:
		save()   # (a pending plan save is the old planner's)
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
	_clear_more()
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
	sw.add_child(Kit.faction_mark(f, 30))
	sw.add_child(Kit.label("%s's turn" % CData.faction_name(f), 26))
	box.add_child(sw)
	box.add_child(Kit.label("Pass the device to the %s player. %s." % [CData.FACTIONS[f]["adj"], CData.date_text(int(st["turn"]))], 16, Kit.COL_DIM))
	show_dialog("", box, [["Start my turn", func():
		cover.visible = false
		_set_planner(f, true)]])


func end_turn(skip_warnings: bool = false) -> void:
	if f < 0 or not CTurn.pending_for(st).is_empty():
		return
	if story.guard_end():
		return
	if tutorial.guard_end():
		return
	if online != null and online.i_submitted():
		return
	if not skip_warnings:
		var warn := panels.warnings()
		if not warn.is_empty():
			panels.show_warnings(warn)
			return
	AudioFx.play("end_turn", 0.9, 0.0, "ui")
	tutorial.on_end()
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


## The turn's resolution (the rules and the AI: 25-30 ms on a desktop, over a second in a tablet's browser) runs
## two frames after the End turn tap, under a "Resolving the turn" dialog drawn first: the tap answers at once.
func _resolve_soon() -> void:
	if _resolving:
		return
	_resolving = true
	var lp = null
	if LoadingPanel.slow_resolve():
		# The last resolve took over half a second: the key art panel with a tip, as the battle build has.
		lp = LoadingPanel.open(get_tree().root, "Resolving the turn", 1, str(st.get("pack", CData.pack)))
		await lp.step("The armies march, the AI moves")
		await get_tree().process_frame
	else:
		var box := Kit.vbox(8)
		box.add_child(Kit.label("The armies march, the AI moves, battles are joined...", Kit.FONT, Color.WHITE, true))
		show_dialog("Resolving the turn", box, [], 460)
		dialog_kind = "resolving"
		await get_tree().process_frame
		await get_tree().process_frame   # (a frame drawn and shown: on the web the page only shows it between frames)
	_resolving = false
	if is_inside_tree():
		_resolve_turn()
	if lp != null and is_instance_valid(lp):
		await lp.done()
		lp.close()


func _resolve_turn() -> void:
	var subs: Array = data["session"]["subs"]
	var t0 := Time.get_ticks_msec()
	st = CTurn.resolve_turn(st, subs)
	data["session"]["subs"] = []
	data["session"]["plans"] = {}
	LoadingPanel.last_resolve_ms = float(Time.get_ticks_msec() - t0)
	_t("campaign_turn_resolved", {"turn": int(st["turn"]), "ms": Time.get_ticks_msec() - t0,
		"hash": CState.hash_text(st), "battles": (st["battles"] as Array).size()})
	f = -1
	AudioFx.play("turn_resolved", 0.8, 0.0, "horn")
	save()
	_next_step()


# ------------------------------------------------------------- planning ---

## Re-run the preview of the plan; drop orders that no longer apply. `pre`: the preview of exactly these
## orders already made (add_order's check), used as it is when it has no errors (CTurn.preview is pure).
func _replan(pre: Dictionary = {}) -> void:
	_routes = {}
	_marks_for = -1
	if f < 0:
		ps = st
		moves = []
		_refresh()
		return
	for guard in 8:
		var t_pv := ZProf.begin()
		var pv: Dictionary = pre if guard == 0 and not pre.is_empty() and (pre["errors"] as Array).is_empty() else CTurn.preview(st, f, orders)
		ZProf.add("h_preview", t_pv)
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
	var t_pv := ZProf.begin()
	var pv := CTurn.preview(st, f, orders + [o])
	ZProf.add("h_preview", t_pv)
	for e in pv["errors"]:
		if int(e[0]) == orders.size():
			AudioFx.play("refused", 0.9, 0.0, "ui")
			_flash(str(e[1]))
			return str(e[1])
	_push_undo()
	AudioFx.play("chime" if str(o.get("t", "")) in ["propose", "answer", "accept_offer", "decline_offer", "gift_money", "gift_region", "buy_region"] else "order_ok", 0.8, 0.0, "ui")
	orders.append(o)
	_replan(pv)
	save_plan()
	return ""


## Several orders at once (one Undo step); none is added if any is refused.
func add_orders(list: Array) -> String:
	var pv := CTurn.preview(st, f, orders + list)
	for e in pv["errors"]:
		if int(e[0]) >= orders.size():
			AudioFx.play("refused", 0.9, 0.0, "ui")
			_flash(str(e[1]))
			return str(e[1])
	_push_undo()
	AudioFx.play("order_ok", 0.8, 0.0, "ui")
	orders.append_array(list)
	_replan(pv)
	save_plan()
	return ""


## Replace the whole plan with `list` (one Undo step), e.g. a pending order
## rewritten in place; nothing changes if any order of it is refused.
func set_orders(list: Array) -> String:
	var pv := CTurn.preview(st, f, list)
	for e in pv["errors"]:
		_flash(str(e[1]))
		return str(e[1])
	_push_undo()
	orders = list
	_replan(pv)
	save_plan()
	return ""


## Version 6: the planned recruit orders into army (it would be mustering).
func recruits_into(army: int) -> Array:
	var out: Array = []
	for o in orders:
		if str(o["t"]) == "recruit" and int(o.get("army", -1)) == army:
			out.append(o)
	return out


## Version 6: a march planned for an army with recruits planned for it:
## the toast asks to cancel the recruits (an army taking recruits cannot
## march this turn); never silently. Returns true when it asked.
func _muster_guard(army: int, then: Callable) -> bool:
	var rec := recruits_into(army)
	if rec.is_empty():
		return false
	var n := rec.size()
	show_toast("This army is taking %d recruit%s this turn: an army taking recruits cannot march until the next turn." % [n, "" if n == 1 else "s"],
		[["Cancel recruits and march", func():
			remove_orders(func(o): return str(o["t"]) == "recruit" and int(o.get("army", -1)) == army)
			then.call()
			if sel_army >= 0 and not CState.army(ps, sel_army).is_empty():
				show_side(func(box): panels.army_panel(box, sel_army))],
		["Keep recruiting", func(): pass]])
	_t("campaign_input", {"what": "muster_toast"})
	return true


func remove_orders(pred: Callable) -> void:
	var keep: Array = []
	for o in orders:
		if not pred.call(o):
			keep.append(o)
	if keep.size() != orders.size():
		_push_undo()
	orders = keep
	_replan()
	save_plan()


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
	save_plan()
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
		save_plan()
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
	save_plan()
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
	var odds := "%d%% (%s)%s" % [Kit.shown_pct(od), Kit.BAND_WORDS[int(od["band"])],
		" " + str(od["no_way"]) if str(od.get("no_way", "")) != "" else ""]
	var city := str(CData.REGIONS[to]["city"])
	if CState.moves_on(ps):
		_march_toast(army, kind, to, odds)
		return
	match kind:
		"siege":
			show_toast("Lays siege to %s: no battle this turn; its supplies last %d turns, then it starves. Ladders after a turn of siege, a ram after two. Storming it now: %s." % [
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
			CData.faction_name(int(fo["by"])), Kit.shown_pct(fo["od"]), Kit.BAND_WORDS[int(fo["od"]["band"])]]
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
	elif why == "mustering":
		text = "This army is taking recruits this turn: it cannot march until the next turn."
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
	ui.move_child(_toast, bottom_bar.get_index())
	_place_toast()
	_place_toast.call_deferred()  # again once the wrapped label has its height
	ui.move_child(_toast, -1)
	var me_id := _toast.get_instance_id()  # (an id, not the node: a lambda capturing a node freed by then logs an error)
	get_tree().create_timer(6.0).timeout.connect(func():
		if is_instance_valid(_toast) and _toast.get_instance_id() == me_id:
			_toast.queue_free()
			_toast = null)


func _place_toast() -> void:
	if _toast == null or not is_instance_valid(_toast):
		return
	_toast.reset_size()
	var base := _vp().y - 64.0
	if cmd_bar != null and cmd_bar.shown:
		base -= cmd_bar.height() + 4.0
	_toast.position = Vector2(8, base - _toast.size.y)


func _flash(text: String) -> void:
	hint.text = text
	hint.modulate = Color(1, 0.7, 0.6)
	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_callback(func(): hint.modulate = Color(1, 1, 1); _update_hint())


## A tap that lands on a river crossing (and nothing else): its name in the
## hint bar for a few seconds. True when it did.
func _crossing_note(p: Vector2) -> bool:
	var id := MapView.crossing_near(_map_point(p), 16.0 / zoom)
	var info := Geo.crossings()
	if id < 0 or id >= info.size():
		return false
	var c: Dictionary = info[id]
	var river := str(Geo.RIVERS[int(c["river"])]["name"])
	hint.text = ("Bridge at %s (%s)" if int(c["kind"]) == 1 else "Ford of %s (%s)") % [str(c["name"]), river]
	hint.modulate = Color(1, 1, 1)
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_callback(func(): _update_hint())
	return true


# ------------------------------------------------------------------- UI ---

func _build_ui() -> void:
	# Top bar.
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", Kit.band_box(Kit.WOOD_BAND, 4.0))   # the wood band with its brass rule (game/rule_box.gd)
	top.name = "top_bar"
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = TOP_H
	ui.add_child(top)
	top_box = Kit.hbox(5)
	top.add_child(top_box)
	top_emblem = Kit.emblem(str(st.get("pack", CData.pack)), 34.0)   # the setting's mark (painted or drawn by the menu setting)
	top_emblem.name = "top_emblem"
	top_emblem.add_to_group("menu_emblem")
	top_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_box.add_child(top_emblem)
	# Faction, then the date (season icon), treasury and income a turn, each
	# with its icon; a tap opens the realm.
	var info := Kit.hbox(14)
	info.name = "top_info"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.clip_contents = true
	info.mouse_filter = Control.MOUSE_FILTER_STOP
	info.gui_input.connect(func(e):
		if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			panels.show_faction())
	top_box.add_child(info)
	top_label = Kit.title("", 18)   # the faction name in the display face (the UI face on narrow screens: _refresh_top)
	top_date = Kit.icon_label("", "summer", Kit.FONT)
	top_money = Kit.label_icon(Kit.label("", Kit.FONT), "treasury", Kit.COL_GOLD)
	top_income = Kit.icon_label("", "income", Kit.FONT)
	for l: Label in [top_label, top_date, top_money, top_income]:
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_FILL
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(l)
	top_label.text = " "  # an indent before the faction name, as before
	net_button = Kit.button("Online", func():
		if onl != null:
			onl.show_online(), 0)
	net_button.name = "net_status"
	net_button.visible = false
	net_button.clip_text = true
	net_button.custom_minimum_size.x = 96
	top_box.add_child(net_button)
	Kit.set_icon(net_button, "online")
	battles_button = Kit.icon_button("Battles", "battles", func(): panels.show_battles(), 0)
	top_box.add_child(battles_button)
	top_box.add_child(Kit.icon_button("Realm", "realm", func(): panels.show_faction(), 0))
	top_box.add_child(Kit.icon_button("Diplomacy", "diplomacy", func(): panels.show_diplomacy(), 0))
	top_box.add_child(Kit.icon_button("Goals", "goals", func(): panels.show_objectives(), 0))
	top_box.add_child(Kit.icon_button("Units", "units", func(): book.open(), 0))
	var menu_b := Kit.icon_button("", "menu", func(): panels.show_menu(), 46)
	menu_b.name = "menu"
	menu_b.tooltip_text = "Menu"
	top_box.add_child(menu_b)
	for nb in top_box.get_children():
		if nb is Button and nb != net_button:
			Kit.nav_style(nb)
	# Side panel (right).
	side = Kit.trim_panel(Kit.PANEL_BG, 10)
	side.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -PANEL_W
	side.offset_top = TOP_H + 4
	side.offset_bottom = -62  # clear of End turn
	side.offset_right = -4
	side.visible = false
	ui.add_child(side)
	side_scroll = TouchScroll.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER  # DISABLED would make the panel grow to its content's width
	side.add_child(side_scroll)
	side_box = Kit.vbox(6)
	side_box.size_flags_horizontal = Control.SIZE_FILL
	side_scroll.add_child(side_box)
	cmd_bar = CommandBar.new(self)
	ui.add_child(cmd_bar)
	get_viewport().size_changed.connect(_refresh_bar)
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
	hint.offset_left = MapKey.MARGIN * 2.0 + maxf(MapKey.BUTTON_W, MapKey.VIEW_W)
	hint.offset_right = hint.offset_left + 412
	# A translucent dark plate behind the hint, sized to its text (the hint sits partly on the table's parchment)
	_hint_plate = Panel.new()
	_hint_plate.show_behind_parent = true
	_hint_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0.04, 0.05, 0.07, 0.58)
	hsb.set_corner_radius_all(5)
	_hint_plate.add_theme_stylebox_override("panel", hsb)
	_hint_plate.visible = false
	hint.add_child(_hint_plate)
	ui.add_child(hint)
	map_key = MapKey.new()
	ui.add_child(map_key)
	map_key.set_expanded(MapKey.load_pref())
	# Bottom right, one row: Deselect, Undo (bare icons), End turn; hidden
	# ones leave no gap and a longer End turn text pushes the others left.
	bottom_bar = Kit.hbox(8)
	bottom_bar.name = "bottom_bar"
	bottom_bar.alignment = BoxContainer.ALIGNMENT_END
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bottom_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_bar.offset_right = -8
	bottom_bar.offset_bottom = -8
	ui.add_child(bottom_bar)
	# Deselect: clears the selection and closes its panel without scrolling
	# back to it (never a move: a button takes the tap from the map).
	deselect_button = Kit.icon_button("", "deselect", func(): deselect_all(), 56, 15)
	deselect_button.name = "deselect"
	deselect_button.tooltip_text = "Deselect"
	deselect_button.custom_minimum_size = Vector2(56, 48)
	deselect_button.visible = false
	bottom_bar.add_child(deselect_button)
	undo_button = Kit.icon_button("", "undo", func(): undo(), 56, 15)
	undo_button.name = "undo"
	undo_button.tooltip_text = "Undo"
	undo_button.custom_minimum_size = Vector2(56, 48)
	undo_button.visible = false
	bottom_bar.add_child(undo_button)
	end_button = Kit.hero_button("End turn", "end_turn", func(): end_turn(), 130, 18)
	bottom_bar.add_child(end_button)
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
	dialog = Kit.trim_panel(Color(0.1, 0.12, 0.11, 0.98), 12)
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	dialog.visible = false
	dialog.set_meta("dim", dim)
	ui.add_child(dialog)
	var dv := Kit.vbox(8)
	dialog.add_child(dv)
	dialog_title = Kit.title("", 22)   # the display face
	dialog_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog_title.custom_minimum_size.x = 40
	dv.add_child(dialog_title)
	dialog_rule = Kit.rule()
	dv.add_child(dialog_rule)
	dialog_scroll = TouchScroll.new()
	dialog_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dv.add_child(dialog_scroll)
	dialog_box = Kit.vbox(6)
	dialog_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_scroll.add_child(dialog_box)
	# The content's wrapped labels settle a frame or more after the dialog opens (slower on a phone): refit when its
	# minimum size changes, so the dialog is its content's height and never taller than the screen.
	dialog_box.minimum_size_changed.connect(func():
		if dialog.visible:
			_fit_dialog())
	dialog_buttons = Kit.hbox(8)
	dialog_buttons.alignment = BoxContainer.ALIGNMENT_END
	dv.add_child(dialog_buttons)
	_build_msel_ui()
	game_menu = GameMenu.new(self)   # the in-game Menu, over everything above
	ui.add_child(game_menu)


func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


## Show a modal dialog. buttons: [[text, callable], ...]; an empty callable
## just closes. The dialog fills most of a phone screen and is capped on a
## desktop.
func show_dialog(title: String, content: Control, buttons: Array, width: float = 620.0, tall: bool = false) -> void:
	for c in dialog_box.get_children():
		dialog_box.remove_child(c)
		c.queue_free()
	for c in dialog_buttons.get_children():
		dialog_buttons.remove_child(c)
		c.queue_free()
	# The same dialog shown again (a button in it re-rendered it) keeps its
	# scroll position; another dialog starts at the top.
	var keep := dialog_scroll.scroll_vertical if dialog.visible and title != "" and dialog_title.text == title else 0
	_dlg_gen += 1
	dialog_title.text = title
	dialog_title.visible = title != ""
	dialog_rule.visible = title != ""
	dialog_box.add_child(content)
	for bdef in buttons:
		var cb: Callable = bdef[1]
		var b := Kit.button(str(bdef[0]), func():
			if cb.is_valid():
				cb.call()
			else:
				close_dialog(), 110)
		b.name = "dlg_" + str(bdef[0]).replace(" ", "_")
		var di := _dialog_icon(str(bdef[0]))
		if di != "":
			Kit.set_icon(b, di)
		dialog_buttons.add_child(b)
	var vp := _vp()
	var w := minf(width, vp.x - 24)
	var h := minf(vp.y - 24, maxf(260.0, vp.y * 0.86))
	dialog.custom_minimum_size = Vector2(w, 0)
	dialog_scroll.custom_minimum_size = Vector2(w - 24, 0)
	dialog_scroll.set_meta("max_h", (h - 110) if tall else minf(h - 110, 560))
	dialog.size = Vector2(w, 0)
	dialog.reset_size()
	dialog.position = (vp - dialog.size) * 0.5
	dialog.visible = true
	dialog_kind = ""
	(dialog.get_meta("dim") as Control).visible = true
	if tutorial != null:
		tutorial.refresh()   # (a lesson over this popup shows its strip, which the dialog leaves room for)
		_fit_dialog()
	call_deferred("_center_dialog")
	_restore_scroll(dialog_scroll, keep, _dlg_gen, true)


## Icons for the dialogs' common buttons, by the start of their text.
const DIALOG_ICONS := [["Close", "close"], ["Cancel", "cancel"], ["Declare war", "war"], ["End turn", "end_turn"],
	["Raise army", "raise"], ["Recruit", "recruit"], ["Confirm", "accept"], ["Copy", "copy"],
	["Submit turn", "end_turn"], ["Lay siege", "siege"], ["Assault", "assault"], ["Cancel recruits", "cancel"]]


static func _dialog_icon(text: String) -> String:
	for d in DIALOG_ICONS:
		if text.begins_with(str(d[0])):
			return str(d[1])
	return ""


## Fit and centre the open dialog. Run once at once and again after the next
## two layouts: before the first layout the new content's wrapped labels are
## measured at their minimum width (a 40 px column: an intro label 564 px high,
## the content 1645), so the scroll area would take its cap and the dialog,
## which never shrinks by itself, kept that height with empty space inside
## and its buttons pushed down.
func _center_dialog() -> void:
	var gen := _dlg_gen
	_fit_dialog()
	for i in 2:
		await get_tree().process_frame
		if gen != _dlg_gen or not dialog.visible:
			return
		_fit_dialog()


func _fit_dialog() -> void:
	# The scroll area takes the content's height, up to the cap and up to what
	# is left of the screen once the title, rule and buttons are counted.
	var want := dialog_box.get_combined_minimum_size().y
	dialog_scroll.custom_minimum_size.y = 0.0
	dialog.reset_size()
	var overhead := dialog.get_combined_minimum_size().y
	var top := tutorial.reserve_top() if tutorial != null else 0.0
	var room := _vp().y - 16.0 - overhead - top
	dialog_scroll.custom_minimum_size.y = maxf(minf(want, minf(float(dialog_scroll.get_meta("max_h", 400.0)), room)), 0.0)
	dialog.reset_size()
	dialog.position = Vector2((_vp().x - dialog.size.x) * 0.5, top + (_vp().y - top - dialog.size.y) * 0.5)


func close_dialog() -> void:
	dialog.visible = false
	(dialog.get_meta("dim") as Control).visible = false
	if tutorial != null:
		tutorial.refresh()


func dialog_open() -> bool:
	return dialog.visible


func show_side(content_builder: Callable) -> void:
	# The command bar shows the selection; the side panel opens on demand
	# (Details) and then follows the selection.
	if _bar_on() and not side.visible and not _force_side and not details_on_select:
		_refresh_bar()
		return
	# Rebuilt for the same selection: keep the scroll position.
	var key := ("a%d" % sel_army) if sel_army >= 0 else (("f%d" % sel_fleet) if sel_fleet >= 0 else ("r%d" % sel_region))
	var keep := side_scroll.scroll_vertical if side.visible and key == _side_key else 0
	_side_key = key
	_side_gen += 1
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
	side_box.custom_minimum_size.x = w - 16.0 - side_scroll.get_v_scroll_bar().get_combined_minimum_size().x  # the panel never grows with its content
	side.visible = true
	_restore_scroll(side_scroll, keep, _side_gen, false)
	_update_deselect()
	_refresh_bar()


## A scroll position back once the rebuilt content is laid out (clamped by
## the container); dropped when the panel / dialog was rebuilt again since.
func _restore_scroll(sc: ScrollContainer, v: int, gen: int, dlg: bool) -> void:
	sc.scroll_vertical = v
	if v <= 0:
		return
	await get_tree().process_frame
	if not is_instance_valid(sc) or (_dlg_gen if dlg else _side_gen) != gen:
		return
	sc.scroll_vertical = v


## The command bar is the selection's view (a version 6 campaign).
func _bar_on() -> bool:
	return cmd_bar != null and _g() and not no_bar


## Rebuild the command bar for the selection and lay the bottom out round it.
func _refresh_bar() -> void:
	if cmd_bar == null or map_key == null or hint == null:
		return
	var t0 := ZProf.begin()
	if ps.is_empty() or not _bar_on():
		cmd_bar.shown = false
		cmd_bar.visible = false
		_bar_sig = []
	else:
		# A tap often asks twice in one frame (show_side, then _refresh_map): the bar is built once per frame for
		# the same selection, state and plan (a rebuild is the costly part of a tap: new controls, text, icons).
		var sig := [Engine.get_process_frames(), sel_army, sel_fleet, sel_region, merge_tap, side.visible, orders.size(),
			_vp(), str(panels._split_sel.get(sel_army, [])), str(sel_more_armies) + str(sel_more_fleets), set_detail, add_mode]
		if sig != _bar_sig or not is_same(_bar_ps, ps) or not is_same(_bar_st, st):
			cmd_bar.refresh()
			_bar_sig = sig
			_bar_ps = ps
			_bar_st = st
	_update_deselect()   # (show_side returns early while the bar shows the selection: the button follows here)
	_update_capsule()
	_layout_bottom()
	ZProf.add("h_bar", t0)


## The bar is full width at the bottom: the hint line, the map key's buttons,
## the End turn row and the side panel's foot rise above it.
func _bar_lift() -> float:
	return cmd_bar.height() + 4.0 if cmd_bar.shown else 0.0   # the bottom corners rise above the bar


func _layout_bottom() -> void:
	var lift := _bar_lift()
	hint.offset_bottom = -12.0 - lift
	# narrow screens: the hint wraps in the room between the map key's buttons and the End turn row
	var room := _vp().x - hint.offset_left - bottom_bar.get_combined_minimum_size().x - 16.0 - 30.0   # (30: the fit button)
	hint.offset_right = hint.offset_left + clampf(room, 120.0, 412.0)
	bottom_bar.offset_bottom = -8.0 - lift
	side.offset_bottom = -62.0 - lift
	map_key.set_lift(lift)
	_place_key()
	_place_toast()
	# the bar covers the map's foot: the pan limits and the fit zoom follow it
	if overlay != null and map_view != null:
		_clamp_view()
		map_view.queue_redraw()
		overlay.queue_redraw()


## Open the full panel for the selection (the old card), optionally scrolled
## to the section whose heading starts with `focus`.
func open_details(focus: String = "") -> void:
	_force_side = true
	if sel_army >= 0 and not CState.army(ps, sel_army).is_empty():
		show_side(func(box): panels.army_panel(box, sel_army))
	elif sel_fleet >= 0 and not CFleet.fleet(ps, sel_fleet).is_empty():
		show_side(func(box): panels.fleet_panel(box, sel_fleet))
	elif sel_region >= 0:
		show_side(func(box): panels.region_panel(box, sel_region))
	_force_side = false
	if focus != "":
		_scroll_side_to.call_deferred(focus)


func _scroll_side_to(focus: String) -> void:
	await get_tree().process_frame
	for l in side_box.find_children("*", "Label", true, false):
		if (l as Label).text.begins_with(focus):
			side_scroll.ensure_control_visible(l)
			return


## Hide the full panel, keep the selection (its Close button).
func close_details() -> void:
	if _bar_on() and cmd_bar.shown and not details_on_select:
		side.visible = false
		_update_deselect()
		_refresh_bar()
	else:
		close_side()


func close_side() -> void:
	side.visible = false
	sel_army = -1
	sel_fleet = -1
	_clear_more()
	merge_tap = -1
	sel_region = -1
	_refresh_map()
	_update_deselect()
	_refresh_bar()


## Deselect button: clears the selected army (ours or an enemy's), region
## or city, a previewed merge or drag, and closes the panel. Never an order.
func deselect_all() -> void:
	if merge_tap >= 0 and _toast != null:
		_toast.queue_free()  # the merge preview's toast
		_toast = null
	_drag_army = -1
	_drag_cell = -1
	_drag_tgt = -1
	overlay.set_drop(-1)
	close_side()
	_update_hint()
	_t("campaign_input", {"what": "deselect"})


## Shown only while something is selected, left of Undo (or of End turn).
func _update_deselect() -> void:
	if deselect_button == null:
		return
	deselect_button.visible = side.visible or sel_army >= 0 or sel_region >= 0 or merge_tap >= 0 or sel_fleet >= 0


## Unit book page as a recruitment card: the UnitEntry view with a Recruit
## button.
## Veterancy (2026-11-06): u, the campaign unit entry (army id, its index k), adds the unit's stars and record
## (Traits.vet_text) above the book page and, for a unit of ours at one of our settlements, its Retrain line: the
## tier-2 row, the cost or why not, and a Retrain button (CRules.retrain_info).
func open_unit_page(ty: int, recruit_cb: Callable, recruit_text: String, fac: int = -1, ak: int = -1,
		u: Dictionary = {}, army: int = -1, k: int = -1) -> void:
	var entry := UnitEntry.new()
	entry.custom_minimum_size = Vector2(0, minf(_vp().y * 0.62, 520))
	entry.set_unit_type(ty, CData.faction_color(f), fac, ak)
	var btns: Array = [["Close", Callable()]]
	if recruit_cb.is_valid():
		btns.push_front([recruit_text, func():
			recruit_cb.call()
			close_dialog()])
	var content: Control = entry
	if not u.is_empty() and not ps.is_empty() and CRules.vet_on(ps):
		var box := Kit.vbox(6)
		box.name = "vet_box"
		var lv := Traits.vet_of(u)
		var hb := Kit.hbox(6)
		if lv > 0:
			var stars := VetStars.new()
			stars.n = lv
			hb.add_child(stars)
		var vl := Kit.label(Traits.vet_text(u), Kit.FONT_SMALL, Kit.COL_BONE, true)
		vl.name = "vet_text"
		vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(vl)
		box.add_child(hb)
		if fac == f and f >= 0 and army >= 0 and k >= 0:
			var info := CRules.retrain_info(ps, f, army, k)
			if info.has("t"):
				var nm2 := CData.unit_name(str(info["t"]), f)
				var why := str(info.get("why", ""))
				var line := "Retrain as %s: %s" % [nm2, ("%d gold, a turn at %s; keeps its men and its stars" % [int(info["cost"]),
					CData.REGIONS[int(info["r"])]["city"]]) if why == "" else (why + (" (%d gold)" % int(info["cost"]) if info.has("cost") else ""))]
				var rl := Kit.label(line, Kit.FONT_SMALL, Kit.COL_GOOD if why == "" else Kit.COL_DIM, true)
				rl.name = "retrain_line"
				box.add_child(rl)
				if why == "":
					var aid := army
					var kk := k
					btns.push_front(["Retrain", func():
						if add_order({"t": "retrain", "army": aid, "unit": kk}) == "":
							close_dialog()])
		box.add_child(entry)
		content = box
	show_dialog(CData.unit_name(UT.key_of(ty), fac), content, btns, 900)


## The unit page's stars (veterancy): n brass stars on their plate.
class VetStars extends Control:
	const KitV := preload("res://game/campaign/ui_kit.gd")
	var n := 0

	func _init() -> void:
		custom_minimum_size = Vector2(48, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		KitV.draw_vet_badge(self, size * 0.5, n, 6.0)


## A selection whose army / fleet no longer exists (destroyed, merged away or taken in a battle) is dropped, so
## the hint, the bar and the Deselect button never follow a stale id.
func _prune_selection() -> void:
	if ps.is_empty():
		return
	if sel_army >= 0 and CState.army(ps, sel_army).is_empty():
		sel_army = -1
		merge_tap = -1
	if sel_fleet >= 0 and (not CFleet.on(ps) or CFleet.fleet(ps, sel_fleet).is_empty()):
		sel_fleet = -1
	if not sel_more_armies.is_empty() or not sel_more_fleets.is_empty():
		# (multi-select: what is gone drops out of the set; a gone focus passes to the next)
		var arm: Array = []
		for id in sel_more_armies:
			if not CState.army(ps, int(id)).is_empty():
				arm.append(int(id))
		var fls: Array = []
		for id in sel_more_fleets:
			if CFleet.on(ps) and not CFleet.fleet(ps, int(id)).is_empty():
				fls.append(int(id))
		sel_more_armies = arm
		sel_more_fleets = fls
		if sel_army < 0 and sel_fleet < 0:
			if not sel_more_armies.is_empty():
				sel_army = int(sel_more_armies.pop_front())
			elif not sel_more_fleets.is_empty():
				sel_fleet = int(sel_more_fleets.pop_front())
		if set_size() <= 1:
			set_detail = false
			add_mode = false


func _refresh() -> void:
	_prune_selection()
	_refresh_top()
	story.refresh()
	_refresh_map()
	_update_hint()
	if side.visible:
		if sel_army >= 0 and not CState.army(ps, sel_army).is_empty():
			show_side(func(box): panels.army_panel(box, sel_army))
		elif sel_fleet >= 0 and not CFleet.fleet(ps, sel_fleet).is_empty():
			show_side(func(box): panels.fleet_panel(box, sel_fleet))
		elif sel_region >= 0:
			show_side(func(box): panels.region_panel(box, sel_region))
		else:
			side.visible = false
			_update_deselect()
	panels.refresh_popup()
	tutorial.refresh()
	tip_scan()


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
	if cmd_bar != null and cmd_bar.shown:
		bottom -= cmd_bar.height() + 4.0
	if hint.text != "" and hint.visible:
		bottom = minf(bottom, hint.get_global_rect().position.y)
	map_key.place(TOP_H + 6.0, bottom - 6.0, vp.x)


func _refresh_top() -> void:
	if st.is_empty():
		return
	var fs := f if f >= 0 else (int(st["humans"][0]) if not (st["humans"] as Array).is_empty() else 0)
	var inc := CRules.income(ps, fs)
	var up := CRules.upkeep(ps, fs)
	# Date with the season as its icon ("280 BC, summer" in the tooltip and
	# the realm dialog), treasury, income a turn.
	var lc := CData.faction_color(fs).lightened(0.45)
	var turn := int(st["turn"])
	top_label.text = " " + CData.faction_name(fs)
	var pk := str(st.get("pack", CData.pack))
	if top_emblem != null and (top_emblem as Object).get("pack") != pk:
		top_emblem.set("pack", pk)
		top_emblem.queue_redraw()
	# The display face for the faction name and the emblem only where the bar has room (not on a phone).
	var roomy := _vp().x >= 820.0
	top_emblem.visible = roomy
	if int(roomy) != _top_title:
		_top_title = int(roomy)
		if roomy and Kit.title_font() != null:
			top_label.add_theme_font_override("font", Kit.title_font())
			top_label.add_theme_font_size_override("font_size", 18)
		else:
			top_label.remove_theme_font_override("font")
			top_label.add_theme_font_size_override("font_size", Kit.FONT)
	top_date.text = CData.date_text(turn).get_slice(",", 0)
	Kit.label_icon(top_date, "summer" if turn % 2 == 0 else "winter")
	top_money.text = Kit.money(int(ps["factions"][fs]["treasury"]))
	top_income.text = "%+d" % (int(inc["total"]) - up)
	Kit.label_icon(top_income, "income", Kit.COL_GOOD if int(inc["total"]) >= up else Kit.COL_BAD)
	for l: Label in [top_label, top_date, top_money, top_income]:
		l.add_theme_color_override("font_color", lc)
	top_box.get_node("top_info").tooltip_text = "%s, %s. Treasury %s, %+d a turn." % [CData.faction_name(fs), CData.date_text(turn),
		top_money.text, int(inc["total"]) - up]
	var nb := CTurn.pending_for(st).size()
	battles_button.text = "Battles (%d)" % nb if nb > 0 else "Battles"
	battles_button.modulate = Color(1, 0.6, 0.5) if nb > 0 else Color(1, 1, 1)
	end_button.disabled = nb > 0 or f < 0 or str(st["phase"]) == "over"
	undo_button.visible = _g() and f >= 0 and not _undo.is_empty()
	_update_deselect()
	if onl != null:
		var eb := onl.end_button_state()
		end_button.text = str(eb[0])
		end_button.disabled = bool(eb[1]) or nb > 0
	tutorial.gate_end_button()


## One clause for the idle hint: what the faded markers in the fog are.
func _fog_hint() -> String:
	return " Faded markers: where an enemy was last seen." if FogView.on else ""


## Amphibious army selected: it may paddle along the coast.
func _paddle_hint() -> String:
	var a := CState.army(ps, sel_army)
	if not a.is_empty() and CRules.amphibious(ps, a):
		return " This army may paddle along the coast (the shaded water): canoes cannot be attacked by land armies, but an enemy fleet sinks them."
	return ""


## The hint's plate hugs its text (the wrapped width and height), refitted when the text or the hint's width changes.
func _fit_hint_plate() -> void:
	if _hint_plate == null:
		return
	var key := "%s|%d|%s" % [hint.text, int(hint.size.x), hint.visible]
	if key == _hint_key:
		return
	_hint_key = key
	var on := hint.text != "" and hint.visible
	_hint_plate.visible = on
	if not on:
		return
	var fs := hint.get_theme_font_size("font_size")
	var tsz := hint.get_theme_font("font").get_multiline_string_size(hint.text, HORIZONTAL_ALIGNMENT_LEFT, maxf(hint.size.x, 40.0), fs,
			-1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	var tw := minf(tsz.x, hint.size.x)
	var th := maxf(tsz.y, hint.size.y)
	_hint_plate.position = Vector2(-6.0, hint.size.y - th - 4.0)
	_hint_plate.size = Vector2(tw + 12.0, th + 8.0)


func _set_hint() -> String:
	var how := "Right-click" if last_mouse else "Tap"
	if add_mode:
		return "Adding: tap armies and fleets to add or remove them. Done, or a tap on the map, ends it."
	var t := "%s selected: %s a spot to send them all" % [set_words(), how]
	if not set_armies().is_empty() and not set_fleets().is_empty():
		t += ", a fleet to board, another army to merge."
	elif not set_armies().is_empty():
		t += ", an enemy to attack, another army to merge."
	else:
		t += " (shore: land the troops)."
	return t


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
	elif set_size() > 1 and _g():
		hint.text = _set_hint()
	elif sel_fleet >= 0 and _g() and last_mouse:
		hint.text = "Right-click the sea to sail there (shaded: this turn; " + CFleet.wind_words() + "), a lit beach to land the troops aboard, an enemy fleet to attack it, your own fleet to join it, an enemy lane (drawn bold) to raid it, an enemy harbour to blockade it (a left click only selects). Left-click empty sea to deselect. Board: select an army and tap one of your fleets; beside it the army boards now, else it marches to a lit cell and boards on arriving."
	elif sel_army >= 0 and _g() and last_mouse:
		hint.text = "Right-click a spot inside the shaded area to march there this turn, further on for later turns; right-click an enemy army to attack it, a city to besiege it, your other army to merge. Same spot again: cancel. Left-click empty ground to deselect." + _paddle_hint()
	elif _g() and last_mouse:
		hint.text = "Left-click an army to move it or recruit into it (at a city), a city for buildings or a new army. Right-click orders, a right drag pans." + _fog_hint()
	elif sel_fleet >= 0 and _g():
		hint.text = "Tap the sea to sail there (shaded: this turn; " + CFleet.wind_words() + "), a lit beach to land the troops aboard, an enemy fleet to attack it, your own fleet to join it, an enemy lane (drawn bold) to raid it, an empty fleet on an enemy harbour to blockade it. Board: select an army and tap one of your fleets; beside it the army boards now, else it marches to a lit cell and boards on arriving."
	elif sel_army >= 0 and _g():
		hint.text = "Tap (or drag the army to) a spot inside the shaded area to march there this turn, further on for later turns; tap an enemy army to attack it, a city to besiege it. Same spot again: cancel." + _paddle_hint()
	elif _g():
		hint.text = "Tap an army to move it or recruit into it (at a city), a city for buildings or a new army." + _fog_hint()
	elif sel_army >= 0 and CState.moves_on(ps):
		hint.text = "Tap a region to march there (bright: this turn, dim: later turns; red: enemy land). Tap it again to cancel."
	elif sel_army >= 0:
		hint.text = "Tap a highlighted region to move there (red: siege or attack; dark: not allowed, tap for why). Tap it again to cancel."
	else:
		hint.text = "Tap an army to move it, a region for buildings and recruits."


func _refresh_map() -> void:
	FogView.update(st, f)   # (the sight changes with the state or the planner only: not per tap)
	_refresh_bar()
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


## The faction whose land a planned march (CRules.plan_path's result) ends a turn in without a right to be there (a
## trespass, MapOverlay.trespass_owner: only an army standing there at the end of a turn pays), else -1.
func trespass_on_path(rt: Dictionary) -> int:
	var cells: Array = rt.get("path", [])
	var ts: Array = rt.get("t", [])
	for k in cells.size():
		var stops: bool = k == cells.size() - 1 or (ts.size() > k + 1 and int(ts[k + 1]) != int(ts[k]))
		if not stops:
			continue
		var o := MapOverlay.trespass_owner(ps, f, CGrid.region(int(cells[k])))
		if o >= 0:
			return o
	return -1


## The toast after a march is planned into land at peace: what a trespass costs, and the way round it.
func trespass_toast(army: int) -> void:
	var rt := route6(army)
	if rt.is_empty() or rt.has("why"):
		return
	var o := trespass_on_path(rt)
	if o < 0:
		return
	show_toast("Trespass: %d regard a turn per army; war at %d. %s's land: ask for passage in Diplomacy." % [
		CDip.REG_TRESPASS, CDip.WAR_LINE, CData.faction_name(o)], ["Diplomacy", func(): panels.show_diplomacy(o)])


## Version 6: army's planned or stored march: {cell, tgt, mode, stored,
## join (an army of ours it marches to merge into, -1), fleet (a fleet of ours
## it boards on arriving, -1)} ({} none).
func plan6(army: int) -> Dictionary:
	for m in moves:
		if int(m[0]) == army:
			var bf := -1
			for o in orders:
				if str(o["t"]) == "move" and int(o["army"]) == army:
					bf = int(o.get("fleet", -1))
			return {"cell": int(m[1]), "tgt": int(m[4]) if (m as Array).size() > 4 else -1, "mode": int(m[2]), "stored": false,
				"join": int(m[5]) if (m as Array).size() > 5 else -1, "fleet": bf}
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
		return {"cell": CState.cell(j), "tgt": -1, "mode": int(a.get("mode", CData.MODE_SIEGE)), "stored": true, "join": join, "fleet": -1}
	var tgt := int(a.get("tgt", -1))
	if tgt >= 0:
		var t := CState.army(ps, tgt)
		if t.is_empty():
			return {}
		return {"cell": CState.cell(t), "tgt": tgt, "mode": int(a.get("mode", CData.MODE_SIEGE)), "stored": true, "join": -1, "fleet": -1}
	if int(a.get("dest_x", -1)) >= 0:
		return {"cell": CGrid.at(int(a["dest_x"]), int(a["dest_y"])), "tgt": -1, "mode": int(a.get("mode", CData.MODE_SIEGE)), "stored": true,
			"join": -1, "fleet": int(a.get("dest_fleet", -1))}
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
	if not same and _muster_guard(army, func(): set_move6(army, c, tgt)):
		return
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
		save_plan()
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
	save_plan()
	_t("campaign_input", {"what": "move", "tgt": tgt})
	trespass_toast(army)


## Version 6: army marches to our army `target` and merges into it on
## arrival (a move with "join"; it keeps following it over the turns). Next
## to it already: a merge order now (the plan preview shows the merged
## army). The same target again cancels the march.
func set_join(army: int, target: int, quiet: bool = false) -> bool:
	var a := CState.army(ps, army)
	var t := CState.army(ps, target)
	if a.is_empty() or t.is_empty():
		return false
	merge_tap = -1
	if CGrid.cheb(CState.cell(a), CState.cell(t)) <= 1 and CRules.merge_check(ps, f, army, target) == "":
		if add_order({"t": "merge", "army": army, "into": target}) == "":
			_t("campaign_input", {"what": "merge"})
			if not quiet:
				select_army(target)
			return true
		return false
	var cur := plan6(army)
	var same := not cur.is_empty() and int(cur.get("join", -1)) == target
	if not same and _muster_guard(army, func(): set_join(army, target)):
		return false
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
		save_plan()
		_t("campaign_input", {"what": "move_cancel"})
		return false
	var mo := {"t": "move", "army": army, "join": target, "mode": CData.MODE_SIEGE, "persist": 1}
	var pv := CTurn.preview(st, f, orders + [mo])
	for e in pv["errors"]:
		if int(e[0]) == orders.size():
			orders = before
			_replan()
			explain_refusal(army, maxi(CGrid.region(CState.cell(t)), 0), str(e[1]))
			return false
	orders.append(mo)
	_undo.append(before)
	_replan()
	save_plan()
	_t("campaign_input", {"what": "move", "join": target})
	return true


## Version 6: army marches to the boarding cell of our fleet `fid` nearest it and boards on arriving (a move with
## "fleet"; CFleet.board_order_check says if it may). The same fleet again cancels the march.
func set_board(army: int, fid: int) -> void:
	var a := CState.army(ps, army)
	var fl := CFleet.fleet(ps, fid)
	if a.is_empty() or fl.is_empty():
		return
	var why := CFleet.board_order_check(ps, f, a, fid)
	if why != "":
		_flash("Cannot board: %s." % why)
		return
	var cur := plan6(army)
	var same := not cur.is_empty() and int(cur.get("fleet", -1)) == fid
	if not same and _muster_guard(army, func(): set_board(army, fid)):
		return
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
		save_plan()
		_t("campaign_input", {"what": "move_cancel"})
		return
	# The boarding cell nearest the army by the march preview: fewest turns, then Chebyshev, then cell index.
	var best := -1
	var best_t := 1 << 30
	var best_d := 1 << 30
	var ac := CState.cell(a)
	for c in CFleet.boarding_cells(ps, fl):
		var pr := CRules.plan_path(ps, a, int(c), -1, CData.MODE_SIEGE, {}, 12, -1)
		if pr.has("why") or (pr["t"] as Array).is_empty() and int(c) != ac:
			continue
		var tn := int(pr["t"][-1]) + 1 if not (pr["t"] as Array).is_empty() else 0
		var d := CGrid.cheb(ac, int(c))
		if tn < best_t or (tn == best_t and d < best_d):
			best = int(c)
			best_t = tn
			best_d = d
	if best < 0:
		_flash("Cannot board: no way to a cell beside the fleet.")
		return
	var mo := {"t": "move", "army": army, "x": CGrid.cx(best), "y": CGrid.cy(best), "mode": CData.MODE_SIEGE, "persist": 1, "fleet": fid}
	var pv := CTurn.preview(st, f, orders + [mo])
	for e in pv["errors"]:
		if int(e[0]) == orders.size():
			orders = before
			_replan()
			explain_refusal(army, maxi(CGrid.region(best), 0), str(e[1]))
			return
	orders.append(mo)
	_undo.append(before)
	_replan()
	save_plan()
	_t("campaign_input", {"what": "move", "fleet": fid})
	show_toast("Marching to board the fleet: %d turn(s), boards on arriving." % maxi(best_t, 1))


## First tap on another of our armies with one selected: preview the merge
## (its path, the caption, a toast with Merge / Select it); a second tap on
## it plans the merge.
func _merge_tap_at(id: int) -> void:
	if _free_set_armies().size() > 1:
		_merge_set_at(id)
		return
	if merge_tap == id:
		if _toast != null:   # the second tap (a double tap) is the answer: the Merge / Select popup goes away
			_toast.queue_free()
			_toast = null
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
	var why := merge_why(sa, id)
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
	var t_m6 := ZProf.begin()
	# (what the overlay showed, to redraw only the parts a selection changed: see the end)
	var was_sel := [overlay.selected_army, overlay.selected_fleet, overlay.merge_tap]
	var was_extra := str(overlay.extra_armies) + "|" + str(overlay.extra_fleets)
	var was_fleets: Array = overlay.fleet_paths
	var was_sea := overlay.sea_reach_rt
	# (a state changed in place, as the input tests do, is caught by a few of its counts)
	var sig := [int(st.get("turn", -1)), str(st.get("phase", "")), (ps.get("armies", []) as Array).size(),
		(ps.get("battles", []) as Array).size(), (ps.get("sieges", []) as Array).size()]
	var fresh := not (is_same(_drawn_ps, ps) and is_same(_drawn_st, st) and _drawn_f == f) or sig != _drawn_sig
	# A tap that selects an army shows the bar and the halo in its own frame; the army's reach, zones, links and
	# merge glyphs (the rules' reach6 and the outlines: the heavy part) follow in the next frame (_tick).
	var later := _defer_sel and not fresh
	_defer_sel = false
	map_view.grid = true
	overlay.grid = true
	overlay.player = f
	overlay.selected_army = sel_army
	overlay.extra_armies = sel_more_armies.duplicate()
	overlay.extra_fleets = sel_more_fleets.duplicate()
	overlay.moves = []
	overlay.paths = []
	overlay.attack_moves = []
	overlay.siege_moves = []
	map_view.targets = []
	map_view.attack_targets = []
	map_view.blocked_targets = []
	map_view.target_turns = {}
	map_view.set_selected_region(sel_region)
	var paths: Array = []
	var t_rt := ZProf.begin()
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
				if not FogView.army_seen(st, a):
					continue
				if int(a.get("dest_x", -1)) >= 0 or int(a.get("tgt", -1)) >= 0:
					var c := CGrid.at(int(a["dest_x"]), int(a["dest_y"])) if int(a.get("dest_x", -1)) >= 0 else -1
					var rt2 := CRules.plan_path(ps, a, c, int(a.get("tgt", -1)), int(a["mode"]))
					if not rt2.has("why"):
						paths.append(path_entry(a, rt2))
	ZProf.add("m6_routes", t_rt)
	var zones: Array = []
	var links: Array = []
	var marks: Array = []
	var sa := CState.army(ps, sel_army) if sel_army >= 0 else {}
	if later and not sa.is_empty():
		map_view.set_reach(PackedInt32Array())
		_map6_next = true
		_map6_frame = Engine.get_process_frames()
	elif not sa.is_empty():
		var rt6 := PackedInt32Array()
		var rt_union := PackedInt32Array()
		if int(sa["f"]) == f:
			var t_r6 := ZProf.begin()
			rt6 = CRules.reach6(ps, sa, 1)
			var both := _set_reach(rt6)   # (a set of armies: where all can get is solid, where any can faint)
			if not both.is_empty():
				rt6 = both[0]
				rt_union = both[1]
			ZProf.add("m6_reach6", t_r6)
			if int(sa["busy"]) == 0:
				if _marks_for != sel_army:
					var t_mk := ZProf.begin()
					_marks = _merge_marks(sa, rt6)
					_marks_for = sel_army
					ZProf.add("m6_marks", t_mk)
				marks = _marks
				var mt := CState.army(ps, merge_tap) if merge_tap >= 0 else {}
				if not mt.is_empty():
					var pr := CRules.plan_path(ps, sa, CState.cell(mt), -1, CData.MODE_SIEGE, {}, 12, merge_tap)
					if not pr.has("why"):
						var pe := path_entry(sa, pr)
						pe["preview"] = 1
						paths.append(pe)
		var t_sr := ZProf.begin()
		map_view.set_reach(rt6, rt_union)
		ZProf.add("m6_set_reach", t_sr)
		var t_zl := ZProf.begin()
		var px := float(CGrid.cell_px())
		for e in CRules.zone_armies(ps, int(sa["f"])):
			if not FogView.army_seen(st, e):
				continue   # (fog: no zone round an army out of sight)
			var zr := CRules.zone_r(ps, e)
			zones.append([MapOverlay.cell_point(CState.cell(e)), (sqrt(float(zr * zr + zr)) + 0.5) * px])
		var lk := CRules.links_of(ps, sa, rt6)
		ZProf.add("m6_zones_links", t_zl)
		for id in lk["support"]:
			links.append([sel_army, int(id), 0])
		for id in lk["attack"]:
			var le := CState.army(ps, int(id))
			if not le.is_empty() and not FogView.army_seen(st, le):
				continue   # (fog: no attack line to an army out of sight)
			links.append([sel_army, int(id), 1])
	else:
		map_view.set_reach(PackedInt32Array())
	overlay.selected_fleet = sel_fleet
	var raid_ids := raid_lanes_of(CFleet.fleet(ps, sel_fleet)) if sel_fleet >= 0 and CFleet.on(ps) else []
	var raid_changed := raid_ids != overlay.raid_lanes
	overlay.raid_lanes = raid_ids
	overlay.fleet_paths = []
	var t_fl := ZProf.begin()
	if CFleet.on(ps) and f >= 0:
		for fl in CFleet.fleets_of(ps, f):
			var vy := planned_voyage(int(fl["id"]))
			if int(vy[0]) < 0 and int(vy[1]) < 0:
				continue
			var fp := CFleet.plan(ps, f, int(fl["id"]), int(vy[0]), int(vy[1]))
			if fp.has("why"):
				continue
			overlay.fleet_paths.append({"fleet": int(fl["id"]), "path": fp["path"], "t": fp["t"], "land": int(fp["land"]),
				"attack": 1 if int(fp["tgt"]) >= 0 else 0, "join": 1 if int(fp.get("join", -1)) >= 0 else 0})
		var sfl := CFleet.fleet(ps, sel_fleet) if sel_fleet >= 0 else {}
		var sea_rt := CFleet.reach(ps, sfl, 0) if not sfl.is_empty() and int(sfl["f"]) == f else PackedInt32Array()
		for oid in set_fleets().slice(1):
			# (a set of fleets: the sea where every one of them can sail this turn)
			var orr := CFleet.reach(ps, CFleet.fleet(ps, int(oid)), 0)
			if orr.size() == sea_rt.size():
				for c in sea_rt.size():
					if orr[c] != 0 and sea_rt[c] == 0:
						sea_rt[c] = -1
		overlay.set_sea_reach(sea_rt)
		if not sfl.is_empty():
			var px2 := float(CGrid.cell_px())
			for e in CFleet.fleets(ps):
				if CState.at_war(ps, int(sfl["f"]), int(e["f"])) and FogView.fleet_seen(st, e):
					zones.append([MapOverlay.cell_point(CFleet.cell(e)), (sqrt(float(CFleet.FLEET_ZONE * CFleet.FLEET_ZONE + CFleet.FLEET_ZONE)) + 0.5) * px2])
	var lfl := CFleet.fleet(ps, sel_fleet) if CFleet.on(ps) and sel_fleet >= 0 else {}
	var land_changed := overlay.set_landing(ps, f, lfl, CState.army(ps, sel_army) if sel_army >= 0 else {})
	ZProf.add("m6_fleets", t_fl)
	# A new state (an order, a resolved turn, another planner) draws the overlay again, and the map when an owner
	# changed; a selection on the same state only the overlay parts it shows (paths with zones / links, fleets,
	# armies with the merge glyphs) and the map's reach / selected-region nodes (map_view.set_reach /
	# set_selected_region): the map's territories and edges are not drawn again for a tap.
	var p_paths := fresh or paths != overlay.paths6 or zones != overlay.zones or links != overlay.links
	var p_armies := fresh or marks != overlay.merge_marks or int(was_sel[2]) != merge_tap or int(was_sel[0]) != sel_army or was_extra != str(overlay.extra_armies) + "|" + str(overlay.extra_fleets)   # (the halo is its own node; the selected standard lifts and has a gold rim, so the armies redraw)
	var p_fleets := fresh or int(was_sel[1]) != sel_fleet or was_extra != str(overlay.extra_armies) + "|" + str(overlay.extra_fleets) or overlay.fleet_paths != was_fleets or overlay.sea_reach_rt != was_sea or land_changed or raid_changed
	overlay.paths6 = paths
	overlay.zones = zones
	overlay.links = links
	overlay.merge_marks = marks
	overlay.merge_tap = merge_tap
	if fresh:
		_drawn_ps = ps
		_drawn_st = st
		_drawn_f = f
		_drawn_sig = sig
		map_view.refresh_state()
		overlay.queue_redraw()
	else:
		overlay.redraw_parts(p_paths, p_fleets, p_armies)
	_note_positions()
	ZProf.add("h_map6", t_m6)


## A set of armies' reach: [where every free army of the set can get this turn (0; a cell reached later by all keeps its
## latest turn), where any can get this turn (0)], per cell as CRules.reach6; [] for a set of one. `first` is the focus's.
func _set_reach(first: PackedInt32Array) -> Array:
	var ids := _free_set_armies()
	if ids.size() < 2 or first.is_empty():
		return []
	var inter := first.duplicate()
	var uni := first.duplicate()
	for id in ids.slice(0, 12):
		if int(id) == sel_army:
			continue
		var r := CRules.reach6(ps, CState.army(ps, int(id)), 1)
		if r.size() != inter.size():
			continue
		for c in inter.size():
			var v := r[c]
			if inter[c] < 0 or v < 0:
				inter[c] = -1
			else:
				inter[c] = maxi(inter[c], v)
			if uni[c] != 0 and v == 0:
				uni[c] = 0
			elif uni[c] != 0:
				uni[c] = -1
	return [inter, uni]


## Version 6: "" if our army sa may merge into our army id now, the checks a
## tap on it runs (_merge_tap_at): next to it, CRules.merge_check; further,
## the march that merges on arrival (CRules._can_move6 with join: units,
## stance, the path past enemy zones of control); else the reason.
func merge_why(sa: Dictionary, id: int) -> String:
	var t := CState.army(ps, id)
	if sa.is_empty() or t.is_empty():
		return "no such army"
	var why := CRules.join_check(ps, sa, id)
	if why == "" and CGrid.cheb(CState.cell(sa), CState.cell(t)) <= 1:
		why = CRules.merge_check(ps, f, int(sa["id"]), id)
	elif why == "":
		why = CRules._can_move6(ps, sa, CState.cell(t), -1, CData.MODE_SIEGE, true, id)
	return why


## Version 6: the armies the selected one (sa, its reach rt6) can merge
## into or give units to: [[id, 0 merge (an army of ours next to it or next
## to a cell it reaches this turn, and merge_why passes: a tap merges),
## 1 gift (an allied player's army next to it), 2 too big to merge]]. An
## army whose merge a tap would refuse otherwise (an enemy zone of control
## in the way, fortified, already moved) gets no mark. Computed once per
## selection and plan (_marks, reset by _replan).
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
				var why := merge_why(sa, id)
				if why == "":
					out.append([id, 0])
				elif why == "too many units to merge" or why.begins_with("more than"):
					out.append([id, 2])
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
	if int(a["f"]) == f and int(plan6(int(a["id"])).get("fleet", -1)) >= 0:
		out["board"] = 1
	if int(a["f"]) == f and trespass_on_path(rt) >= 0:
		out["trespass"] = 1   # (the end marker is drawn in the warning colour)
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
			if FogView.cell_seen(MapOverlay.cell_of_point(at)):
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
		if FogView.on:
			# (fog: only what the planner's team can see replays: armies in sight, or a gone army's steps in sight)
			var ra := CState.army(st, id)
			if not (FogView.army_seen(st, ra) if not ra.is_empty() else FogView.cell_seen(CGrid.at(int(stp[1]), int(stp[2])))):
				continue
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
	if id != sel_army:
		_clear_more()
	sel_army = id
	sel_fleet = -1
	merge_tap = -1
	var a := CState.army(ps, id)
	sel_region = -1
	if not a.is_empty():
		show_side(func(box): panels.army_panel(box, id))
		if int(a["f"]) == f:
			Tips.show("army_selected")
			if _can_raid_here(a):
				Tips.show("raid")
	_defer_sel = true
	_refresh_map()
	_defer_sel = false
	_update_hint()


func select_region(r: int) -> void:
	sel_region = r
	sel_army = -1
	sel_fleet = -1
	_clear_more()
	show_side(func(box): panels.region_panel(box, r))
	if f >= 0 and CState.owner(ps, r) == f:
		Tips.show("town_opened")
	if f >= 0:
		for a in CState.armies_of(ps, f):
			if int(a["r"]) == r and _can_raid_here(a):
				Tips.show("raid")
				break
	tutorial.note("region", r)
	_refresh_map()
	_update_hint()


## Army a of ours stands in a region of a nation we are at war with (the region bar's Raid action is offered).
func _can_raid_here(a: Dictionary) -> bool:
	var r := int(a["r"])
	var o := CState.owner(ps, r)
	return int(a["busy"]) == 0 and o >= 0 and o != f and CState.at_war(ps, f, o) and CState.battle_at(ps, r).is_empty()


func select_fleet(id: int) -> void:
	if id != dock_mode:
		dock_mode = -1
	if id != sel_fleet:
		_clear_more()
	sel_fleet = id
	sel_army = -1
	sel_region = -1
	merge_tap = -1
	if not CFleet.fleet(ps, id).is_empty():
		show_side(func(box): panels.fleet_panel(box, id))
		if f >= 0 and not raid_lanes_of(CFleet.fleet(ps, id)).is_empty():
			Tips.show("lane_raid")
	_refresh_map()
	_update_hint()


## The planned (or stored) voyage of fleet id: [dest cell, tgt] ([-1, -1] none).
func planned_voyage(id: int) -> Array:
	for o in orders:
		if str(o.get("t", "")) == "fmove" and int(o.get("fleet", -1)) == id:
			return [CGrid.at(int(o.get("x", -1)), int(o.get("y", -1))), int(o.get("tgt", -1))]
		if _is_station(o) and int(o.get("fleet", -1)) == id:
			return [int(CSea.station_plan(ps, f, o).get("dest", -1)), -1]   # (lanes) the voyage to the station
	var fl := CFleet.fleet(ps, id)
	if not fl.is_empty() and fl.has("dest_x"):
		return CFleet.voyage(fl)
	return [-1, -1]


## Order fleet id to sail to cell c (sea, or a coast to land on) or after
## enemy fleet tgt; the same destination again cancels the voyage.
func set_fmove(id: int, c: int, tgt: int = -1) -> void:
	var cur := planned_voyage(id)
	var had := false
	var keep: Array = []
	for o in orders:
		if (str(o.get("t", "")) == "fmove" or _is_station(o)) and int(o.get("fleet", -1)) == id:
			had = true
			continue
		keep.append(o)
	if (tgt >= 0 and int(cur[1]) == tgt) or (tgt < 0 and c >= 0 and int(cur[0]) == c):
		if had:
			set_orders(keep)
		else:
			add_order({"t": "fcancel", "fleet": id})
		return
	var p := CFleet.plan(ps, f, id, c, tgt)
	if p.has("why"):
		AudioFx.play("refused", 0.9, 0.0, "ui")
		_flash(str(p["why"]).substr(0, 1).to_upper() + str(p["why"]).substr(1) + ".")
		return
	var o := {"t": "fmove", "fleet": id, "x": CGrid.cx(c), "y": CGrid.cy(c), "persist": 1}
	if int(p["tgt"]) >= 0 or int(p.get("join", -1)) >= 0:
		var tid: int = int(p["tgt"]) if int(p["tgt"]) >= 0 else int(p["join"])
		var tf := CFleet.fleet(ps, tid)
		o["tgt"] = tid
		o["x"] = int(tf["x"])
		o["y"] = int(tf["y"])
	if had:
		set_orders(keep + [o])
	else:
		add_order(o)
	_t("campaign_input", {"what": "fleet_move"})


func _is_station(o: Dictionary) -> bool:
	var t := str(o.get("t", ""))
	return t == "fraid" or t == "fblockade" or t == "fdock"


## (Sea lanes) Order fleet id to raid lane `lane` or blockade region `r`'s port (-1 the other): it sails to the
## station and holds it. The same target again cancels; another target replaces the fleet's voyage.
func set_station(id: int, lane: int, r: int, dock: bool = false) -> void:
	var o := {"t": "fraid", "fleet": id, "lane": lane} if lane >= 0 else {"t": "fblockade", "fleet": id, "r": r}
	if dock:
		o = {"t": "fdock", "fleet": id, "r": r}   # (Docking) sail to the port's dock and dock there
	var keep: Array = []
	var same := false
	var had := false
	for q in orders:
		if (str(q.get("t", "")) == "fmove" or _is_station(q)) and int(q.get("fleet", -1)) == id:
			had = true
			if str(q.get("t", "")) == str(o["t"]) and int(q.get("lane", -2)) == int(o.get("lane", -2)) and int(q.get("r", -2)) == int(o.get("r", -2)):
				same = true
			continue
		keep.append(q)
	if same:
		set_orders(keep)
		return
	var why := ""
	if had:
		why = set_orders(keep + [o])
	else:
		why = add_order(o)
	if why == "":
		_t("campaign_input", {"what": "fleet_dock" if dock else "fleet_raid" if lane >= 0 else "fleet_blockade"})


## (Docking) The region fleet id is ordered to dock in (an fdock order of the plan), -1 none.
func dock_order(id: int) -> int:
	for o in orders:
		if str(o.get("t", "")) == "fdock" and int(o.get("fleet", -1)) == id:
			return int(o.get("r", -1))
	return -1


## (Docking) Fleet id is ordered to cast off (fundock in the plan).
func cast_off_planned(id: int) -> bool:
	for o in orders:
		if str(o.get("t", "")) == "fundock" and int(o.get("fleet", -1)) == id:
			return true
	return false


## (Docking) Cast off fleet id, or take the order back when it is planned already.
func toggle_cast_off(id: int) -> void:
	if cast_off_planned(id):
		var keep: Array = []
		for o in orders:
			if not (str(o.get("t", "")) == "fundock" and int(o.get("fleet", -1)) == id):
				keep.append(o)
		set_orders(keep)
		return
	if add_order({"t": "fundock", "fleet": id}) == "":
		_t("campaign_input", {"what": "fleet_cast_off"})


## (Docking) The Dock button: at one of our docks the fleet docks at once (an fdock order), elsewhere the next tap on one
## of our port cities sails the fleet in.
func start_dock(id: int) -> void:
	var fl := CFleet.fleet(ps, id)
	if fl.is_empty():
		return
	var r := CFleet.dock_region(ps, f, CFleet.cell(fl))
	if r >= 0:
		dock_mode = -1
		set_station(id, -1, r, true)
		_after_station()
		return
	dock_mode = id
	show_toast("Tap one of your port cities to sail in and dock.")

## The lanes the fleet (ours) could raid now: CLanes ids at war with it.
func raid_lanes_of(fl: Dictionary) -> Array:
	var out: Array = []
	if fl.is_empty() or int(fl["f"]) != f or fl.has("flota") or fl.has("sto") or not CFleet.on(ps):
		return out
	for id in CLanes.total():
		if CLanes.hostile(ps, f, id):
			out.append(id)
	return out


## The richest lane worth raiding for fleet fl (value its enemies' ports pay, by the distance), -1 none.
func best_raid(fl: Dictionary) -> int:
	var best := -1
	var bv := -1
	for id in raid_lanes_of(fl):
		if int(id) >= CLanes.count():
			continue
		var ls := CLanes.lane_state(ps, int(id), {})
		var v := 0
		if int(ls["oa"]) >= 0 and CState.at_war(ps, f, int(ls["oa"])):
			v += int(ls["pa"])
		if int(ls["ob"]) >= 0 and CState.at_war(ps, f, int(ls["ob"])):
			v += int(ls["pb"])
		var stn := CLanes.raid_station(ps, f, fl, int(id))
		if v <= 0 or stn < 0:
			continue
		var sc := v * 100 / (1 + CGrid.octile(CFleet.cell(fl), stn) / maxi(CFleet.speed(fl) / 10, 1))
		if sc > bv:
			bv = sc
			best = int(id)
	return best


## The richest enemy port fleet fl could blockade (sea trade by the distance), -1 none.
func best_blockade(fl: Dictionary) -> int:
	var best := -1
	var bv := -1
	if fl.is_empty() or int(fl["f"]) != f or fl.has("flota") or fl.has("sto") or not CFleet.on(ps):
		return -1
	for r in CData.region_count():
		var o := CState.owner(ps, r)
		if CFleet.harbour(r) < 0 or o < 0 or not CState.at_war(ps, f, o):
			continue
		var stn := CSea.blockade_station(ps, f, fl, r)
		if stn < 0:
			continue
		var sc := maxi(CSea.sea_trade(ps, r), 1) * 100 / (1 + CGrid.octile(CFleet.cell(fl), stn) / maxi(CFleet.speed(fl) / 10, 1))
		if sc > bv:
			bv = sc
			best = r
	return best


## Our fleet id joins our fleet into: within a cell now, an immediate merge
## (and the merged-into fleet is selected); farther, a voyage to it that
## merges on arriving (and goes on from turn to turn).
func join_fleet(id: int, into: int, quiet: bool = false) -> void:
	var a := CFleet.fleet(ps, id)
	var b := CFleet.fleet(ps, into)
	if a.is_empty() or b.is_empty():
		return
	if CGrid.cheb(CFleet.cell(a), CFleet.cell(b)) <= 1:
		if add_order({"t": "fmerge", "fleet": id, "into": into}) != "":
			return   # (add_order flashed why)
		if not quiet:
			_flash("Joining")
			select_fleet(into)
		_t("campaign_input", {"what": "fleet_join"})
		return
	set_fmove(id, CFleet.cell(b), into)
	if not quiet and sel_fleet >= 0 and not CFleet.fleet(ps, sel_fleet).is_empty():
		show_side(func(box): panels.fleet_panel(box, sel_fleet))


## Our army id boards our fleet fid (beside it, room aboard).
func embark(id: int, fid: int) -> void:
	var why := CFleet.embark_check(ps, f, id, fid)
	if why != "":
		AudioFx.play("refused", 0.9, 0.0, "ui")
		_flash("Cannot board: %s." % why)
		return
	if add_order({"t": "embark", "army": id, "fleet": fid}) == "":
		select_fleet(fid)
		_t("campaign_input", {"what": "embark"})


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
	_battle_snap = BattleScreen.snapshot(st, b, f)
	if b.has("sea"):
		# (N3a) A sea battle auto-resolves by the fleets' formula at once.
		_battle_id = bid
		_t("campaign_battle", {"mode": "auto", "turn": int(st["turn"]), "region": int(b.get("r", -1)), "sea": 1})
		_apply_battle(bid, CBattle.formula(st, b))
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
	_auto_box = box
	show_dialog("Battle of %s" % CData.REGIONS[int(b["r"])]["city"], box, [])
	_resolver.finished.connect(_on_auto_done)


## (2026-11-05) The defender declines a contested landing (sea_screen.gd's
## Stand off): the pending sea battle is applied with the outcome mode
## CFleet.STAND_OFF (no battle; the troops land, the ships stay in port).
func stand_off(bid: int) -> void:
	var b := CState.battle(st, bid)
	if b.is_empty() or _resolver != null or not CFleet.can_stand_off(st, b):
		return
	if online != null and not await onl.claim(bid, "auto"):
		return
	b = CState.battle(st, bid)
	if b.is_empty() or not CFleet.can_stand_off(st, b):
		return
	_battle_snap = {}
	_battle_id = bid
	_t("campaign_battle", {"mode": "standoff", "turn": int(st["turn"]), "region": int(b.get("r", -1)), "sea": 1})
	_apply_battle(bid, {"mode": CFleet.STAND_OFF})


## (2026-11-05) The defender supports the shore at a contested landing (sea_screen.gd's Support the shore): the
## pending sea battle is applied with the outcome mode CFleet.SUPPORT (no sea battle; the troops land; the ships
## stay by the town for the land battle that follows).
func support_shore(bid: int) -> void:
	var b := CState.battle(st, bid)
	if b.is_empty() or _resolver != null or not CFleet.can_stand_off(st, b):
		return
	if online != null and not await onl.claim(bid, "auto"):
		return
	b = CState.battle(st, bid)
	if b.is_empty() or not CFleet.can_stand_off(st, b):
		return
	_battle_snap = {}
	_battle_id = bid
	_t("campaign_battle", {"mode": "support", "turn": int(st["turn"]), "region": int(b.get("r", -1)), "sea": 1})
	_apply_battle(bid, {"mode": CFleet.SUPPORT})


## (2026-11-05) Support the shore with fleet id where it lies (the fshore order), or take that back: an fshore of the
## plan is dropped; a fleet supporting already is told to stop ({"on": 0}).
func toggle_shore(id: int) -> void:
	var keep: Array = []
	var had := false
	for o in orders:
		if str(o.get("t", "")) == "fshore" and int(o.get("fleet", -1)) == id:
			had = true
			continue
		keep.append(o)
	if had:
		set_orders(keep)
		return
	var on := 0 if CFleet.supporting(st, CFleet.fleet(st, id)) >= 0 else 1
	if add_order({"t": "fshore", "fleet": id, "on": on}) == "":
		_t("campaign_input", {"what": "fleet_shore"})


func _process(delta: float) -> void:
	var t0 := ZProf.begin()
	_tick(delta)
	ZProf.add("screen_process", t0)


func _tick(delta: float) -> void:
	_save_tick()
	if _map6_next and Engine.get_process_frames() > _map6_frame:
		_map6_next = false
		if _g() and not ps.is_empty():
			_refresh_map6()   # (the selected army's reach, deferred from the tap's frame)
	map_view.pulse += delta
	overlay.pulse += delta
	if _resolver != null and _progress != null:
		_progress.value = _resolver.progress
	world.position = offset
	world.scale = Vector2(zoom, zoom)
	map_view.zoom = zoom
	map_view.update_lod(zoom)
	_fit_hint_plate()
	map_view.view_rect = Rect2(-offset / zoom, _vp() / zoom)
	overlay.zoom = zoom
	var xf := Transform2D(0.0, Vector2(zoom, zoom), 0.0, offset)
	table_frame.update_view(xf, _vp())
	if xf != overlay.xform:
		overlay.set_view(xf, map_view.heavy_pending())
		# line widths follow the zoom: the map's own drawing is redone when the zoom moved 3 %, not on every pan or frame
		# (while the zoom is moving only a 35 % change redraws; the rest waits until it settles)
		var dz := absf(zoom - _mv_zoom) / maxf(_mv_zoom, 0.01)
		_mv_settle = 0.12
		if dz > 0.35 or _mv_zoom < 0.0:
			_mv_zoom = zoom
			map_view.queue_redraw()
	if _mv_settle > 0.0:
		_mv_settle -= delta
		if _mv_settle <= 0.0 and absf(zoom - _mv_zoom) > _mv_zoom * 0.02:
			_mv_zoom = zoom
			map_view.queue_redraw()
	if sel_army >= 0 or not moves.is_empty() or not map_view.targets.is_empty():
		# the pulsing tints and the selected army's glow only: the rest of the map and the overlay are not redrawn every frame
		if not map_view.targets.is_empty() or not map_view.blocked_targets.is_empty() or map_view.selected_region >= 0:
			map_view.redraw_pulse()
		overlay.redraw_armies()
	if ps.has("fleets"):
		_wave_redraw += delta
		if _wave_redraw >= 0.07:  # ships bob on the waves (about 14 redraws a second)
			_wave_redraw = 0.0
			overlay.redraw_fleets()
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
	_long_press_tick()


func _on_auto_done(outcome: Dictionary) -> void:
	var b := CState.battle(st, _battle_id)
	_t("campaign_battle", {"mode": "auto", "turn": int(st["turn"]), "region": int(b.get("r", -1)),
		"ms": int(outcome.get("wall_ms", 0)), "scale": int(outcome.get("scale", 100)),
		"ticks": int(outcome.get("ticks", 0)), "winner": int(outcome["winner"])})
	_resolver.queue_free()
	_resolver = null
	_progress = null
	if _roll_die(_battle_id, outcome):
		return
	_apply_battle(_battle_id, outcome)


## The table's die (tabletop pass 5, game/campaign/die_roll.gd; view only): it rolls in the auto-resolve dialog and settles on the
## face the rules gave this player (laurel, broken shield, crossed swords), then the result is applied and shown as before.
## False (nothing rolled) with the setting off, in tests and with a command-line aid, or when the dialog is gone.
func _roll_die(bid: int, outcome: Dictionary) -> bool:
	if not TableMotion.allowed() or _auto_box == null or not is_instance_valid(_auto_box) or not _auto_box.is_inside_tree():
		_auto_box = null
		return false
	var result := "draw"
	var bt := CState.battle(st, bid)
	if int(outcome.get("draw", 0)) == 0 and f >= 0 and not bt.is_empty():
		var won := CRules.battle_side_of(st, bt, f) == (0 if int(outcome.get("winner", 1)) == 0 else 1)
		result = "win" if won else "loss"
	for c in _auto_box.get_children():
		if c is ProgressBar:
			c.visible = false   # (the die takes its place)
	_die = DieRoll.new()
	_die.setup(result)
	_auto_box.add_child(_die)
	_die.settled.connect(func():
		_die.queue_free()
		_die = null
		_auto_box = null
		_apply_battle(bid, outcome), CONNECT_ONE_SHOT)
	return true


func _apply_battle(bid: int, outcome: Dictionary) -> void:
	if int(_battle_snap.get("bid", -1)) != bid:
		_battle_snap = {}
	if online != null:
		onl.upload(bid, outcome)
		_after_battle_refresh()
		return
	var before := (st["events"] as Array).size()
	var bt := CState.battle(st, bid)
	var won := false
	if not bt.is_empty() and f >= 0 and int(outcome.get("draw", 0)) == 0:
		won = CRules.battle_side_of(st, bt, f) == (0 if int(outcome.get("winner", 1)) == 0 else 1)
	st = CTurn.apply_battle(st, bid, outcome)
	save()
	_replan()
	if won:
		Tips.show("battle_won")
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
	if b.has("sea"):
		_fight_sea(b, hf)
		return
	_battle_built = CBattle.build(st, b, hf)
	var lesson: bool = tutorial != null and tutorial.is_lesson_battle(b)
	if lesson:
		(_battle_built["scenario"] as Dictionary).erase("weather")   # (the tutorial's battle teaches the orders: a clear day)
	_battle_snap = BattleScreen.snapshot(st, b, f)
	_battle_id = bid
	battle = Battle.new()
	battle.dive = true
	battle.staged = true   # the loading plate over the setup (game/battle_loading.gd)
	battle.tap_msec = Time.get_ticks_msec()
	battle.custom_scenario = _battle_built["scenario"]
	battle.unit_faction = _battle_built.get("unit_faction", [])
	battle.seed_value = int(_battle_built["seed"])
	battle.weather = "" if lesson else CWeather.of(b)   # (the pending battle's weather, decided by the rules: campaign/cweather.gd)
	battle.scenario_id = "campaign"
	battle.campaign_mode = true
	battle.tutorial = tutorial.battle_script(b)
	battle.exit_requested.connect(_on_battle_exit)
	close_dialog()
	_set_visible(false)
	_t("campaign_battle_start", {"turn": int(st["turn"]), "region": int(b["r"]), "units": (_battle_built["map"] as Array).size()})
	_enter_battle()


## (N3a) A sea battle fought in real time (game/sea_battle.gd), the player
## commanding the side of faction hf, the battle AI the other.
func _fight_sea(b: Dictionary, hf: int) -> void:
	var bid := int(b["id"])
	_battle_built = CSeaBattle.build(st, b, hf)
	_battle_snap = BattleScreen.snapshot(st, b, f)
	_battle_id = bid
	var sb := SeaBattle.new()
	sb.scenario = _battle_built["scenario"]
	sb.seed_value = int(_battle_built["seed"])
	sb.player_side = int(_battle_built["player_side"])
	sb.campaign_mode = true
	sb.look_cell = Vector2i(int(b["x"]), int(b["y"]))   # the water and land look (game/sea_look.gd)
	sb.look_region = int(b["r"])
	sb.title_text = BattleScreen.title(st, b)
	var facs := CRules.battle_factions(st, b)
	var names := ["", ""]
	var cols: Array = []
	for k in 2:
		names[k] = "The %s fleet" % str(CData.FACTIONS[int(facs[k][0])]["adj"])
		cols.append(CData.faction_color(int(facs[k][0])))
	sb.side_names = names
	sb.side_cols = cols
	for u in sb.scenario["units"]:
		var fc := CData.faction_color(int(u.get("f", 0)))
		u["col"] = [fc.r, fc.g, fc.b]
	battle = sb
	battle.exit_requested.connect(_on_battle_exit)
	close_dialog()
	_set_visible(false)
	_t("campaign_battle_start", {"turn": int(st["turn"]), "region": int(b["r"]), "units": (_battle_built["map"] as Array).size(),
		"sea": 1})
	get_tree().root.add_child(battle)


## Add the battle node (its map bakes run in its _ready) behind a short
## "Preparing the battlefield" panel when the build is slow: always the first
## time (unknown), later only when the last build took more than 300 ms.
func _enter_battle() -> void:
	if battle == null or not is_instance_valid(battle):
		return
	# The battle shows its own loading plate over its setup, a step a frame (Battle.staged, game/battle_loading.gd).
	get_tree().root.add_child(battle)


## Server changes that arrived during a battle are shown afterwards.
func _after_battle_refresh() -> void:
	if online != null and has_meta("refresh_after_battle"):
		remove_meta("refresh_after_battle")
		st = online.st
		_replan()


func _set_visible(on: bool) -> void:
	world.visible = on
	overlay.visible = on
	# The miniatures and the table frame switch themselves on each frame;
	# their canvas layers hide them while a battle is open.
	(minis.get_parent() as CanvasLayer).visible = on
	(table_frame.get_parent() as CanvasLayer).visible = on
	ui.visible = on
	set_process_unhandled_input(on)


## A live co-op battle (milestone 5): open its room (create, the host) or
## join the open one, built from the campaign version the room was opened
## at. keep: let the host keep command of this player's units. A player
## whose army is not in the battle joins as a guest (units given to them).
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
	if b.has("sea"):
		_fight_sea_live(bst, b, hs, hmin, v, create, keep)
		return
	_battle_built = CBattle.build(bst, b, hmin)
	_battle_snap = BattleScreen.snapshot(bst, b, f)
	_battle_id = bid
	var net := get_node_or_null("/root/Net")
	var coop = CoopSession.new()
	add_child(coop)
	# Every human with an army in it (either side) may join, and their
	# team-mates without one (guests, given units on their team's side).
	var gl: Array = CoopSession.guest_list(bst, hs, b)
	coop.setup(net.api.base_url if net != null else "", online.id, online.token, online.f, _battle_built, hs, v, create, keep,
		gl, CoopSession.guest_sides(bst, b, _battle_built, gl))
	coop.failed.connect(func(code: String, text: String): _coop_failed(code, text))
	battle = Battle.new()
	battle.dive = true
	battle.staged = true   # the loading plate over the setup (game/battle_loading.gd)
	battle.tap_msec = Time.get_ticks_msec()
	battle.custom_scenario = _battle_built["scenario"]
	battle.unit_faction = _battle_built.get("unit_faction", [])
	battle.seed_value = int(_battle_built["seed"])
	battle.weather = CWeather.of(b)
	battle.scenario_id = "campaign_live"
	battle.campaign_mode = true
	battle.coop = coop
	battle.player_side = coop.side_of_player(online.f)
	battle.coop_region = str(CData.REGIONS[int(b["r"])]["city"])
	battle.exit_requested.connect(_on_battle_exit)
	close_dialog()
	_set_visible(false)
	_t("campaign_battle_start", {"turn": int(st["turn"]), "region": int(b["r"]), "units": (_battle_built["map"] as Array).size(),
		"live": true, "create": create})
	_enter_battle()


## A live sea battle (milestone 5 at sea): the room and the lockstep as for
## a land battle (CoopSession with CSeaBattle.build's controllers), fought
## in game/sea_battle.gd.
func _fight_sea_live(bst: Dictionary, b: Dictionary, hs: Array, hmin: int, v: int, create: bool, keep: bool) -> void:
	var bid := int(b["id"])
	_battle_built = CSeaBattle.build(bst, b, hmin)
	_battle_snap = BattleScreen.snapshot(bst, b, f)
	_battle_id = bid
	var net := get_node_or_null("/root/Net")
	var coop = CoopSession.new()
	add_child(coop)
	var gl: Array = CoopSession.guest_list(bst, hs, b)
	coop.setup(net.api.base_url if net != null else "", online.id, online.token, online.f, _battle_built, hs, v, create, keep,
		gl, CoopSession.guest_sides(bst, b, _battle_built, gl))
	coop.failed.connect(func(code: String, text: String): _coop_failed(code, text))
	var sb := SeaBattle.new()
	sb.scenario = _battle_built["scenario"]
	sb.seed_value = int(_battle_built["seed"])
	sb.player_side = coop.side_of_player(online.f)
	sb.campaign_mode = true
	sb.look_cell = Vector2i(int(b["x"]), int(b["y"]))   # the water and land look (game/sea_look.gd)
	sb.look_region = int(b["r"])
	sb.title_text = BattleScreen.title(bst, b)
	sb.coop = coop
	sb.coop_region = sb.title_text
	var facs := CRules.battle_factions(bst, b)
	var names := ["", ""]
	var cols: Array = []
	for k in 2:
		names[k] = "The %s fleet" % str(CData.FACTIONS[int(facs[k][0])]["adj"])
		cols.append(CData.faction_color(int(facs[k][0])))
	sb.side_names = names
	sb.side_cols = cols
	for u in sb.scenario["units"]:
		var fc := CData.faction_color(int(u.get("f", 0)))
		u["col"] = [fc.r, fc.g, fc.b]
	battle = sb
	battle.exit_requested.connect(_on_battle_exit)
	close_dialog()
	_set_visible(false)
	_t("campaign_battle_start", {"turn": int(st["turn"]), "region": int(b["r"]), "units": (_battle_built["map"] as Array).size(),
		"live": true, "create": create, "sea": 1})
	get_tree().root.add_child(battle)


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
		"not_in_battle":
			msg = "Your army is not in this battle: ask to join, and join when your ally opens it."
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
	if battle is SeaBattle and battle.coop != null:
		_on_coop_exit()
		return
	if battle is SeaBattle:
		var sres: Dictionary = battle.sim.result()
		var sdec: bool = battle.is_decided()
		var sout: Dictionary
		if sdec:
			sout = CSeaBattle.outcome_from_result(_battle_built, sres, "fought")
		else:
			sout = CSeaBattle.outcome_forfeit(_battle_built, sres)
		_t("campaign_battle", {"mode": "fought" if sdec else "forfeit", "turn": int(st["turn"]), "ticks": int(sres["tick"]),
			"winner": int(sout["winner"]), "sea": 1})
		battle.queue_free()
		battle = null
		_set_visible(true)
		_apply_battle(_battle_id, sout)
		return
	if battle.coop != null:
		_on_coop_exit()
		return
	var res: Dictionary = battle.sim.result()
	var decided: bool = battle.is_decided()
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
	if _battle_built.has("sea"):
		# (Live co-op at sea) The last player leaving forfeits their side.
		if bool(r["decided"]):
			outcome = CSeaBattle.outcome_from_result(_battle_built, r["res"], "fought")
		else:
			outcome = CSeaBattle.outcome_from_result(_battle_built, r["res"], "forfeit", c.side_of_player(c.me))
	elif bool(r["decided"]):
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
	var bottom_cover := _bar_lift()   # the command bar hides the map's foot
	var avail := vp - Vector2(0, TOP_H + bottom_cover)
	var fit := minf(avail.x / Geo.SIZE.x, avail.y / Geo.SIZE.y)
	zoom = clampf(zoom, fit, ZOOM_MAX)  # never smaller than the whole map (above the bar)
	var mapsz := Geo.SIZE * zoom
	var margin_x := maxf(60.0, avail.x * 0.25)
	var margin_y := maxf(60.0, avail.y * 0.33)
	# Along each axis: centred if the map fits, else kept on screen with a real buffer.
	if mapsz.x <= avail.x:
		offset.x = (vp.x - mapsz.x) * 0.5
	else:
		# The right edge may come in past the side panel.
		offset.x = clampf(offset.x, vp.x - mapsz.x - minf(PANEL_W, vp.x * 0.48) - margin_x, margin_x)
	if mapsz.y <= avail.y:
		offset.y = TOP_H + (avail.y - mapsz.y) * 0.5
	else:
		offset.y = clampf(offset.y, vp.y - bottom_cover - mapsz.y - margin_y, TOP_H + margin_y)


func _zoom_at(p: Vector2, factor: float) -> void:
	var m := _map_point(p)
	zoom = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	offset = p - m * zoom
	_clamp_view()


func _blocked() -> bool:
	return dialog.visible or book.visible or controls_page.visible or cover.visible or battle != null or game_menu.visible


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
		elif mb.button_index == MOUSE_BUTTON_RIGHT and _g():
			# Real mouse (Total War): a right click is the ORDER for the selection (what a tap does), a right drag
			# pans, a right click with nothing to order does nothing.
			if mb.device == InputEvent.DEVICE_ID_EMULATION:
				return
			if mb.pressed:
				_set_last_mouse(true)
				_rmb_down = true
				_rmb_start = mb.position
				_rmb_dragged = false
			elif _rmb_down:
				_rmb_down = false
				_mouse_pan = false
				if not _rmb_dragged:
					_right_order(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mouse_pan = mb.pressed
			if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and sel_army >= 0:
				# Right click on a region with an army selected: move there.
				var r := _region_at(mb.position)
				if r >= 0 and map_view.targets.has(r):
					set_move(sel_army, r)
					_mouse_pan = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _rmb_down and not _rmb_dragged and mm.position.distance_to(_rmb_start) > DRAG_THRESHOLD:
			_rmb_dragged = true
			_mouse_pan = true
		if _mouse_pan:
			offset += mm.relative
			_clamp_view()
	elif event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
	elif event is InputEventPanGesture:
		offset -= event.delta * 8.0
		_clamp_view()
	elif event is InputEventKey and event.pressed and not event.echo:
		match Controls.action_for_key(event as InputEventKey, "campaign"):
			"map_deselect":
				if side.visible or sel_army >= 0 or sel_fleet >= 0 or sel_region >= 0 or merge_tap >= 0:
					deselect_all()
					get_viewport().set_input_as_handled()
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
	var is_mouse := e.device == InputEvent.DEVICE_ID_EMULATION
	if e.pressed:
		_touches[e.index] = e.position
		_set_last_mouse(is_mouse)
		if not is_mouse:
			# Two-finger tap = deselect: both fingers down within 120 ms, up within 250 ms, each under 12 px.
			var tnow := Time.get_ticks_msec()
			if _touches.size() == 1:
				_tt_t0 = tnow
				_tt_ok = false
				_tt_start.clear()
			elif _touches.size() == 2:
				_tt_ok = tnow - _tt_t0 <= TWO_TAP_DOWN_MS
			else:
				_tt_ok = false
			_tt_start[e.index] = e.position
		if _touches.size() == 1:
			_press_pos = e.position
			_press_mouse = is_mouse
			_dragging = false
			_multi = false
			_drag_army = -1
			_boxing = false
			_lp_fired = false
			_lp_box = false
			_lp_t0 = 0 if is_mouse else maxi(Time.get_ticks_msec(), 1)
			_box_ok = is_mouse and _g() and f >= 0 and _shift_held() and overlay.army_at(e.position) < 0 and overlay.settlement_at(e.position) < 0 \
				and (not CFleet.on(ps) or overlay.fleet_at(e.position) < 0)
			if _g() and f >= 0:
				# A drag that starts on one of our free armies plans its march.
				var id := overlay.army_at(e.position)
				var a := CState.army(ps, id) if id >= 0 else {}
				if not a.is_empty() and int(a["f"]) == f and int(a["busy"]) == 0:
					_drag_army = id
		else:
			_multi = true
			_lp_t0 = 0
			_boxing = false
			_box_panel.visible = false
			_drag_army = -1
			overlay.set_drop(-1)
			_drag_preview(-1, -1)
			_start_pinch()
		return
	if _drag_army >= 0 and _dragging and not _multi and _touches.has(e.index):
		_touches.erase(e.index)
		var id2 := _drag_army
		_drag_army = -1
		_dragging = false
		_drag_preview(-1, -1)
		var xt := _exchange_target(id2, e.position)
		overlay.set_drop(-1)
		if sel_army != id2 and not in_set("a", id2):
			select_army(id2)
		if xt >= 0:
			# dropped on another army of ours standing with it: the Exchange dialog (the drag's march is not planned)
			merge_tap = -1
			panels.show_exchange(id2, xt)
			_t("campaign_input", {"what": "exchange_drag"})
			return
		_plan_at(e.position)
		return
	if not _touches.has(e.index):
		return
	_touches.erase(e.index)
	if _tt_ok and _touches.is_empty():
		_tt_ok = false
		if Time.get_ticks_msec() - _tt_t0 <= TWO_TAP_TOTAL_MS:
			_multi = false
			_dragging = false
			if side.visible or sel_army >= 0 or sel_fleet >= 0 or sel_region >= 0 or merge_tap >= 0:
				deselect_all()
			return
	if _multi:
		if _touches.is_empty():
			_multi = false
		elif _touches.size() >= 2:
			_start_pinch()
		return
	_lp_t0 = 0
	if _boxing:
		_box_end(e.position)
		_dragging = false
		return
	if _lp_fired:
		_lp_fired = false   # (the long press was the gesture: no tap)
		_dragging = false
		return
	if not _dragging:
		if _press_mouse and _g():
			_left_click(e.position)
		else:
			_tap(e.position)
	_dragging = false


func _on_drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index):
		return
	_touches[e.index] = e.position
	if _tt_ok and _tt_start.has(e.index) and e.position.distance_to(_tt_start[e.index]) > TWO_TAP_MOVE:
		_tt_ok = false
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
		_lp_t0 = 0
		if (_lp_box or _box_ok) and _drag_army < 0 and not _boxing:
			# multi-select: a drag from empty ground (a real mouse's left button, or a touch after its long press) is the box
			_boxing = true
			_box_from = _press_pos
			_box_add = add_mode or Input.is_key_pressed(KEY_CTRL)
	if _boxing:
		_box_update(e.position)
		return
	if _dragging and _drag_army >= 0:
		var xt := _exchange_target(_drag_army, e.position)
		overlay.set_drop(xt)
		if xt >= 0:
			if _drag_cell >= 0:
				_drag_preview(-1, -1)   # over an army to trade with: no march path, the target is ringed
			return
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
		if add_mode:
			_tap_add(p)
			return
		if _double_tap(p):
			return
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
	if sel_army < 0 and _crossing_note(p):
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
	if set_size() > 1 and _tap_set(p):
		return
	if CFleet.on(ps) and _tap_fleets(p):
		return
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
	var mk := overlay.marker_at(p)
	if not mk.is_empty():
		_marker_toast(mk)   # (fog: a last-seen marker says what and when)
		return
	var sr := overlay.settlement_at(p)
	if sr >= 0:
		select_region(sr)
		return
	if _lane_tap(p):
		return
	if _crossing_note(p):
		return
	var r := Geo.region_at(_map_point(p))
	if r >= 0:
		select_region(r)
		return
	close_side()


## (Sea lanes) A tap on a raided lane (or its badge) or on a lane between ports at war says why: who raids it and how to
## stop it, or that the ports at war do not trade. True when it was one.
func _lane_tap(p: Vector2) -> bool:
	if CData.SEA_LANES.is_empty() or not CState.grid_on(ps):
		return false
	var id := overlay.lane_at_info(p)
	if id < 0:
		return false
	var rt := CLanes.raiders(ps)
	var ri := overlay.raided_info(id, rt)
	var lname := CLanes.lane_name(id)
	if not ri.is_empty():
		var fl: Dictionary = ri["fleet"]
		var n := (fl["ships"] as Array).size()
		var near := -1
		var bd := 1 << 30
		for r in CData.region_count():
			var d := CGrid.octile(CFleet.cell(fl), CGrid.site(r))
			if d < bd:
				bd = d
				near = r
		var who := "%s fleet (%d ship%s)" % [CData.FACTIONS[int(ri["f"])]["adj"], n, "" if n == 1 else "s"] if bool(ri["seen"]) else "an unseen fleet"
		show_toast("The %s lane is raided by the %s at %s: attack it with a stronger fleet, blockade its port, or make peace." % [
			lname, who, str(CData.REGIONS[near]["city"])] if bool(ri["seen"]) else
			"The %s lane is raided by an enemy fleet out of sight: find it and attack it with a stronger fleet, blockade its port, or make peace." % lname)
		return true
	if CLanes.at_war(ps, id):
		var e := CLanes.ends(id)
		show_toast("No trade on the %s lane: %s and %s are at war." % [lname,
			CData.faction_name(CState.owner(ps, int(e[0]))), CData.faction_name(CState.owner(ps, int(e[1])))])
		return true
	if CLanes.idle(ps, id):
		show_toast(idle_lane_text(ps, f, id))
		return true
	return false


## (2026-11-09, lanes trade by agreement) Why lane id carries no trade: "No trade agreement with Spain: the Havana -
## Veracruz lane pays nothing. Offer trade on the Diplomacy page." when `me` owns one end, else names both owners.
static func idle_lane_text(lst: Dictionary, me: int, id: int) -> String:
	var e := CLanes.ends(id)
	var oa := CState.owner(lst, int(e[0]))
	var ob := CState.owner(lst, int(e[1]))
	var lname := CLanes.lane_name(id)
	var other := ob if CState.same_team(lst, me, oa) else (oa if CState.same_team(lst, me, ob) else -1)
	if me >= 0 and other >= 0:
		return "No trade agreement with %s: the %s lane pays nothing. Offer trade on the Diplomacy page (an alliance trades too)." % [
			CData.faction_name(other), lname]
	return "No trade on the %s lane: %s and %s have no trade agreement." % [lname, CData.faction_name(oa), CData.faction_name(ob)]


## Fog of war: what a tap on a faded last-seen marker says.
func _marker_toast(mk: Dictionary) -> void:
	var fleet := int(mk["kind"]) == 1
	var n := int(mk["units"])
	var what := "%d ship%s" % [n, "" if n == 1 else "s"] if fleet else "%d unit%s" % [n, "" if n == 1 else "s"]
	show_toast("%s %s (%s) last seen on turn %d. It is out of sight now, so it may have moved." % [
		CData.faction_name(int(mk["f"])), "fleet" if fleet else "army", what, int(mk["turn"])])


## Fleets (a pack with ships): a tap on a fleet selects it (ours selected:
## an enemy's is an attack; an army of ours selected: our fleet is boarding
## it; our fleet selected: another fleet of ours is a join, within a cell
## now (fmerge), else a voyage to it that merges on arriving); with our
## fleet selected a tap on the sea or a coast is a voyage.
## Returns true when the tap was the fleets'.
func _tap_fleets(p: Vector2) -> bool:
	var fid := overlay.fleet_at(p)
	var sf := CFleet.fleet(ps, sel_fleet) if sel_fleet >= 0 else {}
	var mine_f := not sf.is_empty() and int(sf["f"]) == f
	if fid >= 0:
		var fl := CFleet.fleet(ps, fid)
		if fid == sel_fleet:
			close_side()
			return true
		if mine_f and CState.at_war(ps, f, int(fl["f"])):
			set_fmove(sel_fleet, -1, fid)
			return true
		var sa := CState.army(ps, sel_army) if sel_army >= 0 else {}
		if not sa.is_empty() and int(sa["f"]) == f and int(fl["f"]) == f:
			if CFleet.embark_check(ps, f, sel_army, fid) == "" or CFleet.near_fleet(sa, fl):
				embark(sel_army, fid)
			else:
				set_board(sel_army, fid)
			return true
		if mine_f and int(fl["f"]) == f and not fl.has("flota"):
			join_fleet(sel_fleet, fid)
			return true
		select_fleet(fid)
		_t("campaign_input", {"what": "select_fleet"})
		return true
	if mine_f and overlay.army_at(p) < 0:
		var c := MapOverlay.cell_of_point(_map_point(p))
		var tsr := overlay.settlement_at(p)
		# (Sea lanes) an enemy harbour with no troops aboard: blockade it; a lane we could raid: raid it.
		# (Docking) one of our (or an ally's) port cities: dock there (an empty fleet at once, a loaded one after the Dock button).
		if tsr >= 0 and not sf.has("flota") and CFleet.can_dock(ps, f, tsr) and ((sf["carry"] as Array).is_empty() or dock_mode == sel_fleet):
			dock_mode = -1
			set_station(sel_fleet, -1, tsr, true)
			_after_station()
			return true
		if tsr >= 0 and (sf["carry"] as Array).is_empty() and CFleet.harbour(tsr) >= 0 and CState.owner(ps, tsr) >= 0 \
				and CState.at_war(ps, f, CState.owner(ps, tsr)) and not sf.has("flota"):
			set_station(sel_fleet, -1, tsr)
			_after_station()
			return true
		if tsr < 0 and not sf.has("flota"):
			var ln := overlay.lane_at(p, overlay.raid_lanes)
			if ln >= 0:
				set_station(sel_fleet, ln, -1)
				_after_station()
				return true
		if tsr >= 0:
			c = CGrid.site(tsr)   # anywhere on a town: its harbour
		if c >= 0 and (CFleet.is_sea(c) or CGrid.passable(c)):
			set_fmove(sel_fleet, c)
			if sel_fleet >= 0 and not CFleet.fleet(ps, sel_fleet).is_empty():
				show_side(func(box): panels.fleet_panel(box, sel_fleet))
			return true
	return false


func _after_station() -> void:
	if sel_fleet >= 0 and not CFleet.fleet(ps, sel_fleet).is_empty():
		show_side(func(box): panels.fleet_panel(box, sel_fleet))


## Real mouse, left click on the overworld (Total War): it only selects. One of our armies / fleets, a city or a
## region selects it (another faction's army or fleet for viewing: the card, never an attack); with ours
## selected, a left click on our other army / fleet SELECTS it (merge and join are the right click's); empty map
## (sea, nothing pickable) deselects, and never orders. Shift keeps the selection. Orders are the right button's.
func _left_click(p: Vector2, additive: bool = false) -> void:
	if f < 0:
		return
	var shift := Input.is_key_pressed(KEY_SHIFT)
	var add := additive or shift or Input.is_key_pressed(KEY_CTRL)
	if _g() and not add and _double_tap(p):
		return
	var fid := overlay.fleet_at(p) if CFleet.on(ps) else -1
	var multi := set_size() > 1
	if fid >= 0:
		if add and _own_fleet(fid):
			add_to_set("f", fid)   # (multi-select: Shift / Ctrl adds the fleet or takes it out)
			return
		_clear_more()
		if fid == sel_fleet and not multi:
			close_side()
		else:
			select_fleet(fid)
			_t("campaign_input", {"what": "select_fleet"})
		return
	var id := overlay.army_at(p)
	if id >= 0:
		if add and _own_army(id):
			add_to_set("a", id)
			return
		_clear_more()
		if id == sel_army and not multi:
			close_side()
		else:
			select_army(id)
			_t("campaign_input", {"what": "select_army"})
		return
	var mk := overlay.marker_at(p)
	if not mk.is_empty():
		_marker_toast(mk)
		return
	var sr := overlay.settlement_at(p)
	if sr >= 0:
		select_region(sr)
		return
	if _crossing_note(p):
		return
	var r := Geo.region_at(_map_point(p))
	if r >= 0:
		select_region(r)
		return
	if not shift:
		deselect_all()


## Real mouse, right click (no drag) on the overworld: the ORDER for what is selected, exactly what a tap on that
## target does (an army: march / attack / siege / join / board; a fleet: sail / land / attack / join). With nothing
## of ours selected, nothing.
func _right_order(p: Vector2) -> void:
	if f < 0:
		return
	if set_size() > 1:
		_tap6(p)   # (multi-select: the order is the whole set's)
		return
	var sf := CFleet.fleet(ps, sel_fleet) if sel_fleet >= 0 and CFleet.on(ps) else {}
	if not sf.is_empty():
		if int(sf["f"]) == f:
			_tap_fleets(p)
		return
	var sa := CState.army(ps, sel_army) if sel_army >= 0 else {}
	if not sa.is_empty() and int(sa["f"]) == f and int(sa["busy"]) == 0:
		_tap6(p)


func _set_last_mouse(v: bool) -> void:
	if v != last_mouse:
		last_mouse = v
		_update_hint()


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
	var grp := _free_set_armies()
	if grp.size() > 1:
		move_group(grp, int(tg[0]), int(tg[1]))
		return
	set_move6(sel_army, int(tg[0]), int(tg[1]))
	if sel_army >= 0 and not CState.army(ps, sel_army).is_empty():
		show_side(func(box): panels.army_panel(box, sel_army))


## The army of ours under screen point p that the dragged army `id` may trade units with (same faction, standing
## together: CRules.together via the panel's partners), -1 none. Dropping on it opens the Exchange dialog.
func _exchange_target(id: int, p: Vector2) -> int:
	var tid := overlay.army_at(p)
	if tid < 0 or tid == id:
		return -1
	var a := CState.army(ps, id)
	var b := CState.army(ps, tid)
	if a.is_empty() or b.is_empty() or int(a["f"]) != f or int(b["f"]) != f:
		return -1
	for o in panels._partners(ps, a):
		if int(o["id"]) == tid:
			return tid
	return -1


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
	overlay.redraw_parts(true, false, false)   # (the drag preview is drawn with the paths)


# ---------------------------------------------------------------------------
# Multi-select on the campaign map (2026-11-09, view only; ui.md "Multi-select on the campaign map"). The selection is a
# set of our own armies and fleets: the focus is sel_army or sel_fleet (everything that reads those still works for a
# set of one), the others are sel_more_armies / sel_more_fleets. A group order is one ordinary per-unit order each
# (add_order / set_move6 / set_fmove / embark ...): the rules do not change.
# ---------------------------------------------------------------------------

const DOUBLE_TAP_MS := 380
const LONG_PRESS_MS := 480
const BOX_MIN := 14.0

var sel_more_armies: Array = []   # the other selected armies (ids), the focus is sel_army
var sel_more_fleets: Array = []   # the other selected fleets (ids)
var add_mode := false             # touch: taps add or remove armies / fleets (the capsule's Done ends it)
var set_detail := false           # a card of the set bar was tapped: the focus's own bar (unit cards), the set kept
var _sel_capsule: PanelContainer = null
var _capsule_label: Label = null
var _box_panel: Panel = null
var _box_ok := false              # the press now down began on empty ground (a drag from it is the box)
var _boxing := false
var _box_add := false
var _box_from := Vector2.ZERO
var _lp_t0 := 0                   # ticks (ms) of the touch now down (0 none): a long press adds / starts the box
var _lp_fired := false
var _lp_box := false              # the long press began on empty ground: the drag that follows is the box
var _last_tap := {}
var test_shift := false           # testing aid: Shift counts as held (the real mouse's box is Shift + left drag)


func _shift_held() -> bool:
	return test_shift or Input.is_key_pressed(KEY_SHIFT)


func _own_army(id: int) -> bool:
	var a := CState.army(ps, id)
	return not a.is_empty() and int(a["f"]) == f


func _own_fleet(id: int) -> bool:
	if not CFleet.on(ps):
		return false
	var fl := CFleet.fleet(ps, id)
	return not fl.is_empty() and int(fl["f"]) == f


## The selected armies of ours (ids, the focus first).
func set_armies() -> Array:
	var out: Array = []
	if sel_army >= 0 and _own_army(sel_army):
		out.append(sel_army)
	for id in sel_more_armies:
		if _own_army(int(id)) and not out.has(int(id)):
			out.append(int(id))
	return out


## The selected fleets of ours (ids, the focus first).
func set_fleets() -> Array:
	var out: Array = []
	if sel_fleet >= 0 and _own_fleet(sel_fleet):
		out.append(sel_fleet)
	for id in sel_more_fleets:
		if _own_fleet(int(id)) and not out.has(int(id)):
			out.append(int(id))
	return out


func set_size() -> int:
	return set_armies().size() + set_fleets().size()


func in_set(kind: String, id: int) -> bool:
	return set_armies().has(id) if kind == "a" else set_fleets().has(id)


func _clear_more() -> void:
	sel_more_armies = []
	sel_more_fleets = []
	set_detail = false
	add_mode = false


## Shift / Ctrl click, add mode's tap: add the army ("a") or fleet ("f") to the set, or take it out when it is in.
## With no army or fleet of ours selected it is a plain select.
func add_to_set(kind: String, id: int) -> void:
	if f < 0 or not (_own_army(id) if kind == "a" else _own_fleet(id)):
		return
	if set_size() == 0:
		if kind == "a":
			select_army(id)
		else:
			select_fleet(id)
		return
	if in_set(kind, id):
		_remove_from_set(kind, id)
	elif kind == "a":
		sel_more_armies.append(id)
	else:
		sel_more_fleets.append(id)
	_after_set_change()


func _remove_from_set(kind: String, id: int) -> void:
	if (kind == "a" and id == sel_army) or (kind == "f" and id == sel_fleet):
		var nk := ""
		var nid := -1
		if not sel_more_armies.is_empty():
			nk = "a"
			nid = int(sel_more_armies.pop_front())
		elif not sel_more_fleets.is_empty():
			nk = "f"
			nid = int(sel_more_fleets.pop_front())
		if nid < 0:
			close_side()
			return
		if nk == "a":
			sel_army = nid
			sel_fleet = -1
		else:
			sel_fleet = nid
			sel_army = -1
	elif kind == "a":
		sel_more_armies.erase(id)
	else:
		sel_more_fleets.erase(id)


## A card on the set bar was tapped: that army / fleet is the focus, the set stays.
func set_focus(kind: String, id: int) -> void:
	if not in_set(kind, id):
		return
	var arm := set_armies()
	var fls := set_fleets()
	if kind == "a":
		arm.erase(id)
	else:
		fls.erase(id)
	if kind == "a":
		sel_army = id
		sel_fleet = -1
		sel_more_armies = arm
		sel_more_fleets = fls
	else:
		sel_fleet = id
		sel_army = -1
		sel_more_armies = arm
		sel_more_fleets = fls
	set_detail = true
	_after_set_change()


func _after_set_change() -> void:
	sel_region = -1
	merge_tap = -1
	if set_size() > 1:
		side.visible = false
	else:
		set_detail = false
		add_mode = false
	_defer_sel = true
	_refresh_map()
	_defer_sel = false
	_update_hint()
	_t("campaign_input", {"what": "set_change", "n": set_size()})


## Select exactly these armies and fleets (ids; the first army, else the first fleet, is the focus).
func select_set(armies: Array, fleets: Array) -> void:
	var arm: Array = []
	for id in armies:
		if _own_army(int(id)) and not arm.has(int(id)):
			arm.append(int(id))
	var fls: Array = []
	for id in fleets:
		if _own_fleet(int(id)) and not fls.has(int(id)):
			fls.append(int(id))
	if arm.is_empty() and fls.is_empty():
		return
	if arm.size() + fls.size() == 1:
		if arm.is_empty():
			select_fleet(int(fls[0]))
		else:
			select_army(int(arm[0]))
		return
	var keep_add := add_mode
	_clear_more()
	add_mode = keep_add
	dock_mode = -1
	if not arm.is_empty():
		sel_army = int(arm[0])
		sel_fleet = -1
		sel_more_armies = arm.slice(1)
		sel_more_fleets = fls
	else:
		sel_fleet = int(fls[0])
		sel_army = -1
		sel_more_fleets = fls.slice(1)
	_after_set_change()


## Double tap: every army of ours in the tapped one's region (not busy in a battle), or every fleet of ours at the tapped
## one's port or cell. False when it is not ours or alone there (then the tap is the ordinary one).
func select_together(kind: String, id: int) -> bool:
	if kind == "a":
		var a := CState.army(ps, id)
		if a.is_empty() or int(a["f"]) != f:
			return false
		var ids: Array = []
		for o in CState.armies_of(ps, f):
			if int(o["r"]) == int(a["r"]) and int(o["busy"]) == 0 and int(o["id"]) != id:
				ids.append(int(o["id"]))
		if ids.is_empty() or int(a["busy"]) != 0:
			return false
		ids.push_front(id)
		select_set(ids, [])
		return true
	var fl := CFleet.fleet(ps, id) if CFleet.on(ps) else {}
	if fl.is_empty() or int(fl["f"]) != f:
		return false
	var dk := CFleet.docked(fl)
	var fids: Array = []
	for o in CFleet.fleets_of(ps, f):
		if int(o["id"]) == id:
			continue
		if CFleet.cell(o) == CFleet.cell(fl) or (dk >= 0 and CFleet.docked(o) == dk):
			fids.append(int(o["id"]))
	if fids.is_empty():
		return false
	fids.push_front(id)
	select_set([], fids)
	return true


## Our armies / fleets whose markers lie inside the screen rectangle (a drag box). With `additive` the set so far stays.
## Returns how many were picked up (the selection is unchanged when none).
func select_in_rect(rect: Rect2, additive: bool = false) -> int:
	if f < 0 or not _g():
		return 0
	var arm: Array = []
	var fls: Array = []
	var pos := overlay.army_positions()
	for id in pos:
		if rect.has_point(pos[id]) and _own_army(int(id)) and int(CState.army(ps, int(id))["busy"]) == 0:
			arm.append(int(id))
	if CFleet.on(ps):
		var fpos := overlay.fleet_positions()
		for id in fpos:
			if rect.has_point(fpos[id]) and _own_fleet(int(id)):
				fls.append(int(id))
	arm.sort()
	fls.sort()
	var n := arm.size() + fls.size()
	if n == 0:
		return 0
	if additive:
		var a2 := set_armies()
		for id in arm:
			if not a2.has(id):
				a2.append(id)
		var f2 := set_fleets()
		for id in fls:
			if not f2.has(id):
				f2.append(id)
		arm = a2
		fls = f2
	select_set(arm, fls)
	return n


## Add mode (touch): taps add or remove armies and fleets until Done (or a tap on the map).
func enter_add_mode(kind: String = "", id: int = -1) -> void:
	if f < 0:
		return
	if kind != "" and id >= 0 and not in_set(kind, id):
		add_to_set(kind, id)
	if set_size() == 0:
		return
	add_mode = true
	_refresh_bar()
	_update_hint()
	_t("campaign_input", {"what": "add_mode"})


func end_add_mode() -> void:
	if not add_mode:
		return
	add_mode = false
	_refresh_bar()
	_update_hint()


## Add mode's tap: one of our markers adds / removes it, anything else ends the mode.
func _tap_add(p: Vector2) -> void:
	var fid := overlay.fleet_at(p) if CFleet.on(ps) else -1
	if fid >= 0 and _own_fleet(fid):
		add_to_set("f", fid)
		return
	var id := overlay.army_at(p) if fid < 0 else -1
	if id >= 0 and _own_army(id):
		add_to_set("a", id)
		return
	end_add_mode()


## "Selecting: 2 armies, 1 fleet" as words.
func set_words() -> String:
	var na := set_armies().size()
	var nf := set_fleets().size()
	var parts: Array = []
	if na > 0:
		parts.append("%d arm%s" % [na, "y" if na == 1 else "ies"])
	if nf > 0:
		parts.append("%d fleet%s" % [nf, "" if nf == 1 else "s"])
	return ", ".join(parts)


func _build_msel_ui() -> void:
	_sel_capsule = Kit.panel(Color(0.12, 0.1, 0.08, 0.96), 6)
	_sel_capsule.name = "select_capsule"
	_sel_capsule.visible = false
	var h := Kit.hbox(8)
	_sel_capsule.add_child(h)
	_capsule_label = Kit.label("", Kit.FONT, Color(1, 0.92, 0.8))
	_capsule_label.name = "select_capsule_label"
	h.add_child(_capsule_label)
	var done := Kit.button("Done", func(): end_add_mode(), 64)
	done.name = "select_done"
	h.add_child(done)
	ui.add_child(_sel_capsule)
	_box_panel = Panel.new()
	_box_panel.name = "select_box"
	_box_panel.visible = false
	_box_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.9, 0.5, 0.12)
	sb.border_color = Color(1.0, 0.85, 0.3, 0.9)
	sb.set_border_width_all(2)
	_box_panel.add_theme_stylebox_override("panel", sb)
	ui.add_child(_box_panel)


## The capsule shows while add mode is on: just under the top bar, centred.
func _update_capsule() -> void:
	if _sel_capsule == null:
		return
	var on := add_mode and set_size() > 0 and _g()
	_sel_capsule.visible = on
	if not on:
		return
	_capsule_label.text = "Selecting: %s." % set_words()
	_sel_capsule.reset_size()
	var vp := _vp()
	_sel_capsule.position = Vector2((vp.x - _sel_capsule.size.x) * 0.5, TOP_H + 8.0)
	_place_capsule.call_deferred()


func _place_capsule() -> void:
	if _sel_capsule == null or not is_instance_valid(_sel_capsule) or not _sel_capsule.visible:
		return
	_sel_capsule.reset_size()
	_sel_capsule.position = Vector2((_vp().x - _sel_capsule.size.x) * 0.5, TOP_H + 8.0)


func _box_update(to: Vector2) -> void:
	var r := Rect2(_box_from, to - _box_from).abs()
	_box_panel.position = r.position
	_box_panel.size = r.size
	_box_panel.visible = true


func _box_end(to: Vector2) -> void:
	_boxing = false
	_lp_box = false
	_box_panel.visible = false
	var r := Rect2(_box_from, to - _box_from).abs()
	var n := select_in_rect(r, _box_add)
	_t("campaign_input", {"what": "box_select", "n": n})
	if n == 0 and not _box_add:
		deselect_all()


## Real mouse and touch: the second tap on the same marker within DOUBLE_TAP_MS selects everything of ours there.
## A lone army (fleet) falls through to the ordinary tap; a merge preview's second tap is the merge's.
func _double_tap(p: Vector2) -> bool:
	var now := Time.get_ticks_msec()
	var fid := overlay.fleet_at(p) if CFleet.on(ps) else -1
	var aid := overlay.army_at(p) if fid < 0 else -1
	var kind := "f" if fid >= 0 else ("a" if aid >= 0 else "")
	var id := fid if fid >= 0 else aid
	var prev := _last_tap
	_last_tap = {"ms": now, "pos": p, "kind": kind, "id": id}
	if kind == "" or prev.is_empty() or str(prev["kind"]) != kind or int(prev["id"]) != id:
		return false
	if now - int(prev["ms"]) > DOUBLE_TAP_MS or p.distance_to(prev["pos"]) > 30.0:
		return false
	if kind == "a" and merge_tap == id:
		return false
	if select_together(kind, id):
		_last_tap = {}
		_t("campaign_input", {"what": "double_tap_select", "n": set_size()})
		return true
	return false


## A touch held still on one of our markers (add mode starts with it) or on empty ground (the drag that follows is a
## box). Called from _tick.
func _long_press_tick() -> void:
	if _lp_t0 == 0 or _lp_fired or _multi or _dragging or _touches.size() != 1 or f < 0 or not _g() or _blocked():
		return
	if Time.get_ticks_msec() - _lp_t0 < LONG_PRESS_MS:
		return
	_lp_t0 = 0
	_lp_fired = long_press_at(_press_pos)   # (true: the long press was the gesture, the release taps nothing)


## A long press at screen point p: on one of our markers it adds it and enters add mode (true); on empty ground it arms the
## box for the drag that may follow (false: a release without a drag is the ordinary tap, however slow).
func long_press_at(p: Vector2) -> bool:
	var fid := overlay.fleet_at(p) if CFleet.on(ps) else -1
	if fid >= 0 and _own_fleet(fid):
		_drag_army = -1
		overlay.set_drop(-1)
		enter_add_mode("f", fid)
		return true
	var id := overlay.army_at(p) if fid < 0 else -1
	if id >= 0 and _own_army(id):
		_drag_army = -1
		overlay.set_drop(-1)
		enter_add_mode("a", id)
		return true
	if fid < 0 and id < 0 and overlay.settlement_at(p) < 0:
		_lp_box = true
		_box_from = p
		_box_add = add_mode
	return false


# ----------------------------------------------------------- group orders ---

## The words of the army (the hero's name, else "the army at <town>").
func army_label(id: int) -> String:
	var hero := CChars.in_slot(ps, id, CChars.SLOT_HERO)
	if not hero.is_empty():
		return str(hero.get("name", "the army"))
	var a := CState.army(ps, id)
	return "the army at %s" % CData.REGIONS[int(a["r"])]["city"] if not a.is_empty() else "an army"


func _toast_text() -> String:
	if _toast == null or not is_instance_valid(_toast):
		return ""
	var ls := _toast.find_children("*", "Label", true, false)
	return str((ls[0] as Label).text) if not ls.is_empty() else ""


func _when_words(last: int) -> String:
	return "this turn" if last <= 0 else ("next turn" if last == 1 else "in %d turns" % (last + 1))


func _plural(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


## Our armies of the set that can take an order now (not in a battle).
func _free_set_armies() -> Array:
	var out: Array = []
	for id in set_armies():
		if int(CState.army(ps, int(id))["busy"]) == 0:
			out.append(int(id))
	return out


## Group Move: every army of `ids` to cell c (after enemy army tgt): one ordinary move each, at its own pace. An army
## already on that march keeps it; when every one already marches there the tap takes the marches back. The toast says
## who arrives when and who cannot go and why.
func move_group(ids: Array, c: int, tgt: int = -1) -> void:
	var all_same := not ids.is_empty()
	for id in ids:
		var cur := plan6(int(id))
		var same := not cur.is_empty() and ((tgt >= 0 and int(cur["tgt"]) == tgt) or (tgt < 0 and int(cur["tgt"]) < 0 and int(cur["cell"]) == c))
		if not same:
			all_same = false
	if all_same:
		for id in ids:
			set_move6(int(id), c, tgt)
		show_toast("Marches cancelled for %s." % _plural(ids.size(), "army", "armies"))
		return
	var ok: Array = []
	var failed: Array = []
	for id in ids:
		var aid := int(id)
		var a := CState.army(ps, aid)
		var cur := plan6(aid)
		if not cur.is_empty() and ((tgt >= 0 and int(cur["tgt"]) == tgt) or (tgt < 0 and int(cur["tgt"]) < 0 and int(cur["cell"]) == c)):
			ok.append(aid)
			continue
		if a.is_empty() or int(a["busy"]) != 0:
			failed.append([aid, "in a battle"])
			continue
		if not recruits_into(aid).is_empty():
			failed.append([aid, "taking recruits this turn"])
			continue
		var rt := CRules.plan_path(ps, a, c, tgt, CData.MODE_SIEGE)
		if rt.has("why"):
			failed.append([aid, str(rt["why"])])
			continue
		set_move6(aid, c, tgt)
		var now := plan6(aid)
		if not now.is_empty() and int(now["cell"]) == c:
			ok.append(aid)
		else:
			failed.append([aid, "refused"])
	var where := str(CData.REGIONS[maxi(CGrid.region(c), 0)]["name"])
	var text := ""
	if not ok.is_empty():
		var parts: Array = []
		if ok.size() <= 4:
			for id in ok:
				var rt2 := route6(int(id))
				var turns: Array = rt2.get("t", [])
				parts.append("%s %s" % [army_label(int(id)), _when_words(int(turns[-1]) if not turns.is_empty() else 0)])
		else:
			var by := {}
			for id in ok:
				var rt3 := route6(int(id))
				var tn: Array = rt3.get("t", [])
				var k := int(tn[-1]) if not tn.is_empty() else 0
				by[k] = int(by.get(k, 0)) + 1
			var ks := by.keys()
			ks.sort()
			for k in ks:
				parts.append("%d %s" % [int(by[k]), _when_words(int(k))])
		text = "%s ordered %s: %s." % [_plural(ok.size(), "army", "armies"), "to attack" if tgt >= 0 else "to " + where, ", ".join(parts)]
	if not failed.is_empty():
		var fl: Array = []
		for e in failed:
			fl.append("%s (%s)" % [army_label(int(e[0])), str(e[1])])
		text += (" " if text != "" else "") + "Cannot go: %s." % ", ".join(fl)
	_t("campaign_input", {"what": "group_move", "ok": ok.size(), "failed": failed.size()})
	show_toast(text)


## Group sail / land: every fleet of `ids` to cell c (a sea cell: sail; a coast cell: land the troops aboard, an empty
## fleet stays). One ordinary fmove each.
func fmove_group(ids: Array, c: int) -> void:
	var landing := not CFleet.is_sea(c)
	var todo: Array = []
	var skipped: Array = []
	for id in ids:
		var fl := CFleet.fleet(ps, int(id))
		if landing and (fl["carry"] as Array).is_empty():
			skipped.append(int(id))
		else:
			todo.append(int(id))
	if todo.is_empty():
		show_toast("No troops aboard to land: the %s stay." % _plural(skipped.size(), "fleet", "fleets"))
		return
	var all_same := true
	for id in todo:
		if int(planned_voyage(int(id))[0]) != c:
			all_same = false
	if all_same:
		for id in todo:
			set_fmove(int(id), c)
		show_toast("Voyages cancelled for %s." % _plural(todo.size(), "fleet", "fleets"))
		return
	var ok: Array = []
	var failed: Array = []
	var units := 0
	for id in todo:
		var fid := int(id)
		if int(planned_voyage(fid)[0]) == c:
			ok.append(fid)
			continue
		var p := CFleet.plan(ps, f, fid, c, -1)
		if p.has("why"):
			failed.append([fid, str(p["why"])])
			continue
		set_fmove(fid, c)
		if int(planned_voyage(fid)[0]) == c:
			ok.append(fid)
			units += CFleet.carried_units(CFleet.fleet(ps, fid))
		else:
			failed.append([fid, "refused"])
	var text := ""
	if not ok.is_empty():
		text = "%s %s%s." % [_plural(ok.size(), "fleet", "fleets"), "land" if landing else "sail",
			" (%s aboard)" % _plural(units, "unit", "units") if landing else ""]
		text = text.replace(" fleet land", " fleet lands").replace(" fleet sail", " fleet sails")
	if not failed.is_empty():
		var fl2: Array = []
		for e in failed:
			fl2.append("fleet %d (%s)" % [int(e[0]), str(e[1])])
		text += (" " if text != "" else "") + "Cannot go: %s." % ", ".join(fl2)
	if not skipped.is_empty():
		text += " %s stay%s (nothing aboard)." % [_plural(skipped.size(), "empty fleet", "empty fleets"), "s" if skipped.size() == 1 else ""]
	_t("campaign_input", {"what": "group_fleet_move", "ok": ok.size(), "failed": failed.size()})
	show_toast(text)


## Embark all: every army of `army_ids` boards the first of `fleet_ids` that has room (selection order, fill one fleet
## then the next); an army not beside any of them marches to board `approach` when it fits (the single tap's rule).
## The toast names who did not fit and why (CFleet.embark_check's own words). Returns {boarded, marching, left}.
func embark_group(army_ids: Array, fleet_ids: Array, approach: int = -1) -> Dictionary:
	var boarded: Array = []
	var marching: Array = []
	var left: Array = []
	var march_units := 0
	for id in army_ids:
		var aid := int(id)
		var a := CState.army(ps, aid)
		if a.is_empty():
			continue
		var done := false
		var why := ""
		for fid in fleet_ids:
			var w := CFleet.embark_check(ps, f, aid, int(fid))
			if w == "":
				if add_order({"t": "embark", "army": aid, "fleet": int(fid)}) == "":
					boarded.append([aid, int(fid)])
					done = true
					break
				w = "the order was refused"
			if why == "" or why.begins_with("not beside"):
				why = w
		if done:
			continue
		if approach >= 0 and why.begins_with("not beside"):
			var afl := CFleet.fleet(ps, approach)
			var bw := CFleet.board_order_check(ps, f, a, approach)
			var room := CFleet.capacity(afl) - CFleet.carried_units(afl) - march_units
			if bw == "" and CState.unit_count(a) > room:
				bw = "not enough room aboard (%d of %d)" % [CFleet.carried_units(afl) + march_units, CFleet.capacity(afl)]
			if bw == "":
				var cur := plan6(aid)
				if not cur.is_empty() and int(cur.get("fleet", -1)) == approach:
					marching.append(aid)
					march_units += CState.unit_count(a)
					continue
				set_board(aid, approach)
				var now := plan6(aid)
				if not now.is_empty() and int(now.get("fleet", -1)) == approach:
					marching.append(aid)
					march_units += CState.unit_count(a)
					continue
				bw = "no way to a cell beside the fleet"
			why = bw
		left.append([aid, why])
	var text := ""
	if not boarded.is_empty():
		text = "%s of %d boarded." % [_plural(boarded.size(), "army", "armies"), army_ids.size()]
	if not marching.is_empty():
		text += (" " if text != "" else "") + "%s march%s to board on arriving." % [_plural(marching.size(), "army", "armies"), "es" if marching.size() == 1 else ""]
	if not left.is_empty():
		var lf: Array = []
		for e in left:
			lf.append("%s (%s)" % [army_label(int(e[0])), str(e[1])])
		text += (" " if text != "" else "") + "Did not fit: %s." % ", ".join(lf)
	if text == "":
		text = "No army to board."
	if left.is_empty() and boarded.is_empty() and marching.is_empty():
		AudioFx.play("refused", 0.9, 0.0, "ui")
	_t("campaign_input", {"what": "embark_group", "boarded": boarded.size(), "left": left.size()})
	_prune_selection()
	if set_size() == 0 and not boarded.is_empty():
		select_fleet(int((boarded[0] as Array)[1]))
	show_toast(text)
	return {"boarded": boarded, "marching": marching, "left": left}


## The set's Board button: armies and fleets both selected.
func board_set() -> void:
	var fls := set_fleets()
	var arm := set_armies()
	if fls.is_empty() or arm.is_empty():
		show_toast("Select armies and a fleet to board them.")
		return
	embark_group(arm, fls, fls[0])


## Merge all: every army of `ids` (not the target) into army `target`, within the unit cap; the rest are reported.
## Armies beside it merge at once, further ones march and merge on arriving (set_join), each its own order.
func merge_group(ids: Array, target: int) -> void:
	var t := CState.army(ps, target)
	if t.is_empty():
		return
	var total := CState.unit_count(t)
	var ok: Array = []
	var left: Array = []
	for id in ids:
		var aid := int(id)
		if aid == target:
			continue
		var a := CState.army(ps, aid)
		if a.is_empty():
			continue
		var n := CState.unit_count(a)
		if total + n > CData.ARMY_MAX:
			left.append([aid, "more than %d units" % CData.ARMY_MAX])
			continue
		var why := merge_why(a, target)
		if why != "":
			left.append([aid, why])
			continue
		if set_join(aid, target, true):
			ok.append(aid)
			total += n
		else:
			left.append([aid, "refused"])
	var text := ""
	if not ok.is_empty():
		text = "%s merge%s into %s (%d units)." % [_plural(ok.size(), "army", "armies"), "s" if ok.size() == 1 else "", army_label(target), total]
	if not left.is_empty():
		var lf: Array = []
		for e in left:
			lf.append("%s (%s)" % [army_label(int(e[0])), str(e[1])])
		text += (" " if text != "" else "") + "Not merged: %s." % ", ".join(lf)
	_t("campaign_input", {"what": "merge_group", "ok": ok.size(), "left": left.size()})
	_prune_selection()
	merge_tap = -1
	if set_size() == 0 or (set_armies().size() == 0 and set_fleets().is_empty()):
		select_army(target)
	_refresh_map()
	show_toast(text)


## The first tap of a group merge: preview in a toast; the second tap (or its Merge button) merges every selected army
## into the tapped one.
func _merge_set_at(id: int) -> void:
	if merge_tap == id:
		if _toast != null:
			_toast.queue_free()
			_toast = null
		merge_group(set_armies(), id)
		return
	merge_tap = id
	var t := CState.army(ps, id)
	var total := CState.unit_count(t)
	var fit := 0
	for aid in set_armies():
		var n := CState.unit_count(CState.army(ps, int(aid)))
		if total + n <= CData.ARMY_MAX:
			total += n
			fit += 1
	_refresh_map()
	var other := id
	show_toast("Merge %s into %s (%d units, at most %d). Tap it again, or Merge. Armies that do not fit stay out and are named." % [
		_plural(fit, "army", "armies"), army_label(id), CState.unit_count(t), CData.ARMY_MAX],
		[["Merge", func(): merge_group(set_armies(), other)], ["Select it", func(): select_army(other)]])
	_t("campaign_input", {"what": "merge_group_preview"})


## Hold: take every selected army's march and every selected fleet's voyage back (each its own cancel).
func hold_group() -> void:
	var n := 0
	for id in set_armies():
		if not plan6(int(id)).is_empty():
			var cur := plan6(int(id))
			set_move6(int(id), int(cur["cell"]), int(cur["tgt"]))
			n += 1
	for id in set_fleets():
		var vy := planned_voyage(int(id))
		if int(vy[0]) >= 0 or int(vy[1]) >= 0:
			set_fmove(int(id), int(vy[0]), int(vy[1]))
			n += 1
	_t("campaign_input", {"what": "hold_group", "n": n})
	show_toast("%s taken back: the selection holds." % _plural(n, "order", "orders") if n > 0 else "Nothing to hold: no march or voyage is planned.")


## Stance for all: every selected army to stance `sv` (one stance order each).
func stance_group(sv: int) -> void:
	for id in set_armies():
		panels._set_stance6(int(id), sv, true)
	_refresh_map()
	_t("campaign_input", {"what": "stance_group", "s": sv})


## What a tap on screen point p orders for a set of more than one: armies to the spot (or after an enemy army), fleets
## to the sea cell or the coast to land on, our fleet with armies selected is Embark all, our other army with armies
## selected is Merge all. True when the tap was the set's.
func _tap_set(p: Vector2) -> bool:
	var arm := _free_set_armies()
	var fls := set_fleets()
	var fid := overlay.fleet_at(p) if CFleet.on(ps) else -1
	if fid >= 0:
		var fl := CFleet.fleet(ps, fid)
		var ours := int(fl["f"]) == f
		if ours and not arm.is_empty():
			var order: Array = [fid]
			for x in fls:
				if int(x) != fid:
					order.append(int(x))
			embark_group(arm, order, fid)
			return true
		if ours and in_set("f", fid):
			if fid == sel_fleet:
				close_side()
			else:
				select_fleet(fid)
			return true
		if ours and not fl.has("flota"):
			for x in fls:
				join_fleet(int(x), fid, true)
			_prune_selection()
			show_toast("%s join%s." % [_plural(fls.size(), "fleet", "fleets"), "s" if fls.size() == 1 else ""])
			return true
		if not ours and CState.at_war(ps, f, int(fl["f"])) and not fls.is_empty():
			for x in fls:
				set_fmove(int(x), -1, fid)
			show_toast("%s ordered to attack." % _plural(fls.size(), "fleet", "fleets"))
			return true
		select_fleet(fid)
		return true
	var id := overlay.army_at(p)
	if id >= 0:
		var e := CState.army(ps, id)
		var ef := int(e["f"])
		if ef == f:
			if in_set("a", id):
				if id == sel_army:
					close_side()
				else:
					select_army(id)
				return true
			if arm.size() > 1:
				_merge_set_at(id)
				return true
			select_army(id)
			return true
		if CState.friendly(ps, f, ef):
			select_army(id)
			return true
		if not arm.is_empty() and CState.at_war(ps, f, ef):
			move_group(arm, CState.cell(e), id)
			return true
		select_army(id)
		return true
	var mk := overlay.marker_at(p)
	if not mk.is_empty():
		_marker_toast(mk)
		return true
	var tsr := overlay.settlement_at(p)
	var fc := MapOverlay.cell_of_point(_map_point(p))
	if tsr >= 0:
		fc = CGrid.site(tsr)
	var tg := _target_at(p)
	var did := false
	if not fls.is_empty() and fc >= 0 and (CFleet.is_sea(fc) or CGrid.passable(fc)):
		fmove_group(fls, fc)
		did = true
	if not arm.is_empty():
		if int(tg[0]) >= 0:
			move_group(arm, int(tg[0]), int(tg[1]))
		elif not did:
			_flash("Not on land.")
	return true
