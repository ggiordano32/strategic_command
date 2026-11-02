extends SceneTree
## Control groups on the bar and the cards (docs/design/ui.md "Control groups"):
##   godot --path . --resolution 393x851 -s tests/groups_shot.gd -- --w=393 --h=851 --shots=DIR [--nontouch] [--mode=one|two|empty|hold|deploy]
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


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var w := 393
	var h := 851
	var shots := ""
	var nontouch := false
	var mode := "two"
	var crop := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--w="): w = int(a.get_slice("=", 1))
		if a.begins_with("--h="): h = int(a.get_slice("=", 1))
		if a.begins_with("--shots="): shots = a.get_slice("=", 1)
		if a.begins_with("--mode="): mode = a.get_slice("=", 1)
		if a.begins_with("--crop="): crop = int(a.get_slice("=", 1))
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
	if mode == "deploy":
		sc = {"width_m": 300, "height_m": 300, "ai_sides": [1], "orders": [], "units": [
			Scenarios.unit(0, UT.HEAVY, 100, 150, 270, Scenarios.FACE_UP),
			Scenarios.unit(0, UT.PIKE, 100, 100, 270, Scenarios.FACE_UP),
			Scenarios.unit(0, UT.PIKE, 100, 200, 270, Scenarios.FACE_UP),
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
	var us: Array[int] = []
	for u in b.sim.n_units:
		if b.sim.u_side[u] == 0:
			us.append(u)
	var pick := func(l: Array) -> void:
		b.selection.clear()
		for u in l:
			b.selection.append(u)
		b.selected = l[0] if not l.is_empty() else -1
		b._selection_changed()
	# Three groups: 1 = the first two, 2 = units 2..4, 3 = the last two plus the first (so unit 0 is in two).
	pick.call([us[0], us[1]])
	b._group_assign(1, "set")
	pick.call(us.slice(2, mini(5, us.size())))
	b._group_assign(2, "set")
	pick.call([us[us.size() - 1], us[us.size() - 2], us[0]])
	b._group_assign(3, "set")
	if mode == "one":
		pick.call([us[0]])
	elif mode == "two":
		pick.call(us)
	elif mode == "empty":
		pick.call([])
	elif mode == "hold":
		pick.call([us[0], us[1]])
	elif mode == "deploy":
		ConfirmOrders.force = "on"
		b._last_touch = true
		pick.call([us[0]])
		b._cam_to(Vector2(150, 230) * b.PX_PER_M)
		b._place_from_tap(Vector2(120, 215) * b.PX_PER_M, false)
	if mode == "two" and nontouch:
		pick.call(us.slice(0, 5))
		b._group_assign(4, "set")
		pick.call(us)
	await _frames(6)
	b.hud.update_cards(b.sim)
	if mode == "hold":
		b.hud._open_explain(b.hud.group_chips[1])
	await _frames(4)
	b.hud.set_undo_toast(true, "2 units: move")
	b._place_process()
	await _frames(4)
	var tag := "%s_%dx%d" % [mode, w, h]
	print(tag, " bar ", b.hud.bottom_height(), " two_rows ", b.hud.two_rows, " groups ", b.control_groups.keys())
	if shots != "":
		DirAccess.make_dir_recursive_absolute(shots)
		var img := root.get_texture().get_image()
		if crop > 0:
			img = img.get_region(Rect2i(0, img.get_height() - crop, img.get_width(), crop))
		img.save_png("%s/%s.png" % [shots, tag])
	quit(0)
