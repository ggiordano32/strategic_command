extends SceneTree
## Missiles over a ridge (windowed, view only): a line shoots across a ridge at a target on the other side, paused with
## shots in the air, saved as a PNG.
##   godot --path . --resolution 1280x720 -s tests/shots_over_hill.gd -- --who=musket|archer|pistol --out=FILE.png [--zoom=3] [--ridge=14] [--dist=70] [--bump]
const Battle := preload("res://game/battle.gd")
const UT := preload("res://sim/unit_types.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const BoardView := preload("res://game/board_view.gd")
const Terrain := preload("res://sim/terrain.gd")
var battle: Battle
var out := "user://shot.png"
var who := "musket"
var zoom := 3.0
var rh := 14
var dist := 70
var bump := false
var ry := 150
var frame := 0
var hold := -1

func _initialize() -> void:
	BoardView.force = "oblique"
	for a in OS.get_cmdline_user_args():
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--who="): who = v
		elif a.begins_with("--out="): out = v
		elif a.begins_with("--zoom="): zoom = float(v)
		elif a.begins_with("--ridge="): rh = int(v)
		elif a.begins_with("--dist="): dist = int(v)
		elif a == "--bump": bump = true
		elif a.begins_with("--ry="): ry = int(v)
	var ty := UT.index_of({"musket": "musketeers", "archer": "archer", "pistol": "pistoleers"}[who])
	var feat: Array = [Scenarios.hill(150, ry, 14, rh)] if bump else [Scenarios.ridge(150, ry, 8, rh, 0, 60)]
	var n := 60
	var sc := Scenarios._test_t([Scenarios.unit(0, ty, n, 150, 150 + dist * 55 / 100, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.index_of("light"), 60, 150, 150 - dist * 45 / 100, Scenarios.FACE_DOWN)],
		[Scenarios.attack(0, 0, 1, 0)], feat)
	battle = Battle.new()
	battle.custom_scenario = sc
	battle.seed_value = 1
	root.add_child(battle)

func _live() -> float:
	var s = battle.sim
	var best := -1.0
	for i in s.pr_t1.size():
		if s.pr_t1[i] >= 0 and s.tick >= s.pr_t0[i] and s.tick <= s.pr_t1[i] and s.pr_t1[i] > s.pr_t0[i]:
			var f := float(s.tick - s.pr_t0[i]) / float(s.pr_t1[i] - s.pr_t0[i])
			if best < 0.0 or absf(f - 0.5) < absf(best - 0.5):
				best = f
	return best

func _process(_d: float) -> bool:
	frame += 1
	if frame == 10:
		battle._toggle_pause()
		battle.camera.zoom = Vector2.ONE * zoom
		battle._cam_to(Vector2(150, ry) * Battle.PX_PER_M)
	elif frame > 10 and hold < 0:
		var s = battle.sim
		s.step()
		battle.soldiers.upload()
		battle.soldiers.set_alpha(1.0)
		battle._view_tick()
		var f := _live()
		if f >= 0.4 and f <= 0.6:
			hold = frame + 4
			print("hold at tick ", s.tick, " shots ", s.stat_shots, " u0 ", s.u_cy[0] / 1024, " u1 ", s.u_cy[1] / 1024)
		if frame > 3000:
			print("no shot in the air")
			quit(1)
	elif hold >= 0 and frame >= hold:
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		quit(0)
	return false
