extends SceneTree
## Beaches and cliffs on the overworld (map_view.gd "beaches and cliffs"; owner 2026-10-22: "we should have beaches
## shown on the overworld so we know where we can and can't land a ship"). For both packs: every coast cell where
## CFleet.land_ok can hold (passable, open sea beside it) has a beach segment, every other coast cell has a cliff
## segment and no beach, no cell has both; the West's landing reach (MapOverlay.set_landing) lights exactly the
## land_ok beaches beside a sea cell the loaded fleet reaches this turn, and nothing for an empty fleet.
## godot --headless --path . -s tests/beach_test.gd
const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CFleet := preload("res://campaign/cfleet.gd")
const MapView := preload("res://game/campaign/map_view.gd")
const MapOverlay := preload("res://game/campaign/map_overlay.gd")
const PackView := preload("res://game/campaign/pack_view.gd")
var fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)


func _initialize() -> void:
	for pack in ["rome", "west"]:
		_pack(pack)
	print("beach_test: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(1 if fails > 0 else 0)


func _open_sea_beside(c: int) -> bool:
	for k in 8:
		var j := CGrid.at(CGrid.cx(c) + CGrid.DX[k], CGrid.cy(c) + CGrid.DY[k])
		if j >= 0 and CGrid.region(j) == -1 and (CFleet.is_sea(j) if CData.ships_on() else true):
			return true
	return false


func _any_sea_beside(c: int) -> bool:
	for k in 8:
		var j := CGrid.at(CGrid.cx(c) + CGrid.DX[k], CGrid.cy(c) + CGrid.DY[k])
		if j >= 0 and CGrid.region(j) == -1:
			return true
	return false


func _pack(pack: String) -> void:
	PackView.use_pack(pack)
	var st: Dictionary = CState.new_campaign("B", 5, [0], {}, [], pack)
	MapView.geometry_lines()
	var landable := 0
	var cliffs := 0
	var both := 0
	var miss_beach := 0
	var miss_cliff := 0
	var stray := 0
	var unseen := MapView.coast_unseen()
	for c in CGrid.count():
		var beach := MapView.coast_drawn(c, 1)
		var cliff := MapView.coast_drawn(c, 2)
		if beach and cliff:
			both += 1
		if CGrid.region(c) == -1:
			if beach or cliff:
				stray += 1
			continue
		var coast := _any_sea_beside(c)
		if unseen.has(c):
			continue   # (a cell of the grid that the map draws as sea: nothing to dress)
		if CFleet.land_ok(st, 0, c) and _open_sea_beside(c):
			landable += 1
			if not beach:
				miss_beach += 1
		elif coast and not (CGrid.passable(c) and _open_sea_beside(c)):
			cliffs += 1
			if not cliff or beach:
				miss_cliff += 1
		if not coast and (beach or cliff):
			stray += 1
	# (land_ok of faction 0 may refuse a few cells the geometric rule allows: those cells still have beaches)
	var counts := MapView.coast_counts()
	print("%s: %d grid coast cells the map draws as sea, %d beach cells drawn (%d land_ok coast cells of faction 0), %d cliff cells drawn (%d by the rule), %d runs, built in %.0f ms" % [
		pack, unseen.size(), counts[0], landable, counts[1], cliffs, counts[2], counts[3]])
	_check(unseen.size() <= 8, pack + ": only a few coast cells are undrawn land (%d)" % unseen.size())
	_check(landable > 100, pack + ": landing coast exists")
	_check(miss_beach == 0, pack + ": every landable coast cell has a beach (%d without)" % miss_beach)
	_check(miss_cliff == 0, pack + ": every other coast cell has cliffs and no beach (%d wrong)" % miss_cliff)
	_check(both == 0, pack + ": no cell is both beach and cliff (%d)" % both)
	_check(stray == 0, pack + ": nothing drawn off the coast (%d)" % stray)
	_check(int(counts[0]) >= landable, pack + ": beaches cover the landing coast")
	var empty := 0
	for c in MapView.beach_cells():
		if MapView.beach_points(c).size() < 1:
			empty += 1
	_check(empty == 0, pack + ": every beach cell has its points (%d without)" % empty)
	if pack == "west":
		_check(int(counts[1]) > 0, "west: cliffs exist")
		_landing(st)


func _landing(st: Dictionary) -> void:
	var fl := {}
	var f := 0
	for e in CFleet.fleets(st):
		fl = e
		f = int(e["f"])
		break
	_check(not fl.is_empty(), "west: a fleet to land from")
	if fl.is_empty():
		return
	var ov := MapOverlay.new()
	var rt := CFleet.reach(st, fl, 0)
	ov.set_sea_reach(rt)
	_check(not ov.set_landing(st, f, fl, {}) or ov.landing_cells.is_empty(), "an empty fleet lights nothing")
	(fl["carry"] as Array).append({"id": 99999, "f": f})
	var changed := ov.set_landing(st, f, fl, {})
	var want := PackedInt32Array()
	for c in CGrid.count():
		if MapView.beach_points(c).size() == 0 or not CFleet.land_ok(st, f, c):
			continue
		for k in 8:
			var j := CGrid.at(CGrid.cx(c) + CGrid.DX[k], CGrid.cy(c) + CGrid.DY[k])
			if j >= 0 and rt[j] == 0:
				want.append(c)
				break
	print("west: fleet ", int(fl["id"]), " lights ", ov.landing_cells.size(), " beaches (brute force ", want.size(), ")")
	_check(changed and ov.landing_cells.size() > 0, "a loaded fleet lights beaches")
	_check(ov.landing_cells == want, "the lit beaches are exactly the land_ok beaches beside the reach")
	for c in ov.landing_cells:
		_check(CFleet.landing_cell(st, f, fl, c) == c or CGrid.cheb(c, CFleet.cell(fl)) > 1, "a lit beach is a landing")
	(fl["carry"] as Array).clear()
	ov.set_landing(st, f, fl, {})
	_check(ov.landing_cells.is_empty(), "unloading unlights them")
	ov.free()
