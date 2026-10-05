extends RefCounted
## Basic deterministic battle AI (milestone 1).
##
## Runs inside BattleSim.step() and acts only by queueing the same orders a
## player would, so it stays lockstep-safe. Each AI unit thinks once a second
## (staggered by unit index): attack the nearest non-routing enemy unit, keep
## the current target unless another is clearly closer, run when close.

const M := 1024
const THINK_PERIOD := 10
const CHARGE_RANGE := 35 * M
const AI_PLAYER_BASE := 100  # order "player" id so AI orders sort after humans

const U_READY := 0
const U_ROUTING := 1
const U_DESTROYED := 2
const O_ATTACK := 2
const ORDER_ATTACK := 2


static func think(sim) -> void:
	var n_units: int = sim.n_units
	var tick: int = sim.tick
	for u in n_units:
		var side: int = sim.u_side[u]
		if sim.ai_sides[side] == 0:
			continue
		if sim.u_state[u] != U_READY:
			continue
		if (u + tick) % THINK_PERIOD != 0:
			continue
		var best := _nearest_enemy(sim, u, true)
		if best < 0:
			best = _nearest_enemy(sim, u, false)
		if best < 0:
			continue
		var cur := -1
		if sim.u_order[u] == O_ATTACK:
			cur = sim.u_target[u]
		var chosen := best
		if cur >= 0 and sim.u_state[cur] != U_DESTROYED and sim.u_state[best] == U_READY:
			# Keep the current target unless the new one is much closer
			# (distance ratio > ~1.4, i.e. squared ratio > 2).
			if sim.u_state[cur] == U_READY and _dist2(sim, u, cur) <= 2 * _dist2(sim, u, best):
				chosen = cur
		var run := 1 if _dist2(sim, u, chosen) < CHARGE_RANGE * CHARGE_RANGE else 0
		if chosen != cur or run != sim.u_run[u]:
			sim.queue_order({"tick": tick, "type": ORDER_ATTACK, "unit": u,
				"target": chosen, "run": run, "player": AI_PLAYER_BASE + side,
				"seq": u})


static func _dist2(sim, a: int, b: int) -> int:
	var dx: int = sim.u_cx[b] - sim.u_cx[a]
	var dy: int = sim.u_cy[b] - sim.u_cy[a]
	return dx * dx + dy * dy


static func _nearest_enemy(sim, u: int, ready_only: bool) -> int:
	var best := -1
	var best_d := 0
	var side: int = sim.u_side[u]
	for o in sim.n_units:
		if sim.u_side[o] == side:
			continue
		var s: int = sim.u_state[o]
		if s == U_DESTROYED or (ready_only and s != U_READY):
			continue
		var d := _dist2(sim, u, o)
		if best < 0 or d < best_d:
			best = o
			best_d = d
	return best
