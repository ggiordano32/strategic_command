extends SceneTree
## The native way (docs/design/campaign_rules.md "The native way (as built)"), headless:
##   godot --headless --path . -s tests/tutorial_native_test.gd
## The scenario tutorial_native with its script (game/campaign/tutorial_native.gd) on the battle screen: the six steps
## driven by the player's orders (place and Start battle; the poison bowmen's Ammo order and an attack until they have
## shot; the fire bowmen's Ammo order and a tap on the gate until it burns; Run and a move for the raiders; attacks by
## the warriors and the Holcan), each card's words (Howto.nstep) and its pointer, then the battle fought out (every
## company attacks the nearest Spaniard) to the win and the closing card; a second battle for Skip and Leave the
## tutorial. Windowed with --shots=DIR it also saves each step's card and pointer as DIR/nat_<n>.png:
##   godot --path . --resolution 1280x720 -s tests/tutorial_native_test.gd -- --shots=DIR
## Exits 0 on success, 1 on failure.

const Battle := preload("res://game/battle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const UT := preload("res://sim/unit_types.gd")
const CData := preload("res://campaign/cdata.gd")
const Howto := preload("res://game/campaign/howto.gd")
const Tips := preload("res://game/campaign/tips.gd")
const TutorialNative := preload("res://game/campaign/tutorial_native.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const FM := preload("res://sim/fixed_math.gd")

class ErrCount extends Logger:
	var n := 0
	var first := ""

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_SCRIPT:
			n += 1
			if first == "":
				first = "%s:%d %s %s" % [file, line, code, rationale]


var _errs := ErrCount.new()
var failures := 0
var shots := ""
var bt: Battle = null
var _keep_pack := ""


func _initialize() -> void:
	OS.add_logger(_errs)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.get_slice("=", 1)
	_keep_pack = CData.pack
	_run.call_deferred()


func _check(c: bool, what: String) -> void:
	if c:
		print("PASS ", what)
	else:
		printerr("FAIL ", what)
		failures += 1


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _shot(nm: String) -> void:
	if shots == "":
		return
	await _frames(10)
	root.get_texture().get_image().save_png("%s/nat_%s.png" % [shots, nm])
	print("   shot %s/nat_%s.png" % [shots, nm])


## A new battle on the scenario with the script, as the title's card starts it (game/main.gd _start_with).
func _launch() -> Battle:
	var b := Battle.new()
	b.scenario_id = "tutorial_native"
	b.seed_value = 1671
	b.tutorial = TutorialNative.new()
	if CData.has_pack("west"):
		CData.use_pack("west")
		b.side_name_fkeys = ["miskito", "new_spain"]
	root.add_child(b)
	for k in 600:
		await process_frame
		if b.sim != null and b.hud != null and b.tutorial.card != null:
			break
	await _frames(4)
	return b


func _ptr_at(c: Control) -> bool:
	var tb = bt.tutorial
	return c != null and tb.pointer.showing and tb.pointer.point.distance_to(c.get_global_rect().get_center()) < 2.0


func _ptr_pt(p: Variant) -> bool:
	var tb = bt.tutorial
	return p != null and tb.pointer.showing and tb.pointer.point.distance_to(p) < 2.0


func _words(n: int) -> bool:
	var tb = bt.tutorial
	return tb.card.visible and tb.card.text_label.text == Howto.nstep(n) and tb.card.title_label.text == Howto.text("nstep_title") % n


func _select(units: Array) -> void:
	bt.selection.clear()
	for u in units:
		bt.selection.append(u)
	bt.selected = units[0]
	bt._selection_changed()


## Step the sim (and the view's bookkeeping) until `cond` holds or `max_ticks` pass; returns whether it held.
func _run_until(cond: Callable, max_ticks: int) -> bool:
	for k in max_ticks:
		if cond.call():
			return true
		bt._do_tick()
		if k % 50 == 49:
			bt.tutorial.update()
			await process_frame
	return cond.call()


func _nearest_foe(u: int) -> int:
	var sim = bt.sim
	var best := -1
	var bd := 1 << 62
	for e in sim.n_units:
		if sim.u_side[e] != bt.player_side and sim.u_alive[e] > 0:
			var dx: int = (sim.u_cx[e] - sim.u_cx[u]) / 1024
			var dy: int = (sim.u_cy[e] - sim.u_cy[u]) / 1024
			if dx * dx + dy * dy < bd:
				bd = dx * dx + dy * dy
				best = e
	return best


func _run() -> void:
	_texts()
	_scenario()
	await _lesson()
	await _skip_leave()
	if CData.has_pack(_keep_pack):
		CData.use_pack(_keep_pack)
	_check(_errs.n == 0, "no script errors logged (%d) %s" % [_errs.n, _errs.first])
	print("%s tutorial_native_test: %d failure(s)" % ["RESULT: PASS" if failures == 0 else "RESULT: FAIL", failures])
	quit(0 if failures == 0 else 1)


func _texts() -> void:
	var ok := Howto.NSTEPS == 6
	for n in range(1, Howto.NSTEPS + 1):
		if Howto.nstep(n) == "":
			ok = false
	_check(ok and Howto.text("nstep_1b") != "" and Howto.text("nstep_win") != "" and Howto.text("ui_menu") == "Back to the menu",
		"the native way's six steps, the Start battle card, the closing card and Back to the menu have words")
	_check(Howto.text("nstep_title") % 2 == "Native lesson 2 of 6", "the card title reads Native lesson n of 6")
	_check(Howto.text("ways_3").contains("The native way"), "Three ways to play points at The native way")
	_check(Scenarios.title("tutorial_native") == "The native way", "the scenario's title is The native way")


func _scenario() -> void:
	var sc := Scenarios.make("tutorial_native")
	var keys := []
	var poison := 0
	var fire := 0
	for ud in sc["units"]:
		if int(ud["side"]) == 0:
			keys.append(UT.key_of(int(ud["type"])))
			var ak := int(ud.get("ak", -1))
			if ak == UT.ammo_index("poison_arrows"):
				poison += 1
			elif ak == UT.ammo_index("fire_arrows"):
				fire += 1
	_check(keys.count("native_bowmen") == 3 and keys.count("canoe_raiders") == 2 and keys.count("native_warriors") == 2 and keys.count("holcan") == 1,
		"the war party: three bowmen, two canoe raiders, two warriors, the Holcan (%s)" % str(keys))
	_check(poison == 2 and fire == 1, "two bowmen carry poisoned arrows, one fire arrows (%d, %d)" % [poison, fire])
	_check(int(sc.get("deploy_time", 0)) == -1 and (sc["ai_sides"] as Array) == [1] and (sc["ai_skill"] as Array) == [0, 0],
		"the player places the army; the garrison is the AI on Easy")


func _lesson() -> void:
	bt = await _launch()
	var tb = bt.tutorial
	var sim = bt.sim
	_check(tb is TutorialNative and sim.city_on != 0 and sim.n_gates > 0 and sim.city_walls == 1,
		"the battle has the script and a walls-1 village with gates (%d gates, walls %d)" % [sim.n_gates, sim.city_walls])
	_check(sim.phase == BattleSim.PHASE_DEPLOY and tb.step == 1 and _words(1), "step 1: the deployment, the card has its words")
	await _frames(2)
	_check(_ptr_pt(tb._centroid(true)), "step 1: the pointer is on the war party")
	await _shot("1")
	var poison: Array[int] = tb.ammo_units(false)
	var fire: Array[int] = tb.ammo_units(true)
	var raiders: Array[int] = tb.mine_key("canoe_raiders")
	var warriors: Array[int] = tb.mine_key("native_warriors")
	var holcan: Array[int] = tb.mine_key("holcan")
	_check(poison.size() == 2 and fire.size() == 1 and raiders.size() == 2 and warriors.size() == 2 and holcan.size() == 1,
		"the script finds two poison companies, one fire, two raiders, two warriors, the Holcan")
	# 1 place and Start battle
	var u0: int = warriors[0]
	bt._select(u0)
	bt._queue(BattleSim.make_move_order(0, u0, int(sim.u_cx[u0]) + 4 * 1024, int(sim.u_cy[u0]), 0, 0, 0))
	await _frames(4)
	_check(tb.seen_log.has(BattleSim.ORDER_PLACE) and tb._sub == "ready" and tb.card.text_label.text == Howto.text("nstep_1b"),
		"step 1: a placement was seen, the card asks for Start battle")
	await _frames(2)
	_check(_ptr_at(bt.hud.ready_button), "step 1: the pointer is on Start battle")
	bt._deploy_ready()
	for k in 300:
		await process_frame
		if sim.phase == BattleSim.PHASE_BATTLE and tb.step == 2:
			break
	await _frames(2)
	_check(sim.phase == BattleSim.PHASE_BATTLE and tb.step == 2 and _words(2), "the battle starts: step 2 (poisoned arrows), its words")
	await _frames(2)
	_check(_ptr_pt(tb._card_of(poison[0])), "step 2: the pointer is on a poison company's card")
	await _shot("2")
	# 2 poisoned arrows: select both, the Ammo chip to the special kind, shoot the nearest Spaniard
	_select(poison)
	await _frames(3)
	_check(bt.hud.ammo_button.is_visible_in_tree() and _ptr_at(bt.hud.ammo_button), "step 2: with the bowmen selected the Ammo chip shows and the pointer is on it")
	bt.hud.ammo_button.pressed.emit()
	await _frames(3)
	var row := bt.hud.opt_box.find_child("opt_1", true, false) as Control if bt.hud.opt_box != null else null
	_check(bt.hud.opt_panel.visible and row != null and _ptr_at(row), "step 2: the Ammo options are open, the pointer is on the poisoned row")
	await _shot("2_ammo")
	bt.hud._choose_option(bt.hud.ammo_button, 1)
	await _frames(2)
	_check(sim.u_akind[poison[0]] != 0 or tb._ammo_on, "step 2: the poison companies shoot their special kind (%s)" % str(tb._ammo_on))
	_check(tb.step == 2, "step 2: the Ammo order alone does not finish the step")
	for u in poison:
		bt._queue(BattleSim.make_attack_order(0, u, _nearest_foe(u), 0))
	var ok2: bool = await _run_until(func(): return tb.step >= 3, 1800)
	var pz := 0
	for u in sim.n_units:
		if sim.u_side[u] != bt.player_side:
			pz += sim.u_poisoned[u]
	_check(ok2, "step 2 done once the poison companies have shot: step 3 (fire arrows) at %d s, %d Spaniards poisoned" % [sim.tick / BattleSim.TICKS_PER_SECOND, pz])
	tb.update()
	await _frames(2)
	_check(_words(3) and _ptr_pt(tb._card_of(fire[0])), "step 3: its words, the pointer on the fire company's card")
	await _shot("3")
	# 3 fire arrows on the gate
	_select(fire)
	await _frames(2)
	_check(_ptr_at(bt.hud.ammo_button), "step 3: the pointer is on the Ammo chip")
	bt.hud._choose_option(bt.hud.ammo_button, 1)
	await _frames(3)
	var g: int = tb.lesson_gate()
	_check(g >= 0 and _ptr_pt(tb._range_pt(fire[0], g)), "step 3: fire arrows chosen, the pointer is on a spot within bowshot of the gate")
	await _shot("3_move")
	# within bowshot first (the fire kind's range is 85 % of the bow's), then the tap on the gate
	var f0: int = fire[0]
	var gx: int = sim.g_ox[g]
	var gy: int = sim.g_oy[g]
	var dx: int = sim.u_cx[f0] - gx
	var dy: int = sim.u_cy[f0] - gy
	var dl: int = maxi(int(sqrt(float(dx) * dx + float(dy) * dy)), 1)
	bt._queue(BattleSim.make_move_order(0, f0, gx + dx * 60 * 1024 / dl, gy + dy * 60 * 1024 / dl, 0, 0, 0))
	await _run_until(func(): return false, 3)
	await _frames(2)
	_check(_ptr_pt(tb._gate_pt(g)), "step 3: once the company walks into bowshot the pointer moves to the gate")
	await _run_until(func(): return sim.u_order[f0] == BattleSim.O_NONE, 900)
	await _frames(2)
	_check(_ptr_pt(tb._gate_pt(g)), "step 3: within bowshot the pointer is on the gate")
	await _shot("3_gate")
	_select(fire)
	var w := Vector2(sim.g_x[g], sim.g_y[g]) / 1024.0 * Battle.PX_PER_M
	var used: bool = bt._tap_gate(g, w)
	var gate_order := false
	for o in sim.pending_orders:
		if int(o.get("type", -1)) == BattleSim.ORDER_ATTACK and int(o.get("gate", -1)) == g:
			gate_order = true
	_check(used and (gate_order or sim.u_gtarget[f0] == g), "step 3: the tap on the gate gives the fire company an attack on it")
	var t3: int = sim.tick
	var ok3: bool = await _run_until(func(): return tb.step >= 4, 3000)
	_check(ok3 and tb.gate_fired(), "step 3 done once the gate is alight: step 4 (canoe raiders), %d s of shooting (burn %d, state %d)" % [(sim.tick - t3) / BattleSim.TICKS_PER_SECOND, sim.g_burn[g], sim.g_state[g]])
	tb.update()
	await _frames(2)
	_check(_words(4) and _ptr_pt(tb._card_of(raiders[0])), "step 4: its words, the pointer on a raiders card")
	await _shot("4")
	# 4 canoe raiders: Run, then a move to the gate
	_select(raiders)
	await _frames(2)
	_check(_ptr_at(bt.hud.run_button), "step 4: with the raiders selected the pointer is on the Run chip")
	bt._toggle_run()
	await _frames(2)
	_check(tb.step == 4 and tb._ran, "step 4: Run alone does not finish the step")
	for u in raiders:
		bt._queue(BattleSim.make_move_order(0, u, sim.g_ox[g], sim.g_oy[g], 0, 0, 1))
	await _frames(2)
	_check(tb.step == 5, "step 4 done by Run and a move: step 5 (the storm)")
	tb.update()
	await _frames(2)
	_check(_words(5) and _ptr_pt(tb._card_of(holcan[0])), "step 5: its words, the pointer on the Holcan's card")
	await _shot("5")
	# 5 the storm: the warriors attack first (not enough alone), then the Holcan
	_select(warriors)
	var tgt := _nearest_foe(warriors[0])
	for u in warriors:
		bt._queue(BattleSim.make_attack_order(0, u, tgt, 1))
	await _frames(2)
	_check(tb.step == 5, "step 5: the warriors' attack alone does not finish the step")
	bt._queue(BattleSim.make_attack_order(0, holcan[0], tgt, 1))
	await _frames(2)
	_check(tb.step == 6, "step 5 done by the warriors' and the Holcan's attacks: step 6 (beat the garrison)")
	tb.update()
	await _frames(2)
	_check(_words(6) and not tb.card.buttons.has("skip") and tb.card.buttons.has("leave") and _ptr_pt(tb._centroid(false)),
		"step 6: its words, no Skip, the pointer on the garrison")
	await _shot("6")
	# fight it out: every company attacks the nearest Spaniard until it is decided
	var guard := 0
	while sim.winner < 0 and sim.ended == 0 and guard < 12000:
		if guard % 100 == 0:
			for u in sim.n_units:
				if sim.u_side[u] == bt.player_side and sim.u_alive[u] > 0:
					var e := _nearest_foe(u)
					if e >= 0:
						bt._queue(BattleSim.make_attack_order(0, u, e, 1))
		guard += 1
		bt._do_tick()
		if guard % 200 == 0:
			await process_frame
	_check(sim.winner == bt.player_side, "the battle is won (%d s; men left %d / %d)" % [sim.tick / BattleSim.TICKS_PER_SECOND, sim.alive_count(0), sim.alive_count(1)])
	tb.update()
	await _frames(2)
	_check(tb.step == TutorialNative.NATIVE_WIN and tb.card.visible and tb.card.text_label.text == Howto.text("nstep_win") and tb.card.buttons.has("menu"),
		"the closing card says the village is won, with Back to the menu")
	await _shot("win")
	var exited := [false]
	bt.exit_requested.connect(func(): exited[0] = true)
	(tb.card.buttons["menu"] as Button).pressed.emit()
	await _frames(2)
	_check(exited[0] and not tb.card.visible, "Back to the menu leaves the battle")
	bt.queue_free()
	bt = null
	await _frames(4)


func _skip_leave() -> void:
	bt = await _launch()
	var tb = bt.tutorial
	var sim = bt.sim
	(tb.card.buttons["skip"] as Button).pressed.emit()
	await _frames(2)
	_check(tb.step == 1 and tb._sub == "ready", "Skip on step 1 shows the Start battle card")
	(tb.card.buttons["skip"] as Button).pressed.emit()
	for k in 300:
		await process_frame
		if sim.phase == BattleSim.PHASE_BATTLE:
			break
	_check(sim.phase == BattleSim.PHASE_BATTLE and tb.step == 2 and _words(2), "Skip again starts the battle: step 2")
	(tb.card.buttons["skip"] as Button).pressed.emit()
	await _frames(2)
	_check(tb.step == 3 and _words(3), "Skip on step 2: step 3")
	(tb.card.buttons["leave"] as Button).pressed.emit()
	await _frames(3)
	tb.update()
	_check(tb.left and not tb.card.visible and not tb.pointer.visible, "Leave the tutorial hides the card and the pointer")
	bt.queue_free()
	bt = null
	await _frames(4)
