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
const TreeLayer := preload("res://game/tree_layer.gd")
const CityLayer := preload("res://game/city_layer.gd")
const MapGen := preload("res://sim/mapgen.gd")
const Terrain := preload("res://sim/terrain.gd")
const UT := preload("res://sim/unit_types.gd")
const Controls := preload("res://game/controls.gd")
const UiScale := preload("res://game/ui_scale.gd")
const CoopHud := preload("res://game/coop_hud.gd")
const Lockstep := preload("res://sim/lockstep.gd")
const CData := preload("res://campaign/cdata.gd")
const FM := preload("res://sim/fixed_math.gd")

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
## The side this player fights on (0 bottom; head-to-head: 1 for the
## player on the top side).
var player_side := 0
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
## Ground palette for scenarios with generated terrain (MapGen.PAL_*; woods
## follow the palette, MapGen.PALETTE_FOREST), or -1 for the scenario's own.
var ground := -1
## A ready-made scenario (campaign battles) used instead of scenario_id.
var custom_scenario: Dictionary = {}
## Sandbox: battle AI skill for both sides (sim/ai_profile.gd), -1 = the
## scenario's own (campaign battles carry theirs in the scenario).
var ai_skill := -1
## Campaign battle: leaving before the battle is decided needs a second tap
## (the army withdraws and the battle counts as lost); the menu buttons
## read "Back to campaign".
var campaign_mode := false
var _leave_confirm := 0.0
## Live co-op battle (game/net/coop_session.gd, milestone 5), or null: the
## session runs the lockstep layer and owns the sim once the battle starts
## (before that `sim` is a stand-in built from the same scenario for the
## lobby). Orders go through it, only for units this player commands;
## pause and speed are votes.
var coop = null
var coop_hud = null
var coop_region := ""
## Custom battle: CustomSetup.summary() of its setup (telemetry
## "custom_battle" at the end), else empty.
var custom_summary: Dictionary = {}

var sim: BattleSim
var camera: Camera2D
var terrain: TerrainLayer
var city: CityLayer
var trees: TreeLayer
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
	var gr := ground
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--force-terrain="):
			# Testing aid: generated terrain of this kind on any scenario.
			scn["terrain"] = {"kind": int(a.get_slice("=", 1))}
		elif a.begins_with("--ground="):
			gr = int(a.get_slice("=", 1))  # testing aid: ground palette (and its woods)
	if gr >= 0 and scn.has("terrain") and not (scn["terrain"] as Dictionary).has("city"):
		scn["terrain"]["ground"] = gr
		scn["terrain"]["forest"] = MapGen.PALETTE_FOREST[clampi(gr, 0, MapGen.PALETTE_FOREST.size() - 1)]
	if ai_skill >= 0 and not campaign_mode:
		scn["ai_skill"] = [ai_skill, ai_skill]
	sim.setup(scn, seed_value)
	bench_mode = sim.is_ai_side(0) and sim.is_ai_side(1)
	interactive = not sim.is_ai_side(player_side)

	# Ground: height shading, contours and the faint 50 m grid in one shader.
	terrain = TerrainLayer.new()
	add_child(terrain)
	terrain.setup(sim, PX_PER_M)

	# Settlement: buildings, walls, towers (static) and the gates.
	city = CityLayer.new()
	add_child(city)
	city.setup(sim, PX_PER_M)

	soldiers = SoldierLayer.new()
	add_child(soldiers)
	soldiers.setup(sim, PX_PER_M)
	soldiers.probed.connect(_on_soldier_probe)

	# Trees above the soldiers; their canopies fade over men under them.
	trees = TreeLayer.new()
	add_child(trees)
	trees.setup(sim, PX_PER_M)
	if "--no-trees" in OS.get_cmdline_user_args():
		trees.visible = false  # testing aid: frame cost without the trees
	print("map view: terrain %.1f ms, city %.1f ms, %d trees %.1f ms" % [terrain.build_ms, city.build_ms,
		trees.count, trees.build_ms])

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
	hud.build(sim, player_side, interactive)
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
	hud.man_wall_pressed.connect(_man_wall)
	hud.come_down_pressed.connect(_come_down)
	hud.drop_pressed.connect(_drop)
	hud.withdraw_pressed.connect(_withdraw)
	hud.withdraw_all_pressed.connect(_withdraw_all)
	hud.group_pressed.connect(_select_group)
	hud.add_toggled.connect(func(on: bool):
		add_mode = on
		_count("add_mode_on" if on else "add_mode_off"))
	hud.orders_toggled.connect(_on_orders_toggled)
	hud.book_pressed.connect(func(): _open_book(-1, "book_open"))
	hud.card_long_pressed.connect(func(u: int): _open_book(sim.u_type[u], "book_open_card"))
	hud.cards_reordered.connect(func(): _count("card_reorder"))
	hud.book.closed.connect(_on_book_closed)
	hud.deselect_pressed.connect(func():
		_count("deselect_button")
		_gm_cancel()
		_select(-1))
	hud.controls_pressed.connect(_open_controls)
	hud.ready_pressed.connect(_deploy_ready)
	hud.controls.closed.connect(func(): _set_paused(_paused_before_controls))
	if coop != null:
		_coop_ready()
	hud.orders_button.set_pressed_no_signal(show_all_orders)
	hud.set_orders_text(show_all_orders)
	overlay.show_all_orders = show_all_orders
	overlay.player_side = player_side
	hud.update_cards(sim)
	_select(-1)
	_update_speed_text()
	_refresh_deploy()
	_apply_debug_args()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frame-stats="):
			_fs_until = float(a.get_slice("=", 1)) + 3.0
	_hash_text = "%08x" % sim.state_hash()
	_tele = get_node_or_null("/root/Telemetry")
	if _tele != null:
		_tele.page_hiding.connect(_on_page_hiding)
	_start_msec = Time.get_ticks_msec()
	_reset_window()
	_t("scenario_start", {"scenario": scenario_id, "seed": seed_value, "terrain": sim.ter_info,
		"terrain_build_ms": terrain.build_ms, "trees": trees.count, "trees_build_ms": trees.build_ms,
		"city_build_ms": city.build_ms, "soldiers": sim.n,
		"units": sim.n_units, "bench": bench_mode, "interactive": interactive,
		"speed": SPEEDS[speed_idx], "start_tick": sim.tick, "hash_at_start": _hash_text})


## Testing aids (desktop only): -- --ai-both --skip-ticks=N --cam=x_m,y_m --zoom=Z
## --select=U[,U...] --pause fast-forward the sim and frame the camera for
## screenshots; --cam-unit=U centres on a unit after the skip; --attack=U:T
## gives unit U an attack order on unit T; --refill=U puts battery U into
## its refill mode (80 ticks run).
func _apply_debug_args() -> void:
	if "--ai-both" in OS.get_cmdline_user_args():
		sim.ai_sides[0] = 1  # screenshots: the AI fights for both sides
	for a in OS.get_cmdline_user_args():
		var v := a.get_slice("=", 1)
		if a.begins_with("--skip-ticks="):
			for t in int(v):
				sim.step()
			soldiers.upload()
			soldiers.set_alpha(1.0)
			_view_tick()
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
				if sim.u_side[u] == player_side and sim.u_cls[u] != UT.CLS_MISSILE and sim.u_cls[u] != UT.CLS_ART:
					if selection.is_empty():
						_select(u)
					else:
						_toggle_in_selection(u)
			_gm_begin()
			_gm_rot = deg_to_rad(float(v))
			_gm_move = Vector2(0, -60.0 * PX_PER_M)
			_gm_update()
		elif a.begins_with("--demo-wall="):
			# --demo-wall=down|up: the player's first wall unit selected, a
			# pending order down off its wall (down), or (up) brought down
			# first, then a tap on the wall's body; for screenshots (with
			# --pause the order stays pending, so its preview shows).
			var wu := -1
			for u in sim.n_units:
				if sim.u_side[u] == player_side and sim.u_wall[u] > 0:
					wu = u
					break
			if wu < 0:
				continue
			var sg: int = sim.u_wall[wu] - 1
			var inside: Vector2i = sim.wall_inside(sg, sim.u_cx[wu], sim.u_cy[wu])
			if v == "up":
				sim.queue_order(BattleSim.make_move_order(sim.tick, wu, inside.x, inside.y, sim.ws_dir[sg], 10 * 1024, 0))
				for t in 600:
					sim.step()
					if sim.u_wall[wu] == 0 and sim.u_stair[wu] == 0 and sim.u_order[wu] == BattleSim.O_NONE:
						break
				soldiers.upload()
				_view_tick()
			_select(wu)
			camera.position = Vector2(sim.u_cx[wu], sim.u_cy[wu]) / M * PX_PER_M
			if v == "up":
				# A tap on the wall's body (the parapet side), off the walkway.
				var mid := BattleSim.seg_pt(sim, sg, BattleSim.seg_len(sim, sg) / 2)
				var tx: int = mid.x + FM.cos_a(sim.ws_dir[sg]) * 3 * 1024 / 4096
				var ty: int = mid.y + FM.sin_a(sim.ws_dir[sg]) * 3 * 1024 / 4096
				_queue(BattleSim.make_move_order(0, wu, tx, ty, sim.u_face[wu], 10 * 1024, 0))
			else:
				_come_down()
		elif a == "--show-orders":
			hud.orders_button.button_pressed = true
		elif a == "--demo-orders":
			# Every other player unit advances 40 m in a wider line; the rest
			# stay put. For screenshots of the all-orders overlay.
			for u in sim.n_units:
				if sim.u_side[u] == player_side and u % 2 == 0:
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
		if coop != null and _coop_others_in():
			hud.banner.text = "Leave? Your units go to your ally. Tap again."
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
	if coop != null:
		_coop_step(delta)
	elif not paused and not _bench_done:
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
			_view_tick()
			_upload_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if coop == null:
		soldiers.set_alpha(clampf(_acc / TICK_SEC, 0.0, 1.0))
	_keys_held(delta)
	orders.refresh()  # drop orders the sim has applied
	# Redrawn every frame, paused or not, so order changes show at once.
	overlay.zoom = camera.zoom.x
	overlay.queue_redraw()

	if bench_mode and not _bench_done:
		_bench_frames.append(delta)
	if _fs_until > 0.0:
		_frame_stats(delta)

	if _tele != null and not _ended:
		_win_frames.append(delta)
		_win_time += delta
		if _win_time >= TELEMETRY_SAMPLE_SEC:
			_send_perf_sample()

	_card_timer -= delta
	if _card_timer <= 0.0:
		_card_timer = 0.25
		hud.update_cards(sim)
		if coop != null:
			_coop_cards()
		_refresh_actions()
		_update_stats_label()
		_refresh_deploy()


## Testing aid --frame-stats=S: after S seconds (the first 3 skipped) print
## the mean and worst frame time and the time spent in the view's per-tick
## work, then quit.
var _fs_until := 0.0
var _fs_t := 0.0
var _fs_n := 0
var _fs_sum := 0.0
var _fs_max := 0.0


func _frame_stats(delta: float) -> void:
	_fs_t += delta
	if _fs_t < 3.0:
		return
	_fs_n += 1
	_fs_sum += delta
	_fs_max = maxf(_fs_max, delta)
	if _fs_t >= _fs_until:
		print("frame stats: %d frames, mean %.2f ms (%.0f fps), worst %.1f ms; canopy update %d us/tick; trees %d; tick %d" % [
			_fs_n, _fs_sum / _fs_n * 1000.0, _fs_n / _fs_sum, _fs_max * 1000.0, trees.update_us, trees.count, sim.tick])
		get_tree().quit()


## Woods and settlement views after the sim moved: canopy fade under the
## soldiers, the gates.
func _view_tick() -> void:
	trees.update_occupancy()
	city.refresh()


func _do_tick() -> void:
	var t0 := Time.get_ticks_usec()
	sim.step()
	_after_tick((Time.get_ticks_usec() - t0) / 1000.0)


## Bookkeeping after the sim stepped (ms: the step's time).
func _after_tick(ms: float) -> void:
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
	elif sim.city_on != 0 and not selection.is_empty() and sim.tick % 5 == 0:
		_refresh_wall_buttons()  # units walk in and out of reach of a wall
	if sim.ended != 0 and not _result_shown and not bench_mode:
		_result_shown = true
		var secs: int = maxi(sim.decided_tick, 0) / 10
		hud.banner.visible = false
		hud.show_result(sim.result(), "%s   (decided after %d:%02d)" % [hud.banner.text, secs / 60, secs % 60], player_side)
		_t("battle_result", {"scenario": scenario_id, "tick": sim.tick, "result": sim.result()})
		if not custom_summary.is_empty():
			var rs: Dictionary = sim.result()
			_t("custom_battle", {"setup": custom_summary, "winner": sim.winner, "my_side": player_side,
				"online": coop != null, "me": coop.me if coop != null else 0, "tick": sim.tick, "sides": rs["sides"]})
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
	hud.set_stats("%d fps  %d:%02d / %d:%02d" % [Engine.get_frames_per_second(), sim.tick / 600, (sim.tick / 10) % 60,
		sim.time_limit / 600, (sim.time_limit / 10) % 60],
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
	if sim.winner == 2 and sim.decided_tick >= sim.time_limit:
		text = "Draw: the %d minutes are up" % (sim.time_limit / 600)
	if sim.winner == player_side:
		text = "Victory" if interactive else "Blue wins"
	elif sim.winner == 1 - player_side:
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
	hud.bench_label.text += "\nMap view: %d trees (built in %.1f ms), canopy update %d us per tick, city %.1f ms, ground %.1f ms" % [
		trees.count, trees.build_ms, trees.update_us, city.build_ms, terrain.build_ms]
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

## The soldier layer's self-check: pixels drawn around the biggest unit.
func _on_soldier_probe(drawn: int, men: int) -> void:
	print("SOLDIER_PROBE drawn=%d men=%d" % [drawn, men])
	_t("soldier_probe", {"drawn": drawn, "men": men, "tick": sim.tick})


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
	if sim.phase == BattleSim.PHASE_DEPLOY:
		# Deployment: moves become placements (the same gestures: tap, line,
		# group), everything else that would set the army going waits.
		var typ := int(order["type"])
		if typ == BattleSim.ORDER_MOVE:
			var pu := int(order["unit"])
			var width := int(order.get("width", BattleSim.files_to_width(orders.value(pu, "files"), sim.u_type[pu])))
			order = {"type": BattleSim.ORDER_PLACE, "unit": pu, "x": int(order["x"]), "y": int(order["y"]),
				"facing": int(order["facing"]), "files": BattleSim.width_to_files(width, sim.u_alive[pu], sim.u_type[pu])}
			if selection.size() <= 1 and not BattleSim.place_clear(sim, pu, int(order["x"]), int(order["y"]),
					int(order["facing"]) & 1023, int(order["files"])):
				# (Units do not stand inside each other: the sim refuses it too.)
				_count("place_refused")
				overlay.flash("Another unit stands there", Vector2(int(order["x"]), int(order["y"])) / M * PX_PER_M)
				return
		elif typ != BattleSim.ORDER_RUN and typ != BattleSim.ORDER_FIRE and typ != BattleSim.ORDER_SKIRMISH \
				and typ != BattleSim.ORDER_DEPLOY and typ != BattleSim.ORDER_PLACE and typ != BattleSim.ORDER_READY:
			_count("order_in_deployment")
			if selected >= 0:
				overlay.flash("Deployment: place your units; orders wait for the battle",
					Vector2(sim.u_cx[selected], sim.u_cy[selected]) / M * PX_PER_M)
			return
	if coop != null:
		# Live co-op: through the lockstep layer, for our own units only.
		if not coop.can_issue():
			return
		var cu := int(order.get("unit", -1))
		if cu >= 0 and not coop.can_order(cu):
			return
		coop.issue(order)
	else:
		# Solo play: orders apply on the next tick.
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


## Deployment phase: this player is ready (solo: the battle starts).
func _deploy_ready() -> void:
	if sim.phase != BattleSim.PHASE_DEPLOY:
		return
	_count("deploy_ready")
	_t("deploy_ready", {"secs_left": sim.deploy_secs_left(), "scenario": scenario_id})
	if coop != null:
		if coop.can_issue():
			coop.issue({"type": BattleSim.ORDER_READY})
		return
	sim.queue_order({"tick": sim.tick, "type": BattleSim.ORDER_READY, "who": 0})
	if paused:
		_toggle_pause()  # a ready player wants the battle to run


## The deployment bar: countdown, who is ready, Start battle / Ready.
func _refresh_deploy() -> void:
	if sim.phase != BattleSim.PHASE_DEPLOY:
		if hud.deploy_panel.visible:
			hud.set_deploy("", "", false)
			_t("battle_start", {"scenario": scenario_id, "tick": sim.tick})
		return
	var s: int = sim.deploy_secs_left()
	var text := "Deployment  %d:%02d" % [s / 60, s % 60]
	if coop != null and coop.ls != null:
		var me_ready := false
		var parts: Array[String] = []
		for p in coop.ls.active_players():
			var r: bool = (sim.dep_ready & (1 << p)) != 0
			if p == coop.me:
				me_ready = r
			elif r:
				parts.append("%s is ready" % coop.player_name(p))
			else:
				parts.append("Waiting for %s" % coop.player_name(p))
		if not parts.is_empty():
			text += "   " + ", ".join(parts)
		hud.set_deploy(text, "Ready" if not me_ready else "Ready: waiting", not me_ready and coop.can_issue())
	else:
		var pend := false
		for o in sim.pending_orders:
			if int(o["type"]) == BattleSim.ORDER_READY:
				pend = true
		hud.set_deploy(text + "   Place your units in the blue zone", "Start battle", not pend and interactive)


const ORDER_NAMES := {BattleSim.ORDER_MOVE: "move", BattleSim.ORDER_ATTACK: "attack",
	BattleSim.ORDER_HALT: "halt", BattleSim.ORDER_RUN: "run", BattleSim.ORDER_FIRE: "fire",
	BattleSim.ORDER_SKIRMISH: "skirmish", BattleSim.ORDER_WITHDRAW: "withdraw",
	BattleSim.ORDER_WITHDRAW_ALL: "withdraw_all", BattleSim.ORDER_DEPLOY: "deploy",
	BattleSim.ORDER_REFILL: "refill", BattleSim.ORDER_GATE: "gate", BattleSim.ORDER_PLACE: "place",
	BattleSim.ORDER_READY: "ready"}


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
		if sim.u_state[u] == BattleSim.U_READY and _mine(u):
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
		if art and UT.stat(sim.u_type[u], "fixed") == 0:
			# (A tower's engine is always set up and has no baggage.)
			deploy = maxi(deploy, orders.value(u, "deploy"))
			refill = maxi(refill, orders.value(u, "refill"))
	if selection.is_empty():
		run = 0
	hud.set_selection(selection, run, fire, skirm, deploy, refill)
	_refresh_wall_buttons()
	if coop != null:
		var to := _gift_target()
		hud.gift_button.visible = not selection.is_empty() and to >= 0
		if to >= 0:
			hud.gift_button.text = "Gift to " + coop.player_name(to)


## Group buttons: every ready player unit of a class.
func _select_group(kind: String) -> void:
	if not interactive:
		return
	_count("group_" + kind)
	selection.clear()
	selected = -1
	# In the card strip's order (the player may have dragged cards around).
	for u in hud.display_order():
		if sim.u_side[u] != player_side or sim.u_state[u] != BattleSim.U_READY or not _mine(u):
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
	if coop != null:
		return  # co-op: the book and the controls page do not pause the battle
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
	if not _mine(u):
		_selection_changed()
		_not_mine_hint(u)
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
	_count("pause_toggle")
	if coop != null:
		coop.request_pause()
		return
	paused = not paused
	hud.pause_button.text = "Play" if paused else "Pause"


func _cycle_speed() -> void:
	_count("speed_change")
	if coop != null:
		_coop_speed(1, true)
		return
	speed_idx = (speed_idx + 1) % SPEEDS.size()
	_update_speed_text()


func _update_speed_text() -> void:
	var s: float = SPEEDS[speed_idx]
	if coop != null and coop.ls != null:
		s = coop.ls.speed_q / 4.0
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


## Walls: "Man the wall" shows while a selected unit may go up onto a
## stretch within reach (BattleSim.man_wall_target), "Come down" while one
## stands on a wall; "Drop" while one carries siege equipment.
func _refresh_wall_buttons() -> void:
	var man := false
	var down := false
	var drop := false
	if sim.city_on != 0 and sim.ws_x0.size() > 0:
		for u in selection:
			if sim.u_state[u] != BattleSim.U_READY:
				continue
			if BattleSim.carrying(sim, u) != 0:
				drop = true
			if sim.u_wall[u] > 0 and sim.u_stair[u] == 0:
				down = true
			elif sim.u_wall[u] == 0 and sim.u_stair[u] != 1 and BattleSim.man_wall_target(sim, u).z >= 0:
				man = true
	hud.set_wall_buttons(man, down, drop)


## "Drop": each selected unit carrying siege equipment puts it down where
## it stands (anyone's foot can pick it up again).
func _drop() -> void:
	var sent := 0
	for u in selection:
		if sim.u_state[u] == BattleSim.U_READY and BattleSim.carrying(sim, u) != 0:
			_queue({"type": BattleSim.ORDER_DROP, "unit": u})
			sent += 1
	_count("drop")
	if sent > 0 and selected >= 0:
		overlay.flash("Put down: free to fight", Vector2(sim.u_cx[selected], sim.u_cy[selected]) / M * PX_PER_M)


## The piece of siege equipment on the ground under world point w (px), or
## -1: the nearest within 5 m (at least the marker hit radius / 2).
func _equip_at(w: Vector2) -> int:
	if sim.n_eq == 0:
		return -1
	var x := int(w.x / PX_PER_M * M)
	var y := int(w.y / PX_PER_M * M)
	var r := maxi(5 * 1024, _marker_hit_r() / 2)
	var best := -1
	var bd := 0
	for q in sim.n_eq:
		if sim.q_state[q] != BattleSim.Q_GROUND:
			continue
		var dx: int = sim.q_x[q] - x
		var dy: int = sim.q_y[q] - y
		var d := dx * dx + dy * dy
		if d <= r * r and (best < 0 or d < bd):
			best = q
			bd = d
	return best


## A tap on piece q with units selected: the selected unit nearest it that
## may carry it goes and picks it up (one unit a piece).
func _tap_equip(q: int, w: Vector2) -> void:
	var best := -1
	var bd := 0
	var why := ""
	for u in selection:
		var r: String = BattleSim.pickup_refusal(sim, u, q)
		if r != "":
			if why == "" or u == selected:
				why = r
			continue
		var d := FM.approx_len(sim.u_cx[u] - sim.q_x[q], sim.u_cy[u] - sim.q_y[q])
		if best < 0 or d < bd:
			best = u
			bd = d
	_count("equip_pickup" if best >= 0 else "equip_refused")
	if best < 0:
		overlay.flash(why, w)
		return
	_queue({"type": BattleSim.ORDER_PICKUP, "unit": best, "equip": q, "run": orders.value(best, "run")})
	overlay.flash("Picking up the ram" if sim.q_kind[q] == BattleSim.EQ_RAM else "Picking up the ladders", w)


## "Man the wall": each selected unit that may goes up onto the stretch
## within 60 m nearest the enemy, at its point nearest the unit (an ordinary
## move order there: the sim takes it up the stair).
func _man_wall() -> void:
	var sent := 0
	var why := ""
	for u in selection:
		if sim.u_state[u] != BattleSim.U_READY or sim.u_wall[u] > 0:
			continue
		var mt := BattleSim.man_wall_target(sim, u)
		if mt.z < 0:
			continue
		var r: String = orders.wall_refusal(u, mt.x, mt.y)
		if r != "":
			why = r
			continue
		_queue(BattleSim.make_move_order(0, u, mt.x, mt.y, sim.ws_dir[mt.z],
			BattleSim.files_to_width(orders.value(u, "files"), sim.u_type[u]), orders.value(u, "run")))
		sent += 1
	_count("man_wall")
	if sent == 0 and selected >= 0:
		overlay.flash(why if why != "" else "No wall within 60 m that these men can man",
			Vector2(sim.u_cx[selected], sim.u_cy[selected]) / M * PX_PER_M)


## "Come down": each selected unit on a wall goes down its nearer stair to
## the street at its foot (BattleSim.wall_inside), facing out, in its
## normal block.
func _come_down() -> void:
	for u in selection:
		if sim.u_state[u] != BattleSim.U_READY or sim.u_wall[u] == 0:
			continue
		var sg: int = sim.u_wall[u] - 1
		var p: Vector2i = sim.wall_inside(sg, sim.u_cx[u], sim.u_cy[u])
		var files := BattleSim.ground_files(sim.u_type[u], sim.u_alive[u])
		_queue(BattleSim.make_move_order(0, u, p.x, p.y, sim.ws_dir[sg],
			BattleSim.files_to_width(files, sim.u_type[u]), orders.value(u, "run")))
	_count("come_down")


func _withdraw() -> void:
	for u in selection:
		_queue(BattleSim.make_withdraw_order(0, u))


func _withdraw_all() -> void:
	if not interactive:
		return
	_queue(BattleSim.make_withdraw_all_order(0, player_side))


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
	# A tap in a gate's doorway is about the gate: it is tested before the
	# units, so a marker floating over the gate (men on the wall above it)
	# or a unit box cannot steal it. Outside the doorway units pick first and
	# the gate's wider reach is the fallback.
	var door := _gate_doorway(w)
	if door >= 0 and _tap_gate(door, w):
		return
	var u := -1 if door >= 0 else _pick_unit(w)
	if u >= 0 and sim.u_side[u] == player_side:
		if sim.u_state[u] != BattleSim.U_READY:
			_count("tap_on_broken_unit")
			return
		if not _mine(u):
			_not_mine_hint(u)
			return
		_count("tap_select")
		if add_mode or _shift_held():
			_toggle_in_selection(u)
		elif selected == u and selection.size() == 1 and not double:
			_select(-1)
		else:
			_select(u)
		return
	if u < 0 and door < 0:
		var g := _gate_at(w)
		if g >= 0 and _tap_gate(g, w):
			return
	if selection.is_empty():
		_count("tap_nothing_selected")
		return
	if u < 0:
		var q := _equip_at(w)
		if q >= 0:
			_tap_equip(q, w)
			return
	if u >= 0:
		# Enemy: attack (missile troops shoot it; double tap = charge at the run).
		var carriers := 0
		for s in selection:
			if BattleSim.carrying(sim, s) != 0:
				carriers += 1  # carrying siege equipment: no attacking
				continue
			_queue(BattleSim.make_attack_order(0, s, u, 1 if double else orders.value(s, "run")))
		if carriers > 0:
			overlay.flash("Carrying siege equipment: put it down first (Drop) to fight", w)
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
		var why: String = orders.wall_refusal(selected, int(dest.x), int(dest.y))
		if why != "":
			_count("wall_refused")
			overlay.flash(why, w)
			return
		_queue(BattleSim.make_move_order(0, selected, int(dest.x), int(dest.y), face, width,
			1 if double else orders.value(selected, "run")))
		return
	_group_move(dest, double)


## Radius (sim units) of a unit marker's hit circle at the current zoom:
## generous on touch screens. Also the least reach of a gate's doorway.
func _marker_hit_r() -> int:
	var mr := maxf(Overlay.MARKER_MIN_R, Overlay.MARKER_SCREEN_R / camera.zoom.x)
	var hit_k := 2.3 if UiScale.is_touch() else 1.7
	return int(mr * hit_k / PX_PER_M * M)


## Gate whose doorway is under world point w (px), or -1: the opening's own
## rectangle in its frame (half width + 1 m along the wall, the wall's
## thickness + 1.5 m each side across it), widened to at least the marker
## hit radius so it stays a fair touch target when zoomed out. The nearest
## gate wins if two overlap.
func _gate_doorway(w: Vector2) -> int:
	if sim.n_gates == 0:
		return -1
	var x := int(w.x / PX_PER_M * M)
	var y := int(w.y / PX_PER_M * M)
	var touch_r := _marker_hit_r()
	var ry := maxi(sim.wall_t / 2 + 1536, touch_r)
	var best := -1
	var best_d := 0
	for g in sim.n_gates:
		var rx := maxi((sim.g_hw[g] + 1) * int(M), touch_r)
		var f: Vector2i = sim.gate_frame(g, x, y)
		if absi(f.x) <= rx and absi(f.y) <= ry:
			var d := f.x * f.x + f.y * f.y
			if best < 0 or d < best_d:
				best = g
				best_d = d
	return best


## Gate within reach of world point w (px), or -1: wider than the doorway,
## used only when no unit was picked.
func _gate_at(w: Vector2) -> int:
	if sim.n_gates == 0:
		return -1
	var x := w.x / PX_PER_M * M
	var y := w.y / PX_PER_M * M
	var reach_y: int = sim.wall_t / 2 + 4 * 1024
	for g in sim.n_gates:
		var reach_x := int((sim.g_hw[g] + 3) * M)
		var f: Vector2i = sim.gate_frame(g, int(x), int(y))
		if absi(f.x) <= reach_x and absi(f.y) <= reach_y:
			return g
	return -1


## A tap on gate g (w the tap, world px). Defenders: open or close it,
## whatever is selected (the selection stays, nothing moves). Attackers:
## batteries shoot it, foot go to its face and hack at it (cavalry and
## missile troops cannot); an open or broken gate is a move. Returns true if
## the tap was used.
func _tap_gate(g: int, w: Vector2) -> bool:
	var st: int = sim.g_state[g]
	if sim.city_def == player_side:
		if st == BattleSim.GATE_BROKEN:
			overlay.flash("The gate is broken: it cannot be shut", w)
			return true
		var any := -1
		for u in sim.n_units:
			if sim.u_side[u] == player_side and sim.u_state[u] == BattleSim.U_READY and _mine(u):
				any = u
				break
		if any < 0:
			return true
		var close := 1 if st == BattleSim.GATE_OPEN else 0
		if close == 1 and sim.gate_busy(g):
			overlay.flash("Men in the gateway: it cannot be shut now", w)
			return true
		_count("gate_close" if close == 1 else "gate_open")
		_queue({"type": BattleSim.ORDER_GATE, "unit": any, "gate": g, "on": close})
		overlay.flash("Closing the gate" if close == 1 else "Opening the gate", w)
		return true
	if selection.is_empty() or st != BattleSim.GATE_CLOSED:
		return false  # an open or broken gate: a tap there is a move
	var sent := 0
	var refused := 0
	var ram := false
	var iron := not BattleSim.gate_hackable(sim, g)
	var ladders := false
	for u in selection:
		var c := UT.cls(sim.u_type[u])
		var k := BattleSim.carrying(sim, u)
		var inside: bool = sim.u_lq[u] >= 0 and (sim.u_wall[u] > 0 \
			or sim.reach_at(sim.u_ax[u], sim.u_ay[u]) == sim.reach_at(sim.g_ix[g], sim.g_iy[g]))
		var ok := false
		if k == BattleSim.EQ_RAM:
			ok = true
			ram = true
		elif k == BattleSim.EQ_LADDERS:
			ladders = true
		elif c == UT.CLS_ART or (inside and c != UT.CLS_CAV):
			ok = true
		elif (c == UT.CLS_INF or c == UT.CLS_PIKE) and not iron:
			ok = true
		if ok:
			_queue({"type": BattleSim.ORDER_ATTACK, "unit": u, "target": -1, "gate": g,
				"run": orders.value(u, "run")})
			sent += 1
		else:
			refused += 1
	_count("gate_attack")
	if ram:
		overlay.flash("RAM THE GATE: the ram goes at it and batters it", w)
	elif sent == 0 and ladders:
		overlay.flash("Carrying ladders: tap a stretch of wall to plant them", w)
	elif sent == 0 and iron:
		overlay.flash("Swords cannot break this iron-bound gate: a ram or artillery breaks it", w)
	elif sent == 0:
		overlay.flash("Cavalry and missile troops cannot break a gate", w)
	elif refused > 0:
		overlay.flash("Foot hack at the gate, engines shoot it; the others stay", w)
	return true


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
		var why: String = orders.wall_refusal(u, int(p.x), int(p.y))
		if why != "":
			_count("wall_refused")
			overlay.flash(why, p / M * PX_PER_M)
			continue
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
		var why: String = orders.wall_refusal(u, int(c.x), int(c.y))
		if why != "":
			_count("wall_refused")
			overlay.flash(why, p["centre"])
			continue
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
	var marker_r := _marker_hit_r()
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
		elif sim.city_on != 0 and not selection.is_empty():
			# Walls: the stretch under the mouse lights up (overlay); not in
			# a gate's doorway, where a click is about the gate.
			var hw := _screen_to_world((event as InputEventMouseMotion).position)
			overlay.hover_w = hw if _gate_doorway(hw) < 0 else Vector2(-1, -1)
			overlay.queue_redraw()
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
			if coop != null:
				_coop_speed(1, false)
			else:
				speed_idx = mini(speed_idx + 1, SPEEDS.size() - 1)
				_update_speed_text()
		"speed_down":
			if coop != null:
				_coop_speed(-1, false)
			else:
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
		"man_wall":
			_man_wall()
		"come_down":
			_come_down()
		"drop":
			_drop()
		"orders_overlay":
			hud.orders_button.button_pressed = not hud.orders_button.button_pressed
		"ready":
			_deploy_ready()
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
		# One rank is the longest line (the order rule clamps the
		# frontage the same way): the line stops growing there.
		var lmax: float = overlay.max_line_px()
		var dv := overlay.preview_b - overlay.preview_a
		overlay.preview_clamped = lmax > 0.0 and dv.length() > lmax
		if overlay.preview_clamped:
			overlay.preview_b = overlay.preview_a + dv.normalized() * lmax
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
		if sim.u_side[u] != player_side or sim.u_state[u] != BattleSim.U_READY or not _mine(u):
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


# -------------------------------------------------------------- co-op ---

func _coop_ready() -> void:
	coop.auto_update = false
	coop_hud = CoopHud.new()
	coop_hud.region_name = coop_region
	add_child(coop_hud)
	coop_hud.build(coop, hud)
	coop_hud.leave_pressed.connect(func():
		_end_scenario("coop_lobby_leave")
		exit_requested.emit())
	hud.gift_pressed.connect(_gift)
	orders.source = _coop_pending
	coop.changed.connect(func():
		_prune_selection()
		overlay.queue_redraw())
	coop.resolved.connect(func():
		coop_hud.flash("The result is in on the server. Back to campaign when you like.", 8.0))
	coop.note.connect(func(text: String, _kind: String): coop_hud.flash(text, 4.0))


## The session stepped the sim (lockstep frames due by wall time).
func _coop_step(delta: float) -> void:
	if coop.ls != null and coop.ls.sim != sim:
		_rebind(coop.ls.sim)
	if coop.ls != null and not has_meta("coop_select_done"):
		# Testing aid: --coop-select=U[,U] once the battle runs here.
		set_meta("coop_select_done", true)
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--coop-select="):
				var want: Array = []
				if a.get_slice("=", 1) == "mine":
					for u in sim.n_units:
						if coop.can_order(u) and want.size() < 2:
							want.append(u)
				else:
					want = Array(a.get_slice("=", 1).split(","))
				for part in want:
					if coop.can_order(int(part)):
						if selection.is_empty():
							_select(int(part))
						else:
							_toggle_in_selection(int(part))
	var t0 := Time.get_ticks_usec()
	var steps: int = coop.update(delta)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_coop_test_aids()
	var ls = coop.ls
	if ls == null:
		soldiers.set_alpha(1.0)
		return
	if ls.sim != sim:
		_rebind(ls.sim)
	if steps > 0:
		_after_tick(ms / steps)
		soldiers.upload()
		_view_tick()
	var p: bool = ls.paused != 0
	if p != paused:
		paused = p
		hud.pause_button.text = "Play" if paused else "Pause"
	var q: int = ls.speed_q
	if q != int(SPEEDS[speed_idx] * 4.0):
		speed_idx = maxi(SPEEDS.find(q / 4.0), 0)
		_update_speed_text()
	# Interpolation between the last two ticks.
	var a := 1.0
	if not paused:
		var f: float = clampf(coop.wall_acc / TICK_SEC, 0.0, 1.0)
		a = f if q >= 4 else clampf((ls.acc + f * q) / 4.0, 0.0, 1.0)
	soldiers.set_alpha(a)


## Testing aids (tests/live_shots.py): --coop-start-alone (the host starts
## without waiting), --coop-test-withdraw-at=F (withdraw the army at frame
## F), --coop-auto-exit (back to the campaign once the battle is over).
func _coop_test_aids() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--coop-start-alone" and coop.phase == "lobby" and coop.is_host() and coop.room.is_open():
			coop.start_battle()
		elif a.begins_with("--coop-test-withdraw-at=") and coop.ls != null and not has_meta("test_withdrawn") \
				and coop.ls.frame >= int(a.get_slice("=", 1)) and coop.can_issue():
			set_meta("test_withdrawn", true)
			_withdraw_all()
		elif a == "--coop-auto-exit" and coop.final_frame >= 0 and not has_meta("test_exit") \
				and coop.ls.frame >= coop.final_frame + 10:
			set_meta("test_exit", true)
			_end_scenario("coop_auto_exit")
			exit_requested.emit()


## The session restored a snapshot (or started): every view part follows
## the new sim.
func _rebind(s) -> void:
	sim = s
	soldiers.sim = s
	overlay.sim = s
	orders.sim = s
	terrain.sim = s
	city.sim = s
	trees.sim = s
	hud._sim = s
	soldiers.upload()
	_view_tick()
	_prune_selection()


func _mine(u: int) -> bool:
	return coop == null or coop.can_order(u)


func _not_mine_hint(u: int) -> void:
	_count("tap_ally_unit")
	if coop != null and coop.ls != null and coop_hud != null:
		var c: int = coop.ls.commander(u)
		coop_hud.flash("%s commands this unit." % (coop.player_name(c) if c >= 0 else "Nobody"), 2.0)


## Orders not applied yet, for the preview: the lockstep queue (both
## players), the sim's own, and what this player queued this frame.
func _coop_pending() -> Array:
	if coop.ls == null:
		return []
	var out: Array = coop.ls.pending_sim_orders()
	for o in coop.outbox:
		var t := int(o.get("type", 0))
		if (t >= BattleSim.ORDER_MOVE and t <= BattleSim.ORDER_REFILL or t == BattleSim.ORDER_PLACE) \
				and t != BattleSim.ORDER_WITHDRAW_ALL:
			var d: Dictionary = o.duplicate()
			d["tick"] = sim.tick
			out.append(d)
	return out


func _coop_cards() -> void:
	if coop.ls == null:
		return
	for u in sim.n_units:
		if sim.u_side[u] != player_side:
			continue
		var c: int = coop.ls.commander(u)
		hud.set_card_owner(u, c != coop.me, coop.player_color(c) if c >= 0 else Color(0.5, 0.5, 0.5))
	if not selection.is_empty():
		_prune_selection()


## Speed request: one step up / down (wrap: the speed button cycles).
func _coop_speed(dir: int, cycle: bool) -> void:
	if coop.ls == null:
		return
	var qs: Array = Lockstep.SPEED_QS
	var i: int = qs.find(coop.ls.vote_speed_q if coop.ls.vote_speed_by == coop.me else coop.ls.speed_q)
	i += dir
	if cycle:
		i = (i + qs.size()) % qs.size()
	i = clampi(i, 0, qs.size() - 1)
	coop.request_speed(int(qs[i]))


## The ally the selection can be gifted to (-1: none taking part).
func _gift_target() -> int:
	if coop == null or coop.ls == null:
		return -1
	for p in coop.others():
		if coop.ls.is_active(int(p)) and coop.ls.side_of(int(p)) == player_side:
			return int(p)
	return -1


func _gift() -> void:
	var to := _gift_target()
	if to < 0 or selection.is_empty():
		return
	_count("gift")
	_t("coop_gift", {"units": selection.size(), "to": to, "tick": sim.tick})
	coop.gift(selection, to)
	coop_hud.flash("%d unit%s given to %s." % [selection.size(), "" if selection.size() == 1 else "s", coop.player_name(to)], 2.5)
	_select(-1)


## Another player takes part and is connected (leaving hands them our units).
func _coop_others_in() -> bool:
	if coop == null or coop.ls == null:
		return false
	for p in coop.ls.active_players():
		if p != coop.me and coop.connected(p):
			return true
	return false


## Leaving a live co-op battle: what to upload from this device, if
## anything ({res, decided}; {}: nothing - another player carries on or
## the host uploads). Leaves the room either way.
func coop_exit_result() -> Dictionary:
	if coop.ls == null:
		coop.leave()
		return {}
	var res: Dictionary = coop.final_result if not coop.final_result.is_empty() else sim.result()
	var out := {}
	if sim.winner >= 0:
		if coop.should_upload():
			coop.announce_upload()
			out = {"res": res, "decided": true}
	elif not _coop_others_in():
		# The last one here: a forfeit, as in a solo battle.
		out = {"res": res, "decided": false}
	coop.leave()
	return out
