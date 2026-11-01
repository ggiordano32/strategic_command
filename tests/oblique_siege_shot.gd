extends SceneTree
## The siege equipment standing in the oblique view (windowed, view only; docs/design/art_pipeline.md "(2026-11-01) Siege
## equipment in oblique"): a walled town (walls 2, towers), the attackers' ladders, poles, ram, tower and mantlets put by hand
## on the field before one wall (the sim is never stepped), shot at 1280x720 in the oblique view:
##   godot --path . --resolution 1280x720 -s tests/oblique_siege_shot.gd -- --out=DIR [--zoom=3]
## Saves DIR/siege_planted.png (a planted set, planted poles, a planted tower), DIR/siege_ground.png (a ram at the gate, a set
## and poles on the ground, mantlets and a wrecked ram), DIR/siege_carried.png (carried: a set, a ram, a tower, a mantlet).

const Battle := preload("res://game/battle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const BoardView := preload("res://game/board_view.gd")
const Terrain := preload("res://sim/terrain.gd")
const MapGen := preload("res://sim/mapgen.gd")
const M := 1024

var battle: Battle
var out := "user://"
var zoom := 3.0
var frame := 0
var shots := 0
var focus := Vector2.ZERO


func _initialize() -> void:
	BoardView.force = "oblique"
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.get_slice("=", 1).trim_suffix("/") + "/"
		elif a.begins_with("--zoom="):
			zoom = float(a.get_slice("=", 1))
	var sc := Scenarios.siege_test(3, 2, 2, MapGen.PAL_DRY, Terrain.K_FLAT, 1, -1, MapGen.PLAN_RING, 0,
		{"ladders": 2, "ram": 1, "towers": 1, "poles": 1, "mantlets": 2})
	battle = Battle.new()
	battle.custom_scenario = sc
	battle.seed_value = 1
	root.add_child(battle)


## A stretch facing +y (south, toward the camera) as long as any: returns [seg, mid x, mid y] in sim units.
func _south_stretch() -> int:
	var sim = battle.sim
	var best := -1
	var bl := 0
	for sg in sim.ws_dir.size():
		var d: int = sim.ws_dir[sg]
		var l := 1000 - absi(d - 256)
		if l > bl:
			bl = l
			best = sg
	return best


var _t := Vector2.RIGHT      # along the stretch (unit), sim axes
var _o := Vector2.DOWN       # out from it (unit)
var _m := Vector2.ZERO       # its middle, sim units


## A point `a` metres along the stretch from its middle and `b` metres out, in sim units.
func _at(a: float, b: float) -> Vector2i:
	var v := _m + (_t * a + _o * b) * M
	return Vector2i(int(v.x), int(v.y))


func _put(q: int, st: int, x: int, y: int, face := 0) -> void:
	var sim = battle.sim
	sim.q_state[q] = st
	sim.q_unit[q] = -1
	sim.q_x[q] = x
	sim.q_y[q] = y
	sim.q_face[q] = face


func _arrange() -> void:
	var sim = battle.sim
	var sg := _south_stretch()
	if sg < 0:
		print("no south stretch")
		quit(1)
		return
	var mx: int = (sim.ws_x0[sg] + sim.ws_x1[sg]) / 2
	var my: int = (sim.ws_y0[sg] + sim.ws_y1[sg]) / 2
	var dir: int = sim.ws_dir[sg]
	_m = Vector2(mx, my)
	_t = Vector2(sim.ws_x1[sg] - sim.ws_x0[sg], sim.ws_y1[sg] - sim.ws_y0[sg]).normalized()
	_o = Vector2(cos(dir * TAU / 1024.0), sin(dir * TAU / 1024.0))
	var tx := 1
	print("stretch ", sg, " dir ", dir, " mid ", mx / M, ",", my / M, " len ", (absi(sim.ws_x1[sg] - sim.ws_x0[sg])) / M)
	var ladders: Array = []
	var poles := -1
	var ram := -1
	var tower := -1
	var mants: Array = []
	for q in sim.n_eq:
		match sim.q_kind[q]:
			BattleSim.EQ_LADDERS: ladders.append(q)
			BattleSim.EQ_POLES: poles = q
			BattleSim.EQ_RAM: ram = q
			BattleSim.EQ_TOWER: tower = q
			BattleSim.EQ_MANTLET: mants.append(q)
	focus = Vector2(_at(0, -2)) / M * Battle.PX_PER_M
	# Planted: a ladder set left, poles, a tower right (their feet 2 m out from the wall's centre line).
	var f1 := _at(-12, 2)
	if not ladders.is_empty():
		_put(ladders[0], BattleSim.Q_PLANTED, f1.x, f1.y)
		sim.q_seg[ladders[0]] = sg
	if poles >= 0:
		var f2 := _at(0, 2)
		_put(poles, BattleSim.Q_PLANTED, f2.x, f2.y)
		sim.q_seg[poles] = sg
	if tower >= 0:
		var f3 := _at(13, 2)
		_put(tower, BattleSim.Q_PLANTED, f3.x, f3.y)
		sim.q_seg[tower] = sg
	var far := _at(0, 90)
	for q in [ram] + ladders.slice(1) + mants:
		if q >= 0:
			_put(q, BattleSim.Q_GROUND, far.x, far.y)
	for q in mants:
		sim.q_len[q] = 4 * M
	battle.set_meta("pieces", [ladders, poles, ram, tower, mants, mx, my, tx, sg])


func _stage(n: int) -> void:
	var sim = battle.sim
	var p: Array = battle.get_meta("pieces")
	var ladders: Array = p[0]
	var poles: int = p[1]
	var ram: int = p[2]
	var tower: int = p[3]
	var mants: Array = p[4]
	var _mx: int = p[5]
	var _my: int = p[6]
	var _tx: int = p[7]
	var _P := func(a: float, b: float): return _at(a, b)
	if n == 1:
		var fa := _at(-16, 18)
		_put(ladders[1], BattleSim.Q_GROUND, fa.x, fa.y, 100)
		fa = _at(-8, 18)
		_put(poles, BattleSim.Q_GROUND, fa.x, fa.y, 180)
		fa = _at(2, 12)
		_put(ram, BattleSim.Q_GROUND, fa.x, fa.y, int(_o.angle() * 1024.0 / TAU))
		for i in mants.size():
			fa = _at(12 + 7 * i, 14)
			_put(mants[i], BattleSim.Q_GROUND, fa.x, fa.y, int(_o.angle() * 1024.0 / TAU) + 1024)
		fa = _at(-30, 12)
		_put(ladders[0], BattleSim.Q_WRECKED, fa.x, fa.y, 0)
		fa = _at(30, 14)
		_put(tower, BattleSim.Q_WRECKED, fa.x, fa.y, 0)
	elif n == 2:
		# Carried by unit 0 (its facing is the carried pieces' heading), the wrecked ones beside.
		var fa := _at(-10, 12)
		for q in [ladders[0], ram, mants[0]]:
			_put(q, BattleSim.Q_CARRIED, fa.x, fa.y)
			sim.q_unit[q] = 0
			fa = _at(2 if q == ladders[0] else 14, 12)
		sim.u_face[0] = int(_o.angle() * 1024.0 / TAU) + 1024 - 256
		fa = _at(14, 8)
		_put(ladders[1], BattleSim.Q_WRECKED, fa.x, fa.y)
		fa = _at(24, 12)
		_put(poles, BattleSim.Q_WRECKED, fa.x, fa.y)
		fa = _at(-2, 24)
		_put(tower, BattleSim.Q_CARRIED, fa.x, fa.y)
		sim.q_unit[tower] = 0
		fa = _at(24, 4)
		_put(mants[1], BattleSim.Q_WRECKED, fa.x, fa.y)
	focus = Vector2(_at(0, -2)) / M * Battle.PX_PER_M


func _process(_d: float) -> bool:
	frame += 1
	if frame == 20:
		if not battle.paused:
			battle._toggle_pause()
		battle.hud.visible = false
		_arrange()
		_view()
	elif frame == 40 or frame == 70:
		var n := 0 if frame == 40 else 1
		if n == 1:
			_stage(1)
			_view()
		else:
			_view()
	elif frame == 100:
		_stage(2)
		_view()
	elif frame == 55 or frame == 85 or frame == 115:
		var n2 := 0 if frame == 55 else (1 if frame == 85 else 2)
		var img := root.get_texture().get_image()
		img.save_png(out + ["siege_planted.png", "siege_ground.png", "siege_carried_wrecked.png"][n2])
		print("saved ", n2)
		if n2 == 2:
			BoardView.force = ""
			quit(0)
	return false


func _view() -> void:
	battle.camera.zoom = Vector2.ONE * zoom
	battle._cam_to(focus)
	battle.camera.force_update_scroll()
	battle.overlay.queue_redraw()
