extends SceneTree
## Scripted input test: feeds synthetic touch events through Godot's input
## pipeline into the battle view and checks the orders that reach the sim.
##   godot --script res://tests/input_test.gd        (needs a window)
## (Add --write-movie to capture frames.)
## Covers: select, drag line, attack, double-tap run, pinch, cards, orders
## overlay, group buttons, "+ Add" multi-select by cards, group move keeping
## relative positions, group line-up by drag, fire / skirmish / withdraw /
## withdraw-army buttons, and the paused-order preview hand-over for each;
## artillery (battle_2000): Missile group includes batteries, battery card,
## Deploy button (pack up while paused, preview, hand-over, packing starts),
## shoot order on a tapped enemy, Run / Skirmish hidden for batteries;
## terrain (menu): the Terrain button cycles the ground for the battles, a
## battle starts on the chosen terrain, and Replay restarts the last battle
## with the same seed and ground.
## Card strip reordering: a mouse drag of a card moves it (the display
## order only: no order, no sim change, the click still selects), All
## selects in the display order, a touch long press lifts a card and a
## drag moves it, a quick touch drag moves nothing, the order survives the
## unit book and the controls page.
## Exits 0 on success, 1 on failure.

const Battle := preload("res://game/battle.gd")
const Hud := preload("res://game/hud.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const UT := preload("res://sim/unit_types.gd")
const Overlay := preload("res://game/overlay.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const MapGen := preload("res://sim/mapgen.gd")

var battle: Battle
var frame := 0
var failures := 0
var steps: Array[Callable] = []
var wait := 0

# Player units of the skirmish scenario, found by type.
var u_inf := -1     # heavy swords
var u_pike := -1
var u_arch := -1
var u_cav := -1
var u_enemy := -1


func _initialize() -> void:
	Input.use_accumulated_input = false
	# Unfocused windows can stall on vsync (Wayland); the test needs real
	# frame timing for double taps.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	battle = Battle.new()
	battle.scenario_id = "skirmish"
	battle.seed_value = 7
	root.add_child(battle)
	steps = [
		_step_find_units,
		_step_pause,
		_step_tap_select,
		_step_check_selected,
		_step_drag_line_begin,
		_step_drag_line_move,
		_step_drag_line_end,
		_step_check_line_order,
		_step_tap_enemy,
		_step_check_attack,
		_step_double_tap_ground_1,
		_step_double_tap_ground_2,
		_step_check_run_move,
		_step_pinch_begin,
		_step_pinch_move,
		_step_pinch_end,
		_step_check_pinch,
		_step_tap_card,
		_step_check_card,
		_step_tap_orders_toggle,
		_step_check_orders_on,
		_step_tap_orders_toggle,
		_step_check_orders_off,
		_step_center_camera,
		_step_paused_move_1,
		_step_paused_check_1,
		_step_paused_move_2,
		_step_paused_check_2,
		_step_unpause,
		_step_check_handover,
		# Unit book.
		_step_book_open_running,
		_step_check_book_open_running,
		_step_book_next,
		_step_check_book_next,
		_step_book_close,
		_step_check_book_closed_running,
		_step_book_open_paused,
		_step_book_close,
		_step_check_book_closed_paused,
		_step_long_press_down,
		_step_long_press_wait,
		_step_long_press_up,
		_step_check_long_press,
		_step_book_close,
		_step_tap_card_after_book,
		_step_check_tap_card_after_book,
		_step_right_click_card,
		_step_check_right_click,
		_step_book_close,
		# Milestone 2 controls.
		_step_pause_again,
		_step_group_all,
		_step_check_group_all,
		_step_group_missile,
		_step_check_group_missile,
		_step_group_inf,
		_step_check_group_inf,
		_step_add_on,
		_step_add_card,
		_step_check_add_card,
		_step_add_card,
		_step_check_remove_card,
		_step_add_off,
		_step_group_move,
		_step_check_group_move,
		_step_group_move_turn,
		_step_check_group_move_turn,
		_step_group_line,
		_step_check_group_line,
		_step_group_missile,
		_step_missile_buttons,
		_step_check_missile_pending,
		_step_shoot_enemy,
		_step_check_shoot_pending,
		_step_unpause,
		_step_check_missile_handover,
		_step_pause_again,
		_step_group_cav,
		_step_withdraw_button,
		_step_check_withdraw_pending,
		_step_withdraw_army_first,
		_step_check_withdraw_army_confirm,
		_step_withdraw_army_second,
		_step_check_withdraw_army_pending,
		_step_unpause,
		_step_check_withdraw_handover,
		_step_check_touch_targets,
		_step_menu_book_open,
		_step_check_menu_book,
		# Artillery.
		_step_art_start,
		_step_art_find,
		_step_group_missile_art,
		_step_check_group_missile_art,
		_step_art_card,
		_step_check_art_card,
		_step_art_deploy_tap,
		_step_check_art_deploy_pending,
		_step_art_shoot,
		_step_check_art_shoot_pending,
		_step_unpause,
		_step_check_art_handover,
		_step_check_art_packing,
		# Compact unit cards (26 player units).
		_step_cards_start,
		_step_cards_phone,
		_step_cards_check_phone,
		_step_cards_tap_last,
		_step_cards_check_tap,
		_step_cards_desktop,
		_step_cards_check_desktop,
		_step_cards_restore,
		# Battle controls (2026-10 additions).
		_step_bc_start,
		_step_bc_marker_click,
		_step_bc_check_marker,
		_step_bc_shift_click,
		_step_bc_check_shift,
		_step_bc_shift_card,
		_step_bc_check_shift_card,
		_step_bc_deselect,
		_step_bc_check_deselect,
		_step_bc_keys,
		_step_bc_check_keys,
		_step_bc_controls_open,
		_step_bc_controls_check,
		_step_bc_controls_closed,
		_step_bc_three_pinch,
		_step_bc_three_pinch_move,
		_step_bc_three_pinch_up,
		_step_bc_check_three_pinch,
		_step_bc_three_down,
		_step_bc_three_move,
		_step_bc_check_three_ghost,
		_step_bc_three_up,
		_step_bc_check_three_orders,
		_step_bc_three_cancel_down,
		_step_bc_three_cancel_move,
		_step_bc_three_cancel_fourth,
		_step_bc_three_cancel_up,
		_step_bc_check_three_cancel,
		_step_bc_alt_down,
		_step_bc_alt_drag,
		_step_bc_alt_wheel,
		_step_bc_check_alt_ghost,
		_step_bc_alt_up,
		_step_bc_check_alt_orders,
		_step_bc_box_down,
		_step_bc_box_drag,
		_step_bc_box_up,
		_step_bc_check_box,
		# Card strip: drag to reorder (a view-only mapping).
		_step_ro_start,
		_step_ro_mouse_up,
		_step_ro_check_mouse,
		_step_ro_click,
		_step_ro_check_click,
		_step_ro_group,
		_step_ro_touch_down,
		_step_ro_touch_wait,
		_step_ro_touch_drag,
		_step_ro_touch_up,
		_step_ro_check_touch,
		_step_ro_short_drag,
		_step_ro_check_short,
		_step_ro_pages,
		_step_ro_check_pages,
		# Gate doorway taps (defender of a walled city).
		_step_gd_start,
		_step_gd_tap_door,
		_step_gd_check_door,
		_step_gd_tap_door_marker,
		_step_gd_check_door_marker,
		_step_gd_tap_marker,
		_step_gd_check_marker,
		_step_eq_start,
		_step_eq_tap_piece,
		_step_eq_check_piece,
		_step_eq_tap_wall,
		_step_eq_check_wall,
		_step_eq_drop,
		_step_eq_check_drop,
		_step_done,
	]


func _process(_delta: float) -> bool:
	frame += 1
	if frame < 5:
		return false
	if wait > 0:
		wait -= 1
		return false
	if steps.is_empty():
		return false
	var s: Callable = steps.pop_front()
	s.call()
	wait = 2
	return false


# ------------------------------------------------------------- helpers ---

## World position -> window position (what parse_input_event expects; the
## viewport then applies the inverse stretch transform).
func _world_to_screen(w: Vector2) -> Vector2:
	return _vp_to_window(battle.get_canvas_transform() * w)


func _vp_to_window(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func _unit_screen(u: int) -> Vector2:
	var sim := battle.sim
	return _world_to_screen(Vector2(sim.u_cx[u], sim.u_cy[u]) / 1024.0 * Battle.PX_PER_M)


## Centre the camera on a world point given in sim units.
func _focus(x: int, y: int) -> void:
	battle.camera.position = Vector2(x, y) / 1024.0 * Battle.PX_PER_M
	battle.camera.force_update_scroll()


func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = pos
	e.relative = rel
	Input.parse_input_event(e)


func _tap_control(c: Control) -> void:
	_no_double_tap()
	var p := _vp_to_window(c.get_global_rect().get_center())
	_touch(0, p, true)
	_touch(0, p, false)


func _check(cond: bool, what: String) -> void:
	if cond:
		print("PASS ", what)
	else:
		printerr("FAIL ", what)
		failures += 1


func _no_double_tap() -> void:
	if is_instance_valid(battle):
		battle._last_tap_time = -10.0


func _sel_set() -> Array:
	var a: Array = []
	for u in battle.selection:
		a.append(u)
	a.sort()
	return a


# --------------------------------------------------------------- steps ---

func _step_find_units() -> void:
	var sim := battle.sim
	for u in sim.n_units:
		var ty: int = sim.u_type[u]
		if sim.u_side[u] == 0:
			if ty == UT.HEAVY and u_inf < 0:
				u_inf = u
			elif ty == UT.PIKE and u_pike < 0:
				u_pike = u
			elif ty == UT.ARCHER and u_arch < 0:
				u_arch = u
			elif ty == UT.CAVALRY and u_cav < 0:
				u_cav = u
		elif u_enemy < 0:
			u_enemy = u
	_check(u_inf >= 0 and u_pike >= 0 and u_arch >= 0 and u_cav >= 0 and u_enemy >= 0,
		"skirmish has heavy, pike, archer and cavalry units (%d %d %d %d)" % [u_inf, u_pike, u_arch, u_cav])
	var vis := 0
	var vr := battle.get_viewport_rect()
	for u in sim.n_units:
		# is_over_ui takes viewport coordinates (not window coordinates).
		var p := battle.get_canvas_transform() * (Vector2(sim.u_cx[u], sim.u_cy[u]) / 1024.0 * Battle.PX_PER_M)
		if vr.has_point(p) and not battle.hud.is_over_ui(p):
			vis += 1
		else:
			print("  unit %d off screen or under the HUD at %s" % [u, str(p)])
	_check(vis == sim.n_units, "initial camera frames every unit clear of the HUD (%d/%d)" % [vis, sim.n_units])


func _step_pause() -> void:
	battle._toggle_pause()  # keep the sim still so screen positions hold


func _step_tap_select() -> void:
	_no_double_tap()
	var p := _unit_screen(u_inf)
	_touch(0, p, true)
	_touch(0, p, false)


func _step_check_selected() -> void:
	_check(battle.selected == u_inf and battle.selection.size() == 1,
		"tap on own unit selects it (selected=%d)" % battle.selected)


var _line_a := Vector2.ZERO
var _line_b := Vector2.ZERO


func _step_drag_line_begin() -> void:
	# Draw a line left to right, 40 m long, 30 m in front of the unit.
	var sim := battle.sim
	_focus(sim.u_ax[u_inf], sim.u_ay[u_inf] - 30 * 1024)
	var w := Vector2(sim.u_ax[u_inf], sim.u_ay[u_inf] - 30 * 1024) / 1024.0 * Battle.PX_PER_M
	_line_a = _world_to_screen(w - Vector2(20, 0) * Battle.PX_PER_M)
	_line_b = _world_to_screen(w + Vector2(20, 0) * Battle.PX_PER_M)
	_touch(0, _line_a, true)


func _step_drag_line_move() -> void:
	var mid := _line_a.lerp(_line_b, 0.5)
	_drag(0, mid, mid - _line_a)
	_drag(0, _line_b, _line_b - mid)


func _step_drag_line_end() -> void:
	_check(battle.overlay.preview_on and battle.overlay.preview_ok, "drag shows formation preview")
	_touch(0, _line_b, false)
	battle.sim.step()  # apply queued order


func _step_check_line_order() -> void:
	var sim := battle.sim
	var files: int = sim.u_files[u_inf]
	_check(sim.u_order[u_inf] == BattleSim.O_MOVE, "drag line issues a move (order=%d)" % sim.u_order[u_inf])
	_check(absi(files - 36) <= 1, "line length sets frontage (files=%d, expect ~36 for 40 m)" % files)
	_check(absi(((sim.u_dface[u_inf] - 768 + 512) & 1023) - 512) <= 2, "left-to-right drag faces up (facing=%d)" % sim.u_dface[u_inf])


func _step_tap_enemy() -> void:
	_no_double_tap()
	var sim := battle.sim
	_focus(sim.u_cx[u_enemy], sim.u_cy[u_enemy])
	var p := _unit_screen(u_enemy)
	_touch(0, p, true)
	_touch(0, p, false)
	battle.sim.step()


func _step_check_attack() -> void:
	var sim := battle.sim
	_check(sim.u_order[u_inf] == BattleSim.O_ATTACK and sim.u_side[sim.u_target[u_inf]] == 1,
		"tap on enemy issues attack (order=%d target=%d)" % [sim.u_order[u_inf], sim.u_target[u_inf]])
	_check(sim.u_run[u_inf] == 0, "single tap attack walks")


var _ground := Vector2.ZERO


func _step_double_tap_ground_1() -> void:
	_no_double_tap()
	var sim := battle.sim
	var g := Vector2(sim.u_ax[u_inf] - 40 * 1024, sim.u_ay[u_inf] + 10 * 1024)
	_focus(int(g.x), int(g.y))
	_ground = _world_to_screen(g / 1024.0 * Battle.PX_PER_M)
	_touch(0, _ground, true)
	_touch(0, _ground, false)


func _step_double_tap_ground_2() -> void:
	_touch(0, _ground, true)
	_touch(0, _ground, false)
	battle.sim.step()


func _step_check_run_move() -> void:
	var sim := battle.sim
	_check(sim.u_order[u_inf] == BattleSim.O_MOVE and sim.u_run[u_inf] == 1,
		"double tap on ground moves at the run (order=%d run=%d)" % [sim.u_order[u_inf], sim.u_run[u_inf]])


var _zoom_before := 0.0
var _order_count_before := 0


func _step_pinch_begin() -> void:
	_no_double_tap()
	_zoom_before = battle.camera.zoom.x
	_order_count_before = battle.sim._order_seq
	var c := _vp_to_window(Vector2(500, 260))
	_touch(0, c - Vector2(50, 0), true)
	_touch(1, c + Vector2(50, 0), true)


func _step_pinch_move() -> void:
	var c := _vp_to_window(Vector2(500, 260))
	_drag(0, c - Vector2(100, 0), Vector2(-50, 0))
	_drag(1, c + Vector2(100, 0), Vector2(50, 0))


func _step_pinch_end() -> void:
	var c := _vp_to_window(Vector2(500, 260))
	_touch(0, c - Vector2(100, 0), false)
	_touch(1, c + Vector2(100, 0), false)


func _step_check_pinch() -> void:
	var z := battle.camera.zoom.x
	_check(z > _zoom_before * 1.5, "pinch out zooms in (%.3f -> %.3f)" % [_zoom_before, z])
	_check(battle.sim._order_seq == _order_count_before, "pinch issues no orders")


func _step_tap_card() -> void:
	_no_double_tap()
	battle._select(-1)
	_tap_control(battle.hud._cards[u_pike])


func _step_check_card() -> void:
	_check(battle.selected == u_pike, "tapping a unit card selects that unit (selected=%d)" % battle.selected)
	_check(battle.sim.u_order[u_pike] == BattleSim.O_NONE, "card tap does not leak a ground order")


var _orders_seq_before := 0


func _step_tap_orders_toggle() -> void:
	_orders_seq_before = battle.sim._order_seq
	_tap_control(battle.hud.orders_button)


func _step_check_orders_on() -> void:
	_check(Battle.show_all_orders and battle.overlay.show_all_orders, "orders toggle turns the all-orders overlay on")
	_check(battle.sim._order_seq == _orders_seq_before, "orders toggle tap does not leak a ground order")
	_check(int(battle._input_counts.get("orders_overlay_on", 0)) == 1, "orders toggle counted in telemetry input counters")


func _step_check_orders_off() -> void:
	_check(not Battle.show_all_orders and not battle.overlay.show_all_orders, "second tap turns the overlay off")
	_check(battle.sim._order_seq == _orders_seq_before, "second toggle tap does not leak an order")


# ---- orders given while paused must show immediately (no sim tick) ----

var _paused_tick := 0
var _predicted := {}


func _draw_line_order(u: int, ahead_m: int, half_m: int) -> Vector2:
	var sim := battle.sim
	var w := Vector2(sim.u_ax[u], sim.u_ay[u] - ahead_m * 1024) / 1024.0 * Battle.PX_PER_M
	var a := _world_to_screen(w - Vector2(half_m, 0) * Battle.PX_PER_M)
	var b := _world_to_screen(w + Vector2(half_m, 0) * Battle.PX_PER_M)
	_touch(0, a, true)
	_drag(0, a.lerp(b, 0.5), (b - a) * 0.5)
	_drag(0, b, (b - a) * 0.5)
	_touch(0, b, false)
	return w * (1024.0 / Battle.PX_PER_M)  # expected front centre in sim units


var _expect_c := Vector2.ZERO


func _step_center_camera() -> void:
	# Keep the gesture away from HUD panels: centre the view ahead of the unit.
	var sim := battle.sim
	_focus(sim.u_ax[u_inf], sim.u_ay[u_inf] - 60 * 1024)


func _step_paused_move_1() -> void:
	_no_double_tap()
	if not battle.paused:
		battle._toggle_pause()
	battle._select(u_inf)
	_paused_tick = battle.sim.tick
	_expect_c = _draw_line_order(u_inf, 50, 15)


func _pending_ok(u: int, expect_files: int, what: String) -> void:
	var o: Variant = battle.orders
	var ov := battle.overlay
	_check(battle.sim.tick == _paused_tick, "%s: no sim tick elapsed (tick %d)" % [what, battle.sim.tick])
	_check(o.has_pending(u), "%s: order recorded as pending in the view" % what)
	_check(battle.sim.u_order[u] != BattleSim.O_MOVE or battle.sim.u_dy[u] != ov._v(u, "dy"), "%s: sim has not applied it yet" % what)
	_check(ov._v(u, "order") == BattleSim.O_MOVE, "%s: overlay draws a move for the unit" % what)
	var dx: int = ov._v(u, "dx")
	var dy: int = ov._v(u, "dy")
	_check(absf(dx - _expect_c.x) < 1500 and absf(dy - _expect_c.y) < 1500,
		"%s: drawn destination matches the gesture (%d,%d vs %.0f,%.0f)" % [what, dx, dy, _expect_c.x, _expect_c.y])
	_check(absi(ov._v(u, "files") - expect_files) <= 1, "%s: drawn frontage %d files (expect ~%d)" % [what, ov._v(u, "files"), expect_files])


func _step_paused_check_1() -> void:
	_pending_ok(u_inf, 27, "paused move")  # 30 m line -> ~27 files


func _step_paused_move_2() -> void:
	_expect_c = _draw_line_order(u_inf, 70, 10)


func _step_paused_check_2() -> void:
	_pending_ok(u_inf, 18, "replacement paused move")  # 20 m line -> ~18 files
	_predicted = {}
	for k in ["order", "dx", "dy", "dface", "files", "run", "target"]:
		_predicted[k] = battle.overlay._v(u_inf, k)


func _step_unpause() -> void:
	_paused_tick = battle.sim.tick
	if battle.paused:
		battle._toggle_pause()


func _handover(u: int, keys: Array, what: String) -> bool:
	if battle.sim.tick <= _paused_tick:
		return false  # wait for the first tick
	var sim := battle.sim
	_check(not battle.orders.has_pending(u), "%s: after unpause the pending entry is dropped" % what)
	var same := true
	for k in keys:
		var simv: int = (sim.get("u_" + k) as PackedInt32Array)[u]
		if simv != _predicted[u][k]:
			same = false
			printerr("  mismatch %s: predicted %d sim %d" % [k, _predicted[u][k], simv])
	_check(same, "%s: sim state after applying equals what was drawn while paused (no jump)" % what)
	return true


func _step_check_handover() -> void:
	var pred := _predicted
	_predicted = {u_inf: pred}
	if not _handover(u_inf, pred.keys(), "move"):
		_predicted = pred
		steps.push_front(_step_check_handover)
		return
	_check(battle.overlay._v(u_inf, "dx") == pred["dx"], "overlay now reads the same destination from the sim")


# ---- milestone 2: groups, multi-select, missiles, withdrawal ----

func _step_pause_again() -> void:
	if not battle.paused:
		battle._toggle_pause()
	_paused_tick = battle.sim.tick


func _step_group_all() -> void:
	_tap_control(battle.hud.group_buttons["all"])


func _ready_player_units(classes: Array) -> Array:
	var a: Array = []
	var sim := battle.sim
	for u in sim.n_units:
		if sim.u_side[u] == 0 and sim.u_state[u] == BattleSim.U_READY and UT.cls(sim.u_type[u]) in classes:
			a.append(u)
	return a


func _step_check_group_all() -> void:
	var want := _ready_player_units([UT.CLS_INF, UT.CLS_PIKE, UT.CLS_MISSILE, UT.CLS_CAV])
	_check(_sel_set() == want, "All selects every ready unit (%s vs %s)" % [str(_sel_set()), str(want)])


func _step_group_missile() -> void:
	_tap_control(battle.hud.group_buttons["missile"])


func _step_check_group_missile() -> void:
	_check(_sel_set() == [u_arch], "Missile selects the archers (%s)" % str(_sel_set()))
	_check(battle.hud.fire_button.visible and battle.hud.skirm_button.visible,
		"fire and skirmish buttons shown for missile troops")


func _step_group_inf() -> void:
	_tap_control(battle.hud.group_buttons["inf"])


func _step_check_group_inf() -> void:
	var want := _ready_player_units([UT.CLS_INF, UT.CLS_PIKE])
	_check(_sel_set() == want, "Inf selects infantry and pikes (%s vs %s)" % [str(_sel_set()), str(want)])
	_check(not battle.hud.fire_button.visible, "fire button hidden without missile troops")


func _step_add_on() -> void:
	_tap_control(battle.hud.add_button)


func _step_add_card() -> void:
	_tap_control(battle.hud._cards[u_arch])


func _step_check_add_card() -> void:
	_check(battle.add_mode, "+ Add toggles add mode on")
	var want := _ready_player_units([UT.CLS_INF, UT.CLS_PIKE])
	want.append(u_arch)
	want.sort()
	_check(_sel_set() == want, "card tap in add mode adds the unit (%s)" % str(_sel_set()))


func _step_check_remove_card() -> void:
	var want := _ready_player_units([UT.CLS_INF, UT.CLS_PIKE])
	_check(_sel_set() == want, "second card tap in add mode removes it (%s)" % str(_sel_set()))


func _step_add_off() -> void:
	_tap_control(battle.hud.add_button)


var _rel_before := Vector2.ZERO
var _cent_target := Vector2.ZERO


func _pair_rel(a: int, b: int, kx: String, ky: String) -> Vector2:
	var ov := battle.overlay
	return Vector2(ov._v(b, kx) - ov._v(a, kx), ov._v(b, ky) - ov._v(a, ky))


func _step_group_move() -> void:
	_no_double_tap()
	_check(not battle.add_mode, "+ Add toggles add mode off")
	var sim := battle.sim
	_rel_before = _pair_rel(u_inf, u_pike, "ax", "ay")
	var cx := (battle.overlay._v(u_inf, "ax") + battle.overlay._v(u_pike, "ax")) / 2
	var cy := (battle.overlay._v(u_inf, "ay") + battle.overlay._v(u_pike, "ay")) / 2
	# Straight ahead of the primary unit: no rotation of the group.
	var face: int = battle.overlay._v(battle.selected, "face")
	var f := Vector2(cos(face * TAU / 1024.0), sin(face * TAU / 1024.0))
	_cent_target = Vector2(cx, cy) + f * 40.0 * 1024.0
	_focus(int(_cent_target.x), int(_cent_target.y))
	var p := _world_to_screen(_cent_target / 1024.0 * Battle.PX_PER_M)
	_touch(0, p, true)
	_touch(0, p, false)
	_check(sim.tick == _paused_tick, "group move given while paused")


func _step_check_group_move() -> void:
	var ov := battle.overlay
	_check(ov._v(u_inf, "order") == BattleSim.O_MOVE and ov._v(u_pike, "order") == BattleSim.O_MOVE,
		"tap on ground moves every selected unit")
	var rel := _pair_rel(u_inf, u_pike, "dx", "dy")
	_check(rel.distance_to(_rel_before) < 2.0 * 1024.0,
		"group move keeps the units' relative positions (%s vs %s)" % [str(rel / 1024.0), str(_rel_before / 1024.0)])
	var c := Vector2(ov._v(u_inf, "dx") + ov._v(u_pike, "dx"), ov._v(u_inf, "dy") + ov._v(u_pike, "dy")) * 0.5
	_check(c.distance_to(_cent_target) < 2.0 * 1024.0, "group centre goes where tapped")


func _step_group_move_turn() -> void:
	_no_double_tap()
	# Tap well to the right of the group: it wheels to face that way.
	var ov := battle.overlay
	var cx := (ov._v(u_inf, "ax") + ov._v(u_pike, "ax")) / 2
	var cy := (ov._v(u_inf, "ay") + ov._v(u_pike, "ay")) / 2
	_cent_target = Vector2(cx + 60 * 1024, cy)
	_focus(int(_cent_target.x), int(_cent_target.y))
	var p := _world_to_screen(_cent_target / 1024.0 * Battle.PX_PER_M)
	_touch(0, p, true)
	_touch(0, p, false)


func _step_check_group_move_turn() -> void:
	var ov := battle.overlay
	var rel := _pair_rel(u_inf, u_pike, "dx", "dy")
	_check(absf(rel.length() - _rel_before.length()) < 2.0 * 1024.0,
		"turning group move keeps the spacing (%.1f m vs %.1f m)" % [rel.length() / 1024.0, _rel_before.length() / 1024.0])
	var df: int = ov._v(u_inf, "dface")
	_check(absi(((df - 0 + 512) & 1023) - 512) < 40, "group faces its direction of travel (dface %d)" % df)


func _step_group_line() -> void:
	_no_double_tap()
	var sim := battle.sim
	# A 70 m line left to right, 50 m ahead of the group.
	var cx := (sim.u_ax[u_inf] + sim.u_ax[u_pike]) / 2
	var cy := mini(sim.u_ay[u_inf], sim.u_ay[u_pike]) - 50 * 1024
	_focus(cx, cy)
	var w := Vector2(cx, cy) / 1024.0 * Battle.PX_PER_M
	var a := _world_to_screen(w - Vector2(35, 0) * Battle.PX_PER_M)
	var b := _world_to_screen(w + Vector2(35, 0) * Battle.PX_PER_M)
	_touch(0, a, true)
	_drag(0, a.lerp(b, 0.5), (b - a) * 0.5)
	_drag(0, b, (b - a) * 0.5)
	_touch(0, b, false)


func _step_check_group_line() -> void:
	var ov := battle.overlay
	var sim := battle.sim
	var units := [u_inf, u_pike]
	units.sort_custom(func(a: int, b: int) -> bool: return ov._v(a, "dx") < ov._v(b, "dx"))
	var l: int = units[0]
	var r: int = units[1]
	var lw := (ov._v(l, "files") - 1) * UT.stat(sim.u_type[l], "file_sp") / 2
	var rw := (ov._v(r, "files") - 1) * UT.stat(sim.u_type[r], "file_sp") / 2
	var gap := (ov._v(r, "dx") - rw) - (ov._v(l, "dx") + lw)
	_check(absi(ov._v(l, "dy") - ov._v(r, "dy")) < 1024, "drag lines the group up on one front line")
	_check(gap > 0 and gap < 5 * 1024, "units side by side without overlap (gap %.1f m)" % (gap / 1024.0))
	var total := (ov._v(r, "dx") + rw) - (ov._v(l, "dx") - lw)
	_check(absi(total - 70 * 1024) < 6 * 1024, "the group fills the drawn line (%.1f m of 70)" % (total / 1024.0))
	for u in units:
		_check(absi(((ov._v(u, "dface") - 768 + 512) & 1023) - 512) <= 2, "lined-up unit %d faces up" % u)


func _step_missile_buttons() -> void:
	_paused_tick = battle.sim.tick
	_check(battle.sim.u_fire[u_arch] == 1, "archers start with fire at will")
	_tap_control(battle.hud.fire_button)
	_tap_control(battle.hud.skirm_button)


func _step_check_missile_pending() -> void:
	var ov := battle.overlay
	_check(ov._v(u_arch, "fire") == 0 and battle.sim.u_fire[u_arch] == 1,
		"fire button: hold fire shown at once, sim unchanged until the tick")
	_check(battle.hud.fire_button.text.ends_with("hold"), "fire button reads hold (%s)" % battle.hud.fire_button.text)
	_check(ov._v(u_arch, "skirm") != battle.sim.u_skirm[u_arch], "skirmish button toggles skirmish mode (pending)")


func _step_shoot_enemy() -> void:
	_no_double_tap()
	var sim := battle.sim
	_focus(sim.u_cx[u_enemy], sim.u_cy[u_enemy])
	var p := _unit_screen(u_enemy)
	_touch(0, p, true)
	_touch(0, p, false)


func _step_check_shoot_pending() -> void:
	var ov := battle.overlay
	_check(ov._v(u_arch, "order") == BattleSim.O_ATTACK and ov._v(u_arch, "target") == u_enemy,
		"tapping an enemy orders the archers to shoot it")
	_predicted = {u_arch: {}}
	for k in ["order", "target", "fire", "skirm", "run"]:
		_predicted[u_arch][k] = ov._v(u_arch, k)


func _step_check_missile_handover() -> void:
	if not _handover(u_arch, ["order", "target", "fire", "skirm", "run"], "fire/skirmish/shoot"):
		steps.push_front(_step_check_missile_handover)


func _step_group_cav() -> void:
	_tap_control(battle.hud.group_buttons["cav"])


func _step_withdraw_button() -> void:
	_check(_sel_set() == [u_cav], "Cav selects the cavalry (%s)" % str(_sel_set()))
	_paused_tick = battle.sim.tick
	_tap_control(battle.hud.withdraw_button)


func _step_check_withdraw_pending() -> void:
	var ov := battle.overlay
	_check(ov._v(u_cav, "order") == BattleSim.O_WITHDRAW and battle.sim.u_order[u_cav] != BattleSim.O_WITHDRAW,
		"withdraw button: withdrawal drawn at once while paused")
	_check(ov._v(u_cav, "dy") == battle.sim.field_h, "withdrawal heads for the own (bottom) map edge")


var _seq_before_army := 0


func _step_withdraw_army_first() -> void:
	_seq_before_army = battle.sim._order_seq
	_tap_control(battle.hud.withdraw_all_button)


func _step_check_withdraw_army_confirm() -> void:
	_check(battle.sim._order_seq == _seq_before_army, "first tap on Withdraw army only asks to confirm")
	_check(battle.hud.withdraw_all_button.text.begins_with("Tap"), "button asks for confirmation (%s)" % battle.hud.withdraw_all_button.text)


func _step_withdraw_army_second() -> void:
	_tap_control(battle.hud.withdraw_all_button)


func _step_check_withdraw_army_pending() -> void:
	var ov := battle.overlay
	var all := true
	_predicted = {}
	for u in _ready_player_units([UT.CLS_INF, UT.CLS_PIKE, UT.CLS_MISSILE, UT.CLS_CAV]):
		if ov._v(u, "order") != BattleSim.O_WITHDRAW:
			all = false
		_predicted[u] = {}
		for k in ["order", "target", "run", "dx", "dy", "dface"]:
			_predicted[u][k] = ov._v(u, k)
	_check(all, "second tap withdraws the whole army (drawn while paused)")


func _step_check_withdraw_handover() -> void:
	if battle.sim.tick <= _paused_tick:
		steps.push_front(_step_check_withdraw_handover)
		return
	for u in _predicted:
		_handover(u, ["order", "target", "run", "dx", "dy", "dface"], "withdraw unit %d" % u)


func _step_check_touch_targets() -> void:
	var small := []
	var hud := battle.hud
	var buttons: Array = [hud.run_button, hud.halt_button, hud.fire_button, hud.skirm_button,
		hud.withdraw_button, hud.withdraw_all_button, hud.add_button]
	for k in hud.group_buttons:
		buttons.append(hud.group_buttons[k])
	# Logical px; on a phone one is 0.88 CSS px (game/ui_scale.gd), so 40 is
	# ~35 CSS px, ~7 mm.
	for b in buttons:
		var sz: Vector2 = (b as Control).get_combined_minimum_size()
		if sz.y < 40 or sz.x < 50:
			small.append((b as Button).text)
	_check(small.is_empty(), "buttons are at least 50x40 logical px (%s)" % str(small))
	var ct: String = hud.card_text(u_arch)
	_check(ct.find("ammo") >= 0, "missile unit card shows ammunition (%s)" % ct.replace("\n", " | "))


# ---- unit book ----

var _book_seq := 0
var _book_sel: Array = []
var _lp_t0 := 0
var _lp_pos := Vector2.ZERO


func _step_book_open_running() -> void:
	_check(not battle.paused, "battle running before opening the book")
	_tap_control(battle.hud.book_button)


func _step_check_book_open_running() -> void:
	_check(battle.hud.book.visible, "Units button opens the unit book")
	_check(battle.paused, "opening the book pauses the battle")


func _step_book_next() -> void:
	_book_seq = battle.hud.book.current
	_tap_control(battle.hud.book.next_button)


func _step_check_book_next() -> void:
	var b = battle.hud.book
	_check(b.current == (_book_seq + 1) % (UT.count() + 2) and b.entry.unit_type == b.current,
		"Next shows the next unit type (%d -> %d)" % [_book_seq, b.current])
	# The last pages are Terrain and Settlements: Prev from the first page
	# wraps to Settlements, and once more to Terrain.
	steps.push_front(_step_check_book_terrain)
	b.show_type(0)
	_tap_control(b.prev_button)


func _step_check_book_terrain() -> void:
	var b = battle.hud.book
	_check(b.current == UT.count() + 1 and b.terrain_page.visible and not b.entry.visible
		and b.terrain_text.text.find("SETTLEMENTS") >= 0 and b.terrain_text.text.find("Gates") >= 0,
		"Prev from the first page shows the Settlements and sieges page")
	_tap_control(b.prev_button)
	_check(b.current == UT.count() and b.terrain_page.visible
		and b.terrain_text.text.find("contour") >= 0 and b.terrain_text.text.find("+0.8%") >= 0
		and b.terrain_text.text.find("WOODS") >= 0,
		"Prev again shows the Terrain page with the rules, numbers and woods")
	b.show_type(1)


func _step_book_close() -> void:
	_tap_control(battle.hud.book.close_button)


func _step_check_book_closed_running() -> void:
	_check(not battle.hud.book.visible, "Close hides the book")
	_check(not battle.paused, "closing restores the running state")


func _step_book_open_paused() -> void:
	battle._toggle_pause()
	_tap_control(battle.hud.book_button)


func _step_check_book_closed_paused() -> void:
	_check(not battle.hud.book.visible and battle.paused, "a battle paused before the book stays paused after it")
	battle._toggle_pause()


func _step_long_press_down() -> void:
	_no_double_tap()
	_book_seq = battle.sim._order_seq
	_book_sel = _sel_set()
	var card: Control = battle.hud._cards[u_pike]
	_lp_pos = _vp_to_window(card.get_global_rect().get_center())
	_lp_t0 = Time.get_ticks_msec()
	_touch(0, _lp_pos, true)


func _step_long_press_wait() -> void:
	if Time.get_ticks_msec() - _lp_t0 < 700:
		steps.push_front(_step_long_press_wait)


func _step_long_press_up() -> void:
	_touch(0, _lp_pos, false)


func _step_check_long_press() -> void:
	var b = battle.hud.book
	_check(b.visible and b.current == battle.sim.u_type[u_pike],
		"long press on a card opens that unit type's page (page %d)" % b.current)
	_check(battle.sim._order_seq == _book_seq, "long press issues no order")
	_check(_sel_set() == _book_sel, "long press does not change the selection (%s, was %s)" % [str(_sel_set()), str(_book_sel)])
	_check(int(battle._input_counts.get("book_open_card", 0)) >= 1, "book opens counted for telemetry")


func _step_tap_card_after_book() -> void:
	battle._select(-1)
	_tap_control(battle.hud._cards[u_pike])


func _step_check_tap_card_after_book() -> void:
	_check(battle.selected == u_pike, "a normal tap on the card still selects (selected=%d)" % battle.selected)
	_check(not battle.hud.book.visible, "a normal tap does not open the book")


func _step_right_click_card() -> void:
	_book_seq = battle.sim._order_seq
	var card: Control = battle.hud._cards[u_arch]
	var p := _vp_to_window(card.get_global_rect().get_center())
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_RIGHT
		e.pressed = pressed
		e.position = p
		e.global_position = p
		Input.parse_input_event(e)


func _step_check_right_click() -> void:
	var b = battle.hud.book
	_check(b.visible and b.current == battle.sim.u_type[u_arch], "right click on a card opens its page")
	_check(battle.sim._order_seq == _book_seq and battle.selected == u_pike, "right click issues no order and keeps the selection")


var _menu: Control = null


func _step_menu_book_open() -> void:
	battle.queue_free()
	_menu = (load("res://game/main.gd") as GDScript).new()
	root.add_child(_menu)
	steps.push_front(_step_menu_book_tap)


func _step_menu_book_tap() -> void:
	for b in _menu.find_children("*", "Button", true, false):
		if (b as Button).text == "Unit book":
			_tap_control(b)
			return
	_check(false, "menu has a Unit book button")


func _step_check_menu_book() -> void:
	var book = _menu.book
	_check(book.visible, "Unit book button on the menu opens the book")
	_check(book.entry.unit_type >= 0, "the book shows a page")
	steps.push_front(_step_check_menu_book_closed)
	_tap_control(book.close_button)


func _step_check_menu_book_closed() -> void:
	_check(not _menu.book.visible, "Close hides the menu's book")
	steps.push_front(_step_terrain_cycle_check)
	steps.push_front(_step_terrain_cycle)
	steps.push_front(_step_menu_sandbox_check)
	steps.push_front(_step_menu_sandbox)
	steps.push_front(_step_menu_controls_check)
	steps.push_front(_step_menu_controls)


func _step_menu_controls() -> void:
	for b in _menu.find_children("home_controls", "Button", true, false):
		_tap_control(b)
		return
	_check(false, "menu has a Controls button")


func _step_menu_controls_check() -> void:
	_check(_menu.controls.visible, "Controls opens from the main menu")
	_check(_menu.controls.find_children("*", "Label", true, false).size() > 60, "the Controls page lists the bindings")
	_tap_control(_menu.controls.close_button)


func _step_menu_sandbox() -> void:
	_check(not _menu.controls.visible, "Close hides the Controls page")
	for b in _menu.find_children("home_sandbox", "Button", true, false):
		_tap_control(b)
		return


func _step_menu_sandbox_check() -> void:
	_check(_menu.page == "sandbox", "Battle sandbox opens the sandbox page")


# ---- terrain (menu) ----

const Terrain := preload("res://sim/terrain.gd")
var _terrain_taps := 0
var _replay_hash := 0
var _replay_seed := -1


func _menu_button(prefix: String) -> Button:
	for b in _menu.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(prefix):
			return b
	return null


func _step_terrain_cycle() -> void:
	var b := _menu_button("Terrain:")
	_check(b != null and b.text == "Terrain: random", "menu has a Terrain button, random by default (%s)" % (b.text if b else "none"))
	_check(_menu_button("Replay") != null and _menu_button("Replay").disabled, "Replay is disabled before any battle")
	_tap_control(b)


func _step_terrain_cycle_check() -> void:
	_terrain_taps += 1
	var b := _menu_button("Terrain:")
	var want: Array[String] = ["", "Terrain: flat", "Terrain: rolling", "Terrain: ridge"]
	_check(b.text == want[_terrain_taps], "Terrain button cycles (%s, want %s)" % [b.text, want[_terrain_taps]])
	if _terrain_taps < 3:
		steps.push_front(_step_terrain_cycle_check)
		_tap_control(b)
	else:
		steps.push_front(_step_terrain_battle_check)
		_tap_control(_menu_button("Small skirmish"))


func _step_terrain_battle_check() -> void:
	var b = _menu._battle
	_check(b != null, "a battle started from the menu")
	if b == null:
		return
	_check(b.sim.ter_on == 1 and int(b.sim.ter_info["kind"]) == Terrain.K_RIDGE,
		"the battle has the chosen terrain (ridge): on %d kind %s" % [b.sim.ter_on, str(b.sim.ter_info.get("kind"))])
	_replay_hash = b.sim.ter_hash
	_replay_seed = b.seed_value
	steps.push_front(_step_terrain_replay)
	b.hud.menu_pressed.emit()


func _step_terrain_replay() -> void:
	_check(_menu._battle == null and _menu._menu.visible, "Menu returns to the start screen")
	var r := _menu_button("Replay")
	_check(r != null and not r.disabled and r.text.find(str(_replay_seed)) >= 0,
		"Replay shows the last seed (%s)" % (r.text if r else "none"))
	steps.push_front(_step_terrain_replay_check)
	_tap_control(r)


func _step_terrain_replay_check() -> void:
	var b = _menu._battle
	_check(b != null and b.seed_value == _replay_seed and b.sim.ter_hash == _replay_hash
		and b.scenario_id == "skirmish", "Replay restarts the same battle with the same seed and ground")
	if b != null:
		b.hud.menu_pressed.emit()


# ---- artillery ----

var u_bolt := -1
var u_stone := -1
var u_art_enemy := -1


func _step_art_start() -> void:
	if is_instance_valid(_menu):
		_menu.queue_free()
	battle = Battle.new()
	battle.scenario_id = "battle_2000"
	battle.seed_value = 7
	root.add_child(battle)


func _step_art_find() -> void:
	var sim := battle.sim
	for u in sim.n_units:
		if sim.u_side[u] == 0 and sim.u_type[u] == UT.BOLT:
			u_bolt = u
		elif sim.u_side[u] == 0 and sim.u_type[u] == UT.STONE:
			u_stone = u
		elif sim.u_side[u] == 1 and sim.u_type[u] == UT.HEAVY and u_art_enemy < 0:
			u_art_enemy = u
	_check(u_bolt >= 0 and u_stone >= 0 and u_art_enemy >= 0,
		"battle_2000 has player bolt and stone throwers (%d %d)" % [u_bolt, u_stone])
	if not battle.paused:
		battle._toggle_pause()
	_paused_tick = battle.sim.tick


func _step_group_missile_art() -> void:
	_tap_control(battle.hud.group_buttons["missile"])


func _step_check_group_missile_art() -> void:
	var want := _ready_player_units([UT.CLS_MISSILE, UT.CLS_ART])
	_check(_sel_set() == want, "Missile selects missile troops and artillery (%s vs %s)" % [str(_sel_set()), str(want)])
	_check(battle.hud.deploy_button.visible, "Deploy button shown when batteries are selected")
	_check(battle.hud.skirm_button.visible, "Skirmish still shown for the archers in the group")


func _step_art_card() -> void:
	_no_double_tap()
	battle._select(-1)
	_tap_control(battle.hud._cards[u_bolt])


func _step_check_art_card() -> void:
	var hud := battle.hud
	_check(battle.selected == u_bolt and battle.selection.size() == 1, "tapping the battery card selects it")
	_check(hud.deploy_button.visible and hud.deploy_button.text == "Deploy: on",
		"Deploy button reads on for a set-up battery (%s)" % hud.deploy_button.text)
	_check(hud.fire_button.visible and not hud.skirm_button.visible and not hud.run_button.visible,
		"battery alone: Fire shown, Skirmish and Run hidden")
	var ct: String = hud.card_text(u_bolt)
	_check(ct.find("eng 4/4") >= 0 and ct.find("shots") >= 0 and ct.find("Ready") >= 0,
		"battery card shows engines, shots and Ready (%s)" % ct.replace("\n", " | "))
	var sz: Vector2 = hud.deploy_button.get_combined_minimum_size()
	_check(sz.x >= 50 and sz.y >= 40, "Deploy button is a usable touch target (%s)" % str(sz))


func _step_art_deploy_tap() -> void:
	_paused_tick = battle.sim.tick
	_tap_control(battle.hud.deploy_button)


func _step_check_art_deploy_pending() -> void:
	var ov := battle.overlay
	_check(battle.sim.tick == _paused_tick, "deploy toggled while paused (no tick)")
	_check(ov._v(u_bolt, "deploy") == 0 and battle.sim.u_deploy[u_bolt] == 1,
		"Deploy button: pack up shown at once, sim unchanged until the tick")
	_check(battle.hud.deploy_button.text == "Deploy: off", "button now reads off (%s)" % battle.hud.deploy_button.text)


func _step_art_shoot() -> void:
	_no_double_tap()
	var sim := battle.sim
	_focus(sim.u_cx[u_art_enemy], sim.u_cy[u_art_enemy])
	# Its marker, not its body: in battle_2000's second line the marker of
	# the unit behind floats over this unit's centre and markers pick first.
	var r := maxf(Overlay.MARKER_MIN_R, Overlay.MARKER_SCREEN_R / battle.camera.zoom.x)
	var p := _world_to_screen(Vector2(sim.u_cx[u_art_enemy], sim.u_cy[u_art_enemy]) / 1024.0 * Battle.PX_PER_M
		+ Vector2(0, -r * 2.2))
	_touch(0, p, true)
	_touch(0, p, false)


func _step_check_art_shoot_pending() -> void:
	var ov := battle.overlay
	_check(ov._v(u_bolt, "order") == BattleSim.O_ATTACK and ov._v(u_bolt, "target") == u_art_enemy,
		"tapping an enemy orders the battery to shoot it (pending; order %d target %d, wanted %d)" % [
			ov._v(u_bolt, "order"), ov._v(u_bolt, "target"), u_art_enemy])
	_check(ov._v(u_bolt, "run") == 0, "a battery never runs")
	_predicted = {u_bolt: {}}
	for k in ["order", "target", "deploy", "run", "fire"]:
		_predicted[u_bolt][k] = ov._v(u_bolt, k)


var _depl_before := -1


func _step_check_art_handover() -> void:
	if not _handover(u_bolt, ["order", "target", "deploy", "run", "fire"], "battery deploy/shoot"):
		steps.push_front(_step_check_art_handover)
		return
	_depl_before = battle.sim.u_depl[u_bolt]
	_paused_tick = battle.sim.tick


func _step_check_art_packing() -> void:
	var sim := battle.sim
	if sim.tick < _paused_tick + 3:
		steps.push_front(_step_check_art_packing)
		return
	_check(sim.u_depl[u_bolt] < _depl_before, "the battery is packing up (%d -> %d)" % [_depl_before, sim.u_depl[u_bolt]])


# ---- compact cards ----

var _cards_win_size := Vector2i.ZERO


func _step_cards_start() -> void:
	battle.queue_free()
	battle = Battle.new()
	battle.scenario_id = "battle_4000"
	battle.seed_value = 7
	root.add_child(battle)
	_cards_win_size = root.content_scale_size


## The phone's logical size: 780 x 360 CSS px at 0.88 CSS px per logical px.
func _step_cards_phone() -> void:
	root.content_scale_size = Vector2i(886, 409)
	if not battle.paused:
		battle._toggle_pause()


func _cards_on_screen() -> Array:
	var vis := root.get_visible_rect()
	var rows := {}
	var off := 0
	for u in battle.hud._cards:
		var r: Rect2 = (battle.hud._cards[u] as Control).get_global_rect()
		rows[int(r.position.y)] = true
		if not vis.encloses(r):
			off += 1
	return [rows.size(), off, battle.hud._cards.size()]


func _step_cards_check_phone() -> void:
	var c := _cards_on_screen()
	_check(c[2] >= 20 and c[1] == 0 and c[0] <= 2,
		"phone: all %d cards on screen, no scrolling, in %d rows (%d off screen)" % [c[2], c[0], c[1]])
	var bottom: float = battle.hud.bottom_height()
	_check(bottom <= 409 * 0.36, "phone: the bottom HUD takes %.0f of 409 logical px" % bottom)


var _last_card := -1


func _step_cards_tap_last() -> void:
	for u in battle.hud._cards:
		_last_card = u
	_tap_control(battle.hud._cards[_last_card])


func _step_cards_check_tap() -> void:
	_check(battle.selected == _last_card and battle.hud._faces[_last_card].selected,
		"tapping the last (narrow) card selects that unit (%d, selected %d)" % [_last_card, battle.selected])


func _step_cards_desktop() -> void:
	root.content_scale_size = Vector2i(2341, 1317)


func _step_cards_check_desktop() -> void:
	var c := _cards_on_screen()
	_check(c[1] == 0 and c[0] == 1, "desktop: all %d cards in %d row" % [c[2], c[0]])
	_check(not battle.hud._faces[_last_card].narrow, "desktop cards show names")


func _step_cards_restore() -> void:
	root.content_scale_size = _cards_win_size


# ---- battle controls ----

var _bc: Array[int] = []   # player units of the skirmish
var _bc_pending0 := 0
var _bc_paused0 := false
var _three := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]


func _mouse(pos: Vector2, pressed: bool, mods: Dictionary = {}, btn: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.position = _vp_to_window(pos)
	e.global_position = e.position
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and btn == MOUSE_BUTTON_LEFT else 0
	e.shift_pressed = mods.get("shift", false)
	e.alt_pressed = mods.get("alt", false)
	Input.parse_input_event(e)


func _mouse_move(pos: Vector2, rel: Vector2, mods: Dictionary = {}) -> void:
	var e := InputEventMouseMotion.new()
	e.position = _vp_to_window(pos)
	e.global_position = e.position
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.alt_pressed = mods.get("alt", false)
	Input.parse_input_event(e)


func _key(code: Key, mods: Dictionary = {}) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.ctrl_pressed = mods.get("ctrl", false)
		Input.parse_input_event(e)


func _marker_screen(u: int) -> Vector2:
	var sim := battle.sim
	var r := maxf(Overlay.MARKER_MIN_R, Overlay.MARKER_SCREEN_R / battle.camera.zoom.x)
	var w := Vector2(sim.u_cx[u], sim.u_cy[u]) / 1024.0 * Battle.PX_PER_M + Vector2(0, -r * 2.2)
	return battle.get_canvas_transform() * w


func _pending_moves() -> int:
	var n := 0
	for o in battle.sim.pending_orders:
		if int(o["type"]) == BattleSim.ORDER_MOVE:
			n += 1
	return n


func _step_bc_start() -> void:
	if is_instance_valid(battle):
		battle.queue_free()
	battle = Battle.new()
	battle.scenario_id = "battle_2000"
	battle.seed_value = 11
	root.add_child(battle)


func _step_bc_marker_click() -> void:
	battle._toggle_pause()
	_bc.clear()
	for u in battle.sim.n_units:
		if battle.sim.u_side[u] == 0 and battle.sim.u_cls[u] == UT.CLS_INF:
			_bc.append(u)
	battle.camera.zoom = Vector2(0.35, 0.35)
	_focus(battle.sim.u_cx[_bc[0]], battle.sim.u_cy[_bc[0]])
	battle._select(-1)
	_no_double_tap()
	var p := _marker_screen(_bc[0])
	_mouse(p, true)
	_mouse(p, false)


func _step_bc_check_marker() -> void:
	_check(battle.selection == [_bc[0]], "clicking a unit's symbol marker selects it (%s)" % str(battle.selection))


func _step_bc_shift_click() -> void:
	_no_double_tap()
	var p := _marker_screen(_bc[1])
	_mouse(p, true, {"shift": true})
	_mouse(p, false, {"shift": true})


func _step_bc_check_shift() -> void:
	_check(battle.selection.has(_bc[0]) and battle.selection.has(_bc[1]), "Shift+click adds a unit on the field (%s)" % str(battle.selection))


func _step_bc_shift_card() -> void:
	_no_double_tap()
	var card: Control = battle.hud._cards[_bc[2]]
	var p := card.get_global_rect().get_center()
	_mouse(p, true, {"shift": true})
	_mouse(p, false, {"shift": true})


func _step_bc_check_shift_card() -> void:
	_check(battle.selection.size() == 3 and battle.selection.has(_bc[2]), "Shift+click on a card adds it (%s)" % str(battle.selection))


func _step_bc_deselect() -> void:
	_tap_control(battle.hud.deselect_button)


func _step_bc_check_deselect() -> void:
	_check(battle.selection.is_empty(), "the None (deselect) button clears the selection")


func _step_bc_keys() -> void:
	_bc_paused0 = battle.paused
	_key(KEY_SPACE)
	_key(KEY_2)


func _step_bc_check_keys() -> void:
	_check(battle.paused != _bc_paused0, "Space toggles pause")
	_check(battle.selection.size() >= 3, "key 2 selects the infantry (%d)" % battle.selection.size())
	_key(KEY_SPACE)
	_key(KEY_ESCAPE)


func _step_bc_controls_open() -> void:
	_check(battle.selection.is_empty(), "Escape deselects")
	battle._set_paused(false)
	_tap_control(battle.hud.controls_button)


func _step_bc_controls_check() -> void:
	_check(battle.hud.controls.visible and battle.paused, "Keys opens the controls page and pauses")
	_tap_control(battle.hud.controls.close_button)


func _step_bc_controls_closed() -> void:
	_check(not battle.hud.controls.visible and not battle.paused, "closing the controls page restores the pause state")
	battle._set_paused(true)
	battle._select_group("all")
	_bc_pending0 = _pending_moves()


func _three_at(c: Vector2) -> void:
	_three = [c + Vector2(-60, 0), c + Vector2(60, 0), c + Vector2(0, 50)]


func _step_bc_three_pinch() -> void:
	# Three fingers down then barely moving: nothing happens.
	_three_at(get_root().get_visible_rect().size * 0.5)
	for i in 3:
		_touch(i, _vp_to_window(_three[i]), true)


func _step_bc_three_pinch_move() -> void:
	for i in 3:
		_drag(i, _vp_to_window(_three[i] + Vector2(6, 0)), Vector2(6, 0))


func _step_bc_three_pinch_up() -> void:
	_check(battle.overlay.ghosts.is_empty(), "a tiny three-finger movement shows no ghost")
	for i in 3:
		_touch(i, _vp_to_window(_three[i] + Vector2(6, 0)), false)


func _step_bc_check_three_pinch() -> void:
	_check(_pending_moves() == _bc_pending0, "and issues no orders")


func _step_bc_three_down() -> void:
	_three_at(get_root().get_visible_rect().size * 0.5)
	for i in 3:
		_touch(i, _vp_to_window(_three[i]), true)


func _step_bc_three_move() -> void:
	# Move up 80 px and twist about 20 degrees, in a few steps.
	var c: Vector2 = (_three[0] + _three[1] + _three[2]) / 3.0
	for k in range(1, 5):
		for i in 3:
			var p: Vector2 = c + ((_three[i] as Vector2) - c).rotated(deg_to_rad(5.0 * k)) + Vector2(0, -20.0 * k)
			_drag(i, _vp_to_window(p), Vector2.ZERO)


func _step_bc_check_three_ghost() -> void:
	_check(battle.overlay.ghosts.size() == battle.selection.size(), "three-finger drag shows a ghost per unit (%d)" % battle.overlay.ghosts.size())
	_check(battle.overlay.ghost_hint.contains("turn"), "the twist turns the group (%s)" % battle.overlay.ghost_hint)


func _step_bc_three_up() -> void:
	_touch(2, _vp_to_window(_three[2]), false)
	_touch(1, _vp_to_window(_three[1]), false)
	_touch(0, _vp_to_window(_three[0]), false)


func _step_bc_check_three_orders() -> void:
	var n := _pending_moves() - _bc_pending0
	_check(n == battle.selection.size(), "lifting a finger places the group: %d move orders" % n)
	# Each unit turned by the same angle.
	var ok := true
	var turn := -1
	for o in battle.sim.pending_orders:
		if int(o["type"]) != BattleSim.ORDER_MOVE:
			continue
		var u: int = o["unit"]
		var t: int = (int(o["facing"]) - battle.sim.u_face[u]) & 1023
		if turn < 0:
			turn = t
		elif t != turn:
			ok = false
	_check(ok and turn > 20 and turn < 120, "every unit turned by the same angle (%d/1024)" % turn)
	_bc_pending0 = _pending_moves()


func _step_bc_three_cancel_down() -> void:
	_step_bc_three_down()


func _step_bc_three_cancel_move() -> void:
	for i in 3:
		_drag(i, _vp_to_window(_three[i] + Vector2(0, -60)), Vector2(0, -60))


func _step_bc_three_cancel_fourth() -> void:
	_check(not battle.overlay.ghosts.is_empty(), "ghost before the cancel")
	_touch(3, _vp_to_window(_three[0] + Vector2(0, 120)), true)


func _step_bc_three_cancel_up() -> void:
	_check(battle.overlay.ghosts.is_empty(), "a fourth finger cancels the group move")
	for i in 4:
		_touch(i, _vp_to_window(_three[mini(i, 2)]), false)


func _step_bc_check_three_cancel() -> void:
	_check(_pending_moves() == _bc_pending0, "the cancelled move issues no orders")


func _step_bc_alt_down() -> void:
	_no_double_tap()
	var c := get_root().get_visible_rect().size * 0.5
	_three[0] = c
	_mouse(c, true, {"alt": true})


func _step_bc_alt_drag() -> void:
	for k in range(1, 6):
		_mouse_move(_three[0] + Vector2(12 * k, 0), Vector2(12, 0), {"alt": true})


func _step_bc_alt_wheel() -> void:
	_mouse(_three[0] + Vector2(60, 0), true, {}, MOUSE_BUTTON_WHEEL_DOWN)
	_key(KEY_E)


func _step_bc_check_alt_ghost() -> void:
	_check(not battle.overlay.ghosts.is_empty() and battle.overlay.ghost_hint.contains("+30"),
		"Alt+drag shows the ghost; wheel and E turn it 15 degrees each (%s)" % battle.overlay.ghost_hint)


func _step_bc_alt_up() -> void:
	_mouse(_three[0] + Vector2(60, 0), false, {"alt": true})


func _step_bc_check_alt_orders() -> void:
	var n := _pending_moves() - _bc_pending0
	_check(n == battle.selection.size(), "releasing the Alt+drag issues the moves (%d)" % n)
	battle._select(-1)


func _step_bc_box_down() -> void:
	_no_double_tap()
	# A box around the first two infantry units, starting on empty ground.
	var a := _unit_screen(_bc[0])
	var b := _unit_screen(_bc[1])
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(10, 60)
	_three[0] = lo
	_three[1] = Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(10, 10)
	_mouse(_root_from_window(lo), true)


func _root_from_window(p: Vector2) -> Vector2:
	return root.get_final_transform().affine_inverse() * p


func _step_bc_box_drag() -> void:
	var a := _root_from_window(_three[0])
	var b := _root_from_window(_three[1])
	for k in range(1, 6):
		_mouse_move(a.lerp(b, k / 5.0), (b - a) / 5.0)


func _step_bc_box_up() -> void:
	_mouse(_root_from_window(_three[1]), false)


func _step_bc_check_box() -> void:
	_check(battle.selection.has(_bc[0]) and battle.selection.has(_bc[1]), "a mouse drag box selects the units inside (%s)" % str(battle.selection))


# ---- card strip: drag to reorder ----

var _ro0: Array[int] = []
var _ro_hash := 0
var _ro_seq := 0
var _ro_t0 := 0
var _ro_p := Vector2.ZERO
var _ro_sel: Array = []


func _ro_card(i: int) -> Rect2:
	return (battle.hud._cards[battle.hud.display_order()[i]] as Control).get_global_rect()


func _ro_box_order() -> Array:
	var out: Array = []
	for c in battle.hud.cards_box.get_children():
		out.append(battle.hud._cards.find_key(c))
	return out


func _step_ro_start() -> void:
	if not battle.paused:
		battle._toggle_pause()
	battle._select(-1)
	_no_double_tap()
	_ro0 = battle.hud.display_order()
	_ro_hash = battle.sim.state_hash()
	_ro_seq = battle.sim._order_seq
	_check(_ro0.size() >= 4, "enough cards to reorder (%d)" % _ro0.size())
	# Desktop: press on the first card and drag it past the third.
	var a := _ro_card(0).get_center()
	var r := _ro_card(2)
	_ro_p = r.get_center() + Vector2(r.size.x * 0.3, 0)
	_mouse(a, true)
	for k in range(1, 6):
		_mouse_move(a.lerp(_ro_p, k / 5.0), (_ro_p - a) / 5.0)


func _step_ro_mouse_up() -> void:
	_check(battle.hud._reorder.is_active(), "a mouse drag lifts the card")
	_mouse(_ro_p, false)


func _step_ro_check_mouse() -> void:
	var want: Array = [_ro0[1], _ro0[2], _ro0[0]]
	want.append_array(_ro0.slice(3))
	_check(battle.hud.display_order() == want, "a mouse drag moves the card after the third (%s -> %s)" % [str(_ro0), str(battle.hud.display_order())])
	_check(_ro_box_order() == want, "the strip shows the new order")
	_check(battle.selection.is_empty() and not battle.hud.book.visible, "the drag selects nothing and opens no page")
	_check(battle.sim.state_hash() == _ro_hash and battle.sim._order_seq == _ro_seq, "view only: no order, the sim state unchanged")
	_check(int(battle._input_counts.get("card_reorder", 0)) == 1, "counted for telemetry")


func _step_ro_click() -> void:
	_no_double_tap()
	var p := _ro_card(2).get_center()
	_mouse(p, true)
	_mouse(p, false)


func _step_ro_check_click() -> void:
	_check(battle.selection == [_ro0[0]], "a click on the moved card still selects its unit (%s)" % str(battle.selection))
	_tap_control(battle.hud.group_buttons["all"])


func _step_ro_group() -> void:
	var want: Array = []
	for u in battle.hud.display_order():
		if battle.sim.u_state[u] == BattleSim.U_READY:
			want.append(u)
	_check(battle.selection == want, "All selects in the strip's order (%s)" % str(battle.selection))
	_ro_sel = battle.selection.duplicate()
	_ro0 = battle.hud.display_order()


## Touch: a long press on the fourth card lifts it, a drag takes it first.
func _step_ro_touch_down() -> void:
	_no_double_tap()
	_ro_p = _vp_to_window(_ro_card(3).get_center())
	_ro_t0 = Time.get_ticks_msec()
	_touch(0, _ro_p, true)


func _step_ro_touch_wait() -> void:
	if Time.get_ticks_msec() - _ro_t0 < 500:
		steps.push_front(_step_ro_touch_wait)


func _step_ro_touch_drag() -> void:
	_check(battle.hud._reorder.is_active(), "a touch long press lifts the card")
	var r := _ro_card(0)
	var to := _vp_to_window(r.get_center() - Vector2(r.size.x * 0.3, 0))
	var prev := _ro_p
	for k in range(1, 7):
		var p := _ro_p.lerp(to, k / 6.0)
		_drag(0, p, p - prev)
		prev = p
	_ro_p = to


func _step_ro_touch_up() -> void:
	_touch(0, _ro_p, false)


func _step_ro_check_touch() -> void:
	var want: Array = [_ro0[3], _ro0[0], _ro0[1], _ro0[2]]
	want.append_array(_ro0.slice(4))
	_check(battle.hud.display_order() == want, "long press and drag moves the card first (%s)" % str(battle.hud.display_order()))
	_check(not battle.hud.book.visible and battle.selection == _ro_sel, "the touch drag opens no page and keeps the selection (%s, book %s)" % [str(battle.selection), str(battle.hud.book.visible)])
	_check(not battle.hud._reorder.is_active() and not Hud.TouchScroll.hold, "the lift is over")
	_ro0 = battle.hud.display_order()


## A quick touch drag (no long press) moves nothing.
func _step_ro_short_drag() -> void:
	_no_double_tap()
	var a := _vp_to_window(_ro_card(1).get_center())
	var b := _vp_to_window(_ro_card(3).get_center())
	_touch(0, a, true)
	var prev := a
	for k in range(1, 5):
		var p := a.lerp(b, k / 4.0)
		_drag(0, p, p - prev)
		prev = p
	_touch(0, b, false)


func _step_ro_check_short() -> void:
	_check(battle.hud.display_order() == _ro0, "a quick touch drag moves no card")
	_check(battle.selection == _ro_sel and not battle.hud.book.visible, "nor selects or opens anything (%s)" % str(battle.selection))


func _step_ro_pages() -> void:
	battle._open_book(-1, "book_open")
	battle.hud.book.close()
	battle._open_controls()
	battle.hud.controls.close()


func _step_ro_check_pages() -> void:
	_check(battle.hud.display_order() == _ro0 and _ro_box_order() == _ro0, "the order survives the unit book and the controls page")


# ---- gate doorway taps ----

var _gd_gate := -1
var _gd_sel := -1     # a selected defender unit (not on the wall)
var _gd_wall := -1    # a defender unit on the wall whose marker overlaps the doorway
var _gd_on := -1      # the toggle a tap should ask for (1 close, 0 open)
var _gd_moves0 := 0


## World point (px) at gate g's frame position (fx along the wall, fy
## outward; sim units).
func _gd_point(g: int, fx: float, fy: float) -> Vector2:
	var sim := battle.sim
	var a: float = sim.g_dir[g] * TAU / 1024.0
	var p := Vector2(sim.g_x[g], sim.g_y[g]) + Vector2(-sin(a), cos(a)) * fx + Vector2(cos(a), sin(a)) * fy
	return p / 1024.0 * Battle.PX_PER_M


func _gd_gate_orders() -> Array:
	var out: Array = []
	for o in battle.sim.pending_orders:
		if int(o["type"]) == BattleSim.ORDER_GATE:
			out.append(o)
	return out


func _gd_tap(w: Vector2) -> void:
	_no_double_tap()
	var p := _world_to_screen(w)
	_touch(0, p, true)
	_touch(0, p, false)


## Walled city (walls 2, inner ring) defended by the player (side 0).
func _step_gd_start() -> void:
	if is_instance_valid(battle):
		battle.queue_free()
	battle = Battle.new()
	battle.custom_scenario = Scenarios.siege_test(303, 2, 2, MapGen.PAL_ARID, Terrain.K_FLAT, 0)
	battle.seed_value = 7
	root.add_child(battle)


func _step_gd_tap_door() -> void:
	var sim := battle.sim
	if not battle.paused:
		battle._toggle_pause()
	_check(sim.city_def == battle.player_side and sim.n_gates > 0,
		"gate test: the player defends a walled city (%d gates)" % sim.n_gates)
	# The last gate that is not broken (inner ring gates come after the outer ones).
	for g in sim.n_gates:
		if sim.g_state[g] != BattleSim.GATE_BROKEN:
			_gd_gate = g
	_gd_on = 1 if sim.g_state[_gd_gate] == BattleSim.GATE_OPEN else 0
	for u in sim.n_units:
		if sim.u_side[u] != 0 or sim.u_state[u] != BattleSim.U_READY:
			continue
		if sim.u_wall[u] > 0 and _gd_wall < 0:
			_gd_wall = u
		elif sim.u_wall[u] == 0 and _gd_sel < 0:
			_gd_sel = u
	_check(_gd_gate >= 0 and _gd_wall >= 0 and _gd_sel >= 0,
		"gate test: a gate, a wall unit and a ground unit (%d %d %d)" % [_gd_gate, _gd_wall, _gd_sel])
	battle.camera.zoom = Vector2(1, 1)
	_focus(sim.g_x[_gd_gate], sim.g_y[_gd_gate])
	battle._select(_gd_sel)
	_gd_moves0 = _pending_moves()
	_gd_tap(_gd_point(_gd_gate, 0, 0))


func _step_gd_check_door() -> void:
	var go := _gd_gate_orders()
	_check(go.size() == 1 and int(go[0]["gate"]) == _gd_gate and int(go[0]["on"]) == _gd_on,
		"defender with a unit selected: a tap on the gate's doorway toggles it (%s)" % str(go))
	_check(battle.selection == [_gd_sel], "the selection is kept (%s)" % str(battle.selection))
	_check(_pending_moves() == _gd_moves0, "no move is queued by the gate tap")


## Put the wall unit's marker over the doorway's edge along the wall, then
## tap the doorway inside that marker's hit circle.
func _step_gd_tap_door_marker() -> void:
	var sim := battle.sim
	var touch_r: int = battle._marker_hit_r()
	var rx := maxi((sim.g_hw[_gd_gate] + 1) * 1024, touch_r)
	var mr := maxf(Overlay.MARKER_MIN_R, Overlay.MARKER_SCREEN_R / battle.camera.zoom.x)
	var lift := int(2.2 * mr / Battle.PX_PER_M * 1024)
	var mk := _gd_point(_gd_gate, rx + 512, 0) / Battle.PX_PER_M * 1024.0  # marker centre, sim units
	var cx := int(mk.x)
	var cy := int(mk.y) + lift
	# Test set-up only (paused, view picking): the unit stands on the wall
	# next to the gate, its marker floating over the doorway.
	var dx: int = cx - sim.u_cx[_gd_wall]
	var dy: int = cy - sim.u_cy[_gd_wall]
	sim.u_cx[_gd_wall] = cx
	sim.u_cy[_gd_wall] = cy
	sim.u_minx[_gd_wall] += dx
	sim.u_maxx[_gd_wall] += dx
	sim.u_miny[_gd_wall] += dy
	sim.u_maxy[_gd_wall] += dy
	var tap := _gd_point(_gd_gate, rx - 512, 0)
	_check(battle._pick_unit(tap) == _gd_wall, "the wall unit's marker covers the doorway tap point")
	_gd_tap(tap)


func _step_gd_check_door_marker() -> void:
	var go := _gd_gate_orders()
	_check(go.size() == 2 and int(go[1]["gate"]) == _gd_gate,
		"a doorway tap under a wall unit's marker toggles the gate (%d gate orders)" % go.size())
	_check(battle.selection == [_gd_sel], "... and does not select the unit on the wall (%s)" % str(battle.selection))
	_check(_pending_moves() == _gd_moves0, "... nor move anything")


func _step_gd_tap_marker() -> void:
	var sim := battle.sim
	var rx := maxi((sim.g_hw[_gd_gate] + 1) * 1024, battle._marker_hit_r())
	var tap := _gd_point(_gd_gate, rx + 512, 0)
	_check(battle._gate_doorway(tap) < 0, "the marker's centre is outside the doorway")
	_gd_tap(tap)


func _step_gd_check_marker() -> void:
	_check(battle.selection == [_gd_wall], "a tap on the marker just outside the doorway selects the unit (%s)" % str(battle.selection))
	_check(_gd_gate_orders().size() == 2, "... and asks nothing of the gate")


# Siege equipment (part 2b): tap a piece to pick it up, refusals, tap a
# stretch with a carried set to plant it, the Drop button.
var _eq_inf := -1
var _eq_cav := -1
var _eq_lp := Vector2i(-1, -1)


func _eq_orders(typ: int) -> Array:
	var out: Array = []
	for o in battle.sim.pending_orders:
		if int(o["type"]) == typ:
			out.append(o)
	return out


func _step_eq_start() -> void:
	if is_instance_valid(battle):
		battle.queue_free()
	battle = Battle.new()
	battle.custom_scenario = Scenarios.siege_test(303, 2, 2, MapGen.PAL_ARID, Terrain.K_FLAT, 1, -1, MapGen.PLAN_RING,
		0, {"ladders": 2, "ram": 1})
	battle.seed_value = 7
	root.add_child(battle)


## Cavalry and foot selected, a tap on ladder set 0: the foot goes for it.
func _step_eq_tap_piece() -> void:
	var sim := battle.sim
	if not battle.paused:
		battle._toggle_pause()
	_check(sim.n_eq == 3, "equipment: two ladder sets and a ram on the ground (%d)" % sim.n_eq)
	for u in sim.n_units:
		if sim.u_side[u] != 0:
			continue
		if sim.u_cls[u] == UT.CLS_INF and _eq_inf < 0:
			_eq_inf = u
		elif sim.u_cls[u] == UT.CLS_CAV and _eq_cav < 0:
			_eq_cav = u
	battle.camera.zoom = Vector2(1, 1)
	_focus(sim.q_x[0], sim.q_y[0])
	battle._select(_eq_cav)
	_gd_tap(Vector2(sim.q_x[0], sim.q_y[0]) / 1024.0 * Battle.PX_PER_M)
	_check(_eq_orders(BattleSim.ORDER_PICKUP).is_empty(), "cavalry alone: a tap on the ladders picks nothing up")
	battle._toggle_in_selection(_eq_inf)
	_gd_tap(Vector2(sim.q_x[0], sim.q_y[0]) / 1024.0 * Battle.PX_PER_M)


func _step_eq_check_piece() -> void:
	var po := _eq_orders(BattleSim.ORDER_PICKUP)
	_check(po.size() == 1 and int(po[0]["unit"]) == _eq_inf and int(po[0]["equip"]) == 0,
		"cavalry and foot selected, a tap on the ladders: the foot picks them up (%s)" % str(po))
	_check(battle.orders.value(_eq_inf, "pick") == 0, "the preview knows the pick-up")
	# Carrying the set from here on (test set-up: picked up at once); the
	# camera goes to a stretch it can be planted on (the tap comes next frame).
	var sim := battle.sim
	sim.pending_orders.clear()
	battle.orders.refresh()
	sim.u_carry[_eq_inf] = 0
	sim.q_state[0] = BattleSim.Q_CARRIED
	sim.q_unit[0] = _eq_inf
	battle._select(_eq_inf)
	for sg in sim.ws_x0.size():
		var mp: Vector2i = BattleSim.seg_pt(sim, sg, BattleSim.seg_len(sim, sg) / 2)
		if BattleSim.ladder_set_for(sim, _eq_inf, sg, mp.x, mp.y) == 0:
			_eq_lp = mp
			break
	_check(_eq_lp.x >= 0, "a stretch the carried set can be planted on")
	_focus(_eq_lp.x, _eq_lp.y)


## Carrying the set, a tap on the stretch; an enemy tapped while carrying
## is refused.
func _step_eq_tap_wall() -> void:
	var sim := battle.sim
	# (The wall tap's own path - _tap, wall_refusal, the move order - is
	# given exactly; the camera may not sit where the walkway is.)
	_check(battle.orders.wall_refusal(_eq_inf, _eq_lp.x, _eq_lp.y) == "", "no refusal for planting there")
	battle._queue(BattleSim.make_move_order(0, _eq_inf, _eq_lp.x, _eq_lp.y, 768, 20 * 1024, 0))
	sim.u_carry[_eq_cav] = -1
	_check(battle.orders.wall_refusal(_eq_cav, _eq_lp.x, _eq_lp.y).contains("Only foot"),
		"cavalry ordered onto the wall: refused (%s)" % battle.orders.wall_refusal(_eq_cav, _eq_lp.x, _eq_lp.y))


func _step_eq_check_wall() -> void:
	var mo := _eq_orders(BattleSim.ORDER_MOVE)
	_check(mo.size() == 1 and int(mo[0]["unit"]) == _eq_inf, "carrying ladders, a tap on the wall: a move there (%s)" % str(mo))
	var wp: Dictionary = battle.orders.wall_plan(_eq_inf)
	_check(str(wp.get("mode", "")) == "ladder" and bool(wp.get("plant", false)),
		"the preview: PLANT LADDERS HERE (%s %s)" % [str(wp.get("mode", "")), str(wp.get("plant", false))])
	var enemy := -1
	for u in battle.sim.n_units:
		if battle.sim.u_side[u] == 1 and not battle.sim.is_tower(u):
			enemy = u
			break
	battle._queue(BattleSim.make_attack_order(0, _eq_inf, enemy, 0))
	_check(battle.orders.value(_eq_inf, "order") == BattleSim.O_MOVE and battle.orders.value(_eq_inf, "target") < 0,
		"carrying: an attack order is refused by the rule (the plant move stands)")
	battle._refresh_actions()
	_check(battle.hud.drop_button.visible, "the Drop button shows while a selected unit carries")


func _step_eq_drop() -> void:
	battle.sim.pending_orders.clear()
	battle.orders.refresh()
	battle.hud.drop_button.pressed.emit()


func _step_eq_check_drop() -> void:
	var dr := _eq_orders(BattleSim.ORDER_DROP)
	_check(dr.size() == 1 and int(dr[0]["unit"]) == _eq_inf, "Drop: the carrier puts the ladders down (%s)" % str(dr))


func _step_done() -> void:
	print("RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
