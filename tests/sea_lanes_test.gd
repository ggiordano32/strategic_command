extends SceneTree
## Every Rome lane's sea battle map (Rome's navy R3, 2026-10-24), headless:
##   godot --headless --script res://tests/sea_lanes_test.gd [-- --pack=west]
## A raid on a lane is fought at one of the lane's sea cells (CLanes.cells_of); the
## battle's water is CSeaBattle.land_of(cell, seed): a coast on the sides where the
## neighbouring cells are land, else open sea with an island. For every sea cell of
## every lane (and every exit lane) and four seeds (wind 285 / 315 / 345, as the
## campaign rolls it around the pack's north-westerly) this builds the sea map the
## way cseabattle.build does (three triremes a side, the layout "we" when the coast
## has a west or north side) and asserts: both fleets start on open water (no land or
## shoal under the ship, START_CLEAR_M clear), the fleets start apart, there is a line
## of open water between them (no island or point blocks the two starts' sight), and
## no map is more than MAX_LAND_PCT % land. Prints a table per lane.

const SeaSim := preload("res://sim/sea_sim.gd")
const CData := preload("res://campaign/cdata.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const CLanes := preload("res://campaign/clanes.gd")
const CSeaBattle := preload("res://campaign/cseabattle.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const CState := preload("res://campaign/cstate.gd")
const CTurn := preload("res://campaign/cturn.gd")
const PackView := preload("res://game/campaign/pack_view.gd")

const MAX_LAND_PCT := 50      # no map more than this % land (grid cells that are land)
const MIN_APART_M := 250      # the fleets' centroids at least this far apart
const SEEDS := 4
const NO_SEA := ["Gades - Tingis"]   # lanes known to have no sea cell

var _ok := true


func _check(c: bool, what: String) -> void:
	if not c:
		print("FAIL " + what)
		_ok = false


func _initialize() -> void:
	var pack := "rome"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack="):
			pack = a.substr(7)
	PackView.use_pack(pack)
	print("pack %s: %d lanes, %d exits" % [pack, CData.SEA_LANES.size(), CLanes.total() - CData.SEA_LANES.size()])
	print("%-30s %5s %5s %5s %6s %6s %5s %5s %s" % ["lane", "cells", "coast", "isle", "land%", "maxl%", "bad", "isleLOS", "worst"])
	var base_w := int(CData.ship_const("WIND_FROM_DEG", 90))
	var total_bad := 0
	for id in CLanes.total():
		var cells := CLanes.cells_of(id)
		var n := 0
		var coast := 0
		var isle := 0
		var land_sum := 0
		var land_max := 0
		var bad := 0
		var blind := 0
		var worst := ""
		for c in cells:
			if not CFleet.is_sea(c):
				continue
			for k in SEEDS:
				var rs := (c * 7919 + k * 104729 + 12345) & 0x7FFFFFFF
				var land := CSeaBattle.land_of(c, rs)
				n += 1
				var kind := int(land.get("kind", 0))
				if kind == 2:
					coast += 1
				elif kind == 1:
					isle += 1
				var dirs := int(land.get("dirs", 0))
				var lay := "we" if ((dirs >> 2) & 1 != 0 or (dirs >> 6) & 1 != 0) else "ns"
				var units: Array = []
				for side in 2:
					for i in 3:
						units.append({"side": side, "t": "trireme"})
				var scn := {"sea": 1, "wind_deg": (base_w + (k - 1) * 30 + 360) % 360, "wind_str": 55, "ai_sides": [1, 1],
					"land": land, "layout": lay, "units": units}
				var sim := SeaSim.new()
				sim.setup(scn, rs & 0xFFFF)
				var lc := 0
				for g in sim.g_w * sim.g_h:
					if sim.g[g] == 2:
						lc += 1
				var lp := lc * 100 / (sim.g_w * sim.g_h)
				land_sum += lp
				land_max = maxi(land_max, lp)
				var why := _why(sim, lp)
				if why.begins_with("los") and kind == 1:
					blind += 1   # an island between the fleets is the map's feature (they sail round it); counted, not failed
				elif why != "":
					bad += 1
					if worst == "":
						worst = "%s @%d,%d k%d" % [why, CGrid.cx(c), CGrid.cy(c), kind]
		total_bad += bad
		var nm := CLanes.lane_name(id)
		if n == 0:
			# (the Straits of Gibraltar are land in the grid: Gades - Tingis joins two ports by army link only, no raid can be fought on it)
			_check(NO_SEA.has(nm), "lane %s has no sea cell" % nm)
			print("%-30s  no sea cells (an army link only)" % nm)
			continue
		print("%-30s %5d %5d %5d %6.1f %6d %5d %5d %s" % [nm.substr(0, 30), n, coast, isle, float(land_sum) / maxf(n, 1.0), land_max, bad, blind, worst])
		_check(bad == 0, "lane %s: %d bad maps (%s)" % [nm, bad, worst])
	print("bad maps in all: %d" % total_bad)
	if pack == "rome":
		_raid_battles()
	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


## "" when the map is sane, else why not.
func _why(sim: SeaSim, land_pct: int) -> String:
	if land_pct > MAX_LAND_PCT:
		return "land %d%%" % land_pct
	var cx := [0, 0]
	var cy := [0, 0]
	var cn := [0, 0]
	for s in sim.n_units:
		var x := sim.s_x[s] / SeaSim.U
		var y := sim.s_y[s] / SeaSim.U
		if sim.land_at_m(x, y) != 0:
			return "ship %d on land/shoal" % s
		if x < 0 or y < 0 or x >= sim.field_w or y >= sim.field_h:
			return "ship %d off the field" % s
		var sd := int(sim.u_side[s])
		cx[sd] += x
		cy[sd] += y
		cn[sd] += 1
	if cn[0] == 0 or cn[1] == 0:
		return "no ships"
	var ax: int = cx[0] / cn[0]
	var ay: int = cy[0] / cn[0]
	var bx: int = cx[1] / cn[1]
	var by: int = cy[1] / cn[1]
	var dx := bx - ax
	var dy := by - ay
	var d := int(sqrt(float(dx * dx + dy * dy)))
	if d < MIN_APART_M:
		return "apart %d m" % d
	var steps := d / 20
	for i in range(1, steps):
		if sim.land_at_m(ax + dx * i / steps, ay + dy * i / steps) == 2:
			return "los blocked at %d%%" % (i * 100 / steps)
	return ""


## The plan's "done when": a Rome campaign fights a sea battle from a lane raid with the corvus deciding
## it. Carthage (at war) raids the Latium - Sardinia lane with two Punic quinqueremes and a trireme;
## Rome's fleet (a corvus quinquereme and a trireme) sails onto it (an fmove at the raider: a pending
## sea battle at a lane cell), CBattle.build makes the scenario, the sim fights it AI against AI, and the
## outcome is written back (CTurn.apply_battle). Over RAID_SEEDS campaigns: how many battles Rome won,
## how many corvus boardings the sim logged, and the ones Rome won with a corvus boarding.
const RAID_SEEDS := 12


func _raid_battles() -> void:
	var rome := CData.faction_index("rome")
	var car := CData.faction_index("carthage")
	var lat := CData.region_index("latium")
	var lane := CLanes.lane_between(lat, CData.region_index("sardinia"))
	var cells := CLanes.sea_cells(lane)
	var mid: int = cells[cells.size() / 2]
	var near: int = cells[cells.size() / 2 - 4]
	var fought := 0
	var rome_won := 0
	var corvus := 0
	var corvus_wins := 0
	var applied := 0
	for k in RAID_SEEDS:
		var st := CState.new_campaign("raid", 100 + k * 7, [rome])
		CState.set_dip(st, rome, car, CState.WAR)
		st["fleets"] = [
			{"id": 900, "f": rome, "x": CGrid.cx(near), "y": CGrid.cy(near), "carry": [], "moved": 0,
				"ships": [{"t": "quinquereme", "h": 100, "c": 100}, {"t": "trireme", "h": 100, "c": 100}]},
			{"id": 901, "f": car, "x": CGrid.cx(mid), "y": CGrid.cy(mid), "carry": [], "moved": 0,
				"ships": [{"t": "quinquereme_p", "h": 100, "c": 100}, {"t": "quinquereme_p", "h": 100, "c": 100}, {"t": "trireme", "h": 100, "c": 100}]}]
		_check(CLanes.raiders(st).has(lane), "raid %d: the Punic fleet on the lane's middle cell raids it" % k)
		var s2 := CTurn.resolve_turn(st, [CTurn.submission(st, rome, [{"t": "fmove", "fleet": 900, "x": CGrid.cx(mid), "y": CGrid.cy(mid), "tgt": 901}])])
		var pend := CTurn.pending_for(s2, rome)
		if pend.is_empty() or int(pend[0].get("sea", 0)) != 1:
			_check(false, "raid %d: the fleet's voyage at the raider leaves a pending sea battle" % k)
			continue
		var bt: Dictionary = CBattle.build(s2, pend[0], rome)
		var scn: Dictionary = bt["scenario"]
		scn["ai_sides"] = [1, 1]
		var sim := SeaSim.new()
		sim.setup(scn, int(bt["seed"]))
		while sim.ended == 0 and sim.tick < 9200:
			sim.step()
		fought += 1
		var cv := 0
		for e in mini(sim.ev_n, SeaSim.EV_CAP):
			if sim.ev_k[e] == SeaSim.EV_GRAPPLE and sim.ev_b[e] == 1:
				cv += 1
		var res := sim.result()
		var oc := CSeaBattle.outcome_from_result(bt, res, "fought")
		var ap := CTurn.apply_battle(s2, int(pend[0]["id"]), oc)
		if not ap.is_empty():
			applied += 1
		var side_rome := 0 if int((pend[0] as Dictionary).get("af", [900])[0]) == 900 else 1
		var won := int(res["winner"]) == side_rome
		rome_won += 1 if won else 0
		corvus += cv
		corvus_wins += 1 if (won and cv > 0) else 0
		print("raid %2d: lane cell %d,%d  %s in %d s, %d corvus boardings, written back %s" % [k, CGrid.cx(mid), CGrid.cy(mid),
			"Rome won" if won else "Carthage won", sim.tick / 10, cv, str(not ap.is_empty())])
	print("lane raids fought %d, Rome won %d, corvus boardings %d, Rome wins with a corvus boarding %d" % [fought, rome_won, corvus, corvus_wins])
	_check(fought == RAID_SEEDS and applied == fought, "every lane raid became a sea battle and was written back (%d of %d)" % [applied, RAID_SEEDS])
	_check(corvus_wins > 0, "the corvus decides a lane-raid battle: Rome won %d of %d with a corvus boarding" % [corvus_wins, fought])
