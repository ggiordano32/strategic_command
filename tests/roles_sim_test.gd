extends SceneTree
## Roles, step 2 (docs/design/battle_sim.md "Roles, step 2 (as built)"): the role behaviours in the sim.
## Set pieces, no AI unless said:
##   pistols   buccaneers (no musket rounds) attack musketeers: a man fires his brace in his first melee
##             rounds and never more than two shots between reloads; then the blade; spent front-rank men
##             change places with loaded men behind and reload there for 30 s (PIS_RELOAD).
##   grenades  grenadiers 15 m from a musket block: thrown on Auto, none on Hold; on Auto none at a
##             20-man party (not a block), thrown there on Use now.
##   caracole  pistoleers attack a musket line: they close, fire, ride back, reload and come again (no
##             charge); with the caracole on Hold they charge home.
##   batter    stone throwers told to batter (Use now, the walls; a building) take hit points off them.
##   drift     native bowmen in the Cover stance at a wood's edge: their men go into the trees; in the
##             Line stance they stay.
##   snapshot  the ability table, the pistols and a caracole under way survive snapshot / restore.
##   godot --headless --script res://tests/roles_sim_test.gd [-- --only=pistols|grenades|caracole|batter|drift|snapshot]

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const MapGen := preload("res://sim/mapgen.gd")
const Terrain := preload("res://sim/terrain.gd")
const M := 1024
const UP := 768
const DOWN := 256

var fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func _u(side: int, key: String, count: int, x: int, y: int, face: int, extra: Dictionary = {}) -> Dictionary:
	var d := Scenarios.unit(side, UT.index_of(key), count, x, y, face)
	for k in extra:
		d[k] = extra[k]
	return d


func _sc(units: Array, orders: Array, terr: Dictionary = {}) -> Dictionary:
	var sc := {"width_m": 300, "height_m": 300, "ai_sides": [], "units": units, "orders": orders}
	if not terr.is_empty():
		sc["terrain"] = terr
	return sc


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var only := ""
	for a in args:
		if a.begins_with("--only="):
			only = a.substr(7)
	if only == "" or only == "pistols":
		_pistols()
	if only == "" or only == "grenades":
		_grenades()
	if only == "" or only == "caracole":
		_caracole()
	if only == "" or only == "batter":
		_batter()
	if only == "" or only == "drift":
		_drift()
	if only == "" or only == "snapshot":
		_snapshot()
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	quit(0 if fails == 0 else 1)


# --------------------------------------------------------------- pistols ---

func _pistol_sc() -> Dictionary:
	return _sc([_u(0, "buccaneers", 60, 150, 190, UP, {"ammo_pct": 0}), _u(1, "musketeers", 100, 150, 150, DOWN, {"ammo_pct": 0})],
		[Scenarios.attack(0, 0, 1, 1)])


func _pistols() -> void:
	var sim := BattleSim.new()
	sim.setup(_pistol_sc(), 11)
	_check(sim.pis_on == 1, "pistols: pis_on with buccaneers")
	var b0: int = sim.u_slot_base[0]
	var n0: int = sim.u_count0[0]
	var shots := PackedInt32Array()
	shots.resize(n0)
	shots.fill(0)
	var prev := sim.s_pis.slice(b0, b0 + n0)
	var was_f := PackedInt32Array()
	was_f.resize(n0)
	was_f.fill(0)
	var too_many := 0
	var not_fighting := 0
	var blade_after := 0
	var reload_seen := 0
	var swapped_back := 0
	var first_shot_tick := -1
	for t in 1200:
		sim.step()
		for k in n0:
			var i := b0 + k
			var p: int = sim.s_pis[i]
			if p < prev[k]:
				shots[k] += prev[k] - p
				if first_shot_tick < 0:
					first_shot_tick = sim.tick
				if sim.state[i] != BattleSim.S_FIGHTING and was_f[k] == 0:
					not_fighting += 1  # (fighting before this tick or now: a man may step back on the tick he fired)
				if shots[k] > 2:
					too_many += 1
			elif p > prev[k]:
				shots[k] = 0  # (reloaded)
				reload_seen += 1
			if p == 0 and sim.s_prl[i] == 0 and sim.state[i] == BattleSim.S_FIGHTING:
				blade_after += 1
			if sim.s_prl[i] > 0 and sim.slot_of[i] >= sim.files_of(0) and sim.state[i] == BattleSim.S_FORMED:
				swapped_back += 1
			prev[k] = p
			was_f[k] = 1 if sim.state[i] == BattleSim.S_FIGHTING else 0
	print("pistols: %d shots, %d hits, %d kills, %d swaps, %d reloads; first shot tick %d; man-ticks blade after the brace %d, stepped back reloading %d" % [
		sim.stat_pis_shots, sim.stat_pis_hits, sim.stat_pis_kills, sim.stat_pis_swaps, sim.stat_pis_reloads,
		first_shot_tick, blade_after, swapped_back])
	_check(sim.stat_pis_shots > 20, "pistols: fired at contact (%d)" % sim.stat_pis_shots)
	_check(too_many == 0, "pistols: no man fired more than his brace between reloads (%d over)" % too_many)
	_check(not_fighting == 0, "pistols: fired only in melee (%d out of it)" % not_fighting)
	_check(blade_after > 0, "pistols: then the blade (a spent man fighting on)")
	_check(sim.stat_pis_swaps > 0, "pistols: spent front-rank men stepped back for loaded men (%d)" % sim.stat_pis_swaps)
	_check(swapped_back > 0, "pistols: a stepped-back man stands in a rear rank reloading")
	_check(sim.stat_pis_reloads > 0 and reload_seen > 0, "pistols: braces reloaded (%d)" % sim.stat_pis_reloads)
	# Hold: no pistols.
	var s2 := _pistol_sc()
	s2["orders"].append(BattleSim.make_ability_order(0, 0, UT.AB_PISTOL, UT.AB_HOLD))
	var sim2 := BattleSim.new()
	sim2.setup(s2, 11)
	for t in 600:
		sim2.step()
	_check(sim2.stat_pis_shots == 0 and sim2.ab_on == 1, "pistols: none on Hold (%d)" % sim2.stat_pis_shots)
	# The rotation's reload time.
	var rl := -1
	for k in n0:
		if sim.s_prl[b0 + k] > 0:
			rl = maxi(rl, sim.s_prl[b0 + k] - sim.tick)
	_check(rl <= BattleSim.PIS_RELOAD, "pistols: a reload ends within PIS_RELOAD (%d left)" % rl)


# -------------------------------------------------------------- grenades ---

func _gren_sc(n_def: int, orders: Array) -> Dictionary:
	return _sc([_u(0, "grenadiers", 60, 150, 170, UP), _u(1, "musketeers", n_def, 150, 155, DOWN, {"ammo_pct": 0})], orders)


func _gren_run(sc: Dictionary, ticks: int) -> int:
	var sim := BattleSim.new()
	sim.setup(sc, 5)
	var a0: int = sim.u_ammo[0]
	for t in ticks:
		sim.step()
	return a0 - sim.u_ammo[0]


func _grenades() -> void:
	var auto := _gren_run(_gren_sc(100, []), 300)
	var hold := _gren_run(_gren_sc(100, [BattleSim.make_ability_order(0, 0, UT.AB_GRENADE, UT.AB_HOLD)]), 300)
	var small := _gren_run(_gren_sc(20, []), 300)
	var now := _gren_run(_gren_sc(20, [BattleSim.make_ability_order(0, 0, UT.AB_GRENADE, UT.AB_NOW, 1)]), 300)
	print("grenades thrown in 30 s: Auto at a block %d, Hold %d, Auto at a 20-man party %d, Use now at it %d" % [auto, hold, small, now])
	_check(auto > 0, "grenades: thrown on Auto at a formed block (%d)" % auto)
	_check(hold == 0, "grenades: none on Hold (%d)" % hold)
	_check(small == 0, "grenades: none on Auto at a party too small for a block (%d)" % small)
	_check(now > 0, "grenades: thrown on Use now at the party (%d)" % now)


# -------------------------------------------------------------- caracole ---

func _car_sc(orders: Array) -> Dictionary:
	return _sc([_u(0, "pistoleers", 60, 150, 250, UP), _u(1, "musketeers", 100, 150, 130, DOWN, {"ammo_pct": 0})],
		[Scenarios.attack(0, 0, 1, 1)] + orders)


func _caracole() -> void:
	var sim := BattleSim.new()
	sim.setup(_car_sc([]), 7)
	_check(sim.car_on == 1, "caracole: car_on with pistoleers")
	var seq: Array[int] = []
	var charged := 0
	var far_back := 0
	var d_fire := -1
	for t in 2400:
		sim.step()
		var ph: int = sim.u_car[0]
		if seq.is_empty() or seq[seq.size() - 1] != ph:
			seq.append(ph)
			if ph == 2 and d_fire < 0:
				d_fire = FM_len(sim.u_cx[0] - sim.u_cx[1], sim.u_cy[0] - sim.u_cy[1])
		if sim.u_charge[0] != 0:
			charged += 1
		if ph == 3:
			far_back = maxi(far_back, FM_len(sim.u_cx[0] - sim.u_cx[1], sim.u_cy[0] - sim.u_cy[1]))
	var txt: Array[String] = []
	for p in seq:
		txt.append(str(p))
	print("caracole: phases %s; %d passes fired, %d rides back; volley at %d m, back to %d m; charging ticks %d; musketeers lost %d" % [
		" ".join(txt.slice(0, 16)), sim.stat_car_volleys, sim.stat_car_back, d_fire / M, far_back / M, charged,
		sim.u_count0[1] - sim.u_alive[1]])
	_check(sim.stat_car_volleys >= 2, "caracole: at least two passes fired (%d)" % sim.stat_car_volleys)
	_check(sim.stat_car_back >= 2, "caracole: rode back after firing (%d)" % sim.stat_car_back)
	_check(seq.size() >= 4 and seq[0] == 1 and seq[1] == 2 and seq[2] == 3 and seq[3] == 1, "caracole: close, ride back, reload, again (%s)" % " ".join(txt))
	_check(charged == 0, "caracole: no charge on Auto (%d ticks)" % charged)
	_check(far_back > d_fire, "caracole: back further than it fired from (%d > %d m)" % [far_back / M, d_fire / M])
	# Hold: a charge.
	var sim2 := BattleSim.new()
	sim2.setup(_car_sc([BattleSim.make_ability_order(0, 0, UT.AB_CARACOLE, UT.AB_HOLD)]), 7)
	var ch2 := 0
	for t in 900:
		sim2.step()
		if sim2.u_charge[0] != 0:
			ch2 += 1
	_check(ch2 > 0 and sim2.stat_car_back == 0, "caracole: on Hold the attack is a charge (%d ticks charging)" % ch2)


static func FM_len(dx: int, dy: int) -> int:
	return int(sqrt(float(dx) * dx + float(dy) * dy))


# ---------------------------------------------------------------- batter ---

func _batter() -> void:
	var sc := Scenarios.siege_test(32, 2, 1, MapGen.PAL_DRY, Terrain.K_FLAT)
	sc["ai_sides"] = []
	sc["orders"] = []
	sc["deploy_zones"] = []
	var probe := BattleSim.new()
	probe.setup(sc, 3)
	var stone := -1
	for u in probe.n_units:
		if probe.u_side[u] != probe.city_def and UT.base_of(probe.u_type[u]) == UT.STONE and stone < 0:
			stone = u
	_check(stone >= 0, "batter: an attacking stone thrower battery")
	if stone < 0:
		return
	_check(BattleSim.ability_refusal(probe, stone, UT.AB_BATTER, UT.AB_NOW) == "", "batter: the stone throwers have it")
	var sg := probe.batter_pick(stone)
	_check(sg >= 0, "batter: a stretch to batter")
	# Walls (target -1: its choice).
	var s1 := sc.duplicate(true)
	s1["orders"] = [BattleSim.make_ability_order(0, stone, UT.AB_BATTER, UT.AB_NOW, -1)]
	var sim := BattleSim.new()
	sim.setup(s1, 3)
	var hp0: int = sim.ws_hp[sg] if sg >= 0 else 0
	for t in 2400:
		sim.step()
	var lost: int = hp0 - sim.ws_hp[sg] if sg >= 0 else 0
	print("batter: walls: stretch %d lost %d of %d hit points (%d shots, breached %d)" % [sg, lost, hp0, sim.stat_wall_shots, sim.ws_state[sg]])
	_check(lost > 0, "batter: the batter order moved the stretch's hit points (%d)" % lost)
	# A building: the nearest one of the town 70-250 m from the battery.
	var bb := -1
	var bd := 0
	for b in probe.ob_state.size():
		if probe.ob_hp0[b] <= 0:
			continue
		var a := probe.ob_aim(b)
		var d := FM_len(a.x - probe.u_cx[stone], a.y - probe.u_cy[stone])
		if d >= 70 * M and d <= 250 * M and (bb < 0 or d < bd):
			bb = b
			bd = d
	_check(bb >= 0, "batter: a building in reach")
	if bb < 0:
		return
	var s2 := sc.duplicate(true)
	s2["orders"] = [BattleSim.make_ability_order(0, stone, UT.AB_BATTER, UT.AB_NOW, -2 - bb)]
	var sim2 := BattleSim.new()
	sim2.setup(s2, 3)
	for t in 2400:
		sim2.step()
	var blost: int = sim2.ob_hp0[bb] - sim2.ob_hp[bb]
	print("batter: building %d at %d m lost %d of %d (%d shots at it, fallen %d)" % [bb, bd / M, blost, sim2.ob_hp0[bb], sim2.stat_bld_shots, sim2.ob_state[bb]])
	_check(sim2.stat_bld_shots > 0 and (blost > 0 or sim2.ob_state[bb] != 0), "batter: shots at the building took hit points off it")


# ----------------------------------------------------------------- drift ---

func _drift_run(stance: int) -> Array:
	var terr := {"kind": Terrain.K_FLAT, "woods": [[150, 120, 60, 18, 2]]}
	var orders: Array = []
	if stance >= 0:
		orders.append({"tick": 0, "type": BattleSim.ORDER_STANCE, "unit": 0, "stance": stance})
	var sc := _sc([_u(0, "native_bowmen", 80, 150, 141, UP), _u(1, "musketeers", 100, 150, 30, DOWN, {"ammo_pct": 0})],
		orders, terr)
	var sim := BattleSim.new()
	sim.setup(sc, 9)
	var n0 := _in_woods(sim, 0)
	for t in 400:
		sim.step()
	return [n0, _in_woods(sim, 0), sim.stat_skd_men, sim.skd_on]


func _in_woods(sim, u: int) -> int:
	var n := 0
	var base: int = sim.u_slot_base[u]
	for s in sim.u_alive[u]:
		var i: int = sim.slot_soldier[base + s]
		if (sim.veg_bits(sim.pos_x[i], sim.pos_y[i]) & MapGen.V_DENS) != 0:
			n += 1
	return n


func _drift() -> void:
	var cov := _drift_run(-1)
	var line := _drift_run(BattleSim.STANCE_LINE)
	print("drift: bowmen in the trees, Cover stance %d -> %d (%d places drawn in), Line stance %d -> %d" % [
		cov[0], cov[1], cov[2], line[0], line[1]])
	_check(int(cov[3]) == 1, "drift: skd_on with woods and skirmishers")
	_check(int(cov[1]) > int(cov[0]) + 10, "drift: Cover stance men into the trees (%d -> %d)" % [cov[0], cov[1]])
	_check(int(line[1]) <= int(line[0]) + 2, "drift: Line stance stays out (%d -> %d)" % [line[0], line[1]])


# -------------------------------------------------------------- snapshot ---

func _snapshot() -> void:
	for kind in ["pistols", "caracole"]:
		var sc := _pistol_sc() if kind == "pistols" else _car_sc([BattleSim.make_ability_order(5, 0, UT.AB_PISTOL, UT.AB_HOLD)])
		if kind == "pistols":
			sc["orders"].append(BattleSim.make_ability_order(400, 0, UT.AB_PISTOL, UT.AB_HOLD))
			sc["orders"].append(BattleSim.make_ability_order(500, 0, UT.AB_PISTOL, UT.AB_AUTO))
		var a := BattleSim.new()
		a.setup(sc, 21)
		var cut := 450 if kind == "pistols" else 380
		for t in cut:
			a.step()
		var blob := a.snapshot()
		var abs0 := a.u_abs.duplicate()
		var car0: int = a.u_car[0]
		for t in 600:
			a.step()
		var h_a := a.state_hash()
		var b := BattleSim.new()
		b.setup(sc, 21)
		var ok := b.restore(blob)
		_check(ok, "snapshot %s: restore" % kind)
		_check(b.u_abs == abs0 and b.u_car[0] == car0, "snapshot %s: the ability table and the caracole state restored" % kind)
		for t in 600:
			b.step()
		_check(b.state_hash() == h_a, "snapshot %s: same hash after restore (%08x / %08x)" % [kind, b.state_hash(), h_a])
		var c := BattleSim.new()
		c.setup(sc, 21)
		for t in cut + 600:
			c.step()
		_check(c.state_hash() == h_a, "snapshot %s: repeat run identical" % kind)
		print("snapshot %s: cut at %d (caracole phase %d, ab_on %d), hash %08x after 600 more ticks on both" % [kind, cut, car0, a.ab_on, h_a])
