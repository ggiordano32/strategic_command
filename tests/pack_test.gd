extends SceneTree
## Content pack plumbing (West pack step 0): CData's pack switch.
##   godot --headless --script res://tests/pack_test.gd
## A Rome campaign has no "pack" key and plays to the same hash before and
## after a switch to another pack and back (every derived cache rebuilt);
## the switch bumps CData.gen and swaps the tables, the grid (CGrid), the
## calendar and the names; use_pack of the active pack is a no-op; unknown
## packs are refused (has_pack, CState.from_json); a state's "pack" key
## hashes as the server's view does (server/internal/server TestStateHashPack).

const CData := preload("res://campaign/cdata.gd")
const CState := preload("res://campaign/cstate.gd")
const CTurn := preload("res://campaign/cturn.gd")
const CGrid := preload("res://campaign/cgrid.gd")
const CRules := preload("res://campaign/crules.gd")
const Dummy := preload("res://tests/data/dummy_pack.gd")
const CFleet := preload("res://campaign/cfleet.gd")

## A Rome AI-only campaign (seed 4242) after 20 turns, all rules as they are.
const ROME_20 := "575e23d5"  # = HEAD 1c04fbe before the pack switch existed

var fails := 0


func _init() -> void:
	_rome_round_trip()
	_refusals()
	_hash_view()
	_west()
	_fleets()
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)


func _check(cond: bool, what: String) -> void:
	if cond:
		print("ok   ", what)
	else:
		fails += 1
		print("FAIL ", what)


func _rome20() -> Dictionary:
	var g := CState.new_campaign("test", 4242, [])
	for t in 20:
		g = CTurn.resolve_turn(g, [])
	return g


func _rome_round_trip() -> void:
	_check(CData.pack == "rome" and CData.region_count() == 36 and CData.faction_count() == 8, "Rome is the default pack")
	var a := _rome20()
	print("     rome 20 turns: %s" % CState.hash_text(a))
	_check(not a.has("pack"), "a Rome state has no \"pack\" key")
	var g0 := CData.gen
	CData.use_pack("rome")
	_check(CData.gen == g0, "use_pack of the active pack is a no-op (gen %d)" % CData.gen)
	var rome_cells := CGrid.count()
	var rome_w := CGrid.width()
	var hops := CRules.land_hops(0, 1)
	# Switch to the test pack: tables, grid, calendar and names follow.
	CData.use_pack_script("dummy", Dummy)
	_check(CData.pack == "dummy" and CData.gen == g0 + 1, "the switch bumps gen")
	_check(CData.region_count() == 2 and CData.faction_count() == 2 and CData.region_index("south") == 1
		and CData.region_index("latium") == -1 and CData.faction_index("suds") == 1, "region / faction lookups rebuilt")
	_check(CData.link(0, 1) == 0 and CData.adjacent(0).size() == 1 and not CData.is_port(0), "adjacency and ports rebuilt")
	_check(CData.date_text(0) == "1650 AD, summer" and CData.date_text(3) == "1651 AD, winter", "an AD calendar counts up")
	_check(CData.name_list(0)[0] == "Alpha" and CData.name_list(1)[0] == "Beta" and CData.name_list(-1)[0] == "Alpha",
		"names: by culture, by faction key, the default")
	_check(CGrid.width() == 4 and CGrid.count() == 8 and CGrid.region(3) == 1 and CGrid.site(1) == 3
		and CGrid.cheb(0, 7) == 3, "the grid follows the pack (CGrid rebuilt)")
	_check(CRules.land_hops(0, 1) == 1, "crules' tables rebuilt")
	_check(CData.sector(0, 1) == 3, "sector() with the pack's LON_PCT")
	# And back: Rome plays exactly as before.
	CData.use_pack("rome")
	_check(CData.pack == "rome" and CData.gen == g0 + 2 and CData.region_count() == 36, "back to Rome")
	_check(CGrid.count() == rome_cells and CGrid.width() == rome_w and CRules.land_hops(0, 1) == hops, "Rome's grid and tables rebuilt")
	_check(CData.date_text(0) == "280 BC, summer", "Rome's calendar")
	var b := _rome20()
	_check(CState.hash_text(b) == CState.hash_text(a) and CState.hash_text(a) == ROME_20,
		"Rome after a switch round trip: the same golden (%s, %s; expected %s)" % [CState.hash_text(a), CState.hash_text(b), ROME_20])
	# A state names its pack: use_state switches (resolve_turn calls it).
	CData.use_pack_script("dummy", Dummy)
	var c := CTurn.resolve_turn(_rome_turn0(), [])
	_check(CData.pack == "rome" and int(c["turn"]) == 1, "resolve_turn switches to the state's pack")


func _rome_turn0() -> Dictionary:
	var g := CState.new_campaign("t0", 7, [])
	return g


func _refusals() -> void:
	for k in ["", "nope", "cenums", "grid_data", "elev_data", "../cdata", "Rome"]:
		_check(not CData.has_pack(k), "has_pack(\"%s\") is false" % k)
	_check(CData.has_pack("rome"), "has_pack(\"rome\")")
	var st := CState.new_campaign("t", 5, [0])
	var txt := CState.to_json(st)
	var bad := st.duplicate(true)
	bad["pack"] = "nope"
	_check(CState.from_json(CState.to_json(bad)).is_empty(), "a state of an unknown pack is refused")
	var explicit := st.duplicate(true)
	explicit["pack"] = "rome"
	var back := CState.from_json(CState.to_json(explicit))
	_check(not back.is_empty() and CData.pack == "rome", "an explicit \"rome\" pack loads")
	_check(CState.hash_text(CState.from_json(txt)) == CState.hash_text(st), "a Rome save round trip keeps its hash")


## The hash of a state with a "pack" key: the server (statemeta.go hashView)
## keeps unknown keys, so these values are pinned in TestStateHashPack too.
func _hash_view() -> void:
	var def := {"format": CState.FORMAT, "humans": [0, 1], "name": "T", "pack": "west",
		"teams": CState.default_teams([0, 1]), "turn": 3, "version": 7}
	var own := def.duplicate(true)
	own["teams"] = [0, 0, 2, 3, 4, 5, 6, 7]
	print("     pack default teams %s, own teams %s" % [CState.hash_text(def), CState.hash_text(own)])
	_check(CState.hash_text(def) == "a9a7a1e4" and CState.hash_text(own) == "a5c588a1",
		"a \"pack\" state hashes as the server's view (%s, %s)" % [CState.hash_text(def), CState.hash_text(own)])


## The West pack (campaign/data/west.gd): it loads, a new West campaign names
## its pack, round-trips JSON with the same hash, plays 5 turns the same
## twice, and switching back restores the Rome golden.
func _west() -> void:
	var g0 := CData.gen
	CData.use_pack("west")
	_check(CData.pack == "west" and CData.region_count() == 49 and CData.faction_count() == 8, "use_pack(\"west\"): 49 regions, 8 factions")
	_check(CData.ERA == "AD" and CData.START_YEAR == 1650 and CData.LON_PCT == 940, "West calendar and projection")
	_check(CGrid.width() == 188 and CGrid.count() == 188 * 118, "West grid 188 x 118")
	var st := CState.new_campaign("w", 99, [], {}, [], "west")
	_check(st.get("pack", "") == "west", "a West campaign has pack \"west\"")
	var h0 := CState.hash_text(st)
	var back := CState.from_json(CState.to_json(st))
	_check(not back.is_empty() and CState.hash_text(back) == h0 and CData.pack == "west", "a West save round trip keeps its hash (%s)" % h0)
	var a := st
	var b := CState.new_campaign("w", 99, [], {}, [], "west")
	for t in 5:
		a = CTurn.resolve_turn(a, [])
		b = CTurn.resolve_turn(b, [])
	_check(CState.hash_text(a) == CState.hash_text(b) and int(a["turn"]) == 5 and a.get("pack", "") == "west",
		"West: 5 turns, deterministic twice (%s)" % CState.hash_text(a))
	CData.use_pack("rome")
	_check(CData.pack == "rome" and CData.gen > g0, "back to Rome after West")
	var r := _rome20()
	_check(CState.hash_text(r) == ROME_20, "Rome golden after a West campaign (%s)" % CState.hash_text(r))


## Fleets (N1, West only): Rome has none; the West start has fleets and
## shipyards and no sea lanes for armies; downwind reaches farther than
## upwind; an army boards, sails and lands; ships are launched; an
## interception is a sea battle, auto-resolved the same every time; a West
## state with troops aboard round-trips JSON with its hash.
func _fleets() -> void:
	CData.use_pack("rome")
	var rs := CState.new_campaign("r", 3, [])
	_check(not CData.ships_on() and CData.CHAINS.size() == 7 and not rs.has("fleets") and not rs.has("next_fleet"),
		"Rome: no ships, seven building chains, no fleet keys")
	CData.use_pack("west")
	var eng := CData.faction_index("england")
	var st := CState.new_campaign("w", 11, [eng], {}, [], "west")
	_check(CData.ships_on() and CData.CHAINS.size() == 8 and str(CData.CHAINS[CData.SHIPYARD]["key"]) == "shipyard",
		"West: ships on, the Shipyard chain")
	_check((st["fleets"] as Array).size() >= 10 and CFleet.fleets_of(st, CData.faction_index("new_spain")).size() == 3,
		"West start: %d fleets (New Spain 3)" % (st["fleets"] as Array).size())
	var pr := CData.region_index("port_royal")
	_check(CState.building(st, pr, CData.SHIPYARD) == 2 and CFleet.dock(pr) >= 0 and CFleet.harbour(pr) >= 0,
		"Port Royal: Shipyard 2, a harbour and a dock")
	_check(CGrid.links(CGrid.port(pr)).is_empty(), "no sea lanes for armies in the West")
	_check(CRules.build_info(st, eng, pr, CData.SHIPYARD).has("level") and str(CRules.build_info(st, CData.faction_index("itza"),
		CData.region_index("tayasal"), CData.SHIPYARD).get("why", "")) != "", "a Shipyard is built only in a port")
	# Wind: from the east; an open-sea fleet reaches farther west than east.
	var open := -1
	for c in CGrid.count():
		if CFleet.is_sea(c) and CFleet.coast_dist(c) >= 3 and CGrid.cy(c) > 10 and CGrid.cx(c) > 60 and CGrid.cx(c) < 120:
			var ok := true
			for dx in range(-30, 31):
				var j := CGrid.at(CGrid.cx(c) + dx, CGrid.cy(c))
				if j < 0 or not CFleet.is_sea(j):
					ok = false
					break
			if ok:
				open = c
				break
	var probe := {"id": 999, "f": eng, "x": CGrid.cx(open), "y": CGrid.cy(open), "ships": [{"t": "frigate", "h": 100, "c": 100}],
		"carry": [], "moved": 0}
	var scratch := st.duplicate(true)
	scratch["fleets"] = [probe]
	var rch := CFleet.reach(scratch, probe, 0)
	var west := 0
	var east := 0
	for dx in range(1, 31):
		if rch[CGrid.at(CGrid.cx(open) - dx, CGrid.cy(open))] == 0:
			west = dx
		if rch[CGrid.at(CGrid.cx(open) + dx, CGrid.cy(open))] == 0:
			east = dx
	_check(open >= 0 and west > east and east > 0, "a frigate runs %d cells west (downwind), beats %d east" % [west, east])
	_check(CFleet.step_cost(6, true) == 8 and CFleet.step_cost(2, true) == 16 and CFleet.step_cost(0, true) == 10
		and CFleet.step_cost(2, false) == 10, "step costs: west 8 (125 %), east 16 (60 %), north 10; rowed 10")
	# Embark at Port Royal, sail and land at Belize (English), launch a ship.
	var fl: Dictionary = CFleet.fleets_of(st, eng)[0]
	var a: Dictionary = CState.armies_of(st, eng)[1]  # the Sevilla army (4 units)
	CState.place(a, CGrid.site(pr))
	var orders: Array = [{"t": "embark", "army": int(a["id"]), "fleet": int(fl["id"])},
		{"t": "ship", "r": pr, "ship": "frigate"}]
	var bz := CData.region_index("belize")
	var dest := CFleet.beach(bz)
	orders.append({"t": "fmove", "fleet": int(fl["id"]), "x": CGrid.cx(dest), "y": CGrid.cy(dest), "persist": 1})
	var pv := CTurn.preview(st, eng, orders)
	_check((pv["errors"] as Array).is_empty() and (pv["fmoves"] as Array).size() == 1, "preview: embark, ship and voyage valid %s" % str(pv["errors"]))
	var ships0 := (fl["ships"] as Array).size()
	var s1 := CTurn.resolve_turn(st, [CTurn.submission(st, eng, orders)])
	var aid := int(a["id"])
	var aboard := not CState.carried_army(s1, aid).is_empty()
	var landed := not CState.army(s1, aid).is_empty() and int(CData.REGIONS[int(CState.army(s1, aid)["r"])]["land"]) == 0
	_check(aboard or landed, "the army boarded (aboard %s, landed %s)" % [aboard, landed])
	var fl1 := CFleet.fleet(s1, int(fl["id"]))
	var built := false
	for e in s1["events"]:
		if str(e["k"]) == "ship_built" and int(e["f"]) == eng:
			built = true
	_check(built, "a frigate launched at Port Royal")
	var js := CState.from_json(CState.to_json(s1))
	_check(not js.is_empty() and CState.hash_text(js) == CState.hash_text(s1), "a West state with fleets round-trips JSON (%s)" % CState.hash_text(s1))
	var g := s1
	for t in 6:
		if landed:
			break
		g = CTurn.resolve_turn(g, [CTurn.submission(g, eng, [])])
		landed = not CState.army(g, aid).is_empty()
	var la := CState.army(g, aid)
	_check(landed and int(CData.REGIONS[int(la["r"])]["land"]) == 0 and CGrid.region(CState.cell(la)) >= 0,
		"the army landed on the mainland (%s) by turn %d" % [CData.REGIONS[int(la.get("r", 0))]["key"] if landed else "-", int(g["turn"])])
	_check(not fl1.is_empty() and (fl1["ships"] as Array).size() >= ships0, "the fleet sailed (%d ships)" % (fl1["ships"] as Array).size())
	# Interception: an English and a Spanish fleet (at war) in open sea; the
	# English sails at the Spaniard: a sea battle, the same twice.
	var sp := CData.faction_index("new_spain")
	var s2 := st.duplicate(true)
	var e1 := {"id": 900, "f": eng, "x": CGrid.cx(open) + 6, "y": CGrid.cy(open), "ships": [{"t": "frigate", "h": 100, "c": 100},
		{"t": "frigate", "h": 100, "c": 100}], "carry": [], "moved": 0}
	var e2 := {"id": 901, "f": sp, "x": CGrid.cx(open) - 6, "y": CGrid.cy(open), "ships": [{"t": "galleon", "h": 100, "c": 100},
		{"t": "sloop", "h": 100, "c": 100}], "carry": [], "moved": 0}
	s2["fleets"] = [e1, e2]
	var s3 := s2.duplicate(true)
	var tc := CFleet.cell(e2)
	CFleet.execute_moves(s2, [[900, tc, eng, 0, -1]])
	CFleet.execute_moves(s3, [[900, tc, eng, 0, -1]])
	var sb := {}
	for e in s2["events"]:
		if str(e["k"]) == "sea_battle":
			sb = e
	_check(not sb.is_empty() and int(sb["af"][0]) == 900 and int(sb["df"][0]) == 901,
		"a voyage into an enemy fleet's zone is a sea battle (won by %s, lost %s)" % ["att" if int(sb.get("won", 1)) == 0 else "def", str(sb.get("lost", []))])
	_check(CState.hash_text(s2) == CState.hash_text(s3), "the sea battle auto-resolves the same twice (%s)" % CState.hash_text(s2))
	# A fleet that loses with troops aboard: they go down with the ships.
	var s4 := st.duplicate(true)
	var w1 := {"id": 910, "f": eng, "x": CGrid.cx(open), "y": CGrid.cy(open), "ships": [{"t": "sloop", "h": 30, "c": 30}],
		"carry": [CState.armies_of(s4, eng)[0].duplicate(true)], "moved": 0}
	(w1["carry"][0] as Dictionary)["units"] = [(w1["carry"][0]["units"] as Array)[0]]
	var w2 := {"id": 911, "f": sp, "x": CGrid.cx(open) + 2, "y": CGrid.cy(open), "ships": [{"t": "galleon", "h": 100, "c": 100},
		{"t": "galleon", "h": 100, "c": 100}], "carry": [], "moved": 0}
	s4["fleets"] = [w1, w2]
	CFleet.resolve(s4, [w2], [w1], CFleet.cell(w1))
	var sunk := 0
	for e in s4["events"]:
		if str(e["k"]) == "army_sunk":
			sunk += 1
	_check(CFleet.fleet(s4, 910).is_empty() == (sunk == 1) and (CFleet.fleet(s4, 910).is_empty() or CFleet.carried_units(CFleet.fleet(s4, 910)) <= CFleet.capacity(CFleet.fleet(s4, 910))),
		"a sunk transport drowns its troops (fleet gone %s, armies sunk %d)" % [CFleet.fleet(s4, 910).is_empty(), sunk])
	CData.use_pack("rome")
