extends SceneTree
## Town maps readable: streets, the Paths overlay, the real route preview, the Occupy flow (needs a window):
##   godot --resolution 1280x720 --script res://tests/city_read_test.gd [-- --shots=DIR [--tag=before] --phone]

const Battle := preload("res://game/battle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const UT := preload("res://sim/unit_types.gd")
const UiScale := preload("res://game/ui_scale.gd")

var failures := 0
var _shots := ""
var _tag := "after"
var _phone := false
var b


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	if _shots == "":
		return
	await _frames(4)
	root.get_texture().get_image().save_png("%s/%s_%s%s.png" % [_shots, name, _tag, "_phone" if _phone else ""])


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.get_slice("=", 1)
		elif a.begins_with("--tag="):
			_tag = a.get_slice("=", 1)
		elif a == "--phone":
			_phone = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	UiScale._dpr_override = 3.0 if _phone else 1.0
	UiScale._touch_override = 1 if _phone else 0
	_run.call_deferred()


## A West town battle (pack west, a plan town) at the given walls level.
func _town(key: String, walls: int) -> Dictionary:
	CData.use_pack("west")
	var st := CState.new_campaign("town", 5, [], {}, [], "west")
	var r := CData.region_index(key)
	st["regions"][r]["level"] = 2
	var got := false
	for sl in st["regions"][r]["slots"]:
		if int(sl[0]) == CData.WALLS:
			sl[1] = walls
			got = true
	if not got:
		st["regions"][r]["slots"].append([CData.WALLS, walls])
	var city := CBattle.city_dict(st, r)
	var rd: Dictionary = CData.REGIONS[r]
	var terr := {"kind": int(rd["terrain"]), "seed": (CState.city_seed(st, r) ^ 0x2545F491) & 0x7FFFFFFF,
		"forest": int(rd["forest"]), "ground": int(rd["ground"])}
	var att: Array = []
	var dfn: Array = []
	for e in Scenarios.WEST_ATT:
		att.append([UT.index_of(str(e[0])), int(e[1])])
	for e in Scenarios.WEST_DEF:
		dfn.append([UT.index_of(str(e[0])), int(e[1])])
	# (We are the defenders, the town's: the attackers are the AI's.)
	var res := Scenarios.settlement(city, terr, att, dfn, 1, [0], {})
	return res["scenario"]


func _new_battle(key := "havana", walls := 0) -> void:
	if is_instance_valid(b):
		b.free()
	b = Battle.new()
	b.custom_scenario = _town(key, walls)
	b.seed_value = 7
	b.player_side = 1
	root.add_child(b)
	await _frames(8)


func _w2s(x: int, y: int) -> Vector2:
	return b.get_canvas_transform() * (Vector2(x, y) / 1024.0 * Battle.PX_PER_M)


func _look(wx: float, wy: float, zoom: float) -> void:
	b.camera.position = Vector2(wx, wy) * Battle.PX_PER_M
	b.camera.zoom = Vector2.ONE * zoom


func _tap_at(x: int, y: int) -> void:
	b._tap(_w2s(x, y), false)
	await _frames(2)


func _pending_occupy(u: int) -> int:
	# The building the unit was ordered into (predicted: pending orders included), -1 none.
	return b.orders.value(u, "occ") - 1


func _step(n: int) -> void:
	for i in n:
		b._do_tick()


func _run() -> void:
	var cfg := ConfigFile.new()
	var had_cfg := cfg.load("user://settings.cfg") == OK
	var old_paths = cfg.get_value("ui", "paths") if had_cfg and cfg.has_section_key("ui", "paths") else null
	if _phone:
		DisplayServer.window_set_size(Vector2i(844, 390))
		await _frames(6)
		UiScale.apply(root)
		await _frames(4)
	await _new_battle()
	b.paused = true
	var sim = b.sim
	_check(sim.city_on == 1 and sim.occ_on == 1 and sim.city_walls == 0 and sim.n_gates == 0, "Havana, walls 0: an open plan town with buildings that can be held")
	var u := 13
	var pl: Array = (sim.map_info["city"] as Dictionary)["plaza"]
	_look(float(pl[0]) - 60.0, float(pl[1]) + 20.0, 0.55)
	await _frames(4)
	await _shot("streets_compare")
	_look(366.0, 190.0, 0.32)
	await _frames(4)
	await _shot("overview")

	# ---- Streets: the layer paints from the sim's cells.
	var st = null
	for c in b.city.get_children():
		if c is Sprite2D and c.get_script() == b.city.CityStreets:
			st = c
	_check(st != null and st.texture != null, "the street layer is built (it reads the sim's cells)")
	await _look_at_unit(u, 0.9)
	await _shot("streets")

	# ---- Paths.
	_check(b.hud.paths_button != null and b.hud.paths_button.visible, "the Paths button shows on a town map")
	_check(b.paths_on and b.hud.paths_button.button_pressed, "Paths is on by default on a first play")
	var blocked := 0
	for i in sim.ob_w * sim.ob_h:
		if (sim.nav[i] & 1) == 0 and sim.obs[i] != 6:
			blocked += 1
	b.city.set_paths_alpha(0.5)
	_check(b.city.paths_cells == blocked and blocked > 500, "the hatch covers exactly the cells the sim bars to foot (%d, the sea left clear)" % blocked)
	b.city.set_paths_alpha(0.0)
	b._select(-1)
	await _frames(3)
	_check(b.city.paths_node == null or not b.city.paths_node.visible, "no unit selected: no hatch")
	b._select(u)
	await _frames(3)
	var mat: ShaderMaterial = b.city.paths_node.material
	_check(b.city.paths_node.visible and float(mat.get_shader_parameter("alpha")) > 0.8, "a unit selected: the hatch shows")
	await _shot("paths")
	var n0: int = b._input_counts.get("paths_toggle", 0)
	await get_root().get_tree().create_timer(2.3).timeout
	await _frames(3)
	_check(not b.city.paths_node.visible, "the hatch has faded out 2 s after the selection changed")
	b.hud.paths_button.button_pressed = false
	await _frames(2)
	_check(not b.paths_on and b._input_counts.get("paths_toggle", 0) == n0 + 1, "the Paths toggle off (counter paths_toggle)")
	var cf2 := ConfigFile.new()
	cf2.load("user://settings.cfg")
	_check(int(cf2.get_value("ui", "paths", 1)) == 0, "... and remembered in settings.cfg")
	b._select(-1)
	b._select(u)
	await _frames(3)
	_check(not b.city.paths_node.visible, "with Paths off a selection shows no hatch")
	b.hud.paths_button.button_pressed = true
	await _frames(3)
	_check(b.paths_on and b.city.paths_node.visible, "Paths on again: the hatch shows at once")

	# ---- The move preview draws the sim's path.
	var from := Vector2i(sim.u_ax[u], sim.u_ay[u])
	var goal := Vector2i(-1, -1)
	var want := PackedInt32Array()
	for ring in range(30, 130, 10):
		for a in range(0, 360, 20):
			var gx: int = from.x + int(cos(deg_to_rad(a)) * ring * 1024.0)
			var gy: int = from.y + int(sin(deg_to_rad(a)) * ring * 1024.0)
			var order := BattleSim.make_move_order(0, u, gx, gy, 768, BattleSim.files_to_width(10, sim.u_type[u]), 0)
			var rt: Dictionary = b.orders.move_route_for(u, order)
			if not rt.is_empty() and not rt["blocked"] and (rt["pts"] as PackedInt32Array).size() > maxi(want.size(), 7):
				goal = Vector2i(gx, gy)
				want = rt["pts"]
	_check(goal.x >= 0, "a sample tap whose route bends through the streets (%s: %d points)" % [str(goal / 1024), want.size() / 2])
	# (The order rule keeps a tap on a house to open ground beside it: the route ends at that snapped goal.)
	if want.size() < 4:
		want = PackedInt32Array([0, 0, 0, 0])
	var direct: PackedInt32Array = sim.route_to(sim.u_ax[u], sim.u_ay[u], want[want.size() - 2], want[want.size() - 1], sim._ground_mask(u))
	var same := want.size() == direct.size() + 2
	for i in direct.size():
		same = same and want[i + 2] == direct[i]
	if not same:
		print("want ", want, " direct ", direct, " goal ", goal)
	_check(same and want[0] == sim.u_cx[u] and want[1] == sim.u_cy[u], "the preview route is the sim's own street search from the unit's centre")
	# ... and it is what the unit then walks: order it, let the sim plan, compare the planned waypoints.
	var cam_c := Vector2(from) * 0.5 + Vector2(goal) * 0.5
	_look(cam_c.x / 1024.0, cam_c.y / 1024.0, 0.7)
	b._tap(_w2s(goal.x, goal.y), false)
	await _frames(2)
	_step(3)
	var base: int = u * sim.PATH_MAX
	var walked := PackedInt32Array()
	for k in range(sim.u_pk[u], sim.u_pn[u]):
		walked.append(sim.pth_x[base + k])
		walked.append(sim.pth_y[base + k])
	var tail: PackedInt32Array = want.slice(2)
	var shortcut := tail.size() - walked.size()
	var walk_ok := shortcut >= 0 and tail.slice(shortcut) == walked
	_check(walk_ok, "the sim plans exactly those waypoints once the order is applied (%d of %d, the first %d skipped as it sees past them)" % [walked.size() / 2, tail.size() / 2, shortcut / 2])
	b.paused = true
	_step(0)
	b._select(-1)
	b._select(u)
	await _frames(3)
	await _shot("route_ordered")
	# The drag preview (touch drag / right-button drag) draws the route and the ghost.
	b.overlay.preview_on = true
	b._line_preview(_w2s(goal.x, goal.y) + Vector2(-30, 0), _w2s(goal.x, goal.y) + Vector2(30, 0))
	await _frames(3)
	_check(b.overlay.preview_ok and not b.overlay.preview_group().is_empty(), "the drag preview has its footprint ghost")
	await _shot("route_preview")
	b.overlay.preview_on = false
	b.overlay.queue_redraw()
	# No way through: the red ghost (a cut-off goal: the sim's search answers nothing).
	var order2 := BattleSim.make_move_order(0, u, goal.x, goal.y, 0, 3000, 0)
	var fake: Dictionary = b.orders.route_from_fields(u, {"ax": from.x, "ay": from.y, "dx": goal.x, "dy": goal.y, "snap": 3})
	_check(fake["blocked"] == true, "a goal the order rule calls unreachable (snap 3) is flagged: red ghost, 'No way through'")
	order2.clear()

	await _occupy(u)

	if had_cfg and old_paths != null:
		cfg.set_value("ui", "paths", old_paths)
		cfg.save("user://settings.cfg")
	elif had_cfg:
		if cfg.has_section_key("ui", "paths"):
			cfg.erase_section_key("ui", "paths")
		cfg.save("user://settings.cfg")
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	print("RESULT: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(0 if failures == 0 else 1)


func _look_at_unit(u: int, zoom: float) -> void:
	_look(b.sim.u_ax[u] / 1024.0, b.sim.u_ay[u] / 1024.0 - 35.0, zoom)
	await _frames(3)


func _mouse_to(x: int, y: int) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _w2s(x, y)
	ev.global_position = ev.position
	b._unhandled_input(ev)
	await _frames(2)


func _mid(bd: int) -> Vector2i:
	var q: PackedVector2Array = b.OccView.quad(b.sim, bd)
	var m := (q[0] + q[1] + q[2] + q[3]) * 0.25 * 1024.0
	return Vector2i(int(m.x), int(m.y))


func _avg_frame_ms(n: int) -> float:
	var t0 := Time.get_ticks_usec()
	await _frames(n)
	return float(Time.get_ticks_usec() - t0) / 1000.0 / n


func _occupy(u: int) -> void:
	var sim = b.sim
	var touch: bool = UiScale.is_touch()
	b._select(-1)
	b._select(u)
	var u2 := 14
	b._toggle_in_selection(u2)
	await _frames(3)
	_check(b.hud.occupy_button.visible and b.hud.occupy_button.text == "Occupy", "units that can take a house selected: the Occupy button shows")
	# What the sim's rule allows (brute force over every building and selected man).
	var want := 0
	for bd in sim.ob_ok.size():
		var ok := false
		for w in b.selection:
			if sim.ob_ok[bd] != 0 and BattleSim.occupy_refusal(sim, w, bd) == "":
				ok = true
		if ok:
			want += 1
	var arm0: int = b._input_counts.get("occupy_arm", 0)
	b._toggle_occupy()  # (the code path the button's press calls: a press does not fire without a window)
	await _frames(3)
	_check(b.occupy_mode and b.overlay.occ_mode and b.hud.occupy_button.button_pressed, "pressing Occupy arms the mode (the button is lit; counter occupy_arm %d)" % (b._input_counts.get("occupy_arm", 0) - arm0))
	_check(b.overlay.occ_lit.size() == want and want > 20, "it lights exactly the %d buildings the sim's rule allows (lit %d)" % [want, b.overlay.occ_lit.size()])
	var all_ok := true
	for bd in b.overlay.occ_lit:
		all_ok = all_ok and sim.ob_ok[bd] != 0 and sim.ob_sn[bd] >= 4 and sim.ob_u[bd] == 0
	_check(all_ok, "every lit building has an inside (at least 4 firing places) and no holder")
	_look(sim.u_ax[u] / 1024.0, sim.u_ay[u] / 1024.0 + 5.0, 1.0)
	await _frames(3)
	await _shot("occupy_lit")
	# The building to look at: the lit one nearest the unit's door.
	var pick := -1
	var bestd := 1 << 60
	for bd in b.overlay.occ_lit:
		var d: int = FM_len(sim.ob_dx[bd] - sim.u_ax[u], sim.ob_dy[bd] - sim.u_ay[u])
		if d > 12 * 1024 and d < bestd and b.OccView.kind_name(sim, bd) != "Shrine":
			bestd = d
			pick = bd
	_check(pick >= 0, "a lit building near the unit to inspect (#%d, %s)" % [pick, b.OccView.kind_name(sim, pick)])
	var mid := _mid(pick)
	var prev0: int = b._input_counts.get("occupy_preview", 0)
	var base_runs: Array = []
	for r in 5:
		base_runs.append(await _avg_frame_ms(30))
	base_runs.sort()
	var base_ms: float = base_runs[2]
	if touch:
		await _tap_at(mid.x, mid.y)
	else:
		await _mouse_to(mid.x, mid.y)
	_check(b.overlay.occ_focus == pick and b._input_counts.get("occupy_preview", 0) == prev0 + 1,
		"%s a lit building shows its sight lines (counter occupy_preview)" % ("one tap on" if touch else "hovering"))
	_check(b.occupy_mode and sim.u_occ[u] == 0 and b.orders.value(u, "occ") == 0, "... and sends nobody yet")
	var fans: Array = b.overlay.occ_fans(pick)
	var rng: float = b.overlay.occ_range_m
	var fan_ok := fans.size() >= 2
	var shortest := 1e9
	var longest := 0.0
	for f in fans:
		var pts: PackedVector2Array = f["pts"]
		fan_ok = fan_ok and pts.size() == 18 and int(f["n"]) >= 1
		for k in range(1, pts.size()):
			var l := pts[0].distance_to(pts[k])
			fan_ok = fan_ok and l <= rng + 1.0
			shortest = minf(shortest, l)
			longest = maxf(longest, l)
	_check(fan_ok and longest > 4.0 and shortest < rng - 1.0, "the fans: %d faces, 16 rays each, within the %d m range, cut by obstacles (rays %.0f to %.0f m)" % [fans.size(), int(rng), shortest, longest])
	_check(b.OccView.places(sim, pick) == sim.ob_sn[pick] and b.OccView.holds(sim, pick) == sim.ob_sn[pick] + 2, "the tip: %s, %d places, holds %d men" % [b.OccView.kind_name(sim, pick), b.OccView.places(sim, pick), b.OccView.holds(sim, pick)])
	var us0: int = b.overlay.occ_fan_us
	await _look_at_building(pick)
	await _shot("occupy_fan")
	var fan_runs: Array = []
	for r in 5:
		fan_runs.append(await _avg_frame_ms(30))
	fan_runs.sort()
	var fan_ms: float = fan_runs[2]
	# (Both are the median of five 30-frame windows; the look differs only by the fan, its tip and the lit outlines.)
	var share := (fan_ms - base_ms) / maxf(base_ms, 0.01)
	var info := "a fan costs %.2f ms a frame to draw (%.1f %% of the frame: %.2f ms with it, %.2f without) and %.2f ms to build once" % [fan_ms - base_ms, share * 100.0, fan_ms, base_ms, us0 / 1000.0]
	if base_ms > 10.0:
		print("INFO (machine loaded, base frame over 10 ms, not checked) " + info)
	else:
		_check(share < 0.15 and us0 < 8000, info)
	# Send.
	var pk0: int = b._input_counts.get("occupy_pick", 0)
	if touch:
		await _tap_at(mid.x, mid.y)
	else:
		await _tap_at(mid.x, mid.y)
	await _frames(2)
	_check(not b.occupy_mode and b._input_counts.get("occupy_pick", 0) == pk0 + 1, "%s sends them in (counter occupy_pick)" % ("a second tap" if touch else "a click"))
	var sent := 0
	var into := {}
	for w in b.selection:
		var o: int = b.orders.value(w, "occ") - 1
		if o >= 0:
			sent += 1
			into[o] = true
	_check(sent == 2 and into.size() == 2 and into.has(pick), "both men are sent, to two buildings, one of them the picked one")
	# The sim takes them in.
	var in_t := -1
	for t in 900:
		b._do_tick()
		if sim.u_occ[u] > 0 and sim.u_occ[u2] > 0:
			in_t = t
			break
	_check(in_t >= 0, "the ORDER_OCCUPY is the sim's: both units are inside after %d ticks" % in_t)
	b._refresh_actions()
	await _frames(2)
	var held: int = sim.u_occ[b.selected] - 1
	_check(b.overlay.occ_focus == held and b.hud.occupy_button.text == "Leave", "a unit that holds a building, selected: its sight fans show (and the button says Leave)")
	await _look_at_building(held)
	await _shot("occupy_held")
	# Cancel: a tap elsewhere, and the button again.
	b._select(-1)
	b._select(6 if false else 12)
	b._select(-1)
	b._select(15)
	await _frames(3)
	var can0: int = b._input_counts.get("occupy_cancel", 0)
	b._toggle_occupy()  # (the code path the button's press calls: a press does not fire without a window)
	await _frames(2)
	_check(b.occupy_mode, "a fresh selection arms Occupy again")
	await _tap_at(sim.u_ax[15] + 3000 * 1024, sim.u_ay[15] - 40 * 1024)
	_check(not b.occupy_mode and b._input_counts.get("occupy_cancel", 0) == can0 + 1 and b.overlay.occ_lit.is_empty(), "a tap on nothing cancels it (counter occupy_cancel)")
	b._toggle_occupy()  # (the code path the button's press calls: a press does not fire without a window)
	await _frames(2)
	b._toggle_occupy()  # (the code path the button's press calls: a press does not fire without a window)
	await _frames(2)
	_check(not b.occupy_mode and b._input_counts.get("occupy_cancel", 0) == can0 + 2, "the button again cancels")
	# Selecting something else cancels quietly.
	b._toggle_occupy()  # (the code path the button's press calls: a press does not fire without a window)
	await _frames(2)
	b._select(16)
	await _frames(2)
	_check(not b.occupy_mode, "another selection drops the mode")
	# Cavalry / engines: no Occupy (nothing lit).
	b._select(12)
	await _frames(2)
	_check(not b.hud.occupy_button.visible, "an engine battery has no Occupy button")


static func FM_len(dx: int, dy: int) -> int:
	return int(sqrt(float(dx) * dx + float(dy) * dy))


func _look_at_building(bd: int) -> void:
	var m := _mid(bd)
	_look(m.x / 1024.0, m.y / 1024.0 - 6.0, 1.15 if not _phone else 0.9)
	await _frames(3)
