extends SceneTree
## Line of fire past a house (docs/design/battle_sim.md "Buildings block a flat shot (as built, 2026-11-06)"): the
## lof_probe's town case (a 60-man line 40 or 120 m off a pike block standing behind the outermost house of a West
## open town), the line ordered to attack, stepped by hand N ticks, the line selected (its order preview drawn), shot
## (windowed):
##   godot --path . --resolution 1280x720 -s tests/lof_shot.gd -- --out=FILE.png [--weapon=musket|bow] [--dist=40]
##       [--ticks=0] [--view=oblique|top] [--zoom=3] [--mode=atk|ai] [--fly]
## --fly: after N ticks, on until a shot of the line is in flight halfway. --cover: the order preview of a line dragged
## along the house's outer face (2.5 m out, facing the pikes): the cover shield at its end.
const Battle := preload("res://game/battle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const BoardView := preload("res://game/board_view.gd")
const Probe := preload("res://tests/lof_probe.gd")
var battle: Battle
var out := "user://lof.png"
var weapon := "musket"
var dist := 40
var ticks := 0
var zoom := 3.0
var mode := "atk"
var fly := false
var cover := false
var cover_at := Vector2.ZERO
var frame := 0
var wait := -1
var focus := Vector2.ZERO


func _initialize() -> void:
	BoardView.force = "oblique"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for a in OS.get_cmdline_user_args():
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--out="): out = v
		elif a.begins_with("--weapon="): weapon = v
		elif a.begins_with("--dist="): dist = int(v)
		elif a.begins_with("--ticks="): ticks = int(v)
		elif a.begins_with("--view="): BoardView.force = v
		elif a.begins_with("--zoom="): zoom = float(v)
		elif a.begins_with("--mode="): mode = v
		elif a == "--fly": fly = true
		elif a == "--cover": cover = true
	battle = Battle.new()
	battle.custom_scenario = Probe.town(weapon, dist, mode)
	battle.seed_value = 7
	root.add_child(battle)


func _flying(s) -> bool:
	for p in s.pr_t1.size():
		if s.pr_unit[p] == 0 and s.pr_t0[p] <= s.tick and s.pr_t1[p] > s.tick and (s.tick - s.pr_t0[p]) * 2 >= s.pr_t1[p] - s.pr_t0[p] - 1:
			return true
	return false


func _process(_d: float) -> bool:
	frame += 1
	if frame == 5:
		battle.paused = true
		battle.hud.visible = false
		if battle.dive_t >= 0.0:
			battle.dive_finish()
	if frame == 30:
		var s = battle.sim
		if mode == "atk":
			s.queue_order(BattleSim.make_attack_order(s.tick, 0, 1, 0))
		for i in ticks:
			s.step()
		if fly:
			var k := 0
			while not _flying(s) and k < 3000:
				s.step()
				k += 1
		print("tick ", s.tick, " shots ", s.stat_shots, " lof ", s.lof_units(0, 1), " line at ", Vector2(s.u_cx[0], s.u_cy[0]) / 1024.0,
			" pikes at ", Vector2(s.u_cx[1], s.u_cy[1]) / 1024.0, " pikes lost ", s.u_count0[1] - s.u_alive[1])
		battle._select(0)
		if cover:
			var t := Vector2(s.u_cx[1], s.u_cy[1]) / 1024.0
			var o := (Vector2(s.u_cx[0], s.u_cy[0]) / 1024.0 - t).normalized()
			var q := t
			var inb := false
			for k in 200:
				var b: bool = s.obs_kind(int(q.x * 1024), int(q.y * 1024)) == 1
				if inb and not b:
					break
				inb = inb or b
				q += o * 0.25
			var pc := (q + o * 2.5) * Battle.PX_PER_M
			var dd := Vector2(-o.x, -o.y).rotated(PI * 0.5) * 4.0 * Battle.PX_PER_M
			battle.overlay.preview_on = true
			battle.overlay.preview_ok = true
			battle.overlay.preview_a = pc - dd
			battle.overlay.preview_b = pc + dd
			print("cover rating ", s.cover_rating_front(int(pc.x / Battle.PX_PER_M * 1024), int(pc.y / Battle.PX_PER_M * 1024),
				int(round(atan2(-o.y, -o.x) * 1024.0 / TAU)) & 1023, 4 * 1024))
			cover_at = pc
		battle.soldiers.upload()
		battle.soldiers.set_alpha(1.0)
		battle._view_tick()
		var mid := (Vector2(s.u_cx[0], s.u_cy[0]) + Vector2(s.u_cx[1], s.u_cy[1])) * 0.5 / 1024.0
		focus = mid * Battle.PX_PER_M if not cover else cover_at
		wait = frame + 25
	if wait > 0 and frame < wait:
		battle.camera.zoom = Vector2.ONE * zoom
		battle._cam_to(focus)
		battle.camera.force_update_scroll()
		battle.overlay.queue_redraw()
	elif wait > 0 and frame >= wait:
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		BoardView.force = ""
		quit(0)
	return false
