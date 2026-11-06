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
##   countermarch  musketeers (4 ranks of 25) shoot a standing pike block 70 m off (docs/AI.md 44.2): an opening
##             full volley, then one rank every reload / 4 ticks in turn (the pointer walks the ranks), each man
##             once a reload; as many shots as on Hold (volleys); each rank volley frightens at CM_FEAR_PCT; Use
##             now rolls too; rodeleros charging home get the last volley within CM_CLOSE (Auto); an AI side at
##             Easy (CM_AUTO 0) volleys; snapshot / restore mid-drill; Rome and the riders have no countermarch.
##             The walk (2026-11-02): after each rank volley its men file to the rear of their files down the gaps
##             and the next rank steps up, so every man has stood in the front rank at a rank volley within the
##             first five; the shots as before; the footprint stays put; none walk on Hold, on the move or in a
##             melee; the stepped-back pistol men walk the same way.
##   pass      filtering through a friendly unit (docs/design/battle_sim.md "Filtering through a friendly unit (as
##             built, 2026-11-02)"): a musket line, a column and lancers ordered through a standing musket line,
##             and a musket line through standing lancers: no two men of the two units within 0.3 m during the pass
##             (they were inside one another before), the standing men step aside, after it nobody within 0.5 m
##             of another man and every man back in his own place (no slot changed hands), the pass at most 15 %
##             slower than the same move over clear ground; two lines marching shoulder to shoulder, and one
##             following 4 m behind another, never mix.
##   ai        the battle AI's Hold / Use now (docs/AI.md 39): grenadiers storming a walled town (AI, Average) Hold in
##             the approach, go up to the gate being hacked and are on Auto once it is down; put by a shut gate
##             they Use now at it; a mortar battery in a West town batters (Use now) a held building on the storm's
##             route, then Auto; Easy never gives an ability order.
##   native    the torch raiders (native siege, 2026-10-29): the grenade and batter abilities; their fire pots on Auto
##             none at a formed block, thrown on Use now; the batter's melee form at a walls-1 gate (Use now: they go
##             to its face and break it; Hold stops them); the siege AI (Average) in a walls-2 oppidum with no ram
##             batters the attacked gate with them (Use now) and it falls; Easy gives no ability order; Rome's rows
##             have neither. A second unit up a planted set (2026-11-01, the owner's "are the poles single use?"):
##             Itza warriors carry poles onto a walls-1 stretch and climb; then the second warriors, the bowmen
##             and the Holcan, each ordered onto the stretch, go up the planted poles and stand on the walkway;
##             the same with Spanish-era ladders and heavy infantry.
##   march     filtering always on (docs/design/battle_sim.md "Filtering always on (as built, 2026-11-06)";
##             tests/march_probe.gd): two musket lines marching side by side with their flank files 0.4 m apart keep
##             0.33 m between any two of their men and arrive as a lone line does; a column 0.3 m behind a line keeps
##             0.33 m; four companies crowding a town's streets to its plaza come under 0.25 m fewer than 1,500
##             man-ticks (2,966 before)
##   route     paths clear of the enemy (docs/design/battle_sim.md "Paths clear of the enemy (as built, 2026-11-06)";
##             tests/route_probe.gd): rodeleros ordered past a musket line's front go round out of its reach (a way
##             round planned, no man lost, arrived); a musket company sent into a house with an enemy company on the
##             plain way to its door goes round and gets in; an attack order on that line goes straight at it (no plan
##             round, the anchor within 3 m of the straight line until contact)
##   godot --headless --script res://tests/roles_sim_test.gd [-- --only=pistols|grenades|caracole|batter|drift|snapshot|ai|countermarch|native|pass|march|route]

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const MapGen := preload("res://sim/mapgen.gd")
const Terrain := preload("res://sim/terrain.gd")
const SiegeAI := preload("res://sim/siege_ai.gd")
const AIProfile := preload("res://sim/ai_profile.gd")
const FM := preload("res://sim/fixed_math.gd")
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
	if only == "" or only == "ai":
		_ai()
	if only == "" or only == "countermarch":
		_countermarch()
	if only == "" or only == "native":
		_native()
	if only == "" or only == "pass":
		_pass()
	if only == "" or only == "march":
		_march()
	if only == "" or only == "route":
		_route()
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
	_check(sim.rt_on == 1, "pistols: a stepped-back man walked to the rear down the gap (rt_on %d)" % sim.rt_on)
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


# -------------------------------------------------------------------- ai ---

## SIEGE_ARMY without its batteries, plus 60 grenadiers, against a level 2 town with walls 1; both AI at `skill`.
func _gren_siege_sc(skill: int) -> Dictionary:
	var att: Array = []
	for e in Scenarios.SIEGE_ARMY:
		if UT.stat(int(e[0]), "cls") != UT.CLS_ART:
			att.append(e.duplicate())
	att.append([UT.index_of("grenadiers"), 60])
	var dfn: Array = [[UT.HEAVY, 60], [UT.SPEAR, 60], [UT.ARCHER, 60], [UT.HEAVY, 100]]
	var city := {"seed": 32, "level": 2, "walls": 1, "bld": [1, 2, 4]}
	var terr := {"kind": Terrain.K_FLAT, "seed": 32 * 7 + 3, "forest": MapGen.PALETTE_FOREST[MapGen.PAL_DRY], "ground": MapGen.PAL_DRY}
	var sc: Dictionary = Scenarios.settlement(city, terr, att, dfn, 1, [0, 1], {})["scenario"]
	sc["ai_skill"] = [skill, skill]
	return sc


func _of_type(sim, side: int, key: String) -> int:
	for u in sim.n_units:
		if sim.u_side[u] == side and sim.u_type[u] == UT.index_of(key):
			return u
	return -1


func _put(sim, u: int, x: int, y: int) -> void:
	sim.u_ax[u] = x
	sim.u_ay[u] = y
	sim.u_dx[u] = x
	sim.u_dy[u] = y
	var base: int = sim.u_slot_base[u]
	for s in sim.u_alive[u]:
		var i: int = sim.slot_soldier[base + s]
		sim.pos_x[i] = x + sim.off_x[base + s]
		sim.pos_y[i] = y + sim.off_y[base + s]
	sim.u_dirty[u] = 1
	sim.u_settled[u] = 0
	sim._update_bounds()


## A mortar battery with the West attack list against a level 1 West town (walls 0); both AI at `skill`.
## Returns [building shots, a Use now at a building seen, back to Auto after, ability orders].
func _bld_run(skill: int) -> Array:
	var att: Array = []
	for e in Scenarios.WEST_ATT:
		att.append([UT.index_of(str(e[0])), int(e[1])])
	att.append([UT.index_of("mortar"), 12])
	var dfn: Array = []
	for e in Scenarios.WEST_DEF:
		dfn.append([UT.index_of(str(e[0])), int(e[1])])
	var terr := {"kind": Terrain.K_ROLLING, "seed": 12 * 7 + 3, "forest": MapGen.PALETTE_FOREST[MapGen.PAL_GREEN] + 20, "ground": MapGen.PAL_GREEN}
	var city := {"seed": 12, "level": 1, "walls": 0, "bld": [1, 2, 4], "plan": MapGen.CUL_LATIN, "coast": 1, "founder": MapGen.CUL_LATIN, "west": 1}
	var sc: Dictionary = Scenarios.settlement(city, terr, att, dfn, 1, [0, 1], {})["scenario"]
	sc["ai_skill"] = [skill, skill]
	var sim := BattleSim.new()
	sim.setup(sc, 91)
	var gu := _of_type(sim, 0, "mortar")
	var now_bld := false
	var back := false
	while sim.tick < 3000 and not back:  # (1500 ticks before the countermarch: the storm takes longer with it)
		sim.step()
		var st: int = sim.ability_state(gu, UT.AB_BATTER)
		if st == UT.AB_NOW and sim.u_abt[gu] <= -2:
			now_bld = true
		elif now_bld and st == UT.AB_AUTO:
			back = true
	return [sim.stat_bld_shots, now_bld, back, sim.stat_ab_orders]


func _ai() -> void:
	# Grenadiers in the approach and the assault (no battery: the foot hack at the gate).
	var sim := BattleSim.new()
	sim.setup(_gren_siege_sc(1), 77)
	var gu := _of_type(sim, 0, "grenadiers")
	var g := -1
	var held_app := 0
	var auto_ass := 0
	var near := 1 << 30
	var broke := -1
	while sim.tick < 2400:
		sim.step()
		g = sim.ai_gate[0]
		if g < 0:
			continue
		var st: int = sim.ability_state(gu, UT.AB_GRENADE)
		if sim.ai_phase[0] == SiegeAI.SP_APPROACH and st == UT.AB_HOLD:
			held_app += 1
		if sim.g_state[g] == BattleSim.GATE_CLOSED:
			var f: Vector2i = sim.gate_face(g)
			near = mini(near, FM_len(f.x - sim.u_cx[gu], f.y - sim.u_cy[gu]))
		elif broke < 0:
			broke = sim.tick
		if broke >= 0 and sim.tick > broke + 100 and st == UT.AB_AUTO:
			auto_ass += 1
	print("ai grenades: Hold in the approach %d ticks, nearest the shut gate %d m, gate down at %d, Auto after it %d ticks" % [
		held_app, near / M, broke, auto_ass])
	_check(held_app > 300 and near < 45 * M and broke > 0 and auto_ass > 0,
		"ai: grenadiers Hold in the approach, go up to the gate being hacked, Auto once it is down")
	# Put by the shut gate: Use now at it.
	var s2 := BattleSim.new()
	s2.setup(_gren_siege_sc(1), 77)
	var g2 := -1
	for t in 30:
		s2.step()
	g2 = s2.ai_gate[0]
	var gu2 := _of_type(s2, 0, "grenadiers")
	var ok_now := false
	var a0 := 0
	if g2 >= 0:
		var p: Vector2i = SiegeAI._gate_point(s2, g2, 18 * M, 0)
		_put(s2, gu2, p.x, p.y)
		a0 = s2.u_ammo[gu2]
		for t in 150:
			s2.step()
			if s2.ability_state(gu2, UT.AB_GRENADE) == UT.AB_NOW and s2.u_abt[gu2] == -2 - g2:
				ok_now = true
	var thrown: int = a0 - s2.u_ammo[gu2]
	print("ai grenades by the gate: Use now at it %s, %d thrown in 15 s" % [str(ok_now), thrown])
	_check(ok_now and thrown > 0, "ai: grenadiers by a shut gate Use now at it and throw")
	var s3 := BattleSim.new()
	s3.setup(_gren_siege_sc(0), 77)
	for t in 1200:
		s3.step()
	_check(s3.stat_ab_orders == 0, "ai: Easy gives no ability order to its grenadiers (%d)" % s3.stat_ab_orders)
	# The batter at a held building.
	var b1 := _bld_run(1)
	var b0 := _bld_run(0)
	print("ai batter: Average %d shots at buildings, Use now %s, back to Auto %s, %d ability orders; Easy %d shots, %d orders" % [
		b1[0], str(b1[1]), str(b1[2]), b1[3], b0[0], b0[3]])
	_check(b1[0] > 0 and b1[1] and b1[2], "ai: a mortar battery batters a held building on the storm's route (Use now), then Auto")
	_check(b0[0] == 0 and b0[3] == 0, "ai: Easy batters no building")


# ---------------------------------------------------------- countermarch ---

## 100 musketeers (25 files, 4 ranks) facing up at y 200, a block of 300 pikemen (side 1, no missiles) 70 m off;
## extra orders appended; side 1 the AI at `ai_skill` when >= 0.
func _cm_sc(orders: Array, ai_skill: int = -1) -> Dictionary:
	var sc := _sc([Scenarios.unit(0, UT.index_of("musketeers"), 100, 150, 200, UP, 25),
		Scenarios.unit(1, UT.index_of("w_pikemen"), 300, 150, 130, DOWN, 30)], orders)
	if ai_skill >= 0:
		sc["ai_sides"] = [0]
		sc["ai_skill"] = [ai_skill, ai_skill]
	return sc


## Run a countermarch set piece `ticks` ticks: per tick the shots fired; the rank pointer before each rank
## volley; the biggest fright jump the pikes took in one tick.
func _cm_run(sc: Dictionary, ticks: int) -> Dictionary:
	var sim := BattleSim.new()
	sim.setup(sc, 31)
	var shots := PackedInt32Array()
	var ranks_seen: Array[int] = []
	var rank_ticks: Array[int] = []
	var jump := 0
	var jump_r := 0
	var men_twice := 0
	var last := PackedInt32Array()
	last.resize(sim.u_count0[0])
	last.fill(-100000)
	var b0: int = sim.u_slot_base[0]
	for t in ticks:
		var sh0: int = sim.stat_shots
		var r0: int = sim.u_cmr[0] if sim.cm_on != 0 else -1
		var rk0: int = sim.stat_cm_rank
		var f0: int = sim.u_fright[1]
		var am := sim.ammo.slice(b0, b0 + sim.u_count0[0])
		sim.step()
		shots.append(sim.stat_shots - sh0)
		if sim.stat_cm_rank != rk0:
			ranks_seen.append(r0)
			rank_ticks.append(sim.tick)
		var jp: int = sim.u_fright[1] - f0 + 1  # (the decay of the tick)
		if rank_ticks.is_empty():
			jump = maxi(jump, jp)
		else:
			jump_r = maxi(jump_r, jp)
		for k in sim.u_count0[0]:
			if sim.ammo[b0 + k] < am[k]:
				if sim.tick - last[k] < sim.t_m_reload[sim.u_type[0]]:
					men_twice += 1
				last[k] = sim.tick
	return {"sim": sim, "shots": shots, "ranks": ranks_seen, "rank_ticks": rank_ticks, "jump": jump, "jump_r": jump_r, "twice": men_twice}


func _countermarch() -> void:
	var mus := UT.index_of("musketeers")
	_check((UT.abilities(mus) & (1 << UT.AB_ROLL)) != 0, "countermarch: musketeers have it")
	for key in ["pistoleers", "dragoons", "light_gun", "buccaneers", "w_pikemen"]:
		_check((UT.abilities(UT.index_of(key)) & (1 << UT.AB_ROLL)) == 0, "countermarch: %s have none" % key)
	for ty in UT.ROME_N:
		if (UT.abilities(ty) & (1 << UT.AB_ROLL)) != 0:
			_check(false, "countermarch: Rome row %d has it" % ty)
	var reload := UT.stat(mus, "m_reload")
	var step := (reload + 3) / 4
	# (2026-11-06, suppression's second pass: the pin now lasts while the line reloads, so the pike block, pinned and
	# losing morale, broke before 900 ticks with Hold and the line fired six volleys instead of seven; the countermarch's
	# own rule is checked as built, suppression off for these battles and _cm_walk's: BattleSim.SUPP_FORCE.)
	(BattleSim as GDScript).set("SUPP_FORCE", 0)
	var auto := _cm_run(_cm_sc([]), 900)
	var sa: BattleSim = auto["sim"]
	var hold := _cm_run(_cm_sc([BattleSim.make_ability_order(0, 0, UT.AB_ROLL, UT.AB_HOLD)]), 900)
	var sh: BattleSim = hold["sim"]
	var now := _cm_run(_cm_sc([BattleSim.make_ability_order(5, 0, UT.AB_ROLL, UT.AB_NOW)]), 900)
	var sn: BattleSim = now["sim"]
	var ranks: Array[int] = auto["ranks"]
	var rt: Array[int] = auto["rank_ticks"]
	var gaps: Array[int] = []
	for k in range(1, rt.size()):
		gaps.append(rt[k] - rt[k - 1])
	var walk := true
	for k in ranks.size():
		if ranks[k] != k % 4:
			walk = false
	var vol_a: Array[int] = []
	for v in (auto["shots"] as PackedInt32Array):
		if v > 0:
			vol_a.append(v)
	var vol_h: Array[int] = []
	for v in (hold["shots"] as PackedInt32Array):
		if v > 0:
			vol_h.append(v)
	print("countermarch: cm_on %d; Auto: %d rank volleys (pointer %s), gaps %s, full %d, fired %s, shots %d, fright jump %d / %d (%d rank frights); Hold: volleys %s, shots %d, jump %d; Use now: %d rank, %d full, shots %d" % [
		sa.cm_on, sa.stat_cm_rank, str(ranks.slice(0, 9)), str(gaps.slice(0, 8)), sa.stat_cm_full, str(vol_a.slice(0, 7)),
		sa.stat_shots, auto["jump"], auto["jump_r"], sa.stat_cm_fright, str(vol_h.slice(0, 5)), sh.stat_shots, hold["jump"],
		sn.stat_cm_rank, sn.stat_cm_full, sn.stat_shots])
	_check(sa.cm_on == 1, "countermarch: cm_on with musketeers")
	_check(vol_a.size() > 0 and vol_a[0] >= 90, "countermarch: the opening is a full volley (%s)" % str(vol_a.slice(0, 1)))
	_check(sa.stat_cm_rank >= 16, "countermarch: rank volleys fired (%d)" % sa.stat_cm_rank)
	_check(walk, "countermarch: the pointer walks the ranks 0, 1, 2, 3, 0 ... (%s)" % str(ranks.slice(0, 9)))
	var even := gaps.size() > 4
	for g in gaps:
		if g != step:
			even = false
	_check(even, "countermarch: a rank volley every reload / ranks = %d ticks (%s)" % [step, str(gaps.slice(0, 8))])
	var rank_ok := vol_a.size() > 4
	for k in range(1, vol_a.size()):
		if vol_a[k] > 25:
			rank_ok = false
	_check(rank_ok, "countermarch: a rank volley is one rank (<= 25 shots) (%s)" % str(vol_a.slice(0, 7)))
	_check(int(auto["twice"]) == 0, "countermarch: no man fires twice within a reload (%d)" % int(auto["twice"]))
	# (Over the same ticks the rolling fire is behind by at most the ranks still to fire of its last cycle.)
	_check(sh.stat_shots - sa.stat_shots >= 0 and sh.stat_shots - sa.stat_shots <= 75, "countermarch: shots as many as by volleys (%d / %d)" % [sa.stat_shots, sh.stat_shots])
	var per_cycle := 0
	for k in range(1, 5):
		per_cycle += vol_a[k]
	_check(per_cycle == vol_h[1], "countermarch: a cycle of four ranks fires a volley's shots (%d / %d)" % [per_cycle, vol_h[1]])
	_check(sh.stat_cm_rank == 0 and vol_h.size() >= 7 and vol_h[1] >= 80, "countermarch: Hold gives volleys (%s)" % str(vol_h.slice(0, 5)))
	var fear := UT.stat(mus, "m_fear")
	_check(int(auto["jump_r"]) == fear * BattleSim.CM_FEAR_PCT / 100 and int(auto["jump"]) == fear, "countermarch: a rank volley frightens at CM_FEAR_PCT (%d), the opening at m_fear (%d)" % [int(auto["jump_r"]), int(auto["jump"])])
	_check(sa.stat_cm_fright >= sa.stat_cm_rank - 2 and sa.stat_cm_fright > 0, "countermarch: every rank volley frightened (%d of %d)" % [sa.stat_cm_fright, sa.stat_cm_rank])
	_check(int(hold["jump"]) == fear, "countermarch: a volley frightens at m_fear (%d)" % int(hold["jump"]))
	_check(sn.stat_cm_rank >= 16, "countermarch: Use now rolls (%d)" % sn.stat_cm_rank)
	_cm_walk(auto, hold)  # (its own battle is the Auto one again: suppression off there too)
	(BattleSim as GDScript).set("SUPP_FORCE", -1)
	# The last volley: rodeleros 75 m off take the opening and the rolling fire, then charge the line.
	var lsc := _sc([Scenarios.unit(0, mus, 100, 150, 200, UP, 25), Scenarios.unit(1, UT.index_of("rodeleros"), 200, 150, 120, DOWN, 40)],
		[Scenarios.attack(240, 1, 0, 1)])
	# (2026-11-06, suppression: the rodeleros charging into the rolling fire are suppressed (no running) and pinned (a
	# crawl), so the scripted charge reaches the line at a walk and the last volley met them in the melee (0 m); the
	# countermarch's own rule is checked as built, suppression off for this battle: BattleSim.SUPP_FORCE.)
	(BattleSim as GDScript).set("SUPP_FORCE", 0)
	var ls := BattleSim.new()
	ls.setup(lsc, 41)
	(BattleSim as GDScript).set("SUPP_FORCE", -1)
	var last_d := -1
	var full0 := 0
	var walk_melee := 0
	for t in 700:
		var fl: int = ls.stat_cm_full
		var wf: int = ls.stat_cm_files
		var engaged: bool = ls.u_contact[0] != 0 or ls.u_fighting[0] > 0
		ls.step()
		if engaged and ls.stat_cm_files != wf:
			walk_melee += 1
		if ls.tick == 240:
			full0 = ls.stat_cm_full
		if ls.stat_cm_full > fl and ls.tick > 240 and last_d < 0:
			last_d = ls._unit_dist(0, 1)
	print("countermarch: the last volley at %d m (%d rank volleys, %d full)" % [last_d / M, ls.stat_cm_rank, ls.stat_cm_full])
	_check(full0 >= 1 and last_d >= 0 and last_d <= BattleSim.CM_CLOSE, "countermarch: the last volley within CM_CLOSE (%d m)" % (last_d / M))
	_check(walk_melee == 0 and ls.stat_cm_files > 0, "countermarch: men walk before the charge (%d), none in the melee (%d)" % [ls.stat_cm_files, walk_melee])
	# On the move: a line ordered forward mid-drill fires no rank volley and nobody walks while it moves.
	var msc := _cm_sc([BattleSim.make_move_order(200, 0, 150 * M, 185 * M, UP, 25 * UT.stat(mus, "file_sp"), 0)])
	var ms := BattleSim.new()
	ms.setup(msc, 31)
	var walk_moving := 0
	for t in 500:
		var wf2: int = ms.stat_cm_files
		ms.step()
		if ms.u_moved[0] != 0 and ms.stat_cm_files != wf2:
			walk_moving += 1
	_check(walk_moving == 0, "countermarch: nobody walks to the rear while the line moves (%d)" % walk_moving)
	# An AI side at Easy (CM_AUTO 0) volleys; at Average it rolls (and counts it once).
	for sk in [0, 1]:
		var ai := BattleSim.new()
		var asc := _cm_sc([], sk)
		ai.setup(asc, 31)
		for t in 600:
			ai.step()
		var cnt: int = ai.stat_aic[AIProfile.C_CM]
		print("countermarch: AI skill %d: %d rank volleys, %d volleys, counted %d" % [sk, ai.stat_cm_rank, ai.stat_volleys, cnt])
		if sk == 0:
			_check(ai.stat_cm_rank == 0 and ai.stat_volleys > 0 and cnt == 0, "countermarch: Easy volleys")
		else:
			_check(ai.stat_cm_rank > 0 and cnt == 1, "countermarch: Average rolls, counted once (%d)" % cnt)
	# Snapshot / restore mid-drill.
	var sc := _cm_sc([BattleSim.make_ability_order(300, 0, UT.AB_ROLL, UT.AB_HOLD), BattleSim.make_ability_order(420, 0, UT.AB_ROLL, UT.AB_AUTO)])
	var a := BattleSim.new()
	a.setup(sc, 21)
	for t in 250:
		a.step()
	var blob := a.snapshot()
	var cmr0: int = a.u_cmr[0]
	for t in 500:
		a.step()
	var h_a := a.state_hash()
	var b := BattleSim.new()
	b.setup(sc, 21)
	_check(b.restore(blob) and b.u_cmr[0] == cmr0, "countermarch: snapshot restores the drill")
	for t in 500:
		b.step()
	_check(b.state_hash() == h_a, "countermarch: same hash after restore (%08x / %08x)" % [b.state_hash(), h_a])
	# Rome: nothing allocated or hashed.
	var rs := BattleSim.new()
	rs.setup(_sc([Scenarios.unit(0, UT.index_of("archer"), 60, 150, 200, UP), Scenarios.unit(1, UT.index_of("heavy"), 80, 150, 140, DOWN)], []), 5)
	for t in 100:
		rs.step()
	_check(rs.cm_on == 0 and rs.u_cmr.is_empty() and rs.s_cms.is_empty(), "countermarch: a Rome battle has none")


## The countermarch's walk (2026-11-02) in the Auto and Hold runs of _cm_run: every man stood in the front rank at
## one of the first five rank volleys; men walked; the footprint and facing stayed put; none walk on Hold.
func _cm_walk(auto: Dictionary, hold: Dictionary) -> void:
	var sim := BattleSim.new()
	sim.setup(_cm_sc([]), 31)
	var b0: int = sim.u_slot_base[0]
	var n0: int = sim.u_count0[0]
	var front := {}
	var rank_v := 0
	var cx0: int = sim.u_cx[0]
	var w0: int = sim.u_maxx[0] - sim.u_minx[0]
	var face0: int = sim.u_face[0]
	var gaps_ok := true
	for t in 900:
		var rk0: int = sim.stat_cm_rank
		var fr: Array[int] = []
		for s in sim.files_of(0):
			fr.append(sim.slot_soldier[b0 + s])
		sim.step()
		if sim.stat_cm_rank != rk0:
			rank_v += 1
			if rank_v <= 5:
				for i in fr:
					front[i] = 1
		# A walking man stands in a gap: never within 0.4 m of another man of the line.
		if t % 3 == 0:
			for s in sim.u_alive[0]:
				var i: int = sim.slot_soldier[b0 + s]
				if sim.s_rtw[i] == 0:
					continue
				for q in sim.u_alive[0]:
					var j: int = sim.slot_soldier[b0 + q]
					if j != i and absi(sim.pos_x[i] - sim.pos_x[j]) < M and absi(sim.pos_y[i] - sim.pos_y[j]) < M \
							and FM.approx_len(sim.pos_x[i] - sim.pos_x[j], sim.pos_y[i] - sim.pos_y[j]) < M * 4 / 10:
						gaps_ok = false
	var sa: BattleSim = auto["sim"]
	var sh: BattleSim = hold["sim"]
	print("countermarch walk: %d men walked to the rear (Hold %d), %d of %d men in the front rank at the first five rank volleys, centre %d -> %d mm, width %d -> %d mm" % [
		sim.stat_cm_files, sh.stat_cm_files, front.size(), n0, cx0, sim.u_cx[0], w0, sim.u_maxx[0] - sim.u_minx[0]])
	_check(sa.stat_cm_files > 0 and sa.stat_cm_files == sim.stat_cm_files, "countermarch: men walk to the rear after their rank's volley (%d)" % sa.stat_cm_files)
	_check(front.size() == n0, "countermarch: every man stood in the front rank within five rank volleys (%d of %d)" % [front.size(), n0])
	_check(sh.stat_cm_files == 0, "countermarch: nobody walks on Hold (%d)" % sh.stat_cm_files)
	_check(gaps_ok, "countermarch: a man walking to the rear keeps 0.4 m from every man of his line")
	_check(absi(sim.u_cx[0] - cx0) < M / 2 and absi(sim.u_maxx[0] - sim.u_minx[0] - w0) < M and sim.u_face[0] == face0,
		"countermarch: the footprint and facing stay put")


# ------------------------------------------------------------------ pass ---

## A unit of side 0 (`mk` x `mn`, `mf` files) at y 240 ordered to y 160 through a standing friend (`sk` x `sn`, `sf`
## files) at y 200, both facing up; a far enemy so the battle runs. Returns the pass's numbers (and the same move
## with the field clear when `clear`).
func _pass_run(mk: String, mn: int, mf: int, sk: String, sn: int, sf: int, clear: bool) -> Dictionary:
	var units := [Scenarios.unit(0, UT.index_of(mk), mn, 150, 240, UP, mf)]
	if not clear:
		units.append(Scenarios.unit(0, UT.index_of(sk), sn, 150, 200, UP, sf))
	units.append(Scenarios.unit(1, UT.index_of("musketeers"), 20, 150, 20, DOWN, 10))
	var w: int = mf * UT.stat(UT.index_of(mk), "file_sp")
	var sim := BattleSim.new()
	sim.setup(_sc(units, [BattleSim.make_move_order(5, 0, 150 * M, 160 * M, UP, w, 0)]), 7)
	var ss0 := sim.slot_soldier.duplicate()
	var closest := 1 << 30
	var aside := 0
	var done := -1
	for t in 1500:
		sim.step()
		if not clear and t % 2 == 0:
			closest = mini(closest, _pass_closest(sim, 0, 1))
			for q in sim.u_alive[1]:
				aside = maxi(aside, _pass_off(sim, 1, q))
		if done < 0 and sim.tick > 10 and sim.u_order[0] == BattleSim.O_NONE:
			var ok := true
			for s in sim.u_alive[0]:
				if _pass_off(sim, 0, s) > M / 3:
					ok = false
			if ok:
				done = sim.tick
		if done >= 0 and sim.tick > done + 60:
			break
	var off := 0
	var nu := 1 if clear else 2
	for u in nu:
		for s in sim.u_alive[u]:
			if _pass_off(sim, u, s) > M * 3 / 10:
				off += 1
	var after := 1 << 30
	var same := sim.slot_soldier == ss0
	for u in nu:
		after = mini(after, _pass_closest(sim, u, u))
	if not clear:
		after = mini(after, _pass_closest(sim, 0, 1))
	return {"t": done, "closest": closest, "aside": aside, "off": off, "after": after, "same": same, "men": sim.stat_mix_men}


## The closest two men, one of unit a and one of unit b (a == b: two of a), within 2 m (else 2 m).
func _pass_closest(sim, a: int, b: int) -> int:
	var best := 2 * M
	for s in sim.u_alive[a]:
		var i: int = sim.slot_soldier[sim.u_slot_base[a] + s]
		for q in sim.u_alive[b]:
			var j: int = sim.slot_soldier[sim.u_slot_base[b] + q]
			if i == j:
				continue
			var dx: int = sim.pos_x[i] - sim.pos_x[j]
			var dy: int = sim.pos_y[i] - sim.pos_y[j]
			if absi(dx) < best and absi(dy) < best:
				best = mini(best, FM.approx_len(dx, dy))
	return best


func _pass_off(sim, u: int, s: int) -> int:
	var k: int = sim.u_slot_base[u] + s
	var i: int = sim.slot_soldier[k]
	return FM.approx_len(sim.u_ax[u] + sim.off_x[k] - sim.pos_x[i], sim.u_ay[u] + sim.off_y[k] - sim.pos_y[i])


func _pass() -> void:
	for c in [["line", "musketeers", 100, 25, "musketeers", 100, 25], ["column", "musketeers", 100, 5, "musketeers", 100, 25],
			["horse", "lancers", 60, 15, "musketeers", 100, 25], ["foot_horse", "musketeers", 100, 25, "lancers", 60, 15]]:
		var r := _pass_run(c[1], c[2], c[3], c[4], c[5], c[6], false)
		var b := _pass_run(c[1], c[2], c[3], c[4], c[5], c[6], true)
		print("pass %s: %.1f s (clear %.1f s), closest %.2f m, the standing men aside up to %.2f m, after: closest %.2f m, %d men off their places, slots kept %s, %d man-steps" % [
			c[0], r["t"] / 10.0, b["t"] / 10.0, r["closest"] / float(M), r["aside"] / float(M), r["after"] / float(M), r["off"], str(r["same"]), r["men"]])
		_check(r["t"] > 0 and b["t"] > 0 and r["t"] >= b["t"] and r["t"] * 100 <= b["t"] * 115, "pass %s: through at most 15 %% slower (%d / %d ticks)" % [c[0], r["t"], b["t"]])
		_check(r["closest"] >= M * 3 / 10, "pass %s: no two men of the two units within 0.3 m (%.2f m)" % [c[0], r["closest"] / float(M)])
		_check(r["aside"] >= M / 10, "pass %s: the standing men step aside (%.2f m)" % [c[0], r["aside"] / float(M)])
		_check(r["after"] >= M / 2 and r["off"] == 0 and r["same"], "pass %s: after it every man in his own place, none within 0.5 m of another" % c[0])
	# Not a crossing: two lines marching shoulder to shoulder (0.4 m between their flanks), and a line following 4 m
	# behind another, never mix (2026-11-02, the coordinator: only a real crossing filters).
	var mus := UT.index_of("musketeers")
	var fsp: int = UT.stat(mus, "file_sp")
	var hw: int = 24 * fsp / 2
	var gap_x: int = (2 * hw + fsp + M * 4 / 10) / M
	for c2 in [["beside", 150 + gap_x, 240], ["behind", 150, 249]]:
		var units := [Scenarios.unit(0, mus, 100, 150, 240, UP, 25), Scenarios.unit(0, mus, 100, c2[1], c2[2], UP, 25),
			Scenarios.unit(1, mus, 20, 150, 20, DOWN, 10)]
		var sim := BattleSim.new()
		sim.setup(_sc(units, [BattleSim.make_move_order(5, 0, 150 * M, 160 * M, UP, 25 * fsp, 0),
			BattleSim.make_move_order(5, 1, int(c2[1]) * M, (int(c2[2]) - 80) * M, UP, 25 * fsp, 0)]), 7)
		var mixed := 0
		for t in 700:
			sim.step()
			mixed += sim.mix_any
		print("pass %s: %d ticks mixing, %d man-steps" % [c2[0], mixed, sim.stat_mix_men])
		_check(sim.stat_mix_men == 0, "pass %s: friends marching %s are left alone (%d man-steps)" % [c2[0], c2[0], sim.stat_mix_men])


# ----------------------------------------------------------------- march ---

func _march() -> void:
	var MP = load("res://tests/march_probe.gd")
	# A lone line on the same move (the beside case's first unit alone): its anchor's arrival.
	var lone: Dictionary = MP.scenario("beside")
	var pm: Array = lone["place_mm"]
	lone["units"] = [lone["units"][0], lone["units"][2]]
	lone["orders"] = [lone["orders"][0]]
	var sim := BattleSim.new()
	sim.setup(lone, 7)
	MP._place(sim, 0, int(pm[0][1]), int(pm[0][2]))
	var lone_t := -1
	for t in 1500:
		sim.step()
		if t > 6 and sim.u_order[0] == BattleSim.O_NONE:
			lone_t = sim.tick
			break
	for c in ["beside", "column", "street"]:
		var r: Dictionary = MP.run_case(c)
		print("march %s: closest %.2f m, %d man-ticks under 0.4 m, %d under 0.25 m, anchors in %.1f s (a lone line %.1f s), %d separation man-steps" % [
			c, r["closest"] / float(M), r["in40"], r["in25"], r["arr"] / 10.0, lone_t / 10.0, r["sep"]])
		if c == "street":
			_check(r["in25"] < 1500 and r["arr"] > 0, "march street: fewer than 1,500 man-ticks under 0.25 m (%d; 2,966 before), arrived" % r["in25"])
		else:
			_check(r["closest"] >= M / 3 and r["in25"] == 0, "march %s: no two men of the two units within 0.33 m (%.2f m)" % [c, r["closest"] / float(M)])
		if c == "beside":
			_check(r["arr"] == lone_t, "march beside: the anchors arrive as a lone line's (%d / %d ticks)" % [r["arr"], lone_t])


# ----------------------------------------------------------------- route ---

func _route() -> void:
	var RP = load("res://tests/route_probe.gd")
	var f: Dictionary = RP.run_case("front")
	print("route front: way %.1f m (plain %.1f m), arrived %.1f s, %d men lost, %d ways round" % [
		f["walked"] / float(M), f["plain"] / float(M), f["arr"] / 10.0, f["lost"], f["detours"]])
	_check(f["detours"] >= 1 and f["arr"] > 0 and f["lost"] == 0 and f["walked"] * 100 <= f["plain"] * 150,
		"route front: round the musket line's front (a way round, arrived, %d men lost, way %d %% of the plain)" % [f["lost"], f["walked"] * 100 / maxi(f["plain"], 1)])
	var a: Array = RP.setup_case("house")
	var sim = a[0]
	var mv: int = a[1]
	var got := false
	for t in 3000:
		sim.step()
		if sim.u_occ[mv] > 0:
			got = true
			break
	print("route house: %d ways round, inside at %.1f s" % [sim.stat_rt_detours, sim.tick / 10.0 if got else -1.0])
	_check(sim.stat_rt_detours >= 1 and got, "route house: round the enemy company and into the house")
	# The attack goes straight: the same rodeleros ordered at the line facing them.
	var t2: Array = RP.setup_case("thru")
	var s2 = t2[0]
	s2.pending_orders.clear()
	s2.queue_order({"tick": 5, "type": BattleSim.ORDER_ATTACK, "unit": 0, "target": 1})
	var x0: int = s2.u_ax[0]
	var dev := 0
	for t in 2000:
		s2.step()
		if s2.u_contact[0] != 0:
			break
		dev = maxi(dev, absi(s2.u_ax[0] - x0))
	print("route attack: %d plans round, the anchor at most %.1f m off the straight line until contact" % [s2.stat_rt_plans, dev / float(M)])
	_check(s2.stat_rt_plans == 0 and dev <= 3 * M, "route attack: straight at the line (%d plans round, %.1f m off)" % [s2.stat_rt_plans, dev / float(M)])


# ---------------------------------------------------------- native siege ---

func _torch_sc(n_def: int, orders: Array) -> Dictionary:
	return _sc([_u(0, "torch_raiders", 60, 150, 170, UP), _u(1, "musketeers", n_def, 150, 155, DOWN, {"ammo_pct": 0})], orders)


## A walls-`walls` oppidum, the torch raiders 14 m out from the gate nearest them, the defenders `dfn` (10
## javelinmen at the plaza holding their fire, for the set pieces); AI sides `ai`. Returns [scenario, gate].
func _torch_gate_sc(walls: int, ai: Array, skill: int, dfn: Array = [[UT.JAVELIN, 10]],
		att: Array = [[UT.index_of("torch_raiders"), 60]]) -> Array:
	var city := {"seed": 21, "level": 1, "walls": walls, "bld": [1, 2], "plan": MapGen.PLAN_OPPIDUM, "founder": MapGen.CUL_CELTIC}
	var terr := {"kind": Terrain.K_FLAT, "seed": 11, "forest": 0, "ground": MapGen.PAL_GREEN}
	var sc: Dictionary = Scenarios.settlement(city, terr, att, dfn, 1, ai, {})["scenario"]
	sc["ai_skill"] = [skill, skill]
	sc["deploy_zones"] = []
	var probe := BattleSim.new()
	probe.setup(sc, 7)
	var gate := -1
	var bd := 1 << 40
	var spot := Vector3i.ZERO
	for g in probe.n_gates:
		if probe.g_cit[g] != 0:
			continue
		var gf: Vector3i = probe.gate_front(g, 0)
		var d := absi(gf.x - probe.u_cx[0]) + absi(gf.y - probe.u_cy[0])
		if d < bd:
			bd = d
			gate = g
			var o := (gf.z + 512) & 1023
			spot = Vector3i(gf.x + FM_cos(o) * 14, gf.y + FM_sin(o) * 14, gf.z)
	var k := 0
	for ud in sc["units"]:
		if int(ud["side"]) == 0:
			ud["x_m"] = spot.x / M + 12 * k  # (side by side along the wall: a second unit 12 m over)
			ud["y_m"] = spot.y / M
			ud["facing"] = spot.z
			k += 1
	return [sc, gate]


static func FM_cos(a: int) -> int:
	return preload("res://sim/fixed_math.gd").cos_a(a) * M / preload("res://sim/fixed_math.gd").TRIG_ONE


static func FM_sin(a: int) -> int:
	return preload("res://sim/fixed_math.gd").sin_a(a) * M / preload("res://sim/fixed_math.gd").TRIG_ONE


func _native() -> void:
	var ab := UT.abilities(UT.index_of("torch_raiders"))
	_check((ab & (1 << UT.AB_GRENADE)) != 0 and (ab & (1 << UT.AB_BATTER)) != 0, "native: torch raiders have the grenade and batter abilities (%d)" % ab)
	var rome_bat := false
	for t in UT.ROME_N:
		if UT.stat(t, "batter") != 0 or (UT.ammo_index("fire_pots") == UT.stat(t, "m_ak") and UT.stat(t, "grenades") != 0):
			rome_bat = true
	_check(not rome_bat, "native: no Rome row has the melee batter or thrown fire pots")
	# Fire pots: on Auto none at a formed block in the open, on Use now thrown at it.
	var auto := _gren_run(_torch_sc(100, []), 300)
	var now := _gren_run(_torch_sc(100, [BattleSim.make_ability_order(0, 0, UT.AB_GRENADE, UT.AB_NOW, 1)]), 300)
	print("native fire pots in 30 s at a musket block 15 m off: Auto %d, Use now %d" % [auto, now])
	_check(auto == 0, "native: fire pots on Auto are not thrown at men in the open (%d)" % auto)
	_check(now > 0, "native: fire pots on Use now are thrown at the unit (%d)" % now)
	# The batter at a walls-1 gate, no AI: Use now breaks it; Hold at 10 s stops the blows.
	var gs := _torch_gate_sc(1, [], 1)
	var sc: Dictionary = gs[0]
	var g: int = gs[1]
	sc["orders"] = [{"tick": 0, "type": BattleSim.ORDER_FIRE, "unit": 1, "on": 0},
		BattleSim.make_ability_order(0, 0, UT.AB_GRENADE, UT.AB_HOLD, -1), BattleSim.make_ability_order(5, 0, UT.AB_BATTER, UT.AB_NOW, -2 - g)]
	var sim := BattleSim.new()
	sim.setup(sc, 7)
	var broke := -1
	while sim.tick < 1500 and broke < 0:
		sim.step()
		if sim.g_state[g] == BattleSim.GATE_BROKEN:
			broke = sim.tick
	print("native batter: walls-1 gate broken at %d by %d blows" % [broke, sim.stat_mbat_blows])
	_check(broke > 0 and sim.stat_mbat_blows > 0, "native: the torch raiders' Use now breaks a walls-1 gate by their blows")
	var sc2: Dictionary = gs[0].duplicate(true)
	sc2["orders"] = [{"tick": 0, "type": BattleSim.ORDER_FIRE, "unit": 1, "on": 0},
		BattleSim.make_ability_order(0, 0, UT.AB_GRENADE, UT.AB_HOLD, -1), BattleSim.make_ability_order(5, 0, UT.AB_BATTER, UT.AB_NOW, -2 - g),
		BattleSim.make_ability_order(300, 0, UT.AB_BATTER, UT.AB_HOLD, -1)]
	var sim2 := BattleSim.new()
	sim2.setup(sc2, 7)
	var b300 := -1
	while sim2.tick < 900:
		sim2.step()
		if sim2.tick == 301:
			b300 = sim2.stat_mbat_blows
	print("native batter Hold at 30 s: %d blows by then, %d at 90 s, gate %d" % [b300, sim2.stat_mbat_blows, sim2.g_state[g]])
	_check(b300 > 0 and sim2.stat_mbat_blows == b300 and sim2.g_state[g] == BattleSim.GATE_CLOSED, "native: Hold stops the battering")
	# The siege AI: a walls-2 oppidum (iron-bound gate, no ram): Average batters the gate with them, Easy gives no order.
	for skill in [1, 0]:
		# (Third pass of cover, 2026-11-06: the defenders' front men now see past the gateway's corners and shoot, so
		# 60 raiders broke at 13 of the 16 blows the iron-bound gate needs; 80 raiders, the check's intent unchanged.)
		var ga := _torch_gate_sc(2, [0, 1], skill, [[UT.HEAVY, 80], [UT.SPEAR, 80]], [[UT.index_of("torch_raiders"), 80]])
		var sc3: Dictionary = ga[0]
		var g3: int = ga[1]
		var s3 := BattleSim.new()
		s3.setup(sc3, 7)
		var now_seen := false
		var down := -1
		while s3.tick < 2400 and down < 0:
			s3.step()
			if s3.ability_state(0, UT.AB_BATTER) == UT.AB_NOW:
				now_seen = true
			if s3.ai_gate[0] >= 0 and s3.g_state[s3.ai_gate[0]] == BattleSim.GATE_BROKEN:
				down = s3.tick
		print("native ai (%s): batter Use now %s, %d blows, gate %d down at %d, %d ability orders" % ["Average" if skill == 1 else "Easy",
			str(now_seen), s3.stat_mbat_blows, g3, down, s3.stat_ab_orders])
		if skill == 1:
			_check(now_seen and s3.stat_mbat_blows > 0 and down > 0, "native: the siege AI batters the gate with the torch raiders and it falls")
		else:
			_check(s3.stat_ab_orders == 0 and s3.stat_mbat_blows == 0, "native: Easy gives the torch raiders no ability order")
	_torch_stretch_check()
	_second_party_check("poles")
	_second_party_check("ladders")


## docs/AI.md 51: two torch raider units at a walls-1 oppidum's gate (the palisade), the AI at Average: the first
## (10 men: slow blows) takes the gate, the second (60) a palisade stretch by it, and that stretch is breached
## before the gate falls (the breach is the entry: the assault begins).
func _torch_stretch_check() -> void:
	var trk := UT.index_of("torch_raiders")
	var ga := _torch_gate_sc(1, [0, 1], 1, [[UT.HEAVY, 80], [UT.SPEAR, 80]], [[trk, 10], [trk, 60]])
	var sc: Dictionary = ga[0]
	var sim := BattleSim.new()
	sim.setup(sc, 7)
	var a := -1
	var b := -1
	for u in sim.n_units:
		if sim.u_side[u] == 0 and sim.t_mbat[sim.u_type[u]] != 0:
			if a < 0:
				a = u
			elif b < 0:
				b = u
	var gate_now := false
	var stretch := -1
	var breach := -1
	var gate_down := -1
	while sim.tick < 3000 and breach < 0:
		sim.step()
		var g: int = sim.ai_gate[0]
		if g >= 0 and sim.ability_state(a, UT.AB_BATTER) == UT.AB_NOW and sim.u_abt[a] == -2 - g:
			gate_now = true
		if stretch < 0 and sim.ability_state(b, UT.AB_BATTER) == UT.AB_NOW and sim.u_abt[b] >= 0:
			stretch = sim.u_abt[b]
		if stretch >= 0 and sim.ws_state[stretch] != BattleSim.WS_STANDING:
			breach = sim.tick
		if gate_down < 0 and g >= 0 and sim.g_state[g] == BattleSim.GATE_BROKEN:
			gate_down = sim.tick
	print("native stretch: gate party %s, second unit's stretch %d, breached at %d, gate down at %d, phase %d, %d blows" % [
		str(gate_now), stretch, breach, gate_down, sim.ai_phase[0], sim.stat_mbat_blows])
	_check(gate_now and stretch >= 0, "native: of two torch raider units at a palisade gate the second batters a stretch")
	_check(breach > 0 and (gate_down < 0 or gate_down >= breach), "native: the second torch raider unit's stretch is breached (a second way in)")



## A unit with no set ordered onto a stretch where its side's set is planted goes up it (ST_LADDER_GO, then
## ST_LADDER) and ends on the walkway (2026-11-01). One run a second unit: kind "poles" (Itza warriors with a
## pole set; then warriors, bowmen, Holcan) or "ladders" (heavy infantry and javelinmen with a ladder set).
func _second_party_check(kind: String) -> void:
	var city := {"seed": 4242, "level": 2, "walls": 1, "bld": [], "towers": 0}
	var terr := {"kind": Terrain.K_FLAT, "seed": 11, "forest": 0, "ground": 2}
	var att: Array
	if kind == "poles":
		att = [[UT.index_of("native_warriors"), 90], [UT.index_of("native_warriors"), 90],
			[UT.index_of("native_bowmen"), 60], [UT.index_of("holcan"), 60]]
	else:
		att = [[UT.HEAVY, 90], [UT.HEAVY, 90], [UT.JAVELIN, 60], [UT.HEAVY, 60]]
	var eq_k: int = BattleSim.EQ_POLES if kind == "poles" else BattleSim.EQ_LADDERS
	for second in [1, 2, 3]:
		var sc: Dictionary = Scenarios.settlement(city, terr, att, [[UT.JAVELIN, 10]], 1, [], {kind: 2})["scenario"]
		var sim := BattleSim.new()
		sim.setup(sc, 77)
		var dfu := -1
		for u in sim.n_units:
			if sim.u_side[u] == 1 and dfu < 0:
				dfu = u
		var q0 := -1
		for q in sim.n_eq:
			if q0 < 0 and sim.q_kind[q] == eq_k:
				q0 = q
		var sg := -1
		var bd := 0
		var mp := Vector2i.ZERO
		for s in sim.ws_x0.size():
			var p: Vector2i = BattleSim.seg_pt(sim, s, BattleSim.seg_len(sim, s) / 2)
			if not BattleSim.ladder_ok(sim, 0, s, p.x, p.y):
				continue
			var d := absi(p.x - sim.u_cx[0]) + absi(p.y - sim.u_cy[0])
			if sg < 0 or d < bd:
				sg = s
				bd = d
				mp = p
		sim.queue_order({"tick": 0, "type": BattleSim.ORDER_FIRE, "unit": dfu, "on": 0, "player": 51})
		sim.queue_order({"tick": 1, "type": BattleSim.ORDER_PICKUP, "unit": 0, "equip": q0, "run": 0, "player": 50})
		var ordered := false
		var sent := false
		var set_for := -2
		var went := false
		var climbed := false
		var up := 0
		while sim.tick < 4500:
			if not ordered and sim.u_carry[0] == q0:
				ordered = true
				sim.queue_order(BattleSim.make_move_order(sim.tick, 0, mp.x, mp.y, 768, 20 * M, 0))
			if not sent and sim.u_stair[0] == BattleSim.ST_LADDER:
				sent = true
				set_for = BattleSim.ladder_set_for(sim, second, sg, mp.x, mp.y)
				sim.queue_order(BattleSim.make_move_order(sim.tick, second, mp.x, mp.y, 768, 20 * M, 0))
			sim.step()
			if sent:
				went = went or sim.u_stair[second] == BattleSim.ST_LADDER_GO
				climbed = climbed or sim.u_stair[second] == BattleSim.ST_LADDER
				if sim.u_wall[second] == sg + 1 and sim.u_stair[second] == 0:
					var base: int = sim.u_slot_base[second]
					for sl in sim.u_alive[second]:
						if sim._on_walk(sim.pos_x[sim.slot_soldier[base + sl]], sim.pos_y[sim.slot_soldier[base + sl]]):
							up += 1
					break
		var key: String = str(UT.TYPES[sim.u_type[second]]["key"])
		print("second party (%s): %s set %d, to the foot %s, climbing %s, %d of %d on the walkway at tick %d" % [
			kind, key, set_for, str(went), str(climbed), up, sim.u_alive[second], sim.tick])
		_check(set_for == q0 and went and climbed and up * 10 >= sim.u_alive[second] * 9 and sim.u_alive[second] > 0,
			"%s: a second unit (%s) ordered onto the stretch goes up the planted set onto the walkway" % [kind, key])
