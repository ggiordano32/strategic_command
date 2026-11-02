extends SceneTree
## Missiles at the target's height (docs/design/art_pipeline.md "Projectiles at the target's height"): a siege fought by the
## AI on both sides, stepped by hand until a missile of the wanted kind is in flight, then shot (windowed):
##   godot --path . --resolution 1280x720 -s tests/arrow_height_shot.gd -- --out=FILE.png --want=up|down|engine|stone
##       [--view=oblique|top] [--zoom=6] [--seed=1] [--cpu] [--back=0]
## up: an arrow aimed at a man on a wall, shot from the ground; down: from a wall at the ground; engine: a tower engine's
## shot; stone: an artillery stone in flight to a point on a walk. --back=N: shoot N ticks before it lands (6).
const Battle := preload("res://game/battle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const BoardView := preload("res://game/board_view.gd")
const Terrain := preload("res://sim/terrain.gd")
const MapGen := preload("res://sim/mapgen.gd")
const UT := preload("res://sim/unit_types.gd")
var battle: Battle
var out := "user://arrow.png"
var want := "up"
var zoom := 6.0
var seed_v := 1
var back := 6
var at_start := false   # --start: look at the firing point, N=back ticks after the shot left
var dy := -9.0   # metres: the camera looks above the ground point (the walk is lifted)
var frame := 0
var found := -1
var focus := Vector2.ZERO
var wait := 0


func _initialize() -> void:
	BoardView.force = "oblique"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for a in OS.get_cmdline_user_args():
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--out="): out = v
		elif a.begins_with("--want="): want = v
		elif a.begins_with("--view="): BoardView.force = v
		elif a.begins_with("--zoom="): zoom = float(v)
		elif a.begins_with("--seed="): seed_v = int(v)
		elif a.begins_with("--dy="): dy = float(v)
		elif a == "--start": at_start = true
		elif a.begins_with("--back="): back = int(v)
	if "--before" in OS.get_cmdline_user_args():
		Battle.SoldierLayer.missile_heights = false
	var sc := Scenarios.siege_test(3, 2, 2, MapGen.PAL_DRY, Terrain.K_FLAT, 1, -1, MapGen.PLAN_RING, 0,
		{"ladders": 2, "ram": 1, "towers": 1, "poles": 1, "mantlets": 2})
	battle = Battle.new()
	battle.custom_scenario = sc
	battle.seed_value = seed_v
	root.add_child(battle)


func _match() -> int:
	var s = battle.sim
	var tk: int = s.tick
	for p in s.pr_t1.size():
		if s.pr_t1[p] < 0 or s.pr_t1[p] <= tk + 1 or s.pr_t0[p] > tk:
			continue
		var su: int = s.pr_unit[p]
		var tu: int = s.pr_tu[p]
		var ty: int = s.pr_ty[p]
		var art: bool = s.t_cls[ty] == UT.CLS_ART
		match want:
			"up":
				if not art and tu >= 0 and s.u_wall[tu] > 0 and s.u_wall[su] == 0 and s.u_neng[su] == 0 and s.pr_t1[p] - tk > 3:
					return p
			"down":
				if not art and s.u_wall[su] > 0 and tu >= 0 and s.u_wall[tu] == 0 and s.pr_t1[p] - tk > 3:
					return p
			"engine":
				if s.u_neng[su] > 0 and tu >= 0 and s.pr_t1[p] - tk > 3:
					return p
			"stone":
				if art and UT.stat(ty, "m_kind") != 1 and s.obs_kind(s.pr_x[p], s.pr_y[p]) in [MapGen.C_WALK, MapGen.C_TOWER]:
					return p
	return -1


func _process(_d: float) -> bool:
	frame += 1
	if frame == 5:
		if "--cpu" in OS.get_cmdline_user_args():
			battle.soldiers.set_cpu_fed(true)
		battle.paused = true
		battle.hud.visible = false
		if battle.dive_t >= 0.0:
			battle.dive_finish()
	if frame >= 30 and found < 0:
		var s = battle.sim
		for i in 40:
			s.step()
			found = _match()
			if found >= 0:
				break
		if found < 0 and s.tick > 6000:
			print("NO MATCH by tick ", s.tick)
			quit(1)
			return false
		if found >= 0:
			var p := found
			var mid := Vector2(s.pr_x[p], s.pr_y[p]) * 0.92 + Vector2(s.pr_sx[p], s.pr_sy[p]) * 0.08
			if at_start:
				mid = Vector2(s.pr_x[p], s.pr_y[p]) * 0.08 + Vector2(s.pr_sx[p], s.pr_sy[p]) * 0.92
			print("MATCH tick ", s.tick, " slot ", p, " from ", Vector2(s.pr_sx[p], s.pr_sy[p]) / 1024.0, " to ", Vector2(s.pr_x[p], s.pr_y[p]) / 1024.0, " tu ", s.pr_tu[p], " ty ", s.pr_ty[p], " ak ", s.pr_ak[p], " art ", s.t_cls[s.pr_ty[p]] == UT.CLS_ART)
			var left: int = back if at_start else s.pr_t1[p] - s.tick - back   # --back=N: N ticks before it lands
			for i in maxi(left, 0):
				s.step()
			var lay: Dictionary = s.map_info["city"]
			print("CITY ", Vector2(int(lay["cx"]), int(lay["cy"])), " field ", Vector2(s.field_w, s.field_h) / 1024.0, " focus m ", mid / 1024.0, " tu pos ", Vector2(s.u_cx[s.pr_tu[p]], s.u_cy[s.pr_tu[p]]) / 1024.0 if s.pr_tu[p] >= 0 else Vector2.ZERO)
			battle.soldiers.upload()
			battle.soldiers.set_alpha(1.0)
			battle._view_tick()
			focus = (mid / 1024.0 + Vector2(0, dy)) * Battle.PX_PER_M
			battle.camera.zoom = Vector2.ONE * zoom
			battle._cam_to(focus)
			battle.camera.force_update_scroll()
			battle.overlay.queue_redraw()
			wait = frame + 25
	elif found >= 0 and frame < wait:
		battle.camera.zoom = Vector2.ONE * zoom
		battle._cam_to(focus)
		battle.camera.force_update_scroll()
	elif found >= 0 and frame >= wait:
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		BoardView.force = ""
		quit(0)
	return false
