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
const TerrainLayer := preload("res://game/terrain_layer.gd")
const Terrain := preload("res://sim/terrain.gd")
const UT := preload("res://sim/unit_types.gd")
const Controls := preload("res://game/controls.gd")
const UiScale := preload("res://game/ui_scale.gd")

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
## Terrain kind for scenarios with generated terrain (Terrain.K_*), or -1
## for the scenario's own (random from the seed for the playable battles).
var terrain_kind := -1
## A ready-made scenario (campaign battles) used instead of scenario_id.
var custom_scenario: Dictionary = {}
## Campaign battle: leaving before the battle is decided needs a second tap
## (the army withdraws and the battle counts as lost); the menu buttons
## read "Back to campaign".
var campaign_mode := false
var _leave_confirm := 0.0

var sim: BattleSim
var camera: Camera2D
var terrain: TerrainLayer
var soldiers: SoldierLayer
var overlay: Overlay
var hud: Hud
var orders: OrderPreview  # queued-but-unapplied orders, for immediate display

var paused := false
var speed_idx := 1
var interactive := true
var bench_mode := false
## Primary selected unit (last one picked), -1 if none.
var selected := -1
## Every selected unit; `selected` is one of them.
var selection: Array[int] = []
## "+ Add" mode: taps on units and cards add to / remove from the selection.
var add_mode := false

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
var _result_shown := false
var _paused_before_book := false

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
# Modifiers of the last left mouse press (Shift / Ctrl / Cmd add to the
# selection; Alt starts a group move) - read from the event itself, which
# is reliable in browsers where key state can be missed.
var _mouse_add := false
var _mouse_alt := false
# Box select (mouse drag on empty ground with nothing selected).
var _box := false
# Group move: three fingers or Alt / G + drag. Units, their start anchors
# and facings, the group centre (sim units), and the gesture's translation
# (world px) and rotation (radians).
var _gm := false            # ghost shown, orders on release
var _gm_pending := false    # three fingers down, not yet past the threshold
var _gm_mouse := false
var _gm_units: Array[int] = []
var _gm_base: Array = []
var _gm_centre := Vector2.ZERO
var _gm_move := Vector2.ZERO
var _gm_rot := 0.0
var _gm_start_mid := Vector2.ZERO
var _gm_start_ang: Array = []
var _gm_start_keys: Array = []
var _gm_mouse_start := Vector2.ZERO
# Long press on a unit on the field opens its unit book page.
var _field_lp_start := -1.0
var _paused_before_controls := false
const GM_MOVE_PX := 24.0      # three-finger movement before the ghost appears
const GM_TURN_RAD := 0.14     # ... or this much twist (8 degrees)
const GM_STEP := PI / 12.0    # wheel / Q / E turn step (15 degrees)
const PAN_SPEED := 900.0      # screen px per second for keyboard panning


func _ready() -> void:
	sim = BattleSim.new()
	var scn := custom_scenario if not custom_scenario.is_empty() else Scenarios.make(scenario_id)
	if terrain_kind >= 0 and scn.has("terrain"):
		scn["terrain"]["kind"] = terrain_kind
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--force-terrain="):
			# Testing aid: generated terrain of this kind on any scenario.
			scn["terrain"] = {"kind": int(a.get_slice("=", 1))}
	sim.setup(scn, seed_value)
	bench_mode = sim.is_ai_side(0) and sim.is_ai_side(1)
	interactive = not sim.is_ai_side(PLAYER_SIDE)

	# Ground: height shading, contours and the faint 50 m grid in one shader.
	terrain = TerrainLayer.new()
	add_child(terrain)
	terrain.setup(sim, PX_PER_M)

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

	hud = Hud.new()
	add_child(hud)
	hud.build(sim, PLAYER_SIDE, interactive)
	if campaign_mode:
		hud.result_menu_button.text = "Back to campaign"
		hud.menu_button.text = "Leave"
	hud.set_stats_expanded(bench_mode)  # benchmarks show the full readout
	_fit_camera()
	hud.card_pressed.connect(_on_card)
	hud.pause_pressed.connect(_toggle_pause)
	hud.speed_pressed.connect(_cycle_speed)
	hud.menu_pressed.connect(_on_menu)
	hud.run_pressed.connect(_toggle_run)
	hud.halt_pressed.connect(_halt)
	hud.fire_pressed.connect(_toggle_fire)
	hud.skirmish_pressed.connect(_toggle_skirmish)
	hud.deploy_pressed.connect(_toggle_deploy)
	hud.refill_pressed.connect(_toggle_refill)
	hud.withdraw_pressed.connect(_withdraw)
	hud.withdraw_all_pressed.connect(_withdraw_all)
	hud.group_pressed.connect(_select_group)
	hud.add_toggled.connect(func(on: bool):
		add_mode = on
		_count("add_mode_on" if on else "add_mode_off"))
	hud.orders_toggled.connect(_on_orders_toggled)
	hud.book_pressed.connect(func(): _open_book(-1, "book_open"))
	hud.card_long_pressed.connect(func(u: int): _open_book(sim.u_type[u], "book_open_card"))
	hud.book.closed.connect(_on_book_closed)
	hud.deselect_pressed.connect(func():
		_count("deselect_button")
		_gm_cancel()
		_select(-1))
	hud.controls_pressed.connect(_open_controls)
	hud.controls.closed.connect(func(): _set_paused(_paused_before_controls))
	hud.orders_button.set_pressed_no_signal(show_all_orders)
	hud.set_orders_text(show_all_orders)
	overlay.show_all_orders = show_all_orders
	overlay.player_side = PLAYER_SIDE
	hud.update_cards(sim)
	_select(-1)
	_update_speed_text()
	_apply_debug_args()
	_hash_text = "%08x" % sim.state_hash()
	_tele = get_node_or_null("/root/Telemetry")
	if _tele != null:
		_tele.page_hiding.connect(_on_page_hiding)
	_start_msec = Time.get_ticks_msec()
	_reset_window()
	_t("scenario_start", {"scenario": scenario_id, "seed": seed_value, "terrain": sim.ter_info,
		"terrain_build_ms": terrain.build_ms, "soldiers": sim.n,
		"units": sim.n_units, "bench": bench_mode, "interactive": interactive,
		"speed": SPEEDS[speed_idx], "start_tick": sim.tick, "hash_at_start": _hash_text})


## Testing aids (desktop only): -- --skip-ticks=N --cam=x_m,y_m --zoom=Z
## --select=U[,U...] --pause fast-forward the sim and frame the camera for
## screenshots; --cam-unit=U centres on a unit after the skip; --attack=U:T
## gives unit U an attack order on unit T; --refill=U puts battery U into
## its refill mode (80 ticks run).
func _apply_debug_args() -> void:
	for a in OS.get_cmdline_user_args():
		var v := a.get_slice("=", 1)
		if a.begins_with("--skip-ticks="):
			for t in int(v):
				sim.step()
			soldiers.upload()
			soldiers.set_alpha(1.0)
		elif a.begins_with("--cam="):
			camera.position = Vector2(float(v.get_slice(",", 0)), float(v.get_slice(",", 1))) * PX_PER_M
		elif a.begins_with("--cam-unit="):
			var cu := int(v)
			camera.position = Vector2(sim.u_cx[cu], sim.u_cy[cu]) / M * PX_PER_M
		elif a.begins_with("--zoom="):
			camera.zoom = Vector2.ONE * float(v)
		elif a == "--pause":
			_toggle_pause()
		elif a.begins_with("--select="):
			var first := true
			for part in v.split(","):
				if first:
					_select(int(part))
					first = false
				else:
					_toggle_in_selection(int(part))
		elif a.begins_with("--refill="):
			# --refill=U tells battery U to refill (it settles in over the
			# following ticks; combine with --skip-ticks to see it).
			sim.queue_order(BattleSim.make_refill_order(sim.tick, int(v), 1))
			for t in 80:
				sim.step()
			soldiers.upload()
		elif a.begins_with("--attack="):
			# --attack=U:T orders unit U to attack (shoot) unit T.
			_queue(BattleSim.make_attack_order(0, int(v.get_slice(":", 0)), int(v.get_slice(":", 1)), 0))
		elif a.begins_with("--demo-ghost="):
			# --demo-ghost=deg: the main line (no missiles) picked up as a
			# group, moved 60 m ahead and turned; for screenshots.
			_select(-1)
			for u in sim.n_units:
				if sim.u_side[u] == PLAYER_SIDE and sim.u_cls[u] != UT.CLS_MISSILE and sim.u_cls[u] != UT.CLS_ART:
					if selection.is_empty():
						_select(u)
					else:
						_toggle_in_selection(u)
			_gm_begin()
			_gm_rot = deg_to_rad(float(v))
			_gm_move = Vector2(0, -60.0 * PX_PER_M)
			_gm_update()
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
	if campaign_mode and sim.winner < 0 and _leave_confirm <= 0.0:
		_leave_confirm = 3.0
		hud.banner.text = "Leave? Your army withdraws (a defeat). Tap again."
		hud.banner.visible = true
		return
	_end_scenario("menu")
	exit_requested.emit()


## True once the battle has a winner (a campaign result can be applied).
func is_decided() -> bool:
	return sim.winner >= 0


## Frame both armies in the part of the screen the HUD leaves clear (below
## the top buttons, above the group bar and unit cards).
func _fit_camera() -> void:
	var vp := get_viewport_rect().size
	var lo := Vector2(sim.field_w, sim.field_h)
	var hi := Vector2.ZERO
	for u in sim.n_units:
		lo = lo.min(Vector2(sim.u_minx[u], sim.u_miny[u]))
		hi = hi.max(Vector2(sim.u_maxx[u], sim.u_maxy[u]))
	lo = lo / M * PX_PER_M
	hi = hi / M * PX_PER_M
	var size := (hi - lo).max(Vector2(PX_PER_M * 40.0, PX_PER_M * 40.0))
	var top := hud.top_height()
	var bottom := hud.bottom_height()
	var clear := Rect2(0.0, top, vp.x, maxf(vp.y - top - bottom, vp.y * 0.3))
	var z := minf(clear.size.x / (size.x * 1.15), clear.size.y / (size.y * 1.25))
	z = clampf(z, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2.ONE * z
	# camera.position is the world point at the viewport centre.
	camera.position = (lo + hi) * 0.5 + (vp * 0.5 - clear.get_center()) / z


# ------------------------------------------------------------- stepping ---

func _process(delta: float) -> void:
	if _leave_confirm > 0.0:
		_leave_confirm -= delta
		if _leave_confirm <= 0.0 and sim.winner < 0:
			hud.banner.visible = false
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
			soldiers.upload()
			_upload_ms = (Time.get_ticks_usec() - t0) / 1000.0
	soldiers.set_alpha(clampf(_acc / TICK_SEC, 0.0, 1.0))
	_keys_held(delta)
	orders.refresh()  # drop orders the sim has applied
	# Redrawn every frame, paused or not, so order changes show at once.
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
		_refresh_actions()
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
	var lost := false
	for u in selection:
		if sim.u_state[u] != BattleSim.U_READY:
			lost = true
	if lost:
		_prune_selection()
	if sim.ended != 0 and not _result_shown and not bench_mode:
		_result_shown = true
		var secs: int = maxi(sim.decided_tick, 0) / 10
		hud.banner.visible = false
		hud.show_result(sim.result(), "%s   (decided after %d:%02d)" % [hud.banner.text, secs / 60, secs % 60], PLAYER_SIDE)
		_t("battle_result", {"scenario": scenario_id, "tick": sim.tick, "result": sim.result()})
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
	hud.set_stats("%d fps  %d:%02d" % [Engine.get_frames_per_second(), sim.tick / 600, (sim.tick / 10) % 60],
		"FPS %d   sim %.2f ms avg / %.2f worst (2 s)   upload %.2f ms\nsoldiers %d  (%d v %d)   missiles %d   tick %d   hash %s\n%s   seed %d" % [
		Engine.get_frames_per_second(), avg, worst, _upload_ms, a0 + a1, a0, a1,
		sim.projectiles_in_flight(), sim.tick, _hash_text, terrain_name(sim), seed_value])


## "Terrain: Ridge" etc. for the readout and the result.
static func terrain_name(p_sim) -> String:
	if p_sim.ter_on == 0:
		return "Terrain: flat"
	var k: int = p_sim.ter_info.get("kind", 0)
	return "Terrain: %s" % Terrain.KIND_NAMES[k].to_lower()


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
	var tname: String = ORDER_NAMES.get(int(order["type"]), "other")
	_player_orders += 1
	_orders_by_type[tname] = int(_orders_by_type.get(tname, 0)) + 1
	if _order_events < MAX_ORDER_EVENTS:
		_order_events += 1
		_t("order", {"type": tname, "tick": sim.tick, "unit": int(order.get("unit", -1)),
			"run": int(order.get("run", 0)), "group": selection.size()})


const ORDER_NAMES := {BattleSim.ORDER_MOVE: "move", BattleSim.ORDER_ATTACK: "attack",
	BattleSim.ORDER_HALT: "halt", BattleSim.ORDER_RUN: "run", BattleSim.ORDER_FIRE: "fire",
	BattleSim.ORDER_SKIRMISH: "skirmish", BattleSim.ORDER_WITHDRAW: "withdraw",
	BattleSim.ORDER_WITHDRAW_ALL: "withdraw_all", BattleSim.ORDER_DEPLOY: "deploy",
	BattleSim.ORDER_REFILL: "refill"}


## Select only unit u (-1: clear the selection).
func _select(u: int) -> void:
	selection.clear()
	if u >= 0:
		selection.append(u)
	selected = u
	_selection_changed()


## Add u to the selection, or remove it if it is already in.
func _toggle_in_selection(u: int) -> void:
	if selection.has(u):
		selection.erase(u)
		if selected == u:
			selected = selection[selection.size() - 1] if not selection.is_empty() else -1
	else:
		selection.append(u)
		selected = u
	_selection_changed()


func _prune_selection() -> void:
	var keep: Array[int] = []
	for u in selection:
		if sim.u_state[u] == BattleSim.U_READY:
			keep.append(u)
	selection = keep
	if not selection.has(selected):
		selected = selection[selection.size() - 1] if not selection.is_empty() else -1
	_selection_changed()


func _selection_changed() -> void:
	# Primary first so the overlay knows which unit gets the RUN label.
	var ordered: Array[int] = []
	if selected >= 0:
		ordered.append(selected)
	for u in selection:
		if u != selected:
			ordered.append(u)
	overlay.selected_units = ordered
	var flags := {}
	for u in selection:
		flags[u] = true
	soldiers.selected_units = flags
	soldiers.upload()
	_refresh_actions()
	overlay.queue_redraw()


## Action button states from the predicted orders of the selection.
## Artillery never runs or skirmishes; only it has the Deploy toggle.
func _refresh_actions() -> void:
	var run := -1
	var fire := -1
	var skirm := -1
	var deploy := -1
	var refill := -1
	for u in selection:
		var art := UT.cls(sim.u_type[u]) == UT.CLS_ART
		if not art:
			run = maxi(run, 1 if orders.value(u, "run") != 0 else 0)
		if UT.stat(sim.u_type[u], "m_ammo") > 0:
			fire = maxi(fire, orders.value(u, "fire"))
			if not art:
				skirm = maxi(skirm, orders.value(u, "skirm"))
		if art:
			deploy = maxi(deploy, orders.value(u, "deploy"))
			refill = maxi(refill, orders.value(u, "refill"))
	if selection.is_empty():
		run = 0
	hud.set_selection(selection, run, fire, skirm, deploy, refill)


## Group buttons: every ready player unit of a class.
func _select_group(kind: String) -> void:
	if not interactive:
		return
	_count("group_" + kind)
	selection.clear()
	selected = -1
	for u in sim.n_units:
		if sim.u_side[u] != PLAYER_SIDE or sim.u_state[u] != BattleSim.U_READY:
			continue
		var c := UT.cls(sim.u_type[u])
		# Artillery goes with the missile troops: both shoot, take Fire
		# orders and stand behind the line.
		var take := kind == "all" or (kind == "inf" and (c == UT.CLS_INF or c == UT.CLS_PIKE)) \
			or (kind == "missile" and (c == UT.CLS_MISSILE or c == UT.CLS_ART)) \
			or (kind == "cav" and c == UT.CLS_CAV)
		if take:
			selection.append(u)
	if not selection.is_empty():
		selected = selection[0]
	_selection_changed()


## Unit book over the battle. Solo play: opening it pauses, closing it
## restores the pause state from before.
func _open_book(ty: int, counter: String) -> void:
	_count(counter)
	_t("book_open", {"from": counter, "unit_type": ty, "tick": sim.tick})
	if not hud.book.visible:
		_paused_before_book = paused
		_set_paused(true)
	hud.book.open(ty)
	overlay.preview_on = false
	_dragging = false
	_touches.clear()
	_primary = -1
	_gesture_multi = false


func _on_book_closed() -> void:
	_set_paused(_paused_before_book)


func _set_paused(on: bool) -> void:
	paused = on
	hud.pause_button.text = "Play" if paused else "Pause"


func _on_card(u: int) -> void:
	if hud.suppress_card == u:
		# Release of a long press that opened the unit book: no selection.
		hud.suppress_card = -1
		_selection_changed()  # undo the card's toggle
		return
	if not interactive or sim.u_state[u] != BattleSim.U_READY:
		_selection_changed()  # undo the card's toggle
		return
	var add := add_mode or hud.card_mod_add
	_count("card_add" if add else "card_select")
	if add:
		_toggle_in_selection(u)
		return
	if selected == u and selection.size() == 1:
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
	if selection.is_empty():
		return
	var any_off := false
	for u in selection:
		if orders.value(u, "run") == 0:
			any_off = true
	for u in selection:
		_queue(BattleSim.make_run_order(0, u, 1 if any_off else 0))
	_refresh_actions()


func _halt() -> void:
	for u in selection:
		_queue(BattleSim.make_halt_order(0, u))


## Fire at will on/off for the missile units in the selection.
func _toggle_fire() -> void:
	var any_on := false
	for u in selection:
		if UT.stat(sim.u_type[u], "m_ammo") > 0 and orders.value(u, "fire") != 0:
			any_on = true
	for u in selection:
		if UT.stat(sim.u_type[u], "m_ammo") > 0:
			_queue(BattleSim.make_fire_order(0, u, 0 if any_on else 1))
	_refresh_actions()


func _toggle_skirmish() -> void:
	var any_on := false
	for u in selection:
		if _skirmisher(u) and orders.value(u, "skirm") != 0:
			any_on = true
	for u in selection:
		if _skirmisher(u):
			_queue(BattleSim.make_skirmish_order(0, u, 0 if any_on else 1))
	_refresh_actions()


func _skirmisher(u: int) -> bool:
	return UT.stat(sim.u_type[u], "m_ammo") > 0 and UT.cls(sim.u_type[u]) != UT.CLS_ART


## Artillery in the selection: pack up if any battery wants to be set up,
## otherwise set them all up.
func _toggle_deploy() -> void:
	var any_on := false
	for u in selection:
		if UT.cls(sim.u_type[u]) == UT.CLS_ART and orders.value(u, "deploy") != 0:
			any_on = true
	for u in selection:
		if UT.cls(sim.u_type[u]) == UT.CLS_ART:
			_queue(BattleSim.make_deploy_order(0, u, 0 if any_on else 1))
	_refresh_actions()


## Artillery in the selection: stop refilling if any battery is, otherwise
## start refilling them all.
func _toggle_refill() -> void:
	var any_on := false
	for u in selection:
		if UT.cls(sim.u_type[u]) == UT.CLS_ART and orders.value(u, "refill") != 0:
			any_on = true
	for u in selection:
		if UT.cls(sim.u_type[u]) == UT.CLS_ART:
			_queue(BattleSim.make_refill_order(0, u, 0 if any_on else 1))
	_refresh_actions()


func _withdraw() -> void:
	for u in selection:
		_queue(BattleSim.make_withdraw_order(0, u))


func _withdraw_all() -> void:
	if not interactive:
		return
	_queue(BattleSim.make_withdraw_all_order(0, PLAYER_SIDE))


func _shift_held() -> bool:
	return _mouse_add or Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL)


func _open_controls() -> void:
	_count("controls_open")
	if not hud.controls.visible:
		_paused_before_controls = paused
		_set_paused(true)
	hud.controls.open()
	_gm_cancel()
	overlay.preview_on = false
	_dragging = false
	_touches.clear()
	_primary = -1
	_gesture_multi = false


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
		if add_mode or _shift_held():
			_toggle_in_selection(u)
		elif selected == u and selection.size() == 1 and not double:
			_select(-1)
		else:
			_select(u)
		return
	if selection.is_empty():
		_count("tap_nothing_selected")
		return
	if u >= 0:
		# Enemy: attack (missile troops shoot it; double tap = charge at the run).
		for s in selection:
			_queue(BattleSim.make_attack_order(0, s, u, 1 if double else orders.value(s, "run")))
		return
	var dest := w / PX_PER_M * M
	if selection.size() == 1:
		# Ground: move there keeping frontage, facing the direction of travel.
		var ax: int = orders.value(selected, "ax")
		var ay: int = orders.value(selected, "ay")
		var dx := dest.x - ax
		var dy := dest.y - ay
		var face: int = orders.value(selected, "face")
		if dx * dx + dy * dy > 4.0 * M * M:
			face = int(round(atan2(dy, dx) * 1024.0 / TAU)) & 1023
		var width: int = BattleSim.files_to_width(orders.value(selected, "files"), sim.u_type[selected])
		_queue(BattleSim.make_move_order(0, selected, int(dest.x), int(dest.y), face, width,
			1 if double else orders.value(selected, "run")))
		return
	_group_move(dest, double)


## Move the whole selection to `dest` (sim units), keeping the units'
## positions relative to each other, rotated so the group faces the way it
## travels (relative to the primary unit's facing).
func _group_move(dest: Vector2, double: bool) -> void:
	_count("group_move")
	var cx := 0.0
	var cy := 0.0
	for u in selection:
		cx += orders.value(u, "ax")
		cy += orders.value(u, "ay")
	cx /= selection.size()
	cy /= selection.size()
	var d := dest - Vector2(cx, cy)
	var ref: int = orders.value(selected, "face")
	var turn := 0
	if d.length_squared() > 4.0 * M * M:
		var want := int(round(atan2(d.y, d.x) * 1024.0 / TAU)) & 1023
		turn = ((want - ref + 512) & 1023) - 512
	var rot := turn * TAU / 1024.0
	for u in selection:
		var rel := Vector2(orders.value(u, "ax") - cx, orders.value(u, "ay") - cy).rotated(rot)
		var p := dest + rel
		var face: int = (orders.value(u, "face") + turn) & 1023
		var width: int = BattleSim.files_to_width(orders.value(u, "files"), sim.u_type[u])
		_queue(BattleSim.make_move_order(0, u, int(p.x), int(p.y), face, width,
			1 if double else orders.value(u, "run")))


func _finish_line(double_run: bool) -> void:
	if selection.is_empty() or not overlay.preview_ok:
		_count("line_too_short")
		return
	_count("line_drag" if selection.size() == 1 else "line_drag_group")
	for p in overlay.preview_group():
		var u: int = p["unit"]
		var c: Vector2 = p["centre"] / PX_PER_M * M
		_queue(BattleSim.make_move_order(0, u, int(c.x), int(c.y), p["facing"], p["width"],
			1 if double_run else orders.value(u, "run")))


func _pick_unit(w: Vector2) -> int:
	var x := int(w.x / PX_PER_M * M)
	var y := int(w.y / PX_PER_M * M)
	var margin := int(2.5 * M)
	var best := -1
	var best_d := 0
	# The symbol marker above each unit is a hit target first (generous on
	# touch screens); a tap on a marker wins over a unit's ground box under
	# it, since markers float over neighbouring units when zoomed out.
	var mr := maxf(Overlay.MARKER_MIN_R, Overlay.MARKER_SCREEN_R / camera.zoom.x)
	var hit_k := 2.3 if UiScale.is_touch() else 1.7
	var marker_r := int(mr * hit_k / PX_PER_M * M)
	var lift := int(2.2 * mr / PX_PER_M * M)
	for u in sim.n_units:
		if sim.u_state[u] >= BattleSim.U_DESTROYED:
			continue
		var mdx: int = x - sim.u_cx[u]
		var mdy: int = y - (sim.u_cy[u] - lift)
		var md := mdx * mdx + mdy * mdy
		if md <= marker_r * marker_r and (best < 0 or md < best_d):
			best = u
			best_d = md
	if best >= 0:
		return best
	for u in sim.n_units:
		if sim.u_state[u] >= BattleSim.U_DESTROYED:
			continue
		var in_box: bool = x >= sim.u_minx[u] - margin and x <= sim.u_maxx[u] + margin \
			and y >= sim.u_miny[u] - margin and y <= sim.u_maxy[u] + margin
		if not in_box:
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


func _input(event: InputEvent) -> void:
	# Modifiers come from the mouse event itself (key state can be missed by
	# the browser). The emulated touch of a click is handled at release, after
	# this has run.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_mouse_add = mb.shift_pressed or mb.ctrl_pressed or mb.meta_pressed
			_mouse_alt = mb.alt_pressed or Input.is_key_pressed(KEY_G)
		if _gm and mb.pressed:
			# While moving a group: wheel turns it, right click cancels.
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_gm_turn(-GM_STEP)
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_gm_turn(GM_STEP)
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				_count("group_move_cancelled")
				_gm_cancel()
				get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if hud.book.visible or hud.controls.visible:
		return  # the book and the controls page are modal; they handle their own keys
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
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			# Right click on a unit (or its symbol): its unit book page.
			var u := _pick_unit(_screen_to_world(mb.position))
			if u >= 0:
				_open_book(sim.u_type[u], "book_open_field")
				return
			_mouse_pan = true
			_count("mouse_pan")
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
		_on_key(event as InputEventKey)


## Keyboard shortcuts, from the controls table (game/controls.gd).
func _on_key(e: InputEventKey) -> void:
	var act := Controls.action_for_key(e, "battle")
	if act != "":
		_count("key_" + act)
	match act:
		"pause":
			_toggle_pause()
		"speed_up":
			speed_idx = mini(speed_idx + 1, SPEEDS.size() - 1)
			_update_speed_text()
		"speed_down":
			speed_idx = maxi(speed_idx - 1, 0)
			_update_speed_text()
		"select_all":
			_select_group("all")
		"select_inf":
			_select_group("inf")
		"select_missile":
			_select_group("missile")
		"select_cav":
			_select_group("cav")
		"deselect":
			if _gm or _gm_pending:
				_count("group_move_cancelled")
				_gm_cancel()
			else:
				_select(-1)
		"run":
			_toggle_run()
		"halt":
			_halt()
		"fire":
			_toggle_fire()
		"skirmish":
			_toggle_skirmish()
		"deploy":
			_toggle_deploy()
		"refill":
			_toggle_refill()
		"orders_overlay":
			hud.orders_button.button_pressed = not hud.orders_button.button_pressed
		"group_rotate_left":
			_gm_turn(-GM_STEP)
		"group_rotate_right":
			_gm_turn(GM_STEP)
		"readout":
			hud.set_stats_expanded(not hud.stats_expanded)
		"book":
			_open_book(sim.u_type[selected] if selected >= 0 else -1, "book_open_key")
		"controls":
			_open_controls()
		"zoom_in":
			_zoom_at(get_viewport_rect().size * 0.5, 1.25)
		"zoom_out":
			_zoom_at(get_viewport_rect().size * 0.5, 0.8)
		"fullscreen":
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Held keys: W A S D / arrows pan.
func _keys_held(delta: float) -> void:
	if hud.book.visible or hud.controls.visible:
		return
	var v := Vector2.ZERO
	if Controls.held("pan_left"):
		v.x -= 1
	if Controls.held("pan_right"):
		v.x += 1
	if Controls.held("pan_up"):
		v.y -= 1
	if Controls.held("pan_down"):
		v.y += 1
	if v != Vector2.ZERO:
		camera.position += v * PAN_SPEED * delta / camera.zoom
		_clamp_camera()
	# Long press on a unit on the field: its unit book page.
	if _primary >= 0 and not _dragging and not _gesture_multi and _field_lp_start > 0.0 \
			and Time.get_ticks_msec() / 1000.0 - _field_lp_start >= hud.LONG_PRESS_SEC:
		_field_lp_start = -1.0
		var u := _pick_unit(_screen_to_world(_press_pos))
		if u >= 0:
			_open_book(sim.u_type[u], "book_open_longpress")


func _on_touch(e: InputEventScreenTouch) -> void:
	var is_mouse := e.device == InputEvent.DEVICE_ID_EMULATION
	if e.pressed:
		if hud.is_over_ui(e.position):
			_count("touch_on_ui")
			return
		if not is_mouse:
			_mouse_add = false
			_mouse_alt = false
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_primary = e.index
			_press_pos = e.position
			_dragging = false
			_gesture_multi = false
			_field_lp_start = Time.get_ticks_msec() / 1000.0 if not is_mouse else -1.0
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
			_box_end(false)
			if _touches.size() == 3 and not _gm and interactive and not selection.is_empty():
				_gm_arm()
			elif _touches.size() >= 4 and (_gm or _gm_pending):
				_count("group_move_cancelled")
				_gm_cancel()
			_start_pinch()
		return
	if not _touches.has(e.index):
		return
	_touches.erase(e.index)
	if _gm and not _gm_mouse:
		# Lifting a finger places the group.
		_gm_commit()
	_gm_pending = false
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
		if _gm and _gm_mouse:
			_gm_commit()
			return
		if _box:
			_box_end(true)
			return
		if not overlay.preview_on:
			_count("pan_drag")
		if overlay.preview_on:
			overlay.preview_on = false
			_finish_line(false)
		return
	if _field_lp_start < 0.0 and not is_mouse:
		return  # the long press opened the unit book
	_field_lp_start = -1.0
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
		if _gm_pending or _gm:
			_gm_touch_update()
			if _gm:
				return
		_update_pinch()
		return
	if e.index != _primary:
		return
	var is_mouse := e.device == InputEvent.DEVICE_ID_EMULATION
	if not _dragging and e.position.distance_to(_press_pos) > DRAG_THRESHOLD:
		_dragging = true
		_field_lp_start = -1.0
		if is_mouse and _mouse_alt and interactive and not selection.is_empty():
			# Alt (or G) + drag: move the selection as it stands.
			_gm_begin()
			_gm_mouse = true
			_gm_mouse_start = _press_pos
			_count("alt_drag_move")
		elif is_mouse and interactive and (selection.is_empty() or _mouse_add) and _pick_unit(_screen_to_world(_press_pos)) < 0:
			# Mouse drag from empty ground with nothing selected (or Shift):
			# box select.
			_box = true
			overlay.box_on = true
			overlay.box_a = _screen_to_world(_press_pos)
			_count("box_select")
		elif not selection.is_empty() and interactive:
			overlay.preview_on = true
	if not _dragging:
		return
	if _gm and _gm_mouse:
		_gm_move = (e.position - _gm_mouse_start) / camera.zoom.x
		_gm_update()
	elif _box:
		overlay.box_b = _screen_to_world(e.position)
	elif overlay.preview_on:
		overlay.preview_a = _screen_to_world(_press_pos)
		overlay.preview_b = _screen_to_world(e.position)
		overlay.preview_ok = overlay.preview_a.distance_to(overlay.preview_b) >= MIN_LINE_M * PX_PER_M
	else:
		# No unit selected: one-finger drag pans.
		camera.position -= e.relative / camera.zoom
		_clamp_camera()


# ------------------------------------------------------------ box select ---

func _box_end(apply: bool) -> void:
	if not _box:
		return
	_box = false
	overlay.box_on = false
	if not apply:
		return
	var rect := Rect2(overlay.box_a, overlay.box_b - overlay.box_a).abs()
	if not _mouse_add:
		_select(-1)
	var any := false
	for u in sim.n_units:
		if sim.u_side[u] != PLAYER_SIDE or sim.u_state[u] != BattleSim.U_READY:
			continue
		var c := Vector2(sim.u_cx[u], sim.u_cy[u]) / M * PX_PER_M
		if rect.has_point(c) and not selection.has(u):
			if not any and selection.is_empty():
				_select(u)
			else:
				_toggle_in_selection(u)
			any = true


# ----------------------------------------------------------- group move ---

## Three fingers are down with units selected: remember where, and wait for
## a clear movement or twist before showing the ghost (so a pinch that
## briefly gains a third finger issues nothing).
func _gm_arm() -> void:
	_gm_pending = true
	var keys := _touches.keys()
	keys.sort()
	_gm_start_keys = keys.slice(0, 3)
	_gm_start_mid = _three_mid()
	_gm_start_ang = []
	for k in _gm_start_keys:
		_gm_start_ang.append(((_touches[k] as Vector2) - _gm_start_mid).angle())


func _three_mid() -> Vector2:
	var m := Vector2.ZERO
	for k in _gm_start_keys:
		m += _touches[k]
	return m / 3.0


func _gm_touch_update() -> void:
	for k in _gm_start_keys:
		if not _touches.has(k):
			return
	var mid := _three_mid()
	var rot := 0.0
	for i in 3:
		var a := ((_touches[_gm_start_keys[i]] as Vector2) - mid).angle()
		rot += wrapf(a - float(_gm_start_ang[i]), -PI, PI)
	rot /= 3.0
	var move := mid - _gm_start_mid
	if _gm_pending and (move.length() > GM_MOVE_PX or absf(rot) > GM_TURN_RAD):
		_gm_pending = false
		_gm_begin()
		_count("three_finger_move")
	if _gm:
		_gm_move = move / camera.zoom.x
		_gm_rot = rot
		_gm_update()


func _gm_begin() -> void:
	_gm_units.clear()
	_gm_base.clear()
	var c := Vector2.ZERO
	for u in selection:
		if sim.u_state[u] != BattleSim.U_READY:
			continue
		_gm_units.append(u)
		var b := {"ax": orders.value(u, "ax"), "ay": orders.value(u, "ay"), "face": orders.value(u, "face"),
			"files": orders.value(u, "files")}
		_gm_base.append(b)
		c += Vector2(int(b["ax"]), int(b["ay"]))
	if _gm_units.is_empty():
		return
	_gm_centre = c / _gm_units.size()
	_gm_move = Vector2.ZERO
	_gm_rot = 0.0
	_gm = true
	_gm_mouse = false
	overlay.preview_on = false
	_gm_update()


func _gm_turn(step: float) -> void:
	if not _gm:
		return
	_gm_rot += step
	_count("group_rotate")
	_gm_update()


## Destination of each unit: its anchor rotated about the group centre and
## moved; facing turned by the same angle; frontage kept.
func _gm_dest() -> Array:
	var out: Array = []
	var turn := int(round(_gm_rot * 1024.0 / TAU))
	var mv := _gm_move / PX_PER_M * M
	for i in _gm_units.size():
		var b: Dictionary = _gm_base[i]
		var rel := Vector2(int(b["ax"]), int(b["ay"])) - _gm_centre
		var p := _gm_centre + rel.rotated(_gm_rot) + mv
		out.append({"unit": _gm_units[i], "x": int(p.x), "y": int(p.y),
			"face": (int(b["face"]) + turn) & 1023, "files": int(b["files"])})
	return out


func _gm_update() -> void:
	var gh: Array = []
	for d in _gm_dest():
		gh.append({"unit": d["unit"], "front": Vector2(d["x"], d["y"]) / M * PX_PER_M,
			"face": d["face"], "files": d["files"]})
	overlay.ghosts = gh
	var deg := int(round(rad_to_deg(_gm_rot)))
	overlay.ghost_hint = "turn %+d deg" % deg if deg != 0 else ""
	overlay.queue_redraw()


func _gm_commit() -> void:
	if not _gm:
		return
	if _gm_move.length() * camera.zoom.x < 6.0 and absf(_gm_rot) < 0.03:
		_gm_cancel()
		return
	if absf(_gm_rot) >= 0.03:
		_count("group_rotate_placed")
	for d in _gm_dest():
		var u: int = d["unit"]
		if sim.u_state[u] != BattleSim.U_READY:
			continue
		var width: int = BattleSim.files_to_width(int(d["files"]), sim.u_type[u])
		_queue(BattleSim.make_move_order(0, u, int(d["x"]), int(d["y"]), int(d["face"]), width,
			orders.value(u, "run")))
	_gm_cancel()


func _gm_cancel() -> void:
	_gm = false
	_gm_pending = false
	_gm_mouse = false
	overlay.ghosts = []
	overlay.ghost_hint = ""
	overlay.queue_redraw()


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
