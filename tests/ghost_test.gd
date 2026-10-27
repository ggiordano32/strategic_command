extends SceneTree
## The last-seen ghost (game/last_seen.gd, docs/design/ui.md), headless:
##   godot --headless --script res://tests/ghost_test.gd
## On asym_woods (side 0 the viewer) the sim is stepped until an enemy unit
## drawn so far drops out of sight: a ghost record with its last place, facing,
## alive count and men appears; it is still there (the outline stage) long after
## GHOST_FADE; it clears at once when the unit is seen again or destroyed; Low
## keeps no men; 

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const LastSeen := preload("res://game/last_seen.gd")
const Overlay := preload("res://game/overlay.gd")

var _ok := true


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		_ok = false


func _initialize() -> void:
	var sim := BattleSim.new()
	sim.setup(Scenarios.make("asym_woods"), 5000)
	_check(sim.vis_on != 0, "asym_woods has line of sight")
	var ls := LastSeen.new()
	var now := 1000
	var ghost := -1
	var low := LastSeen.new()
	while sim.tick < 6000 and sim.winner < 0 and ghost < 0:
		sim.step()
		now += 50
		ls.update(sim, 0, now, true)
		low.update(sim, 0, now, false)
		if not ls.recs.is_empty():
			ghost = ls.recs.keys()[0]
	_check(ghost >= 0, "an enemy unit dropped out of sight and got a ghost (tick %d)" % sim.tick)
	if ghost < 0:
		print("RESULT FAIL")
		quit(1)
		return
	var g: Dictionary = ls.recs[ghost]
	_check(sim.hidden_from(ghost, 0) and sim.u_side[ghost] == 1, "the ghost is an enemy unit hidden from side 0")
	_check(int(g["x"]) == sim.u_cx[ghost] and int(g["y"]) == sim.u_cy[ghost], "last place recorded")
	_check(int(g["alive"]) == sim.u_alive[ghost] and (g["mx"] as PackedInt32Array).size() == sim.u_alive[ghost],
		"alive count and the men's positions recorded")
	_check(low.recs.has(ghost) and (low.recs[ghost]["mx"] as PackedInt32Array).is_empty(), "Low: ghost without men")
	var fx := int(g["x"])
	_check(ls.fade(g, now) < 0.5, "fresh ghost is in the fading stage")
	# The unit really moves on; the ghost stays where it was seen.
	for k in 40:
		sim.step()
	ls.update(sim, 0, now + 1, true)
	_check(ls.recs.has(ghost) and int(ls.recs[ghost]["x"]) == fx, "the record stays at the last seen place")
	now += 20000
	ls.update(sim, 0, now, true)
	_check(ls.recs.has(ghost) and ls.fade(ls.recs[ghost], now) == 1.0 and not ls.animating(now),
		"after the fade the outline stage remains")
	# Seen again: force the sight flag.
	var was: int = sim.u_seen[ghost]
	sim.u_seen[ghost] = 1
	ls.update(sim, 0, now + 10, true)
	_check(not ls.recs.has(ghost), "seen again: the ghost clears at once")
	sim.u_seen[ghost] = 0
	ls.update(sim, 0, now + 20, true)
	_check(ls.recs.has(ghost), "hidden again after being seen: a new ghost")
	sim.u_state[ghost] = BattleSim.U_DESTROYED
	ls.update(sim, 0, now + 30, true)
	_check(not ls.recs.has(ghost), "destroyed: the ghost clears")
	sim.u_state[ghost] = BattleSim.U_READY
	sim.u_seen[ghost] = was
	# Own side is never ghosted; the other viewer has its own set.
	var ls1 := LastSeen.new()
	ls1.update(sim, 1, now, true)
	for u in ls1.recs:
		_check(sim.u_side[u] == 0, "side 1's ghosts are side 0 units")
	# The overlay draws from it (smoke: _process builds, no error).
	var ov := Overlay.new()
	ov.sim = sim
	ov.player_side = 0
	root.add_child(ov)
	ov._process(0.016)
	_check(ov.last_seen != null, "overlay holds a last-seen registry")
	# Battle end clears.
	sim.winner = 0
	ls.update(sim, 0, now + 40, true)
	_check(ls.recs.is_empty(), "battle over: no ghosts")
	print("RESULT " + ("PASS" if _ok else "FAIL"))
	quit(0 if _ok else 1)
