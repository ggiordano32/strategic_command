extends SceneTree
## The Undo toast against the chip bar at phone sizes (docs/design/ui.md "Confirm orders and the placement tool"):
##   godot --path . --resolution 393x851 -s tests/hud_undo_shot.gd -- --w=393 --h=851 --shots=DIR [--stress] [--ghost]
const Battle := preload("res://game/battle.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const UiScale := preload("res://game/ui_scale.gd")
const ConfirmOrders := preload("res://game/confirm_orders.gd")
var b
func _frames(n: int) -> void:
	for i in n:
		await process_frame
func _desc(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		out.append(c)
		out.append_array(_desc(c))
	return out
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var w := 393
	var h := 851
	var shots := ""
	var stress := false
	var ghost := false
	var late := false
	var deploy := false
	var explain := false
	var ctl := false
	var menu := false
	var nontouch := false
	var flow := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--w="): w = int(a.get_slice("=", 1))
		if a.begins_with("--h="): h = int(a.get_slice("=", 1))
		if a.begins_with("--shots="): shots = a.get_slice("=", 1)
		if a == "--stress": stress = true
		if a == "--ghost": ghost = true
		if a == "--late": late = true
		if a == "--deploy": deploy = true
		if a == "--explain": explain = true
		if a == "--ctl": ctl = true
		if a == "--menu": menu = true
		if a == "--nontouch": nontouch = true
		if a == "--flow": flow = true
	for a in OS.get_cmdline_user_args():
		if a == "--nontouch": nontouch = true
	Kit.anim_override = 0
	UiScale._dpr_override = 1.0 if nontouch else 3.0
	UiScale._touch_override = 0 if nontouch else 1
	DisplayServer.window_set_size(Vector2i(w, h))
	root.size = Vector2i(w, h)
	await _frames(6)
	UiScale.apply(root)
	await _frames(4)
	var units: Array = []
	var x := 60
	var seen := {}
	for ty in UT.TYPES.size():
		var r := UT.role(ty)
		if r == "" or UT.stat(ty, "fixed") != 0 or UT.base_of(ty) != ty or seen.has(r):
			continue
		seen[r] = true
		units.append(Scenarios.unit(0, ty, 40, x, 150, 0))
		x += 14
	units.append(Scenarios.unit(1, UT.index_of("spear"), 80, 150, 40, 512))
	var sc := Scenarios._test(units, [])
	if deploy:
		sc = {"width_m": 300, "height_m": 300, "ai_sides": [1], "orders": [], "units": [
			Scenarios.unit(0, UT.HEAVY, 100, 150, 270, Scenarios.FACE_UP),
			Scenarios.unit(0, UT.PIKE, 100, 100, 270, Scenarios.FACE_UP),
			Scenarios.unit(1, UT.HEAVY, 100, 150, 60, Scenarios.FACE_DOWN)],
			"terrain": {"kind": 0}, "deploy_time": 600}
	sc["ai_sides"] = [1]
	b = Battle.new()
	b.custom_scenario = sc
	b.player_side = 0
	b.seed_value = 5
	b.speed_q = 4
	root.add_child(b)
	await _frames(8)
	b._set_paused(true)
	if deploy:
		ConfirmOrders.force = "on"
		b._last_touch = true
		var u0 := -1
		for u in b.sim.n_units:
			if b.sim.u_side[u] == 0:
				u0 = u
		b._select(u0)
		b._cam_to(Vector2(150, 230) * b.PX_PER_M)
		b._place_from_tap(Vector2(120, 215) * b.PX_PER_M, false)
		await _frames(6)
		print("deploy phase ", b.sim.phase, " place_on ", b.place_on, " bar ", b.hud.place_bar.visible)
		root.get_texture().get_image().save_png("%s/deploy_%dx%d.png" % [shots, w, h])
		b._place_from_tap(Vector2(150, 100) * b.PX_PER_M, false)   # outside the zone
		await _frames(6)
		root.get_texture().get_image().save_png("%s/deploy_out_%dx%d.png" % [shots, w, h])
		quit(0)
		return
	var us: Array[int] = []
	for u in b.sim.n_units:
		if b.sim.u_side[u] == 0:
			us.append(u)
	b.selection.clear()
	b.selection.append_array(us if not ghost else [us[0]])
	b.selected = us[0]
	b._selection_changed()
	if stress:
		b.process_mode = Node.PROCESS_MODE_DISABLED
		for c in b.hud._chip_order:
			(c as Control).visible = true
		b.hud._fit_actions()
	await _frames(3)
	if ghost:
		b._last_touch = true
		print("phase ", b.sim.phase, " confirm ", b._confirm_on())
		b._place_from_tap(Vector2(b.sim.u_cx[us[0]], b.sim.u_cy[us[0]]) / b.M * b.PX_PER_M + Vector2(0, -200), false)
		await _frames(4)
		print("place_on ", b.place_on, " bar ", b.hud.place_bar.visible, b.hud.place_bar.get_global_rect())
	if not flow:
		b.hud.set_undo_toast(true, "3 units: move")
	b._place_process()
	await _frames(3)
	b._place_process()
	await _frames(2)
	if late:
		b.selection.clear()
		b.selected = -1
		b._selection_changed()
		await _frames(4)
		b.selection.append_array(us)
		b.selected = us[0]
		b._selection_changed()
		for i in 12:
			await _frames(1)
			var tt: Rect2 = b.hud.undo_toast.get_global_rect()
			var bb: Rect2 = b.hud._bottom.get_global_rect()
			var hits := []
			for c in b.hud._chip_order + [b.hud.run_button]:
				if (c as Control).is_visible_in_tree() and tt.intersects((c as Control).get_global_rect()):
					hits.append(c.key)
			print("late frame ", i, " toast ", tt.position.y, "-", tt.end.y, " bar top ", bb.position.y, " hits ", hits)
	if flow:
		b._place_go()
		b._set_paused(false)
		print("after go: toast ", b.hud.undo_toast.visible, " sel ", b.selection.size())
		for k in 3:
			for i in 20:
				await _frames(1)
				var tt: Rect2 = b.hud.undo_toast.get_global_rect()
				var hits := []
				if b.hud.undo_toast.visible:
					for c in _desc(b.hud._bottom):
						if c is Control and c.is_visible_in_tree() and tt.intersects(c.get_global_rect()):
							hits.append(c.name)
				if i % 5 == 0 or not hits.is_empty():
					print("flow ", k, ".", i, " toast ", tt.position.y, "-", tt.end.y, " bar top ", b.hud._bottom.get_global_rect().position.y, " hits ", hits)
			b.selection.clear()
			b.selection.append_array(us)
			b.selected = us[0]
			b._selection_changed()
	if explain:
		b.hud._open_explain(b.hud.run_button)
		await _frames(4)
		print("explain ", b.hud.explain_panel.get_global_rect(), " idx ", b.hud.explain_panel.get_index(), " toast idx ", b.hud.undo_toast.get_index())
	if ctl:
		b._open_controls()
		await _frames(4)
		print("toast idx ", b.hud.undo_toast.get_index(), " controls idx ", b.hud.controls.get_index(), " book idx ", b.hud.book.get_index(), " place_bar idx ", b.hud.place_bar.get_index())
	if menu:
		b._open_menu()
		await _frames(3)
		b.menu.page = "chips"
		b.menu._build()
		await _frames(4)
		print("menu visible ", b.menu.visible, " toast ", b.hud.undo_toast.visible, " toast idx ", b.hud.undo_toast.get_index(), " menu idx ", b.menu.get_index(), " parents ", b.hud.undo_toast.get_parent().name, " ", b.menu.get_parent().name)
	var t: Rect2 = b.hud.undo_toast.get_global_rect()
	print("vp ", root.get_visible_rect().size, " toast ", t, " bottom ", b.hud._bottom.get_global_rect(), " two_rows ", b.hud.two_rows)
	for c in b.hud._chip_order:
		if (c as Control).is_visible_in_tree() and t.intersects((c as Control).get_global_rect()):
			print("OVERLAP chip ", c.key, " ", (c as Control).get_global_rect())
	for c in [b.hud.place_bar, b.hud.run_button, b.hud.halt_button, b.hud.withdraw_button, b.hud.group_box, b.hud.actions_box, b.hud.chips_box, b.hud.chips_up]:
		if (c as Control).is_visible_in_tree() and t.intersects((c as Control).get_global_rect()):
			print("OVERLAP ", c.name, " ", (c as Control).get_global_rect())
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
		root.get_texture().get_image().save_png("%s/undo_%dx%d%s.png" % [shots, w, h, ("_stress" if stress else "") + ("_ghost" if ghost else "") + ("_menu" if menu else "") + ("_ctl" if ctl else "") + ("_explain" if explain else "")])
	quit(0)
