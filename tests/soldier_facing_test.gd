extends SceneTree
## Men's drawn heading on screen (needs a window):
##   godot --path . --resolution 1280x720 -s tests/soldier_facing_test.gd [-- --shots=DIR]
## Renders only the soldier layers (a SubViewport that sees nothing else) of a
## marching column and of a line dressing on both paths, the texture-fed and
## the CPU-fed shader, and checks the two images are the same pixel for
## pixel; --shots saves the whole window on the texture path.

const Battle := preload("res://game/battle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")

const SoldierLayer := preload("res://game/soldier_layer.gd")

## A move order names the unit's front centre: this many metres ahead of a
## 60-man block's centre (measured on the skirmish's heavy swords).
const FRONT := 9.0
const PROBE_LAYER := 1 << 19

var b
var _shots := ""
var _ok := true


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		_ok = false


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.get_slice("=", 1)
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)
	_run.call_deferred()


## The soldier layers alone around `c` (sim metres), at `ppm` pixels a metre.
func _soldiers_only(c: Vector2, ppm: float, size: int) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.transparent_bg = true
	vp.world_2d = b.get_viewport().world_2d
	vp.canvas_cull_mask = PROBE_LAYER
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var n: Node = b.soldiers
	while n is CanvasItem:
		(n as CanvasItem).visibility_layer |= PROBE_LAYER
		n = n.get_parent()
	for mmi in b.soldiers._layers:
		mmi.visibility_layer |= PROBE_LAYER
	b.add_child(vp)
	var k := ppm / Battle.PX_PER_M
	vp.canvas_transform = Transform2D(0.0, Vector2(k, k), 0.0, Vector2(size, size) * 0.5 - c * Battle.PX_PER_M * k)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	vp.queue_free()
	return img


func _diff(a: Image, c: Image) -> int:
	var da := a.get_data()
	var dc := c.get_data()
	var n := 0
	for i in range(0, da.size(), 4):
		if da[i] != dc[i] or da[i + 1] != dc[i + 1] or da[i + 2] != dc[i + 2] or da[i + 3] != dc[i + 3]:
			n += 1
	return n


func _both(label: String, c: Vector2, ppm: float) -> void:
	b.soldiers.set_cpu_fed(false)
	b.soldiers.set_alpha(0.5)
	await _frames(2)
	var g := await _soldiers_only(c, ppm, 512)
	b.soldiers.set_cpu_fed(true)
	b.soldiers.set_alpha(0.5)
	await _frames(2)
	var p := await _soldiers_only(c, ppm, 512)
	var drawn := 0
	var da := g.get_data()
	for i in range(3, da.size(), 4):
		if da[i] > 64:
			drawn += 1
	var d := _diff(g, p)
	_check(drawn > 1500 and d == 0, "%s: texture and CPU paths draw the same pixels (%d px drawn, %d differ)" % [label, drawn, d])
	b.soldiers.set_cpu_fed(false)
	b.soldiers.set_alpha(0.5)
	await _frames(2)


func _shot(name: String) -> void:
	if _shots == "":
		return
	await _frames(4)
	root.get_texture().get_image().save_png("%s/%s.png" % [_shots, name])


func _look(c: Vector2, zoom: float) -> void:
	b.camera.position = c * Battle.PX_PER_M
	b.camera.zoom = Vector2.ONE * zoom


func _step(n: int) -> void:
	for i in n:
		b.sim.step()
		b.soldiers.upload()
	b.soldiers.set_alpha(1.0)
	b._view_tick()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	b = Battle.new()
	b.scenario_id = "skirmish"
	b.seed_value = 7
	root.add_child(b)
	await _frames(6)
	b.paused = true
	var sim = b.sim
	var u := 0
	var ox: int = sim.u_cx[u]
	var oy: int = sim.u_cy[u]
	var face: int = sim.u_face[u]
	# A column marching obliquely (50 m across, 30 m down).
	sim.queue_order(BattleSim.make_move_order(sim.tick, u, ox + 50 * 1024, oy + 30 * 1024, face, 0, 0))
	_step(110)
	var c := Vector2(sim.u_cx[u], sim.u_cy[u]) / 1024.0
	_look(c, 1.6)
	await _frames(3)
	var turned := 0
	var base: int = sim.u_slot_base[u]
	for s in sim.u_alive[u]:
		var i: int = sim.slot_soldier[base + s]
		if absf(fposmod(b.soldiers.drawn_yaw(i) - float(face) + 512.0, 1024.0) - 512.0) > 60.0:
			turned += 1
	_check(turned * 10 >= sim.u_alive[u] * 8, "marching obliquely: %d of %d men are drawn off the unit's ordered facing" % [turned, sim.u_alive[u]])
	await _both("a column marching obliquely", c, 12.0)
	await _shot("march_oblique")
	# Heavy swords (own sidestep / backstep frames; the cavalry above keep the
	# walk): a line dressing 5 m sideways, then a back step of 4 m.
	var h := 1
	base = sim.u_slot_base[h]
	_step(60)
	ox = sim.u_cx[h]
	oy = sim.u_cy[h]
	face = sim.u_face[h]
	var fa := float(face) * TAU / 1024.0
	var fx := cos(fa)
	var fy := sin(fa)
	sim.queue_order(BattleSim.make_move_order(sim.tick, h, ox + int((-fy * 5.0 + fx * FRONT) * 1024.0), oy + int((fx * 5.0 + fy * FRONT) * 1024.0), face, 0, 0))
	_step(10)
	c = Vector2(sim.u_cx[h], sim.u_cy[h]) / 1024.0
	_look(c, 1.6)
	await _frames(3)
	var act_n := 0
	for s in sim.u_alive[h]:
		var i: int = sim.slot_soldier[base + s]
		var v := Vector2(sim.pos_x[i] - sim.prev_x[i], sim.pos_y[i] - sim.prev_y[i])
		if SoldierLayer.step_action(v, b.soldiers.drawn_yaw(i)).action == 4:
			act_n += 1
	_check(act_n > 0, "heavy swords dressing sideways: %d of %d men sidestep" % [act_n, sim.u_alive[h]])
	await _both("heavy swords mid-sidestep", c, 12.0)
	_look(c, 3.5)
	await _shot("sidestep")
	_step(60)
	ox = sim.u_cx[h]
	oy = sim.u_cy[h]
	sim.queue_order(BattleSim.make_move_order(sim.tick, h, ox + int((fy * 5.0 + fx * FRONT) * 1024.0), oy + int((-fx * 5.0 + fy * FRONT) * 1024.0), face, 0, 0))
	_step(12)
	c = Vector2(sim.u_cx[h], sim.u_cy[h]) / 1024.0
	await _both("heavy swords mid-sidestep to the other side", c, 12.0)
	_look(c, 3.5)
	await _shot("sidestep_other")
	_step(60)
	ox = sim.u_cx[h]
	oy = sim.u_cy[h]
	face = sim.u_face[h]
	sim.queue_order(BattleSim.make_move_order(sim.tick, h, ox + int(fx * (FRONT - 4.0) * 1024.0), oy + int(fy * (FRONT - 4.0) * 1024.0), face, 0, 0))
	_step(10)
	c = Vector2(sim.u_cx[h], sim.u_cy[h]) / 1024.0
	_look(c, 1.6)
	await _frames(3)
	act_n = 0
	for s in sim.u_alive[h]:
		var i: int = sim.slot_soldier[base + s]
		var v := Vector2(sim.pos_x[i] - sim.prev_x[i], sim.pos_y[i] - sim.prev_y[i])
		if SoldierLayer.step_action(v, b.soldiers.drawn_yaw(i)).action == 5:
			act_n += 1
	_check(act_n > 0, "heavy swords backing up: %d of %d men backstep" % [act_n, sim.u_alive[h]])
	await _both("heavy swords mid-backstep", c, 12.0)
	_look(c, 3.5)
	await _shot("backstep")
	# A line dressing: an 8 m step sideways, the facing kept.
	base = sim.u_slot_base[u]
	_step(500)
	ox = sim.u_cx[u]
	oy = sim.u_cy[u]
	face = sim.u_face[u]
	sim.queue_order(BattleSim.make_move_order(sim.tick, u, ox - 4 * 1024, oy - 7 * 1024, face, 0, 0))
	_step(14)
	c = Vector2(sim.u_cx[u], sim.u_cy[u]) / 1024.0
	_look(c, 1.6)
	await _frames(3)
	var kept := 0
	for s in sim.u_alive[u]:
		var i: int = sim.slot_soldier[base + s]
		if b.soldiers.drawn_yaw(i) == float(sim.facing[i]):
			kept += 1
	_check(kept == sim.u_alive[u], "dressing the line: all %d men keep the unit's facing" % kept)
	# The action chosen for a short move against the heading: a sidestep
	# (mirrored when to the right), a backstep, and the march unchanged.
	var fwd_v := Vector2(1.0, 0.0)
	var r := SoldierLayer.step_action(fwd_v * 40.0, 0.0)
	_check(r.action == 1, "a step along the heading plays the walk (march)")
	r = SoldierLayer.step_action(Vector2(0.0, -40.0), 0.0)
	_check(r.action == 4 and not r.mirrored, "a step to his left plays the sidestep as rendered")
	r = SoldierLayer.step_action(Vector2(0.0, 40.0), 0.0)
	_check(r.action == 4 and r.mirrored, "a step to his right plays the sidestep mirrored")
	r = SoldierLayer.step_action(Vector2(-40.0, 0.0), 0.0)
	_check(r.action == 5, "a step backwards plays the backstep")
	r = SoldierLayer.step_action(Vector2(0.0, 40.0), 256.0)  # heading +y (a quarter turn)
	_check(r.action == 1, "heading is respected: along a turned heading it is the walk")
	r = SoldierLayer.step_action(Vector2(0.0, -40.0), 256.0)
	_check(r.action == 5, "heading is respected: against a turned heading it is the backstep")
	# In the live battle: the line dressing's men move laterally / backwards
	# against their drawn heading, so a lateral or backward action is chosen.
	var shuffle := 0
	for s in sim.u_alive[u]:
		var i: int = sim.slot_soldier[base + s]
		var v := Vector2(sim.pos_x[i] - sim.prev_x[i], sim.pos_y[i] - sim.prev_y[i])
		var ra := SoldierLayer.step_action(v, b.soldiers.drawn_yaw(i))
		if ra.action == 4 or ra.action == 5:
			shuffle += 1
	_check(shuffle > 0, "dressing the line: %d of %d men choose a sidestep or backstep" % [shuffle, sim.u_alive[u]])
	await _both("a line dressing", c, 12.0)
	await _shot("line_dressing")
	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)
