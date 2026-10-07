extends SceneTree
## The deployment phase through the battle view (game/battle.gd), headless:
##   godot --headless --script res://tests/deploy_view_test.gd
## A battle with deploy_time: the deployment bar shows; a tap on the ground
## with a unit selected places it there (the men stand there after one
## step, the clock still at 0); a tap into the enemy half is kept to the
## zone's edge; a tap on an enemy gives no order; Start battle ends the
## deployment (the bar goes away) and the battle clock runs.

const Battle := preload("res://game/battle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")

var battle: Battle
var _ok := true
var _frame := 0


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		_ok = false


func _initialize() -> void:
	var sc := Scenarios.make("battle_2000")
	sc["terrain"] = {"kind": 0}
	sc["deploy_time"] = 30
	sc["deploy_zones"] = Scenarios.field_zones(sc)
	battle = Battle.new()
	battle.custom_scenario = sc
	battle.seed_value = 3
	root.add_child(battle)


func _w2s(x: int, y: int) -> Vector2:
	return battle.get_canvas_transform() * (Vector2(x, y) / 1024.0 * Battle.PX_PER_M)


func _process(_d: float) -> bool:
	_frame += 1
	var sim = battle.sim
	match _frame:
		5:
			_check(sim.phase == BattleSim.PHASE_DEPLOY and battle.hud.deploy_panel.visible,
				"deployment phase with its bar (%s)" % battle.hud.deploy_label.text)
			battle.paused = true  # no steps while we tap
			battle._select(0)
			battle._tap(_w2s(sim.u_ax[0] - 40 * 1024, sim.u_ay[0] + 25 * 1024), false)
		6:
			sim.step()
			_check(sim.tick == 0, "the clock stands at 0 while deploying")
			var want_x: int = sim.u_ax[0]
			_check(sim.u_order[0] == BattleSim.O_NONE and sim.u_dx[0] == want_x, "the tap placed unit 0 (no march)")
			var i: int = sim.slot_soldier[sim.u_slot_base[0]]
			_check(absi(sim.pos_x[i] - sim.u_ax[0] - sim.off_x[sim.u_slot_base[0]]) < 2, "its men stand in their places at once")
			# Into the enemy half: kept to the zone's edge.
			battle._tap(_w2s(sim.u_ax[0], 40 * 1024), false)
		7:
			sim.step()
			var edge: int = BattleSim.deploy_clamp(sim, 0, sim.u_ax[0], 0).y
			_check(sim.u_ay[0] == edge, "a tap into the enemy half is kept to the zone (y %d m)" % (sim.u_ay[0] / 1024))
			var enemy := -1
			for u in sim.n_units:
				if sim.u_side[u] == 1:
					enemy = u
					break
			var before: int = sim.pending_orders.size()
			battle._tap(_w2s(sim.u_cx[enemy], sim.u_cy[enemy]), false)
			_check(sim.pending_orders.size() == before, "a tap on an enemy gives no order in the deployment")
			battle._deploy_ready()
		8:
			sim.step()
			_check(sim.phase == BattleSim.PHASE_BATTLE, "Start battle ends the deployment")
			battle.paused = false
		400:
			_check(sim.tick > 0 and not battle.hud.deploy_panel.visible, "the clock runs (tick %d) and the bar is gone" % sim.tick)
			print("RESULT: ", "PASS" if _ok else "FAIL")
			quit(0 if _ok else 1)
	return false
