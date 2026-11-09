extends SceneTree
## Missiles at men in a held building and at a siege tower (docs/design/art_pipeline.md "Men in a held building and at a
## siege tower"): a West town (--want=house: the defenders' musket companies sent into houses, the AI attacking) or a
## walls-2 ring with a siege tower (--want=tower), stepped by hand until a missile of the wanted kind is in flight,
## then shot (windowed):
##   godot --path . --resolution 1280x720 -s tests/held_height_shot.gd -- --out=FILE.png --want=house|house_from|tower
##       [--view=oblique|top] [--zoom=6] [--seed=1] [--cpu] [--back=6] [--town=havana] [--before] [--dy=-4]
## house: a shot at a man of a held building; house_from: a shot from one; tower: a shot landing on a siege tower.
const Battle := preload("res://game/battle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const BoardView := preload("res://game/board_view.gd")
const Terrain := preload("res://sim/terrain.gd")
const MapGen := preload("res://sim/mapgen.gd")
const UT := preload("res://sim/unit_types.gd")
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTown := preload("res://campaign/ctown.gd")
const FM := preload("res://sim/fixed_math.gd")
const M := 1024
var battle: Battle
var out := "user://held.png"
var want := "house"
var town := "havana"
var zoom := 6.0
var seed_v := 1
var back := 6
var dy := -4.0
var frame := 0
var found := -1
var focus := Vector2.ZERO
var wait := 0


func _initialize() -> void:
	BoardView.force = "3d"   # (--view=oblique|top: the flat views, a developer aid)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for a in OS.get_cmdline_user_args():
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--out="): out = v
		elif a.begins_with("--want="): want = v
		elif a.begins_with("--view="): BoardView.force = v
		elif a.begins_with("--zoom="): zoom = float(v)
		elif a.begins_with("--seed="): seed_v = int(v)
		elif a.begins_with("--dy="): dy = float(v)
		elif a.begins_with("--town="): town = v
		elif a.begins_with("--back="): back = int(v)
	if "--before" in OS.get_cmdline_user_args():
		Battle.SoldierLayer.missile_heights = false
	var sc: Dictionary
	if want.begins_with("house"):
		sc = _town_scenario(town)
		sc["ai_sides"] = [0]
		sc["ai_skill"] = [1, 1]
	else:
		sc = Scenarios.siege_test(3, 2, 2, MapGen.PAL_DRY, Terrain.K_FLAT, 1, -1, MapGen.PLAN_RING, 0,
			{"ladders": 2, "ram": 1, "towers": 1, "poles": 1, "mantlets": 2})
	battle = Battle.new()
	battle.custom_scenario = sc
	battle.seed_value = seed_v
	root.add_child(battle)


## The defenders' musket companies go into the houses nearest the street mouths (as tests/open_town_probe.gd).
func _occupy_orders(sim) -> void:
	var lay: Dictionary = sim.map_info["city"]
	var mouths: Array = lay.get("mouths", [])
	var px: int = sim.plaza[0]
	var py: int = sim.plaza[1]
	var taken := {}
	var k := 0
	for u in sim.n_units:
		if sim.u_side[u] != 1:
			continue
		var gun: bool = UT.stat(sim.u_type[u], "m_gun") != 0 and sim.u_cls[u] != UT.CLS_CAV and BattleSim.stance_ok(sim.u_type[u])
		if not gun or mouths.is_empty() or sim.occ_on == 0:
			continue
		var mo: Array = mouths[k % mouths.size()]
		k += 1
		var tx: int = int(mo[0]) * M + (px - int(mo[0]) * M) / 10
		var ty: int = int(mo[1]) * M + (py - int(mo[1]) * M) / 10
		var best := -1
		var bd := 1 << 40
		for b in sim.ob_ok.size():
			if sim.ob_ok[b] == 0 or taken.has(b) or sim.ob_sn[b] < 4:
				continue
			var d := FM.approx_len(sim.ob_dx[b] - tx, sim.ob_dy[b] - ty)
			if d < bd:
				bd = d
				best = b
		if best >= 0:
			taken[best] = 1
			sim.queue_order({"tick": 0, "type": BattleSim.ORDER_OCCUPY, "unit": u, "building": best, "run": 1, "player": 1})
			sim.queue_order({"tick": 0, "type": BattleSim.ORDER_FIRE, "unit": u, "on": 1, "player": 1})


func _town_scenario(key: String) -> Dictionary:
	CData.use_pack("west")
	var r := CData.region_index(key)
	var cul := CData.region_culture(r)
	var st0 := CState.new_campaign("bal", 5, [], {}, [], "west")
	var level := maxi(1, int(st0["regions"][r]["level"]))
	var rd: Dictionary = CData.REGIONS[r]
	var cseed := 0
	for ch in key.to_utf8_buffer():
		cseed = (cseed * 31 + int(ch)) % 100000
	var att: Array = []
	for e in Scenarios.WEST_ATT:
		att.append([UT.index_of(str(e[0])), int(e[1])])
	var dfn: Array = att.duplicate(true)
	var terr := {"kind": int(rd["terrain"]), "seed": cseed * 7 + 3, "forest": int(rd["forest"]), "ground": int(rd["ground"])}
	var city := {"seed": cseed, "level": level, "walls": 0, "bld": [1, 2, 4], "plan": cul,
		"coast": 1 if CData.is_port(r) else 0, "founder": cul, "west": 1}
	var st := CState.new_campaign("bal", 5, [], {}, [], "west")
	city["tp"] = CTown.battle_plan(st, r)
	return Scenarios.settlement(city, terr, att, dfn, 1, [0, 1], {})["scenario"]

func _tower_hit(x: int, y: int) -> int:
	var s = battle.sim
	for q in s.n_eq:
		if s.q_kind[q] != BattleSim.EQ_TOWER or s.q_state[q] == BattleSim.Q_WRECKED:
			continue
		var c := Vector2i(s.q_x[q], s.q_y[q])
		if s.q_state[q] == BattleSim.Q_PLANTED:
			c = s.eq_centre(q)
		var h: int = BattleSim.EQ_DEPTH2[BattleSim.EQ_TOWER]
		if absi(x - c.x) <= h + M and absi(y - c.y) <= h + M:
			return q
	return -1


## --want=ladder: a unit on a ladder or tower climb with men below and men up (the view's lift for them).
var ladder_unit := -1
var ladder_at := Vector2.ZERO


func _match_ladder() -> int:
	var s = battle.sim
	for u in s.n_units:
		if s.u_stair[u] != BattleSim.ST_LADDER or s.u_alive[u] < 3:
			continue
		var up := 0
		var base: int = s.u_slot_base[u]
		for sl in s.u_alive[u]:
			var i: int = s.slot_soldier[base + sl]
			if s.state[i] < 4 and s._on_walk(s.pos_x[i], s.pos_y[i]):
				up += 1
		if up >= 1 and up < s.u_alive[u] - 1:
			ladder_unit = u
			for sl in s.u_alive[u]:
				var i: int = s.slot_soldier[base + sl]
				if s.state[i] < 4 and s._on_walk(s.pos_x[i], s.pos_y[i]):
					ladder_at = Vector2(s.pos_x[i], s.pos_y[i])
					break
			return 0
	return -1


func _match() -> int:
	var s = battle.sim
	var tk: int = s.tick
	if want == "ladder":
		return _match_ladder()
	for p in s.pr_t1.size():
		if s.pr_t1[p] < 0 or s.pr_t1[p] <= tk + 1 or s.pr_t0[p] > tk:
			continue
		var su: int = s.pr_unit[p]
		var tu: int = s.pr_tu[p]
		if su < 0 or su >= s.n_units:
			continue
		match want:
			"house":
				if tu >= 0 and s.u_occ[tu] > 0 and s.pr_t1[p] - tk > 3:
					return p
			"house_from":
				if s.u_occ[su] > 0 and s.pr_t1[p] - tk > 3:
					return p
			"tower":
				if _tower_hit(s.pr_x[p], s.pr_y[p]) >= 0 and s.pr_t1[p] - tk > 3:
					return p
	return -1


## --want=tower: the siege tower put against the south stretch by hand (the AI rarely plants one where shots land on it) and
## arrows from the ground and from the walk injected into the missile slots, half way through their flight (the sim is not
## stepped: the view reads only the arrays).
func _stage_tower() -> void:
	var s = battle.sim
	var best := -1
	var bl := 0
	for sg in s.ws_dir.size():
		var l := 1000 - absi(int(s.ws_dir[sg]) - 256)
		if l > bl:
			bl = l
			best = sg
	var m := Vector2((s.ws_x0[best] + s.ws_x1[best]) / 2, (s.ws_y0[best] + s.ws_y1[best]) / 2)
	var t := Vector2(s.ws_x1[best] - s.ws_x0[best], s.ws_y1[best] - s.ws_y0[best]).normalized()
	var o := Vector2(cos(s.ws_dir[best] * TAU / 1024.0), sin(s.ws_dir[best] * TAU / 1024.0))
	var tq := -1
	for q in s.n_eq:
		if s.q_kind[q] == BattleSim.EQ_TOWER:
			tq = q
	var foot := m + (t * 0.0 + o * 2.0) * M
	s.q_state[tq] = BattleSim.Q_PLANTED
	s.q_unit[tq] = -1
	s.q_x[tq] = int(foot.x)
	s.q_y[tq] = int(foot.y)
	s.q_seg[tq] = best
	var c: Vector2i = s.eq_centre(tq)
	var arch := -1
	for u in s.n_units:
		if s.u_side[u] == 0 and UT.stat(s.u_type[u], "m_range") > 0 and s.u_cls[u] != UT.CLS_ART:
			arch = u
			break
	# Slots 0-2: from the ground 30 / 22 / 14 m out at the tower's middle, the next from the wall walk (wall 4 m along) at ground men below.
	var tk: int = s.tick
	for k in 3:
		var from := Vector2(c) + (o * (30.0 - 8.0 * k)) * M - t * (6.0 * M)
		_put_missile(k, from, Vector2(c) + t * (1.0 * k) * M, tk - 4 - 2 * k, tk + 10 - 2 * k, arch, -1)
	var from2 := m + (t * 7.0 + o * -0.5) * M   # (on the walk, beside the tower)
	_put_missile(3, from2, Vector2(c) + (o * 6.0 + t * 4.0) * M, tk - 5, tk + 8, arch, -1)
	s.pr_count = 4
	var mid := Vector2(c) + o * 8.0 * M
	focus = (mid / 1024.0 + Vector2(0, dy)) * Battle.PX_PER_M


func _put_missile(p: int, from: Vector2, to: Vector2, t0: int, t1: int, shooter: int, target: int) -> void:
	var s = battle.sim
	s.pr_sx[p] = int(from.x)
	s.pr_sy[p] = int(from.y)
	s.pr_x[p] = int(to.x)
	s.pr_y[p] = int(to.y)
	s.pr_t0[p] = t0
	s.pr_t1[p] = t1
	s.pr_unit[p] = shooter
	s.pr_ty[p] = s.u_type[shooter]
	s.pr_tu[p] = target
	s.pr_ak[p] = 0


func _process(_d: float) -> bool:
	frame += 1
	if frame == 5:
		if "--cpu" in OS.get_cmdline_user_args():
			battle.soldiers.set_cpu_fed(true)
		elif "--gpu" in OS.get_cmdline_user_args():
			battle.soldiers.set_cpu_fed(false)
		battle.paused = true
		battle.hud.visible = false
		if battle.dive_t >= 0.0:
			battle.dive_finish()
		if want.begins_with("house"):
			_occupy_orders(battle.sim)
		else:
			battle.sim.ai_sides[0] = 1   # (the AI fights for both sides)
	if frame >= 30 and found < 0 and want == "tower":
		_stage_tower()
		found = 0
		battle.soldiers.upload()
		battle.soldiers.set_alpha(1.0)
		battle._view_tick()
		print("HEIGHTS ", battle.soldiers._pr_hs.slice(0, 4), " ", battle.soldiers._pr_he.slice(0, 4), " dm")
		battle.camera.zoom = Vector2.ONE * zoom
		battle._cam_to(focus)
		battle.camera.force_update_scroll()
		wait = frame + 60
	elif frame >= 30 and found < 0:
		var s = battle.sim
		for i in 40:
			s.step()
			battle.soldiers.upload()   # (every tick, as the game does: the heights are worked out at the launch)
			found = _match()
			if found >= 0:
				break
		if found < 0 and s.tick > 9000:
			print("NO MATCH tick ", s.tick, " ladder_up ", s.stat_ladder_up, " planted ", s.stat_planted, " stairs ", s.u_stair)
			quit(1)
			return false
		if found >= 0 and want == "ladder":
			print("MATCH ladder tick ", s.tick, " unit ", ladder_unit, " type ", s.u_type[ladder_unit], " u_wall ", s.u_wall[ladder_unit], " u_lq ", s.u_lq[ladder_unit], " alive ", s.u_alive[ladder_unit], " at ", ladder_at / 1024.0)
			battle.soldiers.upload()
			battle.soldiers.set_alpha(1.0)
			battle._view_tick()
			print("EXT ", battle.soldiers._unit_ext[ladder_unit])
			focus = (ladder_at / 1024.0 + Vector2(0, dy)) * Battle.PX_PER_M
			battle.camera.zoom = Vector2.ONE * zoom
			battle._cam_to(focus)
			battle.camera.force_update_scroll()
			wait = frame + 60
		elif found >= 0:
			var p := found
			var mid := Vector2(s.pr_x[p], s.pr_y[p]) * 0.92 + Vector2(s.pr_sx[p], s.pr_sy[p]) * 0.08
			if want == "house_from":
				mid = Vector2(s.pr_x[p], s.pr_y[p]) * 0.08 + Vector2(s.pr_sx[p], s.pr_sy[p]) * 0.92
			if s.u_occ[s.pr_tu[p]] > 0: print("HELD b ", s.u_occ[s.pr_tu[p]] - 1, " ob_z ", s.ob_z[s.u_occ[s.pr_tu[p]] - 1], " flat ", s.ob_flat[s.u_occ[s.pr_tu[p]] - 1], " unit ext ", battle.soldiers._unit_ext[s.pr_tu[p]])
			print("MATCH tick ", s.tick, " slot ", p, " from ", Vector2(s.pr_sx[p], s.pr_sy[p]) / 1024.0, " to ", Vector2(s.pr_x[p], s.pr_y[p]) / 1024.0, " tu ", s.pr_tu[p], " ty ", s.pr_ty[p])
			var left: int = s.pr_t1[p] - s.tick - back
			if want == "house_from":
				left = back
			for i in maxi(left, 0):
				s.step()
				battle.soldiers.upload()
			battle.soldiers.upload()
			battle.soldiers.set_alpha(1.0)
			battle._view_tick()
			print("HEIGHTS hs ", battle.soldiers._pr_hs[p], " he ", battle.soldiers._pr_he[p], " dm")
			focus = (mid / 1024.0 + Vector2(0, dy)) * Battle.PX_PER_M
			battle.camera.zoom = Vector2.ONE * zoom
			battle._cam_to(focus)
			battle.camera.force_update_scroll()
			battle.overlay.queue_redraw()
			wait = frame + 120
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
