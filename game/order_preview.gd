extends RefCounted
## View-side record of orders the view has queued but the sim has not applied
## yet, so the UI can show them immediately (most visibly while paused, when
## no tick runs). It predicts each unit's order state by replaying the pending
## orders over the sim's current unit state with the same rules as
## BattleSim._apply_order. It never touches the sim.
##
## An order queued for tick T is applied by the sim during step() while
## sim.tick == T, so it is pending while T >= sim.tick.

const BattleSim := preload("res://sim/battle_sim.gd")

const KEYS := ["order", "ax", "ay", "face", "files", "dx", "dy", "dface", "target", "run"]

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
		var u := int(o.get("unit", -1))
		if u < 0 or u >= sim.n_units:
			continue
		if not _view.has(u):
			_view[u] = _snapshot(u)
		_predict(u, _view[u], o)


func has_pending(u: int) -> bool:
	return _view.has(u)


func pending_count() -> int:
	return _pending.size()


## Predicted value of u_<key>[u]: the pending prediction if any, else the sim.
func value(u: int, key: String) -> int:
	if _view.has(u):
		return _view[u][key]
	return (sim.get("u_" + key) as PackedInt32Array)[u]


func _snapshot(u: int) -> Dictionary:
	var d := {}
	for k in KEYS:
		d[k] = (sim.get("u_" + k) as PackedInt32Array)[u]
	return d


## Mirror of BattleSim._apply_order on the predicted fields.
func _predict(u: int, d: Dictionary, o: Dictionary) -> void:
	if sim.u_state[u] != BattleSim.U_READY:
		return
	var typ := int(o["type"])
	if typ == BattleSim.ORDER_MOVE:
		var x := clampi(int(o["x"]), 0, sim.field_w)
		var y := clampi(int(o["y"]), 0, sim.field_h)
		var face := int(o["facing"]) & 1023
		d["files"] = BattleSim.width_to_files(int(o["width"]), sim.u_alive[u])
		d["run"] = 1 if int(o.get("run", 0)) != 0 else 0
		d["target"] = -1
		var dx: int = x - d["ax"]
		var dy: int = y - d["ay"]
		if dx * dx + dy * dy <= BattleSim.REFORM_IN_PLACE_DIST * BattleSim.REFORM_IN_PLACE_DIST:
			d["ax"] = x
			d["ay"] = y
			d["face"] = face
			d["order"] = BattleSim.O_NONE
		else:
			d["order"] = BattleSim.O_MOVE
			d["dx"] = x
			d["dy"] = y
		d["dface"] = face
	elif typ == BattleSim.ORDER_ATTACK:
		var t := int(o["target"])
		if t < 0 or t >= sim.n_units or sim.u_side[t] == sim.u_side[u] or sim.u_state[t] == BattleSim.U_DESTROYED:
			return
		d["order"] = BattleSim.O_ATTACK
		d["target"] = t
		d["run"] = 1 if int(o.get("run", 0)) != 0 else 0
	elif typ == BattleSim.ORDER_HALT:
		d["order"] = BattleSim.O_NONE
		d["target"] = -1
	elif typ == BattleSim.ORDER_RUN:
		d["run"] = 1 if int(o.get("run", 0)) != 0 else 0
