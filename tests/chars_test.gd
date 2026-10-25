extends SceneTree
## Batch 3 sim hooks on the characters (docs/design/battle_sim.md "Batch 3 sim and campaign
## hooks (as built)"), on Rome's rows given the new fields for the run (no West rows yet):
##   roles     a Champion with "au_roles": his aura reaches only the listed roles (or row keys);
##             without the field every foot unit near him as before.
##   fear      a Champion with "au_fear": enemy foot within his au_fear_r get AU_FEAR and lose
##             au_fear morale a second more than without; an enemy diplomat's steadying aura halves it.
##   parley    a diplomat with "parley_vs" / "parley_bonus": the bonus applies only to the listed
##             targets; on the same seeds the bonus turns refusals into surrenders and never the
##             other way; an unlisted target rolls as before.
##   snapshot  the fear set piece survives snapshot / restore (same hashes after restore).
##   west      the batch 3 rows themselves (sea captain, shaman, missionary) on West units: the role filter, the
##             shaman's fear, the missionary's bonus against a native row and none against a pike block.
##   godot --headless --script res://tests/chars_test.gd [-- --only=roles|fear|parley|snapshot|west]

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const Terrain := preload("res://sim/terrain.gd")
const M := 1024

var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	if only == "" or only == "roles":
		_roles()
	if only == "" or only == "fear":
		_fear()
	if only == "" or only == "parley":
		_parley()
	if only == "" or only == "snapshot":
		_snapshot()
	if only == "" or only == "west":
		_west()
	print("RESULT: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	quit(0 if fails == 0 else 1)


# ------------------------------------------------------------- helpers ---

## Set (or with null erase) fields of a row for the run; returns the old values to put back.
func _set_row(key: String, fields: Dictionary) -> Dictionary:
	var row: Dictionary = UT.TYPES[UT.index_of(key)]
	var old := {}
	for k in fields:
		old[k] = row.get(k, null)
		if fields[k] == null:
			row.erase(k)
		else:
			row[k] = fields[k]
	return old


func _sc(units: Array, chars: Array) -> Dictionary:
	return {"width_m": 400, "height_m": 400, "ai_sides": [], "orders": [], "units": units, "chars": chars,
		"terrain": {"kind": Terrain.K_FLAT}}


func _ch(key: String) -> Dictionary:
	return {"key": key, "name": key.capitalize()}


func _ch_unit(sim, s: int, k: int) -> int:
	for u in sim.n_units:
		if sim.u_side[u] == s and sim.u_char[u] == k:
			return u
	return -1


func _put(sim, u: int, x: int, y: int) -> void:
	sim.u_ax[u] = x * M
	sim.u_ay[u] = y * M
	sim.u_dx[u] = x * M
	sim.u_dy[u] = y * M
	var base: int = sim.u_slot_base[u]
	for s in sim.u_alive[u]:
		var i: int = sim.slot_soldier[base + s]
		sim.pos_x[i] = x * M + sim.off_x[base + s]
		sim.pos_y[i] = y * M + sim.off_y[base + s]
	sim.u_dirty[u] = 1
	sim.u_settled[u] = 0
	sim._update_bounds()


# --------------------------------------------------------------- roles ---

## Our javelinmen (skirmish) and light infantry (line) either side of the Champion, the enemy far
## off; the bits each has after two seconds. Returns [javelin bits, light bits].
func _roles_run() -> Array:
	var sim := BattleSim.new()
	sim.setup(_sc([
		Scenarios.unit(0, UT.index_of("javelin"), 20, 170, 300, Scenarios.FACE_UP),
		Scenarios.unit(0, UT.LIGHT, 20, 230, 300, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.HEAVY, 40, 200, 60, Scenarios.FACE_DOWN)], [[_ch("hero_foot")], []]), 501)
	var h := _ch_unit(sim, 0, UT.CK_FOOT)
	sim.step()
	_put(sim, h, 200, 300)
	for t in 20:
		sim.step()
	return [sim.u_aura[0], sim.u_aura[1], sim._box_gap(h, 0) / M, sim._box_gap(h, 1) / M]


func _roles() -> void:
	var r0 := _roles_run()
	_check(r0[0] == BattleSim.AU_FOOT and r0[1] == BattleSim.AU_FOOT,
		"roles: without au_roles the Champion's aura reaches javelinmen and light foot (bits %d / %d, gaps %d / %d m)" % r0)
	var old := _set_row("hero_foot", {"au_roles": ["skirmish", "shock"]})
	var r1 := _roles_run()
	_check(r1[0] == BattleSim.AU_FOOT and r1[1] == 0,
		"roles: au_roles skirmish, shock: the javelinmen (skirmish) in it, the light foot (line) not (bits %d / %d)" % [r1[0], r1[1]])
	_set_row("hero_foot", {"au_roles": ["light"]})
	var r2 := _roles_run()
	_check(r2[0] == 0 and r2[1] == BattleSim.AU_FOOT,
		"roles: au_roles naming a row key (light): only the light foot (bits %d / %d)" % [r2[0], r2[1]])
	_set_row("hero_foot", {"au_roles": []})
	var r3 := _roles_run()
	_check(r3[0] == r0[0] and r3[1] == r0[1], "roles: an empty au_roles is every unit, as today")
	_set_row("hero_foot", old)


# ---------------------------------------------------------------- fear ---

## Their heavy foot 60 men at (200, 100); our Champion 20 m below it; our own foot far off; with
## `dip` their diplomat beside their foot. Returns [their morale drop over 20 s, their aura bits,
## our foot's aura bits, sim].
func _fear_run(dip: bool, secs: int = 20) -> Array:
	var sim := BattleSim.new()
	sim.setup(_sc([
		Scenarios.unit(0, UT.HEAVY, 60, 200, 360, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.HEAVY, 60, 200, 100, Scenarios.FACE_DOWN)],
		[[_ch("hero_foot")], [_ch("diplomat")] if dip else []]), 777)
	var h := _ch_unit(sim, 0, UT.CK_FOOT)
	sim.step()
	_put(sim, h, 200, int(sim.u_maxy[1] / M) + 15)
	if dip:
		_put(sim, _ch_unit(sim, 1, UT.CK_DIPLOMAT), int(sim.u_maxx[1] / M) + 4, 100)
	for t in 9:
		sim.step()  # to the next whole second (the aura pass)
	var m0: int = sim.u_morale[1]
	for t in secs * 10:
		sim.step()
	return [m0 - sim.u_morale[1], sim.u_aura[1], sim.u_aura[0], sim]


func _fear() -> void:
	var a0 := _fear_run(false)
	var old := _set_row("hero_foot", {"au_fear": 4, "au_fear_r": 30 * M})
	var a1 := _fear_run(false)
	var a2 := _fear_run(true)
	_set_row("hero_foot", old)
	_check(a0[0] == 0 and (a0[1] & BattleSim.AU_FEAR) == 0, "fear: without au_fear their foot loses no morale near him (drop %d)" % a0[0])
	_check((a1[1] & BattleSim.AU_FEAR) != 0 and (a1[2] & BattleSim.AU_FEAR) == 0,
		"fear: au_fear 4: their foot has the AU_FEAR bit, ours not (bits %d / %d)" % [a1[1], a1[2]])
	_check(a1[0] >= 4 * 19 and a1[0] <= 4 * 21, "fear: au_fear 4: their foot loses 4 morale a second (%d over 20 s)" % a1[0])
	_check((a2[1] & BattleSim.AU_STEADY) != 0 and a2[0] * 2 == a1[0],
		"fear: with their diplomat beside them (steadying) the loss is halved (%d vs %d, bits %d)" % [a2[0], a1[0], a2[1]])


# -------------------------------------------------------------- parley ---

## Their light foot (role line) wavering (morale 0) before our diplomat: a parley on seed sd.
## Returns 1 surrendered, 0 refused, -1 no roll.
func _parley_run(sd: int) -> int:
	var sim := BattleSim.new()
	sim.setup(_sc([
		Scenarios.unit(0, UT.HEAVY, 100, 200, 330, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.LIGHT, 60, 200, 200, Scenarios.FACE_DOWN)], [[_ch("diplomat")], []]), 930 + sd)
	var dip := _ch_unit(sim, 0, UT.CK_DIPLOMAT)
	_put(sim, dip, 235, 190)
	sim.u_morale[1] = 0
	sim.step()
	sim.queue_order(BattleSim.make_parley_order(sim.tick, dip, 1))
	for t in 400:
		sim.step()
		if sim.stat_parley_ok > 0:
			return 1
		if sim.stat_parley_fail > 0:
			return 0
	return -1


func _parley() -> void:
	var n := 16
	var base: Array = []
	for sd in n:
		base.append(_parley_run(sd))
	var old := _set_row("diplomat", {"parley_vs": ["line", "west"], "parley_bonus": 40})
	var probe := BattleSim.new()
	probe.setup(_sc([Scenarios.unit(0, UT.HEAVY, 20, 200, 330, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.LIGHT, 20, 200, 200, Scenarios.FACE_DOWN)], [[_ch("diplomat")], []]), 1)
	var dty := UT.index_of("diplomat")
	_check(probe.parley_bonus(dty, UT.LIGHT) == 40 and probe.parley_bonus(dty, UT.index_of("javelin")) == 0
		and probe.parley_bonus(dty, UT.index_of("buccaneers")) == 40,
		"parley: the bonus for a listed role (light: line) and pack (buccaneers: west), none for javelinmen (skirmish)")
	var bon: Array = []
	for sd in n:
		bon.append(_parley_run(sd))
	_set_row("diplomat", {"parley_vs": ["skirmish"]})
	var unl: Array = []
	for sd in n:
		unl.append(_parley_run(sd))
	_set_row("diplomat", old)
	var sup := true
	var gained := 0
	var ok0 := 0
	var ok1 := 0
	for sd in n:
		ok0 += 1 if base[sd] == 1 else 0
		ok1 += 1 if bon[sd] == 1 else 0
		if base[sd] < 0 or bon[sd] < 0 or (base[sd] == 1 and bon[sd] != 1):
			sup = false
		if base[sd] == 0 and bon[sd] == 1:
			gained += 1
	_check(sup and gained > 0, "parley: +40 vs line on the same %d seeds: surrenders %d -> %d (the roll +40, at most 95 %%; never fewer) %s -> %s" % [
		n, ok0, ok1, str(base), str(bon)])
	_check(str(unl) == str(base), "parley: a parley_vs that does not name the target rolls as before %s" % str(unl))


# ------------------------------------------------------------ snapshot ---

func _snapshot() -> void:
	var old := _set_row("hero_foot", {"au_fear": 4, "au_fear_r": 30 * M, "au_roles": ["line"]})
	var r := _fear_run(true, 3)
	var sim = r[3]
	var blob: PackedByteArray = sim.snapshot()
	var h1 := PackedInt64Array()
	for t in 150:
		sim.step()
		h1.append(sim.state_hash())
	var sim2 := BattleSim.new()
	var r2 := _fear_run(true, 0)
	sim2 = r2[3]
	var ok := sim2.restore(blob)
	var h2 := PackedInt64Array()
	for t in 150:
		sim2.step()
		h2.append(sim2.state_hash())
	_set_row("hero_foot", old)
	_check(ok and h1 == h2 and (sim.u_aura[1] & BattleSim.AU_FEAR) != 0,
		"snapshot: au_fear / au_roles set piece: 150 ticks after restore hash as the original (%x)" % h1[h1.size() - 1])


# ---------------------------------------------------------------- west ---

func _west_aura(hero: String, kinds: Array) -> Array:
	var units: Array = []
	for i in kinds.size():
		units.append(Scenarios.unit(0, UT.index_of(str(kinds[i])), 20, 156 + 22 * i, 300, Scenarios.FACE_UP))
	units.append(Scenarios.unit(1, UT.HEAVY, 40, 200, 60, Scenarios.FACE_DOWN))
	var sim := BattleSim.new()
	sim.setup(_sc(units, [[_ch(hero)], []]), 611)
	var h := _ch_unit(sim, 0, UT.CK_FOOT)
	sim.step()
	_put(sim, h, 200, 300)
	for t in 20:
		sim.step()
	var out: Array = []
	for i in kinds.size():
		out.append(sim.u_aura[i])
	return out


func _west() -> void:
	var sc := _west_aura("sea_captain", ["buccaneers", "w_pikemen", "marines", "native_warriors", "musketeers"])
	_check((sc[0] & BattleSim.AU_FOOT) != 0 and sc[1] == 0 and (sc[2] & BattleSim.AU_FOOT) != 0 and (sc[3] & BattleSim.AU_FOOT) != 0 and sc[4] == 0,
		"west: the sea captain's aura reaches buccaneers (skirmish), marines (named) and warriors (shock), not pikemen or musketeers (bits %s)" % str(sc))
	var sh := _west_aura("shaman", ["native_bowmen", "w_pikemen", "native_warriors", "marines"])
	_check((sh[0] & BattleSim.AU_FOOT) != 0 and sh[1] == 0 and (sh[2] & BattleSim.AU_FOOT) != 0 and sh[3] == 0,
		"west: the shaman's aura reaches bowmen and warriors, not pikemen or marines (bits %s)" % str(sh))
	# The shaman's fear: their heavy foot 15 m from him.
	var sim := BattleSim.new()
	sim.setup(_sc([
		Scenarios.unit(0, UT.index_of("native_warriors"), 60, 200, 360, Scenarios.FACE_UP),
		Scenarios.unit(1, UT.HEAVY, 60, 200, 100, Scenarios.FACE_DOWN)], [[_ch("shaman")], []]), 777)
	var h := _ch_unit(sim, 0, UT.CK_FOOT)
	sim.step()
	_put(sim, h, 200, int(sim.u_maxy[1] / M) + 15)
	for t in 9:
		sim.step()
	var m0: int = sim.u_morale[1]
	for t in 200:
		sim.step()
	var drop: int = m0 - sim.u_morale[1]
	_check((sim.u_aura[1] & BattleSim.AU_FEAR) != 0 and drop >= 18 and drop <= 22,
		"west: the shaman frightens the enemy foot 15 m off, 1 morale a second (%d over 20 s)" % drop)
	# The missionary: a wavering native warrior band against a wavering pike block, on the same seeds.
	var gain := {"native_warriors": 0, "w_pikemen": 0}
	for key in gain:
		for sd in 14:
			var pair: Array = []
			for with_bonus in [false, true]:
				var old := {}
				if not with_bonus:
					old = _set_row("missionary", {"parley_bonus": 0})
				var s2 := BattleSim.new()
				s2.setup(_sc([
					Scenarios.unit(0, UT.HEAVY, 100, 200, 330, Scenarios.FACE_UP),
					Scenarios.unit(1, UT.index_of(key), 60, 200, 200, Scenarios.FACE_DOWN)], [[_ch("missionary")], []]), 930 + sd)
				var dip := _ch_unit(s2, 0, UT.CK_DIPLOMAT)
				_put(s2, dip, 235, 190)
				s2.u_morale[1] = 0
				s2.step()
				s2.queue_order(BattleSim.make_parley_order(s2.tick, dip, 1))
				var res := -1
				for t in 400:
					s2.step()
					if s2.stat_parley_ok > 0:
						res = 1
						break
					if s2.stat_parley_fail > 0:
						res = 0
						break
				pair.append(res)
				if not old.is_empty():
					_set_row("missionary", old)
			if pair[0] == 0 and pair[1] == 1:
				gain[key] += 1
			if pair[0] == 1 and pair[1] != 1:
				gain[key] -= 100
	_check(gain["native_warriors"] > 0 and gain["w_pikemen"] == 0,
		"west: the missionary's +25 turns refusals into surrenders of a native band (%d of 14 seeds) and changes no pike block's (%d)" % [gain["native_warriors"], gain["w_pikemen"]])
