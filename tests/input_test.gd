extends SceneTree
## Scripted input test: feeds synthetic touch events through Godot's input
## pipeline into the battle view and checks the orders that reach the sim.
##   godot --headless --script res://tests/input_test.gd
## (Also runs windowed; add --write-movie to capture frames.)
## Exits 0 on success, 1 on failure.

const Battle := preload("res://game/battle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")

var battle: Battle
var frame := 0
var failures := 0
var steps: Array[Callable] = []
var wait := 0


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
	return battle.get_viewport().get_final_transform() * p


func _unit_screen(u: int) -> Vector2:
	var sim := battle.sim
	return _world_to_screen(Vector2(sim.u_cx[u], sim.u_cy[u]) / 1024.0 * Battle.PX_PER_M)


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


func _check(cond: bool, what: String) -> void:
	if cond:
		print("PASS ", what)
	else:
		printerr("FAIL ", what)
		failures += 1


func _no_double_tap() -> void:
	battle._last_tap_time = -10.0


# --------------------------------------------------------------- steps ---

func _step_pause() -> void:
	battle._toggle_pause()  # keep the sim still so screen positions hold


func _step_tap_select() -> void:
	_no_double_tap()
	var p := _unit_screen(0)
	_touch(0, p, true)
	_touch(0, p, false)


func _step_check_selected() -> void:
	_check(battle.selected == 0, "tap on own unit selects it (selected=%d)" % battle.selected)


var _line_a := Vector2.ZERO
var _line_b := Vector2.ZERO


func _step_drag_line_begin() -> void:
	# Draw a line left to right, 40 m long, 30 m in front of the unit.
	var sim := battle.sim
	var w := Vector2(sim.u_ax[0], sim.u_ay[0] - 30 * 1024) / 1024.0 * Battle.PX_PER_M
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
	var files: int = sim.u_files[0]
	_check(sim.u_order[0] == BattleSim.O_MOVE, "drag line issues a move (order=%d)" % sim.u_order[0])
	_check(absi(files - 36) <= 1, "line length sets frontage (files=%d, expect ~36 for 40 m)" % files)
	_check(absi(((sim.u_dface[0] - 768 + 512) & 1023) - 512) <= 2, "left-to-right drag faces up (facing=%d)" % sim.u_dface[0])


func _step_tap_enemy() -> void:
	_no_double_tap()
	var enemy := -1
	for u in battle.sim.n_units:
		if battle.sim.u_side[u] == 1:
			enemy = u
			break
	var p := _unit_screen(enemy)
	_touch(0, p, true)
	_touch(0, p, false)
	battle.sim.step()


func _step_check_attack() -> void:
	var sim := battle.sim
	_check(sim.u_order[0] == BattleSim.O_ATTACK and sim.u_side[sim.u_target[0]] == 1,
		"tap on enemy issues attack (order=%d target=%d)" % [sim.u_order[0], sim.u_target[0]])
	_check(sim.u_run[0] == 0, "single tap attack walks")


var _ground := Vector2.ZERO


func _step_double_tap_ground_1() -> void:
	_no_double_tap()
	var sim := battle.sim
	_ground = _world_to_screen(Vector2(sim.u_ax[0] - 40 * 1024, sim.u_ay[0] + 10 * 1024) / 1024.0 * Battle.PX_PER_M)
	_touch(0, _ground, true)
	_touch(0, _ground, false)


func _step_double_tap_ground_2() -> void:
	_touch(0, _ground, true)
	_touch(0, _ground, false)
	battle.sim.step()


func _step_check_run_move() -> void:
	var sim := battle.sim
	_check(sim.u_order[0] == BattleSim.O_MOVE and sim.u_run[0] == 1,
		"double tap on ground moves at the run (order=%d run=%d)" % [sim.u_order[0], sim.u_run[0]])


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
	# Second player card (unit 1).
	var card: Button = battle.hud._cards[1]
	var p := _vp_to_window(card.get_global_rect().get_center())
	_touch(0, p, true)
	_touch(0, p, false)


func _step_check_card() -> void:
	_check(battle.selected == 1, "tapping a unit card selects that unit (selected=%d)" % battle.selected)
	_check(battle.sim.u_order[1] == BattleSim.O_NONE, "card tap does not leak a ground order")


var _orders_seq_before := 0


func _step_tap_orders_toggle() -> void:
	_no_double_tap()
	_orders_seq_before = battle.sim._order_seq
	var p := _vp_to_window(battle.hud.orders_button.get_global_rect().get_center())
	_touch(0, p, true)
	_touch(0, p, false)


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
	# Keep the gesture away from HUD panels: centre the view ahead of unit 1.
	var sim := battle.sim
	battle.camera.position = Vector2(sim.u_ax[1], sim.u_ay[1] - 40 * 1024) / 1024.0 * Battle.PX_PER_M


func _step_paused_move_1() -> void:
	_no_double_tap()
	if not battle.paused:
		battle._toggle_pause()
	battle._select(1)
	_paused_tick = battle.sim.tick
	_expect_c = _draw_line_order(1, 50, 15)


func _pending_ok(u: int, expect_files: int, what: String) -> void:
	var o: Variant = battle.orders
	var ov := battle.overlay
	_check(battle.sim.tick == _paused_tick, "%s: no sim tick elapsed (tick %d)" % [what, battle.sim.tick])
	_check(o.has_pending(u), "%s: order recorded as pending in the view" % what)
	_check(battle.sim.u_order[u] == BattleSim.O_NONE, "%s: sim has not applied it yet" % what)
	_check(ov._v(u, "order") == BattleSim.O_MOVE, "%s: overlay draws a move for the unit" % what)
	var dx: int = ov._v(u, "dx")
	var dy: int = ov._v(u, "dy")
	_check(absf(dx - _expect_c.x) < 1500 and absf(dy - _expect_c.y) < 1500,
		"%s: drawn destination matches the gesture (%d,%d vs %.0f,%.0f)" % [what, dx, dy, _expect_c.x, _expect_c.y])
	_check(absi(ov._v(u, "files") - expect_files) <= 1, "%s: drawn frontage %d files (expect ~%d)" % [what, ov._v(u, "files"), expect_files])


func _step_paused_check_1() -> void:
	_pending_ok(1, 27, "paused move")  # 30 m line -> ~27 files


func _step_paused_move_2() -> void:
	_expect_c = _draw_line_order(1, 70, 10)


func _step_paused_check_2() -> void:
	_pending_ok(1, 18, "replacement paused move")  # 20 m line -> ~18 files
	_predicted = {}
	for k in ["order", "dx", "dy", "dface", "files", "run", "target"]:
		_predicted[k] = battle.overlay._v(1, k)


func _step_unpause() -> void:
	battle._toggle_pause()


func _step_check_handover() -> void:
	if battle.sim.tick <= _paused_tick:
		steps.push_front(_step_check_handover)  # wait for the first tick
		return
	var sim := battle.sim
	_check(not battle.orders.has_pending(1), "after unpause the pending entry is dropped")
	var same := true
	for k in _predicted:
		var simv: int = (sim.get("u_" + k) as PackedInt32Array)[1]
		if simv != _predicted[k]:
			same = false
			printerr("  mismatch %s: predicted %d sim %d" % [k, _predicted[k], simv])
	_check(same, "sim state after applying equals what was drawn while paused (no jump)")
	_check(battle.overlay._v(1, "dx") == _predicted["dx"], "overlay now reads the same destination from the sim")


func _step_done() -> void:
	print("RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)
