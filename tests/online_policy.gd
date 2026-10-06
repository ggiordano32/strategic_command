extends RefCounted
## A simple scripted player for the online tests (the same policy as
## tests/campaign_solo.gd): build the first affordable of barracks / farm /
## market / walls in each region, recruit the best line unit while upkeep
## stays under 70% of income, and attack the most valuable neighbour at war
## (or independent) when 1.4 times its defence, assaulting at once (move
## mode 1: no siege). Deterministic: same state, same orders.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CAI := preload("res://campaign/cai.gd")
const UT := preload("res://sim/unit_types.gd")


## attack_pct: attack when the army is this % of the target's defence.
## march: armies with nothing to attack move towards the nearest enemy.
static func plan(st: Dictionary, f: int, attack_pct: int = 140, march: bool = false) -> Array:
	var orders: Array = []
	var ps := CState.copy(st)
	if not CState.alive(ps, f):
		return orders
	for r in CState.regions_of(ps, f):
		for c in [CData.BARRACKS, CData.FARM, CData.MARKET, CData.WALLS]:
			var o := {"t": "build", "r": r, "chain": c}
			if CRules.apply_order(ps, f, o) == "":
				orders.append(o)
				break
	var inc := int(CRules.income(ps, f)["total"])
	for r in CState.regions_of(ps, f):
		for line in ["heavy", "spear", "pike", "light", "cav", "javelin"]:
			for tier in [3, 2, 1]:
				var key := CState.roster_type(f, line, tier)
				if key == "" or CRules.recruit_check(ps, f, r, key) != "":
					continue
				if CRules.upkeep(ps, f) + CState.upkeep_of(UT.index_of(key)) > inc * 70 / 100:
					continue
				var o := {"t": "recruit", "r": r, "unit": key}
				if CRules.apply_order(ps, f, o) == "":
					orders.append(o)
				break
	for a in CState.armies_of(ps, f):
		if int(a["busy"]) != 0:
			continue
		var best := -1
		var best_v := 0
		for t in CRules.move_targets(ps, a):
			if not CState.at_war(ps, f, CState.owner(ps, t)):
				continue
			var d := CAI.target_defence(ps, f, t)
			if CState.strength(a) * 100 < d * attack_pct:
				continue
			var v := CAI.region_value(ps, t) * 1000 / maxi(d, 1)
			if v > best_v:
				best_v = v
				best = t
		if best >= 0:
			# Storm it at once (a battle this turn, as before sieges).
			orders.append({"t": "move", "army": int(a["id"]), "to": best, "mode": CData.MODE_ASSAULT})
		elif march:
			var step := _step_towards_enemy(ps, f, a)
			if step >= 0:
				orders.append({"t": "move", "army": int(a["id"]), "to": step})
	return orders


## First step (into friendly land) on the shortest path to a region that
## can be attacked, or -1.
static func _step_towards_enemy(st: Dictionary, f: int, a: Dictionary) -> int:
	var start := int(a["r"])
	var first := {start: -1}
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var r: int = queue.pop_front()
		for e in CData.adjacent(r):
			var n := int(e[0])
			if first.has(n):
				continue
			var o := CState.owner(st, n)
			var step: int = n if r == start else int(first[r])
			if CState.at_war(st, f, o):
				return step if r != start else -1
			if not CState.friendly(st, f, o) or not CState.battle_at(st, n).is_empty():
				continue
			first[n] = step
			queue.append(n)
	return -1
