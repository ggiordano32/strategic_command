extends RefCounted
## The battle tutorial (docs/design/campaign_rules.md "The tutorial": lesson 6's battle): a script of six steps that
## game/battle.gd runs when the guided first campaign hands it one (`battle.tutorial`). Each step is a card (howto.gd
## words) and a pointer on the HUD control or the map spot, and each gates the next: the next card appears when the
## step's order is seen in the order queue (battle.gd calls `seen(order)` for every order it queues):
##   1 place the line (a place order in the deployment; then Start battle), 2 move it forward (a move order),
##   3 fire at will (the Fire chip, its long-press explanation opened once; it must end up on), 4 charge with the horse
##   (an attack order by a cavalry unit), 5 hold (Halt), 6 withdraw a unit (Withdraw and its confirmation).
## The card has "Skip" (to the next step) and "Leave the tutorial" (the cards stop). The defender plays Easy with the
## garrison as the campaign scenario makes it; the player's army wins by its make-up. View only: it reads the sim and
## the HUD, and the player's own orders do everything.

const UT := preload("res://sim/unit_types.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")
const Howto := preload("res://game/campaign/howto.gd")
const TutorCard := preload("res://game/campaign/tutor_card.gd")
const TutorPointer := preload("res://game/campaign/tutor_pointer.gd")

const WIN_STEP := 7        # all six steps done: the closing card

var b           # the Battle
var step := 1
var left := false
var card: TutorCard
var pointer: TutorPointer
var seen_log: Array[int] = []   # the order types seen (tests read it)
var _held := false
var explained := false     # the Fire chip's long-press explanation was opened once
var _seen_types := {}
var _shown := ""
var _sub := ""
var _own := false          # the tutorial is queueing an order itself


## Called by battle.gd once its HUD exists.
func attach(battle) -> void:
	b = battle
	card = TutorCard.new()
	card.visible = false
	card.pressed.connect(_on_button)
	pointer = TutorPointer.new()
	pointer.target = _target
	pointer.visible = false
	var root: Control = b.hud._root
	root.add_child(card)
	root.add_child(pointer)
	b.hud.add_ui_control(card)
	update()


## Every order battle.gd queues for the player.
func seen(order: Dictionary) -> void:
	if _own:
		return   # (an order the tutorial gave itself)
	var t := int(order.get("type", -1))
	seen_log.append(t)
	_seen_types[t] = int(_seen_types.get(t, 0)) + 1
	match step:
		1:
			if t == BattleSim.ORDER_PLACE:
				_sub = "ready"
		2:
			if t == BattleSim.ORDER_MOVE and b.sim.phase == BattleSim.PHASE_BATTLE:
				_next()
		4:
			if t == BattleSim.ORDER_ATTACK and mine(UT.CLS_CAV).has(int(order.get("unit", -1))):
				_next()
		5:
			if t == BattleSim.ORDER_HALT:
				_next()
		6:
			if t == BattleSim.ORDER_WITHDRAW:
				_next()
	update()


func _cls(u: int) -> int:
	if u < 0 or u >= b.sim.n_units:
		return -1
	return UT.cls(b.sim.u_type[u])


func _next() -> void:
	step += 1
	_sub = ""
	update()


## The player's units of class `cls` that are alive (not the general's guard: it rides, but it is not "the horse").
func mine(cls: int) -> Array[int]:
	var out: Array[int] = []
	var sim = b.sim
	for u in sim.n_units:
		if sim.u_side[u] == b.player_side and sim.u_alive[u] > 0 and UT.cls(sim.u_type[u]) == cls and UT.role(sim.u_type[u]) != "command":
			out.append(u)
	return out


func _fire_all_on() -> bool:
	var any := false
	for u in mine(UT.CLS_MISSILE):
		any = true
		if b.orders.value(u, "fire") == 0:
			return false
	return any


## Follow the sim: the step moves on from the deployment, the fire step ends when Fire is on, the card follows.
func update() -> void:
	if b == null or card == null:
		return
	var sim = b.sim
	if step == 1 and sim.phase != BattleSim.PHASE_DEPLOY:
		step = 2
		_sub = ""
	if step == 3 and _seen_types.get(BattleSim.ORDER_FIRE, 0) > 0 and _fire_all_on():
		_next()
		return
	if step == 3 and not explained:
		_open_fire_explain()
	var decided: bool = sim.winner >= 0 or sim.ended != 0
	var show: bool = not left and not decided and b.interactive
	card.visible = show
	if not show:
		return
	var key := "%d%s" % [step, _sub]
	if key != _shown:
		_shown = key
		card.clear_buttons()
		var w := clampf(b.get_viewport().get_visible_rect().size.x * 0.5, 240.0, 460.0)
		if step >= WIN_STEP:
			card.setup("", Howto.text("step_win"), "", w - 24.0)
			card.add_button("done", Howto.text("ui_done"))
		else:
			var txt := Howto.step(step)
			if step == 1 and _sub == "ready":
				txt = Howto.text("step_1b")
			card.setup(Howto.text("step_title") % step, txt, "", w - 24.0)
			card.add_button("skip", "Skip")
			card.add_button("leave", Howto.text("ui_leave"))
		card.position = Vector2(8.0, b.hud.top_height() + 6.0)


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
		"leave", "done":
			left = true
			card.visible = false
			pointer.visible = false


## Fire step: the musketeers are told to hold fire (so the player has something to switch on), selected (the chip shows
## for a selection) and the Fire chip's long-press explanation is opened once.
func _open_fire_explain() -> void:
	var ms := mine(UT.CLS_MISSILE)
	if ms.is_empty():
		explained = true
		return
	var sel: Array[int] = b.selection
	if sel.is_empty() or _cls(sel[0]) != UT.CLS_MISSILE:
		b.selection.clear()
		for u in ms:
			b.selection.append(u)
		b.selected = ms[0]
		b._selection_changed()
	if not _held:
		_held = true
		_own = true
		for u in ms:
			b._queue(BattleSim.make_fire_order(0, u, 0))
		_own = false
		b._refresh_actions()
	var chip: Control = b.hud.fire_button
	if chip != null and chip.is_visible_in_tree():
		b.hud._open_explain(chip)
		explained = true


# -------------------------------------------------------------- the pointer ---

func _world_pt(u: int) -> Vector2:
	var sim = b.sim
	var p: Vector2 = Vector2(sim.u_cx[u], sim.u_cy[u]) / float(b.M) * float(b.PX_PER_M)
	return b.world_to_screen(p)   # (through the board transform: the oblique view too)


func _centroid(own: bool) -> Variant:
	var sim = b.sim
	var sum := Vector2.ZERO
	var n := 0
	for u in sim.n_units:
		if sim.u_alive[u] > 0 and (sim.u_side[u] == b.player_side) == own:
			sum += Vector2(sim.u_cx[u], sim.u_cy[u])
			n += 1
	if n == 0:
		return null
	var c: Vector2 = sum / float(n) / float(b.M) * float(b.PX_PER_M)
	return b.world_to_screen(c)


func _card_of(u: int) -> Variant:
	var cd = b.hud._cards.get(u)
	return TutorPointer.center_of(cd) if cd != null else null


func _chip_pt(c: Control) -> Variant:
	var p: Variant = TutorPointer.center_of(c)
	if p != null:
		return p
	return TutorPointer.center_of(b.hud.more_button)


func _target() -> Variant:
	if b == null or left or card == null or not card.visible:
		return null
	var sim = b.sim
	match step:
		1:
			if _sub == "ready":
				return TutorPointer.center_of(b.hud.ready_button)
			return _centroid(true)
		2:
			var me: Variant = _centroid(true)
			var foe: Variant = _centroid(false)
			if me == null or foe == null:
				return me
			return (me as Vector2).lerp(foe as Vector2, 0.3)
		3:
			if b.hud.opt_panel != null and b.hud.opt_panel.visible:
				var row: Variant = TutorPointer.center_of(b.hud.opt_box.find_child("opt_1", true, false) as Control)
				if row != null:
					return row
			return _chip_pt(b.hud.fire_button)
		4:
			var horse := mine(UT.CLS_CAV)
			if horse.is_empty():
				return null
			if b.selected != horse[0] or b.selection.size() != 1:
				return _card_of(horse[0])
			var best := -1
			var bd := 1e18
			for u in sim.n_units:
				if sim.u_alive[u] > 0 and sim.u_side[u] != b.player_side:
					var d := Vector2(sim.u_cx[u] - sim.u_cx[horse[0]], sim.u_cy[u] - sim.u_cy[horse[0]]).length_squared()
					if d < bd:
						bd = d
						best = u
			if best < 0:
				return null
			return _world_pt(best)
		5:
			if b.selection.is_empty():
				var ms := mine(UT.CLS_MISSILE)
				return _card_of(ms[0]) if not ms.is_empty() else null
			return _chip_pt(b.hud.halt_button)
		6:
			if b.hud.confirm_panel != null and b.hud.confirm_panel.visible:
				return TutorPointer.center_of(b.hud.confirm_ok)
			if b.selection.is_empty():
				var all := mine(UT.CLS_MISSILE)
				return _card_of(all[0]) if not all.is_empty() else null
			return _chip_pt(b.hud.withdraw_button)
	return null
