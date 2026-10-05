extends Node2D
## Battle view and input. Owns the sim, steps it at 10 Hz (scaled by the
## speed setting), uploads state to the renderer after each tick, and turns
## touch / mouse gestures into sim orders. It never writes sim state directly.

signal exit_requested

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const SoldierLayer := preload("res://game/soldier_layer.gd")
const Overlay := preload("res://game/overlay.gd")
const Hud := preload("res://game/hud.gd")
const OrderPreview := preload("res://game/order_preview.gd")

const PX_PER_M := 10.0
const M := 1024.0
const TICK_SEC := 0.1
const MAX_TICKS_PER_FRAME := 4
const SPEEDS := [0.5, 1.0, 2.0, 4.0]
const DRAG_THRESHOLD := 18.0      # screen px before a touch becomes a drag
const DOUBLE_TAP_SEC := 0.35
const DOUBLE_TAP_DIST := 48.0
const MIN_LINE_M := 3.0           # shorter drags keep the current frontage
const ZOOM_MIN := 0.12
const ZOOM_MAX := 4.0
const PLAYER_SIDE := 0
const STATS_WINDOW := 20          # ticks (2 s) for sim ms average / worst
const TELEMETRY_SAMPLE_SEC := 5.0
# Ticks at which the state hash is reported, so runs of the same scenario and
# seed can be compared across devices (multiples of 10).
const HASH_CHECKPOINTS := [100, 300, 600, 1000, 1500, 2000, 3000, 4000]
const MAX_ORDER_EVENTS := 300

## Remembered for the page session (static: survives returning to the menu).
static var show_all_orders := false

var scenario_id := "skirmish"
var seed_value := 1

var sim: BattleSim
var camera: Camera2D
var soldiers: SoldierLayer
var overlay: Overlay
var hud: Hud
var orders: OrderPreview  # queued-but-unapplied orders, for immediate display

var paused := false
var speed_idx := 1
var interactive := true
var bench_mode := false
var selected := -1

var _acc := 0.0
var _sim_ms := PackedFloat64Array()
var _upload_ms := 0.0
var _hash_text := "--------"
var _card_timer := 0.0

# Benchmark bookkeeping.
var _bench_frames := PackedFloat64Array()
var _bench_ticks := PackedFloat64Array()
var _bench_done := false
var _decided_tick := -1

# Telemetry (view only; never touches sim state).
var _tele: Node = null
var _win_frames := PackedFloat64Array()
var _win_sim := PackedFloat64Array()
var _win_time := 0.0
var _input_counts := {}
var _orders_by_type := {}
var _player_orders := 0
var _order_events := 0
var _checkpoint_hashes := {}
var _start_msec := 0
var _ended := false

# Gesture state.
var _touches: Dictionary = {}      # index -> current screen pos
var _primary := -1                 # touch index of the single-finger gesture
var _press_pos := Vector2.ZERO
var _dragging := false
var _gesture_multi := false        # two-finger gesture in progress
var _pinch_dist := 0.0
var _pinch_mid := Vector2.ZERO
var _last_tap_time := -10.0
var _last_tap_pos := Vector2.ZERO
var _mouse_pan := false


func _ready() -> void:
	sim = BattleSim.new()
	sim.setup(Scenarios.make(scenario_id), seed_value)
	bench_mode = sim.is_ai_side(0) and sim.is_ai_side(1)
	interactive = not sim.is_ai_side(PLAYER_SIDE)

	var bg := ColorRect.new()
	bg.color = Color(0.27, 0.38, 0.2)
	bg.size = Vector2(sim.field_w, sim.field_h) / M * PX_PER_M
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var grid := _FieldGrid.new()
	grid.size_px = bg.size
	add_child(grid)

	soldiers = SoldierLayer.new()
	add_child(soldiers)
	soldiers.setup(sim, PX_PER_M)

	orders = OrderPreview.new()
	orders.sim = sim
	overlay = Overlay.new()
	overlay.sim = sim
	overlay.orders = orders
	overlay.px_per_m = PX_PER_M
	add_child(overlay)

	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	_fit_camera()

	hud = Hud.new()
	add_child(hud)
	hud.build(sim, PLAYER_SIDE, interactive)
	hud.card_pressed.connect(_on_card)
	hud.pause_pressed.connect(_toggle_pause)
	hud.speed_pressed.connect(_cycle_speed)
	hud.menu_pressed.connect(_on_menu)
	hud.run_pressed.connect(_toggle_run)
	hud.halt_pressed.connect(_halt)
	hud.orders_toggled.connect(_on_orders_toggled)
	hud.orders_button.set_pressed_no_signal(show_all_orders)
	hud.set_orders_text(show_all_orders)
	overlay.show_all_orders = show_all_orders
	overlay.player_side = PLAYER_SIDE
	hud.update_cards(sim)
	hud.set_selected(-1, 0)
	_update_speed_text()
	_apply_debug_args()
	_hash_text = "%08x" % sim.state_hash()
	_tele = get_node_or_null("/root/Telemetry")
	if _tele != null:
		_tele.page_hiding.connect(_on_page_hiding)
	_start_msec = Time.get_ticks_msec()
	_reset_window()
	_t("scenario_start", {"scenario": scenario_id, "seed": seed_value, "soldiers": sim.n,
		"units": sim.n_units, "bench": bench_mode, "interactive": interactive,
		"speed": SPEEDS[speed_idx], "start_tick": sim.tick, "hash_at_start": _hash_text})


## Testing aids (desktop only): -- --skip-ticks=N --cam=x_m,y_m --zoom=Z
## --select=U fast-forward the sim and frame the camera for screenshots.
func _apply_debug_args() -> void:
	for a in OS.get_cmdline_user_args():
		var v := a.get_slice("=", 1)
		if a.begins_with("--skip-ticks="):
			for t in int(v):
				sim.step()
			soldiers.upload()
		elif a.begins_with("--cam="):
			camera.position = Vector2(float(v.get_slice(",", 0)), float(v.get_slice(",", 1))) * PX_PER_M
		elif a.begins_with("--zoom="):
			camera.zoom = Vector2.ONE * float(v)
		elif a.begins_with("--select="):
			_select(int(v))
		elif a == "--show-orders":
			hud.orders_button.button_pressed = true
		elif a == "--demo-orders":
			# Every other player unit advances 40 m in a wider line; the rest
			# stay put. For screenshots of the all-orders overlay.
			for u in sim.n_units:
				if sim.u_side[u] == PLAYER_SIDE and u % 2 == 0:
					_queue(BattleSim.make_move_order(0, u, sim.u_ax[u] + 6 * 1024,
						sim.u_ay[u] - 40 * 1024, 760, 32 * 1024, 0))


func _on_orders_toggled(on: bool) -> void:
	show_all_orders = on
	overlay.show_all_orders = on
	overlay.queue_redraw()
	_count("orders_overlay_on" if on else "orders_overlay_off")


func _on_menu() -> void:
	_end_scenario("menu")
	exit_requested.emit()


func _fit_camera() -> void:
	# Frame the two armies (central 75% of the field).
	var vp := get_viewport_rect().size
	var field := Vector2(sim.field_w, sim.field_h) / M * PX_PER_M
	camera.position = field * 0.5
	var z := minf(vp.x / (field.x * 0.8), vp.y / (field.y * 0.6))
	camera.zoom = Vector2.ONE * clampf(z, ZOOM_MIN, ZOOM_MAX)


# ------------------------------------------------------------- stepping ---

func _process(delta: float) -> void:
	if not paused and not _bench_done:
		_acc += delta * SPEEDS[speed_idx]
		var steps := 0
		while _acc >= TICK_SEC and steps < MAX_TICKS_PER_FRAME and not _bench_done:
			_do_tick()
			_acc -= TICK_SEC
			steps += 1
		if steps == MAX_TICKS_PER_FRAME and _acc >= TICK_SEC:
			_acc = 0.0  # cannot keep up: drop time rather than spiral
		if steps > 0:
			var t0 := Time.get_ticks_usec()
			soldiers.selected_unit = selected
			soldiers.upload()
			_upload_ms = (Time.get_ticks_usec() - t0) / 1000.0
	soldiers.set_alpha(clampf(_acc / TICK_SEC, 0.0, 1.0))
	orders.refresh()  # drop orders the sim has applied
	# Redrawn every frame, paused or not, so order changes show at once.
	overlay.selected_unit = selected
	overlay.zoom = camera.zoom.x
	overlay.queue_redraw()

	if bench_mode and not _bench_done:
		_bench_frames.append(delta)

	if _tele != null and not _ended:
		_win_frames.append(delta)
		_win_time += delta
		if _win_time >= TELEMETRY_SAMPLE_SEC:
			_send_perf_sample()

	_card_timer -= delta
	if _card_timer <= 0.0:
		_card_timer = 0.25
		hud.update_cards(sim)
		_update_stats_label()


func _do_tick() -> void:
	var t0 := Time.get_ticks_usec()
	sim.step()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_sim_ms.append(ms)
	_win_sim.append(ms)
	if _sim_ms.size() > STATS_WINDOW:
		_sim_ms.remove_at(0)
	if bench_mode:
		_bench_ticks.append(ms)
	if sim.tick % 10 == 0:
		_hash_text = "%08x" % sim.state_hash()
		if sim.tick in HASH_CHECKPOINTS:
			_checkpoint_hashes[str(sim.tick)] = _hash_text
			_t("hash_checkpoint", {"scenario": scenario_id, "seed": seed_value,
				"tick": sim.tick, "hash": _hash_text, "player_orders": _player_orders})
	if selected >= 0 and sim.u_state[selected] != BattleSim.U_READY:
		_select(-1)
	if sim.winner >= 0 and _decided_tick < 0:
		_decided_tick = sim.tick
		_show_result()
		_t("battle_decided", {"scenario": scenario_id, "tick": sim.tick, "winner": sim.winner,
			"alive0": sim.alive_count(0), "alive1": sim.alive_count(1)})
	if bench_mode and _decided_tick >= 0 and sim.tick >= _decided_tick + 100:
		_finish_bench()


func _update_stats_label() -> void:
	var avg := 0.0
	var worst := 0.0
	for v in _sim_ms:
		avg += v
		worst = maxf(worst, v)
	if _sim_ms.size() > 0:
		avg /= _sim_ms.size()
	var a0 := sim.alive_count(0)
	var a1 := sim.alive_count(1)
	hud.stats_label.text = "FPS %d   sim %.2f ms avg / %.2f worst (2 s)   upload %.2f ms\nsoldiers %d  (%d v %d)   tick %d   hash %s" % [
		Engine.get_frames_per_second(), avg, worst, _upload_ms, a0 + a1, a0, a1,
		sim.tick, _hash_text]


func _show_result() -> void:
	var text := "Draw"
	if sim.winner == PLAYER_SIDE:
		text = "Victory" if interactive else "Blue wins"
	elif sim.winner == 1 - PLAYER_SIDE:
		text = "Defeat" if interactive else "Red wins"
	hud.banner.text = text
	hud.banner.visible = true


func _finish_bench() -> void:
	_bench_done = true
	var ticks := _bench_ticks.duplicate()
	ticks.sort()
	var frames := _bench_frames.duplicate()
	var total := 0.0
	for f in frames:
		total += f
	frames.sort()
	var tsum := 0.0
	for t in ticks:
		tsum += t
	var slow1 := frames[int(frames.size() * 0.99)] if frames.size() > 0 else 0.0
	hud.bench_label.text = "Benchmark: %s\n%d soldiers at start, %d ticks (%.0f s battle time)\n\nSim ms per tick: mean %.2f   p95 %.2f   max %.2f\nFrames: %d, avg %.1f fps, 1%% slowest frame %.1f ms (%.0f fps)\nRenderer: %s\n%s" % [
		Scenarios.title(scenario_id), sim.n, ticks.size(), ticks.size() * TICK_SEC,
		tsum / maxf(1.0, ticks.size()), ticks[int(ticks.size() * 0.95)], ticks[ticks.size() - 1],
		frames.size(), frames.size() / maxf(total, 0.001), slow1 * 1000.0, 1.0 / maxf(slow1, 0.0001),
		RenderingServer.get_video_adapter_name(), OS.get_name() + " " + OS.get_model_name()]
	hud.bench_panel.visible = true
	print(hud.bench_label.text)
	_t("bench_summary", {"scenario": scenario_id, "seed": seed_value, "soldiers": sim.n,
		"ticks": ticks.size(), "sim_ms_mean": tsum / maxf(1.0, ticks.size()),
		"sim_ms_p95": ticks[int(ticks.size() * 0.95)], "sim_ms_max": ticks[ticks.size() - 1],
		"frames": frames.size(), "fps_avg": frames.size() / maxf(total, 0.001),
		"frame_ms_p99": slow1 * 1000.0, "frame_ms_max": frames[frames.size() - 1] * 1000.0 if frames.size() > 0 else 0.0,
		"gpu": RenderingServer.get_video_adapter_name(), "text": hud.bench_label.text})
	_end_scenario("bench_complete")


# ------------------------------------------------------------ telemetry ---

func _t(kind: String, data: Dictionary) -> void:
	if _tele != null:
		_tele.event(kind, data)


func _count(key: String) -> void:
	_input_counts[key] = int(_input_counts.get(key, 0)) + 1


func _reset_window() -> void:
	_win_frames = PackedFloat64Array()
	_win_sim = PackedFloat64Array()
	_win_time = 0.0
	_input_counts = {}
	_orders_by_type = {}


func _send_perf_sample() -> void:
	var frames := _win_frames.duplicate()
	frames.sort()
	var ftotal := 0.0
	for f in frames:
		ftotal += f
	var sims := _win_sim
	var smean := 0.0
	var smax := 0.0
	for v in sims:
		smean += v
		smax = maxf(smax, v)
	if sims.size() > 0:
		smean /= sims.size()
	var nf := frames.size()
	var fmax: float = frames[nf - 1] if nf > 0 else 0.0
	_t("perf", {
		"scenario": scenario_id, "tick": sim.tick, "alive": sim.alive_count(),
		"window_s": _win_time, "frames": nf,
		"fps_avg": nf / maxf(ftotal, 0.001),
		"fps_min": 1.0 / maxf(fmax, 0.0001),
		"frame_ms_p95": (frames[mini(nf - 1, int(nf * 0.95))] * 1000.0) if nf > 0 else 0.0,
		"frame_ms_max": fmax * 1000.0,
		"ticks": sims.size(), "sim_ms_mean": smean, "sim_ms_max": smax,
		"upload_ms": _upload_ms, "speed": SPEEDS[speed_idx], "paused": paused,
		"zoom": camera.zoom.x, "input": _input_counts.duplicate(),
		"orders": _orders_by_type.duplicate(),
	})
	_reset_window()


## Final record for this battle (menu, benchmark complete or node freed).
func _end_scenario(reason: String) -> void:
	if _ended or _tele == null:
		return
	if _win_time > 0.5:
		_send_perf_sample()
	_ended = true
	_t("scenario_end", {"scenario": scenario_id, "seed": seed_value, "reason": reason,
		"soldiers": sim.n, "tick": sim.tick, "winner": sim.winner, "decided_tick": _decided_tick,
		"alive0": sim.alive_count(0), "alive1": sim.alive_count(1),
		"wall_s": (Time.get_ticks_msec() - _start_msec) / 1000.0,
		"final_hash": "%08x" % sim.state_hash(), "checkpoint_hashes": _checkpoint_hashes,
		"player_orders": _player_orders})
	_tele.flush()


## The page is being hidden or closed: the main loop may never run again, so
## record where the battle got to (the run may resume if the tab comes back).
func _on_page_hiding() -> void:
	if _ended:
		return
	if _win_time > 0.5:
		_send_perf_sample()
	_t("scenario_snapshot", {"scenario": scenario_id, "seed": seed_value, "tick": sim.tick,
		"winner": sim.winner, "alive0": sim.alive_count(0), "alive1": sim.alive_count(1),
		"wall_s": (Time.get_ticks_msec() - _start_msec) / 1000.0, "hash": _hash_text,
		"hash_tick": sim.tick - sim.tick % 10, "player_orders": _player_orders})


func _exit_tree() -> void:
	_end_scenario("exit")


# --------------------------------------------------------------- orders ---

func _queue(order: Dictionary) -> void:
	# Solo play: orders apply on the next tick. Lockstep will add a delay.
	order["tick"] = sim.tick
	sim.queue_order(order)
	orders.add(order)
	overlay.queue_redraw()
	var tname: String = {BattleSim.ORDER_MOVE: "move", BattleSim.ORDER_ATTACK: "attack",
		BattleSim.ORDER_HALT: "halt", BattleSim.ORDER_RUN: "run"}.get(int(order["type"]), "other")
	_player_orders += 1
	_orders_by_type[tname] = int(_orders_by_type.get(tname, 0)) + 1
	if _order_events < MAX_ORDER_EVENTS:
		_order_events += 1
		_t("order", {"type": tname, "tick": sim.tick, "unit": int(order.get("unit", -1)),
			"run": int(order.get("run", 0))})


func _select(u: int) -> void:
	selected = u
	hud.set_selected(u, orders.value(u, "run") if u >= 0 else 0)
	overlay.queue_redraw()


func _on_card(u: int) -> void:
	if not interactive or sim.u_state[u] != BattleSim.U_READY:
		hud.set_selected(selected, orders.value(selected, "run") if selected >= 0 else 0)  # undo the card's toggle
		return
	if selected == u:
		_select(-1)
	else:
		_select(u)
		_center_on_unit(u)


func _center_on_unit(u: int) -> void:
	var p := Vector2(sim.u_cx[u], sim.u_cy[u]) / M * PX_PER_M
	var vr := get_viewport_rect().size / camera.zoom
	var cam_rect := Rect2(camera.position - vr * 0.5, vr).grow(-vr.x * 0.1)
	if not cam_rect.has_point(p):
		camera.position = p


func _toggle_pause() -> void:
	paused = not paused
	_count("pause_toggle")
	hud.pause_button.text = "Play" if paused else "Pause"


func _cycle_speed() -> void:
	speed_idx = (speed_idx + 1) % SPEEDS.size()
	_count("speed_change")
	_update_speed_text()


func _update_speed_text() -> void:
	var s: float = SPEEDS[speed_idx]
	hud.speed_button.text = ("%.1fx" % s) if s < 1.0 else ("%dx" % int(s))


func _toggle_run() -> void:
	if selected < 0:
		return
	var run := 0 if orders.value(selected, "run") != 0 else 1
	_queue(BattleSim.make_run_order(0, selected, run))
	hud.run_button.text = "Run: on" if run else "Run: off"


func _halt() -> void:
	if selected >= 0:
		_queue(BattleSim.make_halt_order(0, selected))


func _tap(screen_pos: Vector2, double: bool) -> void:
	_count("double_tap" if double else "tap")
	if not interactive:
		return
	var w := _screen_to_world(screen_pos)
	var u := _pick_unit(w)
	if u >= 0 and sim.u_side[u] == PLAYER_SIDE:
		if sim.u_state[u] != BattleSim.U_READY:
			_count("tap_on_broken_unit")
			return
		_count("tap_select")
		if selected == u and not double:
			_select(-1)
		else:
			_select(u)
		return
	if selected < 0:
		_count("tap_nothing_selected")
		return
	if u >= 0:
		# Enemy: attack (double tap = charge at the run).
		_queue(BattleSim.make_attack_order(0, selected, u, 1 if double else orders.value(selected, "run")))
		return
	# Ground: move there keeping frontage, facing the direction of travel.
	var dest := w / PX_PER_M * M
	var ax: int = orders.value(selected, "ax")
	var ay: int = orders.value(selected, "ay")
	var dx := dest.x - ax
	var dy := dest.y - ay
	var face: int = orders.value(selected, "face")
	if dx * dx + dy * dy > 4.0 * M * M:
		face = int(round(atan2(dy, dx) * 1024.0 / TAU)) & 1023
	var width: int = orders.value(selected, "files") * BattleSim.FILE_SPACING
	_queue(BattleSim.make_move_order(0, selected, int(dest.x), int(dest.y), face, width,
		1 if double else orders.value(selected, "run")))


func _finish_line(double_run: bool) -> void:
	if selected < 0 or not overlay.preview_ok:
		_count("line_too_short")
		return
	_count("line_drag")
	var p := overlay.preview_formation()
	var c: Vector2 = p["centre"] / PX_PER_M * M
	_queue(BattleSim.make_move_order(0, selected, int(c.x), int(c.y), p["facing"], p["width"],
		1 if double_run else orders.value(selected, "run")))


func _pick_unit(w: Vector2) -> int:
	var x := int(w.x / PX_PER_M * M)
	var y := int(w.y / PX_PER_M * M)
	var margin := int(2.5 * M)
	var best := -1
	var best_d := 0
	for u in sim.n_units:
		if sim.u_state[u] == BattleSim.U_DESTROYED:
			continue
		# Unit marker (drawn above the centroid) also counts.
		var in_box: bool = x >= sim.u_minx[u] - margin and x <= sim.u_maxx[u] + margin \
			and y >= sim.u_miny[u] - margin and y <= sim.u_maxy[u] + margin
		var mdx: int = x - sim.u_cx[u]
		var mdy: int = y - (sim.u_cy[u] - int(2.2 * 9.0 / camera.zoom.x / PX_PER_M * M))
		var marker_r := int(16.0 / camera.zoom.x / PX_PER_M * M)
		var on_marker := mdx * mdx + mdy * mdy <= marker_r * marker_r
		if not in_box and not on_marker:
			continue
		var dx: int = x - sim.u_cx[u]
		var dy: int = y - sim.u_cy[u]
		var d := dx * dx + dy * dy
		if best < 0 or d < best_d:
			best = u
			best_d = d
	return best


# ---------------------------------------------------------------- input ---

func _screen_to_world(p: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * p


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_count("wheel")
			_zoom_at(mb.position, 1.15)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mouse_pan = mb.pressed
			if mb.pressed:
				_count("mouse_pan")
		# Left button arrives again as an emulated touch; ignore it here.
	elif event is InputEventMouseMotion:
		if _mouse_pan:
			camera.position -= (event as InputEventMouseMotion).relative / camera.zoom
			_clamp_camera()
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_zoom_at(mg.position, mg.factor)
	elif event is InputEventPanGesture:
		camera.position += (event as InputEventPanGesture).delta * 8.0 / camera.zoom
		_clamp_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_toggle_pause()
		elif event.keycode == KEY_ESCAPE:
			_select(-1)


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		if hud.is_over_ui(e.position):
			_count("touch_on_ui")
			return
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_primary = e.index
			_press_pos = e.position
			_dragging = false
			_gesture_multi = false
		elif _touches.size() >= 2:
			# Second finger: cancel any one-finger action, start pinch/pan.
			if not _gesture_multi:
				_count("pinch")
				if _dragging and overlay.preview_on:
					_count("line_cancelled_by_second_finger")
				elif not _dragging:
					_count("tap_cancelled_by_second_finger")
			_gesture_multi = true
			_dragging = false
			overlay.preview_on = false
			_start_pinch()
		return
	if not _touches.has(e.index):
		return
	_touches.erase(e.index)
	if _gesture_multi:
		if _touches.size() >= 2:
			_start_pinch()
		if _touches.is_empty():
			_gesture_multi = false
			_primary = -1
		return
	if e.index != _primary:
		return
	_primary = -1
	var now := Time.get_ticks_msec() / 1000.0
	var double := now - _last_tap_time < DOUBLE_TAP_SEC and e.position.distance_to(_last_tap_pos) < DOUBLE_TAP_DIST
	if _dragging:
		_dragging = false
		if not overlay.preview_on:
			_count("pan_drag")
		if overlay.preview_on:
			overlay.preview_on = false
			_finish_line(false)
		return
	_tap(e.position, double)
	if double:
		_last_tap_time = -10.0
	else:
		_last_tap_time = now
		_last_tap_pos = e.position


func _on_drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index):
		return
	_touches[e.index] = e.position
	if _gesture_multi:
		_update_pinch()
		return
	if e.index != _primary:
		return
	if not _dragging and e.position.distance_to(_press_pos) > DRAG_THRESHOLD:
		_dragging = true
		if selected >= 0 and interactive:
			overlay.preview_on = true
	if not _dragging:
		return
	if overlay.preview_on:
		overlay.preview_a = _screen_to_world(_press_pos)
		overlay.preview_b = _screen_to_world(e.position)
		overlay.preview_ok = overlay.preview_a.distance_to(overlay.preview_b) >= MIN_LINE_M * PX_PER_M
	else:
		# No unit selected: one-finger drag pans.
		camera.position -= e.relative / camera.zoom
		_clamp_camera()


func _two_touches() -> Array:
	var keys := _touches.keys()
	keys.sort()
	return [_touches[keys[0]], _touches[keys[1]]]


func _start_pinch() -> void:
	if _touches.size() < 2:
		return
	var t := _two_touches()
	_pinch_dist = (t[0] as Vector2).distance_to(t[1])
	_pinch_mid = ((t[0] as Vector2) + (t[1] as Vector2)) * 0.5


func _update_pinch() -> void:
	if _touches.size() < 2:
		return
	var t := _two_touches()
	var dist := (t[0] as Vector2).distance_to(t[1])
	var mid := ((t[0] as Vector2) + (t[1] as Vector2)) * 0.5
	camera.position -= (mid - _pinch_mid) / camera.zoom
	if _pinch_dist > 1.0 and dist > 1.0:
		_zoom_at(mid, dist / _pinch_dist)
	_pinch_dist = dist
	_pinch_mid = mid
	_clamp_camera()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := _screen_to_world(screen_pos)
	var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	camera.force_update_scroll()
	var after := _screen_to_world(screen_pos)
	camera.position += before - after
	_clamp_camera()


func _clamp_camera() -> void:
	var field := Vector2(sim.field_w, sim.field_h) / M * PX_PER_M
	camera.position = camera.position.clamp(Vector2.ZERO, field)


## Faint 50 m grid so movement and scale are readable.
class _FieldGrid extends Node2D:
	var size_px := Vector2.ZERO

	func _draw() -> void:
		var step := 500.0
		var col := Color(1, 1, 1, 0.06)
		var x := 0.0
		while x <= size_px.x:
			draw_line(Vector2(x, 0), Vector2(x, size_px.y), col, 2.0)
			x += step
		var y := 0.0
		while y <= size_px.y:
			draw_line(Vector2(0, y), Vector2(size_px.x, y), col, 2.0)
			y += step
