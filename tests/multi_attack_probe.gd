extends SceneTree
## Probe (2026-11-01): two or more human armies ordered against one enemy army
## in the same turn (the owner: "I can't attack when multiple armies attack an
## army at once"). Prints each order's preview acceptance (the view's
## set_move6 path: CTurn.preview), the pending battles after resolve_turn,
## the move_failed / order_failed events and the armies' cells.
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const UT := preload("res://sim/unit_types.gd")

var mi := -1
var foe := -1

func _new() -> Dictionary:
	CData.use_pack("west")
	var st := CState.new_campaign("w", 11, [CData.faction_index("miskito")], {}, [], "west")
	mi = CData.faction_index("miskito")
	foe = CData.faction_index("tierra_firme")
	CRules.declare_war(st, mi, foe)
	CRules.declare_war(st, mi, CData.faction_index("new_spain"))
	st["armies"] = []
	return st

func _put(st: Dictionary, f: int, c: int, units: Array) -> Dictionary:
	var id := CRules.new_army_id(st, f)
	st["factions"][f]["next_army"] = int(st["factions"][f]["next_army"]) + 1
	var us: Array = []
	for t in units:
		us.append({"t": t, "n": UT.size_of(UT.index_of(t))})
	var a := {"id": id, "f": f, "r": CGrid.region(c), "units": us, "from": -1, "moved": 0, "busy": 0}
	CState.place(a, c)
	CRules._insert_army(st, a)
	return CState.army(st, id)

## A row of n passable cells (left to right, every step passable), all in
## one region when one_region, at least 2 from the region's settlement.
func _row(r: int, n: int, one_region: bool = true) -> Array:
	var site := CGrid.site(r)
	for c in CGrid.cells_of(r):
		var ok := true
		var out: Array = []
		for k in n:
			var d := CGrid.at(CGrid.cx(c) + k, CGrid.cy(c))
			if d < 0 or not CGrid.passable(d) or (one_region and CGrid.region(d) != r) or CGrid.cheb(d, site) < 2 \
					or (k > 0 and CGrid.step_cost(out[-1], d) <= 0):
				ok = false
				break
			out.append(d)
		if ok:
			return out
	return []

func _mv(a: Dictionary, e: Dictionary) -> Dictionary:
	return {"t": "move", "army": int(a["id"]), "x": CGrid.cx(CState.cell(e)), "y": CGrid.cy(CState.cell(e)),
		"mode": CData.MODE_SIEGE, "persist": 1, "tgt": int(e["id"])}

func _run(name: String, st: Dictionary, orders: Array) -> Dictionary:
	print("=== ", name)
	for a in st["armies"]:
		print("  army %d f%d cell (%d,%d) r %s units %d busy %d" % [int(a["id"]), int(a["f"]), int(a["x"]), int(a["y"]),
			CData.REGIONS[int(a["r"])]["key"], (a["units"] as Array).size(), int(a["busy"])])
	# The view's path: each order previewed after the ones before it.
	for i in orders.size():
		var pv := CTurn.preview(st, mi, orders.slice(0, i + 1))
		var why := "accepted"
		for e in pv["errors"]:
			if int(e[0]) == i:
				why = "REFUSED: " + str(e[1])
		print("  order %d (army %d -> tgt %d): %s; kind %s" % [i, int(orders[i]["army"]), int(orders[i].get("tgt", -1)), why,
			str(CRules.move_aim(st, CState.army(st, int(orders[i]["army"])), CRules.order_cell(st, CState.army(st, int(orders[i]["army"])), orders[i]),
				int(orders[i].get("tgt", -1)))["kind"])])
	var s1 := CTurn.resolve_turn(st, [CTurn.submission(st, mi, orders)])
	if OS.get_environment("PROBE_DBG") != "" and name.find(OS.get_environment("PROBE_DBG")) >= 0:
		var sd := CState.copy(st)
		var mv: Array = []
		for o in orders:
			mv.append([int(o["army"]), CRules.order_cell(sd, CState.army(sd, int(o["army"])), o), mi, CData.MODE_SIEGE, 1, int(o.get("tgt", -1)), -1, -1])
		CRules.execute_moves6(sd, mv)
		print("  DBG after human moves: battles ", JSON.stringify(sd["battles"]))
		for a in sd["armies"]:
			if int(a["f"]) == mi or int(a["f"]) == foe:
				print("  DBG army %d (%d,%d) busy %d r %d" % [int(a["id"]), int(a["x"]), int(a["y"]), int(a["busy"]), int(a["r"])])
	for b in s1["battles"]:
		print("  BATTLE %d r %s att %s def %s reinf %s at (%s,%s) settlement %s kind %s" % [int(b["id"]), CData.REGIONS[int(b["r"])]["key"],
			str(b["att"]), str(b["def"]), str(b["reinf"]), str(b.get("x", "-")), str(b.get("y", "-")), str(b.get("settlement", 0)), str(b.get("kind", ""))])
	if (s1["battles"] as Array).is_empty():
		print("  NO BATTLE")
		for e in s1["events"]:
			if int(e.get("turn", -1)) == int(st["turn"]) and str(e["k"]) not in ["moves", "income"]:
				print("    ev ", JSON.stringify(e).left(300))
	for e in s1["events"]:
		if int(e.get("turn", -1)) == int(st["turn"]) and str(e["k"]) in ["move_failed", "order_failed", "intercepted"]:
			print("  event ", e)
	for a in s1["armies"]:
		print("  after: army %d cell (%d,%d) busy %d moved %d tgt %s" % [int(a["id"]), int(a["x"]), int(a["y"]), int(a["busy"]), int(a["moved"]), str(a.get("tgt", -1))])
	return s1

func _init() -> void:
	var st0 := _new()
	var W := ["native_warriors", "native_warriors", "native_bowmen", "chieftain"]
	var E := ["musketeers", "w_pikemen", "general"]
	var reg := -1
	var row: Array = []
	for want in [mi, foe]:
		for r in CData.region_count():
			if reg < 0 and CState.owner(st0, r) == want:
				var rr := _row(r, 9)
				if rr.size() == 9:
					reg = r
					row = rr
	print("row ", row.size(), " in ", CData.REGIONS[reg]["key"])
	# A: both next to the enemy, either side of it.
	var st := CState.copy(st0)
	var e := _put(st, foe, row[4], E)
	var a1 := _put(st, mi, row[3], W)
	var a2 := _put(st, mi, row[5], W)
	_run("A both adjacent, either side", st, [_mv(a1, e), _mv(a2, e)])
	# A1: single attacker (control)
	st = CState.copy(st0)
	e = _put(st, foe, row[4], E)
	a1 = _put(st, mi, row[3], W)
	_run("A1 one attacker", st, [_mv(a1, e)])
	# B: one adjacent, one two cells off (a step)
	st = CState.copy(st0)
	e = _put(st, foe, row[4], E)
	a1 = _put(st, mi, row[3], W)
	a2 = _put(st, mi, row[6], W)
	_run("B one adjacent, one 2 cells off", st, [_mv(a1, e), _mv(a2, e)])
	# B2: the far one has the lower id order (order of orders swapped)
	st = CState.copy(st0)
	e = _put(st, foe, row[4], E)
	a1 = _put(st, mi, row[6], W)
	a2 = _put(st, mi, row[3], W)
	_run("B2 lower id far, higher id adjacent", st, [_mv(a1, e), _mv(a2, e)])
	# C: both march several cells
	st = CState.copy(st0)
	e = _put(st, foe, row[4], E)
	a1 = _put(st, mi, row[0], W)
	a2 = _put(st, mi, row[8], W)
	_run("C both march 3 cells", st, [_mv(a1, e), _mv(a2, e)])
	# D: both on the same side, next to each other
	st = CState.copy(st0)
	e = _put(st, foe, row[4], E)
	a1 = _put(st, mi, row[2], W)
	a2 = _put(st, mi, row[1], W)
	_run("D both same side, in a file", st, [_mv(a1, e), _mv(a2, e)])
	# D2: both same cell
	st = CState.copy(st0)
	e = _put(st, foe, row[4], E)
	a1 = _put(st, mi, row[1], W)
	a2 = _put(st, mi, row[1], W)
	_run("D2 both same cell 3 off", st, [_mv(a1, e), _mv(a2, e)])
	# E: three attackers
	st = CState.copy(st0)
	e = _put(st, foe, row[4], E)
	a1 = _put(st, mi, row[3], W)
	a2 = _put(st, mi, row[5], W)
	var a3 := _put(st, mi, row[8], W)
	_run("E three attackers", st, [_mv(a1, e), _mv(a2, e), _mv(a3, e)])
	# F: the first attacker is in a pending battle from the previous turn
	st = CState.copy(st0)
	e = _put(st, foe, row[4], E)
	a1 = _put(st, mi, row[3], W)
	var s1 := _run("F0 turn 1: a1 attacks", st, [_mv(a1, e)])
	if str(s1["phase"]) == "battles":
		print("  phase ", s1["phase"], " (phase battles: no orders until the battle is fought)")
	# Settlement cases: our town town_r (owned by mi), the enemy on a ring cell.
	var town_r := CData.region_index("cabo_gracias")
	var site := CGrid.site(town_r)
	var ring: Array = []
	for d in 8:
		var c := CGrid.at(CGrid.cx(site) + CGrid.DX[d], CGrid.cy(site) + CGrid.DY[d])
		if c >= 0 and CGrid.passable(c) and CGrid.step_cost(site, c) > 0:
			ring.append(c)
	print("site (%d,%d) owner %d ring %d" % [CGrid.cx(site), CGrid.cy(site), CState.owner(st0, town_r), ring.size()])
	# The enemy on a ring cell; a cell next to it (not the site, not ring-adjacent to it) for the field army.
	var ec: int = ring[0]
	var fc := -1
	for d in 8:
		var c := CGrid.at(CGrid.cx(ec) + CGrid.DX[d], CGrid.cy(ec) + CGrid.DY[d])
		if c >= 0 and c != site and CGrid.passable(c) and CGrid.step_cost(ec, c) > 0 and CGrid.site_region(c) < 0:
			fc = c
			break
	# I: a1 (lower id) in the field next to the enemy, a2 inside our town next to it.
	st = CState.copy(st0)
	e = _put(st, foe, ec, E)
	a1 = _put(st, mi, fc, W)
	a2 = _put(st, mi, site, W)
	_run("I lower id in the field, higher id inside our town, both next to the enemy", st, [_mv(a1, e), _mv(a2, e)])
	# I2: ids swapped (the town army the lower id).
	st = CState.copy(st0)
	e = _put(st, foe, ec, E)
	a1 = _put(st, mi, site, W)
	a2 = _put(st, mi, fc, W)
	_run("I2 lower id inside the town, higher id in the field", st, [_mv(a1, e), _mv(a2, e)])
	# I3: two armies inside the town.
	st = CState.copy(st0)
	e = _put(st, foe, ec, E)
	a1 = _put(st, mi, site, W)
	a2 = _put(st, mi, site, W)
	_run("I3 both inside our town next to the enemy", st, [_mv(a1, e), _mv(a2, e)])
	# I4: single army inside (control).
	st = CState.copy(st0)
	e = _put(st, foe, ec, E)
	a1 = _put(st, mi, site, W)
	_run("I4 one army inside the town (control)", st, [_mv(a1, e)])
	# K: the enemy besieges our town; two armies outside relieve (attack the besieger).
	st = CState.copy(st0)
	e = _put(st, foe, ec, E)
	CRules.start_siege(st, town_r, e, -1)
	a1 = _put(st, mi, row[0], W)
	a2 = _put(st, mi, row[8], W)
	_run("K relief: two field armies attack the besieger", st, [_mv(a1, e), _mv(a2, e)])
	# K2: one inside (a sally) and one outside.
	st = CState.copy(st0)
	e = _put(st, foe, ec, E)
	CRules.start_siege(st, town_r, e, -1)
	a1 = _put(st, mi, site, W)
	a2 = _put(st, mi, fc, W)
	_run("K2 sally from inside + relief next to it", st, [_mv(a1, e), _mv(a2, e)])
	# J: a2 besieges an enemy town and the target stands next to it.
	var er := -1
	for r in CData.region_count():
		if er < 0 and CState.owner(st0, r) == foe:
			er = r
	var es := CGrid.site(er)
	var ering: Array = []
	for d in 8:
		var c := CGrid.at(CGrid.cx(es) + CGrid.DX[d], CGrid.cy(es) + CGrid.DY[d])
		if c >= 0 and CGrid.passable(c) and CGrid.step_cost(es, c) > 0:
			ering.append(c)
	print("enemy town ", CData.REGIONS[er]["key"], " ring ", ering.size())
	if ering.size() >= 3:
		var tc := -1
		for d in 8:
			var c := CGrid.at(CGrid.cx(ering[0]) + CGrid.DX[d], CGrid.cy(ering[0]) + CGrid.DY[d])
			if c >= 0 and CGrid.passable(c) and CGrid.cheb(c, es) == 2:
				tc = c
				break
		st = CState.copy(st0)
		var bs1 := _put(st, mi, ering[0], W)
		CRules.start_siege(st, er, bs1, -1)
		var bs2 := _put(st, mi, ering[1], W)
		e = _put(st, foe, tc, E)
		print("  besieger roles ", CRules.siege_role(st, bs1), " ", CRules.siege_role(st, bs2), " dist ", CGrid.cheb(CState.cell(bs1), tc), " ", CGrid.cheb(CState.cell(bs2), tc))
		_run("J two besiegers attack an enemy army next to the siege", st, [_mv(bs1, e), _mv(bs2, e)])
	# T: a fortified target, two attackers from 3 cells either side.
	st = CState.copy(st0)
	e = _put(st, foe, row[4], E)
	e["stance"] = CData.ST_FORTIFY
	a1 = _put(st, mi, row[1], W)
	a2 = _put(st, mi, row[7], W)
	_run("T fortified target", st, [_mv(a1, e), _mv(a2, e)])
	_two_targets(st0, W, E)
	quit(0)


## A box of passable cells w x h (x0..x0+w-1, y0..y0+h-1) whose regions are
## owned by mi or foe, every 8-step inside passable; regions: 1 all one region,
## 2 exactly two regions (split left / right); returns the top-left cell or -1.
func _box(st: Dictionary, w: int, h: int, regions: int) -> int:
	for c in CGrid.count():
		var x0 := CGrid.cx(c)
		var y0 := CGrid.cy(c)
		var ok := true
		var regs := {}
		for dy in h:
			for dx in w:
				var d := CGrid.at(x0 + dx, y0 + dy)
				if d < 0 or not CGrid.passable(d) or CGrid.site_region(d) >= 0 or CGrid.is_wet(d):
					ok = false
					break
				var r := CGrid.region(d)
				var o := CState.owner(st, r)
				if o != mi and o != foe and not CState.at_war(st, mi, o):
					ok = false
					break
				if CGrid.cheb(d, CGrid.site(r)) < 2:
					ok = false
					break
				regs[r] = 1
				if dx > 0 and CGrid.step_cost(CGrid.at(x0 + dx - 1, y0 + dy), d) <= 0:
					ok = false
					break
				if dy > 0 and CGrid.step_cost(CGrid.at(x0 + dx, y0 + dy - 1), d) <= 0:
					ok = false
					break
			if not ok:
				break
		if not ok or regs.size() != regions:
			continue
		if regions == 2:
			# left column in one region, right column in the other
			var rl := CGrid.region(CGrid.at(x0, y0 + h / 2))
			var rr := CGrid.region(CGrid.at(x0 + w - 1, y0 + h / 2))
			if rl == rr:
				continue
		return c
	return -1


## A 15 x 7 box (as _box, any number of regions) whose row 3 is one region
## for x 0..6 and another for x 7..14.
func _border_box(st: Dictionary) -> int:
	for c in CGrid.count():
		var x0 := CGrid.cx(c)
		var y0 := CGrid.cy(c)
		if x0 + 15 > CGrid.width() or y0 + 7 > CGrid.height():
			continue
		var r1 := CGrid.region(CGrid.at(x0, y0 + 3))
		var r2 := CGrid.region(CGrid.at(x0 + 14, y0 + 3))
		if r1 < 0 or r2 < 0 or r1 == r2:
			continue
		var ok := true
		for dx in 15:
			if CGrid.region(CGrid.at(x0 + dx, y0 + 3)) != (r1 if dx < 7 else r2):
				ok = false
				break
		if not ok:
			continue
		for dy in 7:
			for dx in 15:
				var d := CGrid.at(x0 + dx, y0 + dy)
				if d < 0 or not CGrid.passable(d) or CGrid.site_region(d) >= 0 or CGrid.is_wet(d):
					ok = false
					break
				var o := CState.owner(st, CGrid.region(d))
				if o != mi and o != foe and not CState.at_war(st, mi, o):
					ok = false
					break
				if CGrid.cheb(d, CGrid.site(CGrid.region(d))) < 2:
					ok = false
					break
				if dx > 0 and CGrid.step_cost(CGrid.at(x0 + dx - 1, y0 + dy), d) <= 0:
					ok = false
					break
				if dy > 0 and CGrid.step_cost(CGrid.at(x0 + dx, y0 + dy - 1), d) <= 0:
					ok = false
					break
			if not ok:
				break
		if ok:
			return c
	return -1


func _at(b: int, dx: int, dy: int) -> int:
	return CGrid.at(CGrid.cx(b) + dx, CGrid.cy(b) + dy)


## Three armies against two enemy armies X and Y (the coordinator's second report).
func _two_targets(st0: Dictionary, W: Array, E: Array) -> void:
	for regions in [1, 2]:
		var b := _box(st0, 15, 7, 1) if regions == 1 else _border_box(st0)
		if b < 0:
			b = _box(st0, 11, 7, regions)
		if b < 0:
			print("no box with %d region(s)" % regions)
			continue
		print("--- box %d region(s) at (%d,%d): left %s right %s" % [regions, CGrid.cx(b), CGrid.cy(b),
			CData.REGIONS[CGrid.region(_at(b, 0, 3))]["key"], CData.REGIONS[CGrid.region(_at(b, 12, 3))]["key"]])
		var border := 7
		if regions == 2:
			# one attacker across the border from its target, next to it / two cells off
			for off in [1, 2]:
				var stb := CState.copy(st0)
				var xb := _put(stb, foe, _at(b, border - 1, 3), E)
				var ab := _put(stb, mi, _at(b, border - 1 + off, 3), W)
				_run("XB one attacker across the border, %d cell(s) off (X r %s, attacker r %s)" % [off, CData.REGIONS[int(xb["r"])]["key"], CData.REGIONS[int(ab["r"])]["key"]],
					stb, [_mv(ab, xb)])
		for gap in [1, 2, 3, 4]:
			var xx: int = 6 - int(gap) / 2
			if regions == 2:
				xx = border - 1 - (int(gap) - 1) / 2
			var yx: int = xx + int(gap)
			# split 2 + 1, marching (3 cells off)
			var st := CState.copy(st0)
			var x := _put(st, foe, _at(b, xx, 3), E)
			var y := _put(st, foe, _at(b, yx, 3), E)
			var a1 := _put(st, mi, _at(b, xx - 3, 3), W)
			var a2 := _put(st, mi, _at(b, xx, 0), W)
			var a3 := _put(st, mi, _at(b, yx + 3, 3), W)
			_run("2T r%d gap %d split 2+1 marching (X r %s, Y r %s)" % [regions, gap, CData.REGIONS[int(x["r"])]["key"], CData.REGIONS[int(y["r"])]["key"]],
				st, [_mv(a1, x), _mv(a2, x), _mv(a3, y)])
			# split 2 + 1, all starting next to their targets
			st = CState.copy(st0)
			x = _put(st, foe, _at(b, xx, 3), E)
			y = _put(st, foe, _at(b, yx, 3), E)
			a1 = _put(st, mi, _at(b, xx - 1, 3), W)
			a2 = _put(st, mi, _at(b, xx, 2), W)
			a3 = _put(st, mi, _at(b, yx + 1, 3), W)
			_run("2T r%d gap %d split 2+1 adjacent" % [regions, gap], st, [_mv(a1, x), _mv(a2, x), _mv(a3, y)])
			# split 1 + 2, the Y attacker the lowest id
			st = CState.copy(st0)
			x = _put(st, foe, _at(b, xx, 3), E)
			y = _put(st, foe, _at(b, yx, 3), E)
			a3 = _put(st, mi, _at(b, yx + 3, 3), W)
			a1 = _put(st, mi, _at(b, xx - 3, 3), W)
			a2 = _put(st, mi, _at(b, xx, 0), W)
			_run("2T r%d gap %d split 1+2 marching, Y's attacker first" % [regions, gap], st, [_mv(a3, y), _mv(a1, x), _mv(a2, x)])
			# three on X, marching
			st = CState.copy(st0)
			x = _put(st, foe, _at(b, xx, 3), E)
			y = _put(st, foe, _at(b, yx, 3), E)
			a1 = _put(st, mi, _at(b, xx - 3, 3), W)
			a2 = _put(st, mi, _at(b, xx, 0), W)
			a3 = _put(st, mi, _at(b, yx + 3, 3), W)
			_run("2T r%d gap %d three on X marching" % [regions, gap], st, [_mv(a1, x), _mv(a2, x), _mv(a3, x)])
			# three on X, the third from beyond Y (its path passes Y)
			st = CState.copy(st0)
			x = _put(st, foe, _at(b, xx, 3), E)
			y = _put(st, foe, _at(b, yx, 3), E)
			a1 = _put(st, mi, _at(b, xx - 1, 3), W)
			a2 = _put(st, mi, _at(b, xx, 6), W)
			a3 = _put(st, mi, _at(b, yx + 1, 3), W)
			_run("2T r%d gap %d three on X, near" % [regions, gap], st, [_mv(a1, x), _mv(a2, x), _mv(a3, x)])
			# the zone lock alone: one army next to Y, ordered at X; and backing off from Y
			st = CState.copy(st0)
			x = _put(st, foe, _at(b, xx, 3), E)
			y = _put(st, foe, _at(b, yx, 3), E)
			a3 = _put(st, mi, _at(b, yx + 1, 3), W)
			_run("2T r%d gap %d one army next to Y attacks X" % [regions, gap], st, [_mv(a3, x)])
			st = CState.copy(st0)
			x = _put(st, foe, _at(b, xx, 3), E)
			y = _put(st, foe, _at(b, yx, 3), E)
			a3 = _put(st, mi, _at(b, yx + 1, 3), W)
			var away := _at(b, yx + 1, 6)
			_run("2T r%d gap %d back off: the army next to Y marches to (%d,%d)" % [regions, gap, CGrid.cx(away), CGrid.cy(away)], st,
				[{"t": "move", "army": int(a3["id"]), "x": CGrid.cx(away), "y": CGrid.cy(away), "mode": CData.MODE_SIEGE, "persist": 1}])
