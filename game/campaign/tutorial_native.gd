extends "res://game/campaign/tutorial_battle.gd"
## The native way (docs/design/campaign_rules.md "The native way (as built)"): the second guided battle, started from
## the title's Campaign page (or `--scenario=tutorial_native`) on the scenario of that id (sim/scenarios.gd
## native_lesson: a native war party storms a Spanish palisade village). The same shape as the battle tutorial it
## extends (attach / seen(order) / update(), the card, the pointer, Skip and Leave the tutorial); six steps:
##   1 place the war party (a place order in the deployment; then Start battle), 2 poisoned arrows (the Ammo order to
##   the special kind for a poison company, then a shot: a poison company's arrows spent or a Spanish unit poisoned),
##   3 fire arrows on the gate (the gate alight or down), 4 canoe raiders (a run order and a move or attack by a
##   raiders unit), 5 the storm (attack orders by a warriors company and by the Holcan), 6 beat the garrison (the
##   closing card when the battle is won, with "Back to the menu").
## View only: it reads the sim and the HUD; the player's own orders do everything.

const NATIVE_WIN := 7      # the battle won: the closing card

var _ammo_on := false      # step 2: the Ammo order to the poisoned kind was seen
var _ammo0 := {}           # step 2: each poison company's arrows when that order was seen
var _ran := false          # step 4: a run order by a raiders unit
var _rmoved := false       # ... a move or attack by one
var _warr := false         # step 5: an attack by a warriors company
var _holc := false         # ... by the Holcan


## The player's companies of row `key` that are alive.
func mine_key(key: String) -> Array[int]:
	var out: Array[int] = []
	var sim = b.sim
	for u in sim.n_units:
		if sim.u_side[u] == b.player_side and sim.u_alive[u] > 0 and UT.key_of(sim.u_otype[u]) == key:
			out.append(u)
	return out


## The player's companies whose special ammunition kind has "poison" (or "fire" when `fire`).
func ammo_units(fire: bool) -> Array[int]:
	var out: Array[int] = []
	var sim = b.sim
	for u in sim.n_units:
		if sim.u_side[u] != b.player_side or sim.u_alive[u] <= 0:
			continue
		var sk: int = sim.spec_kind(u)
		if sk < 0:
			continue
		if (fire and UT.ammo_stat(sk, "fire") > 0) or (not fire and UT.ammo_stat(sk, "poison") > 0):
			out.append(u)
	return out


## The gate the lesson means: the one nearest the player's companies (-1 none).
func lesson_gate() -> int:
	var sim = b.sim
	if sim.n_gates == 0:
		return -1
	var sx := 0
	var sy := 0
	var n := 0
	for u in sim.n_units:
		if sim.u_side[u] == b.player_side and sim.u_alive[u] > 0:
			sx += sim.u_cx[u]
			sy += sim.u_cy[u]
			n += 1
	if n == 0:
		return 0
	sx /= n
	sy /= n
	var best := 0
	var bd := 1 << 62
	for g in sim.n_gates:
		if sim.g_cit[g] != 0:
			continue
		var dx: int = (sim.g_x[g] - sx) / 1024
		var dy: int = (sim.g_y[g] - sy) / 1024
		if dx * dx + dy * dy < bd:
			bd = dx * dx + dy * dy
			best = g
	return best


## Any gate burning or broken.
func gate_fired() -> bool:
	var sim = b.sim
	for g in sim.n_gates:
		if sim.g_burn[g] > 0 or sim.g_state[g] == BattleSim.GATE_BROKEN:
			return true
	return false


func _poison_shot() -> bool:
	var sim = b.sim
	for u in sim.n_units:
		if sim.u_side[u] != b.player_side and sim.u_poisoned[u] > 0:
			return true
	for u in ammo_units(false):
		if _ammo0.has(u) and sim.u_ammo[u] < int(_ammo0[u]):
			return true
	return false


func seen(order: Dictionary) -> void:
	if _own:
		return
	var t := int(order.get("type", -1))
	var u := int(order.get("unit", -1))
	seen_log.append(t)
	_seen_types[t] = int(_seen_types.get(t, 0)) + 1
	var key := UT.key_of(b.sim.u_otype[u]) if u >= 0 and u < b.sim.n_units else ""
	match step:
		1:
			if t == BattleSim.ORDER_PLACE:
				_sub = "ready"
		2:
			if t == BattleSim.ORDER_AMMO and int(order.get("on", 0)) != 0 and ammo_units(false).has(u):
				_ammo_on = true
				for p in ammo_units(false):
					if not _ammo0.has(p):
						_ammo0[p] = b.sim.u_ammo[p]
		4:
			if key == "canoe_raiders":
				if (t == BattleSim.ORDER_RUN and int(order.get("run", 0)) != 0) \
						or ((t == BattleSim.ORDER_MOVE or t == BattleSim.ORDER_ATTACK) and int(order.get("run", 0)) != 0):
					_ran = true
				if t == BattleSim.ORDER_MOVE or t == BattleSim.ORDER_ATTACK:
					_rmoved = true
				if _ran and _rmoved:
					_next()
		5:
			if t == BattleSim.ORDER_ATTACK:
				if key == "native_warriors":
					_warr = true
				elif key == "holcan":
					_holc = true
				if _warr and _holc:
					_next()
	update()


## Follow the sim: the deployment ends step 1, a shot ends step 2, a burning gate step 3, the win the last.
func update() -> void:
	if b == null or card == null:
		return
	var sim = b.sim
	if step == 1 and sim.phase != BattleSim.PHASE_DEPLOY:
		step = 2
		_sub = ""
	if step == 2 and _ammo_on and _poison_shot():
		step = 3
		_sub = ""
	if step == 3 and gate_fired():
		step = 4
		_sub = ""
	if sim.winner == b.player_side and step < NATIVE_WIN:
		step = NATIVE_WIN
		_sub = ""
	var lost: bool = (sim.winner >= 0 and sim.winner != b.player_side) or (sim.ended != 0 and sim.winner != b.player_side)
	var show: bool = not left and not lost and b.interactive
	card.visible = show
	if not show:
		return
	var key := "%d%s" % [step, _sub]
	if key != _shown:
		_shown = key
		card.clear_buttons()
		var w := clampf(b.get_viewport().get_visible_rect().size.x * 0.5, 240.0, 460.0)
		if step >= NATIVE_WIN:
			card.setup("", Howto.text("nstep_win"), "", w - 24.0)
			card.add_button("menu", Howto.text("ui_menu"))
		else:
			var txt := Howto.nstep(step)
			if step == 1 and _sub == "ready":
				txt = Howto.text("nstep_1b")
			card.setup(Howto.text("nstep_title") % step, txt, "", w - 24.0)
			if step < Howto.NSTEPS:
				card.add_button("skip", "Skip")
			card.add_button("leave", Howto.text("ui_leave"))
		card.position = Vector2(8.0, b.hud.top_height() + 6.0)
	if step >= NATIVE_WIN:
		# The closing card goes under the Victory banner (top centre), not over it.
		var y: float = b.hud.top_height() + 6.0
		var bn: Control = b.hud.banner
		if bn != null and bn.visible:
			y = maxf(y, bn.get_global_rect().end.y + 8.0)
		card.position.y = y


func _on_button(key: String) -> void:
	match key:
		"skip":
			if step == 1 and _sub != "ready" and b.sim.phase == BattleSim.PHASE_DEPLOY:
				_sub = "ready"
				update()
			elif step == 1:
				b._deploy_ready()
				step = 2
				_sub = ""
				update()
			else:
				_next()
		"leave":
			left = true
			card.visible = false
			pointer.visible = false
		"menu":
			left = true
			card.visible = false
			pointer.visible = false
			b._leave_now()


# -------------------------------------------------------------- the pointer ---

func _gate_pt(g: int) -> Variant:
	if g < 0:
		return null
	var sim = b.sim
	var p: Vector2 = Vector2(sim.g_x[g], sim.g_y[g]) / float(b.M) * float(b.PX_PER_M)
	return b.world_to_screen(p)


## The pointer for an Ammo step: the company's card, then the chip (its options' special row), then `then`.
func _ammo_target(units: Array[int], then: Variant) -> Variant:
	if units.is_empty():
		return null
	if not b.selection.has(units[0]):
		return _card_of(units[0])
	var any_off := false
	for u in units:
		if b.selection.has(u) and b.orders.value(u, "akind") == 0:
			any_off = true
	if any_off:
		if b.hud.opt_panel != null and b.hud.opt_panel.visible:
			var row: Variant = TutorPointer.center_of(b.hud.opt_box.find_child("opt_1", true, false) as Control)
			if row != null:
				return row
		return _chip_pt(b.hud.ammo_button)
	return then


## Company u's arrows reach gate g's face from where it stands, or will from where it is going (its fire kind's range).
func _in_bowshot(u: int, g: int) -> bool:
	var sim = b.sim
	var gf: Vector2i = sim.gate_face(g)
	var x: int = sim.u_cx[u]
	var y: int = sim.u_cy[u]
	if sim.u_order[u] == BattleSim.O_MOVE:
		x = sim.u_dx[u]
		y = sim.u_dy[u]
	return Vector2(gf.x - x, gf.y - y).length() <= float(sim.mrange(u)) * 0.95


## The spot to walk company u to for a shot at gate g: 60 % of its range out from the gate's face, on u's side.
func _range_pt(u: int, g: int) -> Variant:
	var sim = b.sim
	var gf: Vector2i = sim.gate_face(g)
	var d := Vector2(sim.u_cx[u] - gf.x, sim.u_cy[u] - gf.y)
	if d.length() < 1.0:
		return _gate_pt(g)
	var p: Vector2 = Vector2(gf.x, gf.y) + d.normalized() * float(sim.mrange(u)) * 0.6
	return b.world_to_screen(p / float(b.M) * float(b.PX_PER_M))


func _nearest_foe(u: int) -> Variant:
	var sim = b.sim
	var best := -1
	var bd := 1e18
	for e in sim.n_units:
		if sim.u_alive[e] > 0 and sim.u_side[e] != b.player_side:
			var d := Vector2(sim.u_cx[e] - sim.u_cx[u], sim.u_cy[e] - sim.u_cy[u]).length_squared()
			if d < bd:
				bd = d
				best = e
	return _world_pt(best) if best >= 0 else null


func _target() -> Variant:
	if b == null or left or card == null or not card.visible:
		return null
	match step:
		1:
			if _sub == "ready":
				return TutorPointer.center_of(b.hud.ready_button)
			return _centroid(true)
		2:
			var pz := ammo_units(false)
			return _ammo_target(pz, _nearest_foe(pz[0]) if not pz.is_empty() else null)
		3:
			var fz := ammo_units(true)
			var g := lesson_gate()
			var then: Variant = _gate_pt(g)
			if not fz.is_empty() and g >= 0 and not _in_bowshot(fz[0], g):
				then = _range_pt(fz[0], g)
			return _ammo_target(fz, then)
		4:
			var rd := mine_key("canoe_raiders")
			if rd.is_empty():
				return null
			if not b.selection.has(rd[0]):
				return _card_of(rd[0])
			if not _ran and b.orders.value(rd[0], "run") == 0:
				return _chip_pt(b.hud.run_button)
			return _gate_pt(lesson_gate())
		5:
			var wr := mine_key("native_warriors")
			var hc := mine_key("holcan")
			if not _holc and not hc.is_empty() and not b.selection.has(hc[0]):
				return _card_of(hc[0])
			if not _warr and not wr.is_empty() and not b.selection.has(wr[0]):
				return _card_of(wr[0])
			return _gate_pt(lesson_gate())
		6:
			return _centroid(false)
	return null
