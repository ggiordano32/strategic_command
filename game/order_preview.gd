extends RefCounted
## View-side record of orders the view has queued but the sim has not applied
## yet, so the UI can show them immediately (most visibly while paused, when
## no tick runs). It predicts each unit's order state by replaying the pending
## orders over the sim's current unit state through the sim's own order rules
## (BattleSim.order_units / apply_order_rule), so prediction and sim cannot
## drift apart as rules change. It never touches the sim.
##
## An order queued for tick T is applied by the sim during step() while
## sim.tick == T, so it is pending while T >= sim.tick.

const BattleSim := preload("res://sim/battle_sim.gd")

var sim
var _pending: Array = []     # orders in queue order (copies)
var _view: Dictionary = {}   # unit -> predicted {key: int}


func add(order: Dictionary) -> void:
	_pending.append(order.duplicate())
	refresh()


## Drop orders the sim has applied and rebuild the predictions. Cheap; call
## every frame and after queueing.
func refresh() -> void:
	var keep: Array = []
	for o in _pending:
		if int(o["tick"]) >= sim.tick:
			keep.append(o)
	_pending = keep
	_view = {}
	for o in _pending:
		for u in BattleSim.order_units(sim, o):
			if not _view.has(u):
				_view[u] = BattleSim.order_fields(sim, u)
			BattleSim.apply_order_rule(sim, u, _view[u], o)


func has_pending(u: int) -> bool:
	return _view.has(u)


func pending_count() -> int:
	return _pending.size()


## Predicted value of u_<key>[u] (key in BattleSim.ORDER_KEYS): the pending
## prediction if any, else the sim.
func value(u: int, key: String) -> int:
	if _view.has(u):
		return _view[u][key]
	return (sim.get("u_" + key) as PackedInt32Array)[u]
