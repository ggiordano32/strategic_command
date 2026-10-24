extends SceneTree
## Poisoned arrows (Caribbean batch 2; docs/design/battle_sim.md "Poisoned arrows (as built)").
## Set pieces, no AI: native bowmen shoot a standing body of native warriors for 30 s, then cease fire.
##   bleed     with poisoned arrows the target keeps losing men after the shooting stops (one man per
##             POISON_PER poisoned every POISON_T, the deaths credited to the bowmen); with plain arrows
##             it loses none once the arrows stop.
##   snapshot  the poisoned counts and clocks survive snapshot / restore mid-bleed; the hash after
##             restore equals the straight run's, and a repeat run is identical.
##   godot --headless --script res://tests/poison_test.gd [-- --only=bleed|snapshot]

const BattleSim := preload("res://sim/battle_sim.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const UT := preload("res://sim/unit_types.gd")
const UP := 768
const DOWN := 256
const STOP := 300    # cease fire at 30 s
const QUIET := 360   # the last arrows have landed by 36 s
const END := 1400    # 140 s: more than four POISON_T after the shooting

var fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func _sc(kind: String) -> Dictionary:
	var arch := Scenarios.unit(0, UT.index_of("native_bowmen"), 40, 150, 200, UP)
	if kind != "":
		arch["ak"] = UT.ammo_index(kind)
	var tgt := Scenarios.unit(1, UT.index_of("native_warriors"), 120, 150, 140, DOWN)
	var orders: Array = [Scenarios.attack(0, 0, 1, 0),
		{"tick": STOP, "type": BattleSim.ORDER_HALT, "unit": 0},
		{"tick": STOP, "type": BattleSim.ORDER_FIRE, "unit": 0, "on": 0}]
	if kind != "":
		orders.append({"tick": 0, "type": BattleSim.ORDER_AMMO, "unit": 0, "on": 1})
	return {"width_m": 300, "height_m": 300, "ai_sides": [], "units": [arch, tgt], "orders": orders}


func _init() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	if only == "" or only == "bleed":
		_bleed()
	if only == "" or only == "snapshot":
		_snapshot()
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	quit(0 if fails == 0 else 1)


func _run(kind: String) -> Dictionary:
	var sim := BattleSim.new()
	sim.setup(_sc(kind), 7)
	var r := {}
	for t in END:
		sim.step()
		if sim.tick == STOP:
			r["stop"] = sim.u_alive[1]
		if sim.tick == QUIET:
			r["quiet"] = sim.u_alive[1]
			r["pq"] = sim.u_poisoned[1]
			r["dead_q"] = sim.stat_poison_dead
	r["end"] = sim.u_alive[1]
	r["poisoned_end"] = sim.u_poisoned[1]
	r["hits"] = sim.stat_poison_hits
	r["dead"] = sim.stat_poison_dead
	r["kills"] = sim.u_kills[0]
	r["poi_on"] = sim.poi_on
	r["hash"] = sim.state_hash()
	r["shots"] = sim.stat_missile_hits
	return r


func _bleed() -> void:
	var k := UT.ammo_index("poison_arrows")
	_check(k == 13, "poison_arrows is AMMO kind 13 (got %d)" % k)
	_check(UT.ammo_stat(k, "dmg") == 67 and UT.ammo_stat(k, "base") == UT.ammo_index("arrows"),
		"poison_arrows: 67 %% damage, riding on arrows")
	var pl := _run("")
	var po := _run("poison_arrows")
	print("plain:  hits %d, alive at stop %d, quiet %d, end %d, poi_on %d" % [pl["shots"], pl["stop"], pl["quiet"], pl["end"], pl["poi_on"]])
	print("poison: hits %d, poisoned men %d (at 36 s %d), alive at stop %d, quiet %d, end %d, dead of poison %d, still poisoned %d, bowmen kills %d" % [
		po["shots"], po["hits"], po["pq"], po["stop"], po["quiet"], po["end"], po["dead"], po["poisoned_end"], po["kills"]])
	_check(int(pl["shots"]) > 20 and int(po["shots"]) > 20, "both runs hit men")
	_check(pl["end"] == pl["quiet"] and pl["poi_on"] == 0, "plain arrows: no losses after the shooting stops, nothing poisoned")
	_check(int(po["hits"]) > 0 and int(po["pq"]) > 0, "poisoned arrows: men poisoned")
	_check(int(po["end"]) < int(po["quiet"]) and int(po["quiet"]) - int(po["end"]) == int(po["dead"]) - int(po["dead_q"]),
		"poisoned arrows: the target loses men after the shooting stops, all of them to poison")
	_check(int(po["dead"]) <= int(po["hits"]), "no more poison deaths than men poisoned")
	var po2 := _run("poison_arrows")
	_check(po2["hash"] == po["hash"] and po2["end"] == po["end"], "repeat run identical (%08x)" % int(po["hash"]))


func _snapshot() -> void:
	var sc := _sc("poison_arrows")
	var a := BattleSim.new()
	a.setup(sc, 7)
	var cut := 600
	for t in cut:
		a.step()
	_check(a.poi_on == 1 and a.u_poisoned[1] > 0, "snapshot: poisoned men at the cut (%d)" % a.u_poisoned[1])
	var blob := a.snapshot()
	var p0 := a.u_poisoned.duplicate()
	var t0 := a.u_poison_t.duplicate()
	for t in 700:
		a.step()
	var h_a := a.state_hash()
	var b := BattleSim.new()
	b.setup(sc, 7)
	_check(b.restore(blob), "snapshot: restore")
	_check(b.u_poisoned == p0 and b.u_poison_t == t0 and b.poi_on == 1, "snapshot: poisoned counts and clocks restored")
	for t in 700:
		b.step()
	_check(b.state_hash() == h_a, "snapshot: same hash after restore (%08x / %08x)" % [b.state_hash(), h_a])
	var c := BattleSim.new()
	c.setup(sc, 7)
	for t in cut + 700:
		c.step()
	_check(c.state_hash() == h_a, "snapshot: repeat run identical")
	print("snapshot: cut at %d (%d poisoned, next death in %d ticks), hash %08x after 700 more ticks on both" % [cut, p0[1], t0[1], h_a])
