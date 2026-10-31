extends SceneTree
## Chip options SET, never toggle (docs/design/ui.md "Chip options set, not toggle"): with three missile units
## selected and one already at will, the Fire row "At will" puts all three at will and "Hold" all three on hold;
## a mixed selection reads "mixed" with no row marked (now); the same for Skirmish.
##   godot --headless --path . -s tests/chip_set_test.gd      Exits 0 / 1.

const Battle := preload("res://game/battle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const Kit := preload("res://game/campaign/ui_kit.gd")

var failures := 0
var b


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		failures += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	Kit.anim_override = 0
	_run.call_deferred()


func _vals(key: String) -> Array:
	return b.selection.map(func(u): return b.orders.value(u, key))


func _choose(c, value: int) -> void:
	c.pressed.emit()
	await _frames(2)
	var row = b.hud.opt_box.find_child("opt_%d" % value, false, false)
	_check(row != null, "%s: a row for %d" % [c.key, value])
	if row != null:
		_check(not row.current or value == 1000, "%s: no row is marked (now) on a mixed selection (row %d)" % [c.key, value]) if b.hud.chip_mixed.get(c.key, false) else null
		row.pressed.emit()
	await _frames(2)


func _run() -> void:
	var units: Array = []
	for i in 3:
		units.append(Scenarios.unit(0, UT.index_of("musket"), 40, 60 + 14 * i, 150, 0))
	units.append(Scenarios.unit(1, UT.index_of("spear"), 80, 150, 40, 512))
	var sc := Scenarios._test(units, [])
	sc["ai_sides"] = [1]
	b = Battle.new()
	b.custom_scenario = sc
	b.player_side = 0
	b.seed_value = 5
	b.speed_q = 4
	root.add_child(b)
	await _frames(8)
	b._set_paused(true)
	var us: Array[int] = []
	for u in b.sim.n_units:
		if b.sim.u_side[u] == 0:
			us.append(u)
	b.selection.clear()
	b.selection.append_array(us)
	b.selected = us[0]
	b._selection_changed()
	await _frames(3)
	var h = b.hud
	_check(us.size() == 3, "three musketeers selected")
	# Fire: one at will (the others hold), then the popover.
	b._queue(BattleSim.make_fire_order(0, us[0], 1))
	b._queue(BattleSim.make_fire_order(0, us[1], 0))
	b._queue(BattleSim.make_fire_order(0, us[2], 0))
	b._refresh_actions()
	await _frames(3)
	print("   fire values: ", _vals("fire"))
	_check(_vals("fire") == [1, 0, 0], "setup: one at will, two holding")
	_check(h.fire_button.state_word == "mixed", "a mixed Fire selection reads mixed (%s)" % h.fire_button.state_word)
	h._open_explain(h.fire_button)
	await _frames(2)
	_check(h.explain_box.get_node("ex_state").text == "Now: mixed", "the explanation says Now: mixed")
	for k in h.explain_box.get_children():
		if str(k.name).begins_with("ex_row_"):
			_check(not str(k.text).contains("(now)"), "no explanation row is marked (now)")
	h._close_explain()
	await _choose(h.fire_button, 1)
	print("   fire values after At will: ", _vals("fire"))
	_check(_vals("fire") == [1, 1, 1], "At will on a mixed selection puts all three at will")
	_check(h.fire_button.state_word == "at will", "the chip reads at will (%s)" % h.fire_button.state_word)
	await _choose(h.fire_button, 1)
	_check(_vals("fire") == [1, 1, 1], "At will again changes nothing")
	await _choose(h.fire_button, 0)
	print("   fire values after Hold: ", _vals("fire"))
	_check(_vals("fire") == [0, 0, 0] and h.fire_button.state_word == "hold", "Hold puts all three on hold")
	# Mixed again, then Hold.
	b._queue(BattleSim.make_fire_order(0, us[2], 1))
	b._refresh_actions()
	await _frames(2)
	await _choose(h.fire_button, 0)
	_check(_vals("fire") == [0, 0, 0], "Hold on a mixed selection puts all three on hold")
	# One-tap flip unchanged for the shortcut path.
	b._toggle_fire()
	_check(_vals("fire") == [1, 1, 1], "the shortcut flip still turns all on")
	# Skirmish.
	b._queue(BattleSim.make_skirmish_order(0, us[0], 1))
	b._queue(BattleSim.make_skirmish_order(0, us[1], 0))
	b._queue(BattleSim.make_skirmish_order(0, us[2], 0))
	b._refresh_actions()
	await _frames(3)
	_check(_vals("skirm") == [1, 0, 0] and h.skirm_button.state_word == "mixed", "skirmish: mixed reads mixed (%s)" % h.skirm_button.state_word)
	await _choose(h.skirm_button, 1)
	print("   skirm values after On: ", _vals("skirm"))
	_check(_vals("skirm") == [1, 1, 1] and h.skirm_button.state_word == "on", "Skirmish On puts all three on")
	await _choose(h.skirm_button, 0)
	_check(_vals("skirm") == [0, 0, 0] and h.skirm_button.state_word == "off", "Skirmish Off puts all three off")
	print("RESULT: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
