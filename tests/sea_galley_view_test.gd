extends SceneTree
## (R2, Rome's navy) The sea battle's view with galleys: the orders bar shows the stroke (Dash, Cruise, Rest) and no
## shot kinds, the ships draw (oars, ram, corvus, furled sail) while the battle runs, a press sets the stroke.
##   godot --headless --script res://tests/sea_galley_view_test.gd

const SeaBattle := preload("res://game/sea_battle.gd")
const SeaSim := preload("res://sim/sea_sim.gd")
const Checks := preload("res://tests/sea_checks.gd")

var sb: Node2D
var _ok := true
var _frame := 0


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		_ok = false


func _initialize() -> void:
	var scn := Checks.scenario("galleys")
	scn["ai_sides"] = [0, 1]
	sb = SeaBattle.new()
	sb.scenario = scn
	sb.seed_value = 3
	root.add_child(sb)


func _btn(nm: String) -> Button:
	return sb.find_child(nm, true, false) as Button


func _process(_d: float) -> bool:
	_frame += 1
	if _frame < 8:
		return false
	if _frame == 8:
		var gal: bool = sb.selection.size() > 0 and sb.sim.u_state[sb.selection[0]] == SeaSim.S_SAIL
		_check(gal, "a ship of the player's is selected")
		var full := _btn("sea_full")
		_check(full != null and full.get_meta("seg_value", "sea_full") == "sea_full", "the stroke buttons exist")
		var texts := ""
		for b in sb.find_children("*", "Button", true, false):
			texts += (b as Button).text + "|"
		_check(texts.contains("Dash") and texts.contains("Cruise") and texts.contains("Rest") and not texts.contains("Full sail"),
			"the sail buttons are the stroke: " + texts)
		_check(_btn("sea_round") == null and _btn("sea_grape") == null, "no shot kinds for a galley")
		_btn("sea_stop").pressed.emit()
		sb.sim.step()
		_check(sb.sim.s_sail[sb.selection[0]] == 0, "Rest sets the stroke to 0")
		_btn("sea_full").pressed.emit()
		sb.sim.step()
		_check(sb.sim.s_sail[sb.selection[0]] == 2, "Dash sets the stroke to 2")
		sb.speed_q = 4
		return false
	if _frame < 120:
		return false
	_check(sb.sim.tick > 5, "the battle ran with the galleys drawn (tick %d)" % sb.sim.tick)
	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)
	return true
