extends SceneTree
## Ambush battles (docs/design/campaign_rules.md "Ambush battles (as built, 2026-11-01)"), headless:
##   godot --headless --script res://tests/ambush_test.gd
## A West field battle where the Spanish lead army is on a forced march (or moved into the region this turn) and
## the Itza attack it: the "ambush" key, the defenders as a column along the axis facing along it, every attacker
## 70 m or more off the axis, the attackers' zone two rects on opposite sides of the strip, no zone rect holding an
## enemy unit, the same scenario twice from the same state, a plain field battle laid out as before; the zone
## helper (grouped flank boxes, cuts round enemy units), an east / west approach, the sim leaving the column
## alone at tick 0. Exits 0 on success, 1 on failure.

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CRules := preload("res://campaign/crules.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CBattle := preload("res://campaign/cbattle.gd")
const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")

const SPANISH := ["lancers", "musketeers", "musketeers", "pikemen", "pikemen", "cutlass", "wagon", "general", "pikemen"]
const ITZA := ["warriors", "warriors", "holcan", "native_bowmen", "native_bowmen", "warriors"]

var _ok := true


func _check(c: bool, what: String) -> void:
	print(("PASS " if c else "FAIL ") + what)
	if not c:
		_ok = false


func _initialize() -> void:
	CData.use_pack("west")
	_zones_unit()
	_ambush_battle()
	_plain_battle()
	print("RESULT: ", "PASS" if _ok else "FAIL")
	quit(0 if _ok else 1)


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


func _cell_at_d(c: int, d: int) -> int:
	for dy in range(-d, d + 1):
		for dx in range(-d, d + 1):
			var k := CGrid.at(CGrid.cx(c) + dx, CGrid.cy(c) + dy)
			if k >= 0 and CGrid.passable(k) and CGrid.cheb(k, c) == d and CGrid.site_region(k) < 0:
				return k
	return -1


## The state: the Spanish army (maybe caught on the march) and the Itza army that attacks it; the battle built
## with the Itza as the human.
func _battle(forced: bool, moved: bool, app: int) -> Array:
	var ns := CData.faction_index("new_spain")
	var iz := CData.faction_index("itza")
	var st := CState.new_campaign("t", 91, [iz], {}, [], "west")
	st["armies"] = []
	st["settings"]["deploy_time"] = 30
	var site := CGrid.site(CData.region_index("havana"))
	var dc := _cell_at_d(site, 4)
	var d := _put(st, ns, dc, SPANISH)
	if forced:
		d["stance"] = CData.ST_FORCED
	if moved:
		d["moved"] = 1
		d["from"] = CGrid.region(_cell_at_d(dc, 3)) if CGrid.region(_cell_at_d(dc, 3)) != int(d["r"]) else -1
	var a := _put(st, iz, _cell_at_d(dc, 2), ITZA)
	var b := CRules.start_field_battle(st, int(d["r"]), [a], [d])
	b["x"] = CGrid.cx(dc)
	b["y"] = CGrid.cy(dc)
	b["app"] = app
	return [st, b, iz]


func _in_rect(z: Array, x: int, y: int) -> bool:
	return x >= int(z[2]) and x <= int(z[4]) and y >= int(z[3]) and y <= int(z[5])


func _ambush_battle() -> void:
	var r1 := _battle(true, false, 4)
	var st: Dictionary = r1[0]
	var b: Dictionary = r1[1]
	var iz: int = r1[2]
	_check(CBattle.is_ambush(st, b), "a forced-march lead defender is an ambush")
	var built := CBattle.build(st, b, iz)
	var sc: Dictionary = built["scenario"]
	_check(sc.has("ambush") and int(sc["ambush"]) == int(built["sim_side"][1]), "the scenario carries the ambush key (sim side %s)" % str(sc.get("ambush")))
	var w := int(sc["width_m"])
	var h := int(sc["height_m"])
	_check(h / 2 > 0 and w >= 560, "the map is %d x %d m" % [w, h])
	var ds := int(sc["ambush"])
	var min_a := 1 << 30
	var worst_d := 0
	var along_ok := true
	var n_d := 0
	for ud in sc["units"]:
		var dy := absi(int(ud["y_m"]) - h / 2)
		if int(ud["side"]) == ds:
			n_d += 1
			worst_d = maxi(worst_d, dy)
			if int(ud["facing"]) != Scenarios.FACE_RIGHT and int(ud["facing"]) != Scenarios.FACE_LEFT:
				along_ok = false
		else:
			min_a = mini(min_a, dy)
	_check(n_d == SPANISH.size() and worst_d <= 40, "the %d defenders stand within 40 m of the axis (worst %d m)" % [n_d, worst_d])
	_check(along_ok, "the column faces along the axis")
	_check(min_a >= 70, "every attacker is 70 m or more off the axis (nearest %d m)" % min_a)
	var zones: Array = sc["deploy_zones"]
	var att_z: Array = []
	var def_z: Array = []
	for z in zones:
		if int(z[0]) == ds:
			def_z.append(z)
		else:
			att_z.append(z)
	_check(def_z.size() == 1 and int(def_z[0][3]) == h / 2 - 40 and int(def_z[0][5]) == h / 2 + 40 and int(def_z[0][2]) == 0 and int(def_z[0][4]) == w,
		"the defenders' zone is the strip along the whole width (%s)" % str(def_z))
	var north := 0
	var south := 0
	for z in att_z:
		if int(z[5]) <= h / 2 - 70:
			north += 1
		if int(z[3]) >= h / 2 + 70:
			south += 1
	_check(att_z.size() == 2 and north == 1 and south == 1, "the attackers' zone is two rects on opposite sides of the strip")
	var clean := true
	for ud in sc["units"]:
		for z in zones:
			if int(z[0]) != int(ud["side"]) and _in_rect(z, int(ud["x_m"]), int(ud["y_m"])):
				clean = false
	_check(clean, "no zone rect holds an enemy unit")
	var built2 := CBattle.build(st, b, iz)
	_check(str(built2) == str(built), "the same state builds the same scenario twice")
	_check(not str(CBattle.build(st, b, -1)["scenario"]["units"]).is_empty(), "a both-AI build works")
	# Moved this turn counts too; a unit that did not move and is not forced does not.
	var r2 := _battle(false, true, 4)
	_check(CBattle.is_ambush(r2[0], r2[1]) == (int(CState.army(r2[0], int(r2[1]["def"][0]))["from"]) >= 0), "a defender that moved in this turn is an ambush")
	var r3 := _battle(false, false, 4)
	_check(not CBattle.is_ambush(r3[0], r3[1]), "a defender standing still is not")
	# East approach: the attackers in two lines, one each side.
	var r4 := _battle(true, false, 2)
	var sc4: Dictionary = CBattle.build(r4[0], r4[1], r4[2])["scenario"]
	var h4 := int(sc4["height_m"])
	var nn := 0
	var ss := 0
	for ud in sc4["units"]:
		if int(ud["side"]) != int(sc4["ambush"]):
			if int(ud["y_m"]) < h4 / 2:
				nn += 1
			else:
				ss += 1
	_check(nn > 0 and ss > 0, "an east approach puts attackers on both sides of the column (%d north, %d south)" % [nn, ss])
	# A northern approach puts them all north.
	var r5 := _battle(true, false, 0)
	var sc5: Dictionary = CBattle.build(r5[0], r5[1], r5[2])["scenario"]
	var all_n := true
	for ud in sc5["units"]:
		if int(ud["side"]) != int(sc5["ambush"]) and int(ud["y_m"]) >= int(sc5["height_m"]) / 2:
			all_n = false
	_check(all_n, "a northern approach puts every attacker north of the column")
	# The sim: the ambushed AI side stays as placed at tick 0 (the human attacker is side 0 here).
	var sim := BattleSim.new()
	sim.setup(sc, int(built["seed"]))
	var moved := 0
	for u in sim.n_units:
		if u_side_is(sim, u, ds):
			if absi(sim.u_ax[u] - int(sc["units"][u]["x_m"]) * 1024) > 1024 or absi(sim.u_ay[u] - int(sc["units"][u]["y_m"]) * 1024) > 1024:
				moved += 1
	_check(sim.phase == BattleSim.PHASE_DEPLOY and moved == 0, "the AI does not redeploy the ambushed column (%d moved)" % moved)


func u_side_is(sim, u: int, s: int) -> bool:
	return sim.u_side[u] == s


func _plain_battle() -> void:
	var r := _battle(false, false, 4)
	var built := CBattle.build(r[0], r[1], r[2])
	var sc: Dictionary = built["scenario"]
	_check(not sc.has("ambush"), "a plain field battle has no ambush key")
	_check(str(sc["deploy_zones"]) == str(Scenarios.field_zones(sc)), "its zones are field_zones' output")
	var clean := true
	for ud in sc["units"]:
		for z in sc["deploy_zones"]:
			if int(z[0]) != int(ud["side"]) and _in_rect(z, int(ud["x_m"]), int(ud["y_m"])):
				clean = false
	_check(clean, "and hold no enemy unit")


func _zones_unit() -> void:
	# Three flank units in a pile become one box; an enemy inside the band is cut out.
	var us: Array = []
	for k in 5:
		us.append({"side": 0, "x_m": 100 + 80 * k, "y_m": 450})
	for y in [100, 130, 160]:
		us.append({"side": 0, "x_m": 45, "y_m": y})
	us.append({"side": 1, "x_m": 280, "y_m": 160})
	us.append({"side": 1, "x_m": 300, "y_m": 420})
	var sc := {"width_m": 560, "height_m": 560, "units": us}
	var z := Scenarios.field_zones(sc)
	var s0 := 0
	var boxed := true
	for q in z:
		if int(q[0]) == 0:
			s0 += 1
	for q in z:
		if int(q[0]) == 0 and _in_rect(q, 300, 420):
			boxed = false
	_check(boxed, "a rect is cut so the enemy standing in the band is outside it")
	var flank := 0
	for q in z:
		if int(q[0]) == 0 and int(q[2]) == 5 and int(q[3]) == 60:
			flank += 1
	_check(flank == 1, "three flank units get one box (%d side-0 rects in all)" % s0)
