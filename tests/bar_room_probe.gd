extends SceneTree
## Bar room probe: for battle_2000 (seed 7) at a few viewports and three selections (batteries, the skirmish/missile
## group, all), prints the width the bottom bar's action row has (the value Hud._fit_now computes), the fixed
## buttons' width, and where each applicable chip stands (bar or More). Used to compare the bar's room across HUD
## changes.   godot --headless --script res://tests/bar_room_probe.gd
const Battle := preload("res://game/battle.gd")
const UiScale := preload("res://game/ui_scale.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")

const SIZES := [[640, 640], [866, 400], [1231, 568]]
const GAPV := 5.0


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	Kit.anim_override = 0
	UiScale.load_settings()
	UiScale.size_idx = 1
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_run.call_deferred()


func _run() -> void:
	for s in SIZES:
		if s[0] > 0:
			UiScale._dpr_override = 3.0
			UiScale._touch_override = 1
			DisplayServer.window_set_size(Vector2i(s[0], s[1]))
			root.size = Vector2i(s[0], s[1])
			root.content_scale_size = Vector2i(s[0], s[1])
			await _frames(6)
			UiScale.apply(root)
			await _frames(4)
		var b := Battle.new()
		b.scenario_id = "battle_2000"
		b.seed_value = 7
		root.add_child(b)
		await _frames(8)
		b._set_paused(true)
		var vp := root.get_visible_rect().size
		for g in ["guns", "skirmish", "all"]:
			b._select_group(g)
			await _frames(3)
			print(_report(b, vp, g))
		b.queue_free()
		await _frames(3)
	quit(0)


func _report(b, vp: Vector2, g: String) -> String:
	var h = b.hud
	var avail: float = h._bar_width() - h.group_box.get_combined_minimum_size().x - 2.0 * GAPV - 4.0
	for n in [h.engine_note, h.carry_note]:
		if (n as Label).visible:
			avail -= (n as Label).get_combined_minimum_size().x + GAPV
	var fixed: Array = []
	for c in [h.halt_button, h.run_button, h.withdraw_button]:
		if (c as Control).visible:
			fixed.append(c)
	var bar := []
	var more := []
	for c in h._chip_order:
		if not (c as Control).visible:
			continue
		if c.get_parent() == h.more_box:
			more.append(c.name)
		else:
			bar.append(c.name)
	return "vp=%s sel=%s n=%d avail=%.0f capsule=%.0f fixed_w=%.0f(full) more_btn=%s | bar=%s | under_more=%s" % [
		str(vp), g, b.selection.size(), avail, h.group_box.get_combined_minimum_size().x, h._row_w(fixed, false),
		str(h.more_button.visible), ",".join(bar), ",".join(more)]
