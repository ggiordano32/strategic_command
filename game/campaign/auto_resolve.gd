extends Node
## Auto-resolve of a campaign battle with a human in it: the real battle sim,
## AI against AI, from the same deterministic inputs as a fought battle (so
## auto-resolve is honest, and as good as the battle AI, which is a little
## worse than good play). Ticks run in slices of at most BUDGET_MS per frame
## so the UI stays responsive; `progress` (0..1) drives a bar.
##
## Big battles run scaled down (FAST_ABOVE soldiers: every unit at
## FAST_SCALE % of its men, results scaled back up): about twice as fast,
## and the outcome statistics stay close (tests/campaign_battles.gd).

signal finished(outcome: Dictionary)

const BattleSim := preload("res://sim/battle_sim.gd")
const CBattle := preload("res://campaign/cbattle.gd")

const BUDGET_MS := 24
const FAST_ABOVE := 2600
const FAST_SCALE := 50
const MAX_TICKS := 12000

var built: Dictionary = {}
var sim: BattleSim
var progress := 0.0
var scale := 100
var wall_ms := 0
var _t0 := 0
var _start_alive := 1
var _done := false


func start(st: Dictionary, b: Dictionary) -> void:
	built = CBattle.build(st, b, -1)
	var soldiers := 0
	for u in built["scenario"]["units"]:
		soldiers += int(u["count"])
	if soldiers > FAST_ABOVE:
		scale = FAST_SCALE
		built = CBattle.build(st, b, -1, FAST_SCALE)
	sim = BattleSim.new()
	sim.setup(built["scenario"], int(built["seed"]))
	_start_alive = maxi(sim.alive_count(), 1)
	_t0 = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	if _done or sim == null:
		return
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < BUDGET_MS:
		sim.step()
		if sim.ended != 0 or sim.tick >= MAX_TICKS:
			_finish()
			return
	# Progress: by time (a battle takes ~3,000-4,500 ticks) and by losses.
	var by_time := sim.tick / 4500.0
	var by_loss := 1.0 - float(mini(sim.alive_count(0), sim.alive_count(1))) * 2.0 / _start_alive
	progress = clampf(maxf(by_time, by_loss), 0.0, 0.97)


func _finish() -> void:
	_done = true
	progress = 1.0
	wall_ms = Time.get_ticks_msec() - _t0
	var out := CBattle.outcome_from_result(built, sim.result(), "auto")
	out["scale"] = scale
	out["wall_ms"] = wall_ms
	finished.emit(out)
