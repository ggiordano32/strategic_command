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
## Live co-op: where the not-yet-applied orders come from instead (the
## lockstep layer's queue, both players' orders, plus the sim's own).
var source := Callable()
var _pending: Array = []     # orders in queue order (copies)
var _view: Dictionary = {}   # unit -> predicted {key: int}


func add(order: Dictionary) -> void:
	_pending.append(order.duplicate())
	refresh()


## Drop orders the sim has applied and rebuild the predictions. Cheap; call
## every frame and after queueing.
func refresh() -> void:
	if source.is_valid():
		_pending = source.call()
	var keep: Array = []
	var applied_all := false
	if sim.phase == BattleSim.PHASE_DEPLOY and not source.is_valid():
		# Deployment: the clock stands at 0, so an order's tick cannot say
		# whether it was applied; none of ours left in the sim = all were.
		applied_all = true
		for so in sim.pending_orders:
			if int(so["player"]) < 50:
				applied_all = false
	for o in _pending:
		if int(o["tick"]) >= sim.tick and not applied_all:
			keep.append(o)
	_pending = keep
	_view = {}
	for o in _pending:
		for u in BattleSim.order_units(sim, o):
			if not _view.has(u):
				_view[u] = BattleSim.order_fields(sim, u)
			BattleSim.apply_order_rule(sim, u, _view[u], o)


## How a pending move of u was kept to ground it can reach (the order
## rule's "snap": 0 as ordered, 1 beside a house or wall, 2 to the gate on
## its side, 3 no way); -1 if none pending.
func snap_of(u: int) -> int:
	if not _view.has(u):
		return -1
	return int((_view[u] as Dictionary).get("snap", 0))


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


# ---------------------------------------------------------------- walls ---
# What a unit will do on the walls, predicted from the same sim rules
# (BattleSim.wall_snap / wall_anchor / wall_slots / ascent_end /
# descent_end / route_to), for the overlay to draw: the wall line its men
# will stand in, the stair it will use and its way to it.

const UT := preload("res://sim/unit_types.gd")

var _route_key := []
var _route := PackedInt32Array()


## The wall move of unit u under its predicted order (pending orders
## included); see plan_from.
func wall_plan(u: int) -> Dictionary:
	if sim.city_on == 0 or sim.ws_x0.size() == 0 or sim.u_state[u] != BattleSim.U_READY:
		return {}
	var d: Dictionary = _view[u] if _view.has(u) else BattleSim.order_fields(sim, u)
	return plan_from(u, d, _view.has(u))


## The wall move of unit u if `order` were given now (the drag preview).
func wall_plan_for(u: int, order: Dictionary) -> Dictionary:
	if sim.city_on == 0 or sim.ws_x0.size() == 0:
		return {}
	var d: Dictionary = (_view[u] as Dictionary).duplicate() if _view.has(u) else BattleSim.order_fields(sim, u)
	BattleSim.apply_order_rule(sim, u, d, order)
	return plan_from(u, d, true)


## A wall move from unit u's order fields `d` (`pending`: not applied yet):
## {} if none, else {mode: "up" | "down" | "along" | "hold", seg (the
## stretch it ends on, -1: the ground), slots (absolute x, y of its men on
## the wall, if it ends there), stair_seg / stair_end (the stair used, -1
## none), route (x, y points from the unit to where it goes, sim units)}.
func plan_from(u: int, d: Dictionary, pending: bool) -> Dictionary:
	var ty: int = sim.u_type[u]
	var alive: int = sim.u_alive[u]
	var cx: int = sim.u_cx[u]
	var cy: int = sim.u_cy[u]
	var out := {"mode": "", "seg": -1, "slots": PackedInt32Array(), "stair_seg": -1, "stair_end": -1,
		"route": PackedInt32Array()}
	var wall: int = sim.u_wall[u]
	var stair: int = sim.u_stair[u]
	if stair == BattleSim.ST_LADDER:
		# Climbing ladders now: its stretch, its men's places, the foot.
		out["mode"] = "climb"
		out["seg"] = wall - 1
		out["slots"] = BattleSim.wall_slots(sim, wall - 1, sim.u_ax[u], sim.u_ay[u], alive, ty)
		out["foot"] = Vector2i(sim.u_lfx[u], sim.u_lfy[u])
		return out
	var lad_go := stair == BattleSim.ST_LADDER_GO and not pending
	if wall == 0 and int(d["order"]) == BattleSim.O_MOVE and (lad_go or BattleSim.can_ladder(sim, u)):
		# Up the ladders: to the foot of the wall, up onto the walkway.
		var lx := int(d["dx"])
		var ly := int(d["dy"])
		var lsg := -1
		if lad_go:
			lsg = sim.u_sseg[u]
			lx = sim.u_wx[u]
			ly = sim.u_wy[u]
		else:
			var wl := BattleSim.wall_snap(sim, lx, ly)
			if wl.z >= 0 and BattleSim.ladder_ok(sim, u, wl.z, wl.x, wl.y):
				lsg = wl.z
				lx = wl.x
				ly = wl.y
		if lsg >= 0:
			var lf := BattleSim.ladder_foot(sim, lsg, lx, ly)
			out["mode"] = "ladder"
			out["seg"] = lsg
			out["foot"] = Vector2i(lf.x, lf.y)
			var rl := PackedInt32Array([cx, cy])
			rl.append_array(_route_cached(u, Vector2i(sim.u_ax[u], sim.u_ay[u]), Vector2i(lf.x, lf.y)))
			rl.append_array([lx, ly])
			out["route"] = rl
			var wal := BattleSim.wall_anchor(sim, lsg, lx, ly, alive, ty)
			out["slots"] = BattleSim.wall_slots(sim, lsg, wal.x, wal.y, alive, ty)
			return out
	if wall > 0 and stair == 0 and int(d["order"]) == BattleSim.O_MOVE and pending:
		# Down (and maybe up again onto another stretch).
		var sg := wall - 1
		var e := BattleSim.descent_end(sim, sg, cx, cy, true, int(d["dx"]), int(d["dy"]))
		out["mode"] = "down"
		out["stair_seg"] = sg
		out["stair_end"] = e
		var route := PackedInt32Array([cx, cy])
		for q in 3:
			var p: Vector2i = sim.stair_pt(sg, e, q)
			route.append_array([p.x, p.y])
		var ws := BattleSim.wall_snap(sim, int(d["dx"]), int(d["dy"]))
		var foot: Vector2i = sim.stair_pt(sg, e, 2)
		if ws.z >= 0:
			var e2 := BattleSim.ascent_end(sim, ws.z, foot.x, foot.y, ws.x, ws.y)
			var f2: Vector2i = sim.stair_pt(ws.z, e2, 2)
			route.append_array(_route_cached(u, foot, f2))
			for q in [1, 0]:
				var p2: Vector2i = sim.stair_pt(ws.z, e2, q)
				route.append_array([p2.x, p2.y])
			var wa := BattleSim.wall_anchor(sim, ws.z, ws.x, ws.y, alive, ty)
			out["seg"] = ws.z
			out["slots"] = BattleSim.wall_slots(sim, ws.z, wa.x, wa.y, alive, ty)
			out["up_seg"] = ws.z
			out["up_end"] = e2
		else:
			route.append_array(_route_cached(u, foot, Vector2i(int(d["dx"]), int(d["dy"]))))
		out["route"] = route
		return out
	if wall > 0 and (stair == 0 or stair == 3):
		out["mode"] = "along" if pending else "hold"
		out["seg"] = wall - 1
		out["slots"] = BattleSim.wall_slots(sim, wall - 1, int(d["ax"]), int(d["ay"]), alive, ty)
		return out
	if stair == 1:
		# Coming down now: the stair, then on.
		var sg1: int = sim.u_sseg[u]
		var e1: int = sim.u_send[u]
		out["mode"] = "down"
		out["stair_seg"] = sg1
		out["stair_end"] = e1
		var r1 := PackedInt32Array([cx, cy])
		for q in 3:
			var p3: Vector2i = sim.stair_pt(sg1, e1, q)
			r1.append_array([p3.x, p3.y])
		out["route"] = r1
		return out
	if wall == 0 and int(d["order"]) == BattleSim.O_MOVE and BattleSim.can_man_walls(sim, u):
		var gx := int(d["dx"])
		var gy := int(d["dy"])
		var sg2 := -1
		var e3 := 0
		if stair == 2 and not pending:
			sg2 = sim.u_sseg[u]
			e3 = sim.u_send[u]
			gx = sim.u_wx[u]
			gy = sim.u_wy[u]
		else:
			var ws2 := BattleSim.wall_snap(sim, gx, gy)
			if ws2.z < 0:
				return {}
			sg2 = ws2.z
			gx = ws2.x
			gy = ws2.y
			e3 = BattleSim.ascent_end(sim, sg2, int(d["ax"]), int(d["ay"]), gx, gy)
		var foot2: Vector2i = sim.stair_pt(sg2, e3, 2)
		out["mode"] = "up"
		out["seg"] = sg2
		out["stair_seg"] = sg2
		out["stair_end"] = e3
		var r2 := PackedInt32Array([cx, cy])
		r2.append_array(_route_cached(u, Vector2i(sim.u_ax[u], sim.u_ay[u]), foot2))
		for q in [1, 0]:
			var p4: Vector2i = sim.stair_pt(sg2, e3, q)
			r2.append_array([p4.x, p4.y])
		out["route"] = r2
		var wa2 := BattleSim.wall_anchor(sim, sg2, gx, gy, alive, ty)
		out["slots"] = BattleSim.wall_slots(sim, sg2, wa2.x, wa2.y, alive, ty)
		return out
	return {}


## The street route from a to b (BattleSim.route_to, read-only), cached
## while the ends (to 4 m) and the gates stay the same: [] if no way.
func _route_cached(u: int, a: Vector2i, b: Vector2i) -> PackedInt32Array:
	var key := [u, a.x >> 12, a.y >> 12, b.x >> 12, b.y >> 12, sim.nav_epoch]
	if key != _route_key:
		_route_key = key
		var gm: int = sim._ground_mask(u)
		_route = sim.route_to(a.x, a.y, b.x, b.y, gm)
	return _route


## A move of unit u to (x, y) on a wall it cannot make: why ("" if it can,
## or (x, y) is not on a wall).
func wall_refusal(u: int, x: int, y: int) -> String:
	if sim.city_on == 0 or sim.ws_x0.size() == 0:
		return ""
	if UT.stat(sim.u_type[u], "fixed") != 0:
		return "A tower's engine stays on its tower: tap an enemy to shoot at it"
	if sim.u_stair[u] == BattleSim.ST_LADDER:
		return "Climbing the ladders: orders wait until all are up"
	var ws := BattleSim.wall_snap(sim, x, y)
	if ws.z < 0 or (sim.u_wall[u] > 0 and ws.z == sim.u_wall[u] - 1):
		return ""
	if sim.u_wall[u] == 0 and BattleSim.can_ladder(sim, u):
		if not BattleSim.ladder_ok(sim, u, ws.z, ws.x, ws.y):
			return "No ladders there: a tower, a gate, the sea or out of reach"
		return ""
	if not BattleSim.can_man_walls(sim, u):
		if sim.u_side[u] != sim.city_def:
			if UT.stat(sim.u_type[u], "ram") != 0:
				return "The ram cannot climb: tap a gate to batter it"
			if sim.u_wall[u] > 0:
				return "Down into the town first (Come down), or along this wall"
			var c0: int = sim.u_cls[u]
			if c0 == UT.CLS_CAV or c0 == UT.CLS_PIKE or c0 == UT.CLS_ART:
				return "Only foot (not pikes) can climb ladders"
			return "No ladders: they come after a turn of siege (custom battles: Ladders)"
		var c: int = sim.u_cls[u]
		if c == UT.CLS_CAV:
			return "Cavalry cannot man walls"
		if c == UT.CLS_ART:
			return "Engines cannot go up on the walls"
		return "Pikes cannot man walls"
	if sim.phase == BattleSim.PHASE_DEPLOY:
		return ""  # deployment: placed straight onto the walkway
	var from := Vector2i(sim.u_ax[u], sim.u_ay[u])
	if sim.u_wall[u] > 0:
		var e0 := BattleSim.descent_end(sim, sim.u_wall[u] - 1, sim.u_cx[u], sim.u_cy[u], true, ws.x, ws.y)
		from = sim.stair_pt(sim.u_wall[u] - 1, e0, 2)
	var e := BattleSim.ascent_end(sim, ws.z, from.x, from.y, ws.x, ws.y)
	var gm: int = sim._ground_mask(u)
	var foot: Vector2i = sim.stair_pt(ws.z, e, 2)
	if sim.route_to(from.x, from.y, foot.x, foot.y, gm).is_empty():
		return "No way to a stair of that wall from here"
	return ""
