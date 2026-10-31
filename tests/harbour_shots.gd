extends SceneTree
## The harbour assault's and the lake of Tayasal's shots (windowed, view only; docs/design/battle_sim.md
## "Amphibious units and the sea gate (as built)"): the scenario run by the AI on both sides until an amphibious unit
## is afloat near the sea gate (the raiders going in; the Itza's sortie going out), the camera on it, saved as a PNG.
##   godot --path . --resolution 1280x720 -s tests/harbour_shots.gd -- --id=west_harbour_assault|tayasal \
##       --out=FILE.png [--view=top|oblique] [--zoom=2.5] [--near=40] [--seed=8100] [--at-gate (canoes in the passage)] [--delay=FRAMES]
const Battle := preload("res://game/battle.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const BoardView := preload("res://game/board_view.gd")
var battle: Battle
var out := "user://harbour.png"
var id := "west_harbour_assault"
var zoom := 2.5
var near := 40
var seed_v := 8100
var frame := 0
var hold := -1
var focus := -1
var at_gate := false
var delay := 0


func _initialize() -> void:
	BoardView.force = "top"
	for a in OS.get_cmdline_user_args():
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--id="): id = v
		elif a.begins_with("--out="): out = v
		elif a.begins_with("--view="): BoardView.force = v
		elif a.begins_with("--zoom="): zoom = float(v)
		elif a.begins_with("--near="): near = int(v)
		elif a.begins_with("--seed="): seed_v = int(v)
		elif a == "--at-gate": at_gate = true
		elif a.begins_with("--delay="): delay = int(v)
	battle = Battle.new()
	battle.custom_scenario = Scenarios.make(id)
	battle.seed_value = seed_v
	root.add_child(battle)


func _process(_d: float) -> bool:
	frame += 1
	if frame == 10:
		battle._toggle_pause()
		battle.camera.zoom = Vector2.ONE * zoom
	elif frame > 10 and hold < 0:
		var s = battle.sim
		for k in 5:
			s.step()
		battle.soldiers.upload()
		battle.soldiers.set_alpha(1.0)
		battle._view_tick()
		if s.harb.size() >= 6:
			for u in s.n_units:
				var tx: int = s.harb[4] if at_gate else s.harb[0]
				var ty: int = s.harb[5] if at_gate else s.harb[1]
				var wet_ok: bool = s.u_wet[u] > 0 if at_gate else s.afloat(u)
				if s.u_state[u] == 0 and wet_ok and (s.u_ai[u] == 40 or s.u_ai[u] == 42) \
						and absi(s.u_cx[u] - tx) + absi(s.u_cy[u] - ty) < near * 1024:
					focus = u
					hold = frame + 6 + delay
					print("hold at tick ", s.tick, " unit ", u, " side ", s.u_side[u], " wet ", s.u_wet[u])
					break
		if frame > 4000:
			print("nobody afloat near the sea gate")
			quit(1)
	elif hold >= 0 and frame < hold:
		var s = battle.sim
		if frame < hold - 6:
			for k in 5:
				s.step()  # (--delay: on into the passage)
			battle.soldiers.upload()
			battle._view_tick()
		var cx: int = s.harb[4] if at_gate else s.u_cx[focus]
		var cy: int = s.harb[5] if at_gate else s.u_cy[focus]
		battle._cam_to(Vector2(cx, cy) / 1024.0 * Battle.PX_PER_M)
	elif hold >= 0 and frame >= hold:
		root.get_texture().get_image().save_png(out)
		print("saved ", out)
		quit(0)
	return false
